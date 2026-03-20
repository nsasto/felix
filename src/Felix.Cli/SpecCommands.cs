using System.CommandLine;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static Command CreateSpecCommand(string felixPs1)
    {
        var cmd = new Command("spec", "Spec management utilities");

        var listCmd = CreateListCommand(felixPs1, new Option<string>("--format", () => "rich", "Output format"));
        listCmd.Description = "List requirements and specs";
        listCmd.IsHidden = false;

        var descArg = new Argument<string?>("description", "Feature description (optional for interactive mode)")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var quickOpt = new Option<bool>(new string[] { "--quick", "-q" }, "Quick mode with minimal questions");

        var createCmd = new Command("create", "Create a new specification")
        {
            descArg,
            quickOpt
        };

        createCmd.SetHandler(async (desc, quick) =>
        {
            var args = new List<string> { "spec", "create" };
            if (!string.IsNullOrEmpty(desc)) args.Add(desc);
            if (quick) args.Add("--quick");

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, descArg, quickOpt);

        var fixDupsOpt = new Option<bool>(new string[] { "--fix-duplicates", "-f" }, "Auto-rename duplicate spec files");

        var fixCmd = new Command("fix", "Align specs folder with requirements.json")
        {
            fixDupsOpt
        };

        fixCmd.SetHandler(async (fixDups) =>
        {
            RunSpecFixUI(fixDups);
            await Task.CompletedTask;
        }, fixDupsOpt);

        var delReqIdArg = new Argument<string>("requirement-id", "Requirement ID to delete");
        var assumeYesOpt = new Option<bool>(new[] { "--yes", "-y" }, "Skip the delete confirmation prompt");

        var deleteCmd = new Command("delete", "Delete a specification")
        {
            delReqIdArg,
            assumeYesOpt
        };

        deleteCmd.SetHandler(async (reqId, assumeYes) =>
        {
            DeleteSpecUI(reqId, assumeYes);
            await Task.CompletedTask;
        }, delReqIdArg, assumeYesOpt);

        var statusReqIdArg = new Argument<string>("requirement-id", "Requirement ID to update");
        var statusArg = new Argument<string>("status", "New status (draft, planned, in_progress, blocked, complete, done)");

        var statusCmd = new Command("status", "Update a requirement status in requirements.json")
        {
            statusReqIdArg,
            statusArg
        };

        statusCmd.SetHandler(async (reqId, status) =>
        {
            UpdateSpecStatusUI(reqId, status);
            await Task.CompletedTask;
        }, statusReqIdArg, statusArg);

        var dryRunOpt = new Option<bool>("--dry-run", "Show what would change without writing files");
        var deleteOpt = new Option<bool>("--delete", "Also delete local specs that no longer exist on server");
        var forceOpt2 = new Option<bool>("--force", "Overwrite local files even if not tracked in manifest");

        var pullCmd = new Command("pull", "Download changed specs from server")
        {
            dryRunOpt,
            deleteOpt,
            forceOpt2
        };

        pullCmd.SetHandler(async (dryRun, delete, force) =>
        {
            await RunSpecPullUI(dryRun, delete, force);
        }, dryRunOpt, deleteOpt, forceOpt2);

        var pushDryRunOpt = new Option<bool>("--dry-run", "Show what would change without uploading");
        var pushForceOpt = new Option<bool>("--force", "Upload all local specs and request create-if-missing requirement mappings");

        var pushCmd = new Command("push", "Upload local spec files to server")
        {
            pushDryRunOpt,
            pushForceOpt
        };

        pushCmd.SetHandler(async (dryRun, force) =>
        {
            await RunSpecPushUI(dryRun, force);
        }, pushDryRunOpt, pushForceOpt);

        cmd.AddCommand(listCmd);
        cmd.AddCommand(createCmd);
        cmd.AddCommand(fixCmd);
        cmd.AddCommand(deleteCmd);
        cmd.AddCommand(statusCmd);
        cmd.AddCommand(pullCmd);
        cmd.AddCommand(pushCmd);

        return cmd;
    }

    sealed record SpecFixResult(
        int TotalSpecs,
        List<string> Added,
        List<string> Updated,
        List<string> Duplicates,
        List<string> Fixed,
        List<string> Orphaned,
        List<string> Errors);

    static void UpdateSpecStatusUI(string requirementId, string status)
    {
        if (!IsValidRequirementId(requirementId))
        {
            AnsiConsole.MarkupLine("[red]Invalid requirement ID format. Expected S-NNNN (for example S-0001).[/]");
            Environment.ExitCode = 1;
            return;
        }

        var normalizedStatus = NormalizeRequirementStatus(status);
        var allowedStatuses = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "draft", "planned", "in_progress", "blocked", "complete", "done"
        };
        if (!allowedStatuses.Contains(normalizedStatus))
        {
            AnsiConsole.MarkupLine($"[red]Invalid status '{status.EscapeMarkup()}'. Allowed: {string.Join(", ", allowedStatuses).EscapeMarkup()}[/]");
            Environment.ExitCode = 1;
            return;
        }

        var document = LoadRequirementsDocument();
        var requirements = GetRequirementsArray(document);
        var requirement = FindRequirementNode(requirements, requirementId);
        if (requirement == null)
        {
            AnsiConsole.MarkupLine($"[red]Requirement {requirementId.EscapeMarkup()} not found in requirements.json.[/]");
            Environment.ExitCode = 1;
            return;
        }

        requirement["status"] = normalizedStatus;
        SaveRequirementsDocument(document);

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Specification Status Updated[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var summary = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));
        summary.AddRow("Requirement", requirementId.EscapeMarkup());
        summary.AddRow("Title", (GetJsonString(requirement.AsObject(), "title") ?? "-").EscapeMarkup());
        summary.AddRow("Status", RenderStatusMarkup(normalizedStatus));

        AnsiConsole.Write(summary);
        AnsiConsole.WriteLine();
        Environment.ExitCode = 0;
    }

    static void DeleteSpecUI(string requirementId, bool assumeYes)
    {
        if (!IsValidRequirementId(requirementId))
        {
            AnsiConsole.MarkupLine("[red]Invalid requirement ID format. Expected S-NNNN (for example S-0001).[/]");
            Environment.ExitCode = 1;
            return;
        }

        var document = LoadRequirementsDocument();
        var requirements = GetRequirementsArray(document);
        var requirement = FindRequirementNode(requirements, requirementId);
        if (requirement == null)
        {
            AnsiConsole.MarkupLine($"[red]Requirement {requirementId.EscapeMarkup()} not found in requirements.json.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var specPathValue = GetJsonString(requirement.AsObject(), "spec_path") ?? string.Empty;
        var specPath = string.IsNullOrWhiteSpace(specPathValue)
            ? Path.Combine(_felixProjectRoot, "specs", requirementId + ".md")
            : Path.GetFullPath(Path.Combine(_felixProjectRoot, specPathValue.Replace('/', Path.DirectorySeparatorChar)));

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[yellow]Delete Specification[/]").RuleStyle(Style.Parse("yellow dim")));
        AnsiConsole.WriteLine();

        var details = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));
        details.AddRow("Requirement", requirementId.EscapeMarkup());
        details.AddRow("Title", (GetJsonString(requirement.AsObject(), "title") ?? "-").EscapeMarkup());
        details.AddRow("Path", specPath.EscapeMarkup());
        details.AddRow("File", File.Exists(specPath) ? Path.GetFileName(specPath).EscapeMarkup() : "[grey](not found)[/]");
        AnsiConsole.Write(details);
        AnsiConsole.WriteLine();

        if (!assumeYes && !AnsiConsole.Confirm("Delete this specification?", false))
        {
            AnsiConsole.MarkupLine("[grey]Deletion cancelled.[/]");
            Environment.ExitCode = 0;
            return;
        }

        if (File.Exists(specPath))
            File.Delete(specPath);

        for (var index = 0; index < requirements.Count; index++)
        {
            if (requirements[index] is JsonObject reqObj && string.Equals(GetJsonString(reqObj, "id"), requirementId, StringComparison.OrdinalIgnoreCase))
            {
                requirements.RemoveAt(index);
                break;
            }
        }

        SaveRequirementsDocument(document);
        AnsiConsole.MarkupLine($"[green]Deleted specification {requirementId.EscapeMarkup()}.[/]");
        Environment.ExitCode = 0;
    }

    static void RunSpecFixUI(bool fixDuplicates)
    {
        var specsDir = Path.Combine(_felixProjectRoot, "specs");
        if (!Directory.Exists(specsDir))
        {
            AnsiConsole.MarkupLine($"[red]Specs directory not found: {specsDir.EscapeMarkup()}[/]");
            Environment.ExitCode = 1;
            return;
        }

        var document = LoadRequirementsDocument();
        var requirements = GetRequirementsArray(document);
        var specFiles = Directory.GetFiles(specsDir, "S-*.md", SearchOption.TopDirectoryOnly)
            .Select(path => new FileInfo(path))
            .OrderBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();

        var added = new List<string>();
        var updated = new List<string>();
        var duplicates = new List<string>();
        var fixedItems = new List<string>();
        var errors = new List<string>();
        var processedIds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var allSpecIds = specFiles
            .Select(file => TryParseRequirementId(file.Name))
            .Where(id => id != null)
            .Select(id => int.Parse(id!.AsSpan(2)))
            .ToList();
        var maxSpecId = allSpecIds.Count > 0 ? allSpecIds.Max() : 0;

        var existingById = requirements
            .OfType<JsonObject>()
            .Select(node => node.DeepClone().AsObject())
            .Where(node => !string.IsNullOrWhiteSpace(GetJsonString(node, "id")))
            .ToDictionary(node => GetJsonString(node, "id")!, node => node, StringComparer.OrdinalIgnoreCase);

        var currentSpecFiles = new List<FileInfo>();
        foreach (var originalFile in specFiles)
        {
            var specFile = originalFile;
            var reqId = TryParseRequirementId(specFile.Name);
            if (reqId == null)
            {
                errors.Add($"Invalid filename format: {specFile.Name}");
                continue;
            }

            if (processedIds.ContainsKey(reqId))
            {
                if (!fixDuplicates)
                {
                    duplicates.Add(specFile.Name);
                    continue;
                }

                maxSpecId = GetNextAvailableSpecNumber(maxSpecId + 1, specsDir);
                var newReqId = $"S-{maxSpecId:D4}";
                var newFileName = reqId + specFile.Name.Substring(reqId.Length);
                newFileName = newFileName.Replace(reqId, newReqId, StringComparison.OrdinalIgnoreCase);
                var newPath = Path.Combine(specsDir, newFileName);
                File.Move(specFile.FullName, newPath);
                fixedItems.Add($"{specFile.Name} -> {newFileName}");
                specFile = new FileInfo(newPath);
                reqId = newReqId;
            }

            processedIds[reqId] = specFile.Name;

            if (existingById.TryGetValue(reqId, out var existing))
            {
                var relativePath = ToRequirementRelativeSpecPath(specFile.Name);
                if (!string.Equals(GetJsonString(existing, "spec_path"), relativePath, StringComparison.OrdinalIgnoreCase))
                    updated.Add(reqId);
                existingById.Remove(reqId);
            }
            else
            {
                added.Add(reqId);
            }

            currentSpecFiles.Add(specFile);
        }

        var orphaned = existingById.Keys.OrderBy(id => id, StringComparer.OrdinalIgnoreCase).ToList();
        var defaultStatus = added.Count > 0 ? PromptForDefaultSpecStatus() : "draft";
        var rebuiltRequirements = new JsonArray();

        foreach (var specFile in currentSpecFiles.OrderBy(file => file.Name, StringComparer.OrdinalIgnoreCase))
        {
            var reqId = TryParseRequirementId(specFile.Name)!;
            var original = requirements
                .OfType<JsonObject>()
                .FirstOrDefault(node => string.Equals(GetJsonString(node, "id"), reqId, StringComparison.OrdinalIgnoreCase));

            var metaPath = Path.Combine(specsDir, Path.GetFileNameWithoutExtension(specFile.Name) + ".meta.json");
            var meta = LoadOptionalJsonObject(metaPath);
            var resolvedStatus = GetJsonString(original?.AsObject() ?? new JsonObject(), "status") ?? defaultStatus;
            var metaStatus = GetJsonString(meta ?? new JsonObject(), "status");
            if (!string.IsNullOrWhiteSpace(metaStatus))
                resolvedStatus = metaStatus!;

            var title = GetSpecTitle(specFile.FullName, reqId, GetJsonString(original?.AsObject() ?? new JsonObject(), "title"));
            var reqNode = new JsonObject
            {
                ["id"] = reqId,
                ["spec_path"] = ToRequirementRelativeSpecPath(specFile.Name),
                ["status"] = resolvedStatus
            };

            if (!string.IsNullOrWhiteSpace(title))
                reqNode["title"] = title;
            if (GetJsonBool(original?.AsObject() ?? new JsonObject(), "commit_on_complete", false))
                reqNode["commit_on_complete"] = true;

            rebuiltRequirements.Add(reqNode);

            if (original == null && !File.Exists(metaPath))
            {
                var newMeta = new JsonObject
                {
                    ["status"] = resolvedStatus,
                    ["priority"] = "medium",
                    ["tags"] = new JsonArray(),
                    ["depends_on"] = new JsonArray(),
                    ["updated_at"] = DateTime.Now.ToString("yyyy-MM-dd")
                };
                File.WriteAllText(metaPath, newMeta.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
            }
        }

        var sortedRequirements = rebuiltRequirements
            .OfType<JsonObject>()
            .OrderBy(node => GetJsonString(node, "id"), StringComparer.OrdinalIgnoreCase)
            .Cast<JsonNode>()
            .ToArray();
        document["requirements"] = new JsonArray(sortedRequirements);
        SaveRequirementsDocument(document);

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Specification Fix[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var summary = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Metric[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Count[/]").RightAligned().NoWrap());
        summary.AddRow("Total specs", currentSpecFiles.Count.ToString());
        summary.AddRow("Added", added.Count.ToString());
        summary.AddRow("Updated", updated.Count.ToString());
        summary.AddRow("Fixed duplicates", fixedItems.Count.ToString());
        summary.AddRow("Duplicate skips", duplicates.Count.ToString());
        summary.AddRow("Orphaned", orphaned.Count.ToString());
        summary.AddRow("Errors", errors.Count.ToString());
        AnsiConsole.Write(summary);
        AnsiConsole.WriteLine();

        if (fixedItems.Count > 0)
            AnsiConsole.MarkupLine($"[cyan]Fixed:[/] {string.Join(", ", fixedItems.Select(item => item.EscapeMarkup()))}");
        if (duplicates.Count > 0)
            AnsiConsole.MarkupLine($"[magenta]Duplicates skipped:[/] {string.Join(", ", duplicates.Select(item => item.EscapeMarkup()))}");
        if (orphaned.Count > 0)
            AnsiConsole.MarkupLine($"[yellow]Orphaned:[/] {string.Join(", ", orphaned.Select(item => item.EscapeMarkup()))}");
        if (errors.Count > 0)
            AnsiConsole.MarkupLine($"[red]Errors:[/] {string.Join(" | ", errors.Select(item => item.EscapeMarkup()))}");

        Environment.ExitCode = errors.Count == 0 ? 0 : 1;
    }

    sealed record RemoteSpecFile(string Path, string Hash);
    sealed record SpecPushFile(string Path, string ContentBase64);
    sealed record SpecPushResult(string Path, bool Uploaded, string? Error);

    static async Task RunSpecPullUI(bool dryRun, bool delete, bool force)
    {
        if (!TryResolveSpecSyncSettings(out var baseUrl, out var apiKey))
            return;

        var manifest = LoadSpecManifest();
        var checkPayload = new JsonObject { ["files"] = BuildManifestFilesObject(manifest) };
        var checkResponse = await PostJsonAsync(baseUrl, "/api/sync/specs/check", checkPayload, apiKey, 15);
        if (!checkResponse.Success)
        {
            AnsiConsole.MarkupLine($"[red]Failed to check specs with server:[/] {(checkResponse.Error ?? "unknown error").EscapeMarkup()}");
            Environment.ExitCode = 1;
            return;
        }

        var downloads = new List<RemoteSpecFile>();
        var deletes = new List<string>();

        try
        {
            using var document = JsonDocument.Parse(checkResponse.Content ?? "{}");
            if (document.RootElement.TryGetProperty("download", out var downloadElement) && downloadElement.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in downloadElement.EnumerateArray())
                {
                    var path = GetJsonString(entry, "path");
                    var hash = GetJsonString(entry, "hash");
                    if (!string.IsNullOrWhiteSpace(path) && !string.IsNullOrWhiteSpace(hash))
                        downloads.Add(new RemoteSpecFile(path!, hash!));
                }
            }

            if (document.RootElement.TryGetProperty("delete", out var deleteElement) && deleteElement.ValueKind == JsonValueKind.Array)
            {
                deletes.AddRange(deleteElement.EnumerateArray()
                    .Where(item => item.ValueKind == JsonValueKind.String)
                    .Select(item => item.GetString())
                    .Where(item => !string.IsNullOrWhiteSpace(item))!
                    .Cast<string>());
            }
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Server response could not be parsed:[/] {ex.Message.EscapeMarkup()}");
            Environment.ExitCode = 1;
            return;
        }

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Spec Pull[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        if (downloads.Count == 0 && deletes.Count == 0)
        {
            AnsiConsole.MarkupLine("[green]Already up to date.[/]");
            Environment.ExitCode = 0;
            return;
        }

        var results = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Action[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Path[/]"))
            .AddColumn(new TableColumn("[yellow]Result[/]"));

        var newFileCount = 0;
        foreach (var entry in downloads.OrderBy(item => item.Path, StringComparer.OrdinalIgnoreCase))
        {
            var destinationPath = Path.Combine(_felixProjectRoot, entry.Path.Replace('/', Path.DirectorySeparatorChar));
            var tracked = manifest.ContainsKey(entry.Path);
            var exists = File.Exists(destinationPath);
            var action = exists ? "update" : "download";

            if (dryRun)
            {
                results.AddRow(action, entry.Path.EscapeMarkup(), "[yellow]dry-run[/]");
                continue;
            }

            if (exists && !tracked && !force)
            {
                results.AddRow(action, entry.Path.EscapeMarkup(), "[yellow]skipped: local file not in manifest[/]");
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
            var downloadResult = await DownloadSpecFileAsync(baseUrl, entry.Path, apiKey);
            if (!downloadResult.Success || downloadResult.Bytes == null)
            {
                results.AddRow(action, entry.Path.EscapeMarkup(), $"[red]{(downloadResult.Error ?? "download failed").EscapeMarkup()}[/]");
                continue;
            }

            await File.WriteAllBytesAsync(destinationPath, downloadResult.Bytes);
            var actualHash = ComputeFileSha256(destinationPath);
            var expectedHash = entry.Hash.ToLowerInvariant();
            manifest[entry.Path] = entry.Hash;
            if (!tracked)
            {
                newFileCount++;
                TryCreateSpecMetaSidecar(entry.Path);
            }

            var resultMarkup = string.Equals(actualHash, expectedHash, StringComparison.OrdinalIgnoreCase)
                ? "[green]ok[/]"
                : $"[yellow]hash mismatch (expected {expectedHash.EscapeMarkup()}, got {actualHash.EscapeMarkup()})[/]";
            results.AddRow(action, entry.Path.EscapeMarkup(), resultMarkup);
        }

        foreach (var relPath in deletes.OrderBy(item => item, StringComparer.OrdinalIgnoreCase))
        {
            if (dryRun)
            {
                results.AddRow("delete", relPath.EscapeMarkup(), "[yellow]dry-run[/]");
                continue;
            }

            if (delete)
            {
                var destinationPath = Path.Combine(_felixProjectRoot, relPath.Replace('/', Path.DirectorySeparatorChar));
                if (File.Exists(destinationPath))
                    File.Delete(destinationPath);
                manifest.Remove(relPath);
                results.AddRow("delete", relPath.EscapeMarkup(), "[green]deleted[/]");
            }
            else
            {
                results.AddRow("delete", relPath.EscapeMarkup(), "[grey]skipped (--delete not set)[/]");
            }
        }

        AnsiConsole.Write(results);
        AnsiConsole.WriteLine();

        if (!dryRun)
            SaveSpecManifest(manifest);

        if (dryRun)
            AnsiConsole.MarkupLine("[yellow]Dry run complete. No files were changed.[/]");
        else
            AnsiConsole.MarkupLine("[green]Spec pull complete.[/]");

        if (!dryRun && newFileCount > 0)
            AnsiConsole.MarkupLine($"[cyan]Hint:[/] {newFileCount} new spec file(s) downloaded. Run 'felix spec fix' to register them in requirements.json.");

        Environment.ExitCode = 0;
    }

    static async Task RunSpecPushUI(bool dryRun, bool force)
    {
        if (!TryResolveSpecSyncSettings(out var baseUrl, out var apiKey))
            return;

        var specsDir = Path.Combine(_felixProjectRoot, "specs");
        if (!Directory.Exists(specsDir))
        {
            AnsiConsole.MarkupLine($"[red]No specs directory found at:[/] {specsDir.EscapeMarkup()}");
            Environment.ExitCode = 1;
            return;
        }

        var specFiles = Directory.GetFiles(specsDir, "*.md", SearchOption.AllDirectories)
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .Select(path => new SpecPushFile(GetSpecRelativePath(specsDir, path), Convert.ToBase64String(File.ReadAllBytes(path))))
            .ToList();

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Spec Push[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        if (specFiles.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No spec files found in specs/.[/]");
            Environment.ExitCode = 0;
            return;
        }

        if (dryRun)
        {
            var table = new Table()
                .Border(TableBorder.Rounded)
                .BorderColor(Color.Grey)
                .AddColumn(new TableColumn("[yellow]Path[/]"));
            foreach (var file in specFiles)
                table.AddRow(file.Path.EscapeMarkup());
            AnsiConsole.Write(table);
            AnsiConsole.WriteLine();
            if (force)
                AnsiConsole.MarkupLine("[yellow]--force would request create-if-missing requirement mappings on the server.[/]");
            AnsiConsole.MarkupLine("[yellow]Dry run complete. No files were uploaded.[/]");
            Environment.ExitCode = 0;
            return;
        }

        var chunkSize = GetIntEnvironmentVariable("FELIX_SPEC_PUSH_CHUNK_SIZE", 10);
        var timeoutSec = GetIntEnvironmentVariable("FELIX_SPEC_PUSH_TIMEOUT_SEC", 120);
        var maxRetries = GetIntEnvironmentVariable("FELIX_SPEC_PUSH_RETRIES", 2);
        var allResults = new List<SpecPushResult>();
        var totalChunks = (int)Math.Ceiling(specFiles.Count / (double)chunkSize);

        for (var chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++)
        {
            var chunk = specFiles.Skip(chunkIndex * chunkSize).Take(chunkSize).ToList();
            var payload = new JsonObject
            {
                ["files"] = new JsonArray(chunk.Select(file => new JsonObject
                {
                    ["path"] = file.Path,
                    ["content"] = file.ContentBase64
                }).ToArray<JsonNode>())
            };

            if (force)
            {
                payload["force"] = true;
                payload["create_missing_requirements"] = true;
                payload["create_requirements_if_missing"] = true;
            }

            HttpStringResult? uploadResponse = null;
            for (var attempt = 1; attempt <= maxRetries + 1; attempt++)
            {
                uploadResponse = await PostJsonAsync(baseUrl, "/api/sync/specs/upload", payload, apiKey, timeoutSec);
                if (uploadResponse.Success)
                    break;

                if (attempt > maxRetries)
                {
                    AnsiConsole.MarkupLine($"[red]Failed to upload chunk {chunkIndex + 1}/{totalChunks}:[/] {(uploadResponse.Error ?? "unknown error").EscapeMarkup()}");
                    Environment.ExitCode = 1;
                    return;
                }

                var delaySeconds = attempt * 5;
                AnsiConsole.MarkupLine($"[yellow]Retrying chunk {chunkIndex + 1}/{totalChunks} in {delaySeconds}s:[/] {(uploadResponse.Error ?? "upload failed").EscapeMarkup()}");
                await Task.Delay(TimeSpan.FromSeconds(delaySeconds));
            }

            try
            {
                using var document = JsonDocument.Parse(uploadResponse!.Content ?? "{}");
                if (document.RootElement.TryGetProperty("results", out var resultsElement) && resultsElement.ValueKind == JsonValueKind.Array)
                {
                    foreach (var result in resultsElement.EnumerateArray())
                    {
                        var path = GetJsonString(result, "path") ?? "-";
                        var uploaded = result.TryGetProperty("uploaded", out var uploadedElement) && uploadedElement.ValueKind == JsonValueKind.True;
                        var error = GetJsonString(result, "error");
                        if (!string.IsNullOrWhiteSpace(error))
                            error = error.Replace("â??", "-", StringComparison.Ordinal);
                        allResults.Add(new SpecPushResult(path, uploaded, error));
                    }
                }
            }
            catch (Exception ex)
            {
                AnsiConsole.MarkupLine($"[red]Upload response could not be parsed:[/] {ex.Message.EscapeMarkup()}");
                Environment.ExitCode = 1;
                return;
            }
        }

        var resultTable = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Path[/]"))
            .AddColumn(new TableColumn("[yellow]Result[/]"))
            .AddColumn(new TableColumn("[yellow]Details[/]"));

        var uploadedCount = 0;
        var skippedCount = 0;
        var missingRequirementCount = 0;
        var forceCreateNotHonoredCount = 0;

        foreach (var result in allResults)
        {
            if (result.Uploaded)
            {
                uploadedCount++;
                resultTable.AddRow(result.Path.EscapeMarkup(), "[green]uploaded[/]", "-");
                continue;
            }

            skippedCount++;
            var detail = result.Error ?? "skipped";
            if (detail.Contains("No requirement found with this spec_path", StringComparison.OrdinalIgnoreCase))
            {
                missingRequirementCount++;
                if (force)
                    forceCreateNotHonoredCount++;
                detail = "No matching requirement for this spec_path on the server project. Verify backend URL/API key project mapping, then bootstrap remote requirements.";
            }

            resultTable.AddRow(result.Path.EscapeMarkup(), "[yellow]skipped[/]", detail.EscapeMarkup());
        }

        AnsiConsole.Write(resultTable);
        AnsiConsole.WriteLine();

        if (skippedCount == 0)
        {
            AnsiConsole.MarkupLine($"[green]Spec push complete. {uploadedCount} file(s) uploaded.[/]");
        }
        else
        {
            AnsiConsole.MarkupLine($"[yellow]Spec push complete. {uploadedCount} uploaded, {skippedCount} skipped.[/]");
            if (force && forceCreateNotHonoredCount > 0)
            {
                AnsiConsole.MarkupLine($"[yellow]Server did not create {forceCreateNotHonoredCount} missing requirement mapping(s) despite --force.[/]");
                AnsiConsole.MarkupLine("[grey]This backend may not support create-if-missing in spec upload yet.[/]");
            }

            if (missingRequirementCount == skippedCount && skippedCount > 0)
            {
                AnsiConsole.MarkupLine("[grey]All skipped specs are missing requirement rows on the server project (local files exist).[/]");
                AnsiConsole.MarkupLine("[grey]Check FELIX_SYNC_URL + API key project mapping, then bootstrap requirements on the backend.[/]");
                AnsiConsole.MarkupLine("[grey]Tip: 'felix spec fix' updates local requirements.json only; it does not create remote requirement rows.[/]");
            }
            else
            {
                AnsiConsole.MarkupLine("[grey]Skipped specs may not have matching requirements in the DB yet.[/]");
                AnsiConsole.MarkupLine("[grey]Run 'felix spec fix' then retry.[/]");
            }
        }

        Environment.ExitCode = 0;
    }

    static bool TryResolveSpecSyncSettings(out string baseUrl, out string apiKey)
    {
        baseUrl = string.Empty;
        apiKey = string.Empty;

        var configPath = Path.Combine(_felixProjectRoot, ".felix", "config.json");
        if (!File.Exists(configPath))
        {
            AnsiConsole.MarkupLine("[red]No .felix/config.json found. Run 'felix setup' first.[/]");
            Environment.ExitCode = 1;
            return false;
        }

        var config = LoadSetupConfig(configPath);
        EnsureSetupConfigDefaults(config);
        var sync = EnsureObject(config, "sync");

        baseUrl = Environment.GetEnvironmentVariable("FELIX_SYNC_URL")
            ?? GetOptionalJsonString(sync, "base_url")
            ?? string.Empty;
        apiKey = Environment.GetEnvironmentVariable("FELIX_SYNC_KEY")
            ?? GetOptionalJsonString(sync, "api_key")
            ?? string.Empty;

        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            AnsiConsole.MarkupLine("[red]sync.base_url is not set in .felix/config.json. Run 'felix setup' to configure it.[/]");
            Environment.ExitCode = 1;
            return false;
        }

        if (string.IsNullOrWhiteSpace(apiKey))
        {
            AnsiConsole.MarkupLine("[red]sync.api_key is not set in .felix/config.json or FELIX_SYNC_KEY. Run 'felix setup' to add your API key.[/]");
            Environment.ExitCode = 1;
            return false;
        }

        return true;
    }

    static Dictionary<string, string> LoadSpecManifest()
    {
        var manifestPath = Path.Combine(_felixProjectRoot, ".felix", "spec-manifest.json");
        var manifest = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(manifestPath))
            return manifest;

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(manifestPath));
            if (document.RootElement.TryGetProperty("files", out var filesElement) && filesElement.ValueKind == JsonValueKind.Object)
            {
                foreach (var property in filesElement.EnumerateObject())
                {
                    if (property.Value.ValueKind == JsonValueKind.String)
                        manifest[property.Name] = property.Value.GetString() ?? string.Empty;
                }
            }
        }
        catch
        {
        }

        return manifest;
    }

    static JsonObject BuildManifestFilesObject(IReadOnlyDictionary<string, string> manifest)
    {
        var filesObject = new JsonObject();
        foreach (var pair in manifest.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase))
            filesObject[pair.Key] = pair.Value;
        return filesObject;
    }

    static void SaveSpecManifest(IReadOnlyDictionary<string, string> manifest)
    {
        var manifestPath = Path.Combine(_felixProjectRoot, ".felix", "spec-manifest.json");
        Directory.CreateDirectory(Path.GetDirectoryName(manifestPath)!);
        var payload = new JsonObject
        {
            ["synced_at"] = DateTime.UtcNow.ToString("o"),
            ["files"] = BuildManifestFilesObject(manifest)
        };
        File.WriteAllText(manifestPath, payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
    }

    sealed record HttpStringResult(bool Success, string? Content, string? Error);
    sealed record HttpBytesResult(bool Success, byte[]? Bytes, string? Error);

    static async Task<HttpStringResult> PostJsonAsync(string baseUrl, string endpoint, JsonObject payload, string apiKey, int timeoutSeconds)
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(timeoutSeconds) };
            using var request = new HttpRequestMessage(HttpMethod.Post, baseUrl.TrimEnd('/') + endpoint)
            {
                Content = new StringContent(payload.ToJsonString(), Encoding.UTF8, "application/json")
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            using var response = await client.SendAsync(request);
            var content = await response.Content.ReadAsStringAsync();
            return response.IsSuccessStatusCode
                ? new HttpStringResult(true, content, null)
                : new HttpStringResult(false, content, ExtractApiErrorMessage(content) ?? $"HTTP {(int)response.StatusCode} {response.ReasonPhrase}");
        }
        catch (Exception ex)
        {
            return new HttpStringResult(false, null, ex.Message);
        }
    }

    static async Task<HttpBytesResult> DownloadSpecFileAsync(string baseUrl, string relativePath, string apiKey)
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            var encodedPath = Uri.EscapeDataString(relativePath);
            using var request = new HttpRequestMessage(HttpMethod.Get, baseUrl.TrimEnd('/') + "/api/sync/specs/file?path=" + encodedPath);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            using var response = await client.SendAsync(request);
            var bytes = await response.Content.ReadAsByteArrayAsync();
            return response.IsSuccessStatusCode
                ? new HttpBytesResult(true, bytes, null)
                : new HttpBytesResult(false, null, ExtractApiErrorMessage(Encoding.UTF8.GetString(bytes)) ?? $"HTTP {(int)response.StatusCode} {response.ReasonPhrase}");
        }
        catch (Exception ex)
        {
            return new HttpBytesResult(false, null, ex.Message);
        }
    }

    static string ComputeFileSha256(string path)
    {
        using var sha = SHA256.Create();
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(sha.ComputeHash(stream)).ToLowerInvariant();
    }

    static void TryCreateSpecMetaSidecar(string relativePath)
    {
        if (!relativePath.StartsWith("specs/", StringComparison.OrdinalIgnoreCase) || !relativePath.EndsWith(".md", StringComparison.OrdinalIgnoreCase))
            return;

        var fileName = Path.GetFileName(relativePath);
        var requirementId = TryParseRequirementId(fileName);
        if (requirementId == null)
            return;

        var metaRelativePath = relativePath[..^3] + ".meta.json";
        var metaPath = Path.Combine(_felixProjectRoot, metaRelativePath.Replace('/', Path.DirectorySeparatorChar));
        if (File.Exists(metaPath))
            return;

        Directory.CreateDirectory(Path.GetDirectoryName(metaPath)!);
        var payload = new JsonObject
        {
            ["status"] = "planned",
            ["priority"] = "medium",
            ["tags"] = new JsonArray(),
            ["depends_on"] = new JsonArray(),
            ["updated_at"] = DateTime.UtcNow.ToString("yyyy-MM-dd")
        };
        File.WriteAllText(metaPath, payload.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
    }

    static string GetSpecRelativePath(string specsDir, string fullPath)
    {
        var relative = Path.GetRelativePath(specsDir, fullPath).Replace('\\', '/');
        return "specs/" + relative.TrimStart('/');
    }

    static int GetIntEnvironmentVariable(string variableName, int fallback)
    {
        var raw = Environment.GetEnvironmentVariable(variableName);
        return int.TryParse(raw, out var parsed) && parsed > 0 ? parsed : fallback;
    }

    static JsonObject LoadRequirementsDocument()
    {
        var path = Path.Combine(_felixProjectRoot, ".felix", "requirements.json");
        if (!File.Exists(path))
            return new JsonObject { ["requirements"] = new JsonArray() };

        try
        {
            var raw = File.ReadAllText(path, Encoding.UTF8).Trim();
            if (string.IsNullOrWhiteSpace(raw))
                return new JsonObject { ["requirements"] = new JsonArray() };

            var node = JsonNode.Parse(raw);
            if (node is JsonArray array)
                return new JsonObject { ["requirements"] = array };
            if (node is JsonObject obj)
            {
                if (obj["requirements"] is JsonObject singleReq)
                    obj["requirements"] = new JsonArray(singleReq);
                else if (obj["requirements"] is not JsonArray)
                    obj["requirements"] = new JsonArray();
                return obj;
            }
        }
        catch { }

        return new JsonObject { ["requirements"] = new JsonArray() };
    }

    static JsonArray GetRequirementsArray(JsonObject document)
    {
        if (document["requirements"] is JsonArray array)
            return array;

        var created = new JsonArray();
        document["requirements"] = created;
        return created;
    }

    static JsonObject? FindRequirementNode(JsonArray requirements, string requirementId)
        => requirements
            .OfType<JsonObject>()
            .FirstOrDefault(node => string.Equals(GetJsonString(node, "id"), requirementId, StringComparison.OrdinalIgnoreCase));

    static void SaveRequirementsDocument(JsonObject document)
    {
        var path = Path.Combine(_felixProjectRoot, ".felix", "requirements.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, document.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine, Encoding.UTF8);
    }

    static bool IsValidRequirementId(string requirementId)
        => System.Text.RegularExpressions.Regex.IsMatch(requirementId, "^S-\\d{4}$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);

    static string NormalizeRequirementStatus(string status)
        => string.Equals(status, "in-progress", StringComparison.OrdinalIgnoreCase) ? "in_progress" : status.ToLowerInvariant();

    static string? TryParseRequirementId(string fileName)
    {
        var match = System.Text.RegularExpressions.Regex.Match(fileName, "^(S-\\d{4})", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value.ToUpperInvariant() : null;
    }

    static int GetNextAvailableSpecNumber(int startFrom, string specsDir)
    {
        var nextId = startFrom;
        while (File.Exists(Path.Combine(specsDir, $"S-{nextId:D4}.md")) || Directory.GetFiles(specsDir, $"S-{nextId:D4}-*.md").Length > 0)
        {
            nextId++;
        }
        return nextId;
    }

    static string ToRequirementRelativeSpecPath(string fileName)
        => $"specs/{fileName}";

    static string PromptForDefaultSpecStatus()
    {
        var selected = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title("[cyan]Default status for newly discovered specs:[/]")
                .AddChoices(new[] { "draft", "planned", "in_progress", "blocked", "done", "complete" }));

        return selected;
    }

    static JsonObject? LoadOptionalJsonObject(string path)
    {
        if (!File.Exists(path))
            return null;

        try
        {
            return JsonNode.Parse(File.ReadAllText(path))?.AsObject();
        }
        catch
        {
            return null;
        }
    }

    static string? GetSpecTitle(string specPath, string requirementId, string? existingTitle)
    {
        var fallbackTitle = string.IsNullOrWhiteSpace(existingTitle) ? null : existingTitle.Trim();
        if (!File.Exists(specPath))
            return fallbackTitle;

        try
        {
            foreach (var line in File.ReadLines(specPath, Encoding.UTF8))
            {
                var match = System.Text.RegularExpressions.Regex.Match(line, "^\\s*#\\s+(.+?)\\s*$");
                if (!match.Success)
                    continue;

                var heading = match.Groups[1].Value.Trim();
                if (string.IsNullOrWhiteSpace(heading))
                    break;

                var prefixPattern = $"^(?:{System.Text.RegularExpressions.Regex.Escape(requirementId)})\\s*[:\\-\\u2013\\u2014]\\s*(.+)$";
                var normalized = System.Text.RegularExpressions.Regex.Match(heading, prefixPattern);
                var title = normalized.Success ? normalized.Groups[1].Value.Trim() : heading;
                return string.IsNullOrWhiteSpace(title) ? fallbackTitle : title;
            }
        }
        catch { }

        return fallbackTitle;
    }
}
