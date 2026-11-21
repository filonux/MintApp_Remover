#!/usr/bin/env bash
# The suites themselves (D5): the registry of run_all.sh against the files of tests/, the shape that
# run_all.sh, sections.sh and mutate.py need from every suite, the totals line that the harness, the
# Python suite and run_all.sh must agree on, and that every fault of faults.py still applies. It reads files;
# it runs run_all.sh only with --list, --help and wrong arguments, and it never starts another suite except
# the Python one (1 s).
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

TESTS="$H_TESTS_DIR"
RUN_ALL="$TESTS/run_all.sh"
# What tests/ may hold besides the suites (test_*): a new tool is listed here in the same change that adds it.
HELPERS=(run_all.sh lint.sh sections.sh measure_sections.sh coverage.sh mutate.py faults.py)
# tests/lib: only the harness.
LIB_FILES=(harness.sh)

in_list() { local x="$1" y; shift; for y in "$@"; do [ "$x" != "$y" ] || return 0; done; return 1; }
yes_no() { if "$@"; then echo 1; else echo 0; fi; }

# The registry, as "name|file|description" lines, read from run_all.sh as data.
mapfile -t REGISTRY < <(sed -n '/^SUITES=(/,/^)/p' "$RUN_ALL" | sed -n 's/^ *"\(.*\)"$/\1/p')
names=() files=()
for entry in "${REGISTRY[@]}"; do
    IFS='|' read -r name file _ <<< "$entry"
    names+=("$name") files+=("$file")
done

echo "-- the registry against the files"
check_eq 'run_all.sh registers suites' 1 "$(yes_no test "${#REGISTRY[@]}" -gt 0)"
for entry in "${REGISTRY[@]}"; do
    IFS='|' read -r name file text <<< "$entry"
    check_eq "$name: the name is lowercase letters, digits and dashes" 1 "$(yes_no test "$(grep -cE '^[a-z][a-z0-9-]*$' <<< "$name")" -eq 1)"
    check_eq "$name: the file is a test_ file, .sh or .py" 1 "$(yes_no test "$(grep -cE '^test_[a-z0-9_]+\.(sh|py)$' <<< "$file")" -eq 1)"
    check_eq "$name: the file exists in tests/" 1 "$(yes_no test -f "$TESTS/$file")"
    check_eq "$name: it has a description" 1 "$(yes_no test -n "$text")"
done
check_eq 'suite names are unique' '' "$(printf '%s\n' "${names[@]}" | sort | uniq -d)"
check_eq 'suite files are unique' '' "$(printf '%s\n' "${files[@]}" | sort | uniq -d)"
for f in "$TESTS"/test_*; do
    check_eq "${f##*/} is registered in run_all.sh" 1 "$(yes_no in_list "${f##*/}" "${files[@]}")"
done
strays=""
for f in "$TESTS"/*; do
    case "${f##*/}" in test_*|lib|__pycache__) continue ;; esac
    in_list "${f##*/}" "${HELPERS[@]}" || strays+=" ${f##*/}"
done
check_eq 'tests/ holds only the suites, lib/ and the tools of HELPERS (no fixtures, no leftovers)' '' "$strays"
extra=""
for f in "$TESTS"/lib/*; do
    in_list "${f##*/}" "${LIB_FILES[@]}" || extra+=" ${f##*/}"
done
check_eq 'tests/lib holds only the harness' '' "$extra"
check_eq 'tests/lib/harness.sh exists' 1 "$(yes_no test -f "$TESTS/lib/harness.sh")"

echo "-- run_all.sh as a command"
list_out="$(bash "$RUN_ALL" --list)"
check_eq '--list prints one line per registered suite' "${#REGISTRY[@]}" "$(grep -c . <<< "$list_out")"
for name in "${names[@]}"; do
    assert_contains "--list shows $name" "$list_out" "$name "
done
rc=0; out="$(bash "$RUN_ALL" no-such-suite 2>&1)" || rc=$?
check_eq 'an unknown suite is refused with status 2' 2 "$rc"
assert_contains 'and the message names it' "$out" 'unknown suite: no-such-suite'
rc=0; out="$(bash "$RUN_ALL" --no-such-option 2>&1)" || rc=$?
check_eq 'an unknown option is refused with status 2' 2 "$rc"
rc=0; out="$(bash "$RUN_ALL" --help 2>&1)" || rc=$?
check_eq '--help ends with status 0' 0 "$rc"
assert_contains '--help documents the per-suite timeout' "$out" 'SUITE_TIMEOUT'

echo "-- the shape of every bash suite"
for entry in "${REGISTRY[@]}"; do
    IFS='|' read -r name file _ <<< "$entry"
    case "$file" in *.sh) ;; *) continue ;; esac
    path="$TESTS/$file"
    [ -f "$path" ] || continue
    titles="$(grep -E '^echo "-- ' "$path" || true)"
    check_eq "$name: the first line is the bash shebang" '#!/usr/bin/env bash' "$(head -n1 "$path")"
    check_eq "$name: the second line opens the header comment" '# ' "$(sed -n 2p "$path" | cut -c1-2)"
    check_eq "$name: it stops at its own first failure (set -euo pipefail)" 1 "$(yes_no grep -qxF 'set -euo pipefail' "$path")"
    check_eq "$name: it loads the harness" 1 "$(yes_no grep -q 'lib/harness\.sh' "$path")"
    check_eq "$name: the last command is finish" finish "$(grep -v '^[[:space:]]*$' "$path" | tail -n1)"
    check_eq "$name: finish appears once at the start of a line" 1 "$(grep -c '^finish$' "$path" || true)"
    check_eq "$name: it has sections (echo \"-- title\" at the start of a line)" 1 "$(yes_no test -n "$titles")"
    check_eq "$name: no section title is empty" '' "$(grep -E '^echo "-- *"$' "$path" || true)"
    # An indented "echo \"-- ...\"" is a sub-heading inside a conditional block (sections.sh only starts a
    # section at the start of a line): allowed, but its title is unique too.
    all_titles="$(grep -E '^[[:space:]]*echo "-- ' "$path" | sed -E 's/^[[:space:]]+//' || true)"
    check_eq "$name: section titles are unique" '' "$(sort <<< "$all_titles" | uniq -d)"
