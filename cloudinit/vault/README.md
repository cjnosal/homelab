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