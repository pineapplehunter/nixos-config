---
name: sandbox-info
description: Information about the sandbox environemnt you are runing in
compatibility: opencode
---

# Sandbox
You are running in a sandbox.
Many operations in the sandbox are not permitted or persistant.

# Tools
You have access to the nix tools in `/nix/store`.
Feel free to use and download binaries from nix.

# Persistant storage
**Use `/persistant` for files that need to be stored persistantly.**
/tmp is mounted as a separate tmpfs from the original system.
It may be cleared at any point during the operation.
`/persistant` is nounted so the changes persist after the process exits.
The underlying persistent directory in the host is different for each project directory, so feel free to clean files that are not needed.
These are all isolated.

# Git operations
In some case you do not have permissions to commit.
In that case, write the commit message and let the user commit it.

