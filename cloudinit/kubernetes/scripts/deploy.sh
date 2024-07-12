#!/usr/bin/env bash
set -euo pipefail

FLAGS=(supervisor)
OPTIONS=(cluster cert_manager_tsig_name external_dns_tsig_name client_id lb_addresses workers subdomain acme domain nameserver pinniped keycloak vault)

help_this="prepare cluster networking utilities"

help_cluster="cluster name"
help_cert_manager_tsig_name="name of bind tsig key allowing dynamic updates of required _acme-challenge subdomains"
help_external_dns_tsig_name="name of bind tsig key allowing dynamic updates of A records for load balancer addresses"
help_client_id="oidc id for pinniped's upstream identity provider"
help_lb_addresses="ip list or range for metallb to allocate"
help_supervisor="install pinniped supervisor in this cluster"
help_workers="number of worker nodes"
help_subdomain="DNS subdomain for ingress"
help_acme="url of acme directory"
help_domain="parent domain of this environment"
help_nameserver="nameserver address"
help_pinniped="hostname of pinniped supervisor"
help_keycloak="url of oidc host"
help_vault="url of vault host"

source /usr/local/include/argshelper

parseargs $@
requireargs cluster acme domain nameserver vault

export KUBECONFIG=/etc/kubernetes/admin.conf

# pod network
kapp deploy -y -a flannel -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# control plane certs
for WORKER in $(seq 1 $workers)
do
  while ! kubectl get csr | grep k8s-${cluster}-worker-${WORKER}
  do
    echo waiting for csr from worker $WORKER
    sleep 2
  done
done

function approver {
  while true
  do
    if kubectl get csr | grep -q Pending
    then
      certreqs=$(kubectl get csr | grep Pending | awk '{print $1}')
      for req in $certreqs
      do
        echo approving csr $req # TODO checks
        kubectl certificate approve $req
      done
    fi
    sleep 10
  done
}

trap cleanup 1 2 3 6 15

cleanup()
{
  if [[ -n "$(jobs -p)" ]]
  then
    echo "trap: stopping csr approver"
    kill $(jobs -p)
  fi
}

approver &

# metrics
kapp deploy -y -a metrics-server -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# storage class
kapp deploy -y -a openebs -f https://openebs.github.io/charts/openebs-operator.yaml
kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# load balancer
kapp deploy -y -a metallb -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml -f- <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lb-pool
  namespace: metallb-system
spec:
  addresses:
  - $lb_addresses
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lb-pool
  namespace: metallb-system
EOF

# ingress - traefik 2.x (chart <28)
helm repo add traefik https://traefik.github.io/charts
helm upgrade --install -n traefik traefik traefik/traefik --wait --create-namespace --version v27.0.2 \
  --set providers.kubernetesIngress.publishedService.enabled=true \
  --set ports.ssh.port=2222 \
  --set ports.ssh.expose.default=true \
  --set ports.ssh.exposedPort=22 \
  --set logs.general.level=INFO \
  --set logs.access.enabled=true \
  --set service.spec.externalTrafficPolicy=Local # preserve remote ips

# tls
STEP_CA=$(cat /usr/local/share/ca-certificates/step_root_ca.crt)
STEP_CA_B64=$(base64 -w0 < /usr/local/share/ca-certificates/step_root_ca.crt)
STEP_INT_CA=$(cat /usr/local/share/ca-certificates/step_intermediate_ca.crt)
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace --version v1.14.5
helm upgrade -i -n cert-manager trust-manager jetstack/trust-manager --set secretTargets.enabled=true --set-json secretTargets.authorizedSecrets="[\"${domain}\",\"ca-bundle\"]" --wait --version v0.10.0

kubectl create secret generic -n cert-manager --from-literal=ca.crt="$STEP_CA" step-root-ca \
  || kubectl get secret -n cert-manager step-root-ca

kubectl create secret generic -n cert-manager --from-literal=ca.crt="$STEP_INT_CA" step-int-ca \
  || kubectl get secret -n cert-manager step-int-ca

kubectl apply -f- <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: step-issuer
spec:
  acme:
    server: ${acme}/acme/acme/directory
    privateKeySecretRef:
      name: step-account-key
    caBundle: "$STEP_CA_B64"
    solvers:
    - http01:
        ingress:
          ingressClassName: traefik
          ingressTemplate:
            metadata:
              annotations:
                traefik.ingress.kubernetes.io/router.entrypoints: web
EOF

if [[ -n "$cert_manager_tsig_name" ]]
then
kubectl create secret generic tsig -n cert-manager --from-file=key=/home/ubuntu/cert-manager.tsig \
  || kubectl get secret tsig -n cert-manager
