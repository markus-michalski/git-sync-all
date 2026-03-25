#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: GitHub Issues Check
#
# Query open issues for repos via GitHub CLI (gh).
# Source this file - do not execute directly.
################################################################################

[[ -n "${_GSA_ISSUES_LOADED:-}" ]] && return 0
_GSA_ISSUES_LOADED=1

# ── Dependency Check ────────────────────────────────────────────────────────
_check_gh_cli() {
    if ! command -v gh &>/dev/null; then
        die "GitHub CLI (gh) not found. Install from https://cli.github.com/"
    fi

    if ! gh auth status &>/dev/null; then
        die "GitHub CLI not authenticated. Run: gh auth login"
    fi

    log_debug "GitHub CLI: authenticated"
}

# ── Get Remote Owner/Repo ───────────────────────────────────────────────────
# Extracts "owner/repo" from the git remote URL.
# Returns empty string if not a GitHub repo.
_get_github_repo() {
    local repo_path="$1"
    local remote_url

    remote_url=$(git -C "$repo_path" remote get-url "${SYNC_REMOTE:-origin}" 2>/dev/null) || return 1

    # Match SSH: git@github.com:owner/repo.git
    if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    return 1
}

# ── Query Issues for Single Repo ────────────────────────────────────────────
# Returns tab-separated lines: number\ttitle (one per issue).
# Empty output means no open issues.
_query_issues() {
    local gh_repo="$1"
    local limit="${2:-10}"

    gh issue list --repo "$gh_repo" --state open --limit "$limit" \
        --json number,title --template '{{range .}}{{.number}}{{"\t"}}{{.title}}{{"\n"}}{{end}}' 2>/dev/null || true
}

# ── Show Issues for Inventory Repos ─────────────────────────────────────────
# Main entry point for --issues mode.
# Reads repos from inventory, queries GitHub issues, displays results.
#
# Returns stats string: "total_repos:repos_with_issues:total_issues:skipped"
show_issues() {
    local -n _issue_repos=$1

    _check_gh_cli

    local total=${#_issue_repos[@]}
    local repos_with_issues=0
    local total_issues=0
    local skipped=0

    # Table header
    printf "${BOLD:-}%-35s %s${NC:-}\n" "REPOSITORY" "OPEN ISSUES" >&2
    printf "%s\n" "$(printf -- '-%.0s' {1..50})" >&2

    local repo_name
    for repo_name in "${_issue_repos[@]}"; do
        # Find repo path on disk
        local repo_path=""
        repo_path=$(_find_repo_path "$repo_name")

        if [[ -z "$repo_path" ]]; then
            printf "%-35s %s\n" "$repo_name" "${YELLOW:-}not found${NC:-}" >&2
            ((skipped++))
            continue
        fi

        # Get GitHub owner/repo
        local gh_repo=""
        gh_repo=$(_get_github_repo "$repo_path") || true

        if [[ -z "$gh_repo" ]]; then
            printf "%-35s %s\n" "$repo_name" "${YELLOW:-}not on GitHub${NC:-}" >&2
            ((skipped++))
            continue
        fi

        log_debug "Querying issues for $gh_repo"

        # Query open issues
        local issues_output
        issues_output=$(_query_issues "$gh_repo")

        local count=0
        if [[ -n "$issues_output" ]]; then
            count=$(echo "$issues_output" | wc -l)
        fi

        if [[ "$count" -gt 0 ]]; then
            printf "%-35s ${RED:-}%s${NC:-}\n" "$repo_name" "$count" >&2
            ((repos_with_issues++))
            ((total_issues += count))

            # Verbose: show issue details
            if [[ "${SYNC_VERBOSITY:-1}" -ge 2 ]]; then
                while IFS=$'\t' read -r num title; do
                    printf "  ${CYAN:-}#%-6s${NC:-} %s\n" "$num" "$title" >&2
                done <<< "$issues_output"
            fi
        else
            printf "%-35s %s\n" "$repo_name" "${GREEN:-}--${NC:-}" >&2
        fi
    done

    # Summary
    echo "" >&2
    if [[ "$repos_with_issues" -eq 0 ]]; then
        log_ok "No open issues in any of the $total repositories"
    else
        log_warn "${repos_with_issues} of ${total} repos have open issues (total: ${total_issues})"
    fi

    echo "${total}:${repos_with_issues}:${total_issues}:${skipped}"
}

# ── Find Repo Path on Disk ─────────────────────────────────────────────────
# Searches SYNC_BASE_DIRS for a repo directory by name.
_find_repo_path() {
    local repo_name="$1"

    local IFS=":"
    local base_dir
    for base_dir in $SYNC_BASE_DIRS; do
        local find_depth=$((SYNC_SCAN_DEPTH + 1))
        while IFS= read -r -d '' git_dir; do
            local found_dir
            found_dir="$(dirname "$git_dir")"
            local found_name
            found_name="$(basename "$found_dir")"
            if [[ "$found_name" == "$repo_name" ]]; then
                echo "$found_dir"
                return 0
            fi
        done < <(find "$base_dir" -maxdepth "$find_depth" \
            -type d -name ".git" -print0 2>/dev/null)
    done

    return 1
}
