#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: CLI Argument Parsing
#
# Parse command-line arguments, show help/version, setup aliases.
# Source this file - do not execute directly.
################################################################################

[[ -n "${_GSA_CLI_LOADED:-}" ]] && return 0
_GSA_CLI_LOADED=1

# ── CLI Override Variables ───────────────────────────────────────────────────
# Set by parse_args(), applied after config loading
CONFIG_FILE=""
DRY_RUN=false
NO_PULL=false
NO_PUSH=false
NO_COMMIT=false
STATUS_ONLY=false
declare -a _CLI_EXCLUDES=()
declare -a _CLI_INCLUDES=()
declare -a _CLI_DIRS=()

# ── Argument Parsing ─────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_help
                exit 0
                ;;
            -V | --version)
                show_version
                exit 0
                ;;
            -n | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v | --verbose)
                SYNC_VERBOSITY=$((${SYNC_VERBOSITY:-1} + 1))
                shift
                ;;
            -q | --quiet)
                SYNC_VERBOSITY=0
                shift
                ;;
            -y | --yes)
                SYNC_AUTO_CONFIRM=true
                shift
                ;;
            -c | --config)
                [[ -z "${2:-}" ]] && die "--config requires a file path"
                CONFIG_FILE="$2"
                shift 2
                ;;
            --init-config)
                # Need core.sh loaded for logging
                _set_defaults 2>/dev/null || true
                init_config
                exit 0
                ;;
            --setup-alias)
                _set_defaults 2>/dev/null || true
                setup_aliases
                exit 0
                ;;
            --no-pull)
                NO_PULL=true
                shift
                ;;
            --no-push)
                NO_PUSH=true
                shift
                ;;
            --no-tags)
                SYNC_TAGS=false
                shift
                ;;
            --no-commit)
                NO_COMMIT=true
                shift
                ;;
            --no-color)
                SYNC_COLOR=false
                shift
                ;;
            --conflict-strategy)
                [[ -z "${2:-}" ]] && die "--conflict-strategy requires a value (skip, stash, commit)"
                SYNC_CONFLICT_STRATEGY="$2"
                shift 2
                ;;
            --status)
                STATUS_ONLY=true
                shift
                ;;
            --exclude)
                [[ -z "${2:-}" ]] && die "--exclude requires a pattern"
                _CLI_EXCLUDES+=("$2")
                shift 2
                ;;
            --include)
                [[ -z "${2:-}" ]] && die "--include requires a pattern"
                _CLI_INCLUDES+=("$2")
                shift 2
                ;;
            --)
                shift
                _CLI_DIRS+=("$@")
                break
                ;;
            -*)
                die "Unknown option: $1 (see --help)"
                ;;
            *)
                _CLI_DIRS+=("$1")
                shift
                ;;
        esac
    done
}

# Apply CLI overrides after config loading (CLI > Config > Defaults)
apply_cli_overrides() {
    if [[ ${#_CLI_EXCLUDES[@]} -gt 0 ]]; then
        SYNC_EXCLUDE="$(
            IFS=:
            echo "${_CLI_EXCLUDES[*]}"
        )"
    fi
    if [[ ${#_CLI_INCLUDES[@]} -gt 0 ]]; then
        SYNC_INCLUDE="$(
            IFS=:
            echo "${_CLI_INCLUDES[*]}"
        )"
    fi
    if [[ ${#_CLI_DIRS[@]} -gt 0 ]]; then
        SYNC_BASE_DIRS="$(
            IFS=:
            echo "${_CLI_DIRS[*]}"
        )"
    fi
}

# ── Help Text ────────────────────────────────────────────────────────────────
show_help() {
    cat <<EOF
${BOLD:-}git-sync-all${NC:-} - Sync all Git repositories in a directory tree

${YELLOW:-}USAGE${NC:-}
    git-sync-all [OPTIONS] [DIRECTORY...]

${YELLOW:-}DESCRIPTION${NC:-}
    Scans directories for Git repositories and synchronizes them:
    fetch tags, commit uncommitted changes, pull from remote, push to remote.

    Without arguments, scans the configured SYNC_BASE_DIRS (default: ~/projekte).
    Pass directories as arguments to override.

${YELLOW:-}OPTIONS${NC:-}
    -h, --help           Show this help and exit
    -V, --version        Show version and exit
    -n, --dry-run        Show what would happen, change nothing
    -v, --verbose        Increase verbosity (can stack: -vv)
    -q, --quiet          Suppress all output except errors
    -y, --yes            Auto-confirm all repositories (no prompts)
    -c, --config FILE    Use specific config file

    --init-config        Create default config at XDG location
    --setup-alias        Add 'git check' alias to ~/.gitconfig

    --no-pull            Skip pulling from remote
    --no-push            Skip pushing to remote
    --no-tags            Skip tag synchronization
    --no-commit          Skip auto-committing (only pull/push)
    --no-color           Disable colored output

    --conflict-strategy  Conflict handling: skip (default), stash, commit
    --status             Show repo status only (no sync actions)
    --exclude PATTERN    Exclude repos matching pattern (repeatable)
    --include PATTERN    Only sync repos matching pattern (repeatable)

${YELLOW:-}CONFIGURATION${NC:-}
    Config file: \${XDG_CONFIG_HOME}/git-sync-all/config.conf
    Default:     ~/.config/git-sync-all/config.conf

    Create with: git-sync-all --init-config

    Priority: CLI flags > Environment variables > Config file > Defaults

${YELLOW:-}EXAMPLES${NC:-}
    git-sync-all                          # Sync all repos in default directory
    git-sync-all ~/work ~/personal        # Sync repos in specific directories
    git-sync-all --dry-run                # Preview what would happen
    git-sync-all --yes                    # No prompts (CI/cron-friendly)
    git-sync-all --status                 # Show status table only
    git-sync-all --exclude vendor         # Skip repos named "vendor"
    git-sync-all --no-commit --no-push    # Only pull from remote

${YELLOW:-}EXIT CODES${NC:-}
    0    All repositories synced successfully
    1    One or more repositories failed to sync

EOF
}

# ── Version ──────────────────────────────────────────────────────────────────
show_version() {
    echo "git-sync-all v${GSA_VERSION}"
}

# ── Alias Setup ──────────────────────────────────────────────────────────────
setup_aliases() {
    local bin_path
    # Use GSA_SCRIPT_DIR (set by bin/git-sync-all) for correct path
    # in both dev layout (lib/../bin/) and installed layout (~/.local/bin/)
    bin_path="${GSA_SCRIPT_DIR}/bin/git-sync-all"
    bin_path="$(readlink -f "$bin_path")"

    # Git alias: git check
    local existing
    existing=$(git config --global alias.check 2>/dev/null || true)

    if [[ -n "$existing" ]]; then
        log_warn "'git check' alias already exists: $existing"
        log_info "To update, run: git config --global alias.check '!$bin_path'"
    else
        git config --global alias.check "!$bin_path"
        log_ok "Added 'git check' alias to ~/.gitconfig"
    fi

    log_info "You can now use: git check"
}
