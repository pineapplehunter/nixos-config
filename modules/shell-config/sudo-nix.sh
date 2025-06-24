#!/usr/bin/env bash

CMD=$1
shift
sudo $(@which-nix@ $CMD) "$@"
