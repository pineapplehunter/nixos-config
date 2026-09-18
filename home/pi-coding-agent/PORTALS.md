# Pi desktop portal integration

## Compatibility probe

The implementation targets the versions installed by this flake on 2026-09-18:

- xdg-desktop-portal 1.22.1
- xdg-desktop-portal-gnome 50.0 and xdg-desktop-portal-gtk 1.15.3
- Bubblewrap 0.12.0
- xdg-dbus-proxy 0.1.7

The document portal was not visible from the pre-existing Pi sandbox: `/run/user/1000/doc` was absent and the old proxy intentionally denied the portal bus names. Source inspection of xdg-desktop-portal 1.22.1 confirmed the applicable protocol:

- The D-Bus sender must expose a regular `/.flatpak-info` containing a valid application name and `[Instance] instance-id`.
- The portal reads `$XDG_RUNTIME_DIR/.flatpak/<instance-id>/bwrapinfo.json`, requires a positive `child-pid`, and opens a pidfd for that Bubblewrap child.
- The Documents FUSE layout is `<mount>/by-app/<application-id>/<document-id>/...`.
- Bubblewrap 0.12.0 supplies `--info-fd` and `--block-fd`; the wrapper uses them to publish `bwrapinfo.json` atomically before Pi starts.
- The filtered xdg-dbus-proxy 0.1.7 rules permit OpenURI.OpenURI, FileChooser.OpenFile, request cancellation, and request responses; they do not permit calls to `org.freedesktop.portal.Documents`.

At launch, the host-side wrapper activates `org.freedesktop.portal.Documents`, resolves `GetMountPoint`, and exposes only `by-app/io.github.pineapplehunter.Pi` as `/run/flatpak/doc`. If the host has no document portal, Pi still starts but file choosing is unavailable and a warning is printed.

## Python wrapper comparison

`wrapping.py` replaces the former 230-line shell wrapper. It preserves root discovery, personal/work profiles, PATH and `/etc` read-only bindings, worktree Git state, persistent project `/tmp`, `@debug-shell`, `@allow`, `@allow-rw`, `@@`, and the existing environment contract.

The Python implementation is longer, but process ownership is explicit: proxy and Pi children are tracked, signals are forwarded, file descriptors are passed deliberately, startup failures share one cleanup path, JSON from `--info-fd` is validated, and metadata writes are atomic. Those properties are substantially easier to review than shell coprocess and trap interactions, so the Python version is used as the production wrapper. PyGObject is already required by the portal clients and lets the wrapper resolve the Documents mount without parsing command output.

## Manual checks

After activating the Home Manager generation, run Pi from a graphical session and use the `open_uri` and `choose_file` tools. Useful boundary checks are:

1. Open an HTTPS URI; verify `file://` is rejected.
2. Choose one host file and verify the returned path begins with `/run/flatpak/doc/` and is readable.
3. Verify an unselected host path is absent from the sandbox.
4. Cancel a chooser and interrupt another request; neither should leave a dialog behind.
5. While Pi runs, inspect `$XDG_RUNTIME_DIR/.flatpak/pi-*` and `$XDG_RUNTIME_DIR/pi-dbus-proxy/session-*`; after exit both must be gone.
6. Start two Pi sessions and verify their instance IDs and sockets differ.
7. Verify `notify` and the Pueue completion hook still send notifications.
