# PowerShell Learnings & Gotchas

Technical learnings for working with PowerShell in the Felix project. Covers parameter binding, Python interop, scripting pitfalls, and debugging patterns.

---

## Parameter Binding & Python Invocation

### Issue: PowerShell Parameter Binding Error

**Symptom**: `A positional parameter cannot be found that accepts argument 'validate-requirement.py'`

**Root Cause**: PowerShell's parameter binding system interprets script arguments as cmdlet parameters when using certain invocation patterns.

**What Happened**:

1. Initial code: `python "$scriptPath" "$requirementId"`
2. PowerShell tokenizes this and tries to match arguments to parameters
3. If `python` resolves to a Function or Alias (not Application), PowerShell applies its parameter binding rules
4. The script path gets misinterpreted as a parameter name, causing the error

**Failed Solutions** (in chronological order):

#### Attempt 1: cmd.exe with String Concatenation

```powershell
# ❌ FAILED - cmd.exe quote parsing issues
$commandLine = "`"$pythonCmd`" `"$arg1`" `"$arg2`""
$output = & cmd /c $commandLine 2>&1
# Problem: cmd.exe has different quoting rules, -3 flag treated as cmd option
```

#### Attempt 2: Start-Process with -Wait

```powershell
# ❌ FAILED - Deadlock with py.exe launcher
$process = Start-Process `
    -FilePath $pythonCmd `
    -ArgumentList $argString `
    -Wait -PassThru `
    -RedirectStandardOutput $tempOut `
    -RedirectStandardError $tempErr
# Problem: py.exe launcher + redirected streams = deadlock (see PYTHON.md)
```

#### Attempt 3: Array Splatting (@)

```powershell
# ❌ FAILED - Still triggers parameter binding
$allArgs = @($pythonArgs) + @($scriptPath, $reqId)
$output = & $pythonCmd @allArgs 2>&1
# Problem: Splatting operator @ can still trigger parameter binding in some contexts
```

#### Final Solution: Direct Array Expansion

```powershell
# ✅ CORRECT - Bypasses parameter binding
$params = @('-3', $scriptPath, $reqId)
$output = & $pythonCmd $params 2>&1
$exitCode = $LASTEXITCODE

# Key: Pass array directly (not splatted), let PowerShell expand it
# This treats each element as a literal argument, not a parameter name
```

**Why This Works**:

- Call operator `&` with direct array passing treats the executable as external command
- Each array element becomes a positional argument passed to the process
- PowerShell doesn't attempt parameter binding for external applications when array is passed this way
- The `2>&1` redirection merges stderr into success stream for unified output

**Comparison Table**:

| Approach                          | Parameter Binding | Deadlock Risk | Quote Handling | Verdict              |
| --------------------------------- | ----------------- | ------------- | -------------- | -------------------- |
| String concatenation with cmd.exe | Low               | Low           | Complex        | ❌ Unreliable        |
| Start-Process with -Wait          | Low               | **HIGH**      | Good           | ❌ Deadlocks         |
| Array splatting (@)               | Medium            | Low           | Good           | ❌ Context-dependent |
| Direct array passing              | **None**          | Low           | Automatic      | ✅ Reliable          |

---

### Command Type Verification

**Symptom**: Python resolution succeeds but invocation still fails with parameter binding errors.

**Root Cause**: `Get-Command` can return Functions/Aliases that shadow actual executables.

**Anti-Pattern**:

```powershell
# ❌ WRONG - Doesn't verify command type
$pythonCmd = Get-Command python | Select-Object -ExpandProperty Source
& $pythonCmd $args  # May fail if 'python' is a Function
```

**Pattern**:

```powershell
# ✅ CORRECT - Verify it's an Application, not Function/Alias
function Resolve-PythonCommand {
    $candidates = @('py', 'python', 'python3')

    foreach ($cmd in $candidates) {
        $resolved = Get-Command $cmd -ErrorAction SilentlyContinue

        # CRITICAL: Must be CommandType 'Application', not 'Function' or 'Alias'
        if ($resolved -and $resolved.CommandType -eq 'Application') {
            return @{
                cmd = $resolved.Source
                args = @()
            }
        }
    }

    throw "No Python interpreter found"
}
```

**Why This Matters**:

- User PowerShell profiles may define `python` as a function/alias
- Functions trigger PowerShell's parameter binding system
- Applications are treated as external processes with literal arguments
- **Always verify `CommandType -eq 'Application'`** before invoking

---

## Code Evolution: Invoking Python Scripts

**Evolution Timeline**:

```powershell
# ITERATION 1: Naive string interpolation
# ❌ FAILS: Parameter binding error
python "$scriptPath" "$arg"

