# Camada 7 — Observabilidade

Saber o que está acontecendo antes, durante e depois de qualquer incidente. A
parte AWS desta camada (CloudTrail e VPC Flow Logs) já foi entregue na Fase 1.3;
aqui entra a observabilidade do host e das aplicações.

**Ferramenta:** Ansible. **Capítulos:** 21–27.

---

## Risco que atravessa a camada inteira

**`t3.micro` tem 1 GB de RAM.** Prometheus, Grafana, Loki, Promtail, Uptime Kuma,
cAdvisor e node-exporter, somados ao Traefik e às aplicações, não cabem com folga.

Esta é a decisão pendente mais importante do projeto, e ela **pertence a esta
camada** — deve ser tomada com o dado real de consumo medido ao final da Fase 5.1,
não antecipada.

Os três caminhos:

| Caminho | Custo | Consequência |
|---|---|---|
| Subir para `t3.small` (2 GB) | +~US$ 7,50/mês, e perde o free tier | Mais simples, resolve de vez |
| Enxugar a stack | US$ 0 | Ex.: Loki com retenção curta, sem Prometheus (usar métricas do próprio Grafana Agent) |
| Observabilidade fora do host | US$ 0 no free tier de terceiros | Grafana Cloud free tier recebe métricas e logs; o host só roda os agentes |

A terceira opção merece atenção: ela resolve o problema de memória **e** o problema
mais fundamental de manter a observabilidade num host que pode ser justamente o
que caiu. Um painel que só existe dentro da máquina que morreu não serve para
diagnosticar por que ela morreu.

**Decidir na Fase 7.1, com dados, e registrar aqui.**

---

## Fase 7.1 — Métricas de host e containers

**Branch:** `feat/c7f1-metricas` · **Capítulos:** 21–24

Quatro capítulos numa fase: observabilidade geral (21), administração e
monitoramento do host (22), dos containers (23) e métricas de sistema (24). Eles
descrevem a mesma preocupação em níveis diferentes.

### O que a role faz

| Item | Capítulo | Detalhe |
|---|---|---|
| Coletor de métricas do host | 22, 24 | CPU, memória, disco, rede, carga |
| Métricas de containers | 23 | Por container: CPU, memória, reinícios |
| Armazenamento de séries temporais | 21 | Local ou remoto — decisão acima |
| Grafana | 21 | Dashboards; acessível **apenas pela rede WireGuard** |

O manual usa Netdata e Grafana. Ler os capítulos antes de decidir o conjunto exato
— não presumir.

### Riscos

- Consumo de memória (ver acima).
- Retenção de métricas enche o disco. Definir política desde o início.
- **Grafana exposto publicamente é vazamento de mapa da infraestrutura.** Restringir
  ao túnel e conferir com varredura externa.
- Senha padrão do Grafana (`admin/admin`) é o erro mais comum. Trocar na
  provisionamento, via `ansible-vault`.

### Checklist

- [ ] Grafana responde pelo túnel e **não** pela internet.
- [ ] Senha padrão trocada.
- [ ] Dashboard mostra métricas reais do host.
- [ ] Métricas por container aparecem.
- [ ] Retenção configurada; disco não cresce indefinidamente.
- [ ] **Consumo de memória medido e registrado neste documento.**
- [ ] Serviços voltam após `reboot`.
- [ ] Segunda execução: `changed=0`.

---

## Fase 7.2 — Logs centralizados

**Branch:** `feat/c7f2-logs` · **Capítulo:** 25

### Objetivo

Loki + Promtail + Grafana: logs de sistema e de containers consultáveis num lugar
só, correlacionáveis com as métricas da fase anterior.

### O que a role faz

| Item | Detalhe |
|---|---|
| Loki | Armazenamento de logs, retenção definida |
| Promtail | Coleta de `/var/log` e dos logs de container |
| Datasource no Grafana | Loki ligado ao Grafana da Fase 7.1 |

### O que vale coletar

Além dos logs de aplicação, os que importam para segurança:

