using System.Text.Json;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.IO.Pipes;
using System.Text;
using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public sealed class Felix3LivePublisherTests
{
    [Fact]
    public async Task PublisherSendsOnlyAfterFakeCloudReportsViewerActive()
    {
        using var portReservation = new TcpListener(IPAddress.Loopback, 0);
        portReservation.Start();
        var port = ((IPEndPoint)portReservation.LocalEndpoint).Port;
        portReservation.Stop();

        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();
        await using var publisher = new Felix3LivePublisher("test-only-key");

        var acceptTask = listener.GetContextAsync();
        var configure = JsonSerializer.Serialize(new
        {
            type = "configure",
            enabled = true,
            include_text = true,
            base_url = $"http://127.0.0.1:{port}",
            cloud_run_id = "cloud-run-1"
        });
        await publisher.ReadPipeAsync(new MemoryStream(Encoding.UTF8.GetBytes(configure + "\n")), CancellationToken.None);

        var context = await acceptTask.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal("Bearer test-only-key", context.Request.Headers["Authorization"]);
        var accepted = await context.AcceptWebSocketAsync(null);
        using var cloudSocket = accepted.WebSocket;

        var fragmentedControl = Encoding.UTF8.GetBytes("{\"type\":\"connected\",\"viewer_active\":false}");
        var splitAt = fragmentedControl.Length / 2;
        await cloudSocket.SendAsync(
            fragmentedControl.AsMemory(0, splitAt),
            WebSocketMessageType.Text,
            endOfMessage: false,
            CancellationToken.None);
        await cloudSocket.SendAsync(
            fragmentedControl.AsMemory(splitAt),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await publisher.ReadPipeAsync(EventPipe("assistant.delta", "must stay queued nowhere"), CancellationToken.None);
        Assert.Equal(0, publisher.QueuedEventCount);

        await cloudSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"viewer_active\",\"active\":true}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, true);
        await publisher.ReadPipeAsync(EventPipe("assistant.delta", "surfaced output"), CancellationToken.None);

        var received = new byte[4096];
        var message = await cloudSocket.ReceiveAsync(received, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(5));
        var json = Encoding.UTF8.GetString(received, 0, message.Count);
        Assert.Contains("\"type\":\"live_event\"", json);
        Assert.Contains("surfaced output", json);
        Assert.DoesNotContain("must stay queued nowhere", json);

        await cloudSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"viewer_active\",\"active\":false}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, false);
        await publisher.ReadPipeAsync(EventPipe("assistant.delta", "after viewer closed"), CancellationToken.None);
        Assert.Equal(0, publisher.QueuedEventCount);
        using var detachedViewerTimeout = new CancellationTokenSource(TimeSpan.FromMilliseconds(350));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await cloudSocket.ReceiveAsync(new byte[4096], detachedViewerTimeout.Token));
    }

    [Fact]
    public async Task QueueRequiresViewerAndClearsWhenViewerLeaves()
    {
        await using var publisher = new Felix3LivePublisher("test-only-key");
        using var phaseEvent = JsonDocument.Parse("""{"kind":"phase.started","phase":"building","harness":"opencode"}""");

        publisher.TryQueue(phaseEvent.RootElement);
        Assert.Equal(0, publisher.QueuedEventCount);

        publisher.SetViewerActive(true);
        publisher.TryQueue(phaseEvent.RootElement);
        Assert.Equal(1, publisher.QueuedEventCount);

        publisher.SetViewerActive(false);
        Assert.Equal(0, publisher.QueuedEventCount);
        Assert.Equal(0, publisher.DroppedEvents);
    }

    [Fact]
    public async Task ViewerStateDiagnosticsReportOnlyPresenceTransitions()
    {
        await using var publisher = new Felix3LivePublisher("test-only-key");
        var transitions = new ConcurrentQueue<bool>();
        publisher.ViewerStateChanged += transitions.Enqueue;

        publisher.SetViewerActive(false);
        publisher.SetViewerActive(true);
        publisher.SetViewerActive(true);
        publisher.SetViewerActive(false);
        publisher.SetViewerActive(false);

        Assert.Equal(new[] { false, true, false }, transitions.ToArray());
    }

    [Fact]
    public async Task AssistantTextIsDiscardedWhenTextStreamingIsDisabled()
    {
        await using var publisher = new Felix3LivePublisher("test-only-key");
        publisher.SetViewerActive(true);
        using var textEvent = JsonDocument.Parse("""{"kind":"assistant.delta","text":"private surfaced text"}""");

        publisher.TryQueue(textEvent.RootElement);

        Assert.Equal(0, publisher.QueuedEventCount);
        Assert.Equal(0, publisher.DroppedEvents);
    }

    [Fact]
    public async Task PublisherCoalescesAdjacentAssistantDeltasIntoOneWebSocketMessage()
    {
        using var portReservation = new TcpListener(IPAddress.Loopback, 0);
        portReservation.Start();
        var port = ((IPEndPoint)portReservation.LocalEndpoint).Port;
        portReservation.Stop();

        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();
        await using var publisher = new Felix3LivePublisher("test-only-key");
        var acceptTask = listener.GetContextAsync();
        var configure = JsonSerializer.Serialize(new
        {
            type = "configure",
            enabled = true,
            include_text = true,
            base_url = $"http://127.0.0.1:{port}",
            cloud_run_id = "cloud-run-1"
        });
        await publisher.ReadPipeAsync(new MemoryStream(Encoding.UTF8.GetBytes(configure + "\n")), CancellationToken.None);

        var context = await acceptTask.WaitAsync(TimeSpan.FromSeconds(5));
        var accepted = await context.AcceptWebSocketAsync(null);
        using var cloudSocket = accepted.WebSocket;
        await cloudSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"connected\",\"viewer_active\":true}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, true);

        var events = EventPipe("assistant.delta", "one", 1).ToArray()
            .Concat(EventPipe("assistant.delta", " two", 2).ToArray())
            .ToArray();
        await publisher.ReadPipeAsync(new MemoryStream(events), CancellationToken.None);

        var received = new byte[4096];
        var message = await cloudSocket.ReceiveAsync(received, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(5));
        var json = Encoding.UTF8.GetString(received, 0, message.Count);
        using var document = JsonDocument.Parse(json);
        var liveEvent = document.RootElement.GetProperty("event");
        Assert.Equal("one two", liveEvent.GetProperty("text").GetString());
        Assert.Equal(2, liveEvent.GetProperty("seq").GetInt64());
    }

    [Fact]
    public async Task PublisherReconnectsWithoutReplayingEarlierOutput()
    {
        using var portReservation = new TcpListener(IPAddress.Loopback, 0);
        portReservation.Start();
        var port = ((IPEndPoint)portReservation.LocalEndpoint).Port;
        portReservation.Stop();

        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();
        await using var publisher = new Felix3LivePublisher("test-only-key");
        var acceptTask = listener.GetContextAsync();
        var configure = JsonSerializer.Serialize(new
        {
            type = "configure",
            enabled = true,
            include_text = true,
            base_url = $"http://127.0.0.1:{port}",
            cloud_run_id = "cloud-run-1"
        });
        await publisher.ReadPipeAsync(new MemoryStream(Encoding.UTF8.GetBytes(configure + "\n")), CancellationToken.None);

        var firstContext = await acceptTask.WaitAsync(TimeSpan.FromSeconds(5));
        var firstAccepted = await firstContext.AcceptWebSocketAsync(null);
        using var firstCloudSocket = firstAccepted.WebSocket;
        await firstCloudSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"connected\",\"viewer_active\":true}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, true);
        await publisher.ReadPipeAsync(EventPipe("assistant.delta", "only in first live window"), CancellationToken.None);
        var received = new byte[4096];
        var firstMessage = await firstCloudSocket.ReceiveAsync(received, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Contains("only in first live window", Encoding.UTF8.GetString(received, 0, firstMessage.Count));

        var reconnectTask = listener.GetContextAsync();
        await firstCloudSocket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "test disconnect", CancellationToken.None);
        var secondContext = await reconnectTask.WaitAsync(TimeSpan.FromSeconds(6));
        var secondAccepted = await secondContext.AcceptWebSocketAsync(null);
        using var secondCloudSocket = secondAccepted.WebSocket;
        await secondCloudSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"connected\",\"viewer_active\":false}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, false);
        await secondCloudSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"viewer_active\",\"active\":true}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, true);

        using var noReplayTimeout = new CancellationTokenSource(TimeSpan.FromMilliseconds(350));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
            await secondCloudSocket.ReceiveAsync(received, noReplayTimeout.Token));
        Assert.Equal(0, publisher.QueuedEventCount);
    }

    [Fact]
    public async Task PublisherReconnectsAfterCloudSocketAbortsDuringRun()
    {
        using var portReservation = new TcpListener(IPAddress.Loopback, 0);
        portReservation.Start();
        var port = ((IPEndPoint)portReservation.LocalEndpoint).Port;
        portReservation.Stop();

        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();
        await using var publisher = new Felix3LivePublisher("test-only-key");
        var connectionStates = new ConcurrentQueue<string>();
        publisher.ConnectionStateChanged += connectionStates.Enqueue;
        var firstAccept = listener.GetContextAsync();
        var configure = JsonSerializer.Serialize(new
        {
            type = "configure",
            enabled = true,
            include_text = true,
            base_url = $"http://127.0.0.1:{port}",
            cloud_run_id = "cloud-run-1"
        });
        await publisher.ReadPipeAsync(new MemoryStream(Encoding.UTF8.GetBytes(configure + "\n")), CancellationToken.None);

        var firstContext = await firstAccept.WaitAsync(TimeSpan.FromSeconds(5));
        var firstAccepted = await firstContext.AcceptWebSocketAsync(null);
        using var firstCloudSocket = firstAccepted.WebSocket;
        await firstCloudSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"connected\",\"viewer_active\":true}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, true);

        var reconnectAccept = listener.GetContextAsync();
        firstCloudSocket.Abort();
        await WaitForViewerState(publisher, false);

        var disconnectedHandoff = System.Diagnostics.Stopwatch.StartNew();
        await publisher.ReadPipeAsync(
            EventPipe("phase.completed", "local phase completed during Cloud disconnect"),
            CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(1));
        disconnectedHandoff.Stop();
        Assert.True(disconnectedHandoff.Elapsed < TimeSpan.FromSeconds(1));
        Assert.Equal(0, publisher.QueuedEventCount);

        var reconnectContext = await reconnectAccept.WaitAsync(TimeSpan.FromSeconds(8));
        var reconnectAccepted = await reconnectContext.AcceptWebSocketAsync(null);
        using var reconnectSocket = reconnectAccepted.WebSocket;
        await reconnectSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"connected\",\"viewer_active\":true}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, true);

        var received = new byte[4096];
        var pendingMessage = reconnectSocket.ReceiveAsync(received, CancellationToken.None);
        await Task.Delay(350);
        Assert.False(pendingMessage.IsCompleted, "the phase emitted during the disconnect must not be replayed");

        await publisher.ReadPipeAsync(EventPipe("tool.started", "local run continued after disconnect"), CancellationToken.None);
        var message = await pendingMessage.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Contains("local run continued after disconnect", Encoding.UTF8.GetString(received, 0, message.Count));
        Assert.Equal(new[] { "connected", "disconnected", "connected" }, connectionStates.ToArray());
    }

    [Fact]
    public void ReconnectDelayStartsQuicklyAndCapsAfterRepeatedFailures()
    {
        var delays = new List<int>();
        var delay = Felix3LivePublisher.InitialReconnectDelay;
        for (var i = 0; i < 7; i++)
        {
            delays.Add((int)delay.TotalSeconds);
            delay = Felix3LivePublisher.GetNextReconnectDelay(delay, stableSession: false);
        }

        Assert.Equal(new[] { 1, 2, 4, 8, 16, 30, 30 }, delays);
        Assert.Equal(TimeSpan.FromSeconds(1), Felix3LivePublisher.GetNextReconnectDelay(delay, stableSession: true));
        Assert.Equal(
            TimeSpan.FromSeconds(30),
            Felix3LivePublisher.GetReconnectWaitDelay(TimeSpan.FromSeconds(30), jitterFactor: 1.2));
        Assert.Equal(
            TimeSpan.FromSeconds(24),
            Felix3LivePublisher.GetReconnectWaitDelay(TimeSpan.FromSeconds(30), jitterFactor: 0.8));
    }

    [Fact]
    public async Task SlowViewerDoesNotBlockLocalEventHandoff()
    {
        using var portReservation = new TcpListener(IPAddress.Loopback, 0);
        portReservation.Start();
        var port = ((IPEndPoint)portReservation.LocalEndpoint).Port;
        portReservation.Stop();

        using var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        listener.Start();
        await using var publisher = new Felix3LivePublisher("test-only-key");
        var acceptTask = listener.GetContextAsync();
        var configure = JsonSerializer.Serialize(new
        {
            type = "configure",
            enabled = true,
            include_text = true,
            base_url = $"http://127.0.0.1:{port}",
            cloud_run_id = "cloud-run-1"
        });
        await publisher.ReadPipeAsync(new MemoryStream(Encoding.UTF8.GetBytes(configure + "\n")), CancellationToken.None);

        var context = await acceptTask.WaitAsync(TimeSpan.FromSeconds(5));
        var accepted = await context.AcceptWebSocketAsync(null);
        using var cloudSocket = accepted.WebSocket;
        await cloudSocket.SendAsync(
            Encoding.UTF8.GetBytes("{\"type\":\"connected\",\"viewer_active\":true}"),
            WebSocketMessageType.Text,
            true,
            CancellationToken.None);
        await WaitForViewerState(publisher, true);

        // Keep the socket open but never receive. The publisher may stall on
        // its own send loop once TCP applies backpressure; local pipe handoff
        // must still finish using the bounded in-memory queue.
        var slowBurst = new MemoryStream();
        var longToolName = new string('x', 12 * 1024);
        for (var i = 0; i < 512; i++)
        {
            var line = JsonSerializer.Serialize(new
            {
                type = "event",
                @event = new
                {
                    kind = "tool.started",
                    tool = longToolName,
                    status = "started",
                    phase = "building",
                    harness = "opencode",
                    run_id = "local-run",
                    seq = i + 1,
                    timestamp = DateTimeOffset.UtcNow
                }
            });
            var bytes = Encoding.UTF8.GetBytes(line + "\n");
            slowBurst.Write(bytes);
        }

        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        await publisher.ReadPipeAsync(new MemoryStream(slowBurst.ToArray()), CancellationToken.None)
            .WaitAsync(TimeSpan.FromSeconds(5));
        stopwatch.Stop();

        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(5));
        Assert.InRange(publisher.QueuedEventCount, 0, 512);
    }

    [Fact]
    public async Task QueueHasStrictCountBoundAndAccountsForDroppedEvents()
    {
        await using var publisher = new Felix3LivePublisher("test-only-key");
        publisher.SetViewerActive(true);
        using var eventDocument = JsonDocument.Parse("""{"kind":"tool.started","tool":"shell","status":"started"}""");

        for (var i = 0; i < 513; i++)
            publisher.TryQueue(eventDocument.RootElement);

        Assert.Equal(512, publisher.QueuedEventCount);
        Assert.Equal(1, publisher.DroppedEvents);
    }

    [Fact]
    public async Task QueueMarksNextForwardedEventAfterDroppingAnEvent()
    {
        await using var publisher = new Felix3LivePublisher("test-only-key");
        publisher.SetViewerActive(true);
        using var eventDocument = JsonDocument.Parse("""{"kind":"tool.started","tool":"shell","status":"started"}""");

        for (var i = 0; i < 513; i++)
            publisher.TryQueue(eventDocument.RootElement);

        while (publisher.TryDequeue(out _)) { }
        using var nextDocument = JsonDocument.Parse("""{"kind":"phase.started","phase":"building"}""");
        publisher.TryQueue(nextDocument.RootElement);

        Assert.True(publisher.TryDequeue(out var forwarded));
        using var forwardedDocument = JsonDocument.Parse(forwarded);
        Assert.True(forwardedDocument.RootElement.GetProperty("gap").GetBoolean());
    }

    [Fact]
    public async Task QueueHasStrictByteBoundAndAccountsForDroppedEvents()
    {
        await using var publisher = new Felix3LivePublisher("test-only-key");
        publisher.SetViewerActive(true);
        using var eventDocument = JsonDocument.Parse(
            JsonSerializer.Serialize(new { kind = "tool.started", tool = new string('x', 12 * 1024), status = "started" }));

        for (var i = 0; i < 200; i++)
            publisher.TryQueue(eventDocument.RootElement);

        Assert.InRange(publisher.QueuedByteCount, 1, 1024 * 1024);
        Assert.InRange(publisher.QueuedEventCount, 1, 512);
        Assert.True(publisher.DroppedEvents > 0);
    }

    [Fact]
    public async Task NamedPipeReaderStopsCleanlyWhenCoordinatorExits()
    {
        var pipeName = $"felix3-live-test-{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous);
        await using var publisher = new Felix3LivePublisher("test-only-key");
        using var cancellation = new CancellationTokenSource();
        await using var client = new NamedPipeClientStream(
            ".",
            pipeName,
            PipeDirection.Out,
            PipeOptions.Asynchronous);
        await client.ConnectAsync(5000);
        await server.WaitForConnectionAsync();
        var readTask = publisher.ReadPipeAsync(server, cancellation.Token);

        cancellation.Cancel();

        await readTask.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(0, publisher.QueuedEventCount);
    }

    [Fact]
    public async Task CoordinatorConfigureMessageCrossesNamedPipeWithoutCloudAvailability()
    {
        var pipeName = $"felix3-live-config-test-{Guid.NewGuid():N}";
        await using var server = new NamedPipeServerStream(
            pipeName,
            PipeDirection.In,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous);
        await using var client = new NamedPipeClientStream(
            ".",
            pipeName,
            PipeDirection.Out,
            PipeOptions.Asynchronous);
        await using var publisher = new Felix3LivePublisher("test-only-key");

        var acceptTask = server.WaitForConnectionAsync();
        await client.ConnectAsync(5000);
        await acceptTask.WaitAsync(TimeSpan.FromSeconds(5));
        var readTask = publisher.ReadPipeAsync(server, CancellationToken.None);
        var writer = new StreamWriter(client, new UTF8Encoding(false), 1024, leaveOpen: true)
        {
            AutoFlush = true
        };
        await writer.WriteLineAsync(JsonSerializer.Serialize(new
        {
            type = "configure",
            enabled = true,
            include_text = true,
            base_url = "http://127.0.0.1:1",
            cloud_run_id = "pipe-contract-run"
        }));

        await WaitForConfigured(publisher);
        Assert.True(publisher.IsConfigured);

        await writer.FlushAsync();
        writer.Dispose();
        client.Dispose();
        await readTask.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Fact]
    public async Task UnavailableCloudSocketDoesNotBlockLocalEventHandoff()
    {
        using var portReservation = new TcpListener(IPAddress.Loopback, 0);
        portReservation.Start();
        var port = ((IPEndPoint)portReservation.LocalEndpoint).Port;
        portReservation.Stop();

        await using var publisher = new Felix3LivePublisher("test-only-key");
        var unavailable = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        publisher.ConnectionStateChanged += state => unavailable.TrySetResult(state);
        var configure = JsonSerializer.Serialize(new
        {
            type = "configure",
            enabled = true,
            include_text = true,
            base_url = $"http://127.0.0.1:{port}",
            cloud_run_id = "cloud-run-1"
        });
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();
        await publisher.ReadPipeAsync(new MemoryStream(Encoding.UTF8.GetBytes(configure + "\n")), CancellationToken.None);
        await publisher.ReadPipeAsync(EventPipe("assistant.delta", "local output remains available"), CancellationToken.None);
        stopwatch.Stop();
        var connectionState = await unavailable.Task.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(1));
        Assert.Equal(0, publisher.QueuedEventCount);
        Assert.Equal("unavailable", connectionState);
    }

    private static MemoryStream EventPipe(string kind, string text, long sequence = 1)
    {
        var message = JsonSerializer.Serialize(new
        {
            type = "event",
            @event = new { kind, text, phase = "building", harness = "grok-build", run_id = "local-run", seq = sequence, timestamp = DateTimeOffset.UtcNow }
        });
        return new MemoryStream(Encoding.UTF8.GetBytes(message + "\n"));
    }

    private static async Task WaitForViewerState(Felix3LivePublisher publisher, bool expected)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(5);
        while (publisher.ViewerActive != expected && DateTimeOffset.UtcNow < deadline)
            await Task.Delay(10);
        Assert.Equal(expected, publisher.ViewerActive);
    }

    private static async Task WaitForConfigured(Felix3LivePublisher publisher)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(5);
        while (!publisher.IsConfigured && DateTimeOffset.UtcNow < deadline)
            await Task.Delay(10);
        Assert.True(publisher.IsConfigured);
    }
}
