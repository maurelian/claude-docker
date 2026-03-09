#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env so we can inspect SSH_AUTHORIZED_KEYS
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# Default SSH_AUTHORIZED_KEYS to the host ssh-agent's loaded keys
if [ -z "${SSH_AUTHORIZED_KEYS:-}" ]; then
    if ! ssh-add -l >/dev/null 2>&1; then
        echo "Error: SSH_AUTHORIZED_KEYS is not set in .env and no keys are loaded in ssh-agent." >&2
        echo "Either add SSH_AUTHORIZED_KEYS=\"...\" to .env or load a key with: ssh-add <your-key>" >&2
        exit 1
    fi
    SSH_AUTHORIZED_KEYS=$(ssh-add -L)
fi

export SSH_AUTHORIZED_KEYS

COMPOSE_FILES="-f docker-compose.yml"

# Built-in modules (conditional on host state)
[ -f "$HOME/.gitconfig" ] && COMPOSE_FILES="$COMPOSE_FILES -f modules/gitconfig.yml"
[ -f "$HOME/.gitignore" ] && COMPOSE_FILES="$COMPOSE_FILES -f modules/gitignore.yml"
[ -d "$HOME/.local/state/mise" ] && COMPOSE_FILES="$COMPOSE_FILES -f modules/mise.yml"

# User-provided compose overlays
for f in "$SCRIPT_DIR"/compose.d/*.yml; do
    [ -f "$f" ] && COMPOSE_FILES="$COMPOSE_FILES -f $f"
done

docker compose $COMPOSE_FILES up -d --build
