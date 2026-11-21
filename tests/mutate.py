#!/usr/bin/env python3
"""mutate.py - mutation checks of the program (D3): it breaks the program on purpose, one change at a
time, and runs the suite on the broken copy. A mutant that no check notices SURVIVES. A survivor is
either a missing check (add it) or a change that alters nothing the program does (equivalent: say why).

  python3 tests/mutate.py list RANGE...            the mutants of those lines, without running them
  python3 tests/mutate.py run SUITE RANGE... [options]
    SUITE    tests/test_clean.sh (or any bash suite with "-- " sections) or tests/test_i18n.py
    RANGE    A-B (lines of the program), a function name (the lines of its definition) or
             key:NAME[,NAME...] (the text of messages: both languages, changed in wording and form)
    --map F  the map of tests/coverage.sh (map.tsv): each mutant runs only the sections that reach its
             line, one at a time, and stops at the first one that fails; a line that no section reaches
             is UNCOVERED. The sections that caught most mutants so far go first (a resumed campaign
             counts those of its report); the verdict does not depend on the order. Without --map the
             whole suite runs.
    --only IDS   comma-separated mutant ids (from a previous list or report)
    --out F      report, one TSV line per mutant: id, line, operator, result, where, seconds, change.
                 A mutant already in F is not run again (to resume a campaign).
    --timeout N  the most a run may last, in seconds (default 120). A run is cut sooner: after 10 times what
                 the unchanged program needs for that same section, and never before 10 seconds, so a loop
                 costs seconds and a slow section is not cut. A run that is cut counts as caught (a loop) but is
                 marked "(timeout)" in the report and counted apart in the summary: a slow machine gives the
                 same result. Run with no other load and check each one: delete its row from F and run it again
                 with a larger --timeout.
  The program copy is run with MINTAPP_TEST_SCRIPT, which the harness and test_i18n.py both read.
  Before a suite (or a section) is used for the first time it runs on the unchanged program; if that does not
  pass, the campaign stops: a run that cannot pass would count every mutant as caught.
  Results: CAUGHT, SURVIVED, UNCOVERED.
"""
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROGRAM = ROOT / "script" / "MintApp_Remover.sh"
SLOW = 10    # a run is cut after SLOW times the seconds the unchanged program takes on that section ...
FLOOR = 10   # ... and never before FLOOR seconds
SWAPS = {"-eq": "-ne", "-ne": "-eq", "-gt": "-ge", "-ge": "-gt", "-lt": "-le", "-le": "-lt", "-z": "-n", "-n": "-z"}
NOT_STATEMENT = re.compile(
    r"^(if|then|else|elif|fi|for|while|until|do|done|case|esac|function|local|declare|readonly|return|"
    r"break|continue|\}|\{|;;|\)|\(|\[\[|trap)\b|^[}{)(]|^[^\s]*\)\s*$|^\*?[A-Za-z0-9_|*\"'-]*\)")


def code_mask(line):
    """True for each character of the line that is code: outside quotes, comments and escapes."""
    mask = [False] * len(line)
    quote = ""
    i = 0
    while i < len(line):
        c = line[i]
        if quote == "'":
            if c == "'":
                quote = ""
        elif c == "\\":
            i += 1
        elif quote == '"':
            if c == '"':
                quote = ""
        elif c in "'\"":
            quote = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t;"):
            break
        else:
            mask[i] = True
        i += 1
    return mask


def open_state(lines):
    """For each line: "open" if it starts inside a quote or a here-document (no mutants there), "cont" if it
    follows a line that ends in a backslash (mutants, but not its deletion: ":" would join the line before),
    "" otherwise."""
    state, quote, heredoc, cont = [], "", "", False
    for line in lines:
        state.append("open" if quote or heredoc else "cont" if cont else "")
        if heredoc:
            if line.strip() == heredoc:
                heredoc = ""
            continue
        cont = line.rstrip().endswith("\\") and not line.rstrip().endswith("\\\\")
        i = 0
        while i < len(line):
            c = line[i]
            if quote == "'":
                if c == "'":
                    quote = ""
            elif c == "\\":
                i += 1
            elif quote == '"':
                if c == '"':
                    quote = ""
            elif c in "'\"":
                quote = c
            elif c == "#" and (i == 0 or line[i - 1] in " \t;"):
                break
            i += 1
        m = re.search(r"<<-?\s*['\"]?([A-Za-z_]+)['\"]?\s*$", line) if not quote else None
        if m:
            heredoc = m.group(1)
    return state