# ITERATION 2: Quote everything
# ❌ FAILS: Still parameter binding error
& "python" "$scriptPath" "$arg"

# ITERATION 3: Use cmd.exe
# ❌ FAILS: cmd.exe quote parsing, py.exe flags misinterpreted
$cmdLine = "`"$python`" `"$arg1`" `"$arg2`""
& cmd /c $cmdLine

# ITERATION 4: Start-Process with redirects
# ❌ FAILS: Deadlock with py.exe launcher
Start-Process -FilePath $python -ArgumentList $args -Wait -RedirectStandardOutput ...

# ITERATION 5: Array splatting
# ❌ FAILS: Context-dependent parameter binding
$allArgs = @($arg1, $arg2)
& $python @allArgs

# ITERATION 6: Direct array passing ✅ FINAL SOLUTION
$params = @($arg1, $arg2)
$output = & $python $params 2>&1
$exitCode = $LASTEXITCODE
```

**Key Insight**: PowerShell's parameter binding is sophisticated but fragile. The safest pattern is direct array passing with the call operator.

---

## Environment & Configuration

### Python Resolution Strategy

**Priority Order**:

1. Config file explicit path: `felix/config.json` → `python.executable`
2. py launcher: `py -3` (Windows-specific, most reliable on Windows)
3. Direct python: `python3` or `python` (cross-platform fallback)

**Implementation**:

```powershell
function Resolve-PythonCommand {
    param([hashtable]$Config)

    # 1. Check config override
    if ($Config.python.executable) {
        $cmd = Get-Command $Config.python.executable -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.CommandType -eq 'Application') {
            return @{
                cmd = $cmd.Source
                args = $Config.python.args ?? @()
            }
        }
    }

    # 2. Try py launcher
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py -and $py.CommandType -eq 'Application') {
        return @{ cmd = $py.Source; args = @('-3') }
    }

    # 3. Fallback to python
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python -and $python.CommandType -eq 'Application') {
        return @{ cmd = $python.Source; args = @() }
    }

    throw "No Python interpreter found. Install Python 3.8+ or configure python.executable in config.json"
}

# CRITICAL: Resolve Python ONCE at startup, not per-invocation
$pythonInfo = Resolve-PythonCommand -Config $config
if (-not $pythonInfo) {
    Write-Host "ERROR: Python not found"
    exit 1
}
```

**Why Resolve Once**:

- Avoid repeated `Get-Command` overhead
- Ensure consistent Python version throughout execution
- Fail fast if Python unavailable

---

## ErrorActionPreference & Stderr

**Symptom**: PowerShell throws `NativeCommandError` or terminates when running external commands that write to stderr, even when the command succeeds.

**Root Cause**: When `$ErrorActionPreference = "Stop"` (common in scripts), PowerShell treats **any stderr output from native commands as terminating errors**.

**Example** - uvicorn startup logs go to stderr:

```powershell
$ErrorActionPreference = "Stop"

# This FAILS even though the command is working:
& python -m uvicorn main:app 2>&1
# ERROR: py.exe : INFO:     Uvicorn running on http://0.0.0.0:8080
```

**Anti-Pattern**:

```powershell
# ❌ WRONG - stderr becomes terminating error
$ErrorActionPreference = "Stop"
$output = & $pythonExe $args 2>&1
```

**Pattern**:

```powershell
# ✅ CORRECT - Temporarily allow stderr
$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"  # Allow stderr without termination

try {
    $output = & $pythonExe $args 2>&1
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $prevErrorAction  # Restore original
}
```

**Why This Matters**:

- Many tools (pytest, npm, uvicorn, pip) write INFO/WARNING to stderr
- `2>&1` merges stderr to stdout stream - but PowerShell still tracks the source
- With `$ErrorActionPreference = "Stop"`, stderr lines become terminating exceptions

---

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

## Unicode vs ASCII Text in Output

**Problem:** Unicode symbols (✓, ✗, ⚠) can cause PowerShell parser errors depending on file encoding, terminal capabilities, and PowerShell version.

**Solution:** Use ASCII text markers in brackets for consistency and reliability:

```powershell
# Reliable across all environments
Write-Host "[OK] Success" -ForegroundColor Green
Write-Host "[ERROR] Failed" -ForegroundColor Red
Write-Host "[WARN] Warning" -ForegroundColor Yellow
```

**Best Practice:**

- Use consistent text markers throughout scripts
- Markers should be self-explanatory and parseable
- Keep markers short (3-7 characters)
- Use colors to reinforce meaning

---

## Hashtables

### PSCustomObject vs Hashtable Mutability

**Problem:** PowerShell JSON deserialization creates PSCustomObject instances, which cannot have properties added/modified easily.

**Solution:** Convert PSCustomObject to hashtable for mutability:

```powershell
# Convert to hashtable
$hash = @{
    id = $obj.id
    title = $obj.title
    new_property = "value"  # Can add freely
}

