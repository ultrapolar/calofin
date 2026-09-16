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
    or group left open, no raw AutoLISP message on a cancel;
  * the GAP pass: geometry that chains into a perimeter except for a
    drafting gap is recognised as one, arrowed at every open joint and
    offered a zero fillet -- and what that fillet did is read back off
    the drawing rather than assumed.  A zero-radius fillet is the one
    fillet tests/lispvm.py does for real (it cuts no arc and moves the
    two lines to where they cross, exactly as AutoCAD does), which is
    what lets a fillet that TOOK be told from one AutoCAD refused.  A
    gap whose two ends are on ONE open polyline is the exception and
    is tested as one: FILLET is never handed both picks there (it
    would join the two segments and throw away the perimeter between
    them), and the same join is made by editing the polyline instead.

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

from lispvm import VM, Dot, Ent, LispError  # noqa: E402

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


#: Four lines that would be a 300 x 200 rectangle if the last one
#: reached the first: it stops 6" short of (0,0).  One open chain, two
#: loose ends, one gap -- the case a drafter meets every week.
def _esc(_vm):
    """An Esc at whatever prompt the script has reached."""
    raise LispError("Function cancelled", _vm)


def gappy(vm, legs=None):
    for a, b in (legs or [((0, 0), (300, 0)), ((300, 0), (300, 200)),
                          ((300, 200), (0, 200)), ((0, 200), (0, 6))]):
        vm.loads('(entmake (list (cons 0 "LINE") (cons 8 "DEMO") '
                 '(list 10 %.4f %.4f 0.0) (list 11 %.4f %.4f 0.0)))'
                 % (a[0], a[1], b[0], b[1]))
    return vm


#: The tutorial's outline drawn as loose lines, with its last leg 12"
#: short of the start: the slot's two inside corners are only reachable
#: once that gap closes, which is the whole point of asking.
CORNERED = [((0, 0), (300, 0)), ((300, 0), (300, 168)), ((300, 168), (132, 168)),
            ((132, 168), (132, 120)), ((132, 120), (84, 120)),
            ((84, 120), (84, 168)), ((84, 168), (0, 168)), ((0, 168), (0, 12))]


def arrows(vm):
    return [e for e in vm.entities
            if e not in vm.deleted and vm.layer_of(e) == "PADDLE-GAP"]


def verts(vm, e):
    return [tuple(round(v, 4) for v in g[1:3])
            for g in vm.entdata.get(e, [])
            if isinstance(g, list) and g and g[0] == 10]


def fillets(vm):
    return [c for c in vm.commands if c and c[0] == "_.FILLET"]


print("PADDLE -- a perimeter that closes except for a gap is one, and says so")
vm = gappy(fresh(DEMO_LAYER))
vm.loads('(setvar "FILLETRAD" 13.5) (setvar "TRIMMODE" 0)')
before = dict(vm.sysvars)
vm.run("c:PADDLE", [None, None, "Yes"])
out = "".join(vm.printed)
check("it read the loose lines as one perimeter with a gap in it",
      "one closed perimeter with 1 gap(s) in it" in out)
check("it measured the gap and said where it is",
      'gap 1 of 1: 6" wide, at 0.00,3.00' in out)
check("it filleted at radius 0, once",
      len(fillets(vm)) == 1 and vm.sysvars["FILLETRAD"] != 0.0)
check("both picks went to FILLET as entity/point pairs",
      len(fillets(vm)[0]) == 3
      and all(isinstance(x, list) and isinstance(x[0], Ent)
              for x in fillets(vm)[0][1:]), f"{fillets(vm)}")
check("it said the gap closed", "1 gap(s) closed with a zero fillet" in out)
check("the arrow came away with the gap", not arrows(vm))
check("and the perimeter it left was read and padded",
      "auto-detected the largest closed loop" in out
      and "no concave features need pads" in out)
check("FILLETRAD and TRIMMODE are back where the drafter had them",
      vm.sysvars == before,
      {k: (before[k], vm.sysvars[k])
       for k in before if before[k] != vm.sysvars[k]})
check("no undo mark was left open", vm.undo_marks == 0)


print("PADDLE -- the arrow points at the gap, from outside the loop")
vm = gappy(fresh(DEMO_LAYER))
vm.run("c:PADDLE", [None, None, "No"])
arw = arrows(vm)
check("one arrow, one gap", len(arw) == 1, f"{len(arw)}")
vs = verts(vm, arw[0])
check("it is a closed polyline of seven points",
      len(vs) == 7 and dxf(vm, arw[0], 70) == 1, f"{vs}")
