#!/usr/bin/env python3
"""
Validates requirement acceptance criteria from spec files.

This is a thin wrapper around the PowerShell implementation at
scripts/validate-requirement.ps1, providing a cross-platform Python interface.

Usage:
    py -3 scripts/validate-requirement.py S-0001
    python scripts/validate-requirement.py S-0002

Exit Codes:
    0 - All acceptance criteria passed
    1 - One or more acceptance criteria failed
    2 - Invalid arguments or requirement not found
"""

import subprocess
import sys
import os
from pathlib import Path


def find_project_root() -> Path:
    """Locate the project root by searching for felix/ and specs/ directories."""
    current = Path.cwd()
    
    for _ in range(10):  # Max depth
        if (current / "felix").is_dir() and (current / "specs").is_dir():
            return current
        parent = current.parent
        if parent == current:
            break
        current = parent
    
    # Fallback: assume script is in scripts/ directory
    script_dir = Path(__file__).resolve().parent
    return script_dir.parent


def get_powershell_executable() -> str:
    """Find the appropriate PowerShell executable."""
    # Try pwsh (PowerShell Core) first, then fall back to powershell
    for exe in ["pwsh", "powershell"]:
        try:
            result = subprocess.run(
                [exe, "-Version"],
                capture_output=True,
                timeout=5
            )
            if result.returncode == 0:
                return exe
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    
    # Default to powershell on Windows
    if sys.platform == "win32":
        return "powershell"
    return "pwsh"


def main():
    """Main entry point."""
    # Handle help flag
    if len(sys.argv) == 2 and sys.argv[1] in ["-h", "--help", "/?", "-?"]:
        print(__doc__)
        print("\nExample:")
        print("  py -3 scripts/validate-requirement.py S-0002")
        print("\nThis will validate the acceptance criteria defined in the")
        print("spec file for requirement S-0002.")
        return 0
    
    # Validate arguments
    if len(sys.argv) != 2:
        print("Usage: py -3 scripts/validate-requirement.py <requirement-id>", file=sys.stderr)
        print("Example: py -3 scripts/validate-requirement.py S-0002", file=sys.stderr)
        return 2
    
    requirement_id = sys.argv[1]
    
    # Find project root and PowerShell script
    project_root = find_project_root()
    ps_script = project_root / "scripts" / "validate-requirement.ps1"
    
    if not ps_script.exists():
        print(f"Error: PowerShell validation script not found at {ps_script}", file=sys.stderr)
        return 2
    
    # Get PowerShell executable
    ps_exe = get_powershell_executable()
    
    # Build command
    cmd = [
        ps_exe,
        "-ExecutionPolicy", "Bypass",
        "-NoProfile",
        "-File", str(ps_script),
        requirement_id
    ]
    
    # Execute PowerShell script, passing through stdout/stderr
    try:
        result = subprocess.run(
            cmd,
            cwd=str(project_root),
            # Don't capture - let output stream directly to console
            stdin=subprocess.DEVNULL
        )
        return result.returncode
    except FileNotFoundError:
        print(f"Error: PowerShell executable '{ps_exe}' not found", file=sys.stderr)
        print("Please ensure PowerShell is installed and in PATH", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("\nValidation interrupted by user", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
