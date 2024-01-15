#!/usr/bin/env bash
set -euo pipefail

pushd /root/

# init

function generatecred {
  (tr -dc A-Za-z0-9 </dev/urandom || [[ $(kill -L $?) == PIPE ]]) | head -c 16
}
export -f generatecred

generatecred > ./workspace/cloudinit/ldap_admin.passwd
generatecred > ./workspace/cloudinit/keycloak_admin.passwd
generatecred > ./workspace/cloudinit/keycloak_db.passwd
generatecred > ./workspace/cloudinit/user.passwd

KEYCLOAK_ADMIN_PASSWD=$(cat ./workspace/cloudinit/keycloak_admin.passwd)

eval $(ssh-agent)
ssh-add ~/.ssh/vm

# prepare vm template
./workspace/proxmox/updatetemplate || ./workspace/proxmox/createtemplate

# prepare service vms
export NAMESERVER=192.168.3.1
export SKIP_DOMAIN=true
./workspace/proxmox/preparevm bind
unset NAMESERVER
unset SKIP_DOMAIN

ssh ubuntu@bind.home.arpa addhost.sh pve 192.168.2.200

./workspace/proxmox/preparevm step

ssh ubuntu@step.home.arpa step ca root > workspace/cloudinit/step_root_ca.pem
ssh ubuntu@step.home.arpa sudo cat /etc/step-ca/certs/intermediate_ca.crt > workspace/cloudinit/step_intermediate_ca.pem

./workspace/proxmox/preparevm ldap

./workspace/proxmox/preparevm keycloak

./workspace/proxmox/preparevm vault

curl -kfSsL -o /root/workspace/cloudinit/vault_host_ssh_ca.pem https://vault.home.arpa:8200/v1/ssh-host-signer/public_key
curl -kfSsL -o /root/workspace/cloudinit/vault_client_ssh_ca.pem https://vault.home.arpa:8200/v1/ssh-client-signer/public_key

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

echo $SSH_ROLE_ID > /root/workspace/cloudinit/ssh_host_role_id

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

/usr/local/bin/create-client admin ${KEYCLOAK_ADMIN_PASSWD} infrastructure -s clientId=vault \
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
/usr/local/bin/create-client admin ${KEYCLOAK_ADMIN_PASSWD} infrastructure -s clientId=step-ca \
	-s 'redirectUris=["http://127.0.0.1:10000/*"]' || \
  /opt/keycloak/bin/kcadm.sh get clients -r infrastructure -q clientId=step-ca --fields secret | jq -r '.[0].secret'
EOF
)

CONFIG="--ca-url https://step.home.arpa --admin-subject=step --password-file /etc/step-ca/password.txt \
  --admin-provisioner cert-provisioner"

ssh ubuntu@step.home.arpa bash -euo pipefail << EOF
sudo su
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

# create workstation
export IP=$(./workspace/proxmox/ips next)
ssh ubuntu@bind.home.arpa addhost.sh workstation $IP
./workspace/cloudinit/workstation/generate.sh
bash -c "
export DISK0=32G
export MEMORY=8192
export CORES=4
./workspace/proxmox/newvm jammy-cloudinit-4g workstation workstation.yml

./workspace/proxmox/waitforhost workstation.home.arpa"

# prompt
echo
echo Bootstrap complete - use the username you selected in cloudinit/user.yml and this temporary password to log in to workstation.home.arpa:
cat ./workspace/cloudinit/user.passwd
echo
echo Once logged in, run \`changeldappassword\`
echo
echo Next, rotate LDAP and Keycloak admin credentials - see respective README files