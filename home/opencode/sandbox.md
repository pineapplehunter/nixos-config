---
name: sandbox-info
description: Use when reasoning about sandbox limits, /tmp persistence, temporary files, repository clones, Nix tools, or git permission failures.
compatibility: opencode
---

# Sandbox

You are running in a sandbox. Some filesystem, network, and process operations may be restricted, and some paths are temporary.

# Tools

Nix tools and store paths are available under `/nix/store`. Prefer using Nix-provided tools instead of downloading arbitrary binaries.

# Temporary Storage

Use `/tmp` for temporary files, public repository clones, scratch work, and logs.

In this sandbox, `/tmp` is backed by a persistent per-project host directory, so files there survive opencode restarts and can be reused across sessions for the same project.

The underlying persistent directory is different for each project directory, so `/tmp` contents are isolated per project. Clean up files you no longer need.

# Git Operations

Some sessions do not have permission to create commits. If `git commit` fails because of sandbox permissions, leave the working tree intact and provide the commit message for the user to run.

Never use destructive git commands to work around sandbox limitations.
