#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: Sync Logic
#
# Core sync workflow, statistics, status display, user confirmation.
# Source this file - do not execute directly.
################################################################################

[[ -n "${_GSA_SYNC_LOADED:-}" ]] && return 0
_GSA_SYNC_LOADED=1

# ── User Confirmation ────────────────────────────────────────────────────────
ask_confirmation() {
    local prompt="$1"

    # Auto-confirm mode
    if [[ "${SYNC_AUTO_CONFIRM:-false}" == "true" ]]; then
        return 0
    fi

    # Non-interactive (piped input)
    if [[ ! -t 0 ]]; then
        log_warn "Non-interactive mode, skipping (use --yes to auto-confirm)"
        return 1
    fi

    local response
    while true; do
        echo -e -n "${YELLOW}${prompt} [y/n/q]: ${NC}" >&2
        read -r response </dev/tty

        case "${response,,}" in
            y | yes) return 0 ;;
            n | no) return 1 ;;
            q | quit)
                echo "" >&2
                log_warn "Aborted by user"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid input. Use 'y' (yes), 'n' (no) or 'q' (quit).${NC}" >&2
                ;;
        esac
    done
}

# ── Build Commit Message ─────────────────────────────────────────────────────
_build_commit_msg() {
    local template="${SYNC_COMMIT_MSG:-chore: auto-sync from {hostname}}"
    local msg="$template"

    # Replace placeholders
    msg="${msg//\{hostname\}/$(hostname)}"
    msg="${msg//\{date\}/$(date +%Y-%m-%d)}"
    msg="${msg//\{repo\}/$(basename "$PWD")}"

    echo "$msg"
}

# ── Ask for Commit Message ───────────────────────────────────────────────────
# Prompts user for a custom commit message, falls back to default if empty.
# In auto-confirm or non-interactive mode, returns the default message.
_ask_commit_msg() {
    local default_msg
    default_msg="$(_build_commit_msg)"

    # Auto-confirm or non-interactive: use default
    if [[ "${SYNC_AUTO_CONFIRM:-false}" == "true" ]] || [[ ! -t 0 ]]; then
        echo "$default_msg"
        return 0
    fi

    echo -e "  ${BLUE}Default message:${NC} ${default_msg}" >&2
    echo -e -n "  ${YELLOW}Commit message (Enter = default): ${NC}" >&2
    local user_msg
    read -r user_msg </dev/tty

    if [[ -z "$user_msg" ]]; then
        echo "$default_msg"
    else
        echo "$user_msg"
    fi
}

# ── Sync Single Repository ──────────────────────────────────────────────────
# Prints result to stdout: clean, synced, skipped, failed
sync_repository() {
    local repo_path="$1"
    local repo_name
    repo_name="$(basename "$repo_path")"
    local branch
    branch="$(get_current_branch "$repo_path")"

    log_info "${BOLD}${repo_name}${NC} (${branch})"

    # Sync tags first (if enabled)
    if [[ "${SYNC_TAGS:-true}" == "true" ]]; then
        if ! sync_tags "$repo_path" 2>/dev/null; then
            log_debug "  Tag sync failed (non-critical)"
        fi
    fi

    local did_something=false

    # 1. Check for uncommitted changes
    if [[ "${NO_COMMIT:-false}" != "true" ]] && has_uncommitted_changes "$repo_path"; then
        log_info "  Uncommitted changes detected"
        show_changed_files "$repo_path" 5

        echo "" >&2
        if ! ask_confirmation "  Commit and push changes?"; then
            log_warn "  Skipped"
            echo "skipped"
            echo "" >&2
            return 0
        fi

        local commit_msg
        commit_msg="$(_ask_commit_msg)"

        log_info "  Committing changes..."
        if commit_changes "$repo_path" "$commit_msg" "${SYNC_COMMIT_BODY:-}"; then
            log_ok "  Changes committed"
            did_something=true
        else
            log_error "  Commit failed"
            echo "failed"
            return 0
        fi
    fi

    # 2. Check for unpulled commits (remote is ahead)
    if [[ "${NO_PULL:-false}" != "true" ]]; then
        if has_unpulled_commits "$repo_path"; then
            local unpulled_count
            unpulled_count=$(count_unpulled "$repo_path")
            log_info "  ${unpulled_count} unpulled commit(s) from remote"

            log_info "  Pulling from remote..."
            if pull_changes "$repo_path" 2>/dev/null; then
                log_ok "  Pulled successfully"
                did_something=true
            else
                log_error "  Pull failed (possible conflicts - resolve manually)"
                echo "failed"
                return 0
            fi
        fi
    fi

    # 3. Check for unpushed commits
    if [[ "${NO_PUSH:-false}" != "true" ]]; then
        if has_unpushed_commits "$repo_path"; then
            local unpushed_count
            unpushed_count=$(count_unpushed "$repo_path")
            log_info "  ${unpushed_count} unpushed commit(s)"

            log_info "  Pushing to remote..."
            if push_commits "$repo_path" 2>/dev/null; then
                log_ok "  Pushed successfully"
                did_something=true
            else
                log_error "  Push failed"
                echo "failed"
                return 0
            fi
        fi
    fi

    # Result
    if [[ "$did_something" == "true" ]]; then
        log_ok "  Synced"
        echo "" >&2
        echo "synced"
    else
        log_ok "  Clean (nothing to sync)"
        echo "" >&2
        echo "clean"
    fi
}

