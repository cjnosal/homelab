#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

FLAGS=(runcluster)
OPTIONS=(node host sshpubkey sshprivkey nodeprivkey)

help_this="set up environment"
help_host="hostname or ip of proxmox node"
help_node="name of proxmox node"
help_sshpubkey="file path containing ssh public key to access vms"
help_sshprivkey="file path containing ssh private key to access vms"
help_nodeprivkey="file path containing ssh private key to access proxmox node"
help_runcluster="create additional kubernetes cluster for user applications"


source ${SCRIPT_DIR}/../cloudinit/base/include/argshelper

parseargs $@
requireargs node host sshpubkey sshprivkey nodeprivkey

source ${SCRIPT_DIR}/api/auth

# config

export local_storage=local
export lvm_storage=local-lvm
export gateway=192.168.3.1
export subnet=192.168.2.0/23
export reverse_zone=2.168.192.in-addr.arpa
export domain=home.arpa
export core_lb_range=192.168.2.100-192.168.2.109
export run_lb_range=192.168.2.110-192.168.2.119
export img=https://cloud-images.ubuntu.com/minimal/releases/jammy/release/ubuntu-22.04-minimal-cloudimg-amd64.img
workstation_img=https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
export template_name=$(basename $img .img)
workstation_template_name=$(basename $workstation_img .img)


# init

mkdir -p ${SCRIPT_DIR}/../creds

pgrep ssh-agent || eval $(ssh-agent)
ssh-add ${sshprivkey}
ssh-add ${nodeprivkey}

# prepare vm template
${SCRIPT_DIR}/updatetemplate --img ${template_name} || ${SCRIPT_DIR}/createtemplate --img ${img}
${SCRIPT_DIR}/updatetemplate --img ${workstation_template_name} || ${SCRIPT_DIR}/createtemplate --img ${workstation_img}

# prepare service vms
export nameserver=$(${SCRIPT_DIR}/ips --next)
${SCRIPT_DIR}/preparevm --vmname bind --skip_domain -- --ip ${nameserver} --nameserver ${gateway}


scp -r ${SCRIPT_DIR}/../cloudinit/base ${SCRIPT_DIR}/../cloudinit/bind ubuntu@${nameserver}:/home/ubuntu/init
ssh ubuntu@${nameserver} sudo bash << EOF
/home/ubuntu/init/bind/runcmd --network "${subnet}" --forwarders "${gateway}" --zone "${domain}" --reverse_zone "${reverse_zone}"
EOF

${SCRIPT_DIR}/waitforhost bind.${domain}

ssh ubuntu@bind.${domain} addhost.sh ${node} ${host}

${SCRIPT_DIR}/preparevm --vmname step
scp -r ${SCRIPT_DIR}/../cloudinit/base ${SCRIPT_DIR}/../cloudinit/step ubuntu@step.${domain}:/home/ubuntu/init
ssh ubuntu@step.${domain} sudo bash << EOF
/home/ubuntu/init/step/runcmd --network "${subnet}" --domain "${domain}"
EOF

# fetch ca for new vms
ssh ubuntu@step.${domain} step ca root > ${SCRIPT_DIR}/../creds/step_root_ca.crt
ssh ubuntu@step.${domain} sudo cat /etc/step-ca/certs/intermediate_ca.crt > ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt

# backfill step ca
scp -r ${SCRIPT_DIR}/../creds/step_root_ca.crt ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt ubuntu@bind.${domain}:/home/ubuntu/init/certs
ssh ubuntu@bind.${domain} sudo gettlsca

# trust locally
echo copying step CA to local trust store
sudo cp ${SCRIPT_DIR}/../creds/step_root_ca.crt ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

${SCRIPT_DIR}/preparevm --vmname ldap
scp -r ${SCRIPT_DIR}/../cloudinit/base ${SCRIPT_DIR}/../cloudinit/ldap ${SCRIPT_DIR}/../cloudinit/user.yml ubuntu@ldap.${domain}:/home/ubuntu/init
scp -r ${SCRIPT_DIR}/../creds/step_root_ca.crt ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt ubuntu@ldap.${domain}:/home/ubuntu/init/certs
ssh ubuntu@ldap.${domain} sudo bash << EOF
/home/ubuntu/init/ldap/runcmd --domain "${domain}" --acme "https://step.${domain}/acme/acme/directory" \
  --userfile /home/ubuntu/init/user.yml
