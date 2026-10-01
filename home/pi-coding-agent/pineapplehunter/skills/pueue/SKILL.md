---
name: pueue
description: Run background commands in Pi's private Pueue queue, inspect results, manage concurrency, and diagnose automatic completion turns.
---

# Pueue

Pi's wrapper starts an isolated `pueued`, not the host daemon. Keep the same
living interactive/RPC Pi session: ordinary `--print`/JSON cannot wake after
exit; exiting Pi or destroying the sandbox ends delivery.

## Enqueue → process

Pueue executes shell commands. Quote the whole command to keep operators in the
queued shell and quote spaced arguments inside it. From the project root, with
script/inputs prepared:

```bash
pueue add --print-task-id -- 'python3 "scripts/check files.py" && printf "check complete\n"'
```

Retain the returned ID. After its completion, substitute it for `TASK_ID`:

```bash
pueue log --lines 3 TASK_ID
```

Expand `--lines` or use `--full` only as needed; read a usable subagent report
first instead of redundant logs. Verify the terminal result and required outputs
before claiming success; failure/cancellation is terminal, not success. Continue
the original request.

Every completion starts a turn when idle or queues a follow-up when busy; no
subscription/yield tool. Do independent work, then end your response naturally
**without exiting Pi**. Never `pueue wait`, follow logs merely to wait, or poll.
A subagent writes its final report only after **all** private tasks are terminal
and completion notifications processed in a model run; newly enqueued work
repeats this cycle. Intermediate replies do not finish the worker.

## Manage and diagnose

- `pueue parallel 4`: multiple small independent tasks, default group. Restore
  `pueue parallel 1` before enqueueing larger tasks; lowering does not stop
  already-running jobs.
- `pueue status`/`--json`: diagnosis, not waiting. Nonfinishing tasks produce no
  completion and have no inactivity timeout; diagnose and repair/cancel them.
- `pueue clean` removes **all finished tasks and logs**: first process every
  needed finished result and retain evidence. Use `pueue --help` for other commands.
