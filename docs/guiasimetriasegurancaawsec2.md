# Guia de Simetria de Camadas de Segurança — Ambiente AWS (EC2)

> Baseado no modelo de "defesa em profundidade" do seu guia de self-hosting Linux, traduzido para os serviços nativos da AWS. Objetivo: nenhuma camada deve ficar muito mais forte (ou mais fraca) que as outras.

## 1. O que significa "simetria" em segurança, e por que ela importa mais que "força"

A maioria dos ambientes inseguros não tem uma camada fraca por falta de esforço — tem uma camada **fraca por desequilíbrio**. É comum ver um WAF caríssimo e bem configurado na borda, protegendo uma aplicação cujo IAM dá permissão de administrador para tudo, ou um Security Group bem fechado na frente de uma instância sem nenhum log de auditoria habilitado.

Isso importa porque **o nível de segurança real do seu ambiente é o nível da sua camada mais fraca, não a média das camadas**. Um invasor não precisa vencer a sua melhor defesa — ele procura a camada que você deixou para depois. Por isso, antes de aprofundar qualquer camada, o primeiro objetivo de engenharia é garantir que todas estejam, no mínimo, no mesmo patamar de maturidade.

O guia que você está seguindo já ensina esse raciocínio para uma VPS genérica: borda (Cloudflare) → perímetro de rede (firewall) → acesso administrativo (VPN) → host (SSH hardening) → detecção (Fail2ban). A AWS tem um equivalente nativo para cada uma dessas camadas — e, como veremos, mais duas camadas que o modelo de VPS não cobre explicitamente (identidade/IAM e criptografia gerenciada), que numa conta AWS **não são opcionais**: ignorá-las cria a assimetria mais comum de todas.

## 2. Mapa de equivalência: self-hosting → AWS nativo

| Camada (função) | Como o guia resolve em uma VPS | Equivalente nativo na AWS |
|---|---|---|
| Borda / entrada pública | Cloudflare Proxy + WAF + SSL Full (Strict) | Amazon CloudFront ou ALB + AWS WAF + AWS Shield + ACM (certificados TLS gerenciados) |
| Perímetro de rede | iptables, política padrão-bloqueio | Security Groups (com deny-by-default implícito) + Network ACLs + subnets públicas/privadas na VPC |
| Acesso administrativo | Túnel VPN (WireGuard) dedicado | AWS Systems Manager Session Manager e/ou EC2 Instance Connect Endpoint (sem porta de entrada exposta) |
| Hardening do host / SSH | Chaves apenas, sem login root | IMDSv2 obrigatório, sem SSH exposto à internet, IAM Instance Profile em vez de credenciais fixas |
| Identidade e segredos | *(não coberto diretamente no guia)* | IAM com privilégio mínimo, IAM Identity Center, MFA, AWS Secrets Manager / Parameter Store |
| Criptografia em repouso | Disco da VPS sem gestão de chave centralizada | Amazon EBS Encryption com AWS KMS (chaves gerenciadas pelo cliente) |
| Detecção e resposta | Fail2ban (reativo, baseado em log local) | Amazon GuardDuty + AWS Security Hub + Amazon Inspector (scanning contínuo de vulnerabilidades) |
| Observabilidade | Netdata, Grafana, Loki, Uptime Kuma | Amazon CloudWatch (métricas, logs, alarmes) + VPC Flow Logs + AWS CloudTrail (auditoria de API) |
| Manutenção / continuidade | Backup manual, atualizações agendadas | AWS Backup + Systems Manager Patch Manager + AMI dourada (imagem base com hardening CIS) |

Note que as duas linhas "Identidade e segredos" e "Criptografia em repouso" não têm um capítulo dedicado no guia de self-hosting — porque numa VPS tradicional isso é resolvido de forma mais simples (um usuário, uma chave SSH). Na AWS, a camada de identidade (IAM) é, na prática, **a camada mais crítica de todas**, porque credenciais mal configuradas dão acesso a todas as outras camadas de uma vez. Deixar essa camada em segundo plano é o erro de assimetria mais comum em contas AWS novas.

## 3. Detalhamento de cada camada

Para cada camada: o objetivo, o porquê (o raciocínio de engenharia por trás), e o que verificar.

### 3.1 Borda pública (Edge)
**Objetivo:** nenhuma requisição maliciosa ou não criptografada deve chegar perto da sua instância.
**Por quê:** assim como o guia esconde o IP real da VPS atrás da Cloudflare, na AWS você nunca deve expor o IP público da instância EC2 diretamente à internet para tráfego de aplicação. Um CloudFront ou Application Load Balancer na frente permite terminar TLS de forma gerenciada, aplicar regras de WAF (bloqueio de SQLi, XSS, rate limiting) e absorver ataques volumétricos com o AWS Shield Standard (incluído automaticamente).
**Verificar:** a instância EC2 está em subnet privada, sem IP público? O certificado TLS está no ACM (renovação automática)? Existem regras de WAF ativas (não só criadas, mas em modo "block", não "count")?

