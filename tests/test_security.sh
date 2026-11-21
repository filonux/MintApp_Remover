#!/usr/bin/env bash
# Security (D5). The program must not reach the network, run text as code, call the privilege command from
# anywhere but three functions, or remove files outside the few functions meant to, and every name that comes
# from outside must be refused by the validators when it is hostile.
# The first part reads the program with a scanner that is tried on small faulty files before it judges the
# program, so it cannot go silent. A failure there is an alarm, not always a defect: review the change, then
# update the list that names it (DELETERS, RECURSIVE, TEMP_MAKERS, PRIV_RUNNERS). The second part runs the
# program. What the pm, stores and config suites prove about their own names and files is not repeated.
# The program is read through H_SCRIPT, so a changed copy (MINTAPP_TEST_SCRIPT) is judged too.
# SC2016 is off for the whole file: the code given to app_eval is single-quoted on purpose, because the
# program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

sorted() { printf '%s\n' "$@" | LC_ALL=C sort -u | paste -sd' ' -; }
yes_no() { if "$@"; then echo 1; else echo 0; fi; }

# The functions that remove files; the two that may remove a folder with what is inside; the ones that make
# temporary files; the ones that run the privilege command. A new one is reviewed first (what it touches,
# where, after which confirmation) and then added.
DELETERS="$(sorted gui_dialog priv_authenticate run_gui_step atomic_write clean_flush clean_apply clean_x11_logs \
    clean_open_done sweep_stale_temp_files gui_cleanup embedded_icon_write install_prune_empty cmd_install \
    uninstall_rm_dir uninstall_clean_temp cmd_uninstall)"
RECURSIVE="$(sorted gui_cleanup uninstall_rm_dir)"
TEMP_MAKERS="$(sorted gui_dialog gui_work_dir atomic_write clean_open_prepare)"
PRIV_RUNNERS="$(sorted priv_run priv_authenticate clean_priv_check)"

# ------------------------------------------------------------- the scanner ----
# scan MODE FILE prints "LINE<TAB>FUNCTION<TAB>KIND" for every finding, on the code only: comments are cut and
# continued lines are joined. Text inside quotes counts (a trap or "bash -c" string runs), so a message that
# holds a command name is flagged too: reword it. Heredocs are read as code.
SCAN="$H_TMP/scan.py"
cat > "$SCAN" <<'PYEOF'
import re
import sys

FUNC = re.compile(r"^(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{")
ONE_LINER = re.compile(r"\}\s*(?:#.*)?$")
START, PATH, END = r"(?<![\w.$-])", r"(?:[\w./-]*/)?", r"(?![\w-])"
# Where a command can start: the beginning of a statement, or after a word that runs its argument.
POS = r"(?:^|[;&|({`]|\$\(|\b(?:then|do|else|exec|command|env|nohup|time|xargs)\s+(?!-))\s*"
CONT = re.compile(r";|&&|\|\||\||\)|`")


def word(*names):
    return re.compile(START + PATH + "(" + "|".join(names) + ")" + END)


NET = word("curl", "wget", "aria2c", "nc", "ncat", "netcat", "socat", "telnet", "ssh", "scp", "sftp", "ftp",
           "tftp", "rsync", "ping", "traceroute", "nslookup", "dig", "openssl", "git", "pip", "pip3", "npm", "cargo")
