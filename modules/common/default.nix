{ pkgs, config, self, inputs, lib, ... }: {
  imports =
    let
      inherit (self.nixosModules) shell-config japanese;
      inherit (inputs) sops-nix xremap-flake home-manager;
    in
    [
      ./packages.nix
      ./fonts.nix
      shell-config
      japanese
      sops-nix.nixosModules.sops
      xremap-flake.nixosModules.default
      home-manager.nixosModules.home-manager
    ];

  nixpkgs = {
    overlays = [
      self.overlays.default
      inputs.nix-xilinx.overlay
    ];
    config.allowUnfree = true;
  };

  nix = {
    # package = pkgs.nixVersions.unstable;
    settings = {
      experimental-features = [ "nix-command" "flakes" "ca-derivations" ];
      trusted-users = [ "shogo" "riken" "shogotr" ];
      substituters =
        [ "https://cache.nixos.org/" "https://pineapplehunter.cachix.org" ];
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

  sops.defaultSopsFile = ../../secrets/secrets.yml;

  services.xremap.enable = lib.mkDefault false;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  i18n.inputMethod.enabled = "ibus";

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  programs.starship = {
    enable = true;
    # presets = [ "bracketed-segments" ];
  };
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ls = "${pkgs.eza}/bin/eza --icons --git --time-style '+%y/%m/%d %H:%M'";
      la = "ls -a";
      ll = "ls -lha";
      ip = "ip -c";
    };
  };
  environment.pathsToLink = [ "/share/zsh" ];

  users.defaultUserShell = pkgs.zsh;
  programs.not-found-exec.enable = true;

  programs.direnv = {
    enable = true;
    silent = true;
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

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  environment.variables = {
    BAT_THEME = "GitHub";
    DIRENV_WARN_TIMEOUT = "1h";
  };
}
