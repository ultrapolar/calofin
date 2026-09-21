"""The ribbon's icons: the right set, real PNGs, and all different.

``tools/gen_ribbon_icons.py`` draws ``ui/calofin_ribbon/icons/*.png``
with nothing but ``zlib`` and ``struct`` -- no imaging library -- in two
kinds and two sizes: one per LAZPANEL category, and one per FEATURED
routine, at 16 (the collapsed panel's drop-down) and 32 (the face of a
large button).

This holds the tree to five things nothing else can see:

1. The set on disk is exactly the set the ribbon asks for, named the way
   ``RibbonExtensionApplication.cs``'s ``LoadIcon`` spells it.  A file
   short of that list is a large button with no picture; a file past it
   is dead weight copied into every bundle for ever.
2. ``DESIGN`` and ``FEATURED`` name the same routines.  These are two
   editorial lists in two files, which is a drift machine unless
   something holds them together -- and the drift is silent both ways:
   a featured routine with no glyph ships a blank large button, a glyph
   with no button is drawn every run and never seen.
3. Every file is a well-formed PNG of the size its name claims.
4. **No two icons are the same picture.**  The whole argument for
   spending 36 glyphs is that a drafter can tell them apart; two
   commands that got the same drawing -- a copy-paste in ``DESIGN``, a
   subject reused by accident -- would look exactly like a working
   ribbon and be worth nothing.
5. The tree is what a fresh run would write, which is the contract
   every generated file in this repo is held to.

Run: python3 tests/test_ribbon_icons.py
"""

import os
import re
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import check_registry as cr  # noqa: E402
import gen_ribbon_icons as gri  # noqa: E402
import gen_ui_data  # noqa: E402
from callib import ROOT, read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


FEATURED = [cmd for _cat, cmd in gen_ui_data.featured()]
CS = read(ROOT / "ui" / "calofin_ribbon" / "RibbonExtensionApplication.cs")


print("== 1. the set on disk is the set the ribbon asks for ==")

want = sorted(p.name for p in gri.wanted())
have = sorted(p.name for p in gri.OUT_DIR.glob("*.png"))
check("exactly the %d expected files, none missing, none extra" % len(want),
      have == want,
      "missing %s / extra %s" % (sorted(set(want) - set(have)),
                                 sorted(set(have) - set(want))))
check("that is %d categories + %d routines, at %s"
      % (len(cr.CATEGORIES), len(FEATURED),
         " and ".join("%d" % s for s in gri.SIZES)),
      len(want) == (len(cr.CATEGORIES) + len(FEATURED)) * len(gri.SIZES))

# The names are a contract with the C#, which builds them by hand out of
# a prefix, the lowercased name and the size.  Read the spellings back
# off the source rather than trusting that both sides were edited.
for frag in ('"cmd-"', '"cat-"', '"-16.png"', '"-32.png"',
             "ToLowerInvariant()"):
    check("LoadIcon's callers still spell %s" % frag, frag in CS)


print("== 2. DESIGN and FEATURED name the same routines ==")

no_glyph = sorted(set(FEATURED) - set(gri.DESIGN))
no_button = sorted(set(gri.DESIGN) - set(FEATURED))
check("every FEATURED routine has a glyph", not no_glyph, repr(no_glyph))
check("every glyph belongs to a FEATURED routine", not no_button,
      repr(no_button))

# featured() itself refuses a name that is not the FACE of a button --
# a variant riding in a dropdown would have an icon nothing shows.
# Prove it still refuses rather than trusting the docstring.
saved = set(gen_ui_data.FEATURED)
try:
    gen_ui_data.FEATURED = saved | {"POOLCOVER"}
    try:
        gen_ui_data.featured()
        bites = False
    except SystemExit:
        bites = True
finally:
    gen_ui_data.FEATURED = saved
check("featuring a dropdown variant is refused", bites)


print("== 3. every file is a well-formed PNG of the size it claims ==")

PNG_SIG = b"\x89PNG\r\n\x1a\n"
sized = {}
for path in sorted(gri.wanted()):
    data = path.read_bytes()
    name = path.name
    if data[:8] != PNG_SIG:
        check("%s starts with the PNG signature" % name, False)
        continue
    w, h = struct.unpack(">II", data[16:24])
    claimed = int(re.search(r"-(\d+)\.png$", name).group(1))
    sized.setdefault(claimed, []).append((name, (w, h) == (claimed, claimed)))
for size in sorted(sized):
    rows = sized[size]
    bad = [n for n, ok in rows if not ok]
    check("all %d of the %dpx icons really are %dx%d"
          % (len(rows), size, size, size), not bad, repr(bad))


print("== 4. no two icons are the same picture ==")

for size in gri.SIZES:
    seen = {}
    dupes = []
    for path, blob in sorted(gri.wanted().items()):
        if not path.name.endswith("-%d.png" % size):
            continue
        if blob in seen:
            dupes.append("%s == %s" % (path.name, seen[blob]))
        seen[blob] = path.name
    check("the %d icons at %dpx are %d different pictures"
          % (len(seen) + len(dupes), size, len(seen)), not dupes, repr(dupes))

# 16 is not a copy of 32 under another name: it is drawn, not resampled,
# and six subjects say it again in fewer strokes.  If the two ever came
# out equal the small one would be doing nothing.
same = [c for c in gri.DESIGN
        if gri.command_png(c, "Layout", 16) == gri.command_png(c, "Layout", 32)]
check("no routine's two sizes are the same bytes", not same, repr(same))


print("== 5. the tree is current, and deterministic ==")

problems = gri.check()
check("gen_ribbon_icons --check is happy", not problems, repr(problems))

# The determinism the whole approach rests on: two renders of the same
# input are byte-identical, so "is this current" is a byte comparison
# rather than a re-render and an eyeball.
check("rendering twice is byte-identical",
      all(gri.category_png(c, s) == gri.category_png(c, s)
          for c in cr.CATEGORIES for s in gri.SIZES)
      and all(gri.command_png(c, cat, s) == gri.command_png(c, cat, s)
              for cat, c in gen_ui_data.featured() for s in gri.SIZES))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL RIBBON ICON CHECKS PASSED (%d icons: %d categories + %d "
      "routines, at %s)"
      % (len(gri.wanted()), len(cr.CATEGORIES), len(FEATURED),
         " and ".join("%dpx" % s for s in gri.SIZES)))
