#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: Sync Logic
#
# Core sync workflow, statistics, status display, user confirmation.
# Conflict detection, stash workflow, and automatic recovery.
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

# ── Conflict Action Menu ────────────────────────────────────────────────────
# Shows extended menu when both local dirty + remote changes exist.
# Returns: commit, stash, skip, quit
_ask_conflict_action() {
    local has_conflicts="$1"

    # Auto-confirm mode: use conflict strategy
    if [[ "${SYNC_AUTO_CONFIRM:-false}" == "true" ]]; then
        if [[ "$has_conflicts" == "true" ]]; then
            local strategy="${SYNC_CONFLICT_STRATEGY:-skip}"
            case "$strategy" in
                skip)
                    log_warn "  Auto-mode: skipping (potential conflicts detected)"
                    echo "skip"
                    ;;
                stash)
                    log_info "  Auto-mode: using stash workflow"
                    echo "stash"
                    ;;
                commit)
                    log_warn "  Auto-mode: committing despite potential conflicts"
                    echo "commit"
                    ;;
                *)
                    echo "skip"
                    ;;
            esac
        else
            # No conflicts detected → safe to commit
            echo "commit"
        fi
        return 0
    fi

    # Non-interactive
    if [[ ! -t 0 ]]; then
        log_warn "  Non-interactive mode, skipping"
        echo "skip"
        return 0
    fi

    # Interactive menu
    echo "" >&2
    if [[ "$has_conflicts" == "true" ]]; then
        echo -e "  ${RED}Potential conflicts in files changed both locally and on remote!${NC}" >&2
    fi
    echo -e "  ${YELLOW}[c]${NC} Commit + sync (may require manual conflict resolution)" >&2
    echo -e "  ${YELLOW}[s]${NC} Stash + pull + restore (keep changes uncommitted)" >&2
    echo -e "  ${YELLOW}[k]${NC} Skip this repo" >&2
    echo -e "  ${YELLOW}[q]${NC} Quit" >&2

    local response
    while true; do
        echo -e -n "  ${YELLOW}Action [c/s/k/q]: ${NC}" >&2
        read -r response </dev/tty
        case "${response,,}" in
            c)
                echo "commit"
                return 0
                ;;
            s)
                echo "stash"
                return 0
                ;;
            k)
                echo "skip"
                return 0
                ;;
            q)
                echo "quit"
                return 0
                ;;
            *) echo -e "  ${RED}Invalid. Use c, s, k, or q.${NC}" >&2 ;;
        esac
    done
}

# ── Helper: Commit changes with message prompt ──────────────────────────────
_do_commit() {
    local repo_path="$1"
    local commit_msg
    commit_msg="$(_ask_commit_msg)"

    log_info "  Committing changes..."
    if commit_changes "$repo_path" "$commit_msg" "${SYNC_COMMIT_BODY:-}" >/dev/null; then
        log_ok "  Changes committed"
        return 0
    else
        log_error "  Commit failed"
        return 1
    fi
}

# ── Helper: Stash → Pull → Stash Pop workflow ───────────────────────────────
_stash_pull_pop() {
    local repo_path="$1"

    log_info "  Stashing changes..."
    if ! stash_changes "$repo_path" >/dev/null 2>/dev/null; then
        log_error "  Stash failed"
        return 1
    fi
    log_ok "  Changes stashed"

    log_info "  Pulling from remote..."
    local pull_stderr
    pull_stderr=$(mktemp)
    if ! pull_changes "$repo_path" >/dev/null 2>"$pull_stderr"; then
        log_error "  Pull failed"
        [[ -s "$pull_stderr" ]] && sed 's/^/    /' "$pull_stderr" >&2
        rm -f "$pull_stderr"
        _handle_pull_failure "$repo_path"
        # Restore stash
        log_info "  Restoring stashed changes..."
        if stash_pop "$repo_path" >/dev/null 2>/dev/null; then
            log_ok "  Stash restored"
        else
            log_warn "  Stash restore failed (changes preserved in 'git stash list')"
        fi
        return 1
    fi
    rm -f "$pull_stderr"
    log_ok "  Pulled successfully"

    log_info "  Restoring stashed changes..."
    local pop_stderr
    pop_stderr=$(mktemp)
    if stash_pop "$repo_path" >/dev/null 2>"$pop_stderr"; then
        rm -f "$pop_stderr"
        log_ok "  Stash restored"
        return 0
    else
        log_warn "  Stash pop has conflicts - resolve manually"
        [[ -s "$pop_stderr" ]] && sed 's/^/    /' "$pop_stderr" >&2
        rm -f "$pop_stderr"
        log_info "  Hint: resolve conflicts, then 'git stash drop'"
        return 1
    fi
}

