{
  flake.homeModules.cradsec =
    { config, ... }:
    {
      programs.ssh = {
        enable = true;
        settings = {
          cradsec-sgx = {
            hostname = "10.102.51.25";
            user = "takata";
            identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
          };
          cradsec-tdx = {
            hostname = "10.102.51.31";
            user = "takata";
            identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
          };
          cradsec-sgx-tailscale = {
            hostname = "cradsec-sgx-machine.tail9ccf68.ts.net";
            user = "takata";
            identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
          };
          cradsec-tdx-tailscale = {
            hostname = "cradsec-tdx-machine.tail9ccf68.ts.net";
            user = "takata";
            identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
          };
          cradsec-riscv-tailscale = {
            hostname = "ubuntu.tail9ccf68.ts.net";
            user = "takata";
            identityFile = "${config.home.homeDirectory}/.ssh/cradsec_takata";
          };
        };
      };
    };
}
