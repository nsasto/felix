# Ralph Explained

## The Problem Ralph Solves

You've probably seen this before: an AI coding agent starts strong, then gradually loses context. It forgets what it did three steps ago. It duplicates code. It breaks things that were working. The more it does, the more confused it gets.

Why does this happen?

**Context pollution.**

AI models have a "smart zone" - a sweet spot where they have just enough context to be brilliant, but not so much they're overwhelmed. Most agent systems fight this by trying to cram more and more into the context window. Ralph takes the opposite approach.

**Ralph keeps the agent in its smart zone by starting fresh every time.**

## The Core Insight

Imagine you're teaching someone to build a house, but they have short-term memory loss. Every morning, they forget what happened yesterday.

Most people would say: "That's impossible! How can they build anything?"

But Ralph figured out the trick: **Write everything down in the right places.**

Each morning, your builder:

1. Reads the blueprint (what we're building)
2. Reads the plan (what to do next)
3. Reads the operations manual (how to use the tools)
4. Does ONE thing
5. Updates the plan
6. Goes to sleep

Tomorrow, they wake up fresh. No confusion. No accumulated mistakes. No "wait, why did I do that yesterday?"

**That's Ralph.**

## The Three Phases

Ralph isn't just "run the agent in a loop." It's a funnel with three distinct phases:

### Phase 1: Define Requirements (Human-Led)

Before the agent does anything, a human writes clear requirements.

Not a novel. Not vague wishes. **Clear, narrow specs.**

Each spec answers: "What should exist?" Not how, not when - just what.

**Example:**

- Good: "User can sign in with email and password"
- Bad: "We need authentication and it should be secure and maybe use OAuth and have 2FA eventually"

The rule of thumb: one sentence without the word "and."

If you can't describe it simply, split it.

### Phase 2: Planning Mode (Agent Plans with Iteration)

Now the agent reads your specs and generates a plan - but it doesn't stop at the first draft.

**Planning is iterative with self-review:**

1. Generate initial plan
2. Review against 5 criteria:
   - Philosophy alignment (Ralph principles)
   - Tech stack consistency
   - Simplicity (avoid over-engineering)
   - Maintainability
   - Scope appropriateness
3. Refine and simplify
4. Repeat until satisfied
5. Signal completion: `<promise>PLAN_COMPLETE</promise>`

The plan is just a prioritized list of concrete tasks:

```
1. Create user database schema
2. Add password hashing utility
3. Build login endpoint
4. Add authentication middleware
5. Write integration tests
```

**Key insights:**

- The plan is disposable. If it gets stale or wrong, regenerate it.
- Planning loops multiple times to ensure quality before building starts
- The agent in planning mode has ONE rule: **No code changes.** Only planning.
- Plans are scoped to a single requirement, not the entire project

### Phase 3: Building Mode (Agent Executes)

This is where the magic happens.

The agent:

1. **Loads fresh context** - Reads specs, reads plan, reads how-to-run guide
2. **Picks ONE task** - The most important incomplete item
3. **Investigates first** - Searches the codebase: "Does this already exist?"
4. **Implements** - Writes the code
5. **Validates** - Runs tests, builds, lints
6. **Updates artifacts** - Marks task done, updates status
7. **Commits**
8. **Exits**

Then the whole loop starts over. Fresh agent. Fresh context. No baggage.

## Why This Works

### 1. Context is Everything

AI models are like humans: they're brilliant when focused, confused when overwhelmed.

Ralph keeps every iteration focused on:

- What we're building (specs)
- What to do next (plan)
- How to do it (operational guide)

That's it. No 10,000-line conversation history. No "wait, what were we doing?"

### 2. File-Based Memory

Instead of context windows, Ralph uses **the file system as memory.**

The agent doesn't need to remember what happened yesterday - it's written down:

- Specs persist
- The plan persists
- Progress is in git commits
- Instructions are in files

The agent just reads the files, does work, updates the files, and exits.

### 3. Backpressure is the Steering Wheel

Here's the real trick: Ralph doesn't try to make the agent "smart enough" to avoid mistakes.

Instead, it uses **backpressure** - automatic checks that force self-correction:

- Tests fail? Fix them or mark the task blocked.
- Build breaks? Fix it or mark blocked.
- Types don't check? Fix it or mark blocked.

The agent can't move forward until these pass. It's not optional polish - it's the mechanism that keeps quality high.

### 4. Naive Persistence

This is the philosophical foundation: **The agent doesn't need to be clever about memory.**

Just restart it in a simple loop. Progress is on disk. Tests validate correctness. Git tracks history.

No complex orchestration. No sophisticated memory management. No agent trying to "remember" what it did.

**Naive persistence: dumb outer loop, smart agent inside.**

## The Ralph Loop in Practice

Here's what actually runs:

```bash
while true; do
  # Load artifacts
  # Run agent (planning or building mode)
  # Update artifacts
  # Check if done
done
```

That's it. Seriously.

The sophistication is in:

- How the artifacts are structured
- What the agent is prompted to do
- How backpressure validates progress

Not in the loop itself.

## The Artifacts

Ralph systems center on a few key files:

### `specs/` - What to Build

Narrowly scoped requirement documents. Human readable. Stable over time.

Each file answers one question: "What should this thing do?"

### Plans - Two-Tier System

**`IMPLEMENTATION_PLAN.md` (root)** - Optional master plan for humans:

- Comprehensive view of the entire project
- Shows overall approach and architecture
- Not read by the agent during execution

**`runs/<run-id>/plan-<req-id>.md`** - Agent execution plans:

- Narrow scope (single requirement only)
- Current prioritized task list for that requirement
- Updated by the agent as work progresses
- **This is disposable.** If it's wrong, regenerate it.

### `AGENTS.md` - How to Operate

The operational guide: how to run tests, start the dev server, build the project.

This must stay short and operational, or it pollutes every loop with noise.

### `felix/requirements.json` - Structured Status

Machine-readable registry of requirement IDs, status, and dependencies.

Lets automation and UIs query progress without parsing Markdown.

## Common Misconceptions

### "Won't restarting make it slow?"

No. Reading a few files is instant. The "memory" overhead of long context is actually slower and less reliable.

### "But won't it forget important context?"

If it's important, **write it down.** That's the whole point. Force yourself to make knowledge explicit and file-based.

### "What if the plan gets out of date?"

Regenerate it. That's why it's disposable. Better to regenerate than to try to "patch" a stale plan.

### "Won't it duplicate work?"

Not if you follow the rules. Building mode has an explicit step: **"Investigate existing code first."**

The prompts guard against this: "Don't assume not implemented."

## The Meta-Lesson

Ralph is about **building better constraints** instead of trying to prompt the agent to be perfect.

Bad approach: "Please remember everything and don't make mistakes."

Ralph approach: "You can only see these files. You can only do one thing. Tests must pass to proceed."

**Shape the environment, don't beg the model.**

## Felix: Ralph as a Product

Felix is what happens when you take Ralph's philosophy and turn it into an operable system:

- Rules become runtime behavior
- Modes are explicit and enforced
- Artifacts are structured
- State is durable and inspectable
- Runs are auditable

Ralph is the insight. Felix is the implementation.

---

## Summary: Ralph in One Minute

1. **Write clear, narrow specs** (human)
2. **Generate a disposable plan** (agent, planning mode)
3. **Loop:**
   - Load specs + plan + operations guide
   - Pick one task
   - Implement
   - Validate with tests
   - Update status
   - Commit
   - Exit
4. **Repeat** until done

Keep the agent in its smart zone by starting fresh every time.

Use files as memory. Use tests as steering. Keep it simple.

That's Ralph.
