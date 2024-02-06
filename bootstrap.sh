#!/usr/bin/env bash
set -euo pipefail

./sync.sh

if [[ "$#" == "1" && "$1" == "--reset" ]]
then
  echo reset environment
  time ssh root@192.168.2.200 ./workspace/proxmox/reset.sh
fi

echo initialize environment
time ssh root@192.168.2.200 ./workspace/proxmox/init.sh | tee init.log