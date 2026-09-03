# SPDX-License-Identifier: GPL-3.0-or-later
"""Every place a tool has to be registered, checked against the tree.

Adding a tool means writing the tool -- and then remembering six other
files: a caption and a placement in lisp/lazpanel/LAZPANEL.lsp, a slot
in shared/parts/CALOFIN-LOADER.lsp, a row plus two hand-counted numbers
in README.md, an entry in the VB palette's own catalog and a name in
the glue list that greys its button out.  Forget one and nothing
complains until a reader notices, because those numbers are prose.

They rot.  README.md said the panel covered 62 headline commands while
the panel carried 66 -- the sentence wraps mid-number, so a hand sweep
of the other two occurrences walked straight past it.

So the numbers stop being typed.  This module computes each one from
the tree and compares; --fix rewrites the digits, inserts a missing
caption row and a missing Rest-page placement, and then names the
decisions it will not make for you.

What it deliberately does NOT do:

  * write caption TEXT.  "Pool side view" is editorial.  --fix inserts
    an empty caption and test_lazpanel.py's `assert all(CAPTIONS...)`
    refuses to go green until a human fills it in.
  * choose a category page.  Layout/Points/Dimensions/Checking is a
    judgement about what a tool IS.  A plausible-but-wrong placement
    nobody reviews is worse than a loud gap.
  * choose a job page other than Rest.  Rest is *defined* as the
    complement of Pool/Cover/Spa, so appending there is arithmetic, not
    judgement; moving a tool off Rest is judgement.
  * touch the VB palette at all.  Nothing here can compile it -- the
    project targets net48 against the AutoCAD.NET reference assemblies
    -- so a --fix that edited VB source would be writing code no test
    in this repo can run.  The palette is CHECKED and reported on,
    with the exact New Entry(...) line to paste, and left to a human.

LAZPANEL.lsp stays a hand-edited lisp/ file: --fix is a codemod over
it, the way `sed` would be, not a build step.  It has no generated
region and no marker comments, and nothing here writes to a generated
tier -- --fix prints the regeneration commands instead of running them.
"""

import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from callib import (  # noqa: E402
    LISP_DIR, PARTS_DIR, ROOT, census, headline_commands, held_back,
    loader_members, read,
)

PANEL = LISP_DIR / "lazpanel" / "LAZPANEL.lsp"

#: The VB palette's own catalog, and the LISP glue that tells it which
#: commands this session has loaded.  Neither can be compiled or run
#: here -- Calofin.vbproj targets net48 against the AutoCAD.NET
#: reference assemblies -- but both are TEXT, and text is exactly what
#: drifts: the palette shipped 60 of the panel's 67 and nothing said so.
PALETTE = ROOT / "ui" / "calofin_net" / "CalofinPalette.vb"
GLUE = ROOT / "ui" / "calofin_ui" / "calofin.lsp"

#: One {"Layout", { ... }} block of CommandCatalog.Groups.
VB_GROUP = re.compile(r'\{"(\w+)", \{(.*?)\n        \}\}', re.S)
VB_ENTRY = re.compile(r'New Entry\("([^"]+)", "([^"]*)", "([^"]*)"\)')

#: Captions are one per line, the text aligned to a fixed column so the
#: table reads as two columns rather than a ragged list.
CAPTION_COL = 24
CAPTION_ROW = re.compile(r'^    \("([A-Z0-9_-]+)"\s+"([^"]*)"\)$', re.M)

#: The four job pages.  Rest is the complement of the other three, which
#: is what lets --fix append to it without making a judgement.
JOBS = ("Pool", "Cover", "Spa", "Rest")
CATEGORIES = ("Layout", "Points", "Dimensions", "Checking")


# ---------------------------------------------------------------- parsing

def _table_span(src, name):
    """(start, end) of the body of a top-level (setq lzp:*NAME* '(...))."""
    m = re.search(r"\(setq lzp:\*" + name + r"\*\s*\n?\s*'\(", src)
    if not m:
        return None
    i = src.index("'(", m.start()) + 1
    depth, j = 0, i
    while j < len(src):
        if src[j] == "(":
            depth += 1
        elif src[j] == ")":
            depth -= 1
            if depth == 0:
                return (i, j + 1)
        j += 1
    return None