EOF
BOOTSTRAP_PASSWORD=$(ssh -o LogLevel=error ubuntu@ldap.${domain} bash << EOF
sudo cat /root/bootstrap.passwd
sudo rm /root/bootstrap.passwd
EOF
)
echo $BOOTSTRAP_PASSWORD > ${SCRIPT_DIR}/../creds/ldap_bootstrap.passwd

${SCRIPT_DIR}/preparevm --vmname keycloak -- --disk 8
scp -r ${SCRIPT_DIR}/../cloudinit/base ${SCRIPT_DIR}/../cloudinit/keycloak ubuntu@keycloak.${domain}:/home/ubuntu/init
scp -r ${SCRIPT_DIR}/../creds/step_root_ca.crt ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt ubuntu@keycloak.${domain}:/home/ubuntu/init/certs
ssh ubuntu@keycloak.${domain} sudo bash << EOF
/home/ubuntu/init/keycloak/runcmd --domain "${domain}" --acme "https://step.${domain}/acme/acme/directory" \
  --ldap ldaps://ldap.${domain} --mail mail.${domain}
EOF
KEYCLOAK_ADMIN_PASSWD=$(ssh -o LogLevel=error ubuntu@keycloak.${domain} sudo cat /root/keycloak_admin.passwd)

# vault oidc login
ssh -o LogLevel=error ubuntu@keycloak.${domain} bash > ${SCRIPT_DIR}/../creds/vault-client-secret << EOF
set -euo pipefail
cd /opt/keycloak/bin

/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=vault \
  -s 'redirectUris=["http://localhost:8250/oidc/callback","https://vault.${domain}:8250/oidc/callback","https://vault.${domain}:8200/ui/vault/auth/oidc/oidc/callback"]'
EOF

${SCRIPT_DIR}/preparevm --vmname vault
scp -r ${SCRIPT_DIR}/../cloudinit/base ${SCRIPT_DIR}/../cloudinit/vault ubuntu@vault.${domain}:/home/ubuntu/init
scp -r ${SCRIPT_DIR}/../creds/step_root_ca.crt ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt ubuntu@vault.${domain}:/home/ubuntu/init/certs
ssh ubuntu@vault.${domain} mkdir -p /home/ubuntu/init/creds/
scp -r ${SCRIPT_DIR}/../creds/vault-client-secret ubuntu@vault.${domain}:/home/ubuntu/init/creds/
ssh ubuntu@vault.${domain} sudo bash << EOF
/home/ubuntu/init/vault/runcmd --domain "${domain}" --acme "https://step.${domain}/acme/acme/directory" \
  --ldap ldaps://ldap.${domain} --oidc https://keycloak.${domain}:8443/realms/infrastructure \
  --clientsecret /home/ubuntu/init/creds/vault-client-secret --subnet ${subnet},127.0.0.0/8
EOF

curl -fSsL -o ${SCRIPT_DIR}/../creds/vault_host_ssh_ca.pem https://vault.${domain}:8200/v1/ssh-host-signer/public_key
curl -fSsL -o ${SCRIPT_DIR}/../creds/vault_client_ssh_ca.pem https://vault.${domain}:8200/v1/ssh-client-signer/public_key
scp ubuntu@vault.${domain}:/usr/local/include/vault.env ${SCRIPT_DIR}/../creds/vault.env

# backfill ssh ca
export SSH_ROLE_ID=$(ssh -o LogLevel=error ubuntu@vault.${domain} bash << EOF
set -euo pipefail
export VAULT_ADDR=https://vault.${domain}:8200
export VAULT_TOKEN=\$(sudo jq -r .root_token /root/vaultinit.json)
vault read --field role_id auth/approle/role/ssh-host-role/role-id
EOF
)

echo $SSH_ROLE_ID > ${SCRIPT_DIR}/../creds/ssh_host_role_id

for vm in bind step ldap keycloak vault
do
  scp -r ${SCRIPT_DIR}/../creds/ssh_host_role_id ${SCRIPT_DIR}/../creds/vault.env ubuntu@${vm}.${domain}:/home/ubuntu/init/creds/
	ssh ubuntu@${vm}.${domain} bash << EOF
set -euo pipefail
sudo /usr/local/bin/getsshcert --vault https://vault.${domain}:8200 --roleid /home/ubuntu/init/creds/ssh_host_role_id
sudo /usr/local/bin/getsshclientca --vault https://vault.${domain}:8200