URL = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://")
DEVNET = re.compile(r"/dev/(?:tcp|udp)\b")
EVAL = re.compile(START + "eval" + END)
SOURCE = re.compile(POS + r"(?:source|\.)\s+\S")
# A name followed by "|" or ")" is a case pattern and one followed by "*" is a glob ("*|pkexec*" in the exclusion
# lists), not a call. An entry of a message table, [key]="text", is read by people and never run.
DIRECT = re.compile(POS + r"(sudo-rs|sudo|doas|pkexec|su)(?![\w|)*])")
TEXT_ENTRY = re.compile(r"^\s*\[[A-Za-z0-9_]+\]=")
REMOVE = word("rm", "rmdir", "unlink", "shred")
FIND = word("find")
MKTEMP = word("mktemp")
# The saved traps are run by eval, so every mention of TUI_SAVED_TRAPS must be one of four forms: set empty, set
# from what "trap -p" prints, the test that it is not empty, and the eval itself. A form must not have more text
# glued to it (a closing quote, a word, a $).
GLUE = r'''(?![\w"'$`\\])'''
SAVED_FORMS = [
    ("empty", re.compile(r'(?<![\w$])TUI_SAVED_TRAPS=""' + GLUE)),
    ("trap", re.compile(r'(?<![\w$])TUI_SAVED_TRAPS="\$\(trap -p [A-Z ]+\)"' + GLUE)),
    ("test", re.compile(r'\[ -z "\$TUI_SAVED_TRAPS" \]')),
    ("eval", re.compile(r'(?<![\w-])eval "\$TUI_SAVED_TRAPS"' + GLUE)),
]


def strip_comment(line):
    """The line without its comment: a # that starts a word, outside quotes."""
    dq = sq = 0
    esc = False
    for k, ch in enumerate(line):
        if esc:
            esc = False
        elif ch == "\\" and not sq % 2:
            esc = True
        elif ch == "'" and not dq % 2:
            sq += 1
        elif ch == '"' and not sq % 2:
            dq += 1
        elif ch == "#" and not (dq % 2 or sq % 2) and (k == 0 or line[k - 1] in " \t;"):
            return line[:k]
    return line


def load(path):
    raw = open(path, encoding="utf-8").read().split("\n")
    rows, owner, i = [], "-", 0
    while i < len(raw):
        number, line = i + 1, raw[i]
        m = FUNC.match(line)
        if m:
            owner = m.group(1)
        text = strip_comment(line)
        while text.rstrip().endswith("\\") and i + 1 < len(raw):
            i += 1
            text = text.rstrip()[:-1] + " " + strip_comment(raw[i])
        rows.append((number, owner, text))
        if line == "}" or (m and ONE_LINER.search(line)):
            owner = "-"
        i += 1
    return rows


def statement(text, end):
    return CONT.split(text[end:])[0]


def main(mode, path):
    rows = load(path)
    if mode == "functions":
        print(len({owner for _, owner, _ in rows} - {"-"}))
        return
    for number, owner, text in rows:
        found = []
        if mode == "net":
            found += ["tool" for _ in NET.finditer(text)]
            found += ["url" for _ in URL.finditer(text)]
            found += ["devnet" for _ in DEVNET.finditer(text)]
        elif mode == "eval":
            found += ["eval" for _ in EVAL.finditer(text)]
            found += ["source" for _ in SOURCE.finditer(text)]
        elif mode == "priv":
            for m in re.finditer(r"\$\{?PRIV_CMD", text):
                after = text[m.end():]
                if after[:1] and after[0] in "#%/:^,@!?+=-":
                    continue  # ${PRIV_CMD##*/}: a part of the name, not a call
                if re.match(r"\s*\]", after.lstrip("}").lstrip('"')):
                    continue  # [ -n "$PRIV_CMD" ]: a test
                found.append("call")
            if not TEXT_ENTRY.match(text):
                found += ["direct" for _ in DIRECT.finditer(text)]
        elif mode == "rm":
            for m in REMOVE.finditer(text):
                options, dashdash = [], False
                for token in statement(text, m.end()).split():
                    if token == "--":
                        dashdash = True
                        break
                    if not token.startswith("-"):
                        break
                    options.append(token)
                found.append("rm")
                if any(re.match(r"-[A-Za-z]*[rR]", o) or o == "--recursive" for o in options):
                    found.append("recursive")
                if not dashdash:
                    found.append("no-dashdash")
            if FIND.search(text) and re.search(r"\s-delete(?![\w-])", text):
                found.append("rm")
                if not re.search(r"\s-(?:xdev|mount|maxdepth)\b", text):
                    found.append("wide-find")
        elif mode == "mktemp":
            for m in MKTEMP.finditer(text):
                rest = statement(text, m.end())
                good = re.search(r"X{6,}[\"']?(?:\s|$)", rest) and not re.search(r"\s-[A-Za-z]*u", rest)
                found.append("ok" if good else "bad")
        elif mode == "traps":
            known = []
            for kind, pattern in SAVED_FORMS:
                for m in pattern.finditer(text):
                    known.append((m.start(), m.end()))
                    found.append(kind)
            for m in re.finditer(r"TUI_SAVED_TRAPS", text):
                if not any(a <= m.start() < b for a, b in known):
                    found.append("other")
        for kind in found:
            print("%s\t%s\t%s" % (number, owner, kind))