def mutations(line, keys):
    """The one-line changes of a line of code: (operator, new line)."""
    out = []
    mask = code_mask(line)
    body = line.strip()
    indent = line[: len(line) - len(line.lstrip())]
    if not body or body.startswith("#"):
        return out
    ends = ("\\", "(", "{", "&&", "||", "|", "then", "do", ";;", "else")
    if not NOT_STATEMENT.match(body) and not body.endswith(ends) and "<<" not in body:
        out.append(("del", indent + ":"))
    for m in re.finditer(r"\breturn( [01])?(?=\s*(;|$|\}|&&|\|\|))", line):
        if mask[m.start()]:
            new = "return 1" if (m.group(1) or "").strip() != "1" else "return 0"
            out.append(("ret", line[: m.start()] + new + line[m.end():]))
    for m in re.finditer(r"&&|\|\|", line):
        if mask[m.start()]:
            out.append(("andor", line[: m.start()] + ("||" if m.group() == "&&" else "&&") + line[m.end():]))
    for m in re.finditer(r"(?<![\w$])!\s+(?=[\[a-z_$\"(])", line):
        if mask[m.start()]:
            out.append(("not", line[: m.start()] + line[m.end():]))
    for m in re.finditer(r"\b(if|elif|while)\s+(?!!)", line):
        if mask[m.start()]:
            out.append(("neg", line[: m.end()] + "! " + line[m.end():]))
    for m in re.finditer(r"(?<=\s)(-eq|-ne|-gt|-ge|-lt|-le|-z|-n)(?=\s)", line):
        if mask[m.start()]:
            out.append(("cmp", line[: m.start()] + SWAPS[m.group()] + line[m.end():]))
    for m in re.finditer(r"(?<=\s)(==|!=|=)(?=\s)", line):
        if mask[m.start()] and re.search(r"\[\[?\s", line[: m.start()]):
            new = "!=" if m.group() != "!=" else "=="
            out.append(("eq", line[: m.start()] + new + line[m.end():]))
    for m in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*)=([01])(?![0-9A-Za-z_.])", line):
        if mask[m.start()] and not line[: m.start()].rstrip().endswith("local"):
            out.append(("num", line[: m.start(2)] + ("1" if m.group(2) == "0" else "0") + line[m.end(2):]))
    arm = re.match(r"^(\s*[^\s()]+\)\s+)(.+?)(\s*;;\s*)$", line)
    if arm and arm.group(2) != ":" and mask[len(arm.group(1))]:
        out.append(("arm", arm.group(1) + ":" + arm.group(3)))
    for m in re.finditer(r"\|\|\s*(true|return [01]?)\s*(?=[;&)}]|$)", line):
        if mask[m.start()]:
            out.append(("tail", line[: m.start()].rstrip() + line[m.end():]))
    for m in re.finditer(r"\bmsg\s+([a-z][a-z0-9_]*)", line):
        key = m.group(1)
        if key in keys:
            other = keys[(keys.index(key) + 1) % len(keys)]
            out.append(("msg", line[: m.start(1)] + other + line[m.end(1):]))
    for m in re.finditer(r'"([a-z][a-z_]{1,19})"', line):
        out.append(("lit", line[: m.start(1)] + "zz_" + m.group(1) + line[m.end(1):]))
    seen, uniq = set(), []
    for op, new in out:
        if new != line and new not in seen:
            seen.add(new)
            uniq.append((op, new))
    return uniq


def text_mutations(line, other):
    """Changes of the text of a message of MSG_ES or MSG_EN: (operator, new line). \"other\" is the same
    message in the other language."""
    head, _, rest = line.partition('="')
    value, _, tail = rest.rpartition('"')
    if not _:
        return []
    out = []

    def put(op, new_value):
        if new_value != value:
            out.append((op, f'{head}="{new_value}"{tail}'))

    phrase = re.search(r"gestor de paquetes|package manager", value)
    for name in ("apt", "dnf", "apt-get"):
        if phrase:
            put("names-" + name, value[: phrase.start()] + name + value[phrase.end():])
        else:
            put("names-" + name, re.sub(r"([.:])?$", " " + name + r"\1", value, count=1))
    put("pct-drop", value.replace("%s", "", 1))
    put("pct-add", value + " %s")
    put("end-drop", re.sub(r"[.:?]$", "", value))
    put("end-space", value + " ")
    put("end-nl", value + "\\n")
    put("double-space", value.replace(" ", "  ", 1))
    put("accent", re.sub("[áéíóú]", lambda m: "aeiou"["áéíóú".index(m.group())], value, count=1))
    put("term", re.sub(r"aplicaciones|applications", lambda m: "programas" if m.group() == "aplicaciones" else "programs", value, count=1))
    put("empty", "")
    other_value = other.partition('="')[2].rpartition('"')[0]
    put("other-language", other_value)
    return out


