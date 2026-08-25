#!/usr/bin/env bash
# Suite de validacao estatica obrigatoria antes de qualquer PR.
# Os mesmos quatro passos que o pre-commit roda, em um comando so.
set -uo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

status=0
run() {
  local label="$1"; shift
  echo
  echo "── ${label}"
  if "$@"; then
    echo "   ok"
  else
    echo "   FALHOU"
    status=1
  fi
}

run "terraform fmt"   terraform fmt -check -recursive -diff terraform
run "terraform validate" scripts/tf-validate.sh
run "tflint"          tflint --recursive --chdir=terraform --minimum-failure-severity=error
run "ansible-lint"    ansible-lint
run "gitleaks"        gitleaks dir --no-banner --redact .

echo
[ "${status}" -eq 0 ] && echo "Validacao completa: tudo limpo." || echo "Validacao completa: ha falhas acima."
exit "${status}"
