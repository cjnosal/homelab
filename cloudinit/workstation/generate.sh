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
  --data-value-file addldapusertogroup=${SCRIPT_DIR}/../ldap/scripts/addldapusertogroup \
  --data-value-file enable_k8s_auth_script=${SCRIPT_DIR}/../vault/scripts/enable-k8s-auth.sh \
  --data-value-file add_k8s_sa_script=${SCRIPT_DIR}/../vault/scripts/add-k8s-service-account.sh \
  --data-value-file add_app_role_script=${SCRIPT_DIR}/../vault/scripts/add-app-role.sh \
  --data-value-file synccmd=${SCRIPT_DIR}/../keycloak/scripts/sync-realm