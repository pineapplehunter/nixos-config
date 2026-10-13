# Repository

Personal Nix flake for NixOS systems, Home Manager profiles, custom packages, and development templates.

## Structure

- `home/`: Home Manager modules and profiles.
- `machines/`: NixOS flake configuration entry points.
- `modules/`: Shared and host-specific NixOS modules.
- `overlay/`: Package overlays, local packages, and patches.
- `secrets/`: SOPS-encrypted configuration data.
- `templates/`: Reusable Nix flake templates.
- `.github/`: CI workflows.

See README.md in each subdirectory for more information.

# Evaluation test

Before evaluating the flake, add any new source files referenced by Nix to the Git index.
The full all-systems check below takes time so it is recommended to run before git commits.

```shell
nix flake check --no-build --all-systems
```
