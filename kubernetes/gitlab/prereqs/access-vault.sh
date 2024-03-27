#!/usr/bin/env bash
set -euo pipefail

# As a Vault administrator, set up a vault path to be shared
# between the LDAP admins and the Gitlab service account

source /usr/local/include/vault.env
source /usr/local/include/ldap.env
source /usr/local/include/ldapauthhelper
vault login -no-print -method=ldap role=ldap-admin username=${LDAP_BIND_UID} password=${LDAP_BIND_PW}

# service account can read gitlab's ldap password
enable-k8s-auth.sh --cluster core --url https://k8s-core-master.home.arpa:6443

add-k8s-service-account.sh --cluster core --namespace gitlab --service_account gitlab-auth-config --policy -<<EOF
path "infrastructure/ldap/gitlab" {
 capabilities = ["read"]
}
EOF

# gitlab admins can manage their space to backup credentials
vault policy write gitlab-ownership -<<EOF
path "infrastructure/gitlab" {
 capabilities = ["list"]
}
path "infrastructure/gitlab/*" {
 capabilities = ["create", "update", "list", "read", "patch", "delete"]
}
EOF

vault write auth/ldap/groups/gitlab-admin policies=gitlab-ownership

vault write auth/oidc/role/gitlab-admin -<<EOF
{
  "bound_audiences": "vault",
  "allowed_redirect_uris": [
    "https://vault.home.arpa:8200/ui/vault/auth/oidc/oidc/callback",
    "https://vault.home.arpa:8250/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ],
  "user_claim": "preferred_username",
  "token_policies": [
    "gitlab-ownership"
  ],
  "bound_claims": {
    "groups": [
      "gitlab-admin"
    ]
  }
}
EOF

# ldap admins can generate a password for gitlab
vault policy write ldap-gitlab-write -<<EOF
path "infrastructure/ldap/gitlab" {
 capabilities = ["create", "update"]
}
EOF

if vault read auth/ldap/groups/ldap-admin
then
  vault read auth/ldap/groups/ldap-admin -format=json \
    | jq -r ".data | .policies[.policies | length] |= . + \"ldap-gitlab-write\"" \
    | vault write auth/ldap/groups/ldap-admin -
else
  vault write auth/ldap/groups/ldap-admin policies=ldap-gitlab-write
fi