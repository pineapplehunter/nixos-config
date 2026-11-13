{
  flake.nixosModules.action-pam = import ../pam.nix { withHowdy = true; };
}
