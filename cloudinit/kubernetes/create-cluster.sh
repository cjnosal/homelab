#!/usr/bin/env bash
set -euo pipefail

FLAGS=(supervisor)
OPTIONS=(cluster cert_manager_tsig_name external_dns_tsig_name client_id lb_addresses workers subdomain)

help_this="create a kubernetes cluster"

help_cluster="cluster name"
help_cert_manager_tsig_name="name of bind tsig key allowing dynamic updates of required _acme-challenge subdomains"
help_external_dns_tsig_name="name of bind tsig key allowing dynamic updates of A records for load balancer addresses"
help_client_id="oidc id for pinniped's upstream identity provider"
help_lb_addresses="ip list or range for metallb to allocate"
help_workers="number of worker nodes"
help_subdomain="DNS subdomain for nginx ingress"
help_supervisor="install pinniped supervisor in this cluster"

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source ${SCRIPT_DIR}/../argshelper

parseargs $@
requireargs cluster lb_addresses workers subdomain

export IP=$(./workspace/proxmox/ips next)
mastervm=k8s-${cluster}-master
./workspace/cloudinit/kubernetes/generate.sh $IP master ${mastervm} $cluster

ssh ubuntu@bind.home.arpa addhost.sh ${mastervm} $IP

./workspace/proxmox/newvm --vmname ${mastervm} --userdata ${mastervm}.yml --ip $IP --disk 16 --memory 16384 --cores 4
./workspace/proxmox/waitforhost ${mastervm}.home.arpa

ssh -o LogLevel=error ubuntu@${mastervm}.home.arpa bash > ./workspace/creds/k8s-${cluster}-join-cmd << EOF
sudo cat /root/joincmd
EOF


for WORKER in $(seq 1 $workers)
do
  export IP=$(./workspace/proxmox/ips next)
  workervm=k8s-${cluster}-worker-${WORKER}
  ./workspace/cloudinit/kubernetes/generate.sh $IP worker ${workervm} $cluster

  ssh ubuntu@bind.home.arpa addhost.sh ${workervm} $IP

  ./workspace/proxmox/newvm --vmname ${workervm} --userdata ${workervm}.yml --ip $IP --disk 256 --memory 16384 --cores 8
  ./workspace/proxmox/waitforhost ${workervm}.home.arpa
done

deploy_args=""

if [[ -n "$cert_manager_tsig_name" ]]
then
  cat ./workspace/creds/tsigkeys | grep "key \"${cert_manager_tsig_name}\"" -A2 | grep secret | cut -d'"' -f2 > ./workspace/creds/tsigkeys-${cert_manager_tsig_name}
  scp ./workspace/creds/tsigkeys-${cert_manager_tsig_name} ubuntu@${mastervm}.home.arpa:/home/ubuntu/cert-manager.tsig
  deploy_args="$deploy_args --cert_manager_tsig_name $cert_manager_tsig_name"
fi

if [[ -n "$external_dns_tsig_name" ]]
then
  cat ./workspace/creds/tsigkeys | grep "key \"${external_dns_tsig_name}\"" -A2 | grep secret | cut -d'"' -f2 > ./workspace/creds/tsigkeys-${external_dns_tsig_name}
  scp ./workspace/creds/tsigkeys-${external_dns_tsig_name} ubuntu@${mastervm}.home.arpa:/home/ubuntu/external-dns.tsig
  deploy_args="$deploy_args --external_dns_tsig_name $external_dns_tsig_name"
fi

if [[ -n "$client_id" ]]
then
  scp ./workspace/creds/k8s-${client_id}-client-secret ubuntu@${mastervm}.home.arpa:/home/ubuntu/.oidc
  deploy_args="$deploy_args --client_id $client_id"
fi

if [[ "$supervisor" == "1" ]]
then
  deploy_args="$deploy_args --supervisor"
fi

ssh ubuntu@${mastervm}.home.arpa sudo bash << EOF
set -euo pipefail
deploy.sh --cluster $cluster --subdomain $subdomain --lb_addresses $lb_addresses --workers $workers $deploy_args
EOF

ssh ubuntu@${mastervm}.home.arpa sudo bash << EOF
set -euo pipefail
while ! curl -fSsL https://pinniped.eng.home.arpa/homelab-issuer/.well-known/openid-configuration
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
echo "curl -fSsL https://k8s-${cluster}-master.home.arpa:8443/kubeconfig > ~/.kube/config"