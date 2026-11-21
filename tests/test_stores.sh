#!/usr/bin/env bash
# Flatpak and Snap (F4.5a): the privileged command for anything (priv_run), the progress window for
# any command (run_gui_step), the strict identifiers, the plan lines and the removal records, also
# when a run is interrupted. Stub sudo and zenity; nothing real.
# SC2016 is off: the code given to app_eval is single-quoted on purpose, the program expands it.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

GUI=(DISPLAY=:99 MINTAPP_UI=gui MINTAPP_ASCII=0 MINTAPP_LANG=en)

# fresh: a new sandbox with a folder for the windows (its zenity stub has no answers: every window is closed); ge CODE [VAR=val ...]: CODE
# with the windows usable. GUI_STOP_TICKS=400 (D2): in these tests sleep is a stub that returns at once, so a tick lasts about
# 0.9 ms (20 ticks, the default, are 18 ms; 400 are about 0.35 s), not the 0.15 s of real use. With the default, a zenity stub that
# shares the CPU can need more than 20 ticks to log its call, and the program kills the window first. Measured threshold: between
# 20 and 40 ticks, the same with 4 and with 16 busy processes; 400 is at least 10 times that.
fresh() { new_sandbox; mkdir -p "$SB/tmp"; sandbox_chown; }
ge() { local code="$1"; shift; app_eval "GUI_STOP_TICKS=400; zenity_usable; $code" "${GUI[@]}" TMPDIR="$SB/tmp" "$@"; }

# value_of LABEL EXPECTED: the text between << and >> of OUT.
value_of() { local v="${OUT#*<<}"; check_eq "$1" "$2" "${v%%>>*}"; }
# body FILE: a record without its date line (the only one that changes).
body() { grep -v '^# Date: ' "$1"; }

echo "-- priv_run: the command line each tool receives"
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
args_of() { cat "$SB/$1" 2>/dev/null || echo '(not called)'; }

app_eval 'priv_run FOO=1 flatpak uninstall -y org.a.b.c; printf "<<%s>>" "$?"' PATH="$SB/pb-sudo"
check_eq 'sudo gets the variable directly' 'FOO=1 flatpak uninstall -y org.a.b.c' "$(args_of pb-sudo/sudo.args)"
value_of 'priv_run returns 0 when the command succeeds' 0
app_eval 'priv_run snap remove vlc' PATH="$SB/pb-sudo"
check_eq 'sudo without variables gets the command as it is' 'snap remove vlc' "$(args_of pb-sudo/sudo.args)"
app_eval 'priv_run FOO=1 flatpak uninstall -y org.a.b.c' PATH="$SB/pb-doas"
check_eq 'doas gets the variable through env' 'env FOO=1 flatpak uninstall -y org.a.b.c' "$(args_of pb-doas/doas.args)"
app_eval 'priv_run snap remove vlc' PATH="$SB/pb-doas"
check_eq 'doas without variables gets the command as it is (no env rule needed)' 'snap remove vlc' "$(args_of pb-doas/doas.args)"
app_eval 'priv_run X-Y=1 snap remove vlc' PATH="$SB/pb-doas"
check_eq 'a first word that is not a variable name gets no env' 'X-Y=1 snap remove vlc' "$(args_of pb-doas/doas.args)"
app_eval 'priv_run FOO=1 snap remove vlc' PATH="$SB/pb-none" MINTAPP_SUDO="$SB/pb-mysu/mysu"
check_eq 'a custom command gets the variable through env' 'env FOO=1 snap remove vlc' "$(args_of pb-mysu/mysu.args)"
rm -f "$SB"/pb-both/*.args
app_eval 'priv_run snap remove vlc' PATH="$SB/pb-both"
check_eq 'with both installed only sudo is called' '1|0' "$(find "$SB/pb-both" -name sudo.args | wc -l)|$(find "$SB/pb-both" -name doas.args | wc -l)"
mkpriv pb-fail sudo 7
app_eval 'priv_run snap remove vlc; printf "<<%s>>" "$?"' PATH="$SB/pb-fail"
value_of 'the exit status of the privileged command is passed on' 7
app_eval 'priv_run snap remove vlc; printf "<<%s>>" "$?"' PATH="$SB/pb-none"
value_of 'without any privilege command priv_run fails with 127' 127
rm -f "$SB"/pb-sudo/*.args
app_eval 'priv_run; printf "<<%s>>" "$?"' PATH="$SB/pb-sudo"
value_of 'nothing to run: status 2' 2
check_eq 'nothing to run: the privilege command is not called' '(not called)' "$(args_of pb-sudo/sudo.args)"

echo "-- priv_run in windows: the password is asked with -A"
fresh
ge 'UI_ENGINE=gui; priv_run MYVAR=hello printenv MYVAR'
check_eq 'windows: the command runs and sees the variable' 'hello' "$OUT"
check_eq 'windows: sudo was called with -A' 'sudo -A MYVAR=hello printenv MYVAR' "$(sudo_log)"
: > "$SB/state/sudo.log"
app_eval 'UI_ENGINE=text; priv_run MYVAR=hello printenv MYVAR'
check_eq 'terminal: the command runs and sees the variable' 'hello' "$OUT"
check_eq 'terminal: sudo without -A (it asks on the terminal)' 'sudo MYVAR=hello printenv MYVAR' "$(sudo_log)"

echo "-- apt_privileged goes through priv_run"
new_sandbox
app_eval 'priv_run() { echo "PR $*"; }; apt_privileged purge -y firefox'
check_eq 'apt_privileged asks priv_run for the same apt-get line as always' \
    'PR DEBIAN_FRONTEND=noninteractive apt-get purge -y firefox' "$OUT"

echo "-- run_gui_step: the progress window for any command"
fresh
ge 'f() { printf "one\ntwo\n"; return 0; }; PM_TAIL=keep; run_gui_step "Working <x>..." f; st=$?; printf "<<%s|%s|%s|%s>>" "$st" "$GUI_PROGRESS_PID" "$STEP_TAIL" "$PM_TAIL"'
value_of 'a shell function: its status, the window closed, the last lines kept; PM_TAIL untouched' $'0||one\ntwo|keep'
check_eq 'one window: the progress one' 1 "$(zenity_calls)"
assert_contains 'it is a progress window' "$(zenity_call)" '--progress'
assert_contains 'with the text given, as a label' "$(zenity_call)" '--text=Working &lt;x&gt;...'
check_eq 'its input ended (that is what closes it)' 1 "$(grep -c '^@@END@@$' "$SB/state/zenity.stdin")"
fresh
ge 'f() { echo "boom"; return 3; }; run_gui_step "x" f; st=$?; printf "<<%s|%s>>" "$st" "$STEP_TAIL"'
value_of 'a command that fails: its status and its output are kept' '3|boom'
fresh
app_eval_in 'secret' 'zenity_usable; run_gui_step "x" cat; printf "<<%s|%s>>" "$?" "$STEP_TAIL"' "${GUI[@]}" TMPDIR="$SB/tmp"
value_of 'the command does not get the input of the program (a read ends at once)' '0|'
fresh
ge 'f() { echo "out"; echo "err" >&2; }; run_gui_step "x" f; printf "<<%s>>" "$STEP_TAIL"'
check_eq 'standard error is kept as well, and nothing of the command is written on the terminal' $'<<out\nerr>>' "$OUT"
fresh
ge 'f() { echo "out"; return 4; }; STEP_TAIL=stale; run_gui_step "x" f; st=$?; printf "<<%s|%s>>" "$st" "$STEP_TAIL"' TMPDIR="$SB/nowhere"
value_of 'no private folder: the command runs without the window and its status is its own' '4|'
check_eq 'no private folder: no window' 0 "$(zenity_calls)"
fresh
ge 'run_gui_step() { echo "RGS $*"; STEP_TAIL="last line"; return 5; }; PM_TAIL=stale; run_pm_gui "Working..." purge x; st=$?; printf "<<%s|%s>>" "$st" "$PM_TAIL"'
assert_contains 'run_pm_gui hands pm_run and its arguments to run_gui_step' "$OUT" 'RGS Working... pm_run purge x'
value_of 'run_pm_gui keeps the status and puts the last lines in PM_TAIL' '5|last line'
fresh; fake_installed mintstick
ge 'UI_ENGINE=gui; run_pm_gui "x" purge mintstick; st=$?; printf "<<%s|%s>>" "$st" "$PM_TAIL"'
value_of 'run_pm_gui end to end: apt-get ran and its last line is kept' '0|Removing mintstick ...'
check_eq 'run_pm_gui end to end: with -A, as before' \
    'sudo -A DEBIAN_FRONTEND=noninteractive apt-get purge -y mintstick' "$(sudo_log)"

echo "-- run_gui_step: a window that does not end by itself is stopped after GUI_STOP_TICKS"
fresh
mv "$SB/bin/zenity" "$SB/bin/zenity.real"
printf '%s\n' '#!/bin/sh' 'PATH=/usr/local/bin:/usr/bin:/bin' 'case " $* " in *" --progress "*) exec sleep 62 ;; esac' \
    "exec \"$SB/bin/zenity.real\" \"\$@\"" > "$SB/bin/zenity"
chmod 755 "$SB/bin/zenity"; sandbox_chown
ge 'f() { echo done; }; GUI_STOP_TICKS=2; run_gui_step "x" f; st=$?; printf "<<%s|%s|%s>>" "$st" "$GUI_PROGRESS_PID" "$STEP_TAIL"'
value_of 'the window never ends: the step returns, the window is forgotten and the output is kept' '0||done'
check_eq 'the window that never ended was stopped' 0 "$(ps -eo args= | awk '/sleep 62$/ { n++ } END { print n + 0 }')"

echo "-- identifiers: only what is safe reaches a command line"
# idcheck FUNCTION LABEL VALID... -- INVALID...: each value is checked by FUNCTION in one run.
idcheck() {
    local fn="$1" what="$2" v mode=yes code="" i=0
    local -a want=() shown=()
    shift 2
    for v in "$@"; do
        if [ "$v" = "--" ]; then mode=no; continue; fi
        printf -v code '%s if %s %q; then echo yes; else echo no; fi;' "$code" "$fn" "$v"
        want+=("$mode"); shown+=("$v")
    done
    app_eval "$code"
    local -a got=()
    mapfile -t got <<< "$OUT"
    for i in "${!want[@]}"; do
        if [ "${want[$i]}" = yes ]; then
            check_eq "$what: $(printf '%q' "${shown[$i]}") is accepted" yes "${got[$i]:-missing}"
        else
            check_eq "$what: $(printf '%q' "${shown[$i]}") is refused" no "${got[$i]:-missing}"
        fi
    done
}
LONG255="a.b.$(printf 'c%.0s' {1..251})"; LONG256="a.b.$(printf 'c%.0s' {1..252})"
idcheck is_flatpak_id 'Flatpak ID' org.mozilla.firefox com.github.Eloston.UngoogledChromium org.gnome.gedit \
    io.github.some-user.App-Name org.freedesktop.Platform.Compat.i386 org.kde.kdenlive "$LONG255" -- \
    -rf --user -org.a.b org.foo org.foo. .org.foo.bar org..foo.bar 1org.foo.bar org.foo.-bar 'org.foo.bar baz' \
    'org.foo.bar;ls' 'org.foo.$(id)' 'org.foo.bar"x' "org.foo.bar'x" $'org.foo.bar\nx' $'org.foo.bar\r' $'org.foo.\e[31m' \
    '' "$LONG256"
idcheck is_snap_name 'Snap name' firefox vlc core22 gnome-3-38-2004 a1 1a ab "$(printf 'a%.0s' {1..40})" -- \
    -rf rf- a 12 a--b Firefox 'a b' 'a;b' a_b '$(id)' $'snap\n' '' "$(printf 'a%.0s' {1..41})"
idcheck is_flatpak_remote 'Flatpak remote' flathub fedora gnome-nightly my.remote_1 -- \
    -x --system '' 'a b' a/b 'a;b' $'a\nb'

echo "-- plan lines"
# plan_case LABEL EXPECTED LINE: EXPECTED is "status|kind|scope|id|remote" after parse_store_line
# (the four fields are empty after a failure).
plan_case() {
    local code
    printf -v code 'parse_store_line %q; printf "<<%%s|%%s|%%s|%%s|%%s>>" "$?" "$STORE_KIND" "$STORE_SCOPE" "$STORE_ID" "$STORE_REMOTE"' "$3"
    app_eval "$code"
    value_of "$1" "$2"
}
new_sandbox
plan_case 'a Flatpak of the system with its remote'    '0|flatpak|system|org.mozilla.firefox|flathub' 'flatpak system org.mozilla.firefox flathub'
plan_case 'a Flatpak of the user without a remote'     '0|flatpak|user|org.gnome.gedit|'              'flatpak user org.gnome.gedit'
plan_case 'a Snap'                                     '0|snap|system|vlc|'                           'snap system vlc'
plan_case 'tabs and extra spaces are tolerated'        '0|snap|system|vlc|'                           $'  snap\t system   vlc  '
plan_case 'an option as the identifier is refused'     '1||||'                                        'flatpak system -rf'
plan_case 'an option as the Snap name is refused'      '1||||'                                        'snap system -rf'
plan_case 'a scope that does not exist is refused'     '1||||'                                        'flatpak root org.a.b.c'
plan_case 'a Snap is always of the system'             '1||||'                                        'snap user vlc'
plan_case 'a Snap has no remote'                       '1||||'                                        'snap system vlc stable'
plan_case 'a remote that reads as an option is refused' '1||||'                                       'flatpak system org.a.b.c --system'
plan_case 'a field left over is refused'               '1||||'                                        'flatpak user org.a.b.c flathub extra'
plan_case 'a store that does not exist is refused'     '1||||'                                        'apt system foo'
plan_case 'a line without the identifier is refused'   '1||||'                                        'flatpak user'
plan_case 'an empty line is refused'                   '1||||'                                        ''
plan_case 'a control character in the line is refused' '1||||'                                        $'flatpak user org.a.b.c\e[31m'

echo "-- write_store_record: the record"
new_sandbox
PLAN=$'flatpak system org.mozilla.firefox flathub\nflatpak user org.gnome.gedit\nsnap system vlc'
app_eval 'write_store_record "$HOME/rec.txt" completed "$PLAN"; echo "rc=$?"' PLAN="$PLAN"
check_eq 'it is written and returns 0' 'rc=0' "$OUT"
EXPECTED='# MintApp Remover removal record
# Status: completed
# Operation: flatpak uninstall
# Operation: snap remove
#
# Applications in the plan:
flatpak system org.mozilla.firefox flathub
flatpak user org.gnome.gedit
snap system vlc
#
# To reinstall (review first; the remote or the channel may have changed):
# sudo flatpak install --system flathub org.mozilla.firefox
# flatpak install --user org.gnome.gedit
# sudo snap install vlc'
check_eq 'the whole record: status, operations, plan and hints' "$EXPECTED" "$(body "$SB/home/rec.txt")"
assert_contains 'the date is there' "$(cat "$SB/home/rec.txt")" '# Date: 20'
check_eq 'it is private (mode 600)' 600 "$(stat -c '%a' "$SB/home/rec.txt")"
check_eq 'no temporary file is left' 0 "$(find "$SB/home" -name '.tmp.*' | wc -l)"
assert_not_contains 'a finished run has no interruption note' "$(cat "$SB/home/rec.txt")" 'interrupted'

app_eval 'PRIV_CMD=/usr/bin/doas; write_store_record "$HOME/rec-doas.txt" completed "$PLAN"' PLAN="$PLAN"
assert_contains 'with doas the hint for the system Flatpak says doas' "$(cat "$SB/home/rec-doas.txt")" '# doas flatpak install --system flathub org.mozilla.firefox'
assert_contains 'with doas the hint for the Snap says doas' "$(cat "$SB/home/rec-doas.txt")" '# doas snap install vlc'
assert_contains 'the hint for the Flatpak of the user needs no privileges' "$(cat "$SB/home/rec-doas.txt")" '# flatpak install --user org.gnome.gedit'
assert_not_contains 'with doas nothing mentions sudo' "$(cat "$SB/home/rec-doas.txt")" 'sudo'

app_eval 'write_store_record "$HOME/rec-int.txt" interrupted "$PLAN"' PLAN="$PLAN"
assert_contains 'an interrupted record says so' "$(cat "$SB/home/rec-int.txt")" '# Status: interrupted'
assert_contains 'it warns that part of the plan may be applied' "$(cat "$SB/home/rec-int.txt")" 'part of this plan may already be applied'
assert_contains 'it says how to see the Flatpaks that remain' "$(cat "$SB/home/rec-int.txt")" '# See what is still installed: flatpak list --app'
assert_contains 'it says how to see the Snaps that remain' "$(cat "$SB/home/rec-int.txt")" '# See what is still installed: snap list'
assert_not_contains 'it does not talk about dpkg (that is apt)' "$(cat "$SB/home/rec-int.txt")" 'dpkg'
app_eval 'write_store_record "$HOME/rec-snap.txt" interrupted "snap system vlc"'
assert_not_contains 'only Snaps: no Flatpak command' "$(cat "$SB/home/rec-snap.txt")" 'flatpak'
app_eval 'write_store_record "$HOME/rec-fp.txt" "failed (exit code 1)" "flatpak user org.a.b.c"'
assert_contains 'a failed run says how it failed' "$(cat "$SB/home/rec-fp.txt")" '# Status: failed (exit code 1)'
assert_not_contains 'only Flatpaks: no Snap command' "$(cat "$SB/home/rec-fp.txt")" 'snap'

app_eval 'write_store_record "$HOME/rec.txt" started "flatpak user org.a.b.c"; write_store_record "$HOME/rec.txt" completed "flatpak user org.a.b.c"; echo "rc=$?"'
check_eq 'a second write replaces the first: one status line, the final one' 'rc=0|# Status: completed' "$OUT|$(grep '^# Status' "$SB/home/rec.txt")"

echo "-- write_store_record: what is not valid is left out"
new_sandbox
app_eval 'write_store_record "$HOME/rec.txt" started "$PLAN"' PLAN=$'flatpak system -rf\nsnap system vlc'
check_eq 'an identifier such as -rf gets no plan line and no hint; the rest stays' \
    '# MintApp Remover removal record
# Status: started
# Operation: snap remove
#
# Applications in the plan:
snap system vlc
# (1 invalid line(s) left out)
#
# To reinstall (review first; the remote or the channel may have changed):
# sudo snap install vlc' "$(body "$SB/home/rec.txt")"
app_eval 'write_store_record "$HOME/rec.txt" started "$PLAN"' PLAN=$'flatpak system -rf\nsnap system --purge'
assert_not_contains 'nothing valid: no reinstall hint at all' "$(cat "$SB/home/rec.txt")" 'To reinstall'
assert_not_contains 'nothing valid: the invalid text is not copied' "$(cat "$SB/home/rec.txt")" '-rf'
assert_contains 'nothing valid: it says how many were left out' "$(cat "$SB/home/rec.txt")" '# (2 invalid line(s) left out)'
app_eval 'write_store_record "$HOME/rec.txt" started ""; echo "rc=$?"'
check_eq 'an empty plan still gives a record' 'rc=0' "$OUT"
assert_not_contains 'an empty plan: no lines of invalid text' "$(cat "$SB/home/rec.txt")" 'invalid'
app_eval 'write_store_record "$HOME/rec.txt" started "$PLAN"' PLAN=$'snap system vlc\n\n   \nsnap system gimp'
check_eq 'blank lines are ignored and not counted as invalid' '2|0' \
    "$(grep -c '^snap system ' "$SB/home/rec.txt")|$(grep -c invalid "$SB/home/rec.txt" || true)"
app_eval 'write_store_record "$HOME/rec.txt" started "$PLAN"' PLAN=$'flatpak user org.a.b.c\e[31m\nsnap system vlc\nsnap system gimp\x01'
check_eq 'control characters never reach the record: no byte outside the printable ones' 0 "$(LC_ALL=C tr -d '\n\t -~' < "$SB/home/rec.txt" | wc -c)"
check_eq 'the lines with control characters are the ones left out' '1|2' \
    "$(grep -c '^snap system vlc$' "$SB/home/rec.txt")|$(sed -n 's/^# (\([0-9]*\) invalid.*/\1/p' "$SB/home/rec.txt")"
