---
name: todo
description: Manages generic Markdown task lists: creates and locates lists, validates metadata, reports prioritized status, reviews task relevance and baselines, completes tasks, and advances to the next task. Use for task-list creation, status, counts, priorities, validation, task selection, resolution, completion, or “next,” with either an in-tree or /tmp list.
---

# TODO Management

Use this skill for Markdown task lists describing software work, research,
writing, operations, or any other kind of task.

## Choose the task-list location

Choose one mode explicitly when starting a list, then keep using it for that
workspace:

- **In-tree** (default): `<workspace-root>/todo`. Use this when tasks should be
  versioned with the work.
- **Temporary**: `/tmp/pi-tasks/<workspace-name>-<path-hash>/todo`. Use this when
  the list should stay outside the work tree. Temporary lists are local and may
  be deleted by system cleanup; do not use this mode as the sole durable record.

The workspace root is the Git top level when available, otherwise the current
directory. Resolve or create the directory with the bundled helper:

```bash
TODO_SKILL="$HOME/.pi/agent/skills/todo"
TASK_DIR=$(python3 "$TODO_SKILL/scripts/task-dir.py" intree)
# Or:
TASK_DIR=$(python3 "$TODO_SKILL/scripts/task-dir.py" tmp)

python3 "$TODO_SKILL/scripts/task-dir.py" --create intree
python3 "$TODO_SKILL/scripts/task-dir.py" --create tmp
```

Pass `--root <path>` when the workspace differs from the current directory.
Never silently switch modes because one list is empty or missing. If the user has
not selected a mode and neither list exists, default to in-tree. If exactly one
exists, use it. If both exist, ask which one to use. Create a new list only when
requested or when adding its first task.

## Task format

Use this frontmatter schema:

```markdown
---
title: A short task title
created: 2026-09-15
status: pending
priority: P1
base: v6
tag: review
---
```

Required fields:

- `title`: a nonempty task title.
- `created`: an ISO date (`YYYY-MM-DD`).
- `status`: one of `pending`, `in-progress`, `blocked`, `deferred`, or
  `completed`.
- `priority`: one of `P0`, `P1`, `P2`, or `P3`, where P0 is highest.

Optional fields:

- `base`: the task-specific baseline. In a Git workspace this is normally a tag
  or commit. For non-Git work it may identify a dated snapshot, document
  version, ticket state, or other concrete baseline.
- `tag`: one provenance or grouping category.
- `finished`: the completion date in ISO format. It is required exactly when
  `status` is `completed` and must be absent otherwise.

Use `base` when a meaningful comparison baseline exists; do not invent one just
to populate metadata.

Use this body structure when creating or repairing a task:

```markdown
## Description

Task context, requirements, and relevant external feedback.

## Checklist

- [ ] A concrete completion check.

## Completion notes

Results recorded after completion.
```

Preserve existing meaning, quoted feedback, constraints, and completion evidence
when repairing metadata or structure. A task filename should be stable and
readable; an optional sequence prefix such as `R01-` may be used when the list
needs stable display IDs.

## List and validate tasks

Resolve the selected location and run:

```bash
python3 "$TODO_SKILL/scripts/todo-stats.py" "$TASK_DIR"
```

The command reads and validates each `*.md` file except `README.md`. It omits
completed tasks, sorts unfinished tasks by priority, creation date, and filename,
and prints the unfinished list and count. An absent or empty directory is a valid
list with zero unfinished tasks.

If validation fails, repair the task according to the format above. Preserve its
meaning and evidence; do not discard details merely to make validation pass.

## Work on a task

### 1. Select and read it

List unfinished tasks, select the first task in the reported order, and read its
complete Markdown file. Treat the filename stem as its ID when no ID is recorded
in the task itself.

### 2. Check current relevance

Inspect the current artifacts, state, and evidence named by the task, plus the
minimum directly related context. Do not assume a pending task remains relevant.
Classify it as:

- **Still relevant**: the requested outcome remains substantially unresolved.
- **Partially relevant**: later work resolved part, but not all, of the concern.
- **No longer relevant**: the current state already resolves or supersedes it.

Cite concrete evidence from the current state. If the task is no longer relevant,
recommend completing it with an explanation rather than doing unnecessary work.

### 3. Compare with its baseline

Treat `base` as the task-specific comparison baseline. For a Git revision, use:

```bash
git diff <base> -- <relevant-paths>
git show <base>:<relevant-path>
```

For a document version, snapshot, ticket state, or other baseline, use the
appropriate comparison. Explain what was already addressed, what remains, and
whether the current state supersedes an older proposed solution. Do not
substitute a global baseline or restore baseline content blindly. The optional
`tag` records provenance or grouping; it does not replace the baseline or
determine priority.

If `base` is absent, say that no explicit baseline was recorded and assess the
task against the current state and its description. Do not invent a baseline.

### 4. Show recorded feedback

Quote verbatim all external feedback, review comments, or user-provided wording
recorded in the task. Preserve the original language; translate only if asked.
If no associated feedback is recorded, state that explicitly.

### 5. Suggest a resolution

Propose the smallest change that satisfies the remaining task while preserving
later improvements. Include concrete edits or actions when useful. Distinguish
required corrections from optional refinements. Do not modify work artifacts
until the user approves the suggestion unless the user already explicitly asked
you to perform the work.

Use this presentation order:

1. **Task information**: ID, title, priority, status, optional base and tag,
   task-list mode, and relevant artifacts.
2. **Current relevance**: still, partially, or no longer relevant, with evidence.
3. **Changes since baseline**: concise comparison, or note that no baseline is
   recorded.
4. **Recorded feedback**: verbatim, or state that none is recorded.
5. **Suggested resolution**: minimal concrete action.

## Handle “next”

When the user says “next” or asks to move to the next task, close out the current
task before presenting another one.

1. Recheck the current artifacts, task checklist, and relevant validation.
2. If the task is complete or superseded:
   - Set `status` to `completed`.
   - Add the current date as `finished`.
   - Reconcile its checklist and add completion notes with evidence or the
     superseding decision.
   - Run validation appropriate to the changed artifacts and `git diff --check`
     when working in a Git tree.
   - If the workspace uses version control, commit only the current tracked
     changes that belong to the completed task. Do not create an empty commit;
     report when no commit was needed. Never try to commit a task file stored in
     `/tmp` as though it were part of the work tree.
   - Re-run the list command for the selected location and present the next
     unfinished task using this workflow.
3. If the task is not complete:
   - Do not mark it completed, commit unrelated work, or advance.
   - Report the unresolved checklist items or validation failures.

Do not interpret “next” as merely displaying another task while silently leaving
a resolvable current task pending.

## Validate helper changes

```bash
python3 -m py_compile \
  "$TODO_SKILL/scripts/task-dir.py" \
  "$TODO_SKILL/scripts/todo-stats.py"
python3 "$TODO_SKILL/scripts/todo-stats.py" "$TASK_DIR"
```
