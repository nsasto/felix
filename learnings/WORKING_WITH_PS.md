# Working with PowerShell - Learnings & Gotchas

This document captures key learnings, debugging insights, and common pitfalls when working with PowerShell in the Felix project.

## Regular Expressions

### Multiline Matching with `.` Wildcard

**Problem:** PowerShell regex patterns using `.` do NOT match newline characters by default, causing XML tag parsing to fail on multiline content.

**Example Failure:**
```powershell
$text = @"
<question>
Line 1
Line 2
</question>
"@

# This FAILS - . doesn't match newlines
if ($text -match '<question>(.*?)</question>') {
    Write-Host $Matches[1]  # Empty or incomplete
}
```

**Solution:** Use the `(?s)` flag (single-line mode) to make `.` match any character including newlines:
```powershell
# This WORKS
if ($text -match '(?s)<question>(.*?)</question>') {
    Write-Host $Matches[1]  # Gets full multiline content
}
```

**Impact:** Critical for parsing AI responses with XML tags that span multiple lines.

---

## Parameter Passing

### Switch Parameters Must Be Bare, Not Strings

**Problem:** When calling scripts with switch parameters, you cannot pass them as strings in an array.

**Example Failure:**
```powershell
# WRONG - This doesn't work
$args = @("-ProjectPath", $path, "-SpecBuildMode", "-QuickMode")
& "script.ps1" @args

# Switch parameters get interpreted as strings, not switches
```

**Solution:** Pass switch parameters directly using parameter syntax:
```powershell
# CORRECT
& "script.ps1" -ProjectPath $path -SpecBuildMode -QuickMode

# Or with explicit parameter splatting
$params = @{
    ProjectPath = $path
    SpecBuildMode = $true
    QuickMode = $true
}
& "script.ps1" @params
```

**Impact:** Spec builder mode wasn't being activated because switches were passed as strings.

---

## Interactive Console Detection

### Detecting Terminal vs Redirected Mode

**Problem:** File-based prompts designed for UI/TUI integration hang in interactive terminal sessions.

**Solution:** Check if stdin is redirected and if running in an interactive environment:
```powershell
$isInteractive = [Console]::IsInputRedirected -eq $false -and [Environment]::UserInteractive

if ($isInteractive) {
    # Use Read-Host for direct user input
    $input = Read-Host "Your answer"
}
else {
    # Use file-based prompts for UI/TUI
    # Write prompt file, wait for response file
}
```

**Key Properties:**
- `[Console]::IsInputRedirected` - True if stdin is piped or redirected
- `[Environment]::UserInteractive` - True if process has interactive user session

**Impact:** Allows spec builder to work both in terminal and programmatically via files.

---

## JSON Structure Handling

### Requirements.json Array Structure

**Problem:** When loading `requirements.json`, wrapping the entire object in an array breaks the structure.

**Incorrect:**
```powershell
# WRONG - Wraps entire JSON object in array
$requirements = @()
if (Test-Path $file) {
    $content = Get-Content $file -Raw | ConvertFrom-Json
    $requirements = @($content)  # This is wrong!
}
```

**Correct:**
```powershell
# CORRECT - Access the .requirements property
$requirementsData = @{ requirements = @() }
if (Test-Path $file) {
    $requirementsData = Get-Content $file -Raw | ConvertFrom-Json
}
$requirements = @($requirementsData.requirements)

# When saving back
$requirementsData = @{ requirements = $requirements }
$requirementsData | ConvertTo-Json -Depth 10 | Set-Content $file
```

**Impact:** Spec builder couldn't update requirements.json correctly.

---

## File Pattern Matching

### Wildcard Patterns for Duplicate Detection

**Problem:** Checking for exact filename `S-0054.md` fails when actual file is `S-0054-descriptive-slug.md`.

**Incorrect:**
```powershell
# WRONG - Only finds exact match
$specPath = Join-Path $dir "S-0054.md"
if (Test-Path $specPath) {
    # Never true if file has slug
}
```

