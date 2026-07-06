# Public Repository Research

When researching code in a public repository, prefer inspecting a local clone over repeated remote searches.

If you expect to search the same public repository multiple times, or if remote searches are not quickly answering the question, clone the repository locally and inspect it with local search/read tools.

Use a shallow clone when history is not needed. Prefer `/persistant` for public repository clones so the checkout can be reused across the session or future sessions. Use `/tmp` only when the clone is clearly disposable and persistence is undesirable.
