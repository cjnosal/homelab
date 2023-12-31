# Workstation setup

A VM for user interaction with deployed services
Provisions a user and comes with required client tools in the lubuntu desktop environment

```
export IP=$(./workspace/proxmox/ips next)
export DISK0=32G
export MEMORY=8192
export CORES=4
./workspace/cloudinit/workstation/generate.sh $username $displayname
./workspace/proxmox/newvm jammy-cloudinit-4g workstation workstation.yml
```

## Connect
Use remote desktop to connect to workstation.home.arpa and login with LDAP