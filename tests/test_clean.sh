#!/usr/bin/env bash
# System cleaning, steps P.4a to P.4d (FP.4): the catalog (entries, levels, rights, texts in both
# languages), the engine that lists and removes files (what paths it accepts, what it lists, what
# it skips, what it removes) and the menus of the deep cleanup (the level, then what to clean:
# all of it, by category or one by one), then what runs after the summary: the confirmation, the
# run, the result and the record. Fast: everything happens in folders of the sandbox, never on the
# real system.
# SC2016 is off for the whole file: the code given to app_eval is single-quoted on purpose, because
# the program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

new_sandbox
H="$SB/home"

value_of() { local v="${OUT#*<<}"; check_eq "$1" "$2" "${v%%>>*}"; }
# ev LABEL EXPECTED CODE [VAR=val ...]: CODE prints <<value>>, which must be EXPECTED.
ev() { local label="$1" expected="$2" code="$3"; shift 3; app_eval "$code" "$@"; value_of "$label" "$expected"; }
# eng INTERFACE: the code that makes the program run with text, tui, whiptail or gui. select_interface sets UI_ENGINE and
# HAVE_WHIPTAIL when the program loads, so a UI_ENGINE=... in the environment is ignored (the harness refuses it): the interface
# goes in the code that is evaluated, before what the test runs.
eng() {
    case "$1" in
        text) printf 'UI_ENGINE=text; HAVE_WHIPTAIL=0' ;;
        tui|whiptail|gui) printf 'UI_ENGINE=%s; HAVE_WHIPTAIL=1' "$1" ;;
        *) echo "eng: unknown interface: $1" >&2; return 1 ;;
    esac
}

echo "-- Catalog: entries, levels, rights, BleachBit"
ev 'fourteen entries' 14 'printf "<<%s>>" "${#CLEAN_CATALOG[@]}"'
ev 'every entry: five fields, a known category and level, rights 0 or 1, no repeated id' ok '
bad=0; ids=" "
for line in "${CLEAN_CATALOG[@]}"; do
    IFS="|" read -r -a f <<< "$line"
    [ "${#f[@]}" -eq 5 ] || bad=1
    [[ "${f[1]}" =~ ^(privacy|cache|logs|packages)$ ]] || bad=1
    [[ "${f[2]}" =~ ^(SC|C)$ ]] || bad=1
    [[ "${f[3]}" =~ ^[01]$ ]] || bad=1
    [[ "$ids" != *" ${f[0]} "* ]] || bad=1
    ids+="${f[0]} "
done
printf "<<%s>>" "$([ "$bad" -eq 0 ] && echo ok || echo bad)"'
ev 'every entry cites its BleachBit cleaners, except the three this program adds' ok '
bad=0
for line in "${CLEAN_CATALOG[@]}"; do
    IFS="|" read -r id _ _ _ bb <<< "$line"
    if [[ "$id" =~ ^(rc_config|crash|app_caches)$ ]]; then [ "$bb" = "-" ] || bad=1
    else [[ "$bb" =~ ^[a-z_0-9]+\.[a-z_0-9]+( [a-z_0-9]+\.[a-z_0-9]+)*$ ]] || bad=1; fi
done
printf "<<%s>>" "$([ "$bad" -eq 0 ] && echo ok || echo bad)"'
ev 'simple level: no privacy item the user may consider theirs, nor X11 logs, nor leftover settings' \
    'recent clipboard thumbnails browsers cache app_caches tmp rotated_logs journal apt_cache' 'clean_ids S; printf "<<%s>>" "${CLEAN_LIST[*]}"'
ev 'complete level: all fourteen, in catalog order' \
    'recent clipboard trash thumbnails browsers cache app_caches tmp rotated_logs journal x11_logs crash apt_cache rc_config' 'clean_ids C; printf "<<%s>>" "${CLEAN_LIST[*]}"'
ev 'the entries that need administrator rights' 'rotated_logs journal crash apt_cache rc_config' '
clean_ids C; out=""
for id in "${CLEAN_LIST[@]}"; do clean_field "$id" 4; [ "$REPLY" -ne 1 ] || out+="$id "; done
printf "<<%s>>" "${out% }"'
ev 'an entry that does not exist: status 1' 1 'clean_field nothing 2; printf "<<%s>>" $?'
ev 'clean_field: the category of the trash' privacy 'clean_field trash 2; printf "<<%s>>" "$REPLY"'
ev 'simple level: the limits in days (cache, tmp, rotated logs, journal)' '30 7 7 14' '
out=""; for id in cache tmp rotated_logs journal; do clean_days "$id" S; out+="$REPLY "; done; printf "<<%s>>" "${out% }"'
ev 'complete level: no limit anywhere' '0 0 0 0' '
out=""; for id in cache tmp rotated_logs journal; do clean_days "$id" C; out+="$REPLY "; done; printf "<<%s>>" "${out% }"'
ev 'simple level: what has no limit says 0' '0 0' 'clean_days recent S; a="$REPLY"; clean_days apt_cache S; printf "<<%s %s>>" "$a" "$REPLY"'
ev 'the limits are constants the user could change in one place' '14 7 30 7' 'printf "<<%s %s %s %s>>" "$CLEAN_DAYS_JOURNAL" "$CLEAN_DAYS_LOGS" "$CLEAN_DAYS_CACHE" "$CLEAN_DAYS_TMP"'

echo "-- Catalog: names and descriptions in both languages"
texts() {  # texts LANG: the name and the description of every entry, one per line
    app_eval 'clean_ids C; for id in "${CLEAN_LIST[@]}"; do printf "%s\n%s\n" "$(clean_name "$id")" "$(clean_desc "$id")"; done' MINTAPP_LANG="$1" MINTAPP_ASCII=0
    printf '%s\n' "$OUT"
}
EN_TXT="$(texts en)"; ES_TXT="$(texts es)"
check_eq 'English: a name and a description for each of the fourteen' 28 "$(grep -c . <<< "$EN_TXT")"
check_eq 'Spanish: a name and a description for each of the fourteen' 28 "$(grep -c . <<< "$ES_TXT")"
check_eq 'no text is the same in both languages' 0 "$(paste -d'|' <(printf '%s\n' "$EN_TXT") <(printf '%s\n' "$ES_TXT") | awk -F'|' '$1 == $2' | grep -c . || true)"
cats() {
    app_eval 'for c in privacy cache logs packages; do printf "%s\n" "$(clean_cat_name "$c")"; done' MINTAPP_LANG="$1" MINTAPP_ASCII=0
    printf '%s\n' "$OUT"
}
check_eq 'English: the four categories' 'Privacy|Caches|Logs|Packages' "$(cats en | grep . | paste -sd'|')"
check_eq 'Spanish: the four categories' 'Privacidad|Cachés|Registros|Paquetes' "$(cats es | grep . | paste -sd'|')"
check_eq 'the texts that say "needs administrator rights" are the entries that do' 5 "$(grep -ci 'administrator rights' <<< "$EN_TXT")"

echo "-- Places the cleaning may work in (clean_path_ok)"
pathok() {  # pathok LABEL EXPECTED PATH [VAR=val ...]: status of clean_path_ok
    local label="$1" expected="$2" path="$3"; shift 3
    app_eval "clean_path_ok $(printf '%q' "$path"); printf '<<%s>>' \$?" "$@"
    value_of "$label" "$expected"
}
for p in "$H/.cache" "$H/.local/share/Trash/files" "$H/a/b" /tmp /var/tmp /var/log /var/crash /var/lib/systemd/coredump /var/cache/apt; do
    pathok "allowed: ${p/#$H/\~}" 0 "$p"