# ── Helper: Handle pull failure (abort rebase/merge) ────────────────────────
_handle_pull_failure() {
    local repo_path="$1"

    if is_rebase_in_progress "$repo_path"; then
        log_warn "  Aborting rebase to restore clean state..."
        if abort_rebase "$repo_path" >/dev/null 2>/dev/null; then
            log_ok "  Rebase aborted, repo restored"
        else
            log_error "  Failed to abort rebase! Run: cd $repo_path && git rebase --abort"
        fi
    elif is_merge_in_progress "$repo_path"; then
        log_warn "  Aborting merge to restore clean state..."
        if abort_merge "$repo_path" >/dev/null 2>/dev/null; then
            log_ok "  Merge aborted, repo restored"
        else
            log_error "  Failed to abort merge! Run: cd $repo_path && git merge --abort"
        fi
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
        if ! sync_tags "$repo_path" >/dev/null 2>/dev/null; then
            log_debug "  Tag sync failed (non-critical)"
        fi
    fi

    local did_something=false
    local already_pulled=false
    local is_dirty=false
    local has_remote=false

    # ── 1. Assess current state ──────────────────────────────────────────────

    if has_uncommitted_changes "$repo_path"; then
        is_dirty=true
    fi

    if [[ "${NO_PULL:-false}" != "true" ]]; then
        fetch_remote "$repo_path" 2>/dev/null || true
        if has_unpulled_commits_local "$repo_path"; then
            has_remote=true
        fi
    fi

    # ── 2. Handle uncommitted changes ────────────────────────────────────────

    if [[ "$is_dirty" == "true" ]]; then

        if [[ "${NO_COMMIT:-false}" == "true" ]]; then
            # --no-commit mode: auto-stash if remote has updates
            if [[ "$has_remote" == "true" ]]; then
                log_info "  Uncommitted changes + remote updates (--no-commit mode)"
                log_info "  Auto-stashing for pull..."
                if _stash_pull_pop "$repo_path"; then
                    did_something=true
                    already_pulled=true
                else
                    echo "failed"
                    echo "" >&2
                    return 0
                fi
            else
                log_debug "  Uncommitted changes (skipping commit per --no-commit)"
            fi

        elif [[ "$has_remote" == "true" ]]; then
            # Dirty + remote changes → conflict detection + extended menu
            log_info "  Uncommitted changes detected"
            show_changed_files "$repo_path" 5

            local unpulled_count
            unpulled_count=$(count_unpulled "$repo_path")
            log_info "  Remote has ${unpulled_count} new commit(s)"

            local conflict_files
            conflict_files=$(detect_potential_conflicts "$repo_path")
            if [[ -n "$conflict_files" ]]; then
                echo "" >&2
                log_warn "  Potential conflicts in:"
                while IFS= read -r cfile; do
                    echo -e "    ${RED}${cfile}${NC}" >&2
                done <<<"$conflict_files"
            fi

            local action
            action=$(_ask_conflict_action "$([[ -n "$conflict_files" ]] && echo true || echo false)")

            case "$action" in
                commit)
                    if ! _do_commit "$repo_path"; then
                        echo "failed"
                        echo "" >&2
                        return 0
                    fi
                    did_something=true
                    ;;
                stash)
                    if _stash_pull_pop "$repo_path"; then
                        did_something=true
                        already_pulled=true
                    else
                        echo "failed"
                        echo "" >&2
                        return 0
                    fi
                    ;;
                skip)
                    log_warn "  Skipped"
                    echo "skipped"
                    echo "" >&2
                    return 0
                    ;;
                quit)
                    echo "" >&2
                    log_warn "Aborted by user"
                    exit 0
                    ;;
            esac

        else
            # Dirty, no remote changes → simple commit prompt
            log_info "  Uncommitted changes detected"
            show_changed_files "$repo_path" 5

            echo "" >&2
            if ! ask_confirmation "  Commit and push changes?"; then
                log_warn "  Skipped"
                echo "skipped"
                echo "" >&2
                return 0
            fi

            if ! _do_commit "$repo_path"; then
                echo "failed"
                echo "" >&2
                return 0
            fi
            did_something=true
        fi
    fi

    # ── 3. Pull from remote (if not already done via stash workflow) ─────────

    if [[ "$already_pulled" == "false" ]] && [[ "${NO_PULL:-false}" != "true" ]]; then
        # Use cached state if available, otherwise check fresh
        if [[ "$has_remote" == "true" ]] || has_unpulled_commits_local "$repo_path"; then
            local unpulled_count
            unpulled_count=$(count_unpulled "$repo_path")
            log_info "  ${unpulled_count} unpulled commit(s) from remote"

            log_info "  Pulling from remote..."
            local pull_stderr
            pull_stderr=$(mktemp)
            if pull_changes "$repo_path" >/dev/null 2>"$pull_stderr"; then
                rm -f "$pull_stderr"
                log_ok "  Pulled successfully"
                did_something=true
            else
                log_error "  Pull failed"
                [[ -s "$pull_stderr" ]] && sed 's/^/    /' "$pull_stderr" >&2
                rm -f "$pull_stderr"
                _handle_pull_failure "$repo_path"
                echo "failed"
                echo "" >&2
                return 0
            fi
        fi
    fi

    # ── 4. Push to remote ────────────────────────────────────────────────────

    if [[ "${NO_PUSH:-false}" != "true" ]]; then
        if has_unpushed_commits "$repo_path"; then
            local unpushed_count
            unpushed_count=$(count_unpushed "$repo_path")
            log_info "  ${unpushed_count} unpushed commit(s)"

            log_info "  Pushing to remote..."
            if push_commits "$repo_path" >/dev/null 2>/dev/null; then
                log_ok "  Pushed successfully"
                did_something=true
            else
                log_error "  Push failed"
                echo "failed"
                echo "" >&2
                return 0
            fi
        fi
    fi

    # ── Result ───────────────────────────────────────────────────────────────

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
