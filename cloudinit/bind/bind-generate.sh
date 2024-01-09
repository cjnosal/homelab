#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_ip=$1
export YTT_cidr_prefix=23
export YTT_forwarders="192.168.3.1;"
export YTT_zone="home.arpa"
export YTT_hostname="bind"

export YTT_reverse_cidr="$(for i in 3 2 1; do cut -z -d'.' -f $i <<< $YTT_ip ; done | tr '\0' '.')" # includes trailing dot
export YTT_reverse_zone=${YTT_reverse_cidr}in-addr.arpa
export YTT_subnet=$(cut -d'.' -f 1-3 <<< $YTT_ip)
export YTT_last=$(cut -d'.' -f 4 <<< $YTT_ip)

write_snippet bind.yml -f ${SCRIPT_DIR}/bind-template.yml