#!/usr/bin/env bash
# Catalogs and exclusions per desktop (F4.3): which applications each desktop detects
# (CATALOG_ALL -> CATALOG) and which system components advanced mode hides (EXCLUDED_ALL ->
# EXCLUDED_PATTERNS). The wording of names and descriptions is checked by the i18n suite.
# Fast: the program is only sourced, except in the end-to-end blocks.
# SC2016 is off for the whole file: the code given to app_eval is single-quoted on purpose, because
# the program expands it, not this script.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }

# What XDG_CURRENT_DESKTOP holds on each desktop ("other" is a desktop with no catalog of its own).
declare -A XDG=([cinnamon]='X-Cinnamon' [gnome]='ubuntu:GNOME' [kde]='KDE' [xfce]='XFCE' [mate]='MATE' [other]='LXQt')
DESKTOPS=(cinnamon gnome kde xfce mate other)

new_sandbox

echo "-- catalog per desktop"
# Every desktop's list as " key1 key2 ... " (so a key is found with spaces around it) and its size.
declare -A KEYS=() SIZE=()
for d in "${DESKTOPS[@]}"; do
    app_eval 'printf "%s|" "${#CATALOG[@]}"; printf " %s" "${CATALOG[@]%%|*}"; printf " "' XDG_CURRENT_DESKTOP="${XDG[$d]}"
    SIZE[$d]="${OUT%%|*}"
    KEYS[$d]="${OUT#*|}"
done
app_eval 'printf "%s" "${#CATALOG_ALL[@]}"'
TOTAL="$OUT"
check_eq 'the catalog is not empty' 1 "$(( TOTAL > 0 ? 1 : 0 ))"

for d in cinnamon gnome kde xfce mate; do
    check_eq "$d: has a catalog of its own (at least 20 applications, fewer than the whole)" 1 \
        "$(( SIZE[$d] >= 20 && SIZE[$d] < TOTAL ? 1 : 0 ))"
done
check_eq 'an unrecognized desktop (other) detects the whole catalog' "$TOTAL" "${SIZE[other]}"
app_eval 'for e in "${CATALOG_ALL[@]}"; do printf "%s " "${e%%|*}"; done' XDG_CURRENT_DESKTOP=LXQt
check_eq 'other: the order of the catalog is kept' " ${OUT% } " "${KEYS[other]}"

for d in "${DESKTOPS[@]}"; do
    for k in firefox thunderbird libreoffice; do
        assert_contains "$d: $k (marked \"*\") is detected" "${KEYS[$d]}" " $k "
    done
done
check_eq 'every desktop lists the "*" applications first, in the catalog order' 6 \
    "$(n=0; for d in "${DESKTOPS[@]}"; do case "${KEYS[$d]}" in ' firefox thunderbird libreoffice '*) n=$((n + 1)) ;; esac; done; echo "$n")"

# The applications that are stock in one desktop are detected there and nowhere else.
echo "-- the applications of each desktop"
own() { # own DESKTOP "key ..." : those keys are in DESKTOP and in no other real desktop.
    local d="$1" k o
    for k in $2; do
        assert_contains "$d: stock application $k is detected" "${KEYS[$d]}" " $k "
        for o in cinnamon gnome kde xfce mate; do
            [ "$o" != "$d" ] || continue
            assert_not_contains "$o: $k belongs to $d only" "${KEYS[$o]}" " $k "
        done
    done
}
own gnome 'evince eog totem gnome_logs gnome_snapshot loupe gnome_tour'
own kde 'kcalc okular kate gwenview ark spectacle haruna krdc neochat'
own xfce 'mousepad ristretto parole xfburn gimp hexchat menulibre'
own mate 'pluma eom engrampa mate_utils mozo'

echo "-- Mint and Cinnamon (the original catalog)"
for k in document_viewer webapp_manager warpinator hypnotix pix text_editor backup_tool usb_tools; do
    assert_contains "cinnamon: Mint application $k is detected" "${KEYS[cinnamon]}" " $k "
done
for k in warpinator hypnotix pix xed; do
    assert_not_contains "kde: Mint application $k is not detected" "${KEYS[kde]}" " $k "