main(sys.argv[1], sys.argv[2])
PYEOF

scan() { python3 "$SCAN" "$1" "$2"; }
# in_funcs MODE FILE KIND_REGEX: the functions with a finding of that kind, sorted, on one line.
in_funcs() { scan "$1" "$2" | awk -F'\t' -v k="$3" '$3 ~ k { print $2 }' | LC_ALL=C sort -u | paste -sd' ' -; }
# at_lines MODE FILE KIND_REGEX: the numbers of the lines with a finding of that kind, on one line.
at_lines() { scan "$1" "$2" | awk -F'\t' -v k="$3" '$3 ~ k { print $1 }' | LC_ALL=C sort -un | paste -sd, -; }

echo "-- the scanner finds what it looks for (small faulty files)"
FAULTS="$H_TMP/faults"
mkdir -p "$FAULTS"
# fault FILE LINE...: one line of the faulty file per argument.
fault() { local f="$FAULTS/$1"; shift; printf '%s\n' "$@" > "$f"; }
fault net.sh 'f() {' \
    '    curl -s example.org' \
    "    bash -c 'wget -q x'" \
    '    exec 3<>/dev/tcp/host/80' \
    '    url="https://example.org/x"' \
    '    /usr/bin/ping -c1 x' \
    '    # curl in a comment is not code' \
    '    ls ssh-* curly ssh_config # wget in a comment at the end' \
    '}'
check_eq 'net: a client, one inside a string, /dev/tcp, a URL and a client by path are found; comments, ssh-*, curly and ssh_config are not' 2,3,4,5,6 "$(at_lines net "$FAULTS/net.sh" .)"
fault eval.sh 'f() {' \
    '    eval "$x"' \
    '    source ./lib.sh' \
    '    . ./lib.sh' \
    '    [ -f x ] && . "$y"' \
    '    evaluate "$x"; echo "source of the problem" # eval' \
    '}'
check_eq 'eval: eval, source, the dot and the dot after && are found' 2,3,4,5 "$(at_lines eval "$FAULTS/eval.sh" .)"
fault priv.sh 'priv_run() {' \
    '    [ -n "$PRIV_CMD" ] || detect_privilege || return 127' \
    '    local name="${PRIV_CMD##*/}"' \
    '    "$PRIV_CMD" -A "$@"' \
    '}' \
    'sneaky() {' \
    '    SUDO_ASKPASS=x "$PRIV_CMD" -v' \
    '    sudo rm -f -- "$x"' \
    '    echo "sudo is needed"; command -v sudo > /dev/null' \
    '    case "$k" in sudo|doas) : ;; esac' \
    '    pkexec bash' \
    '    [help]="Command (default: sudo; doas if sudo is missing)"' \
    '    EXCLUDED=("*|pkexec*" "*|polkit*")' \
    '    doas -n true' \
    '    su -c true' \
    '    sudo-rs true' \
    '}'
check_eq 'priv: the calls are in priv_run and sneaky, not in the tests and the name expansion' 'priv_run sneaky' "$(in_funcs priv "$FAULTS/priv.sh" '^call$')"
check_eq 'priv: sudo, pkexec, doas, su and sudo-rs in command position are found; text, command -v, case patterns, globs and message-table entries are not' 8,11,14,15,16 "$(at_lines priv "$FAULTS/priv.sh" '^direct$')"
fault rm.sh 'remove_a() {' \
    '    rm -f -- "$a"' \
    '    rmdir -- "$d"' \
    '}' \
    'remove_b() {' \
    '    rm -rf "$b"' \
    '    priv_run rm -f -- "${list[@]}"' \
    '    find "$root" -type f -delete' \
    '    /bin/rm -f -- "$c"' \
    '    unlink "$d"' \
    '    # rm -rf / is only a comment' \
    '    echo "removing" # rm' \
    '}' \
    "remove_c() { find \"\$x\" -maxdepth 1 -name '.tmp.*' -delete; }" \
    'remove_d() {' \
    "    rm -f \\" \
    '        -- "$e"' \
    '}' \
    'remove_e() { unlink -- "$f"; }' \
    'remove_f() { shred -u -- "$f"; }' \
    'remove_g() { rm --recursive -- "$g"; }' \
    'remove_h() { find "$h" -mount -type f -delete; }'
