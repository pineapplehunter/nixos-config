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
    ./btrfs-assistant.nix
    ./canon-cups-ufr2.nix
    ./curl-upki.nix
    ./errands.nix
    ./gitify.nix
    ./gnome-settings-daemon.nix
    ./hl-log-viewer.nix
    ./omnix.nix
    ./tpm-passkey.nix
    ./niks3.nix
    ./nixgl.nix
    ./eza.nix
    ./rpi5.nix
    ./snapper-gui.nix
    ./super-productivity.nix
    ./tuned.nix
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
      overlays.btrfs-assistant
      overlays.canon-cups-ufr2
      overlays.curl-upki
      overlays.errands
      overlays.gitify
      overlays.gnome-settings-daemon
      overlays.hl-log-viewer
      overlays.omnix
      overlays.tpm-passkey
      overlays.niks3
      overlays.nixgl
      overlays.eza
      overlays.snapper-gui
      overlays.super-productivity
      overlays.tuned
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
