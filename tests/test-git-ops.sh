#!/usr/bin/env bash
# shellcheck shell=bash
################################################################################
# Tests: Git Operations
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/lib/core.sh"
source "$PROJECT_DIR/lib/config.sh"
source "$PROJECT_DIR/lib/git-ops.sh"
source "$SCRIPT_DIR/test-helpers.sh"

# Suppress log output
SYNC_VERBOSITY=0
SYNC_REMOTE="origin"
SYNC_PULL_STRATEGY="rebase"
DRY_RUN=false

echo "=== Git Operations Tests ==="

# ── Setup ────────────────────────────────────────────────────────────────────
test_dir=$(setup_test_repos)

# ── Test: get_current_branch ─────────────────────────────────────────────────
echo ""
echo "-- get_current_branch --"

branch=$(get_current_branch "$test_dir/clean-repo")
# Default branch could be main or master depending on git config
assert_ne "unknown" "$branch" "clean-repo has a known branch" || true

# ── Test: has_uncommitted_changes ────────────────────────────────────────────
echo ""
echo "-- has_uncommitted_changes --"

if has_uncommitted_changes "$test_dir/dirty-repo"; then
    : $((_TEST_TOTAL += 1))
    : $((_TEST_PASSED += 1))
    echo -e "  \033[0;32mPASS\033[0m dirty-repo has uncommitted changes"
else
    : $((_TEST_TOTAL += 1))
    : $((_TEST_FAILED += 1))
    echo -e "  \033[0;31mFAIL\033[0m dirty-repo should have uncommitted changes"
fi

if has_uncommitted_changes "$test_dir/clean-repo"; then
    : $((_TEST_TOTAL += 1))
    : $((_TEST_FAILED += 1))
    echo -e "  \033[0;31mFAIL\033[0m clean-repo should NOT have uncommitted changes"
else
    : $((_TEST_TOTAL += 1))
    : $((_TEST_PASSED += 1))
    echo -e "  \033[0;32mPASS\033[0m clean-repo is clean"
fi

# ── Test: count_dirty_files ──────────────────────────────────────────────────
echo ""
echo "-- count_dirty_files --"

dirty_count=$(count_dirty_files "$test_dir/dirty-repo")
# Trim whitespace
dirty_count=$(echo "$dirty_count" | tr -d ' ')
assert_eq "1" "$dirty_count" "dirty-repo has 1 dirty file" || true

clean_count=$(count_dirty_files "$test_dir/clean-repo")
clean_count=$(echo "$clean_count" | tr -d ' ')
assert_eq "0" "$clean_count" "clean-repo has 0 dirty files" || true

# ── Test: has_unpushed_commits ───────────────────────────────────────────────
echo ""
echo "-- has_unpushed_commits --"

if has_unpushed_commits "$test_dir/unpushed-repo"; then
    : $((_TEST_TOTAL += 1))
    : $((_TEST_PASSED += 1))
    echo -e "  \033[0;32mPASS\033[0m unpushed-repo has unpushed commits"
else
    : $((_TEST_TOTAL += 1))
    : $((_TEST_FAILED += 1))
    echo -e "  \033[0;31mFAIL\033[0m unpushed-repo should have unpushed commits"
fi

if has_unpushed_commits "$test_dir/clean-repo"; then
    : $((_TEST_TOTAL += 1))
    : $((_TEST_FAILED += 1))
    echo -e "  \033[0;31mFAIL\033[0m clean-repo should NOT have unpushed commits"
else
    : $((_TEST_TOTAL += 1))
    : $((_TEST_PASSED += 1))
    echo -e "  \033[0;32mPASS\033[0m clean-repo has no unpushed commits"
fi

# ── Test: count_unpushed ─────────────────────────────────────────────────────
echo ""
echo "-- count_unpushed --"

unpushed_count=$(count_unpushed "$test_dir/unpushed-repo")
unpushed_count=$(echo "$unpushed_count" | tr -d ' ')
assert_eq "1" "$unpushed_count" "unpushed-repo has 1 unpushed commit" || true

# ── Test: commit_changes ─────────────────────────────────────────────────────
echo ""
echo "-- commit_changes --"

# Commit the dirty repo's changes
commit_changes "$test_dir/dirty-repo" "test: auto commit" "Test body" >/dev/null 2>&1

if has_uncommitted_changes "$test_dir/dirty-repo"; then
    : $((_TEST_TOTAL += 1))
    : $((_TEST_FAILED += 1))
    echo -e "  \033[0;31mFAIL\033[0m dirty-repo still has uncommitted changes after commit"
else
    : $((_TEST_TOTAL += 1))
    : $((_TEST_PASSED += 1))
    echo -e "  \033[0;32mPASS\033[0m dirty-repo is clean after commit_changes"
fi

# Check commit message
last_msg=$(git -C "$test_dir/dirty-repo" log -1 --format="%s")
assert_eq "test: auto commit" "$last_msg" "commit message is correct" || true

# ── Test: push_commits ───────────────────────────────────────────────────────
echo ""
echo "-- push_commits --"

push_commits "$test_dir/unpushed-repo" >/dev/null 2>&1

if has_unpushed_commits "$test_dir/unpushed-repo"; then
    : $((_TEST_TOTAL += 1))
    : $((_TEST_FAILED += 1))
    echo -e "  \033[0;31mFAIL\033[0m unpushed-repo still has unpushed commits after push"
else
    : $((_TEST_TOTAL += 1))
    : $((_TEST_PASSED += 1))
    echo -e "  \033[0;32mPASS\033[0m unpushed-repo is pushed after push_commits"
fi

# ── Test: dry-run mode ───────────────────────────────────────────────────────
echo ""
echo "-- dry-run mode --"

# Create a new dirty file in clean-repo
echo "dry-run test" >"$test_dir/clean-repo/dry-run.txt"

DRY_RUN=true
commit_changes "$test_dir/clean-repo" "should not commit" 2>/dev/null

# File should still be uncommitted (dry-run didn't actually commit)
if has_uncommitted_changes "$test_dir/clean-repo"; then
    : $((_TEST_TOTAL += 1))
    : $((_TEST_PASSED += 1))
    echo -e "  \033[0;32mPASS\033[0m dry-run did not actually commit"
else
    : $((_TEST_TOTAL += 1))
    : $((_TEST_FAILED += 1))
    echo -e "  \033[0;31mFAIL\033[0m dry-run should NOT commit changes"
fi
DRY_RUN=false

# ── Test: subshell isolation (cd does not leak) ──────────────────────────────
echo ""
echo "-- subshell isolation --"

original_dir="$PWD"
get_current_branch "$test_dir/clean-repo" >/dev/null
assert_eq "$original_dir" "$PWD" "get_current_branch does not change PWD" || true

has_uncommitted_changes "$test_dir/dirty-repo" || true
assert_eq "$original_dir" "$PWD" "has_uncommitted_changes does not change PWD" || true

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup_all
print_test_results
