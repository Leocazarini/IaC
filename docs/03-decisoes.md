# 03 — Decisões de arquitetura (ADRs)

Registro das decisões que moldam o projeto. Cada uma tem contexto, decisão,
consequência e o que foi descartado. Uma ADR não se reabre sem um motivo novo —
o objetivo é que sessões futuras não re-discutam o que já foi resolvido.

---

## ADR-001 — NAT por instância, não NAT Gateway

**Contexto.** Manter a instância de aplicação num subnet privado, como o guia de
segurança recomenda, exige um caminho de saída para a internet. A resposta
gerenciada da AWS é o NAT Gateway: US$ 0,045/hora (~US$ 32/mês) mais US$ 0,045 por
GB processado. Para um projeto pessoal, esse item sozinho custaria mais que todo o
resto do ambiente.

**Decisão.** O NAT é feito por uma instância `t4g.nano` própria no subnet público,
com `ip_forward` habilitado, `MASQUERADE` no iptables e `source_dest_check`
desabilitado na ENI.

**Consequências.**
- Custo de rede cai de ~US$ 35/mês para ~US$ 3/mês.
- Surge um host a mais para manter, endurecer, monitorar e aplicar patch.
- O NAT deixa de ser gerenciado: se a instância cair, o subnet privado perde a
  saída para a internet. Não há redundância multi-AZ.
- A largura de banda passa a ser limitada pela instância, não pelo serviço. Para
  o volume esperado, isso é irrelevante.

**Descartado.** *NAT Gateway* — custo desproporcional ao projeto. *Subnet público
com Security Group restrito e sem NAT* — mais barato ainda (US$ 0) e foi
considerado, mas abandona a segmentação de rede que o guia trata como camada
própria.

---

## ADR-002 — WireGuard como acesso administrativo, não Session Manager

**Contexto.** O guia de segurança propõe o AWS Systems Manager Session Manager
como equivalente nativo da VPN: acesso autenticado por IAM, sessões registradas,
nenhuma porta de entrada aberta, e custo zero. É tecnicamente superior ao WireGuard
em quase todos os aspectos — exceto um.

**Decisão.** O acesso administrativo é WireGuard, rodando no bastion.

**Consequências.**
- O contrato anti-lock-in permanece íntegro: o acesso administrativo funciona
  igual em qualquer provedor. Migrar não exige repensar como se entra na máquina.
- É necessário abrir UDP 51820 no Security Group do bastion — uma porta exposta
  que o Session Manager não exigiria. O WireGuard mitiga isso não respondendo a
  pacotes não autenticados: para um scanner, a porta é indistinguível de fechada.
- Há um servidor VPN a mais para manter, com rotação de chaves de peer manual.
- Perde-se o registro automático de sessão (keystroke logging) que o Session
  Manager oferece de graça.

**Descartado.** *Session Manager apenas* — cria dependência de AWS na camada de
acesso, justamente a camada que mais dói migrar. *Ambos em paralelo* — mais
robusto, mas são duas camadas de acesso para manter, documentar e endurecer;
assimetria de esforço para um projeto pessoal.

---

## ADR-003 — Detecção, segredos e backup self-hosted

**Contexto.** O guia propõe GuardDuty + Security Hub + Inspector para detecção,
Secrets Manager para segredos e AWS Backup para continuidade. Nenhum deles tem
free tier permanente: são trials de 15 a 30 dias, depois cobrança recorrente.
Somados, ficam entre US$ 15 e 30/mês para um ambiente pequeno.

**Decisão.** Usa-se da AWS apenas o que é gratuito de forma permanente —
CloudTrail (trail único para S3), VPC Flow Logs, IMDSv2, EBS encryption com chave
gerenciada pela AWS, SSM Parameter Store Standard. As demais funções ficam
self-hosted:

| Função | Serviço AWS descartado | Adotado |
|---|---|---|
| Detecção de intrusão | GuardDuty, Security Hub, Inspector | CrowdSec |
| Gestão de segredos | Secrets Manager (US$ 0,40/segredo/mês) | `ansible-vault` + Parameter Store Standard |
| Backup | AWS Backup | `restic` → Backblaze B2 |
| WAF | AWS WAF (US$ 5/ACL + US$ 1/regra) | Cloudflare (plano free) |

**Consequências.**
- Custo dessas camadas cai de ~US$ 25/mês para praticamente zero.
- Perde-se a correlação com a inteligência de ameaças da AWS que o GuardDuty faz
  sobre CloudTrail, DNS e Flow Logs em escala de conta inteira. O CrowdSec cobre
  o host, não a conta.
- Mais software para manter atualizado e mais responsabilidade operacional.
- **Nenhuma camada do guia é abandonada** — todas as nove continuam
  implementadas. O que muda é a implementação, não a cobertura.

