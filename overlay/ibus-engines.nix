{
  flake.overlays.ibus-engines = final: prev: {
    # Wire custom mozc / mozc-ut packages into ibus-engines.
    ibus-engines = prev.ibus-engines // {
      mozc = final.ibus-mozc;
      mozc-ut = final.ibus-mozc.override { mozc = final.mozc-ut; };
    };
  };
}
