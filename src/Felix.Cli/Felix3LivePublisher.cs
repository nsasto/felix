using System.IO.Pipes;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Felix.Cli;

/// <summary>
/// Reads normalized Felix events from the coordinator's private local pipe and
/// forwards them to Cloud only while an authorized run viewer is connected.
/// Live payloads are intentionally held in memory and are never logged.
/// </summary>
internal sealed class Felix3LivePublisher : IAsyncDisposable
{
    private const int MaxPipeLineBytes = 24 * 1024;
    private const int MaxQueuedEvents = 512;
    private const int MaxQueuedBytes = 1024 * 1024;
    internal static readonly TimeSpan InitialReconnectDelay = TimeSpan.FromSeconds(1);
    internal static readonly TimeSpan MaxReconnectDelay = TimeSpan.FromSeconds(30);
    private readonly Queue<string> _queue = new();
    private readonly object _queueLock = new();
    private readonly SemaphoreSlim _queueSignal = new(0);
    private readonly string? _configuredApiKey;
    private int _queuedBytes;
    private long _droppedEvents;
    private bool _pendingGap;
    private CancellationTokenSource? _socketCancellation;
    private Task? _socketTask;
    private string? _apiKey;
    private string? _lastConnectionState;
    private Uri? _socketUri;
    private bool _includeAssistantText;
    private volatile bool _viewerActive;
    private bool _viewerStateKnown;

    internal Felix3LivePublisher(string? apiKey = null) => _configuredApiKey = apiKey;

    internal bool IsConfigured => _socketUri is not null;
    internal bool ViewerActive => _viewerActive;
    internal event Action<string>? ConnectionStateChanged;
    internal event Action<bool>? ViewerStateChanged;
    internal long DroppedEvents => Interlocked.Read(ref _droppedEvents);
    internal int QueuedByteCount
    {
        get { lock (_queueLock) return _queuedBytes; }
    }
    internal int QueuedEventCount
    {
        get { lock (_queueLock) return _queue.Count; }
    }

