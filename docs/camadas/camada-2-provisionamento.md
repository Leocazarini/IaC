# Camada 2 — Provisionamento

As instâncias e o que as cerca. É aqui que o custo do projeto começa de fato, e é
aqui que o contrato anti-lock-in ganha forma concreta.

**Ferramenta:** Terraform (+ shell). **Capítulos do manual:** 01–04.

> **Antes de começar:** resolver a pendência P1 em [`../PROGRESS.md`](../PROGRESS.md)
> — qual é o modelo de free tier da conta. Ela determina se a `t3.micro` sai de
> graça ou custa ~US$ 7,50/mês.

---

## Fase 2.1 — Bastion

**Branch:** `feat/c2f1-bastion`
**Capítulos:** 01–02

### Objetivo

Criar a instância que faz NAT para o subnet privado e termina a VPN
administrativa. Ver ADR-001 e ADR-006 em [`../03-decisoes.md`](../03-decisoes.md)
para o porquê de acumular as duas funções.

### O que vira Terraform

| Recurso | Detalhe |
|---|---|
| `aws_instance` (bastion) | `t4g.nano` (ARM Graviton), AMI Ubuntu via `data source` |
| `aws_eip` + `aws_eip_association` | O único endereço público do ambiente |
| `aws_key_pair` | Chave pública do operador |
| `aws_route` (private → ENI) | Fecha a rota declarada na Fase 1.2 |

### Configurações que não podem faltar

```
source_dest_check    = false            # sem isto a AWS descarta o tráfego roteado
metadata_options {
  http_tokens   = "required"            # IMDSv2 obrigatório
  http_endpoint = "enabled"
}
root_block_device {
  encrypted = true                      # redundante com o default da região, explícito por segurança
  volume_type = "gp3"
}
```

**`source_dest_check = false` é a linha mais fácil de esquecer e a mais difícil de
diagnosticar.** Por padrão a AWS descarta pacotes cuja origem ou destino não seja
a própria instância — que é exatamente o que um roteador NAT faz o tempo todo. O
sintoma é o subnet privado sem saída para a internet, sem nenhum erro visível.

**Por que IMDSv2 obrigatório:** o endpoint de metadados entrega as credenciais
temporárias da instance profile. No IMDSv1, um `GET` simples basta — o que
significa que uma falha de SSRF na aplicação vira roubo de credencial da AWS.
O IMDSv2 exige um token obtido por `PUT` com header próprio, que um SSRF comum não
consegue produzir. É um vetor que não existe em VPS tradicional e que muitas AMIs
antigas ainda deixam aberto por padrão.

### Escolha do tipo de instância

`t4g.nano` — ARM Graviton, ~US$ 3/mês. **Não é elegível ao free tier** (a lista
inclui `t4g.micro`, não `t4g.nano`), e isso está previsto na estimativa. O
`t4g.micro` seria gratuito, mas consumiria as mesmas 750 h/mês que a instância de
aplicação precisa — numa conta legado, cobrir o bastion com o free tier significa
descobrir a aplicação.

Por ser ARM, os pacotes e imagens Docker precisam ter build `arm64`. Para NAT e
WireGuard isso não é restrição.

### Riscos

- **Elastic IP não associado continua sendo cobrado.** Um `destroy` parcial que
  deixe o EIP para trás gera fatura silenciosa.
- A rota do subnet privado aponta para uma ENI específica. Recriar a instância
  gera ENI nova; a rota precisa ser atualizada junto — garantido por dependência
  explícita no Terraform.
- Perder a chave SSH nesta fase, antes do WireGuard existir, significa recriar a
  instância. Não há outro caminho de entrada.

### Checklist de validação

- [ ] SSH no EIP funciona a partir do `admin_cidr`, e falha de outro IP.
- [ ] `aws ec2 describe-instances` mostra `SourceDestCheck: false`.
- [ ] `HttpTokens: required` nas opções de metadados.
- [ ] Volume raiz criptografado.
- [ ] Route table do subnet privado aponta para a ENI do bastion.
- [ ] Instância tem as tags `Project`, `Env`, `Phase`, `ManagedBy`.

---

## Fase 2.2 — Host de aplicação

**Branch:** `feat/c2f2-app-host`
**Capítulos:** 01–02

### Objetivo

Criar a instância que roda a aplicação, no subnet privado, sem endereço público.

### O que vira Terraform

| Recurso | Detalhe |
|---|---|
| `aws_instance` (app) | `t3.micro`, sem IP público, subnet privado |
| `aws_ebs_volume` + attachment | Volume separado para `/srv` *(avaliar na fase)* |

Mesmas opções obrigatórias do bastion: IMDSv2 `required`, volume criptografado,
tags completas. `source_dest_check` permanece no padrão (`true`) — este host não
roteia nada.

### Sobre o volume de dados

