# Completion-driven Pueue agents

Status: core implementation complete and validated; the extension and design
are bundled alongside personal skills in the `pineapplehunter` Pi package. Temporary implementation tasks live under
`/tmp/pi-tasks/nixos-config-03c5cf0c8e/todo`.

## Agreed design

Keep Pueue as executor; replace blocking waits with automatic notifications.
Assume the same Pi session for the lifetime of queued work. Notify for every
completion in that sandbox's private daemon, without `pueue-watch` or
`pueue-yield` tools. Agents end their responses naturally when only background
work remains, leaving Pi alive and idle.

```text
Agent: pueue add / pi-subagent
  -> Pueue returns task ID
Agent: performs independent work, then ends its response
Pueue: task finishes
  -> callback atomically publishes an event in private /run
pueue-tool/index.ts: reconciles status and sends a completion message
  -> idle Pi starts a turn; busy Pi queues a follow-up
Agent: inspects results and continues the original request
```

Pueue 4.0.4 supports `daemon.callback`; Pi 0.87.1 supports idle turn triggering,
queued custom follow-ups, and actionable pre-settlement boundaries. No Pi fork
or host-wide notification broker is required.

## Transport and combined extension

- `wrapper/pueue.yml` invokes the packaged `pi-pueue-complete --id {{id}}`.
  Parent and child daemons use the same configuration.
- `wrapper/pueue-complete.py` atomically renames a small event file into
  `/run/pi-pueue/completions`. It does not need an active listener.
- Only the numeric ID is interpolated into the shell callback. Pueue callback
  templates are not shell-escaped, so never interpolate task commands/output.
- `extensions/pueue-tool/index.ts` combines the former running-task status display with
  completion notification handling. One shared status query updates the UI and
  identifies terminal results. Hooks trigger prompt reconciliation; a ten-second
  infrastructure timer recovers missed hooks/watch events and refreshes status.
- Events are hints; `pueue status --json` is authoritative. Reconcile before
  final settlement as well, preventing callback delay from hiding a fast task.
- Deduplicate task attempts using IDs and start/end timestamps. Track queued
  notifications and those included in model context; persist processed keys in
  Pi session entries after a completed run. Rebuild from the active branch on
  reload. Full crash-level exactly-once execution is not promised.
- Completion messages use Pi's default labelled, coloured custom-message popup,
  not a custom plain-text renderer. They show `Task N "label" (group): "result".`,
  the queued command as Markdown code, and a short log-inspection/continuation
  instruction. Missing labels and the default group are omitted. The same concise
  content reaches the user and model; task logs are not automatically injected.
  Failed and cancelled tasks also notify. Backtick-containing commands use safe
  code delimiters, and explicit Markdown breaks keep the three-line layout.
- Watchers and timers start at session startup and are cleaned up on shutdown
  or reload. `PI_PUEUE_NOTIFY_DIR` gates activation so host queues are not watched.
- After an abort/error, interactive automatic turns pause. A new user prompt or
  `/pueue-notifications` resumes them; `off` pauses them without cancelling tasks.

## Interactive log browser

`/pueue-logs` opens an automatically refreshed task list, including queued,
running, failed, cancelled, and other retained finished tasks. Arrow keys select
and Enter opens logs; `/pueue-logs <id>` opens a task directly. Running tasks use
`pueue follow`; other tasks stream `pueue log --full`. The viewer retains the
last 5,000 lines rather than loading arbitrarily large logs into memory.

Use arrows/Page Up/Page Down to scroll, Home/End to jump, and `f` to toggle
following the bottom. Escape returns to the list, then closes it; Ctrl+C closes
immediately. Closing, reloading, or shutting down kills only viewer processes
and clears its refresh timer, never cancelling the task. Completion handling
remains independent, and viewed output is not sent to the model.

Subagent-labelled tasks display readable activity parsed from the RPC events
streamed into their parent Pueue task's stdout: assistant text, tool calls/results,
errors, and final lifecycle events. `v` toggles raw output. The launcher tees the
same bytes to `stdout.log` for compatibility, flushing both destinations as
output arrives. Pueue retains output separately for each task, so later resumes
do not overwrite earlier tasks' activity. No file mapping or state-directory
lookup is needed. Older launches that only logged to a file have no archived
activity in Pueue. Cleaned Pueue tasks cannot be browsed. Child-private Pueue
task lists are deliberately not exposed.

The browser requires interactive Pi; RPC and print modes cannot open it.

### Layout and references

The browser uses a rounded, padded panel, a theme-highlighted selected row,
semantic status colours, and aligned ID/status/name/group columns. Commands
appear only in a selected-task preview instead of crowding every row. Subagent
names omit the internal session UUID. A capped, fixed-height log viewport
separates status/command metadata from output and scroll/follow information.
Narrow terminals use status glyphs and shorter help; short terminals omit
secondary chrome. Width, height, clipping, and wrapping adapt to resizing.

