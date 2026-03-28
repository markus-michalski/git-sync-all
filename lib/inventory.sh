#!/bin/bash
# shellcheck shell=bash
################################################################################
# git-sync-all: Repository Inventory
#
# Parse repos.yml inventory file, verify repos exist on disk.
# Source this file - do not execute directly.
################################################################################

[[ -n "${_GSA_INVENTORY_LOADED:-}" ]] && return 0
_GSA_INVENTORY_LOADED=1

# Global associative array: repo name → clone URL (populated by parse_inventory)
declare -gA _GSA_REPO_URLS=()

# ── Inventory File Resolution ────────────────────────────────────────────────
_resolve_inventory_path() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/git-sync-all/repos.yml"
}

# ── Simple YAML Parser ──────────────────────────────────────────────────────
# Parses our simplified YAML format (groups with flat lists).
# Populates the named array reference with repo names for the given groups.
#
# Args:
#   $1 - nameref: output array for repo names
#   $2 - inventory file path
#   $3 - comma-separated group names (empty = "all")
parse_inventory() {
    local -n _inv_result=$1
    local inv_file="$2"
    local groups="${3:-all}"
    _inv_result=()

    if [[ ! -f "$inv_file" ]]; then
        die "Inventory file not found: $inv_file"
    fi

    # Build group filter set
    local -A group_filter=()
    local IFS=","
    local g
    for g in $groups; do
        # Trim whitespace
        g="${g## }"
        g="${g%% }"
        group_filter["$g"]=1
    done
    unset IFS

    local current_group=""
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Group header: "groupname:"
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
            current_group="${BASH_REMATCH[1]}"
            continue
        fi

        # List item: "  - reponame" or "  - reponame: https://clone-url"
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.+)$ ]]; then
            local raw_entry="${BASH_REMATCH[1]}"
            # Trim trailing whitespace and carriage returns
            raw_entry="${raw_entry%% }"
            raw_entry="${raw_entry%%$'\r'}"

            local repo_name=""
            local clone_url=""

            # Check for key-value format: "name: https://..."
            if [[ "$raw_entry" =~ ^([a-zA-Z0-9._-]+):[[:space:]]+(https?://.+)$ ]]; then
                repo_name="${BASH_REMATCH[1]}"
                clone_url="${BASH_REMATCH[2]}"
            else
                repo_name="$raw_entry"
            fi

            # Check if current group matches filter
            if [[ -n "$current_group" ]] && [[ -n "${group_filter[$current_group]+x}" ]]; then
                _inv_result+=("$repo_name")
                if [[ -n "$clone_url" ]]; then
                    _GSA_REPO_URLS["$repo_name"]="$clone_url"
                fi
            fi
        fi
    done <"$inv_file"

    log_debug "Parsed ${#_inv_result[@]} repos from inventory (groups: $groups)"
}

# ── List Available Groups ────────────────────────────────────────────────────
# Prints all group names found in the inventory file.
list_inventory_groups() {
    local inv_file="$1"

    if [[ ! -f "$inv_file" ]]; then
        die "Inventory file not found: $inv_file"
    fi

    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done <"$inv_file"
}

# ── Get GitHub Username ─────────────────────────────────────────────────────
# Resolves the GitHub username for clone hints.
# Priority: SYNC_GITHUB_USER env/config > gh CLI > empty string
_get_github_username() {
    if [[ -n "${SYNC_GITHUB_USER:-}" ]]; then
        echo "$SYNC_GITHUB_USER"
        return 0
    fi

    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        local user
        user=$(gh api user -q .login 2>/dev/null) || true
        if [[ -n "$user" ]]; then
            echo "$user"
            return 0
        fi
    fi

    echo ""
}

# ── Verify Repos Exist ──────────────────────────────────────────────────────
# Checks that all repos from inventory exist as directories containing .git.
# Searches across all SYNC_BASE_DIRS.
#
# Returns stats string: "expected:found:missing"
# Prints missing repos to stderr.
verify_inventory() {
    local -n _verify_repos=$1
    local expected=${#_verify_repos[@]}
    local found=0
    local missing=0
    local -a missing_repos=()

    # Build lookup of discovered repo names from all base dirs
    local -A existing_repos=()
    local IFS=":"
    local base_dir
    for base_dir in $SYNC_BASE_DIRS; do
        local find_depth=$((SYNC_SCAN_DEPTH + 1))
        while IFS= read -r -d '' git_dir; do
            local repo_dir
            repo_dir="$(dirname "$git_dir")"
            local repo_name
            repo_name="$(basename "$repo_dir")"
            existing_repos["$repo_name"]="$repo_dir"
        done < <(find "$base_dir" -maxdepth "$find_depth" \
            -type d -name ".git" -print0 2>/dev/null)
    done
    unset IFS

    # Check each expected repo
    local repo
    for repo in "${_verify_repos[@]}"; do
        if [[ -n "${existing_repos[$repo]+x}" ]]; then
            ((found++))
            log_ok "  ${repo} → ${existing_repos[$repo]}"
        else
            ((missing++))
            missing_repos+=("$repo")
            log_error "  ${repo} → NOT FOUND"
        fi
    done

    # Summary
    echo "" >&2
    if [[ "$missing" -eq 0 ]]; then
        log_ok "All ${expected} repositories found"
    else
        log_warn "${found}/${expected} found, ${missing} missing"
        echo "" >&2

        # Resolve GitHub username once for clone hints
        local gh_user=""
        gh_user=$(_get_github_username)

        local first_base_dir="${SYNC_BASE_DIRS%%:*}"

        log_info "Missing repositories:"
        local m
        for m in "${missing_repos[@]}"; do
            if [[ -n "${_GSA_REPO_URLS[$m]+x}" ]]; then
                # Repo has explicit clone URL
                echo -e "  ${RED}${m}${NC}" >&2
                echo -e "    git clone ${_GSA_REPO_URLS[$m]} ${first_base_dir}/${m}" >&2
            elif [[ -n "$gh_user" ]]; then
                # No URL → assume GitHub repo owned by user
                echo -e "  ${RED}${m}${NC}" >&2
                echo -e "    gh repo clone ${gh_user}/${m} ${first_base_dir}/${m}" >&2
            else
                # No URL, no GitHub user → generic hint
                echo -e "  ${RED}${m}${NC}" >&2
            fi
        done
        echo "" >&2

        if [[ -z "$gh_user" ]]; then
            log_info "Clone missing repos into one of: ${SYNC_BASE_DIRS//:/, }"
        fi
        log_info "Tip: Add clone URLs in repos.yml for external repos (name: https://...)"
    fi

    echo "${expected}:${found}:${missing}"
}

# ── Find Untracked Repos ───────────────────────────────────────────────────
# Finds repos on disk that are NOT listed in the inventory.
# Populates the named array reference with paths of untracked repos.
#
# Args:
#   $1 - nameref: output array for untracked repo paths
#   $2 - nameref: inventory repo names array
find_untracked_repos() {
    local -n _untracked_result=$1
    local -n _inv_repos=$2
    _untracked_result=()

    # Build lookup of inventory repo names
    local -A inv_lookup=()
    local repo
    for repo in "${_inv_repos[@]}"; do
        inv_lookup["$repo"]=1
    done

    # Discover all repos on disk
    local -A existing_repos=()
    local IFS=":"
    local base_dir
    for base_dir in $SYNC_BASE_DIRS; do
        local find_depth=$((SYNC_SCAN_DEPTH + 1))
        while IFS= read -r -d '' git_dir; do
            local repo_dir
            repo_dir="$(dirname "$git_dir")"
            local repo_name
            repo_name="$(basename "$repo_dir")"
            existing_repos["$repo_name"]="$repo_dir"
        done < <(find "$base_dir" -maxdepth "$find_depth" \
            -type d -name ".git" -print0 2>/dev/null)
    done
    unset IFS

    # Find repos on disk not in inventory
    local name
    for name in "${!existing_repos[@]}"; do
        if [[ -z "${inv_lookup[$name]+x}" ]]; then
            _untracked_result+=("${existing_repos[$name]}")
        fi
    done

    log_debug "Found ${#_untracked_result[@]} untracked repos"
}

# ── Offer Cleanup of Untracked Repos ──────────────────────────────────────
# Lists untracked repos and asks user whether to remove each one.
# Always requires explicit confirmation per repo (--yes is ignored for safety).
#
# Args:
#   $1 - nameref: array of untracked repo paths
#
# Returns: "total:removed:kept" stats string
offer_cleanup_untracked() {
    local -n _cleanup_repos=$1
    local total=${#_cleanup_repos[@]}
    local removed=0
    local kept=0

    if [[ "$total" -eq 0 ]]; then
        echo "0:0:0"
        return 0
    fi

    echo "" >&2
    log_warn "${total} repo(s) on disk but NOT in inventory:"
    local path
    for path in "${_cleanup_repos[@]}"; do
        echo -e "  ${YELLOW}$(basename "$path")${NC} → ${path}" >&2
    done
    echo "" >&2

    # Non-interactive: just report, don't offer deletion
    if [[ ! -t 0 ]]; then
        log_info "Non-interactive mode: skipping cleanup prompts"
        echo "${total}:0:${total}"
        return 0
    fi

    for path in "${_cleanup_repos[@]}"; do
        local name
        name="$(basename "$path")"

        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_dry "Would ask to remove: ${name} (${path})"
            ((kept++))
            continue
        fi

        local response
        while true; do
            echo -e -n "${YELLOW}Remove ${BOLD}${name}${NC}${YELLOW} from disk? (${path}) [y/n/q]: ${NC}" >&2
            read -r response </dev/tty

            case "${response,,}" in
                y | yes)
                    rm -rf "$path"
                    log_ok "  Removed: ${name}"
                    ((removed++))
                    break
                    ;;
                n | no)
                    log_info "  Kept: ${name}"
                    ((kept++))
                    break
                    ;;
                q | quit)
                    echo "" >&2
                    log_warn "Cleanup aborted by user"
                    ((kept += total - removed - kept))
                    echo "${total}:${removed}:${kept}"
                    return 0
                    ;;
                *)
                    echo -e "${RED}Invalid input. Use 'y' (yes), 'n' (no) or 'q' (quit).${NC}" >&2
                    ;;
            esac
        done
    done

    echo "" >&2
    if [[ "$removed" -gt 0 ]]; then
        log_ok "${removed} repo(s) removed, ${kept} kept"
    else
        log_info "No repos removed"
    fi

    echo "${total}:${removed}:${kept}"
}

