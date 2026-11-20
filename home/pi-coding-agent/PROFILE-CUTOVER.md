# Pi Work/Auto profile cutover

Run this from a **host terminal outside Pi**, as the account that owns `~/.pi`.
The utility uses Python 3 and no network. It is not installed or run by Home
Manager, `pi-update`, or any launcher.

From the `nixos-config` checkout:

```sh
python3 home/pi-coding-agent/pi-profile-cutover.py
```

This is a dry run. The report contains known setting names and session counts,
not values, transcript paths, or transcript content. `--home /path/to/fixture`
selects a different root without consulting `PI_CODING_AGENT_DIR`.

## What it can merge

- The active `pi`, `pi-work` and `pi-auto` wrappers all set
  `PI_CODING_AGENT_SESSION_DIR` to `~/.pi/agent/sessions`. Normally there is no
  Work/Auto history to copy. For older profile-local histories, both flat and
  Pi's `--<working-directory>--` layouts under each profile's `sessions/` are
  checked. Byte-identical files with the same header ID are deduplicated across
  names and profiles. Differing histories with the same ID and destination
  path conflicts are reported, not overwritten or spliced. When only Work and
  Auto conflict, neither wins. Copies preserve transcript bytes and mtime, so
  any `parentSession` path remains as originally recorded. If a canonical
  session entry cannot be compared safely, session staging is withheld.
- For `settings.json`, only allowlisted, typed UI/thinking/compaction
  preferences are eligible. Missing safe fields, including individual fields
  in supported nested objects, can be added; existing canonical fields win.
  If Work and Auto disagree on a field missing in canonical, it is omitted.
  Links, multiply linked files, and non-regular inputs are not followed.
  The Work/Auto wrappers commonly link settings to canonical; those already
  share the same settings. If canonical settings are linked or invalid, no
  settings additions are offered.
- The utility does **not** import credentials, MCP or model configs,
  proxies, shell/updater commands, package declarations, extension settings,
  npm/git/cache state, trust decisions or `defaultProjectTrust`, custom
  resources, keybindings, provider/model defaults or model lists, subagent
  presets, reserve, routes, or custom session locations. Review those
  separately; do not copy whole profile directories into canonical. It
  checks session headers, not the entire transcript structure, and does not
  infer a Codex route from a filename, old provider ID, or profile name.

## Later apply and retirement

1. With the legacy wrappers still available, verify plain `pi` with
   `codex-host` and the desired `/codex-route` choices. Verify the workflows
   you depend on (usage, search/fetch, subagents, and separately configured
   images, as applicable). Explicitly choose and save the canonical model
   and default route; update any old model IDs in presets only after review.
   For a resumed session with an obsolete model ID, reselect it under
   `codex-host` and choose its route explicitly when needed.
2. Close all Pi instances and queued/running subagents using these profiles.
   Keep the current host generation and customization snapshot for rollback.
   Make a private backup of canonical `settings.json` (or record its absence)
   and `sessions/`, without copying or moving logins. Run the dry run again and
   review its conflict counts. Resolve any skipped histories manually before
   retiring wrappers, or keep them in the old profiles for later review.
3. From the same host terminal, run:

   ```sh
   python3 home/pi-coding-agent/pi-profile-cutover.py --stage
   ```

   It writes `~/pi-cutover-*/` with mode `0700`, not into any profile. Use only
   the bundle named on successful completion. Keep it private: transcripts
   can contain sensitive text, and the bundle is not scrubbed. Skipped or
   conflicting entries remain in their original profiles; there is no live
   apply flag.
4. While Pi is still stopped, review `settings-additions.json` locally and
   add its fields to canonical `settings.json` (including at the indicated
   nested locations). Do **not** replace canonical settings with the additions
   file. If canonical settings are managed by a symlink, edit their owning
   configuration separately. For sessions, explicitly copy the staged files
   retaining their relative paths, without overwriting. For example, in Bash
   with GNU coreutils supporting `--update=none-fail`:

   ```bash
   # Replace this with the exact directory reported by --stage.
   stage="$HOME/pi-cutover-REVIEWED"
   (
     set -eu
     umask 077
     test -f "$stage/settings-additions.json"
     cd -- "$stage/sessions"
     find . -type f -name '*.jsonl' -print0 > "$stage/session-additions.list"
     while IFS= read -r -d '' src; do
       dest="$HOME/.pi/agent/sessions/${src#./}"
       mkdir -p -- "$(dirname -- "$dest")"
       cp --update=none-fail --preserve=timestamps -- "$src" "$dest"
     done < "$stage/session-additions.list"
   )
   ```

   Do not apply a stale bundle after profiles have changed. If a copy fails,
   stop and generate a fresh plan; earlier copies may already have succeeded.
5. Start plain `pi`, confirm `/resume` sees expected history and default
   settings work. Switch scripts/shortcuts from `pi-work` and `pi-auto` to
   plain `pi`. Only after a successful verification period, make a separate
   reviewed Nix change retiring those two entrypoints, the associated profile
   branches in `wrapping.py`, and their profile-specific Home Manager MCP
   activation and updater targets. Rebuild the host generation. Leave legacy
   dirs and logins intact through the rollback window. If you later archive
   the legacy dirs offline, keep them private; do not log out shared logins
   or remove access to independent providers from canonical `auth.json`.

## Rollback

Stop Pi and its workers. Restore the prior host generation and customization
snapshot, and restore script/shortcut changes. Back up current canonical
settings before restoring the pre-cutover copy or reversing just the added
fields. Existing wrappers already see the canonical session directory, so
imported history may stay. To undo only this import, use the staging manifest
and move those added files to a private archive without overwriting anything;
preserve later sessions and any changes to imported transcripts. If legacy
dirs were archived after verification, restore them under their original names
without overwriting any recreated dirs. No broker or legacy logout is needed.
