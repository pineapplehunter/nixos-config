{
  flake.homeModules.opencode =
    { pkgs, lib, ... }:
    let
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
      programs.opencode = {
        enable = true;
        package = opencode-wrapped;
        settings = lib.mkMerge [
          {
            autoupdate = false;
            formatter = true;
            lsp = true;
          }
          (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
            permission = "allow";
          })
        ];
        skills = {
          flake = ./flake.md;
          nixpkgs = ./nixpkgs.md;
          sandbox = ./sandbox.md;
        };
      };
    };
}
