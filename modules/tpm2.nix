{
  flake.nixosModules.tpm2 =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.tpm2;
    in
    {
      options.my.tpm2.enable = lib.mkEnableOption "enable common tpm features";
      config = lib.mkIf cfg.enable {
        security.tpm2 = {
          enable = true;
          abrmd.enable = lib.mkDefault true;
          pkcs11.enable = lib.mkDefault true;

          tctiEnvironment.enable = lib.mkDefault true;
          tctiEnvironment.interface = lib.mkDefault "tabrmd";
        };

        environment.systemPackages = [
          pkgs.tpm2-tools
          pkgs.tss2
        ];
      };
    };
}
