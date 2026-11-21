#!/usr/bin/env python3
"""i18n: the Spanish and English tables and the app catalog stay in sync."""
import os
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# MINTAPP_TEST_SCRIPT=file reads another copy of the program (mutation checks, tests/mutate.py), as the harness does.
TEXT = Path(os.environ.get("MINTAPP_TEST_SCRIPT") or ROOT / "script" / "MintApp_Remover.sh").read_text(encoding="utf-8")
passed = failed = gaps = 0


def report(ok, label, *details):
    global passed, failed
    if ok:
        passed += 1
        print(f"  PASS  {label}")
    else:
        failed += 1
        print(f"  FAIL  {label}")
        for d in details:
            print(f"        {d}")


def table(name):
    m = re.search(r"declare -A %s=\(\n(.*?)\n\)\n" % name, TEXT, re.S)
    if not m:
        return {}
    return dict(re.findall(r'^\s*\[([a-z0-9_]+)\]="((?:[^"\\]|\\.)*)"$', m.group(1), re.M))


def keys_of(name):
    """Every key of a table in file order, duplicates included (a dict would hide them)."""
    m = re.search(r"declare -A %s=\(\n(.*?)\n\)\n" % name, TEXT, re.S)
    return re.findall(r'^\s*\[([a-z0-9_]+)\]=', m.group(1), re.M) if m else []


ES, EN = table("MSG_ES"), table("MSG_EN")
NAME_ES, NAME_EN = table("APP_NAME_ES"), table("APP_NAME_EN")
DESC_ES, DESC_EN = table("APP_DESC_ES"), table("APP_DESC_EN")
catalog = re.search(r"CATALOG_ALL=\(\n(.*?)\n\)\nreadonly", TEXT, re.S)
# "key|desktops|package1,package2": desktops is "*" or words separated by spaces (F4.3)
CATALOG = re.findall(r'^\s*"([a-z0-9_]+)\|([^|"]+)\|([^"]+)"$', catalog.group(1), re.M) if catalog else []

print("-- message tables")
report(len(ES) > 40 and len(EN) > 40, "both message tables were parsed", f"ES={len(ES)} EN={len(EN)}")
dups = [f"{t}.{k}" for t in ("MSG_ES", "MSG_EN", "APP_NAME_ES", "APP_NAME_EN", "APP_DESC_ES", "APP_DESC_EN")
        for k, n in Counter(keys_of(t)).items() if n > 1]
report(not dups, "no table defines the same key twice (the second would silently win)", f"duplicated: {dups}")
report(set(ES) == set(EN), "Spanish and English have exactly the same keys",
       f"only ES: {sorted(set(ES) - set(EN))}", f"only EN: {sorted(set(EN) - set(ES))}")


def specs(s):
    return Counter(re.findall(r"%[sd%]", s))


bad = [k for k in ES if k in EN and specs(ES[k]) != specs(EN[k])]
report(not bad, "both languages use the same printf placeholders in every message", f"differ: {bad}")
bad = [k for k in ES if k in EN and ES[k].count("\\n") != EN[k].count("\\n")]
report(not bad, "both languages break lines the same way (same number of \\n)", f"differ: {bad}")
identical = [k for k in ES if k in EN and ES[k] == EN[k] and k not in {"title"}]
report(not identical, "no message is left untranslated (identical in both languages)", f"identical: {identical}")
empty = [(lang, k) for lang, tab in (("ES", ES), ("EN", EN)) for k, v in tab.items() if not v.strip()]
report(not empty, "no empty messages in either language", f"{empty}")

