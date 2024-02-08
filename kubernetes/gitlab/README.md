# Gitlab

Deploy the Gitlab source control to the core cluster

## Prereqs

Setup has dependencies on multiple personas

A single admin can run 
`./prereqs.sh -all --gitlab_admin $(whoami)`

If roles are split, each role can run their portion:
`./prereqs.sh -vault|ldap|keycloak|kubernetes`


## Deploy

Gitlab Admin
```
./deploy.sh
```

### Promote an admin

Syncing admins from LDAP is an enterprise edition feature
After a user has logged in, modify their db entry from the rails console:
```
kubectl -n gitlab exec -it deployment/gitlab-toolbox -- /srv/gitlab/bin/rails runner - <<EOF
user = User.find_by(username: "$(whoami)")
user.admin = true
user.save!
EOF
```

## Login

Browse to https://gitlab.eng.home.arpa

### Setup SSH key
```
ssh-keygen -t ssh-ed25519 -b 384 -C $(whoami)@gitlab.home.arpa -f ~/.ssh/gitlab-ssh
chmod 400 ~/.ssh/gitlab-ssh
```
Upload public key to https://gitlab.eng.home.arpa/-/profile/keys

## Admin console

### open console without entering pod
kubectl exec -it deployment/gitlab-toolbox -- /srv/gitlab/bin/rails console

### check the status of DB migrations
kubectl exec -it deployment/gitlab-toolbox -- /usr/local/bin/gitlab-rake db:migrate:status