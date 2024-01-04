# Keycloak

OIDC integration with openLDAP

## add DNS record
`export IP=$(./workspace/proxmox/ips next)`
see cloudinit/bind/README.md (done first because cloudinit includes certbot setup)
`ssh ubuntu@bind.home.arpa addhost.sh keycloak $IP`

```
./workspace/cloudinit/keycloak/generate.sh $IP
./workspace/proxmox/newvm jammy-cloudinit-4g keycloak keycloak.yml
```

## update credentials
### Change the keycloak db password
`sudo -u postgres psql -c '\password keycloak'`

`sudoedit /opt/keycloak/conf/keycloak.conf` and change `db-password`

`sudo systemctl restart keycloak`

### Change the keycloak admin password
`/opt/keycloak/bin/kcadm.sh set-password --server https://keycloak.home.arpa:8443 --realm master --user admin --username admin`

## Configure realm
* Navigate to https://keycloak.home.arpa:8443
* Click Administrative Console

### Create realm
* Click master (realm dropdown)
* Click Create Realm
* Enter Realm Name: infrastructure
* Click Create

### Configure ldap
* Create a `keycloak` system user in LDAP
  `ssh ubuntu@ldap.home.arpa bash -c "sudo addldapsystem keycloak Keycloak && ldappasswd -x -D cn=admin,dc=home,dc=arpa -W -S uid=keycloak,ou=Systems,dc=home,dc=arpa`
* Navigate to User federation > Add Ldap providers
* Fill in the form:
  * Connection URL: ldaps://ldap.home.arpa
  * Bind DN: uid=keycloak,ou=Systems,dc=home,dc=arpa
  * Bind credential
  * Edit mode: READ_ONLY
  * Users DN: ou=People,dc=home,dc=arpa
  * Username LDAP attribute: uid
  * UUID LDAP attribute: entryUUID
  * User object classes: inetOrgPerson
  * Save
* Select the newly created ldap tile and navigate to Mappers > Add Mapper
  * Name: group-ldap-mapper
  * Mapper type: group-ldap-mapper
  * LDAP groups dn: ou=Groups,dc=home,dc=arpa
  * group class: groupOfNames
  * Save

### Verify ldap login

In an incognito window browse to https://keycloak.home.arpa:8443/realms/infrastructure/account/#/
Sign in with an LDAP user


## generate clients from the CLI
```
CLIENT_SECRET=$(/usr/local/bin/create-client -s clientId=my_client -s 'redirectUris=["https://endpoint/path"]')
```

### expose LDAP groups to client
* Navigate to the new client > client scopes > ${client}-dedicated
* Add mapper > by configuration > group membership
    * Name ldap-groups
    * token claim name groups
    * disable full group paths

### Verify token
```
curl -kfsSL -X POST 'https://keycloak.home.arpa:8443/realms/infrastructure/protocol/openid-connect/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=password' --data-urlencode 'scope=openid' --data-urlencode 'response_type=id_token'  \
  --data-urlencode 'client_id=$CLIENT_ID' --data-urlencode "client_secret=$CLIENT_SECRET" \
  --data-urlencode 'username=$USERNAME' --data-urlencode "password=$USER_PASSWORD" | \
  jq .access_token | cut -d'.' -f2 | base64 -d | jq .
```

## assign realm admin role to ldap group
```
/opt/keycloak/bin/kcadm.sh add-roles -r infrastructure --gname=keycloak-realm-admin --cclientid realm-management --rolename realm-admin
```