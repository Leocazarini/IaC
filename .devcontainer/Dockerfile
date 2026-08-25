# Ambiente de desenvolvimento do repositório de IaC.
# Base Ubuntu LTS, alinhada com o sistema operacional dos hosts gerenciados.
FROM ubuntu:24.04

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
ARG NODE_MAJOR=22
ARG GITLEAKS_VERSION=8.28.0
ARG TZ=America/Sao_Paulo

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=${TZ}

# Utilitários de sistema, cliente SSH e ferramentas de rede usadas na validação
# manual dos hosts (dig, nc, wg genkey).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release apt-transport-https \
        git openssh-client rsync unzip zip tar gzip \
        jq less vim nano make sudo procps file tree \
        python3 python3-pip python3-venv pipx \
        wireguard-tools iproute2 iputils-ping dnsutils netcat-openbsd \
        bash-completion tzdata \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# Terraform, a partir do repositório oficial da HashiCorp.
# Para fixar a versão: substituir "terraform" por "terraform=<versão>-*".
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y --no-install-recommends terraform \
    && rm -rf /var/lib/apt/lists/*

# Node.js, requisito do Claude Code.
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2, no pacote correspondente à arquitetura da imagem.
RUN set -eux; \
    case "$(uname -m)" in \
        x86_64)  awscli_arch=x86_64 ;; \
        aarch64) awscli_arch=aarch64 ;; \
        *) echo "arquitetura não suportada: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# gitleaks — varredura de segredos exigida pelo pre-commit.
RUN set -eux; \
    case "$(uname -m)" in \
        x86_64)  gitleaks_arch=x64 ;; \
        aarch64) gitleaks_arch=arm64 ;; \
        *) echo "arquitetura não suportada: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gitleaks_arch}.tar.gz" \
        -o /tmp/gitleaks.tar.gz; \
    tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks; \
    chmod +x /usr/local/bin/gitleaks; \
    rm -f /tmp/gitleaks.tar.gz

# tflint — análise estática dos módulos Terraform.
RUN curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# Ansible, ansible-lint e pre-commit em ambientes isolados, expostos em /usr/local/bin.
# O metapacote "ansible" traz as collections usadas pelo projeto (amazon.aws,
# community.docker, community.crypto, ansible.posix).
ENV PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin
RUN pipx install --include-deps ansible \
    && pipx inject ansible boto3 botocore passlib netaddr \
    && pipx install ansible-lint \
    && pipx install pre-commit \
    && rm -rf /root/.cache

# Claude Code.
RUN npm install -g @anthropic-ai/claude-code && npm cache clean --force

# Usuário não-root com o mesmo UID/GID do host, para que os arquivos criados no
# bind mount do projeto pertençam ao usuário do host.
RUN set -eux; \
    if getent passwd "${USER_UID}" >/dev/null; then userdel -r "$(getent passwd "${USER_UID}" | cut -d: -f1)" 2>/dev/null || true; fi; \
    if getent group "${USER_GID}" >/dev/null; then groupdel "$(getent group "${USER_GID}" | cut -d: -f1)"; fi; \
    groupadd --gid "${USER_GID}" "${USERNAME}"; \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" --shell /bin/bash --create-home "${USERNAME}"; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"${USERNAME}"; \
    chmod 0440 /etc/sudoers.d/"${USERNAME}"

# Diretórios que recebem volumes nomeados. Criados aqui com o dono correto para
# que o volume herde a permissão na primeira montagem.
RUN install -d -o "${USER_UID}" -g "${USER_GID}" \
        /workspace \
        /commandhistory \
        /home/${USERNAME}/.claude \
        /home/${USERNAME}/.aws \
        /home/${USERNAME}/.cache \
        /home/${USERNAME}/.terraform.d/plugin-cache

USER ${USERNAME}
WORKDIR /workspace

# Histórico de shell persistido em volume, cache de providers do Terraform
# compartilhado entre ambientes e host_key_checking já resolvido pelo inventário.
ENV HISTFILE=/commandhistory/.bash_history \
    HISTSIZE=100000 \
    HISTFILESIZE=100000 \
    TF_PLUGIN_CACHE_DIR=/home/${USERNAME}/.terraform.d/plugin-cache \
    ANSIBLE_HOST_KEY_CHECKING=False \
    PATH=/home/${USERNAME}/.local/bin:${PATH}

RUN printf '%s\n' \
        'export PS1="\[\e[38;5;110m\]iac\[\e[0m\]:\[\e[38;5;150m\]\w\[\e[0m\]\$ "' \
        'export PROMPT_COMMAND="history -a"' \
        'shopt -s histappend' \
        'alias tf=terraform' \
        'complete -C /usr/bin/terraform terraform tf' \
        '[ -f /etc/bash_completion ] && . /etc/bash_completion' \
        >> /home/${USERNAME}/.bashrc

CMD ["sleep", "infinity"]
