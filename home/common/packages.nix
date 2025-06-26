{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
in
{
  config.home.packages =
    [
      pkgs.attic-client
      pkgs.chafa
      pkgs.difftastic
      pkgs.dust
      pkgs.elan
      pkgs.fd
      pkgs.ffmpegthumbnailer
      pkgs.file
      pkgs.fzf
      pkgs.htop
      pkgs.imagemagick
      pkgs.jq
      pkgs.ncdu
      pkgs.nix-index
      pkgs.nix-output-monitor
      pkgs.nix-search-cli
      pkgs.nix-tree
      pkgs.nix-update
      pkgs.nixfmt-rfc-style
      pkgs.nixpkgs-fmt
      pkgs.nixpkgs-review
      pkgs.npins
      pkgs.p7zip
      pkgs.ripgrep
      pkgs.starship
      pkgs.tokei
      pkgs.tree
      pkgs.typst
      pkgs.wasmtime
      pkgs.xh
      pkgs.zellij
      pkgs.zoxide

      # multilib for bintools
      (pkgs.wrapBintoolsWith { bintools = pkgs.binutils-unwrapped-all-targets; })
    ]
    ++ lib.optionals isDarwin [ pkgs.iterm2 ]
    ++ lib.optionals isLinux [ pkgs.julia ];
}
