{
  flake.overlays.mozc-dictionaries =
    final: prev:
    let
      inherit (prev) lib;

      # Backport the UT dictionary updates from nixpkgs PR #570751, commit
      # 4ae816f6146d107b85afd9906e62aefce83edd18. The new merger in our split Mozc
      # package needs the upstream .txt.bz2 files rather than legacy tar archives.
      # https://github.com/NixOS/nixpkgs/pull/570751
      # Remove these overrides once the pinned nixpkgs includes equivalent updates.
      dictionaries = {
        mozcdic-ut-alt-cannadic = {
          version = "0-unstable-2026-09-05";
          rev = "e7230d7f6d9b72cb656a1eb23d2ccdb7c70d141f";
          hash = "sha256-1+JjR8rAKtOa2lhMH3m8GKIz3UC8U7XVWelgXXn7310=";
        };
        mozcdic-ut-edict2 = {
          version = "0-unstable-2026-07-08";
          rev = "8fe8f7918baf513c3d7e243807dfcda2d5c30139";
          hash = "sha256-YCxAmNmHVfGS1VxExK5FWQOA/SXBNuamU9yIWmfN9VU=";
        };
        mozcdic-ut-jawiki = {
          version = "0-unstable-2026-10-02";
          rev = "57af6adefedab262c295c4bfff71a89902cbe05c";
          hash = "sha256-UFyk0rjp+G4zGIdQy+qemg8K86XJH7WU0LcPBZbk/5I=";
        };
        mozcdic-ut-neologd = {
          version = "0-unstable-2026-04-19";
          rev = "d8307abf02b830b185c9320822cffa0d0787c54e";
          hash = "sha256-N00QZ9p5loD/ld6D1BB85tK/rvarRylWVCJqpnz47Ck=";
        };
        mozcdic-ut-personal-names = {
          version = "0-unstable-2026-10-02";
          rev = "b557dd4c1548cc7c2164d5f8b14170c40cbb6f81";
          hash = "sha256-/Qwt6WvNR6EVYpMXcmEpdORa39mksllI/6oVDahgAVE=";
        };
        mozcdic-ut-place-names = {
          version = "0-unstable-2026-10-02";
          rev = "98cf8e9d7731695a52e5bc72ed633933c71d1913";
          hash = "sha256-NIeV5iSTSJE867VqtUlcbyegMHpszFuZwOkHQlhJdhM=";
        };
        mozcdic-ut-skk-jisyo = {
          version = "0-unstable-2026-04-19";
          rev = "7c02e535bd6d999a715a53b58c3366f2401bfb7f";
          hash = "sha256-Ew8mzdhQHzCHSkwo9HzPKduSPrH0BZx/YNEsoOPLe3I=";
        };
        mozcdic-ut-sudachidict = {
          version = "0-unstable-2026-07-24";
          rev = "c686771bada1d59e9b105c81b29e6ac1a239cb54";
          hash = "sha256-UjntnOfSxit22ZyVtzi6znB0C2JfErw+8MAwvg5cyV4=";
        };
      };
    in
    lib.mapAttrs (
      name: source:
      prev.${name}.overrideAttrs (old: {
        inherit (source) version;
        src = final.fetchFromGitHub {
          owner = "utuhiro78";
          repo = name;
          inherit (source) rev hash;
        };
        installPhase = ''
          runHook preInstall
          install -Dt $out ${name}.txt.bz2
          runHook postInstall
        '';
        meta = removeAttrs old.meta [ "hydraPlatforms" ];
      })
    ) dictionaries
    // {
      # Match the PR's Hydra metadata changes without updating these data sources.
      jawiki-all-titles-in-ns0 = prev.jawiki-all-titles-in-ns0.overrideAttrs (old: {
        meta = removeAttrs old.meta [ "hydraPlatforms" ];
      });
      jp-zip-codes = prev.jp-zip-codes.overrideAttrs (old: {
        meta = removeAttrs old.meta [ "hydraPlatforms" ];
      });
    };
}
