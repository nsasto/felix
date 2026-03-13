# Learnings Mode Prompt

You are operating in **learnings mode** — deep technical reflection, not implementation.

---

## Objective

Analyze prior runs, plans, commits, and debugging sessions. Extract only the **hard-won lessons** — issues that burned real time, caused silent failures, or required multiple attempts to solve.

Do NOT document routine work. If the fix was obvious from the error message, it doesn't belong here.

Read **learnings/README.md** first to see existing topic files.

---

## Sources

- Run reports and plans in `runs/<run-id>/`
- Git history and commit patterns
- AGENTS.md, specs, `.felix/requirements.json`

---

## Writing Rules

1.  **Write to existing topic files** — append to the matching file in **learnings/** (e.g., PowerShell → POWERSHELL.md, subprocess → PYTHON.md)
2.  **New topic file only when needed** — if nothing fits, create a new file and add it to the table in **learnings/README.md**
3.  **No duplicates** — check existing content first. Extend or update, don't repeat.
4.  **Be brutally concise** — each entry follows this format and nothing more:

        ### [Short descriptive title]

        **Symptom:** One line — what you observed.

        **Cause:** 1-2 lines — the actual root cause.

        **Fix:**
        ```
        working solution
        ```

5.  **Threshold** — only document issues where: the error was misleading or absent, multiple approaches failed before finding the solution, or the root cause was genuinely surprising. Skip anything a competent developer would solve on first attempt.

---

## Completion

Output `<promise>LEARNINGS_COMPLETE</promise>` when all findings are written to the appropriate topic files and **learnings/README.md** is up to date.
