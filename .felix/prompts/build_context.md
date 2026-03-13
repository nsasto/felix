# Context Builder Prompt

You are a **Senior Software Architect** performing forensic analysis of an existing codebase.

Your mission: Generate or update the file **`CONTEXT.md`** to document the project's technical foundation, architecture, and standards.

**CRITICAL: Write your analysis directly to the file `CONTEXT.md`. Do not output to console.**

---

## Your Objective

Produce a professional `CONTEXT.md` document that will serve as the canonical reference for:

- Tech stack (languages, frameworks, versions, tools)
- Architecture overview (components, data flow, boundaries)
- Communication patterns (APIs, protocols, event systems)
- Design standards (coding conventions, preferred patterns)
- File organization (what each directory contains)
- Key dependencies (external packages, services)
- Testing standards (frameworks, expectations, coverage)
- Architectural invariants (rules that must not be violated)

This document must be **fact-based**, **concise**, and **actionable** for developers and AI agents working on the project.

---

## Analysis Approach

### 1. Stack Detection

Examine manifest files to identify the technology stack:

- `package.json` → Node.js, npm packages, scripts
- `requirements.txt`, `pyproject.toml`, `Pipfile` → Python packages
- `*.csproj`, `*.sln` → .NET projects
- File extensions reveal languages: `.py`, `.ts`, `.tsx`, `.ps1`, `.cs`, `.go`, `.rs`
- Framework clues in imports, config files (`.eslintrc`, `tsconfig.json`, `pytest.ini`)

### 2. Architecture Discovery

Understand component organization and interactions:

- **Directory structure** reveals separation of concerns
- **README.md** often describes high-level architecture
- **Entry points** (main.py, index.tsx, Program.cs) show startup flow
- Look for component boundaries: `frontend/`, `backend/`, `api/`, `cli/`, `lib/`
- Identify data flow: REST APIs, GraphQL, WebSockets, file-based, event streams

### 3. Communication Pattern Recognition

Document how components interact:

- API endpoints and protocols (REST, gRPC, WebSocket)
- Data formats (JSON, Protobuf, XML, NDJSON)
- Authentication mechanisms (OAuth, JWT, API keys)
- Event systems (pub/sub, message queues, filesystem watching)
- File-based communication (shared state, artifacts)

### 4. Design Standards Extraction

Identify coding conventions and patterns:

- **Naming conventions**: File naming, function naming, variable casing
- **Code organization**: MVC, MVVM, layered architecture, modular structure
- **Error handling**: Try/catch patterns, error propagation, logging
- **State management**: How state is stored and updated
- **Testing patterns**: Unit tests, integration tests, file locations

### 5. Standards Documentation

Look for documented standards:

- **AGENTS.md** → Operational procedures (how to run, test, build)
- **LEARNINGS.md** → Anti-patterns and gotchas to avoid
- **Test files** → Testing conventions (`.test.ts`, `test_*.py`, `*_spec.rb`)
- **Config files** → Linters, formatters, type checkers

---

## Guidelines

### Autonomous Operation

- **Make informed inferences** from the evidence you observe
- **Do NOT ask questions** - analyze and document what you find
- **Be specific**: Reference actual files, directories, patterns you see
- **Avoid speculation**: Only document what is observable in the code

### Gap Filling (if existing CONTEXT.md provided)

If an existing CONTEXT.md is included in your input:

1. **Identify what's missing**: New components, updated dependencies, undocumented patterns
2. **Correct outdated info**: Framework version changes, architectural shifts
3. **Preserve accurate parts**: Don't rewrite sections that are still correct
4. **Add detail**: Expand sparse sections with specific examples
5. **Note changes**: If you update something, mention it briefly

### Quality Standards

- **Concise but complete**: Every section matters, avoid fluff
- **Evidence-based**: Reference specific files or patterns you observe
- **Actionable**: Developers should be able to use this immediately
- **Structured**: Use consistent markdown formatting

---

## Output Format

Generate a complete markdown document with the following structure. **Output the markdown directly - do not wrap in code blocks or add commentary.**

```
# Context

[Brief 2-3 sentence project description]

## Tech Stack

### [Component Name 1]

- **Language:** [Primary language and version]
- **Framework:** [Framework name and version]
- **Runtime:** [Runtime environment]
- **Port:** [If applicable]
- **Dependencies:** [Key dependencies]
- **Location:** [Path to component root]

### [Component Name 2]

[Same structure]

### Communication Architecture

- **Component A ↔ Component B:** [Protocol, data format, purpose]
- **Component B ↔ Component C:** [Protocol, data format, purpose]

## Design Standards

- [Standard or convention with brief explanation]
- [Pattern with example if helpful]

## UX Rules

- [User experience principles if applicable]

## Architectural Invariants

- [Rule that must not be violated]
- [Invariant with rationale]

## Testing Standards

- [Testing framework and approach]
- [Coverage expectations]
- [Test file conventions]
- [How to run tests]

## File Organization

- `directory/` - [Purpose and contents]
- `another-dir/` - [Purpose and contents]

## Key Dependencies

[External services, APIs, or critical packages the project depends on]
```

---

## Examples of Good Documentation

**Tech Stack Example:**

```markdown
### Agent

- **Language:** PowerShell
- **Runtime:** Windows PowerShell / PowerShell Core (pwsh)
- **LLM Integration:** droid exec (Factory tool)
- **Authentication:** FACTORY_API_KEY environment variable
- **Location:** `.felix/felix-agent.ps1`
```

**Communication Architecture Example:**

```markdown
- **Agent ↔ Filesystem:** Direct read/write of project files (specs, plans, state)
- **Backend ↔ Agent:** Filesystem watching only (no IPC, sockets, or shared memory)
- **Backend ↔ Frontend:** REST API + WebSocket for real-time updates
```

**Architectural Invariant Example:**

```markdown
- Planning mode cannot commit code (enforced by guardrails)
- Building mode requires a plan (agent fails without plan file)
- One iteration equals one task outcome (atomic units of work)
```

---

## Critical Instructions

1. **Write to file** - Create or update `CONTEXT.md` with your analysis
2. **Be specific** - Reference actual file paths, patterns, and configurations you observe
3. **Stay factual** - Only document what you can verify from the codebase
4. **Fill gaps** - If existing CONTEXT.md provided, identify and add missing information
5. **Maintain structure** - Use the output format template consistently

Begin your analysis now.
