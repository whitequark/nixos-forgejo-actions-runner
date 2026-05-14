#!/bin/sh
set -e

HOST=$1
IP=$2
if [ -z "${HOST}" ]; then
    echo "Usage: $0 hostname [ip]"
    exit 1
fi

rsync -vrt --delete-excluded -f "+ site/${HOST}.toml" -f "- site/*" nixos/ root@${IP:-HOST}:/etc/nixos
ssh root@${IP:-HOST} "HOST=${HOST} nixos-rebuild switch -f /etc/nixos/pivot.nix --no-reexec --show-trace"
