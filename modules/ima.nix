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
          kernelPatches = [
            {
              name = "ima";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                IMA = yes;
                IMA_APPRAISE = yes;
                IMA_APPRAISE_BOOTPARAM = yes;
                IMA_DEFAULT_HASH_SHA256 = yes;
                IMA_KEXEC = yes;
                IMA_LSM_RULES = yes;
                IMA_MEASURE_ASYMMETRIC_KEYS = yes;
                IMA_NG_TEMPLATE = yes;
                IMA_QUEUE_EARLY_BOOT_KEYS = yes;
                IMA_READ_POLICY = yes;
                IMA_WRITE_POLICY = yes;

                # Make crypto modules builtin.
                # Crypto modules required to run IMA are not measured.
                CRYPTO_AEAD = yes;
                CRYPTO_AES_NI_INTEL = yes;
                CRYPTO_LIB_GF128MUL = yes;
              };
            }
          ];
          initrd.systemd.enable = true;
          initrd.systemd.tpm2.enable = true;
          kernelParams = map (policy: "ima_policy=${policy}") cfg.policy;
        };

        environment = {
          etc."ima/ima-policy".text = ''
            measure func=MODULE_CHECK
            measure func=FIRMWARE_CHECK
            measure func=POLICY_CHECK
            measure func=CRITICAL_DATA
          '';

          systemPackages = [ pkgs.ima-evm-utils ];
        };

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
