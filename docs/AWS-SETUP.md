# Configuração da AWS e do GitHub (etapas 4, 5 e 6)

Este guia cria, pelo Console da AWS, tudo o que o `deploy.yml` precisa. Use **a mesma região** em todos os passos (exemplo: `us-east-1`).

Visão geral do que será criado:

| Recurso | Nome sugerido | Para quê |
|---|---|---|
| Repositório ECR (privado) | `devops-python-api` | Guardar as imagens Docker |
| Usuário IAM | `github-actions-devops` | Credenciais do GitHub Actions para **enviar** imagens ao ECR |
| IAM Role | `ec2-ecr-readonly` | Permitir que a EC2 **baixe** imagens do ECR (sem chaves) |
| Key pair | `devops-python-api-key` | Acesso SSH seguro da pipeline à EC2 |
| Security group | `devops-python-api-sg` | Liberar portas 22 (SSH) e 80 (HTTP) |
| Instância EC2 | `devops-python-api` | Executar o container |

---

## 1. Repositório no Amazon ECR

1. Console → **Elastic Container Registry** → **Create repository**.
2. Visibility: **Private**. Name: `devops-python-api`.
3. Deixe o restante no padrão e clique em **Create**.

## 2. Usuário IAM para o GitHub Actions

O GitHub só precisa **enviar** imagens para esse repositório, então a política é restrita a isso.

1. **IAM → Policies → Create policy → JSON** e cole (troque `REGIAO` e `ID_DA_CONTA`):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "LoginNoEcr",
         "Effect": "Allow",
         "Action": "ecr:GetAuthorizationToken",
         "Resource": "*"
       },
       {
         "Sid": "PushNoRepositorio",
         "Effect": "Allow",
         "Action": [
           "ecr:BatchCheckLayerAvailability",
           "ecr:BatchGetImage",
           "ecr:CompleteLayerUpload",
           "ecr:GetDownloadUrlForLayer",
           "ecr:InitiateLayerUpload",
           "ecr:PutImage",
           "ecr:UploadLayerPart"
         ],
         "Resource": "arn:aws:ecr:REGIAO:ID_DA_CONTA:repository/devops-python-api"
       }
     ]
   }
   ```

   Nome da política: `github-actions-ecr-push`.

2. **IAM → Users → Create user** → `github-actions-devops` (sem acesso ao console) → **Attach policies directly** → marque `github-actions-ecr-push`.
3. Abra o usuário → **Security credentials → Create access key** → caso de uso *Application running outside AWS*.
4. Copie o **Access key ID** e o **Secret access key**. Eles vão **somente** para os Secrets do GitHub (passo 7), nunca para arquivos do repositório.

## 3. IAM Role da instância EC2

1. **IAM → Roles → Create role**.
2. Trusted entity: **AWS service** → Use case: **EC2**.
3. Permissions: marque **`AmazonEC2ContainerRegistryReadOnly`**.
4. Nome: `ec2-ecr-readonly` → **Create role**.

Com essa role, a instância obtém credenciais temporárias automaticamente e consegue executar `aws ecr get-login-password` e `docker pull`, sem nenhuma chave salva no servidor.

## 4. Key pair (SSH)

1. **EC2 → Key pairs → Create key pair** → nome `devops-python-api-key`, tipo **ED25519** (ou RSA), formato **.pem**.
2. O arquivo `.pem` é baixado uma única vez. Guarde-o: o conteúdo dele vai para o secret `EC2_SSH_KEY`.

## 5. Security group

**EC2 → Security groups → Create security group** → `devops-python-api-sg`, regras de entrada:

| Tipo | Porta | Origem | Motivo |
|---|---|---|---|
| SSH | 22 | `0.0.0.0/0` | Deploy pelos runners do GitHub (IPs variáveis); acesso somente com a chave privada |
| HTTP | 80 | `0.0.0.0/0` | Acesso público à API |

> O SSH aceita apenas autenticação por chave no Amazon Linux (senha desabilitada). Como os runners do GitHub não têm IP fixo, a porta 22 precisa ficar aberta; por isso a chave privada fica somente nos Secrets.

## 6. Instância EC2

**EC2 → Launch instance**:

- Name: `devops-python-api`
- AMI: **Amazon Linux 2023**
- Instance type: `t3.micro` ou `t2.micro` (free tier)
- Key pair: `devops-python-api-key`
- Network settings → **Select existing security group** → `devops-python-api-sg`; Auto-assign public IP: **Enable**
- Advanced details → **IAM instance profile**: `ec2-ecr-readonly`
- Advanced details → **User data**: cole o conteúdo de [`scripts/ec2-user-data.sh`](../scripts/ec2-user-data.sh) (instala e inicia o Docker)

Após alguns minutos, confira (opcional, apenas para validar a instalação):

```bash
ssh -i devops-python-api-key.pem ec2-user@IP_PUBLICO
docker --version
systemctl is-active docker
aws sts get-caller-identity   # deve mostrar a role ec2-ecr-readonly
```

> Se a instância for parada e iniciada, o IP público muda. Atualize a variável `EC2_HOST` ou associe um **Elastic IP**.

## 7. Secrets e variáveis no GitHub

No repositório: **Settings → Secrets and variables → Actions**.

Aba **Secrets** (valores sensíveis, nunca aparecem nos logs):

| Nome | Valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | Access key do usuário `github-actions-devops` |
| `AWS_SECRET_ACCESS_KEY` | Secret key do usuário `github-actions-devops` |
| `EC2_SSH_KEY` | Conteúdo completo do arquivo `.pem` (incluindo as linhas `-----BEGIN ...` e `-----END ...`) |

Aba **Variables** (valores não sensíveis):

| Nome | Exemplo |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `devops-python-api` |
| `EC2_HOST` | IP público ou DNS público da instância |
| `EC2_USER` | `ec2-user` |

Recomendado: **Settings → Branches → Add branch ruleset** (ou *branch protection rule*) para a `main`, exigindo Pull Request e o status check **Qualidade e testes** aprovado antes do merge. Assim, um PR com teste falhando não chega à `main` e, portanto, não é implantado.

## 8. Primeiro deploy

Faça o merge do Pull Request na `main` (ou rode **Actions → Deploy na EC2 → Run workflow**). Ao final:

```bash
curl http://IP_PUBLICO/health
curl http://IP_PUBLICO/version
```

## 9. Limpeza ao final da avaliação

Para evitar cobranças:

1. **EC2** → Terminate a instância; libere o Elastic IP, se tiver criado.
2. **ECR** → apague o repositório `devops-python-api` (com as imagens).
3. **IAM** → desative/apague a access key e o usuário `github-actions-devops`; apague a role e a política, se quiser.
4. **GitHub** → remova os Secrets.
