#!/bin/bash

ALLCLIENTS=/etc/wireguard/clients/*.info

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for client in $ALLCLIENTS; do
    peer=$(cat ${client} | grep '^peer=' | cut -d '=' -f 2)
    email=$(cat ${client} | grep '^email=' | cut -d '=' -f 2)
    echo "] peer_add.sh - peer: $peer - email: $email"
    bash ${__dir}/peer_add.sh -p ${peer} -e ${email}
done
