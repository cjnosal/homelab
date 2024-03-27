#!/usr/bin/env bash
set -euo pipefail

source /usr/local/include/vault.env
source /usr/local/include/ldap.env
source /usr/local/include/ldapauthhelper
vault login -no-print -method=ldap role=gitlab-admin username=${LDAP_BIND_UID} password=${LDAP_BIND_PW}

# PVC is retained when reinstalling
DB_CRED=$(vault read -field password infrastructure/gitlab/db || generatecred)
vault write infrastructure/gitlab/db password=${DB_CRED}

REDIS_CRED=$(vault read -field password infrastructure/gitlab/redis || generatecred)
vault write infrastructure/gitlab/redis password=${REDIS_CRED}

GITALY_CRED=$(vault read -field password infrastructure/gitlab/gitaly || generatecred)
vault write infrastructure/gitlab/gitaly password=${GITALY_CRED}

ADMIN_CRED=$(generatecred)

MINIO_ACCESS_CRED=$(generatecred)
MINIO_SECRET_CRED=$(generatecred)

ytt -f secrets.yml \
  -v root_password="${ADMIN_CRED}" \
  -v db_password="${DB_CRED}" \
  -v redis_secret="${REDIS_CRED}" \
  -v gitaly_token="${GITALY_CRED}" \
  -v minio_access="${MINIO_ACCESS_CRED}" \
  -v minio_secret="${MINIO_SECRET_CRED}" \
  | kubectl apply -n gitlab -f-

# fetch ldap bind password gitlab will use to search users
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab-auth-config
  namespace: gitlab
---
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-auth-config
  namespace: gitlab
  annotations:
    kubernetes.io/service-account.name: gitlab-auth-config
type: kubernetes.io/service-account-token
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: static-auth
  namespace: gitlab
spec:
  method: kubernetes
  mount: k8s-core
  kubernetes:
    role: gitlab-gitlab-auth-config-role
    serviceAccount: gitlab-auth-config
    audiences:
      - https://kubernetes.default.svc.cluster.local
      - vault
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: ldap-password
  namespace: gitlab
spec:
  type: kv-v1

  # mount path
  mount: infrastructure

  # path of the secret
  path: ldap/gitlab

  # dest k8s secret
  destination:
    name: ldap-password
    create: true

  # static secret refresh interval
  refreshAfter: 30s

  # Name of the CRD to authenticate to Vault
  vaultAuthRef: gitlab/static-auth
EOF
kubectl wait -n gitlab vaultstaticsecret ldap-password --for=jsonpath='{.status.secretMAC}'


helm repo add gitlab https://charts.gitlab.io/

helm upgrade --install -n gitlab gitlab gitlab/gitlab --wait \
  --values values.yml

# wait for external-dns
while [[ -z "$(dig -4 gitlab.eng.home.arpa @bind.home.arpa +noall +answer)" ]]
do
  echo waiting for dns
  sleep 2
done