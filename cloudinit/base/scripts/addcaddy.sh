#!/usr/bin/env bash
set -euo pipefail

help_this="install caddy"

source /usr/local/include/argshelper
parseargs $@

curl -fSsL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -fSsL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --force-yes caddy

rm /usr/share/caddy/index.html