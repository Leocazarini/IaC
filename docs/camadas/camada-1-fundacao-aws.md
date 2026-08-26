# Camada 1 — Fundação AWS

Tudo que precisa existir **antes** da primeira instância: quem pode fazer o quê
(IAM), onde as coisas vão morar (VPC), e como o que acontecer será registrado
(CloudTrail, Flow Logs) e protegido em repouso (EBS encryption).

Nenhuma fase desta camada cria recurso com cobrança recorrente relevante. É a
camada mais barata e a que mais sustenta as outras.

**Ferramenta:** Terraform. **Capítulos do manual:** 09 (parcial).

> A Camada 0 (Fase 0.1 — esqueleto do repositório) precede esta e não tem
> documento próprio: entrega estrutura de diretórios, `.gitignore`, pre-commit
> (`terraform fmt`/`validate`, `ansible-lint`, `gitleaks`) e os módulos vazios
> com o contrato de outputs declarado, sem nenhum recurso.

---

## Fase 1.1 — Identidade e controle de gastos

**Branch:** `feat/c1f1-iam-identidade`

### Objetivo

Estabelecer a camada que, se ficar assimétrica, invalida todas as outras. Um
Security Group perfeito não importa se a aplicação roda com uma role de
administrador — é o equivalente ao root sem senha.

### O que é feito à mão (e por quê)

Estes itens não são automatizáveis — ou porque não têm API, ou porque são
justamente o que dá ao Terraform a permissão de existir. Ficam registrados aqui
como procedimento documentado, executado uma vez:

1. **MFA no usuário root da conta.** Não há API para configurar MFA no root. Feito
   pelo console, uma vez, e o root não volta a ser usado no dia a dia.
2. **Usuário IAM de operação + role administrativa com MFA.** Substitui o IAM
   Identity Center, que criaria uma AWS Organization e custaria o free tier da
   conta — ver **ADR-009** em [`../03-decisoes.md`](../03-decisoes.md). É o
   bootstrap da identidade: sem essa credencial, o Terraform não roda, então ela
   não pode ser criada pelo Terraform. Sequência no console:
   - Criar o usuário IAM (ex.: `ops-admin`), com MFA virtual, **sem nenhuma
     policy anexada** além da de assumir a role.
   - Criar a role administrativa com trust policy para o próprio usuário,
     condicionada a `aws:MultiFactorAuthPresent = true`.
   - Gerar a access key do usuário e configurar o perfil do `aws-cli` com
     `role_arn` + `mfa_serial`, para que a credencial efetiva seja temporária.
3. **Confirmação do tipo de free tier da conta.** Console → Billing → Free Tier.
   *(Resolvida: Free account plan, modelo novo — registrado em
   [`../04-custos.md`](../04-custos.md).)*

> **Não ative o IAM Identity Center nesta conta.** Numa conta standalone ele só
> existe como *organization instance*, o que cria uma AWS Organization e converte
> o Free account plan em plano pago, expirando os créditos na hora. O *account
> instance* preserva o free tier mas só atribui aplicações — não dá acesso
> administrativo à conta.

### O que vira Terraform

| Recurso | Função |
|---|---|
| `aws_iam_role` + `aws_iam_instance_profile` (bastion) | Permissão mínima da instância bastion |
| `aws_iam_role` + `aws_iam_instance_profile` (app) | Permissão mínima da instância de aplicação |
| `aws_iam_policy` | Políticas de privilégio mínimo, escritas à mão — não `AdministratorAccess`, não `PowerUserAccess` |
| `aws_budgets_budget` | Orçamento mensal com notificação por e-mail |
| `aws_cloudwatch_metric_alarm` | Alarme sobre `EstimatedCharges` |

**Sobre o instance profile:** ele existe para eliminar credencial fixa dentro da
instância. Mesmo que nenhuma permissão AWS seja necessária no início, o profile é
criado vazio — porque adicionar um profile depois exige recriar a associação, e
porque é ele que torna possível, mais adiante, dar acesso ao Parameter Store sem
colocar uma chave em arquivo.

**Permissões previstas:** leitura no SSM Parameter Store para os parâmetros do
próprio ambiente (`ssm:GetParameter` com `Resource` restrito por path), e escrita
de log no CloudWatch. Nada além disso.

### Riscos

- **Alarme de billing só dispara depois do gasto acontecer.** Ele avisa, não
  previne. A prevenção real é o `terraform destroy` ao final de cada sessão —
  que neste plano de free tier não protege a fatura, e sim o saldo de crédito
  que define quanto tempo a conta ainda tem.
