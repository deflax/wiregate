#!/usr/bin/env bash

source config

check_root() {
    if [ "$EUID" -ne 0 ]; then
        printf %b\\n "] Please run the script as root."
        exit 1
    fi
}

usage()
{
    echo "Usage: peer_disable.sh -p <peer name>"
}

check_root

no_args="true"
while getopts p: option
do
    case $option in
        (p)
            name=${OPTARG};;
        (*)
            usage
            exit;;
    esac
    no_args="false"
done

[[ "$no_args" == "true" ]] && { usage; exit 1; }

# Check if peer config exist
if [ ! -f /etc/wireguard/clients/${name}.info ]; then
    echo "] Peer ${name} does not exists"
    exit 2
fi

#check if config is previously disabled
if [ -f /etc/wireguard/clients/${name}_public.disabled ]; then
    #echo "] ${name} is already disabled."
    exit 0
fi

echo "] Disable wireguard config for ${name}"
wg set wg0 peer $(cat /etc/wireguard/clients/${name}_public.key) remove
mv /etc/wireguard/clients/${name}_public.key /etc/wireguard/clients/${name}_public.disabled

exit 0