    internal async Task ReadPipeAsync(Stream pipe, CancellationToken cancellationToken)
    {
        using var reader = new StreamReader(pipe, new UTF8Encoding(false), false, 4096, leaveOpen: true);
        while (!cancellationToken.IsCancellationRequested)
        {
            string? line;
            try
            {
                line = await reader.ReadLineAsync(cancellationToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            if (line is null)
                break;
            if (Encoding.UTF8.GetByteCount(line) > MaxPipeLineBytes)
                continue;

            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (!root.TryGetProperty("type", out var typeElement))
                    continue;

                switch (typeElement.GetString())
                {
                    case "configure":
                        await ConfigureAsync(root);
                        break;
                    case "close":
                        await CloseRunAsync();
                        break;
                    case "event":
                        if (root.TryGetProperty("event", out var liveEvent))
                            TryQueue(liveEvent);
                        break;
                }
            }
            catch (JsonException)
            {
                // The pipe is an optional side channel; malformed data must not
                // affect local run execution or expose provider payloads.
            }
            catch (Exception ex) when (ex is InvalidOperationException or FormatException or ArgumentException)
            {
                // Invalid optional live configuration must never fail a run.
            }
        }
    }

    private async Task ConfigureAsync(JsonElement root)
    {
        if (!root.TryGetProperty("enabled", out var enabled) || !enabled.GetBoolean())
            return;
        if (!root.TryGetProperty("base_url", out var baseUrl) ||
            !root.TryGetProperty("cloud_run_id", out var runId))
            return;
        if (string.IsNullOrWhiteSpace(_configuredApiKey))
            return;

        await CloseRunAsync();
        if (!Uri.TryCreate(baseUrl.GetString(), UriKind.Absolute, out var endpoint) ||
            endpoint.Scheme is not ("http" or "https"))
            return;
        _includeAssistantText = root.TryGetProperty("include_text", out var includeText) &&
                                includeText.ValueKind == JsonValueKind.True;
        var builder = new UriBuilder(endpoint)
        {
            Scheme = endpoint.Scheme == Uri.UriSchemeHttps ? "wss" : "ws",
            Port = endpoint.IsDefaultPort ? -1 : endpoint.Port,
            Path = $"/api/runs/{Uri.EscapeDataString(runId.GetString()!)}/live",
            Query = string.Empty,
            Fragment = string.Empty
        };
        _apiKey = _configuredApiKey;
        _socketUri = builder.Uri;
        _socketCancellation = new CancellationTokenSource();
        _viewerStateKnown = false;
        _socketTask = RunSocketAsync(_socketCancellation.Token);
    }

    private async Task CloseRunAsync()
    {
        SetViewerActive(false);
        _socketCancellation?.Cancel();
        if (_socketTask is not null)
        {
            try { await _socketTask; } catch { }
        }
        _socketCancellation?.Dispose();
        _socketCancellation = null;
        _socketTask = null;
        _socketUri = null;
        _includeAssistantText = false;
        _apiKey = null;
        _lastConnectionState = null;
        ClearQueue();
    }

    internal void TryQueue(JsonElement liveEvent)
    {
        if (!_viewerActive)
            return;

        var serialized = liveEvent.GetRawText();
        var bytes = Encoding.UTF8.GetByteCount(serialized);
        if (bytes > 16 * 1024)
        {
            Interlocked.Increment(ref _droppedEvents);
            lock (_queueLock) _pendingGap = true;
            return;
        }

        var isText = liveEvent.TryGetProperty("kind", out var kind) &&
                     kind.GetString() == "assistant.delta";
        if (isText && !_includeAssistantText)
            return;
        lock (_queueLock)
        {
            if (!_viewerActive)
                return;
            while (_queue.Count >= MaxQueuedEvents || _queuedBytes + bytes + (_pendingGap ? 16 : 0) > MaxQueuedBytes)
            {
                if (isText || !DropOldestText())
                {
                    Interlocked.Increment(ref _droppedEvents);
                    _pendingGap = true;
                    return;
                }
            }

            if (_pendingGap)
            {
                try
                {
                    var marked = JsonNode.Parse(serialized)?.AsObject();
                    if (marked is not null)
                    {
                        marked["gap"] = true;
                        serialized = marked.ToJsonString();
                        bytes = Encoding.UTF8.GetByteCount(serialized);
                    }
                }
                catch (JsonException) { }
                _pendingGap = false;
            }
            _queue.Enqueue(serialized);
            _queuedBytes += bytes;
            _queueSignal.Release();
        }
    }

    private bool DropOldestText()
    {
        if (_queue.Count == 0)
            return false;
        var items = _queue.ToArray();
        var textIndex = Array.FindIndex(items, IsAssistantDelta);
        if (textIndex < 0)
            return false;
        var retained = new Queue<string>();
        for (var i = 0; i < items.Length; i++)
        {
            if (i == textIndex)
            {
                _queuedBytes -= Encoding.UTF8.GetByteCount(items[i]);
                Interlocked.Increment(ref _droppedEvents);
                _pendingGap = true;
                _queueSignal.Wait(0);
                continue;
            }
            retained.Enqueue(items[i]);
        }
        _queue.Clear();
        foreach (var item in retained)
            _queue.Enqueue(item);
        return true;
    }

    private static bool IsAssistantDelta(string value)
    {
        try
        {
            using var document = JsonDocument.Parse(value);
            return document.RootElement.TryGetProperty("kind", out var kind) &&
                   kind.GetString() == "assistant.delta";
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private async Task RunSocketAsync(CancellationToken cancellationToken)
    {
        var reconnectDelay = InitialReconnectDelay;
        while (!cancellationToken.IsCancellationRequested && _socketUri is not null)
        {
            using var socket = new ClientWebSocket();
            DateTimeOffset? connectedAt = null;
            socket.Options.SetRequestHeader("Authorization", $"Bearer {_apiKey}");
            try
            {
                await socket.ConnectAsync(_socketUri, cancellationToken);
                connectedAt = DateTimeOffset.UtcNow;
                ReportConnectionState("connected");
                using var sessionCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                var receive = ReceiveLoopAsync(socket, sessionCancellation.Token);
                var send = SendLoopAsync(socket, sessionCancellation.Token);
                await Task.WhenAny(receive, send);
                sessionCancellation.Cancel();
                try { await Task.WhenAll(receive, send); } catch { }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception)
            {
                // No event payload or exception text is logged. Reconnect is
                // best effort and never affects the Felix workflow.
            }

            if (!cancellationToken.IsCancellationRequested)
                ReportConnectionState(connectedAt.HasValue ? "disconnected" : "unavailable");

            SetViewerActive(false);
            ClearQueue();
            var stableSession = connectedAt.HasValue && DateTimeOffset.UtcNow - connectedAt.Value >= MaxReconnectDelay;
            var delayBase = stableSession ? InitialReconnectDelay : reconnectDelay;
            var jitterFactor = 0.8 + (Random.Shared.NextDouble() * 0.4);
            var delay = GetReconnectWaitDelay(delayBase, jitterFactor);
            try { await Task.Delay(delay, cancellationToken); }
            catch (OperationCanceledException) { break; }

            reconnectDelay = GetNextReconnectDelay(delayBase, stableSession);
        }
    }

    private void ReportConnectionState(string state)
    {
        if (_lastConnectionState == state)
            return;
        _lastConnectionState = state;
        try { ConnectionStateChanged?.Invoke(state); }
        catch { /* Diagnostics must never affect the local run. */ }
    }

    internal static TimeSpan GetNextReconnectDelay(TimeSpan currentDelay, bool stableSession) =>
        stableSession
            ? InitialReconnectDelay
            : TimeSpan.FromTicks(Math.Min(currentDelay.Ticks * 2, MaxReconnectDelay.Ticks));

    internal static TimeSpan GetReconnectWaitDelay(TimeSpan delay, double jitterFactor) =>
        TimeSpan.FromTicks(Math.Min(
            (long)(delay.Ticks * Math.Clamp(jitterFactor, 0.8, 1.2)),
            MaxReconnectDelay.Ticks));

    private async Task ReceiveLoopAsync(ClientWebSocket socket, CancellationToken cancellationToken)
    {
        const int maxControlMessageBytes = 4096;
        var buffer = new byte[1024];
        while (!cancellationToken.IsCancellationRequested && socket.State == WebSocketState.Open)
        {
            using var message = new MemoryStream();
            var messageType = WebSocketMessageType.Text;
            var oversized = false;
            WebSocketReceiveResult result;
            do
            {
                result = await socket.ReceiveAsync(buffer, cancellationToken);
                if (result.MessageType == WebSocketMessageType.Close)
                    return;
                if (message.Position == 0)
                    messageType = result.MessageType;

                if (messageType == WebSocketMessageType.Text && !oversized)
                {
                    if (message.Length + result.Count > maxControlMessageBytes)
                        oversized = true;
                    else
                        message.Write(buffer, 0, result.Count);
                }
            } while (!result.EndOfMessage);

            // Control frames are tiny. Drain and discard oversized or binary
            // messages instead of allocating unbounded memory or reconnecting.
            if (messageType != WebSocketMessageType.Text || oversized)
                continue;

            try
            {
                using var document = JsonDocument.Parse(message.ToArray());
                var root = document.RootElement;
                if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("type", out var type) &&
                    type.ValueKind == JsonValueKind.String)
                {
                    if ((type.GetString() == "connected" || type.GetString() == "viewer_active") &&
                        root.TryGetProperty("viewer_active", out var active) &&
                        active.ValueKind is JsonValueKind.True or JsonValueKind.False)
                        SetViewerActive(active.GetBoolean());
                    else if (type.GetString() == "viewer_active" &&
                             root.TryGetProperty("active", out var state) &&
                             state.ValueKind is JsonValueKind.True or JsonValueKind.False)
                        SetViewerActive(state.GetBoolean());
                }
            }
            catch (JsonException) { }
        }
    }

    private async Task SendLoopAsync(ClientWebSocket socket, CancellationToken cancellationToken)
    {
        var heartbeat = DateTimeOffset.UtcNow;
        while (!cancellationToken.IsCancellationRequested && socket.State == WebSocketState.Open)
        {
            if (_viewerActive && TryDequeue(out var eventJson))
            {
                eventJson = await CoalesceAssistantDeltasAsync(eventJson, cancellationToken);
                var payload = Encoding.UTF8.GetBytes($"{{\"type\":\"live_event\",\"event\":{eventJson}}}");
                await socket.SendAsync(payload, WebSocketMessageType.Text, true, cancellationToken);
                continue;
            }

            if (DateTimeOffset.UtcNow - heartbeat >= TimeSpan.FromSeconds(10))
            {
                await socket.SendAsync(
                    Encoding.UTF8.GetBytes("{\"type\":\"ping\"}"),
                    WebSocketMessageType.Text,
                    true,
                    cancellationToken);
                heartbeat = DateTimeOffset.UtcNow;
            }
            var untilHeartbeat = TimeSpan.FromSeconds(10) - (DateTimeOffset.UtcNow - heartbeat);
            if (untilHeartbeat > TimeSpan.Zero)
                await _queueSignal.WaitAsync(untilHeartbeat, cancellationToken);
        }
    }

    internal bool TryDequeue(out string eventJson)
    {
        lock (_queueLock)
        {
            if (_queue.Count == 0)
            {
                eventJson = string.Empty;
                return false;
            }
            eventJson = _queue.Dequeue();
            _queuedBytes -= Encoding.UTF8.GetByteCount(eventJson);
            _queueSignal.Wait(0);
            return true;
        }
    }

    private async Task<string> CoalesceAssistantDeltasAsync(
        string firstEvent,
        CancellationToken cancellationToken)
    {
        JsonObject? combined;
        try { combined = JsonNode.Parse(firstEvent)?.AsObject(); }
        catch (JsonException) { return firstEvent; }
        if (combined is null || combined["kind"]?.GetValue<string>() != "assistant.delta")
            return firstEvent;

        var text = combined["text"]?.GetValue<string>() ?? string.Empty;
        var phase = combined["phase"]?.GetValue<string>();
        var harness = combined["harness"]?.GetValue<string>();
        var deadline = DateTimeOffset.UtcNow + TimeSpan.FromMilliseconds(180);
        while (text.Length < 3500 && DateTimeOffset.UtcNow < deadline)
        {
            string? next = null;
            var flush = false;
            lock (_queueLock)
            {
                if (_queue.Count > 0)
                {
                    var candidate = _queue.Peek();
                    try
                    {
                        using var document = JsonDocument.Parse(candidate);
                        var root = document.RootElement;
                        var sameDelta = root.GetProperty("kind").GetString() == "assistant.delta" &&
                                        !(root.TryGetProperty("gap", out var gap) && gap.ValueKind == JsonValueKind.True) &&
                                        NullableString(root, "phase") == phase &&
                                        NullableString(root, "harness") == harness;
                        var candidateText = sameDelta ? root.GetProperty("text").GetString() ?? string.Empty : string.Empty;
                        if (!sameDelta || text.Length + candidateText.Length > 3500)
                            flush = true;
                        else
                        {
                            next = _queue.Dequeue();
                            _queuedBytes -= Encoding.UTF8.GetByteCount(next);
                            _queueSignal.Wait(0);
                        }
                    }
                    catch (JsonException) { }
                }
            }

            if (flush)
                break;
            if (next is null)
            {
                var remaining = deadline - DateTimeOffset.UtcNow;
                if (remaining > TimeSpan.Zero)
                    await _queueSignal.WaitAsync(remaining, cancellationToken);
                continue;
            }

            using var nextDocument = JsonDocument.Parse(next);
            var nextRoot = nextDocument.RootElement;
            text += nextRoot.GetProperty("text").GetString();
            combined["seq"] = nextRoot.GetProperty("seq").GetInt64();
            combined["timestamp"] = nextRoot.GetProperty("timestamp").GetString();
        }
        combined["text"] = text;
        return combined.ToJsonString();
    }

    private static string? NullableString(JsonElement value, string property) =>
        value.TryGetProperty(property, out var element) && element.ValueKind != JsonValueKind.Null
            ? element.GetString()
            : null;

    private void ClearQueue()
    {
        lock (_queueLock)
        {
            _queue.Clear();
            _queuedBytes = 0;
            _pendingGap = false;
            while (_queueSignal.Wait(0)) { }
        }
    }

    internal void SetViewerActive(bool active)
    {
        if (_viewerStateKnown && _viewerActive == active)
            return;

        _viewerActive = active;
        _viewerStateKnown = true;
        if (!active)
            ClearQueue();
        try { ViewerStateChanged?.Invoke(active); }
        catch { /* Diagnostics must never affect the local run. */ }
    }

    public async ValueTask DisposeAsync()
    {
        await CloseRunAsync();
        _queueSignal.Dispose();
    }
}
