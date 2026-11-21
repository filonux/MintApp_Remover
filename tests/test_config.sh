#!/usr/bin/env bash
# Configuration file (FU.4): where it lives, how it is read (as data, validated),
# how it is written (atomic, private) and the cleanup of stale temporaries.
# Fast: the program is only sourced, nothing needs a terminal.
# SC2016 is off for the whole file: the code given to app_eval is single-quoted on purpose, because
# the program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

H_KEEP_CONFIG=1    # the harness would delete the configuration before every run
new_sandbox
CFG="$SB/home/.config/mintapp-remover"
STATE="$SB/home/.local/state/mintapp-remover"
PWNED="$SB/home/pwned"

# reset: no configuration, no state, nothing left from the previous case.
reset() { rm -rf -- "$SB/home/.config" "$SB/home/.local" "$SB/home/rel" "$SB/xdg" "$PWNED"; }

# put_config CONTENT: the configuration file, written with printf %b.
put_config() {
    mkdir -p "$CFG"
    printf '%b' "$1" > "$CFG/config"
    sandbox_chown
}

# get_with CONTENT [VAR=val ...]: the file holds CONTENT; prints "value|status" of
# config_get interface.
get_with() {
    local content="$1"; shift
    reset; put_config "$content"
    app_eval 'v="$(config_get interface)"; echo "$v|$?"' "$@"
    printf '%s' "$OUT"
}

# g LABEL EXPECTED CONTENT: config_get interface on a file with that CONTENT.
g() { check_eq "read: $1" "$2" "$(get_with "$3")"; }

# h LABEL EXPECTED CONTENT: the same, and the content must not have run anything.
h() {
    check_eq "hostile ($1): value" "$2" "$(get_with "$3")"
    check_eq "hostile ($1): nothing ran" no "$(exists "$PWNED")"
}

mode() { stat -c %a -- "$1"; }
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }
# body FILE: the lines of the file that are not comments or blank.
body() { grep -v '^#\|^$' "$1" || true; }
# tmp_count: temporary files of a write, anywhere in the home.
tmp_count() { find "$SB/home" -name '.tmp.*' | wc -l; }

echo "-- config_dir"
reset
app_eval 'config_dir'
check_eq 'default: ~/.config/mintapp-remover' "$CFG" "$OUT"
app_eval 'config_dir' "XDG_CONFIG_HOME=$SB/xdg"
check_eq 'an absolute XDG_CONFIG_HOME is used' "$SB/xdg/mintapp-remover" "$OUT"
app_eval 'config_dir' "XDG_CONFIG_HOME=$SB/xdg/"
check_eq 'a trailing slash in XDG_CONFIG_HOME does not double' "$SB/xdg/mintapp-remover" "$OUT"
# A literal tilde is the point here: the shell does not expand it in an environment variable.
# shellcheck disable=SC2088
for rel in rel/dir . .. '~/x' xdg ' /x'; do
    app_eval 'config_dir' "XDG_CONFIG_HOME=$rel"
    check_eq "a relative XDG_CONFIG_HOME ($rel) is ignored" "$CFG" "$OUT"
done
app_eval 'config_dir' XDG_CONFIG_HOME=
check_eq 'an empty XDG_CONFIG_HOME is ignored' "$CFG" "$OUT"
app_eval 'config_dir' "HOME=$SB/home/"
check_eq 'a trailing slash in HOME does not double' "$CFG" "$OUT"
app_eval 'config_dir' HOME=/
check_eq 'HOME=/ gives /.config/mintapp-remover' "/.config/mintapp-remover" "$OUT"
for bad in '' rel/home; do
    app_eval 'config_dir; echo "|$?"' "HOME=$bad"
    check_eq "without a usable HOME ('$bad') and no XDG it fails with no output" "|1" "$OUT"
done
app_eval 'unset HOME; config_dir; echo "|$?"'
check_eq 'with HOME unset and no XDG it fails with no output' "|1" "$OUT"
app_eval 'config_dir; echo "|$?"' HOME= "XDG_CONFIG_HOME=$SB/xdg"
check_eq 'an absolute XDG_CONFIG_HOME works even without HOME' "$SB/xdg/mintapp-remover|0" "$OUT"

