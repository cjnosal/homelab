# Workstation setup

A VM for user interaction with deployed services
Provisions a user and comes with required client tools in the lubuntu desktop environment

```
export IP=$(./workspace/proxmox/ips --next)
./workspace/cloudinit/workstation/generate.sh $username $displayname
./workspace/proxmox/newvm --vmname workstation --userdata workstation.yml --disk 32 --memory 8192 --cores 4 --ip $IP
```

## Connect
Use remote desktop to connect to workstation.home.arpa and login with LDAP

## First time setup

`source ~/.homelab` to:
* generate an ssh keypair
* initialize the `step cli`
* fetch kubeconfigs