---
name: commit-conventions
description: Applies this repository's established Git commit style when drafting, reviewing, or creating commits. Use when asked to commit changes, propose a commit message, split work into commits, amend a message, or check whether a commit follows repository conventions.
---

# Commit Conventions

Follow the style established by this repository's history rather than Conventional Commits.

## Before Writing a Message

1. Inspect `git status --short`, the staged diff, and the unstaged diff. Preserve unrelated work.
2. Inspect recent messages for the affected paths with `git log --oneline -- <paths>`. Use the repository-wide rules below unless a clearly established path-specific pattern is more precise.
3. Keep each commit focused on one coherent change. If the work contains independent changes, propose or create separate commits.
4. When creating a commit, stage only the intended files or hunks. Never include unrelated pre-existing changes.

## Subject

Use this form:

```text
scope: imperative summary
```

- Choose a short subsystem or configuration-area scope; do not use Conventional Commit types such as `feat`, `fix`, or `chore`.
- Use the vocabulary already present in history. Common scopes include `flake`, `pi`, `skills`, `todo`, `home`, `home/<component>`, `modules`, `modules/<component>`, `overlay`, `overlays`, machine names such as `action`, `beast`, `kpro-takata`, and `rpi5`, and uppercase `CI`.
- Prefer the narrowest scope that accurately describes the whole commit. Use a broader established scope when several related components change together.
- Start the summary with a lowercase imperative verb: `add`, `remove`, `update`, `fix`, `use`, `enable`, `disable`, `set`, `refactor`, or similar.
- Describe the outcome, not the editing process.
- Keep the subject concise: target 50 characters and do not exceed 72 characters.
- Do not end the subject with a period.

Examples matching history:

```text
flake: update inputs
pi: add notification sender metadata
overlays: remove obsolete package overrides
modules/common: fix ibus ime handling on wayland
beast: disable APST
CI: increase timeout
```

For a true revert, retain Git's standard form:

```text
Revert "original subject"
```

## Body

Include a body by default for nontrivial changes. A subject alone is fine only when the change is trivial and its purpose is already clear from the subject.

- Separate it from the subject with a blank line.
- Summarize what changed and explain why it was made, including the problem or motivation. Do not merely restate the subject or enumerate the diff.
- Include relevant consequences, tradeoffs, or removal conditions when they help future readers understand the change.
- Use complete sentences and short paragraphs, wrapping prose near 72 characters.
- Do not add issue references, sign-offs, co-author trailers, or AI attribution unless the user explicitly requests them or the change actually requires them.

## Passing the Message to Git

Prefer `git commit -F -` with a quoted heredoc instead of multiple `-m` arguments or a temporary message file. Quoting the delimiter prevents shell expansion and preserves multiline formatting.

```bash
git commit -F - <<'EOF'
scope: imperative summary

Summarize what changed and why it was needed.
EOF
```

When explicitly asked to amend, use the same method with `--amend`. Add `--only` for a message-only amendment to avoid including staged changes; omit it when intentionally including reviewed, staged changes.

## Creating or Reviewing a Commit

- If the user asks only for a message, output the proposed message without mutating the repository.
- If the user asks to commit, review the exact staged diff, run `git diff --cached --check`, and commit with the approved or clearly implied message.
- Do not amend, rebase, force-push, or otherwise rewrite existing history unless explicitly requested.
- After committing, report the commit hash and subject. If committing is blocked, report the blocker without weakening these conventions.