def message_lines(lines, name):
    """The line numbers (1-based) of [name]=\" in each table: the first one is MSG_ES, the second MSG_EN."""
    return [i + 1 for i, l in enumerate(lines) if re.match(r'^\s*\[' + re.escape(name) + r'\]="', l)]


def function_range(lines, name):
    for i, line in enumerate(lines):
        if line.startswith(name + "() {"):
            for j in range(i + 1, len(lines)):
                if lines[j] == "}":
                    return i + 1, j + 1
    sys.exit(f"mutate.py: no function {name} in the program")


def parse_ranges(lines, specs):
    out = []
    for s in specs:
        m = re.fullmatch(r"(\d+)-(\d+)", s)
        out.append((int(m.group(1)), int(m.group(2))) if m else function_range(lines, s))
    return out


def syntax_ok(path):
    return subprocess.run(["bash", "-n", str(path)], capture_output=True).returncode == 0


def generate(specs, only=None):
    text = PROGRAM.read_text(encoding="utf-8")
    lines = text.split("\n")
    keys = re.findall(r'^\s*\[([a-z0-9_]+)\]="', text.split("declare -A MSG_EN=(")[1].split("\n)\n")[0], re.M)
    state = open_state(lines)
    found = []
    with tempfile.TemporaryDirectory() as tmp:
        probe = Path(tmp) / "probe.sh"
        for spec in [x for x in specs if x.startswith("key:")]:
            for name in spec[4:].split(","):
                where = message_lines(lines, name)
                if len(where) != 2:
                    sys.exit(f"mutate.py: [{name}] must be in both tables (found {len(where)})")
                for n, o in ((where[0], where[1]), (where[1], where[0])):
                    for op, new in text_mutations(lines[n - 1], lines[o - 1]):
                        mid = f"{n}:{op}"
                        if only and mid not in only:
                            continue
                        changed = lines[:]
                        changed[n - 1] = new
                        body = "\n".join(changed)
                        probe.write_text(body, encoding="utf-8")
                        if syntax_ok(probe):
                            found.append({"id": mid, "line": n, "op": op, "old": f"[{name}] " + ("ES" if n == where[0] else "EN"), "new": op, "text": body})
        for lo, hi in parse_ranges(lines, [x for x in specs if not x.startswith("key:")]):
            for n in range(lo, hi + 1):
                if state[n - 1] == "open":
                    continue
                counts = {}
                for op, new in mutations(lines[n - 1], keys):
                    if op == "del" and state[n - 1]:
                        continue
                    counts[op] = counts.get(op, 0) + 1
                    mid = f"{n}:{op}{counts[op]}"
                    if only and mid not in only:
                        continue
                    changed = lines[:]
                    changed[n - 1] = new
                    body = "\n".join(changed)
                    probe.write_text(body, encoding="utf-8")
                    if syntax_ok(probe):
                        found.append({"id": mid, "line": n, "op": op, "old": lines[n - 1].strip(), "new": new.strip(), "text": body})
    return found


def load_map(path):
    sections = {}
    for row in Path(path).read_text().splitlines():
        line, _, secs = row.partition("\t")
        sections[int(line)] = [int(s) for s in secs.split()]
    return sections


def run_suite(suite, script, sections, timeout):
    env = dict(os.environ, MINTAPP_TEST_SCRIPT=str(script))
    if sections:
        env.update(ONLY_SECTIONS=str(sections), SECTIONS_SUITE="tests/" + suite.name, BASH_ENV=str(ROOT / "tests" / "sections.sh"))
    cmd = ["python3", str(suite)] if suite.suffix == ".py" else ["bash", "tests/" + suite.name]
    try:
        done = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "caught", "timeout"
    out = done.stdout
    if done.returncode != 0 or re.search(r"^  FAIL", out, re.M) or not re.search(r"^  -- \d+ passed", out, re.M):
        first = re.search(r"^  FAIL  (.*)$", out, re.M)
        return "caught", (first.group(1)[:110] if first else f"status {done.returncode}")
    return "survived", ""


