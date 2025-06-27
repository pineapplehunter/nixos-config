{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
in
{
  config.home.packages =
    with pkgs;
    [
      attic-client
      difftastic
      dust
      elan
      fd
      ffmpegthumbnailer
      file
      fzf
      htop
      jq
      ncdu
      nix-index
      nix-output-monitor
      nix-search-cli
      nix-tree
      nix-update
      nixfmt-rfc-style
      nixpkgs-fmt
      nixpkgs-review
      npins
      ripgrep
      starship
      tokei
      tree
      typst
      wabt
      wasm-tools
      wasmtime
      xh
      zellij
    ]
    ++ [
      # multilib for bintools
      (pkgs.wrapBintoolsWith { bintools = pkgs.binutils-unwrapped-all-targets; })
    ]
    ++ lib.optionals isDarwin [ pkgs.iterm2 ]
    ++ lib.optionals isLinux [ pkgs.julia ];
}
