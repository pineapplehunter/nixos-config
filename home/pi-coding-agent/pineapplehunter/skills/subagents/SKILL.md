---
name: subagents
description: "Launch, resume, and inspect Pi subagents. Use for focused reviews or SIMA parallel work: one shared task file, independent workspaces, and per-worker --context roles."
---

# Subagents

## Rules

- Use Bash from the **original project root**, never as `PI_SUBAGENT_ROLE=child`.
  The child sees project files at that cwd, **not** the parent's backing path.
  Parent-side `/tmp` baselines/reports are invisible: copy required inputs into
  the workspace or task file. The original checkout is not mounted.
  Launch cwd must not be `/`, home itself, or **at/below** `/tmp`, `/run`, `/nix`,
  `/proc`, `/dev`, `/etc`, `/bin`, `/usr`. `/tmp` backing workspaces are fine;
  never `cd` into them to launch.
- Copy inputs (including hidden instructions/configs, imports, manifests,
  lockfiles, tests) with relative paths preserved; keep a baseline. No live
  checkout, hard links, or concurrent shared workspace. Launcher copies/merges
  no project files. **Task files** specify scope, constraints, output, verification.
- `pi-subagent NAME WORKSPACE TASK_FILE` enqueues asynchronously. Save its JSON:
  `name`, `session_id`, `task_id`, `state_directory`, `response_path`, `stdout_path`.
  Name is a label. `--run` is internal; no launcher status/cleanup commands or
  state-root overrides exist. State is `/tmp/pi-subagent-state/SESSION_ID`.
- Optional `--no-inherit-resources` disables extension/skill discovery except
  the pinned Pueue completion extension. Pi built-ins/tools/auth/settings remain;
  prompts/themes and package resolution are unchanged. Repeat it on resume;
  existing history is not erased. Use fresh sessions for clean-reference tests.
- SIMA: one brief with common requirements/named jobs, independent copies/sessions,
  each assigned one job via `--context 'Execute only JOB.'`/`-c` (literal system
  text, not a file). No shared mutable state/synchronized execution or shell `&`.
  Unrelated contexts may use separate briefs. Dependencies need waves: copy
  accepted earlier results into later workspaces.
- Model/thinking: `--model provider/model`, `--thinking LEVEL` >
  `<parent-agent-dir>/subagents.json` (`model`, `thinkingLevel`) > parent's
  `PI_PROVIDER/PI_MODEL` and `PI_REASONING_LEVEL` > Pi defaults/saved session.
  Missing/null config values inherit; env model combines provider and model.

## Examples

From this configuration repository's root (adapt paths elsewhere), run each
whole block in **one Bash tool call**. Variables do not persist; retain the
printed directory and read its saved launch JSON in later calls.

### Single: launch-validation review

```bash
set -euo pipefail
r=$(mktemp -d /tmp/pi-one.XXXXXX)
mkdir "$r/base" "$r/work"
cp -a "$PWD/." "$r/base/"
cp -a "$r/base/." "$r/work/"
cat > "$r/task.md" <<'TASK'
Review home/pi-coding-agent/pineapplehunter/tools/subagents/launcher.py against
adjacent SUBAGENTS.md: check path/session validation. Do not edit or commit.
Trace findings; report file/line, impact, triggering input, checked cases, and
untested assumptions. Verify project files are unchanged.
TASK
printf 'Files: %s\n' "$r"
pi-subagent launch-review "$r/work" "$r/task.md" \
  --no-inherit-resources | tee "$r/launch.json"
```

### SIMA: independent sandbox and completion reviews

```bash
set -euo pipefail
r=$(mktemp -d /tmp/pi-sima.XXXXXX)
mkdir "$r/base" "$r/sandbox" "$r/completion"
cp -a "$PWD/." "$r/base/"
for job in sandbox completion; do
  cp -a "$r/base/." "$r/$job/"
done
cat > "$r/task.md" <<'TASK'
Review home/pi-coding-agent/pineapplehunter/ against tools/subagents/SUBAGENTS.md.
Execute only your job. Do not edit or commit. Trace findings; report file/line,
impact, triggering scenario, checked cases, and untested assumptions. Verify
project files are unchanged.
## Sandbox job
Review mounts/resource isolation in tools/subagents/launcher.py only.
## Completion job
Review early success, notifications, and report delivery in
tools/subagents/runner.py and extensions/pueue-tool/index.ts only.
TASK
printf 'Files: %s\n' "$r"
pi-subagent sandbox-review "$r/sandbox" "$r/task.md" \
  -c 'Execute only the Sandbox job.' | tee "$r/sandbox.json"
pi-subagent completion-review "$r/completion" "$r/task.md" \
  -c 'Execute only the Completion job.' | tee "$r/completion.json"
```

After either example completes, read its `response_path` first; skip logs for a
usable report. For failed tasks or missing/incomplete reports, start with
`pueue log --lines 3 TASK_ID`, increasing `--lines` if needed (or read `stdout_path`).

## Results, resume, cleanup

- Do independent work, then end your response; completion notifications resume
  you. **Do not wait/poll.** Intermediate replies are not outer completion:
  ALL private tasks must be terminal AND their notifications processed in a
  model run, or explicit failure/cancellation occurs. Inspect workers separately.
- Require a nonempty report and verify findings/diffs/tests: success proves
  neither delivery nor correctness. Compare read-only workspaces with
  `diff -qr --exclude=.git BASE WORKSPACE`
  (Git may refresh its index). Integrate selected changes, never entire workspace
  overwrites; run combined tests in the original project.
- From the **same original cwd**:
  `pi-subagent NAME NEW_WORKSPACE FOLLOW_UP_FILE --resume SESSION_ID`.
  **First verify the session is terminal/unlocked and native history exists.**
  Task ID/label cannot resume it. Repeat the original `--context` exactly unless
  reassignment was requested (no stored role). Explain changed inputs so files
  are reread. Archive results:
  turns replace prompt/report/stdout. Never alter active workspace/state or reuse
  queued/running/locked sessions.
- State survives parent Pi restart, not necessarily tmp cleanup. Before deletion,
  stop active tasks and verify terminal status with `pueue status`; then
  `rm -rf -- /tmp/pi-subagent-state/SESSION_ID` deletes history/logs/tmp, not Pueue
  task records. Clean workspace/baseline separately after integration/follow-ups.

## Child environment/report

Children inherit PATH/env/API keys/proxies/auth; extensions/skills load by default.
`--no-inherit-resources` changes loading, not mounts. `~/.pi` and custom agent
directories use temporary writable overlays: settings/OAuth changes vanish,
never reach the parent. Do not edit parent resources to repair children. Nix-store
targets are immutable: replace links with copies inside the child overlay to edit.
Trusted project, shared Nix store/daemon/network permit builds/`nix develop`;
**not a network/credential security boundary**. Desktop sockets/portals absent;
private Pueue/`/tmp`; parent sessions/transcript hidden, not copied. Conversations
persist at `/run/pi-subagent/sessions`.

Launcher supplies these mechanics separately: no nested subagents; after all
results, write `/run/pi-subagent/response.md` with project-relative changed paths,
test outcomes, and precise missing-input requests for parent follow-up. Parent
reads this report, not the ordinary final reply.