: > "$SB/home/afile"; sandbox_chown
app_eval 'write_store_record "$HOME/afile/rec.txt" started "snap system vlc" 2>/dev/null; echo "rc=$?"'
check_eq 'a record that cannot be written returns failure' 'rc=1' "$OUT"

echo "-- write_store_record: the applications that were not removed"
new_sandbox
PLAN=$'flatpak system org.mozilla.firefox flathub\nflatpak user org.gnome.gedit\nsnap system vlc'
app_eval 'write_store_record "$HOME/rec.txt" "failed (1 of 3 applications not removed)" "$PLAN" "$FAILED"' PLAN="$PLAN" FAILED='snap system vlc'
check_eq 'a failed application is listed apart and has no reinstall hint; the others keep theirs' \
    '# MintApp Remover removal record
# Status: failed (1 of 3 applications not removed)
# Operation: flatpak uninstall
# Operation: snap remove
#
# Applications in the plan:
flatpak system org.mozilla.firefox flathub
flatpak user org.gnome.gedit
snap system vlc
#
# Not removed (the command failed):
snap system vlc
#
# To reinstall (review first; the remote or the channel may have changed):
# sudo flatpak install --system flathub org.mozilla.firefox
# flatpak install --user org.gnome.gedit' "$(body "$SB/home/rec.txt")"
app_eval 'write_store_record "$HOME/rec.txt" failed "$PLAN" "$FAILED"' PLAN="$PLAN" FAILED=$'flatpak system org.mozilla.firefox flathub\nflatpak user org.gnome.gedit\nsnap system vlc'
assert_not_contains 'everything failed: no reinstall section at all' "$(cat "$SB/home/rec.txt")" 'To reinstall'
check_eq 'everything failed: the three are listed as not removed' 3 "$(sed -n '/^# Not removed/,$p' "$SB/home/rec.txt" | grep -c '^[a-z]')"
app_eval 'write_store_record "$HOME/rec.txt" failed "$PLAN" "$FAILED"' PLAN="$PLAN" FAILED=$'  snap\t system   vlc  '
assert_contains 'a failed line with other spacing is still recognised as the plan line' "$(cat "$SB/home/rec.txt")" $'# Not removed (the command failed):\nsnap system vlc\n'
assert_not_contains 'and its hint is left out' "$(cat "$SB/home/rec.txt")" 'snap install vlc'
app_eval 'write_store_record "$HOME/rec.txt" failed "$PLAN" "$FAILED"' PLAN="$PLAN" FAILED='snap system gimp'
assert_not_contains 'a failed line that is not in the plan is ignored' "$(cat "$SB/home/rec.txt")" 'Not removed'
assert_contains 'and every hint stays' "$(cat "$SB/home/rec.txt")" '# sudo snap install vlc'
app_eval 'write_store_record "$HOME/rec.txt" failed "$PLAN" "$FAILED"' PLAN="$PLAN" FAILED=$'snap system --purge\nflatpak user -rf\nsnap system vlc'
check_eq 'invalid failed lines are not copied; the valid one is (once in the plan, once apart)' '2|0' \
    "$(grep -c '^snap system vlc$' "$SB/home/rec.txt" | head -n1)|$(grep -c -e '--purge' -e '-rf' "$SB/home/rec.txt" || true)"
check_eq 'invalid failed lines are not counted as invalid plan lines' 0 "$(grep -c 'invalid' "$SB/home/rec.txt" || true)"
app_eval 'write_store_record "$HOME/rec.txt" interrupted "$PLAN" "$FAILED"' PLAN="$PLAN" FAILED='snap system vlc'
assert_contains 'an interrupted record can carry the failed ones too' "$(cat "$SB/home/rec.txt")" '# Not removed (the command failed):'
app_eval 'write_store_record "$HOME/rec.txt" completed "$PLAN"; write_store_record "$HOME/rec2.txt" completed "$PLAN" ""' PLAN="$PLAN"
check_eq 'with no failed lines (not given, or empty) the record is the same' '' "$(diff <(body "$SB/home/rec.txt") <(body "$SB/home/rec2.txt"))"
assert_not_contains 'and it has no "Not removed" section' "$(cat "$SB/home/rec.txt")" 'Not removed'

echo "-- an interrupted run leaves its record (on_exit)"
new_sandbox
app_eval 'ACTIVE_RECORD="$HOME/store.txt"; ACTIVE_STORE=1; ACTIVE_PLAN="$PLAN"; on_exit; printf "<<%s|%s>>" "$ACTIVE_RECORD" "$ACTIVE_STORE"' PLAN=$'flatpak user org.a.b.c\nsnap system vlc'
value_of 'on_exit clears the run in progress' '|0'
check_eq 'a Flatpak/Snap run: the record is the interrupted one of the stores' \
    '# MintApp Remover removal record
# Status: interrupted
# The run was interrupted: part of this plan may already be applied.
# See what is still installed: flatpak list --app
# See what is still installed: snap list
# Operation: flatpak uninstall
# Operation: snap remove
#
# Applications in the plan:
flatpak user org.a.b.c
snap system vlc
#
# To reinstall (review first; the remote or the channel may have changed):
# flatpak install --user org.a.b.c
# sudo snap install vlc' "$(body "$SB/home/store.txt")"
app_eval 'ACTIVE_RECORD="$HOME/apt.txt"; ACTIVE_PLAN="Purg foo [1.0]"; ACTIVE_REQUEST="purge foo"; on_exit'
assert_contains 'an apt run still writes the apt record' "$(cat "$SB/home/apt.txt")" '# Operation: apt-get purge foo'
assert_contains 'an apt run still suggests dpkg --configure' "$(cat "$SB/home/apt.txt")" 'dpkg --configure -a'
assert_contains 'the apt record names the manager of its plan' "$(cat "$SB/home/apt.txt")" '# Packages in the apt plan:'
assert_contains 'the apt record gives the reinstall line' "$(cat "$SB/home/apt.txt")" '# sudo apt-get install foo'
assert_contains 'the apt hint carries the privilege command' "$(cat "$SB/home/apt.txt")" '# If apt reports a broken state, run: sudo dpkg --configure -a'
app_eval 'ACTIVE_RECORD="$HOME/apt2.txt"; ACTIVE_PLAN="snap system vlc"; ACTIVE_STORE=0; on_exit'
assert_contains 'ACTIVE_STORE=0 means apt, whatever the plan looks like' "$(cat "$SB/home/apt2.txt")" '# Operation: apt-get'
new_sandbox
app_eval 'ACTIVE_STORE=1; on_exit; echo done'
check_eq 'with no run in progress nothing is written' 'done|0' "$OUT|$(find "$SB/home" -type f | wc -l)"
new_sandbox
app_eval 'install_traps; ACTIVE_RECORD="$HOME/term.txt"; ACTIVE_STORE=1; ACTIVE_PLAN="snap system vlc"; kill -TERM $$; sleep 5'
check_eq 'a real SIGTERM ends the program with 143' 143 "$RC"
assert_contains 'a real SIGTERM leaves the store record as interrupted' "$(cat "$SB/home/term.txt" 2>/dev/null || echo none)" '# Status: interrupted'
assert_contains 'a real SIGTERM: with the Snap in the plan' "$(cat "$SB/home/term.txt" 2>/dev/null || echo none)" 'snap system vlc'
# D2: a second signal while on_exit runs (strace showed a bash subshell sending SIGHUP to the whole
# group after the first one; which subshell is not identified) must neither stop the cleanup nor
# change the status: the signals are ignored there.
for again in HUP TERM; do
    new_sandbox
    app_eval 'install_traps; gui_cleanup() { kill -s '"$again"' $$; }; ACTIVE_RECORD="$HOME/again.txt"; ACTIVE_STORE=1; ACTIVE_PLAN="snap system vlc"; kill -TERM $$; sleep 5'
    check_eq "SIG$again while on_exit runs: the program still ends with the status of the first signal" 143 "$RC"
    assert_contains "SIG$again while on_exit runs: the record is still written as interrupted" \
        "$(cat "$SB/home/again.txt" 2>/dev/null || echo none)" '# Status: interrupted'
done

# ------------------------------------------------------------------------------------------------
# 4.5b: plan, confirmation and removal. flatpak and snap are stubs that keep their state in
# $SB/state: flatpak.system and flatpak.user (one ID per line), snap.list (one name per line),
# store.fail ("ID STATUS": that removal fails with that status), store.hang (an ID whose removal
# never ends: the stub writes "hung PGID" in hang.marker, its process group, and waits), stores.log (every call), during.log (the
# status line of the removal record as each removal starts) and during.ID.txt (the whole record).
# The stubs are as strict as the real commands about what the program must always give: a scope
# for flatpak, --noninteractive and -y for a Flatpak removal, nothing but the name for snap.
# ------------------------------------------------------------------------------------------------
stub_stores() {
    _stub flatpak <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
echo "flatpak $*" >> "$S/stores.log"
cmd="$1"; shift
scope=""; id=""; ni=0; yes=0; so=0
for a in "$@"; do
    case "$a" in
        --user) scope=user ;;
        --system) scope=system ;;
        --noninteractive) ni=1 ;;
        --show-origin) so=1 ;;
        -y|--assumeyes) yes=1 ;;
        -*) echo "error: Unknown option $a" >&2; exit 1 ;;
        *) if [ -z "$id" ]; then id="$a"; else echo "error: too many arguments" >&2; exit 1; fi ;;
    esac
