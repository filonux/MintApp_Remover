#!/usr/bin/env bash
# Graphical dialogs (FU.5): the "gui" engine, which runs zenity.
#   1. With the zenity stub of the harness (no display needed): when zenity can be
#      used, which engine starts, how every dialog is mapped to zenity's options and
#      statuses, and the screens of the program end to end.
#   2. Smoke test with the real zenity in Xvfb, a window manager and xdotool: what
#      Enter, Tab and Esc really do in each kind of window; then, with the real xterm,
#      the start from the launcher with the terminal saved. Skipped, with the reason,
#      when one of those tools is missing.
# SC2016 is off for the whole file: the code given to app_eval is single-quoted on purpose,
# because the program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

new_sandbox
# ICON_NAME: the file in assets/ that the program falls back on when its embedded icon is not there
# (ICON_ASSET in the program); the cases below set it up beside a copy of the program.
ICON_NAME="$(sed -n 's/^ICON_ASSET="\([^"]*\)".*/\1/p' "$H_SCRIPT" | head -n 1)"
[ -n "$ICON_NAME" ] || { echo "ICON_ASSET not found in the program" >&2; exit 1; }
# The program with windows, in English, with Unicode symbols whatever the locale is.
GUI=(DISPLAY=:99 MINTAPP_UI=gui MINTAPP_ASCII=0 MINTAPP_LANG=en)

# value_of LABEL EXPECTED: the text between << and >> of OUT.
value_of() { local v="${OUT#*<<}"; check_eq "$1" "$2" "${v%%>>*}"; }

# plain: OUT without colors. The plain-text menu colors the key and the label of each option apart
# (F7.0), so "1. Detect applications" is not one piece in the raw output.
plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }

# zj [N]: the arguments of the N-th zenity call (default: the last) in one line, each one
# between "~" and with its line breaks as "|", so that "~--info~" finds a whole argument.
zj() { printf '~%s' "$(zenity_call "$@" | tr '\036\n' '|~')"; }
# has LABEL ARG [N]: that call has the argument ARG.
has() { assert_contains "$1" "$(zj "${3:-0}")" "~$2~"; }
lacks() { assert_not_contains "$1" "$(zj "${3:-0}")" "~$2~"; }

# dlg CODE [VAR=val ...]: CODE (a dialog call) runs with zenity usable. OUT is "status|answer":
# the status of the dialog and what it wrote to stderr.
dlg() {
    local code="$1"; shift
    app_eval "zenity_usable; ans=\"\$($code 3>&1 1>&2 2>&3)\"; echo \"\$?|\$ans\"" "${GUI[@]}" "$@"
}

# A zenity of our own in $SB/alt, which comes first in the PATH of the cases that ask for it.
ALT_PATH() { printf '%s' "$SB/alt:$SB/bin:$H_SYS_PATH"; }
HELP_OPTS=(--checklist --hide-column --print-column --no-markup --default-cancel --extra-button --switch --text-info)
# alt_zenity [WITHOUT [EXTRA...]]: a zenity whose help lists every option the dialogs rely on, but
# WITHOUT, and each EXTRA line besides (an optional option such as --icon=X, or one that is not).
alt_zenity() {
    local opt body="" without="${1:-}"
    [ "$#" -eq 0 ] || shift
    for opt in "${HELP_OPTS[@]}"; do
        [ "$opt" = "$without" ] || body+="printf '%s\n' '  $opt=VALUE   x'; "
    done
    for opt in "$@"; do body+="printf '%s\n' '  $opt   x'; "; done
    mkdir -p "$SB/alt"
    printf '#!/bin/sh\nif [ "$1" = "--help-all" ]; then echo "Usage:"; %s exit 0; fi\nexit 0\n' "$body" > "$SB/alt/zenity"
    chmod 755 "$SB/alt/zenity"; sandbox_chown
}

echo "-- zenity_usable: when the windows can be used"
usable() {  # usable LABEL EXPECTED [VAR=val ...]: status of zenity_usable (0 = usable)
    local label="$1" expected="$2"; shift 2
    app_eval 'zenity_usable; printf "<<%s>>" "$?"' "$@"
    value_of "$label" "$expected"
}
usable 'a zenity and a display: usable'                         0 DISPLAY=:99
usable 'a Wayland session alone is enough'                      0 WAYLAND_DISPLAY=wayland-0
usable 'no display and no Wayland session: not usable'          1
usable 'an empty DISPLAY is no display'                         1 DISPLAY=
usable 'no zenity command: not usable'                          1 DISPLAY=:99 PATH="$SB/emptybin"
for opt in "${HELP_OPTS[@]}"; do
    alt_zenity "$opt"
    usable "a zenity whose help lacks $opt: not usable"         1 DISPLAY=:99 PATH="$(ALT_PATH)"
done
alt_zenity
usable 'a zenity whose help lists everything: usable'           0 DISPLAY=:99 PATH="$(ALT_PATH)"
mkdir -p "$SB/alt"
printf '#!/bin/sh\nif [ "$1" = "--help-all" ]; then printf "%%s\\n" "  --checklist-extra" "  --hide-column-x" "  --print-columns" "  --no-markups" "  --default-cancelled" "  --extra-buttons" "  --switches" "  --text-information"; exit 0; fi\nexit 0\n' > "$SB/alt/zenity"
chmod 755 "$SB/alt/zenity"; sandbox_chown
usable 'an option only as the start of another one does not count' 1 DISPLAY=:99 PATH="$(ALT_PATH)"
printf '#!/bin/sh\nexit 1\n' > "$SB/alt/zenity"
usable 'a help that fails: not usable'                          1 DISPLAY=:99 PATH="$(ALT_PATH)"

echo "-- GUI_OPTS: the optional options of zenity (--icon, --hide-header)"
opts() {  # opts LABEL EXPECTED [VAR=val ...]: GUI_OPTS once zenity_usable ran
    local label="$1" expected="$2"; shift 2
    app_eval 'zenity_usable; printf "<<%s>>" "$GUI_OPTS"' "$@"
    value_of "$label" "$expected"
}
opts 'a help that lists both: both are known'                 ' --icon --hide-header ' DISPLAY=:99
zenity_help_without --icon
opts 'a help without --icon: only --hide-header'              ' --hide-header ' DISPLAY=:99
zenity_help_without --hide-header
opts 'a help without --hide-header: only --icon'              ' --icon ' DISPLAY=:99
zenity_help_without --icon --hide-header
opts 'a help with neither: none'                              ' ' DISPLAY=:99
usable 'a help with neither: zenity is still usable'          0 DISPLAY=:99
zenity_help_without
alt_zenity '' --icons=X --hide-headers
opts 'an option only as the start of another one does not count' ' ' DISPLAY=:99 PATH="$(ALT_PATH)"
alt_zenity --checklist --icon=X
opts 'a zenity that is not usable has no optional options'    '' DISPLAY=:99 PATH="$(ALT_PATH)"
rm -rf "$SB/alt"
app_eval 'zenity_usable; gui_opt --icon; a=$?; gui_opt --hide-header; b=$?; gui_opt --ic; c=$?; gui_opt --icon-name; d=$?; printf "<<%s %s %s %s>>" $a $b $c $d' DISPLAY=:99
value_of 'gui_opt: yes for what the help lists, no for the start of a name or a longer one' '0 0 1 1'
app_eval 'zenity_usable; gui_opt --icon; printf "<<%s>>" $?'
value_of 'gui_opt without a display (no windows): no' 1

# The check runs zenity once, whatever the number of dialogs: the stub counts its help calls.
alt_zenity
sed -i 's|^if \[ "\$1" = "--help-all" \]; then|if [ "$1" = "--help-all" ]; then echo x >> "'"$SB"'/alt/helps";|' "$SB/alt/zenity"
rm -f "$SB/alt/helps"
app_eval 'zenity_usable; zenity_usable; gui_available; zenity_usable; echo done' DISPLAY=:99 PATH="$(ALT_PATH)"
check_eq 'the help is asked once, however many times it is checked' 1 "$(wc -l < "$SB/alt/helps")"

echo "-- GUI_LOCALE: zenity runs under C.UTF-8 when the system has it"
printf '#!/bin/sh\nprintf "%%s\\n" C C.utf8 POSIX\n' > "$SB/alt/locale"; chmod 755 "$SB/alt/locale"; sandbox_chown
alt_zenity
app_eval 'zenity_usable; printf "<<%s>>" "$GUI_LOCALE"' DISPLAY=:99 PATH="$(ALT_PATH)"
value_of 'C.utf8 listed: GUI_LOCALE is C.UTF-8' C.UTF-8
printf '#!/bin/sh\nprintf "%%s\\n" C POSIX en_US.utf8\n' > "$SB/alt/locale"
app_eval 'zenity_usable; printf "<<%s>>" "$GUI_LOCALE"' DISPLAY=:99 PATH="$(ALT_PATH)"
value_of 'no C.UTF-8 in the list: GUI_LOCALE stays empty' ''
printf '#!/bin/sh\nprintf "%%s\\n" C C.UTF-8\n' > "$SB/alt/locale"
app_eval 'zenity_usable; printf "<<%s>>" "$GUI_LOCALE"' PATH="$(ALT_PATH)"
value_of 'zenity not usable: GUI_LOCALE stays empty' ''
# What zenity gets: LC_ALL=C.UTF-8 in its environment, and nothing of the user's locale.
printf '#!/bin/sh\nif [ "$1" = "--help-all" ]; then exec "%s/bin/zenity" --help-all; fi\nprintf "%%s" "$LC_ALL" > "%s/alt/lc"\nexit 0\n' "$SB" "$SB" > "$SB/alt/zenity"
chmod 755 "$SB/alt/zenity"; sandbox_chown
printf '#!/bin/sh\nprintf "%%s\\n" C C.UTF-8\n' > "$SB/alt/locale"
dlg 'wt_msgbox "Hi"' PATH="$(ALT_PATH)" LC_ALL=es_ES.ISO-8859-1
check_eq 'zenity runs with LC_ALL=C.UTF-8 whatever the user has' C.UTF-8 "$(cat "$SB/alt/lc")"
rm -rf "$SB/alt"

echo "-- Which engine starts"
engine() {  # engine LABEL EXPECTED [VAR=val ...]: "engine haswindows" once the program is loaded
    local label="$1" expected="$2"; shift 2
    app_eval 'printf "<<%s %s>>" "$UI_ENGINE" "$HAVE_WHIPTAIL"' "$@"
    value_of "$label" "$expected"
}
engine 'MINTAPP_UI=gui with zenity usable: gui'                  'gui 1' MINTAPP_UI=gui DISPLAY=:99
engine 'MINTAPP_UI=gui without a display: text (no terminal)'    'text 0' MINTAPP_UI=gui
engine 'MINTAPP_UI=gui without zenity: text (no terminal)'       'text 0' MINTAPP_UI=gui DISPLAY=:99 PATH="$SB/emptybin"
engine 'MINTAPP_UI=text with zenity usable: text'                'text 0' MINTAPP_UI=text DISPLAY=:99
engine 'MINTAPP_UI=whiptail with zenity usable: whiptail'        'whiptail 1' MINTAPP_UI=whiptail DISPLAY=:99

echo "-- The G entry: offered by the other engines when zenity can be used, never by gui itself"
# TERMINAL_TABLE=(): no emulator to go to, whatever the machine has installed (T has its own cases below).
tags() {  # tags LABEL EXPECTED [VAR=val ...]: the keys of the main menu
    local label="$1" expected="$2"; shift 2
    app_eval 'TERMINAL_TABLE=(); build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"' "$@"
    value_of "$label" "$expected"
}
tags 'whiptail + zenity usable: G between 4 and L'               '1 2 3 4 G L 0' MINTAPP_UI=whiptail DISPLAY=:99
tags 'whiptail without a display: no G'                          '1 2 3 4 L 0' MINTAPP_UI=whiptail
tags 'text + zenity usable: G'                                   '1 2 3 4 G L 0' MINTAPP_UI=text DISPLAY=:99
tags 'gui: no G (already in windows) and no T (no terminal)'     '1 2 3 4 L 0' MINTAPP_UI=gui DISPLAY=:99 MINTAPP_LANG=en

U=$'\037'    # what the program puts between the label and the description of a menu entry
LONG15="$(seq -f 'line %g' 1 15)"

echo "-- Message (msgbox): a window with one button"
fake_zenity OK
dlg 'wt_msgbox "Hello\nworld"'
check_eq 'msgbox: OK is status 0 and no answer' '0|' "$OUT"
check_eq 'msgbox: zenity ran once' 1 "$(zenity_calls)"
has 'msgbox: an info window' --info
has 'msgbox: markup off, so "&" and "<" are shown as they are' --no-markup
has 'msgbox: the title of the program' '--title=MintApp Remover'
has 'msgbox: the width its text needs (here the narrowest), the height is zenity'"'"'s' --width=320
has 'msgbox: the text, its line break as one' '--text=Hello|world'
has 'msgbox: the label of the button' --ok-label=OK
lacks 'msgbox: no height given' --height=560
fake_zenity CANCEL
dlg 'wt_msgbox "Hello"'
check_eq 'msgbox: a closed window is status 1' '1|' "$OUT"
fake_zenity OK
dlg 'wt_msgbox "a & b <c> \"quoted\""'
has 'msgbox: "&" and "<" go in as they are' '--text=a & b <c> "quoted"'
dlg 'wt_msgbox "$(seq -f "line %g" 1 14)"'
has 'msgbox: 14 lines still fit a message window' --info
lacks 'msgbox: 14 lines are not a scrolling text' --text-info
dlg 'wt_msgbox "$(seq -f "line %g" 1 15)"'
has 'msgbox: 15 lines go to a scrolling text window' --text-info
lacks 'msgbox: and not to an info window' --info
has 'msgbox: the long text is wider' --width=820
has 'msgbox: and taller' --height=560
has 'msgbox: the OK label' --ok-label=OK
has 'msgbox: Close is the only way out besides OK' --cancel-label=Close
check_eq 'msgbox: the text goes in by stdin, as it is' "$LONG15" "$(zenity_stdin)"
dlg 'wt_msgbox "$(for i in $(seq 1 100); do printf "word "; done)"'
has 'msgbox: 100 words in one paragraph are about 7 lines: no scroll' --info
dlg 'wt_msgbox "$(for i in $(seq 1 220); do printf "word "; done)"'
has 'msgbox: 220 words wrap to over 14 lines: scroll' --text-info
fake_zenity CANCEL
dlg 'wt_msgbox "$(seq -f "line %g" 1 15)"'
check_eq 'msgbox, scrolling: Close is status 1' '1|' "$OUT"

echo "-- Question (yesno): two buttons"
fake_zenity OK
dlg 'wt_yesno "Delete?" Yes No'
check_eq 'question: OK is yes (0)' '0|' "$OUT"
has 'question: a question window' --question
has 'question: markup off' --no-markup
has 'question: the text' '--text=Delete?'
has 'question: the yes button is OK' --ok-label=Yes
has 'question: the no button is Cancel' --cancel-label=No
lacks 'question: nothing is the default but zenity'"'"'s own' --default-cancel
lacks 'question: no extra buttons' --switch
fake_zenity CANCEL
dlg 'wt_yesno "Delete?" Yes No'
check_eq 'question: Cancel, Esc or the close button are no (1)' '1|' "$OUT"
fake_zenity OK
dlg 'wt_yesno "Delete?" Uninstall Cancel normal defaultno'
check_eq 'question defaultno: OK is still yes (0)' '0|' "$OUT"
has 'question defaultno: the focus starts on the no button' --default-cancel
fake_zenity CANCEL
dlg 'wt_yesno "Delete?" Uninstall Cancel normal defaultno'
check_eq 'question defaultno: Cancel is no (1)' '1|' "$OUT"
fake_zenity OK
dlg 'wt_yesno "Delete?" Uninstall Cancel big defaultno'
has 'question, big: the size does not change a short question' --question

echo "-- Choice between two actions: two buttons, none of them \"no\""
fake_zenity EXTRA:Alpha
dlg 'wt_yesno "Pick" Alpha Beta normal "" choice'
check_eq 'choice: the first button is action one (0)' '0|' "$OUT"
has 'choice: zenity without OK and Cancel' --switch
has 'choice: the first button' --extra-button=Alpha
has 'choice: the second button' --extra-button=Beta
lacks 'choice: no OK label' --ok-label=Alpha
lacks 'choice: no Cancel label' --cancel-label=Beta
fake_zenity EXTRA:Beta
dlg 'wt_yesno "Pick" Alpha Beta normal "" choice'
check_eq 'choice: the label of the second button is action two (1)' '1|' "$OUT"
fake_zenity CANCEL
dlg 'wt_yesno "Pick" Alpha Beta normal "" choice'
check_eq 'choice: Esc or the close button is the first action, never the second' '0|' "$OUT"
fake_zenity OK
dlg 'wt_yesno "Pick" Alpha Beta normal "" choice'
check_eq 'choice: status 0 without a label is the first action' '0|' "$OUT"
fake_zenity EXTRA:Other
dlg 'wt_yesno "Pick" Alpha Beta normal "" choice'
check_eq 'choice: a label that is not the second one is the first action' '0|' "$OUT"
fake_zenity EXTRA:Alpha
dlg 'wt_yesno "Pick" Alpha Alpha normal "" choice'
check_eq 'choice: two buttons with the same label: the first action' '1|' "$OUT"
fake_zenity EXTRA:Beta
dlg 'wt_yesno "Pick" Alpha Beta normal "" nonsense'
check_eq 'a sixth parameter other than "choice" is an ordinary question' '1|' "$OUT"
has 'ordinary question: no switch' --question

echo "-- Long question: a scrolling text with its own buttons"
fake_zenity OK
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Yes No'
check_eq 'long question: OK is yes (0)' '0|' "$OUT"
has 'long question: a text window' --text-info
has 'long question: OK is the yes button' --ok-label=Yes
has 'long question: Cancel is the no button' --cancel-label=No
lacks 'long question: no extra button' '--extra-button=Yes'
check_eq 'long question: the text goes in by stdin' "$LONG15" "$(zenity_stdin)"
fake_zenity CANCEL
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Yes No'
check_eq 'long question: Cancel is no (1)' '1|' "$OUT"

echo "-- Long destructive question: Enter must never confirm"
fake_zenity OK
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Uninstall Cancel big defaultno'
check_eq 'long defaultno: Enter (the OK button) is no (1)' '1|' "$OUT"
has 'long defaultno: the safe answer is the OK button (Enter)' --ok-label=Cancel
has 'long defaultno: the destructive one is an extra button' --extra-button=Uninstall
has 'long defaultno: closing is Close' --cancel-label=Close
lacks 'long defaultno: Uninstall is not the OK label' --ok-label=Uninstall
check_eq 'long defaultno: the text goes in by stdin' "$LONG15" "$(zenity_stdin)"
fake_zenity EXTRA:Uninstall
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Uninstall Cancel big defaultno'
check_eq 'long defaultno: the label of the extra button is yes (0)' '0|' "$OUT"
fake_zenity CANCEL
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Uninstall Cancel big defaultno'
check_eq 'long defaultno: Close or Esc is no (1)' '1|' "$OUT"
fake_zenity EXTRA:Something
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Uninstall Cancel big defaultno'
check_eq 'long defaultno: any other label is no (1)' '1|' "$OUT"

echo "-- Long choice between two actions"
fake_zenity OK
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Alpha Beta big "" choice'
check_eq 'long choice: OK is the first action (0)' '0|' "$OUT"
has 'long choice: the first action is the OK button' --ok-label=Alpha
has 'long choice: the second one is an extra button' --extra-button=Beta
has 'long choice: Close' --cancel-label=Close
fake_zenity EXTRA:Beta
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Alpha Beta big "" choice'
check_eq 'long choice: the label of the extra button is the second action (1)' '1|' "$OUT"
fake_zenity CANCEL
dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Alpha Beta big "" choice'
check_eq 'long choice: Close or Esc is the first action' '0|' "$OUT"

echo "-- Text entry (inputbox)"
fake_zenity OUT:typed
dlg 'wt --inputbox "a_b\\c" 10 40 init'
check_eq 'entry: what was typed is the answer, status 0' '0|typed' "$OUT"
has 'entry: an entry window' --entry
has 'entry: "_" doubled (it would be a mnemonic) and "\" doubled' '--text=a__b\\c'
has 'entry: the initial text' --entry-text=init
has 'entry: OK label by default' --ok-label=OK
has 'entry: Cancel label by default' --cancel-label=Cancel
fake_zenity 'OUT:two words'
dlg 'wt --ok-button Go --cancel-button Back --inputbox "Name" 10 40 ""'
check_eq 'entry: spaces are kept' '0|two words' "$OUT"
has 'entry: its own OK label' --ok-label=Go
has 'entry: its own Cancel label' --cancel-label=Back
has 'entry: an empty initial text' --entry-text=
fake_zenity CANCEL
dlg 'wt --inputbox "Name" 10 40 init'
check_eq 'entry: Cancel is status 1 and no answer' '1|' "$OUT"

echo "-- Menu"
fake_zenity OUT:2
dlg 'wt --ok-button OK --cancel-button Cancel --menu "Pick" 20 70 3 1 One 2 Two 3 Three'
check_eq 'menu: the tag of the row is the answer' '0|2' "$OUT"
has 'menu: a list window' --list
lacks 'menu: not a checklist' --checklist
has 'menu: width (short cells: the narrowest list)' --width=520
has 'menu: height (three rows: 3 x 35 + 226)' --height=331
has 'menu: the text above the list (its title, in bold)' --text='<b>Pick</b>'
has 'menu: OK label' --ok-label=OK
has 'menu: Cancel label' --cancel-label=Cancel
has 'menu: the first column is the key of the entry (its tag)' --column=Key
has 'menu: the column of options' --column=Option
lacks 'menu: no description column without descriptions' --column=Description
lacks 'menu: no icon column without icons' '--column= '
lacks 'menu: the key is shown, not hidden' --hide-column=1
has 'menu: and it is what is printed' --print-column=1
assert_contains 'menu: the rows in order' "$(zj)" '~1~One~2~Two~3~Three~'
fake_zenity CANCEL
dlg 'wt --menu "Pick" 20 70 1 1 One'
check_eq 'menu: Cancel, Esc or the close button: status 1 and no answer' '1|' "$OUT"
fake_zenity OUT:2
dlg "wt --menu \"Pick\" 20 70 2 1 \"One${U}first\" 2 \"Two${U}second\""
check_eq 'menu with descriptions: the answer is still the tag' '0|2' "$OUT"
has 'menu with descriptions: a third column' --column=Description
assert_contains 'menu with descriptions: label and description are two cells' "$(zj)" '~1~One~first~2~Two~second~'
dlg "wt --menu \"Pick\" 20 70 2 1 \"One${U}first\" 2 Two"
assert_contains 'menu with one description: the others get an empty cell' "$(zj)" '~1~One~first~2~Two~~'
fake_zenity 'OUT: -t'
dlg 'wt --menu "Pick" 20 70 2 -t "-label" 2 Two'
check_eq 'menu: a tag that starts with "-" comes back without the protecting space' '0|-t' "$OUT"
assert_contains 'menu: a tag and a label that start with "-" get a space (zenity takes them for options)' "$(zj)" '~ -t~ -label~2~Two~'
fake_zenity OUT:2
dlg 'wt --menu "a & b <c> \\d" 20 70 1 1 One'
has 'menu: "&", "<", ">" are escaped as markup and "\" doubled in the text' '--text=<b>a &amp; b &lt;c&gt; \\d</b>'
fake_zenity OUT:2
dlg 'wt --backtitle Back --default-item 2 --menu "Pick" 20 70 2 1 One 2 Two'
check_eq 'menu: backtitle and default item are accepted' '0|2' "$OUT"
lacks 'menu: and zenity gets neither' Back

echo "-- Checklist"
fake_zenity 'OUT:a|c'
dlg 'wt --checklist "Pick" 20 70 3 a "A & b" ON c "-C" OFF d "D" off'
check_eq 'checklist: the ticked tags come between quotes, as whiptail prints them' '0|"a" "c"' "$OUT"
has 'checklist: a list window' --list
has 'checklist: with check boxes' --checklist
has 'checklist: the first column is the box' '--column= '
has 'checklist: the tag column' --column=Tag
has 'checklist: the name column' --column=Application
has 'checklist: the tag column is hidden' --hide-column=2
has 'checklist: and it is what is printed' --print-column=2
has 'checklist: tags are separated by a bar' '--separator=|'
assert_contains 'checklist: states, tags and labels; ON is TRUE, OFF and off are FALSE' "$(zj)" '~TRUE~a~A & b~FALSE~c~ -C~FALSE~d~D~'
fake_zenity 'OUT: -p|b'
dlg 'wt --checklist "Pick" 20 70 2 -p P on b B on'
check_eq 'checklist: a tag that starts with "-" comes back clean' '0|"-p" "b"' "$OUT"
fake_zenity 'OUT:'
dlg 'wt --checklist "Pick" 20 70 1 a A off'
check_eq 'checklist: OK with nothing ticked is status 0 and an empty answer' '0|' "$OUT"
fake_zenity CANCEL
dlg 'wt --checklist "Pick" 20 70 1 a A on'
check_eq 'checklist: Cancel is status 1 and no answer' '1|' "$OUT"
fake_zenity 'OUT:a'
dlg 'wt --checklist "a & b <c>" 20 70 1 a A on'
has 'checklist: the text is escaped like a menu text' '--text=<b>a &amp; b &lt;c&gt;</b>'

echo "-- Size: the width a text needs, the height its rows need"
X60="$(printf 'x%.0s' {1..60})"; X80="$(printf 'x%.0s' {1..80})"; X100="$(printf 'x%.0s' {1..100})"
# wide LABEL EXPECTED CODE: the window that CODE opens has that --width.
wide() { fake_zenity OK; dlg "$3"; has "$1" "--width=$2"; }
wide 'message: a short text takes the narrowest width' 320 'wt_msgbox "Hi"'
wide 'message: 60 characters take 60 x 6.5 + 24' 414 "wt_msgbox \"$X60\""
wide 'message: 80 characters' 544 "wt_msgbox \"$X80\""
wide 'message: a longer line takes the widest width and wraps' 560 "wt_msgbox \"$X100\""
wide 'message: the longest line decides, not the number of lines' 414 "wt_msgbox \"Hi\\n$X60\\nHi\""
wide 'question: the same rule' 414 "wt_yesno \"$X60\" Yes No normal"
wide 'choice: the same rule' 414 "wt_yesno \"$X60\" Alpha Beta normal \"\" choice"
wide 'error window: the same rule' 414 "gui_error \"$X60\""
wide 'entry: a short text takes the narrowest entry' 420 'wt --ok-button OK --cancel-button Cancel --inputbox "Name" 10 40 ""'
wide 'entry: a long text takes what it needs' 544 "wt --ok-button OK --cancel-button Cancel --inputbox \"$X80\" 10 40 \"\""
fake_zenity OK; dlg "wt_msgbox \"$X100\""
lacks 'message: no height given (zenity grows the window by the lines)' --height=560
assert_not_contains 'message: no height of any kind' "$(zj)" '~--height='
# A list takes the width of its cells (label and description together, 6.5 px per character, plus
# 100) and the height of its rows. A menu adds 30 px for the column of keys (GUI_COL_PX) and 30
# more for that of the emoji when it has one: 98 characters are 637 + 100 + 30 = 767.
US=$'\037'; RS=$'\036'; L36="$(printf 'l%.0s' {1..36})"; D62="$(printf 'd%.0s' {1..62})"
# listed LABEL WIDTH HEIGHT CODE: the list that CODE opens has that --width and --height.
listed() { fake_zenity CANCEL; dlg "$4"; has "$1: width" "--width=$2"; has "$1: height" "--height=$3"; }
MENU='wt --ok-button OK --cancel-button Cancel --menu'
listed 'menu of two rows, a short label and its description' 520 296 "$MENU \"Pick\" 20 70 2 1 \"a${US}b\" 2 \"c${US}d\""
listed 'menu: a label of 36 and a description of 62 characters' 767 296 "$MENU \"Pick\" 20 70 2 1 \"$L36${US}$D62\" 2 \"c${US}d\""
listed 'menu: the longest label and the longest description count, not the longest row' 767 296 "$MENU \"Pick\" 20 70 2 1 \"$L36${US}d\" 2 \"c${US}$D62\""
listed 'menu with an emoji column: 30 px more for it' 797 296 "$MENU \"Pick\" 20 70 2 1 \"E${RS}$L36${US}$D62\" 2 \"c${US}d\""
listed 'menu with an emoji column: and the shortest list stays the same' 520 296 "$MENU \"Pick\" 20 70 2 1 \"E${RS}a${US}b\" 2 \"F${RS}c${US}d\""
listed 'menu: without descriptions only the labels count' 520 296 "$MENU \"Pick\" 20 70 2 1 \"$L36\" 2 c"
listed 'menu: cells that are too long take the widest width' 820 296 "$MENU \"Pick\" 20 70 2 1 \"$X100${US}$X100\" 2 c"
rows() {  # rows N: N rows of a short label for a menu
    local i; for ((i = 1; i <= $1; i++)); do printf ' %s "r%s"' "$i" "$i"; done
}
listed 'menu: one row is not shorter than the shortest list' 520 280 "$MENU \"Pick\" 20 70 1$(rows 1)"
listed 'menu: nine rows: 9 x 35 + 226' 520 541 "$MENU \"Pick\" 20 70 9$(rows 9)"
listed 'menu: ten rows do not fit in the tallest list' 520 560 "$MENU \"Pick\" 20 70 10$(rows 10)"
listed 'menu: thirty rows scroll in the tallest list' 520 560 "$MENU \"Pick\" 20 70 30$(rows 30)"
listed 'menu: a text of three lines takes two more lines of height' 520 369 "$MENU \"a\\nb\\nc\" 20 70 3$(rows 3)"
listed 'menu: a text that wraps takes a line for each time' 520 369 "$MENU \"$(printf 'word %.0s' {1..30})\" 20 70 3$(rows 3)"
CHECK='wt --ok-button OK --cancel-button Cancel --checklist'
listed 'checklist: short names, three rows of 41 px' 520 349 "$CHECK \"Pick\" 20 70 3 a A off b B off c C off"
listed 'checklist: a name of 60 characters and the check box' 542 349 "$CHECK \"Pick\" 20 70 3 a $X60 off b B off c C off"
for kind in menu checklist; do
    code="$MENU \"Pick\" 20 70 2 1 a 2 b"; [ "$kind" = menu ] || code="$CHECK \"Pick\" 20 70 2 a A off b B off"
    fake_zenity CANCEL; dlg "$code"
    has "$kind: the column headers are hidden when zenity can" --hide-header
    zenity_help_without --hide-header
    fake_zenity CANCEL; dlg "$code"
    lacks "$kind: and kept when its help does not list --hide-header" --hide-header
    zenity_help_without
done
fake_zenity CANCEL; dlg 'wt_msgbox "$(seq -f "line %g" 1 30)"'
has 'a long text keeps its own size: width' --width=820
has 'a long text keeps its own size: height' --height=560

echo "-- Text above a list: the title in bold, the hint dimmed, every line escaped"
HINT='<span alpha="60%">'
fake_zenity CANCEL; dlg "$MENU \"Pick\" 20 70 1 1 a"
has 'menu, one line: only the title, in bold' '--text=<b>Pick</b>'
fake_zenity CANCEL; dlg "$MENU \"Title\\nthe hint\" 20 70 1 1 a"
has 'menu, two lines: the title bold and the hint dimmed' "--text=<b>Title</b>|${HINT}the hint</span>"
fake_zenity CANCEL; dlg "$MENU \"Title\\nfirst\\nsecond\" 20 70 1 1 a"
has 'menu, three lines: every line of the hint dimmed' "--text=<b>Title</b>|${HINT}first</span>|${HINT}second</span>"
fake_zenity CANCEL; dlg "$MENU \"A & B <x>\\nhint <y> &\" 20 70 1 1 a"
has 'menu: what looks like markup in the text is shown, not obeyed' "--text=<b>A &amp; B &lt;x&gt;</b>|${HINT}hint &lt;y&gt; &amp;</span>"
fake_zenity CANCEL; dlg "$CHECK \"Title\\nthe hint\" 20 70 1 a A off"
has 'checklist: the same, title bold and hint dimmed' "--text=<b>Title</b>|${HINT}the hint</span>"
lacks 'checklist: its markup is on (the title needs it)' --no-markup
fake_zenity OK; dlg 'wt_msgbox "Hello\nworld"'
has 'a message keeps its plain text, with no markup' '--text=Hello|world'
# The main menu in windows says nothing about the keys of the terminal: its text is the status line (F7.0)
# in bold, an empty dimmed line and its own dimmed prompt, and nothing else.
# menu_text: the --text of the last window, with its line breaks as "|".
menu_text() { local t; t="$(zj)"; t="${t#*~--text=}"; printf '%s' "${t%%~*}"; }
fake_zenity CANCEL
app_eval 'main_menu_whiptail' "${GUI[@]}"
txt="$(menu_text)"
check_eq 'main menu in windows (en): the status line, then its own prompt, without keys' "|${HINT}</span>|${HINT}Select an option:</span>" "${txt#<b>*</b>}"
fake_zenity CANCEL
app_eval 'main_menu_whiptail' "${GUI[@]}" MINTAPP_LANG=es
txt="$(menu_text)"
check_eq 'main menu in windows (es): the status line, then its own prompt, without keys' "|${HINT}</span>|${HINT}Selecciona una opción:</span>" "${txt#<b>*</b>}"

echo "-- Icon: the program's on messages and questions, the theme's warning on what destroys"
REAL_SCRIPT="$H_SCRIPT"
# icon_app [icon]: from now on the cases run a copy of the program in "$SB/my app/script" (a folder
# with a space) WITHOUT its embedded icon (the "#@" lines), so that the icon is the file
# assets/$ICON_NAME beside it when the argument is "icon". real_app: the program itself, whole.
icon_app() {
    rm -rf -- "$SB/my app" "$SB/links"
    mkdir -p -- "$SB/my app/script" "$SB/my app/assets"
    sed '/^#@/d' "$REAL_SCRIPT" > "$SB/my app/script/MintApp_Remover.sh"
    if [ "${1:-}" = icon ]; then printf 'png' > "$SB/my app/assets/$ICON_NAME"; fi
    sandbox_chown
    H_SCRIPT="$SB/my app/script/MintApp_Remover.sh"
}
real_app() { H_SCRIPT="$REAL_SCRIPT"; }
# no_icon LABEL CODE: CODE (a dialog call) opens one window, and none of its arguments is --icon.
no_icon() { fake_zenity OK; dlg "$2"; assert_not_contains "$1" "$(zj)" '~--icon='; }
icon_app icon
ICON="$(readlink -f "$SB/my app/assets/$ICON_NAME")"
fake_zenity OK; dlg 'wt_msgbox "Done"'
has 'message: the program icon' "--icon=$ICON"
fake_zenity OK; dlg 'wt_yesno "Continue?" Yes No normal'
has 'question: the program icon' "--icon=$ICON"
fake_zenity OK; dlg 'wt_yesno "Pick" Alpha Beta normal "" choice'
has 'choice: the program icon' "--icon=$ICON"
fake_zenity OK; dlg 'wt_yesno "Remove?" Remove Cancel normal defaultno'
has 'destructive question: the warning icon of the theme' --icon=dialog-warning
lacks 'destructive question: not the program icon' "--icon=$ICON"
no_icon 'menu: no icon (zenity has none for a list)' 'wt --ok-button OK --cancel-button Cancel --menu "Pick" 20 70 2 a A b B'
no_icon 'checklist: no icon' 'wt --ok-button OK --cancel-button Cancel --checklist "Pick" 20 70 2 a A off b B off'
no_icon 'entry: no icon' 'wt --ok-button OK --cancel-button Cancel --inputbox "Name" 10 40 ""'
no_icon 'long message (a scrolling text): no icon' 'wt_msgbox "$(seq -f "line %g" 1 30)"'
no_icon 'long destructive question (a scrolling text): no icon' 'wt_yesno "$(seq -f "line %g" 1 30)" Remove Cancel big defaultno'
no_icon 'error window: the icon of the theme' 'gui_error "Oops"'
icon_app
no_icon 'without the icon file: a message has no icon' 'wt_msgbox "Done"'
no_icon 'without the icon file: a question has no icon' 'wt_yesno "Continue?" Yes No normal'
fake_zenity OK; dlg 'wt_yesno "Remove?" Remove Cancel normal defaultno'
has 'without the icon file: the destructive question keeps the warning icon' --icon=dialog-warning
mkdir -p "$SB/my app/assets/$ICON_NAME"; sandbox_chown
no_icon 'the icon file is a folder: no icon' 'wt_msgbox "Done"'
icon_app icon; chmod 000 "$SB/my app/assets/$ICON_NAME"
no_icon 'the icon file cannot be read: no icon' 'wt_msgbox "Done"'
icon_app icon
zenity_help_without --icon
no_icon 'a zenity without --icon: a message has none' 'wt_msgbox "Done"'
no_icon 'a zenity without --icon: a question has none' 'wt_yesno "Continue?" Yes No normal'
no_icon 'a zenity without --icon: the destructive question has none either' 'wt_yesno "Remove?" Remove Cancel normal defaultno'
zenity_help_without --hide-header
fake_zenity OK; dlg 'wt_msgbox "Done"'
has 'a zenity without --hide-header: the icon is not affected' "--icon=$ICON"
zenity_help_without
mkdir -p "$SB/links"; ln -s "$SB/my app/script/MintApp_Remover.sh" "$SB/links/mintapp"; sandbox_chown
H_SCRIPT="$SB/links/mintapp"
fake_zenity OK; dlg 'wt_msgbox "Done"'
has 'run through a link to the script: the icon beside the real script' "--icon=$ICON"
# The icon the program carries (F6.3): written when the windows start, it goes before the file in
# assets/, and a damaged copy falls back on that file.
real_app
fake_zenity OK
app_eval 'zenity_usable; gui_icon_prepare; gui_find_icon; f="$REPLY"; sed -n "s/^#@//p" "$1" | base64 -d > "$GUI_WORK_DIR/want.png"; if cmp -s "$f" "$GUI_WORK_DIR/want.png"; then s=same; else s=different; fi; if [ "${f%/*}" = "$GUI_WORK_DIR" ]; then w=inside; else w=outside; fi; rm -rf -- "$GUI_WORK_DIR"; printf "<<%s %s>>" "$s" "$w"' "${GUI[@]}"
value_of 'embedded icon: the windows take the one inside the program, from its private folder' 'same inside'
icon_app icon
cp -- "$REAL_SCRIPT" "$SB/my app/script/MintApp_Remover.sh"; sandbox_chown
fake_zenity OK; dlg 'gui_icon_prepare; wt_msgbox "Done"'
assert_contains 'embedded icon and a file in assets/: the window carries the embedded copy' "$(zj)" '/icon.png~'
assert_not_contains 'and not the file in assets/' "$(zj)" "assets/$ICON_NAME"
awk '/^#@/ { n++; if (n > 5) next } { print }' "$REAL_SCRIPT" > "$SB/my app/script/MintApp_Remover.sh"; sandbox_chown
fake_zenity OK; dlg 'gui_icon_prepare; wt_msgbox "Done"'
has 'a damaged embedded icon: the window takes the file in assets/' "--icon=$ICON"
real_app

echo "-- Window class: every window starts through gui_cmd, as mintapp-remover"
fake_zenity OK
app_eval 'zenity_usable; gui_cmd --info --text=x; echo "<<alive $?>>"' "${GUI[@]}"
value_of 'gui_cmd on the shell of the program: the program is not replaced' 'alive 0'
check_eq 'gui_cmd on the shell of the program: zenity ran once' 1 "$(zenity_calls)"
# In a pipe in the background, as the progress window runs, the process is zenity itself: stopping
# the window by its PID stops zenity, not a shell around it that would leave the window open.
mkdir -p "$SB/alt"
printf '#!/bin/sh\nif [ "$1" = "--help-all" ]; then exec "%s/bin/zenity" --help-all; fi\necho $$ > "%s/alt/pid"\nexec sleep 5\n' "$SB" "$SB" > "$SB/alt/zenity"
chmod 755 "$SB/alt/zenity"; sandbox_chown
app_eval "zenity_usable; echo | gui_cmd --progress >/dev/null 2>&1 & p=\$!; for _ in \$(seq 1 20); do [ -s '$SB/alt/pid' ] && break; sleep 0.1; done; kill \"\$p\" 2>/dev/null; wait \"\$p\" 2>/dev/null; echo \"<<\$p>>\"" "${GUI[@]}" PATH="$(ALT_PATH)"
v="${OUT#*<<}"
check_eq 'a window in a pipe in the background: $! is the process of zenity itself' "$(cat "$SB/alt/pid")" "${v%%>>*}"
rm -rf "$SB/alt"
# trace LABEL CODE: CODE opens one window; the trace of the process and its subshells (set -x, into a
# file) must show that it was started as "exec -a mintapp-remover zenity", once.
trace() {
    local label="$1" code="$2"
    fake_zenity OK; : > "$SB/state/trace"; sandbox_chown
    app_eval "zenity_usable; exec 9>>'$SB/state/trace'; BASH_XTRACEFD=9; set -x; $code; set +x" "${GUI[@]}" TMPDIR="$SB/tmp" >/dev/null 2>&1 || true
    check_eq "$label" '1 1' "$(zenity_calls) $(grep -c 'exec -a mintapp-remover zenity ' "$SB/state/trace" || true)"
}
new_sandbox; mkdir -p "$SB/tmp"; sandbox_chown; fake_installed mintstick
trace 'message: started as mintapp-remover' 'wt_msgbox "Hi"'
trace 'question: started as mintapp-remover' 'wt_yesno "Q" Yes No normal'
trace 'menu: started as mintapp-remover' 'wt --ok-button OK --cancel-button Cancel --menu "Pick" 20 70 2 a A b B'
trace 'checklist: started as mintapp-remover' 'wt --ok-button OK --cancel-button Cancel --checklist "Pick" 20 70 2 a A off b B off'
trace 'entry: started as mintapp-remover' 'wt --ok-button OK --cancel-button Cancel --inputbox "Name" 10 40 ""'
trace 'scrolling text: started as mintapp-remover' 'wt_msgbox "$(seq -f "line %g" 1 30)"'
trace 'error window: started as mintapp-remover' 'gui_error "Oops"'
trace 'progress window: started as mintapp-remover' 'UI_ENGINE=gui; run_pm_gui "Working..." purge mintstick'
new_sandbox
echo "-- When zenity cannot run: status 254, never a closed window"
for answer in NODISPLAY BROKEN; do
    fake_zenity "$answer"; dlg 'wt_msgbox "Hello"'
    check_eq "$answer: a message ends with 254" '254|' "$OUT"
    fake_zenity "$answer"; dlg 'wt_yesno "Delete?" Yes No'
    check_eq "$answer: a question ends with 254" '254|' "$OUT"
    fake_zenity "$answer"; dlg 'wt --menu "Pick" 20 70 1 1 One'
    check_eq "$answer: a menu ends with 254" '254|' "$OUT"
    fake_zenity "$answer"; dlg 'wt --checklist "Pick" 20 70 1 a A on'
    check_eq "$answer: a checklist ends with 254" '254|' "$OUT"
    fake_zenity "$answer"; dlg 'wt --inputbox "Name" 10 40 x'
    check_eq "$answer: an entry ends with 254" '254|' "$OUT"
    fake_zenity "$answer"; dlg 'wt_yesno "$(seq -f "line %g" 1 15)" Yes No'
    check_eq "$answer: a long text ends with 254" '254|' "$OUT"
done
fake_zenity CANCEL
dlg 'wt_msgbox "Hello"'
check_eq 'a closed window is 1, not 254' '1|' "$OUT"
# A status of zenity itself: 130 and 143 are signals (Ctrl-C, TERM) and go on to the caller.
for rc in 2 126 127 193 255; do
    printf '#!/bin/sh\nif [ "$1" = "--help-all" ]; then exec "%s/bin/zenity" --help-all; fi\nexit %s\n' "$SB" "$rc" > "$SB/alt-zenity"
    mkdir -p "$SB/alt"; mv "$SB/alt-zenity" "$SB/alt/zenity"; chmod 755 "$SB/alt/zenity"; sandbox_chown
    dlg 'wt_msgbox "Hello"' PATH="$(ALT_PATH)"
    check_eq "zenity status $rc is 254" '254|' "$OUT"
done
for rc in 129 130 143 192; do
    printf '#!/bin/sh\nif [ "$1" = "--help-all" ]; then exec "%s/bin/zenity" --help-all; fi\nexit %s\n' "$SB" "$rc" > "$SB/alt/zenity"
    dlg 'wt_msgbox "Hello"' PATH="$(ALT_PATH)"
    check_eq "zenity status $rc (a signal) goes on as it is" "$rc|" "$OUT"
done
rm -rf "$SB/alt"
dlg 'UI_ENGINE=gui; wt_msgbox "Hello"' PATH="$SB/emptybin"
check_eq 'zenity gone after the check (command not found): 254' '254|' "$OUT"

echo "-- Odd calls"
fake_zenity OK
app_eval 'zenity_usable; gui_dialog --title T; echo "<<$?>>"' "${GUI[@]}"
value_of 'a call without a kind is status 1' 1
check_eq 'and zenity did not run' 0 "$(zenity_calls)"
app_eval 'zenity_usable; gui_dialog --title T --radiolist "x" 10 10 1; echo "<<$?>>"' "${GUI[@]}"
value_of 'a kind it does not know is status 1' 1

# win ANSWER...: the program with windows; each ANSWER is what one zenity window does (see
# fake_zenity). OUT and RC are the program's.
win() { fake_zenity "$@"; app_run '' "${GUI[@]}"; }
# win_alone ANSWER...: win with no emulator to go to, whatever the machine has installed.
win_alone() { fake_zenity "$@"; app_eval 'TERMINAL_TABLE=(); main' "${GUI[@]}"; }
# strip: OUT without the terminal escape sequences and blank lines (the screens still write there).
strip() { printf '%s\n' "$OUT" | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -v '^$' || true; }

echo "-- Start and leave: help window, main menu, Exit"
win_alone OK OUT:0
check_eq 'help, then Exit: status 0' 0 "$RC"
check_eq 'help, then Exit: the program says goodbye on the terminal' 'Exiting...' "$OUT"
check_eq 'help window and menu: two windows' 2 "$(zenity_calls)"
has 'help window: a choice between two actions' --switch 1
has 'help window: the first one is "Understood"' --extra-button=Understood 1
has 'help window: the second is the other language, in its own name' --extra-button=Español 1
assert_contains 'help window: it describes the windows, not the keys of the terminal' "$(zj 1)" 'Graphical windows (zenity)'
has 'menu: a list' --list 2
has 'menu: key, option and description' --column=Key 2
has 'menu: and the description' --column=Description 2
lacks 'menu: no emoji column when the system has no color emoji font' '--column= ' 2
has 'menu: OK' --ok-label=OK 2
has 'menu: the Cancel button is the way out' --cancel-label=Exit 2
assert_contains 'menu: six entries in order, with their descriptions' "$(zj 2)" \
    '~1~Detect applications~See which catalog applications are installed.~2~Uninstall applications~'
assert_contains 'menu: language and exit last' "$(zj 2)" '~L~Español~Switch the interface to Spanish.~0~Exit~'
assert_not_contains 'menu: no G (already in windows) and no T (no terminal)' "$(zj 2)" '~G~'
assert_not_contains 'menu: no T without a terminal' "$(zj 2)" '~T~'
win CANCEL CANCEL
check_eq 'closing the help window goes to the menu; closing the menu leaves: status 0' 0 "$RC"
check_eq 'closing the menu leaves without a word' '' "$OUT"
check_eq 'closing the help window did not skip the menu' 2 "$(zenity_calls)"
win EXTRA:Understood OUT:0
check_eq '"Understood" goes on to the menu' 'Exiting...' "$OUT"

echo "-- A display that cannot be reached"
win OK NODISPLAY
check_eq 'menu: status 1, not a silent exit as if the window had been closed' 1 "$RC"
check_eq 'menu: it says what to do' 'The graphical window (zenity) could not be opened. Check that a graphical session is running or use MINTAPP_UI=tui.' "$OUT"
win NODISPLAY NODISPLAY
check_eq 'help and menu: a display lost in the help window does not hide it' 1 "$RC"
assert_contains 'help and menu: the message comes from the menu' "$OUT" 'could not be opened'
win OK BROKEN
check_eq 'a zenity that fails (status 5): status 1' 1 "$RC"

echo "-- Language: from the help window and from the menu"
win EXTRA:Español OK OUT:0
check_eq 'language button of the help window: back to the help, now in Spanish' 'Saliendo...' "$OUT"
assert_contains 'the help window shows again, in Spanish' "$(zj 2)" 'Ventanas gráficas (zenity)'
has 'its buttons are in Spanish' --extra-button=Entendido 2
has 'and the other language is English' --extra-button=English 2
has 'the menu is in Spanish: OK' --ok-label=Aceptar 3
has 'the menu is in Spanish: Exit' --cancel-label=Salir 3
win OK OUT:L OUT:L OUT:0
check_eq 'L twice: Spanish and back to English' 'Exiting...' "$OUT"
has 'after the first L the menu is in Spanish' --cancel-label=Salir 3
has 'after the second L the menu is in English' --cancel-label=Exit 4
check_eq 'one window per screen: help, menu, menu, menu' 4 "$(zenity_calls)"

echo "-- Emoji in the menus: only when the system draws them in color"
# Every sandbox starts with a fontconfig that has no fonts (fake_fonts), so none of this depends
# on the fonts of the machine that runs the tests.
E_DETECT=🔍 E_TRASH=🗑️ E_COMPASS=🧭 E_BROOM=🧹 E_LAPTOP=💻 E_GLOBE=🌐 E_DOOR=🚪
E_BOX=📦 E_SOAP=🧼 E_LEAF=🍃 E_SPONGE=🧽 E_CHECK=✅ E_FOLDER=📂 E_PAGE=📄
# emoji LABEL EXPECTED [VAR=val ...]: the status of gui_emoji (0 = the windows draw emoji).
emoji() {
    local label="$1" expected="$2"; shift 2
    app_eval 'gui_emoji; printf "<<%s>>" "$?"' "${GUI[@]}" "$@"
    value_of "$label" "$expected"
}
# icons LABEL EXPECTED ENGINE MENU TAG...: the emoji menu_icon_list gives to those entries, joined by "|".
icons() {
    local label="$1" expected="$2" engine="$3" menu="$4"; shift 4
    app_eval "UI_ENGINE=$engine; tags=($*); menu_icon_list $menu tags icons; printf '<<%s>>' \"\$(IFS='|'; echo \"\${icons[*]}\")\"" "${GUI[@]}"
    value_of "$label" "$expected"
}
emoji 'no fonts at all: no emoji' 1
fake_emoji_font
emoji 'a color emoji font that has the newest emoji: emoji' 0
fake_fonts 'Unifont|0|1'
emoji 'a font that has the character but is not a color one (a black and white block): no emoji' 1
fake_fonts 'Old Emoji|1|0'
emoji 'a color emoji font without the newest emoji (U+1F9FC): no emoji' 1
fake_fonts 'Unifont|0|1' 'Old Emoji|1|0'
emoji 'two fonts that have one of the two things each: no emoji' 1
fake_fonts 'Unifont|0|1' 'Noto Color Emoji|1|1'
emoji 'a bitmap font and a color one that has it: emoji' 0
fake_emoji_font
emoji 'MINTAPP_ASCII=1: no emoji even with the font' 1 MINTAPP_ASCII=1
check_eq 'MINTAPP_ASCII=1: fontconfig is not even asked' 0 "$(fc_list_calls)"
emoji 'a locale without UTF-8: no emoji even with the font' 1 MINTAPP_ASCII= LC_ALL=C
emoji 'no fc-list command: no emoji' 1 PATH="$SB/emptybin"
fake_emoji_font
app_eval 'gui_emoji; gui_emoji; gui_emoji; printf "<<%s>>" "$GUI_EMOJI"' "${GUI[@]}"
value_of 'asked more than once: still emoji' 1
check_eq 'fontconfig is asked once, however many windows follow' 1 "$(fc_list_calls)"
assert_contains 'what it asks: color fonts that have U+1F9FC (a bitmap font that has it draws a block)' "$(cat "$SB/state/fc-list.log")" ':charset=1f9fc:color=True'

# With a color emoji font: one emoji for each entry of the main menu and of the cleaning ones.
fake_emoji_font
icons 'main menu: one emoji per entry, in order' "$E_DETECT|$E_TRASH|$E_COMPASS|$E_BROOM|$E_LAPTOP|$E_GLOBE|$E_DOOR" gui main 1 2 3 4 T L 0
icons 'cleaning menu' "$E_BOX|$E_SOAP" gui clean 1 2
icons 'level menu' "$E_LEAF|$E_SPONGE" gui level S C
icons 'scope menu' "$E_CHECK|$E_FOLDER|$E_PAGE" gui scope 1 2 3
icons 'an entry with no emoji (G) gets an empty one, and the list keeps its length' "|$E_DETECT" gui main G 1
icons 'a tag is not a tag of another menu' "|" gui main S C
icons 'the terminal engines never get emoji (tui)' '||||||' tui main 1 2 3 4 T L 0
icons 'the terminal engines never get emoji (whiptail)' '||||||' whiptail main 1 2 3 4 T L 0
icons 'the terminal engines never get emoji (text)' '||||||' text main 1 2 3 4 T L 0
fake_fonts
icons 'without a color font: none, even in the windows' '||||||' gui main 1 2 3 4 T L 0

# A menu with emoji is a list of four columns: key, emoji, label and description.
fake_emoji_font
fake_zenity CANCEL
dlg "$MENU \"Pick\" 20 70 3 1 \"${E_DETECT}${RS}One${US}first\" 2 \"${E_TRASH}${RS}Two${US}second\" 3 Three"
has 'menu with emoji: the key column' --column=Key
has 'menu with emoji: a column for the emoji, with no title' '--column= '
has 'menu with emoji: the option column' --column=Option
has 'menu with emoji: the description column' --column=Description
assert_contains 'menu with emoji: key, emoji, label and description, one cell each; an entry without them has empty cells' "$(zj)" "~1~$E_DETECT~One~first~2~$E_TRASH~Two~second~3~~Three~~"
has 'menu with emoji: what is printed is still the key' --print-column=1
fake_zenity OUT:2
dlg "$MENU \"Pick\" 20 70 2 1 \"${E_DETECT}${RS}One\" 2 \"${E_TRASH}${RS}Two\""
check_eq 'menu with emoji: the answer is the key, not the emoji' '0|2' "$OUT"

# The screens of the program with a color emoji font.
fake_zenity OK OUT:0
app_eval 'TERMINAL_TABLE=(); main' "${GUI[@]}"
has 'main menu with emoji: the emoji column' '--column= ' 2
assert_contains 'main menu with emoji: the first entries' "$(zj 2)" "~1~$E_DETECT~Detect applications~See which catalog applications are installed.~2~$E_TRASH~Uninstall applications~"
assert_contains 'main menu with emoji: language and exit last' "$(zj 2)" "~L~$E_GLOBE~Español~Switch the interface to Spanish.~0~$E_DOOR~Exit~"
fake_zenity OK OUT:0
app_eval 'TERMINAL_TABLE=(); main' "${GUI[@]}" MINTAPP_LANG=es
has 'main menu with emoji, in Spanish: the key column is "Tecla"' --column=Tecla 2
assert_contains 'main menu with emoji, in Spanish: language and exit last' "$(zj 2)" "~L~$E_GLOBE~English~"
fake_zenity OK OUT:4 CANCEL OUT:0
app_eval 'TERMINAL_TABLE=(); main' "${GUI[@]}"
assert_contains 'cleaning menu with emoji: both actions' "$(zj 3)" "~1~$E_BOX~"
assert_contains 'cleaning menu with emoji: the deep one too' "$(zj 3)" "~2~$E_SOAP~"
fake_fonts
fake_zenity OK OUT:4 CANCEL OUT:0
app_eval 'TERMINAL_TABLE=(); main' "${GUI[@]}"
lacks 'cleaning menu without a color font: no emoji column' '--column= ' 3

echo "-- Option 1: detect"
fake_installed mintstick
win OK OUT:1 OK OUT:0
check_eq 'detect: back to the menu and out' 'Exiting...' "$(strip | tail -n1)"
has 'detect: an info window' --info 3
assert_contains 'detect: the application, its package and size' "$(zj 3)" 'USB Tools (USB Image Writer + USB Stick Formatter)  [mintstick 1.0, 1.0 MB]'
assert_contains 'detect: the count' "$(zj 3)" '1 application detected.'
new_sandbox
win OK OUT:1 OK OUT:0
assert_contains 'detect with nothing installed: says so' "$(zj 3)" '0 applications detected.'

echo "-- Option 2: uninstall"
# Option 2 only scans and goes from the menu straight to the list: unlike option 1, it opens no detection window.
new_sandbox; fake_installed mintstick
win OK OUT:2 'OUT:"1"' OK OK OK OUT:0
check_eq 'uninstall, confirmed: status 0' 0 "$RC"
check_eq 'uninstall, confirmed: the real removal ran' 1 "$(real_removals)"
assert_contains 'uninstall, confirmed: apt purged the package' "$(apt_log)" 'apt-get purge -y mintstick'
assert_contains 'uninstall, confirmed: with administrator rights' "$(sudo_log)" 'apt-get purge -y mintstick'
check_eq 'uninstall, confirmed: a record was saved' 1 "$(state_files | wc -l)"
check_eq 'uninstall, confirmed: simulated first, twice (plan and re-check)' 2 "$(grep -c '^apt-get -s purge' <<< "$(apt_log)")"
check_eq 'uninstall: help, menu, list, plan, question, progress, result, menu' 8 "$(zenity_calls)"
has 'list: a checklist' --checklist 3
assert_contains 'list: nothing ticked, the number is the tag' "$(zj 3)" '~FALSE~1~USB Tools (USB Image Writer + USB Stick Formatter) — Write ISO images and format USB drives~'
has 'plan: an info window' --info 4
assert_contains 'plan: it is the real plan of the manager (simulation)' "$(zj 4)" 'REAL plan that the package manager would execute (simulation)'
assert_contains 'plan: with what apt would remove' "$(zj 4)" 'Purg mintstick [1.0]'
has 'question: starts on Cancel, so Enter does not confirm' --default-cancel 5
has 'question: the button that confirms says what it does' --ok-label=Uninstall 5
has 'question: and the other one cancels' --cancel-label=Cancel 5
assert_contains 'question: it lists what goes' "$(zj 5)" 'The following applications will be removed:'
has 'progress: a progress window' --progress 6
has 'progress: it pulses (apt-get gives no percentage)' --pulsate 6
has 'progress: it closes by itself' --auto-close 6
has 'progress: without a Cancel button (apt-get would go on)' --no-cancel 6
has 'progress: with the title of the program' '--title=MintApp Remover' 6
has 'progress: and the text says what is going on' '--text=Uninstalling...' 6
has 'result: an info window' --info 7
assert_contains 'result: success' "$(zj 7)" 'Uninstallation completed successfully.'

new_sandbox; fake_installed mintstick
win OK OUT:2 'OUT:"1"' OK CANCEL OUT:0
check_eq 'uninstall, Cancel at the question: back to the menu' 'Exiting...' "$(strip | tail -n1)"
check_eq 'uninstall, Cancel: nothing was removed' 0 "$(real_removals)"
check_eq 'uninstall, Cancel: administrator rights were not asked for' '' "$(sudo_log)"
check_eq 'uninstall, Cancel: no record' 0 "$(state_files | wc -l)"
check_eq 'uninstall, Cancel: the next window is the menu' 6 "$(zenity_calls)"
has 'uninstall, Cancel: ... and it is a menu' --column=Description 6

new_sandbox; fake_installed mintstick
win OK OUT:2 CANCEL OUT:0
check_eq 'uninstall, Esc in the list: back to the menu, nothing removed' 0 "$(real_removals)"
has 'uninstall, Esc in the list: the next window is the menu' --column=Description 4

new_sandbox; fake_installed mintstick
win OK OUT:2 'OUT:' OK OUT:0
assert_contains 'uninstall, nothing ticked: says so' "$(zj 4)" 'No applications were selected.'
check_eq 'uninstall, nothing ticked: nothing removed' 0 "$(real_removals)"

new_sandbox
win OK OUT:2 OK OUT:0
assert_contains 'uninstall with nothing installed: says so' "$(zj 3)" 'No installed applications from the curated catalog were detected.'

echo "-- Option 2: a plan that drags meta-packages (E14)"
new_sandbox; fake_installed mintstick; fake_dependents mintstick mint-meta-cinnamon mint-meta-core
win OK OUT:2 'OUT:"1"' OK CANCEL OUT:0
has 'meta-packages: the plan with the warning is long: a scrolling text window' --text-info 4
PLAN_TXT="$(zenity_stdin)"
assert_contains 'meta-packages: the plan window carries the warning' "$PLAN_TXT" 'WARNING: the plan also removes system meta-packages.'
assert_contains 'meta-packages: it lists them, one per line' "$PLAN_TXT" $'  - mint-meta-cinnamon\n  - mint-meta-core\n'
assert_contains 'meta-packages: the plan itself is in the same window' "$PLAN_TXT" 'Purg mintstick [1.0]'
before_warn="${PLAN_TXT%%WARNING:*}"; before_plan="${PLAN_TXT%%Purg mintstick*}"
check_eq 'meta-packages: the warning comes before the plan' yes "$([ "${#before_warn}" -lt "${#before_plan}" ] && echo yes || echo no)"
assert_contains 'meta-packages: the question is the stronger one' "$(zj 5)" 'The plan also removes system meta-packages (see the warning above).'
has 'meta-packages: the stronger question still starts on Cancel' --default-cancel 5
has 'meta-packages: and its confirming button still says what it does' --ok-label=Uninstall 5
check_eq 'meta-packages: Cancel removes nothing' 0 "$(real_removals)"

new_sandbox; fake_installed mintstick; fake_dependents mintstick mint-meta-cinnamon
win OK OUT:2 'OUT:"1"' OK OK OK OUT:0
check_eq 'meta-packages: the warning informs, it does not block: Uninstall goes on' 1 "$(real_removals)"

new_sandbox; fake_installed mintstick
win OK OUT:2 'OUT:"1"' OK CANCEL OUT:0
assert_not_contains 'meta-packages: a plan without them has no warning' "$(zj 4)" 'meta-packages'
assert_not_contains 'meta-packages: and the question is the usual one' "$(zj 5)" 'continue anyway'

echo "-- Option 3: other applications"
new_sandbox
win OK OUT:3 OK OUT:0
assert_contains 'other applications, none found: says so' "$(zj 3)" 'No additional applications were detected outside the curated catalog.'

echo "-- Option 4: clean up dependencies"
new_sandbox; fake_autoremovable libfoo1 libbar2
win OK OUT:4 OUT:1 OK OK OK OUT:0
check_eq 'clean up, confirmed: status 0' 0 "$RC"
assert_contains 'clean up, confirmed: autoremove ran' "$(apt_log)" 'apt-get autoremove -y'
assert_contains 'clean up, confirmed: and the cache was cleaned' "$(apt_log)" 'apt-get autoclean -y'
assert_contains 'clean up: the plan is the real one' "$(zj 4)" 'REAL plan that the package manager would execute (simulation): these packages'
assert_contains 'clean up: it lists the packages' "$(zj 4)" 'Remv libfoo1 [1.0]'
has 'clean up: the question starts on Cancel' --default-cancel 5
has 'clean up: a progress window for the removal' --progress 6
has 'clean up: another one for the cache' --progress 7
assert_contains 'clean up: the result' "$(zj 8)" 'Dependencies removed.'
new_sandbox; fake_autoremovable libfoo1 libbar2
win OK OUT:4 OUT:1 OK CANCEL OUT:0
check_eq 'clean up, Cancel: nothing was removed' 0 "$(real_removals)"
new_sandbox
win OK OUT:4 OUT:1 OK OUT:0
assert_contains 'clean up with nothing to remove: says so (after the progress of the cache)' "$(zj 5)" 'No unused dependencies were found; nothing to remove.'
check_eq 'clean up with nothing to remove: no removal' 0 "$(real_removals)"

# ----------------------------------------------------------------------------
# Administrator rights and progress in windows (improvement 1): the password helper of
# "sudo -A", priv_authenticate, the progress window while apt-get works, the apt output in the
# error window and the cleanup of the private folder. The password of these cases has spaces,
# quotes, "$" and shell characters on purpose: it must reach sudo exactly as it was typed.
# ----------------------------------------------------------------------------
PW='Pa ss w0rd $HOME '\''q'\'' "d" ;&|<x> z'
# fresh: a new sandbox with a TMPDIR of its own, where the private folder of the windows is made.
fresh() { new_sandbox; mkdir -p "$SB/tmp"; sandbox_chown; }
# ge CODE [VAR=val ...]: CODE with the windows usable and the private folder under $SB/tmp.
ge() { local code="$1"; shift; app_eval "zenity_usable; $code" "${GUI[@]}" TMPDIR="$SB/tmp" "$@"; }
# winp ANSWER...: the whole program in windows (as win) with that TMPDIR and the variables of XENV.
XENV=()
winp() { fake_zenity "$@"; app_run '' "${GUI[@]}" TMPDIR="$SB/tmp" "${XENV[@]+"${XENV[@]}"}"; }
# The user the program runs as: the sandbox user when the tests run as root.
APP_UID="$H_APP_UID"; [ "$(id -u)" -eq 0 ] || APP_UID="$(id -u)"
RETRY='--text=The password is not correct. Enter your administrator password again.'
# helper: what the helper does when run by hand: status|password.
helper() { ge 'make_askpass; pw="$("$ASKPASS_HELPER" "[sudo] password for tester: ")"; st=$?; printf "<<%s|%s>>" "$st" "$pw"' "$@"; }

echo "-- Password helper (sudo -A): the file, its folder and its window"
fresh
ge 'make_askpass; printf "<<%s>>%s|%s" "$?" "$ASKPASS_HELPER" "$GUI_WORK_DIR"'
value_of 'make_askpass: succeeds' 0
v="${OUT#*>>}"; HELPER="${v%%|*}"; WDIR="${v#*|}"
check_eq 'the folder is made under the TMPDIR' "$SB/tmp" "$(dirname "$WDIR")"
assert_contains 'the folder is called mintapp-gui.XXXXXX' "$WDIR" '/mintapp-gui.'
check_eq 'the helper is in that folder' "$WDIR/askpass" "$HELPER"
check_eq 'the folder is private (700)' 700 "$(stat -c %a "$WDIR")"
check_eq 'the helper can be run and read by its owner only (700)' 700 "$(stat -c %a "$HELPER")"
check_eq 'the folder belongs to the user that runs the program' "$APP_UID" "$(stat -c %u "$WDIR")"
check_eq 'and so does the helper' "$APP_UID" "$(stat -c %u "$HELPER")"
check_eq 'the helper is a /bin/sh script' '#!/bin/sh' "$(head -n1 "$HELPER")"
check_eq 'the helper is valid sh' 0 "$(/bin/sh -n "$HELPER" >/dev/null 2>&1; echo $?)"
assert_contains 'the helper starts zenity through bash, which gives its window the class of the others' "$(cat "$HELPER")" "-c 'exec -a \"\$0\" \"\$@\"' 'mintapp-remover' "
assert_not_contains 'the helper does not hold a password' "$(cat "$HELPER")" 'Pa ss'
fresh
ge 'make_askpass; make_askpass; make_askpass; printf "<<%s>>" "$(ls -d "$TMPDIR"/mintapp-gui.* | wc -l)"'
value_of 'make_askpass, called again: the same helper, one folder' 1
fresh; mkdir -p "$SB/run"; sandbox_chown
ge 'gui_work_dir; printf "<<%s>>" "$(dirname "$GUI_WORK_DIR")"' XDG_RUNTIME_DIR="$SB/run"
value_of 'with XDG_RUNTIME_DIR the folder is made there' "$SB/run"
ge 'gui_work_dir; printf "<<%s>>" "$(dirname "$GUI_WORK_DIR")"' XDG_RUNTIME_DIR="$SB/nowhere"
value_of 'a XDG_RUNTIME_DIR that does not exist: the TMPDIR' "$SB/tmp"
ge 'gui_work_dir; printf "<<%s>>" "$?"' TMPDIR="$SB/nowhere"
value_of 'no place to make it: gui_work_dir fails' 1
ge 'make_askpass; printf "<<%s>>" "$?"' TMPDIR="$SB/nowhere"
value_of 'no place to make it: make_askpass fails' 1
ge 'PATH=/nonexistent; make_askpass; printf "<<%s>>" "$?"'
value_of 'no zenity: make_askpass fails' 1

echo "-- Password helper: what it asks and what it returns"
fresh
fake_zenity "OUT:$PW"
helper
value_of 'it prints exactly what was typed and ends with 0' "0|$PW"
check_eq 'it opened one window' 1 "$(zenity_calls)"
has 'a password entry' --entry 1
has 'the text typed is hidden' --hide-text 1
has 'with the title of the program' '--title=MintApp Remover' 1
has 'the first time it asks plainly' '--text=Enter your administrator password to continue.' 1
has 'OK button' --ok-label=OK 1
has 'Cancel button' --cancel-label=Cancel 1
lacks 'the prompt of sudo is not shown (it is not for the user)' '--text=[sudo] password for tester: ' 1
assert_not_contains 'the window is not given the password' "$(zj 1)" 'Pa ss'
lacks 'the window has no initial text' --entry-text= 1
fake_zenity CANCEL
helper
value_of 'Cancel: status 1 and no password' '1|'
fake_zenity OUT:a OUT:b OUT:c
ge 'make_askpass; for i in 1 2 3; do "$ASKPASS_HELPER" >/dev/null; done; printf "<<%s>>" "$(cat "$GUI_WORK_DIR/tries")"'
value_of 'it counts its tries' 3
lacks 'the first try asks plainly' "$RETRY" 1
has 'the second try says the password was wrong' "$RETRY" 2
has 'and so does the third' "$RETRY" 3
fake_zenity OUT:a
helper MINTAPP_LANG=es
has 'in Spanish: the text' '--text=Escribe tu contraseña de administrador para continuar.' 1
has 'in Spanish: OK' --ok-label=Aceptar 1
has 'in Spanish: Cancel' --cancel-label=Cancelar 1
# Texts with quotes and shell syntax reach the window unchanged and run nothing.
HOST='It'\''s "x" $(touch "$HOME/pwned") `touch "$HOME/pwned2"` ; touch "$HOME/pwned3" # end'
fake_zenity OUT:a
ge 'MSG_EN[askpass_text]=$HOST; WT_TITLE=$HOST; make_askpass; "$ASKPASS_HELPER" >/dev/null; printf "<<%s>>" "$?"' HOST="$HOST"
value_of 'a hostile text: the helper still works' 0
has 'a hostile text: it is shown as it is' "--text=$HOST" 1
has 'a hostile title: shown as it is' "--title=$HOST" 1
check_eq 'a hostile text: nothing was run' none "$(compgen -G "$SB/home/pwned*" >/dev/null && echo created || echo none)"
fake_zenity OUT:a
ge 'GUI_LOCALE=C.UTF-8; make_askpass; printf "<<%s>>" "$(grep -c "^LC_ALL=C.UTF-8; export LC_ALL$" "$ASKPASS_HELPER")"'
value_of 'with a locale for zenity, the helper runs it under that locale' 1
ge 'GUI_LOCALE=; make_askpass; printf "<<%s>>" "$(grep -c "LC_ALL" "$ASKPASS_HELPER" || true)"'
value_of 'without one, the helper sets none' 0

echo "-- Password helper: it follows the language of the program"
fresh
fake_zenity OUT:a OUT:a
ge 'make_askpass; set_language es; make_askpass; "$ASKPASS_HELPER" >/dev/null; printf "<<%s>>" "$?"'
value_of 'after switching to Spanish: the helper works' 0
has 'after switching to Spanish: the window is in Spanish' '--text=Escribe tu contraseña de administrador para continuar.' 1
has 'after switching to Spanish: and so are its buttons' --ok-label=Aceptar 1
fake_zenity OUT:a OUT:a
ge 'set_language es; make_askpass; set_language en; make_askpass; "$ASKPASS_HELPER" >/dev/null; printf "<<%s>>" "$?"'
has 'and back to English' '--text=Enter your administrator password to continue.' 1
fresh
ge 'make_askpass; set_language es; make_askpass; set_language en; make_askpass; printf "<<%s>>" "$(ls -d "$TMPDIR"/mintapp-gui.* | wc -l)"'
value_of 'switching language rewrites the helper in the same folder' 1

echo "-- priv_authenticate: the password comes first, in a window"
fresh
# pa LABEL EXPECTED [VAR=val ...]: status of priv_authenticate in windows.
pa() { local label="$1" expected="$2"; shift 2; ge 'UI_ENGINE=gui; priv_authenticate; printf "<<%s>>" "$?"' "$@"; value_of "$label" "$expected"; }
pa 'no password needed: 0' 0
check_eq 'no password needed: it only checked (sudo -A -v)' 'sudo -A -v' "$(sudo_log)"
check_eq 'no password needed: no window' 0 "$(zenity_calls)"
fake_sudo_password "$PW"; fake_zenity "OUT:$PW"
pa 'right password: 0' 0
check_eq 'right password: sudo got it' "$PW" "$(sudo_given)"
check_eq 'right password: one window' 1 "$(zenity_calls)"
fake_sudo_password "$PW"; fake_zenity OUT:bad "OUT:$PW"
pa 'wrong and then right: 0' 0
check_eq 'wrong and then right: both tries reached sudo' "bad"$'\n'"$PW" "$(sudo_given)"
has 'wrong and then right: the second window says it was wrong' "$RETRY" 2
fake_sudo_password "$PW"; fake_zenity OUT:bad1 OUT:bad2 OUT:bad3
pa 'three wrong passwords: no rights (77)' 77
check_eq 'three wrong passwords: three windows' 3 "$(zenity_calls)"
fake_sudo_password "$PW"; fake_zenity CANCEL
pa 'cancelled: no rights (77)' 77
check_eq 'cancelled: one window, nothing typed' 1 "$(zenity_calls)"
check_eq 'cancelled: sudo got nothing' '' "$(sudo_given)"
# The counter starts again with each request: a second request does not open with "wrong".
fake_sudo_password "$PW"; fake_zenity OUT:x OUT:y OUT:z "OUT:$PW"
ge 'UI_ENGINE=gui; priv_authenticate; a=$?; priv_authenticate; b=$?; printf "<<%s %s>>" "$a" "$b"'
value_of 'a failed request and then a good one' '77 0'
lacks 'the second request opens with the plain text' "$RETRY" 4
fake_sudo_password "$PW"; fake_zenity "OUT:$PW"
ge 'UI_ENGINE=gui; priv_authenticate; printf "<<%s>>" "${SUDO_ASKPASS-unset}"'
value_of 'SUDO_ASKPASS is only for that sudo, it is not left in the environment' unset
ge 'UI_ENGINE=tui; priv_authenticate; printf "<<%s>>" "$?"'
value_of 'on the terminal: nothing to do (sudo asks by itself)' 0
ge 'UI_ENGINE=whiptail; priv_authenticate; printf "<<%s>>" "$?"'
value_of 'with whiptail: nothing to do' 0
ge 'UI_ENGINE=text; priv_authenticate; printf "<<%s>>" "$?"'
value_of 'in text mode: nothing to do' 0
fresh
printf '#!/bin/sh\necho "doas $*" >> "%s/state/sudo.log"\nexit 0\n' "$SB" > "$SB/bin/doas"; chmod 755 "$SB/bin/doas"; sandbox_chown
pa 'doas cannot ask in a window: it passes' 0 MINTAPP_SUDO=doas
check_eq 'doas: it was not run' '' "$(sudo_log)"
pa 'no sudo and no doas: it passes (the start already refused)' 0 MINTAPP_SUDO=no-such-command
check_eq 'no sudo and no doas: nothing was run' '' "$(sudo_log)"
fake_sudo_password "$PW"; fake_zenity "OUT:$PW"
ge 'UI_ENGINE=gui; PRIV_CMD="$(type -P sudo)"; PATH=/nonexistent; priv_authenticate; printf "<<%s>>" "$?"'
value_of 'the helper cannot be made (no zenity): no rights (77)' 77
check_eq 'the helper cannot be made: sudo was not run' '' "$(sudo_log)"
pa 'no folder for the helper: no rights (77)' 77 TMPDIR="$SB/nowhere"
check_eq 'no folder for the helper: sudo was not run' '' "$(sudo_log)"

echo "-- Uninstall in windows: the password comes before the record and the progress"
fresh; fake_installed mintstick
winp OK OUT:2 'OUT:"1"' OK OK OK OUT:0
check_eq 'no password needed: eight windows, as before' 8 "$(zenity_calls)"
check_eq 'no password needed: rights first, then the removal, both with -A' \
    "sudo -A -v"$'\n'"sudo -A DEBIAN_FRONTEND=noninteractive apt-get purge -y mintstick" "$(sudo_log)"
check_eq 'a whole run leaves no private folder behind' '' "$(ls -A "$SB/tmp")"
fresh; fake_installed mintstick; fake_sudo_password "$PW"
winp OK OUT:2 'OUT:"1"' OK OK "OUT:$PW" OK OUT:0
check_eq 'right password: status 0' 0 "$RC"
check_eq 'right password: nine windows (help, menu, list, plan, question, password, progress, result, menu)' 9 "$(zenity_calls)"
has 'right password: after the question, the password entry' --entry 6
has 'right password: hidden' --hide-text 6
has 'right password: and then the progress window' --progress 7
assert_contains 'right password: the result' "$(zj 8)" 'Uninstallation completed successfully.'
check_eq 'right password: the package was purged' 1 "$(real_removals)"
check_eq 'right password: one record' 1 "$(state_files | wc -l)"
check_eq 'right password: sudo got what was typed, once (the ticket did the rest)' "$PW" "$(sudo_given)"
check_eq 'right password: rights first, then the removal, both with -A' \
    "sudo -A -v"$'\n'"sudo -A DEBIAN_FRONTEND=noninteractive apt-get purge -y mintstick" "$(sudo_log)"
check_eq 'right password: the helper (700) was in a private folder (700)' '700 700' "$(askpass_modes | cut -d' ' -f1 | paste -sd' ')"
check_eq 'right password: sudo ran the helper that the program wrote' '#!/bin/sh' "$(askpass_copy | head -n1)"
check_eq 'right password: the private folder is gone at the end' '' "$(ls -A "$SB/tmp")"
check_eq 'right password: it is nowhere else (logs, records, helper, calls)' '' \
    "$(grep -rlF --exclude=zenity.answers --exclude=sudo.password --exclude=sudo.given -- "$PW" "$SB" 2>/dev/null || true)"

fresh; fake_installed mintstick; fake_sudo_password "$PW"
winp OK OUT:2 'OUT:"1"' OK OK OUT:bad1 "OUT:$PW" OK OUT:0
check_eq 'wrong and then right: status 0' 0 "$RC"
check_eq 'wrong and then right: ten windows' 10 "$(zenity_calls)"
has 'wrong and then right: the second try says it was wrong' "$RETRY" 7
lacks 'wrong and then right: the first one did not' "$RETRY" 6
has 'wrong and then right: then the progress window' --progress 8
check_eq 'wrong and then right: the package was purged' 1 "$(real_removals)"
check_eq 'wrong and then right: sudo got both tries' "bad1"$'\n'"$PW" "$(sudo_given)"

fresh; fake_installed mintstick; fake_sudo_password "$PW"
winp OK OUT:2 'OUT:"1"' OK OK OUT:bad1 OUT:bad2 OUT:bad3 OK OUT:0
check_eq 'three wrong passwords: the program goes on to the menu and leaves' 0 "$RC"
check_eq 'three wrong passwords: ten windows' 10 "$(zenity_calls)"
has 'three wrong passwords: the second try says it was wrong' "$RETRY" 7
has 'three wrong passwords: and the third' "$RETRY" 8
lacks 'three wrong passwords: the first did not' "$RETRY" 6
assert_contains 'three wrong passwords: the result says there were no rights' "$(zj 9)" 'Administrator rights were not obtained'
assert_contains 'three wrong passwords: and that nothing was uninstalled' "$(zj 9)" 'Nothing was uninstalled.'
check_eq 'three wrong passwords: nothing was purged' 0 "$(real_removals)"
assert_not_contains 'three wrong passwords: and sudo never ran apt-get' "$(sudo_log)" 'apt-get purge'
check_eq 'three wrong passwords: no record (the password comes first)' 0 "$(state_files | wc -l)"
check_eq 'three wrong passwords: no progress window' 0 "$(grep -c -- '^--progress$' "$SB/state/zenity.args" || true)"
check_eq 'three wrong passwords: no "record saved" note on a refusal' 0 "$(zj 9 | grep -c 'record' || true)"
check_eq 'three wrong passwords: the private folder is gone' '' "$(ls -A "$SB/tmp")"

fresh; fake_installed mintstick; fake_sudo_password "$PW"
winp OK OUT:2 'OUT:"1"' OK OK CANCEL OK OUT:0
check_eq 'cancelled: eight windows (help, menu, list, plan, question, password, result, menu)' 8 "$(zenity_calls)"
assert_contains 'cancelled: the result says there were no rights' "$(zj 7)" 'Administrator rights were not obtained'
check_eq 'cancelled: nothing was purged' 0 "$(real_removals)"
check_eq 'cancelled: no record' 0 "$(state_files | wc -l)"
check_eq 'cancelled: sudo got nothing' '' "$(sudo_given)"
check_eq 'cancelled: no progress window' 0 "$(grep -c -- '^--progress$' "$SB/state/zenity.args" || true)"

echo "-- Clean up dependencies in windows with a sudo password"
fresh; fake_autoremovable libfoo1 libbar2; fake_sudo_password "$PW"
winp OK OUT:4 OUT:1 OK OK "OUT:$PW" OK OUT:0
check_eq 'clean up, right password: ten windows (the cache has its own progress)' 10 "$(zenity_calls)"
has 'clean up, right password: the password after the question' --entry 6
has 'clean up, right password: progress of the removal' --progress 7
has 'clean up, right password: progress of the cache' --progress 8
assert_contains 'clean up, right password: the result' "$(zj 9)" 'Dependencies removed.'
check_eq 'clean up, right password: asked once, for both steps' "$PW" "$(sudo_given)"
assert_contains 'clean up, right password: the cache was cleaned' "$(sudo_log)" 'apt-get autoclean -y'
fresh; fake_autoremovable libfoo1 libbar2; fake_sudo_password "$PW"
winp OK OUT:4 OUT:1 OK OK CANCEL OK OUT:0
check_eq 'clean up, cancelled: eight windows' 8 "$(zenity_calls)"
assert_contains 'clean up, cancelled: it says there were no rights' "$(zj 7)" 'Administrator rights were not obtained'
check_eq 'clean up, cancelled: nothing was removed' 0 "$(real_removals)"
assert_not_contains 'clean up, cancelled: the cache was not touched either' "$(sudo_log)" 'autoclean'
fresh; fake_sudo_password "$PW"
winp OK OUT:4 OUT:1 CANCEL OK OUT:0
check_eq 'nothing to remove, password cancelled for the cache: six windows' 6 "$(zenity_calls)"
assert_contains 'nothing to remove, password cancelled for the cache: it says there were no rights' "$(zj 5)" 'Administrator rights were not obtained'
check_eq 'nothing to remove, password cancelled for the cache: the cache was not cleaned' 0 "$(grep -c autoclean <<< "$(apt_log)" || true)"
fresh; fake_sudo_password "$PW"
winp OK OUT:4 OUT:1 "OUT:$PW" OK OUT:0
check_eq 'nothing to remove, right password: the cache was cleaned' 1 "$(grep -c 'autoclean -y' <<< "$(apt_log)" || true)"
has 'nothing to remove, right password: with a progress window' --progress 5

echo "-- Progress window: the line that follows apt-get"
fresh
# feed LABEL EXPECTED LOG: what gui_progress_feed prints for a log (LOG is a printf format).
feed() {
    local label="$1" expected="$2"
    ge 'printf "$LOG" > "$HOME/l"; : > "$HOME/r"; sleep() { rm -f "$HOME/r"; }; out="$(gui_progress_feed "$HOME/l" "$HOME/r")"; printf "<<%s>>" "$out"' LOG="$3"
    value_of "$label" "$expected"
}
feed 'the last line of the log is the text of the window' '# Removing foo ...' 'Reading package lists...\nRemoving foo ...\n'
feed 'a progress bar redraws the line with a carriage return: the last piece' '# Progress: [ 50%]' 'Get:1 a\rProgress: [ 50%%]\r'
feed 'empty and blank lines do not count' '# Removing foo' 'Removing foo\n   \n\n'
feed 'an empty log shows nothing' '' ''
feed 'a tab is a space' '# a b' 'a\tb\n'
feed 'a backslash is a slash (zenity reads it as an escape)' '# a/b' 'a\\b\n'
feed 'escape sequences lose their escape' '# ok[31m red' 'ok\033[31m red\n'
feed 'markup characters are spaces (the label reads Pango markup)' '# Unpacking  b  x' 'Unpacking <b>&x\n'
feed 'a long line is cut to 64 characters' "# $(printf 'x%.0s' {1..61})..." "$(printf 'x%.0s' {1..70})\\n"
ge 'printf "one\n" > "$HOME/l"; : > "$HOME/r"; n=0
    sleep() { n=$((n + 1)); case $n in 1|2) printf "two\n" >> "$HOME/l" ;; *) rm -f "$HOME/r" ;; esac; }
    printf "<<%s>>" "$(gui_progress_feed "$HOME/l" "$HOME/r" | paste -sd, -)"'