check_eq 'rm: every function that removes is found, also by path, after priv_run, in a one-line function and with unlink or shred alone' 'remove_a remove_b remove_c remove_d remove_e remove_f remove_g remove_h' "$(in_funcs rm "$FAULTS/rm.sh" '^rm$')"
check_eq 'rm: the functions with -r or --recursive remove a folder with its contents, the others do not' 'remove_b remove_g' "$(in_funcs rm "$FAULTS/rm.sh" '^recursive$')"
check_eq 'rm: a missing -- is found (and not when the -- is on a continued line)' remove_b "$(in_funcs rm "$FAULTS/rm.sh" '^no-dashdash$')"
check_eq 'rm: a find -delete that may leave the file system or go deep is found, one with -maxdepth or -mount is not' remove_b "$(in_funcs rm "$FAULTS/rm.sh" '^wide-find$')"
check_eq 'rm: comments are not removals' 'remove_a remove_b remove_c remove_d remove_e remove_f remove_g remove_h' "$(in_funcs rm "$FAULTS/rm.sh" '.')"
fault mktemp.sh 'make_a() {' \
    '    f="$(mktemp "${TMPDIR:-/tmp}/app.XXXXXX")" || exit 1' \
    '    d="$(mktemp -d "$base/app.XXXXXX")"' \
    '}' \
    'make_b() {' \
    '    f="$(mktemp /tmp/app)"' \
    '    g="$(mktemp -u "$base/app.XXXXXX")"' \
    '    h="$(mktemp "$base/app.XXXXX")"' \
    '}'
check_eq 'mktemp: the functions that make temporary files are found' 'make_a make_b' "$(in_funcs mktemp "$FAULTS/mktemp.sh" '.')"
check_eq 'mktemp: a name without a template, with -u or with five X is bad' make_b "$(in_funcs mktemp "$FAULTS/mktemp.sh" '^bad$')"
check_eq 'mktemp: a template of six X, also with -d, is good (only make_a has one)' make_a "$(in_funcs mktemp "$FAULTS/mktemp.sh" '^ok$')"
fault traps.sh 'tui_open() {' \
    '    TUI_SAVED_TRAPS="$(trap -p INT TERM HUP WINCH)"' \
    '}' \
    'tui_close() {' \
    '    [ -z "$TUI_SAVED_TRAPS" ] || eval "$TUI_SAVED_TRAPS"' \
    '}' \
    'TUI_SAVED_TRAPS=""' \
    'one_liner() { TUI_SAVED_TRAPS="$1"; }' \
    'others() {' \
    '    TUI_SAVED_TRAPS+="; rm x"' \
    '    read -r TUI_SAVED_TRAPS' \
    '    local TUI_SAVED_TRAPS="$1"' \
    '    : "${TUI_SAVED_TRAPS:=$1}"' \
    '    TUI_SAVED_TRAPS="$(trap -p INT TERM HUP WINCH; touch x)"' \
    '    TUI_SAVED_TRAPS=""$1' \
    '    printf -v TUI_SAVED_TRAPS "%s" "$1"' \
    '    echo "$TUI_SAVED_TRAPS"' \
    '    eval "${TUI_SAVED_TRAPS}"' \
    '    # TUI_SAVED_TRAPS="$1" in a comment is not code' \
    '    echo done # eval "$TUI_SAVED_TRAPS"' \
    '}' \
    'again() { eval "$TUI_SAVED_TRAPS"; }'
