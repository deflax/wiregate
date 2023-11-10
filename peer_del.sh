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
    echo "Usage: peer_del.sh -p <peer name>"
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

echo "] Removing wireguard config for ${name}"
salvaged_ip=$(cat /etc/wireguard/clients/${name}.info | grep "^ip=" | cut -d '=' -f 2)
echo "] Salvaged IP is ${salvaged_ip} and will be returned back to ${ip_db}"
echo ${salvaged_ip} >> ${ip_db}

#check if config is previously disabled
if [ -f /etc/wireguard/clients/${name}_public.disabled ]; then
    echo "] ${name} was previously disabled."
    mv /etc/wireguard/clients/${name}_public.disabled /etc/wireguard/clients/${name}_public.key
fi

wg set wg0 peer $(cat /etc/wireguard/clients/${name}_public.key) remove
rm /etc/wireguard/clients/${name}_public.key
rm /etc/wireguard/clients/${name}.info

# remove additional sensitive info
rm -f /etc/wireguard/clients/${name}_wg0.conf
rm -f /etc/wireguard/clients/${name}_qr.png
rm -f /etc/wireguard/clients/${name}_alltraffic_wg0.conf
rm -f /etc/wireguard/clients/${name}_alltraffic_qr.png
rm -f /etc/wireguard/clients/${name}_private.key

exit 0
