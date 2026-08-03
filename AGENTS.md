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

When modifying the source, be sure to check that it evaluates correctly.

```shell
nix flake check --no-build
```
