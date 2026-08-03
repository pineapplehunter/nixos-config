# Modules

Reusable NixOS modules.
Directories are used for configurations that require multiple files.
`machines/` contains each host's system, hardware, storage, and service configuration.

## Adding a module

When adding a module:

- It must be added to `default.nix`.
- The module must be imported by `common.nix` or `minimal.nix`.

