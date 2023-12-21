# LDAP setup

Create an open LDAP server

## add DNS record
export IP=$(./workspace/ips next)
see cloudinit/bind/README.md (done first because cloudinit includes certbot setup)

```
./workspace/cloudinit/ldap/generate.sh $IP
./workspace/newvm jammy-cloudinit-4g ldap ldap.yml
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
sudo ldapadd -H ldapi:/// -f /run/user.ldif -W  -x -D cn=admin,dc=home,dc=arpa

## set user password

ldappasswd -x -D cn=admin,dc=home,dc=arpa -W -S uid=conor,ou=people,dc=home,dc=arpa

## verify

ldapsearch -x -H ldap://ldap2.home.arpa "(uid=conor)" entryUuid # plain
ldapsearch -x -ZZ -H ldap://ldap2.home.arpa "(uid=conor)" entryUuid # starttls
ldapsearch -x -H ldaps://ldap2.home.arpa "(uid=conor)" entryUuid # tls