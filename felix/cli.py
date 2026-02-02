"""
Felix CLI - Artifact Templates and Scaffolding

Commands:
  - felix init: Initialize Felix in an existing project
  - felix spec create <name>: Create a new specification
  - felix validate: Validate Felix project health

Usage:
  python -m felix init [--minimal]
  python -m felix spec create <name> [--title TITLE]
  python -m felix validate
"""

import argparse
import json
import os
import re
import sys
from datetime import date
from pathlib import Path
from typing import Optional


# =============================================================================
# Template Contents
# =============================================================================

CONFIG_JSON_TEMPLATE = """{
  // Felix Configuration
  // -------------------
  // version: Configuration schema version
  // executor.mode: Execution mode - "local" for local agent
  // executor.max_iterations: Maximum iterations before stopping (safety limit)
  // executor.default_mode: Starting mode - "planning" or "building"
  // executor.auto_transition: Auto-transition from planning to building when plan is complete
  // executor.commit_on_complete: Create a git commit after each successful task
  //
  // agent.agent_id: Which agent preset to use from ~/.felix/agents.json

  "version": "0.1.0",
  "executor": {
    "mode": "local",
    "max_iterations": 100,
    "default_mode": "building",
    "auto_transition": true,
    "commit_on_complete": true
  },
  "agent": {
    "agent_id": 0
  },
  "paths": {
    "specs": "specs",
    "agents": "AGENTS.md",
    "runs": "runs"
  },
  "backpressure": {
    // enabled: Run tests/lint after each building iteration
    // commands: Array of commands to run (parsed from AGENTS.md if empty)
    // max_retries: How many consecutive failures before blocking the requirement
    "enabled": true,
    "commands": [],
    "max_retries": 3
  }
}
"""

# JSON doesn't support comments, so we provide two versions
CONFIG_JSON_CLEAN = """{
  "version": "0.1.0",
  "executor": {
    "mode": "local",
    "max_iterations": 100,
    "default_mode": "building",
    "auto_transition": true,
    "commit_on_complete": true
  },
  "agent": {
    "agent_id": 0
  },
  "paths": {
    "specs": "specs",
    "agents": "AGENTS.md",
    "runs": "runs"
  },
  "backpressure": {
    "enabled": true,
    "commands": [],
    "max_retries": 3
  }
}
"""

REQUIREMENTS_JSON_TEMPLATE = """{
  "requirements": [
    // Example requirement entry (uncomment and modify):
    // {
    //   "id": "S-0001",
    //   "title": "My First Requirement",
    //   "spec_path": "specs/S-0001-my-first-requirement.md",
    //   "status": "draft",
    //   "priority": "high",
    //   "labels": ["feature"],
    //   "depends_on": [],
    //   "updated_at": "2026-01-25"
    // }
  ]
}
"""

# Clean version without comments (valid JSON)
REQUIREMENTS_JSON_CLEAN = """{
  "requirements": []
}
"""

PLANNING_PROMPT_TEMPLATE = """# Planning Mode Prompt

You are operating in **planning mode**.

## Your Responsibilities

- Read the current requirement spec (provided in context)
- Read CONTEXT.md for tech stack and architectural constraints
- Generate a focused implementation plan for the current requirement
- Save plan to the specified output path (in runs/<run-id>/plan-<requirement-id>.md)
- **CRITICAL: Must not modify source code files - only planning artifacts**

## Rules

1. **Narrow Scope** - Plan ONLY for the current requirement
2. **Gap Analysis** - Search codebase to see what's already implemented
3. **Narrow Tasks** - Each task should be completable in ONE building iteration
4. **Simplicity First** - Always choose the simplest approach that works
5. **Avoid Overengineering** - No premature abstractions, no unnecessary complexity
6. **Search Before Planning** - Don't assume features aren't implemented; verify first
7. **Clear Checkboxes** - Use `- [ ]` for pending items

## Workflow

1. Read the current requirement spec from context
2. Read CONTEXT.md for tech stack and architectural constraints
3. Read AGENTS.md to understand how to run tests/builds
4. Search codebase to verify what's actually implemented
5. Generate implementation plan with concrete, prioritized tasks
6. Save plan to path specified in context

## Output Format

Create a file at the path specified in context:

```markdown
# Implementation Plan for [Requirement ID]

## Summary

Brief description of what needs to be implemented for this requirement.

## Tasks

### Task Group 1

- [ ] Concrete, actionable task description
- [ ] Another task with clear acceptance criteria

### Task Group 2

- [ ] Task items here

## Dependencies

- List any blockers or dependencies on other requirements

## Notes

- Technical decisions or constraints to keep in mind
```

## Allowed File Modifications

You may ONLY modify:
- The plan file at the specified path in runs/<run-id>/plan-<requirement-id>.md
- felix/requirements.json if updating requirement status

Any other file modifications will be automatically reverted.

## Completion Signal

When planning is complete, output: `<promise>PLAN_COMPLETE</promise>`
"""

