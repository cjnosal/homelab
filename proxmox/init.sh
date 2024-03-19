#!/usr/bin/env bash
set -euo pipefail

pushd /root/

# init

mkdir -p ./workspace/creds

eval $(ssh-agent)
ssh-add ~/.ssh/vm

# prepare vm template
./workspace/proxmox/updatetemplate || ./workspace/proxmox/createtemplate

# prepare service vms
./workspace/proxmox/preparevm --vmname bind --skip_userdata --skip_domain -- --nameserver 192.168.3.1

scp -r ./workspace/cloudinit/base ./workspace/cloudinit/bind ubuntu@192.168.2.201:/home/ubuntu/init
ssh ubuntu@192.168.2.201 sudo bash << EOF
/home/ubuntu/init/bind/runcmd --network "192.168.2.0/23" --forwarders "192.168.3.1" --zone "home.arpa" --reverse_zone "2.168.192.in-addr.arpa"
EOF
./workspace/proxmox/waitforhost bind.home.arpa

ssh ubuntu@bind.home.arpa addhost.sh pve 192.168.2.200

./workspace/proxmox/preparevm --vmname step --skip_userdata
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/step ubuntu@step.home.arpa:/home/ubuntu/init
ssh ubuntu@step.home.arpa sudo bash << EOF
/home/ubuntu/init/step/runcmd --network "192.168.2.0/23" --domain "home.arpa"
EOF

ssh ubuntu@step.home.arpa step ca root > workspace/creds/step_root_ca.crt
ssh ubuntu@step.home.arpa sudo cat /etc/step-ca/certs/intermediate_ca.crt > workspace/creds/step_intermediate_ca.crt

./workspace/proxmox/preparevm --vmname ldap --skip_userdata
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/ldap ./workspace/cloudinit/user.yml ubuntu@ldap.home.arpa:/home/ubuntu/init
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@ldap.home.arpa:/home/ubuntu/init/certs
ssh ubuntu@ldap.home.arpa sudo bash << EOF
/home/ubuntu/init/ldap/runcmd --domain "home.arpa" --acme "https://step.home.arpa/acme/acme/directory" \
  --userfile /home/ubuntu/init/user.yml
EOF

./workspace/proxmox/preparevm --vmname keycloak --skip_userdata -- --disk 8
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/keycloak ubuntu@keycloak.home.arpa:/home/ubuntu/init
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@keycloak.home.arpa:/home/ubuntu/init/certs
ssh ubuntu@keycloak.home.arpa sudo bash << EOF
/home/ubuntu/init/keycloak/runcmd --domain "home.arpa" --acme "https://step.home.arpa/acme/acme/directory" \
  --ldap ldaps://ldap.home.arpa --mail mail.home.arpa
EOF
KEYCLOAK_ADMIN_PASSWD=$(ssh -o LogLevel=error ubuntu@keycloak.home.arpa sudo cat /root/keycloak_admin.passwd)

# vault oidc login
ssh -o LogLevel=error ubuntu@keycloak.home.arpa bash > ./workspace/creds/vault-client-secret << EOF
set -euo pipefail
cd /opt/keycloak/bin

/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=vault \
  -s 'redirectUris=["http://localhost:8250/oidc/callback","https://vault.home.arpa:8250/oidc/callback","https://vault.home.arpa:8200/ui/vault/auth/oidc/oidc/callback"]'
EOF

./workspace/proxmox/preparevm --vmname vault --skip_userdata
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/vault ubuntu@vault.home.arpa:/home/ubuntu/init
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@vault.home.arpa:/home/ubuntu/init/certs
ssh ubuntu@vault.home.arpa mkdir /home/ubuntu/init/creds/
scp -r ./workspace/creds/vault-client-secret ubuntu@vault.home.arpa:/home/ubuntu/init/creds/
ssh ubuntu@vault.home.arpa sudo bash << EOF
/home/ubuntu/init/vault/runcmd --domain "home.arpa" --acme "https://step.home.arpa/acme/acme/directory" \
  --ldap ldaps://ldap.home.arpa --oidc https://keycloak.home.arpa:8443/realms/infrastructure \
  --clientsecret /home/ubuntu/init/creds/vault-client-secret --subnet 192.168.2.0/23,127.0.0.0/8
EOF

