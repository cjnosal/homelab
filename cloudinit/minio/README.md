# Minio storage

# Access 

https://minio.home.arpa:9000


## Install CLI
sudo wget --progress=dot:giga https://dl.min.io/client/mc/release/linux-amd64/mc \
  -O /usr/local/bin/mc

sudo chmod +x /usr/local/bin/mc

Login:



## Configure cli:
1) use ldap credentials to authorize a new access key
    `mc idp ldap accesskey create --login https://minio.home.arpa:9000`
2) configure the endpoint and credentials
    `mc alias set minio https://minio.home.arpa:9000`


# Admin

Add to ldap group minio-admin is bound to policy consoleAdmin

mc idp ldap policy attach minio --group="${groupdn}" consoleAdmin

## view debug logs
mc admin trace -a -v minio --node minio.home.arpa:9000