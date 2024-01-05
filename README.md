# Homelab

Experimenting with a single-node Proxmox environment to create an enterprise-like environment.

## Proxmox

### Environment setup

* IPv4 bridged network with 192.168.2/23 CIDR
* home.arpa TLD
* Carvel `ytt` available on the Proxmox node

## Cloudinit

### Components

* DNS (bind9)
* CA (SmallStep)
* LDAP (openLDAP)
* OIDC (keycloak)
* SSH CA (Vault)
* Secret management (Vault)
* Workstation (Lubuntu + xrdp + firefox)