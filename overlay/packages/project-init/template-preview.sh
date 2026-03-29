REPO=${REPO:-github:pineapplehunter/nixos-config}
TEMPLATE_PATH=$(nix eval "$REPO#templates.$1.path" --raw --quiet)
bat --plain --color=always "$TEMPLATE_PATH/flake.nix"
