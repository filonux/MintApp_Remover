#!/usr/bin/env bash
# Meta-package guard (E14, F4.4): detection by name and by dpkg section, and the
# stronger warning when a plan removes one. Stub apt/dpkg, nothing real.
# SC2016 is off: the code given to app_eval is single-quoted on purpose, the program expands it.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
# This suite checks the Unicode symbols: its sandboxes run with MINTAPP_ASCII=0 (see harness.sh).
export H_UNICODE=1

plain() { printf '%s' "$OUT" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }

echo "-- detection by name"
new_sandbox
YES_NAMES=(ubuntu-desktop ubuntu-desktop-minimal ubuntu-standard ubuntu-minimal ubuntu-restricted-extras
    ubuntu-restricted-addons ubuntu-server ubuntu-server-minimal
    kubuntu-desktop xubuntu-desktop lubuntu-desktop edubuntu-desktop ubuntu-mate-desktop ubuntu-budgie-desktop
    task-gnome-desktop task-kde-desktop task-desktop task-laptop task-english
    mint-meta-cinnamon mint-meta-core mint-meta-codecs linuxmint-keyring
    plasma-meta kde-applications-meta some-meta some-meta-extras some-metapackage
    mate-desktop-environment mate-desktop-environment-extra cinnamon-desktop-environment
    gnome gnome-core kde-full kde-standard kde-plasma-desktop plasma-desktop xfce4 xfce4-goodies lxde lxqt
    patterns-gnome-gnome_basic)
NO_NAMES=(firefox libreoffice libreoffice-core vlc gimp thunderbird nemo gnome-calculator gnome-shell
    ubuntu-docs ubuntu-keyring ubuntu-drivers-common ubuntu-session ubuntu-advantage-tools ubuntu-wallpapers-noble
    ubuntu-mate-themes kubuntu-docs xubuntu-artwork lubuntu-artwork edubuntu-docs
    cinnamon-desktop-data libgnome-desktop-3-20t64 xdg-desktop-portal xdg-desktop-portal-gtk plasma-desktop-data
    gnome-desktop-testing desktop-file-utils xfce4-terminal xfce4-panel lxqt-panel lxde-icon-theme
    libmetacity1 metacity python3-metakernel libubuntu-example mintinstall transmission-gtk)

CODE='for n in '"${YES_NAMES[*]} ${NO_NAMES[*]}"'; do if is_meta_name "$n"; then echo "yes $n"; else echo "no $n"; fi; done'
app_eval "$CODE"
for n in "${YES_NAMES[@]}"; do assert_contains "$n is a meta-package by its name" "$OUT" "yes $n"$'\n'; done
for n in "${NO_NAMES[@]}"; do
    case "$n" in transmission-gtk) end='' ;; *) end=$'\n' ;; esac
    assert_contains "$n is not a meta-package by its name" "$OUT" "no $n$end"
done

echo "-- the plan: what counts and what does not"
plan_meta() {  # plan_meta PLAN [REQUESTED...]: OUT = the names found, then "rc=STATUS"
    local code a
    printf -v code 'plan_meta_packages %q' "$1"; shift
    for a in "$@"; do printf -v code '%s %q' "$code" "$a"; done
    app_eval "$code; echo \"rc=\$?\""
}
new_sandbox
fake_installed firefox mint-meta-cinnamon ubuntu-desktop libfoo
plan_meta $'Purg firefox [1.0]\nPurg mint-meta-cinnamon [1.0]'
check_eq 'a dragged meta-package is found' $'mint-meta-cinnamon\nrc=0' "$OUT"
plan_meta $'Purg firefox [1.0]\nRemv libfoo [1.0]'
check_eq 'a plan without meta-packages finds none (status 1)' 'rc=1' "$OUT"
plan_meta $'Remv ubuntu-desktop [1.0]'
check_eq 'Remv lines count as well as Purg' $'ubuntu-desktop\nrc=0' "$OUT"
plan_meta $'Purg ubuntu-desktop [1.0]\nPurg firefox [1.0]' ubuntu-desktop
check_eq 'a package the user asked for is not reported (it is in the summary)' 'rc=1' "$OUT"
plan_meta $'Purg ubuntu-desktop [1.0]\nPurg mint-meta-cinnamon [1.0]' ubuntu-desktop
check_eq 'only the dragged one is reported when the other was asked for' $'mint-meta-cinnamon\nrc=0' "$OUT"
plan_meta $'Purg ubuntu-desktop [1.0]' ubuntu-deskto
check_eq 'asking for a similar name does not hide the meta-package' $'ubuntu-desktop\nrc=0' "$OUT"
plan_meta $'Purg mint-meta-core [1.0]\nPurg ubuntu-desktop [1.0]\nPurg mint-meta-core [1.0]'
check_eq 'the names come sorted and without repeats' $'mint-meta-core\nubuntu-desktop\nrc=0' "$OUT"
plan_meta ''
check_eq 'an empty plan finds none' 'rc=1' "$OUT"
plan_meta $'Inst ubuntu-desktop [1.0]\nConf ubuntu-desktop [1.0]'
check_eq 'only removals count: Inst and Conf lines are ignored' 'rc=1' "$OUT"
plan_meta $'Purg libfoo:i386 [1.0]'
check_eq 'a name with an architecture is read as it is (not a meta-package)' 'rc=1' "$OUT"