def check_baseline(suite, plain, sections, timeout, passed):
    """The unchanged program must pass what a mutant is run against (once per section, or per suite).
    passed maps each one to the seconds the unchanged program took: the mutants' time limit comes from it."""
    if sections in passed:
        return
    began = time.time()
    result, why = run_suite(suite, plain, sections, timeout)
    if result != "survived":
        sys.exit(f"mutate.py: the unchanged program does not pass {f'section {sections}' if sections else 'the suite'}"
                 f" ({why}); every mutant would count as caught. Fix that first.")
    passed[sections] = time.time() - began


def run_limit(passed, sections, ceiling):
    """Seconds a mutant may take on this section (or suite): SLOW times the unchanged program, FLOOR at least,
    --timeout at most."""
    return min(ceiling, max(FLOOR, int(SLOW * passed[sections]) + 1))


def main(argv):
    if len(argv) < 2 or argv[0] not in ("list", "run"):
        sys.exit(__doc__)
    mode, rest = argv[0], argv[1:]
    suite = None
    if mode == "run":
        suite, rest = Path(rest[0]).resolve(), rest[1:]
    opts = {"--map": None, "--only": None, "--out": None, "--timeout": "120"}
    specs = []
    while rest:
        if rest[0] in opts:
            opts[rest[0]], rest = rest[1], rest[2:]
        else:
            specs.append(rest[0])
            rest = rest[1:]
    if not specs:
        sys.exit("mutate.py: give at least one RANGE")
    only = set(opts["--only"].split(",")) if opts["--only"] else None
    mutants = generate(specs, only)
    if mode == "list":
        for m in mutants:
            print(f"{m['id']}\t{m['old']}\t=>\t{m['new']}")
        print(f"# {len(mutants)} mutants", file=sys.stderr)
        return 0
    coverage = load_map(opts["--map"]) if opts["--map"] else None
    out = Path(opts["--out"]) if opts["--out"] else None
    rows = [r.split("\t") for r in out.read_text().splitlines()] if out and out.exists() else []
    done = set(r[0] for r in rows)
    kills = {}  # section -> mutants it caught (the report of an earlier run counts too)
    for r in rows:
        hit = re.match(r"sec (\d+)\b(?! \(timeout\))", r[4]) if len(r) > 4 and r[3] == "CAUGHT" else None
        if hit:
            kills[int(hit.group(1))] = kills.get(int(hit.group(1)), 0) + 1
    ceiling, tally = int(opts["--timeout"]), {}
    with tempfile.TemporaryDirectory(dir="/dev/shm" if os.path.isdir("/dev/shm") else None) as tmp:
        os.chmod(tmp, 0o755)
        script, plain, passed = Path(tmp) / "mutant.sh", Path(tmp) / "plain.sh", {}
        plain.write_text(PROGRAM.read_text(encoding="utf-8"), encoding="utf-8")
        os.chmod(plain, 0o644)
        for m in mutants:
            if m["id"] in done:
                continue
            script.write_text(m["text"], encoding="utf-8")
            os.chmod(script, 0o644)
            began, where = time.time(), "whole"
            if suite.suffix == ".py" or coverage is None:
                check_baseline(suite, plain, None, ceiling, passed)
                result, why = run_suite(suite, script, None, run_limit(passed, None, ceiling))
            elif not coverage.get(m["line"]):
                result, why, where = "uncovered", "", "-"
            else:
                result, why = "survived", ""
                for sec in sorted(coverage[m["line"]], key=lambda s: (-kills.get(s, 0), s)):
                    check_baseline(suite, plain, sec, ceiling, passed)
                    result, why = run_suite(suite, script, sec, run_limit(passed, sec, ceiling))
                    where = f"sec {sec}"
                    if result == "caught":
                        if why != "timeout":
                            kills[sec] = kills.get(sec, 0) + 1
                        break
                else:
                    where = "secs " + ",".join(map(str, coverage[m["line"]]))
            tally[result] = tally.get(result, 0) + 1
            if why == "timeout":
                tally["timeout"] = tally.get("timeout", 0) + 1
            row = "\t".join([m["id"], str(m["line"]), m["op"], result.upper(), where + (f" ({why})" if why else ""),
                             f"{time.time() - began:.0f}", m["old"] + "  =>  " + m["new"]])
            print(row, flush=True)
            if out:
                with out.open("a", encoding="utf-8") as fh:
                    fh.write(row + "\n")
    print("# " + ", ".join(f"{k.upper()} {v}" for k, v in sorted(tally.items()) if k != "timeout"), file=sys.stderr)
    if tally.get("timeout"):
        print(f"# {tally['timeout']} of the caught ones are timeouts: check each one with no other load", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
