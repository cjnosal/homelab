#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

pushd ${SCRIPT_DIR}

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    name: monitoring
    smallstep.com/inject: enabled
EOF

LOKI_PASSWORD=$(cat /home/ubuntu/init/creds/alloy.passwd)
ytt -f ${SCRIPT_DIR}/secrets.yml \
  -v loki_password="${LOKI_PASSWORD}" \
  | kubectl apply -n monitoring -f-

helm upgrade --install grafana-k8s-monitoring --atomic --timeout 300s  grafana/k8s-monitoring --namespace monitoring  --values ${SCRIPT_DIR}/values.yml --wait \
  --set-string cluster.name=core \
  --version 1.0.10
