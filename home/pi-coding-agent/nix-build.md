---
name: nix-build-preferences
description: Use before running Nix builds with nix build or nix-build, including package checks, flake builds, and derivation debugging.
compatibility: pi
---

# Nix Build Preferences

Use this skill for tasks that require running `nix build` or `nix-build`.

## Reduce Output

Suppress build output by default to reduce token usage.

For `nix-build`, use both quiet flags:

```shell
nix-build -Q -q --no-link --print-out-paths -A package-name
```

For `nix build`, use `--quiet`:

```shell
nix build --quiet --no-link --print-out-paths .#package-name
```

Add quiet options for all nix related subcommands such as `nix flake check` too.

## Keep The Environment Clean

Always add `--no-link` unless the task explicitly needs a `result` symlink.

Always add `--print-out-paths` so successful builds print the output path for easier debugging and follow-up inspection.

## Debug Build Output

If a quiet build fails and you need the build output for debugging, prefer `nix log` over rerunning with noisy output:

```shell
nix log /nix/store/...drv
```

Use the failing derivation path printed by Nix. Rerun the smallest relevant build with more output only when `nix log` is unavailable or insufficient.

## NixOS Tests

Set sensible timeouts in NixOS tests. Avoid unbounded waits such as `wait_until_succeeds` without a timeout when a service, network condition, or VM state may hang.

Prefer explicit bounded waits that match the expected startup time, and keep them as short as practical while avoiding flakes.
