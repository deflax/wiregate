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
    echo "Usage: peer_add.sh -p <peer name> -e <email address>"
}

random_ip_pickup() {
    # Randomly select an IP and remove it from the pool
    local ipsleft=`cat ${ip_db} | wc -l`
    if [[ "${ipsleft}" -eq 0 ]]; then
	echo "empty"
    else
        local random_ip=$(shuf -n 1 ${ip_db})
        grep -v "${random_ip}$" ${ip_db} > ${ip_db}.tmp
        mv ${ip_db}.tmp ${ip_db}
        echo "${random_ip}"
    fi
}

check_root

no_args="true"
while getopts p:e: option
do
    case $option in
        (p)
            name=${OPTARG};;
        (e)
            email=${OPTARG};;
        (*)
            usage
            exit;;
    esac
    no_args="false"
done

[[ "$no_args" == "true" ]] && { usage; exit 1; }

# Check if IP pool exist
if [ ! -f ${ip_db} ]; then
    echo "] IP pool does not exists at ${ip_db}. Generate it first."
    exit 3
fi

# Check if both arguments exist
if [ -z ${name} ] || [ -z ${email} ]; then
    echo "] Not enough arguments"
    exit 1 
fi

# Check if peer config exist
if [ -f /etc/wireguard/clients/${name}_public.key ]; then
    peer_exists_in_wg=$(wg show wg0 dump | grep $(cat /etc/wireguard/clients/${name}_public.key) | wc -l)
    if [ ! ${peer_exists_in_wg} -eq 0 ]; then
        #echo "] ${name} already activated"
        exit 2
    fi
fi

# Generate wireguard peer keys and config
if [ -z ${server_endpoint_address} ]; then
    server_endpoint_address=$(ip addr show ${public_ifname} | grep -o "inet [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*")
fi

# Creating clients subdir
mkdir -p /etc/wireguard/clients

if [ ! -f /etc/wireguard/clients/${name}.info ]; then
    echo "] ${name} config will be generated."
    peer_address_from_pool=$(random_ip_pickup)
    if [ ${peer_address_from_pool} = "empty" ]; then
        echo "] IP Pool is empty"
        exit 5
    fi

    bash -c "cat > /etc/wireguard/clients/${name}_wg0.conf" << ENDOFFILE
[Interface]
PrivateKey = client_private_key
Address = selected_peer_address/32
DNS = 10.net_prefix.0.1

[Peer]
PublicKey = server_public_key
Endpoint = server_endpoint:550net_prefix
# Route only vpn trafic through vpn
AllowedIPs = 10.net_prefix.0.0/20, allowed_routes
# Route ALL traffic through vpn
#AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 21
ENDOFFILE

    bash -c "cat > /etc/wireguard/clients/${name}_alltraffic_wg0.conf" << ENDOFFILE
[Interface]
PrivateKey = client_private_key
Address = selected_peer_address/32
DNS = 10.net_prefix.0.1

[Peer]
PublicKey = server_public_key
Endpoint = server_endpoint:550net_prefix
# Route only vpn trafic through vpn
#AllowedIPs = 10.net_prefix.0.0/20, allowed_routes
# Route ALL traffic through vpn
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 21
ENDOFFILE

    cat << EOF | bash
cd /etc/wireguard/clients
umask 077
[ ! -f ${name}_private.key ] && wg genkey | tee ${name}_private.key | wg pubkey > ${name}_public.key
EOF

    sed -i "s/net_prefix/${net_prefix}/g" /etc/wireguard/clients/${name}_wg0.conf
    sed -i "s#allowed_routes#${allowed_routes}#g" /etc/wireguard/clients/${name}_wg0.conf
    sed -i "s/selected_peer_address/${peer_address_from_pool}/g" /etc/wireguard/clients/${name}_wg0.conf
    sed -i "s/server_endpoint/${server_endpoint_address}/g" /etc/wireguard/clients/${name}_wg0.conf
    sed -i "s/server_public_key/$(sed 's:/:\\/:g' /etc/wireguard/server_public.key)/" /etc/wireguard/clients/${name}_wg0.conf
    sed -i "s/client_private_key/$(sed 's:/:\\/:g' /etc/wireguard/clients/${name}_private.key)/" /etc/wireguard/clients/${name}_wg0.conf

    sed -i "s/net_prefix/${net_prefix}/g" /etc/wireguard/clients/${name}_alltraffic_wg0.conf
    sed -i "s#allowed_routes#${allowed_routes}#g" /etc/wireguard/clients/${name}_alltraffic_wg0.conf
    sed -i "s/selected_peer_address/${peer_address_from_pool}/g" /etc/wireguard/clients/${name}_alltraffic_wg0.conf
    sed -i "s/server_endpoint/${server_endpoint_address}/g" /etc/wireguard/clients/${name}_alltraffic_wg0.conf
    sed -i "s/server_public_key/$(sed 's:/:\\/:g' /etc/wireguard/server_public.key)/" /etc/wireguard/clients/${name}_alltraffic_wg0.conf
    sed -i "s/client_private_key/$(sed 's:/:\\/:g' /etc/wireguard/clients/${name}_private.key)/" /etc/wireguard/clients/${name}_alltraffic_wg0.conf
    qrencode -t PNG -o /etc/wireguard/clients/${name}_alltraffic_qr.png < /etc/wireguard/clients/${name}_alltraffic_wg0.conf

    echo "peer=${name}" > /etc/wireguard/clients/${name}.info
    echo "email=${email}" >> /etc/wireguard/clients/${name}.info
    echo "ip=${peer_address_from_pool}" >> /etc/wireguard/clients/${name}.info
    peer_ip=$(cat /etc/wireguard/clients/${name}.info | grep "^ip=" | cut -d '=' -f 2)

    #send mail with the generated config
    bash -c "./peer_mail.sh -p ${name}"
else
    echo "] ${name} config already exists."
    peer_ip=$(cat /etc/wireguard/clients/${name}.info | grep "^ip=" | cut -d '=' -f 2)

    #check if private key was previously disabled
    if [ -f /etc/wireguard/clients/${name}_public.disabled ]; then
        echo "] ${name} was previously disabled."
	mv /etc/wireguard/clients/${name}_public.disabled /etc/wireguard/clients/${name}_public.key
    fi

    #check if peer ip already exist in the database
    ip_exists_in_pool=$(grep "${peer_ip}$" ${ip_db} | wc -l)
    if [ ${ip_exists_in_pool} -eq 1 ]; then
        echo "] ${peer_ip} exists in pool. Removing to avoid duplicates."
        grep -v "${peer_ip}$" ${ip_db} > ${ip_db}.tmp
        mv ${ip_db}.tmp ${ip_db}
    fi
fi

echo "] ${name} (${email}) config set. Endpoint address is ${server_endpoint_address}. Selected user VPN IP is ${peer_ip}"
wg set wg0 peer $(cat /etc/wireguard/clients/${name}_public.key) allowed-ips ${peer_ip}/32 persistent-keepalive 21

