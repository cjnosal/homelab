#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

FLAGS=(ldap vault kubernetes keycloak all)
OPTIONS=(gitlab_admin)

help_this="configure services required by gitlab, requiring admin access for each role"

help_ldap="create a gitlab system user, and ldap groups for gitlab admins"
help_keycloak="sync ldap groups"
help_vault="allow ldap admins to share the system password, and gitlab admins to backup the db password"
help_kubernetes="create the gitlab namespace and allow gitlab admins access"
help_all="configure all prerequisites"

help_gitlab_admin="initial member of gitlab admin group"

source /usr/local/include/argshelper
source /usr/local/include/ldap.env
source /usr/local/include/ldapauthhelper

parseargs $@

if [[ "$all" == "1" ]]
then
    ldap=1
    keycloak=1
    vault=1
    kubernetes=1
fi

if [[ "$vault" == "1" ]]
then
    ${SCRIPT_DIR}/prereqs/access-vault.sh
fi

if [[ "$ldap" == "1" ]]
then
    requireargs gitlab_admin
    ${SCRIPT_DIR}/prereqs/ldap-password.sh --gitlab_admin ${gitlab_admin}
fi

if [[ "$keycloak" == "1" ]]
then
    sync-realm --username ${LDAP_BIND_UID} --password ${LDAP_BIND_PW}
fi

if [[ "$kubernetes" == "1" ]]
then
    ${SCRIPT_DIR}/prereqs/k8s-namespace.sh
fi