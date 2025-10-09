{
  flake.homeModules.packages =
    { pkgs, ... }:
    let
      # multilib for bintools
      multi-bintools = pkgs.wrapBintoolsWith { bintools = pkgs.binutils-unwrapped-all-targets; };

      tpm2-tools-wrapper =
        name:
        pkgs.writeShellScriptBin name ''
          usage(){
            echo Usage: $0 sub-command args
            echo availible subcommands:
            find ${pkgs.tpm2-tools}/bin -name "${name}_*" | xargs -I@ basename @ | sort | sed 's/${name}_/  /g'
          }

          if [ -z "$1" ]; then
            echo sub command not specified
            usage
            exit 1
          fi

          subcmd="$1"
          cmd="${pkgs.tpm2-tools}/bin/${name}_$subcmd"

          if ! [ -f "$cmd" ]; then
            echo sub command does not exist
            usage
            exit 2
          fi
          shift
          exec "$cmd" "$@"
        '';
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
          (tpm2-tools-wrapper "tpm2")
          (tpm2-tools-wrapper "tss2")
        ];
    };
}
