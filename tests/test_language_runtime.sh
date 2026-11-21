#!/usr/bin/env bash
# Language and system (os-release, desktop) detection at run time (the script is sourced, no menus).
# SC2016 is off for the whole file: the code given to app_eval (directly or through sys_is) is
# single-quoted on purpose, because the program expands it, not this script. Hostile values such
# as '$(x)' are quoted so that they reach the program unexpanded.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
# This suite checks the Unicode symbols: its sandboxes run with MINTAPP_ASCII=0 (see harness.sh).
export H_UNICODE=1
new_sandbox
SCRIPT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../script" && pwd)/MintApp_Remover.sh"

# os-release samples, reduced to the lines that matter. Ubuntu 24.04 is a real
# capture; the others follow each distribution's documented format.
OSR="$SB/osr"
mkdir -p "$OSR"
cat > "$OSR/linuxmint-22.3" <<'EOF'
PRETTY_NAME="Linux Mint 22.3"
NAME="Linux Mint"
VERSION_ID="22.3"
VERSION="22.3 (Zena)"
VERSION_CODENAME=zena
ID=linuxmint
ID_LIKE="ubuntu debian"
HOME_URL="https://www.linuxmint.com/"
VERSION_CODENAME=zena
UBUNTU_CODENAME=noble
EOF
cat > "$OSR/ubuntu-24.04" <<'EOF'
PRETTY_NAME="Ubuntu 24.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.4 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
UBUNTU_CODENAME=noble
EOF
cat > "$OSR/debian-12" <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
VERSION="12 (bookworm)"
VERSION_CODENAME=bookworm
ID=debian
HOME_URL="https://www.debian.org/"
EOF
cat > "$OSR/pop-22.04" <<'EOF'
NAME="Pop!_OS"
VERSION="22.04 LTS"
ID=pop
ID_LIKE="ubuntu debian"
PRETTY_NAME="Pop!_OS 22.04 LTS"
VERSION_ID="22.04"
VERSION_CODENAME=jammy
UBUNTU_CODENAME=jammy
EOF
cat > "$OSR/fedora-40" <<'EOF'
NAME="Fedora Linux"
VERSION="40 (Workstation Edition)"
ID=fedora
VERSION_ID=40
VERSION_CODENAME=""
PLATFORM_ID="platform:f40"
PRETTY_NAME="Fedora Linux 40 (Workstation Edition)"
VARIANT_ID=workstation
EOF
cat > "$OSR/rocky-9" <<'EOF'
NAME="Rocky Linux"
VERSION="9.4 (Blue Onyx)"
ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="9.4"
PLATFORM_ID="platform:el9"
PRETTY_NAME="Rocky Linux 9.4 (Blue Onyx)"
EOF
cat > "$OSR/arch" <<'EOF'
NAME="Arch Linux"
PRETTY_NAME="Arch Linux"
ID=arch
BUILD_ID=rolling
LOGO=archlinux-logo
EOF
cat > "$OSR/manjaro" <<'EOF'
NAME="Manjaro Linux"
PRETTY_NAME="Manjaro Linux"
ID=manjaro
ID_LIKE=arch
BUILD_ID=rolling
EOF
cat > "$OSR/opensuse-tumbleweed" <<'EOF'
NAME="openSUSE Tumbleweed"
# VERSION="20240801"
ID="opensuse-tumbleweed"
ID_LIKE="opensuse suse"
VERSION_ID="20240801"
PRETTY_NAME="openSUSE Tumbleweed"
EOF
cat > "$OSR/alpine-3.20" <<'EOF'
NAME="Alpine Linux"
ID=alpine
VERSION_ID=3.20.2
PRETTY_NAME="Alpine Linux v3.20"
EOF
sandbox_chown

# lang_is LABEL EXPECTED [ENV=VAL ...]: the language picked with that environment.
lang_is() {
    local label="$1" expected="$2" value
    shift 2
    # Markers: bash may warn on stderr about locales that are not installed.
    app_eval 'printf "<<%s>>" "$APP_LANG"' "$@"
    value="${OUT#*<<}"
    check_eq "$label" "$expected" "${value%%>>*}"
}

