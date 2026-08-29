{
  flake.nixosModules.captive =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.captive.tailescale;
      dispatcherScript = pkgs.writeShellScript "tailscale-nm-dns" ''
        ACTION="$2"

        [ "$ACTION" = "connectivity-change" ] || exit 0

        case "$CONNECTIVITY_STATE" in
            FULL|full)
                ${pkgs.util-linux}/bin/logger -t tailscale-nm-dns \
                    "NetworkManager connectivity FULL; enabling Tailscale DNS"

                ${config.services.tailscale.package}/bin/tailscale set --accept-dns=true
                ;;

            *)
                ${pkgs.util-linux}/bin/logger -t tailscale-nm-dns \
                    "NetworkManager connectivity $CONNECTIVITY_STATE; disabling Tailscale DNS"

                ${config.services.tailscale.package}/bin/tailscale set --accept-dns=false
                ;;
        esac

        exit 0
      '';
    in
    {
      options.my.captive.tailescale.enable =
        lib.mkEnableOption "Tailscale DNS handling for NetworkManager captive portals";

      config = lib.mkIf cfg.enable {
        networking.networkmanager = {
          dispatcherScripts = [ { source = dispatcherScript; } ];
          settings = {
            connectivity = {
              enabled = true;
              uri = "http://firefox-portal-detection.com/generate_204";
              response = "";
              interval = 30;
              timeout = 5;
            };
          };
        };
      };
    };
}
