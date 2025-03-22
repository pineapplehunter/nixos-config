{ pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  config = {
    programs.emacs = {
      enable = true;
      package = if isLinux then pkgs.emacs-unstable-pgtk else pkgs.emacs;
      extraPackages = epkgs: [
        epkgs.diff-hl
        epkgs.eglot
        epkgs.evil
        epkgs.nix-mode
        epkgs.slime
        epkgs.tree-sitter
        epkgs.tree-sitter-langs
        epkgs.treesit-auto
      ];
      extraConfig = builtins.readFile ./init.el;
    };

    services.emacs.enable = isLinux;

    home.file.".sbclrc".text = ''
      (load (posix-getenv "ASDF"))
    '';
  };
}