echo "-- detection order (gettext: LANGUAGE > LC_ALL > LC_MESSAGES > LANG; C/POSIX -> English)"
lang_is 'no locale at all -> English' en
lang_is 'LANG=es_ES.UTF-8 -> Spanish' es LANG=es_ES.UTF-8
lang_is 'LANG=es_MX.UTF-8 -> Spanish' es LANG=es_MX.UTF-8
lang_is 'LANG=es (bare) -> Spanish' es LANG=es
lang_is 'LANG=es_ES@euro -> Spanish' es LANG=es_ES@euro
lang_is 'LANG=en_US.UTF-8 -> English' en LANG=en_US.UTF-8
lang_is 'LANG=fr_FR.UTF-8 -> English' en LANG=fr_FR.UTF-8
lang_is 'LANG=pt_BR.UTF-8 -> English' en LANG=pt_BR.UTF-8
lang_is 'LANG=de_DE.UTF-8 -> English' en LANG=de_DE.UTF-8
lang_is 'LANG=ca_ES.UTF-8 (Catalan) -> English' en LANG=ca_ES.UTF-8
lang_is 'LANG=C -> English' en LANG=C
lang_is 'LANG=C.UTF-8 -> English' en LANG=C.UTF-8
lang_is 'LANG=POSIX -> English' en LANG=POSIX
lang_is 'LC_ALL beats LANG' es LC_ALL=es_ES.UTF-8 LANG=en_US.UTF-8
lang_is 'LC_ALL=en beats LANG=es' en LC_ALL=en_US.UTF-8 LANG=es_ES.UTF-8
lang_is 'LC_MESSAGES beats LANG' en LC_MESSAGES=en_US.UTF-8 LANG=es_ES.UTF-8
lang_is 'LC_ALL beats LC_MESSAGES' es LC_ALL=es_ES.UTF-8 LC_MESSAGES=en_US.UTF-8
lang_is 'LANGUAGE=en beats LANG=es' en LANG=es_ES.UTF-8 LANGUAGE=en
lang_is 'LANGUAGE=es:en beats LANG=en' es LANG=en_US.UTF-8 LANGUAGE=es:en
lang_is 'LANGUAGE=en:es -> English (first match wins)' en LANG=es_ES.UTF-8 LANGUAGE=en:es
lang_is 'LANGUAGE=de:es -> Spanish (first supported)' es LANG=de_DE.UTF-8 LANGUAGE=de:es
lang_is 'LANGUAGE=fr:de -> English (nothing supported, like gettext)' en LANG=es_ES.UTF-8 LANGUAGE=fr:de
lang_is 'LANGUAGE=C:es -> English (C stops the list)' en LANG=es_ES.UTF-8 LANGUAGE=C:es
lang_is 'LANGUAGE ignored when locale is C' en LANG=C LANGUAGE=es
lang_is 'LANGUAGE ignored when no locale is set' en LANGUAGE=es
lang_is 'empty LANGUAGE falls back to LANG' es LANG=es_ES.UTF-8 LANGUAGE=
lang_is 'LANG=gl_ES.UTF-8 (Galician) -> English' en LANG=gl_ES.UTF-8
lang_is 'LANG=es_ES.utf8 (lowercase codeset) -> Spanish' es LANG=es_ES.utf8
lang_is 'LANG= (empty) -> English' en LANG=
lang_is 'empty LC_ALL falls through to LANG' es LC_ALL= LANG=es_ES.UTF-8
lang_is 'empty LC_ALL and LC_MESSAGES fall through to LANG' es LC_ALL= LC_MESSAGES= LANG=es_ES.UTF-8
lang_is 'LC_ALL=C beats a Spanish LANG' en LC_ALL=C LANG=es_ES.UTF-8
lang_is 'LC_ALL=POSIX beats a Spanish LANG' en LC_ALL=POSIX LANG=es_ES.UTF-8
lang_is 'LC_MESSAGES=C beats a Spanish LANG' en LC_MESSAGES=C LANG=es_ES.UTF-8
lang_is 'LANGUAGE=es_ES.UTF-8 (with codeset) -> Spanish' es LANG=en_US.UTF-8 LANGUAGE=es_ES.UTF-8
lang_is 'LANGUAGE=es@euro -> Spanish' es LANG=en_US.UTF-8 LANGUAGE=es@euro
lang_is 'LANGUAGE=en_GB:es -> English (first match wins)' en LANG=es_ES.UTF-8 LANGUAGE=en_GB:es
lang_is 'LANGUAGE=:es (empty first entry is skipped) -> Spanish' es LANG=en_US.UTF-8 LANGUAGE=:es
lang_is 'LANGUAGE=es: (trailing colon) -> Spanish' es LANG=en_US.UTF-8 LANGUAGE=es:
lang_is 'LANGUAGE=es ignored when LC_ALL=C' en LC_ALL=C LANGUAGE=es

