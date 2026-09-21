"""The ribbon's generated catalog, against the panel it comes from.

``ui/calofin_ribbon/Generated/CommandCatalog.g.cs`` is
``tools/gen_ui_data.py``'s second output: the same
``lzp:*captions*`` / ``lzp:*groups*`` tables the VB palette's
``CommandCatalog.g.vb`` already carries, written again in C# because
the ribbon is its own assembly and referencing the VB one just to read
one table would be a heavier dependency than the table is worth.

Unlike the palette's flat list, the ribbon folds a routine's VARIANTS
into that routine's dropdown -- POOLCOVER and POOLDEMO under POOL,
the four RECONVs under their CONVs -- because a ribbon panel is one row
on a shared strip and Layout's 37 buttons do not fit on it.  That fold
is the thing most worth checking, and in one specific direction: a tool
in the WRONG dropdown is a nuisance a drafter works around, while a
tool in NO item at all is simply unreachable from this surface, and
nothing about the ribbon would look broken.

So, parsed back out with its own regexes rather than by calling
``gen_ui_data.build_cs()`` -- a test that asked the generator what it
generates would agree with itself no matter what it emitted:

1. Every category carries exactly the panel's own commands, each of
   them exactly once, whether on a face or in a dropdown.
2. The families are the ones intended -- spot-checked against the
   editorial claim, not against the rule that produced them.
3. Every caption and blurb is the panel's / blurbs.txt's own.
4. The file on disk is what the generator would write now.

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

CS_PANEL = re.compile(r'\{ "(\w+)", new\[\]\s*\{(.*?)\n            \} \},',
                      re.S)
CS_ENTRY = re.compile(
    r'new Entry\("([^"]+)", '
    r'"((?:[^"\\]|\\.)*)", "((?:[^"\\]|\\.)*)"\)')


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


def items(block):
    """[(primary, [variant, ...])] out of one panel's Item list.

    Read a line at a time rather than with one big regex: a plain item
    is a single line ending in ``new Entry[0])``, a family opens with
    ``new[]`` and closes on its own ``}),``, and a pattern spanning
    newlines happily swallows the plain item that follows a family."""
    out = []
    open_item = None
    for line in block.splitlines():
        text = line.strip()
        if text.startswith("new Item("):
            face = cs_entries(line)
            open_item = (face[0], [])
            out.append(open_item)
            if "new Entry[0]" in text:
                open_item = None
        elif open_item is not None and text.startswith("new Entry("):
            open_item[1].extend(cs_entries(line))
        elif text == "}),":
            open_item = None
    return out


PANELS = {m.group(1): items(m.group(2)) for m in CS_PANEL.finditer(SRC)}


print("== 1. every command, exactly once, on a face or in a dropdown ==")

check("the %d category panels are the panel's groups" % len(cr.CATEGORIES),
      sorted(PANELS) == sorted(cr.CATEGORIES), repr(sorted(PANELS)))

seen = []
for group in cr.CATEGORIES:
    want = [c for names in PAGES.get(group, {}).values() for c in names]
    got = [e[0] for primary, variants in PANELS.get(group, [])
           for e in [primary] + variants]
    seen.extend(got)
    check("%s reaches all %d of the panel's commands"
          % (group, len(want)), sorted(got) == sorted(want),
          repr(sorted(set(want) ^ set(got))))
    check("%s: %d command(s) on %d button(s)"
          % (group, len(got), len(PANELS.get(group, []))),
          len(PANELS.get(group, [])) <= len(got))

check("no command appears twice anywhere on the ribbon",
      len(seen) == len(set(seen)),
      repr(sorted(c for c in set(seen) if seen.count(c) > 1)))
check("every command the panel carries is reachable",
      set(seen) == set(CAPS), repr(sorted(set(CAPS) - set(seen))))


print("== 2. the families are the ones meant ==")

# Stated here as the editorial claim they are, rather than re-derived
# from gen_ui_data's rules: the rules are what produced the file, so
# asking them again would prove only that they are deterministic.
WANT_FAMILIES = {
    "POOL": ["POOLCOVER", "POOLDEMO"],
    "ABHD": ["ABHDCOVER", "SIMPABHD", "CABHD"],
    "LAZFORM": ["LAZTXT", "LAZFORMCOVER"],
    "FITABHD": ["FITABHDCOVER"],
    "PADDLE": ["MOHAMADDLE"],
    "SMARTFILLET": ["HONEFILLET"],
    "LINGUTTER": ["LINGUTTERSCAN"],
    "ABCDEF": ["ALTABCDEF"],
    "PERPPTS": ["CPERPPTS"],
    "AUTODIM": ["AUTODIMSIDEPOV"],
    "CLEARDIM": ["CLEARDIMSCAN"],
    "XFTCONV": ["XFTRECONV"],
    "SOCONV": ["SORECONV"],
    "VSCONV": ["VSRECONV"],
    "G2MCONV": ["G2MRECONV"],
    "DIMCHECK": ["DIMSCAN"],
    "ABCURCHECK": ["ABCURCHECKSCAN"],
    "LINFINCHECK": ["LINFINSCAN", "LITELINFINSCAN"],
    "COVERCHECK": ["COVERSCAN", "LITECOVERSCAN"],
    "SPACHECK": ["SPACHECKSCAN", "LITESPACHECKSCAN"],
}

found = {primary[0]: [v[0] for v in variants]
         for group in PANELS.values() for primary, variants in group}

for name, want in sorted(WANT_FAMILIES.items()):
    check("%s carries %s" % (name, ", ".join(want)),
          found.get(name) == want, repr(found.get(name)))

# The other direction: nothing ELSE grew a dropdown.  A new affix rule
# that over-reached would show up here rather than as a tool nobody can
# find, and the three step SHAPES staying three buttons is the case
# this pins -- they are parallel tools, not versions of one.
extra = {k: v for k, v in found.items() if v and k not in WANT_FAMILIES}
check("no tool grew a dropdown nobody asked for", not extra, repr(extra))
check("the three step shapes are still three buttons",
      not found.get("CORNERSTP") and "HEMISTEP" in found
      and "NORMIESTEP" in found,
      repr(found.get("CORNERSTP")))


print("== 3. every caption and blurb is the panel's own ==")

all_entries = [e for group in PANELS.values()
               for primary, variants in group
               for e in [primary] + variants]

wrong_cap = [(c, cap, CAPS.get(c)) for c, cap, _ in all_entries
             if cap != CAPS.get(c)]
check("every caption is the panel's own", not wrong_cap, repr(wrong_cap[:3]))

bad_blurb = [c for c, _, b in all_entries
             if b != (BLURBS.get(c) or CAPS.get(c, c))]
check("every blurb in the file is the one blurbs.txt (or the caption) gives",
      not bad_blurb, repr(bad_blurb[:3]))
check("a blurb is never empty", all(b.strip() for _, _, b in all_entries))


print("== 4. the file is current ==")

check("gen_ui_data --check is happy", not gen_ui_data.check(),
      repr(gen_ui_data.check()))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL RIBBON CATALOG CHECKS PASSED (%d commands on %d buttons, "
      "%d panels)"
      % (len(seen), sum(len(v) for v in PANELS.values()), len(PANELS)))
