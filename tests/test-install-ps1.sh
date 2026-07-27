#!/usr/bin/env bash
# shellcheck shell=bash
################################################################################
# Tests: Windows installer (install.ps1)
#
# Skipped on non-Windows hosts (no PowerShell available).
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== install.ps1 Tests ==="

# ── Skip on non-Windows ──────────────────────────────────────────────────────
if ! command -v powershell.exe &>/dev/null; then
    echo "  SKIP  powershell.exe not available (non-Windows host)"
    echo ""
    echo "Results: skipped"
    exit 0
fi

if ! command -v cygpath &>/dev/null; then
    echo "  SKIP  cygpath not available (not an MSYS/Git Bash environment)"
    echo ""
    echo "Results: skipped"
    exit 0
fi

INSTALLER="$REPO_ROOT/install.ps1"

# Run install.ps1 with the given arguments, capturing stdout+stderr.
# Always passes -NoPathUpdate so tests never touch the user's PATH.
_run_installer() {
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "$(cygpath -w "$INSTALLER")" -NoPathUpdate "$@" 2>&1
}

test_dir=$(mktemp -d)
_TEST_DIRS+=("$test_dir")
prefix="$test_dir/opt"
win_prefix="$(cygpath -w "$prefix")"

# ── Test: installer exists ───────────────────────────────────────────────────
echo ""
echo "-- installer present --"

if [[ -f "$INSTALLER" ]]; then
    : $((_TEST_TOTAL += 1))
    : $((_TEST_PASSED += 1))
    echo -e "  \033[0;32mPASS\033[0m install.ps1 exists"
else
    : $((_TEST_TOTAL += 1))
    : $((_TEST_FAILED += 1))
    echo -e "  \033[0;31mFAIL\033[0m install.ps1 missing at $INSTALLER"
    print_test_results
    exit 1
fi

# ── Test: copy install lays out bin/lib/config ───────────────────────────────
echo ""
echo "-- install (copy mode) --"

install_out=$(_run_installer -Prefix "$win_prefix" || true)

assert_eq "true" "$([[ -f "$prefix/bin/git-sync-all" ]] && echo true || echo false)" \
    "bin/git-sync-all installed" || echo "$install_out"
assert_eq "true" "$([[ -f "$prefix/bin/git-sync-all.cmd" ]] && echo true || echo false)" \
    "bin/git-sync-all.cmd shim created"
assert_eq "true" "$([[ -f "$prefix/lib/core.sh" ]] && echo true || echo false)" \
    "lib/core.sh installed"
assert_eq "true" "$([[ -f "$prefix/config/config.conf.example" ]] && echo true || echo false)" \
    "config example installed"

# All libs must be present (bin/git-sync-all sources them by name)
lib_missing=""
for lib in core config cli repo-discovery git-ops sync inventory issues; do
    [[ -f "$prefix/lib/${lib}.sh" ]] || lib_missing="${lib_missing} ${lib}"
done
assert_eq "" "$lib_missing" "all libraries installed"

# ── Test: installed files use LF line endings ────────────────────────────────
echo ""
echo "-- line endings --"

# Count CR bytes directly - 'grep $'\r'' is unreliable under MSYS, where the
# lone CR argument gets stripped and the empty pattern then matches every line.
_count_cr() {
    tr -cd '\r' <"$1" | wc -c | tr -d '[:space:]'
}

assert_eq "0" "$(_count_cr "$prefix/bin/git-sync-all")" \
    "installed bin/git-sync-all has no CR characters"
assert_eq "0" "$(_count_cr "$prefix/lib/core.sh")" \
    "installed lib/core.sh has no CR characters"

# The .cmd shim is the opposite case: cmd.exe wants CRLF.
cmd_cr=$(_count_cr "$prefix/bin/git-sync-all.cmd")
assert_ne "0" "$cmd_cr" "cmd shim uses CRLF line endings"

# ── Test: installed script is executable via bash ────────────────────────────
echo ""
echo "-- installed script runs --"

version_out=$(bash "$prefix/bin/git-sync-all" --version 2>&1 || true)
assert_contains "$version_out" "git-sync-all v" "installed script reports version via bash"

help_out=$(bash "$prefix/bin/git-sync-all" --help 2>&1 || true)
assert_contains "$help_out" "USAGE" "installed script prints help (libs resolve correctly)"

# ── Test: .cmd shim works from cmd.exe ───────────────────────────────────────
echo ""
echo "-- cmd shim --"

shim_out=$(MSYS_NO_PATHCONV=1 cmd.exe /c "${win_prefix}\\bin\\git-sync-all.cmd" --version 2>&1 || true)
assert_contains "$shim_out" "git-sync-all v" "cmd shim reports version"

# ── Test: install is idempotent ──────────────────────────────────────────────
echo ""
echo "-- idempotent reinstall --"

if reinstall_out=$(_run_installer -Prefix "$win_prefix"); then rc=0; else rc=$?; fi
assert_eq "0" "$rc" "reinstall exits successfully"
assert_eq "true" "$([[ -f "$prefix/bin/git-sync-all" ]] && echo true || echo false)" \
    "bin/git-sync-all still present after reinstall" || echo "$reinstall_out"

# ── Test: link mode forwards to the repo ─────────────────────────────────────
echo ""
echo "-- install (link mode) --"

link_prefix="$test_dir/linked"
win_link_prefix="$(cygpath -w "$link_prefix")"
link_out=$(_run_installer -Prefix "$win_link_prefix" -Link || true)

assert_eq "true" "$([[ -f "$link_prefix/bin/git-sync-all" ]] && echo true || echo false)" \
    "link mode creates bin/git-sync-all" || echo "$link_out"
assert_eq "false" "$([[ -d "$link_prefix/lib" ]] && echo true || echo false)" \
    "link mode does not copy lib/"

link_version=$(bash "$link_prefix/bin/git-sync-all" --version 2>&1 || true)
assert_contains "$link_version" "git-sync-all v" "link-mode forwarder runs the repo script"

# ── Test: uninstall removes what it installed ────────────────────────────────
echo ""
echo "-- uninstall --"

uninstall_out=$(_run_installer -Prefix "$win_prefix" -Uninstall || true)

assert_eq "false" "$([[ -f "$prefix/bin/git-sync-all" ]] && echo true || echo false)" \
    "uninstall removes bin/git-sync-all" || echo "$uninstall_out"
assert_eq "false" "$([[ -f "$prefix/bin/git-sync-all.cmd" ]] && echo true || echo false)" \
    "uninstall removes cmd shim"
assert_eq "false" "$([[ -d "$prefix/lib" ]] && echo true || echo false)" \
    "uninstall removes lib/"

# ── Test: uninstall keeps foreign files ──────────────────────────────────────
echo ""
echo "-- uninstall is not destructive --"

safe_prefix="$test_dir/safe"
win_safe_prefix="$(cygpath -w "$safe_prefix")"
_run_installer -Prefix "$win_safe_prefix" >/dev/null 2>&1 || true
mkdir -p "$safe_prefix/bin"
echo "do not delete me" >"$safe_prefix/bin/unrelated.txt"
echo "mine too" >"$safe_prefix/important.txt"

_run_installer -Prefix "$win_safe_prefix" -Uninstall >/dev/null 2>&1 || true

assert_eq "true" "$([[ -f "$safe_prefix/bin/unrelated.txt" ]] && echo true || echo false)" \
    "uninstall keeps unrelated file in bin/"
assert_eq "true" "$([[ -f "$safe_prefix/important.txt" ]] && echo true || echo false)" \
    "uninstall keeps unrelated file in prefix root"

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup_all
print_test_results
