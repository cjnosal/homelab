#!/usr/bin/env bash
set -euo pipefail

sed -i.bk$(date +%s) "s/};/  $@\n};/" /etc/bind/named.conf.update-policy
sudo rndc reload