value_of 'a new line is shown once; the same line again is not repeated' '# one,# two'
ge ': > "$HOME/l"; printf "<<%s>>" "$(gui_progress_feed "$HOME/l" "$HOME/none")"'
value_of 'without the "running" file it ends at once and shows nothing' ''
ge ': > "$HOME/r"; sleep() { rm -f "$HOME/r"; }; printf "<<%s>>" "$(gui_progress_feed "$HOME/none" "$HOME/r")"'
value_of 'a log that does not exist yet shows nothing and does not fail' ''

echo "-- Progress window: closing it"
fresh
ge 'gui_progress_stop; printf "<<%s>>" "$?"'
value_of 'no window: nothing to close' 0
ge '(exit 0) & GUI_PROGRESS_PID=$!; gui_progress_stop; printf "<<%s|%s>>" "$?" "$GUI_PROGRESS_PID"'
value_of 'a window that ended by itself: its pid is forgotten' '0|'
ge '/usr/bin/sleep 20 & p=$!; GUI_PROGRESS_PID=$p; gui_progress_stop; printf "<<%s|%s>>" "$(kill -0 "$p" 2>/dev/null && echo alive || echo gone)" "$GUI_PROGRESS_PID"'
value_of 'a window that does not end: it is stopped' 'gone|'

