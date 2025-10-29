{
  flake.nixosModules.ima =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.my.ima;
    in
    {

      options.my.ima = {
        enable = lib.mkEnableOption "IMA support";
        policy = lib.mkOption {
          description = "IMA policy";
          type = lib.types.str;
          default = "critical_data";
        };
      };

      config = lib.mkIf cfg.enable {
        boot = {
          kernelPatches = [
            {
              name = "ima";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                EVM = yes;
                IMA = yes;
                IMA_DEFAULT_HASH_SHA256 = yes;
                IMA_READ_POLICY = yes;
                IMA_WRITE_POLICY = yes;
              };
            }
          ];
          initrd.systemd.enable = true;
          initrd.systemd.tpm2.enable = true;
          kernelParams = [ "ima_policy=${cfg.policy}" ];
        };

        environment.systemPackages = [ pkgs.ima-evm-utils ];

        security = {
          tpm2.enable = true;
          lsm = [ "ima" ];
        };

        systemd = {
          additionalUpstreamSystemUnits = lib.optionals config.systemd.tpm2.enable [
            "systemd-pcrfs-root.service"
            "systemd-pcrfs@.service"
            "systemd-pcrmachine.service"
            "systemd-pcrphase-initrd.service"
            "systemd-pcrphase-sysinit.service"
            "systemd-pcrphase.service"
          ];
        };
      };
    };
}
