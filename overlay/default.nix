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
    ./flatpak.nix
    ./gnome-settings-daemon.nix
    ./face-recognition-models.nix
    ./nix-search-cli.nix
    ./eza.nix
    ./tpm2-tools.nix
    ./vtk.nix
    ./opencode.nix
    ./ibus-engines.nix
    ./linux-latest.nix
    ./rpi5.nix
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
      overlays.flatpak
      overlays.gnome-settings-daemon
      overlays.face-recognition-models
      overlays.nix-search-cli
      overlays.eza
      overlays.tpm2-tools
      overlays.vtk
      overlays.opencode
      overlays.ibus-engines
      overlays.linux-latest
      overlays.custom-packages
    ];

    custom-packages =
      final: prev:
      prev.lib.packagesFromDirectoryRecursive {
        inherit (final) callPackage;
        directory = ./packages;
      };
  };
}
