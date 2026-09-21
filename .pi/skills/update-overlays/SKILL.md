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
8. After the work and validation finish, use `notify` with a concise Markdown report. Make this the final tool call for the task:
   - If no overlay-related repository change was needed, say that the audit found no changes and omit `color`.
   - If at least one overlay-related change was made and the task completed without errors, use green (`#57F287`) and summarize the changes and validation.
   - If any update, audit, or validation error occurred, or the task could not be completed, use red (`#ED4245`) and report the error, completed work, and any required user action.