curl -kfSsL -o /root/workspace/creds/vault_host_ssh_ca.pem https://vault.home.arpa:8200/v1/ssh-host-signer/public_key
curl -kfSsL -o /root/workspace/creds/vault_client_ssh_ca.pem https://vault.home.arpa:8200/v1/ssh-client-signer/public_key

while ! curl -kfSsL https://step.home.arpa:8443/step_root_ca.crt
do
  sleep 2
  echo retry fetching CA from caddy
done

# backfill step ca
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@bind.home.arpa:/home/ubuntu/init/certs
ssh ubuntu@bind.home.arpa sudo gettlsca

# backfill ssh ca
export SSH_ROLE_ID=$(ssh -o LogLevel=error ubuntu@vault.home.arpa bash << EOF
set -euo pipefail
export VAULT_ADDR=https://vault.home.arpa:8200
export VAULT_TOKEN=\$(sudo jq -r .root_token /root/vaultinit.json)
vault read --field role_id auth/approle/role/ssh-host-role/role-id
EOF
)

echo $SSH_ROLE_ID > /root/workspace/creds/ssh_host_role_id

for vm in bind step ldap keycloak vault
do
  scp -r ./workspace/creds/ssh_host_role_id ubuntu@${vm}.home.arpa:/home/ubuntu/init/creds/
	ssh ubuntu@${vm}.home.arpa bash << EOF
set -euo pipefail
sudo /usr/local/bin/getsshcert --vault https://vault.home.arpa:8200 --roleid /home/ubuntu/init/creds/ssh_host_role_id
sudo /usr/local/bin/getsshclientca --vault https://vault.home.arpa:8200
sudo /usr/local/bin/getsshserverca --vault https://vault.home.arpa:8200 --domain home.arpa

cat << EOC | sudoappend /etc/ssh/sshd_config.d/home.arpa.conf
TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem
HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub
EOC

sudo systemctl restart sshd
EOF
done

# step oidc login
export STEP_CLIENT_SECRET=$(ssh -o LogLevel=error ubuntu@keycloak.home.arpa bash << EOF
set  -euo pipefail
/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=step-ca \
	-s 'redirectUris=["http://127.0.0.1:10000/*"]' || \
  /opt/keycloak/bin/kcadm.sh get clients -r infrastructure -q clientId=step-ca --fields secret | jq -r '.[0].secret'
EOF
)

export CONFIG="--ca-url https://step.home.arpa --admin-subject=step --password-file /etc/step-ca/password.txt \
  --admin-provisioner cert-provisioner"

ssh ubuntu@step.home.arpa sudo bash << EOF
set -euo pipefail
export STEPPATH=/etc/step-ca

step ca provisioner add keycloak --type OIDC --client-id step-ca --client-secret $STEP_CLIENT_SECRET \
  --configuration-endpoint https://keycloak.home.arpa:8443/realms/infrastructure/.well-known/openid-configuration \
  --listen-address :10000 --group step-admin $CONFIG

step ca admin add step-admin keycloak --super=true  $CONFIG
step ca admin add step-admin cert-provisioner --super=true  $CONFIG
step ca provisioner update keycloak --admin=step-provisioner-admin  $CONFIG

sudo systemctl restart step-ca
EOF

./workspace/proxmox/preparevm --vmname workstation --skip_userdata -- --cores 4 --memory 8192 --disk 32
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/ldap \
  ./workspace/cloudinit/keycloak ./workspace/cloudinit/vault \
  ./workspace/cloudinit/workstation ./workspace/cloudinit/user.yml \
  ubuntu@workstation.home.arpa:/home/ubuntu/init
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@workstation.home.arpa:/home/ubuntu/init/certs
scp -r ./workspace/kubernetes ubuntu@workstation.home.arpa:/home/ubuntu/init/kubernetes
ssh ubuntu@workstation.home.arpa mkdir /home/ubuntu/init/creds/
ssh ubuntu@workstation.home.arpa sudo bash << EOF
/home/ubuntu/init/workstation/runcmd --domain "home.arpa" --userfile /home/ubuntu/init/user.yml
EOF

