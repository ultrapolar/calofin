"""The ribbon's panel icons: one per category, current, and real PNGs.

``tools/gen_ribbon_icons.py`` draws ``ui/calofin_ribbon/icons/*.png``
from ``tools/check_registry.py``'s ``CATEGORIES`` with nothing but
``zlib`` and ``struct`` -- no imaging library. This holds the tree to
three things nothing else checks:

1. There is exactly one icon per category, named the way
   ``RibbonExtensionApplication.cs``'s ``LoadIcon`` looks for it
   (lowercased, ``.png``) -- a renamed or added category with no
   matching icon file would leave a ribbon button with no picture and
   nothing here to say why.
2. Every file is a well-formed PNG of the size the ribbon expects.
3. The tree is what a fresh run would write -- the same contract every
   other generated file in this repo is held to, via the module's own
   ``--check``.

Run: python3 tests/test_ribbon_icons.py
"""

import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import check_registry as cr  # noqa: E402
import gen_ribbon_icons as gri  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


print("== 1. one icon per category, named the way the ribbon looks for it ==")

want_names = sorted(c.lower() + ".png" for c in cr.CATEGORIES)
have_names = sorted(p.name for p in gri.OUT_DIR.glob("*.png"))
check("exactly the %d expected icon files, none extra" % len(want_names),
      have_names == want_names, repr((want_names, have_names)))


print("== 2. every file is a well-formed PNG of the expected size ==")

PNG_SIG = b"\x89PNG\r\n\x1a\n"
for cat in cr.CATEGORIES:
    p = gri.out_path(cat)
    ok_file = p.is_file()
    check("%s exists" % p.relative_to(gri.ROOT), ok_file)
    if not ok_file:
        continue
    data = p.read_bytes()
    check("%s starts with the PNG signature" % p.name,
          data[:8] == PNG_SIG)
    w, h = struct.unpack(">II", data[16:24])
    check("%s is %dx%d" % (p.name, gri.SIZE, gri.SIZE),
          (w, h) == (gri.SIZE, gri.SIZE), repr((w, h)))


print("== 3. the tree is current ==")

check("gen_ribbon_icons --check is happy", not gri.check(),
      repr(gri.check()))

# The determinism this whole approach rests on: two runs of the same
# category over the same source table produce byte-identical PNGs, so
# --check can compare bytes rather than re-rendering and eyeballing.
check("regenerating a category is byte-identical",
      all(gri.png_bytes(c) == gri.png_bytes(c) for c in cr.CATEGORIES))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL RIBBON ICON CHECKS PASSED (%d icons)" % len(cr.CATEGORIES))
