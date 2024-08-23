# AI Chat Inference

Deploy openwebui frontend for remote ollama deployment

## Prerequisite

### Ollama
Deploy ollama on the gpu worker at gpu.home.arpa

### OIDC client
```
CLIENT_SECRET=$(/usr/local/bin/create-client  --authrealm infrastructure --realm infrastructure   -- -s clientId=open-webui \
  -s 'redirectUris=["https://gpt.eng.home.arpa/oauth/oidc/callback"]' -s 'webOrigins=["https://gpt.eng.home.arpa/oauth/oidc/login"]')

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: oidc
  namespace: open-webui
stringData:
  client_id: open-webui
  client_secret: $CLIENT_SECRET
EOF
```

## Deploy

`./deploy.sh`

## Frontend

Open-WebUI https://gpt.eng.home.arpa

Sign up with arbitrary local credentials
