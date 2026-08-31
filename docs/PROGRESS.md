# PROGRESS — status do projeto

> **Este é o primeiro arquivo a ler ao retomar o trabalho.** Ele contém apenas
> status e ponteiros. O conteúdo de cada fase está no documento da sua camada.

**Fase atual:** 1.2 — 🟦 em validação, na branch `feat/c1f2-vpc-rede`
**Próxima ação concreta:** aplicada no lab e com o checklist da fase inteiro
verde (78 recursos, custo zero, segundo `plan` sem diferenças). Falta abrir o PR
e mergear. Depois: Fase 1.3, criptografia e auditoria. Ver
[`camadas/camada-1-fundacao-aws.md`](./camadas/camada-1-fundacao-aws.md).

---

## Legenda

| Status | Significado |
|---|---|
| ⬜ pendente | Não iniciada |
| 🟨 em andamento | Branch aberta, código sendo escrito |
| 🟦 em validação | Código pronto, aplicado no lab, rodando checklist |
| ✅ concluída | Testada, PR mergeado, documentação entregue |
| ⏸️ bloqueada | Depende de algo externo — ver observação |

---

## Camada 0 — Fundação do repositório

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 0.1 | Estrutura, `.gitignore`, pre-commit, esqueleto dos módulos | ✅ | `chore/c0f1-estrutura-repo` | [#1](https://github.com/Leocazarini/IaC/pull/1) |

## Camada 1 — Fundação AWS

Detalhes: [`camadas/camada-1-fundacao-aws.md`](./camadas/camada-1-fundacao-aws.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 1.1 | Identidade: IAM, instance profiles, alarme de billing | ✅ | `feat/c1f1-iam-identidade` | [#2](https://github.com/Leocazarini/IaC/pull/2) |
| 1.2 | Rede: VPC, subnets, IGW, rotas, SG, NACL | 🟦 | `feat/c1f2-vpc-rede` | — |
| 1.3 | Criptografia e auditoria: EBS default, CloudTrail, Flow Logs | ⬜ | `feat/c1f3-cripto-auditoria` | — |

## Camada 2 — Provisionamento

Detalhes: [`camadas/camada-2-provisionamento.md`](./camadas/camada-2-provisionamento.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 2.1 | Bastion `t4g.nano`: EIP, NAT, IMDSv2 | ⬜ | `feat/c2f1-bastion` | — |
| 2.2 | App `t3.micro` no subnet privado | ⬜ | `feat/c2f2-app-host` | — |
| 2.3 | Contrato de outputs, inventário, smoke tests | ⬜ | `feat/c2f3-outputs-inventario` | — |

## Camada 3 — Configuração do host

Detalhes: [`camadas/camada-3-host.md`](./camadas/camada-3-host.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 3.1 | Role `base` | ⬜ | `feat/c3f1-role-base` | — |
| 3.2 | Role `ssh_hardening` | ⬜ | `feat/c3f2-ssh-hardening` | — |
| 3.3 | Roles `nat` + `wireguard` | ⬜ | `feat/c3f3-nat-wireguard` | — |
| 3.4 | Role `firewall` + espelhamento no SG | ⬜ | `feat/c3f4-firewall` | — |
| 3.5 | Role `crowdsec` | ⬜ | `feat/c3f5-crowdsec` | — |

## Camada 4 — DNS

Detalhes: [`camadas/camada-4-dns.md`](./camadas/camada-4-dns.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 4.1 | Cloudflare DNS-only | ⬜ | `feat/c4f1-dns-cloudflare` | — |

## Camada 5 — Plataforma de aplicação

Detalhes: [`camadas/camada-5-plataforma.md`](./camadas/camada-5-plataforma.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 5.1 | Role `docker` + estrutura `/srv` | ⬜ | `feat/c5f1-docker` | — |
| 5.2 | Role `traefik` | ⬜ | `feat/c5f2-traefik` | — |

## Camada 6 — Borda pública

Detalhes: [`camadas/camada-6-borda-publica.md`](./camadas/camada-6-borda-publica.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 6.1 | Proxy Cloudflare + SSL Full (Strict) | ⬜ | `feat/c6f1-proxy-ssl` | — |
| 6.2 | WAF Cloudflare | ⬜ | `feat/c6f2-waf` | — |

## Camada 7 — Observabilidade

Detalhes: [`camadas/camada-7-observabilidade.md`](./camadas/camada-7-observabilidade.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 7.1 | Métricas de host e containers | ⬜ | `feat/c7f1-metricas` | — |
| 7.2 | Loki + Promtail + Grafana | ⬜ | `feat/c7f2-logs` | — |
| 7.3 | Uptime Kuma + alertas | ⬜ | `feat/c7f3-alertas` | — |

## Camada 8 — Continuidade

Detalhes: [`camadas/camada-8-continuidade.md`](./camadas/camada-8-continuidade.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 8.1 | Backup restic + teste de restauração + patching | ⬜ | `feat/c8f1-backup-patch` | — |
| 8.2 | Homepage + documentação gerada | ⬜ | `feat/c8f2-homepage-docs` | — |

---

## Pendências abertas

| # | Pendência | Bloqueia | Como resolver |
|---|---|---|---|
| P2 | **Domínio e zona Cloudflare não definidos.** | Camada 4 | Confirmar o domínio a usar e que ele já está com nameservers apontando para a Cloudflare |
| P4 | **Conta Backblaze B2 para backup não criada.** | Camada 8 | Criar antes da Fase 8.1 |
| P8 | **O arquivo `terraform/envs/lab/tfplan` foi commitado no PR #2 e está no histórico do `main`.** É o plano binário da Fase 1.1: contém, em texto claro, o IP público do operador e o e-mail de billing. O `.gitignore` tinha `*.tfplan`, que não pega um arquivo chamado `tfplan`. | Nada tecnicamente; é exposição de dado | O arquivo saiu do índice e o `.gitignore` foi corrigido na branch da Fase 1.2. Remover do histórico exige reescrita (`git filter-repo`) e `push --force`; decidir se vale, considerando que o IP residencial muda e o e-mail já é público nos commits |
| P7 | **O Free account plan encerra em 6 meses ou quando os créditos zerarem — e a conta fecha automaticamente.** Há 90 dias para migrar ao Paid account plan antes da exclusão dos recursos. | Continuidade do projeto | Acompanhar o saldo em Billing → Free Tier; decidir a migração antes do fim do prazo. Ver [`04-custos.md`](./04-custos.md) |

**Resolvidas:** P6 — identidade de bootstrap de pé: usuário `ops-admin` com MFA,
role `ops-admin-role` exigindo MFA na trust policy, e o perfil `ops` do
`aws-cli`. Verificado: assumir sem MFA retorna `AccessDenied`. P1 — a conta está
no **Free account plan** (modelo novo,
pós-15/jul/2025): US$ 100 + até US$ 100 em créditos, 6 meses de prazo, sem as
750 h/mês do modelo legado; registrado em [`04-custos.md`](./04-custos.md) e
desdobrado na P7. P3 — região decidida: `us-east-1` / `location_code = "use1"`.
P5 — o remote existe (`git@github.com:Leocazarini/IaC.git`).

---

## Histórico de conclusões

_(preencher conforme as fases forem mergeadas: data, fase, PR, observação)_

| Data | Fase | PR | Observação |
|---|---|---|---|
| 2026-08-26 | 0.1 | [#1](https://github.com/Leocazarini/IaC/pull/1) | Esqueleto do repositório, pre-commit e contrato de outputs. Nenhum recurso criado, custo zero. |
| 2026-08-28 | 1.1 | [#2](https://github.com/Leocazarini/IaC/pull/2) | Roles e instance profiles das duas instâncias com privilégio mínimo escrito à mão, orçamento mensal e alarme de `EstimatedCharges` em `us-east-1`. Identidade de bootstrap (`ops-admin` + `ops-admin-role` com MFA) feita à mão no console. Custo zero. |
