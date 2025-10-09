{
  inputs,
  config,
  lib,
  withSystem,
  ...
}:
let
  mods = config.flake.homeModules;
  config-template = [
    {
      configname = "shogo";
      username = "shogo";
      modules = [
        mods.common
        mods.shogo
      ];
    }
    {
      configname = "kpro";
      username = "takata";
      modules = [
        mods.common
        mods.kpro
      ];
    }
    {
      configname = "minimal-shogo";
      username = "shogo";
      modules = [
        mods.minimal
        mods.shogo
      ];
    }
  ];
  all-configs = lib.cartesianProduct {
    system = config.systems;
    config = config-template;
  };
  configurations = lib.listToAttrs (
    map (
      { system, config }:
      {
        name = "${config.configname}-${system}";
        value = inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = withSystem system ({ pkgs, ... }: pkgs);
          modules = [
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
  imports = [
    inputs.home-manager.flakeModules.home-manager

    ./alacritty/default.nix
    ./common.nix
    ./cradsec.nix
    ./dconf.nix
    ./emacs/default.nix
    ./flatpak-update.nix
    ./ghostty.nix
    ./helix/default.nix
    ./inkscape-symbols.nix
    ./julia.nix
    ./kpro.nix
    ./minimal.nix
    ./nixos-common.nix
    ./packages-minimal.nix
    ./packages.nix
    ./pineapplehunter.nix
    ./shogo.nix
    ./ssh.nix
    ./zellij.nix
  ];

  flake.homeConfigurations = configurations;
}
