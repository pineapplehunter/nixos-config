{
  imports = [
    ./action/configuration.nix
    ./action/hardware-configuration.nix

    ./beast/configuration.nix
    ./beast/garage.nix
    ./beast/hardware-configuration.nix
    ./beast/immich-related.nix

    ./kpro-takata/configuration.nix
    ./kpro-takata/hardware-configuration.nix

    ./rpi5/default.nix
    ./rpi5/garage.nix
  ];
}
