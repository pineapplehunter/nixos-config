---
name: sandbox-info
description: Use when reasoning about sandbox limits, persistent storage, temporary files, Nix tools, or git permission failures.
compatibility: opencode
---

# Sandbox

You are running in a sandbox. Some filesystem, network, and process operations may be restricted, and some paths are temporary.

# Tools

Nix tools and store paths are available under `/nix/store`. Prefer using Nix-provided tools instead of downloading arbitrary binaries.

# Persistent Storage

Use `/persistant` for files that must survive after the current process exits.

`/tmp` is a separate tmpfs from the host system. It may be cleared at any point and should only hold disposable logs, caches, and intermediate files.

`/persistant` is mounted so changes persist after the process exits. The underlying host directory is different for each project directory, so files there are isolated per project. Clean up files you no longer need.

Note the path is spelled `/persistant` in this environment.

# Git Operations

Some sessions do not have permission to create commits. If `git commit` fails because of sandbox permissions, leave the working tree intact and provide the commit message for the user to run.

Never use destructive git commands to work around sandbox limitations.