kubectl apply -f- <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: bind-issuer
spec:
  acme:
    server: ${acme}/acme/acme/directory
    privateKeySecretRef:
      name: step-account-key-bind
    caBundle: "$STEP_CA_B64"
    solvers:
    - dns01:
        rfc2136:
          nameserver: ${nameserver}
          tsigKeyName: $cert_manager_tsig_name
          tsigAlgorithm: HMACSHA512
          tsigSecretSecretRef:
            name: tsig
            key: key
EOF
fi

kubectl apply -f- << EOF
---
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: ${domain}
spec:
  sources:
  - secret:
      name: "step-root-ca"
      key: "ca.crt"
  - secret:
      name: "step-int-ca"
      key: "ca.crt"
  target:
    configMap:
      key: "${domain}.pem"
    secret:
      key: "ca.crt"
    namespaceSelector:
      matchLabels:
        smallstep.com/inject: "enabled"
---
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: ca-bundle
spec:
  sources:
  - useDefaultCAs: true
  - secret:
      name: "step-root-ca"
      key: "ca.crt"
  - secret:
      name: "step-int-ca"
      key: "ca.crt"
  target:
    configMap:
      key: "root-certs.pem"
    secret:
      key: "ca.crt"
    namespaceSelector:
      matchLabels:
        smallstep.com/inject: "enabled"
EOF

# oidc
if [[ "$supervisor" == "1" ]]
then
kapp deploy -y -a pinniped -f https://get.pinniped.dev/v0.28.0/install-pinniped-supervisor.yaml -f- <<EOF
apiVersion: v1
kind: Service
metadata:
  name: pinniped-supervisor-loadbalancer
  namespace: pinniped-supervisor
  annotations:
    external-dns.alpha.kubernetes.io/hostname: ${pinniped}
spec:
  type: LoadBalancer
  selector:
    app: pinniped-supervisor
  ports:
  - protocol: TCP
    port: 443
    targetPort: 8443
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: supervisor-tls-cert-request
  namespace: pinniped-supervisor
spec:
  secretName: supervisor-tls-cert
  issuerRef:
    name: bind-issuer
    kind: ClusterIssuer
  dnsNames:
  - "${pinniped}"
---
apiVersion: idp.supervisor.pinniped.dev/v1alpha1
kind: OIDCIdentityProvider
metadata:
  namespace: pinniped-supervisor
  name: keycloak
spec:
  issuer: "${keycloak}/realms/infrastructure"
  tls:
    certificateAuthorityData: "$STEP_CA_B64"
  authorizationConfig:
    additionalScopes: [groups,email,offline_access]
    allowPasswordGrant: true
  claims:
    username: email
    groups: groups
  client:
    secretName: keycloak-client-credentials
---
apiVersion: v1
kind: Secret
metadata:
  namespace: pinniped-supervisor
  name: keycloak-client-credentials
type: secrets.pinniped.dev/oidc-client
stringData:
  clientID: $client_id
  clientSecret: $(cat /home/ubuntu/.oidc)
---
apiVersion: config.supervisor.pinniped.dev/v1alpha1
kind: FederationDomain
metadata:
  name: homelab-federation-domain
  namespace: pinniped-supervisor
spec:
  issuer: "https://${pinniped}/homelab-issuer"
  tls:
    secretName: supervisor-tls-cert
  identityProviders:
  - displayName: Keycloak
    objectRef:
      apiGroup: idp.supervisor.pinniped.dev
      kind: OIDCIdentityProvider
      name: keycloak
    transforms:
      constants:
       - name: prefix
         type: string
         stringValue: "oidc:"
       - name: onlyIncludeGroupsWithThisPrefix
         type: string
         stringValue: "k8s-"
      expressions:
         - type: groups/v1
           expression: 'groups.filter(group, group.startsWith(strConst.onlyIncludeGroupsWithThisPrefix))'
         - type: username/v1
           expression: 'strConst.prefix + username'
         - type: groups/v1
           expression: 'groups.map(group, strConst.prefix + group)'
EOF

fi

# oidc pinniped concierge
kapp deploy -y -a pinniped-concierge \
  -f "https://get.pinniped.dev/v0.28.0/install-pinniped-concierge-crds.yaml" \
  -f "https://get.pinniped.dev/v0.28.0/install-pinniped-concierge-resources.yaml" \
  -f- << EOF
---
apiVersion: authentication.concierge.pinniped.dev/v1alpha1
kind: JWTAuthenticator
metadata:
  name: pinniped-authenticator
  namespace: pinniped-concierge
