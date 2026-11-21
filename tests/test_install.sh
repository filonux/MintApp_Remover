#!/usr/bin/env bash
# "install" and "uninstall" (F5.1): where the files go, what the launcher says,
# that running them twice changes nothing, that they never write through a link
# and that uninstall leaves nothing of the program behind. Every case runs the
# program in a sandbox HOME, as an unprivileged user, with no apt, no sudo and
# no terminal: installing must not need any of them.
# The data of the program (F5.3): what uninstall asks about, keeps, deletes and refuses.
# SC2016 is off for the whole file: the code given to app_eval is single-quoted on purpose, because
# the program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# --------------------------------------------------------------- helpers ----
H_KEEP_CONFIG=1    # the harness would delete the settings before every run, and some cases hold them
exists() { if [ -e "$1" ] || [ -L "$1" ]; then echo yes; else echo no; fi; }
mode() { stat -c %a -- "$1"; }
inode() { stat -c %i -- "$1"; }
# tree: every path under the home, relative to it, sorted (empty for an empty home).
tree() { (cd "$SB/home" && find . -mindepth 1 | LC_ALL=C sort); }
# tmp_count: temporary files of an atomic write, anywhere in the home.
tmp_count() { find "$SB/home" -name '.tmp.*' | wc -l; }
# count_of TEXT NEEDLE: how many lines of TEXT contain NEEDLE.
count_of() { grep -cF -- "$2" <<< "$1" || true; }

be32() { printf '\\x%02x\\x%02x\\x%02x\\x%02x' $(($1 >> 24 & 255)) $(($1 >> 16 & 255)) $(($1 >> 8 & 255)) $(($1 & 255)); }
# make_png FILE WIDTH HEIGHT: a file that starts like a PNG of that size (signature and header
# chunk), followed by filler. It is all the program reads of an icon besides copying it.
make_png() {
    {
        printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR'
        printf '%b' "$(be32 "$2")$(be32 "$3")"
        printf '\x08\x06\x00\x00\x00'
        printf 'filler so that the file is more than a header'
    } > "$1"
}

