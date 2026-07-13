# Public Repository Research

When researching code in a public repository, prefer inspecting a local clone over repeated remote searches.

If you expect to search the same public repository multiple times, or if remote searches are not quickly answering the question, use the `sandbox-info` skill, then clone the repository locally and inspect it with local search/read tools.

Use a shallow clone when history is not needed. Put public repository clones under `/tmp`; in this sandbox, `/tmp` is persistent per project so checkouts can be reused across opencode restarts and future sessions for the same project.
