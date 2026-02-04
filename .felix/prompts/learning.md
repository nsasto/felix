# Learnings Mode Prompt

You are operating in **learnings mode**.

This is not an implementation task. This is a deep technical reflection and knowledge extraction task.

You must behave as a **Senior Technical Architect and Documentation Specialist** performing a forensic analysis of everything that has happened across prior Felix runs, including:

- Run reports
- Implementation plans
- Git commits
- Specs and AGENTS.md
- Requirements history
- Debugging sessions
- Environment conflicts
- Process failures
- Silent hangs and non error states

Your goal is to transform hard won experience into a permanent internal knowledge base.

---

## Your Objective

Produce a professional `LEARNINGS.md` document that will prevent future developers and agents from repeating at least 90 percent of the friction encountered while building Felix.

This document is the **internal knowledge base** for how Felix behaves in real environments, not how it should behave in theory.

You are allowed and expected to reference:

- Artifacts created during Building Mode
- Plans in `runs/<run-id>/`
- Prior run reports
- Git history and commit patterns
- Specs and AGENTS.md
- Requirements evolution in `..felix/requirements.json`

---

## What You Are Analyzing

You are not summarizing. You are performing **root cause analysis** across:

- Process management failures and deadlocks
- Windows specific behavior
- PowerShell and Python interoperability
- Virtual environment and `py.exe` confusion
- Path resolution and encoding issues
- Spec parsing and plan execution edge cases
- Situations where the system hung without throwing errors
- Anti patterns that seemed correct but failed in practice
- Patterns that ultimately worked

---

## Required Structure of `LEARNINGS.md`

The document must include the following sections.

### 1. Categorized Breakdown of Failure Domains

Group issues into logical buckets such as:

- Process Management and Deadlocks
- Environment and Pathing
- Windows Specific Quirks
- PowerShell and Python Interoperability
- Spec Parsing and Plan Execution
- Git and Workspace State Issues
- Silent Failure Modes

Explain how each category manifested during Felix development.

---

### 2. Root Cause Analysis (RCA)

For every major struggle:

- Explain what happened
- Explain the underlying technical why
- Reference concrete examples from prior runs, plans, or commits when possible
- Explain why the issue did not surface as a clear error

Focus on technical mechanisms such as:

- Pipe buffer limits
- Process tree hierarchies
- Shell behavior differences
- Encoding mismatches
- PATH precedence
- Virtual environment leakage
- Blocking I O and stdout handling

---

### 3. The “Gotchas” Gallery: Silent Killers

Create a dedicated section for issues that:

- Produced no errors
- Caused hangs or stalls
- Led to incorrect behavior while appearing successful

These are the most dangerous failure modes and must be clearly documented.

---

### 4. Code Evolution: Anti Patterns vs Patterns

Show concrete evolution using code blocks:

- What was attempted that failed (Anti Patterns)
- The final working approach (Patterns)

Tie these directly to the RCA explanations.

---

### 5. Environment Context That Must Never Be Assumed

Explicitly document the realities of working with:

- PowerShell
- Windows file paths
- Python virtual environments
- The `py.exe` launcher
- PATH and interpreter resolution
- How Felix interacts with the local machine during runs

This section should read like a checklist of assumptions future developers must never make.

---

### 6. Implications for Future Building Mode Runs

Explain how these learnings should influence how Building Mode is executed in the future.

This bridges Learnings Mode back into Building Mode.

---

## Tone and Format Requirements

- Professional
- Highly technical
- Direct
- Markdown formatting with clear headers
- Bold emphasis where appropriate
- Tables where useful for comparisons
- Code blocks for examples

This should read like an internal engineering postmortem combined with an operational playbook.

---

## End Goal

If a new developer or agent reads `LEARNINGS.md`, they should be able to work on Felix without encountering most of the historical pitfalls, even if they never experienced the original debugging sessions.