echo "-- The last lines of apt-get for the error window"
fresh
# tail_of LABEL EXPECTED LOG: step_tail_text of a log (LOG is a printf format), lines joined by ",".
tail_of() {
    local label="$1" expected="$2"
    ge 'printf "$LOG" > "$HOME/l"; printf "<<%s>>" "$(step_tail_text "$HOME/l" | paste -sd, -)"' LOG="$3"
    value_of "$label" "$expected"
}
ge 'seq 1 20 > "$HOME/l"; printf "<<%s>>" "$(step_tail_text "$HOME/l" | paste -sd, -)"'
value_of 'only the last 12 lines' '9,10,11,12,13,14,15,16,17,18,19,20'
tail_of 'fewer lines: all of them' 'a,b' 'a\nb\n'
tail_of 'a progress bar ends a line with a carriage return' 'Get 1,Progress 50%' 'Get 1\rProgress 50%%\r\n'
tail_of 'blank lines are skipped' 'a,b' 'a\n\n  \nb\n'
tail_of 'control characters are removed' 'a[0mb' 'a\033[0mb\n'
tail_of 'a backslash is a slash' 'C:/dir/x' 'C:\\dir\\x\n'
tail_of 'an empty log is an empty text' '' ''
ge 'printf "$LOG" > "$HOME/l"; t="$(step_tail_text "$HOME/l")"; printf "<<%s|%s>>" "${#t}" "${t: -3}"' LOG="$(printf 'x%.0s' {1..150})\\n"
value_of 'a line of 150 characters is cut to 100, with "..."' '100|...'
ge 'printf "$LOG" > "$HOME/l"; t="$(step_tail_text "$HOME/l")"; printf "<<%s>>" "${#t}"' LOG="$(printf 'x%.0s' {1..100})\\n"
value_of 'a line of exactly 100 characters is not cut' 100

