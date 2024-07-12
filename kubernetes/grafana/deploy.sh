#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

pushd ${SCRIPT_DIR}

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

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

grafanacred=$(cat /home/ubuntu/init/creds/grafana.passwd)

ytt -f ${SCRIPT_DIR}/secrets.yml \
  -v loki_user="grafana" \
  -v loki_password="${grafanacred}" \
  | kubectl apply -n monitoring -f-


helm upgrade --install my-grafana grafana/grafana --namespace monitoring --values ${SCRIPT_DIR}/values.yml --wait --version 7.3.11
admincred=$(kubectl get secret --namespace monitoring my-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

# wait for external-dns
while [[ -z "$(dig -4 grafana.eng.home.arpa @bind.home.arpa +noall +answer)" ]]
do
	echo waiting for dns
	sleep 2
done

while ! curl -fSsL https://grafana.eng.home.arpa -X HEAD
do
	echo waiting for grafana
	sleep 2
done