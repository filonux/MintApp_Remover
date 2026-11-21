#!/usr/bin/env bash
# Test harness shared by every bash suite. It never touches the real system:
# each test gets a sandbox (new_sandbox) with its own HOME and stub apt-get,
# dpkg, dpkg-query, sudo, whiptail and sleep in front of the real commands.
# The program runs in an empty environment (env -i), as an unprivileged user
# even when the suite itself runs as root.
#
# Running the program:  app_run INPUT [VAR=val ...] [-- ARGS...]   (OUT, RC)
#                       app_eval CODE [VAR=val ...]  sources it and evals CODE
#                       app_eval_in INPUT CODE [VAR=val ...]  the same, with stdin
#                       app_run_pty / app_run_as_root  (see below)
# Checks:               check_eq, assert_contains, assert_not_contains,
#                       skip_case, finish
# Fake system:          fake_installed, fake_owner, fake_configfiles, fake_priority,
#                       fake_essential, fake_section, fake_dependents, fake_autoremovable,
#                       fake_pkginfo, fake_answers, fake_zenity, zenity_help_without,
#                       fake_fonts, fake_emoji_font (no emoji font unless asked),
#                       fake_sudo_password, make_desktop, fake_file, fake_age
# Cleaning:             a run that goes through app_run must never CONFIRM a cleaning: the "tmp"
#                       entry works on the real /tmp, where this very sandbox lives. Answer n
#                       (text) or CANCEL (whiptail). To confirm one, use app_eval_in on
#                       deep_clean with CLEAN_TMP_DIRS, CLEAN_LOG_DIR, CLEAN_CRASH_DIRS and
#                       CLEAN_APT_DIR in the sandbox, and allow_clean_confirm first. Two guards:
#                       the whiptail and zenity stubs refuse the "Clean"/"Limpiar" button unless
#                       allowed (a FAIL, nothing removed), and a run that leaves the sandbox
#                       without its state folder stops the suite (_guard_sandbox). The text
#                       mode has no stub to refuse: only the second guard covers it.
# Logs:                 apt_log, sudo_log, sudo_given, askpass_copy, askpass_modes,
#                       dpkg_calls, dpkgq_log, real_removals, state_files,
#                       clean_records, checklist_dump, zenity_calls, zenity_call,
#                       zenity_stdin, fc_list_calls
# shellcheck shell=bash
# The variables below are read by the suites that source this file.
# shellcheck disable=SC2034

H_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H_TESTS_DIR="$(cd "$H_LIB_DIR/.." && pwd)"
H_REPO_DIR="$(cd "$H_TESTS_DIR/.." && pwd)"
# MINTAPP_TEST_SCRIPT=file runs another copy of the program (mutation checks).
H_SCRIPT="${MINTAPP_TEST_SCRIPT:-$H_REPO_DIR/script/MintApp_Remover.sh}"
# The version the program under test declares: what --version and the header must print.
H_VERSION="$(sed -n '/^MINTAPP_VERSION=/{s/^[^"]*"\([^"]*\)".*/\1/p;q}' "$H_SCRIPT")"
H_BASH="$(command -v bash)"
H_ENV="$(command -v env)"
H_TIMEOUT="$(command -v timeout || true)"
H_SETPRIV="$(command -v setpriv || true)"
H_SYS_PATH="/usr/local/bin:/usr/bin:/bin"
H_APP_UID=65534
H_APP_GID=65534
H_TMP="$(mktemp -d "${TMPDIR:-/tmp}/mintapp-tests.XXXXXX")"
chmod 755 "$H_TMP"
SB=""
OUT=""
RC=0
T_PASS=0 T_FAIL=0 T_SKIP=0 T_GAP=0

_harness_cleanup() { rm -rf -- "$H_TMP"; }
trap _harness_cleanup EXIT

# ---------------------------------------------------------------- checks ----
_clip() {
    local s="${1//$'\n'/⏎}"
    if [ "${#s}" -gt 400 ]; then s="${s:0:400}..."; fi
    printf '%s' "$s"
}

_pass() { T_PASS=$((T_PASS + 1)); printf '  PASS  %s\n' "$1"; }
_fail() { T_FAIL=$((T_FAIL + 1)); printf '  FAIL  %s\n' "$1"; shift; local d; for d in "$@"; do printf '        %s\n' "$d"; done; }

