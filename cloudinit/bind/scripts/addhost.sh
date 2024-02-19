#!/usr/bin/env bash
set -euo pipefail

HOST=$1
IP=$2

source /usr/local/include/bind.env

sudo nsupdate -l -4 <<EOF
zone $ZONE
update add ${HOST}.${ZONE} 60 A $IP
send
EOF

named-checkzone ${ZONE} /var/lib/bind/forward.${ZONE}

if ! grep -q '*' <<< $HOST
then
  segment=$(cut -d'.' -f4 <<< "$IP")

  sudo nsupdate -l -4 <<EOF
  zone $REV_ZONE
update add ${segment}.${REV_ZONE} 60 PTR ${HOST}.${ZONE}
send
EOF

  named-checkzone ${REV_ZONE} /var/lib/bind/reverse.${ZONE}
fi

while [[ -z "$(dig -4 ${HOST}.${ZONE} @localhost +noall +answer)" ]]
do
  sleep 2
  echo retry
done
echo resolving ${HOST}.${ZONE} to $(dig -4 ${HOST}.${ZONE} @localhost +noall +answer)