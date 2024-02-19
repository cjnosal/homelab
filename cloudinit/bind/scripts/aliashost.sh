#!/usr/bin/env bash
set -euo pipefail

HOST_ALIAS=$1
CANONICAL_FQDN=$2

source /usr/local/include/bind.env

if ! grep -q '\.$' <<< "$CANONICAL_FQDN"
then
  CANONICAL_FQDN="$CANONICAL_FQDN."
fi

sudo nsupdate -l -4 <<EOF
zone $ZONE
update add ${HOST_ALIAS}.${ZONE} 60 CNAME $CANONICAL_FQDN
send
EOF

named-checkzone ${ZONE} /var/lib/bind/forward.${ZONE}