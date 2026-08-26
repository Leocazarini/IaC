#!/usr/bin/env bash
# Prepara a identidade do container na subida. Roda como o usuário dev.
set -euo pipefail

SSH_DIR="${HOME}/.ssh"
KEY="${SSH_DIR}/deploy-key-github"

# Chave de acesso ao repositório, própria deste container. É gerada uma única vez
# e vive no volume ssh-keys; nenhuma chave do host é montada aqui.
chmod 700 "${SSH_DIR}"
if [ ! -f "${KEY}" ]; then
    ssh-keygen -t ed25519 -N '' -C "deploy-key-github@iac-dev" -f "${KEY}" >/dev/null
    echo "[entrypoint] chave deploy-key-github gerada:"
    echo
    cat "${KEY}.pub"
    echo
    echo "[entrypoint] cadastre-a em Settings > Deploy keys do repositório no GitHub."
fi
chmod 600 "${KEY}"
chmod 644 "${KEY}.pub"

# Usa a chave apenas para o GitHub e não oferece nenhuma outra identidade.
cat > "${SSH_DIR}/config" <<EOF
Host github.com
    HostName github.com
    User git
    IdentityFile ${KEY}
    IdentitiesOnly yes
    AddKeysToAgent no
EOF
chmod 600 "${SSH_DIR}/config"

# Chave pública do servidor do GitHub, fixada para dispensar a confirmação
# interativa na primeira conexão.
# Fonte: https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
if [ ! -f "${SSH_DIR}/known_hosts" ]; then
    echo "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl" \
        > "${SSH_DIR}/known_hosts"
    chmod 644 "${SSH_DIR}/known_hosts"
fi

# Autoria dos commits. Recebida por variável de ambiente; o .gitconfig do host
# não é montado.
if [ -n "${GIT_USER_NAME:-}" ]; then
    git config --global user.name "${GIT_USER_NAME}"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.email "${GIT_USER_EMAIL}"
fi
git config --global --add safe.directory /workspace

exec "$@"