# ICON_NAME: the file in assets/ the program falls back on when its embedded icon is missing or
# damaged (ICON_ASSET in the program).
ICON_NAME="$(sed -n 's/^ICON_ASSET="\([^"]*\)".*/\1/p' "$H_SCRIPT" | head -n 1)"
[ -n "$ICON_NAME" ] || { echo "ICON_ASSET not found in the program" >&2; exit 1; }
# copy_program TO [keep]: the program without the icon it carries inside (the "#@" lines), so that
# a case sets the icon with a file in assets/; with "keep", whole, as it ships.
copy_program() {
    if [ "${2:-}" = keep ]; then cp -- "$H_SCRIPT" "$1"; else sed '/^#@/d' "$H_SCRIPT" > "$1"; fi
}
# embedded_png FILE: the icon the program carries ("#@" lines), decoded to FILE.
embedded_png() { sed -n 's/^#@//p' "$H_SCRIPT" | base64 -d > "$1"; }
# png_same_image A B: yes when two PNG files hold the same image (same header, palette,
# transparency and decompressed rows); other chunks, such as metadata, do not count.
png_same_image() {
    python3 - "$1" "$2" <<'PYEOF'
import struct, sys, zlib
def image(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos, ch = 8, []
    while pos < len(d):
        n, = struct.unpack('>I', d[pos:pos + 4])
        ch.append((d[pos + 4:pos + 8], d[pos + 8:pos + 8 + n]))
        pos += 12 + n
    one = lambda t: b''.join(b for k, b in ch if k == t)
    return one(b'IHDR'), one(b'PLTE'), one(b'tRNS'), zlib.decompress(one(b'IDAT'))
print('yes' if image(sys.argv[1]) == image(sys.argv[2]) else 'no')
PYEOF
}

# fresh [keep]: a new sandbox and a copy of the program at $SB/app/script (without its embedded icon,
# see copy_program); a case that wants an icon puts one at $SB/app/assets/$ICON_NAME (as the
# repository lays them out).
fresh() {
    new_sandbox
    rm -rf -- "$SB/app"
    mkdir -p "$SB/app/script" "$SB/app/assets" "$SB/tools"
    copy_program "$SB/app/script/MintApp_Remover.sh" "${1:-}"
    # A PATH with the tools the program needs and no zenity, for the launcher cases.
    local tool
    for tool in bash cat chmod cmp cut date dirname env find grep head id ls mkdir mktemp mv od readlink \
        rm rmdir sed sort stat sync tput tr uname; do
        if [ -n "$(command -v "$tool")" ]; then ln -sf "$(command -v "$tool")" "$SB/tools/$tool"; fi
    done
    sandbox_chown
}
BIN_REL=".local/bin/mintapp-remover"
LAUNCHER_REL=".local/share/applications/mintapp-remover.desktop"
ICON512_REL=".local/share/icons/hicolor/512x512/apps/mintapp-remover.png"

# app_copy [VAR=val ...] [-- ARGS...]: runs the copy of the program in $SB/app, nothing on stdin.
app_copy() {
    local real="$H_SCRIPT"
    H_SCRIPT="$SB/app/script/MintApp_Remover.sh"
    app_run '' "$@"
    H_SCRIPT="$real"
}

# app_copy_pty INPUT [VAR=val ...] [-- ARGS...]: the copy on a pseudo-terminal with INPUT typed on it
# (what the program does only on a terminal, such as asking).
app_copy_pty() {
    local input="$1" cmd
    shift
    local -a envs=() args=()
    while [ "$#" -gt 0 ]; do
        if [ "$1" = "--" ]; then shift; args=("$@"); break; fi
        envs+=("$1"); shift
    done
    printf -v cmd '%q ' "$H_BASH" "$SB/app/script/MintApp_Remover.sh" "${args[@]+"${args[@]}"}"
    _exec "$input" 60 "${envs[@]+"${envs[@]}"}" -- "$(command -v script)" -qec "$cmd" /dev/null
    OUT="${OUT//$'\r'/}"
}
# make_data: the settings, the records and the leftovers the program makes in its own folders.
make_data() {
    mkdir -p "$SB/home/.config/mintapp-remover" "$SB/home/.local/state/mintapp-remover"
    printf 'language=en\n' > "$SB/home/.config/mintapp-remover/config"
    printf 'record\n' > "$SB/home/.local/state/mintapp-remover/removal-20261031-100000-1-1.txt"
    printf 'record\n' > "$SB/home/.local/state/mintapp-remover/clean-20261031-100000-1-1.txt"
    : > "$SB/home/.local/state/mintapp-remover/.lock"
    : > "$SB/home/.local/state/mintapp-remover/.tmp.AbCdEf"
    : > "$SB/home/.config/mintapp-remover/.tmp.XyZ123"
    sandbox_chown
}
# installed: a sandbox with the program installed and data made (the usual start of a case).
installed() {
    fresh
    make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
    app_copy -- install
    make_data
}
RECORDS=".local/state/mintapp-remover"
ONLY_RECORDS=$'./.local\n./.local/state\n./.local/state/mintapp-remover\n./.local/state/mintapp-remover/clean-20261031-100000-1-1.txt\n./.local/state/mintapp-remover/removal-20261031-100000-1-1.txt'

# The reference for the Exec key: the rules of the desktop entry specification, written
# independently of the program (string escapes first, then the quoting of the arguments, then %%;
# a lone % would be a field code, which the launcher does not use, so it shows as <FIELD CODE>).
exec_args() {
    python3 - "$1" <<'PYEOF'
import sys
v = sys.argv[1]
table = {'s': ' ', 'n': '\n', 't': '\t', 'r': '\r', '\\': '\\'}
out, i = [], 0
while i < len(v):
    if v[i] == '\\' and i + 1 < len(v) and v[i + 1] in table:
        out.append(table[v[i + 1]]); i += 2
    else:
        out.append(v[i]); i += 1
s = ''.join(out)
args, cur, quoted, started, i = [], '', False, False, 0
while i < len(s):
    c = s[i]
    if quoted:
        if c == '\\' and i + 1 < len(s) and s[i + 1] in '"`$\\':
            cur += s[i + 1]; i += 2; continue
        if c == '"':
            quoted = False; i += 1; continue
        cur += c; i += 1; continue
    if c == '"':
        quoted = True; started = True; i += 1; continue
    if c in ' \t':
        if started or cur:
            args.append(cur); cur = ''; started = False
        i += 1; continue
    cur += c; started = True; i += 1
if started or cur:
    args.append(cur)
def fields(a):
    r, i = '', 0
    while i < len(a):
        if a[i] == '%':
            if i + 1 < len(a) and a[i + 1] == '%':
                r += '%'; i += 2; continue
            r += '<FIELD CODE>'; i += 1; continue
        r += a[i]; i += 1
    return r
print('\n'.join(fields(a) for a in args))
PYEOF
}
# exec_value FILE: the value of the Exec key of a desktop entry.
exec_value() { sed -n 's/^Exec=//p' "$1"; }

# ------------------------------------------------------------ the paths ----
echo "-- install_data_dir and install_paths"
fresh
app_eval 'install_data_dir'
check_eq 'default: ~/.local/share' "$SB/home/.local/share" "$OUT"
app_eval 'install_data_dir' "XDG_DATA_HOME=$SB/xdg"
check_eq 'an absolute XDG_DATA_HOME is used' "$SB/xdg" "$OUT"
app_eval 'install_data_dir' "XDG_DATA_HOME=$SB/xdg/"
check_eq 'a trailing slash in XDG_DATA_HOME does not double' "$SB/xdg" "$OUT"
app_eval 'install_data_dir' 'XDG_DATA_HOME=relative/path'
check_eq 'a relative XDG_DATA_HOME is ignored (the specification says so)' "$SB/home/.local/share" "$OUT"
app_eval 'install_data_dir; echo "|$?"' 'HOME=relative'
check_eq 'a relative HOME gives no folder and fails' '|1' "$OUT"
app_eval 'install_data_dir; echo "|$?"' 'HOME='
check_eq 'an empty HOME gives no folder and fails' '|1' "$OUT"
app_eval 'install_paths; echo "$INSTALL_BIN|$INSTALL_DESKTOP|$INSTALL_ICON_ROOT"'
check_eq 'the three places' "$SB/home/$BIN_REL|$SB/home/$LAUNCHER_REL|$SB/home/.local/share/icons/hicolor" "$OUT"
app_eval 'install_paths; echo "$INSTALL_BIN|$INSTALL_DESKTOP|$INSTALL_ICON_ROOT"' "XDG_DATA_HOME=$SB/xdg"
check_eq 'with XDG_DATA_HOME the launcher and the icon move, the command does not' \
    "$SB/home/$BIN_REL|$SB/xdg/applications/mintapp-remover.desktop|$SB/xdg/icons/hicolor" "$OUT"
app_eval 'install_paths; echo "[$INSTALL_BIN]|$?"' 'HOME=relative'
check_eq 'install_paths fails and sets nothing without a usable HOME' '[]|1' "$OUT"

# ---------------------------------------------------------- PNG and sizes ----
echo "-- png_dimensions and install_icon_size"
fresh
make_png "$SB/home/p1.png" 1024 1024; make_png "$SB/home/p2.png" 48 32; make_png "$SB/home/p3.png" 65536 7
sandbox_chown
app_eval 'png_dimensions "$HOME/p1.png"'
check_eq 'a PNG: width and height' '1024 1024' "$OUT"
app_eval 'png_dimensions "$HOME/p2.png"'
check_eq 'width and height are not swapped' '48 32' "$OUT"
app_eval 'png_dimensions "$HOME/p3.png"'
check_eq 'a size beyond 16 bits is read whole' '65536 7' "$OUT"
printf 'not a png at all, but long enough to have 24 bytes' > "$SB/home/text.png"
printf '\x89PNG\r\n\x1a\n' > "$SB/home/short.png"
{ printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIDAT'; printf '\x00\x00\x01\x00\x00\x00\x01\x00'; } > "$SB/home/wrongchunk.png"
: > "$SB/home/empty.png"
{ printf '\x89PNX\r\n\x1a\n\x00\x00\x00\x0dIHDR'; printf '\x00\x00\x01\x00\x00\x00\x01\x00'; } > "$SB/home/wrongsig.png"
sandbox_chown
for f in text short wrongchunk wrongsig empty missing; do
    app_eval 'png_dimensions "$HOME/'"$f"'.png"; echo "|$?"'
    check_eq "not a PNG ($f): nothing printed and it fails" '|1' "$OUT"
done
size_of() { app_eval 'install_icon_size '"$1 $2"'; echo "|$?"'; printf '%s' "$OUT"; }
check_eq '1024 px goes under 512x512 (hicolor has nothing bigger)' '512|0' "$(size_of 1024 1024)"
check_eq '512 px' '512|0' "$(size_of 512 512)"
check_eq '300 px goes under the largest size that fits: 256' '256|0' "$(size_of 300 300)"
check_eq '100 px goes under 96' '96|0' "$(size_of 100 100)"
check_eq '48 px' '48|0' "$(size_of 48 48)"
check_eq '16 px, the smallest' '16|0' "$(size_of 16 16)"
check_eq '15 px is too small' '|1' "$(size_of 15 15)"
check_eq 'a non-square icon is refused' '|1' "$(size_of 512 256)"
check_eq 'not a number is refused' '|1' "$(size_of abc abc)"

# ----------------------------------------------------- the Exec quoting ----
echo "-- desktop_exec_quote (against the specification)"
quote_roundtrip() {
    # $1 label, $2 path. The path travels in the environment, so no quoting of ours is involved.
    app_eval 'desktop_exec_quote "$P" && printf "%s" "$REPLY"' "P=$2"
    local value="$OUT"
    if command -v python3 >/dev/null 2>&1; then
        check_eq "Exec round trip: $1" "$2" "$(exec_args "$value")"
    else
        skip_case "Exec round trip: $1 (python3 is not available)"
    fi
}
quote_roundtrip 'plain path' '/home/user/.local/bin/mintapp-remover'
quote_roundtrip 'a space' '/home/some user/.local/bin/mintapp-remover'
quote_roundtrip 'a dollar sign' '/home/us$er/bin/x'
quote_roundtrip 'a double quote' '/home/us"er/bin/x'
quote_roundtrip 'a backtick' '/home/us`er/bin/x'
quote_roundtrip 'a backslash' '/home/us\er/bin/x'
quote_roundtrip 'a backslash before a quote' '/home/us\"er/bin/x'
quote_roundtrip 'two backslashes' '/home/a\\b/bin/x'
quote_roundtrip 'a percent sign (a field code if left alone)' '/home/100%/bin/x'
quote_roundtrip 'a percent and a letter' '/home/%u/bin/x'
quote_roundtrip 'a single quote, an ampersand and a semicolon' "/home/it's&a;b/bin/x"
quote_roundtrip 'accents' '/home/josé/bin/x'
app_eval 'desktop_exec_quote "$P"; echo "|$?"' $'P=/home/a\nb/bin/x'
check_eq 'a newline in the path is refused' '|1' "$OUT"
app_eval 'desktop_exec_quote "$P"; echo "|$?"' $'P=/home/a\tb/bin/x'
check_eq 'a tab in the path is refused' '|1' "$OUT"
app_eval 'desktop_exec_quote "$P"; printf "%s" "$REPLY"' 'P=/a/b'
check_eq 'the value is always in double quotes' '"/a/b"' "$OUT"

# ---------------------------------------------------------- a fresh install ----
echo "-- install"
fresh
make_png "$SB/icon256.png" 256 256
cp -- "$SB/icon256.png" "$SB/app/assets/$ICON_NAME"
sandbox_chown
app_copy -- install
H="$SB/home"
check_eq 'install ends well' 0 "$RC"
check_eq 'it lists the three files as installed' 3 "$(count_of "$OUT" '(installed)')"
assert_contains 'the command line' "$OUT" "  command   $H/$BIN_REL  (installed)"
assert_contains 'the icon line (256 px goes under 256x256)' "$OUT" "  icon      $H/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png  (installed)"
assert_contains 'the launcher line' "$OUT" "  launcher  $H/$LAUNCHER_REL  (installed)"
assert_contains 'the banner names the version' "$OUT" 'Installing MintApp Remover '
check_eq 'the command is a copy of the program' yes "$(cmp -s "$SB/app/script/MintApp_Remover.sh" "$H/$BIN_REL" && echo yes || echo no)"
check_eq 'the command is executable (755)' 755 "$(mode "$H/$BIN_REL")"
check_eq 'the launcher is readable by all, writable by its owner (644)' 644 "$(mode "$H/$LAUNCHER_REL")"
check_eq 'the icon is a copy of the file beside the program' yes "$(cmp -s "$SB/icon256.png" "$H/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png" && echo yes || echo no)"
check_eq 'no temporary file is left' 0 "$(tmp_count)"
check_eq 'it creates no configuration' no "$(exists "$H/.config")"
check_eq 'it creates no state folder' no "$(exists "$H/.local/state")"
check_eq 'it never asks for administrator rights' 0 "$(sudo_log | wc -l)"
check_eq 'it never touches apt' 0 "$(apt_log | wc -l)"
launcher="$(cat "$H/$LAUNCHER_REL")"
assert_contains 'launcher: it is a desktop entry' "$launcher" '[Desktop Entry]'
assert_contains 'launcher: an application' "$launcher" 'Type=Application'
assert_contains 'launcher: the name' "$launcher" 'Name=MintApp Remover'
assert_contains 'launcher: Exec is the installed command, in quotes' "$launcher" "Exec=\"$H/$BIN_REL\""
assert_contains 'launcher: TryExec hides the entry if the command goes' "$launcher" "TryExec=$H/$BIN_REL"
assert_contains 'launcher: the icon is the installed one, by name' "$launcher" 'Icon=mintapp-remover'
assert_contains 'launcher: StartupWMClass is the class of the windows' "$launcher" 'StartupWMClass=mintapp-remover'
assert_contains 'launcher: it sits in the System category' "$launcher" 'Categories=System;'
assert_contains 'launcher: names in Spanish' "$launcher" 'Comment[es]=Desinstala aplicaciones'
check_eq 'launcher: it does not need a terminal (zenity is here)' 1 "$(count_of "$launcher" 'Terminal=false')"
if command -v desktop-file-validate >/dev/null 2>&1; then
    check_eq 'desktop-file-validate finds nothing to say about the launcher' '' "$(desktop-file-validate "$H/$LAUNCHER_REL" 2>&1 || true)"
else
    skip_case 'desktop-file-validate is not available'
fi
GUI_CLASS_OF_PROGRAM="$(grep -m1 -oE 'GUI_CLASS="[a-z-]+"' "$H_SCRIPT" | cut -d'"' -f2 || true)"
if [ -n "$GUI_CLASS_OF_PROGRAM" ]; then
    check_eq 'StartupWMClass is the class the windows really carry' "$GUI_CLASS_OF_PROGRAM" "$(sed -n 's/^StartupWMClass=//p' "$H/$LAUNCHER_REL")"
else
    skip_case 'the class of the windows is not a plain assignment'
fi
if command -v python3 >/dev/null 2>&1; then
    check_eq 'launcher: Exec decodes to the installed command, alone' "$H/$BIN_REL" "$(exec_args "$(exec_value "$H/$LAUNCHER_REL")")"
fi

echo "-- install: the installed command runs"
app_run '' -- --version
real_version="$OUT"
H_SCRIPT_SAVED="$H_SCRIPT"; H_SCRIPT="$H/$BIN_REL"
app_run '' -- --version
H_SCRIPT="$H_SCRIPT_SAVED"
check_eq 'the installed copy reports the same version' "$real_version" "$OUT"

echo "-- install twice"
before_bin="$(inode "$H/$BIN_REL")"; before_launcher="$(inode "$H/$LAUNCHER_REL")"
before_icon="$(inode "$H/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png")"
app_copy -- install
check_eq 'the second run ends well' 0 "$RC"
check_eq 'everything is up to date' 3 "$(count_of "$OUT" '(up to date)')"
check_eq 'nothing is called installed again' 0 "$(count_of "$OUT" '(installed)')"
check_eq 'the command is not rewritten' "$before_bin" "$(inode "$H/$BIN_REL")"
check_eq 'the launcher is not rewritten' "$before_launcher" "$(inode "$H/$LAUNCHER_REL")"
check_eq 'the icon is not rewritten' "$before_icon" "$(inode "$H/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png")"
check_eq 'still no temporary file' 0 "$(tmp_count)"

echo "-- install repairs what was changed"
printf '#!/bin/sh\necho tampered\n' > "$H/$BIN_REL"; chmod 755 "$H/$BIN_REL"
app_copy -- install
assert_contains 'a changed command is updated' "$OUT" "command   $H/$BIN_REL  (updated)"
check_eq 'and is the program again' yes "$(cmp -s "$SB/app/script/MintApp_Remover.sh" "$H/$BIN_REL" && echo yes || echo no)"
chmod 700 "$H/$BIN_REL"
app_copy -- install
assert_contains 'a command with the wrong mode is updated' "$OUT" "command   $H/$BIN_REL  (updated)"
check_eq 'and is executable again' 755 "$(mode "$H/$BIN_REL")"
printf '[Desktop Entry]\nName=Old\n' > "$H/$LAUNCHER_REL"
app_copy -- install
assert_contains 'a changed launcher is updated' "$OUT" "launcher  $H/$LAUNCHER_REL  (updated)"
assert_contains 'and says what it should' "$(cat "$H/$LAUNCHER_REL")" 'Name=MintApp Remover'
chmod 600 "$H/$LAUNCHER_REL"
app_copy -- install
assert_contains 'a launcher with the wrong mode is updated' "$OUT" "launcher  $H/$LAUNCHER_REL  (updated)"
check_eq 'and is readable by all again' 644 "$(mode "$H/$LAUNCHER_REL")"
printf 'not an icon' > "$H/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png"
app_copy -- install
assert_contains 'a changed icon is updated' "$OUT" "(updated)"
check_eq 'and is the picture again' yes "$(cmp -s "$SB/icon256.png" "$H/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png" && echo yes || echo no)"
check_eq 'no temporary file is left after the repairs' 0 "$(tmp_count)"

echo "-- install in Spanish"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- install
check_eq 'it ends well' 0 "$RC"
assert_contains 'the banner is in Spanish' "$OUT" 'Instalando MintApp Remover '
assert_contains 'the labels and states are in Spanish' "$OUT" '  comando   '
assert_contains 'the state is in Spanish' "$OUT" '(instalado)'
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- install
assert_contains 'the second run says "al día"' "$OUT" '(al día)'

# -------------------------------------------------- the PATH and the end ----
echo "-- install: PATH"
fresh
make_png "$SB/icon256.png" 256 256; cp -- "$SB/icon256.png" "$SB/app/assets/$ICON_NAME"; sandbox_chown
app_copy -- install
assert_contains 'the folder of the command is not in PATH: it says so' "$OUT" "$SB/home/.local/bin is not in your PATH"
assert_contains 'it shows the line to add, as it has to be typed' "$OUT" '  export PATH="$HOME/.local/bin:$PATH"'
assert_contains 'it gives the full path to run it now' "$OUT" "  $SB/home/$BIN_REL"
check_eq 'the warning does not make it fail' 0 "$RC"
app_copy "PATH=$SB/home/.local/bin:$SB/bin:$H_SYS_PATH" -- install
assert_not_contains 'with the folder in PATH there is no warning' "$OUT" 'is not in your PATH'
assert_contains 'it names the command, to be run by name' "$OUT" $'run:\n  mintapp-remover'
app_copy "PATH=$SB/home/.local/bin/:$SB/bin:$H_SYS_PATH" -- install
assert_contains 'a PATH entry with a trailing slash is a different text: the warning stays (the safe side)' "$OUT" 'is not in your PATH'

echo "-- install: XDG_DATA_HOME"
fresh
make_png "$SB/icon256.png" 256 256; cp -- "$SB/icon256.png" "$SB/app/assets/$ICON_NAME"; sandbox_chown
app_copy "XDG_DATA_HOME=$SB/home/data" -- install
check_eq 'the launcher goes to XDG_DATA_HOME' yes "$(exists "$SB/home/data/applications/mintapp-remover.desktop")"
check_eq 'the icon goes to XDG_DATA_HOME' yes "$(exists "$SB/home/data/icons/hicolor/256x256/apps/mintapp-remover.png")"
check_eq 'the command still goes to ~/.local/bin' yes "$(exists "$SB/home/$BIN_REL")"
check_eq 'nothing goes to ~/.local/share' no "$(exists "$SB/home/.local/share")"

# ------------------------------------------------------------ the icon ----
echo "-- install: the icon"
fresh
app_copy -- install
check_eq 'without an icon file it still ends well' 0 "$RC"
assert_contains 'it says there is no usable icon' "$OUT" 'No usable icon found'
check_eq 'it lists no icon line' 0 "$(count_of "$OUT" '  icon  ')"
check_eq 'no icon folder is made' no "$(exists "$SB/home/.local/share/icons")"
assert_contains 'the launcher takes a generic icon of the theme' "$(cat "$SB/home/$LAUNCHER_REL")" 'Icon=applications-system'
for kind in 'text:not a png at all, 40 bytes or more of text....' 'tiny:png8' 'wide:png512x256' 'small:png15'; do
    fresh
    case "$kind" in
        text:*) printf 'not a png at all, 40 bytes or more of text....' > "$SB/app/assets/$ICON_NAME" ;;
        tiny:*) make_png "$SB/app/assets/$ICON_NAME" 8 8 ;;
        wide:*) make_png "$SB/app/assets/$ICON_NAME" 512 256 ;;
        small:*) make_png "$SB/app/assets/$ICON_NAME" 15 15 ;;
    esac
    sandbox_chown
    app_copy -- install
    check_eq "icon (${kind%%:*}): refused, the rest installed" "0|yes|no" "$RC|$(exists "$SB/home/$BIN_REL")|$(exists "$SB/home/.local/share/icons")"
    assert_contains "icon (${kind%%:*}): it says there is no usable icon" "$OUT" 'No usable icon found'
