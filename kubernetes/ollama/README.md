# AI Chat Inference

Deploy ollama to the gpu kind cluster

## Deploy

`./deploy.sh --host ollama.home.arpa`

## API

```
curl https://ollama.home.arpa:30001/api/generate -d '{
"model": "phi3",
"prompt": "Why is the sky blue?",
"stream": false
}'
```
