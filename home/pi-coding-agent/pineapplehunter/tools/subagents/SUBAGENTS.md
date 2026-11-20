# Pi subagent launcher

```text
pi-subagent <name> <directory> <prompt_file> [--profile <preset>]
            [--resume <session_id>] [--context <text>]
            [--no-inherit-resources]
```

Home Manager packages `launcher.py` with `pkgs.writers.writePython3Bin` (including
build-time flake8 linting), substitutes only the RPC runner path, and puts it directly in
`sandboxTools`. Commands run by binary
name using the inherited parent PATH. There is no CLI-specific wrapper.

Run `pi-update` before launching subagents. The workflow skill is installed at
`~/.pi/customizations/package/skills/subagents/SKILL.md`.

## Optional extension/skill isolation

By default, children load the parent's configured/discovered extensions and
skills. **Do not use `--no-inherit-resources` by default.** Use it only when an
inherited tool, extension, or skill would interfere with the objective—for
example, to test Pi's tools in isolation or review a skill without loading it
first:

```bash
pi-subagent review-skill /tmp/review-workspace /tmp/review-task.md \
  --no-inherit-resources
```

Every child explicitly loads the pinned snapshot's public
`extensions/pueue-tool/index.ts` and private `extensions/subagent-pueue/index.ts`
adapter. Normal discovery deduplicates canonical extension paths. With this
flag the launcher also passes `--no-extensions --no-skills`, but retains both
explicit extensions. A `codex-host/...` preset also explicitly loads the pinned
`extensions/codex-host/index.ts` in either mode. Run the updater to install
these paths; missing required files fail launch. The runner requires both `pueue-notifications` and
`subagent-pueue-status` commands before sending the initial prompt.

Built-in tool selection, authentication, model/thinking settings, project
instructions, prompts, and themes are unchanged. Pi's built-in inline helpers
(such as its `llama` command) can still load; the flags suppress discovered and
configured resources, not those built-ins. Configured packages are still
resolved by Pi; this is resource-loading suppression, not package removal or a
filesystem/credential security boundary. Except for the explicit extensions
above, custom tools/providers supplied by extensions are unavailable in this
mode; use normal inheritance if needed.

The flag is forwarded to the queued worker and printed resume command. Repeat
it on manual resume to keep this mode; there is no separate mode metadata.
Switching modes does not erase existing native conversation history. For a
clean-reference evaluation, start a fresh session and supply reference files in
the workspace or task document.

## Host Codex preset handoff

Start broker-enabled plain `pi` and use `/subagents` to explicitly choose a
`codex-host/<model>` preset. No CLI account or socket path is needed. The
launcher accepts only the normal wrapper's `PI_CODEX_HOST_SOCKET` pointing to
`/run/pi-codex-host/broker.sock`. It checks the socket at submission and again
in the queued worker. An internal boolean marks the authorization in the
queued command; no credential, route or socket override is stored in session
metadata. Only the socket inode is mounted read-only, not its directory;
non-`codex-host` presets do not receive it. Host broker account files are not
mounted. Existing Pi settings and independent Pi logins still follow the
ordinary resource-overlay rules below.

A fresh brokered child does not inherit the parent's `/codex-route` selection
or saved default. It uses the broker's default route (Auto with both accounts,
otherwise the available single-account route). The sandbox masks
`codex-route-default` without modifying the parent file. A brokered resume can
restore the **child's own** route from its native history. Mounting only the
socket inode means a running worker may lose access if the host replaces the
socket; resume from a fresh parent sandbox if needed.

No presets are rewritten. Use `/subagents` to replace retired `codex-host-*`
provider IDs. To resume with a new selection, supply `--profile <preset>`;
otherwise a retired saved selection fails with a diagnostic.

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
selection.json   # Resolved model/thinking retained for resume
sessions/        # Native Pi JSONL conversation files
prompt.md        # Snapshot of the task file only
response.md
stdout.log       # Latest-run compatibility copy of task stdout
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
tmp and runtime directories. The configured UPKI cache is mounted read-only,
so inherited `curl-upki` can check revocation without writing to the host cache.
Networking and environment/PATH are inherited. The supplied project is trusted by default.

`~/.pi` and any custom agent directory outside it are writable `--tmp-overlay`
mounts. Existing settings/auth and package files remain available. Extensions
and skills load normally unless `--no-inherit-resources` is supplied; this flag
changes discovery, not the mounts. Upper-layer changes vanish on exit and never
modify the parent.
Nix-store symlink targets remain immutable unless copied into the writable
resource overlay. Parent session directories are hidden with tmpfs, and only
child session storage is bound persistently. The launcher explicitly unsets
inherited `PUEUE_CONFIG_PATH` and `PI_PUEUE_NOTIFY_DIR` with Bubblewrap's
`--unsetenv`; it neither copies a config nor starts pueued. The public extension
creates a fresh private daemon/config/callback/tempdir for each interactive/RPC
Pi process and exports those variables for subsequent commands. Print/JSON mode
starts no daemon. Reload/new/resume/fork in the same process preserve the daemon;
quit kills tasks/daemon and removes its tempdir. Desktop service sockets and the
parent Pueue socket are not mounted; no inherited config/host queue is attached.