- `sshd` — tentativas de acesso
- CrowdSec — decisões tomadas
- Traefik — requisições, com o IP real do cliente (`CF-Connecting-IP`)
- `sudo` — escalação de privilégio

### Riscos

- **Loki sem limite de retenção enche o disco.** É a causa mais comum de disco
  cheio nesse tipo de stack. Definir retenção curta (7–14 dias) num ambiente
  pequeno.
- Logs podem conter dado sensível (token em URL, header de autenticação).
  Configurar o Promtail para descartar ou mascarar esses campos.
- Sem os labels certos, o log vira um monte indistinguível. Definir labels por
  host, serviço e nível.

### Checklist

- [ ] Grafana consulta o Loki e retorna logs.
- [ ] Logs de sistema e de container aparecem, separados por label.
- [ ] Log do Traefik mostra o IP real do cliente.
- [ ] Retenção configurada e verificada.
- [ ] Uso de disco do Loki monitorado por um painel.
- [ ] Segunda execução: `changed=0`.

---

## Fase 7.3 — Uptime e alertas

**Branch:** `feat/c7f3-alertas` · **Capítulos:** 26–27

### Objetivo

Fechar o ciclo: não basta registrar, é preciso **avisar**. O guia é direto quanto a
isso — findings que ficam acumulando num painel que ninguém abre não são detecção.

### O que a role faz

| Item | Capítulo | Detalhe |
|---|---|---|
| Uptime Kuma | 26 | Monitores HTTP e TCP dos serviços publicados |
| Canais de notificação | 27 | E-mail, Telegram, ou o que o capítulo definir |
| Alertas do Grafana | 27 | Sobre métricas: disco, memória, carga |

### Alertas mínimos

O que precisa avisar, independentemente do que o capítulo detalhar:

| Alerta | Por quê |
|---|---|
| Serviço fora do ar | O básico |
| Disco acima de 80% | Loki/logs enchendo antes de quebrar tudo |
| Memória acima de 90% | O risco conhecido do `t3.micro` |
| Certificado perto do vencimento | Mesmo o de origem, de 15 anos, um dia vence |
| Decisão do CrowdSec em volume anômalo | Ataque em curso |
| **Gasto na AWS acima do orçamento** | Já configurado na Fase 1.1; validar que chega |

### O problema do monitor que mora dentro do que monitora

Uptime Kuma rodando no mesmo host das aplicações **não avisa quando o host cai** —
ele cai junto. Duas saídas:

1. Um monitor externo gratuito (UptimeRobot, Better Stack) fazendo o papel de
   "quem vigia o vigia".
2. Notificação por *heartbeat*: o Uptime Kuma envia um ping periódico a um serviço
   externo, que alerta quando o ping para de chegar.

**A segunda é mais elegante e não custa nada.** Decidir e registrar na fase.

### Riscos

- Excesso de alerta gera fadiga e o alerta real passa despercebido. Começar com o
  mínimo da tabela acima e ampliar sob demanda.
- Canal de notificação não testado é canal que não funciona. Testar cada um
  disparando um alerta de verdade.
- Token do canal de notificação é segredo. `ansible-vault`.

### Checklist

- [ ] Uptime Kuma monitora os serviços publicados.
- [ ] Derrubar um serviço de teste dispara notificação **recebida de fato**.
- [ ] Cada alerta da tabela mínima existe e foi testado.
- [ ] Monitoramento externo ou heartbeat configurado e validado.
- [ ] Alerta de billing da Fase 1.1 chega ao canal certo.
- [ ] Tokens em `ansible-vault`.
- [ ] Segunda execução: `changed=0`.

---

## Ao final da camada

Métricas, logs e disponibilidade observáveis num lugar só, com alertas que chegam a
uma pessoa. A camada "Observabilidade" do guia está completa — do registro de API
na conta AWS (CloudTrail, Fase 1.3) até o alerta no celular.

**Próxima:** [`camada-8-continuidade.md`](./camada-8-continuidade.md).