./workspace/proxmox/preparevm --vmname mail --skip_userdata -- --disk 8
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/mail \
  ubuntu@mail.home.arpa:/home/ubuntu/init
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@mail.home.arpa:/home/ubuntu/init/certs
ssh ubuntu@mail.home.arpa sudo bash << EOF
/home/ubuntu/init/mail/runcmd --domain "home.arpa" --acme "https://step.home.arpa/acme/acme/directory" \
  --network 192.168.2.0/23 --nameserver 192.168.2.201 --ldap ldaps://ldap.home.arpa
EOF

DKIM="$(ssh -o LogLevel=error ubuntu@mail.home.arpa bash << EOF
sudo cat /etc/opendkim/mail.txt | cut -d'(' -f2 | cut -d')' -f1 | xargs
EOF
)"

ssh ubuntu@bind.home.arpa bash << EOF
set -euo pipefail
sudo nsupdate -l -4 <<EOD
zone home.arpa
update add home.arpa. 60 MX 10 mail.home.arpa.
update add mail._domainkey.home.arpa 60 TXT $DKIM
update add home.arpa. 60 TXT "v=spf1 mx a ?all"
send
EOD

EOF

# k8s oidc login
ssh -o LogLevel=error ubuntu@keycloak.home.arpa bash > ./workspace/creds/k8s-pinniped-client-secret << EOF
set  -euo pipefail
/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=pinniped \
  -s 'redirectUris=["https://pinniped.eng.home.arpa/homelab-issuer/callback"]' || \
  /opt/keycloak/bin/kcadm.sh get clients -r infrastructure -q clientId=pinniped --fields secret | jq -r '.[0].secret'
EOF

# tsig setup for pinniped acme challenge and external-dns
ssh ubuntu@bind.home.arpa sudo bash <<EOF
set -euo pipefail
tsig-keygen -a hmac-sha512 k8s-core-cert-manager >> /etc/bind/named.conf.tsigkeys
tsig-keygen -a hmac-sha512 k8s-core-external-dns >> /etc/bind/named.conf.tsigkeys
tsig-keygen -a hmac-sha512 k8s-run-cert-manager >> /etc/bind/named.conf.tsigkeys
tsig-keygen -a hmac-sha512 k8s-run-external-dns >> /etc/bind/named.conf.tsigkeys
add-update-policy.sh "grant k8s-core-cert-manager name _acme-challenge.pinniped.eng.home.arpa txt;"
add-update-policy.sh "grant k8s-core-external-dns wildcard *.eng.home.arpa a;"
add-update-policy.sh "grant k8s-core-external-dns wildcard *.eng.home.arpa txt;"
add-update-policy.sh "grant k8s-core-external-dns wildcard *.eng.home.arpa cname;"
add-update-policy.sh "grant k8s-run-external-dns wildcard *.apps.home.arpa a;"
add-update-policy.sh "grant k8s-run-external-dns wildcard *.apps.home.arpa txt;"
add-update-policy.sh "grant k8s-run-external-dns wildcard *.apps.home.arpa cname;"
add-allow-transfer.sh "key k8s-core-external-dns;"
add-allow-transfer.sh "key k8s-run-external-dns;"
EOF

ssh ubuntu@bind.home.arpa sudo cat /etc/bind/named.conf.tsigkeys > ./workspace/creds/tsigkeys

./workspace/cloudinit/kubernetes/create-cluster.sh --cluster core --lb_addresses "192.168.2.100-192.168.2.109" --workers 2 --subdomain eng \
  --cert_manager_tsig_name k8s-core-cert-manager --external_dns_tsig_name k8s-core-external-dns \
  --acme https://step.home.arpa/acme/acme/directory --domain home.arpa --nameserver 192.168.2.201 \
  --pinniped pinniped.eng.home.arpa --vault https://vault.home.arpa:8200 \
  --client_id pinniped --keycloak https://keycloak.home.arpa:8443 --supervisor \
  --version v1.28

./workspace/cloudinit/kubernetes/create-cluster.sh --cluster run --lb_addresses "192.168.2.110-192.168.2.119" --workers 2 --subdomain apps \
  --acme https://step.home.arpa/acme/acme/directory --domain home.arpa --nameserver 192.168.2.201 \
  --pinniped pinniped.eng.home.arpa --vault https://vault.home.arpa:8200 \
  --cert_manager_tsig_name k8s-run-cert-manager --external_dns_tsig_name k8s-run-external-dns \
  --version v1.28


