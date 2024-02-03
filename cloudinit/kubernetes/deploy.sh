#!/usr/bin/env bash
set -euo pipefail

FLAGS=(supervisor)
OPTIONS=(cluster tsig_name client_id lb_addresses workers)

help_this="prepare cluster networking utilities"

help_cluster="cluster name"
help_tsig_name="name of bind tsig key allowing dynamic updates of required _acme-challenge subdomains"
help_client_id="oidc id for pinniped's upstream identity provider"
help_lb_addresses="ip list or range for metallb to allocate"
help_supervisor="install pinniped supervisor in this cluster"
help_workers="number of worker nodes"

source /usr/local/include/argshelper

parseargs $@
requireargs cluster

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

# ingress
kapp deploy -y -a ingress-nginx -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/cloud/deploy.yaml
kubectl patch ingressclass nginx -p '{"metadata": {"annotations":{"ingressclass.kubernetes.io/is-default-class":"true"}}}'

# tls
STEP_CA=$(curl -fSsL https://step.home.arpa:8443/step_root_ca.crt)
STEP_CA_B64=$(base64 -w0 <<< $STEP_CA)
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace
helm upgrade -i -n cert-manager trust-manager jetstack/trust-manager --set secretTargets.enabled=true --set-json secretTargets.authorizedSecrets='["home.arpa","ca-bundle"]' --wait

kubectl create secret generic -n cert-manager --from-literal=ca.crt="$STEP_CA" step-root-ca \
  || kubectl get secret -n cert-manager step-root-ca

kubectl apply -f- <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: step-issuer
spec:
  acme:
    server: https://step.home.arpa/acme/acme/directory
    privateKeySecretRef:
      name: step-account-key
    caBundle: "$STEP_CA_B64"
    solvers:
    - http01:
        ingress:
          ingressClassName: nginx
EOF

if [[ -n "$tsig_name" ]]
then
kubectl create secret generic tsig -n cert-manager --from-file=key=/home/ubuntu/.tsig \
  || kubectl get secret tsig -n cert-manager
kubectl apply -f- <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: bind-issuer
spec:
  acme:
    server: https://step.home.arpa/acme/acme/directory
    privateKeySecretRef:
      name: step-account-key-bind
    caBundle: "$STEP_CA_B64"
    solvers:
    - dns01:
        rfc2136:
          nameserver: bind.home.arpa
          tsigKeyName: $tsig_name
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
  name: home.arpa
spec:
  sources:
  - secret:
      name: "step-root-ca"
      key: "ca.crt"
  target:
    configMap:
      key: "home.arpa.pem"
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
  - "pinniped.home.arpa"
---
apiVersion: idp.supervisor.pinniped.dev/v1alpha1
kind: OIDCIdentityProvider
metadata:
  namespace: pinniped-supervisor
  name: keycloak
spec:
  issuer: "https://keycloak.home.arpa:8443/realms/infrastructure"
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
  issuer: "https://pinniped.home.arpa/homelab-issuer"
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
  issuer: "https://pinniped.home.arpa/homelab-issuer"
  audience: $cluster
  tls:
    certificateAuthorityData: "$STEP_CA_B64"
EOF

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

echo "stopping csr approver"
kill $(jobs -p)

echo "deploy.sh complete"