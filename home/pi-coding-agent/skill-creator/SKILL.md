---
name: skill-creator
description: Creates, updates, audits, and validates Agent Skills for Pi. Use when the user wants to create a skill, improve an existing SKILL.md, add reusable agent instructions or helpers, troubleshoot skill discovery or triggering, or learn skill-authoring best practices.
---

# Skill Creator

Create portable Agent Skills that follow the Agent Skills specification and work
with Pi. Prefer standard skill fields and structures over vendor-specific
extensions.

## Start with authoritative documentation

Before creating or changing a skill:

1. Read Pi's `docs/skills.md` completely from the Pi documentation path supplied
   in the system context.
2. Follow relevant links from that document when the task involves other Pi
   behavior.
3. Consult the [Agent Skills specification](https://agentskills.io/specification)
   when portability or an edge case matters.

Do not copy assumptions from Claude Code, Codex, or another harness into a Pi
skill without verifying that Pi supports them.

## Choose the right mechanism

Use a skill for specialized instructions, workflows, references, scripts, or
assets that should load only when relevant. Use `AGENTS.md` for concise
instructions that should always apply. Use ordinary project configuration for
mechanical rules better enforced by tools such as formatters or linters.

## Creation workflow

### 1. Capture intent

Establish:

- What capability or workflow the skill provides.
- Concrete examples of requests that should trigger it.
- Requests that should not trigger it.
- Expected outputs and completion criteria.
- Repeated operations that deserve scripts, references, or assets.
- Whether the skill belongs globally or only in the current project.

Ask only the questions needed to resolve meaningful ambiguity. When the request
already provides enough detail, proceed without an interview.

### 2. Select a location

Use Pi's documented skill locations:

- Global Pi skill: `~/.pi/agent/skills/<name>/SKILL.md`
- Project Pi skill: `.pi/skills/<name>/SKILL.md`
- Cross-harness project skill: `.agents/skills/<name>/SKILL.md`

When managing Pi through a declarative configuration, add the source skill to
that configuration rather than editing the generated home path directly.
Inspect nearby skills and configuration patterns before choosing a destination.

### 3. Plan progressive disclosure

Use this structure only as needed:

```text
<skill-name>/
├── SKILL.md
├── scripts/
├── references/
└── assets/
```

- Keep the core procedure and resource-selection guidance in `SKILL.md`.
- Put detailed or conditional documentation in `references/`.
- Put deterministic or repeatedly rewritten operations in `scripts/`.
- Put templates and output resources in `assets/`.
- Link every supporting resource directly from `SKILL.md` and state when to use
  it. Avoid chains of references that require the agent to discover links
  recursively.
- Do not add empty directories, placeholder resources, changelogs, or redundant
  README files.

### 4. Scaffold the skill

For a new skill, run the bundled initializer from this skill directory:

```bash
python3 scripts/init-skill.py <name> --path <parent-directory>
```

Create optional resource directories only when they are useful:

```bash
python3 scripts/init-skill.py <name> --path <parent-directory> \
  --resources scripts,references,assets
```

If Python is unavailable in the current environment, create the same structure
with the available file tools instead of installing a runtime solely to run the
initializer.

Never overwrite an existing skill silently. Read it first and preserve its
useful behavior unless the user asks for a replacement.

### 5. Write effective frontmatter

At minimum, write:

```yaml
---
name: example-skill
description: Explains what the skill does and the requests or contexts in which it should be used.
---
```

Follow these rules:

- Use a short lowercase hyphenated name, no longer than 64 characters.
- Match the directory name for portability.
- Keep the description no longer than 1024 characters.
- Describe both **what** the skill does and **when** it should load.
- Include useful domain terms, filenames, extensions, and request phrasings.
- Keep trigger guidance in the description because Pi sees it before loading the
  body.
- Use optional frontmatter fields only when Pi's documentation confirms their
  behavior. Avoid vendor-specific fields unless targeting that vendor too.

### 6. Write the instructions

Write direct, actionable instructions for another agent instance:

- Assume the agent already has broad reasoning and coding knowledge.
- Include non-obvious constraints, decision points, required ordering, and
  common failure modes.
- Match precision to risk: use flexible guidance when many approaches work and
  exact commands or scripts when mistakes are costly.
- Use examples where they clarify behavior better than prose.
- State how to resolve relative resource paths.
- Keep the main file concise; split details when they would obscure the core
  workflow.
- Do not mention tools or capabilities unavailable in Pi unless the skill checks
  for them and provides a fallback.

Test every bundled script that is created or changed.

### 7. Validate and test

Run the bundled structural check:

```bash
python3 scripts/validate-skill.py <path-to-skill-directory>
```

Also:

1. Check all referenced files exist and all scripts parse or execute correctly.
2. Review the description against positive and negative trigger examples.
3. Test realistic requests in a fresh Pi session because skills are discovered
   at startup.
4. Confirm the skill appears without discovery warnings.
5. Iterate from observed failures instead of adding speculative instructions.
6. Run repository-specific checks when the skill is maintained in a repository.

## Updating or auditing a skill

1. Read the complete `SKILL.md` and directly referenced resources.
2. Identify the actual issue: discovery, triggering, procedure, missing context,
   unsupported tools, broken resources, or excessive context size.
3. Make the smallest coherent correction.
4. Preserve user-specific constraints and working resources.
5. Validate and test the changed behavior.

Use these audit questions:

- Does the frontmatter satisfy Pi and the open specification?
- Does the description clearly cover capability and trigger contexts?
- Does the directory name match the skill name?
- Are instructions specific where failure is costly and flexible elsewhere?
- Are detailed resources loaded only when needed?
- Are all referenced paths valid and shallow?
- Are scripts portable enough for the declared compatibility?
- Does the skill avoid assumptions about another agent harness?