echo "-- MINTAPP_LANG override"
lang_is 'MINTAPP_LANG=es beats an English locale' es MINTAPP_LANG=es LANG=en_US.UTF-8
lang_is 'MINTAPP_LANG=en beats a Spanish locale' en MINTAPP_LANG=en LANG=es_ES.UTF-8
lang_is 'invalid MINTAPP_LANG is ignored (Spanish locale)' es MINTAPP_LANG=fr LANG=es_ES.UTF-8
lang_is 'invalid MINTAPP_LANG is ignored (English locale)' en MINTAPP_LANG=xx LANG=en_US.UTF-8
lang_is 'empty MINTAPP_LANG is ignored' es MINTAPP_LANG= LANG=es_ES.UTF-8
lang_is 'MINTAPP_LANG=es beats LANGUAGE=en' es MINTAPP_LANG=es LANGUAGE=en LANG=en_US.UTF-8
lang_is 'MINTAPP_LANG=en beats LANGUAGE=es' en MINTAPP_LANG=en LANGUAGE=es LANG=es_ES.UTF-8
lang_is 'MINTAPP_LANG=es applies even with the C locale' es MINTAPP_LANG=es LANG=C
lang_is 'MINTAPP_LANG=ES (uppercase) -> Spanish' es MINTAPP_LANG=ES LANG=en_US.UTF-8
lang_is 'MINTAPP_LANG=En (mixed case) -> English' en MINTAPP_LANG=En LANG=es_ES.UTF-8
lang_is 'MINTAPP_LANG=es_MX.UTF-8 (locale style) -> Spanish' es MINTAPP_LANG=es_MX.UTF-8 LANG=en_US.UTF-8
lang_is 'MINTAPP_LANG=en-US (BCP 47 style) -> English' en MINTAPP_LANG=en-US LANG=es_ES.UTF-8
lang_is 'MINTAPP_LANG=espanol is ignored (only the language code counts)' en MINTAPP_LANG=espanol LANG=en_US.UTF-8
lang_is 'MINTAPP_LANG=english is ignored (only the language code counts)' es MINTAPP_LANG=english LANG=es_ES.UTF-8

echo "-- detection reaches the screens (whole program, no sourcing)"
app_run $'\n0\n' LANG=es_ES.UTF-8
assert_contains 'LANG=es_ES: the menu is in Spanish' "$OUT" 'Desinstalar aplicaciones'
app_run $'\n0\n' LANG=es_ES.UTF-8 LANGUAGE=en
assert_contains 'LANGUAGE=en over a Spanish LANG: the menu is in English' "$OUT" 'Uninstall applications'
app_run $'\n0\n' LANG=es_ES.UTF-8 MINTAPP_LANG=en
assert_contains 'MINTAPP_LANG=en over a Spanish LANG: the menu is in English' "$OUT" 'Uninstall applications'
app_run $'\n0\n' LC_ALL=C LANG=es_ES.UTF-8
assert_contains 'LC_ALL=C over a Spanish LANG: the menu is in English' "$OUT" 'Uninstall applications'

echo "-- switching language"
app_eval 'toggle_language; printf %s "$APP_LANG"' LANG=en_US.UTF-8
check_eq 'toggle English -> Spanish' es "$OUT"
app_eval 'toggle_language; toggle_language; printf %s "$APP_LANG"' LANG=en_US.UTF-8
check_eq 'toggle twice returns to English' en "$OUT"
app_eval 'toggle_language; printf %s "$(msg menu_exit)"' LANG=en_US.UTF-8
check_eq 'messages follow the switch' Salir "$OUT"
app_eval 'printf %s "$(msg menu_language)"' MINTAPP_LANG=es
check_eq 'the language button names English while the interface is Spanish' English "$OUT"
app_eval 'printf %s "$(msg menu_language)"' MINTAPP_LANG=en
check_eq 'the language button names Spanish in Spanish while the interface is English' Español "$OUT"
app_eval 'toggle_language; printf %s "$(msg menu_language)"' MINTAPP_LANG=en
check_eq 'the button follows the switch (English interface -> Spanish -> offers English)' English "$OUT"
app_eval 'toggle_language; printf %s "$WT_TITLE"' LANG=en_US.UTF-8 MINTAPP_OS_RELEASE="$OSR/linuxmint-22.3"
check_eq 'window title is refreshed on switch and does not name the system' 'MintApp Remover' "$OUT"

