#!/usr/bin/env @shell@

CMD=$1
shift
sudo $(@which-nix@ $CMD) "$@"
