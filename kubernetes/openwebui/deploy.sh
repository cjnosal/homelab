#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

pushd ${SCRIPT_DIR}

# deploy UI 

helm repo add open-webui https://helm.openwebui.com/
helm repo update

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: open-webui
  labels:
    name: open-webui
    smallstep.com/inject: enabled
EOF

helm upgrade --install open-webui open-webui/open-webui --namespace open-webui \
  --values values.yaml --post-renderer=./kustomize/hook.sh --wait





