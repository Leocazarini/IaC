#!/usr/bin/env bash
# Roda terraform validate em cada diretorio de configuracao do repositorio.
#
# O init usa -backend=false: valida sintaxe e referencias sem tocar no estado
# nem exigir credencial de provedor.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
dirs=(
  "${repo_root}/terraform/modules/compute-aws"
  "${repo_root}/terraform/modules/cloudflare"
  "${repo_root}/terraform/envs/lab"
)

status=0
for dir in "${dirs[@]}"; do
  [ -d "${dir}" ] || continue
  echo "==> ${dir#"${repo_root}"/}"
  terraform -chdir="${dir}" init -backend=false -input=false -no-color >/dev/null
  terraform -chdir="${dir}" validate -no-color || status=1
done

exit "${status}"
