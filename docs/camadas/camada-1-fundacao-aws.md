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

**Trust policy da role administrativa.** É ela que exige o MFA — sem a condição,
a role vira apenas um atalho para privilégio permanente. Nos três blocos abaixo,
`<ACCOUNT_ID>` é marcador de lugar: substitua o texto **e os sinais `<` `>`** pelo
número da conta, senão o editor de políticas do console recusa o JSON.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::<ACCOUNT_ID>:user/ops-admin" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "Bool": { "aws:MultiFactorAuthPresent": "true" },
      "NumericLessThan": { "aws:MultiFactorAuthAge": "43200" }
    }
  }]
}
```

**Permissão da role.** A role recebe `AdministratorAccess`, e isso **não**
contradiz a regra de privilégio mínimo da fase — a regra vale para as roles de
*instância*, que o Terraform cria e que rodam sem supervisão. Esta é a identidade
de bootstrap do operador: ela precisa criar VPC, EC2, S3, CloudTrail, IAM e tudo
mais que as 22 fases declararem, e uma política enumerando isso quebraria a cada
fase nova. O que a limita não é o escopo, é o tempo e o segundo fator: a
credencial expira e não sai sem MFA.

**Policy do usuário `ops-admin`** — a única que ele recebe:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::<ACCOUNT_ID>:role/ops-admin-role"
  }]
}
```

**Perfil do `aws-cli`.** O `aws configure` guarda a access key em
`~/.aws/credentials`; o perfil que o Terraform usa fica em `~/.aws/config` e
aponta para a role. No devcontainer, `/home/dev/.aws` é um volume Docker nomeado
— sobrevive a rebuild e nunca toca o repositório.

```ini
# ~/.aws/credentials  — a access key de vida longa, sem privilégio proprio
[ops-admin]
aws_access_key_id     = AKIA...
aws_secret_access_key = ...

# ~/.aws/config  — o perfil efetivamente usado
[profile ops]
role_arn       = arn:aws:iam::<ACCOUNT_ID>:role/ops-admin-role
source_profile = ops-admin
mfa_serial     = arn:aws:iam::<ACCOUNT_ID>:mfa/ops-admin
region         = us-east-1
```

Com isso, `export AWS_PROFILE=ops` faz o `aws-cli` pedir o código do MFA e
trabalhar com credencial temporária.

**O Terraform não usa esse perfil diretamente.** O provider AWS lê o
`mfa_serial`, entende que precisa de um token e falha com *"assume role with MFA
enabled, but AssumeRoleTokenProvider session option not set"* — ele não tem
prompt interativo para pedir o código. Quem tem é o `aws-cli`, então ele resolve
a credencial e a entrega pronta:

```bash
export AWS_PROFILE=ops
aws sts get-caller-identity          # pede o codigo do MFA uma vez, e cacheia

eval "$(aws configure export-credentials --profile ops --format env)"
unset AWS_PROFILE                    # as variaveis de ambiente tem precedencia
export AWS_DEFAULT_REGION=us-east-1  # o unset acima levou a regiao junto
terraform plan
```

**Por que o `AWS_DEFAULT_REGION` aparece aqui.** O `unset AWS_PROFILE` descarta
tambem a regiao, que vinha do perfil. O Terraform nao sente — a regiao dele esta
no `providers.tf` — mas qualquer `aws ec2 describe-*` posterior falha com
`NoRegion`, e o erro nao sugere a causa. E o mesmo motivo pelo qual um recurso
"nao aparece" no console: ele abre na ultima regiao usada, e a deste projeto e
`us-east-1` (N. Virginia).