echo "-- detection by the section dpkg reports"
new_sandbox
fake_installed foo-extras bar-extras baz libqux tasksel-data
fake_section foo-extras metapackages
fake_section bar-extras universe/metapackages
fake_section baz tasks
fake_section libqux libs
plan_meta $'Purg foo-extras [1.0]\nPurg bar-extras [1.0]\nPurg baz [1.0]\nPurg libqux [1.0]\nPurg tasksel-data [1.0]'
check_eq 'metapackages, universe/metapackages and tasks are found; libs and misc are not' $'bar-extras\nbaz\nfoo-extras\nrc=0' "$OUT"
new_sandbox
fake_installed zz-meta-x aa-extras mm-extras
fake_section aa-extras metapackages
fake_section mm-extras tasks
plan_meta $'Purg zz-meta-x [1.0]\nPurg mm-extras [1.0]\nPurg aa-extras [1.0]'
check_eq 'what the patterns and what the section find come together, sorted' $'aa-extras\nmm-extras\nzz-meta-x\nrc=0' "$OUT"
new_sandbox
plan_meta $'Purg not-installed [1.0]'
check_eq 'a package dpkg does not know is not reported' 'rc=1' "$OUT"

echo "-- the section finds what the names no longer cover (Ubuntu 24.04)"
# Packages and sections as apt-cache shows them in Ubuntu 24.04: 34 of its 168 "ubuntu-*" are meta-packages. The
# first group has no name pattern and is found by its section; the second is the kind of package that the pattern
# "ubuntu-*" used to flag as a meta-package without being one.
new_sandbox
UBUNTU_META=(ubuntu-wsl:metapackages ubuntu-wallpapers:metapackages ubuntu-kernel-accessories:metapackages
    ubuntu-cloud-minimal:metapackages ubuntu-budgie-desktop-minimal:universe/metapackages
    ubuntu-edu-music:universe/metapackages ubuntu-defaults-it:universe/metapackages
    ubuntu-mate-core:universe/metapackages ubuntu-packaging-guide:universe/metapackages
    ubuntukylin-default-settings:universe/metapackages)
UBUNTU_OTHER=(ubuntu-docs:text ubuntu-drivers-common:admin ubuntu-keyring:misc ubuntu-session:gnome
    ubuntu-advantage-tools:universe/misc ubuntu-mate-themes:universe/x11 ubuntu-wallpapers-noble:x11
    ubuntu-release-upgrader-core:admin ubuntu-mono:gnome ubuntu-settings:x11 ubuntu-sounds:universe/gnome)
ubuntu_plan=""
ubuntu_names=()
for entry in "${UBUNTU_META[@]}" "${UBUNTU_OTHER[@]}"; do
    ubuntu_names+=("${entry%%:*}")
    fake_section "${entry%%:*}" "${entry#*:}"
    ubuntu_plan+="Purg ${entry%%:*} [1.0]"$'\n'
