FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    git curl sudo zsh fzf ripgrep make \
    iptables ipset iproute2 dnsutils \
    openssh-server jq vim gh golang gpg python3.12-venv \
    ca-certificates tmux

# Install internal domain root certificates
RUN printf '%s\n' \
    '-----BEGIN CERTIFICATE-----' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    '-----END CERTIFICATE-----' \
    > /usr/local/share/ca-certificates/custom-ca.crt && \
    printf '%s\n' \
    '-----BEGIN CERTIFICATE-----' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    'REDACTED' \
    '-----END CERTIFICATE-----' \
    > /usr/local/share/ca-certificates/custom-ca-2.crt && \
    update-ca-certificates

# Non-root user for better isolation
ARG USERNAME
ARG USER_HOME
ARG CODE_PATH
RUN mkdir -p "$(dirname "$USER_HOME")" && \
    useradd -ms /bin/zsh -d "$USER_HOME" $USERNAME && \
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# SSH setup
RUN mkdir /var/run/sshd && \
    cp -r /etc/ssh /etc/ssh.original

USER $USERNAME
WORKDIR $CODE_PATH

RUN go install golang.org/x/tools/gopls@latest

# TODO: Install claude
# TODO: Install mise
