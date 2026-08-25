# Camada 3 — Configuração do host

O sistema operacional sai de "AMI crua" e chega a "servidor endurecido". É a
camada com mais fases e a que exige mais cuidado de ordem: várias delas podem
cortar o próprio acesso se aplicadas fora de sequência.

**Ferramenta:** Ansible (+ Terraform na 3.4). **Capítulos:** 05, 07, 08, 09, 10.

---

## Ordem obrigatória

```
3.1 base → 3.2 ssh_hardening → 3.3 nat + wireguard → 3.4 firewall → 3.5 crowdsec
                                      │
                              a partir daqui o host
                              de aplicação é alcançável
```

A ordem não é preferência. `ssh_hardening` antes de `base` derruba o acesso antes
do usuário `ops` existir. `firewall` antes de `wireguard` bloqueia o próprio túnel
que substituiria o SSH que o firewall vai fechar.

**Regra de segurança para toda esta camada:** manter uma sessão SSH aberta e ociosa
enquanto aplica qualquer fase que mexa em SSH ou firewall. Se a nova configuração
cortar o acesso, a sessão antiga ainda permite reverter. Fechá-la só depois de
abrir uma sessão nova com sucesso.

---

## Fase 3.1 — Role `base`

**Branch:** `feat/c3f1-role-base` · **Capítulo:** 05

### Objetivo

Trazer o sistema a um estado conhecido e igual em todos os hosts, antes de qualquer
hardening.

### O que a role faz

| Item | Detalhe |
|---|---|
| Atualização de pacotes | `apt update` + `upgrade` |
| Pacotes base | Definidos em `group_vars`, nunca fixos na task |
| Hostname | Padrão `[ambiente]-[função]-[local]-[número]` |
| Timezone e locale | `en_US.UTF-8` conforme o manual |
| Sincronização de tempo | `chrony` |
| Usuário `ops` | Com sudo e chave pública autorizada |

**O usuário `ops` é o pré-requisito de tudo que vem depois.** A Fase 3.2 bloqueia o
login de root e o usuário padrão da AMI; se `ops` não existir e funcionar antes
disso, o acesso se perde.

### Riscos

- Atualização de pacotes pode exigir reinício (kernel). Prever `reboot` controlado
  com espera de reconexão.
- `apt upgrade` numa instância recém-criada às vezes colide com o
  `unattended-upgrades` que já está rodando no boot. Tratar o lock do apt.

### Checklist

- [ ] `hostnamectl` mostra o hostname no padrão.
- [ ] `timedatectl` mostra o timezone correto.
- [ ] `chronyc tracking` mostra sincronizado.
- [ ] `ssh ops@host` funciona com chave.
- [ ] `sudo whoami` retorna `root` para o `ops`.
- [ ] **Segunda execução do playbook: `changed=0`.**

---

## Fase 3.2 — Role `ssh_hardening`

**Branch:** `feat/c3f2-ssh-hardening` · **Capítulo:** 07

### Objetivo

Só chave, sem senha, sem root. Corresponde à camada "Hardening do host" do guia.

### O que a role faz

Aplica o `sshd_config` do manual. Itens centrais:

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Mais os ajustes de tentativa, timeout e usuários permitidos que o capítulo definir
— **ler o capítulo antes de implementar**, não supor.

### Risco principal

Esta é a fase que mais derruba acesso. Mitigações obrigatórias:

1. Validar a sintaxe **antes** de recarregar: `sshd -t`.
2. Usar `handler` com `reload`, não `restart` — o `reload` não derruba sessões
   estabelecidas.
3. Manter a sessão de segurança aberta (regra da camada).
4. Confirmar que `ops` + chave funcionam antes de bloquear root e usuário padrão.

### Checklist

- [ ] `ssh root@host` é recusado.
- [ ] `ssh -o PubkeyAuthentication=no ops@host` é recusado (senha não passa).
- [ ] `ssh ops@host` com chave funciona.
- [ ] `sshd -t` sem erro.
- [ ] Segunda execução: `changed=0`.

