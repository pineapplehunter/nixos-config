{ self, nixpkgs, inputs }:
let
  cfg-linux = mods: inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    modules = [
      { nixpkgs.overlays = [ self.overlays.default ]; }
    ] ++ mods;
  };
  cfg-darwin = mods: inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.x86_64-darwin;
    modules = [
      { nixpkgs.overlays = [ self.overlays.default ]; }
    ] ++ mods;
  };
in
rec {
  modules = {
    shogo = import ./shogo;
    shogotr = import ./shogotr;
    riken = import ./riken;
    shogomacx86 = import ./shogomacx86;
  };
  configurations = {
    shogo = cfg-linux [ modules.shogo ];
    shogotr = cfg-linux [ modules.shogotr ];
    riken = cfg-linux [ modules.riken ];
    shogomacx86 = cfg-darwin [ modules.shogomacx86 ];
  };
}
