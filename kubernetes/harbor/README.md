# Harbor

Deploy the Harbor container registry to the core cluster

## Prereqs

Setup has dependencies on multiple personas

A single admin can run 
`./prereqs.sh -all --harbor_admin $(whoami)`

If roles are split, each role can run their portion:
`./prereqs.sh -dns|ldap|vault|kubernetes`


## Deploy

Harbor Admin
```
./deploy.sh
```

## Login
```
docker login harbor.eng.home.arpa
```