def captions(src):
    """The caption table as {COMMAND: text}, in file order."""
    span = _table_span(src, "captions")
    if span is None:
        return None
    return dict(CAPTION_ROW.findall(src[span[0]:span[1]]))


def _sexp(body):
    """BODY, an AutoLISP list, as nested Python lists of strings.

    Pages and columns are indistinguishable by indentation -- the first
    page sits behind the table's own two parens and every later one is
    flush with the columns -- so the structure has to come from paren
    depth, not from a line pattern.
    """
    stack, cur, i, n = [], [], 0, len(body)
    while i < n:
        ch = body[i]
        if ch == "(":
            stack.append(cur)
            cur = []
        elif ch == ")":
            if not stack:
                break
            done, cur = cur, stack.pop()
            cur.append(done)
        elif ch == '"':
            j = body.index('"', i + 1)
            cur.append(body[i + 1:j])
            i = j
        i += 1
    return cur[0] if len(cur) == 1 and isinstance(cur[0], list) else cur


def pages(src):
    """{page: {column: [command, ...]}} out of lzp:*groups*."""
    span = _table_span(src, "groups")
    if span is None:
        return None
    out = {}
    for page in _sexp(src[span[0]:span[1]]):
        if not page or not isinstance(page[0], str):
            continue
        cols = {}
        for col in page[1:]:
            if isinstance(col, list) and col and isinstance(col[0], str):
                cols[col[0]] = [c for c in col[1:] if isinstance(c, str)]
        out[page[0]] = cols
    return out


def buttons(src):
    """Every placement on the panel, repeats and all."""
    pg = pages(src)
    if pg is None:
        return []
    return [c for cols in pg.values() for names in cols.values()
            for c in names]


def bundle_counts():
    """(files, commands) the bundle will hold, from the loader's list."""
    members = loader_members() or []
    held = set(held_back())
    files = [m for m in members if m not in held]
    cmds = set()
    for name in files:
        p = PARTS_DIR / name
        if p.is_file():
            cmds |= {m.upper() for m in
                     re.findall(r"^\(defun\s+[cC]:([^\s()]+)", read(p), re.M)}
    return len(files), len(cmds)


# ----------------------------------------------------------------- counts

def derived_counts():
    """Every number the prose states, computed from the tree."""
    src = read(PANEL)
    files, cmds = bundle_counts()
    return {
        "headline": len(headline_commands()),
        "buttons": len(buttons(src)),
        "bundle_files": files,
        "bundle_commands": cmds,
    }


def count_rules(n):
    """(path, regex, expected) for every hand-typed number in the prose.

    Each regex has exactly one group, and it is the digits to compare.
    A regex that stops matching is a hard error, not a skip: a reworded
    sentence must not be able to silently drop out of the check.
    """
    return [
        (ROOT / "README.md",
         r"with the (\d+) headline drafting commands above", n["headline"]),
        (ROOT / "README.md",
         r"so (\d+) commands make \d+ buttons", n["headline"]),
        (ROOT / "README.md",
         r"so \d+ commands make (\d+) buttons", n["buttons"]),
        # this one wraps mid-sentence, which is how it rotted unnoticed
        (ROOT / "README.md",
         r"covers the (\d+)\s+headline drafting commands", n["headline"]),
        (LISP_DIR / "lazpanel" / "README.md",
         r"-- (\d+) of them across \d+ buttons", n["headline"]),
        (LISP_DIR / "lazpanel" / "README.md",
         r"-- \d+ of them across (\d+) buttons", n["buttons"]),
        (ROOT / "shared" / "README.md",
         r"loaded - (\d+) commands in one session",
         n["bundle_commands"]),
        (ROOT / "shared" / "README.md",
         r"the build as (\d+) separate files", n["bundle_files"]),
    ]


# ----------------------------------------------------------------- checks

