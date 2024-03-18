#!/usr/bin/env bash
set -euo pipefail

FLAGS=(supervisor)
OPTIONS=(cluster cert_manager_tsig_name external_dns_tsig_name client_id lb_addresses workers subdomain acme domain nameserver pinniped keycloak vault version)

help_this="create a kubernetes cluster"

help_cluster="cluster name"
help_cert_manager_tsig_name="name of bind tsig key allowing dynamic updates of required _acme-challenge subdomains"
help_external_dns_tsig_name="name of bind tsig key allowing dynamic updates of A records for load balancer addresses"
help_client_id="oidc id for pinniped's upstream identity provider"
help_lb_addresses="ip list or range for metallb to allocate"
help_workers="number of worker nodes"
help_subdomain="DNS subdomain for ingress"
help_supervisor="install pinniped supervisor in this cluster"
help_acme="url of acme directory"
help_domain="parent domain of this environment"
help_version="kubernetes version (e.g. v1.28)"
# help_nameserver="nameserver address"
# help_pinniped="hostname of pinniped supervisor"
# help_keycloak="url of oidc host"
# help_vault="url of vault host"

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source ${SCRIPT_DIR}/../base/include/argshelper

parseargs $@
requireargs cluster lb_addresses workers subdomain acme domain nameserver pinniped vault version

export IP=$(./workspace/proxmox/ips next)
mastervm=k8s-${cluster}-master
#./workspace/cloudinit/kubernetes/generate.sh $IP master ${mastervm} $cluster

ssh ubuntu@${nameserver} addhost.sh ${mastervm} $IP

./workspace/proxmox/newvm --vmname ${mastervm} --ip $IP --disk 16 --memory 16384 --cores 4
./workspace/proxmox/waitforhost ${mastervm}.${domain}

scp -r ./workspace/cloudinit/base ./workspace/cloudinit/kubernetes \
  ubuntu@${mastervm}.${domain}:/home/ubuntu/init
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@${mastervm}.${domain}:/home/ubuntu/init/certs
ssh ubuntu@${mastervm}.${domain} sudo bash << EOF
/home/ubuntu/init/kubernetes/runcmd --domain ${domain} --node master --version ${version} --acme ${acme}
EOF

ssh -o LogLevel=error ubuntu@${mastervm}.${domain} bash > ./workspace/creds/k8s-${cluster}-join-cmd << EOF
sudo cat /root/joincmd
EOF


for WORKER in $(seq 1 $workers)
do
  export IP=$(./workspace/proxmox/ips next)
  workervm=k8s-${cluster}-worker-${WORKER}
  #./workspace/cloudinit/kubernetes/generate.sh $IP worker ${workervm} $cluster

  ssh ubuntu@${nameserver} addhost.sh ${workervm} $IP

  ./workspace/proxmox/newvm --vmname ${workervm} --ip $IP --disk 256 --memory 16384 --cores 8
  ./workspace/proxmox/waitforhost ${workervm}.${domain}

  scp -r ./workspace/cloudinit/base ./workspace/cloudinit/kubernetes \
    ubuntu@${workervm}.${domain}:/home/ubuntu/init
  scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@${workervm}.${domain}:/home/ubuntu/init/certs
  ssh ubuntu@${workervm}.${domain} mkdir /home/ubuntu/init/creds/
  scp -r ./workspace/creds/k8s-${cluster}-join-cmd ubuntu@${workervm}.${domain}:/home/ubuntu/init/creds/joincmd
  ssh ubuntu@${workervm}.${domain} sudo bash << EOF
  chmod a+rx /home/ubuntu/init/creds/joincmd
  /home/ubuntu/init/kubernetes/runcmd --domain ${domain} --node worker --version ${version} --acme ${acme}
EOF
done

deploy_args=""

if [[ -n "$cert_manager_tsig_name" ]]
then
  cat ./workspace/creds/tsigkeys | grep "key \"${cert_manager_tsig_name}\"" -A2 | grep secret | cut -d'"' -f2 > ./workspace/creds/tsigkeys-${cert_manager_tsig_name}
  scp ./workspace/creds/tsigkeys-${cert_manager_tsig_name} ubuntu@${mastervm}.${domain}:/home/ubuntu/cert-manager.tsig
  deploy_args="$deploy_args --cert_manager_tsig_name $cert_manager_tsig_name"
fi

if [[ -n "$external_dns_tsig_name" ]]
then
  cat ./workspace/creds/tsigkeys | grep "key \"${external_dns_tsig_name}\"" -A2 | grep secret | cut -d'"' -f2 > ./workspace/creds/tsigkeys-${external_dns_tsig_name}
  scp ./workspace/creds/tsigkeys-${external_dns_tsig_name} ubuntu@${mastervm}.${domain}:/home/ubuntu/external-dns.tsig
  deploy_args="$deploy_args --external_dns_tsig_name $external_dns_tsig_name"
fi

if [[ -n "$client_id" ]]
then
  scp ./workspace/creds/k8s-${client_id}-client-secret ubuntu@${mastervm}.${domain}:/home/ubuntu/.oidc
  deploy_args="$deploy_args --client_id $client_id"
fi

if [[ "$supervisor" == "1" ]]
then
  deploy_args="$deploy_args --supervisor --keycloak $keycloak"
fi

ssh ubuntu@${mastervm}.${domain} sudo bash << EOF
set -euo pipefail
/home/ubuntu/init/kubernetes/scripts/deploy.sh --cluster $cluster --subdomain $subdomain --lb_addresses $lb_addresses --workers $workers $deploy_args \
  --domain $domain --acme $acme --nameserver $nameserver  --pinniped $pinniped --vault $vault
EOF

ssh ubuntu@${mastervm}.${domain} sudo bash << EOF
set -euo pipefail
while ! curl -fSsL https://${pinniped}/homelab-issuer/.well-known/openid-configuration
do
  echo waiting for pinniped supervisor
  sleep 2
done
pinniped get kubeconfig --kubeconfig /etc/kubernetes/admin.conf \
  | sed -e "s/admin/user/g" -e "s/kubernetes/${cluster}/g" > /usr/share/caddy/kubeconfig
chmod a+r /usr/share/caddy/*
EOF

echo
echo "cluster ready"
echo "to log in from your workstation run:"
echo "curl -fSsL https://${mastervm}.${domain}:8443/kubeconfig > ~/.kube/config"