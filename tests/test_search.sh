#!/usr/bin/env bash
# Search, detail and origin of applications (FP.3).
# SC2016 is off for the whole file: the code given to app_eval is single-quoted on purpose,
# because the program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
# This suite checks the Unicode symbols: its sandboxes run with MINTAPP_ASCII=0 (see harness.sh).
export H_UNICODE=1

# fold TEXT [VAR=val ...]: the text folded by the program.
fold() {
    local text="$1"; shift
    app_eval "fold_search '$text'; printf '%s' \"\$REPLY\"" "$@"
    printf '%s' "$OUT"
}
# matches HAYSTACK QUERY [VAR=val ...]: "yes" or "no".
matches() {
    local hay="$1" query="$2"; shift 2
    app_eval "fold_search '$hay'; h=\"\$REPLY\"; search_prepare '$query'; if search_match \"\$h\"; then printf yes; else printf no; fi" "$@"
    printf '%s' "$OUT"
}

new_sandbox

echo "-- fold_search: case and accents (FP.3a)"
for loc in C C.UTF-8; do
    check_eq "capitals and accents are folded (locale $loc)" 'escaner de documentos' "$(fold 'ESCÁNER de Documentos' LC_ALL=$loc)"
    check_eq "ñ and ü become n and u (locale $loc)" 'ano pinguino' "$(fold 'Año Pingüino' LC_ALL=$loc)"
    check_eq "capital accents are folded even without UTF-8 case rules (locale $loc)" 'nandu arbol' "$(fold 'ÑANDÚ ÁRBOL' LC_ALL=$loc)"
    check_eq "ß, æ and œ expand (locale $loc)" 'strasse aether oeuvre' "$(fold 'Straße Æther Œuvre' LC_ALL=$loc)"
    check_eq "a text without accents is only lowercased (locale $loc)" 'gnome-calculator 2.0_x' "$(fold 'GNOME-Calculator 2.0_X' LC_ALL=$loc)"
done
check_eq 'an empty text stays empty' '' "$(fold '')"

echo "-- clean_query"
cq() {
    app_eval "clean_query \$'$1'; printf '<%s>' \"\$REPLY\""
    printf '%s' "$OUT"
}
check_eq 'blanks are trimmed and collapsed' '<a b c>' "$(cq '   a   b\tc  ')"
check_eq 'control characters become spaces (an escape sequence cannot pass)' '<a [31mb>' "$(cq 'a\x1b[31mb')"
check_eq 'backslashes are dropped (they would break a dialog text)' '<a n b>' "$(cq 'a\\\\n b')"
check_eq 'only blanks give an empty text' '<>' "$(cq ' \t  ')"
long="$(printf 'x%.0s' $(seq 1 100))"
check_eq 'a long text is cut at 64 characters' "<$(printf 'x%.0s' $(seq 1 64))>" "$(cq "$long")"
check_eq 'the cut never leaves a trailing space' '<aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>' "$(cq "$(printf 'a%.0s' $(seq 1 64)) tail")"

echo "-- search_match: words, AND, literal (FP.3a)"
check_eq 'one word found anywhere' yes "$(matches 'firefox web browser' 'brow')"
check_eq 'a word that is not there' no "$(matches 'firefox web browser' 'mail')"
check_eq 'several words: all must be there (AND)' yes "$(matches 'firefox web browser' 'web fire')"
check_eq 'several words: one missing is enough to fail' no "$(matches 'firefox web browser' 'web mail')"
check_eq 'the order of the words does not matter' yes "$(matches 'document scanner simple-scan' 'scan document')"
check_eq 'no words match everything' yes "$(matches 'anything' '   ')"
check_eq 'an empty text matches everything' yes "$(matches 'anything' '')"
check_eq 'the query ignores case' yes "$(matches 'Firefox' 'FIREFOX')"
check_eq 'the query ignores accents' yes "$(matches 'Escáner de documentos' 'escaner')"
check_eq 'the text may have accents the query lacks and the other way round' yes "$(matches 'escaner' 'ESCÁNER')"
check_eq 'a star is a plain character, not a wildcard' no "$(matches 'firefox' '*')"
check_eq 'a question mark is a plain character' no "$(matches 'firefox' 'fire?ox')"
check_eq 'brackets are plain characters' no "$(matches 'firefox' '[f]irefox')"
check_eq 'a plus sign is found literally (c++)' yes "$(matches 'editor c++ pro' 'c++')"
check_eq 'a dot is not "any character"' no "$(matches 'firefox' 'f.refox')"
check_eq 'a hyphenated package name is found whole' yes "$(matches 'gnome-calculator' 'gnome-calc')"

echo "-- search_filter: the indexes that match"
filter() {
    local query="$1"
    app_eval "HAY=(); for t in 'Firefox web browser' 'Thunderbird email client' 'Escáner de documentos' 'Calculadora' 'Mail Spring email'; do fold_search \"\$t\"; HAY+=(\"\$REPLY\"); done; search_filter HAY '$query'; printf '%s' \"\${VISIBLE_IDX[*]-}\""
    printf '%s' "$OUT"
}
check_eq 'an empty search keeps every index' '0 1 2 3 4' "$(filter '')"
check_eq 'a search keeps the indexes that match, in order' '1 4' "$(filter 'email')"
check_eq 'a search with no match leaves none' '' "$(filter 'zzz')"
check_eq 'two words narrow the result' '4' "$(filter 'EMAIL spring')"
check_eq 'accents in the data and the query agree' '2' "$(filter 'escaner')"
app_eval 'HAY=(a b c d e); search_filter HAY ""; printf %s "${#HAY[@]}"'
check_eq 'search_filter works through a nameref and leaves the array alone' 5 "$OUT"