### 3.2 Perímetro de rede (VPC)
**Objetivo:** replicar o "bloqueia tudo, exceto o necessário" do iptables, mas em duas camadas (stateful e stateless).
**Por quê:** Security Groups (stateful, por instância/recurso) fazem o papel do iptables do guia. Network ACLs (stateless, por subnet) são uma camada extra que a VPS não tem — funcionam como uma segunda muralha caso um Security Group seja mal configurado. Ter as duas configuradas de forma equivalente é o que garante simetria dentro da própria camada de rede.
**Verificar:** nenhum Security Group libera `0.0.0.0/0` em portas de administração (22, 3389, bancos de dados)? Subnets de banco de dados/aplicação são privadas (sem rota para Internet Gateway)?

### 3.3 Acesso administrativo
**Objetivo:** eliminar a necessidade de expor qualquer porta de administração à internet — indo além do que a VPN do guia já faz.
**Por quê:** o guia usa uma VPN dedicada para não expor SSH publicamente. Na AWS, o Systems Manager Session Manager faz o mesmo, mas sem precisar manter servidor de VPN: o acesso passa pela API da AWS, autenticado via IAM, com todas as sessões logadas (keystroke logging) e sem nenhuma porta de entrada aberta no Security Group.
**Verificar:** a porta 22 está fechada para `0.0.0.0/0` em todos os Security Groups? O SSM Agent está instalado e a instância tem a IAM role `AmazonSSMManagedInstanceCore`?

### 3.4 Hardening do host
**Objetivo:** mesmo com acesso controlado, a instância deve resistir a abusos vindos de dentro da própria infraestrutura.
**Por quê:** o IMDSv2 (token-based) evita que uma vulnerabilidade de SSRF na aplicação seja usada para roubar as credenciais temporárias da instância — um vetor de ataque que não existe em VPS tradicionais e que muitas contas AWS deixam configurado no modo antigo (IMDSv1) por padrão em imagens mais antigas.
**Verificar:** IMDSv2 está marcado como obrigatório (`HttpTokens: required`) em todas as instâncias? A AMI usada segue uma linha de base com hardening (CIS Benchmark) e não a imagem pública "crua"?

### 3.5 Identidade e segredos (IAM)
**Objetivo:** cada componente (pessoa, aplicação, instância) tem exatamente a permissão de que precisa — nada além disso.
**Por quê:** essa é a camada que, se deixada assimétrica, invalida todas as outras. Um Security Group perfeito não importa se a aplicação rodando na instância tem uma IAM role com permissão de administrador. É o "usuário root sem senha" da AWS.
**Verificar:** o usuário root da conta tem MFA e não é usado no dia a dia? O acesso humano é via IAM Identity Center (SSO) com papéis temporários, não usuários IAM com chave de acesso fixa? Segredos de aplicação (senhas de banco, tokens de API) estão no Secrets Manager/Parameter Store, nunca em variável de ambiente hardcoded ou no user-data da instância?

### 3.6 Criptografia em repouso
**Objetivo:** dados parados (disco, snapshot, backup) protegidos mesmo se alguém tiver acesso físico ou a uma cópia.
**Por quê:** o guia já cobre criptografia em trânsito (SSL Full Strict); a AWS adiciona criptografia em repouso de forma simples e sem custo de performance perceptível — deixar isso desligado é uma assimetria fácil de evitar.
**Verificar:** a criptografia de EBS por padrão está habilitada na região? Os volumes e snapshots usam uma chave gerenciada pelo cliente no KMS (não a chave padrão da AWS, se você precisar de controle sobre rotação/revogação)?

### 3.7 Detecção e resposta
**Objetivo:** substituir a reação manual do Fail2ban por detecção contínua e automatizada, em escala de conta inteira.
**Por quê:** o Fail2ban reage a padrões em um log local, de uma máquina. O GuardDuty analisa CloudTrail, DNS e VPC Flow Logs de toda a conta, correlacionando com inteligência de ameaças da AWS. O Inspector faz o papel que nenhuma ferramenta do guia cobre: escaneamento contínuo de vulnerabilidades conhecidas (CVEs) no sistema operacional e nas dependências.
**Verificar:** GuardDuty está habilitado em todas as regiões usadas (não só na região principal)? Os findings de GuardDuty/Inspector chegam a algum lugar monitorado (Security Hub, e-mail, chat), ou ficam apenas acumulando no console sem ninguém ver?

### 3.8 Observabilidade
**Objetivo:** saber o que está acontecendo antes, durante e depois de qualquer incidente.
**Por quê:** Netdata/Grafana/Loki monitoram a saúde da máquina; CloudWatch faz o mesmo na AWS, mas o CloudTrail adiciona algo que o guia de VPS não precisa cobrir: um registro imutável de **quem fez o quê na conta AWS** (quem mudou um Security Group, quem criou uma chave de acesso). Sem CloudTrail habilitado, um incidente de segurança na conta é praticamente impossível de investigar depois.
**Verificar:** CloudTrail está habilitado como "organization trail" ou em todas as regiões, com os logs indo para um bucket S3 com acesso restrito? Existem alarmes no CloudWatch para eventos sensíveis (ex: login do root, mudança de Security Group, desativação do CloudTrail)?

