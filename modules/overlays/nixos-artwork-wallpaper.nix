{ final, ... }: {
  nixos-artwork-wallpaper = final.callPackage ../../packages/nixos-artwork-wallpaper/package.nix { };
}