done
fake_installed "${ubuntu_names[@]}"
plan_meta "$ubuntu_plan"
check_eq 'ubuntu-*: the meta-packages no pattern names are found by their section; the rest are not flagged' \
    $'ubuntu-budgie-desktop-minimal\nubuntu-cloud-minimal\nubuntu-defaults-it\nubuntu-edu-music\nubuntu-kernel-accessories\nubuntu-mate-core\nubuntu-packaging-guide\nubuntu-wallpapers\nubuntu-wsl\nubuntukylin-default-settings\nrc=0' "$OUT"

echo "-- dpkg is asked once, and only for what the names left"
q_calls() {  # q_calls PLAN: OUT = the dpkg-query calls plan_meta_packages makes for that plan
    local code
    printf -v code 'rm -f "$HOME/q.log"; dpkg-query() { echo "$*" >> "$HOME/q.log"; }; plan_meta_packages %q >/dev/null; cat "$HOME/q.log" 2>/dev/null; true' "$1"
    app_eval "$code"
}
FMT='-W -f=${Package}\t${Section}\n --'
new_sandbox
q_calls $'Purg aa-pkg [1]\nPurg bb-pkg [1]\nPurg cc-pkg [1]'
check_eq 'one dpkg-query call for all the names' "$FMT aa-pkg bb-pkg cc-pkg" "$OUT"
q_calls $'Purg ubuntu-desktop [1]\nPurg task-laptop [1]'
check_eq 'dpkg is not asked when the patterns decided everything' '' "$OUT"
q_calls $'Purg ubuntu-desktop [1]\nPurg ok-pkg [1]'
check_eq 'dpkg is asked only for the names the patterns did not decide' "$FMT ok-pkg" "$OUT"
q_calls $'Purg -rf [1]\nPurg Bad_Name [1]\nPurg a [1]\nPurg ok-pkg [1]\nPurg -- [1]'
check_eq 'names that are not valid package names never reach dpkg' "$FMT ok-pkg" "$OUT"

