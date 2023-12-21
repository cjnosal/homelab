#!/usr/bin/env bash
set -euxo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_ip=$1
export YTT_hostname=step
export YTT_zone="home.arpa"
export YTT_cidr_prefix=23
export YTT_subnet=$(cut -d'.' -f 1-3 <<< $YTT_ip).0

write_snippet step.yml -f ${SCRIPT_DIR}/template.yml