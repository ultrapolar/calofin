#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for PADDLE: c:PADDLE and c:TUTORIALPADDLE driven
end-to-end in the VM, on the sample perimeter the tutorial itself draws.

PADDLE was the one tool in the tree with NO runtime coverage of its
commands at all.  Not by choice: it is the only routine that reaches
the drawing through the ActiveX block surface -- it asks the layout for
its block and hands that to vla-InsertBlock -- and the VM carried none
of that, so both commands died on an undefined function before their
first prompt.  tests/test_cancel_paths.py had to name PADDLE in
NEEDS_ACTIVEX for exactly that reason, and tests/test_covercheck_pads.py
could only reach the pure geometry helpers.  836 lines of tool, and
nothing ever ran the command.

The VM carries vla-get-ActiveLayout / -Block / -Blocks, vla-Item on the
Blocks collection, vla-Add, vla-InsertBlock, vla-Delete, vlax-3d-point
and findfile now, so this file drives the real thing.

What is asserted, and why each one is worth asserting:

  * the pads land on the FEATURES -- the slot's two inside corners and
    the concave arc -- and nowhere else.  Convex corners and the 2-degree
    kink get nothing, which is the whole specification;
  * they are flush and never overlap.  The pads are axis-aligned
    squares, so "flush" is Chebyshev distance == the pad size, not
    centre distance: the row along the arc reads 36 apart that way while
    its centres are 39.5 apart straight-line.  Asserting the wrong norm
    would pass a row of overlapping pads;
  * a pad block whose base point is NOT at its centre still lands
    centred.  That is what paddle--block-delta exists for, and it is
    measured through vla-GetBoundingBox on an INSERT, so this is also
    the test that the bounding box of a block reference is the block's
    geometry and not just its insertion point;
  * the block resolution order -- a definition already in the drawing
    wins, and a missing one falls back to a plain square rather than
    failing;
  * the layer is created, and an existing one that is off, frozen or
    locked is put back so the result is visible;
  * every exit hands the session back: sysvars unchanged, no undo mark
    or group left open, no raw AutoLISP message on a cancel.

Run: python3 tests/test_paddle.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_paddle.py
"""

import math
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

LISP_ROOT = os.path.join(REPO_DIR, os.environ.get("CALOFIN_LISP_ROOT", "lisp"))
PADDLE = os.path.join(LISP_ROOT, "paddle", "PADDLE.lsp")
LIB = None
if os.path.basename(LISP_ROOT) == "shared":
    PARTS = os.path.join(LISP_ROOT, "parts")
    PADDLE = os.path.join(PARTS, "PADDLE.lsp")
    LIB = os.path.join(PARTS, "CALOFIN-LIB.lsp")

from lispvm import VM, Dot, LispError  # noqa: E402

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


PADSIZE = 36.0

#: A layer for the sample perimeter to sit on.  The tutorial makes its
#: own; c:PADDLE is driven here on a drawing that already has one.
DEMO_LAYER = '''
(entmakex (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")
                (cons 100 "AcDbLayerTableRecord") (cons 2 "DEMO")
                (cons 70 0) (cons 62 3) (cons 6 "Continuous")))
'''

#: Pad36x36 with its base point at a CORNER instead of the centre --
#: the case paddle--block-delta exists to absorb.
CORNER_BASED_BLOCK = '''
(entmake (list (cons 0 "BLOCK") (cons 2 "Pad36x36")
               (list 10 0.0 0.0 0.0) (cons 70 0)))
(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity") (cons 8 "0")
               (cons 100 "AcDbPolyline") (cons 90 4) (cons 70 1)
               (list 10 0.0 0.0) (list 10 36.0 0.0)
               (list 10 36.0 36.0) (list 10 0.0 36.0)))
(entmake (list (cons 0 "ENDBLK")))
'''


def fresh(extra=""):
    """A VM with PADDLE loaded (on the library, at the grouped tier)."""
    vm = VM()
    if LIB:
        vm.load(LIB)
    vm.load(PADDLE)
    if extra:
        vm.loads(extra)
    return vm


def with_perimeter(extra=""):
    """A VM whose drawing holds the tutorial's sample perimeter: straight
    walls, a 2-degree kink, convex corners, a rectangular slot with two
    90-degree inside corners, a tight concave bite and a sweep too big
    to need pads.  One of everything, which is the point of it."""
    vm = fresh(extra)
    vm.loads(DEMO_LAYER)
    vm.loads('(paddle--demo-pline (list 0.0 0.0 0.0) "DEMO")')
    return vm


def dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


def pads_of(vm, since=0):
    return [e for e in vm.entities[since:]
            if e not in vm.deleted and dxf(vm, e, 0) == "INSERT"]


def centres(vm, pads, delta=(0.0, 0.0)):
    """Where each pad actually sits: the insertion point plus the offset
    from the block's base to the centre of its extents."""
    out = []
    for e in pads:
        ip = dxf(vm, e, 10)
        out.append((round(ip[0] + delta[0], 4), round(ip[1] + delta[1], 4)))
    return sorted(out)