echo "-- the warning text"
meta_text() {  # meta_text NAMES: OUT = <<the warning for those names (one per line)>>
    local code
    printf -v code 'meta_warning_text %q; printf "<<%%s>>" "$REPLY"' "$1"
    app_eval "$code" MINTAPP_LANG=en MINTAPP_ASCII=0
}
new_sandbox
meta_text $'aa-meta\nbb-meta'
assert_contains 'the warning lists the first package' "$OUT" '  - aa-meta'
assert_contains 'the warning lists the second package' "$OUT" '  - bb-meta'
assert_contains 'the bullets are one per line' "$OUT" $'  - aa-meta\n  - bb-meta\n'
first="${OUT%%  - aa-meta*}"; second="${OUT%%  - bb-meta*}"
check_eq 'the warning lists them in the order given' yes "$([ "${#first}" -lt "${#second}" ] && echo yes || echo no)"
assert_contains 'the warning says what a meta-package is' "$OUT" 'A meta-package contains no applications'
assert_contains 'the warning tells the user how to back out' "$OUT" 'If you did not expect this, cancel.'
assert_contains 'the warning ends with a blank line (the plan follows it in the dialogs)' "$OUT" $'cancel.\n\n>>'
check_eq 'the warning starts with the notice, with nothing before it' '<<WARNING: the plan also' "${OUT:0:24}"

echo "-- the warning in the plans (text mode)"
WARN_EN='WARNING: the plan also removes system meta-packages.'
LIST_EN=$'Meta-packages in the plan:\n  - '
# The stronger question is wider than 80 columns: wrap_prompt wraps it at a space, so the terminal never cuts it.
ASK_META_EN=$'The plan also removes system meta-packages. Do you want to continue anyway?\n[y/N]: '
ASK_PLAIN_EN='Do you want to uninstall the packages listed above? [y/N]: '
UNI=(MINTAPP_ASCII=0)
# Text mode as the program runs it with no terminal: every case here is option 2 unless it says otherwise.
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon
app_run $'\n2\n1\nc\nn\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"; P="$(plain)"
assert_contains 'option 2: a plan that drags a meta-package shows the warning' "$P" "$WARN_EN"
assert_contains 'option 2: the warning lists the dragged meta-package' "$P" "${LIST_EN}mint-meta-cinnamon"
assert_not_contains 'option 2: what the user chose is not in the warning (it is in the summary)' "$P" '  - firefox'
assert_contains 'option 2: the summary still lists what the user chose' "$P" '  ✓ Firefox'
assert_not_contains 'option 2: the warning is followed by a single blank line, not by two' "$P" $'cancel.\n\n\n'
check_eq 'option 2: answering no removes nothing' 0 "$(real_removals)"
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon
app_run $'\n2\n1\nc\ny\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"
check_eq 'option 2: the warning informs, it does not block: yes removes' 1 "$(real_removals)"
assert_contains 'option 2: the purge is of what the user chose' "$(apt_log)" 'apt-get purge -y firefox'
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon
app_run $'\n2\n1\nc\n\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"
check_eq 'option 2: an empty answer to the stronger question is a no' 0 "$(real_removals)"
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon
app_run $'\n2\n1\nc\n' MINTAPP_LANG=en "${UNI[@]}"
check_eq 'option 2: end of input at the stronger question is a no' 0 "$(real_removals)"
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon mint-meta-core
app_run $'\n2\n1\nc\nn\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"; P="$(plain)"
assert_contains 'several meta-packages: all of them, sorted, one per line' "$P" "${LIST_EN}mint-meta-cinnamon"$'\n  - mint-meta-core\n'
new_sandbox; fake_installed firefox
app_run $'\n2\n1\nc\nn\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"; P="$(plain)"
assert_not_contains 'a plan without meta-packages shows no warning' "$P" 'meta-packages'
new_sandbox; fake_installed firefox some-extras; fake_section some-extras metapackages; fake_dependents firefox some-extras
app_run $'\n2\n1\nc\nn\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"; P="$(plain)"
assert_contains 'a package that only the dpkg section marks as a meta-package is reported too' "$P" "${LIST_EN}some-extras"

echo "-- the question: stronger with meta-packages, the usual one without (text mode on a terminal)"
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon
app_run_pty $'\n2\n1\nc\nn\n\n0\n' MINTAPP_LANG=en MINTAPP_UI=text "${UNI[@]}"; P="$(plain)"
assert_contains 'the stronger question is asked' "$P" "$ASK_META_EN"
assert_not_contains 'and the usual one is not' "$P" "$ASK_PLAIN_EN"
before_warn="${P%%"$WARN_EN"*}"; before_ask="${P%%"$ASK_META_EN"*}"
check_eq 'the warning comes before the question' yes "$([ "${#before_warn}" -lt "${#before_ask}" ] && echo yes || echo no)"
new_sandbox; fake_installed firefox
app_run_pty $'\n2\n1\nc\nn\n\n0\n' MINTAPP_LANG=en MINTAPP_UI=text "${UNI[@]}"; P="$(plain)"
assert_contains 'without meta-packages the usual question is asked' "$P" "$ASK_PLAIN_EN"
assert_not_contains 'and the stronger one is not' "$P" 'continue anyway'
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon
# LANG=C.UTF-8: the wrapping counts characters, not bytes, as in a UTF-8 terminal (the accents would count double).
app_run_pty $'\n2\n1\nc\nn\n\n0\n' MINTAPP_LANG=es MINTAPP_UI=text "${UNI[@]}" LANG=C.UTF-8; P="$(plain)"
assert_contains 'Spanish: the warning' "$P" 'ATENCIÓN: el plan elimina también metapaquetes del sistema.'
assert_contains 'Spanish: the list' "$P" $'Metapaquetes del plan:\n  - mint-meta-cinnamon'
assert_contains 'Spanish: the stronger question' "$P" $'El plan elimina también metapaquetes del sistema. ¿Quieres continuar de todos\nmodos? [s/N]: '

echo "-- what the user asked for is not reported (option 3), what is dragged along is"
new_sandbox; fake_installed foo-desktop
make_desktop foo.desktop 'Foo extras'; fake_owner "$SB/apps/foo.desktop" foo-desktop
app_run $'\n3\n\n1\nc\nn\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"; P="$(plain)"
assert_contains 'option 3: the launcher is listed and its purge is planned' "$P" 'Purg foo-desktop'
assert_not_contains 'option 3: a meta-package the user picked is in the summary, not in a warning' "$P" "$WARN_EN"
new_sandbox; fake_installed foo-desktop
make_desktop foo.desktop 'Foo extras'; fake_owner "$SB/apps/foo.desktop" foo-desktop
fake_dependents foo-desktop mint-meta-core
app_run $'\n3\n\n1\nc\nn\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"; P="$(plain)"
assert_contains 'option 3: only the dragged meta-package is reported' "$P" "${LIST_EN}mint-meta-core"
assert_not_contains 'option 3: the one picked is not in that list' "$P" '  - foo-desktop'
check_eq 'option 3: answering no removes nothing' 0 "$(real_removals)"

echo "-- option 4: the cleanup plan is checked too (nothing was asked for there)"
new_sandbox; fake_autoremovable ubuntu-desktop-minimal libold1
app_run $'\n4\n1\nn\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"; P="$(plain)"
assert_contains 'option 4: a cleanup that removes a meta-package shows the warning' "$P" "$WARN_EN"
assert_contains 'option 4: it lists the meta-package' "$P" "${LIST_EN}ubuntu-desktop-minimal"
assert_not_contains 'option 4: and not the ordinary dependency' "$P" '  - libold1'
check_eq 'option 4: answering no removes nothing' 0 "$(real_removals)"
new_sandbox; fake_autoremovable ubuntu-desktop-minimal libold1
app_run $'\n4\n1\ny\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"
assert_contains 'option 4: yes goes on with the cleanup' "$(apt_log)" 'apt-get autoremove -y'
new_sandbox; fake_autoremovable libold1 libold2
app_run $'\n4\n1\nn\n\n0\n' MINTAPP_LANG=en "${UNI[@]}"; P="$(plain)"
assert_not_contains 'option 4: a cleanup of ordinary dependencies shows no warning' "$P" 'meta-packages'

echo "-- the warning in the plans (whiptail)"
# wt_dialog PATTERN: every line of the whiptail call whose first line contains PATTERN
wt_dialog() { awk -v pat="$1" '!p && index($0, pat) {p=1; print; next} p && /^whiptail / {exit} p' "$SB/state/whiptail.log"; }
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon mint-meta-core
fake_answers OK TAG:2 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=en "${UNI[@]}"
check_eq 'whiptail: the flow exits 0' 0 "$RC"
PLAN_DLG="$(wt_dialog '--scrolltext --msgbox WARNING')"
assert_contains 'whiptail: the plan dialog carries the warning' "$PLAN_DLG" "$WARN_EN"
assert_contains 'whiptail: and lists the dragged meta-packages, one per line' "$PLAN_DLG" $'  - mint-meta-cinnamon\n  - mint-meta-core\n'
assert_contains 'whiptail: the plan is in the same dialog' "$PLAN_DLG" 'Purg firefox'
before_warn="${PLAN_DLG%%"$WARN_EN"*}"; before_plan="${PLAN_DLG%%Purg firefox*}"
check_eq 'whiptail: the warning comes before the plan' yes "$([ "${#before_warn}" -lt "${#before_plan}" ] && echo yes || echo no)"
Q="$(wt_dialog '--yes-button Uninstall')"
assert_contains 'whiptail: the question is the stronger one' "$Q" 'The plan also removes system meta-packages (see the warning above).'
assert_contains 'whiptail: and asks to continue anyway' "$Q" 'Do you want to continue anyway?'
assert_contains 'whiptail: the stronger question still starts on Cancel' "$Q" '--defaultno'
check_eq 'whiptail: yes goes on: the removal ran' 1 "$(real_removals)"
new_sandbox; fake_installed firefox; fake_dependents firefox mint-meta-cinnamon
fake_answers OK TAG:2 'TAG:"1"' OK NO TAG:0
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=en "${UNI[@]}"
check_eq 'whiptail: no removes nothing' 0 "$(real_removals)"
new_sandbox; fake_installed firefox
fake_answers OK TAG:2 'TAG:"1"' OK YES OK TAG:0
app_run '' MINTAPP_UI=whiptail MINTAPP_LANG=en "${UNI[@]}"
assert_not_contains 'whiptail: a plan without meta-packages has no warning' "$(cat "$SB/state/whiptail.log")" 'meta-packages'
Q="$(wt_dialog '--yes-button Uninstall')"
assert_contains 'whiptail: and the question is the usual one' "$Q" 'Do you want to continue uninstalling these packages?'

finish
