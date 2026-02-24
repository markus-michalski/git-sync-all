#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: Repository Discovery
#
# Find Git repositories, apply include/exclude filters.
# Source this file - do not execute directly.
################################################################################

[[ -n "${_GSA_REPO_DISCOVERY_LOADED:-}" ]] && return 0
_GSA_REPO_DISCOVERY_LOADED=1

# ── Discover Repos ───────────────────────────────────────────────────────────
# Populates the named array reference with discovered repo paths
discover_repos() {
    local -n _result=$1
    _result=()

    local IFS=":"
    local base_dir
    for base_dir in $SYNC_BASE_DIRS; do
        log_debug "Scanning: $base_dir (depth: $SYNC_SCAN_DEPTH)"

        # maxdepth = scan_depth + 1 because .git is always one level below the repo dir
        local find_depth=$((SYNC_SCAN_DEPTH + 1))
        while IFS= read -r -d '' git_dir; do
            local repo_dir
            repo_dir="$(dirname "$git_dir")"
            local repo_name
            repo_name="$(basename "$repo_dir")"

            # Apply include/exclude filters
            if _should_skip_repo "$repo_name"; then
                log_debug "Skipping filtered repo: $repo_name"
                continue
            fi

            # Check remote exists
            if ! _has_remote "$repo_dir"; then
                log_debug "Skipping repo without remote: $repo_name"
                continue
            fi

            _result+=("$repo_dir")
        done < <(find "$base_dir" -maxdepth "$find_depth" \
            -type d -name ".git" -print0 2>/dev/null | sort -z)
    done

    log_info "Found ${#_result[@]} repositories"
}

# ── Filter Logic ─────────────────────────────────────────────────────────────

# Returns 0 (true) if repo should be skipped
_should_skip_repo() {
    local repo_name="$1"

    # Include filter (whitelist): if set, repo MUST match one pattern
    if [[ -n "${SYNC_INCLUDE:-}" ]]; then
        local saved_ifs="$IFS"
        IFS=":"
        local matched=false
        local pattern
        for pattern in $SYNC_INCLUDE; do
            # shellcheck disable=SC2053
            if [[ "$repo_name" == $pattern ]]; then
                matched=true
                break
            fi
        done
        IFS="$saved_ifs"

        if [[ "$matched" == "false" ]]; then
            return 0 # skip: not in include list
        fi
    fi

    # Exclude filter (blacklist)
    if [[ -n "${SYNC_EXCLUDE:-}" ]]; then
        local saved_ifs="$IFS"
        IFS=":"
        local pattern
        for pattern in $SYNC_EXCLUDE; do
            # shellcheck disable=SC2053
            if [[ "$repo_name" == $pattern ]]; then
                IFS="$saved_ifs"
                return 0 # skip: matches exclude
            fi
        done
        IFS="$saved_ifs"
    fi

    return 1 # don't skip
}

# Check if repo has configured remote
_has_remote() {
    local repo_dir="$1"
    (
        cd "$repo_dir" || return 1
        git remote get-url "${SYNC_REMOTE:-origin}" &>/dev/null
    )
}