#: Commands no suite invokes, and WHY -- the one list that may excuse a
#: command from tests/.  A name that gains a suite must leave this list
#: in the same commit (an entry with a suite fails the check), and a
#: name that is neither here nor in tests/ fails it too.  Version
#: reporters are excused by construction: tests/test_versions.py runs
#: every *VER.
UNTESTED = {
    "DDALT": "drone-height toolset: needs an EXIF/GPS photo fixture",
    "DDGPS": "drone-height toolset: needs an EXIF/GPS photo fixture",
    "DDTEST": "drone-height toolset: needs an EXIF/GPS photo fixture",
    "LAZASCII": "DCL font probe; the dialog API is stubbed per suite",
    "LAZPIN": "DCL pin editor; the dialog API is stubbed per suite",
    "LAZTXT": "DCL text view; the dialog API is stubbed per suite",
    "TUTORIALCORNERSTP": "tutorial: pauses and a demo drawing, no suite yet",
    "TUTORIALHEMISTEP": "tutorial: pauses and a demo drawing, no suite yet",
    "TUTORIALNORMIESTEP": "tutorial: pauses and a demo drawing, no suite yet",
    "TUTORIALCOVERCHECK": "tutorial: pauses and a demo scene, no suite yet",
    "TUTORIALDIMCHECK": "tutorial: pauses and a demo drawing, no suite yet",
    "TUTORIALDIMSCAN": "alias of TUTORIALDIMCHECK",
    "TUTORIALLINFINCHECK": "tutorial: pauses and a demo drawing, no suite yet",
    "TUTORIALLINFINSCAN": "alias of TUTORIALLINFINCHECK",
    "TUTORIALPADDLE": "tutorial: drives the ActiveX block surface the VM lacks",
}


SWEEP = ROOT / "tests" / "test_cancel_paths.py"


def sweep_covers():
    """The commands tests/test_cancel_paths.py drives by construction:
    every headline command but its NO_PROMPT and NEEDS_ACTIVEX sets,
    plus its QUIET, FILE_CANCEL and MORE rosters -- read off the file, as
    test_shared.py reads the loader, so the two cannot drift."""
    src = read(SWEEP)

    def names(var):
        m = re.search(r"^%s = [\[{](.*?)[\]}]" % var, src, re.S | re.M)
        return set(re.findall(r"'([A-Z0-9-]+)'", m.group(1))) if m else set()
    covered = headline_commands() - names("NO_PROMPT") - names("NEEDS_ACTIVEX")
    covered -= names("FILE_CANCEL")
    return covered | names("QUIET") | names("FILE_CANCEL") | names("MORE")


def test_census():
    """Problems: commands no test names and no UNTESTED entry excuses,
    and UNTESTED entries a suite has caught up with."""
    problems = []
    tests = "".join(read(p) for p in (ROOT / "tests").glob("test_*.py")).lower()
    swept = sweep_covers()
    named = set()
    for c in census():
        if c.endswith("VER") or c.endswith("VERSION"):
            continue
        if ("c:" + c.lower()) in tests or c in swept:
            named.add(c)
        elif c not in UNTESTED:
            problems.append(
                "%s is invoked by no suite under tests/ - drive it, or "
                "excuse it in UNTESTED in tools/check_registry.py with the "
                "reason" % c)
    for c in sorted(set(UNTESTED) & named):
        problems.append(
            "%s is in UNTESTED but a suite invokes it - remove the entry"
            % c)
    for c in sorted(set(UNTESTED) - set(census())):
        problems.append("%s is in UNTESTED but is not a command" % c)
    return problems


def palette_catalog():
    """{group: {command: caption}} out of the VB palette's own source,
    or None when the block cannot be found at all."""
    src = read(PALETTE)
    body = re.search(r"Groups As New Dictionary.*?\n\n", src, re.S)
    if not body:
        return None
    out = {}
    for m in VB_GROUP.finditer(body.group(0)):
        out[m.group(1)] = {e.group(1): e.group(2)
                           for e in VB_ENTRY.finditer(m.group(2))}
    return out or None


def glue_roster():
    """The command names calofin.lsp probes for, as a set."""
    m = re.search(r"calofin:\*commands\*\s*'\((.*?)\)\)", read(GLUE), re.S)
    return set(re.findall(r'"([A-Z0-9-]+)"', m.group(1))) if m else None


