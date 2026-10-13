# Overlays

This directory contains Nix overlays used by this repository.
They provide
- Local package customizations
- Workarounds for upstream issues
- Newer package variants
- Packages maintained directly in this configuration

## Adding an overlay

All overlays must be registered in `default.nix`.
Add comments covering the following to the overlay file:

- Why it is needed
- The relevant upstream issue, pull request, or commit, when one exists
- When the override can be removed

Record the common batch-audit date below rather than in each overlay file.

Most should be included in the default overlay, while hardware-specific overlays may be enabled only by the relevant machine configuration.

## Last checked

All overlays were last checked together on 2026-10-14.

## Backports

- VTK 9.5 and 9.6's PEGTL configuration fix from
  [nixpkgs PR #572295](https://github.com/NixOS/nixpkgs/pull/572295) is backported
  until the pinned input includes it. This is a partial update, not a new
  full-batch audit.
- Mozc UT dictionary updates and the pinned-input merger from
  [nixpkgs PR #570751](https://github.com/NixOS/nixpkgs/pull/570751) are backported
  onto the local split Mozc package. The legacy merger attribute is not overridden;
  Fcitx configuration is unchanged. This is a partial update, not a new full-batch
  audit.