cat << EOC | sudoappend /etc/ssh/sshd_config.d/ca.conf
TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem
HostCertificate /etc/ssh/ssh_host_rsa_key-cert.pub
EOC

sudo systemctl restart sshd
EOF
done

# step oidc login
export STEP_CLIENT_SECRET=$(ssh -o LogLevel=error ubuntu@keycloak.${domain} bash << EOF
set  -euo pipefail
/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=step-ca \
	-s 'redirectUris=["http://127.0.0.1:10000/*"]' || \
  /opt/keycloak/bin/kcadm.sh get clients -r infrastructure -q clientId=step-ca --fields secret | jq -r '.[0].secret'
EOF
)

export CONFIG="--ca-url https://step.${domain} --admin-subject=step --password-file /etc/step-ca/password.txt \
  --admin-provisioner cert-provisioner"

ssh ubuntu@step.${domain} sudo bash << EOF
set -euo pipefail
export STEPPATH=/etc/step-ca

step ca provisioner add keycloak --type OIDC --client-id step-ca --client-secret $STEP_CLIENT_SECRET \
  --configuration-endpoint https://keycloak.${domain}:8443/realms/infrastructure/.well-known/openid-configuration \
  --listen-address :10000 --group step-admin $CONFIG

step ca admin add step-admin keycloak --super=true  $CONFIG
step ca admin add step-admin cert-provisioner --super=true  $CONFIG
step ca provisioner update keycloak --admin=step-provisioner-admin  $CONFIG

sudo systemctl restart step-ca
EOF

${SCRIPT_DIR}/preparevm --vmname workstation -- --cores 4 --memory 16384 --disk 32 --template_name $workstation_template_name
scp -r ${SCRIPT_DIR}/../cloudinit/base ${SCRIPT_DIR}/../cloudinit/ldap \
  ${SCRIPT_DIR}/../cloudinit/keycloak ${SCRIPT_DIR}/../cloudinit/vault \
  ${SCRIPT_DIR}/../cloudinit/workstation ${SCRIPT_DIR}/../cloudinit/user.yml \
  ubuntu@workstation.${domain}:/home/ubuntu/init
scp -r ${SCRIPT_DIR}/../creds/step_root_ca.crt ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt ubuntu@workstation.${domain}:/home/ubuntu/init/certs
scp -r ./kubernetes ubuntu@workstation.${domain}:/home/ubuntu/init/kubernetes
ssh ubuntu@workstation.${domain} mkdir -p /home/ubuntu/init/creds/
scp -r ${SCRIPT_DIR}/../creds/ssh_host_role_id ${SCRIPT_DIR}/../creds/vault.env ubuntu@workstation.${domain}:/home/ubuntu/init/creds/
ssh ubuntu@workstation.${domain} sudo bash << EOF
/home/ubuntu/init/workstation/runcmd --domain "${domain}" --userfile /home/ubuntu/init/user.yml --desktop
EOF

${SCRIPT_DIR}/preparevm --vmname mail -- --disk 8 --memory 8192
scp -r ${SCRIPT_DIR}/../cloudinit/base ${SCRIPT_DIR}/../cloudinit/mail \
  ubuntu@mail.${domain}:/home/ubuntu/init
scp -r ${SCRIPT_DIR}/../creds/step_root_ca.crt ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt ubuntu@mail.${domain}:/home/ubuntu/init/certs
ssh ubuntu@mail.${domain} mkdir -p /home/ubuntu/init/creds/
scp -r ${SCRIPT_DIR}/../creds/ssh_host_role_id ${SCRIPT_DIR}/../creds/vault.env ubuntu@mail.${domain}:/home/ubuntu/init/creds/
ssh ubuntu@mail.${domain} sudo bash << EOF
/home/ubuntu/init/mail/runcmd --domain "${domain}" --acme "https://step.${domain}/acme/acme/directory" \
  --network ${subnet} --nameserver ${nameserver} --ldap ldaps://ldap.${domain}
EOF

DKIM="$(ssh -o LogLevel=error ubuntu@mail.${domain} bash << EOF
sudo cat /etc/opendkim/mail.txt | cut -d'(' -f2 | cut -d')' -f1 | xargs
EOF
)"

ssh ubuntu@bind.${domain} bash << EOF
set -euo pipefail
sudo nsupdate -l -4 <<EOD
zone ${domain}
update add ${domain}. 60 MX 10 mail.${domain}.
update add mail._domainkey.${domain} 60 TXT $DKIM
update add ${domain}. 60 TXT "v=spf1 mx a ?all"
send
EOD

