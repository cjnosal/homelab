#!/usr/bin/env bash
set -euo pipefail

# As an LDAP administrator, create a system entry for gitlab
# and save the password in vault

OPTIONS=(gitlab_admin)

help_gitlab_admin="LDAP user to add to the new gitlab-admin group"

source /usr/local/include/argshelper
source /usr/local/include/ldap.env
source /usr/local/include/vault.env

parseargs $@
requireargs gitlab_admin

source /usr/local/include/ldapauthhelper

GITLAB_LDAP_CRED=$(generatecred)

# gitlab system account to search ldap users
if ! ldapsearch -x "(uid=gitlab)" | grep "uid=gitlab,ou=Systems,${SUFFIX}"
then
  addldapsystem gitlab Gitlab
fi

ldappasswd $AUTH_ARGS -s $GITLAB_LDAP_CRED -S uid=gitlab,ou=Systems,${SUFFIX}

echo "login to vault with ldap-admin role"
vault login -no-print -method=ldap role=ldap-admin username=${LDAP_BIND_UID} password=${LDAP_BIND_PW}
vault write infrastructure/ldap/gitlab uid=gitlab password=${GITLAB_LDAP_CRED}

# gitlab-admin group for the gitlab admin role
if ! ldapsearch -x "(cn=gitlab-admin)" | grep "cn=gitlab-admin,ou=Groups,${SUFFIX}"
then
  addldapgroup gitlab-admin
fi

if ! ldapsearch -x "(cn=gitlab-admin)" | grep "member: uid=${gitlab_admin},"
then
  addldapusertogroup $gitlab_admin gitlab-admin
fi

# k8s-gitlab-admin group for access to the deployment namespace
if ! ldapsearch -x "(cn=k8s-gitlab-admin)" | grep "cn=k8s-gitlab-admin,ou=Groups,${SUFFIX}"
then
  addldapgroup k8s-gitlab-admin
fi

if ! ldapsearch -x "(cn=k8s-gitlab-admin)" | grep "member: uid=${gitlab_admin},"
then
  addldapusertogroup $gitlab_admin k8s-gitlab-admin
fi