# Pi host integration

Home Manager installs Pi, `pi-update`, Bubblewrap wrappers (`pi`, `pi-work`,
`pi-auto`), the private Pueue integration, subagent launcher/runner, clipboard,
portal clients, and host MCP registrations. Host/runtime sources remain under
`pineapplehunter/wrapper/` and `pineapplehunter/tools/subagents/`.

Extensions, global skills, external package declarations, and shared agent
instructions now live in the separate
[pi-customizations](https://github.com/pineapplehunter/pi-customizations)
repository. This module no longer imports those resources into the Nix store,
writes a package list during activation, or manages the global `AGENTS.md`.
Project-specific `.pi/skills` stay in this repository.

## Migration / updating

1. Rebuild Home Manager/NixOS once to install the updater and new runtime paths.
2. Before launching Pi/subagents, seed the copied package:

   ```sh
   pi-update --local /absolute/path/to/pi-customizations
   ```

3. Commit/push the resource repository to its default GitHub location, then use:

   ```sh
   pi-update
   ```

Both modes update all configured global external packages. `--local` only
changes the customization source; it always copies and never edits that checkout.
`--repo URL`/`--branch NAME` (or `PI_CUSTOMIZATIONS_REPO`/`PI_CUSTOMIZATIONS_BRANCH`)
override the default `pineapplehunter/pi-customizations` `main` source.

The package snapshot lives at `~/.pi/customizations/package/`, already visible
through existing `~/.pi` sandbox/subagent mounts. The launcher explicitly loads
that snapshot's Pueue extension with `--no-inherit-resources`; run the updater
before launching subagents. Host code changes still need a rebuild; resources
need only an update and Pi reload/restart. Pi itself remains Nix-managed:
`pi-update` invokes the unwrapped executable's `update --extensions`, not
`pi update` (which would request a self-update).

The updater preserves unrelated preferences/packages, authentication, sessions,
and MCP settings. It tracks owned package entries, retires the two old
Nix-store resource packages, and replaces only its own resource snapshot. Existing
linked profile settings follow the personal profile; independent settings are
merged and updated separately. A failed external update exits nonzero but may
leave some external packages already updated; retry after fixing the error.
Home Manager activation itself performs no customization/package network update.

See the resource repository README for portability, package ownership, licenses,
and vendored upstream maintenance. The host MCP merge still uses `update-mcp.py`
and remains independent of customization updates.

## Wrapper flags

Use `pi @noflake` (also `pi-work`/`pi-auto`) to sandbox the current directory
instead of finding an ancestor `flake.nix`. That directory is writable inside
the sandbox. Wrapper flags precede Pi arguments, for example:

```sh
pi @noflake --print "Summarize this directory"
```

Combine with `@debug-shell`, `@allow PATH` (read-only), or `@allow-rw PATH`.
`@@` ends wrapper flag parsing. `@dev` exposes the entire host `/dev` and mounts
`/sys` read-only for hardware discovery. Host device permissions still apply;
only enable it for trusted hardware/firmware work. Without it, the minimal
sandbox `/dev` remains unchanged.

## Checks

```sh
python3 -m unittest discover -s home/pi-coding-agent/tests -p 'test_update*.py'
nix flake check --no-build --all-systems
```

Wrapper D-Bus tests need `dbus-next` and an explicitly private `dbus-run-session`;
see `tests/test_wrapper_dbus.py`. Resource tests moved to pi-customizations.