done
[ -n "$scope" ] || { echo "error: the program must say --user or --system" >&2; exit 1; }
case "$cmd" in
    info)
        cat > /dev/null
        if grep -qx -- "$id" "$S/flatpak.$scope" 2>/dev/null; then
            if [ "$so" = 1 ]; then awk -v i="$id" '$1==i{print $2}' "$S/flatpak.origin" 2>/dev/null | head -n1; else echo "ID: $id"; fi
            exit 0
        fi
        echo "error: $id not installed" >&2; exit 1 ;;
    uninstall)
        { [ "$ni" = 1 ] && [ "$yes" = 1 ]; } || { echo "error: it would ask a question" >&2; exit 1; }
        grep -qx -- "$id" "$S/flatpak.$scope" 2>/dev/null || { echo "error: $id not installed" >&2; exit 1; }
        cat "$HOME"/.local/state/mintapp-remover/removal-*.txt > "$S/during.$id.txt" 2>/dev/null
        printf '%s: %s\n' "$id" "$(grep -h '^# Status' "$S/during.$id.txt" 2>/dev/null | head -n1)" >> "$S/during.log"
        if [ "$(cat "$S/store.hang" 2>/dev/null)" = "$id" ]; then echo "hung $(cut -d' ' -f5 /proc/$$/stat)" > "$S/hang.marker"; exec sleep 60; fi
        fail="$(awk -v i="$id" '$1==i{print $2}' "$S/store.fail" 2>/dev/null | head -n1)"
        if [ -n "$fail" ]; then echo "error: could not remove $id" >&2; exit "$fail"; fi
        grep -vx -- "$id" "$S/flatpak.$scope" > "$S/flatpak.$scope.new"; mv "$S/flatpak.$scope.new" "$S/flatpak.$scope"
        echo "Uninstalling $id"; exit 0 ;;
esac
echo "error: unexpected command $cmd" >&2; exit 1
EOF
    _stub snap <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
echo "snap $*" >> "$S/stores.log"
cmd="$1"; shift
name=""
for a in "$@"; do
    case "$a" in
        -*) echo "error: unknown flag $a" >&2; exit 1 ;;
        *) if [ -z "$name" ]; then name="$a"; else echo "error: too many arguments" >&2; exit 1; fi ;;
    esac
done
case "$cmd" in
    list)
        cat > /dev/null
        if grep -qx -- "$name" "$S/snap.list" 2>/dev/null; then echo "$name  1.0  1  latest/stable  pub  -"; exit 0; fi
        echo "error: no matching snaps installed" >&2; exit 1 ;;
    remove)
        grep -qx -- "$name" "$S/snap.list" 2>/dev/null || { echo "error: snap \"$name\" is not installed" >&2; exit 1; }
        cat "$HOME"/.local/state/mintapp-remover/removal-*.txt > "$S/during.$name.txt" 2>/dev/null
        printf '%s: %s\n' "$name" "$(grep -h '^# Status' "$S/during.$name.txt" 2>/dev/null | head -n1)" >> "$S/during.log"
        if [ "$(cat "$S/store.hang" 2>/dev/null)" = "$name" ]; then echo "hung $(cut -d' ' -f5 /proc/$$/stat)" > "$S/hang.marker"; exec sleep 60; fi
        fail="$(awk -v i="$name" '$1==i{print $2}' "$S/store.fail" 2>/dev/null | head -n1)"
        if [ -n "$fail" ]; then echo "error: cannot remove $name" >&2; exit "$fail"; fi
        grep -vx -- "$name" "$S/snap.list" > "$S/snap.list.new"; mv "$S/snap.list.new" "$S/snap.list"
        echo "$name removed"; exit 0 ;;
esac
echo "error: unexpected command $cmd" >&2; exit 1
EOF
    : > "$SB/state/stores.log"; : > "$SB/state/during.log"; : > "$SB/state/store.fail"
    : > "$SB/state/flatpak.system"; : > "$SB/state/flatpak.user"; : > "$SB/state/snap.list"; : > "$SB/state/flatpak.origin"
    sandbox_chown
}
stores_sandbox() { new_sandbox; stub_stores; }
fresh_stores() { fresh; stub_stores; }
# set_store LIST ID...: what is installed in that list (flatpak.system, flatpak.user or snap.list).
set_store() { local f="$1"; shift; printf '%s\n' "$@" > "$SB/state/$f"; sandbox_chown; }
stores_log() { cat "$SB/state/stores.log" 2>/dev/null || true; }
# count_log TEXT: how many calls of the stubs are exactly TEXT.
count_log() { local n; n="$(grep -cxF -- "$1" "$SB/state/stores.log" 2>/dev/null)" || n=0; printf '%s' "$n"; }
# stores_present: what is still installed, in one line.
stores_present() {
    printf 'fs=%s fu=%s sn=%s' "$(paste -sd, "$SB/state/flatpak.system")" "$(paste -sd, "$SB/state/flatpak.user")" \
        "$(paste -sd, "$SB/state/snap.list")"
}
# in_plan: the three kinds, installed, for the tests that follow.
FP_SYS=org.mozilla.firefox FP_USR=org.gnome.gedit SNAP_A=vlc
install_three() { set_store flatpak.system "$FP_SYS"; set_store flatpak.user "$FP_USR"; set_store snap.list "$SNAP_A"; }

echo "-- store_installed: each store is asked about its own application"
stores_sandbox; install_three
inst() {  # inst LINE: OUT = <<yes|no>> (invalid when the line does not parse)
    local code
    printf -v code 'parse_store_line %q || { printf "<<invalid>>"; exit; }; if store_installed; then printf "<<yes>>"; else printf "<<no>>"; fi' "$1"
    app_eval "$code"
}
inst 'flatpak system org.mozilla.firefox flathub'; value_of 'a Flatpak of the system that is installed' yes
inst 'flatpak user org.gnome.gedit';               value_of 'a Flatpak of the user that is installed' yes
inst 'snap system vlc';                            value_of 'a Snap that is installed' yes
inst 'flatpak user org.mozilla.firefox';           value_of 'installed for the system is not installed for the user' no
inst 'flatpak system org.gnome.gedit';             value_of 'installed for the user is not installed for the system' no
inst 'flatpak system org.not.installed';           value_of 'a Flatpak that is not installed' no
inst 'snap system gimp';                           value_of 'a Snap that is not installed' no
check_eq 'the Flatpak of the system is asked with --system' 1 "$(count_log 'flatpak info --system org.mozilla.firefox')"
check_eq 'the Flatpak of the user is asked with --user' 1 "$(count_log 'flatpak info --user org.gnome.gedit')"
check_eq 'the Snap is asked with snap list NAME' 1 "$(count_log 'snap list vlc')"
app_eval 'STORE_KIND=apt STORE_SCOPE=system STORE_ID=firefox; if store_installed; then printf "<<yes>>"; else printf "<<no>>"; fi'
value_of 'a kind that is neither Flatpak nor Snap is not installed' no
app_eval 'STORE_KIND="" STORE_SCOPE="" STORE_ID=""; if store_installed; then printf "<<yes>>"; else printf "<<no>>"; fi'
value_of 'nothing read by parse_store_line is not installed' no
app_eval 'parse_store_line "flatpak system org.mozilla.firefox"; if store_installed; then printf "<<yes>>"; else printf "<<no>>"; fi' PATH="$SB/emptybin"
value_of 'without the flatpak command it counts as not installed' no
app_eval 'parse_store_line "snap system vlc"; if store_installed; then printf "<<yes>>"; else printf "<<no>>"; fi' PATH="$SB/emptybin"
value_of 'without the snap command it counts as not installed' no
app_eval_in 'secret' 'parse_store_line "snap system vlc"; store_installed; parse_store_line "flatpak user org.gnome.gedit"; store_installed; read -r x; printf "<<%s>>" "$x"'
value_of 'the question to the store does not take the input of the program' secret

echo "-- store_make_plan: valid, installed, without repeats, sorted"
stores_sandbox; install_three
mk() {  # mk REQUEST: OUT = <<status|plan>>
    local code
    printf -v code 'STORE_PLAN=stale; store_make_plan %q; st=$?; printf "<<%%s|%%s>>" "$st" "$STORE_PLAN"' "$1"
    app_eval "$code"
}
ALL3=$'flatpak system org.mozilla.firefox flathub\nflatpak user org.gnome.gedit\nsnap system vlc'
mk $'snap system vlc\nflatpak user org.gnome.gedit\nflatpak system org.mozilla.firefox flathub'
value_of 'the plan is sorted, whatever the order of the request' "0|$ALL3"
mk $'flatpak system org.mozilla.firefox flathub\nsnap system gimp\nflatpak user org.gnome.gedit\nflatpak user org.nobody.Installed\nsnap system vlc'
value_of 'what is not installed is left out' "0|$ALL3"
: > "$SB/state/stores.log"
mk $'flatpak system -rf\napp system firefox\n\n   \nsnap user vlc\nflatpak system org.mozilla.firefox flathub\nsnap system vlc --purge\nflatpak system org.mozilla.firefox;ls'
value_of 'lines that are not valid are left out, blank ones too' '0|flatpak system org.mozilla.firefox flathub'
assert_not_contains 'what is not valid never reaches a command' "$(stores_log)" '-rf'
check_eq 'only the valid line was asked about' 1 "$(stores_log | wc -l)"
: > "$SB/state/stores.log"
mk $'flatpak system org.mozilla.firefox flathub\nflatpak system org.mozilla.firefox\nflatpak system org.mozilla.firefox other'
value_of 'a repeated application stays once, the first line' '0|flatpak system org.mozilla.firefox flathub'
check_eq 'and the store is asked once for it' 1 "$(count_log 'flatpak info --system org.mozilla.firefox')"
mk $'flatpak system org.mozilla.firefox\nflatpak system org.mozilla.firefox flathub'
value_of 'the first line stays, also when it has no remote' '0|flatpak system org.mozilla.firefox'
set_store flatpak.user org.mozilla.firefox org.gnome.gedit
mk $'flatpak system org.mozilla.firefox\nflatpak user org.mozilla.firefox'
value_of 'the same ID in the system and in the user is two applications' $'0|flatpak system org.mozilla.firefox\nflatpak user org.mozilla.firefox'
mk $'snap system gimp\nflatpak user org.nobody.Installed'
value_of 'nothing installed: it fails and the plan is empty (not the stale one)' '1|'
mk ''
value_of 'an empty request: it fails and the plan is empty' '1|'
mk $'flatpak system -rf\nsnap user vlc'
value_of 'nothing valid: it fails and the plan is empty' '1|'

echo "-- store_plan_fingerprint and store_plan_still_valid"
stores_sandbox; install_three
fpr() {  # fpr PLAN: the fingerprint of that plan
    local code
    printf -v code 'store_plan_fingerprint %q' "$1"
    app_eval "$code"
}
fpr $'snap system vlc\nflatpak user org.gnome.gedit'; A_FP="$OUT"
fpr $'flatpak user org.gnome.gedit\nsnap system vlc'; B_FP="$OUT"
check_eq 'the fingerprint does not depend on the order of the lines' "$A_FP" "$B_FP"
check_eq 'the fingerprint is a SHA-256 (64 hex digits)' yes "$([[ "$A_FP" =~ ^[0-9a-f]{64}$ ]] && echo yes || echo no)"
fpr $'flatpak user org.gnome.gedit\nsnap system vlc\nsnap system gimp'
check_eq 'one more application changes it' no "$([ "$OUT" = "$A_FP" ] && echo yes || echo no)"
fpr 'flatpak user org.gnome.gedit'
check_eq 'one application less changes it' no "$([ "$OUT" = "$A_FP" ] && echo yes || echo no)"
fpr $'flatpak system org.mozilla.firefox flathub'; A_FP="$OUT"
fpr $'flatpak system org.mozilla.firefox other'
check_eq 'another remote changes it' no "$([ "$OUT" = "$A_FP" ] && echo yes || echo no)"

REQ3=$'flatpak system org.mozilla.firefox flathub\nflatpak user org.gnome.gedit\nsnap system vlc'
valid() {  # valid MUTATION: plans REQ3, runs MUTATION (shell code; $ST is the state folder), checks again: <<status|new plan>>
    local code
    printf -v code 'store_make_plan %q; plan="$STORE_PLAN"; %s; store_plan_still_valid "$plan" %q; st=$?; printf "<<%%s|%%s>>" "$st" "$STORE_PLAN"' \
        "$REQ3" "$1" "$REQ3"
    app_eval "$code" ST="$SB/state"
}
stores_sandbox; install_three
valid ':'
value_of 'nothing changed: still valid, and the new plan is left in STORE_PLAN' "0|$ALL3"
install_three
valid ': > "$ST/snap.list"'
value_of 'an application removed after the confirmation: not valid' $'1|flatpak system org.mozilla.firefox flathub\nflatpak user org.gnome.gedit'
install_three; set_store snap.list ''
valid 'echo vlc > "$ST/snap.list"'
value_of 'an application installed after the confirmation: not valid either (the plan grew)' "1|$ALL3"
install_three
valid ': > "$ST/flatpak.system"; : > "$ST/flatpak.user"; : > "$ST/snap.list"'
value_of 'everything removed after the confirmation: not valid, empty plan' '1|'

echo "-- store_plan_text: one line per application"
stores_sandbox
ptext() {  # ptext PLAN [VAR=val ...]: OUT = <<the text>>
    local plan="$1" code; shift
    printf -v code 'printf "<<%%s>>" "$(store_plan_text %q)"' "$plan"
    app_eval "$code" "$@"
}
ptext "$ALL3" MINTAPP_LANG=en
value_of 'English: kind, identifier, scope and remote' $'  Flatpak: org.mozilla.firefox (system-wide, flathub)\n  Flatpak: org.gnome.gedit (your user only)\n  Snap: vlc (system-wide)'
ptext "$ALL3" MINTAPP_LANG=es
value_of 'Spanish: the same, with the scope in Spanish' $'  Flatpak: org.mozilla.firefox (todo el sistema, flathub)\n  Flatpak: org.gnome.gedit (solo tu usuario)\n  Snap: vlc (todo el sistema)'
ptext $'flatpak user -rf\nsnap system vlc\n\napp system x' MINTAPP_LANG=en
value_of 'lines that are not valid and blank ones are left out of the text' $'  Snap: vlc (system-wide)'
ptext '' MINTAPP_LANG=en
value_of 'an empty plan gives an empty text' ''

echo "-- store_plan_needs_priv: which plans ask for administrator rights"
stores_sandbox
needs() {  # needs PLAN: OUT = <<yes|no>>
    local code
    printf -v code 'if store_plan_needs_priv %q; then printf "<<yes>>"; else printf "<<no>>"; fi' "$1"
    app_eval "$code"
}
needs 'flatpak user org.gnome.gedit';                                    value_of 'a Flatpak of the user: no rights' no
needs $'flatpak user org.gnome.gedit\nflatpak user org.a.b.c';           value_of 'only Flatpaks of the user: no rights' no
needs 'flatpak system org.mozilla.firefox flathub';                      value_of 'a Flatpak of the system: rights' yes
needs 'snap system vlc';                                                 value_of 'a Snap: rights' yes
needs $'flatpak user org.gnome.gedit\nsnap system vlc';                  value_of 'a Snap among Flatpaks of the user: rights' yes
needs $'flatpak user org.gnome.gedit\nflatpak system org.a.b.c\nflatpak user org.d.e.f'; value_of 'one Flatpak of the system anywhere in the plan: rights' yes
needs '';                                                                value_of 'an empty plan: no rights' no
needs $'flatpak user -rf\nflatpak user org.gnome.gedit';                 value_of 'lines that are not valid are ignored' no

