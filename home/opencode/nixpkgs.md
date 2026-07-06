---
name: nixpkgs-fix
description: Use ONLY in a nixpkgs checkout when fixing a failing package build, test, checkPhase, or package expression.
compatibility: opencode
---

# Nixpkgs Package Fix

Use this skill when the current repository is `nixpkgs` and the user wants a package build or test failure fixed.

## Inputs

Identify the package attribute first. If the user did not provide one, ask for it before making edits.

Capture the failing command and platform when available. If the user pasted a log, use it to narrow the failing phase before rebuilding.

## Build The Package

Build with `nix-build` from the nixpkgs root:

```console
nix-build -A package-name 2>&1 | tee /tmp/build.log
```

Always pipe build output to a log file. Some builds stall or produce too much output for the tool response; the log lets you inspect failures afterward.

If a package has a targeted passthru test or check, run the smallest relevant build after the first failure is understood.

## Edit Scope

Start with the package expression and nearby patches. Touch only files related to the failing package unless the failure clearly comes from a shared helper, dependency, or test infrastructure.

Avoid broad rebuilds and dependency bumps unless they are necessary for the fix.

## Fix Strategy

Inspect the failing phase and prefer the smallest correct fix:

- Patch source or test expectations when upstream behavior changed.
- Add missing native build inputs for tools used at build time.
- Add build inputs only when linked libraries or runtime discovery require them.
- Disable or narrow tests only when they are flaky, require network access, require unavailable hardware, or are invalid in the Nix sandbox.
- Preserve maintainers, metadata, and existing style.

## Verification

After editing, rebuild the package and capture the log again:

```console
nix-build -A package-name 2>&1 | tee /tmp/build.log
```

Report the exact build command used, whether it passed, and any remaining failures. If the environment lacks a required tool or permission, explain the blocker and the next command the user should run.

## Missing Tools

If a tool is not on `PATH`, first check whether it is available through the nixpkgs checkout or `nix shell`. Ask the user only when the tool cannot reasonably be obtained through Nix or when network access is required.
