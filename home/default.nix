{
  self,
  nixpkgs,
  inputs,
  ...
}:
let
  inherit (nixpkgs) lib;
  multiConfig =
    name: mods:
    lib.attrsets.mergeAttrsList (
      map (system: {
        "${name}-${system}" = inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = self.legacyPackages.${system};
          extraSpecialArgs = {
            inherit inputs self;
          };
          modules = [
            self.homeModules.common
            (
              { pkgs, ... }:
              {
                pineapplehunter.config-name = "${name}-${system}";
                home.username = name;
                home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${name}" else "/home/${name}";
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
    riken = import ./riken;
  };
  configurations = lib.attrsets.mergeAttrsList [
    (multiConfig "shogo" [ modules.shogo ])
    (multiConfig "shogotr" [ modules.riken ])
    (multiConfig "riken" [ modules.riken ])
  ];
}
