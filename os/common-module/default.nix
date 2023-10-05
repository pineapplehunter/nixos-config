{ inputs }: { config, pkgs, ... }:
{
  imports = [
    (import ./overlays.nix { inherit inputs; })
    ./packages.nix
    ./fonts.nix
  ];

  nixpkgs.config.allowUnfree = true;
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" "ca-derivations" ];
      trusted-users = [ "shogo" "riken" ];
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
    };
    ohMyZsh.enable = true;
    interactiveShellInit = ''
      eval "$(starship init zsh)"
    '';
  };

  programs.direnv = {
    enable = true;
    silent = true;
    nix-direnv = {
      enable = true;
      package = (pkgs.nix-direnv.overrideAttrs (old: {
        patches = [ ./direnv.patch ];
        postPatch = ''
          sed -i "2iNIX_BIN_PREFIX=${pkgs.nix}/bin/" direnvrc
          substituteInPlace direnvrc \
            --replace "grep" "${pkgs.gnugrep}/bin/grep"
          substituteInPlace direnvrc \
            --replace "nom" "${pkgs.nix-output-monitor}/bin/nom"
        '';
      }));
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
}
