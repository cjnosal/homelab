# Stable Diffusion

## Build

### Prerequisites
Configure /etc/docker/daemon.json to trust harbor.eng.home.arpa
`"insecure-registries": [ "harbor.eng.home.arpa" ]` or create `/etc/docker/certs.d/ca.crt` and restart docker
Configure the cluster to trust harbor (add CA to each node's trust store, and restart containerd)

Sign in with write access to the `library` public project

### Run
`./build.sh`

## Deploy

Deploys with TLS-protected ingress and an init container to download the model.

### Prerequisites
`add-update-policy.sh "grant gpu-worker-cert-manager name _acme-challenge.sd.home.arpa txt;"`
And have the `bind-issuer` configured with corresponding tsig credential

### Run
`./deploy.sh`


### Configure Open-Webui
A generated api key is written to creds/stable-diffusion. Copy to the open-webui admin panel.