print("-- keys used by the script")
used = set(re.findall(r"\bmsg(?:ln)? ([a-z0-9_]+)", TEXT))
used |= set(re.findall(r"\bmsgf_v \w+ ([a-z0-9_]+)", TEXT))
used |= set(re.findall(r"\$\(msg ([a-z0-9_]+)\)", TEXT))
used |= set(re.findall(r"\bmsg_in \w+ ([a-z0-9_]+)", TEXT))   # launcher comment, written in both languages (F5.1)
used |= {f"{k}_{s}" for k in ("detected_count", "advanced_warning", "advanced_unmanaged") for s in ("1", "n")}
used |= {f"nav_text_{i}" for i in range(1, 3)}
# The cleaning catalog (FP.4) asks for its names with msg "clean_item_$id", so the keys are derived from it.
clean_match = re.search(r"CLEAN_CATALOG=\((.*?)\n\)", TEXT, re.S)
report(clean_match is not None, "the cleaning catalog (CLEAN_CATALOG) is in the script")
CLEAN = re.findall(r'^\s*"([a-z_0-9]+)\|([a-z]+)\|', clean_match.group(1), re.M) if clean_match else []
used |= {f"clean_item_{i}" for i, _ in CLEAN} | {f"clean_item_{i}_desc" for i, _ in CLEAN}
used |= {f"clean_cat_{c}" for _, c in CLEAN}
report(not (used - set(EN)), "every message key the script asks for exists", f"missing: {sorted(used - set(EN))}")
unused = sorted(set(EN) - used)
report(not unused, "every defined message is used", f"unused: {unused}")

print("-- app catalog")
keys = [k for k, _, _ in CATALOG]
report(len(keys) >= 20, "the catalog was parsed", f"{len(keys)} entries")
report(len(keys) == len(set(keys)), "catalog keys are unique")
DESKTOPS = {"cinnamon", "gnome", "kde", "xfce", "mate"}
bad = [(k, d) for k, d, _ in CATALOG if d != "*" and not (d.split() and set(d.split()) <= DESKTOPS and len(set(d.split())) == len(d.split()))]
report(not bad, "every catalog entry names \"*\" or known desktops (cinnamon gnome kde xfce mate), without repeats", f"{bad}")
for label, tab in (("APP_NAME_ES", NAME_ES), ("APP_NAME_EN", NAME_EN), ("APP_DESC_ES", DESC_ES), ("APP_DESC_EN", DESC_EN)):
    report(set(tab) == set(keys), f"{label} covers exactly the catalog keys",
           f"missing: {sorted(set(keys) - set(tab))}", f"extra: {sorted(set(tab) - set(keys))}")
