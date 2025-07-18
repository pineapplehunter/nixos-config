{ pkgs, lib, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
{
  config.home.packages =
    with pkgs;
    [
      difftastic
      dust
      elan
      fzf
      nix-index
      nix-update
      nixfmt-rfc-style
      nixpkgs-fmt
      tokei
      starship
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
    ++ lib.optionals isLinux [ pkgs.julia ];
}