done
fresh
make_png "$SB/app/assets/$ICON_NAME" 300 300; sandbox_chown
app_copy -- install
check_eq 'a 300 px icon is filed under 256x256' yes "$(exists "$SB/home/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png")"
make_png "$SB/app/assets/$ICON_NAME" 1024 1024; sandbox_chown
app_copy -- install
check_eq 'a new icon of another size is filed under its own size' yes "$(exists "$SB/home/.local/share/icons/hicolor/512x512/apps/mintapp-remover.png")"
check_eq 'and the old copy is gone, so it cannot show the old picture' no "$(exists "$SB/home/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png")"
rm -f -- "$SB/app/assets/$ICON_NAME"
app_copy -- install
assert_contains 'with no icon file now, the icon installed before is kept' "$OUT" '(kept)'
assert_not_contains 'and it does not complain' "$OUT" 'No usable icon found'
assert_contains 'and the launcher still names it' "$(cat "$SB/home/$LAUNCHER_REL")" 'Icon=mintapp-remover'
check_eq 'the kept icon is still there' yes "$(exists "$SB/home/$ICON512_REL")"
echo "-- install: the embedded icon"
fresh keep
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy -- install
check_eq 'with the icon inside the program, the file beside it is not used: 512x512, not 256x256' "yes|no" "$(exists "$SB/home/$ICON512_REL")|$(exists "$SB/home/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png")"
embedded_png "$SB/embedded.png"
check_eq 'the installed icon is the embedded one, whole' yes "$(cmp -s "$SB/embedded.png" "$SB/home/$ICON512_REL" && echo yes || echo no)"
check_eq 'no temporary file is left' 0 "$(tmp_count)"
# A damaged block (cut short: it no longer ends with the IEND chunk) is not used.
fresh
awk '/^#@/ { n++; if (n > 5) next } { print }' "$H_SCRIPT" > "$SB/app/script/MintApp_Remover.sh"
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy -- install
check_eq 'a damaged embedded icon: the file beside the program is installed instead' yes "$(exists "$SB/home/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png")"
check_eq 'and the damaged one is not installed' no "$(exists "$SB/home/$ICON512_REL")"
rm -f -- "$SB/app/assets/$ICON_NAME"
rm -rf -- "$SB/home/.local/share/icons"
app_copy -- install
check_eq 'a damaged embedded icon and no file beside the program: ends well, no icon' "0|no" "$RC|$(exists "$SB/home/.local/share/icons")"
assert_contains 'and it says there is no usable icon' "$OUT" 'No usable icon found'

