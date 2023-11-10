#!/usr/bin/env bash

if [ ! -f config ]; then
    echo "] Create a config file based on config.dist"
    exit 1
fi

source config

check_root() {
  if [ "$EUID" -ne 0 ]; then
    printf %b\\n "] Please run the script as root."
    exit 1
  fi
}

# Welcome
echo ""
cat README.md
echo ""

check_root

# enable IPv4 forwarding
sed -i 's/\#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf

# negate the need to reboot after the above change
sysctl -p

# update/upgrade server and refresh repo
apt update -y && apt upgrade -y && apt autoremove -y

# remove the default firewall
ufw disable
apt remove --purge ufw -y
apt install iptables netfilter-persistent -y

# install fail2ban
apt install fail2ban -y

# install python-ldap
apt install python3-dev python3-pip python3-ldap -y

# install wireguard
systemctl stop wg-quick@wg0.service
systemctl disable wg-quick@wg0.service
apt install wireguard -y
apt install qrencode -y

# install jq
apt install jq -y

# install curl
apt install curl -y

# create Wireguard interface config
bash -c "cat > /etc/wireguard/wg0.conf" << ENDOFFILE
[Interface]
PrivateKey = server_private_key
Address = 10.net_prefix.0.1/20
ListenPort = 550net_prefix

PostUp = iptables -A FORWARD -i ${public_ifname} -o wg0 -j ACCEPT; iptables -A FORWARD -i wg0 -o ${public_ifname} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o ${public_ifname} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${public_ifname} -o wg0 -j ACCEPT; iptables -D FORWARD -i wg0 -o ${public_ifname} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o ${public_ifname} -j MASQUERADE
SaveConfig = true
ENDOFFILE

cat << EOF | bash
cd /etc/wireguard/
umask 077
[ ! -f server_private.key ] && wg genkey | tee server_private.key | wg pubkey > server_public.key
EOF
sed -i "s/net_prefix/${net_prefix}/g" /etc/wireguard/wg0.conf
sed -i "s/server_private_key/$(sed 's:/:\\/:g' /etc/wireguard/server_private.key)/" /etc/wireguard/wg0.conf

# make root owner of the Wireguard config file
chown -v root:root /etc/wireguard/wg0.conf
chmod -v 600 /etc/wireguard/wg0.conf

# make Wireguard interface start at boot
systemctl enable wg-quick@wg0.service


# flush all chains
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
# delete all chains
iptables -X

# configure the firewall and make it persistent
DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y
systemctl enable netfilter-persistent
iptables -P INPUT DROP
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p all -s localhost -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 655 -j ACCEPT
iptables -A INPUT -p udp --dport 655 -j ACCEPT
iptables -A INPUT -p tcp -s ${monitor_host} --dport 10050 -j ACCEPT
iptables -A INPUT -p udp --dport 550${net_prefix} -j ACCEPT
iptables -A INPUT -p all -i wg0 -j ACCEPT
iptables -P FORWARD ACCEPT
iptables -A FORWARD -i wg0 -o wg0 -j REJECT
iptables -P OUTPUT ACCEPT
netfilter-persistent save

# install Unbound DNS
systemctl stop unbound.service
systemctl disable unbound.service
apt install unbound unbound-host -y

# download list of DNS root servers
curl -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.cache

# create unbound log file
mkdir -p /var/log/unbound
chown unbound:unbound /var/log/unbound/
touch /var/log/unbound/unbound.log
chown unbound:unbound /var/log/unbound/unbound.log

echo "/var/log/unbound/unbound.log rw," > /etc/apparmor.d/local/usr.sbin.unbound
apparmor_parser -r /etc/apparmor.d/usr.sbin.unbound

# create custom conf
touch /etc/unbound/custom.conf
chown unbound:unbound /etc/unbound/custom.conf

