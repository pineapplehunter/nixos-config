# Pi snapshot subagents

Pi can submit child-agent turns to Pueue in private copies of the current project. The extension only creates snapshots, starts turns, and remembers their paths. The main agent manages Pueue tasks and reads Markdown responses directly.

## Tools

Only `subagents_enable` is initially active. It runs:

```console
pueue group add --parallel 4 subagent
```

and activates three tools:

| Tool | Purpose |
|---|---|
| `subagent_start` | Create a named child turn, or send another prompt to an existing child session. |
| `subagent_status` | Return the paths belonging to one or more named children. |
| `subagent_cleanup` | Delete a named snapshot after its task has finished or been stopped. |

`subagent_start` returns the state directory and the globally unique Pueue `task_id`. The same ID is stored in the state directory's `task-id` file. Pi uses its own Pueue daemon in the sandbox; these commands do not inspect the host's Pueue daemon. Pueue is the source of truth for execution state. Use existing shell tools and `pueue-wait`, for example:

```console
pueue status --json
pueue log <task-id>
pueue kill <task-id>
```

The extension does not poll, cancel, remove, or recover Pueue tasks.

## Default child model

Run `/subagent-model` in interactive Pi to select an available model and then a thinking level supported by that model. Both choices are saved as `model` and `thinkingLevel` in `<agent-dir>/subagents.json` (normally `~/.pi/agent/subagents.json`) and apply to future subagent turns, including turns in later Pi sessions. Select `(inherit parent model)` or `(inherit parent thinking level)` to leave either setting tied to the parent; the config stores `null` for inherited settings. Existing configs without `thinkingLevel` also inherit the parent level. The command does not change the parent or any already submitted task. If a saved model becomes unavailable or the saved thinking level is unsupported by the selected model, `subagent_start` fails with a prompt to choose again rather than silently changing the setting.

## Snapshot layout

Each named child has a directly inspectable directory:

```text
/tmp/pi-subagents/<name>/
├── baseline/     # initial project copy
├── workspace/    # writable child copy
├── tmp/          # private child /tmp and Pueue runtime
├── sessions/     # child Pi conversation context
├── prompt.md       # current prompt from the main agent
├── response.md     # current response from the child
├── stdout.log      # complete text output from child Pi
├── task-id         # latest Pueue task ID
├── queued          # exists while the Pueue task has not started
└── bwrap-info.json # Bubblewrap child PID in the parent PID namespace
```

Snapshots use Btrfs reflinks in `/tmp`, so unchanged files share storage with the source and only changed blocks consume additional disk space:

```console
cp -a --reflink=always "$PWD/." "$baseline/"
cp -a --reflink=always "$baseline/." "$workspace/"
```

If copying fails, creation fails and removes the partial directory. No special handling is applied to Git metadata, symlinks, or nested mounts.

Paths and session IDs exist only in extension memory. A restarted Pi does not recover earlier children. Normal Pi shutdown removes `/tmp/pi-subagents`; because `/tmp` is host-backed, an unclean shutdown may leave stale files. Only one parent Pi process should manage subagents in a project at a time. Stop active Pueue tasks before cleanup or shutdown.

## Starting a turn

The Pueue submission section in `subagents.ts` performs one operation: `pueue add --immediate`. Each task uses a label such as `reviewer:turn-2`, making agent turns easy to identify within the `subagent` group. The same file contains the two short shell commands used around Bubblewrap. Before submission, the extension creates an empty `queued` marker. When Pueue starts the task, the outer command removes that marker and opens `bwrap-info.json` for Bubblewrap's `--info-fd 3`; inside Bubblewrap, the launcher command starts the private Pueue daemon and child Pi. The resulting `child-pid` is in the parent PID namespace. Start and cleanup reject a name while either the queued marker exists or that PID is alive. The submitted command mounts:

```text
tmpfs               → /run
--dir                  /run/pi-pueue
--dir                  /run/pi-subagent
<state>/workspace   → <original-project-path>
<state>/sessions    → /run/pi-subagent/sessions
<state>/prompt.md   → /run/pi-subagent/prompt.md (read-only)
<state>/response.md → /run/pi-subagent/response.md
<state>/stdout.log  → /run/pi-subagent/stdout.log
<state>/tmp         → /tmp
```

The child sees the copied workspace at the same absolute path as the parent. It also gets private PID and `/proc` views. Other restrictions come from the outer Pi sandbox.

Child Pi uses the same generated session ID for every turn:

```console
pi --print \
  --session-dir /run/pi-subagent/sessions \
  --session-id <session-id> \
  @/run/pi-subagent/prompt.md \
  </dev/null
```

`PI_SUBAGENT_ROLE=child` prevents the extension from registering parent tools. The child retains the normal coding tools and skills except D-Bus-dependent tools (`notify`), which are made inactive. Its entire `/run` is a private tmpfs. It reuses the main `pueue.yml`, with `/run/pi-pueue` providing private sockets and daemon state. This is separate from the parent Pi sandbox's Pueue daemon.

## Communication

Communication uses only `prompt.md` and `response.md`.

The generated prompt tells the child to:

- freely modify the copied project;
- write its response to `/run/pi-subagent/response.md` before ending;
- request missing information in that file;
- report tests and changed files using paths relative to the current directory;
- avoid creating other subagents.

The main-agent flow is:

1. Call `subagent_start` and use the returned Pueue `task_id` (also available in the state directory's `task-id` file).
2. Wait with `pueue-wait` or inspect with raw Pueue commands.
3. Read `response.md`; use `subagent_status` if the state paths must be looked up again.
4. Inspect `stdout.log` when the complete child output is needed.
5. If another turn is needed, call `subagent_start` with the same name and a new prompt.

The child Pi output is redirected to `stdout.log`. On success, the Pueue output is only `The subagent has run successfully. The response can be found at \`path\``. Reusing a name overwrites `prompt.md`, clears `response.md`, and resumes the same workspace and Pi session. The queued marker and Bubblewrap PID check prevent a new turn while the previous one is queued or running.

`subagent_cleanup` deletes only the snapshot directory and in-memory entry. It does not change Pueue task records.

## Pueue footer status

The separate, model-invisible `pueue-status.ts` extension runs:

```console
pueue status --json status=running
```

every ten seconds. It displays nothing when idle, `pueue: N` for default-group work, or grouped counts such as `pueue: N(default) M(subagent)`. Its key is `usage-pueue`, placing it immediately after pi-usage's `usage` status.