echo "-- store_uninstall_cmd: the command line of each store"
stores_sandbox; install_three
ucmd() {  # ucmd LINE [VAR=val ...]: store_uninstall_cmd for that plan line: OUT = <<status>>
    local line="$1" code; shift
    printf -v code 'parse_store_line %q || exit; store_uninstall_cmd; printf "<<%%s>>" "$?"' "$line"
    app_eval "$code" "$@"
}
ucmd 'flatpak system org.mozilla.firefox flathub'
value_of 'a Flatpak of the system: status 0' 0
check_eq 'it goes through the privilege command with these options' \
    'sudo flatpak uninstall --system --noninteractive -y org.mozilla.firefox' "$(sudo_log)"
check_eq 'and nothing else is called' 'flatpak uninstall --system --noninteractive -y org.mozilla.firefox' "$(stores_log)"
check_eq 'that Flatpak is gone, the rest stays' 'fs= fu=org.gnome.gedit sn=vlc' "$(stores_present)"
: > "$SB/state/sudo.log"; : > "$SB/state/stores.log"
ucmd 'flatpak user org.gnome.gedit'
value_of 'a Flatpak of the user: status 0' 0
check_eq 'it does not use the privilege command' '' "$(sudo_log)"
check_eq 'its command line' 'flatpak uninstall --user --noninteractive -y org.gnome.gedit' "$(stores_log)"
: > "$SB/state/sudo.log"; : > "$SB/state/stores.log"
ucmd 'snap system vlc'
value_of 'a Snap: status 0' 0
check_eq 'it goes through the privilege command' 'sudo snap remove vlc' "$(sudo_log)"
check_eq 'its command line has the name and nothing else' 'snap remove vlc' "$(stores_log)"
check_eq 'everything is gone' 'fs= fu= sn=' "$(stores_present)"
install_three; printf 'vlc 4\norg.gnome.gedit 6\n' > "$SB/state/store.fail"; sandbox_chown
ucmd 'snap system vlc';              value_of 'a Snap that fails: its status is passed on' 4
ucmd 'flatpak user org.gnome.gedit'; value_of 'a Flatpak that fails: its status is passed on' 6
ucmd 'snap system gimp';             value_of 'an application that is not there: the status of the store (1)' 1
: > "$SB/state/sudo.log"; : > "$SB/state/stores.log"
app_eval 'STORE_KIND=apt STORE_SCOPE=system STORE_ID=firefox; store_uninstall_cmd; printf "<<%s>>" "$?"'
value_of 'a kind that is not Flatpak or Snap: status 2' 2
check_eq 'and no command is run' '' "$(sudo_log)$(stores_log)"
install_three; : > "$SB/state/store.fail"; : > "$SB/state/stores.log"; : > "$SB/state/sudo.log"
ucmd 'flatpak system org.mozilla.firefox'; ucmd 'snap system vlc'; ucmd 'flatpak user org.gnome.gedit'
assert_not_contains 'the data of a Flatpak is never deleted' "$(stores_log)" 'delete-data'
assert_not_contains 'a Snap is not removed with --purge' "$(stores_log)" 'purge'
fresh_stores; install_three
ge 'UI_ENGINE=gui; parse_store_line "snap system vlc"; store_uninstall_cmd; printf "<<%s>>" "$?"'
value_of 'in windows: the Snap is removed too' 0
check_eq 'in windows the password is asked with -A' 'sudo -A snap remove vlc' "$(sudo_log)"

echo "-- execute_store_removal: the whole plan, one at a time, with its record"
EXEC_CODE=$(cat <<'EOF'
execute_store_removal "$plan"; st=$?
nl=$'\n'; f="${STORE_FAILED//$nl/;}"
printf "<<%s|%s|%s|%s|%s>>" "$st" "$STORE_TOTAL" "$STORE_FAILED_N" "$f" "${LAST_RECORD:+rec}"
EOF
)
# run_exec PLAN [VAR=val ...]: OUT = ...<<status|applications tried|failed|failed lines (joined by ;)|rec if the record was written>>
run_exec() {
    local plan="$1" code; shift
    printf -v code 'plan=%q; %s' "$plan" "$EXEC_CODE"
    app_eval "$code" "$@"
}
rec_file() { state_files | head -n1; }
stores_sandbox; install_three
run_exec "$ALL3"
value_of 'all removed: status 0, three tried, none failed, the record written' '0|3|0||rec'
check_eq 'the three applications are gone' 'fs= fu= sn=' "$(stores_present)"
check_eq 'one record was written' 1 "$(state_files | wc -l)"
check_eq 'the record is the completed one, with its plan and hints' "$EXPECTED" "$(body "$(rec_file)")"
check_eq 'the commands ran in the order of the plan' $'flatpak uninstall --system --noninteractive -y org.mozilla.firefox\nflatpak uninstall --user --noninteractive -y org.gnome.gedit\nsnap remove vlc' "$(stores_log)"
check_eq 'the privilege command was used for the system Flatpak and the Snap only' \
    $'sudo flatpak uninstall --system --noninteractive -y org.mozilla.firefox\nsudo snap remove vlc' "$(sudo_log)"
check_eq 'each removal started with the record already on disk as "started"' \
    $'org.mozilla.firefox: # Status: started\norg.gnome.gedit: # Status: started\nvlc: # Status: started' "$(cat "$SB/state/during.log")"
assert_contains 'that record already listed the whole plan' "$(cat "$SB/state/during.org.mozilla.firefox.txt")" 'snap system vlc'
assert_contains 'and the output of the commands is on the terminal' "$OUT" 'Uninstalling org.mozilla.firefox'
check_eq 'no temporary file is left' 0 "$(find "$SB/home" -name '.tmp.*' | wc -l)"
check_eq 'the record is private (mode 600)' 600 "$(stat -c '%a' "$(rec_file)")"

stores_sandbox; install_three
printf 'org.gnome.gedit 4\n' > "$SB/state/store.fail"; sandbox_chown
run_exec "$ALL3"
value_of 'one fails: its status, three tried, one failed, its line given' '4|3|1|flatpak user org.gnome.gedit|rec'
check_eq 'the others were removed all the same' 'fs= fu=org.gnome.gedit sn=' "$(stores_present)"
check_eq 'the record says how many were not removed' '# Status: failed (1 of 3 applications not removed)' "$(grep '^# Status' "$(rec_file)")"
assert_contains 'the failed one is listed as not removed' "$(cat "$(rec_file)")" $'# Not removed (the command failed):\nflatpak user org.gnome.gedit\n'
assert_not_contains 'and it has no reinstall hint (it is still installed)' "$(cat "$(rec_file)")" '# flatpak install --user org.gnome.gedit'
assert_contains 'the ones removed keep their hint' "$(cat "$(rec_file)")" '# sudo snap install vlc'

stores_sandbox; install_three
printf 'vlc 6\norg.mozilla.firefox 5\n' > "$SB/state/store.fail"; sandbox_chown
run_exec "$ALL3"
value_of 'two fail: the status of the first in the plan, not the last or the highest' '5|3|2|flatpak system org.mozilla.firefox flathub;snap system vlc|rec'
check_eq 'the one that does not fail was removed after the first failure' 'fs=org.mozilla.firefox fu= sn=vlc' "$(stores_present)"
check_eq 'every application was tried' 3 "$(stores_log | grep -c 'uninstall\|remove')"

stores_sandbox; install_three
printf 'org.mozilla.firefox 7\norg.gnome.gedit 7\nvlc 7\n' > "$SB/state/store.fail"; sandbox_chown
run_exec "$ALL3"
value_of 'all fail' '7|3|3|flatpak system org.mozilla.firefox flathub;flatpak user org.gnome.gedit;snap system vlc|rec'
check_eq 'the record says all three failed' '# Status: failed (3 of 3 applications not removed)' "$(grep '^# Status' "$(rec_file)")"
assert_not_contains 'the record has no reinstall section' "$(cat "$(rec_file)")" 'To reinstall'

stores_sandbox; install_three
run_exec 'flatpak user org.gnome.gedit'
value_of 'only a Flatpak of the user: it works' '0|1|0||rec'
check_eq 'it never calls the privilege command' '' "$(sudo_log)"

echo "-- execute_store_removal: the run in progress, and a record that cannot be written"
stores_sandbox; install_three
app_eval 'store_run_step() { if [ "$ACTIVE_RECORD" = "$LAST_RECORD" ] && [ -n "$ACTIVE_RECORD" ] && [ "$ACTIVE_STORE" = 1 ] && [ "$ACTIVE_PLAN" = "$plan" ]; then printf "ok "; else printf "bad "; fi; return 0; }
    plan=$(printf "flatpak user org.a.b.c\nsnap system vlc"); execute_store_removal "$plan"; printf "<<%s|%s|%s>>" "$?" "$ACTIVE_RECORD" "$ACTIVE_STORE"'
assert_contains 'during each step the run in progress is the one on_exit would record' "$OUT" 'ok ok <<0||0>>'
stores_sandbox; install_three
: > "$SB/home/.local"; sandbox_chown
run_exec "$ALL3"
value_of 'no place for the record: the removal runs all the same, with no record' '0|3|0||'
check_eq 'the applications were removed' 'fs= fu= sn=' "$(stores_present)"
stores_sandbox; install_three
app_eval 'eval "$(declare -f write_store_record | sed "1s/write_store_record/first_write_store_record/")"
    write_store_record() { if [ "$2" = started ]; then first_write_store_record "$@"; else return 1; fi; }
    plan=$(printf "snap system vlc"); execute_store_removal "$plan"; printf "<<%s|%s>>" "$?" "${LAST_RECORD:+rec}"'
value_of 'the final record cannot be written: the removal is done and there is no record to point to' '0|'
stores_sandbox; install_three
mkdir -p "$SB/pb-doas"; printf '#!/bin/sh\nexec "$@"\n' > "$SB/pb-doas/doas"; chmod +x "$SB/pb-doas/doas"; sandbox_chown
run_exec 'snap system vlc' MINTAPP_SUDO="$SB/pb-doas/doas"
value_of 'with doas the removal works' '0|1|0||rec'
assert_contains 'with doas the hint of the record written before the removal already says doas' "$(cat "$SB/state/during.vlc.txt")" '# doas snap install vlc'
assert_not_contains 'and it never says sudo' "$(cat "$SB/state/during.vlc.txt")" 'sudo'

echo "-- execute_store_removal in windows: the password comes first"
fresh_stores; install_three; fake_sudo_password secret
fake_zenity CANCEL
ge 'UI_ENGINE=gui; '"$EXEC_CODE" plan="$ALL3"
value_of 'password window closed: status 77, nothing tried, nothing failed, no record' '77|0|0||'
check_eq 'nothing was removed' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc' "$(stores_present)"
check_eq 'no store command was called' '' "$(stores_log)"
check_eq 'no record was written' 0 "$(state_files | wc -l)"
fresh_stores; install_three; fake_sudo_password secret
fake_zenity 'OUT:wrong' 'OUT:wrong' 'OUT:wrong'
ge 'UI_ENGINE=gui; '"$EXEC_CODE" plan="$ALL3"
value_of 'wrong password three times: status 77, nothing was run or recorded' '77|0|0||'
check_eq 'a wrong password removed nothing and wrote nothing' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc|0' "$(stores_present)|$(state_files | wc -l)"
fresh_stores; install_three; fake_sudo_password secret
fake_zenity 'OUT:secret'
ge 'UI_ENGINE=gui; '"$EXEC_CODE" plan="$ALL3"
value_of 'the right password: everything is removed' '0|3|0||rec'
check_eq 'the password was asked once for the three' 'secret' "$(sudo_given)"
check_eq 'the three are gone' 'fs= fu= sn=' "$(stores_present)"
fresh_stores; install_three; fake_sudo_password secret
fake_zenity CANCEL
ge 'UI_ENGINE=gui; '"$EXEC_CODE" plan='flatpak user org.gnome.gedit'
value_of 'only a Flatpak of the user: no password is asked and it is removed' '0|1|0||rec'
check_eq 'the password helper was never used' '' "$(sudo_given)$(sudo_log)"

echo "-- store_error_text: why a removal failed"
stores_sandbox
etext() {  # etext STATUS ENGINE [VAR=val ...]: OUT = <<the text>> for 1 failure of 3 and the tail "line1/line2"
    local st="$1" engine="$2" code; shift 2
    printf -v code 'UI_ENGINE=%s; STORE_TOTAL=3 STORE_FAILED_N=1 STORE_FAILURE_TAIL=$"line1\nline2"; store_error_text %s; printf "<<%%s>>" "$REPLY"' "$engine" "$st"
    app_eval "$code" "$@"
}
etext 4 text MINTAPP_LANG=en
value_of 'terminal: how many failed, the exit code and a pointer to the terminal' $'Uninstalls that failed: 1 of 3 (exit code 4).\n\nCheck the flatpak or snap output above in the terminal.'
etext 4 gui MINTAPP_LANG=en
value_of 'windows: the same, with the last lines of the output instead of the pointer' $'Uninstalls that failed: 1 of 3 (exit code 4).\n\nLast lines of the output:\nline1\nline2'
etext 77 text MINTAPP_LANG=en
value_of 'no rights: only the message about the rights (terminal)' 'Administrator rights were not obtained (the password was cancelled or wrong, or your user is not allowed to get them). Nothing was uninstalled.'
etext 77 gui MINTAPP_LANG=en
value_of 'no rights: the same in windows' 'Administrator rights were not obtained (the password was cancelled or wrong, or your user is not allowed to get them). Nothing was uninstalled.'
etext 4 text MINTAPP_LANG=es MINTAPP_ASCII=0
value_of 'Spanish, terminal' $'Desinstalaciones fallidas: 1 de 3 (código de salida 4).\n\nRevisa el mensaje de flatpak o snap más arriba en la terminal.'
etext 4 gui MINTAPP_LANG=es MINTAPP_ASCII=0
value_of 'Spanish, windows' $'Desinstalaciones fallidas: 1 de 3 (código de salida 4).\n\nÚltimas líneas de la salida:\nline1\nline2'

echo "-- confirm_and_remove_stores in text mode"
plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }
# flow_text INPUT [VAR=val ...]: the flow for ALL3 in text mode (no whiptail), INPUT on stdin; OUT ends with <<status>>.
flow_text() {
    local input="$1"; shift
    app_eval_in "$input" 'UI_ENGINE=text; HAVE_WHIPTAIL=0; confirm_and_remove_stores "$REQ"; printf "<<%s>>" "$?"' REQ="$ALL3" MINTAPP_LANG=en "$@"
}
# status_of_flow: the number between the last << and >> of OUT.
status_of_flow() { local v="${OUT##*<<}"; printf '%s' "${v%%>>*}"; }
# position TEXT NEEDLE: where NEEDLE starts in TEXT (the length of what comes before; -1 if absent).
position() { local before="${1%%"$2"*}"; if [ "$before" = "$1" ]; then echo -1; else echo "${#before}"; fi; }
# in_order LABEL TEXT A B C...: each text comes after the previous one.
in_order() {
    local label="$1" text="$2" prev=-1 cur ok=yes n; shift 2
    for n in "$@"; do
        cur="$(position "$text" "$n")"
        if [ "$cur" -le "$prev" ]; then ok="no (\"$n\" at $cur, after $prev)"; fi
        prev="$cur"
    done
    check_eq "$label" yes "$ok"
}
removal_calls() { stores_log | grep -cE '^(flatpak uninstall|snap remove)' || true; }

