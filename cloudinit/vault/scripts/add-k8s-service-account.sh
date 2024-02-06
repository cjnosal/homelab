#!/usr/bin/env bash
set -euo pipefail

OPTIONS=(cluster service_account namespace policy)

help_this="add a vault policy for a specified kubernetes service account"

help_cluster="name of the cluster (e.g. core)"
help_service_account="name of the service account"
help_namespace="namespace of the service account"
help_policy="file path of a vault policy determining what secrets the service account can access (- for stdin)"

source /usr/local/include/argshelper

parseargs $@
requireargs cluster service_account namespace policy

policy_name=k8s-${cluster}-${namespace}-${service_account}-policy

vault write auth/k8s-${cluster}/role/${namespace}-${service_account}-role \
    bound_service_account_names=${service_account} \
    bound_service_account_namespaces=${namespace} \
    audience=vault \
    token_policies=${policy_name} \
    ttl=1h


if [[ "${policy}" == "-" ]]
then
    vault policy write ${policy_name} -<<EOF
$(cat -)
EOF
else
    vault policy write ${policy_name} ${policy}
fi