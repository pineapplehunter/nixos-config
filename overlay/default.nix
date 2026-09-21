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
    ./niks3.nix
    ./eza.nix
    ./ibus-engines.nix
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
      overlays.gnome-settings-daemon
      overlays.niks3
      overlays.eza
      overlays.ibus-engines
      overlays.custom-packages
    ];

    # Expose packages under ./packages through the default overlay so machine and
    # Home Manager modules can consume them. There is no linked upstream issue or PR.
    # Drop this only when this repository no longer contains custom packages.
    custom-packages =
      final: prev:
      prev.lib.packagesFromDirectoryRecursive {
        inherit (final) callPackage;
        directory = ./packages;
      };
  };
}
