#!/usr/bin/env bash
# Functional tests: menus and removal flows end to end, with stub apt/dpkg/sudo.
# SC2016 is off for the whole file: the code given to app_eval and bare_eval is single-quoted on purpose,
# because the program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
# This suite checks the Unicode symbols: its sandboxes run with MINTAPP_ASCII=0 (see harness.sh).
export H_UNICODE=1

plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }

echo "-- command line"
new_sandbox
app_run '' -- --version
check_eq '--version prints the version and exits 0' "0:MintApp Remover $H_VERSION" "$RC:$OUT"
app_run '' -- --help
assert_contains '--help documents MINTAPP_LANG' "$OUT" 'MINTAPP_LANG'
check_eq '--help exits 0' 0 "$RC"
app_run '' MINTAPP_LANG=es -- --help
assert_contains '--help follows the language' "$OUT" 'Uso: MintApp_Remover.sh'
app_run '' -- --nope
check_eq 'unknown option exits 2' 2 "$RC"
assert_contains 'unknown option is named in the error' "$OUT" 'Unrecognized option: --nope'
app_run '' -- --help
check_eq '--help never touches apt' 0 "$(apt_log | wc -l)"

echo "-- --help layout (F4.2)"
# widest: the widest line of stdin in characters, not bytes (UTF-8 continuation bytes are dropped first).
widest() { LC_ALL=C sed 's/[\x80-\xbf]//g' | LC_ALL=C awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }'; }
# fits: "ok" if no line of stdin is wider than 80 columns, else "N columns" (visible in the failure).
fits() { local w; w="$(widest)"; if [ "$w" -le 80 ]; then echo ok; else echo "$w columns"; fi; }
check_eq 'control: widest finds the longest line' 5 "$(printf 'ab\nc\nabcde\n' | widest)"
check_eq 'control: widest counts accents and symbols as one column each' 4 "$(printf 'añ€é\n' | widest)"
check_eq 'control: an 80-column line fits' ok "$(printf '%080d\n' 0 | fits)"
check_eq 'control: a 100-column line is reported with its width' '100 columns' "$(printf '%0100d\n' 0 | fits)"
for help_lang in en es; do
    for help_ascii in 0 1; do
        app_run '' MINTAPP_LANG=$help_lang MINTAPP_ASCII=$help_ascii -- --help
        check_eq "--help fits in 80 columns (language $help_lang, ASCII $help_ascii)" ok "$(printf '%s\n' "$OUT" | fits)"
    done
    app_run '' MINTAPP_LANG=$help_lang MINTAPP_ASCII=0 -- --nope
    check_eq "the usage after an unknown option fits in 80 columns ($help_lang)" ok "$(printf '%s\n' "$OUT" | fits)"
    app_run '' MINTAPP_LANG=$help_lang -- --help
    for help_var in MINTAPP_LANG MINTAPP_UI MINTAPP_LAUNCHER_DIRS MINTAPP_PM MINTAPP_SUDO MINTAPP_ASCII NO_COLOR; do
        assert_contains "--help documents $help_var ($help_lang)" "$OUT" "  $help_var"
    done
done

echo "-- start and exit"
new_sandbox
app_run ''
check_eq 'end of input at the menu exits 0 (no hang)' 0 "$RC"
app_run $'\n0\n'
check_eq 'option 0 exits 0' 0 "$RC"
assert_contains 'option 0 says goodbye' "$OUT" 'Exiting...'
app_run $'\nx\n99\n\n0\n'
assert_contains 'invalid menu input is reported' "$OUT" 'Invalid option.'
check_eq 'invalid menu input never crashes' 0 "$RC"
new_sandbox
app_run $'\n0\n' PATH="$SB/emptybin"
check_eq 'missing dpkg is a clean error' 1 "$RC"
assert_contains 'missing dpkg is explained' "$OUT" 'requires dpkg'
if [ "$(id -u)" -eq 0 ]; then
    app_run_as_root $'\n0\n'
    check_eq 'start: refuses to run as root' 1 "$RC"
    assert_contains 'root refusal is explained' "$OUT" 'Do not run MintApp Remover as root'
else
    skip_case 'refuses to run as root (the suite is not root)'
fi

echo "-- minimum bash version (F4.2)"
SCRIPT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../script" && pwd)/MintApp_Remover.sh"
new_sandbox
# bv LABEL EXPECTED_STATUS MAJOR MINOR: status of require_bash_version for that bash.
bv() {
    local label="$1" expected="$2" value
    app_eval "require_bash_version '$3' '$4' 2>/dev/null; printf '<<%s>>' \"\$?\""
    value="${OUT#*<<}"
    check_eq "$label" "$expected" "${value%%>>*}"
}
bv 'bash 3.2 (macOS, old systems) is refused'          1 3 2
bv 'bash 3.9 is refused'                               1 3 9
bv 'bash 4.0 is refused (no namerefs)'                 1 4 0
bv 'bash 4.2 is refused (no namerefs)'                 1 4 2
bv 'bash 4.3 is the first one accepted'                0 4 3
bv 'bash 4.4 is accepted'                              0 4 4
bv 'bash 4.10 is accepted (numeric comparison, not text)' 0 4 10
bv 'bash 5.0 is accepted'                              0 5 0
bv 'bash 5.2 is accepted'                              0 5 2
bv 'bash 10.0 is accepted'                             0 10 0
bv 'an unknown version (0.0) is refused'               1 0 0
bv 'empty version numbers are refused, no crash'       1 '' ''
bv 'garbage version numbers are refused, no crash'     1 'x' 'y'
app_eval 'require_bash_version 4 3'
check_eq 'a supported bash prints nothing' '' "$OUT"
app_eval 'require_bash_version 3 2'
assert_contains 'English: says what is required' "$OUT" 'requires bash 4.3 or newer'
assert_contains 'English: says what was found' "$OUT" 'this is version 3.2.'
app_eval 'require_bash_version 3 2' MINTAPP_LANG=es
assert_contains 'Spanish (MINTAPP_LANG): says what is required' "$OUT" 'requiere bash 4.3 o superior'
assert_contains 'Spanish (MINTAPP_LANG): says what was found' "$OUT" 'versión 3.2.'
app_eval 'require_bash_version 3 2' LANG=es_ES.UTF-8
assert_contains 'Spanish (locale es_ES.UTF-8)' "$OUT" 'requiere bash'
app_eval 'require_bash_version 3 2' LANG=es_ES.UTF-8 MINTAPP_LANG=en
assert_contains 'MINTAPP_LANG=en beats a Spanish locale' "$OUT" 'requires bash'
app_eval 'require_bash_version 3 2' LANG=en_US.UTF-8
assert_contains 'English locale' "$OUT" 'requires bash'
app_eval 'require_bash_version 3 2' LANG=es
assert_contains 'bare "es" locale is Spanish' "$OUT" 'requiere bash'
app_eval 'require_bash_version 3 2' LANG=espanol
assert_contains 'a word that merely starts with "es" is not Spanish' "$OUT" 'requires bash'
app_eval 'require_bash_version 3 2 2>/dev/null'
check_eq 'the refusal goes to stderr, not stdout' '' "$OUT"
chk_line=$(grep -n '^require_bash_version "' "$SCRIPT_FILE" | head -n1 | cut -d: -f1)
decl_line=$(grep -n '^declare -A' "$SCRIPT_FILE" | head -n1 | cut -d: -f1)
check_eq 'the version check runs before the first associative array' yes "$([ "${chk_line:-999999}" -lt "${decl_line:-0}" ] && echo yes || echo no)"
fn_line=$(grep -n '^require_bash_version() {' "$SCRIPT_FILE" | head -n1 | cut -d: -f1)
check_eq 'the check is written without bash 4 syntax (old bash must be able to parse it)' 0 \
    "$(sed -n "${fn_line},${chk_line}p" "$SCRIPT_FILE" | grep -cE '\[\[|declare -A|mapfile|\$\{[A-Za-z_]+(,,|\^\^)|local -n|\{[A-Z_]+\}[<>]' || true)"
check_eq 'the check passes the real BASH_VERSINFO' 1 "$(grep -c '^require_bash_version "${BASH_VERSINFO\[0\]:-0}" "${BASH_VERSINFO\[1\]:-0}"' "$SCRIPT_FILE" || true)"
bash_ver_ok=0; "$BASH" -c 'exit 0' && bash_ver_ok=1
check_eq 'the bash running the suite is accepted by the real program' 1 "$bash_ver_ok"

echo "-- Scriptya header: ICON (F2.8)"
# The "# ICON:" path is relative to the script's folder.
icon_rel="$(sed -n 's/^# ICON: //p' "$SCRIPT_FILE")"
icon_file="$(dirname "$SCRIPT_FILE")/$icon_rel"
check_eq 'the header has exactly one "# ICON:" line' 1 "$(grep -c '^# ICON: ' "$SCRIPT_FILE" || true)"
check_eq 'the ICON path points to an existing file' yes "$([ -f "$icon_file" ] && echo yes || echo "no: $icon_rel")"
check_eq 'the ICON file is a PNG image (signature)' 89504e470d0a1a0a "$(head -c 8 "$icon_file" 2>/dev/null | od -An -tx1 | tr -d ' \n')"

