#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: Git Operations
#
# All git operations with subshell isolation and dry-run support.
# Source this file - do not execute directly.
################################################################################

[[ -n "${_GSA_GIT_OPS_LOADED:-}" ]] && return 0
_GSA_GIT_OPS_LOADED=1

# ── Dry-Run Wrapper ──────────────────────────────────────────────────────────
# Wraps git commands: shows instead of executes in dry-run mode
git_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_dry "git $*"
        return 0
    fi
    git "$@"
}

# ── Read-Only Operations (always execute, even in dry-run) ───────────────────

get_current_branch() {
    local repo_path="$1"
    (
        cd "$repo_path" || return 1
        git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
    )
}

has_uncommitted_changes() {
    local repo_path="$1"
    (
        cd "$repo_path" || return 1
        [[ -n "$(git status --porcelain 2>/dev/null)" ]]
    )
}

count_dirty_files() {
    local repo_path="$1"
    (
        cd "$repo_path" || return 1
        git status --porcelain 2>/dev/null | wc -l
    )
}

# Show changed files (first N lines)
show_changed_files() {
    local repo_path="$1"
    local max_lines="${2:-5}"
    (
        cd "$repo_path" || return 1
        local changed_files
        changed_files=$(git status --porcelain | head -"$max_lines")
        while IFS= read -r line; do
            echo -e "    ${YELLOW}${line}${NC}" >&2
        done <<<"$changed_files"

        local total
        total=$(git status --porcelain | wc -l)
        if [[ "$total" -gt "$max_lines" ]]; then
            echo -e "    ${YELLOW}... and $((total - max_lines)) more files${NC}" >&2
        fi
    )
}

has_unpushed_commits() {
    local repo_path="$1"
    (
        cd "$repo_path" || return 1
        local upstream
        # shellcheck disable=SC1083
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null) || return 1
        [[ -z "$upstream" ]] && return 1

        local count
        count=$(git log "${upstream}..HEAD" --oneline 2>/dev/null | wc -l)
        [[ "$count" -gt 0 ]]
    )
}

count_unpushed() {
    local repo_path="$1"
    (
        cd "$repo_path" || return 1
        local upstream
        # shellcheck disable=SC1083
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null) || {
            echo "0"
            return
        }
        git log "${upstream}..HEAD" --oneline 2>/dev/null | wc -l
    )
}

has_unpulled_commits() {
    local repo_path="$1"
    (
        cd "$repo_path" || return 1
        local branch upstream
        branch=$(git rev-parse --abbrev-ref HEAD)
        # shellcheck disable=SC1083
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null) || return 1
        [[ -z "$upstream" ]] && return 1

        # Fetch to get latest remote state
        git fetch "${SYNC_REMOTE:-origin}" "$branch" --quiet 2>/dev/null

        local count
        count=$(git log "HEAD..${upstream}" --oneline 2>/dev/null | wc -l)
        [[ "$count" -gt 0 ]]
    )
}

count_unpulled() {
    local repo_path="$1"
    (
        cd "$repo_path" || return 1
        local upstream
        # shellcheck disable=SC1083
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null) || {
            echo "0"
            return
        }
        git log "HEAD..${upstream}" --oneline 2>/dev/null | wc -l
    )
}

# ── Write Operations (respect dry-run) ──────────────────────────────────────

commit_changes() {
    local repo_path="$1"
    local commit_msg="$2"
    local commit_body="${3:-}"

    (
        cd "$repo_path" || return 1

        git_cmd add -A

        if [[ -n "$commit_body" ]]; then
            git_cmd commit -m "$commit_msg" -m "$commit_body"
        else
            git_cmd commit -m "$commit_msg"
        fi
    )
}

pull_changes() {
    local repo_path="$1"
    local strategy="${SYNC_PULL_STRATEGY:-rebase}"
    local remote="${SYNC_REMOTE:-origin}"

    (
        cd "$repo_path" || return 1
        local branch
        branch=$(git rev-parse --abbrev-ref HEAD)

        case "$strategy" in
            rebase)
                git_cmd pull --rebase "$remote" "$branch"
                ;;
            merge)
                git_cmd pull "$remote" "$branch"
                ;;
            *)
                log_error "Unknown pull strategy: $strategy"
                return 1
                ;;
        esac
    )
}

push_commits() {
    local repo_path="$1"
    local remote="${SYNC_REMOTE:-origin}"

    (
        cd "$repo_path" || return 1
        local branch
        branch=$(git rev-parse --abbrev-ref HEAD)
        git_cmd push "$remote" "$branch"
    )
}

sync_tags() {
    local repo_path="$1"
    local remote="${SYNC_REMOTE:-origin}"

    (
        cd "$repo_path" || return 1
        git_cmd fetch --tags --prune-tags "$remote" 2>/dev/null
    )
}
