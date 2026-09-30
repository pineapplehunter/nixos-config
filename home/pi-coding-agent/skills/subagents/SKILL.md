---
name: subagents
description: Delegate tasks to independent Pi subagents using caller-prepared workspaces and the pi-subagent launcher. Use for parallel implementation, focused reviews, launching or resuming native Pi sessions, and inspecting their results.
compatibility: Linux, Bubblewrap with tmp-overlay support, Pi, and a running Pueue daemon; provided by this configuration.
---

# Subagents

Use `pi-subagent` through Bash. You manage input files, comparisons, integration,
and cleanup. The launcher runs an isolated Pi process and retains its native
session files, reports, and logs. Never invoke this workflow from a child
(`PI_SUBAGENT_ROLE=child`).

## Prepare

1. Create a dedicated workspace, normally under `/tmp`. Never use the live
   project or share a writable workspace between concurrent children.
2. Copy only inputs needed for the task, preserving project-relative paths.
   Include relevant instructions, imports, manifests, lockfiles, and tests.
   For a full copy, use `cp -a "$project/." "$workspace/"`. Do not use hard
   links: child edits would affect the originals.
3. Keep your own baseline copies if comparing changes. The launcher does not
   copy project files, maintain a baseline, or merge results.
4. Write the task to a prompt file. Include scope, constraints, expected output,
   and verification. Environment/reporting guidance is supplied separately by
   the launcher as appended system instructions; do not repeat it in the file.

## Launch

```bash
pi-subagent review /tmp/review-workspace /tmp/review-task.md
```

The three positional arguments are a human-readable name, prepared directory,
and prompt-file path (not literal prompt text). Always run from the original
project root: the calling directory is the project mount path. The workspace is
mounted at that absolute path; the original project is not mounted. Runtime
paths such as `/tmp`, `/run`, `/nix`, and the home directory itself cannot be
project targets.

The result is JSON containing `name`, `session_id`, `task_id`, `state_directory`,
`response_path`, and `stdout_path`. Retain the session ID and task ID. There is no
separate metadata registry or status command. State lives at
`/tmp/pi-subagent-state/<session_id>` and survives parent Pi exit/restart, but
not necessarily system tmp cleanup. This state root is fixed; it cannot be
overridden by arguments or environment variables. `--run` is an internal
Pueue worker argument, not part of the delegation workflow.

### Model and thinking

Each invocation reads `<parent-agent-dir>/subagents.json`, the same file used by
the former subagent tool:

```json
{"model": "provider/model", "thinkingLevel": "high"}
```

Explicit `--model provider/model` and `--thinking level` take precedence.
Configured null/missing values inherit the parent's current model/thinking from
Pi's environment. With neither defaults nor parent environment, Pi chooses its
own defaults or saved session settings. There is no separate model metadata.

The supplied project is trusted by default. The Nix daemon socket and
configuration are always exposed for builds and `nix develop`.

## Shared instructions, different workers

Use `--context` (or `-c`) to give each agent a role while reusing one task file:

```bash
pi-subagent frontend /tmp/frontend /tmp/tasks.md \
  -c "You are the frontend worker. Execute only the Frontend task."
pi-subagent tests /tmp/tests /tmp/tasks.md \
  -c "You are the test worker. Execute only the Tests task."
```

Context is literal text appended to system instructions, not a file path. The
shared task file remains unchanged. Define clear responsibilities in that file
and give each agent its own workspace and session. Tasks with dependencies
should run in separate waves rather than concurrently.

Context is forwarded to the queued worker and included in the printed resume
command. Supply it again on manual resume to retain the same role, or pass new
context to change the assignment. No separate role metadata is stored.

## Environment and resources

The child inherits the parent's PATH and environment, including API keys and
proxies. Child home, agent-directory, session, and Pueue configuration variables
are set explicitly. `~/.pi` is exposed through a writable tmpfs overlay, so skills,
extensions/tools, settings, credentials, and packages are available. A custom
agent directory outside `~/.pi` receives its own overlay. Changes in these
overlays are discarded after each run, including OAuth updates; they do not
propagate to the parent. Immutable Nix-store symlink targets remain read-only;
replace a symlink with a copied file/directory inside the overlay if edits are
needed. Do not edit the parent's resource directories to help a running child.

Parent session directories are hidden. Only the child's own conversation is
persisted separately at `/run/pi-subagent/sessions`. The child has a private
Pueue daemon, not the parent's task queue. Host desktop sockets/portals are not
mounted, so tools depending on those services may be unavailable despite being
loaded. Networking and Nix daemon capabilities are shared; this is not a
credential or network security boundary. The child's `/etc`, `/bin`, and `/usr`
are whole read-only mounts inherited from the existing parent sandbox.

## Wait and inspect

Use `pueue-wait` with the returned task ID once running. Inspect Pueue first if
queued; do not use a silent unbounded `pueue wait`.

```bash
pueue status
pueue log <task_id>
```

Read the report and stdout paths with the read tool. Inspect workspace changes
and verification results before integration. A successful Pi exit alone does not
establish task correctness. Successful task stdout prints a resumable command.

## Resume with the same or different inputs

```bash
pi-subagent review /tmp/new-workspace /tmp/follow-up.md --resume <session_id>
```

Supply the name, directory, and prompt file each time. The name is only a label;
`--resume` identifies the native conversation. A different backing directory is
allowed. Keep the original project mount path by invoking from the same project
root. Explain changed inputs in the brief because saved history can contain
observations about old files. The launcher tells the child to reread relevant
files.

The native session must already exist under the fixed state root. Each turn
replaces the prompt/report/stdout; retain previous reports separately if needed.
Never modify workspace files or remove state while a child is running. The
launcher rejects reuse while the session has a queued/running task or an active
execution lock. Pueue owns task status; it is not duplicated in a metadata file.

## Cleanup

Confirm completion with Pueue first. Stop and verify termination of active tasks
before deleting anything. Then remove the exact returned state path:

```bash
rm -rf -- /tmp/pi-subagent-state/<session_id>
```

This deletes saved conversation history, logs, and temporary files. Remove your
workspace and baseline copies separately after integration. There is no cleanup
command; removing files does not remove Pueue task records.

## Child prompt

Pi loads its normal system prompt and applicable user/project instructions and
resources. The launcher appends system instructions explaining workspace scope,
resource overlays, persisted sessions, tools, and response expectations. It
requires a report at `/run/pi-subagent/response.md`, relative changed-file paths,
test outcomes, requests for missing inputs, and no nested subagents. The prompt
file supplies only the task as a user message. Optional `--context` text is
appended separately to the system instructions. Resume also includes native saved
conversation history; the parent's transcript is never copied.