# ---------------------------------------------------------------------------
# FP.3b: detail of each application and origin of what apt does not manage
# ---------------------------------------------------------------------------
plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }
# many_apps: eight or more catalog applications installed (the search is offered).
many_apps() {
    fake_installed firefox thunderbird libreoffice gnome-calculator simple-scan rhythmbox pix xed baobab
}

echo "-- format_size_kb (FP.3b)"
size() {
    local kb="$1"; shift
    app_eval "format_size_kb '$kb'; printf '%s' \"\$REPLY\"" "$@"
    printf '%s' "$OUT"
}
check_eq 'zero is 0 KB' '0 KB' "$(size 0)"
check_eq 'under a megabyte stays in KB' '845 KB' "$(size 845)"
check_eq '1023 KB is still KB' '1023 KB' "$(size 1023)"
check_eq '1024 KB is 1.0 MB' '1.0 MB' "$(size 1024)"
check_eq 'megabytes carry one decimal, rounded to the nearest' '12.3 MB' "$(size 12595)"
check_eq 'a size just below the next tenth rounds down' '1023.4 MB' "$(size 1048000)"
check_eq 'just under a gigabyte rounds up to 1.0 GB, never to 1024.0 MB' '1.0 GB' "$(size 1048575)"
check_eq '1048576 KB is 1.0 GB' '1.0 GB' "$(size 1048576)"
check_eq 'gigabytes carry one decimal' '1.2 GB' "$(size 1258291)"
check_eq 'Spanish uses a decimal comma' '12,3 MB' "$(size 12595 MINTAPP_LANG=es)"
check_eq 'a text that is not a number counts as 0' '0 KB' "$(size abc)"
check_eq 'an empty size counts as 0' '0 KB' "$(size '')"
check_eq 'leading zeros are not octal' '10 KB' "$(size 010)"
check_eq 'a number with too many digits counts as 0 (it would wrap around)' '0 KB' "$(size 99999999999999999999)"

echo "-- load_package_detail"
new_sandbox
fake_installed libreoffice libreoffice-core firefox
fake_pkginfo libreoffice 24.2.7 30 Office
fake_pkginfo libreoffice-core 24.2.7 52000 Core
fake_pkginfo firefox 128.0.1+build1 251000 Browser
detail() { app_eval "load_package_detail $1; printf '%s|%s|%s|%s' \"\$DETAIL_MAIN\" \"\$DETAIL_VERSION\" \"\$DETAIL_EXTRA\" \"\$DETAIL_SIZE\""; printf '%s' "$OUT"; }
check_eq 'one package: name, version, no extras, size' 'firefox|128.0.1+build1|0|251000' "$(detail firefox)"
check_eq 'several packages: the first names the entry, sizes add up' 'libreoffice|24.2.7|1|52030' "$(detail 'libreoffice libreoffice-core')"
fake_installed bigpkg; fake_pkginfo bigpkg 1.0 99999999999999999999 Huge
check_eq 'a size with too many digits is ignored, not wrapped around' 'bigpkg|1.0|0|0' "$(detail bigpkg)"
cat > "$SB/bin/dpkg-query" <<EOF
#!/bin/sh
echo called >> "$SB/dq.log"
EOF
chmod 755 "$SB/bin/dpkg-query"; sandbox_chown
app_eval 'load_package_detail; printf "%s|%s|%s" "$DETAIL_MAIN" "$DETAIL_EXTRA" "$DETAIL_SIZE"'
check_eq 'no packages: empty detail' '|0|0' "$OUT"
check_eq 'no packages: dpkg-query is not called (it would list the whole system)' 0 "$(cat "$SB/dq.log" 2>/dev/null | wc -l)"

echo "-- option 1: detail in text mode (FP.3b)"
new_sandbox; fake_installed firefox libreoffice libreoffice-core
fake_pkginfo firefox 128.0.1+build1 251000 Browser
fake_pkginfo libreoffice 24.2.7 30 Office
fake_pkginfo libreoffice-core 24.2.7 52000 Core
app_run $'\n1\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'a line shows name, package, version and size' "$P" '✓ Firefox  [firefox 128.0.1+build1, 245.1 MB]'
assert_contains 'an application with more packages says how many more' "$P" '✓ LibreOffice  [libreoffice 24.2.7 (+1 more), 50.8 MB]'
assert_contains 'the total installed size is shown' "$P" 'Installed size (approx.): 295.9 MB'
assert_contains 'the count is still shown' "$P" '2 applications detected.'
app_run $'\nl\n1\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'Spanish: decimal comma and wording' "$P" '✓ Firefox  [firefox 128.0.1+build1, 245,1 MB]'
assert_contains 'Spanish: total line' "$P" 'Tamaño instalado (aprox.): 295,9 MB'
new_sandbox; fake_installed firefox
fake_pkginfo firefox 1.0 0 Browser
app_run $'\n1\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'a size of zero is left out instead of showing 0 KB' "$P" '✓ Firefox  [firefox 1.0]'
assert_not_contains 'no total line when nothing has a size' "$P" 'Installed size'
new_sandbox; fake_installed firefox
fake_pkginfo firefox $'1.0\e[31mX' 1024 Browser
app_run $'\n1\n\n0\n' MINTAPP_UI=text
assert_not_contains 'an escape sequence in a package version never reaches the terminal' "$OUT" $'\e[31m'
assert_contains 'the rest of that version is shown' "$(plain)" 'firefox 1.0[31mX'
new_sandbox; fake_installed firefox
app_run $'\n1\n\n0\n' MINTAPP_UI=text COLUMNS=40 LINES=24; P="$(plain)"
assert_contains 'a narrow screen wraps the detail instead of cutting it' "$P" '✓ Firefox  [firefox 1.0, 1.0 MB]'