# create Unbound config file
bash -c "cat > /etc/unbound/unbound.conf" << ENDOFFILE
server:
    num-threads: 4

    # enable logs
    verbosity: 1
    logfile: /var/log/unbound/unbound.log
    chroot: ""
    log-queries: yes

    # list of root DNS servers
    root-hints: "/var/lib/unbound/root.hints"

    # use the root server's key for DNSSEC
    auto-trust-anchor-file: "/var/lib/unbound/root.key"

    # respond to DNS requests on all interfaces
    interface: 0.0.0.0
    max-udp-size: 3072

    # IPs authorised to access the DNS Server
    access-control: 0.0.0.0/0                 refuse
    access-control: 127.0.0.1                 allow
    access-control: 10.net_prefix.0.0/20              allow

    # not allowed to be returned for public Internet  names
    private-address: 10.net_prefix.0.0/20

    #hide DNS Server info
    hide-identity: yes
    hide-version: yes

    # limit DNS fraud and use DNSSEC
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes

    # add an unwanted reply threshold to clean the cache and avoid, when possible, DNS poisoning
    unwanted-reply-threshold: 10000000

    # have the validator print validation failures to the log
    val-log-level: 1

    # minimum lifetime of cache entries in seconds
    cache-min-ttl: 1800

    # maximum lifetime of cached entries in seconds
    cache-max-ttl: 14400
    prefetch: yes
    prefetch-key: yes

    # additional entries
    include: /etc/unbound/custom.conf
ENDOFFILE

sed -i "s/net_prefix/${net_prefix}/g" /etc/unbound/unbound.conf

# give root ownership of the Unbound config
chown -R unbound:unbound /var/lib/unbound

# enable Unbound in place of systemd-resovled
systemctl enable unbound-resolvconf
systemctl enable unbound
systemctl start unbound

# disable systemd-resolved
systemctl stop systemd-resolved
systemctl disable systemd-resolved
unlink /etc/resolv.conf
bash -c "cat > /etc/resolv.conf" << ENDOFFILE
nameserver 127.0.0.1
ENDOFFILE

# Initial database generation
bash -c "./gen-ip-database.sh"

#provide scripts in /usr/local/bin
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -v ${__dir}/wgstats.sh /usr/local/bin/
cp -v ${__dir}/wgldap.sh /usr/local/bin/

#install Postfix mailserver
if [ $email_origin == "wire.example.com" ]; then
    echo "] WARN: Mailing is disabled!"
else
    echo "] Setting up mail server $email_origin ..."
    if [ ! -f /etc/postfix/main.cf ]; then
        echo "] Mail server config does not exist. Installing..."

        # install postfix
        echo "postfix postfix/mailname string ${email_origin}" | debconf-set-selections
        echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
        apt install -y postfix mailutils libsasl2-2 ca-certificates libsasl2-modules mutt zip

        # setup mail server for email reports
        /usr/sbin/postconf -e "relayhost = [${email_host}]:587" \
        "smtp_sasl_auth_enable = yes" \
        "smtp_sasl_security_options = noanonymous" \
        "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd" \
        "smtp_use_tls = yes" \
        "smtp_tls_security_level = encrypt" \
        "smtp_tls_note_starttls_offer = yes"
        echo "[${email_host}]:587 ${email_user}:${email_pass}" > /etc/postfix/sasl_passwd
        /usr/sbin/postmap hash:/etc/postfix/sasl_passwd
        chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
        chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
        /usr/sbin/postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
        /usr/sbin/postconf -e "myorigin = ${email_origin}"
        sleep 2
        service postfix restart
    fi
fi

# Setup LDAP sync service
if [ $ldap_server == "ldap://idm.example.com" ]; then
    echo "] WARN: LDAP disabled!"
else
    echo "] Setting up LDAP server $ldap_server"
    cp -v ${__dir}/wgldapsync.service /etc/systemd/system/wgldapsync.service
    cp -v ${__dir}/wgldapsync.timer /etc/systemd/system/wgldapsync.timer
    systemctl daemon-reload
    systemctl enable wgldapsync.timer
    systemctl status wgldapsync.service
    systemctl status wgldapsync.timer
fi

# reboot to make changes effective
echo "] System reboot after 30 seconds..."
sleep 30
reboot
