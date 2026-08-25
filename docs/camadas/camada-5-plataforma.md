# Camada 5 — Plataforma de aplicação

Docker, estrutura de diretórios e proxy reverso. A partir daqui o ambiente deixa de
ser "um servidor endurecido" e passa a ser "um lugar onde aplicações rodam".

**Ferramenta:** Ansible. **Capítulos:** 14–20.

Esta camada roda **apenas no host de aplicação**. O bastion não recebe Docker nem
Traefik — ADR-006 é explícita: ampliar o papel do bastion desfaz a segmentação de
rede que justifica sua existência.

---

## Fase 5.1 — Role `docker` e estrutura de diretórios

**Branch:** `feat/c5f1-docker` · **Capítulos:** 14–19

Seis capítulos numa fase só. Eles formam uma unidade: estrutura de diretórios,
instalação do Docker, redes, volumes, gestão de containers e o procedimento de
atualização/rollback. Separá-los produziria fases que não entregam nada testável
sozinhas.

### O que a role faz

| Item | Capítulo | Detalhe |
|---|---|---|
| Estrutura `/srv` | 14 | `apps/`, `data/`, `logs/` com dono e permissão definidos |
| Docker Engine + Compose plugin | 15 | Repositório oficial, não o `docker.io` do Ubuntu |
| Redes Docker | 16 | Rede de borda (Traefik) e redes internas por aplicação |
| Volumes | 17 | Nomeados, sob `/srv/data`, nunca `bind mount` improvisado |
| Saúde e reinício | 18 | `restart: unless-stopped` e `healthcheck` como padrão |
| Atualização e rollback | 19 | Procedimento com tag fixa de imagem, não `latest` |

### O ponto de atenção: Docker e o firewall

**Este é o conflito mais importante desta camada**, registrado como pendência na
Fase 3.4.

O Docker manipula `iptables` por conta própria. Ao publicar uma porta com
`-p 0.0.0.0:8080:8080`, ele insere regras na cadeia `DOCKER` que são avaliadas
**antes** das regras da cadeia `INPUT` — ou seja, ele contorna o firewall
configurado na Fase 3.4 sem avisar.

O resultado prático é uma porta que o operador acredita estar fechada, e que está
aberta para a internet.

Mitigações, a decidir na implementação:

1. Publicar portas apenas em `127.0.0.1` (`-p 127.0.0.1:8080:8080`), deixando o
   Traefik como único componente que escuta em endereço externo.
2. Usar `DOCKER_OPTS="--iptables=false"` e gerenciar as regras manualmente — mais
   controle, mais trabalho e mais chance de quebrar a rede dos containers.
3. Regras na cadeia `DOCKER-USER`, que é avaliada antes das regras do Docker e
   sobrevive aos seus reinícios.

A inclinação é combinar (1) e (3): publicar só em loopback e proteger a cadeia
`DOCKER-USER`. **Validar o resultado com varredura de porta de fora**, não por
inspeção de configuração.

### Riscos

- Conflito Docker × firewall descrito acima. Se não for tratado, a Fase 3.4 vira
  ficção.
- `t3.micro` tem 1 GB de RAM. Docker sozinho cabe; com a stack da Camada 7 pode não
  caber. Registrar o consumo real ao final desta fase para embasar a decisão da
  Camada 7.
- Imagens `latest` quebram o rollback do capítulo 19. Tag fixa é requisito, não
  preferência.
- Sem `logrotate` ou driver de log com limite, os logs de container enchem o disco.
  Configurar `max-size` e `max-file` no `daemon.json`.

### Checklist

- [ ] `docker --version` e `docker compose version` respondem.
- [ ] `/srv/apps`, `/srv/data`, `/srv/logs` existem com dono e permissão corretos.
- [ ] Container de teste sobe, responde e reinicia sozinho após `docker kill`.
- [ ] Container sobe automaticamente após `reboot` do host.
- [ ] **`nmap` a partir de fora não mostra nenhuma porta de container exposta.**
- [ ] `daemon.json` limita tamanho e rotação de log.
- [ ] Segunda execução: `changed=0`.

---

## Fase 5.2 — Role `traefik`

**Branch:** `feat/c5f2-traefik` · **Capítulo:** 20

### Objetivo

Proxy reverso na frente das aplicações. **É o pré-requisito da Camada 6:** o modo
SSL Full (Strict) da Cloudflare exige um certificado válido respondendo na origem,
e quem responde é o Traefik.

### O que a role faz

| Item | Detalhe |
|---|---|
| Traefik v3 | Compose em `/srv/apps/traefik` |
| Provider Docker | Descoberta de serviço por label, sem configuração estática por app |
| Entrypoints | 80 e 443 |
| Redirecionamento | HTTP → HTTPS |
| Certificado | **Certificado de origem da Cloudflare** *(implementação na Fase 6.1)* |
| Dashboard | Acessível apenas pela rede WireGuard, nunca publicamente |

### Certificado: por que não Let's Encrypt

O manual usa Let's Encrypt com desafio ACME. Neste projeto, a Camada 6 usa
**certificado de origem da Cloudflare**, que é mais adequado ao arranjo:

- Validade de até 15 anos, sem renovação automática para manter funcionando.
- Emitido para uso exclusivo entre Cloudflare e origem — não é confiável para um
  navegador que acesse a origem diretamente, o que é exatamente o comportamento
  desejado quando todo o tráfego legítimo passa pelo proxy.
- Não depende do desafio ACME, que exigiria expor a porta 80 ao mundo.

Nesta fase o Traefik pode subir com certificado autoassinado provisório; o
certificado de origem entra na Fase 6.1.

### Riscos

- Dashboard do Traefik exposto publicamente entrega o mapa inteiro da
  infraestrutura. Restringir à rede WireGuard e conferir.
- O Traefik precisa acessar o socket do Docker. Montar como **somente leitura** —
  acesso de escrita ao socket equivale a root no host.
- Sem o certificado de origem, a Fase 6.1 não pode ativar Full (Strict). A ordem
  importa.

### Checklist

- [ ] `curl -I http://IP` responde e redireciona para HTTPS.
- [ ] `curl -kI https://IP` responde com certificado (autoassinado nesta fase).
- [ ] Um container de teste com label do Traefik é roteado corretamente.
- [ ] Dashboard **não** responde pela internet; responde pelo túnel.
- [ ] Socket do Docker montado como `:ro`.
- [ ] Traefik volta sozinho após `reboot`.
- [ ] Segunda execução: `changed=0`.

---

## Ao final da camada

Há uma plataforma capaz de rodar aplicações em containers, com proxy reverso
roteando por domínio. A origem responde — o que destrava a ativação do proxy e do
SSL Full (Strict).

**Próxima:** [`camada-6-borda-publica.md`](./camada-6-borda-publica.md).
