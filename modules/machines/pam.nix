# Shared local authentication policy for action and kpro-takata.
# Password authentication (including sudo) renews the per-user 12-hour window.
# Closing any GDM session clears it for that user, including other sessions.
{
  withHowdy ? false,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  pam = config.security.pam.package;
  unix = config.security.pam.pam_unixModulePath;
  helper = pkgs.stdenv.mkDerivation {
    pname = "pam-timeout";
    version = "1";
    src = ./pam-timeout.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -std=c23 -Wall -Wextra -Werror -O2 "$src" -o pam-timeout
    '';
    installPhase = ''
      install -Dm0555 pam-timeout "$out/bin/pam-timeout"
    '';
  };
  exec = "${pam}/lib/security/pam_exec.so";
  permit = "${pam}/lib/security/pam_permit.so";
  unavailable = "${pam}/lib/security/pam_debug.so";
  fingerprint = "${config.services.fprintd.package}/lib/security/pam_fprintd.so";
  howdy = "${config.services.howdy.package}/lib/security/pam_howdy.so";
  command = action: [
    "quiet"
    "seteuid"
    "${helper}/bin/pam-timeout"
    action
  ];

  # WARNING: security.pam.services.<name>.rules and useDefaultRules are
  # experimental and subject to breaking changes without notice. Monitor
  # nixpkgs' PAM module when updating: incompatible changes can lock users
  # out or leave the system open to attackers.
  rules =
    entries:
    lib.listToAttrs (
      lib.imap0 (i: entry: {
        name = entry.name;
        value = (builtins.removeAttrs entry [ "name" ]) // {
          order = 100 + i;
        };
      }) entries
    );
  rule = name: control: modulePath: args: {
    inherit
      name
      control
      modulePath
      args
      ;
  };
  checkRule = name: control: rule name control exec (command "check");
  unavailableRule = name: rule name "requisite" unavailable [ "auth=authinfo_unavail" ];
  authService = entries: {
    useDefaultRules = false;
    rules.auth = rules entries;
  };

  # Only successful Unix-password authentication renews the per-user window.
  # A biometric success must bypass this entire substack.
  passwordRules = [
    (rule "unix" "requisite" unix [ "try_first_pass" ])
    (rule "renew" "optional" exec (command "update"))
    (rule "keyring" "optional" "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so" [ ])
    (rule "permit" "required" permit [ ])
  ];

  # Sequential callers fall back to the password substack on any biometric
  # failure. Jump counts only depend on whether the Howdy rule is present.
  localRules = [
    (checkRule "window-before" "[success=ignore default=${if withHowdy then "3" else "2"}]")
  ]
  ++ lib.optional withHowdy (rule "howdy" "[success=1 default=ignore]" howdy [ ])
  ++ [
    (rule "fingerprint" "[success=ignore default=1]" fingerprint [ ])
    (checkRule "window-after" "[success=1 default=ignore]")
    (rule "password" "substack" "local-password" [ ])
    (rule "permit" "required" permit [ ])
  ];

  # GDM runs biometrics alongside a separate password conversation. An
  # unavailable result must not reset password entry. Each check skips one
  # unavailable-result rule; Howdy success also skips fingerprint itself.
  biometricRules = [
    (checkRule "window-before" "[success=1 default=ignore]")
    (unavailableRule "expired-before")
  ]
  ++ lib.optional withHowdy (rule "howdy" "[success=2 default=ignore]" howdy [ ])
  ++ [
    (rule "fingerprint" "[success=1 default=ignore]" fingerprint [ ])
    (unavailableRule "biometric-unavailable")
    (checkRule "window-after" "[success=1 default=ignore]")
    (unavailableRule "expired-after")
    (rule "permit" "required" permit [ ])
  ];

  loginChecks = [
    (rule "shells" "required" "${pam}/lib/security/pam_shells.so" [ ])
    (rule "nologin" "requisite" "${pam}/lib/security/pam_nologin.so" [ ])
  ];
  gdmChecks = loginChecks ++ [
    (rule "faillock" "requisite" "${pam}/lib/security/pam_faillock.so" [ "preauth" ])
  ];
  serviceAuth =
    checks: stack:
    lib.mkForce (
      rules (
        checks
        ++ [
          (rule "local-policy" "substack" stack [ ])
        ]
      )
    );
  biometricServices = [
    "cups"
    "groupadd"
    "groupmems"
    "polkit-1"
    "su"
    "sudo"
    "sudo-i"
    "systemd-run0"
  ];
  passwordServices = [
    "chfn"
    "chpasswd"
    "chsh"
    "groupdel"
    "groupmod"
    "passwd"
    "useradd"
    "userdel"
    "usermod"
  ];
  localServices = biometricServices ++ passwordServices ++ [ "login" ];
in
{
  # Keep the daemons available without silently enabling biometrics in sshd,
  # systemd-user, su-l, or screen lockers outside this policy's allowlist.
  services.fprintd.enablePam = false;
  security.pam.howdy.enable = false;
  security.pam.enableLegacySettings = false;

  security.pam.services = lib.mkMerge [
    {
      local-password = authService passwordRules;
      local-auth = authService localRules;
      local-biometrics = authService biometricRules;
      login.rules.auth = serviceAuth loginChecks "local-auth";
      gdm-password.rules.auth = serviceAuth loginChecks "local-password";
      gdm-fingerprint.rules.auth = serviceAuth gdmChecks "local-biometrics";
    }
    (lib.genAttrs biometricServices (_: {
      rules.auth = serviceAuth [ ] "local-auth";
    }))
    (lib.genAttrs passwordServices (_: {
      rules.auth = serviceAuth [ ] "local-password";
    }))
    # Do not short-circuit password updates before the keyring has consumed
    # the new token. Keep the remaining upstream password rules and settings.
    (lib.genAttrs localServices (_: {
      rules.password.unix.control = lib.mkForce "requisite";
    }))
    {
      passwd.rules.password.gnome_keyring.enable = lib.mkForce true;
    }
    (lib.genAttrs [ "gdm-password" "gdm-fingerprint" ] (_: {
      rules.session.clear-biometric-window = {
        order = 20000;
        control = "optional";
        modulePath = exec;
        args = command "clear-on-close";
      };
    }))
  ];
}
