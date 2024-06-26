# Step setup

Create a Step certificate authority and generate a root CA for this environment

Update cloudinit templates to trust the root and intermediate certs
nameserver bind.home.arpa

```
./workspace/proxmox/preparevm --vmname step --userdata ""
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/step ubuntu@step.home.arpa:/home/ubuntu/init
ssh ubuntu@step.home.arpa sudo bash << EOF
/home/ubuntu/init/step/runcmd --network "192.168.2.0/23" --domain "home.arpa"
EOF
```

## add DNS record
see cloudinit/bind/README.md

## grab ca for future vms
```
ssh -i .ssh/vm ubuntu@step.home.arpa step ca root > workspace/creds/step_root_ca.crt
ssh -i .ssh/vm ubuntu@step.home.arpa sudo cat /etc/step-ca/certs/intermediate_ca.crt > workspace/creds/step_intermediate_ca.crt
```

## trust CA in existing vm
```
sudo curl -kfSsL -o /usr/local/share/ca-certificates/step_root_ca.crt https://step.home.arpa:8444/step_root_ca.crt
sudo curl -kfSsL -o /usr/local/share/ca-certificates/step_intermediate_ca.crt https://step.home.arpa:8444/step_intermediate_ca.crt
sudo chmod -R a+r /usr/local/share/ca-certificates/*.crt
sudo update-ca-certificates
```
or
```
scp workspace/creds/step_root_ca.crt ubuntu@bind.home.arpa:/tmp/steproot.crt
scp workspace/creds/step_intermediate_ca.crt ubuntu@bind.home.arpa:/tmp/step_intermediate.crt
ssh ubuntu@bind.home.arpa << EOF
sudo cp /tmp/steproot.crt /usr/local/share/ca-certificates/steproot.crt
sudo cp /tmp/step_intermediate.crt /usr/local/share/ca-certificates/step_intermediate.crt
sudo chmod -R a+r /usr/local/share/ca-certificates/*.crt
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

On the workstation:
```
step ca bootstrap --ca-url https://step.home.arpa --install \
  --fingerprint $(curl -fSsL https://step.home.arpa:8444/fingerprint)
```

## issue a certificate

### manually
`step ca certificate $SAN file.crt file.key`
or
`step ca certificate $EMAIL file.crt file.key`

* select the oidc provisioner
* authenticate in browser

### acme
`https://step.home.arpa/acme/acme/directory`

## inspect the certificate

### view a certificate
`openssl x509 -in file.crt -noout -text`

### verify a chain
```
openssl verify -verbose server.pem
openssl verify -verbose -no-CApath -CAfile root.pem intermediate.pem
openssl verify -verbose -no-CApath -CAfile intermediate.pem -partial_chain server.pem
```

### save a remote server's cert chain
```
echo D | openssl s_client -showcerts -connect step.home.arpa:443 2>/dev/null | awk '
/BEGIN CERTIFICATE/,/END CERTIFICATE/ {
print $0
}
' | awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} {print > "cert" n ".pem"}'
```