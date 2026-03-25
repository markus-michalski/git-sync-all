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

# ── Cleanup & Results ───────────────────────────────────────────────────────

cleanup_all
print_test_results
