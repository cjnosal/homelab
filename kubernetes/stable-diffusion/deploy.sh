#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f deployment.yaml --wait
kubectl -n stable-diffusion rollout status deployment/sd-web