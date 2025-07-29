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
    common = import ./common;
    nixos-common = {
      imports = [ self.homeModules.common ];
      config.pineapplehunter.is-nixos = true;
    };
    alacritty = ./alacritty/default.nix;
    dconf = ./dconf/default.nix;
    emacs = ./emacs/default.nix;
    flatpak-update = ./flatpak-update/default.nix;
    ghostty = ./ghostty/default.nix;
    helix = ./helix/default.nix;
    minimal = ./minimal/default.nix;
    pineapplehunter = ./pineapplehunter/default.nix;
    shogo = ./shogo/default.nix;
    zellij = ./zellij/default.nix;
    cradsec = ./cradsec/default.nix;
    ssh = ./ssh/default.nix;
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
