---
name: pueue
description: Use pueue to run commands in the background and receive automatic completion turns.
---

# Pueue

Pi's wrapper starts an isolated `pueued` for the Pi session; Pueue commands
inside Pi do not control the host daemon. Assume the same Pi session throughout
queued work.

- `pueue add -- <cmd>`: enqueue a command. Retain the returned task ID.
- `pueue log <task_id>`: inspect task output after completion.
- `pueue status`: inspect task states when diagnosing a problem.
- `pueue clean`: remove finished tasks after processing their results.

See `pueue --help` for more subcommands.

## Automatic completion

Every task completion automatically starts a new agent turn when idle, or
queues a follow-up when busy. No subscription or yield tool is needed.

After enqueueing work, do any independent work. When there is nothing else to
do, end your response naturally. Do not call `pueue wait`, follow logs merely
to wait, or repeatedly poll status. A completion message will resume you;
inspect the task logs as needed and continue the original request.

A subagent stays alive until all its private Pueue tasks are terminal and their
completion notifications have been processed in a model run. Write the final
report only after processing results. Failures and cancellations are terminal
results too; they are not evidence of successful work.

Notifications require a living interactive/RPC Pi process. Ordinary `--print`
and JSON invocations are single-shot and do not support this idle-wakeup
workflow. Exiting Pi or destroying the sandbox also ends notification delivery.
A task that never finishes produces no completion; investigate with status or
cancel it rather than assuming an inactivity timeout still exists.

After an aborted/failed interactive run, automatic turns pause. A new user
prompt or `/pueue-notifications` resumes them; `/pueue-notifications off` pauses
notifications without stopping tasks.
