# Ambiente de desenvolvimento em container

Container Ubuntu 24.04 com todo o ferramental do projeto e o Claude Code
instalados. O repositório é montado em `/workspace`; nada do que o ambiente
precisa é instalado na máquina do host.

## Uso

```bash
./.devcontainer/dev shell     # sobe o container (constrói na 1ª vez) e abre um shell
./.devcontainer/dev claude    # abre o Claude Code dentro do container
./.devcontainer/dev up        # apenas sobe, sem entrar
./.devcontainer/dev exec <cmd>
./.devcontainer/dev build     # reconstrói a imagem do zero
./.devcontainer/dev down      # para e remove o container
./.devcontainer/dev nuke      # remove também os volumes de estado
```

No VS Code ou Cursor: **Reopen in Container** usa o mesmo `docker-compose.yml`
via `devcontainer.json`.

## O que está instalado

| Ferramenta | Uso no projeto |
|---|---|
| Terraform + tflint | Provisionamento e análise estática dos módulos |
| Ansible (metapacote) + ansible-lint | Configuração dos hosts; inclui `amazon.aws`, `ansible.posix`, `community.docker`, `community.crypto` |
| AWS CLI v2 | Credenciais e consultas à conta |
| gitleaks | Varredura de segredos exigida antes de todo PR |
| pre-commit | Ganchos de validação da Fase 0.1 |
| Claude Code | Assistente, rodando dentro do ambiente |
| `wireguard-tools`, `dig`, `nc`, `jq`, `git`, `ssh` | Validação manual dos hosts |

`boto3`/`botocore` já estão injetados no ambiente do Ansible, requisito dos
módulos `amazon.aws`.

## Primeiro acesso ao Claude Code

O login não vem do host por padrão: rode `claude` dentro do container e
autentique uma vez. A credencial fica no volume `claude-state` e sobrevive a
`dev down`, `dev up` e reconstruções da imagem — some apenas com `dev nuke`.

Para reaproveitar o login do host sem autenticar de novo, descomente em
`docker-compose.yml`:

```yaml
- ${HOME}/.claude/.credentials.json:/home/dev/.claude/.credentials.json
```

## Identidade e credenciais

O usuário do container é `dev`, com UID/GID iguais aos do host — arquivos
criados em `/workspace` pertencem ao seu usuário, sem `root` no meio do caminho.

Do host são montados:

| Caminho | Modo | Por quê |
|---|---|---|
| `~/.aws` | leitura e escrita | Perfil do `aws-cli`, conforme `docs/06-convencoes.md`; escrita permite `aws configure` e cache de SSO |
| `~/.ssh` | somente leitura | Chaves de acesso aos hosts; somente leitura evita alteração acidental a partir do container |
| `~/.gitconfig` | somente leitura | Autoria correta dos commits |

Como `~/.ssh` é somente leitura, o `ssh` não consegue gravar em `known_hosts` e
emite um aviso ao conectar a um host novo — a conexão funciona. O Ansible já
roda com `ANSIBLE_HOST_KEY_CHECKING=False`.

Essas montagens dão a qualquer processo do container acesso às suas credenciais
reais de AWS e SSH. É o que torna o ambiente utilizável para IaC; para uma
sessão sem esse acesso, comente as três linhas em `docker-compose.yml`.

## Estado preservado entre execuções

| Volume | Conteúdo |
|---|---|
| `claude-state` | Autenticação e configuração do Claude Code |
| `shell-history` | Histórico do bash |
| `terraform-plugin-cache` | Providers baixados, compartilhados entre ambientes |

## Docker dentro do container

Não vem habilitado. O Docker do projeto roda nos hosts gerenciados, via Ansible.
Para testar roles localmente com `molecule`, descomente a montagem do socket em
`docker-compose.yml` — ela concede ao container controle total sobre o Docker do
host.
