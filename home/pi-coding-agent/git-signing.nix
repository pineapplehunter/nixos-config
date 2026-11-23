{
  flake.homeModules.pi-coding-agent =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      gitUser = config.programs.git.settings.user;
      gitPublicKey = config.programs.git.signing.key;
      client = pkgs.writers.writePython3Bin "pi-git-sign" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/git_sign_client.py);
      daemon = pkgs.writers.writePython3Bin "pi-git-signingd" {
        libraries = [ pkgs.python3Packages.dbus-next ];
      } (lib.readFile ./pineapplehunter/wrapper/git_sign_daemon.py);
    in
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        programs.pi-coding-agent.sandbox = {
          gitSigningClient = client;
          gitConfig = (pkgs.formats.gitIni { }).generate "pi-gitconfig" {
            user = {
              inherit (gitUser) name email;
              # Git requires a key selector; only the host broker chooses the key.
              signingKey = "pi-host-signer";
            };
            commit.gpgSign = true;
            gpg = {
              format = "ssh";
              ssh.program = lib.getExe client;
            };
          };
        };

        assertions = [
          {
            assertion = config.programs.git.signing.format == "ssh" && lib.hasSuffix ".pub" gitPublicKey;
            message = "Pi's host signer requires an SSH public signing key (*.pub).";
          }
        ];

        systemd.user.services.pi-git-signing = {
          Unit.Description = "Sign attributed Pi commits with the host SSH key";
          Service = {
            Type = "dbus";
            BusName = "io.github.pineapplehunter.GitSign1";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe daemon)
              "--ssh-keygen"
              (lib.getExe' pkgs.openssh "ssh-keygen")
              "--key"
              gitPublicKey
              "--name"
              gitUser.name
              "--email"
              gitUser.email
            ];
          };
        };

        xdg.dataFile."dbus-1/services/io.github.pineapplehunter.GitSign1.service".text = ''
          [D-BUS Service]
          Name=io.github.pineapplehunter.GitSign1
          Exec=${lib.getExe daemon} --ssh-keygen ${lib.getExe' pkgs.openssh "ssh-keygen"} --key ${lib.escapeShellArg gitPublicKey} --name ${lib.escapeShellArg gitUser.name} --email ${lib.escapeShellArg gitUser.email}
          SystemdService=pi-git-signing.service
        '';
      };
    };
}
