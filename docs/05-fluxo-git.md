# 05 — Fluxo de trabalho e Git

## Princípio

**Uma fase = uma branch = um PR = um merge = um par de documentos.**

Nunca uma branch por camada inteira. A camada é uma unidade de planejamento; a
fase é a unidade de entrega. Uma branch que acumula três fases não é revisável e
não pode ser revertida sem levar junto o que funcionava.

---

## Convenções de nomenclatura

### Branches

```
<tipo>/c<camada>f<fase>-<slug>
```

| Tipo | Quando |
|---|---|
| `feat` | Nova capacidade de infraestrutura |
| `chore` | Estrutura, ferramental, configuração de repositório |
| `fix` | Correção em fase já mergeada |
| `docs` | Alteração apenas em documentação |
| `refactor` | Reorganização sem mudança de comportamento |

Exemplos: `feat/c1f2-vpc-rede` · `feat/c3f3-nat-wireguard` · `chore/c0f1-estrutura-repo`

### Commits

```
<tipo>(c<camada>f<fase>): <descrição em minúsculas, imperativo, pt-BR>
```

Exemplos:

```
feat(c1f2): vpc, subnets publica e privada e route tables
feat(c1f2): security groups e nacls com portas efemeras
fix(c1f2): corrige rota de saida do subnet privado
docs(c1f2): registra traducao do capitulo 09 para SG/NACL
```

Vários commits por branch são bem-vindos — um por passo lógico. O que importa é
que cada commit deixe a branch num estado coerente.

---

## Ciclo de uma fase

```
 1. Ler       → docs/PROGRESS.md, o doc da camada, e os capítulos do manual da fase
 2. Planejar  → confirmar o escopo com o operador antes de codar
 3. Branch    → git switch -c feat/cXfY-slug
 4. Implementar
 5. Validar   → terraform fmt -check · terraform validate
                ansible-lint · gitleaks detect
 6. Aplicar   → terraform apply no envs/lab  (mostrar o plan e o custo antes)
 7. Testar    → checklist da fase + segunda execução do playbook (idempotência)
 8. Documentar→ gerar os dois textos (templates abaixo) e entregar ao operador
 9. PR        → descrição = texto simples
10. Merge     → comentário principal = texto técnico
11. Registrar → atualizar docs/PROGRESS.md (status, PR, histórico)
12. Destruir  → terraform destroy no lab (perguntar antes se deve ficar de pé)
```

**O passo 7 não se pula.** A promessa do projeto é "deploy igual em minutos", e
isso só é verdade se cada fase foi validada numa instância criada do zero. Toda
role Ansible precisa provar idempotência: a segunda execução tem que retornar
`changed=0`.

---

## Validação estática obrigatória

Roda no pre-commit e antes de qualquer PR:

| Ferramenta | Comando | O que pega |
|---|---|---|
| Terraform fmt | `terraform fmt -check -recursive` | Formatação inconsistente |
| Terraform validate | `terraform validate` | Erro de sintaxe e referência |
| ansible-lint | `ansible-lint` | Antipadrões e falhas de idempotência |
| gitleaks | `gitleaks detect --no-git` | Segredo prestes a ser commitado |

O `gitleaks` é o mais importante da lista. `*.tfvars`, senhas de vault e chaves
privadas estão no `.gitignore`, mas o `.gitignore` protege contra descuido, não
contra erro de caminho.

---

## Os dois documentos de cada fase

Ao final de cada implementação, dois textos são gerados e entregues ao operador,
que os aplica manualmente:

| Texto | Onde vai | Para quem |
|---|---|---|
| **Simples** | Descrição do PR | Alguém sem formação técnica |
| **Técnico** | Comentário principal do merge | Quem vai manter ou auditar |

A separação existe porque são leitores diferentes com perguntas diferentes. O
primeiro quer saber o que mudou no mundo; o segundo, o que mudou no sistema.

---

### Template — descrição do PR (versão simples)

**Regras rígidas:**