echo "-- option 1: detail in whiptail (FP.3b)"
new_sandbox; fake_installed firefox
fake_pkginfo firefox 128.0 251000 Browser
fake_answers OK TAG:1 OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: the detail is in the dialog' "$(cat "$SB/state/whiptail.log")" '✓ Firefox  [firefox 128.0, 245.1 MB]'
assert_not_contains 'whiptail: a short list gets no search button' "$(cat "$SB/state/whiptail.log")" '--no-button Search'

echo "-- launcher_origin and origin labels (FP.3b)"
new_sandbox
mkdir -p "$SB/x/flatpak/exports/share/applications" "$SB/x/snapd/desktop/applications" "$SB/x/plain"
printf '[Desktop Entry]\nType=Application\nName=A\n' > "$SB/x/flatpak/exports/share/applications/a.desktop"
printf '[Desktop Entry]\nType=Application\nName=B\n' > "$SB/x/snapd/desktop/applications/b.desktop"
printf '[Desktop Entry]\nType=Application\nName=C\nExec=/usr/bin/flatpak run --branch=stable org.example.C\n' > "$SB/x/plain/c.desktop"
printf '[Desktop Entry]\nType=Application\nName=D\nExec=env BAMF=1 /snap/bin/d %%u\n' > "$SB/x/plain/d.desktop"
printf '[Desktop Entry]\nType=Application\nName=E\nExec=snap run e\n' > "$SB/x/plain/e.desktop"
printf '[Desktop Entry]\nType=Application\nName=F\nExec=/home/u/Apps/F.AppImage\n' > "$SB/x/plain/f.desktop"
printf '[Desktop Entry]\nType=Application\nName=G\n' > "$SB/x/plain/g.desktop"
sandbox_chown
origin() { app_eval "printf '<%s>' \"\$(origin_label \"\$(launcher_origin '$1')\")\""; printf '%s' "$OUT"; }
check_eq 'a launcher in a flatpak exports folder is Flatpak' '<Flatpak>' "$(origin "$SB/x/flatpak/exports/share/applications/a.desktop")"
check_eq 'a launcher in a snapd folder is Snap' '<Snap>' "$(origin "$SB/x/snapd/desktop/applications/b.desktop")"
check_eq 'an Exec line with "flatpak run" is Flatpak' '<Flatpak>' "$(origin "$SB/x/plain/c.desktop")"
check_eq 'an Exec line through /snap/bin is Snap' '<Snap>' "$(origin "$SB/x/plain/d.desktop")"
check_eq 'an Exec line with "snap run" is Snap' '<Snap>' "$(origin "$SB/x/plain/e.desktop")"
check_eq 'an AppImage is a manual install' '<manual install>' "$(origin "$SB/x/plain/f.desktop")"
check_eq 'a launcher with no Exec is a manual install' '<manual install>' "$(origin "$SB/x/plain/g.desktop")"
check_eq 'a launcher that does not exist is a manual install' '<manual install>' "$(origin "$SB/x/plain/none.desktop")"
app_eval 'APP_LANG=es; printf "<%s|%s|%s>" "$(origin_label manual)" "$(origin_label apt)" "$(origin_label other)"'
check_eq 'Spanish: manual install is translated, apt stays apt' '<instalación manual|apt|instalación manual>' "$OUT"

echo "-- option 3: origin of what apt does not manage (FP.3b)"
new_sandbox; fake_installed vlc
make_desktop vlc.desktop 'VLC media player'; fake_owner "$SB/apps/vlc.desktop" vlc
make_desktop flat.desktop 'Flat App' 'Exec=/usr/bin/flatpak run org.example.Flat'
make_desktop snp.desktop 'Snap App' 'Exec=/snap/bin/snp'
make_desktop man.desktop 'Hand Made' 'Exec=/opt/hand/run.sh'
make_desktop div.desktop 'Diverted'; fake_owner "$SB/apps/div.desktop" 'diversion by thing from'
app_run $'\n3\n\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'a Flatpak launcher is listed with its origin' "$P" '- Flat App [Flatpak]'
assert_contains 'a Snap launcher is listed with its origin' "$P" '- Snap App [Snap]'
assert_contains 'a manual launcher is listed with its origin' "$P" '- Hand Made [manual install]'
assert_contains 'an ambiguous apt owner is labelled apt' "$P" '- Diverted (ambiguous package) [apt]'
assert_not_contains 'the list of unmanaged launchers starts on its own line, not glued to the note' "$P" '.)  - '
assert_contains 'the count of unmanaged launchers is still there' "$P" '4 additional launchers cannot be uninstalled from here'
assert_contains 'the manageable application is offered' "$P" 'VLC media player [vlc]'
app_run $'\nl\n3\n\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'Spanish: the origin of a manual launcher is translated' "$P" '- Hand Made [instalación manual]'
new_sandbox
make_desktop flat.desktop 'Flat App' 'Exec=/usr/bin/flatpak run org.example.Flat'
app_run $'\n3\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'with nothing manageable the origin is listed too' "$P" '- Flat App [Flatpak]'
assert_not_contains 'with nothing manageable the list is not glued to the note either' "$P" '.)  - '
new_sandbox; fake_installed vlc
make_desktop vlc.desktop 'VLC media player'; fake_owner "$SB/apps/vlc.desktop" vlc
make_desktop flat.desktop 'Flat App' 'Exec=/usr/bin/flatpak run org.example.Flat'
fake_answers OK TAG:3 OK CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: the origin is in the advanced-mode dialog' "$(cat "$SB/state/whiptail.log")" '- Flat App [Flatpak]'