done
for k in calculator document_scanner transmission disks; do
    assert_contains "xfce: shared application $k is detected" "${KEYS[xfce]}" " $k "
done
assert_not_contains 'gnome: the Mint text editor (xed) is not detected' "${KEYS[gnome]}" ' text_editor '
assert_contains 'gnome and xfce share the file archiver (file-roller)' "${KEYS[gnome]}${KEYS[xfce]}" ' archive_manager '

echo "-- no application is left without a desktop"
union=" ${KEYS[cinnamon]} ${KEYS[gnome]} ${KEYS[kde]} ${KEYS[xfce]} ${KEYS[mate]} "
app_eval 'for e in "${CATALOG_ALL[@]}"; do printf "%s\n" "${e%%|*}"; done' XDG_CURRENT_DESKTOP=LXQt
missing=""
for k in $OUT; do
    case "$union" in *" $k "*) ;; *) missing+="$k " ;; esac
done
check_eq 'every catalog entry is detected on at least one real desktop' '' "$missing"

echo "-- exclusions per desktop (advanced mode)"
# Probe: the components of every desktop, the system ones and some ordinary applications. A desktop
# protects its own session, file manager and settings; the system ones are protected on all of them.
OWN_ALL='nemo cinnamon-session muffin gnome-control-center nautilus gnome-shell mutter gnome-software dolphin plasma-desktop kwin-x11 systemsettings kinfocenter plasma-discover thunar xfce4-panel xfwm4 xfce4-settings caja marco mate-panel mate-session-manager'
SYSTEM='gdm3 lightdm sddm apt snapd synaptic network-manager cups konsole xterm gnome-terminal mintupdate ubuntu-session'
ORDINARY='xfce4-taskmanager mate-calc inkscape vlc'
declare -A OWN=(
    [cinnamon]='nemo cinnamon-session muffin gnome-control-center gnome-shell'
    [gnome]='gnome-control-center nautilus gnome-shell mutter gnome-software'
    [kde]='dolphin plasma-desktop kwin-x11 systemsettings kinfocenter plasma-discover'
    [xfce]='thunar xfce4-panel xfwm4 xfce4-settings'
    [mate]='caja marco mate-panel mate-session-manager')
declare -A FM=([cinnamon]=nemo [gnome]=nautilus [kde]=dolphin [xfce]=thunar [mate]=caja)
declare -A EXCL=()
for d in "${DESKTOPS[@]}"; do
    app_eval 'for p in $PROBE; do if is_excluded_package "$p"; then printf "%s " "$p"; fi; done' \
        XDG_CURRENT_DESKTOP="${XDG[$d]}" PROBE="$OWN_ALL $SYSTEM $ORDINARY"
    EXCL[$d]=" $OUT"
    if [ "$d" = other ]; then want="$OWN_ALL $SYSTEM"; else want="${OWN[$d]} $SYSTEM"; fi
    check_eq "$d: protects its own components and the system ones, and nothing else" "$want" "${OUT% }"
done
for d in cinnamon gnome kde xfce mate; do
    assert_contains "$d: its file manager (${FM[$d]}) is protected" "${EXCL[$d]}" " ${FM[$d]} "
    for o in cinnamon gnome kde xfce mate; do
        [ "$o" != "$d" ] || continue
        assert_not_contains "$o: the file manager of $d (${FM[$d]}) can be removed here" "${EXCL[$o]}" " ${FM[$d]} "
    done
done
for d in cinnamon gnome kde xfce mate; do
    assert_contains "other: an unknown desktop protects ${FM[$d]}, the file manager of $d" "${EXCL[other]}" " ${FM[$d]} "
done

