#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_ip=$1
export YTT_acme="https://step.home.arpa/acme/acme/directory"
export YTT_hostname=keycloak
export YTT_zone="home.arpa"

write_snippet keycloak.yml -f ${SCRIPT_DIR}/template.yml \
  --data-value-file placeholderadmincred=${SCRIPT_DIR}/../../creds/keycloak_admin.passwd \
  --data-value-file synccmd=${SCRIPT_DIR}/scripts/sync-realm