check_eq 'traps: set from trap -p, the test, the eval, set empty and an eval in a one-line function are the known forms' \
    '2:trap 5:test 5:eval 7:empty 22:eval' \
    "$(scan traps "$FAULTS/traps.sh" | awk -F'\t' '$3 != "other" { print $1 ":" $3 }' | paste -sd' ' -)"
check_eq 'traps: any other mention is found (one-line function, +=, read, local, :=, more after trap -p, a glued word, printf -v, echo, ${}); comments are not' \
    8,10,11,12,13,14,15,16,17,18 "$(at_lines traps "$FAULTS/traps.sh" '^other$')"
check_eq 'the scanner sees the program: it finds its functions (hundreds)' 1 "$(yes_no test "$(scan functions "$H_SCRIPT")" -gt 300)"

echo "-- no network client, no URL and no /dev/tcp in the code"
check_eq 'the program calls no network client, holds no URL and opens no /dev/tcp or /dev/udp' '' "$(scan net "$H_SCRIPT" | head -n3)"

echo "-- no text is run as code"
check_eq 'the only eval is the one that restores the saved traps' tui_close "$(in_funcs eval "$H_SCRIPT" '^eval$')"
check_eq 'TUI_SAVED_TRAPS is mentioned four times, one of each form: set empty, set from what trap -p prints, tested, evaled' \
    'empty eval test trap' "$(scan traps "$H_SCRIPT" | cut -f3 | LC_ALL=C sort | paste -sd' ' -)"
check_eq 'the program sources nothing' '' "$(at_lines eval "$H_SCRIPT" '^source$')"

echo "-- administrator rights run from three places only"
check_eq 'PRIV_CMD is called only by priv_run, priv_authenticate and clean_priv_check' "$PRIV_RUNNERS" "$(in_funcs priv "$H_SCRIPT" '^call$')"
check_eq 'sudo, doas, pkexec and su are never called by name' '' "$(scan priv "$H_SCRIPT" | awk -F'\t' '$3 == "direct"' | head -n3)"

echo "-- files are removed only where they should be"
check_eq 'only the known functions remove files (a new one: review it, then add it to DELETERS)' "$DELETERS" "$(in_funcs rm "$H_SCRIPT" '^rm$')"
check_eq 'only two functions remove a folder with its contents (RECURSIVE)' "$RECURSIVE" "$(in_funcs rm "$H_SCRIPT" '^recursive$')"
check_eq 'every rm, rmdir and unlink ends its options with --, so a name cannot read as an option' '' "$(in_funcs rm "$H_SCRIPT" '^no-dashdash$')"
check_eq 'every find -delete stays on one file system or one level (-xdev or -maxdepth)' '' "$(in_funcs rm "$H_SCRIPT" '^wide-find$')"

echo "-- temporary files"
check_eq 'only the known functions make temporary files (TEMP_MAKERS)' "$TEMP_MAKERS" "$(in_funcs mktemp "$H_SCRIPT" '.')"
check_eq 'every mktemp has a template of six X or more and never -u' '' "$(in_funcs mktemp "$H_SCRIPT" '^bad$')"

