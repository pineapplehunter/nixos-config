{
  self,
  nixpkgs,
  inputs,
  ...
}:
let
  inherit (nixpkgs) lib;
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];
  modules = {
    alacritty = ./alacritty/default.nix;
    common = ./common/default.nix;
    cradsec = ./cradsec.nix;
    dconf = ./dconf.nix;
    emacs = ./emacs/default.nix;
    flatpak-update = ./flatpak-update.nix;
    ghostty = ./ghostty.nix;
    helix = ./helix/default.nix;
    julia = ./julia.nix;
    kpro = ./kpro.nix;
    minimal = ./minimal/default.nix;
    nixos-common = {
      imports = [ self.homeModules.common ];
      config.pineapplehunter.isNixos = true;
    };
    pineapplehunter = ./pineapplehunter.nix;
    shogo = ./shogo.nix;
    ssh = ./ssh.nix;
    zellij = ./zellij/default.nix;
  };
  config-template = [
    {
      configname = "shogo";
      username = "shogo";
      modules = [
        modules.common
        modules.shogo
      ];
    }
    {
      configname = "kpro";
      username = "takata";
      modules = [
        modules.common
        modules.kpro
      ];
    }
    {
      configname = "minimal-shogo";
      username = "shogo";
      modules = [
        modules.minimal
        modules.shogo
      ];
    }
  ];
  all-configs = lib.cartesianProduct {
    system = systems;
    config = config-template;
  };
  configurations = lib.listToAttrs (
    map (
      { system, config }:
      {
        name = "${config.configname}-${system}";
        value = inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = self.legacyPackages.${system};
          extraSpecialArgs = { inherit inputs self; };
          modules = [
            self.homeModules.pineapplehunter
            (
              { pkgs, ... }:
              {
                pineapplehunter.config-name = "${config.configname}-${system}";
                home.username = config.username;
                home.homeDirectory =
                  if pkgs.stdenv.hostPlatform.isDarwin then
                    "/Users/${config.username}"
                  else
                    "/home/${config.username}";
              }
            )
          ]
          ++ config.modules;
        };
      }
    ) all-configs
  );
in
{
  inherit modules configurations;
}
