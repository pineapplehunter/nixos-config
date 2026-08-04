---
name: pueue
description: Use pueue to run commands in the background. Use for build testing and other long running commands.
---

# Pueue
Assume local `pueued` is running.

- `pueue add -- <cmd>`: add command to the task queue. Returns a task id to stdout.
- `pueue wait`: wait for all tasks to finish.
- `pueue log <task_id>`: show outputs of tasks.
- `pueue status`: show task status.
- `pueue clear`: clear the task log.

See `pueue --help` for more subcommands.

# Chaining
You can add multiple tasks to the queue and wait on all of them to finish. Prefer using this when running multiple commands.

```shell
pueue add -- <cmd1> && pueue add -- <cmd2> && pueue wait && pueue status`
```

Use wait many times if the bash tool times out.