stores_sandbox; install_three
flow_text $'y\n\n'
P="$(plain)"
check_eq 'yes: the flow ends well (status 0)' 0 "$(status_of_flow)"
check_eq 'yes: the three applications are gone' 'fs= fu= sn=' "$(stores_present)"
in_order 'yes: the notice, the plan, the removal and the result come in that order' "$P" \
    'Preparing the uninstallation plan (nothing will be removed yet)...' \
    'This is the plan to uninstall Flatpak and Snap applications.' \
    '  Flatpak: org.mozilla.firefox (system-wide, flathub)' 'Uninstalling org.mozilla.firefox...' \
    'Uninstalling org.gnome.gedit...' 'Uninstalling vlc...' 'Uninstallation completed successfully.' \
    'A record of what was removed was saved to:'
assert_contains 'yes: the plan lists the Flatpak of the user and the Snap' "$P" $'  Flatpak: org.gnome.gedit (your user only)\n  Snap: vlc (system-wide)'
assert_not_contains 'yes: the plan does not talk about packages' "$P" 'packages'
check_eq 'yes: one record, the completed one' '# Status: completed|1' "$(grep '^# Status' "$(rec_file)")|$(state_files | wc -l)"
check_eq 'yes: each application was asked twice (the plan and the check before removing), then one removal each' '6|3' "$(stores_log | grep -c ' info \| list ')|$(removal_calls)"

stores_sandbox; install_three
flow_text $'n\n\n'
P="$(plain)"
check_eq 'no: the status is 1' 1 "$(status_of_flow)"
assert_contains 'no: it says the operation was cancelled' "$P" 'Operation cancelled.'
check_eq 'no: nothing was removed' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc' "$(stores_present)"
check_eq 'no: no command of removal, no privilege command, no record' '0|0|0' "$(removal_calls)|$(sudo_log | wc -l)|$(state_files | wc -l)"
assert_not_contains 'no: it never says it uninstalled' "$P" 'Uninstalling org'
stores_sandbox; install_three
flow_text $'\n\n'
check_eq 'an empty answer is a no' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc|0' "$(stores_present)|$(removal_calls)"
stores_sandbox; install_three
flow_text ''
check_eq 'end of input at the question is a no' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc|0' "$(stores_present)|$(removal_calls)"
stores_sandbox; install_three
flow_text $'maybe\n\n'
assert_contains 'an answer that is neither yes nor no is reported' "$(plain)" 'not recognized'
check_eq 'and removes nothing' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc|0' "$(stores_present)|$(removal_calls)"
for yes in yes Y SI sí; do
    stores_sandbox; install_three
    flow_text "$yes"$'\n\n'
    check_eq "the answer \"$yes\" is a yes" 'fs= fu= sn=' "$(stores_present)"
done

stores_sandbox; install_three
flow_text $'y\n\n' MINTAPP_LANG=es MINTAPP_ASCII=0
P="$(plain)"
in_order 'Spanish: the notice, the plan and the result' "$P" 'Preparando el plan de desinstalación (todavía no se borra nada)...' \
    'Este es el plan de desinstalación de Flatpak y Snap.' '  Flatpak: org.mozilla.firefox (todo el sistema, flathub)' \
    'Desinstalando vlc...' 'Desinstalación completada.' 'Se guardó un registro de lo eliminado en:'

stores_sandbox; install_three
app_eval_in $'\n' 'UI_ENGINE=text; HAVE_WHIPTAIL=0; confirm_and_remove_stores ""; printf "<<%s>>" "$?"' MINTAPP_LANG=en
assert_contains 'an empty request is reported' "$(plain)" 'No applications were selected.'
check_eq 'an empty request calls no store at all' '' "$(stores_log)"
app_eval_in $'\n' 'UI_ENGINE=text; HAVE_WHIPTAIL=0; confirm_and_remove_stores "$REQ"' REQ=$'  \n\t\n' MINTAPP_LANG=en
assert_contains 'a request of blanks is reported the same' "$(plain)" 'No applications were selected.'
check_eq 'a request of blanks calls no store either' '' "$(stores_log)"

stores_sandbox; install_three
flow_text $'\n' REQ=$'snap system gimp\nflatpak user org.nobody.Installed'
assert_contains 'nothing installed any more: it is reported' "$(plain)" 'The selected applications are no longer installed.'
check_eq 'nothing installed any more: no removal, no question, no record' '0|0' "$(removal_calls)|$(state_files | wc -l)"
assert_not_contains 'nothing installed any more: the plan is not shown' "$(plain)" 'This is the plan'

stores_sandbox; install_three
flow_text $'y\n\n' REQ=$'flatpak system -rf\nsnap system gimp\nsnap system vlc\nflatpak user org.gnome.gedit;ls\nsnap system vlc'
P="$(plain)"
assert_contains 'what is not valid or not installed is not in the plan' "$P" $'the package manager is not involved:\n\n  Snap: vlc (system-wide)\n'
check_eq 'only the valid, installed application is removed, once' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=|1' "$(stores_present)|$(removal_calls)"
assert_not_contains 'what is not valid never reaches a command' "$(stores_log)" '-rf'

stores_sandbox; install_three
app_eval_in $'y\n\n' 'review_store_plan() { : > "$ST/snap.list"; return 0; }; UI_ENGINE=text; HAVE_WHIPTAIL=0; confirm_and_remove_stores "$REQ"; printf "<<%s>>" "$?"' \
    REQ="$ALL3" ST="$SB/state" MINTAPP_LANG=en
assert_contains 'the system changes after the confirmation: it says so' "$(plain)" 'The system changed after the plan was calculated, so nothing was removed.'
check_eq 'the system changes after the confirmation: nothing is removed or recorded' '0|0|0' "$(removal_calls)|$(state_files | wc -l)|$(sudo_log | wc -l)"
check_eq 'the other applications are still there' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=' "$(stores_present)"

stores_sandbox; install_three; printf 'vlc 4\n' > "$SB/state/store.fail"; sandbox_chown
flow_text $'y\n\n'
P="$(plain)"
check_eq 'a failure: the status of the failed command' 4 "$(status_of_flow)"
assert_contains 'a failure: how many failed and the exit code' "$P" 'Uninstalls that failed: 1 of 3 (exit code 4).'
assert_contains 'a failure: it points to the output above' "$P" 'Check the flatpak or snap output above in the terminal.'
assert_contains 'a failure: the output of the command is above, on the terminal' "$P" 'error: cannot remove vlc'
assert_not_contains 'a failure: no success message' "$P" 'completed successfully'
assert_contains 'a failure: the record is still pointed to' "$P" 'A record of what was removed was saved to:'
check_eq 'a failure: the others were removed' 'fs= fu= sn=vlc' "$(stores_present)"
check_eq 'a failure: the record says so' '# Status: failed (1 of 3 applications not removed)' "$(grep '^# Status' "$(rec_file)")"
stores_sandbox; install_three; printf 'vlc 4\n' > "$SB/state/store.fail"; sandbox_chown
flow_text $'y\n\n' MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'a failure in Spanish' "$(plain)" 'Desinstalaciones fallidas: 1 de 3 (código de salida 4).'

stores_sandbox; install_three; : > "$SB/home/.local"; sandbox_chown
flow_text $'y\n\n'
P="$(plain)"
check_eq 'no place for the record: the removal is done' 'fs= fu= sn=' "$(stores_present)"
assert_contains 'no place for the record: it warns that it could not be saved' "$P" 'Warning: the removal record could not be saved.'
assert_contains 'no place for the record: the result is still a success' "$P" 'Uninstallation completed successfully.'

echo "-- confirm_and_remove_stores in whiptail"
# The same flow with the boxes of whiptail (stub): the plan, the question that starts on Cancel, the
# result. wt_flow ANSWER...: what the stub answers, one per box (OK or YES, NO, ESC; when they run
# out it is Esc). REQ is WT_REQ and the language WT_LANG; OUT ends with <<status>>.
WT_REQ="$ALL3" WT_LANG=en
wt_flow() {
    fake_answers "$@"
    app_eval 'UI_ENGINE=whiptail; HAVE_WHIPTAIL=1; confirm_and_remove_stores "$REQ"; printf "<<%s>>" "$?"' \
        REQ="$WT_REQ" MINTAPP_LANG="$WT_LANG" MINTAPP_ASCII=0
}
wt_calls() { grep -c '^@@END@@$' "$SB/state/whiptail.args" || true; }
# wt_nth N: the N-th call to whiptail, as it was logged (the text of a box wrapped as whiptail got it).
wt_nth() { awk -v want="$1" '/^whiptail /{n++} n==want' "$SB/state/whiptail.log"; }
wt_all() { cat "$SB/state/whiptail.log"; }
UNTOUCHED='fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc'

stores_sandbox; install_three
wt_flow OK YES OK
P="$(plain)"
check_eq 'whiptail, yes: the flow ends well (status 0)' 0 "$(status_of_flow)"
check_eq 'whiptail, yes: the three applications are gone' 'fs= fu= sn=' "$(stores_present)"
check_eq 'whiptail, yes: three boxes, in this order: the plan, the question, the result' \
    '3|--msgbox|--yesno|--msgbox' \
    "$(wt_calls)|$(wt_nth 1 | grep -o -m1 -e '--msgbox' -e '--yesno')|$(wt_nth 2 | grep -o -m1 -e '--msgbox' -e '--yesno')|$(wt_nth 3 | grep -o -m1 -e '--msgbox' -e '--yesno')"
assert_contains 'whiptail, yes: the first box introduces the plan' "$(wt_nth 1)" '--msgbox This is the plan to uninstall Flatpak and Snap applications.'
assert_contains 'whiptail, yes: and lists the three applications, one per line' "$(wt_nth 1)" \
    $'  Flatpak: org.mozilla.firefox (system-wide, flathub)\n  Flatpak: org.gnome.gedit (your user only)\n  Snap: vlc (system-wide)'
assert_not_contains 'whiptail, yes: the plan does not talk about packages' "$(wt_nth 1)" 'packages'
assert_contains 'whiptail, yes: the question starts on Cancel' "$(wt_nth 2)" '--defaultno'
assert_contains 'whiptail, yes: its buttons say what they do' "$(wt_nth 2)" '--yes-button Uninstall --no-button Cancel --yesno'
assert_contains 'whiptail, yes: and it asks about these applications' "$(wt_nth 2)" 'Do you want to continue uninstalling these applications?'
assert_contains 'whiptail, yes: the last box says it went well' "$(wt_nth 3)" '--msgbox Uninstallation completed successfully.'
assert_contains 'whiptail, yes: and points to the record' "$(wt_nth 3)" 'A record of what was removed was saved to:'
assert_not_contains 'whiptail, yes: no literal "\n" reaches a box' "$(wt_all)" '\n'
assert_contains 'whiptail, yes: the removals show on the terminal, one line each' "$P" $'Uninstalling org.mozilla.firefox...\nUninstalling org.mozilla.firefox\nUninstalling org.gnome.gedit...'
check_eq 'whiptail, yes: one record, the completed one' '# Status: completed|1' "$(grep '^# Status' "$(rec_file)")|$(state_files | wc -l)"
check_eq 'whiptail, yes: the privilege command asks on the terminal (no -A)' \
    $'sudo flatpak uninstall --system --noninteractive -y org.mozilla.firefox\nsudo snap remove vlc' "$(sudo_log)"
check_eq 'whiptail, yes: no window of zenity' 0 "$(zenity_calls)"

stores_sandbox; install_three
wt_flow OK NO
check_eq 'whiptail, no: the status is 1' 1 "$(status_of_flow)"
check_eq 'whiptail, no: only the plan and the question were shown' 2 "$(wt_calls)"
check_eq 'whiptail, no: nothing was removed' "$UNTOUCHED" "$(stores_present)"
check_eq 'whiptail, no: no removal, no privilege command, no record' '0|0|0' "$(removal_calls)|$(sudo_log | wc -l)|$(state_files | wc -l)"
assert_not_contains 'whiptail, no: it never says it uninstalled' "$(plain)" 'Uninstalling org'

stores_sandbox; install_three
wt_flow OK ESC
check_eq 'whiptail, Esc at the question: status 255' 255 "$(status_of_flow)"
check_eq 'whiptail, Esc at the question: nothing removed, nothing recorded' "$UNTOUCHED|0|0" "$(stores_present)|$(removal_calls)|$(state_files | wc -l)"
stores_sandbox; install_three
wt_flow OK
check_eq 'whiptail, a question nobody answers is an Esc: nothing removed' "$UNTOUCHED|0" "$(stores_present)|$(removal_calls)"
stores_sandbox; install_three
wt_flow ESC NO
check_eq 'whiptail, Esc on the plan box: the question is still asked, and no ends it' '2|1' "$(wt_calls)|$(status_of_flow)"
check_eq 'whiptail, Esc on the plan box: nothing removed' "$UNTOUCHED" "$(stores_present)"

stores_sandbox; install_three
WT_LANG=es wt_flow OK YES OK
check_eq 'whiptail, Spanish: the flow ends well and the three are gone' '0|fs= fu= sn=' "$(status_of_flow)|$(stores_present)"
assert_contains 'whiptail, Spanish: the plan' "$(wt_nth 1)" $'--msgbox Este es el plan de desinstalación de Flatpak y Snap.'
assert_contains 'whiptail, Spanish: with the scope in Spanish' "$(wt_nth 1)" '  Flatpak: org.gnome.gedit (solo tu usuario)'
assert_contains 'whiptail, Spanish: the question starts on Cancel with its buttons' "$(wt_nth 2)" '--defaultno --yes-button Desinstalar --no-button Cancelar --yesno'
assert_contains 'whiptail, Spanish: the result' "$(wt_nth 3)" '--msgbox Desinstalación completada.'

stores_sandbox; install_three; printf 'vlc 4\n' > "$SB/state/store.fail"; sandbox_chown
wt_flow OK YES OK
check_eq 'whiptail, a failure: the status of the failed command' 4 "$(status_of_flow)"
check_eq 'whiptail, a failure: the others were removed' 'fs= fu= sn=vlc' "$(stores_present)"
assert_contains 'whiptail, a failure: the result box says how many failed' "$(wt_nth 3)" '--msgbox Uninstalls that failed: 1 of 3 (exit code 4).'
assert_contains 'whiptail, a failure: and where to read why' "$(wt_nth 3)" 'Check the flatpak or snap output above in the terminal.'
assert_not_contains 'whiptail, a failure: no success message' "$(wt_nth 3)" 'completed successfully'
assert_contains 'whiptail, a failure: the record is still pointed to' "$(wt_nth 3)" 'A record of what was removed was saved to:'
assert_contains 'whiptail, a failure: the output of the command is on the terminal' "$(plain)" 'error: cannot remove vlc'

