#!/usr/bin/env bash
# shellcheck shell=bash
################################################################################
# Tests: Configuration Loading & Validation
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/lib/core.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Configuration Tests ==="

# ── Test: defaults are set ───────────────────────────────────────────────────
echo ""
echo "-- defaults --"

# Clear ALL config vars first (including SYNC_VERBOSITY)
unset SYNC_BASE_DIRS SYNC_SCAN_DEPTH SYNC_PULL_STRATEGY SYNC_REMOTE \
    SYNC_VERBOSITY SYNC_AUTO_CONFIRM SYNC_TAGS SYNC_COLOR \
    SYNC_EXCLUDE SYNC_INCLUDE SYNC_COMMIT_MSG SYNC_COMMIT_BODY 2>/dev/null || true

_set_defaults
assert_eq "$HOME/projekte" "$SYNC_BASE_DIRS" "SYNC_BASE_DIRS default" || true
assert_eq "3" "$SYNC_SCAN_DEPTH" "SYNC_SCAN_DEPTH default" || true
assert_eq "rebase" "$SYNC_PULL_STRATEGY" "SYNC_PULL_STRATEGY default" || true
assert_eq "origin" "$SYNC_REMOTE" "SYNC_REMOTE default" || true
assert_eq "1" "$SYNC_VERBOSITY" "SYNC_VERBOSITY default" || true
assert_eq "false" "$SYNC_AUTO_CONFIRM" "SYNC_AUTO_CONFIRM default" || true
assert_eq "true" "$SYNC_TAGS" "SYNC_TAGS default" || true
assert_eq "auto" "$SYNC_COLOR" "SYNC_COLOR default" || true

# Suppress output for remaining tests
SYNC_VERBOSITY=0

# ── Test: config file overrides defaults ─────────────────────────────────────
echo ""
echo "-- config file override --"

test_dir=$(mktemp -d)
_TEST_DIRS+=("$test_dir")

# Create a test config
mkdir -p "$test_dir/repos"
cat >"$test_dir/config.conf" <<EOF
SYNC_BASE_DIRS="$test_dir/repos"
SYNC_SCAN_DEPTH=5
SYNC_PULL_STRATEGY="merge"
SYNC_REMOTE="upstream"
SYNC_VERBOSITY=0
EOF

# Reset and load
unset SYNC_BASE_DIRS SYNC_SCAN_DEPTH SYNC_PULL_STRATEGY SYNC_REMOTE SYNC_VERBOSITY 2>/dev/null || true
load_config "$test_dir/config.conf"

assert_eq "$test_dir/repos" "$SYNC_BASE_DIRS" "config overrides SYNC_BASE_DIRS" || true
assert_eq "5" "$SYNC_SCAN_DEPTH" "config overrides SYNC_SCAN_DEPTH" || true
assert_eq "merge" "$SYNC_PULL_STRATEGY" "config overrides SYNC_PULL_STRATEGY" || true
assert_eq "upstream" "$SYNC_REMOTE" "config overrides SYNC_REMOTE" || true

# ── Test: validation catches bad pull strategy ───────────────────────────────
echo ""
echo "-- validation: bad pull strategy --"

# Run in subshell because validate_config calls die() on failure
output=$(bash -c "
    source '$PROJECT_DIR/lib/core.sh'
    source '$PROJECT_DIR/lib/config.sh'
    SYNC_BASE_DIRS='$test_dir/repos'
    SYNC_SCAN_DEPTH=3
    SYNC_PULL_STRATEGY='invalid'
    SYNC_VERBOSITY=0
    validate_config
" 2>&1 || true)
assert_contains "$output" "SYNC_PULL_STRATEGY" "validation catches invalid pull strategy" || true

# ── Test: validation catches bad verbosity ───────────────────────────────────
echo ""
echo "-- validation: bad verbosity --"

output=$(bash -c "
    source '$PROJECT_DIR/lib/core.sh'
    source '$PROJECT_DIR/lib/config.sh'
    SYNC_BASE_DIRS='$test_dir/repos'
    SYNC_SCAN_DEPTH=3
    SYNC_PULL_STRATEGY='rebase'
    SYNC_VERBOSITY=5
    validate_config
" 2>&1 || true)
assert_contains "$output" "SYNC_VERBOSITY" "validation catches invalid verbosity" || true

# ── Test: validation catches non-existent directory ──────────────────────────
echo ""
echo "-- validation: non-existent directory --"

output=$(bash -c "
    source '$PROJECT_DIR/lib/core.sh'
    source '$PROJECT_DIR/lib/config.sh'
    SYNC_BASE_DIRS='/nonexistent/path/that/does/not/exist'
    SYNC_SCAN_DEPTH=3
    SYNC_PULL_STRATEGY='rebase'
    SYNC_VERBOSITY=1
    validate_config
" 2>&1 || true)
assert_contains "$output" "directory not found" "validation catches missing directory" || true

# ── Test: validation catches bad scan depth ──────────────────────────────────
echo ""
echo "-- validation: bad scan depth --"

output=$(bash -c "
    source '$PROJECT_DIR/lib/core.sh'
    source '$PROJECT_DIR/lib/config.sh'
    SYNC_BASE_DIRS='$test_dir/repos'
    SYNC_SCAN_DEPTH=0
    SYNC_PULL_STRATEGY='rebase'
    SYNC_VERBOSITY=1
    validate_config
" 2>&1 || true)
assert_contains "$output" "SYNC_SCAN_DEPTH" "validation catches zero scan depth" || true

# ── Test: load_config works without config file ──────────────────────────────
echo ""
echo "-- no config file (defaults only) --"

unset SYNC_BASE_DIRS SYNC_SCAN_DEPTH SYNC_PULL_STRATEGY SYNC_VERBOSITY 2>/dev/null || true

# Use a non-existent config path
load_config "/tmp/nonexistent-config-file-$(date +%s).conf"
assert_eq "$HOME/projekte" "$SYNC_BASE_DIRS" "defaults work without config file" || true

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup_all
print_test_results
