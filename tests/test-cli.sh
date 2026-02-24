#!/usr/bin/env bash
# shellcheck shell=bash
################################################################################
# Tests: CLI Argument Parsing
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source libraries (need core first for logging stubs)
source "$PROJECT_DIR/lib/core.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/cli.sh"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== CLI Argument Parsing Tests ==="

# ── Test: --version output ───────────────────────────────────────────────────
echo ""
echo "-- version flag --"
GSA_VERSION="1.0.0"
output=$(show_version)
assert_contains "$output" "1.0.0" "--version contains version number" || true

# ── Test: --help output ──────────────────────────────────────────────────────
echo ""
echo "-- help flag --"
output=$(show_help)
assert_contains "$output" "git-sync-all" "--help contains tool name" || true
assert_contains "$output" "--dry-run" "--help contains --dry-run" || true
assert_contains "$output" "--config" "--help contains --config" || true
assert_contains "$output" "--status" "--help contains --status" || true

# ── Test: parse_args sets DRY_RUN ────────────────────────────────────────────
echo ""
echo "-- dry-run flag --"
DRY_RUN=false
SYNC_VERBOSITY=1
_CLI_EXCLUDES=()
_CLI_INCLUDES=()
_CLI_DIRS=()
parse_args --dry-run
assert_eq "true" "$DRY_RUN" "--dry-run sets DRY_RUN=true" || true

# ── Test: parse_args sets SYNC_AUTO_CONFIRM ──────────────────────────────────
echo ""
echo "-- yes flag --"
SYNC_AUTO_CONFIRM=false
DRY_RUN=false
_CLI_EXCLUDES=()
_CLI_INCLUDES=()
_CLI_DIRS=()
parse_args --yes
assert_eq "true" "$SYNC_AUTO_CONFIRM" "--yes sets SYNC_AUTO_CONFIRM=true" || true

# ── Test: parse_args sets quiet mode ─────────────────────────────────────────
echo ""
echo "-- quiet flag --"
SYNC_VERBOSITY=1
DRY_RUN=false
SYNC_AUTO_CONFIRM=false
_CLI_EXCLUDES=()
_CLI_INCLUDES=()
_CLI_DIRS=()
parse_args --quiet
assert_eq "0" "$SYNC_VERBOSITY" "--quiet sets SYNC_VERBOSITY=0" || true

# ── Test: parse_args increases verbosity ─────────────────────────────────────
echo ""
echo "-- verbose flag --"
SYNC_VERBOSITY=1
DRY_RUN=false
SYNC_AUTO_CONFIRM=false
_CLI_EXCLUDES=()
_CLI_INCLUDES=()
_CLI_DIRS=()
parse_args -v
assert_eq "2" "$SYNC_VERBOSITY" "-v increases SYNC_VERBOSITY to 2" || true

# ── Test: parse_args collects excludes ───────────────────────────────────────
echo ""
echo "-- exclude flag --"
DRY_RUN=false
SYNC_AUTO_CONFIRM=false
SYNC_VERBOSITY=1
_CLI_EXCLUDES=()
_CLI_INCLUDES=()
_CLI_DIRS=()
parse_args --exclude "vendor" --exclude "node_modules"
assert_eq "2" "${#_CLI_EXCLUDES[@]}" "--exclude collects patterns" || true
assert_eq "vendor" "${_CLI_EXCLUDES[0]}" "--exclude first pattern" || true
assert_eq "node_modules" "${_CLI_EXCLUDES[1]}" "--exclude second pattern" || true

# ── Test: parse_args collects directories ────────────────────────────────────
echo ""
echo "-- directory arguments --"
DRY_RUN=false
SYNC_AUTO_CONFIRM=false
SYNC_VERBOSITY=1
_CLI_EXCLUDES=()
_CLI_INCLUDES=()
_CLI_DIRS=()
parse_args /tmp/dir1 /tmp/dir2
assert_eq "2" "${#_CLI_DIRS[@]}" "positional args collected as dirs" || true
assert_eq "/tmp/dir1" "${_CLI_DIRS[0]}" "first directory" || true

# ── Test: parse_args --no-pull, --no-push, --no-commit ───────────────────────
echo ""
echo "-- no-pull/push/commit flags --"
DRY_RUN=false
SYNC_AUTO_CONFIRM=false
SYNC_VERBOSITY=1
NO_PULL=false
NO_PUSH=false
NO_COMMIT=false
_CLI_EXCLUDES=()
_CLI_INCLUDES=()
_CLI_DIRS=()
parse_args --no-pull --no-push --no-commit
assert_eq "true" "$NO_PULL" "--no-pull" || true
assert_eq "true" "$NO_PUSH" "--no-push" || true
assert_eq "true" "$NO_COMMIT" "--no-commit" || true

# ── Test: apply_cli_overrides merges excludes ────────────────────────────────
echo ""
echo "-- apply_cli_overrides --"
_CLI_EXCLUDES=("vendor" "node_modules")
_CLI_INCLUDES=()
_CLI_DIRS=("/tmp/custom")
SYNC_EXCLUDE=""
SYNC_INCLUDE=""
SYNC_BASE_DIRS=""
apply_cli_overrides
assert_eq "vendor:node_modules" "$SYNC_EXCLUDE" "excludes merged with colon" || true
assert_eq "/tmp/custom" "$SYNC_BASE_DIRS" "dirs merged" || true

# ── Test: unknown option causes die ──────────────────────────────────────────
echo ""
echo "-- unknown option --"
# Run in a separate bash process because die() calls exit
output=$(bash -c "
    source '$PROJECT_DIR/lib/core.sh'
    source '$PROJECT_DIR/lib/config.sh'
    source '$PROJECT_DIR/lib/cli.sh'
    SYNC_VERBOSITY=1
    parse_args --unknown-flag
" 2>&1 || true)
assert_contains "$output" "Unknown option" "unknown flag triggers error" || true

# ── Results ──────────────────────────────────────────────────────────────────
print_test_results
