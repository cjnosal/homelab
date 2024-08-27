#!/usr/bin/env bash
set -euo pipefail

docker build -f Dockerfile.auto1111 -t harbor.eng.home.arpa/library/auto1111:latest .
docker push harbor.eng.home.arpa/library/auto1111:latest