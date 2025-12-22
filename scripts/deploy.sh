#!/bin/sh

HOST=$1
if [ -z "${HOST}" ]; then
    echo "Usage: $0 hostname"
    exit 1
fi

rsync -vrt --delete --delete-excluded nixos/ root@${HOST}:/etc/nixos
ssh root@${HOST} "HOST=${HOST} nixos-rebuild switch -f /etc/nixos/pivot.nix --no-reexec --show-trace"