echo "-- install: the icon of the repository"
fresh
app_run '' -- install
check_eq 'the real program installs with its real icon' 0 "$RC"
check_eq 'it lists one icon line' 1 "$(count_of "$OUT" '  icon  ')"
installed_icon="$(find "$SB/home/.local/share/icons/hicolor" -name mintapp-remover.png | head -n 1)"
embedded_png "$SB/embedded.png"
check_eq 'the installed icon is the one inside the program, whole' yes "$(cmp -s "$SB/embedded.png" "$installed_icon" && echo yes || echo no)"
check_eq 'it is filed under 512x512, the largest size hicolor has' yes "$(exists "$SB/home/$ICON512_REL")"
repo_icon="$H_REPO_DIR/assets/$ICON_NAME"
if [ ! -r "$repo_icon" ]; then
    skip_case "the repository has no assets/$ICON_NAME beside the program"
elif ! command -v python3 >/dev/null 2>&1; then
    skip_case 'the icon inside the program is the same image as the one in assets/ (python3 is not available)'
else
    check_eq 'the icon inside the program is the same image as the one in assets/, pixel for pixel' yes "$(png_same_image "$SB/embedded.png" "$repo_icon")"
fi

# ------------------------------------------------------------- the launcher ----
echo "-- install: Terminal in the launcher"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy "PATH=$SB/tools" -- install
check_eq 'without zenity it still ends well, with no apt, no sudo and no zenity at all' 0 "$RC"
assert_contains 'without zenity it says the launcher opens a terminal' "$OUT" 'zenity is not installed'
check_eq 'and the launcher asks the desktop for one' 1 "$(count_of "$(cat "$SB/home/$LAUNCHER_REL")" 'Terminal=true')"
app_copy "PATH=$SB/tools:$SB/bin" -- install
check_eq 'with zenity in PATH it ends well' 0 "$RC"
assert_not_contains 'with zenity it says nothing about it' "$OUT" 'zenity is not installed'
check_eq 'and the launcher needs no terminal' 1 "$(count_of "$(cat "$SB/home/$LAUNCHER_REL")" 'Terminal=false')"
assert_contains 'the launcher is updated when zenity appears' "$OUT" 'launcher  '

echo "-- install: an odd HOME"
new_sandbox
ODD="$SB/ho me/it's \$x \"q\" \`b\` \\w %u"
mkdir -p "$SB/app/script" "$SB/app/assets" "$ODD"
copy_program "$SB/app/script/MintApp_Remover.sh"; make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
chown_odd() { if [ "$(id -u)" -eq 0 ]; then chown -R "$H_APP_UID:$H_APP_GID" "$SB/ho me"; fi; }; chown_odd
app_copy "HOME=$ODD" -- install
check_eq 'a HOME with spaces, quotes, dollars, backticks, backslashes and a percent sign installs' 0 "$RC"
odd_launcher="$ODD/.local/share/applications/mintapp-remover.desktop"
check_eq 'the launcher is there' yes "$(exists "$odd_launcher")"
if command -v python3 >/dev/null 2>&1; then
    check_eq 'its Exec is exactly the installed command, as one argument' "$ODD/.local/bin/mintapp-remover" "$(exec_args "$(exec_value "$odd_launcher")")"
fi
if command -v desktop-file-validate >/dev/null 2>&1; then
    check_eq 'desktop-file-validate accepts it' '' "$(desktop-file-validate "$odd_launcher" 2>&1 || true)"
fi

# ----------------------------------------------------------------- errors ----
echo "-- install: errors"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy HOME= -- install
check_eq 'without a HOME it fails' 1 "$RC"
assert_contains 'and says why' "$OUT" 'HOME is not set to an absolute folder'
app_copy HOME=relative -- install
check_eq 'with a relative HOME it fails' 1 "$RC"
check_eq 'and writes nothing' no "$(exists "$SB/home/.local")"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256
mkdir -p "$SB/home/.local/bin/mintapp-remover"; sandbox_chown
app_copy -- install
check_eq 'a folder where the command goes: it fails' 1 "$RC"
assert_contains 'and names the path it could not write' "$OUT" "Could not write $SB/home/$BIN_REL."
check_eq 'it stops there: no launcher' no "$(exists "$SB/home/$LAUNCHER_REL")"
check_eq 'it stops there: no icon' no "$(exists "$SB/home/.local/share")"
check_eq 'the folder is still a folder' yes "$([ -d "$SB/home/.local/bin/mintapp-remover" ] && echo yes || echo no)"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256
mkdir -p "$SB/home/.local/bin"; chmod 555 "$SB/home/.local/bin"; sandbox_chown
app_copy -- install
if [ "$(id -u)" -eq 0 ] || [ ! -w "$SB/home/.local/bin" ]; then
    check_eq 'a folder that cannot be written: it fails' 1 "$RC"
    assert_contains 'and says so' "$OUT" 'Could not write'
    check_eq 'and leaves no temporary file' 0 "$(tmp_count)"
else
    skip_case 'a folder that cannot be written (the sandbox user can write to it)'
fi
chmod 755 "$SB/home/.local/bin" 2>/dev/null || true
fresh
mkdir -p "$SB/home/.local/share/applications/mintapp-remover.desktop"; sandbox_chown
app_copy -- install
check_eq 'a folder where the launcher goes: it fails' 1 "$RC"
assert_contains 'and names the path it could not write' "$OUT" "Could not write $SB/home/$LAUNCHER_REL."
echo "-- install: a script that is not a file"
fresh
_exec "$(cat "$H_SCRIPT")" 60 -- "$H_BASH" -s install
check_eq 'piped into bash there is no file to copy: it fails' 1 "$RC"
assert_contains 'and says so' "$OUT" 'Cannot read this script as a file'
check_eq 'and writes nothing' 0 "$(tree | wc -l)"
# Without the icon lines: they come after main, so a program that exits early (--version does) leaves
# whoever writes the pipe with SIGPIPE, and the status of the pipeline would be that of the writer.
_exec "$(sed '/^#@/d' "$H_SCRIPT")" 60 -- "$H_BASH" -s -- --version
check_eq 'piped into bash the program still runs (the guard at the end of the file does not need BASH_SOURCE)' 0 "$RC"
assert_contains 'and answers' "$OUT" 'MintApp Remover '
_exec "$(cat "$H_SCRIPT")" 60 -- "$H_BASH" -s -- --version
assert_contains 'with the icon lines too it answers' "$OUT" 'MintApp Remover '
echo "-- install: never as root"
if [ "$(id -u)" -eq 0 ]; then
    fresh
    H_AS_ROOT=1 _exec '' 60 -- "$H_BASH" "$SB/app/script/MintApp_Remover.sh" install
    check_eq 'as root it refuses' 1 "$RC"
    assert_contains 'and says why' "$OUT" 'Do not run MintApp Remover as root'
    check_eq 'and writes nothing' 0 "$(tree | wc -l)"
