# devops-python-api — CI/CD com GitHub Actions, Docker, Amazon ECR e EC2

API HTTP de tarefas escrita em Python (FastAPI), usada para demonstrar uma esteira completa de integração e entrega contínua:

**alteração no código → branch → Pull Request → testes automatizados → merge na main → build Docker → publicação no ECR → deploy na EC2 → aplicação atualizada.**

Os dados ficam em memória para manter o foco no fluxo DevOps, sem banco de dados.

## API publicada

| Recurso | Endereço |
|---|---|
| API | `http://<IP_PUBLICO_EC2>/` |
| Versão implantada | `http://<IP_PUBLICO_EC2>/version` |
| Saúde | `http://<IP_PUBLICO_EC2>/health` |
| Documentação Swagger | `http://<IP_PUBLICO_EC2>/docs` |

> Substitua `<IP_PUBLICO_EC2>` pelo IP ou DNS público da instância.

## Tecnologias utilizadas

| Ferramenta | Uso no projeto |
|---|---|
| Python 3.13 + FastAPI + Uvicorn | Aplicação e servidor HTTP |
| pytest + pytest-cov + httpx2 | Testes automatizados e cobertura (mínimo de 90%) |
| Ruff | Análise estática e formatação |
| Git + GitHub (branches e Pull Requests) | Versionamento e revisão |
| GitHub Actions | Pipelines de CI (`ci.yml`) e CD (`deploy.yml`) |
| Docker | Empacotamento e execução da aplicação |
| Amazon ECR | Registro privado das imagens |
| Amazon EC2 (Amazon Linux 2023) | Servidor que executa o container |
| AWS IAM (usuário + role) | Permissões mínimas, sem credenciais no código |

## Estrutura do repositório

```text
.
├── .github/workflows/
│   ├── ci.yml                 # CI: valida Pull Requests (lint, testes, build do container)
│   └── deploy.yml             # CD: testes → build → push no ECR → deploy na EC2
├── app/
│   ├── __init__.py
│   └── main.py                # API FastAPI
├── docs/
│   ├── API.md
│   ├── AWS-SETUP.md           # passo a passo de ECR, IAM, EC2 e Secrets
│   ├── DOCKER.md
│   ├── GITHUB-ACTIONS.md
│   └── evidencias/            # capturas de tela da entrega
├── scripts/
│   ├── deploy-ec2.sh          # executado na EC2 pela pipeline de deploy
│   └── ec2-user-data.sh       # instala o Docker no primeiro boot da EC2
├── tests/test_api.py          # testes automatizados
├── .dockerignore
├── .python-version
├── compose.yaml
├── Dockerfile
├── pyproject.toml             # configuração de pytest, cobertura e Ruff
└── requirements.txt           # dependências da aplicação e dos testes
```

## Endpoints

| Método | Caminho | Objetivo | Resposta esperada |
|---|---|---|---|
| GET | `/` | Apresentar a API | `200` |
| GET | `/health` | Informar saúde e versão | `200` |
| GET | `/version` | Informar versão e commit implantado | `200` |
| GET | `/tasks` | Listar tarefas | `200` |
| POST | `/tasks` | Criar uma tarefa | `201` |
| PATCH | `/tasks/{id}/done` | Concluir uma tarefa | `200` ou `404` |

## 1. Execução local

Pré-requisitos: Git e Python 3.13.

### Linux e macOS

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --requirement requirements.txt
uvicorn app.main:app --reload
```

### Windows PowerShell

```powershell
py -3.13 -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --requirement requirements.txt
uvicorn app.main:app --reload
```

Acesse <http://localhost:8000>, <http://localhost:8000/docs> e <http://localhost:8000/version>.

Verificações locais (as mesmas executadas pela CI):

```bash
ruff check .
ruff format --check .
pytest --cov=app --cov-report=term-missing
```

## 2. Docker

Construir e executar a imagem localmente:

```bash
docker build -t devops-python-api:local .
docker run --rm -d -p 8000:8000 --name devops-python-api devops-python-api:local
curl http://localhost:8000/health
docker ps
docker logs devops-python-api
docker stop devops-python-api
```

Ou com Docker Compose: `docker compose up --build`.

O `Dockerfile` usa `python:3.13-slim`, instala as dependências de `requirements.txt` durante o build, copia apenas o diretório `app`, executa como usuário sem privilégios, expõe a porta `8000`, define um `HEALTHCHECK` em `/health` e inicia a API com `uvicorn app.main:app --host 0.0.0.0 --port 8000`.

## 3. Pipeline de integração contínua (`ci.yml`)

Acionada automaticamente quando um Pull Request para a `main` é aberto ou atualizado (e manualmente pela aba Actions).

| Job | Steps |
|---|---|
| **Qualidade e testes** | checkout → setup do Python 3.13 (com cache do pip) → `pip install -r requirements.txt` → `ruff check` → `ruff format --check` → `pytest` com cobertura → upload dos relatórios (JUnit e cobertura) |
| **Build e teste do container** (`needs` do job anterior) | `docker build` → `docker run` → chamada a `/health` → logs → remoção do container |

O resultado aparece no próprio Pull Request (✔ ou ✖). Com a regra de proteção da `main` exigindo a CI aprovada, um PR com testes falhando não pode ser mergeado.

## 4. Pipeline de entrega contínua (`deploy.yml`)

Acionada a cada push na `main`, ou seja, após o merge de um Pull Request aprovado.

```text
tests ──▶ build-and-push ──▶ deploy
```

1. **`tests`** — reutiliza o `ci.yml` (`workflow_call`): exatamente os mesmos testes do PR. **Se falharem, os jobs seguintes não executam.**
2. **`build-and-push`** — autentica na AWS com as credenciais dos GitHub Secrets, faz login no ECR, constrói a imagem e a publica com duas tags: o **SHA do commit** (imutável, rastreável) e `latest`.
3. **`deploy`** — abre uma conexão SSH com a EC2 usando a chave guardada em Secret e executa [`scripts/deploy-ec2.sh`](scripts/deploy-ec2.sh), que:
   1. autentica o Docker da instância no ECR usando a **IAM Role** da EC2;
   2. baixa a imagem com a tag do commit;
   3. remove o container anterior;
   4. inicia o novo container (`-p 80:8000`, `--restart unless-stopped`, `APP_COMMIT=<sha>`);
   5. verifica se o container está em execução e respondendo em `/health`.

   Por fim, o runner chama `http://<EC2>/version` e confere se o commit em produção é o que acabou de ser publicado.