echo "-- config_valid"
# valid EXPECTED KEY VALUE: the status of config_valid.
valid() {
    app_eval 'config_valid "$K" "$V"; echo $?' "K=$2" "V=$3"
    check_eq "config_valid '$2' '$3' -> $1" "$1" "$OUT"
}
valid 0 interface terminal
valid 0 interface gui
for v in Gui GUI Terminal '' ' gui' 'gui ' auto text whiptail 'gui;x' gu terminal2 $'terminal\n'; do
    valid 1 interface "$v"
done
for k in lang Language Interface INTERFACE 'interface ' ' interface' ''; do valid 1 "$k" gui; done
valid 0 language es
valid 0 language en
for v in ES En fr '' ' es' 'es ' es_ES en-US gui $'es\n'; do valid 1 language "$v"; done
valid 0 help_seen yes
valid 0 help_seen no
for v in Yes YES y n 1 0 true false '' ' yes' 'yes ' $'yes\n'; do valid 1 help_seen "$v"; done
for k in help-seen helpseen Help_seen help_seen_; do valid 1 "$k" yes; done
valid 1 interface yes
valid 1 language yes
valid 1 help_seen gui

echo "-- config_get and config_load: where there is nothing"
reset
app_eval 'v="$(config_get interface)"; echo "$v|$?"'
check_eq 'no file: config_get prints nothing and fails' '|1' "$OUT"
app_eval 'config_load; echo $?'
check_eq 'no file: config_load fails' 1 "$OUT"
app_eval 'config_load; echo "${#CONFIG[@]}"'
check_eq 'no file: CONFIG is empty' 0 "$OUT"
put_config 'interface=gui\n'
app_eval 'v="$(config_get speed)"; echo "$v|$?"'
check_eq 'an unknown key fails even with a file' '|1' "$OUT"
app_eval 'v="$(config_get language)"; echo "$v|$?"'
check_eq 'a known key the file does not set fails too' '|1' "$OUT"
app_eval 'config_load; echo $?; config_get interface'
check_eq 'config_load succeeds and config_get prints the bare value' $'0\ngui' "$OUT"
app_eval 'config_get interface; rm -f "$HOME/.config/mintapp-remover/config"; config_load; echo " $?"; v="$(config_get interface)"; echo "$v|$?"'
check_eq 'config_load drops what was loaded before' $'gui 1\n|1' "$OUT"

echo "-- config file read as data"
g 'terminal' 'terminal|0' 'interface=terminal\n'
g 'gui' 'gui|0' 'interface=gui\n'
g 'no final newline' 'gui|0' 'interface=gui'
g 'spaces around key and value' 'gui|0' '  interface = gui  \n'
g 'tabs around the value' 'terminal|0' 'interface=\tterminal\t\n'
g 'capitals in the value' 'gui|0' 'interface=GUI\n'
g 'CRLF line ends' 'gui|0' 'interface=gui\r\n'
g 'comments and blank lines around' 'terminal|0' '# note\n\n  # more\ninterface=terminal\n\n'
g 'a commented key is not read' '|1' '# interface=gui\n'
g 'a key with # in front is not read' '|1' '#interface=gui\n'
g 'the last valid line wins' 'terminal|0' 'interface=gui\ninterface=terminal\n'
g 'an invalid later line does not erase a valid one' 'gui|0' 'interface=gui\ninterface=bogus\n'
g 'an unknown key is ignored, the known one is kept' 'gui|0' 'language=es\ninterface=gui\nfoo=bar\n'
g 'a line without = is ignored' 'gui|0' 'interface\ninterface=gui\n'
g 'a value that is not allowed' '|1' 'interface=auto\n'
g 'an empty value' '|1' 'interface=\n'
g 'a quoted value is not accepted' '|1' 'interface="gui"\n'
g 'a value with trailing words' '|1' 'interface=gui extra\n'
g 'a value with a second =' '|1' 'interface=gui=1\n'
g 'an empty file' '|1' ''
g 'the key in capitals is another key' '|1' 'INTERFACE=gui\n'
g 'a key with a space inside is another key' '|1' 'inter face=gui\n'
g 'NUL bytes are dropped without warnings' 'gui|0' 'interface=gui\n\0\0\n'
g 'a line over 256 characters is ignored' 'terminal|0' "interface=terminal\ninterface=gui$(printf '%300s' '')\n"
g 'a line of 256 characters is read' 'gui|0' "interface=gui$(printf '%243s' '')\n"
pad="$(head -c 5000 /dev/zero | tr '\0' '#')"
g 'a valid line after the first 4096 bytes is not read' '|1' "$pad\ninterface=gui\n"
g 'a valid line before the first 4096 bytes is read, whatever follows' 'gui|0' "interface=gui\n$pad\n"

