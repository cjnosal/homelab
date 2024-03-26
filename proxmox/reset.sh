#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

OPTIONS=(host)

help_this="delete all vms"
help_host="hostname or ip of proxmox node"

source ${SCRIPT_DIR}/../cloudinit/base/include/argshelper

parseargs $@
requireargs host

source ${SCRIPT_DIR}/api/auth

echo shutting down all vms
for node in $(curl -fsL -H"${auth}" https://${host}:8006/api2/json/nodes | jq -r .data[].node)
do
	STOP_TASK=$(curl -fsL -H"${auth}" https://${host}:8006/api2/json/nodes/${node}/stopall \
	  -d force-stop=1 \
	  | jq -r .data)
	${SCRIPT_DIR}/api/waitfortask --task $STOP_TASK
done

echo destroying all vms
DEL_TASKS=()
for node in $(curl -fsL -H"${auth}" https://${host}:8006/api2/json/nodes | jq -r .data[].node)
do
  for vm in $(curl -fsL -H"${auth}" https://${host}:8006/api2/json/nodes/${node}/qemu | jq -r .data[].vmid)
  do
    DEL_TASKS+=($(curl -X DELETE -fsL -H"${auth}" https://${host}:8006/api2/json/nodes/${node}/qemu/${vm} \
      | jq -r .data))
  done
  for t in ${DEL_TASKS[@]}
  do
  	${SCRIPT_DIR}/api/waitfortask --task $t
  done
done

rm -rf ${SCRIPT_DIR}/../creds