echo "-- hostile names are refused by every validator"
# Every string below must be refused by every validator, whatever it checks. The bytes outside ASCII are written
# as \x escapes, so the list does not depend on the locale this suite runs in. The names with dots are for the
# Flatpak ID, which needs three elements to get past its first test; the letters and digits that are not ASCII
# (accents, full-width letters, "²", Arabic and Devanagari digits) are what a range such as [a-z] or [0-9] takes
# in en_US.UTF-8 and others (D7).
# The last two are over the length limits: 300 letters (a Flatpak ID refuses them for having no dots) and a Flatpak ID
# of 256 characters, 255 being the longest allowed, which only its length refuses (P41).
HOSTILE=(
    '' - -rf --help -- ' ' 'a b' ' a' 'a ' $'a\tb' $'a\nb' $'a\n' $'\nrm' $'a\rb'
    $'firefox\n' $'\nfirefox' $'org.mozilla.firefox\n' $'vlc\n' $'flathub\n' $'Foo_bar\n'
    'a;b' 'a&&b' 'a|b' 'a$(id)' 'a`id`' 'a"b' "a'b" 'a\b' 'a*' 'a?' 'a[b]' 'a<b' 'a>b' 'a(b)' 'a{b}' 'a!b'
    'a#b' 'a=b' 'a%b' 'a^b' 'org.a.b;touch pwned' 'firefox && reboot'
    ../x /etc/passwd a/b ./a '~' '~root' '$HOME' '${HOME}'
    $'a\x01b' $'a\eb' $'a\x7fb' $'a\xe2\x80\x8bb' $'a\xe2\x80\xaeb'
    $'\xc3\xb1and\xc3\xba' $'caf\xc3\xa9' $'\xd0\xb0pp' $'\xef\xbd\x81\xef\xbd\x82\xef\xbd\x83' $'\xc3\x9f'
    $'\xc3\x89' $'a\xc3\x89' $'\xef\xbc\xa1\xef\xbc\xa2' $'\xce\xb1\xce\xb2' $'a-\xc3\xa9' $'lib\xc3\xa96'
    $'\xc2\xb2' $'a\xc2\xb2' $'\xc2\xb2\xc2\xb2' $'a\xc2\xb2b' $'a\xc2\xbc' $'a\xd9\xa3' $'a\xe0\xa5\xab'
    $'a\xef\xbc\x90' $'a\xe2\x82\x80' $'a\xe2\x91\xa0'
    $'org.mozilla.caf\xc3\xa9' $'org.\xc3\xb1and\xc3\xba.app' $'\xc3\xa9org.a.b' $'org.mozilla.f\xc3\xafrefox'
    $'org.a.b\xc2\xb2' $'org.a.\xc2\xb2' $'org.\xc2\xb2.b' $'\xef\xbd\x8f\xef\xbd\x92\xef\xbd\x87.a.b'
    $'org.a.\xef\xbd\x82' $'org.a.\xd9\xa3' $'org.a.b\xc3\x89' $'org.a.b-\xc3\xa9'
    "$(printf 'a%.0s' {1..300})" "a.b.$(printf 'c%.0s' {1..252})"
)
HFILE="$H_TMP/hostile.list"
printf '%s\0' "${HOSTILE[@]}" > "$HFILE"
chmod 644 "$HFILE"
# detect_system takes ID and ID_LIKE from os-release: a good file, one in capitals, and six whose ID and one ID_LIKE
# word are made of letters or digits that are not ASCII (café, ñandú, full-width "abc", "ß", "a²", "É").
OSR_DIR="$H_TMP/osr"
OSR_NAMES="good capitals hostile1 hostile2 hostile3 hostile4 hostile5 hostile6"
mkdir -p "$OSR_DIR"
printf 'ID=debian\nID_LIKE="ubuntu debian"\n' > "$OSR_DIR/good"
printf 'ID=DEBIAN\nID_LIKE="UBUNTU DEBIAN"\n' > "$OSR_DIR/capitals"
n=0
for word in $'caf\xc3\xa9' $'\xc3\xb1and\xc3\xba' $'\xef\xbd\x81\xef\xbd\x82\xef\xbd\x83' $'\xc3\x9f' $'a\xc2\xb2' $'\xc3\x89'; do
    n=$((n + 1))
    printf 'ID=%s\nID_LIKE="ubuntu %s debian"\n' "$word" "$word" > "$OSR_DIR/hostile$n"
done
SYS_EXPECT="$(printf 'SYSTEM good|debian|ubuntu debian\nSYSTEM capitals|debian|ubuntu debian\n'
    for n in 1 2 3 4 5 6; do printf 'SYSTEM hostile%s||ubuntu debian\n' "$n"; done)"
