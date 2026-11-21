#!/bin/bash
# MENU: MintApp Remover
# DESCRIPTION: Remove preinstalled apps safely, always showing the real package-manager plan first
# CONFIRM: false
# TERMINAL: true
# SUDO: false
# ICON: ../assets/icon5.png
#
# MintApp Remover
# Uninstaller and cleaner for preinstalled applications on Linux
#
# Copyright (C) 2026 Filonux
#
# License:
#   MintApp Remover is free software distributed under the terms of the
#   GNU General Public License version 3 (GPLv3).
#   See the LICENSE.txt file for the full license text.
#
# Usage: chmod +x MintApp_Remover.sh && ./MintApp_Remover.sh
#        ./MintApp_Remover.sh --help | --version
#
# Offers a curated catalog of commonly preinstalled applications (Option 2)
# and an advanced mode (Option 3) that scans the real menu launchers
# (.desktop) to find applications outside that catalog, Flatpak and Snap ones
# included, excluding system components. Packages are removed after showing
# the simulation of the package manager; Flatpak and Snap, after the plan of
# their own command. Option 4 cleans up: the dependencies no longer needed
# and, deeper, leftover files and caches.
#
# Compatibility: Linux with apt/dpkg (Debian, Ubuntu and derivatives), with
# dnf 4 and rpm (Fedora, RHEL and derivatives; dnf 5 is not supported yet),
# with pacman (Arch and derivatives) and with zypper (openSUSE and
# derivatives). The package manager is chosen at start: MINTAPP_PM, else
# the one of the distribution family, else the first one found (pm_detect).
# At start it also detects the distribution and the desktop (/etc/os-release
# and XDG_CURRENT_DESKTOP) to pick the Option 2 catalog and the system
# components that Option 3 leaves out (Cinnamon, GNOME, KDE Plasma, XFCE,
# MATE), without naming them in the interface. On an unrecognized desktop it
# uses the lists of all of them. Option 3 is the most portable because it
# relies on a dynamic launcher scan instead of a fixed list. Not compatible
# with distros without apt, dnf, pacman or zypper (Alpine, Void, Gentoo, etc.).

set -uo pipefail

# bash 5.2 replaces an "&" in the replacement of ${text//pattern/replacement}
# with the text it matched (shopt patsub_replacement); earlier versions never
# did. The program writes "&" literally in replacements (gui_escape), so the
# feature is switched off: the same code then behaves alike in every version.
shopt -u patsub_replacement 2>/dev/null || true

# ----------------------------------------------------------------------------
# Minimum bash version: 4.3 (associative arrays, namerefs). It is checked
# before anything else, with syntax that any bash 3.x can still parse, so an
# old bash gets one clear line instead of a cascade of syntax errors. The text
# is bilingual here because the message tables do not exist yet; the language
# is guessed from MINTAPP_LANG or the locale only.
# $1 = major, $2 = minor of the running bash. Fails (status 1) if too old.
# ----------------------------------------------------------------------------
require_bash_version() {
    local major="$1" minor="$2" lang="${MINTAPP_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}"
    if [ "$major" -gt 4 ] 2>/dev/null || { [ "$major" -eq 4 ] && [ "$minor" -ge 3 ]; } 2>/dev/null; then
        return 0
    fi
    case "$lang" in
        [eE][sS]|[eE][sS][_.@-]*)
            printf 'MintApp Remover requiere bash 4.3 o superior; esta es la versión %s.%s.\n' "$major" "$minor" >&2 ;;
        *)
            printf 'MintApp Remover requires bash 4.3 or newer; this is version %s.%s.\n' "$major" "$minor" >&2 ;;
    esac
    return 1
}
# "return" ends a sourced file; when the script is executed it fails and "exit"
# runs instead. ShellCheck cannot see that, hence the disable.
# shellcheck disable=SC2317
require_bash_version "${BASH_VERSINFO[0]:-0}" "${BASH_VERSINFO[1]:-0}" || { return 1 2>/dev/null || exit 1; }

MINTAPP_VERSION="2.2.0"
readonly MINTAPP_VERSION

# ----------------------------------------------------------------------------
# Colors. One hue, green, for everything that can be chosen: a chosen item is
# told apart by its SHAPE (a solid block, black on green), never by another
# colour. Blue is only for what cannot be chosen (frames, titles) and yellow
# for warnings and errors, so no blue block can be taken for a selection.
# Plain-text mode
# uses ANSI sequences and whiptail its own palette (replacing the default one,
# which usually highlights in red/magenta). Both are switched off, and the
# dialogs go monochrome, when NO_COLOR is set to any non-empty value
# (https://no-color.org), when TERM is "dumb" or when the terminal reports
# fewer than 8 colors. If that cannot be told (no tput, no or unknown TERM) the
# colors stay on.
# ----------------------------------------------------------------------------
use_color() {
    [ -z "${NO_COLOR:-}" ] || return 1
    # Without TERM in its environment bash sets TERM=dumb for itself, without
    # exporting it: that means "unknown", only an exported "dumb" is a dumb
    # terminal.
    if [ "${TERM:-}" = "dumb" ]; then
        case "$(declare -p TERM 2>/dev/null)" in "declare -x "*) return 1 ;; esac
    fi
    local count
    count=$(tput colors 2>/dev/null) || return 0
    case "$count" in
        "") return 0 ;;
        *[!0-9]*) return 1 ;;   # "-1": the terminal has no color capability
    esac
    [ "$count" -ge 8 ]
}

setup_colors() {
    if use_color; then
        C_RESET="\033[0m"
        C_TITLE="\033[1;34m"      # blue (headers, titles)
        C_OK="\033[1;32m"         # green (success / detected)
        C_WARN="\033[1;33m"       # yellow (warnings)
        C_MARK="\033[1;30;42m"    # black on green (marked/selected)
        C_ERR="\033[1;33m"        # yellow (errors)
        C_BOLD="\033[1m"
        C_DIM="\033[2m"           # dim (descriptions under the menu options)
        # Black background; bright green text for normal elements and for the
        # buttons and list entries that are not active (the same hue as the
        # active one, so only the block tells them apart), bright blue for
        # borders and titles (plain blue on black is barely readable), and
        # black on solid green for the active element. Backgrounds stay
        # plain: a terminal draws only the 8 basic ones.
        export NEWT_COLORS='
root=brightgreen,black
border=brightblue,black
window=brightgreen,black
shadow=black,black
title=brightblue,black
button=brightgreen,black
actbutton=black,green
compactbutton=brightgreen,black
checkbox=brightgreen,black
actcheckbox=black,green
entry=brightgreen,black
label=brightgreen,black
listbox=brightgreen,black
actlistbox=black,green
sellistbox=brightgreen,black
actsellistbox=black,green
textbox=brightgreen,black
acttextbox=black,green
helpline=brightblue,black
roottext=brightblue,black
emptyscale=,black
fullscale=,green
disentry=blue,black
'
    else
        C_RESET="" C_TITLE="" C_OK="" C_WARN="" C_MARK="" C_ERR="" C_BOLD="" C_DIM=""
        export NEWT_MONO=1
    fi
    readonly C_RESET C_TITLE C_OK C_WARN C_MARK C_ERR C_BOLD C_DIM
}
setup_colors

# ----------------------------------------------------------------------------
# Symbols and ASCII mode. The program draws a few symbols (check marks, arrows,
# a dash) and the Spanish text has accents. Without a UTF-8 locale the terminal
# and whiptail show them as garbage and misjudge widths, so in that case the
# program's own text is written in plain ASCII: symbols become + [x] [ ] - ^ v
# and accents are dropped. Names that come from the system (launchers) are
# shown as they are; the name of the system in the status line of the main menu
# is folded (ascii_only), so that screen stays pure ASCII. MINTAPP_ASCII=1
# forces ASCII (a console font without those glyphs) and MINTAPP_ASCII=0
# forces Unicode.
# ----------------------------------------------------------------------------
use_unicode() {
    case "${MINTAPP_ASCII:-}" in
        1) return 1 ;;
        0) return 0 ;;
    esac
    # The real charmap tells whether the locale is usable (LANG=es_ES.UTF-8 on
    # a machine that never generated it gives ANSI_X3.4-1968); the variables
    # are the fallback when "locale" is not available.
    local charset
    charset="$(locale charmap 2>/dev/null)" || charset=""
    [ -n "$charset" ] || charset="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "${charset^^}" in
        *UTF-8*|*UTF8*) return 0 ;;
    esac
    return 1
}

if use_unicode; then
    UNICODE=1
    SYM_OK="✓" SYM_ON="☑" SYM_OFF="☐" SYM_DASH="—"
    SYM_RULE="═" SYM_LINE="─"   # heavy rule (header), light rule (sections)
    SYM_ELLIPSIS="…"            # marks a label cut to fit a dialog
    SYM_SEP="·"                 # separates the fields of a status line
else
    UNICODE=0
    SYM_OK="+" SYM_ON="[x]" SYM_OFF="[ ]" SYM_DASH="-"
    SYM_RULE="=" SYM_LINE="-"
    SYM_ELLIPSIS="..."
    SYM_SEP="|"
fi
readonly UNICODE SYM_OK SYM_ON SYM_OFF SYM_DASH SYM_RULE SYM_LINE SYM_ELLIPSIS SYM_SEP

# ASCII version of the program's own text: puts it in REPLY. Only the
# characters the program itself uses are handled (see the tests: a new one
# in a message must be added here).
ascii_fold() {
    local t="$1"
    t="${t//↑/^}" t="${t//↓/v}" t="${t//←/<-}" t="${t//→/->}" t="${t//—/-}" t="${t//✓/+}" t="${t//☑/[x]}" t="${t//☐/[ ]}"
    t="${t//á/a}" t="${t//é/e}" t="${t//í/i}" t="${t//ó/o}" t="${t//ú/u}" t="${t//ü/u}" t="${t//ñ/n}"
    t="${t//Á/A}" t="${t//É/E}" t="${t//Í/I}" t="${t//Ó/O}" t="${t//Ú/U}" t="${t//Ü/U}" t="${t//Ñ/N}"
    t="${t//¿/}" t="${t//¡/}"
    REPLY="$t"
}

# Like ascii_fold, for a name that comes from the system and is shown on a
# screen that must stay pure ASCII: what the program knows is folded and any
# other non-ASCII character becomes "?". Puts it in REPLY.
ascii_only() {
    ascii_fold "$1"
    REPLY="${REPLY//[![:ascii:]]/?}"
}

# ----------------------------------------------------------------------------
# Interface: on a terminal the program's own dialogs ("tui": full window,
# redrawn when the window is resized, focus shown in colour, keys listed on the
# last row); without a terminal (a launcher) the graphical dialogs ("gui",
# zenity) when zenity and a graphical session are there; whiptail when asked
# for; otherwise the plain-text menu. Command line: --gui and --terminal force
# one or the other (never both; --gui fails when the windows cannot be used).
# From a launcher, when the last choice was the terminal (T in the windows,
# saved as "interface"), a terminal emulator opens with the program instead of
# the windows (terminal_start_wanted).
# Advanced configuration (environment variables, all optional):
#   MINTAPP_UI=tui|gui|whiptail|text   force one interface (default: tui on a
#                             terminal, gui without one). gui needs zenity and
#                             a graphical session; without them the default is
#                             used. --gui and --terminal prevail over it.
#   MINTAPP_TERMINAL=name-or-path   terminal emulator to open when going back
#                             to the terminal (default: the first one found,
#                             see TERMINAL_TABLE)
#   MINTAPP_ESC_WAIT=0.15   seconds to wait after Esc before taking it as the
#                             Esc key (raise it on a slow SSH link)
#   MINTAPP_LANG=en|es   force the interface language instead of auto-detecting
#   MINTAPP_LAUNCHER_DIRS=dir1:dir2   scan only these folders in Option 3
#   MINTAPP_OS_RELEASE=file   read the system name from this file instead of
#                             /etc/os-release (tests and diagnostics)
#   MINTAPP_PM=apt|dnf|pacman|zypper   force the package manager (only the ones
#                             with a backend, see PM_BACKENDS; any other value
#                             is an error). Default: the one of the
#                             distribution family, else the first one found
#                             (pm_detect)
#   MINTAPP_SUDO=name-or-path   command that gives administrator rights
#                             (default: sudo; doas if sudo is missing). In
#                             windows sudo asks for the password in a window
#                             (sudo -A); doas cannot, so it needs a nopass rule.
#   NO_COLOR=1   no colors (also with TERM=dumb or fewer than 8 colors)
#   MINTAPP_ASCII=1|0   plain ASCII text (1) or Unicode symbols (0); by
#                             default ASCII is used when the locale is not UTF-8
# ----------------------------------------------------------------------------
# zenity can be used when the command exists, there is a graphical session and
# its help lists the options the dialogs rely on (a clone or an old version
# that lacks one would fail in the middle of a screen). The answer is kept: the
# check runs zenity once. Status 0 = usable. It also sets GUI_LOCALE, the locale
# zenity runs under (see gui_dialog): C.UTF-8 when the system has it. The same
# help gives GUI_OPTS, the optional options it lists (--icon, --hide-header; see
# gui_opt): a window uses one only if it is there, else it looks as it always did.
GUI_USABLE=""
GUI_LOCALE=""
GUI_OPTS=""
zenity_usable() {
    if [ -z "$GUI_USABLE" ]; then
        GUI_USABLE=1
        if command -v zenity >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
            local help opt re
            help="$(zenity --help-all 2>/dev/null)" || help=""
            GUI_USABLE=0
            for opt in --checklist --hide-column --print-column --no-markup --default-cancel --extra-button --switch --text-info; do
                re="(^|[[:space:]])${opt}([=[:space:]]|\$)"
                [[ "$help" =~ $re ]] || { GUI_USABLE=1; break; }
            done
            if [ "$GUI_USABLE" -eq 0 ]; then
                GUI_OPTS=" "
                for opt in --icon --hide-header; do
                    re="(^|[[:space:]])${opt}([=[:space:]]|\$)"
                    [[ ! "$help" =~ $re ]] || GUI_OPTS+="$opt "
                done
                if locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$'; then
                    GUI_LOCALE="C.UTF-8"
                fi
            fi
        fi
    fi
    return "$GUI_USABLE"
}

# gui_opt OPTION: status 0 when zenity's help lists that optional option.
gui_opt() {
    [[ "$GUI_OPTS" == *" $1 "* ]]
}

# The dialogs need both stdin and stdout to be a terminal.
has_terminal() {
    [ -t 0 ] && [ -t 1 ]
}

# Which interface starts (UI_ENGINE; HAVE_WHIPTAIL means "dialog screens" for
# tui, gui and whiptail, which share one contract). UI_REQUEST is what the
# command line asked for: --gui ("gui") or --terminal ("terminal").
#   - A request beats MINTAPP_UI. --gui is MINTAPP_UI=gui; --terminal only
#     rules out the windows (tui, whiptail and text stay as MINTAPP_UI says).
#   - MINTAPP_UI=whiptail forces whiptail even without a terminal (tests).
#   - MINTAPP_UI=gui asks for zenity and, when it cannot be used, takes the
#     default (--gui does not: main refuses to go on, see main).
#   - By default: tui on a terminal, whatever else there is. Without a
#     terminal (a launcher, cron) the windows when zenity can be used, unless
#     --terminal was given; otherwise the plain-text menu.
# It runs when the file is loaded and again in main, after the command line.
# Only switch_to_gui and switch_to_terminal change the result afterwards (the
# G and T entries of the menus); main may also end this copy to open a terminal
# (terminal_start_wanted).
UI_REQUEST=""
UI_ENGINE=text
HAVE_WHIPTAIL=0
select_interface() {
    local ui="${MINTAPP_UI:-auto}"
    UI_ENGINE=text HAVE_WHIPTAIL=0
    case "$UI_REQUEST" in
        gui) ui=gui ;;
        terminal) [ "$ui" != "gui" ] || ui=auto ;;
    esac
    case "$ui" in
        text) ;;
        whiptail)
            if command -v whiptail >/dev/null 2>&1; then UI_ENGINE=whiptail HAVE_WHIPTAIL=1; fi ;;
        gui)
            if zenity_usable; then
                UI_ENGINE=gui HAVE_WHIPTAIL=1
            elif has_terminal; then
                UI_ENGINE=tui HAVE_WHIPTAIL=1
            fi ;;
        *)
            if has_terminal; then
                UI_ENGINE=tui HAVE_WHIPTAIL=1
            elif [ "$UI_REQUEST" != "terminal" ] && zenity_usable; then
                UI_ENGINE=gui HAVE_WHIPTAIL=1
            fi ;;
    esac
}
select_interface

WT_TITLE=""

# whiptail box dimensions: recalculated on every screen from the real
# terminal size (see calc_whiptail_dimensions), because asking whiptail for a
# box larger than the terminal leaves buttons outside the interactive area.
# The values here are only a fallback in case a function runs before the
# first call to that function.
WT_HEIGHT=20
WT_WIDTH=73
WT_HEIGHT_BIG=22
WT_WIDTH_BIG=76
# Widest box in columns, however large the window is: past this the lines
# get too long to read. One value per kind of box; change them here.
WT_MAX_WIDTH=120
WT_MAX_WIDTH_BIG=140
TERM_LINES=24
TERM_COLS=80
# Plain-text screens use the terminal's width minus one column (a line that
# fills the last column wraps early on some terminals), never more than
# TEXT_MAX_WIDTH: past that the lines get too long to read.
TEXT_MAX_WIDTH=100
TEXT_W=79

# Puts the terminal size in TERM_LINES and TERM_COLS: 24x80 when it cannot be
# told (no terminal, no tput) or when the value is implausibly small.
read_terminal_size() {
    TERM_LINES=$(tput lines 2>/dev/null)
    TERM_COLS=$(tput cols 2>/dev/null)
    case "$TERM_LINES" in ''|*[!0-9]*) TERM_LINES=24 ;; esac
    case "$TERM_COLS"  in ''|*[!0-9]*) TERM_COLS=80 ;; esac
    [ "$TERM_LINES" -lt 10 ] && TERM_LINES=24
    [ "$TERM_COLS" -lt 40 ] && TERM_COLS=80
    return 0
}

# Computes the whiptail box sizes from the terminal size at that moment.
# Called at the start of every screen, so if the user resizes the window
# between screens the next one adjusts by itself. The font size is the
# terminal's business, not the script's: what the script controls is how much
# of the window the box takes, so a larger window shows more rows and wider
# lines. Normal boxes (menus, lists, short messages) take 85% of the height
# and 92% of the width; big boxes (plans, long text) take 92% and 96%. On an
# 80x24 terminal that is the classic 20x73 and 22x76.
calc_whiptail_dimensions() {
    read_terminal_size

    WT_HEIGHT=$(( TERM_LINES * 85 / 100 ))
    WT_WIDTH=$(( TERM_COLS * 92 / 100 ))
    WT_HEIGHT_BIG=$(( TERM_LINES * 92 / 100 ))
    WT_WIDTH_BIG=$(( TERM_COLS * 96 / 100 ))

    [ "$WT_WIDTH" -gt "$WT_MAX_WIDTH" ] && WT_WIDTH=$WT_MAX_WIDTH
    [ "$WT_WIDTH_BIG" -gt "$WT_MAX_WIDTH_BIG" ] && WT_WIDTH_BIG=$WT_MAX_WIDTH_BIG
    [ "$WT_HEIGHT" -lt 12 ] && WT_HEIGHT=12
    [ "$WT_HEIGHT_BIG" -lt 14 ] && WT_HEIGHT_BIG=14
    [ "$WT_WIDTH" -lt 30 ] && WT_WIDTH=30
    [ "$WT_WIDTH_BIG" -lt 40 ] && WT_WIDTH_BIG=40

    # Never past the terminal: the first row belongs to the backtitle and the
    # box casts a shadow on its right and bottom edges.
    local max_height=$(( TERM_LINES - 2 )) max_width=$(( TERM_COLS - 2 ))
    [ "$WT_HEIGHT" -gt "$max_height" ] && WT_HEIGHT=$max_height
    [ "$WT_HEIGHT_BIG" -gt "$max_height" ] && WT_HEIGHT_BIG=$max_height
    [ "$WT_WIDTH" -gt "$max_width" ] && WT_WIDTH=$max_width
    [ "$WT_WIDTH_BIG" -gt "$max_width" ] && WT_WIDTH_BIG=$max_width
    return 0
}

# Sets TEXT_W, the width of the plain-text screens, from the terminal size at
# that moment (read again on every screen, like the dialogs).
set_text_width() {
    read_terminal_size
    TEXT_W=$(( TERM_COLS - 1 ))
    [ "$TEXT_W" -le "$TEXT_MAX_WIDTH" ] || TEXT_W=$TEXT_MAX_WIDTH
    return 0
}

# ----------------------------------------------------------------------------
# Dialog text and boxes. Without --scrolltext whiptail silently cuts the text
# that does not fit; with it the focus starts on the text, so Enter does
# nothing until TAB reaches a button. So the text is wrapped here, its lines
# are counted, and --scrolltext is used only when the text is taller than the
# box. A message or question needs 6 rows besides its text (borders, blank
# lines, buttons) and a list needs 7 besides its prompt and its items.
# ----------------------------------------------------------------------------
WT_BOX_H=20
WT_BOX_W=73
WT_TEXT=""
WT_TEXT_LINES=0
WT_LIST_ROWS=10
WT_SCROLL=()

# Wraps the line $2 to WIDTH columns ($1), breaking at spaces, and leaves its rows
# in WRAP_ROWS. It runs in the shell that calls it (no sub-shell), so wrap_even
# can try many widths cheaply. The continuation of a line keeps that line's
# indentation, unless it is wider than a third of the width and leaves less than
# 20 columns for the text. Leading spaces that fill the width (they would be a
# row of their own) or leave no room for the first word (it would be split by
# its own indentation) are dropped: the line starts at the first column. A line
# laid out as a key and its explanation ("  TAB      explanation ..."; two or
# more spaces, a key of at most 12 characters, three or more spaces) hangs
# instead: its continuation goes under the explanation, not under the key, if
# 20 columns or more are left there. The tables a package manager prints start
# in the first column or after one space, so they do not match. A word longer
# than the width is cut at the width, except a path (a word with a "/"): it
# breaks after the last "/" that fits, if the name after that "/" fits whole on
# a row and something precedes the "/" after the continuation indentation, so a
# name is split only when it is wider than a row by itself; spaces that end the
# line are dropped when they fall on a break.
WRAP_ROWS=()
wrap_line() {
    local width="$1" line="$2" indent hang head cut first name
    local hang_re='^( {2,})([^ ]( ?[^ ])*) {3,}[^ ]'
    [ "$width" -ge 10 ] || width=10
    WRAP_ROWS=()
    indent="${line%%[![:space:]]*}"
    first="${line:${#indent}}"
    first="${first%% *}"
    if [ "${#indent}" -ge "$width" ] || { [ "${#first}" -le "$width" ] && [ $(( ${#indent} + ${#first} )) -gt "$width" ]; }; then
        line="${line:${#indent}}"
        indent=""
    fi
    # An indentation wider than a third of the line that leaves less than 20 columns would leave no room.
    if [ "${#indent}" -gt $(( width / 3 )) ] && [ $(( width - ${#indent} )) -lt 20 ]; then indent=""; fi
    hang="$indent"
    if [ "${#line}" -gt "$width" ] && [ -n "$indent" ] && [[ "$line" =~ $hang_re ]] \
        && [ "${#BASH_REMATCH[2]}" -le 12 ] \
        && [ $(( width - ${#BASH_REMATCH[0]} + 1 )) -ge 20 ]; then
        printf -v hang '%*s' $(( ${#BASH_REMATCH[0]} - 1 )) ''
    fi
    while [ "${#line}" -gt "$width" ]; do
        # One character past the width: a space there is a clean break.
        head="${line:0:width+1}"
        cut=""
        if [[ "$head" == *" "* ]]; then
            cut="${head% *}"
            if [ "${#cut}" -le "${#hang}" ] || [ -z "${cut//[[:space:]]/}" ]; then
                cut=""
            fi
        fi
        if [ -z "$cut" ]; then
            # No break at a space: cut at the width, or after the last "/" of
            # the row (head: what precedes it; name: the name after it).
            cut="${line:0:width}"
            head="${cut%/*}"
            name="${line:${#head}+1}"
            name="${name%%[/[:space:]]*}"
            if [ "$head" != "$cut" ] && [ "${#head}" -gt "${#hang}" ] \
                && [ "${#name}" -le $(( width - ${#hang} )) ]; then
                cut="${head}/"
            fi
            WRAP_ROWS+=("$cut")
            line="${hang}${line:${#cut}}"
            continue
        fi
        WRAP_ROWS+=("${cut%"${cut##*[![:space:]]}"}")
        line="${line:${#cut}}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${hang}${line}"
    done
    # Only spaces left after the last break are not a row of their own.
    if [ "${#WRAP_ROWS[@]}" -eq 0 ] || [ -n "${line//[[:space:]]/}" ]; then WRAP_ROWS+=("$line"); fi
}

# Wraps the text on stdin to WIDTH columns ($1), one line at a time (wrap_line).
wrap_text() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        wrap_line "$1" "$line"
        printf '%s\n' "${WRAP_ROWS[@]}"
    done
}

# The own engines (tui and gui) lay their text and their rows out themselves,
# so the text is not wrapped and the labels are not cut for them (whiptail needs
# both). Succeeds when the active engine is one of them.
engine_fits_itself() {
    [ "$UI_ENGINE" = "tui" ] || [ "$UI_ENGINE" = "gui" ]
}

# The active dialog engine with what every dialog of the program shares: the
# title of the box and, on the first row of the screen, the backtitle (name and
# version; zenity has no backtitle).
wt() {
    case "$UI_ENGINE" in
        tui) tui_dialog --title "$WT_TITLE" --backtitle "$(app_backtitle)" "$@" ;;
        gui) gui_dialog --title "$WT_TITLE" "$@" ;;
        *) whiptail --title "$WT_TITLE" --backtitle "$(app_backtitle)" "$@" ;;
    esac
}

# Sets WT_BOX_H and WT_BOX_W to the size of a "normal" or "big" ($1) box.
wt_box_size() {
    calc_whiptail_dimensions
    if [ "${1:-normal}" = "big" ]; then
        WT_BOX_H=$WT_HEIGHT_BIG
        WT_BOX_W=$WT_WIDTH_BIG
    else
        WT_BOX_H=$WT_HEIGHT
        WT_BOX_W=$WT_WIDTH
    fi
}

# Wraps a dialog text for a box WIDTH ($2) columns wide: \n sequences become
# line breaks (as whiptail itself would do), WT_TEXT gets the wrapped text and
# WT_TEXT_LINES its number of lines. Six columns are left for the borders and
# the scroll bar, so whiptail never has to wrap a line again. The own engines
# keep the text as it is; gui (zenity wraps it itself) counts the lines it
# will take at GUI_WRAP_COLS columns.
wt_text() {
    local text="${1//\\n/$'\n'}"
    local -a lines=()
    if [ "$UI_ENGINE" = "gui" ]; then
        WT_TEXT="$text"
        mapfile -t lines < <(printf '%s\n' "$text" | wrap_text "$GUI_WRAP_COLS")
    elif engine_fits_itself; then
        WT_TEXT="$text"
        mapfile -t lines <<< "$WT_TEXT"
    else
        WT_TEXT="$(printf '%s\n' "$text" | wrap_text $(( $2 - 6 )))"
        mapfile -t lines <<< "$WT_TEXT"
    fi
    WT_TEXT_LINES="${#lines[@]}"
}

# Prepares a message or a question: $1 = text, $2 = size (normal | big). Sets
# WT_TEXT, WT_BOX_W, WT_BOX_H (as tall as the text needs, at least 9 rows and
# at most what the size allows) and WT_SCROLL (--scrolltext only if the text
# is taller than that).
wt_fit_message() {
    wt_box_size "${2:-normal}"
    wt_text "$1" "$WT_BOX_W"
    local height=$(( WT_TEXT_LINES + 6 ))
    WT_SCROLL=()
    # gui sizes its windows itself: only whether the text is taller than a
    # message window (GUI_TEXT_LINES) matters, and then it scrolls.
    if [ "$UI_ENGINE" = "gui" ]; then
        [ "$WT_TEXT_LINES" -le "$GUI_TEXT_LINES" ] || WT_SCROLL=(--scrolltext)
        return 0
    fi
    [ "$height" -ge 9 ] || height=9
    if [ "$height" -gt "$WT_BOX_H" ]; then
        height="$WT_BOX_H"
        WT_SCROLL=(--scrolltext)
    fi
    WT_BOX_H="$height"
}

# Message box. $1 = text (with \n sequences), $2 = size: normal | big.
wt_msgbox() {
    wt_fit_message "$1" "${2:-normal}"
    wt --ok-button "$(msg ok)" "${WT_SCROLL[@]+"${WT_SCROLL[@]}"}" --msgbox "$WT_TEXT" "$WT_BOX_H" "$WT_BOX_W"
}

# Question; its status is whiptail's (0 yes, 1 no, 255 Esc). $1 = text,
# $2 = label of the yes button, $3 = label of the no button, $4 = size,
# $5 = "defaultno": the no button starts active (what Enter presses),
# $6 = "choice": the two buttons are two actions, not yes and no (a language
# button, a search button). Only gui cares: there closing the window or Esc
# is the first action, never the second one (zenity cannot tell Esc from "no").
wt_yesno() {
    local -a default=()
    [ "${5:-}" != "defaultno" ] || default=(--defaultno)
    if [ "${6:-}" = "choice" ] && [ "$UI_ENGINE" = "gui" ]; then default+=(--choice); fi
    wt_fit_message "$1" "${4:-normal}"
    wt "${default[@]+"${default[@]}"}" --yes-button "$2" --no-button "$3" "${WT_SCROLL[@]+"${WT_SCROLL[@]}"}" --yesno "$WT_TEXT" "$WT_BOX_H" "$WT_BOX_W"
}

# Prepares a list dialog (menu or checklist): $1 = prompt, $2 = number of
# items. Sets WT_TEXT, WT_BOX_W, WT_LIST_ROWS (every row the box can spare,
# never more than the items) and WT_BOX_H (exactly what those rows need: if
# whiptail is asked for more rows than fit it grows the box past the terminal).
wt_list_prepare() {
    wt_box_size normal
    wt_text "$1" "$WT_BOX_W"
    WT_LIST_ROWS=$(( WT_BOX_H - WT_TEXT_LINES - 7 ))
    [ "$WT_LIST_ROWS" -ge 3 ] || WT_LIST_ROWS=3
    [ "$WT_LIST_ROWS" -le "$2" ] || WT_LIST_ROWS="$2"
    WT_BOX_H=$(( WT_TEXT_LINES + WT_LIST_ROWS + 7 ))
}

# whiptail never cuts the label of a list row: a long one runs past the frame
# (and off the screen) or covers the scroll bar. A label starts 9 columns plus
# the width of the widest tag after the left border, and the bar sits 4
# columns before the right border; one blank column is left before the bar.
# $1 = box width, $2 = number of entries (the widest tag has as many digits as
# that number). Puts the usable columns in REPLY, never fewer than 10.
wt_label_width() {
    if engine_fits_itself; then REPLY=100000; return 0; fi
    local width=$(( $1 - 15 - ${#2} ))
    [ "$width" -ge 10 ] || width=10
    REPLY="$width"
}

# Fits a label to WIDTH columns ($1) and puts it in REPLY: unchanged if it
# fits, else cut with an ellipsis. $2 = label; $3 = optional tail, the end of
# the label (such as "[package]") that is kept whole while the rest is cut,
# because it is what tells two entries apart.
wt_fit_label() {
    local width="$1" label="$2" tail="${3:-}" head sep text keep
    REPLY="$label"
    [ "${#label}" -gt "$width" ] || return 0
    [ "$width" -ge 4 ] || width=4
    if [ -n "$tail" ] && [[ "$label" == *"$tail" ]]; then
        head="${label%"$tail"}"
        sep="${head##*[![:space:]]}"
        text="${head%"$sep"}"
        keep=$(( width - ${#tail} - ${#sep} - ${#SYM_ELLIPSIS} ))
        if [ "$keep" -ge 3 ]; then
            text="${text:0:keep}"
            REPLY="${text%"${text##*[![:space:]]}"}${SYM_ELLIPSIS}${sep}${tail}"
            return 0
        fi
    fi
    text="${label:0:width-${#SYM_ELLIPSIS}}"
    REPLY="${text%"${text##*[![:space:]]}"}${SYM_ELLIPSIS}"
}

# A whiptail row has room for one line, so a description that does not fit
# next to its label ("label - description", see menu_item_text) is cut. When
# that happens in a menu, this puts every description whole in the text of the
# box, under the prompt, each one after its label and wrapped, and the rows keep
# the labels alone. $1 = prompt, $2 = number of entries, $3 = columns of a row
# (wt_label_width), $4 and $5 = the names of the arrays of labels and
# descriptions. Succeeds, with WT_TEXT, WT_BOX_H and WT_LIST_ROWS ready for the
# new text, when it did so; fails, with them ready for the prompt alone, when
# every description fits or when the text and the rows would not fit the screen
# (then the descriptions stay in the rows, cut as ever).
wt_menu_descs_in_text() {
    local prompt="$1" count="$2" width="$3" i room max row text="$1" cut=0
    local -n _wd_labels="$4" _wd_descs="$5"
    for (( i = 0; i < count; i++ )); do
        [ -n "${_wd_descs[i]}" ] || continue
        room=$(( width - ${#_wd_labels[i]} - 3 ))
        if [ "$room" -lt 8 ] || [ "${#_wd_descs[i]}" -gt "$room" ]; then cut=1; fi
    done
    if [ "$cut" -eq 1 ]; then
        wt_box_size normal
        max="$WT_BOX_H"
        text+=$'\n'
        for (( i = 0; i < count; i++ )); do
            text+=$'\n'"${_wd_labels[i]}"
            [ -z "${_wd_descs[i]}" ] || while IFS= read -r row; do
                text+=$'\n'"   ${row}"
            done < <(printf '%s\n' "${_wd_descs[i]}" | wrap_even $(( WT_BOX_W - 9 )))
        done
        wt_text "$text" "$WT_BOX_W"
        [ $(( WT_TEXT_LINES + count + 7 )) -le "$max" ] || cut=0
    fi
    if [ "$cut" -eq 1 ]; then wt_list_prepare "$text" "$count"; else wt_list_prepare "$prompt" "$count"; fi
    [ "$cut" -eq 1 ]
}

# ----------------------------------------------------------------------------
# Own dialog engine ("tui"), the default interface on a terminal. It has the
# same contract as whiptail (menu, checklist, yesno, msgbox, inputbox; status
# 0 accept, 1 cancel, 255 Esc; the answer goes to stderr), so the screens do
# not change. What whiptail cannot do and this engine does: it fills the whole
# window, draws again when the window is resized, shows the focused button in
# colour and lists the keys on the last row. It is plain bash (no dependency)
# and it always puts the terminal back as it found it.
# ----------------------------------------------------------------------------
TUI_MIN_ROWS=12             # smaller than this a "enlarge the window" note is shown
TUI_MIN_COLS=44
TUI_MAX_TEXT=110            # widest text line: past this reading gets tiring
TUI_TICK=0.25               # idle poll of the window size, in seconds
TUI_ESC_WAIT=0.15           # wait after Esc to tell it from an arrow key (MINTAPP_ESC_WAIT)
# MINTAPP_ESC_WAIT: a number of seconds from 0.05 to 5 with up to three
# decimals; anything else (text, a comma, out of range) leaves the default.
# The value is only compared as a number of milliseconds, never evaluated.
if [[ "${MINTAPP_ESC_WAIT:-}" =~ ^([0-9])(\.([0-9]{1,3}))?$ ]]; then
    _frac="${BASH_REMATCH[3]}000"
    _ms=$(( BASH_REMATCH[1] * 1000 + 10#${_frac:0:3} ))
    if [ "$_ms" -ge 50 ] && [ "$_ms" -le 5000 ]; then TUI_ESC_WAIT="$MINTAPP_ESC_WAIT"; fi
    unset _frac _ms
fi
TUI_ACTIVE=0
TUI_SAVED_STTY=""
TUI_SAVED_TRAPS=""
TUI_RESIZED=0
TUI_SIG=0                   # status of a signal that arrived while a dialog was open
TUI_HOTKEYS=""              # "key=status ..." extra keys for the next yesno/msgbox
TUI_R=24
TUI_C=80
TUI_SP=""

# Sets TS_* (styles) and TG_* (frame glyphs). Colour only when the terminal
# has it (use_color); without colour the focus is shown in reverse video.
# Everything that can be chosen (buttons, list rows) is green; what is chosen
# is told apart by shape: a block (black on green) for what has the focus and a
# pointer in the margin for the current row of a list.
tui_init_style() {
    local e=$'\033['
    TS_RESET="${e}0m"
    if use_color; then
        TS_BAR="${e}1;37;44m" TS_BORDER="${e}1;34m" TS_TITLE="${e}1;32m" TS_TAG="${e}1;32m"
        TS_SEL="${e}30;42m" TS_MARK="${e}1;32m" TS_BTN="${e}1;32m" TS_BTN_ON="${e}30;42m"
        TS_CHIP="${e}30;47m" TS_WARN="${e}1;33m" TS_SCROLL="${e}34m" TS_THUMB="${e}1;34m"
        TS_SEL_OFF="${e}1;32m" TS_DESC="${e}2m"
    else
        TS_BAR="${e}7m" TS_BORDER="" TS_TITLE="${e}1m" TS_TAG="${e}1m"
        TS_SEL="${e}7m" TS_MARK="${e}1m" TS_BTN="" TS_BTN_ON="${e}7m"
        TS_CHIP="${e}7m" TS_WARN="${e}1m" TS_SCROLL="" TS_THUMB="${e}1m"
        TS_SEL_OFF="${e}4m" TS_DESC="${e}2m"
    fi
    if [ "$UNICODE" -eq 1 ]; then
        TG_TL="┌" TG_TR="┐" TG_BL="└" TG_BR="┘" TG_H="─" TG_V="│" TG_TL_T="┤" TG_TR_T="├"
        TG_THUMB="█" TG_TRACK="│" TG_ON="◀" TG_ONR="▶" TG_UPDN="↑↓" TG_LR="←→"
    else
        TG_TL="+" TG_TR="+" TG_BL="+" TG_BR="+" TG_H="-" TG_V="|" TG_TL_T="|" TG_TR_T="|"
        TG_THUMB="#" TG_TRACK=":" TG_ON="<" TG_ONR=">" TG_UPDN="Up/Dn" TG_LR="Lf/Rt"
    fi
}

# tui_fit TEXT WIDTH: REPLY is the text cut with an ellipsis, or padded with
# blanks, to exactly WIDTH columns.
tui_fit() {
    local t="$1" w="$2"
    if [ "$w" -le 0 ]; then REPLY=""; return 0; fi
    if [ "${#t}" -gt "$w" ]; then
        if [ "$w" -gt "${#SYM_ELLIPSIS}" ]; then
            t="${t:0:w-${#SYM_ELLIPSIS}}${SYM_ELLIPSIS}"
        else
            t="${t:0:w}"
        fi
    fi
    REPLY="${t}${TUI_SP:0:w-${#t}}"
}

# ---- terminal: open, close, size ---------------------------------------------
# Switches to the alternate screen (the shell screen comes back untouched),
# hides the cursor, stops the terminal echoing keys that arrive while a screen
# is drawn, unbinds Ctrl-Z and Ctrl-\ (a suspended or killed dialog would leave
# the alternate screen on and the shell prompt painted over it; the keys then
# arrive as characters the dialogs ignore) and takes over INT/TERM/HUP/WINCH.
# The old traps and the terminal state are put back by tui_close. The signal
# traps only note the signal (TUI_SIG): leaving from inside the trap would run
# while "read" is still waiting, and bash restores the terminal state it saved
# for "read" after the trap, undoing tui_close (flow control stayed off). The
# dialog loop sees the note, closes, and only then exits (see tui_dialog).
tui_open() {
    [ "$TUI_ACTIVE" -eq 0 ] || return 0
    TUI_ACTIVE=1 TUI_SIG=0
    TUI_SAVED_STTY="$(stty -g 2>/dev/null)" || TUI_SAVED_STTY=""
    TUI_SAVED_TRAPS="$(trap -p INT TERM HUP WINCH)"
    trap 'TUI_SIG=130' INT
    trap 'TUI_SIG=143' TERM
    trap 'TUI_SIG=129' HUP
    trap 'TUI_RESIZED=1' WINCH
    stty -echo -icanon -ixon 2>/dev/null || true
    stty susp undef quit undef 2>/dev/null || true     # apart: an stty without them must not undo the line above
    printf '\033[?1049h\033[?25l\033[?7l\033[2J'
    TUI_R=0 TUI_C=0
    tui_init_style
}

tui_close() {
    [ "$TUI_ACTIVE" -eq 1 ] || return 0
    TUI_ACTIVE=0
    printf '\033[0m\033[?7h\033[?25h\033[?1049l'
    if [ -n "$TUI_SAVED_STTY" ]; then stty "$TUI_SAVED_STTY" 2>/dev/null || stty sane 2>/dev/null || true; fi
    trap - INT TERM HUP WINCH
    [ -z "$TUI_SAVED_TRAPS" ] || eval "$TUI_SAVED_TRAPS"
}

# Reads the window size again; sets TUI_DIRTY when it changed or WINCH came.
tui_check_size() {
    local sz rows cols
    sz="$(stty size 2>/dev/null)" || sz=""
    rows="${sz%% *}" cols="${sz##* }"
    [[ "$rows" =~ ^[0-9]+$ ]] && [[ "$cols" =~ ^[0-9]+$ ]] || { rows=24 cols=80; }
    if [ "$rows" -eq 0 ] || [ "$cols" -eq 0 ]; then rows=24 cols=80; fi
    if [ "$rows" -ne "$TUI_R" ] || [ "$cols" -ne "$TUI_C" ] || [ "$TUI_RESIZED" -eq 1 ]; then
        TUI_R="$rows" TUI_C="$cols" TUI_RESIZED=0 TUI_DIRTY=1 TUI_CLEAR=1 TUI_WRAPPED_W=0
        printf -v TUI_SP '%*s' $(( cols + 8 )) ''
    fi
}

# ---- keys --------------------------------------------------------------------
TUI_KEY=""
TUI_PENDING=""

# Throws away what was typed before the screen appeared, so a key pressed too
# many times does not answer the next question.
tui_flush_input() {
    local junk=""
    while IFS= read -rs -n 256 -t 0.02 junk; do :; done
    : "$junk"
    TUI_PENDING=""
}

# Reads what follows an Esc. A lone Esc (nothing arrives within TUI_ESC_WAIT)
# is the Esc key; "[" or "O" start an arrow/function key, whose parts are
# awaited one by one, so a sequence that arrives split is never taken for Esc.
tui_read_escape() {
    local c seq="" n=0 final params base
    IFS= read -rsn1 -t "$TUI_ESC_WAIT" c || { TUI_KEY="esc"; return 0; }
    case "$c" in
        "[")
            while [ "$n" -lt 8 ]; do
                IFS= read -rsn1 -t "$TUI_ESC_WAIT" c || { TUI_KEY=""; return 3; }
                seq+="$c"
                n=$(( n + 1 ))
                case "$c" in [A-Za-z~]) break ;; esac
            done
            final="${seq: -1}" params="${seq%?}" base="${params%%;*}"
            case "$final" in
                A) TUI_KEY="up" ;;    B) TUI_KEY="down" ;;
                C) TUI_KEY="right" ;; D) TUI_KEY="left" ;;
                H) TUI_KEY="home" ;;  F) TUI_KEY="end" ;;
                Z) TUI_KEY="btab" ;;
                "~") case "$base" in
                        1|7) TUI_KEY="home" ;; 4|8) TUI_KEY="end" ;;
                        5) TUI_KEY="pgup" ;;  6) TUI_KEY="pgdn" ;;
                        3) TUI_KEY="del" ;;   *) TUI_KEY="" ;;
                     esac ;;
                *) TUI_KEY="" ;;
            esac
            [ -n "$TUI_KEY" ] || return 3 ;;
        "O")
            IFS= read -rsn1 -t "$TUI_ESC_WAIT" c || { TUI_KEY=""; return 3; }
            case "$c" in
                A) TUI_KEY="up" ;;    B) TUI_KEY="down" ;;
                C) TUI_KEY="right" ;; D) TUI_KEY="left" ;;
                H) TUI_KEY="home" ;;  F) TUI_KEY="end" ;;
                *) TUI_KEY=""; return 3 ;;
            esac ;;
        *) TUI_KEY="esc"; TUI_PENDING="$c" ;;     # Esc followed at once by a key
    esac
    return 0
}

# Reads one key into TUI_KEY (up down left right home end pgup pgdn enter esc
# tab btab space bksp del, or the character itself). Status: 0 a key, 1 end of
# input, 2 nothing came within the idle tick, 3 an unknown sequence.
tui_read_key() {
    local k st
    TUI_KEY=""
    if [ -n "$TUI_PENDING" ]; then
        k="$TUI_PENDING" TUI_PENDING=""
    else
        IFS= read -rsn1 -t "$TUI_TICK" k
        st=$?
        if [ "$st" -gt 128 ]; then return 2; fi
        [ "$st" -eq 0 ] || return 1
    fi
    case "$k" in
        "") TUI_KEY="enter" ;;
        $'\t') TUI_KEY="tab" ;;
        " ") TUI_KEY="space" ;;
        $'\177'|$'\b') TUI_KEY="bksp" ;;
        $'\033') tui_read_escape; return $? ;;
        *) TUI_KEY="$k" ;;
    esac
    return 0
}

# ---- drawing -----------------------------------------------------------------
TUI_BUF=""
TUI_DIRTY=1
TUI_CLEAR=1
TUI_WRAPPED_W=0
TUI_KIND="" TUI_TITLE="" TUI_BACK="" TUI_TEXT=""
TUI_NB=0 TUI_FOCUS=0 TUI_CUR=0 TUI_TOP=0 TUI_TSCROLL=0 TUI_INPUT="" TUI_IPOS=0
TUI_STATUS=255 TUI_ESC_STATUS=255 TUI_DONE=0 TUI_RESULT="" TUI_TAGW=1 TUI_HAS_SEARCH=0 TUI_CURSOR_ROW=0 TUI_CURSOR_COL=0
TUI_IW=0 TUI_IH=0 TUI_TW=0 TUI_NL=0 TUI_TH=0 TUI_LR=0 TUI_TL=0 TUI_LW=0
TUI_BTN=() TUI_TAGS=() TUI_LABELS=() TUI_STATES=() TUI_LINES=() TUI_ROW=()
TUI_DESCS=() TUI_HAS_DESC=0 TUI_LEVEL=0     # menu descriptions and how they are shown (tui_layout)
TUI_DL=() TUI_DS=() TUI_DN=() TUI_DMAX=0 TUI_DAREA=0 TUI_DESC_W=0   # the descriptions wrapped (tui_wrap_descs)
TUI_K_ENTER="" TUI_K_SPACE="" TUI_K_MOVE="" TUI_K_MARK="" TUI_K_SWITCH=""
TUI_K_SCROLL="" TUI_K_CLOSE="" TUI_K_TABS="" TUI_K_SEARCH="" TUI_K_CANCEL="" TUI_K_ALL=""

# Sets REPLY to the scroll-bar glyph of row K (0-based) of a window of ROWS
# rows over TOTAL lines seen from OFFSET: "$1"=total "$2"=rows "$3"=offset "$4"=k.
tui_sbar() {
    local total="$1" rows="$2" off="$3" k="$4" thumb pos
    if [ "$total" -le "$rows" ]; then REPLY=" "; return 0; fi
    thumb=$(( rows * rows / total ))
    [ "$thumb" -ge 1 ] || thumb=1
    pos=$(( off * (rows - thumb) / (total - rows) ))
    if [ "$k" -ge "$pos" ] && [ "$k" -lt $(( pos + thumb )) ]; then
        REPLY="${TS_THUMB}${TG_THUMB}${TS_RESET}"
    else
        REPLY="${TS_SCROLL}${TG_TRACK}${TS_RESET}"
    fi
}

# Wraps the text to the current width (only when the width changed), with
# wrap_even: no paragraph ends with one or two words alone on its last row.
tui_wrap() {
    TUI_TW=$(( TUI_IW - 4 ))
    [ "$TUI_TW" -le "$TUI_MAX_TEXT" ] || TUI_TW="$TUI_MAX_TEXT"
    [ "$TUI_TW" -ge 10 ] || TUI_TW=10
    if [ "$TUI_WRAPPED_W" -ne "$TUI_TW" ]; then
        TUI_LINES=()
        if [ -n "$TUI_TEXT" ]; then
            mapfile -t TUI_LINES < <(printf '%s\n' "$TUI_TEXT" | wrap_even "$TUI_TW")
        fi
        while [ "${#TUI_LINES[@]}" -gt 0 ] && [ -z "${TUI_LINES[${#TUI_LINES[@]}-1]//[[:space:]]/}" ]; do
            unset 'TUI_LINES[${#TUI_LINES[@]}-1]'
        done
        TUI_WRAPPED_W="$TUI_TW"
    fi
    TUI_NL="${#TUI_LINES[@]}"
}

# Wraps the description of every menu entry to the width it has under its label
# (wrap_even), once per width. TUI_DL holds the rows of all of them, TUI_DS[i]
# the index where those of entry i start, TUI_DN[i] how many they are and
# TUI_DMAX the most any entry has.
tui_wrap_descs() {
    local w=$(( TUI_LW - TUI_TAGW - 2 )) i
    local -a drows
    [ "$w" -ge 10 ] || w=10
    [ "$TUI_DESC_W" -ne "$w" ] || return 0
    TUI_DL=() TUI_DS=() TUI_DN=() TUI_DMAX=0
    for (( i = 0; i < ${#TUI_TAGS[@]}; i++ )); do
        drows=()
        [ -z "${TUI_DESCS[i]}" ] || mapfile -t drows < <(printf '%s\n' "${TUI_DESCS[i]}" | wrap_even "$w")
        TUI_DS[i]="${#TUI_DL[@]}" TUI_DN[i]="${#drows[@]}"
        TUI_DL+=("${drows[@]+"${drows[@]}"}")
        [ "${#drows[@]}" -le "$TUI_DMAX" ] || TUI_DMAX="${#drows[@]}"
    done
    TUI_DESC_W="$w"
}

# How a menu with descriptions uses the $1 rows its list has, from the roomiest
# layout to the tightest; the first one in which every entry is visible wins
# (TUI_LEVEL). The descriptions are shown whole, in as many rows as they need:
# 3 = label, description and a blank row per entry; 2 = label and description;
# 1 = labels only, and under the list the description of the current entry in
# TUI_DAREA rows (the most any has, or what is left; the last row ends in an
# ellipsis if it does not fit); 0 = labels only (a list taller than the window
# scrolls as ever).
tui_menu_level() {
    local rows="$1" n="${#TUI_TAGS[@]}" i need=0
    TUI_LEVEL=0 TUI_DAREA=0
    [ "$TUI_KIND" = "menu" ] && [ "$TUI_HAS_DESC" -eq 1 ] && [ "$n" -gt 0 ] || return 0
    tui_wrap_descs
    for (( i = 0; i < n; i++ )); do need=$(( need + 1 + TUI_DN[i] )); done
    if [ "$rows" -ge $(( need + n - 1 )) ]; then TUI_LEVEL=3
    elif [ "$rows" -ge "$need" ]; then TUI_LEVEL=2
    elif [ "$rows" -ge $(( n + 2 )) ] && [ "$TUI_DMAX" -gt 0 ]; then
        TUI_LEVEL=1
        TUI_DAREA=$(( rows - n - 1 ))
        [ "$TUI_DAREA" -le "$TUI_DMAX" ] || TUI_DAREA="$TUI_DMAX"
    fi
}

# Puts the rows of the window in place: how many rows text and list get.
tui_layout() {
    local avail tl_max gap
    TUI_IW=$(( TUI_C - 2 ))
    TUI_IH=$(( TUI_R - 4 ))
    TUI_LW=$(( TUI_IW - 3 ))
    tui_wrap
    avail=$(( TUI_IH - 4 ))                 # without the top blank and the button rows
    case "$TUI_KIND" in
        msgbox|yesno)
            TUI_TL="$TUI_NL" TUI_TH="$avail" TUI_LR=0
            [ "$TUI_TL" -le "$TUI_TH" ] || TUI_TL="$TUI_TH"
            ;;
        inputbox)
            TUI_TH=$(( avail - 2 ))
            TUI_TL="$TUI_NL"
            [ "$TUI_TL" -le "$TUI_TH" ] || TUI_TL="$TUI_TH"
            TUI_LR=0
            ;;
        *)
            tl_max=$(( avail - 4 ))
            TUI_TL="$TUI_NL"
            [ "$TUI_TL" -le "$tl_max" ] || TUI_TL="$tl_max"
            gap=0; [ "$TUI_TL" -le 0 ] || gap=1
            TUI_LR=$(( avail - TUI_TL - gap ))
            tui_menu_level "$TUI_LR"
            [ "$TUI_LR" -le "${#TUI_TAGS[@]}" ] || TUI_LR="${#TUI_TAGS[@]}"
            [ "$TUI_LR" -ge 1 ] || TUI_LR=1
            TUI_TH="$TUI_TL"
            ;;
    esac
    # Keep the scroll positions inside their range.
    local max=$(( TUI_NL - TUI_TH ))
    [ "$max" -ge 0 ] || max=0
    [ "$TUI_TSCROLL" -le "$max" ] || TUI_TSCROLL="$max"
    tui_follow_cursor
}

tui_follow_cursor() {
    local n="${#TUI_TAGS[@]}"
    [ "$n" -gt 0 ] && [ "$TUI_LR" -gt 0 ] || return 0
    [ "$TUI_CUR" -lt "$n" ] || TUI_CUR=$(( n - 1 ))
    [ "$TUI_CUR" -ge 0 ] || TUI_CUR=0
    [ "$TUI_CUR" -ge "$TUI_TOP" ] || TUI_TOP="$TUI_CUR"
    [ "$TUI_CUR" -lt $(( TUI_TOP + TUI_LR )) ] || TUI_TOP=$(( TUI_CUR - TUI_LR + 1 ))
    [ "$TUI_TOP" -le $(( n - TUI_LR )) ] || TUI_TOP=$(( n - TUI_LR ))
    [ "$TUI_TOP" -ge 0 ] || TUI_TOP=0
}

# Text rows (inner rows from 2). A scroll bar shows when the text is longer
# than its window and the dialog can scroll it (message and question).
tui_paint_text() {
    local k text sb total="$TUI_NL"
    case "$TUI_KIND" in msgbox|yesno|inputbox) ;; *) total="$TUI_TL"; TUI_TSCROLL=0 ;; esac
    for (( k = 0; k < TUI_TL; k++ )); do
        tui_fit "${TUI_LINES[$(( TUI_TSCROLL + k ))]-}" "$TUI_TW"; text="$REPLY"
        tui_sbar "$total" "$TUI_TL" "$TUI_TSCROLL" "$k"; sb="$REPLY"
        TUI_ROW[2 + k]="  ${text}${TUI_SP:0:TUI_IW-TUI_TW-3}${sb}"
    done
}

# List rows (menu and checklist): every row is green; the current one has a
# pointer in the margin always, and a solid block (black on green) while the
# list has the focus (bold, no block, when a button has it). With TUI_LEVEL 2
# or 3 the description of each menu entry hangs under its label; with 1 the one
# of the current entry hangs under the list.
tui_paint_list() {
    local first=$(( 2 + TUI_TL + (TUI_TL > 0 ? 1 : 0) ))
    local n="${#TUI_TAGS[@]}" k i j label tag mark sel row sb tagw="$TUI_TAGW" sty at ptr dw ds dc
    sel="$TS_SEL"; [ "$TUI_FOCUS" -eq -1 ] || sel="$TS_SEL_OFF"
    dw=$(( TUI_LW - tagw - 2 ))
    at="$first"
    for (( k = 0; k < TUI_LR; k++ )); do
        i=$(( TUI_TOP + k ))
        [ "$i" -lt "$n" ] || break
        label="${TUI_LABELS[$i]}"
        tui_sbar "$n" "$TUI_LR" "$TUI_TOP" "$k"; sb="$REPLY"
        ptr=" "; [ "$i" -ne "$TUI_CUR" ] || ptr="${TS_MARK}${TG_ONR}${TS_RESET}"
        if [ "$TUI_KIND" = "menu" ]; then
            tag="${TUI_TAGS[$i]}"; tag="${tag}${TUI_SP:0:tagw-${#tag}}"
            if [ "$i" -eq "$TUI_CUR" ]; then
                tui_fit "${tag}  ${label}" "$TUI_LW"
                row="${ptr}${sel}${REPLY}${TS_RESET} ${sb}"
            else
                tui_fit "$label" "$dw"
                row=" ${TS_TAG}${tag}${TS_RESET}  ${REPLY} ${sb}"
            fi
        else
            mark="$SYM_OFF"; sty=""
            [ "${TUI_STATES[$i]}" -ne 1 ] || { mark="$SYM_ON"; sty="$TS_MARK"; }
            tui_fit "$label" $(( TUI_LW - ${#SYM_ON} - 1 ))
            if [ "$i" -eq "$TUI_CUR" ]; then
                row="${ptr}${sel}${mark} ${REPLY}${TS_RESET} ${sb}"
            else
                row=" ${sty}${mark} ${REPLY}${TS_RESET} ${sb}"
            fi
        fi
        TUI_ROW[at]="$row"
        at=$(( at + 1 ))
        if [ "$TUI_LEVEL" -ge 2 ]; then
            # The description hangs under the label, dim; the current entry's is plain.
            sty="$TS_DESC"; [ "$i" -ne "$TUI_CUR" ] || sty=""
            ds="${TUI_DS[i]}"
            for (( j = 0; j < TUI_DN[i]; j++ )); do
                tui_fit "${TUI_DL[ds + j]}" "$dw"
                TUI_ROW[at]=" ${TUI_SP:0:tagw+2}${sty}${REPLY}${TS_RESET} ${sb}"
                at=$(( at + 1 ))
            done
            [ "$TUI_LEVEL" -ne 3 ] || at=$(( at + 1 ))
        fi
    done
    if [ "$TUI_LEVEL" -eq 1 ]; then
        ds="${TUI_DS[TUI_CUR]}" dc="${TUI_DN[TUI_CUR]}"
        for (( j = 0; j < TUI_DAREA; j++ )); do
            row=""
            [ "$j" -ge "$dc" ] || row="${TUI_DL[ds + j]}"
            [ "$j" -lt $(( TUI_DAREA - 1 )) ] || [ "$dc" -le "$TUI_DAREA" ] || row+="$SYM_ELLIPSIS"
            tui_fit "$row" "$dw"
            TUI_ROW[first + n + 1 + j]=" ${TUI_SP:0:tagw+2}${TS_DESC}${REPLY}${TS_RESET}  "
        done
    fi
}

# The button row, centred. All buttons are green; the focused one is a block
# (black on green) between arrows, and with the focus on the list the default
# one (the first) is a block too, without arrows, so it is clear what Enter
# does. The position in the list goes on the right.
tui_paint_buttons() {
    local i lab gap=3 total=0 start rest counter="" row="" maxlab
    local -a labs=()
    maxlab=$(( (TUI_IW - 4 - gap * (TUI_NB - 1)) / TUI_NB - 4 ))
    [ "$maxlab" -ge 3 ] || maxlab=3
    for (( i = 0; i < TUI_NB; i++ )); do
        lab="${TUI_BTN[$i]}"
        [ "${#lab}" -le "$maxlab" ] || lab="${lab:0:maxlab-${#SYM_ELLIPSIS}}${SYM_ELLIPSIS}"
        labs[i]="$lab"
        total=$(( total + ${#lab} + 4 ))
    done
    total=$(( total + gap * (TUI_NB - 1) ))
    start=$(( (TUI_IW - total) / 2 ))
    for (( i = 0; i < TUI_NB; i++ )); do
        [ "$i" -eq 0 ] || row+="${TUI_SP:0:gap}"
        if [ "$i" -eq "$TUI_FOCUS" ]; then
            row+="${TS_BTN_ON}${TG_ONR} ${labs[$i]} ${TG_ON}${TS_RESET}"
        elif [ "$TUI_FOCUS" -eq -1 ] && [ "$i" -eq 0 ]; then
            row+="${TS_BTN_ON}[ ${labs[$i]} ]${TS_RESET}"
        else
            row+="${TS_BTN}[ ${labs[$i]} ]${TS_RESET}"
        fi
    done
    rest=$(( TUI_IW - start - total ))
    if [ "${#TUI_TAGS[@]}" -gt 0 ]; then
        counter="$(( TUI_CUR + 1 ))/${#TUI_TAGS[@]}"
        if [ "$rest" -gt $(( ${#counter} + 3 )) ]; then
            row="${TUI_SP:0:start}${row}${TUI_SP:0:rest-${#counter}-2}${counter}  "
        else
            row="${TUI_SP:0:start}${row}${TUI_SP:0:rest}"
        fi
    else
        row="${TUI_SP:0:start}${row}${TUI_SP:0:rest}"
    fi
    TUI_ROW[TUI_IH-1]="$row"
}

# The line of an input box: shows the tail of the text when it is longer.
tui_paint_input() {
    local row=$(( 2 + TUI_TL + 1 )) fw view off sty
    fw=$(( TUI_TW < 60 ? TUI_TW : 60 ))
    off=0
    [ "$TUI_IPOS" -lt "$fw" ] || off=$(( TUI_IPOS - fw + 1 ))
    view="${TUI_INPUT:off:fw}"
    tui_fit "$view" "$fw"
    sty="$TS_BTN"; [ "$TUI_FOCUS" -ne -1 ] || sty="$TS_SEL"
    TUI_ROW[row]="  ${sty}${REPLY}${TS_RESET}${TUI_SP:0:TUI_IW-fw-2}"
    TUI_CURSOR_ROW=$(( row + 2 )) TUI_CURSOR_COL=$(( 4 + TUI_IPOS - off ))
}

# Last row: the keys that work now, each as "key + what it does". When they
# do not fit the least important ones are dropped first.
tui_paint_keybar() {
    local -a keys=() labs=() prio=()
    local i n total worst enter_label hk st lab out k
    if [ "$TUI_KIND" = "msgbox" ] || [ "$TUI_FOCUS" -lt 0 ]; then enter_label="${TUI_BTN[0]}"; else enter_label="${TUI_BTN[$TUI_FOCUS]}"; fi
    keys+=("$TUI_K_ENTER"); labs+=("$enter_label"); prio+=(1)
    if [ "$TUI_ESC_STATUS" -ne 255 ]; then
        keys+=("Esc"); labs+=("${TUI_BTN[$TUI_ESC_STATUS]}"); prio+=(2)
    elif [ "$TUI_KIND" = "msgbox" ]; then
        keys+=("Esc"); labs+=("$TUI_K_CLOSE"); prio+=(2)
    else
        keys+=("Esc"); labs+=("$TUI_K_CANCEL"); prio+=(2)
    fi
    case "$TUI_KIND" in
        msgbox|yesno)
            if [ "$TUI_NL" -gt "$TUI_TH" ]; then keys+=("$TG_UPDN"); labs+=("$TUI_K_SCROLL"); prio+=(3); fi
            if [ "$TUI_NB" -gt 1 ]; then keys+=("$TG_LR"); labs+=("$TUI_K_SWITCH"); prio+=(4); fi
            for hk in $TUI_HOTKEYS; do
                [ "${hk%%=*}" != "esc" ] || continue
                st="${hk#*=}"; lab="${TUI_BTN[$st]-}"
                [ -z "$lab" ] || { keys+=("${hk%%=*}"); labs+=("$lab"); prio+=(2); }
            done ;;
        menu|checklist)
            keys+=("$TG_UPDN"); labs+=("$TUI_K_MOVE"); prio+=(4)
            if [ "$TUI_KIND" = "checklist" ]; then
                keys+=("$TUI_K_SPACE"); labs+=("$TUI_K_MARK"); prio+=(2)
                keys+=("A/N"); labs+=("$TUI_K_ALL"); prio+=(3)
            fi
            [ "$TUI_HAS_SEARCH" -eq 0 ] || { keys+=("/"); labs+=("$TUI_K_SEARCH"); prio+=(5); }
            keys+=("Tab"); labs+=("$TUI_K_TABS"); prio+=(6) ;;
    esac
    while true; do
        n="${#keys[@]}" total=0
        for (( i = 0; i < n; i++ )); do total=$(( total + ${#keys[i]} + ${#labs[i]} + 5 )); done
        [ "$total" -le $(( TUI_C - 1 )) ] && break
        [ "$n" -gt 1 ] || break
        worst=0
        for (( i = 1; i < n; i++ )); do [ "${prio[i]}" -le "${prio[worst]}" ] || worst="$i"; done
        unset 'keys[worst]' 'labs[worst]' 'prio[worst]'
        keys=("${keys[@]}") labs=("${labs[@]}") prio=("${prio[@]}")
    done
    out=" "
    for (( i = 0; i < ${#keys[@]}; i++ )); do
        k="${keys[i]}"; [ "${#k}" -ne 1 ] || k="${k^^}"
        out+="${TS_CHIP} ${k} ${TS_RESET} ${labs[i]}  "
    done
    k=0
    for (( i = 0; i < ${#keys[@]}; i++ )); do k=$(( k + ${#keys[i]} + ${#labs[i]} + 5 )); done
    TUI_BUF+=$'\033['"${TUI_R};1H${TS_RESET}${out}${TUI_SP:0:TUI_C-k-1}"
}

# One screen: top bar, frame with its title, the body rows and the key bar.
tui_render() {
    local r title seg w left right
    TUI_BUF=""
    [ "$TUI_CLEAR" -eq 0 ] || { TUI_BUF=$'\033[2J'; TUI_CLEAR=0; }
    if [ "$TUI_R" -lt "$TUI_MIN_ROWS" ] || [ "$TUI_C" -lt "$TUI_MIN_COLS" ]; then
        local small
        msgf_v small tui_small "${TUI_C}x${TUI_R}" "${TUI_MIN_COLS}x${TUI_MIN_ROWS}"
        small="$(printf '%s\n' "$small" | wrap_text $(( TUI_C > 12 ? TUI_C - 2 : 10 )))"
        TUI_BUF+=$'\033[2J\033[1;1H'"${TS_WARN}${small//$'\n'/$'\033[K\r\n'}${TS_RESET}"
        printf '%s' "$TUI_BUF"
        return 0
    fi
    tui_layout
    for (( r = 1; r <= TUI_IH; r++ )); do TUI_ROW[r]="${TUI_SP:0:TUI_IW}"; done
    TUI_CURSOR_ROW=0 TUI_CURSOR_COL=0
    tui_paint_text
    [ "${#TUI_TAGS[@]}" -eq 0 ] || tui_paint_list
    [ "$TUI_KIND" != "inputbox" ] || tui_paint_input
    tui_paint_buttons
    # top bar
    tui_fit " ${TUI_BACK}" "$TUI_C"
    TUI_BUF+=$'\033[1;1H'"${TS_BAR}${REPLY}${TS_RESET}"
    # frame: top border with the centred title
    title="${TUI_TITLE:0:TUI_IW-8}"
    if [ -n "$title" ]; then
        seg="${TG_TL_T} ${title} ${TG_TR_T}"
        w=$(( ${#title} + 4 ))
        left=$(( (TUI_IW - w) / 2 )) right=$(( TUI_IW - w - left ))
        printf -v seg '%s' "${TS_BORDER}${TG_TL}$(tui_hr "$left")${TS_RESET}${TS_BORDER}${TG_TL_T}${TS_RESET}${TS_TITLE} ${title} ${TS_RESET}${TS_BORDER}${TG_TR_T}$(tui_hr "$right")${TG_TR}${TS_RESET}"
    else
        seg="${TS_BORDER}${TG_TL}$(tui_hr "$TUI_IW")${TG_TR}${TS_RESET}"
    fi
    TUI_BUF+=$'\033[2;1H'"$seg"
    for (( r = 1; r <= TUI_IH; r++ )); do
        TUI_BUF+=$'\033['"$(( r + 2 ));1H${TS_BORDER}${TG_V}${TS_RESET}${TUI_ROW[r]}${TS_BORDER}${TG_V}${TS_RESET}"
    done
    TUI_BUF+=$'\033['"$(( TUI_R - 1 ));1H${TS_BORDER}${TG_BL}$(tui_hr "$TUI_IW")${TG_BR}${TS_RESET}"
    tui_paint_keybar
    if [ "$TUI_CURSOR_ROW" -gt 0 ]; then
        TUI_BUF+=$'\033['"${TUI_CURSOR_ROW};${TUI_CURSOR_COL}H"$'\033[?25h'
    else
        TUI_BUF+=$'\033[?25l'
    fi
    printf '%s' "$TUI_BUF"
}

# A run of N frame-line glyphs.
tui_hr() {
    local n="$1" out=""
    [ "$n" -gt 0 ] || return 0
    if [ "$UNICODE" -eq 1 ]; then
        printf -v out '%*s' "$n" ''
        printf '%s' "${out// /$TG_H}"
    else
        printf -v out '%*s' "$n" ''
        printf '%s' "${out// /-}"
    fi
}

# ---- keys of each dialog -------------------------------------------------------
tui_finish() {
    TUI_STATUS="$1" TUI_DONE=1
}

# Puts the answer of the dialog in TUI_RESULT (what whiptail prints on stderr).
tui_collect() {
    local i out=""
    case "$TUI_KIND" in
        menu) TUI_RESULT="${TUI_TAGS[$TUI_CUR]-}" ;;
        checklist)
            for (( i = 0; i < ${#TUI_TAGS[@]}; i++ )); do
                [ "${TUI_STATES[i]}" -ne 1 ] || out+="${out:+ }\"${TUI_TAGS[i]}\""
            done
            TUI_RESULT="$out" ;;
        inputbox) TUI_RESULT="$TUI_INPUT" ;;
        *) TUI_RESULT="" ;;
    esac
}

# Enter on the focused button; with the focus on the list it is the first one.
tui_activate() {
    local b="$TUI_FOCUS"
    [ "$b" -ge 0 ] || b=0
    [ "$TUI_KIND" != "msgbox" ] || b=0
    [ "$b" -ne 0 ] || tui_collect
    tui_finish "$b"
}

tui_scroll_text() {
    local max=$(( TUI_NL - TUI_TH )) page=$(( TUI_TH - 1 ))
    [ "$max" -ge 0 ] || max=0
    [ "$page" -ge 1 ] || page=1
    case "$1" in
        up) TUI_TSCROLL=$(( TUI_TSCROLL - 1 )) ;;
        down) TUI_TSCROLL=$(( TUI_TSCROLL + 1 )) ;;
        pgup) TUI_TSCROLL=$(( TUI_TSCROLL - page )) ;;
        pgdn) TUI_TSCROLL=$(( TUI_TSCROLL + page )) ;;
        home) TUI_TSCROLL=0 ;;
        end) TUI_TSCROLL="$max" ;;
    esac
    [ "$TUI_TSCROLL" -ge 0 ] || TUI_TSCROLL=0
    [ "$TUI_TSCROLL" -le "$max" ] || TUI_TSCROLL="$max"
}

tui_move_list() {
    local n="${#TUI_TAGS[@]}" page=$(( TUI_LR - 1 ))
    [ "$n" -gt 0 ] || return 0
    [ "$page" -ge 1 ] || page=1
    case "$1" in
        up) TUI_CUR=$(( TUI_CUR - 1 )) ;;
        down) TUI_CUR=$(( TUI_CUR + 1 )) ;;
        pgup) TUI_CUR=$(( TUI_CUR - page )) ;;
        pgdn) TUI_CUR=$(( TUI_CUR + page )) ;;
        home) TUI_CUR=0 ;;
        end) TUI_CUR=$(( n - 1 )) ;;
    esac
    [ "$TUI_CUR" -ge 0 ] || TUI_CUR=0
    [ "$TUI_CUR" -lt "$n" ] || TUI_CUR=$(( n - 1 ))
    tui_follow_cursor
}

# A / N: marks ($1 = 1) or unmarks ($1 = 0) every entry of the list but the
# search row. The list is already what the search left visible.
tui_mark_all() {
    local i
    for (( i = 0; i < ${#TUI_TAGS[@]}; i++ )); do
        if [ "$TUI_HAS_SEARCH" -eq 1 ] && [ "${TUI_TAGS[i]}" = "S" ]; then continue; fi
        TUI_STATES[i]="$1"
    done
}

# Moves the focus among the buttons (0..NB-1) and the list (-1); $1 = step.
tui_focus_step() {
    local f="$TUI_FOCUS" lo=0
    [ "${#TUI_TAGS[@]}" -eq 0 ] && [ "$TUI_KIND" != "inputbox" ] || lo=-1
    f=$(( f + $1 ))
    [ "$f" -le $(( TUI_NB - 1 )) ] || f="$lo"
    [ "$f" -ge "$lo" ] || f=$(( TUI_NB - 1 ))
    TUI_FOCUS="$f"
}

tui_keys_buttons() {
    case "$TUI_KEY" in
        enter|space) tui_activate ;;
        left|btab) [ "$TUI_FOCUS" -le 0 ] || TUI_FOCUS=$(( TUI_FOCUS - 1 )) ;;
        right) [ "$TUI_FOCUS" -ge $(( TUI_NB - 1 )) ] || TUI_FOCUS=$(( TUI_FOCUS + 1 )) ;;
        tab) TUI_FOCUS=$(( (TUI_FOCUS + 1) % TUI_NB )) ;;
        up|down|pgup|pgdn|home|end) tui_scroll_text "$TUI_KEY" ;;
        q|Q) tui_finish "$TUI_ESC_STATUS" ;;      # q is Esc
    esac
}

# The keys of the list work wherever the focus is, so TAB is never needed: an
# arrow, Space, A or N from a button give the focus back to the list. Space acts
# on the list: it marks the entry (checklist) or accepts it (menu). Enter is the
# one that presses the focused button, as the key bar says.
tui_keys_list() {
    local i lk="${TUI_KEY,,}"
    case "$TUI_KEY" in
        up|down|home|end|pgup|pgdn)
            TUI_FOCUS=-1
            tui_move_list "$TUI_KEY" ;;
        tab) tui_focus_step 1 ;;
        btab) tui_focus_step -1 ;;
        left) [ "$TUI_FOCUS" -le 0 ] || TUI_FOCUS=$(( TUI_FOCUS - 1 )) ;;
        right) [ "$TUI_FOCUS" -lt 0 ] || [ "$TUI_FOCUS" -ge $(( TUI_NB - 1 )) ] || TUI_FOCUS=$(( TUI_FOCUS + 1 )) ;;
        enter) tui_activate ;;
        space)
            if [ "${#TUI_TAGS[@]}" -gt 0 ]; then
                TUI_FOCUS=-1
                if [ "$TUI_KIND" = "menu" ]; then
                    tui_activate
                else
                    TUI_STATES[TUI_CUR]=$(( 1 - TUI_STATES[TUI_CUR] ))
                fi
            fi ;;
        q|Q) tui_finish "$TUI_ESC_STATUS" ;;      # q is Esc
        "/")
            if [ "$TUI_HAS_SEARCH" -eq 1 ]; then
                for (( i = 0; i < ${#TUI_TAGS[@]}; i++ )); do
                    [ "${TUI_TAGS[i]}" != "S" ] || { TUI_STATES[i]=1; TUI_FOCUS=-1; tui_activate; break; }
                done
            fi ;;
        *)
            if [ "$TUI_KIND" = "checklist" ]; then
                case "$lk" in
                    a) TUI_FOCUS=-1; tui_mark_all 1 ;;
                    n) TUI_FOCUS=-1; tui_mark_all 0 ;;
                esac
            elif [ "${#TUI_KEY}" -eq 1 ]; then
                # The tag of a menu entry is its shortcut: 1, 2, L, 0 ...
                for (( i = 0; i < ${#TUI_TAGS[@]}; i++ )); do
                    if [ "${TUI_TAGS[i],,}" = "$lk" ]; then
                        TUI_CUR="$i" TUI_FOCUS=-1
                        tui_follow_cursor
                        tui_activate
                        break
                    fi
                done
            fi ;;
    esac
}

tui_keys_input() {
    local len="${#TUI_INPUT}"
    case "$TUI_KEY" in
        enter) tui_activate ;;
        tab) tui_focus_step 1 ;;
        btab) tui_focus_step -1 ;;
        left)  if [ "$TUI_FOCUS" -eq -1 ]; then [ "$TUI_IPOS" -le 0 ] || TUI_IPOS=$(( TUI_IPOS - 1 )); elif [ "$TUI_FOCUS" -gt 0 ]; then TUI_FOCUS=$(( TUI_FOCUS - 1 )); fi ;;
        right) if [ "$TUI_FOCUS" -eq -1 ]; then [ "$TUI_IPOS" -ge "$len" ] || TUI_IPOS=$(( TUI_IPOS + 1 )); elif [ "$TUI_FOCUS" -lt $(( TUI_NB - 1 )) ]; then TUI_FOCUS=$(( TUI_FOCUS + 1 )); fi ;;
        home) TUI_IPOS=0 ;;
        end) TUI_IPOS="$len" ;;
        bksp) if [ "$TUI_IPOS" -gt 0 ]; then TUI_INPUT="${TUI_INPUT:0:TUI_IPOS-1}${TUI_INPUT:TUI_IPOS}"; TUI_IPOS=$(( TUI_IPOS - 1 )); fi ;;
        del) TUI_INPUT="${TUI_INPUT:0:TUI_IPOS}${TUI_INPUT:TUI_IPOS+1}" ;;
        space) TUI_KEY=" "; tui_input_add ;;
        up|down|pgup|pgdn) ;;
        *) tui_input_add ;;
    esac
}

# Adds the key as text: one printable character, no control codes.
tui_input_add() {
    [ "${#TUI_KEY}" -eq 1 ] || return 0
    [[ "$TUI_KEY" != [[:cntrl:]] ]] || return 0
    [ "${#TUI_INPUT}" -lt 200 ] || return 0
    TUI_INPUT="${TUI_INPUT:0:TUI_IPOS}${TUI_KEY}${TUI_INPUT:TUI_IPOS}"
    TUI_IPOS=$(( TUI_IPOS + 1 ))
}

tui_handle_key() {
    local hk lk="${TUI_KEY,,}"
    if [ -n "$TUI_HOTKEYS" ] && [ "${#TUI_KEY}" -eq 1 ] && [ "$TUI_KIND" != "inputbox" ]; then
        for hk in $TUI_HOTKEYS; do
            [ "${hk%%=*}" != "$lk" ] || { tui_finish "${hk#*=}"; return 0; }
        done
    fi
    if [ "$TUI_KEY" = "esc" ]; then tui_finish "$TUI_ESC_STATUS"; return 0; fi
    case "$TUI_KIND" in
        msgbox|yesno) tui_keys_buttons ;;
        menu|checklist) tui_keys_list ;;
        inputbox) tui_keys_input ;;
    esac
    TUI_DIRTY=1
}

# ---- the dialog ---------------------------------------------------------------
# Same arguments as whiptail (geometry is accepted and ignored: the dialog
# fills the window). The answer goes to stderr like whiptail's; the status is
# 0 (accept / yes), 1 (cancel / no) or 255 (Esc, or the input ended).
tui_dialog() {
    local ok_label="" cancel_label="" yes_label="" no_label="" default_item="" defno=0 i rk n tagw=0 hk
    TUI_KIND="" TUI_TITLE="" TUI_BACK="" TUI_TEXT="" TUI_INPUT="" TUI_IPOS=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --title) TUI_TITLE="$2"; shift 2 ;;
            --backtitle) TUI_BACK="$2"; shift 2 ;;
            --ok-button) ok_label="$2"; shift 2 ;;
            --cancel-button) cancel_label="$2"; shift 2 ;;
            --yes-button) yes_label="$2"; shift 2 ;;
            --no-button) no_label="$2"; shift 2 ;;
            --default-item) default_item="$2"; shift 2 ;;
            --defaultno) defno=1; shift ;;
            --msgbox|--yesno|--inputbox|--menu|--checklist)
                TUI_KIND="${1#--}" TUI_TEXT="${2//\\n/$'\n'}"
                shift 2
                break ;;
            *) shift ;;
        esac
    done
    [ "${1:-}" != "--" ] || shift
    shift 2 2>/dev/null || shift "$#"            # height and width
    TUI_TAGS=() TUI_LABELS=() TUI_STATES=() TUI_BTN=() TUI_DESCS=() TUI_HAS_DESC=0 TUI_LEVEL=0 TUI_DESC_W=0
    case "$TUI_KIND" in
        msgbox) TUI_BTN=("${ok_label:-OK}") TUI_FOCUS=0 ;;
        yesno)
            TUI_BTN=("${yes_label:-Yes}" "${no_label:-No}") TUI_FOCUS=0
            [ "$defno" -eq 0 ] || TUI_FOCUS=1 ;;
        inputbox)
            TUI_BTN=("${ok_label:-OK}" "${cancel_label:-Cancel}") TUI_FOCUS=-1
            TUI_INPUT="${1:-}" TUI_IPOS="${#1}" ;;
        menu|checklist)
            TUI_BTN=("${ok_label:-OK}" "${cancel_label:-Cancel}") TUI_FOCUS=-1
            shift 1                                # rows of the list
            while [ "$#" -ge 2 ]; do
                TUI_TAGS+=("$1")
                if [ "$TUI_KIND" = "menu" ] && [[ "$2" == *$'\037'* ]]; then
                    # "label<US>description": a menu entry with a description (menu_item_text)
                    TUI_LABELS+=("${2%%$'\037'*}") TUI_DESCS+=("${2#*$'\037'}") TUI_HAS_DESC=1
                else
                    TUI_LABELS+=("$2") TUI_DESCS+=("")
                fi
                if [ "$TUI_KIND" = "checklist" ]; then
                    case "${3:-OFF}" in [Oo][Nn]) TUI_STATES+=(1) ;; *) TUI_STATES+=(0) ;; esac
                    shift 3
                else
                    TUI_STATES+=(0); shift 2
                fi
            done ;;
        *) return 1 ;;
    esac
    TUI_NB="${#TUI_BTN[@]}" TUI_CUR=0 TUI_TOP=0 TUI_TSCROLL=0 TUI_HAS_SEARCH=0
    for (( i = 0; i < ${#TUI_TAGS[@]}; i++ )); do
        [ "${#TUI_TAGS[i]}" -le "$tagw" ] || tagw="${#TUI_TAGS[i]}"
        [ -z "$default_item" ] || [ "${TUI_TAGS[i]}" != "$default_item" ] || TUI_CUR="$i"
        [ "$TUI_KIND" != "checklist" ] || [ "${TUI_TAGS[i]}" != "S" ] || TUI_HAS_SEARCH=1
    done
    TUI_TAGW="$tagw"
    TUI_K_ENTER="$(msg kb_enter)" TUI_K_SPACE="$(msg kb_space)" TUI_K_MOVE="$(msg kb_move)"
    TUI_K_MARK="$(msg kb_mark)" TUI_K_SWITCH="$(msg kb_switch)" TUI_K_SCROLL="$(msg kb_scroll)"
    TUI_K_CLOSE="$(msg kb_close)" TUI_K_TABS="$(msg kb_buttons)" TUI_K_SEARCH="$(msg search_button)"
    TUI_K_CANCEL="$(msg cancel)" TUI_K_ALL="$(msg kb_all)"
    TUI_STATUS=255 TUI_ESC_STATUS=255 TUI_DONE=0 TUI_RESULT="" TUI_DIRTY=1 TUI_CLEAR=1 TUI_WRAPPED_W=0 TUI_RESIZED=0
    for hk in $TUI_HOTKEYS; do [ "${hk%%=*}" != "esc" ] || TUI_ESC_STATUS="${hk#*=}"; done
    tui_open
    tui_flush_input
    while [ "$TUI_DONE" -eq 0 ] && [ "$TUI_SIG" -eq 0 ]; do
        tui_check_size
        if [ "$TUI_DIRTY" -eq 1 ]; then TUI_DIRTY=0; tui_render; fi
        tui_read_key
        rk=$?
        case "$rk" in
            0) tui_handle_key ;;
            1) tui_finish 255 ;;
        esac
    done
    tui_close
    if [ "$TUI_SIG" -ne 0 ]; then TUI_HOTKEYS=""; exit "$TUI_SIG"; fi
    n="$TUI_STATUS"
    if [ "$n" -eq 0 ]; then
        case "$TUI_KIND" in menu|checklist|inputbox) printf '%s' "$TUI_RESULT" >&2 ;; esac
    fi
    TUI_HOTKEYS=""
    return "$n"
}

# ----------------------------------------------------------------------------
# Graphical dialogs ("gui"): zenity, with the same contract as tui_dialog (menu,
# checklist, yesno, msgbox, inputbox; the answer goes to stderr) plus --choice.
# What differs, because it is what zenity does:
#   - Esc, Cancel and the window's close button all end with status 1 and no
#     output: they cannot be told apart, and gui_dialog never returns 255.
#   - A yesno that is a choice between two actions (--choice) has two buttons
#     and no "no": the second prints its label and ends with status 1, and
#     closing the window counts as the first (status 0), so a stray Esc cannot
#     pick the second action.
#   - A text taller than GUI_TEXT_LINES (--scrolltext) goes to a window with a
#     scroll bar (--text-info), which always has a Cancel button of its own.
#   - Status 254 means zenity could not run (no display, invalid option, not
#     found): a closed window is never mistaken for a broken zenity.
#   - Sizes are in pixels and chosen here; the height and width the callers
#     give for whiptail are ignored, as in tui_dialog.
#   - A menu list shows four columns: the key of the entry (its tag: 1, 2, T, 0),
#     an emoji, the label and the description. The emoji come in the text of the
#     entry, before the label and a record separator (menu_item_text), and only
#     when the system draws them in color (gui_emoji); without them the list has
#     three columns. Typing in the list searches it (zenity's own bar), so the
#     key is not a shortcut.
#   - Every window starts through gui_cmd, which gives it the class of the
#     program. A message and a question carry the program's icon, the question
#     that destroys something (defaultno) the warning icon of the theme, and
#     an error the icon of the theme, but only when zenity has --icon (gui_opt).
# ----------------------------------------------------------------------------
GUI_W_MIN=320           # narrowest message (zenity adds 138 px of icon and margins to it)
GUI_W_MAX=560           # widest message
GUI_W_ENTRY=420         # narrowest text entry
GUI_W_PROGRESS=440      # narrowest progress window (its lines are cut at 64 characters)
GUI_W_LIST=520          # narrowest list
GUI_W_BIG=820           # width of a long text and widest list
GUI_H_LIST_MIN=280      # shortest list
GUI_H_LIST=560          # height of a long text and tallest list
GUI_ROW_PX=35           # height of a menu row
GUI_ROW_CHECK_PX=41     # height of a row with a check box
GUI_LIST_PAD=216        # what a list needs besides its rows: title, a line of text, header strip, buttons
GUI_LINE_PX=19          # each further line of the text above a list
GUI_CHAR_PX2=13         # twice the width in pixels of an average character (6.5)
GUI_COL_PX=30           # width of a narrow column of a menu list: the key, the icon
GUI_WRAP_COLS=72        # columns a message is counted at (zenity wraps it itself)
GUI_TEXT_LINES=14       # lines of text that still fit a message window
GUI_CLASS="mintapp-remover"     # class of every window; a launcher (.desktop) must carry it too
GUI_ICON=""             # the program's icon file; "-" = there is none; set by gui_find_icon
ICON_ASSET="icon5.png"  # the file in ../assets the embedded icon was made from (the fallback)
ICON_FILE=""            # the embedded icon once written (inside GUI_WORK_DIR), see program_icon

# The program's icon for a window, in REPLY: a file, because for a name the icon
# theme lacks zenity draws a broken icon, so it is given a file that exists,
# never a name of ours. It is the embedded icon, written when the windows start
# (gui_icon_prepare), else ../assets/icon5.png beside the script (a link to the
# script is followed). Status 0 only when zenity has --icon and there is a file.
# It only reads what is ready: it may run in a subshell, which would lose a
# folder it made, so it makes none.
gui_find_icon() {
    if [ -n "$GUI_ICON" ] && [ "$GUI_ICON" != "-" ] && [ ! -f "$GUI_ICON" ]; then
        GUI_ICON=""     # gone since: gui_cleanup removes the folder it was in
    fi
    if [ -z "$GUI_ICON" ]; then
        GUI_ICON="-"
        if gui_opt --icon; then
            if [ -n "$ICON_FILE" ] && [ -f "$ICON_FILE" ]; then
                GUI_ICON="$ICON_FILE"
            elif program_icon_asset; then
                GUI_ICON="$REPLY"
            fi
        fi
    fi
    REPLY="$GUI_ICON"
    [ "$GUI_ICON" != "-" ]
}

# Writes the embedded icon for the windows (program_icon), once and in the main
# shell: ICON_FILE then reaches every subshell that opens a window. The folder it
# goes in is removed by gui_cleanup, which on_exit runs, so this is called once
# the traps are in place (main) and when the windows start in the middle of a run
# (switch_to_gui). It always succeeds: with no icon the windows go without.
gui_icon_prepare() {
    gui_opt --icon || return 0
    program_icon || true
    GUI_ICON=""
    return 0
}

# zenity ARGS... under the locale it needs (GUI_LOCALE) and with GUI_CLASS as its
# name: that name is the class of its windows (WM_CLASS), by which a taskbar
# finds the program's icon. No zenity version has an option for it; "exec -a"
# works with all. exec replaces the process that runs it, so on the program's
# own shell this makes a subshell first; in $( ), a pipe or "&" it is one already.
gui_cmd() {
    if [ "$BASHPID" = "$$" ]; then
        ( gui_cmd "$@" )
        return
    fi
    [ -z "$GUI_LOCALE" ] || export LC_ALL="$GUI_LOCALE"
    exec -a "$GUI_CLASS" zenity "$@"
}

# REPLY = how many characters the longest line of $1 has.
gui_longest_line() {
    local line max=0
    while IFS= read -r line || [ -n "$line" ]; do
        [ "${#line}" -le "$max" ] || max="${#line}"
    done <<< "$1"
    REPLY="$max"
}

# REPLY = the width in pixels of a window for the text $1: what its longest line
# needs (an average character takes GUI_CHAR_PX2 / 2 px, plus 24 of margin),
# between $2 (GUI_W_MIN if none) and GUI_W_MAX. A longer line wraps. A window
# wider than its text leaves it floating far from the icon.
gui_text_width() {
    local w min="${2:-$GUI_W_MIN}"
    gui_longest_line "$1"
    w=$(( REPLY * GUI_CHAR_PX2 / 2 + 24 ))
    [ "$w" -ge "$min" ] || w="$min"
    [ "$w" -le "$GUI_W_MAX" ] || w="$GUI_W_MAX"
    REPLY="$w"
}

# REPLY = "WIDTH HEIGHT" in pixels of a list of ROWS ($2) rows of ROWPX ($4) pixels
# whose columns take COLS ($3) characters together, plus EXTRA ($5, none by default)
# pixels for the narrow ones (the key, the icon), under the text $1: wide enough for
# them (a longer cell is cut, not wrapped) and tall enough for all its rows, so that
# nothing is left empty at the bottom; a list that does not fit in GUI_H_LIST
# scrolls. The text above it takes a line more for each time it wraps.
gui_list_size() {
    local text="$1" rows="$2" cols="$3" rowpx="$4" extra="${5:-0}" w h room line n tl=0
    w=$(( cols * GUI_CHAR_PX2 / 2 + 100 + extra ))
    [ "$w" -ge "$GUI_W_LIST" ] || w="$GUI_W_LIST"
    [ "$w" -le "$GUI_W_BIG" ] || w="$GUI_W_BIG"
    room=$(( (w - 40) * 2 / GUI_CHAR_PX2 ))
    while IFS= read -r line || [ -n "$line" ]; do
        n=$(( (${#line} + room - 1) / room ))
        tl=$(( tl + (n > 1 ? n : 1) ))
    done <<< "$text"
    h=$(( rows * rowpx + GUI_LIST_PAD + (tl - 1) * GUI_LINE_PX + 10 ))
    [ "$h" -ge "$GUI_H_LIST_MIN" ] || h="$GUI_H_LIST_MIN"
    [ "$h" -le "$GUI_H_LIST" ] || h="$GUI_H_LIST"
    REPLY="$w $h"
}

# A cell of a list that starts with "-" would be read as an option, and "--"
# does not end the options in zenity: it gets a space in front. Puts it in REPLY.
gui_arg() {
    REPLY="$1"
    case "$1" in -*) REPLY=" $1" ;; esac
}

# The text of a list or an entry, ready for zenity: it reads "\n" and "\\" in
# both, Pango markup in a list (an "&" left alone makes it drop the whole text)
# and "_" as a mnemonic mark in an entry. $1 = text, $2 = list | entry.
gui_escape() {
    local t="$1"
    t="${t//\\/\\\\}"
    if [ "$2" = "list" ]; then
        t="${t//&/&amp;}" t="${t//</&lt;}" t="${t//>/&gt;}"
    else
        t="${t//_/__}"
    fi
    REPLY="$t"
}

# REPLY = the text $1 above a list, in Pango markup: its first line is the title
# (bold) and the rest the hint (dimmed, whatever the theme). Each line is
# escaped, so a name with "<" or "&" shows as it is.
gui_list_text() {
    local line out="" first=1
    while IFS= read -r line || [ -n "$line" ]; do
        gui_escape "$line" list
        if [ "$first" -eq 1 ]; then
            out="<b>$REPLY</b>" first=0
        else
            out+=$'\n'"<span alpha=\"60%\">$REPLY</span>"
        fi
    done <<< "$1"
    REPLY="$out"
}

# Whether the windows can draw emoji in color: the program is in Unicode (not
# MINTAPP_ASCII=1, not a locale without UTF-8) and fontconfig has a color emoji
# font with U+1F9FC, the newest emoji of the menus (Unicode 11). Without the
# color filter a bitmap font that has the glyph (Unifont) matches too and draws
# it as a black and white block. Asked once: GUI_EMOJI is -1 until then, then 0
# or 1.
GUI_EMOJI=-1
gui_emoji() {
    if [ "$GUI_EMOJI" -lt 0 ]; then
        GUI_EMOJI=0
        if [ "$UNICODE" -eq 1 ] && command -v fc-list >/dev/null 2>&1 \
            && [ -n "$(fc-list ':charset=1f9fc:color=True' family 2>/dev/null)" ]; then
            GUI_EMOJI=1
        fi
    fi
    [ "$GUI_EMOJI" -eq 1 ]
}

gui_dialog() {
    local title="" kind="" text="" ok_label="" cancel_label="" yes_label="" no_label=""
    local defno=0 choice=0 scroll=0 initial="" i tag first second item extra
    local has_desc=0 has_icon=0 out="" err rc status broken=0 stdin_text=0 icon="" width size lmax dmax
    local -a tags=() labels=() descs=() icons=() states=() args=() parts=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --title) title="$2"; shift 2 ;;
            --ok-button) ok_label="$2"; shift 2 ;;
            --cancel-button) cancel_label="$2"; shift 2 ;;
            --yes-button) yes_label="$2"; shift 2 ;;
            --no-button) no_label="$2"; shift 2 ;;
            --backtitle|--default-item) shift 2 ;;
            --defaultno) defno=1; shift ;;
            --choice) choice=1; shift ;;
            --scrolltext) scroll=1; shift ;;
            --msgbox|--yesno|--inputbox|--menu|--checklist)
                kind="${1#--}" text="${2//\\n/$'\n'}"
                shift 2
                break ;;
            *) shift ;;
        esac
    done
    [ "${1:-}" != "--" ] || shift
    shift 2 2>/dev/null || shift "$#"            # height and width
    case "$kind" in
        inputbox) initial="${1:-}" ;;
        menu|checklist)
            shift 1                                # rows of the list
            while [ "$#" -ge 2 ]; do
                tags+=("$1")
                item="$2"
                if [ "$kind" = "menu" ] && [[ "$item" == *$'\036'* ]]; then
                    icons+=("${item%%$'\036'*}") item="${item#*$'\036'}" has_icon=1
                else
                    icons+=("")
                fi
                if [ "$kind" = "menu" ] && [[ "$item" == *$'\037'* ]]; then
                    labels+=("${item%%$'\037'*}") descs+=("${item#*$'\037'}") has_desc=1
                else
                    labels+=("$item") descs+=("")
                fi
                if [ "$kind" = "checklist" ]; then
                    case "${3:-OFF}" in [Oo][Nn]) states+=(TRUE) ;; *) states+=(FALSE) ;; esac
                    shift 3
                else
                    shift 2
                fi
            done ;;
        msgbox|yesno) ;;
        *) return 1 ;;
    esac

    first="${yes_label:-Yes}" second="${no_label:-No}"
    args=(--title="$title")
    case "$kind" in
        msgbox)
            if [ "$scroll" -eq 1 ]; then
                args+=(--text-info --width="$GUI_W_BIG" --height="$GUI_H_LIST"
                       --ok-label="${ok_label:-OK}" --cancel-label="$(msg kb_close)")
                stdin_text=1
            else
                gui_text_width "$text"
                args+=(--info --no-markup --width="$REPLY" --text="$text" --ok-label="${ok_label:-OK}")
                ! gui_find_icon || icon="$REPLY"
            fi ;;
        yesno)
            if [ "$scroll" -eq 1 ]; then
                args+=(--text-info --width="$GUI_W_BIG" --height="$GUI_H_LIST")
                stdin_text=1
                if [ "$choice" -eq 1 ]; then
                    args+=(--ok-label="$first" --extra-button="$second" --cancel-label="$(msg kb_close)")
                elif [ "$defno" -eq 1 ]; then
                    # Enter must never confirm: the safe answer is the button that has the
                    # focus and the destructive one is an extra button that prints its label.
                    args+=(--ok-label="$second" --extra-button="$first" --cancel-label="$(msg kb_close)")
                else
                    args+=(--ok-label="$first" --cancel-label="$second")
                fi
            else
                gui_text_width "$text"
                args+=(--question --no-markup --width="$REPLY" --text="$text")
                if [ "$defno" -eq 1 ]; then
                    ! gui_opt --icon || icon="dialog-warning"
                else
                    ! gui_find_icon || icon="$REPLY"
                fi
                if [ "$choice" -eq 1 ]; then
                    args+=(--switch --extra-button="$first" --extra-button="$second")
                else
                    args+=(--ok-label="$first" --cancel-label="$second")
                    [ "$defno" -eq 0 ] || args+=(--default-cancel)
                fi
            fi ;;
        inputbox)
            gui_text_width "$text" "$GUI_W_ENTRY"; width="$REPLY"
            gui_escape "$text" entry
            args+=(--entry --width="$width" --text="$REPLY" --entry-text="$initial"
                   --ok-label="${ok_label:-OK}" --cancel-label="${cancel_label:-Cancel}") ;;
        menu)
            lmax=0 dmax=0
            for (( i = 0; i < ${#tags[@]}; i++ )); do
                [ "${#labels[i]}" -le "$lmax" ] || lmax="${#labels[i]}"
                [ "${#descs[i]}" -le "$dmax" ] || dmax="${#descs[i]}"
            done
            extra="$GUI_COL_PX"
            [ "$has_icon" -eq 0 ] || extra=$(( extra + GUI_COL_PX ))
            gui_list_size "$text" "${#tags[@]}" $(( lmax + dmax )) "$GUI_ROW_PX" "$extra"; size="$REPLY"
            gui_list_text "$text"
            args+=(--list --width="${size% *}" --height="${size#* }" --text="$REPLY"
                   --ok-label="${ok_label:-OK}" --cancel-label="${cancel_label:-Cancel}"
                   --column="$(msg gui_col_key)")
            [ "$has_icon" -eq 0 ] || args+=(--column=" ")
            args+=(--column="$(msg gui_col_option)")
            [ "$has_desc" -eq 0 ] || args+=(--column="$(msg gui_col_description)")
            args+=(--print-column=1)
            ! gui_opt --hide-header || args+=(--hide-header)
            for (( i = 0; i < ${#tags[@]}; i++ )); do
                gui_arg "${tags[i]}"; args+=("$REPLY")
                if [ "$has_icon" -eq 1 ]; then gui_arg "${icons[i]}"; args+=("$REPLY"); fi
                gui_arg "${labels[i]}"; args+=("$REPLY")
                if [ "$has_desc" -eq 1 ]; then gui_arg "${descs[i]}"; args+=("$REPLY"); fi
            done ;;
        checklist)
            lmax=0
            for (( i = 0; i < ${#tags[@]}; i++ )); do
                [ "${#labels[i]}" -le "$lmax" ] || lmax="${#labels[i]}"
            done
            # the check box column takes about 8 more characters
            gui_list_size "$text" "${#tags[@]}" $(( lmax + 8 )) "$GUI_ROW_CHECK_PX"; size="$REPLY"
            gui_list_text "$text"
            args+=(--list --checklist --width="${size% *}" --height="${size#* }" --text="$REPLY"
                   --ok-label="${ok_label:-OK}" --cancel-label="${cancel_label:-Cancel}"
                   --column=" " --column=Tag --column="$(msg gui_col_name)"
                   --hide-column=2 --print-column=2 --separator="|")
            ! gui_opt --hide-header || args+=(--hide-header)
            for (( i = 0; i < ${#tags[@]}; i++ )); do
                args+=("${states[i]}")
                gui_arg "${tags[i]}"; args+=("$REPLY")
                gui_arg "${labels[i]}"; args+=("$REPLY")
            done ;;
    esac

    [ -z "$icon" ] || args+=(--icon="$icon")
    # gui_cmd gives zenity C.UTF-8 whatever the locale is: it fails on any non-ASCII
    # argument and garbles its answer when the locale is not UTF-8, and its
    # messages must stay in English for the check of an unreachable display.
    err="$(mktemp "${TMPDIR:-/tmp}/mintapp-zenity.XXXXXX" 2>/dev/null)" || err=/dev/null
    # A long text goes in by stdin (an argument cannot be as long); a here-string, not a
    # pipe, so a window closed before it read everything cannot end the pipeline with SIGPIPE.
    if [ "$stdin_text" -eq 1 ]; then
        out="$(gui_cmd "${args[@]}" 2>"$err" <<< "$text")"
    else
        out="$(gui_cmd "${args[@]}" 2>"$err" </dev/null)"
    fi
    rc=$?
    # An unreachable display ends with status 1 and no output, like a closed window:
    # only its message tells them apart.
    if [ "$rc" -eq 1 ] && [ -z "$out" ] && grep -qi 'open display' "$err" 2>/dev/null; then broken=1; fi
    [ "$err" = /dev/null ] || rm -f -- "$err"
    if [ "$broken" -eq 1 ]; then return 254; fi
    case "$rc" in
        0|1) ;;
        *) if [ "$rc" -gt 128 ] && [ "$rc" -lt 193 ]; then return "$rc"; fi
           return 254 ;;
    esac

    status=1
    case "$kind" in
        msgbox) [ "$rc" -ne 0 ] || status=0 ;;
        yesno)
            if [ "$choice" -eq 1 ]; then
                # Closing the window (or its Cancel button) is the first action; only the
                # second one's own label says the second was picked.
                if [ "$out" = "$second" ]; then status=1; else status=0; fi
            elif [ "$scroll" -eq 1 ] && [ "$defno" -eq 1 ]; then
                if [ "$out" = "$first" ]; then status=0; else status=1; fi
            else
                [ "$rc" -ne 0 ] || status=0
            fi ;;
        inputbox)
            if [ "$rc" -eq 0 ]; then status=0; printf '%s' "$out" >&2; fi ;;
        menu)
            if [ "$rc" -eq 0 ]; then status=0; printf '%s' "${out# }" >&2; fi ;;
        checklist)
            if [ "$rc" -eq 0 ]; then
                status=0
                IFS='|' read -ra parts <<< "$out"
                out=""
                for tag in "${parts[@]+"${parts[@]}"}"; do
                    tag="${tag# }"
                    out+="${out:+ }\"$tag\""
                done
                printf '%s' "$out" >&2
            fi ;;
    esac
    return "$status"
}

# An error window with one button, for what stops the program before any
# screen (see fail_start). Best effort: it never fails, and it does not use
# gui_dialog (no title or sizes to compute, no status to translate). $1 = text.
gui_error() {
    gui_text_width "$1"
    gui_cmd --error --no-markup --title="$WT_TITLE" --width="$REPLY" \
        --text="$1" --ok-label="$(msg ok)" >/dev/null 2>&1 </dev/null || true
}

# ----------------------------------------------------------------------------
# Language and interface
# ----------------------------------------------------------------------------
APP_LANG="en"

declare -A MSG_ES=(
    [title]="MintApp Remover"
    [nav_title]="CÓMO MOVERSE POR LOS MENÚS"
    [nav_whiptail]="  ↑ / ↓      Moverse por la lista de opciones.\n  ESPACIO    Marcar o desmarcar una aplicación (listas con casillas).\n  TAB        Cambiar el foco entre la lista y los botones.\n             Algunos botones NO se activan hasta llevarles el foco.\n  ENTER      Confirmar la opción o el botón resaltado.\n\nEscribir el número de una opción NO la elige: usa siempre las flechas."
    [nav_text]="Modo texto activo (sin diálogos):"
    [nav_text_1]="Escribe el NÚMERO o la LETRA de la opción que quieras y pulsa Enter."
    [nav_text_2]="En las pantallas de selección múltiple: escribe el número de una aplicación para marcarla/desmarcarla (se resaltará en verde); luego escribe 'c' para confirmar o '0' para volver atrás."
    [nav_gui]="Ventanas gráficas (zenity):\n- Menús: elige con el ratón o con ↑ ↓ e Intro.\n- Listas con casillas: haz clic en una casilla o pulsa Intro sobre la fila para marcarla, y confirma con Aceptar.\n- Esc, el botón Cancelar o la cruz de la ventana vuelven atrás.\n- Los textos largos se desplazan con la rueda del ratón."
    [select_help_gui]="(clic o Intro: marcar/desmarcar | Aceptar: confirmar | Esc: volver)"
    [advanced_select_gui]="MODO AVANZADO: aplicaciones a eliminar.\n(clic o Intro: marcar/desmarcar | Aceptar: confirmar | Esc: volver)"
    [nav_zoom]="¿Texto pequeño? Ctrl y + aumenta la letra y Ctrl y - la reduce."
    [nav_text_prompt]="Pulsa Enter para continuar o escribe L para cambiar a %s:"
    [kb_enter]="Intro"
    [kb_space]="Espacio"
    [kb_move]="Mover"
    [kb_mark]="Marcar"
    [kb_switch]="Cambiar botón"
    [kb_scroll]="Desplazar"
    [kb_close]="Cerrar"
    [kb_buttons]="Botones"
    [kb_all]="Todo/Nada"
    [tui_small]="Ventana demasiado pequeña (%s): amplíala a %s o más."
    [nav_tui]="  ↑ ↓            Moverse por la lista, esté donde esté el foco.\n  Inicio / Fin   Primera o última opción.\n  RePág / AvPág  Moverse de página en página.\n  ESPACIO        Marcar o desmarcar una aplicación (listas con casillas);\n                 en un menú, elegir la opción.\n  A / N          Marcar o desmarcar todas las aplicaciones de la lista.\n  INTRO          Confirmar: se activa el botón resaltado en verde.\n  ESC o Q        Volver o cancelar (Q no, si estás escribiendo).\n  %s  Menú principal: cada tecla abre su opción.\n  /              Buscar en las listas largas.\n  TAB            Opcional: pasar a los botones (también sirven ← →).\n\nLa última fila muestra siempre las teclas que funcionan en cada pantalla."
    [understood]="Entendido"
    [ok]="Aceptar"
    [pause]="Pulsa Enter para continuar..."
    [detected_header]="Aplicaciones detectadas"
    [detected_count_1]="aplicación detectada."
    [detected_count_n]="aplicaciones detectadas."
    [uninstalling]="Desinstalando..."
    [uninstall_ok]="Desinstalación completada."
    [result_removed_pkgs]="Paquetes eliminados (%s): %s"
    [result_removed_apps]="Aplicaciones eliminadas (%s): %s"
    [uninstall_error]="Hubo un problema durante la desinstalación (código de salida %s).\n\nRevisa el mensaje del gestor de paquetes más arriba en la terminal."
    [uninstall_error_gui]="Hubo un problema durante la desinstalación (código de salida %s).\n\nÚltimas líneas de la salida del gestor de paquetes:\n%s"
    [askpass_text]="Escribe tu contraseña de administrador para continuar."
    [askpass_retry]="La contraseña no es correcta. Escribe tu contraseña de administrador de nuevo."
    [priv_denied]="No se obtuvieron permisos de administrador (se canceló la contraseña, era incorrecta o tu usuario no está autorizado a obtenerlos). No se desinstaló nada."
    [select_apps]="Selecciona las aplicaciones que quieras eliminar."
    [select_help]="(↑ ↓ mover | Espacio: marcar/desmarcar | Enter: confirmar | Esc: volver)"
    [advanced_select]="MODO AVANZADO: aplicaciones a eliminar.\n(↑ ↓ mover | Espacio: marcar/desmarcar | Enter: confirmar | Esc: volver)"
    [none_selected]="No has seleccionado ninguna aplicación."
    [none_still_installed]="Las aplicaciones seleccionadas ya no están instaladas."
    [will_remove]="Se eliminarán las siguientes aplicaciones:"
    [yes_remove]="Desinstalar"
    [cancel]="Cancelar"
    [cancelled]="Operación cancelada."
    [none_candidate]="No se ha detectado ninguna aplicación instalada del catálogo."
    [advanced_header]="MODO AVANZADO — aplicaciones detectadas mediante los lanzadores del menú"
    [advanced_text]="(escribe el número para marcar/desmarcar, 'c' para confirmar, '0' para volver)"
    [invalid]="Opción no válida."
    [out_of_range]="Número fuera de rango."
    [scanning]="Escaneando los lanzadores del menú de aplicaciones..."
    [no_extra]="No se ha detectado ninguna aplicación adicional fuera del catálogo curado."
    [advanced_warning_1]="MODO AVANZADO\n\nEsta opción escanea TODOS los lanzadores del menú de aplicaciones, no solo el catálogo curado de la Opción 2. Los componentes conocidos del sistema (el escritorio, el gestor de archivos, la terminal, el gestor de paquetes, la red, etc.) se excluyen automáticamente, al igual que los paquetes que tu gestor de paquetes protege por ser esenciales para el sistema. Aun así, revisa la lista con cuidado antes de confirmar.\n\nAntes de borrar nada, se te mostrará el plan real del gestor de paquetes (simulación), incluidos los paquetes dependientes que eliminaría. Las aplicaciones de Flatpak y Snap aparecen marcadas con el nombre de su tienda y tienen su propio plan y su propia confirmación.\n\nSe detectó %s aplicación adicional."
    [advanced_warning_n]="MODO AVANZADO\n\nEsta opción escanea TODOS los lanzadores del menú de aplicaciones, no solo el catálogo curado de la Opción 2. Los componentes conocidos del sistema (el escritorio, el gestor de archivos, la terminal, el gestor de paquetes, la red, etc.) se excluyen automáticamente, al igual que los paquetes que tu gestor de paquetes protege por ser esenciales para el sistema. Aun así, revisa la lista con cuidado antes de confirmar.\n\nAntes de borrar nada, se te mostrará el plan real del gestor de paquetes (simulación), incluidos los paquetes dependientes que eliminaría. Las aplicaciones de Flatpak y Snap aparecen marcadas con el nombre de su tienda y tienen su propio plan y su propia confirmación.\n\nSe detectaron %s aplicaciones adicionales."
    [advanced_unmanaged_1]="\n(%s lanzador más no se puede desinstalar desde aquí: no tiene un paquete asociado ni es un Flatpak o un Snap que se pueda identificar; suele ser una instalación manual.)\n"
    [advanced_unmanaged_n]="\n(%s lanzadores más no se pueden desinstalar desde aquí: no tienen un paquete asociado ni son Flatpak o Snap que se puedan identificar; suelen ser instalaciones manuales.)\n"
    [plan_calculating]="Calculando el plan de desinstalación (simulación; todavía no se borra nada)..."
    [plan_password_note]="El gestor de paquetes necesita permisos de administrador incluso para calcular el plan, así que puede pedirte la contraseña ahora."
    [plan_error]="No se pudo calcular un plan de desinstalación. Respuesta recibida:\n\n%s"
    [pm_plan_unreadable]="No se pudo leer el plan de %s: su salida no tiene el formato esperado. No se cambió nada."
    [plan_real]="Este es el plan REAL que ejecutaría el gestor de paquetes (simulación), incluidos los paquetes dependientes que eliminaría:"
    [plan_count_all]="Paquetes en el plan: %s."
    [plan_count_split]="Paquetes en el plan: %s (elegidos: %s, dependientes: %s)."
    [confirm_plan]="¿Quieres continuar con la desinstalación? Esta acción no se puede deshacer."
    [confirm_plan_text]="¿Quieres confirmar la desinstalación de los paquetes anteriores? [s/N]: "
    [confirm_plan_meta]="El plan elimina también metapaquetes del sistema (ver el aviso anterior). ¿Quieres continuar de todos modos? Esta acción no se puede deshacer."
    [confirm_plan_meta_text]="El plan elimina también metapaquetes del sistema. ¿Quieres continuar de todos modos? [s/N]: "
    [meta_warning]="ATENCIÓN: el plan elimina también metapaquetes del sistema.\n\nUn metapaquete no contiene aplicaciones: solo mantiene instalado todo un conjunto (un escritorio, una tarea o la base de la distribución). Sin él, esos paquetes dejan de estar marcados como necesarios y una limpieza de dependencias posterior (opción 4 o una limpieza automática del gestor de paquetes) podría eliminarlos.\n\nMetapaquetes del plan:\n%s\nSi no lo esperabas, cancela.\n\n"
    [answer_unknown]="Respuesta no reconocida."
    [cleaning]="Limpiando el sistema..."
    [clean_done]="Limpieza completada."
    [dependencies_removed]="Dependencias eliminadas."
    [cache_cleaned]="Se ha limpiado la caché de paquetes."
    [cache_clean_failed]="No se pudo limpiar la caché de paquetes (código de salida %s)."
    [space_recovered]="Espacio de disco recuperado (aprox.): %s MB"
    [detail_more]="+%s más"
    [detected_size]="Tamaño instalado (aprox.): %s"
    [detect_text_prompt]="Pulsa Enter para continuar o escribe 's' para buscar:"
    [search_button]="Buscar"
    [search_prompt]="Escribe lo que quieres buscar: nombre, descripción o paquete. Con varias palabras se buscan todas. Déjalo vacío para ver todo."
    [search_prompt_text]="Buscar (vacío = ver todo):"
    [search_status]="Búsqueda: \"%s\" (se muestran %s de %s)."
    [search_none]="Ninguna aplicación coincide con \"%s\"."
    [search_hidden]="Marcadas fuera de esta búsqueda: %s (se conservan)."
    [search_item]="Buscar (marca aquí y pulsa Aceptar)"
    [search_hint_text]="Escribe 's' para buscar."
    [origin_manual]="instalación manual"
    [menu_detect]="Detectar aplicaciones"
    [menu_uninstall]="Desinstalar aplicaciones"
    [menu_advanced]="Buscar otras aplicaciones (avanzado)"
    [menu_clean]="Limpiar"
    [menu_exit]="Salir"
    [menu_prompt]="Selecciona una opción:"
    [menu_whiptail]="Selecciona una opción (↑ ↓ + Enter):"
    [menu_prompt_gui]="Selecciona una opción:"
    [menu_status_apps_1]="1 aplicación detectada"
    [menu_status_apps_n]="%s aplicaciones detectadas"
    [menu_language]="English"
    [menu_detect_desc]="Ver qué aplicaciones del catálogo hay instaladas."
    [menu_uninstall_desc]="Elegir y eliminar, con el plan real a la vista."
    [menu_advanced_desc]="Buscar otras aplicaciones a partir de los lanzadores del menú."
    [menu_clean_desc]="Quitar dependencias que sobran o limpiar a fondo residuos y cachés."
    [menu_gui]="Menú gráfico"
    [menu_gui_desc]="Abrir la versión con ventanas."
    [menu_terminal]="Volver al terminal"
    [menu_terminal_desc]="Seguir con los menús del terminal."
    [gui_col_key]="Tecla"
    [gui_col_option]="Opción"
    [gui_col_description]="Descripción"
    [gui_col_name]="Aplicación"
    [gui_failed]="No se pudo abrir la ventana gráfica (zenity). Comprueba que hay una sesión gráfica o usa MINTAPP_UI=tui."
    [gui_unavailable]="--gui necesita zenity y una sesión gráfica (DISPLAY o WAYLAND_DISPLAY)."
    [gui_terminal_conflict]="--gui y --terminal no pueden usarse a la vez."
    [terminal_none]="No se encontró ningún emulador de terminal. Instala uno o indica el tuyo con MINTAPP_TERMINAL."
    [terminal_forced_error]="MINTAPP_TERMINAL=%s no es un emulador de terminal ejecutable."
    [terminal_failed]="No se pudo abrir el terminal. Puedes seguir en las ventanas."
    [menu_language_desc]="Cambiar la interfaz a inglés."
    [menu_exit_desc]="Salir sin hacer más cambios."
    [exit]="Saliendo..."
    [root_error]="No ejecutes MintApp Remover como root ni con sudo."
    [root_hint]="El propio script te pedirá la contraseña de administrador mediante sudo (o doas) solo cuando realmente la necesite."
    [dpkg_error]="MintApp Remover requiere dpkg y está pensado para distribuciones basadas en Debian/Ubuntu."
    [apt_error]="MintApp Remover requiere apt."
    [sudo_error]="MintApp Remover requiere sudo o doas para realizar operaciones de gestión de paquetes."
    [priv_forced_error]="MINTAPP_SUDO=%s no es un comando ejecutable válido."
    [pm_forced_error]="MINTAPP_PM=%s no es un gestor de paquetes válido (admitidos: %s)."
    [pm_none_error]="MintApp Remover no encontró ningún gestor de paquetes que admita (admitidos: %s)."
    [dnf_error]="MintApp Remover requiere dnf y rpm."
    [pacman_error]="MintApp Remover requiere pacman y pacman-conf."
    [zypper_error]="MintApp Remover requiere zypper y rpm."
    [dnf_version_error]="MintApp Remover requiere dnf 4 y \"dnf --version\" dice: \"%s\". dnf 5 (Fedora 41 y posteriores) aún no es compatible."
    [ambiguous_package]="paquete ambiguo"
    [plan_changed]="El sistema cambió después de calcular el plan, así que no se eliminó nada.\n\nVuelve a ejecutar la opción para revisar el plan actualizado."
    [plan_real_clean]="Este es el plan REAL que ejecutaría el gestor de paquetes (simulación): estos paquetes se instalaron como dependencias y ya no son necesarios:"
    [no_unused_deps]="No hay dependencias sin usar; no se eliminó nada."
    [record_saved]="Se guardó un registro de lo eliminado en:\n%s"
    [record_failed]="Aviso: no se pudo guardar el registro de lo eliminado."
    [store_plan_intro]="Este es el plan de desinstalación de Flatpak y Snap. Cada aplicación se quita con el comando de su tienda ('flatpak uninstall' o 'snap remove'); el gestor de paquetes no interviene:"
    [store_scope_system]="todo el sistema"
    [store_scope_user]="solo tu usuario"
    [store_confirm_text]="¿Quieres confirmar la desinstalación de las aplicaciones anteriores? [s/N]: "
    [store_removing]="Desinstalando %s..."
    [store_error]="Desinstalaciones fallidas: %s de %s (código de salida %s).\n\nRevisa el mensaje de flatpak o snap más arriba en la terminal."
    [store_error_gui]="Desinstalaciones fallidas: %s de %s (código de salida %s).\n\nÚltimas líneas de la salida:\n%s"
    [store_confirm]="¿Quieres continuar con la desinstalación de estas aplicaciones? Esta acción no se puede deshacer."
    [store_plan_calculating]="Preparando el plan de desinstalación (todavía no se borra nada)..."
    [lock_error]="Ya hay otra instancia de MintApp Remover en ejecución."
    [unknown_option]="Opción no reconocida: %s"
    [usage]="MintApp Remover %s\nDesinstala aplicaciones preinstaladas en Linux mostrando antes el plan real\ndel gestor de paquetes, y limpia los residuos del sistema.\n\nUso: MintApp_Remover.sh [OPCIÓN]\n     MintApp_Remover.sh install\n     MintApp_Remover.sh uninstall [DATOS]\n\n  -h, --help       Muestra esta ayuda y sale.\n  -V, --version    Muestra la versión y sale.\n  --gui            Abre las ventanas (zenity), aunque haya terminal.\n  --terminal       Usa el terminal; no abre ventanas.\n  --show-help      Muestra la ayuda de teclas aunque ya la hayas visto.\n  install          Instala el comando mintapp-remover, el lanzador del menú y\n                   el icono en tus carpetas (sin sudo).\n  uninstall        Los quita y pregunta qué hacer con tus ajustes y registros.\n                   DATOS evita la pregunta:\n                     --keep-records  borra los ajustes y conserva los registros\n                     --keep-all      conserva los dos\n                     --purge         borra los dos, sin dejar rastro\n\nSin terminal (por ejemplo desde el icono) y con zenity, abre las\nventanas; si la última vez elegiste el terminal (tecla T en las ventanas),\nabre un emulador de terminal.\n\nVariables de entorno (opcionales):\n  MINTAPP_LANG=en|es\n      Fuerza el idioma de la interfaz.\n  MINTAPP_UI=tui|gui|whiptail|text\n      Fuerza los diálogos propios, las ventanas (zenity), whiptail o el menú\n      de texto. Sin zenity o sin sesión gráfica, gui usa el valor por\n      defecto. --gui y --terminal prevalecen sobre esta variable.\n  MINTAPP_TERMINAL=nombre|ruta\n      Emulador de terminal que se abre al volver al terminal (por defecto,\n      el primero que se encuentre).\n  MINTAPP_ESC_WAIT=0.15\n      Segundos de espera tras Esc (súbelo en un enlace SSH lento).\n  MINTAPP_LAUNCHER_DIRS=dir1:dir2\n      Escanea solo estas carpetas en la opción 3.\n  MINTAPP_PM=apt|dnf|pacman|zypper\n      Fuerza el gestor de paquetes (por defecto, el que usa la distribución).\n  MINTAPP_SUDO=sudo|doas|ruta\n      Comando para permisos de administrador (por defecto sudo; si falta, doas).\n  NO_COLOR=1\n      Desactiva los colores (también con TERM=dumb).\n  MINTAPP_ASCII=1|0\n      Fuerza texto ASCII (1) o símbolos Unicode (0). Por defecto, ASCII si\n      el idioma del sistema no es UTF-8."
    [install_intro]="Instalando MintApp Remover %s en tus carpetas (no hacen falta permisos de administrador):"
    [install_label_bin]="comando"
    [install_label_launcher]="lanzador"
    [install_label_icon]="icono"
    [install_state_new]="instalado"
    [install_state_updated]="actualizado"
    [install_state_current]="al día"
    [install_state_kept]="conservado"
    [install_icon_none]="No se encontró ningún icono utilizable (ni el incrustado en el script ni un PNG cuadrado de al menos 16 píxeles en ../assets/icon5.png, junto al script): el lanzador mostrará uno genérico."
    [install_no_zenity]="zenity no está instalado: el lanzador abrirá un terminal en lugar de ventanas."
    [install_path_warn]="%s no está en tu PATH, así que el comando mintapp-remover no se puede ejecutar por su nombre. Añade esta línea a ~/.profile y vuelve a iniciar sesión:"
    [install_done]="Hecho. Abre MintApp Remover desde el menú de aplicaciones o ejecuta:"
    [install_err_home]="HOME no apunta a una carpeta absoluta, así que no hay dónde instalar."
    [install_err_source]="No se puede leer este script como archivo para copiarlo (por ejemplo, si llega por una tubería a bash)."
    [install_err_write]="No se pudo escribir %s."
    [install_err_remove]="No se pudo eliminar %s."
    [uninstall_intro]="Quitando MintApp Remover de tus carpetas:"
    [uninstall_state_removed]="eliminado"
    [uninstall_state_absent]="no estaba"
    [uninstall_nothing]="MintApp Remover no está instalado en tus carpetas: no hay nada que quitar."
    [uninstall_done]="Hecho."
    [install_label_config]="ajustes"
    [install_label_records]="registros"
    [uninstall_ask_intro]="¿Qué hacemos con tus datos?"
    [uninstall_choice_records]="1) Borrar los ajustes y conservar los registros de lo que quitaste (por defecto)"
    [uninstall_choice_all]="2) Conservarlo todo: ajustes y registros."
    [uninstall_choice_none]="3) Borrarlo todo, sin dejar rastro."
    [uninstall_ask_prompt]="Elige 1, 2 o 3 (q cancela) [1]:"
    [uninstall_cancelled]="Cancelado: no se ha quitado nada."
    [uninstall_busy]="MintApp Remover se está ejecutando (o hay una eliminación en curso). Ciérralo y vuelve a intentarlo."
    [uninstall_purge_hint]="Para borrar también los datos que se han conservado, ejecuta MintApp_Remover.sh uninstall --purge."
    [uninstall_conflict]="Usa solo una de las opciones --keep-records, --keep-all y --purge."
    [clean_cat_privacy]="Privacidad"
    [clean_cat_cache]="Cachés"
    [clean_cat_logs]="Registros"
    [clean_cat_packages]="Paquetes"
    [clean_item_recent]="Documentos recientes"
    [clean_item_recent_desc]="Vacía las listas de documentos recientes del escritorio y de las aplicaciones."
    [clean_item_clipboard]="Portapapeles"
    [clean_item_clipboard_desc]="Vacía lo último que copiaste, si hay xsel, xclip o wl-copy instalados."
    [clean_item_trash]="Papelera"
    [clean_item_trash_desc]="Elimina para siempre todo lo que hay en la papelera. No se puede deshacer."
    [clean_item_thumbnails]="Miniaturas"
    [clean_item_thumbnails_desc]="Quita las vistas previas de imágenes que guarda el gestor de archivos; se crean de nuevo cuando hacen falta."
    [clean_item_browsers]="Cachés de navegadores"
    [clean_item_browsers_desc]="Vacía la caché de Firefox, Chrome, Chromium, Brave, Opera, LibreWolf y Thunderbird. Los que estén abiertos se saltan."
    [clean_item_cache]="Resto de cachés"
    [clean_item_cache_desc]="Quita lo que las aplicaciones guardan en ~/.cache y rehacen por sí solas."
    [clean_item_app_caches]="Cachés de aplicaciones (Flatpak, Snap)"
    [clean_item_app_caches_desc]="Vacía las cachés propias de las aplicaciones Flatpak y Snap."
    [clean_item_tmp]="Archivos temporales"
    [clean_item_tmp_desc]="Elimina tus archivos de /tmp y /var/tmp que no están en uso."
    [clean_item_rotated_logs]="Registros rotados"
    [clean_item_rotated_logs_desc]="Elimina las copias antiguas de los registros del sistema (.1, .gz, .old). Requiere permisos de administrador."
    [clean_item_journal]="Diario del sistema"
    [clean_item_journal_desc]="Recorta el diario de systemd. Requiere permisos de administrador."
    [clean_item_x11_logs]="Errores de X11"
    [clean_item_x11_logs_desc]="Vacía ~/.xsession-errors, donde la sesión gráfica anota sus errores."
    [clean_item_crash]="Informes de fallos"
    [clean_item_crash_desc]="Elimina informes de fallos y volcados de memoria. Requiere permisos de administrador."
    [clean_item_apt_cache]="Caché de paquetes"
    [clean_item_apt_cache_desc]="Borra los archivos .deb descargados que apt conserva. Requiere permisos de administrador."
    [clean_item_rc_config]="Configuración residual"
    [clean_item_rc_config_desc]="Purga la configuración de paquetes ya desinstalados, tras mostrarte el plan de apt. Requiere permisos de administrador."
    [back]="Volver"
    [clean_menu_prompt]="¿Qué quieres hacer?"
    [clean_action_deps]="Limpiar dependencias"
    [clean_action_deps_desc]="Quita las dependencias que sobran y limpia la caché de paquetes."
    [clean_action_deep]="Limpieza profunda"
    [clean_action_deep_desc]="Borra residuos, cachés y registros del sistema y de tus aplicaciones, después de mostrarte qué y cuánto."
    [clean_level_prompt]="Elige el nivel de la limpieza profunda. Antes de borrar nada verás qué se limpia y cuánto espacio libera."
    [clean_level_simple]="Simple (bajo riesgo)"
    [clean_level_simple_desc]="Solo residuos y cachés que las aplicaciones rehacen, con límites de edad. No toca la papelera ni lo que consideras tuyo."
    [clean_level_complete]="Completa (a fondo)"
    [clean_level_complete_desc]="Lo mismo sin límites de edad, más la papelera, toda la caché del usuario, el diario archivado, los errores de X11, los informes de fallos y la configuración residual."
    [clean_level_includes]="Este nivel limpia:"
    [clean_scope_prompt]="¿Qué quieres limpiar?"
    [clean_scope_all]="Todo el nivel"
    [clean_scope_all_desc]="Limpia todo lo de la lista, sin elegir nada más."
    [clean_scope_cats]="Por categorías"
    [clean_scope_cats_desc]="Eliges categorías enteras; cada una limpia todo lo suyo."
    [clean_scope_entries]="Una a una"
    [clean_scope_entries_desc]="Eliges cada elemento por separado."
    [clean_pick_cats]="Marca las categorías que quieras limpiar.\nCada una limpia todo lo suyo en este nivel."
    [clean_pick_entries]="Marca lo que quieras limpiar."
    [clean_pick_none]="No has marcado nada. Marca algo de la lista o vuelve atrás."
    [clean_measuring]="Calculando lo que se limpiaría. No se borra nada."
    [clean_sum_title]="Limpieza profunda %s. Esto se limpiaría:"
    [clean_files_1]="%s archivo"
    [clean_files_n]="%s archivos"
    [clean_pkgs_1]="%s paquete"
    [clean_pkgs_n]="%s paquetes"
    [clean_sum_clipboard]="se vacía (%s)"
    [clean_sum_more]="(y %s más)"
    [clean_sum_open]="Navegadores abiertos, se saltan: %s"
    [clean_sum_empty]="Sin nada que limpiar: %s"
    [clean_sum_unavailable]="No disponible en este sistema: %s"
    [clean_sum_busy]="En uso ahora, se salta: %s"
    [clean_sum_unknown]="No se pudo calcular: %s"
    [clean_sum_total]="Total: %s en %s"
    [clean_sum_nothing]="No hay nada que limpiar con lo que has elegido."
    [clean_running]="Limpiando: %s"
    [clean_res_title]="Limpieza profunda %s. Resultado:"
    [clean_res_done]="Limpiado:"
    [clean_res_failed]="Con fallos:"
    [clean_res_clipboard]="vaciado (%s)"
    [clean_res_left]="%s sin limpiar"
    [clean_res_fail]="falló la limpieza"
    [clean_res_changed]="el plan cambió, no se purgó nada."
    [clean_res_freed]="Espacio recuperado: %s en %s"
    [clean_res_nothing]="No se limpió nada."
    [clean_yes]="Limpiar"
    [clean_confirm]="¿Quieres continuar con la limpieza? Esta acción no se puede deshacer."
    [clean_confirm_text]="¿Quieres confirmar esta limpieza? [s/N]: "
    [clean_priv_denied]="No se obtuvieron permisos de administrador (se canceló la contraseña, era incorrecta o tu usuario no está autorizado a obtenerlos). No se limpió nada."
    [clean_password_note]="Una parte de esta limpieza necesita permisos de administrador.\nPuede pedirte la contraseña ahora."
)

declare -A MSG_EN=(
    [title]="MintApp Remover"
    [nav_title]="HOW TO NAVIGATE THE MENUS"
    [nav_whiptail]="  ↑ / ↓      Move through the list of options.\n  SPACE      Mark or unmark an application (on checkbox screens).\n  TAB        Move focus between the list and the buttons.\n             Some buttons CANNOT be activated until focus is on them.\n  ENTER      Confirm the highlighted option or button.\n\nTyping an option number does NOT select it: always use the arrow keys."
    [nav_text]="Text mode is active (no dialogs):"
    [nav_text_1]="Type the NUMBER or LETTER of the option you want, then press Enter."
    [nav_text_2]="On multi-selection screens: type the number of an application to mark or unmark it (it will be highlighted in green), then type 'c' to confirm or '0' to go back."
    [nav_gui]="Graphical windows (zenity):\n- Menus: choose with the mouse or with ↑ ↓ and Enter.\n- Lists with checkboxes: click a box or press Enter on the row to mark it, then confirm with OK.\n- Esc, the Cancel button or the window's close button go back.\n- Long texts scroll with the mouse wheel."
    [select_help_gui]="(click or Enter: mark/unmark | OK: confirm | Esc: go back)"
    [advanced_select_gui]="ADVANCED MODE: applications to remove.\n(click or Enter: mark/unmark | OK: confirm | Esc: go back)"
    [nav_zoom]="Text too small? Ctrl and + enlarges the font, Ctrl and - shrinks it."
    [nav_text_prompt]="Press Enter to continue or type L to switch to %s:"
    [kb_enter]="Enter"
    [kb_space]="Space"
    [kb_move]="Move"
    [kb_mark]="Mark"
    [kb_switch]="Switch button"
    [kb_scroll]="Scroll"
    [kb_close]="Close"
    [kb_buttons]="Buttons"
    [kb_all]="All/None"
    [tui_small]="Window too small (%s): enlarge it to %s or more."
    [nav_tui]="  ↑ ↓            Move through the list, wherever the focus is.\n  Home / End     First or last entry.\n  PgUp / PgDn    Move one page at a time.\n  SPACE          Mark or unmark an application (on checkbox screens);\n                 in a menu, choose the entry.\n  A / N          Mark or unmark every application in the list.\n  ENTER          Confirm: the button highlighted in green is activated.\n  ESC or Q       Go back or cancel (not Q while typing).\n  %s  Main menu: each key opens its option.\n  /              Search long lists.\n  TAB            Optional: switch to the buttons (← → work too).\n\nThe last row always shows the keys that work on each screen."
    [understood]="Understood"
    [ok]="OK"
    [pause]="Press Enter to continue..."
    [detected_header]="Detected applications"
    [detected_count_1]="application detected."
    [detected_count_n]="applications detected."
    [uninstalling]="Uninstalling..."
    [uninstall_ok]="Uninstallation completed successfully."
    [result_removed_pkgs]="Removed packages (%s): %s"
    [result_removed_apps]="Removed applications (%s): %s"
    [uninstall_error]="Uninstallation failed (exit code %s).\n\nCheck the package manager output above in the terminal."
    [uninstall_error_gui]="Uninstallation failed (exit code %s).\n\nLast lines of the package manager output:\n%s"
    [askpass_text]="Enter your administrator password to continue."
    [askpass_retry]="The password is not correct. Enter your administrator password again."
    [priv_denied]="Administrator rights were not obtained (the password was cancelled or wrong, or your user is not allowed to get them). Nothing was uninstalled."
    [select_apps]="Select the applications you want to remove."
    [select_help]="(↑ ↓ move | Space: mark/unmark | Enter: confirm | Esc: go back)"
    [advanced_select]="ADVANCED MODE: applications to remove.\n(↑ ↓ move | Space: mark/unmark | Enter: confirm | Esc: go back)"
    [none_selected]="No applications were selected."
    [none_still_installed]="The selected applications are no longer installed."
    [will_remove]="The following applications will be removed:"
    [yes_remove]="Uninstall"
    [cancel]="Cancel"
    [cancelled]="Operation cancelled."
    [none_candidate]="No installed applications from the curated catalog were detected."
    [advanced_header]="ADVANCED MODE — Applications detected from menu launchers"
    [advanced_text]="(type a number to mark or unmark, 'c' to confirm, '0' to go back)"
    [invalid]="Invalid option."
    [out_of_range]="Number out of range."
    [scanning]="Scanning application menu launchers..."
    [no_extra]="No additional applications were detected outside the curated catalog."
    [advanced_warning_1]="ADVANCED MODE\n\nThis option scans ALL application menu launchers, not just the curated catalog in Option 2. Known system components (the desktop, the file manager, the terminal, the package manager, networking, etc.) are excluded automatically, as are packages that your package manager protects as essential to the system. Even so, review the list carefully before confirming.\n\nBefore anything is removed, you will see the real plan of the package manager (simulation), including any dependent packages it would remove. Flatpak and Snap applications appear marked with the name of their store and have their own plan and their own confirmation.\n\n%s additional application was detected."
    [advanced_warning_n]="ADVANCED MODE\n\nThis option scans ALL application menu launchers, not just the curated catalog in Option 2. Known system components (the desktop, the file manager, the terminal, the package manager, networking, etc.) are excluded automatically, as are packages that your package manager protects as essential to the system. Even so, review the list carefully before confirming.\n\nBefore anything is removed, you will see the real plan of the package manager (simulation), including any dependent packages it would remove. Flatpak and Snap applications appear marked with the name of their store and have their own plan and their own confirmation.\n\n%s additional applications were detected."
    [advanced_unmanaged_1]="\n(%s additional launcher cannot be uninstalled from here: it has no associated package and is not a Flatpak or Snap that can be identified; it is usually a manual install.)\n"
    [advanced_unmanaged_n]="\n(%s additional launchers cannot be uninstalled from here: they have no associated package and are not Flatpak or Snap applications that can be identified; they are usually manual installs.)\n"
    [plan_calculating]="Calculating the uninstallation plan (simulation; nothing is removed yet)..."
    [plan_password_note]="The package manager needs administrator rights even to calculate the plan, so it may ask for your password now."
    [plan_error]="Could not calculate an uninstallation plan. Response received:\n\n%s"
    [pm_plan_unreadable]="Could not read the plan of %s: its output does not have the expected format. Nothing was changed."
    [plan_real]="This is the REAL plan that the package manager would execute (simulation), including any dependent packages it would remove:"
    [plan_count_all]="Packages in the plan: %s."
    [plan_count_split]="Packages in the plan: %s (chosen: %s, dependent: %s)."
    [confirm_plan]="Do you want to continue uninstalling these packages? This action cannot be undone."
    [confirm_plan_text]="Do you want to uninstall the packages listed above? [y/N]: "
    [confirm_plan_meta]="The plan also removes system meta-packages (see the warning above). Do you want to continue anyway? This action cannot be undone."
    [confirm_plan_meta_text]="The plan also removes system meta-packages. Do you want to continue anyway? [y/N]: "
    [meta_warning]="WARNING: the plan also removes system meta-packages.\n\nA meta-package contains no applications: it only keeps a whole set installed (a desktop, a task or the base of the distribution). Without it, those packages are no longer marked as needed, and a later dependency cleanup (option 4 or an automatic cleanup by the package manager) could remove them.\n\nMeta-packages in the plan:\n%s\nIf you did not expect this, cancel.\n\n"
    [answer_unknown]="Answer not recognized."
    [cleaning]="Cleaning up the system..."
    [clean_done]="Cleanup completed."
    [dependencies_removed]="Dependencies removed."
    [cache_cleaned]="Package cache cleaned."
    [cache_clean_failed]="The package cache could not be cleaned (exit code %s)."
    [space_recovered]="Approx. disk space recovered: %s MB"
    [detail_more]="+%s more"
    [detected_size]="Installed size (approx.): %s"
    [detect_text_prompt]="Press Enter to continue or type 's' to search:"
    [search_button]="Search"
    [search_prompt]="Type what to look for: name, description or package. With several words, all of them must match. Leave it empty to show everything."
    [search_prompt_text]="Search (empty = show all):"
    [search_status]="Search: \"%s\" (showing %s of %s)."
    [search_none]="No application matches \"%s\"."
    [search_hidden]="Marked outside this search: %s (kept)."
    [search_item]="Search (check here and press OK)"
    [search_hint_text]="Type 's' to search."
    [origin_manual]="manual install"
    [menu_detect]="Detect applications"
    [menu_uninstall]="Uninstall applications"
    [menu_advanced]="Find other applications (advanced)"
    [menu_clean]="Clean up"
    [menu_exit]="Exit"
    [menu_prompt]="Select an option:"
    [menu_whiptail]="Select an option (↑ ↓ + Enter):"
    [menu_prompt_gui]="Select an option:"
    [menu_status_apps_1]="1 application detected"
    [menu_status_apps_n]="%s applications detected"
    [menu_language]="Español"
    [menu_detect_desc]="See which catalog applications are installed."
    [menu_uninstall_desc]="Pick and remove them, with the real plan shown first."
    [menu_advanced_desc]="Find other applications from their menu launchers."
    [menu_clean_desc]="Remove leftover dependencies or deep-clean waste files and caches."
    [menu_gui]="Graphical menu"
    [menu_gui_desc]="Open the windowed version."
    [menu_terminal]="Back to terminal"
    [menu_terminal_desc]="Continue with the terminal menus."
    [gui_col_key]="Key"
    [gui_col_option]="Option"
    [gui_col_description]="Description"
    [gui_col_name]="Application"
    [gui_failed]="The graphical window (zenity) could not be opened. Check that a graphical session is running or use MINTAPP_UI=tui."
    [gui_unavailable]="--gui needs zenity and a graphical session (DISPLAY or WAYLAND_DISPLAY)."
    [gui_terminal_conflict]="--gui and --terminal cannot be used together."
    [terminal_none]="No terminal emulator was found. Install one or name yours with MINTAPP_TERMINAL."
    [terminal_forced_error]="MINTAPP_TERMINAL=%s is not an executable terminal emulator."
    [terminal_failed]="The terminal could not be opened. You can keep working in the windows."
    [menu_language_desc]="Switch the interface to Spanish."
    [menu_exit_desc]="Leave without making further changes."
    [exit]="Exiting..."
    [root_error]="Do not run MintApp Remover as root or with sudo."
    [root_hint]="The script will ask for the administrator password through sudo (or doas) only when it actually needs it."
    [dpkg_error]="MintApp Remover requires dpkg and is intended for Debian/Ubuntu-based distributions."
    [apt_error]="MintApp Remover requires apt."
    [sudo_error]="MintApp Remover requires sudo or doas for package-management operations."
    [priv_forced_error]="MINTAPP_SUDO=%s is not a valid executable command."
    [pm_forced_error]="MINTAPP_PM=%s is not a valid package manager (supported: %s)."
    [pm_none_error]="MintApp Remover did not find a package manager it supports (supported: %s)."
    [dnf_error]="MintApp Remover requires dnf and rpm."
    [pacman_error]="MintApp Remover requires pacman and pacman-conf."
    [zypper_error]="MintApp Remover requires zypper and rpm."
    [dnf_version_error]="MintApp Remover requires dnf 4, and \"dnf --version\" says: \"%s\". dnf 5 (Fedora 41 and later) is not supported yet."
    [ambiguous_package]="ambiguous package"
    [plan_changed]="The system changed after the plan was calculated, so nothing was removed.\n\nRun the option again to review the updated plan."
    [plan_real_clean]="This is the REAL plan that the package manager would execute (simulation): these packages were installed as dependencies and are no longer needed:"
    [no_unused_deps]="No unused dependencies were found; nothing to remove."
    [record_saved]="A record of what was removed was saved to:\n%s"
    [record_failed]="Warning: the removal record could not be saved."
    [store_plan_intro]="This is the plan to uninstall Flatpak and Snap applications. Each one is removed with the command of its store ('flatpak uninstall' or 'snap remove'); the package manager is not involved:"
    [store_scope_system]="system-wide"
    [store_scope_user]="your user only"
    [store_confirm_text]="Do you want to uninstall the applications listed above? [y/N]: "
    [store_removing]="Uninstalling %s..."
    [store_error]="Uninstalls that failed: %s of %s (exit code %s).\n\nCheck the flatpak or snap output above in the terminal."
    [store_error_gui]="Uninstalls that failed: %s of %s (exit code %s).\n\nLast lines of the output:\n%s"
    [store_confirm]="Do you want to continue uninstalling these applications? This action cannot be undone."
    [store_plan_calculating]="Preparing the uninstallation plan (nothing will be removed yet)..."
    [lock_error]="Another instance of MintApp Remover is already running."
    [unknown_option]="Unrecognized option: %s"
    [usage]="MintApp Remover %s\nUninstall preinstalled applications on Linux, showing the real plan of\nthe package manager first, and clean up system leftovers.\n\nUsage: MintApp_Remover.sh [OPTION]\n       MintApp_Remover.sh install\n       MintApp_Remover.sh uninstall [DATA]\n\n  -h, --help       Show this help and exit.\n  -V, --version    Show the version and exit.\n  --gui            Open the windows (zenity), even on a terminal.\n  --terminal       Use the terminal; never open windows.\n  --show-help      Show the key help again, even if you have seen it.\n  install          Install the mintapp-remover command, the menu launcher and\n                   the icon in your own folders (no sudo needed).\n  uninstall        Remove them from your folders and ask what to do with your\n                   settings and removal records. DATA skips the question:\n                     --keep-records  delete the settings, keep the records\n                     --keep-all      keep both\n                     --purge         delete both, leaving no trace\n\nWithout a terminal (for example from the launcher) and with zenity, it\nopens the windows; if you last chose the terminal (key T in the windows),\nit opens a terminal emulator instead.\n\nEnvironment variables (optional):\n  MINTAPP_LANG=en|es\n      Force the interface language.\n  MINTAPP_UI=tui|gui|whiptail|text\n      Force the built-in dialogs, the windows (zenity), whiptail or the\n      plain-text menu. Without zenity or a graphical session, gui uses the\n      default. --gui and --terminal take precedence over it.\n  MINTAPP_TERMINAL=name|path\n      Terminal emulator to open when you go back to the terminal (default:\n      the first one found).\n  MINTAPP_ESC_WAIT=0.15\n      Seconds to wait after Esc (raise it on a slow SSH link).\n  MINTAPP_LAUNCHER_DIRS=dir1:dir2\n      Scan only these folders in Option 3.\n  MINTAPP_PM=apt|dnf|pacman|zypper\n      Force the package manager (default: the one the distribution uses).\n  MINTAPP_SUDO=sudo|doas|path\n      Command for administrator rights (default: sudo; doas if sudo is missing).\n  NO_COLOR=1\n      Disable colors (also with TERM=dumb).\n  MINTAPP_ASCII=1|0\n      Force plain ASCII text (1) or Unicode symbols (0). By default ASCII\n      is used when the system locale is not UTF-8."
    [install_intro]="Installing MintApp Remover %s in your own folders (no administrator rights needed):"
    [install_label_bin]="command"
    [install_label_launcher]="launcher"
    [install_label_icon]="icon"
    [install_state_new]="installed"
    [install_state_updated]="updated"
    [install_state_current]="up to date"
    [install_state_kept]="kept"
    [install_icon_none]="No usable icon found (neither the one embedded in the script nor a square PNG of at least 16 pixels at ../assets/icon5.png, beside the script): the launcher will show a generic one."
    [install_no_zenity]="zenity is not installed, so the launcher will open a terminal instead of windows."
    [install_path_warn]="%s is not in your PATH, so the command mintapp-remover cannot be run by name. Add this line to ~/.profile and log in again:"
    [install_done]="Done. Open MintApp Remover from the application menu or run:"
    [install_err_home]="HOME is not set to an absolute folder, so there is nowhere to install."
    [install_err_source]="Cannot read this script as a file to copy it (for example when it is piped into bash)."
    [install_err_write]="Could not write %s."
    [install_err_remove]="Could not remove %s."
    [uninstall_intro]="Removing MintApp Remover from your folders:"
    [uninstall_state_removed]="removed"
    [uninstall_state_absent]="not there"
    [uninstall_nothing]="MintApp Remover is not installed in your folders: nothing to remove."
    [uninstall_done]="Done."
    [install_label_config]="settings"
    [install_label_records]="records"
    [uninstall_ask_intro]="What should happen to your data?"
    [uninstall_choice_records]="1) Delete the settings and keep the records of what you removed (default)"
    [uninstall_choice_all]="2) Keep everything: settings and records."
    [uninstall_choice_none]="3) Delete everything, leaving no trace."
    [uninstall_ask_prompt]="Choose 1, 2 or 3 (q cancels) [1]:"
    [uninstall_cancelled]="Cancelled: nothing was removed."
    [uninstall_busy]="MintApp Remover is running (or a removal is in progress). Close it and try again."
    [uninstall_purge_hint]="To delete the data that was kept as well, run MintApp_Remover.sh uninstall --purge."
    [uninstall_conflict]="Use only one of --keep-records, --keep-all and --purge."
    [clean_cat_privacy]="Privacy"
    [clean_cat_cache]="Caches"
    [clean_cat_logs]="Logs"
    [clean_cat_packages]="Packages"
    [clean_item_recent]="Recent documents"
    [clean_item_recent_desc]="Clears the recent documents lists of the desktop and its applications."
    [clean_item_clipboard]="Clipboard"
    [clean_item_clipboard_desc]="Empties what you last copied, if xsel, xclip or wl-copy is installed."
    [clean_item_trash]="Trash"
    [clean_item_trash_desc]="Permanently deletes everything in the trash. It cannot be undone."
    [clean_item_thumbnails]="Thumbnails"
    [clean_item_thumbnails_desc]="Removes the image previews the file manager saves; they are made again when needed."
    [clean_item_browsers]="Browser caches"
    [clean_item_browsers_desc]="Empties the cache of Firefox, Chrome, Chromium, Brave, Opera, LibreWolf and Thunderbird. Open ones are skipped."
    [clean_item_cache]="Other caches"
    [clean_item_cache_desc]="Removes what applications keep in ~/.cache and rebuild on their own."
    [clean_item_app_caches]="Application caches (Flatpak, Snap)"
    [clean_item_app_caches_desc]="Empties the cache of each Flatpak and Snap application."
    [clean_item_tmp]="Temporary files"
    [clean_item_tmp_desc]="Removes your files in /tmp and /var/tmp that are not in use."
    [clean_item_rotated_logs]="Rotated logs"
    [clean_item_rotated_logs_desc]="Removes the old copies of the system logs (.1, .gz, .old). Needs administrator rights."
    [clean_item_journal]="System journal"
    [clean_item_journal_desc]="Trims the systemd journal. Needs administrator rights."
    [clean_item_x11_logs]="X11 error log"
    [clean_item_x11_logs_desc]="Empties ~/.xsession-errors, where the graphical session writes its errors."
    [clean_item_crash]="Crash reports"
    [clean_item_crash_desc]="Removes crash reports and memory dumps. Needs administrator rights."
    [clean_item_apt_cache]="Package cache"
    [clean_item_apt_cache_desc]="Deletes the downloaded .deb files that apt keeps. Needs administrator rights."
    [clean_item_rc_config]="Leftover settings"
    [clean_item_rc_config_desc]="Purges the settings of packages that are already removed, after showing you the plan of apt. Needs administrator rights."
    [back]="Back"
    [clean_menu_prompt]="What do you want to do?"
    [clean_action_deps]="Clean up dependencies"
    [clean_action_deps_desc]="Removes the dependencies that are no longer needed and cleans the package cache."
    [clean_action_deep]="Deep cleanup"
    [clean_action_deep_desc]="Deletes waste files, caches and logs of the system and of your applications, after showing you what and how much."
    [clean_level_prompt]="Choose the level of the deep cleanup. Before anything is deleted you will see what is cleaned and how much space it frees."
    [clean_level_simple]="Simple (low risk)"
    [clean_level_simple_desc]="Only waste files and caches that applications rebuild, with age limits. It does not touch the trash or what you may consider yours."
    [clean_level_complete]="Complete (thorough)"
    [clean_level_complete_desc]="The same without age limits, plus the trash, the whole user cache, the archived journal, the X11 errors, the crash reports and the leftover settings."
    [clean_level_includes]="This level cleans:"
    [clean_scope_prompt]="What do you want to clean?"
    [clean_scope_all]="The whole level"
    [clean_scope_all_desc]="Cleans everything on the list, with nothing more to choose."
    [clean_scope_cats]="By category"
    [clean_scope_cats_desc]="You pick whole categories; each one cleans everything of its own."
    [clean_scope_entries]="One by one"
    [clean_scope_entries_desc]="You pick each item separately."
    [clean_pick_cats]="Mark the categories you want to clean.\nEach one cleans everything of its own at this level."
    [clean_pick_entries]="Mark what you want to clean."
    [clean_pick_none]="Nothing is marked. Mark something on the list or go back."
    [clean_measuring]="Working out what would be cleaned. Nothing is deleted."
    [clean_sum_title]="Deep cleanup, %s level. This would be cleaned:"
    [clean_files_1]="%s file"
    [clean_files_n]="%s files"
    [clean_pkgs_1]="%s package"
    [clean_pkgs_n]="%s packages"
    [clean_sum_clipboard]="gets emptied (%s)"
    [clean_sum_more]="(and %s more)"
    [clean_sum_open]="Open browsers, skipped: %s"
    [clean_sum_empty]="Nothing to clean: %s"
    [clean_sum_unavailable]="Not available on this system: %s"
    [clean_sum_busy]="In use now, skipped: %s"
    [clean_sum_unknown]="Could not be worked out: %s"
    [clean_sum_total]="Total: %s in %s"
    [clean_sum_nothing]="There is nothing to clean with what you chose."
    [clean_running]="Cleaning: %s"
    [clean_res_title]="Deep cleanup, %s level. Result:"
    [clean_res_done]="Cleaned:"
    [clean_res_failed]="With failures:"
    [clean_res_clipboard]="emptied (%s)"
    [clean_res_left]="%s not cleaned"
    [clean_res_fail]="cleaning failed"
    [clean_res_changed]="the plan changed, nothing was purged."
    [clean_res_freed]="Space recovered: %s in %s"
    [clean_res_nothing]="Nothing was cleaned."
    [clean_yes]="Clean"
    [clean_confirm]="Do you want to continue with the cleanup? This action cannot be undone."
    [clean_confirm_text]="Do you want to confirm this cleanup? [y/N]: "
    [clean_priv_denied]="Administrator rights were not obtained (the password was cancelled or wrong, or your user is not allowed to get them). Nothing was cleaned."
    [clean_password_note]="Part of this cleanup needs administrator rights.\nIt may ask for your password now."
)

msg() {
    local key="$1"
    local value
    if [ "$APP_LANG" = "es" ]; then
        value="${MSG_ES[$key]}"
    else
        value="${MSG_EN[$key]}"
    fi
    if [ "$UNICODE" -eq 0 ]; then
        ascii_fold "$value"
        value="$REPLY"
    fi
    printf '%s' "$value"
}

# Prints a message followed by a newline.
msgln() {
    msg "$1"
    printf '\n'
}

# Formats a catalog message (a printf format) into the variable named by $1.
# $2 = message key, $3.. = printf arguments. The catalog strings are printf
# formats on purpose (translators may reorder text around each %s).
msgf_v() {
    local __var="$1" __key="$2" __fmt
    shift 2
    __fmt="$(msg "$__key")"
    # shellcheck disable=SC2059
    printf -v "$__var" "$__fmt" "$@"
}

set_language() {
    APP_LANG="$1"
    WT_TITLE="$(app_title)"
}

# Prints the language MINTAPP_LANG asks for (es or en) and succeeds; fails,
# printing nothing, when it is unset or names another language. Only the
# language code counts: ES, es_MX.UTF-8 and en-US are accepted.
forced_language() {
    local forced="${MINTAPP_LANG:-}"
    forced="${forced,,}"
    forced="${forced%%[_.@-]*}"
    case "$forced" in
        es|en) printf '%s' "$forced" ;;
        *) return 1 ;;
    esac
}

# Order of precedence: MINTAPP_LANG, the language saved in the configuration
# (apply_saved_language, which runs later: this one runs when the file is
# loaded), the system locale.
detect_language() {
    local locale="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    local candidate normalized forced
    local -a preferences=()

    if forced="$(forced_language)"; then
        set_language "$forced"
        return
    fi

    case "$locale" in
        C|C.*|POSIX|POSIX.*|"")
            set_language "en"
            return
            ;;
    esac

    # Like gettext: when LANGUAGE is set it alone decides, taking the first
    # entry we translate. If none matches, the original (English) text is
    # used, not the language of the locale.
    if [ -n "${LANGUAGE:-}" ]; then
        IFS=: read -r -a preferences <<< "$LANGUAGE"
        for candidate in "${preferences[@]+"${preferences[@]}"}"; do
            normalized="${candidate%%.*}"
            normalized="${normalized%%@*}"
            case "$normalized" in
                es|es_*) set_language "es"; return ;;
                en|en_*|C|POSIX) set_language "en"; return ;;
            esac
        done
        set_language "en"
        return
    fi

    normalized="${locale%%.*}"
    normalized="${normalized%%@*}"
    case "$normalized" in
        es|es_*) set_language "es" ;;
        *) set_language "en" ;;
    esac
}

# Switches between Spanish and English and saves the choice (config_set: if it
# cannot be saved the switch still holds for this run).
toggle_language() {
    if [ "$APP_LANG" = "es" ]; then
        set_language "en"
    else
        set_language "es"
    fi
    config_set language "$APP_LANG" || true

    if [ "$DETECTION_DONE" -eq 1 ]; then
        local i key
        for i in "${!DETECTED_KEYS[@]}"; do
            key="${DETECTED_KEYS[$i]}"
            DETECTED_NAMES[i]="$(catalog_name "$key")"
            DETECTED_DESC[i]="$(catalog_desc "$key")"
        done
    fi
}

# ----------------------------------------------------------------------------
# System detection: distribution (os-release) and desktop environment.
# /etc/os-release is parsed as data, line by line: it is never sourced, so
# nothing written in it can run as code. MINTAPP_OS_RELEASE=file reads another
# file (tests, diagnostics); if that file is missing nothing is detected.
# ----------------------------------------------------------------------------

# Makes text coming from outside the script (a launcher, os-release) safe to
# print: removes control characters (a terminal escape sequence starts with
# ESC), turns tabs into spaces and backslashes into slashes (echo -e and
# printf %b would interpret them), and shortens very long text so it cannot
# break a dialog.
sanitize_display() {
    local text="$1"
    text="${text//$'\t'/ }"
    text="${text//[[:cntrl:]]/}"
    text="${text//\\//}"
    if [ "${#text}" -gt 64 ]; then
        text="${text:0:61}..."
    fi
    printf '%s' "$text"
}

# The characters of the identifier patterns of detect_system, pm_valid_name,
# is_flatpak_id, is_snap_name and is_flatpak_remote, written out: a range such
# as [a-z] follows the collation of the locale and, in en_US.UTF-8 and others,
# also takes "é", full-width letters and "²" (D7). They are set here because
# detect_system runs as soon as the script is loaded.
ID_LOWER="abcdefghijklmnopqrstuvwxyz"
ID_UPPER="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
ID_DIGIT="0123456789"

SYS_ID=""             # os-release ID: linuxmint, ubuntu, debian, fedora, arch...
SYS_ID_LIKE=""        # os-release ID_LIKE (valid words only)
SYS_PRETTY=""         # full name, e.g. "Debian GNU/Linux 12 (bookworm)"
SYS_LABEL=""          # short name, e.g. "Debian GNU/Linux 12" (not shown in the interface)
SYS_FAMILY="unknown"  # debian | fedora | arch | suse | unknown
SYS_DESKTOP="other"   # cinnamon | gnome | kde | xfce | mate | other

# Puts an os-release value in REPLY without its quotes. Inside double quotes
# the escapes \" \\ \$ and \` are resolved (os-release(5)).
os_release_unquote() {
    local v="$1" q bs=$'\\' dq='"' dol='$' bt='`'
    if [ "${#v}" -ge 2 ]; then
        q="${v:0:1}"
        if [[ "$q" == [\"\'] && "${v: -1}" == "$q" ]]; then
            v="${v:1:${#v}-2}"
            if [ "$q" = '"' ]; then
                v="${v//"$bs$dq"/$dq}"
                v="${v//"$bs$dol"/$dol}"
                v="${v//"$bs$bt"/$bt}"
                v="${v//"$bs$bs"/$bs}"
            fi
        fi
    fi
    REPLY="$v"
}

# Fills SYS_* from os-release and XDG_CURRENT_DESKTOP, loads the lists of the
# detected desktop (load_desktop_lists) and refreshes the window title (which
# does not include the system). Never fails: what cannot be detected stays
# empty/"unknown".
# SYS_PRETTY is shown on the status line of the main menu (menu_status_text);
# SYS_FAMILY is read by pm_detect (package manager). SYS_LABEL is kept but not
# read, which is what the disable below is for.
# shellcheck disable=SC2034
detect_system() {
    local file line token name="" version="" pretty="" raw_id="" raw_like="" label
    local -a tokens=()
    SYS_ID="" SYS_ID_LIKE="" SYS_PRETTY="" SYS_LABEL="" SYS_FAMILY="unknown" SYS_DESKTOP="other"

    if [ -n "${MINTAPP_OS_RELEASE:-}" ]; then
        file="$MINTAPP_OS_RELEASE"
    elif [ -r /etc/os-release ]; then
        file="/etc/os-release"
    else
        file="/usr/lib/os-release"
    fi

    if [ -f "$file" ] && [ -r "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            [[ "$line" =~ ^[[:space:]]*(ID|ID_LIKE|NAME|PRETTY_NAME|VERSION_ID)=(.*)$ ]] || continue
            token="${BASH_REMATCH[1]}"
            os_release_unquote "${BASH_REMATCH[2]}"
            # The last assignment wins, as in a shell.
            case "$token" in
                ID) raw_id="$REPLY" ;;
                ID_LIKE) raw_like="$REPLY" ;;
                NAME) name="$REPLY" ;;
                PRETTY_NAME) pretty="$REPLY" ;;
                VERSION_ID) version="$REPLY" ;;
            esac
        done < "$file"
    fi

    # ID and ID_LIKE decide the family, so only the characters os-release(5)
    # allows are accepted (no globbing, no spaces inside a word). They are
    # written out (ID_LOWER, ID_DIGIT: see above), and "I" is changed before
    # lowering the rest because ${x,,} turns it into "ı" in tr_TR.
    raw_id="${raw_id//I/i}" raw_like="${raw_like//I/i}"
    raw_id="${raw_id,,}"
    [[ "$raw_id" =~ ^[${ID_LOWER}${ID_DIGIT}._-]+$ ]] && SYS_ID="$raw_id"
    read -r -a tokens <<< "${raw_like,,}"
    for token in "${tokens[@]+"${tokens[@]}"}"; do
        [[ "$token" =~ ^[${ID_LOWER}${ID_DIGIT}._-]+$ ]] && SYS_ID_LIKE+="${SYS_ID_LIKE:+ }$token"
    done

    # Name to show: PRETTY_NAME, else NAME + VERSION_ID, else the ID.
    pretty="$(sanitize_display "$pretty")"
    if [ -z "$pretty" ]; then
        name="$(sanitize_display "$name")"
        version="$(sanitize_display "$version")"
        pretty="$name"
        if [ -n "$name" ] && [ -n "$version" ]; then pretty="$name $version"; fi
        if [ -z "$pretty" ]; then pretty="$SYS_ID"; fi
    fi
    pretty="${pretty#"${pretty%%[![:space:]]*}"}"
    pretty="${pretty%"${pretty##*[![:space:]]}"}"
    SYS_PRETTY="$pretty"

    # Short label: without the trailing "(codename)", at most 22 characters.
    label="${pretty%% (*}"
    label="${label%"${label##*[![:space:]]}"}"
    if [ -z "$label" ]; then label="$pretty"; fi
    if [ "${#label}" -gt 22 ]; then label="${label:0:19}..."; fi
    SYS_LABEL="$label"

    # Family = package-manager lineage: the first known word of ID, ID_LIKE.
    read -r -a tokens <<< "$SYS_ID $SYS_ID_LIKE"
    for token in "${tokens[@]+"${tokens[@]}"}"; do
        case "$token" in
            debian|ubuntu|linuxmint|raspbian|devuan) SYS_FAMILY="debian" ;;
            fedora|rhel|centos|rocky|almalinux|ol|amzn) SYS_FAMILY="fedora" ;;
            arch|archlinux|archarm|manjaro|endeavouros) SYS_FAMILY="arch" ;;
            suse|sles|sled|opensuse|opensuse-*) SYS_FAMILY="suse" ;;
            *) continue ;;
        esac
        break
    done

    # Desktop: the first recognized word of XDG_CURRENT_DESKTOP, which is a
    # colon-separated list ("ubuntu:GNOME", "X-Cinnamon"). Only the fixed names
    # below are ever stored, never the raw value.
    IFS=: read -r -a tokens <<< "${XDG_CURRENT_DESKTOP:-}"
    for token in "${tokens[@]+"${tokens[@]}"}"; do
        case "${token,,}" in
            x-cinnamon|cinnamon) SYS_DESKTOP="cinnamon" ;;
            gnome) SYS_DESKTOP="gnome" ;;
            kde) SYS_DESKTOP="kde" ;;
            xfce) SYS_DESKTOP="xfce" ;;
            mate) SYS_DESKTOP="mate" ;;
            *) continue ;;
        esac
        break
    done

    load_desktop_lists
    WT_TITLE="$(app_title)"
}

# The title is the program name only: the interface speaks of "Linux" in
# general. The detected system (SYS_*) is kept for the catalogs, not for show.
app_title() {
    msg title
}

# Backtitle of the dialogs: program name and version.
app_backtitle() {
    printf '%s %s' "$(app_title)" "$MINTAPP_VERSION"
}

catalog_name() {
    local key="$1" value
    if [ "$APP_LANG" = "es" ]; then
        value="${APP_NAME_ES[$key]}"
    else
        value="${APP_NAME_EN[$key]}"
    fi
    if [ "$UNICODE" -eq 0 ]; then
        ascii_fold "$value"
        value="$REPLY"
    fi
    printf '%s' "$value"
}

catalog_desc() {
    local key="$1" value
    if [ "$APP_LANG" = "es" ]; then
        value="${APP_DESC_ES[$key]}"
    else
        value="${APP_DESC_EN[$key]}"
    fi
    if [ "$UNICODE" -eq 0 ]; then
        ascii_fold "$value"
        value="$REPLY"
    fi
    printf '%s' "$value"
}

count_detected() {
    local count="$1"
    if [ "$count" -eq 1 ]; then
        printf '%s' "$(msg detected_count_1)"
    else
        printf '%s' "$(msg detected_count_n)"
    fi
}

count_unmanaged() {
    local count="$1" text
    if [ "$count" -eq 1 ]; then
        msgf_v text advanced_unmanaged_1 "$count"
    else
        msgf_v text advanced_unmanaged_n "$count"
    fi
    printf '%s' "$text"
}

# ----------------------------------------------------------------------------
# Internal list of candidate applications
# Format: "key|desktops|package1,package2"
# desktops is "*" (every desktop) or the desktops that ship the application,
# separated by spaces: cinnamon gnome kde xfce mate. An application whose
# packages are not installed is never shown, so the list only has to say where
# it is a stock application. load_desktop_lists derives CATALOG, the list in
# use, from this one.
# ----------------------------------------------------------------------------
CATALOG_ALL=(
    "firefox|*|firefox"
    "thunderbird|*|thunderbird"
    "libreoffice|*|libreoffice,libreoffice-core,libreoffice-writer,libreoffice-calc,libreoffice-impress,libreoffice-draw,libreoffice-base,libreoffice-math"
    # Linux Mint (Cinnamon, MATE and XFCE editions) and Cinnamon
    "calculator|cinnamon gnome xfce|gnome-calculator"
    "calendar|cinnamon gnome|gnome-calendar"
    "document_viewer|cinnamon mate xfce|xreader"
    "document_scanner|cinnamon gnome mate xfce|simple-scan"
    "webapp_manager|cinnamon mate xfce|webapp-manager"
    "warpinator|cinnamon mate xfce|warpinator"
    "transmission|cinnamon gnome mate xfce|transmission-gtk"
    "hypnotix|cinnamon mate xfce|hypnotix"
    "rhythmbox|cinnamon gnome mate|rhythmbox"
    "celluloid|cinnamon mate xfce|celluloid"
    "pix|cinnamon mate xfce|pix"
    "drawing|cinnamon mate xfce|drawing"
    "image_viewer|cinnamon mate xfce|xviewer"
    "text_editor|cinnamon mate xfce|xed"
    "archive_manager|cinnamon gnome xfce|file-roller"
    "sticky_notes|cinnamon mate xfce|sticky"
    "character_map|cinnamon mate xfce|gucharmap"
    "backup_tool|cinnamon mate xfce|mintbackup"
    "usb_tools|cinnamon mate xfce|mintstick"
    "disks|cinnamon gnome mate xfce|gnome-disk-utility"
    "disk_usage_analyzer|cinnamon gnome xfce|baobab"
    "system_monitor|cinnamon gnome|gnome-system-monitor"
    # GNOME (Ubuntu, Debian)
    "evince|gnome|evince"
    "eog|gnome|eog"
    "totem|gnome|totem"
    "shotwell|gnome|shotwell"
    "gnome_text_editor|gnome|gnome-text-editor"
    "gedit|gnome|gedit"
    "gnome_characters|gnome|gnome-characters"
    "gnome_clocks|gnome|gnome-clocks"
    "gnome_contacts|gnome|gnome-contacts"
    "gnome_weather|gnome|gnome-weather"
    "gnome_maps|gnome|gnome-maps"
    "gnome_music|gnome|gnome-music"
    "gnome_screenshot|gnome|gnome-screenshot"
    "cheese|gnome|cheese"
    "remmina|gnome|remmina"
    "deja_dup|gnome|deja-dup"
    "usb_creator|gnome|usb-creator-gtk"
    "aisleriot|gnome|aisleriot"
    "gnome_mines|gnome xfce|gnome-mines"
    "gnome_sudoku|gnome xfce|gnome-sudoku"
    "yelp|gnome mate|yelp"
    "gnome_font_viewer|gnome xfce|gnome-font-viewer"
    "gnome_logs|gnome|gnome-logs"
    "gnome_power_statistics|gnome|gnome-power-manager"
    "seahorse|gnome mate|seahorse"
    "gnome_snapshot|gnome|gnome-snapshot"
    "loupe|gnome|loupe"
    "gnome_mahjongg|gnome|gnome-mahjongg"
    "gnome_tour|gnome|gnome-tour"
    "gnome_connections|gnome|gnome-connections"
    "evolution|gnome mate|evolution"
    # KDE Plasma
    "kcalc|kde|kcalc"
    "okular|kde|okular"
    "kate|kde|kate"
    "kwrite|kde|kwrite"
    "gwenview|kde|gwenview"
    "ark|kde|ark"
    "kcharselect|kde|kcharselect"
    "spectacle|kde|spectacle,kde-spectacle"
    "kdeconnect|kde|kdeconnect"
    "elisa|kde|elisa"
    "kolourpaint|kde|kolourpaint"
    "skanpage|kde|skanpage"
    "skanlite|kde|skanlite"
    "filelight|kde|filelight"
    "partitionmanager|kde|partitionmanager"
    "plasma_systemmonitor|kde|plasma-systemmonitor"
    "haruna|kde|haruna"
    "kmahjongg|kde|kmahjongg"
    "kmines|kde|kmines"
    "kpat|kde|kpat"
    "ksudoku|kde|ksudoku"
    "konversation|kde|konversation"
    "krdc|kde|krdc"
    "kwalletmanager|kde|kwalletmanager"
    "ksystemlog|kde|ksystemlog"
    "neochat|kde|neochat"
    "kamoso|kde|kamoso"
    # XFCE (Xubuntu, Debian)
    "mousepad|xfce|mousepad"
    "ristretto|xfce|ristretto"
    "parole|xfce|parole"
    "atril|mate xfce|atril"
    "xfce_screenshooter|xfce|xfce4-screenshooter"
    "xfce_taskmanager|xfce|xfce4-taskmanager"
    "xfce_notes|xfce|xfce4-notes"
    "xfburn|xfce|xfburn"
    "catfish|xfce|catfish"
    "xarchiver|xfce|xarchiver"
    "orage|xfce|orage"
    "abiword|xfce|abiword"
    "gnumeric|xfce|gnumeric"
    "gigolo|xfce|gigolo"
    "gimp|xfce|gimp"
    "hexchat|xfce|hexchat"
    "menulibre|xfce|menulibre"
    "mugshot|xfce|mugshot"
    "xfce_dictionary|xfce|xfce4-dict"
    # MATE (Ubuntu MATE, Debian)
    "pluma|mate|pluma"
    "eom|mate|eom"
    "engrampa|mate|engrampa"
    "mate_calc|mate|mate-calc"
    "mate_system_monitor|mate|mate-system-monitor"
    "mate_user_guide|mate|mate-user-guide"
    "mate_utils|mate|mate-utils"
    "mozo|mate|mozo"
)
readonly CATALOG_ALL

declare -A APP_NAME_ES=(
    [firefox]="Firefox"
    [thunderbird]="Thunderbird"
    [libreoffice]="LibreOffice"
    [calculator]="Calculadora"
    [calendar]="Calendario"
    [document_viewer]="Visor de documentos"
    [document_scanner]="Escáner de documentos"
    [webapp_manager]="Gestor de aplicaciones web"
    [warpinator]="Warpinator"
    [transmission]="Transmission"
    [hypnotix]="Hypnotix"
    [rhythmbox]="Rhythmbox"
    [celluloid]="Celluloid"
    [pix]="Pix"
    [drawing]="Dibujo"
    [image_viewer]="Visor de imágenes"
    [text_editor]="Editor de texto"
    [archive_manager]="Gestor de archivos comprimidos"
    [sticky_notes]="Notas adhesivas"
    [character_map]="Mapa de caracteres"
    [backup_tool]="Herramienta de copias de seguridad personales"
    [usb_tools]="Herramientas USB (grabador de imágenes y formateador)"
    [disks]="Discos"
    [disk_usage_analyzer]="Analizador de uso de disco"
    [system_monitor]="Monitor del sistema"
    # GNOME
    [evince]="Evince"
    [eog]="Eye of GNOME"
    [totem]="Totem"
    [shotwell]="Shotwell"
    [gnome_text_editor]="Editor de texto de GNOME"
    [gedit]="gedit"
    [gnome_characters]="Caracteres"
    [gnome_clocks]="Relojes"
    [gnome_contacts]="Contactos"
    [gnome_weather]="El tiempo"
    [gnome_maps]="Mapas"
    [gnome_music]="Música de GNOME"
    [gnome_screenshot]="Captura de pantalla de GNOME"
    [cheese]="Cheese"
    [remmina]="Remmina"
    [deja_dup]="Deja Dup"
    [usb_creator]="Creador de discos de arranque"
    [aisleriot]="AisleRiot Solitaire"
    [gnome_mines]="Minas"
    [gnome_sudoku]="Sudoku"
    [yelp]="Ayuda"
    [gnome_font_viewer]="Fuentes"
    [gnome_logs]="Registros"
    [gnome_power_statistics]="Estadísticas de energía"
    [seahorse]="Contraseñas y claves"
    [gnome_snapshot]="Snapshot"
    [loupe]="Loupe"
    [gnome_mahjongg]="Mahjongg"
    [gnome_tour]="Tour de GNOME"
    [gnome_connections]="Conexiones"
    [evolution]="Evolution"
    # KDE Plasma
    [kcalc]="KCalc"
    [okular]="Okular"
    [kate]="Kate"
    [kwrite]="KWrite"
    [gwenview]="Gwenview"
    [ark]="Ark"
    [kcharselect]="KCharSelect"
    [spectacle]="Spectacle"
    [kdeconnect]="KDE Connect"
    [elisa]="Elisa"
    [kolourpaint]="KolourPaint"
    [skanpage]="Skanpage"
    [skanlite]="Skanlite"
    [filelight]="Filelight"
    [partitionmanager]="Gestor de particiones de KDE"
    [plasma_systemmonitor]="Monitor del sistema de Plasma"
    [haruna]="Haruna"
    [kmahjongg]="KMahjongg"
    [kmines]="KMines"
    [kpat]="KPatience"
    [ksudoku]="KSudoku"
    [konversation]="Konversation"
    [krdc]="KRDC"
    [kwalletmanager]="KWalletManager"
    [ksystemlog]="KSystemLog"
    [neochat]="NeoChat"
    [kamoso]="Kamoso"
    # XFCE
    [mousepad]="Mousepad"
    [ristretto]="Ristretto"
    [parole]="Parole"
    [atril]="Atril"
    [xfce_screenshooter]="Captura de pantalla de Xfce"
    [xfce_taskmanager]="Administrador de tareas de Xfce"
    [xfce_notes]="Notas de Xfce"
    [xfburn]="Xfburn"
    [catfish]="Catfish"
    [xarchiver]="Xarchiver"
    [orage]="Orage"
    [abiword]="AbiWord"
    [gnumeric]="Gnumeric"
    [gigolo]="Gigolo"
    [gimp]="GIMP"
    [hexchat]="HexChat"
    [menulibre]="MenuLibre"
    [mugshot]="Mugshot"
    [xfce_dictionary]="Diccionario de Xfce"
    # MATE
    [pluma]="Pluma"
    [eom]="Eye of MATE"
    [engrampa]="Engrampa"
    [mate_calc]="Calculadora de MATE"
    [mate_system_monitor]="Monitor del sistema de MATE"
    [mate_user_guide]="Guía del usuario de MATE"
    [mate_utils]="Utilidades de MATE"
    [mozo]="Mozo"
)

declare -A APP_NAME_EN=(
    [firefox]="Firefox"
    [thunderbird]="Thunderbird"
    [libreoffice]="LibreOffice"
    [calculator]="Calculator"
    [calendar]="Calendar"
    [document_viewer]="Document Viewer"
    [document_scanner]="Document Scanner"
    [webapp_manager]="Web App Manager"
    [warpinator]="Warpinator"
    [transmission]="Transmission"
    [hypnotix]="Hypnotix"
    [rhythmbox]="Rhythmbox"
    [celluloid]="Celluloid"
    [pix]="Pix"
    [drawing]="Drawing"
    [image_viewer]="Image Viewer"
    [text_editor]="Text Editor"
    [archive_manager]="Archive Manager"
    [sticky_notes]="Sticky Notes"
    [character_map]="Character Map"
    [backup_tool]="Backup Tool"
    [usb_tools]="USB Tools (USB Image Writer + USB Stick Formatter)"
    [disks]="Disks"
    [disk_usage_analyzer]="Disk Usage Analyzer"
    [system_monitor]="System Monitor"
    # GNOME
    [evince]="Evince"
    [eog]="Eye of GNOME"
    [totem]="Totem"
    [shotwell]="Shotwell"
    [gnome_text_editor]="GNOME Text Editor"
    [gedit]="gedit"
    [gnome_characters]="Characters"
    [gnome_clocks]="Clocks"
    [gnome_contacts]="Contacts"
    [gnome_weather]="Weather"
    [gnome_maps]="Maps"
    [gnome_music]="GNOME Music"
    [gnome_screenshot]="GNOME Screenshot"
    [cheese]="Cheese"
    [remmina]="Remmina"
    [deja_dup]="Deja Dup"
    [usb_creator]="Startup Disk Creator"
    [aisleriot]="AisleRiot Solitaire"
    [gnome_mines]="Mines"
    [gnome_sudoku]="Sudoku"
    [yelp]="Help"
    [gnome_font_viewer]="Fonts"
    [gnome_logs]="Logs"
    [gnome_power_statistics]="Power Statistics"
    [seahorse]="Passwords and Keys"
    [gnome_snapshot]="Snapshot"
    [loupe]="Loupe"
    [gnome_mahjongg]="Mahjongg"
    [gnome_tour]="GNOME Tour"
    [gnome_connections]="Connections"
    [evolution]="Evolution"
    # KDE Plasma
    [kcalc]="KCalc"
    [okular]="Okular"
    [kate]="Kate"
    [kwrite]="KWrite"
    [gwenview]="Gwenview"
    [ark]="Ark"
    [kcharselect]="KCharSelect"
    [spectacle]="Spectacle"
    [kdeconnect]="KDE Connect"
    [elisa]="Elisa"
    [kolourpaint]="KolourPaint"
    [skanpage]="Skanpage"
    [skanlite]="Skanlite"
    [filelight]="Filelight"
    [partitionmanager]="KDE Partition Manager"
    [plasma_systemmonitor]="Plasma System Monitor"
    [haruna]="Haruna"
    [kmahjongg]="KMahjongg"
    [kmines]="KMines"
    [kpat]="KPatience"
    [ksudoku]="KSudoku"
    [konversation]="Konversation"
    [krdc]="KRDC"
    [kwalletmanager]="KWalletManager"
    [ksystemlog]="KSystemLog"
    [neochat]="NeoChat"
    [kamoso]="Kamoso"
    # XFCE
    [mousepad]="Mousepad"
    [ristretto]="Ristretto"
    [parole]="Parole"
    [atril]="Atril"
    [xfce_screenshooter]="Xfce Screenshot"
    [xfce_taskmanager]="Xfce Task Manager"
    [xfce_notes]="Xfce Notes"
    [xfburn]="Xfburn"
    [catfish]="Catfish"
    [xarchiver]="Xarchiver"
    [orage]="Orage"
    [abiword]="AbiWord"
    [gnumeric]="Gnumeric"
    [gigolo]="Gigolo"
    [gimp]="GIMP"
    [hexchat]="HexChat"
    [menulibre]="MenuLibre"
    [mugshot]="Mugshot"
    [xfce_dictionary]="Xfce Dictionary"
    # MATE
    [pluma]="Pluma"
    [eom]="Eye of MATE"
    [engrampa]="Engrampa"
    [mate_calc]="MATE Calculator"
    [mate_system_monitor]="MATE System Monitor"
    [mate_user_guide]="MATE User Guide"
    [mate_utils]="MATE Utilities"
    [mozo]="Mozo"
)

declare -A APP_DESC_ES=(
    [firefox]="Navegador web"
    [thunderbird]="Cliente de correo electrónico"
    [libreoffice]="Suite ofimática"
    [calculator]="Calculadora"
    [calendar]="Calendario"
    [document_viewer]="Visor de documentos"
    [document_scanner]="Escáner de documentos e imágenes"
    [webapp_manager]="Crear aplicaciones web"
    [warpinator]="Compartir archivos en red local"
    [transmission]="Cliente BitTorrent"
    [hypnotix]="Cliente IPTV"
    [rhythmbox]="Reproductor de música"
    [celluloid]="Reproductor de vídeo"
    [pix]="Organizador de fotografías"
    [drawing]="Editor sencillo de imágenes"
    [image_viewer]="Visor de imágenes"
    [text_editor]="Editor de texto"
    [archive_manager]="Gestor de archivos comprimidos"
    [sticky_notes]="Notas adhesivas"
    [character_map]="Mapa de caracteres"
    [backup_tool]="Herramienta de copias de seguridad personales"
    [usb_tools]="Grabar imágenes ISO y formatear memorias USB"
    [disks]="Gestión de discos y particiones"
    [disk_usage_analyzer]="Analizador de uso de disco"
    [system_monitor]="Monitor de procesos y recursos"
    # GNOME
    [evince]="Visor de documentos"
    [eog]="Visor de imágenes"
    [totem]="Reproductor de vídeo"
    [shotwell]="Organizador de fotografías"
    [gnome_text_editor]="Editor de texto"
    [gedit]="Editor de texto"
    [gnome_characters]="Buscar e insertar caracteres especiales"
    [gnome_clocks]="Relojes del mundo, alarmas y temporizadores"
    [gnome_contacts]="Libreta de direcciones"
    [gnome_weather]="Previsión meteorológica"
    [gnome_maps]="Mapas y rutas"
    [gnome_music]="Reproductor de música"
    [gnome_screenshot]="Capturar la pantalla"
    [cheese]="Fotos y vídeos con la cámara web"
    [remmina]="Cliente de escritorio remoto"
    [deja_dup]="Copias de seguridad de archivos personales"
    [usb_creator]="Crear memorias USB de arranque"
    [aisleriot]="Juegos de cartas de solitario"
    [gnome_mines]="Juego del buscaminas"
    [gnome_sudoku]="Juego de sudokus"
    [yelp]="Visor de documentación"
    [gnome_font_viewer]="Ver y comparar las fuentes instaladas"
    [gnome_logs]="Visor de los registros del sistema"
    [gnome_power_statistics]="Historial de la batería y del consumo"
    [seahorse]="Gestionar contraseñas y claves de cifrado"
    [gnome_snapshot]="Fotos y vídeos con la cámara web"
    [loupe]="Visor de imágenes"
    [gnome_mahjongg]="Juego de solitario con fichas"
    [gnome_tour]="Introducción guiada al escritorio"
    [gnome_connections]="Cliente de escritorio remoto"
    [evolution]="Correo, calendario y contactos"
    # KDE Plasma
    [kcalc]="Calculadora"
    [okular]="Visor de documentos"
    [kate]="Editor de texto"
    [kwrite]="Editor de texto sencillo"
    [gwenview]="Visor de imágenes"
    [ark]="Gestor de archivos comprimidos"
    [kcharselect]="Mapa de caracteres"
    [spectacle]="Herramienta de capturas de pantalla"
    [kdeconnect]="Integración del teléfono con el escritorio"
    [elisa]="Reproductor de música"
    [kolourpaint]="Editor sencillo de imágenes"
    [skanpage]="Escanear documentos"
    [skanlite]="Escanear imágenes"
    [filelight]="Analizador de uso de disco"
    [partitionmanager]="Gestión de discos y particiones"
    [plasma_systemmonitor]="Monitor de procesos y recursos"
    [haruna]="Reproductor de vídeo"
    [kmahjongg]="Juego de solitario con fichas"
    [kmines]="Juego del buscaminas"
    [kpat]="Juegos de cartas de solitario"
    [ksudoku]="Juego de sudokus"
    [konversation]="Cliente de chat IRC"
    [krdc]="Cliente de escritorio remoto"
    [kwalletmanager]="Gestionar las contraseñas guardadas (KWallet)"
    [ksystemlog]="Visor de los registros del sistema"
    [neochat]="Cliente de chat Matrix"
    [kamoso]="Fotos y vídeos con la cámara web"
    # XFCE
    [mousepad]="Editor de texto"
    [ristretto]="Visor de imágenes"
    [parole]="Reproductor multimedia"
    [atril]="Visor de documentos"
    [xfce_screenshooter]="Capturar la pantalla"
    [xfce_taskmanager]="Monitor de procesos y recursos"
    [xfce_notes]="Notas adhesivas"
    [xfburn]="Grabador de CD y DVD"
    [catfish]="Búsqueda de archivos"
    [xarchiver]="Gestor de archivos comprimidos"
    [orage]="Calendario"
    [abiword]="Procesador de textos"
    [gnumeric]="Hoja de cálculo"
    [gigolo]="Gestionar carpetas y unidades remotas"
    [gimp]="Editor de imágenes avanzado"
    [hexchat]="Cliente de chat IRC"
    [menulibre]="Editor del menú de aplicaciones"
    [mugshot]="Editar tu perfil de usuario"
    [xfce_dictionary]="Consultar palabras y definiciones"
    # MATE
    [pluma]="Editor de texto"
    [eom]="Visor de imágenes"
    [engrampa]="Gestor de archivos comprimidos"
    [mate_calc]="Calculadora"
    [mate_system_monitor]="Monitor de procesos y recursos"
    [mate_user_guide]="Documentación del escritorio"
    [mate_utils]="Capturas, diccionario, búsqueda de archivos y registros"
    [mozo]="Editor del menú de aplicaciones"
)

declare -A APP_DESC_EN=(
    [firefox]="Web browser"
    [thunderbird]="Email client"
    [libreoffice]="Office suite"
    [calculator]="Calculator"
    [calendar]="Calendar"
    [document_viewer]="Document viewer"
    [document_scanner]="Scan documents and images"
    [webapp_manager]="Create web applications"
    [warpinator]="Share files on the local network"
    [transmission]="BitTorrent client"
    [hypnotix]="IPTV client"
    [rhythmbox]="Music player"
    [celluloid]="Video player"
    [pix]="Photo organizer"
    [drawing]="Simple image editor"
    [image_viewer]="Image viewer"
    [text_editor]="Text editor"
    [archive_manager]="Archive manager"
    [sticky_notes]="Sticky notes"
    [character_map]="Character map"
    [backup_tool]="Personal backup tool"
    [usb_tools]="Write ISO images and format USB drives"
    [disks]="Disk and partition management"
    [disk_usage_analyzer]="Disk usage analyzer"
    [system_monitor]="Process and resource monitor"
    # GNOME
    [evince]="Document viewer"
    [eog]="Image viewer"
    [totem]="Video player"
    [shotwell]="Photo organizer"
    [gnome_text_editor]="Text editor"
    [gedit]="Text editor"
    [gnome_characters]="Find and insert special characters"
    [gnome_clocks]="World clocks, alarms and timers"
    [gnome_contacts]="Address book"
    [gnome_weather]="Weather forecast"
    [gnome_maps]="Maps and routes"
    [gnome_music]="Music player"
    [gnome_screenshot]="Capture the screen"
    [cheese]="Webcam photos and videos"
    [remmina]="Remote desktop client"
    [deja_dup]="Back up personal files"
    [usb_creator]="Create bootable USB drives"
    [aisleriot]="Solitaire card games"
    [gnome_mines]="Minesweeper game"
    [gnome_sudoku]="Sudoku puzzle game"
    [yelp]="Documentation browser"
    [gnome_font_viewer]="View and compare installed fonts"
    [gnome_logs]="System log viewer"
    [gnome_power_statistics]="Battery and power usage history"
    [seahorse]="Manage passwords and encryption keys"
    [gnome_snapshot]="Webcam photos and videos"
    [loupe]="Image viewer"
    [gnome_mahjongg]="Tile-matching solitaire game"
    [gnome_tour]="Guided introduction to the desktop"
    [gnome_connections]="Remote desktop client"
    [evolution]="Email, calendar and contacts"
    # KDE Plasma
    [kcalc]="Calculator"
    [okular]="Document viewer"
    [kate]="Text editor"
    [kwrite]="Simple text editor"
    [gwenview]="Image viewer"
    [ark]="Archive manager"
    [kcharselect]="Character map"
    [spectacle]="Screenshot tool"
    [kdeconnect]="Phone and desktop integration"
    [elisa]="Music player"
    [kolourpaint]="Simple image editor"
    [skanpage]="Scan documents"
    [skanlite]="Scan images"
    [filelight]="Disk usage analyzer"
    [partitionmanager]="Disk and partition management"
    [plasma_systemmonitor]="Process and resource monitor"
    [haruna]="Video player"
    [kmahjongg]="Tile-matching solitaire game"
    [kmines]="Minesweeper game"
    [kpat]="Solitaire card games"
    [ksudoku]="Sudoku puzzle game"
    [konversation]="IRC chat client"
    [krdc]="Remote desktop client"
    [kwalletmanager]="Manage saved passwords (KWallet)"
    [ksystemlog]="System log viewer"
    [neochat]="Matrix chat client"
    [kamoso]="Webcam photos and videos"
    # XFCE
    [mousepad]="Text editor"
    [ristretto]="Image viewer"
    [parole]="Media player"
    [atril]="Document viewer"
    [xfce_screenshooter]="Capture the screen"
    [xfce_taskmanager]="Process and resource monitor"
    [xfce_notes]="Sticky notes"
    [xfburn]="CD and DVD burner"
    [catfish]="File search"
    [xarchiver]="Archive manager"
    [orage]="Calendar"
    [abiword]="Word processor"
    [gnumeric]="Spreadsheet"
    [gigolo]="Manage remote folders and drives"
    [gimp]="Advanced image editor"
    [hexchat]="IRC chat client"
    [menulibre]="Application menu editor"
    [mugshot]="Edit your user profile"
    [xfce_dictionary]="Look up words and definitions"
    # MATE
    [pluma]="Text editor"
    [eom]="Image viewer"
    [engrampa]="Archive manager"
    [mate_calc]="Calculator"
    [mate_system_monitor]="Process and resource monitor"
    [mate_user_guide]="Desktop documentation"
    [mate_utils]="Screenshots, dictionary, file search and logs"
    [mozo]="Application menu editor"
)

# Arrays filled after detection
DETECTED_NAMES=()
DETECTED_KEYS=()
DETECTED_PACKAGES=()
DETECTED_DESC=()
DETECTION_DONE=0

# ----------------------------------------------------------------------------
# Advanced mode (Option 3): blacklist of system components.
# Unlike CATALOG (a whitelist), the starting universe here is "all menu
# launchers", so anything clearly part of the system is excluded by pattern.
# It is one layer, not the only one: it is complemented by the protection of
# the manager (pm_protected) and by its real simulation (pm_simulate) before
# confirming.
# Format: "desktops|pattern", with desktops as in CATALOG_ALL. "*" patterns are
# system components on any desktop; the others are the session, file manager,
# settings and software center of one desktop. Each pattern names the package
# that owns a launcher and is no wider than needed ("xfce4-*" would hide
# applications the user may want to remove). load_desktop_lists derives
# EXCLUDED_PATTERNS, the list in use, from this one.
# ----------------------------------------------------------------------------
EXCLUDED_ALL=(
    # Any desktop: login screens, privileges, package management, network,
    # services, audio, printing, terminals, input methods, Mint and Ubuntu
    "*|gdm3*" "*|lightdm*" "*|slick-greeter*" "*|sddm*"
    "*|policykit-1*" "*|polkit*" "*|gksu*" "*|pkexec*"
    "*|synaptic*" "*|gdebi*" "*|software-properties*" "*|update-manager*" "*|update-notifier*"
    "*|apt" "*|apt-*" "*|dpkg" "*|dpkg-*" "*|snapd*"
    "*|dnf*" "*|rpm" "*|rpm-*" "*|pacman-*" "*|pamac*" "*|octopi*"
    "*|zypper" "*|zypper-*" "*|libzypp*" "*|yast2*"
    "*|gufw*" "*|ufw*" "*|network-manager*" "*|nm-*"
    "*|systemd*" "*|udisks2*" "*|gparted*" "*|blueman*" "*|timeshift*"
    "*|pulseaudio*" "*|pipewire*"
    "*|cups*" "*|system-config-printer*" "*|printer-driver*"
    "*|gnome-terminal*" "*|xfce4-terminal*" "*|mate-terminal*" "*|konsole*" "*|xterm*"
    "*|language-selector*" "*|im-config*" "*|ibus*"
    "*|mint*" "*|xapp*" "*|ubuntu-*"
    # Cinnamon
    "cinnamon|cinnamon*" "cinnamon|muffin*" "cinnamon|cjs*" "cinnamon|nemo*"
    # Cinnamon (it uses the GNOME ones) and GNOME
    "cinnamon gnome|gnome-control-center*" "cinnamon gnome|gnome-shell*"
    "cinnamon gnome|gnome-session*" "cinnamon gnome|gnome-settings-daemon*"
    # GNOME
    "gnome|gnome-initial-setup*" "gnome|gnome-keyring*" "gnome|gnome-online-accounts*"
    "gnome|gnome-software*" "gnome|mutter*" "gnome|nautilus*"
    # KDE Plasma
    "kde|plasma-desktop*" "kde|plasma-workspace*" "kde|plasma-discover*" "kde|plasma-nm*"
    "kde|plasma-pa*" "kde|plasma-integration*" "kde|plasma-firewall*" "kde|plasma-thunderbolt*"
    "kde|kde-*" "kde|kwin*" "kde|kscreen*" "kde|kinfocenter*" "kde|systemsettings*"
    "kde|dolphin*" "kde|kmenuedit*" "kde|khotkeys*" "kde|kdeplasma-addons*" "kde|bluedevil*"
    "kde|print-manager*" "kde|kubuntu-*"
    # XFCE
    "xfce|xfce4-session*" "xfce|xfce4-settings*" "xfce|xfce4-panel*"
    "xfce|xfce4-appfinder*" "xfce|xfce4-power-manager*" "xfce|xfce4-notifyd*"
    "xfce|xfce4-screensaver*" "xfce|xfce4-whiskermenu-plugin*" "xfce|xfdesktop4*"
    "xfce|xfwm4*" "xfce|xfconf*" "xfce|thunar*" "xfce|exo-utils*" "xfce|garcon*"
    "xfce|tumbler*" "xfce|light-locker*" "xfce|xubuntu-*"
    # MATE
    "mate|mate-session-manager*" "mate|mate-settings-daemon*" "mate|mate-control-center*"
    "mate|mate-panel*" "mate|mate-desktop*" "mate|mate-menu*" "mate|mate-power-manager*"
    "mate|mate-notification-daemon*" "mate|mate-screensaver*" "mate|mate-media*"
    "mate|mate-polkit*" "mate|mate-applets*" "mate|mate-indicator-applet*"
    "mate|caja*" "mate|marco*"
)
readonly EXCLUDED_ALL

# The lists in use, filled by load_desktop_lists.
CATALOG=()
EXCLUDED_PATTERNS=()

# Succeeds if the "desktops" field $1 of CATALOG_ALL or EXCLUDED_ALL covers the
# detected desktop. An unrecognized desktop (SYS_DESKTOP is "other") is covered
# by every field: it detects every catalog and excludes every pattern.
desktop_applies() {
    local word
    [ "$1" = "*" ] && return 0
    [ "$SYS_DESKTOP" = "other" ] && return 0
    for word in $1; do
        [ "$word" = "$SYS_DESKTOP" ] && return 0
    done
    return 1
}

# Fills CATALOG ("key|packages") and EXCLUDED_PATTERNS with the entries that
# cover the detected desktop. detect_system calls it, so the lists always
# match SYS_DESKTOP.
load_desktop_lists() {
    local entry key rest desktops value
    CATALOG=()
    EXCLUDED_PATTERNS=()
    for entry in "${CATALOG_ALL[@]}"; do
        key="${entry%%|*}" rest="${entry#*|}"
        desktops="${rest%%|*}" value="${rest#*|}"
        if desktop_applies "$desktops"; then CATALOG+=("$key|$value"); fi
    done
    for entry in "${EXCLUDED_ALL[@]}"; do
        desktops="${entry%%|*}" value="${entry#*|}"
        if desktop_applies "$desktops"; then EXCLUDED_PATTERNS+=("$value"); fi
    done
}

detect_system
detect_language

# Arrays filled after scanning launchers (.desktop)
ADV_NAMES=()
ADV_PACKAGES=()
ADV_LINES=()            # one per entry: empty for a package, the plan line of a Flatpak or Snap
ADV_UNMANAGED_NAMES=()
ADV_UNMANAGED_ORIGINS=()
ADV_HAY=()
declare -A SEEN_PKGS=()
declare -A LAUNCHER_OWNERS=()

# ----------------------------------------------------------------------------
# Utilities
# ----------------------------------------------------------------------------
pause() {
    echo
    read -rp "$(msg pause)" _ || true
}

# Prints a line of the glyph $1 as wide as the text screen (see set_text_width).
print_rule() {
    local line
    printf -v line '%*s' "$TEXT_W" ''
    printf '%s\n' "${line// /$1}"
}

# Clears the screen and draws the header of a plain-text screen: the title
# between two heavy rules, as wide as the terminal (at most TEXT_MAX_WIDTH). The
# version ends the title line, dim and aligned to the right edge (the dialogs
# carry it in their backtitle); it is left out when two spaces would not stay
# between it and the title.
header() {
    local title="${1:-$(app_title)}" version="v${MINTAPP_VERSION}" gap
    set_text_width
    clear
    printf '%b' "$C_TITLE"
    print_rule "$SYM_RULE"
    title="${title:0:TEXT_W-1}"
    gap=$(( TEXT_W - 2 - ${#title} - ${#version} ))
    if [ "$gap" -ge 2 ]; then
        printf ' %s%*s%b%s%b%b\n' "$title" "$gap" '' "$C_DIM" "$version" "$C_RESET" "$C_TITLE"
    else
        printf ' %s\n' "$title"
    fi
    print_rule "$SYM_RULE"
    printf '%b\n' "$C_RESET"
}

# A light rule, as wide as the text screen, that separates the parts of a
# screen (the list from its prompt, the plan from its summary).
section_rule() {
    local line
    set_text_width
    printf -v line '%*s' "$TEXT_W" ''
    printf '%b%s%b\n' "$C_TITLE" "${line// /$SYM_LINE}" "$C_RESET"
}

# Plain-text output wrapped to the screen width (see wrap_text: a continuation
# line keeps its line's indentation). Color is applied after wrapping, never
# inside the text, so no escape sequence is ever counted as a column.
# text_wrap prints $1 as it is; text_print also turns \n sequences into line
# breaks (the catalog messages and the dialog texts use them).
text_wrap() {
    set_text_width
    printf '%s\n' "$1" | wrap_text "$TEXT_W"
}

text_print() {
    set_text_width
    printf '%b\n' "$1" | wrap_text "$TEXT_W"
}

# text_print in the color $1: every wrapped line gets its own color and reset.
text_say() {
    local line
    while IFS= read -r line; do
        printf '%b%s%b\n' "$1" "$line" "$C_RESET"
    done < <(text_print "$2")
}

# Prints a plan in plain-text mode, wrapped like text_wrap. The lines that remove
# something get the warning color: the "Purg" and "Remv" lines of a package plan
# (with $2 = all, every line: the plans of Flatpak and Snap have nothing else).
# The manager's own lines stay plain. Each line is wrapped on its own, so the
# text is the same as text_wrap's, with or without color.
text_plan() {
    local line wrapped
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "${2-}" = all ] || [[ "$line" == "Purg "* || "$line" == "Remv "* ]]; then
            while IFS= read -r wrapped; do
                printf '%b%s%b\n' "$C_WARN" "$wrapped" "$C_RESET"
            done < <(text_wrap "$line")
        else
            text_wrap "$line"
        fi
    done <<< "$1"
}

# One option of a plain-text menu (F7.0): the key in green and the label in bold,
# "1. Detect applications". Each part is colored whole and the text is the same
# with or without color, so the width checks never see a sequence.
text_option() {
    printf '%b%s.%b %b%s%b\n' "$C_OK" "$1" "$C_RESET" "$C_BOLD" "$2" "$C_RESET"
}

# Prints the prompt $1 of a plain-text menu in green, followed by a space that
# is not colored, so what is typed is not either. For read -p, which writes it
# as it is (no readline, so no markers around the sequences).
text_prompt() {
    printf '%b%s%b ' "$C_OK" "$1" "$C_RESET"
}

# Prepares the prompt $1 of a plain-text question for read -p, which writes it
# as it is: the terminal would cut a prompt wider than the screen in the middle
# of a word. The prompt is wrapped like the rest of the text: its lines but the
# last are printed now and the last one is left in PROMPT_LAST, one column
# narrower than the screen so that what is typed has room. The space that ends
# a prompt is not wrapped with the text (it would fall on a break and be lost):
# it goes back on the last row, which is wrapped one column narrower again if
# the space would not fit.
PROMPT_LAST=""
wrap_prompt() {
    local -a lines=()
    local i last text="$1" space=""
    set_text_width
    if [[ "$text" == *[[:space:]] ]]; then
        space=" "
        text="${text%"${text##*[![:space:]]}"}"
    fi
    mapfile -t lines < <(printf '%s\n' "$text" | wrap_text $(( TEXT_W - 1 )))
    last=$(( ${#lines[@]} - 1 ))
    if [ -n "$space" ] && [ "${#lines[last]}" -ge $(( TEXT_W - 1 )) ]; then
        mapfile -t lines < <(printf '%s\n' "$text" | wrap_text $(( TEXT_W - 2 )))
        last=$(( ${#lines[@]} - 1 ))
    fi
    for (( i = 0; i < last; i++ )); do printf '%s\n' "${lines[i]}"; done
    PROMPT_LAST="${lines[last]}${space}"
}

# One bullet of a plain-text list, wrapped to the screen width: "  - " opens
# the first line and the continuation lines go under the text, not under the
# dash. One message is one bullet, so no sentence is cut by hand.
text_bullet() {
    local line prefix="  - "
    set_text_width
    while IFS= read -r line; do
        printf '%s%s\n' "$prefix" "$line"
        prefix="    "
    done < <(printf '%s\n' "$1" | wrap_text $(( TEXT_W - 4 )))
}

# Like wrap_text, but a line that needs more than one row never ends with one
# or two words alone on the last row: it is wrapped again, one column narrower
# each time while the number of rows stays the same, and the first width that
# leaves three words or more on the last row is used. It never goes under 20
# columns nor under the longest word with the line's indentation, so narrowing
# never cuts a word the plain wrap kept whole. A width that gives another number
# of rows ends the search: it changed the layout (a hanging indent was lost). If
# no width does, the plain wrap stays.
wrap_even() {
    local width="$1" line try floor word lead _we_n
    local -a _we_rows _we_words
    while IFS= read -r line || [ -n "$line" ]; do
        wrap_line "$width" "$line"
        _we_rows=("${WRAP_ROWS[@]}")
        _we_n="${#_we_rows[@]}"
        read -ra _we_words <<< "${_we_rows[_we_n-1]}"
        if [ "$_we_n" -gt 1 ] && [ "${#_we_words[@]}" -lt 3 ]; then
            lead="${line%%[![:space:]]*}"
            floor=20
            read -ra _we_words <<< "$line"
            for word in "${_we_words[@]+"${_we_words[@]}"}"; do
                [ $(( ${#lead} + ${#word} )) -le "$floor" ] || floor=$(( ${#lead} + ${#word} ))
            done
            for (( try = width - 1; try >= floor; try-- )); do
                wrap_line "$try" "$line"
                [ "${#WRAP_ROWS[@]}" -eq "$_we_n" ] || break
                read -ra _we_words <<< "${WRAP_ROWS[${#WRAP_ROWS[@]}-1]}"
                if [ "${#_we_words[@]}" -ge 3 ]; then _we_rows=("${WRAP_ROWS[@]}"); break; fi
            done
        fi
        printf '%s\n' "${_we_rows[@]}"
    done
}

# text_wrap with wrap_even, for the descriptions: a block of text that reads
# worse with one or two words alone on its last row.
text_wrap_even() {
    set_text_width
    printf '%s\n' "$1" | wrap_even "$TEXT_W"
}

# Prints the text $2 and a newline to the file descriptor $1 (1 or 2), for the
# messages that go out without a screen of their own (the errors of the start
# and the reports of install and uninstall). On a terminal the text is wrapped
# to its width, like the plain-text screens (wrap_even), so the terminal never
# cuts a word at its edge; into a pipe or a file it goes out as it is, one line
# per line of the text. The size is read from that terminal: tput looks at the
# standard input, which may be something else.
print_fit() {
    local fd="$1"
    if [ ! -t "$fd" ]; then
        printf '%s\n' "$2" >&"$fd"
        return 0
    fi
    set_text_width <&"$fd"
    printf '%s\n' "$2" | wrap_even "$TEXT_W" >&"$fd"
}

# print_fit for a text that holds a path: $3 is the path as it stands in the text
# $2 (its first occurrence counts). On a terminal, a path wider than the text
# width, or with spaces (wrap_text takes them for gaps), goes whole on a line of
# its own, at the first column so that only the path is copied; a terminal
# narrower than the path wraps it by itself, which does not harm the copy. The
# text before and after it is wrapped as print_fit does, without the spaces
# that joined it to the path. In any other case this is print_fit.
print_fit_path() {
    local fd="$1" text="$2" path="$3" before after
    if [ -t "$fd" ] && [ -n "$path" ] && [[ "$text" == *"$path"* ]]; then
        set_text_width <&"$fd"
        if [ "${#path}" -gt "$TEXT_W" ] || [[ "$path" == *[[:space:]]* ]]; then
            before="${text%%"$path"*}"
            after="${text#*"$path"}"
            before="${before%"${before##*[![:space:]]}"}"
            after="${after#"${after%%[![:space:]]*}"}"
            {
                [ -z "$before" ] || printf '%s\n' "$before" | wrap_even "$TEXT_W"
                printf '%s\n' "$path"
                [ -z "$after" ] || printf '%s\n' "$after" | wrap_even "$TEXT_W"
            } >&"$fd"
            return 0
        fi
    fi
    print_fit "$fd" "$text"
}

# One entry of a numbered selection list, wrapped to the screen width.
# $1 = number, $2 = check symbol, $3 = name, $4 = label (the package, may be
# empty), $5 = 1 if the entry is marked. A marked entry is a solid block; an
# unmarked one shows its label in the title color when the label stays whole
# on its line. A continuation line is indented under the name.
text_entry() {
    local num="$1" marker="$2" name="$3" label="$4" marked="$5" first=1 line prefix text
    set_text_width
    text="$marker $name"
    [ -z "$label" ] || text+=" $label"
    while IFS= read -r line; do
        if [ "$first" -eq 1 ]; then prefix="  ${num}) "; first=0; else prefix="        "; fi
        if [ "$marked" -eq 1 ]; then
            printf '%s%b %s %b\n' "$prefix" "$C_MARK" "$line" "$C_RESET"
        elif [ -n "$label" ] && [[ "$line" == *"$label" ]]; then
            printf '%s%s%b%s%b\n' "$prefix" "${line%"$label"}" "$C_TITLE" "$label" "$C_RESET"
        else
            printf '%s%s\n' "$prefix" "$line"
        fi
    done < <(printf '%s\n' "$text" | wrap_text $(( TEXT_W - 10 )))
}

# Puts in REPLY the key help of the tui engine. Its main-menu line lists the
# keys the menu really has (G only when there is a graphical menu), padded to
# the 13 columns of the key column.
nav_tui_text() {
    local keys
    build_main_menu
    printf -v keys '%-13s' "${MENU_TAGS[*]}"
    msgf_v REPLY nav_tui "$keys"
}

# ----------------------------------------------------------------------------
# First screen (shown once, before the main menu) with the navigation
# instructions. In the own engine (tui) every key works wherever the focus is;
# in whiptail the reliable method is arrows + TAB + ENTER/SPACE (typing a
# number selects nothing); in plain-text mode typing the number or letter does
# work, because it is our own "read"-based menu. The screen also offers the
# language switch, so a wrong automatic choice is fixable before anything else:
# the "No" button in whiptail, the L key in text mode. Esc, Enter, any other
# key and end of input continue to the menu. Once the person has answered it,
# the configuration records it (help_seen) and main stops showing it at start;
# end of input in text mode is no answer, so it is not recorded.
# ----------------------------------------------------------------------------
show_navigation_help() {
    local prompt answer status
    while true; do
        if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
            if [ "$UI_ENGINE" = "tui" ]; then
                TUI_HOTKEYS="l=1 esc=0"
                nav_tui_text
                wt_yesno "${REPLY}\n\n$(msg nav_zoom)" "$(msg understood)" "$(msg menu_language)" big
            elif [ "$UI_ENGINE" = "gui" ]; then
                wt_yesno "$(msg nav_gui)" "$(msg understood)" "$(msg menu_language)" normal "" choice
            else
                wt_yesno "$(msg nav_whiptail)\n\n$(msg nav_zoom)" "$(msg understood)" "$(msg menu_language)" big
            fi
            status=$?
            mark_help_seen
            [ "$status" -eq 1 ] || return 0
        else
            header "$(msg nav_title)"
            text_wrap "$(msg nav_text)"
            echo
            text_bullet "$(msg nav_text_1)"
            text_bullet "$(msg nav_text_2)"
            echo
            text_wrap "$(msg nav_zoom)"
            echo
            msgf_v prompt nav_text_prompt "$(msg menu_language)"
            wrap_prompt "$prompt "
            read -rp "$PROMPT_LAST" answer || return 0
            mark_help_seen
            [ "${answer,,}" = "l" ] || return 0
        fi
        toggle_language
    done
}

# Succeeds if at least one package of an entry (comma-separated) is installed.
package_installed() {
    local pkgs="$1"
    local IFS=','
    local pkg
    for pkg in $pkgs; do
        if pm_installed "$pkg"; then
            return 0
        fi
    done
    return 1
}

# Given an entry "package1,package2,...", prints (one per line) only the
# packages of that list that are really installed, since some catalog apps
# have more than one possible package name depending on the distribution version.
installed_packages_from_list() {
    local pkgs="$1"
    local IFS=','
    local pkg
    for pkg in $pkgs; do
        if pm_installed "$pkg"; then
            echo "$pkg"
        fi
    done
}

# ----------------------------------------------------------------------------
# Search. Ignores case and accents; several words mean AND; every word is
# matched literally (no wildcards). Accents are folded with an explicit table,
# not with the locale, so a search gives the same result with or without UTF-8.
# ----------------------------------------------------------------------------
# Longest search text kept, in characters.
SEARCH_MAX_LENGTH=64

# "accented=plain" pairs. Capitals are listed too: without a UTF-8 locale
# lowercasing leaves them alone.
SEARCH_FOLD_PAIRS=(
    "á=a" "à=a" "â=a" "ä=a" "ã=a" "å=a" "ā=a" "ă=a" "ą=a" "ç=c" "ć=c" "č=c" "ď=d" "đ=d"
    "é=e" "è=e" "ê=e" "ë=e" "ē=e" "ę=e" "ě=e" "í=i" "ì=i" "î=i" "ï=i" "ī=i" "ł=l"
    "ñ=n" "ń=n" "ň=n" "ó=o" "ò=o" "ô=o" "ö=o" "õ=o" "ø=o" "ō=o" "ő=o" "ŕ=r" "ř=r"
    "ś=s" "š=s" "ş=s" "ť=t" "ú=u" "ù=u" "û=u" "ü=u" "ū=u" "ů=u" "ű=u" "ų=u" "ý=y" "ÿ=y"
    "ź=z" "ż=z" "ž=z" "ß=ss" "æ=ae" "œ=oe"
    "Á=a" "À=a" "Â=a" "Ä=a" "Ã=a" "Å=a" "Ç=c" "Ć=c" "Č=c" "Ď=d" "É=e" "È=e" "Ê=e" "Ë=e"
    "Í=i" "Ì=i" "Î=i" "Ï=i" "Ł=l" "Ñ=n" "Ó=o" "Ò=o" "Ô=o" "Ö=o" "Õ=o" "Ø=o" "Ř=r"
    "Ś=s" "Š=s" "Ú=u" "Ù=u" "Û=u" "Ü=u" "Ý=y" "Ž=z" "Æ=ae" "Œ=oe"
)
# Every accented character in one string: a text without any skips the table.
SEARCH_FOLD_CLASS=""
for _pair in "${SEARCH_FOLD_PAIRS[@]}"; do SEARCH_FOLD_CLASS+="${_pair%%=*}"; done
unset _pair

# Lowercase text without accents, for comparing: puts it in REPLY.
fold_search() {
    local t="${1,,}" pair
    if [[ "$t" == *["$SEARCH_FOLD_CLASS"]* ]]; then
        for pair in "${SEARCH_FOLD_PAIRS[@]}"; do
            t="${t//"${pair%%=*}"/"${pair##*=}"}"
        done
    fi
    REPLY="$t"
}

# Cleans what the user typed into REPLY: no control characters or backslashes
# (they could break a dialog), one space between words, at most
# SEARCH_MAX_LENGTH characters.
clean_query() {
    local t="${1//[[:cntrl:]]/ }"
    local -a words=()
    t="${t//\\/ }"
    read -ra words <<< "$t"
    # One space after every word (none at all gives a single space): the final
    # trim removes it. "${words[*]}" would fail on an empty array in bash 4.3.
    printf -v t '%s ' "${words[@]+"${words[@]}"}"
    t="${t:0:SEARCH_MAX_LENGTH}"
    REPLY="${t%"${t##*[![:space:]]}"}"
}

# Splits a search text into SEARCH_WORDS (folded). $1 = text. No words = all.
SEARCH_WORDS=()
search_prepare() {
    fold_search "$1"
    SEARCH_WORDS=()
    read -ra SEARCH_WORDS <<< "$REPLY"
}

# Succeeds if the folded text $1 contains every word of SEARCH_WORDS.
search_match() {
    local word
    for word in "${SEARCH_WORDS[@]+"${SEARCH_WORDS[@]}"}"; do
        [[ "$1" == *"$word"* ]] || return 1
    done
    return 0
}

# Puts in VISIBLE_IDX the indexes of the entries that match a search.
# $1 = name of the array of folded texts (one per entry), $2 = search text.
VISIBLE_IDX=()
search_filter() {
    local -n _haystacks="$1"
    local i
    search_prepare "$2"
    VISIBLE_IDX=()
    for i in "${!_haystacks[@]}"; do
        if search_match "${_haystacks[$i]}"; then VISIBLE_IDX+=("$i"); fi
    done
}

# Counts the marked entries the current search hides (those not in
# VISIBLE_IDX) and puts the count in REPLY. $1 = name of the marks array
# (0/1 per entry).
search_hidden_marked() {
    local -n _shm_sel="$1"
    local i marked=0 shown=0
    for i in "${!_shm_sel[@]}"; do
        if [ "${_shm_sel[$i]}" -eq 1 ]; then marked=$((marked + 1)); fi
    done
    for i in "${VISIBLE_IDX[@]+"${VISIBLE_IDX[@]}"}"; do
        if [ "${_shm_sel[$i]}" -eq 1 ]; then shown=$((shown + 1)); fi
    done
    REPLY=$((marked - shown))
}

# Puts in REPLY the notice about marked entries a search hides, or nothing when
# none is hidden. $1 = name of the marks array.
search_hidden_notice() {
    local hidden
    search_hidden_marked "$1"
    hidden="$REPLY"
    REPLY=""
    if [ "$hidden" -gt 0 ]; then msgf_v REPLY search_hidden "$hidden"; fi
}

# ----------------------------------------------------------------------------
# Shared UI helpers
# ----------------------------------------------------------------------------

# Shows an informational message with the active interface.
# $1 = text (may contain \n sequences), $2 = "big" for the large box.
show_message() {
    local text="$1" size="${2:-normal}"
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_msgbox "$text" "$size"
    else
        header
        text_print "$text"
        pause
    fi
}

# Asks a yes/no question before a removal. $1 = dialog text, $2 = plain-text
# prompt. In a dialog the "no" button starts active, so a stray Enter cancels.
# Succeeds only on an explicit "yes": y, yes, s, si or sí (either language, any
# case; read already drops surrounding blanks). Anything else, a typo included,
# counts as "no", so a misread answer can never start a removal; an answer that
# is neither yes nor no is reported. End of input counts as "no".
ask_yes_no() {
    local wt_text="$1" prompt="$2" answer
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_yesno "$wt_text" "$(msg yes_remove)" "$(msg cancel)" normal defaultno
        return
    fi
    wrap_prompt "$prompt"
    read -rp "$PROMPT_LAST" answer || return 1
    # "sÍ": without UTF-8 case rules the lowercase form keeps the capital Í.
    case "${answer,,}" in
        y|yes|s|si|sí|sÍ) return 0 ;;
        ""|n|no) return 1 ;;
    esac
    text_wrap "$(msg answer_unknown)"
    return 1
}

# ----------------------------------------------------------------------------
# Plans: every destructive operation (purge, autoremove) is simulated
# first, shown to the user, confirmed, and re-checked right before it runs.
# ----------------------------------------------------------------------------
PLAN_OUTPUT=""

# Removes the NOTE block that apt-get prints before a simulation when it is not
# run as root ("This is only a simulation! ..."). apt translates it, so it is
# recognised by its shape and never by its words: a first line followed by at
# least two lines indented with six spaces, at the very start of the output.
# A plan line (Purg/Remv/Inst/Conf) is never treated as part of that block.
# Reads the apt output on stdin and writes the rest to stdout.
strip_apt_note() {
    local -a lines=()
    local skip=0
    mapfile -t lines
    if [ "${#lines[@]}" -ge 3 ] && [[ "${lines[0]}" != [[:space:]]* ]] \
        && [[ ! "${lines[0]}" =~ ^(Purg|Remv|Inst|Conf)[[:space:]] ]] \
        && [[ "${lines[1]}" == "      "* ]] && [[ "${lines[2]}" == "      "* ]]; then
        skip=1
        while [ "$skip" -lt "${#lines[@]}" ] && [[ "${lines[skip]}" == "      "* ]]; do
            skip=$((skip + 1))
        done
    fi
    [ "$skip" -lt "${#lines[@]}" ] && printf '%s\n' "${lines[@]:skip}"
    return 0
}

# ----------------------------------------------------------------------------
# Administrator rights. The program never runs as root: it asks for them only
# for what changes the system (the removal, the Flatpak and Snap removals and
# the system cleaning) and, with dnf, to calculate the plan; through sudo or,
# if sudo is missing, doas.
# MINTAPP_SUDO=name-or-path forces another compatible command ("env VAR=value
# command" must work with it); an invalid value is an error, never a silent
# fallback to something the user did not choose.
# ----------------------------------------------------------------------------
PRIV_CMD=""

# Finds the privilege command and stores its full path in PRIV_CMD. Fails
# (status 1) if none is usable. Only executable files count: a function, an
# alias or a shell builtin of the same name is ignored.
detect_privilege() {
    local choice="${MINTAPP_SUDO:-}" found=""
    PRIV_CMD=""
    if [ -n "$choice" ]; then
        # A plain command name or a path: no spaces, quotes or shell
        # characters, and nothing that could be read as an option.
        [[ "$choice" =~ ^[A-Za-z0-9_./+][A-Za-z0-9_./+-]*$ ]] || return 1
        found="$(type -P -- "$choice")" || return 1
    else
        found="$(type -P sudo)" || found="$(type -P doas)" || return 1
    fi
    [ -n "$found" ] || return 1
    PRIV_CMD="$found"
}

# Short name of the privilege command, for the hints written in records.
priv_name() {
    local name="${PRIV_CMD##*/}"
    printf '%s' "${name:-sudo}"
}

# Runs "[VAR=value...] COMMAND [ARGS...]" with administrator rights. sudo takes
# the variables directly; any other command gets them through "env", which also
# works with doas (it does not accept VAR=value). Without variables the command
# is passed as it is. In windows sudo asks for the password with -A. Status:
# 127 if there is no privilege command, 2 if nothing was given to run, otherwise
# the status of COMMAND.
priv_run() {
    [ "$#" -gt 0 ] || return 2
    [ -n "$PRIV_CMD" ] || detect_privilege || return 127
    if [ "${PRIV_CMD##*/}" = "sudo" ]; then
        if [ "$UI_ENGINE" = "gui" ] && make_askpass; then
            # No terminal to ask on: -A asks in a window, if sudo needs a password.
            SUDO_ASKPASS="$ASKPASS_HELPER" "$PRIV_CMD" -A "$@"
        else
            "$PRIV_CMD" "$@"
        fi
    elif [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        "$PRIV_CMD" env "$@"
    else
        "$PRIV_CMD" "$@"
    fi
}

# Runs "apt-get ARGS..." with administrator rights and without apt asking
# questions.
apt_privileged() {
    priv_run DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

# ----------------------------------------------------------------------------
# Package manager (4.6). PM is the manager the program works with, and what
# depends on it goes through the pm_* functions. PM_BACKENDS lists the managers
# that have a backend here. MINTAPP_PM=name forces one of them; any other value
# is an error, never a silent fallback to something the user did not choose.
# ----------------------------------------------------------------------------
PM="apt"                # pm_detect (preflight) sets it; code that is only sourced uses apt
PM_BACKENDS="apt dnf pacman zypper"

# Sets PM, in this order: (1) the manager MINTAPP_PM names; (2) the one of the
# distribution family (SYS_FAMILY: debian is apt, fedora is dnf, arch is pacman,
# suse is zypper), if it is in PM_BACKENDS; (3) the first of PM_BACKENDS whose
# tool is in the PATH. Fails (status 1, PM left as apt) if MINTAPP_PM is not one
# of PM_BACKENDS or if nothing is found. A manager chosen by (1) or (2) whose
# tool is missing is not a failure here: preflight_checks says what is missing.
pm_detect() {
    local choice="${MINTAPP_PM:-}" name=""
    PM="apt"
    if [ -n "$choice" ]; then
        [[ "$choice" =~ ^[a-z]+$ ]] || return 1
        case " $PM_BACKENDS " in
            *" $choice "*) PM="$choice"; return 0 ;;
        esac
        return 1
    fi
    case "$SYS_FAMILY" in
        debian) name="apt" ;;
        fedora) name="dnf" ;;
        arch) name="pacman" ;;
        suse) name="zypper" ;;
    esac
    if [ -n "$name" ]; then
        case " $PM_BACKENDS " in
            *" $name "*) PM="$name"; return 0 ;;
        esac
    fi
    for name in $PM_BACKENDS; do
        PM="$name"
        if command -v "$(pm_tool)" >/dev/null 2>&1; then return 0; fi
    done
    PM="apt"
    return 1
}

# The command PM runs, as it is shown in records and errors.
pm_tool() {
    case "$PM" in
        apt) printf 'apt-get' ;;
        dnf) printf 'dnf' ;;
        pacman) printf 'pacman' ;;
        zypper) printf 'zypper' ;;
    esac
}

# $1 = a request as pm_run takes it ("purge foo"): the command line it ran, for
# the records. dnf has no "purge": the same request is "dnf remove foo" (the
# configuration files that rpm keeps are not removed, see pm_run). pacman: purge
# is "pacman -Rcn foo" and autoremove is the usual way to remove the orphans.
# zypper: purge is "zypper remove foo" (rpm has no purge, as with dnf),
# autoremove removes what zypper files as unneeded and clean is "zypper clean".
# shellcheck disable=SC2016  # the $( ) of the autoremove text is shown, not run
pm_operation_text() {
    case "$PM" in
        apt) printf 'apt-get %s' "$1" ;;
        dnf)
            case "$1" in
                purge|"purge "*) printf 'dnf remove%s' "${1#purge}" ;;
                clean|"clean "*) printf 'dnf clean packages%s' "${1#clean}" ;;
                *) printf 'dnf %s' "$1" ;;
            esac ;;
        pacman)
            case "$1" in
                purge|"purge "*) printf 'pacman -Rcn%s' "${1#purge}" ;;
                autoremove) printf 'pacman -Rns $(pacman -Qdtq)' ;;
                clean|"clean "*) printf 'pacman -Sc%s' "${1#clean}" ;;
                *) printf 'pacman %s' "$1" ;;
            esac ;;
        zypper)
            case "$1" in
                purge|"purge "*) printf 'zypper remove%s' "${1#purge}" ;;
                autoremove) printf 'zypper remove --clean-deps (the unneeded packages)' ;;
                clean|"clean "*) printf 'zypper clean%s' "${1#clean}" ;;
                *) printf 'zypper %s' "$1" ;;
            esac ;;
    esac
}

# The start of the command line that reinstalls packages (their names follow),
# for the records.
pm_install_text() {
    case "$PM" in
        apt) printf 'apt-get install' ;;
        dnf) printf 'dnf install' ;;
        pacman) printf 'pacman -S' ;;
        zypper) printf 'zypper install' ;;
    esac
}

# The line a record of an interrupted run carries about the manager's own state
# (nothing if PM has none). dnf: an interrupted transaction can leave duplicate
# or incomplete packages; "dnf check" reports them (it does not repair them).
# pacman: "pacman -Dk" checks that its database is consistent. zypper: "zypper
# verify" checks the dependencies of the installed packages.
pm_interrupt_hint() {
    case "$PM" in
        apt) printf '# If apt reports a broken state, run: %s dpkg --configure -a\n' "$(priv_name)" ;;
        dnf) printf '# If dnf reports a broken state, start with: %s dnf check\n' "$(priv_name)" ;;
        pacman) printf '# If pacman reports a broken state, start with: %s pacman -Dk\n' "$(priv_name)" ;;
        zypper) printf '# If zypper reports a broken state, start with: %s zypper verify\n' "$(priv_name)" ;;
    esac
}

# Runs "ACTION [PACKAGE...]" with administrator rights and without the manager
# asking questions. ACTION is purge, autoremove or clean (the cache of
# downloaded packages). Status: the command's; 2 for an action PM lacks.
# dnf: purge is "dnf remove -y" (rpm has no purge: the configuration files the
# user changed stay as .rpmsave), autoremove is "dnf autoremove -y" and clean is
# "dnf clean packages", which takes no names and so gets none. No "--" is put
# before the names (apt gets none either): they come from the catalog or from
# process_desktop_file, which checks them with pm_valid_name, so none reads as
# an option.
# pacman: purge is "pacman -Rcn --noconfirm" (-c also removes what depends on
# the packages, as apt and dnf do; -n keeps no .pacsave copies), autoremove
# removes the orphans pacman_orphans lists, with their own unused dependencies
# ("pacman -Rns"), and runs nothing if there are none (pacman has no such
# action), and clean is "pacman -Sc --noconfirm" (the cache of packages that are
# no longer installed), which takes no names.
# zypper: purge is "zypper --non-interactive remove" (it removes what depends
# on the packages too, as the plan of pm_simulate shows; no "--clean-deps", so
# the plan is exactly what goes), autoremove is "remove --clean-deps" of what
# zypper_unneeded lists (nothing runs if there is none; zypper has no such
# action) and clean is "zypper --non-interactive clean" (the cache of downloaded
# packages), which takes no names.
pm_run() {
    local action="$1"
    shift
    case "$PM:$action" in
        apt:purge|apt:autoremove) apt_privileged "$action" -y "$@" ;;
        apt:clean) apt_privileged autoclean -y "$@" ;;
        dnf:purge) priv_run dnf remove -y "$@" ;;
        dnf:autoremove) priv_run dnf autoremove -y "$@" ;;
        dnf:clean) priv_run dnf clean packages ;;
        pacman:purge) priv_run pacman -Rcn --noconfirm "$@" ;;
        pacman:autoremove)
            pacman_orphans || return 1
            [ "${#PACMAN_ORPHANS[@]}" -gt 0 ] || return 0
            priv_run pacman -Rns --noconfirm "${PACMAN_ORPHANS[@]}" ;;
        pacman:clean) priv_run pacman -Sc --noconfirm ;;
        zypper:purge) priv_run zypper --non-interactive remove "$@" ;;
        zypper:autoremove)
            zypper_unneeded || return 1
            [ "${#ZYPPER_UNNEEDED[@]}" -gt 0 ] || return 0
            priv_run zypper --non-interactive remove --clean-deps "${ZYPPER_UNNEEDED[@]}" ;;
        zypper:clean) priv_run zypper --non-interactive clean ;;
        *) return 2 ;;
    esac
}

# Simulates "ACTION [PACKAGE...]" (purge or autoremove, as pm_run takes them)
# without changing anything, and stores the plan in PLAN_OUTPUT (the error text
# if the simulation fails). Status: the manager's; 2, with an empty PLAN_OUTPUT,
# for an action PM does not simulate. apt simulates without administrator
# rights, so it never asks for the password before the user confirms the plan.
# dnf refuses to simulate without them, so its backend goes through priv_run:
# the password is asked when the plan is calculated (pm_plan_needs_privileges;
# plan_authorize gets the rights first, plan_password_hint warns). pacman (--print)
# and zypper (--dry-run) need none, like apt. In the plan, each package
# to remove is a line that starts with "Purg " or "Remv " and its name: apt
# prints it that way, and the backend of another manager has to write its plan
# in that shape, because plan_has_removals, plan_fingerprint and
# plan_package_names read it.
pm_simulate() {
    PLAN_OUTPUT=""
    case "$PM:${1-}" in
        apt:purge|apt:autoremove) simulate_apt "$@" ;;
        dnf:purge|dnf:autoremove) simulate_dnf "$@" ;;
        pacman:purge|pacman:autoremove) simulate_pacman "$@" ;;
        zypper:purge|zypper:autoremove) simulate_zypper "$@" ;;
        *) return 2 ;;
    esac
}

# Succeeds if PM needs administrator rights to calculate a plan (dnf; apt, pacman
# and zypper do not). plan_authorize and plan_password_hint read it.
pm_plan_needs_privileges() {
    [ "$PM" = "dnf" ]
}

# Succeeds if the package $1 is really installed, not only its configuration
# files. Status 2 for a manager PM lacks. apt: the exact status
# "install ok installed" is required: a package removed without purge stays
# in "deinstall ok config-files", and "dpkg -s" would still succeed even
# though only residual configuration files remain. The status is captured
# first instead of piped into "grep -q", because under pipefail an early grep
# exit can turn a match into a SIGPIPE failure. dnf and zypper: rpm_installed (rpm has no
# state in which only the configuration files remain). pacman: pacman_installed
# (neither has pacman).
pm_installed() {
    local status
    case "$PM" in
        apt)
            status=$(dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null) || return 1
            grep -qx 'install ok installed' <<< "$status" ;;
        dnf|zypper) rpm_installed "$1" ;;
        pacman) pacman_installed "$1" ;;
        *) return 2 ;;
    esac
}

# Asks the manager who owns each path given as an argument. For every path that
# somebody owns it writes the line "OWNER: /path", where OWNER is the package
# name, several names separated by ", " if many claim the file, or
# "diversion by ..." (dpkg) if the file is diverted; a path nobody owns has no
# line. The status says nothing (dpkg fails when any path has no owner) and
# errors are not shown. Status 2 if there are no paths or for a manager PM lacks.
# dnf and zypper: rpm_owner (rpm has no diversions). pacman: pacman_owner (neither has
# pacman).
pm_owner() {
    [ "$#" -gt 0 ] || return 2
    case "$PM" in
        apt) dpkg -S "$@" 2>/dev/null ;;
        dnf|zypper) rpm_owner "$@" ;;
        pacman) pacman_owner "$@" ;;
        *) return 2 ;;
    esac
}

# Prints, one per line, the packages among $@ that the manager itself files as
# meta-packages: the ones META_PATTERNS cannot tell by their name. A package it
# does not know, or does not file that way, has no line. One question for all
# the names. Status 0, even if it prints nothing; 2 without names or for a
# manager PM lacks. apt: the dpkg sections "metapackages" and "tasks", with or
# without a component before them ("universe/metapackages"). dnf and zypper:
# rpm_meta_packages. pacman: pacman_meta_packages.
pm_meta_packages() {
    [ "$#" -gt 0 ] || return 2
    local name section
    case "$PM" in
        apt)
            while IFS=$'\t' read -r name section; do
                case "${section##*/}" in
                    metapackages|tasks) printf '%s\n' "$name" ;;
                esac
            done < <(dpkg-query -W -f='${Package}\t${Section}\n' -- "$@" 2>/dev/null) ;;
        dnf|zypper) rpm_meta_packages "$@" ;;
        pacman) pacman_meta_packages "$@" ;;
        *) return 2 ;;
    esac
}

# Prints a line "NAME<TAB>VERSION<TAB>SIZE" for each installed package among
# $@: SIZE is what it takes on disk, in KiB. A package the manager does not
# know has no line. One question for all the names. The status is the
# manager's and says nothing about the lines; 2 without names (apt would list
# every package of the system) or for a manager PM lacks. A package installed
# for two architectures has two lines. dnf and zypper: rpm_detail. pacman: pacman_detail.
pm_detail() {
    [ "$#" -gt 0 ] || return 2
    case "$PM" in
        apt) dpkg-query -W -f='${Package}\t${Version}\t${Installed-Size}\n' -- "$@" 2>/dev/null ;;
        dnf|zypper) rpm_detail "$@" ;;
        pacman) pacman_detail "$@" ;;
        *) return 2 ;;
    esac
}

# Succeeds if the manager protects the package $1: the system cannot do
# without it, so the program never offers to remove it. Status 1 if it does
# not, 2 for a manager PM lacks.
# apt: priority required or important, or Essential: yes, in ONE question (a
# package that is not installed is not); the two values are separated by "|"
# because a tab is a blank for "read" and an empty priority would make it drop
# the first field.
# dnf: dnf_protected (it reads files, and the list does not look at what is
# installed).
# pacman: pacman_protected (HoldPkg, also a list that ignores what is installed).
# zypper: zypper_protected (the package locks, which zypper itself will not remove).
pm_protected() {
    local priority="" essential=""
    case "$PM" in
        apt)
            IFS='|' read -r priority essential < <(dpkg-query -W -f='${Priority}|${Essential}\n' -- "$1" 2>/dev/null) || true
            case "$priority" in
                required|important) return 0 ;;
            esac
            [ "$essential" = "yes" ] ;;
        dnf) dnf_protected "$1" ;;
        pacman) pacman_protected "$1" ;;
        zypper) zypper_protected "$1" ;;
        *) return 2 ;;
    esac
}

# The packages that are no longer installed but keep their configuration files,
# one name per line (status 2 if PM has no such state). apt: dpkg's state "rc".
pm_residual() {
    case "$PM" in
        apt) dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null | awk '$1 == "rc" { print $2 }' ;;
        *) return 2 ;;
    esac
}

# Succeeds if $1 can be the name of a package of the manager. Every pattern
# starts with a letter or a digit, so a name that passes cannot look like an
# option to the manager. Status 2 for a manager PM lacks.
# apt: Debian policy (lowercase, at least two characters), with the optional
# ":architecture" that apt prints for foreign packages ("libc6:i386").
# dnf, zypper and pacman: rpm and pacman names can have capitals, "_" and "@".
# At most 255 characters, as for a Flatpak ID.
pm_valid_name() {
    local low="$ID_LOWER$ID_DIGIT" any="$ID_UPPER$ID_LOWER$ID_DIGIT"
    case "$PM" in
        apt) [ "${#1}" -le 255 ] && [[ "$1" =~ ^[${low}][${low}+.-]+(:[${low}-]+)?$ ]] ;;
        dnf|zypper|pacman) [ "${#1}" -le 255 ] && [[ "$1" =~ ^[${any}][${any}+._@-]*$ ]] ;;
        *) return 2 ;;
    esac
}

# ----------------------------------------------------------------------------
# Administrator rights and progress in windows. Without a terminal sudo cannot
# ask for the password, so "sudo -A" runs a small helper that asks in a zenity
# window. While the package manager works a progress window shows its last
# line; the whole output goes to a file, and its last lines go to the error
# window if it fails (there is no terminal above to read them on). doas has no
# such option:
# it needs a permit/nopass rule or a terminal.
# ----------------------------------------------------------------------------
PRIV_STATUS_DENIED=77   # no administrator rights (sysexits EX_NOPERM); no manager uses it
GUI_WORK_DIR=""         # private folder (mode 700): the password helper, the icon and the files of a run
ASKPASS_HELPER=""
ASKPASS_LANG=""         # language of the texts written in the helper
PM_TAIL=""              # last lines of the output of the last package-manager step run in windows
STEP_TAIL=""            # the same for the last step of any command (run_gui_step)
GUI_PROGRESS_PID=""     # the progress window, while it is open
GUI_STOP_TICKS=20       # gui_progress_stop waits this many 0.15 s for the window to end (3 s)

# Puts $1 in REPLY between single quotes, to be written inside a /bin/sh script.
sh_quote() {
    REPLY="'${1//\'/\'\\\'\'}'"
}

# Creates the private folder once. Fails if it cannot be made.
gui_work_dir() {
    [ -n "$GUI_WORK_DIR" ] && [ -d "$GUI_WORK_DIR" ] && return 0
    local base="${XDG_RUNTIME_DIR:-}"
    { [ -n "$base" ] && [ -d "$base" ] && [ -w "$base" ]; } || base="${TMPDIR:-/tmp}"
    GUI_WORK_DIR="$(mktemp -d "${base%/}/mintapp-gui.XXXXXX" 2>/dev/null)" || { GUI_WORK_DIR=""; return 1; }
}

# Writes the password helper and puts its path in ASKPASS_HELPER; it is written
# again only if the language changed. The texts are written into it, quoted, so
# it needs nothing from the environment. It counts the tries (a second one says
# the password was wrong) and exits with status 1 when the window is closed or
# cancelled. /bin/sh has no "exec -a", so the helper starts zenity through bash
# to give the window the class of the others (see gui_cmd).
# shellcheck disable=SC2016  # the helper's own variables are in single quotes on purpose
make_askpass() {
    [ -n "$ASKPASS_HELPER" ] && [ -x "$ASKPASS_HELPER" ] && [ "$ASKPASS_LANG" = "$APP_LANG" ] && return 0
    local zen q_zen q_bash q_class q_dir q_title q_text q_retry q_ok q_cancel file
    zen="$(command -v zenity)" || return 1
    gui_work_dir || return 1
    sh_quote "$zen"; q_zen="$REPLY"
    sh_quote "$BASH"; q_bash="$REPLY"
    sh_quote "$GUI_CLASS"; q_class="$REPLY"
    sh_quote "$GUI_WORK_DIR"; q_dir="$REPLY"
    sh_quote "$WT_TITLE"; q_title="$REPLY"
    gui_escape "$(msg askpass_text)" entry; sh_quote "$REPLY"; q_text="$REPLY"
    gui_escape "$(msg askpass_retry)" entry; sh_quote "$REPLY"; q_retry="$REPLY"
    sh_quote "$(msg ok)"; q_ok="$REPLY"
    sh_quote "$(msg cancel)"; q_cancel="$REPLY"
    file="$GUI_WORK_DIR/askpass"
    ASKPASS_HELPER=""   # a write that fails must not leave a half-written helper marked as good
    {
        printf '%s\n' '#!/bin/sh' \
            '# Written by MintApp Remover: sudo -A runs it to ask for the password in a window.' \
            "dir=$q_dir" \
            'n=$(cat "$dir/tries" 2>/dev/null) || n=0' \
            'n=$((n + 1))' \
            'echo "$n" > "$dir/tries"' \
            "text=$q_text" \
            "[ \"\$n\" -le 1 ] || text=$q_retry"
        [ -z "$GUI_LOCALE" ] || printf 'LC_ALL=%s; export LC_ALL\n' "$GUI_LOCALE"
        printf '%s\n' "pw=\$($q_bash -c 'exec -a \"\$0\" \"\$@\"' $q_class $q_zen --entry --hide-text --title=$q_title --text=\"\$text\" --ok-label=$q_ok --cancel-label=$q_cancel 2>/dev/null </dev/null) || exit 1" \
            'printf "%s\n" "$pw"'
    } > "$file" 2>/dev/null || return 1
    chmod 700 -- "$file" || return 1
    ASKPASS_HELPER="$file" ASKPASS_LANG="$APP_LANG"
}

# In windows, gets the administrator rights before anything is recorded or run:
# "sudo -A -v" asks for the password in a window (or does nothing if sudo needs
# none) and sudo then remembers it for the next calls of this same program,
# which is why apt-get never runs in the background. On a terminal sudo asks by
# itself, and doas cannot ask in a window: both pass. Status 0 = go on,
# PRIV_STATUS_DENIED = no rights (cancelled, wrong password, not allowed).
priv_authenticate() {
    [ "$UI_ENGINE" = "gui" ] || return 0
    [ -n "$PRIV_CMD" ] || detect_privilege || return 0
    [ "${PRIV_CMD##*/}" = "sudo" ] || return 0
    make_askpass || return "$PRIV_STATUS_DENIED"
    rm -f -- "$GUI_WORK_DIR/tries"
    SUDO_ASKPASS="$ASKPASS_HELPER" "$PRIV_CMD" -A -v >/dev/null 2>&1 </dev/null || return "$PRIV_STATUS_DENIED"
}

# The last line of the file $1 as the text of the progress window, whenever it
# changes, until the file $2 is removed. The progress window reads these lines.
gui_progress_feed() {
    local line last=""
    while [ -e "$2" ]; do
        line="$(tail -c 4096 -- "$1" 2>/dev/null | tr '\r' '\n' | grep -v '^[[:space:]]*$' | tail -n 1)" || line=""
        line="$(sanitize_display "$line")"
        line="${line//[&<>]/ }"
        if [ -n "$line" ] && [ "$line" != "$last" ]; then
            printf '# %s\n' "$line"
            last="$line"
        fi
        sleep 0.3
    done
}

# Closes the progress window: it ends by itself when its input does; if it does
# not within GUI_STOP_TICKS x 0.15 s (three seconds) it is stopped.
gui_progress_stop() {
    local i
    [ -n "$GUI_PROGRESS_PID" ] || return 0
    for (( i = 0; i < GUI_STOP_TICKS; i++ )); do
        kill -0 "$GUI_PROGRESS_PID" 2>/dev/null || break
        sleep 0.15
    done
    kill "$GUI_PROGRESS_PID" 2>/dev/null || true
    wait "$GUI_PROGRESS_PID" 2>/dev/null || true
    GUI_PROGRESS_PID=""
}

# The last 12 lines of the command output in the file $1, ready for a window:
# a carriage return (a progress bar) ends a line, no control characters or
# backslashes (zenity reads them as escapes), lines cut to 100 characters.
step_tail_text() {
    local line out=""
    while IFS= read -r line; do
        line="${line//[[:cntrl:]]/}"
        line="${line//\\//}"
        [ "${#line}" -le 100 ] || line="${line:0:97}..."
        out+="${out:+$'\n'}$line"
    done < <(tr '\r' '\n' < "$1" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n 12)
    printf '%s' "$out"
}

# Runs the command "$2 ARGS..." in windows: a progress window while it works,
# and its output kept in STEP_TAIL (the last lines). The command runs here, in
# the foreground, so sudo reuses the password it was given; only the window is
# in the background. $1 = text of the progress window. Without a private
# folder it runs without the window. Status: the command's.
run_gui_step() {
    local text="$1" log run status width
    shift
    STEP_TAIL=""
    if ! gui_work_dir; then
        "$@" </dev/null
        return
    fi
    log="$GUI_WORK_DIR/step.log" run="$GUI_WORK_DIR/running"
    : > "$log"; : > "$run"
    gui_text_width "$text" "$GUI_W_PROGRESS"; width="$REPLY"
    gui_escape "$text" list
    gui_progress_feed "$log" "$run" | gui_cmd --progress --pulsate --auto-close --no-cancel \
        --title="$WT_TITLE" --width="$width" --text="$REPLY" >/dev/null 2>&1 &
    GUI_PROGRESS_PID=$!
    "$@" >"$log" 2>&1 </dev/null
    status=$?
    rm -f -- "$run"
    gui_progress_stop
    STEP_TAIL="$(step_tail_text "$log")"
    return "$status"
}

# "pm_run ACTION [PACKAGE...]", in windows (run_gui_step); the last lines of its
# output stay in PM_TAIL. $1 = text of the progress window.
run_pm_gui() {
    local text="$1" status
    shift
    PM_TAIL=""
    run_gui_step "$text" pm_run "$@"
    status=$?
    PM_TAIL="$STEP_TAIL"
    return "$status"
}

# Runs "pm_run ACTION [PACKAGE...]": in windows with the progress window and the
# output kept (run_pm_gui), otherwise as it is, on the terminal. $1 = text of
# the progress window.
run_pm_step() {
    local text="$1"
    shift
    if [ "$UI_ENGINE" = "gui" ]; then
        run_pm_gui "$text" "$@"
    else
        pm_run "$@"
    fi
}

# Puts in REPLY the text that tells why a removal failed ($1 = its status): no
# rights, the manager's last lines in windows (nothing above to read) or a
# pointer to the terminal.
removal_error_text() {
    if [ "$1" -eq "$PRIV_STATUS_DENIED" ]; then
        REPLY="$(msg priv_denied)"
    elif [ "$UI_ENGINE" = "gui" ]; then
        msgf_v REPLY uninstall_error_gui "$1" "$PM_TAIL"
    else
        msgf_v REPLY uninstall_error "$1"
    fi
}

# The apt backend of pm_simulate: runs "apt-get -s ARGS..." and stores its
# output, without the NOTE block, in PLAN_OUTPUT. Returns apt-get's status.
simulate_apt() {
    local output status
    output=$(apt-get -s "$@" 2>&1)
    status=$?
    PLAN_OUTPUT=$(strip_apt_note <<< "$output")
    return "$status"
}

# Succeeds if "dnf --version" reports dnf 4, the one this backend is written
# for and measured against (4.14.0). dnf 5 (Fedora 41 and later) prints another
# table that dnf_read_plan would refuse, so preflight_checks refuses it first,
# with a clear message. REPLY gets the first line of the answer (empty if dnf
# said nothing). Only the text counts: a dnf that prints a version and then
# fails is not a reason to stop here.
dnf_version_ok() {
    local out
    out="$(dnf --version 2>/dev/null)" || true
    REPLY="${out%%$'\n'*}"
    [[ "$REPLY" =~ ^4\.[0-9]+ ]]
}

# The dnf backend of pm_simulate: "dnf remove|autoremove --assumeno ARGS...",
# with administrator rights (dnf 4 refuses without them, even to simulate) and
# in the C locale, because its text is what decides (dnf_read_plan).
# --color=never: a "color=always" in dnf.conf would put escape codes in the names.
simulate_dnf() {
    local action="$1" verb output status
    shift
    case "$action" in
        purge) verb="remove" ;;
        autoremove) verb="autoremove" ;;
        *) return 2 ;;
    esac
    output=$(priv_run LC_ALL=C dnf "$verb" --assumeno --color=never "$@" 2>&1)
    status=$?
    dnf_read_plan "$action" "$status" <<< "$output"
}

# Reads what dnf printed for a simulated removal (stdin; $1 = the action, $2 =
# dnf's status) and sets PLAN_OUTPUT: a line "Remv NAME [VERSION] (ARCH)" for
# each package of its table, or the error text. dnf's status says nothing: a
# good simulation ends with 1 ("Operation aborted.": --assumeno answers no) and
# "Nothing to do" with 0. The text decides, and the plan is trusted only if the
# table holds removals alone and has as many rows as its summary says ("Remove
# N Packages"); anything else, like the table of dnf 5, is an error, never a
# plan. Status: 0 for a plan (empty for an autoremove with nothing to remove; a
# purge that matches no package is an error); otherwise dnf's status, or 1 if
# it was 0.
dnf_read_plan() {
    local action="$1" dnf_status="$2" line state="" declared="" rows=0
    local aborted=0 nothing=0 unreadable=0 name arch version _rest text=""
    local -a dnf_lines=() dnf_rows=()
    mapfile -t dnf_lines
    for line in ${dnf_lines[@]+"${dnf_lines[@]}"}; do
        if [ "$line" = "Operation aborted." ]; then
            aborted=1
        elif [ "$line" = "Nothing to do." ]; then
            nothing=1
        elif [ "$line" = "Transaction Summary" ]; then
            state="summary"
        elif [ "$state" = "summary" ]; then
            if [[ "$line" =~ ^Remove[[:space:]]+([0-9]+)[[:space:]]+Packages?$ ]]; then
                declared="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^(Install|Upgrade|Downgrade|Reinstall|Skip)[[:space:]] ]]; then
                unreadable=1
            fi
        else
            case "$line" in
                "Removing:"|"Removing dependent packages:"|"Removing unused dependencies:") state="rows" ;;
                " "*)
                    [ "$state" = "rows" ] || continue
                    read -r name arch version _rest <<< "$line"
                    if [ -n "$version" ] && [[ "$line" != *[[:cntrl:]]* ]]; then
                        dnf_rows+=("Remv $name [$version] ($arch)")
                        rows=$((rows + 1))
                    else
                        unreadable=1
                    fi ;;
                "") ;;
                *) [ "$state" != "rows" ] || unreadable=1 ;;   # another section inside the table
            esac
        fi
    done
    if [ "$unreadable" -eq 0 ] && [ -n "$declared" ]; then
        if [ "$rows" -eq "$declared" ] && [ "$rows" -ge 1 ] && [ "$aborted" -eq 1 ]; then
            printf -v PLAN_OUTPUT '%s\n' "${dnf_rows[@]}"
            PLAN_OUTPUT="${PLAN_OUTPUT%$'\n'}"
            return 0
        fi
        unreadable=1
    fi
    if [ "$unreadable" -eq 0 ] && [ "$dnf_status" -eq 0 ] && [ "$nothing" -eq 1 ] && [ "$action" = "autoremove" ]; then
        return 0
    fi
    for line in ${dnf_lines[@]+"${dnf_lines[@]}"}; do
        case "$line" in
            ""|"Last metadata expiration check: "*|"Dependencies resolved."|"Nothing to do."|"Complete!") ;;
            *) text+="$line"$'\n' ;;
        esac
    done
    if [ "$unreadable" -eq 1 ] || [ -z "$text" ]; then
        msgf_v PLAN_OUTPUT pm_plan_unreadable "$(pm_tool)"
    else
        PLAN_OUTPUT="${text%$'\n'}"
    fi
    [ "$dnf_status" -ne 0 ] && [ "$unreadable" -eq 0 ] && return "$dnf_status"
    return 1
}

# The rpm backend of pm_installed (dnf and zypper): succeeds if a
# package whose NAME is exactly $1 is installed. rpm also reads "name-version"
# and "name.arch" as queries, and those are not names, so the answer is
# compared with $1. Only the output of a query that succeeded is read: what rpm
# prints for a package it does not find depends on the locale. The "--" keeps
# an empty or option-like name from becoming an option ("rpm -q -a" lists every
# package and succeeds).
rpm_installed() {
    local names
    [ -n "${1-}" ] || return 1
    names=$(rpm -q --qf '%{NAME}\n' -- "$1" 2>/dev/null) || return 1
    grep -qxF -- "$1" <<< "$names"
}

# The rpm backend of pm_owner (dnf and zypper): for each path that
# a package owns, the line "NAME: /path"; if several own it (a folder that two
# packages share, or one package installed for two architectures, which rpm
# reports twice) their names, each once and sorted, separated by ", ". rpm is
# asked once per path, because with many it does not say which line belongs to
# which path. A path with an owner ends with status 0 and its owner on stdout;
# for one without, rpm writes on stdout too (and on stderr if the path does not
# exist), so the output of a query that failed is never read. The "--" keeps a
# path that starts with "-" from becoming an option. Status 0.
rpm_owner() {
    local path names
    for path in "$@"; do
        names=$(rpm -qf --qf '%{NAME}\n' -- "$path" 2>/dev/null) || continue
        names=$(LC_ALL=C sort -u <<< "$names")
        [ -n "$names" ] && printf '%s: %s\n' "${names//$'\n'/, }" "$path"
    done
    return 0
}

# The rpm backend of pm_detail (dnf and zypper): "NAME<TAB>VERSION<TAB>KiB"
# for each installed package among $@, in one question. VERSION is rpm's
# "EVR": version-release, with "epoch:" in front only if the package has one.
# rpm gives the size in bytes: it is rounded up to KiB here. For a package it
# does not find, rpm writes "package X is not installed" on stdout (the text
# depends on the locale), and "name-version" and "name.arch" are queries to rpm
# too: so only a line of three fields whose NAME is one of those asked is kept.
# The status is rpm's (1 if any is missing) and says nothing about the lines.
# The "--" keeps a name from becoming an option.
rpm_detail() {
    local out line name version bytes status=0 want=$'\n' tab=$'\t'
    local row="^([^$tab]+)$tab([^$tab]+)$tab([0-9]{1,15})\$"
    for name in "$@"; do want+="$name"$'\n'; done
    out=$(rpm -q --qf '%{NAME}\t%{EVR}\t%{LONGSIZE}\n' -- "$@" 2>/dev/null) || status=$?
    while IFS= read -r line; do
        [[ "$line" =~ $row ]] || continue
        name="${BASH_REMATCH[1]}" version="${BASH_REMATCH[2]}" bytes="${BASH_REMATCH[3]}"
        [[ "$want" == *$'\n'"$name"$'\n'* ]] || continue
        printf '%s\t%s\t%s\n' "$name" "$version" "$(( (10#$bytes + 1023) / 1024 ))"
    done <<< "$out"
    return "$status"
}

# The rpm backend of pm_meta_packages (dnf and zypper): rpm has no
# section for meta-packages, so a package with no files at all (not even a
# folder: it only brings its dependencies) counts as one. A mistake only makes
# the warning of a plan stronger (it never blocks). One question for all the
# names. %{FILENAMES:arraysize} prints "(none)" for no entries and their number
# otherwise; "0" is read as none too. Each name is printed once, and only if
# it is one of those asked, as in rpm_detail. Status 0, whatever rpm says (it
# is 1 if any name is missing).
rpm_meta_packages() {
    local out line name count want=$'\n' seen=$'\n' tab=$'\t'
    local row="^([^$tab]+)$tab(\\(none\\)|[0-9]{1,15})\$"
    for name in "$@"; do want+="$name"$'\n'; done
    out=$(rpm -q --qf '%{NAME}\t%{FILENAMES:arraysize}\n' -- "$@" 2>/dev/null) || true
    while IFS= read -r line; do
        [[ "$line" =~ $row ]] || continue
        name="${BASH_REMATCH[1]}" count="${BASH_REMATCH[2]}"
        case "$count" in "(none)"|0) ;; *) continue ;; esac
        [[ "$want" == *$'\n'"$name"$'\n'* ]] || continue
        [[ "$seen" == *$'\n'"$name"$'\n'* ]] && continue
        seen+="$name"$'\n'
        printf '%s\n' "$name"
    done <<< "$out"
    return 0
}

# Where dnf reads the packages it protects (dnf_protected_names). They are not
# readonly so that a test can point them elsewhere.
DNF_CONF="/etc/dnf/dnf.conf"
DNF_PROTECTED_DIRS=("/etc/dnf/protected.d" "/etc/yum/protected.d")

# Prints the names in the file $1, a list of packages as dnf reads it: one or
# more per line, separated by commas, spaces or tabs. A line that starts with
# "#" is a comment; a "#" after a name is not, and what follows it is read as
# names. Nothing if the file cannot be read.
dnf_list_names() {
    local line word
    local -a words
    [ -f "$1" ] && [ -r "$1" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//$'\r'/ }"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        read -r -a words <<< "${line//,/ }"
        for word in "${words[@]+"${words[@]}"}"; do printf '%s\n' "$word"; done
    done < "$1"
    return 0
}

# Prints the names that $DNF_CONF gives to protected_packages, in its [main]
# section (a line that starts with a blank goes on with the value, even one
# with nothing else: dnf 4.14.0 does the same). An entry
# "glob:PATTERN" stands for the names in the files PATTERN matches.
dnf_conf_names() {
    local line word file section="" more=0 value=""
    local -a words
    [ -f "$DNF_CONF" ] && [ -r "$DNF_CONF" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//$'\r'/ }"
        if [ "$more" -eq 1 ] && [[ "$line" =~ ^[[:space:]]+ ]]; then
            value+=" $line"
            continue
        fi
        more=0
        if [[ "$line" =~ ^\[([^]]*)\] ]]; then
            section="${BASH_REMATCH[1]}"
        elif [ "$section" = "main" ] && [[ "$line" =~ ^protected_packages[[:space:]]*=(.*)$ ]]; then
            value+=" ${BASH_REMATCH[1]}"
            more=1
        fi
    done < "$DNF_CONF"
    read -r -a words <<< "${value//,/ }"
    for word in "${words[@]+"${words[@]}"}"; do
        if [[ "$word" == glob:* ]]; then
            # The pattern is expanded on purpose, so it is not quoted.
            # shellcheck disable=SC2086
            for file in ${word#glob:}; do dnf_list_names "$file"; done
        else
            printf '%s\n' "$word"
        fi
    done
    return 0
}

# Prints, one per line, the packages the dnf backend protects: the union of
# what dnf can protect. "dnf" itself; the "*.conf" files of the folders in
# DNF_PROTECTED_DIRS (any other file, and a hidden one, does not count); and
# protected_packages of dnf.conf. dnf takes that setting instead of its default
# (dnf and the protected.d files), so the union protects more than dnf does in
# that case: it only hides packages, never offers one dnf would refuse.
dnf_protected_names() {
    local dir file
    printf 'dnf\n'
    for dir in "${DNF_PROTECTED_DIRS[@]+"${DNF_PROTECTED_DIRS[@]}"}"; do
        for file in "$dir"/*.conf; do dnf_list_names "$file"; done
    done
    dnf_conf_names
    return 0
}

# The dnf backend of pm_protected: succeeds if the package $1 is one of
# dnf_protected_names. Only files are read: dnf cannot be asked without
# administrator rights, and rpm does not know about it.
dnf_protected() {
    local names
    names=$'\n'"$(dnf_protected_names)"$'\n'
    [[ "$names" == *$'\n'"$1"$'\n'* ]]
}

# The pacman backend. It needs no administrator rights to look (query, owner,
# simulation); pm_run asks for them to remove. Its text is read in the C locale.

# Puts the orphans in PACMAN_ORPHANS: the packages that were installed as
# dependencies and that nothing requires, not even as optional ("pacman -Qdtq").
# Status 0 (the array is empty if there are none; pacman says nothing and fails
# then); 1, with an empty array, if a name is not a valid package name: the
# answer is not trusted.
PACMAN_ORPHANS=()
pacman_orphans() {
    local out name
    PACMAN_ORPHANS=()
    out=$(LC_ALL=C pacman -Qdtq 2>/dev/null) || true
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        pm_valid_name "$name" || { PACMAN_ORPHANS=(); return 1; }
        PACMAN_ORPHANS+=("$name")
    done <<< "$out"
    return 0
}

# The pacman backend of pm_simulate: "pacman -Rc|-Rs --print" in the C locale
# and without administrator rights (--print needs none). It prints the plan of
# what pm_run carries out: purge is -Rcn there and autoremove is -Rns of the
# orphans; here there is no -n, which cannot go with --print and only decides
# whether .pacsave copies are kept, never which packages go. autoremove ignores
# its arguments: the orphans decide, and with none there is nothing to simulate
# (status 0, empty plan). A name pacman does not know makes it fail as a whole.
simulate_pacman() {
    local action="$1" flags output status
    shift
    case "$action" in
        purge) flags="-Rc" ;;
        autoremove)
            if ! pacman_orphans; then
                msgf_v PLAN_OUTPUT pm_plan_unreadable "$(pm_tool)"
                return 1
            fi
            [ "${#PACMAN_ORPHANS[@]}" -gt 0 ] || return 0
            set -- "${PACMAN_ORPHANS[@]}"
            flags="-Rs" ;;
        *) return 2 ;;
    esac
    output=$(LC_ALL=C pacman "$flags" --print --print-format 'Remv %n [%v]' --noconfirm --color never -- "$@" 2>&1)
    status=$?
    pacman_read_plan "$status" <<< "$output"
}

# Reads what pacman printed for a simulated removal (stdin; $1 = its status) and
# sets PLAN_OUTPUT: the rows "Remv NAME [VERSION]" or the error text. The status
# is reliable here (0 is a plan, anything else is not), but the text is checked
# too: the plan is trusted only with at least one row and no line that is not a
# row (a name that pm_valid_name accepts, a plain version, no control
# characters). A "warning:" line is skipped: pacman writes some about its
# configuration in every call. Status: 0 for a plan; otherwise pacman's, or 1 if
# it was 0 (a purge that prints nothing is an error, never an empty plan).
pacman_read_plan() {
    local pacman_status="$1" line text="" other=0
    local row='^Remv ([^ ]+) \[([A-Za-z0-9][A-Za-z0-9._+~:-]*)\]$'
    local -a plan_rows=()
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        text+="$line"$'\n'
        if [[ "$line" =~ $row ]] && [[ "$line" != *[[:cntrl:]]* ]] && pm_valid_name "${BASH_REMATCH[1]}"; then
            plan_rows+=("$line")
        elif [[ "$line" != "warning: "* ]]; then
            other=1
        fi
    done
    if [ "$pacman_status" -eq 0 ]; then
        if [ "$other" -eq 0 ] && [ "${#plan_rows[@]}" -gt 0 ]; then
            printf -v PLAN_OUTPUT '%s\n' "${plan_rows[@]}"
            PLAN_OUTPUT="${PLAN_OUTPUT%$'\n'}"
            return 0
        fi
        msgf_v PLAN_OUTPUT pm_plan_unreadable "$(pm_tool)"
        return 1
    fi
    PLAN_OUTPUT="${text%"${text##*[![:space:]]}"}"
    [ -n "$PLAN_OUTPUT" ] || msgf_v PLAN_OUTPUT pm_plan_unreadable "$(pm_tool)"
    return "$pacman_status"
}

# The pacman backend of pm_installed: succeeds if a package whose name is exactly
# $1 is installed ("pacman -Q"). pacman compares the whole name (not
# "name-version", not wildcards, not capitals) and prints "NAME VERSION"; that
# NAME is compared with $1 here too, as rpm_installed does, and only the output
# of a query that succeeded is read. The "--" keeps an option-like name from
# being one.
pacman_installed() {
    local out
    [ -n "${1-}" ] || return 1
    out=$(LC_ALL=C pacman -Q -- "$1" 2>/dev/null) || return 1
    [ "${out%% *}" = "$1" ]
}

# Succeeds if $1 is an absolute path that "pacman -Qo" prints back as it was
# given: no "//", no "." or ".." component, no "/" at the end (it adds one to a
# folder) and no line break. pacman prints any other path in its own form
# (absolute, cleaned up), so pacman_owner asks about each of those by itself.
pacman_plain_path() {
    case "$1" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *//*|*/./*|*/../*|*/|*/.|*/..|*$'\n'*) return 1 ;;
    esac
    return 0
}

# Asks "pacman -Qo" about the paths given and prints "NAME PATH" for each of its
# answers "PATH is owned by NAME VERSION": PATH as pacman prints it (it can differ
# from the one asked: a folder gets a "/" at the end and a relative path comes back
# absolute), one line for each package if several own it; NAME passes pm_valid_name
# and VERSION is a plain version, and the line starts with "/". PATH is read
# whole even if it contains " is owned by ": the last two words are the name and
# the version, because neither has a space. Anything else is not a line, and the
# error text for a path nobody owns (stderr) is not shown. Status 0: pacman fails
# if any path has no owner.
pacman_owned_lines() {
    local out line path name
    local row='^(/.+) is owned by ([^ ]+) [A-Za-z0-9][A-Za-z0-9._+~:-]*$'
    out=$(LC_ALL=C pacman -Qo -- "$@" 2>/dev/null) || true
    while IFS= read -r line; do
        [[ "$line" =~ $row ]] || continue
        path="${BASH_REMATCH[1]}" name="${BASH_REMATCH[2]}"
        pm_valid_name "$name" || continue
        printf '%s %s\n' "$name" "$path"
    done <<< "$out"
    return 0
}

# The pacman backend of pm_owner: for each path that a package owns, the line
# "NAME: /path" with the path as it was given; if several own it (a folder that
# two packages share) their names, each once and sorted in the C locale,
# separated by ", ". One question to pacman for all the plain paths
# (pacman_plain_path): "pacman -Qo" reads its whole database on each call, so
# one question per launcher would take tens of seconds. The answer is matched
# with the path by its text (a folder is looked for with its "/" too). A path
# that is not plain gets a question of its own, and every line of the answer is
# its owner: "./" goes before one without "/", since pacman looks for a name
# like that in the PATH. A plain path whose folder is a link comes back in
# another form and is not found: it counts as having no owner. An empty path is
# skipped. Status 0.
pacman_owner() {
    local path arg key names line
    local -a batch=()
    local -A owners=()
    for path in "$@"; do
        if [ -n "$path" ] && pacman_plain_path "$path"; then batch+=("$path"); fi
    done
    if [ "${#batch[@]}" -gt 0 ]; then
        while IFS= read -r line; do
            key="${line#* }"
            owners["$key"]+="${owners[$key]:+$'\n'}${line%% *}"
        done < <(pacman_owned_lines "${batch[@]}")
    fi
    for path in "$@"; do
        [ -n "$path" ] || continue
        if pacman_plain_path "$path"; then
            names="${owners[$path]-}"
            [ -n "$names" ] || names="${owners[$path/]-}"
        else
            arg="$path"
            case "$arg" in
                */*) ;;
                *) arg="./$arg" ;;
            esac
            names=$(pacman_owned_lines "$arg" | cut -d' ' -f1)
        fi
        [ -n "$names" ] || continue
        names=$(LC_ALL=C sort -u <<< "$names")
        printf '%s: %s\n' "${names//$'\n'/, }" "$path"
    done
    return 0
}

# Rounds up to whole KiB the size that "pacman -Qi" prints for a package ("4.00
# KiB", "1500.00 B"): two decimals, B up to 2048 and then KiB, MiB... in steps of
# 1024. Prints the KiB, in integers, from hundredths of the unit. Status 1 and
# no output for any other text: up to four digits before the point and a unit
# up to PiB are accepted (more could overflow, and pacman does not print it).
# pacman has already rounded to two decimals, so a size in GiB can be some MiB
# off.
pacman_size_kib() {
    local hundredths unit
    [[ "${1-}" =~ ^([0-9]{1,4})\.([0-9]{2})\ (B|KiB|MiB|GiB|TiB|PiB)$ ]] || return 1
    hundredths=$(( 10#${BASH_REMATCH[1]} * 100 + 10#${BASH_REMATCH[2]} ))
    unit="${BASH_REMATCH[3]}"
    case "$unit" in
        B) printf '%s\n' $(( (hundredths + 102399) / 102400 )) ;;
        KiB) printf '%s\n' $(( (hundredths + 99) / 100 )) ;;
        MiB) printf '%s\n' $(( (hundredths * 1024 + 99) / 100 )) ;;
        GiB) printf '%s\n' $(( (hundredths * 1048576 + 99) / 100 )) ;;
        TiB) printf '%s\n' $(( (hundredths * 1073741824 + 99) / 100 )) ;;
        PiB) printf '%s\n' $(( (hundredths * 1099511627776 + 99) / 100 )) ;;
    esac
}

# The pacman backend of pm_detail: "NAME<TAB>VERSION<TAB>KiB" for each installed
# package among $@, in one question ("pacman -Qi", in the C locale). A block
# gives a line only if its Name is one of those asked (once), its Version is a
# plain version and its "Installed Size" reads (pacman_size_kib). The status is
# pacman's (1 if any name is missing) and says nothing about the lines.
pacman_detail() {
    local out line arg name="" version="" size="" kib status=0
    local want=$'\n' seen=$'\n'
    local version_re='^[A-Za-z0-9][A-Za-z0-9._+~:-]*$'
    for arg in "$@"; do want+="$arg"$'\n'; done
    out=$(LC_ALL=C pacman -Qi -- "$@" 2>/dev/null) || status=$?
    # The text ends with a blank line, which closes the last block.
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            if [ -n "$name" ] && [[ "$want" == *$'\n'"$name"$'\n'* ]] \
                && [[ "$seen" != *$'\n'"$name"$'\n'* ]] \
                && [[ "$version" =~ $version_re ]] \
                && kib=$(pacman_size_kib "$size"); then
                seen+="$name"$'\n'
                printf '%s\t%s\t%s\n' "$name" "$version" "$kib"
            fi
            name="" version="" size=""
        elif [[ "$line" =~ ^Name\ +:\ (.+)$ ]]; then
            [ -n "$name" ] || name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Version\ +:\ (.+)$ ]]; then
            [ -n "$version" ] || version="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Installed\ Size\ +:\ (.+)$ ]]; then
            [ -n "$size" ] || size="${BASH_REMATCH[1]}"
        fi
    done <<< "$out"$'\n'
    return "$status"
}

# The pacman backend of pm_meta_packages: a package with no files at all (it
# only brings its dependencies, as "base" does) counts as a meta-package, as in
# rpm_meta_packages. One question: "pacman -Qk" prints "NAME: N total files, M
# missing files" for each installed package. Only N = 0 and a NAME among those
# asked count, once. Status 0, whatever pacman says.
pacman_meta_packages() {
    local out line name arg want=$'\n' seen=$'\n'
    local row='^([^ ]+): 0 total files?, [0-9]+ missing files?$'
    for arg in "$@"; do want+="$arg"$'\n'; done
    out=$(LC_ALL=C pacman -Qk -- "$@" 2>/dev/null) || true
    while IFS= read -r line; do
        [[ "$line" =~ $row ]] || continue
        name="${BASH_REMATCH[1]}"
        [[ "$want" == *$'\n'"$name"$'\n'* ]] || continue
        [[ "$seen" == *$'\n'"$name"$'\n'* ]] && continue
        seen+="$name"$'\n'
        printf '%s\n' "$name"
    done <<< "$out"
    return 0
}

# The pacman backend of pm_protected: succeeds if the package $1 matches a
# pattern of HoldPkg ("pacman-conf HoldPkg", one per line). The patterns are
# globs, as pacman reads them (fnmatch). Status 1 if none matches; 2 if
# pacman-conf fails (the list is unknown, and a manager that cannot say
# protects, see is_excluded_package).
pacman_protected() {
    local out pattern
    [ -n "${1-}" ] || return 1
    out=$(LC_ALL=C pacman-conf HoldPkg 2>/dev/null) || return 2
    while IFS= read -r pattern; do
        [ -n "$pattern" ] || continue
        # shellcheck disable=SC2254  # the pattern is a glob on purpose
        case "$1" in
            $pattern) return 0 ;;
        esac
    done <<< "$out"
    return 1
}

# ----------------------------------------------------------------------------
# zypper backend (4.6, step 6). zypper has no purge, no autoremove and no
# protected list of its own: purge is "remove", the unneeded packages are the
# ones "zypper packages --unneeded" lists, and what it refuses to remove are the
# packages that are locked. rpm answers the questions about installed packages
# (rpm_installed, rpm_owner, rpm_detail, rpm_meta_packages).
# ----------------------------------------------------------------------------

# Puts in ZYPPER_UNNEEDED the packages zypper files as unneeded (installed only
# as a dependency and no longer required): the rows of the table that
# "zypper packages --unneeded" prints, "S | Repository | Name | Version | Arch".
# No names, not repeated (a package of two architectures has two rows). Status
# 0 (the array is empty if there are none); 1, with an empty array, if zypper
# fails or a row is not what an installed package looks like (the repository
# is @System, the state "i" or "i+", the name passes pm_valid_name): the answer
# is not trusted.
ZYPPER_UNNEEDED=()
zypper_unneeded() {
    local out line name state repo seen=" "
    local -a cols
    ZYPPER_UNNEEDED=()
    out=$(LC_ALL=C zypper --non-interactive --no-color packages --unneeded 2>/dev/null) || return 1
    while IFS= read -r line; do
        [[ "$line" == *" | "* ]] || continue
        IFS='|' read -ra cols <<< "$line"
        state="${cols[0]//[[:space:]]/}"
        [ "$state" != "S" ] || continue
        if [ "${#cols[@]}" -ne 5 ]; then ZYPPER_UNNEEDED=(); return 1; fi
        repo="${cols[1]//[[:space:]]/}"
        name="${cols[2]//[[:space:]]/}"
        case "$state" in i|i+) ;; *) ZYPPER_UNNEEDED=(); return 1 ;; esac
        if [ "$repo" != "@System" ] || ! pm_valid_name "$name"; then ZYPPER_UNNEEDED=(); return 1; fi
        case "$seen" in *" $name "*) continue ;; esac
        seen+="$name "
        ZYPPER_UNNEEDED+=("$name")
    done <<< "$out"
    return 0
}

# The zypper backend of pm_simulate: "zypper remove --dry-run" in the C locale
# and without administrator rights (a dry run needs none). It prints the plan
# of what pm_run carries out: purge is "remove" and autoremove is "remove
# --clean-deps" of the packages zypper_unneeded lists (its arguments are
# ignored: zypper decides, and with none there is nothing to simulate: status 0,
# empty plan). A name zypper does not know makes it fail as a whole (status
# 104), as does a locked package (status 4).
simulate_zypper() {
    local action="$1" output status
    local -a flags=()
    shift
    case "$action" in
        purge) ;;
        autoremove)
            if ! zypper_unneeded; then
                msgf_v PLAN_OUTPUT pm_plan_unreadable "$(pm_tool)"
                return 1
            fi
            [ "${#ZYPPER_UNNEEDED[@]}" -gt 0 ] || return 0
            set -- "${ZYPPER_UNNEEDED[@]}"
            flags=(--clean-deps) ;;
        *) return 2 ;;
    esac
    output=$(LC_ALL=C zypper --non-interactive --no-color remove --dry-run "${flags[@]+"${flags[@]}"}" "$@" 2>&1)
    status=$?
    zypper_read_plan "$status" <<< "$output"
}

# Reads what zypper printed for a simulated removal (stdin; $1 = its status) and
# sets PLAN_OUTPUT: the rows "Remv NAME" or the error text. Only the status 0
# counts as a plan, and the text is checked too: the plan is the one section
# "The following N packages are going to be REMOVED:" (or "package is", for
# one), whose names (any number of lines that start with two spaces) are N, all
# valid, and which the summary "N packages to remove." repeats; any other
# "The following ..." section (an install, an upgrade...), a control
# character or a count that does not match makes it unreadable. Lines of
# progress ("Reading installed packages...", the prompt zypper answers by
# itself with --non-interactive...) are skipped. Status: 0 for a plan;
# otherwise zypper's, or 1 if it was 0 (never an empty plan: a purge that
# removes nothing is an error).
zypper_read_plan() {
    local zypper_status="$1" line text="" other=0 sections=0 declared=0 summary=-1 in_list=0 token
    local head='^The following ([0-9]+ packages are|package is) going to be REMOVED:$'
    local count='^([0-9]+) packages? to remove\.$'
    local -a names=()
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || { in_list=0; continue; }
        text+="$line"$'\n'
        [[ "$line" != *[[:cntrl:]]* ]] || other=1
        if [[ "$line" =~ $head ]]; then
            sections=$((sections + 1))
            if [ "${BASH_REMATCH[1]}" = "package is" ]; then declared=1; else declared="${BASH_REMATCH[1]%% *}"; fi
            in_list=1
        elif [ "$in_list" -eq 1 ] && [[ "$line" == "  "[![:space:]]* ]]; then
            for token in $line; do
                if pm_valid_name "$token"; then names+=("$token"); else other=1; fi
            done
        else
            in_list=0
            if [[ "$line" =~ $count ]]; then summary="${BASH_REMATCH[1]}"
            elif [[ "$line" == "The following "* ]]; then other=1
            fi
        fi
    done
    if [ "$zypper_status" -eq 0 ]; then
        if [ "$other" -eq 0 ] && [ "$sections" -eq 1 ] && [ "$declared" -ge 1 ] \
            && [ "${#names[@]}" -eq "$declared" ] && [ "$summary" -eq "$declared" ]; then
            printf -v PLAN_OUTPUT 'Remv %s\n' "${names[@]+"${names[@]}"}"
            PLAN_OUTPUT="${PLAN_OUTPUT%$'\n'}"
            return 0
        fi
        msgf_v PLAN_OUTPUT pm_plan_unreadable "$(pm_tool)"
        return 1
    fi
    PLAN_OUTPUT="${text%"${text##*[![:space:]]}"}"
    [ -n "$PLAN_OUTPUT" ] || msgf_v PLAN_OUTPUT pm_plan_unreadable "$(pm_tool)"
    return "$zypper_status"
}

# The file with the package locks of zypper (not readonly: the tests point it
# elsewhere). A lock is a block of "key: value" lines separated by a blank
# line: "type: package", "match_type: glob" (or string, or regex),
# "case_sensitive: on" (or off) and "solvable_name: PATTERN".
ZYPPER_LOCKS="/etc/zypp/locks"

# The zypper backend of pm_protected: succeeds if a lock of ZYPPER_LOCKS
# matches the package $1 (zypper refuses to remove it: the plan fails with
# status 4, and the program does not offer it). Status 1 if none does or the
# file does not exist (no locks); 2 if it exists and cannot be read (the locks
# are unknown, and a manager that cannot say protects, see is_excluded_package).
# Only the locks on package names count (not on patterns or products).
zypper_protected() {
    local line key value type="package" match="glob" case_on=1 name=""
    [ -n "${1-}" ] || return 1
    [ -e "$ZYPPER_LOCKS" ] || return 1
    [ -f "$ZYPPER_LOCKS" ] && [ -r "$ZYPPER_LOCKS" ] || return 2
    local -i hit=0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        if [ -z "${line//[[:space:]]/}" ]; then
            zypper_lock_matches "$1" "$type" "$match" "$case_on" "$name" && hit=1
            type="package"; match="glob"; case_on=1; name=""
            continue
        fi
        [[ "$line" == *:* ]] || continue
        key="${line%%:*}"
        value="${line#*:}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        case "$key" in
            type) type="$value" ;;
            match_type) match="$value" ;;
            case_sensitive) if [ "$value" = "off" ]; then case_on=0; else case_on=1; fi ;;
            solvable_name) name="$value" ;;
        esac
    done < "$ZYPPER_LOCKS"
    zypper_lock_matches "$1" "$type" "$match" "$case_on" "$name" && hit=1
    [ "$hit" -eq 1 ]
}

# Succeeds if the lock (type, match_type, case_sensitive as 1 or 0, solvable_name)
# is on a package name and matches the package $1.
zypper_lock_matches() {
    local pkg="$1" type="$2" match="$3" case_on="$4" pattern="$5" result=1
    [ "$type" = "package" ] && [ -n "$pattern" ] || return 1
    [ "$case_on" -eq 1 ] || shopt -s nocasematch
    case "$match" in
        string) [[ "$pkg" == "$pattern" ]] && result=0 ;;   # quoted: literal text, but nocasematch still applies
        glob)
            # shellcheck disable=SC2254  # the pattern is a glob on purpose
            case "$pkg" in $pattern) result=0 ;; esac ;;
        regex) [[ "$pkg" =~ $pattern ]] && result=0 ;;
    esac
    [ "$case_on" -eq 1 ] || shopt -u nocasematch
    return "$result"
}

# Succeeds if a simulated plan contains at least one package to remove.
plan_has_removals() {
    grep -qE '^(Purg|Remv) ' <<< "$1"
}

# Fingerprint of a simulated plan: SHA-256 of its sorted "Purg"/"Remv" lines.
# Used to verify that the plan about to run is the one the user confirmed.
plan_fingerprint() {
    local lines
    lines=$(grep -E '^(Purg|Remv) ' <<< "$1" | LC_ALL=C sort)
    sha256sum <<< "$lines" | cut -d' ' -f1
}

# Prints the package names of a simulated plan on one line.
plan_package_names() {
    sed -nE 's/^(Purg|Remv) ([^ ]+).*/\2/p' <<< "$1" | LC_ALL=C sort -u | tr '\n' ' '
}

# Meta-packages and base packages of the system (E14): they only keep a set of
# packages installed (a desktop, a task, the base of a distribution). A plan
# that removes one deserves a stronger warning. Shell patterns on the name;
# plan_meta_packages also asks the manager (pm_meta_packages), which knows the
# real ones. A brand prefix is not a pattern: in Ubuntu 24.04 only 34 of its 168
# "ubuntu-*" packages are meta-packages (the rest are wallpapers, themes,
# documents and tools), so the ones named here are the well-known ones and the
# manager's section finds the others (ubuntu-wsl, ubuntu-budgie-desktop-minimal...).
META_PATTERNS=(
    "*-desktop" "*-desktop-environment*" "task-*"
    "*-meta" "*-meta-*" "*-metapackage"
    "ubuntu-desktop-*" "ubuntu-minimal" "ubuntu-standard" "ubuntu-server*" "ubuntu-restricted-*"
    "mint-meta-*" "linuxmint*"
    "gnome" "gnome-core" "kde-full" "kde-standard" "xfce4" "xfce4-goodies" "lxde" "lxqt"
    "patterns-*"
)
readonly META_PATTERNS

# Succeeds if the package name $1 matches META_PATTERNS.
is_meta_name() {
    local pattern
    for pattern in "${META_PATTERNS[@]}"; do
        # shellcheck disable=SC2053
        [[ "$1" == $pattern ]] && return 0
    done
    return 1
}

# Prints, one per line, the meta-packages that the simulated plan $1 removes,
# without the packages the user asked for ($2...: they are in the summary).
# Succeeds only if there is at least one. Names that pm_valid_name rejects are
# ignored; the manager is asked once for all the names the patterns left.
plan_meta_packages() {
    local plan="$1" name requested
    shift
    printf -v requested ' %s' "$@"
    requested+=" "
    local -a names=() rest=() hits=()
    read -r -a names <<< "$(plan_package_names "$plan")"
    for name in "${names[@]+"${names[@]}"}"; do
        [[ "$requested" == *" $name "* ]] && continue
        pm_valid_name "$name" || continue
        if is_meta_name "$name"; then hits+=("$name"); else rest+=("$name"); fi
    done
    if [ "${#rest[@]}" -gt 0 ]; then
        while IFS= read -r name; do
            hits+=("$name")
        done < <(pm_meta_packages "${rest[@]}")
    fi
    [ "${#hits[@]}" -gt 0 ] || return 1
    printf '%s\n' "${hits[@]}" | LC_ALL=C sort -u
}

# Puts in REPLY the warning about the meta-packages $1 (one name per line).
meta_warning_text() {
    local list="" name
    while IFS= read -r name; do list+="  - ${name}"$'\n'; done <<< "$1"
    msgf_v REPLY meta_warning "$list"
}

# Shows a plan with its introduction and asks for confirmation (the dialog that
# every plan shares: packages, Flatpak and Snap). $1 = introduction, $2 = plan text,
# $3 = summary (may be empty), $4 = warning (may be empty; in the dialogs it
# goes before the introduction, in text mode between the plan and the summary),
# $5 = question of the dialogs, $6 = prompt of the text mode, $7 = "all" if every
# line of the plan removes something (see text_plan). The question starts on
# "no". Succeeds only if the user confirms.
plan_dialog() {
    local intro="$1" plan="$2" summary="$3" warning="$4" confirm="$5" confirm_text="$6" lines="${7-}"
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_msgbox "${warning}${intro}\n\n${plan}" big
        ask_yes_no "${summary}\n${confirm}" ""
    else
        header
        text_print "$intro"
        echo
        text_plan "$plan" "$lines"
        section_rule
        if [ -n "$warning" ]; then
            # The blank line that separates it from the intro in the dialogs is not needed here.
            while [[ "$warning" == *$'\n' ]]; do warning="${warning%$'\n'}"; done
            text_say "$C_WARN" "$warning"
            section_rule
        fi
        [ -n "$summary" ] && text_print "$summary"
        if ! ask_yes_no "" "$confirm_text"; then
            text_wrap "$(msg cancelled)"
            pause
            return 1
        fi
    fi
}

# Puts in REPLY the line that counts the packages of the plan $1: all of them
# and, when the user chose some ($2...), how many of those the plan holds and how
# many more the manager adds as dependents. Fails, leaving REPLY alone, if the
# plan removes nothing.
plan_count_text() {
    local plan="$1" name total=0 chosen=0 requested
    local -a names=()
    shift
    printf -v requested ' %s' "$@"
    requested+=" "
    read -r -a names <<< "$(plan_package_names "$plan")"
    for name in "${names[@]+"${names[@]}"}"; do
        total=$(( total + 1 ))
        if [[ "$requested" == *" $name "* ]]; then chosen=$(( chosen + 1 )); fi
    done
    [ "$total" -gt 0 ] || return 1
    if [ "$chosen" -gt 0 ]; then
        msgf_v REPLY plan_count_split "$total" "$chosen" $(( total - chosen ))
    else
        msgf_v REPLY plan_count_all "$total"
    fi
}

# Shows the simulated plan of the package manager and asks for confirmation.
# $1 = introduction text, $2 = plan, $3 = summary of the selection (may be
# empty), $4... = the packages the user asked for. If the plan also removes
# meta-packages (plan_meta_packages) it adds a warning and a stronger question,
# which still starts on "no". Succeeds only if the user confirms.
review_plan() {
    local intro="$1" plan="$2" summary="${3-}" metas="" warning="" confirm confirm_text
    shift $(( $# < 3 ? $# : 3 ))
    confirm="$(msg confirm_plan)" confirm_text="$(msg confirm_plan_text)"
    if metas="$(plan_meta_packages "$plan" "$@")"; then
        meta_warning_text "$metas"
        warning="$REPLY"
        confirm="$(msg confirm_plan_meta)" confirm_text="$(msg confirm_plan_meta_text)"
    fi
    # The count closes the summary, right above the question (literal \n: the
    # summary is formatted by the dialogs and by text_print).
    if plan_count_text "$plan" "$@"; then summary+="${summary:+\\n}${REPLY}\\n"; fi
    plan_dialog "$intro" "$plan" "$summary" "$warning" "$confirm" "$confirm_text"
}

# Re-simulates the operation and compares it with the plan the user
# confirmed. Succeeds only if both plans are identical, so a change in the
# system between confirmation and execution can never run an unreviewed plan.
# $1 = confirmed plan, $2.. = the arguments of pm_simulate (for example: purge
# firefox).
plan_still_valid() {
    local confirmed="$1"; shift
    pm_simulate "$@" || return 1
    [ "$(plan_fingerprint "$PLAN_OUTPUT")" = "$(plan_fingerprint "$confirmed")" ]
}

# Shows the error of a failed simulation. $1 = what the command printed: the
# manager's text or, with dnf (its simulation runs through priv_run), that of
# the privilege command if it fails after plan_authorize. Both end with status
# 1, so the title does not say who failed.
show_plan_error() {
    local error_msg
    msgf_v error_msg plan_error "$1"
    show_message "$error_msg" big
}

# Before a simulation, tells in the terminal that the manager may ask for the
# password (pm_plan_needs_privileges). Prints nothing for a manager that does not.
plan_password_hint() {
    pm_plan_needs_privileges || return 0
    text_wrap "$(msg plan_password_note)"
    echo
}

# Before a simulation, gets the administrator rights if the manager needs them
# to calculate a plan (pm_plan_needs_privileges), as priv_authenticate does for a
# removal: a cancelled or wrong password is then told as that (priv_denied),
# not as an error of the plan. Status 0 = go on; PRIV_STATUS_DENIED = no rights
# (the message is shown).
plan_authorize() {
    pm_plan_needs_privileges || return 0
    priv_authenticate && return 0
    show_message "$(msg priv_denied)"
    return "$PRIV_STATUS_DENIED"
}

# ----------------------------------------------------------------------------
# Atomic writes and removal records
# ----------------------------------------------------------------------------
LAST_RECORD=""
RECORD_SEQ=0

# The removal in progress (if any), so that an interruption can still leave an
# honest record of it (see on_exit).
ACTIVE_RECORD=""
ACTIVE_PLAN=""
ACTIVE_REQUEST=""
ACTIVE_STORE=0      # 1 if the removal in progress is of Flatpak/Snap (write_store_record)
ACTIVE_CLEAN=0      # 1 if the run in progress is a deep cleanup (write_clean_record)
LOCK_FD=""

# Persistent state directory (XDG Base Directory: $XDG_STATE_HOME, default
# ~/.local/state). A relative XDG_STATE_HOME is invalid by the specification
# and is ignored.
state_dir() {
    local base="${XDG_STATE_HOME:-}"
    [[ "$base" == /* ]] || base="$HOME/.local/state"
    printf '%s/mintapp-remover' "${base%/}"
}

# Creates the state directory, private to the user (mode 700): removal records
# list what was installed on this machine.
ensure_state_dir() {
    local dir
    dir="$(state_dir)"
    mkdir -p -- "$dir" && chmod 700 -- "$dir"
}

# Writes stdin to the file $1 atomically, with file mode $2 (default 600). The
# data goes to a temporary file in the same directory (same filesystem, so the
# final rename is atomic), is flushed to disk, and only then replaces the
# destination: a reader, a crash or a power loss can never leave a half-written
# file at the final path. The temporary file is removed on any failure and on
# Ctrl-C, SIGTERM and SIGHUP. "mv -T" makes a directory an invalid destination
# instead of moving the file inside it.
atomic_write() {
    local dest="$1" mode="${2:-600}"
    (
        dir="$(dirname -- "$dest")"
        mkdir -p -- "$dir" || exit 1
        tmp="$(mktemp -- "$dir/.tmp.XXXXXX")" || exit 1
        trap '[ -z "$tmp" ] || rm -f -- "$tmp"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        trap 'exit 129' HUP
        cat > "$tmp" || exit 1
        chmod -- "$mode" "$tmp" || exit 1
        sync -- "$tmp" 2>/dev/null || true
        mv -fT -- "$tmp" "$dest" || exit 1
        tmp=""
        sync -- "$dir" 2>/dev/null || true
    )
}

# Writes (atomically) a removal record.
# $1 = file, $2 = status, $3 = plan, $4 = requested operation.
write_removal_record() {
    local file="$1" status="$2" plan="$3" request="$4"
    {
        printf '# MintApp Remover removal record\n'
        printf '# Date: %s\n' "$(date -Is)"
        printf '# Status: %s\n' "$status"
        if [[ "$status" == interrupted* ]]; then
            printf '# The run was interrupted: part of this plan may already be applied.\n'
            pm_interrupt_hint
        fi
        printf '# Operation: %s\n' "$(pm_operation_text "$request")"
        printf '#\n# Packages in the %s plan:\n' "$PM"
        grep -E '^(Purg|Remv) ' <<< "$plan" || true
        printf '#\n# To reinstall (review first; purged configuration files are not restored):\n'
        printf '# %s %s %s\n' "$(priv_name)" "$(pm_install_text)" "$(plan_package_names "$plan")"
    } | atomic_write "$file"
}

# ----------------------------------------------------------------------------
# Flatpak and Snap (4.5): identifiers, plan lines and removal records. What
# comes from a launcher or a store is data, never a command: an identifier
# reaches command lines and records only if it matches the strict patterns
# below (so never one that reads as an option, such as "-rf", or that carries
# spaces, quotes or control characters).
# A plan line is "flatpak SCOPE ID [REMOTE]" (SCOPE: system or user) or
# "snap system NAME".
# ----------------------------------------------------------------------------

# Succeeds if $1 is a Flatpak application ID: three or more elements joined by
# dots. The first has letters, digits and "_" and does not start with a digit;
# the others may also have "-" but do not start with it.
is_flatpak_id() {
    local first="${ID_UPPER}${ID_LOWER}_" more="${ID_UPPER}${ID_LOWER}${ID_DIGIT}_"
    [ "${#1}" -le 255 ] && [[ "$1" =~ ^[${first}][${more}]*(\.[${more}][${more}-]*){2,}$ ]]
}

# Succeeds if $1 is a Snap name: 2 to 40 lowercase letters, digits and single
# hyphens (none at the ends), with at least one letter.
is_snap_name() {
    local low="$ID_LOWER$ID_DIGIT"
    [ "${#1}" -ge 2 ] && [ "${#1}" -le 40 ] || return 1
    [[ "$1" =~ ^[${low}]+(-[${low}]+)*$ ]] && [[ "$1" == *[${ID_LOWER}]* ]]
}

# Succeeds if $1 is a Flatpak remote name (flathub, fedora, a user remote...).
is_flatpak_remote() {
    local any="$ID_UPPER$ID_LOWER$ID_DIGIT"
    [ "${#1}" -le 64 ] && [[ "$1" =~ ^[${any}][${any}._-]*$ ]]
}

# Reads the plan line $1 into STORE_KIND, STORE_SCOPE, STORE_ID and
# STORE_REMOTE (empty when there is none). Fails, with all four empty, if the
# line has anything else or any field is not valid.
parse_store_line() {
    local extra=""
    STORE_KIND="" STORE_SCOPE="" STORE_ID="" STORE_REMOTE=""
    read -r STORE_KIND STORE_SCOPE STORE_ID STORE_REMOTE extra <<< "$1" || true
    case "$STORE_KIND" in
        flatpak)
            [ -z "$extra" ] && { [ "$STORE_SCOPE" = system ] || [ "$STORE_SCOPE" = user ]; } \
                && is_flatpak_id "$STORE_ID" && { [ -z "$STORE_REMOTE" ] || is_flatpak_remote "$STORE_REMOTE"; } \
                && return 0 ;;
        snap)
            [ "$STORE_SCOPE" = system ] && [ -z "$STORE_REMOTE" ] \
                && is_snap_name "$STORE_ID" && return 0 ;;
    esac
    STORE_KIND="" STORE_SCOPE="" STORE_ID="" STORE_REMOTE=""
    return 1
}

# Prints the command that installs again the application read by
# parse_store_line (the remote only if it is known).
store_reinstall_hint() {
    case "$STORE_KIND" in
        flatpak)
            if [ "$STORE_SCOPE" = system ]; then
                printf '%s flatpak install --system%s %s' "$(priv_name)" "${STORE_REMOTE:+ $STORE_REMOTE}" "$STORE_ID"
            else
                printf 'flatpak install --user%s %s' "${STORE_REMOTE:+ $STORE_REMOTE}" "$STORE_ID"
            fi ;;
        snap) printf '%s snap install %s' "$(priv_name)" "$STORE_ID" ;;
    esac
}

# Writes (atomically) the record of a Flatpak/Snap removal.
# $1 = file, $2 = status, $3 = plan, one line per application, $4 = optional,
# the lines of the plan whose removal failed: they are listed apart and get no
# reinstall hint, because they are still installed. A line that is not valid is
# neither written nor given a hint; only how many were left out.
write_store_record() {
    local file="$1" status="$2" plan="$3" failed_plan="${4-}" line entry bad=0 flatpaks=0 snaps=0
    local -a entries=() hints=() kept=()
    local -A failed=()
    while IFS= read -r line; do
        if parse_store_line "$line"; then failed["$STORE_KIND $STORE_SCOPE $STORE_ID${STORE_REMOTE:+ $STORE_REMOTE}"]=1; fi
    done <<< "$failed_plan"
    while IFS= read -r line; do
        [ -n "${line//[[:space:]]/}" ] || continue
        if parse_store_line "$line"; then
            entry="$STORE_KIND $STORE_SCOPE $STORE_ID${STORE_REMOTE:+ $STORE_REMOTE}"
            entries+=("$entry")
            if [ -n "${failed[$entry]:-}" ]; then kept+=("$entry"); else hints+=("$(store_reinstall_hint)"); fi
            if [ "$STORE_KIND" = flatpak ]; then flatpaks=1; else snaps=1; fi
        else
            bad=$((bad + 1))
        fi
    done <<< "$plan"
    {
        printf '# MintApp Remover removal record\n'
        printf '# Date: %s\n' "$(date -Is)"
        printf '# Status: %s\n' "$status"
        if [[ "$status" == interrupted* ]]; then
            printf '# The run was interrupted: part of this plan may already be applied.\n'
            if [ "$flatpaks" -eq 1 ]; then printf '# See what is still installed: flatpak list --app\n'; fi
            if [ "$snaps" -eq 1 ]; then printf '# See what is still installed: snap list\n'; fi
        fi
        if [ "$flatpaks" -eq 1 ]; then printf '# Operation: flatpak uninstall\n'; fi
        if [ "$snaps" -eq 1 ]; then printf '# Operation: snap remove\n'; fi
        printf '#\n# Applications in the plan:\n'
        if [ "${#entries[@]}" -gt 0 ]; then printf '%s\n' "${entries[@]}"; fi
        if [ "$bad" -gt 0 ]; then printf '# (%s invalid line(s) left out)\n' "$bad"; fi
        if [ "${#kept[@]}" -gt 0 ]; then
            printf '#\n# Not removed (the command failed):\n'
            printf '%s\n' "${kept[@]}"
        fi
        if [ "${#hints[@]}" -gt 0 ]; then
            printf '#\n# To reinstall (review first; the remote or the channel may have changed):\n'
            printf '# %s\n' "${hints[@]}"
        fi
    } | atomic_write "$file"
}

# Runs the real removal (pm_run), writing a record before ("started")
# and after (final status). The second write atomically replaces the first, so
# an interrupted run still leaves a complete record of what was planned.
# $1 = confirmed plan, $2 = action (purge/autoremove), $3.. = packages.
# Sets LAST_RECORD to the record path ("" if it could not be written). Status:
# the manager's, or PRIV_STATUS_DENIED (nothing ran, no record) when the windows
# could not get administrator rights.
execute_removal() {
    local plan="$1" action="$2" progress_text; shift 2
    local record status outcome
    LAST_RECORD=""
    # In windows the password comes first: if it is not given nothing is
    # recorded or run.
    priv_authenticate || return "$PRIV_STATUS_DENIED"
    RECORD_SEQ=$((RECORD_SEQ + 1))
    record="$(state_dir)/removal-$(date +%Y%m%d-%H%M%S)-$$-$RECORD_SEQ.txt"

    ensure_state_dir || true
    if write_removal_record "$record" "started" "$plan" "$action $*"; then
        LAST_RECORD="$record"
    fi

    ACTIVE_RECORD="$LAST_RECORD"
    ACTIVE_PLAN="$plan"
    ACTIVE_REQUEST="$action $*"
    if [ "$action" = "autoremove" ]; then progress_text="$(msg cleaning)"; else progress_text="$(msg uninstalling)"; fi
    run_pm_step "$progress_text" "$action" "$@"
    status=$?
    ACTIVE_RECORD=""

    if [ -n "$LAST_RECORD" ]; then
        outcome="completed"
        [ "$status" -ne 0 ] && outcome="failed ($(pm_tool) exit code $status)"
        write_removal_record "$record" "$outcome" "$plan" "$action $*" || LAST_RECORD=""
    fi
    return "$status"
}

# Text line about the removal record, for result screens.
record_note_text() {
    local note
    if [ -n "$LAST_RECORD" ]; then
        msgf_v note record_saved "$LAST_RECORD"
    else
        note="$(msg record_failed)"
    fi
    printf '\n\n%s' "$note"
}

# ----------------------------------------------------------------------------
# Flatpak and Snap (4.5b): plan, confirmation and removal. The request is a list
# of plan lines (see parse_store_line), one per application. Unlike packages, there
# is no simulation: the plan is the request checked against what is installed
# now (store_make_plan), and the same check is made again right before the
# removal (store_plan_still_valid), so only the plan the user confirmed runs.
# ----------------------------------------------------------------------------
STORE_PLAN=""            # made by store_make_plan: valid lines of installed applications
STORE_FAILED=""          # the plan lines whose removal failed in the last run
STORE_FAILURE_TAIL=""    # last lines of the output of the first removal that failed (windows)
STORE_TOTAL=0            # applications the last run tried to remove
STORE_FAILED_N=0         # of those, how many failed

# Succeeds if the application read by parse_store_line is installed now. A
# missing flatpak or snap command counts as "not installed".
store_installed() {
    case "$STORE_KIND" in
        flatpak) flatpak info "--$STORE_SCOPE" "$STORE_ID" >/dev/null 2>&1 </dev/null ;;
        snap) snap list "$STORE_ID" >/dev/null 2>&1 </dev/null ;;
        *) return 1 ;;
    esac
}

# Makes the plan of the request $1 (plan lines, one per application): STORE_PLAN
# gets the valid lines of the applications installed now, as "kind scope id
# [remote]", sorted, one per application (the first of a repeated one stays).
# Fails, with STORE_PLAN empty, if nothing is left.
store_make_plan() {
    local line
    local -a entries=()
    local -A seen=()
    STORE_PLAN=""
    while IFS= read -r line; do
        parse_store_line "$line" || continue
        [ -z "${seen[$STORE_KIND $STORE_SCOPE $STORE_ID]:-}" ] || continue
        seen["$STORE_KIND $STORE_SCOPE $STORE_ID"]=1
        store_installed || continue
        entries+=("$STORE_KIND $STORE_SCOPE $STORE_ID${STORE_REMOTE:+ $STORE_REMOTE}")
    done <<< "$1"
    [ "${#entries[@]}" -gt 0 ] || return 1
    STORE_PLAN="$(printf '%s\n' "${entries[@]}" | LC_ALL=C sort)"
}

# Fingerprint of a plan: SHA-256 of its sorted lines.
store_plan_fingerprint() {
    local lines
    lines="$(LC_ALL=C sort <<< "$1")"
    sha256sum <<< "$lines" | cut -d' ' -f1
}

# Makes the plan of the request $2 again and compares it with the plan $1 that
# the user confirmed. Succeeds only if both are the same. It leaves the new
# plan in STORE_PLAN, so a caller keeps its own copy of the confirmed one.
store_plan_still_valid() {
    store_make_plan "$2" || return 1
    [ "$(store_plan_fingerprint "$STORE_PLAN")" = "$(store_plan_fingerprint "$1")" ]
}

# The plan $1 as text for the person, one line per application:
# "  Flatpak: org.mozilla.firefox (system-wide, flathub)".
store_plan_text() {
    local line scope text=""
    while IFS= read -r line; do
        parse_store_line "$line" || continue
        if [ "$STORE_SCOPE" = user ]; then scope="$(msg store_scope_user)"; else scope="$(msg store_scope_system)"; fi
        text+="  ${STORE_KIND^}: ${STORE_ID} (${scope}${STORE_REMOTE:+, $STORE_REMOTE})"$'\n'
    done <<< "$1"
    printf '%s' "${text%$'\n'}"
}

# Shows the plan $1 and asks for confirmation (plan_dialog). Succeeds only if
# the user confirms.
review_store_plan() {
    plan_dialog "$(msg store_plan_intro)" "$(store_plan_text "$1")" "" "" "$(msg store_confirm)" "$(msg store_confirm_text)" all
}

# Succeeds if some application of the plan $1 needs administrator rights: the
# Flatpaks of the system and every Snap.
store_plan_needs_priv() {
    local line
    while IFS= read -r line; do
        parse_store_line "$line" || continue
        { [ "$STORE_KIND" = flatpak ] && [ "$STORE_SCOPE" = user ]; } || return 0
    done <<< "$1"
    return 1
}

# Uninstalls the application read by parse_store_line with the command of its
# store. The Flatpaks of the system and the Snaps go through priv_run; a Flatpak
# of the user needs no rights. The identifiers are valid, so none can read as an
# option. Status: the command's.
store_uninstall_cmd() {
    case "$STORE_KIND" in
        flatpak)
            if [ "$STORE_SCOPE" = system ]; then
                priv_run flatpak uninstall --system --noninteractive -y "$STORE_ID"
            else
                flatpak uninstall --user --noninteractive -y "$STORE_ID"
            fi ;;
        snap) priv_run snap remove "$STORE_ID" ;;
        *) return 2 ;;
    esac
}

# Runs store_uninstall_cmd for the application read by parse_store_line: in
# windows with the progress window (the last lines of its output stay in
# STEP_TAIL), otherwise on the terminal under a line that says which one it is.
store_run_step() {
    local text
    msgf_v text store_removing "$STORE_ID"
    STEP_TAIL=""
    if [ "$UI_ENGINE" = "gui" ]; then
        run_gui_step "$text" store_uninstall_cmd
    else
        text_wrap "$text"
        store_uninstall_cmd
    fi
}

# Runs the real removal of the confirmed plan $1, one application at a time (one
# that fails does not stop the rest), with a record before ("started") and
# after (the final status), as execute_removal does. Sets LAST_RECORD
# ("" if it could not be written), STORE_FAILED, STORE_FAILURE_TAIL, STORE_TOTAL
# and STORE_FAILED_N. Status: 0 if all were removed; PRIV_STATUS_DENIED (nothing
# ran, no record) if the windows could not get administrator rights; otherwise
# the status of the first command that failed.
execute_store_removal() {
    local plan="$1" line record status first=0 outcome
    LAST_RECORD="" STORE_FAILED="" STORE_FAILURE_TAIL="" STORE_TOTAL=0 STORE_FAILED_N=0
    if store_plan_needs_priv "$plan"; then
        priv_authenticate || return "$PRIV_STATUS_DENIED"
        # The hints of the first record name the command that the removal will use.
        [ -n "$PRIV_CMD" ] || detect_privilege || true
    fi
    RECORD_SEQ=$((RECORD_SEQ + 1))
    record="$(state_dir)/removal-$(date +%Y%m%d-%H%M%S)-$$-$RECORD_SEQ.txt"
    ensure_state_dir || true
    if write_store_record "$record" "started" "$plan"; then
        LAST_RECORD="$record"
    fi
    ACTIVE_STORE=1 ACTIVE_PLAN="$plan" ACTIVE_REQUEST=""
    ACTIVE_RECORD="$LAST_RECORD"
    # The plan comes in through fd 3, so that no command of the loop can read it.
    while IFS= read -r line <&3; do
        parse_store_line "$line" || continue
        STORE_TOTAL=$((STORE_TOTAL + 1))
        store_run_step
        status=$?
        if [ "$status" -ne 0 ]; then
            STORE_FAILED_N=$((STORE_FAILED_N + 1))
            STORE_FAILED+="${STORE_FAILED:+$'\n'}$line"
            if [ "$first" -eq 0 ]; then first="$status"; STORE_FAILURE_TAIL="$STEP_TAIL"; fi
        fi
    done 3<<< "$plan"
    ACTIVE_RECORD="" ACTIVE_STORE=0

    if [ -n "$LAST_RECORD" ]; then
        outcome="completed"
        [ "$first" -eq 0 ] || outcome="failed ($STORE_FAILED_N of $STORE_TOTAL applications not removed)"
        write_store_record "$record" "$outcome" "$plan" "$STORE_FAILED" || LAST_RECORD=""
    fi
    return "$first"
}

# Puts in REPLY the text that tells why a Flatpak/Snap removal failed ($1 = its
# status): no rights, the last lines of the output in windows (nothing above to
# read) or a pointer to the terminal.
store_error_text() {
    if [ "$1" -eq "$PRIV_STATUS_DENIED" ]; then
        REPLY="$(msg priv_denied)"
    elif [ "$UI_ENGINE" = "gui" ]; then
        msgf_v REPLY store_error_gui "$STORE_FAILED_N" "$STORE_TOTAL" "$1" "$STORE_FAILURE_TAIL"
    else
        msgf_v REPLY store_error "$STORE_FAILED_N" "$STORE_TOTAL" "$1"
    fi
}

# Runs the real removal of a confirmed plan and shows the result. $1 = plan.
run_store_removal() {
    local status result record_note=""
    header
    text_wrap "$(msg uninstalling)"
    echo
    execute_store_removal "$1"
    status=$?
    echo
    if [ "$status" -eq 0 ]; then
        result="$(msg uninstall_ok)"
        if removed_stores_text "$1"; then result+="\n\n${REPLY}"; fi
    else
        store_error_text "$status"
        result="$REPLY"
    fi
    [ "$status" -eq "$PRIV_STATUS_DENIED" ] || record_note="$(record_note_text)"
    show_removal_result "$status" "$result" "$record_note"
    return "$status"
}

# The whole flow for Flatpaks and Snaps, as confirm_and_purge is for packages:
# makes the plan of the request $1, shows it, asks, checks again that it has
# not changed and only then removes. $1 = plan lines, one per application.
confirm_and_remove_stores() {
    local request="$1" plan
    if [ -z "${request//[[:space:]]/}" ]; then
        show_message "$(msg none_selected)"
        return
    fi
    header
    text_wrap "$(msg store_plan_calculating)"
    echo
    if ! store_make_plan "$request"; then
        show_message "$(msg none_still_installed)"
        return
    fi
    plan="$STORE_PLAN"
    review_store_plan "$plan" || return
    if ! store_plan_still_valid "$plan" "$request"; then
        show_message "$(msg plan_changed)"
        return
    fi
    run_store_removal "$plan"
}

# ----------------------------------------------------------------------------
# Configuration: $XDG_CONFIG_HOME/mintapp-remover/config (default
# ~/.config/mintapp-remover/config), private to the user (directory 700, file
# 600). One "key=value" per line. The file is read as data, never sourced or
# evaluated, and only the first CONFIG_MAX_BYTES bytes are read. Every key and
# value is checked (config_valid); anything else is ignored, so a damaged or
# hand-edited file cannot change what the program does. Keys:
#   interface=terminal|gui   how the program opens
#   language=es|en           interface language (MINTAPP_LANG prevails)
#   help_seen=yes|no         the navigation help was already shown
# ----------------------------------------------------------------------------
CONFIG_KEYS=(interface language help_seen)
CONFIG_MAX_BYTES=4096
declare -A CONFIG=()
CONFIG_LOADED=0

# Configuration directory. A relative XDG_CONFIG_HOME is invalid by the XDG
# specification and is ignored. Fails (no output) without a usable base.
config_dir() {
    local base="${XDG_CONFIG_HOME:-}"
    if [[ "$base" != /* ]]; then
        base="${HOME:-}"
        [[ "$base" == /* ]] || return 1
        base="${base%/}/.config"
    fi
    printf '%s/mintapp-remover' "${base%/}"
}

# Succeeds if $1 is a known configuration key.
config_known() {
    local key
    for key in "${CONFIG_KEYS[@]}"; do
        [ "$key" != "$1" ] || return 0
    done
    return 1
}

# Succeeds if $1 is a known key and $2 one of its allowed values.
config_valid() {
    case "$1=$2" in
        interface=terminal|interface=gui) return 0 ;;
        language=es|language=en) return 0 ;;
        help_seen=yes|help_seen=no) return 0 ;;
    esac
    return 1
}

# Reads the file into CONFIG, discarding what was loaded before. In the file,
# spaces or tabs around the key and the value (so also a CRLF line end) and
# capitals in the value are tolerated. Fails if there is no readable regular
# file; CONFIG is then empty.
config_load() {
    local dir file line key value
    CONFIG=()
    CONFIG_LOADED=1
    dir="$(config_dir)" || return 1
    file="$dir/config"
    [ -f "$file" ] && [ -r "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        [ "${#line}" -le 256 ] || continue
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}" value="${line#*=}"
        key="${key#"${key%%[![:space:]]*}"}" key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}" value="${value%"${value##*[![:space:]]}"}"
        value="${value,,}"
        if config_valid "$key" "$value"; then CONFIG[$key]="$value"; fi
    done < <(head -c "$CONFIG_MAX_BYTES" -- "$file" 2>/dev/null | tr -d '\000')
    return 0
}

# Prints the value of key $1 (loading the file on first use). Fails, printing
# nothing, if the key is unknown or has no valid value in the file.
config_get() {
    [ "$CONFIG_LOADED" -eq 1 ] || config_load || true
    config_known "$1" || return 1
    [ -n "${CONFIG[$1]+x}" ] || return 1
    printf '%s' "${CONFIG[$1]}"
}

# Text of the file: a header and one line per key that has a value.
config_render() {
    local key
    printf '# MintApp Remover configuration; the program rewrites this file.\n'
    printf '# One key=value per line. interface: terminal | gui; language: es | en; help_seen: yes | no\n'
    for key in "${CONFIG_KEYS[@]}"; do
        [ -z "${CONFIG[$key]+x}" ] || printf '%s=%s\n' "$key" "${CONFIG[$key]}"
    done
}

# Saves $1=$2, keeping the other keys as they are on disk now. Status 2: unknown
# key or invalid value (nothing is touched); 1: it could not be written (the
# file is left as it was, and CONFIG goes back to it). It prints nothing: the
# caller decides what to tell the person.
config_set() {
    local dir
    config_valid "$1" "$2" || return 2
    dir="$(config_dir)" || return 1
    config_load || true
    CONFIG[$1]="$2"
    if { (umask 077; mkdir -p -- "$dir") && chmod 700 -- "$dir" \
        && config_render | atomic_write "$dir/config" 600; } 2>/dev/null; then
        return 0
    fi
    config_load || true
    return 1
}

# Applies the saved language unless MINTAPP_LANG names one (it prevails). It runs
# in main, before any screen: detect_language has already chosen from the
# locale when the file was loaded.
apply_saved_language() {
    local saved
    forced_language >/dev/null && return 0
    saved="$(config_get language)" || return 0
    set_language "$saved"
}

# Succeeds if the navigation help was already shown on this machine.
help_already_seen() {
    [ "$(config_get help_seen || true)" = "yes" ]
}

# Records that the navigation help was shown (best effort).
mark_help_seen() {
    config_set help_seen yes || true
}

# ----------------------------------------------------------------------------
# Option 1: Detect applications
# ----------------------------------------------------------------------------
# What detection knows about each application found (same index as
# DETECTED_KEYS): main package, its version, how many more packages the entry
# has installed, and the installed size of all of them in KiB. DETECTED_HAY is
# the folded text a search looks into (names and descriptions in both
# languages, so "browser" finds Firefox in a Spanish session too).
DETECTED_MAIN=()
DETECTED_VERSION=()
DETECTED_EXTRA=()
DETECTED_SIZE_KB=()
DETECTED_HAY=()
# Lists with fewer entries than this are short enough to read whole: they get
# no search.
SEARCH_MIN_ITEMS=8

# Puts a size given in KiB in REPLY: "845 KB", "12.3 MB", "1.2 GB" (a comma
# instead of the point in Spanish), rounded to the nearest tenth. Anything that
# is not a number counts as 0.
format_size_kb() {
    local kb="${1:-0}" unit="MB" tenths sep="."
    # More than 15 digits would wrap around in the arithmetic: not a size.
    [[ "$kb" =~ ^[0-9]{1,15}$ ]] || kb=0
    kb=$((10#$kb))
    [ "$APP_LANG" != "es" ] || sep=","
    if [ "$kb" -lt 1024 ]; then
        REPLY="$kb KB"
        return 0
    fi
    tenths=$(( (kb * 10 + 512) / 1024 ))
    # 1023.96 MB rounds up to 1024.0 MB: that is 1.0 GB.
    if [ "$tenths" -ge 10240 ]; then
        tenths=$(( (kb * 10 + 524288) / 1048576 )); unit="GB"
    fi
    REPLY="$(( tenths / 10 ))${sep}$(( tenths % 10 )) $unit"
}

# Reads name, version and installed size of the installed packages $@ with ONE
# question to the manager (pm_detail) and sets DETAIL_MAIN and DETAIL_VERSION
# (of the first one),
# DETAIL_EXTRA (how many more there are) and DETAIL_SIZE (KiB, all together).
load_package_detail() {
    local pkg version size count=0 total=0
    DETAIL_MAIN="" DETAIL_VERSION="" DETAIL_EXTRA=0 DETAIL_SIZE=0
    [ "$#" -gt 0 ] || return 0
    while IFS=$'\t' read -r pkg version size; do
        [ -n "$pkg" ] || continue
        if [ "$count" -eq 0 ]; then
            DETAIL_MAIN="$(sanitize_display "$pkg")"
            DETAIL_VERSION="$(sanitize_display "$version")"
        fi
        count=$((count + 1))
        # Up to 12 digits (a petabyte in KiB); more would wrap around.
        if [[ "$size" =~ ^[0-9]{1,12}$ ]]; then total=$((total + 10#$size)); fi
    done < <(pm_detail "$@")
    DETAIL_EXTRA=$(( count > 0 ? count - 1 : 0 ))
    DETAIL_SIZE=$total
}

# Text a search looks into for the catalog entry $1 with packages $2 (comma
# separated): both languages' name and description, and the packages. Puts the
# folded text in REPLY.
catalog_haystack() {
    fold_search "${APP_NAME_ES[$1]:-} ${APP_NAME_EN[$1]:-} ${APP_DESC_ES[$1]:-} ${APP_DESC_EN[$1]:-} ${2//,/ }"
}

# Detail line of detected application $1: "firefox 128.0, 245.1 MB" or, with
# more packages, "libreoffice 24.2 (+7 more), 612.4 MB".
detail_text() {
    local i="$1" text more
    text="${DETECTED_MAIN[i]}"
    [ -z "${DETECTED_VERSION[i]}" ] || text+=" ${DETECTED_VERSION[i]}"
    if [ "${DETECTED_EXTRA[i]}" -gt 0 ]; then
        msgf_v more detail_more "${DETECTED_EXTRA[i]}"
        text+=" ($more)"
    fi
    if [ "${DETECTED_SIZE_KB[i]}" -gt 0 ]; then
        format_size_kb "${DETECTED_SIZE_KB[i]}"
        text+=", $REPLY"
    fi
    printf '%s' "$text"
}

# Looks for the catalog applications that are installed and fills the
# DETECTED_* arrays. It shows nothing.
scan_catalog() {
    DETECTED_NAMES=()
    DETECTED_KEYS=()
    DETECTED_PACKAGES=()
    DETECTED_DESC=()
    DETECTED_MAIN=()
    DETECTED_VERSION=()
    DETECTED_EXTRA=()
    DETECTED_SIZE_KB=()
    DETECTED_HAY=()

    local entry key pkgs
    local -a installed=()
    for entry in "${CATALOG[@]}"; do
        IFS='|' read -r key pkgs <<< "$entry"
        if package_installed "$pkgs"; then
            mapfile -t installed < <(installed_packages_from_list "$pkgs")
            load_package_detail "${installed[@]+"${installed[@]}"}"
            DETECTED_KEYS+=("$key")
            DETECTED_NAMES+=("$(catalog_name "$key")")
            DETECTED_PACKAGES+=("$pkgs")
            DETECTED_DESC+=("$(catalog_desc "$key")")
            DETECTED_MAIN+=("$DETAIL_MAIN")
            DETECTED_VERSION+=("$DETAIL_VERSION")
            DETECTED_EXTRA+=("$DETAIL_EXTRA")
            DETECTED_SIZE_KB+=("$DETAIL_SIZE")
            catalog_haystack "$key" "$pkgs"
            DETECTED_HAY+=("$REPLY")
        fi
    done

    DETECTION_DONE=1
}

# One line of the plain-text detection list: a check mark, the name and its
# detail between brackets, wrapped to the screen width. $1 = name, $2 = detail.
text_detect_line() {
    local line first=1
    set_text_width
    while IFS= read -r line; do
        if [ "$first" -eq 1 ]; then
            printf '  %b%s%b %s\n' "$C_OK" "$SYM_OK" "$C_RESET" "$line"
            first=0
        else
            printf '    %s\n' "$line"
        fi
    done < <(printf '%s  [%s]\n' "$1" "$2" | wrap_text $(( TEXT_W - 4 )))
}

# Shows the detected applications with their package, version and size. With
# a long list it also offers the search: the "No" button in whiptail (the same
# trick as the language button), the S key in text mode. Esc, Enter and end of
# input leave the screen.
show_detected() {
    local query="" total="${#DETECTED_NAMES[@]}" can_search=0 count i sum_kb answer rest
    local status_line size_line summary status
    local -a visible=()
    [ "$total" -lt "$SEARCH_MIN_ITEMS" ] || can_search=1
    while true; do
        if [ "$can_search" -eq 1 ]; then
            search_filter DETECTED_HAY "$query"
        else
            VISIBLE_IDX=("${!DETECTED_NAMES[@]}")
        fi
        visible=("${VISIBLE_IDX[@]+"${VISIBLE_IDX[@]}"}")
        count="${#visible[@]}"
        sum_kb=0
        for i in "${visible[@]+"${visible[@]}"}"; do sum_kb=$((sum_kb + DETECTED_SIZE_KB[i])); done
        status_line=""
        if [ -n "$query" ]; then msgf_v status_line search_status "$query" "$count" "$total"; fi
        size_line=""
        if [ "$sum_kb" -gt 0 ]; then
            format_size_kb "$sum_kb"
            msgf_v size_line detected_size "$REPLY"
        fi

        if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
            summary="$(msg detected_header):\n\n"
            [ -z "$status_line" ] || summary+="${status_line}\n\n"
            for i in "${visible[@]+"${visible[@]}"}"; do
                summary+="  ${SYM_OK} ${DETECTED_NAMES[$i]}  [$(detail_text "$i")]\n"
            done
            summary+="\n${count} $(count_detected "$count")"
            [ -z "$size_line" ] || summary+="\n${size_line}"
            if [ "$can_search" -eq 0 ]; then
                wt_msgbox "$summary" big
                return 0
            fi
            TUI_HOTKEYS="esc=0"     # Esc leaves the screen like OK: the key bar says so
            wt_yesno "$summary" "$(msg ok)" "$(msg search_button)" big "" choice
            status=$?
            TUI_HOTKEYS=""
            [ "$status" -eq 1 ] || return 0
            if ask_search "$query"; then query="$REPLY"; fi
        else
            header
            printf '%b%s%b\n' "$C_BOLD" "$(msg detected_header)" "$C_RESET"
            if [ -n "$status_line" ]; then text_wrap "$status_line"; fi
            echo
            for i in "${visible[@]+"${visible[@]}"}"; do
                text_detect_line "${DETECTED_NAMES[$i]}" "$(detail_text "$i")"
            done
            section_rule
            echo "${count} $(count_detected "$count")"
            if [ -n "$size_line" ]; then text_wrap "$size_line"; fi
            if [ "$can_search" -eq 0 ]; then
                pause
                return 0
            fi
            echo
            wrap_prompt "$(msg detect_text_prompt) "
            read -rp "$PROMPT_LAST" answer || return 0
            case "$answer" in
                [sS]|[sS]\ *)
                    rest="${answer#?}"
                    clean_query "$rest"
                    if [ -n "$REPLY" ]; then
                        query="$REPLY"
                    elif ask_search "$query"; then
                        query="$REPLY"
                    fi
                    ;;
                *) return 0 ;;
            esac
        fi
    done
}

# Option 1: looks for the installed catalog applications and shows them.
detect_programs() {
    scan_catalog
    show_detected
}

# Asks for a search text and puts the cleaned text in REPLY (empty = show
# everything). $1 = the current text, offered as the starting point in the
# dialog. Fails if the user cancels, so the caller keeps the current search.
ask_search() {
    local answer height
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_box_size normal
        wt_text "$(msg search_prompt)" "$WT_BOX_W"
        height=$(( WT_TEXT_LINES + 7 ))
        [ "$height" -le "$WT_BOX_H" ] || height="$WT_BOX_H"
        answer=$(wt --ok-button "$(msg ok)" --cancel-button "$(msg cancel)" \
            --inputbox "$WT_TEXT" -- "$height" "$WT_BOX_W" "$1" 3>&1 1>&2 2>&3) || return 1
    else
        read -rp "$(msg search_prompt_text) " answer || return 1
    fi
    clean_query "$answer"
}

# Recap of what a removal took away (6.2c): how many names there are and the
# first REMOVED_SHOWN of them; the rest are only counted ("+2 more").
REMOVED_SHOWN=6

# Puts in REPLY the names $@ in one line: the first REMOVED_SHOWN, separated by
# commas, and the rest counted ("+2 more").
removed_list() {
    local total=$# more list="" n=0 name
    for name in "$@"; do
        [ "$n" -lt "$REMOVED_SHOWN" ] || break
        list+="${list:+, }${name}"
        n=$(( n + 1 ))
    done
    if [ "$total" -gt "$n" ]; then
        msgf_v more detail_more $(( total - n ))
        list+=", ${more}"
    fi
    REPLY="$list"
}

# Puts in REPLY the recap line of the packages of the plan $1, which has just
# been carried out ("Removed packages (3): a, b, c"). Fails if the plan holds none.
removed_packages_text() {
    local name
    local -a all=() gone=()
    read -r -a all <<< "$(plan_package_names "$1")"
    for name in "${all[@]+"${all[@]}"}"; do
        if pm_valid_name "$name"; then gone+=("$name"); fi
    done
    [ "${#gone[@]}" -gt 0 ] || return 1
    removed_list "${gone[@]}"
    msgf_v REPLY result_removed_pkgs "${#gone[@]}" "$REPLY"
}

# The same for the Flatpak and Snap applications of the plan $1 (their ids).
removed_stores_text() {
    local line
    local -a gone=()
    while IFS= read -r line; do
        if parse_store_line "$line"; then gone+=("$STORE_ID"); fi
    done <<< "$1"
    [ "${#gone[@]}" -gt 0 ] || return 1
    removed_list "${gone[@]}"
    msgf_v REPLY result_removed_apps "${#gone[@]}" "$REPLY"
}

# Prints, in plain-text mode, the note about the record of a removal: wrapped to
# the screen, except a line that is a path (starts with /), which goes whole. The
# terminal wraps it by itself, and what is copied has no break inside the name
# (text_wrap would cut it). Blank lines in a row are squeezed into one, so the
# note is separated from what comes before it by a single blank line. An empty
# note prints nothing: pause, which comes next, brings its own blank line.
text_note() {
    local line blank=0
    [ -n "$1" ] || return 0
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            [ "$blank" -eq 1 ] || echo
            blank=1
        elif [[ "$line" == /* ]]; then
            printf '%s\n' "$line"; blank=0
        else
            text_print "$line"; blank=0
        fi
    done <<< "$1"
}

# Shows the result of a removal in the active interface. $1 = status of the
# removal (0 = done, in green; otherwise in the color of errors, C_ERR, which
# is yellow), $2 = result text, $3 = the note about the record (may be empty),
# $4 = size of the dialog (normal or big).
show_removal_result() {
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_msgbox "${2}${3}" "${4:-normal}"
    else
        if [ "$1" -eq 0 ]; then
            text_say "$C_OK" "$2"
        else
            text_say "$C_ERR" "$2"
        fi
        text_note "$3"
        pause
    fi
}

# Runs the real purge of a confirmed plan and shows the result, adapted to the
# active interface. $1 = confirmed plan, $2.. = packages to purge.
run_purge() {
    local plan="$1"; shift
    local -a pkgs=("$@")

    header
    text_wrap "$(msg uninstalling)"
    echo
    # Options 2 and 3 both end here: what was detected (option 2's list) and
    # the count of the main menu are taken again when next needed.
    MENU_APPS=-1 DETECTION_DONE=0
    execute_removal "$plan" purge "${pkgs[@]}"
    local status=$?
    echo

    local result record_note=""
    if [ "$status" -eq 0 ]; then
        result="$(msg uninstall_ok)"
        if removed_packages_text "$plan"; then result+="\n\n${REPLY}"; fi
    else
        removal_error_text "$status"
        result="$REPLY"
    fi
    [ "$status" -eq "$PRIV_STATUS_DENIED" ] || record_note="$(record_note_text)"
    show_removal_result "$status" "$result" "$record_note"
    return "$status"
}

# ----------------------------------------------------------------------------
# Selection lists with a search (Options 2 and 3). The entries keep their
# number (their index + 1) whatever the search shows, and what the user marked
# stays marked while the search changes: the marks live in an array with one
# 0/1 per entry, not in the dialog. With fewer than SEARCH_MIN_ITEMS entries
# the list is shown whole and without search.
# ----------------------------------------------------------------------------

# Checklist dialog with search. whiptail has no extra button, so the search is
# a first entry of the list: check it and press OK to search (the marks made
# so far are kept). $1 = prompt, $2 = labels, $3 = folded search texts and
# $4 = marks (0/1; updated), all three arrays given by name, one value per
# entry. $5 = optional array of tails: the end of each label (like "[package]"),
# kept whole when a long label has to be cut to the width of the box. Status:
# 0 = OK (marks updated), 1 = cancelled or Esc.
wt_checklist_search() {
    local prompt="$1" tails_name="${5:-}"
    local -n _wcs_labels="$2" _wcs_hay="$3" _wcs_sel="$4"
    local -n _wcs_tails="${tails_name:-_wcs_hay}"
    local total="${#_wcs_labels[@]}" can_search=0 query="" i tag idx want_search selection wt_status
    local status_line shown state label_w tail
    local -a args=() tags=()
    [ "$total" -lt "$SEARCH_MIN_ITEMS" ] || can_search=1
    while true; do
        if [ "$can_search" -eq 1 ]; then
            search_filter _wcs_hay "$query"
        else
            VISIBLE_IDX=("${!_wcs_labels[@]}")
        fi
        if [ -n "$query" ] && [ "${#VISIBLE_IDX[@]}" -eq 0 ]; then
            msgf_v status_line search_none "$query"
            wt_msgbox "$status_line"
            query=""
            continue
        fi
        shown="$prompt"
        if [ -n "$query" ]; then
            msgf_v status_line search_status "$query" "${#VISIBLE_IDX[@]}" "$total"
            shown+="\n${status_line}"
            search_hidden_notice _wcs_sel
            [ -z "$REPLY" ] || shown+="\n${REPLY}"
        fi
        # The box is measured first: the labels are fitted to its width.
        wt_list_prepare "$shown" "$(( ${#VISIBLE_IDX[@]} + can_search ))"
        wt_label_width "$WT_BOX_W" "$total"
        label_w="$REPLY"
        args=()
        if [ "$can_search" -eq 1 ]; then
            wt_fit_label "$label_w" "$(msg search_item)"
            args+=("S" "$REPLY" "OFF")
        fi
        for i in "${VISIBLE_IDX[@]+"${VISIBLE_IDX[@]}"}"; do
            state="OFF"
            [ "${_wcs_sel[$i]}" -ne 1 ] || state="ON"
            tail=""
            [ -z "$tails_name" ] || tail="${_wcs_tails[$i]}"
            wt_fit_label "$label_w" "${_wcs_labels[$i]}" "$tail"
            args+=("$((i+1))" "$REPLY" "$state")
        done

        selection=$(wt \
            --ok-button "$(msg ok)" --cancel-button "$(msg cancel)" \
            --checklist "$WT_TEXT" -- \
            "$WT_BOX_H" "$WT_BOX_W" "$WT_LIST_ROWS" \
            "${args[@]}" \
            3>&1 1>&2 2>&3)
        wt_status=$?
        [ "$wt_status" -eq 0 ] || return 1

        # The dialog decides the marks of the entries it showed; the marks of
        # the hidden ones stay as they were.
        for i in "${VISIBLE_IDX[@]+"${VISIBLE_IDX[@]}"}"; do _wcs_sel[i]=0; done
        want_search=0
        read -ra tags <<< "${selection//\"/}"
        for tag in "${tags[@]+"${tags[@]}"}"; do
            if [ "$tag" = "S" ] && [ "$can_search" -eq 1 ]; then
                want_search=1
                continue
            fi
            [[ "$tag" =~ ^[0-9]+$ ]] || continue
            idx=$((10#$tag - 1))
            [[ " ${VISIBLE_IDX[*]-} " == *" $idx "* ]] || continue
            _wcs_sel[idx]=1
        done
        [ "$want_search" -eq 1 ] || return 0
        if ask_search "$query"; then query="$REPLY"; fi
    done
}

# Plain-text selection list with search. $1 = kind of header (apps, advanced,
# clean_cats or clean_entries); $2 = names, $3 = labels shown after the name (the package; may be
# empty), $4 = descriptions shown under the name (may be empty), $5 = folded
# search texts and $6 = marks (0/1; updated), all arrays given by name. Type a
# number to mark or unmark, s to search ("s text" searches at once), c to
# confirm, 0 to go back. Status: 0 = confirmed, 1 = went back or end of input.
text_checklist_search() {
    local kind="$1"
    local -n _tcs_names="$2" _tcs_labels="$3" _tcs_descs="$4" _tcs_hay="$5" _tcs_sel="$6"
    local total="${#_tcs_names[@]}" can_search=0 query="" i num choice digits idx rest marker marked status_line
    [ "$total" -lt "$SEARCH_MIN_ITEMS" ] || can_search=1
    while true; do
        if [ "$can_search" -eq 1 ]; then
            search_filter _tcs_hay "$query"
        else
            VISIBLE_IDX=("${!_tcs_names[@]}")
        fi
        header
        case "$kind" in
            advanced) text_say "$C_WARN" "$(msg advanced_header)" ;;
            clean_cats) text_print "$(msg clean_pick_cats)" ;;
            clean_entries) text_wrap "$(msg clean_pick_entries)" ;;
            *) text_wrap "$(msg select_apps)" ;;
        esac
        text_wrap "$(msg advanced_text)"
        if [ "$can_search" -eq 1 ]; then
            text_wrap "$(msg search_hint_text)"
            if [ -n "$query" ]; then
                msgf_v status_line search_status "$query" "${#VISIBLE_IDX[@]}" "$total"
                text_wrap "$status_line"
                search_hidden_notice _tcs_sel
                [ -z "$REPLY" ] || text_say "$C_OK" "$REPLY"
            fi
        fi
        echo
        for i in "${VISIBLE_IDX[@]+"${VISIBLE_IDX[@]}"}"; do
            num=$(printf '%2d' "$((i+1))")
            marker="$SYM_OFF"; marked=0
            if [ "${_tcs_sel[$i]}" -eq 1 ]; then marker="$SYM_ON"; marked=1; fi
            text_entry "$num" "$marker" "${_tcs_names[$i]}" "${_tcs_labels[$i]}" "$marked"
            [ -z "${_tcs_descs[$i]}" ] || text_wrap_even "        ${_tcs_descs[$i]}"
        done
        if [ -n "$query" ] && [ "${#VISIBLE_IDX[@]}" -eq 0 ]; then
            msgf_v status_line search_none "$query"
            text_say "$C_ERR" "$status_line"
        fi

        section_rule
        read -rp "> " choice || return 1

        case "$choice" in
            0)
                return 1
                ;;
            c|C)
                return 0
                ;;
            [sS]|[sS]\ *)
                if [ "$can_search" -eq 0 ]; then
                    echo -e "${C_ERR}$(msg invalid)${C_RESET}"
                    sleep 1
                    continue
                fi
                rest="${choice#?}"
                clean_query "$rest"
                if [ -n "$REPLY" ]; then
                    query="$REPLY"
                elif ask_search "$query"; then
                    query="$REPLY"
                fi
                ;;
            ''|*[!0-9]*)
                echo -e "${C_ERR}$(msg invalid)${C_RESET}"
                sleep 1
                ;;
            *)
                # Ten digits or more (leading zeros apart) is never an entry,
                # and would wrap around in the arithmetic (2^64 + 1 would
                # mark entry 1).
                digits="${choice#"${choice%%[!0]*}"}"
                if [ "${#digits}" -gt 9 ]; then idx=-1; else idx=$((10#$choice - 1)); fi
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "$total" ] && [[ " ${VISIBLE_IDX[*]-} " == *" $idx "* ]]; then
                    if [ "${_tcs_sel[$idx]}" -eq 1 ]; then
                        _tcs_sel[idx]=0
                    else
                        _tcs_sel[idx]=1
                    fi
                else
                    echo -e "${C_ERR}$(msg out_of_range)${C_RESET}"
                    sleep 1
                fi
                ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# Option 2: Uninstall applications — whiptail version (checkboxes)
# ----------------------------------------------------------------------------
uninstall_programs_whiptail() {
    local -a labels=() selected=()
    local i
    for i in "${!DETECTED_NAMES[@]}"; do
        labels+=("${DETECTED_NAMES[$i]} ${SYM_DASH} ${DETECTED_DESC[$i]}")
        selected+=(0)
    done

    local help
    if [ "$UI_ENGINE" = "gui" ]; then help="$(msg select_help_gui)"; else help="$(msg select_help)"; fi
    wt_checklist_search "$(msg select_apps)\n${help}" labels DETECTED_HAY selected || return

    local -a to_remove_names=() to_remove_pkgs=()
    local pkg
    for i in "${!DETECTED_NAMES[@]}"; do
        [ "${selected[$i]}" -eq 1 ] || continue
        to_remove_names+=("${DETECTED_NAMES[$i]}")
        while IFS= read -r pkg; do
            to_remove_pkgs+=("$pkg")
        done < <(installed_packages_from_list "${DETECTED_PACKAGES[$i]}")
    done

    if [ "${#to_remove_names[@]}" -eq 0 ]; then
        wt_msgbox "$(msg none_selected)"
        return
    fi
    if [ "${#to_remove_pkgs[@]}" -eq 0 ]; then
        wt_msgbox "$(msg none_still_installed)"
        return
    fi

    confirm_and_purge to_remove_names to_remove_pkgs
    DETECTION_DONE=0
}

# ----------------------------------------------------------------------------
# Option 2: Uninstall applications — plain-text version (fallback)
# ----------------------------------------------------------------------------
uninstall_programs_text() {
    local -a no_labels=() selected=()
    local i
    for i in "${!DETECTED_NAMES[@]}"; do
        no_labels+=("")
        selected+=(0)
    done

    text_checklist_search apps DETECTED_NAMES no_labels DETECTED_DESC DETECTED_HAY selected || return

    local -a to_remove_names=() to_remove_pkgs=()
    local pkg
    for i in "${!DETECTED_NAMES[@]}"; do
        [ "${selected[$i]}" -eq 1 ] || continue
        to_remove_names+=("${DETECTED_NAMES[$i]}")
        while IFS= read -r pkg; do
            to_remove_pkgs+=("$pkg")
        done < <(installed_packages_from_list "${DETECTED_PACKAGES[$i]}")
    done

    if [ "${#to_remove_names[@]}" -eq 0 ]; then
        header
        text_wrap "$(msg none_selected)"
        pause
        return
    fi

    if [ "${#to_remove_pkgs[@]}" -eq 0 ]; then
        header
        text_wrap "$(msg none_still_installed)"
        pause
        return
    fi

    confirm_and_purge to_remove_names to_remove_pkgs
    DETECTION_DONE=0
}

# ----------------------------------------------------------------------------
# Option 2: Uninstall applications — dispatcher
# ----------------------------------------------------------------------------
uninstall_programs() {
    # Only scans: the list below already names every detected application, so the
    # read-only detection screen of option 1 would be one more screen to dismiss.
    if [ "$DETECTION_DONE" -eq 0 ]; then
        scan_catalog
    fi

    if [ "${#DETECTED_NAMES[@]}" -eq 0 ]; then
        if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
            wt_msgbox "$(msg none_candidate)"
        else
            header
            text_wrap "$(msg none_candidate)"
            pause
        fi
        return
    fi

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        uninstall_programs_whiptail
    else
        uninstall_programs_text
    fi
}

# ----------------------------------------------------------------------------
# Option 3: Find other applications (ADVANCED MODE)
# Instead of relying on fixed package names, it walks the real menu launchers
# (.desktop) and infers the owning package of each one (pm_owner). Since
# the starting universe is wider and less controlled than the curated
# catalog, it filters by blacklist and ALWAYS shows the real simulation of the
# package manager (pm_simulate) with the full plan first, including any
# dependent it decides to remove.
# ----------------------------------------------------------------------------

# Succeeds (true) if the package must be excluded from advanced mode, either
# because it matches a blacklist pattern or because the manager protects it
# (pm_protected: the system components). Only a clear "no" (status 1) lets a
# package through: a manager that cannot say (status 2) protects it.
is_excluded_package() {
    local pkg="$1"
    local pattern status=0

    # The guarded expansion: bash 4.3 treats an empty array as unset under set -u.
    for pattern in "${EXCLUDED_PATTERNS[@]+"${EXCLUDED_PATTERNS[@]}"}"; do
        # shellcheck disable=SC2053
        if [[ "$pkg" == $pattern ]]; then
            return 0
        fi
    done

    pm_protected "$pkg" || status=$?
    [ "$status" -eq 1 ] || return 0

    return 1
}

# Succeeds (true) if the package is already covered by the curated CATALOG,
# so it is not offered twice (once by Option 2 and once by Option 3).
is_catalog_package() {
    local pkg="$1"
    local entry pkgs p

    for entry in "${CATALOG[@]+"${CATALOG[@]}"}"; do
        IFS='|' read -r _ pkgs _ <<< "$entry"
        for p in ${pkgs//,/ }; do
            if [ "$p" = "$pkg" ]; then
                return 0
            fi
        done
    done
    return 1
}

desktop_name() {
    local f="$1" locale base lang country modifier name key
    local -a keys=()
    locale="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"

    if [ "$APP_LANG" = "es" ]; then
        lang="es"
    else
        lang="en"
    fi

    modifier=""
    [[ "$locale" == *@* ]] && modifier="${locale##*@}"
    base="${locale%%@*}"
    base="${base%%.*}"
    country=""
    [[ "$base" == *_* ]] && country="${base#*_}"

    if [[ "${base%%_*}" == "$lang" ]]; then
        if [ -n "$country" ] && [ -n "$modifier" ]; then
            keys+=("${lang}_${country}@${modifier}")
        fi
        [ -n "$country" ] && keys+=("${lang}_${country}")
        [ -n "$modifier" ] && keys+=("${lang}@${modifier}")
    fi
    keys+=("$lang")

    for key in "${keys[@]}"; do
        name=$(grep -m1 "^Name\[$key\]=" "$f" 2>/dev/null | cut -d= -f2-)
        [ -n "${name:-}" ] && { printf '%s' "$name"; return; }
    done

    grep -m1 '^Name=' "$f" 2>/dev/null | cut -d= -f2-
}

# First, cheap pass over a launcher: only Type=Application entries that are
# not NoDisplay/Hidden are worth asking pm_owner about. Succeeds for a candidate.
launcher_is_candidate() {
    local f="$1" value
    value=$(grep -m1 '^Type=' "$f" 2>/dev/null | cut -d= -f2-)
    [ "$value" = "Application" ] || return 1
    value=$(grep -m1 '^NoDisplay=' "$f" 2>/dev/null | cut -d= -f2-)
    [ "$value" = "true" ] && return 1
    value=$(grep -m1 '^Hidden=' "$f" 2>/dev/null | cut -d= -f2-)
    [ "$value" = "true" ] && return 1
    return 0
}

# Asks who owns each launcher with ONE pm_owner call per chunk of 200 paths
# instead of one per file: dpkg rescans its whole file database on every call,
# so 150 launchers take tens of seconds one by one and well under a second
# together. Fills LAUNCHER_OWNERS[path] with the owner(s) pm_owner printed ("pkg",
# "pkg-a, pkg-b" or "diversion by X from"); a launcher nobody owns has no entry.
# $@ = launcher paths.
load_launcher_owners() {
    LAUNCHER_OWNERS=()
    local -a chunk=()
    local line owner path count
    while [ "$#" -gt 0 ]; do
        count=$(( $# < 200 ? $# : 200 ))
        chunk=("${@:1:count}")
        shift "$count"
        while IFS= read -r line; do
            [[ "$line" == *": /"* ]] || continue
            owner="${line%%: /*}"
            path="/${line#*: /}"
            LAUNCHER_OWNERS["$path"]+="${LAUNCHER_OWNERS[$path]:+$'\n'}$owner"
        done < <(pm_owner "${chunk[@]}")
    done
}

# Where a launcher no package owns comes from: flatpak, snap or manual (an
# AppImage, a downloaded installer, a hand-made launcher). The folder of the
# launcher decides first; failing that, how its Exec line starts the program.
launcher_origin() {
    local f="$1" exec_line
    case "$f" in
        */flatpak/exports/*) printf flatpak; return ;;
        /var/lib/snapd/*|*/snapd/desktop/*) printf snap; return ;;
    esac
    exec_line="$(grep -m1 '^Exec=' "$f" 2>/dev/null | cut -d= -f2-)"
    case "$exec_line" in
        *"flatpak run"*) printf flatpak ;;
        */snap/bin/*|*"snap run"*) printf snap ;;
        *) printf manual ;;
    esac
}

# Label of an origin for the interface: the package manager (apt, dnf...),
# Flatpak, Snap (proper names, the same in every language) or "manual install"
# (translated).
origin_label() {
    case "$1" in
        flatpak) printf 'Flatpak' ;;
        snap) printf 'Snap' ;;
        apt|dnf|pacman|zypper) printf '%s' "$1" ;;
        *) msg origin_manual ;;
    esac
}

# Which Flatpak or Snap a launcher belongs to, as a plan line (see
# parse_store_line): "flatpak user ID", "flatpak system ID" or "snap system
# NAME". Only a launcher in the folder where its store exports them counts, and
# the identifier comes from the NAME OF THE FILE, never from what the file says
# (anyone can edit a launcher), and must pass the strict patterns. Fails, with no
# output, for anything else: that launcher stays in the unmanaged list.
launcher_store_line() {
    local f="$1" base scope
    base="${f##*/}"
    base="${base%.desktop}"
    case "$f" in
        */flatpak/exports/share/applications/*.desktop)
            if [ -n "${HOME:-}" ] && [[ "$f" == "$HOME"/* ]]; then scope=user; else scope=system; fi
            is_flatpak_id "$base" || return 1
            printf 'flatpak %s %s' "$scope" "$base" ;;
        */snapd/desktop/applications/*.desktop)
            # snapd names its launchers SNAP_APP.desktop
            [[ "$base" == *_* ]] || return 1
            is_snap_name "${base%%_*}" || return 1
            printf 'snap system %s' "${base%%_*}" ;;
        *) return 1 ;;
    esac
}

# Adds a Flatpak or Snap to the entries offered for removal: its name, the tail
# the lists show ("Flatpak: ID") and its plan line. A second launcher of the same
# application adds nothing. Fails if the plan line is not valid.
add_store_entry() {
    local name="$1" line="$2" key
    parse_store_line "$line" || return 1
    key="store $STORE_KIND $STORE_SCOPE $STORE_ID"
    if [ -z "${SEEN_PKGS[$key]:-}" ]; then
        SEEN_PKGS[$key]=1
        ADV_NAMES+=("$name")
        ADV_PACKAGES+=("${STORE_KIND^}: $STORE_ID")
        ADV_LINES+=("$line")
    fi
}

# The launchers that no package owns, one per line as "  - Name [origin]\n"
# (with a literal \n, like every dialog text of the program).
unmanaged_lines() {
    local i text=""
    for i in "${!ADV_UNMANAGED_NAMES[@]}"; do
        text+="  - ${ADV_UNMANAGED_NAMES[$i]} [$(origin_label "${ADV_UNMANAGED_ORIGINS[$i]:-manual}")]\n"
    done
    printf '%s' "$text"
}

# Classifies one launcher that passed launcher_is_candidate, using the owners
# loaded by load_launcher_owners, and adds it to the ADV_* arrays. If it has no
# owning package (Flatpak, Snap or manual install) or the owner is ambiguous,
# it is recorded as "unmanaged" instead of being offered for purging.
process_desktop_file() {
    local f="$1"
    local name owner_output owner_line pkg store_line

    name="$(sanitize_display "$(desktop_name "$f")")"
    [ -n "$name" ] || name="$(sanitize_display "$(basename "$f" .desktop)")"

    owner_output="${LAUNCHER_OWNERS[$f]:-}"
    if [ -z "$owner_output" ]; then
        # A Flatpak or a Snap that can be identified is offered for removal with
        # the command of its store; anything else stays in the unmanaged list.
        if store_line="$(launcher_store_line "$f")" && add_store_entry "$name" "$store_line"; then
            return
        fi
        ADV_UNMANAGED_NAMES+=("$name")
        ADV_UNMANAGED_ORIGINS+=("$(launcher_origin "$f")")
        return
    fi
    # A diverted file has no single clear owner.
    if grep -q '^diversion by ' <<< "$owner_output"; then
        ADV_UNMANAGED_NAMES+=("$name ($(msg ambiguous_package))")
        ADV_UNMANAGED_ORIGINS+=("$PM")
        return
    fi
    owner_line=$(head -n1 <<< "$owner_output")

    pkg="${owner_line%%:*}"
    read -r pkg <<< "$pkg"
    # Several packages claim the same file ("a, b") or the owner is not a valid
    # package name: ambiguous, so it is never offered for removal. This also
    # guarantees that what reaches the manager cannot look like an option.
    if ! pm_valid_name "$pkg"; then
        ADV_UNMANAGED_NAMES+=("$name ($(msg ambiguous_package))")
        ADV_UNMANAGED_ORIGINS+=("$PM")
        return
    fi

    [ -n "${SEEN_PKGS[$pkg]:-}" ] && return
    is_excluded_package "$pkg" && return
    is_catalog_package "$pkg" && return

    SEEN_PKGS[$pkg]=1
    ADV_NAMES+=("$name")
    ADV_PACKAGES+=("$pkg")
    ADV_LINES+=("")
}

# Sorts the ADV_* arrays alphabetically (by visible name) after the scan,
# so the list is easier to review.
# The field separator is \x1f (unit separator), not \x01: bash 4.3 doubles a
# \x01 byte inside $'...' (sort then fails with "multi-character tab"). Names
# cannot contain control characters (sanitize_display removes them).
sort_advanced_arrays() {
    [ "${#ADV_NAMES[@]}" -eq 0 ] && return

    local i combined
    combined=""
    for i in "${!ADV_NAMES[@]}"; do
        combined+="${ADV_NAMES[$i]}"$'\x1f'"${ADV_PACKAGES[$i]}"$'\x1f'"${ADV_LINES[$i]:-}"$'\n'
    done

    ADV_NAMES=()
    ADV_PACKAGES=()
    ADV_LINES=()

    local name pkg line
    while IFS=$'\x1f' read -r name pkg line; do
        [ -z "$name" ] && continue
        ADV_NAMES+=("$name")
        ADV_PACKAGES+=("$pkg")
        ADV_LINES+=("$line")
    done < <(printf '%s' "$combined" | sort -f -t $'\x1f' -k1,1)
}

# Walks the standard launcher directories and fills the ADV_NAMES /
# ADV_PACKAGES / ADV_LINES / ADV_UNMANAGED_NAMES arrays.
scan_launchers() {
    ADV_NAMES=()
    ADV_PACKAGES=()
    ADV_LINES=()
    ADV_UNMANAGED_NAMES=()
    ADV_UNMANAGED_ORIGINS=()
    ADV_HAY=()
    SEEN_PKGS=()

    local -a dirs=()
    if [ -n "${MINTAPP_LAUNCHER_DIRS:-}" ]; then
        # Advanced configuration: scan only these folders (colon-separated).
        IFS=: read -r -a dirs <<< "$MINTAPP_LAUNCHER_DIRS"
    else
        dirs=(
            "/usr/share/applications"
            "/usr/local/share/applications"
            "/var/lib/snapd/desktop/applications"
            "/var/lib/flatpak/exports/share/applications"
            "$HOME/.local/share/applications"
            "$HOME/.local/share/flatpak/exports/share/applications"
        )
    fi
    local dir f
    local -a candidates=()

    # Pass 1: cheap filters. Pass 2: one pm_owner query for everything that is
    # left. Pass 3: classification.
    for dir in "${dirs[@]+"${dirs[@]}"}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' f; do
            launcher_is_candidate "$f" && candidates+=("$f")
        done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
    done
    [ "${#candidates[@]}" -gt 0 ] && load_launcher_owners "${candidates[@]}"
    for f in "${candidates[@]+"${candidates[@]}"}"; do
        process_desktop_file "$f"
    done

    sort_advanced_arrays

    # What a search looks into: the name and the package of each entry.
    ADV_HAY=()
    local i
    for i in "${!ADV_NAMES[@]}"; do
        fold_search "${ADV_NAMES[$i]} ${ADV_PACKAGES[$i]}"
        ADV_HAY+=("$REPLY")
    done
}

# Shared by Options 2 and 3: simulates the purge of the given packages with
# the package manager (including any dependent it decides to remove), shows the plan,
# asks for confirmation, re-checks that the plan has not changed and only then
# runs the real purge. Takes the names of two arrays (by reference):
# $1 = visible names, $2 = packages to purge.
confirm_and_purge() {
    local -n _names="$1"
    local -n _pkgs="$2"

    # Nothing to remove (for example a dialog that returned only unknown tags):
    # The package manager is never called without packages.
    if [ "${#_pkgs[@]}" -eq 0 ]; then
        show_message "$(msg none_selected)"
        return
    fi

    header
    text_wrap "$(msg plan_calculating)"
    echo
    plan_password_hint
    plan_authorize || return

    pm_simulate purge "${_pkgs[@]}"
    local sim_status=$?
    local plan="$PLAN_OUTPUT"

    if [ "$sim_status" -ne 0 ]; then
        show_plan_error "$plan"
        return
    fi

    local summary
    summary="$(msg will_remove)\n\n"
    local name
    for name in "${_names[@]}"; do
        summary+="  ${SYM_OK} $name\n"
    done

    review_plan "$(msg plan_real)" "$plan" "$summary" "${_pkgs[@]}" || return

    if ! plan_still_valid "$plan" purge "${_pkgs[@]}"; then
        show_message "$(msg plan_changed)"
        return
    fi

    run_purge "$plan" "${_pkgs[@]}"
}

# Adds to the plan line of a Flatpak the remote it came from (the reinstall hint
# of the record uses it). It is asked of flatpak only for what the user chose, and
# what comes back is kept only if it is a valid remote name.
store_line_with_remote() {
    local line="$1" remote=""
    if parse_store_line "$line" && [ "$STORE_KIND" = flatpak ] && [ -z "$STORE_REMOTE" ]; then
        read -r remote < <(flatpak info "--$STORE_SCOPE" --show-origin "$STORE_ID" 2>/dev/null </dev/null) || true
        is_flatpak_remote "$remote" && line+=" $remote"
    fi
    printf '%s' "$line"
}

# Option 3, after the choice. $1 = the marks (0/1, one per entry), by name. The
# marked packages go through confirm_and_purge; the Flatpaks and Snaps go
# through confirm_and_remove_stores: each flow has its own plan and its own
# confirmation. Fails, doing nothing, if nothing is marked.
remove_advanced_selection() {
    local -n _marks="$1"
    local -a names=() pkgs=()
    local request="" i
    for i in "${!ADV_NAMES[@]}"; do
        [ "${_marks[$i]}" -eq 1 ] || continue
        if [ -n "${ADV_LINES[$i]:-}" ]; then
            request+="${request:+$'\n'}$(store_line_with_remote "${ADV_LINES[$i]}")"
        else
            names+=("${ADV_NAMES[$i]}")
            pkgs+=("${ADV_PACKAGES[$i]}")
        fi
    done
    [ "${#pkgs[@]}" -gt 0 ] || [ -n "$request" ] || return 1
    if [ "${#pkgs[@]}" -gt 0 ]; then confirm_and_purge names pkgs; fi
    if [ -n "$request" ]; then confirm_and_remove_stores "$request"; fi
    return 0
}

# Option 3 — selection with whiptail (checkboxes)
find_other_apps_whiptail() {
    local -a labels=() tails=() selected=()
    local i
    for i in "${!ADV_NAMES[@]}"; do
        labels+=("${ADV_NAMES[$i]}  [${ADV_PACKAGES[$i]}]")
        tails+=("[${ADV_PACKAGES[$i]}]")
        selected+=(0)
    done

    local prompt
    if [ "$UI_ENGINE" = "gui" ]; then prompt="$(msg advanced_select_gui)"; else prompt="$(msg advanced_select)"; fi
    wt_checklist_search "$prompt" labels ADV_HAY selected tails || return

    remove_advanced_selection selected || wt_msgbox "$(msg none_selected)"
}

# Option 3 — selection in plain text (fallback without whiptail)
find_other_apps_text() {
    local -a labels=() no_descs=() selected=()
    local i
    for i in "${!ADV_NAMES[@]}"; do
        labels+=("[${ADV_PACKAGES[$i]}]")
        no_descs+=("")
        selected+=(0)
    done

    text_checklist_search advanced ADV_NAMES labels no_descs ADV_HAY selected || return

    if ! remove_advanced_selection selected; then
        header
        text_wrap "$(msg none_selected)"
        pause
    fi
}

# Option 3 — dispatcher: scans, warns about advanced mode and delegates
# according to the available interface.
find_other_apps() {
    local unmanaged
    header
    text_wrap "$(msg scanning)"
    scan_launchers

    if [ "${#ADV_NAMES[@]}" -eq 0 ]; then
        local msg_text
        msg_text="$(msg no_extra)"
        if [ "${#ADV_UNMANAGED_NAMES[@]}" -gt 0 ]; then
            unmanaged="$(count_unmanaged "${#ADV_UNMANAGED_NAMES[@]}")"
            # $(...) drops the newline the message ends with: put it back.
            msg_text+="$unmanaged\n$(unmanaged_lines)"
        fi

        if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
            wt_msgbox "$msg_text" big
        else
            header
            text_print "$msg_text"
            pause
        fi
        return
    fi

    local warning_text
    if [ "${#ADV_NAMES[@]}" -eq 1 ]; then
        msgf_v warning_text advanced_warning_1 "${#ADV_NAMES[@]}"
    else
        msgf_v warning_text advanced_warning_n "${#ADV_NAMES[@]}"
    fi
    if [ "${#ADV_UNMANAGED_NAMES[@]}" -gt 0 ]; then
        unmanaged="$(count_unmanaged "${#ADV_UNMANAGED_NAMES[@]}")"
        warning_text+="$unmanaged\n$(unmanaged_lines)"
    fi

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_msgbox "$warning_text" big
        find_other_apps_whiptail
    else
        header
        text_print "$warning_text"
        pause
        find_other_apps_text
    fi
}

# ----------------------------------------------------------------------------
# System cleaning (FP.4): a catalog of kinds of waste and the engine that lists
# and removes files. Adapted from BleachBit (GPL-3.0-or-later): each entry
# names the BleachBit cleaners it follows; an entry BleachBit lacks says "-".
# Two levels. Simple: low risk, only what applications rebuild, with age limits.
# Complete: BleachBit without its warnings, no age limits. Nothing runs without
# a listing, a summary and a confirmation, and files are only touched inside the
# places clean_path_ok allows. The limits (days) are the four constants below.
# ----------------------------------------------------------------------------
CLEAN_DAYS_JOURNAL=14   # simple level: the journal keeps this many days
CLEAN_DAYS_LOGS=7       # simple level: rotated logs older than this go
CLEAN_DAYS_CACHE=30     # simple level: caches not used for this long go
CLEAN_DAYS_TMP=7        # simple level: files of /tmp older than this go

# "id|category|levels|administrator|BleachBit cleaners". Levels: SC = simple
# and complete, C = complete only. Administrator: 1 = needs sudo or doas.
CLEAN_CATALOG=(
    "recent|privacy|SC|0|system.recent_documents kde.recent_documents"
    "clipboard|privacy|SC|0|system.clipboard"
    "trash|privacy|C|0|system.trash"
    "thumbnails|cache|SC|0|thumbnails.cache"
    "browsers|cache|SC|0|firefox.cache chromium.cache google_chrome.cache brave.cache opera.cache thunderbird.cache"
    "cache|cache|SC|0|system.cache"
    "app_caches|cache|SC|0|-"
    "tmp|cache|SC|0|system.tmp"
    "rotated_logs|logs|SC|1|system.rotated_logs"
    "journal|logs|SC|1|journald.clean"
    "x11_logs|logs|C|0|x11.debug_logs"
    "crash|logs|C|1|-"
    "apt_cache|packages|SC|1|apt.clean"
    "rc_config|packages|C|1|-"
)
readonly CLEAN_CATALOG

# The categories of the catalog, in the order the lists show them.
CLEAN_CATEGORIES=(privacy cache logs packages)
readonly CLEAN_CATEGORIES

# The only places outside the home folder the cleaning may work in. A path must
# be one of them exactly (never something inside them) to be a root of its own.
CLEAN_SYSTEM_ROOTS=(/tmp /var/tmp /var/log /var/crash /var/lib/systemd/coredump /var/cache/apt)
readonly CLEAN_SYSTEM_ROOTS

CLEAN_LIST=()            # clean_ids: the entries of a level, in catalog order
CLEAN_FILES=0            # clean_apply: files and links removed
CLEAN_BYTES=0            # ... their size in bytes
CLEAN_SKIPPED=0          # ... records and files left alone, and why they were
CLEAN_FAILED=0           # ... files that could not be removed
CLEAN_BATCH=()           # clean_apply: the paths waiting for the next rm
CLEAN_BATCH_SIZES=()
CLEAN_DRY=0              # 1: clean_apply counts what it would remove and removes nothing
CLEAN_ROOT=0             # 1: clean_apply removes with administrator rights (priv_run rm)
CLEAN_DEPTH=0            # clean_scan: how many levels below the folder it looks (0 = all)

# Puts in CLEAN_LIST the entries of the level $1 (S simple, C complete).
clean_ids() {
    local line id levels
    CLEAN_LIST=()
    for line in "${CLEAN_CATALOG[@]}"; do
        IFS='|' read -r id _ levels _ <<< "$line"
        if [ "$1" = C ] || [[ "$levels" == *S* ]]; then CLEAN_LIST+=("$id"); fi
    done
}

# Puts in REPLY the field $2 (1 = id, 2 = category, 3 = levels, 4 =
# administrator, 5 = BleachBit) of the entry $1. Fails if there is no such entry.
clean_field() {
    local line f
    for line in "${CLEAN_CATALOG[@]}"; do
        [ "${line%%|*}" = "$1" ] || continue
        IFS='|' read -r -a f <<< "$line"
        REPLY="${f[$(( $2 - 1 ))]-}"
        return 0
    done
    REPLY=""
    return 1
}

# Puts in REPLY the age limit in days of the entry $1 at the level $2: only
# the simple level has limits; 0 means no limit.
clean_days() {
    REPLY=0
    [ "$2" = S ] || return 0
    case "$1" in
        cache|app_caches) REPLY="$CLEAN_DAYS_CACHE" ;;
        tmp) REPLY="$CLEAN_DAYS_TMP" ;;
        rotated_logs) REPLY="$CLEAN_DAYS_LOGS" ;;
        journal) REPLY="$CLEAN_DAYS_JOURNAL" ;;
    esac
}

# Name and description of an entry, and name of a category, in the language in use.
clean_name() { msg "clean_item_$1"; }
clean_desc() { msg "clean_item_$1_desc"; }
clean_cat_name() { msg "clean_cat_$1"; }

# Succeeds if $1 is a folder the cleaning may work in: one of
# CLEAN_SYSTEM_ROOTS exactly, or a folder inside the home folder (never the home
# folder itself). The path is absolute, with no trailing slash, no empty, "." or
# ".." component and no control character. HOME must be a real folder (two
# components or more, such as /home/user): a short or odd HOME is not trusted.
clean_path_ok() {
    local p="${1-}" home="${HOME-}" root
    [[ "$p" == /* ]] || return 1
    [[ "$p" != *[[:cntrl:]]* ]] || return 1
    [[ "$p" != */ && "$p" != *//* ]] || return 1
    [[ "$p/" != *"/./"* && "$p/" != *"/../"* ]] || return 1
    for root in "${CLEAN_SYSTEM_ROOTS[@]}"; do
        [ "$p" != "$root" ] || return 0
    done
    [[ "$home" =~ ^/[^/]+(/[^/]+)+$ ]] || return 1
    [[ "$home" != *[[:cntrl:]]* && "$home/" != *"/./"* && "$home/" != *"/../"* ]] || return 1
    [[ "$p" == "$home"/?* ]]
}

# Lists what can be removed under the folder $1, as records "SIZE PATH" ended
# with a NUL, for clean_apply. $2 = age limit in days (0 = none): only what
# changed and was last used before that. $3 = 1: only files of this user. More
# arguments are extra tests for find (such as -name). Only files and links:
# never folders, nothing behind a link, nothing on another filesystem, and not
# the folder itself. CLEAN_DEPTH (1 to 999) limits how many levels it looks below
# the folder. Status 1, listing nothing, if the folder is not allowed, is not a
# folder, is a link, or the limit or $3 is not valid.
clean_scan() {
    local root="${1-}" days="${2-}" own="${3-}"
    shift $(( $# < 3 ? $# : 3 ))
    local -a age=() mine=() depth=()
    clean_path_ok "$root" && [ -d "$root" ] && [ ! -L "$root" ] || return 1
    [[ "$days" =~ ^[0-9]{1,5}$ ]] || return 1
    days=$(( 10#$days ))
    case "$own" in
        0) ;;
        1) mine=(-uid "$(id -u)") ;;
        *) return 1 ;;
    esac
    [ "$days" -eq 0 ] || age=(-mtime "+$days" -atime "+$days")
    [[ "${CLEAN_DEPTH:-0}" =~ ^[1-9][0-9]{0,2}$ ]] && depth=(-maxdepth "$CLEAN_DEPTH")
    find "$root" -xdev "${depth[@]+"${depth[@]}"}" -mindepth 1 \( -type f -o -type l \) \
        "${age[@]+"${age[@]}"}" "${mine[@]+"${mine[@]}"}" "$@" -printf '%s %p\0' 2>/dev/null
    return 0
}

# Writes in the file $1, one per line, every path some process has open or
# mapped (/proc/*/fd and /proc/*/maps): what is in use is never removed. Sockets,
# pipes and the like are not paths and are left out.
clean_open_files() {
    {
        find /proc/[0-9]*/fd -maxdepth 1 -type l -printf '%l\n' 2>/dev/null
        cat /proc/[0-9]*/maps 2>/dev/null |
            awk '{ sub(/^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +/, ""); if (substr($0, 1, 1) == "/") print }'
    } | grep '^/' | sed 's/ (deleted)$//' | sort -u > "$1" || true
}

# Succeeds if the file $1 belongs to this program: its work folder, the lock that
# keeps a second copy out and the list of what is open (CLEAN_OPENFILE). Those are
# never removed.
clean_own_file() {
    [ "${1##*/}" != "mintapp-remover.lock" ] || return 0
    [ -z "${CLEAN_OPENFILE:-}" ] || [ "$1" != "$CLEAN_OPENFILE" ] || return 0
    [ -n "${GUI_WORK_DIR:-}" ] && [[ "$1" == "$GUI_WORK_DIR"/* ]]
}

# Removes the files waiting in CLEAN_BATCH and counts how each went: gone =
# removed, still there = failed. The rest of the batch goes on if one fails.
# With CLEAN_DRY=1 it removes nothing and counts them all as removed; with
# CLEAN_ROOT=1 it removes with administrator rights (the paths were checked by
# clean_apply: files and links inside an allowed root).
clean_flush() {
    local i p
    [ "${#CLEAN_BATCH[@]}" -gt 0 ] || return 0
    if [ "$CLEAN_DRY" -eq 1 ]; then
        for i in "${!CLEAN_BATCH[@]}"; do
            CLEAN_FILES=$(( CLEAN_FILES + 1 ))
            CLEAN_BYTES=$(( CLEAN_BYTES + CLEAN_BATCH_SIZES[i] ))
        done
        CLEAN_BATCH=() CLEAN_BATCH_SIZES=()
        return 0
    fi
    if [ "$CLEAN_ROOT" -eq 1 ]; then
        priv_run rm -f -- "${CLEAN_BATCH[@]}" >/dev/null 2>&1 || true
    else
        rm -f -- "${CLEAN_BATCH[@]}" >/dev/null 2>&1 || true
    fi
    for i in "${!CLEAN_BATCH[@]}"; do
        p="${CLEAN_BATCH[$i]}"
        if [ -e "$p" ] || [ -L "$p" ]; then
            CLEAN_FAILED=$(( CLEAN_FAILED + 1 ))
        else
            CLEAN_FILES=$(( CLEAN_FILES + 1 ))
            CLEAN_BYTES=$(( CLEAN_BYTES + CLEAN_BATCH_SIZES[i] ))
        fi
    done
    CLEAN_BATCH=() CLEAN_BATCH_SIZES=()
}

# Removes what clean_scan listed, read from stdin, inside the folder $1, in
# groups of 200. $2 = file with the paths in use (clean_open_files). $3 = age limit,
# $4 = 1 for files of this user only, $5 = 0 to leave empty folders alone: the
# folders that stay empty go afterwards, with the same limit (the folder $1
# stays). Every record is checked again, and skipped (and counted) if it is
# badly made, outside the folder, has a "." or ".." component, is a folder, no
# longer exists, is in use or belongs to this program. Sets CLEAN_FILES,
# CLEAN_BYTES, CLEAN_SKIPPED and CLEAN_FAILED. Status 1, removing nothing, if the
# folder is not allowed, is not a folder or is a link.
clean_apply() {
    local root="${1-}" openfile="${2-}" days="${3:-0}" own="${4:-0}" prune="${5:-1}" rec size path line
    local -A open=()
    local -a mine=() old=()
    CLEAN_FILES=0 CLEAN_BYTES=0 CLEAN_SKIPPED=0 CLEAN_FAILED=0
    CLEAN_BATCH=() CLEAN_BATCH_SIZES=()
    clean_path_ok "$root" && [ -d "$root" ] && [ ! -L "$root" ] || return 1
    [[ "$days" =~ ^[0-9]{1,5}$ ]] || return 1
    days=$(( 10#$days ))
    if [ -r "$openfile" ] && [ -f "$openfile" ]; then
        while IFS= read -r line; do [ -z "$line" ] || open["$line"]=1; done < "$openfile"
    fi
    while IFS= read -r -d '' rec; do
        size="${rec%% *}" path="${rec#* }"
        if [[ "$rec" != *" "* ]] || ! [[ "$size" =~ ^[0-9]{1,15}$ ]] \
            || [[ "$path" != "$root"/?* || "$path" == *//* || "$path/" == *"/./"* || "$path/" == *"/../"* ]] \
            || { [ -d "$path" ] && [ ! -L "$path" ]; } \
            || { [ ! -e "$path" ] && [ ! -L "$path" ]; } \
            || [ -n "${open[$path]+x}" ] || clean_own_file "$path"; then
            CLEAN_SKIPPED=$(( CLEAN_SKIPPED + 1 ))
            continue
        fi
        CLEAN_BATCH+=("$path") CLEAN_BATCH_SIZES+=("$(( 10#$size ))")
        [ "${#CLEAN_BATCH[@]}" -lt 200 ] || clean_flush
    done
    clean_flush
    if [ "$prune" -eq 1 ] && [ "$CLEAN_DRY" -eq 0 ]; then
        [ "$own" -ne 1 ] || mine=(-uid "$(id -u)")
        [ "$days" -eq 0 ] || old=(-mtime "+$days")
        find "$root" -xdev -mindepth 1 -type d -empty "${old[@]+"${old[@]}"}" "${mine[@]+"${mine[@]}"}" -delete >/dev/null 2>&1 || true
    fi
    return 0
}

# ----------------------------------------------------------------------------
# What each entry of the catalog works on (FP.4, step P.4b): the entries that
# take the files of the user. clean_places says where an entry works, and
# clean_item measures it (nothing is removed) or runs it, with the engine above.
# ----------------------------------------------------------------------------
CLEAN_PLACES=()           # clean_places: "ROOT US OWN US PRUNE US DEPTH US tests of find...", US = $'\037'
CLEAN_OPENFILE=""         # the paths in use (clean_open_files), made by whoever starts a cleaning
CLEAN_ITEM_FILES=0        # clean_item: files and links it removes (or would remove) ...
CLEAN_ITEM_BYTES=0        # ... their size in bytes
CLEAN_ITEM_SKIPPED=0      # ... what the engine left alone (in use, odd records)
CLEAN_ITEM_FAILED=0       # ... what could not be removed
CLEAN_ITEM_NOTE=""        # what it left out or used: browsers that are open, the tools of the clipboard
CLEAN_ITEM_WHERE=""       # where it works, one place per line, for the summary
CLEAN_ITEM_STATE=ok       # ok, or unavailable if it cannot work here (no tool for the clipboard)

# "name|process names|cache folders": a folder is relative to the cache folder,
# or to the home folder if it starts with "home:". The cache of a browser is
# only cleaned while it is closed.
CLEAN_BROWSERS=(
    "Firefox|firefox firefox-bin firefox-esr|mozilla/firefox home:snap/firefox/common/.cache/mozilla/firefox"
    "Chromium|chromium chromium-browse chromium-browser|chromium home:snap/chromium/common/.cache/chromium"
    "Chrome|chrome google-chrome|google-chrome google-chrome-beta google-chrome-unstable"
    "Brave|brave brave-browser|BraveSoftware/Brave-Browser"
    "Opera|opera|opera"
    "LibreWolf|librewolf|librewolf"
    "Thunderbird|thunderbird thunderbird-bin|thunderbird home:snap/thunderbird/common/.cache/thunderbird"
)
readonly CLEAN_BROWSERS

# The temporary folders (they have to be in CLEAN_SYSTEM_ROOTS too).
CLEAN_TMP_DIRS=(/tmp /var/tmp)

# The folders of the entries that need administrator rights (in CLEAN_SYSTEM_ROOTS too).
CLEAN_LOG_DIR=/var/log
CLEAN_CRASH_DIRS=(/var/crash /var/lib/systemd/coredump)
CLEAN_APT_DIR=/var/cache/apt

# $1 with the characters find takes as a pattern (* ? [ ] \) escaped.
clean_glob() {
    local s="$1" out="" c i
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            \\|\*|\?|\[|\]) out+="\\$c" ;;
            *) out+="$c" ;;
        esac
    done
    printf '%s' "$out"
}

# Adds to CLEAN_PLACES the place ROOT ($1) with OWN ($2: 1 = only the files of
# this user), PRUNE ($3: 1 = then remove the folders that stay empty) and DEPTH
# ($4: how deep to look, 0 = no limit), and the tests of find that follow. A root
# that is not allowed (clean_path_ok), does not exist or is a link is left out:
# an entry may work in places that this system does not have.
clean_place() {
    local IFS=$'\037'
    clean_path_ok "$1" && [ -d "$1" ] && [ ! -L "$1" ] || return 0
    CLEAN_PLACES+=("$*")
}

# Succeeds if a process runs under one of the names given (its name in
# /proc/PID/comm, which the kernel cuts at 15 characters).
clean_running() {
    local f name n
    for f in /proc/[0-9]*/comm; do
        read -r name 2>/dev/null < "$f" || continue
        for n in "$@"; do
            [ "$name" != "$n" ] || return 0
        done
    done
    return 1
}

# Puts in CLEAN_PLACES where the entry $1 works at the level $2, and in
# CLEAN_ITEM_NOTE the browsers it leaves out because they are open. Status 1 for
# an entry that does not work on files (clipboard, x11_logs) or that this step
# does not have yet.
clean_places() {
    local id="$1" level="$2" home="${HOME-}" cache="${XDG_CACHE_HOME:-${HOME-}/.cache}"
    local days prune g d r entry name procs roots
    local -a ex=() pa=() ra=()
    CLEAN_PLACES=()
    CLEAN_ITEM_NOTE=""
    clean_days "$id" "$level"
    days="$REPLY"
    case "$id" in
        recent)
            clean_place "$home/.local/share" 1 0 1 -name 'recently-used.xbel*'
            clean_place "$home/.local/share/RecentDocuments" 1 0 0 -name '*.desktop' ;;
        trash)
            clean_place "$home/.local/share/Trash/files" 0 1 0
            clean_place "$home/.local/share/Trash/info" 0 0 0 -name '*.trashinfo'
            clean_place "$home/.local/share/Trash/expunged" 0 1 0
            clean_place "$home/.local/share/Trash" 0 0 1 -name directorysizes ;;
        thumbnails)
            clean_place "$cache/thumbnails" 1 1 0
            clean_place "$home/.thumbnails" 1 1 0 ;;
        browsers)
            for entry in "${CLEAN_BROWSERS[@]}"; do
                IFS='|' read -r name procs roots <<< "$entry"
                read -r -a pa <<< "$procs"
                if clean_running "${pa[@]+"${pa[@]}"}"; then
                    CLEAN_ITEM_NOTE+="${CLEAN_ITEM_NOTE:+, }$name"
                    continue
                fi
                read -r -a ra <<< "$roots"
                for r in "${ra[@]+"${ra[@]}"}"; do
                    case "$r" in
                        home:*) d="$home/${r#home:}" ;;
                        *) d="$cache/$r" ;;
                    esac
                    clean_place "$d" 1 1 0
                done
            done ;;
        cache)
            # The rest of the cache: what the entries of the thumbnails and of the browsers
            # (which have to be closed) take care of stays out.
            g=$(clean_glob "$cache")
            ex=(-not -path "$g/thumbnails/*")
            for entry in "${CLEAN_BROWSERS[@]}"; do
                IFS='|' read -r _ _ roots <<< "$entry"
                read -r -a ra <<< "$roots"
                for r in "${ra[@]+"${ra[@]}"}"; do
                    [[ "$r" == home:* ]] || ex+=(-not -path "$g/$r/*")
                done
            done
            clean_place "$cache" 1 1 0 "${ex[@]}" ;;
        app_caches)
            for d in "$home"/.var/app/*/cache "$home"/snap/*/common/.cache; do
                clean_place "$d" 1 1 0
            done ;;
        tmp)
            # Empty folders go only with an age limit: a program may have just made one.
            prune=0
            [ "$days" -eq 0 ] || prune=1
            for d in "${CLEAN_TMP_DIRS[@]}"; do
                g=$(clean_glob "$d")
                # What belongs to the session (sockets, locks, the folders of the desktop) is left alone.
                ex=(-not -path "$g/.X11-unix/*" -not -path "$g/.ICE-unix/*" -not -path "$g/.XIM-unix/*"
                    -not -path "$g/.font-unix/*" -not -path "$g/.Test-unix/*" -not -path "$g/ssh-*"
                    -not -path "$g/pulse-*" -not -path "$g/dbus-*" -not -path "$g/runtime-*"
                    -not -path "$g/.mount_*" -not -path "$g/snap-private-tmp/*" -not -path "$g/systemd-private-*"
                    -not -name '.X*-lock' -not -name '*.lock' -not -name '*.pid' -not -name '*.sock')
                clean_place "$d" 1 "$prune" 0 "${ex[@]}"
            done ;;
        rotated_logs)
            g=$(clean_glob "$CLEAN_LOG_DIR")
            clean_place "$CLEAN_LOG_DIR" 0 0 0 -not -path "$g/journal/*" \
                '(' -name '*.[0-9]' -o -name '*.[0-9][0-9]' -o -name '*.gz' -o -name '*.xz' -o -name '*.bz2' \
                -o -name '*.zst' -o -name '*.old' -o -name '*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' ')' ;;
        journal)
            # Only the archived files (their name has an "@"): the ones in use are never counted.
            g=$(clean_glob "$CLEAN_LOG_DIR")
            clean_place "$CLEAN_LOG_DIR" 0 0 0 -path "$g/journal/*" -name '*@*.journal*' ;;
        crash)
            # Only what is right in the folder: /var/crash is open to every user, and something deeper
            # could be reached through a link that somebody puts there while this runs.
            for d in "${CLEAN_CRASH_DIRS[@]}"; do
                clean_place "$d" 0 0 1
            done ;;
        apt_cache)
            g=$(clean_glob "$CLEAN_APT_DIR")
            clean_place "$CLEAN_APT_DIR" 0 0 0 '(' -path "$g/archives/*.deb" -o -path "$g/archives/partial/*" \
                -o -path "$g/pkgcache.bin" -o -path "$g/srcpkgcache.bin" ')' ;;
        *) return 1 ;;
    esac
    return 0
}

# Succeeds if a service of the session bus has the name $1 (it runs).
clean_bus_has() {
    command -v dbus-send >/dev/null 2>&1 || return 1
    timeout 5 dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.NameHasOwner "string:$1" 2>/dev/null | grep -q 'boolean true'
}

# The clipboard entry. $1 = measure: only says in CLEAN_ITEM_NOTE which tools it
# would use; run: empties the clipboard and the primary selection with xsel (or
# xclip) on X11 and with wl-copy on Wayland, and the history of GPaste and Klipper
# if they run. The state is unavailable if there is no tool for this session; if
# none of the tools works, one failure is counted.
clean_clipboard() {
    local mode="$1" ok=0 x11=""
    CLEAN_ITEM_NOTE=""
    if [ -n "${DISPLAY-}" ]; then
        if command -v xsel >/dev/null 2>&1; then x11=xsel
        elif command -v xclip >/dev/null 2>&1; then x11=xclip; fi
    fi
    if [ -n "$x11" ]; then
        CLEAN_ITEM_NOTE+="${CLEAN_ITEM_NOTE:+, }$x11"
        if [ "$mode" = run ]; then
            case "$x11" in
                xsel)
                    timeout 5 xsel --clipboard --clear >/dev/null 2>&1 && ok=1
                    timeout 5 xsel --primary --clear >/dev/null 2>&1 && ok=1 ;;
                xclip)
                    timeout 5 xclip -selection clipboard -in < /dev/null >/dev/null 2>&1 && ok=1
                    timeout 5 xclip -selection primary -in < /dev/null >/dev/null 2>&1 && ok=1 ;;
            esac
        fi
    fi
    if [ -n "${WAYLAND_DISPLAY-}" ] && command -v wl-copy >/dev/null 2>&1; then
        CLEAN_ITEM_NOTE+="${CLEAN_ITEM_NOTE:+, }wl-copy"
        if [ "$mode" = run ]; then
            timeout 5 wl-copy --clear >/dev/null 2>&1 && ok=1
            timeout 5 wl-copy --primary --clear >/dev/null 2>&1 && ok=1
        fi
    fi
    if command -v gpaste-client >/dev/null 2>&1 && { clean_bus_has org.gnome.GPaste2 || clean_bus_has org.gnome.GPaste; }; then
        CLEAN_ITEM_NOTE+="${CLEAN_ITEM_NOTE:+, }GPaste"
        if [ "$mode" = run ]; then timeout 5 gpaste-client empty >/dev/null 2>&1 && ok=1; fi
    fi
    if clean_bus_has org.kde.klipper; then
        CLEAN_ITEM_NOTE+="${CLEAN_ITEM_NOTE:+, }Klipper"
        if [ "$mode" = run ]; then
            timeout 5 dbus-send --session --type=method_call --dest=org.kde.klipper /klipper \
                org.kde.klipper.klipper.clearClipboardHistory >/dev/null 2>&1 && ok=1
        fi
    fi
    if [ -z "$CLEAN_ITEM_NOTE" ]; then
        CLEAN_ITEM_STATE=unavailable
    elif [ "$mode" = run ] && [ "$ok" -eq 0 ]; then
        CLEAN_ITEM_FAILED=1
    fi
    return 0
}

# The entry of the X11 errors: ~/.xsession-errors is emptied (the session has it
# open and goes on writing in it) and ~/.xsession-errors.old is removed. Only
# regular files of this user: a link, or a file of someone else, is left alone.
clean_x11_logs() {
    local mode="$1" f size
    for f in "${HOME-}/.xsession-errors" "${HOME-}/.xsession-errors.old"; do
        clean_path_ok "$f" && [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] || continue
        size=$(stat -c %s -- "$f" 2>/dev/null) || continue
        [[ "$size" =~ ^[0-9]+$ ]] || continue
        CLEAN_ITEM_WHERE+="$f"$'\n'
        [ "$size" -gt 0 ] || continue
        if [ "$mode" = run ]; then
            case "$f" in
                *.old) rm -f -- "$f" 2>/dev/null ;;
                *) : > "$f" 2>/dev/null ;;
            esac || { CLEAN_ITEM_FAILED=$(( CLEAN_ITEM_FAILED + 1 )); continue; }
        fi
        CLEAN_ITEM_FILES=$(( CLEAN_ITEM_FILES + 1 ))
        CLEAN_ITEM_BYTES=$(( CLEAN_ITEM_BYTES + size ))
    done
    return 0
}

# apt and dpkg lock these files while they work: nothing of the apt cache is
# removed then.
CLEAN_APT_LOCKS=(/var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend)

# Succeeds if a process holds a lock (/proc/locks) on one of the files given.
clean_locked() {
    local f inode
    for f in "$@"; do
        inode=$(stat -c %i -- "$f" 2>/dev/null) || continue
        awk -v i="$inode" '{ n = split($6, a, ":"); if (a[n] == i) found = 1 } END { exit !found }' \
            /proc/locks 2>/dev/null && return 0
    done
    return 1
}

# Runs, with administrator rights, the vacuum of the systemd journal that the level $1
# asks for: the days to keep (S) or all that is archived (C, as BleachBit does).
clean_vacuum() {
    clean_days journal "$1"
    if [ "$1" = S ]; then
        priv_run journalctl "--vacuum-time=${REPLY}d" >/dev/null 2>&1
    else
        priv_run journalctl --vacuum-size=1 >/dev/null 2>&1
    fi
}

# The plan that clean_residual showed when it measured, which it checks when it runs.
CLEAN_RC_PLAN=""

# The entry of the residual configuration (rc_config): the packages that are no
# longer installed but keep their configuration files (pm_residual). measure
# counts them (CLEAN_ITEM_FILES, no size) and keeps the real plan of the manager,
# a purge simulated, in CLEAN_RC_PLAN and CLEAN_ITEM_WHERE; run purges them only if
# that plan is still the same (plan_still_valid) and counts those that went. The
# state is unavailable if the manager has no such state.
clean_residual() {
    local mode="$1" out st name before after
    local -a pkgs=()
    out=$(pm_residual)
    st=$?
    if [ "$st" -eq 2 ]; then CLEAN_ITEM_STATE=unavailable; return 0; fi
    while IFS= read -r name; do
        [ -z "$name" ] || ! pm_valid_name "$name" || pkgs+=("$name")
    done <<< "$out"
    before="${#pkgs[@]}"
    [ "$before" -gt 0 ] || return 0
    if [ "$mode" = run ] && [ -n "$CLEAN_RC_PLAN" ]; then
        if ! plan_still_valid "$CLEAN_RC_PLAN" purge "${pkgs[@]}"; then
            CLEAN_ITEM_FAILED="$before" CLEAN_ITEM_NOTE=changed
            return 0
        fi
    else
        if ! pm_simulate purge "${pkgs[@]}"; then
            CLEAN_ITEM_FAILED="$before"
            CLEAN_ITEM_NOTE=$(head -n 1 <<< "$PLAN_OUTPUT")
            return 0
        fi
        plan_has_removals "$PLAN_OUTPUT" || return 0
        if [ "$mode" = measure ]; then
            CLEAN_RC_PLAN="$PLAN_OUTPUT"
            CLEAN_ITEM_FILES="$before"
            CLEAN_ITEM_WHERE="$(grep -E '^(Purg|Remv) ' <<< "$PLAN_OUTPUT")"$'\n'
            return 0
        fi
    fi
    pm_run purge "${pkgs[@]}" >/dev/null 2>&1
    after=$(pm_residual | grep -c .)
    [ "$after" -le "$before" ] || after="$before"
    CLEAN_ITEM_FILES=$(( before - after ))
    CLEAN_ITEM_FAILED="$after"
    return 0
}

# Walks the places of an entry (clean_places must have filled CLEAN_PLACES) with the
# engine and leaves the totals in CLEAN_ITEM_FILES, _BYTES, _SKIPPED, _FAILED and
# _WHERE. $1 = 1: only count (CLEAN_DRY); $2 = 1: remove with administrator rights.
clean_item_scan() {
    local place root own prune depth days="$3" files=0 bytes=0 skipped=0 failed=0
    local -a f
    CLEAN_ITEM_WHERE=""
    for place in "${CLEAN_PLACES[@]+"${CLEAN_PLACES[@]}"}"; do
        IFS=$'\037' read -r -a f <<< "$place"
        root="${f[0]}" own="${f[1]}" prune="${f[2]}" depth="${f[3]}"
        unset 'f[0]' 'f[1]' 'f[2]' 'f[3]'     # what is left are the tests of find
        CLEAN_ITEM_WHERE+="$root"$'\n'
        CLEAN_ROOT="$2" CLEAN_DRY="$1" clean_apply "$root" "${CLEAN_OPENFILE:-/dev/null}" "$days" "$own" "$prune" \
            < <(CLEAN_DEPTH="$depth" clean_scan "$root" "$days" "$own" "${f[@]+"${f[@]}"}")
        files=$(( files + CLEAN_FILES ))
        bytes=$(( bytes + CLEAN_BYTES ))
        skipped=$(( skipped + CLEAN_SKIPPED ))
        failed=$(( failed + CLEAN_FAILED ))
    done
    CLEAN_ITEM_FILES="$files" CLEAN_ITEM_BYTES="$bytes" CLEAN_ITEM_SKIPPED="$skipped" CLEAN_ITEM_FAILED="$failed"
}

# Succeeds if the entry $1 needs administrator rights (the catalog says so).
clean_admin() {
    clean_field "$1" 4
    [ "$REPLY" = 1 ]
}

# Measures ($1 = measure: nothing is removed) or runs ($1 = run) the entry $2 at
# the level $3 and leaves in CLEAN_ITEM_FILES, _BYTES, _SKIPPED, _FAILED, _NOTE,
# _WHERE and _STATE what it did or would do. What a process has open (the file
# CLEAN_OPENFILE, if the caller made one) is never removed. What needs
# administrator rights is only removed with them (priv_run); measuring needs none.
# The state is unavailable if the entry cannot work on this system, and busy
# (the note says what is in use) if apt is working. The journal is measured by
# its archived files and cleaned with journalctl; its totals when it runs are
# what the vacuum took away. Status 2, doing nothing, for a mode that is not one
# of those or an entry that does not exist.
# shellcheck disable=SC2034  # _SKIPPED and _STATE are read by the flow of P.4d
clean_item() {
    local mode="$1" id="$2" level="$3" days dry=0 root=0 files bytes st
    CLEAN_ITEM_FILES=0 CLEAN_ITEM_BYTES=0 CLEAN_ITEM_SKIPPED=0 CLEAN_ITEM_FAILED=0
    CLEAN_ITEM_NOTE="" CLEAN_ITEM_WHERE="" CLEAN_ITEM_STATE=ok
    case "$mode" in
        measure) dry=1 ;;
        run) ;;
        *) return 2 ;;
    esac
    case "$id" in
        clipboard) clean_clipboard "$mode"; return ;;
        x11_logs) clean_x11_logs "$mode"; return ;;
        rc_config) clean_residual "$mode"; return ;;
    esac
    clean_places "$id" "$level" || return 2
    clean_days "$id" "$level"
    days="$REPLY"
    case "$id" in
        apt_cache)
            if [ "$PM" != apt ]; then CLEAN_ITEM_STATE=unavailable; return 0; fi
            if clean_locked "${CLEAN_APT_LOCKS[@]}"; then CLEAN_ITEM_STATE=busy CLEAN_ITEM_NOTE=apt; return 0; fi ;;
        journal)
            if ! command -v journalctl >/dev/null 2>&1; then CLEAN_ITEM_STATE=unavailable; return 0; fi
            clean_item_scan 1 0 "$days"
            if [ "$mode" = run ]; then
                files="$CLEAN_ITEM_FILES" bytes="$CLEAN_ITEM_BYTES"
                clean_vacuum "$level"
                st=$?
                clean_item_scan 1 0 "$days"
                CLEAN_ITEM_FILES=$(( files > CLEAN_ITEM_FILES ? files - CLEAN_ITEM_FILES : 0 ))
                CLEAN_ITEM_BYTES=$(( bytes > CLEAN_ITEM_BYTES ? bytes - CLEAN_ITEM_BYTES : 0 ))
                [ "$st" -eq 0 ] || CLEAN_ITEM_FAILED=1
            fi
            return 0 ;;
    esac
    clean_admin "$id" && root=1
    clean_item_scan "$dry" "$root" "$days"
    return 0
}

clean_system() {
    header
    text_wrap "$(msg cleaning)"
    echo
    plan_password_hint
    plan_authorize || return

    pm_simulate autoremove
    local sim_status=$?
    local plan="$PLAN_OUTPUT"
    if [ "$sim_status" -ne 0 ]; then
        show_plan_error "$plan"
        return
    fi

    local before after freed freed_mb removed_note record_note="" removed=0
    before=$(df --output=avail -B1 / | tail -1 | tr -d ' ')

    if plan_has_removals "$plan"; then
        review_plan "$(msg plan_real_clean)" "$plan" "" || return
        if ! plan_still_valid "$plan" autoremove; then
            show_message "$(msg plan_changed)"
            return
        fi
        header
        text_wrap "$(msg cleaning)"
        echo
        MENU_APPS=-1
        execute_removal "$plan" autoremove
        local status=$?
        if [ "$status" -ne 0 ]; then
            removal_error_text "$status"
            show_message "$REPLY"
            return
        fi
        DETECTION_DONE=0
        removed_note="$(msg dependencies_removed)"
        record_note="$(record_note_text)"
        removed=1
    else
        removed_note="$(msg no_unused_deps)"
    fi

    local cache_status cache_msg
    if priv_authenticate; then
        run_pm_step "$(msg cleaning)" clean
        cache_status=$?
    else
        # Cancelled with nothing removed: there is nothing to report as done.
        if [ "$removed" -eq 0 ]; then
            show_message "$(msg priv_denied)"
            return
        fi
        cache_status=$PRIV_STATUS_DENIED
    fi
    if [ "$cache_status" -eq 0 ]; then
        cache_msg="$(msg cache_cleaned)"
    else
        msgf_v cache_msg cache_clean_failed "$cache_status"
    fi

    after=$(df --output=avail -B1 / | tail -1 | tr -d ' ')
    freed=$(( after - before ))
    if [ "$freed" -lt 0 ]; then
        freed=0
    fi
    freed_mb=$(( freed / 1024 / 1024 ))

    local space_msg
    msgf_v space_msg space_recovered "$freed_mb"

    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_msgbox "$(msg clean_done)\n\n${removed_note}\n${cache_msg}\n${space_msg}${record_note}"
    else
        echo
        text_say "$C_OK" "$(msg clean_done)"
        echo
        text_wrap "$removed_note"
        text_wrap "$cache_msg"
        text_wrap "$space_msg"
        [ -n "$record_note" ] && text_print "$record_note"
        pause
    fi
}

# ----------------------------------------------------------------------------
# Option 4: the two actions of the cleaning (FP.4d). "Clean up dependencies" is
# clean_system. "Deep cleanup" asks the level, then what to clean at it (all of
# it, whole categories or entry by entry) and works with the catalog above.
# ----------------------------------------------------------------------------
CLEAN_LEVEL=""           # the level chosen for the deep cleanup: S (simple) or C (complete)
CLEAN_CHOSEN=()          # the entries chosen to clean at that level, in catalog order

# Option 4: asks the action and runs it. Going back leaves it, doing nothing.
clean_menu() {
    local -a tags=(1 2) labels=() descs=() icons=()
    labels=("$(msg clean_action_deps)" "$(msg clean_action_deep)")
    descs=("$(msg clean_action_deps_desc)" "$(msg clean_action_deep_desc)")
    menu_icon_list clean tags icons
    choose_menu "$(msg clean_menu_prompt)" tags labels descs icons || return 0
    case "$REPLY" in
        1) clean_system ;;
        2) deep_clean ;;
    esac
}

# Asks the level of the deep cleanup and puts it in CLEAN_LEVEL (S or C). Fails,
# leaving CLEAN_LEVEL empty, if the user goes back or the menu gives anything else.
clean_choose_level() {
    local -a tags=(S C) labels=() descs=() icons=()
    CLEAN_LEVEL=""
    labels=("$(msg clean_level_simple)" "$(msg clean_level_complete)")
    descs=("$(msg clean_level_simple_desc)" "$(msg clean_level_complete_desc)")
    menu_icon_list level tags icons
    choose_menu "$(msg clean_level_prompt)" tags labels descs icons || return 1
    case "${REPLY^^}" in
        S|C) CLEAN_LEVEL="${REPLY^^}" ;;
        *) return 1 ;;
    esac
}

# Puts in REPLY the names of the entries of the category $1 at the level $2, in
# catalog order and separated by commas; empty if the level has none of them.
clean_cat_names() {
    local id joined=""
    clean_ids "$2"
    for id in "${CLEAN_LIST[@]}"; do
        clean_field "$id" 2
        [ "$REPLY" = "$1" ] || continue
        joined+="${joined:+, }$(clean_name "$id")"
    done
    REPLY="$joined"
}

# Puts in REPLY what the level $1 cleans: its title and, for every category, the
# names of its entries, with \n sequences.
clean_level_text() {
    local cat text
    text="$(msg clean_level_includes)"
    for cat in "${CLEAN_CATEGORIES[@]}"; do
        clean_cat_names "$cat" "$1"
        [ -z "$REPLY" ] || text+="\n$(clean_cat_name "$cat"): $REPLY"
    done
    REPLY="$text"
}

# Asks what to clean at the level $1 and puts all, cats or entries in REPLY. The
# menu starts with what the level cleans, so that the list stays in sight. Fails
# if the user goes back.
clean_choose_scope() {
    local -a tags=(1 2 3) labels=() descs=() icons=()
    local list
    clean_level_text "$1"
    list="$REPLY"
    labels=("$(msg clean_scope_all)" "$(msg clean_scope_cats)" "$(msg clean_scope_entries)")
    descs=("$(msg clean_scope_all_desc)" "$(msg clean_scope_cats_desc)" "$(msg clean_scope_entries_desc)")
    menu_icon_list scope tags icons
    choose_menu "${list}\n\n$(msg clean_scope_prompt)" tags labels descs icons || return 1
    case "$REPLY" in
        1) REPLY=all ;;
        2) REPLY=cats ;;
        3) REPLY=entries ;;
        *) REPLY=""; return 1 ;;
    esac
}

# A list with checkboxes in the active interface. $1 = kind (cats or entries: it
# decides the text above the list); $2, $3 and $4 = the names of the arrays of
# names, descriptions and marks (0/1; updated), one value per entry. Status 0 =
# confirmed, 1 = went back.
clean_checklist() {
    local kind="$1" prompt help i
    local -n _cc_names="$2" _cc_descs="$3"
    local -a labels=() blanks=() hay=()
    for i in "${!_cc_names[@]}"; do
        labels+=("${_cc_names[$i]} ${SYM_DASH} ${_cc_descs[$i]}")
        blanks+=("")
        fold_search "${_cc_names[$i]} ${_cc_descs[$i]}"
        hay+=("$REPLY")
    done
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        if [ "$kind" = cats ]; then prompt="$(msg clean_pick_cats)"; else prompt="$(msg clean_pick_entries)"; fi
        if [ "$UI_ENGINE" = "gui" ]; then help="$(msg select_help_gui)"; else help="$(msg select_help)"; fi
        wt_checklist_search "${prompt}\n${help}" labels hay "$4"
    else
        text_checklist_search "clean_$kind" "$2" blanks "$3" hay "$4"
    fi
}

# The categories of the level $1 as a list to mark: each one marked brings every
# entry of its own at that level. None starts marked, because a category carries
# all of its entries (the trash too, at the complete level). Puts the entries in
# CLEAN_CHOSEN, in catalog order. Fails, leaving it empty, if the user goes back.
clean_pick_categories() {
    local cat id i
    local -a cats=() names=() descs=() sel=()
    CLEAN_CHOSEN=()
    for cat in "${CLEAN_CATEGORIES[@]}"; do
        clean_cat_names "$cat" "$1"
        [ -n "$REPLY" ] || continue
        cats+=("$cat")
        descs+=("$REPLY")
        names+=("$(clean_cat_name "$cat")")
        sel+=(0)
    done
    while true; do
        clean_checklist cats names descs sel || return 1
        clean_ids "$1"
        for id in "${CLEAN_LIST[@]}"; do
            clean_field "$id" 2
            for i in "${!cats[@]}"; do
                [ "${cats[i]}" = "$REPLY" ] && [ "${sel[i]}" -eq 1 ] && CLEAN_CHOSEN+=("$id")
            done
        done
        [ "${#CLEAN_CHOSEN[@]}" -eq 0 ] || return 0
        show_message "$(msg clean_pick_none)"
    done
}

# The entries of the level $1 as a list to mark. All start marked except the
# trash, which cannot be undone and is cleaned only if the user marks it. Puts the
# marked ones in CLEAN_CHOSEN, in catalog order. Fails, leaving it empty, if the
# user goes back.
clean_pick_entries() {
    local id i
    local -a ids=() names=() descs=() sel=()
    CLEAN_CHOSEN=()
    clean_ids "$1"
    for id in "${CLEAN_LIST[@]}"; do
        ids+=("$id")
        names+=("$(clean_name "$id")")
        descs+=("$(clean_desc "$id")")
        if [ "$id" = trash ]; then sel+=(0); else sel+=(1); fi
    done
    while true; do
        clean_checklist entries names descs sel || return 1
        for i in "${!ids[@]}"; do
            [ "${sel[i]}" -ne 1 ] || CLEAN_CHOSEN+=("${ids[i]}")
        done
        [ "${#CLEAN_CHOSEN[@]}" -eq 0 ] || return 0
        show_message "$(msg clean_pick_none)"
    done
}

# Asks what to clean at the level $1 and puts the entries in CLEAN_CHOSEN, in
# catalog order. Going back from a list returns to the scope menu; going back from
# the scope menu fails, leaving CLEAN_CHOSEN empty (the level menu comes next).
clean_pick() {
    CLEAN_CHOSEN=()
    while clean_choose_scope "$1"; do
        case "$REPLY" in
            all)
                clean_ids "$1"
                CLEAN_CHOSEN=("${CLEAN_LIST[@]}")
                return 0 ;;
            cats) clean_pick_categories "$1" && return 0 ;;
            entries) clean_pick_entries "$1" && return 0 ;;
        esac
    done
    return 1
}

# ----------------------------------------------------------------------------
# What the deep cleanup would do (FP.4d, step 2b): the entries chosen are
# measured, removing nothing, and shown with their places and sizes.
# ----------------------------------------------------------------------------
CLEAN_M_STATE=()         # for each entry of CLEAN_CHOSEN, in its order: ok, unavailable or busy ...
CLEAN_M_FILES=()         # ... the files it would remove (the packages, for rc_config)
CLEAN_M_BYTES=()         # ... their size in bytes
CLEAN_M_FAILED=()        # ... what could not be worked out
CLEAN_M_NOTE=()          # ... what clean_item says of it (open browsers, tools, what holds apt)
CLEAN_M_WHERE=()         # ... where it works, one place per line
CLEAN_TOTAL_FILES=0      # the files of the entries that work (not the packages of rc_config)
CLEAN_TOTAL_BYTES=0      # ... and their size in bytes
CLEAN_PLACES_SHOWN=6     # the places the summary names for each entry; the rest are only counted

# Makes the file CLEAN_OPENFILE with what the processes have open, which the
# engine never removes or counts. Fails, leaving CLEAN_OPENFILE empty, if it
# cannot be made.
clean_open_prepare() {
    clean_open_done
    CLEAN_OPENFILE="$(mktemp "${TMPDIR:-/tmp}/mintapp-clean.XXXXXX" 2>/dev/null)" || { CLEAN_OPENFILE=""; return 1; }
    clean_open_files "$CLEAN_OPENFILE"
}

# Removes the file CLEAN_OPENFILE, if there is one.
clean_open_done() {
    [ -z "${CLEAN_OPENFILE:-}" ] || rm -f -- "$CLEAN_OPENFILE"
    CLEAN_OPENFILE=""
}

# Measures the entries of CLEAN_CHOSEN at the level CLEAN_LEVEL, removing nothing
# (clean_item measure), and keeps in the CLEAN_M_* arrays what each one would do and
# in CLEAN_TOTAL_* the sum of what works.
clean_measure_chosen() {
    local i id
    CLEAN_M_STATE=() CLEAN_M_FILES=() CLEAN_M_BYTES=() CLEAN_M_FAILED=() CLEAN_M_NOTE=() CLEAN_M_WHERE=()
    CLEAN_TOTAL_FILES=0 CLEAN_TOTAL_BYTES=0
    clean_open_prepare || true
    for i in "${!CLEAN_CHOSEN[@]}"; do
        id="${CLEAN_CHOSEN[i]}"
        clean_item measure "$id" "$CLEAN_LEVEL" || true
        CLEAN_M_STATE[i]="$CLEAN_ITEM_STATE"
        CLEAN_M_FILES[i]="$CLEAN_ITEM_FILES"
        CLEAN_M_BYTES[i]="$CLEAN_ITEM_BYTES"
        CLEAN_M_FAILED[i]="$CLEAN_ITEM_FAILED"
        CLEAN_M_NOTE[i]="$CLEAN_ITEM_NOTE"
        CLEAN_M_WHERE[i]="$CLEAN_ITEM_WHERE"
        if [ "$CLEAN_ITEM_STATE" = ok ] && [ "$id" != rc_config ]; then
            CLEAN_TOTAL_FILES=$(( CLEAN_TOTAL_FILES + CLEAN_ITEM_FILES ))
            CLEAN_TOTAL_BYTES=$(( CLEAN_TOTAL_BYTES + CLEAN_ITEM_BYTES ))
        fi
    done
    clean_open_done
}

# Puts in REPLY what the measure says of the entry number $1 of CLEAN_CHOSEN:
# unavailable (this system lacks it), busy (in use), unknown (could not be worked
# out), empty (nothing to clean) or work. The summary shows only the "work" ones
# with their size, and only those run: what is confirmed is what is done.
clean_entry_class() {
    local i="$1"
    case "${CLEAN_M_STATE[i]-}" in
        unavailable|busy) REPLY="${CLEAN_M_STATE[i]}"; return 0 ;;
    esac
    if [ "${CLEAN_M_FAILED[i]:-0}" -gt 0 ] && [ "${CLEAN_M_FILES[i]:-0}" -eq 0 ]; then
        REPLY=unknown
        return 0
    fi
    case "${CLEAN_CHOSEN[i]}" in
        clipboard) REPLY=work ;;
        rc_config) if [ "${CLEAN_M_FILES[i]:-0}" -gt 0 ]; then REPLY=work; else REPLY=empty; fi ;;
        *) if [ "${CLEAN_M_FILES[i]:-0}" -eq 0 ] && [ "${CLEAN_M_BYTES[i]:-0}" -eq 0 ]; then REPLY=empty; else REPLY=work; fi ;;
    esac
}

# Succeeds if something measured would be cleaned (an entry of class "work").
clean_has_work() {
    local i
    for i in "${!CLEAN_CHOSEN[@]}"; do
        clean_entry_class "$i"
        [ "$REPLY" != work ] || return 0
    done
    return 1
}

# Runs the command $2 (with the arguments that follow) while the user is told $1:
# in windows with a progress window, otherwise on a screen with the text.
clean_working() {
    local text="$1"
    shift
    if [ "$UI_ENGINE" = "gui" ]; then
        run_gui_step "$text" "$@"
    else
        header
        text_wrap "$text"
        "$@"
    fi
}

# Puts in REPLY the join of the arguments, with ", " between them.
clean_join() {
    local s="" x
    for x in "$@"; do s+="${s:+, }$x"; done
    REPLY="$s"
}

# Puts in REPLY the count $1 with its noun: "1 file", "340 files".
clean_files_text() {
    if [ "$1" -eq 1 ]; then msgf_v REPLY clean_files_1 "$1"; else msgf_v REPLY clean_files_n "$1"; fi
}

# The same for packages.
clean_pkgs_text() {
    if [ "$1" -eq 1 ]; then msgf_v REPLY clean_pkgs_1 "$1"; else msgf_v REPLY clean_pkgs_n "$1"; fi
}

# Puts in REPLY an amount of files as the screens write it: "340 KB, 12 files".
# $1 = bytes, $2 = files.
clean_amount_text() {
    local size
    format_size_kb $(( ($1 + 1023) / 1024 ))
    size="$REPLY"
    clean_files_text "$2"
    REPLY="$size, $REPLY"
}

# Puts in REPLY the lines (with \n sequences) that name what was left out: the open
# browsers $1 and the names in the arrays called $2 to $5 (nothing to clean, not
# available, in use, not worked out), in that order.
clean_notes_text() {
    local opened="$1" txt notes="" NL='\n'
    local -n _cn_empty="$2" _cn_unavail="$3" _cn_busy="$4" _cn_unknown="$5"
    if [ -n "$opened" ]; then msgf_v txt clean_sum_open "$opened"; notes+="${notes:+$NL}$txt"; fi
    if [ "${#_cn_empty[@]}" -gt 0 ]; then
        clean_join "${_cn_empty[@]}"; msgf_v txt clean_sum_empty "$REPLY"; notes+="${notes:+$NL}$txt"
    fi
    if [ "${#_cn_unavail[@]}" -gt 0 ]; then
        clean_join "${_cn_unavail[@]}"; msgf_v txt clean_sum_unavailable "$REPLY"; notes+="${notes:+$NL}$txt"
    fi
    if [ "${#_cn_busy[@]}" -gt 0 ]; then
        clean_join "${_cn_busy[@]}"; msgf_v txt clean_sum_busy "$REPLY"; notes+="${notes:+$NL}$txt"
    fi
    if [ "${#_cn_unknown[@]}" -gt 0 ]; then
        clean_join "${_cn_unknown[@]}"; msgf_v txt clean_sum_unknown "$REPLY"; notes+="${notes:+$NL}$txt"
    fi
    REPLY="$notes"
}

# Puts in REPLY the place $2 of the entry $1 as the summary names it: the home
# folder as "~", a backslash doubled (the text goes through printf %b) and, where
# only some files of a folder go, which ones.
clean_place_text() {
    local p="$2"
    case "$1" in
        recent)
            [[ "$p" != */RecentDocuments ]] || p+="/*.desktop"
            [[ "$p" != */.local/share ]] || p+="/recently-used.xbel*" ;;
        trash)
            [[ "$p" != */Trash ]] || p+="/directorysizes"
            [[ "$p" != */Trash/info ]] || p+="/*.trashinfo" ;;
        rotated_logs) p+=" (*.1, *.gz, *.xz, *.bz2, *.zst, *.old, *-????????)" ;;
        journal) p+="/journal/*@*.journal*" ;;
        apt_cache) p+=" (*.deb, *.bin)" ;;
    esac
    [ -z "${HOME-}" ] || [[ "$p" != "$HOME"/* ]] || p="~${p#"$HOME"}"
    REPLY="${p//\\/\\\\}"
}

# Puts in REPLY the short name of the level CLEAN_LEVEL in lower case, for the
# titles of the summary and the result, where it goes in the middle of a sentence.
clean_level_word() {
    REPLY="$(msg clean_level_simple)"
    [ "$CLEAN_LEVEL" = S ] || REPLY="$(msg clean_level_complete)"
    REPLY="${REPLY%% (*}"
    REPLY="${REPLY,,}"
}

# Puts in REPLY the summary of what clean_measure_chosen measured, with \n
# sequences: each entry with its size and places, then the entries with nothing to
# clean, those this system lacks and those in use, and the total.
clean_summary_text() {
    local i id name detail line pkg n shown size title out txt body="" notes="" opened="" NL='\n'
    local -a empty=() unavail=() busy=() unknown=()
    clean_level_word
    msgf_v title clean_sum_title "$REPLY"
    for i in "${!CLEAN_CHOSEN[@]}"; do
        id="${CLEAN_CHOSEN[i]}"
        name="$(clean_name "$id")"
        [ "$id" != browsers ] || opened="${CLEAN_M_NOTE[i]-}"
        clean_entry_class "$i"
        case "$REPLY" in
            unavailable) unavail+=("$name"); continue ;;
            busy) busy+=("$name (${CLEAN_M_NOTE[i]-})"); continue ;;
            unknown) unknown+=("$name"); continue ;;
            empty) empty+=("$name"); continue ;;
        esac
        case "$id" in
            clipboard) msgf_v detail clean_sum_clipboard "${CLEAN_M_NOTE[i]-}" ;;
            rc_config)
                clean_pkgs_text "${CLEAN_M_FILES[i]}"
                detail="$REPLY" ;;
            *)
                clean_amount_text "${CLEAN_M_BYTES[i]}" "${CLEAN_M_FILES[i]}"
                detail="$REPLY" ;;
        esac
        body+="${body:+$NL}$name: $detail"
        n=0 shown=0
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            if [ "$id" = rc_config ]; then
                read -r _ pkg _ <<< "$line"
                pm_valid_name "$pkg" || continue
                REPLY="$pkg"
            else
                clean_place_text "$id" "$line"
            fi
            n=$(( n + 1 ))
            [ "$shown" -lt "$CLEAN_PLACES_SHOWN" ] || continue
            body+="$NL  $REPLY"
            shown=$(( shown + 1 ))
        done <<< "${CLEAN_M_WHERE[i]-}"
        if [ "$n" -gt "$shown" ]; then
            msgf_v txt clean_sum_more "$(( n - shown ))"
            body+="$NL  $txt"
        fi
    done
    clean_notes_text "$opened" empty unavail busy unknown
    notes="$REPLY"
    out="$title"
    [ -z "$body" ] || out+="$NL$NL$body"
    [ -z "$notes" ] || out+="$NL$NL$notes"
    if ! clean_has_work; then
        out+="$NL$NL$(msg clean_sum_nothing)"
    elif [ "$CLEAN_TOTAL_FILES" -gt 0 ]; then
        format_size_kb $(( (CLEAN_TOTAL_BYTES + 1023) / 1024 ))
        size="$REPLY"
        clean_files_text "$CLEAN_TOTAL_FILES"
        msgf_v txt clean_sum_total "$size" "$REPLY"
        out+="$NL$NL$txt"
    fi
    REPLY="$out"
}

# Shows the summary $1 and asks whether to clean. The question starts on "no" (and
# the dialog button is "Clean", not "OK"), so a stray Enter never starts it. In the
# dialogs a long summary scrolls. Succeeds only if the user confirms.
clean_confirm() {
    local summary="$1"
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_yesno "${summary}\n\n$(msg clean_confirm)" "$(msg clean_yes)" "$(msg cancel)" big defaultno
        return
    fi
    header
    text_print "$summary"
    section_rule
    if ! ask_yes_no "" "$(msg clean_confirm_text)"; then
        text_wrap "$(msg cancelled)"
        pause
        return 1
    fi
}

# Measures what was chosen, shows what the cleaning would do (places and sizes)
# and asks to confirm it. With nothing to clean it only shows the summary. Succeeds
# only if there is something to clean and the user confirms.
clean_summary() {
    local text
    clean_working "$(msg clean_measuring)" clean_measure_chosen
    clean_summary_text
    text="$REPLY"   # clean_has_work writes REPLY too
    if ! clean_has_work; then
        show_message "$text" big
        return 1
    fi
    clean_confirm "$text"
}

# ----------------------------------------------------------------------------
# What the deep cleanup does (FP.4d, step 3): the entries that the summary showed
# with something to clean run one at a time, and what each one did is kept.
# ----------------------------------------------------------------------------
CLEAN_R_STATE=()         # for each entry of CLEAN_CHOSEN, in its order: done, skipped or failed ...
CLEAN_R_WHY=()           # ... why it was skipped: empty, unavailable, busy or unknown
CLEAN_R_FILES=()         # ... what it removed (the packages, for rc_config) ...
CLEAN_R_BYTES=()         # ... their size in bytes
CLEAN_R_FAILED=()        # ... what it could not remove
CLEAN_R_NOTE=()          # ... what clean_item says of it (open browsers, what holds apt, changed)
CLEAN_FREED_FILES=0      # the files removed by all of them (not the packages of rc_config)
CLEAN_FREED_BYTES=0      # ... and their size in bytes

# Writes (atomically) the record of a cleaning. $1 = file, $2 = status. It reads the last
# measure (CLEAN_M_*) and run (CLEAN_R_*). One line "id: state" per entry, with its files and
# bytes (the packages, for rc_config): what it did if it ran, what the measure said ("measured")
# if it did not yet (pending, or running if it was the one in progress) and nothing if it was
# skipped. Then the packages of the rc_config plan and the totals.
write_clean_record() {
    local file="$1" status="$2" i id state files bytes failed detail level=complete rc=0
    local -a lines=()
    [ "$CLEAN_LEVEL" != S ] || level=simple
    for i in "${!CLEAN_CHOSEN[@]}"; do
        id="${CLEAN_CHOSEN[i]}" state="${CLEAN_R_STATE[i]-}" detail=""
        if [ -z "$state" ] || [ "$state" = running ]; then
            clean_entry_class "$i"
            if [ "$REPLY" != work ]; then state="skipped ($REPLY)"; elif [ -z "$state" ]; then state=pending; fi
        elif [ "$state" = skipped ]; then
            state="skipped (${CLEAN_R_WHY[i]-})"
        fi
        if [[ "$state" != skipped* ]]; then
            if [ "$state" = pending ] || [ "$state" = running ]; then
                files="${CLEAN_M_FILES[i]:-0}" bytes="${CLEAN_M_BYTES[i]:-0}" failed=0
            else
                files="${CLEAN_R_FILES[i]:-0}" bytes="${CLEAN_R_BYTES[i]:-0}" failed="${CLEAN_R_FAILED[i]:-0}"
            fi
            case "$id" in
                clipboard) ;;
                rc_config) detail=", packages $files" ;;
                *) detail=", files $files, bytes $bytes" ;;
            esac
            [ "$failed" -eq 0 ] || detail+=", failed $failed"
            if [ "$id" = rc_config ]; then
                rc=1
                [ "${CLEAN_R_NOTE[i]-}" != changed ] || detail+=", plan changed"
            fi
            case "$state" in pending|running) [ -z "$detail" ] || detail+=" measured" ;; esac
        fi
        lines+=("$id: $state$detail")
    done
    {
        printf '# MintApp Remover cleaning record\n'
        printf '# Date: %s\n' "$(date -Is)"
        printf '# Status: %s\n' "$status"
        printf '# Level: %s\n' "$level"
        if [[ "$status" == interrupted* ]]; then
            printf '# The run was interrupted: part of this cleaning may already be done.\n'
        fi
        printf '#\n# Entries:\n'
        if [ "${#lines[@]}" -gt 0 ]; then printf '%s\n' "${lines[@]}"; fi
        printf '#\n# Measured: files %s, bytes %s\n' "$CLEAN_TOTAL_FILES" "$CLEAN_TOTAL_BYTES"
        case "$status" in
            started) ;;
            interrupted*) printf '# Recovered by the finished entries: files %s, bytes %s\n' "$CLEAN_FREED_FILES" "$CLEAN_FREED_BYTES" ;;
            *) printf '# Recovered: files %s, bytes %s\n' "$CLEAN_FREED_FILES" "$CLEAN_FREED_BYTES" ;;
        esac
        if [ "$rc" -eq 1 ] && [ -n "$CLEAN_RC_PLAN" ]; then
            printf '#\n# Packages in the rc_config plan:\n'
            grep -E '^(Purg|Remv) ' <<< "$CLEAN_RC_PLAN" || true
        fi
    } | atomic_write "$file"
}

# Starts the record of the cleaning, "started", before anything runs, so that an interrupted
# run still leaves one (ACTIVE_RECORD, for on_exit). Sets LAST_RECORD ("" if it could not be
# written).
clean_record_begin() {
    local record
    LAST_RECORD=""
    RECORD_SEQ=$((RECORD_SEQ + 1))
    record="$(state_dir)/clean-$(date +%Y%m%d-%H%M%S)-$$-$RECORD_SEQ.txt"
    ensure_state_dir || true
    if write_clean_record "$record" started; then
        LAST_RECORD="$record"
    fi
    ACTIVE_RECORD="$LAST_RECORD" ACTIVE_CLEAN=1
}

# Closes the record of the cleaning with its final status: completed, or failed (how many
# entries could not be cleaned completely). The second write replaces the first.
clean_record_end() {
    local status=completed n=0 st
    ACTIVE_RECORD="" ACTIVE_CLEAN=0
    [ -n "$LAST_RECORD" ] || return 0
    for st in "${CLEAN_R_STATE[@]+"${CLEAN_R_STATE[@]}"}"; do
        [ "$st" != failed ] || n=$((n + 1))
    done
    if [ "$n" -eq 1 ]; then
        status="failed (1 entry not cleaned completely)"
    elif [ "$n" -gt 1 ]; then
        status="failed ($n entries not cleaned completely)"
    fi
    write_clean_record "$LAST_RECORD" "$status" || LAST_RECORD=""
}

# Succeeds if an entry that will run needs administrator rights.
clean_run_needs_priv() {
    local i
    for i in "${!CLEAN_CHOSEN[@]}"; do
        clean_entry_class "$i"
        [ "$REPLY" = work ] || continue
        clean_admin "${CLEAN_CHOSEN[i]}" && return 0
    done
    return 1
}

# Gets the administrator rights before anything is recorded or run, so that a password that
# is not given or is wrong stops the cleaning at once, and does not turn into one failed
# entry after another (what priv_run runs here has its output thrown away). In windows it is
# priv_authenticate. On a terminal it says that the password may be asked and, with sudo,
# asks it now (sudo -v); doas has no such check, so it asks command by command. Status 0 =
# go on, PRIV_STATUS_DENIED = no rights.
clean_priv_check() {
    if [ "$UI_ENGINE" = "gui" ]; then
        priv_authenticate || return "$PRIV_STATUS_DENIED"
        return 0
    fi
    text_print "$(msg clean_password_note)"
    echo
    [ -n "$PRIV_CMD" ] || detect_privilege || return 0
    [ "${PRIV_CMD##*/}" = "sudo" ] || return 0
    "$PRIV_CMD" -v || return "$PRIV_STATUS_DENIED"
}

# Runs the entry $1 at the level CLEAN_LEVEL (clean_item run) after saying which one it
# is, in a line of text. In windows the line goes to the output of the whole run
# (clean_run_chosen), and the progress window shows the last line it wrote.
clean_run_step() {
    local text
    msgf_v text clean_running "$(clean_name "$1")"
    if [ "$UI_ENGINE" = "gui" ]; then printf '%s\n' "$text"; else text_wrap "$text"; fi
    clean_item run "$1" "$CLEAN_LEVEL"
}

# Runs, one after the other, the entries of CLEAN_CHOSEN that clean_entry_class calls
# "work" and keeps in the CLEAN_R_* arrays what each one did: skipped (the others, and
# one that is busy, unavailable or has nothing left now), failed (something could not be
# removed) or done. CLEAN_FREED_* add up what was removed, also by an entry that failed
# in part. The list of what is open is made first and removed after.
clean_run_entries() {
    local i id
    clean_open_prepare || true
    for i in "${!CLEAN_CHOSEN[@]}"; do
        id="${CLEAN_CHOSEN[i]}"
        CLEAN_R_FILES[i]=0 CLEAN_R_BYTES[i]=0 CLEAN_R_FAILED[i]=0 CLEAN_R_WHY[i]="" CLEAN_R_NOTE[i]=""
        clean_entry_class "$i"
        if [ "$REPLY" != work ]; then
            CLEAN_R_STATE[i]=skipped CLEAN_R_WHY[i]="$REPLY" CLEAN_R_NOTE[i]="${CLEAN_M_NOTE[i]-}"
            continue
        fi
        CLEAN_R_STATE[i]=running
        clean_run_step "$id" || true
        CLEAN_R_NOTE[i]="$CLEAN_ITEM_NOTE"
        case "$CLEAN_ITEM_STATE" in
            unavailable|busy) CLEAN_R_STATE[i]=skipped CLEAN_R_WHY[i]="$CLEAN_ITEM_STATE"; continue ;;
        esac
        CLEAN_R_FILES[i]="$CLEAN_ITEM_FILES" CLEAN_R_BYTES[i]="$CLEAN_ITEM_BYTES" CLEAN_R_FAILED[i]="$CLEAN_ITEM_FAILED"
        if [ "$CLEAN_ITEM_FAILED" -gt 0 ]; then
            CLEAN_R_STATE[i]=failed
        elif [ "$id" != clipboard ] && [ "$CLEAN_ITEM_FILES" -eq 0 ] && [ "$CLEAN_ITEM_BYTES" -eq 0 ]; then
            CLEAN_R_STATE[i]=skipped CLEAN_R_WHY[i]=empty
        else
            CLEAN_R_STATE[i]="done"
        fi
        if [ "$id" != rc_config ]; then
            CLEAN_FREED_FILES=$(( CLEAN_FREED_FILES + CLEAN_ITEM_FILES ))
            CLEAN_FREED_BYTES=$(( CLEAN_FREED_BYTES + CLEAN_ITEM_BYTES ))
        fi
    done
    clean_open_done
}

# Runs what the summary showed (clean_run_entries) and keeps what each entry did. In
# windows the whole run has one progress window, whose text is the line of the entry that
# works (clean_run_step). The administrator rights come first (clean_priv_check): status
# PRIV_STATUS_DENIED, with nothing run and no record, if they are not given. If something
# runs, the record (clean_record_begin) is written before it and closed after;
# LAST_RECORD is its path ("" if there is none).
clean_run_chosen() {
    CLEAN_R_STATE=() CLEAN_R_WHY=() CLEAN_R_FILES=() CLEAN_R_BYTES=() CLEAN_R_FAILED=() CLEAN_R_NOTE=()
    CLEAN_FREED_FILES=0 CLEAN_FREED_BYTES=0
    LAST_RECORD=""
    if clean_run_needs_priv; then
        clean_priv_check || return "$PRIV_STATUS_DENIED"
    fi
    if clean_has_work; then clean_record_begin; fi
    if [ "$UI_ENGINE" = "gui" ]; then
        run_gui_step "$(msg cleaning)" clean_run_entries
    else
        clean_run_entries
    fi
    clean_record_end
    return 0
}

# Succeeds if an entry failed in the last run.
clean_has_failed() {
    local st
    for st in "${CLEAN_R_STATE[@]+"${CLEAN_R_STATE[@]}"}"; do
        [ "$st" != failed ] || return 0
    done
    return 1
}

# Puts in REPLY what clean_run_chosen did, with \n sequences: what was cleaned, what
# failed (with what did go), what was skipped (grouped as in the summary) and the
# space recovered.
clean_result_text() {
    local i id name detail left size txt title out opened="" ok_body="" bad_body="" notes="" NL='\n'
    local -a empty=() unavail=() busy=() unknown=()
    clean_level_word
    msgf_v title clean_res_title "$REPLY"
    for i in "${!CLEAN_CHOSEN[@]}"; do
        id="${CLEAN_CHOSEN[i]}"
        name="$(clean_name "$id")"
        [ "$id" != browsers ] || opened="${CLEAN_R_NOTE[i]-}"
        if [ "${CLEAN_R_STATE[i]-}" = skipped ]; then
            case "${CLEAN_R_WHY[i]-}" in
                unavailable) unavail+=("$name") ;;
                busy) busy+=("$name (${CLEAN_R_NOTE[i]-})") ;;
                unknown) unknown+=("$name") ;;
                *) empty+=("$name") ;;
            esac
            continue
        fi
        detail=""
        if [ "$id" = clipboard ]; then
            [ "${CLEAN_R_STATE[i]-}" != "done" ] || msgf_v detail clean_res_clipboard "${CLEAN_R_NOTE[i]-}"
        elif [ "$id" = rc_config ]; then
            if [ "${CLEAN_R_FILES[i]:-0}" -gt 0 ]; then clean_pkgs_text "${CLEAN_R_FILES[i]}"; detail="$REPLY"; fi
        elif [ "${CLEAN_R_FILES[i]:-0}" -gt 0 ] || [ "${CLEAN_R_BYTES[i]:-0}" -gt 0 ]; then
            clean_amount_text "${CLEAN_R_BYTES[i]:-0}" "${CLEAN_R_FILES[i]:-0}"
            detail="$REPLY"
        fi
        if [ "${CLEAN_R_STATE[i]-}" = failed ]; then
            case "$id" in
                clipboard|journal) left="$(msg clean_res_fail)" ;;
                rc_config)
                    if [ "${CLEAN_R_NOTE[i]-}" = changed ]; then
                        left="$(msg clean_res_changed)"
                    else
                        clean_pkgs_text "${CLEAN_R_FAILED[i]:-0}"; msgf_v left clean_res_left "$REPLY"
                    fi ;;
                *) clean_files_text "${CLEAN_R_FAILED[i]:-0}"; msgf_v left clean_res_left "$REPLY" ;;
            esac
            detail+="${detail:+; }$left"
            bad_body+="${bad_body:+$NL}  $name: $detail"
        else
            ok_body+="${ok_body:+$NL}  $name${detail:+: $detail}"
        fi
    done
    out="$title"
    [ -z "$ok_body" ] || out+="$NL$NL$(msg clean_res_done)$NL$ok_body"
    [ -z "$bad_body" ] || out+="$NL$NL$(msg clean_res_failed)$NL$bad_body"
    clean_notes_text "$opened" empty unavail busy unknown
    notes="$REPLY"
    [ -z "$notes" ] || out+="$NL$NL$notes"
    if [ -z "$ok_body$bad_body" ]; then
        out+="$NL$NL$(msg clean_res_nothing)"
    elif [ "$CLEAN_FREED_FILES" -gt 0 ]; then
        format_size_kb $(( (CLEAN_FREED_BYTES + 1023) / 1024 ))
        size="$REPLY"
        clean_files_text "$CLEAN_FREED_FILES"
        msgf_v txt clean_res_freed "$size" "$REPLY"
        out+="$NL$NL$txt"
    fi
    REPLY="$out"
}

# Shows what the last run did: in green if all went well, in the color of errors
# (C_ERR, yellow) if something failed. $1 = the note about the record (may be
# empty). It returns the status of the box, which clean_run ignores: closing the
# box with Esc or Close changes nothing about the result of the cleaning.
clean_show_result() {
    local status=0
    ! clean_has_failed || status=1
    clean_result_text
    show_removal_result "$status" "$REPLY" "${1-}" big
}

# Runs the confirmed cleaning and shows what it did, with the note about its record.
# Status: 0 = nothing failed, 1 = some entry failed, PRIV_STATUS_DENIED = no administrator
# rights (nothing ran, no record).
clean_run() {
    local status=0 note=""
    if [ "$UI_ENGINE" != "gui" ]; then
        header
        text_wrap "$(msg cleaning)"
        echo
    fi
    clean_run_chosen || status=$?
    if [ "$status" -eq "$PRIV_STATUS_DENIED" ]; then
        show_message "$(msg clean_priv_denied)"
        return "$status"
    fi
    echo
    if clean_has_work; then note="$(record_note_text)"; fi
    clean_show_result "$note"
    ! clean_has_failed
}

# Option 4, "Deep cleanup": the level, then what to clean at it, what that would
# do and its confirmation, then the removal. Going back from the scope returns to
# the level; from the level it leaves, and so does not confirming. It always
# succeeds: main_menu_text takes any other status of an entry as an invalid
# option, and a failed cleaning is already told by clean_show_result.
deep_clean() {
    while true; do
        clean_choose_level || return 0
        clean_pick "$CLEAN_LEVEL" && break
    done
    clean_summary || return 0
    clean_run || true
    return 0
}

# ----------------------------------------------------------------------------
# Main menu
# ----------------------------------------------------------------------------
# The entries of the main menu, in order: MENU_TAGS (the key that opens each),
# MENU_LABELS and MENU_DESCS (one line of explanation each). Built on every
# round, so a language change shows at once.
MENU_TAGS=() MENU_LABELS=() MENU_DESCS=() MENU_ICONS=()

# Terminal emulators that can be opened to go back to the terminal (T), in
# order of preference. "name|words": the words make the emulator run whatever
# follows them as a command (kitty needs none).
TERMINAL_TABLE=(
    "x-terminal-emulator|-e"
    "gnome-terminal|--"
    "konsole|-e"
    "xfce4-terminal|-x"
    "mate-terminal|-x"
    "lxterminal|-e"
    "qterminal|-e"
    "terminator|-x"
    "alacritty|-e"
    "kitty|"
    "xterm|-e"
)
# The emulator that terminal_find chose: its path and its words. Read by
# terminal_relay.
TERMINAL_BIN="" TERMINAL_WORDS=""

# Looks for the emulator: MINTAPP_TERMINAL (a name or a path) when it is set,
# else the first one of the table that is installed. A forced one that the
# table does not list takes "-e". Status 0 = found, 1 = none installed,
# 2 = MINTAPP_TERMINAL cannot be run (no fallback to the table: the person
# asked for that one). "type -P" also returns a file that is not executable,
# hence the -x.
terminal_find() {
    local want="${MINTAPP_TERMINAL:-}" entry found
    TERMINAL_BIN="" TERMINAL_WORDS=""
    if [ -n "$want" ]; then
        [[ "$want" =~ ^[A-Za-z0-9_./+][A-Za-z0-9_./+-]*$ ]] || return 2
        found="$(type -P -- "$want")" && [ -x "$found" ] || return 2
        TERMINAL_BIN="$found" TERMINAL_WORDS="-e"
        for entry in "${TERMINAL_TABLE[@]}"; do
            if [ "${entry%%|*}" = "${found##*/}" ]; then TERMINAL_WORDS="${entry#*|}"; break; fi
        done
        return 0
    fi
    for entry in "${TERMINAL_TABLE[@]}"; do
        found="$(type -P -- "${entry%%|*}")" && [ -x "$found" ] || continue
        TERMINAL_BIN="$found" TERMINAL_WORDS="${entry#*|}"
        return 0
    done
    return 1
}

# Tells why the terminal did not open: on stderr and in an error window.
terminal_relay_fail() {
    print_fit 2 "$1"
    gui_error "$1"
}

# Opens the program in a terminal emulator (the T entry of the windows and the
# start with "interface=terminal" and no terminal). The new copy waits for this
# one to end (--after) before it takes the lock, so after a success (status 0)
# the caller has to end. Status 1 = no terminal was opened: the reason has been
# shown and the program goes on in the windows. The arguments go on to the new
# copy. The emulator gets the file itself or, when this copy cannot run it
# (started as "bash file", mode 644), the same bash and the file: otherwise it
# would stay open with its error while this copy ended.
terminal_relay() {
    local rc=0 pid self bad
    local -a words=() cmd=()
    terminal_find || rc=$?
    case "$rc" in
        1)
            terminal_relay_fail "$(msg terminal_none)"
            return 1
            ;;
        2)
            msgf_v bad terminal_forced_error "$(sanitize_display "${MINTAPP_TERMINAL:-}")"
            terminal_relay_fail "$bad"
            return 1
            ;;
    esac
    if ! install_self; then
        terminal_relay_fail "$(msg terminal_failed)"
        return 1
    fi
    self="$REPLY"
    read -ra words <<< "$TERMINAL_WORDS"
    if [ -x "$self" ]; then cmd=("$self"); else cmd=("${BASH:-bash}" "$self"); fi
    # The emulator must not inherit the lock: it would outlive this copy and the
    # new one could never take it.
    if [ -n "$LOCK_FD" ]; then
        "$TERMINAL_BIN" ${words[@]+"${words[@]}"} "${cmd[@]}" --terminal --after "$$" "$@" \
            </dev/null >/dev/null 2>&1 {LOCK_FD}>&- &
    else
        "$TERMINAL_BIN" ${words[@]+"${words[@]}"} "${cmd[@]}" --terminal --after "$$" "$@" \
            </dev/null >/dev/null 2>&1 &
    fi
    pid=$!
    # Ending with an error within half a second means it did not open (a wrong
    # option, no display). Ending with 0, that it handed the window to a server
    # (gnome-terminal): it did.
    if wait_for_exit "$pid" 5 && ! wait "$pid"; then
        terminal_relay_fail "$(msg terminal_failed)"
        return 1
    fi
    disown "$pid" 2>/dev/null || true
}

# The G entry of the menus is offered when zenity and a graphical session can be
# used and the program is not already showing windows (gui_available). The
# windows offer T instead (terminal_available) when there is somewhere to go:
# the terminal the program was started from or, from a launcher, an emulator
# that can be opened. Both choices are remembered in the configuration
# ("interface"), so that the launcher respects them (FU.6).
gui_available() {
    [ "$UI_ENGINE" != "gui" ] && zenity_usable
}

terminal_available() {
    [ "$UI_ENGINE" = "gui" ] || return 1
    has_terminal || terminal_find
}

# Whether this start has to open a terminal emulator instead of the windows
# (FU.6b): the program was started without a terminal (a launcher), the last
# choice was the terminal ("interface=terminal") and this run asks for nothing
# else: no --gui, no --terminal (the copy that terminal_relay starts has it, so
# it never relays again) and no MINTAPP_UI that names an interface ("auto" or
# an unknown value counts as unset, as in select_interface). The emulator needs
# a graphical session; zenity is not needed.
terminal_start_wanted() {
    has_terminal && return 1
    [ -z "$UI_REQUEST" ] || return 1
    case "${MINTAPP_UI:-auto}" in
        tui|gui|whiptail|text) return 1 ;;
    esac
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || return 1
    [ "$(config_get interface || true)" = "terminal" ]
}

# From here on the dialogs are zenity windows. Fails, changing nothing, if
# zenity cannot be used. The menu loops notice the new engine and start again.
switch_to_gui() {
    zenity_usable || return 1
    UI_ENGINE=gui HAVE_WHIPTAIL=1
    gui_icon_prepare
    config_set interface gui || true
}

# From here on the dialogs are the program's own, in a terminal: this one when
# the program was started from one, else a new emulator, where a new copy
# takes over (terminal_relay) and this one ends. Fails, changing nothing, when
# there is no terminal to go to (terminal_relay has said why).
switch_to_terminal() {
    if ! has_terminal; then
        terminal_relay || return 1
        config_set interface terminal || true
        exit 0
    fi
    UI_ENGINE=tui HAVE_WHIPTAIL=1
    config_set interface terminal || true
}

build_main_menu() {
    MENU_TAGS=(1 2 3 4)
    MENU_LABELS=("$(msg menu_detect)" "$(msg menu_uninstall)" "$(msg menu_advanced)" "$(msg menu_clean)")
    MENU_DESCS=("$(msg menu_detect_desc)" "$(msg menu_uninstall_desc)" "$(msg menu_advanced_desc)" "$(msg menu_clean_desc)")
    if gui_available; then
        MENU_TAGS+=(G) MENU_LABELS+=("$(msg menu_gui)") MENU_DESCS+=("$(msg menu_gui_desc)")
    elif terminal_available; then
        MENU_TAGS+=(T) MENU_LABELS+=("$(msg menu_terminal)") MENU_DESCS+=("$(msg menu_terminal_desc)")
    fi
    MENU_TAGS+=(L 0)
    MENU_LABELS+=("$(msg menu_language)" "$(msg menu_exit)")
    MENU_DESCS+=("$(msg menu_language_desc)" "$(msg menu_exit_desc)")
    menu_icon_list main MENU_TAGS MENU_ICONS
}

# Status line of the main menu (F7.0): the system, the package manager and how
# many catalog applications are installed. Everything in it is data (SYS_PRETTY,
# PM, the count); the title stays the program name only (FP.1).
#
# MENU_APPS is that count, -1 while it has not been taken. Taking it asks the
# manager once per package (about a second on a real system), so it is done
# once and again only after something that can remove packages (run_purge,
# clean_system) or after option 1, which scans the catalog anyway.
MENU_APPS=-1

# Puts in REPLY the number of catalog applications installed (MENU_APPS).
menu_apps_count() {
    local entry key pkgs n=0
    if [ "$MENU_APPS" -lt 0 ]; then
        for entry in "${CATALOG[@]}"; do
            IFS='|' read -r key pkgs <<< "$entry"
            ! package_installed "$pkgs" || n=$(( n + 1 ))
        done
        MENU_APPS="$n"
    fi
    REPLY="$MENU_APPS"
}

# Puts in REPLY the status line, at most $1 columns wide: "system | manager |
# N applications detected". When it does not fit, the name of the system is cut
# first, then the manager goes; the count always stays.
menu_status_text() {
    local width="$1" sys="${SYS_PRETTY:-Linux}" sep=" ${SYM_SEP} " apps room
    if [ "$UNICODE" -eq 0 ]; then ascii_only "$sys"; sys="$REPLY"; fi
    menu_apps_count
    if [ "$REPLY" -eq 1 ]; then
        msgf_v apps menu_status_apps_1
    else
        msgf_v apps menu_status_apps_n "$REPLY"
    fi
    REPLY="${sys}${sep}${PM}${sep}${apps}"
    [ "${#REPLY}" -gt "$width" ] || return 0
    room=$(( width - 2 * ${#sep} - ${#PM} - ${#apps} ))
    if [ "$room" -ge 12 ]; then
        wt_fit_label "$room" "$sys"
        REPLY="${REPLY}${sep}${PM}${sep}${apps}"
        return 0
    fi
    room=$(( width - ${#sep} - ${#apps} ))
    if [ "$room" -ge 8 ]; then
        wt_fit_label "$room" "$sys"
        REPLY="${REPLY}${sep}${apps}"
        return 0
    fi
    wt_fit_label "$width" "$apps"
}

# Puts in REPLY the columns the status line may use in the dialog of the active
# engine (the text area of its box). gui wraps its own text.
menu_status_width() {
    case "$UI_ENGINE" in
        gui) REPLY=200 ;;
        tui)
            read_terminal_size
            REPLY=$(( TERM_COLS - 6 ))
            [ "$REPLY" -le "$TUI_MAX_TEXT" ] || REPLY="$TUI_MAX_TEXT"
            ;;
        *)
            wt_box_size normal
            REPLY=$(( WT_BOX_W - 6 ))
            ;;
    esac
    [ "$REPLY" -ge 20 ] || REPLY=20
}

# Puts in REPLY the text above the list of the main menu in a dialog engine:
# the status line and, where the engine does not list its keys itself (tui does,
# on its last row), the instruction to choose.
menu_prompt_text() {
    local status
    menu_status_width
    menu_status_text "$REPLY"
    status="$REPLY"
    case "$UI_ENGINE" in
        tui) REPLY="$status" ;;
        gui) REPLY="${status}\n\n$(msg menu_prompt_gui)" ;;
        *) REPLY="${status}\n\n$(msg menu_whiptail)" ;;
    esac
}

# Puts in REPLY the item text of a dialog menu entry: $1 = label, $2 =
# description, $3 = usable columns, $4 = its emoji (only the windows have one:
# menu_icon_list). The tui engine takes the parts apart (the emoji and a record
# separator, the label, a unit separator, the description) and lays them out by
# the height it has; whiptail has one line per entry, so the description follows
# the label and is the part that gets cut: when fewer than 8 columns are left for
# it, the label goes alone.
menu_item_text() {
    local label="$1" desc="$2" width="$3" icon="${4:-}" room
    if engine_fits_itself; then
        REPLY="${icon:+$icon$'\036'}${label}${desc:+$'\037'$desc}"
        return 0
    fi
    room=$(( width - ${#label} - 3 ))
    if [ -z "$desc" ] || [ "$room" -lt 8 ]; then
        wt_fit_label "$width" "$label"
        return 0
    fi
    wt_fit_label "$room" "$desc"
    REPLY="$label - $REPLY"
}

# Fills the array named $3 with the emoji of the entries of the menu $1 (main,
# clean, level or scope) whose tags are in the array named $2: one per entry,
# empty when the entry has none or when the dialogs are not windows that can draw
# them in color (gui_emoji). The terminal engines never get one. All the emoji of
# the program are here.
menu_icon_list() {
    local menu="$1" i icon
    local -n _mi_tags="$2" _mi_icons="$3"
    _mi_icons=()
    for (( i = 0; i < ${#_mi_tags[@]}; i++ )); do
        icon=""
        if [ "$UI_ENGINE" = "gui" ] && gui_emoji; then
            case "$menu:${_mi_tags[i]}" in
                main:1) icon="🔍" ;;
                main:2) icon="🗑️" ;;
                main:3) icon="🧭" ;;
                main:4) icon="🧹" ;;
                main:T) icon="💻" ;;
                main:L) icon="🌐" ;;
                main:0) icon="🚪" ;;
                clean:1) icon="📦" ;;
                clean:2) icon="🧼" ;;
                level:S) icon="🍃" ;;
                level:C) icon="🧽" ;;
                scope:1) icon="✅" ;;
                scope:2) icon="📂" ;;
                scope:3) icon="📄" ;;
            esac
        fi
        _mi_icons+=("$icon")
    done
}

# A menu of a few choices. $1 = prompt (with \n sequences); $2, $3 and $4 = the
# names of the arrays of tags, labels and descriptions (one value per entry); $5 =
# the name of the array of emoji, if it has one (menu_icon_list). Puts the tag
# chosen in REPLY. Status 0 = chosen, 1 = went back (the Back button,
# Esc, "0" in the plain text or the end of the input). In plain text the user types
# the tag, in any case; anything else is told as not valid and asked again.
choose_menu() {
    local prompt="$1" i width opt count line in_text desc
    local -a items=() _cm_none=()
    local -n _cm_tags="$2" _cm_labels="$3" _cm_descs="$4" _cm_icons="${5:-_cm_none}"
    REPLY=""
    count="${#_cm_tags[@]}"
    if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
        wt_list_prepare "$prompt" "$count"
        wt_label_width "$WT_BOX_W" "$count"
        width="$REPLY"
        # whiptail: a description that does not fit its row goes whole into the text.
        in_text=0
        if ! engine_fits_itself && wt_menu_descs_in_text "$prompt" "$count" "$width" _cm_labels _cm_descs; then in_text=1; fi
        for (( i = 0; i < count; i++ )); do
            desc="${_cm_descs[i]}"; [ "$in_text" -eq 0 ] || desc=""
            menu_item_text "${_cm_labels[i]}" "$desc" "$width" "${_cm_icons[i]:-}"
            items+=("${_cm_tags[i]}" "$REPLY")
        done
        # Esc is the Back button: the own dialogs name it in their key bar.
        TUI_HOTKEYS="esc=1"
        opt=$(wt --ok-button "$(msg ok)" --cancel-button "$(msg back)" \
            --menu "$WT_TEXT" "$WT_BOX_H" "$WT_BOX_W" "$WT_LIST_ROWS" \
            "${items[@]}" 3>&1 1>&2 2>&3) || { TUI_HOTKEYS=""; return 1; }
        TUI_HOTKEYS=""
        REPLY="$opt"
        return 0
    fi
    while true; do
        header
        text_print "$prompt"
        echo
        for (( i = 0; i < count; i++ )); do
            text_option "${_cm_tags[i]}" "${_cm_labels[i]}"
            while IFS= read -r line; do
                printf '     %b%s%b\n' "$C_DIM" "$line" "$C_RESET"
            done < <(printf '%s\n' "${_cm_descs[i]}" | wrap_even $(( TEXT_W - 5 )))
        done
        text_option 0 "$(msg back)"
        section_rule
        read -rp "$(text_prompt "$(msg menu_prompt)")" opt || return 1
        [ "$opt" != "0" ] || return 1
        for (( i = 0; i < count; i++ )); do
            if [ "${opt^^}" = "${_cm_tags[i]^^}" ]; then REPLY="${_cm_tags[i]}"; return 0; fi
        done
        echo -e "${C_ERR}$(msg invalid)${C_RESET}"
        sleep 1
    done
}

# Opens the entry whose tag is $1 (any case, but not "0": leaving is the
# caller's). Fails only if the menu has no such entry, so a key that is not an
# option does nothing; what the entry itself returns does not count (going back
# from the list of option 2 returns 1, and that is not an invalid option).
run_menu_entry() {
    local tag="${1^^}" t found=0
    for t in "${MENU_TAGS[@]}"; do [ "$t" != "$tag" ] || found=1; done
    [ "$found" -eq 1 ] || return 1
    case "$tag" in
        1) detect_programs; MENU_APPS="${#DETECTED_KEYS[@]}" ;;
        2) uninstall_programs || true ;;
        3) find_other_apps || true ;;
        4) clean_menu || true ;;
        G) switch_to_gui || true ;;
        T) switch_to_terminal || true ;;
        L) toggle_language ;;
    esac
    return 0
}

main_menu_whiptail() {
    local -a items
    local opt wt_status i width count engine="$UI_ENGINE"
    while true; do
        build_main_menu
        count="${#MENU_TAGS[@]}"
        menu_prompt_text
        wt_list_prepare "$REPLY" "$count"
        wt_label_width "$WT_BOX_W" "$count"
        width="$REPLY"
        items=()
        for (( i = 0; i < count; i++ )); do
            menu_item_text "${MENU_LABELS[i]}" "${MENU_DESCS[i]}" "$width" "${MENU_ICONS[i]:-}"
            items+=("${MENU_TAGS[i]}" "$REPLY")
        done
        TUI_HOTKEYS="esc=1"
        opt=$(wt \
            --ok-button "$(msg ok)" --cancel-button "$(msg menu_exit)" \
            --menu "$WT_TEXT" "$WT_BOX_H" "$WT_BOX_W" "$WT_LIST_ROWS" \
            "${items[@]}" \
            3>&1 1>&2 2>&3)
        wt_status=$?
        TUI_HOTKEYS=""

        if [ "$wt_status" -ne 0 ]; then
            # 254: zenity itself could not run (a closed window ends with 1).
            if [ "$wt_status" -eq 254 ] && [ "$UI_ENGINE" = "gui" ]; then
                print_fit 2 "$(msg gui_failed)"
                exit 1
            fi
            [ "$UI_ENGINE" = "gui" ] || clear
            exit 0
        fi

        if [ "$opt" = "0" ]; then
            [ "$UI_ENGINE" = "gui" ] || clear
            msgln exit
            exit 0
        fi
        run_menu_entry "$opt" || true
        # G or T changed the engine: main_menu starts this menu again with it.
        [ "$UI_ENGINE" = "$engine" ] || return 0
    done
}

# Plain-text menu layout by the height of the terminal (TEXT_MENU_LEVEL): 3 =
# a blank row between entries, 2 = the description under each label, 1 = labels
# only. The first that leaves the prompt on screen wins. The header takes 4
# rows, the closing rule and the prompt 2 more. The status line and its blank
# row (2 rows, TEXT_MENU_STATUS) are shown only when the entries fit with them.
TEXT_MENU_LEVEL=1
TEXT_MENU_STATUS=0
text_menu_level() {
    local i n="${#MENU_TAGS[@]}" total=0 lines fixed
    set_text_width
    for (( i = 0; i < n; i++ )); do
        [ -z "${MENU_DESCS[i]}" ] && continue
        lines="$(printf '%s\n' "${MENU_DESCS[i]}" | wrap_even $(( TEXT_W - 5 )) | wc -l)"
        total=$(( total + lines ))
    done
    TEXT_MENU_STATUS=0
    [ $(( 8 + n )) -lt "$TERM_LINES" ] && TEXT_MENU_STATUS=1
    fixed=$(( 6 + 2 * TEXT_MENU_STATUS ))
    TEXT_MENU_LEVEL=1
    if [ $(( fixed + n + total + n - 1 )) -lt "$TERM_LINES" ]; then
        TEXT_MENU_LEVEL=3
    elif [ $(( fixed + n + total )) -lt "$TERM_LINES" ]; then
        TEXT_MENU_LEVEL=2
    fi
}

main_menu_text() {
    local opt i line engine="$UI_ENGINE"
    while true; do
        build_main_menu
        text_menu_level
        header
        if [ "$TEXT_MENU_STATUS" -eq 1 ]; then
            menu_status_text $(( TEXT_W - 2 ))
            printf ' %b%s%b\n\n' "$C_OK" "$REPLY" "$C_RESET"
        fi
        for (( i = 0; i < ${#MENU_TAGS[@]}; i++ )); do
            text_option "${MENU_TAGS[i]}" "${MENU_LABELS[i]}"
            if [ "$TEXT_MENU_LEVEL" -ge 2 ]; then
                while IFS= read -r line; do
                    printf '     %b%s%b\n' "$C_DIM" "$line" "$C_RESET"
                done < <(printf '%s\n' "${MENU_DESCS[i]}" | wrap_even $(( TEXT_W - 5 )))
                [ "$TEXT_MENU_LEVEL" -lt 3 ] || [ "$i" -eq $(( ${#MENU_TAGS[@]} - 1 )) ] || echo
            fi
        done
        section_rule
        read -rp "$(text_prompt "$(msg menu_prompt)")" opt || { echo; msgln exit; exit 0; }

        if [ "$opt" = "0" ]; then
            msgln exit
            exit 0
        fi
        if ! run_menu_entry "$opt"; then
            echo -e "${C_ERR}$(msg invalid)${C_RESET}"
            sleep 1
        fi
        [ "$UI_ENGINE" = "$engine" ] || return 0
    done
}

# Both menus end the program themselves; they return only when the engine
# changed (G, T), and then the loop picks the menu of the new one.
main_menu() {
    while true; do
        if [ "$HAVE_WHIPTAIL" -eq 1 ]; then
            main_menu_whiptail
        else
            main_menu_text
        fi
    done
}

# ----------------------------------------------------------------------------
# Process safety: single instance, clean exit, interrupted removals
# ----------------------------------------------------------------------------

# Status 0 while the process $1 exists. One that has ended but whose parent has
# not collected it yet (a zombie) counts as gone: it holds nothing any more.
# /proc says it for any user's process; kill -0 would answer "no" to the ones
# of another user. Without /proc, kill -0 is all there is.
process_alive() {
    local key state rest
    if [ -r "/proc/$1/status" ]; then
        while IFS=$': \t' read -r key state rest; do
            if [ "$key" = State ]; then [[ "$state" != [ZX] ]]; return; fi
        done 2>/dev/null < "/proc/$1/status"
    fi
    kill -0 "$1" 2>/dev/null
}

# Waits until the process $1 is gone, for $2 tenths of a second at most (default
# 100: ten seconds). Status 0 = it is gone, 1 = it is still there.
wait_for_exit() {
    local n
    for (( n = 0; n < ${2:-100}; n++ )); do
        process_alive "$1" || return 0
        sleep 0.1
    done
    ! process_alive "$1"
}

# Takes the single-instance lock: two copies at once would race on the same
# package operations. The lock is an open file descriptor, so the kernel
# releases it when the program ends, however it ends; the package manager
# inherits it, so a second copy also waits while a removal is still running.
# The lock file lives in the per-user runtime directory (gone at logout, no
# trace on disk) or, without one, in the private state directory. Best effort:
# if it cannot be created (or flock is missing) the program runs unlocked.
# Fails (status 1) only when another instance holds the lock.
acquire_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    local lock
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
        lock="$XDG_RUNTIME_DIR/mintapp-remover.lock"
    else
        ensure_state_dir || return 0
        lock="$(state_dir)/.lock"
    fi
    # The redirection of a bare "exec" would be permanent, so the group is what
    # silences the error message; the descriptor itself stays open.
    { exec {LOCK_FD}>>"$lock"; } 2>/dev/null || return 0
    flock -n "$LOCK_FD"
}

# Removes temporary files of a write that was killed without a chance to clean
# up (SIGKILL, power loss), in the state and configuration directories. Only
# files older than an hour are touched.
sweep_stale_temp_files() {
    local dir
    for dir in "$(state_dir)" "$(config_dir || true)"; do
        [ -n "$dir" ] && [ -d "$dir" ] || continue
        find "$dir" -maxdepth 1 -type f -name '.tmp.*' -mmin +60 -delete 2>/dev/null || true
    done
}

# Closes the progress window and removes the private folder of the windows (the
# password helper, the icon and the manager's output), if they exist.
gui_cleanup() {
    if [ -n "$GUI_PROGRESS_PID" ]; then
        kill "$GUI_PROGRESS_PID" 2>/dev/null || true
        GUI_PROGRESS_PID=""
    fi
    case "$GUI_WORK_DIR" in
        */mintapp-gui.*) rm -rf -- "$GUI_WORK_DIR" 2>/dev/null || true ;;
    esac
    GUI_WORK_DIR="" ASKPASS_HELPER="" ASKPASS_LANG="" ICON_FILE="" GUI_ICON=""
}

# The terminal settings the program started with (stty -g, taken by
# install_traps; empty without a terminal). "stty sane" alone is not a way back:
# it turns brkint and imaxbel on and iutf8 off, whatever the terminal had.
EXIT_STTY=""

# Runs on every exit (normal, error or signal). If a removal was running it
# leaves a record saying so, and after a signal it puts the terminal back as
# the program found it (a killed dialog can leave echo or colours switched
# off); only without those settings, or if they cannot be applied, "stty sane".
# The signals are ignored here, not reset to their default action: a second
# SIGHUP (the subshells of the progress window resend it to the whole group)
# would otherwise kill the program before the record is written (D2).
on_exit() {
    local status=$?
    trap '' INT TERM HUP
    trap - EXIT
    gui_cleanup
    clean_open_done
    if [ -n "$ACTIVE_RECORD" ]; then
        if [ "$ACTIVE_CLEAN" -eq 1 ]; then
            write_clean_record "$ACTIVE_RECORD" "interrupted" || true
        elif [ "$ACTIVE_STORE" -eq 1 ]; then
            write_store_record "$ACTIVE_RECORD" "interrupted" "$ACTIVE_PLAN" || true
        else
            write_removal_record "$ACTIVE_RECORD" "interrupted" "$ACTIVE_PLAN" "$ACTIVE_REQUEST" || true
        fi
        ACTIVE_RECORD="" ACTIVE_STORE=0 ACTIVE_CLEAN=0
    fi
    if [ "$status" -gt 128 ]; then
        if [ -t 1 ]; then printf '\033[?7h\033[?25h%b\n' "$C_RESET"; fi
        if [ -t 0 ]; then
            if [ -n "$EXIT_STTY" ]; then stty "$EXIT_STTY" 2>/dev/null || stty sane 2>/dev/null || true
            else stty sane 2>/dev/null || true; fi
        fi
    fi
    return 0
}

install_traps() {
    if [ -t 0 ]; then EXIT_STTY="$(stty -g 2>/dev/null)" || EXIT_STTY=""; fi
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
}

# ----------------------------------------------------------------------------
# Installation (F5.1). "install" copies the program into the user's own
# folders and "uninstall" takes it away again; neither needs administrator
# rights:
#   ~/.local/bin/mintapp-remover                                      the command
#   $XDG_DATA_HOME/applications/mintapp-remover.desktop               the launcher
#   $XDG_DATA_HOME/icons/hicolor/NxN/apps/mintapp-remover.png         the icon
# XDG_DATA_HOME defaults to ~/.local/share; as in config_dir, a relative one is
# ignored. Both can be run again: what is already right is left alone, and
# every file is written atomically (atomic_write).
# ----------------------------------------------------------------------------
INSTALL_NAME="mintapp-remover"
# hicolor sizes, largest first. An icon bigger than the first is filed under it
# (hicolor has no larger folder) and toolkits scale it down.
INSTALL_ICON_SIZES=(512 256 192 128 96 72 64 48 36 32 24 22 16)
INSTALL_BIN=""
INSTALL_DESKTOP=""
INSTALL_ICON_ROOT=""

# The folder of user data, without a trailing slash. Fails without a usable
# HOME.
install_data_dir() {
    local base="${XDG_DATA_HOME:-}"
    if [[ "$base" != /* ]]; then
        base="${HOME:-}"
        [[ "$base" == /* ]] || return 1
        base="${base%/}/.local/share"
    fi
    printf '%s' "${base%/}"
}

# Sets INSTALL_BIN, INSTALL_DESKTOP and INSTALL_ICON_ROOT. Fails (and sets
# nothing) without a usable HOME.
install_paths() {
    local data home="${HOME:-}"
    [[ "$home" == /* ]] || return 1
    data="$(install_data_dir)" || return 1
    INSTALL_BIN="${home%/}/.local/bin/$INSTALL_NAME"
    INSTALL_DESKTOP="$data/applications/$INSTALL_NAME.desktop"
    INSTALL_ICON_ROOT="$data/icons/hicolor"
}

# This script, with links resolved, in REPLY. Fails if it is not a readable
# regular file (a script piped into bash has no file to copy).
install_self() {
    REPLY="$(readlink -f -- "${BASH_SOURCE[0]:-}" 2>/dev/null)" || return 1
    [ -f "$REPLY" ] && [ -r "$REPLY" ]
}

# ----------------------------------------------------------------------------
# The icon of the program (F6). It travels inside this file, after the last
# line of code, as "#@" comment lines: a PNG in base64 that is never run, so
# the one script carries its own icon. Beside the script there may also be
# ../assets/icon5.png, the file it was made from: it is used only when the
# embedded copy is missing or damaged.
# ----------------------------------------------------------------------------

# Decodes the "#@" lines of the file $1 into the file $2 and checks the result:
# a PNG that ends with the IEND chunk (the last 8 bytes of a complete file are
# "IEND" and its CRC) and is a square of a size hicolor has. Fails otherwise,
# leaving no file.
embedded_icon_write() {
    local dims width height end
    command -v base64 >/dev/null 2>&1 || return 1
    if sed -n 's/^#@//p' "$1" 2>/dev/null | base64 -d > "$2" 2>/dev/null \
        && end="$(tail -c 8 "$2" | od -An -v -tx1 | tr -d ' \n')" \
        && [ "$end" = "49454e44ae426082" ] \
        && dims="$(png_dimensions "$2")"; then
        read -r width height <<< "$dims"
        if install_icon_size "$width" "$height" >/dev/null; then return 0; fi
    fi
    rm -f -- "$2"
    return 1
}

# The file ../assets/icon5.png beside the script, in REPLY (a link to the script
# is followed). Fails if it is not a readable file.
program_icon_asset() {
    local dir
    install_self || return 1
    dir="${REPLY%/*}"
    REPLY="${dir%/*}/assets/$ICON_ASSET"
    [ -f "$REPLY" ] && [ -r "$REPLY" ]
}

# The icon of the program as a PNG file, in REPLY: the embedded copy, written
# once into the private folder of the run (gui_work_dir; gui_cleanup removes
# it), else the file beside the script. Fails when there is neither.
program_icon() {
    local self
    install_self || return 1
    self="$REPLY"
    if [ -n "$ICON_FILE" ] && [ -f "$ICON_FILE" ]; then
        REPLY="$ICON_FILE"
        return 0
    fi
    ICON_FILE=""
    if gui_work_dir && embedded_icon_write "$self" "$GUI_WORK_DIR/icon.png"; then
        ICON_FILE="$GUI_WORK_DIR/icon.png"
        REPLY="$ICON_FILE"
        return 0
    fi
    program_icon_asset
}

# The icon to install, in REPLY (program_icon). Fails if there is none.
install_icon_source() {
    program_icon
}

# Prints "WIDTH HEIGHT" of the PNG file $1, read from its header (the 8-byte
# signature, then the IHDR chunk). Fails if it is not a PNG.
png_dimensions() {
    local -a b
    local head
    head="$(od -An -v -tu1 -N24 -- "$1" 2>/dev/null | tr -s ' \n' '  ')" || return 1
    read -r -a b <<< "$head"
    [ "${#b[@]}" -eq 24 ] || return 1
    [ "${b[*]:0:8}" = "137 80 78 71 13 10 26 10" ] || return 1
    [ "${b[12]} ${b[13]} ${b[14]} ${b[15]}" = "73 72 68 82" ] || return 1
    printf '%s %s' \
        "$(( (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19] ))" \
        "$(( (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23] ))"
}

# Prints the hicolor size an icon of $1 by $2 pixels goes under: the largest
# of INSTALL_ICON_SIZES that fits in it. Fails if it is not square or is
# smaller than the smallest size.
install_icon_size() {
    local size
    [ "$1" -eq "$2" ] 2>/dev/null || return 1
    for size in "${INSTALL_ICON_SIZES[@]}"; do
        if [ "$1" -ge "$size" ]; then printf '%s' "$size"; return 0; fi
    done
    return 1
}

# The installed copies of the icon, one path per line (any size).
install_icon_files() {
    local file
    for file in "$INSTALL_ICON_ROOT"/*/apps/"$INSTALL_NAME.png"; do
        if [ -e "$file" ] || [ -L "$file" ]; then printf '%s\n' "$file"; fi
    done
}

# Puts the command line of the launcher in REPLY, as the Exec key of a desktop
# entry needs it: always in double quotes, with ", `, $ and \ escaped (the
# backslash twice over, because the string escape of the file comes first) and
# % doubled, which the specification reserves for field codes. Fails if the
# path has a control character: a value cannot hold it.
desktop_exec_quote() {
    local path="$1"
    [[ "$path" != *[[:cntrl:]]* ]] || return 1
    path="${path//\\/\\\\\\\\}"
    path="${path//\"/\\\\\"}"
    path="${path//\$/\\\\\$}"
    path="${path//\`/\\\\\`}"
    path="${path//%/%%}"
    REPLY="\"$path\""
}

# Prints the launcher. $1 = the Exec value (desktop_exec_quote), $2 = the path
# of the command (TryExec: the menu hides the entry when it is gone), $3 = the
# Icon value, $4 = true|false (Terminal). StartupWMClass is the class of the
# program's windows (GUI_CLASS), the one a task bar uses to pick the icon.
install_desktop_text() {
    printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        'Version=1.0' \
        'Name=MintApp Remover' \
        'GenericName=Application uninstaller' \
        'GenericName[es]=Desinstalador de aplicaciones' \
        'Comment=Remove preinstalled applications safely and clean up the system' \
        'Comment[es]=Desinstala aplicaciones preinstaladas con seguridad y limpia el sistema' \
        "Exec=$1" \
        "TryExec=$2" \
        "Icon=$3" \
        "Terminal=$4" \
        'Categories=System;' \
        'Keywords=uninstall;remove;clean;applications;apt;' \
        'Keywords[es]=desinstalar;quitar;limpiar;aplicaciones;apt;' \
        "StartupWMClass=$INSTALL_NAME"
}

# Writes the file $1 with mode $2 and the content of the file $3, unless it is
# already like that. REPLY: new, updated or current.
install_put_file() {
    local existed=0
    if [ -e "$1" ] || [ -L "$1" ]; then existed=1; fi
    if [ -f "$1" ] && cmp -s -- "$3" "$1" && [ "$(stat -L -c %a -- "$1" 2>/dev/null)" = "$2" ]; then
        REPLY=current
        return 0
    fi
    atomic_write "$1" "$2" < "$3" || return 1
    if [ "$existed" -eq 1 ]; then REPLY=updated; else REPLY=new; fi
}

# The same with the text $3 (a newline is added) instead of a file.
install_put_text() {
    local existed=0 have
    if [ -e "$1" ] || [ -L "$1" ]; then existed=1; fi
    if [ -f "$1" ]; then
        have="$(cat -- "$1" 2>/dev/null; printf x)"
        if [ "$have" = "$3"$'\nx' ] && [ "$(stat -L -c %a -- "$1" 2>/dev/null)" = "$2" ]; then
            REPLY=current
            return 0
        fi
    fi
    printf '%s\n' "$3" | atomic_write "$1" "$2" || return 1
    if [ "$existed" -eq 1 ]; then REPLY=updated; else REPLY=new; fi
}

# Prints the text of the state $1 of a file: new, updated, current or kept.
install_state_text() {
    case "$1" in
        new) msg install_state_new ;;
        updated) msg install_state_updated ;;
        current) msg install_state_current ;;
        kept) msg install_state_kept ;;
    esac
}

# Prints one line of the report: label $1 (a message key already turned into
# text), path $2 and state $3, with the labels padded to the same width. Into a
# pipe or a file it is always that one line. On a terminal, a line wider than
# the screen is laid out so the terminal never cuts it inside the state; the
# path itself is never touched: the state goes under the path, and if the path
# does not fit beside the label either, the label goes alone and the path
# under it, indented 4, with the state behind it if that fits (else under it).
INSTALL_LABEL_WIDTH=0
install_report_line() {
    local label="$1" path="$2" state="$3" line
    if [ ! -t 1 ]; then
        printf '  %-*s  %s  (%s)\n' "$INSTALL_LABEL_WIDTH" "$label" "$path" "$state"
        return 0
    fi
    set_text_width <&1
    printf -v line '  %-*s  %s  (%s)' "$INSTALL_LABEL_WIDTH" "$label" "$path" "$state"
    if [ "${#line}" -le "$TEXT_W" ]; then
        printf '%s\n' "$line"
        return 0
    fi
    printf -v line '  %-*s  %s' "$INSTALL_LABEL_WIDTH" "$label" "$path"
    if [ "${#line}" -le "$TEXT_W" ]; then
        printf '%s\n' "$line"
        printf '%*s(%s)\n' $(( ${#line} - ${#path} )) '' "$state"
        return 0
    fi
    printf '  %s\n' "$label"
    printf -v line '    %s  (%s)' "$path" "$state"
    if [ "${#line}" -le "$TEXT_W" ]; then
        printf '%s\n' "$line"
    else
        printf '    %s\n    (%s)\n' "$path" "$state"
    fi
}

# Sets INSTALL_LABEL_WIDTH to that of the longest label in the current language:
# of the three files, and with "data" also of the two folders of data.
install_label_width() {
    local label
    INSTALL_LABEL_WIDTH=0
    for label in "$(msg install_label_bin)" "$(msg install_label_launcher)" "$(msg install_label_icon)"; do
        if [ "${#label}" -gt "$INSTALL_LABEL_WIDTH" ]; then INSTALL_LABEL_WIDTH="${#label}"; fi
    done
    [ "${1:-}" = data ] || return 0
    for label in "$(msg install_label_config)" "$(msg install_label_records)"; do
        if [ "${#label}" -gt "$INSTALL_LABEL_WIDTH" ]; then INSTALL_LABEL_WIDTH="${#label}"; fi
    done
}

# Removes the empty folders from $1 upwards, never HOME itself. A folder that is
# not under HOME is only pruned below the folder $2 (a base such as
# XDG_DATA_HOME, which stays); without $2 it is left alone. rmdir only takes
# away an empty folder, so what anything else keeps there stays.
install_prune_empty() {
    local dir="$1" limit="${HOME%/}"
    case "$dir/" in
        "$limit"/*) ;;
        *)
            limit="${2:-}"
            [ -n "$limit" ] || return 0
            case "$dir/" in "$limit"/*) ;; *) return 0 ;; esac
            ;;
    esac
    while [ -n "$dir" ] && [ "$dir" != "$limit" ] && [ "$dir" != "/" ]; do
        rmdir -- "$dir" 2>/dev/null || break
        dir="${dir%/*}"
    done
}

# Removes the empty folders where the command, the launcher and the icons go,
# whether or not there was a file in them.
install_prune_places() {
    local size data
    data="$(install_data_dir)" || data=""
    install_prune_empty "${INSTALL_BIN%/*}"
    install_prune_empty "${INSTALL_DESKTOP%/*}" "$data"
    for size in "${INSTALL_ICON_SIZES[@]}"; do
        install_prune_empty "$INSTALL_ICON_ROOT/${size}x${size}/apps" "$data"
    done
}

# "install": puts the command, the launcher and the icon in place. Status 0 when
# everything is in place, 1 if something could not be written.
cmd_install() {
    local text self icon_src dims width height size icon_dest state icon_name="applications-system"
    local terminal=false exec_value bin_dir old
    if [ "$EUID" -eq 0 ]; then
        print_fit 2 "$(msg root_error)"
        return 1
    fi
    if ! install_paths; then
        print_fit 2 "$(msg install_err_home)"
        return 1
    fi
    if ! install_self; then
        print_fit 2 "$(msg install_err_source)"
        return 1
    fi
    self="$REPLY"
    install_label_width
    msgf_v text install_intro "$MINTAPP_VERSION"
    print_fit 1 "$text"

    # The command.
    if ! install_put_file "$INSTALL_BIN" 755 "$self"; then
        msgf_v text install_err_write "$INSTALL_BIN"
        printf '%s\n' "$text" >&2
        return 1
    fi
    state="$REPLY"
    install_report_line "$(msg install_label_bin)" "$INSTALL_BIN" "$(install_state_text "$state")"

    # The icon: the one embedded in the script (else the file beside it) when it
    # is a square PNG of a size hicolor has; an icon installed before is kept
    # when there is none.
    icon_dest=""
    if install_icon_source; then
        icon_src="$REPLY"
        if dims="$(png_dimensions "$icon_src")"; then
            read -r width height <<< "$dims"
            if size="$(install_icon_size "$width" "$height")"; then
                icon_dest="$INSTALL_ICON_ROOT/${size}x${size}/apps/$INSTALL_NAME.png"
            fi
        fi
    fi
    if [ -n "$icon_dest" ]; then
        if ! install_put_file "$icon_dest" 644 "$icon_src"; then
            gui_cleanup
            msgf_v text install_err_write "$icon_dest"
            printf '%s\n' "$text" >&2
            return 1
        fi
        state="$REPLY"
        # An older copy of another size would show the old picture.
        while IFS= read -r old; do
            [ "$old" = "$icon_dest" ] || rm -f -- "$old"
        done < <(install_icon_files)
        install_report_line "$(msg install_label_icon)" "$icon_dest" "$(install_state_text "$state")"
        icon_name="$INSTALL_NAME"
    elif old="$(install_icon_files | head -n 1)" && [ -n "$old" ]; then
        install_report_line "$(msg install_label_icon)" "$old" "$(install_state_text kept)"
        icon_name="$INSTALL_NAME"
    else
        print_fit 2 "$(msg install_icon_none)"
    fi
    gui_cleanup     # the copy of the embedded icon is no longer needed

    # The launcher. Without zenity there are no windows to open when the menu
    # starts the program without a terminal, so it asks the desktop for one.
    if command -v zenity >/dev/null 2>&1; then
        terminal=false
    else
        terminal=true
        print_fit 2 "$(msg install_no_zenity)"
    fi
    if ! desktop_exec_quote "$INSTALL_BIN"; then
        msgf_v text install_err_write "$INSTALL_DESKTOP"
        printf '%s\n' "$text" >&2
        return 1
    fi
    exec_value="$REPLY"
    if ! install_put_text "$INSTALL_DESKTOP" 644 \
        "$(install_desktop_text "$exec_value" "$INSTALL_BIN" "$icon_name" "$terminal")"; then
        msgf_v text install_err_write "$INSTALL_DESKTOP"
        printf '%s\n' "$text" >&2
        return 1
    fi
    state="$REPLY"
    install_report_line "$(msg install_label_launcher)" "$INSTALL_DESKTOP" "$(install_state_text "$state")"

    # The command is found by name only if its folder is in PATH.
    bin_dir="${INSTALL_BIN%/*}"
    printf '\n'
    case ":${PATH:-}:" in
        *":$bin_dir:"*)
            print_fit 1 "$(msg install_done)"
            printf '  %s\n' "$INSTALL_NAME"
            ;;
        *)
            msgf_v text install_path_warn "$bin_dir"
            print_fit_path 1 "$text" "$bin_dir"
            # Written as the person must type it: $HOME and $PATH stay as they are.
            # shellcheck disable=SC2016
            printf '  export PATH="$HOME/.local/bin:$PATH"\n\n'
            print_fit 1 "$(msg install_done)"
            printf '  %s\n' "$INSTALL_BIN"
            ;;
    esac
}

# Succeeds if another copy of the program holds the instance lock (see
# acquire_lock), which a removal in progress passes on to the manager. It only
# looks: no lock file is made.
uninstall_busy() {
    local file fd
    command -v flock >/dev/null 2>&1 || return 1
    for file in "${XDG_RUNTIME_DIR:-/nonexistent}/mintapp-remover.lock" "$(state_dir)/.lock"; do
        [ -f "$file" ] || continue
        { exec {fd}<"$file"; } 2>/dev/null || continue
        if ! flock -n "$fd"; then
            exec {fd}<&-
            return 0
        fi
        exec {fd}<&-
    done
    return 1
}

# Removes, whole, the data folder $1. It must be one of the program's own: a
# path that does not end in /mintapp-remover is refused. A link is removed, not
# what it points to.
uninstall_rm_dir() {
    [[ "$1" == /*/mintapp-remover || "$1" == /mintapp-remover ]] || return 1
    rm -rf -- "$1" 2>/dev/null && [ ! -e "$1" ] && [ ! -L "$1" ]
}

# Removes the temporary files of an interrupted write and the lock file from
# the data folder $1, which stays.
uninstall_clean_temp() {
    find "$1" -maxdepth 1 -type f \( -name '.tmp.*' -o -name '.lock' \) -delete 2>/dev/null || true
}

# Prints the error for something that could not be removed.
uninstall_fail() {
    local text
    msgf_v text install_err_remove "$1"
    printf '%s\n' "$text" >&2
}

# Asks what to do with the data; the answer goes to REPLY: records (the
# default), all, none or cancel (q, or the end of the input).
uninstall_ask() {
    local answer
    msgln uninstall_ask_intro
    print_fit 1 "$(printf '  %s\n  %s\n  %s' "$(msg uninstall_choice_records)" "$(msg uninstall_choice_all)" "$(msg uninstall_choice_none)")"
    while true; do
        if ! read -r -p "$(msg uninstall_ask_prompt) " answer; then
            printf '\n'
            REPLY=cancel
            return 0
        fi
        case "${answer,,}" in
            ""|1) REPLY=records; return 0 ;;
            2) REPLY=all; return 0 ;;
            3) REPLY=none; return 0 ;;
            q) REPLY=cancel; return 0 ;;
        esac
    done
}

# "uninstall": takes away what "install" put in place, and decides about the
# data the program made ($1: records = delete the settings and keep the
# records, all = keep both, none = delete both; empty = ask on a terminal, and
# records without one). Status 0 when it is done, 1 if something could not be
# removed or the person cancelled.
cmd_uninstall() {
    local choice="${1:-}" text file found=0 failed=0 state config="" sdir="" data_kept=0
    local have_config=0 have_state=0
    if [ "$EUID" -eq 0 ]; then
        print_fit 2 "$(msg root_error)"
        return 1
    fi
    if ! install_paths; then
        print_fit 2 "$(msg install_err_home)"
        return 1
    fi
    install_label_width data
    if uninstall_busy; then
        print_fit 2 "$(msg uninstall_busy)"
        return 1
    fi
    config="$(config_dir || true)"
    sdir="$(state_dir)"
    if [ -n "$config" ] && { [ -e "$config" ] || [ -L "$config" ]; }; then have_config=1; fi
    if [ -e "$sdir" ] || [ -L "$sdir" ]; then have_state=1; fi
    local -a files=("$INSTALL_BIN" "$INSTALL_DESKTOP")
    while IFS= read -r file; do files+=("$file"); done < <(install_icon_files)
    for file in "${files[@]}"; do
        if [ -e "$file" ] || [ -L "$file" ]; then found=1; fi
    done
    if [ "$found" -eq 0 ] && [ "$have_config" -eq 0 ] && [ "$have_state" -eq 0 ]; then
        print_fit 1 "$(msg uninstall_nothing)"
        return 0
    fi
    if [ -z "$choice" ]; then
        choice=records
        if { [ "$have_config" -eq 1 ] || [ "$have_state" -eq 1 ]; } && [ -t 0 ]; then
            uninstall_ask
            if [ "$REPLY" = cancel ]; then
                msgln uninstall_cancelled
                return 1
            fi
            choice="$REPLY"
        fi
    fi
    print_fit 1 "$(msg uninstall_intro)"
    for file in "${files[@]}"; do
        case "$file" in
            "$INSTALL_BIN") text="$(msg install_label_bin)" ;;
            "$INSTALL_DESKTOP") text="$(msg install_label_launcher)" ;;
            *) text="$(msg install_label_icon)" ;;
        esac
        if [ -e "$file" ] || [ -L "$file" ]; then
            if rm -f -- "$file" 2>/dev/null && [ ! -e "$file" ] && [ ! -L "$file" ]; then
                state="$(msg uninstall_state_removed)"
            else
                uninstall_fail "$file"
                failed=1
                continue
            fi
        else
            state="$(msg uninstall_state_absent)"
        fi
        install_report_line "$text" "$file" "$state"
    done
    if [ "$have_config" -eq 1 ]; then
        if [ "$choice" = all ]; then
            uninstall_clean_temp "$config"
            install_report_line "$(msg install_label_config)" "$config" "$(install_state_text kept)"
            data_kept=1
        elif uninstall_rm_dir "$config"; then
            install_report_line "$(msg install_label_config)" "$config" "$(msg uninstall_state_removed)"
        else
            uninstall_fail "$config"
            failed=1
        fi
    fi
    if [ "$have_state" -eq 1 ]; then
        if [ "$choice" != none ]; then
            uninstall_clean_temp "$sdir"
            install_report_line "$(msg install_label_records)" "$sdir" "$(install_state_text kept)"
            data_kept=1
        elif uninstall_rm_dir "$sdir"; then
            install_report_line "$(msg install_label_records)" "$sdir" "$(msg uninstall_state_removed)"
        else
            uninstall_fail "$sdir"
            failed=1
        fi
    fi
    # The lock of the running copies lives in the runtime folder, which is not
    # the program's own: its file goes too.
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then rm -f -- "$XDG_RUNTIME_DIR/mintapp-remover.lock" 2>/dev/null || true; fi
    install_prune_places
    if [ "$have_config" -eq 1 ]; then install_prune_empty "${config%/*}" "${config%/*}"; fi
    if [ "$have_state" -eq 1 ]; then install_prune_empty "${sdir%/*}" "${sdir%/*}"; fi
    [ "$failed" -eq 0 ] || return 1
    if [ "$data_kept" -eq 1 ]; then
        printf '\n'
        print_fit 1 "$(msg uninstall_purge_hint)"
    fi
    msgln uninstall_done
}

# ----------------------------------------------------------------------------
# Preflight checks
# ----------------------------------------------------------------------------
# Stops the program with status 1 and the error in $1 (it may have several
# lines). It goes to stderr (wrapped to the screen on a terminal, see
# print_fit) and, when the program runs in windows (no terminal
# to read it from), also to an error window: a launcher would otherwise end
# without a word.
fail_start() {
    print_fit 2 "$1"
    [ "$UI_ENGINE" != "gui" ] || gui_error "$1"
    exit 1
}

preflight_checks() {
    # Must not run as root: the script asks for administrator rights (sudo or
    # doas) only for the commands that change the system, and starting with
    # sudo in front would change $HOME to root's, breaking the user-launcher
    # scan of Option 3.
    if [ "$EUID" -eq 0 ]; then
        fail_start "$(msg root_error)"$'\n'"$(msg root_hint)"
    fi

    # $HOME is needed for the state directory and the user launchers; recover
    # it from the account database when the environment does not provide it.
    if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
        HOME="$(getent passwd "$EUID" 2>/dev/null | cut -d: -f6)"
        HOME="${HOME:-/nonexistent}"
        export HOME
        # The configuration was looked up without a HOME: read it again.
        CONFIG_LOADED=0
        apply_saved_language
    fi

    # With an empty or "dumb" $TERM (.desktop launchers, wrappers, etc.)
    # whiptail may draw but stop responding to Enter/Space; a reasonable value
    # is forced before starting any dialog.
    if [ -z "${TERM:-}" ] || [ "$TERM" = "dumb" ]; then
        export TERM=linux
    fi

    if ! pm_detect; then
        local pm_bad
        if [ -n "${MINTAPP_PM:-}" ]; then
            msgf_v pm_bad pm_forced_error "$(sanitize_display "${MINTAPP_PM:-}")" "${PM_BACKENDS// /, }"
        else
            msgf_v pm_bad pm_none_error "${PM_BACKENDS// /, }"
        fi
        fail_start "$pm_bad"
    fi
    # Each manager needs its own tools: rpm answers the questions about the
    # installed packages for dnf and zypper, and pacman-conf gives the HoldPkg
    # of pacman. dnf must be version 4 (dnf_version_ok).
    case "$PM" in
        apt)
            command -v dpkg >/dev/null 2>&1 || fail_start "$(msg dpkg_error)"
            command -v apt-get >/dev/null 2>&1 || fail_start "$(msg apt_error)"
            ;;
        dnf)
            { command -v dnf >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; } || fail_start "$(msg dnf_error)"
            if ! dnf_version_ok; then
                local dnf_bad
                msgf_v dnf_bad dnf_version_error "$(sanitize_display "$REPLY")"
                fail_start "$dnf_bad"
            fi
            ;;
        pacman)
            { command -v pacman >/dev/null 2>&1 && command -v pacman-conf >/dev/null 2>&1; } || fail_start "$(msg pacman_error)"
            ;;
        zypper)
            { command -v zypper >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; } || fail_start "$(msg zypper_error)"
            ;;
    esac
    if ! detect_privilege; then
        if [ -n "${MINTAPP_SUDO:-}" ]; then
            local bad
            msgf_v bad priv_forced_error "$(sanitize_display "$MINTAPP_SUDO")"
            fail_start "$bad"
        fi
        fail_start "$(msg sudo_error)"
    fi
}

usage() {
    local text
    msgf_v text usage "$MINTAPP_VERSION"
    printf '%s\n' "$text"
}

# Ends the program with the error for the option $1 and the usage (status 2).
reject_option() {
    local bad
    msgf_v bad unknown_option "$1"
    printf '%s\n\n' "$bad" >&2
    usage >&2
    exit 2
}

main() {
    local arg want_gui=0 want_terminal=0 want_help=0 command="" data_choice="" this_choice after=""
    local -a relay_args=()
    # "install" and "uninstall" come first and take no other option than the
    # ones that only print something.
    case "${1:-}" in
        install|uninstall) command="$1"; shift ;;
    esac
    while [ "$#" -gt 0 ]; do
        arg="$1"
        shift
        case "$arg" in
            -h|--help|help)
                usage
                exit 0
                ;;
            -V|--version)
                printf 'MintApp Remover %s\n' "$MINTAPP_VERSION"
                exit 0
                ;;
            --keep-records|--keep-all|--purge)
                [ "$command" = uninstall ] || reject_option "$arg"
                case "$arg" in
                    --keep-records) this_choice=records ;;
                    --keep-all) this_choice=all ;;
                    --purge) this_choice=none ;;
                esac
                if [ -n "$data_choice" ] && [ "$data_choice" != "$this_choice" ]; then
                    print_fit 2 "$(msg uninstall_conflict)"
                    exit 2
                fi
                data_choice="$this_choice"
                ;;
            --gui|--terminal|--show-help)
                [ -z "$command" ] || reject_option "$arg"
                case "$arg" in
                    --gui) want_gui=1 ;;
                    --terminal) want_terminal=1 ;;
                    --show-help) want_help=1 ;;
                esac
                ;;
            --after)
                # Internal, not in the help: the copy that terminal_relay
                # starts waits for the one that started it to end.
                [ -z "$command" ] || reject_option "$arg"
                [[ "${1:-}" =~ ^[1-9][0-9]{0,6}$ ]] || reject_option "$arg${1:+ $(sanitize_display "$1")}"
                after="$1"
                shift
                ;;
            *) reject_option "$arg" ;;
        esac
    done
    case "$command" in
        install) apply_saved_language; cmd_install; exit $? ;;
        uninstall) apply_saved_language; cmd_uninstall "$data_choice"; exit $? ;;
    esac
    if [ "$want_gui" -eq 1 ] && [ "$want_terminal" -eq 1 ]; then
        print_fit 2 "$(msg gui_terminal_conflict)"
        exit 2
    fi
    if [ "$want_gui" -eq 1 ]; then UI_REQUEST=gui; fi
    if [ "$want_terminal" -eq 1 ]; then UI_REQUEST=terminal; fi
    apply_saved_language
    select_interface
    # --gui is an explicit request: when the windows cannot be opened it says so
    # (MINTAPP_UI=gui, a preference, falls back to the default instead).
    if [ "$UI_REQUEST" = "gui" ] && [ "$UI_ENGINE" != "gui" ]; then
        print_fit 2 "$(msg gui_unavailable)"
        exit 1
    fi

    preflight_checks
    # Started by the terminal relay: the lock is taken only once the copy that
    # started this one has ended (if it has not in ten seconds, the lock says so).
    [ -z "$after" ] || wait_for_exit "$after" || true
    if ! acquire_lock; then
        fail_start "$(msg lock_error)"
    fi
    sweep_stale_temp_files
    install_traps
    # From a launcher with the terminal as the last choice: the program opens in
    # a terminal emulator and this copy ends, so that the new one takes the
    # lock. If no emulator opens, terminal_relay says why and the program goes
    # on as it would without that choice. --show-help goes on to the new copy.
    if terminal_start_wanted; then
        [ "$want_help" -ne 1 ] || relay_args=(--show-help)
        if terminal_relay ${relay_args[@]+"${relay_args[@]}"}; then exit 0; fi
    fi
    [ "$UI_ENGINE" != "gui" ] || gui_icon_prepare

    # First screen of the program (navigation instructions): until it has been
    # shown once (help_seen) or when --show-help asks for it.
    if [ "$want_help" -eq 1 ] || ! help_already_seen; then
        show_navigation_help
    fi

    main_menu
}

# Runs only when executed, not when sourced (the tests source this file). Read
# from a pipe (bash -s) BASH_SOURCE is empty and $0 is "bash": that runs too.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi

# The embedded icon (see program_icon): a PNG in base64, 76 characters to each
# "#@" line. Nothing below this line is code.
#@iVBORw0KGgoAAAANSUhEUgAABAAAAAQACAMAAABIw9uxAAAC/VBMVEVHcEx0z6JexZFQuINJt31/
#@3q5Uz44jlVZGr3dNwoRBp3E+n2wbh0tOwoVEs3ib/8kDEQosz3YHGxL2//kJIBYIHhUIHRQ4VUoK
#@IRgMIhkeOC4YMygaNSoQJhwKIxk3VEkOIxsVLyQWMCY80X86VUs0UUYTKyERJx4QKR8GGRAEEgwm
#@w2oOKB0yy3U2UUcDDgkoQjgMIBcRKyA2U0hY55kgOzAPJRsgOTA7VkwVLSMlPzQFFA0jPjNjpvoS
#@KR8VKyITKSAWLiVN344GFg80T0UxTUIlQTYvx3NdoPkoRDk60XwLJRodNSxgo/qF+sAwyXVT5JUs
#@wW4SLSIYMScyT0Qzz3pk6KMtw3AcNyw1zXgNJRsNJxwrv20qvWwIGRIpu2o8fvM/gvN28rNP4ZFo
#@rPtq66gaMykuxXI4z3sqRTpo86knQDdv7q1h5qAvyXIxS0EsRz0/1YJG2ohI24ojPDJV5ZdR4pMJ
#@HhZ79bgyzHgpxGwouWh+97o5e/Ji76M+04Bmqfs10nwuTEA0zHchPDFB1oMuST+G+8I3znln6aZa
#@6Zw6z3031n+D+b8ltGVd7J9f7aAQIRojsWIrxm5b45trr/xl8aVHivWA+L1FiPVY4Zgwc/EsST4z
#@dvF59LZBhPRE1YYNHRds9q1s7asnt2c52oJG1ohV35UmwGlusfx0uP5anfgrRjxA04JKjfVDhvRI
#@14k2efJQ3JFE2IZL3YxJ3Istx3Bx769e5J5L2Y0eplpO245PkvZXmvhwtP0XmlEboVZ3u/4irWBU
#@l/csb/ALGhQ9WE0YaDwpRzxc6p0hql5ytv0Uk0xw+bBC14VS3ZMcb0JK2ItJjPVMj/Z08bERjkhC
#@1IQ834Y0e1VRlfc8WE0+Wk8LTCgOVC0TXDMivmUweFFz8LA7V00WYjh0/bQ9V015vv8sdU46flsl
#@oFsqrmR8v/+U/MRFlGsnYkQdfUgZUDM/d8cVMERtupNgoYEnTnpAbpklVaCQ7bsfQGHO5fmmzPht
#@8qtj66Iqy3RiuXDpAAAAD3RSTlMA9L6WIP7s+/3+O3KxVsj/LlzlAADQb0lEQVR42uycMZKjOhCG
#@kQAHUPhohBxgql72nDtwrnJARuAimGQDH2F1Cyd7gb3JSrhnm5phMGiRTJn/kyy0B/j0N2p2ohck
#@yfI4llIKQyrSNH1/P9Z3LlM5zeI4kXcX3iby6xG/h/j5iP8d+DGN/5w4z6JyRrdte9sZ9oY4z7MI
#@rJqkMNaL9O1Ul7WZqqwvdTfNz7P/p9X6D//P3ZjHoTpYzNNuznaxXO1hkBdJtCpA1olvQ75UdY8L
#@DQL5v03/nTjY0ef+T00HgakIVnAMgCSPpTiVhvp7LpvNf/h/rpzyn0Z/fj0NWnMMZNHzQOyLtFSG
#@Uf03nv94/z875j/Dyg/QmFMAtUBoCineyh71OBvNf/hvh0v+9wsAGsNoM8y8BiwFUPRLcTTKu/uP
#@/N/U/f/ZPf/pQfuxE6CyLwQ4BLyTy7TujDcT+Q//R6nuYyafUr+iOYzuPbVZrntvV4Mgs7d9St31
#@74P8HwH9f4cjYCD1qxH/aU8/FAJ+6v60ZPz5j/xH/99Ojv2qG1PQB33nsNsX0WKAJBaXUgX2H/mP
#@/j9tJ6M/MNvdHnXAUvbXJYH8h/8h+v9cBHRUM/0nPJ8BsB/5D/899P9Z+EnXf4weYIdPBP6t8ldl
#@UP+R/+j/96dz/jPNLo8cADnZj/yH/yH7/+w7ye+a/8xtjzJgdvinxn6F/If/wfv/BtpVTvmPMmCB
#@8K+VIbz/yH/0/83igH5Ao6/TbgNAIlNjfnj/kf/o/3MFwF8DLOI/lQFoCkwPf+Q//A/e/++oPOQ/
#@/fSuiMAIsVAqnP/If/T/R77/t2O5/G/sNGMXQ/ORi79n+4/8x///rxbPf56NWW9DRwDI5FE90X/k
#@P/r/9KT9ovn/4b9F6/bzfSAoRK3W6j/yH/3/Eaapz+PrEQAyUapn+4/8R/+/Vwgs/P7f2JX4OAIi
#@wPqXL5b/8B/9f6KhtflbANBytUcAyGStFPIf/q+g/0+7hfv/JD7BW62pIwD91+A/8h/9/8Xv/7kF
#@YHyn0WPzXwgn8qJW4j/yH/1/P/f/jf5UAfTZ9qdBpP8r5j/8R/+fy3/dDFYAhEyiTRKnajX+I//R
#@/59dAOjJcPAPssmGQCHUivxH/qP/z5vl/R++A2A29x6QyPLp/iP/0f/n9j9vfOT/WAVAt4EJXv6R
#@//A/fP+fffeY/1wBfEsrt/7yj/yH/6H7/zxpqTz4Txn/kFuxjepfqJX5j/zH3//3mv9cAYzQbqQf
#@EB/hP/xf1H9nDoRX/wnejXEtXv6zfxXI/2Oaij/knQFkXNu+/03SqaRHbgHDTdkamZ6iRmX/K5mj
#@/u9dmkMZdWWKAXAeIYIUuUdxwBEJCHAQVQcgUFwBKgDEAaJAZeDeoTroxGGCC3h755vMyvyys/Ld
#@v9lrZe+8T9L25R488Pns31pr7Um/f3LS63Uj2t12u125zKyOyiWCawmTqSVTTeDFZV5fYlGyJvlV
#@sil5L3gj+CBYEbwUPLWwGvGj4AfBcwvr6xvJPDtjXvBXCy1J9P/g5R/Hx8f/6vZ6E5Mff9M+/zEB
#@WHgXf9/+IWBsx7H/sfiR9r0ubA9ixRe+RH8gLW8/7z/fAMJ/ogB0APgCsAFwUIBVIgBW/yMs/icU
#@gPUfPIhoNBrn//x4/LXbm/xI+88MAGIZsHt7LwdPlbdc+v/v0qn4QSUIg1lhOfHwV/vPN4D1ny+A
#@+wA4HQHg/wgTwHqM3X8+AK0kHgyzvBz9T8vPjj/3Jnb55//1/r/DDBBza08Ex7Zd+R899U/iZ37H
#@Jidvv9J/RQJqgC4A4z9RgNysAVbP0AZg/RSr//waoGUJgGQ5Ggge/PG1N/nO5j8NzEcH4hDcxiHg
#@XnnLif8/Re53KmEw26nQzDryn0iA9F9ZAN5/IgCbwP8IAPv1a4B1YPefDUCLDIAIwXF34tDy/Kcn
#@AFTg9u4EjO9k7/9Oud9rxwv9dMy6859ogPRfUwDef6IA8N//CAD/1WsA+A8s/tNrgJYmAMvL083p
#@6eVfuwnrgd943uEvPP/xdffe7T/7H83/WP4grHQqvvTn/ScTUFMHgPefCMAmFQCJOgDSf/0aYH2A
#@9F8RgJYmAMtRAM54cNyb1D7/oT/+wVfcgfFb5P93v2fr/y+lk27kUVBJzax7/9kC1ICiALz/RAEg
#@vOsRwOa/Yg0A/5UTAO0/sPg/CAB42Z38zfifGvP8j79v017g2KvM/Mej/yiSKBLJs/7Sf30C4L+2
#@ALz/RAA2gf81wOqIAVjXBACw/gOb/wiAofkjGsA//0UCTAEidqdu8eGfwn/Y3x2Y5V1/6b8+AfBf
#@WQDWf6IA0n9+G/CDhA+A9F+1CbA+xIgBaGkCsAymJXEDFLwzX/A//mfsNuz+bWfm/0+x/fDKvf9u
#@p4AaUBWA9Z8IAGSnCmDzX7EGWBXwAZD+j74J0LJi9V8EAMzEDeAf/yIBQw0o/jKgtJWR/7A/MLjT
#@3/1mYDjSCMD5TxRgUxuAD0QABHQAQN4DsCwCIFg+nninW/9j/o9BBaZu4eG/wv9SrxMM66TT338E
#@kv0frQCE/0QA4L+mAB80ARC4CoBiDdCyY/NfBMDQbD77HI8BqZ//F/6AsSLv/r/NxP+fTtp49ufK
#@f6BJQAjUBeAHAEsB4L8iAPD/htcA6wLPAVi2BMDQPO69S/38/22gP/jtH8W9FDT+Kgv/S71K0Ik0
#@Ml8ROdGfa0CC/+oCYA9AFQDBpi4A8N/1GmA1qwCAjAOwzAVgemZ6o7uX+vkP9w3/7+694l/+UfmP
#@h39YObPf6J8r/4kGqK8CAul/NgXYVBbgg4cARD/TawD/AVgeYtrKTOvzJP38x3cCU4Ve/uv9L590
#@wlifc/sD5/67T0AI1AXgbwG4GQGk9y4OAleVATC43AVcThWAmZnp48kU5/+IgWSseMv/X0b2v9SL
#@bYH6sF/4r9fffwOE/+oCwH9HIwARALjudhNgVQYgprgBiP4cT9Dn/8lgI6D4y3/e/51+N4wxj39U
#@ICZ//hMJEP4rCwD7/Y4A0n/XawD8mN9dQDYAYAb8em0CLIuA4t0IGNvS+w/927EsgfEff+XafyIB
#@YagsgPTf4wgg/Xe9Bjj/OY+7gPoAYArgzv+TObx3O27/gGv1hyxBiOd+AZ7/RALgv7IA8F9bAP02
#@oPTf2RpA+M9vAuQ/AKB5PMmf/xd5K/DOaP5v97uR6yG+BtN/ev9nbwo+AIAOwIshvK4B3jgNABj2
#@P7+7gMsCKgAACbCf/1sYL/72P7hG/7B27j/cN+f/+CHH/gN+CUAXQPivKcCaIgDMCaBBuwQAxv9b
#@tQs4xPTXT9T5PyjkYcDU2xH834r0rwURkfzxt3GffwXIv/9cAYIYbQCoDwQl/NcV4A0ZAMJ/SwGM
#@/952Ad0HoDkzzN9a3V3+/F/yj/wX4LvtEfwvd4MzTVCAgfmwpxj+gyT/9QUgPxOc958PAPznCkD4
#@bw3A8M+34Rig2bxUgJkfJ5LPAPG3hd13u//I+2HA+Aj+/35SMf6Hxv+bmP87pyxcRlsA5W8HAOxn
#@ghP+KwLwhg4A4b8tAPjnNu0CNhMCEHE8KZ7/DLviOLB4x//AtvUfDvyPv7ADoFkAjOy+8F+XAeG/
#@vgD8bwXg/ecL8IYKAFB8KKjA4yaA+wA0kwIQ0/x8KC4AEh3Yjb/yXYDxrWuxLP4B/McJoNDfvf8d
#@IPzXRkD4ry1AdfQArOkDAPPJAhD+6wNQuGOAZmIAwEZvYD/U59nN7YWAMbX/5V4YXvD/9M/A/gv+
#@UwnQy8/7D9gEZPM7wvQFWNMH4I0iAKT/fAH4TYA8BaBpCwCOBGP5+UMA/kpQwfzf7h8N+x/gDqDw
#@n5wA9Pbz/tMNEP5bCkD4rwkA/FcX4I0iAJz/RACKfQzQtAQgZuZBT24CsHsBu1O3yv9yN4wY+G9W
#@AJCf1h+o9Ff6TzQA/itGAOm/vgBrugAAOgCA918fAP+7gA1FAJrJAUABwMNfJ81nf+kLUHD/d04q
#@F/yH/OIOsFv/O0DnP5GAAOgKUB09AGujB4AvAO2/fhPAfwAaigA0DVcHYGa6Zz39s2wFTt0W/0vd
#@8JQzLcw39If//BGgVn+9/8A2AugLIP0nCkD473INQPsPCnEM0FAEoMkEIG7AnxgC0hZgFzNA4f1/
#@exJc8h9fftb/Hb3/kiv9pwtABEBxHxia+1oD8P4XZhewoQhAkwgAaM700umPL8wAxfYfq/+qCQDk
#@D8WngKQZAPT6u/SfLYD7EcD9GmBF+l/4ADRiUh4DNKkAgIcPjz+lf/6jAAX3f6dfCYHwP4h/lv4z
#@5NR/vgC5GgEUAVjxFADg4xigoQhAM10AHv51grdfFKDI939+6uHxH2PO/1EBDwuAjkf/6QLoRwD/
#@awB+C7DAxwANGQCQbQAezvzrMOUAAKYK7P9Wvx2Gwn98ySNAugB6/Z36DxwsAugRwH0AFGeAgPUf
#@eJ8AGuc4CwAK8DdiLxBLf/wFcBpYzPv/v/QizQfAf3wHg0vAUv8i+88XIG8jwHt6DcB8CoiE9H/0
#@Y4B5TQAaDgKQMALEBZjupdoAEDNA0d7/3cbdnyT/sQxw+/zvePYfuFgEuA/AezoAK/oAkP7Tu4CE
#@/0wAGqMHgFoDgK+H3PMf9udmBpjaUTz/+0dhLTSY/b/BACD8J8jafzoQpP9sAfK1BiB+MbjiPSAD
#@7z8VAMJ//hig4TcA9T8m2fU//gE3/F7Avd8Vz/+TIBQM/DdHACkLoNJfYnXfwPov0Y8AN7UGeE8H
#@YEUfANp/fhdQ+q8JQEMRAO0uIHg2QTz/z+w3JbjRt4PvKD7/7/duKIH4g01AWn8H/nc4NP6TBfC/
#@BqA/EAjY/NevAQj/+QBI/4kCWPx3fA5omOnu2p//MgExd+8U6vO/t8vtUGLcN58E6igAdqk7aRD+
#@OyuA+xHA7j8TgBV9AFj/iTUA7T8RgIbnAICZ4z3b8x/2C/ApYQXwH5jLP3IBMPjX4QKgky3Wt4D4
#@AuR0BID+zBpgJeMA/KAPAOM/EYCGwPFFAMMfk/bnf1ICxorz+3+2T6rV6/wXkoR+/D9SBUBRABcj
#@wGtJFgF4TwRA8WngArX/lgAI/xUBaFzCTwBwLdDy/Mc/gr/fUAHGU/u/06siALYCABcLAIv+Ov9t
#@qwD9RqD/k0CL/8QaYCXjADD+g3UB5T8RgIbPAMgCzPSSn//4Tk7AWD4vAEj/33aT/UcDpP98AEbX
#@X+9/BgWw+g/8B+C9OgD6NQDhPxEA4b8iAA0HAeBHgKV6dzfx+W/hJn5n0L1f0vpfblfD5BUAGoA/
#@rhYANv31/oMsC1CjAiDJeg3wfgj3AeD9txWA8J84B2zcaADqEeJO0PmDH9/JTOXvAFBe/i+1qzGX
#@/Me3+bpAmN0AYNFf778hswLUJNoRYC0NFv+JTYDRA0D6TwRA+s8XgPDf7U0g+B/z38d74vkvxM9B
#@AUq8/6Bfkf6LApz9EeTafyIBKQNQyyIAeOTfrgA8pwIg/FcEgPDf0U0g+A8emZeDID8yYOvA3p18
#@HQDI7f9+WE0eAIZvAfsNwNEI/jspQM2g3AbkZ34mAP53AS3+EwF4NkIACP+dXwSoD3g2Cfkt4gvu
#@et0AfJX2+Q//E7cALuwBiAVARDH8B/oCSP91I0D6bT/5sz4A6hGAvgNMBADeK5cAhP+uA1A3LD2Y
#@SHz/z8KY/zcAaP9PqsZ/ywQQhkL/wvgP9K8FGf+VAdDv+9sDADwHgPAfWFcAigAw/gMXAahf5OH0
#@BPzn7D/cPfz7eG42AC5f/7lyAID2+EezBaD2/yhb/4F+ESD9VxRAv++f802A51wANkYLAOG/2wDU
#@BTMoAJOAQ8VGoD//d+LnPzEB5Mz/o8tI/zMsAPz3OAIIchyA5xaG/R8pAIT/TgNQv8RSLyoABxLg
#@6XeGjad8/vds/puLgDHGBz4ALvw/srBgR7sIqBUjAMBnAJ5zAdgYNQCE/y4DUE/gYW9wAYDA15uB
#@U9sa/4HtElCM0R+4GgCOAGu/nAJcFKCmLwD2AP0HwMsxwHMrxn9FAASE/+7uAteTWHrY3U3BoZ+j
#@gHJa/2siAMmHAA5WABr/j66hAzwWgAiAuPynOvp3uQvoPgAbigDIAhD+O7sKWAf6AoBDD0cBY7r1
#@P7D7zwfAlf9HpP/2BvgZAYz+wC6/EV4/Avg/BmADsOEmAA/YAEyPeBVQiq+fAX6e8ncDgD//A5Y3
#@gYcCENIByNj/I9p/MHoB9AEQ9iMA/CPf5y6g+wBsuAnAAwvJ/isDANmzKcCh222AO78r/LevAIT/
#@YaYrAMp/Qn8wyoWADNcAQn+gWfUL5XO5C0gEgPllIIoAPLCR4L96E6Bu4+FSL10B7ro/AaT971dD
#@YgIwPwl8+n9EoLgS5GYESNLfOv2zM38OAvBj6gDAfZBhAB5YEf47CQCYS1WAw8PDMa8ngMT9f0Pi
#@IaDDAND+H2n8B35HALH4ty7/YfLRSfnbt/LJ0SY385O7gM6WAD/SAQDw30EAWg/sCP/dBeDRoxQF
#@OIxwuA1wbyfV879m9z9pAggdDAAO/HdTACoALwxGf5AQgMWTb/dP+Xbymlz048c32QQApPA/dQA2
#@3ASgxQZg2nEAlh6RBYD/Me5eDCynev+/UhXY9Q+hvyIA/v0nEuBmBKBfAEIAev+5P+A/PXbXDwV4
#@4+UYQPifOgAbbgLQYgMw7TgAS6cBWJpI4b+7bYCxlJ//A+yHgPotAP0AQOov/HdeACIAL6y3f2QA
#@2qX7Q5Tb4pd+xn8lFgD/2f0xgPQ/Jt1NQDcBaMUwAZh2HIClKAAxMxOk/2DM/xVA6f/b2H9BaIf2
#@H/j3X1+AbALwQmJ9/gf9+5foV+Rv/d3Et1z1n/1n1wGQ/icVgN8ByOwqYIsNwLTjACydB2CpNcn7
#@72oboJTC/51uNeQD4H4L0J3/wPUIAP0lV+lvFv+SbyeLogCR/xgGkmd+p8cA0v+0AVh3E4AWG4Bp
#@xwFYikEB5p5Ncv672wYY4/wHvapyADA4GACc+A9cjwAvkkiyH9d8umWpvtkKgPUIgCBp5ndwDGD1
#@nw/AupsAtNgATDsOwBJ4BP78yPkP7ro4AeD9P6nWcrMC0Pt/MIyDAgTDhLT/4JL+m0As/gWlNhKQ
#@SMLM7yAANv/pAKzrAwD/JcZ/KgDTjgOwNByA6JNCOf/BuMcFgNR/u18FfgKg95+Xn4jA6CNAGIa0
#@/gD6C/8rmP4t9INk+68a+kcPAO8/HYB1ewAA6T+A/2wApm2wLwMBi/8mAP//0fEh73/mnw0wTvkP
#@yhUiAN5XACn8P7CRaQGE/2Ea/RPX/ptrOPqz85+TzdhhSwKE8eoAgDT+k3eB16kAkP4D+E8GYNqK
#@xX9yBFgSAYj5TPrvYBFw5y3pPw4A3AfAof/wXJGA0UaAMIbWX/oPNrH4Jyh34XByBRAAC4qLAKz/
#@RADEe8CWApD+A/jPBWCZD8CMJgBLSQGY61H+g5/HHSwAGP+3u9UcrgDo+z8HDNkVwPgP+Md/jLz5
#@0+7fpym1z+1NLoA0XvivWANQ/hMBgP/UCED6D+A/FYBlPgAzmgAsyQCApQnOf3DPxwLgVcIGoPMA
#@KAYA2n8SvgBcAEI6AHL/34z/L7D4Z/nWX7yQAKl4wswv/ecDwPvPBWCdDQDpP4D/A5RHAMD4rwnA
#@0lUBaE3y/v+c4SKgzPvfr+UuALz/BzzZjgAhHQDoL/23L/4tR4ImAVDcPvNL/5UBWB1m2H8iAOt0
#@AEj/QWsY5R0AQPoPEv0XAQBLf+6z/md5IXCMn//LR1Vwo1sAHQnvP0+GI0BouD4ArxP1b5fvKyh3
#@VwYJwN9EAT64CgD5oWDrfAB0/gPlJUBA+g8s/iMAhv86PqT938tqEXBnh37+/9Kt5i4A8F+g958v
#@AB2AMEUAcP9f6L951L+vpF8ZJABYAhAj/c8wAORHgqwrA8D7DxSvARl4//kAgK7Ff0cnASXa/61e
#@9UpudAXQEej0JwqgWQNYfz243X/ov4bFv45vJ5srZw4PJ0C0QCqfSQCA8Z8IwLo2ALz/QPEesIHz
#@XxGAuaUe7f9eNicBU68I/0EfNwC9bwH49x8o7gJUJPCfDkCC/5bFP7kVAPfx99CkH/3tKwCrrgPA
#@+w8s/hMB4PxXBODxw0nS/6zeCSjR/v/UroJcBMCC2n+J1X8g/ZeEAnsALm3+r8l7vxrK7ZUVSDwo
#@gDE++wDIAsB/5wHg/QcW/4kAEP4rAjA393hu4yPp/97hXgaLgHHaf9wAyF8AFpz4D6z+A7v/QYoA
#@LKIA8B9U+vczoR+eu5uw1kcA4LkiAMwmwKqHAPD+A4v/RADs/isDMBcF4PHjY8p/FOC70Y8AWf+3
#@cAPA/R6g3n86ADw2/4Hd/3RbAGsvjP4xJ/T0T9wOFgkQO4MDzc+M568CEgFY9REA3n+Q7D8XAMJ/
#@RQDmEIDHPW7+j79HXgSMEf6DcsAHwOMAsOBsAAA2/4Hd/4DUfzH+GtafvPfLHwmek/C0f3PB8jPj
#@swvA6o0GoMUGYJkPAO8/GwD4jwAsTRL+xwmIGBv1CJCd/3ECmLsALNgDYPe/bbAEQPovsfsf0NO/
#@ePuPvffLU2oPBBaKC8nPftDvAlrwvgRosQFY5gPQ5P3nAzCHAMRsfOL8j5nKfgB4lcRJ9QUfgJqP
#@AOj9l/ZbG2DxH9j9D+jpf+3i+p+496ugv2gcxz9ScfmfCx+AFhuAZT4A9jeAlAGYA49POab9H20f
#@8N4O6f9WqVa1Muy/wwBI/5UBaAMmARb/gcX/GIv+Rv6Lb/9trhH3frVbAVJlobgknwHg1wAtBwGw
#@vwKsDMDcUACe9Aj/wUifDTLGPv93PqfyXxEAxQAALTX+twGXAIv/wO5/QEz/0F+x+FdtBQiE4pJC
#@B6DlIADNCN5/MgCw3xRgaZLwH+zf0Q8A24z/WADYkf57CcCCdgBoAzYB0n+J3f/Aoj8wj3+x+HdD
#@6UgqHvstFTfkIADaXcCWgwDYPwRIEwD4L0aA5/uk/6PsA5ZY/8shH4BahJdTwAUiALz/lgKo/QeW
#@6R8s6hf/ytvBa08jiZ+e+X32twWvAcjwGKDlIADMpwCyAQDw3wQAzP2L8B/s31MPAKT/uALEBaDm
#@LgDSf+UKoA3oAnz5ktb/2SCYPf+q2QIg9Vcu/hW3gyP9I1NXWOwBePp/JwBNFwGYEwFAASZI//X7
#@gCWL//QCAAz572UPcMESALX/QPr/JfUGQOQ9vuC/NQC+Fv9yKwCuRiHQYPVfGwDgKwANTQCaLgIw
#@JwMAWp9I/7VHgfdekf7/u0IHoOYrANJ/OgBtgiH/Y8gTADMAxAU4rUAcAfsBgPF/tn/fI/0w1v9p
#@JDMi8FIbgKeFDEBDE4AmFQD6A4HA3BUB+P4r6///6EaAEuN/TK/KBqCmCECgCcACEQCN/0D6/8Xu
#@/2zSABAv/lGAayYAj4t/uRXw5mnMy0j9p6dOqwLwVB8AcCMBaGgC0NQEoH4J6wCAAKAAPcJ/MK56
#@DZjzf6tfZQNQUwQgCBR7gLBPsQJocxj/gcX/5AlgoP5sULv6EGAtXgB4nf7lVsDpIgALgSgEfAKk
#@/0ULQEMTgKYmAPXLDPt/dQDmWpOk/6qjwBL5/N9pswGoKQIQaAKw4DAAwPgPqLcA5BYA/gpsz/81
#@+C9f+vVGqY0ErJx1gC0A/0tBErj5ADQ0AWhqAlBPYMj/5ACAuWPCfzCmeAuA8x8vATIBqCkCEFAB
#@kP4TAVD7D4z/wO7/bNIeAPSvBUMFEMv/NSwAFuT075F+FdKunH5fOQSI/136X6wANDQBaGoCUE9i
#@2P/kAIC5Hum/YgQYI/yPeXtEBqCmCECgCcCC2wAA+D8g3XvAg6V/EAwHYPjtv0Xov8i+9OvsdnDs
#@fgQGgeQEiPWB9L9QAWhoAtDUBKCeyJD/lgDgJIDxXzEC3HnL+b/Vq3IBqCkCECgCIPx3GIAvF0nx
#@QSDx9t9pAvBXkLT4xxe3+HefgO5Fe89Uh+7CePHj00IGoKEJQFMTgHoyxn9bAMBX0v/9vTv6AQD+
#@K+8AgrCmCECgCAD8V24BtHngv8Hq/6zwP4D6NTn9Dw0AxL1fv1sBYOVsKwC6DzrwcrgA8P/GAzCv
#@CEDDWwDq3O8FtgRAXAfas/EX5QcB2f3f6lYpaooABJoALLgPAPgyDPtRgEEE9v6wABicAiYu/kNu
#@8e+eb/21iwV4eQYyAOOHEvAU/t9wAOYVAWh4C0D9Kgb+EwH4/s89zv+UvyVgnPA/pl91FoDAfQAO
#@RpgARAC4zwIe3P6H+gZ594+49+t9K8AIjD2BIedfGk4DYMdPAOYVAWh4C0D9Soz/9gCgAF27/8oR
#@oMT5v911FoDARwD0/qsCgFcATu//Y+9v9oL+NTH/e1/8E7eDJcb5lxfJRwDmFQFoeAtA/WrgPxuA
#@pUnC/5ifU4wA3xH+YwB44SgAQa4DcKAJAGb/yP4L+gP5yT/84t8v/cpgAhAJwAnhgDwEYF4RgIa3
#@ANQtwH82AN8fM/7H3FUNAK9stFUDABGAINcBOFAEIH76408EAjDAPP7X4ue//3u//O3g91dMAYP/
#@C9x8AOYVAWh4C0DdBvynA/Ckx/i/v7e/P8W/B8z53686CkCQ6wAcpA8AHv+x+Kdcffs/lt/r4l9x
#@O1hijCf99xCAeUUAGt4CULcC/+kAfP9s3+K/ahdgjPN/p+0oAEGuA3CgCAAe/7XzCUC8AjR0+v8C
#@i//cUm6fOTxUADEO3HQA5hUBaOQlAPCfnwAedxn796M/99KeAb7SDwD6AIDcBuBAEYDgbP0f1OT8
#@H+tfG4z/8dP/qH8/5/Rfw+GLCRAxuOEAzCsC0MhNAB6lCkDEw8m9TEeA7zj/d9puAhD6CkBH+Sqw
#@IgCzAYD/QbL/0fS/qFr8+98K+ACHnypx/DbgvCIAjaIGIObrHskdfgsQ/usHAPUpQOgrAB1NAA50
#@AYhP/WG/ePkn/jJ3fxf9T//a28GrYKC0IgCU/4oAzCsC0Ch0AB5P7HGMUa8BbFP+77SdBCD0FYDo
#@R+WngSkCANCB6Es+/teQALz0WwxK7aEE4F8W3n9FAOYVAWgUOwBzf1L67+9/ZEaAMcr/7WgAeJ19
#@AEJfAehoAnCgCkClYvSP/ZePf0z/a7OY/gtDf/FCAsSCQOZAFIL2XxGAeUUAGgUOAOhxBaA+GqhM
#@+b/d5f3nAxD6CgB+FgHQ+28JgLnWVAvgv9AfBVjM39EfcTsY1g6Uhvj4MeGZz/uvD8C8IgCNogfg
#@8ZONfS4An+4QW4CU/yXefz4Aoa8AdDQBOFAEoHKKmP6l/muLWPwXjnJ3FRinhe9A/FfWf0UA5hUB
#@aBQ7AChAj1wEjBNbgIz/r7pVHjYAocMAAOM/AiBg/Afky4AVkPD4h/5gEfd+i0ipsioxiieM/PiR
#@818RgHlFABreA1DPfgnwpPWR8n//LvFRYIT/2+Vq9gEIswgAMwJ0NAE4SD8AVM6J/RfP/wvTf61Y
#@i395JLiZkADLEx8/E/4rAjCvCECj8AEAXcr/6+8Dj1P+v+q9zjwAoSYAFcUawPx4IKH8twRA6g8G
#@r/8J/0HeF//E7WCpst33p5T/igDMKwLQuCUBmJv+RPn/83WXgUqM/9s/hZkHINQEoKIIQAcQIwDj
#@P7D/LgDM/wl3/9dw77folNurP8T+QmRKd95/PgDzigA0bkMAQJfxfx+XgWwrAMb/7ZPXWQcg1ARA
#@/swEoGPgR4ADewAsj//4FmAo3/4bgMV/8emHp66u6vlh5ADMKwLQuD0BeDLzz2v8B9fcBx6n/N9p
#@Zx2AkAqAKID4kdoF7NAB4P3vJOtvDgDCUOpf/MW/3ApYkQnQ+68KwLwiAI1bEgDwmfA/4pN9BcD4
#@v91/nXEAQk0AKooAAKoAvP+dxL1/PP3j71Dc/Qf8S78F2QqAxS78JwIwrwhAI7MANHMQgCcP/8n4
#@v7/3nfUaMOP/di/jAKT6beFCs1THAAu2AIBR/BcBCPABQMlv/uLe722i1IaysdB6/3UBmL/RADSz
#@DMAjRQBAl/HffhI4Tvn/72q2AZBQAagoAiB/pgpwILjkfwf6G87sP/8QgPCy/i8W+vdvIf1FFCA2
#@Wuk/vwIAhP/OA9DMRwCePPjI+P9x/55yBQD/sQWYZQDkz1QAxI/UGmCBCsBByud/J/nXAODpHxEK
#@/SNq/C/7Kdrt4JdG3Uhs3n8+ALz/ngLQdBqAOSoAoEf4H/EX5Qpg+5x2pgGoaQIgf2YCgJ/JAvD+
#@d/6XvTOArOza9/+kvfGSzu17DhiSnJs0kkkQRyV6M7eenExlX67GoOe0KgGGHp7bypuZINhUx9x7
#@Pa8BBkfVuJQULqJ3Ho0BgAumb+CqGeiUp8FkhAQAb6/Z+Z3s/T3rnN/v/PZZ++yZvT/t/f/tNfMK
#@fD5Za+21svHyH30BmN5utvmf/NVflk8Hx/1NIwDLAw1ALTMB2Pz4gd1/4IBZAXD+n9STLAGwABVN
#@APBZsgaAZwxADJX/cP2nQsd/s/jqz/1WAOE+AMsDDUAtCwEgjuz+Ixc1K4DdFkd1Q5/OAsOj7DXA
#@JUUA4FlWANQf/TfMAEb/ygzd/1sC/fHS76vI6Z8hAeZ/zgKwPNAA1FIOwHy3AJSPHzD+42lAPAUk
#@8f/6Uh8DUNEEAB5FawB4hgLYYM7/08//GSR2+fcFmTv36/6VYLvIrgKwPNAA1DISAGLE7j/S4TTg
#@RYn/zZN6/wIAj6L3gIjoPhA8MwEg5VF+q//IZACd/mcW/znaCogW4N2o+wkDoPe/HwGoDToAc8Cx
#@yP+DDpeCX2P9Nxz2LwDwKJsCwKNoDQDPQCf/u4PLf/LfgPrnYPFvOR2MnGsf/dmfKADLAw1AzUEA
#@qokCUB4F/+2M2gMwLPH/+mzdVoC6IgAVTQAmFQHAAUTn/5UAewCWyP8AXPznh9O/wSSAxKcYoOsp
#@B2A9aQBqDgJQTRSA8sYv6L8d61GAN3j/6RCAIe6/IgD4LAoAPIvWAPjcjsL/Kwb7BsCSCQDBLv5z
#@sBUACaCnlzwANQcBqCYMQPmDfYH/B/ajAK9J/L92aAsAPIreA1Y0AZiUBwBhCqD3H379ZzxueVv8
#@40XhuP5hAejp5Q5AzUEAqokD8P4R+i9fAwxx/huGZy0BqCsCAI+yXUB4FK0BcIAvAO//lY7+w9wG
#@Fv/542T23Xe3t1sNQLIbgAkmADUHAagmD0D5WOD/gf0XA/kC/6+ZFQAGAB5Fa4CKJgDwKJoCzDAB
#@IBL7bw7/V1B/Q+4W/3BR+G1jKkwEXroANICagwBU+xGAjRH0X7oGuGj3HzhsD0BdEQBAtguIz5IA
#@4ABfALn/+NMfvvqR38U/bgVsGxj/iwBU+xKA8nPw38rBHr8FQP7jCgADUFcEYFYTAHyWFGBGEACi
#@F/9Bf7r6W4HFf8Vc+i0YekIFMAnYfgUCUOt/AKp9CsDiKPgvfQ8wzPtv7gFgAPBZEgB4lK0BJhUB
#@gAEsAJLQ/yAA9sV/wclto2tLaoX/yQMwlloAphUBqGoCMAeUDYe8/3AlEG4Cgv/wDgAKUFcEAJ9F
#@AZhUBAAG+AII/Uf9jf0zoH9A/NLvN36u1wGnf6QEbG8HInc2XjQBIBT+uw/AtCIAVU0A5qwBOOb9
#@P3hwMCrYAthtw78EAagrAoDPojUAPksKAANQADsS/0F/+vnf9dXfvT+VSt/mejdw+HDbYAJgCgCi
#@R413EoCx1AIwrQhAVROAOUsADKMPJPyK3QLYbWeoHjceHkUFmNUEYFIRABwQFeDKFc5/0J9+/s/E
#@/K/EZ//XfigZPvws1wkYerwd2B9KfO45pADagAHQ++8yAIz/gM1/RQDmOgRg4ydQXXYfYMjqP3Aa
#@N76uCAA8CtcAkgCA8DiA2P03dPHffvXf2E9Yzv0+++zD0hlffvpveeb0P00CQkh0q/H9DsBYagGY
#@VgSgqgnAnDUAhokDSQFwDeBb/QeexIyvKwIwmywA8ikADrRj85+Q6j85Y9EfFv+fflmKcGs3368E
#@WwGgBJDwYHxfAzCWWgCmLfD+KwIw1zkAmyOCCcABfCj4TYn/wyh9DEkA2AvC+ikAoigA/DnO/eO0
#@Xk12X/z7N0tAzrcCnkQKYETfJuHR+P4FYCy1AEwrAlDtIQAr4D9QDnn+QFKAi7gFwPpPvwpAH4BZ
#@VwFIXgD0H7HP/mn132nx/+zbUjtffJTvV4KzkQQYp0l4NB4e1XuAY6kFYFoRgGoPAVhZsfoPAVh4
#@6xHvPx4GHLL6DxxqAkCQ/27XAEwAAKH/8h//l+KL/49o8Q/cuJ7v08F/AJE7GQ+P24g7/1UBmO5D
#@AC4Dcf9X7P7DDGDziPU/4K9wDMjmP3ApWQBmUw4AwNwMVOo/2fnc7/Xo4h+4v1ucDo5CwlMLAPCf
#@0PvvIgDTDgIA/q+A//Y9gIXnrP+GN/B3AXD+D9cTBYC9IDzQAgj8R/3hg9+w+G/i4h+4W2wFRDmX
#@HKQH/2Po/XcQgGkXAWD8B0L/NzffOhD4H3sR+LrAf/8kUQAQhwFQFKDXxX/o/2TEf1j83y1xfPFJ
#@cTq4LQGRFsDjtgW9/wlvA3P+OwjAigH9B87839wY4fw3jOAeIPqPHNUTFsDVGkAxBYACyPWP+h/R
#@H770+8kXJQEPd/K9FfBH8Jk0x5/66H8Lrf8OLgNOOw7AygvQfyD0P+AXzn/DHu4Bov/IkzQDAAWA
#@56RTAEiAQv+lmP9HeO5XyP1nud4KOESjyXP8sZ/cf8cvAaYdB2AlhPc/ZELgf+wjgcMC/5/WgRTX
#@AEt8ALQFUCz+I/6vGeKXfq/dL/XA93k/HQzAiqArSv8dBGDacQBWzgD/AfI/YITz3/A6XAVE/4GT
#@wQUAn+VTAEShPxHVf4n0r5gv/cZe/X1fklOcDn528nUnvRMHYCx5AIQrgGnHAVgh5rpy7v/Cj4z/
#@sAlwEf1nLgKkvAbgvxeiL4Bm9n/m/5r5B8/9Shb/wE0/368EO2rOBOCOyn9FABoI+u84ACvCAGye
#@c8z5b9iHlwDd/W8eDioA+KybAhCJ9Y/u/Vfg0u/DkobiorCGO2kFoJEsAFeTBmBFGICFzRa/XRhl
#@/Dc8ejP+EmC3Kzuz9cGsAehZPQUAtLN/+PFv4M/9Cvnws3y/ElxS+J9WABoDDsCKMAALrQAYjrr6
#@j5sAQ/zP/2tDdUcBYAoAz64KQN5L9Q/+/T/7pV8dnz/N90Xh/5BIv9zLh8FV/hPovz4AjP9sAFaE
#@AViIBWDufwX+P2pdB9ix+497gJ6XfgCWNAFgYH/sM6/+jP547vfpl6WE/M9ucTp4mfN/mfxPKwAN
#@fQDQf9VdoJUYXf2PzQDesfmPjEYOAu9yHAX+e6muAcB/VQEuyQvQXX+Sn/TnLv1q+Cr3p4OXl7vv
#@+lMC7rgNAPqPKA8BKe4CrQgDsIAB2Bzl/X9EvxPgdfDfyqEXkPYaYIkLAFOA1ggi0Z/UZz/28+yr
#@Uj8oTgfXjbidp/3LVADw310AGgkDcNVdANB/DMAR+G/lTdoD3OV5PIAA4ABfAFRYWAD7D//WGkR1
#@6VdBcVH4baNu3PjgH3oMMf9/OgFoJAzA1aQBWAG6+I8BeC7w/8GvzwKwyzPs9R6AtYQFoGftFCA2
#@hKD+COqvufSr4b1rOd8KMPJiAMKBlv4GpwFg/AcU/isCwPiPARgH/62c7QIO8f43h7yeC7CWMAD0
#@rC0ADiFd/W/p333x37xV6jPFReHzAhjdIwWIC+78LWBDFQDGfwcBWLAFYGNjlPf/1tku4PAuz2nP
#@AVgLSBIAGtAGAMYsoP4RhIv/uyUXfPlNvrcCvj5b7BOUAFDccQAaHUngv4MALLSI+b9xxPrf+s2g
#@O/wEYPdIFADwP8kUgJ61BYAxO51e/dln/7pLvxoe+vneCngXdTYFSDcADX0AeP+TB4D1n64Eg//A
#@xfAqEEuzeYgBYAqwljAAFWUAyHYcEwGzf/ZjPw754S/5Ph0ctz8sAOD0GEBDFQDGfwcBWLAFYMNw
#@zPpPZwHfFPjf/NkTFSDuv34NQAPaKYBlUKz/jNX/Clz6fa/kkuIzQpfa5gBpBqChCgDjv4MALESI
#@+G/44ID3f+/FLuDrAv/vebIAgP/aKUCFCwBTAOu8wE70T8yv+X7xmX/QP+AxXPr9sOSW4jNCJ38b
#@Wx5D/d0HAP3nA6D3P3EAFqJE/TeMcv7TjeDXeP/94Z4CsJYwADAgnAIw2PUPOdM/wPg/ifozl36d
#@cauZ71eCgcWgdToBaOgDoPdfEYCFGOD/b454//dHBQFoGk64ABDkvzQACPivmgLQEFsA+MOK+Sfw
#@n/nS787DUkoUF4VpEgC43QOcUAWA8V8zAVjtHoCFOOQ/8Qvr/6PwVwIM8f7TW0C+AOS/tgDgv6YA
#@rSGko//hz/3JswTg4p+59OuS4jNCdUyA+wBMcCsAQO8/E4BVRQA2zjlm/Q94gzsG0AwRBwD8V0wB
#@8LnXRUBsDAD9icD98Pf8mvU/nvtlLv0658bTnJ8OHmspnUoAJpgAjNcAhf9MANB/eQA2IrzF+W8w
#@7wGv8/43j9gAEGsYAL4ASKIpAIxJjglVAv2N+8Z+fPPPXfp1T3FReNnMAkKl3W8BTDABGMcAiC4A
#@KQKwapsAMAHYiPFP3v8XtwGavP/NHxUBUE0B2AsCTAFwCCH9wf+gAOE/ZD/zpd9UKS4KB+abfwOi
#@hrsIwIShq/8YAK3/TABW2QAsAOj/xgjjf4C5DfAr1n86BhDS3wCA8PjMTQFQdxhCzDgs/oMB0n8J
#@9Hd06VdB8RmhseX1sZCo4VHhlQFgbgGh/4oA/E4TgFVFAMD/948Y/w3Be8A3BP7veITbKQANaKcA
#@MAbAOI1U6J+Y/3ju97++KA2UG/fyvRXw7+tjRNTwqPA0LdAHgPVfEYDfaQKwKgkA+o/8xPhvCN4D
#@XuT9bw6nEwAa0BaAeztARCb/4cY/6G+59Pt5aeA8yPdF4cP1SALIcJvw+j3ACSYA44oAgPFAJ/8V
#@Adho4znjv+GfnQ8CNiEA7tcANKBdBFjGwH8i9vN/aQn0h4/9BHxbygDF6eDzBEQVX0bjtQGYYAIw
#@rgiAzn9FAMobbRxz/hsgAOA/ceKlMAXAAWYKgKD/uDsYh979Wff+HtPiH9/+DZbiovA/TAEAm/Gq
#@AEwQjP8OAgD+KwJQtgTgA95/cxDgNcZ/BwEAwH9lAcIhBPyHr42S/TH/Z+ncL5z/yQR/z/dnhE7v
#@WBOAAVD5zwRgnJ8AKAOA/isCUIYAhPyV8d/wJgTA6r9/4jlfA8wmDACNIVb/6b9hWfzDx37gsz8Z
#@4Lucnw4O1wHYgeT+MwEYdxsAxn8mAGVrADZHeP/3L1p/JWgTOPWcTgHAf00BIkNAJ//D/2zF/uoP
#@wTtAg6PYCpg0CQiUdeK/oYv/bvYA7f7LzwGVKQDAiM1/4NcXhnj/d49cBwAHei0ADEEB7PobwP8r
#@p3a38NO/g6S4KHz6+/XQ4pT9T74HiFj8VwSgTAEQHARA/78LAtBk/KeTwIo1ABRADhMA1B2HurCE
#@/q/hqz8Efg9IFihOB4feuvB/wua/4wCg/0wA0H8KAPIvFv+Rf70wxPu/e+g5mAIg+ikAjAHtfxV/
#@9OO5XwR/E9jAKS4KP1kP6aP/hMV/pwFA/+UBQP+Rn3j/90eCADTB/3a6B8BjA+C2ALYxUJ7XHxf/
#@CP4u0AFTXBS+HU3Aeh/8J3j/9QFg/FcEoNwlAM/RfwsmAOg/EwAsADw6nwKg7dzmYIh19t9iEhf/
#@CPw28AxQfEbo3fWQ0Gu1/1wAxh0H4HKSAJS7BOA3z+3+wwxguMn4zwQAn/UB0BUAx6z6w28bQ/9x
#@8c/RvFVsBWThdDAVAJYDWIN1kf+E1X9HbwHR/y4BmLcFoIwBiHEM/tsIAsD733zSOQD4LNoGXOtf
#@Afi9AbK+k/5bsPhngC+CDZi7xVZAhIjo8IOfhpUTAHdvAS+f091/WwDKXQMwdcz7fys+A2jyAYAC
#@4LNoCgADSQKwZMHy4x9QLP4B+CbowCguClsKANuDtE7QB8DdHuBlPgDkP2D8hwAg71j9xxnAU/S/
#@lwDgs2gKAM9JCoBDoe4S/Qnp4j+7p4Mf7uR7K+AOJoBUh5W/LgDjTgNwWRiAeVsAykwA3v+Y9//m
#@6IXrvP/Nnz0A/O9pG5AGOCp8AdqH8C+i+YrFP+D0VwQVXxTWbwUQEeP7H4BaXwNwWRiA+QCb/xAA
#@ZNziP/LfF+7x/jcnPYT8730KAM9JpgDtY/A3bT/5SX/82I+KT7OxFfDh93k/HdyJLAYA/OcDMG8J
#@gM1/5C3e/+ADwTu8/81ZDwH/5VMAGEhSgLYx/JuoPwGXfhVk7KJw8RmhP3QpAIxk5iXAZWEA5m0B
#@KAsCsMj6b34jSJP3v1n3EPBfPAWA5ySLABhD3Rn94WM/eq79kJmLwsXpYAXov+sA8BMACMC8OgCb
#@Fv+R/Qs2/xGvnbqnCQAMJCkAjFWArvp7Hrz6U5C1i8LFZ4QY0zP2FrDKBAD8FwUAsfmPXOD9xwAg
#@8jUADCQpAIz14L+Hr/6S801xUTgDDM0yrmfpJUBVGID5JAFg/acZQDN5ACRTABjQFYD855mdtf/4
#@h3O/CjJ7UfjG0+J0MJLJPcAqHwDwXxUA3v8XAWg6CAAUAEi6CJDob4Jj0V/76o/h2v1SJriV84vC
#@ev/TDEBVGIB5ZgLABYD33wSgqQiAYgoAA0kWATL92/H0i3+eezdKGaD4jBAqnp2XAOA/H4D5hAHg
#@/TcBaDoKAAgPA0kKwGPR3zP/JF/8Z/+icHE6OOsvAarCAMyLA7Bhh/XfBKApwEs+Bai7DwD++Ee2
#@lnSL/+Ki8Mt9OhiZcLYHCHT1n38LOO84APvOAkCA/y4LwOvvbcHi3wnNmxm5KFycDgZiyg/yJUCV
#@DwD67yQA+2kGINFvC0yovxegf/P/kl8ULrYCGvY5P/1pI+09wKowAPOOA7CvCIC6ADjgqABra+2L
#@/601z/Czg8V/5i8KF6eDjeHxApwLT3+cbgCqwgCg//0OwH6aAYABbQHAdWTNAP57of76S78v90Vh
#@P99bAWOh4ZQA/JEfPga43wPk/YcALDITgKQB2FcEQF0AGFAHAFyHIYT0X9tyNvvP/kXh+zk/HdwI
#@DacEoPDBc0haB4GrwgAsOg7Afm8B8BMFAAf0BQDZOf8D/Q1w6dch8BmhTJDzi8JLDYICEAqPxkv8
#@Tx6AaoTu/i+qtgAQ3n9RAHwKwG1NAWAgUQHAdRiyLv5nHM7+i4vC2ef07fMEmH87Gk9PDrcAqsIA
#@LDoOwH5vAfApALc1AdB8N8jWBKvrliH48e/+1V/2LwrfzPlF4dB6BANgA/xPGIAqHwD030kA9nsL
#@gB9w5r+mAIhgCoAjIVbXLWNbZu2f2uK/uCicfYZ/bFjhAyD3XxCAqjAAi4a+vASY4v3nA+AbQv8V
#@AdAUgEaQ0HXAMhSIH6I/9/sKXhTO+enghpVeAlBLGAD0H4j735cATE2x/vMB8F9A/qcxBYgMAWss
#@nln5m3+3tuSXfnNyOvhpvrcCthsMvP8I+p88AOS/9iUA+D/F+c8HwA8h/1OYAsAQpz9iZv4G/bnf
#@V/SicPFF4fUkAag5DgD4zweA9z+A8Z8PgE8BuE14jguAIy2kP/1D/WHxP2Cuf17KAMVFYX0AajYc
#@bAEs9i0AUwbGfzYAPkH6O58C4BCM8w14gX7xX1wUfpU5+QcjPDyz/uu3ADAArP98AMB/A+M/FwDf
#@HgCHBcAhuf6RH/9w7jcbPPuquCicidPB3X/i8/67DMBiC/S/1wBMhTD+MwHwIQDqKYDot4VZRJf6
#@73mefvGfs9PBxWeEmCk/PKL/LvcAF89B//kAgP8h6H9PAfC1AUDfaYAtwBrC608H/rbM/wLW4Nxv
#@pniakc8I3S1OB4fUwv+3FjceA1BLKQCLERj/Aav/BvS/lwD4EAB1AWiAXQTIooB4Xuj+C/8v6Rf/
#@uTod/E2+twLepgAY92sGEj5WgBr673QPcDEK+A+w/hPofw8B8PsVgO4XhZMS2m/QL/7zeFH47zu5
#@XgecfkwBaNES3tDqA/rvbguA918agKlz0H95AHwIgLoAONCiL/aT//DqL8vsZOR08A9/yflFYfKf
#@CIUn8I9dB2AxBvjPBwD8J9B/cQD8pAEA//tagNb/aSB/S3/9pd+cXhQuPiNkN5wKgAFwuwWwGAf8
#@5wMA/hPovzQAPnJbWQAciKH1P8A7n/2He/+XMj77h88IFReFM/EZIXsBiAwEYK7nAEzFQP+FAfD7
#@FQAYAYS2w0Dkv0v246u/7HPtvVIGKD4j1HUSgMMO9wAXAcZ/APyPgP7LAuCzARAWAEcQgf8Gi/7c
#@4j/73PtTcVE4C6eDax0TkOYWwCIA/gO8/wT6LwqArwsAAv6rFgH41+L69+Xcb3E6+KN8vxL8umYj
#@/QDw/vMBmELQf0kAfD4AogKA/4opAP498D+kkmzxX1wULk4HL9csDH4LYK7nAEy1IfB/DwLg6wOA
#@JC0A/D3Sn/x3uvgvLgoXWwEutwD4AMz1HICpdgT+QwB8LgCEMgAIpz8R9z/FxX/xGaEcMPzYGK30
#@38EeIOM/EPEf4f2HAPhOAyArQPjjHvBA/5d38Y98kolXgsVF4do0FmBgWwCr6L8kAFM2WP8hAD4f
#@AOcFCH/cA9E9BTfnfouLwg938r0V8PF0LAHTyhVA8gCg/4jAf4LzHwLgZyAA4Rj6H4Fm/31f/BcX
#@hR/k/KIwFYAMB+NT2gNcXUX/BQGYssP4DwHw+QC4L4AZ4fV3f+63uCicx9PBxvqI4HHh3WwBGOL+
#@r871HIApTQD2IAC+8wDwBahbOJef/Hd/6be4KJxPTn5P4l+FAtCjiwCA/yuM/wD6Lw3AHgTA5wPg
#@vgBd/N8ivFOXs//ionDOPyM0cfWqMT2w2IgNwrvZAgD/ew7AlCYAexAAnw2Ag0UAIfff/au/4jNC
#@3+X8M0KB+qHS5LzrADD+AxL/Cd5/CoDPBsD9FAC8tx38+bPzV3/FReHionCdPJ42GNtbwjs8BkT+
#@9xqAKU0A9iAAPh8A9wXAH/zt/s9m/9Vf0ovCpQxQXBR+p5UAxN0eIPnfYwCmNAHYgwD4/QrAbXUB
#@wH9iIOd+i9PBxengWqsAZ/8jnB0DIv972wL4rSYAexAAXxsA9J1GVNsAnP9H/8/eGYXGcZ57/+qL
#@VlcfH7RQhW9BYDh7FfCBopBQlD2+MQ5BbuDYpmBj2GAc2TZxUrfZ4MXGMXXjRmmj1hgjxCLiSLrJ
#@wsFtG4XcnRu3JY4cEFpdFZkIvDK72cI5l9bhzF+bR7P77PvM7KN3Z3Z2Zn6z2l1PODfl/H/7PM+8
#@70y5tLX1UfglQLpROGEUfnOo+sbcBpJMFsAfEdQIAPlXC2BiPwJYYgIo9UsA/IzKAD75//f/s1Xa
#@AnfD+//LdKNwAin+stpi9P+3RZoZIIBlQGL+GTz/egEsMQGUVAJg8Pzv2wBt59qzj79dLrTSv5Vp
#@nAm/Ckg3CieFqd8cGBlB/A9Vq9/8m2QAfO/zCAD5VwtgYj8CWLITAIfnf58GoHMs/3v8txN+59i6
#@WKvVMmvxv6Ht3XfSUUD41O9Utx89enS02qIhCoAZgOdfJQCWf4UAJvYjgKWgBMDP6AxA5/ilPwLl
#@P2jUwOhWiApINwonhYeHTjcfOTSr1TfwOsRL+/bA6/MvCIDyT6jyrxbAkrUAOG7+LUoAOiflv4YC
#@wHn9V622AQM0VuI/CqgfTzcKh0nppzd24++8na62+M4sAPpO8PzrBCDkX4DlXyuAJRsBCFD+bQxA
#@50z5v/nWW5ecDgA8bMUfJGIUsJxuFA6L+scz28j+Ls3F3RqgWjOXAPSdYPlXjwCQf7UAKP8qASwF
#@JQB+RmsA91x3/sH3I4DRGiqAjVYZMPowtD4gfaJw3BdgPas+bUW/9bdddXgDQwCGnwBe0guA8q8T
#@wMR+BLBkKQAB5N/OAIb/6OYfNLbAmVby8ZaYUcCFiIwCVuKsgPIbp5B8UoDzdqAKnogCAMr8E0L+
#@dQKY2I8AloISwH7XCPec/0utGUBmL/0brY/GRdtRQLpROF0dPPXjD0Za0cerxchuD/DdS61YdxqA
#@jwR4/nUCoPwTqvyrBLBkIwAlul0BHcnvzv+lmzcdAWyV5ij3zhuRuTAV/2vTq+lG4SCb/8Xt7+NP
#@4OvhahUC2M0+3veQBYD86zsAIf8CLP8+Ahjj+bcXQBAGYL/83QJABUCXAEkBOPCZgD4gXR0cIE7z
#@j7x30WwJANnHW+e6YELOv0IAkxoBKPLPBLAUsAAsmgBe+Xfnf7cCWMsg8VT+uy5oLG/F/1L1vahs
#@FI7Zut83TrL4UyWwvbgrAIQfb7IANPkHQv4VApjYjwCWrARQDEQAwCAAgvIPalvgeKMGOioA/DWO
#@hzYKSFcHP45b88/DD0ZuVKkCADCAEZ5/vQAmGZr8KwSwZCWAIgQQmAFYB8Dzf5MEgM1Ay7XOCoC+
#@Zh5PpRuF0ycKK9f9ovnn0QfNp7QQ6BUk2MMAPvkH/S4AJvYjgCUrARQhgOAM4F8AfNa6CgAFlEep
#@AsAbWSApq4PfjoYC5uJQbz2m5p/TxCIAEsArSLAsAJ5/rQDyagGo8j9G+bcSQBEVQDAG4LRlv60A
#@+AwC2ONehuaArgdAY7mUbhROVwf3vO73aMeVf/dj5MNquwBeIQG8ZJ9/wPOvFMDEfgSwZCWAInh/
#@X/QY+u78I/z0+w8BfAYB7LHSQPIp/e7RuJWAUcBculHYnl87m34fGWmeRfCZAHwN8NL+BJBXC2Bi
#@PwJYshJAsRSsABB3If8A+ecC2Crf70w/fSRiFHA3fYyQJfVzWPdLsOafOEQCAC0DqPMPvPOfV+df
#@L4AlKwEUgVoARK9VP28AaP3P97//09MkAGItQ/U/XnSkG4X9STcKr/0J6345dOmvHSYAvixQm3/A
#@8q8TQFYngLFdASxZCaBY0gmA02vbbxAAwo835B8VAOMMRgHsgAIaKwkYBRxPHyNk3/xzRt6sAi4A
#@VgLwQgDLBPQC4PknFBNAKf9MAEtWAigS7wdlAEq9oQBwoALgIF0GxB8xh1FAtwQ2MvfSjcLp6mB5
#@069Q/Z+qAi4AZgCDAAilAPJqAWT3I4AlXxY8BFAshSMAwAXQSj/i7wiAtQAtCxS3Rg0GwCvzcCrd
#@KBwSq78etk2/Ps0/E0CeCwDvPP8yHvkHyvyrBdBD/mUBIP12AgA9CUC6/g+c+B9EBWDi80zNaIDa
#@c6GNAtLHCK3Uh2bT70mp+p+pmgWQJwGQAcgDlgVAXi2AbDACWPAQQLFkLQCw3/xT+f/Z9MFpSQC0
#@Ophwtwo0LsZ/FJBuFNYw9YsbwqU/rPuVBODABYB3SwHw/BPe+dd3AGP++ZcFQNknAczbGICnXsw/
#@KwAQf1YBcJbbRwFtb+GNAtKNwu+UIi/Lnbel5v9KFSgEAHQC4PlXCyAbjAAWJAGw338IYH7e0gDy
#@pX/ifTYC3M0/4g8ByDwcReS7JJCMe4aVv043Ctus++WX/rgAuAEImxFAfg+r/NsLYMFDAMVOkH+9
#@AAjxwh8TwPud+XdA/EkAMhcyZgPUVtONwulGYWz6PSE1/69WCb0AXtpfB5BXCyAbjAAWPARQZAaY
#@B3YlAK/6DQK4eZMJYBocPHj+vCgAd3Vwe/rdUcCtUrpROOEbhX/94zd91/3KApAN8JJeADz/DK/8
#@6zsA4JN/UQBFznw/DMAizwXwviMAwp0AOJyHAPx4rrZhAPcMi8Hu1fSJwhbN/+K2fOnPQgB480PI
#@v04A2WAEsOAhgGLJVgAc49TfKAA+AZhmAhB5aFoVAAWMJmBVQOFaulHYyFr1U33zzwTgGoBbQF8A
#@5Nuxyr+lABY8BFDsZt7aADz/gAmA4u92AFQAiAJgq4O7KwAc8b5nWLpRWKb0xlmp+f+gCsIWQF5d
#@AGSDEcCChwCKJVkAlgZ4i2EUwCV3BOigEABGARu8AgBhjgLSjcLlyPwv8psPpeb/RLUnvsu1G8Be
#@AHm1ALIu2vwDOf+yAIqEpQA4lH8Gzz9tAqD4CwIQeMhGAXt9QOZZujo4LA5NRSL+Z/TNvywAQmUA
#@If8KAWSDEcCChwCKJVkAlgZ4y5P2+p8qgIPfFwAvcwHIPMwg8HSQBhJy+/DHM9G4JBiBjcKFP5+W
#@mv+Zau8CyFkI4BVGnmGVfxsBLMgCQPplAVgaoDcBuPGfbhfAw54OcKthKAEcAzTmthKyOjjdKFz6
#@5dmmYt2vxLe57hLACXZYBUA2GAEseAigWLIXgM4AeyfZAPASrgEg/+BybxUAWWC5wSuAFpkzod0z
#@LN0oXBzg/wa/OyBV/6erGr5jAtBVATz/WgFkO1DnH4j5FwRQlJgPzAB0kl8CxHEQoADQVAD4xCVB
#@twJwC4FEbBQuRmR18Gp9UM2/cdMveIpLf7oKgHoARFgnAOkKAOGf/0AEsOAhgGJJFkBQBqCTrANo
#@jQDbKwCk2/+PLHAh0xH+PR00RtONwqFxcRAKKB86pV/3K1cAVAJYCQD513YAcv6tBLDgIYCizHxg
#@BsBJLgBaBEgTgJcvowJovbw/3X9sXWy0Vf9uR5CIe4bVV/5fQjcKT/1U2vTbPFpV8227APIQQJsB
#@/DTA8q8UQDYYASx4CKBYGogAABeAw8FptwNwKgCKts8n/aM1Cqi5xT8gH2TuxX8UMHUoiY8Rqu8c
#@sL70xysAMoAsAHX+LQSgyD/wyj8XQNGL+WAMQAK42SUAWgMAXr7cYwXA/0GjACSfXviL5+rg9InC
#@n6P5l9f96vm2QwBOiNUCoPyrRwBWAhgjPPLPBVAs+QsgAAO0ziH5fAbYagCoBXjosIXXlvmTDvYP
#@Wh3MaYR3z7B0dfDxsJr/kz73+7WqAEC7APDmBct/mCOAsT3k/HMBFL2ZD8gA7zMBsG0ANAK4XKNw
#@I97mT2Kr4ytWBxtpHE83CsfoMUJ40q/Ful+xAgCWAuD5D3wEMOYi5p8LoNgHAdxUKoALgN8IgPLf
#@EgBQVwB4FXYfI8TAmcyFu/F/jNDPk7FR2GbTr8wiKgAHQQCvKPIfYgcwJghgQRQA8l9SCoAbACHW
#@FwGiANrXAFx22PCrAPAVf+3/oK/PRqn9pw8Qn1FA+hihtepTq3W/cgUglAAIuJ8AKP8hdwBj7Qj5
#@5wIo+jLfTVf+lQbwrwBa+YcB9jsDoI9bUh8wt5U+RmjoNwqX3jjhte53cf/Hd9YC4PkPXABjHQj5
#@ZwIoFtUtAOD51xuABCDeCYBVANohwJarjdtdCqiFPApIVwd/XQzmSb/iHb9OIcRWFUA2qxcAy3+4
#@I4CxTnzzDwEUgaUAkF29AbgAEH9eAZAAWLrZZ3srQP9g/3205ua+1uaBzLOP0o3Cw/pEYWz69Vn3
#@u2hxuAIw7gnwEwDyH+4IYIwh599WAIDnX2cAHwGgAGACkKCYyyUA2HpmviSIe4alG4WH9DFChT9f
#@kR/20wqxBe0CIAMoBID8h9sBjHHk/FsLAPD86w3g/t8zAVAB0GoBXiQBCAMAqSRgJrjI+gAqBxq3
#@043Cw7g6+KNfHhbi3zxM0V+0mgE4AgBaAVD+Q+4AxgQBLAQiAMDzrzUAF4D7QFC6BoD8swrAhmVp
#@Gjh09wxLnyhc/9urUvP/qRti6woA5HNqASD/IXcAY4IAFgISAOD51wgAC4CZQNofCCpUAJbgkqCJ
#@2uhQjQLSxwjV74nN//aMk/y+4Aggu18BUPZDuwg4ZoDybyuAsocAbnJ6F8BNswCmgbsKgFUAtkir
#@g2vPhTYKSJ8obL1RuPgned0v4l/ty/EdBAB8BPCKkP8wO4AxE5R/SwGUy/MSlF6lASj4ogCOBFQB
#@AOPqYIwCVoZjFJBuFJ766VGp+T+7aJN+dvxDKwCW/wA6ACDnn4P82wugDAFI3Ny/AW4CswCOtM8A
#@uADsoXsHczJnSpGPcPoYofrOjLjud5HGfoFXAIALgOffsgMg9PknkH9rAZRlAdgYgILPBID8kwAc
#@ghHAljwK+CTdKBzxUcCFP3o2/31Lv/P6djY76ysAJF6V/wBGAGMCC30QQBnMB2AACr4gAMQ/oAoA
#@HJc2Cq9GeaNwulG4dEhe94vU9tMAi9/N7lUAeR8BsPyHOwIYsxDAuo8AyrIAbA1wk3OJCwA3AwlE
#@AGDOOArY3GhcjOooIN0oPPUL8Y5fJxf7CjyCCiA3q6gA6AJgyB3AmIUA1n0EUCYB2BtAKQDaCSQN
#@Ae35ROgDEnH78LvvDN8ooH7r2ra47pdC209QAWRztBpQujkovrD8h9oBjFkIYN1HAGW9AIh+CCCw
#@FgDxd/6E1cGR3CicbhR+/I646fd6e/qrfXqhAiABuBUAAi4IAF/D7wDGLASw7iOAMheArQFwViEA
#@xN95vQgBBMNxaWngcgL6gEhvFFY0/0fb6/bgK4C8JAB8C7YDADz/FgJY9xFAmQvA1gA4axbAPM0A
#@mQCCmwEQy+IooBgZBaQbhevyHb9Od2a/2t8ZgMNs5xQwzwTQboLwOwAbAaz7CKDMBWBrADprEsAl
#@/LlbgdsF8KJaAParg0Hm2d10o3BIHKp7b/p9W2r+t6noF8JvWwHM5ij/vgLAlwh1AKCH/MsCKHMB
#@2BqAzpoEgPCbBHAZoAX4JKjDUcC9JI8CLkRkFLAiK2ANzb+07jdIUAHkYADgJwB8RqkDAP75lwVQ
#@5gKwNQA7ywXgwARAHcCLEEBwQAErEb1nWLpRGJt+z8rrfhkBVgB7NQATAH0R8x/kRUALAaz7CKDM
#@BWBlABZ3QQCfMQGc3zPAZoAVQOtjuSbdPjz+o4Cp1ehuFK6vfH/HrwfshXW/INgKYDYLBwAfAeA9
#@Wh0A8M+/JIAyF4CtAdhZswCAuQL4JFgcA/BRQBTuGZauDr73tse638D552x2nBYD5k0CoOA7HwTP
#@/8A6AOCTf1kAZca8rQFMp9vzbxQA7QaGAB4GfDivW+IoIAEbhe9FZaNwh5f+TE/6fYBXGyM/Cz7+
#@aAFmx1s9QF6qAOhr9DoA4JN/UQBlzrylAYyn2/NPAkD8B1MB4I/uHcwJ8Z5h6ergx3udCd3xi6L/
#@gF7NE4uh8I+eKgAQwQ4A+ORfEkBZLQAfA5hPs/wzAbAKIOgCAH/Om3hJ8Fa4G4XTjcL1nVe3Kf2M
#@pzOL4fAtVQDiDMA+/wMQwLqPAMoqAXAD6JlnAjhyMPwKgMoAZ1XARnLvGVZ4OxoKmKv/3wu/oua/
#@rQF4QOt+Q+KfEEA2K14FiHQHAIT8ewugbOCvGgPYCwCwCiA8LmaMKwM3avcfphuFQ+LY4utNN/7t
#@n01a95uICsCyAPiRnH9ZAGWjAFQGsBcArwA2PwkT8d7BK+X4jwLmoiCAk80HSDyOjhFg8xRyGXIF
#@IM8AAsh/4AJY9xFAWRBAMAaYNwsA8R9YBQBGB3jPsHR18P+MPACsAXjAm//g+ZZdBYiaAMb0Alj3
#@EUBZEEAgBkD28WcWwMuDqgAA7h08mHuGpY8R+vsjxB+0igCyAK37jUgFACLeAfxAyL8sgLK1AICu
#@+pcFMLAKANBjhBibjdUgRwHp6uBPmw/acBuB5uHFxRnnCI8Z3xlAxDuAH/xAyL8ogLIoAJ0BrARw
#@xK0ALg+sAgCrtXSjcNic+Aqx764Amk8RSDAT2sGvAuAVAQEoCgAugHUfAZRlAUgGuCQbwF4AZAAm
#@gAiMAu7FfxRQ/HoAzf92169/6w3rfmcGXgFwAeR5/iO1CuhHXQJY9xFA2U8A3ADIrZ0B9jQiCYCt
#@AwibWyGOAtLHCP3no+5ff7xh3e8MEjmoCgDkTQL4l8h2AMg/E8C6jwDKPgIAXfm3MwAJoGMvMBfA
#@i4OqAIC8OnjuYbpRuK9c6Wz+29f9Io2DrQDyeDEBOF9CF4Ai/1wA6z4CKPsKALD82xqAC2DaJIAB
#@VgDgOWkUkG4U7iN/GGHVP8X/qZP6QdFRAQgCiGIBgPxzAaz7CKDsIwCC5d/CAEwAn8kCQAUwQM6N
#@bpgZfXY3faJwP5t/Xv5j3S+CuDiggyoAIuICYPl34PmXBVD2FQDB8m9hACaAzyIpAPAMjxHaZAeq
#@gP6MAtKNwr9vmmd/I0dnBkrnVQAmgLylAHJqASjyzwWw7iOAslYACK2lAbgAQJcAwKAFAAWsNjYY
#@LQk0bpfTjcL2637bcGd/zVMzg4RVAPmcLIDQ8w+88s8FsO4jgHKvAgAs/zYG4AKYliuAc4M8HAOc
#@G61tmsBGYQsFpBuF/8Ka/70K4CkyGJUKAHReBcjbCSAHrJ4I5pd/wPIvCaDcuwAAy7/eADivFcBg
#@Oef83cnwNgDH5mYyNgpfC6j5/3vHpT86nOr/gxkQlQogz58QygUg559g+VcKQJN/LoB1HwGUNQIA
#@SKxkAI7ws88E4HYAR6JZAez+rTQ2u4ACkrFROIhLgr/l1f/3NA9/P4aLYAUAAeT1ArDNP0fOPxfA
#@uo8AyjoBAJZ9nQHofIcAEH9aBRDRCgB/q41NXgFgFLCZbhTeDyfZul9a+N/8dCYSGK8CkAJsBJDT
#@CmC8G9/8A55/ewHYG2CeEAUAIlYB0JeuUQAUANKNwrbrfqn2p0t/RBQrAC4A+/zLAtDmnwtgPQAB
#@2Big87wsAH4VYMD5d0uBncxGexVA33HPsHSjsALe/Lfyj3W/MyDKFQCwEIB1/oGUfy6A9UAEQAbQ
#@jwLZf6D8cwGc5xXAucjw7NxKo7sCAI3VdHVwr1yRLv2dnQGRrwC4ABT7gHJaAYybEPLPBbAegABs
#@DDBv4lIvAvgkKgcccL/WNgOgAwq4WE43Cms2/bL8O+t+wRBWAHb5lwVgkX+wHoAA9AYAQv4vyQJ4
#@OaIVABTgjAI2eAWAr+I9w9LVwaz5Z/HH6wE1/1GtAGQBKAoAy/wTQv4DFYC9AYw//h4CuNxRAUTl
#@1eJ4pqsCAPIoIN0ozDb9smv/tO43ahUABJAVBaBdBJDTCmDcjJR/vQAqCgFYGkCo/nsTQHQgB8w1
#@uisAvDWWEzAKWNlv/E+z5p+O5smZ6PFPCwEMPP+gh/wrBGBhAAa7EZAkACf/AAKIWvrx+eybGgWf
#@KoDWWxJGAVOH7Df9tmr/6DX/vAJwmwCTABQdQE4rgHEBIf96AVRsBGBvALoRkFwBIP4kgMjx7A5G
#@Ad04G4XPldInChua/0cs/lT9H5uZuR7dCmA2pxSAlH+tAMYlhPyrBVBRCMDeAPw8zlD5bxLAebof
#@EAQQUS5mNk0YNgqnjxH6LYs/HRFs/uGjVgUwi/jPygJQFAAh5x/45V8hAHsDdJ+/JAmAVwCvQQAR
#@ZbVhLgIac4V0o7DHpl/Kf/M0whZJBbQqgNx4FgpQCCDPofzrBDAuIuRfK4CKhQAkA8gKoNPsjNv/
#@SzOASAsA8NXBROZ4OfZFwN2fqx7248af8v/0OpJ2PYKH8/oHCoDseLazApjUCYDyrxXAeNACqGgE
#@YG2AS4QogGljBfBihGcABFYHm/uAc/G/Z1hhRrPul+36HbmBpOEvshVAFpcBZnNZWQB5vwJgMPkH
#@PvlXCMDWAOy8UQCAzwCGoAIAfKMwUbv/Sfw3Ch8/pnrYj/v73zwxA6JaAcxcxwwg57ycwxVATiUA
#@yr9WAONBC6CiE4ClAdh/MAsA6R+6GQCxSn0A2yrYuF1I+Org17+SL/1RsR3lGUDWXQycNwkg7ycA
#@i/wHJ4CKUgB2BrjEEAUAhm0GQIxuCPcM20nwRmG27pfy31r3ez3iYAYwm8WRdSuAnCwAsQPIaQVg
#@m39Czr9WAFYGuNSFLADEX54BDN8oICn3DLswIzf/vPp3GHlvN2ERPqAnpwJoXQikZwPkugWAjw6E
#@/GsEMB60ACpKARRY3nUKEP6DJIAhnAEQyx2jgHSj8BXW/NNf89T1IcCdAaAIoHuD+wkgzwk0/0DI
#@P5DyrxRAgQSgNwDuH2jGQwDnh28GQHxRExSwUkjcY4T+8BWr/in+uPQ3FPAKAAZgAsjLAqD8awUw
#@bl8AEEL+lQIokAD0BsBpEVkA7HYAQyOAO+fOXU3yKKD8tUfzT1cAtz/gOYv0DIDGAPR8MB8B5Dmq
#@/IPxoAVQUQqgQALQG4CfZ8H3EAA6gFb+I98CcAXIq4OfJegxQr83NP94/+rwsMTfOAPwrQBU+QeB
#@5R8I+VcJoEAC0BtANgMF30MA5y+fb28B7gzPcWc1yaOAlfZNv7wCQPM/POAyIKsAcqwCyPsIYFIr
#@gImgBVBRCqDABOAJzz8hl/6yANAAvDx0FQBwFCCuDk7ARuHS238Z4dnHgUd9volcDVsFMC5XACQA
#@Mf+T6vwHLICKUgAFEoDeANJ51vuLAqBlAA7Pb94ZIlAGXM1Io4A7pZg3AQe2WfVPnyM3EKpXh04A
#@dBUAsAogzwWgyj9g+bcvALwFUFEKoKASAOD5J8wCAKIA3BGAI4Bh6gHggHO3G0kcBRTfcar/R6bm
#@v3kCkRrqCgDkPQXA8z+pzH/QAqgoBVBQCgBQ/jmSAIAsAOR/2CoAcsCX5o3Cm425tXpcLwSelZr/
#@T68PIWwGwCsAwAWgyD/Q5N9eABWlAApqAQDKP0ctAKoAXnvxteGrAPBxNVmjgPrFD7b3Nvqx5v/Y
#@9eEVQFaqAAgh/1oBTPS3AAAs/0oBFJQCIFj+RQW0h9+zAnjeEcDwAQXsCJcEN0bvxG6j8OO3nxqa
#@fzDyAtKUgArAPv9BCqCiFEChjWmdAWQ1SAIAxgpgdwTw2pM7w8qcNAr44lmsNgoXf3666fb8eNG/
#@mq9TnoZ8BpDVVACTWgFMWBcAPgKoKAVQaGeaDGCLLIAj+ON7AVt3BIQAhpdvhD4gThuF63OHR9ri
#@T+FH9f90aOPPrwJkvSsAln+gzb99B8Bg+dcIoMAEEIABuvp/JoA4VADAY3VwMR7xP47m342++/tP
#@zX8cKoCsbwVgn//gBFBRCqDABBCAAbgAQAwrALAirg4+F4ONwmu/Ys3/ngNGaN3v0M8A8HQQ7wqA
#@5R/o8h9AAfBDN/9KARQY08wAVngI4GAcKwAgbxR+NuR9wN0vTzVZ7kFr3S9f+Te0VwFwVyC/CsA+
#@/4EJoKIUQMEogL4pwEMAfAbIK4C4jQKeOKOAtfowN/9HR1j4qft/iuo/LhUAEutZAbD8A1X+FQWA
#@XgAVpQAKggD6WQTIAjhPAohRBQB24rdRuH7mQzT/lP32+G/fODb8uDMA0LkOYJILwDb/AXQAP6T8
#@6wRQMAggAAMIAkD841gBXL1zdaUhjgKGcnVw4Wve/JMDmmeRn+vDfrhXARzo1qBGAbD8A33+AxJA
#@RSmAgigApPSv/UIQAMU/fhUAWI3RKOCjL+lhP5zmaSc9ID4VwASNAKkCmOQCsM6/XQEgC6CiFEDB
#@xF7+mQGs8BEAvwoQB66aVwc/cUYBK+X6cO37vzFiTD8u/b15LBa4MwAIgBRgEgDLPwgs/4oCAAKo
#@KAVQMEL5ByEJ4CcxrADATiYOo4Azr24L1f/IC8diw95VgHFUAO1XASa5AOzyDxT5VwigohRAwcxe
#@/kFwAjjIBBCvCoCYG/qNwsU/ftoUmv+Tx0CsKgA8HpBVAEwALP9gwPknAVSUAigIuPkHYQogdhUA
#@EO8dvLxWH4ZNvyek5v8pr/5jMQOAAjorgEmjACbbUOUf+OdfWwA4VJQCKEhQ/j0NMD29DwH81VsA
#@ABXA1VghrQ5+spmJ/CigfvHGiFD9b793LF607wak54MaBWCZf6DOfwACKIggn34GQIr1AsCnpwBw
#@OwAIIGYI9w5+sjEa7XuGfX7AfOkP634pN3GbATivzgpg0iSAyXYCzL+iAOhFANdcARRkpo8wTPkH
#@+xHAtCgAGgFAALFjWRoFfBPdjcLF/7giVP9o/mMqAFcBwCQAy/wDn/yrBfBujwK45gqg4MGRbgz5
#@B/sRADiSsAoASDcMiuo9w+pzZ6VLf2j+YyoAMN5RAQAugMkOBp//HgVwzRVAQSMAwPNP6AVA+Rcq
#@gNdiKgBhdTDI7JQju+k3Ac0/FwCbARgEYJN/oMi/KACWf+Cbf1cABZ0AAM8/0T8BIP/xFQC4LW4U
#@vhOxjcKPK1Lz/9UJhCXWAuhYB5DjAuD5nww5/4DlvzcBXHMFUNAKAPD8E/2tAJ6PbQsAdsz3Dn7y
#@pHE/SquDS1+clpr/K8d+lggB0AyAC8A2/0CVf9BD/oFv/kkABb0AgDH/YD8CQPyTVgGAj51RwBN+
#@QAHR2Shcv43mX67+k10BTHJ0+Qc++dcJ4N0eBXDNFUBBLQDCnH+cVwtgN/68AmBDwJgqILMZ6dXB
#@Z97cli79HUVOkiAAmgGAyRwXgCL/IPD89yKAa64ACgoBcIz5d+hdANPA/f1PXAUAbjeemIjEPcMK
#@61Lz36TmP1EVADUBugJAzD9Q5l8QAMs/8M8/BFBQCYBjzD/oUQDTTAAJmwEQ92so/NnhvAa9UXjq
#@/kl53S+RqBkAF4Au/8A+/xyWfy4AOf8QQMFCAEDIv78BaBsAYBOAZFUAYMdZHWyuAhorhfrgNv0e
#@lZv/+MMqAKMAJjm6/ANV/oFv/gk5/zYC4Aj59zVAe/6ZABI1AyBWMvjNZ4dzZnCjgHsfis3/4QTk
#@n80ABAGo8g+s8y8L4F1BAHL+K9YCACz/PSqA8m++BpCsCoBWBz/hQAIDumdYeeGpVP2feg+kFQBW
#@BTN0+Qf9zr+/AK61UbEWADDmH/QkgCPCRcAEzQCIb9gogBzQWA57FDC1/PpX0rrf95KB7wwAH6r8
#@A+v8SwJg+Qe+v/8HbCsAQsi/pwKmp1sCOCIIIGkVANj5mI0CoACAJwqHuu73xrbU/L+AcCSzAsh2
#@CGDSgC7/wC7/gOWfCUDKPxmgFwGsHfGFoqwwgFs1iBUA2wyUAD7G6uCOCoA+N0bDGwVckDf9nn0v
#@MbDLgLNMAIi7Lv/ALv+gx/wDn9//So8VwBoE4AuSbEbMv78AqAL4OEncb3RXAPgMa6NwSd70ewXB
#@SGgFkIMCSADAIABd/oFd/gHLv48ArrVxoOIc/gJYgwCsEPOP9PsI4Pnnn0+YAHY+dlYHmy4IOqOA
#@uc/rgVf/yyekS39/fy9ZsAogyzcE4ot//tUCGPNEzr8oAKH/77ECWIMAbBHzD7gA+D2BIYBkcfVv
#@uCTICGUUUL91Q173+16SBYD42wrAPv+CAFj+CZ/+H4dvBbBmLwDgmf+DkgBA8gQAnNXBBgU4pzYC
#@3ShcuCau+30dkUiyACa4APDFtgCwyz+g/MsCEPv/XlqANWsBEGL+Ef60ApBHAVwBjS+CGgV89I24
#@6fdTBCLBApiFALJWArDPP+g5/8Cz/++pAljjArBArv+R/bQC4PBRABHUE4Vxx6/00p9ZAOOz2Qku
#@AHyxLQDs8g9Y/gUBiL//PgJY4wKww6v/TysAA/IoYKfY902/HyR63a8sAGApAPv8E0L+fQQg/v77
#@tABrXAC2sOv/BKU/rQC6mBM2Cvd7FFCoiM3/SWQh4QLIzk5wAeSAZQFgl38g5x/4/f5f864A1mwE
#@IID8SwIAaQXA+cbcB/T1nmFTX55qeq37TSuAQARgXQCw/AsCkH//vWcAa5YCEPAWwMtpBdCFsFG4
#@b/cMq98+LDb/rUt/qQDGuQDoS1gFgCAAOf9A+v3vqQJYC0IAwFsADmkFwMDqYBPYKBzopt8TiEEq
#@AAe1AIIvAMC7PQhA/v2HAkQBrAUkAKARQFoBgNXGEyO10TuWG4WL6+Km39MvJBxZABT3EC8BADn/
#@ogDk33844JpYAawFJwDgLYCf/CStABi/E0YBm3b3DJtaRfP/rbH5P5p4ghWAff7/Vco/4f3773UV
#@YC1QAQBvAVz+X/bOAEKOK4zjBS4ABoNlCEVAeY+VUADMwsomINAIobfVJkCLahkoYUsvKAhCNBoQ
#@oqARAJyt4MIEFIxF5JwsACiddy9z37xv3zdvvsm+28P3u+v1CID/b//ve9/MoQZwIBzAOcDl0u93
#@B/+l37M3fq3cr6O9yUygBdCkfKcFQBMFACA+/8MNoIwmACAogGvQAGoBCA/Hl95tdRRwrz78N+F3
#@eX1r9uOMQgQA7LIAaKoAAPTnv8HOAX0CKDHNxn4MaAFYRABnLF9Srw9/8+0D/kO/T9c2/qgC1Hu/
#@sy9mAkcAOygAOlwAUuLzHxqAfwhYbvAxpbsQwMgI4MOBYBVAbAez3xl2Yt/4tUINwF79CdEFsIX8
#@hwtA2n3+pxpAuclZSLee/IAARjXSAFo8XJDbwYvHrId+bfrhp/063JvPmIgAdlAAdJ8CkBL7//DD
#@twdQeoB1/e1/9HcKwI4Apv9CAgRiO9i8M6zndvBd+8YvG3unAaxvzwQkAEuXAK5sED3/vQpASu3/
#@2/+sD7AASq8A1BkRun9XA7g2rdmvG8ByKd/m2/CC2gp488eD3m/8Wm02gDX/6k8EsIsCoA3hApB6
#@z//dDaD0olQcAyiAagA1aAYgLBfkdvCj6iS093trrx17UMHR+8lM4Akgev4BOv9hAeD9f2gAWACl
#@H+UQWwCoAXhmAMKYHAUsO0cBXzeHf9QA5PB/wQWA89/nBJB6z/9dDaAkUC4RBJD7BTAdNUcAhNCx
#@HUyOAh4/Pzv8Ow2gbv93ZkIvATgS2EUB0L0LQOo5/7sNAAmgpFCICALIc/81oAiA5AXzQeHrr+6c
#@Hf5X0AA4e78igCy+AML571kAUt/5HwpAgRtASaI2iCCA3NcALO+WPgR6FFBuKODk73lz+Lc/wAJy
#@+B8ugPMuAJpRAFL0+Y8KgAUEUHIEoCIIwMYfngWABuAVgLBYPiO3g++j7eB735zu/a5wA1gdvr05
#@64sIINuNACD/nAKQovM/KgBIACVPACq6AGAGIAIgWfxFjgL+u946/JuHfm3qUQNY/zQTKAE8CQvg
#@fAuAZhWA1Hf+fw4FoGgLoOxCeYkhAJP+9gwgJABhQW0Hw4PCJ89uv22y7zSAwN6vCOAJEkCGBXDl
#@XAuAZhQAK4A6/KgBQAtwGkDZifITRwAGxgxAWHQ/KHxyf7L3MfEQ/iF7vyKAqwEBRC4AZP5pARRN
#@+tEBoMY5ApTdKII4AoARwEgaQB8ObtDbwT9Xv/5z1OS/LQGz9zvpQggL4FwLgO4vgNRSoE9/NAIE
#@AZQBckURTQBwCRgWgHDwklLA7eO1DT02wPp4MptwEAFcDQggbgHQ7AKQbp7/oQ20BVCGyIcYQH2i
#@AKQBMFiMvVeCZvDvy7/Z+90+IoAsXgHQ7AIADcA7AgQBlCGqfIABgv1AkQJoDgA1VgAfFkGERxuj
#@AFv9PQY43Ls1YSICMGQ1uykAukUo/yCAJv5IAYUjgHD+jQC4CgifEJQFCwBPAAwigF6g7eCjw5WX
#@QYd/EcBlWgDxC4AeUgAS1ADs/xCf9ch/lbMNoBr4AvgeBDAdiQBY/Nm+Eqyj7vs6Op5EQAQQswDo
#@IQUgSYrPPfP/gimAqia3KJKucPMFgBrA/v67hdAHZxRwtPI1gMP384kwQACXNwWQsfM/sADoIQUg
#@MQLwPQPEE0BlyJkGUA5DBVDn324CywyAwQ/NdvDhylMBXt+cCNsRAPwauwDoIQUgqSkKeP8fXACw
#@BFCBAPorgDMlMHznF8BUZgCDeGVHASbwiPWdiTBMAJcpAcQvAHpIAUgMBWz+Q/JZAqgsOcsAvDGB
#@fRWItwHYGcA+8xZAGJ9uB69qoh3+RQAZFkAWqQDoIQUgOcUu/DkNoGAJoEICMKiQApSXTgEYOhqA
#@zAC4mO1gE3/n8L/Fqz8RQGZgHwAwg/MfEEBiqRNf4OhzBFB5BBAsAYqiQwAWYgYgDWAINy65M4DX
#@X00iIAKIXQA0gpP/xKQeXgPGFkBFCKCzBKgOAgJAfxYMbgFkBsBnPP6t3QCezgU2HQLIaAHEz39I
#@AEmDu//LFUAF5BhFkatOegpgC7cAwrzVAFbzOIgAsqgFQGNY+U/qAgANgCuAihYAbQD4J4qgAGz8
#@0QxgLLCZQwMQAWxVAJmNu/OGsB3knxBAAqD4swRQIQFgiPwzDNAlAHwLMBbYRGoAIgAIufk14hWg
#@3oCRf9QACqYAKloAtAI67QCEBfCLNIAL2gBEAJh4BwA9pAAkbdD6L0MAFS0AgMx/WAFBAZwCtwBj
#@4cI0ABGA44FoBUBzBQD5hyPAwAZQ0QKgFdBpB4xHAF9iAYw+sQGIALbeAEQAV7EAwgUgev6BxAUe
#@AuA1gAqTU6D8cxTgCADy3xLAdHSxZgAiABHAqQOwAGLsAOkhAkgQMANkCaCiBUArIKCHLpxLQKcB
#@TJs9gPEFQAQgArAOQAKIUQD0sAMAArLPEUDFEkCO8s83QHsLsMZpANOL3gBEACKAbPsF4H927kAz
#@kiyMAvA8RIRuUK9wMVlaYBcFgh3BwIzB0goXkF0YLDRwQR6h2XcoAJZ9ixHWvkAeYSe/rexN/so9
#@XX/9lbrhnBkYqgc4X597k+5gAED3XxYAPAKA/kMA2rz/Kqj7CoCKFgABIAAhB+BWyowBuFB5lf5r
#@AHT7MQB/YwB0y4EPBQDaFi+APRcAAagAgNsHABoFgP8BIBgAUP0ffg8AA4D737dzAgBouQCWyccc
#@gI/Tw9wfAwbAfwAY+z8GgAQBgPsPAQBBAOy4AAhA7QDcCgCNAkDHqf8YANB/WQC/YwBw/zEAKAAA
#@CRdAnQAQAAkAwOcG0N7/cQBw0jvcfw2AIRAALoDqASAAjQLA+wAQLABI/00ApPQO918DYAoE4JIL
#@oGoACECjAbjwGwD2/psBSAIA7H/f+gQBIOECqB0AApDX3XUAhEkAgP5jAJIAgPvft045AYCb2hcA
#@ASAAed0tA8C//yYA0gAA6n/fumUMgFYDUP8CIAAEQNruOADCi7H1HwCQJO9A/w0AAALU14E/B+Bw
#@UAvgV2ZyCMBrA7B8/zUA52YA0gAA7n/fuibrfwmAbAEQAAKwFgDH2yEKAGm40wHAv/8AgJQDAPrf
#@t84Z+l8EYMsFQABWB+A4BkDedq8BECwAnJsBSDkAqP99656TALjiAiAA6wJwxADg/ud5rf4DAFIG
#@AOg/AMAcAaAtArDlApiRDzkAH5jpuT8eCwBcGAAo9N8AwLkZgJQDAPoPALBH+o8XwJ4LgACsD8Am
#@ByBve5X9BwCkHIBi/wEAu90sANodFwABeBMAbJ4CcFEAwHAACBYAzs0AJAhA/yyq51lx7QDIf8AF
#@QADeGgBCwBAwAFboPwIgQQD651E9H/pvIEALAhbAvq4FQAAIQJ75N4DBAsC5GYAEAehVRmu+e4wd
#@gCGlBXBV/wIgAASgjv5jABIEoNeRfpbK6wBApQuAABCAgAGwHwCCBYBzMwAJAtCPRNc8765dgLz8
#@vAMgAFUCEAIGwHQA8O8/BiBBAPqx6JrvVGYCIFEADAvg58lhCIALAMEIgH//JdJ/MwAJAtCPRtV8
#@N5b5ANy8sABWAoAAEIAwAsATBGYNgABi6H8JgAQB6BEAO9X/LPMBkNSzAAgAAdBHgAYAsHT/zQAk
#@CEAPAJBIb20E7CAAUn8uAALwpgAwHgACiqH/BQASBKDHAMCgN3wIwEP7HRYA8ykH4NP0MOOXgI0C
#@wHgAsPXfDECCAPQQgKGrJgKGumMAJDUuAAJAABoAgF//w4z+awASBKBHAAxVNQqQP4AB2G65AAjA
#@GwDAOgBs/TcDkCAAfSHP+m8iYJcHAyD1r34BEAACYO8/iL3/GoAEAehLUf1XAkACRh/AAOyv9tUs
#@AAJAADYGABbvPwYgQQD6YvKe2gjY6UAAJPv1FwABIABBAzCkwQPAqf9mABIEoC9npP+YANV/lRMX
#@wPW6ABAAAhD+A2CjAWiapQ8AoP8YgAQB6EHyllpGwA6kAMBDrgkAAVgPAIkAsNEANAYATP23A5Ag
#@AD1KVlILAcXio0tAWQC/MZMzEwDmMwZA2r7gAMD9xwAkCECPEi9V/6EAGQHonR8vAAJQAQBcABsF
#@QPavpftvBSBBAHD/4/BhXRMBYPpLcgB+4AKoEQAugOAEQDghef+tA0AASBCAE/ofL0FmAyDRAMgC
#@uOYCMOVzDsBnZnIwAI3EYQDg/hsBSPMBiAAAiQcAN6MLYM8FQACqACDkAORtX77/hgEgwf3HAEQM
#@gATV/AQAJFwAjgDcDX9nA0AAwgoAgP7DpPkAxAEAHPQ2DwGQC8CnAOw9FgAXwN1cAAhAeA5A89j2
#@5fu/IABdGYA4AQD8Ln8KABKvBcAFcCcTgAvAG4C86979D4b+WwHoygBEDAAWQD+AAeAC4B1A1QA0
#@/gDg/vsD0JUBiBgATIB6AAIg9ecC8LoDuOMRwB2AJs9i/QcDAAf3vwhANACgG65yGgBXEi4ALoDV
#@8mUUAB3nAwDuvxcAXRmAiAHABKAnsv4rALgAZgJwN/wxAcAsCwDuPxgAOLj/BQAiBgATAJ/I+q8B
#@kP7LAviFmZyFfgrABXCrAPAcALj/TgB0ZQAiBgATAJ4oAPDkBHBtAIBxWgBcAMenANwqAJbqPxgA
#@OKj/BQAiBgALAB7BAFzJALi2AMB8yRfAF2Z6RgGQrwWwAeDcfxzQ/wIAEQKAs7vE0QCoO8BrIwAE
#@IFsARgAIgCQHQD4VrADw6v8Z7r8PAF0ZgIgB8IsGYLvlAvAAIBOAbTbk22kALNd/MADsAHRlAOK6
#@AGy39S4ALgAugM1SAJyd4f67ANCVAYgqS5dfA8AFwAVQJQCb240CYKH+gwFgB6ArAxBfH4AhXABc
#@APUD8FwA2H+Jd//tAHRlAOJIDofFATgcuAC4AKq/AxjSlGPq/xnuvwcAXRmAOJbD9ywOwPf2V74A
#@uAC4AAIAwLP/YADgwP5rAOKLABxeAQAJF4BPvvovAC6AcAoAGx17/50B6MoAxJcAkLwKAFsuAC6A
#@OnJvBMDU/zND/1FA/zUAsQzA4VUA2HIBcAHUkK/3fz0XIAAAPPsPDwA4oP8KgFgEQFLu8TwA3v8P
#@wBUXABfA6vn2CMCTTwRJPA8AZw+B/XcAoCsDEBEAkmKNb2YA8F4D8LgAfmImx20BcAEczQDY+48H
#@AA7ufw5ABAAAAYaf5DsCsJf+GwEgAHdZvjLTkwFwxAD4998ZgK4MQMQADCn0/yFOAAwfBjYDQAAe
#@B4ABAOYPBUAmgNsB4Exi6T8O7H8GQIQA5Cn030CAvFIDMBwAfrQBQAD+8VwAXAB6Amz8+w8OAHYA
#@ujIAsZiDSqH/0wmQV44tgEEAAsAFsPYCOB7VBNhgAMz99wagKwMQIQAqo/23ESCv5ALgAvDMn/+y
#@cwYQjmSJHwYMwBMzjemxZhdGxf6t/9DGipiJwDIDeiFjCOgai4G7WxqHQ+4YhuaaA0CrgSSAu4NB
#@zySr9eq009BAuqEJvc1FQooAV/V6fps3Sb28eq9eVaUq70s63Yez4PvqV6+65/rOcHh8ddHf/Hp7
#@+9Xz54WCRYhVKDx//mp7++vN/sXV8XB457orXgCLAaD4skN7df8p9zQPACD0HwF4IxUAwPMfhLn0
#@IwBaFoDBLID96+HZZf/xBglDkXhsbPcvz4bXe4ELgEnAYgB8oL38DYDYf30B+Gl5AN5IBgBw/Qeh
#@tj/9NAvALIBo7F0Pr/rbG0SNIg3B1fD6/RcL4IgbAADtEYCV8B8I/EcA3sgHAHD9B+IAALMAzAJQ
#@5LfTs4vtKtFC6ZWfgT9T+jQAogIgBPL+x3YDAIT+0wC8UQoA4PoPhAGg7psFYBaACt3zq80Nopki
#@2di8Ou+KAyBE3X+NAfhpeQDeqAYAcP0HIQLgy28WgFkAUpwML7eLJC6K5Pnz6lwAgK/2KvsP4H9c
#@AQBc/0GYAICABfBlAAxmAby/c9a/RxKgWKoeBQUgYAbgjwUl/I87AGL/36oHQA7+8z82AOIFYDAL
#@YH94cZckSLFaP2IKAHhXe2EA4vcfhPD/bbwBECTgr0wAoP/CAqh4AfiXQZr37AJ4nxeujzdLJHlu
#@hwD0hekc2VP3Hwj9f/c2kQCAhQHACcAL9m8BPFQCYHjPLoBcyL83xO5PherR3ASgH8G2C/xPKADi
#@639SAQBf+s8NwC1YABUTALMAfPstkjbVOhwWXu3T9B8Ir/8JBgAw/gsC8Jr+cyCvlReACYBHXhbA
#@6YVFVoLiwg5YQf+B6PKfcAAA/BcFwNc/2hmAuQUAmb72n18USJGsAmjAXALk/E87AChACgEA1H9x
#@AHz9o5wBmAVwhXd29T85/oqsHEVrly3AqvkPltjvv2I9AxDwM0W8AOgRgAmAWgAYMnvx7xfJalJi
#@ZsCq+Q8E9/8pLQAQJgA+JgDrGoDryw2yytQPovi/m04AMADSDAAIdQtgFsB6BmBvuElWntLRSvoP
#@ll7/f0o1ABCfGwD8g4BmAaxlALpnd0kmKNZ3Ff1PLwBwP1oAtnQEwCc4ABgAZgGsYQBOrgokO1SP
#@FPyPdQAA0f2/agDgroYAUPhnAFgA/zZIk9kA3OmXSLaobqyW/4B7+Y98BgB1dQSAys9ZAHgKYHSW
#@Z++SYS8r4NY/Y5QKQv93dwX+JxMAqK8aAJgLNAWA/8fAZgGsUQDen2+TjFIsCPz3gf8xDwDAf/4v
#@FwAnUFygLQD3/S/2b4HNAlizAJx+TUDeVsDuLcn4D/j3/1IBcJxgb4G2AFCo/zgDMAtgfQLw/nST
#@ZJzSEd9/IPY/ngBgAMgHwHGcLY7/IIYAvKb8aBbAugTgtE9A/lbALkv8TwBB4PX/nWQAHA84vug/
#@0BkAYJ4CrE8A7vTJdyQXlDZE/sd/AwDE139xABwf1vEtDnoD8AC3AGYBrEEATi6LJD9Ud1n3lfzX
#@HwBc/2UD4FAYx7f4aA2Apz+zAP4kjSEzAdg/K5Bcwf6t4O4CG/EPAMB5/i8RAAcBgOJbS9EeAOq/
#@CUCuA3D+iuSOYn3Rf+DpLfZffwCgvlQAHAQgNPoCgCOAXC8AE4CPfZJLShs8/30E/scQgLe3rwVe
#@LguAA7Yk0LwAKjleACYAJ5clklequxz/KbEOACC6/3/59uWyADiSAQAaA5DrBWACMLxLckyx7h/4
#@fT73Y/2nxOk/4B//owDLAuAoBADoPQN4agKQxwB8iHf9H1XG0+nEdUejdrtcLvd6nZubTq/n/Thq
#@j0auO5lOx5UjEiclqrnvPwqwwQD/4w8A9f/dov5LA+CoBQBoCAAeAuRxAZgA7A8LMU3vyq+e9u3m
#@TSg65ZGXgvFBXM8DNmbXeeo/S2wDAED/wDuAl957SQAc5QAAswBMAPhcbxLt1McTd+SJP7iRp+l1
#@YFyPYwRs/K75zH8Qk/8A/nP3Pz8ATpQAAB0LoELPAP4ojWGVA7B/bBGtHExdtywQfyBMQ6fsulPd
#@Y6AKzcNR0Ejg+R/0XxoAJ2IAgK4FkCszTQA+PiYaeTR12wFmD9ifvRd+ElJ2Jy+KekdAWgHA9f+d
#@ZAAcDQEAYQJA7ecEIG8LwARgf2gRTRR/nvibXz/N0WSsLwLVhP0H8J+jPzcAjp4AAFEAcPkPDEAl
#@PwvABACH/9/pmv077OVeIwMaAX23A6VCov4DXP8lA+BoCwBYGoAv9//8GYBZAKrsXzLsrwznd4kG
#@iuPJqPP5pn6gHwSl03Y1DQErjQAIrv+cADiCAGhsAOcAQP8CMAHYW41X97Kow363SQ0dxAkysKOn
#@AdVCov5jASAB4QPgBHB/K54EwH9uAHK1AMwC2Pv4LYnME3cHl/5EoDcDGhpQrCfmPxBf/xcD4ARx
#@HwXQnAD4vxiA1/l7CmAWwP5ZKfq1f8dXcpAQN/Q9uN0B0UdA0gHA3/9KBMDhBAAJ0NsA+B8YgB/x
#@m4D5WABmAXQvSTQOJu3BTccT0v9KhI7/xrfy5GG8Z4EFzVii6/9iABxeAIQJ8F2WTsATfgBw/c/L
#@AjABuN6OevHv+fr7rxQScOMfObbcaSm+Amj3Xz4ADjcAwgQ8ocjNgK1lAcAzgFwsABOA387vkQg8
#@mpQ9Aan8qS0A+tRhx30WKWPWzPbY/bcE+i8EwOEHACz3Xy4BW8sDAP/zsABMACLd/o/dzgD2J7cA
#@ABJAf/ZwxxGfBsD2WANgyQfAEQSAIvBfnADg+c8PAPNbADQA/5TGsEoBOOkTdaajzo1vHsDPSTLA
#@f5bugNG0FO02AJbG678l1p8NgMPn/hZeiwmA/xIJwP+HE4D5fxHwexOAjAfg0yuiSnXa7tzcUPPw
#@SjAB+M8iAfTDT0B5UieqFAsz22P1Xy4AzhLuw34kgOc/ZA7lP+AEAAvABCDjAfjtdIMocuDu3OoO
#@71NaAFDf+8DXjnugfhBQWChAHP5bQv2ZADjLoNqjAPQby/1Al+X8NwsgvwEYVokaR5NmpzOn3iAd
#@+fEj+72pnoAqW4DY/JcJgANEC8D/mkvAosqiBMxt/7gWgAnABd776XFcVLz6U/1XGiRArQBAv/9A
#@rD8C4CwH0s+vAPrlvdj3fQax/zDfLICcLoDuBVGiPtnpZICdSV31KHCGfv9lA+AIwHUfdwJ4z/nv
#@vajIogYED4agBVAxC0CZff/KDzJ2/F9def3BYGdSjVwA3f4D1n8QFABHBC76sB8R8ITfgv7IwQI8
#@/xcCUKtpXQAmALgHSC8A14+JCr+2Oxnih6n6UaB+LAbB1R8BcIT4ts89CWCbgLf/CoLn/0IAqP16
#@F4C5BUjxDODjV0SB16NOtrgZvViZAlgswus/DYADRAtg8TaAAv0RAEEDnogC8CCGBWDOALopvD7e
#@VXry1+tkjUHLfRilAPW6Xv+ByH8aAAeEOANYuA1gxwBtAB/4Lw7AA89/BOCbCAEwZwBp3gJ0908L
#@RJoSbv6zQ4t+NidV5QLUPbT6D+B/9ABAf3YKsHhiIwlLgP/CAEB/cwugawEkf/lX8n/chlHZS0B7
#@rFQAy6rfotF/AP11LACYjzd7/aefT+hPAp4swvi/EIAKXQBPn/73P9IY0j0D6J5bRJaq24JNmWyA
#@e0SkqVoogKXTf/0BqM0/AsQBABDdAgCZAHxDjwBMAJTYxw1AKmcAwxKRZVpuZZpOq/yrUgFoArxP
#@bf4D+B81ADb1E/5/cf+PDEghEQDqvwmACl08BfRf3YSR9//A9RXKsP0d/9N9qFgAy0eX/wD+RwyA
#@bVP96QrAQWAN2mIMyBF/AAxdX3+w8v5Pd6B/piPQ2ZmqFABo8h/Af9UAwH/7VlD6nj//V0YiAM9M
#@ABTo4uqf+AKQ3/8HLvTPOp2Be5BGAawg4H+kANg0AEFXfHxXJuYFYAKQ0gI4t6QP/3PgP+iUx8kX
#@wArkpYYA2D6fDaUjoMZe+hEEZQRPAcwCyOACkPbf7bXyhVtNuACWcgAaggDYFCo/ex8A+TWCADxg
#@A5C9BWDOAGSf/z8dtXqtnDGqJFoASzkADUEAbASAggjM9N+KOQBYAH+TxpDSAvi4QaSYNFu5ozNo
#@ThMsgKUcgIYgAPZnZlf+Gn4CW3rUFywAo7M86SyAT3dlf/en18rXAujRV8utExmK6gWwlAPQEATA
#@BswC8N/0pZGazwv6ZRZAthfAp6+IDJVRr9ei7xxxG4Cb0VO5AliKBbCUA9AQBMC2AaTHAsCZwJbm
#@ADyYBeBHswAyuAA+PCYyjMu9DvUlh7QGO+MkCmApB6AhCIA9Y6YqdgA+tAbgAUAAzALI1gI46cv9
#@5R+u/fmk1XOLsRfAUg5AQxAAm2E2/vHC/6xpDMDv9psFkNEFcEEkOHLzrP9t20YHUkWUL4ClHICG
#@IAA2C3P9h/3w31NXdwCgf6QFYDhJfAEcEwmetfPsP2g/i7UAlnIAGoIA2IA9A5i33//SMQNqlPkA
#@fKNvAZgFcNKNn2FR7vZ/LSiP9RSgLuM/EPvPC4ANAp4CwH8sAPoRRwAqFLMAsrEATk6rJDzTZm9N
#@kPuNgCqnAPV6XcJ/IPafEwB7Dk9wvHD/T+VnMxBPAL73/DcLIAMLQO4XgCaHvbXhcBK9AHUfaf8t
#@of+cANjz1DzmzwEhvvSNgCAAr+cD4C+AP0hjSHYBfHglMXTd3lrhllQeBTAFsOoUWf8tkf+cANgL
#@1ChUfLyhPVpwS8QAwP+FBWB0lke8AFJ6AFgfHa4PPX/rjOqSxwAAqgcUwFIOQEMQAHuRGpjz34f5
#@2UdDAPQvALMATmLmioTmYORZsV4J6IyOVAsA1ecDYCkHoCEIgB0cAMDoP3cvANT8178ATAAuZq+T
#@eBmWZPxvHa4XvV5rdKB8DGBR5iaApRyAhiAAtiAAvv+QnoeE+vTDLICMLwCJA8Bna3X9B63OLw8V
#@C2BZAQWwlAPQEATAFgWAwtcfyF37zQLI9gLYJmF5+MuaXf9Br/1I+i8DwUIBLOUANAQBsMUBQAFE
#@SAVA/wIwnFwwnMRJX+LX/w7Xk16z2a5IHwNwCmApB6AhCIDNoaZGmADA/VrtheYFYAKQ0C3AGQlL
#@5YfDtaXX01IA3BQoBaAhCICtLQAgdACAxgVgApDMLcBpiYTkUftwjWn2fghfAN5NgCWFwP/5ANha
#@AwDCBQD2mwWQtQXw4ZXxPyTN8H8aVAyeAJYcIfz/v1kAbN0BACL/mQAAswAyswAuSEj+/5fD5jrb
#@702AZvuhxE1AtWpFJIT/swDYcQQAiI4A5/b/wgL4izSGZBbAUOL5f3PNB4BH+N8HqPpY0RD7PwuA
#@HVMAwFL/X8wFwNefXQAmAAoksgA+3SPh+PvIV2Ct/fe+eoPQvxNY1BEAsf8IgB1jAADf/6AAUP9X
#@fAGYBdAP/fv/3gA2eAkY1ZMrgNh/BMCOOQCA8V8QAAyAVV4AZgEck5CMmnQBG3q9UYmEoxS5AEL/
#@EQA7gQAA+B8yAE/NAoiwAEBMATi1SDjcJjAcuokdA4j8RwDsZAIA4H+4AKzsAjAL4MO3JBSlSdPA
#@MEmqAAL/EQA7uQCAZANgzgAuUv0b4Ok/mgaW6f/YOwPISNK0j39AAMpn73A1fTpzpG1srFkuRKtJ
#@R9DtTrTLMDN3tzMLtTcDGuCw0AykAIUGQAFWAICI6TBiWIvAsOgEgjHBdtJ0E+D6kZ5X+qnq93mq
#@6n27a5LnVx0HN7D8f/k/z/tWhzsE5DQAnX8QwI8FEQAgAjApAAU0gAPTD/cK4OqffIn8NP5gPhWA
#@zD8I4MfiCUB2AOYbwIH5AWDXYbHZkMRjvC2HxWo+AxD5X7wAHjxgCaAiAsjAwe0GcGAc7gnAy3eS
#@9zjvjucxBFD5X7wAAM4I8BchNQeoARh+urwTgNXxAYCsAKaB/x7cvxq2nccARP4LIgCAagAS5/T8
#@YrcB9BwO20PJf6IB3g7nUAHo/H8ZAqhdFi1c0gD6DotB5+dOAsLPnYF9AxD5L5QAIPxT54C3rwI/
#@L1i2pAEcfeVwqDU6MxADeJvcPSBgTABrxRWAAgugVvupWNmSBnDKGwCupADMrgBXL21XADr/BRSA
#@+yQ2A9TybAGlAQAHZuFdAaiOZudfePt2ZHsPSOe/kAIAkABqSxLotBxA9b/5wAjwi8mP63AYdrQI
#@15aHADr/RRUAvA18ewu4ufFb+gSIAIAzCw2AtwHc8jo6BO59oO2sBiDyb0AAEGFbAoD4fxbAmMsL
#@yXSGHQBwZloAf2YNAFcdAuGqarUCUPnnC4BIsHEBgAHU1wGAAIDfX/2Nj3Bwk/0bCZicAA7OHQbf
#@jjoEAtwGsGkAOv98ARABzisAZQD8fSAq/5VKZfPjXpoEiADOlAIODMK7AzjwOzTCwOYQQOefLwAy
#@vylCzxHAFhJApQIKeP5Jgs0XAER/wtzvAB7vdxgI+5HFCkDnnymA5Hg/wDDzD2RqAJVSKby8kGjz
#@BXDrFMAYH1YdBqMOowEIfmfkcKhmMgCdf64AxpD5B9KU/lkCcKcEsDEtgFJY+b0u4eYwWQIaPwVw
#@HZrqtc9CYJ4FrmYaAuj8swUA0PknHYD/v4QAtpAAwkopDMON315LvJkNwPwpwAeHQbTvd+RhPX4j
#@tFYB6PynEQBA5h9g5x+jFQAYoBaCAMrrsgpgNoDJx6QAdllXAH0eAhoCeBWAKwI6/2wBKHhRZucf
#@CQD/XQC0A4AhIAyByxeScPYS0GQD6DsMrv2Oz0YYpKwA7CZA558ngCAW7gckRP6pBqAqwCagKkB4
#@IwDg5I1knBSAYq4FYPudL6ToAPvHqSoAfxag888SQBAkje40Kfv/RACui18FmKoAYVgJb1he0q0C
#@BPoqsK0CkHIAEEbsCqDgC2AtrwACLAA+Gfq/iwSwsakUMDUDAH+VI8F5N4DvWFeA0iG0B+wKoOAK
#@YC2vAAJCAARp+78SwJOtxAoQlsJKqDj7XoI+z4tAfdY7AH5KBNY7AdXUBqDzTwsgyCkA9tJg+vc/
#@ngFQBVCUPr55nYhgowH8m/NngPyUCJ3O0EoFYOS/SQggMCAA3tJg+vf/QyWAeAUohaVQEY1XAQJD
#@AEcGPn3eFYDUCI3IRgVg5J8QQKAEYJ+b/E+tAKgKAETR5YWkfT4NYNfSBlBoj2xUADr/hACCuQrA
#@jQtgQzWAhAqgDBCePyPCIAI4MvBwCsBDzxcy4P3HQgUg808IIAgW2ACwAabfCEAloNaXVYD9BtBz
#@aDJuAIUrCxWAyj8hgEAxn/zrBLBSAwNUJm8EhOGUAqLx48oqwHYD4HwT6HXbbwsZ8P1r8xWAyD8h
#@gGBBAnCRAJQB0IXgqQoQhbIKsN0ATh2S6mFbyILf9g+3GRUgnQHo/GsEEGABLLoCjHlcAdAaAIiA
#@8L2sAuw1ANYXAQ2zFwBhaLwCkPnXCCAojACUAdT3AiWuAUACm/291xOEo9NbHOXn3CH5er8tZMXf
#@f8kQQCoDUPnXCCCwKwBiC6gxAAgghApQxqeBQPjgkwqACMBoAzj6ilMAhCJVACL/GgEERRWAKgCl
#@9XI5vgcYc/mDZN9GAzhxSF7mKgDC/rHhCjA7/4QAAoTl4CsBcCtAzADRRAFAeFLfA+47hhvArhSA
#@IlSAVRMCaBICCDD2Z39VAWZvAVQHqCV1gOgWy/09Yc9sA/jVITnOWwBkC/BfsxWAzn+iAIIFCADg
#@VQCIP2WA8PnF3hQigLwF4PTLKwBSAej8JwkgMCMACDJbABglgAQDPCYNAFy+2DOINID/dyjCRjsP
#@gtduNyKjFYDOf4IAAjMCcCewBaCirwTAMED8JECx/nFtzxDSAI5OOAXAa+dDDOANrQugSQggSCJ7
#@/gG+AVT0lQDUEMA3gGJ3ac8Q0gDoFeD2vpcPYWwAxl2AVb4BGPnHAgjMCMBF0Od/ChX+xAqADRAi
#@0BxgZhUgAvh1lS4AXrvt5X3kuTZZAZpk/rEAgmRmxpzMvyJ1BXg4Zos2QElrgOj8HyIAAwI4pQvA
#@lWcA4XDVYAVoUvnHAghmoIs5mX8FRwDYAIq4AdQQUNIpoNJf++f9xKQA/uBQXHu+lw8BGoA3MFgB
#@msgATUIAQSoBzAy2OxvWDIANAOnHBlCngeQYELmfRAA5BdB3SMwUAMG/4gigmkkATUIAwUzImk/n
#@X5GqAigDAMgA3BIAqwARQC56DsXAa3smENqDPDPAtkYATUIAwWzSrPlcBrQA8BCg4h/vAEBItICT
#@VyKAHHxN/zFAzxDCiFUBqokCQHWgedsATUIAgYYUaz6XCcp/CgOsrKwoA8xWQIRXAW9EAPbeAyrv
#@eIYQdspsAShU/mcLoEkIINDhutw1n5sC9CdBdEMANgBMAClLwPNPIgBbE0B16BlDGNIzQHIF2NYI
#@oEkIINBCj/kZUflHFYDoADVVAKZKQFmvgMufRABZoL8KaPXQs4+cBBIVIL4SbCoDNAkBBHrwmG8U
#@LAA0BGgMoG4DqDcDyloDhCevRAAWJoDqwBMMMmAJAFeAbY0AmoQAAgI85psmjwFUAVgvra+XiRKw
#@u/Tm3mBMAD2HQlaARhllmQG2FUgA+vy3QAABxVRnd+0wcwgA4reBUAkAxvkfQ64CRACmJ4Co4QkG
#@aUTsCoBBAgD0+QcBBCTufKANoASQWALWWQo4fyECMHsGsNAVoKwBCQFo8w8CCGjc+UEYYAsbAJeA
#@2CIgihlg/aQuAuDTY7wGsCOPwad9xRUAYYAmQQsEEDBwC2OAjdsdgFkCokcRYnlJBGDuFtBgx9sR
#@DMJeA+YUQKvYAqANoEoAoYAozuXFvRNAN9tP3yH4drQjmKUxmocAWgUWgEo/MsAyCCBeAh6DAZAC
#@Qq0CjqPz7++TADLGf8wZfQlgRzAMfRVglWMAOv8FHwGQAUABygBYAdQcEKPUX5MRQA8o4Bt6AhCM
#@M+ALoJpNAK0vRQCQffxycMIc8DiDAtyleySALny66f6X9V1AFiYAgTcDgAGq2QTQKrYAkAEA9eVA
#@yAArK7gEpFoFrN1ZzCwB3zsUMgEscgZIHgRIAbSKLwAgPgAgBSgDoDlAKSAMCQW8f3YvBNA9yvYc
#@9WQCKOwMAGQTQKuQAiAMoMKfZICZc0BIKeCbvjQAzQ7gjzIBFPUcILsAWoUWAGGASfqTFYDmgDJA
#@loDnn+6+ALIWgD7jDKCxI5ikAQ89A1RpA9D5L7wA3OTrgApsADwHlEt0CYAXhdfuHl28BMzynJET
#@gPH8Cw34MTEDNJv1OpH/OksA4wC6i0LlHxtACWDWHFACoAXQCiifPLuLDaD3+XPatXUPeLgjWOkA
#@QxMCqNfrRP5ZAnj6BHAXhMq/TgErE2aUAFoB3y3d4QbQyzgC0G8CVq8agnl2Gt6Vk38GqI8h8s8R
#@wFMQwAIVAPnHBkhWQA1IUkB4D1cBXUj+5Oe0m40P9JvAjR0rjzwRWQFYAiDyzxDAUxDAAhUABYA2
#@AFJABUi7Cjj74U4JwMAxIHkL4LphCeHagAAAff5pATxVAliMA9QKgFcCZnxfYDkssVYBr+6SAFQF
#@yCwAcgUwagh2ZoDGiBYAZYA6oM8/JQDI/2QHoJh//uMKWMYGQHMAyv96KYQxgFbA8tJdEkBPKaCb
#@Kf/dvzsEhw07CCYOAuuAPv+UACD+0AAQ/Pwayn/MAAkK2NQoYH29XArjRHF6F3eoASgHZMo//SLA
#@oGEN4YkZAejz3/o/Iv+oAag4psivAQFoSkDCHFC7AZWAhPPARwmvCcN3hjXvAt3T3viZkL4BwL84
#@cQiGDWsIw9wzwE3GtfnXCwDCrxoAzmKa+GZN/5QAqBKgFKA2gZkUcHz8r379TggAAAncNICUwD84
#@XeAKQBgZEoAu/3oBPP1MUv4Bbv6B7Od/qRSwmVIBjxIV4C61vnRudgC9iQW66SvA+LO7wBWAcGhI
#@ALr8gwCI3//wJOefUgDdGfg3gJIMkDwHbOoUoL4rCCsAGyC6vGitfdFPC0aASQVgNwBUAag3gbYa
#@FhFq3CUAMEMAgC7//2PvDCDcyrc/vsAChPu3/tXuagbaN6/UDArRdirY8hSTR4bXfVlLGTAL8HgL
#@BQDFxloAw6IjZIFg3ch2I4Y2qMZgSFsM6AbpDJ2aG3g5mdw5mTP53XNP7j3J/W3vJ2myeIHq95Pv
#@Ofnd+wIEUESM+QfC5d9HfgYY4RVAbxMiXwWgAnbXrW8AkP7ZG0CjzX0DqZ4CSDmJWgFQAF+b8g8C
#@YL7/qQCWLhI+/4Dw9z8GMgegAcLPAduToAKu920WgN8AZt0BwA4wXQHYvQT4enMsAD/tJP9BAihO
#@Ysoywudf6ICgT3MlgDkXGOp2Ya0h21fe2SyA8QYQG4DoOeTNIi8ESHlwyAqAmQE2xwLAuJP8gwC4
#@738gVBr5/PMSkHw+mzUp4C6vAM4ArTHvf7G+AYzeGjPAngPcrqQpVWVbJgAKCOAMmv9gARTPw2TR
#@h80vhck/rwCAzAFEAcwqgFXAyssNawXgVwBoAHLYc4B55WNAKUdxCwDzjwLgvv+Bsy38Egebf/n+
#@gFfAKPzwys8BMyhgtW95A4D3xizkuGNAFVVS2KNArADQACT/gQIoUiBrTJYRmn8eNv/AEqsAyD2r
#@AH4OoAqA08GfZAPoc//6jit6pNyv8FvA3CQBAgBI/lEAzPc/4N+YOyyh848w+ecNAOBhAGYO8BXg
#@R59bBbz59i+wA/hd+LKbYTiszI2dwcDzPGfBeN5g8Ox+ZW5E2QICRAA0/wYBFC+yJCd8/hFR/hFf
#@AAC9MogogBgAKgCvgO3h42p/w/JfAeRwB4FLlflk4UHPc5KE13swrw6Qj1MANP9UAPT7nxcAA6RW
#@jDj/AOSfGoDeKnCqAq5eAwWwcwCQ/dzmcwAaPwIcVebBi4GTPAY7lblwFFkAaACSf5MAitNYmi98
#@/in3Am4TBJBbhdESwBsA6P5pZwOAh8KPAMsnFX2eeU4y8eaigJNoSwAUAPI9FQD3/Q8szZ/Z888o
#@gMQf888oACaB3X/b1QDw0ZDD3hD0WH/y95zkMrhdUec4dgF8HyyA4nSWFgPNPy+AbDZLDUAVcIdT
#@wAq9OqiF/Ktf+0QaAH8lwM1D7RF44CSbXkWZesQt4AYKgOYfBcB8/2sIQGGTcJZ/gwKmzwFfmhRA
#@GwBy+d2n0gD6GYZqRZWfPCfpDLS3oFVRA+AF8H2wAIomlhIOUQA7BxAF8JcItyZ4/2fNCqI1AP5X
#@wFZFlZ5jAd4j1QJQqZckDSA3TQAjA2wa81/7jPv+B5Zs4J5AAdcQ+RywvftNzQKiNQD+UqB/VjQZ
#@OHbwoqLKvVgEAC+G/KMAaPCtE0A2iwrgVgHXJpHPAdf7n0AD6DIrgJM0//qLgKMMQxgBbBoFUEMB
#@QPrJ9z9iRf6B8KsAagChAq68+8s3gMvclQB1PQaOPfTqinyYQQA5FMBoCbAJTBVAbUIARcsbgB97
#@fg5AAyBwLPiWcBXwJOkC6E4Q/zGAm8dp/k95VlejIhAAMMo/EQAwvQLUJgRQBEAClgoAY8+uAtZ8
#@LhhAtgpYebmecAG8xofGMYC6Fj3HLh7pCeA4I10C5EILoDYhgKLFDeAewiiA3i2Q3iOAKoCbAwr9
#@ZAsg2giwzN0OqK5D5ZFjGd4DNQEcSgWQCy2AGgrAT75RAVmbDMCvAkwG4BVA54DuczsaAAigLfuz
#@l2Fw6zpUPMc2vLoWrlAAudACqE0IwLD9Q4Y5ssIAGHumBDAKYK8QRN78YE8DEMSfPwfUShcAyKCu
#@RYkXwPJyjoACMBqghgIY5T+YLKCd4Oj5RwX4wacKuAvwcwB/y1Dkan/dhgYAoRbQZgVwr67DuQEg
#@XQOscQIA5AKoTQgA4g8vjAAA9W/wyPknCiDcnWANjwVGVED2cysaQBsk0A75zh8EPKrr4DkTpEPA
#@kYoAashnOPtzAgDU8o9E+zQaADDlHyAHg5k5wGgAoPuHJQ0A8h3uvX2wGAE8c+ykZ5MAagBpAJwA
#@EL38IxHzjwow5h/Tf2eqAq6KFLB98G05aeA5AHkD4O8HlDupa9D0HEup1FU4iSqADSoAyL+8Aegp
#@wBhf4ad5Bdw1GeAOvVUg5J+eBzDEHy8UTpwAaANoSwpAo7uQg4A7jq0M9I8C8gagAgCoADD/2AA4
#@shfQzr8P/+nICrgDkDXAEDCARAGly++S3gAaYRsAPBgB5FQEUBk41lJJiAAAKgA0AOQ/SgNA1POP
#@CD7NrALuzq6AFb4FvP/TigbAvwOFRRwErJBQpRXgOJwAloMFUEMB1KgA2PRTASC6+SdI88+XALxb
#@sEEBgnPBQAnuGZboHQBb/lEFnACWj5sK9Bx78ZoK7PMCGDFdAOtjA9RQALWLAghB1oh2/gmS/JtO
#@BGP+AfMqQHBpAHKjn9gGMIRvAPifNzLBHDbjp+45FrPTVOAwXgHU4hUAoJ9/Cpd/Ask/uT1AUAm4
#@yiugdYErSVkFtCcbQHtEw38y76CCh6kAhAwU/kJiFkAtfgEAOvlnuBcekn9iAE4BxACcAkqtN0+S
#@IQDSADD+De4dnv9YgAAeOzbjLawBAFMFsI4CAAPUdAQAqOWfQZB/rgQQBaABxHPAystvkrYDEOe/
#@/RV3MaDC913PsZrbCn8lcQqgpigAqQMM6c3Ohjj/IACjAq5FV0ChnaQGMKQhGgDg+X8LaAADx2p6
#@+g1ANgOgAMAANWUBSBRgyG42GtICwM4BX86+Cug+T0wDeD1TA/giE8wrhZW35xDSJcCvsQmgBmxq
#@CgAQ5B+Jln9eBCYDGBSAAkAF0IuDmBIAHPySjAYAzLAD4G4IVG3Gj+ekSwBCNSYBjPOvKACBAwyh
#@zcaNVAH0AuGgOWCbLwGX+v9dJO2zAjBE+iNAexEC2HcUSAUwMgDmX1sAgDz/ikDaGQPMooBtXgGl
#@wucJEAAuAX0azPvoP3OZYNxm/DiWs9+MHTdGAcC7sgCQZOQfFYDwcwAagJ0DVoJLQOn9H4sXADaA
#@8aNtem9M/E+WM8Hspw3gAvH/jTT34xMAvKkKgMLnf5EK8HPPlABWAUQAhFLr4IfFCeC1/+xCuGXo
#@CyBtADwhBQBME8B4CVDG/CsLgMLnPwEKQHAPCGD68SLhSQWsjCEGIJRu9JPTAMxbP/pcxAjgOpS0
#@AbgxCKBchvwrCYBnkfln5gDOAIwCiACMCrj8Lgk7AHgKYJeA+/Fj+68A+/FTzbCEEsCmogB4aP4T
#@rIA1UwlABdASAMFn5oD3PyahAcQpgJuvUgHoC6DpvhIJACEC2FQWAA/Nf2LngDVOAVfNCjCXgJXd
#@bxe8A5DCHQQ63I+fQSoAQvMwFgFsbm5EEMDWVAEUCoWsXUD+Iyvg1qwKWO3b1QCYo8B5BQE0e47V
#@DPZjpx6LAOAl7gZQOEWawOj5jZz/uOYAsgrgFXDlnd0C0G8Atx2r6e3HT2QBAJEEsDV8mPIPyBMY
#@R37jzD+vAMx/hFVACS4UtkcAzOXAOQ0BWH4W+HYyRwCgxgiAMYAh/0IHxJ/fqJ9HMP/mOeBLBA0Q
#@fg4oDVl5+dQWATycfwNw7V4CeM2kNYBvQADrkRrAFjy2TPlHZkhgfN/fUT8PFCD10hIA0RcqoLBn
#@iQBuML8CHO4rsJOuAIgTIwtg+IzUACD/W2z+gVkSKMg/T6T8DwlSwDWAKAArAL8KQAO0ur9ZIYBV
#@7q7A+wq4XroCOM9xNAEATANgwg/532LzzzvAGDth/nnkn4cJgBqAKICcCgZwChCsAkqtPKwCLBAA
#@d1fgj64GNs8ATTd+9j+GEwBgEECkBrA1pQEUAhHl3yfO/COC/AMBJYAcC8QhgFcA3QPmW6V86VL/
#@aeIFwP4/A7kaNC2eAFwNPkQSwMgA+DOATABbpw9gMqIFFlH+ESb/itw9pWBSAG4ByIkAXgG0AIye
#@sApo/10bKwXQsbcC/JRQAWAFKNcuUg41AkzksxAKWf6RBebfrIA7QKACwlaA0uiRhxrQ6j5PtgBe
#@Z4I5cdMKMInnqnASiwCAzXJ5Sv6JAEj44QXAeBZCI8w/wudfWQGmCjBlF3gu/pdCbAIh+/428OCX
#@JAvgDXMO4MjVoefYyY6rwlFsDaA8RQBlKgCqAGwAsyDOPzK//EPeDawCmH12BgAFrLAKgAow+lN6
#@2H+aXAHsZoI5cpXw0gIQnwBwCVAub5Qv5p8KgH7/YwOYEXn+kfnkvxBsgDsIyf80BVxiFFA6twgo
#@/e1yI7ECeMmcA7jrKvHYsZH7rg7XYxJAGbiY/8ARAClEgck/g37+AxVwB6EDAF0DUAVsGxQw7gDw
#@OnTA+z/mJIA94bOfCablajFIfwJAShkeXgCj/NMGUDYIgHz/A4WoMPnn0M0/wFcAqgBiAGYV0EJK
#@uA4sDfnP7tskNoC9vQzDz64Onapn4YXArg6/ZmIRQPkUmv/AEQCIPgIgTP55FPMPGPI/owJWDApA
#@UAE3+gkUAH9TwENXi7qXDgBjDqMIIIcCuDgClKkA6I9/8O5TiAk2/zw6+QdM+UcDkEWAcBVAwn/6
#@mh8poPsueQ2AuyXQ8rGrxm3HLp65SnSOIwgglwtoAGWDAABs/0WpAHgwdgvXQIFiyD+vgFvhVgH0
#@TFB+vA/I50tvfnwaN+cFsCd7MNcDAx9dNTo7li0AOq4SH2YXwPDF3ADKVAB0/sf0A4VkEmv+5Qpg
#@5oAVgJsDxmNAPv//L9+qCkDeAArMzwAfXCUgTjtp/qMJADA3gLJBAOT3f1wCJpk48i83AK8Akv/p
#@g8Aw+618KQ8KKLST1QC63EGAjiIWGWDQUeQoJgGsnwlgA/NPBUD3/0jBAiLkP1IJ4BVADUAdAM9R
#@C+j+lqQGwJwFXl5SjP/w8TjN/5B7sQhgHRvAxgbkP6gBbPkNgI4AlhAh/4wC1tbEqwBUgPlQ4GkJ
#@APKtgyfJaQDcUcBSR5eK51jAi44qpegCAM4aABwKLpsEgPM/Zt82AWCGufyLFbAGiFcB3BqgdLYG
#@gEf+q5exCWCvO8GenH6G4buOHlAC6gMn6Xj3O5q432XiEED5rAGMrwkIaAB++Is2C4AEmMk/83kA
#@BbAmmQPIGtCkAABegXw+21ARQFv82LvJHQToKOO+SP76T5fjTKwNAPNPBUD3/4RVa/NPkeZfrgBs
#@AJcuGRRAfw7E+I/+dJ8vvgEA3EGADx1tqs3Bp/v1D3yMtQEM40/yTxsAZH+aAlaHiBKY1PxTQn9+
#@bQ0NQBSA2ScFgFcAHQPgB4Hh84uDJwloAOxBgJPOHHjgJTX+jzrVjjYngvyzDWBjSNkoAHr4jwgA
#@ECYwQn4V88+zitDd/3WfaxOYFQAGuBRmDvDvEuI7IP+wv/gGwB4EOOrMgWr1QRJbwOBxZx4sRRYA
#@NgD/OBAVAP3+hydl1UeYwCj5XXz+0QAIMYBhCYD3DOdKAAIVADQw3gZebjx9G+kRfQfAHQTIVzvz
#@odlLVA3wBs/czlyo5sUCOKcByL/fAOj3PxEA/fWfCgARJjBafheUf7kCMP8+IACpAvLwAAcAryOd
#@Dn4bfQdwwP3DO5xPCjrVVz93HvUGnrfw6HveoHe/487LfIcZqQCWiQD8+BvyT0YA/P43CgCQJjBq
#@fheZf/kccIueBsA5AAg0ADoAaO3G2AA0fgf8WJ0fpy54VV0onc6rV6P36nz4KBXA8lQBDPO/Dv3f
#@PAJsCRoA4wBDrKLnd5H5l80BZwKgCmBvGg5P7ADMKkC3AQC5TCC5D3OMHjwTATSSOdH5IBTAskkA
#@o3uCrBsaAL3+v8gLABDlH4gjv4vKv2wOwA4gmwNKI0bph1eg+/usBSAGAXA/AxxVU1Q5kglgeboA
#@gI2yARDA1uRPAMX/sXMGkHVl+/7fmkiTtBlbZUavXpVemMlO2IQB589/xgEcuDdwxyRz0noABuCG
#@RAEAikwYk6r3hpIDvNfi6cxFRzVKDckdhiJphqLNJU3O4TgCvL1Ozsm3O2ftfNfea+3ss3fW52TS
#@O2YGF5/v+q7fWuvQBgBU/Qdm/M3Af7UIQALEjQCcBpaPrwZ3MqBU3VnJqAHQKaC3kWojt/y24aoA
#@/88MgL9FBIDk/h8NAKDsP9DzH5yj/3wUwCOAjwKqAlwLFojf41u7idAPgB2XULeSpkndVcIDkQEg
#@/CcNAParBABQ9x/o+w+M+294HyCILgGSs8BOCRCfTgTM/Jp5AGQwBbS0jAXA0neRON+SAiCYPVuL
#@GP4Dw+t3ev6b3wcgABYXJXcCqxsnc0ARAYLtn88/AA5ueS7hyEqaJkeaAVDuBsDS0ndLERVgyXmC
#@27+R3KBexPEfpNDfU/Wf7APgf3QEoAEgAkJgHxD86k4DxXeGnXMAbJc8FgDeF79ZUuRTzQC41gmA
#@JcF3cr5x1oT7JAK+UhEjoVYp9Xej/vMICPsviYA/HYMpACJAtg3ofFVg90gg4PrWeQbA62tegMu4
#@Yy1NjzuuZgCMz8/PIwDkDWDZWRfiEz5XVSOpVmn2dwP+831A1MMATAF6IyDyfbD44GZwdxIweevp
#@eQXA1pwnoAlQallNUwMjABoArnwEcDMUAHIeOkN4ABDJ/5tRJ7FW+v5zzPgviwD5DEAwgQiIKgEb
#@km1Ax/9q2/7Or+2X5xEAB9teF5fQtJ6mR1M1ANyIAKh8wxvAv52hbzmHiVSeiY9R/zk6//3ZXxEq
#@iwCUAB4BKAGhq4Ebb+6lHgA7ZU81APyG1TQ1vv/SVUY+A5zmDWDp350GYCYAgL6WafsPPosNeQ4g
#@jwAB3QcAlID2pxsClYN0A+DNuAc8l3H3+5Sw1L1kAQBmEQB/j2oAL803ADPkwn+NCID/pAS0kyDQ
#@/4RbT9MLgK1pL4TLaFlRU4KPAIB8Bjg5SxvA0t/VAuD9TCZk77/xBEAEqLwOPAZDgA47z9IJgANx
#@9BcvAY6sqWlxlDAAwI0PjgGjrgLuKQXA25kMyYP/PALgP0oAj4CTLw0XZ4LIgGsv0giAnUmvB5ew
#@8YM1NRV++2FDNwDc7SAAat0AkLEkAuAjMgAQvJvJmj70HwnAIwD+S0pAVARUu7Td3wjVgOkD0wHw
#@ouJJcBl162o61F3tBhAEgND/b2ccAogA4P4/2Z/pCzL0X78ETISB/9JRAG4EIATEGBBs/2IyAA5m
#@PSkuwW9aVVPhh6Z+AOyIBnD2IcD/XqYBIBie6SOy8l8jAjAFALLDgI0eqp0E6JwGnFAqe+XXz0wF
#@wMF22ZPjMhrW1XRouAkPAcAbcg1AcNkZyFUAgD7yHwEAoueAJxeDeirAYvdhAMBBAF4InjC+ZSYA
#@dq55EjI8CLT8dtdzGT4LgC3SAMQM4Kpz5VvOSJ/JD3/7zn8QCgBJBMi+KEweAe0aUA5+BKEImPk9
#@fgDwzX/2B4GWJvefBsDB/Dw7BFi66ozxEcC36/3pP+hD/5EA8giA/McgAeQXAnAvCOChMA8Adu+3
#@9AGx9gA/WFKgESMAvIgA+H1+Xn4IAP+DABhVGAI++Usa/qbQ3zP3n0cABgA9CUAioNw9DtjAJKBU
#@wkPhJAEgNv+l08SqAF7d2mqeuqfgPwuAyzgECFyX+S8CwPk2k6uA3FgtfzPwn0TA119LjwF5BCAB
#@ug0AGSAo3TxIGgCvPy7JibUHsLqa5vvvW66BANjDNYDAdan/tSuOs5bFVUBuqyl/s/AfzM19DUgC
#@kAhogwKw0akAwW9v9mmSAHgxXToLuwfIkIaJAFhBAwhoKx/yX3DFUboK+E5Ry+T+6vvPSdt/rPpA
#@JAAIB0CsEoBrAacGASXx187LuAGwtV2i2D1AP+4AyAwQLOAQIKCt/Gn/a6NqAbCvrqWGv5r+ZwCp
#@/YI5YxFQ7VCG/239S+JTfXEvVgDsTJY4dg+QEU3uPw+AcRwCCNrKh/wXDDpKN4FG4mmp429G/n9q
#@ENiPCJAmQPxRQLsAhEtAqfNH5UA9AN6MlyjKlwHtHiCLHQA9BCjfCgJgSgTAGf7XHEfpJtBmbC31
#@/M2r/zwCJI+ClEcB3W8LLXd/cBjQjoEbT9UC4MVsCdAIcCl2D2CYumtiBLAdagBt5eF/h3uOo3QT
#@6MkNZf+Brr958p9HQMj/pPuAaht8TdBpdl7SABD3fiWylz+gBNTeA1hlzXJkJADe4BDgmL8vnfb/
#@u5eOo3YR4DBhLdf2N2f+g2lJCYD/yhGwsfGJ7CxAfDpPBNECAj5+sSLkX4kOgJ1rUvVBTw1wGYt3
#@/ttikDuLsUcA8ouAYf3RAJZO2HMCnnD/n7yK6z8w4G8e/Z+elu0DYD4dBSy2kX9LCM4Dw/NAPBSO
#@CIA3FUX7AQ+AUstKaxByCYDMAMGvogHAdTSApROCpwABQ8z/gH3ZDT51LY34mzP/eyMAewBaAkT7
#@j0gAlADJG8ESHgrLTv5nuf1JEqBhrTVJw0wA7AUNYF7SAJaUAwD+4xhAWswz8DcH/gvCjwK/jhEB
#@Hf/J94UiAaCxV20/FJY9+o2QnySBy/Dq1lpj4BKA3g6gvDwv/AfwH6HQDoCPmP+CG1Bdv5YX338A
#@/wWIALoP+BEJEL0PEBEgfkBb7fFgH/BLz6NfBf1BrArQtN6ao+kaCYBK4H9taf7E9c4OIJwIY07A
#@APNf8F6iOvPf+i+A/ycRIJVfEgHCfsUIqIaHgd7sryvh9j/XdbqsinoA+NftGNAYdyY0AwBfCVqr
#@LYXo+A+mBp2AK8x/wSu56sR/678A/reRPgsAkifCJAF6LwcKtp9C/4NZkQywP2YEuBQ7BjSG2giQ
#@jwB2grfAPQ1gKcyyIxhk/guG+171wLQ+8x/0PAgmEQD/j0vAIhJAPgtAAoDJrZPZ/yRyIR6qFcCO
#@AY3RMFMAylvztVMNAP7jGkCbIeK/YKT//Qd94j8Q/k8AHgEoAN19wIYEHAcgAsJHgkL/remyBooV
#@oP6fFiPUlfwnASB4On98CIhDAPjf5bLT5iPu/7dPvsqL/yEy939OIJ/88QQIRUB0AnRCQCZvueSJ
#@MNBBLQAaVl0zNEwFwIoYAcxD/17ENwK2GWD+C972uf+c8/N/LgyeAcQtAbgRKJDIjwTofMyjdg7g
#@2QpgBKUzQKVDADECmJ8/OwI6AXCF+S/Yz5f/nDRu/kP6sP/xI6BnECiQ+y++LAwtwGwIqF8FOLLy
#@mkDlGYDKDNDbnq8J/yX6g6krTptB5r/gX/n3XyMesJeXQfwHEzQC4H/CCKgmjYBqQGQAeC6jfNfa
#@q8/dsqkdwJv5wH8UADmjzjFDzH/B50X2n6PhP4kA/jAAD4MCpBEg/idCILb4YSQJoFBMm1Zfbe40
#@Xb0dADgI9J+S6g8eOh0+4v4bGQJY/9X3AdAftwJ7IqBHXcRAEvlBTwK4lA3tCmC5u2EsAPYUGsCe
#@02GA+29oCGD9V46AD18FAEkJkG4F4LCO/QpXAYB2BbA0XQ78F0T5P7nMG4A4BDhmjPkveBw4kI3f
#@hfKfjwL+pB0BcDum/dFzAM9WgPS5WzVWAG7Nz7dngLgKEHkIIFhl/gsOpwUJ1mcj63tB/OclIOy+
#@LAHOjgCgLD/QuQvkN+9oYWm6xgLgDSsAOAQQDDH/Be/gYmx/TfX7/PtPIkDYbyICygnsnxTEvgoA
#@qg+swzooFwCFAPidjADwFKjNAPNfMDINkvir7T/Iqf8kAqQ3gXgEyDMgpvxIAFkGnEcFsByZKwDl
#@ZwoN4Jlzwhj1X/AV95n5a8B/kGP/yfcC8BKAUQCvAdR93gPUEqBUtxYnp142VwCmVUYAlx2wyvwX
#@/KGoM/FX33+QS/8BCQCNEqCFPAFchlc6shonBpcADQTAzrxIgKWzueqAIea/YFjdZuav9b8D959H
#@AORPMQKUHgSUE1cAS72kvgPg14BEAYgTAAPMf8HqjTgyU6+s/23oeyAaAdA/xQRQ2gN4DStyUhr6
#@BQDsHY8ApshFYDBK/Re85y7H9ffC+g/gv3ICgJM9QMoRUFILAK9lTU5GyzUYAB9/IxoA8X/F+ZA1
#@+B9nDwA0/L2g/gP4HzMCPhGkFQEiAOC/YgJ8edu6nITbX6j7zwNgez5gampqic0AwZCC/6trt4jI
#@Gv6m73/IUcP+f60JEiBeBHyCCBCklAB4EMBJVAEsTUMFACOAqdrUFB0BgAHhP+Ut91jH33T9VybK
#@fyJxBgmQagQgAfAmkOLb20BJeLCh7L9KALwU3whMAqA25nzIoIr/q8NqGmuJmpH/vMun7b9GBAj0
#@jwN13gSC2EeBltu4A2RkBzDb9p+MAJadMENc/+Dnq+lckgP/SQRcD5AmgCQCrgmqalwLc+pCUII3
#@gZ5Xv3M73sd+6iWjBeCN8J/tAPacMANPVBLgVaqWWv9lCXD9hCj/Qdf/MFx+APsFSSpA47YlJg1X
#@IwAkXwgs/F9SGgGAQWr/Kt4DmMb6DyT+g+gtAIi0/5pU/o0Tuv/BtY79ySqA7zVv20U91qcZx3/e
#@AK4tKxSA2hUn5h5gtf3rMHVZrf+JIwCE5T8VBRL3kQHinyMBElWAav22JQb1qor/6gVgW6UA1Aad
#@U1xi67/4Y3Xf+q8Pew+gEQEgotyH5f8khPC/8+/A//gJ4NlNgP4GQCMADmoxRgBgTGH9X139aWZu
#@LmuXL878D4QTgEXANQk9S788MroRgABQvgwEWtZqdVqukR0AeFmjZwBTGAGAdb7+B3+8h4MZr+WF
#@8B/qE1gA8Awg8gMkgCQAPFeBjQfWa1UeLBouADd4AcC3ASnvAdr+iwgYhn9Z+g9y7H+lAsE5zH9E
#@gAS4T+ynCeCqcGTFVqVhugBsqYwAlp1expj/gmAMCE/6wH+QI/8rXf4UD7b+RwP3zyCcANgExK8A
#@vt0EqNJyDReA8rOa4Cz/p0IPAcA6W//bIbDPtVNR2bT/oH/9r4BY/oMo/z/++Ey14T4BCSD7fjAE
#@gD0JMH8CYG4HwAvA1FVHwiW6/osUWL8V1kVH5ZRnef3hfwXE858kwPj4+CLPAA5PAOivnAB+4661
#@m3NXfQOguAPwVM4ApqZGHQmjbP0/joE/ZKolV9ms//qYlt6o/4H33Qi4ftp/gbEIqCIBYgUAaFq9
#@OU01/3kB8MI7gCXi/0tHyhBb/9s5MCKXUWspz73/FYIx/7sRAPXhv5kMwJ0BnQrg+nYTwHhUL+kX
#@AC/kv7fNCoDw/7urjpQBsv53guCQ7L4Tqpyh/9C+v/0HUv+BZgJIvyAYAaCWABPkLNDy4AtDBUD8
#@7nBARwBTAVccKYNR/od4MsxGcBoqW/+J//L9fzSJEiDimwFjBYDnn30WaLl75JoIgJD/kyu1AOb/
#@rhPBUNT6jw8qQHpLufVfwvWQ/4LU/McWAAmgvgcArbuWM2jF9h8B4Ib89+TvAKZk/gsuOxFcoeu/
#@4Mm+usMaKlv/ZdN/+B9qASb9F3Tsj6oAahHg1a3lkTyql+MHAPxHALR/dyj/ihFA4LrcfzwF7mWV
#@r/+Cz+MZrKGy9V/W/8EiMOe/oIoHgfGnABgDWNGjeD6RvAC4CAD4L6gs4AxA7r8ALwH5VYBVGWuk
#@AgBDVd76jyuAIf/PngVoXQWY1K8Avt+wokfRiOm/H+0/AuAFCkAgeoT/vdcAwShf/wXrfz7nKm/9
#@F3QOAcdPYeZAEPrrVwDQtKbLabrxCwDwQmAH8LI7AqhFrf8C7ADYGHA1incxNbP+6/svEP4HjEdk
#@AFDw/+MPgP3AxBTAt4NAKbdbcf33qf+dEeC8cD9wfX5K7r90BwCu8PVfsHkrA1mt/wDuR00D1NwH
#@3QAA0RWAJgCo2kGghHo1mf8kAH6vCZaCjxBd7r/8DACs8fVf8Kpf/L1g/oNxeQbAZwX5ARqAkQoA
#@/Inn1ncyANQIAMkIcEoMAeaXZP6zMwDBJbL+Z1YBiL/F959GAJ3/kcsCRisA+NIeBZziQcOU/5IR
#@4JIYAggk/rMdgGCQrf+YAlQqfdjfC+8/kMsfF/kMkM4BPeXLAF7jkXX+Qx7F9Z8XANwCFEyhAYT8
#@p2cAbYb4+i9Yv1Fpo+Fvyvv3vvH/Zhez/puSnySAfgXwjqz0H3LkeqkUgNcn+gvfJf7zMwDBWMd/
#@wtp+pYuOv6b8J5y//zdBiv4vBhixH8SoAK4inj0MBI+artECgDPAn7sFYH4K74F7/F8edAhDfP0X
#@rH9V+YB87d8N+E+MT81/gLm/Oft5BYD/MSqAZw8DT2h5hv3HGeA8KkCtx392BgAGhP8K7FfCaPrb
#@D/O7rxXgrqfvP38LEFt+QOaACIAYCbDRemQR3G2V3ZQC4GntGOwAZP7XrjiUNb7+C9Y+r/Sg62+2
#@/iuSqf/k9J/bzyEVIFkC1K38gno1Lf9v1b7pBMCS+An7D146nAFIrlwBgL6/1v9jiPvIAKAlv/kK
#@AHyv/shyv74Y33/FCcDBSQEQx4Ay/8kIEAzS5b/DYSUC7i/10/rP1AeLYRTsl/8T8xUA+It1GwD1
#@H9PwH5eABFNt5SX+00sA4NKqEmsjc5VIdPwH1v9xNRblCL+DP+Ty87NAXgHUNwE2AR7UJ9zUAkAU
#@ADQAmf+4BKBeAc7UP/jrbeVMtPwHF9R/2K0VAnL1gfIUAP4nqgCeN3HBEyC5/z4vAMvSEeDUacgI
#@kFcA6C/4abbC0PQfXCD/sfDrJkD8oSCvAAiAWAnge/5nFzYBHgQ/zz/T91+9AMj9f+aoMUqWf8Ga
#@CIF3FRX0/QeF9R+135D/xm8DlTUSwHaA+qduwgDweQGYkxaAKaA2AgRDag0AR4EUI/6DAvkP9c35
#@r3ElwHQFAP4FngPcr0+Y8N8lRwC4BSj1vzbqKDK2+oTZv9b+Ga7EwJT/IN/+Q3yT/pu5EiSvAPA/
#@VgLYSWB9MZb/QPwdfQY0c3IEgFuA8J/cAkxWAda6EXBoTlkNP/PlP8Q37L+B+8B8E1ACmAMqdwCv
#@/uDicb++oeM/OOuLQATzS0EFmIryn98CBKNnuI8KEDAyY07Xij797T+8N++/5nsAXgEEvALwDGg9
#@uHC0qrH9B9z/2Q8LQI//YM8B+gcBa2wOSND2k9A//sP7tPw3+RqQVwCtBPC8jYuWAI9aZTfVAPi1
#@1iFY/wPzo/zfRQHQqABrUL/zd4eGJK2kRib+X09G2u4T/8kcsMw3ARTPaz64UDS9dP3fri2gAMB/
#@egaoXwHWxA/uAybEvP9E4ZT8v26ClN0Hcd8EwX9eAQi+f3SR/D9ydfznAVDeC08A4D85AyQMntH7
#@13AVIIiAtxV90vefovwfX0+PVOUn/vMKgMvANAEIjecXZv7XcL0U/ccXAaEARPh/b9AxWQHW8Nn8
#@c6XvuanJ9XMhXfeJ/yQASAK4sfAb9Qsy/m+ks/4jAMZXUACE5/CfFgDC4Brb/7c/AcPWfyMYdN/w
#@u2DJi0CtCuD7ExciAeoTrp/Af+ACfgm4TZT/u6NOXC6x/f9JBry3/hvAvPrMf0LYf7ObAL/cssd/
#@BvyfWf7gEmDwA//JO8C4FQCL/6n1X/z+1w3rvzb8iN+8/wT4bz4BPO/ofsH7f9P10t4A4AhwSgK9
#@BUwYUFv/U9oEWP8XBdn7jwAwsAkAnl/sUeDzhgvSKgDbNcUAuOwkYYju/9tREPA2bX8vlv+LIGP/
#@zVcA4P9YL/L2PzX/EQDXXqZRAMDY2et/50ew+VWK/oPC+w/vs/dfHgBGE8BvFbX+t8r6/vMCsMUL
#@AJkAEIai9v9IgE4VGJ5O3X9QQP9hfJ/5jwDgmwDPjYt/9Px+AXl+5PoJ/Qfc/1sLhgsAvxAM+bEB
#@aLP6Rwb79yL4j3W/7/wHk2Y3AcD3P20VT398+UcK/iMAJvcUC8B3V52kXIre/7d/IQXWD7Ob3+XR
#@/3HQh/7zANBLAOCVm/cfFOpzv1ky4T8vAC+Y//wOQPyjwLXT/f+Ekems/Af97z+070v/M0gA32/U
#@C7X8N1wd/3kBkFwBSKMA4CgQ2//w/P90BOz30/ldX/kP7XPiPwJAfROgkQDlAm0DWhup+9/haZoF
#@AAzJ139s/8H77P03iTnpc+B/BhUA+F6jILNAHP4b858+AmL+L111dBjrGQBg49/+G/DY6FlgWiKb
#@8p8on1P/wbX0EwB41UKUgNai66XrPzYAD1UDYHnQ0eJSxABAwshM3/sPSCxY/9NPAD4JKPbuH/7H
#@PwH4hfgPrjp6DK7j/D90ACAJgf28+U+w/oNJOgYgCUDwvebzXPvfrBr0n18BUr0D8MzR5QqWf6z+
#@0g6wvvY+3/5b/xEAySuA5xa/BPDl37z/CAB3e5kXAHwVsC5DOAAIhYCEx5/n0n/rv/kE8JP4cPQ8
#@r1f/PNc/H/8F48+I/2DP0WcQ4keqjzFAjv23/pMAIAnAGwA1ohrsA57fz9sP2r+O/+ongL8vKB8B
#@jjkGGMD+n4bA8Fyx/Lf+A6UAgP9+Iis+a+VN/9YXrmfWfxIArxeMTwD5JgD3f85kfe1VQf23/qsm
#@gKuD54lRwPP8fOoNk/qr+D97j/uPbwI1wijfBID3hfTf+q++CXD18L0joVY+/D8quYlI7v+1PfMF
#@gHIJd4Apjw8L6L/1nySA/CDQTx4BOWj/z583y27K/gM+ADB/BAiGPnz6Rxi5lX//rf9ZJADwS0fP
#@n3cW2X79EbM/34T+QMH/F9R/cMUxxqhyA1jHt4MUxX/rP2ABYCoBPHExSNCv/mP0b9R/fgNAPQAu
#@OwYZwO0/HgP7efbf+m+yAri+n9iTarOtf1/6T/U377+gsrKQ2gSQMLSGCGAdYP2PYvpv/acJ4JlM
#@AN89qved+wH1o7J7Hv6DkycA8L8TALV0J4BgkNsP1t/n1X/rv/kEcHVsabT6zf9Ww/U94/pT/wUH
#@3H/zGwBsAmKwfphj/63/2XcApIeIgD6iRc790/T/xcIC8Z98DYj2JgDww8Bi+m/9p+8CZQmg1wJ+
#@FDuBfqDenECcmfefDAC2l7n/5jcAYHCde48xwP98VSj/rf+ABICpDgA83/+y1Q+LP/0/Yt5/BMCN
#@h6c3ALWa4UdAhLG1OAkwcqtQ/lv/gcR/mgDcHOJONdsaUG8uur6rg6/n//RKDP9rY04aXFL3X1wH
#@mCmU/9Z/QAJAngDaEeA3mvWs7Mfib85/oOD/+M8LC6f95ycAWY0B1tuf4bki+W/9B5PxEwACaSn0
#@WQYZ0LbfdzP1f/Jp138B83/PSYnRdXX919fX9+eK4r/1n1cAngC+q4vX7gHnbr+ri6/r/4G6/zgB
#@yGoM0NEfCZBP/63/5hPAd/Vp94BzmQm2sPZn4j8CgPuf7gYAXFKwHwnwDyRAXv23/mskgMYggAjl
#@lRuterr2H1Wx9mfs/wuJ//wKUEZjAOgv2C+S/9Z/UE2aAL5rBM8NisBRKy35/z+W/tT05wcA8H8X
#@AcD8Xxl00oLfBhDqd34d89d3hfTf+l+NmwBQwdUFuvj+jw2z24F66+gz0TBckLX/r7H+K/i/e8VJ
#@lzHF9b8TAWvvCum/9T9+AvgnuCaANBtBCNRNuN9siNqvbz/wzfi/wP1PewAALrH1H/YL/vqqUP5b
#@/xEAsTuA4QRAEQjwGkfJu0CredQoY8vfT/7vLEvW/5RPAAlDdP0PR8C7gvlv/WcJAKQJIHDTcM3z
#@SxMiB5T7QL3VOmqIZV9kiJuh/hL/8QBgGQEg/M/oBBAMDpH1H/Z3zgIK4r/1H8D/fkgAIEz2PL88
#@0WgciSho1Vv1ev1E+IBWQPMo8H6i7B7/y24q+Cb833mIAQD8z2YDwO8Dtf2XRMDm/lwh/Lf+A/jP
#@E0A+CEjFO/jUK5x/DP6R54J+8h8B8DpY/3fFBAD+CzLyH4ydsf7DfrA5PF0I/63/AO7HSwDzEcAP
#@DPl1RNP4Rvx/s4wBIPzPbgAABqLXf3kEDM/k33/rv/kEKCa+Kf93cQFAwf+VUefcuCRf/+X2C4Zn
#@8+y/9d98ApAIsP5vLeMAQAD/s7kBQAaBneO/zh+9jNwolP/Wf54A8P8ilQDfkP8H7fV/Iex/1gMA
#@MLjZu/5LvAebI5/n33/rP0sAQBIAFFd/Df+vHWD9V/K/dtk5X8bWe9Z/EgM/HRbKf+s/SwDgAZkp
#@Vv/T/o8/jbv+vxx0skiA8P1/wub7HPtv/TefAKDo+gNXZf2f/lm+/mczAORHARj/Ed7l2X/rv/kE
#@ABfHf77+33q2vLxbW64twP8MB4AkAdbx4fxjfzr//lv/9RIgSpni66/o//a9uOt/7aqTCZck9/9J
#@AgzfKpL/1n+aAAD+R1lTdP3V/H+9LFn/szoAIAzBf2p/JwFGPs+//9Z/jQQ425zi60/8nzwI/McD
#@AJDpAQBJgDgRsPnT+1z7b/3XSIAiRoAPDPhfebq8jAMANf/3nOwYFAmgZD/4x7tKHv23/uvfByhe
#@AvhG/fe2n8Vf/3EAmAWDm+uqBQAM38q//9Z/kgBAMgckFl0s/bH+v3lI1v8sDgAJo5vq9mMQcFgA
#@/63/YJKUgEJGgG/Y/09+F/rHWv9rU/dwAJhpAsSMgH++L4D/1n8g9V+SAIDKlEv7Nfyf3gv0xxcA
#@gMwvABDGVO0Hm5ub+9P599/6D2T+kwTIbwT48fWn/u/cW94VBQD6c/9r8D/jBIjpv2DkMP/+W/+B
#@zH/yNEjBqTzrz5d/+P/xwbJAIj+7AJTDBNhs8/jxH5Xc+2/9B/IA4AnApMqt/erLv7sdXP5vL//L
#@cc7/4H+uEmDzhOEb+fff+k8SAP7nPwJ8YNL/8ouHJ/5LIBcA85IA8B+MvMm9/9Z/QKaAwFONAJAj
#@+4Gr5P/004fo//nyH4zF8B+sb76by73/1n9AEgB4QNmxHNnPl3/4/3plWYDj/zz5D8bi+A8ejxzm
#@23/rP0kAXgLiiJaPfT9b/kF3+d/N6/oPxjYT+C9mge+mi+O/9Z8kQA4iQH/br+5/+c3Kw2P9Nfb/
#@OUqATRn/MXJYPP+t/3wbwCMg4xBIWPvVl//ZXx4+FPoL/3O+/uNOoLL/4PH+TJH8t/6rlwAQ17z+
#@kx/+u0r+T764J/xfbvu/kH//aQJsRvEYk4D8+2/95wnAI0BNwP6QH7gR/nsytn9+GNDxXwq5/9OH
#@jA7F9B/s/6VQ/lv/1UsASKZhtuoDV6C6/E//Luzv3P7F/D+f/oPBoZj+owT89GrO+p9j/6tVxQQw
#@GQEgI/WB20ZR/0+27gn/dzvj/1gPAOF/rhJgkzPyxvqfY/95AqhHgI6X6YhPcAH3v7zz8qFg9/j6
#@z3Ks/r8L//OSAPCftYD9P1v/c+q/QKsEAHOGulIxfX3rdfR3t3+51979S17/TxH/8f6/j7mU2P/H
#@mz+9mrb+585/ngBaEWDc1wz0B7MHbf132+v/grj+x/0HK/3rPxhI6L9gc+R9xfqfN/95AmhGgJsj
#@/YHs4t/Bvbb/J9d/PmSKjv9+HnXywJXNpP4LEAHW/xz4zxOAbAOAzH+QW/1BZete2//d5fbyH7X+
#@T0VxedDJB2OPE/mPCLD+58Z/UI1RAkpSpAEA+l1/4v/NrZXQ8h97/b/s5IbRofj+g38+Hj60/ufC
#@f54AgAQALQF9bj/RvyL0P97+d27/7sb0/6qTIwaHEvmPDBg+tP7nxX8g8x+QDsBqQI71LwWjv67+
#@3du/C+FDv3we//MEiO8/WoD1Pyf+A/ivXwJ4BvRl9Zfov/2r0L9b/3ehv7L/OP7LDwPJ/EcCbA6/
#@r1j/c+E/gP8JS4AXxu0hHzt/UN5+GtZf5n8+x/98FJjMfzDydtr6nwf/wSSBRIDXi9tLv1d/cPPN
#@z4H7J/Uf+hP/yfg/L6PApP6jBvzXq1nrf3785wnA7wP0bwa4cfXfPli5h+Uf0/92AsD6/N7+JQxe
#@4v5Tfto/vGn9L6j/ai3AjSJL+/mx3+s96B86/AfwP6+3/wgDev7/8/gz8nbW+l8A//+PnTvQcBwI
#@Azhed0eze3KoAq1lAVZBAApYQIG+QB/iAHmHQ57gcNYCah1MBk6gjCKHq0W6WQ7ZhG3yCJe5/Yi2
#@n7nG51Iz5t8XWPh9XzOZLfhvPwKU9M6qH/405OCvDPb4N+u/pf/8sqdz7gNl/0McvgZY/yb6J34L
#@gM502R/lPx3F4R7/5vA/Rfxr8eM/hPeBJP8Q5/zieaSzf+sfBgDelDoDoI7v+mL6r1d5gPH3F0en
#@/3VGPf7jvaP6b2bA41gD/9Y/fQRAquNARZ298DvmP5H664A/8vTfxr9weybkcpp/iMucbKSlf+sf
#@Ug+A9q8FkTo78D/gf5vEb/qb9Z9K/nUpvv7Bv3lf/5HHALp/iDnZWFf/1j91BEAE/7h0BX6EP9Lk
#@qRRBtM/fh5/9QNe/zNDTf6T3D3T/HGKcXbxUM638W/+EEQAzgPZVQC38VPu4/kES55HED/xlf+1/
#@A/6w/VH/hl3+UV8KIvuHGONLJ6uurH8t/NNHAD4DYArQU9JX6x8mq3UUHfCHWz9v/P17lD/4N/n0
#@T3EpiOYfZgDbvGbVzPrXwD9pBEA39CFACvkfv22Zixp/cbD99/gv4OrfAvFv6st/vI+c7B+ZAnfO
#@425s/evmHyYA3rT9EOhY/3C0jdehEELqL4KgwLa/j579A3rwr/7Xf8P68InmH4/Vn43zElee9a+B
#@f+oImN4o6gD/cJ78Ln8IWQTLH9/+fgpn/7h/1fp3e6bmcqp/PMa+y2sCTj/bJXPrXwP/hBFAOBUk
#@6B94yXZVrnMBRaKI5Cco6s+X4+2fKtZ/nfFP/4qTALp/PCaPBeqWF85r/znbVVUyvvY8z/o/v3/S
#@5WC8/+n/djC4Gs4mk/ko2T6t4vJXP8/DMBQiB/xy9dc1u/9g+9/7C9j+bf33L3tm5zKSf/UAgD4z
#@pJ/qluru/tnXE9qc0p/2zV7HbSyJwottw2q5f17CYYPPoVBgJBigoFD7CkMGHSgxMICCnlcQFkwM
#@TGRgvMEsFCqbZFPH4lNs1bksn6tLUuao/2jrflW3JPVgJjun6v7Mpz7cN3l/Ar/24F/f4WMrH1YB
#@ydQxUZZgJqRpmilzYaHo7ZlQNdgp+3ZGkhqPYK/Rypf9fmfqh/6rnci/Yu8Pu38pnV+jTf6gU/5r
#@tP+fnH8+p/7BOen/0/tPyPv3svzyMvr/GOr/g+YHsKIJTBEqfw3lmwGYBcwVNQBhUYmYqgMT2Nd1
#@J0siZIQ1ohloaDbZu4oliRCk/olFvmjupPeL9iXFgqB85IOjaun+i3IByjI4+6f+z+Puv4ubt0+l
#@/6h/OADivS6kW/cvpX8sjw8ayJVBC4AHmAXMljMlDaeAopDcVBo+exQNuEArI0//wQ/+/BO1/lL/
#@yev+//UcYAf111QSEH+986f4fflD/1/bp3/QJf/t1T/OhYv/RP0/Tf/X9o/wE+VF9P/rxybhBEAH
#@QExW6gEwAFiA7wFzbyOwWegQsGmbA+ABcIIjjOpEsXVoBJpo+YTSN/HvTfvY9le1+B84/FP9Kn/o
#@v+yWf6f+N5j+z4U3t1H/T6B/Hfeb+sd6sf7f9ADVvyxA+euSEAeYrHQjsJwsAwvgRgBUGgXngGAz
#@wPgetIAefEHsEH7j39atH+L37vyd/jfs/lq65N9NGR7+xX1A1P9p/R/5Wv0fUP0SrRbgzgKXPAv0
#@zwLAwqHHAc05AAcB8ADGbv9ooH3t+ggBtXKH/hVO/TT91k/1Q/6mf6m95Q9GN1RG3Aecrv/Y/5Ev
#@uP9vqh/xEfIPTwIlrSwnSmMKCG8EFhAX54CQ3RO4AAd+0TsS7N3UL7VS+bPz66L67c2P7ftPaf/b
#@85n+g0cBj9d/7P8I5sv2f3pAeAZo8pd1AOSPQ4DQAmwMCKaAQlCdyRzQ6QL0AXzfSfRjx6D23X8G
#@nV89IHzra+q37m8P/iRPkD9e/pwt794+gf5j/7eFfNX+D/nzEFAIxY+iBBZgQ8As407At4BqsakQ
#@gfiRe88FdjYNmLQlWwOJsI4P2UP5srT7i/iD276g+Zv8S3fqPz9F/m1Xf/EooL/+Y/+n9l/7/J8G
#@gAUPMO3bpy5jUsMhQIEDBB6AewF7IiTZwg6FVnBoBFWLA1R1x7daWVSQP9q+1DUv+yUD+S+s+5v8
#@F/Hs7+9x9fZx+o/9/+D+7zXP/z9YAHysAiD/JHHyP5wC+CwgsIC5s4AC+q/gARpNdghM8BZ7WoL9
#@gUL3fmPDv0N1oco/7PwbUhhs/q3dPy+j/PtawOn6j/2fEwDqAPo/SpcBuBBWEwnOAOYBqYadB2bm
#@AUA9oKiwEGuJNqBomsCen5C8UllIUvngwbGujqv/K7f+bfLPY/fvzcVfp+s/9n9O/xKD2P+ztMsf
#@BUwkVP+6wEyhBdADvg0Cm8Kk+M0FerCjMdhXCl8ToPFz7qf4A/UvJAWVPpt/2P3zKP/evLn4I+r/
#@hP7vfQzh/B9BOm8B6AGg3gYcngYqNAHgDECLmoBRrbuHgW1FgWPG1zTVA/3yYMrnWX9T/DjwB67x
#@fy2lsPmH3T+7O0YR5d+0gN+j/k+5/+fHq9//I5h4CBRawJQRTAGwgE4PmGc8EdQQoP6Cw8C60uhi
#@6yoSYJ+PqCB7SL+98RdkAcqiXITNv//ef9168h+5GD9G//H9//0wzv/JSjN4DohyEBP/OgDMDi0g
#@owUIC7qADuLQZ7UBlaRImAH088EGfE767u/s9+7f7KV+iQ75Q/jZ8el/G+Xfyc34MfqP7//vX+X8
#@P9j/W65cIrosQEmk/+uaiv4PDgMbc8Dc4CgA5NP0750N+NJGMoj7w2Yta7OW0CSc+iXJ0eafHd//
#@748++4nc3P6Y+o/v/xEeqzqQKJQ/LSCZSiQ6AyS8EXSEHsApgCZw6AMb8wH3sZYlIbrW9PCNAIpH
#@0dV+1edTSh7IP21u/VHyvO3k7ypK/Hu862UBsf8HiTWM/X/Q/yURQmABmip+qToDBC8DdX3j4DgA
#@8HYQFAXOBhEhlSQMwZYm4Y+OmR8fJWIxn6v4pZBcglt/jACt+n+4jid/vXhzO/7B9B/f/yNq8IX9
#@375Q/rQA1/9dTDTAkvBeEGQaNAHaQFF7gGE+UFjpgZpHKP6C0lfxq/xJKiFyh/rR/TMtTv55bP6P
#@2wn8EfXf//0/1hDu/6l+C0sQWADF75g0PWCmhS8DzAXaTIAUDTYaDYouOO+XkvV3EX+WlWVG+Qsq
#@7Zx9vxZ/Q/+7ePD3hGNA7P8IL4e5/0daGJQ/zwDUCGomZAn8N8IaRlZj+kdpwrGgW+xaAu2j3def
#@qn0hU/zeX4ryc9V7aVv/XFO0H+i/iM3/accA6j++/8fHMN7/I7EOpI8MmNbqx4IFkInHgf4DE1Ay
#@vhU0Hwj1j1UgLfjFgAeQOdAvJUJ7P8Lv/Sp+yL/u+xlqjT/6P6b5x9dB46j/1v4/zPN/vv/xUgM0
#@LSBJsBKqX6LFA2ahCYDmwSBZnAa3FE77Zamtv8wcJch1Qf5O6+j7lL8S1f+UHnAZ9X/0/T/WAPf/
#@HAHa8CcA+e5bAD48ZvQAEhgAKmeBcCLor3zs9e2wD6qXQHG9P/fVj/4P7VP91P8+qv+pLgbHP4z+
#@4/t/9n2kRpMEa2pTAL6Y+u0jfByIyikACTINMkdoaaPe1zf+PC/hAjjqEyh+BfWuzDn5G/gp1Sf2
#@/mf0gNj/2fq5BnP/3+oADZJfVolO/q5OIX6tk0TCid9uBADPAlE6NgNZK/OADNGgxMp87nwTuJOf
#@6Z2p3yjxs8wD/W/jqd8z8O7i8q/Y/yH9IZ7/U/4W9qXBL6tVLX+bAlDwKMB5gC6g6pegCdACSBqS
#@kQ7Bl5r8e5kZpaYs4MQP+Wc21zd6fX5IMXq+5z6Rq9txvP+XNYjz/679f+ABDaB8KxC/I5GU4BwA
#@/YMlgk+DfBNIsVJNn0yjPyb2VJFmr5GBO4mm1kH4p3J/HVv/8w8Ct+Ozv/8f7vt/Kr9b/7oBAM4G
#@pginf8EeBYa3ARYGPSDcDJDMJ2WPD7TvSV90f4f+n+fZHcL2+gHh3xYi/lfY9UcTOMf7f8p/WO//
#@g9m/S/+JDy8BEk0UWTgBCIHwP0sYsybpMfI0z6SkWBlIjRIh1JLPMvsicZxqdH3zwhKIvLm6vfz3
#@mfV/Fpf3w3r/T/13939t/wb7fyJA+ciaSSufZQj4jODlYDvhNKApok4DShe0CEi+p/bL7ej6Vff8
#@cRS4/N/Znf9zABjc/f/3zv+mJn9D1Y9FC/CYtHNkCiAt3R9xAP3A/mkOemh/s78eyNAfZ4Hr28vx
#@GZ3/D/z//+dHGwnBMyAoP7ES6B+lg6WhdtCcA9I+5AfGkPej2I1E+kNr+5F36gOX49/P4Pyfvwb3
#@/h+J6Lz/90H7x4f7IQV0Pwuk/sns86zeERyl0wJ6UT6o8K9vBt/0oxFcXVzf3l4K47Eq7ufo/0iW
#@gb7/d4FskkgGBwBJSCh/FNCp/4DflFlALpH+ZuGkf4TFZrPd7vbCaKSqv7p69zPq/v/UwGZ9DYub
#@hQAAAABJRU5ErkJggg==
