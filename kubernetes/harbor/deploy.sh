#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source /usr/local/include/vault.env
source /usr/local/include/ldap.env
source /usr/local/include/ldapauthhelper
vault login -no-print -method=ldap role=harbor-admin username=${LDAP_BIND_UID} password=${LDAP_BIND_PW}

# PVC is retained when reinstalling
DB_CRED=$(vault read -field password infrastructure/harbor/db || generatecred)
vault write infrastructure/harbor/db password=${DB_CRED}

ADMIN_CRED=$(generatecred)
SECRET_KEY=$(generatecred)

REG_CRED=$(generatecred)
HT_REG_CRED=$(htpasswd -nbB harbor_registry_user $REG_CRED)

PRIVATE_KEY=$(openssl genrsa -traditional 4096)

ytt -f ${SCRIPT_DIR}/secrets.yml \
  -v admin_password="${ADMIN_CRED}" \
  -v secret_key="${SECRET_KEY}" \
  -v registry_login.password="${REG_CRED}" \
  -v registry_login.hash="${HT_REG_CRED}" \
  -v private_key="${PRIVATE_KEY}" \
  | kubectl apply -n harbor -f-

kubectl apply -f- << EOF
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: harbor-tls-cert-request
  namespace: harbor
spec:
  secretName: tls
  issuerRef:
    name: bind-issuer
    kind: ClusterIssuer
  dnsNames:
  - "harbor.eng.home.arpa"
EOF
kubectl wait -n harbor --timeout=3m --for=condition=ready=true certificate harbor-tls-cert-request

helm repo add harbor https://helm.goharbor.io

helm upgrade --install harbor harbor/harbor --namespace harbor  --wait \
  --values ${SCRIPT_DIR}/values.yml \
  --set-string database.internal.password=${DB_CRED} \
  --version 1.14.2

# wait for external-dns
while [[ -z "$(dig -4 harbor.eng.home.arpa @bind.home.arpa +noall +answer)" ]]
do
	echo waiting for dns
	sleep 2
done

# fetch ldap bind password harbor will use to search users
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: harbor-auth-config
  namespace: harbor
---
apiVersion: v1
kind: Secret
metadata:
  name: harbor-auth-config
  namespace: harbor
  annotations:
    kubernetes.io/service-account.name: harbor-auth-config
type: kubernetes.io/service-account-token
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: static-auth
  namespace: harbor
spec:
  method: kubernetes
  mount: k8s-core
  kubernetes:
    role: harbor-harbor-auth-config-role
    serviceAccount: harbor-auth-config
    audiences:
      - https://kubernetes.default.svc.cluster.local
      - vault
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: ldap-password
  namespace: harbor
spec:
  type: kv-v1

  # mount path
  mount: infrastructure

  # path of the secret
  path: ldap/harbor

  # dest k8s secret
  destination:
    name: ldap-password
    create: true

  # static secret refresh interval
  refreshAfter: 30s

  # Name of the CRD to authenticate to Vault
  vaultAuthRef: harbor/static-auth
EOF
kubectl wait -n harbor vaultstaticsecret ldap-password --for=jsonpath='{.status.secretMAC}'

# configure ldap authentication for harbor
kubectl apply -f- << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: config-auth
  namespace: harbor
spec:
  template:
    spec:
      restartPolicy: Never
      volumes:
      - name: ldap-password
        secret:
          secretName: ldap-password
      - name: admin
        secret:
          secretName: admin
      - name: ca
        secret:
          secretName: home.arpa
      containers:
      - name: main
        image: ubuntu:latest
        volumeMounts:
        - name: ldap-password
          readOnly: true
          mountPath: "/etc/ldap-password"
        - name: admin
          readOnly: true
          mountPath: "/etc/admin-password"
        - name: ca
          readOnly: true
          mountPath: "/etc/ca"
        command: ["bash"]
        args:
        - -c
        - |
          set -eu
          apt-get update
          apt-get install -y curl
          ADMIN_CRED=$(cat /etc/admin-password/HARBOR_ADMIN_PASSWORD)
          HARBOR_LDAP_CRED=$(cat /etc/ldap-password/password)
          curl -fSsL --cacert /etc/ca/ca.crt -X PUT -u "admin:${ADMIN_CRED}" -H "Content-Type: application/json" https://harbor.eng.home.arpa/api/v2.0/configurations --data-binary @- << EOB
          {
            "auth_mode": "ldap_auth",
            "ldap_url": "ldaps://ldap.home.arpa",
            "ldap_base_dn": "dc=home,dc=arpa",
            "ldap_search_dn": "uid=harbor,ou=Systems,dc=home,dc=arpa",
            "ldap_search_password": "${HARBOR_LDAP_CRED}",
            "ldap_uid": "uid",
            "ldap_group_admin_dn": "cn=harbor-admin,ou=groups,dc=home,dc=arpa",
            "ldap_group_attribute_name": "cn",
            "ldap_group_base_dn": "ou=groups,dc=home,dc=arpa",
            "ldap_group_membership_attribute": "memberof",
            "ldap_verify_cert": true
          }
          EOB
EOF
kubectl wait -n harbor job config-auth --timeout=2m --for=condition=complete=true