else
    skip_case 'as root it refuses (the suite is not run as root)'
fi

# ----------------------------------------------------------- never through a link ----
echo "-- install: links"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256
mkdir -p "$SB/home/.local/bin" "$SB/home/elsewhere"
printf 'precious\n' > "$SB/home/elsewhere/target"
ln -s "$SB/home/elsewhere/target" "$SB/home/$BIN_REL"
sandbox_chown
app_copy -- install
check_eq 'a link where the command goes is replaced, not followed' 0 "$RC"
check_eq 'what the link pointed to is untouched' 'precious' "$(cat "$SB/home/elsewhere/target")"
check_eq 'the command is now a real file' no "$([ -L "$SB/home/$BIN_REL" ] && echo yes || echo no)"
check_eq 'and the program' yes "$(cmp -s "$SB/app/script/MintApp_Remover.sh" "$SB/home/$BIN_REL" && echo yes || echo no)"
echo "-- install: a command that is a link to the program is already right"
fresh
mkdir -p "$SB/home/.local/bin"
ln -s "$SB/app/script/MintApp_Remover.sh" "$SB/home/$BIN_REL"
chmod 755 "$SB/app/script/MintApp_Remover.sh"
sandbox_chown
app_copy -- install
assert_contains 'a link to an identical program counts as up to date' "$OUT" "command   $SB/home/$BIN_REL  (up to date)"
check_eq 'and stays a link' yes "$([ -L "$SB/home/$BIN_REL" ] && echo yes || echo no)"

# ------------------------------------------------------------ the command line ----
echo "-- command line"
fresh
app_copy -- install --gui
check_eq 'install takes no --gui' 2 "$RC"
assert_contains 'it names the option' "$OUT" 'Unrecognized option: --gui'
check_eq 'and installs nothing' 0 "$(tree | wc -l)"
app_copy -- install extra
check_eq 'install takes no other word' 2 "$RC"
app_copy -- uninstall --terminal
check_eq 'uninstall takes no --terminal' 2 "$RC"
app_copy -- uninstall --show-help
check_eq 'uninstall takes no --show-help' 2 "$RC"
app_copy -- install --help
check_eq 'install --help prints the usage' 0 "$RC"
assert_contains 'the usage names install' "$OUT" '       MintApp_Remover.sh install'
assert_contains 'the usage names uninstall and its data option' "$OUT" 'MintApp_Remover.sh uninstall [DATA]'
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- --help
assert_contains 'the Spanish usage names install' "$OUT" '     MintApp_Remover.sh install'
assert_contains 'the Spanish usage names uninstall and its data option' "$OUT" 'MintApp_Remover.sh uninstall [DATOS]'
app_copy -- --install
check_eq '--install is not an option' 2 "$RC"
app_copy -- install uninstall
check_eq 'two commands are refused' 2 "$RC"
for lang in en es; do
    app_copy MINTAPP_LANG=$lang -- --help
    assert_contains "--help documents install ($lang)" "$OUT" '  install   '
    assert_contains "--help documents uninstall ($lang)" "$OUT" '  uninstall '
done
app_copy MINTAPP_LANG=en -- --help
assert_contains 'the English help says where it installs' "$OUT" 'in your own folders (no sudo needed)'
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- --help
assert_contains 'the Spanish help says where it installs' "$OUT" 'en tus carpetas (sin sudo)'
check_eq 'install and uninstall do not run the usual start (no lock, no state, no terminal)' no "$(exists "$SB/home/.local/state")"

# --------------------------------------------------------------- uninstall ----
echo "-- uninstall"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy -- install
app_copy -- uninstall
check_eq 'uninstall ends well' 0 "$RC"
check_eq 'it lists the three files as removed' 3 "$(count_of "$OUT" '(removed)')"
assert_contains 'the command line' "$OUT" "  command   $SB/home/$BIN_REL  (removed)"
assert_contains 'the launcher line' "$OUT" "  launcher  $SB/home/$LAUNCHER_REL  (removed)"
assert_contains 'the icon line' "$OUT" "mintapp-remover.png  (removed)"
check_eq 'nothing is left in the home, not even an empty folder' 0 "$(tree | wc -l)"
check_eq 'the home itself is never removed' yes "$(exists "$SB/home")"
check_eq 'no temporary file' 0 "$(tmp_count)"
app_copy -- uninstall
check_eq 'a second uninstall ends well' 0 "$RC"
assert_contains 'and says there is nothing to remove' "$OUT" 'MintApp Remover is not installed in your folders: nothing to remove.'
check_eq 'it touches nothing' 0 "$(tree | wc -l)"
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- install
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- uninstall
assert_contains 'in Spanish' "$OUT" 'Quitando MintApp Remover de tus carpetas:'
assert_contains 'the state in Spanish' "$OUT" '(eliminado)'
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- uninstall
assert_contains 'nothing to remove, in Spanish' "$OUT" 'no está instalado en tus carpetas'

echo "-- uninstall: nothing installed"
fresh
mkdir -p "$SB/home/.local/bin" "$SB/home/.local/share/icons/hicolor/256x256/apps"; sandbox_chown
app_copy -- uninstall
check_eq 'it ends well' 0 "$RC"
assert_contains 'it says there is nothing to remove' "$OUT" 'nothing to remove'
check_eq 'empty folders it did not make are left alone' $'./.local\n./.local/bin\n./.local/share\n./.local/share/icons\n./.local/share/icons/hicolor\n./.local/share/icons/hicolor/256x256\n./.local/share/icons/hicolor/256x256/apps' "$(tree)"

echo "-- uninstall: what is not ours stays"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256
mkdir -p "$SB/home/.local/bin" "$SB/home/.local/share/applications" "$SB/home/.local/share/icons/hicolor/256x256/apps"
printf 'other\n' > "$SB/home/.local/bin/other-tool"
printf '[Desktop Entry]\nName=Other\n' > "$SB/home/.local/share/applications/other.desktop"
printf 'png\n' > "$SB/home/.local/share/icons/hicolor/256x256/apps/other.png"
sandbox_chown
app_copy -- install
app_copy -- uninstall
check_eq 'what other programs keep there is still there' \
    $'./.local\n./.local/bin\n./.local/bin/other-tool\n./.local/share\n./.local/share/applications\n./.local/share/applications/other.desktop\n./.local/share/icons\n./.local/share/icons/hicolor\n./.local/share/icons/hicolor/256x256\n./.local/share/icons/hicolor/256x256/apps\n./.local/share/icons/hicolor/256x256/apps/other.png' \
    "$(tree)"
check_eq 'the other command was not touched' 'other' "$(cat "$SB/home/.local/bin/other-tool")"

echo "-- uninstall: a folder with something else in it is not removed, and the walk up stops there"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256
mkdir -p "$SB/home/.local/share/icons/hicolor/256x256/apps"
printf 'x\n' > "$SB/home/.local/share/icons/hicolor/index.theme"
sandbox_chown
app_copy -- install
app_copy -- uninstall
check_eq 'the icon folders that hold something else stay' yes "$(exists "$SB/home/.local/share/icons/hicolor/index.theme")"
check_eq 'the empty folders of the icon go' no "$(exists "$SB/home/.local/share/icons/hicolor/256x256")"
check_eq 'the folders above stay' yes "$(exists "$SB/home/.local/share/icons")"

echo "-- uninstall: only part of it is installed"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy -- install
rm -f -- "$SB/home/$BIN_REL" "$SB/home/.local/share/icons/hicolor/256x256/apps/mintapp-remover.png"
app_copy -- uninstall
check_eq 'the rest is removed' 0 "$RC"
assert_contains 'the launcher is removed' "$OUT" '(removed)'
check_eq 'and the home is empty again' 0 "$(tree | wc -l)"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy -- install
rm -f -- "$SB/home/$LAUNCHER_REL"
app_copy -- uninstall
assert_contains 'what was not there is said' "$OUT" '(not there)'
check_eq 'and the command and the icon are removed' 0 "$(tree | wc -l)"

echo "-- uninstall: links"
fresh
mkdir -p "$SB/home/.local/bin" "$SB/home/elsewhere"
printf 'precious\n' > "$SB/home/elsewhere/target"
ln -s "$SB/home/elsewhere/target" "$SB/home/$BIN_REL"
sandbox_chown
app_copy -- uninstall
check_eq 'a link is removed' no "$(exists "$SB/home/$BIN_REL")"
check_eq 'what it pointed to is not' 'precious' "$(cat "$SB/home/elsewhere/target")"
fresh
mkdir -p "$SB/home/.local/bin" "$SB/home/elsewhere"
ln -s "$SB/home/elsewhere/missing" "$SB/home/$BIN_REL"
sandbox_chown
app_copy -- uninstall
check_eq 'a broken link counts as installed and is removed' no "$(exists "$SB/home/$BIN_REL")"

