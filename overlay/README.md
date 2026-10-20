# Overlays

This directory contains Nix overlays used by this repository.
They provide
- Local package customizations
- Workarounds for upstream issues
- Newer package variants
- Packages maintained directly in this configuration

## Adding an overlay

All overlays must be registered in `default.nix`.
Add comments covering the following to the overlay file:

- Why it is needed
- The relevant upstream issue, pull request, or commit, when one exists
- When the override can be removed

Record the common batch-audit date below rather than in each overlay file.

Most should be included in the default overlay, while hardware-specific overlays may be enabled only by the relevant machine configuration.

## Experimental Ghostty scrolling

`ghostty.nix` ports the shader-based prototype from
[Ghostty discussion #3206](https://github.com/ghostty-org/ghostty/discussions/3206#discussioncomment-19000959)
to the pinned Ghostty 1.3.1 package. It is included in the default overlay;
`home/ghostty.nix` enables the installed shader without continuous animation.

Precision scroll events shift the viewport by the fractional row remainder.
Alternate-screen applications, mouse-reporting applications, and selections stay
on the cell grid. Typing or clicking resets the offset; clicking therefore snaps
the text before hit-testing rather than supporting fractional-row selection.

This is not native smooth scrolling: it does not render the extra row exposed at
the viewport edge, correct hover hit-testing for shifted text, or add momentum or
elastic overscroll. Ordinary mouse-wheel scrolling stays line-based. Remove the
Home Manager `custom-shader` setting to disable the visual effect. The source
patch needs reviewing when Ghostty is upgraded.

## Last checked

All overlays were last checked together on 2026-10-14.

## Backports

- VTK 9.5 and 9.6's PEGTL configuration fix from
  [nixpkgs PR #572295](https://github.com/NixOS/nixpkgs/pull/572295) is backported
  until the pinned input includes it. This is a partial update, not a new
  full-batch audit.
- Mozc UT dictionary updates and the pinned-input merger from
  [nixpkgs PR #570751](https://github.com/NixOS/nixpkgs/pull/570751) are backported
  onto the local split Mozc package. The legacy merger attribute is not overridden;
  Fcitx configuration is unchanged. This is a partial update, not a new full-batch
  audit.
