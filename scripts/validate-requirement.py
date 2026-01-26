#!/usr/bin/env python3
"""
Felix Validation Script - Validates requirement acceptance criteria

Usage:
    python scripts/validate-requirement.py <requirement-id>
    
Example:
    python scripts/validate-requirement.py S-0002
    
Exit codes:
    0 - All acceptance criteria passed
    1 - One or more acceptance criteria failed
    2 - Invalid arguments or requirement not found
"""
import sys
import os
import re
import subprocess
import json
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
from datetime import datetime

# Fix Unicode output on Windows
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')


def find_project_root() -> Path:
    """Find the project root by looking for felix/ directory."""
    current = Path.cwd()
    
    # Check current directory and parents
    for path in [current] + list(current.parents):
        if (path / "felix").is_dir() and (path / "specs").is_dir():
            return path
    
    # Fallback: assume script is in scripts/ subdirectory
    script_dir = Path(__file__).resolve().parent
    if script_dir.name == "scripts":
        return script_dir.parent
    
    raise RuntimeError("Could not find project root (no felix/ and specs/ directories found)")


def load_requirements(project_root: Path) -> Dict[str, Any]:
    """Load felix/requirements.json."""
    req_file = project_root / "felix" / "requirements.json"
    if not req_file.exists():
        raise FileNotFoundError(f"Requirements file not found: {req_file}")
    
    with open(req_file) as f:
        return json.load(f)


def find_spec_file(project_root: Path, requirement_id: str) -> Optional[Path]:
    """Find the spec file for a requirement ID."""
    specs_dir = project_root / "specs"
    
    # First check requirements.json for explicit spec_path
    try:
        requirements = load_requirements(project_root)
        for req in requirements.get("requirements", []):
            if req.get("id") == requirement_id:
                spec_path = req.get("spec_path")
                if spec_path:
                    full_path = project_root / spec_path
                    if full_path.exists():
                        return full_path
    except Exception:
        pass
    
    # Fallback: search for file matching pattern
    pattern = f"{requirement_id}-*.md"
    matches = list(specs_dir.glob(pattern))
    
    if matches:
        return matches[0]
    
    # Try exact match
    exact = specs_dir / f"{requirement_id}.md"
    if exact.exists():
        return exact
    
    return None


def get_requirement_labels(project_root: Path, requirement_id: str) -> List[str]:
    """Get labels for a requirement from requirements.json."""
    try:
        requirements = load_requirements(project_root)
        for req in requirements.get("requirements", []):
            if req.get("id") == requirement_id:
                return req.get("labels", [])
    except Exception:
        pass
    
    return []


def parse_acceptance_criteria(spec_content: str) -> List[Dict[str, Any]]:
    """
    Parse acceptance criteria from spec markdown.
    
    Looks for section starting with "## Acceptance Criteria" and extracts
    checklist items. Each item can optionally include a command in backticks
    and expected outcome in parentheses.
    
    Example formats:
    - [ ] Backend starts: `python app/backend/main.py` (exit code 0)
    - [ ] Health endpoint responds: `curl http://localhost:8080/health` (status 200)
    - [x] Tests pass: `cd app/backend && pytest` (exit code 0)
    - [ ] Simple criterion without command
    
    Returns list of dicts with keys:
    - text: Full criterion text
    - command: Extracted command (if any)
    - expected: Expected outcome description (if any)
    - checked: Whether criterion is already marked complete
    """
    criteria = []
    
    # Find the Acceptance Criteria or Validation Criteria section
    # Prefer Validation Criteria if it exists (more specific testable commands)
    ac_pattern = re.compile(r"^##\s*Validation\s+Criteria", re.IGNORECASE | re.MULTILINE)
    match = ac_pattern.search(spec_content)
    
    # Fall back to Acceptance Criteria if no Validation Criteria section
    if not match:
        ac_pattern = re.compile(r"^##\s*Acceptance\s+Criteria", re.IGNORECASE | re.MULTILINE)
        match = ac_pattern.search(spec_content)
    
    if not match:
        return criteria
    
    # Get content from that section until next ## header or end
    section_start = match.end()
    next_section = re.search(r"^##\s+", spec_content[section_start:], re.MULTILINE)
    
    if next_section:
        section_content = spec_content[section_start:section_start + next_section.start()]
    else:
        section_content = spec_content[section_start:]
    
    # Parse checklist items
    # Match both top-level and nested checklist items
    item_pattern = re.compile(r"^[\s]*-\s*\[([ xX])\]\s*(.+)$", re.MULTILINE)
    
    for item_match in item_pattern.finditer(section_content):
        checked = item_match.group(1).lower() == "x"
        text = item_match.group(2).strip()
        
        criterion = {
            "text": text,
            "command": None,
            "expected": None,
            "checked": checked,
        }
        
        # Extract command from backticks
        cmd_match = re.search(r"`([^`]+)`", text)
        if cmd_match:
            criterion["command"] = cmd_match.group(1)
        
        # Extract expected outcome from parentheses at end
        expected_match = re.search(r"\(([^)]+)\)\s*$", text)
        if expected_match:
            criterion["expected"] = expected_match.group(1)
        
        criteria.append(criterion)
    
    return criteria


