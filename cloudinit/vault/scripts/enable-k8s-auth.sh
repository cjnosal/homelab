#!/usr/bin/env bash
set -euo pipefail

OPTIONS=(cluster)

help_this="enable vault kubernetes authentication for the specified cluster"

help_cluster="name of the cluster (e.g. core)"

source /usr/local/include/argshelper

parseargs $@
requireargs cluster

vault auth tune k8s-${cluster} \
  || vault auth enable -path=k8s-${cluster} kubernetes

#kubectl -n kube-system get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' > k8s-core.crt
CLUSTER_CA=$(curl -fSsL https://k8s-${cluster}-master.home.arpa:8443/kubeconfig \
  | yq .clusters[0].cluster.certificate-authority-data \
  | base64 -d)

vault write auth/k8s-${cluster}/config \
    kubernetes_host=https://k8s-${cluster}-master.home.arpa:6443 \
    kubernetes_ca_cert="${CLUSTER_CA}"