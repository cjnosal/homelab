#!/usr/bin/env bash
set -euo pipefail

# As an LDAP administrator, create a system entry for harbor
# and save the password in vault

OPTIONS=(harbor_admin)

help_harbor_admin="LDAP user to add to the new harbor-admin group"

source /usr/local/include/argshelper

parseargs $@
requireargs harbor_admin

AUTH_ARGS="-x"
if [[ -z "${LDAP_BIND_DN:-}" ]]
then
	echo "bind uid:"
	read BIND_USER_UID
	export LDAP_BIND_DN=$(ldapsearch -H ldaps://ldap.home.arpa -x "(uid=${BIND_USER_UID})" dn | grep dn: | awk '{print $2}')
fi
AUTH_ARGS="$AUTH_ARGS -D $LDAP_BIND_DN"

if [[ -z "${LDAP_BIND_PW:-}" ]]
then
  echo "password:"
  read -s LDAP_BIND_PW
  export LDAP_BIND_PW
fi
AUTH_ARGS="$AUTH_ARGS -w $LDAP_BIND_PW"


function generatecred {
  (tr -dc A-Za-z0-9 </dev/urandom || [[ $(kill -L $?) == PIPE ]]) | head -c 16
}
export -f generatecred
HARBOR_LDAP_CRED=$(generatecred)

# harbor system account to search ldap users
if ! ldapsearch -x "(uid=harbor)" | grep 'uid=harbor,ou=Systems,dc=home,dc=arpa'
then
  addldapsystem harbor Harbor
fi

ldappasswd $AUTH_ARGS -s $HARBOR_LDAP_CRED -S uid=harbor,ou=systems,dc=home,dc=arpa

export VAULT_ADDR=https://vault.home.arpa:8200
echo "login to vault as ldap-admin"
vault login -no-print -method=ldap role=ldap-admin
vault write infrastructure/ldap/harbor uid=harbor password=${HARBOR_LDAP_CRED}

# harbor-admin group for the harbor admin role
if ! ldapsearch -x "(cn=harbor-admin)" | grep 'cn=harbor-admin,ou=Groups,dc=home,dc=arpa'
then
  addldapgroup harbor-admin
fi

if ! ldapsearch -x "(cn=harbor-admin)" | grep "member: uid=${harbor_admin},"
then
  addldapusertogroup $harbor_admin harbor-admin
fi

# k8s-harbor-admin group for access to the deployment namespace
if ! ldapsearch -x "(cn=k8s-harbor-admin)" | grep 'cn=k8s-harbor-admin,ou=Groups,dc=home,dc=arpa'
then
  addldapgroup k8s-harbor-admin
fi

if ! ldapsearch -x "(cn=k8s-harbor-admin)" | grep "member: uid=${harbor_admin},"
then
  addldapusertogroup $harbor_admin k8s-harbor-admin
fi