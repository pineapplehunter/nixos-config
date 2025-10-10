{
  lib,
  pkgs,
  config,
  ...
}:
{
  security.pam.services =
    let
      inherit (pkgs)
        fprintd
        gnome-keyring
        linux-pam
        systemd
        ;
      # this directory will be wiped on every boot
      stamp-dir = "/var/run/pam-timeout";
      check-timeout = pkgs.writeShellScript "check-timeout.sh" ''
        PATH=${lib.makeBinPath [ pkgs.coreutils ]}
        # FIXME: this uses a plain text file that stores the time of
        # last login.  Check if this is fine with my threat model.
        # Hint for me: I assume no one except me has access to root user.
        if [ -z "$PAM_USER" ]; then
          echo no user is set
          exit 1
        fi
        STAMP_FILE="${stamp-dir}/$PAM_USER/password_login_time"
        MAX_AGE=$((12 * 60 * 60))  # 12 hours

        if [[ ! -f "$STAMP_FILE" ]]; then
          echo no stamp file found
          exit 1  # Require password
        fi

        last_time=$(< "$STAMP_FILE")
        now=$(date +%s)

        if (( now - last_time < MAX_AGE )); then
          exit 0  # OK to use fingerprint
        else
          exit 1  # Too old, force password
        fi
      '';

      update-timeout = pkgs.writeShellScript "update-timeout.sh" ''
        PATH=${lib.makeBinPath [ pkgs.coreutils ]}
        umask 077
        if [ -z "$PAM_USER" ]; then
          echo no user is set
          exit 1
        fi
        STAMP_DIR="${stamp-dir}/$PAM_USER"
        mkdir -p "$STAMP_DIR"
        date +%s > "$STAMP_DIR/password_login_time"
      '';

      # copied from nixpkgs
      # https://github.com/NixOS/nixpkgs/blob/caf5a7d2d10c4cc33d02cf16f540ba79d6ccd004/nixos/modules/security/pam.nix#L1502-L1514
      makeLimitsConf =
        limits:
        pkgs.writeText "limits.conf" (
          lib.concatMapStrings (
            {
              domain,
              type,
              item,
              value,
            }:
            "${domain} ${type} ${item} ${toString value}\n"
          ) limits
        );

      default-rule = ''
        # Account management.
        account required ${linux-pam}/lib/security/pam_unix.so

        # Authentication management.
        # This check introduces timeout on unix login.  It will only
        # allow fingerprint or other means of login it unix has not
        # timed out.  The control flow is created by skipping lines.
        # It calls check-timeout twice to prevent toctou attacks
        # !!! PLEASE CHECK SKIP LINES WHEN MODIFYING !!!
        auth [success=ignore default=2]      ${linux-pam}/lib/security/pam_exec.so quiet seteuid ${check-timeout}
        auth [success=ignore default=1] ${fprintd}/lib/security/pam_fprintd.so
        auth [success=4 default=ignore]      ${linux-pam}/lib/security/pam_exec.so quiet seteuid ${check-timeout}
        auth [success=1 default=ignore]      ${linux-pam}/lib/security/pam_unix.so likeauth nullok try_first_pass
        auth requisite                       ${linux-pam}/lib/security/pam_deny.so
        auth optional                        ${linux-pam}/lib/security/pam_exec.so quiet seteuid ${update-timeout}
        auth optional                        ${gnome-keyring}/lib/security/pam_gnome_keyring.so
        auth requisite                       ${linux-pam}/lib/security/pam_permit.so

        # Password management.
        password sufficient ${linux-pam}/lib/security/pam_unix.so nullok yescrypt
        password optional   ${gnome-keyring}/lib/security/pam_gnome_keyring.so use_authtok

        # Session management.
        session required ${linux-pam}/lib/security/pam_env.so conffile=/etc/pam/environment readenv=0
        session required ${linux-pam}/lib/security/pam_unix.so
        session required ${linux-pam}/lib/security/pam_limits.so conf=${makeLimitsConf config.security.pam.services.login.limits}
      '';
      login-session = ''
        # Session management.
        session required ${linux-pam}/lib/security/pam_loginuid.so
        session required ${linux-pam}/lib/security/pam_lastlog.so silent
        session optional ${systemd}/lib/security/pam_systemd.so
        session optional ${gnome-keyring}/lib/security/pam_gnome_keyring.so auto_start
      '';
      only-unix-rule = ''
        # Authentication management.
        # This check introduces timeout on unix login.  It will only
        # allow fingerprint or other means of login it unix has not
        # timed out.  The control flow is created by skipping lines.
        # It calls check-timeout twice to prevent toctou attacks
        # !!! PLEASE CHECK SKIP LINES WHEN MODIFYING !!!
        auth [success=1 default=ignore] ${linux-pam}/lib/security/pam_unix.so likeauth nullok try_first_pass
        auth requisite                  ${linux-pam}/lib/security/pam_deny.so
        auth optional                   ${linux-pam}/lib/security/pam_exec.so quiet seteuid ${update-timeout}
        auth optional                   ${gnome-keyring}/lib/security/pam_gnome_keyring.so
        auth requisite                  ${linux-pam}/lib/security/pam_permit.so

        account  include default-auth
        password include default-auth
        sesstion include default-auth
      '';
      use-default-rule = ''
        auth      substack      default-auth
        account   include       default-auth
        password  substack      default-auth
        session   include       default-auth
      '';
      use-default-with-login-rule = ''
        auth      substack      default-auth
        account   include       default-auth
        password  substack      default-auth
        session   include       default-auth
        session   include       default-with-login
      '';
      use-only-unix-rule = ''
        auth      substack      only-unix-auth
        account   include       only-unix-auth
        password  substack      only-unix-auth
        session   include       only-unix-auth
      '';
    in
    {
      default-auth.text = default-rule;
      default-with-login.text = login-session;
      only-unix-auth.text = only-unix-rule;

      chfn.text = lib.mkForce use-only-unix-rule;
      chpasswd.text = lib.mkForce use-only-unix-rule;
      chsh.text = lib.mkForce use-only-unix-rule;
      cups.text = lib.mkForce use-default-rule;
      gdm-fingerprint.enable = lib.mkForce false;
      gdm-password.text = lib.mkForce use-default-with-login-rule;
      groupadd.text = lib.mkForce use-default-rule;
      groupdel.text = lib.mkForce use-only-unix-rule;
      groupmems.text = lib.mkForce use-default-rule;
      groupmod.text = lib.mkForce use-only-unix-rule;
      login.text = lib.mkForce use-default-with-login-rule;
      passwd.text = lib.mkForce use-only-unix-rule;
      polkit-1.text = lib.mkForce use-default-rule;
      su.text = lib.mkForce use-default-rule;
      sudo-i.text = lib.mkForce use-default-rule;
      sudo.text = lib.mkForce use-default-rule;
      systemd-run0.text = lib.mkForce use-default-rule;
      useradd.text = lib.mkForce use-default-rule;
      userdel.text = lib.mkForce use-only-unix-rule;
      usermod.text = lib.mkForce use-only-unix-rule;
    };
}
