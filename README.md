# Infraestrutura como código — AWS EC2

Reprodução em código da infraestrutura de um manual de self-hosting, rodando em
AWS, com as nove camadas de segurança de um guia de simetria implementadas de
forma equilibrada e a um custo compatível com um projeto pessoal.

Critério de sucesso: **`terraform apply` + `ansible-playbook` sobem a infra
inteira do zero, em minutos, de forma idêntica todas as vezes.**

---

## Por onde começar

A documentação vive em [`docs/`](./docs/). Ao retomar o trabalho, abra
[`docs/PROGRESS.md`](./docs/PROGRESS.md) — ele diz qual é a fase atual e qual é
a próxima ação concreta. Na primeira leitura, siga o índice em
[`docs/README.md`](./docs/README.md).

## Estrutura

```
terraform/
├── modules/
│   ├── compute-aws/   # único lugar do repositório que referencia recursos AWS
│   └── cloudflare/    # DNS, proxy, modo de SSL, WAF
└── envs/lab/          # ambiente descartável de teste
ansible/
├── inventory/         # gerado a partir do output do Terraform, não versionado
├── group_vars/
├── roles/             # uma role por preocupação
└── playbooks/site.yml
scripts/               # geração de inventário, validação, smoke tests
docs/                  # planejamento, decisões e o documento de cada camada
```

## Ambiente de desenvolvimento

Todo o ferramental — Terraform, Ansible, ansible-lint, pre-commit, gitleaks,
tflint, AWS CLI — está fixado no devcontainer. Ver
[`.devcontainer/README.md`](./.devcontainer/README.md).

```bash
pre-commit install     # uma vez por clone
scripts/validate.sh    # a suíte de validação estática completa
```

## Nada de segredo no repositório

`*.tfvars`, estado do Terraform, senha de vault, chaves privadas e configuração
de peer WireGuard estão no `.gitignore` e são verificados pelo `gitleaks` a cada
commit. Credenciais da AWS vêm do perfil do `aws-cli`; o token da Cloudflare, da
variável de ambiente `CLOUDFLARE_API_TOKEN`.
