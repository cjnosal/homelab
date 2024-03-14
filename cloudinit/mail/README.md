# mail

## setup

```
./workspace/proxmox/preparevm --vmname mail --skip_userdata -- --disk 8
scp -r ./workspace/cloudinit/base ./workspace/cloudinit/mail \
  ubuntu@mail.home.arpa:/home/ubuntu/init
scp -r ./workspace/creds/step_root_ca.crt ./workspace/creds/step_intermediate_ca.crt ubuntu@mail.home.arpa:/home/ubuntu/init/certs
ssh ubuntu@mail.home.arpa sudo bash << EOF
/home/ubuntu/init/mail/runcmd --domain "home.arpa" --acme "https://step.home.arpa/acme/acme/directory" \
  --network 192.168.2.0/23 --nameserver 192.168.2.201 --ldap ldaps://ldap.home.arpa
EOF
```

### configure dns records
```
DKIM="$(ssh -o LogLevel=error ubuntu@mail.home.arpa bash << EOF
sudo cat /etc/opendkim/mail.txt | cut -d'(' -f2 | cut -d')' -f1 | xargs
EOF
)"

ssh ubuntu@bind.home.arpa bash << EOF
set -euo pipefail
sudo nsupdate -l -4 <<EOD
zone home.arpa
update add home.arpa. 60 MX 10 mail.home.arpa.
update add mail._domainkey.home.arpa 60 TXT $DKIM
update add home.arpa. 60 TXT "v=spf1 mx a ?all"
send
EOD

EOF
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