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

  # Um modulo que declara configuration_aliases nao valida isolado: o provider
  # com alias so existe no root que o consome, e o validate acusa "Provider
  # configuration not present". Nesses casos o init acima ja pega erro de
  # sintaxe, e a validacao real acontece pelo envs/lab, que passa o alias.
  if grep -rqs 'configuration_aliases' "${dir}"/*.tf; then
    echo "    pulado: declara configuration_aliases, validado via terraform/envs/lab"
    continue
  fi

  terraform -chdir="${dir}" validate -no-color || status=1
done

exit "${status}"
