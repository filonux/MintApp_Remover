#!/usr/bin/env bash
# measure_sections.sh SUITE SECTIONS OUT.tsv [FULL_LOG]
#   Runs each section of SUITE alone (tests/sections.sh) and writes one line per section: section, seconds,
#   PASS, FAIL, SKIP, exit status and, when FULL_LOG (the output of the complete suite) is given, the checks
#   the section did that the complete run did not do (extra) and those it lost (missing).
#   SECTIONS is a list with ranges, as in ONLY_SECTIONS: "1-64" or "12 56-58". SUITE is an absolute path.
#   A section is faithful when its status is 0 and extra and missing are 0. The log of each section is
#   kept in ${SECTIONS_LOGS:-/tmp/mintapp-sections}/sec_N.log. The last line of OUT.tsv is "# done".
set -uo pipefail
suite=$1 list=$2 out=$3 full=${4:-}
tools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
logs=${SECTIONS_LOGS:-/tmp/mintapp-sections}
mkdir -p "$logs"
cd "$(dirname "$suite")/.." || exit 1
sorted() { sort; }
: > "$out"
for w in $list; do
    case "$w" in *-*) lo=${w%-*} hi=${w#*-} ;; *) lo=$w hi=$w ;; esac
    for ((k = lo; k <= hi; k++)); do
        s=$SECONDS
        ONLY_SECTIONS="$k" SECTIONS_SUITE="tests/$(basename "$suite")" BASH_ENV="$tools/sections.sh" \
            bash "tests/$(basename "$suite")" > "$logs/sec_$k.log" 2>&1
        rc=$?
        extra="" missing=""
        if [ -n "$full" ]; then
            expected="$(awk -v k="$k" '/^-- /{n++} n==k && /^  PASS/' "$full" | sorted)"
            got="$(grep '^  PASS' "$logs/sec_$k.log" | sorted)"
            extra="$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$got") | grep -c .)"
            missing="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$got") | grep -c .)"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$k" "$((SECONDS - s))" "$(grep -c '^  PASS' "$logs/sec_$k.log")" \
            "$(grep -c '^  FAIL' "$logs/sec_$k.log")" "$(grep -c '^  SKIP' "$logs/sec_$k.log")" "$rc" "$extra" "$missing" >> "$out"
    done
done
echo "# done" >> "$out"
