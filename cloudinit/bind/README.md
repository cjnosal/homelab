# Bind Setup

Create a bind9 dns server with a home.arpa zone on the VM's IPv4 /23 network 

# With cloudinit
## Create vm
1. install ytt
2. create bind server
```
export IP=$(./workspace/proxmox/ips next)
./workspace/cloudinit/bind/generate.sh $IP
./workspace/proxmox/newvm --vmname bind --userdata bind.yml --ip $IP --nameserver 192.168.3.1
```

# Workstation gateway
Configure your workstation or router to delegate home.arpa to the VM to locally resolve hosts
Configure the PVE nodes (System > DNS) if gateway isn't delegating

# Populate records

## Add A and PTR records for new hosts
`ssh ubuntu@${BIND_IP} addhost.sh $HOST $HOST_IP`
or
`ssh ubuntu@${BIND_IP} /home/ubuntu/bind/addhost.sh $HOST $HOST_IP`


## Add CNAME records for new hosts
`ssh ubuntu@${BIND_IP} aliashost.sh $HOST_ALIAS $CANONICAL_FQDN.`
e.g. `ssh ubuntu@${BIND_IP} aliashost.sh foo bar.home.arpa.`

## Remote Dynamic Updates

Remote clients can update DNS records with a shared key, e.g. for certbot DNS01 challenges.

Generate a tsig key
`tsig-keygen -a hmac-sha512 k8s-core-cert-manager >> /etc/bind/named.conf.tsigkeys`

Grant the tsig key access
`add-update-policy.sh "grant cert-manager name _acme-challenge.pinniped.home.arpa txt;"`

## Add all Proxmox VMs and Containers
On PVE Node:
```
PAIRS="$(./hostips)"
ssh -i /root/.ssh/vm ubuntu@${BIND_IP} "xargs -I{} -n2 addhost.sh <<< \"$PAIRS\""
```