HOSTILE_CODE='
# refused LABEL VALIDATOR...: prints "ACCEPTED LABEL name" for each hostile name the validator takes.
refused() {
    local label="$1" name
    shift
    while IFS= read -r -d "" name; do
        if "$@" "$name"; then printf "ACCEPTED %s %q\n" "$label" "$name"; fi
    done < "$HOSTILE_FILE"
}
# accepts LABEL VALIDATOR NAME: prints "CONTROL LABEL" when a valid name passes, so a validator that is
# never called right cannot look strict.
accepts() { local label="$1"; shift; if "$@"; then printf "CONTROL %s\n" "$label"; fi; }
# What this locale does with "é": LOCALE alpha when it is a letter (any UTF-8 locale; in C it is two bytes), and
# ARMED when a range such as [a-z] takes it too (en_US, es_ES, de_DE and tr_TR; not C or C.utf8): the trap of D7.
e="$(printf "\xc3\xa9")"
if [[ $e =~ ^[[:alpha:]]$ ]]; then printf "LOCALE alpha\n"; else printf "LOCALE plain\n"; fi
if [[ $e =~ ^[a-z]$ ]]; then printf "ARMED\n"; fi
for PM in apt dnf pacman zypper; do refused "pm_valid_name($PM)" pm_valid_name; done
refused is_flatpak_id is_flatpak_id
refused is_snap_name is_snap_name
refused is_flatpak_remote is_flatpak_remote
PM=apt; accepts "pm_valid_name(apt)" pm_valid_name libc6:i386
for PM in dnf pacman zypper; do accepts "pm_valid_name($PM)" pm_valid_name Foo_bar@1; done
accepts is_flatpak_id is_flatpak_id org.mozilla.firefox
accepts is_snap_name is_snap_name vlc
accepts is_flatpak_remote is_flatpak_remote flathub
# The configuration: no hostile name is a key or a value, and near misses of a good pair are refused too.
config_value() { config_valid "$1" "$2"; }
config_key() { config_valid "$1" gui; }
for key in interface language help_seen; do refused "config_valid($key)" config_value "$key"; done
refused config_valid_key config_key
accepts config_valid config_valid interface gui
nl="$(printf "\n_")"; nl="${nl%_}"
for pair in "interface |gui" " interface|gui" "INTERFACE|gui" "interface|gui;rm" "interface|gui " "interface|GUI" "interface|"; do
    if config_valid "${pair%%|*}" "${pair#*|}"; then printf "ACCEPTED near_miss %q\n" "$pair"; fi
done
if config_valid interface "gui$nl"; then printf "ACCEPTED near_miss gui-newline\n"; fi
# detect_system is not a validator but reads ID and ID_LIKE with the same kind of pattern.
for name in $OSR_NAMES; do
    MINTAPP_OS_RELEASE="$OSR_DIR/$name" detect_system
    printf "SYSTEM %s|%s|%s\n" "$name" "$SYS_ID" "$SYS_ID_LIKE"
done
'
# The locales: C, C.utf8 when the system has it, and four built here with localedef in the suite's own folder
# (no administrator rights; the program finds them through LOCPATH). They are where a range such as [a-z] also
# takes "é", full-width letters and "²" (D7), so the validators are tried in them. One that cannot be built (no
# localedef, or no /usr/share/i18n: the "locales" package) is skipped and said; with CI set it is a failure.
LOCDIR="$H_TMP/locales"
mkdir -p "$LOCDIR"
locales=(C)
mapfile -t system_locales < <(locale -a 2> /dev/null || true)
for loc in "${system_locales[@]}"; do
    case "$loc" in C.utf8|C.UTF-8) locales+=("$loc"); break ;; esac
done
built=0
for loc in en_US es_ES de_DE tr_TR; do
    if command -v localedef > /dev/null 2>&1 \
        && localedef --no-archive -i "$loc" -f UTF-8 "$LOCDIR/$loc.UTF-8" > /dev/null 2>&1; then
        locales+=("$loc.UTF-8")
        built=$((built + 1))
    else
        skip_case "the locale $loc.UTF-8 cannot be built here (localedef and the locales package are needed)"
        # The CI installs locales (quality.yml): there, skipping would leave the trap of D7 unarmed without a failure.
        [ -z "${CI:-}" ] || check_eq "CI: the locale $loc.UTF-8 is built (localedef and the locales package are installed)" built skipped
    fi
