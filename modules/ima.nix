{
  flake.nixosModules.ima =
    {
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
          type = lib.types.listOf lib.types.str;
          apply = lib.unique;
          default = [
            "critical_data"
            "tcb"
          ];
        };
      };

      config = lib.mkIf cfg.enable {
        boot = {
          initrd.systemd.tpm2.enable = true;
          kernelParams = map (p: "ima_policy=${p}") cfg.policy;
        };

        environment = {
          etc."ima/ima-policy".text = ''
            measure func=MODULE_CHECK
            measure func=FIRMWARE_CHECK
            measure func=POLICY_CHECK
            measure func=CRITICAL_DATA
          '';
        };

        security = {
          tpm2.enable = true;
          lsm = [ "ima" ];
        };
      };
    };
}
