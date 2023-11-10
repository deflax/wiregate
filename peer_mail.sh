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
    echo "Usage: peer_mail.sh -p <peer name>"
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

email_client=$(cat /etc/wireguard/clients/${name}.info | grep "^email=" | cut -d '=' -f 2)

if [ -z ${email_client} ]; then
    echo "] Peer not found."
    exit 2
fi

echo "] Sending the profile data to $email_destination"
# strip non alphanumeric characters from peer name
stname=$(echo ${name} | sed "s/[^[:alnum:]-]//g")

# fill profile tmp dir with data
mkdir payload
mkdir payload/mobile
cp -v /etc/wireguard/clients/${name}_wg0.conf payload/profile.conf
cp -v /etc/wireguard/clients/${name}_alltraffic_wg0.conf payload/profile_alltraffic.conf
cp -v /etc/wireguard/clients/${name}_alltraffic_qr.png payload/mobile/profile_alltraffic_QR.png

mkdir payload/linux
cp -v client-tools/wg-rapid payload/linux/wg-rapid
cp -v client-tools/startvpn.desktop payload/linux/startvpn.desktop
chmod +x payload/linux/startvpn.desktop

# pack the attachment
cd payload
zip -r ../payload.zip .
cd ..
mv payload.zip ${stname}_profile.zip

# sent the message
mutt -s "WireGate VPN for ${email_client}" ${email_destination} -a ${stname}_profile.zip < mail.md
#mutt -s "WireGate VPN for ${email_client}" ${email_client} -a ${stname}_profile.zip < mail.md

rm -f -r -v payload

exit 0