echo "-- the help screen and the language are remembered (5.2, whole program)"
# The harness deletes the configuration before every run; here it must last from one run to the next.
H_KEEP_CONFIG=1
CFGF="$SB/home/.config/mintapp-remover/config"
rm -rf "$SB/home/.config"
app_run $'\n0\n' LANG=en_US.UTF-8
assert_contains 'first start: the help screen is shown' "$OUT" 'Text mode is active'
assert_contains 'and then the menu' "$OUT" 'Uninstall applications'
check_eq 'answering the help screen records help_seen' 'help_seen=yes' "$(grep -v '^#' "$CFGF")"
check_eq 'the configuration file is private (600)' 600 "$(stat -c %a "$CFGF")"
app_run $'0\n' LANG=en_US.UTF-8
assert_not_contains 'second start: the help screen is not shown again' "$OUT" 'Text mode is active'
assert_contains 'the menu comes straight away' "$OUT" 'Uninstall applications'
check_eq 'the second start ends well' 0 "$RC"
app_run $'\n0\n' LANG=en_US.UTF-8 -- --show-help
assert_contains '--show-help shows it again' "$OUT" 'Text mode is active'
app_run $'\n0\n' LANG=en_US.UTF-8 -- --show-help --terminal
assert_contains '--show-help works with the other options' "$OUT" 'Text mode is active'
app_run '' LANG=en_US.UTF-8 -- --help
assert_contains '--help lists --show-help' "$OUT" '--show-help'
rm -rf "$SB/home/.config"
app_run '' LANG=en_US.UTF-8
assert_contains 'no answer at all (end of input): the help screen was shown' "$OUT" 'Text mode is active'
check_eq 'but it is not recorded as seen' no "$([ -e "$CFGF" ] && echo yes || echo no)"
rm -rf "$SB/home/.config"
app_run $'l\n\n0\n' LANG=en_US.UTF-8
assert_contains 'L on the help screen switches it to Spanish' "$OUT" 'Modo texto activo'
check_eq 'the switch and the help are both recorded' $'language=es\nhelp_seen=yes' "$(grep -v '^#' "$CFGF" | sort -r)"
app_run $'0\n' LANG=en_US.UTF-8
assert_contains 'next start: the saved language beats the English locale' "$OUT" 'Desinstalar aplicaciones'
app_run $'0\n' LANG=en_US.UTF-8 MINTAPP_LANG=en
assert_contains 'MINTAPP_LANG still beats the saved language' "$OUT" 'Uninstall applications'
check_eq 'and does not change what was saved' 'language=es' "$(grep '^language' "$CFGF")"
app_run $'0\n' LANG=en_US.UTF-8 MINTAPP_LANG=fr
assert_contains 'a MINTAPP_LANG that names no language lets the saved one apply' "$OUT" 'Desinstalar aplicaciones'
printf 'language=en\nhelp_seen=yes\n' > "$CFGF"
app_run $'0\n' LANG=es_ES.UTF-8
assert_contains 'a hand-written language=en beats a Spanish locale' "$OUT" 'Uninstall applications'
printf 'language=klingon\nhelp_seen=maybe\n' > "$CFGF"
app_run $'\n0\n' LANG=es_ES.UTF-8
assert_contains 'invalid values change nothing: the locale decides' "$OUT" 'Desinstalar aplicaciones'
assert_contains 'and the help is shown, since help_seen is not valid' "$OUT" 'Modo texto activo'
# The dialog screens (own engine, whiptail, windows) end the help screen in one place, so whiptail,
# whose stub needs no terminal (MINTAPP_UI=whiptail), stands for them. Esc counts: the screen was shown.
rm -rf "$SB/home/.config"
fake_answers OK ESC
app_run '' LANG=en_US.UTF-8 MINTAPP_UI=whiptail
check_eq 'whiptail: answering the help screen records help_seen' 'help_seen=yes' "$(grep -v '^#' "$CFGF")"
check_eq 'whiptail: the configuration file is private (600)' 600 "$(stat -c %a "$CFGF")"
rm -rf "$SB/home/.config"
fake_answers ESC ESC
app_run '' LANG=en_US.UTF-8 MINTAPP_UI=whiptail
check_eq 'whiptail: Esc on the help screen records it too' 'help_seen=yes' "$(grep -v '^#' "$CFGF")"
rm -rf "$SB/home/.config"
fake_answers NO OK ESC
app_run '' LANG=en_US.UTF-8 MINTAPP_UI=whiptail
check_eq 'whiptail: the language button on the help screen records the language and the help' \
    $'language=es\nhelp_seen=yes' "$(grep -v '^#' "$CFGF" | sort -r)"
: > "$SB/state/whiptail.log"
fake_answers ESC
app_run '' LANG=en_US.UTF-8 MINTAPP_UI=whiptail
check_eq 'whiptail: once recorded, the help screen does not come back (only the menu is drawn)' 1 \
    "$(grep -c '^whiptail ' "$SB/state/whiptail.log")"
