#!/bin/bash

# Build the docker compose file list shared by run.sh and stop.sh.
# Expects SCRIPT_DIR to be set by the caller.

# Resolve a symlink to a mountable path. For symlinked dotfiles (e.g. Nix Home
# Manager pointing into /nix/store), Docker Desktop can't follow the symlink.
# We hard link the resolved target into .mount-stage/ so Docker sees a local path
# that shares the same inode. Falls back to cp -L if hard linking fails (cross-fs).
# For non-symlinks, mounts the original file directly.
resolve_mount_path() {
    local src="$1" name="$2"
    if [ -L "$src" ]; then
        local resolved mount_stage="$SCRIPT_DIR/.mount-stage"
        mkdir -p "$mount_stage"
        # python -c is portable across macOS and Linux (readlink -f is GNU-only)
        resolved="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$src")"
        local dest="$mount_stage/$name"
        if ln -f "$resolved" "$dest" 2>/dev/null || cp -L "$src" "$dest"; then
            echo "$dest"
        else
            echo "$src"
        fi
    else
        echo "$src"
    fi
}

build_compose_file_args() {
    COMPOSE_FILE_ARGS=(-f docker-compose.yml)

    # Built-in modules (conditional on host state)
    if [ -f "$HOME/.gitconfig" ]; then
        export GITCONFIG_PATH
        GITCONFIG_PATH="$(resolve_mount_path "$HOME/.gitconfig" .gitconfig)"
        COMPOSE_FILE_ARGS+=(-f modules/gitconfig.yml)
    fi
    if [ -f "$HOME/.gitignore" ]; then
        export GITIGNORE_PATH
        GITIGNORE_PATH="$(resolve_mount_path "$HOME/.gitignore" .gitignore)"
        COMPOSE_FILE_ARGS+=(-f modules/gitignore.yml)
    fi
    [ -d "$HOME/.local/state/mise" ] && COMPOSE_FILE_ARGS+=(-f modules/mise.yml)

    # Codex CLI config: create the directory if it doesn't exist so Docker
    # doesn't create it as root on first mount.
    mkdir -p "$HOME/.codex"
    COMPOSE_FILE_ARGS+=(-f modules/codex.yml)

    # User-provided compose overlays
    local f
    for f in "$SCRIPT_DIR"/compose.d/*.yml; do
        [ -f "$f" ] && COMPOSE_FILE_ARGS+=(-f "$f") || true
    done

    if [ -n "${EXTRA_PORTS:-}" ]; then
        local extra_ports_file="$SCRIPT_DIR/.mount-stage/extra-ports.yml"
        mkdir -p "$SCRIPT_DIR/.mount-stage"
        {
            printf 'services:\n'
            printf '  claude-dev:\n'
            printf '    ports:\n'
            local port
            for port in $EXTRA_PORTS; do
                printf '      - "%s"\n' "$port"
            done
        } > "$extra_ports_file"
        COMPOSE_FILE_ARGS+=(-f "$extra_ports_file")
    fi

    # EXTRA_MOUNTS: space-separated host paths to bind-mount read-only at the
    # same path inside the container. Missing files are skipped silently so
    # the list can include optional dotfiles. Symlinks are resolved via
    # resolve_mount_path for Nix home-manager compatibility.
    if [ -n "${EXTRA_MOUNTS:-}" ]; then
        local extra_mounts_file="$SCRIPT_DIR/.mount-stage/extra-mounts.yml"
        local mount_lines=""
        local src resolved name
        for src in $EXTRA_MOUNTS; do
            [ -e "$src" ] || continue
            name="extra-$(printf '%s' "$src" | shasum | cut -c1-12)-$(basename "$src")"
            resolved="$(resolve_mount_path "$src" "$name")"
            mount_lines+="      - \"${resolved}:${src}:ro\""$'\n'
        done
        if [ -n "$mount_lines" ]; then
            mkdir -p "$SCRIPT_DIR/.mount-stage"
            {
                printf 'services:\n'
                printf '  claude-dev:\n'
                printf '    volumes:\n'
                printf '%s' "$mount_lines"
            } > "$extra_mounts_file"
            COMPOSE_FILE_ARGS+=(-f "$extra_mounts_file")
        fi
    fi
}