echo "-- uninstall: what cannot be removed"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy -- install
rm -f -- "$SB/home/$BIN_REL"; mkdir -p "$SB/home/$BIN_REL/inside"; sandbox_chown
app_copy -- uninstall
check_eq 'a folder where the command was: it fails' 1 "$RC"
assert_contains 'and names it' "$OUT" "Could not remove $SB/home/$BIN_REL."
check_eq 'it still removed the launcher' no "$(exists "$SB/home/$LAUNCHER_REL")"
check_eq 'and the icon' no "$(exists "$SB/home/.local/share/icons")"
check_eq 'and the folder is untouched' yes "$([ -d "$SB/home/$BIN_REL/inside" ] && echo yes || echo no)"
assert_not_contains 'it does not claim to be done' "$OUT" 'Done.'

echo "-- uninstall: no usable HOME, and never as root"
fresh
app_copy HOME= -- uninstall
check_eq 'without a HOME it fails' 1 "$RC"
assert_contains 'and says why' "$OUT" 'HOME is not set to an absolute folder'
if [ "$(id -u)" -eq 0 ]; then
    make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
    app_copy -- install
    H_AS_ROOT=1 _exec '' 60 -- "$H_BASH" "$SB/app/script/MintApp_Remover.sh" uninstall
    check_eq 'as root it refuses' 1 "$RC"
    check_eq 'and removes nothing' yes "$(exists "$SB/home/$BIN_REL")"
else
    skip_case 'as root it refuses (the suite is not run as root)'
fi

# -------------------------------------------------- the data (F5.3) ----
echo "-- uninstall: data, no terminal, no option (settings go, records stay)"
installed
before_tree="$(tree)"
app_copy -- uninstall
check_eq 'it ends well' 0 "$RC"
assert_contains 'the settings are removed' "$OUT" "settings  $SB/home/.config/mintapp-remover  (removed)"
assert_contains 'the records are kept' "$OUT" "records   $SB/home/$RECORDS  (kept)"
assert_not_contains 'without a terminal it does not ask' "$OUT" 'What should happen'
assert_contains 'it says how to delete what was kept' "$OUT" 'MintApp_Remover.sh uninstall --purge'
assert_contains 'and ends with Done.' "$OUT" 'Done.'
check_eq 'what is left: the records, nothing else' "$ONLY_RECORDS" "$(tree)"
check_eq 'the settings folder is gone' no "$(exists "$SB/home/.config")"
check_eq 'the records are untouched' record "$(cat "$SB/home/$RECORDS/removal-20261031-100000-1-1.txt")"
check_eq 'the lock file and the temporary file of the records folder are gone' 0 "$(find "$SB/home/$RECORDS" -name '.lock' -o -name '.tmp.*' | wc -l)"
check_eq 'the program itself is gone too' no "$(exists "$SB/home/$BIN_REL")"
installed
app_copy -- uninstall --keep-records
check_eq '--keep-records is what happens without an option' "$ONLY_RECORDS" "$(tree)"

echo "-- uninstall --keep-all"
installed
app_copy -- uninstall --keep-all
check_eq 'it ends well' 0 "$RC"
assert_contains 'the settings are kept' "$OUT" "settings  $SB/home/.config/mintapp-remover  (kept)"
assert_contains 'the records are kept' "$OUT" "records   $SB/home/$RECORDS  (kept)"
check_eq 'the settings are untouched' 'language=en' "$(cat "$SB/home/.config/mintapp-remover/config")"
check_eq 'the records are untouched' record "$(cat "$SB/home/$RECORDS/clean-20261031-100000-1-1.txt")"
check_eq 'the temporary files and the lock file are gone from both folders' 0 "$(find "$SB/home/.config" "$SB/home/$RECORDS" -name '.lock' -o -name '.tmp.*' | wc -l)"
check_eq 'the command, the launcher and the icon are gone' nono "$(exists "$SB/home/.local/bin")$(exists "$SB/home/.local/share")"
assert_contains 'it says how to delete what was kept' "$OUT" 'uninstall --purge'

echo "-- uninstall --purge"
installed
app_copy -- uninstall --purge
check_eq 'it ends well' 0 "$RC"
assert_contains 'the settings are removed' "$OUT" "settings  $SB/home/.config/mintapp-remover  (removed)"
assert_contains 'the records are removed' "$OUT" "records   $SB/home/$RECORDS  (removed)"
assert_not_contains 'it has nothing left to point to' "$OUT" 'uninstall --purge'
check_eq 'no trace: the home is empty' 0 "$(tree | wc -l)"
check_eq 'and still there' yes "$(exists "$SB/home")"
check_eq 'a second --purge has nothing to remove' 'nothing' "$(app_copy -- uninstall --purge; [ "$RC" -eq 0 ] && grep -q 'nothing to remove' <<< "$OUT" && echo nothing)"

echo "-- uninstall: the options"
installed
before_tree="$(tree)"
app_copy -- uninstall --keep-records --purge
check_eq 'two different options are refused' 2 "$RC"
assert_contains 'it says to use only one' "$OUT" 'Use only one of --keep-records, --keep-all and --purge.'
check_eq 'and removes nothing' "$before_tree" "$(tree)"
app_copy -- uninstall --purge --keep-all
check_eq 'the order does not matter' 2 "$RC"
app_copy -- uninstall --purge --purge
check_eq 'the same option twice is fine' 0 "$RC"
installed
app_copy -- install --purge
check_eq 'install takes no data option' 2 "$RC"
assert_contains 'and names it' "$OUT" 'Unrecognized option: --purge'
app_copy -- --purge
check_eq 'the data options need uninstall' 2 "$RC"
app_copy -- --keep-all
check_eq '--keep-all needs uninstall too' 2 "$RC"
app_copy -- uninstall --everything
check_eq 'an unknown option is refused' 2 "$RC"
check_eq 'and nothing was removed' yes "$(exists "$SB/home/$BIN_REL")"
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- uninstall --keep-records --purge
assert_contains 'the conflict in Spanish' "$OUT" 'Usa solo una de las opciones --keep-records, --keep-all y --purge.'

echo "-- uninstall: no data, nothing to ask"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
app_copy -- install
app_copy -- uninstall
assert_not_contains 'no settings line without settings' "$OUT" 'settings'
assert_not_contains 'no records line without records' "$OUT" 'records'
assert_not_contains 'no hint without data' "$OUT" '--purge'

echo "-- uninstall: the program was never installed, but it left data"
fresh
make_data
app_copy -- uninstall --purge
check_eq 'it removes the data' 0 "$(tree | wc -l)"
assert_not_contains 'it does not say there is nothing' "$OUT" 'nothing to remove'
fresh
make_data
app_copy -- uninstall
check_eq 'without an option it keeps the records' "$ONLY_RECORDS" "$(tree)"

echo "-- uninstall: asking on a terminal"
if command -v script >/dev/null 2>&1; then
    installed
    app_copy_pty $'\n' -- uninstall
    check_eq 'Enter alone: the default' "$ONLY_RECORDS" "$(tree)"
    assert_contains 'it shows the question' "$OUT" 'What should happen to your data?'
    assert_contains 'it shows the first choice, marked as the default' "$OUT" '1) Delete the settings and keep the records of what you removed (default)'
    assert_contains 'it shows the second choice' "$OUT" '2) Keep everything: settings and records.'
    assert_contains 'it shows the third choice' "$OUT" '3) Delete everything, leaving no trace.'
    assert_contains 'it shows the prompt with its default' "$OUT" 'Choose 1, 2 or 3 (q cancels) [1]:'
    check_eq 'it ends well' 0 "$RC"
    installed
    app_copy_pty $'2\n' -- uninstall
    check_eq '2: everything is kept' 'language=en' "$(cat "$SB/home/.config/mintapp-remover/config")"
    check_eq '2: and the records' yes "$(exists "$SB/home/$RECORDS/removal-20261031-100000-1-1.txt")"
    installed
    app_copy_pty $'3\n' -- uninstall
    check_eq '3: no trace' 0 "$(tree | wc -l)"
    installed
    app_copy_pty $'x\n9\n3\n' -- uninstall
    check_eq 'an answer that is not a choice is asked again (twice here), then 3 works' 0 "$(tree | wc -l)"
    check_eq 'the prompt came three times' 3 "$(grep -o 'Choose 1, 2 or 3' <<< "$OUT" | wc -l)"
    installed
    before_tree="$(tree)"
    app_copy_pty $'q\n3\n' -- uninstall
    check_eq 'q cancels: status 1 (the 3 typed after it is not read)' 1 "$RC"
    assert_contains 'it says nothing was removed' "$OUT" 'Cancelled: nothing was removed.'
    check_eq 'and nothing was removed' "$before_tree" "$(tree)"
    installed
    before_tree="$(tree)"
    app_copy_pty '' -- uninstall
    check_eq 'the end of the input cancels too' 1 "$RC"
    check_eq 'and nothing was removed' "$before_tree" "$(tree)"
    installed
    app_copy_pty $'3\n' MINTAPP_LANG=es MINTAPP_ASCII=0 -- uninstall
    assert_contains 'the question in Spanish' "$OUT" '¿Qué hacemos con tus datos?'
    assert_contains 'the prompt in Spanish' "$OUT" 'Elige 1, 2 o 3 (q cancela) [1]:'
    assert_contains 'the third choice in Spanish' "$OUT" '3) Borrarlo todo, sin dejar rastro.'
    installed
    app_copy_pty '' -- uninstall --purge
    check_eq 'with an option on a terminal it does not ask' 0 "$(tree | wc -l)"
    assert_not_contains 'no question' "$OUT" 'What should happen'
    fresh
    make_png "$SB/app/assets/$ICON_NAME" 256 256; sandbox_chown
    app_copy -- install
    app_copy_pty '' -- uninstall
    check_eq 'on a terminal, with no data there is nothing to ask' 0 "$RC"
    assert_not_contains 'no question without data' "$OUT" 'What should happen'