check("its tip is on the gap", vs[0] == (0.0, 3.0), f"{vs[0]}")
#: the loop's middle is (150,100); an arrow flying in from outside has
#: every other point of it further from that middle than its tip
check("every other point of it is further out than the tip",
      all(math.dist(v, (150.0, 100.0)) > math.dist(vs[0], (150.0, 100.0))
          for v in vs[1:]), f"{vs}")


print("PADDLE -- No leaves the arrow standing and fillets nothing")
check("it asked before touching anything", not fillets(vm))
check("the arrow is still there", len(arrows(vm)) == 1)
check("the lines are where the drafter drew them",
      [0.0, 6.0] in [dxf(vm, e, 11)[:2] for e in vm.entities
                     if dxf(vm, e, 0) == "LINE"])
check("it said the gap was left, and why nothing was padded",
      "1 gap(s) left as they are" in "".join(vm.printed)
      and "no closed perimeter loop found" in "".join(vm.printed))


print("PADDLE -- Enter at the gap question takes the default, Yes")
vm = gappy(fresh(DEMO_LAYER))
vm.run("c:PADDLE", [None, None, None])
check("Enter closed the gap", len(fillets(vm)) == 1 and not arrows(vm))


print("PADDLE -- a wall run past its neighbour is trimmed, not the perimeter")
#: the last leg is a 30" stub that crosses the first wall 10" along and
#: sticks 20" out past it.  FILLET keeps the side it was picked on, so
#: a pick in the middle of that stub would keep the overshoot and trim
#: the stub off the perimeter instead; the pick goes nine tenths of the
#: way IN from the loose end for exactly that reason.
vm = gappy(fresh(DEMO_LAYER),
           [((0, 0), (300, 0)), ((300, 0), (300, 200)), ((300, 200), (0, 200)),
            ((0, 200), (0, 10)), ((0, 10), (0, -20))])
vm.run("c:PADDLE", [None, None, "Yes"])
stub = [e for e in vm.entities if dxf(vm, e, 0) == "LINE"
        and dxf(vm, e, 10)[:2] == [0.0, 10.0]]
check("the overshoot came off at the crossing",
      len(stub) == 1 and dxf(vm, stub[0], 11)[:2] == [0.0, 0.0],
      f"{[dxf(vm, e, 11) for e in stub]}")
check("the wall it was still attached to did not move",
      [0.0, 10.0] in [dxf(vm, e, 11)[:2] for e in vm.entities
                      if dxf(vm, e, 0) == "LINE"])
check("and the perimeter it left is the one that was padded",
      "auto-detected the largest closed loop" in "".join(vm.printed)
      and not arrows(vm))


print("PADDLE -- two gaps exactly as wide as each other are both found")
#: a wall left short at BOTH ends leaves two gaps of the same width,
#: which is the commonest two-gap case there is and the one a vl-sort
#: of the candidate pairs would lose: vl-sort drops an element that
#: compares equal to another under the predicate it is handed, and a
#: ring with a gap missing is not a ring, so neither arrow would go in.
vm = gappy(fresh(DEMO_LAYER),
           [((0, 0), (300, 0)), ((0, 20), (300, 20))])
vm.run("c:PADDLE", [None, None, "No", "No"])
out = "".join(vm.printed)
check("both gaps were found", "one closed perimeter with 2 gap(s)" in out)
check("both are 20 wide, at the two ends of the pair of walls",
      'gap 1 of 2: 20" wide, at 300.00,10.00' in out
      and 'gap 2 of 2: 20" wide, at 0.00,10.00' in out, out)
check("and both were arrowed", len(arrows(vm)) == 2, f"{len(arrows(vm))}")


print("PADDLE -- a fillet AutoCAD refuses is reported, not assumed")
#: a C whose two open ends are parallel and 6 apart: they never cross,
#: so FILLET cannot join them however far they run on.  The other gap
#: in the same run is an ordinary one, and closes.
vm = gappy(fresh(DEMO_LAYER),
           [((0, 0), (300, 0)), ((300, 0), (300, 200)), ((300, 200), (0, 200)),
            ((0, 200), (0, 120)), ((6, 100), (6, 0))])
vm.run("c:PADDLE", [None, None, "Yes", "Yes"])
out = "".join(vm.printed)
check("it found both gaps", "one closed perimeter with 2 gap(s)" in out)
check("it tried both", len(fillets(vm)) == 2, f"{len(fillets(vm))}")
check("it said which one FILLET would not close",
      "FILLET would not close 1 gap(s)" in out)
check("the refused gap keeps its arrow, the closed one does not",
      len(arrows(vm)) == 1, f"{len(arrows(vm))}")
check("and it did not claim a perimeter it has not got",
      "no closed perimeter loop found" in out)