## sync dns journal to config
ssh ubuntu@bind.home.arpa bash << EOF
set -euo pipefail
sudo rndc sync home.arpa
sudo rndc sync 2.168.192.in-addr.arpa
EOF

# rotate creds
# original creds were persisted in cloudinit files (on node and in vm) and in dpkg-preconfigure database in VMs

## rotate vault root token and unseal key
NEW_VAULT_CREDS=$(ssh -o LogLevel=error ubuntu@vault.home.arpa bash << EOF
set -euo pipefail
export VAULT_ADDR=https://vault.home.arpa:8200
export VAULT_TOKEN=\$(sudo jq -r .root_token /root/vaultinit.json)
export VAULT_UNSEAL_KEY=\$(sudo jq -r .unseal_keys_hex[0] /root/vaultinit.json)
export REVOKE=Y

export VAULT_TOKEN=\$(/usr/local/bin/rotate-root-token)
if [[ -z "\${VAULT_TOKEN}" ]]
then
  >&2 echo "error rotating root token"
  exit 1
fi
export VAULT_UNSEAL_KEY=\$(/usr/local/bin/rotate-unseal-key)
if [[ -z "\${VAULT_UNSEAL_KEY}" ]]
then
  >&2 echo "error rotating unseal key"
  exit 1
fi

sudo rm -rf /root/vaultinit.json
sudo rm -rf /root/.vault-token
rm -rf ~/.vault-token

cat << EOC
{
  "root_token": "\$VAULT_TOKEN",
  "unseal_keys_hex": [
    "\$VAULT_UNSEAL_KEY"
  ]
}
EOC

EOF
)
if [[ -z "${NEW_VAULT_CREDS}" ]]
then
  echo "error rotating vault creds"
  exit 1
fi
echo "$NEW_VAULT_CREDS" > ./workspace/creds/vault_creds.json

## rotate ldap admin password
NEW_LDAP_PASSWORD=$(ssh -o LogLevel=error ubuntu@ldap.home.arpa bash << EOF
set -euo pipefail

NEW_LDAP_PASSWORD=\$(generatecred)
HASH=\$(slappasswd -s \$NEW_LDAP_PASSWORD)
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// >&2 << E0C
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: \$HASH
E0C

echo "\$NEW_LDAP_PASSWORD"
EOF
)
if [[ -z "${NEW_LDAP_PASSWORD}" ]]
then
  echo "error rotating ldap cred"
  exit 1
fi
echo "$NEW_LDAP_PASSWORD" > ./workspace/creds/ldap_admin.passwd

## rotate keycloak admin password
NEW_KEYCLOAK_PASSWORD=$(ssh -o LogLevel=error ubuntu@keycloak.home.arpa bash << EOF
set -euo pipefail

NEW_KEYCLOAK_PASSWORD=\$(generatecred)

PLACEHOLDER_CRED=\$(sudo grep PASSWORD /etc/systemd/system/keycloak.service | cut -d'=' -f3)
/opt/keycloak/bin/kcadm.sh config credentials --server https://keycloak.home.arpa:8443 --realm master \
  --user admin --password \${PLACEHOLDER_CRED}

/opt/keycloak/bin/kcadm.sh set-password --username admin -p "\$NEW_KEYCLOAK_PASSWORD"

rm -rf ~/.keycloak/kcadm.config
sudo rm -rf /root/.keycloak/kcadm.config

echo "\$NEW_KEYCLOAK_PASSWORD"
EOF
)
if [[ -z "${NEW_KEYCLOAK_PASSWORD}" ]]
then
  echo "error rotating keycloak cred"
  exit 1
fi
echo "$NEW_KEYCLOAK_PASSWORD" > ./workspace/creds/keycloak_admin.passwd

USER_PASSWORD=$(ssh -o LogLevel=error ubuntu@ldap.home.arpa bash << EOF
sudo cat /root/user.passwd
sudo rm /root/user.passwd
EOF
)

# prompt
echo
echo Bootstrap complete - use the username you selected in cloudinit/user.yml and this temporary password to log in to workstation.home.arpa:
echo ${USER_PASSWORD}
echo
echo Once logged in, run \`changeldappassword --domain home.arpa --ldap ldaps://ldap.home.arpa\`
echo
echo Run \`~/.homelab\` to initialize CLIs
echo
echo "Admin credentials at /root/workspace/creds/ should be saved in an encrypted backup (not in vault) in case of lockout"