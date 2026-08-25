# Camada 8 — Continuidade

A última camada do guia: backup e atualização que não dependem de alguém lembrar.
Fecha também o projeto, com a documentação gerada a partir da própria infra.

**Ferramenta:** Ansible. **Capítulos:** 28–29.

> **Pendência P4** em [`../PROGRESS.md`](../PROGRESS.md): conta Backblaze B2 ainda
> não criada. Resolver antes da Fase 8.1.

---

## Fase 8.1 — Backup e patching

**Branch:** `feat/c8f1-backup-patch`

Esta fase não corresponde a um capítulo do manual — o manual trata backup como
procedimento manual pelo painel do provedor. Aqui ela é construída a partir da
camada "Manutenção e continuidade" do guia de segurança.

### Objetivo

Backup automatizado **com restauração testada**, e patches de segurança em janela
definida.

### A distinção que define esta fase

O guia é direto: existe diferença entre *ter backup configurado* e *ter backup*.
Um snapshot agendado que nunca foi restaurado é uma hipótese, não uma garantia — e
o momento de descobrir que ele não funciona não pode ser o momento em que ele é
necessário.

**Esta fase não se considera concluída sem uma restauração real executada e
validada.** Não uma verificação de integridade — uma restauração de fato, com os
dados voltando para um lugar e sendo conferidos.

### O que a role faz

| Item | Detalhe |
|---|---|
| `restic` | Backup incremental, deduplicado e **cifrado no cliente** |
| Destino: Backblaze B2 | ~US$ 6/TB/mês; para poucos GB, centavos |
| Agendamento | Timer do systemd, não cron |
| Política de retenção | `forget --prune` com política de gerações |
| Escopo | `/srv/data`, volumes Docker, configurações em `/srv/apps` |
| Verificação | `restic check` periódico |
| `unattended-upgrades` | Patches de segurança automáticos, janela definida |
| Reinício automático | Apenas se o capítulo/política permitir; senão, alerta |

### Por que restic + B2, e não AWS Backup

ADR-003. AWS Backup cobra por GB armazenado e restaurado, sem franquia gratuita.
O `restic` cifra no cliente — o provedor de armazenamento nunca vê o conteúdo — e
o Backblaze B2 custa uma fração do S3.

Efeito colateral valioso: o backup fica **fora da AWS**. Um backup que mora na
mesma conta que a infraestrutura não protege contra o cenário de a conta ser
comprometida ou suspensa.

### Riscos

- **A senha do repositório restic é o ponto de falha absoluto.** Perdê-la torna
  todos os backups irrecuperáveis, sem exceção e sem recurso. Guardar fora do
  repositório e fora do servidor — gerenciador de senhas do operador, com cópia
  física se for o caso.
- Backup rodando durante escrita de banco de dados gera cópia inconsistente. Para
  bancos, dump antes ou snapshot consistente.
- `unattended-upgrades` pode reiniciar serviço em horário ruim. Definir a janela.
- Backup que nunca foi restaurado não é backup — daí o checklist abaixo.

### Checklist

- [ ] `restic snapshots` lista snapshots recentes.
- [ ] Timer do systemd ativo (`systemctl list-timers`).
- [ ] **Restauração real executada:** restaurar em diretório temporário e conferir
      o conteúdo contra o original.
- [ ] Política de retenção aplicada — snapshots antigos são removidos.
- [ ] `restic check` sem erro.
- [ ] Senha do repositório guardada fora do servidor e fora do repositório.
- [ ] `unattended-upgrades` ativo e instalando apenas segurança.
- [ ] Falha de backup gera alerta (integração com a Fase 7.3).
- [ ] Segunda execução: `changed=0`.

---

## Fase 8.2 — Homepage e documentação gerada

**Branch:** `feat/c8f2-homepage-docs` · **Capítulos:** 28–29

### Objetivo

Um ponto de entrada para os serviços do ambiente, e documentação que reflete a
infra que existe de fato — não a que existia quando alguém escreveu o documento.

### O que a role faz

