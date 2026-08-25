# PROGRESS — status do projeto

> **Este é o primeiro arquivo a ler ao retomar o trabalho.** Ele contém apenas
> status e ponteiros. O conteúdo de cada fase está no documento da sua camada.

**Fase atual:** 0.1 — 🟦 em validação, na branch `chore/c0f1-estrutura-repo`
**Próxima ação concreta:** mergear a 0.1 e abrir `feat/c1f1-iam-identidade`. A
Fase 1.1 pode começar sem nenhuma pendência resolvida; a **P3 (região AWS)
precisa estar decidida antes da Fase 1.2**. Ver
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
| 0.1 | Estrutura, `.gitignore`, pre-commit, esqueleto dos módulos | 🟦 | `chore/c0f1-estrutura-repo` | — |

## Camada 1 — Fundação AWS

Detalhes: [`camadas/camada-1-fundacao-aws.md`](./camadas/camada-1-fundacao-aws.md)

| Fase | Conteúdo | Status | Branch | PR |
|---|---|---|---|---|
| 1.1 | Identidade: IAM, instance profiles, alarme de billing | ⬜ | `feat/c1f1-iam-identidade` | — |
| 1.2 | Rede: VPC, subnets, IGW, rotas, SG, NACL | ⬜ | `feat/c1f2-vpc-rede` | — |
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
| P1 | **Data de criação da conta AWS não confirmada.** Define se o free tier é o modelo legado (750h/mês por 12 meses) ou o novo (crédito de $200 por 6 meses). Muda a estimativa de custo. | Camada 2 | Console AWS → Billing and Cost Management → Free Tier. Ver [`04-custos.md`](./04-custos.md) |
| P2 | **Domínio e zona Cloudflare não definidos.** | Camada 4 | Confirmar o domínio a usar e que ele já está com nameservers apontando para a Cloudflare |
| P3 | **Região AWS não decidida.** Afeta latência e preço. | Camada 1 | Decidir antes da Fase 1.2 (`sa-east-1` tem menor latência no Brasil, mas é mais cara que `us-east-1`). Entra em `terraform.tfvars` como `region` e `location_code` |
| P4 | **Conta Backblaze B2 para backup não criada.** | Camada 8 | Criar antes da Fase 8.1 |
| P5 | **Repositório não tem remote.** Sem remote não há PR, e o fluxo de uma fase = uma branch = um PR não fecha. | Todas as fases | Criar o repositório remoto e `git remote add origin` |

---

## Histórico de conclusões

_(preencher conforme as fases forem mergeadas: data, fase, PR, observação)_

| Data | Fase | PR | Observação |
|---|---|---|---|
| — | — | — | — |