# The package managers of the other families, and what goes with them, are system components on any desktop (4.6,
# steps 5e and 6e). The neighbours with another name (zyppy, zypperx) are ordinary applications: the patterns are
# exact ("zypper", "zypper-*"), not a prefix.
PKGMGRS='dnf dnf-data rpm rpm-build pacman-contrib pamac-gtk octopi zypper zypper-lifecycle-plugin libzypp yast2 yast2-network'
for d in gnome kde other; do
    app_eval 'for p in $PROBE; do if is_excluded_package "$p"; then printf "%s " "$p"; fi; done' \
        XDG_CURRENT_DESKTOP="${XDG[$d]}" PROBE="$PKGMGRS zyppy zypperx"
    check_eq "$d: the package managers (dnf, rpm, pacman, zypper and their tools) are protected, their neighbours are not" "$PKGMGRS" "${OUT% }"
done

echo "-- the tables of exclusions"
app_eval '
bad=""
declare -A seen=()
for e in "${EXCLUDED_ALL[@]}"; do
    d="${e%%|*}" pat="${e#*|}"
    if [ "$d" != "*" ]; then
        for w in $d; do
            case " cinnamon gnome kde xfce mate " in *" $w "*) ;; *) bad+="[desktop $w in $e] " ;; esac
        done
    fi
    [[ "$pat" =~ ^[a-z0-9*][a-z0-9*.+-]*$ ]] || bad+="[pattern of $e] "
    case "$pat" in "xfce4-*"|"mate-*"|"gnome-*"|"plasma-*"|"kde*"|"k*"|"x*"|"lib*"|"*") bad+="[too wide: $e] " ;; esac
    if [ -n "${seen[$e]:-}" ]; then bad+="[repeated: $e] "; fi
    seen[$e]=1
done
printf "%s" "$bad"'
check_eq 'every entry names "*" or known desktops, has a valid pattern, is not too wide and is not repeated' '' "$OUT"
app_eval '
for w in cinnamon gnome kde xfce mate; do
    n=0
    for e in "${EXCLUDED_ALL[@]}"; do
        for x in ${e%%|*}; do if [ "$x" = "$w" ]; then n=$((n + 1)); fi; done
    done
    printf "%s " "$n"
done'
read -r -a own_n <<< "$OUT"
REAL=(cinnamon gnome kde xfce mate)
for i in "${!REAL[@]}"; do
    check_eq "${REAL[$i]}: has patterns of its own (at least 4 besides the shared ones)" 1 "$(( own_n[i] >= 4 ? 1 : 0 ))"
done
app_eval '[[ "$(declare -p CATALOG_ALL)" == "declare -ar "* && "$(declare -p EXCLUDED_ALL)" == "declare -ar "* ]] && echo yes || echo no'
check_eq 'both tables are read-only: nothing can change them after the program loads' yes "$OUT"
app_eval 'for e in "${CATALOG_ALL[@]}"; do r="${e#*|}"; printf " %s" "${r#*|}"; done' XDG_CURRENT_DESKTOP=LXQt
catalog_pkgs=" ${OUT//,/ } "
found=""
for p in $OWN_ALL $SYSTEM; do
    case "$catalog_pkgs" in *" $p "*) found+="$p " ;; esac
done
check_eq 'the catalog never offers a session, a file manager or a system service' '' "$found"

echo "-- which desktops a field covers (desktop_applies)"
app_eval 'for d in cinnamon gnome kde xfce mate other; do
    SYS_DESKTOP="$d"
    for f in "*" kde "cinnamon gnome" "gnome mate" "cinnamon gnome mate xfce"; do
        if desktop_applies "$f"; then r=y; else r=n; fi
        printf "%s|%s=%s\n" "$d" "$f" "$r"
    done
done'
declare -A APPLIES=()
while IFS='=' read -r k v; do APPLIES[$k]="$v"; done <<< "$OUT"
covers() { check_eq "a field \"$2\" ${3/y/covers}${3/n/does not cover} $1" "$3" "${APPLIES["$1|$2"]:-?}"; }
covers cinnamon '*' y
covers other '*' y
covers kde kde y
covers gnome kde n
covers other kde y
covers cinnamon 'cinnamon gnome' y
covers gnome 'cinnamon gnome' y
covers kde 'cinnamon gnome' n
covers mate 'cinnamon gnome' n
covers other 'cinnamon gnome' y
covers mate 'gnome mate' y
covers xfce 'gnome mate' n
covers xfce 'cinnamon gnome mate xfce' y
covers kde 'cinnamon gnome mate xfce' n