# ---------------------------------------------------------------------------
# FP.3c: search in the long lists
# ---------------------------------------------------------------------------
echo "-- option 1: search (FP.3c)"
new_sandbox; many_apps
app_run $'\n1\ns browser\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: "s word" searches at once and says what it shows' "$P" 'Search: "browser" (showing 1 of 9).'
assert_not_contains 'text: the filtered screen leaves out the rest' "${P#*Search: \"browser\"}" 'Rhythmbox'
assert_contains 'text: the filtered screen keeps the match with its detail' "${P#*Search: \"browser\"}" '✓ Firefox  [firefox 1.0, 1.0 MB]'
app_run $'\n1\ns\nmail\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: a lone "s" asks for the text on the next line' "$P" 'Search: "mail" (showing 1 of 9).'
app_run $'\n1\ns zzz\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: a search with no match shows 0 of N' "$P" 'Search: "zzz" (showing 0 of 9).'
assert_contains 'text: and counts 0 applications' "$P" '0 applications detected.'
app_run $'\n1\ns firefox\ns\n\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: an empty search brings the whole list back' "${P#*showing 1 of 9}" 'Rhythmbox'
app_run $'\n1\ns mail\ns firefox\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: a new search replaces the previous one' "$P" 'Search: "firefox" (showing 1 of 9).'
app_run $'\n1\ns a\x1b]0;TITLE\ab\n\n0\n' MINTAPP_UI=text
assert_not_contains 'text: a terminal escape typed into the search is not echoed' "$OUT" $'\e]0;'
app_run $'\n1\nx\n0\n' MINTAPP_UI=text
assert_not_contains 'text: any other answer leaves the screen' "$(plain)" 'showing'
new_sandbox; fake_installed firefox thunderbird
app_run $'\n1\ns firefox\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_not_contains 'text: a short list offers no search' "$P" 'showing'
app_run $'\nl\n1\ns navegador\n\n0\n' MINTAPP_UI=text MINTAPP_LANG=es; P="$(plain)"
assert_not_contains 'text: a short list in Spanish offers no search either' "$P" 'Búsqueda'
new_sandbox; many_apps
fake_answers OK TAG:1 NO TAG:browser OK TAG:0
app_run '' MINTAPP_UI=whiptail; W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail: a long list offers the search in the No button' "$W" '--yes-button OK --no-button Search --yesno'
assert_contains 'whiptail: the dialog asks for the text' "$W" '--inputbox Type what to look for'
assert_contains 'whiptail: the filtered list says what it shows' "$W" 'Search: "browser" (showing 1 of 9).'
check_eq 'whiptail: the filtered list leaves the rest out (Rhythmbox only in the first list)' 1 "$(grep -c '✓ Rhythmbox' "$SB/state/whiptail.log")"
new_sandbox; many_apps
fake_answers OK TAG:1 NO ESC OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_not_contains 'whiptail: cancelling the search dialog keeps the list as it was' "$(cat "$SB/state/whiptail.log")" 'Search: "'
check_eq 'whiptail: and the program carries on to the menu' 0 "$RC"

