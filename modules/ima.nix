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
          kernelPatches = [
            {
              name = "builtin-crypto";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                # IMA initializes before modules are measured, so its crypto
                # dependencies must be available without module loading.
                CRYPTO = yes;
                CRYPTO_ALGAPI = yes;
                CRYPTO_HASH = yes;
                CRYPTO_HASH_INFO = yes;
                CRYPTO_HMAC = yes;
                CRYPTO_MANAGER = yes;
                CRYPTO_SHA1 = yes;
                CRYPTO_SHA256 = yes;

                # Used by the asymmetric-key path that NixOS enables for IMA.
                CRYPTO_AKCIPHER = yes;
                CRYPTO_RSA = yes;
                CRYPTO_SIG = yes;
              };
            }
          ];
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