# Or use ordered hashtable to preserve order
$hash = [ordered]@{
    id = $obj.id
    title = $obj.title
}
```

### Building Lookup Tables

**Pattern:** Convert array of objects to hashtable for O(1) lookups:

```powershell
$lookup = @{}
foreach ($req in $requirements) {
    $reqHash = @{ id = $req.id; title = $req.title }
    $lookup[$req.id] = $reqHash
}

# Fast lookup and modification
if ($lookup.ContainsKey("S-0001")) {
    $lookup["S-0001"].title = "Updated Title"
}
```

**Key Points:**

- Hashtables use `@{}` syntax
- Access with `$hash["key"]` or `$hash.key`
- Check existence with `.ContainsKey("key")`
- Use `[ordered]@{}` to preserve insertion order

---

## Parameter Passing

### Switch Parameters Must Be Bare, Not Strings

**Problem:** When calling scripts with switch parameters, you cannot pass them as strings in an array.

**Solution:** Pass switch parameters directly using parameter syntax:

```powershell
# CORRECT - explicit parameter splatting
$params = @{
    ProjectPath = $path
    SpecBuildMode = $true
    QuickMode = $true
}
& "script.ps1" @params
```

### Array Splatting vs Hashtable Splatting

**Problem:** Using array splatting (`@array`) causes PowerShell to bind parameters POSITIONALLY, which fails when the array contains parameter names.

**Key Rules:**

- `@array` → Positional parameter binding (left to right)
- `@hashtable` → Named parameter binding (by key name)
- Array splatting CANNOT contain parameter names (like `-Format`)
- Use hashtables when you need named parameters

---

## Interactive Console Detection

**Problem:** File-based prompts designed for UI/TUI integration hang in interactive terminal sessions.

**Solution:**

```powershell
$isInteractive = [Console]::IsInputRedirected -eq $false -and [Environment]::UserInteractive

if ($isInteractive) {
    $input = Read-Host "Your answer"
}
else {
    # Use file-based prompts for UI/TUI
}
```

---

## JSON Structure Handling

### Requirements.json Array Structure

**Problem:** Wrapping the entire JSON object in an array breaks the structure.

**Correct:**

```powershell
$requirementsData = @{ requirements = @() }
if (Test-Path $file) {
    $requirementsData = Get-Content $file -Raw | ConvertFrom-Json
}
$requirements = @($requirementsData.requirements)

# When saving back
$requirementsData = @{ requirements = $requirements }
$requirementsData | ConvertTo-Json -Depth 10 | Set-Content $file
```

---

## File Pattern Matching

### Wildcard Patterns for Duplicate Detection

**Problem:** Checking for exact filename `S-0054.md` fails when actual file is `S-0054-descriptive-slug.md`.

**Correct:**

```powershell
$existingSpec = Get-ChildItem -Path $dir -Filter "S-0054*.md" -ErrorAction SilentlyContinue
if ($existingSpec) {
    Write-Host "Found: $($existingSpec.FullName)"
}
```

---

## Appendix: Full Working Implementation

### Invoke-RequirementValidation

```powershell
function Invoke-RequirementValidation {
    param(
        [hashtable]$PythonInfo,
        [string]$ValidationScript,
        [string]$RequirementId
    )

    # Build flat argument array - DO NOT splat with @
    $params = @()
    if ($PythonInfo.args) {
        $params += $PythonInfo.args
    }
    $params += @($ValidationScript, $RequirementId)

    # Use call operator with direct array passing (not splatting)
    try {
        $output = & $PythonInfo.cmd $params 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }

    return @{ output = $output; exitCode = $exitCode }
}
```

---

## Best Practices Summary

1. Always verify `CommandType -eq 'Application'` before invoking
2. Use direct array passing: `& $cmd $params`, not `& $cmd @params`
3. Resolve Python once at startup, cache the result
4. Use `2>&1` to merge streams into unified output
5. Check `$LASTEXITCODE` immediately after invocation
6. Use `(?s)` flag for multiline regex matching
7. Prefer ASCII text markers over Unicode symbols
8. Use hashtable splatting for named parameters, not array splatting
9. Convert PSCustomObject to hashtable before mutation
10. Use wildcard patterns with `Get-ChildItem -Filter` for flexible file matching
