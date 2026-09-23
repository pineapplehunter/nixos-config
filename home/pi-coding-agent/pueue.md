---
name: pueue
description: Use pueue to run commands in the background. Use for build testing and other long running commands.
---

# Pueue
Assume local `pueued` is running.

- `pueue add -- <cmd>`: add command to the task queue. Returns a task id to stdout.
- `pueue-wait` tool: wait for an already-running task. Its timeout measures output inactivity and stops only the local follow client.
- `pueue log <task_id>`: show outputs of tasks.
- `pueue status`: show task status.
- `pueue clear`: clear the task log.

See `pueue --help` for more subcommands.

## Waiting

Use the `pueue-wait` tool instead of `pueue wait`, which may remain silent indefinitely. Pass `task_id` when multiple tasks are running. A queued or otherwise non-running task cannot be selected.
