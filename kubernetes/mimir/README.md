Grafana Mimir metrics collector

### inspect mimir
kubectl -n mimir logs deployment/mimir-gateway

curl -fSsL "https://mimir.eng.home.arpa/prometheus/api/v1/..." -u user:pass --basic