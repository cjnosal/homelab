#!/usr/bin/env bash
set -euo pipefail

FLAGS=()
OPTIONS=(cluster)

help_this="create a kind cluster with nvidia gpu support"

help_cluster="cluster name"

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
source ${SCRIPT_DIR}/../base/include/argshelper

parseargs $@
requireargs cluster

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
