Grafana Loki log collector

### inspect loki
kubectl -n loki logs deployment/loki-gateway

curl -fSsL "https://loki.eng.home.arpa/loki/api/v1/query_range?start=1714004728084842939&end=1714004748084842939&query=%7Bstream%3D%22stdout%22%2Cpod%3D%22loki-canary-9mckh%22%7D+&limit=1000"  -u user:pass --basic  | jq .

curl -fSsL "https://loki.eng.home.arpa/loki/api/v1/labels"
curl -fSsL "https://loki.eng.home.arpa/loki/api/v1/label/component/values"
curl -fSsL "https://loki.eng.home.arpa/loki/api/v1/label/unit/values"
curl -fSsL "https://loki.eng.home.arpa/loki/api/v1/label/hostname/values"

### query is url-encoded logql `{key="value",key2="value2"}`
curl -fSsL "https://loki.eng.home.arpa/loki/api/v1/query_range?start=1714004728084842939&query=%7Bcomponent%3D%22loki.source.journal%22%7D&limit=10"  | jq .data.result
curl -fSsL "https://loki.eng.home.arpa/loki/api/v1/query_range?start=1714004728084842939&query=%7Bcomponent%3D%22loki.source.journal%22%2Chostname%3D%22workstation%22%7D&limit=10"