pkgs = [p for _, _, lst in CATALOG for p in lst.split(",")]
report(all(re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", p) for p in pkgs), "catalog package names follow Debian naming rules",
       f"{[p for p in pkgs if not re.fullmatch(r'[a-z0-9][a-z0-9+.-]+', p)]}")
report(len(pkgs) == len(set(pkgs)), "no package appears under two catalog entries")
# Names that are the same in Spanish and English because they are proper names (or one shared word).
PROPER = set("""
    firefox thunderbird libreoffice warpinator transmission hypnotix rhythmbox celluloid pix
    evince eog totem shotwell gedit cheese remmina deja_dup aisleriot gnome_sudoku gnome_snapshot loupe
    gnome_mahjongg evolution
    kcalc okular kate kwrite gwenview ark kcharselect spectacle kdeconnect elisa kolourpaint skanpage
    skanlite filelight haruna kmahjongg kmines kpat ksudoku konversation krdc kwalletmanager ksystemlog
    neochat kamoso
    mousepad ristretto parole atril xfburn catfish xarchiver orage abiword gnumeric gigolo gimp hexchat
    menulibre mugshot
    pluma eom engrampa mozo
""".split())
same = [k for k in keys if NAME_ES.get(k) == NAME_EN.get(k) and k not in PROPER]
report(not same, "app names are translated unless they are proper names", f"identical: {same}")
stale = sorted(k for k in PROPER if k in NAME_ES and NAME_ES[k] != NAME_EN.get(k))
report(not stale, "every proper name in the exception list really is the same in both languages", f"differ: {stale}")
unknown = sorted(PROPER - set(keys))
report(not unknown, "every proper name in the exception list is a catalog key", f"not in the catalog: {unknown}")

print("-- language hygiene")
former = [r"\bmodo text\b", r"\bcódigo de output\b", r"\bEditor de text\b", r"main_menu_texto"]
found = [f for f in former if re.search(f, TEXT)]
report(not found, "no leftovers of the old automatic translation", f"{found}")
EN_WORDS = re.compile(r"\b(the|and|with|your|this|that|are|is|not|will|would|please|does|from|into|option|selected|cannot)\b", re.I)
ES_WORDS = re.compile(r"\b(el|la|los|las|del|para|con|una|que|se|esta|este|tu|tus|selecciona|opción|aplicación)\b", re.I)
KEEP = re.compile(r"'[^']*'|\bapt-get\b|\bapt\b|\bdpkg\b|\bsudo\b|\bwhiptail\b|\bFlatpak\b|\bSnap\b|\bMINTAPP_\w+")


def strip_code(s):
    return KEEP.sub(" ", s)


mixed_es = [k for k, v in ES.items() if k not in {"usage"} and EN_WORDS.search(strip_code(v))]
report(not mixed_es, "Spanish messages contain no English function words", f"{mixed_es}")
mixed_en = [k for k, v in EN.items() if k not in {"usage"} and ES_WORDS.search(strip_code(v))]
report(not mixed_en, "English messages contain no Spanish function words", f"{mixed_en}")
bad = [k for k, v in ES.items() if v.count("¿") != v.count("?") or v.count("¡") != v.count("!")]
report(not bad, "Spanish question and exclamation marks are paired", f"{bad}")
bad = [k for k, v in list(ES.items()) + list(EN.items()) if "  " in v.replace("\\n  ", "").replace("  -", "")
       and k not in {"nav_whiptail", "nav_tui", "usage"}]
report(not bad, "no accidental double spaces in messages", f"{sorted(set(bad))}")
# nav_whiptail, nav_tui and usage align columns, but only in rows that start with a space: the lines of prose have none.
bad = [(lang, k, line) for lang, tab in (("ES", ES), ("EN", EN)) for k in ("nav_whiptail", "nav_tui", "usage")
       for line in tab[k].split("\\n") if "  " in line and not line.startswith(" ")]
report(not bad, "in the help texts that align columns, only the indented rows have double spaces", f"{bad}")
# A literal \\n at an edge is a line break, not a space; a prompt ends in a space on purpose (the cursor goes after it) and
# an indented text starts with two. Each edge is judged by itself: a text that starts with \\n can still end in a space.
PROMPTS = {"confirm_plan_text", "confirm_plan", "confirm_plan_meta_text", "store_confirm_text", "clean_confirm_text"}
bad = [k for k, v in list(ES.items()) + list(EN.items())
       if (v != v.rstrip() and k not in PROMPTS) or (v != v.lstrip() and not v.startswith("  "))]
report(not bad, "no stray leading/trailing spaces in messages", f"{sorted(set(bad))}")

print("-- wording (F3.1): one term per concept, one register, no cut sentences")
# Names and descriptions share their keys, so each table gets its own prefix (merging them would hide one of the two).
ALL_ES = {**ES, **{f"name {k}": v for k, v in NAME_ES.items()}, **{f"desc {k}": v for k, v in DESC_ES.items()}}
ALL_EN = {**EN, **{f"name {k}": v for k, v in NAME_EN.items()}, **{f"desc {k}": v for k, v in DESC_EN.items()}}
bad = [k for k, v in ALL_ES.items() if re.search(r"\bprogramas?\b", v, re.I)]
report(not bad, "Spanish says \"aplicación\", never \"programa\", for an installed application", f"{bad}")
bad = [k for k, v in ALL_EN.items() if re.search(r"\bprograms?\b", v, re.I)]
report(not bad, "English says \"application\", never \"program\", for an installed application", f"{bad}")
USTED = re.compile(r"\b(Pulse|Seleccione|Escriba|Revise|Ejecute|Vuelva|Elija|Marque|Confirme|Cancele|Desmarque|usted|ustedes)\b")
bad = [k for k, v in ES.items() if USTED.search(v)]
report(not bad, "Spanish addresses the user as tú (no usted forms)", f"{bad}")
NO_TILDE = re.compile(r"\b(aplicacion|configuracion|descripcion|operacion|seleccion|instalacion|desinstalacion|opcion|"
                      r"informacion|contrasena|musica|fotografia|imagenes|escaner|gestion|analisis|simulacion|"
                      r"confirmacion|ejecucion|actualizacion|ningun|tambien|asi|mas|via|codigo|pagina|numero|"
                      r"despues|rapido|facil|vacio|unico|ultimo|estadisticas|energia|bateria|busqueda|menu|introduccion|contrasenas|"
                      r"ejecutaria|eliminaria|borraria|quitaria|caches|(?<!-)version)\b", re.I)   # "--version" is an option
bad = [(k, m.group(0)) for k, v in ALL_ES.items() for m in [NO_TILDE.search(v)] if m]
report(not bad, "Spanish words that need an accent have it", f"{bad}")
ENDS = re.compile(r"[.?!:)\]…]$|%s$")
LABELS = {"title", "nav_title", "advanced_header", "space_recovered"}   # headings and status lines
TRAILING = re.compile(r"(\\n|\s)+$")                                    # literal \n or spaces
bad = [(lang, k) for lang, tab in (("ES", ES), ("EN", EN)) for k, v in tab.items()
       if len(v.split()) > 3 and k not in LABELS and not ENDS.search(TRAILING.sub("", v))]
report(not bad, "no message with more than three words ends without closing punctuation", f"{bad}")
bad = [k for k in ES if k.startswith("nav_text") and "whiptail" in (ES[k] + EN[k]).lower()]
report(not bad, "the text-mode help does not claim whiptail is missing (it can also be off for other reasons)", f"{bad}")
LABELS_ALL = {**{f"name_es {k}": v for k, v in NAME_ES.items()}, **{f"name_en {k}": v for k, v in NAME_EN.items()},
              **{f"desc_es {k}": v for k, v in DESC_ES.items()}, **{f"desc_en {k}": v for k, v in DESC_EN.items()}}
bad = [k for k, v in LABELS_ALL.items() if v.rstrip().endswith(".") or v != v.strip()]
report(not bad, "catalog names and descriptions are short labels (no final period, no stray spaces)", f"{bad}")

report(ES["menu_language"] == "English" and EN["menu_language"] == "Español",
       "the language button shows the destination language in its own name (English / Español)")
report(ES["nav_text_prompt"].count("%s") == 1 and EN["nav_text_prompt"].count("%s") == 1
       and ES["nav_text_prompt"].endswith(":") and EN["nav_text_prompt"].endswith(":"),
       "the help-screen prompt names the other language (one %s) in both languages")
report(ES["confirm_plan_text"].endswith("[s/N]: ") and EN["confirm_plan_text"].endswith("[y/N]: "),
       "the text confirmation prompt shows [s/N] in Spanish and [y/N] in English (default: no)")
report("Respuesta no reconocida" in ES["answer_unknown"] and "not recognized" in EN["answer_unknown"],
       "an unrecognized yes/no answer has its own message in both languages")

print("-- meta-package guard (E14, F4.4)")
META_KEYS = ("meta_warning", "confirm_plan_meta", "confirm_plan_meta_text")
report(all(k in ES and k in EN for k in META_KEYS),
       "the warning and the stronger confirmations exist in both languages")
report(ES["confirm_plan_meta_text"].endswith("[s/N]: ") and EN["confirm_plan_meta_text"].endswith("[y/N]: "),
       "the stronger text confirmation shows [s/N] in Spanish and [y/N] in English (default: no)")
report(all(ES[k].count("%s") == (1 if k == "meta_warning" else 0) and EN[k].count("%s") == (1 if k == "meta_warning" else 0)
           for k in META_KEYS),
       "the warning takes exactly one list (%s) and the two confirmations take none, in both languages")
report(all("metapaquete" in ES[k] for k in META_KEYS) and not any(re.search(r"meta[ -]paquete", ES[k], re.I) for k in META_KEYS),
       "Spanish says \"metapaquete\" (one word) in the warning and in both confirmations")
report(all("meta-package" in EN[k] for k in META_KEYS) and not any(re.search(r"metapackage|meta package", EN[k], re.I) for k in META_KEYS),
       "English says \"meta-package\" (hyphenated) in the warning and in both confirmations")
report(ES["meta_warning"].endswith("\\n\\n") and EN["meta_warning"].endswith("\\n\\n"),
       "the warning ends with a blank line, because the plan text follows it in the dialogs")

print("-- Flatpak and Snap (F4.5b)")
STORE_KEYS = ("store_plan_intro", "store_scope_system", "store_scope_user", "store_confirm", "store_confirm_text",
              "store_plan_calculating", "store_removing", "store_error", "store_error_gui")
report(all(k in ES and k in EN for k in STORE_KEYS), "the plan, scope, confirmation, progress and error texts exist in both languages")
report(ES["store_confirm_text"].endswith("[s/N]: ") and EN["store_confirm_text"].endswith("[y/N]: "),
       "the text confirmation of the stores shows [s/N] in Spanish and [y/N] in English (default: no)")
report(all(ES[k].count("%s") == n and EN[k].count("%s") == n
           for k, n in (("store_removing", 1), ("store_error", 3), ("store_error_gui", 4), ("store_plan_intro", 0),
                        ("store_scope_system", 0), ("store_scope_user", 0), ("store_confirm_text", 0),
                        ("store_confirm", 0), ("store_plan_calculating", 0))),
       "each text takes the printf arguments the code gives it, in both languages")
report(all("'flatpak uninstall'" in v and "'snap remove'" in v for v in (ES["store_plan_intro"], EN["store_plan_intro"])),
       "the introduction names the real commands, the same in both languages")
report(ES["store_error_gui"].endswith("%s") and EN["store_error_gui"].endswith("%s")
       and "terminal" in ES["store_error"] and "terminal" in EN["store_error"],
       "the error of the windows ends with the output of the command; the terminal one points above")
report("aplicaciones" in ES["store_confirm"] and "applications" in EN["store_confirm"]
       and not re.search(r"paquete", ES["store_confirm"] + ES["store_confirm_text"], re.I)
       and not re.search(r"package", EN["store_confirm"] + EN["store_confirm_text"], re.I),
       "the confirmations of the stores speak of applications, not packages (those are apt's)")
report(not re.search(r"simulaci", ES["store_plan_calculating"], re.I) and not re.search(r"simulat", EN["store_plan_calculating"], re.I),
       "the notice that the plan is being prepared does not promise a simulation (only apt has one)")
report(not any("apt" in v.replace("apt no", "").replace("apt is not", "") for v in (ES["store_error"], EN["store_error"], ES["store_error_gui"], EN["store_error_gui"])),
       "the errors of the stores do not blame apt")

print("-- package manager at start (4.6, step 4e)")
PM_START_KEYS = (("pm_none_error", 1), ("dnf_error", 0), ("dnf_version_error", 1))
report(all(k in ES and k in EN for k, _ in PM_START_KEYS),
       "the texts about the manager at start (none found, dnf or rpm missing, dnf 5) exist in both languages")
report(all(ES[k].count("%s") == n and EN[k].count("%s") == n for k, n in PM_START_KEYS),
       "each takes the printf arguments the code gives it (the managers, nothing, the first line of dnf --version), in both languages")
report(ES["pm_none_error"].endswith("(admitidos: %s).") and EN["pm_none_error"].endswith("(supported: %s)."),
       "the text of \"no manager found\" ends with the list of the managers that have a backend, like the one of MINTAPP_PM")
report(all("dnf" in v and "rpm" in v for v in (ES["dnf_error"], EN["dnf_error"])),
       "the text of the missing tool names both dnf and rpm, in both languages")
report(all("dnf --version" in v and "dnf 5" in v and "Fedora 41" in v and "dnf 4" in v for v in (ES["dnf_version_error"], EN["dnf_version_error"])),
       "the text of the refused version names dnf 4 (what is needed), dnf 5 and Fedora 41 (what is refused) and the command, in both languages")

print("-- texts that name a package manager (4.6, step 7)")
# A text names a manager on purpose only where it is that manager's: its tools missing at start, the two cleaning entries
# that only apt has and the list of managers of MINTAPP_PM in the usage. A text that names one anywhere else was left behind
# when the program learned to work with another manager: it must say "package manager".
NAMING = {
    "apt, apt-get or dpkg": (r"\b(apt(-get)?|dpkg)\b", {"apt_error", "dpkg_error", "clean_item_apt_cache_desc", "clean_item_rc_config_desc", "usage"}),
    "dnf or rpm": (r"\b(dnf|rpm)\b", {"dnf_error", "dnf_version_error", "zypper_error", "usage"}),
    "pacman": (r"\bpacman\b", {"pacman_error", "usage"}),
    "zypper": (r"\bzypper\b", {"zypper_error", "usage"}),
}
for what, (rx, expected) in NAMING.items():
    found = {lang: {k for k, v in T.items() if re.search(rx, v, re.I)} for lang, T in (("ES", ES), ("EN", EN))}
    report(all(f == expected for f in found.values()),
           f"the texts that name {what} are those of that manager and no other, in both languages",
           *(f"{lang}: also names it {sorted(f - expected)}; no longer names it {sorted(expected - f)}"
             for lang, f in found.items() if f != expected))
NEUTRAL_KEYS = ("uninstall_error", "uninstall_error_gui", "advanced_warning_1", "advanced_warning_n", "advanced_unmanaged_1",
                "advanced_unmanaged_n", "plan_error", "plan_real", "plan_real_clean", "plan_password_note", "meta_warning",
                "menu_uninstall_desc", "menu_clean_desc", "store_plan_intro")
ANY_MANAGER = re.compile(r"\b(apt(-get)?|dpkg|dnf|rpm|pacman|zypper|yum)\b", re.I)
report(all(k in ES and k in EN for k in NEUTRAL_KEYS), "the texts that must name no manager exist in both languages")
report(not [(lang, k) for lang, T in (("ES", ES), ("EN", EN)) for k in NEUTRAL_KEYS if ANY_MANAGER.search(T.get(k, ""))],
       "the plan, the errors, the warnings and the menu descriptions name no manager: they are the same with apt, dnf and pacman",
       *[f"{lang} {k}: {T[k]}" for lang, T in (("ES", ES), ("EN", EN)) for k in NEUTRAL_KEYS if ANY_MANAGER.search(T.get(k, ""))])
report(all(ANY_MANAGER.search(line) is None or "MINTAPP_PM" in line for T in (ES, EN) for line in T["usage"].split("\\n")),
       "the usage names the managers only in the line of MINTAPP_PM")
report(all(ES[k].count("%s") == n and EN[k].count("%s") == n for k, n in (("plan_error", 1), ("plan_password_note", 0))),
       "the error of the plan takes the output of the manager (one %s) and the note about the password takes nothing")

print("-- deep cleanup: confirmation and rights (FP.4d, step 3)")
CLEAN_RUN_KEYS = ("clean_yes", "clean_confirm", "clean_confirm_text", "clean_priv_denied")
report(all(k in ES and k in EN for k in CLEAN_RUN_KEYS),
       "the button, the question, the text prompt and the notice of denied rights exist in both languages")
report(all(ES[k].count("%s") == 0 and EN[k].count("%s") == 0 for k in CLEAN_RUN_KEYS),
       "none of them takes a printf argument, in both languages")
report(ES["clean_confirm_text"].endswith("[s/N]: ") and EN["clean_confirm_text"].endswith("[y/N]: "),
       "the text confirmation of the cleaning shows [s/N] in Spanish and [y/N] in English (default: no)")
report("no se puede deshacer" in ES["clean_confirm"] and "cannot be undone" in EN["clean_confirm"],
       "the question says that the cleaning cannot be undone, in both languages")
report(ES["clean_yes"] != ES["yes_remove"] and EN["clean_yes"] != EN["yes_remove"]
       and ES["clean_yes"] != ES["cancel"] and EN["clean_yes"] != EN["cancel"] and len(ES["clean_yes"].split()) == len(EN["clean_yes"].split()) == 1,
       "the button that confirms is one word that names the action (not \"Uninstall\", not \"Cancel\"), in both languages")
report(all(T["clean_priv_denied"].endswith(" " + T["clean_res_nothing"])
           and T["clean_priv_denied"].rsplit(". ", 1)[0] == T["priv_denied"].rsplit(". ", 1)[0] for T in (ES, EN)),
       "the notice of denied rights gives the cause as the uninstall one does and ends with \"nothing was cleaned\", in both languages")

print("-- deep cleanup: review of the texts (P.4e)")
# The titles take the level in lower case (clean_level_word): in Spanish it agrees with "limpieza", so there is no "nivel %s".
report(all(ES[k].count("%s") == 1 and EN[k].count("%s") == 1 and "nivel %s" not in ES[k] and "%s level" in EN[k]
           for k in ("clean_sum_title", "clean_res_title")),
       "the titles of the summary and the result take the level in lower case: \"limpieza profunda completa\", \"complete level\"")
# The complete level cleans more than the simple one; its description must name every entry that only it has.
only_c = [i for i, lv in re.findall(r'^\s*"([a-z_0-9]+)\|[a-z]+\|(SC|C)\|', clean_match.group(1), re.M) if lv == "C"]
NAMED = {"trash": ("papelera", "trash"), "x11_logs": ("X11", "X11"), "crash": ("informes de fallos", "crash reports"),
         "rc_config": ("configuración residual", "leftover settings")}
report(sorted(only_c) == sorted(NAMED),
       "the entries that only the complete level has are the four whose names this check knows (a new one needs its words here)",
       f"catalog: {sorted(only_c)}; known: {sorted(NAMED)}")
missing = [(lang, i) for lang, T, n in (("ES", ES, 0), ("EN", EN, 1)) for i in only_c
           if i in NAMED and NAMED[i][n].casefold() not in T["clean_level_complete_desc"].casefold()]
report(not missing, "the description of the complete level names each entry that only it cleans, in both languages", f"{missing}")
browsers_match = re.search(r"CLEAN_BROWSERS=\(\n(.*?)\n\)\nreadonly", TEXT, re.S)
BROWSERS = re.findall(r'^\s*"([^|"]+)\|', browsers_match.group(1), re.M) if browsers_match else []
report(len(BROWSERS) >= 7, "the list of browsers of the cleaning (CLEAN_BROWSERS) was parsed", f"{BROWSERS}")
missing = [(lang, b) for lang, T in (("ES", ES), ("EN", EN)) for b in BROWSERS
           if b.casefold() not in T["clean_item_browsers_desc"].casefold()]
report(not missing, "the text of the browser caches names every browser the program cleans, in both languages", f"{missing}")
report(not re.search(r"\bthe own\b", " ".join(EN.values())),
       "English does not say \"the own\" (a possessive needs its owner: \"of each application\")")

# One term for the administrator's authority per language: "permisos de administrador" / "administrator rights".
report(not [k for k, v in ES.items() if re.search(r"derechos de administrador|privilegios", v, re.I)],
       "Spanish says \"permisos de administrador\" everywhere, never \"derechos\" or \"privilegios\"")
report(not [k for k, v in EN.items() if re.search(r"administrator permissions|\bprivileges\b|admin rights|root rights", v, re.I)],
       "English says \"administrator rights\" everywhere, never \"permissions\" or \"privileges\"")
# The program also works with doas or the command of MINTAPP_SUDO: a denial that blames "sudo" is wrong for them.
report(not [(lang, k) for lang, T in (("ES", ES), ("EN", EN)) for k in ("priv_denied", "clean_priv_denied") if re.search(r"\bsudo\b", T[k])],
       "the notices of denied rights do not name sudo (the user may have doas or another command)")

print(f"  -- {passed} passed, {failed} failed, {gaps} planned gaps")
sys.exit(1 if failed else 0)
