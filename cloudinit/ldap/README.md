# LDAP setup

Create an open LDAP server

## add DNS record
export IP=$(./workspace/proxmox/ips next)
see cloudinit/bind/README.md (done first because cloudinit includes certbot setup)

```
./workspace/cloudinit/ldap/generate.sh $IP
./workspace/proxmox/newvm jammy-cloudinit-4g ldap ldap.yml
```

## change the placeholder admin password!

```
HASH=$(slappasswd)
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// << E0F
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $HASH
E0F
```

## add users and groups
Convenience scripts write ldif files and invoke ldapadd/ldapmodify
```
sudo addldapgroup $cn
sudo addldapuser $uid $givenname $surname $email
sudo addldapsystem $uid $displayname
sudo addldapusertogroup $uid $cn
```

## set user temporary password

`ldappasswd -x -D cn=admin,dc=home,dc=arpa -W -S uid=$uid,ou=people,dc=home,dc=arpa`

User can self-serve change the password
`ldappasswd -x -D uid=$uid,ou=people,dc=home,dc=arpa -W -S uid=$uid,ou=people,dc=home,dc=arpa -H ldaps://ldap.home.arpa`

## verify
```
ldapsearch -x -H ldap://ldap.home.arpa "(uid=$uid)" entryUuid # plain
ldapsearch -x -ZZ -H ldap://ldap.home.arpa "(uid=$uid)" entryUuid # starttls
ldapsearch -x -H ldaps://ldap.home.arpa "(uid=$uid)" entryUuid # tls
```