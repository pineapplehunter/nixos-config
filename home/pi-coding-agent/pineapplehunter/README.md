# Pineapplehunter Pi package

This directory is a ready-to-load Pi package. Its static `package.json` uses
Pi's conventional resource discovery; no generated manifest or per-file Nix
mapping is needed.

```text
package.json
extensions/
  nix-bash.ts
  nix-search.ts
  notify.ts
  open-file/index.ts        # with OPEN_FILE.md
  pueue-tool/index.ts       # with DESIGN.md
skills/                    # complete personal skill directories
tools/subagents/           # launcher/runner sources and SUBAGENTS.md
wrapper/                   # sandbox/helper sources
sandbox-instructions.md
```

Try this directory directly from the repository root:

```sh
pi -e ./home/pi-coding-agent/pineapplehunter
```

Home Manager registers a Nix-store copy of this directory in `piPackages`,
alongside the existing npm packages. The separate `anthropic-skills` package is
assembled by a small `runCommand` that copies its static manifest and the curated
skills from the pinned upstream input. Both packages include complete skill
scripts/assets and design documentation.

Adding an extension under `extensions/` or a complete skill under `skills/`
requires no Nix or manifest edits. Pi supplies the declared peer dependencies;
no npm dependencies or second copies of Pi are bundled. Resolve helper paths
relative to the loaded skill's `SKILL.md`, not an assumed home resource path.

The parent `default.nix` still builds Python executables, sandbox services, and
Pueue configuration from these sources. `/open-file`, notifications, and automatic
Pueue turns require the corresponding sandbox/host runtime; installing resources
alone does not provide those services.

The parent's `update-settings.py` replaces the managed package list while
preserving unrelated Pi settings. Home Manager's activation script references
the package store paths, keeping them alive with the generation. On activation,
Home Manager removes resource links owned by the previous generation; unmanaged
user/project resources remain untouched. Restart Pi or reload after activation.
Subagents inherit the same package paths through the read-only Nix store.
Optional `pi-subagent --no-inherit-resources` suppresses automatic extension and
skill loading while explicitly retaining the pinned Pueue completion extension;
package resolution, other settings, prompts, and themes are unchanged. See
[the launcher documentation](tools/subagents/SUBAGENTS.md).

## Browse background work

Use `/pueue-logs` to select a task or `/pueue-logs <id>` to open one directly.
Finished tasks remain browsable until cleaned. A compact, themed task table
shows statuses and human labels, with the selected command in a separate preview.
The framed log viewer follows live output, supports arrows/Page Up/Page Down
scrolling, and uses `f` to switch auto-follow on/off. Escape returns to the task
list or closes it; Ctrl+C closes without cancelling work.

Subagents show readable assistant output, tool calls/results, and errors from
their recorded RPC stream. Press `v` for raw output. The viewer keeps the last
5,000 lines and does not insert logs into the agent's context. Child-private
Pueue queues are not browsed. See `extensions/pueue-tool/DESIGN.md` for limits.

Edit repository sources rather than immutable installed packages.
