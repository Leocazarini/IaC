# 01 — Visão geral

## O problema

A infraestrutura existe hoje como um procedimento manual: 29 capítulos de manual,
executados à mão, na ordem certa, sem errar. Isso funciona uma vez. O problema
aparece na segunda vez — um ambiente de homologação, uma migração, um servidor
substituído depois de um incidente. Cada reexecução manual produz um resultado
ligeiramente diferente do anterior, e essas diferenças são invisíveis até o
momento em que importam.

O objetivo deste projeto é eliminar essa variação: descrever a infraestrutura
inteira como código, de modo que qualquer ambiente novo nasça idêntico aos
anteriores por definição, e não por disciplina.

**Critério de sucesso:** `terraform apply` seguido de `ansible-playbook` sobe a
infraestrutura completa a partir do zero, em minutos, com o mesmo resultado todas
as vezes.

---

## O conceito central: simetria de camadas

O guia de segurança que orienta este projeto parte de uma observação incômoda: a
maioria dos ambientes inseguros não tem uma camada fraca por falta de esforço —
tem uma camada fraca **por desequilíbrio**. É comum encontrar um WAF caro e bem
calibrado na borda, protegendo uma aplicação cujo IAM dá permissão de
administrador para tudo.

Isso importa porque o nível de segurança real de um ambiente é o nível da sua
camada mais fraca, não a média das camadas. Um invasor não precisa vencer a melhor
defesa — ele procura a camada que ficou para depois.

A consequência prática para este projeto é uma regra de priorização: **antes de
aprofundar qualquer camada, todas devem estar no mesmo patamar mínimo de
maturidade.** É por isso que o mapa de fases avança em camadas horizontais
(fundação inteira → provisionamento inteiro → configuração inteira) em vez de
verticalizar um único serviço até a perfeição.

### As nove camadas

| Camada | Função | Onde é implementada |
|---|---|---|
| Borda pública | Nada malicioso ou não criptografado chega perto da origem | Camada 6 — Cloudflare |
| Perímetro de rede | Bloqueia tudo, exceto o necessário, em duas paredes | Camada 1.2 — SG + NACL |
| Acesso administrativo | Nenhuma porta de administração exposta à internet | Camada 3.3 — WireGuard |
| Hardening do host | A máquina resiste a abusos vindos de dentro | Camadas 2 e 3.2 — IMDSv2 + SSH |
| Identidade e segredos | Cada componente tem exatamente a permissão de que precisa | Camada 1.1 — IAM |
| Criptografia em repouso | Disco e snapshot protegidos mesmo se copiados | Camada 1.3 — EBS encryption |
| Detecção e resposta | Ataque em curso é percebido, não descoberto depois | Camada 3.5 — CrowdSec |
| Observabilidade | Saber o que aconteceu antes, durante e depois | Camadas 1.3 e 7 |
| Manutenção e continuidade | Backup e patch que não dependem de alguém lembrar | Camada 8 |

Nenhuma das nove fica órfã. O mapeamento completo, fase a fase, está em
[`07-mapa-de-fases.md`](./07-mapa-de-fases.md).

---

## A tensão entre o guia e o orçamento

O guia de segurança foi escrito assumindo os serviços gerenciados nativos da AWS.
Seguido à risca, ele custa entre **US$ 85 e 110 por mês** só em camadas de
segurança, antes de contar a instância — para um projeto pessoal de tráfego
baixíssimo. Um dos serviços que ele menciona, o AWS Shield Advanced, custa
US$ 3.000 por mês.

Isso é, ironicamente, a mesma assimetria que o guia adverte: gastar
desproporcionalmente numa camada que uma VPS de US$ 6/mês com Cloudflare já
resolvia.

A resposta deste projeto não é abrir mão das camadas — é **manter as nove camadas
e trocar a implementação de cada uma pela alternativa mais barata que entrega a
mesma proteção**. Onde a AWS oferece a função de graça (IAM, VPC, Security Groups,
NACLs, IMDSv2, EBS encryption, CloudTrail, VPC Flow Logs), usa-se a AWS. Onde ela
cobra por algo que software livre resolve (WAF, detecção, gestão de segredos,
backup, observabilidade), usa-se a alternativa.

O resultado fica em torno de **US$ 4–8/mês** de custo incremental. O raciocínio
serviço por serviço, com as fontes oficiais de preço, está em
[`04-custos.md`](./04-custos.md).

---

## Escopo

### Dentro

- Toda a fundação AWS: identidade, rede, criptografia e auditoria.
- Provisionamento das instâncias EC2 e do que as cerca.
- Configuração e hardening completo do sistema operacional.
- DNS, proxy reverso, TLS e WAF na borda.
- Plataforma de aplicação: Docker, redes, volumes, Traefik.
- Observabilidade: métricas, logs centralizados, uptime e alertas.
- Backup com teste de restauração e patching automatizado.
- Os 29 capítulos do manual, todos alocados a alguma fase.

### Fora

- **Alta disponibilidade e múltiplas zonas.** Uma instância de aplicação, uma AZ.
  Adicionar HA multiplicaria o custo e não é o objetivo de um projeto pessoal.
- **Backend remoto de estado do Terraform.** O estado fica local por enquanto
  (ver ADR-005 em [`03-decisoes.md`](./03-decisoes.md)).
- **Pipeline de CI/CD.** As fases são aplicadas a partir da máquina do operador.
- **Ambiente de produção separado.** Existe apenas o ambiente `lab`, descartável.
  Um `prod` é uma extensão trivial depois que o `lab` estiver estável.
- **Os serviços pagos da AWS descartados por custo** — listados em
  [`04-custos.md`](./04-custos.md) com suas alternativas.

---

## Princípios de execução

Três regras que valem para todas as fases e não se re-discutem:

1. **Uma fase por vez, com aprovação entre elas.** Nada é implementado "para usar
   depois". Cada fase entrega o mínimo que funciona e é validada antes da seguinte
   começar.

2. **Nada é dado como pronto sem teste em servidor virgem.** A promessa do projeto
   é "deploy igual em minutos"; isso só é verdade se cada fase foi aplicada e
   validada numa instância criada do zero. O checklist de validação de cada fase
   está no documento da sua camada.

3. **Mínimo lock-in.** Toda lógica específica de provedor fica isolada num único
   módulo, atrás de um contrato fixo de outputs. Trocar a AWS por outro provedor
   deve significar escrever um módulo novo — não reescrever o projeto. O contrato
   está em [`02-arquitetura.md`](./02-arquitetura.md).