BUILDING_PROMPT_TEMPLATE = """# Building Mode Prompt

You are operating in **building mode**.

## Your Responsibilities

- Select exactly ONE incomplete task from the implementation plan
- Inspect existing code BEFORE implementing (don't duplicate functionality)
- Implement that single task
- Mark the task complete in the plan (change `- [ ]` to `- [x]`)
- Update requirement status in felix/requirements.json if needed

## Rules

1. **One task per iteration** - implement ONLY one item, then exit
2. **Investigate before implementing** - search codebase for existing implementations
3. **Update plan after implementing** - change `- [ ]` to `- [x]` for completed items
4. **Update requirements status** - if completing a requirement, set status to "complete"
5. **Exit cleanly** - output a run report summarizing what was done

## Workflow

1. Read the implementation plan from context
2. Select the FIRST incomplete task (`- [ ]`) in priority order
3. Read relevant context from specs and AGENTS.md
4. Search codebase for existing implementations (use Grep/Glob tools)
5. Implement the task (create/edit files as needed)
6. After implementation, update the plan:
   - Change `- [ ] <task>` to `- [x] <task>`
7. If this completes the requirement, update felix/requirements.json:
   - Set status: "complete" for the requirement

## Run Report Format

After completing the task, output a brief summary:

```
## Run Report

**Task Completed:** [brief description of task]

**Summary:**
- What was implemented
- Files modified
- Any notable decisions

**Outcome:** SUCCESS or BLOCKED (with reason)
```

## Completion Signals

- `<promise>TASK_COMPLETE</promise>` - You finished this task. Agent will continue to next task.
- `<promise>ALL_COMPLETE</promise>` - All tasks in the plan are done. Requirement is complete.
"""

ALLOWLIST_JSON_TEMPLATE = """{
  "description": "Commands and operations allowed for Felix executor",
  
  "allowed_commands": [
    "git",
    "npm",
    "node", 
    "python",
    "pip",
    "pytest",
    "cargo",
    "rustc",
    "make"
  ],
  
  "allowed_file_patterns": [
    "src/**",
    "tests/**",
    "app/**",
    "specs/**",
    "felix/requirements.json",
    "felix/state.json",
    "AGENTS.md"
  ],
  
  "restricted_paths": [
    "felix/config.json",
    "felix/prompts/**",
    "felix/policies/**"
  ]
}
"""

DENYLIST_JSON_TEMPLATE = """{
  "description": "Operations explicitly prohibited for Felix executor",
  
  "denied_commands": [
    "rm -rf /",
    "rm -rf ~",
    "format",
    "shutdown",
    "reboot",
    "curl | bash",
    "wget | sh"
  ],
  
  "denied_paths": [
    "/",
    "/home",
    "/etc",
    "node_modules/",
    ".git/objects/"
  ],
  
  "denied_operations": [
    "network_access_planning_mode",
    "code_changes_planning_mode",
    "config_modification",
    "prompt_modification"
  ]
}
"""

AGENTS_MD_TEMPLATE = """# Agents - How to Operate This Repository

This file tells Felix **how to run the system**.
Keep this file operational only - no planning or status updates.

## Install Dependencies

```bash
# TODO: Add your dependency installation commands
# Example for Python:
# pip install -r requirements.txt

# Example for Node.js:
# npm install
```

## Run Tests

```bash
# TODO: Add your test commands
# Example for Python:
# pytest tests/

# Example for Node.js:
# npm test
```

## Build the Project

```bash
# TODO: Add your build commands
# Example for frontend:
# npm run build

# Example for compiled languages:
# make build
```

## Start the Application

### Development Mode

```bash
# TODO: Add your development server commands
# Example:
# npm run dev
```

### Production Mode

```bash
# TODO: Add your production commands
# Example:
# npm start
```

## Repository Conventions

- Keep this file operational only
- No planning or status updates
- No long explanations
- If it wouldn't help a new engineer run the repo, it doesn't belong here
"""

