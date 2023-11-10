#!/bin/bash

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "] WireGate plugins:"
systemctl list-timers --all | grep 'ACTIVATES\|wgldapsync'
echo ""

echo "] WireGate peers:"
tmpfile1=$(mktemp /tmp/wgstats.1.XXXXXX)
tmpfile2=$(mktemp /tmp/wgstats.2.XXXXXX)

ALLPEERS=$(wg show all dump | grep -v off)

echo "$ALLPEERS" | while IFS= read -r peer ; do
	peerkey=$(echo "$peer" | cut -d $'\t' -f 2)
	peerfile=$(basename $(grep -l "${peerkey}" /etc/wireguard/clients/*_public.key))
	peername=$(echo ${peerfile} | cut -d '_' -f 1)
	clientip=$(echo "$peer" | cut -d $'\t' -f 4)
	peerip=$(echo "$peer" | cut -d $'\t' -f 5)
	peerlatesths=$(echo "$peer" | cut -d $'\t' -f 6)
	if [ ${peerlatesths} -eq 0 ]; then
		peerlatesthsfmt="Never"
	else
		peerlatesthsfmt=$(date -d@${peerlatesths})
	fi
	peerrx=$(echo "$peer" | cut -d $'\t' -f 7 | numfmt --to=iec-i --suffix=B)
	peertx=$(echo "$peer" | cut -d $'\t' -f 8 | numfmt --to=iec-i --suffix=B)
	echo "${peerlatesths},$peername,$clientip,$peerip,${peerlatesthsfmt},$peerrx,$peertx" >> $tmpfile1
done

sort -k1 -n -t "," $tmpfile1 | cut -d "," -f 2- > $tmpfile2
sed -i '1s/^/Peer,Client Address,Peer Address,Latest Handshake,Data Recieved,Data Sent\n/' $tmpfile2
column -e -t -s "," $tmpfile2

rm $tmpfile1
rm $tmpfile2
exit 0
