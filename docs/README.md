# Infra como Código — AWS EC2

Reprodução em código da infraestrutura descrita no manual de self-hosting, rodando
em AWS, com as nove camadas de segurança do guia de simetria implementadas de forma
equilibrada e a um custo compatível com um projeto pessoal.

O critério de sucesso do projeto é objetivo: **`terraform apply` + `ansible-playbook`
sobem a infra inteira do zero, em minutos, de forma idêntica todas as vezes.**

---

## Por onde começar

**Se você está retomando o trabalho:** abra [`PROGRESS.md`](./PROGRESS.md). Ele diz
qual é a fase atual e qual é a próxima ação concreta. Nada mais é necessário para
continuar.

**Se é a primeira vez que você lê estes documentos**, siga nesta ordem:

| # | Documento | O que responde |
|---|---|---|
| 1 | [`01-visao-geral.md`](./01-visao-geral.md) | O que é o projeto, o que é "simetria de camadas", o que está dentro e fora do escopo |
| 2 | [`02-arquitetura.md`](./02-arquitetura.md) | Como a infra é desenhada: rede, hosts, bootstrap, contrato anti-lock-in |
| 3 | [`03-decisoes.md`](./03-decisoes.md) | Por que cada escolha foi feita, e o que foi descartado |
| 4 | [`04-custos.md`](./04-custos.md) | O que é grátis na AWS, o que não é, e quanto esta arquitetura custa por mês |
| 5 | [`05-fluxo-git.md`](./05-fluxo-git.md) | Branches, commits, PRs e os dois textos de documentação exigidos por fase |
| 6 | [`06-convencoes.md`](./06-convencoes.md) | Regras de código, nomenclatura, tags e idempotência |
| 7 | [`07-mapa-de-fases.md`](./07-mapa-de-fases.md) | O índice de execução: as 8 camadas e suas 22 fases |

Os detalhes de execução de cada camada ficam em [`camadas/`](./camadas/), um
arquivo por camada.

---

## Estrutura destes documentos

```
docs/
├── README.md              ← você está aqui
├── PROGRESS.md            ← status vivo. LEIA PRIMEIRO ao retomar o trabalho
├── 01-visao-geral.md      ← contexto e escopo
├── 02-arquitetura.md      ← desenho da infra
├── 03-decisoes.md         ← ADRs (registros de decisão)
├── 04-custos.md           ← free tier e estimativa mensal
├── 05-fluxo-git.md        ← fluxo de trabalho e templates de documentação
├── 06-convencoes.md       ← padrões de código e nomenclatura
├── 07-mapa-de-fases.md    ← índice das 22 fases
└── camadas/
    ├── camada-1-fundacao-aws.md     ← VPC, IAM, NACL, criptografia, auditoria
    ├── camada-2-provisionamento.md  ← as instâncias EC2
    ├── camada-3-host.md             ← configuração e hardening do sistema
    ├── camada-4-dns.md              ← DNS Cloudflare
    ├── camada-5-plataforma.md       ← Docker e Traefik
    ├── camada-6-borda-publica.md    ← proxy, SSL e WAF
    ├── camada-7-observabilidade.md  ← métricas, logs e alertas
    └── camada-8-continuidade.md     ← backup, patching e documentação
```

---

## Estrutura do repositório (alvo)

O que estes documentos planejam construir:

```
iac/
├── terraform/
│   ├── modules/
│   │   ├── compute-aws/      # VPC, SG, NACL, EC2, EIP, IAM — único lugar com AWS
│   │   └── cloudflare/       # DNS, proxy, SSL mode, WAF
│   └── envs/
│       └── lab/              # ambiente descartável de teste
├── ansible/
│   ├── inventory/            # gerado a partir do output do Terraform
│   ├── group_vars/
│   ├── roles/                # uma role por preocupação
│   └── playbooks/site.yml
├── scripts/                  # gen-inventory, smoke tests
└── docs/                     # este diretório
```

---

## Avisos

- **`docs/manual/` é gitignored.** É onde os capítulos do manual `.docx` são
  extraídos para leitura. É conteúdo de terceiros e não deve ser commitado.
- **Nenhum segredo entra no repositório.** `*.tfvars`, senhas de vault e chaves
  ficam fora do versionamento. Ver [`06-convencoes.md`](./06-convencoes.md).
- **Este projeto não usa AWS Shield Advanced, GuardDuty, Security Hub, Inspector,
  Secrets Manager, AWS Backup, ALB nem NAT Gateway.** Cada um foi avaliado e
  substituído por uma alternativa equivalente e gratuita ou muito mais barata.
  O raciocínio completo está em [`04-custos.md`](./04-custos.md).