**Correct:**
```powershell
# CORRECT - Use wildcard with Get-ChildItem
$existingSpec = Get-ChildItem -Path $dir -Filter "S-0054*.md" -ErrorAction SilentlyContinue
if ($existingSpec) {
    Write-Host "Found: $($existingSpec.FullName)"
}
```

**Impact:** Spec builder failed duplicate detection when specs had descriptive slugs.

---

## String Manipulation

### Slugification for Filenames

**Best Practice:** Convert titles to URL-safe slugs for filenames:
```powershell
$title = "User Profile Page"
$slug = $title.ToLower() `
    -replace '[^\w\s-]', '' `      # Remove special chars
    -replace '\s+', '-' `           # Spaces to dashes
    -replace '-+', '-' `            # Collapse multiple dashes
    -replace '^-|-$', ''            # Trim leading/trailing dashes

# Result: "user-profile-page"
```

---

## XML Tag Parsing Strategy

### Multiple Tag Types in Same Response

**Pattern:** Parse all possible tags and return array of events, not just first match:
```powershell
function Parse-Response {
    param([string]$Response)
    $events = @()
    
    # Check for filename (can appear WITH question or spec)
    if ($Response -match '(?s)<filename>(.*?)</filename>') {
        $events += @{ type = "filename"; content = $Matches[1].Trim() }
    }
    
    # Check for question
    if ($Response -match '(?s)<question>(.*?)</question>') {
        $events += @{ type = "question"; content = $Matches[1].Trim() }
    }
    
    # Check for spec
    if ($Response -match '(?s)<spec>(.*?)</spec>') {
        $events += @{ type = "complete"; content = $Matches[1].Trim() }
    }
    
    # Fallback if no tags
    if ($events.Count -eq 0) {
        $events += @{ type = "question"; content = $Response }
    }
    
    return $events
}
```

**Impact:** AI can provide multiple XML tags in same response (e.g., `<filename>` before `<spec>`).

---

## Debugging Tips

### Add Verbose Logging for Config Loading

**Pattern:** Add debug logs at each stage of initialization to identify where hangs occur:
```powershell
Emit-Log -Level "debug" -Message "Loading Felix config from $ConfigFile" -Component "init"
$config = Get-FelixConfig -ConfigFile $ConfigFile
Emit-Log -Level "debug" -Message "Config loaded successfully" -Component "init"

Emit-Log -Level "debug" -Message "Loading agents configuration" -Component "init"
$agentsData = Get-AgentsConfiguration
Emit-Log -Level "debug" -Message "Agents data loaded successfully" -Component "init"
```

**Impact:** Quickly identifies which function is hanging or failing silently.

---

## Common Pitfalls

### 1. Assuming File Existence
Always check if files exist before operations:
```powershell
if (Test-Path $file) {
    # Safe to proceed
}
```

### 2. Forgetting UTF-8 Encoding
Always specify encoding for spec files:
```powershell
Set-Content -Path $file -Value $content -Encoding UTF8
```

### 3. Not Handling Empty Arrays
PowerShell treats single items differently than arrays:
```powershell
# Always wrap in @() to ensure array
$items = @($jsonObject.items)
```

### 4. Exit Codes in Conditional Logic
Check `$LASTEXITCODE` immediately after external commands:
```powershell
& external-command
if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE"
}
```

---

## Best Practices Summary

1. **Always use `(?s)` flag** when parsing multiline XML/HTML tags
2. **Pass switch parameters directly**, not as strings in arrays
3. **Detect interactive mode** before choosing prompt strategy
4. **Preserve JSON structure** when loading and saving nested objects
5. **Use wildcards** for flexible file pattern matching
6. **Add debug logging** at each stage of complex operations
7. **Specify UTF-8 encoding** explicitly for all text file operations
8. **Validate parameters early** before expensive operations
9. **Return structured data** (hashtables/PSCustomObjects) from functions
10. **Test with real-world multiline content** when parsing text

---

## Related Resources

- [PowerShell Regular Expressions](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_regular_expressions)
- [PowerShell Advanced Parameters](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters)
- [Console Class Documentation](https://learn.microsoft.com/en-us/dotnet/api/system.console)
