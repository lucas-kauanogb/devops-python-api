#!/bin/bash
# Preparação da instância EC2 Ubuntu (executar uma única vez).
# Pode ser colado em "Advanced details > User data" ao criar a instância,
# ou executado via SSH / EC2 Instance Connect com sudo.
set -euxo pipefail

apt-get update
apt-get install -y docker.io awscli
systemctl enable --now docker

# Permite que o usuário ubuntu (usado pelo deploy via SSH) execute docker sem sudo.
usermod -aG docker ubuntu
