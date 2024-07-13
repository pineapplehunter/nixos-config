{ pkgs
, lib
, config
, inputs
, ...
}:
let
  ibus-engines-patch = inputs.nixpkgs-pineapplehunter.legacyPackages.x86_64-linux.ibus-engines;
in
{
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji
  ];

  # japanese input managers
  i18n.inputMethod = {
    ibus.engines = with pkgs.ibus-engines; [
      mozc-ut
      anthy
    ];
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-anthy
    ];
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = lib.mkDefault "jp";
    variant = lib.mkDefault "";
  };

  # Configure console keymap
  console.keyMap = lib.mkDefault "jp106";

  # Set your time zone.
  time.timeZone = lib.mkDefault "Asia/Tokyo";

  # Select internationalisation properties.
  i18n.defaultLocale = lib.mkDefault "ja_JP.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = lib.mkDefault "ja_JP.UTF-8";
    LC_IDENTIFICATION = lib.mkDefault "ja_JP.UTF-8";
    LC_MEASUREMENT = lib.mkDefault "ja_JP.UTF-8";
    LC_MONETARY = lib.mkDefault "ja_JP.UTF-8";
    LC_NAME = lib.mkDefault "ja_JP.UTF-8";
    LC_NUMERIC = lib.mkDefault "ja_JP.UTF-8";
    LC_PAPER = lib.mkDefault "ja_JP.UTF-8";
    LC_TELEPHONE = lib.mkDefault "ja_JP.UTF-8";
    LC_TIME = lib.mkDefault "ja_JP.UTF-8";
  };

  nixpkgs.overlays =
    let
      ibus-version-overlay = final: prev: {
        ibus =
          if prev.ibus.version == "1.5.29" then
            prev.ibus.overrideAttrs
              rec {
                version = "1.5.30";
                src = prev.fetchFromGitHub {
                  owner = "ibus";
                  repo = "ibus";
                  rev = version;
                  hash = "sha256-VgSjeKF9DCkDfE9lHEaWpgZb6ibdgoDf/I6qeJf8Ah4=";
                };
              }
          else
            prev.ibus;

        ibus-engines = prev.ibus-engines // {
          inherit (ibus-engines-patch) mozc mozc-ut;
        };
      };
    in
    lib.optionals (config.i18n.inputMethod.enabled == "ibus") [ ibus-version-overlay ];
}
