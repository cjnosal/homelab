# Kubernetes

Create clusters with a shared pinniped supervisor for oidc login.
All clusters are setup with nginx ingress, metalLB, cert-manager, and EBS storage

## Prepare credentials for pinniped auth
### oidc client secret
```
ssh -o LogLevel=error ubuntu@keycloak.home.arpa bash > ./workspace/creds/k8s-pinniped-client-secret << EOF
set  -euo pipefail
/usr/local/bin/create-client --username admin --password ${KEYCLOAK_ADMIN_PASSWD} --authrealm master --realm infrastructure -- -s clientId=pinniped \
  -s 'redirectUris=["https://pinniped.eng.home.arpa/homelab-issuer/callback"]' || \
  /opt/keycloak/bin/kcadm.sh get clients -r infrastructure -q clientId=pinniped --fields secret | jq -r '.[0].secret'
EOF
```

### tsig key for acme challenge
```
ssh ubuntu@bind.home.arpa sudo bash <<EOF
set -euo pipefail
tsig-keygen -a hmac-sha512 k8s-core-cert-manager >> /etc/bind/named.conf.tsigkeys
add-update-policy.sh "grant k8s-core-cert-manager name _acme-challenge.pinniped.eng.home.arpa txt;"
EOF

ssh ubuntu@bind.home.arpa sudo cat /etc/bind/named.conf.tsigkeys > ./workspace/creds/tsigkeys
```

### ldap group for cluster admins
```
addldapgroup k8s-${CLUSTER}-admin
addldapusertogroup cnosal k8s-${CLUSTER}-admin
```
Run `sync-realm` on keycloak VM if defining new groups

## Create clusters

### Core cluster with pinniped supervisor
./workspace/cloudinit/kubernetes/create-cluster.sh --cluster core --lb_addresses "192.168.2.100-192.168.2.109" --workers 2 --subdomain eng \
  --cert_manager_tsig_name k8s-core-cert-manager --external_dns_tsig_name k8s-core-external-dns \
  --acme https://step.home.arpa --domain home.arpa --nameserver 192.168.2.201 \
  --pinniped pinniped.eng.home.arpa --vault https://vault.home.arpa:8200 \
  --client_id pinniped --keycloak https://keycloak.home.arpa:8443 --supervisor

### Run cluster
./workspace/cloudinit/kubernetes/create-cluster.sh --cluster run --lb_addresses "192.168.2.110-192.168.2.119" --workers 2 --subdomain apps \
  --acme https://step.home.arpa --domain home.arpa --nameserver 192.168.2.201 \
  --pinniped pinniped.eng.home.arpa --vault https://vault.home.arpa:8200 \
  --cert_manager_tsig_name k8s-run-cert-manager --external_dns_tsig_name k8s-run-external-dns

## Access
The master node serves the pinniped kubeconfig (which does not contain secrets)

`curl -fSsL https://k8s-${CLUSTER}-master.home.arpa:8444/kubeconfig > ~/.kube/config`

kubectl will invoke the pinniped CLI to prompt for credentials

## TLS for kubernetes resources

Label namespaces to inject trust-manager bundles with the environments CA certificate
`smallstep.com/inject: "enabled"`

Cert-manager is configured with two ClusterIssuers: 
* `step-issuer` (for http01 challenges within the cluster's wildcard subdomain)
* `bind-issuer` (for dns01 challenges with appropriate tsig key for arbitrary domains)

ClusterIssuers can be referenced via Certificate spec or ingress annotation: 
`cert-manager.io/cluster-issuer: step-issuer`

## Kind with GPU on WSL2

A kind cluster is created using Nvidia configuration and binaries to expose 'nvidia.com/gpu' resources to the cluster.


### Prerequisite

1. The host's docker daemon must be configured to use the nvidia container toolkit and runtime. Run gpu/prepare-node on the host if needed.
2. TSIG key set up for dns01 challenges

Add a DNS entry for the host, and enable cert-manager to orchestrate dns01 challenges for ollama.home.arpa
```
getsshclientcert --vault https://vault.home.arpa:8200

ssh ops@bind.home.arpa bash <<EOF
sudo su
set -euo pipefail

addhost.sh ollama 192.168.3.12

tsig-keygen -a hmac-sha512 gpu-worker-cert-manager >> /etc/bind/named.conf.tsigkeys

add-update-policy.sh "grant gpu-worker-cert-manager name _acme-challenge.ollama.home.arpa txt;"
EOF
```

Deploy the tsig credential
```
ssh ops@bind.home.arpa bash > gpu-worker-cert-manager.tsig <<EOF
sudo su
set -euo pipefail

cat /etc/bind/named.conf.tsigkeys | grep "key \"gpu-worker-cert-manager\"" -A2 | grep secret | cut -d'"' -f2
EOF
```

### Deploy

`./create-kind-gpu-cluster.sh --cluster gpu-worker --tsigname gpu-worker-cert-manager --tsigpath gpu-worker-cert-manager.tsig`

### Known Issues

Note: After updating GPU drivers the OS blocks access to the GPU (can verify by running nvidia-smi). 
Docker Desktop's WSL will terminate unexpectedly if a container tries to access the GPU in this state.
WSL must be restarted (wsl --shutdown) to recover.

Note: The current configuration does not support GPU timesharing. With a single GPU, 
updating the ollama configuration will hang as the new pod will be in pending state waiting for the gpu.
Patch the old replicaset to 0 desired replicas so the new pod can be scheduled.