O `export-credentials` lê o cache que o comando anterior deixou em
`~/.aws/cli/cache` e exporta `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e
`AWS_SESSION_TOKEN` já assumidos. Vale pelo tempo de sessão da role — uma hora,
por padrão. Passado isso, repetir os dois comandos.

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
| `aws_subnet` (public) | `10.0.1.0/24`, `map_public_ip_on_launch = false` |
| `aws_subnet` (private) | `10.0.11.0/24`, `map_public_ip_on_launch = false` |
| `aws_internet_gateway` | Anexado à VPC |
| `aws_route_table` (public) | `0.0.0.0/0` → IGW |
| `aws_route_table` (private) | Sem rota default *(a rota para a ENI do bastion entra na Fase 2.1)* |
| `aws_route_table_association` (public, private) | Um subnet por tabela |
| `aws_security_group` (bastion) | UDP 51820 aberto; TCP 22 apenas de `admin_cidr`; todo o tráfego do subnet privado |
| `aws_security_group` (app) | TCP 22 do CIDR WireGuard; 80/443 dos ranges Cloudflare |
| `aws_network_acl` (public, private) | Espelham os SGs, mais portas efêmeras nos dois sentidos |
| `aws_network_acl_rule` | Uma regra por linha das tabelas de perímetro abaixo |

**Sobre `admin_cidr`:** variável que existe apenas para a janela de bootstrap.
Quando o WireGuard sobe (Fase 3.3), ela é esvaziada e a regra de SSH desaparece do
Security Group. Ver a sequência completa em [`../02-arquitetura.md`](../02-arquitetura.md).

**Sobre os ranges da Cloudflare:** obtidos dinamicamente via `data "http"` sobre
`https://www.cloudflare.com/ips-v4`, nunca fixados. Eles mudam. Hoje são 15
prefixos; o `data source` tem `postcondition` no código de status, porque uma
resposta de erro produziria uma lista vazia — e uma lista vazia não falha, apenas
apaga silenciosamente as regras de 80/443.

### As duas paredes, regra por regra

**Security Group do bastion** — entrada:

| Porta | Origem | Por quê |
|---|---|---|
| UDP 51820 | `0.0.0.0/0` | O peer administrativo conecta de onde estiver; quem autentica é a chave, não o endereço |
| TCP 22 | `admin_cidr` | Janela de bootstrap; a regra desaparece quando a lista fica vazia |
| todo o tráfego | `10.0.11.0/24` | **Requisito do NAT**, ver abaixo |

**Security Group do app** — entrada: TCP 22 do CIDR WireGuard, TCP 80 e 443 de
cada range da Cloudflare. Saída liberada nos dois.

**NACLs** — entrada e saída, por subnet:

| | Público | Privado |
|---|---|---|
| Entrada | todo o tráfego da VPC · UDP 51820 · TCP 80/443 · TCP 22 de `admin_cidr` · efêmeras TCP e UDP | todo o tráfego da VPC e do CIDR WireGuard · TCP 80/443 · efêmeras TCP e UDP |
| Saída | todo o tráfego da VPC · DNS 53 TCP/UDP · NTP 123 · TCP 80/443 · efêmeras TCP e UDP | idem, mais todo o tráfego do CIDR WireGuard |

### Decisões tomadas na implementação

**O Security Group do bastion precisa aceitar o subnet privado inteiro.** Isso não
estava nas regras previstas em [`../02-arquitetura.md`](../02-arquitetura.md) e é
o tipo de omissão que só aparece quando o NAT não funciona. O tráfego do host de
aplicação para a internet chega ao bastion pela ENI dele — e uma ENI é avaliada
pelo Security Group como qualquer outra entrada. Sem a regra, o roteamento existe,
a rota está correta, e nenhum pacote passa.

**A NACL é mais grossa que o Security Group, de propósito.** Uma NACL aceita 20
regras; 15 ranges da Cloudflare × 2 portas são 30. A restrição por origem do
tráfego web fica no Security Group, que é a fonte da verdade; a NACL confere
apenas a porta. Isso não é preguiça: a NACL existe para segurar um erro de
configuração no SG, e uma NACL que precise ser reescrita a cada mudança da
Cloudflare erraria mais do que protegeria.

**A saída das NACLs é lista explícita, não `allow all`.** Resolução de nome,
relógio, HTTP e HTTPS, mais as portas efêmeras de retorno. A consequência a
registrar: tráfego de saída para uma porta fora dessa lista é descartado pela
NACL, mesmo com o Security Group liberado. Se uma fase futura precisar de uma
porta nova de saída, ela entra naquela fase.

**O subnet público também tem `map_public_ip_on_launch = false`.** O bastion
recebe um Elastic IP explícito na Fase 2.1. Endereço público automático criaria um
segundo IP, efêmero, que muda a cada parada da instância e fica fora do alcance do
registro DNS.

**Os dois subnets ficam na mesma zona de disponibilidade.** Tráfego entre zonas é
cobrado por GB, e todo o tráfego do host de aplicação passa pelo bastion. A zona
vem da variável `availability_zone`; nula, usa a primeira da região.

