# 07 — Mapa de fases

Índice de execução do projeto: 8 camadas, 22 fases. Cada fase é uma branch, um PR
e um par de documentos.

A ordem é a da construção — fundação primeiro, depois provisionamento, depois
configuração, por último observação e continuidade. Ela **não** segue a numeração
do manual.

---

## Visão consolidada

| Camada | Fase | Conteúdo | Ferramenta | Caps. manual | Camada do guia |
|---|---|---|---|---|---|
| **0 — Repo** | 0.1 | Estrutura, `.gitignore`, pre-commit, esqueleto dos módulos | git | — | — |
| **1 — Fundação AWS** | 1.1 | IAM, instance profiles, alarme de billing | Terraform | — | Identidade e segredos |
| | 1.2 | VPC, subnets, IGW, rotas, SG, NACL | Terraform | 09 | Perímetro de rede |
| | 1.3 | EBS encryption, CloudTrail, VPC Flow Logs | Terraform | — | Criptografia · Observabilidade |
| **2 — Provisionamento** | 2.1 | Bastion `t4g.nano`: EIP, NAT, IMDSv2 | Terraform | 01–02 | Hardening do host |
| | 2.2 | App `t3.micro` no subnet privado | Terraform | 01–02 | Hardening do host |
| | 2.3 | Outputs, inventário, smoke tests | Terraform + shell | 03–04 | — |
| **3 — Host** | 3.1 | Role `base` | Ansible | 05 | — |
| | 3.2 | Role `ssh_hardening` | Ansible | 07 | Hardening do host |
| | 3.3 | Roles `nat` + `wireguard` | Ansible | 08 | Acesso administrativo |
| | 3.4 | Role `firewall` + espelho no SG | Ansible + TF | 09 | Perímetro de rede |
| | 3.5 | Role `crowdsec` | Ansible | 10 | Detecção e resposta |
| **4 — DNS** | 4.1 | Cloudflare DNS-only | Terraform | 06 | Borda pública |
| **5 — Plataforma** | 5.1 | Role `docker` + estrutura `/srv` | Ansible | 14–19 | — |
| | 5.2 | Role `traefik` | Ansible | 20 | — |
| **6 — Borda pública** | 6.1 | Proxy Cloudflare + SSL Full (Strict) | TF + Ansible | 11–12 | Borda pública |
| | 6.2 | WAF Cloudflare | Terraform | 13 | Borda pública |
| **7 — Observabilidade** | 7.1 | Métricas de host e containers | Ansible | 21–24 | Observabilidade |
| | 7.2 | Loki + Promtail + Grafana | Ansible | 25 | Observabilidade |
| | 7.3 | Uptime Kuma + alertas | Ansible | 26–27 | Observabilidade |
| **8 — Continuidade** | 8.1 | Backup `restic` + teste de restauração + patching | Ansible | — | Manutenção e continuidade |
| | 8.2 | Homepage + documentação gerada | Ansible | 28–29 | — |

---

## Dependências entre fases

```
0.1 ──► 1.1 ──► 1.2 ──► 1.3
                 │       │
                 └───────┴──► 2.1 ──► 2.2 ──► 2.3
                                                │
                                                ▼
                          3.1 ──► 3.2 ──► 3.3 ──► 3.4 ──► 3.5
                                           │
                                    (túnel de pé:
                                     o host app fica
                                     alcançável)
                                           │
                                           ▼
                                          4.1 ──► 5.1 ──► 5.2
                                                            │
                                                            ▼
                                                 6.1 ──► 6.2
                                                            │
                                                            ▼
                                          7.1 ──► 7.2 ──► 7.3
                                                            │
                                                            ▼
                                                 8.1 ──► 8.2
```

**Três dependências que não são óbvias:**

1. **3.3 destrava o host de aplicação.** Antes do WireGuard subir, o host no subnet
   privado não é alcançável. Todas as fases seguintes dependem disso.

2. **5.2 (Traefik) precisa vir antes de 6.1 (SSL Full Strict).** O modo Full
   (Strict) da Cloudflare exige um certificado válido respondendo na origem —
   e quem responde é o Traefik. Esta é uma inversão deliberada em relação à ordem
   do manual, que faz a Cloudflare antes do Traefik porque era um procedimento
   manual, sem essa restrição.

3. **4.1 (DNS) precisa vir antes de 6.1**, mas em modo *DNS-only* — sem proxy. O
   proxy só é ativado na 6.1, depois que a origem responde corretamente. Ativar o
   proxy antes esconde erros de origem atrás de páginas de erro da Cloudflare.

---

## Cobertura do guia de segurança

As nove camadas da seção 2 do guia, e onde cada uma é implementada:

