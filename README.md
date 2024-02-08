# Homelab

Experimenting with a single-node Proxmox environment to create an enterprise-like environment.

## Proxmox

### Environment setup

* Proxmox node at 192.168.2.200 with root sshkey in local agent
* IPv4 bridged network with 192.168.2/23 CIDR
* home.arpa TLD
* Carvel `ytt` available on the Proxmox node

### Bootstrap VMs

Copy cloudinit/sample-user.yml to cloudinit/user.yml and customize the values for the first admin,
then run bootstrap.sh

## Cloudinit

### Components

* DNS (bind9)
* CA (SmallStep)
* LDAP (openLDAP)
* OIDC (keycloak)
* SSH CA (Vault)
* Secret management (Vault)
* Mail (postfix + dovecot + spamassassin + clamav + sieve)
* Kubernetes
    * flannel
    * metrics-server
    * cert-manager
    * traefik
    * metallb
    * openebs
    * pinniped
    * external-dns
* Kubernetes deployments
    * Harbor
    * Gitlab
* Workstation (Lubuntu + xrdp + firefox + thunderbird)