print("PADDLE -- an open polyline is joined in place, not handed to FILLET")
#: the pool outline drawn as ONE polyline that stops 6" short of its
#: own start -- the commonest near-miss there is.  FILLET must not be
#: asked for this one: two picks on one polyline joins those two
#: segments and throws away every segment between them, which here is
#: the perimeter.  PADDLE makes the same join by editing the polyline:
#: first vertex to the crossing, last vertex away, closed flag on.
OPEN_PL = ('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
           ' (cons 8 "DEMO") (cons 100 "AcDbPolyline") (cons 90 9) (cons 70 0)'
           ' (list 10 0.0 0.0) (list 10 300.0 0.0) (list 10 300.0 168.0)'
           ' (list 10 132.0 168.0) (list 10 132.0 120.0) (list 10 84.0 120.0)'
           ' (list 10 84.0 168.0) (list 10 0.0 168.0) (list 10 0.0 6.0)))')
vm = fresh(DEMO_LAYER)
vm.loads(OPEN_PL)
pl = vm.entities[0]
n0 = len(vm.entities)
vm.run("c:PADDLE", [None, None, "Yes"])
out = "".join(vm.printed)
check("it said it would join the polyline itself",
      "both ends are on one polyline" in out)
check("it issued no FILLET", not fillets(vm))
check("the polyline is closed now", dxf(vm, pl, 70) == 1)
check("its last vertex went, and the count went with it",
      dxf(vm, pl, 90) == 8 and len(verts(vm, pl)) == 8,
      f"{dxf(vm, pl, 90)} {verts(vm, pl)}")
check("the join is at the crossing of the two end segments",
      verts(vm, pl)[0] == (0.0, 0.0), f"{verts(vm, pl)[0]}")
check("the arrow came away, and the slot got its pads",
      not arrows(vm) and centres(vm, pads_of(vm, n0)) == sorted(CORNERS),
      f"{centres(vm, pads_of(vm, n0))}")


print("PADDLE -- the crossing the polyline is joined at is measured, not guessed")
#: the same polyline with its last leg running in at an angle: the two
#: end segments cross at a point that is on neither of them yet, and
#: that point -- not the loose end, not the first vertex -- is where
#: the join lands, exactly as a zero fillet would leave it
vm = fresh(DEMO_LAYER)
vm.loads('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
         ' (cons 8 "DEMO") (cons 100 "AcDbPolyline") (cons 90 5) (cons 70 0)'
         ' (list 10 0.0 0.0) (list 10 300.0 0.0) (list 10 300.0 200.0)'
         ' (list 10 0.0 200.0) (list 10 6.0 20.0)))')
pl = vm.entities[0]
vm.run("c:PADDLE", [None, None, "Yes"])
check("the first vertex moved to where the ends cross",
      verts(vm, pl)[0] == (6.6667, 0.0), f"{verts(vm, pl)[0]}")
check("and the polyline came out closed, one vertex shorter",
      dxf(vm, pl, 70) == 1 and len(verts(vm, pl)) == 4, f"{verts(vm, pl)}")


print("PADDLE -- one entity it cannot join in place is named, never filleted")
#: an arc at one end of the gap.  The edit above is a straight-to-
#: straight join; anything else on one entity (an arc end, a heavy 2D
#: POLYLINE, two ends that never cross) is marked and named instead --
#: what must never happen is FILLET being handed both picks.
vm = fresh(DEMO_LAYER)
vm.loads('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
         ' (cons 8 "DEMO") (cons 100 "AcDbPolyline") (cons 90 5) (cons 70 0)'
         ' (list 10 0.0 0.0) (list 10 300.0 0.0) (list 10 300.0 200.0)'
         ' (list 10 0.0 200.0) (cons 42 -0.3) (list 10 0.0 6.0)))')
vm.run("c:PADDLE", [None, None])            # no answer: it must not ask
out = "".join(vm.printed)
check("it still recognised the perimeter and marked the gap",
      "one closed perimeter with 1 gap(s)" in out and len(arrows(vm)) == 1)
check("it never asked", not any("zero fillet" in p for p, _ in vm.prompts))
check("it issued no FILLET", not fillets(vm))
check("it said why, and what to do instead",
      "both ends are on one entity" in out and "PEDIT > Close" in out)


print("PADDLE -- a handed-over selection is still the only geometry read")
#: the re-read after a fillet is the moment a run could quietly widen
#: to the whole drawing.  Here the perimeter is handed over pickfirst
#: (what LINGUTTER does) with a title block border sitting around it:
#: auto-detect would take the border as the largest closed loop, so the
#: border must not be read at all -- before the fillet or after it.
vm = gappy(fresh(DEMO_LAYER), CORNERED)
vm.loads('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
         ' (cons 8 "DEMO") (cons 100 "AcDbPolyline") (cons 90 4) (cons 70 1)'
         ' (list 10 -500.0 -500.0) (list 10 900.0 -500.0)'
         ' (list 10 900.0 900.0) (list 10 -500.0 900.0)))')
