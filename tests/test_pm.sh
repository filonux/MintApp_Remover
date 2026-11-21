#!/usr/bin/env bash
# Package manager layer (4.6): the manager the program works with (pm_detect, MINTAPP_PM) and what goes
# through the generic pm_* functions: the actions (pm_run), the simulation of a removal (pm_simulate),
# whether a package is installed (pm_installed), who owns a file (pm_owner), what the manager files as
# a meta-package (pm_meta_packages), the detail of a package (pm_detail) and whether it protects it
# (pm_protected) and what can be the name of a package (pm_valid_name). Stub apt-get, dpkg, dpkg-query and sudo; the cases that use the real dpkg, rpm, dnf,
# pacman or zypper (steps 4f, 5f and 6f) are skipped where they are not installed.
# SC2016 is off: the code given to app_eval is single-quoted on purpose, the program expands it.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

# code_only: the program without its comment lines (H_SCRIPT is the copy under test).
# strip_functions NAME... < CODE: that code without the bodies of those functions (a function starts
# with "name() {" and ends with a "}" at the start of a line).
code_only() { sed -E 's/^[[:space:]]*#.*$//' "$H_SCRIPT"; }
strip_functions() {
    awk -v names=" $* " '
        /^[A-Za-z_][A-Za-z0-9_]*\(\) \{$/ { n = $0; sub(/\(\).*/, "", n); if (index(names, " " n " ")) skip = 1 }
        !skip { print }
        skip && /^}$/ { skip = 0 }
    '
}
# count_of PATTERN: how many lines of the code (read from stdin) have that extended pattern.
count_of() { grep -cE "$1" || true; }
# at_least_one N: yes if N is 1 or more (the control that a detector sees what it looks for).
at_least_one() { if [ "$1" -ge 1 ]; then echo yes; else echo no; fi; }

new_sandbox
echo "-- pm_run: the generic actions of the package manager (4.6)"
app_eval 'apt_privileged() { echo "AP $*"; return 7; }; pm_run purge firefox vlc; echo "st=$?"'
check_eq 'pm_run purge: apt-get purge -y with the packages, and its status' $'AP purge -y firefox vlc\nst=7' "$OUT"
app_eval 'apt_privileged() { echo "AP $*"; }; pm_run autoremove; echo "st=$?"'
check_eq 'pm_run autoremove: apt-get autoremove -y' $'AP autoremove -y\nst=0' "$OUT"
app_eval 'apt_privileged() { echo "AP $*"; }; pm_run clean; echo "st=$?"'
check_eq 'pm_run clean: apt-get autoclean -y' $'AP autoclean -y\nst=0' "$OUT"
app_eval 'apt_privileged() { echo "AP $*"; }; pm_run install firefox; echo "st=$?"'
check_eq 'pm_run refuses an action that is not generic (status 2, nothing runs)' 'st=2' "$OUT"
app_eval 'apt_privileged() { echo "AP $*"; }; PM=nope; pm_run purge firefox; echo "st=$?"'
check_eq 'pm_run refuses a manager without backend (status 2, nothing runs)' 'st=2' "$OUT"
app_eval 'echo "$PM"'
check_eq 'a program that is only sourced works with apt' 'apt' "$OUT"
app_eval 'pm_tool; echo; pm_operation_text "purge foo"; echo; pm_install_text; echo'
check_eq 'apt: the texts of the records' $'apt-get\napt-get purge foo\napt-get install' "$OUT"

echo "-- the dnf backend: pm_run, pm_tool and the texts of the records (4.6, step 4a)"
# These cases call the functions of the dnf backend, not pm_detect, so they set PM themselves.
# dr CODE [VAR=val...]: CODE with PM=dnf and a privilege command that only says what it was given
# (PR_RC is its status); OUT ends with "st=" and the status of CODE.
dr() { app_eval "PM=dnf; priv_run() { echo \"PR \$*\"; return \${PR_RC:-0}; }; $1; echo \"st=\$?\"" "${@:2}"; }
# dnf_stub: a dnf in the sandbox that logs its arguments to the state folder (FAKE_DNF_RC is its status).
dnf_stub() {
    printf '#!/bin/sh\necho "dnf $*" >> "%s/state/dnf.log"\nexit "${FAKE_DNF_RC:-0}"\n' "$SB" > "$SB/bin/dnf"
    chmod 755 "$SB/bin/dnf"
}
new_sandbox
dr 'pm_run purge firefox vlc' PR_RC=7
check_eq 'dnf, purge: dnf remove -y with the packages, with privileges, and its status' $'PR dnf remove -y firefox vlc\nst=7' "$OUT"
dr 'pm_run autoremove'
check_eq 'dnf, autoremove: dnf autoremove -y' $'PR dnf autoremove -y\nst=0' "$OUT"
dr 'pm_run clean'
check_eq 'dnf, clean: dnf clean packages' $'PR dnf clean packages\nst=0' "$OUT"
dr 'pm_run clean foo bar'
check_eq 'dnf, clean: it takes no names, so it gets none' $'PR dnf clean packages\nst=0' "$OUT"
for refused in 'install firefox' 'PURGE foo' 'remove foo' 'upgrade' 'clean-all'; do
    read -ra args <<< "$refused"
    dr "pm_run ${args[*]}"
    check_eq "dnf, $refused: not an action of pm_run, status 2 and nothing runs" 'st=2' "$OUT"
done
dr 'apt_privileged() { echo APT; }; pm_run purge foo; pm_run autoremove; pm_run clean'
check_eq 'dnf never goes through the apt backend' $'PR dnf remove -y foo\nPR dnf autoremove -y\nPR dnf clean packages\nst=0' "$OUT"
new_sandbox
dnf_stub
app_eval 'PM=dnf; pm_run purge firefox vlc; echo "st=$?"' FAKE_DNF_RC=3
check_eq 'through the real priv_run: the status of dnf comes back' 'st=3' "$OUT"
check_eq 'through the real priv_run: sudo runs dnf remove -y, with no variables before it' 'sudo dnf remove -y firefox vlc' "$(sudo_log)"
check_eq 'and dnf got exactly those arguments' 'dnf remove -y firefox vlc' "$(cat "$SB/state/dnf.log")"
app_eval 'PM=dnf; pm_run clean; PM=dnf; pm_run autoremove'
check_eq 'through the real priv_run: clean and autoremove' $'dnf remove -y firefox vlc\ndnf clean packages\ndnf autoremove -y' "$(cat "$SB/state/dnf.log")"
app_eval 'echo "$PM_BACKENDS"'
check_eq 'PM_BACKENDS lists the managers that have a backend: apt, dnf, pacman and zypper (step 6e)' 'apt dnf pacman zypper' "$OUT"

app_eval 'PM=dnf; pm_tool; echo; pm_operation_text "purge foo bar"; echo; pm_operation_text purge; echo; pm_operation_text autoremove; echo
pm_operation_text clean; echo; pm_operation_text "purgex foo"; echo; pm_install_text; echo'
check_eq 'dnf: the texts of the records (purge is "remove", clean is "clean packages")' \
    $'dnf\ndnf remove foo bar\ndnf remove\ndnf autoremove\ndnf clean packages\ndnf purgex foo\ndnf install' "$OUT"
app_eval 'PM=dnf; pm_interrupt_hint'
check_eq 'dnf: the hint of an interrupted run, with sudo by default' '# If dnf reports a broken state, start with: sudo dnf check' "$OUT"
app_eval 'PM=dnf; PRIV_CMD=/usr/bin/doas; pm_interrupt_hint'
check_eq 'dnf: the hint names the privilege command in use' '# If dnf reports a broken state, start with: doas dnf check' "$OUT"
plan=$'Purg foo [1.0]\nPurg bar [1.0]'
app_eval "PM=dnf; PRIV_CMD=/usr/bin/doas; write_removal_record \"\$HOME/rec.txt\" 'interrupted (SIGTERM)' $(printf '%q' "$plan") 'purge foo bar'"
rec="$(cat "$SB/home/rec.txt")"
assert_contains 'a dnf record: the operation as dnf runs it' "$rec" '# Operation: dnf remove foo bar'
assert_contains 'a dnf record: the manager of the plan' "$rec" '# Packages in the dnf plan:'
assert_contains 'a dnf record: how to reinstall, with the names sorted' "$rec" '# doas dnf install bar foo'
assert_contains 'an interrupted dnf record: the hint about the state of the manager' "$rec" '# If dnf reports a broken state, start with: doas dnf check'
assert_not_contains 'a dnf record does not name apt anywhere' "$rec" 'apt'
new_sandbox
app_eval 'PM=dnf; priv_run() { return 5; }; execute_removal "Purg foo [1.0]" purge foo; echo "st=$?"'
check_eq 'a failed dnf removal: the status of dnf comes back' 'st=5' "$OUT"
assert_contains 'a failed dnf removal: the record says dnf and its exit code' "$(cat "$(state_files | head -n1)")" '# Status: failed (dnf exit code 5)'
new_sandbox
app_eval 'PM=dnf; priv_run() { echo "PR $*" >&2; return 0; }; execute_removal "Remv libold [1.0]" autoremove; echo "st=$?"'
check_eq 'a dnf autoremove runs through priv_run' $'PR dnf autoremove -y\nst=0' "$OUT"
assert_contains 'a completed dnf autoremove: the record' "$(cat "$(state_files | head -n1)")" $'# Status: completed\n'
assert_contains 'a completed dnf autoremove: its operation' "$(cat "$(state_files | head -n1)")" '# Operation: dnf autoremove'

echo "-- pm_detect and MINTAPP_PM (4.6, step 4e)"
# pd CODE [VAR=val...]: CODE and then "rc=STATUS PM=MANAGER". The harness gives every sandbox MINTAPP_PM=apt,
# so a case about the automatic choice empties it (MINTAPP_PM=) and gives the system (osr) and the PATH.
pd() { app_eval "$1; echo \"rc=\$? PM=\$PM\"" "${@:2}"; }
# osr ID [ID_LIKE]: an os-release file in the sandbox; its path goes to stdout.
osr() { printf 'ID=%s\n' "$1" > "$SB/osr-$1"; if [ -n "${2:-}" ]; then printf 'ID_LIKE="%s"\n' "$2" >> "$SB/osr-$1"; fi; printf '%s' "$SB/osr-$1"; }
new_sandbox
# Folders that hold only the tool of one manager, both, or none: the PATH of the cases about the tools.
mkdir -p "$SB/onlyapt" "$SB/onlydnf" "$SB/bothtools"
printf '#!/bin/sh\nexit 0\n' > "$SB/onlyapt/apt-get"
printf '#!/bin/sh\nexit 0\n' > "$SB/onlydnf/dnf"
cp "$SB/onlyapt/apt-get" "$SB/bothtools/apt-get"
cp "$SB/onlydnf/dnf" "$SB/bothtools/dnf"
chmod 755 "$SB/onlyapt/apt-get" "$SB/onlydnf/dnf" "$SB/bothtools/apt-get" "$SB/bothtools/dnf"
pd 'pm_detect' MINTAPP_PM=apt
check_eq 'MINTAPP_PM=apt is accepted' 'rc=0 PM=apt' "$OUT"
pd 'pm_detect' MINTAPP_PM=dnf
check_eq 'MINTAPP_PM=dnf is accepted: dnf has its backend' 'rc=0 PM=dnf' "$OUT"
pd 'pm_detect' MINTAPP_PM=pacman
check_eq 'MINTAPP_PM=pacman is accepted: pacman has its backend (step 5e)' 'rc=0 PM=pacman' "$OUT"
pd 'pm_detect' MINTAPP_PM=zypper
check_eq 'MINTAPP_PM=zypper is accepted: zypper has its backend (step 6e)' 'rc=0 PM=zypper' "$OUT"
# xbps (Void) stands for a manager that has no backend and is out of scope (see the limits in F4).
for bad_pm in xbps APT Apt DNF 'apt dnf' 'apt-get' '-s' 'a*' '../apt' 'apt;ls' 'x' pt nf ap; do
    pd 'pm_detect' MINTAPP_PM="$bad_pm"
    check_eq "MINTAPP_PM='$bad_pm' is not valid: status 1 and apt as the fallback value" 'rc=1 PM=apt' "$OUT"
done
pd 'PM_BACKENDS="apt dnf xbps"; pm_detect' MINTAPP_PM=xbps
check_eq 'a manager is accepted as soon as PM_BACKENDS lists it (PM_BACKENDS decides)' 'rc=0 PM=xbps' "$OUT"
pd 'PM_BACKENDS="apt dnf"; pm_detect' 'MINTAPP_PM=apt dnf'
check_eq 'a list is never taken as a name, even if both words are backends' 'rc=1 PM=apt' "$OUT"
pd 'pm_detect' MINTAPP_PM=apt MINTAPP_OS_RELEASE="$(osr fedora)"
check_eq 'MINTAPP_PM outranks the family: apt on a Fedora' 'rc=0 PM=apt' "$OUT"
pd 'pm_detect' MINTAPP_PM=dnf MINTAPP_OS_RELEASE="$(osr debian)"
check_eq 'MINTAPP_PM outranks the family: dnf on a Debian' 'rc=0 PM=dnf' "$OUT"
pd 'pm_detect' MINTAPP_PM=xbps MINTAPP_OS_RELEASE="$(osr debian)" PATH="$SB/bothtools"
check_eq 'an invalid MINTAPP_PM is an error, never a fallback to the family or to the tools' 'rc=1 PM=apt' "$OUT"
pd 'PM=dnf; pm_detect' MINTAPP_PM=xbps
check_eq 'a refusal leaves apt in PM, whatever PM held before' 'rc=1 PM=apt' "$OUT"
pd 'PM=dnf; pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/emptybin"
check_eq 'nothing found leaves apt in PM, whatever PM held before' 'rc=1 PM=apt' "$OUT"
pd 'PM=dnf; pm_detect' MINTAPP_PM=apt
check_eq 'a new choice replaces what PM held before' 'rc=0 PM=apt' "$OUT"
# The automatic choice, by the family of the distribution (every tool is in the PATH).
while IFS='|' read -r id like want; do
    pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr "$id" "$like")" PATH="$SB/bothtools"
    check_eq "family: ID=$id${like:+ ID_LIKE=\"$like\"} is $want" "rc=0 PM=$want" "$OUT"
done <<'EOF'
debian||apt
ubuntu||apt
linuxmint|ubuntu debian|apt
fedora||dnf
rhel||dnf
rocky|rhel centos fedora|dnf
almalinux|rhel centos fedora|dnf
nobara|rhel centos fedora|dnf
EOF
echo "-- the family table of detect_system, word by word (4.6, step 4e)"
# ID only and a PATH with no tool: the family is the only thing that can give the manager.
tested_ids=""
while IFS='|' read -r want words; do
    for id in $words; do
        pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr "$id")" PATH="$SB/emptybin"
        check_eq "family word: ID=$id is $want" "rc=0 PM=$want" "$OUT"
        tested_ids+=" $id"
    done
done <<'EOF'
apt|debian ubuntu linuxmint raspbian devuan
dnf|fedora rhel centos rocky almalinux ol amzn
pacman|arch archlinux archarm manjaro endeavouros
zypper|suse sles sled opensuse opensuse-leap opensuse-tumbleweed
EOF
for id in debianx xfedora ubuntu-core opensusex; do
    pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr "$id")" PATH="$SB/emptybin"
    check_eq "ID=$id is not a word of the table: no family, no tool, a failure" 'rc=1 PM=apt' "$OUT"
done
# Guard: every word of the table in the program has a case above, so a word added or misspelled there
# cannot go untested. A word with "*" (opensuse-*) is covered by a tested ID that it matches.
table_words="$(code_only | sed -nE 's/^[[:space:]]*([a-z0-9*|-]+)\) SYS_FAMILY="[a-z]+" ;;$/\1/p')"
check_eq 'control: the guard finds the four families of the table' 4 "$(printf '%s\n' "$table_words" | count_of '.')"
untested=""
while read -r word; do
    covered=no
    for id in $tested_ids; do
        # shellcheck disable=SC2254 # the word is a pattern on purpose
        case "$id" in $word) covered=yes ;; esac
    done
    [ "$covered" = yes ] || untested+=" $word"
done < <(printf '%s\n' "$table_words" | tr '|' '\n')
check_eq 'every word of the table in the program has a case above' '' "$untested"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr fedora)" PATH="$SB/onlyapt"
check_eq 'the family decides, not the tools: Fedora with only apt-get is dnf (preflight says what is missing)' 'rc=0 PM=dnf' "$OUT"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr debian)" PATH="$SB/onlydnf"
check_eq 'the family decides, not the tools: Debian with only dnf is apt' 'rc=0 PM=apt' "$OUT"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr fedora)" PATH="$SB/emptybin"
check_eq 'the family decides without looking at the PATH: Fedora with no tools is dnf' 'rc=0 PM=dnf' "$OUT"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr arch)" PATH="$SB/onlyapt"
check_eq 'the family decides, not the tools: Arch with only apt-get is pacman (preflight says what is missing)' 'rc=0 PM=pacman' "$OUT"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr arch)" PATH="$SB/emptybin"
check_eq 'the family decides without looking at the PATH: Arch with no tools is pacman' 'rc=0 PM=pacman' "$OUT"
# A family whose manager is not in PM_BACKENDS (here suse, with zypper taken out of the list), and a system that is
# not recognized, go by the tools.
# shellcheck disable=SC2043  # one family is enough; the loop stays for the next one that is taken out
for no_backend in opensuse-leap; do
    pd 'PM_BACKENDS="apt dnf pacman"; pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr "$no_backend")" PATH="$SB/onlydnf"
    check_eq "$no_backend (its manager is not in PM_BACKENDS): the tool that is there, dnf" 'rc=0 PM=dnf' "$OUT"
    pd 'PM_BACKENDS="apt dnf pacman"; pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr "$no_backend")" PATH="$SB/bothtools"
    check_eq "$no_backend: with several tools, the first of PM_BACKENDS (apt)" 'rc=0 PM=apt' "$OUT"
    pd 'PM_BACKENDS="apt dnf pacman"; pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr "$no_backend")" PATH="$SB/emptybin"
    check_eq "$no_backend: no tool at all is a failure (status 1, apt as the fallback value)" 'rc=1 PM=apt' "$OUT"
done
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/onlydnf"
check_eq 'no os-release, only dnf: dnf' 'rc=0 PM=dnf' "$OUT"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/onlyapt"
check_eq 'no os-release, only apt-get: apt' 'rc=0 PM=apt' "$OUT"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/bothtools"
check_eq 'no os-release, both tools: the first of PM_BACKENDS, apt' 'rc=0 PM=apt' "$OUT"
pd 'PM_BACKENDS="dnf apt"; pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/bothtools"
check_eq 'the order of PM_BACKENDS is the order of the tools' 'rc=0 PM=dnf' "$OUT"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/emptybin"
check_eq 'no os-release and no tool: a failure (status 1, apt as the fallback value)' 'rc=1 PM=apt' "$OUT"
# Every manager with a backend is tied to its family (the real PM_BACKENDS decides, no override).
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr arch)" PATH="$SB/emptybin"
check_eq 'family arch is pacman' 'rc=0 PM=pacman' "$OUT"
pd 'pm_detect' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr opensuse-leap)" PATH="$SB/emptybin"
check_eq 'family suse is zypper' 'rc=0 PM=zypper' "$OUT"

echo "-- MINTAPP_PM and the manager at start (4.6, step 4e)"
new_sandbox
app_run $'\n0\n' MINTAPP_PM=xbps
check_eq 'an invalid MINTAPP_PM stops the program with 1' 1 "$RC"
assert_contains 'the error names the value and the managers that have a backend' "$OUT" 'MINTAPP_PM=xbps is not a valid package manager (supported: apt, dnf, pacman, zypper).'
check_eq 'and nothing runs: no apt, no privileges' '0:0' "$(apt_log | wc -l):$(sudo_log | wc -l)"
app_run $'\n0\n' MINTAPP_PM=xbps MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'the error follows the language' "$OUT" 'MINTAPP_PM=xbps no es un gestor de paquetes válido (admitidos: apt, dnf, pacman, zypper).'
app_run $'\n0\n' MINTAPP_PM=$'a\e[31mb'
assert_not_contains 'a control character of the value is not written as it is' "$OUT" $'\e[31m'
app_run $'\n0\n' MINTAPP_PM=apt PATH="$SB/emptybin"
assert_contains 'MINTAPP_PM=apt without dpkg: the usual error' "$OUT" 'requires dpkg'
mkdir -p "$SB/onlydpkg"
printf '#!/bin/sh\nexit 0\n' > "$SB/onlydpkg/dpkg"
chmod 755 "$SB/onlydpkg/dpkg"
app_run $'\n0\n' MINTAPP_PM=apt PATH="$SB/onlydpkg"
assert_contains 'MINTAPP_PM=apt with dpkg but without apt-get: the usual error' "$OUT" 'requires apt.'
app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr debian)"
check_eq 'an empty MINTAPP_PM starts normally, and the family of the system chooses' 0 "$RC"
app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/emptybin"
check_eq 'no manager to be found: the program stops with 1' 1 "$RC"
assert_contains 'the error says that nothing was found and lists the managers that have a backend' "$OUT" 'MintApp Remover did not find a package manager it supports (supported: apt, dnf, pacman, zypper).'
assert_not_contains 'and it is not the error of a forced manager' "$OUT" 'MINTAPP_PM='
app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$SB/no-such-file" PATH="$SB/emptybin" MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'the error follows the language' "$OUT" 'MintApp Remover no encontró ningún gestor de paquetes que admita (admitidos: apt, dnf, pacman, zypper).'
check_eq 'and nothing runs: no apt, no privileges' '0:0' "$(apt_log | wc -l):$(sudo_log | wc -l)"

echo "-- dnf at start: dnf and rpm present, and dnf 4 only (4.6, step 4e)"
# dnf_version_stub: a dnf that logs its arguments, prints FAKE_DNF_VERSION and ends with FAKE_DNF_RC.
dnf_version_stub() {
    printf '#!/bin/sh\necho "dnf $*" >> "%s/state/dnf.log"\nprintf "%%s" "${FAKE_DNF_VERSION-}"\nexit "${FAKE_DNF_RC:-0}"\n' "$SB" > "$SB/bin/dnf"
    chmod 755 "$SB/bin/dnf"
}
rpm_stub() { printf '#!/bin/sh\nexit 0\n' > "$SB/bin/rpm"; chmod 755 "$SB/bin/rpm"; }
# dv VERSION_OUTPUT [VAR=val...]: dnf_version_ok against that "dnf --version"; OUT is "rc=STATUS [FIRST LINE]".
dv() { app_eval 'dnf_version_ok; echo "rc=$? [$REPLY]"' FAKE_DNF_VERSION="$1" "${@:2}"; }
new_sandbox
dnf_version_stub
rpm_stub
dnf5_out=$'dnf5 version 5.2.6.2\ndnf5 plugin API version 2.0\nlibdnf5 version 5.2.6.2\nlibdnf5 plugin API version 2.0'
dnf4_out=$'4.19.0\n  Installed: dnf-0:4.19.0-1.fc40.noarch at Fri 05 Jul 2024 00:00:00 UTC\n  Built    : Fedora Project at Fri 05 Jul 2024 00:00:00 UTC\n\n  Installed: rpm-0:4.19.1.1-1.fc40.x86_64 at Fri 05 Jul 2024 00:00:00 UTC'
dv '4.14.0'
check_eq 'dnf 4.14.0 (the version measured, Ubuntu 24.04): supported' 'rc=0 [4.14.0]' "$OUT"
dv "$dnf4_out"
check_eq 'dnf 4 as a Fedora prints it (more lines after the version): supported, and only the first line is kept' 'rc=0 [4.19.0]' "$OUT"
for good in 4.7.0 4.0.0 4.20.1 4.14; do
    dv "$good"
    check_eq "dnf $good (RHEL 8 or another dnf 4): supported" "rc=0 [$good]" "$OUT"
done
dv "$dnf5_out"
check_eq 'dnf 5 (Fedora 41 and later): refused, with its first line' 'rc=1 [dnf5 version 5.2.6.2]' "$OUT"
for bad_ver in 5.0.0 3.9.0 40.1 4 x4.1 ' 4.14.0' 'v4.14.0' 'dnf 4.14.0' '4.' '4.x' '4.a'; do
    dv "$bad_ver"
    check_eq "dnf says \"$bad_ver\": not dnf 4" "rc=1 [$bad_ver]" "$OUT"
done
dv ''
check_eq 'dnf says nothing: not supported, an empty first line' 'rc=1 []' "$OUT"
dv '4.14.0' FAKE_DNF_RC=1
check_eq 'only the text counts: a dnf that prints 4.14.0 and then fails is dnf 4' 'rc=0 [4.14.0]' "$OUT"
check_eq 'dnf is asked its version and nothing else' 'dnf --version' "$(tail -n1 "$SB/state/dnf.log")"
printf '#!/bin/sh\necho "Traceback (most recent call last)" >&2\nexit 1\n' > "$SB/bin/dnf"
app_eval 'dnf_version_ok; echo "rc=$? [$REPLY]"'
check_eq 'a dnf that only fails (an error on stderr, nothing on stdout) is not supported, and the error is not shown' 'rc=1 []' "$OUT"

echo "-- dnf at start: what the program does (4.6, step 4e)"
new_sandbox
dnf_version_stub
rpm_stub
app_run $'\n0\n' MINTAPP_PM=dnf FAKE_DNF_VERSION=4.14.0
check_eq 'MINTAPP_PM=dnf with dnf 4 and rpm: the program starts' 0 "$RC"
check_eq 'it asked dnf its version, once, and nothing else' 'dnf --version' "$(cat "$SB/state/dnf.log")"
check_eq 'and apt was not used' 0 "$(apt_log | wc -l)"
mkdir -p "$SB/nodnf" "$SB/norpm"
cp "$SB/bin/rpm" "$SB/nodnf/rpm"; cp "$SB/bin/dnf" "$SB/norpm/dnf"; cp "$SB/bin/sudo" "$SB/nodnf/sudo"; cp "$SB/bin/sudo" "$SB/norpm/sudo"
: > "$SB/state/dnf.log"
app_run $'\n0\n' MINTAPP_PM=dnf PATH="$SB/nodnf" FAKE_DNF_VERSION=4.14.0
check_eq 'dnf missing: the program stops with 1' 1 "$RC"
assert_contains 'dnf missing: it says that dnf and rpm are needed' "$OUT" 'MintApp Remover requires dnf and rpm.'
app_run $'\n0\n' MINTAPP_PM=dnf PATH="$SB/norpm" FAKE_DNF_VERSION=4.14.0
check_eq 'rpm missing: the program stops with 1' 1 "$RC"
assert_contains 'rpm missing: the same message' "$OUT" 'MintApp Remover requires dnf and rpm.'
app_run $'\n0\n' MINTAPP_PM=dnf PATH="$SB/nodnf" FAKE_DNF_VERSION=4.14.0 MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'the message follows the language' "$OUT" 'MintApp Remover requiere dnf y rpm.'
check_eq 'with dnf or rpm missing, dnf was not asked anything' '' "$(cat "$SB/state/dnf.log")"
app_run $'\n0\n' MINTAPP_PM=dnf FAKE_DNF_VERSION="$dnf5_out"
check_eq 'dnf 5: the program stops with 1' 1 "$RC"
assert_contains 'dnf 5: the message shows what dnf said and that dnf 5 is not supported' "$OUT" \
    'MintApp Remover requires dnf 4, and "dnf --version" says: "dnf5 version 5.2.6.2". dnf 5 (Fedora 41 and later) is not supported yet.'
app_run $'\n0\n' MINTAPP_PM=dnf FAKE_DNF_VERSION="$dnf5_out" MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'dnf 5: the message follows the language' "$OUT" \
    'MintApp Remover requiere dnf 4 y "dnf --version" dice: "dnf5 version 5.2.6.2". dnf 5 (Fedora 41 y posteriores) aún no es compatible.'
check_eq 'dnf 5: nothing ran, no apt and no privileges' '0:0' "$(apt_log | wc -l):$(sudo_log | wc -l)"
app_run $'\n0\n' MINTAPP_PM=dnf FAKE_DNF_VERSION=''
check_eq 'dnf that says nothing: the program stops with 1' 1 "$RC"
assert_contains 'dnf that says nothing: the message shows an empty text' "$OUT" '"dnf --version" says: "".'
app_run $'\n0\n' MINTAPP_PM=dnf FAKE_DNF_VERSION=$'x\e[31mred\tz'
check_eq 'a version with a control character: the program stops with 1' 1 "$RC"
assert_not_contains 'its escape code is not written' "$OUT" $'\e[31m'
assert_contains 'the rest of the text is' "$OUT" '"dnf --version" says: "x[31mred z".'
app_run $'\n0\n' MINTAPP_PM=dnf FAKE_DNF_VERSION="$(printf 'v%.0s' $(seq 1 100))"
assert_contains 'a long first line is cut, with "..."' "$OUT" "$(printf 'v%.0s' $(seq 1 61))..."
assert_not_contains 'and the whole line is not written' "$OUT" "$(printf 'v%.0s' $(seq 1 65))"
# The manager that the family chooses goes through the same check, and only the chosen one is asked.
app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr fedora)" FAKE_DNF_VERSION="$dnf5_out"
check_eq 'Fedora (dnf by its family) with dnf 5: the program stops with 1' 1 "$RC"
assert_contains 'the same error' "$OUT" 'dnf 5 (Fedora 41 and later) is not supported yet.'
: > "$SB/state/dnf.log"
app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr debian)" FAKE_DNF_VERSION="$dnf5_out"
check_eq 'Debian with a dnf 5 around: the program starts with apt' 0 "$RC"
check_eq 'and dnf was not asked anything (only the chosen manager is checked)' '' "$(cat "$SB/state/dnf.log")"

echo "-- the real dnf at start (4.6, step 4e)"
# Measured: dnf 4.14.0 (Ubuntu 24.04) prints its version alone on the first line, and dnf handles --version
# before it reads its configuration or loads a plugin, so nothing can come before the version. These cases
# use the dnf and the rpm of the machine and are skipped where there are none (apt: the packages "dnf" and
# "rpm"). The verdict is compared with what that dnf says, so a machine with dnf 5 checks the refusal.
if command -v dnf > /dev/null 2>&1 && command -v rpm > /dev/null 2>&1; then
    new_sandbox
    real_first="$(dnf --version 2> /dev/null | head -n1 || true)"
    if [[ "$real_first" =~ ^4\.[0-9]+ ]]; then real_rc=0; else real_rc=1; fi
    app_eval 'dnf_version_ok; echo "rc=$? [$REPLY]"'
    check_eq "the real dnf says \"$real_first\": the verdict follows its first line" "rc=$real_rc [$real_first]" "$OUT"
    app_run $'\n0\n' MINTAPP_PM=dnf
    check_eq 'MINTAPP_PM=dnf with the real dnf and rpm: it starts with dnf 4 and stops with another' "$real_rc" "$RC"
    check_eq 'and apt was not used' 0 "$(apt_log | wc -l)"
    if [ "$real_rc" -eq 1 ]; then
        assert_contains 'dnf is not 4: the message shows what dnf said' "$OUT" "\"dnf --version\" says: \"$real_first\"."
    fi
    app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr fedora)"
    check_eq 'Fedora (dnf by its family) with the real dnf: the same verdict' "$real_rc" "$RC"
elif [ -n "${CI:-}" ]; then
    check_eq 'CI: dnf and rpm are installed' 'installed' 'missing'
else
    skip_case 'the real dnf at start (dnf or rpm not installed)'
fi

echo "-- pacman and zypper at start: the tools each one needs (4.6, steps 5e and 6e)"
# Preflight only looks for the tools in the PATH: it asks none of them anything. The main menu does ask
# the manager it works with (the count of its status line, F7.0), so the preflight is run on its own,
# and the whole program is checked for what it asks only with apt, where none of these tools is the chosen one.
new_sandbox
tool_stub() {
    printf '#!/bin/sh\necho "%s $*" >> "%s/state/tools.log"\nexit 0\n' "$1" "$SB" > "$SB/bin/$1"
    chmod 755 "$SB/bin/$1"
}
for tool in pacman pacman-conf zypper rpm; do tool_stub "$tool"; done
# only_with NAME TOOL...: a PATH folder with the privilege command and just those tools (the others are missing).
only_with() {
    local dir="$SB/$1" t
    shift
    mkdir -p "$dir"
    cp "$SB/bin/sudo" "$dir/sudo"
    for t in "$@"; do cp "$SB/bin/$t" "$dir/$t"; done
}
only_with nopacman pacman-conf
only_with nopacmanconf pacman
only_with nozypper rpm
only_with norpmz zypper
: > "$SB/state/tools.log"
app_eval 'preflight_checks; echo ok' MINTAPP_PM=pacman; pre_pacman="$OUT"
app_eval 'preflight_checks; echo ok' MINTAPP_PM=zypper; pre_zypper="$OUT"
check_eq 'the preflight of pacman and of zypper passes, asks none of the tools anything and does not use apt' 'ok:ok:0:0' \
    "$pre_pacman:$pre_zypper:$(wc -l < "$SB/state/tools.log"):$(apt_log | wc -l)"
