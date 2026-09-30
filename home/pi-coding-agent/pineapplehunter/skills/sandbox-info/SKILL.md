---
name: sandbox-info
description: Explain Pi's Bubblewrap sandbox detatched from the host system. Use when you want to know the sandbox capabilities.
compatibility: pi
---

# Pi sandbox

Pi is running in a isolated environment detatched from the host system using bubblewrap. An easy assumption to have is that only the project directory (current working directory) is mounted read writable and any other directory is tmpfs.
For more information about the filesystem, use `nix shell nixpkgs#util-linux -c findmnt`.
Any action taken in this sandbox will not affect the host system except for the project files.

## Nix tool usage

Nix tooling is installed and available. When in need of new tools, use `nix shell` or `nix_bash` tool.

## Temporary files

`/tmp` is backed by the host storage and it is persistant across pi restarts.