stores_sandbox; install_three
WT_REQ='' wt_flow OK
check_eq 'whiptail, an empty request: one box, status 0' '1|0' "$(wt_calls)|$(status_of_flow)"
assert_contains 'whiptail, an empty request: it says nothing was selected' "$(wt_nth 1)" '--msgbox No applications were selected.'
check_eq 'whiptail, an empty request: no store is called' '' "$(stores_log)"
stores_sandbox; install_three
WT_REQ=$'snap system gimp\nflatpak user org.nobody.Installed' wt_flow OK
check_eq 'whiptail, nothing installed any more: one box and no question' '1' "$(wt_calls)"
assert_contains 'whiptail, nothing installed any more: it says so' "$(wt_nth 1)" 'The selected applications are no longer installed.'
check_eq 'whiptail, nothing installed any more: no removal, no record' '0|0' "$(removal_calls)|$(state_files | wc -l)"

stores_sandbox; install_three
fake_answers OK
app_eval 'review_store_plan() { : > "$ST/snap.list"; return 0; }; UI_ENGINE=whiptail; HAVE_WHIPTAIL=1; confirm_and_remove_stores "$REQ"; printf "<<%s>>" "$?"' \
    REQ="$ALL3" ST="$SB/state" MINTAPP_LANG=en
assert_contains 'whiptail, the system changes after the confirmation: a box says so' "$(wt_nth 1)" 'The system changed after the plan'
check_eq 'whiptail, the system changes after the confirmation: nothing removed or recorded' '0|0|0' "$(removal_calls)|$(state_files | wc -l)|$(sudo_log | wc -l)"

stores_sandbox; install_three
WT_REQ=$'flatpak system -rf\nsnap system gimp\nsnap system vlc\nflatpak user org.gnome.gedit;ls\nsnap system vlc' wt_flow OK YES OK
assert_contains 'whiptail, what is not valid or not installed is not in the plan' "$(wt_nth 1)" $'the package manager is not involved:\n\n  Snap: vlc (system-wide)'
assert_not_contains 'whiptail, what is not valid never reaches a box' "$(wt_all)" '-rf'
check_eq 'whiptail, only the valid, installed application is removed, once' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=|1' "$(stores_present)|$(removal_calls)"

echo "-- confirm_and_remove_stores in windows"
# The same flow with the windows of zenity (stub): the plan, the question that starts on Cancel, the
# password (only if a Flatpak of the system or a Snap is in the plan), a progress window per
# application and the result. win_flow ANSWER...: what the stub answers, one per window that asks
# (OK, CANCEL, OUT:text; the progress windows take none); REQ is WT_REQ and the language WT_LANG;
# OUT ends with <<status>>.
win_flow() {
    fake_zenity "$@"
    ge 'UI_ENGINE=gui; HAVE_WHIPTAIL=1; confirm_and_remove_stores "$REQ"; printf "<<%s>>" "$?"' REQ="$WT_REQ" MINTAPP_LANG="$WT_LANG"
}
# zkinds: the kind of every window, in order, joined by commas. zt N: the N-th window as text, with real line breaks.
zkinds() {
    local i n out=""
    n="$(zenity_calls)"
    for ((i = 1; i <= n; i++)); do out+="${out:+,}$(zenity_call "$i" | grep -m1 -xE -e '--(info|question|entry|progress)' || echo '?')"; done
    printf '%s' "$out"
}
zt() { zenity_call "$1" | tr '\036' '\n'; }

fresh_stores; install_three; fake_sudo_password secret
win_flow OK OK OUT:secret OK
check_eq 'windows, yes: the flow ends well (status 0)' 0 "$(status_of_flow)"
check_eq 'windows, yes: the three applications are gone' 'fs= fu= sn=' "$(stores_present)"
check_eq 'windows, yes: seven windows: plan, question, password, one progress per application, result' \
    '--info,--question,--entry,--progress,--progress,--progress,--info' "$(zkinds)"
assert_contains 'windows, yes: the plan window introduces the plan' "$(zt 1)" '--text=This is the plan to uninstall Flatpak and Snap applications.'
assert_contains 'windows, yes: and lists the three applications, one per line' "$(zt 1)" \
    $'  Flatpak: org.mozilla.firefox (system-wide, flathub)\n  Flatpak: org.gnome.gedit (your user only)\n  Snap: vlc (system-wide)'
assert_contains 'windows, yes: the question starts on Cancel' "$(zt 2)" '--default-cancel'
assert_contains 'windows, yes: its buttons say what they do' "$(zt 2)" $'--ok-label=Uninstall\n--cancel-label=Cancel'
assert_contains 'windows, yes: it asks about these applications' "$(zt 2)" 'Do you want to continue uninstalling these applications?'
assert_contains 'windows, yes: with the warning icon' "$(zt 2)" '--icon=dialog-warning'
assert_contains 'windows, yes: the password is typed hidden' "$(zt 3)" '--hide-text'
check_eq 'windows, yes: the progress windows name each application, in the order of the plan' \
    $'--text=Uninstalling org.mozilla.firefox...\n--text=Uninstalling org.gnome.gedit...\n--text=Uninstalling vlc...' \
    "$(zt 4 | grep '^--text=')"$'\n'"$(zt 5 | grep '^--text=')"$'\n'"$(zt 6 | grep '^--text=')"
check_eq 'windows, yes: every progress window was closed by the end of its input' 3 "$(grep -c '^@@END@@$' "$SB/state/zenity.stdin")"
assert_contains 'windows, yes: the result window says it went well' "$(zt 7)" '--text=Uninstallation completed successfully.'
assert_contains 'windows, yes: and points to the record' "$(zt 7)" 'A record of what was removed was saved to:'
check_eq 'windows, yes: the password was typed once, for the three' secret "$(sudo_given)"
check_eq 'windows, yes: rights first, then each removal, all with -A' \
    $'sudo -A -v\nsudo -A flatpak uninstall --system --noninteractive -y org.mozilla.firefox\nsudo -A snap remove vlc' "$(sudo_log)"
assert_not_contains 'windows, yes: nothing of the stores is written on the terminal' "$(plain)" 'org.mozilla.firefox'
check_eq 'windows, yes: one record, the completed one' '# Status: completed|1' "$(grep '^# Status' "$(rec_file)")|$(state_files | wc -l)"

fresh_stores; install_three; fake_sudo_password secret
win_flow OK CANCEL
check_eq 'windows, no: the status is 1' 1 "$(status_of_flow)"
check_eq 'windows, no: only the plan and the question: no password, no progress' '--info,--question' "$(zkinds)"
check_eq 'windows, no: nothing removed, no privilege command, no record' "$UNTOUCHED|0|0|0" \
    "$(stores_present)|$(removal_calls)|$(sudo_log | wc -l)|$(state_files | wc -l)"
fresh_stores; install_three; fake_sudo_password secret
win_flow CANCEL
check_eq 'windows, the question closed without an answer is a no: nothing removed' "$UNTOUCHED|0" "$(stores_present)|$(removal_calls)"

fresh_stores; install_three; fake_sudo_password secret
win_flow OK OK CANCEL OK
check_eq 'windows, password window closed: status 77' 77 "$(status_of_flow)"
check_eq 'windows, password window closed: nothing removed, no record' "$UNTOUCHED|0|0" "$(stores_present)|$(removal_calls)|$(state_files | wc -l)"
check_eq 'windows, password window closed: no progress window, and a result window' '--info,--question,--entry,--info' "$(zkinds)"
assert_contains 'windows, password window closed: it says why nothing was uninstalled' "$(zt 4)" '--text=Administrator rights were not obtained'
assert_not_contains 'windows, password window closed: no record is pointed to' "$(zt 4)" 'A record of what was removed'
fresh_stores; install_three; fake_sudo_password secret
win_flow OK OK OUT:bad OUT:bad OUT:bad OK
check_eq 'windows, wrong password three times: status 77, nothing removed or recorded' "77|$UNTOUCHED|0" "$(status_of_flow)|$(stores_present)|$(state_files | wc -l)"
check_eq 'windows, wrong password three times: one password window per try, no progress window' \
    '3|--info,--question,--entry,--entry,--entry,--info' "$(sudo_given | wc -l)|$(zkinds)"
assert_contains 'windows, wrong password three times: the result says no rights were obtained' "$(zt 6)" '--text=Administrator rights were not obtained'

fresh_stores; install_three; fake_sudo_password secret; printf 'vlc 4\n' > "$SB/state/store.fail"; sandbox_chown
win_flow OK OK OUT:secret OK
check_eq 'windows, a failure: the status of the failed command' 4 "$(status_of_flow)"
check_eq 'windows, a failure: the others were removed' 'fs= fu= sn=vlc' "$(stores_present)"
check_eq 'windows, a failure: the same seven windows' '--info,--question,--entry,--progress,--progress,--progress,--info' "$(zkinds)"
assert_contains 'windows, a failure: the result says how many failed' "$(zt 7)" '--text=Uninstalls that failed: 1 of 3 (exit code 4).'
assert_contains 'windows, a failure: it shows the last lines of the output (nothing above to read)' "$(zt 7)" $'Last lines of the output:\nerror: cannot remove vlc'
assert_not_contains 'windows, a failure: no success message' "$(zt 7)" 'completed successfully'
assert_contains 'windows, a failure: the record is still pointed to' "$(zt 7)" 'A record of what was removed was saved to:'
check_eq 'windows, a failure: the record says so' '# Status: failed (1 of 3 applications not removed)' "$(grep '^# Status' "$(rec_file)")"

fresh_stores; install_three; fake_sudo_password secret
WT_REQ='flatpak user org.gnome.gedit' win_flow OK OK OK
check_eq 'windows, only a Flatpak of the user: no password window' '--info,--question,--progress,--info' "$(zkinds)"
check_eq 'windows, only a Flatpak of the user: removed, with no privilege command' '0|fs=org.mozilla.firefox fu= sn=vlc|' \
    "$(status_of_flow)|$(stores_present)|$(sudo_log)"

fresh_stores; install_three; fake_sudo_password secret
WT_LANG=es win_flow OK OK OUT:secret OK
check_eq 'windows, Spanish: the flow ends well and the three are gone' '0|fs= fu= sn=' "$(status_of_flow)|$(stores_present)"
assert_contains 'windows, Spanish: the plan' "$(zt 1)" '--text=Este es el plan de desinstalación de Flatpak y Snap.'
assert_contains 'windows, Spanish: the question and its buttons' "$(zt 2)" $'--ok-label=Desinstalar\n--cancel-label=Cancelar'
assert_contains 'windows, Spanish: a progress window' "$(zt 6)" '--text=Desinstalando vlc...'
assert_contains 'windows, Spanish: the result' "$(zt 7)" '--text=Desinstalación completada.'

fresh_stores; install_three
WT_REQ='' win_flow OK
check_eq 'windows, an empty request: one window that says nothing was selected' '--info' "$(zkinds)"
assert_contains 'windows, an empty request: its text' "$(zt 1)" '--text=No applications were selected.'
fresh_stores; install_three
WT_REQ=$'snap system gimp\nflatpak user org.nobody.Installed' win_flow OK
check_eq 'windows, nothing installed any more: one window, no plan, no removal, no record' '--info|0|0' "$(zkinds)|$(removal_calls)|$(state_files | wc -l)"
assert_contains 'windows, nothing installed any more: it says so' "$(zt 1)" '--text=The selected applications are no longer installed.'

fresh_stores; install_three; fake_sudo_password secret
fake_zenity OK
ge 'review_store_plan() { : > "$ST/snap.list"; return 0; }; UI_ENGINE=gui; HAVE_WHIPTAIL=1; confirm_and_remove_stores "$REQ"; printf "<<%s>>" "$?"' \
    REQ="$ALL3" ST="$SB/state" MINTAPP_LANG=en
check_eq 'windows, the system changes after the confirmation: one window, no password' '--info' "$(zkinds)"
assert_contains 'windows, the system changes after the confirmation: it says so' "$(zt 1)" '--text=The system changed after the plan was calculated, so nothing was removed.'
check_eq 'windows, the system changes after the confirmation: nothing removed, recorded or asked' '0|0|0' "$(removal_calls)|$(state_files | wc -l)|$(sudo_log | wc -l)"


# ------------------------------------------------------------------------------------------------
# Real signals. The removal of the Snap never ends (store.hang) and a signal arrives while it runs.
# The program runs in a group of its own (the program, sudo, the stub and what they start), so that
# a signal can go to the whole group (Ctrl-C, a closed terminal, systemd) or only to the program.
#  - "setsid --wait": when setsid has to fork (the caller leads its own group, as with job control)
#    it exits with 0 at once without --wait, and the status of the program is lost.
#  - A job that bash starts in the background ignores SIGINT, and a signal ignored at the start
#    cannot be trapped. python puts SIGINT back to its default (and SIGPIPE and SIGXFSZ, which it
#    ignores itself) before it starts the program; without python3 the INT cases are skipped.
#  - The same goes for SIGHUP when the suite itself is started with nohup (D2): the program
#    inherits the ignored SIGHUP and the HUP cases end with 999. python puts it back too.
# hung_start CODE [VAR=val ...]: starts CODE and waits for the removal to hang. hung_send SIGNAL
# group|pid. hung_finish: waits for the program to end (8 s; if it does not, KILL to the group)
# and sets RC (999 if it did not end), HUNG_LEFT (processes of the group still alive) and
# HUNG_SAME (the stub is in the group of the program). hung_run SIGNAL WHO CODE ... does the three.
# ------------------------------------------------------------------------------------------------
H_PYTHON="$(command -v python3 || true)"
PY_UNIGNORE='import os, signal, sys
for s in (signal.SIGINT, signal.SIGHUP, signal.SIGPIPE, signal.SIGXFSZ):
    signal.signal(s, signal.SIG_DFL)
os.execv(sys.argv[1], sys.argv[1:])'
HUNG_BG="" HUNG_PGID="" HUNG_SAME=no HUNG_LEFT=0

pgid_of() { cut -d' ' -f5 "/proc/$1/stat" 2>/dev/null || true; }
# group_alive PGID: how many processes of the group are alive (zombies do not count).
group_alive() { ps -eo pgid=,stat= | awk -v g="$1" '$1 == g && $2 !~ /^Z/ { n++ } END { print n + 0 }'; }

hung_start() {
    local code="$1" i prog
    shift
    local -a pre=() wrap=()
    rm -f -- "$SB/state/hang.marker" "$SB/state/prog.pid"
    if [ "$(id -u)" -eq 0 ]; then pre=("$H_SETPRIV" --reuid="$H_APP_UID" --regid="$H_APP_GID" --clear-groups); fi
    if [ -n "$H_PYTHON" ]; then wrap=("$H_PYTHON" -c "$PY_UNIGNORE"); fi
    setsid --wait "$H_ENV" -i "${BASE_ENV[@]}" "$@" "${pre[@]+"${pre[@]}"}" "${wrap[@]+"${wrap[@]}"}" \
        "$H_BASH" -c 'echo $$ > "$2"; source "$1"; eval "$3"' bash "$H_SCRIPT" "$SB/state/prog.pid" "$code" \
        </dev/null >"$SB/state/hung.out" 2>&1 &
    HUNG_BG=$!
    for (( i = 0; i < 100; i++ )); do
        [ -s "$SB/state/hang.marker" ] && break
        kill -0 "$HUNG_BG" 2>/dev/null || break
        sleep 0.1
    done
    HUNG_PGID="" HUNG_SAME=no
    if read -r _ HUNG_PGID < "$SB/state/hang.marker" 2>/dev/null; then
        prog="$(cat "$SB/state/prog.pid" 2>/dev/null || true)"
        [ -z "$prog" ] || [ "$(pgid_of "$prog")" != "$HUNG_PGID" ] || HUNG_SAME=yes
    fi
    return 0
}

