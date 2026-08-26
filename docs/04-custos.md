# 04 — Custos e AWS Free Tier

Todos os valores abaixo foram verificados nas páginas oficiais de preço da AWS
(links ao final). Preços em USD, região `us-east-1`. Regiões brasileiras
(`sa-east-1`) custam significativamente mais.

A região do projeto é **`us-east-1`** (`location_code = "use1"`) — decidida na
Fase 1.1, pelo custo e por ser onde a métrica de billing existe de qualquer
forma. A latência maior a partir do Brasil é o preço aceito; num ambiente de
laboratório destruído ao final de cada sessão, ela não é o critério dominante.

---

## Pendência: qual é o free tier desta conta?

> **P1 — bloqueia a Camada 2.** A AWS reestruturou o Free Tier em **15 de julho de
> 2025**, e os dois modelos coexistem. A data de criação da conta determina qual se
> aplica, e isso muda a estimativa de custo. **Verificar em Console AWS →
> Billing and Cost Management → Free Tier antes de provisionar qualquer instância.**

| | Conta criada **antes** de 15/jul/2025 | Conta criada **em ou após** 15/jul/2025 |
|---|---|---|
| Tipos EC2 elegíveis | `t2.micro`, `t3.micro` | `t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, `c7i-flex.large`, `m7i-flex.large` |
| Mecânica | 750 h/mês **compartilhadas entre todas as instâncias**, depois cobrança normal | Crédito de US$ 100 + até US$ 100 adicionais |
| Duração | 12 meses a partir da criação da conta | 6 meses, ou até o crédito acabar — o que vier primeiro |
| Ao estourar | Passa a cobrar pay-as-you-go | No *Free plan*, o uso é bloqueado; no *Paid plan*, passa a cobrar |

**Duas armadilhas a registrar:**

1. **As 750 h/mês são um pool compartilhado, não por instância.** Duas instâncias
   rodando 24/7 consomem ~1.460 h/mês — uma fica coberta, a outra é cobrada.
2. **`t4g.nano` não é elegível ao free tier em nenhum dos modelos.** A lista inclui
   `t4g.micro`, não `t4g.nano`. O bastion será cobrado (~US$ 3/mês) de qualquer
   forma — o que já está previsto na estimativa.

### Os créditos cobrem os serviços pagos?

Sim, e isso é relevante. O crédito de US$ 200 não é uma lista de serviços
liberados — é saldo em dólar descontado automaticamente de qualquer cobrança
elegível. A lista de exclusão dos termos promocionais é curta e não inclui nenhum
serviço deste projeto: Mechanical Turk, AWS Managed Services, Enterprise/Partner-Led
Support, Marketplace, Professional Services, Training, Certification, registro de
domínio no Route 53, mineração de criptomoeda e taxas upfront de Savings
Plans/Reserved Instances.

Ou seja, numa conta nova no *Paid plan*, GuardDuty, Secrets Manager, NAT Gateway e
afins consomem o crédito antes de gerar fatura. Numa conta legado, não existe esse
saldo — a cobrança é direta desde o primeiro uso.

---

## Free tier por serviço

Estado de cada serviço mencionado no guia de segurança.

### Sempre gratuitos, sem limite relevante

| Serviço | Observação |
|---|---|
| VPC, subnets, route tables, Internet Gateway | Sem cobrança própria |
| Security Groups, Network ACLs | Sem cobrança própria |
| IAM, IAM Identity Center, MFA virtual | Sem cobrança em nenhum cenário |
| AWS Shield Standard | Incluído automaticamente em toda conta |
| ACM (certificado público) | Grátis para uso com CloudFront/ALB/API Gateway |
| IMDSv2, IAM Instance Profile | Atributos da instância |
| EBS Encryption (a funcionalidade) | Sem custo com a chave gerenciada pela AWS |
| KMS — chave gerenciada pela AWS | Sem custo de criação ou armazenamento |
| SSM Session Manager (em EC2) | Sem cobrança adicional |
| SSM Patch Manager (em EC2) | Sem cobrança adicional |
| SSM Parameter Store — Standard | Sem custo |
| VPC Flow Logs — a captura | Paga-se apenas o destino (CloudWatch ou S3) |

### Sempre gratuitos até um limite

| Serviço | Franquia mensal permanente |
|---|---|
| CloudWatch | 10 métricas customizadas · 5 GB de logs (ingestão + armazenamento) · 10 alarmes · 3 dashboards · 1 M chamadas de API |
| KMS — requisições | 20.000/mês (operações simétricas; assimétricas e `GenerateDataKeyPair` não contam) |
| CloudTrail | Histórico de 90 dias no console + **1 trail** de management events entregue a S3 |
| CloudFront (plano flat-rate Free) | 1 M requisições + 100 GB/mês, incluindo WAF, Shield, Route 53 e certificado |

### Pagos, sem free tier permanente

| Serviço | Custo | Situação neste projeto |
|---|---|---|
| **AWS Shield Advanced** | **US$ 3.000/mês** (contrato de 1 ano) | Fora de escopo. O Shield Standard, gratuito, cobre o cenário de DDoS L3/L4 comum |
| NAT Gateway | US$ 0,045/h (~US$ 32) + US$ 0,045/GB | Substituído por NAT em instância — ADR-001 |
| ALB | US$ 0,0225/h + LCU (~US$ 23/mês) | Substituído pela Cloudflare — ADR-004 |
| AWS WAF (standalone) | US$ 5/ACL + US$ 1/regra + US$ 0,60/milhão req | Substituído pela Cloudflare — ADR-004 |
| GuardDuty | Trial 30 dias, depois por volume de log analisado | Substituído por CrowdSec — ADR-003 |
| Security Hub | Trial 30 dias, depois por *resource unit* (EC2 = US$ 3,75) | Substituído — ADR-003 |
| Amazon Inspector | Trial 15 dias, depois ~US$ 1,26/instância/mês | Substituído — ADR-003 |
| Secrets Manager | Trial 30 dias por segredo, depois US$ 0,40/segredo/mês | Substituído por `ansible-vault` + Parameter Store — ADR-003 |
| AWS Backup | Por GB armazenado e restaurado, sem franquia | Substituído por `restic` + Backblaze B2 — ADR-003 |
| KMS — chave gerenciada pelo cliente (CMK) | **US$ 1/mês por chave, sempre** | Não usada. EBS encryption com a chave `aws/ebs` gratuita |
| IP público IPv4 | US$ 0,005/h por endereço (~US$ 3,60/mês) | 1 Elastic IP no bastion — inevitável |
| CloudTrail — data events, Insights, trails extras | US$ 0,10 a US$ 2,00 por 100 mil eventos | Apenas o trail gratuito de management events |
| SSM Parameter Store — Advanced | US$ 0,05/parâmetro/mês | Apenas parâmetros Standard |

---

## O que o guia custaria, seguido à risca

| Item | Custo mensal |
|---|---|
| ALB | ~US$ 23 |
| NAT Gateway | ~US$ 35 |
| AWS WAF (1 ACL + 5 regras) | ~US$ 13 |
| GuardDuty + Security Hub + Inspector | ~US$ 15 |
| Secrets Manager (10 segredos) | ~US$ 4 |
| AWS Backup | ~US$ 5 |
| KMS CMK | US$ 1 |
| **Subtotal, sem contar as instâncias** | **~US$ 96/mês** |
| Shield Advanced, se incluído | +US$ 3.000 |

Para um projeto pessoal de tráfego baixíssimo. É exatamente a assimetria que o
guia adverte na sua seção 1 — desproporção entre o esforço gasto numa camada e o
valor real protegido.

---

## O que esta arquitetura custa

| Item | Custo mensal |
|---|---|
| Bastion `t4g.nano` (NAT + WireGuard, 24/7) | ~US$ 3,00 |
| App `t3.micro` | US$ 0 se coberto pelas 750 h · ~US$ 7,50 se não |
| Elastic IP (1, em uso) | ~US$ 3,60 |
| EBS gp3 (~16 GB nas duas instâncias) | ~US$ 1,30 |
| CloudTrail (1 trail) + S3 do trail | ~US$ 0,10 |
| VPC Flow Logs (só REJECT) → CloudWatch | ~US$ 0 dentro dos 5 GB |
| Snapshots de EBS | ~US$ 0,20 |
| Cloudflare (DNS, proxy, WAF, TLS) | US$ 0 |
| CrowdSec, Grafana, Loki, Uptime Kuma, Traefik | US$ 0 (rodam na instância) |
| Backblaze B2 (backup, poucos GB) | ~US$ 0,10 |
| **Total** | **~US$ 8/mês** com a `t3.micro` no free tier<br>**~US$ 16/mês** sem free tier |

Contra os ~US$ 96/mês da versão nativa, com as mesmas nove camadas cobertas.

**E durante a construção o custo é ainda menor:** o ambiente `lab` é destruído com
`terraform destroy` ao final de cada sessão de teste. Só se paga pelas horas em que
ele esteve de pé.

---

## Regras de custo do projeto

1. **Confirmar antes de aplicar.** Todo `terraform plan` que introduza um recurso
   com cobrança recorrente deve ter o custo explicitado ao operador antes do
   `apply`.
2. **Destruir ao final da sessão.** `terraform destroy` no `lab` sempre que o
   ambiente não estiver em uso.
3. **Alarme de billing na Fase 1.1.** Antes de qualquer instância existir. Um
   alarme do CloudWatch em um limite baixo (ex.: US$ 10) — cabe nos 10 alarmes
   gratuitos.
4. **Elastic IP não alocado também é cobrado.** Um EIP órfão depois de um destroy
   parcial é a forma mais comum de fatura inesperada num projeto assim.
5. **Nada de trial que vira cobrança silenciosa.** Não ativar GuardDuty, Security
   Hub, Inspector ou Secrets Manager "só para ver" — o trial termina e a cobrança
   começa sem novo aviso.

---

## Fontes

Páginas oficiais consultadas na elaboração desta tabela:

- [Free Tier — visão geral (docs de Billing)](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier.html)
- [Free Tier do EC2 (docs)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html)
- [AWS Free Tier FAQs](https://aws.amazon.com/free/free-tier-faqs/)
- [Promotional Credit Terms & Conditions](https://aws.amazon.com/awscredits/)
- [CloudFront — planos flat-rate (docs)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/flat-rate-pricing-plan.html)
- [VPC](https://aws.amazon.com/vpc/pricing/) ·
  [ELB](https://aws.amazon.com/elasticloadbalancing/pricing/) ·
  [WAF](https://aws.amazon.com/waf/pricing/) ·
  [Shield](https://aws.amazon.com/shield/pricing/) ·
  [ACM](https://aws.amazon.com/certificate-manager/pricing/)
- [KMS](https://aws.amazon.com/kms/pricing/) ·
  [Secrets Manager](https://aws.amazon.com/secrets-manager/pricing/) ·
  [Systems Manager](https://aws.amazon.com/systems-manager/pricing/)
- [GuardDuty](https://aws.amazon.com/guardduty/pricing/) ·
  [Security Hub](https://aws.amazon.com/security-hub/pricing/) ·
  [Inspector](https://aws.amazon.com/inspector/pricing/)
- [CloudWatch](https://aws.amazon.com/cloudwatch/pricing/) ·
  [CloudTrail](https://aws.amazon.com/cloudtrail/pricing/) ·
  [AWS Backup](https://aws.amazon.com/backup/pricing/)

> Preços de nuvem mudam. Revalidar esta tabela antes de decisões de custo
> relevantes, e ao retomar o projeto depois de uma pausa longa.