echo "-- package manager in windows: run_pm_gui"
fresh; fake_installed mintstick
fake_zenity
ge 'UI_ENGINE=gui; PM_TAIL=stale; run_pm_gui "Working <on> it..." purge mintstick; st=$?; printf "<<%s|%s|%s>>" "$st" "$GUI_PROGRESS_PID" "$PM_TAIL"'
value_of 'it returns the status of apt-get, closes the window and keeps the last line' '0||Removing mintstick ...'
check_eq 'the package was purged' 1 "$(real_removals)"
check_eq 'one window: the progress one' 1 "$(zenity_calls)"
has 'a progress window' --progress 1
has 'it pulses (apt-get gives no percentage)' --pulsate 1
has 'it closes by itself' --auto-close 1
has 'without a Cancel button (apt-get would go on)' --no-cancel 1
has 'with the title of the program' '--title=MintApp Remover' 1
has 'the text is the one given, as it is written for a label' '--text=Working &lt;on&gt; it...' 1
assert_contains 'with the narrowest width of a progress window (its lines are short)' "$(zj 1)" '~--width=440~'
check_eq 'its input ended (that is what closes it)' 1 "$(grep -c '^@@END@@$' "$SB/state/zenity.stdin")"
check_eq 'apt-get was run with -A (a window, not a terminal, asks for the password)' \
    'sudo -A DEBIAN_FRONTEND=noninteractive apt-get purge -y mintstick' "$(sudo_log)"
