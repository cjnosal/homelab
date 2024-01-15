#!/usr/bin/env bash
set -eu

truncate -s 0 /root/.ssh/known_hosts

./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm shutdown {} -forceStop
./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm unlock {}
./workspace/proxmox/ids | grep -v 9000 | xargs -I{} -n1 qm destroy {}

rm -f workspace/cloudinit/*.pem
rm -f workspace/cloudinit/*.crt
rm -f workspace/cloudinit/ssh_host_role_id
rm -f workspace/cloudinit/*.passwd