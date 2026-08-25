# Camada 6 — Borda pública

A camada que fica entre a internet e tudo o mais. Corresponde à camada "Borda /
entrada pública" do guia — implementada com Cloudflare no plano gratuito em vez de
CloudFront/ALB + AWS WAF + ACM (ADR-004).

**Ferramenta:** Terraform (+ Ansible para o certificado). **Capítulos:** 11–13.

---

## Por que esta camada vem depois do Traefik

O modo SSL **Full (Strict)** exige um certificado válido respondendo na origem. Sem
o Traefik da Fase 5.2 de pé, ativar Full (Strict) produz erro 526 e o site fica
fora do ar.

O manual faz a Cloudflare antes do Traefik porque era um procedimento manual, sem
essa restrição de automação. **Esta inversão é deliberada** e está registrada em
[`../07-mapa-de-fases.md`](../07-mapa-de-fases.md).

---

## Fase 6.1 — Proxy e SSL Full (Strict)

**Branch:** `feat/c6f1-proxy-ssl` · **Capítulos:** 11–12

### Objetivo

Esconder o endereço de origem atrás do proxy e cifrar as duas pernas da conexão —
navegador→Cloudflare e Cloudflare→origem — com validação de certificado nas duas.

### Os modos de SSL da Cloudflare

Entender a diferença é o ponto central do capítulo 12:

| Modo | Navegador→CF | CF→Origem | Validação do cert de origem |
|---|---|---|---|
| Off | ❌ | ❌ | — |
| Flexible | ✅ | ❌ **texto claro** | — |
| Full | ✅ | ✅ | ❌ **aceita autoassinado e expirado** |
| **Full (Strict)** | ✅ | ✅ | ✅ |

**Flexible é ativamente perigoso:** o cadeado aparece para o usuário enquanto o
tráfego entre Cloudflare e origem trafega sem cifra. É a configuração que mais
gera falsa sensação de segurança.

**Full sem Strict** aceita qualquer certificado na origem, inclusive um forjado —
o que abre espaço para interceptação entre a Cloudflare e o servidor.

Só Full (Strict) fecha o circuito. É o alvo desta fase.

### O que é feito

| Item | Onde | Detalhe |
|---|---|---|
| Certificado de origem | Cloudflare → Ansible | Gerado no painel/API, instalado no Traefik |
| `proxied = true` nos registros | Terraform | A nuvem passa de cinza para laranja |
| Modo SSL `full_strict` | Terraform | `cloudflare_zone_settings_override` |
| Always Use HTTPS | Terraform | Redireciona qualquer HTTP na borda |
| Min TLS version | Terraform | 1.2 no mínimo |
| SG do app restrito à Cloudflare | Terraform | 80/443 apenas dos ranges publicados |

### O passo que fecha a camada

Restringir o Security Group do host de aplicação para aceitar 80/443 **apenas dos
ranges de IP da Cloudflare** é o que transforma o proxy de "recomendação" em
"caminho único". Sem isso, qualquer um que descubra o endereço de origem acessa a
aplicação direto, contornando WAF, rate limiting e TLS da borda.

Os ranges vêm de `data "http"` sobre `https://www.cloudflare.com/ips-v4` —
dinâmicos, nunca fixos no código, porque mudam.

### Riscos

- **Ordem de ativação.** Ativar `proxied = true` antes de o certificado de origem
  estar instalado gera erro 526. Instalar o certificado primeiro, validar por
  `curl` direto na origem, só então ativar o proxy.
- **Restringir o SG antes de o proxy estar ativo derruba o próprio acesso de
  teste.** A ordem é: certificado → proxy → validar → restringir SG.
- O certificado de origem não é confiável para navegadores. Acessar a origem
  diretamente vai mostrar erro de certificado — isso é o comportamento correto,
  não um defeito.
- A chave privada do certificado de origem é um segredo. `ansible-vault`,
  gitignored, verificado pelo `gitleaks`.
- Com o proxy ativo, o IP do cliente chega no header `CF-Connecting-IP`. Traefik e
  CrowdSec precisam ser configurados para lê-lo, senão todo tráfego parece vir da
  Cloudflare e o banimento por IP fica inútil (ou bane a Cloudflare inteira).

### Checklist

- [ ] `curl -I https://dominio.tld` responde 200 com certificado válido.
- [ ] Header `cf-ray` presente na resposta — confirma que passou pelo proxy.
- [ ] `dig +short dominio.tld` retorna IPs da Cloudflare, **não** o EIP.
- [ ] SSL Labs (ou `testssl.sh`) sem alerta grave; TLS mínimo 1.2.
- [ ] `curl` direto no EIP em 443 **falha** — o SG bloqueia.
- [ ] `http://dominio.tld` redireciona para HTTPS.
- [ ] Log do Traefik mostra o IP real do cliente, não o da Cloudflare.
- [ ] Painel da Cloudflare mostra a nuvem **laranja** e modo Full (Strict).

---

## Fase 6.2 — WAF Cloudflare

**Branch:** `feat/c6f2-waf` · **Capítulo:** 13

### Objetivo

Bloquear ataques de aplicação (SQLi, XSS, varredura de caminho) e abusos de volume
antes que cheguem à origem.

### A regra de ouro: `count` antes de `block`

Toda regra nova entra em modo **`count`** (registra e deixa passar), fica assim por
alguns dias, e só vira **`block`** depois que os dados mostram que ela não está
pegando tráfego legítimo.

O guia é explícito quanto a isso, e o motivo é prático: uma regra de WAF mal
calibrada em modo block derruba usuários reais de forma difícil de diagnosticar —
o erro aparece na borda, não no log da aplicação.

Um WAF em modo `count` para sempre, no entanto, é decoração. A fase só se considera
concluída quando as regras estiverem em `block` e validadas.

### O que vira Terraform

| Item | Detalhe |
|---|---|
| `cloudflare_ruleset` (managed) | Regras gerenciadas da Cloudflare |
| `cloudflare_ruleset` (custom) | Regras próprias — o plano free permite 5 |
| Rate limiting | Por IP, no limite do plano free |
| Bloqueio geográfico | Se aplicável ao caso de uso |

### Limites do plano free

- 5 regras de WAF customizadas.
- Rate limiting básico.
- Sem retenção de log de requisição (dificulta a calibração pós-fato — daí a
  importância do período em `count`).

Se essas restrições apertarem, a alternativa é o CrowdSec com bouncer de
Cloudflare, que empurra decisões do host para a borda via API — mantendo o custo
zero. Fica registrado como caminho, não como escopo desta fase.

### Riscos

- Regra em `block` cedo demais derruba tráfego legítimo.
- Sem log de requisição no plano free, a calibração depende do período em `count`
  e do painel de segurança.
- Regra de bloqueio geográfico pode barrar o próprio operador em viagem.

### Checklist

- [ ] Requisição com padrão de SQLi óbvio é bloqueada (testar com payload inócuo).
- [ ] Tráfego legítimo do dia a dia não é bloqueado.
- [ ] Rate limiting dispara sob rajada e libera depois.
- [ ] **Nenhuma regra permanece em `count` ao final da fase.**
- [ ] Painel de segurança mostra eventos sendo registrados.

---

## Ao final da camada

O endereço de origem está escondido, o tráfego é cifrado e validado nas duas
pernas, a origem só aceita conexão vinda da Cloudflare, e ataques de aplicação são
filtrados antes de chegar.

Sete das nove camadas do guia estão implementadas. Faltam observabilidade completa
e continuidade.

**Próxima:** [`camada-7-observabilidade.md`](./camada-7-observabilidade.md).
