#!/usr/bin/env bash
# Runs the test suites of MintApp Remover. Nothing here touches the real system:
# every suite works in its own sandbox (tests/lib/harness.sh).
#
# Usage: bash tests/run_all.sh [-v|--verbose] [SUITE...]
#        bash tests/run_all.sh --list
#   With no SUITE it runs all of them; with names (see --list) only those.
#   Without -v only failures, skips and planned gaps are listed, plus one line
#   per suite; to see only the planned gaps: bash tests/run_all.sh | grep GAP
#   SUITE_TIMEOUT=seconds limits each suite (default 900).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# name | file | what it checks
# Only suites that exist are registered: a registered file that is missing is a
# failure (below), so a suite is added here in the same change that creates it.
SUITES=(
    "quality|test_quality.sh|sources: syntax, hygiene, leftover markers, single script, ShellCheck"
    "suite-quality|test_suite_quality.sh|the suites themselves: registry, shape of each suite, totals line"
    "security|test_security.sh|code: no network, no eval, privileges and deletions in known places; hostile names refused"
    "aesthetics|test_aesthetics.sh|text screens: wrapping and alignment of every message at 80 to 30 columns, NO_COLOR, ASCII, palette, header"
    "i18n|test_i18n.py|Spanish/English tables, catalog and wording"
    "language|test_language_runtime.sh|language, system and desktop detection"
    "catalog|test_catalog.sh|catalogs and exclusions per desktop: Cinnamon, GNOME, KDE, XFCE, MATE"
    "config|test_config.sh|configuration file: location, validated read, private atomic write"
    "install|test_install.sh|install and uninstall: command, launcher and icon in the user folders"
    "meta|test_meta.sh|meta-package guard: detection and stronger warning in the plans"
    "pm|test_pm.sh|package manager layer: manager choice, actions, simulation, installed packages, owners"
    "stores|test_stores.sh|Flatpak and Snap: privileged commands, strict identifiers, removal records"
    "functions|test_functions.sh|menus and removal flows end to end (stub apt/dpkg)"
    "search|test_search.sh|search, detail and origin of applications"
    "clean|test_clean.sh|system cleaning: catalog, allowed paths, listing and removal of files"
    "gui|test_gui.sh|zenity windows: stub end to end, real zenity in Xvfb (skipped without it)"
)

verbose=0
selected=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -v|--verbose) verbose=1 ;;
        --list)
            for entry in "${SUITES[@]}"; do
                IFS='|' read -r name file text <<< "$entry"
                printf '%-14s %-28s %s\n' "$name" "$file" "$text"
            done
            exit 0 ;;
        -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]##*/}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "run_all.sh: unknown option: $1" >&2; exit 2 ;;
        *) selected+=("$1") ;;
    esac
    shift
done

known() {
    local entry name
    for entry in "${SUITES[@]}"; do
        name="${entry%%|*}"
        [ "$name" != "$1" ] || return 0
    done
    return 1
}
for name in "${selected[@]+"${selected[@]}"}"; do
    known "$name" || { echo "run_all.sh: unknown suite: $name (see --list)" >&2; exit 2; }
done

wanted() {
    [ "${#selected[@]}" -eq 0 ] && return 0
    local s
    for s in "${selected[@]}"; do [ "$s" != "$1" ] || return 0; done
    return 1
}

total_pass=0 total_fail=0 total_skip=0 total_gap=0 failed_suites=()
log="$(mktemp)"
trap 'rm -f -- "$log"' EXIT
began=$SECONDS

for entry in "${SUITES[@]}"; do
    IFS='|' read -r name file _ <<< "$entry"
    wanted "$name" || continue
    printf '== %s (%s)\n' "$name" "$file"
    if [ ! -f "$file" ]; then
        printf '  FAIL  the suite file %s is missing\n' "$file"
        failed_suites+=("$name"); continue
    fi
    case "$file" in
        *.py) runner=(python3 "$file") ;;
        *) runner=(bash "$file") ;;
    esac
    timeout "${SUITE_TIMEOUT:-900}" "${runner[@]}" > "$log" 2>&1
    status=$?
    if [ "$verbose" -eq 1 ]; then cat "$log"; else grep -vE '^  (PASS  |-- |--$)|^-- ' "$log" | grep -E '^  (FAIL|GAP|SKIP)|^        |^[^ -=]' || true; fi
    totals="$(grep -E '^  -- [0-9]+ passed' "$log" | tail -n1)"
    if [ -z "$totals" ]; then
        printf '  FAIL  %s ended without totals (exit status %s)\n' "$name" "$status"
        failed_suites+=("$name"); continue
    fi
    pass="$(sed -nE 's/.* ([0-9]+) passed.*/\1/p' <<< "$totals")"
    fail="$(sed -nE 's/.* ([0-9]+) failed.*/\1/p' <<< "$totals")"
    skip="$(sed -nE 's/.* ([0-9]+) skipped.*/\1/p' <<< "$totals")"
    gap="$(sed -nE 's/.* ([0-9]+) planned gaps.*/\1/p' <<< "$totals")"
    total_pass=$((total_pass + ${pass:-0})); total_fail=$((total_fail + ${fail:-0}))
    total_skip=$((total_skip + ${skip:-0})); total_gap=$((total_gap + ${gap:-0}))
    printf '%s\n' "$totals"
    if [ "$status" -ne 0 ] || [ "${fail:-0}" -ne 0 ]; then failed_suites+=("$name"); fi
done

printf '\n== TOTAL: %s passed, %s failed, %s skipped, %s planned gaps (%s s)\n' \
    "$total_pass" "$total_fail" "$total_skip" "$total_gap" "$((SECONDS - began))"
if [ "${#failed_suites[@]}" -gt 0 ]; then
    printf 'Failed suites: %s\n' "${failed_suites[*]}"
    exit 1
fi
