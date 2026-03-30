# Resolve FORWARD_* env vars and Claude credentials on first shell init.
# SSH AcceptEnv passes host env vars with a FORWARD_ prefix to avoid collisions.
# This script strips the prefix so all processes see the real names.
# Must run before other .zshrc.d scripts (hence the 00- prefix).

# Merge host mise trusted/tracked configs without overwriting container-local entries
for dir in trusted-configs tracked-configs; do
    host_dir=~/.local/state/mise/host-$dir
    dest_dir=~/.local/state/mise/$dir
    if [[ -d "$host_dir" ]]; then
        mkdir -p "$dest_dir"
        cp -r --update=none "$host_dir"/. "$dest_dir"/
    fi
done

# Write full credentials JSON to tmpfs so Claude Code sees native "claude.ai" auth.
# Only overwrite if the incoming credentials are newer than what's already in tmpfs
# (the container may have refreshed the token since the last session start).
if [[ -n "${FORWARD_CLAUDE_CREDS_JSON:-}" ]]; then
    creds_target=~/.claude/.credentials.json
    shm_dir=/dev/shm/claude-creds
    shm_file=$shm_dir/.credentials.json

    if [[ -L "$creds_target" && "$(readlink "$creds_target")" == /dev/shm/* ]]; then
        shm_file="$(readlink "$creds_target")"
        shm_dir="$(dirname "$shm_file")"
    fi

    mkdir -p "$shm_dir"
    chmod 700 "$shm_dir"

    # Compare expiresAt to avoid overwriting a fresher token from a previous session
    _get_expires_at() {
        python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('claudeAiOauth', {}).get('expiresAt', 0))
except Exception:
    print(0)
" <<< "$1"
    }

    incoming_exp=$(_get_expires_at "$FORWARD_CLAUDE_CREDS_JSON")
    existing_exp=0
    if [[ -f "$shm_file" ]]; then
        existing_exp=$(_get_expires_at "$(cat "$shm_file")")
    fi

    if (( incoming_exp > existing_exp )); then
        printf '%s' "$FORWARD_CLAUDE_CREDS_JSON" > "$shm_file"
        chmod 600 "$shm_file"
    elif (( existing_exp > 0 )); then
        echo "Keeping existing container credentials (newer than host)." >&2
    fi

    if [[ ! -L "$creds_target" || "$(readlink "$creds_target")" != "$shm_file" ]]; then
        ln -sf "$shm_file" "$creds_target"
    fi

    unset FORWARD_CLAUDE_CREDS_JSON
fi

# Unprefix FORWARD_* env vars: FORWARD_GH_TOKEN=xxx becomes GH_TOKEN=xxx
for var in ${(k)parameters[(I)FORWARD_*]}; do
    export "${var#FORWARD_}=${(P)var}"
    unset "$var"
done
