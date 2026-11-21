#!/usr/bin/env bash
# coverage.sh SUITE SECTIONS OUT_DIR
#   Which lines of the program each section of a suite runs. Each section of SECTIONS (a list with ranges, as
#   in ONLY_SECTIONS: "1-64" or "12 56-58") runs alone (tests/sections.sh) against a copy of the program that notes
#   every line it executes. It writes OUT_DIR/sec_N.lines (one line number per row) and, at the end, OUT_DIR/map.tsv:
#   "line TAB sections" for each line that some section ran. tests/mutate.py reads the map to run only the sections
#   that reach the changed line. SUITE is an absolute path. The copy keeps the numbering: the line
#   "set -uo pipefail" of the program also turns on set -T and a DEBUG trap that notes each line once per process.
#   Slower than a normal run (a trap on every command). Needs a folder where every user can write (/dev/shm).
set -uo pipefail
suite=$1 list=$2 out=$3
tools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prog="$tools/../script/MintApp_Remover.sh"
at="$(grep -n -m1 '^set -uo pipefail$' "$prog" | cut -d: -f1)"
[ -n "$at" ] || { echo "coverage.sh: the program has no line 'set -uo pipefail'" >&2; exit 1; }
work="$(mktemp -d "${COV_TMP:-/dev/shm}/mintapp-cov.XXXXXX")"
chmod 755 "$work"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$out"
cd "$(dirname "$suite")/.." || exit 1
for w in $list; do
    case "$w" in *-*) lo=${w%-*} hi=${w#*-} ;; *) lo=$w hi=$w ;; esac
    for ((k = lo; k <= hi; k++)); do
        raw="$work/raw_$k"
        mkdir -p "$raw"
        chmod 1777 "$raw"
        {
            head -n "$((at - 1))" "$prog"
            # shellcheck disable=SC2016  # the program expands these, not this script
            printf 'set -uo pipefail; set -T; _COV_DIR=%q; _COV_SELF=${BASH_SOURCE[0]}; declare -gA _COV_SEEN=(); ' "$raw"
            # shellcheck disable=SC2016  # the program expands these, not this script
            printf '%s\n' '_cov_hit() { [ "${BASH_SOURCE[1]-}" = "$_COV_SELF" ] || return 0; [ -z "${_COV_SEEN[${BASH_LINENO[0]}]-}" ] || return 0; _COV_SEEN[${BASH_LINENO[0]}]=1; echo "${BASH_LINENO[0]}" >> "$_COV_DIR/$$"; }; trap _cov_hit DEBUG'
            tail -n "+$((at + 1))" "$prog"
        } > "$work/prog_$k.sh"
        chmod 644 "$work/prog_$k.sh"
        MINTAPP_TEST_SCRIPT="$work/prog_$k.sh" ONLY_SECTIONS="$k" SECTIONS_SUITE="tests/$(basename "$suite")" \
            BASH_ENV="$tools/sections.sh" bash "tests/$(basename "$suite")" > "$work/log_$k" 2>&1 \
            || echo "coverage.sh: section $k ended with status $? (see its lines anyway)" >&2
        find "$raw" -type f -print0 | xargs -0 -r cat | sort -n -u > "$out/sec_$k.lines"
        rm -rf -- "$raw" "$work/prog_$k.sh"
    done
done
for f in "$out"/sec_*.lines; do
    k="${f##*/sec_}"; k="${k%.lines}"
    awk -v k="$k" '{ print $1 "\t" k }' "$f"
done | sort -n -k1,1 -k2,2n | awk -F'\t' '{ if ($1 != last) { if (last != "") print last "\t" s; last = $1; s = $2 } else s = s " " $2 } END { if (last != "") print last "\t" s }' > "$out/map.tsv"
echo "coverage.sh: $(wc -l < "$out/map.tsv") lines of the program run by the sections of $out"
