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
  -f ${SCRIPT_DIR}/../user.yml