echo "-- config file: nothing in it is executed"
h 'command substitution in the value' '|1' "interface=\$(touch $PWNED)"
h 'backticks in the value' '|1' "interface=\`touch $PWNED\`"
h 'a command after the value' '|1' "interface=gui;touch $PWNED"
h 'a command on the next line' 'gui|0' "interface=gui\ntouch $PWNED"
h 'command substitution in the key' '|1' "\$(touch $PWNED)=gui"
h 'backticks in the key' '|1' "\`touch $PWNED\`=gui"
h 'a subscript in the key' '|1' "interface[\$(touch $PWNED)]=gui"
h 'an arithmetic subscript in the key' '|1' "a[\$(touch $PWNED)]=gui"

echo "-- config file: unusual kinds of file"
reset; mkdir -p "$CFG/config"; sandbox_chown
app_eval 'v="$(config_get interface)"; echo "$v|$?"'
check_eq 'a directory in place of the file: no value' '|1' "$OUT"
reset; mkdir -p "$CFG"; mkfifo "$CFG/config"; sandbox_chown
app_eval 'v="$(config_get interface)"; echo "$v|$?"'
check_eq 'a FIFO in place of the file: no value, and no waiting' '|1' "$OUT"
reset; mkdir -p "$CFG"; head -c 3000 /dev/urandom > "$CFG/config"; sandbox_chown
app_eval 'v="$(config_get interface)"; echo "$v|$?"'
check_eq 'random bytes: no value and no errors' '|1' "$OUT"
reset; put_config 'interface=gui\n'; mv "$CFG/config" "$SB/real-config"; ln -s "$SB/real-config" "$CFG/config"
chmod 644 "$SB/real-config"; sandbox_chown
app_eval 'v="$(config_get interface)"; echo "$v|$?"'
check_eq 'a symbolic link to a regular file is followed' 'gui|0' "$OUT"
reset; put_config 'interface=gui\n'; chmod 000 "$CFG/config"
app_eval 'v="$(config_get interface)"; echo "$v|$?"'
check_eq 'an unreadable file: no value, no error text' '|1' "$OUT"
chmod 600 "$CFG/config"

echo "-- config_set: creating the file"
reset
app_eval 'config_set interface gui; echo $?'
check_eq 'set on a fresh home succeeds' 0 "$OUT"
check_eq 'the directory is private (700)' 700 "$(mode "$CFG")"
check_eq 'the file is private (600)' 600 "$(mode "$CFG/config")"
check_eq 'the .config folder was created private too (700)' 700 "$(mode "$SB/home/.config")"
check_eq 'the file is two comment lines and the setting' $'#\n#\ninterface=gui' "$(sed -E 's/^(#).*/\1/' "$CFG/config")"
check_eq 'the file ends with a newline' '' "$(tail -c1 "$CFG/config" | tr -d '\n')"
check_eq 'no temporary file is left' 0 "$(tmp_count)"
app_eval 'v="$(config_get interface)"; echo "$v|$?"'
check_eq 'another run reads what was saved' 'gui|0' "$OUT"
app_eval 'config_set interface terminal; v="$(config_get interface)"; echo "$v|$?"'
check_eq 'set then get in the same run gives the new value' 'terminal|0' "$OUT"
check_eq 'saving again replaces the line (still one)' 'interface=terminal' "$(body "$CFG/config")"
app_eval 'config_load; v="$(config_get interface)"; echo "$v|$?"'
check_eq 'and a reload agrees with the disk' 'terminal|0' "$OUT"

echo "-- config_set: refused values"
reset; put_config 'interface=gui\n'; before="$(cat "$CFG/config")"
for pair in 'interface|auto' 'interface|GUI' 'interface|' 'language|fr' 'language|ES' 'help_seen|1' 'help_seen|true' 'x|gui' '|gui'; do
    app_eval 'config_set "$K" "$V"; echo $?' "K=${pair%%|*}" "V=${pair#*|}"
    check_eq "config_set '${pair%%|*}' '${pair#*|}': status 2" 2 "$OUT"