echo "-- bash 4.3: empty arrays and the 0x01 byte (F4.2)"
# bash 4.3 treats "${array[@]}" of an empty array as an unbound variable under "set -u" (4.4 and
# later do not), and doubles a \x01 byte written inside $'...'. These checks read the code, so they
# fail on any bash; a container job with bash 4.3 (F4.7) is what proves the program itself runs there.
code_only() { sed -E 's/^[[:space:]]*#.*$//' "$SCRIPT_FILE"; }
# unguarded_expansions ARRAY < CODE: expansions of ARRAY that bash 4.3 rejects when it is empty.
# The accepted form is "${ARRAY[@]+"${ARRAY[@]}"}"; the count ${#ARRAY[@]} is always fine.
unguarded_expansions() {
    local arr="$1" code plain guarded star sliced
    code="$(cat)"
    plain=$(grep -oF -- "\${${arr}[@]}" <<< "$code" | wc -l)
    guarded=$(grep -oF -- "\${${arr}[@]+\"\${${arr}[@]}\"}" <<< "$code" | wc -l)
    star=$(grep -oF -- "\${${arr}[*]}" <<< "$code" | wc -l)
    sliced=$(grep -oF -- "\${${arr}[@]:" <<< "$code" | wc -l)
    echo $((plain - guarded + star + sliced))
}
check_eq 'control: a guarded expansion is accepted' 0 "$(printf '%s\n' 'for t in "${tags[@]+"${tags[@]}"}"; do' | unguarded_expansions tags)"
check_eq 'control: a bare "${a[@]}" is found' 1 "$(printf '%s\n' 'for t in "${tags[@]}"; do' | unguarded_expansions tags)"
check_eq 'control: a bare ${a[*]} is found' 1 "$(printf '%s\n' 'echo "${tags[*]}"' | unguarded_expansions tags)"
check_eq 'control: a slice ${a[@]:1:2} is found' 1 "$(printf '%s\n' 'x=("${tags[@]:1:2}")' | unguarded_expansions tags)"
check_eq 'control: the count ${#a[@]} is fine' 0 "$(printf '%s\n' '[ "${#tags[@]}" -gt 0 ]' | unguarded_expansions tags)"
check_eq 'control: another array is not counted' 0 "$(printf '%s\n' 'for t in "${other[@]}"; do' | unguarded_expansions tags)"
check_eq 'control: a guarded and a bare expansion together count one' 1 "$(printf '%s\n' 'a "${tags[@]+"${tags[@]}"}" b "${tags[@]}"' | unguarded_expansions tags)"
read_arrays="$(code_only | grep -oE 'read +(-[A-Za-z]+ +)*-[A-Za-z]*a[A-Za-z]* +[A-Za-z_][A-Za-z0-9_]*' | awk '{print $NF}' | sort -u)"
check_eq 'the arrays filled with read -a are found (so the loop below checks something)' yes "$([ -n "$read_arrays" ] && echo yes || echo no)"
for arr in $read_arrays; do
    check_eq "read -a array '$arr': no expansion without the empty-array guard" 0 "$(code_only | unguarded_expansions "$arr")"
done

# x01_in_dollar_quote < CODE: lines with a \x01 byte (any spelling) inside $'...'.
x01_in_dollar_quote() { grep -cE "\\$'[^']*\\\\(x01|x1([^0-9A-Fa-f]|')|001|01([^0-7]|')|1([^0-7]|')|cA)" || true; }
check_eq 'control: $'\''\x01'\'' is found' 1 "$(printf '%s\n' "x=\$'\\x01'" | x01_in_dollar_quote)"
check_eq 'control: $'\''\x1'\'' is found' 1 "$(printf '%s\n' "x=\$'\\x1'" | x01_in_dollar_quote)"
check_eq 'control: $'\''\001'\'' is found' 1 "$(printf '%s\n' "x=\$'\\001'" | x01_in_dollar_quote)"
check_eq 'control: $'\''\cA'\'' is found' 1 "$(printf '%s\n' "x=\$'\\cA'" | x01_in_dollar_quote)"
check_eq 'control: $'\''a\x01b'\'' is found' 1 "$(printf '%s\n' "x=\$'a\\x01b'" | x01_in_dollar_quote)"
check_eq 'control: $'\''\x10'\'' is fine' 0 "$(printf '%s\n' "x=\$'\\x10'" | x01_in_dollar_quote)"
check_eq 'control: $'\''\011'\'' (a tab) is fine' 0 "$(printf '%s\n' "x=\$'\\011'" | x01_in_dollar_quote)"
check_eq 'control: $'\''\x1f'\'' (the separator in use) is fine' 0 "$(printf '%s\n' "x=\$'\\x1f'" | x01_in_dollar_quote)"
check_eq 'control: $'\''\n'\'' is fine' 0 "$(printf '%s\n' "x=\$'\\n'" | x01_in_dollar_quote)"
check_eq 'control: a sed backreference \1 outside $'\'''\'' is fine' 0 "$(printf '%s\n' "sed 's/(a)/\\1/'" | x01_in_dollar_quote)"
check_eq 'the code has no $'\''\x01'\'' (bash 4.3 doubles it and sort fails)' 0 "$(code_only | x01_in_dollar_quote)"

# An empty selection must never reach apt, even if a dialog returns only unknown tags.
new_sandbox; fake_installed firefox
app_eval 'declare -a sel_names=() sel_pkgs=(); confirm_and_purge sel_names sel_pkgs'
assert_contains 'an empty selection is reported (English)' "$OUT" 'No applications were selected.'
check_eq 'an empty selection never calls apt (no simulation, no removal)' 0 "$(apt_log | wc -l)"
check_eq 'an empty selection writes no removal record' 0 "$(state_files | wc -l)"
app_eval 'declare -a sel_names=() sel_pkgs=(); confirm_and_purge sel_names sel_pkgs' MINTAPP_LANG=es
assert_contains 'an empty selection is reported (Spanish)' "$OUT" 'No has seleccionado ninguna aplicación.'
check_eq 'an empty selection never calls apt (Spanish)' 0 "$(apt_log | wc -l)"
app_eval 'declare -a sel_names=(Firefox) sel_pkgs=(); confirm_and_purge sel_names sel_pkgs'
check_eq 'names without packages never call apt either' 0 "$(apt_log | wc -l)"
app_eval 'declare -a sel_names=(Firefox) sel_pkgs=(firefox); confirm_and_purge sel_names sel_pkgs'
assert_contains 'control: with a package the simulation does run' "$(apt_log)" 'apt-get -s purge firefox'

echo "-- privilege escalation: sudo, doas, MINTAPP_SUDO (F4.2)"
new_sandbox
# mkpriv DIR NAME [STATUS]: an executable $SB/DIR/NAME that writes its arguments to $SB/DIR/NAME.args
# and exits with STATUS (default 0). It runs nothing else, so it can stand for sudo, doas or anything.
mkpriv() {
    mkdir -p "$SB/$1"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/%s.args"\nexit %s\n' "$SB/$1" "$2" "${3:-0}" > "$SB/$1/$2"
    chmod +x "$SB/$1/$2"
    sandbox_chown
}
mkpriv pb-sudo sudo
mkpriv pb-doas doas
mkpriv pb-both sudo; mkpriv pb-both doas
mkpriv pb-mysu mysu
mkdir -p "$SB/pb-none"; sandbox_chown
# det LABEL EXPECTED [ENV=VAL ...]: "status|PRIV_CMD" after detect_privilege (@SB@ stands for the sandbox).
det() {
    local label="$1" expected="$2" value
    shift 2
    app_eval 'detect_privilege; printf "<<%s|%s>>" "$?" "$PRIV_CMD"' "$@"
    value="${OUT#*<<}"
    check_eq "$label" "${expected//@SB@/$SB}" "${value%%>>*}"
}
det 'only sudo installed: sudo is used'                     '0|@SB@/pb-sudo/sudo' PATH="$SB/pb-sudo"
det 'only doas installed: doas is used'                     '0|@SB@/pb-doas/doas' PATH="$SB/pb-doas"
det 'both installed: sudo is preferred'                     '0|@SB@/pb-both/sudo' PATH="$SB/pb-both"
det 'neither installed: nothing is found'                   '1|' PATH="$SB/pb-none"
det 'MINTAPP_SUDO=doas beats the automatic choice'          '0|@SB@/pb-both/doas' PATH="$SB/pb-both" MINTAPP_SUDO=doas
det 'MINTAPP_SUDO=sudo with both installed'                 '0|@SB@/pb-both/sudo' PATH="$SB/pb-both" MINTAPP_SUDO=sudo
det 'MINTAPP_SUDO with an absolute path'                    '0|@SB@/pb-mysu/mysu' PATH="$SB/pb-none" MINTAPP_SUDO="$SB/pb-mysu/mysu"
det 'MINTAPP_SUDO with a bare name found in PATH'           '0|@SB@/pb-mysu/mysu' PATH="$SB/pb-mysu" MINTAPP_SUDO=mysu
det 'an empty MINTAPP_SUDO means automatic'                 '0|@SB@/pb-sudo/sudo' PATH="$SB/pb-sudo" MINTAPP_SUDO=
det 'a missing MINTAPP_SUDO command is an error, not a fallback to sudo' '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO=nosuch-command
det 'a MINTAPP_SUDO with arguments is refused'              '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO='sudo -n'
det 'a MINTAPP_SUDO that looks like an option is refused'   '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO='-n'
det 'a MINTAPP_SUDO with ";" is refused'                    '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO='sudo;ls'
det 'a MINTAPP_SUDO with $() is refused'                    '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO='$(id)'
det 'a MINTAPP_SUDO with backticks is refused'              '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO='`id`'
det 'a MINTAPP_SUDO with a glob is refused'                 '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO='su*'
det 'a MINTAPP_SUDO pointing at a directory is refused'     '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO="$SB/pb-mysu"
: > "$SB/notexec"; chmod 644 "$SB/notexec"; sandbox_chown
det 'a MINTAPP_SUDO pointing at a non-executable file is refused' '1|' PATH="$SB/pb-sudo" MINTAPP_SUDO="$SB/notexec"
det 'a shell builtin is not accepted as the command'        '1|' PATH="$SB/pb-none" MINTAPP_SUDO=echo
app_eval 'detect_privilege; printf "<<%s>>" "$?"' PATH="$SB/pb-sudo" MINTAPP_SUDO="\$(touch $SB/home/pwned-priv)"
check_eq 'a hostile MINTAPP_SUDO is never executed' 0 "$(find "$SB/home" -name 'pwned-*' | wc -l)"
app_eval 'printf "<<%s>>" "$(priv_name)"' PATH="$SB/pb-none"
check_eq 'priv_name falls back to sudo before any detection' '<<sudo>>' "$OUT"
app_eval 'detect_privilege; printf "<<%s>>" "$(priv_name)"' PATH="$SB/pb-doas"
check_eq 'priv_name names doas when doas is the one in use' '<<doas>>' "$OUT"
app_eval 'detect_privilege; printf "<<%s>>" "$(priv_name)"' PATH="$SB/pb-none" MINTAPP_SUDO="$SB/pb-mysu/mysu"
check_eq 'priv_name names a custom command by its file name' '<<mysu>>' "$OUT"

# apt_privileged: the exact command line each tool receives.
rm -f "$SB"/pb-*/*.args
app_eval 'apt_privileged purge -y firefox; printf "<<%s>>" "$?"' PATH="$SB/pb-sudo"
check_eq 'sudo gets the variable directly' 'DEBIAN_FRONTEND=noninteractive apt-get purge -y firefox' "$(cat "$SB/pb-sudo/sudo.args")"
check_eq 'apt_privileged returns 0 when the command succeeds' '<<0>>' "$OUT"
app_eval 'apt_privileged purge -y firefox' PATH="$SB/pb-doas"
check_eq 'doas gets the variable through env' 'env DEBIAN_FRONTEND=noninteractive apt-get purge -y firefox' "$(cat "$SB/pb-doas/doas.args")"
app_eval 'apt_privileged autoclean -y' PATH="$SB/pb-none" MINTAPP_SUDO="$SB/pb-mysu/mysu"
check_eq 'a custom command also gets the variable through env' 'env DEBIAN_FRONTEND=noninteractive apt-get autoclean -y' "$(cat "$SB/pb-mysu/mysu.args")"
rm -f "$SB"/pb-both/*.args
app_eval 'apt_privileged purge -y firefox' PATH="$SB/pb-both"
check_eq 'with both installed only sudo is called' '1|0' "$(find "$SB/pb-both" -name sudo.args | wc -l)|$(find "$SB/pb-both" -name doas.args | wc -l)"
mkpriv pb-fail sudo 7
app_eval 'apt_privileged purge -y firefox; printf "<<%s>>" "$?"' PATH="$SB/pb-fail"
check_eq 'the exit status of the privileged command is passed on' '<<7>>' "$OUT"
app_eval 'apt_privileged purge -y firefox; printf "<<%s>>" "$?"' PATH="$SB/pb-none"
check_eq 'without any privilege command apt_privileged fails with 127 and runs nothing' '<<127>>' "$OUT"

# Whole program: preflight.
new_sandbox
mkdir -p "$SB/nopriv"
printf '#!/bin/sh\nexit 0\n' > "$SB/nopriv/dpkg"; cp "$SB/nopriv/dpkg" "$SB/nopriv/apt-get"; chmod +x "$SB/nopriv/"*; sandbox_chown
app_run $'\n0\n' PATH="$SB/nopriv"
check_eq 'neither sudo nor doas: a clean error, exit 1' 1 "$RC"
assert_contains 'neither sudo nor doas: English message' "$OUT" 'requires sudo or doas'
app_run $'\n0\n' PATH="$SB/nopriv" MINTAPP_LANG=es
assert_contains 'neither sudo nor doas: Spanish message' "$OUT" 'requiere sudo o doas'
app_run $'\n0\n' MINTAPP_SUDO=nosuch-command
check_eq 'an invalid MINTAPP_SUDO stops the program (exit 1)' 1 "$RC"
assert_contains 'an invalid MINTAPP_SUDO is named in the error (English)' "$OUT" 'MINTAPP_SUDO=nosuch-command is not a valid executable command.'
app_run $'\n0\n' MINTAPP_SUDO=nosuch-command MINTAPP_LANG=es
assert_contains 'an invalid MINTAPP_SUDO is named in the error (Spanish)' "$OUT" 'MINTAPP_SUDO=nosuch-command no es un comando ejecutable válido.'
check_eq 'an invalid MINTAPP_SUDO never reaches apt' 0 "$(apt_log | wc -l)"
app_run $'\n0\n' MINTAPP_SUDO=$'x\033[31mred'
check_eq 'a MINTAPP_SUDO with an escape sequence is printed without the ESC byte' 0 "$(printf '%s' "$OUT" | grep -c $'\033' || true)"
app_run $'\n0\n' MINTAPP_SUDO=
check_eq 'an empty MINTAPP_SUDO starts normally' 0 "$RC"

# Whole program: a removal through doas, and the default (sudo) untouched.
new_sandbox; fake_installed firefox
mkdir -p "$SB/privbin"
printf '#!/bin/bash\necho "doas $*" >> "%s/doas.log"\nexec "$@"\n' "$SB" > "$SB/privbin/doas"; chmod +x "$SB/privbin/doas"; sandbox_chown
app_run $'\n2\n1\nc\ny\n\n0\n' MINTAPP_SUDO="$SB/privbin/doas"
check_eq 'doas: the removal runs and exits 0' 0 "$RC"
check_eq 'doas: exactly one real removal' 1 "$(real_removals)"
check_eq 'doas: it was called with env, as doas needs' 'doas env DEBIAN_FRONTEND=noninteractive apt-get purge -y firefox' "$(head -n1 "$SB/doas.log")"
check_eq 'doas: sudo was not used' 0 "$(sudo_log | wc -l)"
assert_contains 'doas: the record tells how to reinstall with doas' "$(cat "$(state_files | head -n1)")" '# doas apt-get install firefox'
assert_not_contains 'doas: the record does not mention sudo' "$(cat "$(state_files | head -n1)")" 'sudo'
new_sandbox; fake_autoremovable libold1
mkdir -p "$SB/privbin"
printf '#!/bin/bash\necho "doas $*" >> "%s/doas.log"\nexec "$@"\n' "$SB" > "$SB/privbin/doas"; chmod +x "$SB/privbin/doas"; sandbox_chown
app_run $'\n4\n1\ny\n\n0\n' MINTAPP_SUDO="$SB/privbin/doas"
check_eq 'doas: the cleanup runs autoremove and autoclean through doas' 2 "$(wc -l < "$SB/doas.log")"
assert_contains 'doas: autoclean line' "$(cat "$SB/doas.log")" 'doas env DEBIAN_FRONTEND=noninteractive apt-get autoclean -y'
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\ny\n\n0\n'
check_eq 'default: sudo is used for the removal (one call)' 1 "$(sudo_log | wc -l)"
app_eval "PRIV_CMD=/usr/bin/doas; write_removal_record '$SB/rec-doas.txt' interrupted 'Purg foo [1.0]' 'purge foo'; cat '$SB/rec-doas.txt'"
assert_contains 'an interrupted record suggests dpkg --configure through the command in use' "$OUT" 'run: doas dpkg --configure -a'
app_eval "write_removal_record '$SB/rec-sudo.txt' interrupted 'Purg foo [1.0]' 'purge foo'; cat '$SB/rec-sudo.txt'"
assert_contains 'without a detected command the hint says sudo' "$OUT" 'run: sudo dpkg --configure -a'

echo "-- colors: NO_COLOR, TERM and tput (F4.2)"
# bare_eval CODE [ENV=VAL ...]: sources the program in an EMPTY environment (only what is passed, so
# PATH and TERM are exactly the ones the case names) and evals CODE. Output and errors go to OUT.
bare_eval() {
    local code="$1"
    shift
    OUT="$("$ENV_BIN" -i "$@" "$BASH" -c 'source "$1"; eval "$2"' bash "$SCRIPT_FILE" "$code" 2>&1 < /dev/null)" || true
}
ENV_BIN="$(command -v env)"
new_sandbox
# mktput DIR ANSWER [STATUS]: a "tput" that answers ANSWER to "tput colors" and fails for anything else.
mktput() {
    mkdir -p "$SB/$1"
    printf '#!/bin/sh\n[ "$1" = colors ] || exit 1\nprintf "%%s\\n" "%s"\nexit %s\n' "$2" "${3:-0}" > "$SB/$1/tput"
    chmod +x "$SB/$1/tput"
    sandbox_chown
}
mktput tp-256 256; mktput tp-16 16; mktput tp-8 8; mktput tp-7 7; mktput tp-2 2; mktput tp-0 0
mktput tp-neg -1; mktput tp-empty ''; mktput tp-junk abc; mktput tp-fail '' 3
mkdir -p "$SB/tp-none"; sandbox_chown
# col LABEL EXPECTED [ENV=VAL ...]: status of use_color (0 = colors on, 1 = off).
col() {
    local label="$1" expected="$2" value
    shift 2
    bare_eval 'use_color; printf "<<%s>>" "$?"' "$@"
    value="${OUT#*<<}"
    check_eq "$label" "$expected" "${value%%>>*}"
}
col 'the terminal reports 256 colors: on'                       0 PATH="$SB/tp-256" TERM=xterm-256color
col '16 colors: on'                                             0 PATH="$SB/tp-16" TERM=xterm
col 'exactly 8 colors is enough: on'                            0 PATH="$SB/tp-8" TERM=xterm
col '7 colors: off'                                             1 PATH="$SB/tp-7" TERM=xterm
col '2 colors: off'                                             1 PATH="$SB/tp-2" TERM=xterm
col '0 colors: off'                                             1 PATH="$SB/tp-0" TERM=xterm
col 'tput says -1 (no color capability): off'                   1 PATH="$SB/tp-neg" TERM=xterm
col 'an answer that is not a number: off'                       1 PATH="$SB/tp-junk" TERM=xterm
col 'tput prints nothing (cannot tell): on'                     0 PATH="$SB/tp-empty" TERM=xterm
col 'tput fails, e.g. unknown terminal (cannot tell): on'       0 PATH="$SB/tp-fail" TERM=xterm
col 'no tput installed (cannot tell): on'                       0 PATH="$SB/tp-none" TERM=xterm
col 'NO_COLOR=1 beats a terminal with 256 colors'               1 PATH="$SB/tp-256" TERM=xterm-256color NO_COLOR=1
col 'NO_COLOR=0 also disables: any non-empty value counts'      1 PATH="$SB/tp-256" TERM=xterm NO_COLOR=0
col 'NO_COLOR=yes disables'                                     1 PATH="$SB/tp-256" TERM=xterm NO_COLOR=yes
col 'NO_COLOR=" " (a space) disables: it is not empty'          1 PATH="$SB/tp-256" TERM=xterm NO_COLOR=' '
col 'an empty NO_COLOR is ignored'                              0 PATH="$SB/tp-256" TERM=xterm NO_COLOR=
col 'NO_COLOR=1 without tput disables as well'                  1 PATH="$SB/tp-none" TERM=xterm NO_COLOR=1
# TERM=dumb is checked on its own, so these two do not depend on what tput says about "dumb".
col 'TERM=dumb without tput: off'                               1 PATH="$SB/tp-none" TERM=dumb
col 'TERM=dumb beats a tput that reports 256 colors'            1 PATH="$SB/tp-256" TERM=dumb
col 'TERM=dumb with NO_COLOR empty: still off'                  1 PATH="$SB/tp-none" TERM=dumb NO_COLOR=
# Without TERM in its environment bash sets TERM=dumb for itself without exporting it: unknown, not dumb.
bare_eval 'printf "<<%s>>" "$(declare -p TERM 2>&1)"' PATH="$SB/tp-none"
assert_contains 'premise: with no TERM bash sets its own, unexported TERM=dumb' "$OUT" '<<declare -- TERM="dumb">>'
col 'no TERM in the environment, no tput: on (bash'"'"'s own dumb is not the user'"'"'s)' 0 PATH="$SB/tp-none"
col 'no TERM in the environment, tput reports 256: on'          0 PATH="$SB/tp-256"
col 'an empty TERM without tput: on'                            0 PATH="$SB/tp-none" TERM=
col 'TERM=linux with 8 colors: on'                              0 PATH="$SB/tp-8" TERM=linux

# What setup_colors does with the answer.
setup_state() {  # prints C_OK C_MARK NEWT_MONO NEWT_COLORS (as set/unset), after export to a child
    bare_eval 'all="$C_RESET$C_TITLE$C_OK$C_WARN$C_MARK$C_ERR$C_BOLD"
        printf "<<%s|%s|%s|%s>>" "${all:+codes}" "${C_MARK:+mark}" "$("$BASH" -c "printf %s \"\${NEWT_MONO:-unset}\"")" "$("$BASH" -c "printf %s \"\${NEWT_COLORS:+palette}\"")"' "$@"
    value="${OUT#*<<}"
    value="${value%%>>*}"
}
setup_state PATH="$SB/tp-256" TERM=xterm
check_eq 'colors on: ANSI codes, a marked item and the whiptail palette (no monochrome)' 'codes|mark|unset|palette' "$value"
setup_state PATH="$SB/tp-256" TERM=xterm NO_COLOR=1
check_eq 'NO_COLOR: no ANSI codes at all, and whiptail goes monochrome' '||1|' "$value"
setup_state PATH="$SB/tp-none" TERM=dumb
check_eq 'TERM=dumb: no ANSI codes, whiptail monochrome' '||1|' "$value"
setup_state PATH="$SB/tp-2" TERM=xterm
check_eq 'a 2-color terminal: no ANSI codes, whiptail monochrome' '||1|' "$value"
bare_eval 'printf "<<%s>>" "$C_MARK"' PATH="$SB/tp-256" TERM=xterm
assert_contains 'colors on: a marked item is a solid block (black on green)' "$OUT" '30;42'
bare_eval 'printf "<<%s>>" "$NEWT_COLORS"' PATH="$SB/tp-256" TERM=xterm
assert_contains 'colors on: the whiptail palette keeps the green/black/blue scheme' "$OUT" 'actlistbox=black,green'

# Whole program. clear and tput may print cursor sequences that are not colors, so only SGR
# sequences (ESC [ ... m) are counted.
sgr_count() { printf '%s' "$1" | grep -c $'\033\\[[0-9;]*m' || true; }
new_sandbox; fake_installed firefox thunderbird
app_run $'\n1\n\n2\n1\nx\n99\nc\nn\n\n0\n' TERM=xterm-256color NO_COLOR=
check_eq 'colors on: the screens use SGR colors' 1 "$([ "$(sgr_count "$OUT")" -gt 0 ] && echo 1 || echo 0)"
app_run $'\n1\n\n2\n1\nx\n99\nc\nn\n\n0\n' TERM=xterm-256color NO_COLOR=1
check_eq 'NO_COLOR=1: detect, selection, errors and plan have no SGR color at all' 0 "$(sgr_count "$OUT")"
check_eq 'NO_COLOR=1: the program still works (exit 0)' 0 "$RC"
assert_contains 'NO_COLOR=1: a marked item is still told apart by its symbol' "$OUT" '☑ Firefox'
assert_contains 'NO_COLOR=1: an unmarked item has its own symbol' "$OUT" '☐ Thunderbird'
assert_contains 'NO_COLOR=1: errors still say what happened' "$OUT" 'Invalid option.'
app_run $'\n1\n\n0\n' TERM=dumb
check_eq 'TERM=dumb: no SGR color' 0 "$(sgr_count "$OUT")"
check_eq 'TERM=dumb: the program still starts and exits 0' 0 "$RC"
app_run $'\n1\n\n0\n' TERM=dumb MINTAPP_LANG=es
assert_contains 'TERM=dumb: the Spanish screens are intact too' "$OUT" 'aplicaciones detectadas.'

echo "-- ASCII mode: choice of Unicode or ASCII (F4.2)"
# us LABEL EXPECTED [ENV=VAL ...]: status of use_unicode (0 = Unicode, 1 = ASCII). Without "locale" in
# the PATH the decision is made from LC_ALL, LC_CTYPE and LANG, in that order.
us() {
    local label="$1" expected="$2" value
    shift 2
    bare_eval 'use_unicode; printf "<<%s>>" "$?"' PATH="$SB/tp-none" "$@"
    value="${OUT#*<<}"
    check_eq "$label" "$expected" "${value%%>>*}"
}
us 'no locale at all: ASCII'                                    1
us 'LANG=es_ES.UTF-8: Unicode'                                  0 LANG=es_ES.UTF-8
us 'LANG=en_US.utf8: Unicode (any case, with or without the dash)' 0 LANG=en_US.utf8
us 'LANG=es_ES.UTF8: Unicode'                                   0 LANG=es_ES.UTF8
us 'LANG=C.UTF-8: Unicode'                                      0 LANG=C.UTF-8
us 'LANG=es_ES.ISO-8859-1: ASCII'                               1 LANG=es_ES.ISO-8859-1
us 'LANG=es_ES.ISO8859-15@euro: ASCII'                          1 LANG=es_ES.ISO8859-15@euro
us 'LANG=C: ASCII'                                              1 LANG=C
us 'LANG=POSIX: ASCII'                                          1 LANG=POSIX
us 'LC_ALL beats LANG (UTF-8 over C)'                           0 LC_ALL=C.UTF-8 LANG=C
us 'LC_ALL beats LANG (C over UTF-8)'                           1 LC_ALL=C LANG=es_ES.UTF-8
us 'LC_CTYPE beats LANG (UTF-8 over C)'                         0 LC_CTYPE=es_ES.UTF-8 LANG=C
us 'LC_CTYPE beats LANG (C over UTF-8)'                         1 LC_CTYPE=C LANG=es_ES.UTF-8
us 'LC_ALL beats LC_CTYPE'                                      1 LC_ALL=C LC_CTYPE=es_ES.UTF-8
us 'an empty LC_ALL is the same as unset'                       0 LC_ALL= LANG=es_ES.UTF-8
us 'LC_MESSAGES alone does not make the terminal UTF-8'         1 LC_MESSAGES=es_ES.UTF-8
us 'LANGUAGE alone does not make the terminal UTF-8'            1 LANGUAGE=es
us 'MINTAPP_ASCII=1 forces ASCII in a UTF-8 locale'             1 MINTAPP_ASCII=1 LANG=es_ES.UTF-8
us 'MINTAPP_ASCII=0 forces Unicode without a locale'            0 MINTAPP_ASCII=0
us 'MINTAPP_ASCII=0 forces Unicode in the C locale'             0 MINTAPP_ASCII=0 LANG=C
us 'an empty MINTAPP_ASCII is automatic (UTF-8 locale)'         0 MINTAPP_ASCII= LANG=es_ES.UTF-8
us 'an empty MINTAPP_ASCII is automatic (C locale)'             1 MINTAPP_ASCII= LANG=C
us 'any other MINTAPP_ASCII value is automatic (UTF-8 locale)'  0 MINTAPP_ASCII=maybe LANG=es_ES.UTF-8
us 'any other MINTAPP_ASCII value is automatic (C locale)'      1 MINTAPP_ASCII=maybe LANG=C
# With "locale" available its real charmap decides, because a name in LANG proves nothing when that
# locale was never generated on the machine.
if command -v locale > /dev/null 2>&1 && locale -a 2> /dev/null | grep -qix 'c\.utf-\?8'; then
    real_us() { local label="$1" expected="$2" value; shift 2; bare_eval 'use_unicode; printf "<<%s>>" "$?"' PATH=/usr/bin:/bin "$@"; value="${OUT#*<<}"; check_eq "$label" "$expected" "${value%%>>*}"; }
    real_us 'locale present: a generated UTF-8 locale gives Unicode' 0 LC_ALL=C.UTF-8
    real_us 'locale present: LC_ALL beats LANG' 0 LC_ALL=C.UTF-8 LANG=C
    real_us 'locale present: the C locale gives ASCII' 1 LC_ALL=C
    real_us 'locale present: a UTF-8 name that was never generated gives ASCII' 1 LC_ALL=xx_YY.UTF-8
    real_us 'locale present: MINTAPP_ASCII=1 still forces ASCII' 1 LC_ALL=C.UTF-8 MINTAPP_ASCII=1
else
    skip_case 'locale present: the real charmap decides (no generated UTF-8 locale or no locale command)'
fi
# symbols() prints "UNICODE|SYM_OK|SYM_ON|SYM_OFF|SYM_DASH" (UNICODE is 1 for Unicode, 0 for ASCII).
symbols() {
    bare_eval 'printf "<<%s|%s|%s|%s|%s>>" "$UNICODE" "$SYM_OK" "$SYM_ON" "$SYM_OFF" "$SYM_DASH"' PATH="$SB/tp-none" "$@"
    value="${OUT#*<<}"
    value="${value%%>>*}"
}
symbols MINTAPP_ASCII=1
check_eq 'ASCII symbols: + [x] [ ] -' '0|+|[x]|[ ]|-' "$value"
symbols MINTAPP_ASCII=0
check_eq 'Unicode symbols: ✓ ☑ ☐ —' '1|✓|☑|☐|—' "$value"
symbols LANG=C
check_eq 'the symbols follow the automatic choice (C locale: ASCII)' '0|+|[x]|[ ]|-' "$value"
symbols LANG=es_ES.UTF-8
check_eq 'the symbols follow the automatic choice (UTF-8 locale: Unicode)' '1|✓|☑|☐|—' "$value"

echo "-- ASCII mode: folding the program's own text (F4.2)"
# fold LABEL EXPECTED INPUT [ENV=VAL ...]: what ascii_fold leaves in REPLY. The default environment has no
# locale (bytes), which is the case ASCII mode is for; a few cases also run in a UTF-8 locale.
fold() {
    local label="$1" expected="$2" input="$3" value
    shift 3
    bare_eval 'ascii_fold "$TXT"; printf "<<%s>>" "$REPLY"' PATH="$SB/tp-none" TXT="$input" "$@"
    value="${OUT#*<<}"
    check_eq "$label" "$expected" "${value%>>}"
}
fold 'arrows become ^ and v'                          '^ v'                     '↑ ↓'
fold 'left and right arrows become <- and ->'            '<- ->'                   '← →'
fold 'the em dash becomes a hyphen'                   'a - b'                   'a — b'
fold 'the check mark becomes +'                       '+ ok'                    '✓ ok'
fold 'check boxes become [x] and [ ]'                 '[x] on [ ] off'          '☑ on ☐ off'
fold 'lowercase accents and ñ lose them'              'aeiouun'                 'áéíóúüñ'
fold 'uppercase accents and Ñ lose them'              'AEIOUUN'                 'ÁÉÍÓÚÜÑ'
fold 'the opening ¿ and ¡ are dropped'                'Seguro? Hecho!'          '¿Seguro? ¡Hecho!'
fold 'a repeated opening mark is dropped every time'  'aaa'                     '¿¿ááá'
fold 'plain ASCII is left untouched'                  'Plain text 123 %s \\n [x]' 'Plain text 123 %s \\n [x]'
fold 'glob characters, & and backslashes are left alone' 'a*b?c[d]&\\e'         'a*b?c[d]&\\e'
fold 'an empty string stays empty'                    ''                        ''
fold 'characters the program never uses are kept'    'çœ€ 日本'               'çœ€ 日本'
fold 'a whole Spanish sentence'                       'Como moverse: ^ / v - Pulsa Enter' 'Cómo moverse: ↑ / ↓ — Pulsa Enter'
fold 'several lines'                                  $'a\ne'                    $'á\né'
fold 'a printf format keeps its conversions'          'Version %s: %s de %s'    'Versión %s: %s de %s'
bare_eval 'ascii_fold "á"; ascii_fold "b"; printf "<<%s>>" "$REPLY"' PATH="$SB/tp-none"
check_eq 'REPLY is replaced on every call, never appended' '<<b>>' "$OUT"
if command -v locale > /dev/null 2>&1 && locale -a 2> /dev/null | grep -qix 'c\.utf-\?8'; then
    fold 'in a UTF-8 locale: accents and symbols fold the same way' 'Como esta? ^ v - + [x] [ ] nN' '¿Cómo está? ↑ ↓ — ✓ ☑ ☐ ñÑ' PATH=/usr/bin:/bin LC_ALL=C.UTF-8
    fold 'in a UTF-8 locale: other characters are kept'               'çœ€ 日本' 'çœ€ 日本' PATH=/usr/bin:/bin LC_ALL=C.UTF-8
else
    skip_case 'ascii_fold in a UTF-8 locale (no generated UTF-8 locale)'
fi

echo "-- ASCII mode: every message and catalog entry (F4.2)"
# For each key of both languages: how many strings there are and how many still hold a byte >= 0x80.
walk_all() {  # walk_all MODE: "strings|non-ASCII strings|changed by folding" for ascii/unicode
    bare_eval 'n=0; bad=0; for lang in en es; do APP_LANG="$lang"
        for k in "${!MSG_EN[@]}"; do v="$(msg "$k")"; n=$((n+1)); [ -z "$(printf %s "$v" | LC_ALL=C tr -d "\\000-\\177")" ] || bad=$((bad+1)); done
        for k in "${!APP_NAME_EN[@]}"; do for f in catalog_name catalog_desc; do v="$($f "$k")"; n=$((n+1)); [ -z "$(printf %s "$v" | LC_ALL=C tr -d "\\000-\\177")" ] || bad=$((bad+1)); done; done
    done; printf "<<%s|%s>>" "$n" "$bad"' PATH=/usr/bin:/bin "$@"
    value="${OUT#*<<}"
    value="${value%%>>*}"
}
walk_all MINTAPP_ASCII=1
check_eq 'ASCII mode: no message or catalog string keeps a non-ASCII byte' 0 "${value#*|}"
check_eq 'ASCII mode: the walk covers a real number of strings (both languages, messages and catalog)' 1 "$([ "${value%%|*}" -gt 200 ] && echo 1 || echo 0)"
walk_all MINTAPP_ASCII=0
check_eq 'Unicode mode: the text keeps its accents (the check above is not vacuous)' 1 "$([ "${value#*|}" -gt 40 ] && echo 1 || echo 0)"
bare_eval 'APP_LANG=es; printf "<<%s>>" "$(msg nav_title)"' PATH=/usr/bin:/bin MINTAPP_ASCII=0
check_eq 'Unicode mode: Spanish keeps its accents' '<<CÓMO MOVERSE POR LOS MENÚS>>' "$OUT"
bare_eval 'APP_LANG=es; printf "<<%s>>" "$(msg nav_title)"' PATH=/usr/bin:/bin MINTAPP_ASCII=1
check_eq 'ASCII mode: Spanish loses them' '<<COMO MOVERSE POR LOS MENUS>>' "$OUT"
bare_eval 'APP_LANG=en; printf "<<%s>>" "$(msg nav_title)"' PATH=/usr/bin:/bin MINTAPP_ASCII=1
check_eq 'ASCII mode: English is unchanged' '<<HOW TO NAVIGATE THE MENUS>>' "$OUT"
bare_eval 'APP_LANG=es; printf "<<%s>>" "$(msg select_help)"' PATH=/usr/bin:/bin MINTAPP_ASCII=1
assert_contains 'ASCII mode: the arrows of the help line become ^ and v' "$OUT" '(^ v mover |'
bare_eval 'APP_LANG=es; printf "<<%s>>" "$(msg select_help)"' PATH=/usr/bin:/bin MINTAPP_ASCII=0
assert_contains 'Unicode mode: the arrows stay' "$OUT" '(↑ ↓ mover |'
bare_eval 'APP_LANG=es; printf "<<%s|%s>>" "$(catalog_name image_viewer)" "$(catalog_desc thunderbird)"' PATH=/usr/bin:/bin MINTAPP_ASCII=1
check_eq 'ASCII mode: a catalog name and a catalog description lose their accents' '<<Visor de imagenes|Cliente de correo electronico>>' "$OUT"
bare_eval 'APP_LANG=es; printf "<<%s|%s>>" "$(catalog_name image_viewer)" "$(catalog_desc thunderbird)"' PATH=/usr/bin:/bin MINTAPP_ASCII=0
check_eq 'Unicode mode: they keep them' '<<Visor de imágenes|Cliente de correo electrónico>>' "$OUT"

echo "-- ASCII mode: whole program (F4.2)"
# nonascii TEXT: how many bytes >= 0x80 the text holds.
nonascii() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\177' | wc -c | tr -d ' '; }
# detect, then uninstall with a selection, plan, confirmation and result, then exit.
FLOW=$'\n1\n\n2\n1\nc\ny\n\n0\n'
new_sandbox; fake_installed firefox thunderbird
app_run "$FLOW" MINTAPP_ASCII=1 MINTAPP_LANG=es
check_eq 'ASCII + Spanish: the whole flow exits 0' 0 "$RC"
check_eq 'ASCII + Spanish: not a single non-ASCII byte on screen' 0 "$(nonascii "$OUT")"
P="$(plain)"
assert_contains 'ASCII + Spanish: the result has no accents' "$P" 'Desinstalacion completada.'
assert_contains 'ASCII + Spanish: catalog text has no accents' "$P" 'Cliente de correo electronico'
assert_contains 'ASCII + Spanish: detected apps are marked with +' "$P" '+ Firefox'
assert_contains 'ASCII + Spanish: a marked item shows [x]' "$P" '[x] Firefox'
assert_contains 'ASCII + Spanish: an unmarked item shows [ ]' "$P" '[ ] Thunderbird'
check_eq 'ASCII + Spanish: the removal itself is unaffected' 1 "$(real_removals)"
assert_contains 'ASCII + Spanish: the purge is the same' "$(apt_log)" 'apt-get purge -y firefox'
new_sandbox; fake_installed firefox thunderbird
app_run "$FLOW" MINTAPP_ASCII=1 MINTAPP_LANG=en
check_eq 'ASCII + English: not a single non-ASCII byte on screen' 0 "$(nonascii "$OUT")"
assert_contains 'ASCII + English: same symbols' "$(plain)" '[x] Firefox'
new_sandbox; fake_installed firefox thunderbird
app_run "$FLOW" MINTAPP_ASCII=0 MINTAPP_LANG=es
P="$(plain)"
assert_contains 'Unicode + Spanish: accents stay' "$P" 'Desinstalación completada.'
assert_contains 'Unicode + Spanish: detected apps are marked with ✓' "$P" '✓ Firefox'
assert_contains 'Unicode + Spanish: a marked item shows ☑' "$P" '☑ Firefox'
assert_contains 'Unicode + Spanish: an unmarked item shows ☐' "$P" '☐ Thunderbird'
assert_contains 'Unicode + Spanish: catalog text keeps its accents' "$P" 'Cliente de correo electrónico'
check_eq 'Unicode: the same flow removes the same package' 1 "$(real_removals)"

# Automatic choice, end to end: an empty MINTAPP_ASCII lets the locale decide.
new_sandbox
app_run $'\n0\n' MINTAPP_ASCII= LC_ALL=C MINTAPP_LANG=es
assert_contains 'automatic + C locale: the screens are in ASCII' "$OUT" 'COMO MOVERSE POR LOS MENUS'
check_eq 'automatic + C locale: no non-ASCII byte' 0 "$(nonascii "$OUT")"
if command -v locale > /dev/null 2>&1 && locale -a 2> /dev/null | grep -qix 'c\.utf-\?8'; then
    app_run $'\n0\n' MINTAPP_ASCII= LC_ALL=C.UTF-8 MINTAPP_LANG=es
    assert_contains 'automatic + UTF-8 locale: the screens keep their accents' "$OUT" 'CÓMO MOVERSE POR LOS MENÚS'
else
    skip_case 'automatic + UTF-8 locale (no generated UTF-8 locale)'
fi

# Names that come from the system are shown as they are: only the program's own text is folded.
new_sandbox; fake_installed cafe-pkg
make_desktop 'cafe.desktop' 'Café app'; fake_owner "$SB/apps/cafe.desktop" cafe-pkg
sandbox_chown
app_run $'\n3\n\nc\n\n0\n' MINTAPP_ASCII=1 MINTAPP_LANG=es
P="$(plain)"
assert_contains 'ASCII: the program text around a system name is folded' "$P" 'MODO AVANZADO - aplicaciones detectadas mediante los lanzadores del menu'
assert_contains 'ASCII: a launcher name from the system is shown as it is' "$P" 'Café app [cafe-pkg]'
check_eq 'ASCII: the only non-ASCII bytes are the two of the "é" in that name' 2 "$(nonascii "$OUT")"
# The name of the system is data and reaches the screen only in the status line of the main menu (F7.0), never in
# the title (FP.1). ASCII mode folds it (ascii_only): what has no ASCII form becomes "?", one per character in a
# UTF-8 locale and one per byte in any other (the case ASCII mode is for). Unicode keeps it whole.
new_sandbox
printf 'ID=cafe\nPRETTY_NAME="Café ☃ OS 1"\n' > "$SB/os-release-cafe"; sandbox_chown
# cafe_run [VAR=val ...]: runs the text menu on that system; CAFE_LINE is its status line, without the leading space.
cafe_run() {
    app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1 MINTAPP_OS_RELEASE="$SB/os-release-cafe" "$@"
    CAFE_LINE="$(plain | grep -a -m1 'detected$' | sed 's/^ //')" || true
}
cafe_run MINTAPP_ASCII=1
check_eq 'ASCII, no locale (bytes): what has no ASCII form becomes one "?" per byte' 'Cafe ??? OS 1 | apt | 0 applications detected' "$CAFE_LINE"
check_eq 'ASCII, no locale: the screens stay pure ASCII whatever the system is called' 0 "$(nonascii "$OUT")"
check_eq 'ASCII: the name is on the status line only, not in the title' 1 "$(plain | grep -ac 'Caf')"
cafe_run MINTAPP_ASCII=0
check_eq 'Unicode, no locale: the name is kept whole' 'Café ☃ OS 1 · apt · 0 applications detected' "$CAFE_LINE"
if command -v locale > /dev/null 2>&1 && locale -a 2> /dev/null | grep -qix 'c\.utf-\?8'; then
    cafe_run MINTAPP_ASCII=1 LC_ALL=C.UTF-8
    check_eq 'ASCII forced in a UTF-8 locale: one "?" per character' 'Cafe ? OS 1 | apt | 0 applications detected' "$CAFE_LINE"
    check_eq 'ASCII forced in a UTF-8 locale: the screens stay pure ASCII' 0 "$(nonascii "$OUT")"
    cafe_run MINTAPP_ASCII=0 LC_ALL=C.UTF-8
    check_eq 'Unicode in a UTF-8 locale: the name is kept whole' 'Café ☃ OS 1 · apt · 0 applications detected' "$CAFE_LINE"
else
    skip_case 'status line with a non-ASCII system name in a UTF-8 locale (no generated UTF-8 locale)'
fi

# --help and the dialogs.
new_sandbox
app_run '' MINTAPP_ASCII=1 MINTAPP_LANG=es -- --help
check_eq 'ASCII: --help in Spanish has no non-ASCII byte' 0 "$(nonascii "$OUT")"
assert_contains 'ASCII: --help in Spanish folds the usage line' "$OUT" 'Uso: MintApp_Remover.sh [OPCION]'
assert_contains 'ASCII: --help documents MINTAPP_ASCII' "$OUT" 'MINTAPP_ASCII=1|0'
assert_contains 'ASCII: --help documents NO_COLOR' "$OUT" 'NO_COLOR=1'
app_run '' MINTAPP_ASCII=0 MINTAPP_LANG=es -- --help
assert_contains 'Unicode: --help in Spanish keeps its accents' "$OUT" 'Uso: MintApp_Remover.sh [OPCIÓN]'
app_run '' MINTAPP_ASCII=0 MINTAPP_LANG=en -- --help
assert_contains 'English --help documents MINTAPP_ASCII' "$OUT" 'Force plain ASCII text (1) or Unicode symbols (0).'
new_sandbox; fake_installed firefox
fake_answers OK TAG:2 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail MINTAPP_ASCII=1 MINTAPP_LANG=es
WT_LOG="$(cat "$SB/state/whiptail.log")"
check_eq 'ASCII dialogs: the whole flow exits 0' 0 "$RC"
check_eq 'ASCII dialogs: every argument given to whiptail is ASCII' 0 "$(nonascii "$WT_LOG")"
assert_contains 'ASCII dialogs: the checklist separator is a hyphen' "$WT_LOG" 'Firefox - '
check_eq 'ASCII dialogs: the purge still happens' 1 "$(real_removals)"
new_sandbox; fake_installed firefox
fake_answers OK TAG:2 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail MINTAPP_ASCII=0 MINTAPP_LANG=es
assert_contains 'Unicode dialogs: the checklist separator is an em dash' "$(cat "$SB/state/whiptail.log")" 'Firefox — '

echo "-- option 1: detect"
new_sandbox; fake_installed firefox thunderbird
app_run $'\n1\n\n0\n'; P="$(plain)"
check_eq 'detect exits 0' 0 "$RC"
assert_contains 'detect lists Firefox' "$P" 'Firefox'
assert_contains 'detect lists Thunderbird' "$P" 'Thunderbird'
assert_contains 'detect reports the count' "$P" '2 applications detected.'
assert_not_contains 'detect omits apps that are not installed' "$P" 'Rhythmbox'
check_eq 'detect never calls apt' 0 "$(apt_log | wc -l)"
new_sandbox; fake_installed pix; fake_configfiles pix
app_run $'\n1\n\n0\n'; P="$(plain)"
assert_contains 'a package with only config files is not "installed"' "$P" '0 applications detected.'
new_sandbox; fake_installed firefox
app_run $'\n1\n\n0\n'
assert_contains 'singular count' "$OUT" '1 application detected.'
app_run $'\nl\n1\n\n0\n'
assert_contains 'detect speaks Spanish after switching' "$OUT" 'aplicación detectada.'

echo "-- option 2: uninstall"
new_sandbox; fake_installed firefox thunderbird
app_run $'\n2\n1\nc\ny\n\n0\n'; P="$(plain)"
check_eq 'confirmed purge exits 0' 0 "$RC"
check_eq 'exactly one real removal' 1 "$(real_removals)"
assert_contains 'purge targets the selected package' "$(apt_log)" 'apt-get purge -y firefox'
assert_not_contains 'purge leaves the unselected package alone' "$(apt_log)" 'thunderbird'
assert_contains 'the apt plan is shown before confirming' "$P" 'Purg firefox'
assert_contains 'success is reported' "$P" 'Uninstallation completed successfully.'
assert_contains 'the removal record is announced' "$P" 'A record of what was removed was saved to:'
check_eq 'one removal record is written' 1 "$(state_files | wc -l)"
REC="$(state_files | head -n1)"
assert_contains 'record has the final status' "$(cat "$REC")" '# Status: completed'
assert_contains 'record lists the plan' "$(cat "$REC")" 'Purg firefox'
assert_contains 'record explains how to reinstall' "$(cat "$REC")" 'sudo apt-get install firefox'
check_eq 'record is private (mode 600)' 600 "$(stat -c %a "$REC")"
check_eq 'no temporary files are left behind' 0 "$(find "$SB/home" -name '.tmp.*' | wc -l)"
new_sandbox; fake_installed firefox thunderbird
app_run $'\n2\n1\n2\nc\ny\n\n0\n'
assert_contains 'several selections go in one purge' "$(apt_log)" 'apt-get purge -y firefox thunderbird'
new_sandbox; fake_installed firefox
app_run $'\n2\n1\n1\nc\n\n0\n'
assert_contains 'marking an item twice unmarks it' "$OUT" 'No applications were selected.'
check_eq 'unmarked selection removes nothing' 0 "$(real_removals)"
new_sandbox; fake_installed libreoffice-core libreoffice-writer
app_run $'\n2\n1\nc\ny\n\n0\n'
assert_contains 'multi-package entries purge only the installed packages' "$(apt_log)" 'apt-get purge -y libreoffice-core libreoffice-writer'
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\nn\n\n0\n'
check_eq 'answering no removes nothing' 0 "$(real_removals)"
assert_contains 'answering no says cancelled' "$OUT" 'Operation cancelled.'
app_run $'\n2\n1\nc\n\n\n0\n'
check_eq 'an empty answer is a no' 0 "$(real_removals)"
app_run $'\n2\n1\nc\n'
check_eq 'end of input at the confirmation is a no' 0 "$(real_removals)"
app_run $'\n2\n0\n0\n'
check_eq 'option 0 goes back without removing' 0 "$(real_removals)"
app_run $'\n2\nx\n99\n0\n0\n'
assert_contains 'garbage in the selection is reported' "$OUT" 'Invalid option.'
assert_contains 'out-of-range numbers are reported' "$OUT" 'Number out of range.'
new_sandbox
app_run $'\n2\n\n0\n'
assert_contains 'nothing installed: explained' "$OUT" 'No installed applications from the curated catalog were detected.'
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon
app_run $'\n2\n1\nc\nn\n\n0\n'
assert_contains 'dragged dependents appear in the plan' "$OUT" 'Purg mint-meta-cinnamon'

echo "-- apt plan handling (simulation without sudo)"
new_sandbox
NOTE_EN=$'NOTE: This is only a simulation!\n      apt-get needs root privileges for real execution.\n      Keep also in mind that locking is deactivated,\n      so don\'t depend on the relevance to the real current situation!'
NOTE_ES=$'NOTA: ¡Esto es solo una simulación!\n      apt-get necesita privilegios de root para la ejecución real.\n      Tenga también en cuenta que el bloqueo está desactivado,\n      por lo que no dependa de la relevancia de la situación real actual.'
strip_case() {  # strip_case INPUT: sets OUT to what strip_apt_note leaves
    local input="$1"
    printf '%s\n' "$input" > "$SB/note-input.txt"; chmod 644 "$SB/note-input.txt"
    app_eval "strip_apt_note < '$SB/note-input.txt'"
}
strip_case "$NOTE_EN"$'\nReading package lists...\nPurg foo [1.0]'
check_eq 'the English apt NOTE is removed' $'Reading package lists...\nPurg foo [1.0]' "$OUT"
strip_case "$NOTE_ES"$'\nLeyendo lista de paquetes...\nPurg foo [1.0]'
check_eq 'a translated apt NOTE is removed by its shape' $'Leyendo lista de paquetes...\nPurg foo [1.0]' "$OUT"
strip_case $'Reading package lists...\nBuilding dependency tree...\nPurg foo [1.0]'
check_eq 'output without a NOTE is left untouched' $'Reading package lists...\nBuilding dependency tree...\nPurg foo [1.0]' "$OUT"
strip_case $'Purg foo [1.0]\n      x\n      y'
check_eq 'a plan line is never taken for a NOTE' $'Purg foo [1.0]\n      x\n      y' "$OUT"
strip_case $'Header\n      only one indented line\nPurg foo [1.0]'
check_eq 'one indented line is not enough to be a NOTE' $'Header\n      only one indented line\nPurg foo [1.0]' "$OUT"
strip_case $'Reading package lists...\n'"$NOTE_EN"$'\nPurg foo [1.0]'
check_eq 'a NOTE in the middle of the output is not touched' $'Reading package lists...\n'"$NOTE_EN"$'\nPurg foo [1.0]' "$OUT"
strip_case ''
check_eq 'empty output stays empty' '' "$OUT"
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\nn\n\n0\n'
assert_not_contains 'the plan shown to the user has no simulation NOTE' "$OUT" 'only a simulation'
assert_contains 'the plan shown to the user keeps the apt summary' "$OUT" 'The following packages will be REMOVED'
if command -v apt-get >/dev/null 2>&1 && [ -r /var/lib/dpkg/status ]; then
    new_sandbox
    app_eval 'pm_simulate autoremove; printf "<<rc=%s>>%s" "$?" "$PLAN_OUTPUT"' PATH=/usr/bin:/bin
    assert_contains 'real apt-get -s works without root or sudo' "$OUT" '<<rc=0>>'
    assert_not_contains 'real apt-get output has no NOTE after stripping' "$OUT" 'simulation'
    app_eval 'pm_simulate purge mintapp-no-such-package-xyz; printf "<<rc=%s>>%s" "$?" "$PLAN_OUTPUT"' PATH=/usr/bin:/bin
    assert_contains 'a failed real simulation keeps apt exit status' "$OUT" '<<rc=100>>'
    assert_contains 'a failed real simulation keeps the apt error text' "$OUT" 'mintapp-no-such-package-xyz'
else
    skip_case 'real apt-get -s works without root or sudo (apt-get not available)'
fi

echo "-- removal safety nets"
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\ny\n\n0\n' FAKE_APT_DRIFT=1
check_eq 'a plan that changed after confirming runs nothing' 0 "$(real_removals)"
assert_contains 'the changed plan is explained' "$OUT" 'The system changed after the plan was calculated'
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\n\n0\n' FAKE_APT_SIM_FAIL=1
check_eq 'a failed simulation removes nothing' 0 "$(real_removals)"
assert_contains 'a failed simulation is explained' "$OUT" 'Could not calculate an uninstallation plan'
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\ny\n\n0\n' FAKE_APT_FAIL=100
assert_contains 'a failed apt run is reported with its exit code' "$OUT" 'Uninstallation failed (exit code 100)'
assert_contains 'the record shows the failure' "$(cat "$(state_files | head -n1)")" 'failed (apt-get exit code 100)'
new_sandbox; fake_installed firefox
mkdir -p "$SB/home/.local" && : > "$SB/home/.local/state" && sandbox_chown
app_run $'\n2\n1\nc\ny\n\n0\n'
check_eq 'an unwritable record location does not block the removal' 1 "$(real_removals)"
assert_contains 'an unwritable record location is reported' "$OUT" 'could not be saved'

echo "-- option 3: advanced mode"
new_sandbox
fake_installed vlc inkscape coretool esstool firefox
make_desktop vlc.desktop 'VLC media player';          fake_owner "$SB/apps/vlc.desktop" vlc
make_desktop inkscape.desktop 'Inkscape' 'Name[es]=Inkscape Editor vectorial'; fake_owner "$SB/apps/inkscape.desktop" inkscape
make_desktop settings.desktop 'Settings';             fake_owner "$SB/apps/settings.desktop" cinnamon-control-center
make_desktop hidden.desktop 'Hidden tool' 'NoDisplay=true'; fake_owner "$SB/apps/hidden.desktop" hiddentool
make_desktop ffx.desktop 'Firefox';                   fake_owner "$SB/apps/ffx.desktop" firefox
make_desktop flat.desktop 'Flat App'
make_desktop core.desktop 'Core Tool';                fake_owner "$SB/apps/core.desktop" coretool; fake_priority coretool required
make_desktop ess.desktop 'Essential Tool';            fake_owner "$SB/apps/ess.desktop" esstool;  fake_essential esstool
printf '[Desktop Entry]\nType=Link\nName=A link\n' > "$SB/apps/link.desktop"
sandbox_chown
app_run $'\n3\n\n2\nc\ny\n\n0\n'; P="$(plain)"
assert_contains 'advanced lists an unlisted app with its package' "$P" 'Inkscape [inkscape]'
assert_contains 'advanced lists the second app' "$P" 'VLC media player [vlc]'
assert_not_contains 'advanced skips system components by pattern' "$P" 'Settings'
assert_not_contains 'advanced skips NoDisplay launchers' "$P" 'Hidden tool'
assert_not_contains 'advanced skips catalog apps (Option 2 covers them)' "$P" '[firefox]'
assert_not_contains 'advanced skips priority required' "$P" 'Core Tool'
assert_not_contains 'advanced skips Essential packages' "$P" 'Essential Tool'
assert_not_contains 'advanced skips non-application launchers' "$P" 'A link'
assert_contains 'launchers without an apt package are reported' "$P" '1 additional launcher cannot be uninstalled from here'
assert_contains 'advanced purges only the selection' "$(apt_log)" 'apt-get purge -y vlc'
check_eq 'advanced makes exactly one real removal' 1 "$(real_removals)"
app_run $'\n3\n\nc\n\n0\n'
assert_contains 'advanced with no selection says so' "$OUT" 'No applications were selected.'
app_run $'\nl\n3\n\n0\n0\n' LANG=en_US.UTF-8
assert_contains 'advanced shows the Spanish launcher name' "$(plain)" 'Inkscape Editor vectorial [inkscape]'
new_sandbox
make_desktop settings.desktop 'Settings'; fake_owner "$SB/apps/settings.desktop" cinnamon-control-center
sandbox_chown
app_run $'\n3\n\n0\n'
assert_contains 'advanced with only system launchers says nothing extra was found' "$OUT" 'No additional applications were detected'

echo "-- yes/no answers in text mode (F3.3)"
new_sandbox
# yn LABEL EXPECTED ANSWER [ENV=VAL ...]: status of ask_yes_no for a typed answer.
yn() {
    local label="$1" expected="$2" answer="$3" value
    shift 3
    app_eval 'ask_yes_no "" "" <<< "$TEST_ANSWER"; printf "<<%s>>" "$?"' TEST_ANSWER="$answer" "$@"
    value="${OUT##*<<}"
    check_eq "$label" "$expected" "${value%%>>*}"
}
for lang in en es; do
    for a in y Y yes YES Yes ' yes ' '  Y' s S si SI Si sí Sí SÍ ' sí '; do
        yn "[$lang] \"$a\" confirms" 0 "$a" MINTAPP_LANG="$lang"
    done
    for a in '' ' ' n N no NO nope yess 'yes please' ok 1 0 ye sii -y 'y n' 'sí por favor' 'yes;rm'; do
        yn "[$lang] \"$a\" does not confirm" 1 "$a" MINTAPP_LANG="$lang"
    done
done
yn 'a tab around the answer is ignored' 0 $'\tyes\t' MINTAPP_LANG=en
yn 'SÍ confirms in a locale without UTF-8 case rules' 0 'SÍ' MINTAPP_LANG=es LANG=C
app_eval 'ask_yes_no "" "" < /dev/null; printf "<<%s>>" "$?"' MINTAPP_LANG=en
check_eq 'end of input is a no' '<<1>>' "$OUT"
app_eval 'ask_yes_no "" "" <<< "yess"; true' MINTAPP_LANG=en
assert_contains 'English: an unrecognized answer is reported' "$OUT" 'Answer not recognized.'
app_eval 'ask_yes_no "" "" <<< "yess"; true' MINTAPP_LANG=es
assert_contains 'Spanish: an unrecognized answer is reported' "$OUT" 'Respuesta no reconocida.'
app_eval 'ask_yes_no "" "" <<< "no"; true' MINTAPP_LANG=en
assert_not_contains 'a plain "no" is not reported as unrecognized' "$OUT" 'not recognized'
app_eval 'ask_yes_no "" "" <<< ""; true' MINTAPP_LANG=en
assert_not_contains 'Enter alone is a quiet "no"' "$OUT" 'not recognized'
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\nsi\n\n0\n'
check_eq 'English interface: "si" confirms the removal' 1 "$(real_removals)"
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\n YES \n\n0\n' MINTAPP_LANG=es
check_eq 'Spanish interface: " YES " confirms the removal' 1 "$(real_removals)"
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\nyess\n\n0\n'
check_eq 'a misspelt confirmation removes nothing' 0 "$(real_removals)"
check_eq 'a misspelt confirmation asks sudo for nothing' 0 "$(sudo_log | wc -l)"
assert_contains 'a misspelt confirmation is reported' "$OUT" 'Answer not recognized.'
assert_contains 'a misspelt confirmation cancels the operation' "$OUT" 'Operation cancelled.'

echo "-- option 3: owner lookup in batches"
new_sandbox
for i in $(seq 1 30); do make_desktop "app$i.desktop" "App number $i"; fake_owner "$SB/apps/app$i.desktop" "pkg-$i"; fake_installed "pkg-$i"; done
make_desktop 'my app (1).desktop' 'Spaced name'; fake_owner "$SB/apps/my app (1).desktop" spaced-pkg; fake_installed spaced-pkg
make_desktop 'café.desktop' 'Café app';           fake_owner "$SB/apps/café.desktop" cafe-pkg;     fake_installed cafe-pkg
make_desktop 'unowned.desktop' 'Unowned app'
sandbox_chown
app_run $'\n3\n\nc\n\n0\n'; P="$(plain)"
check_eq 'one dpkg call serves every launcher' 1 "$(dpkg_calls)"
assert_contains 'batched lookup: first launcher' "$P" 'App number 1 [pkg-1]'
assert_contains 'batched lookup: last launcher' "$P" 'App number 30 [pkg-30]'
assert_contains 'batched lookup: a name with spaces and parentheses' "$P" 'Spaced name [spaced-pkg]'
assert_contains 'batched lookup: a name with accents' "$P" 'Café app [cafe-pkg]'
assert_contains 'batched lookup: unowned launchers are still counted' "$P" '1 additional launcher cannot be uninstalled from here'
new_sandbox
for i in $(seq 1 250); do make_desktop "bulk$i.desktop" "Bulk $i"; fake_owner "$SB/apps/bulk$i.desktop" "bulk-$i"; done
sandbox_chown
app_run $'\n3\n\nc\n\n0\n'
check_eq '250 launchers need two dpkg calls (chunks of 200)' 2 "$(dpkg_calls)"
assert_contains 'every launcher of every chunk is listed' "$(plain)" 'Bulk 250 [bulk-250]'
if command -v dpkg >/dev/null 2>&1; then
    new_sandbox
    app_eval 'load_launcher_owners /usr/bin/dpkg /nonexistent/none.desktop; printf "<<%s|%s>>" "${LAUNCHER_OWNERS[/usr/bin/dpkg]:-}" "${LAUNCHER_OWNERS[/nonexistent/none.desktop]:-none}"' PATH=/usr/bin:/bin
    assert_contains 'the batch parser understands the output of the real dpkg' "$OUT" '<<dpkg|none>>'
else
    skip_case 'the batch parser understands the output of the real dpkg (dpkg not available)'
fi

echo "-- option 4: clean up"
new_sandbox; fake_autoremovable libold1 libold2
app_run $'\n4\n1\ny\n\n0\n'; P="$(plain)"
check_eq 'clean exits 0' 0 "$RC"
assert_contains 'clean shows the real autoremove plan' "$P" 'Remv libold1'
assert_contains 'clean runs autoremove' "$(apt_log)" 'apt-get autoremove -y'
assert_contains 'clean runs autoclean' "$(apt_log)" 'apt-get autoclean -y'
assert_contains 'clean reports the dependencies' "$P" 'Dependencies removed.'
assert_contains 'clean reports the cache' "$P" 'Package cache cleaned.'
new_sandbox; fake_autoremovable libold1
app_run $'\n4\n1\nn\n\n0\n'
check_eq 'declining the cleanup plan removes nothing' 0 "$(real_removals)"
app_run $'\n4\n1\ny\n\n0\n' FAKE_APT_DRIFT=1
check_eq 'a cleanup plan that changed runs nothing' 0 "$(real_removals)"
new_sandbox
app_run $'\n4\n1\n\n0\n'
assert_contains 'no orphans: explained' "$OUT" 'No unused dependencies were found; nothing to remove.'
check_eq 'no orphans: nothing removed' 0 "$(apt_log | grep -c 'autoremove -y' || true)"

new_sandbox; fake_autoremovable libold1
app_run $'\n4\n1\ny\n\n0\n' FAKE_APT_FAIL=100 FAKE_APT_FAIL_ACTION=autoclean
assert_contains 'clean: a failed autoclean is reported with its exit code' "$OUT" 'The package cache could not be cleaned (exit code 100).'
assert_not_contains 'clean: a failed autoclean never claims the cache was cleaned' "$OUT" 'Package cache cleaned.'
new_sandbox; fake_installed firefox; fake_autoremovable firefox
app_run $'\n2\n0\n4\n1\ny\n\n2\n\n\n0\n'
assert_contains 'clean: the next uninstall screen sees what the cleanup removed' "$(plain)" 'No installed applications from the curated catalog were detected.'

echo "-- language switch from the menu"
new_sandbox
app_run $'\n0\n'
assert_contains 'text menu in English: the language line names Spanish' "$(plain)" 'L. Español'
app_run $'\nl\n0\n'
assert_contains 'the menu switches to Spanish' "$OUT" 'Desinstalar aplicaciones'
assert_contains 'text menu in Spanish: the language line names English' "$(plain)" 'L. English'
app_run $'\nl\nl\n0\n' LANG=es_ES.UTF-8
assert_contains 'switching twice comes back' "$OUT" 'Uninstall applications'

echo "-- language switch on the first screen and mid-session (F3.5)"
new_sandbox
app_run $'l\n\n0\n'
assert_contains 'text: "l" on the help screen shows the help in Spanish' "$OUT" 'CÓMO MOVERSE POR LOS MENÚS'
assert_contains 'text: the menu after that switch is in Spanish' "$OUT" 'Desinstalar aplicaciones'
app_run $'L\nl\n\n0\n'
check_eq 'text: the help screen is drawn three times (English, Spanish, English)' 3 "$(printf '%s\n' "$OUT" | grep -cE 'HOW TO NAVIGATE|CÓMO MOVERSE')"
assert_contains 'text: switching twice on the help screen ends in English' "$OUT" 'Uninstall applications'
app_run $'x\n0\n'
assert_not_contains 'text: any other key on the help screen only continues' "$OUT" 'CÓMO MOVERSE'
if command -v script >/dev/null 2>&1; then
    new_sandbox
    app_run_pty $'\n0\n' MINTAPP_UI=text
    assert_contains 'text: the help screen offers the switch (English)' "$OUT" 'Press Enter to continue or type L to switch to Español:'
    app_run_pty $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=es
    assert_contains 'text: the help screen offers the switch (Spanish)' "$OUT" 'Pulsa Enter para continuar o escribe L para cambiar a English:'
else
    skip_case 'text: the help screen prompt on a pseudo-terminal (util-linux script is not available)'
fi
new_sandbox
fake_answers NO OK 'TAG:0'
app_run '' MINTAPP_UI=whiptail
WT_LOG="$(cat "$SB/state/whiptail.log")"
check_eq 'whiptail: the switch on the help screen exits cleanly' 0 "$RC"
assert_contains 'whiptail: the help screen has a button for the other language' "$WT_LOG" '--no-button Español'
assert_contains 'whiptail: that button shows the help again in Spanish' "$WT_LOG" 'Moverse por la lista de opciones.'
assert_contains 'whiptail: the help button then offers English' "$WT_LOG" '--no-button English'
assert_contains 'whiptail: the main menu that follows is in Spanish' "$WT_LOG" 'Desinstalar aplicaciones'
new_sandbox
fake_answers ESC 'TAG:0'
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail: Esc on the help screen just continues' 0 "$RC"
assert_not_contains 'whiptail: Esc on the help screen does not switch language' "$(cat "$SB/state/whiptail.log")" 'Moverse por la lista'
new_sandbox; fake_installed firefox thunderbird
app_run $'\n1\n\nl\n2\n1\nc\ny\n\n0\n'; P="$(plain)"
assert_not_contains 'mid-session switch: the detection is kept (no second detection screen)' "$P" 'Aplicaciones detectadas'
assert_contains 'mid-session switch: detected apps are re-translated in the list' "$P" 'Cliente de correo electrónico'
check_eq 'mid-session switch: the selection removes exactly the chosen package' 1 "$(real_removals)"
assert_contains 'mid-session switch: the right package is purged' "$(apt_log)" 'apt-get purge -y firefox'
assert_contains 'mid-session switch: the result is in the new language' "$P" 'Desinstalación completada.'

echo "-- whiptail path (stub whiptail)"
new_sandbox; fake_installed firefox
fake_answers OK 'TAG:0'
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail: menu exits with 0' 0 "$RC"
assert_contains 'whiptail in English: the language button names Spanish' "$(cat "$SB/state/whiptail.log")" 'L Español'
new_sandbox; fake_installed firefox
fake_answers OK TAG:2 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail: full uninstall flow exits 0' 0 "$RC"
assert_contains 'whiptail: purge runs for the checked item' "$(apt_log)" 'apt-get purge -y firefox'
assert_contains 'whiptail: the plan goes through a dialog' "$(cat "$SB/state/whiptail.log")" 'Purg firefox'
assert_contains 'whiptail: the question to uninstall starts on Cancel (--defaultno)' \
    "$(grep -F -- '--yes-button Uninstall' "$SB/state/whiptail.log" | head -n1 || true)" '--defaultno'
new_sandbox; fake_installed firefox
fake_answers OK TAG:2 'TAG:"1"' OK NO TAG:0
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail: declining removes nothing' 0 "$(real_removals)"
new_sandbox; fake_installed firefox
fake_answers OK TAG:2 CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail: cancelling the checklist removes nothing' 0 "$(real_removals)"
new_sandbox; fake_installed firefox
fake_answers OK TAG:L TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: the language button switches the dialogs to Spanish' "$(cat "$SB/state/whiptail.log")" 'Desinstalar aplicaciones'
assert_contains 'whiptail in Spanish: the language button names English' "$(cat "$SB/state/whiptail.log")" 'L English'
new_sandbox
fake_answers OK ESC
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail: Esc/Cancel at the menu exits 0' 0 "$RC"
new_sandbox; fake_autoremovable libold1
fake_answers OK TAG:4 TAG:1 OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: the cleanup runs autoremove and autoclean' "$(apt_log)" 'apt-get autoclean -y'
assert_contains 'whiptail: the cleanup result dialog reports the cache' "$(cat "$SB/state/whiptail.log")" 'Package cache cleaned.'
assert_contains 'whiptail: the question to clean up starts on Cancel (--defaultno)' \
    "$(grep -F -- '--yes-button Uninstall' "$SB/state/whiptail.log" | head -n1 || true)" '--defaultno'
# A launcher whose name starts with "-" must not be read by whiptail as an option (E21).
new_sandbox; fake_installed weirdpkg
make_desktop weird.desktop '-weird app'; fake_owner "$SB/apps/weird.desktop" weirdpkg
fake_answers OK TAG:3 OK 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: a launcher named "-weird app" is listed' "$(cat "$SB/state/whiptail.log")" '-weird app'
assert_contains 'whiptail: a launcher named "-weird app" can be purged' "$(apt_log)" 'apt-get purge -y weirdpkg'
# >>> FP2.1-dimensions
echo "-- interface scaling (FP.2): box sizes follow the terminal"
new_sandbox
# mkterm: a "tput" that reports the size in FAKE_LINES x FAKE_COLS (and 256 colors), so a test can resize the
# "terminal" between two screens.
mkdir -p "$SB/term" "$SB/term-blind"
printf '#!/bin/sh\ncase "$1" in lines) echo "${FAKE_LINES:-24}" ;; cols) echo "${FAKE_COLS:-80}" ;; colors) echo 256 ;; *) exit 1 ;; esac\n' > "$SB/term/tput"
printf '#!/bin/sh\nexit 1\n' > "$SB/term-blind/tput"
chmod +x "$SB/term/tput" "$SB/term-blind/tput"; sandbox_chown
TERM_PATH="$SB/term:$SB/bin:/usr/local/bin:/usr/bin:/bin"
BLIND_PATH="$SB/term-blind:$SB/bin:/usr/local/bin:/usr/bin:/bin"
# dims LABEL EXPECTED LINES COLS [PATH]: "H W BIG_H BIG_W" after calc_whiptail_dimensions.
dims() {
    local label="$1" expected="$2" l="$3" c="$4" path="${5:-$TERM_PATH}"
    app_eval 'calc_whiptail_dimensions; printf "<<%s %s %s %s>>" "$WT_HEIGHT" "$WT_WIDTH" "$WT_HEIGHT_BIG" "$WT_WIDTH_BIG"' \
        PATH="$path" FAKE_LINES="$l" FAKE_COLS="$c"
    value="${OUT#*<<}"
    check_eq "$label" "$expected" "${value%%>>*}"
}
dims '80x24 keeps the classic boxes (20x73 and 22x76)'        '20 73 22 76' 24 80
dims '120x40: the boxes grow with the window'                  '34 110 36 115' 40 120
dims '200x60: the width stops at its maximum, the height keeps growing' '51 120 55 140' 60 200
dims '300x100: the maximum width does not move'                '85 120 92 140' 100 300
dims 'no tput at all: falls back to 24x80'                     '20 73 22 76' 24 80 "$BLIND_PATH"
dims 'a tput that fails: falls back to 24x80'                  '20 73 22 76' 24 80 "$BLIND_PATH"
dims 'an implausibly small terminal (5 lines) counts as unknown' '20 73 22 76' 5 80
dims 'an implausibly narrow terminal (20 columns) counts as unknown' '20 73 22 76' 24 20
dims '50x12: the box leaves room for the backtitle and the shadow' '10 46 10 48' 12 50
# Every size must fit: never more than the terminal minus the backtitle row and the shadow, never below the minimums.
app_eval 'bad=0; checked=0
for cols in 40 41 45 50 60 79 80 81 100 119 120 121 140 160 200 250 400; do
    for lines in 10 11 12 14 20 24 25 30 40 50 60 100; do
        FAKE_LINES=$lines FAKE_COLS=$cols calc_whiptail_dimensions; checked=$((checked + 1))
        for h in "$WT_HEIGHT" "$WT_HEIGHT_BIG"; do [ "$h" -le $((lines - 2)) ] || bad=$((bad + 1)); done
        for w in "$WT_WIDTH" "$WT_WIDTH_BIG"; do [ "$w" -le $((cols - 2)) ] || bad=$((bad + 1)); done
        [ "$WT_WIDTH" -le "$WT_MAX_WIDTH" ] && [ "$WT_WIDTH_BIG" -le "$WT_MAX_WIDTH_BIG" ] || bad=$((bad + 1))
        # The minimums (30 and 40 columns) give way only where the terminal itself is narrower than that.
        [ "$WT_WIDTH" -ge $(( cols - 2 < 30 ? cols - 2 : 30 )) ] && [ "$WT_WIDTH_BIG" -ge $(( cols - 2 < 40 ? cols - 2 : 40 )) ] || bad=$((bad + 1))
        [ "$WT_HEIGHT" -ge $(( lines - 2 < 12 ? lines - 2 : 12 )) ] || bad=$((bad + 1))
        [ "$WT_HEIGHT_BIG" -ge "$WT_HEIGHT" ] && [ "$WT_WIDTH_BIG" -ge "$WT_WIDTH" ] || bad=$((bad + 1))
    done
done
printf "<<%s of %s>>" "$bad" "$checked"' PATH="$TERM_PATH"
value="${OUT#*<<}"
check_eq 'from 40x10 to 400x100 no box is larger than the terminal or below its minimum (204 sizes checked)' "0 of 204" "${value%%>>*}"
# Resizing between two screens: the next box is calculated again.
app_eval 'FAKE_LINES=24 FAKE_COLS=80 calc_whiptail_dimensions; a="$WT_HEIGHT x $WT_WIDTH"
FAKE_LINES=40 FAKE_COLS=120 calc_whiptail_dimensions; b="$WT_HEIGHT x $WT_WIDTH"
FAKE_LINES=24 FAKE_COLS=80 calc_whiptail_dimensions; c="$WT_HEIGHT x $WT_WIDTH"
printf "<<%s|%s|%s>>" "$a" "$b" "$c"' PATH="$TERM_PATH"
value="${OUT#*<<}"
check_eq 'a resized window gives a new size on the next screen, and back again' '20 x 73|34 x 110|20 x 73' "${value%%>>*}"
# <<< FP2.1-dimensions

# >>> FP2.2-backtitle-palette
echo "-- dialog backtitle and palette (FP.2)"
# The first screen row of every dialog names the program and its version; the title of the box stays the name.
app_eval 'printf "%s|%s" "$(app_backtitle)" "$MINTAPP_VERSION"'
bt_value="${OUT%%|*}"; bt_version="${OUT#*|}"
check_eq 'the backtitle is the program name and its version' "MintApp Remover $bt_version" "$bt_value"
check_eq 'the version has the form N.N.N' yes "$([[ "$bt_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo "no: $bt_version")"
app_eval 'toggle_language; printf "%s" "$(app_backtitle)"'
check_eq 'the backtitle does not change with the language' "MintApp Remover $bt_version" "$OUT"
app_eval 'printf "%s" "$(app_backtitle)"' MINTAPP_ASCII=1 MINTAPP_LANG=es
check_eq 'the backtitle is plain ASCII in ASCII mode' 0 "$(nonascii "$OUT")"
# wt() picks the engine in a case: its whiptail call is the arm "*) whiptail ...".
check_eq 'every dialog goes through wt(): the only direct whiptail call is the one inside it' 1 \
    "$(code_only | grep -cE '^[[:space:]]*(\*\)[[:space:]]*)?whiptail[[:space:]]' || true)"
new_sandbox; fake_installed firefox
fake_answers OK 'TAG:0'
app_run '' MINTAPP_UI=whiptail
check_eq 'the first dialog of a session carries the backtitle' yes \
    "$([[ "$(head -n1 "$SB/state/whiptail.log")" == *"--backtitle MintApp Remover $bt_version"* ]] && echo yes || echo no)"
assert_contains 'the box title is still the program name alone' "$(cat "$SB/state/whiptail.log")" '--title MintApp Remover --backtitle'

# Palette: readable foregrounds (bright), backgrounds from the 8 basic colors, only names that newt knows.
mkdir -p "$SB/term"
printf '#!/bin/sh\ncase "$1" in lines) echo 24 ;; cols) echo 80 ;; colors) echo 256 ;; *) exit 1 ;; esac\n' > "$SB/term/tput"; chmod +x "$SB/term/tput"
app_eval 'printf "%s" "$NEWT_COLORS"' PATH="$SB/term:$SB/bin:/usr/local/bin:/usr/bin:/bin" TERM=xterm
PALETTE="$OUT"
palette_count() { printf '%s\n' "$PALETTE" | awk -F'[=,]' -v re="$1" 'NF == 3 && ($1 ":" $2 ":" $3) ~ re { n++ } END { print n + 0 }'; }
KNOWN='^(black|red|green|brown|blue|magenta|cyan|lightgray|gray|brightred|brightgreen|brightbrown|brightblue|brightmagenta|brightcyan|white)$'
check_eq 'the palette has its entries (so the checks below look at something)' yes "$([ "$(palette_count '.')" -ge 20 ] && echo yes || echo no)"
check_eq 'every color in the palette is a name that newt knows' 0 \
    "$(printf '%s\n' "$PALETTE" | awk -F'[=,]' -v re="$KNOWN" 'NF == 3 { for (i = 2; i <= 3; i++) if ($i != "" && $i !~ re) n++ } END { print n + 0 }')"
check_eq 'no background is a bright color (a terminal draws only the 8 basic ones)' 0 "$(palette_count ':bright[a-z]+$')"
check_eq 'normal text, buttons and inactive entries share one bright green on black' 10 "$(palette_count '^(root|window|label|listbox|textbox|checkbox|entry|button|compactbutton|sellistbox):brightgreen:black$')"
check_eq 'nothing that can be chosen is blue: no button or entry uses a blue foreground' 0 "$(palette_count '^(button|compactbutton|actbutton|checkbox|actcheckbox|entry|listbox|actlistbox|sellistbox|actsellistbox):(bright)?blue:')"
check_eq 'borders, titles, backtitle and help line are bright blue on black' 4 "$(palette_count '^(border|title|roottext|helpline):brightblue:black$')"
check_eq 'the active element is a solid green block (black on green)' 5 "$(palette_count '^(actbutton|actcheckbox|actlistbox|actsellistbox|acttextbox):black:green$')"
check_eq 'plain blue text on black appears only for disabled entries' 1 "$(palette_count ':blue:black$')"
# <<< FP2.2-backtitle-palette

# >>> FP2.3-text-width
echo "-- plain-text screens follow the terminal width (FP.2)"
new_sandbox
# A "tput" that reports FAKE_COLS columns (default 80) and 256 colors.
mkdir -p "$SB/term"
printf '#!/bin/sh\ncase "$1" in lines) echo "${FAKE_LINES:-24}" ;; cols) echo "${FAKE_COLS:-80}" ;; colors) echo 256 ;; *) exit 1 ;; esac\n' > "$SB/term/tput"
chmod +x "$SB/term/tput"; sandbox_chown
TX_PATH="$SB/term:$SB/bin:/usr/local/bin:/usr/bin:/bin"
# fits_at N: "ok" if no line of stdin is wider than N columns, else "W columns" (visible in the failure).
fits_at() { local w; w="$(widest)"; if [ "$w" -le "$1" ]; then echo ok; else echo "$w columns"; fi; }
# tx_header LABEL EXPECTED COLS [TITLE]: width of the widest line header() draws at that terminal width.
tx_header() {
    local label="$1" expected="$2" cols="$3"
    app_eval "clear() { :; }; header ${4:+\"$4\"}" PATH="$TX_PATH" FAKE_COLS="$cols" NO_COLOR=1 MINTAPP_ASCII=0
    check_eq "$label" "$expected" "$(printf '%s\n' "$OUT" | widest)"
}
tx_header 'header: 80 columns -> rules of 79' 79 80
tx_header 'header: 40 columns -> rules of 39' 39 40
tx_header 'header: 120 columns -> capped at 100' 100 120
tx_header 'header: 300 columns -> capped at 100' 100 300
tx_header 'header: a title longer than the screen is cut to the rule width' 59 60 "$(printf 'x%.0s' $(seq 1 150))"
app_eval 'clear() { :; }; header' PATH="$TX_PATH" NO_COLOR=1 MINTAPP_ASCII=0
check_eq 'header: rule, title, rule (the blank line after them is trimmed by $(...))' 3 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check_eq 'header: the title opens the line between the rules' ' MintApp Remover' "$(printf '%s\n' "$OUT" | sed -n 2p | cut -c1-16)"
hdr_line="$(printf '%s\n' "$OUT" | sed -n 2p)"
check_eq 'header: the version ends the title line, one column short of the rule' "v$bt_version 78" "${hdr_line##* } ${#hdr_line}"
# hdr_title N: line of the title that header() draws for a title of N characters (80 columns: room for N <= 75 - version).
hdr_title() { app_eval "clear() { :; }; header \"$(printf 'x%.0s' $(seq 1 "$1"))\"" PATH="$TX_PATH" NO_COLOR=1 MINTAPP_ASCII=0; printf '%s\n' "$OUT" | sed -n 2p; }
hv_len=$(( ${#bt_version} + 1 ))
hdr_line="$(hdr_title $(( 75 - hv_len )))"
check_eq 'header: a title that leaves two spaces keeps the version' "v$bt_version" "${hdr_line##* }"
hdr_line="$(hdr_title $(( 76 - hv_len )))"
check_eq 'header: a title that leaves one space drops the version' $(( 77 - hv_len )) "${#hdr_line}"
app_eval 'clear() { :; }; header' PATH="$TX_PATH" NO_COLOR=1 MINTAPP_ASCII=0
assert_contains 'header: Unicode rules are made of the heavy glyph' "$OUT" '═══════'
app_eval 'clear() { :; }; header' PATH="$TX_PATH" NO_COLOR=1 MINTAPP_ASCII=1
check_eq 'header: in ASCII mode there is nothing outside ASCII' 0 "$(nonascii "$OUT")"
assert_contains 'header: ASCII rules are made of =' "$OUT" '======='
app_eval 'section_rule' PATH="$TX_PATH" FAKE_COLS=50 NO_COLOR=1 MINTAPP_ASCII=0
check_eq 'section_rule: 49 light glyphs at 50 columns' "$(printf '─%.0s' $(seq 1 49))" "$OUT"
app_eval 'section_rule' PATH="$TX_PATH" FAKE_COLS=50 NO_COLOR=1 MINTAPP_ASCII=1
check_eq 'section_rule: dashes in ASCII mode' "$(printf -- '-%.0s' $(seq 1 49))" "$OUT"

# text_wrap / text_print / text_say / text_entry
app_eval 'text_wrap "$(printf "word%.0s " $(seq 1 60))"' PATH="$TX_PATH" FAKE_COLS=50 NO_COLOR=1
check_eq 'text_wrap: no line is wider than the screen (49 at 50 columns)' ok "$(printf '%s\n' "$OUT" | fits_at 49)"
check_eq 'text_wrap: no word is lost' 60 "$(printf '%s' "$OUT" | wc -w | tr -d ' ')"
app_eval 'text_wrap "        $(printf "word%.0s " $(seq 1 30))"' PATH="$TX_PATH" FAKE_COLS=40 NO_COLOR=1
check_eq 'text_wrap: every continuation keeps the indentation' 0 "$(printf '%s\n' "$OUT" | grep -vc '^        [^ ]' || true)"
check_eq 'text_wrap: the indented text fits too (39 at 40 columns)' ok "$(printf '%s\n' "$OUT" | fits_at 39)"
app_eval 'text_print "one\ntwo"' PATH="$TX_PATH" NO_COLOR=1
check_eq 'text_print: \n sequences become line breaks' "one|two" "$(printf '%s' "$OUT" | tr '\n' '|')"
app_eval 'text_wrap "one\ntwo"' PATH="$TX_PATH" NO_COLOR=1
check_eq 'text_wrap: the text is printed as it is (no \n expansion)' 'one\ntwo' "$OUT"
app_eval 'text_say "$C_OK" "$(printf "word%.0s " $(seq 1 40))"' PATH="$TX_PATH" FAKE_COLS=40 TERM=xterm
tx_lines="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
check_eq 'text_say: the text is wrapped (more than one line)' yes "$([ "$tx_lines" -gt 1 ] && echo yes || echo no)"
check_eq 'text_say: every wrapped line is closed with a reset' "$tx_lines" "$(printf '%s\n' "$OUT" | grep -c $'\033\\[0m' || true)"
check_eq 'text_say: every wrapped line starts with the color' "$tx_lines" "$(printf '%s\n' "$OUT" | grep -c $'^\033\\[1;32m' || true)"
app_eval 'text_entry " 3" "$SYM_OFF" "A name that is long enough to need a second line" "[some-package]" 0' PATH="$TX_PATH" FAKE_COLS=40 NO_COLOR=1 MINTAPP_ASCII=0
check_eq 'text_entry: an entry fits the screen (39 at 40 columns)' ok "$(printf '%s\n' "$OUT" | fits_at 39)"
tx_first="$(printf '%s\n' "$OUT" | sed -n 1p)"
check_eq 'text_entry: the number and the check mark open the first line' yes "$([[ "$tx_first" == '   3) ☐ A name'* ]] && echo yes || echo "no: $tx_first")"
check_eq 'text_entry: the continuation is indented under the name' 0 "$(printf '%s\n' "$OUT" | tail -n +2 | grep -vc '^        [^ ]' || true)"
assert_contains 'text_entry: the package label is kept' "$OUT" '[some-package]'
app_eval 'text_entry " 3" "$SYM_ON" "Name" "[pkg]" 1' PATH="$TX_PATH" TERM=xterm
check_eq 'text_entry: a marked entry is a solid block that closes with a reset' 1 "$(printf '%s\n' "$OUT" | grep -c $'\033\\[1;30;42m ☑ Name \\[pkg\\] \033\\[0m$' || true)"
app_eval 'text_entry " 3" "$SYM_OFF" "Name" "[pkg]" 0' PATH="$TX_PATH" TERM=xterm
check_eq 'text_entry: an unmarked entry shows its package in the title color' 1 "$(printf '%s\n' "$OUT" | grep -c $'\033\\[1;34m\\[pkg\\]\033\\[0m$' || true)"

# The whole program: every screen of the plain-text menu at a narrow terminal and at a wide one.
fake_installed firefox thunderbird libreoffice vlc
make_desktop long.desktop 'An application with a really quite long name'
fake_owner "$SB/apps/long.desktop" a-rather-long-package-name; fake_installed a-rather-long-package-name
for tx_cols in 40 60 100 200; do
    for tx_lang in en es; do
        # Help, detect (+pause), uninstall list (mark 1, back), advanced (+pause; mark 1, back), cleanup (the action menu,
        # the level menu and the list of what the level cleans, +pause), exit.
        app_run $'\n1\n\n2\n1\n0\n3\n\n1\n0\n4\n2\nC\n\n0\n' MINTAPP_UI=text MINTAPP_ASCII=0 NO_COLOR=1 MINTAPP_LANG=$tx_lang PATH="$TX_PATH" FAKE_COLS=$tx_cols
        tx_limit=$(( tx_cols - 1 )); [ "$tx_limit" -le 100 ] || tx_limit=100
        check_eq "the whole text menu fits $tx_cols columns ($tx_lang): no line wider than $tx_limit" ok "$(plain | fits_at "$tx_limit")"
        check_eq "the whole text menu reaches the exit ($tx_lang, $tx_cols columns)" 0 "$RC"
    done
done
app_run $'\n2\n1\n\n0\n0\n' MINTAPP_UI=text MINTAPP_ASCII=0 NO_COLOR=1 PATH="$TX_PATH" FAKE_COLS=40
assert_contains 'the marked entry keeps its check mark in the list' "$(plain)" '☑ Firefox'
assert_contains 'the unmarked entry keeps its empty box' "$(plain)" '☐ Thunderbird'
app_run $'\n3\n\n1\n\n0\n0\n' MINTAPP_UI=text MINTAPP_ASCII=0 NO_COLOR=1 PATH="$TX_PATH" FAKE_COLS=40
assert_contains 'advanced: a long name is shown marked, wrapped, with its package' "$(plain | tr '\n' ' ' | tr -s ' ')" '☑ An application with a really quite long name [a-rather-long-package-name]'
app_run $'\n3\n\n1\n0\n0\n' MINTAPP_UI=text MINTAPP_ASCII=1 NO_COLOR=1 PATH="$TX_PATH" FAKE_COLS=40
check_eq 'ASCII mode: the whole advanced screen has nothing outside ASCII' 0 "$(nonascii "$OUT")"
# The font size belongs to the terminal: the help screen tells how to enlarge it (FP.2b).
app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=en
assert_contains 'text help: the zoom tip is shown (English)' "$OUT" 'Ctrl and + enlarges the font'
app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=es
assert_contains 'text help: the zoom tip is shown (Spanish)' "$OUT" 'Ctrl y + aumenta la letra'
app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=es MINTAPP_ASCII=1
check_eq 'text help: the zoom tip adds nothing outside ASCII in ASCII mode' 0 "$(nonascii "$OUT")"
new_sandbox
fake_answers OK 'TAG:0'
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail help: the zoom tip is part of the first dialog' "$(cat "$SB/state/whiptail.log")" 'Text too small? Ctrl and + enlarges the font'
# <<< FP2.3-text-width

echo "-- keyboard help texts: no TAB required (FU.2)"
# help_text LANG KEY: OUT is the message in that language, in Unicode mode, with its \n as line breaks.
help_text() { bare_eval "APP_LANG=$1; printf '%s' \"\$(msg $2)\"" PATH=/usr/bin:/bin MINTAPP_ASCII=0; OUT="${OUT//\\n/$'\n'}"; }
for tx_lang in en es; do
    for tx_key in select_help advanced_select menu_whiptail; do
        help_text "$tx_lang" "$tx_key"
        assert_not_contains "$tx_key ($tx_lang): TAB is not asked for" "$OUT" 'TAB'
        assert_contains "$tx_key ($tx_lang): Enter confirms" "$OUT" 'Enter'
    done
    help_text "$tx_lang" nav_tui
    assert_contains "nav_tui ($tx_lang): A / N" "$OUT" 'A / N'
done
help_text en nav_tui
assert_contains 'nav_tui (en): Home / End' "$OUT" 'Home / End'
assert_contains 'nav_tui (en): PgUp / PgDn' "$OUT" 'PgUp / PgDn'
check_eq 'nav_tui (en): TAB is described as optional' 1 "$(printf '%s\n' "$OUT" | grep 'TAB' | grep -c 'Optional' || true)"
assert_contains 'nav_tui (en): Space also chooses in a menu' "$OUT" 'in a menu, choose'
help_text es nav_tui
assert_contains 'nav_tui (es): Inicio / Fin' "$OUT" 'Inicio / Fin'
assert_contains 'nav_tui (es): RePág / AvPág' "$OUT" 'RePág / AvPág'
check_eq 'nav_tui (es): TAB is described as optional' 1 "$(printf '%s\n' "$OUT" | grep 'TAB' | grep -c 'Opcional' || true)"
assert_contains 'nav_tui (es): Space also chooses in a menu' "$OUT" 'en un menú, elegir'

echo "-- key help of the tui engine: Q and the main-menu keys (FU.3)"
# nav_keys LANG ASCII [CODE]: OUT is the key help as the program builds it, with the \n turned into line breaks.
nav_keys() { app_eval "${3:-}"'nav_tui_text; printf "%s" "$REPLY"' MINTAPP_LANG="$1" MINTAPP_ASCII="$2"; }
GUI_HOOK='gui_available() { return 0; }; '
# col_of TEXT: the column where TEXT starts on its line of OUT (the description column of the help).
col_of() { printf '%s\n' "$OUT" | LC_ALL=C awk -v t="$1" 'index($0, t) { print index($0, t); exit }'; }
nav_keys en 0
check_eq 'key help (en): the main-menu line lists 1 2 3 4 L 0 while there is no graphical menu' '  1 2 3 4 L 0    Main menu: each key opens its option.' "$(printf '%s\n' "$OUT" | grep 'Main menu')"
assert_not_contains 'key help (en): no format left over' "$OUT" '%s'
assert_contains 'key help (en): Q is Esc' "$OUT" 'ESC or Q       Go back or cancel (not Q while typing).'
check_eq 'key help (en): the main-menu line starts its text in the column of the others' "$(col_of 'Go back')" "$(col_of 'Main menu')"
nav_keys en 0 "$GUI_HOOK"
check_eq 'key help (en): with a graphical menu G is listed between 4 and L' '  1 2 3 4 G L 0  Main menu: each key opens its option.' "$(printf '%s\n' "$OUT" | grep 'Main menu')"
check_eq 'key help (en) with G: the text still starts in the same column' "$(col_of 'Go back')" "$(col_of 'Main menu')"
nav_keys es 0
check_eq 'key help (es): the main-menu line lists 1 2 3 4 L 0 while there is no graphical menu' '  1 2 3 4 L 0    Menú principal: cada tecla abre su opción.' "$(printf '%s\n' "$OUT" | grep 'Menú principal')"
assert_not_contains 'key help (es): no format left over' "$OUT" '%s'
assert_contains 'key help (es): Q is Esc' "$OUT" 'ESC o Q        Volver o cancelar (Q no, si estás escribiendo).'
check_eq 'key help (es): the main-menu line starts its text in the column of the others' "$(col_of 'Volver')" "$(col_of 'Menú principal')"
nav_keys es 0 "$GUI_HOOK"
check_eq 'key help (es): with a graphical menu G is listed between 4 and L' '  1 2 3 4 G L 0  Menú principal: cada tecla abre su opción.' "$(printf '%s\n' "$OUT" | grep 'Menú principal')"
nav_keys es 1 "$GUI_HOOK"
check_eq 'key help (es, ASCII mode): nothing outside ASCII' 0 "$(nonascii "$OUT")"
assert_contains 'key help (es, ASCII mode): the key line is intact' "$OUT" '  1 2 3 4 G L 0  Menu principal: cada tecla abre su opcion.'
nav_keys en 0 'build_main_menu() { MENU_TAGS=(1 2 3 4 5 6 7); }; '
assert_contains 'key help: the keys come from the menu itself (a different menu, a different line)' "$OUT" '  1 2 3 4 5 6 7  Main menu'
app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=en
assert_contains 'text help (en): the number or the letter of an option' "$OUT" 'Type the NUMBER or LETTER of the option'
app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=es
assert_contains 'text help (es): the number or the letter of an option' "$OUT" 'Escribe el NÚMERO o la LETRA de la opción'
help_text en select_help
assert_contains 'select_help (en): it keeps its opening, as the Spanish one does' "$OUT" '(↑ ↓ move |'

echo "-- text mode: option 2 explains typing numbers, not arrow keys"
new_sandbox
fake_installed firefox thunderbird
app_run $'\n2\n0\n0\n' MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1 MINTAPP_ASCII=0
assert_contains 'option 2 (en): says what to type' "$OUT" 'type a number to mark or unmark'
assert_not_contains 'option 2 (en): no arrow-key help in a screen with no arrows' "$OUT" '↑ ↓'
app_run $'\n2\n0\n0\n' MINTAPP_UI=text MINTAPP_LANG=es NO_COLOR=1 MINTAPP_ASCII=0
assert_contains 'option 2 (es): says what to type' "$OUT" 'escribe el número para marcar/desmarcar'
assert_not_contains 'option 2 (es): no arrow-key help in a screen with no arrows' "$OUT" '↑ ↓'
app_run $'\n3\n\n0\n0\n' MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1 MINTAPP_ASCII=0
assert_not_contains 'option 3 (en): still no arrow-key help' "$OUT" '↑ ↓'

echo "-- MINTAPP_ESC_WAIT: seconds to wait after Esc (FU.1)"
esc_wait() {  # esc_wait VALUE: the wait the engine ends up with ("unset" for no variable at all)
    if [ "$1" = unset ]; then bare_eval 'printf "<<%s>>" "$TUI_ESC_WAIT"' PATH=/usr/bin:/bin
    else bare_eval 'printf "<<%s>>" "$TUI_ESC_WAIT"' PATH=/usr/bin:/bin MINTAPP_ESC_WAIT="$1"; fi
    value="${OUT#*<<}"
    printf '%s' "${value%%>>*}"
}
check_eq 'no variable: 0.15 s' 0.15 "$(esc_wait unset)"
check_eq 'an empty variable: 0.15 s' 0.15 "$(esc_wait '')"
check_eq 'a value is taken as it is (0.6)' 0.6 "$(esc_wait 0.6)"
check_eq 'a whole number of seconds is accepted (2)' 2 "$(esc_wait 2)"
check_eq 'three decimals are accepted (0.075)' 0.075 "$(esc_wait 0.075)"
check_eq 'the upper limit, 5 s, is accepted' 5 "$(esc_wait 5)"
check_eq 'the lower limit, 0.05 s, is accepted' 0.05 "$(esc_wait 0.05)"
check_eq 'below the lower limit falls back to 0.15 (0.01)' 0.15 "$(esc_wait 0.01)"
check_eq 'zero falls back to 0.15' 0.15 "$(esc_wait 0)"
check_eq 'above the upper limit falls back to 0.15 (6)' 0.15 "$(esc_wait 6)"
check_eq 'a negative value falls back to 0.15' 0.15 "$(esc_wait -1)"
check_eq 'text falls back to 0.15' 0.15 "$(esc_wait fast)"
check_eq 'a comma is not a decimal point: falls back to 0.15' 0.15 "$(esc_wait 0,5)"
check_eq 'four decimals fall back to 0.15' 0.15 "$(esc_wait 0.1234)"
check_eq 'an injected command is never run, it falls back' 0.15 "$(esc_wait '1; echo x')"

echo "-- main menu: a description per option, by the height of the terminal (FU.3)"
new_sandbox
mkdir -p "$SB/term"
printf '#!/bin/sh\ncase "$1" in lines) echo "${FAKE_LINES:-24}" ;; cols) echo "${FAKE_COLS:-80}" ;; colors) echo 256 ;; *) exit 1 ;; esac\n' > "$SB/term/tput"
printf 'ID=linuxmint\nPRETTY_NAME="Linux Mint 22.3"\n' > "$SB/os-release"
chmod +x "$SB/term/tput"; sandbox_chown
M_PATH="$SB/term:$SB/bin:/usr/local/bin:/usr/bin:/bin"
# menu_at LINES [VAR=val ...]: runs the text menu on a terminal of that height (help screen passed, then 0).
menu_at() { local rows="$1"; shift; app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1 MINTAPP_ASCII=0 PATH="$M_PATH" FAKE_LINES="$rows" MINTAPP_OS_RELEASE="$SB/os-release" "$@"; M_PLAIN="$(plain)"; }
# m_line TEXT: number of the first line of M_PLAIN that is exactly TEXT.
m_line() { printf '%s\n' "$M_PLAIN" | grep -n -m1 -x -F -- "$1" | cut -d: -f1 || true; }
# m_at N: line N of M_PLAIN.
m_at() { printf '%s\n' "$M_PLAIN" | sed -n "${1}p"; }
M_D1='     See which catalog applications are installed.'

# The layout follows the height. With the 6 entries of this menu, each description on one line at 80
# columns: the status line and the blank row under it come from 15 rows, the descriptions from 21 and
# the blank row between entries from 26. Every limit is tried on both sides.
for m_rows in 26 30 40; do
    menu_at "$m_rows"
    m_l1="$(m_line '1. Detect applications')"
    check_eq "text menu, $m_rows rows: the description is under its option" "$M_D1" "$(m_at $((m_l1 + 1)))"
    check_eq "text menu, $m_rows rows: a blank line separates the entries" '' "$(m_at $((m_l1 + 2)))"
    check_eq "text menu, $m_rows rows: the next option follows" '2. Uninstall applications' "$(m_at $((m_l1 + 3)))"
done
for m_rows in 21 23 25; do
    menu_at "$m_rows"
    m_l1="$(m_line '1. Detect applications')"
    check_eq "text menu, $m_rows rows: the description is under its option" "$M_D1" "$(m_at $((m_l1 + 1)))"
    check_eq "text menu, $m_rows rows: no blank line, the next option follows" '2. Uninstall applications' "$(m_at $((m_l1 + 2)))"
done
for m_rows in 10 12 14 15 18 20; do
    menu_at "$m_rows"
    m_l1="$(m_line '1. Detect applications')"
    assert_not_contains "text menu, $m_rows rows: labels only, no description" "$M_PLAIN" 'See which catalog'
    check_eq "text menu, $m_rows rows: the next option follows the label" '2. Uninstall applications' "$(m_at $((m_l1 + 1)))"
done
# rule_lines GLYPH: the numbers of the lines of stdin made only of GLYPH. It is a bash substitution and
# not a grep range on purpose: in the C locale grep reads the bytes of a glyph such as ─ one by one and
# finds no rule at all, which made "the menu fits" pass without measuring anything.
rule_lines() {
    local n=0 line
    while IFS= read -r line; do
        n=$((n + 1))
        [ -z "$line" ] || [ -n "${line//"$1"/}" ] || printf '%s\n' "$n"
    done
}
export -f rule_lines
for rl_locale in C C.UTF-8; do
    check_eq "control: rule_lines finds the rules of multibyte glyphs (locale $rl_locale)" $'2\n5' \
        "$(printf 'x\n═══\n──\n\n═\n' | LC_ALL=$rl_locale bash -c 'rule_lines ═' 2> /dev/null)"
done
check_eq 'control: rule_lines ignores a line that holds the glyph and something else' '' \
    "$(printf '═ x\nx ═\n═ ═\n' | rule_lines '═')"
# Whatever the height (from 13 rows, what labels alone need), everything from the first row of the
# header to the prompt line under the closing rule is on the screen, and at least one row is left over.
# The header is the pair of ═ rules just above the first entry (the help screen has its own before it);
# its first rule is where the menu starts, with or without a status line under it.
for m_rows in 13 14 15 20 21 25 26 40; do
    menu_at "$m_rows"
    m_l1="$(m_line '1. Detect applications')"
    m_first="$(printf '%s\n' "$M_PLAIN" | rule_lines '═' | awk -v l="$m_l1" '$1 < l { a = b; b = $1 } END { print a }')"
    m_rule="$(printf '%s\n' "$M_PLAIN" | rule_lines '─' | tail -n1)"
    if [ -z "$m_first" ] || [ -z "$m_rule" ]; then
        m_fit="rules not found (header: '$m_first', closing: '$m_rule')"
    else
        m_need=$((m_rule + 1 - m_first + 1))
        if [ "$m_need" -lt "$m_rows" ]; then m_fit=ok; else m_fit="$m_need rows"; fi
    fi
    check_eq "text menu, $m_rows rows: the menu and its prompt fit" ok "$m_fit"
done
menu_at 24 MINTAPP_LANG=es
assert_contains 'text menu in Spanish: descriptions too' "$M_PLAIN" '     Ver qué aplicaciones del catálogo hay instaladas.'
assert_contains 'text menu in Spanish: the language option says what it does' "$M_PLAIN" '     Cambiar la interfaz a inglés.'
menu_at 24 MINTAPP_LANG=es MINTAPP_ASCII=1
check_eq 'text menu in ASCII mode: nothing outside ASCII' 0 "$(nonascii "$OUT")"
assert_contains 'text menu in ASCII mode: accents dropped from the descriptions' "$M_PLAIN" 'Ver que aplicaciones del catalogo hay instaladas.'
# Colour: the description is dim; NO_COLOR sends no dim code at all.
app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=en PATH="$M_PATH" FAKE_LINES=24 MINTAPP_ASCII=0
assert_contains 'text menu with colour: the description is dim' "$OUT" $'\033[2mSee which catalog applications are installed.'
menu_at 24
assert_not_contains 'text menu with NO_COLOR: no dim code' "$OUT" $'\033[2m'
# A narrow terminal wraps a description under its label and no line is wider than the screen.
menu_at 40 FAKE_COLS=40
check_eq 'text menu, 40 columns: nothing wider than the screen' ok "$(printf '%s\n' "$M_PLAIN" | { w="$(widest)"; [ "$w" -le 39 ] && echo ok || echo "$w columns"; })"
m_l3="$(m_line '3. Find other applications (advanced)')"
check_eq 'text menu, 40 columns: a long description continues under itself' '     their menu launchers.' "$(m_at $((m_l3 + 2)))"


echo "-- main menu: status line (F7.0)"
new_sandbox
mkdir -p "$SB/term"
printf '#!/bin/sh\ncase "$1" in lines) echo "${FAKE_LINES:-24}" ;; cols) echo "${FAKE_COLS:-80}" ;; colors) echo 256 ;; *) exit 1 ;; esac\n' > "$SB/term/tput"
printf 'ID=linuxmint\nPRETTY_NAME="Linux Mint 22.3"\n' > "$SB/os-release"
chmod +x "$SB/term/tput"; sandbox_chown
S_PATH="$SB/term:$SB/bin:/usr/local/bin:/usr/bin:/bin"
# status_run [VAR=val ...]: the text menu on a 24x80 terminal in colour (help screen passed, then 0). STATUS is
# its status line without the leading space, empty when there is none; OUT keeps the raw screen.
status_run() {
    app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=en PATH="$S_PATH" MINTAPP_OS_RELEASE="$SB/os-release" "$@"
    STATUS="$(plain | grep -a -m1 -E '(detected|detectadas?)$' | sed 's/^ //')" || true
}
# The count follows the packages installed: none, one (singular), two (plural); English, Spanish.
status_run NO_COLOR=1
check_eq 'status line: system, manager and a count of none' 'Linux Mint 22.3 · apt · 0 applications detected' "$STATUS"
status_run NO_COLOR=1 MINTAPP_LANG=es
check_eq 'status line in Spanish: none' 'Linux Mint 22.3 · apt · 0 aplicaciones detectadas' "$STATUS"
fake_installed firefox
status_run NO_COLOR=1
check_eq 'status line: one application is singular' 'Linux Mint 22.3 · apt · 1 application detected' "$STATUS"
status_run NO_COLOR=1 MINTAPP_LANG=es
check_eq 'status line in Spanish: one application is singular' 'Linux Mint 22.3 · apt · 1 aplicación detectada' "$STATUS"
fake_installed thunderbird
status_run NO_COLOR=1
check_eq 'status line: two applications are plural' 'Linux Mint 22.3 · apt · 2 applications detected' "$STATUS"
status_run NO_COLOR=1 MINTAPP_LANG=es
check_eq 'status line in Spanish: two applications are plural' 'Linux Mint 22.3 · apt · 2 aplicaciones detectadas' "$STATUS"
fake_installed pix; fake_configfiles pix
status_run NO_COLOR=1
check_eq 'status line: a package that kept only its configuration is not counted' 'Linux Mint 22.3 · apt · 2 applications detected' "$STATUS"
status_run NO_COLOR=1 MINTAPP_ASCII=1
check_eq 'status line in ASCII: the fields are separated by |' 'Linux Mint 22.3 | apt | 2 applications detected' "$STATUS"
status_run NO_COLOR=1 MINTAPP_OS_RELEASE="$SB/no-such-file"
check_eq 'status line: a system that cannot be read is just "Linux"' 'Linux · apt · 2 applications detected' "$STATUS"
# Colour: the whole line is bold green and closed; NO_COLOR sends no green at all.
status_run
assert_contains 'status line with colour: bold green, closed with a reset' "$OUT" $'\033[1;32mLinux Mint 22.3 · apt · 2 applications detected\033[0m'
status_run NO_COLOR=1
assert_not_contains 'status line with NO_COLOR: no green code' "$OUT" $'\033[1;32m'
# Place: under the header, one blank row, then the entries.
S_PLAIN="$(plain)"
s_at="$(printf '%s\n' "$S_PLAIN" | grep -a -n -m1 'applications detected$' | cut -d: -f1)"
check_eq 'status line: a blank row separates it from the first entry' $'\n1. Detect applications' "$(printf '%s\n' "$S_PLAIN" | sed -n "$((s_at + 1)),$((s_at + 2))p")"
# It is shown only when the entries fit with it: from 15 rows with the 6 entries of this menu (the "menu fits"
# check below measures that the screen holds it).
for s_rows in 15 16 24 40; do
    status_run NO_COLOR=1 FAKE_LINES=$s_rows
    check_eq "status line, $s_rows rows: shown" 'Linux Mint 22.3 · apt · 2 applications detected' "$STATUS"
done
for s_rows in 10 13 14; do
    status_run NO_COLOR=1 FAKE_LINES=$s_rows
    check_eq "status line, $s_rows rows: left out, the entries come first" '' "$STATUS"
done
echo "-- main menu: status line, cut and width by engine (F7.0)"
# term_sandbox: a new sandbox with a tput that reports FAKE_LINES x FAKE_COLS (24x80 by default) and 256 colours;
# T_PATH is the PATH that finds it.
term_sandbox() {
    new_sandbox
    mkdir -p "$SB/term"
    printf '#!/bin/sh\ncase "$1" in lines) echo "${FAKE_LINES:-24}" ;; cols) echo "${FAKE_COLS:-80}" ;; colors) echo 256 ;; *) exit 1 ;; esac\n' > "$SB/term/tput"
    chmod +x "$SB/term/tput"; sandbox_chown
    T_PATH="$SB/term:$SB/bin:/usr/local/bin:/usr/bin:/bin"
}
# have_utf8: a UTF-8 locale is generated here, so a run can count characters and not bytes.
have_utf8() { command -v locale > /dev/null 2>&1 && locale -a 2> /dev/null | grep -qix 'c\.utf-\?8'; }
term_sandbox
# The line is cut by this order: the name of the system first, then the manager, and the count never goes until
# nothing else is left. With a name of 55 characters, apt and 12 applications (ASCII, so the ellipsis is three dots)
# every width is checked against a line written by hand; 88/87, 45/44, 35/34 and 24/23 are the two sides of a limit.
SL_NAME='Linux Mint 22.3 Zena Cinnamon Edition, Long Long Name O'
check_eq 'control: the system name of the cut tests has 55 characters' 55 "${#SL_NAME}"
# sl_cut WIDTH [VAR=val ...]: the status line cut to WIDTH columns.
sl_cut() {
    local w="$1"; shift
    app_eval "SYS_PRETTY='$SL_NAME' PM=apt MENU_APPS=12; menu_status_text $w; printf '%s' \"\$REPLY\"" MINTAPP_LANG=en MINTAPP_ASCII=1 "$@"
}
sl_cut 88
check_eq 'status line, 88 columns: it fits whole' "$SL_NAME | apt | 12 applications detected" "$OUT"
sl_cut 87
check_eq 'status line, 87 columns: the name loses its last characters' 'Linux Mint 22.3 Zena Cinnamon Edition, Long Long Na... | apt | 12 applications detected' "$OUT"
sl_cut 60
check_eq 'status line, 60 columns: the name is cut, the manager and the count stay' 'Linux Mint 22.3 Zena Cin... | apt | 12 applications detected' "$OUT"
sl_cut 45
check_eq 'status line, 45 columns: the name keeps 12 columns, the least that is cut with the manager' 'Linux Min... | apt | 12 applications detected' "$OUT"
sl_cut 44
check_eq 'status line, 44 columns: the manager goes' 'Linux Mint 22.... | 12 applications detected' "$OUT"
sl_cut 35
check_eq 'status line, 35 columns: the name keeps 8 columns, the least that is cut with the count' 'Linux... | 12 applications detected' "$OUT"
sl_cut 34
check_eq 'status line, 34 columns: the system goes, the count stays whole' '12 applications detected' "$OUT"
sl_cut 24
check_eq 'status line, 24 columns: the count alone fits' '12 applications detected' "$OUT"
sl_cut 23
check_eq 'status line, 23 columns: not even the count fits, and it is cut' '12 applications dete...' "$OUT"
# Whatever the width: never wider than it, and from the width of the count up the count is never cut.
app_eval "SYS_PRETTY='$SL_NAME' PM=apt MENU_APPS=12; bad=''
    for w in \$(seq 24 100); do
        menu_status_text \$w
        [ \"\${#REPLY}\" -le \$w ] || bad+=\" wide:\$w\"
        case \$REPLY in *'12 applications detected') ;; *) bad+=\" count:\$w\" ;; esac
    done
    for w in 20 21 22 23; do menu_status_text \$w; [ \"\${#REPLY}\" -le \$w ] || bad+=\" wide:\$w\"; done
    printf '<<%s>>' \"\$bad\"" MINTAPP_LANG=en MINTAPP_ASCII=1
check_eq 'status line, 20 to 100 columns: never wider than its width, and the count is kept from 24 up' '<<>>' "$OUT"
if have_utf8; then
    sl_cut 60 MINTAPP_ASCII=0 LC_ALL=C.UTF-8
    check_eq 'status line in Unicode, 60 columns: one ellipsis character, the separators are one column each' 'Linux Mint 22.3 Zena Cinna… · apt · 12 applications detected' "$OUT"
    sl_cut 45 MINTAPP_ASCII=0 LC_ALL=C.UTF-8
    check_eq 'status line in Unicode, 45 columns: it still fits the width' 'Linux Mint… · apt · 12 applications detected' "$OUT"
else
    skip_case 'status line in Unicode: the cut counts characters (no generated UTF-8 locale)'
fi
# The width each engine gives it: gui wraps its own text (200), tui the terminal minus 6 columns with a ceiling of
# 110, whiptail the text area of its box (WT_BOX_W - 6, with the ceiling of the box) and never fewer than 20.
sw() { app_eval "UI_ENGINE=$1; menu_status_width; printf '%s' \"\$REPLY\"" PATH="$T_PATH" FAKE_COLS="$2" MINTAPP_ASCII=1; }
for sw_cols in 40 200; do
    sw gui "$sw_cols"
    check_eq "status width, gui on $sw_cols columns: 200, whatever the terminal" 200 "$OUT"
done
for sw_case in 40:34 80:74 115:109 116:110 117:110 200:110; do
    sw tui "${sw_case%%:*}"
    check_eq "status width, tui on ${sw_case%%:*} columns" "${sw_case##*:}" "$OUT"
done
for sw_case in 40:30 80:67 130:113 131:114 132:114 200:114; do
    sw whiptail "${sw_case%%:*}"
    check_eq "status width, whiptail on ${sw_case%%:*} columns" "${sw_case##*:}" "$OUT"
done
for sw_engine in tui whiptail; do
    app_eval "read_terminal_size() { TERM_LINES=24 TERM_COLS=10; }; UI_ENGINE=$sw_engine; menu_status_width; printf '%s' \"\$REPLY\"" MINTAPP_ASCII=1
    check_eq "status width, $sw_engine on a terminal with next to no columns: never fewer than 20" 20 "$OUT"
done
# What goes above the list: tui lists its keys itself, so it gets the status line alone; the others add the
# instruction to choose (the line breaks are the \n sequences the dialogs turn into breaks).
for mp_case in 'tui|' 'gui|\n\nSelect an option:' 'whiptail|\n\nSelect an option (↑ ↓ + Enter):'; do
    app_eval "SYS_PRETTY='Linux Mint 22.3' PM=apt MENU_APPS=2; UI_ENGINE=${mp_case%%|*}; menu_prompt_text; printf '%s' \"\$REPLY\"" PATH="$T_PATH" MINTAPP_LANG=en MINTAPP_ASCII=0
    check_eq "text above the list, ${mp_case%%|*}: the status line${mp_case##*|}" "Linux Mint 22.3 · apt · 2 applications detected${mp_case##*|}" "$OUT"
done
# End to end. The plain-text menu takes its width from the terminal: no line is wider than the screen and the
# count is always there, from 40 columns to a wide window.
printf 'ID=long\nPRETTY_NAME="%s"\n' "$SL_NAME" > "$SB/os-release-long"; sandbox_chown
fake_installed firefox thunderbird
for sl_cols in 40 50 60 80 100 140; do
    app_run $'\n0\n' MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1 PATH="$T_PATH" FAKE_COLS=$sl_cols FAKE_LINES=30 MINTAPP_OS_RELEASE="$SB/os-release-long"
    sl_wide="$(plain | widest)"
    if [ "$sl_wide" -le $((sl_cols - 1)) ]; then sl_fit=ok; else sl_fit="$sl_wide columns"; fi
    check_eq "text menu, $sl_cols columns, a 55-character system name: nothing wider than the screen" ok "$sl_fit"
    check_eq "text menu, $sl_cols columns, a 55-character system name: the status line keeps its count" '2 applications detected' \
        "$(plain | grep -a -m1 -E 'detected$' | sed -E 's/.*[^0-9]([0-9]+ applications detected)$/\1/; s/^ //')"
done
# whiptail: the first line of the text of its box is the status line, cut for the box (60 columns: box of 55, text
# area of 49) or whole (140 columns), and a blank line follows it.
wt_menu_text() { awk -v want="${1:-1}" 'prev == "--menu" && ++c == want { print; exit } { prev = $0 }' "$SB/state/whiptail.args" | tr '\036' '\n'; }
if have_utf8; then
    for sl_cols in 60:'Linux Mint 22.3… · apt · 2 applications detected' 140:"$SL_NAME"' · apt · 2 applications detected'; do
        fake_answers OK 'TAG:0'; : > "$SB/state/whiptail.args"
        app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=en PATH="$T_PATH" FAKE_COLS="${sl_cols%%:*}" FAKE_LINES=24 MINTAPP_ASCII=0 LANG=C.UTF-8 MINTAPP_OS_RELEASE="$SB/os-release-long"
        check_eq "whiptail menu, ${sl_cols%%:*} columns: the first line of the box is the status line, then a blank one" \
            "${sl_cols#*:}"$'\n\nSelect an option (↑ ↓ + Enter):' "$(wt_menu_text 1)"
    done
else
    skip_case 'whiptail menu: the status line cut for the box (no generated UTF-8 locale)'
fi

echo "-- main menu: the count of applications is taken once and retaken when it must be (F7.0)"
# The count asks the manager once per package. It is taken on the first screen and then kept: the same
# calls are not made again, so a menu that is drawn many times costs the same as one drawn once.
term_sandbox
fake_installed firefox thunderbird
# dpkgq.log has a line per call of dpkg-query: the lines before and after the second count tell what is a new call
# and what is a repeated one. "first" is the count, "probed" that the first one did ask, "repeated" the lines the
# second one added, "stale" what the count says once the system has changed behind its back, "retaken" that it
# asks again, and "fresh" what it says, only after the program drops what it kept (MENU_APPS=-1).
app_eval 'q() { wc -l < "$DPKGQ"; }
    menu_apps_count; first=$REPLY; a=$(q)
    menu_apps_count; again=$REPLY; b=$(q)
    echo pix >> "$INSTALLED"
    menu_apps_count; stale=$REPLY; c=$(q)
    MENU_APPS=-1; menu_apps_count; fresh=$REPLY; d=$(q)
    printf "first=%s probed=%s again=%s repeated=%s stale=%s repeated=%s fresh=%s retaken=%s" \
        "$first" "$((a > 0 ? 1 : 0))" "$again" "$((b - a))" "$stale" "$((c - b))" "$fresh" "$((d > c ? 1 : 0))"' \
    DPKGQ="$SB/state/dpkgq.log" INSTALLED="$SB/state/installed" MINTAPP_LANG=en
check_eq 'count: taken once (2 installed), the second one asks nothing, a change is seen only when it is dropped' \
    'first=2 probed=1 again=2 repeated=0 stale=2 repeated=0 fresh=3 retaken=1' "$OUT"
# The same on the screen: a menu drawn three times asks dpkg-query as often as one drawn once.
mq_run() { : > "$SB/state/dpkgq.log"; app_run "$1" MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1 PATH="$T_PATH"; wc -l < "$SB/state/dpkgq.log"; }
mq_once="$(mq_run $'\n0\n')"
mq_thrice="$(mq_run $'\n7\n7\n0\n')"
check_eq 'control: the menu does ask the manager for its count' 1 "$((mq_once > 0 ? 1 : 0))"
check_eq 'a menu drawn three times asks the manager as many times as one drawn once' "$mq_once" "$mq_thrice"

echo "-- main menu: the count is retaken after a removal and after option 1 (F7.0)"
# fl_run INPUT: the text menu on the system of fl_system, 24x80 without colour; FL is the number of applications
# on each status line, in order, separated by |.
fl_system() {
    term_sandbox
    printf 'ID=linuxmint\nPRETTY_NAME="Linux Mint 22.3"\n' > "$SB/os-release"; sandbox_chown
}
fl_run() {
    app_run "$1" MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1 PATH="$T_PATH" MINTAPP_OS_RELEASE="$SB/os-release" "${@:2}"
    FL="$(plain | grep -a ' · apt · ' | sed -E 's/.* · ([0-9]+) application.*/\1/' | paste -sd'|')"
}
# Option 3 removes VLC and, with it, Thunderbird. Screens, in order: the start (2 applications), after option 1
# (2), after option 3 has removed two (1), after option 2 (1).
fl_system
fake_installed firefox thunderbird vlc; fake_dependents vlc thunderbird
make_desktop vlc.desktop 'VLC player'; fake_owner "$SB/apps/vlc.desktop" vlc
fl_run $'\n1\n\n3\n\n1\nc\ny\n\n2\n\n0\n0\n'
check_eq 'removing from option 3: the count of the next screens drops from 2 to 1' '2|2|1|1' "$FL"
check_eq 'removing from option 3: the program ended normally and really removed' '0|1' "$RC|$(real_removals)"
# DETECTION_DONE: option 1 scanned the catalog, but the removal made that scan old. Option 2, which would show it
# as it is, scans again: after the removal its list has Firefox and no Thunderbird.
fl_third="$(plain | grep -a -n ' · apt · ' | sed -n 3p | cut -d: -f1)"
fl_after="$(plain | tail -n +"$fl_third")"
assert_contains 'removing from option 3: option 2 scans again and lists Firefox' "$fl_after" 'Firefox'
assert_not_contains 'removing from option 3: option 2 does not list what was removed with it (Thunderbird)' "$fl_after" 'Thunderbird'
# Cleaning unused dependencies (option 4, then 1) removes packages too.
fl_system
fake_installed firefox thunderbird; fake_autoremovable firefox
fl_run $'\n4\n1\ny\n\n0\n'
check_eq 'cleaning unused dependencies: the count drops from 2 to 1' '2|1' "$FL"
assert_contains 'cleaning unused dependencies: the autoremove did run' "$(apt_log)" 'apt-get autoremove -y'
# A removal that is not confirmed removes nothing and keeps the count (the plan is shown, then cancelled).
fl_system
fake_installed firefox thunderbird; fake_autoremovable firefox
fl_run $'\n4\n1\nn\n\n0\n'
check_eq 'cleaning cancelled: nothing is removed and the count stays at 2' '2|2' "$FL"
# Option 1 retakes the count. A sleep that installs Thunderbird the first time it is called changes the system
# between two screens: the first redraw (after an invalid key) still says 1, the one after option 1 says 2.
fl_system
fake_installed firefox
printf '#!/bin/sh\ngrep -qx thunderbird "%s" || echo thunderbird >> "%s"\nexit 0\n' "$SB/state/installed" "$SB/state/installed" > "$SB/bin/sleep"
chmod 755 "$SB/bin/sleep"; sandbox_chown
fl_run $'\n7\n1\n\n0\n'
check_eq 'a change behind the menu: the redraw keeps the count (1), option 1 takes it again (2)' '1|1|2' "$FL"
assert_contains 'a change behind the menu: option 1 lists the new application too' "$(plain)" '✓ Thunderbird'
echo "-- main menu entries and the G hook (FU.3)"
app_eval 'build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"' MINTAPP_LANG=en
check_eq 'no graphical menu yet: the entries are 1 2 3 4 L 0' '<<1 2 3 4 L 0>>' "$OUT"
app_eval 'gui_available() { return 0; }; build_main_menu; printf "<<%s|%s|%s>>" "${MENU_TAGS[*]}" "${MENU_LABELS[4]}" "${MENU_DESCS[4]}"' MINTAPP_LANG=en
check_eq 'with a graphical menu G comes after 4 and before L' '<<1 2 3 4 G L 0|Graphical menu|Open the windowed version.>>' "$OUT"
app_eval 'build_main_menu; printf "<<%s>>" "${#MENU_LABELS[@]}${#MENU_DESCS[@]}"' MINTAPP_LANG=es
check_eq 'every entry has a label and a description (6 and 6)' '<<66>>' "$OUT"
app_eval_in $'g\n0\n' 'gui_available() { return 0; }; switch_to_gui() { echo GUI-OPENED; }; clear() { :; }; sleep() { :; }; main_menu_text' MINTAPP_LANG=en NO_COLOR=1
assert_contains 'text menu: g opens the graphical menu when it is offered' "$OUT" 'GUI-OPENED'
app_eval_in $'G\n0\n' 'gui_available() { return 0; }; switch_to_gui() { echo GUI-OPENED; }; clear() { :; }; sleep() { :; }; main_menu_text' MINTAPP_LANG=en NO_COLOR=1
assert_contains 'text menu: G in capitals too' "$OUT" 'GUI-OPENED'
assert_contains 'text menu: the G entry is listed' "$OUT" 'G. Graphical menu'
app_eval_in $'g\n0\n' 'switch_to_gui() { echo GUI-OPENED; }; clear() { :; }; sleep() { :; }; main_menu_text' MINTAPP_LANG=en NO_COLOR=1
assert_not_contains 'text menu: g does nothing while the graphical menu is not offered' "$OUT" 'GUI-OPENED'
assert_contains 'text menu: g is answered as an invalid option' "$OUT" 'Invalid option.'
app_eval_in $'g\n0\n' 'gui_available() { return 0; }; switch_to_gui() { return 1; }; clear() { :; }; sleep() { :; }; main_menu_text' MINTAPP_LANG=en NO_COLOR=1
assert_not_contains 'text menu: a graphical menu that fails to open is not an invalid option' "$OUT" 'Invalid option.'
app_eval_in $'7\n\n0\n' 'clear() { :; }; sleep() { :; }; main_menu_text' MINTAPP_LANG=en NO_COLOR=1
assert_contains 'text menu: a number that is not an option is still invalid' "$OUT" 'Invalid option.'
# Going back from a list is not a mistake: only a key that is not an option is "Invalid option.".
for ba_tag in 2 3 4; do
    app_eval_in "$ba_tag"$'\n0\n' 'uninstall_programs() { return 1; }; find_other_apps() { return 1; }; clean_menu() { return 1; }; clear() { :; }; sleep() { :; }; main_menu_text' MINTAPP_LANG=en NO_COLOR=1
    assert_not_contains "text menu: option $ba_tag, when the user goes back (status 1), is not an invalid option" "$OUT" 'Invalid option.'
done
new_sandbox; fake_installed firefox
app_run $'\n2\n0\n0\n' MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1
assert_not_contains 'text menu: going back from the list of option 2 is not an invalid option' "$OUT" 'Invalid option.'
check_eq 'text menu: going back from the list of option 2 ends normally' 0 "$RC"

echo "-- main menu on whiptail: label and description on one line (FU.3)"
new_sandbox
mkdir -p "$SB/term"
printf '#!/bin/sh\ncase "$1" in lines) echo "${FAKE_LINES:-24}" ;; cols) echo "${FAKE_COLS:-80}" ;; colors) echo 256 ;; *) exit 1 ;; esac\n' > "$SB/term/tput"
chmod +x "$SB/term/tput"; sandbox_chown
M_PATH="$SB/term:$SB/bin:/usr/local/bin:/usr/bin:/bin"
fake_answers OK 'TAG:0'
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=en PATH="$M_PATH" FAKE_COLS=140 FAKE_LINES=40 MINTAPP_ASCII=0
assert_contains 'whiptail menu, wide terminal: the description follows the label' "$(cat "$SB/state/whiptail.log")" '1 Detect applications - See which catalog applications are installed.'
assert_contains 'whiptail menu, wide terminal: the exit entry too' "$(cat "$SB/state/whiptail.log")" '0 Exit - Leave without making further changes.'
fake_answers OK 'TAG:0'
: > "$SB/state/whiptail.log"
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=en PATH="$M_PATH" FAKE_COLS=60 FAKE_LINES=24 MINTAPP_ASCII=0 LANG=C.UTF-8
W_LOG="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail menu, 60 columns: the description is cut with an ellipsis to the label width' "$W_LOG" '1 Detect applications - See which catalo… 2 Uninstall applications - Pick and remo… 3 Find other applications (advanced) 4 Clean up - '
assert_not_contains 'whiptail menu, 60 columns: a label with no room left for a description goes alone, without a dangling dash' "$W_LOG" '(advanced) -'
fake_answers OK 'TAG:L' 'TAG:0'
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=en PATH="$M_PATH" FAKE_COLS=140 FAKE_LINES=40 MINTAPP_ASCII=0
assert_contains 'whiptail menu: L switches the language and the menu comes back in Spanish' "$(cat "$SB/state/whiptail.log")" '1 Detectar aplicaciones - Ver qué aplicaciones del catálogo hay instaladas.'
fake_answers OK 'TAG:G' 'TAG:0'
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=en
check_eq 'whiptail menu: a G answer while it is not offered does nothing and the menu stays' 0 "$RC"

echo "-- robustness: the input ends at every step of a flow (D5)"
# Each flow runs once for every way its input can end: with no lines, with the first one, and so on up to all of them
# (the stub whiptail does the same with its answers: when they run out it answers Esc). Every run must end by itself with
# status 0 and no bash error, remove only from the line that confirms and leave no temporary file (TMPDIR and the
# state folder are in the sandbox). A confirmation typed without its line break must not confirm.
# cut_verdict STATUS OUTPUT: "ok", or why the run is not.
cut_verdict() {
    if [ "$1" -eq 124 ]; then echo timeout
    elif printf '%s' "$2" | grep -qE ': line [0-9]+: |unbound variable|syntax error|bad substitution|bad array subscript|unexpected EOF|command not found'; then echo 'bash error'
    elif [ "$1" -ne 0 ]; then echo "status $1"
    else echo ok; fi
}
# cut_leftovers: the temporary files a run left, one per line: in TMPDIR, and the ones of the atomic writes in HOME.
cut_leftovers() { { ls -A "$SB/tmp"; find "$SB/home" -name '.tmp.*' -printf '%f\n'; } 2>/dev/null; }
# cut_expect REMOVE_AT K: the removals a run with K lines must make (REMOVE_AT is the line that confirms; 0: never).
cut_expect() { if [ "$1" -gt 0 ] && [ "$2" -ge "$1" ]; then echo 1; else echo 0; fi; }
# cut_input K LINE...: sets CUT_INPUT to the first K lines, each one closed by a line break.
cut_input() {
    local k="$1" i
    shift
    CUT_INPUT=""
    for ((i = 1; i <= k; i++)); do CUT_INPUT+="${!i}"$'\n'; done
}
# cut_run INPUT [VAR=val ...]: one run of the program, with TMPDIR in the sandbox and 30 seconds at most (a run takes
# about one; app_run would wait 120 for every run of a flow that hangs).
cut_run() {
    local input="$1"
    shift
    mkdir "$SB/tmp"; sandbox_chown
    _exec "$input" 30 TMPDIR="$SB/tmp" "$@" -- "$H_BASH" "$H_SCRIPT"
}
# cut_check LABEL REMOVALS: the three checks on the run that has just ended.
cut_check() {
    local what='removes nothing'
    [ "$2" -eq 0 ] || what='removes once'
    check_eq "$1: ends by itself, with status 0 and no bash error" ok "$(cut_verdict "$RC" "$OUT")"
    check_eq "$1: $what" "$2" "$(real_removals)"
    check_eq "$1: leaves no temporary file" '' "$(cut_leftovers)"
}
# cut_text LABEL SETUP REMOVE_AT [VAR=val ...] -- LINE...: SETUP builds the sandbox before every run. A flow stops at its
# first timeout: the rest would only wait as long.
cut_text() {
    local label="$1" setup="$2" remove_at="$3" k n
    shift 3
    local -a envs=() lines=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    lines=("$@"); n=${#lines[@]}
    for ((k = 0; k <= n; k++)); do
        "$setup"
        cut_input "$k" "${lines[@]}"
        cut_run "$CUT_INPUT" MINTAPP_UI=text "${envs[@]+"${envs[@]}"}"
        cut_check "$label, input ends after $k of $n lines" "$(cut_expect "$remove_at" "$k")"
        [ "$RC" -ne 124 ] || return 0
    done
    if [ "$remove_at" -gt 0 ]; then
        "$setup"
        cut_input "$remove_at" "${lines[@]}"
        cut_run "${CUT_INPUT%$'\n'}" MINTAPP_UI=text "${envs[@]+"${envs[@]}"}"
        cut_check "$label, the confirmation without its line break" 0
    fi
}
# cut_wt LABEL SETUP REMOVE_AT [VAR=val ...] -- ANSWER...: the same with the answers of the stub whiptail.
cut_wt() {
    local label="$1" setup="$2" remove_at="$3" k n
    shift 3
    local -a envs=() answers=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    answers=("$@"); n=${#answers[@]}
    for ((k = 0; k <= n; k++)); do
        "$setup"
        fake_answers "${answers[@]:0:k}"
        cut_run '' MINTAPP_UI=whiptail "${envs[@]+"${envs[@]}"}"
        cut_check "$label, answers end after $k of $n" "$(cut_expect "$remove_at" "$k")"
        [ "$RC" -ne 124 ] || return 0
    done
}
cut_none()    { new_sandbox; }
cut_apps()    { new_sandbox; fake_installed firefox thunderbird; }
cut_orphans() { new_sandbox; fake_autoremovable libold1 libold2; }
cut_launcher() {
    new_sandbox; fake_installed vlc
    make_desktop vlc.desktop 'VLC media player'; fake_owner "$SB/apps/vlc.desktop" vlc
    sandbox_chown
}
cut_files() {
    new_sandbox
    fake_file "$SB/home/.local/share/recently-used.xbel" 300
    fake_file "$SB/home/.cache/thumbnails/normal/a.png" 200
}
cut_text 'robustness, help and menu'                  cut_none     0 -- l '' 0
cut_text 'robustness, detect'                         cut_apps     0 -- '' 1 '' 0
cut_text 'robustness, uninstall (English)'            cut_apps     5 MINTAPP_LANG=en -- '' 2 1 c y '' 0
cut_text 'robustness, uninstall (Spanish, two marks)' cut_apps     6 MINTAPP_LANG=es -- '' 2 1 2 c s '' 0
cut_text 'robustness, advanced'                       cut_launcher 6 -- '' 3 '' 1 c y '' 0
cut_text 'robustness, clean up dependencies'          cut_orphans  4 -- '' 4 1 y '' 0
cut_text 'robustness, deep cleanup refused with n'    cut_files    0 -- '' 4 2 s 2 1 c n '' 0
cut_text 'robustness, search then uninstall'          cut_apps     6 -- '' 2 's mail' 1 c y '' 0
cut_wt   'robustness, whiptail detect'                cut_apps     0 -- OK TAG:1 OK TAG:0
cut_wt   'robustness, whiptail uninstall'             cut_apps     5 -- OK TAG:2 'TAG:"1"' OK YES OK TAG:0
# Controls: the checks above must fail when they should.
new_sandbox; mkdir "$SB/tmp"; sandbox_chown
_exec '' 1 PATH="$H_SYS_PATH" -- "$H_BASH" -c 'sleep 5'
check_eq 'control: a run that does not end is a timeout' timeout "$(cut_verdict "$RC" "$OUT")"
_exec '' 5 -- "$H_BASH" -c 'mintapp_no_such_command; true'
check_eq 'control: a bash error counts even with status 0' 'bash error' "$(cut_verdict "$RC" "$OUT")"
_exec '' 5 -- "$H_BASH" -c 'echo done; exit 3'
check_eq 'control: a status other than 0 is reported with its number' 'status 3' "$(cut_verdict "$RC" "$OUT")"
_exec '' 5 -- "$H_BASH" -c 'echo done'
check_eq 'control: a clean run is accepted' ok "$(cut_verdict "$RC" "$OUT")"
check_eq 'control: no temporary file, none reported' '' "$(cut_leftovers)"
_exec '' 5 TMPDIR="$SB/tmp" -- "$H_BASH" -c 'mktemp "$TMPDIR/mintapp-x.XXXXXX" > /dev/null'
check_eq 'control: a file left in TMPDIR is reported' 1 "$(cut_leftovers | wc -l)"
: > "$SB/home/.tmp.abc123"
check_eq 'control: a file of an atomic write left in HOME is reported too' 2 "$(cut_leftovers | wc -l)"
check_eq 'control: no removal is expected before the confirming line' '0 0' "$(cut_expect 6 5) $(cut_expect 0 9)"
check_eq 'control: one removal is expected from the confirming line on' '1 1' "$(cut_expect 6 6) $(cut_expect 6 8)"
cut_input 2 a b c
check_eq 'control: cut_input gives the first lines, each with its line break' $'a\nb\n' "$CUT_INPUT"
cut_input 0 a b c
check_eq 'control: cut_input with 0 gives nothing' '' "$CUT_INPUT"

finish