### 3.9 Manutenção e continuidade
**Objetivo:** o mesmo cuidado de backup/atualização do guia, mas automatizado e auditável.
**Por quê:** backup manual funciona até alguém esquecer de rodar. AWS Backup centraliza e agenda snapshots com política de retenção; o Patch Manager garante que os patches de segurança do SO saem em janela controlada, sem depender de alguém lembrar.
**Verificar:** existe um plano de backup com teste de restauração já validado (não só snapshot configurado)? As instâncias recebem patches de segurança em um cronograma definido, não "quando alguém lembrar"?

## 4. Scorecard de simetria

Preencha isto para o seu ambiente atual (0 = inexistente, 1 = básico/manual, 2 = configurado, 3 = maduro/automatizado/testado). O objetivo não é maximizar cada nota isoladamente — é **reduzir a diferença entre a nota mais alta e a mais baixa**.

| Camada | Nota (0–3) |
|---|---|
| Borda pública (CDN/WAF/TLS) | |
| Perímetro de rede (SG/NACL) | |
| Acesso administrativo (Session Manager) | |
| Hardening do host (IMDSv2, AMI) | |
| Identidade e segredos (IAM) | |
| Criptografia em repouso (KMS) | |
| Detecção e resposta (GuardDuty/Inspector) | |
| Observabilidade (CloudWatch/CloudTrail) | |
| Manutenção e continuidade (Backup/Patch) | |

Se alguma camada estiver em 0 ou 1 enquanto outras estão em 3, essa é a camada a atacar primeiro — independente de qual pareça "mais importante" abstratamente.

## 5. Roteiro de implementação do zero

Seguindo a mesma lógica de fases do seu guia (Provisionar → Proteger → Operar → Observar → Manter), adaptada para começar uma conta AWS já simétrica desde o início, em vez de simetrizar depois:

**Fase 0 — Fundação da conta**
Ativar MFA no usuário root, criar o primeiro usuário administrativo via IAM Identity Center, configurar alarme de billing, decidir a região principal.

**Fase 1 — Rede (VPC)**
Criar VPC com subnets públicas (para o ALB/CloudFront) e privadas (para as instâncias), sem rota direta da internet para as subnets privadas.

**Fase 2 — Borda**
Configurar ALB ou CloudFront, ACM para o certificado, AWS WAF em modo "count" primeiro (para calibrar regras sem bloquear tráfego legítimo), depois mudar para "block".

**Fase 3 — Acesso administrativo e hardening do host**
Lançar a instância já com IMDSv2 obrigatório, IAM Instance Profile com a role do SSM, Security Group sem nenhuma porta de administração aberta.

**Fase 4 — Identidade e segredos**
Criar as IAM roles de aplicação com privilégio mínimo antes de instalar qualquer coisa nelas; mover qualquer segredo para o Secrets Manager antes de colocar a aplicação em produção.

**Fase 5 — Criptografia**
Habilitar criptografia de EBS por padrão na região antes de criar qualquer volume.

**Fase 6 — Detecção**
Ativar GuardDuty, Security Hub e Inspector antes de expor qualquer coisa publicamente — não depois de um incidente.

**Fase 7 — Observabilidade**
CloudTrail multi-região ligado desde o primeiro dia (o maior erro comum é ativá-lo só depois que algo já aconteceu, perdendo o histórico justamente do período mais crítico).

**Fase 8 — Manutenção**
AWS Backup e Patch Manager configurados antes de haver dados de produção para perder.

Um ponto de engenharia importante: se você fizer isso via console manualmente, cada ambiente futuro (homologação, produção, uma segunda conta) corre o risco de sair ligeiramente diferente — que é exatamente a assimetria que você quer evitar. Quando estiver confortável com o porquê de cada camada, vale considerar descrever essa configuração como código (Terraform ou AWS CloudFormation), para que qualquer ambiente novo nasça já com o mesmo nível de segurança nas nove camadas, por definição.

## 6. Perguntas para você validar sozinho

Antes de considerar qualquer camada "pronta", vale se perguntar: se eu tentasse acessar essa camada de fora, sem ser eu mesmo, o que aconteceria? Por exemplo: tentar abrir a porta 22 da instância pela internet (deve falhar), verificar se o GuardDuty está realmente ativo em todas as regiões que você usa (não só na principal), e confirmar que os logs do CloudTrail realmente chegam a um lugar que alguém olha — não apenas que a opção está marcada como "habilitada" no console.

---

**Fontes consultadas para validar práticas atuais (2026):**
- [AWS EC2 Security Best Practices 2026 — Toc Consulting](https://tocconsulting.fr/best-practices/ec2-security)
- [AWS VPC Security Best Practices 2026 — Toc Consulting](https://tocconsulting.fr/best-practices/vpc-security)
- [12 AWS Cloud Security Best Practices for 2026 — Qualys](https://blog.qualys.com/product-tech/2026/04/09/1aws-cloud-security-best-practices-guide)