EOF

# k8s oidc login
ssh -o LogLevel=error ubuntu@keycloak.${domain} bash > ${SCRIPT_DIR}/../creds/k8s-pinniped-client-secret << EOF
set  -euo pipefail
/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=pinniped \
  -s 'redirectUris=["https://pinniped.eng.${domain}/homelab-issuer/callback"]' || \
  /opt/keycloak/bin/kcadm.sh get clients -r infrastructure -q clientId=pinniped --fields secret | jq -r '.[0].secret'
EOF

# tsig setup for pinniped acme challenge and external-dns
ssh ubuntu@bind.${domain} sudo bash <<EOF
set -euo pipefail
tsig-keygen -a hmac-sha512 k8s-core-cert-manager >> /etc/bind/named.conf.tsigkeys
tsig-keygen -a hmac-sha512 k8s-core-external-dns >> /etc/bind/named.conf.tsigkeys
tsig-keygen -a hmac-sha512 k8s-run-cert-manager >> /etc/bind/named.conf.tsigkeys
tsig-keygen -a hmac-sha512 k8s-run-external-dns >> /etc/bind/named.conf.tsigkeys
add-update-policy.sh "grant k8s-core-cert-manager name _acme-challenge.pinniped.eng.${domain} txt;"
add-update-policy.sh "grant k8s-core-external-dns wildcard *.eng.${domain} a;"
add-update-policy.sh "grant k8s-core-external-dns wildcard *.eng.${domain} txt;"
add-update-policy.sh "grant k8s-core-external-dns wildcard *.eng.${domain} cname;"
add-update-policy.sh "grant k8s-run-external-dns wildcard *.apps.${domain} a;"
add-update-policy.sh "grant k8s-run-external-dns wildcard *.apps.${domain} txt;"
add-update-policy.sh "grant k8s-run-external-dns wildcard *.apps.${domain} cname;"
add-allow-transfer.sh "key k8s-core-external-dns;"
add-allow-transfer.sh "key k8s-run-external-dns;"
EOF

ssh ubuntu@bind.${domain} sudo cat /etc/bind/named.conf.tsigkeys > ${SCRIPT_DIR}/../creds/tsigkeys

${SCRIPT_DIR}/../cloudinit/kubernetes/create-cluster.sh --cluster core --lb_addresses "${core_lb_range}" --workers 2 --subdomain eng \
  --cert_manager_tsig_name k8s-core-cert-manager --external_dns_tsig_name k8s-core-external-dns \
  --acme https://step.${domain}/acme/acme/directory --domain ${domain} --nameserver ${nameserver} \
  --pinniped pinniped.eng.${domain} --vault https://vault.${domain}:8200 \
  --client_id pinniped --keycloak https://keycloak.${domain}:8443 --supervisor \
  --version v1.28

scp ubuntu@k8s-core-master.${domain}:/home/ubuntu/init/creds/bootstrap-config.yml ${SCRIPT_DIR}/../creds/k8s-core-bootstrap-config.yml

if [[ "${runcluster}" == "1" ]]
then
${SCRIPT_DIR}/../cloudinit/kubernetes/create-cluster.sh --cluster run --lb_addresses "${run_lb_range}" --workers 2 --subdomain apps \
  --acme https://step.${domain}/acme/acme/directory --domain ${domain} --nameserver ${nameserver} \
  --pinniped pinniped.eng.${domain} --vault https://vault.${domain}:8200 \
  --cert_manager_tsig_name k8s-run-cert-manager --external_dns_tsig_name k8s-run-external-dns \
  --version v1.28
fi

${SCRIPT_DIR}/preparevm --vmname bootstrap -- --disk 8
scp -r ${SCRIPT_DIR}/../cloudinit/base ${SCRIPT_DIR}/../cloudinit/ldap \
  ${SCRIPT_DIR}/../cloudinit/keycloak ${SCRIPT_DIR}/../cloudinit/vault \
  ${SCRIPT_DIR}/../cloudinit/workstation ${SCRIPT_DIR}/../kubernetes \
  ${SCRIPT_DIR}/../cloudinit/user.yml \
  ubuntu@bootstrap.${domain}:/home/ubuntu/init
