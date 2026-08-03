# Home

Home Manager profiles and modules.
The name of the file represents the configuration it holds.
Directories are used for configurations that require multiple files.

## Adding a module

When adding a module:

- It must be added to `default.nix`.
- The module must be imported by `common.nix` or `minimal.nix`.