done
check_eq 'refused values leave the file as it was' "$before" "$(cat "$CFG/config")"
reset
app_eval 'config_set interface auto; echo $?'
check_eq 'a refused value on a fresh home: status 2' 2 "$OUT"
check_eq 'a refused value creates nothing' no "$(exists "$SB/home/.config")"

echo "-- config_set: what is kept and what is replaced"
reset; put_config '# my notes\nlanguage=es\ninterface=gui\nfoo=bar\n'
app_eval 'config_set interface terminal; echo $?'
check_eq 'set over a hand-edited file succeeds' 0 "$OUT"
check_eq 'the file is rewritten with only the known valid keys' $'interface=terminal\nlanguage=es' "$(body "$CFG/config")"
check_eq 'hand-written comments are replaced by the header' 0 "$(grep -c 'my notes' "$CFG/config" || true)"
# With a second key (the next phase adds some), saving one must not lose the other.
EXTRA_KEY='CONFIG_KEYS=(interface extra); config_valid() { case "$1=$2" in interface=gui|extra=x) return 0 ;; esac; return 1; }'
reset; put_config 'extra=x\n'
app_eval "$EXTRA_KEY"'; config_set interface gui; echo $?; config_get extra; echo; config_get interface'
check_eq 'another valid key already on disk is kept' $'0\nx\ngui' "$OUT"
check_eq 'both keys are in the file, in key order' $'interface=gui\nextra=x' "$(body "$CFG/config")"
reset; put_config 'interface=terminal\n'
app_eval "$EXTRA_KEY"'; config_load; printf "extra=x\n" > "$HOME/.config/mintapp-remover/config"; config_set interface gui; echo $?'
check_eq 'set reads the disk again: a key saved after the load is not lost' $'interface=gui\nextra=x' "$(body "$CFG/config")"
reset; put_config 'interface=gui\n'; chmod 644 "$CFG/config"; chmod 755 "$CFG"
app_eval 'config_set interface terminal; echo $?'
check_eq 'an existing 644 file is replaced by a 600 one' 600 "$(mode "$CFG/config")"
check_eq 'an existing 755 directory becomes 700' 700 "$(mode "$CFG")"

echo "-- config_set: location"
reset
app_eval 'config_set interface gui; echo $?' "XDG_CONFIG_HOME=$SB/xdg"
check_eq 'an absolute XDG_CONFIG_HOME receives the file' 'interface=gui' "$(body "$SB/xdg/mintapp-remover/config")"
check_eq 'and ~/.config is not touched' no "$(exists "$SB/home/.config")"
reset
app_eval 'cd "$HOME"; config_set interface gui; echo $?' XDG_CONFIG_HOME=rel/dir
check_eq 'a relative XDG_CONFIG_HOME writes to ~/.config' 'interface=gui' "$(body "$CFG/config")"
check_eq 'and nothing is created at the relative path' no "$(exists "$SB/home/rel")"
reset
app_eval 'config_set interface gui; echo $?' HOME=rel/home
check_eq 'with no usable home and no XDG, set fails (status 1)' 1 "$OUT"
check_eq 'and writes nothing in the sandbox' 0 "$(find "$SB/home" -mindepth 1 | wc -l)"
reset
app_eval 'config_set interface gui; echo $?' XDG_CONFIG_HOME=/proc
check_eq 'a place where nothing can be created: status 1' 1 "$OUT"

echo "-- config_set: failures leave things as they were"
reset; put_config 'interface=gui\n'
app_eval 'atomic_write() { cat > /dev/null; return 1; }; config_set interface terminal; echo $?; config_get interface'
check_eq 'a failed write: status 1, and the value in memory goes back to the disk one' $'1\ngui' "$OUT"
check_eq 'a failed write leaves the file as it was' 'interface=gui' "$(body "$CFG/config")"
reset; mkdir -p "$CFG/config"; sandbox_chown
app_eval 'config_set interface gui; echo $?'
check_eq 'a directory in place of the file: status 1' 1 "$OUT"
check_eq 'the directory is intact and nothing was moved inside it' 0 "$(find "$CFG/config" -mindepth 1 | wc -l)"
check_eq 'no temporary file is left' 0 "$(tmp_count)"
reset; mkdir -p "$SB/home"; : > "$SB/home/.config"; sandbox_chown
app_eval 'config_set interface gui; echo $?'
check_eq 'a regular file where the directory should be: status 1' 1 "$OUT"
reset