**A tabela de rotas do subnet privado nasce sem rota default.** Uma rota que aponta
para uma ENI não pode ser declarada antes de a ENI existir. Até a Fase 2.1, o
subnet privado alcança apenas a própria VPC — o que é o comportamento correto, não
uma pendência.

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
- [ ] O Security Group do bastion aceita o CIDR do subnet privado — sem essa
      regra o NAT da Fase 2.1 não encaminha nada.
- [ ] Os dois subnets estão na mesma zona de disponibilidade.

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
| `aws_s3_bucket` (trail) | Bucket do CloudTrail, nome sufixado pelo identificador da conta |
| `aws_s3_bucket_public_access_block` | As quatro travas de acesso público ligadas |
| `aws_s3_bucket_versioning` | Preserva o objeto original quando algo o sobrescreve |
| `aws_s3_bucket_server_side_encryption_configuration` | `AES256`, com a chave gerenciada pelo S3 |
| `aws_s3_bucket_policy` | Permite escrita apenas ao serviço CloudTrail, e apenas em nome deste trail |
| `aws_s3_bucket_lifecycle_configuration` | Expira objetos antigos — evita crescimento indefinido |
| `aws_cloudtrail` | Multi-região, apenas management events (o trail gratuito), com validação de integridade |
| `aws_cloudwatch_log_group` | Retenção curta, para caber nos 5 GB gratuitos |
| `aws_iam_role` + `aws_iam_role_policy` (flow log) | Identidade do serviço de Flow Logs, restrita a esse único log group |
| `aws_flow_log` | VPC Flow Logs, `traffic_type = "REJECT"`, destino CloudWatch Logs |

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

### Decisões tomadas na implementação

**O log group dos Flow Logs fica fora do prefixo que as roles de instância podem
escrever.** A política de privilégio mínimo da Fase 1.1 dá às instâncias
`logs:PutLogEvents` em `/vps-infra/lab/*`. Um log de rede colocado ali seria
gravável pela própria máquina que ele existe para vigiar — e registro que o
vigiado pode escrever não é evidência. O grupo mora em `/aws/vpc/flow-logs/…`, que
nenhuma role de instância alcança.

**O serviço de Flow Logs precisa de uma role própria, que não estava na tabela do
plano.** Quem escreve no CloudWatch é o serviço, não a instância, e ele só escreve
assumindo uma role da conta. A trust policy carrega `aws:SourceAccount` e
`aws:SourceArn`, para que um flow log de outra conta não consiga usá-la — o mesmo
cuidado de confused deputy aplicado à política do bucket.

**A política do bucket é condicionada ao ARN do trail, e esse ARN é montado à
mão.** Ler `aws_cloudtrail.main.arn` criaria um ciclo: o trail só sobe depois que a
política autoriza a escrita, e a política precisaria do trail para existir. O ARN é
previsível a partir da região, da conta e do nome, então é construído em `locals`.
Sem a condição, qualquer trail de qualquer conta poderia pedir ao serviço que
entregasse neste bucket.

**Versionamento sem expiração de versão antiga não expira nada.** Com
versionamento ligado, a regra de ciclo de vida que expira só a versão corrente
apenas transforma o objeto em versão não-corrente, que fica no bucket para sempre.
A regra cobre as duas, e ainda aborta upload multipart incompleto.

**A criptografia do bucket é declarada, não herdada.** O S3 já criptografa por
padrão desde 2023; declarar `AES256` explicitamente faz uma eventual mudança
aparecer como diferença no `plan` em vez de passar despercebida. Custo zero, como
a chave gerenciada pela AWS.

**`force_destroy` do bucket do trail é variável, com padrão diferente por
ambiente.** O módulo assume `false` — o padrão seguro, que preserva os registros.
O `lab`, que é destruído ao final de cada sessão, passa `true`: ali o bucket que
sobrevive ao `destroy` é exatamente o recurso órfão descrito nos riscos.

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
- [ ] O bucket do trail recebeu objeto: `aws s3 ls` no prefixo `AWSLogs/` lista
      arquivo depois de alguns minutos — o trail pode estar ligado e não entregar.
- [ ] O log group dos Flow Logs **não** está sob o prefixo que as roles de
      instância podem escrever.

---

## Ao final da camada

A conta tem identidade controlada, teto de gasto vigiado, rede desenhada com duas
paredes e auditoria ligada — e ainda não custa praticamente nada, porque nenhuma
instância existe.

**Próxima:** [`camada-2-provisionamento.md`](./camada-2-provisionamento.md).
