#!/usr/bin/env bash
set -euo pipefail

FLAGS=()
OPTIONS=(cluster tsigname tsigpath)

help_this="create a kind cluster with nvidia gpu support"

help_cluster="cluster name"
help_tsigname="name of TSIG key that can write _acme-challenge.ollama.home.arpa"
help_tsigpath="path to file containing TSIG secret that can write _acme-challenge.ollama.home.arpa"

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source ${SCRIPT_DIR}/../base/include/argshelper

parseargs $@
requireargs cluster tsigname tsigpath

export DOCKER_SHIM_ARGS="--gpus=all -e NVIDIA_DRIVER_CAPABILITIES=compute,utility -e NVIDIA_VISIBLE_DEVICES=all"
${SCRIPT_DIR}/kind/kindwrap --cluster ${cluster}

# connectivity to cluster control plane will be lost as containerd restarts
docker cp ${SCRIPT_DIR}/gpu/prepare-node ${cluster}-control-plane:/usr/local/bin/prepare-node
docker exec -i ${cluster}-control-plane /usr/local/bin/prepare-node

kubectl config use-context kind-${cluster}
sleep 5
while ! kubectl get ns > /dev/null
do
  echo waiting for kube api server
  sleep 2
done


${SCRIPT_DIR}/gpu/prepare-cluster

helm repo add traefik https://traefik.github.io/charts

helm repo update

helm upgrade --install -n traefik traefik traefik/traefik --wait --create-namespace --version v27.0.2   \
  --set providers.kubernetesIngress.publishedService.enabled=true --set logs.general.level=INFO  \
    --set logs.access.enabled=true   --set service.spec.externalTrafficPolicy=Local \
    --set service.type=NodePort --set ports.web.nodePort=30000 --set ports.websecure.nodePort=30001

# tls
STEP_CA=$(curl -kfSsL https://step.home.arpa:8444/step_root_ca.crt)
STEP_CA_B64=$(base64 -w0 <<< $STEP_CA)
STEP_INT_CA=$(curl https://step.home.arpa:8444/step_intermediate_ca.crt)
helm repo add jetstack https://charts.jetstack.io
helm upgrade -i -n cert-manager cert-manager jetstack/cert-manager --set installCRDs=true --wait --create-namespace --version v1.14.5

kubectl create secret generic tsig -n cert-manager --from-file=key=${tsigpath} \
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
          tsigKeyName: $tsigname
          tsigAlgorithm: HMACSHA512
          tsigSecretSecretRef:
            name: tsig
            key: key
EOF

helm upgrade -i -n cert-manager trust-manager jetstack/trust-manager --set secretTargets.enabled=true --set-json secretTargets.authorizedSecrets="[\"home.arpa\",\"ca-bundle\"]" --wait --version v0.10.0

kubectl create secret generic -n cert-manager --from-literal=ca.crt="$STEP_CA" step-root-ca   || kubectl get secret -n cert-manager step-root-ca
kubectl create secret generic -n cert-manager --from-literal=ca.crt="$STEP_INT_CA" step-int-ca   || kubectl get secret -n cert-manager step-int-ca

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
  - secret:
      name: "step-int-ca"
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