#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for MOHAMADDLE: c:MOHAMADDLE driven end-to-end in the
VM, on the same feature geometry tests/test_paddle.py uses.

MOHAMADDLE is PADDLE's own engine (chaining, feature detection, the
no-overlap dodge, the block-resolution fallback) with one new thing in
front of it: a prompt asking which pad size to place. This file does
not re-verify the geometry rules PADDLE already proves -- test_paddle.py
covers those, and MOHAMADDLE's engine is a straight port -- it verifies
the part that is actually new:

  * the size prompt is the FIRST thing asked, before any selection;
  * "24" places 24x24 pads (block Pad24x24), "36" places 36x36 pads
    (block Pad36x36), and pressing Enter takes the default;
  * a run remembers the size it was given and offers THAT as the
    default the next time it is asked, in the same session;
  * every exit hands the session back: sysvars unchanged, no undo mark
    left open, no raw AutoLISP message on a cancel;
  * PADDLE's GAP pass came over with the engine and is reached through
    this command's own prompts: geometry that chains into a perimeter
    except for a drafting gap is arrowed and offered a zero fillet
    before the pads go in, and the arrows land on PADDLE's own layer
    because the two tools mark the same thing in the same drawing.
    The rules behind it are PADDLE's and are proved there
    (test_paddle.py); what is checked here is that the pass is wired
    into MOHAMADDLE at all, and that it sits AFTER the size pick.