**Descartado.** *AWS nativo pago* — melhor cobertura, custo incompatível com o
projeto. *Híbrido com GuardDuty apenas* — foi considerado por ser o de maior
valor real da tríade, mas mantém uma cobrança recorrente por uma camada que o
CrowdSec já cobre no nível que este ambiente exige.

---

## ADR-004 — Cloudflare na borda, não CloudFront + ALB + ACM + AWS WAF

**Contexto.** O guia mapeia a borda pública para CloudFront ou ALB, mais AWS WAF,
mais Shield, mais ACM. Um ALB custa ~US$ 23/mês fixo mesmo com tráfego zero, e o
AWS WAF cobra US$ 5 por Web ACL mais US$ 1 por regra. O guia também menciona o
Shield Advanced (US$ 3.000/mês), que está fora de questão.

**Decisão.** Toda a borda é Cloudflare no plano gratuito: DNS, proxy, WAF, TLS
Full (Strict) com certificado de origem. Gerenciada pelo provider Terraform da
Cloudflare.

**Consequências.**
- Custo da borda: US$ 0.
- O IP de origem fica escondido atrás do proxy, e o Security Group do host de
  aplicação aceita 80/443 apenas dos ranges publicados pela Cloudflare — o que
  torna o bypass do WAF impraticável.
- A borda deixa de ser AWS, o que na verdade reforça o contrato anti-lock-in: ela
  já não muda ao trocar de provedor de compute.
- O AWS Shield Standard continua ativo de graça na conta, protegendo o que ainda
  toca a AWS diretamente. É proteção redundante e não custa nada.
- Fica-se sujeito aos limites do plano free da Cloudflare (5 regras de WAF
  customizadas, sem log de requisição retido).

**Descartado.** *CloudFront no plano flat-rate Free* — hoje inclui CDN, WAF,
Shield, Route 53 e certificado por US$ 0/mês, com franquia de 1 M de requisições e
100 GB. É competitivo e foi avaliado, mas amarra DNS, WAF e TLS à AWS, contrariando
o contrato anti-lock-in. *ALB + AWS WAF + ACM* — ~US$ 40/mês para a mesma função.

---

## ADR-005 — Estado do Terraform local

**Contexto.** O padrão em ambientes de equipe é backend remoto (S3 + DynamoDB para
lock), o que garante estado compartilhado e travamento contra execuções
concorrentes.

**Decisão.** O estado fica local, em `terraform/envs/lab/terraform.tfstate`,
gitignored.

**Consequências.**
- Um operador, uma máquina, sem concorrência — o lock não resolve um problema que
  este projeto tem.
- Evita criar um bucket S3 e uma tabela DynamoDB só para isso.
- **O estado não é versionado nem replicado.** Perder a máquina significa perder o
  estado e ter que importar os recursos manualmente. Mitigado pelo fato de o
  ambiente `lab` ser descartável por natureza: o custo real de perder o estado é
  destruir os recursos órfãos pelo console e reaplicar.
- Migrar para backend remoto depois é uma operação de um comando
  (`terraform init -migrate-state`) — a decisão é reversível.

**Descartado.** *Backend S3 + DynamoDB* — correto para produção com mais de um
operador; prematuro aqui.

---

## ADR-006 — O bastion acumula NAT e WireGuard

**Contexto.** ADR-001 exige um host no subnet público para fazer NAT. ADR-002 exige
um host com endereço público para terminar o túnel WireGuard. São duas
necessidades e a mesma topologia atende as duas.

**Decisão.** Uma única instância `t4g.nano` no subnet público exerce os dois
papéis. Ela não roda aplicação.

**Consequências.**
- O custo de ~US$ 3/mês passa a servir duas funções.
- **Ponto único de falha:** se o bastion cair, o host de aplicação perde
  simultaneamente a saída para a internet e o acesso administrativo. O tráfego web
  dos usuários continua, porque passa pela Cloudflare direto para o Traefik.
- O bastion concentra exposição e por isso recebe hardening mais rigoroso que o
  host de aplicação — o inverso da intuição de que "o servidor importante é o de
  aplicação".
- **Regra permanente:** nenhuma aplicação, nenhum container e nenhum serviço extra
  no bastion. Ampliar o papel dele desfaz a segmentação de rede que justifica sua
  existência.

**Descartado.** *Dois hosts separados* — isola falhas, mas dobra o custo e a
superfície de manutenção para eliminar um risco aceitável num projeto pessoal.

---

## ADR-007 — CrowdSec no lugar do Fail2ban

**Contexto.** O manual usa Fail2ban: reativo, baseado em padrões de log local,
decisão isolada por máquina.

**Decisão.** Usa-se CrowdSec, mantendo a mesma posição na arquitetura.

**Consequências.**
- Ganha-se inteligência de ameaças comunitária: IPs que atacaram outros
  participantes já chegam bloqueados, antes da primeira tentativa aqui.
