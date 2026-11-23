{
  flake.homeModules.pi-coding-agent =
    { pkgs, lib, ... }:
    let
      daemon = pkgs.writers.writePython3Bin "pi-clipboardd" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/clipboard_daemon.py);
    in
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        programs.pi-coding-agent.sandbox.clipboardClient = pkgs.writers.writePython3Bin "wl-copy" {
          libraries = [ pkgs.python3Packages.dbus-next ];
        } (lib.readFile ./pineapplehunter/wrapper/clipboard_client.py);

        systemd.user.services.pi-clipboard = {
          Unit = {
            Description = "Copy text from Pi to the host clipboard";
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "dbus";
            BusName = "io.github.pineapplehunter.LocalClipboard1";
            ExecStart = "${lib.getExe daemon} --wl-copy ${lib.getExe' pkgs.wl-clipboard "wl-copy"}";
          };
        };

        xdg.dataFile."dbus-1/services/io.github.pineapplehunter.LocalClipboard1.service" = {
          text = ''
            [D-BUS Service]
            Name=io.github.pineapplehunter.LocalClipboard1
            Exec=${lib.getExe daemon} --wl-copy ${lib.getExe' pkgs.wl-clipboard "wl-copy"}
            SystemdService=pi-clipboard.service
          '';
        };
      };
    };
}
