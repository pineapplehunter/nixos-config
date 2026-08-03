## My Nix configurations
[![CI](https://github.com/pineapplehunter/nixos-config/actions/workflows/check-and-cache.yml/badge.svg)](https://github.com/pineapplehunter/nixos-config/actions/workflows/check-and-cache.yml)

- NixOS configurations
- Home Manager configurations
- Custom overlays

## Bootstrapping Home Manager

```shell
$ git clone https://github.com/pineapplehunter/nixos-config.git
$ HOME_CONFIG_NAME=shogo-x86_64-linux nix develop -c home switch
```

## Bootstrapping NixOS

```shell
$ git clone https://github.com/pineapplehunter/nixos-config.git
$ HOST=action nix develop -c os switch
```
