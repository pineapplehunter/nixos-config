{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (config.flake) overlays;
in
{
  imports = [
    ./gnome-settings-daemon.nix
    ./nix-search-cli.nix
    ./niks3.nix
    ./eza.nix
    ./ibus-engines.nix
    ./linux-latest.nix
    ./rpi5.nix
    ./fwupd.nix
  ];

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.nixgl.overlays.default
          overlays.default
        ];
      };
    };

  flake.overlays = {
    default = lib.composeManyExtensions [
      overlays.gnome-settings-daemon
      overlays.nix-search-cli
      overlays.niks3
      overlays.eza
      overlays.ibus-engines
      overlays.linux-latest
      overlays.fwupd
      overlays.custom-packages
    ];

    # Expose packages under ./packages through the default overlay so machine and
    # Home Manager modules can consume them. There is no linked upstream issue or PR.
    # Drop this only when this repository no longer contains custom packages.
    # Last checked: 2026-08-26.
    custom-packages =
      final: prev:
      prev.lib.packagesFromDirectoryRecursive {
        inherit (final) callPackage;
        directory = ./packages;
      };
  };
}
