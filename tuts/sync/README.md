# Understanding Felix Sync: A Journey Through Distributed Systems

**Welcome to the most interesting part of Felix** – the system that makes local agent runs visible to your entire team, without any of the agents caring whether the server is up or down.

This isn't your typical "sync to cloud" feature. This is a masterclass in building resilient distributed systems that work offline-first, fail gracefully, and never block the user.

## What You'll Learn

This tutorial series will take you deep into:

1. **[The Big Picture](01-architecture.md)** - Why we built sync this way (spoiler: most systems get this wrong)
2. **[The Outbox Pattern](02-outbox-pattern.md)** - The single best pattern for reliable distributed systems
3. **[PowerShell Plugin](03-cli-implementation.md)** - Building a production-grade CLI sync client
4. **[FastAPI Backend](04-backend-implementation.md)** - REST endpoints, rate limiting, and idempotency
5. **[Database Design](05-database-schema.md)** - Schema evolution and the agent_id saga
6. **[Frontend Integration](06-frontend-viewer.md)** - Making artifacts beautiful in React
7. **[Battle Scars](07-lessons-learned.md)** - Every bug we hit and how we fixed it
8. **[Testing Strategy](08-testing.md)** - E2E tests that actually catch problems
9. **[Operations Guide](09-operations.md)** - Running this in production

## Why This Matters

Every developer will eventually need to build a system where:

- Local tools need to report to a central server
- Network failures are common
- You can't afford to block users
- Data must eventually reach the server

You could spend months learning these lessons the hard way. Or you could spend a few hours reading how we solved it.

## The 30-Second Pitch

Felix agents run autonomously on developers' machines, writing files locally. When sync is enabled, a background plugin quietly uploads these artifacts to a team server – but if the network is down, the plugin just queues the upload and tries again later. The agent never waits, never crashes, and never knows if sync succeeded.

**That's the whole system.** Everything else is just making that simple idea bulletproof.

## What Makes This Interesting

This isn't a tutorial about "how to POST to an API." This is about:

- **Resilience** - How to build systems that work when everything else is broken
- **Observability** - Making invisible background processes visible (without being annoying)
- **Type Safety Hell** - PowerShell integers vs Python strings (you'll laugh, then cry)
- **Database Migrations** - Adding columns without breaking production
- **Rate Limiting** - Protecting your server from enthusiastic agents
- **Testing Distributed Systems** - How to simulate network failures reliably

## Start Here

If you're new to distributed systems: Start with [The Big Picture](01-architecture.md).

If you've built sync systems before: Jump to [The Outbox Pattern](02-outbox-pattern.md) – we'll show you why this pattern is better than webhooks, polling, or message queues.

If you just want war stories: Skip to [Battle Scars](07-lessons-learned.md) for bugs and fixes.

If you're debugging sync right now: Go to [Operations Guide](09-operations.md).

---

**Ready?** Let's build a sync system that actually works.

[Start with Chapter 1: The Big Picture →](01-architecture.md)