---

## Fase 3.3 — Roles `nat` e `wireguard`

**Branch:** `feat/c3f3-nat-wireguard` · **Capítulo:** 08

### Objetivo

A fase que destrava o resto do projeto. Ao final dela, o host de aplicação passa a
ser alcançável e o subnet privado ganha saída para a internet.

Corresponde à camada "Acesso administrativo" do guia — com WireGuard no lugar do
Session Manager (ADR-002).

### Role `nat` (só no bastion)

| Item | Detalhe |
|---|---|
| `net.ipv4.ip_forward = 1` | Persistente via `sysctl.d`, não só em runtime |
| `MASQUERADE` | Na interface externa, para o CIDR do subnet privado |
| Persistência das regras | `iptables-persistent` ou equivalente — as regras precisam sobreviver a reboot |

**Complemento indispensável do lado da AWS:** `source_dest_check = false` na
instância, feito na Fase 2.1. Sem os dois, não há NAT.

### Role `wireguard` (só no bastion)

| Item | Detalhe |
|---|---|
| Interface `wg0` | Rede `10.8.0.0/24` |
| Chaves do servidor | Geradas na primeira execução, **nunca commitadas** |
| Peers | Definidos em `group_vars`, com a chave privada no `ansible-vault` |
| Encaminhamento | Permite que o peer alcance a VPC inteira, não só o bastion |
| Serviço | `wg-quick@wg0` habilitado no boot |

### Tradução do manual

O capítulo 08 descreve a VPN administrativa numa VPS, onde o servidor VPN é o
próprio host de aplicação. Aqui ele é o bastion, e o túnel dá acesso à **rede**,
não a uma máquina. A configuração de `AllowedIPs` do peer precisa cobrir o CIDR
da VPC, não apenas o IP do servidor WireGuard.

### Riscos

- **Chave privada do WireGuard em arquivo é o segredo mais fácil de vazar do
  projeto.** `wg*.conf` está no `.gitignore` e o `gitleaks` roda no pre-commit.
- MTU dentro do túnel: valor errado causa conexão que estabelece e trava em
  transferências grandes. Sintoma clássico e difícil de diagnosticar.
- Sobreposição de CIDR: `10.8.0.0/24` foi escolhido para não colidir com a VPC
  (`10.0.0.0/16`). Se a rede local do operador usar `10.8.x.x`, muda.

### Checklist

- [ ] `wg show` no bastion lista a interface e o peer.
- [ ] Túnel de pé na máquina do operador: `ping` no IP privado do bastion.
- [ ] Pelo túnel, `ssh ops@10.0.11.10` (host app) funciona.
- [ ] Do host app, `curl https://example.com` funciona — **prova que o NAT roteia**.
- [ ] Após `reboot` do bastion, NAT e WireGuard voltam sozinhos.
- [ ] `sysctl net.ipv4.ip_forward` retorna `1` depois do reboot.
- [ ] Segunda execução: `changed=0`.

### Ao final: fechar a janela de bootstrap

Com o túnel funcionando, esvaziar `admin_cidr` e reaplicar o Terraform. O Security
Group do bastion passa a expor apenas UDP 51820. **Validar que o SSH pelo IP
público realmente parou de responder** — é o objetivo da camada.

---

## Fase 3.4 — Role `firewall`

**Branch:** `feat/c3f4-firewall` · **Capítulo:** 09 (parte do host)

### Objetivo

Fechar o firewall do sistema operacional, espelhando o que os Security Groups já
definem. Terceira e última parede do perímetro.

### Política

Bloqueio total por padrão, com exceções para:

- `loopback`
- Conexões estabelecidas e relacionadas
- `wg0` (o túnel)
- Portas específicas por host: UDP 51820 no bastion; 80/443 no app

### O princípio de espelhamento

**O Security Group é a fonte da verdade; o firewall do host o espelha.** Uma porta
aberta no host e fechada no SG é confusão silenciosa — o serviço não responde e o
motivo não está onde se procura. Divergência entre as duas camadas é bug, não
defesa em profundidade.

