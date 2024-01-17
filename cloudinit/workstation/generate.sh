#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_hostname=workstation
export YTT_suffix="dc=home,dc=arpa"
export YTT_zone="home.arpa"

write_snippet workstation.yml -f ${SCRIPT_DIR}/template.yml -f ${SCRIPT_DIR}/../user.yml \
  --data-value-file ldapauthhelper=${SCRIPT_DIR}/../ldap/scripts/ldapauthhelper \
  --data-value-file addldapgroup=${SCRIPT_DIR}/../ldap/scripts/addldapgroup \
  --data-value-file addldapsystem=${SCRIPT_DIR}/../ldap/scripts/addldapsystem \
  --data-value-file addldapuser=${SCRIPT_DIR}/../ldap/scripts/addldapuser \
  --data-value-file addldapusertogroup=${SCRIPT_DIR}/../ldap/scripts/addldapusertogroup