- **`EstimatedCharges` só existe em `us-east-1`**, independentemente da região do
  resto da infra. O alarme precisa ser criado lá.
- Política de privilégio mínimo escrita cedo demais gera atrito nas fases
  seguintes. Se uma fase precisar de permissão nova, ela é adicionada naquela
  fase — nunca antecipada "por precaução".

### Checklist de validação

- [ ] Login no root exige MFA.
- [ ] `aws sts get-caller-identity` com o perfil de operação retorna a role
      administrativa assumida, não o usuário IAM — prova que o `assume-role` está
      no caminho.
- [ ] Assumir a role sem MFA falha com `AccessDenied`.
- [ ] O usuário IAM não tem policy anexada além da de assumir a role.
- [ ] A conta **não** está em uma AWS Organization
      (`aws organizations describe-organization` retorna
      `AWSOrganizationsNotInUseException`) e o plano continua sendo o Free
      account plan.
- [ ] `aws iam list-attached-role-policies` nas roles de instância criadas pelo
      Terraform não retorna `AdministratorAccess` nem `PowerUserAccess`.
- [ ] O orçamento aparece em Billing → Budgets e o e-mail de notificação foi
      confirmado.
- [ ] Alarme de `EstimatedCharges` existe em `us-east-1` e está em estado `OK`.
- [x] Tipo de free tier da conta confirmado e registrado em
      [`../04-custos.md`](../04-custos.md).

---

## Fase 1.2 — Rede

**Branch:** `feat/c1f2-vpc-rede`
**Capítulo:** 09 (a parte de perímetro; o firewall do host fica na Fase 3.4)

### Objetivo

Replicar o "bloqueia tudo, exceto o necessário" do manual, mas em duas paredes:
Security Groups (stateful, por instância) e Network ACLs (stateless, por subnet).

### Tradução do manual

O manual trata firewall como uma coisa só, porque numa VPS é uma coisa só. Na AWS
existem três lugares distintos, e confundi-los é a origem da maioria dos erros:

| Manual | AWS | Fase |
|---|---|---|
| "firewall do provedor" | Security Group | 1.2 |
| — (não existe na VPS) | Network ACL | 1.2 |
| `iptables` no host | `nftables`/`iptables` no host | 3.4 |

As três coexistem e precisam ser coerentes. A regra deste projeto: **o Security
Group é a fonte da verdade; o firewall do host o espelha.** Divergência entre os
dois é bug, não defesa em profundidade.

### O que vira Terraform

| Recurso | Detalhe |
|---|---|
| `aws_vpc` | `10.0.0.0/16`, DNS hostnames habilitado |
| `aws_subnet` (public) | `10.0.1.0/24` |
| `aws_subnet` (private) | `10.0.11.0/24`, `map_public_ip_on_launch = false` |
| `aws_internet_gateway` | Anexado à VPC |
| `aws_route_table` (public) | `0.0.0.0/0` → IGW |
| `aws_route_table` (private) | `0.0.0.0/0` → ENI do bastion *(implementação na Fase 2.1)* |
| `aws_security_group` (bastion) | UDP 51820 aberto; TCP 22 apenas de `admin_cidr` |
| `aws_security_group` (app) | TCP 22 do CIDR WireGuard; 80/443 dos ranges Cloudflare |
| `aws_network_acl` (public, private) | Espelham os SGs, mais portas efêmeras |

**Sobre `admin_cidr`:** variável que existe apenas para a janela de bootstrap.
Quando o WireGuard sobe (Fase 3.3), ela é esvaziada e a regra de SSH desaparece do
Security Group. Ver a sequência completa em [`../02-arquitetura.md`](../02-arquitetura.md).

**Sobre os ranges da Cloudflare:** obtidos dinamicamente via `data "http"` sobre
`https://www.cloudflare.com/ips-v4`, nunca fixados. Eles mudam.

### Riscos

- **NACL stateless é a armadilha clássica.** Toda regra de entrada precisa da
  regra de saída correspondente nas portas efêmeras (`1024–65535`). Esquecer isso
  produz uma conexão que estabelece e depois trava, sem erro claro.
- A rota do subnet privado depende de uma ENI que só existe na Fase 2.1. Nesta
  fase ela fica declarada mas não resolvida — o `apply` completo só fecha na 2.1.
