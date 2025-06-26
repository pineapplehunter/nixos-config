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
            self.homeModules.common
            (
              { pkgs, ... }:
              {
                pineapplehunter.config-name = "${cfgname}-${system}";
                home.username = username;
                home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
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
    pineapplehunter = import ./pineapplehunter;
    shogo = import ./shogo;
    flatpak-update = import ./flatpak-update;
    emacs = import ./emacs;
    alacritty = import ./alacritty;
    helix = import ./helix;
  };
  configurations = lib.attrsets.mergeAttrsList [
    (multiConfig "shogo" "shogo" [ modules.shogo ])
  ];
}
