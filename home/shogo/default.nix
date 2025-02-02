{ pkgs, ... }:

{
  home.packages = builtins.attrValues {
    inherit (pkgs)
      cargo-show-asm
      cargo-binutils
      cargo-bloat
      cargo-expand
      cargo-fuzz
      cargo-outdated
      cargo-tauri
      cargo-watch
      racket
      sqlx-cli
      trunk
      ;
  };

  programs.git = {
    userName = "Shogo Takata";
    userEmail = "peshogo@gmail.com";
  };
}
