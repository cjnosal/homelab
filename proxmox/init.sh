#!/usr/bin/env bash
set -euo pipefail

pushd /root/

# init

function generatecred {
  (tr -dc A-Za-z0-9 </dev/urandom || [[ $(kill -L $?) == PIPE ]]) | head -c 16
}
export -f generatecred

mkdir -p ./workspace/creds

generatecred > ./workspace/creds/ldap_admin.passwd
generatecred > ./workspace/creds/keycloak_admin.passwd
generatecred > ./workspace/creds/user.passwd

KEYCLOAK_ADMIN_PASSWD=$(cat ./workspace/creds/keycloak_admin.passwd)

eval $(ssh-agent)
ssh-add ~/.ssh/vm

# prepare vm template
./workspace/proxmox/updatetemplate || ./workspace/proxmox/createtemplate

# prepare service vms
./workspace/proxmox/preparevm --vmname bind --skip_domain -- --nameserver 192.168.3.1
./workspace/proxmox/waitforhost bind.home.arpa

ssh ubuntu@bind.home.arpa addhost.sh pve 192.168.2.200

./workspace/proxmox/preparevm --vmname step

ssh ubuntu@step.home.arpa step ca root > workspace/creds/step_root_ca.pem
ssh ubuntu@step.home.arpa sudo cat /etc/step-ca/certs/intermediate_ca.crt > workspace/creds/step_intermediate_ca.pem

./workspace/proxmox/preparevm --vmname ldap

./workspace/proxmox/preparevm --vmname keycloak

./workspace/proxmox/preparevm --vmname vault

curl -kfSsL -o /root/workspace/creds/vault_host_ssh_ca.pem https://vault.home.arpa:8200/v1/ssh-host-signer/public_key
curl -kfSsL -o /root/workspace/creds/vault_client_ssh_ca.pem https://vault.home.arpa:8200/v1/ssh-client-signer/public_key

while ! curl -kfSsL https://step.home.arpa:8443/step_root_ca.crt
do
  sleep 2
  echo retry fetching CA from caddy
done

# backfill step ca
ssh ubuntu@bind.home.arpa sudo gettlsca

# backfill ssh ca
SSH_ROLE_ID=$(ssh -o LogLevel=error ubuntu@vault.home.arpa bash << EOF
set -euo pipefail
export VAULT_ADDR=https://vault.home.arpa:8200
export VAULT_TOKEN=\$(sudo jq -r .root_token /root/vaultinit.json)
vault read --field role_id auth/approle/role/ssh-host-role/role-id
EOF
)

echo $SSH_ROLE_ID > /root/workspace/creds/ssh_host_role_id

for vm in bind step ldap keycloak vault
do
	ssh ubuntu@${vm}.home.arpa bash << EOF
set -euo pipefail
echo $SSH_ROLE_ID > /tmp/ssh_host_role_id
sudo mv /tmp/ssh_host_role_id /etc/
sudo /usr/local/bin/getsshcert
sudo /usr/local/bin/getsshclientca
sudo /usr/local/bin/getsshserverca

cat << EOC | sudoappend /etc/ssh/sshd_config.d/home.arpa.conf
TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem
HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub
EOC

sudo systemctl restart sshd
EOF
done

# vault oidc login
VAULT_CLIENT_SECRET=$(ssh -o LogLevel=error ubuntu@keycloak.home.arpa bash << EOF
set -euo pipefail
cd /opt/keycloak/bin
#./kcadm.sh config credentials --server https://keycloak.home.arpa:8443 --realm master --user admin --password ${KEYCLOAK_ADMIN_PASSWD}

/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=vault \
	-s 'redirectUris=["http://localhost:8250/oidc/callback","https://vault.home.arpa:8250/oidc/callback","https://vault.home.arpa:8200/ui/vault/auth/oidc/oidc/callback"]'
EOF
)

ssh ubuntu@vault.home.arpa bash << EOF
set -euo pipefail
export VAULT_ADDR=https://vault.home.arpa:8200
export VAULT_TOKEN=\$(sudo jq -r .root_token /root/vaultinit.json)
vault write auth/oidc/config \
         oidc_discovery_url="https://keycloak.home.arpa:8443/realms/infrastructure" \
         oidc_client_id="vault" \
         oidc_client_secret="$VAULT_CLIENT_SECRET" \
         default_role="vault-user"

vault write ssh-client-signer/roles/ssh-role -<<EOR
  {
    "algorithm_signer": "rsa-sha2-256",
    "allow_user_certificates": true,
    "allowed_users": "ops,{{identity.entity.aliases.\$(vault auth list -format=json | jq -r '.["oidc/"].accessor').name}}",
    "allowed_users_template": true,
    "allowed_extensions": "permit-pty",
    "default_extensions": { "permit-pty": "" },
    "key_type": "ca",
    "default_user": "ops",
    "ttl": "30m0s"
  }
EOR

EOF

# step oidc login
STEP_CLIENT_SECRET=$(ssh -o LogLevel=error ubuntu@keycloak.home.arpa bash << EOF
set  -euo pipefail
/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=step-ca \
	-s 'redirectUris=["http://127.0.0.1:10000/*"]' || \
  /opt/keycloak/bin/kcadm.sh get clients -r infrastructure -q clientId=step-ca --fields secret | jq -r '.[0].secret'
EOF
)

CONFIG="--ca-url https://step.home.arpa --admin-subject=step --password-file /etc/step-ca/password.txt \
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

./workspace/proxmox/preparevm --vmname workstation -- --cores 4 --memory 8192 --disk 32

./workspace/proxmox/preparevm --vmname mail
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
  -s 'redirectUris=["https://pinniped.home.arpa/homelab-issuer/callback"]' || \
  /opt/keycloak/bin/kcadm.sh get clients -r infrastructure -q clientId=pinniped --fields secret | jq -r '.[0].secret'
EOF

# tsig setup for pinniped.home.arpa
ssh ubuntu@bind.home.arpa sudo bash <<EOF
set -euo pipefail
tsig-keygen -a hmac-sha512 k8s-core-cert-manager >> /etc/bind/named.conf.tsigkeys
add-update-policy.sh "grant k8s-core-cert-manager name _acme-challenge.pinniped.home.arpa txt;"
EOF

ssh ubuntu@bind.home.arpa sudo cat /etc/bind/named.conf.tsigkeys > ./workspace/creds/tsigkeys

./workspace/cloudinit/kubernetes/create-cluster.sh --cluster core --lb_addresses "192.168.2.100-192.168.2.109" --workers 2 --subdomain eng \
  --tsig_name k8s-core-cert-manager --client_id pinniped --supervisor

./workspace/cloudinit/kubernetes/create-cluster.sh --cluster run --lb_addresses "192.168.2.110-192.168.2.119" --workers 2 --subdomain apps


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
function generatecred {
  (tr -dc A-Za-z0-9 </dev/urandom || [[ \$(kill -L \$?) == PIPE ]]) | head -c 16
}
export -f generatecred
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
function generatecred {
  (tr -dc A-Za-z0-9 </dev/urandom || [[ \$(kill -L \$?) == PIPE ]]) | head -c 16
}
export -f generatecred
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

# prompt
echo
echo Bootstrap complete - use the username you selected in cloudinit/user.yml and this temporary password to log in to workstation.home.arpa:
cat ./workspace/creds/user.passwd
rm ./workspace/creds/user.passwd
echo
echo Once logged in, run \`changeldappassword\`
echo
echo "Admin credentials at /root/workspace/creds/ should be saved in an encrypted backup (not in vault) in case of lockout"