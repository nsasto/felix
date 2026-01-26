# Validation Requirement Bug - Complete Debugging History

**Date**: January 26, 2026  
**Issue**: `felix-agent.ps1` fails when calling Python validation script with parameter binding error  
**Status**: Fixed after multiple root cause discoveries

---

## Original Symptom

```
[VALIDATION] All plan tasks complete. Running validation...
C:\dev\Felix\felix-agent.ps1 : A positional parameter cannot be found that accepts argument 'validate-requirement.py'.
At line:1 char:1
+ .\felix-agent.ps1 C:\dev\felix\
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidArgument: (:) [felix-agent.ps1], ParameterBindingException
    + FullyQualifiedErrorId : PositionalParameterNotFound,felix-agent.ps1
```

**Context**: Error occurred when felix-agent.ps1 tried to run validation after completing all tasks for a requirement.

---

## Root Causes Discovered (Chronologically)

### Root Cause #1: Python Subprocess Deadlock

**Discovery**: Validation script would hang indefinitely with no error output.

**Investigation**:

- Process tree: `PowerShell → py.exe → python.exe → subprocess (uvicorn)`
- Using `subprocess.run(capture_output=True)` with verbose commands
- Pipe buffer (64KB on Windows) fills with uvicorn startup logs
- Child process blocks waiting for pipe to be read
- Parent `subprocess.run()` blocks waiting for child to complete
- **Classic pipe buffer deadlock**

**Solution**: Changed to `capture_output=False` in `validate-requirement.py`

```python
# Before (DEADLOCKS)
process = subprocess.run(
    command,
    capture_output=True,  # ❌ Creates pipes that can fill
    text=True,
    timeout=120,
)

# After (WORKS)
process = subprocess.run(
    command,
    capture_output=False,  # ✅ Streams directly to console
    text=True,
    timeout=120,
)
```

**Files Modified**: `scripts/validate-requirement.py`

---

### Root Cause #2: Wrong Try/Catch Block Catching Validation Errors

**Discovery**: Validation errors were being reported as "ERROR during droid execution" instead of showing actual validation failures.

**Investigation**:

- All validation code was inside the try/catch block for droid exec (lines 777-1207)
- Any error in validation, guardrails, or signal processing got caught by the droid error handler
- Error messages were misleading

**Solution**: Restructured try/catch to wrap ONLY droid exec

```powershell
# Before: Everything inside one giant try/catch
try {
    $output = $fullPrompt | droid exec ...
    Write-Host $output
    Set-Content output.log $output

    # Guardrail checks
    # Signal processing
    # Validation calls
    # ... (400+ lines)
}
catch {
    Write-Host "ERROR during droid execution: $_"  # ❌ Catches everything
}

# After: Separate concerns
try {
    $output = $fullPrompt | droid exec ...
    $droidSuccess = $true
}
catch {
    Write-Host "ERROR during droid execution: $_"  # ✅ Only droid errors
    exit 1
}

# Post-droid processing outside try/catch
Write-Host $output
Set-Content output.log $output
# Guardrails, signals, validation all run here
```

**Files Modified**: `felix-agent.ps1` (major restructuring)

---

### Root Cause #3: PowerShell Array Passing Issue

**Discovery**: Even after fixes #1 and #2, the "positional parameter" error persisted.

**Investigation**:

- Error message showed PowerShell couldn't parse arguments to validation function
- Initially tried: `& $pythonExe $pythonArgs $ValidationScript $RequirementId`
- PowerShell was treating `$pythonArgs` (an array) as a single argument object
- The validation script path appeared as the second "parameter" to PowerShell's parameter binder
- Parameter binding system got confused and threw the error

**Attempted Solutions** (chronological):

#### Attempt 1: Direct Array Passing (Failed)

```powershell
# ❌ Still failed - array passed as object
$params = @()
if ($PythonInfo.args) {
    $params += $PythonInfo.args
}
$params += @($ValidationScript, $RequirementId)
$output = & $PythonInfo.cmd $params 2>&1
```

#### Attempt 2: Conditional Expansion (Failed)

```powershell
# ❌ Still failed - wrong operator
if ($pythonArgs -and $pythonArgs.Count -gt 0) {
    $output = & $pythonExe $pythonArgs $ValidationScript $RequirementId 2>&1
}
```

#### Final Solution: Proper Array Splatting (Success)

```powershell
# ✅ Works correctly
if ($pythonArgs -and $pythonArgs.Count -gt 0) {
    # Build complete argument array
    $allArgs = $pythonArgs + @($ValidationScript, $RequirementId)
    # Splat with @ to expand each element as separate argument
    $output = & $pythonExe @allArgs 2>&1
}
else {
    # Direct invocation without launcher args
    $output = & $pythonExe $ValidationScript $RequirementId 2>&1
}
```

**Key Insight**:

- Without `@`: PowerShell sees array as single parameter
- With `@`: PowerShell expands array elements as separate positional arguments
- Must combine all args into one array first, then splat

**Files Modified**: `felix-agent.ps1` (`Invoke-RequirementValidation` function)

---

### Root Cause #4: $ErrorActionPreference + Stderr = Terminating Error

**Discovery**: When validation runs, PowerShell throws `NativeCommandError` even when command succeeds.

**Investigation**:

