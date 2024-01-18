#!/usr/bin/env bash
set -eu

truncate -s 0 /root/.ssh/known_hosts

./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm shutdown {} -forceStop
./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm unlock {}
./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm destroy {}

rm -rf workspace/creds