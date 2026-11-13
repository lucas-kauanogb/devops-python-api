# Configuração da AWS e do GitHub (etapas 4, 5 e 6)

O projeto foi implantado em uma conta **AWS Academy (Learner Lab)**, região **`us-east-1`**. Esse ambiente não permite criar usuários, políticas ou roles no IAM, então foram usados os recursos que o laboratório já oferece: credenciais temporárias da sessão e a role `LabRole`.

| Recurso | Nome usado | Para quê |
|---|---|---|
| Repositório ECR (privado) | `devops-ceub/lucas` | Guardar as imagens Docker |
| Credenciais temporárias do Lab | AWS Details → AWS CLI | GitHub Actions enviar imagens ao ECR |
| IAM Role da instância | `LabRole` (instance profile `LabInstanceProfile`) | EC2 baixar imagens do ECR sem chaves |
| Key pair | `vockey` (`labsuser.pem`) | Acesso SSH da pipeline à EC2 |
| Security group | regras 22 e 80 | Liberar SSH e HTTP |
| Instância EC2 | `vm-deploy` (Ubuntu, `t3.micro`) | Executar o container |

---

## 1. Repositório no Amazon ECR

Console → **Elastic Container Registry** → **Create repository** → visibilidade **Private**, nome `devops-ceub/lucas`.

## 2. Instância EC2

**EC2 → Launch instance**:

- Name: `vm-deploy`
- AMI: **Ubuntu Server**
- Instance type: `t3.micro`
- Key pair: `vockey`
- Security group com as regras de entrada:

  | Tipo | Porta | Origem | Motivo |
  |---|---|---|---|
  | SSH | 22 | `0.0.0.0/0` | Deploy pelos runners do GitHub (IPs variáveis); acesso somente com a chave privada |
  | HTTP | 80 | `0.0.0.0/0` | Acesso público à API |

- Advanced details → **IAM instance profile**: `LabInstanceProfile`

Em uma instância já criada, a role pode ser associada em **Actions → Security → Modify IAM role**.

## 3. Preparação do servidor (uma única vez)

Via SSH ou **Connect → EC2 Instance Connect**, execute o conteúdo de [`scripts/ec2-user-data.sh`](../scripts/ec2-user-data.sh):

```bash
sudo apt-get update
sudo apt-get install -y docker.io awscli
sudo systemctl enable --now docker
sudo usermod -aG docker ubuntu
```

Depois de reconectar, a verificação esperada é:

```bash
docker ps                     # tabela vazia, sem erro de permissão
aws sts get-caller-identity   # ARN contendo assumed-role/LabRole
```

Essa preparação não faz parte do deploy: as atualizações da aplicação são feitas apenas pela pipeline.

## 4. Secrets e variáveis no GitHub

**Settings → Secrets and variables → Actions**, todos em nível de repositório.

**Secrets**:

| Nome | Origem do valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | Learner Lab → AWS Details → AWS CLI → Show |
| `AWS_SECRET_ACCESS_KEY` | idem |
| `AWS_SESSION_TOKEN` | idem |
| `EC2_SSH_KEY` | Conteúdo completo de `labsuser.pem` (Learner Lab → AWS Details → Download PEM) |

**Variables**:

| Nome | Valor |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `devops-ceub/lucas` |
| `EC2_HOST` | IP público da `vm-deploy` |
| `EC2_USER` | `ubuntu` |

## 5. A cada nova sessão do Learner Lab

As credenciais da sessão expiram e a instância recebe outro IP ao ser religada. Antes de executar a pipeline:

1. Atualizar `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`.
2. Atualizar `EC2_HOST` com o novo IP público.

## 6. Problemas encontrados e soluções

| Erro na pipeline | Causa | Solução |
|---|---|---|
| `Input required and not supplied: aws-region` | Variáveis criadas em um Environment não usado pelo job | Criar as variáveis em nível de repositório |
| `The security token included in the request is invalid` | Faltava o session token das credenciais temporárias | Adicionar `aws-session-token` ao workflow e o secret `AWS_SESSION_TOKEN` |
| `Load key ...: error in libcrypto` | Secret salvo com outro nome (`EC2_SSH_PRIVATE_KEY`), chegando vazio | Criar o secret com o nome exato `EC2_SSH_KEY` |
| `aws: command not found` | Ubuntu não traz o AWS CLI | Instalar `awscli` na preparação do servidor |

## 7. Limpeza ao final da avaliação

1. **EC2** → Terminate a instância `vm-deploy`.
2. **ECR** → apagar o repositório `devops-ceub/lucas` com as imagens.
3. **GitHub** → remover os Secrets.
