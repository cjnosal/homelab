#!/usr/bin/env bash
set -euo pipefail

# As a DNS administrator, update dynamic update policies to
# allow the cert-manager bind-issuer to solve dns01 acme challenge

source /usr/local/include/vault.env
source /usr/local/include/ldap.env
source /usr/local/include/ldapauthhelper
vault login -no-print -method=ldap role=dns-ops username=${LDAP_BIND_UID} password=${LDAP_BIND_PW}

vault write -field=signed_key ssh-client-signer/sign/dns-role \
  public_key=@$HOME/.ssh/id_rsa.pub valid_principals=dns-ops > ~/.ssh/id_rsa-cert.pub

ssh dns-ops@bind.home.arpa bash <<EOF
set -euo pipefail
sudo add-update-policy.sh "grant k8s-core-cert-manager name _acme-challenge.harbor.eng.home.arpa txt;"
EOF