Nenhum comando manual é executado na instância após cada alteração.

### Segredos e permissões

| Onde | Nome | Conteúdo |
|---|---|---|
| GitHub Secret | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Usuário IAM com permissão **apenas de push** no repositório ECR |
| GitHub Secret | `EC2_SSH_KEY` | Chave privada do key pair da EC2 |
| GitHub Variable | `AWS_REGION`, `ECR_REPOSITORY`, `EC2_HOST`, `EC2_USER` | Configuração não sensível |
| IAM Role da EC2 | `AmazonEC2ContainerRegistryReadOnly` | Leitura do ECR sem chaves na instância |

Nenhuma senha, token ou chave está versionada no repositório. O passo a passo completo está em [docs/AWS-SETUP.md](docs/AWS-SETUP.md).

## 5. Arquitetura de implantação

```text
 Desenvolvedor                         GitHub                                   AWS
┌─────────────┐  push branch   ┌──────────────────────┐
│ feature/... │ ─────────────▶ │ Pull Request → main  │
└─────────────┘                │   ci.yml (testes)    │
                               └──────────┬───────────┘
                                          │ merge
                               ┌──────────▼───────────┐   docker push   ┌──────────────────┐
                               │ deploy.yml           │ ──────────────▶ │ Amazon ECR       │
                               │ tests → build → push │                 │ (repo privado)   │
                               │ → deploy (SSH)       │                 └────────┬─────────┘
                               └──────────┬───────────┘                          │ docker pull
                                          │ SSH (chave em Secret)                │ (IAM Role)
                                          │                         ┌────────────▼─────────┐
                                          └───────────────────────▶ │ EC2 Amazon Linux     │
                                                                    │ container :80→:8000  │
                                                                    └────────────┬─────────┘
                                                                                 │ HTTP :80
                                                                            Usuário / navegador
```

## 6. Como verificar a versão implantada

```bash
curl http://<IP_PUBLICO_EC2>/version
# {"version":"1.0.0","commit":"<sha-do-commit>"}
```

- `version` é a versão declarada em `app/main.py`.
- `commit` é o SHA do commit da `main` que gerou a imagem; deve coincidir com o último commit da `main` e com a tag da imagem no ECR.

Também é possível conferir na instância (somente leitura): `docker ps` mostra a imagem `.../devops-python-api:<sha>` em execução.

## 7. Demonstração de atualização automática

| | Versão 1 | Versão 2 |
|---|---|---|
| Pull Request | `<link do PR #1>` | `<link do PR #2>` |
| Commit | `<sha 1>` | `<sha 2>` |
| `GET /version` | `{"version":"1.0.0", ...}` | `{"version":"1.1.0", ...}` |

A versão 2 foi produzida apenas com branch → PR → merge; o deploy na EC2 ocorreu sozinho pela pipeline.

## 8. Evidências

| Evidência | Arquivo |
|---|---|
| CI executada com sucesso no Pull Request | `docs/evidencias/01-ci-pr.png` |
| Imagem publicada no ECR com a tag do commit | `docs/evidencias/02-ecr-imagem.png` |
| Pipeline de deploy concluída | `docs/evidencias/03-deploy-pipeline.png` |
| Container em execução na EC2 (`docker ps`) | `docs/evidencias/04-ec2-docker-ps.png` |
| API acessível pelo navegador | `docs/evidencias/05-api-navegador.png` |
| Versão 1 e versão 2 em `/version` | `docs/evidencias/06-versao-1.png`, `docs/evidencias/07-versao-2.png` |

Execuções das pipelines: aba **Actions** do repositório.

## Referências

- [GitHub Actions: criar e testar Python](https://docs.github.com/pt/actions/tutorials/build-and-test-code/building-and-testing-python)
- [Reutilizando workflows](https://docs.github.com/pt/actions/sharing-automations/reusing-workflows)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
- [aws-actions/amazon-ecr-login](https://github.com/aws-actions/amazon-ecr-login)
- [Amazon ECR: enviar imagens](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html)
- [FastAPI](https://fastapi.tiangolo.com/)
