#!/usr/bin/env bash
set -euo pipefail

OPTIONS=(cluster url)

help_this="enable vault kubernetes authentication for the specified cluster"

help_cluster="name of the cluster (e.g. core)"
help_url="url of the cluster's api server"

source /usr/local/include/argshelper
source /usr/local/include/vault.env

parseargs $@
requireargs cluster url

vault auth tune k8s-${cluster} \
  || vault auth enable -path=k8s-${cluster} kubernetes

CLUSTER_CA=$(kubectl -n kube-system get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')

vault write auth/k8s-${cluster}/config \
    kubernetes_host=${url} \
    kubernetes_ca_cert="${CLUSTER_CA}"