else
    skip_case 'asking on a terminal (util-linux script is not available)'
fi

echo "-- uninstall: a copy of the program is running"
if command -v flock >/dev/null 2>&1; then
    installed
    before_tree="$(tree)"
    mkdir -p "$SB/run"; : > "$SB/run/mintapp-remover.lock"; chmod 666 "$SB/run/mintapp-remover.lock"; sandbox_chown
    setsid flock -x "$SB/run/mintapp-remover.lock" sleep 60 &
    holder=$!
    sleep 1
    app_copy "XDG_RUNTIME_DIR=$SB/run" -- uninstall --purge
    check_eq 'with the lock held it refuses' 1 "$RC"
    assert_contains 'and says why' "$OUT" 'MintApp Remover is running (or a removal is in progress). Close it and try again.'
    check_eq 'and removes nothing' "$before_tree" "$(tree)"
    check_eq 'and leaves the lock file as it was' yes "$(exists "$SB/run/mintapp-remover.lock")"
    kill -- "-$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
    app_copy "XDG_RUNTIME_DIR=$SB/run" -- uninstall --purge
    check_eq 'once it is released it goes ahead' 0 "$RC"
    check_eq 'and removes the lock file, which is in a folder that is not ours' no "$(exists "$SB/run/mintapp-remover.lock")"
    check_eq 'the runtime folder itself stays' yes "$(exists "$SB/run")"
    installed
    setsid flock -x "$SB/home/$RECORDS/.lock" sleep 60 &
    holder=$!
    sleep 1
    before_tree="$(tree)"
    app_copy -- uninstall --purge
    check_eq 'the lock file in the records folder (no runtime folder) counts too' 1 "$RC"
    check_eq 'and nothing is removed' "$before_tree" "$(tree)"
    kill -- "-$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
    installed
    mkdir -p "$SB/run"; sandbox_chown
    app_copy "XDG_RUNTIME_DIR=$SB/run" -- uninstall --keep-all
    check_eq 'with no lock held it never makes the lock file' no "$(exists "$SB/run/mintapp-remover.lock")"
    check_eq 'and it goes ahead' 0 "$RC"
else
    skip_case 'a copy running (flock is not available)'
fi

fresh
mkdir -p "$SB/run"; sandbox_chown
app_copy "XDG_RUNTIME_DIR=$SB/run" -- uninstall
assert_contains 'nothing installed and no data: it says so' "$OUT" 'nothing to remove'
check_eq 'looking for a running copy makes no lock file' no "$(exists "$SB/run/mintapp-remover.lock")"
check_eq 'and no records folder either' no "$(exists "$SB/home/.local")"

echo "-- uninstall_rm_dir only removes folders of the program"
new_sandbox
mkdir -p "$SB/home/x/mintapp-remover/sub" "$SB/home/x/mintapp-remover2" "$SB/home/x/other"
printf 'a\n' > "$SB/home/x/mintapp-remover/sub/file"; sandbox_chown
rm_dir_status() { app_eval 'uninstall_rm_dir "$P"; echo $?' "P=$1"; printf '%s' "$OUT"; }
check_eq 'a folder called mintapp-remover goes, with what is in it' 0 "$(rm_dir_status "$SB/home/x/mintapp-remover")"
check_eq 'it is gone' no "$(exists "$SB/home/x/mintapp-remover")"
check_eq 'a folder with another name is refused' 1 "$(rm_dir_status "$SB/home/x/other")"
check_eq 'a name that only starts like it is refused' 1 "$(rm_dir_status "$SB/home/x/mintapp-remover2")"
check_eq 'a relative path is refused' 1 "$(rm_dir_status 'mintapp-remover')"
check_eq 'the parent is refused' 1 "$(rm_dir_status "$SB/home/x")"
check_eq 'an empty path is refused' 1 "$(rm_dir_status '')"
check_eq 'the root is refused' 1 "$(rm_dir_status '/')"
check_eq 'the refused folders are still there (other)' yes "$(exists "$SB/home/x/other")"
check_eq 'the refused folders are still there (mintapp-remover2)' yes "$(exists "$SB/home/x/mintapp-remover2")"

echo "-- install_prune_empty"
new_sandbox
mkdir -p "$SB/home/a/b/c" "$SB/home/k/d" "$SB/out/x/y" "$SB/base/m/n"
printf 'f\n' > "$SB/home/k/file"; sandbox_chown
prune() { app_eval 'install_prune_empty "$1" ${2:+"$2"}' "$@" >/dev/null 2>&1 || true; }
app_eval 'install_prune_empty "$HOME/a/b/c"; echo "$?"'
check_eq 'an empty chain under the home goes, up to the home' "0|no|yes" "$OUT|$(exists "$SB/home/a")|$(exists "$SB/home")"
app_eval 'install_prune_empty "$HOME/k/d"'
check_eq 'a folder with something else in it stops the walk' "no|yes|yes" "$(exists "$SB/home/k/d")|$(exists "$SB/home/k")|$(exists "$SB/home/k/file")"
app_eval 'install_prune_empty "$HOME"'
check_eq 'the home itself is never removed' yes "$(exists "$SB/home")"
app_eval 'install_prune_empty "$SB/out/x/y"' "SB=$SB"
check_eq 'outside the home and with no base, it leaves everything' yes "$(exists "$SB/out/x/y")"
app_eval 'install_prune_empty "$SB/out/x/y" "$SB/out/x"' "SB=$SB"
check_eq 'outside the home with a base, the base stays' "yes|yes|no" "$(exists "$SB/out")|$(exists "$SB/out/x")|$(exists "$SB/out/x/y")"
app_eval 'install_prune_empty "$SB/base/m/n" "$SB/base"' "SB=$SB"
check_eq 'outside the home with a base, what is below it goes' "yes|no" "$(exists "$SB/base")|$(exists "$SB/base/m")"
mkdir -p "$SB/out2/p/q"; sandbox_chown
app_eval 'install_prune_empty "$SB/out2/p/q" "$SB/base"' "SB=$SB"
check_eq 'a base that is not above the folder: it leaves everything' yes "$(exists "$SB/out2/p/q")"

echo "-- uninstall: folders outside the home"
fresh
make_png "$SB/app/assets/$ICON_NAME" 256 256
mkdir -p "$SB/xc" "$SB/xs" "$SB/xd"; sandbox_chown
XDG=("XDG_CONFIG_HOME=$SB/xc" "XDG_STATE_HOME=$SB/xs" "XDG_DATA_HOME=$SB/xd")
app_copy "${XDG[@]}" -- install
mkdir -p "$SB/xc/mintapp-remover" "$SB/xs/mintapp-remover"
printf 'language=en\n' > "$SB/xc/mintapp-remover/config"; printf 'r\n' > "$SB/xs/mintapp-remover/removal-1.txt"; sandbox_chown
app_copy "${XDG[@]}" -- uninstall --purge
check_eq 'it ends well' 0 "$RC"
check_eq 'what is in the bases is gone' 0 "$(find "$SB/xc" "$SB/xs" "$SB/xd" -mindepth 1 | wc -l)"
check_eq 'the config base stays' yes "$(exists "$SB/xc")"
check_eq 'the state base stays' yes "$(exists "$SB/xs")"
check_eq 'the data base stays' yes "$(exists "$SB/xd")"
check_eq 'the command in the home is gone and the home is empty' 0 "$(tree | wc -l)"

