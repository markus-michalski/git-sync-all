#!/usr/bin/env bash
# shellcheck shell=bash
################################################################################
# Test Helpers
#
# Mock repo creation, assertions, and test utilities.
################################################################################

set -euo pipefail

# ── Test State ───────────────────────────────────────────────────────────────
_TEST_TOTAL=0
_TEST_PASSED=0
_TEST_FAILED=0
_TEST_DIRS=()

# ── Assertions ───────────────────────────────────────────────────────────────

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-assert_eq}"
    : $((_TEST_TOTAL += 1))

    if [[ "$expected" == "$actual" ]]; then
        : $((_TEST_PASSED += 1))
        echo -e "  \033[0;32mPASS\033[0m $msg"
        return 0
    else
        : $((_TEST_FAILED += 1))
        echo -e "  \033[0;31mFAIL\033[0m $msg"
        echo -e "    Expected: '$expected'"
        echo -e "    Actual:   '$actual'"
        return 1
    fi
}

assert_ne() {
    local unexpected="$1"
    local actual="$2"
    local msg="${3:-assert_ne}"
    : $((_TEST_TOTAL += 1))

    if [[ "$unexpected" != "$actual" ]]; then
        : $((_TEST_PASSED += 1))
        echo -e "  \033[0;32mPASS\033[0m $msg"
        return 0
    else
        : $((_TEST_FAILED += 1))
        echo -e "  \033[0;31mFAIL\033[0m $msg"
        echo -e "    Did not expect: '$unexpected'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-assert_contains}"
    : $((_TEST_TOTAL += 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        : $((_TEST_PASSED += 1))
        echo -e "  \033[0;32mPASS\033[0m $msg"
        return 0
    else
        : $((_TEST_FAILED += 1))
        echo -e "  \033[0;31mFAIL\033[0m $msg"
        echo -e "    Expected to contain: '$needle'"
        echo -e "    In: '$haystack'"
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-assert_exit_code}"
    assert_eq "$expected" "$actual" "$msg (exit code)"
}

# ── Mock Repo Creation ───────────────────────────────────────────────────────

# Create a temporary directory with mock git repos
# Returns the path to the temp directory
setup_test_repos() {
    local test_dir
    test_dir=$(mktemp -d)
    _TEST_DIRS+=("$test_dir")

    # Repo 1: clean, up-to-date
    _create_mock_repo "$test_dir/clean-repo" "clean"

    # Repo 2: has uncommitted changes
    _create_mock_repo "$test_dir/dirty-repo" "dirty"

    # Repo 3: has unpushed commits
    _create_mock_repo "$test_dir/unpushed-repo" "unpushed"

    # Repo 4: no remote configured
    _create_mock_repo "$test_dir/no-remote-repo" "no-remote"

    # Repo 5: not a git repo at all
    mkdir -p "$test_dir/not-a-repo"
    echo "just a file" >"$test_dir/not-a-repo/file.txt"

    echo "$test_dir"
}

_create_mock_repo() {
    local path="$1"
    local type="$2"

    mkdir -p "$path"

    # Create a bare remote to push to
    local bare_remote="${path}.bare"
    git init --bare --quiet "$bare_remote"

    # Init repo
    git init --quiet "$path"
    git -C "$path" remote add origin "$bare_remote"

    # Configure git user for commits
    git -C "$path" config user.email "test@test.com"
    git -C "$path" config user.name "Test User"

    # Initial commit
    echo "initial content" >"$path/README.md"
    git -C "$path" add -A
    git -C "$path" commit -m "initial commit" --quiet

    # Determine default branch name and push
    local branch
    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD)
    git -C "$path" push origin "$branch" --quiet 2>/dev/null

    # Set upstream tracking
    git -C "$path" branch --set-upstream-to="origin/$branch" "$branch" >/dev/null 2>&1

    case "$type" in
        dirty)
            echo "uncommitted change" >"$path/dirty.txt"
            ;;
        unpushed)
            echo "local only change" >"$path/local.txt"
            git -C "$path" add -A
            git -C "$path" commit -m "local commit" --quiet
            ;;
        no-remote)
            git -C "$path" remote remove origin
            ;;
        clean)
            # Already clean
            ;;
    esac
}

# Create a single mock repo of given type
create_single_mock_repo() {
    local test_dir="$1"
    local name="$2"
    local type="${3:-clean}"

    _create_mock_repo "$test_dir/$name" "$type"
}

# ── Cleanup ──────────────────────────────────────────────────────────────────

teardown_test_repos() {
    local test_dir="$1"
    rm -rf "$test_dir"
}

# Cleanup all test directories (call at end of test file)
cleanup_all() {
    local dir
    for dir in "${_TEST_DIRS[@]}"; do
        rm -rf "$dir" 2>/dev/null || true
    done
}

# ── Test Results ─────────────────────────────────────────────────────────────

print_test_results() {
    echo ""
    if [[ "$_TEST_FAILED" -gt 0 ]]; then
        echo -e "\033[0;31mResults: $_TEST_PASSED/$_TEST_TOTAL passed, $_TEST_FAILED failed\033[0m"
        return 1
    else
        echo -e "\033[0;32mResults: $_TEST_PASSED/$_TEST_TOTAL passed\033[0m"
        return 0
    fi
}