def get_label_based_commands(labels: List[str], project_root: Path) -> List[Dict[str, Any]]:
    """
    Get validation commands based on requirement labels.
    
    Labels map to commands:
    - backend → pytest in app/backend
    - frontend → npm test in app/frontend
    - agent → (no automatic tests for now)
    
    Returns list of dicts with keys:
    - command: The command to run
    - cwd: Directory to run command in
    - description: Human-readable description
    """
    commands = []
    
    if "backend" in labels:
        backend_dir = project_root / "app" / "backend"
        if backend_dir.exists():
            commands.append({
                "command": "python -m pytest",
                "cwd": str(backend_dir),
                "description": "backend pytest"
            })
    
    if "frontend" in labels:
        frontend_dir = project_root / "app" / "frontend"
        if frontend_dir.exists():
            commands.append({
                "command": "npm test",
                "cwd": str(frontend_dir),
                "description": "frontend npm test"
            })
    
    return commands


def run_command(command: str, cwd: Path, timeout: int = 120) -> Tuple[bool, str, int]:
    """
    Run a validation command.
    
    Returns (success, output, return_code).
    """
    print(f"  Running: {command}")
    
    try:
        # Handle cd commands by parsing and setting cwd
        actual_cwd = str(cwd)
        actual_cmd = command
        
        if command.startswith("cd "):
            parts = command.split("&&", 1)
            cd_part = parts[0].strip()
            # Extract directory from cd command
            dir_path = cd_part[3:].strip()
            
            # Handle absolute paths
            if Path(dir_path).is_absolute():
                actual_cwd = dir_path
            else:
                actual_cwd = str(cwd / dir_path)
            
            if len(parts) > 1:
                actual_cmd = parts[1].strip()
            else:
                # Just a cd command - skip
                return True, "", 0
        
        # Stream output to console to avoid pipe deadlock
        process = subprocess.run(
            actual_cmd,
            shell=True,
            cwd=actual_cwd,
            capture_output=False,
            text=True,
            timeout=timeout,
        )
        
        success = process.returncode == 0
        
        return success, "Output streamed to console", process.returncode
        
    except subprocess.TimeoutExpired:
        return False, f"Command timed out after {timeout}s", 1
    except Exception as e:
        return False, f"Error running command: {e}", 1


def validate_criterion(criterion: Dict[str, Any], project_root: Path) -> Tuple[bool, str]:
    """
    Validate a single acceptance criterion.
    
    Returns (passed, message).
    """
    text = criterion["text"]
    command = criterion["command"]
    expected = criterion["expected"]
    
    # If no command specified, we can't auto-validate
    if not command:
        return True, f"⚠️  Manual verification required: {text}"
    
    # Run the command
    success, output, return_code = run_command(command, project_root)
    
    # Check expected outcome if specified
    if expected:
        expected_lower = expected.lower()
        
        # Check for exit code expectations
        if "exit code 0" in expected_lower:
            if return_code != 0:
                return False, f"❌ Expected exit code 0, got {return_code}: {text}"
        elif "exit code" in expected_lower:
            # Extract expected exit code
            code_match = re.search(r"exit code (\d+)", expected_lower)
            if code_match:
                expected_code = int(code_match.group(1))
                if return_code != expected_code:
                    return False, f"❌ Expected exit code {expected_code}, got {return_code}: {text}"
        
        # Check for status code expectations (HTTP)
        if "status" in expected_lower:
            status_match = re.search(r"status\s*(\d+)", expected_lower)
            if status_match:
                expected_status = status_match.group(1)
                if expected_status not in output:
                    return False, f"❌ Expected status {expected_status} not found: {text}"
    
    # Default: just check command succeeded
    if success:
        return True, f"✅ {text}"
    else:
        return False, f"❌ Command failed: {text}"