- A separação entre detecção (agente) e remediação (bouncer) permite bloquear na
  borda — há bouncer para Traefik e para Cloudflare — em vez de apenas no iptables
  local.
- É um componente a mais na cadeia, com sua própria configuração e atualização.
- O capítulo 10 do manual precisa de tradução ao ser implementado: os conceitos
  (jail, filtro, ação, tempo de banimento) mapeiam para CrowdSec, mas os arquivos
  e comandos são outros. Registrar a tradução em
  [`camadas/camada-3-host.md`](./camadas/camada-3-host.md).

**Descartado.** *Fail2ban* — fiel ao manual e mais simples, mas puramente reativo
e local. A troca custa pouco e eleva a camada de detecção de forma desproporcional
ao esforço.

---

## ADR-008 — Ubuntu Server LTS como imagem base

**Contexto.** O guia recomenda uma AMI endurecida conforme CIS Benchmark em vez da
imagem pública crua. AMIs CIS prontas existem no AWS Marketplace, mas são pagas
(cobrança por hora de instância).

**Decisão.** AMI oficial da Canonical (Ubuntu Server 22.04 LTS ou superior),
selecionada dinamicamente por `data source`, com o hardening aplicado por Ansible
em vez de vir pronto na imagem.

**Consequências.**
- Sem custo de licenciamento de AMI.
- O hardening fica versionado e auditável no repositório, em vez de opaco dentro
  de uma imagem — o que é preferível para um projeto cujo objetivo é justamente
  descrever a infra como código.
- O tempo de bootstrap é maior: a instância sobe crua e é endurecida depois.
- **Não se atinge conformidade CIS formal.** Aplica-se o hardening do manual, que
  cobre os itens de maior impacto, sem passar por auditoria de benchmark.
- Fica em aberto, para uma fase futura, construir uma AMI dourada com Packer a
  partir do próprio Ansible — o que reduziria o tempo de bootstrap sem abrir mão
  da rastreabilidade.

**Descartado.** *AMI CIS do Marketplace* — conformidade pronta, custo recorrente e
hardening opaco. *Amazon Linux* — melhor integração com a AWS, mas divergiria do
manual inteiro, que é escrito para Debian/Ubuntu.

---

## ADR-009 — Usuário IAM com `assume-role` e MFA, não IAM Identity Center

**Contexto.** O guia de segurança e a Fase 1.1 previam o IAM Identity Center como
a forma de sair do usuário root: identidade centralizada, credencial de curta
duração, sem access key permanente. O serviço em si é gratuito.

Ao tentar ativá-lo, o console avisou que a conta perderia o free tier. O motivo:
uma conta standalone só consegue um **organization instance** do Identity Center,
e criar esse instance **cria uma AWS Organization** com a própria conta como
management account. Nos termos do Free account plan, entrar no AWS Organizations
é uma das sete ações que convertem a conta para o plano pago — e os créditos
**expiram imediatamente**, não são transferidos.

A alternativa dentro do próprio serviço, o **account instance**, não exige
Organizations, mas só faz atribuição de *aplicações* dentro da conta. Não concede
acesso administrativo à conta AWS, que é exatamente o que a Fase 1.1 precisa.

**Decisão.** O acesso administrativo é um usuário IAM sem permissão própria, que
assume uma role de administração com `sts:AssumeRole` condicionado a MFA. O perfil
do `aws-cli` é configurado com `role_arn` + `mfa_serial`, de modo que a credencial
efetivamente usada pelo Terraform é temporária. O root fica com MFA e sai de uso.

**Consequências.**
- O Free account plan é preservado: os créditos e o prazo de 6 meses continuam
  valendo, e a premissa de custo do projeto (ADR-003, ADR-004) não é abandonada
  logo na primeira fase.
- A credencial que o Terraform usa é de curta duração e exige MFA a cada sessão —
  o essencial do que o Identity Center entregaria.
- **Sobra uma access key de vida longa**, a do usuário IAM. É a diferença real
  para o Identity Center, e não desaparece: mitiga-se mantendo essa key sem
  nenhuma permissão além de assumir a role, e rotacionando-a.
- Perde-se o portal de acesso, o login federado e a gestão de identidade
  centralizada. Para um operador só, nenhum dos três resolve um problema existente.
- **A decisão é reversível e tem hora marcada para ser revista:** quando o Free
  account plan encerrar e a conta migrar para o Paid account plan, o custo de
  ativar o Identity Center passa a ser zero. Ver [`04-custos.md`](./04-custos.md).

**Descartado.** *Identity Center (organization instance)* — melhor postura de
identidade, mas o preço é o free tier inteiro e a conversão para pay-as-you-go
desde o primeiro dia. *Identity Center (account instance)* — preserva o free tier,
mas não faz acesso administrativo à conta; resolveria outro problema. *Usuário IAM
administrativo com access key direta* — mais simples, mas deixa uma credencial
permanente com privilégio administrativo, que é o pior dos dois mundos.
