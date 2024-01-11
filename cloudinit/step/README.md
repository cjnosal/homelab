# Step setup

Create a Step certificate authority and generate a root CA for this environment

Update cloudinit templates to trust the root and intermediate certs
nameserver bind.home.arpa

```
export IP=$(./workspace/proxmox/ips next)
./workspace/cloudinit/step/generate.sh $IP
./workspace/proxmox/newvm jammy-cloudinit-4g step step.yml
```

## add DNS record
see cloudinit/bind/README.md

## grab ca for future vms
```
ssh -i .ssh/vm ubuntu@step.home.arpa step ca root > workspace/cloudinit/step_root_ca.pem
ssh -i .ssh/vm ubuntu@step.home.arpa sudo cat /etc/step-ca/certs/intermediate_ca.crt > workspace/cloudinit/step_intermediate_ca.pem
```

## trust CA in existing vm
```
scp workspace/cloudinit/step_root_ca.pem ubuntu@bind.home.arpa:/tmp/steproot.crt
scp workspace/cloudinit/step_intermediate_ca.pem ubuntu@bind.home.arpa:/tmp/step_intermediate.crt
ssh ubuntu@bind.home.arpa << EOF
sudo cp /tmp/steproot.crt /usr/local/share/ca-certificates/steproot.crt
sudo cp /tmp/step_intermediate.crt /usr/local/share/ca-certificates/step_intermediate.crt

sudo update-ca-certificates
EOF
```

## integrate with keycloak

Limited users can request identitity certs for their LDAP email, and provisioner admins can request certs for arbitrary SANs authenticating with their LDAP credentials.

### add OIDC provisioner
https://keycloak.home.arpa:8443/admin/master/console/#/master/clients
import > ./cloudinit/keyclock/step-ca-client.json
copy generated secret

in step vm configure the OIDC provisioner
* default admin name is `step` and the credential is in /etc/step-ca/password.txt
* `step ca provisioner add keycloak --type OIDC --client-id step-ca --client-secret $CLIENT_SECRET --configuration-endpoint https://keycloak.home.arpa:8443/realms/infrastructure/.well-known/openid-configuration --listen-address :10000 --group step-admin`
* `sudo systemctl restart step-ca`

### grant step admin or provisioner admin roles
step ca admin add ${EMAIL} keycloak --super=true|false
step ca provisioner update keycloak --admin=${EMAIL}

admins can also be assigned by oidc group name instead of email
step ca admin add step-admin keycloak --super=true
step ca admin add step-admin cert-provisioner --super=true
step ca provisioner update keycloak --admin=step-provisioner-admin

NOTE: when promted for superuser admin name/subject you must enter the groupname (e.g. step-admin) instead of the member's username

# Request a certificate
## initialize step CLI on a workstation
On the step-ca VM retrieve the CA fingerprint:
`sudo step certificate fingerprint /etc/step-ca/certs/root_ca.crt`

On the workstation:
`step ca bootstrap --ca-url https://step.home.arpa --install --fingerprint $FINGERPRINT`

## issue a certificate
`step ca certificate $SAN file.crt file.key`
or
`step ca certificate $EMAIL file.crt file.key`

* select the oidc provisioner
* authenticate in browser

## inspect the certificate
`openssl x509 -in file.crt -noout -text`