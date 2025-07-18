{
  self,
  nixpkgs,
  inputs,
  ...
}:
let
  inherit (nixpkgs) lib;
  multiConfig =
    cfgname: username: mods:
    lib.attrsets.mergeAttrsList (
      map (system: {
        "${cfgname}-${system}" = inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = self.legacyPackages.${system};
          extraSpecialArgs = {
            inherit inputs self;
          };
          modules = [
            self.homeModules.pineapplehunter
            (
              { pkgs, ... }:
              {
                pineapplehunter.config-name = "${cfgname}-${system}";
                home.username = username;
                home.homeDirectory =
                  if pkgs.stdenv.hostPlatform.isDarwin then "/Users/${username}" else "/home/${username}";
              }
            )
          ] ++ mods;
        };
      }) (import inputs.systems)
    );

in
rec {
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
  };
  configurations = lib.attrsets.mergeAttrsList [
    (multiConfig "shogo" "shogo" [
      modules.common
      modules.shogo
    ])
    (multiConfig "minimal-shogo" "shogo" [
      modules.minimal
      modules.shogo
    ])
  ];
}
