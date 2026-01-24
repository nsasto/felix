#!/usr/bin/env python3
"""
Felix Agent - Ralph Loop Executor
Runs autonomously as a separate process, uses droid for LLM execution.
"""
import sys
import os
import json
import subprocess
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional, List, Tuple


class RalphExecutor:
    """Main Ralph loop executor using droid"""

    def __init__(self, project_path: str):
        self.project_path = Path(project_path).resolve()
        self.iteration = 0
        self.max_iterations = 100

        # Validate project structure
        self._validate_project()

        # Load config
        self.config = self._load_config()
        self.max_iterations = self.config.get("executor", {}).get("max_iterations", 100)

    def _validate_project(self):
        """Ensure project has required Felix structure"""
        required = [
            self.project_path / "felix",
            self.project_path / "specs",
        ]
        for path in required:
            if not path.exists():
                raise ValueError(f"Missing required directory: {path}")

    def _load_config(self) -> Dict[str, Any]:
        """Load felix/config.json"""
        config_file = self.project_path / "felix" / "config.json"
        if config_file.exists():
            with open(config_file) as f:
                return json.load(f)
        return {}

    def _load_requirements(self) -> Dict[str, Any]:
        """Load felix/requirements.json"""
        req_file = self.project_path / "felix" / "requirements.json"
        if req_file.exists():
            with open(req_file) as f:
                return json.load(f)
        return {"requirements": []}

    def _save_requirements(self, data: Dict[str, Any]):
        """Save felix/requirements.json"""
        req_file = self.project_path / "felix" / "requirements.json"
        with open(req_file, "w") as f:
            json.dump(data, f, indent=2)

    def _load_state(self) -> Dict[str, Any]:
        """Load felix/state.json"""
        state_file = self.project_path / "felix" / "state.json"
        if state_file.exists():
            with open(state_file) as f:
                return json.load(f)
        return {}

    def _save_state(self, updates: Dict[str, Any]):
        """Update felix/state.json"""
        state_file = self.project_path / "felix" / "state.json"
        state = self._load_state()
        state.update(updates)
        state["updated_at"] = datetime.now().isoformat()
        with open(state_file, "w") as f:
            json.dump(state, f, indent=2)

    def _determine_mode(self) -> str:
        """Determine if we should be in planning or building mode"""
        state = self._load_state()
        plan_file = self.project_path / "IMPLEMENTATION_PLAN.md"

        # If no plan exists, we need planning mode
        if not plan_file.exists():
            return "planning"

        # Check if state specifies next mode (from auto_transition)
        next_mode = state.get("next_mode")
        if next_mode:
            return next_mode

        # Default to building if we have a plan
        return "building"

    def _load_prompt_template(self, mode: str) -> str:
        """Load prompt template for mode"""
        prompt_file = self.project_path / "felix" / "prompts" / f"{mode}.md"
        if prompt_file.exists():
            return prompt_file.read_text()
        return ""

    def _gather_context(self) -> str:
        """Gather all context files for LLM"""
        context_parts = []

        # CONTEXT.md
        context_file = self.project_path / "specs" / "CONTEXT.md"
        if context_file.exists():
            context_parts.append(f"# Context\n\n{context_file.read_text()}")

        # All specs
        specs_dir = self.project_path / "specs"
        if specs_dir.exists():
            for spec_file in specs_dir.glob("*.md"):
                if spec_file.name != "CONTEXT.md":
                    context_parts.append(
                        f"# Spec: {spec_file.name}\n\n{spec_file.read_text()}"
                    )

        # AGENTS.md
        agents_file = self.project_path / "AGENTS.md"
        if agents_file.exists():
            context_parts.append(f"# Operations Guide\n\n{agents_file.read_text()}")

        # IMPLEMENTATION_PLAN.md
        plan_file = self.project_path / "IMPLEMENTATION_PLAN.md"
        if plan_file.exists():
            context_parts.append(f"# Current Plan\n\n{plan_file.read_text()}")

        # Requirements status
        requirements = self._load_requirements()
        req_summary = json.dumps(requirements, indent=2)
        context_parts.append(f"# Requirements Status\n\n```json\n{req_summary}\n```")

        return "\n\n---\n\n".join(context_parts)

    def _parse_agents_commands(self) -> Dict[str, List[str]]:
        """
        Parse AGENTS.md to extract test, build, and lint commands.
        
        Returns a dict with keys: 'test', 'build', 'lint' containing command lists.
        Looks for specific sections: "Run Tests", "Build the Project", "Lint"
        """
        agents_file = self.project_path / "AGENTS.md"
        if not agents_file.exists():
            return {"test": [], "build": [], "lint": []}
        
        content = agents_file.read_text()
        commands = {"test": [], "build": [], "lint": []}
        
        # Parse sections and extract bash code blocks
        current_section = None
        
        # Patterns for recognized validation sections
        section_patterns = {
            "test": re.compile(r"^#{1,2}\s*run\s+tests?", re.IGNORECASE),
            "build": re.compile(r"^#{1,2}\s*build\s+(the\s+)?project", re.IGNORECASE),
            "lint": re.compile(r"^#{1,2}\s*lint", re.IGNORECASE),
        }
        
        # Pattern to detect ANY section header (to reset current_section)
        any_header_pattern = re.compile(r"^#{1,2}\s+\w+")
        
        lines = content.split("\n")
        in_code_block = False
        code_block_lines = []
        
        for line in lines:
            # Check if this is a header line
            if any_header_pattern.match(line):
                # First check if it matches a known validation section
                matched = False
                for section, pattern in section_patterns.items():
                    if pattern.match(line):
                        current_section = section
                        matched = True
                        break
                
                # If it's a header but not a validation section, reset
                if not matched:
                    current_section = None
            
            # Handle code blocks
            if line.strip().startswith("```"):
                if in_code_block:
                    # End of code block - save commands
                    if current_section and code_block_lines:
                        for cmd in code_block_lines:
                            # Skip comments and empty lines
                            cmd = cmd.strip()
                            if cmd and not cmd.startswith("#"):
                                commands[current_section].append(cmd)
                    code_block_lines = []
                    in_code_block = False
                else:
                    in_code_block = True
            elif in_code_block:
                code_block_lines.append(line)
        
        return commands

    def _run_validation_command(self, command: str, timeout: int = 120) -> Tuple[str, int, Dict[str, Any]]:
        """
        Run a single validation command and return (output, return_code, log_entry).
        
        log_entry contains command metadata for commands.log.jsonl
        """
        print(f"  Running: {command}")
        
        start_time = datetime.now()
        log_entry = {
            "command": command,
            "started_at": start_time.isoformat(),
            "cwd": str(self.project_path),
        }
        
        try:
            # Handle cd commands by parsing and setting cwd
            cwd = str(self.project_path)
            if command.startswith("cd "):
                parts = command.split("&&", 1)
                cd_part = parts[0].strip()
                dir_name = cd_part[3:].strip()
                cwd = str(self.project_path / dir_name)
                log_entry["cwd"] = cwd
                if len(parts) > 1:
                    command = parts[1].strip()
                    log_entry["command"] = command
                else:
                    # Just a cd command, skip it
                    log_entry["skipped"] = True
                    log_entry["return_code"] = 0
                    log_entry["duration_ms"] = 0
                    return "", 0, log_entry
            
            process = subprocess.run(
                command,
                shell=True,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            
            end_time = datetime.now()
            duration_ms = int((end_time - start_time).total_seconds() * 1000)
            
            output = process.stdout + process.stderr
            log_entry["return_code"] = process.returncode
            log_entry["duration_ms"] = duration_ms
            log_entry["output_length"] = len(output)
            
            return output, process.returncode, log_entry
            
        except subprocess.TimeoutExpired:
            log_entry["return_code"] = 1
            log_entry["error"] = f"Command timed out after {timeout}s"
            log_entry["duration_ms"] = timeout * 1000
            return f"Command timed out after {timeout}s", 1, log_entry
        except Exception as e:
            log_entry["return_code"] = 1
            log_entry["error"] = str(e)
            return f"Error running command: {str(e)}", 1, log_entry

    def _run_backpressure(self, max_retries: int = 2) -> Tuple[bool, str, List[Dict[str, Any]]]:
        """
        Run backpressure validation (tests, build, lint).
        
        Returns (success, report, commands_log) where:
        - report contains command outputs for display
        - commands_log contains structured command metadata for JSONL logging
        """
        commands = self._parse_agents_commands()
        report_lines = ["## Backpressure Validation\n"]
        commands_log: List[Dict[str, Any]] = []
        overall_success = True
        
        # Run in order: lint, build, test
        for validation_type in ["lint", "build", "test"]:
            cmds = commands.get(validation_type, [])
            if not cmds:
                report_lines.append(f"### {validation_type.title()}\n*No commands configured*\n")
                continue
            
            report_lines.append(f"### {validation_type.title()}\n")
            
            for cmd in cmds:
                success = False
                last_output = ""
                last_log_entry = None
                
                for attempt in range(max_retries + 1):
                    output, return_code, log_entry = self._run_validation_command(cmd)
                    log_entry["validation_type"] = validation_type
                    log_entry["attempt"] = attempt + 1
                    last_output = output
                    last_log_entry = log_entry
                    
                    if return_code == 0:
                        success = True
                        log_entry["success"] = True
                        commands_log.append(log_entry)
                        report_lines.append(f"✅ `{cmd}` - Passed\n")
                        break
                    elif attempt < max_retries:
                        log_entry["success"] = False
                        commands_log.append(log_entry)
                        print(f"  Retry {attempt + 1}/{max_retries} for: {cmd}")
                
                if not success:
                    overall_success = False
                    if last_log_entry:
                        last_log_entry["success"] = False
                        commands_log.append(last_log_entry)
                    report_lines.append(f"❌ `{cmd}` - Failed\n```\n{last_output[:500]}...\n```\n")
        
        report = "\n".join(report_lines)
        return overall_success, report, commands_log

    def _capture_git_diff(self) -> str:
        """Capture git diff of current changes"""
        try:
            result = subprocess.run(
                ["git", "diff", "HEAD"],
                cwd=str(self.project_path),
                capture_output=True,
                text=True,
                timeout=30,
            )
            return result.stdout
        except Exception as e:
            return f"Error capturing git diff: {str(e)}"

    def _git_commit(self, message: str) -> Tuple[bool, str]:
        """
        Commit current changes with the given message.
        
        Returns (success, output).
        """
        try:
            # Stage all changes
            stage_result = subprocess.run(
                ["git", "add", "-A"],
                cwd=str(self.project_path),
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if stage_result.returncode != 0:
                return False, f"Git add failed: {stage_result.stderr}"
            
            # Check if there are changes to commit
            status_result = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=str(self.project_path),
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if not status_result.stdout.strip():
                return True, "No changes to commit"
            
            # Commit
            commit_result = subprocess.run(
                ["git", "commit", "-m", message],
                cwd=str(self.project_path),
                capture_output=True,
                text=True,
                timeout=30,
            )
            
            if commit_result.returncode != 0:
                return False, f"Git commit failed: {commit_result.stderr}"
            
            return True, commit_result.stdout
            
        except Exception as e:
            return False, f"Git error: {str(e)}"

    def _call_droid(self, prompt: str) -> tuple[str, bool]:
        """Execute prompt via droid, streaming output to console while capturing"""
        try:
            # Write prompt to temp file
            import tempfile

            with tempfile.NamedTemporaryFile(
                mode="w", delete=False, suffix=".txt"
            ) as f:
                f.write(prompt)
                prompt_file = f.name

            try:
                # Run droid with streaming output
                process = subprocess.Popen(
                    ["droid", "exec", "--skip-permissions-unsafe"],
                    stdin=open(prompt_file, "r"),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    cwd=str(self.project_path),
                    bufsize=1,  # Line buffered
                )

                # Stream output to console and capture
                output_lines = []
                for line in process.stdout:
                    print(line, end="", flush=True)
                    output_lines.append(line)

                process.wait(timeout=300)
                output = "".join(output_lines)
                success = process.returncode == 0

                return output, success
            finally:
                os.unlink(prompt_file)

        except subprocess.TimeoutExpired:
            return "ERROR: Droid execution timed out", False
        except FileNotFoundError:
            return "ERROR: droid command not found. Is it installed?", False
        except Exception as e:
            return f"ERROR: {str(e)}", False

    def _check_completion_signal(self, output: str) -> bool:
        """Check if droid signaled completion"""
        return "<promise>COMPLETE</promise>" in output

    def _create_run_directory(self) -> Path:
        """Create runs/<run-id>/ directory"""
        run_id = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
        run_dir = self.project_path / "runs" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        return run_dir

    def _write_run_artifacts(
        self, run_dir: Path, mode: str, output: str, success: bool,
        backpressure_report: str = "", git_diff: str = "",
        commands_log: Optional[List[Dict[str, Any]]] = None
    ):
        """Write execution artifacts to run directory"""
        # Write requirement_id.txt with current requirement being worked on
        state = self._load_state()
        current_req_id = state.get("current_requirement_id")
        if current_req_id:
            (run_dir / "requirement_id.txt").write_text(current_req_id)

        # Snapshot plan
        plan_file = self.project_path / "IMPLEMENTATION_PLAN.md"
        if plan_file.exists():
            (run_dir / "plan.snapshot.md").write_text(plan_file.read_text())

        # Write output log
        (run_dir / "output.log").write_text(output)

        # Write git diff
        if git_diff:
            (run_dir / "diff.patch").write_text(git_diff)

        # Write commands log as JSONL (one JSON object per line)
        if commands_log:
            jsonl_lines = [json.dumps(entry) for entry in commands_log]
            (run_dir / "commands.log.jsonl").write_text("\n".join(jsonl_lines) + "\n")

        # Write report
        report = f"""# Run Report

**Mode:** {mode}
**Iteration:** {self.iteration}
**Requirement:** {current_req_id or "N/A"}
**Success:** {success}
**Timestamp:** {datetime.now().isoformat()}

{backpressure_report}

## LLM Output

```
{output[:5000]}{"..." if len(output) > 5000 else ""}
```
"""
        (run_dir / "report.md").write_text(report)

    def _run_iteration(self, mode: str) -> bool:
        """Run one iteration, return True if should continue"""
        self.iteration += 1

        print(f"\n{'='*60}")
        print(f"  Felix Agent - Iteration {self.iteration}/{self.max_iterations}")
        print(f"  Mode: {mode.upper()}")
        print(f"{'='*60}\n")

        # Update state
        self._save_state(
            {
                "last_mode": mode,
                "current_iteration": self.iteration,
                "status": "running",
            }
        )

        # Load prompt template
        prompt_template = self._load_prompt_template(mode)
        if not prompt_template:
            print(f"Warning: No prompt template found for {mode}")
            return False

        # Gather context
        context = self._gather_context()

        # Construct full prompt
        full_prompt = f"{prompt_template}\n\n---\n\n# Project Context\n\n{context}"

        # Create run directory
        run_dir = self._create_run_directory()

        # Call droid (output streams to console)
        print(f"Calling droid exec...\n")
        output, droid_success = self._call_droid(full_prompt)

        # Check for completion
        if self._check_completion_signal(output):
            print("\n✅ Completion signal detected!")
            self._save_state(
                {"status": "complete", "last_iteration_outcome": "complete"}
            )
            self._write_run_artifacts(run_dir, mode, output, True)
            return False

        # In building mode, run backpressure validation
        backpressure_report = ""
        git_diff = ""
        commands_log: List[Dict[str, Any]] = []
        overall_success = droid_success

        if mode == "building" and droid_success:
            # Capture git diff before potential commit
            git_diff = self._capture_git_diff()
            
            print(f"\n{'='*60}")
            print("  Running Backpressure Validation")
            print(f"{'='*60}\n")
            
            backpressure_success, backpressure_report, commands_log = self._run_backpressure()
            
            if backpressure_success:
                print("\n✅ Backpressure passed! Committing changes...")
                commit_msg = f"felix: Iteration {self.iteration} - {mode} mode task completed"
                commit_success, commit_output = self._git_commit(commit_msg)
                
                if commit_success:
                    print(f"  {commit_output}")
                    self._save_state({"last_iteration_outcome": "committed"})
                else:
                    print(f"  ⚠️ Commit failed: {commit_output}")
                    self._save_state({"last_iteration_outcome": "commit_failed"})
            else:
                print("\n❌ Backpressure failed! Task marked as blocked.")
                overall_success = False
                self._save_state({
                    "status": "blocked",
                    "last_iteration_outcome": "backpressure_failed"
                })
                # Mark current requirement as blocked
                self._mark_requirement_blocked()
        
        # Write run artifacts
        self._write_run_artifacts(
            run_dir, mode, output, overall_success,
            backpressure_report=backpressure_report,
            git_diff=git_diff,
            commands_log=commands_log
        )

        # Check for mode transition (auto_transition)
        auto_transition = self.config.get("executor", {}).get("auto_transition", True)
        if auto_transition and mode == "planning":
            # After planning, switch to building
            self._save_state({"next_mode": "building"})

        return overall_success

    def _mark_requirement_blocked(self):
        """Mark the current requirement as blocked in requirements.json"""
        state = self._load_state()
        current_req_id = state.get("current_requirement_id")
        
        if not current_req_id:
            return
        
        requirements = self._load_requirements()
        for req in requirements.get("requirements", []):
            if req.get("id") == current_req_id:
                req["status"] = "blocked"
                req["updated_at"] = datetime.now().strftime("%Y-%m-%d")
                break
        
        self._save_requirements(requirements)

    def run_until_complete(self):
        """Main Ralph loop - run until complete or max iterations"""
        print(f"\nFelix Agent starting for: {self.project_path}")
        print(f"Max iterations: {self.max_iterations}\n")

        os.chdir(self.project_path)

        should_continue = True
        while should_continue and self.iteration < self.max_iterations:
            mode = self._determine_mode()
            should_continue = self._run_iteration(mode)

            if should_continue:
                print(f"\nIteration {self.iteration} complete. Continuing...")

        if self.iteration >= self.max_iterations:
            print(f"\n Reached max iterations ({self.max_iterations})")
            self._save_state(
                {"status": "max_iterations", "last_iteration_outcome": "incomplete"}
            )

        print("\nFelix Agent complete")


def main():
    if len(sys.argv) < 2:
        print("Usage: python agent.py <project_path>")
        sys.exit(1)

    project_path = sys.argv[1]

    try:
        executor = RalphExecutor(project_path)
        executor.run_until_complete()
    except KeyboardInterrupt:
        print("\n\nAgent interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\nAgent error: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