ge 'UI_ENGINE=gui; run_pm_gui "x" purge mintstick'
check_eq 'the output of apt-get is not written on the terminal' '' "$OUT"
fresh; fake_installed mintstick; fake_zenity
ge "UI_ENGINE=gui; run_pm_gui \"$X80\" purge mintstick"
assert_contains 'a progress window with a long text takes the width it needs' "$(zj 1)" '~--width=544~'
fresh; fake_installed mintstick
ge 'UI_ENGINE=gui; run_pm_gui "x" purge mintstick; st=$?; printf "<<%s|%s>>" "$st" "$PM_TAIL"' FAKE_APT_FAIL=100
value_of 'apt-get fails: its status and its error line are kept' '100|E: Sub-process /usr/bin/dpkg returned an error code (1)'
check_eq 'apt-get fails: the package is still installed' 1 "$(grep -cx mintstick "$SB/state/installed")"
fresh; fake_installed mintstick
ge 'UI_ENGINE=gui; run_pm_gui "x" purge mintstick; st=$?; printf "<<%s|%s>>" "$st" "$PM_TAIL"' TMPDIR="$SB/nowhere"
value_of 'no private folder: apt-get runs without the window and the status is its own' '0|'
check_eq 'no private folder: it was purged' 1 "$(real_removals)"
check_eq 'no private folder: no progress window' 0 "$(zenity_calls)"
check_eq 'no private folder: no -A either (nothing to ask with)' \
    'sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y mintstick' "$(sudo_log)"
fresh; fake_installed mintstick
ge 'UI_ENGINE=text; run_pm_step "x" purge mintstick; printf "<<%s>>" "$?"'
value_of 'on the terminal, run_pm_step runs the manager as it is' 0
check_eq 'on the terminal: no window' 0 "$(zenity_calls)"
check_eq 'on the terminal: without -A (sudo asks on the terminal)' \
    'sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y mintstick' "$(sudo_log)"
assert_contains 'on the terminal: the output of apt-get is seen' "$OUT" 'Removing mintstick ...'

echo "-- A failed removal: what the error window says"
fresh
# etext LABEL ENGINE STATUS TAIL [VAR=val ...]: the text removal_error_text gives (in OUT).
etext() {
    local engine="$2" st="$3" apt_out="$4"; shift 4
    ge 'UI_ENGINE=$ENG; PM_TAIL=$TAIL; removal_error_text "$ST"; printf "%s" "$REPLY"' ENG="$engine" ST="$st" TAIL="$apt_out" "$@"
}
etext x gui 100 'E: boom'
assert_contains 'windows: what failed' "$OUT" 'Uninstallation failed (exit code 100).'
assert_contains 'windows: the last lines of apt' "$OUT" $'Last lines of the package manager output:\nE: boom'
assert_not_contains 'windows: no "look above" (there is no terminal to look at)' "$OUT" 'above'
etext x tui 100 'E: boom'
assert_contains 'terminal: it points at the terminal' "$OUT" 'Check the package manager output above in the terminal.'
assert_not_contains 'terminal: the lines are not repeated' "$OUT" 'E: boom'
etext x text 100 'E: boom'
assert_contains 'text mode: it points at the terminal' "$OUT" 'Check the package manager output above in the terminal.'
etext x gui 77 'E: boom'
assert_contains 'no rights, in windows: it says so' "$OUT" 'Administrator rights were not obtained'
assert_not_contains 'no rights, in windows: and does not show an old apt output' "$OUT" 'E: boom'
etext x tui 77 ''
assert_contains 'no rights, on the terminal: the same' "$OUT" 'Administrator rights were not obtained'
etext x gui 100 'E: fallo' MINTAPP_LANG=es
assert_contains 'Spanish: what failed' "$OUT" 'Hubo un problema durante la desinstalación (código de salida 100).'
assert_contains 'Spanish: the last lines' "$OUT" $'Últimas líneas de la salida del gestor de paquetes:\nE: fallo'
etext x gui 77 '' MINTAPP_LANG=es
assert_contains 'Spanish: no rights' "$OUT" 'No se obtuvieron permisos de administrador'

fresh; fake_installed mintstick
XENV=(FAKE_APT_FAIL=100 FAKE_APT_FAIL_ACTION=purge)
winp OK OUT:2 'OUT:"1"' OK OK OK OUT:0
XENV=()
check_eq 'uninstall fails: eight windows (the progress one included)' 8 "$(zenity_calls)"
has 'uninstall fails: the progress window was shown' --progress 6
assert_contains 'uninstall fails: the error window says what failed' "$(zj 7)" 'Uninstallation failed (exit code 100).'
assert_contains 'uninstall fails: it shows the output of apt, which no terminal shows' "$(zj 7)" 'E: Sub-process /usr/bin/dpkg returned an error code (1)'
assert_contains 'uninstall fails: and where the record is' "$(zj 7)" 'removal-'
check_eq 'uninstall fails: the record says it failed' 1 "$(grep -c 'Status: failed (apt-get exit code 100)' "$(state_files)")"
check_eq 'uninstall fails: the program goes on to the menu and leaves' 0 "$RC"
fresh; fake_autoremovable libfoo1; fake_sudo_password "$PW"
XENV=(FAKE_APT_FAIL=100 FAKE_APT_FAIL_ACTION=autoremove)
winp OK OUT:4 OUT:1 OK OK "OUT:$PW" OK OUT:0
XENV=()
check_eq 'clean up fails: nine windows (help, menu, action, plan, question, password, progress, error, menu)' 9 "$(zenity_calls)"
assert_contains 'clean up fails: the error window shows the output of apt' "$(zj 8)" 'E: Sub-process /usr/bin/dpkg returned an error code (1)'
assert_not_contains 'clean up fails: the cache step did not run' "$(sudo_log)" 'autoclean'

echo "-- Cleaning up: the private folder and the progress window"
fresh
ge 'make_askpass; d="$GUI_WORK_DIR"; gui_cleanup; printf "<<%s|%s|%s>>" "$([ -e "$d" ] && echo kept || echo gone)" "$GUI_WORK_DIR" "$ASKPASS_HELPER"'
value_of 'gui_cleanup: the folder is gone and the variables are empty' 'gone||'
ge 'gui_cleanup; printf "<<%s>>" "$?"'
value_of 'gui_cleanup with nothing to clean: no error' 0
ge 'mkdir -p "$HOME/precious"; : > "$HOME/precious/f"; GUI_WORK_DIR="$HOME/precious"; gui_cleanup; printf "<<%s>>" "$([ -e "$HOME/precious/f" ] && echo kept || echo gone)"'
value_of 'gui_cleanup: it never removes a folder it did not make' kept
ge '/usr/bin/sleep 20 & p=$!; GUI_PROGRESS_PID=$p; gui_cleanup; wait "$p"; printf "<<%s|%s>>" "$?" "$GUI_PROGRESS_PID"'
value_of 'gui_cleanup: it closes a progress window that is still open' '143|'
ge 'install_traps; make_askpass; kill -TERM $$'
check_eq 'SIGTERM with the helper made: the program ends with 143' 143 "$RC"
check_eq 'SIGTERM: the private folder is gone' '' "$(ls -A "$SB/tmp")"
ge 'install_traps; make_askpass; kill -HUP $$'
check_eq 'SIGHUP (the terminal or the session closes): the private folder is gone' '' "$(ls -A "$SB/tmp")"
ge 'install_traps; make_askpass; exit 3'
check_eq 'exit with an error: the private folder is gone' '' "$(ls -A "$SB/tmp")"

new_sandbox
echo "-- Without windows: the program takes the plain-text menu and does not call zenity"
fake_zenity OK
app_run $'0\n' MINTAPP_UI=gui MINTAPP_LANG=en
check_eq 'MINTAPP_UI=gui without a display: status 0' 0 "$RC"
assert_contains 'MINTAPP_UI=gui without a display: the plain-text menu' "$(plain)" '1. Detect applications'
check_eq 'MINTAPP_UI=gui without a display: zenity did not run' 0 "$(zenity_calls)"
alt_zenity --switch
app_run $'0\n' DISPLAY=:99 MINTAPP_UI=gui MINTAPP_LANG=en PATH="$(ALT_PATH)"
assert_contains 'a zenity without --switch: the plain-text menu' "$(plain)" '1. Detect applications'
rm -rf "$SB/alt"

echo "-- From another interface to the windows (G) and back (T)"
new_sandbox
fake_answers OK TAG:G
fake_zenity OUT:0
app_run '' MINTAPP_UI=whiptail DISPLAY=:99 MINTAPP_LANG=en MINTAPP_ASCII=0
check_eq 'G in whiptail: the program goes on in windows and exits: status 0' 0 "$RC"
check_eq 'G: the whiptail screens were the help and one menu' 2 "$(grep -c '^@@END@@$' "$SB/state/whiptail.args")"
check_eq 'G: the next menu is one zenity window' 1 "$(zenity_calls)"
has 'G: and it is a menu' --column=Description
assert_not_contains 'G: it does not offer G again' "$(zj)" '~G~'
check_eq 'G: the choice is remembered' 'interface=gui' "$(grep -x 'interface=gui' "$SB/home/.config/mintapp-remover/config")"
new_sandbox
if command -v script >/dev/null 2>&1; then
    pty() {  # pty CODE [VAR=val ...]: CODE in the program on a pseudo-terminal; OUT as with app_eval
        local cmd code="$1"; shift
        printf -v cmd '%q ' "$H_BASH" -c 'source "$1"; eval "$2"' bash "$H_SCRIPT" "$code"
        _exec '' 60 "$@" -- "$(command -v script)" -qec "$cmd" /dev/null
        OUT="${OUT//$'\r'/}"
    }
    pty 'build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"' "${GUI[@]}"
    value_of 'gui on a terminal: T (back to the terminal) between 4 and L' '1 2 3 4 T L 0'
    pty 'switch_to_terminal; printf "<<%s %s>>" "$UI_ENGINE" "$HAVE_WHIPTAIL"' "${GUI[@]}"
    value_of 'T: the program'"'"'s own dialogs take over' 'tui 1'
    check_eq 'T: the choice is remembered' 'interface=terminal' "$(grep -x 'interface=terminal' "$SB/home/.config/mintapp-remover/config")"
    pty 'build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"' MINTAPP_UI=tui DISPLAY=:99 MINTAPP_LANG=en
    value_of 'the terminal engine on a terminal: G, not T' '1 2 3 4 G L 0'
else
    skip_case 'T on a pseudo-terminal: needs "script" (util-linux)'
fi

echo "-- Command line: --gui and --terminal"
new_sandbox
NOWIN=(DISPLAY=:99 MINTAPP_LANG=en MINTAPP_ASCII=0)      # a display, no MINTAPP_UI: the program decides
fake_zenity OK
app_run '' "${NOWIN[@]}" -- --gui --terminal
check_eq '--gui with --terminal: status 2' 2 "$RC"
check_eq '--gui with --terminal: only the error, no usage' '--gui and --terminal cannot be used together.' "$OUT"
check_eq '--gui with --terminal: no window' 0 "$(zenity_calls)"
app_run '' "${NOWIN[@]}" -- --terminal --gui
check_eq 'the order of the two options does not matter' 2 "$RC"
app_run '' DISPLAY=:99 MINTAPP_LANG=es -- --gui --terminal
check_eq 'the conflict is explained in Spanish' '--gui y --terminal no pueden usarse a la vez.' "$OUT"
app_run '' "${NOWIN[@]}" -- --gui --gui
check_eq 'the same option twice is no conflict' 0 "$RC"
fake_zenity OK
app_run '' "${NOWIN[@]}" -- --gui --help
check_eq '--gui with --help: help, status 0' 0 "$RC"
assert_contains '--gui with --help: the help' "$OUT" 'Usage: MintApp_Remover.sh'
check_eq '--gui with --help: no window' 0 "$(zenity_calls)"
app_run '' "${NOWIN[@]}" -- --terminal --version
check_eq '--terminal with --version: the version only' "MintApp Remover $H_VERSION" "$OUT"
app_run '' "${NOWIN[@]}" -- --gui --nope
check_eq '--gui with an unknown option: status 2' 2 "$RC"
assert_contains '--gui with an unknown option: it is named' "$OUT" 'Unrecognized option: --nope'
app_run '' MINTAPP_LANG=en -- --help
for opt in --gui --terminal; do assert_contains "--help documents $opt" "$OUT" "  $opt "; done
assert_contains '--help says what happens without a terminal' "$OUT" 'Without a terminal (for example from the launcher) and with zenity, it'

echo "-- --gui: the windows, whatever else is set; an error when they cannot be opened"
win_run() {  # win_run ANSWER... -- VAR=val... -- ARGS...: the program with the stub zenity answering ANSWER...
    local -a answers=()
    while [ "$1" != "--" ]; do answers+=("$1"); shift; done
    shift
    fake_zenity "${answers[@]}"
    app_run '' "$@"
}
win_run OK OUT:0 -- "${NOWIN[@]}" -- --gui
check_eq '--gui without a terminal: help window and menu, status 0' 0 "$RC"
check_eq '--gui: two windows' 2 "$(zenity_calls)"
win_run OK OUT:0 -- "${NOWIN[@]}" MINTAPP_UI=text -- --gui
check_eq '--gui beats MINTAPP_UI=text' 2 "$(zenity_calls)"
fake_answers OK OK
win_run OK OUT:0 -- "${NOWIN[@]}" MINTAPP_UI=whiptail -- --gui
check_eq '--gui beats MINTAPP_UI=whiptail: windows' 2 "$(zenity_calls)"
check_eq '--gui beats MINTAPP_UI=whiptail: whiptail did not run' 0 "$(grep -c '^@@END@@$' "$SB/state/whiptail.args" || true)"
fake_zenity OK
app_run '' MINTAPP_LANG=en -- --gui
check_eq '--gui without a display: status 1' 1 "$RC"
check_eq '--gui without a display: it says why' '--gui needs zenity and a graphical session (DISPLAY or WAYLAND_DISPLAY).' "$OUT"
check_eq '--gui without a display: no window' 0 "$(zenity_calls)"
app_run '' MINTAPP_LANG=es MINTAPP_ASCII=0 -- --gui
check_eq '--gui without a display: the message in Spanish' '--gui necesita zenity y una sesión gráfica (DISPLAY o WAYLAND_DISPLAY).' "$OUT"
app_run '' DISPLAY=:99 MINTAPP_LANG=en PATH="$SB/emptybin" -- --gui
check_eq '--gui without zenity: status 1' 1 "$RC"
assert_contains '--gui without zenity: it says why' "$OUT" '--gui needs zenity'
app_run '' MINTAPP_LANG=en MINTAPP_UI=gui -- --gui
check_eq '--gui does not fall back like MINTAPP_UI=gui does' 1 "$RC"
app_run '' MINTAPP_LANG=en WAYLAND_DISPLAY=wayland-0 -- --gui
check_eq '--gui with a Wayland session alone is enough' 0 "$RC"
check_eq '--gui never reaches apt when it fails' 0 "$(apt_log | wc -l)"

echo "-- --terminal: never the windows"
fake_zenity OK
app_run $'0\n' "${NOWIN[@]}" -- --terminal
check_eq '--terminal without a terminal: the plain-text menu, status 0' 0 "$RC"
assert_contains '--terminal without a terminal: the plain-text menu' "$(plain)" '1. Detect applications'
check_eq '--terminal: zenity did not run' 0 "$(zenity_calls)"
app_run $'0\n' "${NOWIN[@]}" MINTAPP_UI=gui -- --terminal
assert_contains '--terminal beats MINTAPP_UI=gui' "$(plain)" '1. Detect applications'
check_eq '--terminal beats MINTAPP_UI=gui: zenity did not run' 0 "$(zenity_calls)"
fake_answers OK TAG:0
app_run '' "${NOWIN[@]}" MINTAPP_UI=whiptail -- --terminal
check_eq '--terminal leaves MINTAPP_UI=whiptail alone: whiptail screens' 2 "$(grep -c '^@@END@@$' "$SB/state/whiptail.args")"
check_eq '--terminal leaves MINTAPP_UI=whiptail alone: no window' 0 "$(zenity_calls)"

echo "-- Without a terminal and without options: the windows, when zenity can be used"
engine 'no terminal, zenity usable: gui'                 'gui 1' DISPLAY=:99
engine 'no terminal, Wayland session: gui'               'gui 1' WAYLAND_DISPLAY=wayland-0
engine 'no terminal, no display: plain text'             'text 0'
engine 'no terminal, no zenity: plain text'              'text 0' DISPLAY=:99 PATH="$SB/emptybin"
engine 'no terminal, MINTAPP_UI=text: plain text'        'text 0' DISPLAY=:99 MINTAPP_UI=text
engine 'no terminal, an unknown MINTAPP_UI: the default' 'gui 1' DISPLAY=:99 MINTAPP_UI=nope
win_run OK OUT:0 -- "${NOWIN[@]}"
check_eq 'a launcher: the program opens the windows by itself, status 0' 0 "$RC"
check_eq 'a launcher: help window and menu' 2 "$(zenity_calls)"
win_run OK OUT:0 -- "${NOWIN[@]}" MINTAPP_UI=text
check_eq 'MINTAPP_UI=text without a terminal: no window' 0 "$(zenity_calls)"