# _guard_sandbox: run after every program run. A confirmation the whiptail stub refused is a FAIL
# (once); a sandbox that lost its state folder was removed by the program, which means a test
# confirmed a cleaning of the real /tmp: the suite stops there, because everything after it
# would fail with errors that hide the cause.
_guard_sandbox() {
    [ -n "$SB" ] || return 0
    if [ -s "$SB/state/unsafe.log" ]; then
        _fail "a run confirmed a cleaning through app_run (refused by the dialog stub)" \
            "use app_eval_in on deep_clean with the CLEAN_* folders in the sandbox, after allow_clean_confirm"
        : > "$SB/state/unsafe.log"
    fi
    [ -d "$SB/state" ] && return 0
    _fail "the sandbox was removed by the program: a test confirmed a cleaning of the real /tmp" \
        "answer n (text) or CANCEL (whiptail) in what goes through app_run; see the header of tests/lib/harness.sh"
    printf '  -- %s passed, %s failed, %s skipped, %s planned gaps (stopped)\n' "$T_PASS" "$T_FAIL" "$T_SKIP" "$T_GAP"
    exit 1
}

# check_eq LABEL EXPECTED ACTUAL
check_eq() {
    if [ "$2" = "$3" ]; then _pass "$1"; else _fail "$1" "expected: $(_clip "$2")" "actual:   $(_clip "$3")"; fi
}

# assert_contains LABEL TEXT NEEDLE (fixed string)
assert_contains() {
    if [[ "$2" == *"$3"* ]]; then _pass "$1"; else _fail "$1" "missing: $(_clip "$3")" "in:      $(_clip "$2")"; fi
}

assert_not_contains() {
    if [[ "$2" != *"$3"* ]]; then _pass "$1"; else _fail "$1" "unexpected: $(_clip "$3")" "in:         $(_clip "$2")"; fi
}

skip_case() { T_SKIP=$((T_SKIP + 1)); printf '  SKIP  %s\n' "$1"; }

# finish: prints the totals (same line as the python suites) and sets the status.
# No suite has planned gaps now (T_GAP stays 0); the field stays because run_all.sh reads it.
finish() {
    printf '  -- %s passed, %s failed, %s skipped, %s planned gaps\n' "$T_PASS" "$T_FAIL" "$T_SKIP" "$T_GAP"
    [ "$T_FAIL" -eq 0 ]
}

# --------------------------------------------------------------- sandbox ----
sandbox_chown() {
    if [ "$(id -u)" -eq 0 ]; then chown -R "$H_APP_UID:$H_APP_GID" "$SB" 2>/dev/null || true; fi
    return 0
}

# _stub NAME: writes the script on stdin as $SB/bin/NAME, with @STATE@ replaced.
_stub() {
    sed "s|@STATE@|$SB/state|g" > "$SB/bin/$1"
    chmod 755 "$SB/bin/$1"
}

new_sandbox() {
    [ -z "$SB" ] || rm -rf -- "$SB"
    SB="$(mktemp -d "$H_TMP/sb.XXXXXX")"
    chmod 755 "$SB"
    mkdir -p "$SB/home" "$SB/state" "$SB/apps" "$SB/bin" "$SB/emptybin"
    : > "$SB/state/installed"; : > "$SB/state/configfiles"; : > "$SB/state/owners"
    : > "$SB/state/priority"; : > "$SB/state/essential"; : > "$SB/state/dependents"
    : > "$SB/state/autoremovable"; : > "$SB/state/pkginfo"; : > "$SB/state/answers"; : > "$SB/state/section"
    : > "$SB/state/apt.log"; : > "$SB/state/sudo.log"; : > "$SB/state/dpkg.log"; : > "$SB/state/dpkgq.log"
    : > "$SB/state/whiptail.log"; : > "$SB/state/whiptail.args"
    : > "$SB/state/zenity.args"; : > "$SB/state/zenity.stdin"; : > "$SB/state/zenity.answers"
    : > "$SB/state/sudo.given"; : > "$SB/state/unsafe.log"
    BASE_ENV=(HOME="$SB/home" PATH="$SB/bin:$H_SYS_PATH" TERM=xterm USER=tester LOGNAME=tester
              MINTAPP_LAUNCHER_DIRS="$SB/apps" MINTAPP_PM=apt)
    # H_UNICODE=1, set by a suite, makes the program run with Unicode symbols (the default under env -i is ASCII).
    [ -z "${H_UNICODE:-}" ] || BASE_ENV+=(MINTAPP_ASCII=0)

    _stub sleep <<'EOF'
#!/bin/sh
exit 0
EOF
    _stub sudo <<'EOF'
#!/bin/sh
# Like sudo: -A asks for the password with the program SUDO_ASKPASS (up to three tries) when
# fake_sudo_password set one; the rights last for the rest of the run (the ticket). -v only asks.
S='@STATE@'
echo "sudo $*" >> "$S/sudo.log"
ask=0; check=0
while [ "$#" -gt 0 ]; do
    case "$1" in -A) ask=1 ;; -v) check=1 ;; -n) ;; *) break ;; esac
    shift
