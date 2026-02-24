#!/usr/bin/env bash
# shellcheck shell=bash
################################################################################
# Tests: Repository Discovery & Filtering
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/lib/core.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/repo-discovery.sh"
source "$SCRIPT_DIR/test-helpers.sh"

# Suppress log output
SYNC_VERBOSITY=0

echo "=== Repository Discovery Tests ==="

# ── Setup ────────────────────────────────────────────────────────────────────
test_dir=$(setup_test_repos)
SYNC_REMOTE="origin"

# ── Test: discovers repos with remotes ───────────────────────────────────────
echo ""
echo "-- basic discovery --"

SYNC_BASE_DIRS="$test_dir"
SYNC_SCAN_DEPTH=1
SYNC_EXCLUDE=""
SYNC_INCLUDE=""

local_repos=()
discover_repos local_repos

# Should find: clean-repo, dirty-repo, unpushed-repo (3 with remotes)
# Should NOT find: no-remote-repo, not-a-repo
assert_eq "3" "${#local_repos[@]}" "finds 3 repos with remotes" || true

# ── Test: exclude filter ─────────────────────────────────────────────────────
echo ""
echo "-- exclude filter --"

SYNC_EXCLUDE="dirty-repo"
local_repos=()
discover_repos local_repos
assert_eq "2" "${#local_repos[@]}" "exclude removes 1 repo" || true

# Multiple excludes
SYNC_EXCLUDE="dirty-repo:unpushed-repo"
local_repos=()
discover_repos local_repos
assert_eq "1" "${#local_repos[@]}" "exclude removes 2 repos" || true

# ── Test: include filter ─────────────────────────────────────────────────────
echo ""
echo "-- include filter --"

SYNC_EXCLUDE=""
SYNC_INCLUDE="clean-repo"
local_repos=()
discover_repos local_repos
assert_eq "1" "${#local_repos[@]}" "include whitelist: only 1 repo" || true

# Multiple includes
SYNC_INCLUDE="clean-repo:dirty-repo"
local_repos=()
discover_repos local_repos
assert_eq "2" "${#local_repos[@]}" "include whitelist: 2 repos" || true

# ── Test: include + exclude combined ─────────────────────────────────────────
echo ""
echo "-- include + exclude combined --"

SYNC_INCLUDE="clean-repo:dirty-repo"
SYNC_EXCLUDE="dirty-repo"
local_repos=()
discover_repos local_repos
assert_eq "1" "${#local_repos[@]}" "include + exclude: exclude wins for dirty-repo" || true

# ── Test: glob pattern matching ──────────────────────────────────────────────
echo ""
echo "-- glob patterns --"

SYNC_INCLUDE=""
SYNC_EXCLUDE="*-repo"
local_repos=()
discover_repos local_repos
assert_eq "0" "${#local_repos[@]}" "glob *-repo excludes all repos" || true

SYNC_EXCLUDE="clean-*"
local_repos=()
discover_repos local_repos
assert_eq "2" "${#local_repos[@]}" "glob clean-* excludes only clean-repo" || true

# ── Test: empty directory ────────────────────────────────────────────────────
echo ""
echo "-- empty directory --"

empty_dir=$(mktemp -d)
_TEST_DIRS+=("$empty_dir")
SYNC_BASE_DIRS="$empty_dir"
SYNC_EXCLUDE=""
SYNC_INCLUDE=""
local_repos=()
discover_repos local_repos
assert_eq "0" "${#local_repos[@]}" "empty directory returns 0 repos" || true

# ── Test: scan depth ─────────────────────────────────────────────────────────
echo ""
echo "-- scan depth --"

nested_dir=$(mktemp -d)
_TEST_DIRS+=("$nested_dir")
mkdir -p "$nested_dir/level1/level2"
_create_mock_repo "$nested_dir/level1/level2/deep-repo" "clean"

SYNC_BASE_DIRS="$nested_dir"
SYNC_SCAN_DEPTH=1
local_repos=()
discover_repos local_repos
assert_eq "0" "${#local_repos[@]}" "depth 1 does not find deep repos" || true

SYNC_SCAN_DEPTH=3
local_repos=()
discover_repos local_repos
assert_eq "1" "${#local_repos[@]}" "depth 3 finds deep repos" || true

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup_all
print_test_results