echo "-- option 2: search keeps what was marked (FP.3c)"
new_sandbox; many_apps
app_run $'\n2\n1\ns mail\n2\ns\n\nc\ny\n\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: marks made before and after a search go in one purge' "$(apt_log)" 'apt-get purge -y firefox thunderbird'
check_eq 'text: one real removal' 1 "$(real_removals)"
assert_contains 'text: a search shows its status above the list' "$P" 'Search: "mail" (showing 1 of 9).'
assert_contains 'text: an entry keeps its number while a search is on' "$P" '2)  ☑ Thunderbird'
new_sandbox; many_apps
app_run $'\n2\ns mail\n1\n0\n0\n' MINTAPP_UI=text
assert_contains 'text: an entry the search hides cannot be marked' "$OUT" 'Number out of range.'
app_run $'\n2\n18446744073709551617\nc\n' MINTAPP_UI=text
assert_contains 'text: a number that wraps around the arithmetic is out of range' "$OUT" 'Number out of range.'
assert_contains 'text: and it marked nothing (it is not entry 1)' "$OUT" 'No applications were selected.'
app_run $'\n2\n0000000000000000001\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: leading zeros still count as the number (not out of range)' "${P#*0000000}" '1)  ☑ Firefox'
app_run $'\n2\ns zzz\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: a search with no match says so' "$P" 'No application matches "zzz".'
check_eq 'text: nothing is removed' 0 "$(real_removals)"
app_run $'\n2\ns scan\nc\n' MINTAPP_UI=text
assert_contains 'text: confirming with nothing marked says so' "$OUT" 'No applications were selected.'
app_run $'\n2\ns simple-scan\n5\ns\n\nc\ny\n\n0\n' MINTAPP_UI=text
assert_contains 'text: the package name is searchable' "$(apt_log)" 'apt-get purge -y simple-scan'
app_run $'\n2\ns document\n5\ns\n\nc\ny\n\n0\n' MINTAPP_UI=text
assert_contains 'text: the description is searchable' "$(apt_log)" 'apt-get purge -y simple-scan'
app_run $'\n2\ns navegador\n1\ns\n\nc\ny\n\n0\n' MINTAPP_UI=text
assert_contains 'text: an English session finds an app by its Spanish description' "$(apt_log)" 'apt-get purge -y firefox'
app_run $'\n2\ns browser\n1\ns\n\nc\ny\n\n0\n' MINTAPP_UI=text MINTAPP_LANG=es
assert_contains 'text: a Spanish session finds an app by its English description' "$(apt_log)" 'apt-get purge -y firefox'
app_run $'\n2\ns ESCANER\n5\ns\n\nc\ny\n\n0\n' MINTAPP_UI=text MINTAPP_LANG=es
assert_contains 'text: the search ignores case and accents' "$(apt_log)" 'apt-get purge -y simple-scan'
new_sandbox; fake_installed firefox thunderbird
app_run $'\n2\ns\n0\n0\n' MINTAPP_UI=text
assert_contains 'text: a short list has no search (the key is invalid)' "$OUT" 'Invalid option.'
assert_not_contains 'text: a short list does not advertise it' "$(plain)" "Type 's' to search."
new_sandbox; many_apps
app_run $'\n2\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: a long list advertises the search' "$P" "Type 's' to search."
app_run $'\nl\n2\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: and says it in Spanish' "$P" "Escribe 's' para buscar."
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"1" "S"' TAG:mail 'TAG:"2"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail; W="$(cat "$SB/state/whiptail.log")"
check_eq 'whiptail: the flow ends well' 0 "$RC"
assert_contains 'whiptail: a mark hidden by the search is still purged' "$(apt_log)" 'apt-get purge -y firefox thunderbird'
assert_contains 'whiptail: the checklist has the search entry first' "$W" ' S Search (check here and press OK) OFF 1 Firefox'
assert_contains 'whiptail: the filtered checklist says what it shows' "$W" 'Search: "mail" (showing 1 of 9).'
assert_contains 'whiptail: the filtered checklist keeps the entry number' "$W" 'OFF 2 Thunderbird — Email client OFF'
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"1" "S"' TAG:mail 'TAG:"2" "S"' TAG: 'TAG:"1" "2"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail; W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail: after clearing the search the marks come back checked' "$W" '1 Firefox — Web browser ON 2 Thunderbird — Email client ON 3 LibreOffice'
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"S"' TAG:zzz OK 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail; W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail: a search with no match says so' "$W" 'No application matches "zzz".'
assert_contains 'whiptail: and the full list comes back' "$(apt_log)" 'apt-get purge -y firefox'
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"S"' ESC 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: cancelling the search dialog keeps the list' "$(apt_log)" 'apt-get purge -y firefox'
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"S"' 'TAG:a b' CANCEL
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail: cancelling the list removes nothing' 0 "$(real_removals)"
new_sandbox; fake_installed firefox thunderbird
fake_answers OK TAG:2 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_not_contains 'whiptail: a short list has no search entry' "$(cat "$SB/state/whiptail.log")" 'Search (check here and press OK)'
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:' OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: nothing checked says so' "$(cat "$SB/state/whiptail.log")" 'No applications were selected.'

echo "-- option 3: search in the advanced list (FP.3c)"
adv_many() {
    local n
    for n in Alpha Bravo Charlie Delta Echo Foxtrot Golf Hotel India; do
        fake_installed "tool-${n,,}"
        make_desktop "$n.desktop" "$n"; fake_owner "$SB/apps/$n.desktop" "tool-${n,,}"
    done
}
new_sandbox; adv_many
app_run $'\n3\n\ns charlie\n3\ns\n\nc\ny\n\n0\n' MINTAPP_UI=text
assert_contains 'text: the name is searchable' "$(apt_log)" 'apt-get purge -y tool-charlie'
check_eq 'text: only the chosen one is purged' 1 "$(real_removals)"
app_run $'\n3\n\ns tool-echo\n5\ns\n\nc\ny\n\n0\n' MINTAPP_UI=text
assert_contains 'text: the package is searchable' "$(apt_log)" 'apt-get purge -y tool-echo'
app_run $'\n3\n\ns charlie\n1\n0\n0\n' MINTAPP_UI=text
assert_contains 'text: a hidden entry cannot be marked here either' "$OUT" 'Number out of range.'
app_run $'\n3\n\ns tool\n1\ns delta\n4\ns\n\nc\nn\n\n0\n' MINTAPP_UI=text
assert_contains 'text: marks survive several searches' "$(plain)" 'Alpha [tool-alpha]'
app_run $'\n3\n\n0\n0\n' MINTAPP_UI=text
assert_contains 'text: the advanced list advertises the search' "$(plain)" "Type 's' to search."
new_sandbox; adv_many
fake_answers OK TAG:3 OK 'TAG:"S"' TAG:charlie 'TAG:"3"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: search then check one entry purges that package' "$(apt_log)" 'apt-get purge -y tool-charlie'
check_eq 'whiptail: one real removal' 1 "$(real_removals)"
# A search text that starts with "-" must reach whiptail as the starting text, not as an option.
new_sandbox; adv_many
make_desktop weird.desktop '-weird app'; fake_installed weirdpkg; fake_owner "$SB/apps/weird.desktop" weirdpkg
fake_answers OK TAG:3 OK 'TAG:"S"' TAG:-weird 'TAG:"S"' TAG: 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: a search starting with "-" is accepted twice and the flow completes' "$(apt_log)" 'apt-get purge -y weirdpkg'
new_sandbox; adv_many
app_run $'\n3\n\ns a\x01\x02b\n0\n0\n' MINTAPP_UI=text
check_eq 'a search with control characters does not crash the program' 0 "$RC"

