#!/bin/bash
# Shared connection logic for be-claude and be-shell.
# Expects SCRIPT_DIR to be set by the caller.
# Sets up env forwarding and defines run_remote().

set -euo pipefail

# Load config
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "Error: $SCRIPT_DIR/.env not found. Copy .env.example to .env and configure it." >&2
    exit 1
fi
source "$SCRIPT_DIR/.env"

# Sync Claude OAuth credentials — passes the full credentials JSON (not just tokens)
# so the container can write it to tmpfs and Claude Code sees native "claude.ai" auth
# with full account metadata (email, org, subscription type, MCP access).
CREDS_JSON="$("$SCRIPT_DIR/files/sync-claude-credentials" pre)" || true
if [[ -n "$CREDS_JSON" ]]; then
    export FORWARD_CLAUDE_CREDS_JSON="$CREDS_JSON"
fi

full=$(pwd)
base=$CODE_PATH
if [[ "$full" == "$base"* ]]; then
    prep="cd $full; "
else
    prep=""
fi
iterm_opts=()
if [[ -n "${ITERM_SESSION_ID:-}" ]]; then
    iterm_opts=(-o "SendEnv=ITERM_SESSION_ID")
fi

# Forward env vars into the container via SSH SendEnv with FORWARD_ prefix.
# The claude-wrapper script in the container strips the prefix before exec'ing claude.
# Claude OAuth credentials are passed as the full JSON blob via FORWARD_CLAUDE_CREDS_JSON.
# The claude-wrapper writes it to tmpfs (/dev/shm) so credentials never touch host disk.
send_env_opts=(-o "SendEnv=FORWARD_CLAUDE_CREDS_JSON")
for key in ${FORWARD_ENVS:-}; do
    [[ -z "${!key:-}" ]] && continue
    export "FORWARD_${key}=${!key}"
    send_env_opts+=(-o "SendEnv=FORWARD_${key}")
done

ssh_port="${SSH_PORT:-2222}"
mosh_port="${MOSH_PORT:-60001}"

# run_remote <remote_command>
# Connects via mosh or ssh and runs the given command.
run_remote() {
    local remote_cmd="${prep}$1"
    local exit_code=0

    local ssh_cmd="ssh -p ${ssh_port} ${send_env_opts[*]} ${iterm_opts[*]}"

    if [[ "${USE_MOSH:-false}" == "true" ]] && command -v mosh &>/dev/null; then
        mosh --ssh="$ssh_cmd" -p "$mosh_port" localhost -- zsh -c "$remote_cmd" || exit_code=$?
    else
        ssh -A -t -p "${ssh_port}" "${send_env_opts[@]}" ${iterm_opts[@]+"${iterm_opts[@]}"} localhost "$remote_cmd" || exit_code=$?
    fi

    exit "${exit_code:-0}"
}