# Without a usable HOME, preflight_checks asks the account database for one. The configuration kept
# there is read from that moment on, or the saved language and the seen help would be ignored.
rm -rf "$SB/home/.config"
mkdir -p "$SB/acct/.config/mintapp-remover"
printf 'language=es\nhelp_seen=yes\n' > "$SB/acct/.config/mintapp-remover/config"
printf '#!/bin/sh\necho "tester:x:%s:%s::%s:/bin/sh"\n' "$H_APP_UID" "$H_APP_GID" "$SB/acct" > "$SB/bin/getent"
chmod 755 "$SB/bin/getent"; sandbox_chown
app_run $'0\n' LANG=en_US.UTF-8 HOME="$SB/nohome"
assert_contains 'HOME is not a folder: the language saved in the account home applies' "$OUT" 'Desinstalar aplicaciones'
check_eq 'and so does the seen help: the help screen is not shown (in either language)' 0 \
    "$(grep -cE 'Text mode is active|Modo texto activo' <<< "$OUT" || true)"
check_eq 'and the run ends well' 0 "$RC"
rm -rf "$SB/acct" "$SB/bin/getent"
rm -rf "$SB/home/.config"
H_KEEP_CONFIG=0
app_run $'\n0\n' LANG=en_US.UTF-8
app_run $'\n0\n' LANG=en_US.UTF-8
assert_contains 'by default the harness starts every run without configuration (the help is shown again)' "$OUT" 'Text mode is active'

echo "-- catalog names follow the language"
app_eval 'printf "%s|" "$(catalog_name calculator)" "$(catalog_desc calculator)"; toggle_language; printf "%s|" "$(catalog_name calculator)" "$(catalog_desc disks)"' LANG=en_US.UTF-8
check_eq 'catalog_name and catalog_desc in both languages' 'Calculator|Calculator|Calculadora|Gestión de discos y particiones|' "$OUT"
app_eval 'DETECTED_KEYS=(calculator); DETECTED_NAMES=(x); DETECTED_DESC=(y); DETECTION_DONE=1; toggle_language; printf "%s|%s" "${DETECTED_NAMES[0]}" "${DETECTED_DESC[0]}"' LANG=en_US.UTF-8
check_eq 'already detected apps are re-translated on switch' 'Calculadora|Calculadora' "$OUT"

echo "-- launcher names (Name[xx] keys)"
make_desktop gimp.desktop 'GIMP' 'Name[es]=GIMP Editor de imágenes' 'Name[es_MX]=GIMP MX'
app_eval "desktop_name '$SB/apps/gimp.desktop'" MINTAPP_LANG=es LANG=es_ES.UTF-8
check_eq 'Spanish interface uses Name[es]' 'GIMP Editor de imágenes' "$OUT"
app_eval "desktop_name '$SB/apps/gimp.desktop'" MINTAPP_LANG=es LANG=es_MX.UTF-8
check_eq 'Name[es_MX] wins for an es_MX locale' 'GIMP MX' "$OUT"
app_eval "desktop_name '$SB/apps/gimp.desktop'" MINTAPP_LANG=en LANG=es_ES.UTF-8
check_eq 'English interface ignores Name[es]' 'GIMP' "$OUT"

# sys_is LABEL EXPECTED EXPR [ENV=VAL ...]: value of a shell expression after start-up detection.
sys_is() {
    local label="$1" expected="$2" expr="$3" value
    shift 3
    app_eval "printf '<<%s>>' \"$expr\"" "$@"
    value="${OUT#*<<}"
    check_eq "$label" "$expected" "${value%%>>*}"
}

