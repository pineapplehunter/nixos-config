{ inputs }: { config, pkgs, ... }:
{
  imports = [
    (import ./overlays.nix { inherit inputs; })
    ./packages.nix
    ./fonts.nix
    ./inputs.nix
    inputs.auto-cpufreq.nixosModules.default
  ];

  nixpkgs.config.allowUnfree = true;
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" "ca-derivations" ];
      trusted-users = [ "shogo" "riken" ];
      substituters = [
        "https://cache.nixos.org/"
        "https://pineapplehunter.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "pineapplehunter.cachix.org-1:OwpZtT7lADb4AYYprPubSST9jVs2fLVlgTLnsPyln7U="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    optimise.automatic = true;
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  programs.zsh = {
    enable = true;
    shellAliases = {
      ls = "${pkgs.eza}/bin/eza --icons";
      la = "ls -a";
      ll = "ls -lha";
    };
    ohMyZsh.enable = true;
    interactiveShellInit = ''
      eval "$(starship init zsh)"
    '';
  };
  users.defaultUserShell = pkgs.zsh;

  programs.direnv = {
    enable = true;
    silent = true;
    nix-direnv = {
      enable = true;
      # package = (pkgs.nix-direnv.overrideAttrs (old: {
      #   patches = [ ./direnv.patch ];
      #   postPatch = ''
      #     sed -i "2iNIX_BIN_PREFIX=${pkgs.nix}/bin/" direnvrc
      #     substituteInPlace direnvrc \
      #       --replace "grep" "${pkgs.gnugrep}/bin/grep"
      #     substituteInPlace direnvrc \
      #       --replace "nom" "${pkgs.nix-output-monitor}/bin/nom"
      #   '';
      # }));
    };
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable flatpak
  services.flatpak.enable = true;

  services.tailscale.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  services.avahi.enable = true;
  services.avahi.nssmdns = true;
  services.avahi.openFirewall = true;

  # Configure console keymap
  console.keyMap = "jp106";
}
