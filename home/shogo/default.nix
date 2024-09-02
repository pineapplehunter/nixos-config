{ pkgs, ... }:

{
  home.packages = with pkgs; [
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