spec:
  issuer: "https://${pinniped}/homelab-issuer"
  audience: $cluster
  tls:
    certificateAuthorityData: "$STEP_CA_B64"
EOF

# external-dns
if [[ -n "$external_dns_tsig_name" ]]
then
  kapp deploy -y -a external-dns -f- <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: external-dns
  labels:
    name: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
  namespace: external-dns
rules:
- apiGroups:
  - ""
  resources:
  - services
  - endpoints
  - pods
  - nodes
  verbs:
  - get
  - watch
  - list
- apiGroups:
  - extensions
  - networking.k8s.io
  resources:
  - ingresses
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - traefik.containo.us
  - traefik.io
  resources:
  - ingressroutes
  - ingressroutetcps
  - ingressrouteudps
  verbs:
  - get
  - list
  - watch
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
  namespace: external-dns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: external-dns
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: external-dns
spec:
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.k8s.io/external-dns/external-dns:v0.14.0
        args:
        - --registry=txt
        - --txt-prefix=k8s-${cluster}-external-dns-
        - --txt-owner-id=k8s-${cluster}
        - --provider=rfc2136
        - --rfc2136-host=${nameserver}
        - --rfc2136-port=53
        - --rfc2136-zone=${domain}
        - --rfc2136-tsig-secret=$(cat /home/ubuntu/external-dns.tsig)
        - --rfc2136-tsig-secret-alg=hmac-sha512
        - --rfc2136-tsig-keyname=${external_dns_tsig_name}
        - --rfc2136-tsig-axfr
        - --rfc2136-min-ttl=300s
        - --source=ingress
        - --source=service
        - --source=traefik-proxy
        - --domain-filter=.${subdomain}.${domain}
        - --policy=sync
        - --log-level=info
        - --txt-cache-interval=5m
        - --interval=15m
        - --events
EOF
fi

# vault connection
helm repo add hashicorp https://helm.releases.hashicorp.com

kubectl create namespace vault-secrets-operator-system
kubectl label namespace vault-secrets-operator-system 'smallstep.com/inject'="enabled"
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator -n vault-secrets-operator-system --wait \
  --set "defaultVaultConnection.enabled=true" \
  --set "defaultVaultConnection.address=${vault}" \
  --set "defaultVaultConnection.caCertSecret=${domain}" \
  --version 0.6.0


# Allow admins full access
cat <<EOF | kubectl apply -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-admin
subjects:
- kind: Group
  name: oidc:k8s-${cluster}-admin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
cat <<EOF | kubectl apply -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: bootstrap-admin
subjects:
- kind: User
  name: bootstrap
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo "stopping csr approver"
kill $(jobs -p)

openssl genrsa -out /home/ubuntu/init/creds/bootstrap.pem
openssl req -new -key /home/ubuntu/init/creds/bootstrap.pem -out /home/ubuntu/init/creds/bootstrap.csr -subj "/CN=bootstrap/O=bootstrap"

cat <<EOF > /home/ubuntu/init/creds/bootstrap-csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: user-request-bootstrap
spec:
  groups:
  - system:authenticated
  request: $(base64 -w 0 < /home/ubuntu/init/creds/bootstrap.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 7200
  usages:
  - digital signature
  - key encipherment
  - client auth
EOF
kubectl create -f /home/ubuntu/init/creds/bootstrap-csr.yaml
kubectl certificate approve user-request-bootstrap
kubectl wait --timeout=3m --for=jsonpath='{.status.certificate}' csr user-request-bootstrap

kubectl get csr user-request-bootstrap -o jsonpath='{.status.certificate}' | base64 -d > /home/ubuntu/init/creds/bootstrap-user.crt

server=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
kubectl --kubeconfig /home/ubuntu/init/creds/bootstrap-config.yml config set-cluster ${cluster} \
  --embed-certs=true --server=$server --certificate-authority=/etc/kubernetes/pki/ca.crt
kubectl --kubeconfig /home/ubuntu/init/creds/bootstrap-config.yml config set-credentials bootstrap \
  --client-certificate=/home/ubuntu/init/creds/bootstrap-user.crt \
  --client-key=/home/ubuntu/init/creds/bootstrap.pem \
  --embed-certs=true
kubectl --kubeconfig /home/ubuntu/init/creds/bootstrap-config.yml config set-context default \
  --cluster=${cluster} --user=bootstrap
kubectl --kubeconfig /home/ubuntu/init/creds/bootstrap-config.yml config use-context default

chown ubuntu /home/ubuntu/init/creds/bootstrap-config.yml

echo "deploy.sh complete"