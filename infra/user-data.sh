#!/usr/bin/env bash
set -euo pipefail

exec > >(tee /var/log/farmable-bootstrap.log | logger -t farmable-bootstrap -s 2>/dev/console) 2>&1

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git unzip
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

install -d -m 0750 /opt/farmable
install -d -m 0750 /var/lib/farmable
echo 'Farmable host bootstrap complete; deployment workflow will populate /opt/farmable.' > /opt/farmable/README