echo "-- On a terminal: the terminal rules, unless the windows are asked for"
if command -v script >/dev/null 2>&1; then
    pty_run() {  # pty_run [VAR=val ...] -- ARGS...: the program itself on a pseudo-terminal
        local -a envs=() args=()
        while [ "$#" -gt 0 ]; do
            if [ "$1" = "--" ]; then shift; args=("$@"); break; fi
            envs+=("$1"); shift
        done
        local cmd
        printf -v cmd '%q ' "$H_BASH" "$H_SCRIPT" "${args[@]+"${args[@]}"}"
        _exec '' 60 "${envs[@]+"${envs[@]}"}" -- "$(command -v script)" -qec "$cmd" /dev/null
        OUT="${OUT//$'\r'/}"
    }
    sel() {  # sel LABEL EXPECTED REQUEST [VAR=val ...]: "engine haswindows" on a terminal
        local label="$1" expected="$2" request="$3"; shift 3
        pty "UI_REQUEST='$request'; select_interface; printf '<<%s %s>>' \"\$UI_ENGINE\" \"\$HAVE_WHIPTAIL\"" "$@"
        value_of "$label" "$expected"
    }
    sel 'terminal and a display: the terminal wins'              'tui 1' ''         DISPLAY=:99
    sel 'terminal, no display: the terminal'                     'tui 1' ''
    sel 'terminal, --gui: windows'                               'gui 1' gui        DISPLAY=:99
    sel 'terminal, --gui without a display: not the windows'     'tui 1' gui
    sel 'terminal, MINTAPP_UI=gui and --terminal: the terminal'  'tui 1' terminal    DISPLAY=:99 MINTAPP_UI=gui
    sel 'terminal, MINTAPP_UI=gui alone: windows (as before)'    'gui 1' ''         DISPLAY=:99 MINTAPP_UI=gui
    sel 'terminal, MINTAPP_UI=text and --gui: windows'           'gui 1' gui        DISPLAY=:99 MINTAPP_UI=text
    fake_zenity OK OUT:0
    pty_run "${NOWIN[@]}" -- --gui
    check_eq '--gui on a terminal: windows, status 0' 0 "$RC"
    check_eq '--gui on a terminal: help window and menu' 2 "$(zenity_calls)"
else
    skip_case 'the terminal rules: needs "script" (util-linux)'
fi

echo "-- A start that fails in windows: the error is also shown in a window"
errwin() {  # errwin LABEL TEXT [OK_LABEL]: the last window is an error window with that text
    local label="$1" text="$2" ok="${3:-OK}"
    has "$label: it is an error window" --error
    has "$label: no markup" --no-markup
    has "$label: title" '--title=MintApp Remover'
    has "$label: OK button" "--ok-label=$ok"
    assert_contains "$label: the text" "$(zj)" "~--text=$text"
}
if [ "$(id -u)" -eq 0 ]; then
    fake_zenity OK
    H_AS_ROOT=1 _exec '' 60 "${NOWIN[@]}" -- "$H_BASH" "$H_SCRIPT"
    check_eq 'root: status 1' 1 "$RC"
    check_eq 'root: one window' 1 "$(zenity_calls)"
    errwin 'root' 'Do not run MintApp Remover as root or with sudo.|The script will ask for the administrator password'
    assert_contains 'root: the message is on stderr as well' "$OUT" 'Do not run MintApp Remover as root or with sudo.'
    fake_zenity OK
    H_AS_ROOT=1 _exec '' 60 DISPLAY=:99 MINTAPP_LANG=es MINTAPP_ASCII=0 -- "$H_BASH" "$H_SCRIPT"
    errwin 'root, Spanish' 'No ejecutes MintApp Remover como root ni con sudo.|El propio script' Aceptar
    fake_zenity OK
    H_AS_ROOT=1 _exec '' 60 "${NOWIN[@]}" MINTAPP_UI=text -- "$H_BASH" "$H_SCRIPT"
    check_eq 'root with MINTAPP_UI=text: no window' 0 "$(zenity_calls)"
else
    skip_case 'root: the error window (the suite is not root)'
fi
mkdir -p "$SB/nodpkg" "$SB/noapt" "$SB/nopriv"
for d in nodpkg noapt nopriv; do cp "$SB/bin/zenity" "$SB/$d/zenity"; done
printf '#!/bin/sh\nexit 0\n' > "$SB/noapt/dpkg"; cp "$SB/noapt/dpkg" "$SB/nopriv/dpkg"; cp "$SB/noapt/dpkg" "$SB/nopriv/apt-get"
chmod +x "$SB"/nodpkg/* "$SB"/noapt/* "$SB"/nopriv/*; sandbox_chown
fake_zenity OK
app_run '' "${NOWIN[@]}" PATH="$SB/nodpkg"
check_eq 'no dpkg: status 1' 1 "$RC"
errwin 'no dpkg' 'MintApp Remover requires dpkg and is intended for Debian/Ubuntu-based distributions.'
fake_zenity OK
app_run '' "${NOWIN[@]}" PATH="$SB/noapt"
check_eq 'no apt-get: status 1' 1 "$RC"
errwin 'no apt-get' 'MintApp Remover requires apt.'
fake_zenity OK
app_run '' "${NOWIN[@]}" PATH="$SB/nopriv"
check_eq 'neither sudo nor doas: status 1' 1 "$RC"
errwin 'neither sudo nor doas' 'MintApp Remover requires sudo or doas for package-management operations.'
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_SUDO=nosuch-command
check_eq 'an invalid MINTAPP_SUDO: status 1' 1 "$RC"
errwin 'an invalid MINTAPP_SUDO' 'MINTAPP_SUDO=nosuch-command is not a valid executable command.'
check_eq 'an invalid MINTAPP_SUDO: one window' 1 "$(zenity_calls)"
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_SUDO=nosuch-command MINTAPP_UI=text
check_eq 'an invalid MINTAPP_SUDO with MINTAPP_UI=text: no window' 0 "$(zenity_calls)"
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_SUDO=nosuch-command -- --terminal
check_eq 'an invalid MINTAPP_SUDO with --terminal: no window' 0 "$(zenity_calls)"
fake_zenity BROKEN
app_run '' "${NOWIN[@]}" MINTAPP_SUDO=nosuch-command
check_eq 'a zenity that fails does not hide the error: status 1' 1 "$RC"
assert_contains 'a zenity that fails does not hide the error: stderr' "$OUT" 'is not a valid executable command.'

# The errors about the package manager (4.6, step 4e) go through the same path: without a terminal
# nothing would show them if they only went to stderr. nopm and nodnf hold zenity (nodnf also rpm).
mkdir -p "$SB/nopm" "$SB/nodnf"
cp "$SB/bin/zenity" "$SB/nopm/zenity"; cp "$SB/bin/zenity" "$SB/nodnf/zenity"
printf '#!/bin/sh\nexit 0\n' > "$SB/nodnf/rpm"
chmod +x "$SB"/nopm/* "$SB"/nodnf/*; sandbox_chown
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_PM=xbps
check_eq 'an invalid MINTAPP_PM: status 1' 1 "$RC"
errwin 'an invalid MINTAPP_PM' 'MINTAPP_PM=xbps is not a valid package manager (supported: apt, dnf, pacman, zypper).'
check_eq 'an invalid MINTAPP_PM: one window' 1 "$(zenity_calls)"
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_PM=xbps MINTAPP_LANG=es
errwin 'an invalid MINTAPP_PM, Spanish' 'MINTAPP_PM=xbps no es un gestor de paquetes válido (admitidos: apt, dnf, pacman, zypper).' Aceptar
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_PM=xbps MINTAPP_UI=text
check_eq 'an invalid MINTAPP_PM with MINTAPP_UI=text: no window' 0 "$(zenity_calls)"
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/nopm"
check_eq 'no package manager found: status 1' 1 "$RC"
errwin 'no package manager found' 'MintApp Remover did not find a package manager it supports (supported: apt, dnf, pacman, zypper).'
check_eq 'no package manager found: one window' 1 "$(zenity_calls)"
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_PM=dnf PATH="$SB/nodnf"
check_eq 'dnf missing: status 1' 1 "$RC"
errwin 'dnf missing' 'MintApp Remover requires dnf and rpm.'
printf '#!/bin/sh\nprintf "dnf5 version 5.2.6.2\\nlibdnf5 version 5.2.6.2\\n"\n' > "$SB/bin/dnf"
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/rpm"
chmod +x "$SB/bin/dnf" "$SB/bin/rpm"; sandbox_chown
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_PM=dnf
check_eq 'dnf 5: status 1' 1 "$RC"
errwin 'dnf 5' 'MintApp Remover requires dnf 4, and "dnf --version" says: "dnf5 version 5.2.6.2". dnf 5 (Fedora 41 and later) is not supported yet.'
check_eq 'dnf 5: one window' 1 "$(zenity_calls)"
fake_zenity OK
app_run '' "${NOWIN[@]}" MINTAPP_PM=dnf MINTAPP_UI=text
check_eq 'dnf 5 with MINTAPP_UI=text: no window' 0 "$(zenity_calls)"
assert_contains 'dnf 5 with MINTAPP_UI=text: the message is on stderr' "$OUT" 'dnf 5 (Fedora 41 and later) is not supported yet.'
rm -f "$SB/bin/dnf" "$SB/bin/rpm"

echo "-- Another instance is running"
hold_lock() {
    mkdir -p "$SB/run"; chmod 700 "$SB/run"; : > "$SB/run/mintapp-remover.lock"; sandbox_chown
    # The subshell becomes the sleep (exec), so killing LOCK_HOLDER ends the one process that has the lock.
    ( exec {fd}>>"$SB/run/mintapp-remover.lock"; flock -n "$fd"; exec sleep 120 ) &
    LOCK_HOLDER=$!
    sleep 0.3
}
release_lock() { kill "$LOCK_HOLDER" 2>/dev/null || true; wait "$LOCK_HOLDER" 2>/dev/null || true; }
hold_lock
fake_zenity OK
app_run '' "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run"
check_eq 'second instance: status 1' 1 "$RC"
check_eq 'second instance: one window' 1 "$(zenity_calls)"
errwin 'second instance' 'Another instance of MintApp Remover is already running.'
assert_contains 'second instance: stderr as well' "$OUT" 'Another instance of MintApp Remover is already running.'
fake_zenity OK
app_run '' DISPLAY=:99 MINTAPP_LANG=es MINTAPP_ASCII=0 XDG_RUNTIME_DIR="$SB/run"
errwin 'second instance, Spanish' 'Ya hay otra instancia de MintApp Remover en ejecución.' Aceptar
fake_zenity OK
app_run '' "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run" MINTAPP_UI=text
check_eq 'second instance with MINTAPP_UI=text: no window' 0 "$(zenity_calls)"
fake_zenity OK
app_run '' "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run" -- --terminal
check_eq 'second instance with --terminal: no window' 0 "$(zenity_calls)"
if command -v script >/dev/null 2>&1; then
    fake_zenity OK
    pty_run "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run"
    check_eq 'second instance on a terminal: status 1' 1 "$RC"
    check_eq 'second instance on a terminal: the message is for the terminal, no window' 0 "$(zenity_calls)"
    assert_contains 'second instance on a terminal: the message' "$OUT" 'Another instance of MintApp Remover is already running.'
fi
release_lock
fake_zenity OK OUT:0
app_run '' "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run"
check_eq 'the lock is free again: the program starts' 0 "$RC"

echo "-- --after PID (internal): the copy that follows waits for the one before"
new_sandbox
rm -f "$SB/bin/sleep"      # the stub of the harness does not wait: these cases need the real sleep
sandbox_chown
fake_zenity OK
app_run '' "${NOWIN[@]}" -- --after
check_eq '--after without a value: status 2' 2 "$RC"
assert_contains '--after without a value: it is named' "$OUT" 'Unrecognized option: --after'
app_run '' "${NOWIN[@]}" -- --after abc
check_eq '--after with a word: status 2' 2 "$RC"
assert_contains '--after with a word: option and value are named' "$OUT" 'Unrecognized option: --after abc'
for v in 0 07 -5 12345678 '1 2'; do
    app_run '' "${NOWIN[@]}" -- --after "$v"
    check_eq "--after '$v' is not a process number: status 2" 2 "$RC"
done
app_run '' "${NOWIN[@]}" -- --after $'\e[31m'
assert_not_contains 'the value of --after is shown without control characters' "$OUT" $'\e'
app_run '' "${NOWIN[@]}" -- install --after 1
check_eq 'install takes no --after: status 2' 2 "$RC"
app_run '' "${NOWIN[@]}" -- --after 1 --help
check_eq '--after with --help: the help, status 0' 0 "$RC"
assert_contains '--after with --help: the help' "$OUT" 'Usage: MintApp_Remover.sh'
assert_not_contains 'the help does not list the internal --after' "$OUT" '--after'
check_eq '--after with --help: no window' 0 "$(zenity_calls)"

app_eval 'sleep 30 & p=$!; process_alive "$p"; a=$?; kill "$p"; wait "$p" 2>/dev/null; process_alive "$p"; b=$?; printf "<<%s %s>>" "$a" "$b"' "${NOWIN[@]}"
value_of 'process_alive: a live process yes, one that was killed and collected no' '0 1'
app_eval 'bash -c "sleep 0.1 & echo \$! > \"$HOME/zpid\"; exec sleep 3" & holder=$!
    sleep 0.6; z="$(cat "$HOME/zpid")"
    kill -0 "$z" 2>/dev/null; exists=$?
    grep -q "^State:[[:space:]]*Z" "/proc/$z/status"; zombie=$?
    process_alive "$z"; alive=$?
    kill "$holder"; wait "$holder" 2>/dev/null
    printf "<<%s %s %s>>" "$exists" "$zombie" "$alive"' "${NOWIN[@]}"
value_of 'process_alive: a zombie still answers kill -0, yet it counts as gone' '0 0 1'
app_eval 'true & p=$!; wait "$p"; wait_for_exit "$p" 5; echo "<<$?>>"' "${NOWIN[@]}"
value_of 'wait_for_exit: a process that is already gone: 0' 0
app_eval 's=$(date +%s%N); sleep 30 & p=$!; wait_for_exit "$p" 3; r=$?; e=$(date +%s%N); kill "$p"; wait "$p" 2>/dev/null
    printf "<<%s %s>>" "$r" "$(( (e - s) / 1000000 >= 250 ))"' "${NOWIN[@]}"
value_of 'wait_for_exit: a process that stays: 1, after the time given' '1 1'
app_eval 'sleep 0.4 & p=$!; wait_for_exit "$p" 30; echo "<<$?>>"' "${NOWIN[@]}"
value_of 'wait_for_exit: a process that ends meanwhile: 0' 0

# The relay case: the lock is held by the copy that started this one, which ends a moment later.
hold_lock
( sleep 1.5; kill "$LOCK_HOLDER" 2>/dev/null ) & ENDER=$!
app_run $'0\n' "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run" -- --terminal
check_eq 'control: without --after the second copy is refused: status 1' 1 "$RC"
t0=$(date +%s%N)
app_run $'0\n' "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run" -- --terminal --after "$LOCK_HOLDER"
t1=$(date +%s%N)
check_eq '--after a copy that holds the lock: it waits, then takes it: status 0' 0 "$RC"
assert_not_contains '--after: no "another instance" error' "$OUT" 'Another instance'
check_eq '--after: it really waited for the other copy to end' 1 "$(( (t1 - t0) / 1000000 >= 800 ))"
wait "$ENDER" 2>/dev/null || true
release_lock
t0=$(date +%s%N)
app_run $'0\n' "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run" -- --terminal --after "$LOCK_HOLDER"
t1=$(date +%s%N)
check_eq '--after a process that is gone: status 0' 0 "$RC"
check_eq '--after a process that is gone: no waiting' 1 "$(( (t1 - t0) / 1000000 < 5000 ))"
hold_lock
fake_zenity OK
t0=$(date +%s%N)
app_run '' "${NOWIN[@]}" XDG_RUNTIME_DIR="$SB/run" -- --after "$LOCK_HOLDER"
t1=$(date +%s%N)
check_eq '--after a copy that does not end: it gives up after ten seconds' 1 "$(( (t1 - t0) / 1000000 >= 9500 ))"
check_eq '--after a copy that does not end: then the lock says so: status 1' 1 "$RC"
assert_contains '--after a copy that does not end: the same error as any second copy' "$OUT" 'Another instance of MintApp Remover is already running.'
release_lock

echo "-- Terminal emulators: the table and MINTAPP_TERMINAL (terminal_find)"
new_sandbox
TERM_DIR="$SB/term"      # the only folder in the PATH of these cases: no real emulator gets in
# The table as the program must have it, in order of preference. It is written out again on purpose:
# a wrong word or a swapped order has to fail here.
EMULATORS=(
    "x-terminal-emulator|-e" "gnome-terminal|--" "konsole|-e" "xfce4-terminal|-x" "mate-terminal|-x"
    "lxterminal|-e" "qterminal|-e" "terminator|-x" "alacritty|-e" "kitty|" "xterm|-e"
)
# mkterm NAME...: executable emulators (they do nothing) in TERM_DIR.
mkterm() {
    local n
    mkdir -p "$TERM_DIR"
    for n in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$TERM_DIR/$n"; chmod 755 "$TERM_DIR/$n"; done
    sandbox_chown
}
# tf [VAR=val ...]: terminal_find with TERM_DIR as the PATH; OUT has <<status|path|words>>.
tf() {
    app_eval 'terminal_find; printf "<<%s|%s|%s>>" "$?" "$TERMINAL_BIN" "$TERMINAL_WORDS"' "${NOWIN[@]}" PATH="$TERM_DIR" "$@"
}
# forced LABEL VALUE PATH WORDS: MINTAPP_TERMINAL=VALUE finds that emulator, with those words.
forced() { tf MINTAPP_TERMINAL="$2"; value_of "MINTAPP_TERMINAL $1" "0|$3|$4"; }
# refused LABEL VALUE: it cannot be run: status 2, nothing chosen, and no fallback although others are installed.
refused() { tf MINTAPP_TERMINAL="$2"; value_of "MINTAPP_TERMINAL $1: status 2, nothing chosen" '2||'; }

mkdir -p "$TERM_DIR"; sandbox_chown
tf
value_of 'no emulator installed: status 1, nothing chosen' '1||'
names=()
for e in "${EMULATORS[@]}"; do names+=("${e%%|*}"); done
mkterm "${names[@]}"
for e in "${EMULATORS[@]}"; do
    tf
    value_of "the first one installed is chosen: ${e%%|*}, words '${e#*|}'" "0|$TERM_DIR/${e%%|*}|${e#*|}"
    rm -f "$TERM_DIR/${e%%|*}"
done
tf
value_of 'all of them gone: status 1 again' '1||'
mkterm xterm
printf '#!/bin/sh\nexit 0\n' > "$TERM_DIR/x-terminal-emulator"; chmod 644 "$TERM_DIR/x-terminal-emulator"; sandbox_chown
tf
value_of 'a file without permission to run is skipped: the next one is chosen' "0|$TERM_DIR/xterm|-e"
rm -f "$TERM_DIR/x-terminal-emulator"

mkterm x-terminal-emulator konsole gnome-terminal xfce4-terminal kitty mything
forced 'konsole (-e) wins over x-terminal-emulator, the first of the table' konsole "$TERM_DIR/konsole" -e
forced 'gnome-terminal: --' gnome-terminal "$TERM_DIR/gnome-terminal" --
forced 'xfce4-terminal: -x' xfce4-terminal "$TERM_DIR/xfce4-terminal" -x
forced 'kitty: no words' kitty "$TERM_DIR/kitty" ''
forced 'one the table does not list: -e' mything "$TERM_DIR/mything" -e
forced 'a path: the words are those of the file name (gnome-terminal)' "$TERM_DIR/gnome-terminal" "$TERM_DIR/gnome-terminal" --
forced 'a path to one the table does not list: -e' "$TERM_DIR/mything" "$TERM_DIR/mything" -e
tf MINTAPP_TERMINAL=
value_of 'MINTAPP_TERMINAL empty: as if it were not set, the table decides' "0|$TERM_DIR/x-terminal-emulator|-e"

printf '#!/bin/sh\nexit 0\n' > "$TERM_DIR/noexec"; chmod 644 "$TERM_DIR/noexec"
mkdir -p "$TERM_DIR/adir"; sandbox_chown
refused 'that does not exist' nonexistent
refused 'with no permission to run (a name)' noexec
refused 'with no permission to run (a path)' "$TERM_DIR/noexec"
refused 'that is a folder (a name)' adir
refused 'that is a folder (a path)' "$TERM_DIR/adir"
refused 'with a path that does not exist' "$TERM_DIR/none/xterm"
# Names that exist but are not plain: the check of the characters refuses them, not the search.
# The tilde is literal on purpose: the shell does not expand it inside quotes.
# shellcheck disable=SC2088
bad=('a b' 'x;y' '$(id)' '-e' 'kon*' $'x\ny' '~/xterm')
for v in "${bad[@]}"; do [[ "$v" == */* ]] || mkterm "$v"; done
for v in "${bad[@]}"; do refused "with strange characters (${v//$'\n'/\\n})" "$v"; done
app_eval 'terminal_find; MINTAPP_TERMINAL=nonexistent terminal_find; printf "<<%s|%s|%s>>" "$?" "$TERMINAL_BIN" "$TERMINAL_WORDS"' "${NOWIN[@]}" PATH="$TERM_DIR"
value_of 'a search that fails does not keep what the one before found' '2||'
rm -rf "$TERM_DIR"

