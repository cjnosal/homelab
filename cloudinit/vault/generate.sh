#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_ip=$1
export YTT_hostname=vault

# certbot config
export YTT_acme="https://step.home.arpa/acme/acme/directory"
export YTT_zone="home.arpa"
export YTT_suffix="dc=home,dc=arpa"
export YTT_cert_group=vault
export YTT_fullchain_path=/opt/vault/tls/tls.crt
export YTT_privkey_path=/opt/vault/tls/tls.key

write_snippet vault.yml  -f ${SCRIPT_DIR}/template.yml