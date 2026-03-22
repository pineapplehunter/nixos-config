{
  flake.homeModules.packages =
    { pkgs, lib, ... }:
    let
      # multilib for bintools
      multi-bintools = pkgs.wrapBintoolsWith { bintools = pkgs.binutils-unwrapped-all-targets; };

      wrapper = pkgs.writeShellApplication {
        name = "bubble-wrapper";
        runtimeInputs = [ pkgs.bubblewrap ];
        text = lib.readFile ./wrapping.sh;
      };

      opencode-wrapped =
        if pkgs.stdenv.hostPlatform.isLinux then
          pkgs.symlinkJoin {
            name = "opencode-wrapped";
            paths = [ pkgs.opencode ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              rm -rf "$out/bin"
              mkdir "$out/bin"
              makeWrapper "${lib.getExe wrapper}" "$out/bin/opencode" \
                --set EXECUTABLE "${lib.getExe pkgs.opencode}" \
                --set PROJECT_ROOT_FILE flake.nix
            '';
          }
        else
          pkgs.opencode;
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
          nix-init
          nix-update
          nixfmt
          nixpkgs-fmt
          opencode-wrapped
          project-init
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