done
if [ "$ask" = 1 ] && [ -n "${SUDO_ASKPASS:-}" ]; then
    cp -- "$SUDO_ASKPASS" "$S/askpass.copy" 2>/dev/null
    stat -c '%a %U' -- "$SUDO_ASKPASS" "$(dirname "$SUDO_ASKPASS")" > "$S/askpass.modes" 2>/dev/null
fi
if [ "$ask" = 1 ] && [ -f "$S/sudo.password" ] && [ ! -f "$S/sudo.ticket" ]; then
    [ -n "${SUDO_ASKPASS:-}" ] || { echo "sudo: no askpass program specified, try setting SUDO_ASKPASS" >&2; exit 1; }
    tries=0
    while [ "$tries" -lt 3 ]; do
        tries=$((tries + 1))
        pw=$("$SUDO_ASKPASS" "[sudo] password for tester: ") || { echo "sudo: no password was provided" >&2; exit 1; }
        echo "$pw" >> "$S/sudo.given"
        if [ "$pw" = "$(cat "$S/sudo.password")" ]; then : > "$S/sudo.ticket"; break; fi
        echo "Sorry, try again." >&2
    done
    [ -f "$S/sudo.ticket" ] || { echo "sudo: 3 incorrect password attempts" >&2; exit 1; }
fi
[ "$check" = 0 ] || exit 0
exec env "$@"
EOF
    _stub dpkg-query <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
fmt=""; pkgs=""; show=""
for a in "$@"; do
    case "$a" in
        -f=*) fmt="${a#-f=}" ;;
        --showformat=*) fmt="${a#--showformat=}" ;;
        -W|--show) show=1 ;;
        -*) ;;
        *) pkgs="$pkgs $a" ;;
    esac
done
# Without names, -W lists them all (the ones in "installed", which also has those that kept their configuration).
[ -n "$pkgs" ] || [ -z "$show" ] || pkgs=$(tr '\n' ' ' < "$S/installed")
rc=0
set -- $pkgs; echo "dpkg-query $#" >> "$S/dpkgq.log"
for p in $pkgs; do
    if ! grep -qx -- "$p" "$S/installed"; then
        echo "dpkg-query: no packages found matching $p" >&2; rc=1; continue
    fi
    if grep -qx -- "$p" "$S/configfiles"; then status="deinstall ok config-files"; abbr="rc "; else status="install ok installed"; abbr="ii "; fi
    prio=$(awk -F'\t' -v p="$p" '$1==p{print $2}' "$S/priority" | head -n1); [ -n "$prio" ] || prio=optional
    if grep -qx -- "$p" "$S/essential"; then ess=yes; else ess=""; fi
    sec=$(awk -F'\t' -v p="$p" '$1==p{print $2}' "$S/section" | head -n1); [ -n "$sec" ] || sec=misc
    info=$(awk -F'\t' -v p="$p" '$1==p{print $2 "\t" $3 "\t" $4}' "$S/pkginfo" | head -n1)
    [ -n "$info" ] || info=$(printf '1.0\t1024\tFake package')
    ver=$(printf '%s' "$info" | cut -f1); size=$(printf '%s' "$info" | cut -f2); summ=$(printf '%s' "$info" | cut -f3)
    line="$fmt"
    line=$(printf '%s' "$line" | sed -e "s|\${db:Status-Abbrev}|$abbr|g" -e "s|\${binary:Package}|$p|g" -e "s|\${Status}|$status|g" -e "s|\${Priority}|$prio|g" \
        -e "s|\${Essential}|$ess|g" -e "s|\${Section}|$sec|g" -e "s|\${Package}|$p|g" -e "s|\${Version}|$ver|g" \
        -e "s|\${Installed-Size}|$size|g" -e "s|\${binary:Summary}|$summ|g")
    printf '%b' "$line"
done
exit $rc
EOF
    _stub dpkg <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
case "$1" in
    -S|--search)
        shift
        echo "dpkg -S $#" >> "$S/dpkg.log"
        rc=0
        for p in "$@"; do
            o=$(awk -F'\t' -v p="$p" '$1==p{print $2}' "$S/owners" | paste -sd, - | sed 's/,/, /g')
            if [ -n "$o" ]; then echo "$o: $p"; else echo "dpkg-query: no path found matching pattern $p" >&2; rc=1; fi
        done
        exit $rc ;;
esac
exit 0
EOF
    _stub apt-get <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
