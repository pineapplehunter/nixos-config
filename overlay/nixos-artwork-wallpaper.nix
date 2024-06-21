{ self, final, ... }: {
  inherit (self.packages.${final.system}) nixos-artwork-wallpaper;
}
