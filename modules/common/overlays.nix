{ inputs, config, ... }: with inputs;{
  nixpkgs.overlays = [
    nix-xilinx.overlay
    curl-http3.overlays.default
    rust-overlay.overlays.default
    (final: super: {
      nixos-artwork-wallpaper = final.callPackage ../../packages/nixos-artwork-wallpaper/package.nix { };
      # nix = config.nix.package;
      # haskellPackages = super.haskellPackages.override {
      #   overrides = hsFinal: hsPrev: {
      #     cachix = hsPrev.cachix.override {
      #       nix = config.nix.package;
      #     };
      #   };
      # };
      python310 = super.python310.override {
        packageOverrides = pyself: pysuper: {
          py-slvs = pyself.callPackage ../../packages/python/py-slvs.nix { };
        };
      };
      blender = final.symlinkJoin {
        pname = "${super.blender.pname}-patched";
        inherit (super.blender) name version;
        paths = [ super.blender ];
        nativeBuildInputs = with final;[ makeWrapper python310Packages.wrapPython ];
        pythonPath = with final.python310Packages; [ numpy requests py-slvs ];
        postBuild = ''
          rm $out/bin/blender
          mv $out/bin/.blender-wrapped $out/bin/blender
          
          buildPythonPath "$pythonPath"
          wrapProgram $out/bin/blender \
            --prefix PATH : $program_PATH \
            --prefix PYTHONPATH : "$program_PYTHONPATH" \
            --add-flags "--python-use-system-env"
        '';
      };
    })
  ];
}
