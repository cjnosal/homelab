#!/usr/bin/env bash
set -euo pipefail

# As an LDAP administrator, create a system entry for harbor
# and save the password in vault

OPTIONS=(harbor_admin)

help_harbor_admin="LDAP user to add to the new harbor-admin group"

source /usr/local/include/argshelper
source /usr/local/include/ldap.env
source /usr/local/include/vault.env

parseargs $@
requireargs harbor_admin

source /usr/local/include/ldapauthhelper

HARBOR_LDAP_CRED=$(generatecred)

# harbor system account to search ldap users
if ! ldapsearch -x "(uid=harbor)" | grep "uid=harbor,ou=Systems,${SUFFIX}"
then
  addldapsystem harbor Harbor
fi

ldappasswd $AUTH_ARGS -s $HARBOR_LDAP_CRED -S uid=harbor,ou=systems,${SUFFIX}

echo "login to vault with ldap-admin role"
vault login -no-print -method=ldap role=ldap-admin username=${LDAP_BIND_UID} password=${LDAP_BIND_PW}
vault write infrastructure/ldap/harbor uid=harbor password=${HARBOR_LDAP_CRED}

# harbor-admin group for the harbor admin role
if ! ldapsearch -x "(cn=harbor-admin)" | grep "cn=harbor-admin,ou=Groups,${SUFFIX}"
then
  addldapgroup harbor-admin
fi

if ! ldapsearch -x "(cn=harbor-admin)" | grep "member: uid=${harbor_admin},"
then
  addldapusertogroup $harbor_admin harbor-admin
fi

# k8s-harbor-admin group for access to the deployment namespace
if ! ldapsearch -x "(cn=k8s-harbor-admin)" | grep "cn=k8s-harbor-admin,ou=Groups,${SUFFIX}"
then
  addldapgroup k8s-harbor-admin
fi

if ! ldapsearch -x "(cn=k8s-harbor-admin)" | grep "member: uid=${harbor_admin},"
then
  addldapusertogroup $harbor_admin k8s-harbor-admin
fi