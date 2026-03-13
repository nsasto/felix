# Platform Learnings (Windows & Cross-Language)

Technical learnings for Windows-specific quirks, silent failure patterns, and cross-language best practices in the Felix project.

---

## py.exe Launcher Behavior

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

---

## Unicode Output on Windows

**Problem**: Python prints to stdout fail or show garbled characters in PowerShell.

**Root Cause**: Windows console defaults to legacy codepages (e.g., CP437), not UTF-8.

**Solution** (Python side):

```python
import sys

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
```

**PowerShell side**:

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"
```

---

## Silent Killers Gallery

"Silent Killers" are issues that don't throw errors but cause hangs, incorrect behavior, or mysterious failures.

### 1. The Invisible Hang

**Symptom**: Script appears to run but never completes, no error output.

**Cause**: Subprocess waiting for stdin that will never come.

**Detection**:

```powershell
Get-Process | Where-Object { $_.ProcessName -match 'python|py' } | Format-Table Id, Handles, CPU
# If CPU is 0 and Handles is steady, it's likely waiting on I/O
```

**Prevention**:

```python
subprocess.run(
    command,
    stdin=subprocess.DEVNULL,  # Prevent waiting on stdin
)
```

### 2. The Phantom Function

**Symptom**: Command works in fresh PowerShell session, fails in agent.

**Cause**: PowerShell profile or module auto-loading defines function with same name as executable.

**Detection**:

```powershell
Get-Command python | Select-Object CommandType, Source
# CommandType should be 'Application', not 'Function' or 'Alias'
```

### 3. The Quote Escape Spiral

**Symptom**: Arguments with spaces work manually but fail in automation.

**Cause**: Multiple layers of quote interpretation (PowerShell → cmd → subprocess).

**Example**:

```powershell
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

**Prevention**:

```python
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

## Exit Codes

Felix uses distinct exit codes to indicate different completion states:

| Exit Code | Meaning                | What Happened                                             |
| --------- | ---------------------- | --------------------------------------------------------- |
| 0         | Success                | Requirement complete and validated                        |
| 1         | Error                  | General execution failure (droid errors, file I/O issues) |
| 2         | Blocked (backpressure) | Backpressure failures exceeded max retries (default: 3)   |
| 3         | Blocked (validation)   | Validation failures exceeded max retries (default: 2)     |

**Blocked Requirements**: When exit code 2 or 3 occurs, the requirement is automatically marked as "blocked" in `felix/requirements.json`. To unblock, fix the underlying issues then manually change the status back to "planned".

**Retry Configuration** (in `felix/config.json`):

- Backpressure retries: `backpressure.max_retries` (default: 3)
- Validation retries: `validation.max_validation_retries` (default: 1, allows 2 total attempts)
- Blocking behavior: `validation.mark_blocked_on_failure` (default: true)
- Exit on block: `validation.exit_on_blocked` (default: true)

---

## Debugging Checklist

When something hangs or fails mysteriously:

- [ ] Check CommandType: `Get-Command <cmd> | Select CommandType`
- [ ] Verify process tree: `Get-Process | Where-Object { $_.ProcessName -match 'python|py' }`
- [ ] Test Python isolation: `py -3 -c "print('test')"` (should complete instantly)
- [ ] Check for profile functions: `$PROFILE` existence and contents
- [ ] Verify capture_output: Is it `False` in Python subprocess calls?
- [ ] Test with minimal arguments: Remove all args except script path
- [ ] Check encoding: Add UTF-8 reconfiguration to Python script
- [ ] Look for stdin hangs: Add `stdin=subprocess.DEVNULL` to subprocess calls

## Common Error Messages

| Error Message                                                      | Root Cause                           | Solution                                           |
| ------------------------------------------------------------------ | ------------------------------------ | -------------------------------------------------- |
| "A positional parameter cannot be found that accepts argument 'X'" | PowerShell parameter binding         | Use direct array passing: `& $cmd $params`         |
| Script hangs with no output                                        | Pipe buffer deadlock                 | Set `capture_output=False` in Python               |
| "Unknown option: -3"                                               | cmd.exe interpreting py.exe flag     | Don't use cmd.exe, use direct invocation           |
| Process stays alive after timeout                                  | Timeout doesn't kill child processes | Kill process tree, not just parent                 |
| "python: command not found" on Windows                             | py.exe not in PATH                   | Install Python from python.org (includes launcher) |
| Garbled unicode characters                                         | Console codepage mismatch            | Add UTF-8 reconfiguration to Python script         |

---

## Spec Writing Best Practices

### Validation Criteria with Backticks

**Symptom**: Validation script tries to execute file paths or non-command text as shell commands.

**Root Cause**: The validation script extracts text in backticks from acceptance criteria and attempts to execute it as a command.

**Anti-Pattern**:

```markdown
## Validation Criteria

- [ ] Settings save successfully: Modify setting, save, verify `felix/config.json` updated
```

**Pattern**:

```markdown
## Validation Criteria

<!-- For automated validation with executable commands -->

- [ ] Tests pass: `pytest` (exit code 0)
- [ ] Lint clean: `npm run lint` (exit code 0)

<!-- For manual/UI validation without executable commands -->

- [x] Settings save successfully: Manual verification - modify setting, save, verify config.json updated
```

**Rules**:

1. **Backticks = Executable Command**: Only use backticks for shell commands that can be executed
2. **Manual Checks**: Prefix with "Manual verification -" and mark as [X] to skip automation
3. **File References**: Don't use backticks for file paths in descriptions
4. **Exit Code/Status**: Include expected outcome in parentheses for automated checks

---

## Cross-Language Best Practices

1. Minimize process tree depth (avoid launcher wrappers when possible)
2. Stream output instead of capturing it for real-time feedback
3. Fail fast with clear error messages
4. Document all environment assumptions (Python version, PATH, etc.)
5. Test in clean environment, not just your customized shell