echo "-- stale temporaries (state and configuration folders)"
mkdir -p "$CFG/sub" "$STATE" "$SB/home/.tmp-elsewhere"
: > "$CFG/.tmp.old"; : > "$CFG/.tmp.new"; : > "$CFG/config"; : > "$CFG/other.txt"; : > "$CFG/sub/.tmp.nested"
: > "$STATE/.tmp.old"; : > "$STATE/.tmp.new"; : > "$STATE/removal-old.txt"
: > "$SB/home/.tmp.outside"; : > "$SB/home/.tmp-elsewhere/.tmp.deep"
sandbox_chown
for f in "$CFG/.tmp.old" "$CFG/config" "$CFG/other.txt" "$CFG/sub/.tmp.nested" "$STATE/.tmp.old" \
    "$STATE/removal-old.txt" "$SB/home/.tmp.outside" "$SB/home/.tmp-elsewhere/.tmp.deep"; do fake_age "$f" 3; done
app_eval 'sweep_stale_temp_files; echo $?'
check_eq 'the sweep succeeds' 0 "$OUT"
for f in "$CFG/.tmp.old" "$STATE/.tmp.old"; do
    check_eq "an old temporary is removed: ${f#"$SB/home/"}" no "$(exists "$f")"
done
for f in "$CFG/.tmp.new" "$STATE/.tmp.new" "$CFG/config" "$CFG/other.txt" "$STATE/removal-old.txt" \
    "$CFG/sub/.tmp.nested" "$SB/home/.tmp.outside" "$SB/home/.tmp-elsewhere/.tmp.deep"; do
    check_eq "kept (recent, not a temporary, nested or outside both folders): ${f#"$SB/home/"}" yes "$(exists "$f")"
done
reset; rm -rf "$SB/home/.tmp-elsewhere" "$SB/home/.tmp.outside"
app_eval 'sweep_stale_temp_files; echo $?'
check_eq 'the sweep with neither folder present succeeds' 0 "$OUT"
check_eq 'and creates neither' 0 "$(find "$SB/home" -mindepth 1 | wc -l)"
mkdir -p "$SB/xdg/mintapp-remover"; : > "$SB/xdg/mintapp-remover/.tmp.old"; sandbox_chown
fake_age "$SB/xdg/mintapp-remover/.tmp.old" 3
app_eval 'sweep_stale_temp_files; echo $?' "XDG_CONFIG_HOME=$SB/xdg"
check_eq 'the sweep follows XDG_CONFIG_HOME' no "$(exists "$SB/xdg/mintapp-remover/.tmp.old")"

echo "-- state_dir: a relative XDG_STATE_HOME is ignored (same rule)"
reset
app_eval 'state_dir'
check_eq 'default: ~/.local/state/mintapp-remover' "$STATE" "$OUT"
app_eval 'state_dir' "XDG_STATE_HOME=$SB/xdg"
check_eq 'an absolute XDG_STATE_HOME is used' "$SB/xdg/mintapp-remover" "$OUT"
app_eval 'state_dir' "XDG_STATE_HOME=$SB/xdg/"
check_eq 'a trailing slash does not double' "$SB/xdg/mintapp-remover" "$OUT"
# shellcheck disable=SC2088
for rel in rel/dir . '~/x'; do
    app_eval 'state_dir' "XDG_STATE_HOME=$rel"
    check_eq "a relative XDG_STATE_HOME ($rel) is ignored" "$STATE" "$OUT"
done
app_eval 'state_dir' XDG_STATE_HOME=
check_eq 'an empty XDG_STATE_HOME is ignored' "$STATE" "$OUT"
app_eval 'cd "$HOME"; ensure_state_dir; echo $?' XDG_STATE_HOME=rel/dir
check_eq 'with a relative XDG_STATE_HOME the state folder goes to the default place' "yes:no" "$(exists "$STATE"):$(exists "$SB/home/rel")"

echo "-- the program does not create the file by itself"
reset
app_run '' -- --version
check_eq '--version works' "0:MintApp Remover $H_VERSION" "$RC:$OUT"
app_run '' -- --help
check_eq '--help works' 0 "$RC"
check_eq '--version and --help create no configuration' no "$(exists "$SB/home/.config")"

