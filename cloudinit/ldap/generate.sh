#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_ip=$1
export YTT_acme="https://step.home.arpa/acme/acme/directory"
export YTT_hostname=ldap2
export YTT_zone="home.arpa"
export YTT_suffix="dc=home,dc=arpa"
export YTT_placeholdercred="changeme"

write_snippet ldap.yml -f ${SCRIPT_DIR}/template.yml