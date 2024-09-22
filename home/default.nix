{
  self,
  nixpkgs,
  inputs,
}:
let
  inherit (nixpkgs) lib;
  multiConfig =
    name: mods:
    lib.attrsets.mergeAttrsList (
      map
        (system: {
          "${name}-${system}" = inputs.home-manager.lib.homeManagerConfiguration {
            pkgs = self.legacyPackages.${system};
            modules = mods ++ [
              self.homeModules.common
              self.homeModules.pineapplehunter
              (
                { pkgs, ... }:
                {
                  pineapplehunter.config-name = "${name}-${system}";
                  home.username = name;
                  home.homeDirectory =
                    let
                      inherit (pkgs.stdenv) isLinux isDarwin;
                    in
                    if isLinux then
                      "/home/${name}"
                    else if isDarwin then
                      "/Users/${name}"
                    else
                      throw "os not supported";
                }
              )
            ];
          };
        })
        [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ]
    );

in
rec {
  modules = {
    common = import ./common;
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
