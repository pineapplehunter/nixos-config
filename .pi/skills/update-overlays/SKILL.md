---
name: update-overlays
description: Audits and updates this repository's Nix overlays against its pinned inputs and upstream state. Use when asked to update, audit, refresh, or remove obsolete overlays, or when invoked as /skill:update-overlays.
---

# Update Overlays

Perform the overlay update; do not stop after describing or planning it.

1. Work from the repository root and read [`overlay/README.md`](../../../overlay/README.md) completely.
2. Follow its **Instructions for agents** as the authoritative update procedure. Audit every overlay in the batch unless the user explicitly supplied a narrower scope.
3. Inspect the repository's pinned inputs, overlay registration, package expressions, call sites, and linked upstream sources as required by that procedure. Preserve intentional local packages and custom behavior.
4. Make all justified changes, including deleting obsolete imports, composition entries, patches, and files. Do not make speculative version bumps or remove an overlay merely because it lacks an upstream issue.
5. If the audit results in an overlay-related repository change, set the common `Last checked` date in `overlay/README.md` to the date on which the audit was actually completed. If nothing changes, leave the date untouched. Update the common date only after completing the full batch; for a partial audit, state the scope instead of falsely dating the full batch.
6. Run the validation required by `overlay/README.md`, the repository's `AGENTS.md`, and any more specific instructions. At minimum, run `git diff --check`, search for stale references, and run `nix flake check --no-build --all-systems`. Build the smallest relevant derivation when evaluation cannot verify an override or patch.
7. Report overlays removed, changed, and retained; include the evidence or reason for each decision and any validation that could not be completed.
8. After the work and validation finish, use `notify` with a concise Markdown report focused only on packages actually updated or affected by an overlay change or removal. Make this the final tool call for the task:
   - List only changed packages and briefly describe what changed (include old and new versions when applicable). Do not list retained or unchanged packages, audit evidence, successful validation details, documentation-only edits, or unrelated working-tree issues; keep those in the final chat report.
   - If no packages changed, say only "No packages updated." and omit `color`. Documentation-only edits and audit-date updates do not count as package changes.
   - If packages changed and their update and validation completed without errors, use green (`#57F287`).
   - If a package update or its validation failed, use red (`#ED4245`) and briefly identify the affected package, failure, and required user action. Do not include unrelated errors.