| Item | Capítulo | Detalhe |
|---|---|---|
| Homepage / dashboard | 29 | Painel com links para os serviços, atrás do túnel |
| Documentação gerada | 28 | Inventário da infra a partir do estado real |

### Documentação gerada, não escrita

O valor desta fase está em a documentação ser **derivada do estado real** em vez de
mantida à mão. Fontes possíveis:

- `terraform output` e `terraform show -json` — recursos, IPs, IDs
- `terraform-docs` — variáveis e outputs dos módulos
- `docker compose ps` — o que está rodando
- `ansible-inventory --graph` — hosts e grupos

Documentação escrita à mão diverge da realidade em semanas. Documentação gerada
diverge no momento em que alguém esquece de rodá-la — o que é um problema menor e
detectável.

**Onde ela não substitui nada:** os documentos de `docs/` continuam sendo escritos
à mão, porque registram *intenção* e *porquê*, que nenhum estado de infra contém.
A documentação gerada registra *o quê*.

### Riscos

- Documentação gerada que exponha IP, ID de recurso ou nome de bucket não deve ser
  publicada fora do ambiente protegido.
- Homepage exposta publicamente entrega o mapa dos serviços. Atrás do túnel.
- Geração não automatizada não acontece. Prever no fluxo de fase, ou como hook.

### Checklist

- [ ] Homepage responde pelo túnel e **não** pela internet.
- [ ] Links da homepage funcionam.
- [ ] Documentação gerada reflete o estado real do ambiente.
- [ ] Regeneração é um comando único e documentado.
- [ ] Nenhum segredo na documentação gerada.
- [ ] Segunda execução: `changed=0`.

---

## Ao final da camada — e do projeto

As nove camadas do guia estão implementadas, cada uma no mesmo patamar de
maturidade — que era o objetivo desde o início.

### Validação final do projeto

O teste que prova a promessa central. Numa conta limpa ou após `terraform destroy`
completo:

```bash
terraform apply                          # fundação + instâncias
./scripts/gen-inventory.sh
ansible-playbook playbooks/site.yml      # tudo, do zero
```

- [ ] O ambiente sobe inteiro, sem intervenção manual além da janela de bootstrap.
- [ ] O tempo total é medido e registrado.
- [ ] O site responde por HTTPS, com o certificado correto.
- [ ] Nenhuma porta de administração responde pela internet.
- [ ] O acesso administrativo funciona apenas pela VPN.
- [ ] Alertas chegam.
- [ ] Backup roda e restaura.
- [ ] **Segunda execução completa do playbook: `changed=0`.**

### Scorecard de simetria

Com o ambiente de pé, preencher o scorecard da seção 4 do guia (0 = inexistente,
3 = maduro/automatizado/testado). O objetivo não é maximizar cada nota — é
**reduzir a diferença entre a maior e a menor**.

| Camada | Nota |
|---|---|
| Borda pública (Cloudflare) | |
| Perímetro de rede (SG/NACL/firewall) | |
| Acesso administrativo (WireGuard) | |
| Hardening do host (IMDSv2, SSH) | |
| Identidade e segredos (IAM, vault) | |
| Criptografia em repouso (EBS) | |
| Detecção e resposta (CrowdSec) | |
| Observabilidade (CloudTrail, Grafana, Loki) | |
| Manutenção e continuidade (restic, patches) | |

Qualquer camada em 0 ou 1 enquanto outras estão em 3 é a próxima a atacar —
independentemente de qual pareça mais importante em abstrato.

### O que fica em aberto

Candidatos naturais a uma continuação, nenhum deles no escopo atual:

- **AMI dourada com Packer**, construída a partir do próprio Ansible: reduz o
  tempo de bootstrap sem abrir mão da rastreabilidade (ADR-008).
- **Ambiente `prod` separado**, agora que o `lab` é reproduzível.
- **Backend remoto de estado**, se o projeto ganhar um segundo operador (ADR-005).
- **CI aplicando as fases**, usando o `ProxyJump` já previsto em
  [`../02-arquitetura.md`](../02-arquitetura.md).