# ---------------------------------------------------------------------------
# FP.3c: notice of what the search hides (marks outside the search are kept)
# ---------------------------------------------------------------------------
echo "-- search_hidden_marked and search_hidden_notice (FP.3c)"
hidden() { app_eval "$1; printf '%s' \"\$REPLY\"" "${@:2}"; printf '%s' "$OUT"; }
check_eq 'hidden marks: some marked entries are outside the search' 2 "$(hidden 'SEL=(1 0 1 0 1); VISIBLE_IDX=(0 1); search_hidden_marked SEL')"
check_eq 'hidden marks: nothing marked gives 0' 0 "$(hidden 'SEL=(0 0 0); VISIBLE_IDX=(0); search_hidden_marked SEL')"
check_eq 'hidden marks: marks inside the search are not counted' 0 "$(hidden 'SEL=(1 1 1); VISIBLE_IDX=(0 1 2); search_hidden_marked SEL')"
check_eq 'hidden marks: a search that shows nothing hides every mark' 2 "$(hidden 'SEL=(1 0 1); VISIBLE_IDX=(); search_hidden_marked SEL')"
check_eq 'hidden marks: an empty list gives 0' 0 "$(hidden 'SEL=(); VISIBLE_IDX=(); search_hidden_marked SEL')"
check_eq 'hidden marks: the marks are not changed' '1 0 1' "$(hidden 'SEL=(1 0 1); VISIBLE_IDX=(1); search_hidden_marked SEL; REPLY="${SEL[*]}"')"
check_eq 'notice: says how many marks the search hides (English)' 'Marked outside this search: 2 (kept).' "$(hidden 'SEL=(1 0 1); VISIBLE_IDX=(1); search_hidden_notice SEL' MINTAPP_LANG=en)"
check_eq 'notice: says it in Spanish' 'Marcadas fuera de esta búsqueda: 2 (se conservan).' "$(hidden 'SEL=(1 0 1); VISIBLE_IDX=(1); search_hidden_notice SEL' MINTAPP_LANG=es)"
check_eq 'notice: empty when no mark is hidden' '' "$(hidden 'SEL=(0 1 0); VISIBLE_IDX=(1); search_hidden_notice SEL')"

echo "-- option 2: notice of marks outside the search (FP.3c)"
new_sandbox; many_apps
app_run $'\n2\n1\ns mail\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: a mark the search hides is announced' "$P" 'Marked outside this search: 1 (kept).'
assert_contains 'text: the notice comes right after the search status' "$P" $'Search: "mail" (showing 1 of 9).\nMarked outside this search: 1 (kept).'
app_run $'\n2\n1\n0\n0\n' MINTAPP_UI=text
assert_not_contains 'text: no search, no notice' "$(plain)" 'Marked outside'
app_run $'\n2\n2\ns mail\n0\n0\n' MINTAPP_UI=text
assert_not_contains 'text: a mark that stays visible is not announced' "$(plain)" 'Marked outside'
app_run $'\n2\ns mail\n0\n0\n' MINTAPP_UI=text
assert_not_contains 'text: nothing marked, no notice' "$(plain)" 'Marked outside'
app_run $'\n2\n1\n3\ns mail\n0\n0\n' MINTAPP_UI=text
assert_contains 'text: the notice counts every hidden mark' "$(plain)" 'Marked outside this search: 2 (kept).'
app_run $'\n2\n1\ns mail\n2\ns scan\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: the count follows the marks made during the search' "$P" 'Marked outside this search: 2 (kept).'
app_run $'\n2\n1\ns mail\ns\n\n0\n0\n' MINTAPP_UI=text
check_eq 'text: clearing the search removes the notice' 1 "$(plain | grep -c 'Marked outside')"
app_run $'\n2\n1\ns zzz\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'text: a search with no match still announces the marks it hides' "$P" 'Marked outside this search: 1 (kept).'
app_run $'\n2\n1\ns mail\n0\n0\n' MINTAPP_UI=text MINTAPP_LANG=es
assert_contains 'text: the notice in Spanish' "$(plain)" 'Marcadas fuera de esta búsqueda: 1 (se conservan).'
app_run $'\n2\n1\ns mail\n0\n0\n' MINTAPP_UI=text COLUMNS=40 NO_COLOR=1
check_eq 'text: a narrow terminal does not lose it' 'Marked outside this search: 1 (kept).' "$(plain | grep 'Marked outside' | head -n1)"
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"1" "S"' TAG:mail CANCEL
app_run '' MINTAPP_UI=whiptail; W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail: the filtered checklist announces the hidden mark' "$W" $'Search: "mail" (showing 1 of 9).\nMarked outside this search: 1 (kept).'
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"1" "S"' TAG:mail 'TAG:"2" "S"' TAG: CANCEL
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail: the full list that comes back has no notice' 1 "$(grep -c 'Marked outside' "$SB/state/whiptail.log")"
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"2" "S"' TAG:mail CANCEL
app_run '' MINTAPP_UI=whiptail
assert_not_contains 'whiptail: a mark that stays visible is not announced' "$(cat "$SB/state/whiptail.log")" 'Marked outside'
new_sandbox; many_apps
fake_answers OK TAG:2 'TAG:"1" "S"' TAG:mail CANCEL
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=es
assert_contains 'whiptail: the notice in Spanish' "$(cat "$SB/state/whiptail.log")" 'Marcadas fuera de esta búsqueda: 1 (se conservan).'

