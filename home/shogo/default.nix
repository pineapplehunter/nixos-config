{ pkgs, ... }:

{
  home.packages = builtins.attrValues {
    inherit (pkgs)
      sqlx-cli
      cargo-tauri
      cargo-expand
      cargo-fuzz
      cargo-watch
      cargo-bloat
      cargo-outdated
      cargo-asm
      cargo-binutils
      trunk
      ;
  };

  programs.git = {
    userName = "Shogo Takata";
    userEmail = "peshogo@gmail.com";
  };
}
