---
name: fix-evaluation-errors
description: Diagnoses and fixes Nix flake evaluation errors in this configuration. Use when asked to check or repair evaluation, fix a failing flake check, or invoked as /skill:fix-evaluation-errors.
---

# Fix Evaluation Errors

Perform the evaluation check and any justified repairs; do not stop after describing or planning them.

1. Work from the repository root. Read the repository's `AGENTS.md` and any instructions specific to the files involved. Preserve unrelated work in the tree.
2. Run `nix flake check --no-build --all-systems` before making changes and capture the relevant diagnostics.
3. If the check succeeds, do not make speculative changes. Report that no evaluation errors were found and continue to the notification step.
4. If the check fails, inspect the pinned inputs, affected Nix expressions, module definitions, option declarations, package call sites, and complete error traces needed to identify the root cause. Make the smallest coherent fix while preserving intentional behavior.
5. Re-run `nix flake check --no-build --all-systems` after changes. Also run `git diff --check`, inspect the final diff, and run any narrower evaluation command needed to verify the affected configuration. Do not claim success unless the all-systems check passes.
6. If an error cannot be fixed safely, depends on unavailable credentials or infrastructure, or requires a user decision, stop without speculative changes and clearly identify the blocker and required action.
7. After the check or repair attempt ends, use `notify` with a concise Markdown report. Make this the final tool call for the task:
   - If the initial all-systems check found no errors, omit `color` and say that no evaluation errors were found.
   - If evaluation errors were found and fixed, use green (`#57F287`) and summarize the cause, fix, and successful validation.
   - If evaluation errors remain, could not be fixed, or require user action, use red (`#ED4245`) and summarize the failure, work attempted, and required action.
8. Give the user the same outcome in the final response, including changed files and any validation that could not be completed.
