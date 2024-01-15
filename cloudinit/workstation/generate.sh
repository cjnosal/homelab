#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_hostname=workstation
export YTT_suffix="dc=home,dc=arpa"
export YTT_zone="home.arpa"

write_snippet workstation.yml -f ${SCRIPT_DIR}/template.yml -f ${SCRIPT_DIR}/../user.yml