echo "-- terminal_relay: the program opens in a terminal emulator"
fresh
rm -f "$SB/bin/sleep"      # the relay waits for real: the no-op sleep of the harness would cut the wait short
TERM_DIR="$SB/term"
# program_mode MODE: from now on these cases run a copy of the program with that file mode and assets/
# linked beside it, as in the repository. The relay starts the new copy through its file when the file
# can be run (755) and through bash when it cannot (644), so the mode of the file in the repository
# must not decide these cases. SELF: the file the emulator is given.
program_mode() {
    local dir="$H_TMP/relay-app"
    mkdir -p -- "$dir/script"
    [ -e "$dir/assets" ] || ln -s -- "$H_REPO_DIR/assets" "$dir/assets"
    cp -f -- "$REAL_SCRIPT" "$dir/script/MintApp_Remover.sh"
    chmod "$1" "$dir/script/MintApp_Remover.sh"
    H_SCRIPT="$dir/script/MintApp_Remover.sh"
    SELF="$(readlink -f "$H_SCRIPT")"
}
program_mode 755
EMU_ENTRY='myemu|-e'
# EMU_RUNS: the end of an emulator that runs what it is given and records how it ended, as a real one does.
# The program does not have to be run through bash for the new copy to start: only through the file.
EMU_RUNS='shift; "$@" > "$S/copy.out" 2>&1 < /dev/null; echo $? > "$S/copy.rc"'
# mkemu NAME [END]: a stub emulator in TERM_DIR. It records in $SB/state its arguments (term.args), who it is
# (term.who), where its three standard streams point (term.std), what it has open (term.fds) and its PID
# (term.pid); then it runs END, shell code ("exit 0" by default).
mkemu() {
    mkdir -p "$TERM_DIR"
    {
        printf '#!/bin/sh\nS=%q\n' "$SB/state"
        printf '%s\n' \
            'echo "$0" > "$S/term.who"; echo $$ > "$S/term.pid"' \
            '{ for a in "$@"; do printf "%s\n" "$a"; done; echo @@END@@; } >> "$S/term.args"' \
            'std=$(for i in 0 1 2; do readlink "/proc/$$/fd/$i"; done); printf "%s\n" "$std" > "$S/term.std"' \
            'ls -l "/proc/$$/fd" > "$S/term.fds" 2>&1' \
            "${2:-exit 0}"
    } > "$TERM_DIR/$1"
    chmod 755 "$TERM_DIR/$1"; sandbox_chown
}
# relay CODE [VAR=val ...]: CODE in the windows engine, with TERM_DIR first in the PATH and a table that holds
# only EMU_ENTRY, so that no real emulator gets in.
relay() {
    local code="$1"; shift
    rm -f "$SB"/state/term.*
    ge "TERMINAL_TABLE=('$EMU_ENTRY'); $code" PATH="$TERM_DIR:$SB/bin:$H_SYS_PATH" "$@"
}
# fields: the <<a|b|c>> of OUT in R.
fields() { local v="${OUT#*<<}"; IFS='|' read -r -a R <<< "${v%%>>*}"; }
# term_args: the arguments of the emulator in one line, joined with |.
term_args() { awk '/^@@END@@$/ { exit } { printf "%s%s", (n++ ? "|" : ""), $0 }' "$SB/state/term.args" 2>/dev/null || true; }
# term_files: how many files the stub emulators left (0 = none was started).
term_files() { find "$SB/state" -maxdepth 1 -name 'term.*' | wc -l; }
# stop_emu: ends the emulator of the case if it stays open.
stop_emu() { kill "$(cat "$SB/state/term.pid" 2>/dev/null)" 2>/dev/null || true; }

mkemu myemu
fake_zenity OK
relay 'terminal_relay; r=$?; printf "<<%s|%s|%s>>" "$r" "$$" "$(config_get interface || echo none)"'
fields
check_eq 'an emulator is found and started: status 0' 0 "${R[0]}"
check_eq 'it runs this program with --terminal, to start after this copy has ended' "-e|$SELF|--terminal|--after|${R[1]}" "$(term_args)"
check_eq 'nothing went wrong: no window' 0 "$(zenity_calls)"
check_eq 'the emulator has no input and no output: its three streams are /dev/null' $'/dev/null\n/dev/null\n/dev/null' "$(cat "$SB/state/term.std")"
check_eq 'terminal_relay does not save the choice: the caller does' none "${R[2]}"
for w in -- -x ''; do
    EMU_ENTRY="myemu|$w"
    relay 'terminal_relay; printf "<<%s|%s>>" "$?" "$$"'
    fields
    check_eq "the words of the table go before the program (${w:-none}): status 0" 0 "${R[0]}"
    check_eq "the words of the table go before the program (${w:-none}): arguments" "${w:+$w|}$SELF|--terminal|--after|${R[1]}" "$(term_args)"
done
EMU_ENTRY='myemu|-e'

# A file without permission to run (a launcher with "Exec=bash file", or a copy that kept mode 644): an
# emulator that is given the file itself cannot run it and stays open with its error, while this copy ends.
program_mode 644
mkemu myemu
fake_zenity OK
relay 'terminal_relay; printf "<<%s|%s>>" "$?" "$$"'
fields
check_eq 'a file that cannot be run: status 0' 0 "${R[0]}"
check_eq 'a file that cannot be run: the emulator is given bash, then the file' "-e|$H_BASH|$SELF|--terminal|--after|${R[1]}" "$(term_args)"
check_eq 'a file that cannot be run: no window' 0 "$(zenity_calls)"
for w in -- ''; do
    EMU_ENTRY="myemu|$w"
    relay 'terminal_relay; printf "<<%s|%s>>" "$?" "$$"'
    fields
    check_eq "a file that cannot be run: the words of the table (${w:-none}) go before bash" "${w:+$w|}$H_BASH|$SELF|--terminal|--after|${R[1]}" "$(term_args)"
done
EMU_ENTRY='myemu|-e'
relay 'terminal_relay --show-help; printf "<<%s|%s>>" "$?" "$$"'
fields
check_eq 'a file that cannot be run: the arguments go on after --after' "-e|$H_BASH|$SELF|--terminal|--after|${R[1]}|--show-help" "$(term_args)"
relay 'unset BASH; terminal_relay; printf "<<%s|%s>>" "$?" "$$"'
fields
check_eq 'a file that cannot be run, BASH unset: bash is looked up in the PATH' "-e|bash|$SELF|--terminal|--after|${R[1]}" "$(term_args)"
program_mode 755
relay 'terminal_relay; printf "<<%s|%s>>" "$?" "$$"'
fields
check_eq 'control: a file that can be run is given as it is, without bash' "-e|$SELF|--terminal|--after|${R[1]}" "$(term_args)"

mkdir -p "$SB/run"; sandbox_chown
mkemu myemu 'exec sleep 30'
relay 'acquire_lock; terminal_relay; printf "<<%s|%s>>" "$?" "$LOCK_FD"' XDG_RUNTIME_DIR="$SB/run"
fields
check_eq 'with the lock taken and an emulator that stays open: status 0' 0 "${R[0]}"
[ -n "${R[1]}" ] && lock_taken=yes || lock_taken=no
check_eq 'control: the lock was taken (it has a descriptor)' yes "$lock_taken"
check_eq 'the emulator does not inherit the lock' 0 "$(grep -c 'mintapp-remover.lock' "$SB/state/term.fds" || true)"
check_eq 'this copy has ended, the emulator has not: the lock is free for the new copy' 0 "$(flock -n "$SB/run/mintapp-remover.lock" true; echo $?)"
stop_emu
hold_lock
check_eq 'control: while a copy holds the lock, it is not free' 1 "$(flock -n "$SB/run/mintapp-remover.lock" true; echo $?)"
release_lock

mkemu myemu 'exec sleep 30'
relay 's=$(date +%s%N); terminal_relay; r=$?; e=$(date +%s%N); printf "<<%s|%s>>" "$r" "$(( (e - s) / 1000000 ))"'
fields
stop_emu
check_eq 'an emulator that stays open counts as opened: status 0' 0 "${R[0]}"
check_eq 'it waited half a second to see it stay open (not less, not much more)' 1 "$(( R[1] >= 450 && R[1] < 2500 ))"

echo "-- terminal_relay: when no terminal opens"
mkemu myemu 'exit 3'
fake_zenity OK
relay 's=$(date +%s%N); terminal_relay; r=$?; e=$(date +%s%N); printf "<<%s|%s>>" "$r" "$(( (e - s) / 1000000 ))"'
fields
check_eq 'an emulator that ends with an error at once: status 1' 1 "${R[0]}"
check_eq 'it does not wait the whole half second for one that is already gone' 1 "$(( R[1] < 450 ))"
check_eq 'it opens one error window' 1 "$(zenity_calls)"
errwin 'emulator that fails' 'The terminal could not be opened. You can keep working in the windows.'
assert_contains 'the same text goes to stderr' "$OUT" 'The terminal could not be opened.'
mkemu myemu 'exit 0'
fake_zenity OK
relay 'terminal_relay; printf "<<%s>>" "$?"'
value_of 'an emulator that ends with 0 at once (it handed the window to a server): it opened' 0
check_eq 'and no window' 0 "$(zenity_calls)"

fake_zenity OK
relay 'TERMINAL_TABLE=(); terminal_relay; printf "<<%s>>" "$?"'
value_of 'no emulator installed: status 1' 1
errwin 'no emulator' 'No terminal emulator was found. Install one or name yours with MINTAPP_TERMINAL.'
check_eq 'no emulator: nothing was started' 0 "$(term_files)"
fake_zenity OK
relay 'TERMINAL_TABLE=(); terminal_relay; printf "<<%s>>" "$?"' MINTAPP_LANG=es
errwin 'no emulator, Spanish' 'No se encontró ningún emulador de terminal. Instala uno o indica el tuyo con MINTAPP_TERMINAL.' Aceptar

mkemu myemu
fake_zenity OK
relay 'terminal_relay; printf "<<%s>>" "$?"' MINTAPP_TERMINAL=nonexistent
value_of 'MINTAPP_TERMINAL that cannot be run: status 1' 1
errwin 'forced emulator that cannot be run' 'MINTAPP_TERMINAL=nonexistent is not an executable terminal emulator.'
check_eq 'it does not fall back to the table: no emulator started although one is installed' 0 "$(term_files)"
fake_zenity OK
relay 'terminal_relay; printf "<<%s>>" "$?"' MINTAPP_TERMINAL="$(printf 'x%.0s' {1..100})"
assert_contains 'a very long value is cut in the message' "$(zj)" "~--text=MINTAPP_TERMINAL=$(printf 'x%.0s' {1..61})... is not"
fake_zenity OK
relay 'terminal_relay; printf "<<%s>>" "$?"' MINTAPP_TERMINAL=$'a\e[31mb'
assert_not_contains 'a value with control characters is shown without them' "$(zj)" $'\e'
assert_contains 'a value with control characters is shown without them: the rest of the text' "$(zj)" 'MINTAPP_TERMINAL=a[31mb is not an executable terminal emulator.'

mkemu other
fake_zenity OK
relay 'terminal_relay; printf "<<%s>>" "$?"' MINTAPP_TERMINAL="$TERM_DIR/other"
value_of 'MINTAPP_TERMINAL with a path: status 0' 0
check_eq 'it is the forced emulator that runs, not the table' "$TERM_DIR/other" "$(cat "$SB/state/term.who")"

mkemu myemu
fake_zenity OK
relay 'install_self() { return 1; }; terminal_relay; printf "<<%s>>" "$?"'
value_of 'without a file of the program to run (it was piped in): status 1' 1
errwin 'program without a file' 'The terminal could not be opened. You can keep working in the windows.'
check_eq 'program without a file: no emulator started' 0 "$(term_files)"

echo "-- T from the launcher: offered when an emulator can be opened, and it opens it"
CFG="$SB/home/.config/mintapp-remover/config"
# saved: yes when the configuration of the last run says "interface=terminal".
saved() { if [ -f "$CFG" ] && grep -qx 'interface=terminal' "$CFG"; then echo yes; else echo no; fi; }
mkemu myemu
fake_zenity OK
relay 'build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"'
value_of 'windows without a terminal and an emulator that can be opened: T between 4 and L' '1 2 3 4 T L 0'
relay 'TERMINAL_TABLE=(); build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"'
value_of 'windows without a terminal and no emulator installed: no T' '1 2 3 4 L 0'
relay 'build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"' MINTAPP_TERMINAL=nonexistent
value_of 'a forced emulator that cannot be run: no T' '1 2 3 4 L 0'
relay 'build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"' MINTAPP_TERMINAL="$TERM_DIR/myemu"
value_of 'a forced emulator that can be run: T' '1 2 3 4 T L 0'
relay 'TERMINAL_TABLE=(); UI_ENGINE=tui; build_main_menu; printf "<<%s>>" "${MENU_TAGS[*]}"'
value_of 'outside the windows there is no T, whatever is installed: G' '1 2 3 4 G L 0'

mkemu myemu
fake_zenity OK
relay 'printf "<<%s>>" "$$"; switch_to_terminal; printf "NOT REACHED"'
fields
check_eq 'T without a terminal: this copy ends, status 0' 0 "$RC"
assert_not_contains 'T without a terminal: nothing runs after it' "$OUT" 'NOT REACHED'
check_eq 'T without a terminal: the new copy starts after this one' "-e|$SELF|--terminal|--after|${R[0]}" "$(term_args)"
check_eq 'T without a terminal: the choice is remembered' yes "$(saved)"
check_eq 'T without a terminal: no window' 0 "$(zenity_calls)"

mkemu myemu 'exit 3'
fake_zenity OK
relay 'switch_to_terminal; printf "<<%s|%s>>" "$?" "$UI_ENGINE"'
value_of 'T when the emulator does not open: status 1, the windows stay' '1|gui'
errwin 'T that fails' 'The terminal could not be opened. You can keep working in the windows.'
check_eq 'T that fails: the choice is not remembered' no "$(saved)"
fake_zenity OK
relay 'TERMINAL_TABLE=(); switch_to_terminal; printf "<<%s|%s>>" "$?" "$UI_ENGINE"'
value_of 'T with no emulator: status 1, the windows stay' '1|gui'
errwin 'T with no emulator' 'No terminal emulator was found. Install one or name yours with MINTAPP_TERMINAL.'
check_eq 'T with no emulator: the choice is not remembered' no "$(saved)"

echo "-- T from the launcher, end to end: the new copy takes the lock when this one ends"
mkdir -p "$SB/run" "$SB/tmp"; sandbox_chown
mkemu myemu "$EMU_RUNS"
rm -f "$SB"/state/term.* "$SB"/state/copy.*
fake_zenity OK OUT:T
app_run '' "${GUI[@]}" TMPDIR="$SB/tmp" XDG_RUNTIME_DIR="$SB/run" MINTAPP_TERMINAL="$TERM_DIR/myemu"
check_eq 'T in the menu: the program ends, status 0' 0 "$RC"
check_eq 'T in the menu: the help window and the menu, nothing else' 2 "$(zenity_calls)"
check_eq 'T in the menu: the choice is remembered' yes "$(saved)"
for _ in $(seq 1 150); do [ -f "$SB/state/copy.rc" ] && break; sleep 0.1; done
check_eq 'the new copy ran and ended without error' 0 "$(cat "$SB/state/copy.rc" 2>/dev/null || echo missing)"
assert_not_contains 'the new copy did not find the lock taken' "$(cat "$SB/state/copy.out" 2>/dev/null)" 'Another instance'

echo "-- Start from the launcher with interface=terminal: the program opens in a terminal"
H_KEEP_CONFIG=1          # the harness would delete the configuration before every run
# cfg LINE...: the configuration file, one line each (what the T and G keys save).
cfg() {
    mkdir -p "$SB/home/.config/mintapp-remover"
    printf '%s\n' "$@" > "$CFG"
    chmod 700 "$SB/home/.config/mintapp-remover"; chmod 600 "$CFG"; sandbox_chown
}
# launch [VAR=val ...] [-- ARGS...]: the program as a launcher starts it (no terminal, a display, no MINTAPP_UI)
# with the stub emulator as the one to open. OUT and RC; the emulator leaves term.* and copy.* in $SB/state.
launch() {
    rm -f "$SB"/state/term.* "$SB"/state/copy.*
    app_run '' "${NOWIN[@]}" TMPDIR="$SB/tmp" XDG_RUNTIME_DIR="$SB/run" MINTAPP_TERMINAL="$TERM_DIR/myemu" "$@"
}
# started: yes when an emulator was started. norm: its arguments, with the number after --after as PID.
started() { if [ "$(term_files)" -gt 0 ]; then echo yes; else echo no; fi; }
norm() { term_args | sed -E 's/\|--after\|[1-9][0-9]*/|--after|PID/'; }
mkdir -p "$SB/run" "$SB/tmp"; sandbox_chown

echo "-- ... with the terminal saved and nothing else asked: it opens the emulator and ends"
mkemu myemu
cfg interface=terminal
fake_zenity OK OK OUT:0
launch
check_eq 'saved terminal, no terminal: this copy ends, status 0' 0 "$RC"
check_eq 'it prints nothing' '' "$OUT"
check_eq 'no window opens: neither the help nor the menu' 0 "$(zenity_calls)"
check_eq 'the emulator runs the program with --terminal, to start after this copy' "-e|$SELF|--terminal|--after|PID" "$(norm)"
check_eq 'the choice stays saved' yes "$(saved)"
launch -- --show-help
check_eq '--show-help is for the new copy: it goes on after --after' "-e|$SELF|--terminal|--after|PID|--show-help" "$(norm)"

mkemu myemu "$EMU_RUNS"
fake_zenity OK
launch
check_eq 'end to end: the first copy ends, status 0' 0 "$RC"
for _ in $(seq 1 150); do [ -f "$SB/state/copy.rc" ] && break; sleep 0.1; done
check_eq 'end to end: the new copy ran and ended without error' 0 "$(cat "$SB/state/copy.rc" 2>/dev/null || echo missing)"
assert_not_contains 'end to end: the new copy found the lock free' "$(cat "$SB/state/copy.out" 2>/dev/null)" 'Another instance'
check_eq 'end to end: the new copy has --terminal, so it does not relay again' 1 "$(grep -c '^@@END@@$' "$SB/state/term.args")"
check_eq 'end to end: no window in either copy' 0 "$(zenity_calls)"

echo "-- ... end to end with a program file that cannot be run: bash starts the new copy"
program_mode 644
mkemu myemu "$EMU_RUNS"
fake_zenity OK
launch
check_eq 'no permission to run: the first copy ends, status 0' 0 "$RC"
for _ in $(seq 1 150); do [ -f "$SB/state/copy.rc" ] && break; sleep 0.1; done
check_eq 'no permission to run: the emulator is given bash and the file' "-e|$H_BASH|$SELF|--terminal|--after|PID" "$(norm)"
check_eq 'no permission to run: the new copy ran and ended without error' 0 "$(cat "$SB/state/copy.rc" 2>/dev/null || echo missing)"
assert_not_contains 'no permission to run: the new copy found the lock free' "$(cat "$SB/state/copy.out" 2>/dev/null)" 'Another instance'
assert_not_contains 'no permission to run: the new copy did not stumble on its file' "$(cat "$SB/state/copy.out" 2>/dev/null)" 'Permission denied'
check_eq 'no permission to run: no window in either copy' 0 "$(zenity_calls)"
program_mode 755

mkemu myemu 'exec sleep 30'
fake_zenity OK
launch
check_eq 'an emulator that stays open: status 0' 0 "$RC"
check_eq 'the emulator does not inherit the lock' 0 "$(grep -c 'mintapp-remover.lock' "$SB/state/term.fds" || true)"
check_eq 'this copy has ended and the emulator is open: the lock is free for the new copy' 0 "$(flock -n "$SB/run/mintapp-remover.lock" true; echo $?)"
stop_emu

echo "-- ... a request of this run beats the saved choice: no emulator"
mkemu myemu
fake_zenity OK OUT:0
launch -- --gui
check_eq '--gui: the windows open (help and menu)' 2 "$(zenity_calls)"
check_eq '--gui: no emulator' no "$(started)"
fake_zenity OK
launch -- --terminal
check_eq '--terminal: no emulator (the copy that the relay starts has it)' no "$(started)"
check_eq '--terminal: no window' 0 "$(zenity_calls)"
for ui in gui tui whiptail text; do
    fake_zenity OK OUT:0
    fake_answers OK TAG:0
    launch MINTAPP_UI="$ui"
    check_eq "MINTAPP_UI=$ui names an interface: no emulator" no "$(started)"
done
for ui in auto nope; do
    fake_zenity OK
    launch MINTAPP_UI="$ui"
    check_eq "MINTAPP_UI=$ui counts as not set: the emulator opens" yes "$(started)"
done

echo "-- ... it needs a graphical session and no terminal"
fake_zenity OK
launch DISPLAY=
check_eq 'no graphical session: no emulator, there is nowhere to open it' no "$(started)"
launch DISPLAY= WAYLAND_DISPLAY=wayland-0
check_eq 'a Wayland session alone is enough' yes "$(started)"
if command -v script >/dev/null 2>&1; then
    app_eval 'terminal_start_wanted; printf "<<%s>>" "$?"' "${NOWIN[@]}"
    value_of 'control: without a terminal and with the choice saved, the relay is wanted' 0
    pty 'terminal_start_wanted; printf "<<%s>>" "$?"' "${NOWIN[@]}"
    value_of 'on a terminal the terminal rules: no relay, whatever was saved' 1