# ── Sync All Repos ───────────────────────────────────────────────────────────
# Returns stats string: "total:clean:synced:skipped:failed"
sync_all() {
    local -n _repos=$1
    local total=0 clean=0 synced=0 skipped=0 failed=0

    for repo_path in "${_repos[@]}"; do
        ((total++))

        local result
        result=$(sync_repository "$repo_path") || true

        case "$result" in
            clean) ((clean++)) ;;
            synced) ((synced++)) ;;
            skipped) ((skipped++)) ;;
            failed) ((failed++)) ;;
            *) ((failed++)) ;; # unexpected result
        esac
    done

    echo "${total}:${clean}:${synced}:${skipped}:${failed}"
}

# ── Status-Only Mode ─────────────────────────────────────────────────────────
show_status() {
    local -n _repos=$1

    # Table header
    printf "${BOLD}%-35s %-15s %-10s %-10s %-10s${NC}\n" \
        "REPOSITORY" "BRANCH" "DIRTY" "UNPUSHED" "UNPULLED" >&2
    printf "%s\n" "$(printf -- '-%.0s' {1..80})" >&2

    local total=0 dirty_count=0

    for repo_path in "${_repos[@]}"; do
        ((total++))
        local name branch dirty unpushed unpulled
        name="$(basename "$repo_path")"
        branch="$(get_current_branch "$repo_path")"
        dirty="--"
        unpushed="--"
        unpulled="--"

        if has_uncommitted_changes "$repo_path"; then
            dirty=$(count_dirty_files "$repo_path")
            ((dirty_count++))
        fi

        if has_unpushed_commits "$repo_path"; then
            unpushed=$(count_unpushed "$repo_path")
        fi

        # Note: has_unpulled_commits does a fetch, might be slow
        # In status mode, skip the fetch for speed
        # Users can use --verbose to include fetch

        printf "%-35s %-15s %-10s %-10s %-10s\n" \
            "$name" "$branch" "$dirty" "$unpushed" "$unpulled" >&2
    done

    echo "" >&2
    log_info "$total repositories, $dirty_count with uncommitted changes"

    # Return stats (no actual sync happened)
    echo "${total}:$((total - dirty_count)):0:0:0"
}

# ── Print Summary ────────────────────────────────────────────────────────────
print_summary() {
    local stats="$1"
    local total clean synced skipped failed

    IFS=':' read -r total clean synced skipped failed <<<"$stats"

    echo "" >&2
    echo -e "${CYAN}========================================${NC}" >&2
    echo -e "${CYAN}Synchronization Complete${NC}" >&2
    echo -e "${CYAN}========================================${NC}" >&2
    echo "" >&2
    echo -e "${BLUE}Statistics:${NC}" >&2
    echo -e "  Total repositories: ${CYAN}${total}${NC}" >&2
    echo -e "  Clean (no changes): ${GREEN}${clean}${NC}" >&2
    echo -e "  Synced:             ${GREEN}${synced}${NC}" >&2
    echo -e "  Skipped:            ${YELLOW}${skipped}${NC}" >&2
    echo -e "  Failed:             ${RED}${failed}${NC}" >&2
    echo "" >&2

    if [[ "$failed" -gt 0 ]]; then
        log_error "Some repositories failed to sync. Check output above."
    else
        log_ok "All repositories synchronized successfully!"
    fi
}
