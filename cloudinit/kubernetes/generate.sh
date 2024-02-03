#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

source $SCRIPT_DIR/../generate-utils.sh

export YTT_ip=$1
export YTT_node=$2 # master/worker
export YTT_hostname=$3
export CLUSTER=$4

WORKSPACE=/root/workspace
  
TEMPLATE_ARGS=""
if [[ "$YTT_node" == "worker" && -f ${WORKSPACE}/creds/k8s-${CLUSTER}-join-cmd ]]
then
  TEMPLATE_ARGS="$TEMPLATE_ARGS --data-value-file joincmd=${WORKSPACE}/creds/k8s-${CLUSTER}-join-cmd"
elif [[ "$YTT_node" == "master" ]]
then
  TEMPLATE_ARGS="$TEMPLATE_ARGS --data-value-file deploycmd=${SCRIPT_DIR}/deploy.sh"
fi

write_snippet ${YTT_hostname}.yml -f ${SCRIPT_DIR}/template.yml $TEMPLATE_ARGS