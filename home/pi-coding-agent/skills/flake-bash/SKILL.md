---
name: flake-bash
description: Use when running commands that need tools from a Nix flake devShell or when adding packages to devShells.
compatibility: pi
---

# Nix Flake Bash

Use this skill when a command needs tools that are provided by a project's `flake.nix`, especially packages listed under `devShells`.

## Detect The Flake

Check for `flake.nix` at the project root or in an ancestor directory. The `devShells` outputs define development environments and the command-line tools available inside them.

## Find Missing Packages

Use the `nix-search` tool to find package attribute names before editing a flake. Prefer package attributes that already exist in nixpkgs over ad-hoc downloads.

## Add Packages To A Dev Shell

When a needed tool is missing and the task requires a persistent project change, add it to the relevant `devShells` package list:

```nix
devShells.default = pkgs.mkShell {
  packages = [
    pkgs.package-name
  ];
};
```

Keep the edit minimal and match the existing flake style. If multiple dev shells exist, update only the shell used by the project or task.

## Verification

After changing a flake, run the smallest useful check, such as:

```shell
nix flake check
command --version
```

Avoid expensive checks unless the user requested them or the change is risky.
