#!/usr/bin/env bash
set -euo pipefail

cat <&0 > ./kustomize/all.yaml
kustomize build ./kustomize && rm ./kustomize/all.yaml