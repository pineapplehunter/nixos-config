{
  flake.homeModules.packages =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # multilib for bintools
      multi-bintools = pkgs.wrapBintoolsWith { bintools = pkgs.binutils-unwrapped-all-targets; };
      niks3-wrapped = pkgs.symlinkJoin {
        name = "niks3-wrapper";
        paths = [ pkgs.niks3 ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/niks3" \
            --set-default NIKS3_SERVER_URL "https://niks3.s.ihavenojob.work" \
            --set-default NIKS3_AUTH_TOKEN_FILE "${config.sops.secrets.niks3-token.path}"
        '';
      };
    in
    {
      config.home.packages =
        with pkgs;
        [
          age
          age-plugin-tpm
          age-plugin-yubikey
          difftastic
          dig
          dust
          elan
          fuc
          fzf
          git-extras
          hl-log-viewer
          niks3-wrapped
          nix-init
          nix-update
          nixfmt
          nixpkgs-fmt
          nixr
          project-init
          pv
          sops
          starship
          tokei
          tree
          typst
          wabt
          wasm-tools
          wasmtime
          xh
          zellij
        ]
        ++ [
          multi-bintools
        ]
        ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
          tpm2-tools
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          wayscriber
        ];
    };
}