done
chmod -R a+rX "$LOCDIR"
armed=()
for loc in "${locales[@]}"; do
    new_sandbox
    app_eval "$HOSTILE_CODE" HOSTILE_FILE="$HFILE" OSR_DIR="$OSR_DIR" OSR_NAMES="$OSR_NAMES" LC_ALL="$loc" LOCPATH="$LOCDIR"
    check_eq "[$loc] the code ran to the end" 0 "$RC"
    want=alpha
    [ "$loc" != C ] || want=plain
    check_eq "[$loc] the locale is really in effect (\"é\" is $([ "$want" = alpha ] && echo a letter || echo not a letter))" \
        "LOCALE $want" "$(grep '^LOCALE ' <<< "$OUT" || true)"
    if grep -qx 'ARMED' <<< "$OUT"; then armed+=("$loc"); fi
    check_eq "[$loc] every validator took its good name (7 names, 1 for the configuration)" 8 "$(grep -c '^CONTROL' <<< "$OUT" || true)"
    for v in 'pm_valid_name(apt)' 'pm_valid_name(dnf)' 'pm_valid_name(pacman)' 'pm_valid_name(zypper)' is_flatpak_id is_snap_name \
        is_flatpak_remote; do
        check_eq "[$loc] $v refuses every hostile name" '' "$(grep -F "ACCEPTED $v " <<< "$OUT" | head -n3 || true)"
    done
    check_eq "[$loc] config_valid refuses every hostile key and value, and the near misses of a good pair" '' \
        "$(grep -E '^ACCEPTED (config_valid|near_miss)' <<< "$OUT" | head -n3 || true)"
    check_eq "[$loc] detect_system reads a good ID, also in capitals, and drops the ID and the ID_LIKE word that are not ASCII" \
        "$SYS_EXPECT" "$(grep '^SYSTEM ' <<< "$OUT" || true)"
done
if [ "$built" -gt 0 ]; then
    check_eq 'control: a locale built here takes "é" in [a-z], so the trap of D7 is armed' 1 "$(yes_no test "${#armed[@]}" -gt 0)"
else
    skip_case 'no locale could be built: the trap of D7 (a range that takes "é") is not exercised here'
fi

echo "-- the validators write their characters out (a range follows the locale, D7)"
new_sandbox
app_eval 'declare -f pm_valid_name is_flatpak_id is_snap_name is_flatpak_remote
printf "%s=%s\n" LOWER "$ID_LOWER" UPPER "$ID_UPPER" DIGIT "$ID_DIGIT"'
check_eq 'pm_valid_name, is_flatpak_id, is_snap_name and is_flatpak_remote hold no range such as [a-z] or [0-9]' '' \
    "$(grep -nE '\[[^]]*[A-Za-z0-9]-[A-Za-z0-9]' <<< "$OUT" | head -n3 || true)"
check_eq 'ID_LOWER, ID_UPPER and ID_DIGIT hold exactly the ASCII letters and the ten digits' \
    "$(printf 'LOWER=%s\nUPPER=%s\nDIGIT=%s' abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789)" \
    "$(grep -E '^(LOWER|UPPER|DIGIT)=' <<< "$OUT" || true)"

echo "-- a run reaches no network client"
new_sandbox
fake_installed firefox thunderbird
: > "$SB/state/net.log"
for tool in curl wget nc ncat netcat socat telnet ssh scp sftp ftp rsync ping dig nslookup openssl git pip pip3 npm; do
    _stub "$tool" <<'EOF'
#!/bin/sh
echo "${0##*/} $*" >> @STATE@/net.log
exit 1
EOF
done
sandbox_chown
app_run '' -- --help
app_run '' -- --version
app_run $'\n1\n\n0\n' MINTAPP_UI=text
app_run $'\nl\n3\n\n0\n0\n' MINTAPP_UI=text
app_run $'\n4\n0\n0\n' MINTAPP_UI=text
app_run $'\n2\n\n1\nc\ny\n\n0\n' MINTAPP_UI=text
check_eq 'control: the removal of the last run went through (so the flows did run)' 1 "$(real_removals)"
app_run '' -- install
app_run '' -- uninstall --purge
check_eq 'help, version, the five menus, a removal, install and uninstall called no network client' '' "$(cat "$SB/state/net.log")"

finish