Research was run alongside baseline tests. Useful existing patterns:

- [Pi session manager](https://github.com/vahidkowsari/pi-session-manager/blob/08856696489b1c737050f9b8e426516972ee96a8/extensions/session-manager.ts):
  a framed selector, concise human titles, dim secondary metadata, and bounded
  list height. Its older `@mariozechner` imports are not copied; this package
  uses the installed `@earendil-works` APIs. Its idle wait is unnecessary for
  this read-only observer and would interfere with viewing ongoing work.
- [Pi checklist](https://github.com/championswimmer/pi-checklist/blob/be4c84abf4bb10f0913422b14a3d4ca804ff8636/src/render.ts):
  rounded dialog chrome, semantic status colours, readable status glyphs, and
  compact summaries. We use ordinary Unicode instead of requiring Nerd Fonts.
- Installed Pi 0.87.1 `examples/extensions/preset.ts` and
  `overlay-qa-tests.ts`: themed borders, selection styling, streaming viewport
  sizing, and correct `visibleWidth`/`truncateToWidth` handling. Theme roles and
  callable overlay options are checked against installed declarations.

## Persistent subagents

`--print` exits after one invocation and cannot receive a later completion.
Replace it with `tools/subagents/runner.py`, which starts persistent RPC Pi and
sends the unchanged prompt-file contents through RPC. Preserve model/session
arguments, sandbox mounts, native conversations, and the report file contract.
With launcher `--no-inherit-resources`, child Pi disables automatic extensions
and skills but explicitly loads the Nix-pinned `pueue-tool/index.ts`; the required
completion lifecycle remains active without loading other inherited extensions.

The extension checks at every pre-settlement boundary:

1. Every private Pueue task is terminal.
2. Every task completion has been included in model context.
3. A completed agent run has processed those notifications.
4. No queued completion or automatic continuation remains.

The launcher sets stdout to blocking mode and the RPC runner restores blocking
mode before each forwarded record. A child can change flags on inherited stderr
sharing the same sink after startup, so a startup-only setting is insufficient.
A non-blocking pipe can otherwise truncate a large RPC record and fail when its
reader briefly falls behind; the former file-only sink did not expose this.
Slow-reader tests cover records larger than pipe capacity, including a child's
post-startup flag change, while preserving exit status and the compatibility copy.

Only after these checks and final `agent_settled` does the extension request
shutdown. This avoids a separate runtime-state-file protocol: the runner drains
RPC events until Pi exits and validates the extension's explicit success/failure
entry. Missing extensions, RPC/extension failures, provider errors, aborts, and
daemon-check failures must not masquerade as successful child completion.

If new tasks are enqueued during result processing, repeat the cycle. Intermediate
responses are not final reports. The child writes `response.md` after processing
all results; the outer parent task finishes only after the child exits.

“Read” means included in a model request followed by a completed run. It cannot
prove cognitive attention or full log inspection; instructions require inspecting
logs as needed and continuing the original task.

## Implementation checklist

- [x] Package the atomic hook and share its configuration with children.
- [x] Combine status and notifications in `pueue-tool/index.ts`.
- [x] Add persistent RPC runner and child settlement coordination.
- [x] Update Pueue/build/subagent guidance without watch/yield tools.
- [x] Remove the obsolete blocking wait implementation.
- [x] Complete integration tests, packaging checks, and all-systems evaluation.
- [x] Bundle `pueue-tool/index.ts` and this design documentation in the
  `pineapplehunter` Pi package alongside `skills/pueue` (temporary task 05).

## Validation

Use scripted, zero-cost model providers with real Pi RPC and real isolated
Pueue daemons. Cover idle wakeups, completion while busy, immediate completion,
multiple task waves, failed-task results, and agent/extension failures. Verify
that the parent-facing child task cannot finish before all results are processed.
Also verify watcher cleanup, deduplication, and the merged running-status UI.

Stage only new Nix-referenced source files before evaluating; then run
`nix flake check --no-build --all-systems`. Build the small Python packages to
exercise writer linting without activating Home Manager or changing live Pi.

## Limits

This resumes a living interactive/RPC Pi process, not one whose sandbox has
been destroyed. Session switching and a host supervisor are outside this change.
Ordinary `--print`/JSON remain single-shot and do not support idle wakeups.

There is no longer an inactivity timeout. Tasks that remain paused, stashed,
queued, or hung keep children alive until finished or cancelled. Completion
notifications alone cannot detect a task that never finishes.

## References

- https://github.com/Nukesor/pueue/blob/v4.0.4/pueue/src/daemon/callbacks.rs
- Installed Pi `docs/extensions.md`, `docs/rpc.md`, and `docs/json.md`.
- Installed Pi `examples/extensions/file-trigger.ts`,
  `dist/core/agent-session.js`, and `dist/modes/rpc/rpc-mode.js`.
