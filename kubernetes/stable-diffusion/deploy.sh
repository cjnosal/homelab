#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

pushd $SCRIPT_DIR

API_USER="open-webui"

if ! [[ -f ${SCRIPT_DIR}/../../creds/stable-diffusion ]]
then
	${SCRIPT_DIR}/../../cloudinit/base/scripts/generatecred > ${SCRIPT_DIR}/../../creds/stable-diffusion
fi
API_SECRET=$(cat ${SCRIPT_DIR}/../../creds/stable-diffusion)

kubectl -n stable-diffusion apply -f- << EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: stable-diffusion
  labels:
    name: stable-diffusion
    smallstep.com/inject: enabled
---
apiVersion: v1
kind: Secret
metadata:
  namespace: stable-diffusion
  name: api-cred
type: Opaque
stringData:
  auth: --api-auth ${API_USER}:${API_SECRET}
EOF

kubectl apply -f deployment.yaml --wait
kubectl -n stable-diffusion rollout status deployment/sd-web