echo "apt-get $*" >> "$S/apt.log"
sim=0; action=""; pkgs=""
for a in "$@"; do
    case "$a" in
        -s|--simulate|--just-print|--dry-run) sim=1 ;;
        -*) ;;
        *) if [ -z "$action" ]; then action="$a"; else pkgs="$pkgs $a"; fi ;;
    esac
done
on() { [ -n "$1" ] && [ "$1" != 0 ]; }
if [ "$sim" = 1 ]; then
    if on "${FAKE_APT_SIM_FAIL:-}"; then
        echo "E: Unable to locate package ${pkgs# }" >&2; exit 100
    fi
    n=$(cat "$S/apt.sims" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$S/apt.sims"
    printf '%s\n' "NOTE: This is only a simulation!" "      apt-get needs root privileges for real execution." \
        "      Keep also in mind that locking is deactivated," "      so don't depend on the relevance to the real current situation!"
    echo "Reading package lists..."; echo "Building dependency tree..."
    out=""
    case "$action" in
        purge)
            for p in $pkgs; do
                if grep -qx -- "$p" "$S/installed"; then
                    out="$out
Purg $p [1.0]"
                    for d in $(awk -v p="$p" '$1==p{print $2}' "$S/dependents"); do out="$out
Purg $d [1.0]"; done
                else
                    echo "Package '$p' is not installed, so not removed"
                fi
            done ;;
        autoremove)
            for p in $(cat "$S/autoremovable"); do
                grep -qx -- "$p" "$S/installed" && out="$out
Remv $p [1.0]"
            done ;;
    esac
    if on "${FAKE_APT_DRIFT:-}" && [ "$n" -ge 2 ]; then out="$out
Purg drifted-pkg [1.0]"; fi
    if [ -n "$out" ]; then
        echo "The following packages will be REMOVED:"
        printf '%s\n' "$out" | sed -n 's/^\(Purg\|Remv\) \([^ ]*\) .*/  \2*/p'
        printf '%s\n' "$out" | sed '/^$/d'
    fi
    exit 0
fi
if on "${FAKE_APT_FAIL:-}" && { [ -z "${FAKE_APT_FAIL_ACTION:-}" ] || [ "$FAKE_APT_FAIL_ACTION" = "$action" ]; }; then
    echo "E: Sub-process /usr/bin/dpkg returned an error code (1)" >&2
    exit "$FAKE_APT_FAIL"
fi
case "$action" in
    purge)
        for p in $pkgs; do
            for d in $p $(awk -v p="$p" '$1==p{print $2}' "$S/dependents"); do
                grep -vx -- "$d" "$S/installed" > "$S/installed.new"; mv "$S/installed.new" "$S/installed"
                grep -vx -- "$d" "$S/configfiles" > "$S/configfiles.new"; mv "$S/configfiles.new" "$S/configfiles"
            done
            echo "Removing $p ..."
        done ;;
    autoremove)
        for p in $(cat "$S/autoremovable"); do
            grep -vx -- "$p" "$S/installed" > "$S/installed.new"; mv "$S/installed.new" "$S/installed"
            echo "Removing $p ..."
        done
        : > "$S/autoremovable" ;;
    *) echo "Reading package lists..." ;;
esac
exit 0
EOF
    _stub whiptail <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
{ printf 'whiptail '; for a in "$@"; do printf '%s ' "$a"; done; printf '\n'; } >> "$S/whiptail.log"
# The same call with one argument per line, closed by a marker line. A line break inside an
# argument (the wrapped text of a box) is written as the control character RS (octal 036).
{ for a in "$@"; do printf '%s\n' "$(printf '%s' "$a" | tr '\n' '\036')"; done; echo '@@END@@'; } >> "$S/whiptail.args"
# Like the real whiptail (popt): the geometry and the items that follow a box option are positional, so one that
# starts with "-" is taken as an option and stops the dialog, unless "--" comes first.
skip=0; opts=1
for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    [ "$opts" = 1 ] || continue
    case "$a" in
        --) opts=0 ;;
        --title|--backtitle|--ok-button|--cancel-button|--yes-button|--no-button|--default-item|--msgbox|--yesno|--inputbox|--menu|--checklist|--radiolist) skip=1 ;;
        --scrolltext|--clear|--notags|--nocancel|--defaultno) ;;
        -?*) echo "$a: unknown option" >&2; exit 1 ;;
    esac
