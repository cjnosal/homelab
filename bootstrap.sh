#!/usr/bin/env bash
set -euo pipefail

ssh root@192.168.2.200 mkdir -p /root/workspace/
scp -r ./cloudinit ./proxmox root@192.168.2.200:/root/workspace/

ssh root@192.168.2.200 ./workspace/proxmox/init.sh