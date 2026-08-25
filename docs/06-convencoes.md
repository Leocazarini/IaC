# 06 — Convenções

## Idioma

| Onde | Idioma |
|---|---|
| Identificadores, nomes de recurso, variáveis, roles, arquivos | Inglês |
| Comentários de código | pt-BR |
| Documentação (`docs/`, READMEs, PRs, commits) | pt-BR |

---

## Comentários de código

Esta é a convenção mais fácil de violar por descuido, e a mais importante para a
legibilidade a longo prazo.

**Um comentário de código descreve o que aquilo faz, em estilo instrutivo.** Ele
não conta a história do projeto.

**Proibido em `.tf`, `.yml`, `.sh`, `.cfg`:**

- Referência ao manual: `# cap 09`, `# conforme o manual`, `# ver capítulo 7`
- Referência a fase: `# na Fase 6`, `# implementado na camada 3`
- Narrativa de andamento: `# por enquanto`, `# depois a gente melhora`, `# TODO`
- Justificativa histórica: `# mudamos isso porque antes dava erro`

**Único marcador de futuro permitido:** `(implementação na próxima fase)`

```hcl
# ✗ errado
# Conforme o cap 09 do manual, o firewall do provedor fica permissivo
# porque o firewall real é o do host (ver Fase 6)
resource "aws_security_group" "app" { }

# ✓ certo
# Regras de entrada do host de aplicação.
# Mínimo: SSH apenas da rede WireGuard | Recomendado: 80/443 apenas dos ranges Cloudflare
resource "aws_security_group" "app" { }
```

O estilo instrutivo `Mínimo: X | Recomendado: Y` é útil onde há uma escolha de
configuração: informa quem lê qual é o piso e qual é o alvo.

**Toda a racionalização vai para `docs/`**: o mapa do manual, as citações de
capítulo, as decisões, a tradução para AWS, o modelo de perímetro. O código diz
*o quê*; `docs/camadas/camada-N-*.md` diz *por quê*.

---

## Nomenclatura

### Hostname

```
[ambiente]-[função]-[local]-[número]
```

Exemplos: `lab-bastion-use1-01` · `lab-app-use1-01`

Parametrizado em variável, nunca escrito diretamente no recurso.

### Recursos Terraform

Nome do recurso descreve a função, não o tipo — o tipo já está no bloco:

```hcl
resource "aws_subnet" "public"   { }   # ✓
resource "aws_subnet" "subnet_1" { }   # ✗ não diz nada
```

### Roles Ansible

Uma role por preocupação, nome no singular e em inglês: `base`, `ssh_hardening`,
`nat`, `wireguard`, `firewall`, `crowdsec`, `docker`, `traefik`.

---

## Tags AWS

Obrigatórias em todo recurso que aceite tags:

| Tag | Valor | Uso |
|---|---|---|
| `Project` | `vps-infra` | Filtrar custo e recursos do projeto |
| `Env` | `lab` | Separar ambientes |
| `Phase` | `c1f2` | Rastrear qual fase criou o recurso |
| `ManagedBy` | `terraform` | Distinguir do que foi criado à mão |

Aplicadas via `default_tags` no provider, para não repetir em cada recurso.

---

## Ansible

### Idempotência é requisito, não meta

Toda role deve retornar `changed=0` na segunda execução consecutiva. Uma role que
não é idempotente é um bug, não uma limitação — a promessa do projeto depende de
poder reaplicar o playbook a qualquer momento sem consequências.

Implicações práticas:

- `command` e `shell` só com `creates:`, `removes:` ou `changed_when:` explícito.
- Preferir módulos declarativos (`ansible.builtin.lineinfile`, `template`,
  `service`) a scripts imperativos.
- `changed_when: false` em tarefas puramente de leitura.

### Variáveis

Nunca valor fixo dentro de uma task. Tudo em `group_vars/` ou `defaults/main.yml`
da role:

```yaml
# ✗ errado
- name: Configure SSH port
  lineinfile:
    line: "Port 22022"

# ✓ certo
- name: Configure SSH port
  lineinfile:
    line: "Port {{ ssh_port }}"
```

### Handlers

Reinício de serviço via handler, nunca task direta — evita reiniciar sem
necessidade e mantém a idempotência.

---

## Terraform

- **Módulos com contrato fixo de outputs.** Ver o contrato anti-lock-in em
  [`02-arquitetura.md`](./02-arquitetura.md). Nada fora de
  `modules/compute-aws/` referencia um recurso AWS.
- **Nenhum valor fixo em `main.tf`.** Tudo por variável, com `description` e
  `type` declarados, e `default` só quando houver um padrão realmente seguro.
- **`data source` para a AMI**, nunca ID fixo — ID de AMI muda por região e é
  substituído a cada release da Canonical.
- **Estado local e gitignored** enquanto durar a fase de construção — ADR-005.
- **`terraform fmt` antes de todo commit**, garantido pelo pre-commit.

---

## Segredos

| Tipo | Onde fica |
|---|---|
| Credenciais AWS | Perfil do `aws-cli` — nunca no código, nunca em variável de ambiente commitada |
| Variáveis do Terraform | `terraform.tfvars`, gitignored |
| Segredos de aplicação | `ansible-vault`, ou SSM Parameter Store Standard |
| Chaves privadas SSH e WireGuard | Fora do repositório, sempre |

**Nunca no `user-data` da instância.** O `user-data` é legível por qualquer
processo que alcance o endpoint de metadados — é justamente o vetor que o IMDSv2
obrigatório existe para mitigar.

---

## Sistema operacional

- Ubuntu Server 22.04 LTS ou superior, AMI oficial da Canonical — ADR-008.
- Usuário administrativo `ops`, com sudo e chave. O usuário padrão da AMI
  (`ubuntu`) é desabilitado após o bootstrap.
- Login por senha desabilitado; login de root bloqueado.

---

## Documentação

- Um arquivo por camada em `docs/camadas/`, atualizado **na mesma branch** da fase.
- `PROGRESS.md` atualizado no dia do merge.
- Documentação que descreve intenção (`docs/`) é separada de documentação que
  descreve função (comentário de código). Não duplicar entre as duas: quando
  divergirem, uma delas estará errada e não haverá como saber qual.