echo "-- language and help_seen (5.2): saving and reading"
reset
app_eval 'config_set language es; echo $?; config_set help_seen yes; echo $?; config_set interface gui; echo $?'
check_eq 'the three keys can be saved one after the other' $'0\n0\n0' "$OUT"
check_eq 'the three are in the file, in key order' $'interface=gui\nlanguage=es\nhelp_seen=yes' "$(body "$CFG/config")"
check_eq 'the file is still private (600)' 600 "$(mode "$CFG/config")"
app_eval 'printf "%s|%s|%s" "$(config_get interface)" "$(config_get language)" "$(config_get help_seen)"'
check_eq 'another run reads the three' 'gui|es|yes' "$OUT"
app_eval 'config_set language en; config_get language; echo; config_get help_seen; echo; config_get interface'
check_eq 'changing one key keeps the others' $'en\nyes\ngui' "$OUT"
put_config 'language=ES\nhelp_seen=YES\n'
app_eval 'printf "%s|%s" "$(config_get language)" "$(config_get help_seen)"'
check_eq 'capitals in a hand-written value are tolerated' 'es|yes' "$OUT"
put_config 'language=fr\nhelp_seen=maybe\n'
app_eval 'printf "%s|%s" "$(config_get language)" "$(config_get help_seen)"; echo "|$?"'
check_eq 'a value that is not allowed is ignored' '||0' "$OUT"

echo "-- forced_language (MINTAPP_LANG)"
forced() { app_eval 'v="$(forced_language)"; echo "$v|$?"' "$@"; }
forced MINTAPP_LANG=es;           check_eq 'es' 'es|0' "$OUT"
forced MINTAPP_LANG=EN;           check_eq 'EN (capitals)' 'en|0' "$OUT"
forced MINTAPP_LANG=es_MX.UTF-8;  check_eq 'es_MX.UTF-8 (locale style)' 'es|0' "$OUT"
forced MINTAPP_LANG=en-US;        check_eq 'en-US' 'en|0' "$OUT"
forced MINTAPP_LANG=fr;           check_eq 'another language: nothing, failure' '|1' "$OUT"
forced MINTAPP_LANG=;             check_eq 'empty: nothing, failure' '|1' "$OUT"
forced;                           check_eq 'unset: nothing, failure' '|1' "$OUT"

echo "-- apply_saved_language: MINTAPP_LANG, then the file, then the locale"
saved_lang() { reset; [ -z "$1" ] || put_config "$1"; shift; app_eval 'apply_saved_language; printf "%s|%s" "$APP_LANG" "$(msg menu_exit)"' "$@"; }
saved_lang 'language=es\n' LANG=en_US.UTF-8
check_eq 'the saved language beats the locale (English locale, saved es)' 'es|Salir' "$OUT"
saved_lang 'language=en\n' LANG=es_ES.UTF-8
check_eq 'the saved language beats the locale (Spanish locale, saved en)' 'en|Exit' "$OUT"
saved_lang 'language=es\n' LANG=en_US.UTF-8 MINTAPP_LANG=en
check_eq 'MINTAPP_LANG beats the saved language' 'en|Exit' "$OUT"
saved_lang 'language=en\n' LANG=en_US.UTF-8 MINTAPP_LANG=es
check_eq 'MINTAPP_LANG beats the saved language (the other way)' 'es|Salir' "$OUT"
saved_lang 'language=es\n' LANG=en_US.UTF-8 MINTAPP_LANG=fr
check_eq 'a MINTAPP_LANG that names no language does not count: the saved one applies' 'es|Salir' "$OUT"
saved_lang '' LANG=es_ES.UTF-8
check_eq 'no file: the locale decides (Spanish)' 'es|Salir' "$OUT"
saved_lang '' LANG=en_US.UTF-8
check_eq 'no file: the locale decides (English)' 'en|Exit' "$OUT"
saved_lang 'language=fr\n' LANG=es_ES.UTF-8
check_eq 'an invalid saved language is ignored: the locale decides' 'es|Salir' "$OUT"
saved_lang 'interface=gui\n' LANG=es_ES.UTF-8
check_eq 'a file without the key leaves the locale in charge' 'es|Salir' "$OUT"
saved_lang 'language=en\n' LANG=es_ES.UTF-8 LANGUAGE=es
check_eq 'the saved language beats LANGUAGE too' 'en|Exit' "$OUT"
reset; put_config 'language=en\n'
app_eval 'apply_saved_language; printf %s "$WT_TITLE"' LANG=es_ES.UTF-8
check_eq 'the window title is refreshed (set_language runs)' 'MintApp Remover' "$OUT"
saved_lang 'language=es\n' HOME=rel/home LANG=en_US.UTF-8
check_eq 'without a usable HOME it does nothing and does not fail' 'en|Exit' "$OUT"