echo "-- option 3: notice of marks outside the search (FP.3c)"
new_sandbox; adv_many
app_run $'\n3\n\n1\ns charlie\n0\n0\n' MINTAPP_UI=text
assert_contains 'text: the advanced list announces the hidden mark' "$(plain)" 'Marked outside this search: 1 (kept).'
new_sandbox; adv_many
fake_answers OK TAG:3 OK 'TAG:"1" "S"' TAG:charlie CANCEL
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: the advanced checklist announces the hidden mark' "$(cat "$SB/state/whiptail.log")" 'Marked outside this search: 1 (kept).'

# ---------------------------------------------------------------------------
# FP.3c: labels fitted to the box (whiptail does not cut a label itself: it
# runs past the frame or covers the scroll bar)
# ---------------------------------------------------------------------------
echo "-- wt_label_width (FP.3c)"
lw() { app_eval "wt_label_width $1 $2; printf '%s' \"\$REPLY\""; printf '%s' "$OUT"; }
check_eq 'width: box width - 15 - digits of the entry count (1 digit)' 57 "$(lw 73 5)"
check_eq 'width: 2 digits' 56 "$(lw 73 25)"
check_eq 'width: 3 digits' 55 "$(lw 73 300)"
check_eq 'width: follows the box' 104 "$(lw 120 9)"
check_eq 'width: never below 10' 10 "$(lw 20 5)"

echo "-- wt_fit_label (FP.3c)"
# fit WIDTH LABEL TAIL [VAR=val ...]: the label as the program fits it, between < >.
fit() {
    local w="$1" label="$2" tail="$3"; shift 3
    app_eval "wt_fit_label $w '$label' '$tail'; printf '<%s>' \"\$REPLY\"" LC_ALL=C.UTF-8 "$@"
    printf '%s' "$OUT"
}
check_eq 'fit: a label that fits is unchanged' '<Firefox — Web browser>' "$(fit 30 'Firefox — Web browser' '')"
check_eq 'fit: exactly the width is unchanged' '<12345678901234567890>' "$(fit 20 '12345678901234567890' '')"
check_eq 'fit: one column over is cut, the ellipsis counted in the width' '<1234567890123456789…>' "$(fit 20 '123456789012345678901' '')"
check_eq 'fit: no blank is left before the ellipsis' '<abcdefghijklm…>' "$(fit 15 'abcdefghijklm nopqrstuv' '')"
check_eq 'fit: an accented letter is one column' '<Ábaco — des…>' "$(fit 12 'Ábaco — descripción larga' '')"
check_eq 'fit: in ASCII the ellipsis is three dots and still fits' '<12345678901234567...>' "$(fit 20 '1234567890123456789012345' '' MINTAPP_ASCII=1)"
check_eq 'fit: the tail stays whole and the name is cut' '<Text edi…  [gnome-text-editor]>' "$(fit 30 'Text editor and other long words  [gnome-text-editor]' '[gnome-text-editor]')"
check_eq 'fit: a label that fits keeps its tail as it was' '<Bravo  [tool-bravo]>' "$(fit 30 'Bravo  [tool-bravo]' '[tool-bravo]')"
check_eq 'fit: a tail that leaves no room for a name cuts the whole label' '<Text editor and oth…>' "$(fit 20 'Text editor and other long words  [gnome-text-editor]' '[gnome-text-editor]')"
check_eq 'fit: a tail the label does not end with is ignored' '<12345678901234567…>' "$(fit 18 '12345678901234567890' '[zzz]')"
check_eq 'fit: a tiny width does not abort' '<abc…>' "$(fit 3 'abcdefghij' '')"
app_eval 'bad=0
for w in $(seq 4 60); do
    for l in "short" "A rather long application name with words — and a long description to cut" "Ábaco ñandú — acentos y más texto para recortar bien" "x"; do
        wt_fit_label "$w" "$l" ""; [ "${#REPLY}" -le "$w" ] || bad=$((bad + 1))
        wt_fit_label "$w" "$l  [pkg-name-x]" "[pkg-name-x]"; [ "${#REPLY}" -le "$w" ] || bad=$((bad + 1))
    done
done
printf "%s" "$bad"' LC_ALL=C.UTF-8
check_eq 'fit: the result is never wider than the width (4 to 60, with and without a tail)' 0 "$OUT"

