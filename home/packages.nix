{
  flake.homeModules.packages =
    { pkgs, ... }:
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
          nix-index
          nix-update
          nixfmt-rfc-style
          nixpkgs-fmt
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
          (tpm2-tools.override { abrmdSupport = false; })
        ];
    };
}