Run: python3 tests/test_mohamaddle.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_mohamaddle.py
"""

import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

LISP_ROOT = os.path.join(REPO_DIR, os.environ.get("CALOFIN_LISP_ROOT", "lisp"))
MOHAMADDLE = os.path.join(LISP_ROOT, "mohamaddle", "MOHAMADDLE.lsp")
LIB = None
if os.path.basename(LISP_ROOT) == "shared":
    PARTS = os.path.join(LISP_ROOT, "parts")
    MOHAMADDLE = os.path.join(PARTS, "MOHAMADDLE.lsp")
    LIB = os.path.join(PARTS, "CALOFIN-LIB.lsp")

from lispvm import VM, Dot, LispError  # noqa: E402

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


#: A layer for the sample perimeter to sit on -- the same slot-plus-arc
#: sample test_paddle.py's tutorial draws, built directly here since
#: MOHAMADDLE carries no tutorial/demo of its own.
DEMO_LAYER = '''
(entmakex (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")
                (cons 100 "AcDbLayerTableRecord") (cons 2 "DEMO")
                (cons 70 0) (cons 62 3) (cons 6 "Continuous")))
'''

#: straight walls, a 2-degree kink (ignored), convex corners (ignored),
#: a rectangular slot with two 90-degree inside corners (padded), a
#: concave R4'-0" bite (padded row) and a concave R6'-0" sweep (too
#: big -- no pads).  Vertex list identical to PADDLE's own tutorial demo.
PERIMETER = '''
(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity") (cons 8 "DEMO")
               (cons 100 "AcDbPolyline") (cons 90 13) (cons 70 1)
               (list 10 0.0 0.0)     (list 10 150.0 3.0)  (list 10 300.0 0.0)
               (list 10 300.0 168.0) (list 10 264.0 168.0) (cons 42 -1.0)
               (list 10 168.0 168.0) (list 10 132.0 168.0)
               (list 10 132.0 120.0) (list 10 84.0 120.0)
               (list 10 84.0 168.0)  (list 10 0.0 168.0)
               (list 10 0.0 134.0)   (cons 42 -0.4038)
               (list 10 0.0 34.0)))
'''


def fresh(extra=""):
    """A VM with MOHAMADDLE loaded (on the library, at the grouped tier)."""
    vm = VM()
    if LIB:
        vm.load(LIB)
    vm.load(MOHAMADDLE)
    if extra:
        vm.loads(extra)
    return vm


def with_perimeter(extra=""):
    vm = fresh(extra)
    vm.loads(DEMO_LAYER)
    vm.loads(PERIMETER)
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


CORNERS = [(84.0, 120.0), (132.0, 120.0)]
ARC_ROW = [(180.0, 136.251), (216.0, 120.0), (252.0, 136.251)]
EXPECTED = sorted(CORNERS + ARC_ROW)


def centres(vm, pads):
    return sorted((round(dxf(vm, e, 10)[0], 4), round(dxf(vm, e, 10)[1], 4))
                  for e in pads)


print("MOHAMADDLE -- the size prompt is the FIRST thing asked")
vm = with_perimeter()
try:
    vm.run("c:MOHAMADDLE", ["24", None, None])
except LispError as e:
    raise AssertionError(f"[first prompt] {e}") from None
check("the size prompt came before the perimeter prompt",
      vm.prompts and "Pad size" in vm.prompts[0][0], f"{vm.prompts[:1]}")


print("MOHAMADDLE -- \"36\" places 36x36 pads on the same features PADDLE finds")
vm = with_perimeter()
n0 = len(vm.entities)
vm.run("c:MOHAMADDLE", ["36", None, None])
pads = pads_of(vm, n0)
check("five pads went in", len(pads) == 5, f"got {len(pads)}")
check("every pad is the Pad36x36 block",
      {dxf(vm, e, 2) for e in pads} == {"Pad36x36"})
check("every pad is on the PADS layer",
      {vm.layer_of(e) for e in pads} == {"PADS"})
check("the pads sit on the same features PADDLE finds at 36in",
      centres(vm, pads) == EXPECTED, f"{centres(vm, pads)}")
check("it reported the 36in size",
      '36" pad' in "".join(vm.printed), "".join(vm.printed))


print("MOHAMADDLE -- \"24\" places 24x24 pads instead, still on the corners")
vm = with_perimeter()
n0 = len(vm.entities)
vm.run("c:MOHAMADDLE", ["24", None, None])
pads = pads_of(vm, n0)
check("every pad is the Pad24x24 block",
      {dxf(vm, e, 2) for e in pads} == {"Pad24x24"})
check("a smaller pad pitch fits more pads along the same arc",
      len(pads) > 5, f"got {len(pads)}")
check("the two inside-corner pads land in the same place regardless of size",
      set(CORNERS) <= set(centres(vm, pads)), f"{centres(vm, pads)}")
check("it reported the 24in size",
      '24" pad' in "".join(vm.printed), "".join(vm.printed))


print("MOHAMADDLE -- Enter at the size prompt takes the default (36 first time)")
vm = with_perimeter()
n0 = len(vm.entities)
vm.run("c:MOHAMADDLE", [None, None, None])
pads = pads_of(vm, n0)
check("the default size is 36",
      {dxf(vm, e, 2) for e in pads} == {"Pad36x36"})


print("MOHAMADDLE -- the size just picked becomes the next default in the session")
vm = with_perimeter()
n0 = len(vm.entities)
vm.run("c:MOHAMADDLE", ["24", None, None])
n1 = len(vm.entities)
vm.loads(PERIMETER)                          # a second perimeter to pad
vm.run("c:MOHAMADDLE", [None, None, None])   # Enter: should default to 24 now
pads = pads_of(vm, n1)
check("the second run defaulted to the size picked in the first",
      {dxf(vm, e, 2) for e in pads} == {"Pad24x24"}, f"{[dxf(vm, e, 2) for e in pads]}")


print("MOHAMADDLE -- Esc at the size prompt is silent and leaves nothing open")
vm = with_perimeter()
vm.handle_errors = True
before = dict(vm.sysvars)
n0 = len(vm.entities)


def _esc(_vm):
    raise LispError("Function cancelled", _vm)


try:
    vm.run("c:MOHAMADDLE", [_esc])
except LispError as e:
    raise AssertionError(f"[cancel at size prompt] {e}") from None
check("the handler saw the cancel",
      any("cancel" in m.lower() for m in vm.handled_errors),
      f"{vm.handled_errors}")
check("a plain cancel prints no error line",
      "MOHAMADDLE error" not in "".join(vm.printed))
check("nothing was drawn", not pads_of(vm, n0))
check("every sysvar is back where it started", vm.sysvars == before)
check("no undo mark was left open", vm.undo_marks == 0)


print("MOHAMADDLE -- no pad block anywhere makes a plain square one, sized to the pick")
vm = with_perimeter()
n0 = len(vm.entities)
vm.run("c:MOHAMADDLE", ["24", None, None])
check("it said it created a fallback block",
      "created a plain 24x24 square block" in "".join(vm.printed))
sq = vm.blocks.get("Pad24x24", [])
verts = [g[1:] for a in sq for g in a
         if isinstance(g, list) and g and g[0] == 10]
check("the fallback block is a 24x24 square centred on its base point",
      verts and max(abs(v[0]) for v in verts) == 12.0
      and max(abs(v[1]) for v in verts) == 12.0, f"{verts}")


#: the same slot outline as loose lines, with the last leg 12" short of
#: the start: one open chain, two loose ends, one gap.
GAPPY = [((0, 0), (300, 0)), ((300, 0), (300, 168)), ((300, 168), (132, 168)),
         ((132, 168), (132, 120)), ((132, 120), (84, 120)),
         ((84, 120), (84, 168)), ((84, 168), (0, 168)), ((0, 168), (0, 12))]


def gappy(vm, legs=None):
    for a, b in (legs or GAPPY):
        vm.loads('(entmake (list (cons 0 "LINE") (cons 8 "DEMO") '
                 '(list 10 %.4f %.4f 0.0) (list 11 %.4f %.4f 0.0)))'
                 % (a[0], a[1], b[0], b[1]))
    return vm


def arrows(vm):
    return [e for e in vm.entities
            if e not in vm.deleted and vm.layer_of(e) == "PADDLE-GAP"]


print("MOHAMADDLE -- the gap pass came over with the engine")
vm = gappy(fresh(DEMO_LAYER))
vm.loads('(setvar "FILLETRAD" 13.5) (setvar "TRIMMODE" 0)')
before = dict(vm.sysvars)
n0 = len(vm.entities)
vm.run("c:MOHAMADDLE", ["36", None, None, "Yes"])
out = "".join(vm.printed)
check("the size pick still came first",
      vm.prompts and "Pad size" in vm.prompts[0][0], f"{vm.prompts[:1]}")
check("it read the loose lines as one perimeter with a gap in it",
      "one closed perimeter with 1 gap(s) in it" in out)
check("it measured the gap and said where",
      'gap 1 of 1: 12" wide, at 0.00,6.00' in out)
check("the gap question came after the size pick",
      [p for p, _ in vm.prompts if "zero fillet" in p]
      and "Pad size" in vm.prompts[0][0])
check("it filleted at radius 0, once",
      len([c for c in vm.commands if c and c[0] == "_.FILLET"]) == 1)
check("it said the gap closed", "1 gap(s) closed with a zero fillet" in out)
check("the arrow came away with the gap", not arrows(vm))
check("and the pads went in on the perimeter that left",
      centres(vm, pads_of(vm, n0)) == sorted(CORNERS),
      f"{centres(vm, pads_of(vm, n0))}")
check("FILLETRAD and TRIMMODE are back where the drafter had them",
      vm.sysvars == before,
      {k: (before[k], vm.sysvars[k])
       for k in before if before[k] != vm.sysvars[k]})
check("no undo mark was left open", vm.undo_marks == 0)


print("MOHAMADDLE -- No leaves the arrow standing, on PADDLE's own layer")
vm = gappy(fresh(DEMO_LAYER))
n0 = len(vm.entities)
vm.run("c:MOHAMADDLE", ["36", None, None, "No"])
check("nothing was filleted",
      not [c for c in vm.commands if c and c[0] == "_.FILLET"])
check("the arrow is there, and it is PADDLE's layer it is on",
      len(arrows(vm)) == 1, f"{len(arrows(vm))}")
check("no pads went in - there is no closed perimeter yet",
      not pads_of(vm, n0)
      and "no closed perimeter loop found" in "".join(vm.printed))


print("MOHAMADDLE -- a closed perimeter is never asked about")
vm = with_perimeter()
n0 = len(vm.entities)
vm.run("c:MOHAMADDLE", ["36", None, None])   # no gap answer to give
check("it never asked", not any("zero fillet" in p for p, _ in vm.prompts))
check("no arrow was drawn", not arrows(vm))
check("and it padded the five features", len(pads_of(vm, n0)) == 5)


print("MOHAMADDLEVER -- reports its own banner")
vm = fresh()
vm.run("c:MOHAMADDLEVER", [])
check("MOHAMADDLEVER prints the MOHAMADDLE version",
      "MOHAMADDLE v" in "".join(vm.printed))


if failures:
    print(f"\n{len(failures)} MOHAMADDLE check(s) FAILED")
    sys.exit(1)
print("\nall MOHAMADDLE checks passed")
