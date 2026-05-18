---
name: flake-bash
description: Run bash tool with nix packages.
compatibility: opencode
---

## About the environment
You should spot a flake.nix in the root of the project.
This file holds information about many things, but one thing in perticular is `devShells`. This defines the tools availible in the environement.

## How to run bash commands with the packages in devShell
prefix the command like the following.

```shell
$ nix develop -c command
```

The will spawn a new shell with the tools specified in devShell section.

## How to find packages.
Use nix-search tool.

## How to add a package to devShell

Add it to the list of packages.

```nix
devShells.default = mkShell { packages = [ the list of packages ]; };
  
```

