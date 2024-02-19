#!/usr/bin/env bash
set -euo pipefail

sed -i.bk$(date +%s) "s/};/  $@\n};/" /etc/bind/named.conf.allow-transfer
sudo rndc reload