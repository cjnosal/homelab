# Step setup

Create a Step certificate authority and generate a root CA for this environment

Update cloudinit templates to trust the root and intermediate certs
nameserver bind.home.arpa

```
export IP=$(./workspace/ips next)
./workspace/cloudinit/step/generate.sh $IP
./workspace/newvm jammy-cloudinit-4g step step.yml
```

## add DNS record
see cloudinit/bind/README.md

## grab ca for future vms
```
ssh -i .ssh/vm ubuntu@step.home.arpa step ca root > workspace/cloudinit/step_root_ca.pem
ssh -i .ssh/vm ubuntu@step.home.arpa sudo cat /etc/step-ca/certs/intermediate_ca.crt > workspace/cloudinit/step_intermediate_ca.pem
```