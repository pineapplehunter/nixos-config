{ pkgs, ... }:

{
  home.packages = [
    pkgs.cargo-show-asm
    pkgs.cargo-binutils
    pkgs.cargo-bloat
    pkgs.cargo-expand
    pkgs.cargo-fuzz
    pkgs.cargo-outdated
    pkgs.cargo-tauri
    pkgs.cargo-watch
    pkgs.sqlx-cli
    pkgs.trunk
  ];

  programs.git = {
    userName = "Shogo Takata";
    userEmail = "peshogo@gmail.com";
  };
}