n0 = len(vm.entities)
vm.loads('(sssetfirst nil (ssget "_X" (list (cons 0 "LINE"))))')
vm.run("c:PADDLE", ["Yes"])                 # one answer: the gap question
out = "".join(vm.printed)
check("it never reached the select prompt",
      not any("Select perimeter" in p for p, _ in vm.prompts))
check("it found the gap in what it was handed",
      "one closed perimeter with 1 gap(s)" in out and "1 gap(s) closed" in out)
check("the re-read did not widen to the whole drawing",
      "auto-detected" not in out)
check("and the pads went on the perimeter, not the border",
      centres(vm, pads_of(vm, n0)) == sorted(CORNERS),
      f"{centres(vm, pads_of(vm, n0))}")


print("PADDLE -- a gap too wide to be a drafting gap is left alone")
vm = gappy(fresh(DEMO_LAYER),
           [((0, 0), (300, 0)), ((300, 0), (300, 200)), ((300, 200), (0, 200)),
            ((0, 200), (0, 120))])          # 120 short: a missing wall
vm.run("c:PADDLE", [None, None])
out = "".join(vm.printed)
check("it went back to the plain report",
      "open chain(s) that never close back on themselves" in out)
check("no arrow, no question", not arrows(vm)
      and not any("zero fillet" in p for p, _ in vm.prompts))


print("PADDLE -- a perimeter beside a smaller closed loop is not the loop")
#: the gap only gets an arrow when what it would close is BIGGER than
#: anything already closed -- otherwise the drafter has a perimeter and
#: this is something loose lying beside it
vm = gappy(fresh(DEMO_LAYER),
           [((0, 0), (30, 0)), ((30, 0), (30, 20)), ((30, 20), (0, 20)),
            ((0, 20), (0, 6)),                          # a 30 x 20 near-loop
            ((100, 0), (400, 0)), ((400, 0), (400, 300)),
            ((400, 300), (100, 300)), ((100, 300), (100, 0))])   # closed
vm.run("c:PADDLE", [None, None])
check("the closed loop won and the near-loop was only reported",
      not arrows(vm)
      and "open chain(s) that never close" in "".join(vm.printed))


print("PADDLE -- the arrows are PADDLE's own: cleared and re-marked each run")
vm = gappy(fresh(DEMO_LAYER))
vm.run("c:PADDLE", [None, None, "No"])
first = arrows(vm)
vm.printed = []
vm.run("c:PADDLE", [None, None, "No"])
check("last run's arrow was taken away", all(e in vm.deleted for e in first))
check("and this run drew its own", len(arrows(vm)) == 1
      and arrows(vm) != first)
check("the arrow was never read back as perimeter geometry",
      "one closed perimeter with 1 gap(s)" in "".join(vm.printed))


print("PADDLE -- the pads go in on the perimeter the fillet closed")
vm = gappy(fresh(DEMO_LAYER), CORNERED)
n0 = len(vm.entities)
vm.run("c:PADDLE", [None, None, "Yes"])
check("the two inside corners were padded once the gap closed",
      centres(vm, pads_of(vm, n0)) == sorted(CORNERS),
      f"{centres(vm, pads_of(vm, n0))}")
check("and no arrow was left over", not arrows(vm))


print("PADDLE -- Esc at the gap question leaves the arrows and the session")
vm = gappy(fresh(DEMO_LAYER))
vm.loads('(setvar "FILLETRAD" 13.5) (setvar "TRIMMODE" 0)')
vm.handle_errors = True
before = dict(vm.sysvars)
vm.run("c:PADDLE", [None, None, _esc])
check("the handler saw the cancel",
      any("cancel" in m.lower() for m in vm.handled_errors))
check("a plain cancel prints no error line",
      "PADDLE error" not in "".join(vm.printed))
check("the arrow stays -- it is what the drafter works from next",
      len(arrows(vm)) == 1)
check("every sysvar is back where it started", vm.sysvars == before,
      {k: (before[k], vm.sysvars[k])
       for k in before if before[k] != vm.sysvars[k]})
check("no undo mark was left open", vm.undo_marks == 0)


print("PADDLE -- Esc at the select prompt is silent and leaves nothing open")
vm = with_perimeter()
vm.handle_errors = True
before = dict(vm.sysvars)
n0 = len(vm.entities)


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
