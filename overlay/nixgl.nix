{
  flake.overlays.nixgl = final: prev: {
    # The pinned fork still uses PCRE1's pcregrep in wrapper checks, but
    # nixpkgs removed PCRE1. Supply the compatible PCRE2 tool only to nixGL.
    # https://github.com/pineapplehunter/nixGL/blob/d0cd6aab4e02279c8af82870921971855945fe29/nixGL.nix#L33
    # Remove once the pinned nixGL uses pcre2grep or another supported tool.
    nixgl = prev.nixgl.override {
      pcre = final.runCommand "nixgl-pcregrep-compat" { } ''
        mkdir -p "$out/bin"
        ln -s ${final.lib.getExe' final.pcre2 "pcre2grep"} "$out/bin/pcregrep"
      '';
    };
  };
}