Manter `/srv` (dados de aplicação, volumes Docker) num volume EBS separado do
volume raiz permite recriar a instância sem perder dados, e tirar snapshot só do
que importa. O custo é baixo (~US$ 0,08/GB/mês em gp3).

Fica como decisão da fase: se o volume raiz de 8 GB comportar tudo com folga no
início, um volume separado pode ser adiado — mas separá-lo depois exige migração
de dados, então a inclinação é fazer desde já.

### Riscos

- **Neste ponto o host não é alcançável.** Sem IP público e sem o WireGuard (Fase
  3.3), não há como entrar nele. Isso é esperado, não é falha. A validação desta
  fase é feita de dentro do bastion.
- `t3.micro` tem 1 GB de RAM. Docker + Traefik + a stack de observabilidade
  (Grafana, Loki, Prometheus, Uptime Kuma) é apertado. **Registrar como risco
  aberto para a Camada 7:** pode ser necessário `t3.small` ou reduzir a stack.
  A decisão pertence à Camada 7, com dados reais de consumo — não se antecipa aqui.
- `t3` opera em modo *unlimited* por padrão em algumas configurações, o que gera
  cobrança por CPU credit surplus. Verificar `credit_specification`.

### Checklist de validação

- [ ] Instância não tem IP público (`PublicIpAddress` ausente).
- [ ] A partir do bastion, `ping` e `ssh` no IP privado funcionam.
- [ ] A partir da instância, `curl` para a internet funciona — prova que o NAT
      está roteando *(depende da Fase 3.3; até lá, falha esperada)*.
- [ ] `HttpTokens: required`.
- [ ] Volume raiz criptografado.
- [ ] `credit_specification` não está em `unlimited` sem intenção.

---

## Fase 2.3 — Contrato, inventário e smoke tests

**Branch:** `feat/c2f3-outputs-inventario`
**Capítulos:** 03–04

### Objetivo

Fechar o contrato anti-lock-in e criar a cola entre Terraform e Ansible. Os
capítulos 03 e 04 do manual (validação e testes) viram scripts executáveis, não
procedimento manual.

### O contrato de outputs

O módulo `compute-aws` expõe exatamente estes outputs, e nada fora dele referencia
recurso AWS:

```hcl
output "public_ip"   { }   # EIP do bastion
output "ssh_user"    { }   # usuário de conexão inicial
output "ssh_port"    { }   # porta SSH efetiva
output "instance_id" { }   # id da instância no provedor
```

Como há duas instâncias, o contrato é exposto por host, mantendo os mesmos quatro
campos. O detalhe de forma (mapa por host vs. outputs separados) se resolve na
implementação; o que não muda é o conjunto de campos.

**O que este contrato compra:** trocar de provedor significa escrever um
`modules/compute-hetzner/` com os mesmos quatro outputs. O Ansible inteiro e o
módulo Cloudflare não mudam.

### Scripts

| Script | Função |
|---|---|
| `scripts/gen-inventory.sh` | Lê `terraform output -json` e gera `ansible/inventory/hosts.yml` |
| `scripts/smoke-test.sh` | Verificações do cap. 03: rede, DNS, disco, memória, saída para internet |
| `scripts/bench.sh` | Verificações do cap. 04 — **só o essencial** |

**Sobre o benchmark do capítulo 04:** o manual propõe medições de disco e rede
(`fio`, `iperf`). Num ambiente descartável que sobe e desce a cada sessão, isso
tem pouco valor e consome tempo de teste. A inclinação é implementar apenas
verificações de sanidade e deixar o benchmark completo de fora — mas a decisão
final se toma **depois de ler o capítulo**, e o que ficar de fora deve ser
registrado aqui explicitamente.

### Riscos

- O inventário é gerado, não versionado (`inventory/hosts.yml` está no
  `.gitignore`). Quem clonar o repositório precisa rodar `gen-inventory.sh` antes
  do primeiro playbook.
- Um output que exponha valor sensível vaza para o log do Terraform. Nenhum dos
  quatro campos do contrato é sensível — manter assim.

### Checklist de validação

- [ ] `terraform output -json` retorna os quatro campos do contrato.
- [ ] `gen-inventory.sh` gera um `hosts.yml` válido
      (`ansible-inventory --list` aceita).
- [ ] `ansible all -m ping` responde nos hosts alcançáveis.
- [ ] `smoke-test.sh` roda e retorna código 0.
- [ ] Nenhum recurso `aws_*` referenciado fora de `modules/compute-aws/`
      (`grep -r "aws_" terraform/ --include=*.tf | grep -v modules/compute-aws`).

---

## Ao final da camada

Duas instâncias de pé, o contrato de outputs fechado, e o Ansible com um inventário
para consumir. O host de aplicação ainda está inacessível — isso se resolve na
Fase 3.3.

**Custo a partir daqui:** ~US$ 3–11/mês enquanto o ambiente estiver de pé. Destruir
ao final da sessão.

**Próxima:** [`camada-3-host.md`](./camada-3-host.md).