echo "-- system detection (F4.1): os-release is read as data, never sourced"
SYS='${SYS_ID}|${SYS_FAMILY}|${SYS_LABEL}|${SYS_PRETTY}'
sys_is 'Linux Mint 22.3 -> debian family, short label'        'linuxmint|debian|Linux Mint 22.3|Linux Mint 22.3' "$SYS" MINTAPP_OS_RELEASE="$OSR/linuxmint-22.3"
sys_is 'Ubuntu 24.04 (real capture) -> debian family'          'ubuntu|debian|Ubuntu 24.04.4 LTS|Ubuntu 24.04.4 LTS' "$SYS" MINTAPP_OS_RELEASE="$OSR/ubuntu-24.04"
sys_is 'Debian 12: the codename is dropped from the label'     'debian|debian|Debian GNU/Linux 12|Debian GNU/Linux 12 (bookworm)' "$SYS" MINTAPP_OS_RELEASE="$OSR/debian-12"
sys_is 'Pop!_OS (ID_LIKE ubuntu debian) -> debian family'      'pop|debian|Pop!_OS 22.04 LTS|Pop!_OS 22.04 LTS' "$SYS" MINTAPP_OS_RELEASE="$OSR/pop-22.04"
sys_is 'Fedora 40 -> fedora family'                            'fedora|fedora|Fedora Linux 40|Fedora Linux 40 (Workstation Edition)' "$SYS" MINTAPP_OS_RELEASE="$OSR/fedora-40"
sys_is 'Rocky 9 (ID_LIKE rhel centos fedora) -> fedora'        'rocky|fedora|Rocky Linux 9.4|Rocky Linux 9.4 (Blue Onyx)' "$SYS" MINTAPP_OS_RELEASE="$OSR/rocky-9"
sys_is 'Arch -> arch family (no VERSION_ID: rolling)'          'arch|arch|Arch Linux|Arch Linux' "$SYS" MINTAPP_OS_RELEASE="$OSR/arch"
sys_is 'Manjaro (ID_LIKE arch) -> arch family'                 'manjaro|arch|Manjaro Linux|Manjaro Linux' "$SYS" MINTAPP_OS_RELEASE="$OSR/manjaro"
sys_is 'openSUSE Tumbleweed (comment line, quoted ID) -> suse' 'opensuse-tumbleweed|suse|openSUSE Tumbleweed|openSUSE Tumbleweed' "$SYS" MINTAPP_OS_RELEASE="$OSR/opensuse-tumbleweed"
sys_is 'Alpine (no apt/dpkg) -> unknown family'                'alpine|unknown|Alpine Linux v3.20|Alpine Linux v3.20' "$SYS" MINTAPP_OS_RELEASE="$OSR/alpine-3.20"
sys_is 'ID_LIKE is kept as written'                            'ubuntu debian' '${SYS_ID_LIKE}' MINTAPP_OS_RELEASE="$OSR/linuxmint-22.3"
sys_is 'a repeated key (VERSION_CODENAME in Mint) is harmless' 'linuxmint' '${SYS_ID}' MINTAPP_OS_RELEASE="$OSR/linuxmint-22.3"