CONTEXT_MD_TEMPLATE = """# Context

This file documents product and system context for Felix.

## Tech Stack

### Backend

- **Language:** TODO (e.g., Python 3.11+, Node.js 20+)
- **Framework:** TODO (e.g., FastAPI, Express)
- **Database:** TODO (e.g., PostgreSQL, MongoDB)
- **Location:** TODO (e.g., `src/`, `app/`)

### Frontend

- **Language:** TODO (e.g., TypeScript)
- **Framework:** TODO (e.g., React, Vue)
- **Location:** TODO (e.g., `web/`, `frontend/`)

### Infrastructure

- **Hosting:** TODO (e.g., AWS, Vercel)
- **CI/CD:** TODO (e.g., GitHub Actions)

## Design Standards

- TODO: Add your design principles
- Example: Keep the outer mechanism simple
- Example: File-based memory and state

## UX Rules

- TODO: Add your UX guidelines
- Example: Minimal UI - focus on clarity
- Example: Prefer progressive disclosure

## Architectural Invariants

- TODO: Add your architectural rules
- Example: Planning mode cannot modify code
- Example: All state changes must be logged
"""

SPEC_TEMPLATE = """# {id}: {title}

## Narrative

As a [user type], I need [feature], so that [benefit].

## Acceptance Criteria

### Feature Group 1

- [ ] First acceptance criterion
- [ ] Second acceptance criterion

### Feature Group 2

- [ ] Another criterion

## Technical Notes

Add implementation notes, constraints, and considerations here.

## Validation Criteria

- [ ] Test command: `command here` (expected outcome)
- [ ] Another validation step

## Dependencies

List any requirements this depends on (e.g., S-0001, S-0002).
"""


# =============================================================================
# Helper Functions
# =============================================================================

def get_project_root() -> Path:
    """Get the current working directory as project root."""
    return Path.cwd()


def is_felix_enabled(root: Path) -> bool:
    """Check if Felix is already initialized in the project."""
    felix_dir = root / "felix"
    return (felix_dir / "config.json").exists()


def get_next_spec_id(specs_dir: Path) -> str:
    """Generate the next spec ID by finding the highest existing ID."""
    if not specs_dir.exists():
        return "S-0001"
    
    max_id = 0
    pattern = re.compile(r"S-(\d{4})")
    
    for spec_file in specs_dir.glob("S-*.md"):
        match = pattern.match(spec_file.name)
        if match:
            spec_num = int(match.group(1))
            max_id = max(max_id, spec_num)
    
    return f"S-{max_id + 1:04d}"


def slugify(text: str) -> str:
    """Convert text to a URL-friendly slug."""
    # Convert to lowercase and replace spaces with hyphens
    slug = text.lower().strip()
    # Replace non-alphanumeric characters with hyphens
    slug = re.sub(r'[^a-z0-9]+', '-', slug)
    # Remove leading/trailing hyphens
    slug = slug.strip('-')
    return slug


# =============================================================================
# Init Command
# =============================================================================

def cmd_init(args: argparse.Namespace) -> int:
    """Initialize Felix in an existing project."""
    root = get_project_root()
    minimal = getattr(args, 'minimal', False)
    
    # Check if already Felix-enabled
    if is_felix_enabled(root):
        print(f"Error: Project is already Felix-enabled (felix/config.json exists)")
        print(f"Location: {root / 'felix' / 'config.json'}")
        return 1
    
    print(f"Initializing Felix in: {root}")
    
    # Create directory structure
    directories = [
        "specs",
        "felix",
        "felix/prompts",
        "felix/policies",
        "runs"
    ]
    
    for dir_path in directories:
        full_path = root / dir_path
        full_path.mkdir(parents=True, exist_ok=True)
        print(f"  Created: {dir_path}/")
    
    # Create files
    files_to_create = {
        "felix/config.json": CONFIG_JSON_CLEAN,
        "felix/requirements.json": REQUIREMENTS_JSON_CLEAN,
        "felix/state.json": '{"mode": "planning", "current_requirement": null, "iteration": 0}',
    }
    
    if not minimal:
        # Full setup includes prompts, policies, and templates
        files_to_create.update({
            "felix/prompts/planning.md": PLANNING_PROMPT_TEMPLATE,
            "felix/prompts/building.md": BUILDING_PROMPT_TEMPLATE,
            "felix/policies/allowlist.json": ALLOWLIST_JSON_TEMPLATE,
            "felix/policies/denylist.json": DENYLIST_JSON_TEMPLATE,
            "AGENTS.md": AGENTS_MD_TEMPLATE,
            "specs/CONTEXT.md": CONTEXT_MD_TEMPLATE,
        })
    
    for file_path, content in files_to_create.items():
        full_path = root / file_path
        if not full_path.exists():
            full_path.write_text(content, encoding='utf-8')
            print(f"  Created: {file_path}")
        else:
            print(f"  Skipped: {file_path} (already exists)")
    
    print()
    print("Felix initialized successfully!")
    print()
    print("Next steps:")
    print("  1. Edit AGENTS.md with your project's commands")
    print("  2. Edit specs/CONTEXT.md with your tech stack")
    print("  3. Create your first spec: python -m felix spec create my-feature")
    print("  4. Start Felix agent to begin planning")
    
    return 0


