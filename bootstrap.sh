#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

pushd ${SCRIPT_DIR}

FLAGS=(reset compact)
OPTIONS=(node host sshpubkey sshprivkey nodeprivkey)

help_this="initialize the homelab environment"
help_reset="delete all vms before recreating environment"
help_host="hostname or ip of proxmox node"
help_node="name of proxmox node"
help_sshpubkey="file path containing ssh public key to access vms"
help_sshprivkey="file path containing ssh private key to access vms"
help_nodeprivkey="file path containing ssh private key to access proxmox node"
help_compact="reuse a base vm for multiple services to reduce memory footprint"


source ${SCRIPT_DIR}/cloudinit/base/include/argshelper

parseargs $@
requireargs node host sshpubkey sshprivkey nodeprivkey

source ${SCRIPT_DIR}/proxmox/api/auth

if [[ "${reset}" == "1" ]]
then
  echo reset environment
  time ${SCRIPT_DIR}/proxmox/reset.sh
fi

echo initialize environment
time ${SCRIPT_DIR}/proxmox/init.sh | tee init.log