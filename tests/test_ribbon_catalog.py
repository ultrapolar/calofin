"""The ribbon's generated catalog, against the panel it comes from.

``ui/calofin_ribbon/Generated/CommandCatalog.g.cs`` is
``tools/gen_ui_data.py``'s second output: the same
``lzp:*captions*`` / ``lzp:*groups*`` tables the VB palette's
``CommandCatalog.g.vb`` already carries, written again in C# because
the ribbon is its own assembly and referencing the VB one just to read
one table would be a heavier dependency than the table is worth.

``tests/test_ui_data.py`` already holds the VB file to the panel in
detail; this file asks the same three questions of the C# one, parsed
back out with its own regexes rather than by calling
``gen_ui_data.build_cs()`` -- a test that asked the generator what it
generates would agree with itself no matter what it emitted:

1. Every category carries exactly the panel's own commands.
2. Every caption and blurb in the file is the panel's / blurbs.txt's
   own word for word.
3. The file on disk is what the generator would write now.

Run: python3 tests/test_ribbon_catalog.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import check_registry as cr  # noqa: E402
import gen_ui_data  # noqa: E402
from callib import read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


SRC = read(gen_ui_data.OUT_CS)
PANEL = read(cr.PANEL)
CAPS = cr.captions(PANEL)
PAGES = cr.pages(PANEL)
BLURBS = gen_ui_data.blurbs()

CS_GROUP = re.compile(r'\{ "(\w+)", new\[\]\s*\{(.*?)\n            \} \},',
                      re.S)
CS_ENTRY = re.compile(
    r'new Entry\("([^"]+)", '
    r'"((?:[^"\\]|\\.)*)", "((?:[^"\\]|\\.)*)"\),')


def unescape(s):
    """Reverses gen_ui_data.csstr: a backslash always introduces the one
    literal character that follows it, so undoing it needs no character
    table -- just drop every backslash it finds."""
    out = []
    i = 0
    while i < len(s):
        if s[i] == '\\' and i + 1 < len(s):
            out.append(s[i + 1])
            i += 2
        else:
            out.append(s[i])
            i += 1
    return ''.join(out)


def cs_entries(block):
    return [(m.group(1), unescape(m.group(2)), unescape(m.group(3)))
            for m in CS_ENTRY.finditer(block)]


print("== 1. every category, with the panel's own commands ==")

by_group = {m.group(1): dict((e[0], e[1]) for e in cs_entries(m.group(2)))
            for m in CS_GROUP.finditer(SRC)}

check("the %d category pages are the panel's groups" % len(cr.CATEGORIES),
      sorted(by_group) == sorted(cr.CATEGORIES), repr(sorted(by_group)))

for group in cr.CATEGORIES:
    want = [c for names in PAGES.get(group, {}).values() for c in names]
    check("%s carries the panel's %d" % (group, len(want)),
          sorted(by_group.get(group, {})) == sorted(want),
          repr(sorted(set(want) ^ set(by_group.get(group, {})))))

filed = [c for g in by_group.values() for c in g]
check("no command is filed under two categories",
      len(filed) == len(set(filed)))
check("every command is filed somewhere",
      set(filed) == set(CAPS), repr(sorted(set(CAPS) - set(filed))))


print("== 2. every caption and blurb is the panel's own ==")

wrong_cap = [(c, cap, CAPS.get(c)) for g in by_group.values()
             for c, cap in g.items() if cap != CAPS.get(c)]
check("every caption is the panel's own", not wrong_cap, repr(wrong_cap[:3]))

blurb_of = {e[0]: e[1] for m in CS_GROUP.finditer(SRC)
            for e in cs_entries(m.group(2)) for e in [(e[0], e[2])]}
bad_blurb = [c for c, b in blurb_of.items()
             if b != (BLURBS.get(c) or CAPS.get(c, c))]
check("every blurb in the file is the one blurbs.txt (or the caption) gives",
      not bad_blurb, repr(bad_blurb[:3]))
check("a blurb is never empty", all(b.strip() for b in blurb_of.values()))


print("== 3. the file is current ==")

check("gen_ui_data --check is happy", not gen_ui_data.check(),
      repr(gen_ui_data.check()))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL RIBBON CATALOG CHECKS PASSED (%d commands, %d groups)"
      % (len(filed), len(by_group)))