def check():
    """Problems as a list of strings, empty when the tree is in step."""
    problems = test_census()
    src = read(PANEL)

    caps = captions(src)
    pg = pages(src)
    if caps is None or pg is None:
        problems.append(
            "check_registry: cannot read LAZPANEL's roster tables - has "
            "lzp:*captions* or lzp:*groups* been renamed?")
        return problems

    placed = set(buttons(src))
    want = headline_commands()

    for c in sorted(want - placed):
        problems.append(
            "%s is a headline command with no panel button - run "
            "python3 tools/check_registry.py --fix" % c)
    for c in sorted(placed - want):
        problems.append(
            "%s has a panel button but is not a headline command "
            "(renamed, removed, or newly held back?)" % c)
    for c in sorted(placed - set(caps)):
        problems.append("%s has a button but no caption row" % c)
    for c in sorted(set(caps) - placed):
        problems.append("%s has a caption row but no button" % c)
    for c in sorted(c for c, t in caps.items() if not t.strip()):
        problems.append(
            "%s has an empty caption - write the words the button shows"
            % c)

    # LAZPANEL's own header claims every command appears at least twice,
    # once under a job and once under a category.  Nothing tested it.
    on_job = {c for p in JOBS for names in pg.get(p, {}).values()
              for c in names}
    on_cat = {c for p in CATEGORIES for names in pg.get(p, {}).values()
              for c in names}
    for c in sorted(placed - on_job):
        problems.append("%s is on no job page (%s)" % (c, "/".join(JOBS)))
    for c in sorted(placed - on_cat):
        problems.append(
            "%s is on no category page - pick one of %s; --fix will not "
            "guess which" % (c, "/".join(CATEGORIES)))

    problems.extend(palette_problems(caps, pg, placed))

    n = derived_counts()
    for path, rx, expected in count_rules(n):
        body = read(path)
        m = re.search(rx, body)
        rel = path.relative_to(ROOT)
        if not m:
            problems.append(
                "%s: the sentence matching /%s/ is gone - the count it "
                "carried is no longer checked; restore it or update "
                "tools/check_registry.py" % (rel, rx))
        elif int(m.group(1)) != expected:
            problems.append(
                "%s says %s where the tree gives %d (/%s/) - run "
                "python3 tools/check_registry.py --fix"
                % (rel, m.group(1), expected, rx))
    return problems


def palette_problems(caps, pg, placed):
    """The VB palette against LAZPANEL's roster.

    The two surfaces are meant to file every tool the same way -- the
    palette's four groups ARE the panel's four category pages, and its
    captions are lzp:*captions* text.  They were, once.  Then seven
    tools were added to the panel and not to the palette, every caption
    still agreed, and nothing anywhere said the catalogs had parted.

    Nothing here can build the DLL, so this checks the one thing that
    does not need a compiler: that the two rosters name the same
    commands, in the same groups, with the same words.  A blurb is the
    palette's own -- it has no counterpart on the panel -- so it is not
    compared, only required to be there.
    """
    problems = []
    cat = palette_catalog()
    if cat is None:
        return ["%s: cannot read CommandCatalog.Groups - has the table "
                "been renamed or reshaped?" % PALETTE.relative_to(ROOT)]

    rel = PALETTE.relative_to(ROOT)
    for group in CATEGORIES:
        if group not in cat:
            problems.append("%s: no %s group" % (rel, group))
            continue
        want = {c for names in pg.get(group, {}).values() for c in names}
        have = set(cat[group])
        for c in sorted(want - have):
            problems.append(
                '%s: %s is on the panel\'s %s page and not in the palette '
                '- add New Entry("%s", "%s", "<what it does>") to the %s '
                'group' % (rel, c, group, c, caps.get(c, ""), group))
        for c in sorted(have - want):
            where = [g for g in CATEGORIES
                     if c in {x for ns in pg.get(g, {}).values() for x in ns}]
            problems.append(
                "%s: %s is in the palette's %s group but the panel files "
                "it under %s" % (rel, c, group,
                                 "/".join(where) or "no category page"))
        for c in sorted(have & want):
            if cat[group][c] != caps.get(c, ""):
                problems.append(
                    "%s: %s reads %r in the palette and %r on the panel - "
                    "one caption, two surfaces"
                    % (rel, c, cat[group][c], caps.get(c, "")))

    blank = sorted(c for g in cat.values() for c, _ in g.items()
                   if not c.strip())
    for c in blank:
        problems.append("%s: an entry with no command name" % rel)

    # the glue is what greys a button out; a command missing from it is
    # a button that stays enabled and reports its own absence instead
    roster = glue_roster()
    if roster is None:
        problems.append("%s: cannot read calofin:*commands*"
                        % GLUE.relative_to(ROOT))
    else:
        listed = {c for g in cat.values() for c in g}
        for c in sorted(listed - roster):
            problems.append(
                "%s: %s has a palette button but is not in "
                "calofin:*commands* - its button can never grey out"
                % (GLUE.relative_to(ROOT), c))
    return problems


