    \ \        /_)           ___|       |        
     \ \  \   /  |  __| _ \ |      _` | __|  _ \ 
      \ \  \ /   | |    __/ |   | (   | |    __/ 
       \_/\_/   _|_|  \___|\____|\__,_|\__|\___| 


Wireguard based VPN server endpoint with LDAP support

Tested on Debian 12 bookworm

# Server Commands

./init.sh - setup system services (wireguard, unbound, iptables, sysctl)

./peer_add.sh - define new peer for a new remote device. generates config and QR code inside /etc/wireguard/clients

./peer_del.sh - delete a peer and salvage its ip address back to the ip pool

./peer_addall.sh - recreates wireguard state using existing clients in /etc/wireguard/clients dir

./peer_mail.sh - send the generated profile to the client and remove the sensitive data from server

# Server Tools

./wgstats.sh - show peer stats similar based on wg show all dump

./wgldap.sh - tail the log of the wgldapsync service

# Client Side Tools

./client-tools/wg-rapid - modified wireguard client based on wg-quick that works with systemd-resolv

./client-tools/startvpn.desktop - shortcut for wg-rapid. update the parameter with peer filename