echo "-- the lists follow the detected desktop"
# Detecting again replaces the lists: nothing of the previous desktop is left over.
app_eval '
keys() { printf " %s" "${CATALOG[@]%%|*}"; printf " "; }
XDG_CURRENT_DESKTOP=KDE detect_system;   kde_keys="$(keys)";   kde_n=${#EXCLUDED_PATTERNS[@]}
XDG_CURRENT_DESKTOP=GNOME detect_system; gnome_keys="$(keys)"; gnome_n=${#EXCLUDED_PATTERNS[@]}
printf "%s|%s|%s|%s" "$kde_keys" "$kde_n" "$gnome_keys" "$gnome_n"' XDG_CURRENT_DESKTOP=XFCE
IFS='|' read -r again_kde again_kde_n again_gnome again_gnome_n <<< "$OUT"
app_eval 'printf "%s" "${#EXCLUDED_PATTERNS[@]}"' XDG_CURRENT_DESKTOP=KDE;   fresh_kde_n="$OUT"
app_eval 'printf "%s" "${#EXCLUDED_PATTERNS[@]}"' XDG_CURRENT_DESKTOP=GNOME; fresh_gnome_n="$OUT"
check_eq 'XFCE -> KDE: the catalog is the one of KDE, nothing of XFCE is left' "${KEYS[kde]}" "$again_kde"
check_eq 'KDE -> GNOME: the catalog is the one of GNOME, nothing of KDE is left' "${KEYS[gnome]}" "$again_gnome"
check_eq 'XFCE -> KDE: the exclusions are the ones of KDE' "$fresh_kde_n" "$again_kde_n"
check_eq 'KDE -> GNOME: the exclusions are the ones of GNOME' "$fresh_gnome_n" "$again_gnome_n"

echo "-- end to end: option 1 and option 2 detect only the stock applications of the desktop"
new_sandbox
fake_installed kcalc gnome-calculator okular evince firefox mousepad kde-spectacle
# detects XDG COUNT "names that are listed" "names that are not": the detection screen of a desktop.
detects() {
    local x="$1" count="$2" yes="$3" no="$4" n
    app_run $'\n1\n\n0\n' XDG_CURRENT_DESKTOP="$x"
    P="$(plain | tr -s ' ')"
    # The detection screen ends its count with a period; the status line of the menu (F7.0) does not.
    check_eq "$x: detect exits 0 and counts $count" "0:$count" "$RC:$(grep -E 'applications? detected\.' <<< "$P")"
    for n in $yes; do assert_contains "$x: detect lists $n" "$P" "$n ["; done
    for n in $no; do assert_not_contains "$x: detect does not list $n" "$P" "$n ["; done
}
detects X-Cinnamon '2 applications detected.' 'Firefox Calculator' 'Evince KCalc Okular Mousepad Spectacle'
detects ubuntu:GNOME '3 applications detected.' 'Firefox Calculator Evince' 'KCalc Okular Mousepad Spectacle'
detects KDE '4 applications detected.' 'Firefox KCalc Okular Spectacle' 'Calculator Evince Mousepad'
detects XFCE '3 applications detected.' 'Firefox Calculator Mousepad' 'Evince KCalc Okular Spectacle'
detects MATE '1 application detected.' 'Firefox' 'Calculator Evince KCalc Okular Mousepad Spectacle'
detects LXQt '7 applications detected.' 'Firefox Calculator Evince KCalc Okular Mousepad Spectacle' ''
app_run $'\n1\n\n0\n' XDG_CURRENT_DESKTOP=KDE
assert_contains 'KDE: Spectacle is found by its Ubuntu 24.04 package name (kde-spectacle)' "$(plain | tr -s ' ')" 'Spectacle [kde-spectacle'

echo "-- end to end: option 2 removes only what the desktop lists"
new_sandbox; fake_installed kcalc gnome-calculator
app_run $'\n2\n\n1\nc\ny\n\n0\n' XDG_CURRENT_DESKTOP=KDE
check_eq 'KDE: the removal exits 0' 0 "$RC"
assert_contains 'KDE: the first entry of the list (KCalc) is purged' "$(apt_log)" 'apt-get purge -y kcalc'
assert_not_contains 'KDE: gnome-calculator, which KDE does not list, is never touched' "$(apt_log)" 'gnome-calculator'
new_sandbox; fake_installed kde-spectacle
app_run $'\n2\n\n1\nc\ny\n\n0\n' XDG_CURRENT_DESKTOP=KDE
assert_contains 'KDE: Spectacle is purged under the name that is installed (kde-spectacle)' "$(apt_log)" 'apt-get purge -y kde-spectacle'
assert_not_contains 'KDE: the other name of the entry (spectacle) is not sent to apt' "$(apt_log)" 'purge -y spectacle'

echo "-- end to end: option 3 protects the components of the desktop and offers the rest"
new_sandbox
fake_installed dolphin thunar evince inkscape
make_desktop dolphin.desktop 'Dolphin';            fake_owner "$SB/apps/dolphin.desktop" dolphin
make_desktop thunar.desktop 'Thunar File Manager'; fake_owner "$SB/apps/thunar.desktop" thunar
make_desktop evince.desktop 'Evince';              fake_owner "$SB/apps/evince.desktop" evince
make_desktop inkscape.desktop 'Inkscape';          fake_owner "$SB/apps/inkscape.desktop" inkscape
sandbox_chown
# advanced XDG "listed" "hidden": the list of option 3 with those four launchers.
advanced() {
    local x="$1" yes="$2" no="$3" n
    app_run $'\n3\n\nc\n\n0\n' XDG_CURRENT_DESKTOP="$x"
    P="$(plain)"
    for n in $yes; do assert_contains "$x: advanced offers $n" "$P" "[$n]"; done
    for n in $no; do assert_not_contains "$x: advanced hides $n" "$P" "[$n]"; done
}
advanced KDE 'thunar evince inkscape' 'dolphin'
advanced XFCE 'dolphin evince inkscape' 'thunar'
advanced ubuntu:GNOME 'dolphin thunar inkscape' 'evince'
advanced LXQt 'inkscape' 'dolphin thunar evince'
app_run $'\n3\n\n3\nc\ny\n\n0\n' XDG_CURRENT_DESKTOP=KDE
assert_contains 'KDE: the file manager of another desktop (Thunar) can be removed from advanced mode' "$(apt_log)" 'apt-get purge -y thunar'
assert_not_contains 'KDE: that removal leaves Dolphin alone' "$(apt_log)" 'dolphin'
app_run $'\n3\n\nc\n\n0\n' XDG_CURRENT_DESKTOP=ubuntu:GNOME
assert_contains 'GNOME: Evince is for option 2, so advanced says how many others it found' "$(plain)" '3 additional applications were detected.'

echo "-- wording and test data"
for lang in en es; do
    app_eval 'msg advanced_warning_1; msg advanced_warning_n' MINTAPP_LANG="$lang" MINTAPP_ASCII=0
    for name in Cinnamon Nemo Nautilus Dolphin Thunar Caja Mint; do
        assert_not_contains "$lang: the advanced-mode warning does not name $name (the exclusions follow the desktop)" "$OUT" "$name"
    done
done
app_eval 'msg advanced_warning_1' MINTAPP_LANG=en MINTAPP_ASCII=0
assert_contains 'en: the advanced-mode warning speaks of the desktop and the file manager in general' "$OUT" 'the desktop, the file manager, the terminal'
app_eval 'msg advanced_warning_1' MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'es: the advanced-mode warning speaks of the desktop and the file manager in general' "$OUT" 'el escritorio, el gestor de archivos, la terminal'
# The functions suite takes these as applications "outside the catalog" in advanced mode; if one of
# them enters the catalog that suite fails (it happened with GIMP in F4.3), so it is checked here.
found=""
for p in inkscape vlc; do
    case "$catalog_pkgs" in *" $p "*) found+="$p " ;; esac
done
check_eq 'inkscape and vlc, the "outside the catalog" applications of the functions suite, are not in it' '' "$found"

finish