app_run $'\n0\n' MINTAPP_PM=pacman
check_eq 'MINTAPP_PM=pacman with pacman and pacman-conf: the program starts' 0 "$RC"
app_run $'\n0\n' MINTAPP_PM=zypper
check_eq 'MINTAPP_PM=zypper with zypper and rpm: the program starts' 0 "$RC"
: > "$SB/state/tools.log"
app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr debian)"
check_eq 'Debian with every tool around: the program starts' 0 "$RC"
check_eq 'Debian with every tool around: none of them was asked anything, and apt was not used' '0:0' "$(wc -l < "$SB/state/tools.log"):$(apt_log | wc -l)"
app_run $'\n0\n' MINTAPP_PM=pacman PATH="$SB/nopacman"
check_eq 'pacman missing: the program stops with 1' 1 "$RC"
assert_contains 'pacman missing: it says that pacman and pacman-conf are needed' "$OUT" 'MintApp Remover requires pacman and pacman-conf.'
app_run $'\n0\n' MINTAPP_PM=pacman PATH="$SB/nopacmanconf"
check_eq 'pacman-conf missing: the program stops with 1' 1 "$RC"
assert_contains 'pacman-conf missing: the same message' "$OUT" 'MintApp Remover requires pacman and pacman-conf.'
app_run $'\n0\n' MINTAPP_PM=pacman PATH="$SB/nopacman" MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'the pacman message follows the language' "$OUT" 'MintApp Remover requiere pacman y pacman-conf.'
app_run $'\n0\n' MINTAPP_PM=zypper PATH="$SB/nozypper"
check_eq 'zypper missing: the program stops with 1' 1 "$RC"
assert_contains 'zypper missing: it says that zypper and rpm are needed' "$OUT" 'MintApp Remover requires zypper and rpm.'
app_run $'\n0\n' MINTAPP_PM=zypper PATH="$SB/norpmz"
check_eq 'rpm missing: the program stops with 1' 1 "$RC"
assert_contains 'rpm missing: the same message' "$OUT" 'MintApp Remover requires zypper and rpm.'
app_run $'\n0\n' MINTAPP_PM=zypper PATH="$SB/nozypper" MINTAPP_LANG=es MINTAPP_ASCII=0
assert_contains 'the zypper message follows the language' "$OUT" 'MintApp Remover requiere zypper y rpm.'
# The family decides the manager without looking at the PATH, so a missing tool is told, not skipped.
app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr opensuse-leap)" PATH="$SB/nozypper"
check_eq 'openSUSE (zypper by its family) without zypper: the program stops with 1' 1 "$RC"
assert_contains 'openSUSE without zypper: the zypper message' "$OUT" 'MintApp Remover requires zypper and rpm.'
app_run $'\n0\n' MINTAPP_PM= MINTAPP_OS_RELEASE="$(osr arch)" PATH="$SB/nopacman"
check_eq 'Arch (pacman by its family) without pacman: the program stops with 1' 1 "$RC"
assert_contains 'Arch without pacman: the pacman message' "$OUT" 'MintApp Remover requires pacman and pacman-conf.'
check_eq 'with the tools missing, nothing ran: no apt and no privileges' '0:0' "$(apt_log | wc -l):$(sudo_log | wc -l)"

echo "-- --help and PM_BACKENDS (4.6, step 4e)"
new_sandbox
app_eval 'printf "%s" "${PM_BACKENDS// /|}"'
pm_values="$OUT"
check_eq 'control: the values of MINTAPP_PM are the managers of PM_BACKENDS' 'apt|dnf|pacman|zypper' "$pm_values"
for help_lang in en es; do
    app_run '' MINTAPP_LANG=$help_lang MINTAPP_ASCII=0 -- --help
    assert_contains "--help gives the managers of PM_BACKENDS as the values of MINTAPP_PM ($help_lang)" "$OUT" $'  MINTAPP_PM='"$pm_values"$'\n'
done
# The comment at the top of the program lists the same managers (it is a comment: code_only would drop it).
header_values="$(sed -nE 's/^#[[:space:]]+MINTAPP_PM=([a-z|]+)([[:space:]].*)?$/\1/p' "$H_SCRIPT")"
check_eq 'the header of the program gives the managers of PM_BACKENDS as the values of MINTAPP_PM' "$pm_values" "$header_values"
app_run '' MINTAPP_LANG=en -- --help
assert_contains '--help (English): the default is the manager of the distribution' "$OUT" 'Force the package manager (default: the one the distribution uses).'
app_run '' MINTAPP_LANG=es MINTAPP_ASCII=0 -- --help
assert_contains '--help (Spanish): the default is the manager of the distribution' "$OUT" 'Fuerza el gestor de paquetes (por defecto, el que usa la distribución).'

echo "-- pm_simulate: the plan of a purge or an autoremove, with no privileges (4.6)"
# sim ARG...: pm_simulate with those arguments; OUT is "st=STATUS" and then the plan it left in PLAN_OUTPUT.
sim() { app_eval "pm_simulate $(printf '%q ' "$@"); echo \"st=\$?\"; printf '%s\n' \"\$PLAN_OUTPUT\""; }
new_sandbox
fake_installed foo bar
sim purge foo bar
check_eq 'purge: the status of apt-get, 0' 'st=0' "${OUT%%$'\n'*}"
assert_contains 'purge: the plan has a Purg line for each package' "$OUT" $'Purg foo [1.0]\nPurg bar [1.0]'
check_eq 'purge: it runs apt-get -s purge with the packages and nothing else' 'apt-get -s purge foo bar' "$(apt_log)"
check_eq 'purge: and asks for no privileges' '' "$(sudo_log)"
new_sandbox
fake_autoremovable libold1 libold2
sim autoremove
check_eq 'autoremove: the status of apt-get, 0' 'st=0' "${OUT%%$'\n'*}"
assert_contains 'autoremove: the plan has a Remv line for each package' "$OUT" $'Remv libold1 [1.0]\nRemv libold2 [1.0]'
check_eq 'autoremove: it runs apt-get -s autoremove and nothing else' 'apt-get -s autoremove' "$(apt_log)"
check_eq 'autoremove: and asks for no privileges' '' "$(sudo_log)"
new_sandbox
app_eval 'pm_simulate purge foo; echo "st=$?"; printf "%s\n" "$PLAN_OUTPUT"' FAKE_APT_SIM_FAIL=1
check_eq 'a failed simulation: the status of apt-get' 'st=100' "${OUT%%$'\n'*}"
assert_contains 'a failed simulation: PLAN_OUTPUT is the error text' "$OUT" 'E: Unable to locate package foo'

new_sandbox
for refused in 'clean' 'install foo' 'PURGE foo' 'purge-all' '-s purge foo' 'purge;ls foo'; do
    read -ra args <<< "$refused"
    sim "${args[@]}"
    check_eq "pm_simulate $refused: refused, status 2 and an empty plan" 'st=2' "$OUT"
done
app_eval 'pm_simulate "" purge foo; echo "st=$?"'
check_eq 'an empty action is refused' 'st=2' "$OUT"
app_eval 'pm_simulate; echo "st=$?"'
check_eq 'no arguments at all is refused' 'st=2' "$OUT"
check_eq 'none of the refused calls reached apt-get or the privileges' ':' "$(apt_log):$(sudo_log)"
app_eval 'PLAN_OUTPUT=stale; pm_simulate clean; echo "st=$?"; printf "[%s]\n" "$PLAN_OUTPUT"'
check_eq 'a refusal leaves no old plan behind' $'st=2\n[]' "$OUT"
app_eval 'PM=nope; PLAN_OUTPUT=stale; pm_simulate purge foo; echo "st=$?"; printf "[%s]\n" "$PLAN_OUTPUT"'
check_eq 'a manager without backend: status 2 and an empty plan' $'st=2\n[]' "$OUT"
check_eq 'and nothing runs' ':' "$(apt_log):$(sudo_log)"

new_sandbox
fake_installed foo bar
app_eval 'pm_simulate purge foo bar; plan_has_removals "$PLAN_OUTPUT"; echo "has=$?"; plan_package_names "$PLAN_OUTPUT"; echo'
check_eq 'the plan is what plan_has_removals and plan_package_names read' $'has=0\nbar foo ' "$OUT"
app_eval 'pm_simulate purge foo bar; a="$PLAN_OUTPUT"; simulate_apt purge foo bar; [ "$a" = "$PLAN_OUTPUT" ] && echo same'
check_eq 'for apt, pm_simulate leaves exactly the plan of its backend simulate_apt' 'same' "$OUT"
code='pm_simulate() { echo "PS $*"; PLAN_OUTPUT="$PLAN_NOW"; }
PLAN_NOW="Purg foo [1.0]"
plan_still_valid "Purg foo [1.0]" purge foo; echo "same=$?"
PLAN_NOW=$'"'"'Purg foo [1.0]\nPurg bar [1.0]'"'"'
plan_still_valid "Purg foo [1.0]" purge foo; echo "changed=$?"
pm_simulate() { return 1; }
plan_still_valid "Purg foo [1.0]" purge foo; echo "failed=$?"'
app_eval "$code"
check_eq 'plan_still_valid simulates again through pm_simulate, with the same arguments' \
    $'PS purge foo\nsame=0\nPS purge foo\nchanged=1\nfailed=1' "$OUT"

echo "-- the dnf backend: pm_simulate (4.6, step 4b)"
# The fixtures have the shape of what dnf 4.14.0 printed for "remove|autoremove --assumeno" on a fake root
# (LC_ALL=C, --color=never): the table on stdout and "Operation aborted." on stderr, so it comes last in the
# mixed output, and a status of 1 even for a good plan. dnf ends the rows of the table and the "Freed space"
# line with two spaces; dnf_out adds them when it stores the output, because a space at the end of a line
# in this file would fail the "git show --check" that the CI runs on the tests.
FX_RULE="$(printf '%80s' '' | tr ' ' '=')"
UNREADABLE_EN='Could not read the plan of dnf: its output does not have the expected format. Nothing was changed.'
# fx_row NAME [VERSION [ARCH]]: a row of the table.
fx_row() { printf ' %-26s %-13s %-17s %-15s %s\n' "$1" "${3:-noarch}" "${2:-1.0-1}" '@@commandline' '1.0 k'; }
# fx_table N [LINE]: stdin (the sections and their rows) between the head and the summary of a table of N
# removals; LINE, if given, goes before the table (like "No match for argument").
fx_table() {
    printf '%s\n' 'Last metadata expiration check: 0:00:02 ago on Sun Nov  1 10:00:00 2026.'
    [ -z "${2-}" ] || printf '%s\n' "$2"
    printf '%s\n' 'Dependencies resolved.' "$FX_RULE" ' Package                    Architecture  Version           Repository      Size' "$FX_RULE"
    cat
    printf '\nTransaction Summary\n%s\nRemove  %s Package%s\n\nFreed space: %s.0 k\n' "$FX_RULE" "$1" "$([ "$1" = 1 ] || echo s)" "$1"
}
# dnf_out: stores stdin as what the fake dnf prints on stdout, with the two spaces that dnf puts at the end.
dnf_out() { sed -E '/^ [^ ]/ s/$/  /; /^Freed space/ s/$/  /' > "$SB/state/dnf.out"; }
# dnf_err TEXT: what the fake dnf prints on stderr.
dnf_err() { printf '%s\n' "$1" > "$SB/state/dnf.err"; }
# dnf_replay: a dnf that logs its arguments and its LC_ALL, and replays dnf.out (stdout) and dnf.err
# (stderr); FAKE_DNF_RC is its status.
dnf_replay() {
    printf '#!/bin/sh\necho "dnf $*" >> "%s/state/dnf.log"\necho "${LC_ALL-unset}" >> "%s/state/dnf.env"\ncat "%s/state/dnf.out" 2>/dev/null\ncat "%s/state/dnf.err" >&2 2>/dev/null\nexit "${FAKE_DNF_RC:-1}"\n' \
        "$SB" "$SB" "$SB" "$SB" > "$SB/bin/dnf"
    chmod 755 "$SB/bin/dnf"
}
dnf_log() { cat "$SB/state/dnf.log" 2>/dev/null || true; }
dnf_env() { cat "$SB/state/dnf.env" 2>/dev/null || true; }
# sd_reset: a new sandbox with the fake dnf; DNF_RC is its status (1: a good simulation ends with 1) and
# SD_ENV the variables that the next run gets.
DNF_RC=1
SD_ENV=()
sd_reset() { new_sandbox; dnf_replay; DNF_RC=1; SD_ENV=(); }
# sd_eval CODE: CODE with PM=dnf, through the real priv_run (the fake sudo) and the fake dnf.
sd_eval() { app_eval "PM=dnf; $1" FAKE_DNF_RC="$DNF_RC" "${SD_ENV[@]+"${SD_ENV[@]}"}"; }
# simdnf ARG...: pm_simulate with those arguments, starting from an old plan. OUT: "st=STATUS" and then the
# plan between < and >, so that nothing around it can be lost.
simdnf() { sd_eval "PLAN_OUTPUT=stale; pm_simulate $(printf '%q ' "$@"); echo \"st=\$?\"; printf '<%s>\\n' \"\$PLAN_OUTPUT\""; }
sd_unreadable() { check_eq "$1" $'st=1\n<'"$UNREADABLE_EN"'>' "$OUT"; }

# What dnf printed (measured)
sd_reset
{ echo 'Removing:'; fx_row foo; echo 'Removing dependent packages:'; fx_row bar; } | fx_table 2 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
check_eq 'purge with a dependent package: both in the plan, in the order of the table; status 0 although dnf ended with 1' \
    $'st=0\n<Remv foo [1.0-1] (noarch)\nRemv bar [1.0-1] (noarch)>' "$OUT"
check_eq 'purge: dnf got remove --assumeno --color=never and the name, and nothing else' 'dnf remove --assumeno --color=never foo' "$(dnf_log)"
check_eq 'purge: the privilege command ran dnf in the C locale' 'sudo LC_ALL=C dnf remove --assumeno --color=never foo' "$(sudo_log)"
simdnf purge foo bar
check_eq 'purge of two packages: both names reach dnf, in order' 'dnf remove --assumeno --color=never foo bar' "$(dnf_log | tail -n1)"
sd_reset
{ echo 'Removing:'; fx_row foo 2.4.1-3.fc40 x86_64; echo 'Removing dependent packages:'; fx_row foo-gui 2.4.1-3.fc40 x86_64
  echo 'Removing unused dependencies:'; fx_row libfoo 1:0.9-2.fc40 x86_64; fx_row foo-data 2.4.1-3.fc40; } | fx_table 4 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
check_eq 'purge with dependents and unused dependencies: the three sections, with epoch, release and architecture' \
    $'st=0\n<Remv foo [2.4.1-3.fc40] (x86_64)\nRemv foo-gui [2.4.1-3.fc40] (x86_64)\nRemv libfoo [1:0.9-2.fc40] (x86_64)\nRemv foo-data [2.4.1-3.fc40] (noarch)>' "$OUT"
sd_reset
long='python3-a-very-long-package_name.with+symbols-and-more-segments-for-the-test-devel'
{ echo 'Removing:'; fx_row "$long" '3.2.1~rc1-4.fc40' x86_64; fx_row 'libstdc++-devel' 14.1.1-5.fc40 x86_64; fx_row 'perl-Foo_Bar' 1.0-1.fc40; } | fx_table 3 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
check_eq 'long names, with _ + . and ~ in the version: each on one line and read whole' \
    "st=0"$'\n'"<Remv $long [3.2.1~rc1-4.fc40] (x86_64)"$'\n''Remv libstdc++-devel [14.1.1-5.fc40] (x86_64)'$'\n''Remv perl-Foo_Bar [1.0-1.fc40] (noarch)>' "$OUT"
sd_eval "pm_simulate purge foo; plan_package_names \"\$PLAN_OUTPUT\" | tr ' ' '\\n' | while read -r n; do [ -z \"\$n\" ] || { pm_valid_name \"\$n\" && echo ok || echo \"bad:\$n\"; }; done | sort | uniq -c | tr -s ' ' | tr '\\n' ';'"
check_eq 'every name read from a dnf plan passes pm_valid_name (dnf)' ' 3 ok;' "$OUT"
sd_reset
{ echo 'Removing:'; fx_row libold; } | fx_table 1 | dnf_out
dnf_err 'Operation aborted.'
simdnf autoremove
check_eq 'autoremove with one package (listed under Removing:, "Remove  1 Package")' $'st=0\n<Remv libold [1.0-1] (noarch)>' "$OUT"
check_eq 'autoremove: dnf got autoremove --assumeno --color=never and nothing else' 'dnf autoremove --assumeno --color=never' "$(dnf_log)"
check_eq 'autoremove: through the privilege command, in the C locale' 'sudo LC_ALL=C dnf autoremove --assumeno --color=never' "$(sudo_log)"
sd_reset
printf '%s\n' 'Last metadata expiration check: 0:00:02 ago on Sun Nov  1 10:00:00 2026.' 'Dependencies resolved.' 'Nothing to do.' 'Complete!' | dnf_out
DNF_RC=0
simdnf autoremove
check_eq 'autoremove with nothing to remove (dnf ends with 0): status 0 and an empty plan, not an old one' $'st=0\n<>' "$OUT"
sd_reset
printf '%s\n' 'Last metadata expiration check: 0:00:02 ago on Sun Nov  1 10:00:00 2026.' 'No match for argument: nosuch' 'No packages marked for removal.' \
    'Dependencies resolved.' 'Nothing to do.' 'Complete!' | dnf_out
DNF_RC=0
simdnf purge nosuch
check_eq 'purge that matches nothing installed (dnf ends with 0): an error, status 1, with what dnf said' \
    $'st=1\n<No match for argument: nosuch\nNo packages marked for removal.>' "$OUT"
sd_reset
printf '%s\n' 'No match for argument: nosuch' '' | dnf_out
dnf_err 'Error: No packages marked for removal.'
simdnf purge nosuch
check_eq 'the same, in the dnf that ends with 1: status 1 and its error' $'st=1\n<No match for argument: nosuch\nError: No packages marked for removal.>' "$OUT"
sd_reset
{ echo 'Removing:'; fx_row foo; } | fx_table 1 'No match for argument: nosuch' | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo nosuch
check_eq 'a partial match: the plan holds what matched, and the "No match" line is not in it' $'st=0\n<Remv foo [1.0-1] (noarch)>' "$OUT"
sd_reset
dnf_err 'The operation would result in removing the following protected packages: dnf'
simdnf purge dnf
check_eq 'a protected package (no table, the reason on stderr): status 1 and the reason as the text' \
    $'st=1\n<The operation would result in removing the following protected packages: dnf>' "$OUT"
for rc in 1 2 200; do
    sd_reset
    dnf_err "Error: Failed to download metadata for repo 'fedora': Cannot download repomd.xml"
    DNF_RC=$rc
    simdnf purge foo
    check_eq "dnf fails with $rc: that status, and its error as the text" "st=$rc"$'\n'"<Error: Failed to download metadata for repo 'fedora': Cannot download repomd.xml>" "$OUT"
done

# Plans that cannot be read: an error, never a plan
sd_reset
{ echo 'Removing:'; fx_row foo; fx_row bar; } | fx_table 3 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
sd_unreadable 'fewer rows than the summary says (2 of 3): not a plan'
sd_reset
{ echo 'Removing:'; fx_row foo; fx_row bar; fx_row baz; } | fx_table 2 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
sd_unreadable 'more rows than the summary says (3 of 2): not a plan'
sd_reset
{ echo 'Removing:'; fx_row foo; } | fx_table 0 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
sd_unreadable 'a table of 1 row for a summary of 0 packages: not a plan'
sd_reset
fx_table 0 < /dev/null | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
sd_unreadable 'a summary of 0 packages and no rows: not a plan (a plan has at least one removal)'
sd_reset
fx_table 1 < /dev/null | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
sd_unreadable 'a summary of 1 package and no rows: not a plan'
for rc in 0 1; do
    sd_reset
    { echo 'Removing:'; fx_row foo; } | fx_table 1 | dnf_out
    DNF_RC=$rc
    simdnf purge foo
    sd_unreadable "a table without \"Operation aborted.\" (dnf ended with $rc): not a plan, it may have run the removal"
done
for word in Install Upgrade Downgrade Reinstall Skip; do
    sd_reset
    { echo 'Removing:'; fx_row foo; } | fx_table 1 | sed "s/^Remove  /$word  1 Package\n&/" | dnf_out
    dnf_err 'Operation aborted.'
    simdnf purge foo
    sd_unreadable "\"$word\" in the summary next to a good removal: not a plan"
done
for section in 'Installing dependencies:' 'Installing weak dependencies:' 'Upgrading:' 'Downgrading:' 'Reinstalling:'; do
    sd_reset
    { echo 'Removing:'; fx_row foo; echo "$section"; fx_row bar; } | fx_table 2 | dnf_out
    dnf_err 'Operation aborted.'
    simdnf purge foo
    sd_unreadable "a section of another kind inside the table ($section), with rows that make the count agree: not a plan"
done
sd_reset
{ echo 'Removing:'; fx_row $'\e[1mfoo\e[0m'; } | fx_table 1 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
sd_unreadable 'an escape code in the name of a row (color=always): not a plan'
sd_reset
{ echo 'Removing:'; fx_row $'fo\ao'; } | fx_table 1 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
sd_unreadable 'a control character inside a name: not a plan'
sd_reset
{ echo 'Removing:'; fx_row foo | sed $'s/$/\r/'; } | fx_table 1 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
sd_unreadable 'a carriage return at the end of a row: not a plan'
for short in 'foo' 'foo  noarch'; do
    sd_reset
    { echo 'Removing:'; printf ' %s\n' "$short"; } | fx_table 1 | dnf_out
    dnf_err 'Operation aborted.'
    simdnf purge foo
    sd_unreadable "a row with fewer than 3 fields ('$short'): not a plan"
done
sd_reset
{ echo 'Removing:'; printf ' %s\n' 'foo  noarch  1.0-1'; } | fx_table 1 | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
check_eq 'a row of exactly 3 fields (name, architecture, version) is read' $'st=0\n<Remv foo [1.0-1] (noarch)>' "$OUT"
sd_reset
printf '%s\n' 'Package          Arch   Version     Repository      Size' 'Removing:' ' foo             noarch 1.0-1       @System      1.0 KiB' \
    'Removing dependent packages:' ' bar             noarch 1.0-1       @System      1.0 KiB' '' 'Transaction Summary:' ' Removing:           2 packages' '' | dnf_out
dnf_err 'Operation aborted by the user.'
simdnf purge foo
sd_unreadable 'a table in the style of dnf 5 (from memory, never measured): not a plan'
sd_reset
{ printf '%s\n' 'Dependencies resolved.' "$FX_RULE" 'Removing:'; fx_row foo; } | dnf_out
dnf_err 'Operation aborted.'
simdnf purge foo
check_eq 'a table cut before its summary: status 1' 'st=1' "${OUT%%$'\n'*}"
assert_not_contains 'a table cut before its summary: nothing in PLAN_OUTPUT looks like a plan line' "$OUT" 'Remv '
sd_reset
DNF_RC=0
simdnf autoremove
sd_unreadable 'autoremove: no output at all with status 0 is not "nothing to do"'
sd_reset
printf '%s\n' 'Dependencies resolved.' 'Nothing to do.' '' 'Transaction Summary' "$FX_RULE" 'Install  1 Package' 'Complete!' | dnf_out
DNF_RC=0
simdnf autoremove
sd_unreadable 'autoremove: "Nothing to do." next to a summary that installs is not "nothing to do"'
sd_reset
printf '%s\n' 'Dependencies resolved.' 'Nothing to do.' 'Complete!' | dnf_out
DNF_RC=1
simdnf autoremove
sd_unreadable 'autoremove: "Nothing to do." but dnf ended with 1 is a failure, not "nothing to do"'
sd_reset
DNF_RC=0
simdnf purge foo
sd_unreadable 'purge: no output at all with status 0: not a plan, and not a success'

# Failures and refusals
sd_reset
for rc in 1 77 127; do
    sd_eval "priv_run() { echo 'sudo: a password is required' >&2; return $rc; }; pm_simulate purge foo; echo \"st=\$?\"; printf '<%s>\\n' \"\$PLAN_OUTPUT\""
    check_eq "the privilege command fails with $rc: that status, and what it said as the text" "st=$rc"$'\n<sudo: a password is required>' "$OUT"
done
sd_eval 'priv_run() { return 127; }; pm_simulate purge foo; echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
sd_check_127=$'st=127\n<'"$UNREADABLE_EN"'>'
check_eq 'a privilege command that fails without a word: its status, and a text (never an empty one)' "$sd_check_127" "$OUT"
check_eq 'a failure of the privilege command never reached dnf' '' "$(dnf_log)"
sd_reset
for refused in 'clean' 'install foo' 'remove foo' 'PURGE foo' 'purge-all' '-s purge foo' 'purge;ls foo'; do
    read -ra args <<< "$refused"
    simdnf "${args[@]}"
    check_eq "dnf, pm_simulate $refused: refused, status 2 and an empty plan (the old one is gone)" $'st=2\n<>' "$OUT"
done
simdnf '' purge foo
check_eq 'dnf: an empty action is refused' $'st=2\n<>' "$OUT"
sd_eval 'pm_simulate; echo "st=$?"'
check_eq 'dnf: no arguments at all is refused' 'st=2' "$OUT"
check_eq 'none of the refused calls reached dnf or the privileges' ':' "$(dnf_log):$(sudo_log)"
sd_reset
printf '%s\n' 'No match for argument: nosuch' | dnf_out
SD_ENV=(MINTAPP_LANG=es MINTAPP_ASCII=0)
DNF_RC=1
simdnf purge nosuch
check_eq 'the text of an error that dnf gives is dnf'"'"'s, whatever the language' $'st=1\n<No match for argument: nosuch>' "$OUT"
sd_reset
{ echo 'Removing:'; fx_row foo; } | fx_table 3 | dnf_out
dnf_err 'Operation aborted.'
SD_ENV=(MINTAPP_LANG=es MINTAPP_ASCII=0)
simdnf purge foo
check_eq 'an unreadable plan, in Spanish' $'st=1\n<No se pudo leer el plan de dnf: su salida no tiene el formato esperado. No se cambió nada.>' "$OUT"
SD_ENV=(MINTAPP_LANG=en)
simdnf purge foo
sd_unreadable 'an unreadable plan, in English'

# Integration
sd_reset
{ echo 'Removing:'; fx_row foo; } | fx_table 1 | dnf_out
dnf_err 'Operation aborted.'
SD_ENV=(LC_ALL=C.UTF-8 LANGUAGE=es)
simdnf purge foo
check_eq 'dnf runs in the C locale even if the caller has another (LC_ALL and LANGUAGE)' 'C' "$(dnf_env)"
sd_reset
{ echo 'Removing:'; fx_row foo; } | fx_table 1 | dnf_out
dnf_err 'Operation aborted.'
simdnf autoremove
check_eq 'dnf runs with LC_ALL=C when the caller sets nothing' 'C' "$(dnf_env)"
sd_reset
{ echo 'Removing:'; fx_row foo; echo 'Removing dependent packages:'; fx_row bar; } | fx_table 2 | dnf_out
dnf_err 'Operation aborted.'
sd_eval 'pm_simulate purge foo; plan_has_removals "$PLAN_OUTPUT"; echo "has=$?"; plan_package_names "$PLAN_OUTPUT"; echo'
check_eq 'a dnf plan is what plan_has_removals and plan_package_names read' $'has=0\nbar foo ' "$OUT"
sd_eval 'pm_simulate purge foo; a=$(plan_fingerprint "$PLAN_OUTPUT"); pm_simulate purge foo; b=$(plan_fingerprint "$PLAN_OUTPUT"); [ "$a" = "$b" ] && [ -n "$a" ] && echo same'
check_eq 'the fingerprint of a dnf plan is the same for the same plan' 'same' "$OUT"
sd_reset
{ echo 'Removing:'; fx_row foo; } | fx_table 1 | dnf_out
dnf_err 'Operation aborted.'
{ echo 'Removing:'; fx_row foo; echo 'Removing dependent packages:'; fx_row bar; } | fx_table 2 > "$SB/state/dnf.out2"
sed -E -i '/^ [^ ]/ s/$/  /' "$SB/state/dnf.out2"
printf '%s\n' 'Error: boom' > "$SB/state/dnf.out3"
sd_eval "pm_simulate purge foo; plan=\$PLAN_OUTPUT
plan_still_valid \"\$plan\" purge foo; echo \"same=\$?\"
rm -f -- '$SB/state/dnf.out'; cp -- '$SB/state/dnf.out2' '$SB/state/dnf.out'
plan_still_valid \"\$plan\" purge foo; echo \"changed=\$?\"
rm -f -- '$SB/state/dnf.out'; cp -- '$SB/state/dnf.out3' '$SB/state/dnf.out'
plan_still_valid \"\$plan\" purge foo; echo \"failed=\$?\""
check_eq 'plan_still_valid with dnf: the same plan is valid; another one, or a failure, is not' $'same=0\nchanged=1\nfailed=1' "$OUT"
check_eq 'plan_still_valid simulated three times, always with the same arguments' \
    $'dnf remove --assumeno --color=never foo\ndnf remove --assumeno --color=never foo\ndnf remove --assumeno --color=never foo\ndnf remove --assumeno --color=never foo' "$(dnf_log)"
sd_reset
{ echo 'Removing:'; fx_row foo; echo 'Removing dependent packages:'; fx_row gnome-core; } | fx_table 2 | dnf_out
dnf_err 'Operation aborted.'
sd_eval 'pm_simulate purge foo; plan_meta_packages "$PLAN_OUTPUT" foo; echo "st=$?"'
check_eq 'plan_meta_packages reads the names of a dnf plan (the requested one is left out)' $'gnome-core\nst=0' "$OUT"

echo "-- pm_installed: is the package really installed (4.6)"
new_sandbox
fake_installed foo cfgonly
fake_configfiles cfgonly
pi() { app_eval "pm_installed '$1'; echo \"rc=\$?\"" "${@:2}"; }
pi foo
check_eq 'an installed package' 'rc=0' "$OUT"
pi cfgonly
check_eq 'only its configuration files are left: not installed' 'rc=1' "$OUT"
pi unknown
check_eq 'a package the manager does not know: not installed' 'rc=1' "$OUT"
pi ''
check_eq 'an empty name: not installed' 'rc=1' "$OUT"
app_eval 'PM=nope; pm_installed foo; echo "rc=$?"'
check_eq 'a manager without backend: status 2, even for an installed package' 'rc=2' "$OUT"
check_eq 'asking whether a package is installed needs no privileges' '' "$(sudo_log)"
app_eval 'pm_installed() { [ "$1" = b ]; }; package_installed a,b,c; echo "any=$?"; package_installed a,c; echo "none=$?"; installed_packages_from_list a,b,c'
check_eq 'package_installed and installed_packages_from_list ask pm_installed' $'any=0\nnone=1\nb' "$OUT"
if command -v dpkg-query >/dev/null 2>&1 && [ -r /var/lib/dpkg/status ]; then
    new_sandbox
    app_eval 'pm_installed dpkg; echo "rc=$?"' PATH=/usr/bin:/bin
    check_eq 'the real dpkg-query: dpkg itself is installed' 'rc=0' "$OUT"
    app_eval 'pm_installed mintapp-no-such-package-xyz; echo "rc=$?"' PATH=/usr/bin:/bin
    check_eq 'the real dpkg-query: an unknown package is not' 'rc=1' "$OUT"
else
    skip_case 'the real dpkg-query (not available)'
fi

echo "-- pm_owner: who owns each file (4.6)"
new_sandbox
fake_owner /usr/share/applications/a.desktop pkg-a
fake_owner /usr/share/applications/b.desktop pkg-b1
fake_owner /usr/share/applications/b.desktop pkg-b2
fake_owner '/opt/my app/c d.desktop' pkg-c
app_eval 'pm_owner /usr/share/applications/a.desktop /usr/share/applications/none.desktop /usr/share/applications/b.desktop "/opt/my app/c d.desktop"'
check_eq 'a line "owner: path" for each path somebody owns, none for the rest, no error shown' \
    $'pkg-a: /usr/share/applications/a.desktop\npkg-b1, pkg-b2: /usr/share/applications/b.desktop\npkg-c: /opt/my app/c d.desktop' "$OUT"
check_eq 'one question to the manager for all the paths' 'dpkg -S 4' "$(cat "$SB/state/dpkg.log")"
new_sandbox
app_eval 'pm_owner; echo "rc=$?"'
check_eq 'without paths: status 2' 'rc=2' "$OUT"
app_eval 'PM=nope; pm_owner /usr/share/applications/a.desktop; echo "rc=$?"'
check_eq 'a manager without backend: status 2 and no output' 'rc=2' "$OUT"
check_eq 'and the manager is not asked' 0 "$(dpkg_calls)"
app_eval 'pm_owner() { echo "pkg-x: $1"; echo "pkg-y, pkg-z: $2"; }; load_launcher_owners /x/a.desktop /x/b.desktop; printf "<<%s|%s>>" "${LAUNCHER_OWNERS[/x/a.desktop]:-}" "${LAUNCHER_OWNERS[/x/b.desktop]:-}"'
check_eq 'load_launcher_owners reads what pm_owner prints' '<<pkg-x|pkg-y, pkg-z>>' "$OUT"
app_eval 'pm_owner() { echo "call $#" >&2; }; load_launcher_owners $(seq -f "/x/%g.desktop" 1 250)'
check_eq 'and asks pm_owner in chunks of 200 paths' $'call 200\ncall 50' "$OUT"
if command -v dpkg >/dev/null 2>&1; then
    app_eval 'pm_owner /usr/bin/dpkg /nonexistent/none.desktop' PATH=/usr/bin:/bin
    assert_contains 'the real dpkg: the line has the shape the program reads' "$OUT" 'dpkg: /usr/bin/dpkg'
    assert_not_contains 'the real dpkg: its error for a path nobody owns is not shown' "$OUT" 'none.desktop'
else
    skip_case 'the real dpkg (not available)'
fi