# =============================================================================
# Spec Create Command
# =============================================================================

def cmd_spec_create(args: argparse.Namespace) -> int:
    """Create a new specification file."""
    root = get_project_root()
    name = args.name
    title = getattr(args, 'title', None) or name.replace('-', ' ').title()
    
    # Check Felix is initialized
    if not is_felix_enabled(root):
        print("Error: Felix is not initialized in this project.")
        print("Run 'python -m felix init' first.")
        return 1
    
    specs_dir = root / "specs"
    specs_dir.mkdir(exist_ok=True)
    
    # Generate spec ID
    spec_id = get_next_spec_id(specs_dir)
    
    # Create filename
    slug = slugify(name)
    filename = f"{spec_id}-{slug}.md"
    spec_path = specs_dir / filename
    
    if spec_path.exists():
        print(f"Error: Spec file already exists: {spec_path}")
        return 1
    
    # Create spec content
    content = SPEC_TEMPLATE.format(id=spec_id, title=title)
    spec_path.write_text(content, encoding='utf-8')
    print(f"Created: specs/{filename}")
    
    # Add to requirements.json
    req_path = root / "felix" / "requirements.json"
    if req_path.exists():
        try:
            with open(req_path, 'r', encoding='utf-8') as f:
                req_data = json.load(f)
        except json.JSONDecodeError:
            req_data = {"requirements": []}
    else:
        req_data = {"requirements": []}
    
    # Add new requirement entry
    new_req = {
        "id": spec_id,
        "title": title,
        "spec_path": f"specs/{filename}",
        "status": "draft",
        "priority": "medium",
        "labels": [],
        "depends_on": [],
        "updated_at": date.today().isoformat()
    }
    
    req_data["requirements"].append(new_req)
    
    with open(req_path, 'w', encoding='utf-8') as f:
        json.dump(req_data, f, indent=2)
    
    print(f"Added to: felix/requirements.json (status: draft)")
    print()
    print(f"Edit your spec at: specs/{filename}")
    
    return 0


# =============================================================================
# Validate Command
# =============================================================================

