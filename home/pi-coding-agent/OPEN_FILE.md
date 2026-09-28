# Pi host file chooser integration

Pi exposes a user-only `/open-file` extension command. The command asks whether to select a file or directory, whether access should be read-only or read/write, and for optional context before opening the host desktop file chooser. It is not registered as an agent tool.

## Portal integration

The implementation targets the versions installed by this flake on 2026-09-18:

- xdg-desktop-portal 1.22.1
- xdg-desktop-portal-gnome 50.0 and xdg-desktop-portal-gtk 1.15.3
- Bubblewrap 0.12.0
- xdg-dbus-proxy 0.1.7

The document portal is not normally visible from the Pi sandbox. The integration relies on the following protocol:

- The D-Bus sender exposes a regular `/.flatpak-info` containing a valid application name and `[Instance] instance-id`.
- The portal reads `$XDG_RUNTIME_DIR/.flatpak/<instance-id>/bwrapinfo.json`, requires a positive `child-pid`, and opens a pidfd for that Bubblewrap child.
- The Documents FUSE layout is `<mount>/by-app/<application-id>/<document-id>/...`.
- Bubblewrap supplies `--info-fd` and `--block-fd`; the wrapper publishes `bwrapinfo.json` atomically before Pi starts.
- The filtered D-Bus proxy permits `FileChooser.OpenFile`, request cancellation, and request responses. It does not permit direct calls to `org.freedesktop.portal.Documents` from the sandbox.

At launch, the host-side wrapper activates `org.freedesktop.portal.Documents`, resolves `GetMountPoint`, and exposes only `by-app/io.github.pineapplehunter.Pi`. It is mounted read-only at `/run/flatpak/doc` and read/write at `/run/flatpak/doc-rw`. The Documents portal still enforces the permissions granted by the chooser backend. If the host has no document portal, Pi still starts, but `/open-file` cannot select a host path.

Both paths are temporary portal grants and may disappear. The command tells the agent to consider copying required content to `/tmp`, which is backed by persistent per-project storage. A read/write portal path modifies the host object directly; copying it to `/tmp` creates an independent copy.

## Wrapper implementation

`wrapping.py` preserves root discovery, personal/work profiles, PATH and `/etc` read-only bindings, worktree Git state, persistent project `/tmp`, `@debug-shell`, `@allow`, `@allow-rw`, `@@`, and the existing environment contract.

Process ownership is explicit: proxy and Pi children are tracked, signals are forwarded, file descriptors are passed deliberately, startup failures share one cleanup path, JSON from `--info-fd` is validated, and metadata writes are atomic. PyGObject is required by the portal client and lets the wrapper resolve the Documents mount without parsing command output.

## Manual checks

After activating the Home Manager generation, run Pi from a graphical session:

1. Verify `/open-file` is a slash command and is absent from the agent tool list.
2. Select files and directories with read-only access; verify returned paths begin with `/run/flatpak/doc/` and reject writes.
3. Select files and directories with read/write access; verify paths begin with `/run/flatpak/doc-rw/` and modifications affect the host object.
4. Supply optional context and verify a `mounted-path` message is delivered with the next user turn, without interrupting an active turn.
5. Verify the message warns that the portal path is temporary and suggests `/tmp` when persistence is needed.
6. Verify an unselected host path is absent from both Documents views.
7. Cancel each Pi dialog and the native chooser; no agent context should be emitted.
8. While Pi runs, inspect `$XDG_RUNTIME_DIR/.flatpak/pi-*` and `$XDG_RUNTIME_DIR/pi-dbus-proxy/session-*`; after exit both must be gone.
9. Start two Pi sessions and verify their instance IDs and sockets differ.
10. Verify notifications and the Pueue completion hook still work.
