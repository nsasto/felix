import os
import json
import subprocess
import re
from datetime import datetime
from pathlib import Path

class FelixAgent:
    def __init__(self, project_path):
        self.root = Path(project_path).resolve()
        self.config = self._load_json(self.root / "felix/config.json")
        self.state_file = self.root / "felix/state.json"
        self.req_file = self.root / "felix/requirements.json"

    def _load_json(self, path):
        if not path.exists(): return {}
        with open(path, 'r') as f: return json.load(f)

    def get_git_state(self):
        """Captures commit hash and modified/untracked files."""
        commit = subprocess.getoutput("git rev-parse HEAD")
        files = subprocess.getoutput("git ls-files --modified --others --exclude-standard").splitlines()
        return {"commit": commit, "files": set(files)}

    def run_backpressure(self, run_dir):
        """Executes build/test commands defined in config or AGENTS.md."""
        print(f"\n[BACKPRESSURE] Starting validation...")
        commands = self.config.get("backpressure", {}).get("commands", [])
        
        results = []
        for cmd in commands:
            print(f"  Executing: {cmd}")
            proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=self.root)
            success = proc.returncode == 0
            results.append({"cmd": cmd, "success": success, "log": proc.stdout + proc.stderr})
            print(f"  {'✅ PASSED' if success else '❌ FAILED'}")
        
        return all(r["success"] for r in results)

    def execute_iteration(self):
        # 1. Identify Requirement
        req_data = self._load_json(self.req_file)
        current_req = next((r for r in req_data['requirements'] if r['status'] in ['in_progress', 'planned']), None)
        
        if not current_req:
            print("No active requirements found.")
            return

        # 2. Determine Mode (Planning vs Building)
        # Logic: Check if a plan exists in the /runs folder
        run_id = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
        mode = "planning" # Simplified logic for skeleton
        
        print(f"--- Iteration for {current_req['id']} | Mode: {mode.upper()} ---")

        # 3. Guardrail: Capture state before AI runs
        before_state = self.get_git_state()

        # 4. Call Droid (AI Execution)
        # In Python, we can pipe the prompt directly into the process stdin
        prompt = f"Context for {current_req['id']}..." # Assembly logic goes here
        try:
            process = subprocess.Popen(
                ["droid", "exec", "--skip-permissions-unsafe"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, cwd=self.root
            )
            stdout, stderr = process.communicate(input=prompt)
            print(stdout)
        except Exception as e:
            print(f"Execution Error: {e}")
            return

        # 5. Guardrail Enforcement
        if mode == "planning":
            after_state = self.get_git_state()
            unauthorized = [f for f in (after_state['files'] - before_state['files']) 
                           if not re.match(r"^(runs/|felix/)", f)]
            
            violation_reasons = []
            if unauthorized:
                violation_reasons.append(f"Unauthorized file changes: {', '.join(unauthorized)}")
            if after_state['commit'] != before_state['commit']:
                violation_reasons.append("Unauthorized commit detected")

            if violation_reasons:
                print(f"[GUARDRAIL] Violation! Reverting changes... Reason(s): {'; '.join(violation_reasons)}")
                subprocess.run(["git", "reset", "--hard", "HEAD"], cwd=self.root)
                return

        # 6. Finalize Task
        if "<promise>TASK_COMPLETE</promise>" in stdout:
            if self.run_backpressure(run_id):
                print("[SUCCESS] Requirement verified.")
                # Update status logic here
            else:
                print("[BLOCKED] Backpressure failed.")

if __name__ == "__main__":
    agent = FelixAgent("./")
    agent.execute_iteration()