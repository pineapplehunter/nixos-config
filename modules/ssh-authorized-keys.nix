{ lib, ... }:
{
  flake.nixosModules.ssh-authorized-keys = {
    options.my.sshAuthorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "SSH public keys authorized to access all machines.";
    };
    config.my.sshAuthorizedKeys = lib.mkDefault [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM/QhUXk6LPpFd97zUow1bHkkF1CvRAjCG1iIfg5BBhd"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKsIPYx8p1UIWdxSeziHpy9Ulg3P5tUghMlCvREso2H"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII9nG2lTRf+GAA92Df7yTbxPmL3EMNMgVr5tIv3YgJI7"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4374jhuKtCRAl0oUFRyWhBw1CoPjRved9KwhFCP0MW"
    ];
  };
}
