# Camada 4 — DNS

Camada curta e deliberadamente incompleta: o DNS entra agora, mas o proxy da
Cloudflare **não**. Ele é ativado só na Camada 6, depois que a origem responde.

**Ferramenta:** Terraform (provider Cloudflare). **Capítulo:** 06.

> **Pendência P2** em [`../PROGRESS.md`](../PROGRESS.md): domínio e zona Cloudflare
> ainda não definidos. Resolver antes de iniciar.

---

## Fase 4.1 — DNS Cloudflare em modo DNS-only

**Branch:** `feat/c4f1-dns-cloudflare` · **Capítulo:** 06

### Objetivo

Fazer o domínio resolver para o endereço do ambiente, sem proxy, para que as fases
seguintes possam validar a origem diretamente.

### Por que DNS-only agora e proxy depois

Se o proxy for ativado antes de haver aplicação respondendo na origem, todo erro
de configuração aparece como uma página de erro genérica da Cloudflare (521, 522,
525). O diagnóstico fica muito mais difícil, porque não dá para distinguir "a
origem está fora" de "o TLS entre Cloudflare e origem está errado" de "o firewall
bloqueou".

Em modo DNS-only, a requisição vai direto à origem e o erro é o erro real.

A sequência completa é: **DNS-only (4.1) → Traefik respondendo (5.2) → proxy +
SSL Full Strict (6.1) → WAF (6.2)**.

### O que vira Terraform

| Recurso | Detalhe |
|---|---|
| `cloudflare_record` (A, apex) | Aponta para o EIP do bastion, `proxied = false` |
| `cloudflare_record` (A/CNAME, subdomínios) | Conforme o capítulo definir, `proxied = false` |
| Provider `cloudflare` | Token de API via variável, **nunca no código** |

O valor do registro vem do output `public_ip` do módulo de compute — o módulo
Cloudflare não conhece nada da AWS. É o contrato anti-lock-in em uso.

### Sobre o token da Cloudflare

Token de API com escopo mínimo: permissão de edição de DNS **apenas na zona deste
domínio**. Não usar a Global API Key, que dá acesso a tudo na conta.

O token vai em `terraform.tfvars` (gitignored) ou em variável de ambiente
`CLOUDFLARE_API_TOKEN`. Nunca no código, nunca em output.

### Riscos

- **TTL alto atrapalha as fases seguintes.** Manter TTL baixo (60–300 s) enquanto
  o ambiente é descartável; a Camada 6 vai trocar `proxied` para `true` e mudanças
  precisam propagar rápido.
- Registro apontando para um EIP que foi destruído e recriado passa a apontar para
  o vazio — ou, pior, para o endereço de outra pessoa. Como o ambiente é
  descartável, reaplicar o Terraform após cada `apply` novo é parte do fluxo.
- Zona errada no provider aplica mudanças no domínio errado. Conferir o `zone_id`.

### Checklist

- [ ] `dig +short dominio.tld` retorna o EIP do bastion.
- [ ] `dig` não mostra IPs da Cloudflare — confirma que o proxy está desligado.
- [ ] Painel da Cloudflare mostra a nuvem **cinza** (DNS-only), não laranja.
- [ ] O token usado não é a Global API Key.
- [ ] Token não aparece em nenhum arquivo versionado
      (`git grep -i cloudflare_api_token` vazio).
- [ ] TTL baixo nos registros.

---

## Ao final da camada

O domínio resolve para o ambiente. Nada responde ainda em 80/443 — não há
aplicação. Isso é esperado e se resolve na Camada 5.

**Próxima:** [`camada-5-plataforma.md`](./camada-5-plataforma.md).
