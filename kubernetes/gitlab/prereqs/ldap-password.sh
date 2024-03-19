#!/usr/bin/env bash
set -euo pipefail

# As an LDAP administrator, create a system entry for gitlab
# and save the password in vault

OPTIONS=(gitlab_admin)

help_gitlab_admin="LDAP user to add to the new gitlab-admin group"

source /usr/local/include/argshelper
source /usr/local/include/ldap.env

parseargs $@
requireargs gitlab_admin

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
GITLAB_LDAP_CRED=$(generatecred)

# gitlab system account to search ldap users
if ! ldapsearch -x "(uid=gitlab)" | grep 'uid=gitlab,ou=Systems,dc=home,dc=arpa'
then
  addldapsystem gitlab Gitlab
fi

ldappasswd $AUTH_ARGS -s $GITLAB_LDAP_CRED -S uid=gitlab,ou=systems,dc=home,dc=arpa

export VAULT_ADDR=https://vault.home.arpa:8200
echo "login to vault as ldap-admin"
vault login -no-print -method=ldap role=ldap-admin
vault write infrastructure/ldap/gitlab uid=gitlab password=${GITLAB_LDAP_CRED}

# gitlab-admin group for the gitlab admin role
if ! ldapsearch -x "(cn=gitlab-admin)" | grep 'cn=gitlab-admin,ou=Groups,dc=home,dc=arpa'
then
  addldapgroup gitlab-admin
fi

if ! ldapsearch -x "(cn=gitlab-admin)" | grep "member: uid=${gitlab_admin},"
then
  addldapusertogroup $gitlab_admin gitlab-admin
fi

# k8s-gitlab-admin group for access to the deployment namespace
if ! ldapsearch -x "(cn=k8s-gitlab-admin)" | grep 'cn=k8s-gitlab-admin,ou=Groups,dc=home,dc=arpa'
then
  addldapgroup k8s-gitlab-admin
fi

if ! ldapsearch -x "(cn=k8s-gitlab-admin)" | grep "member: uid=${gitlab_admin},"
then
  addldapusertogroup $gitlab_admin k8s-gitlab-admin
fi