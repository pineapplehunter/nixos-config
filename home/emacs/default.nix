{ pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  config = {
    programs.emacs = {
      enable = true;
      package = if isLinux then pkgs.emacs-unstable-pgtk else pkgs.emacs;
      extraPackages =
        epkgs:
        builtins.attrValues {
          inherit (epkgs)
            diff-hl
            eglot
            evil
            nix-mode
            slime
            tree-sitter
            tree-sitter-langs
            treesit-auto
            ;
        };
      extraConfig = builtins.readFile ./init.el;
    };

    services.emacs.enable = isLinux;

    home.file.".sbclrc".text = ''
      (load (posix-getenv "ASDF"))
    '';
  };
}
