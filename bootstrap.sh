#!/usr/bin/env bash
set -euo pipefail

scp -r ./cloudinit ./proxmox root@192.168.2.200:/root/workspace/

ssh root@192.168.2.200 ./workspace/proxmox/init.sh