- `felix-agent.ps1` sets `$ErrorActionPreference = "Stop"` at line 18
- Many tools (uvicorn, pytest, npm) write INFO/WARNING to stderr, not stdout
- With `$ErrorActionPreference = "Stop"`, stderr output from native commands becomes terminating error
- Error message shows stderr content as if it were an error: `py.exe : INFO: Uvicorn running...`

**Solution**: Temporarily change ErrorActionPreference during Python execution

```powershell
# ✅ Correct approach
$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"  # Allow stderr without termination

try {
    $output = & $pythonExe @allArgs 2>&1
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $prevErrorAction  # Always restore
}
```

**Why This Matters**:

- `2>&1` merges stderr into success stream, but PowerShell still tracks the source
- Each stderr line can trigger `NativeCommandError` with `$ErrorActionPreference = "Stop"`
- Common tools legitimately use stderr for logging
- Must allow stderr during external command execution

**Files Modified**: `felix-agent.ps1` (`Invoke-RequirementValidation` function)

---

## Final Working Code

### Invoke-RequirementValidation Function

```powershell
function Invoke-RequirementValidation {
    param(
        [hashtable]$PythonInfo,
        [string]$ValidationScript,
        [string]$RequirementId
    )

    $pythonExe = $PythonInfo.cmd
    $pythonArgs = $PythonInfo.args

    Write-Host "[VALIDATION] Python: $pythonExe"
    Write-Host "[VALIDATION] Python args: $($pythonArgs -join ' ')"
    Write-Host "[VALIDATION] Script: $ValidationScript"
    Write-Host "[VALIDATION] Requirement: $RequirementId"

    # Temporarily allow stderr (Root Cause #4)
    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        if ($pythonArgs -and $pythonArgs.Count -gt 0) {
            # Root Cause #3 - Proper array splatting
            $allArgs = $pythonArgs + @($ValidationScript, $RequirementId)
            $output = & $pythonExe @allArgs 2>&1
        }
        else {
            $output = & $pythonExe $ValidationScript $RequirementId 2>&1
        }
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }
    finally {
        $ErrorActionPreference = $prevErrorAction
    }

    return @{ output = $output; exitCode = $exitCode }
}
```

### validate-requirement.py (Relevant Portion)

```python
# Root Cause #1 - No capture_output
process = subprocess.run(
    command,
    shell=True,
    cwd=working_dir,
    capture_output=False,  # ✅ Stream to console, no deadlock
    text=True,
    timeout=120,
)
```

---

## Timeline of Fixes

1. **Day 1**: Discovered subprocess deadlock → Changed `capture_output=True` to `False`
2. **Day 1**: Discovered error mislabeling → Restructured try/catch blocks
3. **Day 1**: Discovered parameter binding issue → Multiple attempts with array passing
4. **Day 1**: Discovered ErrorActionPreference trap → Added temporary Continue mode
5. **Day 1**: Final fix with proper array splatting → **RESOLVED**

---

## Lessons Learned

### For PowerShell

1. **Array Splatting**: Use `@array` to expand, not just `$array`
2. **Error Action**: External commands may legitimately use stderr - handle carefully
3. **Command Types**: Always verify `CommandType -eq 'Application'` before invoking
4. **Try/Catch Scope**: Keep try/catch blocks focused on single operation, not entire workflows

### For Python on Windows

1. **Pipe Buffers**: Never use `capture_output=True` with verbose commands
2. **Process Trees**: Be aware of launcher depth (pwsh → py.exe → python.exe)
3. **Stderr Usage**: Many tools use stderr for info logs, not just errors

### For Debugging

1. **Test Isolation**: Run problematic command directly in fresh PowerShell first
2. **Add Debug Output**: Temporary Write-Host statements reveal argument issues
3. **Check Process Tree**: `Get-Process` during hang shows what's blocking
4. **Error Action Matters**: Try with `-ErrorAction Continue` to see if error is spurious

---

## Documentation Updates

All fixes documented in:

- `LEARNINGS.md` - Technical deep-dives on each issue
- This file - Complete debugging journey
- Inline comments in `felix-agent.ps1` and `validate-requirement.py`

---

## Testing Verification

To verify the fix works:

```powershell
# Run felix agent
.\felix-agent.ps1 C:\dev\Felix

# Should now properly:
# 1. Run validation without hanging
# 2. Show actual validation errors (not "droid execution" errors)
# 3. Handle stderr from uvicorn/pytest gracefully
# 4. Pass arguments correctly to Python
```

**Expected Output** (when validation runs):

```
[VALIDATION] All plan tasks complete. Running validation...
[VALIDATION] Python: C:\WINDOWS\py.exe
[VALIDATION] Python args: -3
[VALIDATION] Script: C:\dev\Felix\scripts\validate-requirement.py
[VALIDATION] Requirement: S-0005
============================================================
  Validating Requirement: S-0005
============================================================
[... validation output ...]
✅ Validation PASSED!
```

---

## Related Files

- `felix-agent.ps1` - Main agent script (try/catch restructure, validation function)
- `scripts/validate-requirement.py` - Validation script (capture_output fix)
- `LEARNINGS.md` - Technical documentation of all issues
- `felix/config.json` - Python executable configuration

---

**Status**: ✅ All issues resolved and documented
