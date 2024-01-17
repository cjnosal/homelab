#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_ip=$1
export YTT_acme="https://step.home.arpa/acme/acme/directory"
export YTT_hostname=ldap
export YTT_zone="home.arpa"
export YTT_suffix="dc=home,dc=arpa"

write_snippet ldap.yml -f ${SCRIPT_DIR}/template.yml \
  --data-value-file placeholderadmincred=${SCRIPT_DIR}/../ldap_admin.passwd \
  --data-value-file placeholderusercred=${SCRIPT_DIR}/../user.passwd \
  --data-value-file ldapauthhelper=${SCRIPT_DIR}/scripts/ldapauthhelper \
  --data-value-file addldapgroup=${SCRIPT_DIR}/scripts/addldapgroup \
  --data-value-file addldapsystem=${SCRIPT_DIR}/scripts/addldapsystem \
  --data-value-file addldapuser=${SCRIPT_DIR}/scripts/addldapuser \
  --data-value-file addldapusertogroup=${SCRIPT_DIR}/scripts/addldapusertogroup \
  -f ${SCRIPT_DIR}/../user.yml