#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

FLAGS=(dns ldap vault kubernetes keycloak all)
OPTIONS=(harbor_admin)

help_this="configure services required by harbor, requiring admin access for each role"

help_ldap="create a harbor system user, and ldap groups for harbor admins"
help_keycloak="sync ldap groups"
help_dns="authorize cert manager to set acme challenge records for harbor's domain"
help_vault="allow ldap admins to share the system password, and harbor admins to backup the db password"
help_kubernetes="create the harbor namespace and allow harbor admins access"
help_all="configure all prerequisites"

help_harbor_admin="initial member of harbor admin group"

source /usr/local/include/argshelper

parseargs $@

if [[ "$all" == "1" ]]
then
    ldap=1
    keycloak=1
    dns=1
    vault=1
    kubernetes=1
fi

if [[ "$vault" == "1" ]]
then
    ${SCRIPT_DIR}/prereqs/access-vault.sh
fi

if [[ "$ldap" == "1" ]]
then
    requireargs harbor_admin
    ${SCRIPT_DIR}/prereqs/ldap-password.sh --harbor_admin ${harbor_admin}
fi

if [[ "$keycloak" == "1" ]]
then
    ${SCRIPT_DIR}/prereqs/keycloak-sync.sh
fi

if [[ "$dns" == "1" ]]
then
    ${SCRIPT_DIR}/prereqs/cert-challenge.sh
fi

if [[ "$kubernetes" == "1" ]]
then
    ${SCRIPT_DIR}/prereqs/k8s-namespace.sh
fi