scp -r ${SCRIPT_DIR}/../creds/step_root_ca.crt ${SCRIPT_DIR}/../creds/step_intermediate_ca.crt ubuntu@bootstrap.${domain}:/home/ubuntu/init/certs
scp -r ./kubernetes ubuntu@bootstrap.${domain}:/home/ubuntu/init/kubernetes
ssh ubuntu@bootstrap.${domain} mkdir -p /home/ubuntu/init/creds/
scp -r ${SCRIPT_DIR}/../creds/ssh_host_role_id ${SCRIPT_DIR}/../creds/vault.env ubuntu@bootstrap.${domain}:/home/ubuntu/init/creds/
scp ${SCRIPT_DIR}/../creds/k8s-core-bootstrap-config.yml ${SCRIPT_DIR}/../creds/ldap_bootstrap.passwd ubuntu@bootstrap.${domain}:/home/ubuntu/init/creds/
ssh ubuntu@bootstrap.${domain} sudo bash << EOF
set -euo pipefail
/home/ubuntu/init/workstation/runcmd --domain "${domain}"

export LDAP_BIND_UID="bootstrap"
export LDAP_BIND_PW="\$(cat /home/ubuntu/init/creds/ldap_bootstrap.passwd)"
export KUBECONFIG=/home/ubuntu/init/creds/k8s-core-bootstrap-config.yml

user=\$(yq .username /home/ubuntu/init/user.yml)

/home/ubuntu/init/kubernetes/gitlab/prereqs.sh -all --gitlab_admin \${user}
/home/ubuntu/init/kubernetes/gitlab/deploy.sh

# ssh cert needed to update dns configuration
ssh-keygen -t rsa -f ~/.ssh/id_rsa -C bootstrap@${domain} -N ""

/home/ubuntu/init/kubernetes/harbor/prereqs.sh -all --harbor_admin \${user}
/home/ubuntu/init/kubernetes/harbor/deploy.sh

# randomize the bootstrap user's ldap password (another admin can reset it if the account is needed later)
source /usr/local/include/ldap.env
ldappasswd -x -D uid=bootstrap,ou=people,\${SUFFIX} -w \${LDAP_BIND_PW} -s \$(generatecred) -S uid=bootstrap,ou=people,\${SUFFIX} -H ldaps://\${HOST}
rm /home/ubuntu/init/creds/ldap_bootstrap.passwd
EOF

## sync dns journal to config
ssh ubuntu@bind.${domain} bash << EOF
set -euo pipefail
sudo rndc sync ${domain}
sudo rndc sync ${reverse_zone}
EOF

# rotate creds
# original creds were persisted in cloudinit files (on node and in vm) and in dpkg-preconfigure database in VMs

## rotate vault root token and unseal key
NEW_VAULT_CREDS=$(ssh -o LogLevel=error ubuntu@vault.${domain} bash << EOF
set -euo pipefail
export VAULT_ADDR=https://vault.${domain}:8200
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
echo "$NEW_VAULT_CREDS" > ${SCRIPT_DIR}/../creds/vault_creds.json

## rotate ldap admin password
NEW_LDAP_PASSWORD=$(ssh -o LogLevel=error ubuntu@ldap.${domain} bash << EOF
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
echo "$NEW_LDAP_PASSWORD" > ${SCRIPT_DIR}/../creds/ldap_admin.passwd

## rotate keycloak admin password
NEW_KEYCLOAK_PASSWORD=$(ssh -o LogLevel=error ubuntu@keycloak.${domain} bash << EOF
set -euo pipefail

NEW_KEYCLOAK_PASSWORD=\$(generatecred)

PLACEHOLDER_CRED=\$(sudo grep PASSWORD /etc/systemd/system/keycloak.service | cut -d'=' -f3)
/opt/keycloak/bin/kcadm.sh config credentials --server https://keycloak.${domain}:8443 --realm master \
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
echo "$NEW_KEYCLOAK_PASSWORD" > ${SCRIPT_DIR}/../creds/keycloak_admin.passwd

USER_PASSWORD=$(ssh -o LogLevel=error ubuntu@ldap.${domain} bash << EOF
sudo cat /root/user.passwd
sudo rm /root/user.passwd
EOF
)

# prompt
echo
echo Bootstrap complete - use the username you selected in cloudinit/user.yml and this temporary password to log in to workstation.${domain}:
echo ${USER_PASSWORD}
echo
echo Once logged in, run \`changeldappassword --domain ${domain} --ldap ldaps://ldap.${domain}\`
echo
echo Run \`~/.homelab\` to initialize CLIs
echo
echo "Admin credentials at ${SCRIPT_DIR}/../creds/ should be saved in an encrypted backup (not in vault) in case of lockout"