#!/usr/bin/env bash
# shellcheck shell=bash
################################################################################
# Tests for inventory.sh (YAML parsing and repo verification)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source test helpers
# shellcheck source=tests/test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

# Source required libraries
# shellcheck source=lib/core.sh
source "$PROJECT_DIR/lib/core.sh"
# shellcheck source=lib/config.sh
source "$PROJECT_DIR/lib/config.sh"
# shellcheck source=lib/repo-discovery.sh
source "$PROJECT_DIR/lib/repo-discovery.sh"
# shellcheck source=lib/inventory.sh
source "$PROJECT_DIR/lib/inventory.sh"

# Suppress normal log output during tests
SYNC_VERBOSITY=0

# ── Helper: Create temp inventory file ──────────────────────────────────────
_create_test_inventory() {
    local content="$1"
    local inv_file
    inv_file=$(mktemp --suffix=.yml)
    _TEST_DIRS+=("$inv_file")
    echo "$content" >"$inv_file"
    echo "$inv_file"
}

# ── Tests: parse_inventory ──────────────────────────────────────────────────

echo "=== parse_inventory ==="

# Test: Parse single group
test_parse_single_group() {
    local inv_file
    inv_file=$(_create_test_inventory "all:
  - repo-one
  - repo-two
  - repo-three")

    local -a result=()
    parse_inventory result "$inv_file" "all"

    assert_eq "3" "${#result[@]}" "should find 3 repos in 'all' group"
    assert_eq "repo-one" "${result[0]}" "first repo is repo-one"
    assert_eq "repo-two" "${result[1]}" "second repo is repo-two"
    assert_eq "repo-three" "${result[2]}" "third repo is repo-three"
}
test_parse_single_group

# Test: Parse specific group ignoring others
test_parse_specific_group() {
    local inv_file
    inv_file=$(_create_test_inventory "all:
  - shared-repo
work:
  - work-repo
  - office-tool
personal:
  - my-blog")

    local -a result=()
    parse_inventory result "$inv_file" "work"

    assert_eq "2" "${#result[@]}" "should find 2 repos in 'work' group"
    assert_eq "work-repo" "${result[0]}" "first repo is work-repo"
    assert_eq "office-tool" "${result[1]}" "second repo is office-tool"
}
test_parse_specific_group

# Test: Parse multiple groups
test_parse_multiple_groups() {
    local inv_file
    inv_file=$(_create_test_inventory "all:
  - shared-repo
work:
  - work-repo
personal:
  - my-blog")

    local -a result=()
    parse_inventory result "$inv_file" "all,work"

    assert_eq "2" "${#result[@]}" "should find 2 repos in 'all' + 'work' groups"
    assert_eq "shared-repo" "${result[0]}" "first repo is shared-repo"
    assert_eq "work-repo" "${result[1]}" "second repo is work-repo"
}
test_parse_multiple_groups

# Test: Skip comments and empty lines
test_skip_comments() {
    local inv_file
    inv_file=$(_create_test_inventory "# This is a comment
all:
  # Another comment
  - repo-one

  - repo-two")

    local -a result=()
    parse_inventory result "$inv_file" "all"

    assert_eq "2" "${#result[@]}" "should find 2 repos (skipping comments/blanks)"
}
test_skip_comments

# Test: Empty group returns nothing
test_empty_group() {
    local inv_file
    inv_file=$(_create_test_inventory "all:
  - repo-one
work:")

    local -a result=()
    parse_inventory result "$inv_file" "work"

    assert_eq "0" "${#result[@]}" "empty group should return 0 repos"
}
test_empty_group

# Test: Non-existent group returns nothing
test_nonexistent_group() {
    local inv_file
    inv_file=$(_create_test_inventory "all:
  - repo-one")

    local -a result=()
    parse_inventory result "$inv_file" "nonexistent"

    assert_eq "0" "${#result[@]}" "non-existent group should return 0 repos"
}
test_nonexistent_group

# Test: Missing inventory file triggers die
test_missing_file() {
    local exit_code=0
    # Run in subshell because die() calls exit
    (
        local -a result=()
        parse_inventory result "/tmp/does-not-exist-$$.yml" "all"
    ) 2>/dev/null || exit_code=$?

    assert_ne "0" "$exit_code" "should fail for missing inventory file"
}
test_missing_file

# Test: Parse entries with clone URLs (key-value format)
test_parse_with_urls() {
    local inv_file
    inv_file=$(_create_test_inventory "all:
  - repo-one
  - repo-two: https://github.com/org/repo-two
  - repo-three: https://gitlab.com/other/repo-three.git")

    local -a result=()
    _GSA_REPO_URLS=()
    parse_inventory result "$inv_file" "all"

    assert_eq "3" "${#result[@]}" "should find 3 repos (plain + URL entries)"
    assert_eq "repo-one" "${result[0]}" "first repo is plain name"
    assert_eq "repo-two" "${result[1]}" "second repo is name from key-value"
    assert_eq "repo-three" "${result[2]}" "third repo is name from key-value"

    assert_eq "https://github.com/org/repo-two" "${_GSA_REPO_URLS[repo-two]}" \
        "URL stored for repo-two"
    assert_eq "https://gitlab.com/other/repo-three.git" "${_GSA_REPO_URLS[repo-three]}" \
        "URL stored for repo-three"
    assert_eq "" "${_GSA_REPO_URLS[repo-one]:-}" \
        "no URL stored for plain repo-one"
}
test_parse_with_urls

# Test: Mixed plain and URL entries across groups
test_parse_urls_filtered_by_group() {
    local inv_file
    inv_file=$(_create_test_inventory "public:
  - my-repo
  - external-repo: https://github.com/other/external-repo
private:
  - secret-repo")

    local -a result=()
    _GSA_REPO_URLS=()
    parse_inventory result "$inv_file" "public"

    assert_eq "2" "${#result[@]}" "should find 2 repos in public group"
    assert_eq "my-repo" "${result[0]}" "first is plain repo"
    assert_eq "external-repo" "${result[1]}" "second is URL repo (name only)"
    assert_eq "https://github.com/other/external-repo" \
        "${_GSA_REPO_URLS[external-repo]}" "URL stored for external-repo"
}
test_parse_urls_filtered_by_group

# ── Tests: list_inventory_groups ────────────────────────────────────────────

echo ""
echo "=== list_inventory_groups ==="

test_list_groups() {
    local inv_file
    inv_file=$(_create_test_inventory "all:
  - repo-one
work:
  - work-repo
personal:
  - my-blog")

    local groups
    groups=$(list_inventory_groups "$inv_file")

    assert_contains "$groups" "all" "should list 'all' group"
    assert_contains "$groups" "work" "should list 'work' group"
    assert_contains "$groups" "personal" "should list 'personal' group"
}
test_list_groups

# ── Tests: verify_inventory ─────────────────────────────────────────────────

echo ""
echo "=== verify_inventory ==="

test_verify_all_found() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    # Create mock repos
    create_single_mock_repo "$test_dir" "repo-alpha"
    create_single_mock_repo "$test_dir" "repo-beta"

    # Set config to scan test dir
    SYNC_BASE_DIRS="$test_dir"
    SYNC_SCAN_DEPTH=2

    local -a expected_repos=("repo-alpha" "repo-beta")
    local stats
    stats=$(verify_inventory expected_repos 2>/dev/null)

    local exp found miss
    IFS=':' read -r exp found miss <<<"$stats"

    assert_eq "2" "$exp" "expected count is 2"
    assert_eq "2" "$found" "found count is 2"
    assert_eq "0" "$miss" "missing count is 0"
}
test_verify_all_found

test_verify_with_missing() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    # Create only one of the expected repos
    create_single_mock_repo "$test_dir" "repo-exists"

    SYNC_BASE_DIRS="$test_dir"
    SYNC_SCAN_DEPTH=2

    local -a expected_repos=("repo-exists" "repo-missing" "repo-gone")
    local stats
    stats=$(verify_inventory expected_repos 2>/dev/null)

    local exp found miss
    IFS=':' read -r exp found miss <<<"$stats"

    assert_eq "3" "$exp" "expected count is 3"
    assert_eq "1" "$found" "found count is 1"
    assert_eq "2" "$miss" "missing count is 2"
}
test_verify_with_missing

test_verify_shows_clone_url_hint() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    SYNC_BASE_DIRS="$test_dir"
    SYNC_SCAN_DEPTH=2

    # Set up URL for missing repo
    _GSA_REPO_URLS=([repo-external]="https://github.com/org/repo-external")

    local -a expected_repos=("repo-external")
    local output
    output=$(verify_inventory expected_repos 2>&1 >/dev/null) || true

    assert_contains "$output" "git clone https://github.com/org/repo-external" \
        "should show git clone with URL for missing repo"
}
test_verify_shows_clone_url_hint

test_verify_shows_gh_clone_hint() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    SYNC_BASE_DIRS="$test_dir"
    SYNC_SCAN_DEPTH=2

    # Override _get_github_username to return test user
    _get_github_username() { echo "testuser"; }

    _GSA_REPO_URLS=()
    local -a expected_repos=("my-own-repo")
    local output
    output=$(verify_inventory expected_repos 2>&1 >/dev/null) || true

    assert_contains "$output" "gh repo clone testuser/my-own-repo" \
        "should show gh repo clone for repos without URL"

    # Restore original function
    unset -f _get_github_username
}
test_verify_shows_gh_clone_hint

test_verify_empty_list() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    SYNC_BASE_DIRS="$test_dir"
    SYNC_SCAN_DEPTH=2

    local -a expected_repos=()
    local stats
    stats=$(verify_inventory expected_repos 2>/dev/null)

    local exp found miss
    IFS=':' read -r exp found miss <<<"$stats"

    assert_eq "0" "$exp" "expected count is 0"
    assert_eq "0" "$found" "found count is 0"
    assert_eq "0" "$miss" "missing count is 0"
}
test_verify_empty_list

# ── Tests: find_untracked_repos ────────────────────────────────────────────

echo ""
echo "=== find_untracked_repos ==="

test_no_untracked() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    # Create repos that ARE in inventory
    create_single_mock_repo "$test_dir" "repo-alpha"
    create_single_mock_repo "$test_dir" "repo-beta"

    SYNC_BASE_DIRS="$test_dir"
    SYNC_SCAN_DEPTH=2

    local -a inv_repos=("repo-alpha" "repo-beta")
    local -a untracked=()
    find_untracked_repos untracked inv_repos

    assert_eq "0" "${#untracked[@]}" "no untracked repos when all are in inventory"
}
test_no_untracked

test_finds_untracked() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    # Create 3 repos, only 1 in inventory
    create_single_mock_repo "$test_dir" "repo-listed"
    create_single_mock_repo "$test_dir" "repo-extra-one"
    create_single_mock_repo "$test_dir" "repo-extra-two"

    SYNC_BASE_DIRS="$test_dir"
    SYNC_SCAN_DEPTH=2

    local -a inv_repos=("repo-listed")
    local -a untracked=()
    find_untracked_repos untracked inv_repos

    assert_eq "2" "${#untracked[@]}" "should find 2 untracked repos"
}
test_finds_untracked

test_untracked_empty_inventory() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    create_single_mock_repo "$test_dir" "repo-one"
    create_single_mock_repo "$test_dir" "repo-two"

    SYNC_BASE_DIRS="$test_dir"
    SYNC_SCAN_DEPTH=2

    local -a inv_repos=()
    local -a untracked=()
    find_untracked_repos untracked inv_repos

    assert_eq "2" "${#untracked[@]}" "all repos untracked when inventory is empty"
}
test_untracked_empty_inventory

# ── Tests: offer_cleanup_untracked ─────────────────────────────────────────

echo ""
echo "=== offer_cleanup_untracked ==="

test_cleanup_empty_list() {
    local -a empty=()
    local stats
    stats=$(offer_cleanup_untracked empty 2>/dev/null)

    assert_eq "0:0:0" "$stats" "empty list returns 0:0:0"
}
test_cleanup_empty_list

test_cleanup_dry_run() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    create_single_mock_repo "$test_dir" "repo-to-keep"

    DRY_RUN=true
    local -a repos=("$test_dir/repo-to-keep")
    local stats
    stats=$(offer_cleanup_untracked repos 2>/dev/null)
    DRY_RUN=false

    # Dry-run should keep all repos
    assert_eq "1:0:1" "$stats" "dry-run keeps all repos"
    assert_eq "true" "$([[ -d "$test_dir/repo-to-keep" ]] && echo true || echo false)" \
        "repo dir still exists after dry-run"
}
test_cleanup_dry_run

# ── Cleanup & Results ───────────────────────────────────────────────────────

cleanup_all
print_test_results
