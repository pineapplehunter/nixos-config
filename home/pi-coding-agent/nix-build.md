---
name: nix-build-preferences
description: Use before running Nix builds with nix build or nix-build, including package checks, flake builds, and derivation debugging.
---

# Nix Build Preferences

Use this skill for tasks that require running `nix build` or `nix-build`.

## Building

Use `nix-build` when `default.nix` exists.

```shell
nix-build -A package-name
```

Use `nix build` when `flake.nix` exists.

```shell
nix build .#package-name
```

## Remote builders and cache

The remote builders and cache may fail at anytime.
You may fallback to using no remote builders (--builders "") and only using the nixos official substituter.
Since it is significantly faster to run builds on remote builders, retry building after some time has passed.

## Keep The Environment Clean

Always add `--no-link` unless the task explicitly needs a `result` symlink.

## Use pueue

Many nix operation take significan amount of time which causes the bash tool to timeout.
Use pueue and run the commands in the background.

```shell
pueue add -- <command> && pueue wait
pueue log <id>
````

## NixOS Tests

Set sensible timeouts in NixOS tests. Avoid unbounded waits such as `wait_until_succeeds` without a timeout when a service, network condition, or VM state may hang.

Prefer explicit bounded waits that match the expected startup time, and keep them as short as practical while avoiding flakes.