# -------------------------------------------------------------------- fix

def _insert_caption(src, cmd):
    """A blank caption row for CMD, alphabetically placed."""
    span = _table_span(src, "captions")
    rows = [(m.group(1), m.start(), m.end())
            for m in CAPTION_ROW.finditer(src[span[0]:span[1]])]
    pad = " " * max(1, CAPTION_COL - (5 + len(cmd) + 2))
    line = '    ("%s"%s"")\n' % (cmd, pad)
    at = None
    for name, start, _end in rows:
        if name > cmd:
            at = span[0] + start
            break
    if at is None and rows:
        at = span[0] + rows[-1][2] + 1
    return src[:at] + line + src[at:]


def _append_to_rest(src, cmd):
    """Put CMD at the end of the Rest page's single column."""
    span = _table_span(src, "groups")
    body = src[span[0]:span[1]]
    m = re.search(r'^\s{5}\("Rest"\n\s{5}\(""\n', body, re.M)
    if not m:
        return src
    i = m.end()
    last = i
    for line in body[i:].split("\n"):
        if re.match(r'^\s{6}"[A-Z0-9_-]+"\s*$', line):
            last += len(line) + 1
        else:
            break
    return (src[:span[0] + last] + '      "%s"\n' % cmd
            + src[span[0] + last:])


def _bump_minor(src):
    m = re.search(r'\(setq \*lazpanel-version\* "v(\d+)\.(\d+)"\)', src)
    if not m:
        return src, None
    new = "v%s.%d" % (m.group(1), int(m.group(2)) + 1)
    return (src[:m.start()] + '(setq *lazpanel-version* "%s")' % new
            + src[m.end():], new)


def fix():
    """Repair what is deterministic; report what is not.  Returns 0/1."""
    src = read(PANEL)
    original = src
    caps = captions(src) or {}
    placed = set(buttons(src))
    want = headline_commands()

    added = []
    for cmd in sorted(want - placed):
        if cmd not in caps:
            src = _insert_caption(src, cmd)
        src = _append_to_rest(src, cmd)
        added.append(cmd)

    touched_panel = src != original
    if touched_panel:
        src, newver = _bump_minor(src)
        PANEL.write_text(src, encoding="utf-8")
        print("LAZPANEL.lsp: added %d command(s): %s"
              % (len(added), ", ".join(added)))
        if newver:
            print("LAZPANEL.lsp: version bumped to %s" % newver)

    # the counts, rewritten in place
    n = derived_counts()
    if touched_panel:
        n = derived_counts()
    fixed = 0
    for path, rx, expected in count_rules(n):
        body = read(path)
        m = re.search(rx, body)
        if not m or int(m.group(1)) == expected:
            continue
        s, e = m.span(1)
        path.write_text(body[:s] + str(expected) + body[e:], encoding="utf-8")
        print("%s: %s -> %d" % (path.relative_to(ROOT), m.group(1), expected))
        fixed += 1

    left = check()
    if added:
        print("\nDecisions --fix will not make for you:")
        for cmd in added:
            print("  %s: write its caption, and put it on a category page "
                  "(%s); move it off Rest if it belongs to a job."
                  % (cmd, "/".join(CATEGORIES)))
    if touched_panel:
        print("\nNow regenerate:")
        print("  python3 tools/mirror_shared.py LAZPANEL")
        print("  python3 tools/release_lisp.py")
        print("  python3 tools/build_shared_bundle.py")
    if not added and not fixed:
        print("check_registry: nothing to fix")
    if left:
        print("\nStill outstanding:")
        for p in left:
            print("  - %s" % p)
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fix", action="store_true",
                    help="repair what is deterministic, report the rest")
    args = ap.parse_args()
    if args.fix:
        return fix()
    problems = check()
    if problems:
        print("check_registry: %d problem(s):" % len(problems))
        for p in problems:
            print("  - %s" % p)
        return 1
    n = derived_counts()
    cat = palette_catalog() or {}
    print("check_registry: %d headline commands over %d buttons, "
          "%d counts in step, %d in the palette and its glue"
          % (n["headline"], n["buttons"], len(count_rules(n)),
             sum(len(g) for g in cat.values())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
