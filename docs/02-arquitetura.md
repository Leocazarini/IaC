# 02 — Arquitetura

## Visão geral

```
                              Internet
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
              tráfego web                 acesso administrativo
                    │                           │
                    ▼                           ▼
        ┌───────────────────────┐        UDP 51820 (WireGuard)
        │      Cloudflare       │                │
        │  proxy · WAF · TLS    │                │
        │     (plano free)      │                │
        └───────────┬───────────┘                │
                    │                            │
════════════════════│════════════════════════════│══════════════════
                    │      VPC 10.0.0.0/16       │
                    ▼                            ▼
   ┌────────────────────────────────────────────────────────────┐
   │  subnet-public-a          10.0.1.0/24                      │
   │  ┌──────────────────────────────────────────────────────┐  │
   │  │  bastion   t4g.nano   [Elastic IP]                   │  │
   │  │   • NAT           — MASQUERADE, source/dest check    │  │
   │  │                     desabilitado                     │  │
   │  │   • WireGuard     — termina a VPN administrativa     │  │
   │  │   • IMDSv2 required, EBS encrypted                   │  │
   │  └────────────────────────┬─────────────────────────────┘  │
   └───────────────────────────│────────────────────────────────┘
                               │  rota 0.0.0.0/0 do subnet privado
                               │  aponta para a ENI do bastion
   ┌───────────────────────────▼────────────────────────────────┐
   │  subnet-private-a         10.0.11.0/24                     │
   │  ┌──────────────────────────────────────────────────────┐  │
   │  │  app       t3.micro   (sem IP público)               │  │
   │  │   • Docker + Traefik                                 │  │
   │  │   • IMDSv2 required, EBS encrypted                   │  │
   │  │   • SSH aceito apenas do CIDR do WireGuard           │  │
   │  └──────────────────────────────────────────────────────┘  │
   └────────────────────────────────────────────────────────────┘

   NACLs (stateless) em ambos os subnets — segunda parede
   Internet Gateway apenas no subnet público

════════════════════════════════════════════════════════════════
   Auditoria e observabilidade AWS, custo zero:
   CloudTrail → bucket S3 restrito
   VPC Flow Logs (apenas REJECT) → CloudWatch Logs
```

---

## Endereçamento

| Recurso | CIDR / valor | Observação |
|---|---|---|
| VPC | `10.0.0.0/16` | Espaço amplo, deixa margem para subnets futuros |
| subnet-public-a | `10.0.1.0/24` | Único com rota para o Internet Gateway |
| subnet-private-a | `10.0.11.0/24` | Rota de saída via ENI do bastion |
| Rede WireGuard | `10.8.0.0/24` | Não sobrepõe a VPC; peers administrativos |
| Bastion (privado) | `10.0.1.10` | IP fixo dentro do subnet, referenciado nas rotas |
| App (privado) | `10.0.11.10` | IP fixo, referenciado no inventário do Ansible |

O bastion tem também um Elastic IP público — o único endereço público do ambiente,
e o alvo dos registros DNS.

---

## O bastion acumula duas funções

Esta é a decisão de arquitetura mais consequente do projeto, e vale entender o
porquê. Ver ADR-001 e ADR-006 em [`03-decisoes.md`](./03-decisoes.md).

Manter a instância de aplicação num subnet privado exige que algo faça o roteamento
de saída para a internet (atualizações de pacote, pull de imagens Docker). A
resposta gerenciada da AWS para isso é o NAT Gateway, que custa cerca de US$ 35 por
mês — mais caro que todo o resto do ambiente somado.

Ao mesmo tempo, o acesso administrativo escolhido foi WireGuard, que precisa de um
host com endereço público para terminar o túnel.

São duas necessidades, e uma única instância `t4g.nano` de ~US$ 3/mês resolve as
duas. O bastion é simultaneamente o roteador NAT do subnet privado e o servidor
WireGuard.

**O que isso implica:**

- O bastion é o único ponto de falha do ambiente. Se ele cair, o host de aplicação
  perde a saída para a internet e o acesso administrativo simultaneamente. O
  tráfego web dos usuários, porém, continua funcionando (passa pela Cloudflare
  direto para o Traefik).
- Por acumular funções, o bastion recebe hardening mais rigoroso que o host de
  aplicação, não menos. Ele é o alvo mais exposto.
- `source_dest_check` precisa estar desabilitado na instância, senão a AWS descarta
  os pacotes que ele roteia em nome de terceiros.
- O bastion **não roda aplicação**. Nenhum container, nenhum serviço além de NAT,
  WireGuard e o mínimo de observabilidade. Ampliar o papel dele reintroduz o
  problema que a segmentação de rede resolve.

---

## Sequência de bootstrap

Há um problema de ordem que precisa ser resolvido explicitamente: o Ansible
configura o WireGuard, mas o acesso administrativo definitivo depende do WireGuard
já estar de pé. E o host de aplicação, num subnet privado, só é alcançável depois
que o bastion existe e roteia.

A sequência obrigatória é:

```
 1. terraform apply
    └── cria VPC, subnets, SG, NACL, bastion e app
        SG do bastion abre a porta 22 apenas para o IP do operador
        (variável `admin_cidr`, janela de bootstrap)

 2. ansible-playbook no bastion, via IP público, porta 22
    ├── role base
    ├── role ssh_hardening
    ├── role nat          → ip_forward + MASQUERADE
    └── role wireguard    → sobe o servidor VPN

 3. operador levanta o túnel WireGuard na máquina local
    └── valida: ping no IP privado do bastion pelo túnel

 4. fecha a janela de bootstrap
    └── terraform apply com `admin_cidr` removido
        SG do bastion passa a expor apenas UDP 51820

 5. ansible-playbook no host app, via túnel, pelo IP privado
    └── daqui em diante, todo acesso passa pela VPN
```

**Fallback documentado:** para execução não interativa (um pipeline futuro), o
Ansible pode alcançar o host privado por `ProxyJump` através do bastion, sem
depender do túnel. Isso é uma alternativa de conveniência, não o caminho
principal — o acesso humano do dia a dia é sempre pela VPN.

---

## Perímetro em duas paredes

O guia insiste que Security Groups e NACLs são camadas distintas e que ter as duas
configuradas de forma equivalente é o que garante simetria dentro da própria rede.
A diferença prática:

| | Security Group | Network ACL |
|---|---|---|
| Escopo | Por instância (ENI) | Por subnet |
| Comportamento | Stateful — resposta é liberada automaticamente | Stateless — precisa de regra explícita nos dois sentidos |
| Padrão | Nega tudo; só existe regra de permissão | Permite tudo por padrão; aceita regras de negação |
| Papel aqui | Parede principal, granular | Segunda parede, contra erro de configuração no SG |

Como as NACLs são stateless, cada regra de entrada precisa de uma regra de saída
correspondente para as **portas efêmeras** (`1024–65535`). Esse é o erro clássico
de quem configura NACL pela primeira vez, e está registrado no checklist de
validação da Fase 1.2.

### Regras previstas

**SG do bastion**
- Entrada: UDP 51820 de qualquer origem (WireGuard); TCP 22 apenas de `admin_cidr`
  durante a janela de bootstrap, removido depois.
- Saída: liberada (precisa rotear o tráfego do subnet privado).

**SG do app**
- Entrada: TCP 22 apenas do CIDR do WireGuard; TCP 80/443 apenas dos ranges de IP
  publicados pela Cloudflare.
- Saída: liberada.

**NACL do subnet público** — espelha o SG do bastion, mais as portas efêmeras.
**NACL do subnet privado** — permite tráfego de/para a VPC e a saída via bastion.

Detalhamento na [`camadas/camada-1-fundacao-aws.md`](./camadas/camada-1-fundacao-aws.md).

---

## Contrato anti-lock-in

Toda lógica específica da AWS vive dentro de `terraform/modules/compute-aws/`.
Nada fora desse módulo referencia um recurso AWS. O módulo expõe um contrato fixo
de saídas:

```hcl
output "public_ip"   { }   # endereço público do bastion
output "ssh_user"    { }   # usuário de conexão inicial
output "ssh_port"    { }   # porta SSH efetiva
output "instance_id" { }   # identificador da instância no provedor
```

O Ansible consome apenas `public_ip`, `ssh_user` e a chave SSH, através de um
inventário gerado por `scripts/gen-inventory.sh` a partir de
`terraform output -json`. O módulo Cloudflare consome apenas `public_ip`.

**A consequência que justifica o esforço:** trocar de provedor no futuro significa
escrever um `modules/compute-hetzner/` que exponha os mesmos quatro outputs. O
Ansible inteiro — todas as roles, todo o hardening, toda a plataforma — e o módulo
Cloudflare não mudam uma linha.

Isso também é o motivo de o acesso administrativo ser WireGuard e não o Session
Manager da AWS, e de o DNS/TLS/WAF serem Cloudflare e não Route 53 + ACM + AWS WAF.
Ver ADR-002 e ADR-004.

### Tradução de conceitos do manual

O manual foi escrito para uma VPS genérica. Onde ele fala de recursos do painel do
provedor, a tradução para AWS é:

| Manual (VPS) | Equivalente AWS |
|---|---|
| Snapshot pelo painel | Snapshot de EBS / AMI |
| Firewall do provedor desabilitado | SG permissivo apenas na janela de bootstrap; o firewall real é o do host |
| IP fixo do painel | Elastic IP |
| Console de recuperação | EC2 Serial Console / Session Manager como quebra-galho |
| Redimensionar plano | Trocar o tipo da instância |

Cada tradução usada é registrada no documento da camada correspondente — **nunca
em comentário de código**. Ver [`06-convencoes.md`](./06-convencoes.md).

---

## Ambiente

Existe um único ambiente, `lab`, propositalmente descartável. Ele é criado no
início de uma sessão de teste, validado, e destruído ao final com
`terraform destroy`. A infra não fica de pé entre sessões enquanto o projeto está
em construção — isso mantém o custo perto de zero e força a provar, a cada fase,
que o deploy do zero realmente funciona.

Estado do Terraform em `terraform/envs/lab/terraform.tfstate`, local e gitignored.
