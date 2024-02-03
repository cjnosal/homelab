#!/usr/bin/env bash
set -eu

truncate -s 0 /root/.ssh/known_hosts

echo shutting down all vms
./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm shutdown {} -forceStop

echo unlocking all vms
./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm unlock {}

echo destroying all vms
./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm destroy {}

rm -rf workspace/creds