#!/usr/bin/env bash
# Gera ansible/inventory/hosts.yml a partir do output do Terraform.
#
# O inventario e um artefato derivado: nunca editar a mao, nunca versionar.
# Regerar depois de todo terraform apply que mude endereco ou porta.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
env_dir="${repo_root}/terraform/envs/${TF_ENV:-lab}"
out_file="${repo_root}/ansible/inventory/hosts.yml"
ssh_key="${SSH_KEY_PATH:-${HOME}/.ssh/id_ed25519}"

outputs="$(terraform -chdir="${env_dir}" output -json)"

get() { jq -r --arg k "$1" '.[$k].value // empty' <<<"${outputs}"; }

public_ip="$(get public_ip)"
ssh_user="$(get ssh_user)"
ssh_port="$(get ssh_port)"

if [ -z "${public_ip}" ]; then
  echo "erro: o output public_ip esta vazio — as instancias ainda nao existem." >&2
  echo "      rode terraform apply em ${env_dir#"${repo_root}"/} antes de gerar o inventario." >&2
  exit 1
fi

# Endereco privado do host de aplicacao. Alcancavel pelo tunel WireGuard, ou por
# ProxyJump atraves do bastion quando a execucao for nao interativa.
app_private_ip="${APP_PRIVATE_IP:-10.0.11.10}"

mkdir -p "$(dirname "${out_file}")"
cat > "${out_file}" <<YAML
---
# Gerado por scripts/gen-inventory.sh. Nao editar a mao.
all:
  vars:
    ansible_user: ${ssh_user}
    ansible_port: ${ssh_port}
    ansible_ssh_private_key_file: ${ssh_key}
  children:
    bastion:
      hosts:
        bastion:
          ansible_host: ${public_ip}
    app:
      hosts:
        app:
          ansible_host: ${app_private_ip}
YAML

echo "inventario escrito em ${out_file#"${repo_root}"/}"