echo "-- the rpm backend: pm_installed and pm_owner (4.6, step 4c)"
# They run the real rpm on a database of synthetic packages built with rpmbuild, so the cases are skipped
# where rpm or rpmbuild is not installed (apt: the package "rpm"). These cases call the functions of the
# backend, so they set PM themselves. Packages (all version 1.0-1) and the files they own, which need
# not exist on disk:
#   fixa  (noarch)  a.txt, "sp ace.txt", -dash.txt, real/r.txt; the folders FX, FX/shared and FX/real
#   fixb  (noarch)  b.txt; the folders FX and FX/shared, which it shares with fixa
#   fixc  (x86_64 and i686)  c.txt
#   fixd  (noarch, epoch 3, 2.5-7)  d.bin, of 2049 bytes
#   fixe, fixf  (noarch)  e.bin of 1024 bytes and f.bin of 1025
#   fixm  (noarch)  no files at all (what the 4d cases call a meta-package)
#   fixn  (noarch)  only a folder (not a meta-package: it is an entry in its list)
# On disk: "unowned" (a file nobody owns) and "lnk" (a link to the folder "real").
RPMFX="$H_TMP/rpmfx"
RPMFX_DB="$H_TMP/rpmdb"
# mkrpm ARCH NAME ENTRY...: builds a package; an ENTRY is a file, "d:FOLDER" for a folder it owns, or
# "z:BYTES:FILE" for a file of that size. MK_VER, MK_REL and MK_EPOCH (all optional) set its version,
# MK_REQ a package it requires and MK_TOP the folder where it is built (default: rpmtop, the one of 4c and 4d).
mkrpm() {
    local arch="$1" name="$2" entry spec="$H_TMP/rpmspec-$2-$1.spec"
    shift 2
    {
        printf 'Name: %s\nVersion: %s\nRelease: %s\nSummary: fixture\nLicense: MIT\n' "$name" "${MK_VER:-1.0}" "${MK_REL:-1}"
        if [ -n "${MK_EPOCH:-}" ]; then printf 'Epoch: %s\n' "$MK_EPOCH"; fi
        if [ -n "${MK_REQ:-}" ]; then printf 'Requires: %s\n' "$MK_REQ"; fi
        if [ "$arch" = noarch ]; then printf 'BuildArch: noarch\n'; fi
        printf '%%description\nfixture\n%%install\n'
        for entry in "$@"; do
            case "$entry" in
                d:*) printf 'mkdir -p "%%{buildroot}%s"\n' "${entry#d:}" ;;
                z:*) printf 'mkdir -p "%%{buildroot}%s"\nhead -c %s /dev/zero > "%%{buildroot}%s"\n' "$(dirname "${entry#z:*:}")" "$(cut -d: -f2 <<< "$entry")" "${entry#z:*:}" ;;
                *) printf 'mkdir -p "%%{buildroot}%s"\n: > "%%{buildroot}%s"\n' "${entry%/*}" "$entry" ;;
            esac
        done
        printf '%%files\n'
        for entry in "$@"; do
            case "$entry" in
                d:*) printf '%%dir "%s"\n' "${entry#d:}" ;;
                z:*) printf '"%s"\n' "${entry#z:*:}" ;;
                *) printf '"%s"\n' "$entry" ;;
            esac
        done
    } > "$spec"
    rpmbuild -bb --quiet --target "$arch-linux" --define "_topdir ${MK_TOP:-$H_TMP/rpmtop}" \
        --define '_build_id_links none' --define '__os_install_post %{nil}' "$spec" > /dev/null 2>&1
}
# build_rpm_fixture: the folder of files and the database, once. Fails if rpm or rpmbuild cannot do it.
build_rpm_fixture() {
    command -v rpm > /dev/null 2>&1 && command -v rpmbuild > /dev/null 2>&1 || return 1
    mkdir -p "$RPMFX/real" "$RPMFX_DB" "$H_TMP/rpmtop" || return 1
    ln -sfn real "$RPMFX/lnk"
    : > "$RPMFX/unowned"
    mkrpm noarch fixa "d:$RPMFX" "d:$RPMFX/shared" "d:$RPMFX/real" "$RPMFX/a.txt" "$RPMFX/sp ace.txt" "$RPMFX/-dash.txt" "$RPMFX/real/r.txt"
    mkrpm noarch fixb "d:$RPMFX" "d:$RPMFX/shared" "$RPMFX/b.txt"
    mkrpm x86_64 fixc "$RPMFX/c.txt"
    mkrpm i686 fixc "$RPMFX/c.txt"
    MK_EPOCH=3 MK_VER=2.5 MK_REL=7 mkrpm noarch fixd "z:2049:$RPMFX/d.bin"
    mkrpm noarch fixe "z:1024:$RPMFX/e.bin"
    mkrpm noarch fixf "z:1025:$RPMFX/f.bin"
    mkrpm noarch fixm
    mkrpm noarch fixn "d:$RPMFX/only-dir"
    rpm --dbpath "$RPMFX_DB" --initdb 2> /dev/null || return 1
    rpm --dbpath "$RPMFX_DB" -i --justdb --nodeps --noscripts --notriggers --ignorearch --ignoreos --replacefiles \
        "$H_TMP"/rpmtop/RPMS/*/*.rpm > /dev/null 2>&1
}
# rpm_sandbox: a new sandbox with an rpm that is the real one on a copy of the database. It logs each call
# with every argument in brackets (rpm_log).
rpm_sandbox() {
    new_sandbox
    cp -a "$RPMFX_DB" "$SB/state/rpmdb"
    : > "$SB/state/rpm.log"
    _stub rpm <<'EOF'
#!/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
S='@STATE@'
printf 'rpm' >> "$S/rpm.log"
for a in "$@"; do printf ' [%s]' "$a" >> "$S/rpm.log"; done
echo >> "$S/rpm.log"
exec rpm --dbpath "$S/rpmdb" "$@"
EOF
    sandbox_chown
}
rpm_log() { cat "$SB/state/rpm.log" 2> /dev/null || true; }

RPMFX_OK=0
if build_rpm_fixture; then
    RPMFX_OK=1
    rpm_sandbox
    ri() { app_eval "PM=dnf; pm_installed '$1'; echo \"rc=\$?\"" "${@:2}"; }
    ri fixa
    check_eq 'rpm: an installed package' 'rc=0' "$OUT"
    check_eq 'rpm: the question is "rpm -q" with the name after "--", asked once' \
        'rpm [-q] [--qf] [%{NAME}\n] [--] [fixa]' "$(rpm_log)"
    ri fixc
    check_eq 'rpm: installed for two architectures (rpm prints the name twice)' 'rc=0' "$OUT"
    ri fixz
    check_eq 'rpm: a package that is not installed (its text goes to stdout, with status 1)' 'rc=1' "$OUT"
    for alias in fixa-1.0 fixa-1.0-1 fixa.noarch fixc.i686 'fix*'; do
        ri "$alias"
        check_eq "rpm: \"$alias\" is not the name of an installed package, though rpm -q may accept it" 'rc=1' "$OUT"
    done
    rpm_sandbox
    ri ''
    check_eq 'rpm: an empty name: not installed' 'rc=1' "$OUT"
    check_eq 'rpm: and rpm is not asked' '' "$(rpm_log)"
    ri -a
    check_eq 'rpm: "-a" is a name, not an option (rpm -q -a would list everything and succeed)' 'rc=1' "$OUT"
    check_eq 'rpm: asking whether a package is installed needs no privileges' '' "$(sudo_log)"
    app_eval 'PM=dnf; installed_packages_from_list fixa,fixz,fixb,fixc; package_installed fixz,fixb; echo "any=$?"; package_installed fixz,fixy; echo "none=$?"'
    check_eq 'rpm: installed_packages_from_list and package_installed ask pm_installed' $'fixa\nfixb\nfixc\nany=0\nnone=1' "$OUT"
    app_eval 'PM=dnf; pm_installed fixa; echo "rc=$?"' PATH="$SB/emptybin"
    check_eq 'rpm: without rpm in the system: not installed, and no error text' 'rc=1' "$OUT"
    # An rpm that answers with another NAME than the one asked. The real one does not (it prints the NAME that
    # matched a name, a name-version or a name.arch), so this fixes what decides: the answer is compared as text.
    _stub rpm <<'EOF'
#!/bin/sh
printf '%s\n' "$RPM_SAYS"
EOF
    app_eval 'PM=dnf; pm_installed fixa; echo "rc=$?"' RPM_SAYS=fixa-extra
    check_eq 'rpm: a NAME that only contains the name asked is not that package' 'rc=1' "$OUT"
    app_eval 'PM=dnf; pm_installed fix.; echo "rc=$?"' RPM_SAYS=fixa
    check_eq 'rpm: the name asked is compared as text, not as a pattern' 'rc=1' "$OUT"

    # ro PATH...: pm_owner with dnf on those paths; OUT ends with "rc=" and its status.
    ro() { local args; printf -v args '%q ' "$@"; app_eval "PM=dnf; pm_owner $args; echo \"rc=\$?\""; }
    rpm_sandbox
    ro "$RPMFX/a.txt"
    check_eq 'rpm owner: the line "package: path" for a path a package owns' "fixa: $RPMFX/a.txt"$'\nrc=0' "$OUT"
    check_eq 'rpm owner: the question is "rpm -qf" with the path after "--"' \
        "rpm [-qf] [--qf] [%{NAME}\\n] [--] [$RPMFX/a.txt]" "$(rpm_log)"
    ro "$RPMFX/shared"
    check_eq 'rpm owner: two packages share it: both names, sorted, on one line' "fixa, fixb: $RPMFX/shared"$'\nrc=0' "$OUT"
    ro "$RPMFX/c.txt"
    check_eq 'rpm owner: one package for two architectures: its name once' "fixc: $RPMFX/c.txt"$'\nrc=0' "$OUT"
    ro "$RPMFX/unowned"
    check_eq 'rpm owner: a file nobody owns: no line, no text of rpm' 'rc=0' "$OUT"
    ro "$RPMFX/nope"
    check_eq 'rpm owner: a path that does not exist: no line, no error shown' 'rc=0' "$OUT"
    ro "$RPMFX/lnk/r.txt"
    check_eq 'rpm owner: through a link to a folder, the owner of the real file' "fixa: $RPMFX/lnk/r.txt"$'\nrc=0' "$OUT"
    ro "$RPMFX/sp ace.txt"
    check_eq 'rpm owner: a path with a space comes back whole' "fixa: $RPMFX/sp ace.txt"$'\nrc=0' "$OUT"
    ro "$RPMFX/a.*"
    check_eq 'rpm owner: a wildcard is not expanded' 'rc=0' "$OUT"
    ro ''
    check_eq 'rpm owner: an empty path has no owner' 'rc=0' "$OUT"
    rpm_sandbox
    app_eval "PM=dnf; cd '$RPMFX'; pm_owner -dash.txt a.txt; echo \"rc=\$?\""
    check_eq 'rpm owner: a relative path that starts with "-" is a path, not an option' $'fixa: -dash.txt\nfixa: a.txt\nrc=0' "$OUT"
    check_eq 'rpm owner: and "--" comes before it' "rpm [-qf] [--qf] [%{NAME}\\n] [--] [-dash.txt]"$'\n'"rpm [-qf] [--qf] [%{NAME}\\n] [--] [a.txt]" "$(rpm_log)"
    rpm_sandbox
    ro "$RPMFX/a.txt" "$RPMFX/unowned" "$RPMFX/nope" "$RPMFX/b.txt" "$RPMFX/shared" "$RPMFX/c.txt"
    check_eq 'rpm owner: several paths: each line goes with its path, in the order given' \
        "fixa: $RPMFX/a.txt"$'\n'"fixb: $RPMFX/b.txt"$'\n'"fixa, fixb: $RPMFX/shared"$'\n'"fixc: $RPMFX/c.txt"$'\nrc=0' "$OUT"
    check_eq 'rpm owner: one question per path' 6 "$(rpm_log | grep -c '^rpm \[-qf\]')"
    check_eq 'rpm owner: no privileges' '' "$(sudo_log)"
    rpm_sandbox
    _stub sort <<'EOF'
#!/bin/sh
echo "${LC_ALL-unset}" >> '@STATE@/sort.log'
PATH=/usr/local/bin:/usr/bin:/bin exec sort "$@"
EOF
    app_eval "PM=dnf; pm_owner '$RPMFX/shared'" LC_ALL=C.UTF-8
    check_eq 'rpm owner: the names are sorted in the C locale, whatever the language of the user' 'C' "$(cat "$SB/state/sort.log")"
    rpm_sandbox
    app_eval 'PM=dnf; pm_owner; echo "rc=$?"'
    check_eq 'rpm owner: without paths: status 2' 'rc=2' "$OUT"
    check_eq 'rpm owner: and rpm is not asked' '' "$(rpm_log)"
    app_eval "PM=dnf; pm_owner '$RPMFX/a.txt'; echo \"rc=\$?\"" PATH="$SB/emptybin"
    check_eq 'rpm owner: without rpm in the system: no line and no error text' 'rc=0' "$OUT"
    app_eval "PM=dnf; a='$RPMFX/a.txt'; s='$RPMFX/shared'; u='$RPMFX/unowned'; p='$RPMFX/sp ace.txt'
        load_launcher_owners \"\$a\" \"\$s\" \"\$u\" \"\$p\"
        printf '<<%s|%s|%s|%s>>' \"\${LAUNCHER_OWNERS[\$a]:-}\" \"\${LAUNCHER_OWNERS[\$s]:-}\" \"\${LAUNCHER_OWNERS[\$u]:-}\" \"\${LAUNCHER_OWNERS[\$p]:-}\""
    check_eq 'rpm owner: load_launcher_owners reads what rpm_owner prints' '<<fixa|fixa, fixb||fixa>>' "$OUT"
    printf '#!/bin/sh\nexit 0\n' > "$SB/bin/rpm"
    app_eval "PM=dnf; pm_owner '$RPMFX/a.txt'; echo \"rc=\$?\""
    check_eq 'rpm owner: an rpm that succeeds and says nothing gives no line (never ": path")' 'rc=0' "$OUT"
else
    skip_case 'the rpm backend: pm_installed and pm_owner (rpm or rpmbuild not available)'
    # The CI installs rpm (quality.yml): there, skipping would hide a missing package or a broken fixture.
    [ -z "${CI:-}" ] || check_eq 'CI: rpm and rpmbuild are installed and build the fixture' 'built' 'skipped'
fi

echo "-- pm_meta_packages: what the manager files as a meta-package (4.6)"
new_sandbox
fake_installed app-a mymeta tsk pkgb plain lookalike
fake_section app-a games
fake_section mymeta metapackages
fake_section tsk tasks
fake_section pkgb universe/metapackages
fake_section plain misc
fake_section lookalike mymetapackages
app_eval 'pm_meta_packages mymeta app-a tsk unknown pkgb plain lookalike; echo "rc=$?"'
check_eq 'the sections "metapackages" and "tasks", with or without a component; nothing else, no error shown' \
    $'mymeta\ntsk\npkgb\nrc=0' "$OUT"
check_eq 'one question to the manager for all the names' 'dpkg-query 7' "$(dpkgq_log)"
new_sandbox
app_eval 'pm_meta_packages; echo "rc=$?"'
check_eq 'without names: status 2' 'rc=2' "$OUT"
app_eval 'PM=nope; pm_meta_packages mymeta; echo "rc=$?"'
check_eq 'a manager without backend: status 2 and no output' 'rc=2' "$OUT"
check_eq 'and the manager is not asked' '' "$(dpkgq_log)"
code='pm_meta_packages() { echo "asked: $*" >&2; printf "%s\n" "$1"; }
plan_meta_packages "$(printf "Purg %s [1.0]\n" ubuntu-desktop foo bar)" foo; echo "rc=$?"'
app_eval "$code"
check_eq 'plan_meta_packages asks pm_meta_packages once, with what the patterns left, and adds its answer' \
    $'asked: bar\nbar\nubuntu-desktop\nrc=0' "$OUT"
app_eval 'pm_meta_packages() { echo "asked" >&2; }; plan_meta_packages "$(printf "Purg %s [1.0]\n" ubuntu-desktop)"'
check_eq 'what the patterns tell needs no question to the manager' 'ubuntu-desktop' "$OUT"

echo "-- pm_detail: name, version and size of the installed packages (4.6)"
new_sandbox
fake_installed foo bar
fake_pkginfo foo 1.2.3 500 'Foo app'
fake_pkginfo bar 2.0 1500 'Bar'
app_eval 'pm_detail foo unknown bar'
check_eq 'a line "name, version, size" for each installed package; none for an unknown one; no error shown' \
    $'foo\t1.2.3\t500\nbar\t2.0\t1500' "$OUT"
check_eq 'one question to the manager for all the names' 'dpkg-query 3' "$(dpkgq_log)"
new_sandbox
app_eval 'pm_detail; echo "rc=$?"'
check_eq 'without names: status 2 and no output' 'rc=2' "$OUT"
check_eq 'and the manager is not asked (it would list the whole system)' '' "$(dpkgq_log)"
app_eval 'PM=nope; pm_detail foo; echo "rc=$?"'
check_eq 'a manager without backend: status 2 and no output' 'rc=2' "$OUT"
code='pm_detail() { printf "foo\t1.2.3\t500\nbar\t2.0\t1500\n"; }
load_package_detail foo bar; echo "$DETAIL_MAIN|$DETAIL_VERSION|$DETAIL_EXTRA|$DETAIL_SIZE"'
app_eval "$code"
check_eq 'load_package_detail reads what pm_detail prints' 'foo|1.2.3|1|2000' "$OUT"
app_eval 'pm_detail() { printf "libc6\t2.39\t100\nlibc6\t2.39\t100\n"; }; load_package_detail libc6; echo "$DETAIL_MAIN|$DETAIL_VERSION|$DETAIL_EXTRA|$DETAIL_SIZE"'
check_eq 'load_package_detail: a package installed for two architectures is two lines: one more is counted, and both sizes' 'libc6|2.39|1|200' "$OUT"
app_eval 'pm_detail() { echo called; }; load_package_detail; echo "[$DETAIL_MAIN|$DETAIL_EXTRA|$DETAIL_SIZE]"'
check_eq 'without names, load_package_detail does not ask' '[|0|0]' "$OUT"
if command -v dpkg-query >/dev/null 2>&1 && [ -r /var/lib/dpkg/status ]; then
    new_sandbox
    app_eval 'pm_detail "--showformat=MARK\n" dpkg' PATH=/usr/bin:/bin
    assert_contains 'the real dpkg-query: the line has the shape the program reads' "$OUT" $'dpkg\t'
    assert_not_contains 'the real dpkg-query: a name that looks like an option is a name, not an option' "$OUT" 'MARK'
else
    skip_case 'the real dpkg-query (not available)'
fi

echo "-- pm_protected: what the manager does not let go (4.6)"
new_sandbox
fake_installed req imp ess std opt
fake_priority req required
fake_priority imp important
fake_priority std standard
fake_priority opt optional
fake_essential ess
app_eval 'for p in req imp ess std opt unknown; do pm_protected "$p"; echo "$p=$?"; done'
check_eq 'required, important and Essential are protected; standard, optional and unknown are not' \
    $'req=0\nimp=0\ness=0\nstd=1\nopt=1\nunknown=1' "$OUT"
check_eq 'one question for each package (priority and Essential together)' \
    $'dpkg-query 1\ndpkg-query 1\ndpkg-query 1\ndpkg-query 1\ndpkg-query 1\ndpkg-query 1' "$(dpkgq_log)"
printf '#!/bin/sh\nprintf "|yes\\n"\n' > "$SB/bin/dpkg-query"
app_eval 'pm_protected x; echo "rc=$?"'
check_eq 'an empty priority does not hide Essential (the first field is not lost)' 'rc=0' "$OUT"
printf '#!/bin/sh\nprintf "required|\\n"\n' > "$SB/bin/dpkg-query"
app_eval 'pm_protected x; echo "rc=$?"'
check_eq 'an empty Essential does not hide the priority' 'rc=0' "$OUT"
printf '#!/bin/sh\nexit 1\n' > "$SB/bin/dpkg-query"
app_eval 'pm_protected x; echo "rc=$?"'
check_eq 'a manager that says nothing protects nothing' 'rc=1' "$OUT"
new_sandbox
app_eval 'PM=nope; pm_protected ess; echo "rc=$?"'
check_eq 'a manager without backend: status 2' 'rc=2' "$OUT"
check_eq 'and the manager is not asked' '' "$(dpkgq_log)"
code='EXCLUDED_PATTERNS=("zz*"); pm_protected() { echo "asked $1"; return "$PROT"; }
PROT=1; is_excluded_package zzfoo; echo "pattern=$?"
is_excluded_package other; echo "free=$?"
PROT=0; is_excluded_package other; echo "protected=$?"
PROT=2; is_excluded_package other; echo "cannot say=$?"'
app_eval "$code"
check_eq 'is_excluded_package: a pattern decides alone; otherwise it is what pm_protected says; "cannot say" (2) protects' \
    $'pattern=0\nasked other\nfree=1\nasked other\nprotected=0\nasked other\ncannot say=0' "$OUT"
app_eval 'PM=nope; EXCLUDED_PATTERNS=(); is_excluded_package some-package; echo "rc=$?"'
check_eq 'is_excluded_package: a manager without backend offers nothing' 'rc=0' "$OUT"
if command -v dpkg-query >/dev/null 2>&1 && [ -r /var/lib/dpkg/status ]; then
    app_eval 'pm_protected bash; echo "bash=$?"; pm_protected mintapp-no-such-package-xyz; echo "none=$?"' PATH=/usr/bin:/bin
    check_eq 'the real dpkg-query: bash is protected, an unknown package is not' $'bash=0\nnone=1' "$OUT"
else
    skip_case 'the real dpkg-query (not available)'
fi

echo "-- the rpm backend: pm_detail and pm_meta_packages (4.6, step 4d)"
# Same fixture as step 4c (see there); the cases are skipped where rpm or rpmbuild is not installed.
if [ "$RPMFX_OK" -eq 1 ]; then
    # rd NAME...: pm_detail with dnf on those names; OUT ends with "rc=" and its status.
    rd() { local args; printf -v args '%q ' "$@"; app_eval "PM=dnf; pm_detail $args; echo \"rc=\$?\""; }
    rpm_sandbox
    rd fixa fixd fixz fixc
    check_eq 'rpm detail: a line "name, version, size" per package: epoch in the version, none for an unknown one' \
        $'fixa\t1.0-1\t0\nfixd\t3:2.5-7\t3\nfixc\t1.0-1\t0\nfixc\t1.0-1\t0\nrc=1' "$OUT"
    check_eq 'rpm detail: one question for all the names, with "--" before them' \
        'rpm [-q] [--qf] [%{NAME}\t%{EVR}\t%{LONGSIZE}\n] [--] [fixa] [fixd] [fixz] [fixc]' "$(rpm_log)"
    check_eq 'rpm detail: no privileges' '' "$(sudo_log)"
    rd fixe fixf fixm
    check_eq 'rpm detail: bytes become KiB rounded up (1024 -> 1, 1025 -> 2, none -> 0)' \
        $'fixe\t1.0-1\t1\nfixf\t1.0-1\t2\nfixm\t1.0-1\t0\nrc=0' "$OUT"
    rd fixz
    check_eq 'rpm detail: only an unknown package: no line, and the "not installed" text of rpm is not shown' 'rc=1' "$OUT"
    rd fixa-1.0 fixa.noarch fixc.i686
    check_eq 'rpm detail: "name-version" and "name.arch" are not names: no line' 'rc=0' "$OUT"
    rd -a
    check_eq 'rpm detail: "-a" is a name, not an option (rpm -q -a would list everything)' 'rc=1' "$OUT"
    rpm_sandbox
    app_eval 'PM=dnf; pm_detail; echo "rc=$?"'
    check_eq 'rpm detail: without names: status 2' 'rc=2' "$OUT"
    check_eq 'rpm detail: and rpm is not asked' '' "$(rpm_log)"
    app_eval 'PM=dnf; pm_detail fixa; echo "rc=$?"' PATH="$SB/emptybin"
    check_eq 'rpm detail: without rpm in the system: no line, no error text, rpm'"'"'s status' 'rc=127' "$OUT"
    app_eval 'PM=dnf; load_package_detail fixd fixe; echo "$DETAIL_MAIN|$DETAIL_VERSION|$DETAIL_EXTRA|$DETAIL_SIZE"'
    check_eq 'rpm detail: load_package_detail reads what rpm_detail prints' 'fixd|3:2.5-7|1|4' "$OUT"
    app_eval 'PM=dnf; load_package_detail fixc; echo "$DETAIL_MAIN|$DETAIL_VERSION|$DETAIL_EXTRA|$DETAIL_SIZE"'
    check_eq 'rpm detail: a package of two architectures is two lines, as with dpkg-query: load_package_detail counts one more' 'fixc|1.0-1|1|0' "$OUT"
    # An rpm that answers with lines that are not the shape (name TAB version TAB bytes) or are of another NAME.
    _stub rpm <<'EOF'
#!/bin/sh
printf '%s\n' "$RPM_SAYS"
EOF
    says=$'el paquete fixa no esta instalado\nother\t1.0-1\t10\nfixa\t1.0-1\nfixa\t1.0-1\t10\textra\nfixa\t1.0-1\tabc\nfixa\t\t10\nfixa\t1.0-1\t1234567890123456\nfixa\t1.0-1\t10'
    app_eval 'PM=dnf; pm_detail fixa; echo "rc=$?"' RPM_SAYS="$says"
    check_eq 'rpm detail: only the line of the right shape and NAME is kept (any language, no extra fields)' $'fixa\t1.0-1\t1\nrc=0' "$OUT"
    app_eval 'PM=dnf; pm_detail fixa; echo "rc=$?"' RPM_SAYS=$'junk\tfixa\t1.0-1\t10'
    check_eq 'rpm detail: a field before the name is not the shape either: no line' 'rc=0' "$OUT"
    app_eval 'PM=dnf; pm_detail fixa; echo "rc=$?"' RPM_SAYS=$'fixa\t1.0-1\t09\nfixa\t1.0-1\t000000000001025'
    check_eq 'rpm detail: a size with leading zeros is decimal, not octal (09 -> 1 KiB, 1025 -> 2)' $'fixa\t1.0-1\t1\nfixa\t1.0-1\t2\nrc=0' "$OUT"

    # rm_ NAME...: pm_meta_packages with dnf on those names; OUT ends with "rc=" and its status.
    rm_() { local args; printf -v args '%q ' "$@"; app_eval "PM=dnf; pm_meta_packages $args; echo \"rc=\$?\""; }
    rpm_sandbox
    rm_ fixa fixm fixz fixd fixn
    check_eq 'rpm meta: a package with no files is one; one with files, with only a folder, or unknown is not' $'fixm\nrc=0' "$OUT"
    check_eq 'rpm meta: one question for all the names, with "--" before them' \
        'rpm [-q] [--qf] [%{NAME}\t%{FILENAMES:arraysize}\n] [--] [fixa] [fixm] [fixz] [fixd] [fixn]' "$(rpm_log)"
    check_eq 'rpm meta: no privileges' '' "$(sudo_log)"
    rm_ fixz
    check_eq 'rpm meta: an unknown package: nothing, no error shown, status 0' 'rc=0' "$OUT"
    rm_ fixm-1.0 fixm.noarch
    check_eq 'rpm meta: "name-version" and "name.arch" are not names: nothing' 'rc=0' "$OUT"
    rm_ -a
    check_eq 'rpm meta: "-a" is a name, not an option (rpm -q -a would list everything)' 'rc=0' "$OUT"
    rpm_sandbox
    app_eval 'PM=dnf; pm_meta_packages; echo "rc=$?"'
    check_eq 'rpm meta: without names: status 2' 'rc=2' "$OUT"
    check_eq 'rpm meta: and rpm is not asked' '' "$(rpm_log)"
    app_eval 'PM=dnf; pm_meta_packages fixm; echo "rc=$?"' PATH="$SB/emptybin"
    check_eq 'rpm meta: without rpm in the system: nothing, no error text, status 0' 'rc=0' "$OUT"
    printf -v plan '%q' $'Remv fixm [1.0-1] (noarch)\nRemv fixd [3:2.5-7] (noarch)\nRemv fixe [1.0-1] (noarch)\nRemv fixn [1.0-1] (noarch)'
    app_eval "PM=dnf; plan_meta_packages $plan fixe; echo \"rc=\$?\""
    check_eq 'rpm meta: plan_meta_packages names the empty package of a plan, and not the one that was asked for' $'fixm\nrc=0' "$OUT"
    # An rpm that answers with lines that are not the shape (name TAB count) or are of another NAME.
    _stub rpm <<'EOF'
#!/bin/sh
printf '%s\n' "$RPM_SAYS"
EOF
    says=$'el paquete fixm no esta instalado\nother\t(none)\nfixm\nfixm\t(none)\textra\nfixm\tabc\nfixm\t(none)\nfixm\t0\nfixm\t3'
    app_eval 'PM=dnf; pm_meta_packages fixm; echo "rc=$?"' RPM_SAYS="$says"
    check_eq 'rpm meta: only the lines of the right shape and NAME; "(none)" and "0" are no files; each name once' $'fixm\nrc=0' "$OUT"
    app_eval 'PM=dnf; pm_meta_packages fixm; echo "rc=$?"' RPM_SAYS=$'fixm\t5\nfixm\t(none)'
    check_eq 'rpm meta: a name with files in one line and none in another: listed' $'fixm\nrc=0' "$OUT"
    app_eval 'PM=dnf; pm_meta_packages fixm; echo "rc=$?"' RPM_SAYS=$'fixm\t0'
    check_eq 'rpm meta: a count of 0 alone is no files' $'fixm\nrc=0' "$OUT"
    app_eval 'PM=dnf; pm_meta_packages fixm; echo "rc=$?"' RPM_SAYS=$'junk\tfixm\t(none)'
    check_eq 'rpm meta: a field before the name is not the shape either: nothing' 'rc=0' "$OUT"
else
    skip_case 'the rpm backend: pm_detail and pm_meta_packages (rpm or rpmbuild not available)'
fi

echo "-- the dnf backend: pm_protected (4.6, step 4d)"
# dnf protects the names written in files (dnf.conf and the protected.d folders) and the program reads them: it
# asks neither dnf nor rpm. The cases write those files in the sandbox ($SB/dnf.conf, $SB/p1 and $SB/p2) and
# point the program to them (DNF_CONF and DNF_PROTECTED_DIRS).
# dnf_files: the code that selects dnf and points the program to the files of the sandbox.
dnf_files() { printf "PM=dnf; DNF_CONF='%s/dnf.conf'; DNF_PROTECTED_DIRS=('%s/p1' '%s/p2')" "$SB" "$SB" "$SB"; }
# pfile PATH LINE...: the file $SB/PATH, with those lines.
pfile() {
    local file="$SB/$1"
    shift
    mkdir -p -- "$(dirname -- "$file")"
    printf '%s\n' "$@" > "$file"
    sandbox_chown
}
# dnf_check STATUS WHY NAME...: pm_protected with dnf gives STATUS (0 protected, 1 not) for each NAME. One run of
# the program for all of them, one check for each.
dnf_check() {
    local want="$1" why="$2" name i=0 word
    local -a got
    shift 2
    app_eval "$(dnf_files); for n in $(printf '%q ' "$@"); do pm_protected \"\$n\"; echo \"\$?\"; done"
    mapfile -t got <<< "$OUT"
    if [ "$want" = 0 ]; then word='is protected'; else word='is not protected'; fi
    for name in "$@"; do
        check_eq "dnf: $(printf '%q' "$name") $word ($why)" "$want" "${got[i]:-}"
        i=$((i + 1))
    done
}
new_sandbox
dnf_check 0 'dnf itself, with no file at all' dnf
dnf_check 1 'no file says so' yum foo
dnf_check 1 'an empty name' ''
app_eval 'echo "$DNF_CONF"; printf "%s\n" "${DNF_PROTECTED_DIRS[@]}"'
check_eq 'dnf: where it keeps its list: dnf.conf and the two protected.d folders' $'/etc/dnf/dnf.conf\n/etc/dnf/protected.d\n/etc/yum/protected.d' "$OUT"

# protected.d: the "*.conf" files of both folders.
new_sandbox
pfile p1/names.conf 'one two' 'three,four' 'five, six' $'seven\teight' '   nine' '' '   ' 'ten,' 'gcc-c++' 'wild*'
pfile p2/more.conf eleven
dnf_check 0 'in a file of the first folder: one or more per line, separated by a space, a comma, a comma and a space or a tab' \
    one two three four five six seven eight nine ten
dnf_check 0 'in a file of the second folder' eleven
dnf_check 0 'a name of a package with "+" in it' 'gcc-c++'
dnf_check 0 'a name with "*" is that name' 'wild*'
dnf_check 1 'a name is not a pattern, and a pattern is not a name' wild wildcard 'w*' 'wild?'
dnf_check 1 'in none' twelve foo
new_sandbox
pfile p1/notes.txt a_txt
pfile p1/.hidden.conf a_hidden
pfile p1/names a_noext
pfile p1/conf a_conf_name
pfile p1/names.conf.bak a_bak
pfile p1/sub/deep.conf a_deep
pfile p2/odd.CONF a_upper
pfile p1/dir.conf/inside.conf a_inside
dnf_check 1 'its file does not count: only "*.conf" files of the folders themselves' \
    a_txt a_hidden a_noext a_conf_name a_bak a_deep a_upper a_inside
new_sandbox
pfile p1/c.conf '# commented' '   # indented comment' 'real # note' '#' 'last'
dnf_check 0 'a name before a "#"' real
dnf_check 0 'what follows a "#" after a name is read as names, as dnf does' note
dnf_check 0 'a line after the comments' last
dnf_check 1 'in a comment line' commented indented comment
new_sandbox
mkdir -p "$SB/p1"
printf 'crlf1\r\ncrlf2, crlf3\r\n# crlfcomment\r\nnonl' > "$SB/p1/crlf.conf"
sandbox_chown
dnf_check 0 'CRLF line ends do not stick to the name; the last line may have no line end' crlf1 crlf2 crlf3 nonl
dnf_check 1 'a comment with a CRLF line end' crlfcomment
new_sandbox
pfile p1/open.conf openname
pfile p1/secret.conf secretname
chmod 000 "$SB/p1/secret.conf"
dnf_check 0 'the file next to one that cannot be read' openname
dnf_check 1 'in a file that cannot be read: ignored, with no error text' secretname
new_sandbox
pfile dnf.conf '[main]' 'protected_packages=hidden'
chmod 000 "$SB/dnf.conf"
dnf_check 1 'in a dnf.conf that cannot be read: ignored, with no error text' hidden
dnf_check 0 'and dnf stays protected when dnf.conf cannot be read' dnf

# protected_packages in dnf.conf.
new_sandbox
pfile p1/y.conf yum
pfile dnf.conf '[main]' 'gpgcheck=1' 'protected_packages=foo,bar baz, qux' 'best=True'
dnf_check 0 'in protected_packages, separated by a comma, a space or a comma and a space' foo bar baz qux
dnf_check 0 'dnf and the protected.d files stay when dnf.conf sets the list (dnf would drop them: this protects more)' dnf yum
dnf_check 1 'another setting of dnf.conf is not read' gpgcheck best True 1
new_sandbox
pfile dnf.conf '[other]' 'protected_packages=wrong' '[main]' 'protected_packages = spaced' 'protected_packages_extra=extra' \
    '#protected_packages=commented' '[repo]' 'protected_packages=wrong2'
dnf_check 0 'protected_packages with blanks around "=", in [main] after another section' spaced
dnf_check 1 'in another section, a longer key, a commented key' wrong wrong2 extra commented
new_sandbox
pfile dnf.conf '[main]' 'protected_packages=first,' '    second' $'\tthird' 'unrelated=x' '   ' '    notcont'
dnf_check 0 'the value goes on in the lines that start with a blank' first second third
dnf_check 1 'and stops at the first line that does not' x unrelated notcont
new_sandbox
pfile dnf.conf '[main]' 'protected_packages=one' '   ' '    two' $'\t' $'\tthree' 'other=x' '    notcont'
dnf_check 0 'a line of only blanks does not end the value: dnf goes on with the next one that starts with a blank (measured, dnf 4.14.0)' one two three
dnf_check 1 'and it still stops at the line that does not start with a blank' other x notcont
new_sandbox
printf '[main]\r\nprotected_packages=crlfcfg\r\nprotected_packages=nonlconf' > "$SB/dnf.conf"
pfile p1/y.conf yum
sandbox_chown
dnf_check 0 'dnf.conf with CRLF line ends, the key twice (both count) and no line end at the end' crlfcfg nonlconf
pfile dnf.conf '[main]' 'protected_packages='
dnf_check 0 'an empty protected_packages (dnf would protect nothing) leaves dnf and the protected.d files' dnf yum
new_sandbox
pfile g/a.lst fromglob1 'fromglob2, fromglob3'
pfile g/b.txt fromglob4
pfile g/other.dat notglob
pfile dnf.conf '[main]' "protected_packages=before, glob:$SB/g/*.lst, glob:$SB/g/b.txt glob:$SB/nothing/*.conf glob: after"
dnf_check 0 'glob:PATTERN stands for the names in the files it matches, whatever their extension' fromglob1 fromglob2 fromglob3 fromglob4
dnf_check 0 'the names around the glob: entries' before after
dnf_check 1 'a file the pattern does not match; a pattern that matches nothing (or none) is no error' notglob nothing
new_sandbox
pfile g/rel.lst relname
pfile dnf.conf '[main]' 'protected_packages=glob:g/*.lst'
app_eval "cd '$SB'; $(dnf_files); pm_protected relname; echo \"\$?\"; cd /; pm_protected relname; echo \"\$?\""
check_eq 'a relative glob: is read from the folder the program runs in, as dnf does (measured, dnf 4.14.0)' $'0\n1' "$OUT"
new_sandbox
pfile p1/a.conf fromfile
pfile dnf.conf '[main]' 'protected_packages=fromconf'
app_eval "$(dnf_files); for n in dnf fromfile fromconf other; do pm_protected \"\$n\"; echo \"\$?\"; done" PATH="$SB/emptybin"
check_eq 'dnf: no command is run to know it (not dnf, not rpm, nothing): the files are read' $'0\n0\n0\n1' "$OUT"
app_eval "$(dnf_files); EXCLUDED_PATTERNS=(); for p in dnf fromfile firefox; do is_excluded_package \"\$p\"; echo \"\$p=\$?\"; done"
check_eq 'dnf: is_excluded_package leaves out what dnf protects and lets the rest through' $'dnf=0\nfromfile=0\nfirefox=1' "$OUT"

echo "-- the dnf backend against the real dnf and rpm, on a fake root (4.6, step 4f)"
# The backend as a whole (pm_installed, pm_owner, pm_detail, pm_meta_packages, pm_protected, pm_simulate,
# pm_run and what calls them) with the real dnf 4 and rpm on a fake root (dnf --installroot): a folder with a
# few synthetic packages and their database, so nothing of the system is read or written. dnf refuses to
# work without administrator rights, even to simulate: the cases run as root where the tests run as root
# and through "sudo -n" otherwise. They are skipped where dnf, rpm, rpmbuild, createrepo_c or those rights
# are missing; with CI defined that is a failure. Packages (noarch, 1.0-1), installed in the root as
# "dnf install fixapp fixdep fixmeta fixsolo" does, so fixlib is a dependency:
#   fixlib   lib.txt                                fixapp  fixapp.desktop and app.bin (2049 bytes); requires fixlib
#   fixdep   dep.txt; requires fixapp               fixmeta no files (a meta-package); requires fixlib
#   fixsolo  solo.txt (nobody needs it)             dnf     9.9-1, not installed: the cases about protection add it
# Not covered: the running kernel, which dnf also protects. dnf does not look for it when the root is not "/",
# so no fake root can show it (PLAN, 4.6 step 4d).
DNFFX="$H_TMP/dnffx"
DNF_BIN="$(command -v dnf 2> /dev/null || true)"
RPM_BIN="$(command -v rpm 2> /dev/null || true)"
SUDO_BIN="$(command -v sudo 2> /dev/null || true)"
# The rpm of Debian and Ubuntu keeps its database in ~/.rpmdb (inside the root), so dnf and rpm only see the
# same packages with the same HOME: every dnf and rpm of this section gets this one.
DNF_HOME="/dnffx-home"
# dnf_as_root COMMAND...: as root; through the real sudo (not the stub of the sandbox) if the tests are not root.
dnf_as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else "$SUDO_BIN" -n "$@"; fi; }
# dnf_chown PATH: gives back to the user what root wrote (so the harness can delete it).
dnf_chown() { if [ "$(id -u)" -eq 0 ]; then :; else dnf_as_root chown -R "$(id -u):$(id -g)" "$1"; fi; }
# build_dnf_fixture: the repository and the fake root, once. Fails if anything needed is missing.
build_dnf_fixture() {
    local top="$DNFFX/top" fake="$DNFFX/fake"
    [ -n "$DNF_BIN" ] && [ -n "$RPM_BIN" ] || return 1
    command -v rpmbuild > /dev/null 2>&1 && command -v createrepo_c > /dev/null 2>&1 || return 1
    [ "$(id -u)" -eq 0 ] || { [ -n "$SUDO_BIN" ] && "$SUDO_BIN" -n true > /dev/null 2>&1; } || return 1
    mkdir -p "$top" "$DNFFX/repo" "$fake/root" "$fake/cache" "$fake/log" "$fake/persist" "$fake/noreposdir" || return 1
    MK_TOP="$top" mkrpm noarch fixlib /usr/share/fixlib/lib.txt
    MK_TOP="$top" MK_REQ=fixlib mkrpm noarch fixapp /usr/share/applications/fixapp.desktop z:2049:/usr/share/fixapp/app.bin
    MK_TOP="$top" MK_REQ=fixapp mkrpm noarch fixdep /usr/share/fixdep/dep.txt
    MK_TOP="$top" MK_REQ=fixlib mkrpm noarch fixmeta
    MK_TOP="$top" mkrpm noarch fixsolo /usr/share/fixsolo/solo.txt
    MK_TOP="$top" MK_VER=9.9 mkrpm noarch dnf /usr/share/fakednf/x
    cp "$top"/RPMS/noarch/fix*.rpm "$DNFFX/repo/" || return 1
    createrepo_c -q "$DNFFX/repo" > /dev/null 2>&1 || return 1
    dnf_as_root env LC_ALL=C HOME="$DNF_HOME" "$DNF_BIN" install -y --installroot="$fake/root" --releasever=40 \
        --setopt=cachedir="$fake/cache" --setopt=logdir="$fake/log" --setopt=persistdir="$fake/persist" \
        --setopt=reposdir="$fake/noreposdir" --repofrompath="fx,file://$DNFFX/repo" --nogpgcheck \
        fixapp fixdep fixmeta fixsolo > "$DNFFX/install.log" 2>&1 || { dnf_chown "$DNFFX"; return 1; }
    dnf_chown "$DNFFX"
    [ "$(HOME="$DNF_HOME" rpm --root "$fake/root" -qa 2> /dev/null | wc -l)" -eq 5 ]
}
# dnf_sandbox: a new sandbox with its own copy of the fake root, and a dnf and an rpm that are the real ones
# working on it. FAKE_DNF_CONF, if set when dnf runs, is the dnf.conf it reads (--config).
dnf_sandbox() {
    local as=""
    new_sandbox
    cp -a "$DNFFX/fake" "$SB/state/fake"
    if [ "$(id -u)" -ne 0 ]; then as="$SUDO_BIN -n env LC_ALL=\"\${LC_ALL:-C}\""; fi
    printf '#!/bin/sh\nS="%s/state/fake"\ncase "${1-}" in -*|"") exec %s "%s" "$@" ;; esac\nverb="$1"; shift\nexec %s env HOME="%s" "%s" "$verb" --installroot="$S/root" --releasever=40 --setopt=cachedir="$S/cache" --setopt=logdir="$S/log" --setopt=persistdir="$S/persist" --setopt=reposdir="$S/noreposdir" ${FAKE_DNF_CONF:+--config="$FAKE_DNF_CONF"} "$@"\n' \
        "$SB" "$as" "$DNF_BIN" "$as" "$DNF_HOME" "$DNF_BIN" > "$SB/bin/dnf"
    printf '#!/bin/sh\nexec %s env HOME="%s" "%s" --root "%s/state/fake/root" "$@"\n' "$as" "$DNF_HOME" "$RPM_BIN" "$SB" > "$SB/bin/rpm"
    chmod 755 "$SB/bin/dnf" "$SB/bin/rpm"
}
# dnf_eval CODE [VAR=val...]: CODE of the program with PM=dnf, in the current sandbox, with DNF_INPUT (if set) on
# stdin. As root where the tests are (H_AS_ROOT=1): the program only has its functions loaded here (main does not
# run), and dnf needs the rights.
dnf_eval() {
    local as_root=0
    if [ "$(id -u)" -eq 0 ]; then as_root=1; fi
    H_AS_ROOT=$as_root app_eval_in "${DNF_INPUT-}" "PM=dnf; $1" "${@:2}"
    dnf_chown "$SB"
}
# dnf_present NAME...: "NAME=0" if the package is installed in the fake root of the sandbox, "NAME=1" if not.
dnf_present() { local n code=''; for n in "$@"; do code+="pm_installed $n; echo \"$n=\$?\"; "; done; dnf_eval "$code"; }

if build_dnf_fixture; then
    dnf_sandbox
    dnf_eval 'rpm -qa | sort'
    check_eq 'control: the rpm of the sandbox sees the fake root (five packages, not the ones of the machine)' \
        $'fixapp-1.0-1.noarch\nfixdep-1.0-1.noarch\nfixlib-1.0-1.noarch\nfixmeta-1.0-1.noarch\nfixsolo-1.0-1.noarch' "$OUT"
    dnf_eval 'rpm -q --qf "%{NAME}\n" fixlib; dnf --version | head -n1'
    assert_contains 'control: a dependency is installed, and the dnf of the sandbox is a dnf 4' "$OUT" $'fixlib\n4.'
    dnf_present fixapp fixlib fixsolo nosuch
    check_eq 'pm_installed: the packages of the root, with their dependency, and one that is not there' \
        $'fixapp=0\nfixlib=0\nfixsolo=0\nnosuch=1' "$OUT"
    dnf_eval 'pm_owner /usr/share/applications/fixapp.desktop /usr/share/fixlib/lib.txt /usr/share/nobody.txt; echo "rc=$?"'
    check_eq 'pm_owner: the owner of each path, none for the path nobody owns' \
        $'fixapp: /usr/share/applications/fixapp.desktop\nfixlib: /usr/share/fixlib/lib.txt\nrc=0' "$OUT"
    dnf_eval 'pm_detail fixapp fixlib nosuch'
    check_eq 'pm_detail: version and KiB (2049 bytes are 3), and no line for a package that is not there' \
        $'fixapp\t1.0-1\t3\nfixlib\t1.0-1\t0' "$OUT"
    dnf_eval 'pm_meta_packages fixapp fixmeta fixlib fixsolo nosuch; echo "rc=$?"'
    check_eq 'pm_meta_packages: only the package with no files' $'fixmeta\nrc=0' "$OUT"
    dnf_eval 'pm_protected fixapp; echo "fixapp=$?"; pm_protected dnf; echo "dnf=$?"'
    check_eq 'pm_protected: dnf is protected, a package of the root is not' $'fixapp=1\ndnf=0' "$OUT"

    # The plan: what the real dnf prints for a simulated removal, read by dnf_read_plan. Nothing is removed.
    sim() { dnf_eval "pm_simulate $1; echo \"rc=\$?\"; echo \"\$PLAN_OUTPUT\""; }
    sim 'purge fixsolo'
    check_eq 'pm_simulate purge: one package nobody needs' $'rc=0\nRemv fixsolo [1.0-1] (noarch)' "$OUT"
    sim 'purge fixapp'
    check_eq 'pm_simulate purge: the package and what depends on it' \
        $'rc=0\nRemv fixapp [1.0-1] (noarch)\nRemv fixdep [1.0-1] (noarch)' "$OUT"
    sim 'purge fixlib'
    check_eq 'pm_simulate purge: a library that three packages need takes all of them (the order is dnf'"'"'s: sorted here)' \
        $'Remv fixapp [1.0-1] (noarch)\nRemv fixdep [1.0-1] (noarch)\nRemv fixlib [1.0-1] (noarch)\nRemv fixmeta [1.0-1] (noarch)\nrc=0' \
        "$(LC_ALL=C sort <<< "$OUT")"
    sim 'purge fixmeta'
    check_eq 'pm_simulate purge: a dependency that fixapp still needs stays' $'rc=0\nRemv fixmeta [1.0-1] (noarch)' "$OUT"
    sim 'purge fixapp fixmeta'
    check_eq 'pm_simulate purge: the dependency nobody needs after that goes too (its own section in the table of dnf)' \
        $'Remv fixapp [1.0-1] (noarch)\nRemv fixdep [1.0-1] (noarch)\nRemv fixlib [1.0-1] (noarch)\nRemv fixmeta [1.0-1] (noarch)\nrc=0' \
        "$(LC_ALL=C sort <<< "$OUT")"
    sim 'purge fixsolo nosuch'
    check_eq 'pm_simulate purge: with a name that matches nothing, the plan is of what matched' \
        $'rc=0\nRemv fixsolo [1.0-1] (noarch)' "$OUT"
    sim 'purge nosuch'
    assert_contains 'pm_simulate purge: a name that matches nothing is an error (status 1)' "$OUT" 'rc=1'
    assert_contains 'and the error says which name' "$OUT" 'No match for argument: nosuch'
    assert_not_contains 'and there is no plan' "$OUT" 'Remv '
    sim 'autoremove'
    check_eq 'pm_simulate autoremove: nothing to remove is status 0 and an empty plan' 'rc=0' "$OUT"
    dnf_eval 'pm_simulate purge fixapp; plan="$PLAN_OUTPUT"; plan_still_valid "$plan" purge fixapp; echo "same=$?"
rpm -e --nodeps fixdep 2> /dev/null; plan_still_valid "$plan" purge fixapp; echo "after=$?"'
    check_eq 'plan_still_valid with the real dnf: the same plan holds; if the root changed, it does not' $'same=0\nafter=1' "$OUT"
    dnf_present fixapp fixdep fixlib fixmeta fixsolo
    check_eq 'the simulations changed nothing in the root (only the rpm -e of the case above did)' \
        $'fixapp=0\nfixdep=1\nfixlib=0\nfixmeta=0\nfixsolo=0' "$OUT"

    # Rights and answers: the simulation runs with the privileges dnf 4 demands, and a "yes" waiting on stdin cannot
    # turn it into a removal (the dnf of the sandbox raises its own rights, so only the log of sudo shows the program asked).
    dnf_sandbox
    DNF_INPUT=$'y\ny\ny\n' dnf_eval 'pm_simulate purge fixsolo; echo "rc=$?"; pm_simulate autoremove; echo "rc=$?"'
    check_eq 'pm_simulate with "yes" waiting on stdin: still only a plan (--assumeno answers first)' $'rc=0\nrc=0' "$OUT"
    dnf_present fixsolo fixapp
    check_eq 'and nothing was removed' $'fixsolo=0\nfixapp=0' "$OUT"
    check_eq 'pm_simulate asks for privileges and the C locale, and passes --assumeno and --color=never' \
        $'sudo LC_ALL=C dnf remove --assumeno --color=never fixsolo\nsudo LC_ALL=C dnf autoremove --assumeno --color=never' "$(sudo_log)"

    # A package dnf protects: the program also hides it (pm_protected) and dnf refuses it, in the plan and in the removal.
    dnf_sandbox
    dnf_as_root env HOME="$DNF_HOME" "$RPM_BIN" --root "$SB/state/fake/root" -i --nodeps --noscripts "$DNFFX/top/RPMS/noarch/dnf-9.9-1.noarch.rpm" 2> /dev/null
    sim 'purge dnf'
    assert_contains 'a protected package: the plan is an error (status 1)' "$OUT" 'rc=1'
    assert_contains 'and dnf says why' "$OUT" 'removing the following protected packages: dnf'
    assert_not_contains 'and there is no plan' "$OUT" 'Remv '
    sim 'purge fixsolo dnf'
    assert_contains 'a protected package in the request: there is no plan for the others either' "$OUT" 'rc=1'
    assert_not_contains 'and nothing to remove is offered' "$OUT" 'Remv '
    dnf_eval 'pm_protected dnf; echo "program=$?"; pm_run purge fixsolo dnf > /dev/null 2>&1; echo "removal=$?"'
    check_eq 'the program protects it too, and the real removal fails' $'program=0\nremoval=1' "$OUT"
    dnf_present dnf fixsolo
    check_eq 'and nothing was removed' $'dnf=0\nfixsolo=0' "$OUT"
    # protected_packages in dnf.conf: dnf then protects that list alone; the program reads the same file.
    printf '[main]\nprotected_packages=fixsolo\n' > "$SB/dnf.conf"
    dnf_eval 'DNF_CONF="$SB/dnf.conf"; DNF_PROTECTED_DIRS=(); pm_protected fixsolo; echo "fixsolo=$?"; pm_protected fixapp; echo "fixapp=$?"
pm_simulate purge fixsolo; echo "rc=$?"; echo "$PLAN_OUTPUT"
pm_simulate purge fixapp; echo "rc=$?"; echo "$PLAN_OUTPUT"' FAKE_DNF_CONF="$SB/dnf.conf" SB="$SB"
    assert_contains 'protected_packages: the program protects fixsolo and not fixapp, as dnf.conf says' "$OUT" $'fixsolo=0\nfixapp=1\n'
    assert_contains 'protected_packages: dnf refuses what the file protects' "$OUT" 'removing the following protected packages: fixsolo'
    assert_contains 'protected_packages: and gives the plan of what it does not' "$OUT" $'rc=0\nRemv fixapp [1.0-1] (noarch)\nRemv fixdep [1.0-1] (noarch)'

    # The removals, as the program makes them: with the plan confirmed, through execute_removal.
    dnf_sandbox
    dnf_eval 'pm_simulate purge fixapp; execute_removal "$PLAN_OUTPUT" purge fixapp > /dev/null 2>&1; echo "st=$?"'
    check_eq 'a real removal: the status of dnf' 'st=0' "$OUT"
    check_eq 'a real removal goes through the privilege command: sudo dnf remove -y with the package' 'sudo dnf remove -y fixapp' "$(sudo_log | tail -n1)"
    dnf_present fixapp fixdep fixlib fixmeta fixsolo
    check_eq 'a real removal: the package and its dependent are gone, nothing else' \
        $'fixapp=1\nfixdep=1\nfixlib=0\nfixmeta=0\nfixsolo=0' "$OUT"
    rec="$(cat "$(state_files | head -n1)")"
    assert_contains 'a real removal: the record says it completed' "$rec" '# Status: completed'
    assert_contains 'a real removal: the record names the operation as dnf runs it' "$rec" '# Operation: dnf remove fixapp'
    assert_contains 'a real removal: and the plan, with the dependent' "$rec" 'Remv fixdep [1.0-1] (noarch)'
    assert_contains 'a real removal: and how to reinstall it' "$rec" 'dnf install fixapp fixdep'
    # autoremove needs a dependency that nobody uses: rpm -e on every package that needs it leaves one behind
    # (dnf remove would take it along, see above).
    dnf_sandbox
    dnf_eval 'rpm -e --nodeps fixdep fixapp fixmeta 2> /dev/null; pm_simulate autoremove; echo "rc=$?"; echo "$PLAN_OUTPUT"'
    check_eq 'pm_simulate autoremove: the dependency nobody needs now' $'rc=0\nRemv fixlib [1.0-1] (noarch)' "$OUT"
    dnf_eval 'pm_simulate autoremove; execute_removal "$PLAN_OUTPUT" autoremove > /dev/null 2>&1; echo "st=$?"'
    check_eq 'a real autoremove: the status of dnf' 'st=0' "$OUT"
    dnf_present fixlib fixsolo
    check_eq 'a real autoremove: it removed the dependency and not the package that was asked for' $'fixlib=1\nfixsolo=0' "$OUT"
    dnf_eval 'pm_run clean > /dev/null 2>&1; echo "st=$?"'
    check_eq 'pm_run clean with the real dnf: "dnf clean packages" works (status 0)' 'st=0' "$OUT"
else
    skip_case 'the dnf backend against the real dnf (dnf, rpm, rpmbuild, createrepo_c or administrator rights not available)'
    [ -z "${CI:-}" ] || check_eq 'CI: dnf, rpm, rpmbuild and createrepo_c are installed, and the fake root is built' 'built' 'skipped'
fi

echo "-- the pacman backend: pm_run, pm_tool and the texts of the records (4.6, step 5a)"
# These cases call the functions of the pacman backend, not pm_detect, so they set PM themselves.
# pr CODE [VAR=val...]: CODE with PM=pacman and a privilege command that only says what it was given
# (PR_RC is its status); OUT ends with "st=" and the status of CODE.
pr() { app_eval "PM=pacman; priv_run() { echo \"PR \$*\"; return \${PR_RC:-0}; }; $1; echo \"st=\$?\"" "${@:2}"; }
# pacman_stub: a pacman in the sandbox that logs its arguments to the state folder, prints FAKE_PACMAN_OUT
# and ends with FAKE_PACMAN_RC.
pacman_stub() {
    printf '#!/bin/sh\necho "pacman $*" >> "%s/state/pacman.log"\n[ -z "${FAKE_PACMAN_OUT:-}" ] || printf "%%s\\n" "$FAKE_PACMAN_OUT"\nexit "${FAKE_PACMAN_RC:-0}"\n' "$SB" > "$SB/bin/pacman"
    chmod 755 "$SB/bin/pacman"
}
new_sandbox
pacman_stub
pr 'pm_run purge firefox vlc' PR_RC=7
check_eq 'pacman, purge: pacman -Rcn --noconfirm with the packages, with privileges, and its status' $'PR pacman -Rcn --noconfirm firefox vlc\nst=7' "$OUT"
pr 'pm_run clean'
check_eq 'pacman, clean: pacman -Sc --noconfirm' $'PR pacman -Sc --noconfirm\nst=0' "$OUT"
pr 'pm_run clean foo bar'
check_eq 'pacman, clean: it takes no names, so it gets none' $'PR pacman -Sc --noconfirm\nst=0' "$OUT"
pr 'pm_run autoremove' FAKE_PACMAN_OUT=$'fixorph\nfixlib'
check_eq 'pacman, autoremove: the orphans go to pacman -Rns --noconfirm' $'PR pacman -Rns --noconfirm fixorph fixlib\nst=0' "$OUT"
check_eq 'pacman, autoremove: the orphans are asked with pacman -Qdtq, and nothing else is asked' 'pacman -Qdtq' "$(cat "$SB/state/pacman.log")"
pr 'pm_run autoremove' PR_RC=5 FAKE_PACMAN_OUT=fixorph
check_eq 'pacman, autoremove: the status of the removal comes back' $'PR pacman -Rns --noconfirm fixorph\nst=5' "$OUT"
pr 'pm_run autoremove' FAKE_PACMAN_RC=1
check_eq 'pacman, autoremove with no orphans (no output, status 1): nothing runs and the status is 0' 'st=0' "$OUT"
pr 'pm_run autoremove' FAKE_PACMAN_OUT=$'fixorph\n\nfixlib\n'
check_eq 'pacman, autoremove: blank lines are skipped' $'PR pacman -Rns --noconfirm fixorph fixlib\nst=0' "$OUT"
for bad in '-Rdd' 'two words' 'Evil;x' 'a/b' '.hidden' ':x'; do
    pr 'pm_run autoremove' FAKE_PACMAN_OUT="fixorph"$'\n'"$bad"
    check_eq "pacman, autoremove: the answer has a name that is not a package name (\"$bad\"), so nothing runs (status 1)" 'st=1' "$OUT"
done
for refused in 'install firefox' 'PURGE foo' 'remove foo' 'upgrade' 'clean-all'; do
    read -ra args <<< "$refused"
    pr "pm_run ${args[*]}"
    check_eq "pacman, $refused: not an action of pm_run, status 2 and nothing runs" 'st=2' "$OUT"
done
pr 'apt_privileged() { echo APT; }; dnf_stub_never() { :; }; pm_run purge foo; pm_run clean'
check_eq 'pacman never goes through the apt backend' $'PR pacman -Rcn --noconfirm foo\nPR pacman -Sc --noconfirm\nst=0' "$OUT"
new_sandbox
pacman_stub
app_eval 'PM=pacman; pm_run purge firefox vlc; echo "st=$?"' FAKE_PACMAN_RC=3
check_eq 'through the real priv_run: the status of pacman comes back' 'st=3' "$OUT"
check_eq 'through the real priv_run: sudo runs pacman -Rcn --noconfirm, with no variables before it' 'sudo pacman -Rcn --noconfirm firefox vlc' "$(sudo_log)"
check_eq 'and pacman got exactly those arguments' 'pacman -Rcn --noconfirm firefox vlc' "$(cat "$SB/state/pacman.log")"
app_eval 'PM=pacman; pm_run clean; pm_run autoremove' FAKE_PACMAN_OUT=fixorph
check_eq 'through the real priv_run: clean, and autoremove (asks for the orphans, then removes them)' \
    $'pacman -Rcn --noconfirm firefox vlc\npacman -Sc --noconfirm\npacman -Qdtq\npacman -Rns --noconfirm fixorph' "$(cat "$SB/state/pacman.log")"
app_eval 'case " $PM_BACKENDS " in *" pacman "*) echo listed ;; *) echo missing ;; esac'
check_eq 'PM_BACKENDS: pacman has its backend to choose (step 5e)' 'listed' "$OUT"
app_eval 'PM=pacman; pm_tool; echo; pm_operation_text "purge foo bar"; echo; pm_operation_text purge; echo; pm_operation_text autoremove; echo
pm_operation_text clean; echo; pm_operation_text "purgex foo"; echo; pm_install_text; echo'
check_eq 'pacman: the texts of the records (purge is "-Rcn", autoremove is the orphans idiom, clean is "-Sc")' \
    $'pacman\npacman -Rcn foo bar\npacman -Rcn\npacman -Rns $(pacman -Qdtq)\npacman -Sc\npacman purgex foo\npacman -S' "$OUT"
app_eval 'PM=pacman; pm_interrupt_hint'
check_eq 'pacman: the hint of an interrupted run, with sudo by default' '# If pacman reports a broken state, start with: sudo pacman -Dk' "$OUT"
app_eval 'PM=pacman; PRIV_CMD=/usr/bin/doas; pm_interrupt_hint'
check_eq 'pacman: the hint names the privilege command in use' '# If pacman reports a broken state, start with: doas pacman -Dk' "$OUT"
plan=$'Remv foo [1.0-1]\nRemv bar [1.0-1]'
app_eval "PM=pacman; PRIV_CMD=/usr/bin/doas; write_removal_record \"\$HOME/rec.txt\" 'interrupted (SIGTERM)' $(printf '%q' "$plan") 'purge foo bar'"
rec="$(cat "$SB/home/rec.txt")"
assert_contains 'a pacman record: the operation as pacman runs it' "$rec" '# Operation: pacman -Rcn foo bar'
assert_contains 'a pacman record: the manager of the plan' "$rec" '# Packages in the pacman plan:'
assert_contains 'a pacman record: how to reinstall, with the names sorted' "$rec" '# doas pacman -S bar foo'
assert_contains 'a pacman record: the hint of the interrupted run' "$rec" 'start with: doas pacman -Dk'
assert_not_contains 'a pacman record does not name apt anywhere' "$rec" 'apt'

echo "-- the pacman backend: pm_simulate (4.6, step 5b)"
# The fixtures have the shape of what pacman 6.0.2 printed on a fake root, run by an unprivileged user in the
# C locale: "pacman -Rc|-Rs --print --print-format 'Remv %n [%v]'" prints the rows of the plan and nothing else
# (the dependents first, the target last) and ends with 0; a failure ("error: target not found: X", or the
# HoldPkg question on stdout) ends with 1 and has no rows; -Qdtq prints the orphans (none: nothing, status 1).
UNREADABLE_PACMAN_EN='Could not read the plan of pacman: its output does not have the expected format. Nothing was changed.'
# pacman_replay: a pacman that logs its arguments (pacman.log, one line per call) and its LC_ALL (pacman.env,
# one line per call) and replays files: for -Qdtq, pacman.orph (and pacman.orph.err on stderr) with the status
# FAKE_ORPH_RC; for anything else, pacman.out on stdout and pacman.err on stderr with the status FAKE_PACMAN_RC.
pacman_replay() {
    _stub pacman <<'EOF'
#!/bin/sh
S='@STATE@'
echo "pacman $*" >> "$S/pacman.log"
echo "${LC_ALL-unset}" >> "$S/pacman.env"
if [ "$1" = -Qdtq ]; then cat "$S/pacman.orph" 2>/dev/null; cat "$S/pacman.orph.err" >&2 2>/dev/null; exit "${FAKE_ORPH_RC:-0}"; fi
cat "$S/pacman.out" 2>/dev/null
cat "$S/pacman.err" >&2 2>/dev/null
exit "${FAKE_PACMAN_RC:-0}"
EOF
}
sp_out() { cat > "$SB/state/pacman.out"; }
sp_orph() { cat > "$SB/state/pacman.orph"; }
sp_err() { printf '%s\n' "$1" > "$SB/state/pacman.err"; }
pacman_log() { cat "$SB/state/pacman.log" 2>/dev/null || true; }
pacman_env() { cat "$SB/state/pacman.env" 2>/dev/null || true; }
# sp_reset: a new sandbox with the fake pacman and no old log, output or status (SP_RC and SP_ORPH_RC are the
# statuses of the plan and of -Qdtq; SP_ENV, the variables that the next run gets). Cases that read the log
# start with it: a log with an earlier call in it would make them fail.
SP_RC=0
SP_ORPH_RC=0
SP_ENV=()
sp_reset() { new_sandbox; pacman_replay; SP_RC=0; SP_ORPH_RC=0; SP_ENV=(); }
# sp_eval CODE [VAR=val...]: CODE with PM=pacman and the fake pacman; no privilege command is faked, so the
# fake sudo logs any use of it.
sp_eval() { app_eval "PM=pacman; $1" FAKE_PACMAN_RC="$SP_RC" FAKE_ORPH_RC="$SP_ORPH_RC" "${SP_ENV[@]+"${SP_ENV[@]}"}" "${@:2}"; }
# simpac ARG...: pm_simulate with those arguments, starting from an old plan. OUT: "st=STATUS" and then the
# plan between < and >, so that nothing around it can be lost.
simpac() { sp_eval "PLAN_OUTPUT=stale; pm_simulate $(printf '%q ' "$@"); echo \"st=\$?\"; printf '<%s>\\n' \"\$PLAN_OUTPUT\""; }
sp_unreadable() { check_eq "$1" $'st=1\n<'"$UNREADABLE_PACMAN_EN"'>' "$OUT"; }
PACMAN_RC_ARGS='--print --print-format Remv %n [%v] --noconfirm --color never --'

# What pacman printed (measured), and the call the program makes
sp_reset
printf '%s\n' 'Remv fixb [1.0-1]' 'Remv fixa [1.0-1]' | sp_out
simpac purge fixa
check_eq 'purge with a dependent: both rows, in the order pacman prints them; status 0' $'st=0\n<Remv fixb [1.0-1]\nRemv fixa [1.0-1]>' "$OUT"
check_eq 'purge: pacman got -Rc --print with the format, --noconfirm, --color never and "--" before the name' \
    "pacman -Rc $PACMAN_RC_ARGS fixa" "$(pacman_log)"
check_eq 'purge: pacman ran in the C locale' 'C' "$(pacman_env)"
check_eq 'purge: and no privileges were asked' '' "$(sudo_log)"
simpac purge fixa fixb
check_eq 'purge of two packages: both names reach pacman, in order' "pacman -Rc $PACMAN_RC_ARGS fixa fixb" "$(pacman_log | tail -n1)"
simpac purge -Rdd
check_eq 'a name that looks like an option goes after "--", where pacman reads it as a name' "pacman -Rc $PACMAN_RC_ARGS -Rdd" "$(pacman_log | tail -n1)"
sp_reset
printf '%s\n' 'Remv foo_bar [1:1.0-1]' 'Remv libstdc++ [14.1.1+r5-3]' 'Remv python-a.b@c [3.2.1~rc1-4]' 'Remv gtk3 [3.24.38-1]' 'Remv pkg_x [2.0_rc1-1]' \
    'Remv foo-git [r123.g1a2b3c4-1]' 'Remv NetworkManager [1.44.2.RC1-1]' 'Remv r-base [R4.3.1-1]' | sp_out
simpac purge foo_bar
check_eq 'names with _ + . and @, versions with epoch, + _ and ~, capitals, a letter first: each row is read whole' \
    $'st=0\n<Remv foo_bar [1:1.0-1]\nRemv libstdc++ [14.1.1+r5-3]\nRemv python-a.b@c [3.2.1~rc1-4]\nRemv gtk3 [3.24.38-1]\nRemv pkg_x [2.0_rc1-1]\nRemv foo-git [r123.g1a2b3c4-1]\nRemv NetworkManager [1.44.2.RC1-1]\nRemv r-base [R4.3.1-1]>' "$OUT"
sp_eval "pm_simulate purge foo_bar; plan_package_names \"\$PLAN_OUTPUT\" | tr ' ' '\\n' | while read -r n; do [ -z \"\$n\" ] || { pm_valid_name \"\$n\" && echo ok || echo \"bad:\$n\"; }; done | sort | uniq -c | tr -s ' ' | tr '\\n' ';'"
check_eq 'every name read from a pacman plan passes pm_valid_name (pacman)' ' 8 ok;' "$OUT"
sp_reset
printf '%s\n' 'Remv fixa [1.0-1]' | sp_out
SP_ENV=(LC_ALL=C.UTF-8 LANGUAGE=es)
simpac purge fixa
check_eq 'pacman runs in the C locale even if the caller has another (LC_ALL and LANGUAGE)' 'C' "$(pacman_env)"

# What pacman writes besides the plan
sp_reset
printf '%s\n' 'Remv fixa [1.0-1]' | sp_out
sp_err "warning: config file /etc/pacman.conf, line 12: directive 'Foo' in section 'options' not recognized."
simpac purge fixa
check_eq 'a "warning:" line on stderr is skipped: the plan is still the plan' $'st=0\n<Remv fixa [1.0-1]>' "$OUT"
printf '%s\n' 'warning: first' 'Remv fixb [1.0-1]' 'warning: second' '' 'Remv fixa [1.0-1]' 'warning: last' | sp_out
simpac purge fixa
check_eq 'warnings and blank lines between and around the rows are skipped; the rows keep their order' $'st=0\n<Remv fixb [1.0-1]\nRemv fixa [1.0-1]>' "$OUT"
printf '%s\n' 'Remv fixa [1.0-1]' | sp_out
sp_err $'warning: a\nwarning: b'
simpac purge fixa
check_eq 'several warnings on stderr' $'st=0\n<Remv fixa [1.0-1]>' "$OUT"
printf '%s\n' 'warning: a' 'warning: b' | sp_out
: > "$SB/state/pacman.err"
simpac purge fixa
sp_unreadable 'only warnings (status 0): no rows, so no plan'

# autoremove: the orphans decide
sp_reset
printf '%s\n' fixorph fixlib | sp_orph
printf '%s\n' 'Remv fixorph [1.0-1]' 'Remv fixlib [2.1+r5-3]' | sp_out
simpac autoremove
check_eq 'autoremove: the rows of the plan of the orphans; status 0' $'st=0\n<Remv fixorph [1.0-1]\nRemv fixlib [2.1+r5-3]>' "$OUT"
check_eq 'autoremove: it asks for the orphans, then simulates -Rs on them (not -Rc)' \
    $'pacman -Qdtq\n'"pacman -Rs $PACMAN_RC_ARGS fixorph fixlib" "$(pacman_log)"
check_eq 'autoremove: both calls ran in the C locale' $'C\nC' "$(pacman_env)"
check_eq 'autoremove: and no privileges were asked' '' "$(sudo_log)"
sp_reset
printf '%s\n' fixorph fixlib | sp_orph
printf '%s\n' 'Remv fixorph [1.0-1]' | sp_out
simpac autoremove fixa
check_eq 'autoremove ignores its arguments: the orphans decide' "pacman -Rs $PACMAN_RC_ARGS fixorph fixlib" "$(pacman_log | tail -n1)"
sp_reset
printf 'fixorph\n\nfixlib\n\n' | sp_orph
printf '%s\n' 'Remv fixorph [1.0-1]' | sp_out
simpac autoremove
check_eq 'autoremove: blank lines in the list of orphans are skipped' "pacman -Rs $PACMAN_RC_ARGS fixorph fixlib" "$(pacman_log | tail -n1)"
sp_reset
printf '%s\n' 'Remv fixorph [1.0-1]' 'Remv fixdep [1.0-1]' 'Remv fixlib [2.1+r5-3]' | sp_out
printf '%s\n' fixorph fixlib | sp_orph
simpac autoremove
check_eq 'autoremove: the plan is the one of pacman, which may have more rows than orphans' $'st=0\n<Remv fixorph [1.0-1]\nRemv fixdep [1.0-1]\nRemv fixlib [2.1+r5-3]>' "$OUT"
sp_reset
SP_ORPH_RC=1
printf '%s\n' 'Remv stale [1.0-1]' | sp_out
simpac autoremove
check_eq 'autoremove with no orphans (pacman: nothing, status 1): status 0 and an empty plan, not the old one' $'st=0\n<>' "$OUT"
check_eq 'autoremove with no orphans: only the orphans were asked, so no plan was simulated' 'pacman -Qdtq' "$(pacman_log)"
for bad in '-Rdd' 'two words' 'Evil;x' 'a/b' '.hidden' ':x'; do
    sp_reset
    printf '%s\n' fixorph "$bad" | sp_orph
    printf '%s\n' 'Remv fixorph [1.0-1]' | sp_out
    simpac autoremove
    sp_unreadable "autoremove: a name that is not a package name in the orphans (\"$bad\"): status 1, no plan"
    check_eq "autoremove: with \"$bad\" among the orphans nothing was simulated" 'pacman -Qdtq' "$(pacman_log)"
done
sp_reset
printf '%s\n' fixorph | sp_orph
sp_err 'error: failed to prepare transaction (could not satisfy dependencies)'
SP_RC=1
simpac autoremove
check_eq 'autoremove: pacman fails on the orphans: its status and its text' $'st=1\n<error: failed to prepare transaction (could not satisfy dependencies)>' "$OUT"

sp_reset
printf '%s\n' fixorph fixlib | sp_orph
printf '%s\n' "warning: config file /etc/pacman.conf, line 3: it is a warning" > "$SB/state/pacman.orph.err"
printf '%s\n' 'Remv fixorph [1.0-1]' | sp_out
simpac autoremove
check_eq 'autoremove: what -Qdtq writes on stderr does not reach the screen or the plan' $'st=0\n<Remv fixorph [1.0-1]>' "$OUT"
sp_reset
printf '%s\n' fixorph fixlib | sp_orph
sp_eval 'pacman_orphans; echo "st=$? n=${#PACMAN_ORPHANS[@]} [${PACMAN_ORPHANS[*]}]"'
check_eq 'pacman_orphans: the names, in order; status 0' 'st=0 n=2 [fixorph fixlib]' "$OUT"
printf '%s\n' fixorph '-Rdd' fixlib | sp_orph
sp_eval 'PACMAN_ORPHANS=(old); pacman_orphans; echo "st=$? n=${#PACMAN_ORPHANS[@]}"'
check_eq 'pacman_orphans: a name that is not a package name makes the list empty, all of it, and the status 1' 'st=1 n=0' "$OUT"
sp_reset
SP_ORPH_RC=1
sp_eval 'PACMAN_ORPHANS=(old); pacman_orphans; echo "st=$? n=${#PACMAN_ORPHANS[@]}"'
check_eq 'pacman_orphans: no orphans (nothing, status 1): status 0 and an empty list, not the old one' 'st=0 n=0' "$OUT"
sp_eval 'set -e; pacman_orphans; echo "st=$? n=${#PACMAN_ORPHANS[@]}"'
check_eq 'pacman_orphans: no orphans does not end a shell that has set -e' 'st=0 n=0' "$OUT"

# Failures: the status of pacman decides, and its text is the message
sp_reset
sp_err 'error: target not found: nosuch'
SP_RC=1
simpac purge nosuch
check_eq 'a name pacman does not know: its status and its text, no rows' $'st=1\n<error: target not found: nosuch>' "$OUT"
simpac purge fixa nosuch
check_eq 'a name pacman does not know among known ones: no partial plan, the error as a whole' $'st=1\n<error: target not found: nosuch>' "$OUT"
sp_reset
printf '%s\n' ':: HoldPkg was found in target list. Do you want to continue? [y/N]' | sp_out
SP_RC=1
simpac purge holdme
check_eq 'a package of HoldPkg: status 1 and the question of pacman as the text' $'st=1\n<:: HoldPkg was found in target list. Do you want to continue? [y/N]>' "$OUT"
sp_reset
printf '%s\n' ':: HoldPkg was found in target list. Do you want to continue? [y/N]' | sp_out
sp_err 'warning: it is a warning'
SP_RC=1
simpac purge holdme
check_eq 'an error keeps its whole text, in order, with the warnings (stdout first, then stderr)' $'st=1\n<:: HoldPkg was found in target list. Do you want to continue? [y/N]\nwarning: it is a warning>' "$OUT"
sp_reset
printf '\n%s\n\n%s\n\n' 'error: first' 'error: second' | sp_out
SP_RC=1
simpac purge fixa
check_eq 'an error: blank lines are dropped and nothing is left at the end' $'st=1\n<error: first\nerror: second>' "$OUT"
sp_reset
printf '%s\n' 'Remv fixa [1.0-1]' | sp_out
sp_err 'error: failed to commit transaction (conflicting files)'
SP_RC=1
simpac purge fixa
check_eq 'status 1 with rows: it is an error, not a plan; the text has all its lines' $'st=1\n<Remv fixa [1.0-1]\nerror: failed to commit transaction (conflicting files)>' "$OUT"
for rc in 2 5 127; do
    sp_reset
    sp_err 'error: boom'
    SP_RC=$rc
    simpac purge fixa
    check_eq "a failure of pacman with status $rc: that status and its text" $'st='"$rc"$'\n<error: boom>' "$OUT"
done
sp_reset
SP_RC=3
simpac purge fixa
check_eq 'a failure that prints nothing: its status (3) and the unreadable message, never an empty text' $'st=3\n<'"$UNREADABLE_PACMAN_EN"'>' "$OUT"

# Status 0 is not enough: the text has to be a plan
sp_reset
simpac purge fixa
sp_unreadable 'status 0 and no output at all: an error, never an empty plan'
for bad in 'error: target not found: nosuch' ':: Proceed with removal? [Y/n]' 'Remv fixb' 'Remv fixb []' 'Remv fixb [1.0-1] extra' 'Remv fixb [1.0 -1]' \
    'remv fixb [1.0-1]' 'Purg fixb [1.0-1]' 'Inst fixb [1.0-1]' 'Remv  fixb [1.0-1]' ' Remv fixb [1.0-1]' 'Remv fixb [1.0-1] ' 'Remv fixb [1.0-1]x' \
    'Remv fixb 1.0-1' 'fixb [1.0-1]' 'Remv -Rdd [1.0-1]' 'Remv a/b [1.0-1]' 'Remv Evil;x [1.0-1]' 'Remv foo:bar [1.0-1]' 'Remv .hidden [1.0-1]' \
    'Remv fixb [-1.0]' 'Remv fixb [.1.0]' 'Remv fixb [_1]' 'Remv fixb [+1]' 'Remv fixb [~1]' 'Remv fixb [:1]' 'Remv fixb [1.0;ls]' 'Remv fixb [$(id)]' 'Remv fixb [1.0/2]' 'warning:no-space' 'Warning: capital' ' warning: leading space' \
    $'Remv fixb [1.0-1]\r' $'Remv fixb [1.0-1]\e[0m' $'Remv fi\axb [1.0-1]' $'Remv\tfixb [1.0-1]' $'Remv fixb [1.0\t-1]'; do
    printf '%s\n' 'Remv fixa [1.0-1]' "$bad" | sp_out
    simpac purge fixa
    sp_unreadable "a good row and then a line that is not one ($(printf '%q' "$bad")): the whole plan is distrusted, status 1"
done
printf '%s\n' 'Remv fixa [1.0-1]' | sp_out
sp_err 'error: it printed an error and still ended with 0'
simpac purge fixa
sp_unreadable 'status 0 but an error on stderr next to the rows: no plan'

# pacman_read_plan, read directly
sp_eval 'pacman_read_plan 0 < <(printf "Remv fixa [1.0-1]"); echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
check_eq 'read directly: the last line with no newline is read (status 0)' $'st=0\n<Remv fixa [1.0-1]>' "$OUT"
sp_eval 'pacman_read_plan 1 < <(printf "error: boom"); echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
check_eq 'read directly: an error text with no newline at the end is kept' $'st=1\n<error: boom>' "$OUT"
sp_eval 'pacman_read_plan 0 < <(printf "Remv fixa [1.0-1]\nboom"); echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
sp_unreadable 'read directly: a last line with no newline that is not a row counts (status 0 with it is no plan)'
sp_eval 'pacman_read_plan 0 < <(printf "\n\nRemv fixa [1.0-1]\n\n\nRemv fixb [1.0-1]\n\n"); echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
check_eq 'read directly: blank lines are skipped' $'st=0\n<Remv fixa [1.0-1]\nRemv fixb [1.0-1]>' "$OUT"
sp_eval 'pacman_read_plan 0 < <(printf "\n\n"); echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
sp_unreadable 'read directly: only blank lines (status 0): no plan'
sp_eval 'pacman_read_plan 7 < <(printf "Remv fixa [1.0-1]\nerror: boom\n"); echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
check_eq 'read directly: any status other than 0 comes back as it is, and the text is the error' $'st=7\n<Remv fixa [1.0-1]\nerror: boom>' "$OUT"
sp_eval 'pacman_read_plan 0 < /dev/null; echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
sp_unreadable 'read directly: nothing to read (status 0): no plan'

# Refusals and dispatch
sp_reset
for refused in 'clean' 'install fixa' 'PURGE fixa' 'purge-all' '-Rc fixa' 'purge;ls fixa'; do
    read -ra args <<< "$refused"
    simpac "${args[@]}"
    check_eq "pm_simulate $refused: refused, status 2 and an empty plan" $'st=2\n<>' "$OUT"
done
sp_eval 'pm_simulate "" purge fixa; echo "st=$?"'
check_eq 'an empty action is refused' 'st=2' "$OUT"
sp_eval 'pm_simulate; echo "st=$?"'
check_eq 'no arguments at all is refused' 'st=2' "$OUT"
check_eq 'none of the refused calls reached pacman or the privileges' ':' "$(pacman_log):$(sudo_log)"
sp_reset
sp_eval 'simulate_pacman clean fixa; echo "st=$?"; simulate_pacman "" ; echo "st=$?"; simulate_pacman PURGE x; echo "st=$?"'
check_eq 'simulate_pacman, refused: an action that is not purge or autoremove is 2, called directly too' $'st=2\nst=2\nst=2' "$OUT"
check_eq 'simulate_pacman, refused: and it ran nothing' ':' "$(pacman_log):$(sudo_log)"
sp_reset
printf '%s\n' 'Remv fixa [1.0-1]' | sp_out
sp_eval 'apt_privileged() { echo APT; }; simulate_apt() { echo SA; }; simulate_dnf() { echo SD; }; priv_run() { echo PRIV; }
pm_simulate purge fixa; echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
check_eq 'pacman goes through none of the apt or dnf backends, nor through the privilege command' $'st=0\n<Remv fixa [1.0-1]>' "$OUT"
sp_eval 'pm_simulate purge fixa; a="$PLAN_OUTPUT"; simulate_pacman purge fixa; [ "$a" = "$PLAN_OUTPUT" ] && echo same'
check_eq 'pm_simulate leaves exactly the plan of its backend simulate_pacman' 'same' "$OUT"
sp_reset
sp_eval 'PM=apt; pm_simulate purge fixa >/dev/null'
check_eq 'with apt as the manager, pacman is not asked' '' "$(pacman_log)"
sp_eval 'PM=dnf; PLAN_OUTPUT=stale; simulate_dnf() { echo "SD"; return 5; }; pm_simulate purge fixa; echo "st=$?"'
check_eq 'with dnf as the manager, the dnf backend is the one asked' $'SD\nst=5' "$OUT"

# Messages in each language, and what the plan feeds
sp_reset
SP_ENV=(MINTAPP_LANG=es MINTAPP_ASCII=0)
simpac purge fixa
check_eq 'an unreadable plan, in Spanish' $'st=1\n<No se pudo leer el plan de pacman: su salida no tiene el formato esperado. No se cambió nada.>' "$OUT"
SP_ENV=(MINTAPP_LANG=en)
simpac purge fixa
sp_unreadable 'an unreadable plan, in English'
sp_reset
sp_err 'error: target not found: nosuch'
SP_RC=1
SP_ENV=(MINTAPP_LANG=es MINTAPP_ASCII=0)
simpac purge nosuch
check_eq "the text of an error that pacman gives is pacman's, whatever the language" $'st=1\n<error: target not found: nosuch>' "$OUT"
sp_reset
printf '%s\n' 'Remv fixb [1.0-1]' 'Remv fixa [1.0-1]' | sp_out
sp_eval 'pm_simulate purge fixa; plan_has_removals "$PLAN_OUTPUT"; echo "has=$?"; plan_package_names "$PLAN_OUTPUT"; echo'
check_eq 'the plan is what plan_has_removals and plan_package_names read' $'has=0\nfixa fixb ' "$OUT"
sp_eval 'pm_simulate purge fixa; a=$(plan_fingerprint "$PLAN_OUTPUT"); b=$(plan_fingerprint "$OTHER"); [ "$a" = "$b" ] && echo same' OTHER=$'Remv fixa [1.0-1]\nRemv fixb [1.0-1]'
check_eq 'plan_fingerprint of a pacman plan does not depend on the order of its rows' 'same' "$OUT"
sp_eval 'plan_still_valid "$CONFIRMED" purge fixa; echo "st=$?"' CONFIRMED=$'Remv fixa [1.0-1]\nRemv fixb [1.0-1]'
check_eq 'plan_still_valid: the same plan, simulated again through pm_simulate (any order): valid' 'st=0' "$OUT"
sp_eval 'plan_still_valid "$CONFIRMED" purge fixa; echo "st=$?"' CONFIRMED=$'Remv fixa [1.0-1]\nRemv fixb [1.0-1]\nRemv fixc [1.0-1]'
check_eq 'plan_still_valid: the confirmed plan has one more row than the new one: not valid' 'st=1' "$OUT"
sp_eval 'plan_still_valid "$CONFIRMED" purge fixa; echo "st=$?"' CONFIRMED=$'Remv fixa [1.0-2]\nRemv fixb [1.0-1]'
check_eq 'plan_still_valid: a package changed its version: not valid' 'st=1' "$OUT"
sp_reset
sp_err 'error: target not found: fixa'
SP_RC=1
sp_eval 'plan_still_valid "$CONFIRMED" purge fixa; echo "st=$?"' CONFIRMED='Remv fixa [1.0-1]'
check_eq 'plan_still_valid: pacman now fails: not valid' 'st=1' "$OUT"
sp_reset
sp_eval 'plan_meta_packages "$PLAN" fixa; echo "st=$?"' PLAN=$'Remv fixa [1.0-1]\nRemv kde-meta-x [1.0-1]\nRemv fixb [1.0-1]'
check_eq 'plan_meta_packages reads a pacman plan: the name that matches a pattern, not the one asked for' $'kde-meta-x\nst=0' "$OUT"

# The code
check_eq 'control: the code has simulate_pacman, pacman_read_plan and a pacman --print' 'yes yes yes' \
    "$(at_least_one "$(code_only | count_of 'simulate_pacman')") $(at_least_one "$(code_only | count_of 'pacman_read_plan')") $(at_least_one "$(code_only | count_of 'pacman .*--print')")"
check_eq 'only pm_simulate asks simulate_pacman (its backend)' 0 "$(code_only | strip_functions pm_simulate simulate_pacman | count_of 'simulate_pacman')"
check_eq 'only simulate_pacman reads a plan with pacman_read_plan' 0 "$(code_only | strip_functions simulate_pacman pacman_read_plan | count_of 'pacman_read_plan')"
check_eq 'only simulate_pacman runs pacman with --print (the plan of a removal)' 0 "$(code_only | strip_functions simulate_pacman | count_of 'pacman .*--print')"

echo "-- the pacman backend: pm_installed and pm_owner (4.6, step 5c)"
# The fixtures have the shape of what pacman 6.0.2 printed on a fake root, run by an unprivileged user in the
# C locale (the cases against the real pacman are those of step 5f): "pacman -Q -- NAME" prints "NAME VERSION"
# and fails if the package is not installed; "pacman -Qo -- PATH..." prints "PATH is owned by NAME VERSION" for
# each owner (a folder with a "/" at the end, once per package that has it) and "error: ..." on stderr for a
# path nobody owns, with status 1 if there is any.
# pacman_calls: a pacman that logs its arguments (pacman.log, one line per call), how many it got (pacman.argc)
# and its LC_ALL (pacman.env); it writes pacman.err on stderr first (pacman prints its warnings before anything
# else) and then prints pacman.out.N, the file of the call number N, or else pacman.out; its status is
# FAKE_PACMAN_RC.
pacman_calls() {
    _stub pacman <<'EOF'
#!/bin/sh
S='@STATE@'
echo "pacman $*" >> "$S/pacman.log"
echo "$#" >> "$S/pacman.argc"
echo "${LC_ALL-unset}" >> "$S/pacman.env"
n=$(wc -l < "$S/pacman.log")
f="$S/pacman.out.$((n))"
[ -f "$f" ] || f="$S/pacman.out"
cat "$S/pacman.err" >&2 2>/dev/null
cat "$f" 2>/dev/null
exit "${FAKE_PACMAN_RC:-0}"
EOF
}
pacman_argc() { tr '\n' ' ' < "$SB/state/pacman.argc" 2>/dev/null | sed 's/ $//' || true; }
# qo_reset: a new sandbox with that pacman and nothing of an earlier case (QO_RC is its status).
QO_RC=0
qo_reset() { new_sandbox; pacman_calls; QO_RC=0; }
# qo_out [N] < TEXT: what pacman prints, in its call number N if given and in every call otherwise.
qo_out() { cat > "$SB/state/pacman.out${1:+.$1}"; }
# qe CODE [VAR=val...]: CODE with PM=pacman and that pacman. No privilege command is faked, so the fake sudo
# logs any use of it.
qe() { app_eval "PM=pacman; $1" FAKE_PACMAN_RC="$QO_RC" "${@:2}"; }

# pm_installed
qo_reset
printf '%s\n' 'fixa 1.0-1' | qo_out
qe 'pm_installed fixa; echo "rc=$?"'
check_eq 'an installed package: pm_installed succeeds' 'rc=0' "$OUT"
check_eq 'pacman got -Q, "--" and the name, and was asked once' 'pacman -Q -- fixa' "$(pacman_log)"
check_eq 'pacman ran in the C locale' 'C' "$(pacman_env)"
check_eq 'and no privileges were asked' '' "$(sudo_log)"
qe 'pm_installed Fixa; echo "rc=$?"'
check_eq 'the name is compared as it is: "Fixa" is not "fixa" (pacman prints the one it knows)' 'rc=1' "$OUT"
qo_reset
printf '%s\n' 'fixa-extra 1.0-1' | qo_out
qe 'pm_installed fixa; echo "rc=$?"'
check_eq 'pacman printed another name: not installed (that name is compared with the one asked)' 'rc=1' "$OUT"
qo_reset
QO_RC=1
sp_err "error: package 'fixa' was not found"
qe 'pm_installed fixa; echo "rc=$?"'
check_eq 'a package that is not installed (no output, status 1): not installed' 'rc=1' "$OUT"
qo_reset
QO_RC=1
printf '%s\n' 'fixa 1.0-1' | qo_out
qe 'pm_installed fixa; echo "rc=$?"'
check_eq 'the output of a query that failed is not read (a row, status 1): not installed' 'rc=1' "$OUT"
qo_reset
printf '%s\n' 'fixa 1.0-1' | qo_out
sp_err 'warning: config file /etc/pacman.conf, line 12: directive Foo not recognized.'
qe 'pm_installed fixa; echo "rc=$?"'
check_eq 'a warning on stderr does not change the answer' 'rc=0' "$OUT"
qo_reset
qe 'pm_installed ""; echo "rc=$?"'
check_eq 'an empty name: not installed' 'rc=1' "$OUT"
check_eq 'and pacman is not asked' '' "$(pacman_log)"
qo_reset
printf '%s\n' '-a 1.0-1' | qo_out
qe 'pm_installed -a; echo "rc=$?"'
check_eq 'a package called "-a" is a name: pacman got it after "--" and the answer is read' 'rc=0' "$OUT"
check_eq 'pacman was asked "pacman -Q -- -a" and not "pacman -Q -a"' 'pacman -Q -- -a' "$(pacman_log)"
new_sandbox
_stub pacman <<'EOF'
#!/bin/sh
exit 127
EOF
qe 'pm_installed fixa; echo "rc=$?"'
check_eq 'a pacman that cannot run (status 127): not installed' 'rc=1' "$OUT"
qo_reset
printf '%s\n' 'fixa 1.0-1' | qo_out
qe 'PM=apt; pm_installed fixa; echo "rc=$?"'
check_eq 'with apt as the manager pacman is not asked' '' "$(pacman_log)"

# pacman_plain_path: the paths that pacman prints back as they were given
qo_reset
qe 'while IFS="|" read -r p want; do
    if pacman_plain_path "$p"; then got=yes; else got=no; fi
    [ "$got" = "$want" ] || echo "BAD <$p>: $got"
done <<"EOT"
/usr/share/applications/a.desktop|yes
/opt/my app/c d.desktop|yes
/a/.hidden|yes
/a/..x|yes
/a/.../x|yes
/a|yes
/|no
|no
a/b|no
./a|no
../a|no
/a//b|no
//a|no
/a/./b|no
/a/../b|no
/a/b/|no
/a/.|no
/a/..|no
EOT
p=$(printf "/a\nb"); pacman_plain_path "$p" && echo "BAD newline: yes"
echo done'
check_eq 'pacman_plain_path: absolute, with no "//", no "." or ".." component, no "/" at the end, no line break' 'done' "$OUT"

# pacman_owned_lines: "NAME PATH" for each answer of pacman
qo_reset
qo_out <<'EOF'
/x/a is owned by pkg-a 1.0-1
/x/dir/ is owned by pkg-b 2:3.4_rc1-5
/x/dir/ is owned by pkg-c r123.g1a2b3c4-1
/x/odd is owned by name is owned by pkg-d 1.0-1
EOF
qe 'pacman_owned_lines /x/a /x/dir /x/odd; echo "st=$?"'
check_eq 'pacman_owned_lines: "NAME PATH" per answer, the path as pacman prints it, one line per owner; the whole path even if it holds " is owned by "' \
    $'pkg-a /x/a\npkg-b /x/dir/\npkg-c /x/dir/\npkg-d /x/odd is owned by name\nst=0' "$OUT"
qo_reset
qo_out <<'EOF'
error: No package owns /x/none
warning: something odd
x/y is owned by foo 1.0-1
/x/a is owned by -bad 1.0-1
/x/b is owned by Evil;x 1.0-1
/x/c is owned by foo ;rm
/x/d is owned by foo bar baz
/x/e is owned by foo
/x/f is owned by  1.0-1

/x/ok is owned by pkg-ok 1.0-1
EOF
qe 'pacman_owned_lines /x/none /x/a; echo "st=$?"'
check_eq 'pacman_owned_lines: what is not an answer is skipped (errors, a path that is not absolute, a bad name, a bad version, other words, no version, no name, blank lines)' $'pkg-ok /x/ok\nst=0' "$OUT"

# pm_owner
qo_reset
qo_out <<'EOF'
/usr/share/applications/a.desktop is owned by pkg-a 1.0-1
/usr/share/applications/b.desktop is owned by pkg-b1 2.0-1
/usr/share/applications/b.desktop is owned by pkg-b2 3.1-2
/opt/my app/c d.desktop is owned by pkg-c 1:4.0-1
EOF
sp_err 'error: No package owns /usr/share/applications/none.desktop'
QO_RC=1
qe 'pm_owner /usr/share/applications/a.desktop /usr/share/applications/none.desktop /usr/share/applications/b.desktop "/opt/my app/c d.desktop"; echo "st=$?"'
check_eq 'a line "owner: path" for each path somebody owns, none for the rest, no error shown, and status 0 although pacman failed' \
    $'pkg-a: /usr/share/applications/a.desktop\npkg-b1, pkg-b2: /usr/share/applications/b.desktop\npkg-c: /opt/my app/c d.desktop\nst=0' "$OUT"
check_eq 'one question to pacman for all the paths, with "-Qo" and "--" before them' \
    'pacman -Qo -- /usr/share/applications/a.desktop /usr/share/applications/none.desktop /usr/share/applications/b.desktop /opt/my app/c d.desktop' "$(pacman_log)"
check_eq 'and each path is an argument of its own (the one with spaces too)' '6' "$(pacman_argc)"
check_eq 'pacman ran in the C locale' 'C' "$(pacman_env)"
check_eq 'asking who owns a file needs no privileges' '' "$(sudo_log)"
qo_reset
qe 'pm_owner; echo "rc=$?"'
check_eq 'without paths: status 2' 'rc=2' "$OUT"
check_eq 'and pacman is not asked' '' "$(pacman_log)"
qo_reset
qo_out <<'EOF'
/usr/share/fixroot/ is owned by fixb 1.0-1
/usr/share/fixroot/ is owned by fixa 1.0-1
EOF
qe 'pm_owner /usr/share/fixroot'
check_eq 'a folder that two packages share: pacman prints it with a "/" at the end and a line for each; both names, sorted' 'fixa, fixb: /usr/share/fixroot' "$OUT"
qo_reset
qo_out <<'EOF'
/x/a is owned by pkg-a 1.0-1
/x/a is owned by pkg-a 1.0-1
EOF
qe 'pm_owner /x/a'
check_eq 'an owner that pacman prints twice is named once' 'pkg-a: /x/a' "$OUT"
qo_reset
_stub sort <<'EOF'
#!/bin/sh
echo "${LC_ALL-unset}" >> "@STATE@/sort.env"
exec /usr/bin/sort "$@"
EOF
qo_out <<'EOF'
/x/a is owned by b-pkg 1.0-1
/x/a is owned by B-pkg 1.0-1
/x/a is owned by a-pkg 1.0-1
EOF
qe 'pm_owner /x/a' LC_ALL=C.UTF-8
check_eq 'the names are sorted in the C locale (capitals first)' 'B-pkg, a-pkg, b-pkg: /x/a' "$OUT"
check_eq 'and sort itself ran with LC_ALL=C, whatever the caller has' 'C' "$(cat "$SB/state/sort.env")"
qo_reset
qo_out <<'EOF'
/x/a is owned by b/c.desktop is owned by pkg-c 1.0-1
EOF
qe 'pm_owner "/x/a is owned by b/c.desktop"'
check_eq 'a path that holds " is owned by ": the last two words are the name and the version' 'pkg-c: /x/a is owned by b/c.desktop' "$OUT"
qo_reset
qo_out <<'EOF'
error: No package owns /x/none
/x/a is owned by -bad 1.0-1
/x/b is owned by foo ;rm
y/c is owned by foo 1.0-1

/x/ok is owned by pkg-ok 1.0-1
EOF
qe 'pm_owner /x/none /x/a /x/b /x/c /x/ok'
check_eq 'pm_owner skips what is not an answer, as pacman_owned_lines does' 'pkg-ok: /x/ok' "$OUT"
qo_reset
qe 'pm_owner /x/a /x/b; echo "rc=$?"'
check_eq 'pacman says nothing: no line and status 0' 'rc=0' "$OUT"
qo_reset
qo_out <<'EOF'
/real/x.desktop is owned by pkg 1.0-1
EOF
qe 'pm_owner /lnk/x.desktop'
check_eq 'a plain path that pacman answers in another form (a folder that is a link) counts as having no owner' '' "$OUT"
qo_reset
sp_err '/x/a is owned by intruder 1.0-1'
qe 'pm_owner /x/a'
check_eq 'what pacman writes on stderr is never read as an answer, even if it has the shape of one' '' "$OUT"

# paths that are not plain go one by one, with "./" before a name that has no "/"
qo_reset
qo_out 1 <<'EOF'
/usr/share/applications/a.desktop is owned by pkg-a 1.0-1
EOF
qo_out 2 <<'EOF'
/opt/dup.desktop is owned by pkg-d 1.0-1
EOF
qo_out 3 <<'EOF'
/home/u/bare.desktop is owned by pkg-b 1.0-1
EOF
qo_out 4 <<'EOF'
/home/up.desktop is owned by pkg-u2 1.0-1
/home/up.desktop is owned by pkg-u1 1.0-1
EOF
qe 'pm_owner /usr/share/applications/a.desktop /opt//dup.desktop bare.desktop ../up.desktop ""'
check_eq 'a path that is not plain is asked on its own, and every line of the answer is its owner; an empty path is skipped' \
    $'pkg-a: /usr/share/applications/a.desktop\npkg-d: /opt//dup.desktop\npkg-b: bare.desktop\npkg-u1, pkg-u2: ../up.desktop' "$OUT"
check_eq 'the plain paths go together first; then one question for each of the others, "./" before a name without "/"' \
    $'pacman -Qo -- /usr/share/applications/a.desktop\npacman -Qo -- /opt//dup.desktop\npacman -Qo -- ./bare.desktop\npacman -Qo -- ../up.desktop' "$(pacman_log)"
qo_reset
qo_out <<'EOF'
/x/y is owned by pkg-y 1.0-1
EOF
qe 'pm_owner a.desktop /x//y'
check_eq 'with no plain path there is no question for the batch' $'pacman -Qo -- ./a.desktop\npacman -Qo -- /x//y' "$(pacman_log)"
qo_reset
qe 'pm_owner "/x/a
b"'
check_eq 'a path with a line break is not plain: it gets a question of its own' 'pacman -Qo -- /x/a
b' "$(pacman_log)"

# the callers
qo_reset
qo_out <<'EOF'
/x/a.desktop is owned by pkg-x 1.0-1
/x/b.desktop is owned by pkg-z 1.0-1
/x/b.desktop is owned by pkg-y 1.0-1
EOF
qe 'load_launcher_owners /x/a.desktop /x/b.desktop; printf "<<%s|%s>>" "${LAUNCHER_OWNERS[/x/a.desktop]:-}" "${LAUNCHER_OWNERS[/x/b.desktop]:-}"'
check_eq 'load_launcher_owners reads what pm_owner prints with pacman' '<<pkg-x|pkg-y, pkg-z>>' "$OUT"
qo_reset
qe 'package_installed() { pm_installed "$1"; }; package_installed fixa; echo "rc=$?"' FAKE_PACMAN_RC=1
check_eq 'package_installed asks pm_installed with pacman: nothing printed, so not installed' 'rc=1' "$OUT"

echo "-- pm_residual: the packages that kept their configuration (FP.4, P.4c)"
new_sandbox
fake_installed libold vim foo-config; fake_configfiles libold foo-config
app_eval 'pm_residual; echo "st=$?"'
check_eq 'apt: the packages in the state rc, one per line' $'libold\nfoo-config\nst=0' "$OUT"
new_sandbox
fake_installed vim
app_eval 'pm_residual; echo "st=$?"'
check_eq 'apt: none has kept its configuration' 'st=0' "$OUT"
for other in dnf zypper pacman nope; do
    app_eval "PM=$other; pm_residual; echo \"st=\$?\""
    check_eq "$other has no such state: status 2" 'st=2' "$OUT"
done

echo "-- pm_valid_name: what can be the name of a package (4.6)"
# names_check MANAGER STATUS NAME...: pm_valid_name of that manager must give STATUS (0 a name, 1 not
# a name) for each NAME. One run of the program for all of them.
names_check() {
    local manager="$1" want="$2" name i=0 word
    local -a got
    shift 2
    app_eval "PM=$manager; for n in $(printf '%q ' "$@"); do pm_valid_name \"\$n\"; echo \"\$?\"; done"
    mapfile -t got <<< "$OUT"
    if [ "$want" = 0 ]; then word='is a name'; else word='is not a name'; fi
    for name in "$@"; do
        check_eq "$manager: $(printf '%q' "$name") $word" "$want" "${got[i]:-}"
        i=$((i + 1))
    done
}
APT_NAMES=(firefox libreoffice-core ab 0ad g++ libstdc++6 python3.12 x11-utils lib32z1
    libc6:i386 foo:amd64 libgtk-3-0t64:amd64 gcc-13-base:arm64)
APT_NOT_NAMES=('' a -foo +foo .foo :foo Firefox 'foo bar' 'foo,bar' 'a, b' foo: a:b:c foo:i386:amd64 foo:I386
    foo_bar foo@bar foo/bar 'foo;ls' '$(id)' $'foo\nbar' $'foo\n' --purge -s -- 'foo=1.0' 'foo*' 'foo?' café 日本語)
RPM_NAMES=(firefox Firefox NetworkManager ImageMagick libX11 GConf2 R a perl-Foo-Bar gcc-c++ libstdc++
    foo_bar foo@bar 0ad 9wm python3.12 lib32-foo)
RPM_NOT_NAMES=('' -foo .foo _foo @foo +foo 'foo bar' 'foo,bar' 'a, b' foo:i386 libc6:i386 foo/bar 'foo;ls' '$(id)'
    $'foo\nbar' $'foo\n' --nodeps -s -- 'foo=1' 'foo>=1' 'foo*' 'foo?' café 日本語)
new_sandbox
names_check apt 0 "${APT_NAMES[@]}"
names_check apt 1 "${APT_NOT_NAMES[@]}"
for manager in dnf zypper pacman; do
    names_check "$manager" 0 "${RPM_NAMES[@]}"
    names_check "$manager" 1 "${RPM_NOT_NAMES[@]}"
done
for manager in apt dnf zypper pacman; do
    app_eval "PM=$manager; for n in -s --purge -y -- - -rf -h; do pm_valid_name \"\$n\"; printf '%s ' \"\$?\"; done"
    check_eq "$manager: nothing that looks like an option is a name" '1 1 1 1 1 1 1 ' "$OUT"
done
app_eval 'PM=apt; pm_valid_name café; echo "apt=$?"; PM=dnf; pm_valid_name café; echo "dnf=$?"; pm_valid_name 日本語; echo "ja=$?"' LC_ALL=C.UTF-8
check_eq 'in a UTF-8 locale, letters with accents or of other scripts are not letters of a name' $'apt=1\ndnf=1\nja=1' "$OUT"
for manager in apt dnf zypper pacman; do
    app_eval "PM=$manager; n=\$(printf '%0255d' 0); pm_valid_name \"\$n\"; printf '%s ' \"\$?\"; pm_valid_name \"\${n}0\"; printf '%s' \"\$?\""
    check_eq "$manager: a name of 255 characters passes, one of 256 does not" '0 1' "$OUT"
done
app_eval 'PM=nope; for n in firefox Foo ""; do pm_valid_name "$n"; echo "rc=$?"; done'
check_eq 'a manager without backend: status 2, whatever the name' $'rc=2\nrc=2\nrc=2' "$OUT"

# pmq MANAGER PLAN_NAME...: the names plan_meta_packages asks the manager about, for a plan that removes them.
pmq() {
    local manager="$1"
    shift
    app_eval "PM=$manager; pm_meta_packages() { echo \"asked: \$*\" >&2; }
plan_meta_packages \"\$(printf 'Remv %s [1.0]\\n' $(printf '%q ' "$@"))\""
}
pmq apt libc6:i386 a:b:c foo: Foo bar
check_eq 'plan_meta_packages (apt) asks about the valid names only, a foreign architecture included' 'asked: bar libc6:i386' "$OUT"
pmq dnf NetworkManager libc6:i386 -s foo_bar
check_eq 'plan_meta_packages (dnf) asks about the valid names only, capitals and "_" included' 'asked: NetworkManager foo_bar' "$OUT"
pmq apt -s
check_eq 'a name that looks like an option is never given to the manager' '' "$OUT"
# owned MANAGER OWNER_LINE: what process_desktop_file does with a launcher whose owner line (as pm_owner
# prints it) is that.
owned() {
    app_eval 'PM="$T_PM"; EXCLUDED_PATTERNS=(); CATALOG=(); pm_protected() { return 1; }
f=/x/app.desktop; LAUNCHER_OWNERS[$f]="$T_OWNER"
process_desktop_file "$f"
echo "offered=[${ADV_PACKAGES[*]:-}] unmanaged=[${ADV_UNMANAGED_NAMES[*]:-}]"' T_PM="$1" T_OWNER="$2"
}
OFFER='offered=[foo] unmanaged=[]'
AMBIG='offered=[] unmanaged=[app (ambiguous package)]'
owned apt 'foo: /x/app.desktop'
check_eq 'apt: the owner of the launcher is offered' "$OFFER" "$OUT"
owned apt 'foo:amd64: /x/app.desktop'
check_eq 'apt: the architecture dpkg adds to the owner is dropped' "$OFFER" "$OUT"
for owner in 'foo, bar' Foo a --purge 'foo_bar' '-s'; do
    owned apt "$owner: /x/app.desktop"
    check_eq "apt: the owner '$owner' is ambiguous, so it is never offered" "$AMBIG" "$OUT"
done
owned dnf 'NetworkManager: /x/app.desktop'
check_eq 'dnf: a name with capitals is offered' 'offered=[NetworkManager] unmanaged=[]' "$OUT"
owned pacman 'foo_bar: /x/app.desktop'
check_eq 'pacman: a name with "_" is offered' 'offered=[foo_bar] unmanaged=[]' "$OUT"
for owner in 'foo, bar' --nodeps '-s' 'foo bar'; do
    owned dnf "$owner: /x/app.desktop"
    check_eq "dnf: the owner '$owner' is ambiguous, so it is never offered" "$AMBIG" "$OUT"
done

echo "-- the rest of the program only asks the manager through the pm_* functions (4.6)"
sample=$'a() {\n  from_a\n}\nb() {\n  from_b\n}\nc() {\n  from_c\n}'
check_eq 'control: strip_functions removes the functions it is told to, and only those' $'b() {\n  from_b\n}' "$(strip_functions a c <<< "$sample")"
check_eq 'control: the code has simulate_apt, dpkg-query Status and dpkg -S' 'yes yes yes' \
    "$(at_least_one "$(code_only | count_of 'simulate_apt')") $(at_least_one "$(code_only | count_of 'Status\}')") $(at_least_one "$(code_only | count_of 'dpkg +-S')")"
check_eq 'only pm_simulate asks simulate_apt (its backend)' 0 "$(code_only | strip_functions pm_simulate simulate_apt | count_of 'simulate_apt')"
check_eq 'only pm_installed reads the status of a package' 0 "$(code_only | strip_functions pm_installed | count_of 'Status\}')"
check_eq 'only pm_owner asks dpkg who owns a file' 0 "$(code_only | strip_functions pm_owner | count_of 'dpkg +-S')"
check_eq 'control: the code has dpkg-query' 'yes' "$(at_least_one "$(code_only | count_of 'dpkg-query')")"
check_eq 'only the pm_* functions run dpkg-query' 0 \
    "$(code_only | strip_functions pm_installed pm_meta_packages pm_detail pm_protected pm_residual | count_of 'dpkg-query')"
# Since D7 the patterns list their characters ("[${low}][${low}+..." for apt, "[${any}][${any}+..." for the rest)
# instead of ranges; there is one of each.
NAME_PATTERN='\[\$\{(low|any)\}\]\[\$\{(low|any)\}\+'
check_eq 'control: the code has a pattern for package names (apt, and dnf, zypper and pacman)' '2' \
    "$(code_only | grep -oE "$NAME_PATTERN" | wc -l | tr -d ' ')"
check_eq 'only pm_valid_name knows what a package name looks like' 0 \
    "$(code_only | strip_functions pm_valid_name | count_of "$NAME_PATTERN")"
check_eq 'control: the code has a query to rpm' 'yes' "$(at_least_one "$(code_only | count_of 'rpm +-q')")"
check_eq 'only rpm_installed, rpm_owner, rpm_detail and rpm_meta_packages (the rpm backend) ask rpm' 0 \
    "$(code_only | strip_functions rpm_installed rpm_owner rpm_detail rpm_meta_packages | count_of 'rpm +-q')"

echo "-- the pacman backend: pm_detail, pm_meta_packages and pm_protected (4.6, step 5d)"
# pacman_size_kib: what "pacman -Qi" prints, rounded up to whole KiB; anything else is refused.
qo_reset
qe 'for v in "0.00 B" "1500.00 B" "1.00 KiB" "4.00 KiB" "4.01 KiB" "1536.00 KiB" "1.50 MiB" "1.01 MiB" "4.66 GiB" "1.00 TiB" "1.00 PiB" "1.00 EiB" "12345.00 KiB" "4 KiB" "4.0 KiB" "4.00KiB" "4,00 KiB" "" "-1.00 KiB" "4.08 KiB" "08.00 KiB" "4.09 MiB" "1.01 TiB" "1.01 PiB" "4.00 KiBx" "4.00 KiB "; do if r=$(pacman_size_kib "$v"); then echo "[$v]=$r"; else echo "[$v]=no"; fi; done'
check_eq 'pacman_size_kib: B, KiB, MiB, GiB, TiB and PiB round up to KiB; EiB, 5 digits, other forms and empty are refused' "$(cat <<'EOF'
[0.00 B]=0
[1500.00 B]=2
[1.00 KiB]=1
[4.00 KiB]=4
[4.01 KiB]=5
[1536.00 KiB]=1536
[1.50 MiB]=1536
[1.01 MiB]=1035
[4.66 GiB]=4886365
[1.00 TiB]=1073741824
[1.00 PiB]=1099511627776
[1.00 EiB]=no
[12345.00 KiB]=no
[4 KiB]=no
[4.0 KiB]=no
[4.00KiB]=no
[4,00 KiB]=no
[]=no
[-1.00 KiB]=no
[4.08 KiB]=5
[08.00 KiB]=8
[4.09 MiB]=4189
[1.01 TiB]=1084479243
[1.01 PiB]=1110506744054
[4.00 KiBx]=no
[4.00 KiB ]=no
EOF
)" "$OUT"

# pm_detail
qo_reset
qo_out <<'EOF'
Name            : fixa
Version         : 1.0-1
Description     : the first
Installed Size  : 4.00 KiB
Required By     : None

Name            : fixb
Version         : 2:3.4_5-2
Description     : the second
Installed Size  : 1.50 MiB
Required By     : fixa

Name            : other
Version         : 9-1
Installed Size  : 1.00 KiB

Name            : fixa
Version         : 7-7
Installed Size  : 9.00 KiB

EOF
qe 'pm_detail fixa fixb; echo "rc=$?"'
check_eq 'pm_detail with pacman: one line per package asked (name, version, KiB); one not asked or repeated gives none' $'fixa\t1.0-1\t4\nfixb\t2:3.4_5-2\t1536\nrc=0' "$OUT"
check_eq 'pacman got -Qi, "--" and the names, once, in the C locale' 'pacman -Qi -- fixa fixb|C' "$(pacman_log)|$(pacman_env)"
qo_reset
qo_out <<'EOF'
Name            : fixa
Version         : bad version
Installed Size  : 4.00 KiB

Name            : fixb
Version         : 1-1
Installed Size  : 4 KiB

Name            : fixc
Version         : 1-1
Installed Size  : 0.00 B

EOF
printf '%s\n' 'Name            : fixz' 'Version         : 1-1' 'Installed Size  : 1.00 KiB' '' > "$SB/state/pacman.err"
qe 'pm_detail fixa fixb fixc fixz; echo "rc=$?"'
check_eq 'a block with a version or a size that does not read gives no line; stderr is never read' $'fixc\t1-1\t0\nrc=0' "$OUT"
qo_reset
QO_RC=1
qo_out <<'EOF'
Name            : fixa
Version         : 1.0-1
Installed Size  : 4.00 KiB

EOF
qe 'pm_detail fixa fixc; echo "rc=$?"'
check_eq 'a name pacman does not know: the lines of the others and the status of pacman (1)' $'fixa\t1.0-1\t4\nrc=1' "$OUT"
qo_reset
qe 'pm_detail; echo "rc=$?"'
check_eq 'pm_detail without names: status 2 and pacman is not asked' "rc=2|" "$OUT|$(pacman_log)"
qo_reset
qo_out <<'EOF'
Name            : va
Version         : r123.g1a2b3c4-1
Installed Size  : 1.00 KiB

Name            : vb
Version         : R2-1
Installed Size  : 2.00 KiB

Name            : vc
Version         : 1.0+git~rc1-1
Installed Size  : 3.00 KiB

Name            : vd
Version         : .5-1
Installed Size  : 4.00 KiB

Name            : ve
Version         : -1
Installed Size  : 5.00 KiB

Name            : vf
Version         : ~1-1
Installed Size  : 6.00 KiB

EOF
qe 'pm_detail va vb vc vd ve vf; echo "rc=$?"'
check_eq 'a version that starts with a letter or has + and ~ reads; one that starts with a dot, a dash or a ~ does not' $'va\tr123.g1a2b3c4-1\t1\nvb\tR2-1\t2\nvc\t1.0+git~rc1-1\t3\nrc=0' "$OUT"
qo_reset
qo_out <<'EOF'
Name            : fixa
Name            : zzz
Version         : 1-1
Installed Size  : 1.00 KiB

Name            : fixb
Version         : 2-1
Version         : 8-8
Installed Size  : 2.00 KiB

Name            : fixc
Version         : 3-1
Installed Size  : 3.00 KiB
Installed Size  : 9.00 KiB

Name            : fixd
Version         : 4-1
Description     : Installed Size : 7.00 KiB

Name            : fixe
Description     : Version : 5-1
Installed Size  : 5.00 KiB

Description     : Name : fixf
Version         : 6-1
Installed Size  : 6.00 KiB

EOF
qe 'pm_detail fixa fixb fixc fixd fixe fixf zzz; echo "rc=$?"'
check_eq 'the first Name, Version and Installed Size of a block count; the same words inside another line do not' $'fixa\t1-1\t1\nfixb\t2-1\t2\nfixc\t3-1\t3\nrc=0' "$OUT"

# pm_meta_packages
qo_reset
qo_out <<'EOF'
base: 0 total files, 0 missing files
fixa: 12 total files, 0 missing files
fixb: 0 total files, 0 missing files
other: 0 total files, 0 missing files
fixb: 0 total files, 0 missing files
fixc: 1 total file, 0 missing files
fixd: 10 total files, 0 missing files
EOF
qe 'pm_meta_packages base fixa fixb fixc fixd; echo "rc=$?"'
check_eq 'pm_meta_packages with pacman: only the packages asked that have 0 files, each once' $'base\nfixb\nrc=0' "$OUT"
check_eq 'pacman got -Qk, "--" and the names, once, in the C locale' 'pacman -Qk -- base fixa fixb fixc fixd|C' "$(pacman_log)|$(pacman_env)"
qo_reset
QO_RC=1
printf '%s\n' 'base: 0 total files, 0 missing files' | qo_out
qe 'pm_meta_packages base nope; echo "rc=$?"'
check_eq 'whatever pacman says, the status is 0' $'base\nrc=0' "$OUT"
qo_reset
qe 'pm_meta_packages; echo "rc=$?"'
check_eq 'pm_meta_packages without names: status 2 and pacman is not asked' "rc=2|" "$OUT|$(pacman_log)"
qo_reset
qo_out <<'EOF'
base: 0 total files, 0 missing files
warning: fixa: 0 total files, 0 missing files
fixb: 0 total files, 0 missing files, 3 more
fixc: 0 total files, 0 missing files
EOF
printf '%s\n' 'fixz: 0 total files, 0 missing files' > "$SB/state/pacman.err"
qe 'pm_meta_packages base fixa fixb fixc fixz; echo "rc=$?"'
check_eq 'a row is exactly "NAME: 0 total files, M missing files": text before or after it does not count; stderr is never read' $'base\nfixc\nrc=0' "$OUT"
qo_reset
QO_RC=1
printf '%s\n' 'base: 0 total files, 0 missing files' | qo_out
qe 'set -e; pm_meta_packages base nope; echo "rc=$?"'
check_eq 'pacman failing does not end a shell that has set -e' $'base\nrc=0' "$OUT"

# pm_protected
qo_reset
_stub pacman-conf <<'EOF'
#!/bin/sh
S='@STATE@'
echo "pacman-conf $*" >> "$S/conf.log"
echo "${LC_ALL-unset}" >> "$S/conf.env"
cat "$S/conf.err" >&2 2>/dev/null
cat "$S/conf.out" 2>/dev/null
exit "${FAKE_CONF_RC:-0}"
EOF
printf '%s\n' pacman glibc 'lib*-base' 'my?pkg' '[xy]hold' > "$SB/state/conf.out"
qe 'for p in pacman glibc libfoo-base lib-base libfoo mypkg myXpkg xhold yhold zhold pacman-contrib glibc2; do pm_protected "$p"; echo "$p=$?"; done'
check_eq 'pm_protected with pacman: HoldPkg patterns are globs (*, ? and [..]) that match the whole name' $'pacman=0\nglibc=0\nlibfoo-base=0\nlib-base=0\nlibfoo=1\nmypkg=1\nmyXpkg=0\nxhold=0\nyhold=0\nzhold=1\npacman-contrib=1\nglibc2=1' "$OUT"
check_eq 'pacman-conf got HoldPkg and ran in the C locale; pacman itself was not asked' 'pacman-conf HoldPkg|C|' "$(head -n1 "$SB/state/conf.log")|$(head -n1 "$SB/state/conf.env")|$(pacman_log)"
qe 'pm_protected ""; echo "rc=$?"'
check_eq 'an empty name is not protected' 'rc=1' "$OUT"
: > "$SB/state/conf.out"
qe 'pm_protected pacman; echo "rc=$?"'
check_eq 'an empty HoldPkg protects nothing' 'rc=1' "$OUT"
printf '%s\n' pacman > "$SB/state/conf.out"
qe 'pm_protected pacman; echo "rc=$?"' FAKE_CONF_RC=1
check_eq 'pacman-conf fails: status 2 (the list is unknown, so is_excluded_package protects)' 'rc=2' "$OUT"

printf '%s\n' pacman > "$SB/state/conf.out"
printf '%s\n' evil > "$SB/state/conf.err"
qe 'pm_protected evil; echo "rc=$?"'
check_eq 'what pacman-conf writes on stderr is never read as a pattern' 'rc=1' "$OUT"
rm -f "$SB/state/conf.err"
printf '%s\n' '*' > "$SB/state/conf.out"
qe 'pm_protected anything; echo "rc=$?"; pm_protected ""; echo "rc=$?"'
check_eq 'a "*" pattern protects every name but an empty one' $'rc=0\nrc=1' "$OUT"

# The consumers, with pacman: they read what the three functions print.
printf '%s\n' pacman glibc > "$SB/state/conf.out"
qe 'EXCLUDED_PATTERNS=(); for p in glibc nano; do if is_excluded_package "$p"; then echo "$p: excluded"; else echo "$p: offered"; fi; done'
check_eq 'is_excluded_package with pacman: a HoldPkg package is excluded and another is offered' $'glibc: excluded\nnano: offered' "$OUT"
qe 'EXCLUDED_PATTERNS=(); if is_excluded_package nano; then echo "nano: excluded"; else echo "nano: offered"; fi' FAKE_CONF_RC=1
check_eq 'pacman-conf fails, so what is protected is unknown: is_excluded_package excludes' 'nano: excluded' "$OUT"
qo_reset
qo_out <<'EOF'
Name            : fixa
Version         : 1.0-1
Installed Size  : 4.00 KiB

Name            : fixb
Version         : 2:3.4_5-2
Installed Size  : 1.50 MiB

EOF
qe 'load_package_detail fixa fixb; echo "$DETAIL_MAIN|$DETAIL_VERSION|$DETAIL_EXTRA|$DETAIL_SIZE"'
check_eq 'load_package_detail with pacman: first package, its version, how many more and the sum of the KiB' 'fixa|1.0-1|1|1540' "$OUT"
qo_reset
qo_out <<'EOF'
base: 0 total files, 0 missing files
fixa: 0 total files, 0 missing files
fixb: 12 total files, 0 missing files
EOF
qe 'plan_meta_packages "$(printf "%s\n" "Remv fixb [1-1]" "Remv base [3-2]" "Remv fixa [1.0-1]")" fixa; echo "rc=$?"'
check_eq 'plan_meta_packages with pacman: what the plan removes beyond the request, if pacman files it as a meta-package' $'base\nrc=0' "$OUT"
check_eq 'and it asked pacman once, not about what was requested' 'pacman -Qk -- base fixb' "$(pacman_log)"

check_eq 'control: the code has questions to pacman (-Q...)' 'yes' "$(at_least_one "$(code_only | count_of 'pacman +-Q')")"
check_eq 'only the pacman backend asks pacman -Q (and pm_operation_text writes it in the records)' 0 \
    "$(code_only | strip_functions pacman_orphans pacman_installed pacman_owned_lines pacman_detail pacman_meta_packages pm_operation_text | count_of 'pacman +-Q')"

echo "-- the pacman backend against the real pacman, on a fake root (4.6, step 5f)"
# The backend as a whole (pm_installed, pm_owner, pm_detail, pm_meta_packages, pm_protected, pm_simulate,
# pm_run and what calls them) with the real pacman on a fake root (RootDir, DBPath, CacheDir, LogFile, GPGDir
# and HookDir of a pacman.conf, SigLevel = Never): a folder with a few synthetic packages, built by hand
# (.PKGINFO and files, with their folders, as makepkg makes them) and installed with "pacman -U --noscriptlet",
# so nothing of the system is read or written. Queries and plans (--print) need no rights and run as the
# unprivileged user, as the program does; what changes the root goes through sudo -n where the tests are not
# root. pacman -Qo only knows the paths under RootDir: its wrapper adds it to the paths asked and takes it out
# of the answer, which is what a chroot would do. The cases are skipped where pacman, pacman-conf or those
# rights are missing; with CI defined that is a failure. Packages (1.0-1), installed in the root at once, so
# fixlib is a dependency (--asdeps):
#   fixlib   lib.txt (1 file)                      fixapp   fixapp.desktop and app.bin; 1500 B; requires fixlib
#   fixdep   dep.txt; 3072 B; requires fixapp      fixmeta  no files (a meta-package); requires fixlib
#   fixsolo  solo.txt; 5000000 B (nobody needs it) pacman   9.9-1, not installed: the cases about HoldPkg add it
PACFX="$H_TMP/pacfx"
PAC_BIN="$(command -v pacman 2> /dev/null || true)"
PACCONF_BIN="$(command -v pacman-conf 2> /dev/null || true)"
# pac_as_root COMMAND...: as root; through the real sudo (not the stub of the sandbox) if the tests are not root.
pac_as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else "$SUDO_BIN" -n "$@"; fi; }
# pac_chown PATH: gives back to the user what root wrote (so the harness can delete it).
pac_chown() { if [ "$(id -u)" -ne 0 ]; then pac_as_root chown -R "$(id -u):$(id -g)" "$1"; fi; }
# pac_write_conf ROOT FILE [HOLDPKG]: the pacman.conf of a fake root.
pac_write_conf() {
    printf '[options]\nRootDir = %s\nDBPath = %s/var/lib/pacman\nCacheDir = %s/var/cache/pacman/pkg\nLogFile = %s/var/log/pacman.log\nGPGDir = %s/etc/pacman.d/gnupg\nHookDir = %s/etc/pacman.d/hooks\nHoldPkg = %s\nArchitecture = auto\nSigLevel = Never\nLocalFileSigLevel = Never\n' \
        "$1" "$1" "$1" "$1" "$1" "$1" "${3-pacman glibc}" > "$2"
}
# mkpac NAME VERSION SIZE DEPENDS PATH[:BYTES]...: a package in $PACFX/pkgs (BYTES of "x", 10 by default; SIZE is
# what pacman calls the installed size, whatever the files weigh).
mkpac() {
    local name="$1" ver="$2" size="$3" deps="$4" d f p n x
    shift 4
    d="$PACFX/build/$name"
    mkdir -p "$d" "$PACFX/pkgs" || return 1
    { printf 'pkgname = %s\npkgver = %s\npkgdesc = fixture\narch = any\nsize = %s\n' "$name" "$ver" "$size"
      for x in $deps; do printf 'depend = %s\n' "$x"; done; } > "$d/.PKGINFO"
    for f in "$@"; do
        p="${f%%:*}"; n="${f#*:}"; [ "$n" != "$f" ] || n=10
        mkdir -p "$d$(dirname "$p")" && head -c "$n" /dev/zero | tr '\0' x > "$d$p" || return 1
    done
    (cd "$d" && find . -mindepth 1 -printf '%P\n' | LC_ALL=C sort | tar --no-recursion -czf "$PACFX/pkgs/$name-$ver-any.pkg.tar.gz" -T -)
}
# build_pacman_fixture: the packages and the fake root, once. Fails if anything needed is missing.
build_pacman_fixture() {
    local root="$PACFX/fake/root" conf="$PACFX/fake/pacman.conf" p="$PACFX/pkgs"
    [ -n "$PAC_BIN" ] && [ -n "$PACCONF_BIN" ] || return 1
    [ "$(id -u)" -eq 0 ] || { [ -n "$SUDO_BIN" ] && "$SUDO_BIN" -n true > /dev/null 2>&1; } || return 1
    mkdir -p "$root/var/lib/pacman/sync" "$root/var/cache/pacman/pkg" "$root/var/log" "$root/etc/pacman.d/gnupg" "$root/etc/pacman.d/hooks" || return 1
    mkpac fixlib 1.0-1 0 '' /usr/share/fixlib/lib.txt || return 1
    mkpac fixapp 1.0-1 1500 fixlib /usr/share/applications/fixapp.desktop /usr/share/fixapp/app.bin:2049 || return 1
    mkpac fixdep 1.0-1 3072 fixapp /usr/share/fixdep/dep.txt || return 1
    mkpac fixmeta 1.0-1 0 fixlib || return 1
    mkpac fixsolo 1.0-1 5000000 '' /usr/share/fixsolo/solo.txt || return 1
    mkpac pacman 9.9-1 0 '' /usr/share/fakepacman/x || return 1
    pac_write_conf "$root" "$conf"
    pac_as_root env LC_ALL=C "$PAC_BIN" --config "$conf" -U --noscriptlet --noconfirm \
        "$p/fixlib-1.0-1-any.pkg.tar.gz" "$p/fixapp-1.0-1-any.pkg.tar.gz" "$p/fixdep-1.0-1-any.pkg.tar.gz" \
        "$p/fixmeta-1.0-1-any.pkg.tar.gz" "$p/fixsolo-1.0-1-any.pkg.tar.gz" > "$PACFX/install.log" 2>&1 \
        || { pac_chown "$PACFX"; return 1; }
    pac_as_root env LC_ALL=C "$PAC_BIN" --config "$conf" -D --asdeps fixlib >> "$PACFX/install.log" 2>&1 \
        || { pac_chown "$PACFX"; return 1; }
    pac_chown "$PACFX"
    [ "$(LC_ALL=C "$PAC_BIN" --config "$conf" -Q 2> /dev/null | wc -l)" -eq 5 ]
}
# pf_sandbox [HOLDPKG]: a new sandbox with its own copy of the fake root, and a pacman and a pacman-conf that are
# the real ones working on it. Only what changes the root asks for rights (not -Q... or --print).
pf_sandbox() {
    local as=""
    new_sandbox
    cp -a "$PACFX/fake" "$SB/state/pfake"
    pac_write_conf "$SB/state/pfake/root" "$SB/state/pfake/pacman.conf" "$@"
    if [ "$(id -u)" -ne 0 ]; then as="$SUDO_BIN -n"; fi
    sed -e "s|@PAC@|$PAC_BIN|g" -e "s|@AS@|$as|g" <<'EOF' | _stub pacman
#!/bin/sh
S='@STATE@/pfake'; R="$S/root"; AS='@AS@'
case "${1-}" in -Q*) AS='' ;; *) case " $* " in *" --print "*) AS='' ;; esac ;; esac
if [ "${1-}" = -Qo ] && [ "${2-}" = -- ]; then
    shift 2; n=$#
    while [ "$n" -gt 0 ]; do a="$1"; shift; case "$a" in /*) a="$R$a" ;; esac; set -- "$@" "$a"; n=$((n - 1)); done
    out=$(LC_ALL="${LC_ALL:-C}" '@PAC@' --config "$S/pacman.conf" -Qo -- "$@"); rc=$?
    [ -z "$out" ] || printf '%s\n' "$out" | sed "s|^$R||"
    exit "$rc"
fi
# shellcheck disable=SC2086
exec $AS env LC_ALL="${LC_ALL:-C}" '@PAC@' --config "$S/pacman.conf" "$@"
EOF
    sed -e "s|@CONF@|$PACCONF_BIN|g" <<'EOF' | _stub pacman-conf
#!/bin/sh
exec '@CONF@' --config '@STATE@/pfake/pacman.conf' "$@"
EOF
}
# pf_eval CODE [VAR=val...]: CODE of the program with PM=pacman, in the current sandbox, as the unprivileged user.
pf_eval() { app_eval "PM=pacman; $1" "${@:2}"; }
# pf_root_eval CODE [VAR=val...]: the same with the rights of the removals (root where the tests are root).
pf_root_eval() { H_AS_ROOT=1 app_eval "PM=pacman; $1" "${@:2}"; pac_chown "$SB"; }
# pf_present NAME...: "NAME=0" if the package is installed in the fake root of the sandbox, "NAME=1" if not.
pf_present() { local n code=''; for n in "$@"; do code+="pm_installed $n; echo \"$n=\$?\"; "; done; pf_eval "$code"; }

if build_pacman_fixture; then
    pf_sandbox
    pf_eval 'pacman --version | grep -o "Pacman v[0-9.]*"; pacman -Q | sort'
    assert_contains 'control: the pacman of the sandbox is the real one' "$OUT" 'Pacman v'
    assert_contains 'control: and it sees the fake root (five packages, not the ones of the machine)' "$OUT" $'fixapp 1.0-1\nfixdep 1.0-1\nfixlib 1.0-1\nfixmeta 1.0-1\nfixsolo 1.0-1'
    pf_eval 'pacman -Qdtq; echo "rc=$?"'
    check_eq 'control: fixlib is a dependency that fixapp needs, so it is not an orphan' 'rc=1' "$OUT"
    pf_present fixapp fixlib fixsolo nosuch
    check_eq 'pm_installed: the packages of the root, with their dependency, and one that is not there' \
        $'fixapp=0\nfixlib=0\nfixsolo=0\nnosuch=1' "$OUT"
    pf_eval 'pm_owner /usr/share/applications/fixapp.desktop /usr/share/fixlib/lib.txt /usr/share/nobody.txt /usr/share/fixlib; echo "rc=$?"'
    check_eq 'pm_owner: the owner of each path, a folder too, none for the path nobody owns' \
        $'fixapp: /usr/share/applications/fixapp.desktop\nfixlib: /usr/share/fixlib/lib.txt\nfixlib: /usr/share/fixlib\nrc=0' "$OUT"
    pf_eval 'pm_detail fixapp fixlib fixdep fixsolo nosuch; echo "rc=$?"'
    check_eq 'pm_detail: version and KiB (1500 B print as 1.46 KiB: 2; 4.77 MiB: 4885), no line for a package that is not there, the status of pacman' \
        $'fixapp\t1.0-1\t2\nfixlib\t1.0-1\t0\nfixdep\t1.0-1\t3\nfixsolo\t1.0-1\t4885\nrc=1' "$OUT"
    pf_eval 'pm_meta_packages fixapp fixmeta fixlib fixsolo nosuch; echo "rc=$?"'
    check_eq 'pm_meta_packages: only the package with no files' $'fixmeta\nrc=0' "$OUT"
    pf_eval 'pm_protected fixapp; echo "fixapp=$?"; pm_protected pacman; echo "pacman=$?"'
    check_eq 'pm_protected: pacman is in HoldPkg, a package of the root is not' $'fixapp=1\npacman=0' "$OUT"

    # The plan: what the real pacman prints for a simulated removal (--print), read by pacman_read_plan, with no
    # rights. Nothing is removed. pacman prints what depends on a package first and the package last.
    sim() { pf_eval "pm_simulate $1; echo \"rc=\$?\"; echo \"\$PLAN_OUTPUT\""; }
    sim 'purge fixsolo'
    check_eq 'pm_simulate purge: one package nobody needs' $'rc=0\nRemv fixsolo [1.0-1]' "$OUT"
    sim 'purge fixapp'
    check_eq 'pm_simulate purge: what depends on the package first, the package last' $'rc=0\nRemv fixdep [1.0-1]\nRemv fixapp [1.0-1]' "$OUT"
    sim 'purge fixlib'
    check_eq 'pm_simulate purge: a library that three packages need takes all of them (sorted here: the order is pacman'"'"'s)' \
        $'Remv fixapp [1.0-1]\nRemv fixdep [1.0-1]\nRemv fixlib [1.0-1]\nRemv fixmeta [1.0-1]\nrc=0' "$(LC_ALL=C sort <<< "$OUT")"
    sim 'purge fixmeta'
    check_eq 'pm_simulate purge: a dependency that fixapp still needs stays' $'rc=0\nRemv fixmeta [1.0-1]' "$OUT"
    sim 'purge fixapp fixmeta'
    check_eq 'pm_simulate purge: two packages asked, each once, with what depends on them' \
        $'Remv fixapp [1.0-1]\nRemv fixdep [1.0-1]\nRemv fixmeta [1.0-1]\nrc=0' "$(LC_ALL=C sort <<< "$OUT")"
    sim 'purge fixsolo nosuch'
    assert_contains 'pm_simulate purge: a name pacman does not know invalidates the whole plan (status 1)' "$OUT" 'rc=1'
    assert_contains 'and the error says which name' "$OUT" 'target not found: nosuch'
    assert_not_contains 'and no row of the plan is offered, not even for the name that exists' "$OUT" 'Remv '
    sim 'purge nosuch'
    assert_contains 'pm_simulate purge: a name that matches nothing is an error (status 1)' "$OUT" 'rc=1'
    assert_not_contains 'and there is no plan' "$OUT" 'Remv '
    sim 'autoremove'
    check_eq 'pm_simulate autoremove: no orphans is status 0 and an empty plan' 'rc=0' "$OUT"
    pf_eval 'pm_simulate purge fixlib; plan_meta_packages "$PLAN_OUTPUT" fixlib; echo "rc=$?"'
    check_eq 'plan_meta_packages with the real pacman: of what the plan removes beyond the request, the one that has no files' $'fixmeta\nrc=0' "$OUT"
    pf_eval 'load_package_detail fixapp fixsolo; echo "$DETAIL_MAIN|$DETAIL_VERSION|$DETAIL_EXTRA|$DETAIL_SIZE"'
    check_eq 'load_package_detail with the real pacman: first package, its version, how many more and the sum of the KiB' 'fixapp|1.0-1|1|4887' "$OUT"
    pf_present fixapp fixdep fixlib fixmeta fixsolo
    check_eq 'the simulations changed nothing in the root' $'fixapp=0\nfixdep=0\nfixlib=0\nfixmeta=0\nfixsolo=0' "$OUT"
    pf_root_eval 'pm_simulate purge fixapp; plan="$PLAN_OUTPUT"; plan_still_valid "$plan" purge fixapp; echo "same=$?"
pacman -Rdd --noconfirm fixdep > /dev/null 2>&1; plan_still_valid "$plan" purge fixapp; echo "after=$?"'
    check_eq 'plan_still_valid with the real pacman: the same plan holds; if the root changed, it does not' $'same=0\nafter=1' "$OUT"

    # A package pacman protects (HoldPkg): the program also hides it (pm_protected) and pacman refuses it, in the
    # plan and in the removal (it asks, and with --noconfirm the answer is no).
    pf_sandbox
    "$SB/bin/pacman" -U --noscriptlet --noconfirm "$PACFX/pkgs/pacman-9.9-1-any.pkg.tar.gz" > /dev/null 2>&1 || true
    pac_chown "$SB"
    sim 'purge pacman'
    assert_contains 'a package of HoldPkg: the plan is an error (status 1)' "$OUT" 'rc=1'
    assert_contains 'and pacman says why' "$OUT" 'HoldPkg was found in target list'
    assert_not_contains 'and there is no plan' "$OUT" 'Remv '
    sim 'purge fixsolo pacman'
    assert_contains 'a package of HoldPkg in the request: there is no plan for the others either' "$OUT" 'rc=1'
    assert_not_contains 'and nothing to remove is offered' "$OUT" 'Remv '
    pf_root_eval 'pm_protected pacman; echo "program=$?"; pm_run purge fixsolo pacman > /dev/null 2>&1; echo "removal=$?"'
    check_eq 'the program protects it too, and the real removal fails' $'program=0\nremoval=1' "$OUT"
    pf_present pacman fixsolo
    check_eq 'and nothing was removed' $'pacman=0\nfixsolo=0' "$OUT"
    # HoldPkg of the file of pacman, with a glob: pacman protects that list alone; the program reads the same file and
    # the pattern means the same to both.
    pf_sandbox 'fixso*'
    pf_eval 'pm_protected fixsolo; echo "fixsolo=$?"; pm_protected fixapp; echo "fixapp=$?"
EXCLUDED_PATTERNS=(); for p in fixsolo fixapp; do if is_excluded_package "$p"; then echo "$p: excluded"; else echo "$p: offered"; fi; done'
    check_eq 'HoldPkg = fixso*: the program protects fixsolo and not fixapp, and is_excluded_package follows' $'fixsolo=0\nfixapp=1\nfixsolo: excluded\nfixapp: offered' "$OUT"
    sim 'purge fixsolo'
    assert_contains 'HoldPkg = fixso*: pacman refuses what the pattern matches, as the program does' "$OUT" 'HoldPkg was found in target list'
    sim 'purge fixapp'
    check_eq 'HoldPkg = fixso*: and gives the plan of what it does not' $'rc=0\nRemv fixdep [1.0-1]\nRemv fixapp [1.0-1]' "$OUT"

    # The removals, as the program makes them: with the plan confirmed, through execute_removal.
    pf_sandbox
    pf_root_eval 'pm_simulate purge fixapp; execute_removal "$PLAN_OUTPUT" purge fixapp > /dev/null 2>&1; echo "st=$?"'
    check_eq 'a real removal: the status of pacman' 'st=0' "$OUT"
    check_eq 'a real removal goes through the privilege command: sudo pacman -Rcn --noconfirm with the package' 'sudo pacman -Rcn --noconfirm fixapp' "$(sudo_log | tail -n1)"
    pf_present fixapp fixdep fixlib fixmeta fixsolo
    check_eq 'a real removal: the package and its dependent are gone, nothing else' $'fixapp=1\nfixdep=1\nfixlib=0\nfixmeta=0\nfixsolo=0' "$OUT"
    rec="$(cat "$(state_files | head -n1)")"
    assert_contains 'a real removal: the record says it completed' "$rec" '# Status: completed'
    assert_contains 'a real removal: the record names the operation as pacman runs it' "$rec" '# Operation: pacman -Rcn fixapp'
    assert_contains 'a real removal: and the plan, with the dependent' "$rec" 'Remv fixdep [1.0-1]'
    # autoremove needs a package that nobody uses: -Rdd on every package that needs fixlib leaves it behind as an
    # orphan (a removal with -Rc would take it along, see above).
    pf_sandbox
    pf_root_eval 'pacman -Rdd --noconfirm fixdep fixapp fixmeta > /dev/null 2>&1; pm_simulate autoremove; echo "rc=$?"; echo "$PLAN_OUTPUT"'
    check_eq 'pm_simulate autoremove: the dependency nobody needs now' $'rc=0\nRemv fixlib [1.0-1]' "$OUT"
    pf_root_eval 'pm_simulate autoremove; execute_removal "$PLAN_OUTPUT" autoremove > /dev/null 2>&1; echo "st=$?"'
    check_eq 'a real autoremove: the status of pacman' 'st=0' "$OUT"
    check_eq 'a real autoremove goes through the privilege command: sudo pacman -Rns --noconfirm with the orphans' 'sudo pacman -Rns --noconfirm fixlib' "$(sudo_log | tail -n1)"
    pf_present fixlib fixsolo
    check_eq 'a real autoremove: it removed the orphan and not the package nobody needs' $'fixlib=1\nfixsolo=0' "$OUT"
    pf_root_eval 'pm_run clean > /dev/null 2>&1; echo "st=$?"'
    check_eq 'pm_run clean with the real pacman: "pacman -Sc" works on the fake root (status 0)' 'st=0' "$OUT"
else
    skip_case 'the pacman backend against the real pacman (pacman, pacman-conf or administrator rights not available)'
    [ -z "${CI:-}" ] || check_eq 'CI: pacman and pacman-conf are installed, and the fake root is built' 'built' 'skipped'
fi

echo "-- the password of the plan with dnf, the flows that ask for it, and the texts that name no manager (4.6, step 7)"
# These cases set PM themselves. Only dnf needs administrator rights to calculate a plan (it refuses to simulate without
# them): pm_plan_needs_privileges says so, plan_password_hint warns and plan_authorize gets the rights before pm_simulate,
# so that in windows a cancelled or wrong password is told as that and not as an error of the plan.
new_sandbox
for pair in apt:1 dnf:0 pacman:1 zypper:1 nope:1; do
    app_eval "PM=${pair%%:*}; pm_plan_needs_privileges; echo \"st=\$?\""
    check_eq "pm_plan_needs_privileges with ${pair%%:*}: status ${pair##*:}" "st=${pair##*:}" "$OUT"
done
# fl PM CODE [VAR=val...]: CODE with PM set and what a flow shows or does replaced by stubs that only print what they were
# given: header (nothing), text_wrap (WRAP<text>), show_message (MSG<text>), review_plan (REVIEW; it fails, so the flow stops
# there), priv_authenticate (AUTH; AUTH_RC is its status) and pm_simulate (SIM and its arguments; SIM_RC is its status and
# the plan is "plan-text"). OUT ends with "st=" and the status of CODE.
fl() {
    local pm="$1" code="$2"; shift 2
    app_eval "PM=$pm; header() { :; }; text_wrap() { printf 'WRAP<%s>\\n' \"\$1\"; }; show_message() { printf 'MSG<%s>\\n' \"\$1\"; }
review_plan() { echo REVIEW; return 1; }; priv_authenticate() { echo AUTH; return \${AUTH_RC:-0}; }
pm_simulate() { echo \"SIM \$*\"; PLAN_OUTPUT=plan-text; return \${SIM_RC:-0}; }
$code; echo \"st=\$?\"" "$@"
}
# names_apt TEXT: yes if the text names apt, apt-get or dpkg as a word (the control is the second case).
names_apt() { if grep -qiwE 'apt|apt-get|dpkg' <<< "$1"; then echo yes; else echo no; fi; }
check_eq 'the detector of apt in a text sees it and does not take "adapt" for it' 'yes/no' "$(names_apt 'the plan of apt')/$(names_apt 'adapt the plan')"
# The texts the flows show, read from the program in the same environment: the cases below fix the order and what is
# chosen to show; the wording is fixed by test_i18n.py.
app_eval 'msg plan_calculating'; PCALC="$OUT"
app_eval 'msg cleaning'; CLEANING="$OUT"
app_eval 'msg plan_password_note'; NOTE="$OUT"
app_eval 'msg priv_denied'; DENIED="$OUT"
app_eval 'msgf_v X plan_error plan-text; printf "%s" "$X"'; PERR="$OUT"
app_eval 'msg plan_password_note' MINTAPP_LANG=es; NOTE_ES="$OUT"
check_eq 'the texts that the cases read exist (a missing one would be empty and match anything)' 'yes' "$([ -n "$PCALC" ] && [ -n "$CLEANING" ] && [ -n "$NOTE" ] && [ -n "$DENIED" ] && [ -n "$PERR" ] && echo yes || echo no)"

fl dnf 'plan_password_hint'
check_eq 'plan_password_hint with dnf: tells that the manager may ask for the password' $'WRAP<'"$NOTE"$'>\n\nst=0' "$OUT"
fl dnf 'plan_password_hint' MINTAPP_LANG=es
check_eq 'plan_password_hint with dnf: the same note in Spanish' $'WRAP<'"$NOTE_ES"$'>\n\nst=0' "$OUT"
check_eq 'the note is not the same text in both languages' 'no' "$([ "$NOTE" = "$NOTE_ES" ] && echo yes || echo no)"
for pm in apt pacman zypper; do
    fl "$pm" 'plan_password_hint'
    check_eq "plan_password_hint with $pm: it prints nothing" 'st=0' "$OUT"
done
for pm in apt pacman zypper; do
    fl "$pm" 'plan_authorize' AUTH_RC=77
    check_eq "plan_authorize with $pm: it asks for nothing, even if the rights would be denied" 'st=0' "$OUT"
done
fl dnf 'plan_authorize'
check_eq 'plan_authorize with dnf and the rights: asks once and goes on' $'AUTH\nst=0' "$OUT"
fl dnf 'plan_authorize' AUTH_RC=77
check_eq 'plan_authorize with dnf and no rights: asks once, says so (priv_denied) and gives status 77' $'AUTH\nMSG<'"$DENIED"$'>\nst=77' "$OUT"
fl dnf 'plan_authorize' AUTH_RC=1
check_eq 'plan_authorize with dnf: any failure of the authentication is "no rights" (status 77)' $'AUTH\nMSG<'"$DENIED"$'>\nst=77' "$OUT"

# The flows. confirm_and_purge serves Options 2 and 3; with dnf the rights come before the simulation, and with apt, pacman
# and zypper nothing is asked before the user confirms the plan.
CP='declare -a sel_names=(Firefox) sel_pkgs=(firefox); confirm_and_purge sel_names sel_pkgs'
fl dnf "$CP" AUTH_RC=77
check_eq 'confirm_and_purge with dnf and no rights: the note, the request, the refusal told as that, and no simulation' \
    $'WRAP<'"$PCALC"$'>\n\nWRAP<'"$NOTE"$'>\n\nAUTH\nMSG<'"$DENIED"$'>\nst=77' "$OUT"
check_eq 'confirm_and_purge with dnf and no rights: it shows no error of the plan' 'no' "$([[ "$OUT" == *"$PERR"* ]] && echo yes || echo no)"
fl dnf "$CP" SIM_RC=1
check_eq 'confirm_and_purge with dnf: the rights, then the simulation; its failure is shown as the error of the plan' \
    $'WRAP<'"$PCALC"$'>\n\nWRAP<'"$NOTE"$'>\n\nAUTH\nSIM purge firefox\nMSG<'"$PERR"$'>\nst=0' "$OUT"
check_eq 'confirm_and_purge with dnf: what it shows names no apt or dpkg' 'no' "$(names_apt "$OUT")"
fl dnf "$CP"
check_eq 'confirm_and_purge with dnf and the rights: the plan goes to the review (the stub fails, so the flow stops there)' \
    $'WRAP<'"$PCALC"$'>\n\nWRAP<'"$NOTE"$'>\n\nAUTH\nSIM purge firefox\nREVIEW\nst=1' "$OUT"
for pm in apt pacman zypper; do
    fl "$pm" "$CP" AUTH_RC=77 SIM_RC=1
    check_eq "confirm_and_purge with $pm: no note and no rights before the simulation" \
        $'WRAP<'"$PCALC"$'>\n\nSIM purge firefox\nMSG<'"$PERR"$'>\nst=0' "$OUT"
    check_eq "confirm_and_purge with $pm: what it shows names no apt or dpkg" 'no' "$(names_apt "$OUT")"
done
# clean_system: the same order for the autoremove.
fl dnf 'clean_system' AUTH_RC=77
check_eq 'clean_system with dnf and no rights: the note, the request, the refusal told as that, and no simulation' \
    $'WRAP<'"$CLEANING"$'>\n\nWRAP<'"$NOTE"$'>\n\nAUTH\nMSG<'"$DENIED"$'>\nst=77' "$OUT"
fl dnf 'clean_system' SIM_RC=1
check_eq 'clean_system with dnf: the rights, then the simulation of the autoremove; its failure is the error of the plan' \
    $'WRAP<'"$CLEANING"$'>\n\nWRAP<'"$NOTE"$'>\n\nAUTH\nSIM autoremove\nMSG<'"$PERR"$'>\nst=0' "$OUT"
for pm in apt pacman zypper; do
    fl "$pm" 'clean_system' AUTH_RC=77 SIM_RC=1
    check_eq "clean_system with $pm: the simulation with no rights asked before it" \
        $'WRAP<'"$CLEANING"$'>\n\nSIM autoremove\nMSG<'"$PERR"$'>\nst=0' "$OUT"
done
# What the flows show names no manager, with every manager and in both languages: the request for the rights and its refusal
# (dnf), the error of the plan (all) and the line of the work in progress. The cases above read these texts from the program
# itself, so a text that named apt would match them anyway: what catches it is names_apt.
for lang in en es; do
    for pm in apt dnf pacman zypper; do
        for flow in confirm_and_purge clean_system; do
            code=clean_system; [ "$flow" != confirm_and_purge ] || code="$CP"
            for vars in 'AUTH_RC=77 SIM_RC=1' 'SIM_RC=1'; do
                # shellcheck disable=SC2086
                fl "$pm" "$code" $vars MINTAPP_LANG="$lang"
                check_eq "$flow with $pm ($vars, $lang): what it shows names no apt or dpkg" 'no' "$(names_apt "$OUT")"
            done
        done
    done
done
# The third caller of pm_simulate is the entry of the residual configuration, which only apt has: with another manager it
# is unavailable before it simulates, so it never asks for the password (apt is the control: it does simulate).
fl apt 'pm_residual() { echo oldpkg; }; CLEAN_ITEM_STATE=""; clean_residual measure; echo "state=$CLEAN_ITEM_STATE"'
check_eq 'clean_residual with apt (control): it simulates the purge of what is left over and asks for no rights' $'SIM purge oldpkg\nstate=\nst=0' "$OUT"
for pm in dnf pacman zypper; do
    fl "$pm" 'CLEAN_ITEM_STATE=""; clean_residual measure; echo "state=$CLEAN_ITEM_STATE"'
    check_eq "clean_residual with $pm: unavailable; no simulation and no password" $'state=unavailable\nst=0' "$OUT"
done
# What names the manager is its own name, the same in both languages (the stores are not packages).
app_eval 'printf "<%s>" "$(origin_label apt)" "$(origin_label dnf)" "$(origin_label pacman)" "$(origin_label zypper)" "$(origin_label flatpak)" "$(origin_label snap)"'
check_eq 'origin_label: the name of each manager as it is, the stores with their proper names' '<apt><dnf><pacman><zypper><Flatpak><Snap>' "$OUT"
# A launcher whose owner is a diversion or not a single valid package is listed with the manager in use as its origin.
app_eval 'msg ambiguous_package'; AMBIG="$OUT"
for pm in apt dnf pacman zypper; do
    for owner in 'pkg-a, pkg-b' 'diversion by foo from'; do
        app_eval "PM=$pm; declare -A LAUNCHER_OWNERS=(); f=\$HOME/ambiguous.desktop; printf '[Desktop Entry]\\nType=Application\\nName=Ambiguous\\n' > \"\$f\"
LAUNCHER_OWNERS[\$f]='$owner'; ADV_UNMANAGED_NAMES=(); ADV_UNMANAGED_ORIGINS=(); process_desktop_file \"\$f\"; unmanaged_lines"
        check_eq "the unmanaged list shows [$pm] for a launcher with an ambiguous owner ($owner)" "  - Ambiguous ($AMBIG) [$pm]\\n" "$OUT"
        [ "$pm" = apt ] || check_eq "the unmanaged list with $pm and an ambiguous owner ($owner): it names no apt" 'no' "$(names_apt "$OUT")"
    done
done

echo "-- the zypper backend: pm_run, pm_tool and the texts of the records (4.6, step 6a)"
# These cases call the functions of the zypper backend, not pm_detect, so they set PM themselves.
# zr CODE [VAR=val...]: CODE with PM=zypper and a privilege command that only says what it was given
# (PR_RC is its status); OUT ends with "st=" and the status of CODE.
zr() { app_eval "PM=zypper; priv_run() { echo \"PR \$*\"; return \${PR_RC:-0}; }; $1; echo \"st=\$?\"" "${@:2}"; }
# zypper_replay: a zypper that logs its arguments (zypper.log, one line per call) and its LC_ALL (zypper.env)
# and replays files: for "packages", zypper.unneeded with the status FAKE_UNNEEDED_RC; for anything else,
# zypper.out on stdout and zypper.err on stderr with the status FAKE_ZYPPER_RC.
zypper_replay() {
    _stub zypper <<'EOF'
#!/bin/sh
S='@STATE@'
echo "zypper $*" >> "$S/zypper.log"
echo "${LC_ALL-unset}" >> "$S/zypper.env"
for a in "$@"; do
    if [ "$a" = packages ]; then cat "$S/zypper.unneeded" 2>/dev/null; exit "${FAKE_UNNEEDED_RC:-0}"; fi
done
cat "$S/zypper.out" 2>/dev/null
cat "$S/zypper.err" >&2 2>/dev/null
exit "${FAKE_ZYPPER_RC:-0}"
EOF
}
zy_out() { cat > "$SB/state/zypper.out"; }
zy_unn() { cat > "$SB/state/zypper.unneeded"; }
zypper_log() { cat "$SB/state/zypper.log" 2>/dev/null || true; }
zypper_env() { cat "$SB/state/zypper.env" 2>/dev/null || true; }
# zy_table NAME...: what "zypper packages --unneeded" prints (measured with zypper 1.14.68) for those packages.
zy_table() {
    printf '%s\n' 'Loading repository data...' 'Warning: No repositories defined. Operating only with the installed resolvables. Nothing can be installed.' 'Reading installed packages...'
    if [ "$#" -eq 0 ]; then echo 'No packages found.'; return; fi
    printf '%s\n' 'S | Repository | Name  | Version | Arch' '--+------------+-------+---------+-------'
    local n
    for n in "$@"; do printf 'i | @System    | %s | 1.0-1   | noarch\n' "$n"; done
}
new_sandbox
zypper_replay
zr 'pm_run purge firefox vlc' PR_RC=7
check_eq 'zypper, purge: remove with the packages, non-interactive, with privileges, and its status' $'PR zypper --non-interactive remove firefox vlc\nst=7' "$OUT"
zr 'pm_run clean'
check_eq 'zypper, clean: zypper clean, non-interactive' $'PR zypper --non-interactive clean\nst=0' "$OUT"
zr 'pm_run clean foo bar'
check_eq 'zypper, clean: it takes no names, so it gets none' $'PR zypper --non-interactive clean\nst=0' "$OUT"
zy_table fixorph fixlib | zy_unn
zr 'pm_run autoremove'
check_eq 'zypper, autoremove: the unneeded packages go to remove --clean-deps' $'PR zypper --non-interactive remove --clean-deps fixorph fixlib\nst=0' "$OUT"
check_eq 'zypper, autoremove: the unneeded packages are asked with "packages --unneeded", and nothing else is asked' \
    'zypper --non-interactive --no-color packages --unneeded' "$(zypper_log)"
check_eq 'zypper, autoremove: the question runs in the C locale' 'C' "$(zypper_env)"
zr 'pm_run autoremove' PR_RC=5
check_eq 'zypper, autoremove: the status of the removal is the status of pm_run' $'PR zypper --non-interactive remove --clean-deps fixorph fixlib\nst=5' "$OUT"
zy_table | zy_unn
zr 'pm_run autoremove'
check_eq 'zypper, autoremove with nothing unneeded: nothing runs, status 0' 'st=0' "$OUT"
zy_table fixorph | zy_unn
zr 'pm_run autoremove' FAKE_UNNEEDED_RC=1
check_eq 'zypper, autoremove: if the question fails nothing runs and the status is 1' 'st=1' "$OUT"
zr 'pm_run install firefox'
check_eq 'zypper: an action that is not generic is refused (status 2, nothing runs)' 'st=2' "$OUT"
app_eval 'PM=zypper; pm_tool; echo; pm_operation_text "purge foo bar"; echo; pm_operation_text purge; echo; pm_operation_text autoremove; echo; pm_operation_text clean; echo; pm_operation_text "clean x"; echo; pm_operation_text "purgex foo"; echo; pm_install_text; echo'
check_eq 'zypper: the texts of the records (purge is "remove", autoremove says what it removes, clean is "zypper clean" and keeps what follows it)' \
    $'zypper\nzypper remove foo bar\nzypper remove\nzypper remove --clean-deps (the unneeded packages)\nzypper clean\nzypper clean x\nzypper purgex foo\nzypper install' "$OUT"
app_eval 'PM=zypper; pm_interrupt_hint'
check_eq 'zypper: the hint of an interrupted run, with sudo by default' '# If zypper reports a broken state, start with: sudo zypper verify' "$OUT"
app_eval 'PM=zypper; PRIV_CMD=/usr/bin/doas; pm_interrupt_hint'
check_eq 'zypper: the hint names the privilege command in use' '# If zypper reports a broken state, start with: doas zypper verify' "$OUT"
plan=$'Remv foo\nRemv bar'
app_eval "PM=zypper; PRIV_CMD=/usr/bin/doas; write_removal_record \"\$HOME/rec.txt\" 'interrupted (SIGTERM)' $(printf '%q' "$plan") 'purge foo bar'; cat \"\$HOME/rec.txt\""
rec="$OUT"
assert_contains 'a zypper record: the operation' "$rec" '# Operation: zypper remove foo bar'
assert_contains 'a zypper record: the hint of the interrupted run' "$rec" 'start with: doas zypper verify'
assert_contains 'a zypper record: the reinstall line' "$rec" '# doas zypper install'
app_eval 'PM=zypper; pm_plan_needs_privileges; echo "st=$?"'
check_eq 'zypper simulates without administrator rights, like apt and pacman (pm_plan_needs_privileges fails)' 'st=1' "$OUT"
app_eval 'PM=zypper; pm_residual; echo "st=$?"'
check_eq 'zypper has no state of residual configuration (pm_residual: status 2)' 'st=2' "$OUT"
app_eval 'PM=zypper; for n in foo Foo_bar+x.y@z libc6 -opt "a b"; do pm_valid_name "$n" && echo "ok:$n" || echo "no:$n"; done'
check_eq 'zypper: pm_valid_name takes rpm names (capitals, "_", "+", "." and "@") and nothing that looks like an option' $'ok:foo\nok:Foo_bar+x.y@z\nok:libc6\nno:-opt\nno:a b' "$OUT"

echo "-- the zypper backend: pm_simulate (4.6, step 6b)"
# The fixtures have the shape of what zypper 1.14.68 printed on a fake root in the C locale, with
# "--non-interactive --no-color remove --dry-run": the section of the packages to remove, the summary and the prompt that
# --non-interactive answers by itself (the status is 0); an unknown name ends with 104 and a locked package with 4.
UNREADABLE_ZYPPER_EN='Could not read the plan of zypper: its output does not have the expected format. Nothing was changed.'
ZY_RC=0
ZY_UNN_RC=0
zy_reset() { new_sandbox; zypper_replay; ZY_RC=0; ZY_UNN_RC=0; }
zy_eval() { app_eval "PM=zypper; $1" FAKE_ZYPPER_RC="$ZY_RC" FAKE_UNNEEDED_RC="$ZY_UNN_RC" "${@:2}"; }
# simzy ARG...: pm_simulate with those arguments, starting from an old plan. OUT: "st=STATUS" and then the plan between < and >.
simzy() { zy_eval "PLAN_OUTPUT=stale; pm_simulate $(printf '%q ' "$@"); echo \"st=\$?\"; printf '<%s>\\n' \"\$PLAN_OUTPUT\""; }
zy_unreadable() { check_eq "$1" $'st=1\n<'"$UNREADABLE_ZYPPER_EN"'>' "$OUT"; }
# zy_plan HEADER NAMES SUMMARY: the text of a plan (NAMES is the list line, without its two spaces).
zy_plan() { printf '%s\n' 'Reading installed packages...' 'Resolving package dependencies...' '' "$1" "  $2" '' "$3" 'After the operation, 11.0 B will be freed.' 'Continue? [y/n/v/...? shows all options] (y): y'; }

zy_reset
zy_plan 'The following 2 packages are going to be REMOVED:' 'zbase zdep' '2 packages to remove.' | zy_out
simzy purge zbase
check_eq 'purge with a dependent: both names, as rows "Remv NAME"; status 0' $'st=0\n<Remv zbase\nRemv zdep>' "$OUT"
check_eq 'purge: zypper got --non-interactive --no-color remove --dry-run and the name' 'zypper --non-interactive --no-color remove --dry-run zbase' "$(zypper_log)"
check_eq 'purge: zypper ran in the C locale' 'C' "$(zypper_env)"
check_eq 'purge: and no privileges were asked' '' "$(sudo_log)"
simzy purge zbase zlone
check_eq 'purge of two packages: both names reach zypper, in order' 'zypper --non-interactive --no-color remove --dry-run zbase zlone' "$(zypper_log | tail -n1)"
zy_reset
zy_plan 'The following package is going to be REMOVED:' 'zlone' '1 package to remove.' | zy_out
simzy purge zlone
check_eq 'one package: the singular header and summary are read' $'st=0\n<Remv zlone>' "$OUT"
zy_reset
printf '%s\n' 'The following 3 packages are going to be REMOVED:' '  fix-a fix_b+x' '  Fix.c@d' '' '3 packages to remove.' | zy_out
simzy purge fix-a
check_eq 'a list that zypper wrapped on several lines: the names of all of them, with "_", "+", "." and "@" and capitals' $'st=0\n<Remv fix-a\nRemv fix_b+x\nRemv Fix.c@d>' "$OUT"
zy_reset
ZY_RC=104
printf '%s\n' 'Reading installed packages...' "'nosuch' not found in package names. Trying capabilities." "No provider of 'nosuch' found." 'Resolving package dependencies...' 'Nothing to do.' | zy_out
simzy purge nosuch
check_eq 'a name zypper does not know (104): its status and its text, never a plan' $'st=104\n<Reading installed packages...\n'"'nosuch' not found in package names. Trying capabilities."$'\nNo provider of '"'nosuch'"$' found.\nResolving package dependencies...\nNothing to do.>' "$OUT"
zy_reset
ZY_RC=104
{ zy_plan 'The following package is going to be REMOVED:' 'zlone' '1 package to remove.'; echo 'Installation has completed with error.'; } | zy_out
printf '%s\n' "'nosuch' not found in package names. Trying capabilities." > "$SB/state/zypper.err"
simzy purge zlone nosuch
check_eq 'a partial match (104, with a plan for the name that matched): an error, the plan is not offered' $'st=104' "$(head -n1 <<< "$OUT")"
assert_not_contains 'a partial match: no row of a plan' "$OUT" 'Remv '
zy_reset
ZY_RC=4
printf '%s\n' 'Problem: conflicting requests' ' Solution 1: do not ask to delete all solvables providing zlone.noarch = 1.0-1' ' Solution 2: remove lock to allow removal of zlone-1.0-1.noarch' '' 'Choose from above solutions by number or cancel [1/2/c/d/?] (c): c' | zy_out
simzy purge zlone
check_eq 'a locked package (4): its status, the text of zypper in the first line' $'st=4\n<Problem: conflicting requests' "$(head -n2 <<< "$OUT")"
zy_reset
ZY_RC=7
simzy purge zlone
check_eq 'a failure of zypper without any text: its status and the message of an unreadable plan' $'st=7\n<'"$UNREADABLE_ZYPPER_EN"'>' "$OUT"
zy_reset
ZY_RC=7
printf '%s\n' 'System management is locked by the application with pid 4242 (zypper).' 'Close this application before trying again.' > "$SB/state/zypper.err"
simzy purge zlone
check_eq 'what zypper writes on stderr (here the lock another zypper holds, status 7) is part of the error' $'st=7\n<System management is locked by the application with pid 4242 (zypper).\nClose this application before trying again.>' "$OUT"
zy_reset
zy_eval 'simulate_zypper install foo; echo "st=$?"'
check_eq 'simulate_zypper itself refuses an action that is not purge or autoremove (status 2)' 'st=2' "$OUT"
check_eq 'and it runs nothing' '' "$(zypper_log)"
zy_reset
printf '%s\n' 'Reading installed packages...' 'Resolving package dependencies...' 'Nothing to do.' | zy_out
simzy purge zlone
zy_unreadable 'status 0 but no plan ("Nothing to do."): unreadable, never an empty plan'
zy_reset
simzy purge zlone
zy_unreadable 'status 0 and no output at all: unreadable'
# Plans that are not what they look like: each one makes it unreadable, so the program offers to remove nothing.
zy_bad() { # LABEL then the lines of the output
    local label="$1"; shift
    zy_reset
    printf '%s\n' "$@" | zy_out
    simzy purge zlone
    zy_unreadable "$label"
}
zy_bad 'a header with more names than its list has' 'The following 3 packages are going to be REMOVED:' '  zbase zdep' '' '3 packages to remove.'
zy_bad 'a header with fewer names than its list has' 'The following 2 packages are going to be REMOVED:' '  zbase zdep zlone' '' '2 packages to remove.'
zy_bad 'a summary that does not repeat the count' 'The following 2 packages are going to be REMOVED:' '  zbase zdep' '' '3 packages to remove.'
zy_bad 'no summary' 'The following 2 packages are going to be REMOVED:' '  zbase zdep'
zy_bad 'a header without names' 'The following package is going to be REMOVED:' '' '1 package to remove.'
zy_bad 'a name that is not a package name (it starts with "-")' 'The following package is going to be REMOVED:' '  -rf' '' '1 package to remove.'
zy_bad 'a name that is not a package name (it has ":")' 'The following package is going to be REMOVED:' '  a:b' '' '1 package to remove.'
zy_bad 'two sections of removals' 'The following package is going to be REMOVED:' '  zbase' '' 'The following package is going to be REMOVED:' '  zdep' '' '2 packages to remove.'
zy_bad 'a section of installs next to the removals' 'The following package is going to be REMOVED:' '  zbase' '' 'The following NEW package is going to be installed:' '  other' '' '1 package to remove.'
zy_bad 'a section of upgrades next to the removals' 'The following package is going to be REMOVED:' '  zbase' '' 'The following package is going to be upgraded:' '  other' '' '1 package to remove.'
zy_bad 'a control character in the text (ESC)' 'The following package is going to be REMOVED:' $'  zbase\e[0m' '' '1 package to remove.'
zy_bad 'a list outside any section' '  zbase zdep' '' '2 packages to remove.'
zy_bad 'a header with text before it' 'Note: The following package is going to be REMOVED:' '  zbase' '' '1 package to remove.'
zy_bad 'a header with text after it' 'The following package is going to be REMOVED: zbase' '  zbase' '' '1 package to remove.'
zy_bad 'a summary with text before it' 'The following package is going to be REMOVED:' '  zbase' '' 'There is 1 package to remove.'
zy_bad 'a summary with text after it' 'The following package is going to be REMOVED:' '  zbase' '' '1 package to remove. Continue?'
zy_bad 'a name that is not a package name beside a valid one (the count of one would hold without it)' 'The following package is going to be REMOVED:' '  zbase -rf' '' '1 package to remove.'
zy_bad 'a list line indented with one space is not a list line' 'The following package is going to be REMOVED:' ' zbase' '' '1 package to remove.'
zy_bad 'a list line indented with three spaces is not a list line' 'The following package is going to be REMOVED:' '   zbase' '' '1 package to remove.'
zy_bad 'two sections of removals whose names add up to the count of the last one' 'The following 2 packages are going to be REMOVED:' '  zbase zdep' '' 'The following 4 packages are going to be REMOVED:' '  zlone zx' '' '4 packages to remove.'
zy_bad 'a control character in a line of progress (ESC)' $'Reading installed packages\e[0m...' 'The following package is going to be REMOVED:' '  zbase' '' '1 package to remove.'
# What is not a name is skipped: the names are the ones under the header, up to the first blank line or line that is not of the list.
zy_reset
printf '%s\n' 'The following package is going to be REMOVED:' '  zbase' '' '  zdep' '' '1 package to remove.' | zy_out
simzy purge zbase
check_eq 'an indented line after the blank line that ends the list is not a name' $'st=0\n<Remv zbase>' "$OUT"
zy_reset
printf '%s\n' 'The following package is going to be REMOVED:' '  zbase' 'Resolving package dependencies...' '  zdep' '' '1 package to remove.' | zy_out
simzy purge zbase
check_eq 'an indented line after a line that is not of the list is not a name either' $'st=0\n<Remv zbase>' "$OUT"
zy_reset
printf '%s\n' 'The following package is going to be REMOVED:' '  zbase' '1 package to remove.' | zy_out
simzy purge zbase
check_eq 'the summary right after the list, with no blank line between, is still the summary' $'st=0\n<Remv zbase>' "$OUT"
zy_reset
zy_eval 'zypper_read_plan 0 < <(printf "%s\n%s\n\n%s" "The following package is going to be REMOVED:" "  zbase" "1 package to remove."); echo "st=$?"; printf "<%s>\n" "$PLAN_OUTPUT"'
check_eq 'zypper_read_plan reads what it is given as it comes: a last line with no line end counts' $'st=0\n<Remv zbase>' "$OUT"
zy_reset
printf '%s\n' 'The following 0 packages are going to be REMOVED:' '' '0 packages to remove.' | zy_out
simzy purge zlone
zy_unreadable 'a plan of zero packages is no plan'
# autoremove: the unneeded packages decide.
zy_reset
zy_table fixorph fixlib | zy_unn
zy_plan 'The following 2 packages are going to be REMOVED:' 'fixorph fixlib' '2 packages to remove.' | zy_out
simzy autoremove ignored arguments
check_eq 'autoremove: the plan of the unneeded packages; its own arguments are ignored' $'st=0\n<Remv fixorph\nRemv fixlib>' "$OUT"
check_eq 'autoremove: first the question, then remove --dry-run --clean-deps with those names (and not the arguments)' \
    $'zypper --non-interactive --no-color packages --unneeded\nzypper --non-interactive --no-color remove --dry-run --clean-deps fixorph fixlib' "$(zypper_log)"
check_eq 'autoremove: both calls ran in the C locale' $'C\nC' "$(zypper_env)"
zy_reset
zy_table | zy_unn
simzy autoremove
check_eq 'autoremove with nothing unneeded: status 0, an empty plan, and zypper is not asked for a removal' $'st=0\n<>' "$OUT"
check_eq 'autoremove with nothing unneeded: only the question was asked' 'zypper --non-interactive --no-color packages --unneeded' "$(zypper_log)"
zy_reset
ZY_UNN_RC=1
zy_table fixorph | zy_unn
simzy autoremove
zy_unreadable 'autoremove, the question fails: unreadable, and no removal is simulated'
check_eq 'autoremove, the question fails: only the question was asked' 'zypper --non-interactive --no-color packages --unneeded' "$(zypper_log)"
simzy install foo
check_eq 'an action that is not purge or autoremove: status 2 and an empty plan, nothing runs' $'st=2\n<>' "$OUT"
# zypper_unneeded: the rows of the table
zy_unneeded() { zy_eval 'zypper_unneeded; echo "st=$?"; printf "<%s>\n" "${ZYPPER_UNNEEDED[*]-}"'; }
zy_reset
zy_table fixa fixb fixa | zy_unn
zy_unneeded
check_eq 'zypper_unneeded: the names of the rows, once each (a package of two architectures has two rows)' $'st=0\n<fixa fixb>' "$OUT"
zy_reset
zy_table | zy_unn
zy_unneeded
check_eq 'zypper_unneeded: "No packages found." is status 0 and an empty list' $'st=0\n<>' "$OUT"
zy_reset
{ zy_table fixa; printf 'i+ | @System    | fixb | 1.0-1   | noarch\n'; } | zy_unn
zy_unneeded
check_eq 'zypper_unneeded: a package the user asked for ("i+") is a row too' $'st=0\n<fixa fixb>' "$OUT"
zy_bad_rows() { # LABEL ROW: a table with that row after a good one
    zy_reset
    { zy_table fixa; printf '%s\n' "$2"; } | zy_unn
    zy_unneeded
    check_eq "$1" $'st=1\n<>' "$OUT"
}
zy_bad_rows 'zypper_unneeded: a row of a repository that is not @System makes the whole answer untrusted' 'i | repo-one    | fixb | 1.0-1   | noarch'
zy_bad_rows 'zypper_unneeded: a state that is not an installed package makes it untrusted' 'v | @System    | fixb | 1.0-1   | noarch'
zy_bad_rows 'zypper_unneeded: a name that is not a package name makes it untrusted' 'i | @System    | -bad | 1.0-1   | noarch'
zy_bad_rows 'zypper_unneeded: a row with a column more makes it untrusted' 'i | @System    | fixb | 1.0-1   | noarch | extra'
zy_bad_rows 'zypper_unneeded: a row with a column less makes it untrusted' 'i | @System    | fixb'
zy_reset
ZY_UNN_RC=104
zy_table fixa | zy_unn
zy_unneeded
check_eq 'zypper_unneeded: if zypper fails the list is empty and the status 1' $'st=1\n<>' "$OUT"
# The consumers of the plan read it as they read the one of apt.
zy_reset
zy_plan 'The following 2 packages are going to be REMOVED:' 'zbase zdep' '2 packages to remove.' | zy_out
zy_eval 'pm_simulate purge zbase; plan_has_removals "$PLAN_OUTPUT"; echo "has=$?"; plan_package_names "$PLAN_OUTPUT"; plan_fingerprint "$PLAN_OUTPUT" >/dev/null'
check_eq 'the consumers of the plan: plan_has_removals and plan_package_names read the rows of zypper' $'has=0\nzbase zdep ' "$OUT"
zy_eval 'pm_simulate purge zbase; first="$PLAN_OUTPUT"; plan_still_valid "$first" purge zbase; echo "same=$?"; plan_still_valid "Remv other" purge zbase; echo "other=$?"'
check_eq 'plan_still_valid with zypper: the same plan is valid and another one is not' $'same=0\nother=1' "$OUT"

echo "-- the zypper backend: pm_installed, pm_owner, pm_detail, pm_meta_packages and pm_protected (4.6, steps 6c and 6d)"
# With zypper these ask rpm: the cases against the real rpm are those of step 4c and 4d; here only that the dispatch goes to it.
new_sandbox
app_eval 'rpm_installed() { echo "RI $*"; }; rpm_owner() { echo "RO $*"; }; rpm_detail() { echo "RD $*"; }; rpm_meta_packages() { echo "RM $*"; }
PM=zypper; pm_installed foo; pm_owner /a /b; pm_detail x y; pm_meta_packages p q'
check_eq 'zypper: pm_installed, pm_owner, pm_detail and pm_meta_packages are the rpm ones' $'RI foo\nRO /a /b\nRD x y\nRM p q' "$OUT"
# The locks of zypper (measured: "zypper addlock NAME" writes a block of four lines and a blank line).
zy_lock() { # PROTECTED-CHECKS: writes $HOME/locks from stdin and shows the status of zypper_protected for each name given
    local names="$1"
    cat > "$SB/home/locks" 2> /dev/null || { mkdir -p "$SB/home"; cat > "$SB/home/locks"; }
    app_eval "PM=zypper; ZYPPER_LOCKS=\$HOME/locks; for n in $names; do pm_protected \$n; echo \"\$n=\$?\"; done"
}
new_sandbox
zy_lock 'fixlock fixlock2 other' < <(printf '%s\n' 'type: package' 'match_type: glob' 'case_sensitive: on' 'solvable_name: fixlock' '')
check_eq 'zypper_protected: a lock on a name protects it, and only it' $'fixlock=0\nfixlock2=1\nother=1' "$OUT"
zy_lock 'kernel-default kernel-default-base kernel-xen' < <(printf '%s\n' 'type: package' 'match_type: glob' 'case_sensitive: on' 'solvable_name: kernel-default*' '')
check_eq 'zypper_protected: a glob lock protects what matches' $'kernel-default=0\nkernel-default-base=0\nkernel-xen=1' "$OUT"
zy_lock 'foo* foobar' < <(printf '%s\n' 'type: package' 'match_type: string' 'case_sensitive: on' 'solvable_name: foo*' '')
check_eq 'zypper_protected: a string lock is the exact text, not a pattern (the names here are not asked as globs)' $'foo*=0\nfoobar=1' "$OUT"
zy_lock 'liba libb libc' < <(printf '%s\n' 'type: package' 'match_type: regex' 'case_sensitive: on' 'solvable_name: ^lib(a|b)$' '')
check_eq 'zypper_protected: a regex lock protects what matches' $'liba=0\nlibb=0\nlibc=1' "$OUT"
zy_lock 'fixlock FIXLOCK other' < <(printf '%s\n' 'type: package' 'match_type: string' 'case_sensitive: off' 'solvable_name: FixLock' '')
check_eq 'zypper_protected: case_sensitive off ignores capitals' $'fixlock=0\nFIXLOCK=0\nother=1' "$OUT"
zy_lock 'fixlock FixLock' < <(printf '%s\n' 'type: package' 'match_type: string' 'case_sensitive: on' 'solvable_name: FixLock' '')
check_eq 'zypper_protected: case_sensitive on does not' $'fixlock=1\nFixLock=0' "$OUT"
zy_lock 'fixlock' < <(printf '%s\n' 'type: pattern' 'match_type: glob' 'case_sensitive: on' 'solvable_name: fixlock' '')
check_eq 'zypper_protected: a lock on a pattern (not a package) protects nothing' 'fixlock=1' "$OUT"
zy_lock 'aaa bbb ccc' < <(printf '%s\n' 'type: package' 'match_type: glob' 'solvable_name: aaa' '' 'type: package' 'match_type: glob' 'solvable_name: bbb')
check_eq 'zypper_protected: several locks, and the last block without a blank line after it' $'aaa=0\nbbb=0\nccc=1' "$OUT"
zy_lock 'crlf other' < <(printf 'type: package\r\nmatch_type: glob\r\nsolvable_name: crlf\r\n\r\n')
check_eq 'zypper_protected: a file with CRLF line ends' $'crlf=0\nother=1' "$OUT"
zy_lock 'nopattern x' < <(printf '%s\n' '# zypp locks' '' 'solvable_name: nopattern' '' 'type: package' 'match_type: glob')
check_eq 'zypper_protected: a block without a name, a block with only a name that has no type, and a comment' $'nopattern=0\nx=1' "$OUT"
app_eval 'printf "<%s>" "$ZYPPER_LOCKS"'
check_eq 'zypper_protected: the locks are read from the file zypper keeps them in' '</etc/zypp/locks>' "$OUT"
zy_lock 'fixlock' < <(printf 'type: package \nmatch_type: glob  \nsolvable_name: fixlock \n\n')
check_eq 'zypper_protected: spaces at the end of a value do not matter' 'fixlock=0' "$OUT"
zy_lock 'aaa bbb' < <(printf '%s\n' 'type: package' 'match_type: string' 'solvable_name: aaa' '   ' 'type: package' 'match_type: string' 'solvable_name: bbb' '')
check_eq 'zypper_protected: a line of only spaces ends a block, like an empty one' $'aaa=0\nbbb=0' "$OUT"
zy_lock 'nonl' < <(printf 'type: package\nmatch_type: glob\nsolvable_name: nonl')
check_eq 'zypper_protected: the last line of the file counts even with no line end' 'nonl=0' "$OUT"
zy_lock 'aaa' < <(printf '%s\n' 'type: package' 'type' 'solvable_name: aaa' '')
check_eq 'zypper_protected: a line with no ":" is not a key (one that only says "type" changes nothing)' 'aaa=0' "$OUT"
# Nothing passes from one block to the next: each one starts as a lock on a package, a glob, case sensitive and with no name.
zy_lock 'bbb' < <(printf '%s\n' 'type: pattern' 'solvable_name: aaa' '' 'solvable_name: bbb' '')
check_eq 'zypper_protected: a block with no type is a lock on a package, whatever the block before it was' 'bbb=0' "$OUT"
zy_lock 'barx' < <(printf '%s\n' 'match_type: string' 'solvable_name: foo*' '' 'solvable_name: bar*' '')
check_eq 'zypper_protected: a block with no match_type is a glob, whatever the block before it was' 'barx=0' "$OUT"
zy_lock 'bbb' < <(printf '%s\n' 'match_type: string' 'case_sensitive: off' 'solvable_name: aaa' '' 'match_type: string' 'solvable_name: BBB' '')
check_eq 'zypper_protected: a block with no case_sensitive is case sensitive, whatever the block before it was (and capitals do not stay ignored)' 'bbb=1' "$OUT"
zy_lock 'foo foobar xfoo' < <(printf '%s\n' 'type: package' 'match_type: string' 'solvable_name: foo' '')
check_eq 'zypper_protected: a string lock is the whole name, not a part of it' $'foo=0\nfoobar=1\nxfoo=1' "$OUT"
zy_lock 'foo' < <(printf '%s\n' 'type: package' 'match_type: regex' '')
check_eq 'zypper_protected: a lock with no name protects nothing (an empty regex would match every package)' 'foo=1' "$OUT"
app_eval 'PM=zypper; printf "%s\n" "type: package" "match_type: glob" "solvable_name: *" "" > $HOME/locks-all; ZYPPER_LOCKS=$HOME/locks-all; pm_protected ""; echo "st=$?"; pm_protected foo; echo "st=$?"'
check_eq 'zypper_protected: an empty name is protected by no lock, not even by one on "*" (a name is)' $'st=1\nst=0' "$OUT"
app_eval 'PM=zypper; ZYPPER_LOCKS=$HOME/nofile; pm_protected foo; echo "st=$?"'
check_eq 'zypper_protected: no file of locks is no lock (status 1)' 'st=1' "$OUT"
app_eval 'PM=zypper; mkdir -p $HOME/adir; ZYPPER_LOCKS=$HOME/adir; pm_protected foo; echo "st=$?"'
check_eq 'zypper_protected: a locks path that cannot be read as a file is "unknown" (status 2: it protects)' 'st=2' "$OUT"
app_eval 'PM=zypper; : > $HOME/empty; ZYPPER_LOCKS=$HOME/empty; pm_protected ""; echo "st=$?"; pm_protected foo; echo "st=$?"'
check_eq 'zypper_protected: an empty name and an empty file protect nothing' $'st=1\nst=1' "$OUT"
app_eval 'PM=zypper; ZYPPER_LOCKS=$HOME/locks-none; is_excluded_package fixapp; echo "st=$?"'
check_eq 'is_excluded_package with zypper and no locks: a package that is not protected is not excluded' 'st=1' "$OUT"
printf '%s\n' 'type: package' 'match_type: glob' 'solvable_name: fixlock' '' > "$SB/home/locks"
app_eval 'PM=zypper; ZYPPER_LOCKS=$HOME/locks; is_excluded_package fixlock; echo "st=$?"'
check_eq 'is_excluded_package with zypper: a locked package is excluded (never offered)' 'st=0' "$OUT"

echo "-- the zypper backend against the real zypper, on a fake root (4.6, step 6f)"
# The backend as a whole (pm_installed, pm_owner, pm_detail, pm_meta_packages, pm_protected, pm_simulate,
# pm_run and what calls them) with the real zypper and rpm on a fake root (zypper --root): a folder with a few
# synthetic packages and their database, so nothing of the system is read or written. A plan (remove --dry-run)
# and the list of the unneeded packages need no rights and run as the unprivileged user, as the program does;
# what changes the root goes through "sudo -n" where the tests are not root. The cases are skipped where zypper,
# rpm, rpmbuild or those rights are missing; with CI defined that is a failure. Packages (noarch, 1.0-1), all
# installed in the root; zypper files fixlib as a dependency (AutoInstalled):
#   fixlib   lib.txt                                fixapp  fixapp.desktop and app.bin (2049 bytes); requires fixlib
#   fixdep   dep.txt; requires fixapp               fixmeta no files (a meta-package); requires fixlib
#   fixsolo  solo.txt (nobody needs it)             fixkeep keep.txt (no test removes it: if a removal empties the root, zypper
#                                                   fails to cache the empty database and ends with status 8)
# The rpm of Debian and Ubuntu keeps its database in ~/.rpmdb (inside the root, see 4f): the zypper and the rpm
# of this section get the same HOME, and zypper keeps its cache in the sandbox (--cache-dir).
ZYFX="$H_TMP/zyfx"
ZYPPER_BIN="$(command -v zypper 2> /dev/null || true)"
ZY_HOME="/zyfx-home"
# zy_as_root COMMAND...: as root; through the real sudo (not the stub of the sandbox) if the tests are not root.
zy_as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else "$SUDO_BIN" -n "$@"; fi; }
# zy_chown PATH: gives back to the user what root wrote (so the harness can delete it).
zy_chown() { if [ "$(id -u)" -ne 0 ]; then zy_as_root chown -R "$(id -u):$(id -g)" "$1"; fi; }
# build_zypper_fixture: the packages and the fake root, once. Fails if anything needed is missing.
build_zypper_fixture() {
    local top="$ZYFX/top" root="$ZYFX/fake/root" db
    [ -n "$ZYPPER_BIN" ] && [ -n "$RPM_BIN" ] || return 1
    command -v rpmbuild > /dev/null 2>&1 || return 1
    [ "$(id -u)" -eq 0 ] || { [ -n "$SUDO_BIN" ] && "$SUDO_BIN" -n true > /dev/null 2>&1; } || return 1
    db="$root$ZY_HOME/.rpmdb"
    mkdir -p "$top" "$db" "$root/etc/zypp" "$root/var/lib/zypp" "$ZYFX/fake/cache" || return 1
    MK_TOP="$top" mkrpm noarch fixlib /usr/share/fixlib/lib.txt
    MK_TOP="$top" MK_REQ=fixlib mkrpm noarch fixapp /usr/share/applications/fixapp.desktop z:2049:/usr/share/fixapp/app.bin
    MK_TOP="$top" MK_REQ=fixapp mkrpm noarch fixdep /usr/share/fixdep/dep.txt
    MK_TOP="$top" MK_REQ=fixlib mkrpm noarch fixmeta
    MK_TOP="$top" mkrpm noarch fixsolo /usr/share/fixsolo/solo.txt
    MK_TOP="$top" mkrpm noarch fixkeep /usr/share/fixkeep/keep.txt
    "$RPM_BIN" --dbpath "$db" --initdb 2> /dev/null || return 1
    "$RPM_BIN" --dbpath "$db" -i --justdb --nodeps --noscripts --notriggers --ignorearch --ignoreos --replacefiles \
        "$top"/RPMS/noarch/fix*.rpm > /dev/null 2>&1 || return 1
    printf '%s\n' fixlib > "$root/var/lib/zypp/AutoInstalled"
    [ "$(HOME="$ZY_HOME" "$RPM_BIN" --root "$root" -qa 2> /dev/null | wc -l)" -eq 6 ]
}
# zy_sandbox: a new sandbox with its own copy of the fake root, and a zypper and an rpm that are the real ones
# working on it. Only what changes the root asks for rights (not --dry-run or packages).
zy_sandbox() {
    local as=""
    new_sandbox
    cp -a "$ZYFX/fake" "$SB/state/zfake"
    if [ "$(id -u)" -ne 0 ]; then as="$SUDO_BIN -n"; fi
    sed -e "s|@ZY@|$ZYPPER_BIN|g" -e "s|@AS@|$as|g" -e "s|@HOME@|$ZY_HOME|g" <<'EOF' | _stub zypper
#!/bin/sh
S='@STATE@/zfake'; AS='@AS@'
case " $* " in *" --dry-run "*|*" packages "*) AS='' ;; esac
# shellcheck disable=SC2086
exec $AS env HOME='@HOME@' LC_ALL="${LC_ALL:-C}" '@ZY@' --root "$S/root" --cache-dir "$S/cache" "$@"
EOF
    printf '#!/bin/sh\nexec %s env HOME="%s" "%s" --root "%s/state/zfake/root" "$@"\n' "$as" "$ZY_HOME" "$RPM_BIN" "$SB" > "$SB/bin/rpm"
    chmod 755 "$SB/bin/rpm"
    sandbox_chown
}
# zy_eval CODE [VAR=val...]: CODE of the program with PM=zypper and the locks of the fake root, in the current
# sandbox, as the unprivileged user.
zy_eval() { app_eval "PM=zypper; ZYPPER_LOCKS=\"$SB/state/zfake/root/etc/zypp/locks\"; $1" "${@:2}"; }
# zy_root_eval CODE [VAR=val...]: the same with the rights of the removals (root where the tests are root).
zy_root_eval() { H_AS_ROOT=1 app_eval "PM=zypper; ZYPPER_LOCKS=\"$SB/state/zfake/root/etc/zypp/locks\"; $1" "${@:2}"; zy_chown "$SB"; }
# zy_present NAME...: "NAME=0" if the package is installed in the fake root of the sandbox, "NAME=1" if not.
zy_present() { local n code=''; for n in "$@"; do code+="pm_installed $n; echo \"$n=\$?\"; "; done; zy_eval "$code"; }

if build_zypper_fixture; then
    zy_sandbox
    zy_eval 'zypper --version; rpm -qa | sort'
    assert_contains 'control: the zypper of the sandbox is the real one' "$OUT" 'zypper 1.'
    assert_contains 'control: and its rpm sees the fake root (six packages, not the ones of the machine)' "$OUT" \
        $'fixapp-1.0-1.noarch\nfixdep-1.0-1.noarch\nfixkeep-1.0-1.noarch\nfixlib-1.0-1.noarch\nfixmeta-1.0-1.noarch\nfixsolo-1.0-1.noarch'
    zy_eval 'zypper_unneeded; echo "st=$? [${ZYPPER_UNNEEDED[*]}]"'
    check_eq 'zypper_unneeded: fixlib is a dependency that fixapp needs, so zypper does not file it as unneeded (status 0, none)' 'st=0 []' "$OUT"
    zy_present fixapp fixlib fixsolo nosuch
    check_eq 'pm_installed: the packages of the root, with their dependency, and one that is not there' \
        $'fixapp=0\nfixlib=0\nfixsolo=0\nnosuch=1' "$OUT"
    zy_eval 'pm_owner /usr/share/applications/fixapp.desktop /usr/share/fixlib/lib.txt /usr/share/nobody.txt; echo "rc=$?"'
    check_eq 'pm_owner: the owner of each path, none for the path nobody owns' \
        $'fixapp: /usr/share/applications/fixapp.desktop\nfixlib: /usr/share/fixlib/lib.txt\nrc=0' "$OUT"
    zy_eval 'pm_detail fixapp fixlib nosuch; echo "rc=$?"'
    check_eq 'pm_detail: version and KiB (2049 B: 3), no line for a package that is not there' \
        $'fixapp\t1.0-1\t3\nfixlib\t1.0-1\t0\nrc=1' "$OUT"
    zy_eval 'pm_meta_packages fixapp fixmeta fixlib fixsolo nosuch; echo "rc=$?"'
    check_eq 'pm_meta_packages: only the package with no files' $'fixmeta\nrc=0' "$OUT"
    zy_eval 'pm_protected fixsolo; echo "fixsolo=$?"'
    check_eq 'pm_protected: the root has no file of locks, so nothing is protected' 'fixsolo=1' "$OUT"
    # An unneeded package: zypper files as such what was installed as a dependency (AutoInstalled) and nobody
    # needs now. fixsolo, added to that file, is one from the start; fixlib is the other once nothing needs it.
    printf '%s\n' fixlib fixsolo > "$SB/state/zfake/root/var/lib/zypp/AutoInstalled"
    zy_eval 'zypper_unneeded; echo "st=$? [${ZYPPER_UNNEEDED[*]}]"; zypper --non-interactive --no-color packages --unneeded 2>&1 | grep -c "^i | @System"'
    check_eq 'zypper_unneeded: reads the table of the real zypper; fixlib, still needed by fixapp, is not in it' $'st=0 [fixsolo]\n1' "$OUT"

    # The plan: what the real zypper prints for "remove --dry-run", read by zypper_read_plan, with no rights.
    # Nothing is removed. zypper removes what depends on a package, and not what the package needs.
    sim() { zy_eval "pm_simulate $1; echo \"rc=\$?\"; echo \"\$PLAN_OUTPUT\""; }
    sim 'purge fixsolo'
    check_eq 'pm_simulate purge: one package nobody needs' $'rc=0\nRemv fixsolo' "$OUT"
    sim 'purge fixapp'
    check_eq 'pm_simulate purge: the package and what depends on it' $'Remv fixapp\nRemv fixdep\nrc=0' "$(LC_ALL=C sort <<< "$OUT")"
    sim 'purge fixlib'
    check_eq 'pm_simulate purge: a library that three packages need takes all of them' \
        $'Remv fixapp\nRemv fixdep\nRemv fixlib\nRemv fixmeta\nrc=0' "$(LC_ALL=C sort <<< "$OUT")"
    sim 'purge fixmeta'
    check_eq 'pm_simulate purge: a dependency that fixapp still needs stays (no --clean-deps)' $'rc=0\nRemv fixmeta' "$OUT"
    sim 'purge fixapp fixmeta'
    check_eq 'pm_simulate purge: two packages asked, each once, with what depends on them' \
        $'Remv fixapp\nRemv fixdep\nRemv fixmeta\nrc=0' "$(LC_ALL=C sort <<< "$OUT")"
    sim 'purge fixsolo nosuch'
    assert_contains 'pm_simulate purge: a name zypper does not know invalidates the whole plan (status 104)' "$OUT" 'rc=104'
    assert_contains 'and the error says which name' "$OUT" "'nosuch' not found in package names"
    assert_not_contains 'and no row of the plan is offered, not even for the name that exists' "$OUT" 'Remv '
    sim 'purge nosuch'
    assert_contains 'pm_simulate purge: a name that matches nothing is an error (status 104)' "$OUT" 'rc=104'
    assert_not_contains 'and there is no plan' "$OUT" 'Remv '
    sim 'autoremove'
    check_eq 'pm_simulate autoremove: --clean-deps of what zypper files as unneeded (fixsolo; fixlib stays, fixapp needs it)' $'rc=0\nRemv fixsolo' "$OUT"
    zy_eval 'pm_simulate purge fixlib; plan_meta_packages "$PLAN_OUTPUT" fixlib; echo "rc=$?"'
    check_eq 'plan_meta_packages with the real zypper: of what the plan removes beyond the request, the one that has no files' $'fixmeta\nrc=0' "$OUT"
    zy_eval 'load_package_detail fixapp fixsolo; echo "$DETAIL_MAIN|$DETAIL_VERSION|$DETAIL_EXTRA|$DETAIL_SIZE"'
    check_eq 'load_package_detail with the real zypper: first package, its version, how many more and the sum of the KiB' 'fixapp|1.0-1|1|3' "$OUT"
    zy_present fixapp fixdep fixlib fixmeta fixsolo
    check_eq 'the simulations changed nothing in the root' $'fixapp=0\nfixdep=0\nfixlib=0\nfixmeta=0\nfixsolo=0' "$OUT"
    zy_root_eval 'pm_simulate purge fixapp; plan="$PLAN_OUTPUT"; plan_still_valid "$plan" purge fixapp; echo "same=$?"
zypper --non-interactive remove fixdep > /dev/null 2>&1; plan_still_valid "$plan" purge fixapp; echo "after=$?"'
    check_eq 'plan_still_valid with the real zypper: the same plan holds; if the root changed, it does not' $'same=0\nafter=1' "$OUT"

    # A package zypper protects (a lock): the program also hides it (pm_protected) and zypper refuses it, in the
    # plan and in the removal (it finds a conflict and, with --non-interactive, cancels: status 4).
    zy_sandbox
    zy_root_eval 'zypper addlock fixsolo > /dev/null 2>&1; echo "addlock=$?"; pm_protected fixsolo; echo "fixsolo=$?"; pm_protected fixapp; echo "fixapp=$?"
EXCLUDED_PATTERNS=(); for p in fixsolo fixapp; do if is_excluded_package "$p"; then echo "$p: excluded"; else echo "$p: offered"; fi; done'
    check_eq 'a lock added with the real zypper: the program protects fixsolo and not fixapp, and is_excluded_package follows' \
        $'addlock=0\nfixsolo=0\nfixapp=1\nfixsolo: excluded\nfixapp: offered' "$OUT"
    sim 'purge fixsolo'
    assert_contains 'a locked package: the plan is an error (status 4)' "$OUT" 'rc=4'
    assert_contains 'and zypper says why' "$OUT" 'conflicting requests'
    assert_not_contains 'and there is no plan' "$OUT" 'Remv '
    sim 'purge fixsolo fixapp'
    assert_contains 'a locked package in the request: there is no plan for the others either' "$OUT" 'rc=4'
    assert_not_contains 'and nothing to remove is offered' "$OUT" 'Remv '
    sim 'purge fixapp'
    check_eq 'the lock of another package does not stop this plan' $'Remv fixapp\nRemv fixdep\nrc=0' "$(LC_ALL=C sort <<< "$OUT")"
    zy_root_eval 'pm_run purge fixsolo > /dev/null 2>&1; echo "removal=$?"'
    check_eq 'the real removal of a locked package fails with the status of zypper' 'removal=4' "$OUT"
    zy_present fixsolo
    check_eq 'and nothing was removed' 'fixsolo=0' "$OUT"
    # A lock on a pattern: zypper and the program read "match_type: glob" the same way.
    zy_sandbox
    zy_root_eval 'zypper addlock "fixso*" > /dev/null 2>&1; pm_protected fixsolo; echo "fixsolo=$?"; pm_protected fixapp; echo "fixapp=$?"'
    check_eq 'a lock on fixso*: the program protects fixsolo and not fixapp' $'fixsolo=0\nfixapp=1' "$OUT"
    sim 'purge fixsolo'
    assert_contains 'a lock on fixso*: zypper refuses what the pattern matches, as the program does' "$OUT" 'rc=4'

    # The removals, as the program makes them: with the plan confirmed, through execute_removal.
    zy_sandbox
    zy_root_eval 'pm_simulate purge fixapp; execute_removal "$PLAN_OUTPUT" purge fixapp > /dev/null 2>&1; echo "st=$?"'
    check_eq 'a real removal: the status of zypper' 'st=0' "$OUT"
    check_eq 'a real removal goes through the privilege command: sudo zypper --non-interactive remove with the package' \
        'sudo zypper --non-interactive remove fixapp' "$(sudo_log | tail -n1)"
    zy_present fixapp fixdep fixlib fixmeta fixsolo
    check_eq 'a real removal: the package and what depends on it are gone, nothing else' $'fixapp=1\nfixdep=1\nfixlib=0\nfixmeta=0\nfixsolo=0' "$OUT"
    rec="$(cat "$(state_files | head -n1)")"
    assert_contains 'a real removal: the record says it completed' "$rec" '# Status: completed'
    assert_contains 'a real removal: the record names the operation as zypper runs it' "$rec" '# Operation: zypper remove fixapp'
    assert_contains 'a real removal: and the plan, with the dependent' "$rec" 'Remv fixdep'
    # autoremove takes the chain: with fixlib, fixapp and fixdep filed as dependencies, fixdep is the only package
    # unneeded; once it goes fixapp is not needed either, and --clean-deps takes it along (fixlib stays, fixmeta needs
    # it). The plan has a row that zypper_unneeded did not list.
    zy_sandbox
    printf '%s\n' fixlib fixapp fixdep > "$SB/state/zfake/root/var/lib/zypp/AutoInstalled"
    zy_eval 'zypper_unneeded; echo "st=$? [${ZYPPER_UNNEEDED[*]}]"; pm_simulate autoremove; echo "rc=$?"; echo "$PLAN_OUTPUT"'
    check_eq 'pm_simulate autoremove: one package unneeded, and the plan also has the dependency only it needed (--clean-deps)' \
        $'Remv fixapp\nRemv fixdep\nrc=0\nst=0 [fixdep]' "$(LC_ALL=C sort <<< "$OUT")"
    zy_root_eval 'pm_simulate autoremove; execute_removal "$PLAN_OUTPUT" autoremove > /dev/null 2>&1; echo "st=$?"'
    check_eq 'a real autoremove of the chain: the status of zypper' 'st=0' "$OUT"
    check_eq 'a real autoremove of the chain goes through the privilege command with --clean-deps and the package listed' \
        'sudo zypper --non-interactive remove --clean-deps fixdep' "$(sudo_log | tail -n1)"
    zy_present fixdep fixapp fixlib fixmeta fixsolo
    check_eq 'a real autoremove of the chain: fixdep and fixapp are gone; fixlib, fixmeta and fixsolo stay' \
        $'fixdep=1\nfixapp=1\nfixlib=0\nfixmeta=0\nfixsolo=0' "$OUT"
    # And with two packages unneeded at once: taking away what needs fixlib leaves fixlib and fixsolo.
    zy_sandbox
    printf '%s\n' fixlib fixsolo > "$SB/state/zfake/root/var/lib/zypp/AutoInstalled"
    zy_root_eval 'zypper --non-interactive remove fixdep fixapp fixmeta > /dev/null 2>&1; zypper_unneeded; echo "st=$? n=${#ZYPPER_UNNEEDED[@]}"
pm_simulate autoremove; echo "rc=$?"; echo "$PLAN_OUTPUT"'
    check_eq 'pm_simulate autoremove: the two packages nobody needs now, one row each (sorted here: the order is zypper'"'"'s)' \
        $'Remv fixlib\nRemv fixsolo\nrc=0\nst=0 n=2' "$(LC_ALL=C sort <<< "$OUT")"
    zy_root_eval 'pm_simulate autoremove; execute_removal "$PLAN_OUTPUT" autoremove > /dev/null 2>&1; echo "st=$?"'
    check_eq 'a real autoremove: the status of zypper' 'st=0' "$OUT"
    check_eq 'a real autoremove goes through the privilege command: sudo zypper --non-interactive remove --clean-deps with the packages' \
        'sudo zypper --non-interactive remove --clean-deps fixlib fixsolo' "$(sudo_log | tail -n1)"
    zy_present fixlib fixsolo fixkeep
    check_eq 'a real autoremove: both are gone, and the package nobody asked about stays' $'fixlib=1\nfixsolo=1\nfixkeep=0' "$OUT"
    zy_root_eval 'pm_run clean > /dev/null 2>&1; echo "st=$?"'
    check_eq 'pm_run clean with the real zypper: "zypper clean" works on the fake root (status 0)' 'st=0' "$OUT"
    check_eq 'and it goes through the privilege command: sudo zypper --non-interactive clean' 'sudo zypper --non-interactive clean' "$(sudo_log | tail -n1)"
else
    skip_case 'the zypper backend against the real zypper (zypper, rpm, rpmbuild or administrator rights not available)'
    [ -z "${CI:-}" ] || check_eq 'CI: zypper, rpm and rpmbuild are installed, and the fake root is built' 'built' 'skipped'
fi

finish