## Prompt and results

The task file is copied unchanged to `prompt.md` and sent as an RPC prompt by
`runner.py`. `--append-system-prompt` supplies fixed environment/reporting instructions
separately, so the task file need not describe the sandbox or report location.
Optional `--context` (`-c`) adds literal per-worker context to those system
instructions without modifying the task file. This permits independent agents
to share a task document while receiving different assignments. Context is
forwarded to the queued worker and preserved in the printed resume command;
manual resume can supply different context without a separate metadata registry.

The runner uses persistent `pi --mode rpc`, not single-shot `--print`. The
public `pueue-tool/index.ts` extension owns the process-private Pueue runtime.
The public extension starts a turn while idle or queues a follow-up while busy.
The private `subagent-pueue/index.ts` adapter supplies subagent formatting and
child shutdown. Agents end responses naturally when waiting; there are no
watch/yield tools.

Before settlement the core reconciles authoritative Pueue status, so a late
callback cannot cause premature exit. It tracks notifications included in model
context and marks them processed after a completed run. The adapter requests RPC
shutdown only after the core reports all results processed and Pi is settled.
It emits `pueue-subagent-exit` with `{success,error}` before shutting down the
child; the runner requires explicit successful settlement.
Provider errors, aborts, daemon-check failures, and extension failures cause a
nonzero runner exit rather than successful completion. The runner validates
that the extension is loaded and continuously drains JSONL stdout. The launcher
streams this output (including stderr) into the parent Pueue task's stdout and
tees it to `stdout.log`, flushing both as bytes arrive. `/pueue-logs` displays
readable activity from the task's Pueue output, with a raw-output toggle. Pueue
retains each task's log independently across resumes until cleaned.
Native sessions and `response.md` remain the result contract; `stdout.log` and
the final report are latest-run state, not per-task archives.

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

## Model presets and UI

Run `/subagents` in Pi to add/edit named presets (for example `light` and
`deep`) and choose the default. The menu selects fully qualified provider/model
IDs and thinking levels separately. The terminal model picker follows Pi's
built-in picker: type to fuzzy-filter provider, model ID, or model name; use
arrow keys and Enter to select, or Escape to cancel. The scrolling list shows
at most ten models and shrinks for short terminals.
Each completed change is saved immediately;
cancelling a model/thinking dialog leaves that preset unchanged.
Use **Delete preset** to remove a preset after confirmation. Deleting the default
requires choosing a replacement unless it is the last preset. Cancelling that
choice keeps the preset. Deleting the last preset clears the default; configure
a new preset before launching another agent. Existing agents retain their saved
model/thinking selection.

At parent Pi startup, the extension validates the file and warns if it is
missing, empty, malformed, or has invalid presets/defaults. Validation does not
create or overwrite settings. Non-UI sessions and child agents skip the warning.

Each wrapper profile uses its own `$PI_CODING_AGENT_DIR/subagents.json`
(for example, `~/.pi/agent/subagents.json` for `pi` and
`~/.pi/agent-auto/subagents.json` for `pi-auto`). `PI_CODING_AGENT_DIR` is
required; there is no fallback to another directory or wrapper's presets.
Configure presets separately with `/subagents` in each wrapper.

Example for `pi-auto`:

```json
{
  "defaultProfile": "light",
  "profiles": {
    "light": { "model": "codex-auto/gpt-6-luna", "thinkingLevel": "high" },
    "deep": { "model": "codex-auto/gpt-6.1-sol", "thinkingLevel": "medium" }
  }
}
```

Use `--profile deep` to select a preset, or omit it to use the default.
Model and thinking are configured only through presets, not executable flags.
Parent `PI_MODEL`, `PI_PROVIDER`, `PI_REASONING_LEVEL`, `PI_SESSION_ID`, and
`PI_SESSION_FILE` are not passed into the child. Missing configuration and unknown presets fail rather than silently
selecting another model. Launch JSON includes the resolved selection.
The old single-model config remains readable and appears as `legacy` in the UI;
it migrates on the first saved UI change.

The resolved model/thinking is stored in `selection.json`. Queued workers read
that snapshot. Resume reuses it unless `--profile` is supplied. Older sessions
without that file use the current default. Changes to presets affect new launches, not queued workers
or existing resumed selections.

The UI lists only models Pi reports available through configured credentials
in the current parent; quota and service availability are not checked.
Legacy `codex-auto` requires `pi-auto` and the provider extension; it is
unavailable with `--no-inherit-resources`. Choosing a preset does not install a
provider or supply credentials. Use provider-qualified `openai-codex/...` presets to select upstream
Codex explicitly.