def cmd_validate(args: argparse.Namespace) -> int:
    """Validate Felix project health."""
    root = get_project_root()
    errors = []
    warnings = []
    
    print(f"Validating Felix project: {root}")
    print()
    
    # Check required directories
    required_dirs = ["felix", "specs", "runs"]
    for dir_name in required_dirs:
        dir_path = root / dir_name
        if not dir_path.exists():
            errors.append(f"Missing directory: {dir_name}/")
        else:
            print(f"  [OK] Directory exists: {dir_name}/")
    
    # Check required files
    required_files = [
        ("felix/config.json", "Configuration file"),
        ("felix/requirements.json", "Requirements tracking"),
    ]
    
    for file_path, description in required_files:
        full_path = root / file_path
        if not full_path.exists():
            errors.append(f"Missing file: {file_path} ({description})")
        else:
            print(f"  [OK] File exists: {file_path}")
    
    # Validate config.json schema
    config_path = root / "felix" / "config.json"
    if config_path.exists():
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
            
            required_fields = ["version", "executor"]
            for field in required_fields:
                if field not in config:
                    errors.append(f"config.json missing required field: {field}")
            
            if "executor" in config:
                exec_fields = ["max_iterations", "default_mode"]
                for field in exec_fields:
                    if field not in config["executor"]:
                        warnings.append(f"config.json executor missing field: {field}")
            
            print(f"  [OK] config.json is valid JSON")
        except json.JSONDecodeError as e:
            errors.append(f"config.json is invalid JSON: {e}")
    
    # Validate requirements.json schema
    req_path = root / "felix" / "requirements.json"
    if req_path.exists():
        try:
            with open(req_path, 'r', encoding='utf-8') as f:
                req_data = json.load(f)
            
            if "requirements" not in req_data:
                errors.append("requirements.json missing 'requirements' array")
            elif not isinstance(req_data["requirements"], list):
                errors.append("requirements.json 'requirements' must be an array")
            else:
                for i, req in enumerate(req_data["requirements"]):
                    if "id" not in req:
                        errors.append(f"requirements.json entry {i} missing 'id'")
                    if "status" not in req:
                        warnings.append(f"requirements.json entry {i} missing 'status'")
            
            print(f"  [OK] requirements.json is valid JSON")
        except json.JSONDecodeError as e:
            errors.append(f"requirements.json is invalid JSON: {e}")
    
    # Check specs for valid format
    specs_dir = root / "specs"
    if specs_dir.exists():
        spec_pattern = re.compile(r"S-\d{4}")
        spec_files = list(specs_dir.glob("S-*.md"))
        
        for spec_file in spec_files:
            try:
                content = spec_file.read_text(encoding='utf-8')
                first_line = content.split('\n')[0] if content else ""
                
                if not spec_pattern.search(first_line):
                    warnings.append(f"Spec {spec_file.name} doesn't have ID in first line")
                else:
                    print(f"  [OK] Spec format valid: {spec_file.name}")
            except Exception as e:
                errors.append(f"Cannot read spec {spec_file.name}: {e}")
        
        if not spec_files:
            warnings.append("No spec files found (S-*.md)")
    
    # Print summary
    print()
    if errors:
        print("ERRORS:")
        for error in errors:
            print(f"  [X] {error}")
    
    if warnings:
        print("WARNINGS:")
        for warning in warnings:
            print(f"  [!] {warning}")
    
    print()
    if errors:
        print(f"VALIDATION FAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1
    elif warnings:
        print(f"VALIDATION PASSED with {len(warnings)} warning(s)")
        return 0
    else:
        print("VALIDATION PASSED: Project is healthy")
        return 0


# =============================================================================
# Main Entry Point
# =============================================================================

def main(args: Optional[list] = None) -> int:
    """Main entry point for the Felix CLI."""
    parser = argparse.ArgumentParser(
        prog="felix",
        description="Felix - Artifact Templates and Scaffolding CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python -m felix init              Initialize Felix in current directory
  python -m felix init --minimal    Initialize with minimal files
  python -m felix spec create auth  Create spec for 'auth' feature
  python -m felix validate          Check project health
        """
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Init command
    init_parser = subparsers.add_parser(
        "init",
        help="Initialize Felix in an existing project"
    )
    init_parser.add_argument(
        "--minimal",
        action="store_true",
        help="Create minimal setup (config and requirements only)"
    )
    
    # Spec command with subcommands
    spec_parser = subparsers.add_parser(
        "spec",
        help="Manage specifications"
    )
    spec_subparsers = spec_parser.add_subparsers(dest="spec_command")
    
    # Spec create subcommand
    spec_create_parser = spec_subparsers.add_parser(
        "create",
        help="Create a new specification"
    )
    spec_create_parser.add_argument(
        "name",
        help="Name/slug for the spec (e.g., 'user-authentication')"
    )
    spec_create_parser.add_argument(
        "--title",
        help="Human-readable title (defaults to name with spaces)"
    )
    
    # Validate command
    validate_parser = subparsers.add_parser(
        "validate",
        help="Validate Felix project health"
    )
    
    # Parse arguments
    parsed_args = parser.parse_args(args)
    
    if parsed_args.command is None:
        parser.print_help()
        return 0
    
    # Route to appropriate command
    if parsed_args.command == "init":
        return cmd_init(parsed_args)
    elif parsed_args.command == "spec":
        if getattr(parsed_args, 'spec_command', None) == "create":
            return cmd_spec_create(parsed_args)
        else:
            spec_parser.print_help()
            return 0
    elif parsed_args.command == "validate":
        return cmd_validate(parsed_args)
    else:
        parser.print_help()
        return 0


if __name__ == "__main__":
    sys.exit(main())
