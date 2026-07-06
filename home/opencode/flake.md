---
name: flake-bash
description: Use when running commands that need tools from a Nix flake devShell or when adding packages to devShells.
compatibility: opencode
---

# Nix Flake Bash

Use this skill when a command needs tools that are provided by a project's `flake.nix`, especially packages listed under `devShells`.

## Detect The Flake

Check for `flake.nix` at the project root or in an ancestor directory. The `devShells` outputs define development environments and the command-line tools available inside them.

## Run Commands In The Dev Shell

Prefer running commands through `nix develop` instead of asking the user to install tools globally:

```shell
nix develop -c command arg1 arg2
```

For commands that need shell features such as pipes, redirects, variable expansion, or `&&`, run an explicit shell inside the dev environment:

```shell
nix develop -c bash -lc 'command arg1 | tee /tmp/output.log'
```

Use the repository root as the working directory unless the task requires a specific subdirectory.

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
nix develop -c command --version
```

Avoid expensive checks unless the user requested them or the change is risky.
