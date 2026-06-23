## Graphify Investigator

Graphify is an optional repository knowledge graph. Use it when it will reduce broad searching or repeated file reads, especially for architecture, call-flow, dependency, symbol, and cross-file relationship questions.

Prefer these commands before large grep/read sweeps:

- `felix graphify query "<question>"`
- `felix graphify path "<from>" "<to>"`
- `felix graphify explain "<symbol>"`

If the Felix wrapper is unavailable, use the native equivalents: `graphify query`, `graphify path`, and `graphify explain`.

Do not paste or read `GRAPH_REPORT.md` wholesale into the prompt. Query the graph, inspect the small set of files it identifies, and fall back to normal Felix search when Graphify is missing, stale, or not useful.