hung_send() {
    local sig="$1" who="$2" prog
    # Never signal a group that is not the program's: it could be the one of the tests.
    [ "$HUNG_SAME" = yes ] && [ "$HUNG_PGID" != "$(pgid_of $$)" ] || return 0
    if [ "$who" = group ]; then
        kill -s "$sig" -- "-$HUNG_PGID" 2>/dev/null || true
    else
        prog="$(cat "$SB/state/prog.pid")"
        kill -s "$sig" "$prog" 2>/dev/null || true
    fi
}

hung_finish() {
    local i
    for (( i = 0; i < 80; i++ )); do
        kill -0 "$HUNG_BG" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$HUNG_BG" 2>/dev/null; then
        [ -z "$HUNG_PGID" ] || [ "$HUNG_PGID" = "$(pgid_of $$)" ] || kill -KILL -- "-$HUNG_PGID" 2>/dev/null || true
        kill -KILL "$HUNG_BG" 2>/dev/null || true
        wait "$HUNG_BG" 2>/dev/null || true
        RC=999
    else
        wait "$HUNG_BG" && RC=0 || RC=$?
    fi
    HUNG_LEFT=0
    if [ -n "$HUNG_PGID" ] && [ "$HUNG_PGID" != "$(pgid_of $$)" ]; then
        for (( i = 0; i < 20; i++ )); do
            HUNG_LEFT="$(group_alive "$HUNG_PGID")"
            [ "$HUNG_LEFT" -eq 0 ] && break
            sleep 0.1
        done
        [ "$HUNG_LEFT" -eq 0 ] || kill -KILL -- "-$HUNG_PGID" 2>/dev/null || true
    fi
    return 0
}

hung_run() { local sig="$1" who="$2" code="$3"; shift 3; hung_start "$code" "$@"; hung_send "$sig" "$who"; hung_finish; }

# hung_check LABEL: what any signal that reaches the whole group must leave behind.
hung_check() {
    local rec body tmp
    rec="$(state_files | head -n1)"
    body="$(cat "$rec" 2>/dev/null || echo none)"
    tmp="$(find "$SB/home/.local/state/mintapp-remover" -name '.tmp.*' 2>/dev/null | wc -l)"
    check_eq "$1: the stub runs in the group of the program" yes "$HUNG_SAME"
    check_eq "$1: one record, the interrupted one" '# Status: interrupted|1' "$(grep '^# Status' "$rec" 2>/dev/null || echo none)|$(state_files | wc -l)"
    check_eq "$1: the record has the whole plan" "$ALL3" "$(sed -n '/^# Applications in the plan:/,/^#$/p' <<< "$body" | grep -E '^(flatpak|snap) ')"
    check_eq "$1: no temporary file is left" 0 "$tmp"
    check_eq "$1: no process of the group is left" 0 "$HUNG_LEFT"
    check_eq "$1: what was removed stays removed; the Snap, still there" 'fs= fu= sn=vlc' "$(stores_present)"
}

TERMINAL_HUNG='install_traps; review_store_plan() { return 0; }; UI_ENGINE=text; HAVE_WHIPTAIL=0; confirm_and_remove_stores "$REQ"'

echo "-- a real signal to the group while a removal runs (terminal)"
fresh_stores; install_three; echo vlc > "$SB/state/store.hang"
hung_run TERM group "$TERMINAL_HUNG" REQ="$ALL3" MINTAPP_LANG=en
check_eq 'SIGTERM to the group: the program ends with 143' 143 "$RC"
hung_check 'SIGTERM to the group'

fresh_stores; install_three; echo vlc > "$SB/state/store.hang"
hung_run HUP group "$TERMINAL_HUNG" REQ="$ALL3" MINTAPP_LANG=en
check_eq 'SIGHUP to the group: the program ends with 129' 129 "$RC"
hung_check 'SIGHUP to the group'

if [ -n "$H_PYTHON" ]; then
    fresh_stores; install_three; echo vlc > "$SB/state/store.hang"
    hung_run INT group "$TERMINAL_HUNG" REQ="$ALL3" MINTAPP_LANG=en
    check_eq 'SIGINT to the group: the program ends with 130' 130 "$RC"
    hung_check 'SIGINT to the group'
else
    skip_case 'SIGINT to the group (needs python3 to start the program with SIGINT in its default state)'
fi


echo "-- a real signal to the group while a removal runs (windows)"
WINDOWS_HUNG='install_traps; zenity_usable; review_store_plan() { return 0; }; UI_ENGINE=gui; HAVE_WHIPTAIL=1; confirm_and_remove_stores "$REQ"'
# gui_dirs: the private folders of the windows that exist now.
gui_dirs() { find "$SB/tmp" -maxdepth 1 -name 'mintapp-gui.*' 2>/dev/null | wc -l; }
for pair in TERM:143 HUP:129 INT:130; do
    sig="${pair%%:*}" want_rc="${pair##*:}"
    if [ "$sig" = INT ] && [ -z "$H_PYTHON" ]; then skip_case 'windows, SIGINT to the group (needs python3)'; continue; fi
    fresh_stores; install_three; echo vlc > "$SB/state/store.hang"
    hung_start "$WINDOWS_HUNG" REQ="$ALL3" "${GUI[@]}" TMPDIR="$SB/tmp"
    check_eq "windows, SIG$sig: while the removal runs there is a private folder and a progress window" \
        '1|--progress' "$(gui_dirs)|$(grep -m1 -x -e '--progress' "$SB/state/zenity.args" | tail -n1)"
    hung_send "$sig" group; hung_finish
    check_eq "windows, SIG$sig to the group: the program ends with $want_rc" "$want_rc" "$RC"
    hung_check "windows, SIG$sig to the group"
    check_eq "windows, SIG$sig to the group: the private folder is removed" 0 "$(gui_dirs)"
done

echo "-- a signal only to the program waits for the command in progress"
# bash runs a trap when the command in the foreground ends: until then the program does not end.
# The command is stopped here (TERM to the stub), as a closed terminal or Ctrl-C would stop it.
fresh_stores; install_three; echo vlc > "$SB/state/store.hang"
hung_start "$TERMINAL_HUNG" REQ="$ALL3" MINTAPP_LANG=en
hung_send TERM pid
sleep 1
check_eq 'SIGTERM only to the program: a second later it is still waiting for the command' yes \
    "$(kill -0 "$HUNG_BG" 2>/dev/null && echo yes || echo no)"
check_eq 'SIGTERM only to the program: the record is still the one of a run in progress' '# Status: started' \
    "$(grep '^# Status' "$(rec_file)" 2>/dev/null || echo none)"
STUB_PIDS="$(ps -eo pid=,pgid=,comm= | awk -v g="$HUNG_PGID" '$2 == g && $3 == "sleep" { print $1 }')"
# shellcheck disable=SC2086  # the list of PIDs is split on purpose
[ -z "$STUB_PIDS" ] || kill -TERM $STUB_PIDS 2>/dev/null || true
hung_finish
check_eq 'SIGTERM only to the program: once the command ends, the program ends with 143' 143 "$RC"
hung_check 'SIGTERM only to the program'


echo "-- windows: a progress window that does not close by itself is closed on exit"
# The progress window ends by itself when its input ends; gui_cleanup stops it if it does not. Here
# it never ends (sleep 61) and the signal goes only to the program, so the group does not stop it.
fresh_stores; install_three; echo vlc > "$SB/state/store.hang"
mv "$SB/bin/zenity" "$SB/bin/zenity.real"
printf '%s\n' '#!/bin/sh' 'PATH=/usr/local/bin:/usr/bin:/bin' 'case " $* " in *" --progress "*) exec sleep 61 ;; esac' \
    "exec \"$SB/bin/zenity.real\" \"\$@\"" > "$SB/bin/zenity"
chmod 755 "$SB/bin/zenity"; sandbox_chown
# window_procs: processes of the group that are the progress window of this test.
window_procs() { ps -eo pgid=,args= | awk -v g="$HUNG_PGID" '$1 == g && /sleep 61$/ { n++ } END { print n + 0 }'; }
hung_start "$WINDOWS_HUNG" REQ="$ALL3" "${GUI[@]}" TMPDIR="$SB/tmp"
check_eq 'the progress window is open while the removal runs' '1|1' "$(gui_dirs)|$(window_procs)"
hung_send TERM pid
STUB_PIDS="$(ps -eo pid=,pgid=,args= | awk -v g="$HUNG_PGID" '$2 == g && /sleep 60$/ { print $1 }')"
# shellcheck disable=SC2086  # the list of PIDs is split on purpose
[ -z "$STUB_PIDS" ] || kill -TERM $STUB_PIDS 2>/dev/null || true
hung_finish
check_eq 'SIGTERM only to the program: it ends with 143 once the command ends' 143 "$RC"
hung_check 'windows, a window that does not close by itself'
check_eq 'windows, a window that does not close by itself: the private folder is removed' 0 "$(gui_dirs)"

echo "-- on_exit: after a signal the terminal keeps the settings it had (stty -g, not stty sane)"
# D8. "stty sane", which on_exit ran alone, turns brkint and imaxbel on and iutf8 off, whatever the terminal had.
# pty_stty CODE [VAR=val ...] runs CODE in the program on a pseudo-terminal that starts with the opposite, and reads
# "stty -g" before the program and after it ended (STTY_BEFORE, STTY_AFTER) and the status of the program (STTY_RC).
# A signal ignored at the start cannot be trapped (the suite may run in the background): python puts it back, as above.
pty_stty() {
    local code="$1" dir="$SB/state"
    shift
    printf '%s\n' "$PY_UNIGNORE" > "$dir/unignore.py"
    cat > "$dir/pty.sh" <<'EOF'
stty -brkint -imaxbel iutf8
stty -g > "$STTY_DIR/before"
$PY_WRAP "$APP_BASH" -c 'source "$1"; eval "$2"' bash "$APP_SCRIPT" "$APP_CODE"
echo "$?" > "$STTY_DIR/rc"
stty -g > "$STTY_DIR/after"
EOF
    rm -f -- "$dir/before" "$dir/after" "$dir/rc"
    _exec '' 60 STTY_DIR="$dir" APP_BASH="$H_BASH" APP_SCRIPT="$H_SCRIPT" APP_CODE="$code" \
        PY_WRAP="${H_PYTHON:+$H_PYTHON $dir/unignore.py}" "$@" -- "$(command -v script)" -qec "sh $dir/pty.sh" /dev/null
    STTY_BEFORE="$(cat "$dir/before" 2> /dev/null || true)" STTY_AFTER="$(cat "$dir/after" 2> /dev/null || true)"
    STTY_RC="$(cat "$dir/rc" 2> /dev/null || true)"
}
STTY_BEFORE=""
if [ -n "$(command -v script)" ] && [ -n "$H_PYTHON" ]; then
    new_sandbox; sandbox_chown
    pty_stty 'stty sane'
fi
if [ -z "$STTY_BEFORE" ]; then
    skip_case 'terminal settings after a signal (needs util-linux script, python3 and a pseudo-terminal)'
else
    check_eq 'control: the terminal starts with settings that "stty sane" would change' yes \
        "$([ "$STTY_BEFORE" != "$STTY_AFTER" ] && echo yes || echo no)"
    SANE_STTY="$STTY_AFTER"
    for pair in TERM:143 HUP:129 INT:130; do
        sig="${pair%%:*}" exp_rc="${pair##*:}"
        new_sandbox; sandbox_chown
        pty_stty 'install_traps; kill -s '"$sig"' $$; sleep 5'
        check_eq "SIG$sig on a terminal: the program ends with $exp_rc" "$exp_rc" "$STTY_RC"
        check_eq "SIG$sig on a terminal: the settings are those it found" "$STTY_BEFORE" "$STTY_AFTER"
    done
    # Without usable settings (not taken, or refused by stty) the way back is "stty sane", as before.
    for bad in '' garbage; do
        new_sandbox; sandbox_chown
        pty_stty 'install_traps; EXIT_STTY="'"$bad"'"; kill -s TERM $$; sleep 5'
        check_eq "settings ${bad:-empty}: stty sane puts the terminal in a sane state" "$SANE_STTY" "$STTY_AFTER"
    done
    new_sandbox; sandbox_chown
    pty_stty 'install_traps; exit 3'
    check_eq 'an exit without a signal does not touch the terminal' "$STTY_BEFORE|3" "$STTY_AFTER|$STTY_RC"
fi
new_sandbox
app_eval 'install_traps; kill -s TERM $$; sleep 5'
check_eq 'without a terminal: SIGTERM ends with 143 and stty says nothing' '143|' "$RC|$OUT"

# ------------------------------------------------------------------------------------------------
# 4.5c: option 3 offers the Flatpaks and Snaps of the launchers, each store with its own plan. A
# launcher counts only in the folder where its store exports them, and the identifier comes from the
# name of the file. flatpak.origin ("ID REMOTE", one per line) is what "flatpak info --show-origin"
# says; with nothing there the stub prints nothing.
# ------------------------------------------------------------------------------------------------
echo "-- launcher_store_line: which launcher belongs to which store"
new_sandbox
lsl() {  # lsl PATH [VAR=val ...]: the plan line of that launcher, or (none)
    local path="$1" v; shift
    app_eval 'if line="$(launcher_store_line "$LP")"; then printf "<<%s>>" "$line"; else printf "<<(none)>>"; fi' LP="$path" "$@"
    v="${OUT#*<<}"; printf '%s' "${v%%>>*}"
}
FPD=/var/lib/flatpak/exports/share/applications SND=/var/lib/snapd/desktop/applications
check_eq 'the Flatpak of the system' 'flatpak system org.mozilla.firefox' "$(lsl "$FPD/org.mozilla.firefox.desktop")"
check_eq 'the Flatpak of the user (the folder is under HOME)' 'flatpak user org.gnome.gedit' \
    "$(lsl "$SB/home/.local/share/flatpak/exports/share/applications/org.gnome.gedit.desktop")"
check_eq 'a Snap' 'snap system vlc' "$(lsl "$SND/vlc_vlc.desktop")"
check_eq 'a Snap whose name has a hyphen' 'snap system snap-store' "$(lsl "$SND/snap-store_snap-store.desktop")"
check_eq 'a second launcher of the same Snap gives the same line' 'snap system code' "$(lsl "$SND/code_code-url-handler.desktop")"
check_eq 'a Flatpak ID with two elements is not valid' '(none)' "$(lsl "$FPD/org.firefox.desktop")"
check_eq 'an ID that reads as an option is not valid' '(none)' "$(lsl "$FPD/-rf.x.y.desktop")"
check_eq 'an ID with a space is not valid' '(none)' "$(lsl "$FPD/org.x y.z.desktop")"
check_eq 'a launcher outside the folders of the stores' '(none)' "$(lsl "$SB/home/.local/share/applications/org.mozilla.firefox.desktop")"
check_eq 'a launcher of the apt folder, even with the name of a Flatpak' '(none)' "$(lsl /usr/share/applications/org.mozilla.firefox.desktop)"
check_eq 'a Snap launcher without the underscore' '(none)' "$(lsl "$SND/vlc.desktop")"
check_eq 'a Snap name in capitals is not valid' '(none)' "$(lsl "$SND/VLC_vlc.desktop")"
check_eq 'a Snap name that reads as an option is not valid' '(none)' "$(lsl "$SND/-v_vlc.desktop")"
check_eq 'an empty Snap name' '(none)' "$(lsl "$SND/_vlc.desktop")"
check_eq 'a file of the Flatpak folder that is not a launcher' '(none)' "$(lsl "$FPD/org.mozilla.firefox.txt")"
check_eq 'without HOME nothing is assumed to be of the user: the Flatpak is of the system' 'flatpak system org.gnome.gedit' \
    "$(lsl "$SB/home/.local/share/flatpak/exports/share/applications/org.gnome.gedit.desktop" HOME=)"