echo "-- system detection: odd and hostile files"
sys_is 'a missing file -> nothing detected, no crash, no fallback' '||||unknown' '${SYS_ID}|${SYS_LABEL}|${SYS_PRETTY}|${SYS_ID_LIKE}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/no-such-file"
: > "$SB/osr-empty"
sys_is 'an empty file -> nothing detected'                     '||unknown' '${SYS_ID}|${SYS_LABEL}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-empty"
sys_is 'a directory instead of a file -> nothing detected'     '||unknown' '${SYS_ID}|${SYS_LABEL}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB"
printf 'ID=arch' > "$SB/osr-nonl"
sys_is 'a last line without a newline is read'                 'arch|arch' '${SYS_ID}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-nonl"
printf 'ID=linuxmint\r\nID_LIKE="ubuntu debian"\r\nPRETTY_NAME="Linux Mint 22.3"\r\n' > "$SB/osr-crlf"
sys_is 'CRLF line endings are tolerated'                       'linuxmint|debian|Linux Mint 22.3' '${SYS_ID}|${SYS_FAMILY}|${SYS_LABEL}' MINTAPP_OS_RELEASE="$SB/osr-crlf"
printf 'ID=ubuntu\nID=fedora\n' > "$SB/osr-twice"
sys_is 'the last assignment wins (like a shell would)'         'fedora|fedora' '${SYS_ID}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-twice"
printf "ID='debian'\nPRETTY_NAME='Debian single'\n" > "$SB/osr-single"
sys_is 'single quotes are removed'                             'debian|Debian single' '${SYS_ID}|${SYS_LABEL}' MINTAPP_OS_RELEASE="$SB/osr-single"
printf 'ID=debian\nPRETTY_NAME="My \\"Quoted\\" OS"\n' > "$SB/osr-esc"
sys_is 'an escaped quote inside double quotes is unescaped'    'My "Quoted" OS' '${SYS_PRETTY}' MINTAPP_OS_RELEASE="$SB/osr-esc"
printf '  # comment\n\n   ID=arch\nNAMEX=ignored\nbad line\n' > "$SB/osr-junk"
sys_is 'comments, blank, indented and unknown lines'           'arch|arch' '${SYS_ID}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-junk"
printf 'NAME="Foo OS"\nVERSION_ID="1.2"\nID=foo\n' > "$SB/osr-nopretty"
sys_is 'no PRETTY_NAME: NAME and VERSION_ID are used'          'Foo OS 1.2' '${SYS_PRETTY}' MINTAPP_OS_RELEASE="$SB/osr-nopretty"
printf 'ID=foo\n' > "$SB/osr-idonly"
sys_is 'only ID: the ID is the name'                           'foo|foo|unknown' '${SYS_PRETTY}|${SYS_LABEL}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-idonly"
printf 'ID=foo\nID_LIKE="arch debian"\n' > "$SB/osr-mixed"
sys_is 'two known families: the first word wins'               'arch' '${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-mixed"
printf 'ID=ubuntu\nID_LIKE=fedora\n' > "$SB/osr-mixed2"
sys_is 'the ID outranks ID_LIKE'                               'debian' '${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-mixed2"
printf 'ID="Ubuntu; rm -rf"\nID_LIKE="Bad;token debian"\n' > "$SB/osr-badid"
sys_is 'an invalid ID is dropped, invalid ID_LIKE tokens skipped' '|debian|debian' '${SYS_ID}|${SYS_ID_LIKE}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-badid"
printf 'ID=*\nID_LIKE="* debian"\n' > "$SB/osr-glob"
sys_is 'glob characters in ID and ID_LIKE are not expanded'    '|debian|debian' '${SYS_ID}|${SYS_ID_LIKE}|${SYS_FAMILY}' MINTAPP_OS_RELEASE="$SB/osr-glob"
printf 'ID=debian\nPRETTY_NAME="Evil\033[31mRed\033[0m\tTab"\n' > "$SB/osr-esc2"
sys_is 'ESC is removed and a tab becomes a space'              'Evil[31mRed[0m Tab' '${SYS_PRETTY}' MINTAPP_OS_RELEASE="$SB/osr-esc2"
printf 'ID=debian\nPRETTY_NAME="back\\slash"\n' > "$SB/osr-bslash"
sys_is 'backslashes cannot reach echo -e / printf %b'          'back/slash' '${SYS_PRETTY}' MINTAPP_OS_RELEASE="$SB/osr-bslash"
printf 'ID=debian\nPRETTY_NAME="%s"\n' "$(printf 'A%.0s' $(seq 1 120))" > "$SB/osr-long"
sys_is 'a very long name is capped (pretty 64, label 22)'      '64|22' '${#SYS_PRETTY}|${#SYS_LABEL}' MINTAPP_OS_RELEASE="$SB/osr-long"
cat > "$SB/osr-evil" <<EVIL
ID=debian
NAME="\$(touch $SB/home/pwned-name)"
PRETTY_NAME="\`touch $SB/home/pwned-pretty\`"
VERSION_ID=\$(touch $SB/home/pwned-version)
ID_LIKE="ubuntu; touch $SB/home/pwned-like"
EVIL
app_eval 'printf "<<%s>>" "$SYS_LABEL"' MINTAPP_OS_RELEASE="$SB/osr-evil"
check_eq 'command substitutions in os-release are never executed' 0 "$(find "$SB/home" -name 'pwned-*' | wc -l)"
check_eq 'the script never sources os-release' 0 "$(grep -cE '^[[:space:]]*(source|\.)[[:space:]].*os-release' "$SCRIPT_FILE" || true)"
app_eval 'printf "%s" "$SYS_ID"; MINTAPP_OS_RELEASE=/no/such/file detect_system; printf "|%s|%s" "$SYS_ID" "$SYS_FAMILY"' MINTAPP_OS_RELEASE="$OSR/ubuntu-24.04"
check_eq 're-detecting with a missing file clears the previous system' 'ubuntu||unknown' "$OUT"
REAL_FILE=/etc/os-release; [ -r "$REAL_FILE" ] || REAL_FILE=/usr/lib/os-release
REAL_ID="$(sed -n 's/^ID=//p' "$REAL_FILE" 2>/dev/null | head -n1 | tr -d "\"'" | tr '[:upper:]' '[:lower:]')"
if [ -n "$REAL_ID" ]; then
    sys_is 'without the override the real os-release is used' "$REAL_ID" '${SYS_ID}'
else
    skip_case 'without the override the real os-release is used (this machine has none)'
fi

echo "-- desktop environment (XDG_CURRENT_DESKTOP)"
desk_is() { sys_is "$1" "$2" '${SYS_DESKTOP}' MINTAPP_OS_RELEASE="$OSR/arch" XDG_CURRENT_DESKTOP="$3"; }
desk_is 'X-Cinnamon (Linux Mint) -> cinnamon'                  cinnamon 'X-Cinnamon'
desk_is 'Cinnamon, any case -> cinnamon'                       cinnamon 'cinnamon'
desk_is 'GNOME -> gnome'                                       gnome 'GNOME'
desk_is 'ubuntu:GNOME -> gnome (vendor prefix skipped)'        gnome 'ubuntu:GNOME'
desk_is 'pop:GNOME -> gnome'                                   gnome 'pop:GNOME'
desk_is 'GNOME-Classic:GNOME -> gnome'                         gnome 'GNOME-Classic:GNOME'
desk_is 'KDE -> kde'                                           kde 'KDE'
desk_is 'XFCE -> xfce'                                         xfce 'XFCE'
desk_is 'MATE -> mate'                                         mate 'MATE'
desk_is 'two known desktops: the first one wins'              gnome 'GNOME:KDE'
desk_is 'two known desktops, vendor first: still the first known' kde 'ubuntu:KDE:GNOME'
desk_is 'LXQt (no catalog yet) -> other'                       other 'LXQt'
desk_is 'Unity:Unity7:ubuntu -> other'                         other 'Unity:Unity7:ubuntu'
desk_is 'an empty value -> other'                              other ''
desk_is 'garbage with glob characters -> other'                other '*:[a-z]?:$(x)'
sys_is 'an unset XDG_CURRENT_DESKTOP -> other (no crash)'      other '${SYS_DESKTOP}' MINTAPP_OS_RELEASE="$OSR/arch"

