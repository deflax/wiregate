#!/usr/bin/env bash

source config

check_root() {
  if [ "$EUID" -ne 0 ]; then
    printf %b\\n "] Please run the script as root."
    exit 1
  fi
}

gen_cidr() {
    base=${1%/*}
    masksize=${1#*/}

    [ $masksize -lt 8 ] && { echo "] Max range is /8."; exit 1;}

    mask=$(( 0xFFFFFFFF << (32 - $masksize) ))

    IFS=. read a b c d <<< $base

    ip=$(( ($b << 16) + ($c << 8) + $d ))

    ipstart=$(( $ip & $mask ))
    ipend=$(( ($ipstart | ~$mask ) & 0x7FFFFFFF ))

    seq $ipstart $ipend | while read i; do
        echo $a.$(( ($i & 0xFF0000) >> 16 )).$(( ($i & 0xFF00) >> 8 )).$(( $i & 0x00FF ))
    done 
}

check_root

# This generates all host address for our vpn subnet but skips the following:
# - vpn server address, which ends with .0.1
# - the network address and the broadcast address
# - all host addresses in between that looks like /24 net and mask, they should work but they are
# misleading in that regard, and we do have enough addresses already
if [ -f $ip_db ]; then
    echo "] IP pool exists at $ip_db. Remove it first."
    exit 1
else
    gen_cidr 10.${net_prefix}.0.0/20 | grep -v \\.0$ | grep -v .255$ | grep -v \\.0\\.1$ > $ip_db
fi
