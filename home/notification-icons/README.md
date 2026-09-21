# Notification icons

These raster icons are hosted from this repository for use as Discord webhook avatars.

- `pi`: the official [Pi Coding Agent logo](https://pi.dev/press-kit), converted to PNG.
- `pueue`: a project-local queue/process mark, created because Pueue has no compact official icon. Pueue's repository only publishes a terminal demo image.

The SVG sources are retained so the PNGs can be regenerated with:

```console
rsvg-convert --width 256 --height 256 --output pi.png pi.svg
rsvg-convert --width 256 --height 256 --output pueue.png pueue.svg
```