echo "-- whiptail lists: every label fits the box (FP.3c)"
# A "tput" that reports FAKE_COLS columns, so a test can pick the size of the terminal.
mkterm() {
    mkdir -p "$SB/term"
    printf '#!/bin/sh\ncase "$1" in lines) echo "${FAKE_LINES:-24}" ;; cols) echo "${FAKE_COLS:-80}" ;; colors) echo 256 ;; *) exit 1 ;; esac\n' > "$SB/term/tput"
    chmod 755 "$SB/term/tput"
    sandbox_chown
}
# labels_fit: how many rows the last checklist had and how many labels are wider than
# the box allows (width - 15 - digits of the number of entries, the search entry apart).
labels_fit() {
    local dump width total limit rows=0 over=0 tag label len
    dump="$(checklist_dump)"
    width="$(head -n1 <<< "$dump" | cut -d' ' -f2)"
    total="$(tail -n +2 <<< "$dump" | cut -f1 | grep -vcx S || true)"
    limit=$(( width - 15 - ${#total} ))
    while IFS=$'\t' read -r tag label _; do
        [ -n "$tag" ] || continue
        rows=$((rows + 1))
        len="$(printf '%s' "$label" | LC_ALL=C.UTF-8 wc -m)"
        [ "$len" -le "$limit" ] || over=$((over + 1))
    done < <(tail -n +2 <<< "$dump")
    printf 'rows=%s over=%s' "$rows" "$over"
}
# term_run COLS: option 2 or 3 with the checklist cancelled, in a terminal COLS wide.
term_run() {
    mkterm
    app_run '' MINTAPP_UI=whiptail LC_ALL=C.UTF-8 PATH="$SB/term:$SB/bin:$H_SYS_PATH" FAKE_COLS="$1"
}
for cols in 40 60 80 120 200; do
    new_sandbox; many_apps; fake_installed mintstick
    fake_answers OK TAG:2 CANCEL
    term_run "$cols"
    check_eq "whiptail option 2, $cols columns: every label fits the box" 'rows=11 over=0' "$(labels_fit)"
done
new_sandbox; many_apps; fake_installed mintstick
fake_answers OK TAG:2 CANCEL
term_run 80
D="$(checklist_dump)"
check_eq 'whiptail option 2, 80 columns: the numbering is not touched by the cut' 'S 1 2 3 4 5 6 7 8 9 10' "$(tail -n +2 <<< "$D" | cut -f1 | paste -sd' ')"
assert_contains 'whiptail option 2, 80 columns: a label that fits is as it was' "$D" $'1\tFirefox — Web browser\tOFF'
assert_contains 'whiptail option 2, 80 columns: the long one ends with the ellipsis' "$D" $'USB Tools (USB Image Writer + USB Stick Formatter) — Wr…\tOFF'
assert_contains 'whiptail option 2, 80 columns: the search entry fits whole' "$D" $'S\tSearch (check here and press OK)\tOFF'
new_sandbox; many_apps; fake_installed mintstick; mkterm
fake_answers OK TAG:2 CANCEL
app_run '' MINTAPP_UI=whiptail LC_ALL=C.UTF-8 PATH="$SB/term:$SB/bin:$H_SYS_PATH" FAKE_COLS=60 MINTAPP_LANG=en
assert_contains 'whiptail option 2, 60 columns: the search entry keeps its instruction (English)' "$(checklist_dump)" $'S\tSearch (check here and press OK)\tOFF'
fake_answers OK TAG:2 CANCEL
app_run '' MINTAPP_UI=whiptail LC_ALL=C.UTF-8 PATH="$SB/term:$SB/bin:$H_SYS_PATH" FAKE_COLS=60 MINTAPP_LANG=es
assert_contains 'whiptail option 2, 60 columns: the search entry keeps its instruction (Spanish)' "$(checklist_dump)" $'S\tBuscar (marca aquí y pulsa Aceptar)\tOFF'
new_sandbox; many_apps; fake_installed mintstick
fake_answers OK TAG:2 CANCEL
term_run 200
assert_contains 'whiptail option 2, a wide terminal: nothing is cut' "$(checklist_dump)" $'USB Tools (USB Image Writer + USB Stick Formatter) — Write ISO images and format USB drives\tOFF'
new_sandbox; many_apps; fake_installed mintstick; mkterm
fake_answers OK TAG:2 'TAG:"9"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail LC_ALL=C.UTF-8 PATH="$SB/term:$SB/bin:$H_SYS_PATH" FAKE_COLS=60
assert_contains 'whiptail option 2: marking a cut entry purges its package' "$(apt_log)" 'apt-get purge -y mintstick'
for cols in 40 60 80 120; do
    new_sandbox; adv_many; mkterm
    make_desktop long.desktop 'An application with a really very long name that will not fit'
    fake_installed long-package-name; fake_owner "$SB/apps/long.desktop" long-package-name
    fake_answers OK TAG:3 OK CANCEL
    term_run "$cols"
    check_eq "whiptail option 3, $cols columns: every label fits the box" 'rows=11 over=0' "$(labels_fit)"
    if [ "$cols" -ge 60 ]; then
        assert_contains "whiptail option 3, $cols columns: a cut name keeps its [package] whole" "$(checklist_dump)" '  [long-package-name]'$'\t'
    fi
done

finish