echo "-- uninstall: links to data folders"
installed
rm -rf -- "$SB/home/.config/mintapp-remover"
mkdir -p "$SB/home/elsewhere/cfg"; printf 'language=en\n' > "$SB/home/elsewhere/cfg/config"
ln -s "$SB/home/elsewhere/cfg" "$SB/home/.config/mintapp-remover"
sandbox_chown
app_copy -- uninstall --purge
check_eq 'a link to the settings is removed' no "$(exists "$SB/home/.config/mintapp-remover")"
check_eq 'what it pointed to stays' 'language=en' "$(cat "$SB/home/elsewhere/cfg/config")"

echo "-- uninstall: data that cannot be removed"
installed
mkdir -p "$SB/home/$RECORDS/locked"; printf 'x\n' > "$SB/home/$RECORDS/locked/file"; chmod 555 "$SB/home/$RECORDS/locked"; sandbox_chown
app_copy -- uninstall --purge
if [ "$(id -u)" -eq 0 ] || [ ! -w "$SB/home/$RECORDS/locked" ]; then
    check_eq 'a records folder that cannot be emptied: it fails' 1 "$RC"
    assert_contains 'and names it' "$OUT" "Could not remove $SB/home/$RECORDS."
    assert_not_contains 'it does not claim to be done' "$OUT" 'Done.'
    check_eq 'the settings were still removed' no "$(exists "$SB/home/.config")"
    check_eq 'and the command' no "$(exists "$SB/home/$BIN_REL")"
else
    skip_case 'data that cannot be removed (the sandbox user can write there)'
fi
chmod 755 "$SB/home/$RECORDS/locked" 2>/dev/null || true
installed
mkdir -p "$SB/home/.config/mintapp-remover/locked"; printf 'x\n' > "$SB/home/.config/mintapp-remover/locked/file"
chmod 555 "$SB/home/.config/mintapp-remover/locked"; sandbox_chown
app_copy -- uninstall --purge
if [ "$(id -u)" -eq 0 ] || [ ! -w "$SB/home/.config/mintapp-remover/locked" ]; then
    check_eq 'a settings folder that cannot be emptied: it fails' 1 "$RC"
    assert_contains 'and names it' "$OUT" "Could not remove $SB/home/.config/mintapp-remover."
    assert_not_contains 'it does not claim to be done' "$OUT" 'Done.'
    check_eq 'the records were still removed' no "$(exists "$SB/home/.local/state")"
else
    skip_case 'settings that cannot be removed (the sandbox user can write there)'
fi
chmod 755 "$SB/home/.config/mintapp-remover/locked" 2>/dev/null || true

echo "-- uninstall: data in Spanish"
installed
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- uninstall
assert_contains 'the labels' "$OUT" "ajustes    $SB/home/.config/mintapp-remover  (eliminado)"
assert_contains 'the records line' "$OUT" "registros  $SB/home/$RECORDS  (conservado)"
assert_contains 'the hint' "$OUT" 'ejecuta MintApp_Remover.sh uninstall --purge.'

# ------------------------------------------------------- the whole cycle (F5.4) ----
echo "-- cycle: install, use, uninstall, and the home is as it was"
# snapshot: every path of the home with its type and mode, and the checksum of every file.
snapshot() { (cd "$SB/home" && { find . -mindepth 1 -printf '%p\t%y\t%m\n'; find . -type f -exec sha256sum {} +; } | LC_ALL=C sort); }
# seed_home: what a person already has there, some of it where the program writes.
seed_home() {
    mkdir -p "$SB/home/.config/other-app" "$SB/home/.local/bin" "$SB/home/.local/share/applications" \
        "$SB/home/.local/share/icons/hicolor/48x48/apps" "$SB/home/.local/state/other-app" "$SB/home/Documents"
    printf 'export A=1\n' > "$SB/home/.bashrc"
    printf '[x]\n' > "$SB/home/.config/other-app/settings.ini"
    printf '#!/bin/sh\n' > "$SB/home/.local/bin/other-tool"; chmod 755 "$SB/home/.local/bin/other-tool"
    printf '[Desktop Entry]\nName=Other\n' > "$SB/home/.local/share/applications/other.desktop"
    printf 'png\n' > "$SB/home/.local/share/icons/hicolor/48x48/apps/other.png"
    printf 's\n' > "$SB/home/.local/state/other-app/log"
    printf 'notes\n' > "$SB/home/Documents/notes.txt"
    sandbox_chown
}
# use_installed: runs the installed command like a person would: switches the language (which is
# saved), and uninstalls an application (which writes a record), with the apt of the sandbox.
use_installed() {
    local real="$H_SCRIPT"
    H_SCRIPT="$SB/home/$BIN_REL"
    fake_installed firefox thunderbird
    app_run $'l\n\nl\n2\n\n1\nc\ny\n\n0\n'
    H_SCRIPT="$real"
}
cycle_start() {
    fresh
    make_png "$SB/app/assets/$ICON_NAME" 256 256
    if [ "${1:-}" = seed ]; then seed_home; fi
    sandbox_chown
}

cycle_start seed
snap0="$(snapshot)"
app_copy -- install
check_eq 'installed: the home has more than before' yes "$([ "$(snapshot)" != "$snap0" ] && echo yes || echo no)"
use_installed
check_eq 'the installed command ran and ended well' 0 "$RC"
check_eq 'using it saved the settings' yes "$(exists "$SB/home/.config/mintapp-remover/config")"
check_eq 'using it wrote a record' 1 "$(state_files | wc -l)"
check_eq 'apt was asked to remove firefox once' 1 "$(real_removals)"
app_copy -- uninstall --purge
check_eq 'uninstall --purge ends well' 0 "$RC"
check_eq 'the home is exactly as it was: same paths, types, modes and contents' "$snap0" "$(snapshot)"

cycle_start seed
snap0="$(snapshot)"
app_copy -- install
use_installed
app_copy -- uninstall
check_eq 'uninstall with no option ends well' 0 "$RC"
check_eq 'one record, and nothing else, stays in the records folder' 1 "$(find "$SB/home/.local/state/mintapp-remover" -mindepth 1 | wc -l)"
check_eq 'the settings are gone' no "$(exists "$SB/home/.config/mintapp-remover")"
check_eq 'the rest of the home is as it was' "$(grep -v 'mintapp-remover' <<< "$snap0")" "$(snapshot | grep -v 'mintapp-remover')"
app_copy -- uninstall --purge
check_eq 'a later uninstall --purge removes the records' 0 "$RC"
check_eq 'and the home is as it was' "$snap0" "$(snapshot)"

cycle_start
app_copy -- install
use_installed
app_copy -- uninstall --purge
check_eq 'an empty home goes back to empty' 0 "$(tree | wc -l)"

cycle_start seed
snap0="$(snapshot)"
for round in 1 2; do
    app_copy -- install
    use_installed
    app_copy -- uninstall --purge
    check_eq "two cycles in a row, round $round: the home is as it was" "$snap0" "$(snapshot)"
done

cycle_start seed
snap0="$(snapshot)"
app_copy -- install
app_copy -- install
use_installed
app_copy -- uninstall --purge
app_copy -- uninstall --purge
check_eq 'installing twice and uninstalling twice leaves the home as it was' "$snap0" "$(snapshot)"

cycle_start seed
snap0="$(snapshot)"
app_copy -- install
use_installed
real_script="$H_SCRIPT"; H_SCRIPT="$SB/home/$BIN_REL"
app_run '' -- uninstall --purge
H_SCRIPT="$real_script"
check_eq 'the installed command can uninstall itself' 0 "$RC"
check_eq 'and the home is as it was' "$snap0" "$(snapshot)"

cycle_start seed
snap0="$(snapshot)"
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- install
use_installed
app_copy MINTAPP_LANG=es MINTAPP_ASCII=0 -- uninstall --purge
check_eq 'the same cycle in Spanish leaves the home as it was' "$snap0" "$(snapshot)"

cycle_start seed
mkdir -p "$SB/xc" "$SB/xs" "$SB/xd"; sandbox_chown
XDG=("XDG_CONFIG_HOME=$SB/xc" "XDG_STATE_HOME=$SB/xs" "XDG_DATA_HOME=$SB/xd")
snap0="$(snapshot)"
app_copy "${XDG[@]}" -- install
real_script="$H_SCRIPT"; H_SCRIPT="$SB/home/$BIN_REL"
fake_installed firefox thunderbird
app_run $'l\n\nl\n2\n\n1\nc\ny\n\n0\n' "${XDG[@]}"
H_SCRIPT="$real_script"
check_eq 'with the XDG folders outside the home it ran' 0 "$RC"
check_eq 'it wrote its settings there' yes "$(exists "$SB/xc/mintapp-remover/config")"
check_eq 'and its record' 1 "$(find "$SB/xs/mintapp-remover" -name 'removal-*.txt' | wc -l)"
app_copy "${XDG[@]}" -- uninstall --purge
check_eq 'the home is as it was' "$snap0" "$(snapshot)"
check_eq 'the XDG folders are empty again' 0 "$(find "$SB/xc" "$SB/xs" "$SB/xd" -mindepth 1 | wc -l)"

finish