done
# The button that starts a cleaning ("Clean", "Limpiar"): a yes to it is refused (as a cancel) unless
# the test allowed it (allow_clean_confirm) because it works in folders of the sandbox.
yes=""; prev=""
for a in "$@"; do [ "$prev" != --yes-button ] || yes="$a"; prev="$a"; done
n=$(cat "$S/answers.pos" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$S/answers.pos"
ans=$(sed -n "${n}p" "$S/answers")
case "$ans" in
    OK|YES)
        case "$yes" in
            Clean|Limpiar)
                [ -f "$S/clean.confirm.ok" ] || { echo "whiptail: yes to $yes refused" >> "$S/unsafe.log"; exit 1; } ;;
        esac
        exit 0 ;;
    NO|CANCEL) exit 1 ;;
    TAG:*) printf '%s' "${ans#TAG:}" >&2; exit 0 ;;
    *) exit 255 ;;
esac
EOF
    _stub zenity <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
# What the program asks zenity once, to know it can rely on it (zenity_usable).
if [ "$1" = "--help-all" ]; then
    { printf '%s\n' 'Usage:' '  zenity [OPTION...]' '' \
        '  --checklist                  Create a list dialog with check boxes' \
        '  --hide-column=NUMBER         Hide a specific column' \
        '  --print-column=NUMBER        Print a specific column' \
        '  --no-markup                  Do not enable Pango markup' \
        '  --default-cancel             Give cancel button focus by default' \
        '  --extra-button=TEXT          Add an extra button' \
        '  --switch                     Suppress OK and Cancel buttons' \
        '  --text-info                  Display text information dialog' \
        '  --icon=ICON-NAME             Set the icon name' \
        '  --hide-header                Hide the column headers'; } |
        if [ -s "$S/zenity.nohelp" ]; then grep -v -F -f "$S/zenity.nohelp"; else cat; fi
    exit 0
fi
# The call with one argument per line, closed by a marker line; a line break inside an
# argument is written as the control character RS (octal 036).
{ for a in "$@"; do printf '%s\n' "$(printf '%s' "$a" | tr '\n' '\036')"; done; echo '@@END@@'; } >> "$S/zenity.args"
# Like the real one (GLib): an argument that starts with "-" is an option and must be a known
# one; "--" does not end the options. A list cell such as "-x" therefore stops the dialog.
for a in "$@"; do
    case "$a" in
        --title=*|--text=*|--width=*|--height=*|--ok-label=*|--cancel-label=*|--entry-text=*|--column=*|\
        --hide-column=*|--print-column=*|--separator=*|--extra-button=*|--timeout=*|--percentage=*|--icon=*) ;;
        --info|--error|--question|--entry|--list|--checklist|--no-markup|--default-cancel|--switch|--text-info|\
        --progress|--pulsate|--auto-close|--no-cancel|--password|--hide-text|--modal|--hide-header) ;;
        -?*) echo "Unknown option $a" >&2; exit 1 ;;
    esac
done
case " $* " in
    *" --text-info "*) { cat; echo '@@END@@'; } >> "$S/zenity.stdin" ;;
    # A progress window takes no answer: it only shows what it reads until its input ends.
    *" --progress "*) { cat; echo '@@END@@'; } >> "$S/zenity.stdin"; exit 0 ;;
esac
n=$(cat "$S/zenity.pos" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$S/zenity.pos"
ans=$(sed -n "${n}p" "$S/zenity.answers")
# The button that starts a cleaning ("Clean", "Limpiar"), as an answer or as the OK button: refused
# (as a cancel) unless the test allowed it (allow_clean_confirm). Same rule as the whiptail stub.
clean=0
case "$ans" in
    EXTRA:Clean|EXTRA:Limpiar|OUT:Clean|OUT:Limpiar) clean=1 ;;
    OK) for a in "$@"; do case "$a" in --ok-label=Clean|--ok-label=Limpiar) clean=1 ;; esac; done ;;
esac
if [ "$clean" -eq 1 ] && [ ! -f "$S/clean.confirm.ok" ]; then
    echo "zenity: yes to a cleaning refused" >> "$S/unsafe.log"; exit 1
fi
case "$ans" in
    OK) exit 0 ;;
    OUT:*) printf '%s' "${ans#OUT:}"; exit 0 ;;
    EXTRA:*) printf '%s' "${ans#EXTRA:}"; exit 1 ;;
    NODISPLAY) echo "Gtk-WARNING **: cannot open display: " >&2; exit 1 ;;
    BROKEN) echo "zenity: internal error" >&2; exit 5 ;;
    *) exit 1 ;;     # CANCEL, and a window closed when the answers ran out
esac
EOF
    # fc-list: the system's fonts are the ones of fake_fonts (none by default), so that whether the
    # windows draw emoji (gui_emoji) never depends on the machine that runs the tests. It answers
    # like fontconfig to the two filters the program uses: ":charset=HEX" keeps the fonts that have
    # that character and ":color=True" the color ones; every other pattern is ignored. One line
    # per call in fc-list.log.
    _stub fc-list <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
