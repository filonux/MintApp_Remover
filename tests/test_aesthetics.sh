#!/usr/bin/env bash
# Aesthetics of the text screens (D5, 7.4): how the program wraps, aligns and colors what it prints.
# Exact samples for the layout functions; on every message of the program, in both languages, the
# properties that hold at any width (no row wider than the screen, no word lost or cut, no blank row
# of its own); then color and ASCII on the real screens. What depends on the width of a terminal runs
# on a pseudo-terminal of that width (pty_eval).
# SC2016 is off for the whole file: the code given to app_eval is single-quoted on purpose,
# because the program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

HAVE_PTY=""
if command -v script > /dev/null 2>&1; then HAVE_PTY=1; fi
# Characters (not bytes) are only counted with a UTF-8 locale: the program under test sees it as LC_ALL.
UTF8=""
if [ "$(LC_ALL=C.UTF-8 locale charmap 2> /dev/null || true)" = UTF-8 ]; then UTF8=C.UTF-8; fi
ESC=$'\033'

# plain: OUT without any escape sequence (clear's and the colors').
plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }
# pty_eval COLS CODE [VAR=val ...]: CODE, in the program, on a pseudo-terminal COLS columns wide (OUT).
# PTY_ROWS=N (before the call) sets the height of the terminal (40 by default).
pty_eval() {
    local cols="$1" code="$2" cmd
    shift 2
    printf -v cmd 'stty cols %s rows %s; %q -c %q bash %q %q' "$cols" "${PTY_ROWS:-40}" "$H_BASH" 'source "$1"; eval "$2"' "$H_SCRIPT" "$code"
    _exec '' 60 "$@" -- "$(command -v script)" -qec "$cmd" /dev/null
    OUT="${OUT//$'\r'/}"
}
# wl WIDTH TEXT: the rows of wrap_line, joined with | (OUT).
wl() { app_eval 'wrap_line "$W" "$T"; IFS="|"; printf "%s" "${WRAP_ROWS[*]}"' W="$1" T="$2"; }
# we WIDTH TEXT: the rows of wrap_even, joined with | (OUT).
we() {
    app_eval 'printf "%s\n" "$T" | wrap_even "$W" | { rows=(); while IFS= read -r l; do rows+=("$l"); done; IFS="|"; printf "%s" "${rows[*]}"; }' W="$1" T="$2"
}
# lines_wider LIMIT: the lines of stdin wider than LIMIT characters, as "N columns: text" (up to three).
lines_wider() (
    LC_ALL="${UTF8:-C}"
    local l limit="$1" n=0
    while IFS= read -r l; do
        if [ "${#l}" -gt "$limit" ] && [ "$n" -lt 3 ]; then printf '%s columns: %s\n' "${#l}" "$l"; n=$((n + 1)); fi
    done
)
# squash TEXT: the text without any white space (what wrapping must never change).
squash() { printf '%s' "${1//[[:space:]]/}"; }
# path_problems COLS DIR REST: what is wrong in OUT, the screen print_fit_path drew on a terminal COLS wide for the
# text DIR followed by REST (nothing if it is right). A path wider than the text width, or with a space, is alone on
# the first row; one that fits stays whole at the start of it. Every other row is within the text width, is not blank
# and does not end with a space; no word of the text is lost, repeated or cut.
path_problems() (
    LC_ALL="${UTF8:-C}"
    local cols="$1" dir="$2" rest="$3" tw row i=0
    local -a prows
    tw=$((cols - 1)); [ "$tw" -le 100 ] || tw=100
    mapfile -t prows <<< "$OUT"
    [ "$(squash "$OUT")" = "$(squash "$dir$rest")" ] || echo "the words changed"
    if [ "${#dir}" -gt "$tw" ] || [[ "$dir" == *[[:space:]]* ]]; then
        [ "${prows[0]}" = "$dir" ] || echo "the path is not alone on the first row: ${prows[0]}"
        i=1
    else
        [[ "${prows[0]}" == "$dir "* ]] || echo "the path is not whole at the start of the first row: ${prows[0]}"
    fi
    for (( ; i < ${#prows[@]}; i++ )); do
        row="${prows[i]}"
        [ "${#row}" -le "$tw" ] || echo "row $((i + 1)) has ${#row} columns: $row"
        [ -n "${row//[[:space:]]/}" ] || echo "row $((i + 1)) is blank"
        [ "$row" = "${row%[[:space:]]}" ] || echo "row $((i + 1)) ends with a space"
    done
)

# The audit of the corpus sections, run inside the program: each message of each language, as the screens
# print it (text_print: \n is a line break), wrapped at each width; one output line per problem.
CORPUS='
squash() { local t="${1//[[:space:]]/}"; printf "%s" "$t"; }
nwords() { local -a w; read -ra w <<< "$1"; printf "%s" "${#w[@]}"; }
# audit LABEL WIDTH LINE: the rows in ROWS against the line they come from.
audit() {
    local label="$1" w="$2" line="$3" i n="${#ROWS[@]}" joined=""
    for (( i = 0; i < n; i++ )); do
        joined+="${ROWS[i]}"
        [ "${#ROWS[i]}" -le "$w" ] || echo "$label: ${#ROWS[i]} columns: ${ROWS[i]}"
        [ -n "${ROWS[i]//[[:space:]]/}" ] || [ -z "${line//[[:space:]]/}" ] || echo "$label: a blank row"
        [ "$i" -eq $(( n - 1 )) ] || [ "${ROWS[i]}" = "${ROWS[i]%[[:space:]]}" ] || echo "$label: a row ends with a space: ${ROWS[i]}"
    done
    [ "$(squash "$joined")" = "$(squash "$line")" ] || echo "$label: the words changed"
}
# corpus WIDTHS EVEN_WIDTHS [KEY]: every message, or only KEY
corpus() {
    local lang key text line w
    local -a keys=() plain=() even=()
    for lang in es en; do
        APP_LANG="$lang"
        if [ "$lang" = es ]; then keys=("${!MSG_ES[@]}"); else keys=("${!MSG_EN[@]}"); fi
        for key in "${keys[@]}"; do
            [ -z "${3-}" ] || [ "$key" = "$3" ] || continue
            printf -v text "%b" "$(msg "$key")"
            while IFS= read -r line; do
                for w in $1; do
                    wrap_line "$w" "$line"; ROWS=("${WRAP_ROWS[@]}")
                    audit "$lang/$key/$w" "$w" "$line"
                done
                for w in $2; do
                    wrap_line "$w" "$line"; plain=("${WRAP_ROWS[@]}")
                    mapfile -t even < <(printf "%s\n" "$line" | wrap_even "$w")
                    ROWS=("${even[@]}"); audit "$lang/$key/$w even" "$w" "$line"
                    [ "${#even[@]}" -eq "${#plain[@]}" ] || echo "$lang/$key/$w even: ${#even[@]} rows, the plain wrap has ${#plain[@]}"
                    if [ "${#even[@]}" -gt 1 ] && [ "$(nwords "${even[${#even[@]}-1]}")" -lt "$(nwords "${plain[${#plain[@]}-1]}")" ]; then
                        echo "$lang/$key/$w even: a last row with fewer words than the plain wrap gives"
                    fi
                done
            done <<< "$text"
        done
    done
}'

echo "-- wrap_line: exact samples"
new_sandbox
wl 12 'one two three four five'
check_eq 'a line breaks at the spaces' 'one two|three four|five' "$OUT"
wl 10 'abcdefghijklmnopqrstuvwxyz'
check_eq 'a word longer than the width is cut at the width' 'abcdefghij|klmnopqrst|uvwxyz' "$OUT"
wl 20 '  alpha beta gamma delta epsilon'
check_eq 'the continuation keeps the indentation of its line' '  alpha beta gamma|  delta epsilon' "$OUT"
wl 40 '  TAB      moves between the buttons and the list of things'
check_eq 'a key and its explanation: the continuation goes under the explanation' \
    '  TAB      moves between the buttons and|           the list of things' "$OUT"
wl 30 '  TAB      moves between buttons and lists'
check_eq 'with fewer than 20 columns left for the explanation the continuation goes under the key' \
    '  TAB      moves between|  buttons and lists' "$OUT"
wl 30 ' 1  name   explanation that is long enough to wrap around'
check_eq 'a table line with one space in front does not hang' ' 1  name   explanation that is| long enough to wrap around' "$OUT"
wl 30 '  key  explanation (two spaces after key) text text text text'
check_eq 'a key followed by only two spaces does not hang' \
    '  key  explanation (two spaces|  after key) text text text|  text' "$OUT"
wl 30 '  averyveryveryverylongkeyword   explanation text that is long'
check_eq 'a key longer than 12 characters does not hang' \
    '  averyveryveryverylongkeyword|  explanation text that is|  long' "$OUT"
printf -v SP17 '%*s' 17 ''
wl 40 '  abcdefghijkl   moves between the buttons and the list of things'
check_eq 'a key of exactly 12 characters hangs: the continuation goes under the explanation' \
    "  abcdefghijkl   moves between the|${SP17}buttons and the list of|${SP17}things" "$OUT"
wl 40 '  abcdefghijklm   moves between the buttons and the list of things'
check_eq 'a key of 13 characters does not hang' \
    '  abcdefghijklm   moves between the|  buttons and the list of things' "$OUT"
wl 30 '            alpha beta gamma delta epsilon zeta'
check_eq 'an indentation wider than a third of the width is not repeated' '            alpha beta gamma|delta epsilon zeta' "$OUT"
wl 33 '             alpha beta gamma delta epsilon zeta'
check_eq 'but a wide indentation that leaves 20 columns for the text is repeated' '             alpha beta gamma|             delta epsilon zeta' "$OUT"
wl 32 '             alpha beta gamma delta epsilon zeta'
check_eq 'and one column less (19 left) it is not' '             alpha beta gamma|delta epsilon zeta' "$OUT"
wl 27 '         alpha beta gamma delta epsilon zeta'
check_eq 'an indentation of exactly a third of the width is not wider than a third: it is repeated' '         alpha beta gamma|         delta epsilon zeta' "$OUT"
printf -v SP21 '%*s' 21 ''
wl 21 "${SP21}--keep-records  deletes the settings"
check_eq 'leading spaces as wide as the width would be a row of their own: the line starts at the first column' \
    '--keep-records|deletes the settings' "$OUT"
app_eval 'for w in $(seq 10 40); do wrap_line "$w" "${SP}--keep-records  deletes the settings"; for r in "${WRAP_ROWS[@]}"; do [ -n "${r//[[:space:]]/}" ] || echo "width $w: a blank row"; [ "${#r}" -le "$w" ] || echo "width $w: ${#r} columns"; done; done' SP="$SP21"
check_eq 'a line indented 21 columns has no blank row and no row too wide at any width from 10 to 40' '' "$OUT"
app_eval 'wrap_line 10 "$T"; printf "%s|%s" "${#WRAP_ROWS[@]}" "${WRAP_ROWS[0]}"' T="$(printf '%*s' 30 '')"
check_eq 'a line of spaces wider than the width is one empty row' '1|' "$OUT"
app_eval 'wrap_line 10 "$T"; printf "%s|%s" "${#WRAP_ROWS[@]}" "${WRAP_ROWS[0]}"' T="$(printf '%*s' 10 '')"
check_eq 'and so is one exactly as wide as the width' '1|' "$OUT"
printf -v SP20 '%*s' 20 ''
wl 21 "${SP20}--keep-records  deletes the settings"
check_eq 'spaces that leave no room for the first word are dropped too: the word is not split by its own indentation' \
    '--keep-records|deletes the settings' "$OUT"
app_eval 'for sp in 20 21; do printf -v S "%*s" "$sp" ""; for w in $(seq 14 40); do wrap_line "$w" "${S}--keep-records  deletes the settings"; r="${WRAP_ROWS[0]#"${WRAP_ROWS[0]%%[![:space:]]*}"}"; [ "${r%% *}" = "--keep-records" ] || echo "indent $sp, width $w: ${WRAP_ROWS[0]}"; done; done'
check_eq 'a word that fits the width stays whole at any width from 14 to 40, with 20 or 21 spaces in front' '' "$OUT"
wl 14 '  --keep-records  deletes it'
check_eq 'a word exactly as wide as the width is not split by its own indentation either' '--keep-records|deletes it' "$OUT"
wl 30 "     $(printf 'x%.0s' $(seq 27)) aa bb cc dd ee ff"
check_eq 'a dropped indentation is not repeated on the continuation either' "$(printf 'x%.0s' $(seq 27)) aa|bb cc dd ee ff" "$OUT"
printf -v SP13 '%*s' 13 ''
wl 30 "${SP13}$(printf 'x%.0s' $(seq 40))"
check_eq 'an indentation that is not repeated is not a row of its own before a word longer than the width: the word is cut after it' \
    "${SP13}$(printf 'x%.0s' $(seq 17))|$(printf 'x%.0s' $(seq 23))" "$OUT"
printf -v SP8 '%*s' 8 ''
wl 31 "  TAB   $(printf 'a%.0s' $(seq 30))"
check_eq 'a key whose explanation starts with a word longer than the width is not left alone on its row: the word is cut after it' \
    "  TAB   $(printf 'a%.0s' $(seq 23))|${SP8}$(printf 'a%.0s' $(seq 7))" "$OUT"
wl 5 'abc def ghi jkl'
check_eq 'a width under 10 works as 10' 'abc def|ghi jkl' "$OUT"
wl 30 ''
check_eq 'an empty line is an empty row' '' "$OUT"
app_eval 'wrap_line 30 ""; printf "%s" "${#WRAP_ROWS[@]}"'
check_eq 'and exactly one' 1 "$OUT"
wl 30 'a line that fits '
check_eq 'a line that fits is left as it is' 'a line that fits ' "$OUT"
wl 12 'one two thre'
check_eq 'a line exactly as wide as the width is not wrapped' 'one two thre' "$OUT"
wl 12 'one two three'
check_eq 'one column more and it is' 'one two|three' "$OUT"
wl 10 'abcdefghij  '
check_eq 'spaces at the end that fall on the break are not a row of their own' 'abcdefghij' "$OUT"
wl 12 '  abcdefghij    '
check_eq 'nor are they when the line is indented' '  abcdefghij' "$OUT"
# A path breaks after the last slash that fits when the name after it fits whole on a row; otherwise at the width.
wl 20 '/home/ana/state/removal-001.txt'
check_eq 'a path breaks after the last slash that fits: its names stay whole' '/home/ana/state/|removal-001.txt' "$OUT"
wl 16 '/home/ana/state/removal-001.txt'
check_eq 'a slash in the last column that fits ends the row' '/home/ana/state/|removal-001.txt' "$OUT"
wl 15 '/home/ana/state/removal-001.txt'
check_eq 'one column less that slash does not fit: the row ends at the one before; a name as wide as the row is whole' \
    '/home/ana/|state/|removal-001.txt' "$OUT"
wl 12 '/srv/averyveryverylongname.txt'
check_eq 'a name wider than a row is cut at the width, like any long word' '/srv/averyve|ryverylongna|me.txt' "$OUT"
wl 12 '/averyveryverylongname'
check_eq 'a slash with nothing before it is not a row of its own: the word is cut at the width' '/averyveryve|rylongname' "$OUT"
wl 20 '  /abcdefghijklmnopqr/stu'
check_eq 'a slash right after the indentation is not a break: nothing precedes it, so the row is not left with only the slash' \
    '  /abcdefghijklmnopq|  r/stu' "$OUT"
wl 20 '  /home/ana/state/removal-001.txt'
check_eq 'a path keeps the indentation of its line on the continuation' '  /home/ana/state/|  removal-001.txt' "$OUT"
wl 20 'see /home/ana/state/removal-001.txt now'
check_eq 'a path after other words starts its own row, and what follows it stays with its last name' \
    'see|/home/ana/state/|removal-001.txt now' "$OUT"
printf -v X40 '%*s' 40 ''; X40="${X40// /x}"
wl 40 "  /usr/bin   $X40"
check_eq 'a slash in the key of a key and explanation line is not a break: the word is cut at the width' \
    "  /usr/bin   ${X40:0:27}|${SP13}${X40:0:13}" "$OUT"
wl 40 '  --out      /var/lib/mintapp/records/removal-0001.txt'
check_eq 'a path in the explanation of a key breaks after a slash and hangs under the explanation' \
    "  --out      /var/lib/mintapp/records/|${SP13}removal-0001.txt" "$OUT"

echo "-- wrap_text: every line apart, blank lines kept"
new_sandbox
app_eval 'printf "alpha\n\nbeta gamma delta\n" | wrap_text 10'
check_eq 'a blank line stays and each line wraps on its own' $'alpha\n\nbeta gamma\ndelta' "$OUT"
app_eval 'printf "no newline at the end" | wrap_text 10'
check_eq 'a last line without a newline is wrapped too' $'no newline\nat the end' "$OUT"

echo "-- wrap_even: exact samples and the long word"
new_sandbox
we 30 'aaaa bbbb cccc dddd eeee ffff gggg'
check_eq 'a last row of one word is evened out: three words on it' 'aaaa bbbb cccc dddd|eeee ffff gggg' "$OUT"
we 30 'alpha beta gamma delta epsilon zeta eta theta iota kappa'
check_eq 'a last row of three words or more is left as it is' 'alpha beta gamma delta epsilon|zeta eta theta iota kappa' "$OUT"
we 21 'aaaa bbbb cccc dddddd e f g'
check_eq 'a last row of exactly three words is left as it is, though one column less would move a word down to it' \
    'aaaa bbbb cccc dddddd|e f g' "$OUT"
we 24 'aaaa bbbb cccc dddd eeee ffff'
check_eq 'if no width of 20 or more gives three words, the plain wrap stays' 'aaaa bbbb cccc dddd eeee|ffff' "$OUT"
we 20 'aaaa bbbb cccc dddd eeee ffff'
check_eq 'it never narrows under 20 columns' 'aaaa bbbb cccc dddd|eeee ffff' "$OUT"
we 40 'short text'
check_eq 'a line of one row is left as it is' 'short text' "$OUT"
we 45 '  --gui            Abre las ventanas (zenity), aunque haya terminal.'
check_eq 'narrowing stops where the hanging indent would be lost: the layout of the key stays' \
    '  --gui            Abre las ventanas|                   (zenity), aunque haya|                   terminal.' "$OUT"
we 30 '  indented description that needs two rows at least here'
check_eq 'the indentation stays' '  indented description that|  needs two rows at least here' "$OUT"
we 25 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz and then a few more words'
check_eq 'a word wider than the width is cut like the plain wrap does' \
    'abcdefghijklmnopqrstuvwxy|z0123456789abcdefghijklmn|opqrstuvwxyz and then a|few more words' "$OUT"
LONG=abcdefghijklmnopqrstuvwxyz0123456789
# The output goes to a variable, not into "grep -q": it leaves at the first match, the writer then gets SIGPIPE and the
# program's pipefail turns that into a false "cut" whenever the machine is busy.
app_eval 'for w in $(seq 36 60); do out="$(printf "%s\n" "one two three $LONG four five six seven eight nine ten" | wrap_even "$w")"; [[ "$out" == *"$LONG"* ]] || echo "width $w: the long word was cut"; done' LONG="$LONG"
check_eq 'a word the plain wrap keeps whole is never cut by narrowing (widths 36 to 60)' '' "$OUT"
# The floor of narrowing: the longest word with the indentation of its line, and never under 20 columns. The path
# has 34 characters; each sample ends with two words, so the plain wrap asks to be evened out and only the floor stops it.
P34=/home/u/.local/bin/mintapp-remover
we 34 "Command $P34 installed ok"
check_eq 'a path that fits whole is not cut by narrowing: the floor is the longest word' "Command|$P34|installed ok" "$OUT"
we 36 "  Command  $P34 installed ok"
check_eq 'the floor counts the indentation: the path and its two spaces fit in 36 columns, not in 35' \
    "  Command|  $P34|  installed ok" "$OUT"
app_eval 'for w in $(seq 26 50); do out="$(printf "%s\n" "  a b $LONG d e" | wrap_even "$w")"; [[ "$out" == *"$LONG"* ]] || echo "width $w: the long word was cut"; done' LONG=xxxxxxxxxxxxxxxxxxxxxxxx
check_eq 'with an indentation too, narrowing never cuts a word the plain wrap kept whole (widths 26 to 50)' '' "$OUT"
we 24 '  aaaa bbbb cccc dddd eeee ffff'
check_eq 'narrowing keeps the indentation: the last row gets three words' '  aaaa bbbb cccc|  dddd eeee ffff' "$OUT"
we 24 '  aaa bbb ccc ddd eee fff'
check_eq 'with an indentation it stops at 20 columns too: no width of 20 or more gives three words, the plain wrap stays' \
    '  aaa bbb ccc ddd eee|  fff' "$OUT"

echo "-- every message wraps cleanly (ASCII, both languages)"
new_sandbox
app_eval "$CORPUS"$'\ncorpus "80 70 60 45 30" "80 45"' MINTAPP_ASCII=1
check_eq 'no row is wider than its width, no word changes, no blank row, no space at the end of a row (80 to 30 columns)' \
    '' "$(printf '%s\n' "$OUT" | head -n 5)"

echo "-- every message wraps cleanly (accents and symbols, both languages)"
new_sandbox
if [ -z "$UTF8" ]; then
    skip_case 'the system has no C.UTF-8 locale: widths cannot be counted in characters'
else
    app_eval "$CORPUS"$'\ncorpus "80 70 60 45 30" "80 45"' MINTAPP_ASCII=0 LC_ALL="$UTF8"
    check_eq 'the same, with accents and symbols counted as one column each' '' "$(printf '%s\n' "$OUT" | head -n 5)"
fi

echo "-- the help of the program (--help) wraps cleanly from 21 to 45 columns"
new_sandbox
# Its option lines are indented up to 21 columns, so this is where indentation and width meet: at 21 columns the
# spaces of three lines fill the whole row. The program prints --help as it is; the layout functions must hold anyway.
app_eval "$CORPUS"$'\ncorpus "$(seq 21 45)" "$(seq 21 45)" usage' MINTAPP_ASCII=1
check_eq 'the help, wrapped and evened out at every width from 21 to 45: nothing too wide, no word changed, no blank row, no space at the end of a row' \
    '' "$(printf '%s\n' "$OUT" | head -n 5)"
if [ -z "$UTF8" ]; then
    skip_case 'the system has no C.UTF-8 locale: widths cannot be counted in characters'
else
    app_eval "$CORPUS"$'\ncorpus "$(seq 21 45)" "$(seq 21 45)" usage' MINTAPP_ASCII=0 LC_ALL="$UTF8"
    check_eq 'the same with accents and symbols counted as one column each' '' "$(printf '%s\n' "$OUT" | head -n 5)"
fi
# The audit looks at the rows of the help, so it must have seen those lines: three of 21 spaces in each language.
for lang in es en; do
    app_eval 'msgf_v t usage x; n=0; while IFS= read -r l; do case "$l" in "                     --"*) n=$((n + 1)) ;; esac; done <<< "$t"; printf "%s" "$n"' MINTAPP_LANG="$lang"
    check_eq "the help in $lang has the three lines indented 21 columns that the audit needs" 3 "$OUT"
done

echo "-- the descriptions of the cleaning wrap well where the menus and the checklist print them"
new_sandbox
# Every clean_*_desc, in both languages, as the checklist prints it (text_wrap_even, 8 spaces in front) and as the
# menus do (wrap_even to the text width minus 5). One output line per problem, then the count of descriptions
# and how many of them needed more than one row. With STRICT=1 (80 and 60 columns) none may end with one or two
# words alone: the plain wrap leaves 9 to 21 of them so; under 60 columns some cannot be evened out.
DESC_AUDIT='
squash() { local t="${1//[[:space:]]/}"; printf "%s" "$t"; }
nwords() { local -a w; read -ra w <<< "$1"; printf "%s" "${#w[@]}"; }
set_text_width
n=0 long=0
for lang in es en; do
    APP_LANG="$lang"
    if [ "$lang" = es ]; then keys=("${!MSG_ES[@]}"); else keys=("${!MSG_EN[@]}"); fi
    for key in "${keys[@]}"; do
        case "$key" in clean_*_desc) ;; *) continue ;; esac
        n=$(( n + 1 )); desc="$(msg "$key")"
        label="$lang/$key"
        mapfile -t rows < <(text_wrap_even "        $desc")
        wrap_line "$TEXT_W" "        $desc"; plain=("${WRAP_ROWS[@]}")
        [ "${#rows[@]}" -le 1 ] || long=$(( long + 1 ))
        for row in "${rows[@]}"; do
            [ "${#row}" -le "$TEXT_W" ] || echo "$label checklist: ${#row} columns: $row"
            [ "${row:0:8}" = "        " ] || echo "$label checklist: a row without its indentation: $row"
        done
        [ "$(squash "${rows[*]}")" = "$(squash "$desc")" ] || echo "$label checklist: the words changed"
        [ "${#rows[@]}" -eq "${#plain[@]}" ] || echo "$label checklist: ${#rows[@]} rows, the plain wrap has ${#plain[@]}"
        if [ "${#rows[@]}" -gt 1 ] && [ "$(nwords "${rows[${#rows[@]}-1]}")" -lt "$(nwords "${plain[${#plain[@]}-1]}")" ]; then
            echo "$label checklist: a last row with fewer words than the plain wrap gives"
        fi
        [ "${STRICT:-0}" != 1 ] || [ "${#rows[@]}" -le 1 ] || [ "$(nwords "${rows[${#rows[@]}-1]}")" -ge 3 ] || echo "$label checklist: the last row has fewer than three words: ${rows[${#rows[@]}-1]}"
        mapfile -t rows < <(printf "%s\n" "$desc" | wrap_even $(( TEXT_W - 5 )))
        [ "${STRICT:-0}" != 1 ] || [ "${#rows[@]}" -le 1 ] || [ "$(nwords "${rows[${#rows[@]}-1]}")" -ge 3 ] || echo "$label menu: the last row has fewer than three words: ${rows[${#rows[@]}-1]}"
        for row in "${rows[@]}"; do
            [ "${#row}" -le $(( TEXT_W - 5 )) ] || echo "$label menu: ${#row} columns: $row"
        done
        [ "$(squash "${rows[*]}")" = "$(squash "$desc")" ] || echo "$label menu: the words changed"
    done
done
echo "descriptions $n, wrapped $long"'
for cols in 80 60 45 40; do
    app_eval "$DESC_AUDIT" COLUMNS="$cols" MINTAPP_ASCII=1 STRICT="$([ "$cols" -ge 60 ] && echo 1 || echo 0)"
    check_eq "cleaning descriptions at $cols columns: no row too wide, no word changed, the indentation kept$([ "$cols" -ge 60 ] && echo ', no last row of one or two words')" '' "$(printf '%s\n' "$OUT" | grep -v '^descriptions ' | head -n 5)"
    summary="$(printf '%s\n' "$OUT" | grep '^descriptions ')"
    check_eq "and the audit saw all 42 descriptions ($cols columns)" 'descriptions 42' "${summary%, wrapped*}"
done
check_eq 'at 40 columns most of them need more than one row, so the audit is not empty' yes \
    "$([ "${summary##* }" -ge 20 ] && echo yes || echo "$summary")"
# The audit sets the width itself before it calls text_wrap_even; here the terminal is resized between two calls.
app_eval 'COLUMNS=80 set_text_width; text_wrap_even "$T"' COLUMNS=40 T='aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj'
check_eq 'text_wrap_even reads the width of the terminal each time it is called, and evens out the last row' \
    $'aaaa bbbb cccc dddd eeee ffff gggg\nhhhh iiii jjjj' "$OUT"

echo "-- the help of whiptail fits its box"
new_sandbox
for lang in es en; do
    for ascii in 0 1; do
        app_eval "APP_LANG=$lang; printf '%b\n' \"\$(msg nav_whiptail)\" \"\$(msg nav_zoom)\"" MINTAPP_ASCII="$ascii" LC_ALL="${UTF8:-C}"
        check_eq "no line of the help of whiptail is wider than its 70 columns ($lang, ASCII $ascii)" '' "$(printf '%s\n' "$OUT" | lines_wider 70)"
    done
done

echo "-- text_bullet, text_entry, text_option, text_prompt and wrap_prompt"
new_sandbox
app_eval 'text_bullet "A long bullet text that surely needs more than one row to be shown on a narrow screen of forty columns"' COLUMNS=40
check_eq 'a bullet: the dash on the first row, the rest under the text' \
    $'  - A long bullet text that surely\n    needs more than one row to be shown\n    on a narrow screen of forty columns' "$OUT"
app_eval 'text_entry 3 "$SYM_ON" "VLC media player that has a long name" vlc 1; text_entry 4 "$SYM_OFF" "Short" pkg 0; text_entry 5 "$SYM_OFF" "Without label" "" 0' COLUMNS=40 NO_COLOR=1
check_eq 'an entry without color: number, mark, name and label; the rest under the name' \
    $'  3)  [x] VLC media player that has \n         a long name vlc \n  4) [ ] Short pkg\n  5) [ ] Without label' "$OUT"
app_eval 'text_entry 3 "$SYM_ON" "VLC media player that has a long name" vlc 1; text_entry 4 "$SYM_OFF" "Short" pkg 0' COLUMNS=40
check_eq 'a marked entry is a solid block on every row; an unmarked one shows its label in the title color' \
    "  3) ${ESC}[1;30;42m [x] VLC media player that has ${ESC}[0m"$'\n'"        ${ESC}[1;30;42m a long name vlc ${ESC}[0m"$'\n'"  4) [ ] Short ${ESC}[1;34mpkg${ESC}[0m" "$OUT"
# The label is colored only on the row that ends with it (the name above has none), and an entry without a label has no
# color at all.
app_eval 'text_entry 4 "$SYM_OFF" "A name long enough to need two rows here" pkg 0' COLUMNS=40
check_eq 'an unmarked entry of two rows: the label in the title color on the row that ends with it, nothing on the first' \
    "  4) [ ] A name long enough to"$'\n'"        need two rows here ${ESC}[1;34mpkg${ESC}[0m" "$OUT"
app_eval 'text_entry 5 "$SYM_OFF" "Without label" "" 0' COLUMNS=40
check_eq 'an unmarked entry without a label has no color sequence, not even an empty one' '  5) [ ] Without label' "$OUT"
app_eval 'text_option 3 "Label"; text_prompt "Choice:"' NO_COLOR=1
check_eq 'an option and a prompt without color' $'3. Label\nChoice: ' "$OUT"
app_eval 'text_option 3 "Label"; text_prompt "Choice:"'
check_eq 'an option: the key in green and the label in bold; a prompt: green, and the space after it is not' \
    "${ESC}[1;32m3.${ESC}[0m ${ESC}[1mLabel${ESC}[0m"$'\n'"${ESC}[1;32mChoice:${ESC}[0m " "$OUT"
app_eval 'wrap_prompt "Do you really want to remove everything that was selected? [y/N]:"; printf "<%s>" "$PROMPT_LAST"' COLUMNS=40
check_eq 'a long prompt: all rows but the last are printed, the last is left for read -p' \
    $'Do you really want to remove\n<everything that was selected? [y/N]:>' "$OUT"
# The space that ends a prompt goes back after the wrapping. At 40 columns the rows are 38 wide, and 37 when the last
# one plus the space would reach the last column. P38 is a row of exactly 38.
P38='aaaa bbbb cccc dddd eeee ffff gggggggg'
app_eval 'wrap_prompt "Choice: "; printf "<%s>" "$PROMPT_LAST"' COLUMNS=40
check_eq 'a prompt that fits on one row keeps the one space that ends it, not two' '<Choice: >' "$OUT"
app_eval 'wrap_prompt "$T "; printf "<%s>" "$PROMPT_LAST"' COLUMNS=40 T="$P38"
check_eq 'a last row of 38 and the space would reach the last column: wrapped again one column narrower, no word lost' \
    $'aaaa bbbb cccc dddd eeee ffff\n<gggggggg >' "$OUT"
app_eval 'wrap_prompt "$T hhhh iiii: "; printf "<%s>" "$PROMPT_LAST"' COLUMNS=40 T="$P38"
check_eq 'with the space and a short last row, the rows before it keep the full width' \
    $'aaaa bbbb cccc dddd eeee ffff gggggggg\n<hhhh iiii: >' "$OUT"
app_eval 'wrap_prompt "$T"; printf "<%s>" "$PROMPT_LAST"' COLUMNS=40 T="$P38"
check_eq 'without a space at the end there is nothing to make room for: a row of 38 stays' "<$P38>" "$OUT"
# Every width from 40 to 100 (the interval where a prompt can end exactly at the break): the prompt keeps the
# space that ends it, and no row is empty.
app_eval 'for lang in es en; do APP_LANG="$lang"; for cols in $(seq 40 100); do for key in confirm_plan_text confirm_plan_meta_text clean_confirm_text; do TERM_COLS=$cols; set_text_width() { TEXT_W=$((cols - 1)); [ "$TEXT_W" -le 100 ] || TEXT_W=100; }; wrap_prompt "$(msg "$key")" > /dev/null; [ -n "${PROMPT_LAST//[[:space:]]/}" ] || echo "$lang/$key/$cols: the last row is blank"; case "$PROMPT_LAST" in *" ") ;; *) echo "$lang/$key/$cols: the prompt lost its last space" ;; esac; [ "${#PROMPT_LAST}" -le $((cols - 2)) ] || echo "$lang/$key/$cols: the last row of ${#PROMPT_LAST} leaves no room to type"; done; done; done' MINTAPP_ASCII=1
check_eq 'a confirmation prompt keeps its last space and leaves room to type at any width from 40 to 100' '' "$(printf '%s\n' "$OUT" | head -n 5)"
for cols in 80 60 45 40; do
    for lang in es en; do
        app_eval "APP_LANG=$lang; wrap_prompt \"\$(msg confirm_plan_text)\" > /dev/null; printf '%s %s' \"\${#PROMPT_LAST}\" \"\$TEXT_W\"" COLUMNS="$cols"
        read -r last width <<< "$OUT"
        check_eq "the last row of the confirmation prompt leaves room to type ($lang, $cols columns)" 1 "$([ "$last" -le $((width - 1)) ] && echo 1 || echo 0)"
    done
done

echo "-- the navigation help of the text mode: text_bullet and the hanging indent on the real texts"
new_sandbox
# The two bullets of the help (nav_text_1 and nav_text_2): the dash opens the first row, every other row starts at
# 4 columns, under the text; no row reaches the edge; no word is lost or repeated. One output line per problem, then
# the number of rows of each bullet.
BULLET_AUDIT='
squash() { local t="${1//[[:space:]]/}"; printf "%s" "$t"; }
set_text_width
for key in nav_text_1 nav_text_2; do
    text="$(msg "$key")"
    mapfile -t rows < <(text_bullet "$text")
    joined=""
    for i in "${!rows[@]}"; do
        row="${rows[i]}"
        if [ "$i" -eq 0 ]; then
            [[ "$row" == "  - "[![:space:]]* ]] || echo "$key: the first row does not open with the dash: $row"
        else
            [[ "$row" == "    "[![:space:]]* ]] || echo "$key: row $(( i + 1 )) is not at 4 columns: $row"
        fi
        [ "${#row}" -le "$TEXT_W" ] || echo "$key: ${#row} columns: $row"
        joined+="${row:4}"
    done
    [ "$(squash "$joined")" = "$(squash "$text")" ] || echo "$key: the words changed"
    echo "$key rows ${#rows[@]}"
done'
for lang in es en; do
    for cols in 80 60 45; do
        case "$cols" in 80) want_rows=$'nav_text_1 rows 1\nnav_text_2 rows 3' ;; 60) want_rows=$'nav_text_1 rows 2\nnav_text_2 rows 4' ;; *) want_rows=$'nav_text_1 rows 2\nnav_text_2 rows 5' ;; esac
        app_eval "$BULLET_AUDIT" MINTAPP_LANG="$lang" COLUMNS="$cols" LC_ALL="${UTF8:-C}"
        check_eq "the bullets of the help: dash, text at 4 columns, nothing at the edge, no word lost, and the rows they take ($lang, $cols columns)" "$want_rows" "$OUT"
    done
done
app_eval 'text_bullet "$(msg nav_text_2)"' MINTAPP_LANG=es COLUMNS=45 LC_ALL="${UTF8:-C}"
check_eq 'the second bullet in Spanish at 45 columns: the continuation under the text, five rows' \
    $'  - En las pantallas de selección múltiple:\n    escribe el número de una aplicación para\n    marcarla/desmarcarla (se resaltará en\n    verde); luego escribe \'c\' para confirmar\n    o \'0\' para volver atrás.' "$OUT"
app_eval 'text_bullet "$(msg nav_text_2)"' MINTAPP_LANG=en COLUMNS=60
check_eq 'the second bullet in English at 60 columns' \
    $'  - On multi-selection screens: type the number of an\n    application to mark or unmark it (it will be\n    highlighted in green), then type \'c\' to confirm or \'0\'\n    to go back.' "$OUT"

# The help of whiptail is a table of keys: the explanation of a key goes on after 13 columns, and so must its
# continuation, whatever the width (33 is the narrowest where 20 columns are left for it). Each line of the text is
# wrapped on its own, as wrap_text does, and the rows after the first are looked at: under a key or under the
# indented line that goes on explaining it, they start at column 13; in the closing paragraph, at column 0.
HELP_AUDIT='
squash() { local t="${1//[[:space:]]/}"; printf "%s" "$t"; }
text="$(printf "%b" "$(msg nav_whiptail)")"
for w in $(seq 33 70); do
    joined=""
    while IFS= read -r line; do
        wrap_line "$w" "$line"
        for i in "${!WRAP_ROWS[@]}"; do
            row="${WRAP_ROWS[i]}"
            joined+="$row"
            [ "${#row}" -le "$w" ] || echo "$w: ${#row} columns: $row"
            [ "$i" -gt 0 ] || continue
            case "$line" in
                " "*) [[ "$row" == "             "[![:space:]]* ]] || echo "$w: a continuation that is not under the explanation: $row" ;;
                *) [[ "$row" == [![:space:]]* ]] || echo "$w: a continuation of the closing paragraph that is indented: $row" ;;
            esac
        done
    done <<< "$text"
    [ "$(squash "$joined")" = "$(squash "$text")" ] || echo "$w: the words changed"
done'
for lang in es en; do
    for ascii in 0 1; do
        app_eval "$HELP_AUDIT" MINTAPP_LANG="$lang" MINTAPP_ASCII="$ascii" LC_ALL="${UTF8:-C}"
        check_eq "the help of whiptail from 33 to 70 columns: every continuation under its explanation, no row too wide, no word lost ($lang, ASCII $ascii)" '' "$(printf '%s\n' "$OUT" | head -n 5)"
    done
done
for lang in es en; do
    app_eval 'printf "%b\n" "$(msg nav_whiptail)" | wrap_text 70' MINTAPP_LANG="$lang" LC_ALL="${UTF8:-C}"
    want="$OUT"
    app_eval 'printf "%b" "$(msg nav_whiptail)"' MINTAPP_LANG="$lang" LC_ALL="${UTF8:-C}"
    check_eq "at 70 columns the help of whiptail is not wrapped at all: the text as it is ($lang)" "$OUT" "$want"
done
app_eval 'printf "%b\n" "$(msg nav_whiptail)" | wrap_text 51' MINTAPP_LANG=es LC_ALL="${UTF8:-C}"
check_eq 'the help of whiptail in Spanish at 51 columns: the continuations under the explanations' \
    $'  ↑ / ↓      Moverse por la lista de opciones.\n  ESPACIO    Marcar o desmarcar una aplicación\n             (listas con casillas).\n  TAB        Cambiar el foco entre la lista y los\n             botones.\n             Algunos botones NO se activan hasta\n             llevarles el foco.\n  ENTER      Confirmar la opción o el botón\n             resaltado.\n\nEscribir el número de una opción NO la elige: usa\nsiempre las flechas.' "$OUT"
app_eval 'printf "%b\n" "$(msg nav_whiptail)" | wrap_text 37' MINTAPP_LANG=es LC_ALL="${UTF8:-C}"
check_eq 'the same at 37 columns: the line that goes on under TAB keeps its 13 columns (24 are left for the text)' \
    $'  ↑ / ↓      Moverse por la lista de\n             opciones.\n  ESPACIO    Marcar o desmarcar una\n             aplicación (listas con\n             casillas).\n  TAB        Cambiar el foco entre la\n             lista y los botones.\n             Algunos botones NO se\n             activan hasta llevarles\n             el foco.\n  ENTER      Confirmar la opción o el\n             botón resaltado.\n\nEscribir el número de una opción NO\nla elige: usa siempre las flechas.' "$OUT"
app_eval 'printf "%b\n" "$(msg nav_whiptail)" | wrap_text 37' MINTAPP_LANG=en LC_ALL="${UTF8:-C}"
check_eq 'and in English at 37 columns' \
    $'  ↑ / ↓      Move through the list of\n             options.\n  SPACE      Mark or unmark an\n             application (on checkbox\n             screens).\n  TAB        Move focus between the\n             list and the buttons.\n             Some buttons CANNOT be\n             activated until focus is\n             on them.\n  ENTER      Confirm the highlighted\n             option or button.\n\nTyping an option number does NOT\nselect it: always use the arrow keys.' "$OUT"
# The tables that a package manager prints start in the first column or after one space: no key, no hanging indent.
app_eval 'wrap_line 40 "$L"; IFS="|"; printf "%s" "${WRAP_ROWS[*]}"' L=' vlc-plugins-extra   x86_64   3.0.20-1.fc40   fedora-updates   1.2 M'
check_eq 'a table row of dnf (one space in front) keeps that one space on its continuation' ' vlc-plugins-extra   x86_64| 3.0.20-1.fc40   fedora-updates   1.2 M' "$OUT"
app_eval 'wrap_line 40 "$L"; IFS="|"; printf "%s" "${WRAP_ROWS[*]}"' L='vlc          3.0.20-1    a multimedia player that plays everything'
check_eq 'a table row of pacman (first column) does not hang either' 'vlc          3.0.20-1    a multimedia|player that plays everything' "$OUT"

echo "-- text_plan, text_note and the plan and result texts"
new_sandbox
PLAN=$'Reading package lists...\nPurg vlc [3.0]\nRemv libvlc [3.0] and a long line that needs wrapping at forty columns for sure'
app_eval 'text_plan "$P"' COLUMNS=40 P="$PLAN"
check_eq 'the lines that remove something get the warning color, wrapped row by row; the others stay plain' \
    "Reading package lists..."$'\n'"${ESC}[1;33mPurg vlc [3.0]${ESC}[0m"$'\n'"${ESC}[1;33mRemv libvlc [3.0] and a long line that${ESC}[0m"$'\n'"${ESC}[1;33mneeds wrapping at forty columns for${ESC}[0m"$'\n'"${ESC}[1;33msure${ESC}[0m" "$OUT"
app_eval 'text_plan "$P"' COLUMNS=40 NO_COLOR=1 P="$PLAN"
check_eq 'without color the same text, wrapped the same' \
    $'Reading package lists...\nPurg vlc [3.0]\nRemv libvlc [3.0] and a long line that\nneeds wrapping at forty columns for\nsure' "$OUT"
app_eval 'text_plan "$P" all' COLUMNS=40 P=$'flatpak user org.a.b flathub\nsnap system vlc'
check_eq 'with "all" every line is a removal (Flatpak and Snap plans)' \
    "${ESC}[1;33mflatpak user org.a.b flathub${ESC}[0m"$'\n'"${ESC}[1;33msnap system vlc${ESC}[0m" "$OUT"
app_eval 'text_note "$N"' COLUMNS=40 NO_COLOR=1 N=$'First line of a note that is quite long and needs wrapping to fit.\n\n\n/home/user/.local/state/mintapp-remover/removal-2026.txt\n\nlast'
check_eq 'a note wraps its text, keeps a path whole on its row and squeezes blank lines into one' \
    $'First line of a note that is quite long\nand needs wrapping to fit.\n\n/home/user/.local/state/mintapp-remover/removal-2026.txt\n\nlast' "$OUT"
app_eval 'PM=apt; removed_packages_text "$P"; printf "%s\n" "$REPLY"; removed_packages_text "Purg a [1]"; echo "status $?"' MINTAPP_LANG=en \
    P=$'Purg ab-one [1]\nPurg ab-two [1]\nRemv ab-three [1]\nPurg ab-four [1]\nPurg ab-five [1]\nPurg ab-six [1]\nPurg ab-seven [1]\nPurg ab-eight [1]'
assert_contains 'the recap of removed packages counts them all, names the first six (in order) and the rest as a count' "$OUT" 'Removed packages (8): ab-eight, ab-five, ab-four, ab-one, ab-seven, ab-six, +2 more'
assert_contains 'a name that is not valid is not listed: a plan with none has no recap' "$OUT" 'status 1'
app_eval 'removed_stores_text "$P"; printf "%s\n" "$REPLY"; removed_stores_text "nothing"; echo "status $?"' MINTAPP_LANG=en P=$'flatpak user org.a.b flathub\nsnap system vlc'
check_eq 'the recap of removed Flatpak and Snap applications gives their ids' $'Removed applications (2): org.a.b, vlc\nstatus 1' "$OUT"

echo "-- text_plan: the color marks only what is removed, and without it the text is text_wrap's"
new_sandbox
MIXED=$'Reading package lists...\n\nInst ab-new [1]\nConf ab-one\nPurge it all\n Purg indented line\npurg lower\nPurg ab-one [1] and a long line that needs wrapping at forty columns for sure\nRemv ab-two [1]'
for cols in 80 40; do
    app_eval 'text_wrap "$P"' COLUMNS="$cols" NO_COLOR=1 P="$MIXED"
    want="$OUT"
    app_eval 'text_plan "$P"' COLUMNS="$cols" NO_COLOR=1 P="$MIXED"
    check_eq "without color a plan prints exactly what text_wrap prints, blank line included ($cols columns)" "$want" "$OUT"
    app_eval 'text_plan "$P"' COLUMNS="$cols" P="$MIXED"
    check_eq "with color, once its sequences are taken out, it is the same text ($cols columns)" "$want" "$(plain)"
done
app_eval 'text_plan "$P"' COLUMNS=40 P="$MIXED"
colored="$(printf '%s\n' "$OUT" | grep -F "$ESC" | sed -E 's/\x1b\[[0-9;]*m//g')"
check_eq 'the rows with color are those of the Purg and Remv lines: not "Purge", nor an indented or a lowercase one' \
    $'Purg ab-one [1] and a long line that\nneeds wrapping at forty columns for\nsure\nRemv ab-two [1]' "$colored"
check_eq 'every colored row is closed before it ends' 4 "$(printf '%s\n' "$OUT" | grep -c -E "^${ESC}\[1;33m.*${ESC}\[0m\$")"

echo "-- text_note: an empty note, the blank lines and the record path"
new_sandbox
app_eval 'text_note ""; echo "[end]"' COLUMNS=40 NO_COLOR=1
check_eq 'an empty note prints nothing: the pause that follows brings its own blank row' '[end]' "$OUT"
app_eval_in $'\n' 'HAVE_WHIPTAIL=0; show_removal_result 1 "The password was not accepted." ""; echo "[end]"' MINTAPP_LANG=en COLUMNS=60 NO_COLOR=1
check_eq 'a result with no note (password refused) is followed by one blank row, as one with a note is' \
    $'The password was not accepted.\n\n[end]' "$OUT"
app_eval 'text_note "$N"' COLUMNS=40 NO_COLOR=1 N=$'\n\nA note that is quite long and needs wrapping to fit.'
check_eq 'a note that starts with blank lines is set apart from what comes before by a single blank row' \
    $'\nA note that is quite long and needs\nwrapping to fit.' "$OUT"
REC=/home/u/.local/state/mintapp-remover/removal-2026-11-17.txt
for lang in es en; do
    for cols in 80 60 45 40; do
        app_eval 'LAST_RECORD="$R"; text_note "$(record_note_text)"; echo @@; LAST_RECORD=""; text_note "$(record_note_text)"' \
            MINTAPP_LANG="$lang" COLUMNS="$cols" NO_COLOR=1 R="$REC"
        saved="${OUT%%@@*}" failed="${OUT#*@@}"
        check_eq "the record path is whole on a row of its own ($lang, $cols columns)" 1 "$(printf '%s\n' "$saved" | grep -c -x -F -- "$REC")"
        check_eq "no other row of the note reaches the edge ($lang, $cols columns)" '' \
            "$(printf '%s\n' "$saved" | grep -v -F -- "$REC" | lines_wider $((cols - 1)))"
        check_eq "the warning of a record that could not be saved fits too ($lang, $cols columns)" '' \
            "$(printf '%s\n' "$failed" | lines_wider $((cols - 1)))"
    done
done

echo "-- the recap of what was removed: the first six names, the rest counted"
new_sandbox
STORES=$'flatpak user org.a.one flathub\nsnap system vlc\nsnap system aa\nflatpak system org.b.two\nsnap user bad_one\nflatpak user org.c.three\nsnap system bb\nflatpak system org.d.four flathub\nsnap system cc'
app_eval 'removed_stores_text "$P"; printf "%s" "$REPLY"' MINTAPP_LANG=en P="$STORES"
check_eq 'Flatpak and Snap, in the order of the plan: the six first ids, the rest counted, a line that is no application skipped' \
    'Removed applications (8): org.a.one, vlc, aa, org.b.two, org.c.three, bb, +2 more' "$OUT"
app_eval 'removed_stores_text "$P"; printf "%s" "$REPLY"' MINTAPP_LANG=es P=$'snap system vlc\nsnap system aa\nsnap system bb\nsnap system cc\nsnap system dd\nsnap system ee\nsnap system ff'
check_eq 'the same in Spanish: seven applications, six names and one more' 'Aplicaciones eliminadas (7): vlc, aa, bb, cc, dd, ee, +1 mas' "$OUT"
app_eval 'removed_stores_text "$P"; printf "%s" "$REPLY"' MINTAPP_LANG=en P=$'snap system vlc\nsnap system aa\nsnap system bb\nsnap system cc\nsnap system dd\nsnap system ee'
check_eq 'exactly six: all of them and no "more"' 'Removed applications (6): vlc, aa, bb, cc, dd, ee' "$OUT"
app_eval 'removed_stores_text "$P"; echo "status $?"' P=$'whatever\nsnap system Bad_Name\nflatpak user not a valid id'
check_eq 'lines that are no valid application: no recap' 'status 1' "$OUT"
PKGS8=$'Purg ab-one [1]\nPurg ab-two [1]\nRemv ab-three [1]\nPurg ab-four [1]\nPurg ab-five [1]\nPurg ab-six [1]\nPurg ab-seven [1]\nPurg ab-eight [1]'
app_eval 'PM=apt; removed_packages_text "$P"; printf "%s" "$REPLY"' MINTAPP_LANG=es P="$PKGS8"
check_eq 'packages in Spanish: counted, the first six by name, the rest as a count' \
    'Paquetes eliminados (8): ab-eight, ab-five, ab-four, ab-one, ab-seven, ab-six, +2 mas' "$OUT"
app_eval 'PM=apt; removed_packages_text "$P"; printf "%s" "$REPLY"' MINTAPP_LANG=en P=$'Purg ab-one [1]\nPurg ab-two [1]\nPurg ab-three [1]\nPurg ab-four [1]\nPurg ab-five [1]\nPurg ab-six [1]'
check_eq 'packages, exactly six: all of them and no "more"' 'Removed packages (6): ab-five, ab-four, ab-one, ab-six, ab-three, ab-two' "$OUT"
app_eval 'PM=apt; removed_packages_text "$P"; printf "%s" "$REPLY"' MINTAPP_LANG=en P=$'Purg ab-one [1]\nPurg Bad_Name [1]\nRemv ab-two [1]\nPurg -rf [1]'
check_eq 'packages: a name that is not valid is left out of the list and of the count' 'Removed packages (2): ab-one, ab-two' "$OUT"
app_eval 'PM=apt; removed_packages_text "$P"; echo "status $?"' P=$'Purg Bad_Name [1]\nPurg -rf [1]'
check_eq 'packages: none valid, no recap' 'status 1' "$OUT"

echo "-- plan_count_text: each case in both languages, and where the plan screens show it"
new_sandbox
PLAN3=$'Reading package lists...\nPurg ab-one [1]\nPurg ab-two [1]\nRemv ab-three [1]'
PLAN_REPEATED=$'Purg ab-one [1]\nPurg ab-one [2]\nRemv ab-one [3]'
PLAN_OTHER=$'Inst ab-new [1]\nConf ab-one\nPurg ab-one [1]'
COUNT_LABELS=(
    'chosen and dependent' 'a cleaning plan (none chosen): the total only' 'a chosen name that is not in the plan'
    'a chosen name that is only the start of a package name' 'a name given twice counts once' 'a package repeated in the plan counts once'
    'a repeated package and a chosen name that is not in the plan' 'only the Purg and Remv lines count' 'a plan with no package: no count' 'an empty plan: no count')
COUNT_EN=('Packages in the plan: 3 (chosen: 1, dependent: 2).' 'Packages in the plan: 3.' 'Packages in the plan: 3.' 'Packages in the plan: 3.'
    'Packages in the plan: 3 (chosen: 2, dependent: 1).' 'Packages in the plan: 1 (chosen: 1, dependent: 0).' 'Packages in the plan: 1.'
    'Packages in the plan: 1 (chosen: 1, dependent: 0).' 'status 1' 'status 1')
COUNT_ES=('Paquetes en el plan: 3 (elegidos: 1, dependientes: 2).' 'Paquetes en el plan: 3.' 'Paquetes en el plan: 3.' 'Paquetes en el plan: 3.'
    'Paquetes en el plan: 3 (elegidos: 2, dependientes: 1).' 'Paquetes en el plan: 1 (elegidos: 1, dependientes: 0).' 'Paquetes en el plan: 1.'
    'Paquetes en el plan: 1 (elegidos: 1, dependientes: 0).' 'status 1' 'status 1')
for lang in en es; do
    app_eval 'PM=apt
        count() { if plan_count_text "$@"; then printf "%s\n" "$REPLY"; else printf "status %s\n" "$?"; fi; }
        count "$P3" ab-one; count "$P3"; count "$P3" zz-none; count "$P3" ab; count "$P3" ab-one ab-one ab-two
        count "$PREP" ab-one; count "$PREP" ab-two; count "$POTHER" ab-new ab-one; count "Reading package lists..." ab-one; count "" ab-one' \
        MINTAPP_LANG="$lang" P3="$PLAN3" PREP="$PLAN_REPEATED" POTHER="$PLAN_OTHER"
    mapfile -t got <<< "$OUT"
    for i in "${!COUNT_LABELS[@]}"; do
        if [ "$lang" = en ]; then want="${COUNT_EN[i]}"; else want="${COUNT_ES[i]}"; fi
        check_eq "plan count ($lang): ${COUNT_LABELS[i]}" "$want" "${got[i]-}"
    done
done
# review_plan puts the count at the end of the summary, right above the question.
app_eval_in $'n\n' 'PM=apt; review_plan "Intro text" "$P3" "" ab-one' MINTAPP_LANG=en MINTAPP_UI=text COLUMNS=100 P3="$PLAN3"
check_eq 'text screen: the count closes the summary and a blank line follows it' 'Packages in the plan: 3 (chosen: 1, dependent: 2).|' \
    "$(plain | awk '/^Packages in the plan/ { getline next_line; print $0 "|" next_line }')"
fake_answers NO
: > "$SB/state/whiptail.args"
app_eval 'UI_ENGINE=whiptail; HAVE_WHIPTAIL=1; PM=apt; review_plan "Intro text" "$P3" "" ab-one' MINTAPP_LANG=en MINTAPP_UI=whiptail COLUMNS=100 LINES=40 P3="$PLAN3"
check_eq 'whiptail: the question box starts with the count' 'Packages in the plan: 3 (chosen: 1, dependent: 2).' \
    "$(awk 'prev == "--yesno" { print; exit } { prev = $0 }' "$SB/state/whiptail.args" | tr '\036' '\n' | head -n 1)"

echo "-- print_fit and print_fit_path: a terminal wraps, a pipe does not"
new_sandbox
TEXT='This is a message that needs wrapping on a narrow terminal because it is long and says a few things'
app_eval 'print_fit 1 "$T"' T="$TEXT"
check_eq 'into a pipe a message goes out as one line, as it is' "$TEXT" "$OUT"
if [ -z "$HAVE_PTY" ]; then
    skip_case 'no "script" command: the pseudo-terminal cases are skipped'
else
    for cols in 80 60 45; do
        for fd in 1 2; do
            pty_eval "$cols" 'print_fit "$FD" "$T"' T="$TEXT" FD="$fd"
            check_eq "on a terminal of $cols columns no row reaches the edge (fd $fd)" '' "$(printf '%s\n' "$OUT" | lines_wider $((cols - 1)))"
            check_eq "and no word is lost (fd $fd, $cols columns)" "$(squash "$TEXT")" "$(squash "$OUT")"
        done
    done
    # A line exactly as wide as the terminal: the last column is never written on (the terminal would wrap there).
    # Four words follow it so that evening out the last row cannot hide a row that is one column too wide.
    for cols in 80 60 45; do
        edge="$(printf 'abcdefgh %.0s' {1..12})"
        edge="${edge:0:cols}"
        if [ "${edge: -1}" = ' ' ]; then edge="${edge%?}x"; fi
        pty_eval "$cols" 'print_fit 1 "$T"' T="$edge tail one two three"
        check_eq "a line as wide as the terminal ($cols columns) is wrapped before its edge" '' "$(printf '%s\n' "$OUT" | lines_wider $((cols - 1)))"
    done
    P=/home/tester/a/very/long/folder/name/that/is/longer/than/the/screen/mintapp-remover
    pty_eval 40 'print_fit_path 1 "The program was written to $P and is ready to use now." "$P"' P="$P"
    check_eq 'a path wider than the terminal goes whole on its own row, at the first column' \
        $'The program was written to\n'"$P"$'\nand is ready to use now.' "$OUT"
    pty_eval 40 'print_fit_path 1 "Folder: /home/my user/with spaces/x ready." "/home/my user/with spaces/x"'
    check_eq 'a path with spaces goes whole on its own row too' $'Folder:\n/home/my user/with spaces/x\nready.' "$OUT"
    pty_eval 80 'print_fit_path 1 "Written to /home/u/x.txt and ready." "/home/u/x.txt"'
    check_eq 'a path that fits is wrapped like any other text' 'Written to /home/u/x.txt and ready.' "$OUT"
    app_eval 'print_fit_path 1 "The program was written to $P and is ready." "$P"' P="$P"
    check_eq 'into a pipe print_fit_path is print_fit: one line' "The program was written to $P and is ready." "$OUT"
    # The limit: at 40 columns the text is 39 wide. A path of 39 still fits, so the text wraps as print_fit wraps it; one
    # of 40 goes on its own row, and the text before it is wrapped by itself and evened out (its last row gets 3 words).
    P39="$(printf '%*s' 39 '' | tr ' ' p)"
    P40="${P39}p"
    pty_eval 40 'print_fit_path 1 "$T" "$P"' T="Remember that the command lives in the folder named $P39" P="$P39"
    check_eq 'a path as wide as the text width is wrapped like any other text' \
        $'Remember that the command lives in the\nfolder named\n'"$P39" "$OUT"
    pty_eval 40 'print_fit_path 1 "$T" "$P"' T="Remember that the command lives in the folder named $P40" P="$P40"
    check_eq 'a path one column wider goes on its own row, and the text before it is evened out' \
        $'Remember that the command lives in\nthe folder named\n'"$P40" "$OUT"
    # What the callers see: print_fit and print_fit_path end with status 0 whichever way they go.
    app_eval 'print_fit 1 "$T"; echo "status $?"' T='into a pipe'
    check_eq 'print_fit into a pipe ends with status 0' 'status 0' "${OUT##*$'\n'}"
    pty_eval 40 'print_fit 1 "$T"; echo "status $?"' T="$TEXT"
    check_eq 'print_fit on a terminal ends with status 0' 'status 0' "${OUT##*$'\n'}"
    app_eval 'print_fit_path 1 "$T" "$P"; echo "status $?"' T="Written to /home/u/x.txt and ready." P=/home/u/x.txt
    check_eq 'print_fit_path into a pipe ends with status 0' 'status 0' "${OUT##*$'\n'}"
    pty_eval 80 'print_fit_path 1 "$T" "$P"; echo "status $?"' T="Written to /home/u/x.txt and ready." P=/home/u/x.txt
    check_eq 'print_fit_path with a path that fits ends with status 0' 'status 0' "${OUT##*$'\n'}"
    pty_eval 40 'print_fit_path 1 "$T" "$P"; echo "status $?"' T="Folder: /home/my user/with spaces/x ready." P="/home/my user/with spaces/x"
    check_eq 'print_fit_path with a path on its own row ends with status 0' 'status 0' "${OUT##*$'\n'}"
    # The real use: the warning that the folder of the command is not in PATH starts with that folder. Homes of 10,
    # 45 and 95 characters (the folder adds 11), without and with a space in them, in both languages, on four widths.
    for lang in es en; do
        if [ "$lang" = es ] && [ -z "$UTF8" ]; then
            skip_case 'the system has no C.UTF-8 locale: the Spanish texts cannot be counted in characters'
            continue
        fi
        app_eval 'msgf_v text install_path_warn ""; printf "%s" "$text"' MINTAPP_LANG="$lang" LC_ALL="${UTF8:-C}"
        rest="$OUT"
        for cols in 120 80 60 45; do
            for home in 10 45 95; do
                hbase="/home/$(printf '%*s' "$((home - 6))" '' | tr ' ' u)"
                for dir in "$hbase/.local/bin" "${hbase:0:8} ${hbase:9}/.local/bin"; do
                    kind=''
                    if [[ "$dir" == *' '* ]]; then kind=', with a space'; fi
                    pty_eval "$cols" 'msgf_v text install_path_warn "$P"; print_fit_path 1 "$text" "$P"' \
                        P="$dir" MINTAPP_LANG="$lang" NO_COLOR=1 LC_ALL="${UTF8:-C}"
                    check_eq "the PATH warning ($lang, $cols columns, folder of ${#dir} characters$kind): the path whole, no row too wide, no word lost" \
                        '' "$(path_problems "$cols" "$dir" "$rest")"
                done
            done
        done
    done
fi

echo "-- install_report_line: three layouts, the path never touched"
new_sandbox
RPATH=/home/u/.local/bin/mintapp-remover
app_eval 'INSTALL_LABEL_WIDTH=9; install_report_line Command "$P" new' P="$RPATH"
check_eq 'into a pipe: one line, whatever its width' "  Command    $RPATH  (new)" "$OUT"
if [ -z "$HAVE_PTY" ]; then
    skip_case 'no "script" command: the pseudo-terminal cases are skipped'
else
    pty_eval 80 'INSTALL_LABEL_WIDTH=9; install_report_line Command "$P" updated' P="$RPATH"
    check_eq 'on a wide terminal: one line' "  Command    $RPATH  (updated)" "$OUT"
    pty_eval 55 'INSTALL_LABEL_WIDTH=9; install_report_line Command "$P" updated' P="$RPATH"
    check_eq 'a line wider than the screen: the state goes under the path' \
        "  Command    $RPATH"$'\n'"             (updated)" "$OUT"
    pty_eval 40 'INSTALL_LABEL_WIDTH=9; install_report_line Command "$P" updated' P="$RPATH"
    check_eq 'a path that does not fit beside the label: the label alone, the path under it, the state under that' \
        $'  Command\n    '"$RPATH"$'\n    (updated)' "$OUT"
    for cols in 80 60 45 40; do
        for home in 10 45 95; do
            hpath="/home/$(printf '%*s' "$((home - 6))" '' | tr ' ' u)/.local/bin/mintapp-remover"
            pty_eval "$cols" 'INSTALL_LABEL_WIDTH=9; install_report_line Command "$P" updated' P="$hpath"
            check_eq "the path stays whole on one row ($cols columns, home of $home characters)" 1 "$(grep -c -x -F -e "$hpath" -e "  Command    $hpath  (updated)" -e "  Command    $hpath" -e "    $hpath" -e "    $hpath  (updated)" <<< "$OUT")"
            check_eq "no other row reaches the edge ($cols columns, home of $home)" '' "$(printf '%s\n' "$OUT" | grep -v -F -- "$hpath" | lines_wider $((cols - 1)))"
        done
    done
fi

echo "-- header: width, version and color"
new_sandbox
for cols in 40 60 80 120 200; do
    app_eval 'header' COLUMNS="$cols" NO_COLOR=1
    width=$((cols - 1)); [ "$width" -le 100 ] || width=100
    rule="$(printf '%*s' "$width" '' | tr ' ' '=')"
    check_eq "the rules are as wide as the text screen ($cols columns: $width)" "$rule"$'\n'"$rule" "$(plain | sed -n '1p;3p')"
    line="$(plain | sed -n 2p)"
    check_eq "the title line ends one column before the rules, with the version ($cols columns)" "$((width - 1)) v$H_VERSION" "${#line} ${line##* }"
    check_eq "it starts with a space and the title ($cols columns)" ' MintApp Remover' "${line:0:16}"
    check_eq "a blank line follows the header ($cols columns)" '' "$(plain | sed -n 4p)"
done
app_eval 'header "A title so long that it leaves no room for the version"' COLUMNS=45 NO_COLOR=1
line="$(plain | sed -n 2p)"
check_eq 'a title that leaves no room for the version is cut to the width and the version is left out' ' A title so long that it leaves no room for ' "$line"
app_eval 'header' COLUMNS=60
assert_contains 'with color the version is dim' "$OUT" "${ESC}[2mv${H_VERSION}${ESC}[0m"
assert_contains 'and the rules are in the title color' "$OUT" "${ESC}[1;34m"
app_eval 'header' COLUMNS=60 NO_COLOR=1
check_eq 'without color the header has no color sequence' 0 "$(printf '%s' "$OUT" | LC_ALL=C grep -a -c -P '\x1b\[[0-9;]*m' || true)"
if [ -n "$UTF8" ]; then
    app_eval 'header' COLUMNS=60 NO_COLOR=1 MINTAPP_ASCII=0 LC_ALL="$UTF8"
    check_eq 'in Unicode the rules are heavy lines of the same width' "$(printf '%*s' 59 '' | sed 's/ /═/g')" "$(plain | sed -n 1p)"
fi

echo "-- the palette: green, blue and black; yellow only to warn"
new_sandbox
# Every color sequence the program writes, from its code: "\033[...m" and the tui's "${e}...m".
sgr="$(grep -o -E '(\\033\[|\$\{e\})[0-9;]*m' "$H_SCRIPT" | sed -E 's/^(\\033\[|\$\{e\})//; s/m$//' | sort -u | paste -sd' ' -)"
# The text mode: bold, dim, blue titles, green choices, yellow warnings, black on green for a chosen item. The
# own dialogs add white on blue for their bar, black on white for the chip, a blue scroll bar, and reverse and
# underline when there is no color. Red, magenta, cyan and the bright colors are not in the program.
allowed='0 1 1;30;42 1;32 1;33 1;34 1;37;44 2 30;42 30;47 34 4 7'
unknown=""
for code in $sgr; do
    case " $allowed " in *" $code "*) ;; *) unknown+=" $code" ;; esac
done
check_eq 'every color sequence of the program is one of the palette' '' "$unknown"
app_eval 'printf "%s" "$C_TITLE|$C_OK|$C_WARN|$C_ERR|$C_MARK"'
check_eq 'titles blue, choices green, warnings and errors yellow, a chosen item black on green' \
    '\033[1;34m|\033[1;32m|\033[1;33m|\033[1;33m|\033[1;30;42m' "$OUT"
app_eval 'while IFS="=" read -r k v; do [ -n "$k" ] || continue; IFS="," read -r fg bg <<< "$v"; printf "%s\n%s\n" "$fg" "$bg"; done <<< "$NEWT_COLORS" | grep -v "^$" | sort -u | paste -sd" " -'
check_eq 'the palette of whiptail uses only green, blue and black' 'black blue brightblue brightgreen green' "$OUT"
app_eval 'printf "%s|%s" "${NEWT_COLORS-unset}" "$NEWT_MONO"' NO_COLOR=1
check_eq 'without color whiptail goes monochrome and has no palette' 'unset|1' "$OUT"
app_eval 'tui_init_style; for v in TS_BAR TS_BORDER TS_TITLE TS_TAG TS_SEL TS_MARK TS_BTN TS_BTN_ON TS_CHIP TS_WARN TS_SCROLL TS_THUMB TS_SEL_OFF TS_DESC; do printf "%s=%s\n" "$v" "${!v}"; done | sed "s/\x1b/E/g"' NO_COLOR=1
check_eq 'the own dialogs without color use only bold, dim, underline and reverse' '' "$(printf '%s\n' "$OUT" | grep -E '3[0-7]|4[0-7]|9[0-7]' || true)"

echo "-- every screen: NO_COLOR, color and ASCII"
new_sandbox
fake_installed vlc libreoffice-writer otherpkg
make_desktop vlc.desktop 'VLC media player' 'Exec=vlc' 'Icon=vlc'
make_desktop other.desktop 'Other App' 'Exec=other'
fake_owner "$SB/apps/vlc.desktop" vlc
fake_owner "$SB/apps/other.desktop" otherpkg
CLEAR="$(env -i TERM=xterm "$(command -v clear)" 2> /dev/null || true)"
# The screens of the text interface: the first Enter closes the help of the first screen.
# name|input|arguments
SCREENS=(
    'help||--help'
    'version||--version'
    'unknown-option||--nope'
    'menu|\n0\n|'
    'detected|\n1\n\n0\n|'
    'uninstall-list|\n2\n\n0\n0\n|'
    'plan|\n2\n\n1\nc\nn\n\n0\n|'
    'advanced|\n3\n\n0\n0\n|'
    'clean-menu|\n4\n0\n0\n|'
    'language|\nL\n0\n|'
    'install||install'
    'uninstall||uninstall --purge'
)
# run_screens LANG COLOR: every screen, one file each in $H_TMP/screens (COLOR: on or off).
run_screens() {
    local lang="$1" color="$2" entry name input args dir="$H_TMP/screens"
    local -a envs=(MINTAPP_UI=text MINTAPP_LANG="$lang" MINTAPP_ASCII=1 COLUMNS=60)
    [ "$color" = on ] || envs+=(NO_COLOR=1)
    mkdir -p "$dir"
    for entry in "${SCREENS[@]}"; do
        IFS='|' read -r name input args <<< "$entry"
        # Every screen starts from the same home: what install and uninstall print depends on what is there.
        rm -rf -- "$SB/home/.local" "$SB/home/.config"
        # The uninstall report needs something to remove.
        if [ "$name" = uninstall ]; then app_run '' "${envs[@]}" -- install; fi
        # shellcheck disable=SC2086  # args is a short list of words on purpose
        app_run "$(printf '%b' "$input")" "${envs[@]}" -- $args
        printf '%s' "$OUT" > "$dir/$lang.$color.$name"
    done
}
for lang in es en; do
    run_screens "$lang" on
    run_screens "$lang" off
    for entry in "${SCREENS[@]}"; do
        name="${entry%%|*}"
        on="$(cat "$H_TMP/screens/$lang.on.$name")"
        off="$(cat "$H_TMP/screens/$lang.off.$name")"
        OUT="$off"
        off_clean="${off//"$CLEAR"/}"
        check_eq "NO_COLOR: no escape sequence but the one of clear ($lang, $name)" 0 "$([[ "$off_clean" == *"$ESC"* ]] && echo 1 || echo 0)"
        OUT="$on"
        on_plain="$(plain)"
        check_eq "the color changes nothing of the layout: without its sequences the screen is the same ($lang, $name)" "$off_clean" "${on_plain}"
        check_eq "ASCII: no byte over 127 with color ($lang, $name)" '' "$(printf '%s' "$on" | LC_ALL=C grep -a -n -m2 -P '[^\x00-\x7f]' | cut -c1-70 || true)"
        check_eq "ASCII: no byte over 127 without color ($lang, $name)" '' "$(printf '%s' "$off" | LC_ALL=C grep -a -n -m2 -P '[^\x00-\x7f]' | cut -c1-70 || true)"
    done
done
# Run without section 20 (sections.sh), there are no screens to read: cat would only complain.
all_sgr="$(cat "$H_TMP"/screens/*.on.* 2> /dev/null | LC_ALL=C grep -a -o -P '\x1b\[[0-9;]*m' | sort -u | sed -E "s/^\x1b\[//; s/m$//" | paste -sd' ' -)"
bad=""
for code in $all_sgr; do
    [[ " 0 1 1;30;42 1;32 1;33 1;34 2 " == *" $code "* ]] || bad+=" $code"
done
check_eq 'the color sequences of the text screens are the ones of the palette of the text mode' '' "$bad"
check_eq 'and the screens do use the blue of the titles, the green of the choices and the black on green of a chosen item' yes \
    "$([[ " $all_sgr " == *" 1;34 "* && " $all_sgr " == *" 1;32 "* && " $all_sgr " == *" 1;30;42 "* ]] && echo yes || echo "$all_sgr")"

echo "-- install and uninstall on a terminal: no row reaches the edge and the paths stay whole"
new_sandbox
BIN_DIR="$SB/home/.local/bin"
if [ -z "$HAVE_PTY" ]; then
    skip_case 'no "script" command: the pseudo-terminal cases are skipped'
else
    for lang in es en; do
        for cols in 80 60 45 40; do
            rm -rf -- "$SB/home/.local" "$SB/home/.config"
            pty_eval "$cols" 'main install' MINTAPP_LANG="$lang" NO_COLOR=1
            check_eq "install: no row without a path reaches the edge ($lang, $cols columns)" '' \
                "$(printf '%s\n' "$OUT" | grep -v -F -- "$SB/home" | lines_wider $((cols - 1)))"
            if [ "${#BIN_DIR}" -ge "$cols" ]; then
                check_eq "install: the folder of the command, wider than the screen, is whole on a row of its own ($lang, $cols columns)" 1 \
                    "$(printf '%s\n' "$OUT" | grep -c -x -F -- "$BIN_DIR")"
            else
                check_eq "install: the folder of the command is whole on a row ($lang, $cols columns)" yes \
                    "$(printf '%s\n' "$OUT" | grep -q -F -- "$BIN_DIR" && echo yes || echo no)"
            fi
            pty_eval "$cols" 'main uninstall --purge' MINTAPP_LANG="$lang" NO_COLOR=1
            check_eq "uninstall: no row without a path reaches the edge ($lang, $cols columns)" '' \
                "$(printf '%s\n' "$OUT" | grep -v -F -- "$SB/home" | lines_wider $((cols - 1)))"
        done
    done
    # The same flow with another home: one with spaces, and one over 100 characters long. The folder of the
    # command is the path of the warning that it is not in PATH: whole, on a row of its own.
    for kind in spaces long; do
        if [ "$kind" = spaces ]; then
            other="$SB/my home/with spaces"
        else
            other="$SB/$(printf 'h%.0s' $(seq 50))/$(printf 'k%.0s' $(seq 50))"
        fi
        mkdir -p -- "$other"
        sandbox_chown
        for lang in es en; do
            for cols in 80 45; do
                rm -rf -- "$other/.local" "$other/.config"
                pty_eval "$cols" 'main install' MINTAPP_LANG="$lang" NO_COLOR=1 HOME="$other"
                check_eq "install, home $kind: it ends well ($lang, $cols columns)" 0 "$RC"
                check_eq "install, home $kind: no row without a path reaches the edge ($lang, $cols columns)" '' \
                    "$(printf '%s\n' "$OUT" | grep -v -F -- "$other" | lines_wider $((cols - 1)))"
                check_eq "install, home $kind: the folder of the command is whole on a row of its own ($lang, $cols columns)" 1 \
                    "$(printf '%s\n' "$OUT" | grep -c -x -F -- "$other/.local/bin")"
                pty_eval "$cols" 'main uninstall --purge' MINTAPP_LANG="$lang" NO_COLOR=1 HOME="$other"
                check_eq "uninstall, home $kind: no row without a path reaches the edge ($lang, $cols columns)" '' \
                    "$(printf '%s\n' "$OUT" | grep -v -F -- "$other" | lines_wider $((cols - 1)))"
            done
        done
    done
fi
for lang in es en; do
    rm -rf -- "$SB/home/.local" "$SB/home/.config"
    app_run '' MINTAPP_LANG="$lang" NO_COLOR=1 COLUMNS=120 -- install
    wide="$OUT"
    rm -rf -- "$SB/home/.local" "$SB/home/.config"
    app_run '' MINTAPP_LANG="$lang" NO_COLOR=1 COLUMNS=40 -- install
    check_eq "into a pipe the messages go out as they are, whatever the width of the screen ($lang)" "$wide" "$OUT"
done

echo "-- tui menus: each description whole while it fits, and the frame aligned"
# tui_menu_level on a menu of three entries whose descriptions take 1, 3 and 0 rows (27 columns: the words of 20
# characters cannot share a row). The rows needed are 2 + 4 + 1 = 7 (level 2), 9 with a blank row between entries
# (level 3). Under 7 the labels go alone and the description of the current entry goes under the list in the rows
# left after the list and a blank row, up to the 3 of the longest one (level 1); with fewer than n + 2 rows, level 0.
for sample in '20|3 0' '9|3 0' '8|2 0' '7|2 0' '6|1 2' '5|1 1' '4|0 0' '0|0 0'; do
    app_eval 'TUI_KIND=menu TUI_HAS_DESC=1 TUI_LW=30 TUI_TAGW=1 TUI_TAGS=(1 2 3)
        TUI_DESCS=("short one" "aaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbb cccccccccccccccccccc" "")
        tui_menu_level "$ROWS"; printf "%s %s | %s | %s | %s" "$TUI_LEVEL" "$TUI_DAREA" "${TUI_DN[*]}" "${TUI_DS[*]}" "$TUI_DMAX"' ROWS="${sample%%|*}"
    check_eq "tui_menu_level, ${sample%%|*} rows: level and rows under the list (the rows of each description: 1 3 0)" \
        "${sample#*|} | 1 3 0 | 0 1 4 | 3" "$OUT"
done
app_eval 'TUI_KIND=checklist TUI_HAS_DESC=1 TUI_LW=30 TUI_TAGW=1 TUI_TAGS=(1 2) TUI_DESCS=(a b); tui_menu_level 20; printf "%s" "$TUI_LEVEL"'
check_eq 'tui_menu_level: a checklist has no descriptions to lay out' 0 "$OUT"
app_eval 'TUI_KIND=menu TUI_HAS_DESC=0 TUI_LW=30 TUI_TAGW=1 TUI_TAGS=(1 2) TUI_DESCS=("" ""); tui_menu_level 20; printf "%s" "$TUI_LEVEL"'
check_eq 'tui_menu_level: a menu without descriptions has none to lay out' 0 "$OUT"
if [ -n "$HAVE_PTY" ]; then
    # The own dialogs read keys in raw mode: the end of the input of a pseudo-terminal is not an end of file for them, so
    # the case ends its own dialog. A dialog asks for its first key only after drawing its screen: TUI_KICK replaces
    # that read with a TERM to itself, which the dialog takes as a request to leave (through its own trap, as a real
    # one). Nothing waits for a time: a TERM after a fixed second came before the screen of 8 applications was drawn
    # on a slow machine, and 3 runs of this section in 6 failed.
    TUI_KICK='tui_read_key() { kill -TERM "$BASHPID"; return 2; };'
    # tui_rows: the rows of the last screen the own dialogs drew in OUT, one per line as "N text" (N: its row on the
    # screen; the first time a row is addressed wins, as the terminal is put back with another move to the last one).
    tui_rows() { printf '%s' "$OUT" | sed -E 's/\x1b\[([0-9]+);1H/\n@\1 /g; s/\x1b\[[0-9;?]*[A-Za-z]//g' | sed -n 's/^@//p' | awk '!seen[$1]++'; }
    # frame_problems COLS ROWS: the rows of the frame (from the second to the one over the last) that are not COLS wide.
    frame_problems() (
        LC_ALL="${UTF8:-C}"
        local cols="$1" rows="$2" line n t
        while IFS= read -r line; do
            n="${line%% *}" t="${line#* }"
            if [ "$n" -ge 2 ] && [ "$n" -le $((rows - 1)) ] && [ "${#t}" -ne "$cols" ]; then echo "row $n: ${#t} columns"; fi
        done < <(tui_rows)
    )
    # tui_inner: the text between the borders of the frame, row by row.
    tui_inner() { tui_rows | awk '$1 >= 3 { t = substr($0, length($1) + 3); print substr(t, 1, length(t) - 1) }'; }
    for lang in es en; do
        app_eval 'msg clean_level_simple_desc' MINTAPP_LANG="$lang"; simple_desc="$OUT"
        app_eval 'msg clean_level_complete_desc' MINTAPP_LANG="$lang"; complete_desc="$OUT"
        app_eval 'msg back' MINTAPP_LANG="$lang"; back_label="$OUT"
        for size in '80 24' '120 40' '60 24'; do
            cols="${size% *}" rows="${size#* }"
            PTY_ROWS="$rows" pty_eval "$cols" "$TUI_KICK UI_ENGINE=tui HAVE_WHIPTAIL=1; clean_choose_level || true" MINTAPP_LANG="$lang" NO_COLOR=1
            check_eq "tui, level of the deep cleanup, $cols x $rows ($lang): the frame is $cols columns wide on every row" '' "$(frame_problems "$cols" "$rows")"
            check_eq "tui, level of the deep cleanup, $cols x $rows ($lang): the key bar names Esc like the Back button ($back_label)" 1 \
                "$(tui_rows | awk -v r="$rows" -v b="$back_label" '$1 == r && $0 ~ ("Esc +" b) { f = 1 } END { print f + 0 }')"
            inner="$(tui_inner)"
            check_eq "tui, level of the deep cleanup, $cols x $rows ($lang): no description ends in an ellipsis" 0 "$(printf '%s\n' "$inner" | grep -c -F -e '...' || true)"
            for desc in "$simple_desc" "$complete_desc"; do
                check_eq "tui, level of the deep cleanup, $cols x $rows ($lang): the description is whole: ${desc:0:24}..." 1 \
                    "$([[ "$(squash "$inner")" == *"$(squash "$desc")"* ]] && echo 1 || echo 0)"
            done
        done
        # With a window too short for both, the entry that has the pointer (the first) keeps its description whole
        # under the list.
        PTY_ROWS=16 pty_eval 80 "$TUI_KICK UI_ENGINE=tui HAVE_WHIPTAIL=1; clean_choose_level || true" MINTAPP_LANG="$lang" NO_COLOR=1
        inner="$(tui_inner)"
        check_eq "tui, level of the deep cleanup, 80 x 16 ($lang): the frame is 80 columns wide on every row" '' "$(frame_problems 80 16)"
        check_eq "tui, level of the deep cleanup, 80 x 16 ($lang): the description of the first entry is whole under the list" 1 \
            "$([[ "$(squash "$inner")" == *"$(squash "$simple_desc")"* ]] && echo 1 || echo 0)"
        check_eq "tui, level of the deep cleanup, 80 x 16 ($lang): the description of the second one is not shown" 0 \
            "$([[ "$(squash "$inner")" == *"$(squash "${complete_desc:0:30}")"* ]] && echo 1 || echo 0)"
        if [ -n "$UTF8" ]; then
            for size in '80 24' '60 24'; do
                cols="${size% *}" rows="${size#* }"
                PTY_ROWS="$rows" pty_eval "$cols" "$TUI_KICK UI_ENGINE=tui HAVE_WHIPTAIL=1; clean_choose_level || true" MINTAPP_LANG="$lang" NO_COLOR=1 LC_ALL="$UTF8"
                check_eq "tui, level of the deep cleanup, $cols x $rows, Unicode ($lang): the frame is $cols characters wide on every row" '' "$(frame_problems "$cols" "$rows")"
            done
        fi
    done
    # The detection screen offers the search from 8 applications on: Esc leaves it like OK, and the key bar says so.
    new_sandbox
    fake_installed firefox thunderbird gnome-calculator gnome-calendar xreader simple-scan webapp-manager warpinator
    for lang in es en; do
        app_eval 'msg ok' MINTAPP_LANG="$lang"; ok_label="$OUT"
        PTY_ROWS=24 pty_eval 80 "$TUI_KICK UI_ENGINE=tui HAVE_WHIPTAIL=1; detect_programs || true" MINTAPP_LANG="$lang" NO_COLOR=1
        check_eq "tui, detection screen with the search button, 80 x 24 ($lang): the key bar names Esc like OK ($ok_label)" 1 \
            "$(tui_rows | awk -v r=24 -v b="$ok_label" '$1 == r && $0 ~ ("Esc +" b) { f = 1 } END { print f + 0 }')"
    done
fi

echo "-- whiptail menus: a description that does not fit its row goes whole into the text"
# The whiptail stub of the harness records what the real one would get. menu_dump: the last --menu call, as a line
# "HEIGHT WIDTH ROWS", its text (the stub writes a line break as RS), a line "--" and one "TAG<TAB>LABEL" line per entry.
menu_dump() {
    awk '
        function finish(   i, j, k, t) {
            for (i = 1; i <= n; i++) if (a[i] == "--menu") break
            if (i > n) return
            t = a[i + 1]; gsub(/\036/, "\n", t); j = i + 2
            rec = a[j] " " a[j + 1] " " a[j + 2]; text = t; items = ""
            for (k = j + 3; k + 1 <= n; k += 2) items = items a[k] "\t" a[k + 1] "\n"
        }
        $0 == "@@END@@" { finish(); n = 0; next }
        { a[++n] = $0 }
        END { printf "%s\n%s\n--\n%s", rec, text, items }
    ' "$SB/state/whiptail.args"
}
# menu_text: the text of that menu.
menu_text() { menu_dump | sed -n '2,/^--$/p' | sed '$d'; }
# wt_menu_problems COLS LINES LABELS DESCS: what is wrong in the last menu (nothing if it is right) for the entries
# whose labels and descriptions are in the arrays LABELS and DESCS. Always: one row per entry, the box inside the
# screen in width, its height the text plus the rows plus 7. With every description in the text: each label on a row
# of its own and its description whole on the rows after it, indented 3 (none for an empty one), the rows with the
# labels alone, no text row wider than the box takes (6 columns less), no ellipsis, a row per entry, and the box
# inside the screen in height. With none: each row starts with its label and fits its columns.
wt_menu_problems() (
    LC_ALL="${UTF8:-C}"
    local cols="$1" lines="$2" count i pos row got w h r digits width in_text=0 out_text=0
    local -n _l="$3" _d="$4"
    local -a dump=() trows=() labs=()
    mapfile -t dump < <(menu_dump)
    read -r h w r <<< "${dump[0]}"
    for (( i = 1; i < ${#dump[@]}; i++ )); do [ "${dump[i]}" != -- ] || break; trows+=("${dump[i]}"); done
    for (( i++; i < ${#dump[@]}; i++ )); do labs+=("${dump[i]#*$'\t'}"); done
    count="${#_l[@]}"
    [ "${#labs[@]}" -eq "$count" ] || echo "${#labs[@]} rows for $count entries"
    [ "$w" -le $((cols - 2)) ] || echo "the box is $w columns on a screen of $cols"
    [ "$h" -eq $(( ${#trows[@]} + r + 7 )) ] || echo "height $h is not its ${#trows[@]} text rows plus $r list rows plus 7"
    got="$(squash "${trows[*]}")"
    for (( i = 0; i < count; i++ )); do
        [ -n "${_d[i]}" ] || continue
        if [[ "$got" == *"$(squash "${_d[i]}")"* ]]; then in_text=$((in_text + 1)); else out_text=$((out_text + 1)); fi
    done
    if [ "$in_text" -gt 0 ]; then
        [ "$out_text" -eq 0 ] || echo "$out_text descriptions are not in the text"
        [ "$h" -le $((lines - 2)) ] || echo "the box is $h rows on a screen of $lines"
        [ "$r" -eq "$count" ] || echo "$r list rows for $count entries"
        if printf '%s\n' "${trows[@]}" | grep -q -F -e '...' -e '…'; then echo "an ellipsis in the text"; fi
        for row in "${trows[@]}"; do [ "${#row}" -le $((w - 6)) ] || echo "text row of ${#row} columns: $row"; done
        for (( pos = 0; pos < ${#trows[@]}; pos++ )); do [ "${trows[pos]}" != "${_l[0]}" ] || break; done
        for (( i = 0; i < count; i++ )); do
            [ "${trows[pos]:-}" = "${_l[i]}" ] || { echo "the label ${_l[i]} is not on its row"; break; }
            pos=$((pos + 1)); row=""
            while [[ "${trows[pos]:-}" == "   "* ]]; do row+="${trows[pos]}"; pos=$((pos + 1)); done
            [ "$(squash "$row")" = "$(squash "${_d[i]}")" ] || echo "the description of ${_l[i]} is not whole under it"
            [ "${labs[i]:-}" = "${_l[i]}" ] || echo "row $((i + 1)) is not the label alone: ${labs[i]:-}"
        done
        [ "$pos" -eq "${#trows[@]}" ] || echo "text left after the last entry"
    else
        digits="${#count}"; width=$((w - 15 - digits)); [ "$width" -ge 10 ] || width=10
        for (( i = 0; i < count; i++ )); do
            [ "${#labs[i]}" -le "$width" ] || echo "row ${labs[i]} is wider than its $width columns"
            [ "${#_l[i]}" -gt "$width" ] || [[ "${labs[i]}" == "${_l[i]}"* ]] || echo "row ${labs[i]} does not start with its label"
        done
    fi
)
# wt_menu COLS LINES PROMPT LABELS DESCS [VAR=val ...]: choose_menu on whiptail, with the entries one per line in
# LABELS and DESCS (an empty description only between two lines), at that screen size; whiptail answers Cancel.
wt_menu() {
    local cols="$1" lines="$2" prompt="$3" labels="$4" descs="$5"
    shift 5
    : > "$SB/state/whiptail.args"; : > "$SB/state/whiptail.log"
    fake_answers CANCEL
    app_eval 'UI_ENGINE=whiptail HAVE_WHIPTAIL=1; mapfile -t labels <<< "$L"; mapfile -t descs <<< "$D"; tags=()
        for i in "${!labels[@]}"; do tags+=("$((i + 1))"); done
        choose_menu "$P" tags labels descs || true' COLUMNS="$cols" LINES="$lines" P="$prompt" L="$labels" D="$descs" NO_COLOR=1 "$@"
}
new_sandbox
LONGDESC='The first description has more words than a row of the list can hold, so it needs several rows of its own in the box and then some more words to be sure of it.'
mapfile -t LAB <<< $'Alpha\nBeta'; mapfile -t DES <<< $'first thing\nsecond thing'
wt_menu 80 24 'Choose one.' "$(printf '%s\n' "${LAB[@]}")" "$(printf '%s\n' "${DES[@]}")"
check_eq 'whiptail menu, descriptions that fit their rows: they stay in the rows' $'Alpha - first thing\nBeta - second thing' \
    "$(menu_dump | sed -n '/^--$/,$p' | sed '1d' | cut -f2)"
check_eq 'whiptail menu, descriptions that fit their rows: the text is the prompt alone' 'Choose one.' "$(menu_text)"
check_eq 'whiptail menu, descriptions that fit their rows: nothing wrong' '' "$(wt_menu_problems 80 24 LAB DES)"
mapfile -t LAB <<< $'Alpha\nBeta\nGamma'; mapfile -t DES <<< "$LONGDESC"$'\n\nshort one'
wt_menu 80 24 'Choose one.' "$(printf '%s\n' "${LAB[@]}")" "$LONGDESC"$'\n\nshort one'
check_eq 'whiptail menu, one description too long: all go to the text, the rows keep the labels' $'Alpha\nBeta\nGamma' \
    "$(menu_dump | sed -n '/^--$/,$p' | sed '1d' | cut -f2)"
check_eq 'whiptail menu, one description too long: nothing wrong (one without description has no rows, the short one is in the text too)' '' \
    "$(wt_menu_problems 80 24 LAB DES)"
check_eq 'whiptail menu, one description too long: the text starts with the prompt and a blank row, then the first label' $'Choose one.\n\nAlpha' \
    "$(menu_text | head -n 3)"
check_eq 'whiptail menu, one description too long: the entry without description is followed by the next label' $'Beta\nGamma' \
    "$(menu_text | grep -x -e Beta -e Gamma)"
mapfile -t LAB <<< "$(printf 'Entry %02d\n' $(seq 1 14))"
DES=(); for i in $(seq 1 14); do DES+=("$LONGDESC"); done
wt_menu 80 24 'Choose one.' "$(printf '%s\n' "${LAB[@]}")" "$(printf '%s\n' "${DES[@]}")"
check_eq 'whiptail menu, text and rows do not fit the screen: the text is the prompt alone' 'Choose one.' "$(menu_text)"
check_eq 'whiptail menu, text and rows do not fit the screen: the descriptions stay in the rows, cut' 14 \
    "$(menu_dump | sed -n '/^--$/,$p' | sed '1d' | grep -c -F -e ' - The first' || true)"
check_eq 'whiptail menu, text and rows do not fit the screen: nothing wrong' '' "$(wt_menu_problems 80 24 LAB DES)"
# A label that leaves fewer than 8 columns for its description counts as too long: the description goes to the text.
LABL='A label that takes almost the whole width of its row'
mapfile -t LAB <<< "$LABL"$'\nBeta'; mapfile -t DES <<< $'tiny one\nsecond'
wt_menu 80 24 'Choose one.' "$(printf '%s\n' "${LAB[@]}")" "$(printf '%s\n' "${DES[@]}")"
check_eq 'whiptail menu, a label that takes the row: its description goes to the text' 1 "$([[ "$(menu_text)" == *'   tiny one'* ]] && echo 1 || echo 0)"
check_eq 'whiptail menu, a label that takes the row: nothing wrong' '' "$(wt_menu_problems 80 24 LAB DES)"

# The menus of the program, in both languages: the level and the action menus put their descriptions whole in the
# text on a screen of 80 x 24 and of 120 x 40; at any size what is drawn is consistent (the properties above).
for lang in en es; do
    for menu in 'clean_menu|clean_action_deps clean_action_deep|clean_action_deps_desc clean_action_deep_desc' \
        'clean_choose_level|clean_level_simple clean_level_complete|clean_level_simple_desc clean_level_complete_desc' \
        'clean_choose_scope C|clean_scope_all clean_scope_cats clean_scope_entries|clean_scope_all_desc clean_scope_cats_desc clean_scope_entries_desc'; do
        call="${menu%%|*}" keys="${menu#*|}"
        app_eval "for k in ${keys%%|*}; do printf '%s\\n' \"\$(msg \$k)\"; done" MINTAPP_LANG="$lang"; mapfile -t LAB <<< "$OUT"
        app_eval "for k in ${keys#*|}; do printf '%s\\n' \"\$(msg \$k)\"; done" MINTAPP_LANG="$lang"; mapfile -t DES <<< "$OUT"
        for size in '80 24' '120 40' '100 30' '60 24' '45 24' '80 16'; do
            cols="${size% *}" rows="${size#* }"
            : > "$SB/state/whiptail.args"; : > "$SB/state/whiptail.log"; fake_answers CANCEL
            app_eval "UI_ENGINE=whiptail HAVE_WHIPTAIL=1; $call || true" COLUMNS="$cols" LINES="$rows" MINTAPP_LANG="$lang" NO_COLOR=1
            check_eq "whiptail, $call, $cols x $rows ($lang): the box and its text are consistent" '' "$(wt_menu_problems "$cols" "$rows" LAB DES)"
            if [ "$call" != 'clean_choose_scope C' ] && { [ "$size" = '80 24' ] || [ "$size" = '120 40' ]; }; then
                check_eq "whiptail, $call, $cols x $rows ($lang): the descriptions are in the text" "${#DES[@]}" \
                    "$(n=0; for d in "${DES[@]}"; do [[ "$(squash "$(menu_text)")" == *"$(squash "$d")"* ]] && n=$((n + 1)); done; echo "$n")"
            fi
        done
    done
done
if [ -n "$UTF8" ]; then
    app_eval 'for k in clean_level_simple clean_level_complete; do printf "%s\\n" "$(msg $k)"; done' MINTAPP_LANG=es LC_ALL="$UTF8"; mapfile -t LAB <<< "$OUT"
    app_eval 'for k in clean_level_simple_desc clean_level_complete_desc; do printf "%s\\n" "$(msg $k)"; done' MINTAPP_LANG=es LC_ALL="$UTF8"; mapfile -t DES <<< "$OUT"
    : > "$SB/state/whiptail.args"; : > "$SB/state/whiptail.log"; fake_answers CANCEL
    app_eval 'UI_ENGINE=whiptail HAVE_WHIPTAIL=1; clean_choose_level || true' COLUMNS=80 LINES=24 MINTAPP_LANG=es NO_COLOR=1 LC_ALL="$UTF8"
    check_eq 'whiptail, level of the deep cleanup, 80 x 24, Unicode (es): the box and its text are consistent' '' "$(wt_menu_problems 80 24 LAB DES)"
fi

echo "-- a path in a dialog: it breaks after a slash and its names stay whole"
new_sandbox
# msgbox_text: the text of the last --msgbox the whiptail stub got, one row per line.
msgbox_text() {
    awk '
        function finish(   i, t) {
            for (i = 1; i <= n; i++) if (a[i] == "--msgbox") { t = a[i + 1]; gsub(/\036/, "\n", t); text = t; return }
        }
        $0 == "@@END@@" { finish(); n = 0; next }
        { a[++n] = $0 }
        END { printf "%s", text }
    ' "$SB/state/whiptail.args"
}
# The result of a removal, in the box of whiptail at 80 x 24 (73 columns, 67 of them for the text): the record path
# is longer than a row, so it breaks after a slash and the name of the file is whole on the last row.
REC=/home/username/.local/state/mintapp-remover/removal-20261121-063000-12345-1.txt
for lang in en es; do
    : > "$SB/state/whiptail.args"; : > "$SB/state/whiptail.log"; fake_answers OK
    app_eval 'UI_ENGINE=whiptail HAVE_WHIPTAIL=1; LAST_RECORD="$R"; show_removal_result 0 "Done." "$(record_note_text)"' \
        COLUMNS=80 LINES=24 MINTAPP_LANG="$lang" NO_COLOR=1 R="$REC"
    check_eq "whiptail, 80 x 24 ($lang): the record path breaks after a slash and the name of the file is whole" \
        $'/home/username/.local/state/mintapp-remover/\nremoval-20261121-063000-12345-1.txt' "$(msgbox_text | tail -n 2)"
done
# Any path, at any width from 10 to 45 and with or without indentation: no row is wider than the width or blank,
# nothing is lost, a row that is not the last one is as wide as the width (a cut) or ends with a slash (a break),
# and after a row that stops short at a slash the next name is whole: its row holds the slash that ends it, it is
# the last row, or it fills its row exactly and the slash that ends it starts the row after.
app_eval 'paths=(
    /home/ana/.local/state/mintapp-remover/removal-20261121-063000-12345-1.txt
    /a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/
    /averyveryveryverylongname-with-no-slash-at-all-in-it.txt
    /srv/averyveryveryverylongname-in-the-middle-of-the-path/short/name.txt
    //double//slashes///and-a-trailing-slash//
    relative/path/with-no-leading-slash/file.tar.gz
)
for w in $(seq 10 45); do
    for ind in "" "  " "      " "            "; do
        for p in "${paths[@]}"; do
            wrap_line "$w" "${ind}${p}"; rows=("${WRAP_ROWS[@]}"); last=$(( ${#rows[@]} - 1 )); joined=""
            tag="width $w, indentation ${#ind}, $p"
            for i in "${!rows[@]}"; do
                r="${rows[i]}"; joined+="${r//[[:space:]]/}"
                [ "${#r}" -le "$w" ] || echo "$tag: row $i is ${#r} columns"
                [ -n "${r//[[:space:]]/}" ] || echo "$tag: row $i is blank"
                [ "$i" -eq "$last" ] || [ "${#r}" -eq "$w" ] || [[ "$r" == */ ]] || echo "$tag: row $i stops short and does not end with a slash"
                if [ "$i" -lt "$last" ] && [ "${#r}" -lt "$w" ] && [ "$((i + 1))" -lt "$last" ]; then
                    next="${rows[i + 1]#"${rows[i + 1]%%[![:space:]]*}"}"; after="${rows[i + 2]#"${rows[i + 2]%%[![:space:]]*}"}"
                    [[ "$next" == */* || "$after" == /* ]] || echo "$tag: the name after row $i is cut"
                fi
            done
            [ "$joined" = "$p" ] || echo "$tag: the path changed"
        done
    done
done'
check_eq 'a path wraps by the rules at every width from 10 to 45, with and without indentation' '' "$OUT"

finish