echo "-- window and header title (FP.1): the program name only, never the system"
# The interface speaks of "Linux" in general: the detected system (SYS_*) is kept for the catalogs but
# no title, header or message names it.
for title_os in "$OSR"/* "$SB/no-such-file"; do
    app_eval 'printf "%s|%s" "$(app_title)" "$WT_TITLE"' MINTAPP_OS_RELEASE="$title_os"
    check_eq "the title is just the program name (${title_os##*/})" 'MintApp Remover|MintApp Remover' "$OUT"
done
app_eval 'toggle_language; printf "%s" "$WT_TITLE"' MINTAPP_OS_RELEASE="$OSR/rocky-9" LANG=en_US.UTF-8
check_eq 'the title survives a language switch unchanged' 'MintApp Remover' "$OUT"
app_eval 'MINTAPP_OS_RELEASE="$ALT" detect_system; printf "%s" "$WT_TITLE"' MINTAPP_OS_RELEASE="$OSR/ubuntu-24.04" ALT="$OSR/arch"
check_eq 'a new detection leaves the title alone' 'MintApp Remover' "$OUT"
app_eval 'printf "%s|%s" "$SYS_ID" "$SYS_LABEL"' MINTAPP_OS_RELEASE="$OSR/linuxmint-22.3"
check_eq 'the system is still detected, only not shown' 'linuxmint|Linux Mint 22.3' "$OUT"

# No text of the program may say "Mint" apart from its own name (MintApp, MINTAPP_* variables). Covers the messages, the
# catalog names and the catalog descriptions, in both languages, and --help.
app_eval 'bad=""
for table in MSG_EN MSG_ES APP_NAME_EN APP_NAME_ES APP_DESC_EN APP_DESC_ES; do
    declare -n tbl="$table"
    for k in "${!tbl[@]}"; do
        v="${tbl[$k]}"; v="${v//[Mm][Ii][Nn][Tt][Aa][Pp][Pp]/}"; v="${v//mintbackup/}"; v="${v//mintstick/}"
        case "${v,,}" in *mint*) bad="$bad $table:$k" ;; esac
    done
    unset -n tbl
done
printf "<<%s>>" "$bad"'
check_eq 'no message, catalog name or description says "Mint" (only the program name does)' '<<>>' "$OUT"
for help_lang in en es; do
    app_run '' MINTAPP_LANG=$help_lang -- --help
    assert_not_contains "--help does not say Linux Mint ($help_lang)" "$OUT" 'Linux Mint'
done

echo "-- the detected system reaches no screen but its status line (whole program)"
# The status line of the main menu (F7.0) names the system on purpose; it is the line that ends in the
# count of applications ("... detected" / "... detectadas"). Nothing else on the screen may name it.
plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }
status_line() { plain | grep -a -E '(detected|detectadas?)$' || true; }
app_run $'\n0\n' MINTAPP_OS_RELEASE="$OSR/ubuntu-24.04"
assert_contains 'the main menu header is the program name' "$OUT" 'MintApp Remover'
assert_contains 'on Ubuntu the status line names the system' "$(status_line)" 'Ubuntu 24.04.4 LTS'
check_eq 'on Ubuntu the status line is the only line that names Ubuntu' "$(status_line)" "$(plain | grep -a 'Ubuntu' || true)"
app_run $'\n0\n' MINTAPP_OS_RELEASE="$OSR/linuxmint-22.3" LANG=es_ES.UTF-8
assert_contains 'on Mint the status line names the system (Spanish too)' "$(status_line)" 'Linux Mint 22.3'
check_eq 'on Mint the status line is the only line that says Linux Mint (Spanish too)' "$(status_line)" "$(plain | grep -a 'Linux Mint' || true)"
app_run $'\n0\n' MINTAPP_OS_RELEASE="$OSR/alpine-3.20"
check_eq 'an unsupported distro still starts: detection never blocks' 0 "$RC"
finish
