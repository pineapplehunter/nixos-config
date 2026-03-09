green(){
  echo -e "\e[32m$*\e[0m"
}

red(){
  echo -e "\e[31m$*\e[0m"
}

any-error () {
  red Some error occured while initializing project
}

trap any-error EXIT

REPO=github:pineapplehunter/nixos-config
TYPE=$(nix flake show "$REPO" --json --quiet --quiet | jq '.templates | keys[]' -r | fzf)

green initialilizing project in "$(pwd)"
git init
nix flake init -t "$REPO#$TYPE"
git add .
direnv allow

# reset trap
trap - EXIT
green Successfully initialized project