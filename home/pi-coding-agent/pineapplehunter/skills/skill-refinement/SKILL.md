---
name: skill-refinement
description: "Empirically improve and shorten existing Agent Skills using fresh-subagent tests, fixed rubrics, verified reference reads, and controlled comparisons. Use when asked to refine, simplify, minimize, benchmark, or test a skill without reducing its effectiveness."
---

# Skill Refinement

Improve clarity first, then minimize against measured behavior—not line count
alone. Follow `skill-creator` for format/discovery and `subagents` for delegation.
Edit the declarative source, not an installed/generated copy. Never delegate
from a child; test workers answer hypothetical parent scenarios without nesting.

## 1. Establish the contract

- Read the complete target and its referenced resources. Confirm commands and
  behavior against current implementation/authoritative docs; the skill itself
  is not ground truth. Preserve user-specific constraints and unrelated edits.
- Record intended triggers, non-triggers, required outputs, critical safeguards,
  and current failures. Separate discovery, comprehension, and execution issues.
- Make isolated version snapshots and a small experiment directory, normally
  under `/tmp`. Retain quizzes, rubrics, input copies/hashes, launch JSON, reports,
  and a results table. Never modify a running worker's inputs.
- Choose a bounded budget: normally a baseline, one or two shortening rounds,
  and a final holdout. Fix model/thinking with explicit launcher flags.

## 2. Build and verify an effective baseline

Clarify ambiguous rules; add complete, bounded examples with preparation,
invocation, output inspection, and verification. Avoid duplicating harness
instructions. Check YAML and example syntax **before** launching tests; quote
frontmatter values containing `: `. Prefer only name/description unless more
metadata is needed. Snapshot this effective full version separately from the
original. Minimize only after it demonstrably works; don't preserve known bugs
just to match the original.

## 3. Define tests before reading answers

Write one fixed quiz and a parent-only rubric. Cover ordinary use, tempting
wrong recipes, missing inputs/failure, state or follow-up handling, and safety
boundaries. Ask explicitly for each scored detail; don't penalize an answer for
omitting something an open-ended question never requested.

For a CLI skill, request a complete invocation and repairs of invalid commands.
For a coding skill, request a small implementation/review and checks of forbidden
patterns. Include positive/negative trigger requests separately. Understanding
quizzes and real fixture/execution tests are different evidence; run relevant
mechanical checks too, without unsafe effects or nested delegation.

Use observable binary checks with required evidence and explicit critical gates.
Equivalent correct wording/commands count; contradictions fail. Keep the rubric
out of worker inputs. If a question is ambiguous or requirements change, revise
it and rerun **both** control and candidate; don't move scoring goalposts later.

## 4. Run controlled, reference-verified trials

Normally use two fresh conversations per version; keep quiz, model, thinking,
tools, resource-loading mode, context, and scoring identical. Resumes are useful
for debugging, not independent trials. Use neutral reference filenames, not
quality labels.

Prepare one workspace per worker with `REFERENCE.md` and any required resources
in their documented relative layout. The reference path in the child is the
**original project cwd** plus `/REFERENCE.md`, not the parent's backing `/tmp`
path. Copy every input the child needs into its workspace or prompt.

Prefer `--no-inherit-resources` for closed-reference trials. After preparing the
workspace and quiz, launch from the original project root, for example:

```bash
pi-subagent trial /tmp/trial-workspace /tmp/quiz.md \
  --no-inherit-resources \
  --context "Evaluate only $PWD/REFERENCE.md; do not load installed skills."
```

This disables automatic extensions/skills, retaining the pinned Pueue completion
extension and built-in tool selection. Authentication, environment, settings,
project instructions, prompts, and themes remain; packages are still resolved
and resource files remain readable. It is not a filesystem/credential security
boundary, so keep explicit reference restrictions and read audits. Custom
extension tools/providers are unavailable: if required, use normal inheritance
for **both** control and candidate and record that limitation.