| Camada do guia | Proposta original | Adotado | Onde |
|---|---|---|---|
| Borda / entrada pública | CloudFront/ALB + WAF + Shield + ACM | Cloudflare free | 4.1, 6.1, 6.2 |
| Perímetro de rede | SG + NACL + subnets | Igual ao guia | 1.2, 3.4 |
| Acesso administrativo | Session Manager / EC2 Instance Connect | WireGuard | 3.3 |
| Hardening do host | IMDSv2, sem SSH exposto, instance profile | Igual + hardening do manual | 2.1, 2.2, 3.2 |
| Identidade e segredos | IAM, Identity Center, MFA, Secrets Manager | IAM + `ansible-vault` + Parameter Store | 1.1 |
| Criptografia em repouso | EBS encryption + KMS CMK | EBS encryption com chave da AWS | 1.3 |
| Detecção e resposta | GuardDuty + Security Hub + Inspector | CrowdSec | 3.5 |
| Observabilidade | CloudWatch + Flow Logs + CloudTrail | CloudTrail + Flow Logs + stack Grafana | 1.3, 7.1–7.3 |
| Manutenção e continuidade | AWS Backup + Patch Manager + AMI dourada | `restic` + Backblaze B2 + unattended-upgrades | 8.1 |

Nenhuma camada fica descoberta. As substituições e seus motivos estão em
[`03-decisoes.md`](./03-decisoes.md); os custos comparados, em
[`04-custos.md`](./04-custos.md).

---

## Cobertura do manual

Os 29 capítulos, todos alocados:

| Cap. | Título | Fase |
|---|---|---|
| 01 | Recursos mínimos | 2.1, 2.2 |
| 02 | Criação do servidor | 2.1, 2.2 |
| 03 | Validação | 2.3 |
| 04 | Testes | 2.3 |
| 05 | Configuração base | 3.1 |
| 06 | DNS Cloudflare | 4.1 |
| 07 | Hardening SSH | 3.2 |
| 08 | Adm privada | 3.3 |
| 09 | Perímetro — Firewall | 1.2 (SG/NACL) e 3.4 (host) |
| 10 | Monitoramento + Fail2ban | 3.5 |
| 11 | Proxy Cloudflare | 6.1 |
| 12 | SSL Full (Strict) | 6.1 |
| 13 | WAF Cloudflare | 6.2 |
| 14 | Estrutura de diretórios | 5.1 |
| 15 | Docker 1 | 5.1 |
| 16 | Docker redes | 5.1 |
| 17 | Docker volumes | 5.1 |
| 18 | Exec, restart, saúde de containers | 5.1 |
| 19 | Atualização e rollback | 5.1 |
| 20 | Traefik | 5.2 |
| 21 | Monitoração e observabilidade | 7.1 |
| 22 | Adm e monitoramento do host | 7.1 |
| 23 | Adm e monitoramento dos containers | 7.1 |
| 24 | Métricas do sistema | 7.1 |
| 25 | Loki + Promtail + Grafana | 7.2 |
| 26 | Uptime Kuma | 7.3 |
| 27 | Alertas e notificações | 7.3 |
| 28 | Documentação | 8.2 |
| 29 | Homepage | 8.2 |

Dois capítulos exigem tradução ao serem implementados, e não transcrição direta:

- **Cap. 09** se divide em duas fases. O manual trata firewall como uma coisa só;
  na AWS ele existe em três lugares (Security Group, NACL e o firewall do host).
- **Cap. 10** descreve Fail2ban; a implementação usa CrowdSec (ADR-007). Os
  conceitos mapeiam, os arquivos e comandos não.

---

## Antes de começar cada fase

1. Ler `docs/PROGRESS.md` para confirmar onde o projeto está.
2. Ler o documento da camada em `docs/camadas/`.
3. **Ler os capítulos do manual listados para a fase** — eles contêm os comandos
   exatos, as configurações e o "Checklist para validação" que vira o teste da
   fase. Nunca supor o conteúdo de um capítulo.
4. Confirmar o escopo com o operador antes de escrever código.

Extração de texto de um `.docx` do manual:

```bash
unzip -p "ARQUIVO.docx" word/document.xml | python3 -c "
import sys, re, html
xml = sys.stdin.read()
xml = re.sub(r'<w:p [^>]*>|<w:p>', '\n', xml)
xml = re.sub(r'<w:tab[^>]*/>', '\t', xml)
xml = re.sub(r'<w:br[^>]*/>', '\n', xml)
print(html.unescape(re.sub(r'<[^>]+>', '', xml)))"
```

Extrair para `docs/manual/` — diretório gitignored, conteúdo de terceiros.
