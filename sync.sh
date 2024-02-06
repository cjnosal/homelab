#!/usr/bin/env bash
set -euo pipefail

echo prepare workspace
ssh root@192.168.2.200 mkdir -p /root/workspace/
scp -r ./cloudinit ./proxmox root@192.168.2.200:/root/workspace/