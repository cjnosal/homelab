# Homelab

Experimenting with a single-node Proxmox environment to create an enterprise-like environment.

## Proxmox

### Environment setup

* Proxmox node with ssh enabled
* IPv4 bridged network with 192.168.2/23 CIDR
* home.arpa TLD
* generate an ssh key pair to access VMs

### Preparing Proxmox API Access

#### Create api token to create vms

Datacenter > Permissions > Groups
* add group vmadmin

Datacenter > Permissions > Users
* add user homelab in realm pve auth server

Datacenter > Permissions > Roles
* add bootstrap role
  sys.audit,sys.modify,sdn.use,vm.powermgmt

Datacenter > Permissions
* add user permission to group for path 
/vms and role pvevmadmin
/storage and pvedatastoreadmin
/ bootstrap

Datacenter > Permissions > API Tokens
* create an api token for homelab and save at ~/.pve/auth

#### Download node's CA cert
Datacenter > {node} > System Certificates > pve-root-ca.pem > view certificate > raw certificate

Add the CA to the OS trust store:
copy to /usr/local/share/ca-certificates/ and run `sudo update-ca-certificates`

#### Updating cert

Proxmox adds the IP address and pve.localdomain as Subject Alternative Names. If the node's network configuration has changed run:
```
pvecm updatecerts -f
systemctl restart pveproxy
```

### Bootstrap VMs

Copy cloudinit/sample-user.yml to cloudinit/user.yml and customize the values for the first admin,
then run bootstrap.sh

```
./bootstrap.sh --reset --node pve --host 192.168.2.200 --sshpubkey ~/.ssh/pve-vm.pub --sshprivkey ~/.ssh/pve-vm --nodeprivkey ~/.ssh/pve
```

## Cloudinit

### Components

* DNS (bind9)
* CA (SmallStep)
* LDAP (openLDAP)
* OIDC (keycloak)
* SSH CA (Vault)
* Secret management (Vault)
* Mail (postfix + dovecot + spamassassin + clamav + sieve)
* Object storage (Minio)
* Authenticating Proxy (Authelia)
* Kubernetes
    * flannel
    * metrics-server
    * cert-manager
    * traefik
    * metallb
    * openebs
    * pinniped
    * external-dns
    * alloy
* Kubernetes deployments
    * Harbor
    * Gitlab
    * Loki
    * Grafana
* Workstation
    * Desktop: Lubuntu + xrdp + firefox + thunderbird
    * Dev: golang + docker + sublime text