echo "fc-list $*" >> "$S/fc-list.log"
glyph=0; color=0
for a in "$@"; do
    case "$a" in *charset=1f9fc*) glyph=1 ;; esac
    case "$a" in *color=True*) color=1 ;; esac
done
while IFS='|' read -r family is_color has_glyph; do
    [ -n "$family" ] || continue
    [ "$color" -eq 0 ] || [ "$is_color" = 1 ] || continue
    [ "$glyph" -eq 0 ] || [ "$has_glyph" = 1 ] || continue
    echo "$family"
done < "$S/fonts"
exit 0
EOF
    : > "$SB/state/fonts"; : > "$SB/state/fc-list.log"
    sandbox_chown
}

# ------------------------------------------------------------- fake system ----
_list_add() { printf '%s\n' "$2" >> "$SB/state/$1"; }

fake_installed() {
    local p
    for p in "$@"; do grep -qx -- "$p" "$SB/state/installed" || _list_add installed "$p"; done
    sandbox_chown
}
fake_configfiles()   { local p; for p in "$@"; do _list_add configfiles "$p"; done; sandbox_chown; }
fake_owner()         { printf '%s\t%s\n' "$1" "$2" >> "$SB/state/owners"; sandbox_chown; }
fake_priority()      { printf '%s\t%s\n' "$1" "$2" >> "$SB/state/priority"; sandbox_chown; }
# fake_section PACKAGE SECTION: the Section dpkg-query reports (default "misc").
fake_section()       { printf '%s\t%s\n' "$1" "$2" >> "$SB/state/section"; sandbox_chown; }
fake_essential()     { local p; for p in "$@"; do _list_add essential "$p"; done; sandbox_chown; }
fake_dependents()    { local p="$1" d; shift; for d in "$@"; do printf '%s %s\n' "$p" "$d" >> "$SB/state/dependents"; done; sandbox_chown; }
fake_autoremovable() { fake_installed "$@"; local p; for p in "$@"; do _list_add autoremovable "$p"; done; sandbox_chown; }
# fake_pkginfo PACKAGE VERSION SIZE_KB SUMMARY
fake_pkginfo()       { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$SB/state/pkginfo"; sandbox_chown; }

# fake_answers ANSWER...: what the whiptail stub answers, one per dialog: OK or
# YES (status 0), NO or CANCEL (1), ESC (255), TAG:x (prints x, status 0).
# When the answers run out it behaves as Esc.
fake_answers() {
    : > "$SB/state/answers"; rm -f "$SB/state/answers.pos"
    local a
    for a in "$@"; do printf '%s\n' "$a" >> "$SB/state/answers"; done
    sandbox_chown
}

# fake_zenity ANSWER...: what the zenity stub does, one answer per window: OK (status 0),
# CANCEL (1: Cancel, Esc, a closed window), OUT:text (prints text, status 0: a list row, an
# entry), EXTRA:label (prints label, status 1: an extra button), NODISPLAY (1 with the message
# of an unreachable display), BROKEN (status 5). When the answers run out it is CANCEL.
# The program only uses zenity if DISPLAY is set: give it as VAR=val. It also empties the log
# of calls, so zenity_calls counts from here and not from the whole test.
fake_zenity() {
    : > "$SB/state/zenity.answers"; : > "$SB/state/zenity.args"; : > "$SB/state/zenity.stdin"
    rm -f "$SB/state/zenity.pos"
    local a
    for a in "$@"; do printf '%s\n' "$a" >> "$SB/state/zenity.answers"; done
    sandbox_chown
}

# allow_clean_confirm: the whiptail stub of this sandbox accepts a yes to the button that starts a
# cleaning. Only for runs that clean folders of the sandbox (app_eval_in on deep_clean).
allow_clean_confirm() { : > "$SB/state/clean.confirm.ok"; sandbox_chown; }

# zenity_help_without OPTION...: from now on the help of the zenity stub leaves these options out,
# like a zenity that lacks them (the stub still accepts them); with no argument it lists all again.
zenity_help_without() {
    if [ "$#" -gt 0 ]; then printf '%s\n' "$@" > "$SB/state/zenity.nohelp"; else : > "$SB/state/zenity.nohelp"; fi
    sandbox_chown
}

# fake_sudo_password PASSWORD: sudo now needs this password when it is run with -A (the windows
# ask for it through the zenity stub: answer it with OUT:text; Cancel is a closed window). With no
# call, or fake_sudo_password "" , sudo needs none. The password given is in sudo_given.
fake_sudo_password() {
    rm -f "$SB/state/sudo.ticket"; : > "$SB/state/sudo.given"
    if [ -n "${1:-}" ]; then printf '%s\n' "$1" > "$SB/state/sudo.password"; else rm -f "$SB/state/sudo.password"; fi
    sandbox_chown
}

# fake_fonts FONT...: the fonts the fc-list stub knows, each "FAMILY|COLOR|GLYPH" (COLOR 1 = a
# color font, GLYPH 1 = it has U+1F9FC, the newest emoji of the menus). With no argument the
# system has none, which is how every sandbox starts: the windows draw no emoji. It also empties
# the log of calls to fc-list, so fc_list_calls counts from here.
fake_fonts() {
    : > "$SB/state/fonts"; : > "$SB/state/fc-list.log"
    local f
    for f in "$@"; do printf '%s\n' "$f" >> "$SB/state/fonts"; done
    sandbox_chown
}
# fake_emoji_font: the system has a color emoji font that draws every emoji of the menus.
fake_emoji_font() { fake_fonts 'Noto Color Emoji|1|1'; }
# fc_list_calls: how many times the program asked fontconfig (fc-list.log has one line per call).
fc_list_calls() { grep -c '^fc-list ' "$SB/state/fc-list.log" 2>/dev/null || true; }

# make_desktop FILE NAME [EXTRA LINE...]: a menu launcher in $SB/apps.
make_desktop() {
    local file="$1" name="$2"
    shift 2
    { printf '[Desktop Entry]\nType=Application\nName=%s\n' "$name"; local l; for l in "$@"; do printf '%s\n' "$l"; done; } > "$SB/apps/$file"
    sandbox_chown
}

# fake_file PATH [SIZE_BYTES]: a file (and its folders) with that size.
fake_file() {
    mkdir -p "$(dirname -- "$1")"
    head -c "${2:-1024}" /dev/zero > "$1"
    sandbox_chown
}

# fake_age PATH DAYS: makes the file or folder that many days old.
fake_age() { touch -d "$2 days ago" -- "$1"; }

# ------------------------------------------------------------------- logs ----
apt_log()   { cat "$SB/state/apt.log" 2>/dev/null || true; }
sudo_log()  { cat "$SB/state/sudo.log" 2>/dev/null || true; }
# sudo_given: what was typed in the password window, one try per line.
sudo_given() { cat "$SB/state/sudo.given" 2>/dev/null || true; }
# askpass_copy: the password helper as sudo -A got it; askpass_modes: its mode and owner and
# those of its folder (two lines).
askpass_copy()  { cat "$SB/state/askpass.copy" 2>/dev/null || true; }
askpass_modes() { cat "$SB/state/askpass.modes" 2>/dev/null || true; }
# dpkgq_log: one line "dpkg-query N" per call of dpkg-query, N being the packages it was asked about.
dpkgq_log() { cat "$SB/state/dpkgq.log" 2>/dev/null || true; }
dpkg_calls() { local n; n="$(grep -c '^dpkg -S ' "$SB/state/dpkg.log" 2>/dev/null)" || n=0; printf '%s\n' "${n:-0}"; }
real_removals() { local n; n="$(grep -cE '^apt-get (purge|autoremove) -y' "$SB/state/apt.log" 2>/dev/null)" || n=0; printf '%s\n' "${n:-0}"; }
state_files() { ls -1 "$SB"/home/.local/state/mintapp-remover/removal-*.txt 2>/dev/null || true; }
clean_records() { ls -1 "$SB"/home/.local/state/mintapp-remover/clean-*.txt 2>/dev/null || true; }

# checklist_dump [N]: the N-th (default: the last) --checklist call whiptail got. The first line is
# "HEIGHT WIDTH ROWS"; then one "TAG<TAB>LABEL<TAB>STATE" line per item.
checklist_dump() {
    awk -v want="${1:-0}" '
        function finish(   i, j, k) {
            for (i = 1; i <= n; i++) if (a[i] == "--checklist") break
            if (i > n) return
            calls++
            j = i + 2; if (a[j] == "--") j++
            rec[calls] = a[j] " " a[j + 1] " " a[j + 2]; items[calls] = ""
            for (k = j + 3; k + 2 <= n; k += 3) items[calls] = items[calls] a[k] "\t" a[k + 1] "\t" a[k + 2] "\n"
        }
        $0 == "@@END@@" { finish(); n = 0; next }
        { a[++n] = $0 }
        END { pick = (want == 0) ? calls : want; printf "%s\n%s", rec[pick], items[pick] }
    ' "$SB/state/whiptail.args"
}

# zenity_calls: how many times zenity ran (the help check is not counted).
zenity_calls() { grep -c '^@@END@@$' "$SB/state/zenity.args" 2>/dev/null || true; }
# zenity_call [N]: the arguments of the N-th call (default: the last), one per line.
zenity_call() {
    awk -v want="${1:-0}" '
        $0 == "@@END@@" { calls++; if (want == 0 || calls == want) last = cur; cur = ""; next }
        { cur = cur $0 "\n" }
        END { printf "%s", last }
    ' "$SB/state/zenity.args"
}
# zenity_stdin [N]: the text the N-th --text-info window got on stdin (default: the last).
zenity_stdin() {
    awk -v want="${1:-0}" '
        $0 == "@@END@@" { calls++; if (want == 0 || calls == want) last = cur; cur = ""; next }
        { cur = cur $0 "\n" }
        END { printf "%s", last }
    ' "$SB/state/zenity.stdin"
}

# ----------------------------------------------------------------- running ----
# _exec INPUT TIMEOUT ENV... -- COMMAND...: runs COMMAND in an empty environment
# (BASE_ENV plus ENV...) with INPUT as stdin; OUT gets stdout and stderr, RC the status.
# Commands are given by absolute path: the PATH of a test may hold nothing at all.
_exec() {
    local input="$1" tmo="$2"; shift 2
    local -a envs=() pre=()
    local e
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    # The program sets UI_ENGINE and HAVE_WHIPTAIL when it loads (select_interface), so the environment
    # cannot choose the interface: the run would use another one than the test says. Set them in the
    # code given to app_eval.
    for e in "${envs[@]+"${envs[@]}"}"; do
        case "$e" in
            UI_ENGINE=*|HAVE_WHIPTAIL=*) _fail "the environment cannot set the interface ($e)" \
                "put it in the code given to app_eval: UI_ENGINE=...; HAVE_WHIPTAIL=..." ;;
        esac
    done
    # The simulation counter (FAKE_APT_DRIFT) starts again with every run.
    rm -f -- "$SB/state/apt.sims" "$SB/state/sudo.ticket"
    # So does the configuration: the program remembers that the navigation help was
    # shown (help_seen) and the language, so a run would start differently from the
    # one before. H_KEEP_CONFIG=1, set by a suite that tests the configuration, keeps it.
    [ "${H_KEEP_CONFIG:-0}" = 1 ] || rm -f -- "$SB/home/.config/mintapp-remover/config"
    if [ "$(id -u)" -eq 0 ] && [ "${H_AS_ROOT:-0}" != 1 ]; then
        pre=("$H_SETPRIV" --reuid="$H_APP_UID" --regid="$H_APP_GID" --clear-groups)
    fi
    OUT="$(printf '%s' "$input" | "$H_TIMEOUT" "$tmo" "$H_ENV" -i "${BASE_ENV[@]}" "${envs[@]+"${envs[@]}"}" \
        "${pre[@]+"${pre[@]}"}" "$@" 2>&1)" && RC=0 || RC=$?
    _guard_sandbox
}

