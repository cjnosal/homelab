#!/usr/bin/env bash
set -euo pipefail

# As a Vault administrator, set up a vault path to be shared
# between the LDAP admins and the Harbor service account

export VAULT_ADDR=https://vault.home.arpa:8200
vault login -no-print -method=oidc role=vault-admin

# service account can read harbor's ldap password
enable-k8s-auth.sh --cluster core

add-k8s-service-account.sh --cluster core --namespace harbor --service_account harbor-auth-config --policy -<<EOF
path "infrastructure/ldap/harbor" {
 capabilities = ["read"]
}
EOF

# harbor admins can manage their space to backup credentials
vault policy write harbor-ownership -<<EOF
path "infrastructure/harbor" {
 capabilities = ["list"]
}
path "infrastructure/harbor/*" {
 capabilities = ["create", "update", "list", "read", "patch", "delete"]
}
EOF

vault write auth/ldap/groups/harbor-admin policies=harbor-ownership

vault write auth/oidc/role/harbor-admin -<<EOF
{
  "bound_audiences": "vault",
  "allowed_redirect_uris": [
    "https://vault.home.arpa:8200/ui/vault/auth/oidc/oidc/callback",
    "https://vault.home.arpa:8250/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ],
  "user_claim": "preferred_username",
  "token_policies": [
    "harbor-ownership"
  ],
  "bound_claims": {
    "groups": [
      "harbor-admin"
    ]
  }
}
EOF

# ldap admins can generate a password for harbor
vault policy write ldap-harbor-write -<<EOF
path "infrastructure/ldap/harbor" {
 capabilities = ["create", "update"]
}
EOF

if vault read auth/ldap/groups/ldap-admin
then
  vault read auth/ldap/groups/ldap-admin -format=json \
    | jq -r ".data | .policies[.policies | length] |= . + \"ldap-harbor-write\"" \
    | vault write auth/ldap/groups/ldap-admin -
else
  vault write auth/ldap/groups/ldap-admin policies=ldap-harbor-write
fi