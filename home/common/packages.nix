{ pkgs, ... }:
{
  config.home.packages =
    with pkgs;
    [
      age
      age-plugin-tpm
      age-plugin-yubikey
      agenix
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
    ];
}