def validate_requirement(requirement_id: str) -> int:
    """
    Validate a requirement by checking its acceptance criteria.
    
    Returns exit code: 0 for success, 1 for failure, 2 for errors.
    """
    print(f"\n{'='*60}")
    print(f"  Validating Requirement: {requirement_id}")
    print(f"{'='*60}\n")
    
    try:
        project_root = find_project_root()
        print(f"Project root: {project_root}")
    except Exception as e:
        print(f"Error: {e}")
        return 2
    
    # Find spec file
    spec_file = find_spec_file(project_root, requirement_id)
    if not spec_file:
        print(f"Error: Could not find spec file for {requirement_id}")
        return 2
    
    print(f"Spec file: {spec_file}")
    
    # Load spec content
    spec_content = spec_file.read_text()
    
    # Parse acceptance criteria
    criteria = parse_acceptance_criteria(spec_content)
    
    if not criteria:
        print(f"\nWarning: No acceptance criteria found in spec")
        print("Add '## Acceptance Criteria' section with checklist items")
        return 0  # No criteria = nothing to fail
    
    print(f"\nFound {len(criteria)} acceptance criteria\n")
    
    # Get labels for additional label-based validation
    labels = get_requirement_labels(project_root, requirement_id)
    print(f"Requirement labels: {labels}\n")
    
    # Validate each criterion
    all_passed = True
    results = []
    
    print("Checking acceptance criteria:")
    print("-" * 40)
    
    for criterion in criteria:
        if criterion["checked"]:
            # Already marked complete - skip validation
            results.append((True, f"✅ [Already checked] {criterion['text']}"))
            continue
        
        passed, message = validate_criterion(criterion, project_root)
        results.append((passed, message))
        
        if not passed:
            all_passed = False
    
    # Print results
    for passed, message in results:
        print(message)
    
    # Run label-based commands if any
    label_commands = get_label_based_commands(labels, project_root)
    if label_commands:
        print("\n" + "-" * 40)
        print("Running label-based validation:")
        print("-" * 40)
        
        for cmd_info in label_commands:
            cmd = cmd_info["command"]
            cwd = Path(cmd_info["cwd"])
            desc = cmd_info["description"]
            
            print(f"  Running: {desc} ({cmd})")
            
            try:
                # Stream output to console to avoid pipe deadlock
                process = subprocess.run(
                    cmd,
                    shell=True,
                    cwd=cwd,
                    capture_output=False,
                    text=True,
                    timeout=120,
                )
                
                success = process.returncode == 0
                return_code = process.returncode
                output = "Output streamed to console"
                
            except subprocess.TimeoutExpired:
                success = False
                output = "Command timed out after 120s"
                return_code = 1
            except Exception as e:
                success = False
                output = f"Error running command: {e}"
                return_code = 1
            
            if success:
                print(f"✅ {desc}")
            else:
                print(f"❌ {desc}")
                print(f"   Exit code: {return_code}")
                if "Error" in output or "timed out" in output:
                    print(f"   {output}")
                all_passed = False
    
    # Summary
    print("\n" + "=" * 60)
    if all_passed:
        print(f"  ✅ VALIDATION PASSED for {requirement_id}")
    else:
        print(f"  ❌ VALIDATION FAILED for {requirement_id}")
    print("=" * 60 + "\n")
    
    return 0 if all_passed else 1


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print(__doc__)
        print("Error: Missing requirement ID argument")
        sys.exit(2)
    
    requirement_id = sys.argv[1]
    
    # Validate requirement ID format (optional, but helpful)
    if not re.match(r"^S-\d{4}$", requirement_id):
        print(f"Warning: Requirement ID '{requirement_id}' doesn't match expected format S-XXXX")
    
    exit_code = validate_requirement(requirement_id)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