# app_run INPUT [VAR=val ...] [-- ARGS...]: runs the program with INPUT on stdin.
app_run() {
    local input="$1"; shift
    local -a envs=() args=()
    while [ "$#" -gt 0 ]; do
        if [ "$1" = "--" ]; then shift; args=("$@"); break; fi
        envs+=("$1"); shift
    done
    _exec "$input" 120 "${envs[@]+"${envs[@]}"}" -- "$H_BASH" "$H_SCRIPT" "${args[@]+"${args[@]}"}"
}

# app_eval_in INPUT CODE [VAR=val ...]: sources the program (main does not run)
# and evals CODE, with INPUT on stdin (for code that reads, such as a menu loop).
app_eval_in() {
    local input="$1" code="$2"; shift 2
    # The single quotes are on purpose: the child shell expands $1 and $2.
    # shellcheck disable=SC2016
    _exec "$input" 120 "$@" -- "$H_BASH" -c 'source "$1"; eval "$2"' bash "$H_SCRIPT" "$code"
}

# app_eval CODE [VAR=val ...]: the same with nothing on stdin.
app_eval() {
    local code="$1"; shift
    app_eval_in '' "$code" "$@"
}

# app_run_pty INPUT [VAR=val ...]: like app_run but on a pseudo-terminal (util-linux
# "script"), for what bash only does on a terminal, such as showing a read prompt.
app_run_pty() {
    local input="$1"; shift
    local cmd
    printf -v cmd '%q %q' "$H_BASH" "$H_SCRIPT"
    _exec "$input" 60 "$@" -- "$(command -v script)" -qec "$cmd" /dev/null
    OUT="${OUT//$'\r'/}"
}

# app_run_as_root INPUT: runs it as the real root (the program must refuse).
app_run_as_root() {
    H_AS_ROOT=1 _exec "$1" 60 -- "$H_BASH" "$H_SCRIPT"
}
