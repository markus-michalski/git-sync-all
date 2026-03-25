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

        # List item: "  - reponame"
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.+)$ ]]; then
            local repo_name="${BASH_REMATCH[1]}"
            # Trim trailing whitespace
            repo_name="${repo_name%% }"
            repo_name="${repo_name%%$'\r'}"

            # Check if current group matches filter
            if [[ -n "$current_group" ]] && [[ -n "${group_filter[$current_group]+x}" ]]; then
                _inv_result+=("$repo_name")
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
        log_info "Missing repositories:"
        local m
        for m in "${missing_repos[@]}"; do
            echo -e "  ${RED}${m}${NC}" >&2
        done
        echo "" >&2
        log_info "Clone missing repos into one of: ${SYNC_BASE_DIRS//:/, }"
    fi

    echo "${expected}:${found}:${missing}"
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
