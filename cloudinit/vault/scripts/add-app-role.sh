#!/usr/bin/env bash
set -euo pipefail

OPTIONS=(app policy owner)

help_this="add a vault policy for a specified approle"

help_app="name of the app"
help_policy="file path of a vault policy determining what secrets the app can access (- for stdin)"
help_owner="name of existing ldap group that can access the role-id and secret-id to provision the app"

source /usr/local/include/argshelper

parseargs $@
requireargs app policy owner

policy_name=app-${app}-policy

vault write auth/approle/role/${app}-role \
  secret_id_ttl=10m \
  token_num_uses=10 \
  token_ttl=20m \
  token_max_ttl=30m \
  secret_id_num_uses=1 \
  secret_id_bound_cidrs=192.168.2.0/23 \
  token_bound_cidrs=192.168.2.0/23 \
  bind_secret_id=false \
  token_policies=${policy_name}

if [[ "${policy}" == "-" ]]
then
    vault policy write ${policy_name} -<<EOF
$(cat -)
EOF
else
    vault policy write ${policy_name} ${policy}
fi

vault policy write ${policy_name}-secret-id -<<EOF
path "auth/approle/role/${app}-role/secret-id" {
  capabilities = ["create", "update"]
}
path "auth/approle/role/${app}-role/role-id" {
  capabilities = ["read"]
}
EOF

vault read auth/ldap/groups/${owner} -format=json \
  | jq -r ".data | .policies[.policies | length] |= . + \"${policy_name}-secret-id\"" \
  | vault write auth/ldap/groups/${owner} -
