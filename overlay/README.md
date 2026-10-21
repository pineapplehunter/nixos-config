# Overlays

This directory contains Nix overlays used by this repository.
They provide
- Local package customizations
- Workarounds for upstream issues
- Newer package variants
- Packages maintained directly in this configuration

## Adding an overlay

All overlays must be registered in `default.nix`.
Keep all package-specific information in comments in the overlay Nix file, including:

- Why it is needed
- The authoritative update source and relevant issue, pull request, or commit
- Local integration requirements and known limitations
- When the override can be removed

Keep this README and the update skill generic. Record the common batch-audit date
below rather than in each overlay file.

Most overlays should be included in the default overlay, while hardware-specific
overlays may be enabled only by the relevant machine configuration.

## Last checked

All overlays were last checked together on 2026-10-22.
