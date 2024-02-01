# mail

## setup

```
export IP=$(./workspace/proxmox/ips next)
./workspace/cloudinit/mail/generate.sh $IP
./workspace/proxmox/newvm --vmname mail --userdata mail.yml --ip $IP
```

### set ldap passwords for default accounts
`ldappasswd -x -D uid=$(whoami),ou=people,dc=home,dc=arpa -W -s $secret -S uid=${uid},ou=people,dc=home,dc=arpa`

webmaster@home.arpa will receive mail sent to postmaster@ or abuse@
mailbot@home.arpa can be used as a service account to sent notifications
catchall@home.arpa will recieve mail for any nonexistent accounts

### log in to thunderbird

Account Settings > Add Mail Account

## testing

### dovecot+ldap
doveadm user
doveadm auth lookup
doveadm auth login

### postfix+ldap
swaks --to $recipient --server mail.home.arpa:25 --tls --from $sender --auth-user $sender --auth-password $password

### opendkim
opendkim-testkey -d home.arpa -s mail -k /etc/opendkim/mail.private -v

### spam training

sa-learn ham --progress $inboxfolder
sa-learn spam --progress $spamfolder