done

echo "-- the totals line"
totals="$(bash -c 'source "$1"; T_PASS=3 T_FAIL=0 T_SKIP=2 T_GAP=1; finish' _ "$TESTS/lib/harness.sh")"
check_eq 'finish prints the totals line' '  -- 3 passed, 0 failed, 2 skipped, 1 planned gaps' "$totals"
rc=0; bash -c 'source "$1"; T_FAIL=1; finish' _ "$TESTS/lib/harness.sh" > /dev/null || rc=$?
check_eq 'finish fails when a check failed' 1 "$rc"
rc=0; bash -c 'source "$1"; T_FAIL=0; finish' _ "$TESTS/lib/harness.sh" > /dev/null || rc=$?
check_eq 'finish succeeds when none failed' 0 "$rc"
run_all_text="$(cat "$RUN_ALL")"
for key in passed failed skipped 'planned gaps'; do
    assert_contains "run_all.sh reads the number before '$key'" "$run_all_text" "([0-9]+) $key"
    assert_contains "the harness prints '$key'" "$totals" " $key"
done
py_out="$(python3 "$TESTS/test_i18n.py" 2>&1 || true)"
check_eq 'the Python suite ends with the line that run_all.sh reads' 1 "$(grep -cE '^  -- [0-9]+ passed, [0-9]+ failed' <<< "$py_out" || true)"

echo "-- sections.sh runs one section and keeps the totals"
mini="$H_TMP/mini_suite.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' "source \"$TESTS/lib/harness.sh\"" \
    'echo "-- one"' "check_eq 'first section fails when it runs' 1 2" \
    'echo "-- two"' "check_eq 'second section passes' 1 1" \
    'echo "-- three"' "check_eq 'third section fails when it runs' 1 2" \
    'finish' > "$mini"
# run_mini SECTIONS: the small suite with only those sections (MRC, MOUT).
run_mini() {
    MRC=0
    MOUT="$(ONLY_SECTIONS="$1" SECTIONS_SUITE="$mini" BASH_ENV="$TESTS/sections.sh" bash "$mini" 2>&1)" || MRC=$?
}
run_mini 2
check_eq 'a chosen section that passes ends with status 0' 0 "$MRC"
assert_contains 'and its totals line is printed' "$MOUT" '-- 1 passed, 0 failed'
assert_not_contains 'the checks of a section that was not chosen do not run' "$MOUT" 'fails when it runs'
run_mini 1
check_eq 'a chosen section that fails ends with status 1' 1 "$MRC"
assert_contains 'and only it is counted' "$MOUT" '-- 0 passed, 1 failed'
run_mini '1-3'
assert_contains 'a range chooses every section of it' "$MOUT" '-- 1 passed, 2 failed'
check_eq 'mutate.py lists the mutants of one function' 1 "$(yes_no test "$(python3 "$TESTS/mutate.py" list clean_confirm 2>&1 | grep -c .)" -gt 0)"

echo "-- faults.py: the deliberate faults of the security suite and of the robustness section"
faults_list="$(python3 "$TESTS/faults.py" list 2>&1 || true)"
check_eq 'faults.py lists its faults' 1 "$(yes_no test "$(grep -c . <<< "$faults_list")" -gt 0)"
check_eq 'every line of the list is "ID  what", an id of P, R or S and two digits' '' "$(grep -vE '^[PRS][0-9]{2}  [^ ]' <<< "$faults_list" || true)"
check_eq 'the ids are unique' '' "$(cut -d' ' -f1 <<< "$faults_list" | sort | uniq -d)"
faults_check="$(python3 "$TESTS/faults.py" check 2>&1 || true)"
check_eq 'no fault is stale or invalid (a stale one lost its text in the program or the suite: update it)' '' \
    "$(grep -v ' faults, each makes its change' <<< "$faults_check" || true)"
assert_contains 'and the check made all of them' "$faults_check" "$(grep -c . <<< "$faults_list") faults, each makes its change"

finish