echo "-- toggle_language saves the choice"
reset
app_eval 'toggle_language; echo "$APP_LANG"' LANG=en_US.UTF-8
check_eq 'English -> Spanish' es "$OUT"
check_eq 'the choice is in the file' 'language=es' "$(body "$CFG/config")"
check_eq 'the file is private (600)' 600 "$(mode "$CFG/config")"
app_eval 'toggle_language; toggle_language; echo "$APP_LANG"' LANG=en_US.UTF-8
check_eq 'twice: back to English' en "$OUT"
check_eq 'and the last choice is the one saved' 'language=en' "$(body "$CFG/config")"
reset; put_config 'interface=gui\nhelp_seen=yes\n'
app_eval 'toggle_language' LANG=en_US.UTF-8
check_eq 'saving the language keeps the other keys' $'interface=gui\nlanguage=es\nhelp_seen=yes' "$(body "$CFG/config")"
reset
app_eval 'atomic_write() { cat > /dev/null; return 1; }; toggle_language; echo "$APP_LANG|$?"' LANG=en_US.UTF-8
check_eq 'if it cannot be saved the switch still works and nothing is printed' 'es|0' "$OUT"
reset
app_eval 'toggle_language; echo "$APP_LANG|$?"' LANG=en_US.UTF-8 HOME=rel/home
check_eq 'without a usable HOME it works too' 'es|0' "$OUT"

echo "-- help_already_seen and mark_help_seen"
reset
app_eval 'help_already_seen; echo $?'
check_eq 'no file: not seen' 1 "$OUT"
app_eval 'mark_help_seen; echo $?; help_already_seen; echo $?'
check_eq 'mark_help_seen succeeds, prints nothing else, and the help is then seen' $'0\n0' "$OUT"
check_eq 'help_seen=yes is in the file' 'help_seen=yes' "$(body "$CFG/config")"
app_eval 'help_already_seen; echo $?'
check_eq 'another run still sees it as seen' 0 "$OUT"
put_config 'help_seen=no\n'
app_eval 'help_already_seen; echo $?'
check_eq 'help_seen=no: not seen' 1 "$OUT"
put_config 'help_seen=1\n'
app_eval 'help_already_seen; echo $?'
check_eq 'an invalid value counts as not seen' 1 "$OUT"
reset
app_eval 'atomic_write() { cat > /dev/null; return 1; }; mark_help_seen; echo $?'
check_eq 'a failed write is not an error and prints nothing' 0 "$OUT"
app_eval 'mark_help_seen; echo $?' HOME=rel/home
check_eq 'without a usable HOME it is not an error either' 0 "$OUT"

echo "-- the code (read, not run)"
section="$(sed -n '/^# Configuration: /,/^# Option 1: Detect applications/p' "$H_SCRIPT")"
check_eq 'the configuration section was found' yes "$([ "${#section}" -gt 1000 ] && echo yes || echo no)"
code="$(grep -v '^[[:space:]]*#' <<< "$section")"
assert_not_contains 'the file is never sourced' "$code" 'source '
assert_not_contains 'the file is never sourced with a dot' "$code" '. "$'
assert_not_contains 'nothing is evaluated' "$code" 'eval '
assert_contains 'the file is written atomically, with mode 600' "$code" 'atomic_write "$dir/config" 600'
assert_contains 'in a private directory' "$code" 'chmod 700'
assert_not_contains 'no [[ -v on an array element (it needs bash 4.3 or newer)' "$code" '[[ -v'
assert_not_contains 'no ${var@Q} (bash 4.4)' "$code" '@Q'
assert_contains 'the keys are interface, language and help_seen' "$code" 'CONFIG_KEYS=(interface language help_seen)'

finish
