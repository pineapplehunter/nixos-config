# Pi subagent launcher

```text
pi-subagent <name> <directory> <prompt_file> [--model <model>]
            [--thinking <level>] [--resume <session_id>] [--context <text>]
```

Home Manager packages `launcher.py` with `pkgs.writers.writePython3Bin` (including
build-time flake8 linting) and puts it directly in `sandboxTools`. Commands run by
binary name using the inherited parent PATH. There is no CLI-specific wrapper.

See [the subagents skill](../../skills/subagents/SKILL.md) for the workflow.

## SIMA: Single Instruction, Multiple Agents

**SIMA is the recommended pattern for parallel agents with similar context but
different jobs.** Give every agent the same task file containing common
requirements and named jobs, then select its job with `--context` (`-c`). Keep
workspaces and sessions independent; the parent integrates results.

Just as SIMT (Single Instruction, Multiple Threads) uses a common program with
per-thread data, SIMA uses a common instruction document with per-agent roles.
This is a conceptual analogy, not GPU-style synchronized execution: agents may
follow different steps, and shared instructions do not imply shared writable
state. Use separate task files for unrelated contexts.

See the skill's SIMA section for concrete launch examples.

## Native sessions, not a metadata registry

A new invocation generates a native Pi session ID. Resume takes that ID explicitly
alongside the label, workspace, and task file. These values need not be recorded
in a separate metadata structure: Pi owns the conversation, Pueue owns execution
status, and the caller owns the workspace.

Session state lives at `/tmp/pi-subagent-state/<session_id>`:

```text
control.lock
execution.lock
sessions/        # Native Pi JSONL conversation files
prompt.md        # Snapshot of the task file only
pueue.yml        # Fixed configuration for the child's private daemon
response.md
stdout.log
tmp/
```

The launcher supplies `--session-dir` and `--session-id` to Pi. A resume must find
an existing native session under the fixed state root. Changing the backing
workspace or label does not change the session. Always invoke from the same
original project directory; the mount path is the calling cwd and state storage
is fixed at `/tmp/pi-subagent-state`. Neither has a CLI override.

Control operations use flock. A separate lock is held while Bubblewrap runs.
Queued/running/paused Pueue tasks are matched by a session-specific label prefix,
preventing concurrent reuse without persisted task metadata. There is no status
or cleanup command. Inspect tasks with Pueue and remove finished state using
`rm -rf -- <state_directory>`.

## Sandbox

Bubblewrap starts with an empty root, mounts the supplied workspace at the
original project path, exposes the Nix store/daemon, inherits whole read-only
`/etc`, `/bin`, and `/usr` mounts from the parent sandbox, and provides private
tmp and runtime directories. Networking and environment/PATH are inherited. The supplied project is trusted by default.

`~/.pi` and any custom agent directory outside it are writable `--tmp-overlay`
mounts. Existing skills, extensions/tools, settings, auth, and packages load
normally; their upper-layer changes vanish on exit and never modify the parent.
Nix-store symlink targets remain immutable unless copied into the writable
resource overlay. Parent session directories are hidden with tmpfs, and only
child session storage is bound persistently. Each child starts its own Pueue
daemon. Desktop service sockets and the parent Pueue socket are not mounted.

## Prompt and results

The task file is copied unchanged to `prompt.md` and supplied via Pi's `@file`
input. `--append-system-prompt` supplies fixed environment/reporting instructions
separately, so the task file need not describe the sandbox or report location.
Optional `--context` (`-c`) adds literal per-worker context to those system
instructions without modifying the task file. This permits independent agents
to share a task document while receiving different assignments. Context is
forwarded to the queued worker and preserved in the printed resume command;
manual resume can supply different context without a separate metadata registry.

Those instructions describe overlays, native sessions, private Pueue, changed
workspace scope, relative changed-file paths, test results, missing-input
requests, and the report at `/run/pi-subagent/response.md`. Nested agents are
prohibited by guidance, not by an execution security boundary.

The submitter receives JSON with native session ID, Pueue task ID, and result
paths. On successful completion, task stdout includes a complete resume command.
Native saved history is reused on resume; the parent's transcript is not copied.
Pueue calls the launcher with `--run`, an internal worker argument documented in
a separate help section. It executes the child instead of submitting another
task. Pueue retains the original project's working directory, so no project-path
argument is needed.
Model/thinking choices come from CLI overrides, then parent `subagents.json`,
then parent Pi environment. No separate model/approval registry is maintained.
