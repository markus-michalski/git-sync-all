#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: Core Library
#
# Strict mode, colors, logging, cleanup trap, dependency check, lock file.
# Source this file - do not execute directly.
################################################################################

# Prevent double-sourcing
[[ -n "${_GSA_CORE_LOADED:-}" ]] && return 0
_GSA_CORE_LOADED=1

# ── Strict Mode ──────────────────────────────────────────────────────────────
set -euo pipefail

# ── Global State ─────────────────────────────────────────────────────────────
declare -a _GSA_TEMP_FILES=()
GSA_LOCK_FILE=""
DRY_RUN="${DRY_RUN:-false}"

# ── Temp File Management ─────────────────────────────────────────────────────

# Register a temp file/dir for automatic cleanup on exit
register_temp() {
    _GSA_TEMP_FILES+=("$1")
}

# Create and register a temp file
make_temp_file() {
    local tmp
    tmp=$(mktemp)
    register_temp "$tmp"
    echo "$tmp"
}

# Create and register a temp directory
make_temp_dir() {
    local tmp
    tmp=$(mktemp -d)
    register_temp "$tmp"
    echo "$tmp"
}

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Detect color support and disable if not a terminal or --no-color
setup_colors() {
    local color_mode="${SYNC_COLOR:-auto}"

    case "$color_mode" in
        false | no | off | never)
            _disable_colors
            ;;
        true | yes | on | always)
            # Keep colors enabled
            ;;
        auto | *)
            if [[ ! -t 2 ]]; then
                _disable_colors
            fi
            ;;
    esac
}

_disable_colors() {
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
}

# ── Logging (all to stderr) ─────────────────────────────────────────────────
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    [[ "${SYNC_VERBOSITY:-1}" -ge 1 ]] && echo -e "${YELLOW}[WARN]${NC}  $1" >&2
    return 0
}

log_info() {
    [[ "${SYNC_VERBOSITY:-1}" -ge 1 ]] && echo -e "${BLUE}[INFO]${NC}  $1" >&2
    return 0
}

log_ok() {
    [[ "${SYNC_VERBOSITY:-1}" -ge 1 ]] && echo -e "${GREEN}[OK]${NC}    $1" >&2
    return 0
}

log_debug() {
    [[ "${SYNC_VERBOSITY:-1}" -ge 2 ]] && echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    return 0
}

log_dry() {
    echo -e "${YELLOW}[DRY-RUN]${NC} Would: $1" >&2
}

# Fatal error: print message and exit
die() {
    log_error "$1"
    exit "${2:-1}"
}

# ── Cleanup Trap ─────────────────────────────────────────────────────────────
_gsa_cleanup() {
    # Remove lock file
    if [[ -n "${GSA_LOCK_FILE:-}" && -f "$GSA_LOCK_FILE" ]]; then
        rm -f "$GSA_LOCK_FILE"
    fi

    # Remove temp files
    local file
    for file in "${_GSA_TEMP_FILES[@]}"; do
        rm -rf "$file" 2>/dev/null || true
    done
}
trap _gsa_cleanup EXIT INT TERM

# ── Dependency Check ─────────────────────────────────────────────────────────
check_dependencies() {
    if ! command -v git &>/dev/null; then
        die "Required dependency 'git' not found. Please install git."
    fi

    # Check git version for --prune-tags support (requires >= 2.17)
    local git_version_str
    git_version_str=$(git --version)
    local git_major git_minor
    git_major=$(echo "$git_version_str" | grep -oP '\d+' | head -1)
    git_minor=$(echo "$git_version_str" | grep -oP '\d+' | head -2 | tail -1)

    if [[ "$git_major" -lt 2 ]] || { [[ "$git_major" -eq 2 ]] && [[ "$git_minor" -lt 17 ]]; }; then
        log_warn "Git version ${git_major}.${git_minor} detected. Recommend >= 2.17 for --prune-tags support."
    fi

    log_debug "Git version: ${git_major}.${git_minor}"
}

# ── Lock File ────────────────────────────────────────────────────────────────
acquire_lock() {
    GSA_LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/git-sync-all.lock"

    if [[ -f "$GSA_LOCK_FILE" ]]; then
        local pid
        pid=$(<"$GSA_LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            die "Another instance is running (PID $pid). Remove $GSA_LOCK_FILE if stale."
        else
            log_warn "Removing stale lock file (PID $pid no longer running)"
            rm -f "$GSA_LOCK_FILE"
        fi
    fi

    echo $$ >"$GSA_LOCK_FILE"
    log_debug "Lock acquired: $GSA_LOCK_FILE (PID $$)"
}

# ── Environment Setup ────────────────────────────────────────────────────────
setup_environment() {
    setup_colors
    check_dependencies
    acquire_lock
}
