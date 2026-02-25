#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: Configuration
#
# Load, validate, and manage configuration.
# Source this file - do not execute directly.
################################################################################

[[ -n "${_GSA_CONFIG_LOADED:-}" ]] && return 0
_GSA_CONFIG_LOADED=1

# ── Defaults ─────────────────────────────────────────────────────────────────
_set_defaults() {
    SYNC_BASE_DIRS="${SYNC_BASE_DIRS:-$HOME/projekte}"
    SYNC_SCAN_DEPTH="${SYNC_SCAN_DEPTH:-3}"
    SYNC_EXCLUDE="${SYNC_EXCLUDE:-}"
    SYNC_INCLUDE="${SYNC_INCLUDE:-}"
    SYNC_COMMIT_MSG="${SYNC_COMMIT_MSG:-chore: auto-sync from {hostname}}"
    SYNC_COMMIT_BODY="${SYNC_COMMIT_BODY:-Automatic synchronization of uncommitted changes.}"
    SYNC_AUTO_CONFIRM="${SYNC_AUTO_CONFIRM:-false}"
    SYNC_PULL_STRATEGY="${SYNC_PULL_STRATEGY:-rebase}"
    SYNC_TAGS="${SYNC_TAGS:-true}"
    SYNC_REMOTE="${SYNC_REMOTE:-origin}"
    SYNC_COLOR="${SYNC_COLOR:-auto}"
    SYNC_VERBOSITY="${SYNC_VERBOSITY:-1}"
    SYNC_CONFLICT_STRATEGY="${SYNC_CONFLICT_STRATEGY:-skip}"
}

# ── Config File Resolution ───────────────────────────────────────────────────
_resolve_config_path() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/git-sync-all/config.conf"
}

# ── Load Config ──────────────────────────────────────────────────────────────
load_config() {
    local config_file="${1:-}"

    # Set defaults first
    _set_defaults

    # Resolve config path if not explicitly provided
    if [[ -z "$config_file" ]]; then
        config_file="$(_resolve_config_path)"
    fi

    # Source config if it exists (overrides defaults)
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        log_debug "Loaded config from $config_file"
    else
        log_debug "No config file found at $config_file. Using defaults."
    fi

    # Validate
    validate_config
}

# ── Validation ───────────────────────────────────────────────────────────────
validate_config() {
    # Validate base dirs exist
    local IFS=":"
    local dir
    for dir in $SYNC_BASE_DIRS; do
        if [[ ! -d "$dir" ]]; then
            die "Config error: directory not found: $dir (SYNC_BASE_DIRS)"
        fi
    done

    # Validate pull strategy
    case "$SYNC_PULL_STRATEGY" in
        rebase | merge) ;;
        *) die "Config error: SYNC_PULL_STRATEGY must be 'rebase' or 'merge' (got: $SYNC_PULL_STRATEGY)" ;;
    esac

    # Validate verbosity
    if [[ ! "$SYNC_VERBOSITY" =~ ^[012]$ ]]; then
        die "Config error: SYNC_VERBOSITY must be 0, 1, or 2 (got: $SYNC_VERBOSITY)"
    fi

    # Validate scan depth
    if [[ ! "$SYNC_SCAN_DEPTH" =~ ^[0-9]+$ ]] || [[ "$SYNC_SCAN_DEPTH" -lt 1 ]]; then
        die "Config error: SYNC_SCAN_DEPTH must be a positive integer (got: $SYNC_SCAN_DEPTH)"
    fi

    # Validate conflict strategy
    case "${SYNC_CONFLICT_STRATEGY:-skip}" in
        skip | stash | commit) ;;
        *) die "Config error: SYNC_CONFLICT_STRATEGY must be 'skip', 'stash', or 'commit' (got: $SYNC_CONFLICT_STRATEGY)" ;;
    esac

    log_debug "Config validated"
}

# ── Init Config ──────────────────────────────────────────────────────────────
init_config() {
    local config_dir config_file
    config_file="$(_resolve_config_path)"
    config_dir="$(dirname "$config_file")"

    if [[ -f "$config_file" ]]; then
        log_warn "Config already exists: $config_file"
        log_info "Edit with: \${EDITOR:-nano} $config_file"
        return 0
    fi

    # Find example config relative to script
    local example_config="${GSA_LIB_DIR}/../config/config.conf.example"
    if [[ ! -f "$example_config" ]]; then
        # Fallback for installed version
        example_config="${GSA_LIB_DIR}/../../share/git-sync-all/config.conf.example"
    fi

    mkdir -p "$config_dir"

    if [[ -f "$example_config" ]]; then
        cp "$example_config" "$config_file"
        log_ok "Config created: $config_file"
    else
        # Generate minimal config inline
        cat >"$config_file" <<'CONF'
# git-sync-all configuration
# See: https://github.com/markus-michalski/git-sync-all

# Directories to scan for Git repositories (colon-separated)
SYNC_BASE_DIRS="$HOME/projekte"

# Maximum depth for repo discovery
SYNC_SCAN_DEPTH=3

# Exclude repos by name (colon-separated glob patterns)
# SYNC_EXCLUDE="node_modules:vendor"

# Only sync these repos (colon-separated glob patterns)
# SYNC_INCLUDE="my-project:other-project"

# Default commit message ({hostname} and {date} are replaced)
SYNC_COMMIT_MSG="chore: auto-sync from {hostname}"

# Auto-confirm all repos without asking
SYNC_AUTO_CONFIRM=false

# Pull strategy: rebase or merge
SYNC_PULL_STRATEGY="rebase"

# Sync tags from remote
SYNC_TAGS=true

# Remote name
SYNC_REMOTE="origin"

# Color output: auto, true, false
SYNC_COLOR="auto"

# Verbosity: 0=quiet, 1=normal, 2=verbose
SYNC_VERBOSITY=1
CONF
        log_ok "Config created: $config_file"
    fi

    # Open in editor if interactive
    if [[ -t 0 ]]; then
        local editor="${EDITOR:-${VISUAL:-nano}}"
        log_info "Opening config with $editor..."
        "$editor" "$config_file"
    fi
}
