#!/usr/bin/env bash
# Executado NA instância EC2 pelo workflow deploy.yml (via SSH).
# Uso: deploy-ec2.sh <regiao-aws> <repositorio-ecr> <tag-da-imagem>
#
# A instância obtém permissão de leitura do ECR pela IAM Role associada a ela;
# nenhuma credencial da AWS é enviada pelo GitHub para cá.
set -euo pipefail

REGION="$1"
REPOSITORY="$2"
TAG="$3"

CONTAINER_NAME="devops-python-api"
HOST_PORT=80
CONTAINER_PORT=8000

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${REPOSITORY}:${TAG}"

echo ">> Autenticando o Docker no ECR (${REGISTRY})"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo ">> Baixando a imagem ${REPOSITORY}:${TAG}"
docker pull "$IMAGE"

echo ">> Substituindo o container anterior"
docker rm --force "$CONTAINER_NAME" 2>/dev/null || true

echo ">> Iniciando a nova versão"
docker run \
  --detach \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --publish "${HOST_PORT}:${CONTAINER_PORT}" \
  --env APP_COMMIT="$TAG" \
  "$IMAGE"

echo ">> Verificando se o container está em execução"
for attempt in $(seq 1 20); do
  running=$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME")
  if [ "$running" = "true" ] \
    && curl --fail --silent "http://127.0.0.1:${HOST_PORT}/health"; then
    echo
    docker ps --filter "name=^${CONTAINER_NAME}$"
    echo ">> Removendo imagens antigas para liberar disco"
    docker image prune --all --force > /dev/null
    echo ">> Deploy de ${TAG} concluído"
    exit 0
  fi
  echo "Tentativa ${attempt}: aplicação ainda não respondeu"
  sleep 2
done

echo "!! A aplicação não ficou saudável. Logs do container:"
docker logs "$CONTAINER_NAME" || true
exit 1
