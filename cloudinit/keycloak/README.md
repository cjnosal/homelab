# Keycloak

OIDC integration with openLDAP
```
./workspace/proxmox/preparevm --vmname keycloak --userdata ""
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/keycloak ubuntu@keycloak.home.arpa:/home/ubuntu/init
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@keycloak.home.arpa:/home/ubuntu/init/certs
ssh ubuntu@keycloak.home.arpa sudo bash << EOF
/home/ubuntu/init/keycloak/runcmd --domain "home.arpa" --acme "https://step.home.arpa/acme/acme/directory" \
  --ldap ldaps://ldap.home.arpa
EOF
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

Create a realm with ldap federation:
`./create-realm --username admin --password ${PLACEHOLDER_ADMIN_CRED} --authrealm master --realm infrastructure`

or manually:
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

#### Verify access to admin console
LDAP users in the `keycloak-realm-admin` group can manage the infrastructure realm:
https://keycloak.home.arpa:8443/admin/infrastructure/console/#/

## generate clients from the CLI
```
CLIENT_SECRET=$(/usr/local/bin/create-client --username $ADMIN_USER --password $ADMIN_PASSWORD --authrealm $REALM --realm $REALM \
  -- -s clientId=my_client -s 'redirectUris=["https://endpoint/path"]')
```

### expose LDAP groups to client
* Navigate to the new client > client scopes > ${client}-dedicated
* Add mapper > by configuration > group membership
    * Name ldap-groups
    * token claim name groups
    * disable full group paths

### Verify token
Requires direct grant enabled on the chosen client
```
curl -kfsSL -X POST 'https://keycloak.home.arpa:8443/realms/infrastructure/protocol/openid-connect/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=password' --data-urlencode 'scope=openid' --data-urlencode 'response_type=id_token'  \
  --data-urlencode "client_id=$CLIENT_ID" --data-urlencode "client_secret=$CLIENT_SECRET" \
  --data-urlencode "username=$USERNAME" --data-urlencode "password=$USER_PASSWORD" | \
  jq .access_token | cut -d'.' -f2 | base64 -d | jq .
```

## assign realm admin role to ldap group
```
GROUP_ID=$(/opt/keycloak/bin/kcadm.sh get groups -r infrastructure -q search=keycloak-realm-admin | jq -r .[0].id)
/opt/keycloak/bin/kcadm.sh add-roles -r infrastructure --gid $GROUP_ID --cclientid realm-management --rolename realm-admin
```