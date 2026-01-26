# Project Felix: Technical Learnings & Anti-Patterns

**Document Purpose**: Internal knowledge base documenting critical technical issues, debugging sessions, and solutions encountered during Felix development. Reading this document should prevent 90%+ of the friction future developers will face.

**Context**: Felix is a PowerShell-based AI agent executor that validates requirements using a Python script. The system runs on Windows with PowerShell 7+, Python 3.12+, and the py.exe launcher.

---

## Table of Contents

1. [Process Management & Deadlocks](#process-management--deadlocks)
2. [PowerShell/Python Interoperability](#powershellpython-interoperability)
3. [Windows-Specific Quirks](#windows-specific-quirks)
4. [Silent Killers Gallery](#silent-killers-gallery)
5. [Code Evolution: Anti-Patterns vs. Patterns](#code-evolution-anti-patterns-vs-patterns)
6. [Environment & Configuration](#environment--configuration)
7. [Quick Reference](#quick-reference)

---

## Process Management & Deadlocks

### Issue 1: Python Subprocess Pipe Buffer Deadlock

**Symptom**: Validation script hangs indefinitely when running commands, no error messages, PowerShell process becomes unresponsive.

**Root Cause**: Classic pipe buffer deadlock in process tree hierarchy:

```
PowerShell → py.exe (launcher) → python.exe (interpreter) → subprocess (actual command)
```

When using `subprocess.run(capture_output=True)`:

- Python redirects stdout/stderr to internal pipes (typically 64KB buffer on Windows)
- If child process output exceeds buffer size, it blocks waiting for reader
- But `subprocess.run()` doesn't read until process completes
- **Deadlock**: Child waits for Python to read, Python waits for child to finish

**Technical Details**:

- py.exe is a launcher wrapper, not the actual Python interpreter
- It spawns python.exe as a child process and waits for completion
- When parent (PowerShell) uses `-Wait` or similar blocking mechanisms, it creates a three-level process tree where any pipe buffer overflow causes cascading deadlock
- Buffer fills especially fast with verbose output from pytest, npm test, or FastAPI startup logs

**Anti-Pattern**:

```python
# ❌ WRONG - Will hang on large output
process = subprocess.run(
    command,
    shell=True,
    cwd=working_dir,
    capture_output=True,  # Creates pipe deadlock risk
    text=True,
    timeout=120,
)
output = process.stdout + process.stderr
```

**Pattern**:

```python
# ✅ CORRECT - Streams to console, no deadlock
process = subprocess.run(
    command,
    shell=True,
    cwd=working_dir,
    capture_output=False,  # Output streams directly to console
    text=True,
    timeout=120,
)
# Accept that output is not captured - it's visible in console
return (process.returncode == 0), "Output streamed to console", process.returncode
```

**Alternative Pattern** (if you MUST capture output):

```python
# Use Popen with non-blocking reads or larger buffers
import subprocess
from threading import Thread
from queue import Queue

def read_stream(stream, queue):
    for line in iter(stream.readline, ''):
        queue.put(line)
    stream.close()

process = subprocess.Popen(
    command,
    shell=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

# Read streams in separate threads to prevent deadlock
stdout_queue = Queue()
stderr_queue = Queue()
Thread(target=read_stream, args=(process.stdout, stdout_queue)).start()
Thread(target=read_stream, args=(process.stderr, stderr_queue)).start()

process.wait()
```

**Key Takeaway**: On Windows with py.exe launcher, **never use `capture_output=True` for long-running or verbose commands**. Stream to console instead.

---

## PowerShell/Python Interoperability

### Issue 2: PowerShell Parameter Binding Error

**Symptom**: `A positional parameter cannot be found that accepts argument 'validate-requirement.py'`

**Root Cause**: PowerShell's parameter binding system interprets script arguments as cmdlet parameters when using certain invocation patterns.

**What Happened**:

1. Initial code: `python "$validationScript" "$requirementId"`
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
# Problem: py.exe launcher + redirected streams = deadlock (see Issue 1)
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

### Issue 3: Command Type Verification

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

## Windows-Specific Quirks

### Issue 4: py.exe Launcher Behavior

**Background**: Windows Python installations include `py.exe` - the Python Launcher for Windows.

**How It Works**:

```
User runs: py -3 script.py arg1
          ↓
py.exe reads: Shebang, config, installed versions
          ↓
py.exe spawns: C:\Python312\python.exe script.py arg1
          ↓
py.exe waits: For child process to complete
          ↓
py.exe exits: With child's exit code
```

**Implications**:

1. **Process Tree Depth**: Every `py` invocation adds a process layer
   - Direct: `python.exe` (1 process)
   - Via launcher: `py.exe` → `python.exe` (2 processes)
   - From PowerShell: `pwsh.exe` → `py.exe` → `python.exe` (3 processes)

2. **Redirection Complexity**: When you redirect streams at the PowerShell level:
   - PowerShell captures py.exe's streams
   - py.exe captures python.exe's streams
   - **Double buffering** increases deadlock risk

3. **Argument Passing**: py.exe forwards arguments as-is, but:
   - Quoting may be re-interpreted at each level
   - Some py.exe flags (like `-3`) are consumed before forwarding

**Best Practice**:

```powershell
# For production: Resolve to actual python.exe if possible
$pythonExe = & py -3 -c "import sys; print(sys.executable)"
# Then use $pythonExe directly, bypassing launcher

# For development/scripts: Use py.exe but be aware of process depth
```

### Issue 5: Unicode Output on Windows

**Problem**: Python prints to stdout fail or show garbled characters in PowerShell.

**Root Cause**: Windows console defaults to legacy codepages (e.g., CP437), not UTF-8.

**Solution** (add to Python scripts):

```python
# At top of script, after imports
import sys

if sys.platform == "win32":
    # Force UTF-8 encoding for stdout/stderr
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
```

**PowerShell Side**:

```powershell
# In profile or script startup
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"
```

---

## Silent Killers Gallery

**"Silent Killers"** are issues that don't throw errors but cause hangs, incorrect behavior, or mysterious failures.

### 1. The Invisible Hang

**Symptom**: Script appears to run but never completes, no error output.

**Cause**: Subprocess waiting for stdin that will never come.

**Detection**:

```powershell
# Check if process is waiting on input
Get-Process | Where-Object { $_.ProcessName -match 'python|py' } | Format-Table Id, Handles, CPU
# If CPU is 0 and Handles is steady, it's likely waiting on I/O
```

**Prevention**:

```python
# Always specify stdin handling
subprocess.run(
    command,
    stdin=subprocess.DEVNULL,  # Prevent waiting on stdin
    # ... other args
)
```

### 2. The Phantom Function

**Symptom**: Command works in fresh PowerShell session, fails in agent.

**Cause**: PowerShell profile or module auto-loading defines function with same name as executable.

**Detection**:

```powershell
# Check if 'python' is a function
Get-Command python | Select-Object CommandType, Source
# CommandType should be 'Application', not 'Function' or 'Alias'
```

### 3. The ErrorActionPreference Stderr Trap

**Symptom**: PowerShell throws `NativeCommandError` or terminates when running external commands that write to stderr, even when the command succeeds.

**Root Cause**: When `$ErrorActionPreference = "Stop"` (common in scripts), PowerShell treats **any stderr output from native commands as terminating errors**.

**Example** - uvicorn startup logs go to stderr:

```powershell
$ErrorActionPreference = "Stop"

# This FAILS even though the command is working:
& python -m uvicorn main:app 2>&1
# ERROR: py.exe : INFO:     Uvicorn running on http://0.0.0.0:8080
#        + CategoryInfo          : NotSpecified: (...):String) [], RemoteException
#        + FullyQualifiedErrorId : NativeCommandError
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
- The error message is misleading - it shows the actual stderr content as if it were an error

**Detection**:

```powershell
# Check if your tool writes to stderr:
& your-command 2>stderr.txt
if (Test-Path stderr.txt) { Get-Content stderr.txt }
```

**Prevention**: Always verify CommandType (see Issue 3).

### 3. The Quote Escape Spiral

**Symptom**: Arguments with spaces work manually but fail in automation.

**Cause**: Multiple layers of quote interpretation (PowerShell → cmd → subprocess).

**Example**:

```powershell
# Original path
$path = "C:\Program Files\App\file.txt"

# PowerShell sees:     "C:\Program Files\App\file.txt"
# cmd.exe sees:        C:\Program Files\App\file.txt (quotes removed)
# Subprocess sees:     C:\Program, Files\App\file.txt (split on spaces)
```

**Prevention**:

```powershell
# Use array passing, not string concatenation
$args = @($path)  # PowerShell handles quoting automatically
& $command $args
```

### 4. The Exit Code Lie

**Symptom**: Process appears successful (exit code 0) but actually failed.

**Cause**: Checking exit code of wrapper, not actual command.

**Example**:

```powershell
# ❌ WRONG
Start-Process python -ArgumentList "script.py" -Wait -PassThru
# $LASTEXITCODE is Start-Process exit code (always 0), not python exit code

# ✅ CORRECT
& python script.py
$exitCode = $LASTEXITCODE  # Actual python exit code
```

### 5. The Timeout That Doesn't Timeout

**Symptom**: Script with timeout still hangs indefinitely.

**Cause**: Timeout applies to parent process, not child spawned by parent.

**Example**:

```python
# py.exe timeout doesn't kill python.exe child
subprocess.run(["py", "-3", "script.py"], timeout=30)
# If script.py spawns a child, timeout only kills py.exe, not child
```

**Prevention**:

```python
# Use process groups or kill entire tree
import psutil

process = subprocess.Popen(["py", "-3", "script.py"])
try:
    process.wait(timeout=30)
except subprocess.TimeoutExpired:
    # Kill entire process tree
    parent = psutil.Process(process.pid)
    for child in parent.children(recursive=True):
        child.kill()
    parent.kill()
```

---

## Code Evolution: Anti-Patterns vs. Patterns

### PowerShell: Invoking Python Scripts

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

### Python: Running Subprocess Commands

**Evolution Timeline**:

```python
# ITERATION 1: Basic capture_output
# ❌ FAILS: Pipe deadlock on verbose output
subprocess.run(cmd, shell=True, capture_output=True, text=True)

# ITERATION 2: Redirect to temp files
# ⚠️ WORKS but complex, file I/O overhead
with open(tmp_out, 'w') as out, open(tmp_err, 'w') as err:
    subprocess.run(cmd, shell=True, stdout=out, stderr=err)

# ITERATION 3: Stream to console ✅ FINAL SOLUTION
subprocess.run(cmd, shell=True, capture_output=False, text=True)
# Accept that output goes to console, not captured
```

**Key Insight**: For validation/testing, seeing output in real-time is more valuable than capturing it. Streaming prevents deadlocks and provides better UX.

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

### Configuration Schema

**felix/config.json**:

```json
{
  "python": {
    "executable": "py",
    "args": ["-3"]
  },
  "agent": {
    "max_iterations": 100,
    "timeout_seconds": 300
  },
  "validation": {
    "timeout_seconds": 120,
    "stream_output": true
  }
}
```

**Design Principles**:

- **Explicit over implicit**: Don't guess, make user specify
- **Validate early**: Check Python at startup, not first use
- **Fail fast**: Hard-stop on missing dependencies

---

## Quick Reference

### Debugging Checklist

When something hangs or fails mysteriously:

- [ ] Check CommandType: `Get-Command <cmd> | Select CommandType`
- [ ] Verify process tree: `Get-Process | Where-Object { $_.ProcessName -match 'python|py' }`
- [ ] Test Python isolation: `py -3 -c "print('test')"` (should complete instantly)
- [ ] Check for profile functions: `$PROFILE` existence and contents
- [ ] Verify capture_output: Is it `False` in Python subprocess calls?
- [ ] Test with minimal arguments: Remove all args except script path
- [ ] Check encoding: Add UTF-8 reconfiguration to Python script
- [ ] Look for stdin hangs: Add `stdin=subprocess.DEVNULL` to subprocess calls

### Common Error Messages

| Error Message                                                      | Root Cause                           | Solution                                           |
| ------------------------------------------------------------------ | ------------------------------------ | -------------------------------------------------- |
| "A positional parameter cannot be found that accepts argument 'X'" | PowerShell parameter binding         | Use direct array passing: `& $cmd $params`         |
| Script hangs with no output                                        | Pipe buffer deadlock                 | Set `capture_output=False` in Python               |
| "Unknown option: -3"                                               | cmd.exe interpreting py.exe flag     | Don't use cmd.exe, use direct invocation           |
| Process stays alive after timeout                                  | Timeout doesn't kill child processes | Kill process tree, not just parent                 |
| "python: command not found" on Windows                             | py.exe not in PATH                   | Install Python from python.org (includes launcher) |
| Garbled unicode characters                                         | Console codepage mismatch            | Add UTF-8 reconfiguration to Python script         |

### Best Practices Summary

**PowerShell**:

1. Always verify `CommandType -eq 'Application'` before invoking
2. Use direct array passing: `& $cmd $params`, not `& $cmd @params`
3. Resolve Python once at startup, cache the result
4. Use `2>&1` to merge streams into unified output
5. Check `$LASTEXITCODE` immediately after invocation

**Python**:

1. Use `capture_output=False` for long-running/verbose commands
2. Always specify `stdin=subprocess.DEVNULL` to prevent input hangs
3. Reconfigure stdout/stderr to UTF-8 on Windows
4. Use absolute paths when spawning subprocesses
5. Set timeouts on all subprocess calls

**Cross-Language**:

1. Minimize process tree depth (avoid launcher wrappers when possible)
2. Stream output instead of capturing it for real-time feedback
3. Fail fast with clear error messages
4. Document all environment assumptions (Python version, PATH, etc.)
5. Test in clean environment, not just your customized shell

---

## Appendix: The Full Working Implementation

### PowerShell: Invoke-RequirementValidation

```powershell
function Invoke-RequirementValidation {
    <#
    .SYNOPSIS
    Runs scripts/validate-requirement.py with a resolved Python command

    .DESCRIPTION
    Invokes Python validation script with proper argument passing to avoid
    PowerShell parameter binding issues and subprocess deadlocks.

    .PARAMETER PythonInfo
    Hashtable with keys: cmd (python executable path), args (array of flags like '-3')

    .PARAMETER ValidationScript
    Absolute path to validate-requirement.py

    .PARAMETER RequirementId
    Requirement ID to validate (e.g., 'S-0002')

    .OUTPUTS
    Hashtable with keys: output (string), exitCode (int)
    #>
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
    # This avoids PowerShell parameter binding and py.exe deadlocks
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

### Python: run_command

```python
def run_command(command: str, cwd: Path, timeout: int = 120) -> Tuple[bool, str, int]:
    """
    Run a validation command with proper subprocess handling.

    Streams output to console to avoid pipe buffer deadlocks.

    Args:
        command: Shell command to execute
        cwd: Working directory for command
        timeout: Maximum execution time in seconds

    Returns:
        Tuple of (success: bool, output_message: str, return_code: int)
    """
    print(f"  Running: {command}")

    try:
        # Handle 'cd dir && command' pattern
        actual_cwd = str(cwd)
        actual_cmd = command

        if command.startswith("cd "):
            parts = command.split("&&", 1)
            cd_part = parts[0].strip()
            dir_path = cd_part[3:].strip()

            if Path(dir_path).is_absolute():
                actual_cwd = dir_path
            else:
                actual_cwd = str(cwd / dir_path)

            if len(parts) > 1:
                actual_cmd = parts[1].strip()
            else:
                return True, "", 0

        # CRITICAL: capture_output=False to prevent pipe deadlock
        # Output streams directly to console for real-time feedback
        process = subprocess.run(
            actual_cmd,
            shell=True,
            cwd=actual_cwd,
            capture_output=False,  # Avoid pipe buffer deadlock
            stdin=subprocess.DEVNULL,  # Prevent waiting on stdin
            text=True,
            timeout=timeout,
        )

        success = process.returncode == 0
        return success, "Output streamed to console", process.returncode

    except subprocess.TimeoutExpired:
        return False, f"Command timed out after {timeout}s", 1
    except Exception as e:
        return False, f"Error running command: {e}", 1
```

---

**Document Version**: 1.0  
**Last Updated**: January 26, 2026  
**Maintainer**: Felix Development Team  
**Applies To**: Felix Agent v0.1.0+, Windows 10/11, PowerShell 7+, Python 3.8+
