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
- When its relevance was last checked

Most should be included in the default overlay, while hardware-specific overlays may be enabled only by the relevant machine configuration.

## Instructions for agents

When checking whether an overlay is still relevant:

1. Read its comments and determine whether it is a workaround, an intentional
   local customization, or package infrastructure.
2. Check the repository's pinned inputs rather than assuming the latest
   upstream or nixpkgs state is in use.
3. Inspect linked upstream issues, pull requests, and commits. Confirm whether a
   fix has been merged and is included in the pinned package version.
4. Compare the overlay with the current pinned package expression and source.
   Verify that substitutions and patches still target existing code and that an
   override is not duplicating an input-provided override.
5. Search this repository for references to attributes introduced by the
   overlay. An unused attribute may be removable, but exported overlays and
   intentionally available custom packages should also be considered.
6. For local behavior changes without upstream tracking, do not remove them
   solely because no issue exists. Follow their documented removal condition
   and ask the user if the intent is unclear.
7. After changing an overlay, evaluate every affected NixOS or Home Manager
   configuration. Build the smallest relevant derivation when evaluation alone
   cannot prove that a patch applies or that the package works.
8. Update the overlay's removal guidance and `Last checked` date after completing
   the audit.

Prefer removing obsolete overrides completely, including their imports,
composition entries, patches, and now-unused files. Before finishing, run
`git diff --check` and confirm that no stale references remain.
