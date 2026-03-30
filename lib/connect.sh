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
# 00-forward-env.sh (in .zshrc.d) strips the prefix during shell init so all
# processes see the real names. Credentials are written to tmpfs (/dev/shm).
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

    # Post-session: sync credentials from container tmpfs back to host Keychain.
    # The container may have refreshed the token during the session.
    sync_creds_back || true

    exit "${exit_code:-0}"
}

# Read credentials from container tmpfs and update host Keychain if newer.
sync_creds_back() {
    # Only sync on macOS (Keychain is the credential store)
    [[ "$(uname -s)" != "Darwin" ]] && return 0
    [[ "${CLAUDE_CREDENTIAL_SYNC:-true}" == "false" ]] && return 0

    local container_creds
    container_creds="$(ssh -p "${ssh_port}" -o BatchMode=yes localhost \
        'cat /dev/shm/claude-creds/.credentials.json 2>/dev/null' 2>/dev/null)" || return 0
    [[ -z "$container_creds" ]] && return 0

    local keychain_creds
    keychain_creds="$(security find-generic-password -w -s "Claude Code-credentials" 2>/dev/null)" || keychain_creds=""

    local container_exp keychain_exp
    container_exp="$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('claudeAiOauth', {}).get('expiresAt', 0))
except Exception:
    print(0)
" "$container_creds")"
    keychain_exp="$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('claudeAiOauth', {}).get('expiresAt', 0))
except Exception:
    print(0)
" "$keychain_creds")"

    if (( container_exp > keychain_exp )); then
        security delete-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 || true
        security add-generic-password -s "Claude Code-credentials" -a "$USER" -w "$container_creds" >/dev/null 2>&1
    fi
}