else
    skip_case 'start on a terminal: needs "script" (util-linux)'
fi

echo "-- ... without the terminal saved: the windows, as before"
for saved_as in none gui; do
    if [ "$saved_as" = none ]; then rm -f "$CFG"; else cfg interface=gui; fi
    fake_zenity OK OUT:0
    launch
    check_eq "interface $saved_as: the windows open (help and menu)" 2 "$(zenity_calls)"
    check_eq "interface $saved_as: no emulator" no "$(started)"
done

echo "-- ... when no emulator opens: the reason, and the windows go on"
cfg interface=terminal
mkemu myemu 'exit 3'
fake_zenity OK OK OUT:0
launch
check_eq 'an emulator that fails: error window, help and menu' 3 "$(zenity_calls)"
check_eq 'an emulator that fails: the program goes on, status 0' 0 "$RC"
has 'an emulator that fails: the first window is an error window' --error 1
assert_contains 'an emulator that fails: it says why' "$(zj 1)" '~--text=The terminal could not be opened. You can keep working in the windows.'
assert_contains 'an emulator that fails: the same text on stderr' "$OUT" 'The terminal could not be opened.'
check_eq 'an emulator that fails: the choice stays saved, the next start tries again' yes "$(saved)"
cfg interface=terminal
fake_zenity OK OK OUT:0
app_eval 'TERMINAL_TABLE=(); main' "${NOWIN[@]}" TMPDIR="$SB/tmp" XDG_RUNTIME_DIR="$SB/run"
check_eq 'no emulator installed: error window, help and menu' 3 "$(zenity_calls)"
assert_contains 'no emulator installed: it says why' "$(zj 1)" '~--text=No terminal emulator was found. Install one or name yours with MINTAPP_TERMINAL.'
check_eq 'no emulator installed: the choice stays saved' yes "$(saved)"
cfg interface=terminal
mkemu myemu
fake_zenity OK OK OUT:0
launch MINTAPP_TERMINAL=nonexistent
check_eq 'MINTAPP_TERMINAL that cannot be run: error window, help and menu' 3 "$(zenity_calls)"
assert_contains 'MINTAPP_TERMINAL that cannot be run: it says why' "$(zj 1)" '~--text=MINTAPP_TERMINAL=nonexistent is not an executable terminal emulator.'
check_eq 'MINTAPP_TERMINAL that cannot be run: it does not fall back to another emulator' no "$(started)"

echo "-- ... the relay comes after the start errors and after the lock"
cfg interface=terminal
fake_zenity OK
launch MINTAPP_PM=nope
check_eq 'a start error comes first: status 1' 1 "$RC"
check_eq 'a start error: no emulator' no "$(started)"
check_eq 'a start error: its own window and nothing else' 1 "$(zenity_calls)"
hold_lock
fake_zenity OK
launch
check_eq 'another instance holds the lock: status 1' 1 "$RC"
check_eq 'another instance holds the lock: no emulator, so a second click opens no second terminal' no "$(started)"
errwin 'second instance with the terminal saved' 'Another instance of MintApp Remover is already running.'
release_lock
H_KEEP_CONFIG=0
rm -f "$CFG"

real_app
echo "-- --help: MINTAPP_TERMINAL and the start from the launcher"
for lang in en es; do
    app_run '' MINTAPP_LANG=$lang -- --help
    assert_contains "--help ($lang) documents MINTAPP_TERMINAL" "$OUT" '  MINTAPP_TERMINAL='
    check_eq "--help ($lang): no line wider than 80 columns" 0 "$(printf '%s\n' "$OUT" | awk 'length($0) > 80' | wc -l)"
done
app_run '' MINTAPP_LANG=en -- --help
assert_contains '--help says that the choice of the terminal is respected from the launcher' "$OUT" 'if you last chose the terminal (key T in the windows),'

echo "-- Smoke test with the real zenity: what the keys really do"
missing=()
for tool in zenity Xvfb openbox xdotool; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
    skip_case "real zenity: needs ${missing[*]} (apt install zenity xvfb openbox xdotool)"
else
    X_PIDS=()
    X_NUM=""
    # x_stop: ends the X server and the window manager (and removes what they leave behind).
    x_stop() {
        local pid
        for pid in "${X_PIDS[@]+"${X_PIDS[@]}"}"; do kill "$pid" 2>/dev/null || true; done
        for pid in "${X_PIDS[@]+"${X_PIDS[@]}"}"; do wait "$pid" 2>/dev/null || true; done
        X_PIDS=()
        [ -z "$X_NUM" ] || rm -f -- "/tmp/.X11-unix/X$X_NUM" "/tmp/.X$X_NUM-lock"
    }
    trap 'x_stop; _harness_cleanup' EXIT

    # x_start: Xvfb on the first free display from :90, then openbox (without a window manager
    # the new window would not get the keyboard).
    x_start() {
        local n
        for n in $(seq 90 130); do
            [ ! -e "/tmp/.X11-unix/X$n" ] && [ ! -e "/tmp/.X$n-lock" ] || continue
            Xvfb ":$n" -ac -nolisten tcp -screen 0 1280x800x24 > "$H_TMP/xvfb.log" 2>&1 &
            X_PIDS+=("$!")
            X_NUM="$n"
            for _ in $(seq 1 50); do [ -e "/tmp/.X11-unix/X$n" ] && break; sleep 0.1; done
            [ -e "/tmp/.X11-unix/X$n" ] || return 1
            DISPLAY=":$n" openbox > "$H_TMP/openbox.log" 2>&1 &
            X_PIDS+=("$!")
            for _ in $(seq 1 50); do
                DISPLAY=":$n" xdotool getdisplaygeometry >/dev/null 2>&1 && break
                sleep 0.1
            done
            sleep 0.7
            return 0
        done
        return 1
    }

    # smoke_open CODE: CODE runs in the program with zenity, as the sandbox user, in the background;
    # this returns when its window is up. smoke_close waits for the program: OUT is "<<status>>[[answer]]"
    # of the dialog CODE calls. Only the process of the program is waited for (wait "$SMOKE_PID"), never
    # "wait" alone: that would wait for the X server and openbox too.
    smoke_open() {
        local out="$SB/state/smoke.out"
        local -a pre=()
        if [ "$(id -u)" -eq 0 ]; then pre=("$H_SETPRIV" --reuid="$H_APP_UID" --regid="$H_APP_GID" --clear-groups); fi
        : > "$out"; sandbox_chown
        "$H_ENV" -i "${BASE_ENV[@]}" "${GUI[@]}" DISPLAY=":$X_NUM" PATH="$H_SYS_PATH" "${pre[@]+"${pre[@]}"}" \
            "$H_TIMEOUT" 25 "$H_BASH" -c 'source "$1"; zenity_usable; ans="$(eval "$2" 3>&1 1>&2 2>&3)"; echo "<<$?>>[[$ans]]"' \
            bash "$H_SCRIPT" "$1" > "$out" 2>&1 &
        SMOKE_PID=$!
        # The window is there when the window manager lists it; the keyboard needs a moment more.
        for _ in $(seq 1 100); do
            [ -z "$(DISPLAY=":$X_NUM" xdotool search --onlyvisible --name 'MintApp Remover' 2>/dev/null)" ] || break
            sleep 0.1
        done
        sleep 0.8
    }
    smoke_close() {
        wait "$SMOKE_PID" || true
        OUT="$(tail -n1 "$SB/state/smoke.out")"
    }
    # smoke CODE KEY...: smoke_open, then the window gets the keys (xdotool names, or "type:text")
    # one by one, then smoke_close.
    smoke() {
        local code="$1" key
        shift
        smoke_open "$code"
        for key in "$@"; do
            case "$key" in
                type:*) DISPLAY=":$X_NUM" xdotool type --delay 40 "${key#type:}" ;;
                *) DISPLAY=":$X_NUM" xdotool key "$key" ;;
            esac
            sleep 0.25
        done
        smoke_close
    }
    # probe CODE: CODE opens a window; while it is open, PROBE is "<title>|<command line>" of the process
    # that owns the window of the class mintapp-remover (empty when there is none), GEOM is its size
    # ("WIDTHxHEIGHT") and STRAY is how many windows have the class zenity, the one it has by default.
    # Then Esc closes the window.
    probe() {
        local wid pid
        smoke_open "$1"
        PROBE="" GEOM=""
        # xdotool search ends with 1 when it finds nothing: that must not end the suite (pipefail).
        STRAY="$({ DISPLAY=":$X_NUM" xdotool search --onlyvisible --classname '^zenity$' 2>/dev/null || true; } | wc -l)"
        wid="$({ DISPLAY=":$X_NUM" xdotool search --onlyvisible --classname '^mintapp-remover$' 2>/dev/null || true; } | head -n1)"
        if [ -n "$wid" ]; then
            pid="$(DISPLAY=":$X_NUM" xdotool getwindowpid "$wid" 2>/dev/null || true)"
            PROBE="$(DISPLAY=":$X_NUM" xdotool getwindowname "$wid" 2>/dev/null)|$(tr '\0' ' ' < "/proc/${pid:-0}/cmdline" 2>/dev/null || true)"
            GEOM="$(DISPLAY=":$X_NUM" xdotool getwindowgeometry "$wid" 2>/dev/null | awk '/Geometry/{print $2}')"
        fi
        DISPLAY=":$X_NUM" xdotool key Escape
        smoke_close
    }
    # classed LABEL CODE KIND: the window of CODE has the class and the argv[0] mintapp-remover (WM_CLASS
    # and the first word of its command line), the title of the program, is of KIND, and no window of the
    # program has the class zenity.
    classed() {
        probe "$2"
        assert_contains "$1: class and argv[0] are mintapp-remover, the title is the program's" "$PROBE" 'MintApp Remover|mintapp-remover '
        assert_contains "$1: it is a $3 window" "$PROBE" " --$3 "
        check_eq "$1: no window has the default class zenity" 0 "$STRAY"
    }
    # keys LABEL EXPECTED CODE KEY...: one case.
    keys() {
        local label="$1" expected="$2" code="$3"
        shift 3
        smoke "$code" "$@"
        check_eq "$label" "$expected" "$OUT"
    }

    if ! x_start; then
        skip_case 'real zenity: the X server did not start (see Xvfb)'
    else
        echo "   (zenity $(zenity --version 2>/dev/null || echo '?'))"
        LONG='wt_yesno "$(seq -f "line %g" 1 30)"'
        # A long question that is destructive: the safe button must be the one Enter presses.
        D="$LONG Uninstall Cancel big defaultno"
        keys 'long yes/no, defaultno: Enter is Cancel, so no'              '<<1>>[[]]' "$D" Return
        keys 'long yes/no, defaultno: Tab and Enter is Close, so no'       '<<1>>[[]]' "$D" Tab Return
        keys 'long yes/no, defaultno: three Tabs and Enter is Uninstall'   '<<0>>[[]]' "$D" Tab Tab Tab Return
        keys 'long yes/no, defaultno: Esc is no'                           '<<1>>[[]]' "$D" Escape
        N="$LONG Yes No"
        keys 'long yes/no: Enter is the yes button'                        '<<0>>[[]]' "$N" Return
        keys 'long yes/no: Esc is no'                                      '<<1>>[[]]' "$N" Escape
        C="$LONG Alpha Beta big \"\" choice"
        keys 'long choice: Enter is the first action'                      '<<0>>[[]]' "$C" Return
        keys 'long choice: Esc is the first action, never the second'      '<<0>>[[]]' "$C" Escape
        keys 'long choice: Tab and Enter is Close, which is the first action' '<<0>>[[]]' "$C" Tab Return
        keys 'long choice: three Tabs and Enter is the second action'      '<<1>>[[]]' "$C" Tab Tab Tab Return

        S='wt_yesno "Short question" Yes No normal'
        keys 'short yes/no: Enter is the yes button'                       '<<0>>[[]]' "$S" Return
        keys 'short yes/no: Esc is no'                                     '<<1>>[[]]' "$S" Escape
        SD="$S defaultno"
        keys 'short yes/no, defaultno: Enter is Cancel, so no'             '<<1>>[[]]' "$SD" Return
        keys 'short yes/no, defaultno: Tab and Enter is the yes button'    '<<0>>[[]]' "$SD" Tab Return
        SC='wt_yesno "Pick" Alpha Beta normal "" choice'
        keys 'short choice: Enter is the first action'                     '<<0>>[[]]' "$SC" Return
        keys 'short choice: Tab and Enter is the second action'            '<<1>>[[]]' "$SC" Tab Return
        keys 'short choice: Esc is the first action, never the second'     '<<0>>[[]]' "$SC" Escape

        M='wt --ok-button OK --cancel-button Cancel --menu "Pick" 20 70 3 1 One 2 Two 3 Three'
        keys 'menu: Enter picks the first row'                             '<<0>>[[1]]' "$M" Return
        keys 'menu: Down and Enter pick the second'                        '<<0>>[[2]]' "$M" Down Return
        keys 'menu: Esc is status 1 and no answer'                         '<<1>>[[]]' "$M" Escape
        MT='wt --ok-button OK --cancel-button Cancel --menu "Pick" 20 70 2 -t "-label" 2 Two'
        keys 'menu: a tag that starts with "-" is shown and comes back whole' '<<0>>[[-t]]' "$MT" Return

        keys 'message: Enter is OK'                                        '<<0>>[[]]' 'wt_msgbox "Hello"' Return
        keys 'message: Esc is status 1'                                    '<<1>>[[]]' 'wt_msgbox "Hello"' Escape
        keys 'long message: Enter is OK'                                   '<<0>>[[]]' 'wt_msgbox "$(seq -f "line %g" 1 30)"' Return
        keys 'long message: Esc is status 1'                               '<<1>>[[]]' 'wt_msgbox "$(seq -f "line %g" 1 30)"' Escape

        E='wt --ok-button OK --cancel-button Cancel --inputbox "Name" 10 40 ""'
        keys 'entry: typed text and Enter are the answer'                  '<<0>>[[hello world]]' "$E" 'type:hello world' Return
        keys 'entry: Esc is status 1 and no answer'                        '<<1>>[[]]' "$E" 'type:hello' Escape

        K='wt --ok-button OK --cancel-button Cancel --checklist "Pick" 20 70 3 a "A" off b "B" off c "C" off'
        # Measured with zenity 4.0.1: Enter ticks the row that has the focus (Space does not); the
        # focus starts on the list, and Shift+Tab goes from there to OK. After moving with Down it
        # takes four Tabs to reach OK (three reach Cancel).
        keys 'checklist: Shift+Tab and Enter is OK with nothing ticked'    '<<0>>[[]]' "$K" shift+Tab Return
        keys 'checklist: Esc is status 1 and no answer'                    '<<1>>[[]]' "$K" Escape
        keys 'checklist: Enter ticks the first row, Shift+Tab and Enter confirm' '<<0>>[["a"]]' "$K" Return shift+Tab Return
        keys 'checklist: Down and Enter tick the second, four Tabs and Enter confirm' '<<0>>[["b"]]' "$K" Down Return Tab Tab Tab Tab Return

        # The class and the icon the window manager and the system see in each kind of window.
        classed 'message' 'wt_msgbox "Hello"' info
        ICON_REAL="$(readlink -f "$H_SCRIPT")"; ICON_REAL="${ICON_REAL%/*}"; ICON_REAL="${ICON_REAL%/*}/assets/$ICON_NAME"
        if [ -f "$ICON_REAL" ]; then
            assert_contains 'message: it carries the icon of the program (the file in assets/)' "$PROBE" " --icon=$ICON_REAL "
        else
            skip_case 'real zenity: the icon of the program needs its file in assets/ beside the script'
        fi
        classed 'question' 'wt_yesno "Continue?" Yes No normal' question
        classed 'destructive question' 'wt_yesno "Remove?" Remove Cancel normal defaultno' question
        assert_contains 'destructive question: the warning icon of the theme' "$PROBE" ' --icon=dialog-warning '
        classed 'menu' 'wt --ok-button OK --cancel-button Cancel --menu "Pick" 20 70 2 a A b B' list
        classed 'long message' 'wt_msgbox "$(seq -f "line %g" 1 30)"' text-info
        classed 'error window' 'gui_error "Oops"' error
        classed 'password window of the helper' 'make_askpass; "$ASKPASS_HELPER" "prompt"; gui_cleanup' entry
        classed 'progress window' 'apt_privileged() { sleep 6; }; UI_ENGINE=gui; run_pm_gui "Working..." purge x; gui_cleanup' progress

        # The sizes: what zenity really does with --width and --height.
        # A window with an icon (message, question, error) takes the icon and margins on top of the width asked.
        probe 'wt_msgbox "Hi"'
        pw="${PROBE#* --width=}"; pw="${pw%% *}"
        check_eq 'message: the width asked is the one of its text' 320 "$pw"
        check_eq 'message: the window is that plus the icon and the margins (100 to 180 px)' ok \
            "$([ "${GEOM%x*}" -ge $((pw + 100)) ] && [ "${GEOM%x*}" -le $((pw + 180)) ] && echo ok || echo "$GEOM for $pw")"
        # A list is exactly the size asked, and the one given to a menu of three rows is its own.
        probe "$MENU \"Pick\" 20 70 3$(rows 3)"
        assert_contains 'menu of three rows: the size asked' "$PROBE" ' --width=520 --height=331 '
        check_eq 'menu of three rows: the window is exactly that size' 520x331 "$GEOM"
        probe "$CHECK \"Pick\" 20 70 3 a A off b B off c C off"
        check_eq 'checklist of three rows: the window is exactly the size asked' 520x349 "$GEOM"
        probe "$MENU \"Pick\" 20 70 30$(rows 30)"
        check_eq 'menu of thirty rows: the window is exactly the tallest size' 520x560 "$GEOM"

        # The real xterm, from the launcher with "interface=terminal" saved (FU.6b): the first copy opens it and
        # ends, the copy that runs in it (--terminal --after) takes the lock, and closing xterm frees the lock.
        # With the file as the emulator can run it (755) and as it cannot (644: the relay gives bash first).
        echo "-- Smoke test with the real xterm: the program opens in it from the launcher"
        if ! command -v xterm >/dev/null 2>&1; then
            skip_case 'real xterm: needs xterm (apt install xterm)'
        elif ! DISPLAY=":$X_NUM" timeout 10 xterm -e true >/dev/null 2>&1; then
            skip_case 'real xterm: it does not start in this X server (fonts?)'
        else
            XLOCK="$SB/run/mintapp-remover.lock"
            # proc_find NAME: the PIDs of the processes whose argv[0] is NAME and that were given this program's
            # "--terminal --after": the emulator and, inside it, the new copy of the program (a bash).
            proc_find() {
                local d a0 args
                for d in /proc/[0-9]*; do
                    a0=""
                    IFS= read -r -d '' a0 2>/dev/null < "$d/cmdline" || true
                    [ "${a0##*/}" = "$1" ] || continue
                    args="$(tr '\0' ' ' 2>/dev/null < "$d/cmdline" || true)"
                    case "$args" in *" $SELF --terminal --after "*) echo "${d#/proc/}" ;; esac
                done
            }
            # held: the lock file exists and somebody holds it (flock would create the file, so it is not asked
            # before it exists: the program must be the one that creates it, with its own user).
            held() { [ -e "$XLOCK" ] && ! flock -n "$XLOCK" true; }
            # within10 CODE: CODE succeeds within ten seconds.
            within10() { local _; for _ in $(seq 1 100); do eval "$1" && return 0; sleep 0.1; done; return 1; }
            kill_xterm() { local pid; for pid in $(proc_find xterm) $(proc_find bash); do kill -9 "$pid" 2>/dev/null || true; done; }

            mkdir -p "$SB/run" "$SB/tmp" "$SB/home/.config/mintapp-remover"
            printf 'interface=terminal\n' > "$SB/home/.config/mintapp-remover/config"
            chmod 700 "$SB/home/.config/mintapp-remover"; chmod 600 "$SB/home/.config/mintapp-remover/config"
            sandbox_chown
            rm -f "$SB/bin/sleep"      # the new copy waits for real: the no-op sleep of the harness would cut the wait short
            H_KEEP_CONFIG=1
            for mode in 755 644; do
                program_mode "$mode"
                app_run '' DISPLAY=":$X_NUM" MINTAPP_LANG=en MINTAPP_ASCII=0 MINTAPP_TERMINAL=xterm \
                    TMPDIR="$SB/tmp" XDG_RUNTIME_DIR="$SB/run"
                check_eq "xterm, file $mode: the first copy ends, status 0" 0 "$RC"
                check_eq "xterm, file $mode: it prints nothing" '' "$OUT"
                within10 '[ -n "$(proc_find bash)" ]' && found=yes || found=no
                check_eq "xterm, file $mode: a copy of the program runs in it (bash, the file, --terminal --after)" yes "$found"
                within10 held && took=yes || took=no
                check_eq "xterm, file $mode: that copy takes the lock" yes "$took"
                check_eq "xterm, file $mode: one emulator, no second one" 1 "$(proc_find xterm | wc -l)"
                kill "$(proc_find xterm | head -n1)" 2>/dev/null || true
                within10 '[ -z "$(proc_find bash)" ] && ! held' && freed=yes || freed=no
                check_eq "xterm, file $mode: closing it ends the copy and frees the lock" yes "$freed"
                kill_xterm
            done
            real_app
            H_KEEP_CONFIG=0
            rm -f "$SB/home/.config/mintapp-remover/config"
        fi
    fi
    x_stop
    trap _harness_cleanup EXIT
fi

finish
