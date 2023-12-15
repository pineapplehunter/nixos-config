{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    f5vpn-rpm = {
      url = "https://huskyonnet-ns.uw.edu/public/download/linux_f5vpn.x86_64.rpm";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, f5vpn-rpm }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.permittedInsecurePackages = [
          "qtwebkit-5.212.0-alpha4"
          "openssl-1.1.1w"
        ];
      };
    in

    {
      packages.x86_64-linux.default = self.packages.x86_64-linux.f5vpn;

      packages.x86_64-linux.f5vpn = pkgs.callPackage ./f5vpn.nix { };

      formatter.x86_64-linux = pkgs.nixpkgs-fmt;

      devShell.x86_64-linux = pkgs.mkShell {
        packages = with pkgs;[ rpm cpio openssl ];
      };
    };
}
