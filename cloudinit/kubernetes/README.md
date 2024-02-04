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
  --tsig_name k8s-core-cert-manager --client_id pinniped --supervisor

### Run cluster
./workspace/cloudinit/kubernetes/create-cluster.sh --cluster run --lb_addresses "192.168.2.110-192.168.2.119" --workers 2 --subdomain apps

## Access
The master node serves the pinniped kubeconfig (which does not contain secrets)

`curl -fSsL https://k8s-${CLUSTER}-master.home.arpa:8443/kubeconfig > ~/.kube/config`

kubectl will invoke the pinniped CLI to prompt for credentials

## TLS for kubernetes resources

Label namespaces to inject trust-manager bundles with the environments CA certificate
`smallstep.com/inject: "enabled"`

Cert-manager is configured with two ClusterIssuers: 
* `step-issuer` (for http01 challenges within the cluster's wildcard subdomain)
* `bind-issuer` (for dns01 challenges with appropriate tsig key for arbitrary domains)

ClusterIssuers can be referenced via Certificate spec or ingress annotation: 
`cert-manager.io/cluster-issuer: step-issuer`