#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd $(dirname $0) && pwd)

pushd ${SCRIPT_DIR}

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: loki
  labels:
    name: loki
    smallstep.com/inject: enabled
EOF

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

SECRET_KEY=$(generatecred)
ACCESS_KEY=$(generatecred --length 20)
lokicred=$(cat /home/ubuntu/init/creds/loki.passwd)
s3=minio.home.arpa:9000

cat > login.exp << EOF
#!/usr/bin/env expect
set timeout 30
log_user 0
spawn mc idp ldap accesskey create-with-login https://minio.home.arpa:9000 --name bucket --access-key [lindex \$argv 2] --secret-key [lindex \$argv 3] --description [lindex \$argv 4]

expect "Enter LDAP Username:" {
    send "[lindex \$argv 0]\r";
  }
expect "Enter LDAP Password:" {
    send "[lindex \$argv 1]\r"
}
expect eof
lassign [wait] pid spawn_id os_error actual_exit_code
if {\$actual_exit_code != 0} {
    puts "failed to create access key: \$os_error \$actual_exit_code"
}
exit \$actual_exit_code
EOF
chmod a+rx login.exp
./login.exp loki ${lokicred} ${ACCESS_KEY} ${SECRET_KEY} "bootstrapped loki system creds at $(date)"

# verify
mc alias set minio https://${s3} ${ACCESS_KEY} ${SECRET_KEY}

kapp deploy -y -a authelia-traefik -f- <<EOF
---
apiVersion: 'traefik.containo.us/v1alpha1'
kind: 'Middleware'
metadata:
  name: 'forwardauth-authelia' 
  namespace: 'loki' 
  labels:
    app.kubernetes.io/instance: 'authelia'
    app.kubernetes.io/name: 'authelia'
spec:
  forwardAuth:
    address: 'https://authelia.home.arpa:9091/api/verify?auth=basic'
    tls:
      caSecret: home.arpa
    authResponseHeaders:
      - 'Remote-User'
      - 'Remote-Groups'
      - 'Remote-Email'
      - 'Remote-Name'
EOF

ytt -f ${SCRIPT_DIR}/secrets.yml \
  -v accessKeyId="${ACCESS_KEY}" \
  -v secretKey="${SECRET_KEY}" \
  | kubectl apply -n loki -f-

if ! helm upgrade --install  --values ${SCRIPT_DIR}/values.yml loki grafana/loki -n loki --wait --timeout 300s \
  --set-string loki.storage.s3.endpoint=${s3} \
  --version 6.5.2
then
  echo loki exited with code $?
  exit 1
fi

# wait for external-dns
while [[ -z "$(dig -4 loki.eng.home.arpa @bind.home.arpa +noall +answer)" ]]
do
	echo waiting for dns
	sleep 2
done

while ! curl -fSsL https://loki.eng.home.arpa
do
	echo waiting for loki
	sleep 2
done