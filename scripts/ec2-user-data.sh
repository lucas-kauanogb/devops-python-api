#!/bin/bash
# User data para a instância EC2 (Amazon Linux 2023).
# Cole este conteúdo em "Advanced details > User data" ao criar a instância.
# Ele roda uma única vez, no primeiro boot, como root.
set -euxo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker

# Permite que o ec2-user (usado pelo deploy via SSH) execute docker sem sudo.
usermod -aG docker ec2-user

# O AWS CLI v2 já vem instalado no Amazon Linux 2023 e usa a IAM Role da instância.
