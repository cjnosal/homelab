# vault setup

Create an open vault server

## add DNS record
export IP=$(./workspace/proxmox/ips next)
see cloudinit/bind/README.md (done first because cloudinit includes certbot setup)

```
./workspace/cloudinit/vault/generate.sh $IP
./workspace/proxmox/newvm jammy-cloudinit-4g vault vault.yml
```

## configure LDAP
Policies are created for LDAP groups:
vault-admin > kv-admin (all vault configuration)
vault-user > kv-user (full access to all secrets under kv/)

In LDAP server, `addldapusertogroup $user <vault-admin|vault-user>`

Users can login with:
```
export VAULT_ADDR=https://vault.home.arpa:8200
vault login -method=ldap username=$USER
```

## configure OIDC
in keycloak:
```
CLIENT_SECRET=$(/usr/local/bin/create-client -s clientId=vault \
	-s 'redirectUris=["https://vault.home.arpa:8250/oidc/callback","https://vault.home.arpa:8200/ui/vault/auth/oidc/oidc/callback"]')
```

in vault as root:
```
export VAULT_ADDR=https://vault.home.arpa:8200
export VAULT_TOKEN=$(jq -r .root_token /root/vaultinit.json)
read -s VAULT_CLIENT_SECRET
vault write auth/oidc/config \
         oidc_discovery_url="https://keycloak.home.arpa:8443/realms/infrastructure" \
         oidc_client_id="vault" \
         oidc_client_secret="$VAULT_CLIENT_SECRET" \
         default_role="vault-user"
```

To allow ssh-ops members to connect as their oidc name (in addition to as ops@) amend the allowed_users template of the ssh-role:
```
vault write ssh-client-signer/roles/ssh-role -<<EOF
  {
    "algorithm_signer": "rsa-sha2-256",
    "allow_user_certificates": true,
    "allowed_users": "ops,{{identity.entity.aliases.$(vault auth list -format=json | jq -r '.["oidc/"].accessor').name}}",
    "allowed_users_template": true,
    "allowed_extensions": "permit-pty",
    "default_extensions": { "permit-pty": "" },
    "key_type": "ca",
    "default_user": "ops",
    "ttl": "30m0s"
  }
```

OIDC roles are defined for each LDAP group (vault-admin, vault-user) via groups claim

## rotate root token
```
/usr/local/bin/rotate-root-token
```

## revoke auth tokens
Lookup the accessor of your current session to avoid lockout:
`vault token lookup -format json | jq -r .data.accessor`

List all accessors:
`vault list /auth/token/accessors`

Revoke token by accessor:
`vault token revoke -accessor $ACCESSOR`

## rotate unseal key
```
/usr/local/bin/rotate-unseal-key
```

## SSH CA

### Update default VM configuration
On the Proxmox node:
* create a VM template with the vault role id for signing host certs
```
vault read --field role_id auth/approle/role/ssh-host-role/role-id > /root/workspace/cloudinit/ssh_host_role_id
/root/workspace/proxmox/img2template jammy-cloudinit-4g jammy-cloudinit-4g.img
```

* retrieve the CA PEMs (will be consumed by cloudinit generation)
```
curl -fSsL -o /root/workspace/cloudinit/vault_host_ssh_ca.pem https://vault.home.arpa:8200/v1/ssh-host-signer/public_key
curl -fSsL -o /root/workspace/cloudinit/vault_client_ssh_ca.pem https://vault.home.arpa:8200/v1/ssh-client-signer/public_key
```


### Manually configuring a server
Set up linux users for desired principals
`sudo adduser --home /home/ops --shell /bin/bash --disabled-password --gecos "Ops Team" ops`
`sudo usermod -aG sudo ops`

Request a host cert
```
vault write -field=signed_key ssh-host-signer/sign/hostrole cert_type=host public_key=@/etc/ssh/ssh_host_rsa_key.pub > /etc/ssh/ssh_host_rsa_key-cert.pub
chmod 0640 /etc/ssh/ssh_host_rsa_key-cert.pub
```

Fetch client CA public key:
`curl -fSsL -o /etc/ssh/trusted-user-ca-keys.pem https://vault.home.arpa:8200/v1/ssh-client-signer/public_key`

Update and restart SSHD:
```
TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem
HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub
```

### Manually configuring a client
The user must be part of the ssh-ops ldap group to ssh as the `ops` user
`addldapusertogroup $USERNAME ssh-ops`

Generate a keypair
`ssh-keygen -t rsa -C "me@example.com"`

Trust the server CA
`echo "@cert-authority *.home.arpa $(curl -fSsL https://vault.home.arpa:8200/v1/ssh-host-signer/public_key)" | sudoappend /etc/ssh/ssh_known_hosts`

#### Connect
Request a client cert
`vault write -field=signed_key ssh-client-signer/sign/ssh-role public_key=@$HOME/.ssh/id_rsa.pub valid_principals=ops > ~/.ssh/id_rsa-cert.pub`

Connect:
`ssh -i ~/.ssh/id_rsa me@host`