{
  flake.nixosModules.selinux =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.my.selinux;
    in
    {
      options.my.selinux.enable = lib.mkEnableOption "selinux support";

      config = lib.mkIf cfg.enable {
        boot.kernelPatches = [
          {
            name = "selinux";
            patch = null;
            structuredExtraConfig.SECURITY_SELINUX = lib.kernel.yes;
          }
        ];

        environment = {
          systemPackages = with pkgs; [
            checkpolicy
            e2fsprogs
            libselinux
            policycoreutils
            selinux-python
            setools
            (coreutils-full.override { selinuxSupport = true; })
          ];
          etc = {
            "selinux/config".text = ''
              SELINUX=permissive
              SELINUXTYPE=refpolicy
            '';
            "selinux/semanage.conf".text = ''
              compiler-directory = ${pkgs.policycoreutils}/libexec/selinux/hll

              [load_policy]
              path = ${lib.getExe' pkgs.policycoreutils "load_policy"}
              [end]

              [setfiles]
              path = ${lib.getExe' pkgs.policycoreutils "setfiles"}
              args = -q -c $@ $<
              [end]

              [sefcontext_compile]
              path = ${lib.getExe' pkgs.libselinux "sefcontext_compile"}
              args = -r $@
              [end]
            '';
          };
        };

        security = {
          lsm = [ "selinux" ];
          audit.enable = true;
          auditd.enable = true;
        };

        systemd = {
          package = pkgs.systemd.override { withSelinux = true; };
        };

        system.activationScripts.selinux = {
          deps = [ "etc" ];
          text = ''
            install -d -m0755 /var/lib/selinux
            cmd="${lib.getExe' pkgs.policycoreutils "semodule"} -s refpolicy -i ${pkgs.selinux-refpolicy}/share/selinux/refpolicy/*.pp"
            skipSELinuxActivation=0

            if [ -f /var/lib/selinux/activate-check ]; then
              if [ "$(cat /var/lib/selinux/activate-check)" == "$cmd" ]; then
                skipSELinuxActivation=1
              fi
            fi

            if [ $skipSELinuxActivation -eq 0 ]; then
              eval "$cmd"
              echo "$cmd" >/var/lib/selinux/activate-check
            fi
          '';
        };
      };
    };
}
