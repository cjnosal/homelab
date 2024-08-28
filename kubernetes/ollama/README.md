# AI Chat Inference

Deploy ollama to the gpu kind cluster

## Deploy

`./deploy.sh --host ollama.home.arpa`

### Admin Users

Note that the first LDAP user to login is granted admin access.

## API

```
curl https://ollama.home.arpa:30001/api/generate -d '{
"model": "phi3",
"prompt": "Why is the sky blue?",
"stream": false
}'
```