Por isso esta fase toca Terraform também: qualquer ajuste necessário nos SGs é
feito junto, na mesma branch, para que as duas camadas sejam alteradas em conjunto.

### Riscos

- Fase que corta acesso. Regra da camada vale integralmente: sessão de segurança
  aberta, e as regras aplicadas com a de `ESTABLISHED,RELATED` **primeiro**.
- Regras precisam persistir após reboot.
- O Docker manipula `iptables` por conta própria (Camada 5) e pode conflitar com
  regras estáticas. **Registrar como pendência para a Fase 5.1** — o Docker será
  instalado depois e pode exigir revisão desta configuração.

### Checklist

- [ ] Política padrão de `INPUT` é `DROP`.
- [ ] Pelo túnel, o acesso continua funcionando.
- [ ] Do host app, saída para a internet continua funcionando.
- [ ] Porta não listada é recusada (testar com `nc` de dentro da VPC).
- [ ] Regras sobrevivem a `reboot`.
- [ ] Regras do host e do Security Group são coerentes entre si.
- [ ] Segunda execução: `changed=0`.

---

## Fase 3.5 — Role `crowdsec`

**Branch:** `feat/c3f5-crowdsec` · **Capítulo:** 10

### Objetivo

A camada "Detecção e resposta" do guia. Substitui o Fail2ban do manual por
CrowdSec (ADR-007).

### Tradução do manual

O capítulo 10 descreve Fail2ban. Os conceitos mapeiam, os arquivos e comandos não:

| Fail2ban (manual) | CrowdSec |
|---|---|
| `jail` | Cenário (*scenario*) |
| `filter` (regex) | Parser + cenário |
| `action` | Bouncer |
| `bantime` | Duração da decisão |
| `/etc/fail2ban/jail.local` | `/etc/crowdsec/` |
| `fail2ban-client status` | `cscli metrics`, `cscli decisions list` |

O que o CrowdSec adiciona e o Fail2ban não tem: IPs que atacaram outros
participantes da rede chegam já bloqueados, antes da primeira tentativa aqui.

### O que a role faz

| Item | Detalhe |
|---|---|
| Agente CrowdSec | Análise dos logs do sistema |
| Coleções | SSH no mínimo; Traefik *(implementação na próxima fase)* |
| Bouncer `firewall` | Aplica as decisões no `iptables`/`nftables` |
| Monitoramento mínimo do host | O que o capítulo 10 definir além do banimento |

### Riscos

- **Autobanimento.** Testar o bloqueio a partir de um IP descartável, nunca do IP
  administrativo. Ter à mão `cscli decisions delete --ip <ip>`.
- O bouncer de firewall interage com as regras da Fase 3.4 e com o Docker da
  Camada 5. Ordem de cadeia importa.
- Coleções mal escolhidas geram falso positivo em volume. Começar pelo mínimo
  (SSH) e ampliar depois de observar.

### Checklist

- [ ] `cscli metrics` mostra logs sendo processados.
- [ ] `cscli collections list` mostra a coleção de SSH ativa.
- [ ] `cscli bouncers list` mostra o bouncer registrado e ativo.
- [ ] Tentativas de login falhas a partir de um IP de teste geram decisão
      (`cscli decisions list`).
- [ ] O IP administrativo está na allowlist.
- [ ] Serviço volta sozinho após `reboot`.
- [ ] Segunda execução: `changed=0`.

---

## Ao final da camada

Sistema atualizado e padronizado, SSH só por chave, acesso administrativo
exclusivamente pela VPN, nenhuma porta de administração exposta à internet,
firewall fechado em três camadas coerentes e detecção de intrusão ativa.

Cinco das nove camadas do guia estão implementadas. O ambiente ainda não serve
nenhuma aplicação — isso começa na Camada 5.

**Próxima:** [`camada-4-dns.md`](./camada-4-dns.md).