# ── Init Inventory ──────────────────────────────────────────────────────────
# Create inventory file from example or generate from discovered repos.
init_inventory() {
    local inv_file
    inv_file="$(_resolve_inventory_path)"
    local inv_dir
    inv_dir="$(dirname "$inv_file")"

    if [[ -f "$inv_file" ]]; then
        log_warn "Inventory already exists: $inv_file"
        log_info "Edit with: \${EDITOR:-nano} $inv_file"
        return 0
    fi

    mkdir -p "$inv_dir"

    # Find example file relative to script
    local example_inv="${GSA_LIB_DIR}/../config/repos.yml.example"
    if [[ -f "$example_inv" ]]; then
        cp "$example_inv" "$inv_file"
        log_ok "Inventory created: $inv_file"
    else
        # Generate from currently discovered repos
        {
            echo "# git-sync-all repository inventory"
            echo "# Generated on $(date +%Y-%m-%d) from discovered repositories"
            echo ""
            echo "all:"

            local -a repos=()
            discover_repos repos
            local repo
            for repo in "${repos[@]}"; do
                echo "  - $(basename "$repo")"
            done
        } >"$inv_file"
        log_ok "Inventory generated from discovered repos: $inv_file"
    fi

    # Open in editor if interactive
    if [[ -t 0 ]]; then
        local editor="${EDITOR:-${VISUAL:-nano}}"
        log_info "Opening inventory with $editor..."
        "$editor" "$inv_file"
    fi
}
