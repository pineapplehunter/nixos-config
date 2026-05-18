---
name: nixpkgs-fix
description: Fix nix packages in nixpkgs.
compatibility: opencode
---

## About the environemnt
You are in the nixpkgs repository.
I want you to fix a package that is failing to build.

## What I do
You try to fix the failing package in nixpkgs.
The failing package will be provided as input.
Please ask for the package if it was not provided in the input.

## How to build a package
Packages in nixpkgs can be build as follows.

```console
$ nix-build -A *package-name* 2>&1 | tee /tmp/build.log
```

Some packages stall during the build which results in a no output in bash tool.
ALWAYS pipe all output to a file to be able to inspect the results later.

## Which files I should touch
You should only touch the files related to the failing package.
You may touch other files as needed, but be aware that doing that may result in very long rebuilds.

## I need a tool that is not in PATH
You can ask me for new tools. Let me know.

--

The failing package, if provided,  is the following.