echo "-- store_line_with_remote: the remote is asked only for a Flatpak that has none"
stores_sandbox; install_three
printf '%s\n' 'org.mozilla.firefox flathub' 'org.gnome.gedit bad;remote' > "$SB/state/flatpak.origin"; sandbox_chown
slr() {  # slr LINE: store_line_with_remote of that line
    local v
    app_eval 'printf "<<%s>>" "$(store_line_with_remote "$L")"' L="$1"
    v="${OUT#*<<}"; printf '%s' "${v%%>>*}"
}
check_eq 'a Flatpak gets the remote it came from' 'flatpak system org.mozilla.firefox flathub' "$(slr 'flatpak system org.mozilla.firefox')"
check_eq 'it is asked with its scope and --show-origin' 'flatpak info --system --show-origin org.mozilla.firefox' "$(stores_log | tail -n1)"
check_eq 'what is not a valid remote name is dropped' 'flatpak user org.gnome.gedit' "$(slr 'flatpak user org.gnome.gedit')"
check_eq 'a Flatpak that is not installed keeps its line' 'flatpak system org.nobody.here' "$(slr 'flatpak system org.nobody.here')"
: > "$SB/state/stores.log"; sandbox_chown
check_eq 'a Flatpak that already has a remote keeps it' 'flatpak system org.mozilla.firefox fedora' "$(slr 'flatpak system org.mozilla.firefox fedora')"
check_eq 'a Snap is left as it is' 'snap system vlc' "$(slr 'snap system vlc')"
check_eq 'a line that is not valid is left as it is' 'flatpak system -rf' "$(slr 'flatpak system -rf')"
check_eq 'and none of these three asked flatpak or snap' '' "$(stores_log)"

echo "-- option 3: the Flatpaks and Snaps are offered, with their store"
sd_launcher() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\n' "$2" > "$1"; sandbox_chown; }
# apps_sandbox: an apt application (fooapp), a Flatpak of the system, a Flatpak of the user, a Snap
# and a manual launcher, each in its own folder; LD is the list of folders to scan.
apps_sandbox() {
    stores_sandbox; install_three
    FPS="$SB/sys/var/lib/flatpak/exports/share/applications"
    FPU="$SB/home/.local/share/flatpak/exports/share/applications"
    SNP="$SB/sys/var/lib/snapd/desktop/applications"
    mkdir -p "$FPS" "$FPU" "$SNP"
    sd_launcher "$FPS/org.mozilla.firefox.desktop" 'Firefox Flatpak'
    sd_launcher "$FPU/org.gnome.gedit.desktop" 'Text Editor'
    sd_launcher "$SNP/vlc_vlc.desktop" 'VLC Snap'
    fake_installed fooapp
    make_desktop foo.desktop 'Foo app'; fake_owner "$SB/apps/foo.desktop" fooapp
    make_desktop manual.desktop 'Manual app' 'Exec=/opt/manual/run'
    printf '%s\n' 'org.mozilla.firefox flathub' > "$SB/state/flatpak.origin"; sandbox_chown
    LD="MINTAPP_LAUNCHER_DIRS=$SB/apps:$FPS:$FPU:$SNP"
}
apps_sandbox
app_eval 'scan_launchers; for i in "${!ADV_NAMES[@]}"; do printf "%s|%s|%s|%s\n" "${ADV_NAMES[$i]}" "${ADV_PACKAGES[$i]}" "${ADV_LINES[$i]}" "${ADV_HAY[$i]}"; done' \
    MINTAPP_LANG=en MINTAPP_ASCII=0 "$LD"
check_eq 'the entries are one per application, sorted by name, each with its line (apt ones have none)' \
$'Firefox Flatpak|Flatpak: org.mozilla.firefox|flatpak system org.mozilla.firefox|firefox flatpak flatpak: org.mozilla.firefox\nFoo app|fooapp||foo app fooapp\nText Editor|Flatpak: org.gnome.gedit|flatpak user org.gnome.gedit|text editor flatpak: org.gnome.gedit\nVLC Snap|Snap: vlc|snap system vlc|vlc snap snap: vlc' "$OUT"
app_eval 'scan_launchers; printf "%s|%s\n" "${ADV_UNMANAGED_NAMES[*]}" "${ADV_UNMANAGED_ORIGINS[*]}"' MINTAPP_LANG=en MINTAPP_ASCII=0 "$LD"
check_eq 'only the manual launcher stays unmanaged' 'Manual app|manual' "$OUT"

apps_sandbox
sd_launcher "$SNP/vlc_vlc-extra.desktop" 'VLC Snap (extra)'
sd_launcher "$FPS/weird.name.desktop" 'Weird'
sd_launcher "$FPS/org.mozilla.firefox.Extra.desktop" 'Firefox Flatpak'
app_eval 'scan_launchers; printf "%s|%s|%s\n" "${#ADV_NAMES[@]}" "${#ADV_LINES[@]}" "${ADV_UNMANAGED_NAMES[*]}"' MINTAPP_LANG=en MINTAPP_ASCII=0 "$LD"
check_eq 'a second launcher of the same Snap adds nothing, another valid ID is one more, an ID that is not valid stays unmanaged' \
    '5|5|Manual app Weird' "$OUT"

echo "-- option 3 in text mode: the three stores, chosen together"
O3=(MINTAPP_LANG=en MINTAPP_ASCII=0)
apps_sandbox
app_run $'\n3\n\n1\n3\n4\nc\ny\n\n0\n' "${O3[@]}" "$LD"; P="$(plain)"
assert_contains 'the list marks the Flatpak of the system with its store' "$P" 'Firefox Flatpak'
assert_contains 'and gives its ID' "$P" '[Flatpak: org.mozilla.firefox]'
assert_contains 'the Flatpak of the user' "$P" '[Flatpak: org.gnome.gedit]'
assert_contains 'the Snap' "$P" '[Snap: vlc]'
assert_contains 'the apt application keeps its package' "$P" '[fooapp]'
assert_contains 'the manual launcher is told apart, with its origin' "$P" '  - Manual app [manual install]'
assert_contains 'and the note says it cannot be uninstalled from here' "$P" '1 additional launcher cannot be uninstalled from here'
assert_contains 'the warning tells that the stores have their own plan' "$(printf '%s' "$P" | tr '\n' ' ' | tr -s ' ')" 'Flatpak and Snap applications appear marked with the name of their store'
assert_contains 'the plan comes from the stores, with the remote the Flatpak came from' "$P" '  Flatpak: org.mozilla.firefox (system-wide, flathub)'
assert_contains 'the Flatpak of the user has no remote to show' "$P" '  Flatpak: org.gnome.gedit (your user only)'
assert_contains 'the Snap in the plan' "$P" '  Snap: vlc (system-wide)'
assert_not_contains 'no plan of apt: nothing of apt was chosen' "$P" 'Purg'
check_eq 'the three applications are gone' 'fs= fu= sn=' "$(stores_present)"
check_eq 'apt was not called to remove anything' 0 "$(real_removals)"
check_eq 'the commands of the stores, with administrator rights where they need them' \
    $'sudo flatpak uninstall --system --noninteractive -y org.mozilla.firefox\nsudo snap remove vlc' "$(sudo_log)"
check_eq 'one record, the completed one' '# Status: completed|1' "$(grep '^# Status' "$(rec_file)")|$(state_files | wc -l)"
assert_contains 'the record has the remote of the Flatpak' "$(cat "$(rec_file)")" $'flatpak system org.mozilla.firefox flathub\n'
assert_contains 'and the command to install it again from that remote' "$(cat "$(rec_file)")" '# sudo flatpak install --system flathub org.mozilla.firefox'

apps_sandbox
app_run $'\n3\n\n1\n3\n4\nc\nn\n\n0\n' "${O3[@]}" "$LD"
check_eq 'cancelling the plan removes nothing' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc' "$(stores_present)"
check_eq 'and leaves no record' 0 "$(state_files | wc -l)"
check_eq 'and no command of the stores runs to remove' 0 "$(removal_calls)"

apps_sandbox
app_run $'\n3\n\n3\nc\ny\n\n0\n' "${O3[@]}" "$LD"
check_eq 'one Flatpak of the user alone: it goes, with no administrator rights' 'fs=org.mozilla.firefox fu= sn=vlc' "$(stores_present)"
check_eq 'the user needs no rights for it (no sudo call)' '' "$(sudo_log)"

echo "-- option 3 in text mode: apt and the stores together, each with its own plan"
apps_sandbox
app_run $'\n3\n\n2\n4\nc\ny\n\ny\n\n0\n' "${O3[@]}" "$LD"; P="$(plain)"
assert_contains 'the plan of apt comes first' "$P" 'Purg fooapp [1.0]'
check_eq 'apt purged the apt application' 1 "$(real_removals)"
assert_contains 'and it was the one chosen' "$(apt_log)" 'apt-get purge -y fooapp'
assert_contains 'then the plan of the store' "$P" '  Snap: vlc (system-wide)'
check_eq 'the Snap is gone and the Flatpaks stay' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=' "$(stores_present)"
check_eq 'two records: one of apt, one of the store' 2 "$(state_files | wc -l)"
in_order 'apt first, the store after' "$P" 'Purg fooapp [1.0]' 'Uninstallation completed successfully.' '  Snap: vlc (system-wide)'

apps_sandbox
app_run $'\n3\n\n2\n4\nc\nn\n\ny\n\n0\n' "${O3[@]}" "$LD"
check_eq 'cancelling the plan of apt does not cancel the other: the Snap still has its own question' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=' "$(stores_present)"
check_eq 'and apt removed nothing' 0 "$(real_removals)"

apps_sandbox
app_run $'\n3\n\n2\nc\ny\n\n0\n' "${O3[@]}" "$LD"
check_eq 'only the apt application chosen: apt removes it' 1 "$(real_removals)"
check_eq 'and no store is asked about anything' '' "$(stores_log)"

echo "-- option 3 in whiptail: the stores, chosen with the others"
apps_sandbox
fake_answers OK TAG:3 OK 'TAG:"1" "3" "4"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail "${O3[@]}" "$LD"
check_eq 'whiptail: the flow ends well' 0 "$RC"
check_eq 'whiptail: the three applications are gone' 'fs= fu= sn=' "$(stores_present)"
LIST_BOX="$(awk '/^whiptail /{n++} /--checklist/{p=1} p' "$SB/state/whiptail.log" | head -n 40)"
assert_contains 'whiptail: the list offers the Flatpak with its store and ID' "$LIST_BOX" '[Flatpak: org.mozilla.firefox]'
assert_contains 'whiptail: and the Snap' "$LIST_BOX" '[Snap: vlc]'
assert_contains 'whiptail: and the application of apt with its package' "$LIST_BOX" '[fooapp]'
PLAN_BOX="$(grep -F -A6 -- 'This is the plan to uninstall Flatpak and Snap applications.' "$SB/state/whiptail.log" | head -n 8)"
assert_contains 'whiptail: the plan box lists the Flatpak with its remote' "$PLAN_BOX" '  Flatpak: org.mozilla.firefox (system-wide, flathub)'
assert_contains 'whiptail: the question starts on Cancel' "$(grep -F -B2 -- 'Do you want to continue uninstalling these applications?' "$SB/state/whiptail.log" | head -n 4)" '--defaultno'
check_eq 'whiptail: one record, the completed one' '# Status: completed|1' "$(grep '^# Status' "$(rec_file)")|$(state_files | wc -l)"

apps_sandbox
fake_answers OK TAG:3 OK 'TAG:"1" "3" "4"' OK NO TAG:0
app_run '' MINTAPP_UI=whiptail "${O3[@]}" "$LD"
check_eq 'whiptail: No leaves everything installed' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc' "$(stores_present)"

apps_sandbox
fake_answers OK TAG:3 OK 'TAG:"2" "4"' OK YES OK OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail "${O3[@]}" "$LD"
check_eq 'whiptail, apt and a store together: apt purged its application' 1 "$(real_removals)"
check_eq 'whiptail, apt and a store together: the Snap is gone, the Flatpaks stay' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=' "$(stores_present)"
check_eq 'whiptail, apt and a store together: two records' 2 "$(state_files | wc -l)"

echo "-- option 3 in windows: the stores, chosen with the others"
apps_sandbox
mkdir -p "$SB/tmp"; sandbox_chown
fake_zenity OK OUT:3 OK 'OUT:"1" "3" "4"' OK OK OK OK OK OK OUT:0
app_run '' "${GUI[@]}" TMPDIR="$SB/tmp" "$LD"
check_eq 'windows: the flow ends well' 0 "$RC"
check_eq 'windows: the three applications are gone' 'fs= fu= sn=' "$(stores_present)"
assert_contains 'windows: the list offers the Flatpak with its store and ID' "$(zt 4)" '[Flatpak: org.mozilla.firefox]'
assert_contains 'windows: and the Flatpak of the user' "$(zt 4)" '[Flatpak: org.gnome.gedit]'
assert_contains 'windows: and the Snap' "$(zt 4)" '[Snap: vlc]'
assert_contains 'windows: and the application of apt with its package' "$(zt 4)" '[fooapp]'
assert_contains 'windows: the plan lists the three, with the remote of the Flatpak' "$(zt 5)" $'  Flatpak: org.mozilla.firefox (system-wide, flathub)\n  Flatpak: org.gnome.gedit (your user only)\n  Snap: vlc (system-wide)'
assert_contains 'windows: the question starts on Cancel' "$(zt 6)" '--default-cancel'
assert_contains 'windows: a progress window for each application' "$(zt 8)" 'Uninstalling org.gnome.gedit...'
assert_contains 'windows: the result points to the record' "$(zt 10)" 'A record of what was removed was saved to:'
check_eq 'windows: one record, the completed one' '# Status: completed|1' "$(grep '^# Status' "$(rec_file)")|$(state_files | wc -l)"

apps_sandbox
mkdir -p "$SB/tmp"; sandbox_chown
fake_zenity OK OUT:3 OK 'OUT:"1" "3" "4"' OK CANCEL OUT:0
app_run '' "${GUI[@]}" TMPDIR="$SB/tmp" "$LD"
check_eq 'windows: Cancel leaves everything installed' 'fs=org.mozilla.firefox fu=org.gnome.gedit sn=vlc' "$(stores_present)"
check_eq 'windows: and runs no removal' 0 "$(removal_calls)"

finish
