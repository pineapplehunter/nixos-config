{
  flake.homeModules.packages =
    { pkgs, lib, ... }:
    let
      # multilib for bintools
      multi-bintools = pkgs.wrapBintoolsWith { bintools = pkgs.binutils-unwrapped-all-targets; };

    in
    {
      config.home.packages =
        with pkgs;
        [
          age
          age-plugin-tpm
          age-plugin-yubikey
          agenix
          difftastic
          dig
          dust
          elan
          fuc
          fzf
          git-extras
          hl-log-viewer
          niks3
          nix-index
          nix-init
          nix-update
          nixfmt
          nixpkgs-fmt
          nixr
          project-init
          pv
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