Check that the **installed** `pi-subagent --help` exposes the flag; source changes
require launcher activation before use. If unavailable, use an updated launcher
or document a consistent inheritance-mode fallback—never silently mix modes.
Start fresh sessions: the flag does not erase old conversation history. Repeat
it on manual resume; resource-loading mode is not stored separately.

Use this task template, replacing placeholders with literal paths and cases:

```text
This is a document-understanding evaluation, not execution of the workflow.
First read ONLY <CHILD_PROJECT_ROOT>/REFERENCE.md completely. That workspace
file is the reference under test, NOT an installed skill of the same name.
Do not select/load installed skills or other documents; additional allowed
resources: <explicit list, or none>. Begin the report with the reference path.
Answer as a hypothetical top-level agent. Do not launch agents, enqueue work,
wait, install anything, or mutate inputs. Give feasible commands, decisions,
and reasoning for EVERY numbered scenario below:
<fixed scenarios, without the scoring rubric or expected answers>
Write the required report with numbered answers, changed files, and test
outcomes. State what was actually executed; do not claim planning as execution.
```

Also pass the reference restriction as literal `--context` system guidance, the
same for every version: this is an evaluation of the explicit workspace file,
not a request to load the advertised installed skill. Save every launch JSON.

On completion, read `response_path` first. A usable report normally needs no
`pueue log`; for failure or missing/incomplete output, start with
`pueue log --lines 3 TASK_ID`, expanding only if needed. Do independent work and
end your response when only workers remain; don't wait/poll.

**Audit actual reads before scoring.** Inspect tool-call records in returned
`stdout_path` (Pi RPC: `tool_execution_start`, `toolName: read`, `args.path`).
Normalize relative paths against the child's project cwd; confirm the intended
reference was read fully, inputs match the snapshot, and no installed target or
unapproved material was used. A report's claimed reference or task Success is
not proof. Exclude contaminated trials and rerun with explicit paths/context;
never count them as evidence about the candidate.

## 5. Shorten in controlled rounds

Remove repetition, history/analogies, obvious explanations, and harness-supplied
mechanics first. Consolidate rules and examples without code-golfing. Retain
critical ordering, exact APIs/path semantics, meaningful verification, and
complete examples. Improve terse wording when a test exposes ambiguity.

Record each version's lines/words (tokens if a tokenizer is available), per-worker
scores, failed checks, and qualitative defects. Count required supporting files
as well: moving prose elsewhere is progressive disclosure, not necessarily a
reduction in total needed context. Score valid trials against the unchanged
rubric, then compare with the full control and observed repeat variation.

Reject critical regressions; investigate noncritical differences rather than
chasing one perfect answer. Retest specific corrections, and use a fresh holdout
with different filenames/roles/failure conditions to check transfer. Don't train
to disclosed expected answers. Stop when further deletion harms requirements or
readability, or the agreed budget is exhausted. Keep the shortest **validated**
version, not the shortest draft or a claimed global minimum.

## 6. Validate, integrate, report

- Recheck frontmatter with the `skill-creator` validator, referenced files, example
  syntax/preparation, and relevant fixture checks. Test actual skill discovery in
  fresh Pi; verify the loaded source path and absence of warnings/name collisions.
- Apply accepted content only to the target source. Run repository checks; stage
  new Nix-referenced files before flake evaluation, without unrelated files.
- Report size reductions with the comparison baseline named, valid scores,
  regressions/fixes, excluded trials, remaining uncertainty, and artifact paths.
  Small tests on one model are not universal reliability guarantees; launcher
  instructions, retained ambient resources, and pretrained knowledge remain
  shared confounders even with `--no-inherit-resources`.
- Notify/commit only when requested, in the requested order. Retain evidence
  until review is complete; confirm workers terminal before cleanup. Explain
  that declarative installed copies require activation/reload to pick up changes.
