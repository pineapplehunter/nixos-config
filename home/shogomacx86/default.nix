{ pkgs, ... }:

{
  imports = [
    ../common
    ../common_mac
  ];

  home.username = "shogo";
  home.homeDirectory = "/Users/shogomacx86";

  home.packages = with pkgs;[
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
  ];
}