done
TILDE='~'
for p in '' relative/path "$TILDE/.cache" . / /etc /usr /var /var/lib /var/lib/dpkg /var/lib/systemd /var/cache /var/cache/apt/archives /var/crash/x /var/lib/systemd/coredump/x /tmp/x /var/log/syslog /boot /root "$H" "$H/" "$H/.cache/" \
         "$H/../x" "$H/./x" "$H//x" "$H/a/../b" "$H/.cache/.." /tmp/../etc /tmp/ /tmpx /var/tmp/.. /home/other/.cache "$H.other/.cache" \
         "$H/.cache"$'\n' $'/tmp\n/etc'; do
    pathok "refused: $(printf '%q' "${p/#$H/\~}")" 1 "$p"
done
pathok 'HOME empty: the home folder is not trusted' 1 "$H/.cache" HOME=
pathok 'HOME empty: /tmp is still allowed' 0 /tmp HOME=
pathok 'HOME is /: nothing under it' 1 /.cache HOME=/
pathok 'HOME is /root (one component): refused' 1 /root/.cache HOME=/root
pathok 'HOME of one component: even a deep folder under it is refused' 1 /root/a/b HOME=/root
pathok 'HOME is relative: refused' 1 "$H/.cache" HOME=home/u
pathok 'HOME with a ".." component: refused' 1 /home/u/../v/.cache HOME=/home/u/../v
pathok 'HOME of two components: its folders are allowed' 0 /home/u/.cache HOME=/home/u

echo "-- Listing (clean_scan)"
mk_tree() {
    rm -rf -- "$H/.cache" "$H/.cache2" "$H/rootfile" "$SB/outside" "$SB/decoy" "$H/decoy2"
    fake_file "$H/.cache/a/one" 100; fake_age "$H/.cache/a/one" 40
    fake_file "$H/.cache/a/two" 200
    fake_file "$H/.cache/b" 300; fake_age "$H/.cache/b" 10
    mkdir -p "$H/.cache/empty" "$SB/outside"
    fake_file "$SB/outside/file" 50
    ln -s "$SB/outside/file" "$H/.cache/link"
    ln -s "$SB/outside" "$H/.cache/dlink"
    sandbox_chown
}
list() {  # list LABEL EXPECTED ARGS...: what clean_scan ARGS lists, joined by "|" (@ stands for the home folder)
    local label="$1" expected="$2"; shift 2
    local code='clean_scan'; local a
    for a in "$@"; do code+=" $(printf '%q' "$a")"; done
    app_eval "$code | tr '\0' '\n' | cut -d' ' -f2- | sed \"s|\$HOME|@|\" | sort | paste -sd'|'"
    check_eq "$label" "$expected" "$OUT"
}
mk_tree
list 'everything: files and links, no folders, nothing behind a link to a folder' \
    '@/.cache/a/one|@/.cache/a/two|@/.cache/b|@/.cache/dlink|@/.cache/link' "$H/.cache" 0 0
list 'a limit of 30 days: only what is older and was not used since' '@/.cache/a/one' "$H/.cache" 30 0
list 'a limit of 5 days: the ones of 40 and 10 days' '@/.cache/a/one|@/.cache/b' "$H/.cache" 5 0
touch -m -d '40 days ago' "$H/.cache/a/two"
list 'changed long ago but used today: kept (it is not "unused")' '@/.cache/a/one' "$H/.cache" 30 0
mk_tree
list 'extra tests of the program narrow the list (-name)' '@/.cache/a/two' "$H/.cache" 0 0 -name two
app_eval 'clean_scan "$HOME/.cache" 0 0 -name one | tr "\0" "\n"'
check_eq 'a record is "SIZE PATH": the size of the file in bytes' "100 $H/.cache/a/one" "$OUT"
list 'the root itself is never listed' '' "$H/.cache/empty" 0 0
printf 'x' > "$H/rootfile"; mkdir -p "$H/.cache"; cp "$H/rootfile" "$H/.cache/rootfile"
if [ "$(id -u)" -eq 0 ]; then
    list 'own files only (OWN=1): what belongs to someone else is not listed' \
        '@/.cache/a/one|@/.cache/a/two|@/.cache/b|@/.cache/dlink|@/.cache/link' "$H/.cache" 0 1
    list 'without OWN: it is listed' \
        '@/.cache/a/one|@/.cache/a/two|@/.cache/b|@/.cache/dlink|@/.cache/link|@/.cache/rootfile' "$H/.cache" 0 0
else
    skip_case 'own files only: needs files of another user (run as root)'
fi
rm -f "$H/.cache/rootfile"
for r in /etc "$H" "$H/nothing" "$H/.cache/a/one"; do
    list "refused: $(printf '%q' "${r/#$H/\~}")" '' "$r" 0 0
done
ln -s "$H/.cache" "$H/.cache2"
list 'a root that is a link to a folder is refused' '' "$H/.cache2" 0 0
list 'a limit that is not a number is refused' '' "$H/.cache" 1x 0
app_eval 'clean_scan /etc 0 0; a=$?; clean_scan "$HOME/.cache2" 0 0; b=$?; clean_scan "$HOME/.cache" x 0; c=$?; clean_scan "$HOME/.cache" 0 0 >/dev/null; d=$?; printf "<<%s %s %s %s>>" $a $b $c $d'
value_of 'status: 1 for a refused root, a link, a bad limit; 0 for a good one' '1 1 1 0'
app_eval 'declare -f clean_scan'
assert_contains 'the listing never leaves the filesystem' "$OUT" '-xdev'
assert_contains 'the listing never lists the root' "$OUT" '-mindepth 1'
assert_not_contains 'the listing does not follow links (no find -L or -follow)' "$OUT" 'find -L'
assert_not_contains 'the listing does not follow links (no -follow)' "$OUT" '-follow'

echo "-- Files in use (clean_open_files)"
mk_tree
app_eval 'exec 7< "$HOME/.cache/a/one"; clean_open_files "$HOME/open.txt"; exec 7<&-; printf "<<%s %s>>" "$(grep -cxF "$HOME/.cache/a/one" "$HOME/open.txt")" "$(grep -cxF "$HOME/.cache/a/two" "$HOME/open.txt" || true)"'
value_of 'a file a process has open is listed; one that is not open, not' '1 0'
app_eval 'clean_open_files "$HOME/open.txt"; printf "<<%s>>" "$(grep -vc "^/" "$HOME/open.txt" || true)"'
value_of 'only paths: no sockets or pipes in the list' 0

echo "-- Removal (clean_apply)"
res() { printf '<<%s|%s|%s|%s>>' "$CLEAN_FILES" "$CLEAN_BYTES" "$CLEAN_SKIPPED" "$CLEAN_FAILED"; }
apply() {  # apply CODE: CODE runs after clean_apply; prints <<files|bytes|skipped|failed>> then CODE's output
    app_eval "$1"
}
mk_tree
T1="$SB/outside/file"; T2="$SB/outside"
EXP=$(( 600 + ${#T1} + ${#T2} ))
apply 'clean_apply "$HOME/.cache" /dev/null < <(clean_scan "$HOME/.cache" 0 0); printf "<<%s|%s|%s|%s>>" "$CLEAN_FILES" "$CLEAN_BYTES" "$CLEAN_SKIPPED" "$CLEAN_FAILED"'
value_of 'everything: five files and links removed, with their bytes' "5|$EXP|0|0"
check_eq 'the root stays' yes "$([ -d "$H/.cache" ] && echo yes || echo no)"
check_eq 'the folders that were left empty are gone' none "$(find "$H/.cache" -mindepth 1 | grep . || echo none)"
check_eq 'what a link pointed to is untouched (the file)' yes "$([ -f "$SB/outside/file" ] && echo yes || echo no)"
check_eq 'what a link pointed to is untouched (the folder)' yes "$([ -d "$SB/outside" ] && echo yes || echo no)"

mk_tree
printf '%s\n' "$H/.cache/b" > "$SB/state/open.txt"; sandbox_chown
app_eval "clean_apply \"\$HOME/.cache\" '$SB/state/open.txt' < <(clean_scan \"\$HOME/.cache\" 0 0); printf '<<%s|%s|%s|%s>>' \"\$CLEAN_FILES\" \"\$CLEAN_BYTES\" \"\$CLEAN_SKIPPED\" \"\$CLEAN_FAILED\""
value_of 'a file in the list of open files is skipped' "4|$((300 + ${#T1} + ${#T2}))|1|0"
# shellcheck disable=SC2015
check_eq 'the open file is still there' yes "$([ -f "$H/.cache/b" ] && echo yes || echo no)"

mk_tree
echo decoy > "$SB/decoy"; echo decoy > "$H/decoy2"; sandbox_chown
bad() {  # bad LABEL RECORD...: records written by hand; none may remove anything
    local label="$1"; shift
    local rec code='clean_apply "$HOME/.cache" /dev/null < <('
    for rec in "$@"; do code+="printf '%s\\0' $(printf '%q' "$rec"); "; done
    code+='); printf "<<%s|%s|%s|%s>>" "$CLEAN_FILES" "$CLEAN_BYTES" "$CLEAN_SKIPPED" "$CLEAN_FAILED"'
    app_eval "$code"
    value_of "$label" "0|0|$#|0"
}
bad 'a path outside the root is skipped, not removed' "5 $SB/decoy"
bad 'a path with ".." is skipped, not removed' "5 $H/.cache/../decoy2" "5 $H/.cache/a/../../decoy2"
bad 'a size that is not a number is skipped' "x $H/.cache/a/two" "-5 $H/.cache/a/two" " $H/.cache/a/two"
bad 'a path with a "." component is skipped' "5 $H/.cache/./b"
bad 'the root itself is skipped' "5 $H/.cache"
bad 'a folder with files in it is skipped: only files and links are removed' "5 $H/.cache/a"
bad 'a path in another folder of the home is skipped' "5 $H/decoy2"
check_eq 'the folder and its files are still there' 'yes yes' "$([ -f "$H/.cache/a/one" ] && echo -n 'yes ' || echo -n 'no '; [ -d "$H/.cache/a" ] && echo yes || echo no)"
check_eq 'nothing was removed by those records' 'yes yes yes yes' \
    "$([ -f "$SB/decoy" ] && echo -n 'yes ' || echo -n 'no '; [ -f "$H/decoy2" ] && echo -n 'yes ' || echo -n 'no '; [ -f "$H/.cache/a/two" ] && echo -n 'yes ' || echo -n 'no '; [ -f "$H/.cache/b" ] && echo yes || echo no)"

mk_tree
printf 'x' > "$H/.cache/with space"; printf 'x' > "$H/.cache/new
line"; printf 'x' > "$H/.cache/-dash"; printf 'x' > "$H/.cache/'quote\"s"; sandbox_chown
apply 'clean_apply "$HOME/.cache" /dev/null < <(clean_scan "$HOME/.cache" 0 0); printf "<<%s|%s>>" "$CLEAN_FILES" "$CLEAN_SKIPPED"'
value_of 'names with spaces, a new line, a dash or quotes are removed whole (5 + 4 files)' '9|0'
check_eq 'nothing odd is left behind' none "$(find "$H/.cache" -mindepth 1 | grep . || echo none)"

mk_tree
mkdir -p "$H/.cache/work"; printf 'x' > "$H/.cache/work/helper"; printf 'x' > "$H/.cache/mintapp-remover.lock"; sandbox_chown
apply 'GUI_WORK_DIR="$HOME/.cache/work"; clean_apply "$HOME/.cache" /dev/null < <(clean_scan "$HOME/.cache" 0 0); printf "<<%s|%s>>" "$CLEAN_FILES" "$CLEAN_SKIPPED"'
value_of 'the work folder of the program and its lock are skipped' '5|2'
check_eq 'they are still there' 'yes yes' "$([ -f "$H/.cache/work/helper" ] && echo -n 'yes ' || echo -n 'no '; [ -f "$H/.cache/mintapp-remover.lock" ] && echo yes || echo no)"

mk_tree
mkdir -p "$H/.cache/ro"; printf 'xxxx' > "$H/.cache/ro/stuck"; chmod 555 "$H/.cache/ro"; sandbox_chown
apply 'clean_apply "$HOME/.cache" /dev/null < <(clean_scan "$HOME/.cache" 0 0); printf "<<%s|%s>>" "$CLEAN_FILES" "$CLEAN_FAILED"'
value_of 'a file that cannot be removed is counted as failed, the rest goes on' '5|1'
check_eq 'the file that could not be removed is still there' yes "$([ -f "$H/.cache/ro/stuck" ] && echo yes || echo no)"
chmod 755 "$H/.cache/ro"

mk_tree
mkdir -p "$H/.cache/many"; (cd "$H/.cache/many" && seq 1 450 | xargs touch); sandbox_chown
apply 'clean_apply "$HOME/.cache" /dev/null < <(clean_scan "$HOME/.cache" 0 0 -path "*/many/*"); printf "<<%s|%s|%s>>" "$CLEAN_FILES" "$CLEAN_SKIPPED" "$CLEAN_FAILED"'
value_of '450 files, removed in groups, all counted' '450|0|0'
check_eq 'the files outside the list stay' yes "$([ -f "$H/.cache/b" ] && echo yes || echo no)"

mk_tree
apply 'clean_apply /etc /dev/null < <(printf "5 /etc/hostname\0"); a=$?; clean_apply "$HOME" /dev/null < <(clean_scan "$HOME/.cache" 0 0); b=$?; printf "<<%s %s>>" $a $b'
value_of 'a root that is not allowed: status 1 and nothing removed' '1 1'
check_eq 'nothing was removed' yes "$([ -f "$H/.cache/b" ] && echo yes || echo no)"

mk_tree
apply 'clean_apply "$HOME/.cache" /dev/null < <(clean_scan "$HOME/.cache" 30 0); printf "<<%s|%s>>" "$CLEAN_FILES" "$CLEAN_BYTES"'
value_of 'with a limit only the old file goes' '1|100'
check_eq 'the new ones stay' 'yes yes' "$([ -f "$H/.cache/a/two" ] && echo -n 'yes ' || echo -n 'no '; [ -f "$H/.cache/b" ] && echo yes || echo no)"
check_eq 'a folder that still has files stays' yes "$([ -d "$H/.cache/a" ] && echo yes || echo no)"

echo "-- The engine: dry run and depth (for P.4b)"
mk_tree
app_eval 'CLEAN_DRY=1 clean_apply "$HOME/.cache" /dev/null < <(clean_scan "$HOME/.cache" 0 0); printf "<<%s|%s|%s|%s>>" "$CLEAN_FILES" "$CLEAN_BYTES" "$CLEAN_SKIPPED" "$CLEAN_FAILED"'
value_of 'a dry run counts what it would remove, as the real one does' "5|$EXP|0|0"
check_eq 'a dry run removes nothing: files, links and the empty folder are all there' 7 "$(find "$H/.cache" -mindepth 1 | wc -l)"
printf '%s\n' "$H/.cache/b" > "$SB/state/open.txt"; sandbox_chown
app_eval "CLEAN_DRY=1 clean_apply \"\$HOME/.cache\" '$SB/state/open.txt' < <(clean_scan \"\$HOME/.cache\" 0 0); printf '<<%s|%s>>' \"\$CLEAN_FILES\" \"\$CLEAN_SKIPPED\""
value_of 'a dry run skips what is in use, as the real one does' '4|1'
app_eval 'CLEAN_DEPTH=1 clean_scan "$HOME/.cache" 0 0 | tr "\0" "\n" | cut -d" " -f2- | sed "s|$HOME|@|" | sort | paste -sd"|"'
check_eq 'CLEAN_DEPTH=1: only what is right under the folder' '@/.cache/b|@/.cache/dlink|@/.cache/link' "$OUT"
for depth in abc 0 -1 1000 ''; do
    app_eval 'clean_scan "$HOME/.cache" 0 0 | tr "\0" "\n" | wc -l' CLEAN_DEPTH="$depth"
    check_eq "CLEAN_DEPTH='$depth' is no limit" 5 "$OUT"
done

echo "-- Entries of the user: where they work (clean_places)"
rm -rf "$H/.local" "$H/.cache" "$H/.thumbnails" "$H/.var" "$H/snap"; mkdir -p "$H"
places() {  # places LABEL EXPECTED ID LEVEL [VAR=val ...]: "ROOT|OWN|PRUNE|DEPTH|tests", places joined by ";" (@ = home)
    local label="$1" expected="$2" id="$3" level="$4"; shift 4
    app_eval "clean_places $id $level; printf '%s\\n' \${CLEAN_PLACES[@]+\"\${CLEAN_PLACES[@]}\"} | tr '\\037' '|' | sed \"s|\$HOME|@|g\" | paste -sd';'" "$@"
    check_eq "$label" "$expected" "$OUT"
}
places 'no folders, no places' '' recent C
mkdir -p "$H/.local/share"; sandbox_chown
places 'recent: only the places that exist' '@/.local/share|1|0|1|-name|recently-used.xbel*' recent C
mkdir -p "$H/.local/share/RecentDocuments"; sandbox_chown
places 'recent: both' '@/.local/share|1|0|1|-name|recently-used.xbel*;@/.local/share/RecentDocuments|1|0|0|-name|*.desktop' recent S
mkdir -p "$H/.local/share/Trash/files" "$H/.local/share/Trash/info" "$H/.local/share/Trash/expunged"; sandbox_chown
places 'trash: files, info, expunged and the cache of sizes' \
    '@/.local/share/Trash/files|0|1|0;@/.local/share/Trash/info|0|0|0|-name|*.trashinfo;@/.local/share/Trash/expunged|0|1|0;@/.local/share/Trash|0|0|1|-name|directorysizes' trash C
mkdir -p "$H/.cache/thumbnails" "$H/.thumbnails" "$SB/outside"; sandbox_chown
places 'thumbnails: the cache and the old folder' '@/.cache/thumbnails|1|1|0;@/.thumbnails|1|1|0' thumbnails S
places 'thumbnails: with XDG_CACHE_HOME elsewhere, the folder that does not exist is no place' '@/.thumbnails|1|1|0' thumbnails S XDG_CACHE_HOME="$H/xdg"
mkdir -p "$H/xdg/thumbnails"; sandbox_chown
places 'thumbnails: XDG_CACHE_HOME moves the cache' '@/xdg/thumbnails|1|1|0;@/.thumbnails|1|1|0' thumbnails S XDG_CACHE_HOME="$H/xdg"
mkdir -p "$SB/outside/thumbnails"; sandbox_chown
places 'a cache folder outside the home folder is not a place' '@/.thumbnails|1|1|0' thumbnails S XDG_CACHE_HOME="$SB/outside"
rm -rf "$H/.cache/thumbnails"; ln -s "$SB/outside/thumbnails" "$H/.cache/thumbnails"; sandbox_chown
places 'a place that is a link to a folder is left out' '@/.thumbnails|1|1|0' thumbnails S
rm -f "$H/.cache/thumbnails"
places 'an entry that does not work on files: status 1, no places' '' clipboard S
app_eval 'clean_places clipboard S; echo "st=$?"'
check_eq 'clean_places: status 1 for the clipboard' 'st=1' "$OUT"
app_eval 'clean_places nothing S; echo "st=$?"'
check_eq 'clean_places: status 1 for an entry that does not exist' 'st=1' "$OUT"

echo "-- Entries of the user: measure and run (clean_item)"
rm -f "$H/open.txt"
it() {  # it LABEL EXPECTED MODE ID LEVEL [VAR=val ...]: <<files|bytes|skipped|failed|state|note>>
    local label="$1" expected="$2" mode="$3" id="$4" level="$5"; shift 5
    app_eval "clean_item $mode $id $level; printf '<<%s|%s|%s|%s|%s|%s>>' \"\$CLEAN_ITEM_FILES\" \"\$CLEAN_ITEM_BYTES\" \"\$CLEAN_ITEM_SKIPPED\" \"\$CLEAN_ITEM_FAILED\" \"\$CLEAN_ITEM_STATE\" \"\$CLEAN_ITEM_NOTE\"" "$@"
    value_of "$label" "$expected"
}
left() {  # left DIR: the files and links left under DIR, "@" for the home folder
    find "$1" \( -type f -o -type l \) 2>/dev/null | sed "s|$H|@|" | sort | paste -sd'|'
}
app_eval 'clean_item x recent S; echo "st=$?"'
check_eq 'clean_item: a mode that does not exist is status 2' 'st=2' "$OUT"
app_eval 'clean_item run nothing S; echo "st=$?"'
check_eq 'clean_item: an entry that does not exist is status 2' 'st=2' "$OUT"

rm -rf "$H/.local" "$H/.cache" "$H/.thumbnails" "$H/.var" "$H/snap" "$H/xdg"
fake_file "$H/.local/share/recently-used.xbel" 100
fake_file "$H/.local/share/recently-used.xbel.AB12" 10
fake_file "$H/.local/share/other.txt" 50
fake_file "$H/.local/share/sub/recently-used.xbel" 7
fake_file "$H/.local/share/RecentDocuments/a.desktop" 20
fake_file "$H/.local/share/RecentDocuments/b.txt" 5
BEFORE="$(left "$H/.local")"
it 'recent, measure: the list of the desktop, its temporary copy and the KDE launchers' '3|130|0|0|ok|' measure recent S
check_eq 'recent, measure: nothing was removed' "$BEFORE" "$(left "$H/.local")"
it 'recent, run' '3|130|0|0|ok|' run recent C
check_eq 'recent, run: only those; a file with another name, and the same name deeper, stay' \
    '@/.local/share/RecentDocuments/b.txt|@/.local/share/other.txt|@/.local/share/sub/recently-used.xbel' "$(left "$H/.local")"

rm -rf "$H/.local"
fake_file "$H/.local/share/Trash/files/a" 10
fake_file "$H/.local/share/Trash/files/dir/b" 20
fake_file "$H/.local/share/Trash/info/a.trashinfo" 5
fake_file "$H/.local/share/Trash/info/keep.txt" 3
fake_file "$H/.local/share/Trash/expunged/x" 7
fake_file "$H/.local/share/Trash/directorysizes" 4
it 'trash, measure: files, their records, the expunged and the cache of sizes' '5|46|0|0|ok|' measure trash C
it 'trash, run' '5|46|0|0|ok|' run trash C
check_eq 'trash, run: only a file that is not of the trash is left' '@/.local/share/Trash/info/keep.txt' "$(left "$H/.local")"
check_eq 'trash, run: the folders of the trash stay, the ones inside go' 'yes no' "$([ -d "$H/.local/share/Trash/files" ] && echo -n 'yes ' || echo -n 'no '; [ -d "$H/.local/share/Trash/files/dir" ] && echo yes || echo no)"

rm -rf "$H/.local"
fake_file "$H/.cache/thumbnails/large/a.png" 100
fake_file "$H/.cache/thumbnails/normal/b.png" 200
fake_file "$H/.thumbnails/c.png" 50
fake_file "$H/.cache/other/z" 9
it 'thumbnails, measure' '3|350|0|0|ok|' measure thumbnails S
it 'thumbnails, run' '3|350|0|0|ok|' run thumbnails S
check_eq 'thumbnails, run: the rest of the cache stays' '@/.cache/other/z' "$(left "$H")"
check_eq 'thumbnails, run: the folders stay' 'yes yes' "$([ -d "$H/.cache/thumbnails" ] && echo -n 'yes ' || echo -n 'no '; [ -d "$H/.thumbnails" ] && echo yes || echo no)"

rm -rf "$H/.cache" "$H/.thumbnails"
fake_file "$H/.cache/foo/a" 100; fake_age "$H/.cache/foo/a" 40
fake_file "$H/.cache/foo/b" 200
fake_file "$H/.cache/thumbnails/t" 10; fake_age "$H/.cache/thumbnails/t" 40
fake_file "$H/.cache/mozilla/firefox/p/cache2/c" 30; fake_age "$H/.cache/mozilla/firefox/p/cache2/c" 40
fake_file "$H/.cache/chromium/Default/x" 40; fake_age "$H/.cache/chromium/Default/x" 40
fake_file "$H/.cache/BraveSoftware/Brave-Browser/y" 5; fake_age "$H/.cache/BraveSoftware/Brave-Browser/y" 40
fake_file "$H/.cache/misc" 1; fake_age "$H/.cache/misc" 40
it 'cache, simple level, measure: only what is not used for 30 days; the thumbnails and the browsers have their own entries' '2|101|0|0|ok|' measure cache S
it 'cache, complete level, measure: all of it except those' '3|301|0|0|ok|' measure cache C
printf '%s\n' "$H/.cache/foo/b" > "$SB/state/open.txt"; sandbox_chown
app_eval "CLEAN_OPENFILE='$SB/state/open.txt'; clean_item measure cache C; printf '<<%s|%s|%s>>' \"\$CLEAN_ITEM_FILES\" \"\$CLEAN_ITEM_BYTES\" \"\$CLEAN_ITEM_SKIPPED\""
value_of 'cache, complete level: what a process has open is skipped' '2|101|1'
it 'cache, simple level, run' '2|101|0|0|ok|' run cache S
check_eq 'cache, simple level, run: the new file and what belongs to other entries stay' \
    '@/.cache/BraveSoftware/Brave-Browser/y|@/.cache/chromium/Default/x|@/.cache/foo/b|@/.cache/mozilla/firefox/p/cache2/c|@/.cache/thumbnails/t' "$(left "$H")"
it 'cache, complete level, run: the rest goes' '1|200|0|0|ok|' run cache C
check_eq 'cache, complete level, run: still not those of other entries' \
    '@/.cache/BraveSoftware/Brave-Browser/y|@/.cache/chromium/Default/x|@/.cache/mozilla/firefox/p/cache2/c|@/.cache/thumbnails/t' "$(left "$H")"
it 'cache, with XDG_CACHE_HOME elsewhere in the home: that one is the cache' '0|0|0|0|ok|' measure cache C XDG_CACHE_HOME="$H/xdg"

rm -rf "$H/.cache"
fake_file "$H/.cache/mozilla/firefox/p/cache2/entries/a" 100
fake_file "$H/.cache/chromium/Default/Cache/b" 200
fake_file "$H/.cache/google-chrome/x" 50
fake_file "$H/snap/firefox/common/.cache/mozilla/firefox/q/c" 30
fake_file "$H/.cache/thunderbird/t" 10
fake_file "$H/.cache/other/o" 1
it 'browsers, none open: the caches of all of them, the snap one too' '5|390|0|0|ok|' measure browsers S
it 'browsers: the same in the complete level (no limits)' '5|390|0|0|ok|' measure browsers C
cp "$(command -v sleep)" "$SB/bin/firefox"; chmod 755 "$SB/bin/firefox"
"$SB/bin/firefox" 120 & FFPID=$!
it 'browsers, Firefox open: its cache (and the snap one) is left out and named; the others are cleaned' '3|260|0|0|ok|Firefox' run browsers C
kill "$FFPID" 2>/dev/null || true; wait "$FFPID" 2>/dev/null || true
check_eq 'browsers, Firefox open: its cache stays, the others are gone' '@/.cache/mozilla/firefox/p/cache2/entries/a|@/.cache/other/o|@/snap/firefox/common/.cache/mozilla/firefox/q/c' "$(left "$H")"
it 'browsers, Firefox closed again: now it is cleaned' '2|130|0|0|ok|' run browsers C
cp "$(command -v sleep)" "$SB/bin/chromium-browse"; chmod 755 "$SB/bin/chromium-browse"
fake_file "$H/.cache/chromium/Default/Cache/b" 200; fake_file "$H/.cache/thunderbird/t" 10
"$SB/bin/chromium-browse" 120 & CRPID=$!
it 'browsers, Chromium open (its name is cut at 15 characters): left out' '1|10|0|0|ok|Chromium' measure browsers S
kill "$CRPID" 2>/dev/null || true; wait "$CRPID" 2>/dev/null || true
rm -f "$SB/bin/firefox" "$SB/bin/chromium-browse"
app_eval 'clean_running firefox; echo "st=$?"'
check_eq 'clean_running: no process with that name' 'st=1' "$OUT"
app_eval 'clean_running bash sh; echo "st=$?"'
check_eq 'clean_running: one of the names runs (the shell of the test)' 'st=0' "$OUT"

rm -rf "$H/.var" "$H/snap" "$H/.cache"
fake_file "$H/.var/app/org.x.App/cache/a" 100
fake_file "$H/.var/app/org.x.App/data/keep" 50
fake_file "$H/.var/app/org.y.App/cache/sub/b" 200; fake_age "$H/.var/app/org.y.App/cache/sub/b" 40
fake_file "$H/snap/foo/common/.cache/z" 30
fake_file "$H/snap/foo/common/data/k" 7
it 'app caches, complete level: the cache folders of Flatpak and Snap apps, not their data' '3|330|0|0|ok|' measure app_caches C
it 'app caches, simple level: only what is not used for 30 days' '1|200|0|0|ok|' measure app_caches S
it 'app caches, run' '3|330|0|0|ok|' run app_caches C
check_eq 'app caches, run: their data stays' '@/.var/app/org.x.App/data/keep|@/snap/foo/common/data/k' "$(left "$H")"
check_eq 'the entries of the user never ask for administrator rights (sudo was not called)' '' "$(sudo_log)"

if [ "$(id -u)" -eq 0 ]; then
    rm -rf "$H/.cache" "$H/.local" "$H/.var" "$H/snap" "$H/.thumbnails"
    fake_file "$H/.cache/mine" 10; fake_file "$H/.cache/rootfile" 20
    fake_file "$H/.local/share/recently-used.xbel" 5; fake_file "$H/.local/share/recently-used.xbel.r" 6
    fake_file "$H/.thumbnails/mine" 3; fake_file "$H/.thumbnails/theirs" 4
    # (fake_file gives everything to the user of the program: the files of someone else come last)
    chown 0:0 "$H/.cache/rootfile" "$H/.local/share/recently-used.xbel.r" "$H/.thumbnails/theirs"
    it 'cache: a file of someone else is not listed (only the files of the user)' '1|10|0|0|ok|' measure cache C
    it 'recent: a file of someone else is not listed' '1|5|0|0|ok|' measure recent C
    it 'thumbnails: a file of someone else is not listed' '1|3|0|0|ok|' measure thumbnails C
    rm -rf "$H/.cache" "$H/.local" "$H/.thumbnails"
fi

echo "-- Names of processes and patterns of find"
app_eval 'clean_running ash; echo "st=$?"'
check_eq 'clean_running: the whole name, not a part of it (the test runs under bash)' 'st=1' "$OUT"
app_eval 'clean_glob "a*b?c[d]e\\f"; echo'
check_eq 'clean_glob: the characters of a pattern are escaped' 'a\*b\?c\[d\]e\\f' "$OUT"
app_eval 'clean_glob "/home/ana/.cache"; echo'
check_eq 'clean_glob: an ordinary path stays as it is' '/home/ana/.cache' "$OUT"

echo "-- Temporary files (tmp): in folders of the sandbox, never /tmp itself"
# The real /tmp must not be touched by a test: a copy of the program with the temporary folders in the sandbox.
sed -e 's/^readonly CLEAN_SYSTEM_ROOTS$/true/' "$H_SCRIPT" > "$SB/prog.sh"; chmod 644 "$SB/prog.sh"; sandbox_chown
H_SCRIPT_REAL="$H_SCRIPT"; H_SCRIPT="$SB/prog.sh"
T1="$SB/tmp1"; T2="$SB/tmp2"
TMPENV="CLEAN_SYSTEM_ROOTS=(\"$T1\" \"$T2\"); CLEAN_TMP_DIRS=(\"$T1\" \"$T2\")"
tit() {  # tit LABEL EXPECTED MODE LEVEL: like it, for tmp, with the temporary folders of the sandbox
    local label="$1" expected="$2" mode="$3" level="$4"
    app_eval "$TMPENV; clean_item $mode tmp $level; printf '<<%s|%s|%s|%s|%s>>' \"\$CLEAN_ITEM_FILES\" \"\$CLEAN_ITEM_BYTES\" \"\$CLEAN_ITEM_SKIPPED\" \"\$CLEAN_ITEM_FAILED\" \"\$CLEAN_ITEM_STATE\""
    value_of "$label" "$expected"
}
rm -rf "$T1" "$T2"
fake_file "$T1/new.txt" 10
fake_file "$T1/old.txt" 20; fake_age "$T1/old.txt" 10
fake_file "$T1/dir/old2" 30; fake_age "$T1/dir/old2" 10
fake_file "$T2/v" 40; fake_age "$T2/v" 10
fake_file "$T1/.X0-lock" 5; fake_age "$T1/.X0-lock" 10
fake_file "$T1/app.lock" 5; fake_age "$T1/app.lock" 10
fake_file "$T1/app.pid" 5; fake_age "$T1/app.pid" 10
fake_file "$T1/ssh-abc/agent" 5; fake_age "$T1/ssh-abc/agent" 10
fake_file "$T1/.ICE-unix/x" 5; fake_age "$T1/.ICE-unix/x" 10
fake_file "$T1/systemd-private-1/y" 5; fake_age "$T1/systemd-private-1/y" 10
fake_file "$T1/.mount_App/z" 5; fake_age "$T1/.mount_App/z" 10
fake_file "$T1/dbus-q/w" 5; fake_age "$T1/dbus-q/w" 10
mkdir -p "$T1/emptydir"; fake_age "$T1/emptydir" 10; sandbox_chown
tit 'tmp, simple level: what is older than 7 days, in both folders, and not the files of the session' '3|90|0|0|ok' measure S
if [ "$(id -u)" -eq 0 ]; then
    : > "$T1/theirs"; chown 0:0 "$T1/theirs"; fake_age "$T1/theirs" 10
    tit 'tmp: a file of someone else is not listed (only the files of the user)' '3|90|0|0|ok' measure S
    rm -f "$T1/theirs"
fi
tit 'tmp, complete level: all of it, but still not the files of the session' '4|100|0|0|ok' measure C
tit 'tmp, simple level, run' '3|90|0|0|ok' run S
check_eq 'tmp, simple level: the new file and every file of the session stay' \
    '@/tmp1/.ICE-unix/x|@/tmp1/.X0-lock|@/tmp1/.mount_App/z|@/tmp1/app.lock|@/tmp1/app.pid|@/tmp1/dbus-q/w|@/tmp1/new.txt|@/tmp1/ssh-abc/agent|@/tmp1/systemd-private-1/y' "$(find "$T1" \( -type f -o -type l \) | sed "s|$SB|@|" | sort | paste -sd'|')"
check_eq 'tmp, simple level: an empty folder older than 7 days goes (only with an age limit)' 'no' "$([ -d "$T1/emptydir" ] && echo yes || echo no)"
mkdir -p "$T1/newempty"; sandbox_chown
tit 'tmp, complete level, run' '1|10|0|0|ok' run C
check_eq 'tmp, complete level: an empty folder stays (a program may have just made it)' 'yes' "$([ -d "$T1/newempty" ] && echo yes || echo no)"
# The folders are the real ones in the program as it comes.
app_eval 'printf "<<%s>>" "${CLEAN_TMP_DIRS[*]}"'
H_SCRIPT="$H_SCRIPT_REAL"
value_of 'the temporary folders of the program: /tmp and /var/tmp' '/tmp /var/tmp'

echo "-- The X11 errors (x11_logs)"
rm -rf "$H/.cache" "$H/.var" "$H/snap"; rm -f "$H"/.xsession-errors*
fake_file "$H/.xsession-errors" 500
fake_file "$H/.xsession-errors.old" 300
it 'x11 errors, measure: both files' '2|800|0|0|ok|' measure x11_logs C
check_eq 'x11 errors, measure: nothing changed' '500 300' "$(stat -c %s "$H/.xsession-errors") $(stat -c %s "$H/.xsession-errors.old")"
it 'x11 errors, run' '2|800|0|0|ok|' run x11_logs C
check_eq 'x11 errors, run: the current one is emptied (the session has it open), the old one is gone' '0 no' "$(stat -c %s "$H/.xsession-errors") $([ -e "$H/.xsession-errors.old" ] && echo yes || echo no)"
it 'x11 errors, already empty: nothing to do' '0|0|0|0|ok|' run x11_logs C
rm -f "$H"/.xsession-errors*; mkdir -p "$SB/outside"; echo secret > "$SB/outside/real"; ln -s "$SB/outside/real" "$H/.xsession-errors"; sandbox_chown
it 'x11 errors, a link: left alone' '0|0|0|0|ok|' run x11_logs C
check_eq 'x11 errors, a link: what it points to is untouched' 'secret' "$(cat "$SB/outside/real")"
if [ "$(id -u)" -eq 0 ]; then
    rm -f "$H/.xsession-errors"; echo other > "$H/.xsession-errors"
    it 'x11 errors, a file of someone else: left alone' '0|0|0|0|ok|' run x11_logs C
    check_eq 'x11 errors, a file of someone else: untouched' 'other' "$(cat "$H/.xsession-errors")"
fi
rm -f "$H"/.xsession-errors*

echo "-- The clipboard"
rm -f "$SB/state/clip.log"
for t in xsel xclip wl-copy gpaste-client; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/state/clip.log"\nexit "${FAKE_CLIP_RC:-0}"\n' "$t" "$SB" > "$SB/bin/$t"; chmod 755 "$SB/bin/$t"
done
# dbus-send: says which names of the bus "run" (FAKE_BUS_NAMES) and logs the calls that are not that question.
cat > "$SB/bin/dbus-send" <<STUB
#!/bin/sh
case "\$*" in
    *NameHasOwner*)
        for n in \$FAKE_BUS_NAMES; do case "\$*" in *"string:\$n"*) echo "   boolean true"; exit 0;; esac; done
        echo "   boolean false"; exit 0 ;;
esac
echo "dbus-send \$*" >> "$SB/state/clip.log"
exit "\${FAKE_CLIP_RC:-0}"
STUB
chmod 755 "$SB/bin/dbus-send"; sandbox_chown
clip() {  # clip LABEL EXPECTED_STATE_AND_NOTE EXPECTED_LOG MODE [VAR=val ...]: the result and the calls the tools got
    local label="$1" expected="$2" log="$3" mode="$4"; shift 4
    : > "$SB/state/clip.log"; sandbox_chown
    app_eval "clean_item $mode clipboard S; printf '<<%s|%s|%s>>' \"\$CLEAN_ITEM_STATE\" \"\$CLEAN_ITEM_NOTE\" \"\$CLEAN_ITEM_FAILED\"" "$@"
    value_of "$label: result" "$expected"
    check_eq "$label: calls" "$log" "$(paste -sd'|' < "$SB/state/clip.log")"
}
clip 'X11 with xsel: both selections are emptied' 'ok|xsel|0' 'xsel --clipboard --clear|xsel --primary --clear' run DISPLAY=:0
clip 'X11, measure: the tool is named, nothing runs' 'ok|xsel|0' '' measure DISPLAY=:0
# Without the xsel stub the program would still find a real xsel on a machine that has one, so this case
# gets a PATH of its own: the system commands, minus the clipboard tools (the stubs are in $SB/bin).
NOX="$SB/nox"; mkdir -p "$NOX"
for d in /usr/local/bin /usr/bin /bin; do
    for f in "$d"/*; do
        [ -f "$f" ] && [ -x "$f" ] || continue
        case "${f##*/}" in xsel|xclip|wl-copy|gpaste-client) continue ;; esac
        [ -e "$NOX/${f##*/}" ] || ln -s "$f" "$NOX/${f##*/}"
    done
done
sandbox_chown
mv "$SB/bin/xsel" "$SB/xsel.off"
clip 'X11 without xsel: xclip, with an empty input' 'ok|xclip|0' 'xclip -selection clipboard -in|xclip -selection primary -in' run DISPLAY=:0 PATH="$SB/bin:$NOX"
mv "$SB/xsel.off" "$SB/bin/xsel"
clip 'X11 with both: only xsel (they do the same)' 'ok|xsel|0' 'xsel --clipboard --clear|xsel --primary --clear' run DISPLAY=:0
clip 'Wayland: wl-copy, both selections' 'ok|wl-copy|0' 'wl-copy --clear|wl-copy --primary --clear' run WAYLAND_DISPLAY=wayland-0
clip 'X11 and Wayland at once (XWayland): the tool of each' 'ok|xsel, wl-copy|0' 'xsel --clipboard --clear|xsel --primary --clear|wl-copy --clear|wl-copy --primary --clear' run DISPLAY=:0 WAYLAND_DISPLAY=wayland-0
clip 'no session, no tool that applies: unavailable' 'unavailable||0' '' run
clip 'GPaste running: its history is emptied too' 'ok|xsel, GPaste|0' 'xsel --clipboard --clear|xsel --primary --clear|gpaste-client empty' run DISPLAY=:0 FAKE_BUS_NAMES=org.gnome.GPaste2
clip 'GPaste of the old name' 'ok|GPaste|0' 'gpaste-client empty' run FAKE_BUS_NAMES=org.gnome.GPaste
clip 'Klipper running: its history is emptied' 'ok|Klipper|0' 'dbus-send --session --type=method_call --dest=org.kde.klipper /klipper org.kde.klipper.klipper.clearClipboardHistory' run FAKE_BUS_NAMES=org.kde.klipper
clip 'GPaste installed but not running: not started' 'unavailable||0' '' run
clip 'a tool that fails: one failure, and the state is not unavailable' 'ok|xsel|1' 'xsel --clipboard --clear|xsel --primary --clear' run DISPLAY=:0 FAKE_CLIP_RC=1
rm -f "$SB/bin/xsel" "$SB/bin/xclip" "$SB/bin/wl-copy" "$SB/bin/gpaste-client" "$SB/bin/dbus-send"

echo "-- Entries that need administrator rights (P.4c): in folders of the sandbox, never /var itself"
# A copy of the program that lets the tests give it the folders of the sandbox in place of /var/...
sed -e 's/^readonly CLEAN_SYSTEM_ROOTS$/true/' "$H_SCRIPT" > "$SB/prog.sh"; chmod 644 "$SB/prog.sh"; sandbox_chown
H_SCRIPT_REAL="$H_SCRIPT"; H_SCRIPT="$SB/prog.sh"
LOG="$SB/var/log"; CR1="$SB/var/crash"; CR2="$SB/var/coredump"; APTD="$SB/var/cache/apt"
ADM="CLEAN_SYSTEM_ROOTS=(\"$LOG\" \"$CR1\" \"$CR2\" \"$APTD\"); CLEAN_LOG_DIR=\"$LOG\"; CLEAN_CRASH_DIRS=(\"$CR1\" \"$CR2\"); CLEAN_APT_DIR=\"$APTD\"; CLEAN_APT_LOCKS=(\"$APTD/archives/lock\")"
ait() {  # ait LABEL EXPECTED MODE ID LEVEL [SETUP]: like it, in those folders; the setup code runs first
    local label="$1" expected="$2" mode="$3" id="$4" level="$5" setup="${6-}"
    app_eval "$ADM; $setup clean_item $mode $id $level; printf '<<%s|%s|%s|%s|%s|%s>>' \"\$CLEAN_ITEM_FILES\" \"\$CLEAN_ITEM_BYTES\" \"\$CLEAN_ITEM_SKIPPED\" \"\$CLEAN_ITEM_FAILED\" \"\$CLEAN_ITEM_STATE\" \"\$CLEAN_ITEM_NOTE\""
    value_of "$label" "$expected"
}
sudo_calls() { sudo_log | sed "s|$SB|@|g"; }
reset_sudo() { : > "$SB/state/sudo.log"; sandbox_chown; }

rm -rf "${SB:?}/var"
fake_file "$LOG/syslog" 100
fake_file "$LOG/syslog.1" 200; fake_age "$LOG/syslog.1" 3
fake_file "$LOG/syslog.2.gz" 300; fake_age "$LOG/syslog.2.gz" 10
fake_file "$LOG/auth.log.10" 50; fake_age "$LOG/auth.log.10" 10
fake_file "$LOG/kern.log-20260101" 40; fake_age "$LOG/kern.log-20260101" 10
fake_file "$LOG/dpkg.log.old" 30; fake_age "$LOG/dpkg.log.old" 10
fake_file "$LOG/x.xz" 20; fake_age "$LOG/x.xz" 10
fake_file "$LOG/y.bz2" 10; fake_age "$LOG/y.bz2" 10
fake_file "$LOG/z.zst" 5; fake_age "$LOG/z.zst" 10
fake_file "$LOG/apt/history.log.1.gz" 60; fake_age "$LOG/apt/history.log.1.gz" 10
fake_file "$LOG/app.log" 7; fake_age "$LOG/app.log" 10
fake_file "$LOG/weird.1x" 9; fake_age "$LOG/weird.1x" 10
fake_file "$LOG/journal/abc/system@1.journal" 1000; fake_age "$LOG/journal/abc/system@1.journal" 10
fake_file "$LOG/journal/abc/system@9.journal.old" 77; fake_age "$LOG/journal/abc/system@9.journal.old" 10
reset_sudo
# The rotated logs are the files of root: they have to be listed (the removal is the one that needs the rights).
if [ "$(id -u)" -eq 0 ]; then chown 0:0 "$LOG/syslog.2.gz" "$LOG/apt/history.log.1.gz"; fi
ait 'rotated logs, simple level, measure: the rotated ones older than 7 days, in subfolders too' '8|515|0|0|ok|' measure rotated_logs S
ait 'rotated logs, complete level, measure: all the rotated ones' '9|715|0|0|ok|' measure rotated_logs C
check_eq 'rotated logs, measure: it needs no administrator rights, sudo was not called' '' "$(sudo_calls)"
ait 'rotated logs, simple level, run' '8|515|0|0|ok|' run rotated_logs S
check_eq 'rotated logs, run: one removal with administrator rights, of those files only' \
    '1' "$(sudo_calls | grep -c '^sudo rm -f -- ')"
check_eq 'rotated logs, run: the list of the removal has the 8 files' '8' "$(sudo_calls | tr ' ' '\n' | grep -c '^@/var/log/')"
check_eq 'rotated logs, run: the live log, the new rotated one, the journal and other names stay' \
    '@/var/log/app.log|@/var/log/journal/abc/system@1.journal|@/var/log/journal/abc/system@9.journal.old|@/var/log/syslog|@/var/log/syslog.1|@/var/log/weird.1x' \
    "$(find "$LOG" \( -type f -o -type l \) | sed "s|$SB|@|" | sort | paste -sd'|')"
reset_sudo
ait 'rotated logs, run with the privileges denied: nothing goes and it is counted as failed' '0|0|0|1|ok|' run rotated_logs C 'priv_run() { return 1; };'
rm -rf "$LOG"; mkdir -p "$LOG"; sandbox_chown
( cd "$LOG" && seq 1 450 | sed 's/$/.gz/' | xargs touch ); sandbox_chown
reset_sudo
ait 'rotated logs: 450 files' '450|0|0|0|ok|' run rotated_logs C
check_eq 'rotated logs: the removal goes in batches of 200 (3 calls)' '3' "$(sudo_calls | grep -c '^sudo rm -f -- ')"

rm -rf "${SB:?}/var"
fake_file "$CR1/a.crash" 10
fake_file "$CR1/sub/b.crash" 20
fake_file "$CR2/core.1" 30
mkdir -p "$SB/outside"; ln -s "$SB/outside" "$CR1/linkdir"; sandbox_chown
reset_sudo
LINKSIZE=$(( ${#SB} + 8 ))     # a link weighs what its target text does: "$SB/outside"
ait 'crash reports: what is right in the folders (not deeper); a link to a folder is listed as a link' "3|$(( 40 + LINKSIZE ))|0|0|ok|" measure crash C
ait 'crash reports, run' "3|$(( 40 + LINKSIZE ))|0|0|ok|" run crash C
check_eq 'crash reports, run: what is deeper stays' \
    '@/var/crash/sub/b.crash' "$(find "$CR1" "$CR2" -type f | sed "s|$SB|@|" | sort | paste -sd'|')"
check_eq 'crash reports, run: where the link pointed is untouched' 'yes' "$([ -d "$SB/outside" ] && echo yes || echo no)"

rm -rf "${SB:?}/var"
fake_file "$APTD/archives/a.deb" 100
fake_file "$APTD/archives/b.deb" 200
fake_file "$APTD/archives/partial/c.part" 50
fake_file "$APTD/pkgcache.bin" 300
fake_file "$APTD/srcpkgcache.bin" 400
fake_file "$APTD/archives/lock" 0
fake_file "$APTD/archives/note.txt" 5
reset_sudo
ait 'apt cache, measure: the downloaded packages, the partial ones and the two caches of apt' '5|1050|0|0|ok|' measure apt_cache S
ait 'apt cache with another manager: unavailable' '0|0|0|0|unavailable|' measure apt_cache S 'PM=dnf;'
ait 'apt cache, run' '5|1050|0|0|ok|' run apt_cache C
check_eq 'apt cache, run: the lock and what is not of apt stay' '@/var/cache/apt/archives/lock|@/var/cache/apt/archives/note.txt' \
    "$(find "$APTD" -type f | sed "s|$SB|@|" | sort | paste -sd'|')"
fake_file "$APTD/archives/d.deb" 7
reset_sudo
hold_lock() { setsid flock "$1" sleep 30 & LOCKPID=$!; sleep 1; }
free_lock() { kill -TERM -- "-$LOCKPID" 2>/dev/null || true; wait "$LOCKPID" 2>/dev/null || true; sleep 0.3; }
hold_lock "$APTD/archives/lock"
ait 'apt cache while apt holds its lock: busy, nothing is removed' '0|0|0|0|busy|apt' run apt_cache C
check_eq 'apt cache busy: no removal was tried' '' "$(sudo_calls)"
free_lock
ait 'apt cache with the lock free again' '1|7|0|0|ok|' measure apt_cache C
app_eval 'printf "%s\n" "${CLEAN_APT_LOCKS[@]}"'
check_eq 'the files apt and dpkg lock while they work' $'/var/cache/apt/archives/lock\n/var/lib/dpkg/lock\n/var/lib/dpkg/lock-frontend' "$OUT"
app_eval "$ADM; clean_locked \"$APTD/archives/lock\"; echo \"st=\$?\""
check_eq 'clean_locked: a lock that is not held' 'st=1' "$OUT"
app_eval "$ADM; clean_locked \"$SB/nothing/here\"; echo \"st=\$?\""
check_eq 'clean_locked: a file that does not exist' 'st=1' "$OUT"
hold_lock "$APTD/archives/lock"
app_eval "$ADM; clean_locked \"$SB/nothing/here\" \"$APTD/archives/lock\"; echo \"st=\$?\""
check_eq 'clean_locked: a lock that is held, among other files' 'st=0' "$OUT"
free_lock

rm -rf "${SB:?}/var"
cat > "$SB/bin/journalctl" <<STUB
#!/bin/sh
echo "journalctl \$*" >> "$SB/state/journal.log"
[ -z "\${FAKE_JNOOP:-}" ] || exit 0
case "\$1" in
    --vacuum-size=1) find "$LOG/journal" -type f -name '*@*' -delete ;;
    --vacuum-time=*d) d=\${1#--vacuum-time=}; d=\${d%d}; find "$LOG/journal" -type f -name '*@*' -mtime "+\$d" -delete ;;
esac
exit "\${FAKE_JRC:-0}"
STUB
chmod 755 "$SB/bin/journalctl"; : > "$SB/state/journal.log"
mkjournal() {
    rm -rf "${SB:?}/var"
    fake_file "$LOG/journal/abc/system@1.journal" 1000; fake_age "$LOG/journal/abc/system@1.journal" 20
    fake_file "$LOG/journal/abc/system@2.journal~" 500; fake_age "$LOG/journal/abc/system@2.journal~" 3
    fake_file "$LOG/journal/abc/system.journal" 4000; fake_age "$LOG/journal/abc/system.journal" 1
    fake_file "$LOG/journal/abc/user-1000@3.journal" 200; fake_age "$LOG/journal/abc/user-1000@3.journal" 20
    fake_file "$LOG/syslog.1" 99; fake_age "$LOG/syslog.1" 20
    : > "$SB/state/journal.log"; reset_sudo
}
mkjournal
ait 'journal, simple level, measure: the archived files older than 14 days' '2|1200|0|0|ok|' measure journal S
ait 'journal, complete level, measure: all the archived ones; the one in use never' '3|1700|0|0|ok|' measure journal C
check_eq 'journal, measure: journalctl was not called' '' "$(cat "$SB/state/journal.log")"
ait 'journal, simple level, run: what the vacuum took away' '2|1200|0|0|ok|' run journal S
check_eq 'journal, simple level: journalctl with the days, with administrator rights' 'sudo journalctl --vacuum-time=14d' "$(sudo_calls)"
mkjournal
ait 'journal, complete level, run' '3|1700|0|0|ok|' run journal C
check_eq 'journal, complete level: all that is archived' 'sudo journalctl --vacuum-size=1' "$(sudo_calls)"
check_eq 'journal, run: the file in use and the log that is not of the journal stay' \
    '@/var/log/journal/abc/system.journal|@/var/log/syslog.1' "$(find "$LOG" -type f | sed "s|$SB|@|" | sort | paste -sd'|')"
mkjournal
ait 'journal, run when journalctl fails: one failure, and the freed size is what really went' '2|1200|0|1|ok|' run journal S 'export FAKE_JRC=3;'
mkjournal
ait 'journal, run when the vacuum frees nothing: nothing is counted as freed' '0|0|0|0|ok|' run journal C 'export FAKE_JNOOP=1;'
ait 'journal without journalctl: unavailable' '0|0|0|0|unavailable|' measure journal S 'command() { if [ "$1" = -v ] && [ "$2" = journalctl ]; then return 1; fi; builtin command "$@"; };'
rm -f "$SB/bin/journalctl"

echo "-- Residual configuration of packages (rc_config)"
H_SCRIPT="$H_SCRIPT_REAL"
new_sandbox
fake_installed pkg1 pkg2 vim; fake_configfiles pkg1 pkg2
rcit() {  # rcit LABEL EXPECTED MODE [CODE BEFORE]: <<files|bytes|failed|state|note>> of clean_item for rc_config
    local label="$1" expected="$2" mode="$3" setup="${4-}"
    app_eval "$setup clean_item $mode rc_config C; printf '<<%s|%s|%s|%s|%s>>' \"\$CLEAN_ITEM_FILES\" \"\$CLEAN_ITEM_BYTES\" \"\$CLEAN_ITEM_FAILED\" \"\$CLEAN_ITEM_STATE\" \"\$CLEAN_ITEM_NOTE\""
    value_of "$label" "$expected"
}
rcit 'residual configuration, measure: the packages, no size' '2|0|0|ok|' measure
app_eval 'clean_item measure rc_config C; printf "%s" "$CLEAN_ITEM_WHERE"'
assert_contains 'residual configuration, measure: the plan of the manager is what it shows' "$OUT" 'Purg pkg1'
app_eval 'clean_item measure rc_config C; printf "%s" "$CLEAN_RC_PLAN"'
assert_contains 'residual configuration, measure: it keeps the plan to check it when it runs' "$OUT" 'Purg pkg2'
check_eq 'residual configuration, measure: nothing was purged (only simulated)' 'no' "$(apt_log | grep -q 'purge -y' && echo yes || echo no)"
check_eq 'residual configuration, measure: no administrator rights' '' "$(sudo_log)"
rcit 'residual configuration, run after measuring: the plan is the same and the packages are purged' '2|0|0|ok|' run 'clean_item measure rc_config C;'
check_eq 'residual configuration, run: apt purge, with administrator rights and the two names' 'sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y pkg1 pkg2' "$(sudo_log)"
check_eq 'residual configuration, run: no package keeps its configuration' '' "$(printf '%s\n' pkg1 pkg2 | grep -xFf "$SB/state/configfiles" || true)"
new_sandbox
fake_installed pkg1 pkg2 vim; fake_configfiles pkg1 pkg2
rcit 'residual configuration, the plan changed after measuring: nothing is purged, both count as failed' '0|0|2|ok|changed' run "CLEAN_RC_PLAN='Purg other [1]';"
check_eq 'residual configuration, the plan changed: apt purge was not run' 'no' "$(apt_log | grep -q 'purge -y' && echo yes || echo no)"
app_eval 'clean_item measure rc_config C; printf "pkg3\n" >> "$HOME/../state/installed"; printf "pkg3\n" >> "$HOME/../state/configfiles"; clean_item run rc_config C; printf "<<%s|%s|%s>>" "$CLEAN_ITEM_FILES" "$CLEAN_ITEM_FAILED" "$CLEAN_ITEM_NOTE"'
value_of 'residual configuration: a package that appears between measuring and running changes the plan: nothing is purged' '0|3|changed'
new_sandbox
fake_installed pkg1 pkg2 vim; fake_configfiles pkg1 pkg2
rcit 'residual configuration, run without measuring first: it takes its own plan' '2|0|0|ok|' run
new_sandbox
fake_installed vim
new_sandbox
fake_installed pkg1 pkg2 vim; fake_configfiles pkg1 pkg2
rcit 'residual configuration, apt fails to purge: nothing counts as cleaned, and both as failed' '0|0|2|ok|' run 'export FAKE_APT_FAIL=100;'
new_sandbox
fake_installed pkg1 vim BADNAME; fake_configfiles pkg1 BADNAME
rcit 'residual configuration: a name that is not valid for the manager is left out' '1|0|0|ok|' measure
new_sandbox
fake_installed vim
rcit 'residual configuration, none: nothing to do' '0|0|0|ok|' run
fake_installed pkg1; fake_configfiles pkg1
rcit 'residual configuration, apt fails to simulate: one failure per package and its first line' '0|0|1|ok|E: Unable to locate package pkg1' measure 'export FAKE_APT_SIM_FAIL=1;'
rcit 'residual configuration with another manager: unavailable' '0|0|0|unavailable|' measure 'PM=dnf;'

echo "-- Which entries need administrator rights (clean_admin)"
for id in rotated_logs journal crash apt_cache rc_config; do
    app_eval "clean_admin $id; echo \"st=\$?\""
    check_eq "clean_admin: $id needs administrator rights" 'st=0' "$OUT"
done
for id in recent clipboard trash thumbnails browsers cache app_caches tmp x11_logs nothing; do
    app_eval "clean_admin $id; echo \"st=\$?\""
    check_eq "clean_admin: $id does not" 'st=1' "$OUT"
done

echo "-- Option 4: the two actions and the level of the deep cleanup (P.4d, step 1)"
plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }
listed() {  # listed LEVEL: the ids whose name is in the text clean_level_text gives for the level
    app_eval "clean_level_text $1; text=\"\$REPLY\"; clean_ids C; out=''
for id in \"\${CLEAN_LIST[@]}\"; do [[ \"\$text\" == *\"\$(clean_name \"\$id\")\"* ]] && out+=\"\$id \"; done
printf '<<%s>>' \"\${out% }\""
    local v="${OUT#*<<}"; printf '%s' "${v%%>>*}"
}
new_sandbox; fake_autoremovable libold1
app_run $'\n4\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
check_eq 'the action menu: going back leaves with status 0' 0 "$RC"
assert_contains 'the action menu offers the dependencies' "$P" '1. Clean up dependencies'
assert_contains 'the action menu offers the deep cleanup' "$P" '2. Deep cleanup'
assert_contains 'the action menu explains each action' "$P" 'Removes the dependencies that are no longer needed'
assert_contains 'the action menu has a way back' "$P" '0. Back'
check_eq 'going back from the action menu runs nothing' 0 "$(grep -cE 'autoremove|autoclean|purge' <<< "$(apt_log)" || true)"
check_eq 'going back from the action menu returns to the main menu' 2 "$(grep -c '^4. Clean up' <<< "$P" || true)"
app_run $'\n4\nx\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'the action menu: a key that is not an option is told as such' "$P" 'Invalid option.'
check_eq 'the action menu asks again after it' 2 "$(grep -c '^2. Deep cleanup' <<< "$P" || true)"
app_run $'\n4\n' MINTAPP_UI=text
check_eq 'the action menu: the end of the input leaves cleanly' 0 "$RC"
app_run $'\n4\n1\ny\n\n0\n' MINTAPP_UI=text
assert_contains 'action 1 is the dependency cleanup of always' "$(apt_log)" 'apt-get autoremove -y'
new_sandbox
app_run $'\n4\n2\n0\n0\n' MINTAPP_UI=text; P="$(plain)"
assert_contains 'action 2 asks the level: simple' "$P" 'S. Simple (low risk)'
assert_contains 'action 2 asks the level: complete' "$P" 'C. Complete (thorough)'
assert_contains 'the level menu says what each one is' "$P" 'does not touch the trash or what you may consider yours.'
assert_contains 'the level menu says that nothing is deleted before the summary' "$P" 'what is cleaned and how much space it frees.'
check_eq 'going back from the level menu returns to the main menu' 2 "$(grep -c '^4. Clean up' <<< "$P" || true)"
assert_not_contains 'going back from the level menu shows no list' "$P" 'This level cleans:'
seed_clean() {  # seed_clean: a file for the entries recent, thumbnails and browsers, so that these have something to clean
    fake_file "$SB/home/.local/share/recently-used.xbel" 300
    fake_file "$SB/home/.cache/thumbnails/normal/a.png" 200
    fake_file "$SB/home/.cache/mozilla/firefox/p/cache2/a" 400
}
deep() {  # deep INPUT [VAR=val ...]: seeded sandbox, main menu, "4" (clean up), "2" (deep cleanup), INPUT, and "0" to leave; P gets the screens
    local input="$1"; shift
    seed_clean
    app_run $'\n4\n2\n'"$input"$'0\n' MINTAPP_UI=text "$@"; P="$(plain)"
}
NAMES_EN=('Recent documents' 'Clipboard' 'Trash' 'Thumbnails' 'Browser caches' 'Other caches' 'Application caches (Flatpak, Snap)' 'Temporary files' 'Rotated logs' 'System journal' 'X11 error log' 'Crash reports' 'Package cache' 'Leftover settings')
chosen() {  # chosen [MARKER [NAME...]]: which of the names (by default the English ones of the catalog) the summary after MARKER mentions, in that order, on one line
    local marker="${1:-This would be cleaned:}" name text out=""
    shift || true
    local -a names=("$@")
    [ "${#names[@]}" -gt 0 ] || names=("${NAMES_EN[@]}")
    text="$(awk -v m="$marker" 'index($0, m) { on = 1 } on && /^=====/ { exit } on' <<< "$P" | tr '\n' ' ' | tr -s ' ')"
    for name in "${names[@]}"; do
        [[ "$text" != *"$name"* ]] || out+="${out:+, }$name"
    done
    printf '%s' "$out"
}
new_sandbox
deep $'s\n0\n0\n'
assert_contains 'simple: the level is accepted in lowercase and goes on to what it cleans' "$P" 'What do you want to clean?'
assert_contains 'simple: the list of what the level cleans is shown' "$P" 'This level cleans:'
assert_contains 'simple: the privacy entries it has' "$P" 'Privacy: Recent documents, Clipboard'
assert_contains 'simple: the logs it has' "$P" 'Logs: Rotated logs, System journal'
assert_contains 'simple: the package cache' "$P" 'Packages: Package cache'
assert_not_contains 'simple: never the trash' "$P" 'Trash'
assert_not_contains 'simple: never the X11 errors' "$P" 'X11 error log'
assert_not_contains 'simple: never the crash reports' "$P" 'Crash reports'
assert_not_contains 'simple: never the leftover settings' "$P" 'Leftover settings'
deep $'C\n0\n0\n'
assert_contains 'complete: the trash is in its privacy entries' "$P" 'Privacy: Recent documents, Clipboard, Trash'
assert_contains 'complete: the X11 errors and the crash reports are in its logs' "$P" 'Logs: Rotated logs, System journal, X11 error log, Crash reports'
assert_contains 'complete: the leftover settings are in its packages' "$P" 'Packages: Package cache, Leftover settings'
check_eq 'choosing the level runs no package manager action at all' 0 "$(grep -cE 'autoremove|autoclean|purge|clean' <<< "$(apt_log)" || true)"
check_eq 'simple lists its ten entries and no other' 'recent clipboard thumbnails browsers cache app_caches tmp rotated_logs journal apt_cache' "$(listed S)"
check_eq 'complete lists all fourteen, in catalog order' 'recent clipboard trash thumbnails browsers cache app_caches tmp rotated_logs journal x11_logs crash apt_cache rc_config' "$(listed C)"
app_eval 'clean_level_text S; a="$REPLY"; clean_level_text C; printf "<<%s>>" "$([ "${#a}" -lt "${#REPLY}" ] && echo shorter || echo not)"'
value_of 'the text of simple is shorter than the one of complete' shorter
ev 'clean_level_text: the title, then one line per category with its entries' \
    'This level cleans:\nPrivacy: Recent documents, Clipboard\nCaches: Thumbnails, Browser caches, Other caches, Application caches (Flatpak, Snap), Temporary files\nLogs: Rotated logs, System journal\nPackages: Package cache' \
    'clean_level_text S; printf "<<%s>>" "$REPLY"'
ev 'clean_cat_names: the entries of a category at a level, in catalog order' 'Recent documents, Clipboard, Trash' 'clean_cat_names privacy C; printf "<<%s>>" "$REPLY"'
ev 'clean_cat_names: the same category at the simple level has no trash' 'Recent documents, Clipboard' 'clean_cat_names privacy S; printf "<<%s>>" "$REPLY"'
ev 'clean_cat_names: a category the catalog does not have gives nothing' '' 'REPLY=old; clean_cat_names nothing C; printf "<<%s>>" "$REPLY"'
ev 'clean_cat_names: in Spanish' 'Documentos recientes, Portapapeles, Papelera' 'clean_cat_names privacy C; printf "<<%s>>" "$REPLY"' MINTAPP_LANG=es
cm() {  # cm LABEL EXPECTED INPUT: choose_menu on the plain text with two entries; prints <<status|REPLY>>
    app_eval_in "$3" 'tags=(A B); labels=(one two); descs=(first second); REPLY=old; choose_menu "Pick" tags labels descs; printf "<<%s|%s>>" "$?" "$REPLY"' MINTAPP_UI=text
    value_of "$1" "$2"
}
cm 'choose_menu: a tag in lowercase picks it' '0|B' $'b\n'
cm 'choose_menu: "0" goes back and leaves REPLY empty' '1|' $'0\n'
cm 'choose_menu: the end of the input goes back and leaves REPLY empty' '1|' ''
cm 'choose_menu: a wrong key is asked again until a good one' '0|A' $'x\n9\nA\n'
lv() {  # lv LABEL EXPECTED INPUT [VAR=val ...]: clean_choose_level; prints <<status|CLEAN_LEVEL>>
    local label="$1" expected="$2" input="$3"; shift 3
    app_eval_in "$input" 'CLEAN_LEVEL=old; clean_choose_level; printf "<<%s|%s>>" "$?" "$CLEAN_LEVEL"' "$@"
    value_of "$label" "$expected"
}
lv 'level: "s" is the simple one' '0|S' $'s\n' MINTAPP_UI=text
lv 'level: "C" is the complete one' '0|C' $'C\n' MINTAPP_UI=text
lv 'level: going back leaves it empty' '1|' $'0\n' MINTAPP_UI=text
lv 'level: the end of the input leaves it empty' '1|' '' MINTAPP_UI=text
fake_answers TAG:s
lv 'level: a dialog tag in lowercase is accepted' '0|S' '' MINTAPP_UI=whiptail
fake_answers TAG:X
lv 'level: a tag that is neither S nor C chooses nothing' '1|' '' MINTAPP_UI=whiptail
new_sandbox
deep $'s\n0\n0\n' MINTAPP_LANG=es
assert_contains 'Spanish: the action' "$P" 'Limpieza profunda'
assert_contains 'Spanish: the level' "$P" 'S. Simple (bajo riesgo)'
assert_contains 'Spanish: the list of what the level cleans' "$P" 'Este nivel limpia:'
assert_contains 'Spanish: the categories name their entries' "$P" 'Privacidad: Documentos recientes, Portapapeles'

echo "-- Option 4: what to clean at the level (P.4d, step 2a)"
S_ALL='recent clipboard thumbnails browsers cache app_caches tmp rotated_logs journal apt_cache'
C_ALL='recent clipboard trash thumbnails browsers cache app_caches tmp rotated_logs journal x11_logs crash apt_cache rc_config'
C_NO_TRASH='recent clipboard thumbnails browsers cache app_caches tmp rotated_logs journal x11_logs crash apt_cache rc_config'
S_NAMES='Recent documents, Clipboard, Thumbnails, Browser caches, Other caches, Application caches (Flatpak, Snap), Temporary files, Rotated logs, System journal, Package cache'
C_NAMES='Recent documents, Clipboard, Trash, Thumbnails, Browser caches, Other caches, Application caches (Flatpak, Snap), Temporary files, Rotated logs, System journal, X11 error log, Crash reports, Package cache, Leftover settings'
cs() {  # cs LABEL EXPECTED INPUT [VAR=val ...]: clean_choose_scope S; prints <<status|REPLY>>
    local label="$1" expected="$2" input="$3"; shift 3
    app_eval_in "$input" 'REPLY=old; clean_choose_scope S; printf "<<%s|%s>>" "$?" "$REPLY"' "$@"
    value_of "$label" "$expected"
}
pick() {  # pick LABEL EXPECTED LEVEL INPUT: clean_pick on the plain text; prints <<status|ids chosen>>
    app_eval_in "$4" "clean_pick $3; printf '<<%s|%s>>' \"\$?\" \"\${CLEAN_CHOSEN[*]-}\"" MINTAPP_UI=text
    value_of "$1" "$2"
}
echo "-- the scope menu"
new_sandbox
deep $'s\n0\n0\n'
assert_contains 'scope: asks what to clean' "$P" 'What do you want to clean?'
assert_contains 'scope: the whole level' "$P" '1. The whole level'
assert_contains 'scope: by category' "$P" '2. By category'
assert_contains 'scope: one by one' "$P" '3. One by one'
assert_contains 'scope: explains the whole level' "$P" 'Cleans everything on the list, with nothing more to choose.'
assert_contains 'scope: explains the categories' "$P" 'You pick whole categories; each one cleans everything of its own.'
assert_contains 'scope: explains one by one' "$P" 'You pick each item separately.'
assert_contains 'scope: the list of the level comes before the question' "${P%%What do you want to clean?*}" 'This level cleans:'
check_eq 'scope: going back returns to the level menu' 2 "$(grep -c '^S. Simple' <<< "$P" || true)"
check_eq 'scope: and the level menu goes back to the main menu' 2 "$(grep -c '^4. Clean up' <<< "$P" || true)"
check_eq 'scope: going back never reaches the main menu in one step' 2 "$(grep -c '^1. Detect applications' <<< "$P" || true)"
deep $'s\nx\n7\n0\n0\n'
assert_contains 'scope: a key that is not an option is told as such' "$P" 'Invalid option.'
check_eq 'scope: and it is asked again after each of them' 3 "$(grep -c 'What do you want to clean?' <<< "$P" || true)"
cs 'scope: 1 is the whole level' '0|all' $'1\n' MINTAPP_UI=text
cs 'scope: 2 is the categories' '0|cats' $'2\n' MINTAPP_UI=text
cs 'scope: 3 is the entries' '0|entries' $'3\n' MINTAPP_UI=text
cs 'scope: going back leaves REPLY empty' '1|' $'0\n' MINTAPP_UI=text
cs 'scope: the end of the input leaves REPLY empty' '1|' '' MINTAPP_UI=text
cs 'scope: a wrong key is asked again until a good one' '0|cats' $'x\n7\n2\n' MINTAPP_UI=text
fake_answers TAG:3
cs 'scope in a dialog: the tag of the entries' '0|entries' '' MINTAPP_UI=whiptail
fake_answers TAG:7
cs 'scope in a dialog: a tag that is not an option chooses nothing and leaves REPLY empty' '1|' '' MINTAPP_UI=whiptail

echo "-- the whole level"
pick 'whole level, simple: its ten entries' "0|$S_ALL" S $'1\n'
pick 'whole level, complete: its fourteen entries, the trash too' "0|$C_ALL" C $'1\n'
new_sandbox
deep $'s\n1\nn\n\n'
assert_contains 'whole simple level: the summary opens' "$P" 'This would be cleaned:'
check_eq 'whole simple level: its ten names, in catalog order' "$S_NAMES" "$(chosen)"
deep $'C\n1\nn\n\n'
check_eq 'whole complete level: its fourteen names, the trash among them' "$C_NAMES" "$(chosen)"
check_eq 'choosing runs no package manager action' 0 "$(grep -cE 'autoremove|autoclean|purge|clean' <<< "$(apt_log)" || true)"
check_eq 'choosing writes no cleaning record' '' "$(clean_records)"

echo "-- by category"
pick 'categories, simple: only privacy' '0|recent clipboard' S $'2\n1\nc\n'
pick 'categories, complete: privacy brings the trash' '0|recent clipboard trash' C $'2\n1\nc\n'
pick 'categories, simple: logs have neither the X11 errors nor the crash reports' '0|rotated_logs journal' S $'2\n3\nc\n'
pick 'categories, complete: logs bring both' '0|rotated_logs journal x11_logs crash' C $'2\n3\nc\n'
pick 'categories, simple: packages have no leftover settings' '0|apt_cache' S $'2\n4\nc\n'
pick 'categories, complete: packages bring them' '0|apt_cache rc_config' C $'2\n4\nc\n'
pick 'categories, simple: caches only' '0|thumbnails browsers cache app_caches tmp' S $'2\n2\nc\n'
pick 'categories: marked in reverse, the entries still come in catalog order' '0|recent clipboard trash rotated_logs journal x11_logs crash' C $'2\n3\n1\nc\n'
pick 'categories: all four marked is the whole level' "0|$S_ALL" S $'2\n1\n2\n3\n4\nc\n'
pick 'categories: marking again undoes the mark' '0|apt_cache' S $'2\n1\n1\n4\nc\n'
pick 'categories: a number outside the list marks nothing' '0|apt_cache' S $'2\n5\n4\nc\n'
pick 'categories: with nothing marked it asks again, and then takes what is marked' '0|apt_cache' S $'2\nc\n\n4\nc\n'
pick 'categories: going back from the list returns to the scope, which can take another way' "0|$S_ALL" S $'2\n0\n1\n'
pick 'categories: going back with something marked leaves nothing chosen' '1|' S $'2\n1\n0\n0\n'
app_eval_in $'1\n0\n' 'clean_pick S >/dev/null; clean_pick S; printf "<<%s|%s>>" "$?" "${CLEAN_CHOSEN[*]-}"' MINTAPP_UI=text
value_of 'a pick that goes back does not keep what the one before chose' '1|'
new_sandbox
deep $'s\n2\n0\n0\n0\n'
assert_contains 'categories: the text above the list' "$P" 'Mark the categories you want to clean.'
assert_contains 'categories: the text says what a category brings' "$P" 'Each one cleans everything of its own'
check_eq 'categories: the four of them, none marked at the start' 4 "$(grep -cE '^ +[0-9]+\) +\[ \] ' <<< "$P" || true)"
check_eq 'categories: and none of them marked' 0 "$(grep -cE '^ +[0-9]+\) +\[x\]' <<< "$P" || true)"
assert_contains 'categories: privacy and its entries' "$P" '[ ] Privacy'
assert_contains 'categories: the entries of privacy are shown under it' "$P" 'Recent documents, Clipboard'
assert_contains 'categories: caches' "$P" '[ ] Caches'
assert_contains 'categories: logs' "$P" '[ ] Logs'
assert_contains 'categories: packages' "$P" '[ ] Packages'
assert_not_contains 'categories: four entries are shown whole, with no search' "$P" "Type 's' to search."
check_eq 'categories: going back returns to the scope menu' 2 "$(grep -c 'What do you want to clean?' <<< "$P" || true)"
check_eq 'categories: going back from the list chooses nothing' 0 "$(grep -c 'This would be cleaned:' <<< "$P" || true)"
deep $'s\n2\n1\n0\n0\n0\n'
assert_contains 'categories: a category is shown marked after marking it' "$P" '[x] Privacy'
deep $'s\n2\nc\n\n0\n0\n0\n'
assert_contains 'categories: confirming with nothing marked says so' "$P" 'Nothing is marked. Mark something on the list or go back.'
check_eq 'categories: and the list is shown again' 2 "$(grep -c 'Mark the categories you want to clean.' <<< "$P" || true)"
deep $'C\n2\n3\n1\nc\nn\n\n'
check_eq 'categories, complete: privacy and logs, in catalog order' 'Recent documents, Clipboard, Trash, Rotated logs, System journal, X11 error log, Crash reports' "$(chosen)"
deep $'s\n2\n4\nc\nn\n\n'
check_eq 'categories, simple: packages' 'Package cache' "$(chosen)"

echo "-- one by one"
pick 'entries, simple: all start marked' "0|$S_ALL" S $'3\nc\n'
pick 'entries, complete: all start marked except the trash' "0|$C_NO_TRASH" C $'3\nc\n'
pick 'entries, complete: the trash is cleaned only when marked' "0|$C_ALL" C $'3\n3\nc\n'
pick 'entries: unmarking takes an entry out' '0|thumbnails browsers cache app_caches tmp rotated_logs journal x11_logs crash apt_cache rc_config' C $'3\n1\n2\nc\n'
pick 'entries: with everything unmarked it asks again, and then takes what is marked' '0|thumbnails' S $'3\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\nc\n\n3\nc\n'
pick 'entries: a search keeps marked what it hides' "0|$C_ALL" C $'3\ns trash\n3\nc\n'
pick 'entries: going back from the list returns to the scope' '1|' S $'3\n0\n0\n'
pick 'entries: going back from the list, the scope can take another way' '0|recent clipboard' S $'3\n0\n2\n1\nc\n'
pick 'the scope: going back fails and chooses nothing' '1|' S $'0\n'
pick 'the scope: the end of the input fails and chooses nothing' '1|' S ''
new_sandbox
deep $'C\n3\n0\n0\n0\n'
assert_contains 'entries: the text above the list' "$P" 'Mark what you want to clean.'
check_eq 'entries, complete: the trash is the only one not marked' 1 "$(grep -cE '^ +[0-9]+\) +\[ \] ' <<< "$P" || true)"
check_eq 'entries, complete: the other thirteen are marked' 13 "$(grep -cE '^ +[0-9]+\) +\[x\]' <<< "$P" || true)"
assert_contains 'entries, complete: it is the trash' "$P" '[ ] Trash'
assert_contains 'entries: each one says what it does' "$P" 'Permanently deletes everything in the trash. It cannot be undone.'
assert_contains 'entries: fourteen can be searched' "$P" "Type 's' to search."
check_eq 'entries: going back returns to the scope menu' 2 "$(grep -c 'What do you want to clean?' <<< "$P" || true)"
deep $'s\n3\n0\n0\n0\n'
check_eq 'entries, simple: all ten are marked' 10 "$(grep -cE '^ +[0-9]+\) +\[x\]' <<< "$P" || true)"
check_eq 'entries, simple: none is left unmarked' 0 "$(grep -cE '^ +[0-9]+\) +\[ \] ' <<< "$P" || true)"
assert_not_contains 'entries, simple: no trash to offer' "$P" 'Trash'
deep $'C\n3\n3\n1\nc\nn\n\n'
check_eq 'entries: the summary has the trash once marked and not what was unmarked' 'Clipboard, Trash, Thumbnails, Browser caches, Other caches, Application caches (Flatpak, Snap), Temporary files, Rotated logs, System journal, X11 error log, Crash reports, Package cache, Leftover settings' "$(chosen)"
deep $'s\n3\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\nc\n\n0\n0\n0\n'
assert_contains 'entries: confirming with nothing marked says so' "$P" 'Nothing is marked. Mark something on the list or go back.'
assert_contains 'entries: and the list is shown again after it' "${P#*Nothing is marked}" 'Mark what you want to clean.'

echo "-- Spanish"
deep $'s\n2\nc\n\n1\nc\nn\n\n' MINTAPP_LANG=es
assert_contains 'Spanish: the scope question' "$P" 'Que quieres limpiar?'
assert_contains 'Spanish: the whole level' "$P" '1. Todo el nivel'
assert_contains 'Spanish: by category' "$P" '2. Por categorias'
assert_contains 'Spanish: one by one' "$P" '3. Una a una'
assert_contains 'Spanish: the text of the categories' "$P" 'Marca las categorias que quieras limpiar.'
assert_contains 'Spanish: nothing marked' "$P" 'No has marcado nada. Marca algo de la lista o vuelve atras.'
assert_contains 'Spanish: the category names' "$P" '[ ] Privacidad'
check_eq 'Spanish: the summary' 'Documentos recientes, Portapapeles' "$(chosen 'Esto se limpiaria:' 'Documentos recientes' 'Portapapeles' 'Papelera' 'Miniaturas')"
deep $'s\n3\n0\n0\n0\n' MINTAPP_LANG=es
assert_contains 'Spanish: the text of the entries' "$P" 'Marca lo que quieras limpiar.'
deep $'s\n2\nc\n\n0\n0\n0\n' MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'Spanish with accents (Unicode mode): the scope question' "$P" '¿Qué quieres limpiar?'
assert_contains 'Spanish with accents: by category' "$P" '2. Por categorías'
assert_contains 'Spanish with accents: the text of the categories' "$P" 'Marca las categorías que quieras limpiar.'
assert_contains 'Spanish with accents: nothing marked' "$P" 'No has marcado nada. Marca algo de la lista o vuelve atrás.'

echo "-- Option 4 with dialogs (stub whiptail)"
new_sandbox; fake_autoremovable libold1
fake_answers OK TAG:4 CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail: the action menu has the two actions' "$W" '1 Clean up dependencies'
assert_contains 'whiptail: and the deep cleanup' "$W" '2 Deep cleanup'
assert_contains 'whiptail: its cancel button is Back' "$(grep -F -- '--menu What do you want to do?' <<< "$W" | head -n1)" '--cancel-button Back'
check_eq 'whiptail: Back in the action menu runs nothing' 0 "$(grep -cE 'autoremove|autoclean|purge' <<< "$(apt_log)" || true)"
check_eq 'whiptail: and the program goes on to the main menu and leaves' 0 "$RC"
wt_call() {  # wt_call TEXT: the first whiptail call whose first line has TEXT, with every line of its arguments
    awk -v s="$1" '/^whiptail / { if (done) exit; on = index($0, s) > 0; if (on) done = 1 } on' "$SB/state/whiptail.log"
}
wt_count() { grep -cF -- "$1" "$SB/state/whiptail.log" || true; }
wt_summary() { wt_call '--yesno Deep cleanup,' | tr '\n' ' ' | tr -s ' '; }  # the summary and its question, on one line: whiptail wraps its text where the box ends
dump_off() { checklist_dump | awk -F'\t' 'NR > 1 && $3 == "OFF" { printf "%s ", $1 }' | sed 's/ $//'; }
dump_on() { checklist_dump "$@" | awk -F'\t' 'NR > 1 && $3 == "ON" { printf "%s ", $1 }' | sed 's/ $//'; }
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:C CANCEL CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail: the level menu has both levels' "$W" 'C Complete (thorough)'
assert_contains 'whiptail: the level text goes in the box' "$W" 'Choose the level of the deep cleanup.'
SC="$(wt_call '--menu This level cleans:')"
assert_contains 'whiptail: the scope box starts with what the level cleans' "$SC" 'This level cleans:'
assert_contains 'whiptail: the list of the complete level is in the scope box' "$SC" 'Privacy: Recent documents, Clipboard, Trash'
assert_contains 'whiptail: the question follows the list' "${SC#*Leftover settings}" 'What do you want to clean?'
assert_contains 'whiptail: the scope menu offers the whole level' "$SC" '1 The whole level'
assert_contains 'whiptail: and by category' "$SC" '2 By category'
assert_contains 'whiptail: and one by one' "$SC" '3 One by one'
assert_contains 'whiptail: its cancel button is Back' "$(head -n1 <<< "$SC")" '--cancel-button Back'
check_eq 'whiptail: Back in the scope menu returns to the level menu' 2 "$(wt_count '--menu Choose the level')"
# The text of the main menu starts with its status line (F7.0): its instruction line is what counts the times it is shown.
check_eq 'whiptail: Back in the level menu leaves the deep cleanup, to the main menu' 2 "$(wt_count 'Select an option (')"
check_eq 'whiptail: and the program leaves normally' 0 "$RC"
assert_not_contains 'whiptail: Back in the scope menu chooses nothing' "$W" 'This would be cleaned:'
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
assert_not_contains 'whiptail: Back in the level menu shows no list' "$(cat "$SB/state/whiptail.log")" 'This level cleans:'
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:S TAG:1 CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
W="$(cat "$SB/state/whiptail.log")"
CH="$(wt_summary)"
assert_contains 'whiptail, the whole simple level: the summary has its entries' "$CH" 'Package cache'
assert_contains 'whiptail, the whole simple level: and the first of them' "$CH" 'Recent documents'
assert_not_contains 'whiptail, the whole simple level: never the trash' "$CH" 'Trash'
check_eq 'whiptail, the whole level: no list with boxes is asked' 0 "$(wt_count '--checklist')"
check_eq 'whiptail, the whole level: the program leaves normally' 0 "$RC"
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:C TAG:2 'TAG:"1" "4"' CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail, categories: the four of them, with no search row' '1 2 3 4' "$(checklist_dump | awk -F'\t' 'NR > 1 { printf "%s ", $1 }' | sed 's/ $//')"
check_eq 'whiptail, categories: none starts marked' '' "$(dump_on)"
assert_contains 'whiptail, categories: the first one is privacy' "$(checklist_dump | sed -n 2p)" 'Privacy'
assert_contains 'whiptail, categories: the text above the list' "$(cat "$SB/state/whiptail.log")" 'Mark the categories you want to clean.'
CH="$(wt_summary)"
assert_contains 'whiptail, categories: privacy brings its three' "$CH" 'Trash'
assert_contains 'whiptail, categories: and packages theirs' "$CH" 'Leftover settings'
assert_not_contains 'whiptail, categories: not the caches, which were not marked' "$CH" 'Thumbnails'
assert_not_contains 'whiptail, categories: nor the logs' "$CH" 'Rotated logs'
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:C TAG:2 OK OK 'TAG:"2"' CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail, categories: confirming with nothing marked says so' "$W" 'Nothing is marked. Mark something on the list or go back.'
check_eq 'whiptail, categories: and the list comes again' 2 "$(wt_count '--checklist')"
check_eq 'whiptail, categories: still with none marked' '' "$(dump_on 2)"
CH="$(wt_summary)"
assert_contains 'whiptail, categories: then the caches are chosen' "$CH" 'Thumbnails'
assert_not_contains 'whiptail, categories: and nothing else' "$CH" 'Recent documents'
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:C TAG:3 'TAG:"1" "3"' CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail, entries: the search row, then the fourteen entries' 'S 1 2 3 4 5 6 7 8 9 10 11 12 13 14' "$(checklist_dump | awk -F'\t' 'NR > 1 { printf "%s ", $1 }' | sed 's/ $//')"
check_eq 'whiptail, entries: the search row and the trash are the only ones not marked' 'S 3' "$(dump_off)"
assert_contains 'whiptail, entries: the third one is the trash' "$(checklist_dump | sed -n 5p)" 'Trash'
assert_contains 'whiptail, entries: the text above the list' "$(cat "$SB/state/whiptail.log")" 'Mark what you want to clean.'
CH="$(wt_summary)"
assert_contains 'whiptail, entries: the first one marked is chosen' "$CH" 'Recent documents'
assert_contains 'whiptail, entries: and the trash, once marked' "$CH" 'Trash'
assert_not_contains 'whiptail, entries: not the clipboard, which was not returned' "$CH" 'Clipboard'
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:S TAG:3 'TAG:"1"' CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail, entries, simple: only the search row is not marked' 'S' "$(dump_off)"
check_eq 'whiptail, entries, simple: the ten entries marked' '1 2 3 4 5 6 7 8 9 10' "$(dump_on)"
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:S TAG:3 OK OK 'TAG:"4"' CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail, entries: confirming with nothing marked says so' "$W" 'Nothing is marked. Mark something on the list or go back.'
check_eq 'whiptail, entries: the list comes again with nothing marked' '' "$(dump_on 2)"
assert_contains 'whiptail, entries: then the fourth is chosen' "$(wt_summary)" 'Browser caches'
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:S TAG:2 CANCEL TAG:3 CANCEL CANCEL CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
W="$(cat "$SB/state/whiptail.log")"
check_eq 'whiptail: going back from each list returns to the scope: it is asked three times' 3 "$(wt_count '--menu This level cleans:')"
check_eq 'whiptail: going back from the scope returns to the level: it is asked twice' 2 "$(wt_count '--menu Choose the level')"
assert_not_contains 'whiptail: going back all the way chooses nothing' "$W" 'This would be cleaned:'
check_eq 'whiptail: and the program leaves normally' 0 "$RC"
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:S TAG:2 ESC TAG:1 CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail
assert_contains 'whiptail: Esc in a list goes back to the scope, which takes another way' "$(cat "$SB/state/whiptail.log")" 'This would be cleaned:'
check_eq 'whiptail: and choosing runs no package manager action' 0 "$(grep -cE 'autoremove|autoclean|purge|clean' <<< "$(apt_log)" || true)"
new_sandbox; seed_clean
fake_answers OK TAG:4 TAG:2 TAG:S TAG:1 CANCEL TAG:0
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=es
W="$(cat "$SB/state/whiptail.log")"
assert_contains 'whiptail, Spanish: the scope question' "$W" 'Que quieres limpiar?'
assert_contains 'whiptail, Spanish: the summary' "$W" 'Esto se limpiaria:'

echo "-- The summary (P.4d, step 2b): what is measured and how it is shown"
summary_of() {  # summary_of LEVEL "ID..." [VAR=val ...]: measures those entries and puts in SUMMARY what clean_summary_text says, one line per line
    local level="$1" ids="$2" v; shift 2
    app_eval "CLEAN_LEVEL=$level; CLEAN_CHOSEN=($ids); clean_measure_chosen; clean_summary_text; printf '<<%b>>' \"\$REPLY\"" "TMPDIR=$SB" "$@"
    v="${OUT#*<<}"; SUMMARY="${v%%>>*}"
}
echo "-- the trash: the summary names the files that go, not the whole folder"
TL='~'  # the home folder as the summary writes it (a literal tilde)
new_sandbox
T="$SB/home/.local/share/Trash"
fake_file "$T/files/a" 10; fake_file "$T/files/dir/b" 20
fake_file "$T/info/a.trashinfo" 5; fake_file "$T/info/keep.txt" 3
fake_file "$T/expunged/x" 7; fake_file "$T/directorysizes" 4; fake_file "$T/keep2.txt" 2
ev 'clean_place_text, trash: the folder with the cache of sizes names that file' "$TL/.local/share/Trash/directorysizes" \
    'clean_place_text trash "$HOME/.local/share/Trash"; printf "<<%s>>" "$REPLY"'
ev 'clean_place_text, trash: the folder of the records names its *.trashinfo' "$TL/.local/share/Trash/info/*.trashinfo" \
    'clean_place_text trash "$HOME/.local/share/Trash/info"; printf "<<%s>>" "$REPLY"'
ev 'clean_place_text, trash: the folder of the files goes whole' "$TL/.local/share/Trash/files" \
    'clean_place_text trash "$HOME/.local/share/Trash/files"; printf "<<%s>>" "$REPLY"'
ev 'clean_place_text, trash: and so does the expunged one' "$TL/.local/share/Trash/expunged" \
    'clean_place_text trash "$HOME/.local/share/Trash/expunged"; printf "<<%s>>" "$REPLY"'
summary_of C trash
check_eq 'trash, summary: its four places, each as it is cleaned' \
    $'  ~/.local/share/Trash/files\n  ~/.local/share/Trash/info/*.trashinfo\n  ~/.local/share/Trash/expunged\n  ~/.local/share/Trash/directorysizes' \
    "$(grep '^  ' <<< "$SUMMARY")"
assert_contains 'trash, summary: its size and its five files' "$SUMMARY" 'Trash: 1 KB, 5 files'
trash_left() { find "$SB/home/.local" \( -type f -o -type l \) | sed "s|$SB/home|@|" | sort | paste -sd'|'; }
check_eq 'trash, measuring removed nothing' '@/.local/share/Trash/directorysizes|@/.local/share/Trash/expunged/x|@/.local/share/Trash/files/a|@/.local/share/Trash/files/dir/b|@/.local/share/Trash/info/a.trashinfo|@/.local/share/Trash/info/keep.txt|@/.local/share/Trash/keep2.txt' "$(trash_left)"
app_eval 'clean_item run trash C'
check_eq 'trash, what the summary said: the removal leaves only what it did not name' '@/.local/share/Trash/info/keep.txt|@/.local/share/Trash/keep2.txt' "$(trash_left)"

echo "-- measuring (clean_measure_chosen): what each entry would do, nothing removed"
new_sandbox
MH="$SB/home"
fake_file "$MH/.local/share/recently-used.xbel" 300
fake_file "$MH/.local/share/Trash/files/a" 10
fake_file "$MH/.local/share/Trash/info/a.trashinfo" 5
fake_file "$MH/.cache/thumbnails/normal/a.png" 200
fake_file "$MH/.cache/mozilla/firefox/p/cache2/a" 400
fake_file "$MH/.cache/foo/x" 100
fake_installed pkg1 pkg2 vim; fake_configfiles pkg1 pkg2
# A clipboard tool, and a session bus that says no name runs: the clipboard entry then has a known answer.
printf '#!/bin/sh\nexit 0\n' > "$SB/bin/xsel"
printf '#!/bin/sh\necho "   boolean false"\n' > "$SB/bin/dbus-send"
chmod 755 "$SB/bin/xsel" "$SB/bin/dbus-send"; sandbox_chown
mtree() { find "$SB/home" \( -type f -o -type l \) | sed "s|$SB/home|@|" | sort | paste -sd'|'; }
MEASURE_IDS='recent clipboard trash thumbnails browsers cache app_caches rc_config'
measured() {  # measured LABEL EXPECTED LEVEL "ID..." [CODE BEFORE [VAR=val ...]]: a line "id|state|files|bytes|failed|note" for each entry, then "total|files|bytes"
    local label="$1" expected="$2" level="$3" ids="$4" setup="${5-}"
    shift $(( $# < 5 ? $# : 5 ))
    app_eval "$setup CLEAN_LEVEL=$level; CLEAN_CHOSEN=($ids); clean_measure_chosen
out=''; for i in \"\${!CLEAN_CHOSEN[@]}\"; do out+=\"\${CLEAN_CHOSEN[i]}|\${CLEAN_M_STATE[i]}|\${CLEAN_M_FILES[i]}|\${CLEAN_M_BYTES[i]}|\${CLEAN_M_FAILED[i]}|\${CLEAN_M_NOTE[i]}\"\$'\\n'; done
printf '<<%s%s>>' \"\$out\" \"total|\$CLEAN_TOTAL_FILES|\$CLEAN_TOTAL_BYTES\"" "TMPDIR=$SB" "$@"
    value_of "$label" "$expected"
}
BEFORE_M="$(mtree)"
measured 'measure, complete level: one line per entry in the order chosen, and the totals' \
$'recent|ok|1|300|0|\nclipboard|ok|0|0|0|xsel\ntrash|ok|2|15|0|\nthumbnails|ok|1|200|0|\nbrowsers|ok|1|400|0|\ncache|ok|1|100|0|\napp_caches|ok|0|0|0|\nrc_config|ok|2|0|0|\ntotal|6|1015' \
    C "$MEASURE_IDS" '' DISPLAY=:0
check_eq 'measure: nothing was removed' "$BEFORE_M" "$(mtree)"
check_eq 'measure: apt was never asked to purge (rc_config only simulates)' 'no' "$(apt_log | grep -q 'purge -y' && echo yes || echo no)"
check_eq 'measure: and no administrator rights were used' '' "$(sudo_log)"
measured 'measure, the order of CLEAN_CHOSEN is the order of the arrays' \
$'cache|ok|1|100|0|\nrecent|ok|1|300|0|\ntotal|2|400' C 'cache recent'
measured 'measure, simple level: the cache only counts what was not used for 30 days' \
$'cache|ok|0|0|0|\ntotal|0|0' S cache
fake_age "$MH/.cache/foo/x" 40
measured 'measure, simple level: once the file is 40 days old it counts' \
$'cache|ok|1|100|0|\ntotal|1|100' S cache
measured 'measure, with the clipboard unavailable (no session): its state says so and it adds nothing' \
$'clipboard|unavailable|0|0|0|\ntotal|0|0' C clipboard
measured 'measure: the arrays are made again each time, with nothing left from the call before' \
$'recent|ok|1|300|0|\ntotal|1|300' C recent 'CLEAN_M_STATE=(old old old old); CLEAN_M_FILES=(9 9 9 9); CLEAN_TOTAL_FILES=77; CLEAN_TOTAL_BYTES=77;'
measured 'measure: an empty choice gives empty arrays and zero totals' 'total|0|0' C ''
measured 'measure, the level counts: simple leaves out the trash only because the menu never offers it, the engine measures what it is given' \
$'trash|ok|2|15|0|\ntotal|2|15' S trash
measured 'measure, apt cache with another manager: unavailable, and not counted' \
$'apt_cache|unavailable|0|0|0|\ntotal|0|0' S apt_cache 'PM=dnf;'
measured 'measure, rc_config alone: its packages are not files, so the totals stay at zero' \
$'rc_config|ok|2|0|0|\ntotal|0|0' C rc_config
if [ "$(id -u)" -eq 0 ]; then
    : > "$MH/.cache/foo/theirs"; head -c 900 /dev/zero > "$MH/.cache/foo/theirs"; chown 0:0 "$MH/.cache/foo/theirs"
    measured 'measure: a file of another user inside the cache is left out of the files and of the size' \
$'cache|ok|1|100|0|\ntotal|1|100' C cache
    rm -f "$MH/.cache/foo/theirs"
else
    skip_case 'measure: a file of another user is left out (needs the suite to run as root to make one)'
fi
fake_file "$MH/.cache/foo/open.log" 50
measured 'measure: what a process has open is not counted' \
$'cache|ok|1|100|0|\ntotal|1|100' C cache 'exec 9< "$HOME/.cache/foo/open.log";'
measured 'measure: the same file, once nobody holds it, is counted' \
$'cache|ok|2|150|0|\ntotal|2|150' C cache
app_eval 'CLEAN_LEVEL=C; CLEAN_CHOSEN=(cache); clean_measure_chosen; printf "<<[%s]>>" "$CLEAN_OPENFILE"' "TMPDIR=$SB"
value_of 'measure: the list of open files is removed from the variable when it ends' '[]'
app_eval 'CLEAN_LEVEL=C; CLEAN_CHOSEN=(cache); clean_measure_chosen' "TMPDIR=$SB"
check_eq 'measure: and from the disk' 0 "$(find "$SB" -maxdepth 1 -name 'mintapp-clean.*' | wc -l)"
measured 'measure: if the list of open files cannot be made it still measures' \
$'cache|ok|2|150|0|\ntotal|2|150' C cache 'TMPDIR=/nonexistent/folder; export TMPDIR;'
rm -f "$MH/.cache/foo/open.log"
echo "-- what an entry would do (clean_entry_class) and whether anything would be cleaned (clean_has_work)"
ec() {  # ec LABEL EXPECTED ID STATE FILES BYTES FAILED: the class that clean_entry_class gives to an entry with that measure
    local label="$1" expected="$2"
    app_eval "CLEAN_CHOSEN=($3); CLEAN_M_STATE=($4); CLEAN_M_FILES=($5); CLEAN_M_BYTES=($6); CLEAN_M_FAILED=($7); REPLY=old; clean_entry_class 0; printf '<<%s|%s>>' \"\$?\" \"\$REPLY\""
    value_of "$label" "0|$expected"
}
ec 'class: an entry this system lacks is unavailable, whatever it counted' unavailable cache unavailable 3 100 0
ec 'class: an entry in use is busy' busy apt_cache busy 0 0 0
ec 'class: busy wins over the files it counted' busy apt_cache busy 5 100 0
ec 'class: nothing found is empty' empty cache ok 0 0 0
ec 'class: one file is work' work cache ok 1 100 0
ec 'class: a file of 0 bytes still counts as work' work cache ok 1 0 0
ec 'class: a size without a count is work too' work cache ok 0 5 0
ec 'class: failures and not a single file is unknown (could not be worked out)' unknown cache ok 0 0 2
ec 'class: failures next to files that did count is still work' work cache ok 3 100 1
ec 'class: the clipboard has no files, and it is work' work clipboard ok 0 0 0
ec 'class: the clipboard of a session without tools is unavailable' unavailable clipboard unavailable 0 0 0
ec 'class: a clipboard that failed with nothing counted is unknown' unknown clipboard ok 0 0 1
ec 'class: leftover settings with packages are work, though they have no size' work rc_config ok 2 0 0
ec 'class: leftover settings without packages are empty' empty rc_config ok 0 0 0
ec 'class: leftover settings that could not be simulated are unknown' unknown rc_config ok 0 0 2
ec 'class: leftover settings of a manager that has none are unavailable' unavailable rc_config unavailable 0 0 0
ec 'class: a size without files is work for any ordinary entry, the trash too' work trash ok 0 7 0
app_eval 'CLEAN_CHOSEN=(cache); CLEAN_M_STATE=(); CLEAN_M_FILES=(); CLEAN_M_BYTES=(); CLEAN_M_FAILED=(); clean_entry_class 0; printf "<<%s>>" "$REPLY"'
value_of 'class: an entry that was never measured is empty, not an error' empty
app_eval 'CLEAN_CHOSEN=(cache recent); CLEAN_M_STATE=(ok ok); CLEAN_M_FILES=(0 4); CLEAN_M_BYTES=(0 40); CLEAN_M_FAILED=(0 0); clean_entry_class 1; a="$REPLY"; clean_entry_class 0; printf "<<%s %s>>" "$a" "$REPLY"'
value_of 'class: it answers for the entry whose number it is given' 'work empty'
hw() {  # hw LABEL EXPECTED_STATUS "IDS" "STATES" "FILES" "BYTES" "FAILED": the status of clean_has_work for those measures
    app_eval "CLEAN_CHOSEN=($3); CLEAN_M_STATE=($4); CLEAN_M_FILES=($5); CLEAN_M_BYTES=($6); CLEAN_M_FAILED=($7); clean_has_work; printf '<<%s>>' \"\$?\""
    value_of "$1" "$2"
}
hw 'has work: one entry with files among empty ones' 0 'cache recent trash' 'ok ok ok' '0 3 0' '0 30 0' '0 0 0'
hw 'has work: the first one is the one that works' 0 'cache recent' 'ok ok' '2 0' '20 0' '0 0'
hw 'has work: the last one is the one that works' 0 'cache recent' 'ok ok' '0 2' '0 20' '0 0'
hw 'has work: only the clipboard' 0 'clipboard' 'ok' '0' '0' '0'
hw 'has work: only leftover settings' 0 'rc_config' 'ok' '2' '0' '0'
hw 'has no work: everything empty' 1 'cache recent' 'ok ok' '0 0' '0 0' '0 0'
hw 'has no work: only unavailable, busy and unknown entries' 1 'journal apt_cache cache' 'unavailable busy ok' '0 0 0' '0 0 0' '0 0 4'
hw 'has no work: unavailable entries that show files (they do not run)' 1 'cache' 'unavailable' '5' '50' '0'
hw 'has no work: no entry chosen' 1 '' '' '' '' ''
app_eval 'CLEAN_CHOSEN=(cache recent); CLEAN_M_STATE=(ok ok); CLEAN_M_FILES=(0 4); CLEAN_M_BYTES=(0 40); CLEAN_M_FAILED=(0 0); clean_has_work; printf "<<%s|%s|%s>>" "${CLEAN_CHOSEN[*]}" "${CLEAN_M_FILES[*]}" "${CLEAN_M_BYTES[*]}"'
value_of 'has work: it changes none of the measures' 'cache recent|0 4|0 40'

echo "-- The titles of the summary and the result (P.4e): the level in lower case and in agreement with \"limpieza\""
ev 'level word, English, simple: lower case' simple 'CLEAN_LEVEL=S; clean_level_word; printf "<<%s>>" "$REPLY"'
ev 'level word, English, complete: lower case, without the parenthesis' complete 'CLEAN_LEVEL=C; clean_level_word; printf "<<%s>>" "$REPLY"'
ev 'level word, Spanish, simple: it says "simple" for "limpieza"' simple 'CLEAN_LEVEL=S; clean_level_word; printf "<<%s>>" "$REPLY"' MINTAPP_LANG=es
ev 'level word, Spanish, complete: feminine, as the cleanup it names' completa 'CLEAN_LEVEL=C; clean_level_word; printf "<<%s>>" "$REPLY"' MINTAPP_LANG=es
title_of() {  # title_of KIND LEVEL [VAR=val ...]: the first line of the summary or the result text (KIND: summary|result)
    local kind="$1" level="$2" fn=clean_summary_text; shift 2
    [ "$kind" = summary ] || fn=clean_result_text
    app_eval "CLEAN_LEVEL=$level; CLEAN_CHOSEN=(cache); CLEAN_M_STATE=(ok); CLEAN_M_FILES=(1); CLEAN_M_BYTES=(10); CLEAN_M_FAILED=(0); CLEAN_M_NOTE=(); CLEAN_M_WHERE=(); CLEAN_R_STATE=(done); CLEAN_R_FILES=(1); CLEAN_R_BYTES=(10); CLEAN_R_FAILED=(0); CLEAN_R_NOTE=(); CLEAN_R_WHY=(); $fn; printf '<<%b>>' \"\$REPLY\"" "$@"
    local v="${OUT#*<<}"; v="${v%%>>*}"; printf '%s' "${v%%$'\n'*}"
}
check_eq 'summary title, English, simple level' 'Deep cleanup, simple level. This would be cleaned:' "$(title_of summary S)"
check_eq 'summary title, English, complete level: no capital in the middle of the sentence' 'Deep cleanup, complete level. This would be cleaned:' "$(title_of summary C)"
check_eq 'summary title, Spanish, simple level' 'Limpieza profunda simple. Esto se limpiaria:' "$(title_of summary S MINTAPP_LANG=es)"
check_eq 'summary title, Spanish, complete level: "completa", not "nivel Completa"' 'Limpieza profunda completa. Esto se limpiaria:' "$(title_of summary C MINTAPP_LANG=es)"
check_eq 'result title, English, simple level' 'Deep cleanup, simple level. Result:' "$(title_of result S)"
check_eq 'result title, English, complete level' 'Deep cleanup, complete level. Result:' "$(title_of result C)"
check_eq 'result title, Spanish, simple level' 'Limpieza profunda simple. Resultado:' "$(title_of result S MINTAPP_LANG=es)"
check_eq 'result title, Spanish, complete level' 'Limpieza profunda completa. Resultado:' "$(title_of result C MINTAPP_LANG=es)"

# ---- D3 (P.4d, steps 2b, 3 and 4): what runs after the summary --------------------------------
# The folders of the sandbox in place of /tmp and /var: a copy of the program that accepts them.
# Always sandbox_roots_off before new_sandbox: the copy lives in the sandbox that is removed.
sandbox_roots_on() {
    sed -e 's/^readonly CLEAN_SYSTEM_ROOTS$/true/' "$H_SCRIPT" > "$SB/prog.sh"; chmod 644 "$SB/prog.sh"; sandbox_chown
    H_SCRIPT_REAL="$H_SCRIPT"; H_SCRIPT="$SB/prog.sh"
}
sandbox_roots_off() { H_SCRIPT="$H_SCRIPT_REAL"; }

echo "-- The list of what is open (clean_open_prepare, clean_open_done) and the files of the program itself (clean_own_file)"
new_sandbox
mkdir -p "$SB/lists"; sandbox_chown
fake_file "$SB/home/hold/open.txt" 10; fake_file "$SB/home/hold/closed.txt" 10
ev 'open list: a private file (mode 600) made in TMPDIR' '600|yes' \
    'clean_open_prepare; f="$CLEAN_OPENFILE"; printf "<<%s|%s>>" "$(stat -c %a "$f")" "$([[ "$f" == "$TMPDIR"/mintapp-clean.* ]] && echo yes || echo no)"' TMPDIR="$SB/lists"
ev 'open list: it succeeds' 0 'clean_open_prepare; printf "<<%s>>" "$?"' TMPDIR="$SB/lists"
ev 'open list: it names what a process holds open and not what nobody holds' '1|0' \
    'exec 9< "$HOME/hold/open.txt"; clean_open_prepare; printf "<<%s|%s>>" "$(grep -cxF "$HOME/hold/open.txt" "$CLEAN_OPENFILE")" "$(grep -cxF "$HOME/hold/closed.txt" "$CLEAN_OPENFILE" || true)"' TMPDIR="$SB/lists"
rm -f "$SB"/lists/mintapp-clean.*
ev 'open list: a second call removes the first list and leaves one' 'yes|yes|1' \
    'clean_open_prepare; a="$CLEAN_OPENFILE"; clean_open_prepare; printf "<<%s|%s|%s>>" "$([ -e "$a" ] && echo no || echo yes)" "$([ -f "$CLEAN_OPENFILE" ] && echo yes || echo no)" "$(find "$TMPDIR" -name "mintapp-clean.*" | wc -l)"' TMPDIR="$SB/lists"
rm -f "$SB"/lists/mintapp-clean.*
ev 'open list: a folder it cannot use gives status 1 and an empty variable' '1|[]' \
    'clean_open_prepare; st=$?; printf "<<%s|[%s]>>" "$st" "$CLEAN_OPENFILE"' TMPDIR=/nonexistent/folder
fake_file "$SB/home/old.list" 3
ev 'open list: when it fails the previous list is gone too, not left behind' 'no|[]' \
    'CLEAN_OPENFILE="$HOME/old.list"; clean_open_prepare || true; printf "<<%s|[%s]>>" "$([ -e "$HOME/old.list" ] && echo yes || echo no)" "$CLEAN_OPENFILE"' TMPDIR=/nonexistent/folder
fake_file "$SB/home/old.list" 3; fake_file "$SB/home/other.txt" 3
ev 'clean_open_done: removes the list and empties the variable, and only that file' 'no|[]|yes' \
    'CLEAN_OPENFILE="$HOME/old.list"; clean_open_done; printf "<<%s|[%s]|%s>>" "$([ -e "$HOME/old.list" ] && echo yes || echo no)" "$CLEAN_OPENFILE" "$([ -e "$HOME/other.txt" ] && echo yes || echo no)"'
ev 'clean_open_done: with no list it succeeds and touches nothing' '0|yes' \
    'CLEAN_OPENFILE=""; clean_open_done; printf "<<%s|%s>>" "$?" "$([ -e "$HOME/other.txt" ] && echo yes || echo no)"'
cop() {  # cop LABEL EXPECTED PATH [SETUP]: the status of clean_own_file for PATH (own = 0, not own = 1), after the code SETUP
    local label="$1" expected="$2" path="$3" setup="${4-}"
    app_eval "$setup clean_own_file \"$path\"; printf '<<%s>>' \"\$?\""
    value_of "$label" "$expected"
}
cop 'own file: the lock that keeps a second copy out, wherever it is' 0 /home/x/.local/state/mintapp-remover/mintapp-remover.lock
cop 'own file: a lock of another program is not' 1 /tmp/other.lock
cop 'own file: a name that only ends like the lock is not' 1 /tmp/not-mintapp-remover.lock
cop 'own file: the list of what is open' 0 /tmp/mintapp-clean.AbC123 'CLEAN_OPENFILE=/tmp/mintapp-clean.AbC123;'
cop 'own file: another list of the same kind, not made by this run, is not' 1 /tmp/mintapp-clean.Other 'CLEAN_OPENFILE=/tmp/mintapp-clean.AbC123;'
cop 'own file: with no list made, no path is taken for it' 1 /tmp/mintapp-clean.AbC123 'CLEAN_OPENFILE=;'
cop 'own file: what is inside the work folder of the windows' 0 /tmp/mintapp-gui.Z9/askpass 'GUI_WORK_DIR=/tmp/mintapp-gui.Z9;'
cop 'own file: deeper inside the work folder too' 0 /tmp/mintapp-gui.Z9/a/b 'GUI_WORK_DIR=/tmp/mintapp-gui.Z9;'
cop 'own file: a folder whose name starts like the work folder is not inside it' 1 /tmp/mintapp-gui.Z90/x 'GUI_WORK_DIR=/tmp/mintapp-gui.Z9;'
cop 'own file: with no work folder, nothing is inside it' 1 /tmp/mintapp-gui.Z9/askpass 'GUI_WORK_DIR=;'
echo "-- the list lives in the folder that the tmp entry cleans: the engine must not remove it, or what is open would lose its protection"
new_sandbox; sandbox_roots_on
TL="$SB/tmpl"; TLENV="CLEAN_SYSTEM_ROOTS=(\"$TL\"); CLEAN_TMP_DIRS=(\"$TL\")"
fake_file "$TL/held.txt" 10; fake_file "$TL/gone.txt" 20
app_eval "$TLENV; exec 9< \"$TL/held.txt\"; clean_open_prepare; list=\"\$CLEAN_OPENFILE\"; clean_item run tmp C
a=\"\$CLEAN_ITEM_FILES|\$CLEAN_ITEM_BYTES|\$CLEAN_ITEM_SKIPPED\"
b=\"\$([ -f \"\$list\" ] && echo list-stays || echo list-gone)|\$([ -e \"$TL/held.txt\" ] && echo held-stays || echo held-gone)|\$([ -e \"$TL/gone.txt\" ] && echo gone-stays || echo gone-gone)\"
clean_open_done
printf '<<%s|%s|%s>>' \"\$a\" \"\$b\" \"\$([ -f \"\$list\" ] && echo list-stays || echo list-gone)\"" TMPDIR="$TL"
TLV="${OUT#*<<}"; TLV="${TLV%%>>*}"
check_eq 'tmp with the list inside: one file goes (1 file, 20 bytes) and two are left alone (the open one, the list)' '1|20|2' "$(cut -d'|' -f1-3 <<< "$TLV")"
check_eq 'tmp with the list inside: the list and the open file stay, the other file goes' 'list-stays|held-stays|gone-gone' "$(cut -d'|' -f4-6 <<< "$TLV")"
check_eq 'tmp with the list inside: clean_open_done removes the list afterwards' 'list-gone' "$(cut -d'|' -f7 <<< "$TLV")"
sandbox_roots_off

# ---- D3 (P.4d, step 3): administrator rights, asked before anything is recorded or run ---------
echo "-- Rights first: whether the cleaning needs them (clean_run_needs_priv)"
new_sandbox
nrp() {  # nrp LABEL EXPECTED CHOSEN STATES FILES BYTES [FAILED]: the status of clean_run_needs_priv for those entries, each with the measure at its position
    local label="$1" expected="$2"
    app_eval "CLEAN_CHOSEN=($3); CLEAN_M_STATE=($4); CLEAN_M_FILES=($5); CLEAN_M_BYTES=($6); CLEAN_M_FAILED=(${7:-}); clean_run_needs_priv; printf '<<%s>>' \"\$?\""
    value_of "$label" "$expected"
}
for id in rotated_logs journal crash apt_cache rc_config; do
    nrp "needs rights: $id with something to clean" 0 "$id" ok 1 10
done
ev 'needs rights: the nine entries that work without them never ask' '1 1 1 1 1 1 1 1 1' '
out=""
for id in recent clipboard trash thumbnails browsers cache app_caches tmp x11_logs; do
    CLEAN_CHOSEN=("$id"); CLEAN_M_STATE=(ok); CLEAN_M_FILES=(1); CLEAN_M_BYTES=(10); CLEAN_M_FAILED=()
    clean_run_needs_priv; out+="$? "
done
printf "<<%s>>" "${out% }"'
nrp 'needs rights: the entry with rights comes after one that does not' 0 'tmp rotated_logs' 'ok ok' '1 2' '10 20'
nrp 'needs rights: an entry with rights and nothing to clean asks for nothing' 1 rotated_logs ok 0 0
nrp 'needs rights: nor one that is busy (apt is working)' 1 apt_cache busy 0 0
nrp 'needs rights: nor one this system lacks' 1 journal unavailable 0 0
nrp 'needs rights: nor one that could not be worked out' 1 crash ok 0 0 2
nrp 'needs rights: leftover settings with no packages to purge' 1 rc_config ok 0 0
nrp 'needs rights: the one that needs them has nothing to clean and the other runs: no password for nothing' 1 'rotated_logs tmp' 'ok ok' '0 3' '0 30'
nrp 'needs rights: nothing chosen' 1 '' '' '' ''

echo "-- Rights first (clean_priv_check): on the terminal it says so and asks with sudo -v"
new_sandbox
mkdir -p "$SB/deny"
printf '#!/bin/sh\necho "sudo $*" >> "%s/state/sudo.log"\nexit 1\n' "$SB" > "$SB/deny/sudo"; chmod 755 "$SB/deny/sudo"
printf '#!/bin/sh\necho "doas $*" >> "%s/state/sudo.log"\nexit 0\n' "$SB" > "$SB/bin/doas"; chmod 755 "$SB/bin/doas"
sandbox_chown
pc() {  # pc LABEL EXPECTED INTERFACE [VAR=val ...]: the status of clean_priv_check on a terminal; OUT also holds what it wrote
    local label="$1" expected="$2" code; code="$(eng "$3")"; shift 3
    : > "$SB/state/sudo.log"
    app_eval "$code"'; clean_priv_check; printf "<<%s>>" "$?"' "$@"
    value_of "$label" "$expected"
}
NOTE_EN1='Part of this cleanup needs administrator rights.'; NOTE_EN2='It may ask for your password now.'
for ui in tui whiptail text; do
    pc "$ui, sudo accepts: status 0" 0 "$ui" MINTAPP_LANG=en
    check_eq "$ui, sudo accepts: it ran sudo -v and nothing else" 'sudo -v' "$(sudo_log)"
done
assert_contains 'it says that part of the cleanup needs rights' "$OUT" "$NOTE_EN1"
assert_contains 'and that the password may be asked now' "$OUT" "$NOTE_EN2"
pc 'in Spanish' 0 tui MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'in Spanish: the rights' "$OUT" 'Una parte de esta limpieza necesita permisos de administrador.'
assert_contains 'in Spanish: the password' "$OUT" 'Puede pedirte la contraseña ahora.'
pc 'sudo -v fails: no rights (77)' 77 tui MINTAPP_LANG=en MINTAPP_SUDO="$SB/deny/sudo"
check_eq 'sudo -v fails: that was its only call' 'sudo -v' "$(sudo_log)"
assert_contains 'sudo -v fails: the note came before' "$OUT" "$NOTE_EN2"
pc 'doas: nothing to check, it passes (doas asks command by command)' 0 tui MINTAPP_LANG=en MINTAPP_SUDO=doas
check_eq 'doas: it was not run' '' "$(sudo_log)"
assert_contains 'doas: the note is shown all the same' "$OUT" "$NOTE_EN2"
pc 'no sudo and no doas: it passes (the start already refused)' 0 tui MINTAPP_LANG=en MINTAPP_SUDO=no-such-command
check_eq 'no sudo and no doas: nothing was run' '' "$(sudo_log)"

echo "-- Rights first (clean_priv_check): in windows it is priv_authenticate, with no text on the terminal"
gfresh() { new_sandbox; mkdir -p "$SB/tmp"; sandbox_chown; }
GUI=(DISPLAY=:99 MINTAPP_UI=gui MINTAPP_ASCII=0 MINTAPP_LANG=en)
gpc() { app_eval 'zenity_usable; UI_ENGINE=gui; clean_priv_check; printf "<<%s>>" "$?"' "${GUI[@]}" TMPDIR="$SB/tmp"; }
PW='Pa ss w0rd $HOME'
gfresh
gpc
value_of 'windows, no password needed: 0' 0
check_eq 'windows, no password needed: it only checked (sudo -A -v)' 'sudo -A -v' "$(sudo_log)"
check_eq 'windows, no password needed: no window' 0 "$(zenity_calls)"
assert_not_contains 'windows: nothing about the password is written on the terminal' "$OUT" 'administrator rights'
fake_sudo_password "$PW"; fake_zenity "OUT:$PW"
gpc
value_of 'windows, right password: 0' 0
check_eq 'windows, right password: one window' 1 "$(zenity_calls)"
check_eq 'windows, right password: sudo got what was typed' "$PW" "$(sudo_given)"
fake_sudo_password "$PW"; fake_zenity CANCEL
gpc
value_of 'windows, password cancelled: no rights (77)' 77
check_eq 'windows, password cancelled: one window' 1 "$(zenity_calls)"
check_eq 'windows, password cancelled: sudo got nothing' '' "$(sudo_given)"

# ---- D3 (P.4d, step 3): the confirmation (clean_confirm) --------------------------------------
echo "-- The confirmation in text mode: it starts at \"no\" and only an explicit yes goes on"
new_sandbox
cf() {  # cf LABEL EXPECTED ANSWER [VAR=val ...]: the status of clean_confirm in text mode when the user types ANSWER (nothing at all if it is empty and EOF is given)
    local label="$1" expected="$2" answer="$3"; shift 3
    app_eval_in "$answer"$'\n' 'clean_confirm "The summary of the cleaning"; printf "<<%s>>" "$?"' MINTAPP_LANG=en MINTAPP_ASCII=0 "$@"
    value_of "$label" "$expected"
}
for a in y Y yes YES Yes s S si SI sí Sí SÍ ' y '; do cf "yes: \"$a\"" 0 "$a"; done
for a in n N no NO ''; do cf "no: \"$a\"" 1 "$a"; done
for a in maybe yess ok 1 'y e s'; do cf "not an answer, so no: \"$a\"" 1 "$a"; done
cf 'yes in Spanish: the English one is accepted too' 0 y MINTAPP_LANG=es
cf 'yes in Spanish: "sí"' 0 sí MINTAPP_LANG=es
cf 'yes in English: the Spanish one is accepted too' 0 s
app_eval_in '' 'clean_confirm "The summary of the cleaning"; printf "<<%s>>" "$?"' MINTAPP_LANG=en MINTAPP_ASCII=0
value_of 'end of input counts as no' 1
cf 'yes: the summary is shown to read before answering' 0 y
assert_contains 'yes: the summary is on the screen' "$OUT" 'The summary of the cleaning'
assert_not_contains 'yes: nothing says it was cancelled' "$OUT" 'Operation cancelled.'
cf 'no: status 1' 1 n
assert_contains 'no: it says it was cancelled' "$OUT" 'Operation cancelled.'
assert_not_contains 'no: it is a plain no, not an answer that was not understood' "$OUT" 'Answer not recognized.'
cf 'a typo: status 1' 1 yess
assert_contains 'a typo: it says that the answer was not recognized' "$OUT" 'Answer not recognized.'
assert_contains 'a typo: and then that it was cancelled' "${OUT#*Answer not recognized.}" 'Operation cancelled.'
cf 'in Spanish, a typo' 1 si- MINTAPP_LANG=es
assert_contains 'in Spanish, a typo: the text is Spanish' "$OUT" 'Respuesta no reconocida.'
assert_contains 'in Spanish, a typo: and so is the cancellation' "$OUT" 'Operación cancelada.'
ev 'the question of the text mode ends in [y/N] in English' '[y/N]: ' 'printf "<<%s>>" "$(msg clean_confirm_text | grep -o "\[[a-zA-Z]/N\]: $")"' MINTAPP_LANG=en
ev 'the question of the text mode ends in [s/N] in Spanish' '[s/N]: ' 'printf "<<%s>>" "$(msg clean_confirm_text | grep -o "\[[a-zA-Z]/N\]: $")"' MINTAPP_LANG=es MINTAPP_ASCII=0

echo "-- The confirmation with dialogs: the button says Clean, \"no\" is the one that is active"
new_sandbox
wcf() {  # wcf LABEL EXPECTED ANSWER [VAR=val ...]: the status of clean_confirm with whiptail when the stub answers ANSWER
    local label="$1" expected="$2" answer="$3"; shift 3
    fake_answers "$answer"
    app_eval 'HAVE_WHIPTAIL=1; clean_confirm "The summary of the cleaning"; printf "<<%s>>" "$?"' MINTAPP_LANG=en MINTAPP_ASCII=0 "$@"
    value_of "$label" "$expected"
}
allow_clean_confirm
wcf 'dialog, Clean: status 0' 0 YES
WL="$(cat "$SB/state/whiptail.log")"
check_eq 'dialog: one question' 1 "$(grep -c '^whiptail ' <<< "$WL")"
assert_contains 'dialog: a yes/no box' "$WL" '--yesno'
assert_contains 'dialog: the button that confirms says Clean' "$WL" '--yes-button Clean'
assert_contains 'dialog: and the other says Cancel' "$WL" '--no-button Cancel'
assert_contains 'dialog: "no" is the active button, so a stray Enter cancels' "$WL" '--defaultno'
assert_contains 'dialog: the box has the summary' "$WL" 'The summary of the cleaning'
assert_contains 'dialog: and the question whether to go on with the cleanup' "$WL" 'Do you want to continue with the cleanup?'
wcf 'dialog, Cancel: status 1' 1 CANCEL
wcf 'dialog, Esc: it does not go on' 255 ESC
wcf 'dialog, the answers ran out (Esc): it does not go on' 255 ''
wcf 'dialog in Spanish, Limpiar: status 0' 0 YES MINTAPP_LANG=es
WL="$(grep '^whiptail ' "$SB/state/whiptail.log" | tail -n1)"
assert_contains 'dialog in Spanish: the button says Limpiar' "$WL" '--yes-button Limpiar'
assert_contains 'dialog in Spanish: the other says Cancelar' "$WL" '--no-button Cancelar'

echo "-- The confirmation in windows: Clean is the OK button, and the focus starts on Cancel"
gfresh; allow_clean_confirm
gcf() {  # gcf LABEL EXPECTED ANSWER [VAR=val ...]: the status of clean_confirm in windows when the zenity stub answers ANSWER
    local label="$1" expected="$2" answer="$3"; shift 3
    fake_zenity "$answer"
    app_eval 'zenity_usable; UI_ENGINE=gui; HAVE_WHIPTAIL=1; clean_confirm "The summary of the cleaning"; printf "<<%s>>" "$?"' "${GUI[@]}" TMPDIR="$SB/tmp" "$@"
    value_of "$label" "$expected"
}
gcf 'windows, Clean (the OK button): status 0' 0 OK
check_eq 'windows: one question' 1 "$(zenity_calls)"
ZJ="~$(zenity_call | tr '\036\n' '|~')"
assert_contains 'windows: a question box' "$ZJ" '~--question~'
assert_contains 'windows: the OK button says Clean' "$ZJ" '~--ok-label=Clean~'
assert_contains 'windows: the other says Cancel' "$ZJ" '~--cancel-label=Cancel~'
assert_contains 'windows: the focus starts on Cancel, so Enter never confirms' "$ZJ" '~--default-cancel~'
assert_contains 'windows: the text has the summary' "$ZJ" 'The summary of the cleaning'
gcf 'windows, Cancel: status 1' 1 CANCEL
gcf 'windows, the window closed (answers ran out): it does not go on' 1 ''
gcf 'windows in Spanish, Limpiar: status 0' 0 OK MINTAPP_LANG=es
ZJ="~$(zenity_call | tr '\036\n' '|~')"
assert_contains 'windows in Spanish: the OK button says Limpiar' "$ZJ" '~--ok-label=Limpiar~'
assert_contains 'windows in Spanish: the other says Cancelar' "$ZJ" '~--cancel-label=Cancelar~'

echo "-- The confirmation in windows with a summary that scrolls: Cancel has the focus and Clean is an extra button"
# clean_confirm puts the summary, an empty line and the question in one text. Up to GUI_TEXT_LINES lines it is a
# question box (the case above); with one line more it is a window with a scroll bar (--text-info), whose OK button
# is the one that has the focus: so Cancel is the OK button, Clean an extra button that prints its label, and the
# window's own Cancel says Close. The summary of these cases is made of lines, not of real entries.
LONGCF='q=$(printf "%s\n" "$(msg clean_confirm)" | wrap_text "$GUI_WRAP_COLS" | wc -l)
n=$(( GUI_TEXT_LINES - 1 - q + ${MORE:-1} ))
zenity_usable; UI_ENGINE=gui; HAVE_WHIPTAIL=1
clean_confirm "$(seq -f "Summary line %g" 1 "$n")"; printf "<<%s|%s>>" "$?" "$n"'
lcf() {  # lcf LABEL EXPECTED ANSWER [VAR=val ...]: the status of clean_confirm in windows when the zenity stub answers ANSWER; MORE=0 makes the summary the longest one that still fits a question box; SUMN = its lines
    local label="$1" expected="$2" answer="$3" r; shift 3
    fake_zenity "$answer"
    app_eval "$LONGCF" "${GUI[@]}" TMPDIR="$SB/tmp" "$@"
    r="${OUT#*<<}"; r="${r%%>>*}"; SUMN="${r#*|}"
    check_eq "$label" "$expected" "${r%%|*}"
}
gfresh; allow_clean_confirm
lcf 'scrolls, Clean (the extra button): status 0' 0 EXTRA:Clean
N_SCROLL="$SUMN"
check_eq 'scrolls: one window' 1 "$(zenity_calls)"
ZJ="~$(zenity_call | tr '\036\n' '|~')"
assert_contains 'scrolls: a window with a scroll bar' "$ZJ" '~--text-info~'
assert_not_contains 'scrolls: not a question box' "$ZJ" '~--question~'
assert_contains 'scrolls: the OK button, the one with the focus, says Cancel' "$ZJ" '~--ok-label=Cancel~'
assert_contains 'scrolls: Clean is an extra button' "$ZJ" '~--extra-button=Clean~'
assert_contains 'scrolls: the window'"'"'s own Cancel says Close' "$ZJ" '~--cancel-label=Close~'
assert_not_contains 'scrolls: Clean is never the OK button' "$ZJ" '~--ok-label=Clean~'
ZS="$(zenity_stdin)"
assert_contains 'scrolls: the summary goes in by stdin, from its first line' "$ZS" 'Summary line 1'
assert_contains 'scrolls: to its last' "$ZS" "Summary line $SUMN"
assert_contains 'scrolls: and the question comes after it' "${ZS#*"Summary line $SUMN"}" 'Do you want to continue with the cleanup?'
lcf 'scrolls, Cancel (the OK button, what Enter presses): it does not go on' 1 OK
lcf 'scrolls, Close or Esc: it does not go on' 1 CANCEL
lcf 'scrolls, the window closed (answers ran out): it does not go on' 1 ''
lcf 'scrolls, an extra button that is not Clean: it does not go on' 1 EXTRA:Other
lcf 'scrolls in Spanish, Limpiar (the extra button): status 0' 0 EXTRA:Limpiar MINTAPP_LANG=es
ZJ="~$(zenity_call | tr '\036\n' '|~')"
assert_contains 'scrolls in Spanish: Cancelar is the OK button' "$ZJ" '~--ok-label=Cancelar~'
assert_contains 'scrolls in Spanish: Limpiar is the extra button' "$ZJ" '~--extra-button=Limpiar~'
assert_contains 'scrolls in Spanish: the window'"'"'s own Cancel says Cerrar' "$ZJ" '~--cancel-label=Cerrar~'
assert_contains 'scrolls in Spanish: the question is in Spanish' "$(zenity_stdin)" '¿Quieres continuar con la limpieza?'
lcf 'scrolls in Spanish, the English label is not Limpiar: it does not go on' 1 EXTRA:Clean MINTAPP_LANG=es
lcf 'scrolls in Spanish, Cancelar (the OK button): it does not go on' 1 OK MINTAPP_LANG=es
lcf 'the longest summary that still fits: a question box, Clean its OK button: status 0' 0 OK MORE=0
ZJ="~$(zenity_call | tr '\036\n' '|~')"
assert_contains 'fits: a question box' "$ZJ" '~--question~'
assert_not_contains 'fits: no window with a scroll bar' "$ZJ" '~--text-info~'
assert_contains 'fits: Clean is the OK button' "$ZJ" '~--ok-label=Clean~'
assert_contains 'fits: and Cancel has the focus' "$ZJ" '~--default-cancel~'
check_eq 'the boundary: the summary that scrolls has one line more than the longest one that fits' "$((SUMN + 1))" "$N_SCROLL"

echo "-- A real summary in windows (clean_summary): the complete level scrolls, a single entry is a question box"
# The same two paths as above, now with the summary that the program measures: five entries of the complete
# level are more lines than a question box holds, so it is the window with a scroll bar (what the screenshot
# 2.2 of the README shows); one entry is a question box.
gfresh; allow_clean_confirm
RH="$SB/home"
RFILES=("$RH/.local/share/recently-used.xbel" "$RH/.local/share/Trash/files/a" "$RH/.cache/thumbnails/normal/a.png"
        "$RH/.cache/mozilla/firefox/p/cache2/a" "$RH/.cache/foo/x")
fake_file "${RFILES[0]}" 300; fake_file "${RFILES[1]}" 10; fake_file "${RFILES[2]}" 200
fake_file "${RFILES[3]}" 400; fake_file "${RFILES[4]}" 100
rcf() {  # rcf LABEL EXPECTED ANSWER "ID..." [VAR=val ...]: the status of clean_summary (it measures, shows and asks) in windows at the complete level when the zenity stub answers ANSWER
    local label="$1" expected="$2" answer="$3" ids="$4"; shift 4
    fake_zenity "$answer"
    app_eval "zenity_usable; UI_ENGINE=gui; HAVE_WHIPTAIL=1; CLEAN_LEVEL=C; CLEAN_CHOSEN=($ids); clean_summary; printf '<<%s>>' \"\$?\"" \
        "${GUI[@]}" TMPDIR="$SB/tmp" GUI_STOP_TICKS=400 "$@"
    value_of "$label" "$expected"
}
rfiles_left() { local f n=0; for f in "${RFILES[@]}"; do [ ! -e "$f" ] || n=$((n + 1)); done; printf '%s' "$n"; }
rcf 'real summary, five entries, Clean (the extra button): status 0' 0 EXTRA:Clean 'recent trash thumbnails browsers cache'
check_eq 'real summary: the window of the measuring and the one of the question' 2 "$(zenity_calls)"
ZJ="~$(zenity_call | tr '\036\n' '|~')"
assert_contains 'real summary: the question is a window with a scroll bar' "$ZJ" '~--text-info~'
assert_contains 'real summary: Cancel is its OK button' "$ZJ" '~--ok-label=Cancel~'
assert_contains 'real summary: Clean is an extra button' "$ZJ" '~--extra-button=Clean~'
assert_contains 'real summary: and the window'"'"'s own Cancel says Close' "$ZJ" '~--cancel-label=Close~'
ZS="$(zenity_stdin)"
assert_contains 'real summary: it starts with the title and the level' "$ZS" 'Deep cleanup, complete level. This would be cleaned:'
assert_contains 'real summary: each entry with its size and its files' "$ZS" 'Recent documents: 1 KB, 1 file'
assert_contains 'real summary: the total' "$ZS" 'Total: 1 KB in 5 files'
assert_contains 'real summary: the question comes after the total' "${ZS#*Total:}" 'Do you want to continue with the cleanup?'
check_eq 'real summary: measuring and asking remove nothing' 5 "$(rfiles_left)"
rcf 'real summary, Cancel (the OK button, what Enter presses): status 1' 1 OK 'recent trash thumbnails browsers cache'
rcf 'real summary, Close or Esc: status 1' 1 CANCEL 'recent trash thumbnails browsers cache'
check_eq 'real summary: not confirming removes nothing' 5 "$(rfiles_left)"
rcf 'real summary in Spanish, Limpiar (the extra button): status 0' 0 EXTRA:Limpiar 'recent trash thumbnails browsers cache' MINTAPP_LANG=es
ZJ="~$(zenity_call | tr '\036\n' '|~')"
assert_contains 'real summary in Spanish: Cancelar is the OK button' "$ZJ" '~--ok-label=Cancelar~'
assert_contains 'real summary in Spanish: Limpiar is an extra button' "$ZJ" '~--extra-button=Limpiar~'
assert_contains 'real summary in Spanish: and the window'"'"'s own Cancel says Cerrar' "$ZJ" '~--cancel-label=Cerrar~'
ZS="$(zenity_stdin)"
assert_contains 'real summary in Spanish: the title says the level' "$ZS" 'Limpieza profunda completa.'
assert_contains 'real summary in Spanish: the first entry in Spanish' "$ZS" 'Documentos recientes'
rcf 'real summary in Spanish, Cancelar (the OK button): status 1' 1 OK 'recent trash thumbnails browsers cache' MINTAPP_LANG=es
rcf 'one entry, Clean (the OK button of a question box): status 0' 0 OK 'recent'
ZJ="~$(zenity_call | tr '\036\n' '|~')"
assert_contains 'one entry: the summary fits a question box' "$ZJ" '~--question~'
assert_not_contains 'one entry: no window with a scroll bar' "$ZJ" '~--text-info~'
assert_contains 'one entry: Clean is the OK button' "$ZJ" '~--ok-label=Clean~'
assert_contains 'one entry: and Cancel has the focus, so Enter never confirms' "$ZJ" '~--default-cancel~'
rcf 'one entry, Cancel: status 1' 1 CANCEL 'recent'
check_eq 'one entry: still nothing removed' 5 "$(rfiles_left)"

# ---- D3 (P.4d, step 3): what runs, entry by entry (clean_run_entries, clean_run_step) ----------
echo "-- Running the entries (clean_run_entries): only what the summary showed as work, one at a time"
new_sandbox; mkdir -p "$SB/tmp"; sandbox_chown
# The entries are given a fixed outcome by a clean_item of this test: ID -> "state|files|bytes|failed|note" at run time.
# CLEAN_M_* is what the summary measured (state, files, bytes, failed), at the position of each entry of CLEAN_CHOSEN.
RUN_SETUP='
CLEAN_LEVEL=C; CLEAN_FREED_FILES=0; CLEAN_FREED_BYTES=0
CLEAN_CHOSEN=(recent trash browsers cache apt_cache journal clipboard x11_logs rc_config crash)
CLEAN_M_STATE=(ok ok ok ok ok ok ok ok ok unavailable)
CLEAN_M_FILES=(3 5 1 0 4 2 0 6 2 0)
CLEAN_M_BYTES=(300 50 10 0 40 20 0 60 0 0)
CLEAN_M_FAILED=(0 0 0 0 0 0 0 0 0 0)
CLEAN_M_NOTE=("" "" "" "" "" "" "" "" "" "")
declare -A FK=(
    [recent]="ok|3|300|0|"           [trash]="ok|3|30|2|"       [browsers]="ok|1|10|0|Firefox"
    [apt_cache]="busy|0|0|0|apt"     [journal]="unavailable|0|0|0|"
    [clipboard]="ok|0|0|0|xclip"     [x11_logs]="ok|0|0|0|"     [rc_config]="ok|2|0|0|"
)
RAN=(); SEEN=(); LIST=()
clean_item() {
    local st files bytes failed note
    IFS="|" read -r st files bytes failed note <<< "${FK[$2]}"
    RAN+=("$1:$2:$3"); SEEN+=("${CLEAN_R_STATE[*]-}"); LIST+=("$([ -f "${CLEAN_OPENFILE:-/nonexistent}" ] && echo list || echo nolist)")
    CLEAN_ITEM_STATE="$st" CLEAN_ITEM_FILES="$files" CLEAN_ITEM_BYTES="$bytes" CLEAN_ITEM_SKIPPED=0 CLEAN_ITEM_FAILED="$failed" CLEAN_ITEM_NOTE="$note" CLEAN_ITEM_WHERE=""
}'
RUN_SHOW='j() { (IFS="|"; printf "%s" "$*"); }
printf "<<state=%s\nwhy=%s\nfiles=%s\nbytes=%s\nfailed=%s\nnote=%s\nfreed=%s|%s\nran=%s\nlist=%s\nafter=[%s]\nseen3=%s\n>>" \
    "$(j "${CLEAN_R_STATE[@]}")" "$(j "${CLEAN_R_WHY[@]}")" "$(j "${CLEAN_R_FILES[@]}")" "$(j "${CLEAN_R_BYTES[@]}")" "$(j "${CLEAN_R_FAILED[@]}")" \
    "$(j "${CLEAN_R_NOTE[@]}")" "$CLEAN_FREED_FILES" "$CLEAN_FREED_BYTES" "$(j "${RAN[@]}")" "$(j "${LIST[@]}")" "${CLEAN_OPENFILE:-}" "${SEEN[2]:-}"'
app_eval "$RUN_SETUP; clean_run_entries; $RUN_SHOW" TMPDIR="$SB/tmp" MINTAPP_LANG=en
RV="${OUT#*<<}"; RV="${RV%%>>*}"
kv() { awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' <<< "$RV"; }
check_eq 'run: what each entry did (an entry that fails in part is "failed", the empty ones are skipped)' \
    'done|failed|done|skipped|skipped|skipped|done|skipped|done|skipped' "$(kv state)"
check_eq 'run: why each skipped one was (nothing to clean, in use, not available, nothing left at run time)' \
    '|||empty|busy|unavailable||empty||unavailable' "$(kv why)"
check_eq 'run: only the entries of class work ran, in order, and only to run (never to measure)' \
    'run:recent:C|run:trash:C|run:browsers:C|run:apt_cache:C|run:journal:C|run:clipboard:C|run:x11_logs:C|run:rc_config:C' "$(kv ran)"
check_eq 'run: the files each one removed (the packages, for rc_config)' '3|3|1|0|0|0|0|0|2|0' "$(kv files)"
check_eq 'run: the bytes each one removed' '300|30|10|0|0|0|0|0|0|0' "$(kv bytes)"
check_eq 'run: what could not be removed' '0|2|0|0|0|0|0|0|0|0' "$(kv failed)"
check_eq 'run: the note of each (open browsers, what holds apt)' '||Firefox||apt||xclip|||' "$(kv note)"
check_eq 'run: the total adds what was removed, also by the entry that failed in part, and not the packages' '7|340' "$(kv freed)"
check_eq 'run: the list of what is open exists while every entry runs' 'list|list|list|list|list|list|list|list' "$(kv list)"
check_eq 'run: and is gone at the end' '[]' "$(kv after)"
check_eq 'run: it leaves no list in the folder of temporary files' '0' "$(find "$SB/tmp" -name 'mintapp-clean.*' | wc -l)"
check_eq 'run: while the third entry runs, the two before are done and failed, and this one is running' 'done failed running' "$(kv seen3)"

echo "-- Running the entries: the line that says which one is running, and a list of what is open that could not be made"
runout() {  # runout INTERFACE [VAR=val ...]: OUT of clean_run_entries (the text it prints), with the entries of this test
    local code; code="$(eng "$1")"; shift
    app_eval "$RUN_SETUP; $code; clean_run_entries" "$@"
}
runout text TMPDIR="$SB/tmp" MINTAPP_LANG=en
RO="$OUT"
check_eq 'text: one line "Cleaning: NAME" for each entry that runs (eight)' 8 "$(grep -c '^Cleaning: ' <<< "$RO")"
assert_contains 'text: the first one' "$RO" 'Cleaning: Recent documents'
assert_contains 'text: and the last one that runs' "$RO" 'Cleaning: Leftover settings'
assert_not_contains 'text: an entry with nothing to clean says nothing' "$RO" 'Other caches'
assert_not_contains 'text: nor one that this system lacks' "$RO" 'Crash reports'
check_eq 'text: the lines come in the order of the catalog' 'Recent documents|Trash|Browser caches|Package cache|System journal|Clipboard|X11 error log|Leftover settings' \
    "$(sed -n 's/^Cleaning: //p' <<< "$RO" | paste -sd'|')"
runout gui TMPDIR="$SB/tmp" MINTAPP_LANG=en
check_eq 'windows: the same lines, written as they are (the progress window shows the last one)' 8 "$(grep -c '^Cleaning: ' <<< "$OUT")"
runout text TMPDIR="$SB/tmp" MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'in Spanish: the line says Limpiando and the name in Spanish' "$OUT" 'Limpiando: Documentos recientes'
# A line wider than the screen is what tells the two branches of clean_run_step apart: the text mode wraps it to the terminal
# (two rows per entry), the windows write it whole, because the progress window wraps it by itself.
LONGN='a very long name made of many short words, so that the line is wider than the eighty columns of the screen'
LONGCODE="clean_name() { printf '%s' '$LONGN'; }"
app_eval "$RUN_SETUP; $(eng text); $LONGCODE; clean_run_entries" TMPDIR="$SB/tmp" MINTAPP_LANG=en
check_eq 'text: a line wider than the screen is wrapped, two rows for each of the eight entries' 16 "$(grep -c . <<< "$OUT")"
assert_not_contains 'text: and none of its rows holds the whole line' "$OUT" "Cleaning: $LONGN"
app_eval "$RUN_SETUP; $(eng gui); $LONGCODE; clean_run_entries" TMPDIR="$SB/tmp" MINTAPP_LANG=en
check_eq 'windows: the same line is written whole, one row for each of the eight entries' 8 "$(grep -c "^Cleaning: $LONGN\$" <<< "$OUT")"
check_eq 'windows: and nothing else is written' 8 "$(grep -c . <<< "$OUT")"
app_eval "$RUN_SETUP; clean_run_entries >/dev/null; $RUN_SHOW" TMPDIR=/nonexistent/folder MINTAPP_LANG=en
RV="${OUT#*<<}"; RV="${RV%%>>*}"
check_eq 'no list of what is open could be made: the cleaning goes on, with the same result' \
    'done|failed|done|skipped|skipped|skipped|done|skipped|done|skipped' "$(kv state)"
check_eq 'no list of what is open: every entry ran without one' 'nolist|nolist|nolist|nolist|nolist|nolist|nolist|nolist' "$(kv list)"
check_eq 'no list of what is open: the variable stays empty' '[]' "$(kv after)"

echo "-- Running the entries: what the entry removed at run time says whether it is done"
# Files and bytes of 0 mean nothing was left (skipped, empty); a size without files, or files of 0 bytes, are work done, as in
# the summary; a failure is failed even if nothing went.
app_eval 'CLEAN_LEVEL=C; CLEAN_FREED_FILES=0; CLEAN_FREED_BYTES=0
CLEAN_CHOSEN=(cache recent trash tmp)
CLEAN_M_STATE=(ok ok ok ok); CLEAN_M_FILES=(1 1 1 1); CLEAN_M_BYTES=(10 10 10 10); CLEAN_M_FAILED=(0 0 0 0); CLEAN_M_NOTE=("" "" "" "")
declare -A FK=([cache]="ok|0|7|0" [recent]="ok|2|0|0" [trash]="ok|0|0|0" [tmp]="ok|0|0|1")
clean_item() {
    local st f b x
    IFS="|" read -r st f b x <<< "${FK[$2]}"
    CLEAN_ITEM_STATE="$st" CLEAN_ITEM_FILES="$f" CLEAN_ITEM_BYTES="$b" CLEAN_ITEM_SKIPPED=0 CLEAN_ITEM_FAILED="$x" CLEAN_ITEM_NOTE="" CLEAN_ITEM_WHERE=""
}
j() { (IFS="|"; printf "%s" "$*"); }
clean_run_entries >/dev/null
printf "<<%s;%s;%s>>" "$(j "${CLEAN_R_STATE[@]}")" "$(j "${CLEAN_R_WHY[@]}")" "$CLEAN_FREED_FILES|$CLEAN_FREED_BYTES"' TMPDIR="$SB/tmp" MINTAPP_LANG=en
value_of 'run: a size without files is done, files of 0 bytes are done, nothing left is skipped (empty), a failure is failed' \
    'done|done|skipped|failed;||empty|;2|7'

# ---- D3 (P.4d, steps 3 and 4): the whole run (clean_run_chosen) and clean_has_failed ------------
echo "-- The whole run (clean_run_chosen): the rights first, then the record, the entries, the record closed"
crfresh() {
    new_sandbox; mkdir -p "$SB/tmp" "$SB/deny"
    printf '#!/bin/sh\necho "sudo $*" >> "%s/state/sudo.log"\nexit 1\n' "$SB" > "$SB/deny/sudo"; chmod 755 "$SB/deny/sudo"
    sandbox_chown
}
# What the entries measured (CLEAN_M_*, at the position of each) and what each does when it runs (a clean_item of this test:
# ID -> "state|files|bytes|failed|note"). REC keeps the status that the record has when each entry starts.
CRC_SETUP='
CLEAN_LEVEL=C
CLEAN_CHOSEN=(recent trash browsers cache)
CLEAN_M_STATE=(ok ok ok ok); CLEAN_M_FILES=(3 5 1 0); CLEAN_M_BYTES=(300 50 10 0); CLEAN_M_FAILED=(0 0 0 0); CLEAN_M_NOTE=("" "" "" "")
CLEAN_TOTAL_FILES=9 CLEAN_TOTAL_BYTES=360
declare -A FK=([recent]="ok|3|300|0|" [trash]="ok|3|30|2|" [browsers]="ok|1|10|0|" [cache]="ok|0|0|0|"
               [rotated_logs]="ok|1|5|0|" [tmp]="ok|2|20|0|")
RAN=(); REC=(); ACT=(); ARC=()
clean_item() {
    local st files bytes failed note
    IFS="|" read -r st files bytes failed note <<< "${FK[$2]}"
    RAN+=("$2"); REC+=("$(sed -n "s/^# Status: //p" "$LAST_RECORD" 2>/dev/null | head -n 1)")
    ACT+=("$ACTIVE_CLEAN"); ARC+=("$([ -n "$ACTIVE_RECORD" ] && [ "$ACTIVE_RECORD" = "$LAST_RECORD" ] && echo same || echo other)")
    CLEAN_ITEM_STATE="$st" CLEAN_ITEM_FILES="$files" CLEAN_ITEM_BYTES="$bytes" CLEAN_ITEM_SKIPPED=0 CLEAN_ITEM_FAILED="$failed" CLEAN_ITEM_NOTE="$note" CLEAN_ITEM_WHERE=""
}'
CRC_SHOW='j() { (IFS="|"; printf "%s" "$*"); }
printf "<<st=%s\nran=%s\nrec=%s\nstate=%s\nfreed=%s|%s\nactive=[%s]|%s\nduring=%s\nduring_rec=%s\nlast=[%s]\n>>" "$st" "$(j "${RAN[@]+"${RAN[@]}"}")" "$(j "${REC[@]+"${REC[@]}"}")" \
    "$(j "${CLEAN_R_STATE[@]+"${CLEAN_R_STATE[@]}"}")" "$CLEAN_FREED_FILES" "$CLEAN_FREED_BYTES" "${ACTIVE_RECORD:-}" "$ACTIVE_CLEAN" \
    "$(j "${ACT[@]+"${ACT[@]}"}")" "$(j "${ARC[@]+"${ARC[@]}"}")" "$LAST_RECORD"'
crc() {  # crc CODE [VAR=val ...]: clean_run_chosen after CODE; CRV holds what it left (crk KEY reads one)
    local code="$1"; shift
    app_eval "$CRC_SETUP; $code; clean_run_chosen; st=\$?; $CRC_SHOW" "$@"
    CRV="${OUT#*<<}"; CRV="${CRV%%>>*}"
}
crc_ui() {  # crc_ui INTERFACE CODE [VAR=val ...]: crc with the program running with that interface
    local interface="$1" code="$2"; shift 2
    crc "$(eng "$interface"); $code" "$@"
}
crk() { awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' <<< "$CRV"; }
crec() { local f; f="$(clean_records | head -n 1)"; [ -z "$f" ] || grep -v '^# Date:' "$f"; }   # the record, without its date

crfresh
crc 'FK[trash]="ok|3|30|2|"' MINTAPP_LANG=en
check_eq 'run: status 0, also when an entry failed (the failure is told by the result)' 0 "$(crk st | sed 's/^st=//')"
check_eq 'run: only the entries with work run, in order (the one that measured nothing does not)' 'recent|trash|browsers' "$(crk ran)"
check_eq 'run: the record already says "started" when each entry begins' 'started|started|started' "$(crk rec)"
check_eq 'run: what each one did' 'done|failed|done|skipped' "$(crk state)"
check_eq 'run: the total adds what the three removed' '7|340' "$(crk freed)"
check_eq 'run: nothing is left active at the end (on_exit has nothing to write)' '[]|0' "$(crk active)"
check_eq 'run: while each entry runs, the run is marked as a cleaning (a signal then leaves a cleaning record)' '1|1|1' "$(crk during)"
check_eq 'run: and the record that on_exit would write is the one the run began' 'same|same|same' "$(crk during_rec)"
check_eq 'run: one record, and only one' 1 "$(clean_records | grep -c .)"
check_eq 'run: its name has the date, the process and the sequence' 1 "$(clean_records | grep -cE '/clean-[0-9]{8}-[0-9]{6}-[0-9]+-1\.txt$')"
check_eq 'run: and it is a private file of the state folder (mode 600)' 600 "$(stat -c %a "$(clean_records | head -n 1)")"
check_eq 'run: the record, closed as failed, says what each entry did, what was measured and what was recovered' \
'# MintApp Remover cleaning record
# Status: failed (1 entry not cleaned completely)
# Level: complete
#
# Entries:
recent: done, files 3, bytes 300
trash: failed, files 3, bytes 30, failed 2
browsers: done, files 1, bytes 10
cache: skipped (empty)
#
# Measured: files 9, bytes 360
# Recovered: files 7, bytes 340' "$(crec)"
check_eq 'run: the record is written by a rename: no temporary left in the state folder' 1 "$(find "$SB/home/.local/state/mintapp-remover" -mindepth 1 -maxdepth 1 | wc -l)"

crfresh
crc 'FK[trash]="ok|3|30|0|"' MINTAPP_LANG=en
check_eq 'run, nothing failed: the record closes as completed' '# Status: completed' "$(crec | sed -n 2p)"
check_eq 'run, nothing failed: the total' '7|340' "$(crk freed)"
crfresh
crc 'FK[trash]="ok|3|30|2|"; FK[browsers]="ok|1|10|1|"'
check_eq 'run, two failed: the record says how many (entries, plural)' '# Status: failed (2 entries not cleaned completely)' "$(crec | sed -n 2p)"
crfresh
crc 'CLEAN_LEVEL=S' MINTAPP_LANG=en
check_eq 'run, simple level: the record says so' '# Level: simple' "$(crec | sed -n 3p)"

echo "-- The whole run: with nothing to clean, nothing is recorded; a run that starts again forgets the last one"
crfresh
crc 'CLEAN_M_FILES=(0 0 0 0); CLEAN_M_BYTES=(0 0 0 0)'
check_eq 'nothing to clean: status 0, no entry runs' '0|' "$(crk st | sed 's/^st=//')|$(crk ran)"
check_eq 'nothing to clean: no record is written' 0 "$(clean_records | grep -c .)"
check_eq 'nothing to clean: every entry is skipped as empty, none is left running' 'skipped|skipped|skipped|skipped' "$(crk state)"
crfresh
OLDREC="$SB/home/.local/state/mintapp-remover/clean-19990101-000000-1-1.txt"
mkdir -p "${OLDREC%/*}"; printf '# Status: started\nan earlier run\n' > "$OLDREC"; sandbox_chown
crc "CLEAN_M_FILES=(0 0 0 0); CLEAN_M_BYTES=(0 0 0 0); LAST_RECORD=$OLDREC"
check_eq 'nothing to clean, after a run that left its record: the path of that record is not kept' '[]' "$(crk last)"
check_eq 'nothing to clean: and the earlier record is not rewritten as if it were this run' '# Status: started|an earlier run' "$(paste -sd'|' "$OLDREC")"
crfresh
crc 'CLEAN_R_STATE=(failed failed failed failed failed failed); CLEAN_R_FILES=(9 9 9 9 9 9); CLEAN_FREED_FILES=99; CLEAN_FREED_BYTES=999; LAST_RECORD=/old; ACTIVE_RECORD=/old; ACTIVE_CLEAN=1; FK[trash]="ok|3|30|0|"'
check_eq 'a second run starts from nothing: the entries of the last one do not remain' 'done|done|done|skipped' "$(crk state)"
check_eq 'a second run: the total is of this run only' '7|340' "$(crk freed)"
check_eq 'a second run: it has its own record, and closes the active one' '[]|0' "$(crk active)"

echo "-- The whole run: the rights are asked before anything is recorded or run (text)"
crfresh
crc_ui tui 'CLEAN_CHOSEN=(tmp rotated_logs); CLEAN_M_STATE=(ok ok); CLEAN_M_FILES=(2 1); CLEAN_M_BYTES=(20 5); CLEAN_M_FAILED=(0 0); CLEAN_M_NOTE=("" ""); CLEAN_TOTAL_FILES=3 CLEAN_TOTAL_BYTES=25' \
    MINTAPP_LANG=en MINTAPP_SUDO="$SB/deny/sudo"
check_eq 'rights denied: the status is the one of no rights (77)' 77 "$(crk st | sed 's/^st=//')"
check_eq 'rights denied: nothing ran' '' "$(crk ran)"
check_eq 'rights denied: no record, not even a "started" one' 0 "$(clean_records | grep -c .)"
check_eq 'rights denied: no entry was marked' '' "$(crk state)"
check_eq 'rights denied: sudo -v was the only call' 'sudo -v' "$(sudo_log)"
check_eq 'rights denied: nothing is active, so on_exit would write nothing' '[]|0' "$(crk active)"
: > "$SB/state/sudo.log"
crc_ui tui 'CLEAN_CHOSEN=(tmp rotated_logs); CLEAN_M_STATE=(ok ok); CLEAN_M_FILES=(2 1); CLEAN_M_BYTES=(20 5); CLEAN_M_FAILED=(0 0); CLEAN_M_NOTE=("" ""); CLEAN_TOTAL_FILES=3 CLEAN_TOTAL_BYTES=25' \
    MINTAPP_LANG=en
check_eq 'rights given: status 0, both entries ran' '0|tmp|rotated_logs' "$(crk st | sed 's/^st=//')|$(crk ran | tr '|' '|')"
check_eq 'rights given: sudo -v was asked, once' 'sudo -v' "$(sudo_log)"
check_eq 'rights given: the record is closed as completed' '# Status: completed' "$(crec | sed -n 2p)"
: > "$SB/state/sudo.log"
crc_ui tui 'CLEAN_CHOSEN=(tmp rotated_logs); CLEAN_M_STATE=(ok ok); CLEAN_M_FILES=(2 0); CLEAN_M_BYTES=(20 0); CLEAN_M_FAILED=(0 0); CLEAN_M_NOTE=("" ""); CLEAN_TOTAL_FILES=2 CLEAN_TOTAL_BYTES=20' \
    MINTAPP_LANG=en MINTAPP_SUDO="$SB/deny/sudo"
check_eq 'the entry with rights has nothing to clean: the password is not asked, and the other one runs' '0|tmp' "$(crk st | sed 's/^st=//')|$(crk ran)"
check_eq 'no rights needed: sudo is not even called' '' "$(sudo_log)"

echo "-- The whole run: what is seen (text) and the progress window (windows)"
crfresh
crc_ui text 'FK[trash]="ok|3|30|0|"' MINTAPP_LANG=en
check_eq 'text: a line for each entry that runs goes to the terminal' 'Cleaning: Recent documents|Cleaning: Trash|Cleaning: Browser caches' "$(grep '^Cleaning: ' <<< "$OUT" | paste -sd'|')"
crfresh; fake_zenity ''
crc 'zenity_usable; UI_ENGINE=gui; HAVE_WHIPTAIL=1; FK[trash]="ok|3|30|0|"' "${GUI[@]}" TMPDIR="$SB/tmp" GUI_STOP_TICKS=400
check_eq 'windows: the run is the same (the same entries, the same record)' 'recent|trash|browsers' "$(crk ran)"
check_eq 'windows: a single progress window for the whole run' 1 "$(zenity_calls)"
assert_contains 'windows: it is a progress window' "~$(zenity_call | tr '\036\n' '|~')" '~--progress~'
assert_contains 'windows: with the text of the cleaning' "$(zenity_call | tr '\036\n' '|~')" 'Cleaning'
assert_not_contains 'windows: the lines of each entry do not go to the terminal (the window shows the last)' "$OUT" 'Cleaning: Recent'
check_eq 'windows: the record is closed as completed' '# Status: completed' "$(crec | sed -n 2p)"

echo "-- Failures (clean_has_failed): only an entry that failed counts"
hf() {  # hf LABEL EXPECTED STATES: the status of clean_has_failed (0 = something failed) with those states
    app_eval "CLEAN_R_STATE=($3); clean_has_failed; printf '<<%s>>' \$?"
    value_of "$1" "$2"
}
hf 'no run yet: nothing failed' 1 ''
hf 'all done: nothing failed' 1 'done done done'
hf 'skipped is not a failure (busy, empty, unavailable)' 1 'done skipped skipped'
hf 'one that is still running is not one that failed' 1 'done running'
hf 'one failed among the others' 0 'done failed skipped'
hf 'only one entry, and it failed' 0 'failed'
hf 'the last one failed' 0 'done done failed'
# ---- D3 (P.4d, step 3): the result (clean_result_text) ------------------------------------------
echo "-- The result (clean_result_text): what was cleaned, what failed, what was left out, the space recovered"
# rtext LEVEL FREED_FILES FREED_BYTES TABLE [VAR=val ...]: puts in RES what clean_result_text says, its \n sequences made line
# breaks. TABLE has one row per entry, in the order of CLEAN_CHOSEN: "id|state|why|files|bytes|failed|note" (what clean_run_entries keeps).
rtext() {
    local level="$1" ff="$2" fb="$3" table="$4" id st why files bytes failed note v ids="" sts="" whys="" fls="" bys="" fas="" nts=""
    shift 4
    while IFS='|' read -r id st why files bytes failed note; do
        [ -n "$id" ] || continue
        printf -v v ' %q' "$id"; ids+="$v"; printf -v v ' %q' "$st"; sts+="$v"; printf -v v ' %q' "$why"; whys+="$v"
        printf -v v ' %q' "$files"; fls+="$v"; printf -v v ' %q' "$bytes"; bys+="$v"; printf -v v ' %q' "$failed"; fas+="$v"
        printf -v v ' %q' "$note"; nts+="$v"
    done <<< "$table"
    app_eval "CLEAN_LEVEL=$level; CLEAN_CHOSEN=($ids); CLEAN_R_STATE=($sts); CLEAN_R_WHY=($whys); CLEAN_R_FILES=($fls); CLEAN_R_BYTES=($bys)
CLEAN_R_FAILED=($fas); CLEAN_R_NOTE=($nts); CLEAN_FREED_FILES=$ff; CLEAN_FREED_BYTES=$fb; clean_result_text; printf '<<%b>>' \"\$REPLY\"" "$@"
    v="${OUT#*<<}"; RES="${v%%>>*}"
}
new_sandbox
rtext C 9 360 'recent|done||3|300|0|
trash|done||5|50|0|
browsers|done||1|10|0|Firefox'
check_eq 'result: the title, what was cleaned with its size and files, the open browser, the space recovered' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 3 files\n  Trash: 1 KB, 5 files\n  Browser caches: 1 KB, 1 file\n\nOpen browsers, skipped: Firefox\n\nSpace recovered: 1 KB in 9 files' "$RES"
rtext C 6 330 'recent|done||3|300|0|
trash|failed||3|30|2|'
check_eq 'result: an entry that failed in part goes under "With failures", with what was removed and what was left' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 3 files\n\nWith failures:\n  Trash: 1 KB, 3 files; 2 files not cleaned\n\nSpace recovered: 1 KB in 6 files' "$RES"
rtext C 0 0 'trash|failed||0|0|1|'
check_eq 'result: only a failure, with nothing removed: no "Cleaned" heading, no size, and no space recovered' \
$'Deep cleanup, complete level. Result:\n\nWith failures:\n  Trash: 1 file not cleaned' "$RES"
rtext C 4 40 'trash|failed||4|40|1|
recent|done||0|0|0|'
check_eq 'result: an entry that did nothing but is "done" is listed without size (the failures come after the cleaned)' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents\n\nWith failures:\n  Trash: 1 KB, 4 files; 1 file not cleaned\n\nSpace recovered: 1 KB in 4 files' "$RES"
rtext C 3 3000 'recent|done||3|3000|0|
trash|failed||0|0|2|'
check_eq 'result: two entries failed: "2 files not cleaned" (plural), and the two blocks keep the order of the run' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 3 KB, 3 files\n\nWith failures:\n  Trash: 2 files not cleaned\n\nSpace recovered: 3 KB in 3 files' "$RES"
rtext C 2 20 'thumbnails|done||1|10|0|
trash|done||1|10|0|'
check_eq 'result: the entries come in the order they were chosen, not in the order of the catalog' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Thumbnails: 1 KB, 1 file\n  Trash: 1 KB, 1 file\n\nSpace recovered: 1 KB in 2 files' "$RES"
rtext C 2 20 'trash|done||1|10|0|
thumbnails|done||1|10|0|'
check_eq 'result: the same two the other way round' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Trash: 1 KB, 1 file\n  Thumbnails: 1 KB, 1 file\n\nSpace recovered: 1 KB in 2 files' "$RES"

echo "-- The result: the special entries (clipboard, journal, leftover settings), which do not say files and bytes like the others"
rtext C 0 0 'clipboard|done||0|0|0|xclip
rc_config|done||2|0|0|'
check_eq 'result: the clipboard says with which tool it was emptied, the leftover settings count packages, and no space is said (no files)' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Clipboard: emptied (xclip)\n  Leftover settings: 2 packages' "$RES"
assert_not_contains 'result: the note of the clipboard is not taken for an open browser' "$RES" 'Open browsers'
rtext C 0 0 'rc_config|done||1|0|0|'
check_eq 'result: one package, in the singular' $'Deep cleanup, complete level. Result:\n\nCleaned:\n  Leftover settings: 1 package' "$RES"
rtext C 0 0 'clipboard|failed||0|0|1|xclip'
check_eq 'result: a clipboard that failed says that the cleaning failed (not "files")' \
$'Deep cleanup, complete level. Result:\n\nWith failures:\n  Clipboard: cleaning failed' "$RES"
rtext C 2 2048 'journal|failed||2|2048|1|'
check_eq 'result: a journal that failed in part says what it freed and that the cleaning failed' \
$'Deep cleanup, complete level. Result:\n\nWith failures:\n  System journal: 2 KB, 2 files; cleaning failed\n\nSpace recovered: 2 KB in 2 files' "$RES"
rtext C 0 0 'rc_config|failed||1|0|2|'
check_eq 'result: leftover settings that purged one package and left two: packages, not files' \
$'Deep cleanup, complete level. Result:\n\nWith failures:\n  Leftover settings: 1 package; 2 packages not cleaned' "$RES"
rtext C 0 0 'rc_config|failed||0|0|1|'
check_eq 'result: leftover settings with one package left: singular' \
$'Deep cleanup, complete level. Result:\n\nWith failures:\n  Leftover settings: 1 package not cleaned' "$RES"
rtext C 0 0 'rc_config|failed||0|0|0|changed'
check_eq 'result: leftover settings whose plan changed: nothing was purged, and it says why' \
$'Deep cleanup, complete level. Result:\n\nWith failures:\n  Leftover settings: the plan changed, nothing was purged.' "$RES"
rtext C 0 0 'rc_config|failed||2|0|1|changed'
check_eq 'result: a changed plan wins over the count of packages left' \
$'Deep cleanup, complete level. Result:\n\nWith failures:\n  Leftover settings: 2 packages; the plan changed, nothing was purged.' "$RES"
rtext C 0 0 'clipboard|done||0|0|0|'
check_eq 'result: a clipboard emptied by a tool with no name still says it' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Clipboard: emptied ()' "$RES"

echo "-- The result: what was left out, in the order of the summary, and the case of nothing cleaned"
rtext C 2 20 'recent|done||2|20|0|
browsers|skipped|empty|0|0|0|Firefox, Chromium
cache|skipped|empty|0|0|0|
crash|skipped|unavailable|0|0|0|
apt_cache|skipped|busy|0|0|0|apt
rc_config|skipped|unknown|0|0|0|'
check_eq 'result: open browsers, nothing to clean, not available, in use (with what holds it) and not worked out, in that order' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 2 files\n\nOpen browsers, skipped: Firefox, Chromium\nNothing to clean: Browser caches, Other caches\nNot available on this system: Crash reports\nIn use now, skipped: Package cache (apt)\nCould not be worked out: Leftover settings\n\nSpace recovered: 1 KB in 2 files' "$RES"
rtext C 0 0 'cache|skipped|empty|0|0|0|
journal|skipped|unavailable|0|0|0|'
check_eq 'result: nothing cleaned says so after the notes, and says no space' \
$'Deep cleanup, complete level. Result:\n\nNothing to clean: Other caches\nNot available on this system: System journal\n\nNothing was cleaned.' "$RES"
rtext C 0 0 'cache|skipped|empty|0|0|0|'
check_eq 'result: one entry with nothing' $'Deep cleanup, complete level. Result:\n\nNothing to clean: Other caches\n\nNothing was cleaned.' "$RES"
rtext C 0 0 ''
check_eq 'result: no entry at all: the title and that nothing was cleaned' $'Deep cleanup, complete level. Result:\n\nNothing was cleaned.' "$RES"
rtext C 0 0 'cache|skipped||0|0|0|
tmp|skipped|surprise|0|0|0|'
check_eq 'result: a skipped entry with no reason, or one the program does not know, counts as nothing to clean' \
$'Deep cleanup, complete level. Result:\n\nNothing to clean: Other caches, Temporary files\n\nNothing was cleaned.' "$RES"
rtext C 0 0 'browsers|skipped|empty|0|0|0|Firefox'
check_eq 'result: a browsers entry with nothing to clean still names the browser that was open' \
$'Deep cleanup, complete level. Result:\n\nOpen browsers, skipped: Firefox\nNothing to clean: Browser caches\n\nNothing was cleaned.' "$RES"
rtext C 1 10 'recent|done||1|10|0|
apt_cache|skipped|busy|0|0|0|apt'
check_eq 'result: one that is in use is a note, not a failure, and the rest is still counted' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 1 file\n\nIn use now, skipped: Package cache (apt)\n\nSpace recovered: 1 KB in 1 file' "$RES"
app_eval 'CLEAN_LEVEL=C; CLEAN_CHOSEN=(recent cache); CLEAN_R_STATE=(done skipped); CLEAN_R_WHY=("" empty); CLEAN_R_FILES=(1 0); CLEAN_R_BYTES=(10 0); CLEAN_R_FAILED=(0 0); CLEAN_R_NOTE=("" "")
CLEAN_FREED_FILES=1; CLEAN_FREED_BYTES=10; clean_result_text; case "$REPLY" in *$'"'"'\n'"'"'*) r=real-line-breaks ;; *) r=escape-sequences ;; esac; printf "<<%s>>" "$r"'
value_of 'result: REPLY holds \n sequences, not line breaks (show_removal_result and the windows turn them into lines)' escape-sequences

echo "-- The result: the space recovered (rounded up to KB, as the summary does) and the counts"
rtext C 1 1 'recent|done||1|1|0|'
check_eq 'space: one byte is 1 KB, for the entry and for the total' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 1 file\n\nSpace recovered: 1 KB in 1 file' "$RES"
rtext C 1 1024 'recent|done||1|1024|0|'
check_eq 'space: 1024 bytes are exactly 1 KB' $'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 1 file\n\nSpace recovered: 1 KB in 1 file' "$RES"
rtext C 1 1025 'recent|done||1|1025|0|'
check_eq 'space: 1025 bytes are 2 KB (rounded up, never down)' $'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 2 KB, 1 file\n\nSpace recovered: 2 KB in 1 file' "$RES"
rtext C 1 0 'recent|done||1|0|0|'
check_eq 'space: a file of 0 bytes is a file that was removed: "0 KB, 1 file"' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 0 KB, 1 file\n\nSpace recovered: 0 KB in 1 file' "$RES"
rtext C 12 3145728 'cache|done||12|3145728|0|'
check_eq 'space: 3 MB, with the decimal point' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Other caches: 3.0 MB, 12 files\n\nSpace recovered: 3.0 MB in 12 files' "$RES"
rtext C 3 3 'recent|done||1|1|0|
trash|done||1|1|0|
cache|done||1|1|0|'
check_eq 'space: the total is rounded once, from the sum of bytes, not entry by entry (three bytes are 1 KB, not 3)' \
$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 1 file\n  Trash: 1 KB, 1 file\n  Other caches: 1 KB, 1 file\n\nSpace recovered: 1 KB in 3 files' "$RES"
rtext C 2 1572864 'cache|done||2|1572864|0|' MINTAPP_LANG=es MINTAPP_ASCII=0
check_eq 'space, Spanish: the decimal comma' \
$'Limpieza profunda completa. Resultado:\n\nLimpiado:\n  Resto de cachés: 1,5 MB, 2 archivos\n\nEspacio recuperado: 1,5 MB en 2 archivos' "$RES"
ev 'amount of files, 1: singular' '1 file' 'clean_files_text 1; printf "<<%s>>" "$REPLY"'
ev 'amount of files, 0: plural' '0 files' 'clean_files_text 0; printf "<<%s>>" "$REPLY"'
ev 'amount of files, 2: plural' '2 files' 'clean_files_text 2; printf "<<%s>>" "$REPLY"'
ev 'amount of packages, 1: singular' '1 package' 'clean_pkgs_text 1; printf "<<%s>>" "$REPLY"'
ev 'amount of packages, 0: plural' '0 packages' 'clean_pkgs_text 0; printf "<<%s>>" "$REPLY"'
ev 'amount of packages, 12: plural' '12 packages' 'clean_pkgs_text 12; printf "<<%s>>" "$REPLY"'
ev 'amount of files, Spanish: archivo y archivos' '1 archivo|2 archivos' 'clean_files_text 1; a="$REPLY"; clean_files_text 2; printf "<<%s|%s>>" "$a" "$REPLY"' MINTAPP_LANG=es
ev 'amount of packages, Spanish: paquete y paquetes' '1 paquete|2 paquetes' 'clean_pkgs_text 1; a="$REPLY"; clean_pkgs_text 2; printf "<<%s|%s>>" "$a" "$REPLY"' MINTAPP_LANG=es

echo "-- The result in Spanish: the same order, the same groups"
rtext C 9 360 'recent|done||3|300|0|
trash|failed||3|30|2|
browsers|done||1|10|0|Firefox
cache|skipped|empty|0|0|0|
crash|skipped|unavailable|0|0|0|
apt_cache|skipped|busy|0|0|0|apt
rc_config|skipped|unknown|0|0|0|' MINTAPP_LANG=es MINTAPP_ASCII=0
check_eq 'result in Spanish: title, limpiado, con fallos, notes and the space' \
$'Limpieza profunda completa. Resultado:\n\nLimpiado:\n  Documentos recientes: 1 KB, 3 archivos\n  Cachés de navegadores: 1 KB, 1 archivo\n\nCon fallos:\n  Papelera: 1 KB, 3 archivos; 2 archivos sin limpiar\n\nNavegadores abiertos, se saltan: Firefox\nSin nada que limpiar: Resto de cachés\nNo disponible en este sistema: Informes de fallos\nEn uso ahora, se salta: Caché de paquetes (apt)\nNo se pudo calcular: Configuración residual\n\nEspacio recuperado: 1 KB en 9 archivos' "$RES"
rtext C 0 0 'clipboard|failed||0|0|1|xclip
journal|failed||0|0|1|
rc_config|failed||0|0|1|changed' MINTAPP_LANG=es MINTAPP_ASCII=0
check_eq 'result in Spanish: what failed, in each of its three ways' \
$'Limpieza profunda completa. Resultado:\n\nCon fallos:\n  Portapapeles: falló la limpieza\n  Diario del sistema: falló la limpieza\n  Configuración residual: el plan cambió, no se purgó nada.' "$RES"
rtext C 0 0 'cache|skipped|empty|0|0|0|' MINTAPP_LANG=es MINTAPP_ASCII=0
check_eq 'result in Spanish: nothing cleaned' $'Limpieza profunda completa. Resultado:\n\nSin nada que limpiar: Resto de cachés\n\nNo se limpió nada.' "$RES"
rtext S 1 10 'recent|done||1|10|0|
clipboard|done||0|0|0|xsel' MINTAPP_LANG=es
check_eq 'result in Spanish without accents (a terminal with no UTF-8), simple level' \
$'Limpieza profunda simple. Resultado:\n\nLimpiado:\n  Documentos recientes: 1 KB, 1 archivo\n  Portapapeles: vaciado (xsel)\n\nEspacio recuperado: 1 KB en 1 archivo' "$RES"
# ---- D3 (P.4d, step 3): the result on screen (clean_show_result) ------------------------------
echo "-- The result on screen (clean_show_result), in text: the color says whether something failed, the note of the record has none"
new_sandbox
# What the last run did, as clean_run_entries keeps it: the trash is done (SR_FAIL makes it fail in part), the cache had nothing left.
SR_STATE='CLEAN_LEVEL=C; CLEAN_CHOSEN=(recent trash cache)
CLEAN_R_STATE=(done done skipped); CLEAN_R_WHY=("" "" empty); CLEAN_R_FILES=(3 5 0); CLEAN_R_BYTES=(300 50 0); CLEAN_R_FAILED=(0 0 0)
CLEAN_R_NOTE=("" "" ""); CLEAN_FREED_FILES=8 CLEAN_FREED_BYTES=350'
SR_FAIL='CLEAN_R_STATE=(done failed skipped); CLEAN_R_FAILED=(0 2 0)'
# All fourteen entries done: the longest result there is.
SR_ALL='clean_ids C; CLEAN_CHOSEN=("${CLEAN_LIST[@]}")
for i in "${!CLEAN_CHOSEN[@]}"; do CLEAN_R_STATE[i]=done CLEAN_R_WHY[i]="" CLEAN_R_FILES[i]=1 CLEAN_R_BYTES[i]=1024 CLEAN_R_FAILED[i]=0 CLEAN_R_NOTE[i]=""; done
CLEAN_FREED_FILES=13 CLEAN_FREED_BYTES=13312'
SR_REC="/home/u/.local/state/mintapp-remover/clean-20261113-101112-4242-1.txt"
SR_OK_TXT=$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 3 files\n  Trash: 1 KB, 5 files\n\nNothing to clean: Other caches\n\nSpace recovered: 1 KB in 8 files'
SR_BAD_TXT=$'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 3 files\n\nWith failures:\n  Trash: 1 KB, 5 files; 2 files not cleaned\n\nNothing to clean: Other caches\n\nSpace recovered: 1 KB in 8 files'
SR_NOTE=$'\n\nA record of what was removed was saved to:\n'"$SR_REC"
sr() {  # sr [CODE [VAR=val ...]]: clean_show_result with the state SR_STATE changed by CODE and the note of a record (SR_REC)
    local code="${1-}"; [ "$#" -eq 0 ] || shift
    app_eval "$SR_STATE
$code
LAST_RECORD='$SR_REC'
clean_show_result \"\$(record_note_text)\"" "$@"
}
srn() {  # srn [CODE [VAR=val ...]]: the same with no note
    local code="${1-}"; [ "$#" -eq 0 ] || shift
    app_eval "$SR_STATE
$code
clean_show_result" "$@"
}
# The colors are the program's: read here, never fixed in this file (a change of the palette must not break the tests).
app_eval 'printf "<<%b|%b|%b>>" "$C_OK" "$C_ERR" "$C_RESET"' MINTAPP_LANG=en
SR_V="${OUT#*<<}"; SR_V="${SR_V%%>>*}"; SR_COK="${SR_V%%|*}"; SR_V="${SR_V#*|}"; SR_CERR="${SR_V%%|*}"; SR_CRST="${SR_V#*|}"
check_eq 'the colors are read from the program and it runs with color: C_OK, C_ERR and C_RESET are sequences' ok \
    "$([[ "$SR_COK" == $'\033['*m && "$SR_CERR" == $'\033['*m && "$SR_CRST" == $'\033['*m ]] && echo ok || echo no)"
paint() {  # paint COLOR TEXT: each line of TEXT between COLOR and the reset, as text_say writes it (a blank line too)
    local line
    while IFS= read -r line; do printf '%s%s%s\n' "$1" "$line" "$SR_CRST"; done <<< "$2"
}
sr '' MINTAPP_UI=text MINTAPP_LANG=en
check_eq 'text, nothing failed: the whole result in the color of success, then the note of the record without color' \
    "$(paint "$SR_COK" "$SR_OK_TXT")$SR_NOTE" "$OUT"
sr "$SR_FAIL" MINTAPP_UI=text MINTAPP_LANG=en
check_eq 'text, an entry failed: the whole result in the color of errors, the note still without color' \
    "$(paint "$SR_CERR" "$SR_BAD_TXT")$SR_NOTE" "$OUT"
sr 'CLEAN_R_STATE=(done done failed); CLEAN_R_FAILED=(0 0 1)' MINTAPP_UI=text MINTAPP_LANG=en
check_eq 'text, the failure is the last entry: the same color of errors' \
    "$(paint "$SR_CERR" $'Deep cleanup, complete level. Result:\n\nCleaned:\n  Recent documents: 1 KB, 3 files\n  Trash: 1 KB, 5 files\n\nWith failures:\n  Other caches: 1 file not cleaned\n\nSpace recovered: 1 KB in 8 files')$SR_NOTE" "$OUT"
srn '' MINTAPP_UI=text MINTAPP_LANG=en
check_eq 'text, no note: only the result' "$(paint "$SR_COK" "$SR_OK_TXT")" "$OUT"
sr '' MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1
check_eq 'text with NO_COLOR: the same screen with no sequence at all' "$SR_OK_TXT$SR_NOTE" "$OUT"
sr "$SR_FAIL" MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1
check_eq 'text with NO_COLOR, an entry failed: the text itself says it (the block "With failures")' "$SR_BAD_TXT$SR_NOTE" "$OUT"
sr '' MINTAPP_UI=text MINTAPP_LANG=en NO_COLOR=1 COLUMNS=40 LINES=24
check_eq 'text, a 40-column terminal: the sentence of the note wraps and the path does not (it is copied whole)' \
    "$SR_OK_TXT"$'\n\nA record of what was removed was saved\nto:\n'"$SR_REC" "$OUT"
sr '' MINTAPP_UI=text MINTAPP_LANG=es NO_COLOR=1
assert_contains 'text, Spanish: the title of the result' "$OUT" 'Limpieza profunda completa. Resultado:'
assert_contains 'text, Spanish: the note of the record' "$OUT" $'Se guardo un registro de lo eliminado en:\n'"$SR_REC"
app_eval_in $'\nnext\n' "$SR_STATE
clean_show_result >/dev/null; read -r line; printf '<<%s>>' \"\$line\"" MINTAPP_UI=text MINTAPP_LANG=en
value_of 'text: the screen waits for one Enter, and what is typed after it is left for the next question' next

echo "-- The result on screen: with dialogs (whiptail), a message box of the big size that scrolls only when the text is taller"
new_sandbox
wt_last() {  # wt_last: the arguments of the last whiptail call, one per line (a line break inside an argument is the control character RS)
    awk '$0 == "@@END@@" { last = cur; cur = ""; next } { cur = cur $0 "\n" } END { printf "%s", last }' "$SB/state/whiptail.args"
}
wt_after() {  # wt_after OPTION [N]: the N-th (default 1) argument after OPTION in the last call, its line breaks restored
    wt_last | awk -v o="$1" -v n="${2:-1}" 'f && ++k == n { print; exit } $0 == o { f = 1 }' | tr '\036' '\n'
}
wr() {  # wr [CODE [VAR=val ...]]: clean_show_result with whiptail, which answers OK; the call is in the log of the stub
    fake_answers OK
    sr "$@" MINTAPP_UI=whiptail COLUMNS=80 LINES=24
}
app_eval 'calc_whiptail_dimensions; printf "<<%s %s %s>>" "$WT_HEIGHT_BIG" "$WT_WIDTH_BIG" "$WT_WIDTH"' COLUMNS=80 LINES=24
WB="${OUT#*<<}"; WB="${WB%%>>*}"; WT_BIG_H="${WB%% *}"; WB="${WB#* }"; WT_BIG_W="${WB%% *}"; WT_NORMAL_W="${WB#* }"
wr '' MINTAPP_LANG=en
check_eq 'whiptail: one message box and nothing else' 1 "$(grep -c '^@@END@@$' "$SB/state/whiptail.args")"
check_eq 'whiptail: the box is a message box with the OK button' '--ok-button|OK' "$(wt_last | grep -x -e '--ok-button' -e 'OK' | paste -sd'|')"
assert_contains 'whiptail: and it is --msgbox' "$(wt_last)" '--msgbox'
check_eq 'whiptail: its text is the result and, after it, the note of the record' "$SR_OK_TXT$SR_NOTE" "$(wt_after --msgbox)"
check_eq 'whiptail: it is as tall as the text needs (12 lines and 6 rows of frame, buttons and margins)' 18 "$(wt_after --msgbox 2)"
check_eq 'whiptail: and as wide as the boxes of long text, not the narrower normal ones' "$WT_BIG_W" "$(wt_after --msgbox 3)"
check_eq 'whiptail: the normal and the big widths differ at 80 columns, so the check above tells them apart' 1 "$([ "$WT_BIG_W" -ne "$WT_NORMAL_W" ] && echo 1 || echo 0)"
assert_not_contains 'whiptail: the text fits, so it does not scroll' "$(wt_last)" '--scrolltext'
assert_not_contains 'whiptail: no escape sequence goes into the box (the color is for the plain text only)' "$(cat "$SB/state/whiptail.args")" $'\033'
wr "$SR_FAIL" MINTAPP_LANG=en
check_eq 'whiptail, an entry failed: the same box with the block of the failures in its text' "$SR_BAD_TXT$SR_NOTE" "$(wt_after --msgbox)"
assert_not_contains 'whiptail, an entry failed: still no escape sequence' "$(cat "$SB/state/whiptail.args")" $'\033'
fake_answers OK
srn '' MINTAPP_UI=whiptail COLUMNS=80 LINES=24 MINTAPP_LANG=en
check_eq 'whiptail, no note: the text is only the result' "$SR_OK_TXT" "$(wt_after --msgbox)"
wr "$SR_ALL" MINTAPP_LANG=en
check_eq 'whiptail, fourteen entries: the box is as tall as the big ones allow' "$WT_BIG_H" "$(wt_after --msgbox 2)"
assert_contains 'whiptail, fourteen entries: it scrolls, so nothing is cut' "$(wt_last)" '--scrolltext'
assert_contains 'whiptail, fourteen entries: the last entry is in its text' "$(wt_after --msgbox)" 'Leftover settings: 1 package'
assert_contains 'whiptail, fourteen entries: and so is the note of the record, after the space recovered' "$(wt_after --msgbox)" $'Space recovered: 13 KB in 13 files\n\nA record of what was removed was saved to:'
wr '' MINTAPP_LANG=es
check_eq 'whiptail, Spanish: the button' Aceptar "$(wt_after --ok-button)"
assert_contains 'whiptail, Spanish: the title of the result' "$(wt_after --msgbox)" 'Limpieza profunda completa. Resultado:'
assert_contains 'whiptail, Spanish: the note of the record' "$(wt_after --msgbox)" $'Se guardo un registro de lo eliminado en:\n'"$SR_REC"

echo "-- The result on screen: in windows (zenity), one window, a plain message or a text with a scroll bar"
gfresh
app_eval 'printf "<<%s %s>>" "$GUI_W_BIG" "$GUI_H_LIST"' "${GUI[@]}"
GB="${OUT#*<<}"; GB="${GB%%>>*}"; GUI_BIG_W="${GB% *}"; GUI_BIG_H="${GB#* }"
zr() {  # zr [CODE [VAR=val ...]]: clean_show_result in windows; the zenity stub answers OK
    fake_zenity OK
    sr "$@" "${GUI[@]}" TMPDIR="$SB/tmp"
}
zarg() { zenity_call | grep -m1 -e "^$1" | tr '\036' '\n'; }   # zarg PREFIX: the argument of the last call that starts with PREFIX, its line breaks restored
zr ''
check_eq 'windows: a single window (no progress window: that is clean_run)' 1 "$(zenity_calls)"
check_eq 'windows: nothing is written on the terminal' '' "$OUT"
check_eq 'windows, twelve lines: a plain message window' 1 "$(zenity_call | grep -cx -e '--info')"
assert_not_contains 'windows, twelve lines: not the window with a scroll bar' "$(zenity_call)" '--text-info'
check_eq 'windows, twelve lines: its text is the result and the note of the record' "--text=$SR_OK_TXT$SR_NOTE" "$(zarg --text=)"
check_eq 'windows, twelve lines: the button says OK' '--ok-label=OK' "$(zarg --ok-label=)"
assert_not_contains 'windows, twelve lines: no escape sequence in the text' "$(zenity_call)" $'\033'
zr "$SR_FAIL"
check_eq 'windows, an entry failed: the same window with the block of the failures in its text' "--text=$SR_BAD_TXT$SR_NOTE" "$(zarg --text=)"
zr "$SR_ALL"
check_eq 'windows, fourteen entries: still one window' 1 "$(zenity_calls)"
check_eq 'windows, fourteen entries: the window with a scroll bar' 1 "$(zenity_call | grep -cx -e '--text-info')"
assert_not_contains 'windows, fourteen entries: not the plain message' "$(zenity_call)" $'--info\n'
check_eq 'windows, fourteen entries: as wide as the big windows' "--width=$GUI_BIG_W" "$(zarg --width=)"
check_eq 'windows, fourteen entries: and as tall' "--height=$GUI_BIG_H" "$(zarg --height=)"
check_eq 'windows, fourteen entries: OK is its button and Close the cancel button of the window' '--ok-label=OK|--cancel-label=Close' "$(zarg --ok-label=)|$(zarg --cancel-label=)"
assert_contains 'windows, fourteen entries: the text goes in by stdin and ends with the note of the record' "$(zenity_stdin)" $'Space recovered: 13 KB in 13 files\n\nA record of what was removed was saved to:\n'"$SR_REC"
assert_not_contains 'windows, fourteen entries: and has no escape sequence' "$(zenity_stdin)" $'\033'
fake_zenity OK
srn '' "${GUI[@]}" TMPDIR="$SB/tmp"
check_eq 'windows, no note: the text is only the result' "--text=$SR_OK_TXT" "$(zarg --text=)"
fake_zenity OK
sr "$SR_ALL" "${GUI[@]}" TMPDIR="$SB/tmp" MINTAPP_LANG=es
check_eq 'windows, Spanish: the buttons' '--ok-label=Aceptar|--cancel-label=Cerrar' "$(zarg --ok-label=)|$(zarg --cancel-label=)"
assert_contains 'windows, Spanish: the title of the result' "$(zenity_stdin)" 'Limpieza profunda completa. Resultado:'

# ---- D3 (P.4d, step 4): the record of a cleaning ---------------------------------------------------
echo "-- The record (write_clean_record): what each entry did, what was measured, what was recovered"
new_sandbox
RH="$SB/home"
# The arrays of a run in which the entries ended in every way there is.
REC_SETUP='
CLEAN_LEVEL=C
CLEAN_CHOSEN=(recent cache clipboard rc_config journal trash apt_cache x11_logs)
CLEAN_M_STATE=(ok ok ok ok unavailable ok busy ok)
CLEAN_M_FILES=(2 3 0 2 0 0 0 0); CLEAN_M_BYTES=(300 140 0 0 0 0 0 0); CLEAN_M_FAILED=(0 0 0 0 0 0 0 4); CLEAN_M_NOTE=("" "" "" "" "" "" "" "")
CLEAN_TOTAL_FILES=5 CLEAN_TOTAL_BYTES=440
CLEAN_R_STATE=(done failed done done skipped skipped skipped skipped)
CLEAN_R_WHY=("" "" "" "" unavailable empty busy unknown)
CLEAN_R_FILES=(2 1 0 2 0 0 0 0); CLEAN_R_BYTES=(300 100 0 0 0 0 0 0); CLEAN_R_FAILED=(0 2 0 0 0 0 0 0); CLEAN_R_NOTE=("" "" "" "" "" "" "" "")
CLEAN_FREED_FILES=3 CLEAN_FREED_BYTES=400
CLEAN_RC_PLAN=$'"'"'Purg pkg1 [1.0]\nPurg pkg2 [1.0]\nInst other [2]\nRemv dep [1]'"'"
# No run yet: what the record has when it begins.
REC_BEGIN='CLEAN_R_STATE=(); CLEAN_R_WHY=(); CLEAN_R_FILES=(); CLEAN_R_BYTES=(); CLEAN_R_FAILED=(); CLEAN_R_NOTE=(); CLEAN_FREED_FILES=0; CLEAN_FREED_BYTES=0'
wrec() {  # wrec STATUS [CODE [VAR=val ...]]: writes the record with that status after REC_SETUP and CODE; WST is the status of write_clean_record and WREC the record, without its date
    local status="$1" code="${2-}"; shift $(( $# < 2 ? $# : 2 ))
    app_eval "$REC_SETUP; $code
write_clean_record \"\$HOME/rec.txt\" \"$status\"; st=\$?
printf '<<%s\\n%s>>' \"\$st\" \"\$(grep -v '^# Date: ' \"\$HOME/rec.txt\" 2>/dev/null)\"" "$@"
    WREC="${OUT#*<<}"; WREC="${WREC%%>>*}"; WST="${WREC%%$'\n'*}"; WREC="${WREC#*$'\n'}"
}
PLAN_LINES='#
# Packages in the rc_config plan:
Purg pkg1 [1.0]
Purg pkg2 [1.0]
Remv dep [1]'
wrec 'failed (1 entry not cleaned completely)'
check_eq 'record, run done: it was written' 0 "$WST"
check_eq 'record, run done: one line for each entry however it ended, the totals, and the packages of the plan' \
'# MintApp Remover cleaning record
# Status: failed (1 entry not cleaned completely)
# Level: complete
#
# Entries:
recent: done, files 2, bytes 300
cache: failed, files 1, bytes 100, failed 2
clipboard: done
rc_config: done, packages 2
journal: skipped (unavailable)
trash: skipped (empty)
apt_cache: skipped (busy)
x11_logs: skipped (unknown)
#
# Measured: files 5, bytes 440
# Recovered: files 3, bytes 400
'"$PLAN_LINES" "$WREC"
check_eq 'record: a private file (mode 600)' 600 "$(stat -c %a "$RH/rec.txt")"
check_eq 'record: with its date in ISO 8601' 1 "$(grep -cE '^# Date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9:]{2}:?[0-9]{2}$' "$RH/rec.txt")"
wrec completed 'CLEAN_LEVEL=S'
check_eq 'record: the level S is "simple"' '# Level: simple' "$(sed -n 3p <<< "$WREC")"
wrec completed 'CLEAN_LEVEL=C'
check_eq 'record: the level C is "complete"' '# Level: complete' "$(sed -n 3p <<< "$WREC")"
wrec completed 'CLEAN_LEVEL=x'
check_eq 'record: any other level counts as complete' '# Level: complete' "$(sed -n 3p <<< "$WREC")"
wrec completed
check_eq 'record: completed has the line of what was recovered' 1 "$(grep -c '^# Recovered: files 3, bytes 400$' <<< "$WREC")"

wrec started "$REC_BEGIN"
check_eq 'record, started: what the measure said (pending), what is skipped, and no line of what was recovered' \
'# MintApp Remover cleaning record
# Status: started
# Level: complete
#
# Entries:
recent: pending, files 2, bytes 300 measured
cache: pending, files 3, bytes 140 measured
clipboard: pending
rc_config: pending, packages 2 measured
journal: skipped (unavailable)
trash: skipped (empty)
apt_cache: skipped (busy)
x11_logs: skipped (unknown)
#
# Measured: files 5, bytes 440
'"$PLAN_LINES" "$WREC"
wrec interrupted 'CLEAN_R_STATE=(done running); CLEAN_R_FILES=(2); CLEAN_R_BYTES=(300); CLEAN_R_FAILED=(0); CLEAN_R_WHY=(); CLEAN_FREED_FILES=2 CLEAN_FREED_BYTES=300'
check_eq 'record, interrupted: the finished ones, the one that was running, the ones that never started, and a line that says so' \
'# MintApp Remover cleaning record
# Status: interrupted
# Level: complete
# The run was interrupted: part of this cleaning may already be done.
#
# Entries:
recent: done, files 2, bytes 300
cache: running, files 3, bytes 140 measured
clipboard: pending
rc_config: pending, packages 2 measured
journal: skipped (unavailable)
trash: skipped (empty)
apt_cache: skipped (busy)
x11_logs: skipped (unknown)
#
# Measured: files 5, bytes 440
# Recovered by the finished entries: files 2, bytes 300
'"$PLAN_LINES" "$WREC"
wrec interrupted 'CLEAN_R_STATE=(done done done done running running)'
check_eq 'record, interrupted: an entry that was "running" and had nothing to do is skipped, not running' \
'journal: skipped (unavailable)|trash: skipped (empty)' "$(sed -n '/^journal:/p;/^trash:/p' <<< "$WREC" | paste -sd'|')"
wrec 'failed (2 entries not cleaned completely)' 'CLEAN_R_STATE=(done done failed failed skipped skipped skipped skipped); CLEAN_R_FILES=(2 1 0 0 0 0 0 0); CLEAN_R_FAILED=(0 0 1 2 0 0 0 0); CLEAN_R_NOTE=("" "" "" changed)'
check_eq 'record: the clipboard that failed says how many, and has no files or bytes' 'clipboard: failed, failed 1' "$(grep '^clipboard:' <<< "$WREC")"
check_eq 'record: the leftover settings that failed say the packages, how many failed, and that the plan changed' 'rc_config: failed, packages 0, failed 2, plan changed' "$(grep '^rc_config:' <<< "$WREC")"
wrec completed 'CLEAN_R_NOTE=("" "" "" changed "" "" "" "")'
check_eq 'record: the plan changed, and it was done' 'rc_config: done, packages 2, plan changed' "$(grep '^rc_config:' <<< "$WREC")"
wrec completed 'CLEAN_RC_PLAN=""'
check_eq 'record: the leftover settings with no plan: no list of packages' 0 "$(grep -c 'Packages in the rc_config plan' <<< "$WREC")"
wrec completed 'CLEAN_CHOSEN=(recent cache); CLEAN_R_STATE=(done done)'
check_eq 'record: with a plan but without leftover settings in the cleaning: no list of packages' 0 "$(grep -c 'Packages in the rc_config plan' <<< "$WREC")"
wrec completed 'CLEAN_CHOSEN=(); CLEAN_R_STATE=()'
check_eq 'record: with no entries it still says what was measured and recovered' \
'# MintApp Remover cleaning record
# Status: completed
# Level: complete
#
# Entries:
#
# Measured: files 5, bytes 440
# Recovered: files 3, bytes 400' "$WREC"
# A record that cannot be written: nothing half-written, and the one that was there stays whole.
mkdir -p "$RH/ro"; printf 'the record before\n' > "$RH/ro/rec.txt"; sandbox_chown; chmod 555 "$RH/ro"
app_eval "$REC_SETUP; write_clean_record \"\$HOME/ro/rec.txt\" completed; printf '<<%s>>' \$?"
value_of 'record: in a folder where nothing can be written, it fails' 1
check_eq 'record: the one that was there stays whole' 'the record before' "$(cat "$RH/ro/rec.txt")"
check_eq 'record: and no temporary file is left beside it' rec.txt "$(ls -A "$RH/ro")"
chmod 755 "$RH/ro"

echo "-- The record: it begins before anything runs (clean_record_begin) and is closed after (clean_record_end)"
new_sandbox
RH="$SB/home"; RSD="$RH/.local/state/mintapp-remover"
RB_NAME='[[ "${LAST_RECORD#"$HOME"/.local/state/mintapp-remover/}" =~ ^clean-[0-9]{8}-[0-9]{6}-[0-9]+-SEQ\.txt$ ]] && echo name || echo bad-name'
rbeg() {  # rbeg LABEL EXPECTED [CODE AFTER BEGIN [VAR=val ...]]: <<name|active is the record|marked as cleaning|sequence|status in the file>> after clean_record_begin
    local label="$1" expected="$2" code="${3-}"; shift $(( $# < 3 ? $# : 3 ))
    app_eval "$REC_SETUP; $REC_BEGIN; clean_record_begin; $code
printf '<<%s|%s|%s|%s|%s>>' \"\$(${RB_NAME//SEQ/${RB_SEQ:-1}})\" \"\$([ \"\$ACTIVE_RECORD\" = \"\$LAST_RECORD\" ] && echo same || echo other)\" \"\$ACTIVE_CLEAN\" \"\$RECORD_SEQ\" \"\$(sed -n 's/^# Status: //p' \"\$LAST_RECORD\" 2>/dev/null)\"" "$@"
    value_of "$label" "$expected"
}
rbeg 'begin: the file is named with the date, the process and the sequence; the run is marked; the file says "started"' 'name|same|1|1|started'
check_eq 'begin: the state folder is private (mode 700)' 700 "$(stat -c %a "$RSD")"
check_eq 'begin: one record on the disk' 1 "$(clean_records | grep -c .)"
rm -rf "$RSD"
RB_SEQ=2 rbeg 'begin, a second time in the same run: the sequence goes on, so the name is another one' 'name|same|1|2|started' 'clean_record_begin'
check_eq 'begin, twice: two records, the second did not replace the first' 2 "$(clean_records | grep -c .)"
rm -rf "$RSD"
mkdir -p "$RH/.local"; rm -rf "$RH/.local/state"; : > "$RH/.local/state"; sandbox_chown
app_eval "$REC_SETUP; $REC_BEGIN; clean_record_begin; printf '<<[%s]|[%s]>>' \"\$LAST_RECORD\" \"\$ACTIVE_RECORD\""
value_of 'begin, with no folder where to write: no record, and none for on_exit to rewrite' '[]|[]'
rm -f "$RH/.local/state"

rend() {  # rend LABEL EXPECTED "STATES" [CODE BEFORE THE END]: the status of the record after clean_record_end with those states, <<status|active record|marked|records on disk>>
    local label="$1" expected="$2" states="$3" code="${4:-:}"
    rm -rf "$RSD"
    app_eval "$REC_SETUP; $REC_BEGIN; clean_record_begin; CLEAN_R_STATE=($states); $code; clean_record_end; st=\$?
printf '<<%s|[%s]|%s|%s|%s>>' \"\$(sed -n 's/^# Status: //p' \"\$LAST_RECORD\" 2>/dev/null)\" \"\$ACTIVE_RECORD\" \"\$ACTIVE_CLEAN\" \"\$st\" \"\$(ls \"\$HOME\"/.local/state/mintapp-remover | wc -l)\""
    value_of "$label" "$expected"
}
rend 'end, nothing failed: completed, nothing left active, the same record rewritten' 'completed|[]|0|0|1' 'done skipped done done'
rend 'end, one failed: it says how many, in the singular' 'failed (1 entry not cleaned completely)|[]|0|0|1' 'done failed done done'
rend 'end, two failed: and in the plural' 'failed (2 entries not cleaned completely)|[]|0|0|1' 'failed failed done'
rend 'end, all failed: the count is of the entries' 'failed (4 entries not cleaned completely)|[]|0|0|1' 'failed failed failed failed'
rend 'end, no state at all: completed' 'completed|[]|0|0|1' ''
rend 'end, with no record (it could not be made): it writes nothing, and still leaves nothing active' '|[]|0|0|0' 'done' 'LAST_RECORD=""; rm -rf "$HOME/.local/state"'
rm -rf "$RSD"
app_eval "$REC_SETUP; $REC_BEGIN; clean_record_begin; chmod 555 \"\$HOME/.local/state/mintapp-remover\"; clean_record_end; st=\$?; printf '<<%s|[%s]|%s|%s>>' \"\$st\" \"\$LAST_RECORD\" \"\$(sed -n 's/^# Status: //p' \"\$HOME\"/.local/state/mintapp-remover/clean-*.txt)\" \"\$ACTIVE_CLEAN\"; chmod 755 \"\$HOME/.local/state/mintapp-remover\""
value_of 'end, when it cannot rewrite the record: it still succeeds, it forgets the path (the note then says it failed), and the file stays as it was' '0|[]|started|0'

echo "-- An interrupted cleaning leaves its record: on_exit writes it as \"interrupted\", and leaves no list of open files"
new_sandbox
RH="$SB/home"; RSD="$RH/.local/state/mintapp-remover"
app_eval "install_traps; $REC_SETUP; $REC_BEGIN; clean_record_begin; clean_open_prepare
CLEAN_R_STATE=(done running); CLEAN_R_FILES=(2); CLEAN_R_BYTES=(300); CLEAN_R_FAILED=(0); CLEAN_FREED_FILES=2 CLEAN_FREED_BYTES=300
kill -TERM \$\$; sleep 5; echo not-reached" TMPDIR="$SB"
check_eq 'interrupted (SIGTERM): the program ends with 143 and does not go on' '143|0' "$RC|$(grep -c 'not-reached' <<< "$OUT" || true)"
INTREC="$(clean_records | head -n 1)"
check_eq 'interrupted: still the one record that was begun, not another' 1 "$(clean_records | grep -c .)"
check_eq 'interrupted: its status' '# Status: interrupted' "$(sed -n 's/^\(# Status: .*\)$/\1/p' "$INTREC")"
check_eq 'interrupted: the line that says so, and what the finished entries recovered' '# The run was interrupted: part of this cleaning may already be done.|# Recovered by the finished entries: files 2, bytes 300' "$(grep -e '^# The run' -e '^# Recovered' "$INTREC" | paste -sd'|')"
check_eq 'interrupted: the finished entry, the one that was running, and the one that never started' 'recent: done, files 2, bytes 300|cache: running, files 3, bytes 140 measured|clipboard: pending' "$(sed -n '/^recent:/p;/^cache:/p;/^clipboard:/p' "$INTREC" | paste -sd'|')"
check_eq 'interrupted: the list of what is open does not stay in the folder of temporary files' 0 "$(find "$SB" -maxdepth 1 -name 'mintapp-clean.*' | wc -l | tr -d ' ')"
check_eq 'interrupted: no temporary file in the state folder' 1 "$(find "$RSD" -mindepth 1 | wc -l)"

# ---- D3 (P.4d): the flow of the deep cleanup, end to end (clean_menu, clean_summary, clean_run, deep_clean) ----
# The sections above fix each piece alone. These run the whole thing in the plain text, with real files of the sandbox's HOME.
# Only the privacy entries are chosen with them: the caches and logs would reach /tmp and /var (those go in folders of the
# sandbox, further down).
echo "-- The flow of the deep cleanup (deep_clean): confirmed, not confirmed, going back, nothing to clean"
dfresh() {  # dfresh: a sandbox with three files; two are cleaned by the privacy entries (300 and 10 bytes), one is not (100)
    new_sandbox; RH="$SB/home"
    fake_file "$RH/.local/share/recently-used.xbel" 300
    fake_file "$RH/.local/share/Trash/files/a" 10
    fake_file "$RH/.cache/foo/x" 100
}
dleft() { find "$RH" -type f -not -path '*/.local/state/*' -not -path '*/.config/*' | sed "s|$SB|@|" | LC_ALL=C sort | paste -sd'|'; }
dflow() {  # dflow INPUT [CODE [VAR=val ...]]: CODE (deep_clean) with INPUT typed, in text; P gets the screens, and RCV the status of CODE
    local input="$1" code="${2:-deep_clean}"; shift $(( $# < 2 ? $# : 2 ))
    app_eval_in "$input" "$code; printf '<<rc=%s>>' \$?" MINTAPP_UI=text MINTAPP_LANG=en "$@"
    P="$(plain)"; RCV="${P#*<<rc=}"; RCV="${RCV%%>>*}"
}
order() {  # order TEXT...: yes if each text is on the screens after the one before it
    local rest="$P" t
    for t in "$@"; do
        [[ "$rest" == *"$t"* ]] || { printf no; return; }
        rest="${rest#*"$t"}"
    done
    printf yes
}
drec() { grep -e '^# Status' -e '^# Level' -e '^recent:' -e '^clipboard:' -e '^trash:' -e '^# Measured' -e '^# Recovered' "$(clean_records | head -n 1)" | paste -sd'|'; }
D_ALL='@/home/.cache/foo/x|@/home/.local/share/Trash/files/a|@/home/.local/share/recently-used.xbel'

dfresh
dflow $'C\n2\n1\nc\ny\n\n'
check_eq 'confirmed: deep_clean ends with 0' 0 "$RCV"
check_eq 'confirmed: what privacy cleans is gone and the rest stays' '@/home/.cache/foo/x' "$(dleft)"
check_eq 'confirmed: the screens come in order: the summary, the run, the result, the note of the record' yes \
    "$(order 'This would be cleaned:' 'Cleaning up the system...' 'Cleaning: Recent documents' 'Cleaning: Trash' 'Result:' 'Space recovered: 1 KB in 2 files' 'A record of what was removed was saved to:')"
assert_contains 'confirmed: the result says what was cleaned' "$P" $'Cleaned:\n  Recent documents: 1 KB, 1 file\n  Trash: 1 KB, 1 file'
assert_contains 'confirmed: and what this system lacks' "${P#*Result:}" 'Not available on this system: Clipboard'
check_eq 'confirmed: one record' 1 "$(clean_records | grep -c .)"
check_eq 'confirmed: the note names that record' yes "$([[ "$P" == *"$(clean_records | head -n 1)"* ]] && echo yes || echo no)"
check_eq 'confirmed: the record says what each entry did and the totals' \
    '# Status: completed|# Level: complete|recent: done, files 1, bytes 300|clipboard: skipped (unavailable)|trash: done, files 1, bytes 10|# Measured: files 2, bytes 310|# Recovered: files 2, bytes 310' "$(drec)"

for a in n '' yess; do
    dfresh
    dflow $'C\n2\n1\nc\n'"$a"$'\n\n'
    check_eq "not confirmed (\"$a\"): deep_clean ends with 0" 0 "$RCV"
    check_eq "not confirmed (\"$a\"): nothing is removed" "$D_ALL" "$(dleft)"
    check_eq "not confirmed (\"$a\"): no record" 0 "$(clean_records | grep -c .)"
    assert_not_contains "not confirmed (\"$a\"): nothing runs" "$P" 'Cleaning: '
    assert_contains "not confirmed (\"$a\"): it says so" "$P" 'Operation cancelled.'
done

dfresh
dflow $'C\n0\nS\n2\n1\nc\ny\n\n'
check_eq 'back from the scope to the level, then the simple level: only what that choice cleans (no trash)' '@/home/.cache/foo/x|@/home/.local/share/Trash/files/a' "$(dleft)"
check_eq 'back and another level: the summary of the first choice was never shown, and the one of the second says simple' '1|1' \
    "$(grep -c 'This would be cleaned:' <<< "$P")|$(grep -c 'Deep cleanup, simple level. This would be cleaned:' <<< "$P")"
check_eq 'back and another level: the record is of the level that ran' '# Status: completed|# Level: simple|recent: done, files 1, bytes 300|clipboard: skipped (unavailable)|# Measured: files 1, bytes 300|# Recovered: files 1, bytes 300' "$(drec)"
dfresh
dflow $'0\n'
check_eq 'back from the level: deep_clean ends with 0 and nothing happens' "0|$D_ALL|0" "$RCV|$(dleft)|$(clean_records | grep -c .)"
dflow ''
check_eq 'the end of the input in the level menu: the same' "0|$D_ALL|0" "$RCV|$(dleft)|$(clean_records | grep -c .)"
dflow $'C\n2\n1\nc\n'
check_eq 'the end of the input at the confirmation: it counts as no' "0|$D_ALL|0" "$RCV|$(dleft)|$(clean_records | grep -c .)"

dfresh; rm -f "$RH/.local/share/recently-used.xbel" "$RH/.local/share/Trash/files/a"
dflow $'C\n2\n1\nc\n\n'
check_eq 'nothing to clean: deep_clean ends with 0, nothing is removed, no record' "0|@/home/.cache/foo/x|0" "$RCV|$(dleft)|$(clean_records | grep -c .)"
assert_contains 'nothing to clean: the summary says it and the user is told' "$P" 'There is nothing to clean with what you chose.'
assert_not_contains 'nothing to clean: no confirmation is asked' "$P" 'Operation cancelled.'
assert_not_contains 'nothing to clean: nothing runs' "$P" 'Cleaning up the system...'

echo "-- The flow: an entry that fails does not stop the others, and the failure is told and recorded"
dfresh; chmod 555 "$RH/.local/share/Trash/files"; sandbox_chown
dflow $'C\n2\n1\nc\ny\n\n'
check_eq 'failure: deep_clean ends with 0 all the same (the result is what tells it)' 0 "$RCV"
check_eq 'failure: the recent documents went and the trash file stayed' '@/home/.cache/foo/x|@/home/.local/share/Trash/files/a' "$(dleft)"
assert_contains 'failure: the result separates what was cleaned from what failed' "$P" $'Cleaned:\n  Recent documents: 1 KB, 1 file\n\nWith failures:\n  Trash: 1 file not cleaned'
assert_contains 'failure: the space recovered is only what went' "$P" 'Space recovered: 1 KB in 1 file'
check_eq 'failure: the record says failed, with the entry that did not go' '# Status: failed (1 entry not cleaned completely)|# Level: complete|recent: done, files 1, bytes 300|clipboard: skipped (unavailable)|trash: failed, files 0, bytes 0, failed 1|# Measured: files 2, bytes 310|# Recovered: files 1, bytes 300' "$(drec)"
chmod 755 "$RH/.local/share/Trash/files"

echo "-- The flow: clean_summary and clean_run alone, the statuses that deep_clean builds on"
dfresh
DCODE="$(eng text); CLEAN_LEVEL=C; CLEAN_CHOSEN=(recent trash)"
dflow $'y\n' "$DCODE; clean_summary; echo \"summary=\$?\""
check_eq 'clean_summary, yes: status 0' 'summary=0' "$(grep -o 'summary=[0-9]*' <<< "$P")"
check_eq 'clean_summary, yes: and it removes nothing (that is clean_run)' "$D_ALL" "$(dleft)"
dflow $'n\n' "$DCODE; clean_summary; echo \"summary=\$?\""
check_eq 'clean_summary, no: status 1, nothing removed' "summary=1|$D_ALL" "$(grep -o 'summary=[0-9]*' <<< "$P")|$(dleft)"
dflow '' "$DCODE; clean_summary; echo \"summary=\$?\""
check_eq 'clean_summary, end of input: status 1' summary=1 "$(grep -o 'summary=[0-9]*' <<< "$P")"
dflow $'y\n' "$DCODE; clean_run; echo \"run=\$?\""
check_eq 'clean_run before any summary: nothing was measured, so nothing runs, and the status is 0' "run=0|$D_ALL|0" "$(grep -o 'run=[0-9]*' <<< "$P")|$(dleft)|$(clean_records | grep -c .)"
assert_not_contains 'clean_run before any summary: it says nothing of a record, because none was due' "$P" 'record'
dflow '' "$DCODE; clean_summary >/dev/null; clean_run; echo \"run=\$?\""
check_eq 'clean_run after the summary: status 0, the files go' 'run=0|@/home/.cache/foo/x' "$(grep -o 'run=[0-9]*' <<< "$P")|$(dleft)"
dfresh; chmod 555 "$RH/.local/share/Trash/files"; sandbox_chown
dflow '' "$DCODE; clean_summary >/dev/null; clean_run; echo \"run=\$?\""
check_eq 'clean_run with an entry that failed: status 1' 'run=1' "$(grep -o 'run=[0-9]*' <<< "$P")"
chmod 755 "$RH/.local/share/Trash/files"

echo "-- The flow: the menu of the actions (clean_menu) chooses between the two cleanups"
cmenu() {  # cmenu LABEL EXPECTED INPUT: what clean_menu runs (clean_system and deep_clean are replaced by words) and its status
    app_eval_in "$3" 'clean_system() { echo SYSTEM; }; deep_clean() { echo DEEP; }; header() { :; }; clean_menu; echo "st=$?"' MINTAPP_UI=text MINTAPP_LANG=en
    check_eq "$1" "$2" "$(grep -E '^(SYSTEM|DEEP|st=)' <<< "$OUT" | paste -sd'|')"
}
cmenu 'clean_menu, 1: the dependencies' 'SYSTEM|st=0' $'1\n'
cmenu 'clean_menu, 2: the deep cleanup' 'DEEP|st=0' $'2\n'
cmenu 'clean_menu, 0: neither, and status 0' 'st=0' $'0\n'
cmenu 'clean_menu, a wrong key and then 2: it asks again' 'DEEP|st=0' $'x\n2\n'
cmenu 'clean_menu, the end of the input: neither, status 0' 'st=0' ''

echo "-- The flow: without administrator rights nothing is run or recorded; with them it runs and says so"
# The rotated logs need rights: a folder of the sandbox in place of /var/log, and a sudo that refuses (crfresh) or the normal stub.
crfresh; sandbox_roots_on
LOG="$SB/var/log"
fake_file "$LOG/syslog.2.gz" 300; fake_age "$LOG/syslog.2.gz" 10
LOGENV="CLEAN_SYSTEM_ROOTS=(\"$LOG\"); CLEAN_LOG_DIR=\"$LOG\""
dflow $'S\n2\n3\nc\ny\n\n' "$LOGENV; deep_clean" MINTAPP_SUDO="$SB/deny/sudo"
check_eq 'rights denied: deep_clean ends with 0, the file stays, no record' "0|@/var/log/syslog.2.gz|0" "$RCV|$(find "$LOG" -type f | sed "s|$SB|@|")|$(clean_records | grep -c .)"
check_eq 'rights denied: sudo was asked once, with -v and nothing else' 'sudo -v' "$(sudo_log)"
check_eq 'rights denied: the summary, the request, the refusal' yes "$(order 'This would be cleaned:' 'Part of this cleanup needs administrator rights.' 'Administrator rights were not obtained' 'Nothing was cleaned.')"
assert_not_contains 'rights denied: no entry ran' "$P" 'Cleaning: '
dflow '' "$LOGENV; $(eng text); CLEAN_LEVEL=S; CLEAN_CHOSEN=(rotated_logs); clean_summary >/dev/null; clean_run; echo \"run=\$?\"" MINTAPP_SUDO="$SB/deny/sudo"
check_eq 'rights denied, clean_run alone: the status is 77 (no rights)' run=77 "$(grep -o 'run=[0-9]*' <<< "$P")"
: > "$SB/state/sudo.log"; sandbox_chown
dflow $'S\n2\n3\nc\ny\n\n' "$LOGENV; deep_clean"
check_eq 'rights given: deep_clean ends with 0 and the file is gone' "0|" "$RCV|$(find "$LOG" -type f | sed "s|$SB|@|")"
check_eq 'rights given: sudo -v first, then the removal of that file only' $'sudo -v\nsudo rm -f -- @/var/log/syslog.2.gz' "$(sudo_calls)"
check_eq 'rights given: the record says completed' '# Status: completed|# Level: simple' "$(grep -e '^# Status' -e '^# Level' "$(clean_records | head -n 1)" | paste -sd'|')"
sandbox_roots_off

echo "-- The flow with dialogs (whiptail), confirmed: the same files go and the same record is written"
dfresh; allow_clean_confirm
fake_answers OK TAG:4 TAG:2 TAG:C TAG:2 'TAG:"1"' YES OK TAG:0
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail, confirmed: the program leaves normally and the privacy files are gone' "0|@/home/.cache/foo/x" "$RC|$(dleft)"
check_eq 'whiptail, confirmed: the record' '# Status: completed|# Level: complete|recent: done, files 1, bytes 300|clipboard: skipped (unavailable)|trash: done, files 1, bytes 10|# Measured: files 2, bytes 310|# Recovered: files 2, bytes 310' "$(drec)"
assert_contains 'whiptail, confirmed: the result is a message box with the note of the record' "$(cat "$SB/state/whiptail.log")" 'A record of what was removed was saved to:'
dfresh
fake_answers OK TAG:4 TAG:2 TAG:C TAG:2 'TAG:"1"' NO OK TAG:0
app_run '' MINTAPP_UI=whiptail
check_eq 'whiptail, Cancel at the confirmation: nothing is removed and no record is written' "0|$D_ALL|0" "$RC|$(dleft)|$(clean_records | grep -c .)"
finish