- Nenhum nome de recurso AWS (`aws_vpc`, `t4g.nano`, `sg-0a1b2c`).
- Nenhum comando, nenhum trecho de código, nenhum caminho de arquivo.
- Nenhuma sigla sem tradução na primeira aparição.
- Analogias do mundo físico são bem-vindas — portas, muros, chaves, guardas.
- Se um parágrafo só faz sentido para quem já conhece AWS, ele está errado.

```markdown
## O que mudou

_Uma ou duas frases, em linguagem comum, sobre o que passou a existir._

## Por que isso importa

_Qual risco deixou de existir, ou qual capacidade apareceu. Concreto: o que
poderia dar errado antes e não pode mais._

## O que passa a ser possível agora

- _Item em linguagem de resultado, não de implementação._

## Quanto custa

_Quanto isso adiciona por mês, em dólares. Se for zero, dizer "nada" e explicar
por quê._

## O que ainda não está pronto

_O que um leitor poderia supor que já funciona, mas ainda não funciona, e em qual
etapa vai funcionar._
```

**Exemplo preenchido** (Fase 1.2, rede):

> ## O que mudou
> Criamos a "planta do terreno" onde os servidores vão morar: uma rede privada
> dividida em duas áreas — uma que conversa com a internet e outra que fica
> isolada, sem endereço público nenhum.
>
> ## Por que isso importa
> Antes, qualquer servidor que subíssemos ficaria diretamente exposto à internet,
> visível para qualquer varredura automática. Agora o servidor que roda a
> aplicação fica na área isolada: mesmo que alguém descubra que ele existe, não
> há caminho para chegar até ele de fora.
>
> ## O que passa a ser possível agora
> - Subir servidores sem que eles fiquem publicamente acessíveis.
> - Definir, regra por regra, o que pode entrar e sair de cada área.
>
> ## Quanto custa
> Nada. Rede, divisórias e regras de firewall não são cobradas pela Amazon.
>
> ## O que ainda não está pronto
> A rede está desenhada, mas vazia — nenhum servidor foi criado ainda. Isso
> acontece na próxima etapa.

---

### Template — comentário do merge (versão técnica)

```markdown
## Recursos criados/alterados

| Tipo | Nome | Observação |
|---|---|---|

## Arquivos tocados

- `caminho/arquivo` — o que mudou

## Decisões técnicas e trade-offs

_O que foi decidido durante a implementação e não estava no plano, e por quê.
Alternativas descartadas. Se contradiz uma ADR, dizer explicitamente._

## Validação executada

```
comando executado
→ saída relevante / resultado esperado
```

_Incluir a prova de idempotência quando houver Ansible: segunda execução com
`changed=0`._

## Outputs expostos

| Output | Tipo | Consumido por |
|---|---|---|

## Como reverter

_Comando ou sequência. Se houver efeito colateral que o `destroy` não desfaz
(bucket com objetos, EIP alocado, chave gerada), dizer qual._

## Pendências para a próxima fase

- _O que ficou deliberadamente de fora e onde entra._
```

---

## Regras de merge

- **`main` sempre aplicável.** Nenhum merge que quebre `terraform validate`.
- **Merge commit, não squash.** O histórico por fase tem valor arqueológico: o
  comentário técnico do merge é a documentação daquela fase.
- **PR não se mergeia sem os dois textos prontos.**
- **`PROGRESS.md` é atualizado no mesmo dia do merge**, não depois. Um `PROGRESS.md`
  desatualizado é pior que nenhum: induz a sessão seguinte ao erro.

---

## O que nunca entra no repositório

Garantido por `.gitignore` e verificado por `gitleaks`:

```
*.tfvars              # variáveis, frequentemente com dados sensíveis
*.tfstate             # estado, contém valores em texto claro
*.tfstate.backup
.terraform/
vault-pass            # senha do ansible-vault
*.pem  *.key          # chaves privadas
wg*.conf              # configuração de peer WireGuard, contém chave privada
docs/manual/          # capítulos extraídos do manual — conteúdo de terceiros
inventory/hosts.yml   # gerado a partir do output do Terraform
```

Credenciais da AWS vêm do perfil do `aws-cli`, nunca de variável no código.
Segredos de aplicação ficam em `ansible-vault` ou no SSM Parameter Store.
