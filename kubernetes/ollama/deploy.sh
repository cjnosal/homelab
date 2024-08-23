#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

pushd ${SCRIPT_DIR}

# deploy ollama
helm repo add ollama-helm https://otwld.github.io/ollama-helm/
helm repo update

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: ollama
  labels:
    name: ollama
EOF

helm upgrade --install ollama ollama-helm/ollama --namespace ollama --values ${SCRIPT_DIR}/values.yaml --wait