- NACL muito restritiva quebra o próprio Terraform e o Ansible antes de qualquer
  alarme disparar. Aplicar e testar imediatamente.

### Checklist de validação

- [ ] `terraform validate` e `plan` limpos.
- [ ] Subnet privado não tem rota para o Internet Gateway.
- [ ] `map_public_ip_on_launch` é `false` no subnet privado.
- [ ] Nenhum Security Group tem `0.0.0.0/0` em 22, 3389 ou portas de banco.
- [ ] Regra de SSH do bastion aponta para `admin_cidr`, não para `0.0.0.0/0`.
- [ ] NACLs têm as regras de porta efêmera nos dois sentidos.
- [ ] Ranges da Cloudflare vêm de `data source`, não estão fixos no código.

---

## Fase 1.3 — Criptografia e auditoria

**Branch:** `feat/c1f3-cripto-auditoria`

### Objetivo

Garantir que dados em repouso estejam protegidos e que exista registro imutável de
quem fez o quê na conta — **antes** de haver algo para proteger ou registrar.

O guia é explícito sobre por que a ordem importa: o erro mais comum é ativar o
CloudTrail depois que algo já aconteceu, perdendo exatamente o histórico do
período mais crítico.

### O que vira Terraform

| Recurso | Detalhe |
|---|---|
| `aws_ebs_encryption_by_default` | Habilitado na região. Todo volume criado daí em diante nasce criptografado |
| `aws_s3_bucket` (trail) | Bucket do CloudTrail, acesso público bloqueado, versionamento ligado |
| `aws_s3_bucket_policy` | Permite escrita apenas ao serviço CloudTrail |
| `aws_s3_bucket_lifecycle_configuration` | Expira objetos antigos — evita crescimento indefinido |
| `aws_cloudtrail` | Multi-região, apenas management events (o trail gratuito) |
| `aws_flow_log` | VPC Flow Logs, `traffic_type = "REJECT"`, destino CloudWatch Logs |
| `aws_cloudwatch_log_group` | Retenção curta, para caber nos 5 GB gratuitos |

### Duas decisões de custo embutidas

**EBS encryption usa a chave gerenciada pela AWS (`aws/ebs`), não uma CMK.** O guia
recomenda chave gerenciada pelo cliente para ter controle sobre rotação e
revogação. Uma CMK custa US$ 1/mês, sempre, e o benefício real — revogar a chave
para inutilizar os dados — não se aplica a um projeto pessoal. A criptografia em
si é idêntica.

**Flow Logs capturam apenas `REJECT`.** Capturar `ALL` estoura os 5 GB gratuitos
do CloudWatch rapidamente e gera cobrança. `REJECT` registra o que foi bloqueado
— que é o sinal de segurança útil. O tráfego aceito já aparece nos logs da
aplicação.

### Riscos

- **`aws_ebs_encryption_by_default` é uma configuração de região, não de recurso.**
  Não aparece no `plan` como algo associado a uma instância, e é fácil supor que
  não foi aplicado. Verificar explicitamente.
- Volumes criados **antes** desta fase não são criptografados retroativamente. Como
  ela vem antes da Camada 2, nenhum volume existe ainda — mas se o ambiente for
  recriado fora de ordem, isso vira uma lacuna silenciosa.
- O bucket do CloudTrail sobrevive ao `terraform destroy` se tiver objetos e não
  houver `force_destroy`. É um custo residual pequeno, mas é o tipo de recurso
  órfão que aparece na fatura meses depois.

### Checklist de validação

- [ ] `aws ec2 get-ebs-encryption-by-default` retorna `true`.
- [ ] `aws cloudtrail describe-trails` mostra o trail com `IsMultiRegionTrail: true`.
- [ ] Uma ação qualquer no console aparece no Event History em poucos minutos.
- [ ] O bucket do trail bloqueia acesso público (`aws s3api get-public-access-block`).
- [ ] Flow Logs em estado `ACTIVE` e com `traffic_type` igual a `REJECT`.
- [ ] Log group tem retenção definida — não `Never expire`.
- [ ] Nenhuma CMK do KMS foi criada (`aws kms list-keys` só mostra chaves da AWS).

---

## Ao final da camada

A conta tem identidade controlada, teto de gasto vigiado, rede desenhada com duas
paredes e auditoria ligada — e ainda não custa praticamente nada, porque nenhuma
instância existe.

**Próxima:** [`camada-2-provisionamento.md`](./camada-2-provisionamento.md).
