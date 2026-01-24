#!/usr/bin/env python3
"""
Felix Agent - Ralph Loop Executor
Runs autonomously as a separate process, uses droid for LLM execution.
"""
import sys
import os
import json
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional


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
                    context_parts.append(f"# Spec: {spec_file.name}\n\n{spec_file.read_text()}")
        
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
    
    def _call_droid(self, prompt: str) -> tuple[str, bool]:
        """Execute prompt via droid, return (output, success)"""
        try:
            result = subprocess.run(
                ["droid", "exec", "--skip-permissions-unsafe"],
                input=prompt,
                capture_output=True,
                text=True,
                cwd=str(self.project_path),
                timeout=300  # 5 minute timeout
            )
            
            output = result.stdout + result.stderr
            success = result.returncode == 0
            
            return output, success
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
    
    def _write_run_artifacts(self, run_dir: Path, mode: str, output: str, success: bool):
        """Write execution artifacts to run directory"""
        # Snapshot plan
        plan_file = self.project_path / "IMPLEMENTATION_PLAN.md"
        if plan_file.exists():
            (run_dir / "plan.snapshot.md").write_text(plan_file.read_text())
        
        # Write output log
        (run_dir / "output.log").write_text(output)
        
        # Write report
        report = f"""# Run Report

**Mode:** {mode}
**Iteration:** {self.iteration}
**Success:** {success}
**Timestamp:** {datetime.now().isoformat()}

## Output

```
{output}
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
        self._save_state({
            "last_mode": mode,
            "current_iteration": self.iteration,
            "status": "running"
        })
        
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
        
        # Call droid
        print(f"Calling droid exec...")
        output, success = self._call_droid(full_prompt)
        
        print(output)
        
        # Write run artifacts
        self._write_run_artifacts(run_dir, mode, output, success)
        
        # Check for completion
        if self._check_completion_signal(output):
            print("\n Completion signal detected!")
            self._save_state({
                "status": "complete",
                "last_iteration_outcome": "complete"
            })
            return False
        
        # Check for mode transition (auto_transition)
        auto_transition = self.config.get("executor", {}).get("auto_transition", True)
        if auto_transition and mode == "planning":
            # After planning, switch to building
            self._save_state({"next_mode": "building"})
        
        return True
    
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
            self._save_state({
                "status": "max_iterations",
                "last_iteration_outcome": "incomplete"
            })
        
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
