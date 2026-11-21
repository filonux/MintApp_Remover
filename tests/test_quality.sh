#!/usr/bin/env bash
# Quality of the sources (D5): syntax, hygiene, leftover markers, the paths the comments cite, the shape of
# the single script and ShellCheck. These are the checks of the CI (.github/workflows/quality.yml), made on
# every run. The program is read through H_SCRIPT, so a changed copy (MINTAPP_TEST_SCRIPT) is judged too.
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

SOURCES=("$H_SCRIPT" "$H_TESTS_DIR"/*.sh "$H_TESTS_DIR"/lib/*.sh "$H_TESTS_DIR"/*.py)

rel() { printf '%s' "${1#"$H_REPO_DIR"/}"; }
yes_no() { if "$@"; then echo 1; else echo 0; fi; }
hex_of() { od -An -tx1 | tr -d ' \n'; }
# first3 PATTERN FILE: the first three lines of FILE that match, cut short (empty when none).
first3() { grep -nE -- "$1" "$2" | cut -c1-80 | head -n3 || true; }

echo "-- syntax"
for f in "$H_SCRIPT" "$H_TESTS_DIR"/*.sh "$H_TESTS_DIR"/lib/*.sh; do
    check_eq "bash -n $(rel "$f")" '' "$(bash -n "$f" 2>&1 || true)"
done
for f in "$H_TESTS_DIR"/*.py; do
    check_eq "python syntax $(rel "$f")" '' \
        "$(python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$f" 2>&1 || true)"
done

echo "-- hygiene of every source"
tab=$'\t'
for f in "${SOURCES[@]}"; do
    n="$(rel "$f")"
    check_eq "$n: no trailing spaces or tabs" '' "$(first3 '[[:space:]]+$' "$f")"
    check_eq "$n: no carriage returns" 0 "$(grep -c $'\r' "$f" || true)"
    check_eq "$n: no tab in the indentation" '' "$(first3 "^[[:space:]]*$tab" "$f")"
    check_eq "$n: it ends with a newline" 0a "$(tail -c1 "$f" | hex_of)"
    check_eq "$n: no blank line at the end" 1 "$(yes_no test "$(tail -c2 "$f" | hex_of)" != 0a0a)"
    check_eq "$n: no byte order mark" 1 "$(yes_no test "$(head -c3 "$f" | hex_of)" != efbbbf)"
    check_eq "$n: valid UTF-8 and no NUL byte" '' "$(python3 -c '
import sys
data = open(sys.argv[1], "rb").read()
data.decode("utf-8")
sys.exit(1 if b"\0" in data else 0)' "$f" 2>&1 || echo 'not valid UTF-8, or it has a NUL byte')"
done

echo "-- leftover markers"
# The words are built from pieces so that this file does not hold them itself.
todo_re='TO''DO|FIX''ME|X''XX|HA''CK'
for f in "${SOURCES[@]}"; do
    n="$(rel "$f")"
    check_eq "$n: no unfinished-work marker" '' "$(grep -nwE -- "$todo_re" "$f" | cut -c1-80 | head -n3 || true)"
    check_eq "$n: no merge conflict marker" '' "$(first3 '^(<{7}|>{7})( |$)|^={7}$' "$f")"
    check_eq "$n: no set -x left on" '' "$(first3 '^[[:space:]]*set (-[a-z]*x|-o xtrace)' "$f")"
done

echo "-- the files that comments and tests cite exist"
missing="$(python3 - "$H_REPO_DIR" "${SOURCES[@]}" <<'EOF'
import os
import re
import sys

repo, files = sys.argv[1], sys.argv[2:]
pattern = re.compile(r"(?<![\w/.-])((?:tests|script|assets)/[\w./-]*\w)(.?)")
found = []
for name in files:
    for number, line in enumerate(open(name, encoding="utf-8"), 1):
        for m in pattern.finditer(line):
            path = m.group(1)
            if m.group(2) in ("*", "{", "}", "$", "<", "%", "[", "?"):
                continue  # a pattern or a placeholder
            if not os.path.exists(os.path.join(repo, path)):
                found.append(f"{os.path.relpath(name, repo)}:{number}: {path}")
print("\n".join(found[:5]))
EOF
)"
check_eq 'every repository path the sources cite exists' '' "$missing"

echo "-- the program is a single, importable script"
new_sandbox
check_eq 'script/ holds only MintApp_Remover.sh' MintApp_Remover.sh "$(ls -1A "$H_REPO_DIR/script")"
check_eq 'the first line is a bash shebang' 1 "$(grep -cE '^#!/(usr/)?bin/(env )?bash$' <(head -n1 "$H_SCRIPT") || true)"
check_eq "the line 'set -uo pipefail' appears once (tests/coverage.sh looks for it)" 1 "$(grep -c '^set -uo pipefail$' "$H_SCRIPT" || true)"
version="$(sed -n 's/^MINTAPP_VERSION="\(.*\)"$/\1/p' "$H_SCRIPT" | head -n1)"
check_eq 'MINTAPP_VERSION is major.minor.patch' 1 "$(grep -cE '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$version" || true)"
app_run '' -- --version
check_eq '--version prints the name and the version' "MintApp Remover $version" "$OUT"
check_eq '--version ends with status 0' 0 "$RC"
app_eval 'printf ok'
check_eq 'sourcing the program only defines things: nothing is printed or run' ok "$OUT"
check_eq 'and nothing is left in the home' '' "$(find "$SB/home" -mindepth 1 | head -n3)"

echo "-- ShellCheck"
if command -v "${SHELLCHECK_BIN:-shellcheck}" > /dev/null 2>&1; then
    rc=0; out="$(bash "$H_TESTS_DIR/lint.sh" 2>&1)" || rc=$?
    check_eq 'tests/lint.sh ends with status 0' 0 "$rc"
    assert_contains 'ShellCheck finds nothing in the program and the suites' "$out" 'no findings in'
else
    skip_case 'ShellCheck is not installed (pip install shellcheck-py==0.11.0.1)'
fi

finish
