# Python Learnings & Gotchas

Technical learnings for Python subprocess management, pipe handling, and encoding in the Felix project.

---

## Process Management & Deadlocks

### Subprocess Pipe Buffer Deadlock

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
# Use Popen with non-blocking reads
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

## Code Evolution: Running Subprocess Commands

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

## Appendix: Full Working Implementation

### run_command

```python
def run_command(command: str, cwd: Path, timeout: int = 120) -> Tuple[bool, str, int]:
    """
    Run a validation command with proper subprocess handling.
    Streams output to console to avoid pipe buffer deadlocks.
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
        process = subprocess.run(
            actual_cmd,
            shell=True,
            cwd=actual_cwd,
            capture_output=False,
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

## Best Practices Summary

1. Use `capture_output=False` for long-running/verbose commands
2. Always specify `stdin=subprocess.DEVNULL` to prevent input hangs
3. Reconfigure stdout/stderr to UTF-8 on Windows (see PLATFORM.md)
4. Use absolute paths when spawning subprocesses
5. Set timeouts on all subprocess calls
6. Kill the entire process tree on timeout, not just the parent
