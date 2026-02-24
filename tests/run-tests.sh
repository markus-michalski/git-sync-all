#!/usr/bin/env bash
# shellcheck shell=bash
################################################################################
# Test Runner
#
# Runs all test-*.sh files and reports overall results.
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "========================================"
echo "  git-sync-all Test Suite"
echo "========================================"
echo ""

total_files=0
passed_files=0
failed_files=0
failed_names=()

for test_file in "$SCRIPT_DIR"/test-*.sh; do
    # Skip test-helpers.sh
    [[ "$(basename "$test_file")" == "test-helpers.sh" ]] && continue

    : $((total_files += 1))
    test_name="$(basename "$test_file" .sh)"

    echo "--- Running: $test_name ---"
    if bash "$test_file"; then
        : $((passed_files += 1))
    else
        : $((failed_files += 1))
        failed_names+=("$test_name")
    fi
    echo ""
done

echo "========================================"
echo "  Overall Results"
echo "========================================"
echo ""
echo "  Test files: $total_files"
echo -e "  Passed:     \033[0;32m$passed_files\033[0m"
echo -e "  Failed:     \033[0;31m$failed_files\033[0m"

if [[ ${#failed_names[@]} -gt 0 ]]; then
    echo ""
    echo "  Failed tests:"
    for name in "${failed_names[@]}"; do
        echo -e "    \033[0;31m- $name\033[0m"
    done
fi

echo ""

[[ "$failed_files" -gt 0 ]] && exit 1
exit 0
