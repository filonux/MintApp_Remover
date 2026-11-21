#!/usr/bin/env python3
"""faults.py - deliberate faults for the security suite and for the robustness section (D5): one change at a
time, made in a copy of the program (P and R) or of the suite's scanner (S), and the suite is run on that copy.
A fault that no check notices SURVIVES: either a check is missing (add it) or the change alters nothing the
suite claims (another suite covers it: say which).

  python3 tests/faults.py list
  python3 tests/faults.py check [--only ID,ID...]
  python3 tests/faults.py run [--only ID,ID...] [--out FILE] [--timeout N]

  P faults change a copy of script/MintApp_Remover.sh, which the suite reads through MINTAPP_TEST_SCRIPT.
  S faults change a copy of tests/test_security.sh, which runs on the real program.
  R faults change a copy of the program as well, but run only the robustness section of tests/test_functions.sh
  (the input ends at every step of a flow). R00 is its control and its baseline: the unchanged copy must pass.
  OLD must occur exactly once in the file (None: NEW is appended to the program); a fault whose text is gone is STALE and is not
  counted: update it. The changed file must still pass bash -n and, in the suite, its scanner must still
  compile as Python (else INVALID: every check would fail and the fault would look caught). "check" makes
  every change without running the suite (about a second): tests/test_suite_quality.sh runs it, so a fault
  cannot go stale unnoticed.
  Before the first fault the unchanged suite must pass, or the campaign stops. An R fault takes about a
  minute and a half (a hang adds 30 s to each flow that ends where it hangs): its limit is 900 s.
  Results: CAUGHT (a check failed), SURVIVED, ABORTED (the suite ended without a failed check or timed
  out: look at it), STALE, INVALID. --out: one TSV line per fault (id, result, where, seconds, what);
  a fault already in FILE is not run again (to resume a campaign).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROGRAM = ROOT / "script" / "MintApp_Remover.sh"
TESTS = ROOT / "tests"
SUITE = TESTS / "test_security.sh"
FUNCTIONS = TESTS / "test_functions.sh"
SECTION_TITLE = 'echo "-- robustness: '
ROBUSTNESS_TIMEOUT = 900

TRAPS = '[ -z "$TUI_SAVED_TRAPS" ] || eval "$TUI_SAVED_TRAPS"'
TEXTS = r'''printf 'MintApp Remover %s\n' "$MINTAPP_VERSION"'''
SCAN_ID = r'''[[ "$raw_id" =~ ^[${ID_LOWER}${ID_DIGIT}._-]+$ ]] && SYS_ID="$raw_id"'''
ASK = '    read -rp "$PROMPT_LAST" answer || return 1'
MENU = '        read -rp "$(text_prompt "$(msg menu_prompt)")" opt || { echo; msgln exit; exit 0; }'
OPEN = '    [ -z "${CLEAN_OPENFILE:-}" ] || rm -f -- "$CLEAN_OPENFILE"'
YESNO = '"${WT_SCROLL[@]+"${WT_SCROLL[@]}"}" --yesno "$WT_TEXT" "$WT_BOX_H" "$WT_BOX_W"'
SCAN_LIKE = r'''[[ "$token" =~ ^[${ID_LOWER}${ID_DIGIT}._-]+$ ]] && SYS_ID_LIKE+="${SYS_ID_LIKE:+ }$token"'''

# (id, what, OLD, NEW)
FAULTS = [
    # --- no network
    ("P01", "a network client in a function", None, "fault_a() { curl -s example.org; }"),
    ("P02", "a URL in a string", None, 'fault_a() { echo "see https://example.org"; }'),
    ("P03", "a /dev/tcp socket", None, "fault_a() { exec 3<>/dev/tcp/127.0.0.1/80; }"),
    ("P04", "a client called by path", None, "fault_a() { /usr/bin/wget -q x; }"),
    ("P05", "--version calls curl through a variable (only a run sees it)", TEXTS,
     'c=cu; c+=rl; "$c" -s localhost > /dev/null 2>&1; ' + TEXTS),
    # --- no text run as code
    ("P06", "a new eval", None, 'fault_a() { eval "$1"; }'),
    ("P07", "a second eval of the saved traps", "    " + TRAPS, "    " + TRAPS + "\n    " + TRAPS),
    ("P08", "TUI_SAVED_TRAPS set from outside", None, 'fault_a() { TUI_SAVED_TRAPS="$1"; }'),
    ("P54", "TUI_SAVED_TRAPS read by another command", None, 'fault_a() { echo "$TUI_SAVED_TRAPS"; }'),
    ("P55", "a second assignment from trap -p", None, 'fault_a() { TUI_SAVED_TRAPS="$(trap -p INT)"; }'),
    ("P56", "TUI_SAVED_TRAPS appended to", None, 'fault_a() { TUI_SAVED_TRAPS+="$1"; }'),
    ("P09", "source", None, 'fault_a() { source "$1"; }'),
    ("P10", "the dot command", None, 'fault_a() { . "$1"; }'),
    # --- administrator rights
    ("P11", "PRIV_CMD called from a new function", None, 'fault_a() { "$PRIV_CMD" -v; }'),
    ("P12", "sudo by name", None, "fault_a() { sudo apt-get update; }"),
    ("P13", "pkexec by name", None, "fault_a() { pkexec env; }"),
    ("P14", "doas by name", None, "fault_a() { doas -n true; }"),
    ("P15", "su by name", None, "fault_a() { su -c true; }"),
    ("P16", "sudo-rs by name", None, "fault_a() { sudo-rs true; }"),
    ("P17", "clean_priv_check stops calling PRIV_CMD", '    "$PRIV_CMD" -v || return "$PRIV_STATUS_DENIED"',
     '    true || return "$PRIV_STATUS_DENIED"'),
    # --- deletions
    ("P18", "a new function that removes", None, 'fault_a() { rm -f -- "$1"; }'),
    ("P19", "rm -rf where only rm -f was", '    rm -f -- "$GUI_WORK_DIR/tries"', '    rm -rf -- "$GUI_WORK_DIR/tries"'),
    ("P20", "--recursive in a known function", """trap '[ -z "$tmp" ] || rm -f -- "$tmp"' EXIT""",
     """trap '[ -z "$tmp" ] || rm --recursive -- "$tmp"' EXIT"""),
    ("P21", "-fr in a known function", '    rm -f -- "$2"\n', '    rm -fr -- "$2"\n'),
    ("P22", "rm without --", '    rm -f -- "$run"', '    rm -f "$run"'),
    ("P23", "find -delete without -maxdepth", "find \"$dir\" -maxdepth 1 -type f -name '.tmp.*' -mmin +60 -delete",
     "find \"$dir\" -type f -name '.tmp.*' -mmin +60 -delete"),
    ("P24", "find -delete without -xdev", 'find "$root" -xdev -mindepth 1', 'find "$root" -mindepth 1'),
    ("P25", "find -delete in a new function", None, 'fault_a() { find "$1" -type f -delete; }'),
    ("P26", "unlink in a new function", None, 'fault_a() { unlink "$1"; }'),
    ("P27", "shred in a new function", None, 'fault_a() { shred -u "$1"; }'),
    ("P28", "rmdir in a new function", None, 'fault_a() { rmdir -- "$1"; }'),
    # --- temporary files
    ("P29", "mktemp in a new function", None, 'fault_a() { mktemp "${TMPDIR:-/tmp}/x.XXXXXX"; }'),
    ("P30", "a template of five X", '"${TMPDIR:-/tmp}/mintapp-zenity.XXXXXX"', '"${TMPDIR:-/tmp}/mintapp-zenity.XXXXX"'),
    ("P31", "mktemp -u", 'mktemp "${TMPDIR:-/tmp}/mintapp-clean.XXXXXX"', 'mktemp -u "${TMPDIR:-/tmp}/mintapp-clean.XXXXXX"'),
    ("P32", "mktemp without a template", 'mktemp -- "$dir/.tmp.XXXXXX"', 'mktemp -- "$dir/.tmp."'),
    # --- hostile names
    ("P33", "ID_LOWER takes an accent", 'ID_LOWER="abcdefghijklmnopqrstuvwxyz"', 'ID_LOWER="abcdefghijklmnopqrstuvwxyzé"'),
    ("P34", "ID_DIGIT takes a superscript", 'ID_DIGIT="0123456789"', 'ID_DIGIT="0123456789²"'),
    ("P35", "ID_UPPER lacks the Z", 'ID_UPPER="ABCDEFGHIJKLMNOPQRSTUVWXYZ"', 'ID_UPPER="ABCDEFGHIJKLMNOPQRSTUVWXY"'),
    ("P36", "is_snap_name with a range", '[[ "$1" =~ ^[${low}]+(-[${low}]+)*$ ]]', '[[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]'),
    ("P37", "apt: no length limit", 'apt) [ "${#1}" -le 255 ] && [[ "$1"', 'apt) [[ "$1"'),
    ("P38", "dnf, zypper, pacman: no length limit", 'dnf|zypper|pacman) [ "${#1}" -le 255 ] && [[ "$1"',
     'dnf|zypper|pacman) [[ "$1"'),
    ("P39", "remote: no length limit", '[ "${#1}" -le 64 ] && [[ "$1" =~ ^[${any}]', '[[ "$1" =~ ^[${any}]'),
    ("P40", "snap: no upper length limit", '[ "${#1}" -ge 2 ] && [ "${#1}" -le 40 ] || return 1', '[ "${#1}" -ge 2 ] || return 1'),
    ("P41", "flatpak ID: no length limit", '[ "${#1}" -le 255 ] && [[ "$1" =~ ^[${first}]', '[[ "$1" =~ ^[${first}]'),
    ("P42", "dnf: no end anchor", '[[ "$1" =~ ^[${any}][${any}+._@-]*$ ]]', '[[ "$1" =~ ^[${any}][${any}+._@-]* ]]'),
    ("P43", "remote: no start anchor", '=~ ^[${any}][${any}._-]*$ ]]', '=~ [${any}][${any}._-]*$ ]]'),
    ("P44", "config_valid: any interface", "interface=terminal|interface=gui) return 0 ;;",
     "interface=terminal|interface=gui|interface=*) return 0 ;;"),
    ("P45", "config_valid: any key with gui", "help_seen=yes|help_seen=no) return 0 ;;", "help_seen=yes|help_seen=no|*=gui) return 0 ;;"),
    ("P46", "config_valid: lowercases", '    case "$1=$2" in\n        interface=terminal', '    case "${1,,}=${2,,}" in\n        interface=terminal'),
    ("P47", "config_valid: drops spaces", '    case "$1=$2" in\n        interface=terminal', '    case "${1// /}=${2// /}" in\n        interface=terminal'),
    # --- detect_system
    ("P48", "ID with a range", SCAN_ID, SCAN_ID.replace("${ID_LOWER}${ID_DIGIT}", "a-z0-9")),
    ("P49", "ID_LIKE with a range", SCAN_LIKE, SCAN_LIKE.replace("${ID_LOWER}${ID_DIGIT}", "a-z0-9")),
    ("P50", "ID not lowered", '    raw_id="${raw_id,,}"\n', ""),
    ("P51", "I not turned into i first", '    raw_id="${raw_id//I/i}" raw_like="${raw_like//I/i}"\n', ""),
    ("P52", "ID taken without a check", SCAN_ID, 'SYS_ID="$raw_id"'),
    ("P53", "ID_LIKE words taken without a check", SCAN_LIKE, 'SYS_ID_LIKE+="${SYS_ID_LIKE:+ }$token"'),
    # --- the scanner of the suite (it must not go blind)
    ("S01", "scanner: wget is no network client", '"curl", "wget", "aria2c"', '"curl", "aria2c"'),
    ("S02", "scanner: /dev/tcp is not a socket", r'''DEVNET = re.compile(r"/dev/(?:tcp|udp)\b")''',
     r'''DEVNET = re.compile(r"/dev/(?:udp)\b")'''),
    ("S03", "scanner: no URL", r'''[A-Za-z][A-Za-z0-9+.-]*://")''', r'''[A-Za-z][A-Za-z0-9+.-]*://zz")'''),
    ("S04", "scanner: eval is not eval", 'EVAL = re.compile(START + "eval" + END)', 'EVAL = re.compile(START + "evaI" + END)'),
    ("S05", "scanner: the dot command is not source", r'''(?:source|\.)\s+\S''', r'''(?:source)\s+\S'''),
    ("S06", "scanner: doas is not a call", "(sudo-rs|sudo|doas|pkexec|su)", "(sudo-rs|sudo|pkexec|su)"),
    ("S07", "scanner: su is not a call", "(sudo-rs|sudo|doas|pkexec|su)", "(sudo-rs|sudo|doas|pkexec)"),
    ("S08", "scanner: sudo-rs is not a call", "(sudo-rs|sudo|doas|pkexec|su)", "(sudo|doas|pkexec|su)"),
    ("S09", "scanner: pkexec is not a call", "(sudo-rs|sudo|doas|pkexec|su)", "(sudo-rs|sudo|doas|su)"),
    ("S10", "scanner: a test of PRIV_CMD is a call", r'''if re.match(r"\s*\]", after.lstrip("}").lstrip('"')):''', "if False:"),
    ("S11", "scanner: ${PRIV_CMD##*/} is a call", 'if after[:1] and after[0] in "#%/:^,@!?+=-":', "if False:"),
    ("S12", "scanner: message-table entries are calls", "if not TEXT_ENTRY.match(text):", "if True:"),
    ("S13", "scanner: comments are code", "return line[:k]", "return line"),
    ("S14", "scanner: continued lines are not joined", 'while text.rstrip().endswith("\\\\") and i + 1 < len(raw):',
     "while False and i + 1 < len(raw):"),
    ("S15", "scanner: unlink does not remove", 'word("rm", "rmdir", "unlink", "shred")', 'word("rm", "rmdir", "shred")'),
    ("S16", "scanner: shred does not remove", 'word("rm", "rmdir", "unlink", "shred")', 'word("rm", "rmdir", "unlink")'),
    ("S17", "scanner: rmdir does not remove", 'word("rm", "rmdir", "unlink", "shred")', 'word("rm", "unlink", "shred")'),
    ("S18", "scanner: --recursive is not recursive", ' or o == "--recursive"', ""),
    ("S19", "scanner: -- is never seen", "dashdash = True", "dashdash = False"),
    ("S20", "scanner: -xdev does not bound a find", r'''\s-(?:xdev|mount|maxdepth)''', r'''\s-(?:mount|maxdepth)'''),
    ("S21", "scanner: -mount does not bound a find", r'''\s-(?:xdev|mount|maxdepth)''', r'''\s-(?:xdev|maxdepth)'''),
    ("S22", "scanner: -u is allowed in mktemp", r''' and not re.search(r"\s-[A-Za-z]*u", rest)''', ""),
    ("S23", "scanner: five X are enough", "X{6,}", "X{5,}"),
    ("S24", "scanner: finds no function", 'print(len({owner for _, owner, _ in rows} - {"-"}))', "print(0)"),
    ("S25", "scanner: a mention that is no known form is not reported", 'found.append("other")', "pass"),
    ("S26", "scanner: a word glued to a form still counts as the form",
     "GLUE = r'''(?![\\w\"'$`\\\\])'''", "GLUE = r'''(?!x)'''"),
    ("S27", "scanner: setting it from trap -p is no known form", "trap -p [A-Z ]+", "trap -q [A-Z ]+"),
    # --- the input ends in the middle of a flow (robustness section of test_functions.sh)
    ("R01", "a confirmation typed without its line break confirms", ASK,
     '    read -rp "$PROMPT_LAST" answer || [ -n "$answer" ] || return 1'),
    ("R02", "the end of input at the question confirms", ASK, '    read -rp "$PROMPT_LAST" answer || return 0'),
    ("R03", "the end of input at the main menu loops: the run does not end", MENU,
     '        read -rp "$(text_prompt "$(msg menu_prompt)")" opt || { echo; }'),
    ("R04", "the end of input at the main menu says a mistyped message (a bash error)", MENU,
     MENU.replace("msgln exit;", "msgln exits;")),
    ("R05", "the end of input at the main menu leaves with status 1", MENU, MENU.replace("exit 0;", "exit 1;")),
    ("R06", "the temporary file of a cleaning measure is not removed", OPEN,
     '    [ -z "${CLEAN_OPENFILE:-}" ] || : "$CLEAN_OPENFILE"'),
    ("R07", "whiptail: Esc at the question confirms", YESNO, YESNO + ' || [ "$?" -eq 255 ]'),
]


def apply(text, old, new):
    """The text with the change, or None if OLD is not there exactly once."""
    if old is None:
        return text.rstrip("\n") + "\n" + new + "\n"
    return text.replace(old, new) if text.count(old) == 1 else None


def section_env(suite):
    """What makes test_functions.sh run only its robustness section (sections.sh); nothing for another suite."""
    if suite != FUNCTIONS:
        return {}
    titles = [x for x in FUNCTIONS.read_text(encoding="utf-8").splitlines() if x.startswith('echo "-- ')]
    for number, line in enumerate(titles, 1):
        if line.startswith(SECTION_TITLE):
            return {"ONLY_SECTIONS": str(number), "SECTIONS_SUITE": str(FUNCTIONS), "BASH_ENV": str(TESTS / "sections.sh")}
    sys.exit("faults.py: tests/test_functions.sh has no robustness section")


def run_suite(suite, program, timeout):
    env = dict(os.environ, MINTAPP_TEST_SCRIPT=str(program), **section_env(suite))
    try:
        p = subprocess.run(["bash", str(suite)], env=env, capture_output=True, text=True, errors="replace",
                           timeout=timeout, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, "timed out"
    out = p.stdout + p.stderr
    fails = [line.strip()[6:].strip() for line in out.splitlines() if line.startswith("  FAIL  ")]
    totals = re.search(r"^  -- (\d+) passed, (\d+) failed", out, re.M)
    return (p.returncode, fails, totals), out


def scanner_of(suite_text):
    """The Python that the suite writes to a file and runs as its scanner (between the heredoc markers)."""
    found = re.search(r"<<'PYEOF'\n(.*?)\nPYEOF\n", suite_text, re.S)
    return found.group(1) if found else None


def prepare(fault, tmp):
    """(program, suite, None) with the change made in a copy under TMP, or (None, None, (verdict, where))."""
    ident, _, old, new = fault
    program, suite = PROGRAM, SUITE
    if ident[0] in "PR":
        changed = apply(PROGRAM.read_text(encoding="utf-8"), old, new)
        program = Path(tmp) / "MintApp_Remover.sh"
    else:
        changed = apply(SUITE.read_text(encoding="utf-8"), old, new)
        (Path(tmp) / "tests").mkdir()
        shutil.copytree(TESTS / "lib", Path(tmp) / "tests" / "lib")
        suite = Path(tmp) / "tests" / "test_security.sh"
    if changed is None:
        return None, None, ("STALE", "the text to change is not there exactly once")
    target = program if ident[0] in "PR" else suite
    target.write_text(changed, encoding="utf-8")
    os.chmod(tmp, 0o755)  # the suite runs the program as another user: it must read the copy
    os.chmod(target, 0o644)
    bad = subprocess.run(["bash", "-n", str(target)], capture_output=True, text=True)
    if bad.returncode != 0:
        return None, None, ("INVALID", bad.stderr.strip()[:100])
    if ident[0] == "S":
        scanner = scanner_of(changed)
        if scanner is None:
            return None, None, ("INVALID", "the suite holds no scanner (heredoc PYEOF)")
        try:
            compile(scanner, "scanner", "exec")
        except SyntaxError as error:
            return None, None, ("INVALID", "the scanner no longer compiles: %s" % error)
    return program, suite, None


def one_fault(fault, timeout):
    """(result, where) of one fault."""
    with tempfile.TemporaryDirectory(prefix="faults.") as tmp:
        program, suite, problem = prepare(fault, tmp)
        if problem:
            return problem
        if fault[0][0] == "R":
            suite, timeout = FUNCTIONS, max(timeout, ROBUSTNESS_TIMEOUT)
        result, out = run_suite(suite, program, timeout)
        if result is None:
            return "ABORTED", out
        status, fails, totals = result
        if fails:
            return "CAUGHT", fails[0][:110]
        if status == 0 and totals and totals.group(2) == "0":
            return "SURVIVED", "-"
        return "ABORTED", "status %s, no failed check" % status


def main(argv):
    if len(argv) < 2 or argv[1] not in ("list", "check", "run"):
        print(__doc__)
        return 2
    only, out_file, timeout = None, None, 300
    args = argv[2:]
    while args:
        flag = args.pop(0)
        if flag == "--only" and args:
            only = set(args.pop(0).split(","))
        elif flag == "--out" and args:
            out_file = Path(args.pop(0))
        elif flag == "--timeout" and args:
            timeout = int(args.pop(0))
        else:
            print("faults.py: unknown option: %s" % flag, file=sys.stderr)
            return 2
    chosen = [f for f in FAULTS if only is None or f[0] in only]
    if argv[1] == "list":
        for ident, what, _, _ in chosen:
            print("%s  %s" % (ident, what))
        return 0
    if argv[1] == "check":
        ids = [f[0] for f in FAULTS]
        problems = ["%s: the id is used twice" % i for i in sorted(set(ids)) if ids.count(i) > 1]
        problems += ["%s: the id is not P, R or S and two digits" % i for i in ids if not re.fullmatch(r"[PRS]\d\d", i)]
        for fault in chosen:
            with tempfile.TemporaryDirectory(prefix="faults.") as tmp:
                problem = prepare(fault, tmp)[2]
            if problem:
                problems.append("%s: %s (%s)" % (fault[0], problem[0], problem[1]))
        for line in problems:
            print("faults.py: " + line)
        if not problems:
            print("faults.py: %d faults, each makes its change and the changed file is valid" % len(chosen))
        return 1 if problems else 0
    done = {}
    if out_file and out_file.exists():
        for line in out_file.read_text(encoding="utf-8").splitlines():
            cells = line.split("\t")
            done[cells[0]] = cells[1]
    # Controls: the unchanged program, and an unchanged copy of the program and of the suite (the copies
    # go through the same path as a fault, so a copy that cannot work would count every fault as caught).
    controls = [("P00", "control: unchanged copy of the program", "    " + TRAPS, "    " + TRAPS),
                ("S00", "control: unchanged copy of the suite", "dashdash = True", "dashdash = True")]
    result, out = run_suite(SUITE, PROGRAM, timeout)
    if result is None or result[0] != 0 or result[1] or not result[2] or result[2].group(2) != "0":
        print("faults.py: the suite does not pass on the unchanged program; the campaign stops.")
        print((out if result is None else "\n".join(result[1])) or "")
        return 1
    if any(f[0][0] == "R" for f in chosen):
        controls.append(("R00", "control: unchanged copy of the program, robustness section", ASK, ASK))
    for control in controls:
        verdict, where = one_fault(control, timeout)
        if verdict != "SURVIVED":
            print("faults.py: %s gave %s (%s); the campaign stops." % (control[0], verdict, where))
            return 1
    count = {}
    for fault in chosen:
        ident, what = fault[0], fault[1]
        if ident in done:
            count[done[ident]] = count.get(done[ident], 0) + 1
            continue
        began = time.time()
        verdict, where = one_fault(fault, timeout)
        count[verdict] = count.get(verdict, 0) + 1
        line = "%s\t%s\t%s\t%d\t%s" % (ident, verdict, where, time.time() - began, what)
        print(line, flush=True)
        if out_file:
            with out_file.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
    print("-- %d faults: %s" % (len(chosen), ", ".join("%d %s" % (n, k) for k, n in sorted(count.items()))))
    return 0 if set(count) <= {"CAUGHT"} else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
