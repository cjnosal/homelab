#!/usr/bin/env bash
set -euo pipefail

HOST=$1
IP=$2

source /usr/local/include/bind.env

sudo nsupdate -l -4 <<EOF
zone $ZONE
update delete ${HOST}.${ZONE}
send
EOF

named-checkzone ${ZONE} /var/lib/bind/forward.${ZONE}

if ! grep -q '*' <<< $HOST
then
  segment=$(cut -d'.' -f4 <<< "$IP")

  sudo nsupdate -l -4 <<EOF
zone $REV_ZONE
update delete ${segment}.${REV_ZONE}
send
EOF
  named-checkzone ${REV_ZONE} /var/lib/bind/reverse.${ZONE}
fi