def cheb(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


#: The features of the sample perimeter, worked out from the geometry
#: and confirmed against the routine's own report ("2 at inside corners,
#: 3 along concave arcs").  The slot at x=84..132 turns 90 degrees into
#: the pool at each bottom corner; the row along the concave arc is
#: centred on the middle of the radius at (216,120) with one pad flush
#: to either side.
CORNERS = [(84.0, 120.0), (132.0, 120.0)]
ARC_ROW = [(180.0, 136.251), (216.0, 120.0), (252.0, 136.251)]
EXPECTED = sorted(CORNERS + ARC_ROW)


print("PADDLE -- auto-detect finds the perimeter and pads its features")
vm = with_perimeter()
before = dict(vm.sysvars)
n0 = len(vm.entities)
try:
    vm.run("c:PADDLE", [None, None])       # no pickfirst, Enter = auto-detect
except LispError as e:
    raise AssertionError(f"[auto-detect] {e}") from None
pads = pads_of(vm, n0)
out = "".join(vm.printed)
check("it said it auto-detected the largest closed loop",
      "auto-detected the largest closed loop" in out)
check("five pads went in", len(pads) == 5, f"got {len(pads)}")
check("every pad is the Pad36x36 block",
      {dxf(vm, e, 2) for e in pads} == {"Pad36x36"})
check("every pad is on the PADS layer",
      {vm.layer_of(e) for e in pads} == {"PADS"})
check("every pad is square to the X/Y axes",
      all(abs(dxf(vm, e, 50) or 0.0) < 1e-9 for e in pads))
check("the pads sit on the features and nowhere else",
      centres(vm, pads) == EXPECTED, f"{centres(vm, pads)}")
check("it reported 2 corners and 3 along the arc",
      "2 at inside corners, 3 along concave arcs" in out)
check("no two pads overlap",
      all(cheb(a, b) >= PADSIZE - 1e-6
          for i, a in enumerate(centres(vm, pads))
          for b in centres(vm, pads)[i + 1:]))
row = sorted(ARC_ROW)
check("the row along the arc is flush -- exactly one pad width apart",
      all(abs(cheb(row[i], row[i + 1]) - PADSIZE) < 1e-3
          for i in range(len(row) - 1)))
check("the convex corners and the 2-degree kink got nothing",
      not any(c[1] < 60.0 for c in centres(vm, pads)))
check("every sysvar is back where it started", vm.sysvars == before)
check("no undo mark was left open", vm.undo_marks == 0)


print("PADDLE -- a pad block based at a corner still lands centred")
vm = with_perimeter(CORNER_BASED_BLOCK)
n0 = len(vm.entities)
vm.loads("(setq _d (paddle--block-delta"
         " (vla-get-Block (vla-get-ActiveLayout"
         " (vla-get-ActiveDocument (vlax-get-acad-object)))) \"Pad36x36\"))")
delta = vm.globals["_d"]
check("block-delta measures the base-to-centre offset",
      [round(v, 6) for v in delta] == [18.0, 18.0], f"{delta}")
vm.run("c:PADDLE", [None, None])
pads = pads_of(vm, n0)
check("it kept the block the drawing already had",
      "not found" not in "".join(vm.printed))
check("the pads' CENTRES land on the same features as before",
      centres(vm, pads, delta) == EXPECTED, f"{centres(vm, pads, delta)}")
check("their insertion points are offset by the base, not the centre",
      centres(vm, pads) == sorted((c[0] - 18.0, c[1] - 18.0)
                                  for c in EXPECTED))


print("PADDLE -- no pad block anywhere makes a plain square one")
vm = with_perimeter()
n0 = len(vm.entities)
vm.run("c:PADDLE", [None, None])
check("it said it created a fallback block",
      'created a plain 36x36 square block' in "".join(vm.printed))
check("the block table now holds Pad36x36",
      "Pad36x36" in vm.tables.get("BLOCK", set()))
sq = vm.blocks.get("Pad36x36", [])
verts = [g[1:] for a in sq for g in a
         if isinstance(g, list) and g and g[0] == 10]
check("the fallback block is a 36x36 square centred on its base point",
      verts and max(abs(v[0]) for v in verts) == 18.0
      and max(abs(v[1]) for v in verts) == 18.0, f"{verts}")


print("PADDLE -- a PADS layer that is off, frozen or locked is restored")
FROZEN = '''
(entmakex (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")
                (cons 100 "AcDbLayerTableRecord") (cons 2 "PADS")
                (cons 70 5) (cons 62 -7) (cons 6 "Continuous")))
'''
vm = with_perimeter(FROZEN)
n0 = len(vm.entities)
vm.run("c:PADDLE", [None, None])
rec = vm.recdata[vm.tablerecs["LAYER"]["PADS"]]
flags = next(g.b for g in rec if isinstance(g, Dot) and g.a == 70)
col = next(g.b for g in rec if isinstance(g, Dot) and g.a == 62)
check("it said it put the layer back",
      "was off, frozen or locked" in "".join(vm.printed))
check("the layer is neither frozen nor locked", flags & 5 == 0, f"{flags}")
check("the layer is switched back on", col > 0, f"{col}")
check("and the pads still went in", len(pads_of(vm, n0)) == 5)


print("PADDLE -- a highlighted perimeter is taken as-is, without asking")
vm = with_perimeter()
n0 = len(vm.entities)
vm.loads('(sssetfirst nil (ssget "_X" (list (cons 0 "LWPOLYLINE"))))')
vm.run("c:PADDLE", [])                     # no answers at all: it must not ask
check("it never reached the select prompt",
      not any("Select perimeter" in p for p, _ in vm.prompts))
check("it did not announce an auto-detect",
      "auto-detected" not in "".join(vm.printed))
check("and it padded the same five features",
      centres(vm, pads_of(vm, n0)) == EXPECTED)


print("PADDLE -- an empty drawing says so and draws nothing")
vm = fresh()
try:
    vm.run("c:PADDLE", [None, None])
except LispError as e:
    raise AssertionError(f"[empty drawing] {e}") from None
check("it reported no closed perimeter",
      "no closed perimeter loop found" in "".join(vm.printed))
check("nothing was drawn", not pads_of(vm))
check("it never opened an undo mark it did not close", vm.undo_marks == 0)


print("PADDLE -- an open chain is ignored, and named")
OPEN_CHAIN = '''
(entmake (list (cons 0 "LINE") (cons 8 "DEMO")
               (list 10 0.0 0.0 0.0) (list 11 100.0 0.0 0.0)))
(entmake (list (cons 0 "LINE") (cons 8 "DEMO")
               (list 10 100.0 0.0 0.0) (list 11 100.0 100.0 0.0)))
'''
vm = fresh()
vm.loads(DEMO_LAYER)
vm.loads(OPEN_CHAIN)
vm.run("c:PADDLE", [None, None])
out = "".join(vm.printed)
check("it said it ignored an open chain",
      "open chain(s) that never close" in out)
check("and found no perimeter to pad",
      "no closed perimeter loop found" in out)
check("nothing was drawn", not pads_of(vm))


print("PADDLE -- Esc at the select prompt is silent and leaves nothing open")
vm = with_perimeter()
vm.handle_errors = True
before = dict(vm.sysvars)
n0 = len(vm.entities)


def _esc(_vm):
    raise LispError("Function cancelled", _vm)


try:
    vm.run("c:PADDLE", [None, _esc])
except LispError as e:
    raise AssertionError(f"[cancel] {e}") from None
check("the handler saw the cancel",
      any("cancel" in m.lower() for m in vm.handled_errors),
      f"{vm.handled_errors}")
check("a plain cancel prints no error line",
      "PADDLE error" not in "".join(vm.printed))
check("nothing was drawn", not pads_of(vm, n0))
check("every sysvar is back where it started", vm.sysvars == before)
check("no undo mark was left open", vm.undo_marks == 0)


print("TUTORIALPADDLE -- the full tour draws, pads and closes cleanly")
vm = fresh()
before = dict(vm.sysvars)
try:
    vm.run("c:TUTORIALPADDLE", [None] * 8)
except LispError as e:
    raise AssertionError(f"[full tour] {e}") from None
out = "".join(vm.printed)
check("it drew the sample perimeter on its own layer",
      any(vm.layer_of(e) == "PADDLE-DEMO" for e in vm.entities))
check("it padded the sample", len(pads_of(vm)) == 5)
check("the tour's pads sit on the same features c:PADDLE finds",
      centres(vm, pads_of(vm)) == EXPECTED)
check("it walked both padding steps",
      "Step 1 - inside corners" in out and "Step 2" in out)
check("it ended by naming the real command",
      "Type PADDLE to run it on a real drawing" in out)
check("every sysvar is back where it started", vm.sysvars == before)
check("no undo mark was left open", vm.undo_marks == 0)


print("TUTORIALPADDLE -- No at the demo question explains without drawing")
vm = fresh()
try:
    vm.run("c:TUTORIALPADDLE", [None, "No"])
except LispError as e:
    raise AssertionError(f"[no demo] {e}") from None
check("it still gave the explanation",
      "PADDLE TUTORIAL" in "".join(vm.printed))
check("nothing was drawn", not vm.entdata)
check("no undo mark was left open", vm.undo_marks == 0)


print("TUTORIALPADDLE -- Yes to the erase question takes the demo away")
vm = fresh()
try:
    vm.run("c:TUTORIALPADDLE", [None] * 7 + ["Yes"])
except LispError as e:
    raise AssertionError(f"[erase] {e}") from None
live = [e for e in vm.entities if e not in vm.deleted]
check("every entity the tour drew was erased", not live, f"{len(live)} left")
check("no undo mark was left open", vm.undo_marks == 0)


print("PADDLEVER -- reports its own banner")
vm = fresh()
vm.run("c:PADDLEVER", [])
check("PADDLEVER prints the PADDLE version",
      "PADDLE v" in "".join(vm.printed))


if failures:
    print(f"\n{len(failures)} PADDLE check(s) FAILED")
    sys.exit(1)
print("\nall PADDLE checks passed")
