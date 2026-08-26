# Ambiente de desenvolvimento em container

Container Ubuntu 24.04 com todo o ferramental do projeto e o Claude Code
instalados. O repositório é montado em `/workspace`; nada do que o ambiente
precisa é instalado na máquina do host.

## Uso

```bash
./.devcontainer/dev shell     # sobe o container (constrói na 1ª vez) e abre um shell
./.devcontainer/dev claude    # abre o Claude Code dentro do container
./.devcontainer/dev up        # apenas sobe, sem entrar
./.devcontainer/dev key       # mostra a chave pública deploy-key-github
./.devcontainer/dev exec <cmd>
./.devcontainer/dev manual    # converte docs/manual/*.docx em PDF
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
| LibreOffice (headless) | Converte os capítulos `.docx` do manual em PDF legível |
| `wireguard-tools`, `dig`, `nc`, `jq`, `git`, `ssh` | Validação manual dos hosts |

## Capítulos do manual

Os `.docx` de `docs/manual/` não são legíveis por ferramenta de texto. O comando
`dev manual` converte todos em PDF ao lado dos originais, preservando imagens e
blocos de código. O diretório inteiro é gitignored — conteúdo de terceiros.

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

## Isolamento

O container não enxerga nenhum caminho do host além do próprio repositório,
montado em `/workspace`. Não há montagem de `~/.ssh`, `~/.aws` ou `~/.gitconfig`:
uma credencial que não pertence a este projeto não existe aqui dentro.

A única informação repassada do host é o nome e o e-mail de autoria dos commits,
lidos pelo script `dev` com `git config --get` e entregues como variável de
ambiente.

## Chave SSH

Na primeira subida, o container gera a própria chave — `deploy-key-github`,
ed25519, sem passphrase — e a guarda no volume `ssh-keys`. Ela sobrevive a
`dev down`, `dev up` e reconstruções da imagem; some apenas com `dev nuke`, e aí
uma nova precisa ser cadastrada.

```bash
./.devcontainer/dev key      # mostra a chave pública
```

Cadastre-a no GitHub em **Settings → Deploy keys → Add deploy key** do
repositório, marcando *Allow write access* se for fazer push a partir do
container. A deploy key vale para um repositório só — é exatamente o escopo
desejado.

O remote precisa ser SSH para a chave ser usada:

```bash
git remote add origin git@github.com:<usuario>/<repo>.git
```

O `~/.ssh/config` do container aponta essa chave para o `github.com` com
`IdentitiesOnly yes`, e o `known_hosts` já vem com a chave pública do servidor do
GitHub fixada, o que dispensa a confirmação interativa da primeira conexão.

Para acessar os hosts da infraestrutura, gere um par próprio dentro do container
(`ssh-keygen -t ed25519 -f ~/.ssh/<nome>`) e registre a pública no Terraform.
Chaves do host não entram aqui.

## Credenciais AWS

O volume `aws-config` nasce vazio. Configure dentro do container, uma vez:

```bash
./.devcontainer/dev exec aws configure
```

Use um usuário IAM dedicado a este projeto, com as permissões que ele realmente
precisa — não as suas credenciais de uso geral. `docs/06-convencoes.md` já define
que credencial AWS vive no perfil do `aws-cli` e nunca no código.

## Estado preservado entre execuções

| Volume | Conteúdo |
|---|---|
| `ssh-keys` | A chave `deploy-key-github` e a configuração do SSH |
| `aws-config` | Perfil do `aws-cli` do projeto |
| `claude-state` | Autenticação e configuração do Claude Code |
| `shell-history` | Histórico do bash |
| `terraform-plugin-cache` | Providers baixados, compartilhados entre ambientes |

## Docker dentro do container

Não há socket do Docker montado. O Docker do projeto roda nos hosts gerenciados,
via Ansible; montar o socket do host daria ao container controle total sobre ele,
o que contraria o isolamento descrito acima.
