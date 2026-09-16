#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for UPADOVER: the real file loaded into the repo's
AutoLISP interpreter and c:UPADOVER driven end to end from a script.

UPADOVER makes one promise and the promise is geometric, so most of this
file is geometry: from the point you name round to the point you name,
the wall comes out UNDER pads -- no overlap anywhere, no gap between one
pad and the next, and nothing of the run left bare.  Each of those three
is checked here as a fact about the pads that landed: none overlapping
another, all of them one block joined edge to edge (a pair meeting at a
corner is not joined, which is the break the bridging pads exist to
stop), and no sampled point of the run outside every pad.  On five
shapes that break covers in different ways:

  * a straight wall, where the answer is an obvious flush row;
  * a run round a 90-degree corner, where the row has to turn;
  * a wall at 45 degrees, which crosses a grid CORNER every pad -- the
    case where two pads touching at a point would look like a cover and
    be a break, and where the bridging pads exist;
  * an arc, where the row stair-steps;
  * a notch the run doubles back through, where the same pad has to
    serve both passes rather than being laid twice.

The rest is the question-and-answer layer it shares with PERPMARK and
ABHD: an end named by clicking it or by typing its number ("17",
"Pt.17", "pt 17", "#17", "017" are one point), the shorter way round
taken without asking, the ambiguous way round asked with one click, and
every refusal re-asked where it stands rather than guessed at.

Run: python3 tests/test_upadover.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_upadover.py
"""

import math
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)

LISP_ROOT = os.path.join(REPO_DIR, os.environ.get("CALOFIN_LISP_ROOT", "lisp"))
UPADOVER = os.path.join(LISP_ROOT, "upadover", "UPADOVER.lsp")
LIB = None
if os.path.basename(LISP_ROOT) == "shared":
    PARTS = os.path.join(LISP_ROOT, "parts")
    UPADOVER = os.path.join(PARTS, "UPADOVER.lsp")
    LIB = os.path.join(PARTS, "CALOFIN-LIB.lsp")

from lispvm import VM, Ent, Dot, LispError  # noqa: E402

PAD = 36.0
HALF = PAD / 2.0

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


# ---- drawing scaffolding ---------------------------------------------

def fresh(extra=""):
    vm = VM()
    if LIB:
        vm.load(LIB)
    vm.load(UPADOVER)
    if extra:
        vm.loads(extra)
    return vm


def pline(vm, pts, closed=True, layer="POOL"):
    """An LWPOLYLINE.  PTS entries are (x, y) or (x, y, bulge)."""
    e = Ent()
    vm.entities.append(e)
    d = [Dot(0, "LWPOLYLINE"), Dot(8, layer), Dot(90, len(pts)),
         Dot(70, 1 if closed else 0)]
    for p in pts:
        d.append([10, float(p[0]), float(p[1])])
        if len(p) > 2:
            d.append(Dot(42, float(p[2])))
    vm.entdata[e] = d
    return e


def ab_pt(vm, x, y, number, layer="POINTS", block="ab_pt", tag="number"):
    """A survey point: the INSERT and the ATTRIB naming it."""
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, "INSERT"), Dot(8, layer), Dot(2, block),
                     [10, float(x), float(y), 0.0]]
    if number is not None:
        att = Ent()
        vm.entities.append(att)
        vm.entdata[att] = [Dot(0, "ATTRIB"), Dot(2, tag), Dot(1, str(number))]
    return e


#: The reference pool: 240 x 120, drawn from its bottom-left corner
#: counterclockwise, so the bottom wall runs station 0 -> 240 and the
#: whole loop is 720.
def rect(vm, **kw):
    return pline(vm, [(0, 0), (240, 0), (240, 120), (0, 120)], **kw)


def dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


def pad_ents(vm, since=0):
    return [e for e in vm.entities[since:]
            if e not in vm.deleted and dxf(vm, e, 0) == "INSERT"
            and dxf(vm, e, 2) == "Pad36x36"]


def centres(vm, since=0, delta=(0.0, 0.0)):
    """Where each pad actually sits, in the order they went in: the
    insertion point plus the offset from the block's base to the centre
    of its extents."""
    return [(round(dxf(vm, e, 10)[0] + delta[0], 6),
             round(dxf(vm, e, 10)[1] + delta[1], 6))
            for e in pad_ents(vm, since)]


def run(vm, script, label="UPADOVER"):
    try:
        vm.run("c:UPADOVER", list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def said(vm, text):
    return any(text in s for s in vm.printed)


def asked(vm, text):
    return any(text in p for p, _ in vm.prompts)


# ---- what the pads have to be ----------------------------------------

def overlaps(cs):
    """Pairs of pads that share any area.  Axis-aligned squares of side
    PAD overlap exactly when their centres are closer than PAD in
    CHEBYSHEV distance -- asserting straight-line distance would pass a
    diagonal pair that laps a ninth of its neighbour."""
    return [(a, b) for i, a in enumerate(cs) for b in cs[i + 1:]
            if max(abs(a[0] - b[0]), abs(a[1] - b[1])) < PAD - 1e-6]


def shares_edge(a, b):
    """Two pads meeting along a whole edge: one step of exactly one pad
    width along one axis and nothing along the other.  A diagonal step
    touches at a CORNER instead, which is the break the bridging pads
    exist to stop, so it is not an edge here."""
    dx, dy = abs(a[0] - b[0]), abs(a[1] - b[1])
    return ((abs(dx - PAD) < 1e-6 and dy < 1e-6)
            or (abs(dy - PAD) < 1e-6 and dx < 1e-6))


def loose_seams(cs):
    """Consecutive pads, in the order they went in, that do not share a
    full edge.  That order is the order the run walked them, so this is
    the shape of the cover: a staircase rather than a diagonal string.
    (A run that doubles back can land two pads in a row that are each
    edge-to-edge with an EARLIER pad and not with each other -- which is
    still a sound cover, and why the connectivity check below is the one
    that speaks for every run.)"""
    return [(a, b) for a, b in zip(cs, cs[1:]) if not shares_edge(a, b)]


def loose_pads(cs):
    """Pads no chain of full-edge contacts reaches from the first one.

    This is "no breaks between pads" as a property of the finished
    cover rather than of the order it went in: every pad is joined to
    every other through shared edges, so two pads meeting at a corner
    with the wall threading the junction between them cannot pass.
    """
    seen, stack = {0}, [0]
    while stack:
        i = stack.pop()
        for j, b in enumerate(cs):
            if j not in seen and shares_edge(cs[i], b):
                seen.add(j)
                stack.append(j)
    return [c for j, c in enumerate(cs) if j not in seen]


def bare(cs, samples):
    """Points of the run that no pad covers."""
    return [p for p in samples
            if not any(abs(p[0] - c[0]) <= HALF + 1e-9
                       and abs(p[1] - c[1]) <= HALF + 1e-9 for c in cs)]


def walk_pts(*legs):
    """A run sampled every quarter inch.  Each leg is (from, to) for a
    straight stretch, or (centre, radius, a0, a1) for an arc."""
    out = []
    for leg in legs:
        if len(leg) == 2:
            (x0, y0), (x1, y1) = leg
            n = max(1, int(math.dist((x0, y0), (x1, y1)) * 4))
            out += [(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n)
                    for i in range(n + 1)]
        else:
            (cx, cy), r, a0, a1 = leg
            n = max(1, int(abs(a1 - a0) * r * 4))
            out += [(cx + r * math.cos(a0 + (a1 - a0) * i / n),
                     cy + r * math.sin(a0 + (a1 - a0) * i / n))
                    for i in range(n + 1)]
    return out


def covers(label, vm, n0, samples, delta=(0.0, 0.0)):
    """The whole promise, on one run: no overlap, no loose seam, nothing
    of the wall left bare."""
    cs = centres(vm, n0, delta)
    check(f"{label}: no two pads overlap", not overlaps(cs),
          f"{overlaps(cs)[:2]}")
    check(f"{label}: the pads are one block, joined edge to edge",
          not loose_pads(cs), f"{loose_pads(cs)[:2]}")
    check(f"{label}: the whole run is under pads", not bare(cs, samples),
          f"{len(bare(cs, samples))} of {len(samples)} bare, "
          f"first {bare(cs, samples)[:1]}")
    return cs


# ---- the straight row -------------------------------------------------

print("UPADOVER -- a straight wall, named by two survey points")
vm = fresh()
per = rect(vm)
ab_pt(vm, 0, 0, 1)
ab_pt(vm, 240, 0, 2)
n0 = len(vm.entities)
run(vm, [per, "1", "2"], "straight")
cs = covers("straight wall", vm, n0, walk_pts(((0, 0), (240, 0))))
check("each pad shares an edge with the one that went in before it",
      not loose_seams(cs), f"{loose_seams(cs)[:2]}")
check("the row is the eight pads the run needs",
      cs == [(x, 0.0) for x in (0, 36, 72, 108, 144, 180, 216, 252)], f"{cs}")
check("the first pad is centred on the start itself", cs[0] == (0.0, 0.0))
check("the last pad runs PAST the end rather than stopping short",
      cs[-1][0] > 240.0 and cs[-1][0] - HALF <= 240.0, f"{cs[-1]}")
check("every pad is the pad block", all(dxf(vm, e, 2) == "Pad36x36"
                                        for e in pad_ents(vm, n0)))
check("every pad is on the PADS layer",
      {vm.layer_of(e) for e in pad_ents(vm, n0)} == {"PADS"})
check("every pad is square to the X/Y axes",
      all(abs(dxf(vm, e, 50) or 0.0) < 1e-9 for e in pad_ents(vm, n0)))
check("it reported the count, the layer and the run",
      said(vm, '8 36" pad(s) on layer "PADS", covering 20\'-0"'))
check("and which two points it ran between",
      said(vm, "from Pt.1 to Pt.2"))


# ---- round a corner ---------------------------------------------------

print("UPADOVER -- a run that turns a 90-degree corner")
vm = fresh()
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, [100.0, 0.0, 0.0], [240.0, 80.0, 0.0]], "corner")
covers("round a corner", vm, n0,
       walk_pts(((100, 0), (240, 0)), ((240, 0), (240, 80))))
check("the run is measured along the wall, not across it",
      said(vm, "covering 18'-4\""))


# ---- 45 degrees: the case a corner-touching cover would break on ------

print("UPADOVER -- a wall at 45 degrees, where the grid corners are")
vm = fresh()
per = pline(vm, [(0, 0), (200, 200), (0, 400)], closed=False)
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [200.0, 200.0, 0.0]], "45 degrees")
cs = covers("45 degrees", vm, n0, walk_pts(((0, 0), (200, 200))))
check("it went in as a staircase, not a diagonal string",
      len(cs) == 13 and not loose_seams(cs),
      f"{len(cs)} pads, loose {loose_seams(cs)[:2]}")
check("it said how many pads bridge a corner crossing",
      said(vm, "bridge a grid corner"))


# ---- an arc -----------------------------------------------------------

print("UPADOVER -- a half circle, stair-stepped")
vm = fresh()
per = pline(vm, [(0, 0, 1.0), (200, 0)], closed=False)   # r=100, below
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [200.0, 0.0, 0.0]], "arc")
covers("half circle", vm, n0,
       walk_pts((((100, 0), 100, math.pi, 2 * math.pi))))
check("the arc's own length is what it reports, not the chord's",
      said(vm, "covering 26'-2\""))


print("UPADOVER -- a round spa, which is one CIRCLE and no vertices")
vm = fresh()
per = Ent()
vm.entities.append(per)
vm.entdata[per] = [Dot(0, "CIRCLE"), Dot(8, "SPA"), [10, 0.0, 0.0, 0.0],
                   Dot(40, 60.0)]
n0 = len(vm.entities)
run(vm, [per, [60.0, 0.0, 0.0], [0.0, 60.0, 0.0]], "circle")
covers("a circle", vm, n0, walk_pts((((0, 0), 60, 0.0, math.pi / 2))))
check("a circle closes on itself, so the shorter quarter is taken",
      said(vm, "the shorter way round, 7'-10\" against 23'-7\""))


# ---- a notch the run doubles back through ----------------------------

print("UPADOVER -- a narrow notch, where the run doubles back on itself")
vm = fresh()
per = pline(vm, [(0, 0), (200, 0), (200, 40), (190, 40), (190, 10), (0, 10)])
n0 = len(vm.entities)
run(vm, [per, [100.0, 0.0, 0.0], [100.0, 10.0, 0.0], [0.0, 5.0, 0.0]], "notch")
covers("a notch", vm, n0,
       walk_pts(((100, 0), (0, 0)), ((0, 0), (0, 10)), ((0, 10), (100, 10))))
check("a wall that comes back within a pad of itself is not padded twice",
      len(centres(vm, n0)) == 4, f"{centres(vm, n0)}")


# ---- which way round --------------------------------------------------

print("UPADOVER -- the shorter way round is taken without asking")
vm = fresh()
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [240.0, 0.0, 0.0]], "shorter")
check("it never put the way-round question",
      not asked(vm, "Click a spot the run passes through"))
check("it said which way it went and what the other way would have been",
      said(vm, "the shorter way round, 20'-0\" against 40'-0\""))
check("and it padded the short side",
      all(c[1] == 0.0 for c in centres(vm, n0)), f"{centres(vm, n0)}")


print("UPADOVER -- two ways round within 30% of each other are asked about")
#: The diagonal corners of the rectangle cut it exactly in half: 360
#: each way, which is as even as it gets.  The click is the whole of
#: the answer, so each way round is driven and checked against the wall
#: it should have followed -- and against the one it should not.
for click, where, legs, away in (
        ((240.0, 60.0), "the right-hand wall",
         (((0, 0), (240, 0)), ((240, 0), (240, 120))), (120.0, 120.0)),
        ((120.0, 120.0), "the top wall",
         (((0, 0), (0, 120)), ((0, 120), (240, 120))), (120.0, 0.0))):
    vm = fresh()
    per = rect(vm)
    n0 = len(vm.entities)
    run(vm, [per, [0.0, 0.0, 0.0], [240.0, 120.0, 0.0],
             [click[0], click[1], 0.0]], "even")
    check(f"clicking {where}: it asked first",
          asked(vm, "Click a spot the run passes through"))
    check(f"clicking {where}: it said the two are near enough the same",
          said(vm, "near enough the same that which one you mean is yours"))
    cs = covers(f"clicking {where}", vm, n0, walk_pts(*legs))
    check(f"clicking {where}: the other way round got nothing",
          bare(cs, [away]) == [away], f"{cs}")
    check(f"clicking {where}: it said the answer was yours",
          said(vm, "the way you clicked"))


print("UPADOVER -- an open perimeter has one stretch, so it is never asked")
vm = fresh()
per = pline(vm, [(0, 0), (240, 0), (240, 120)], closed=False)
n0 = len(vm.entities)
run(vm, [per, [200.0, 0.0, 0.0], [0.0, 0.0, 0.0]], "open")
check("no way-round question",
      not asked(vm, "Click a spot the run passes through"))
check("no other-way length to report", not said(vm, "the other way."))
check("it walked backwards along the wall to get there",
      centres(vm, n0)[0] == (200.0, 0.0)
      and centres(vm, n0)[-1][0] < 0.0, f"{centres(vm, n0)}")


# ---- naming the two ends ---------------------------------------------

print("UPADOVER -- an end is clicked or typed, and the spellings agree")
for spell in ("4", "Pt.4", "pt 4", "#4", "004"):
    vm = fresh()
    per = rect(vm)
    ab_pt(vm, 60, 0, 4)
    ab_pt(vm, 180, 0, 5)
    n0 = len(vm.entities)
    run(vm, [per, spell, "5"], f"spelling {spell}")
    check(f'"{spell}" names Pt.4', centres(vm, n0)[0] == (60.0, 0.0)
          and said(vm, "from Pt.4 to Pt.5"), f"{centres(vm, n0)[:1]}")

print("UPADOVER -- a click near a survey point IS that point")
vm = fresh()
per = rect(vm)
ab_pt(vm, 60, 0, 4)
n0 = len(vm.entities)
run(vm, [per, [64.0, 3.0, 0.0], [180.0, 0.0, 0.0]], "snap")
check("the pick snapped to Pt.4 rather than to where it landed",
      centres(vm, n0)[0] == (60.0, 0.0) and said(vm, "from Pt.4 to the end"),
      f"{centres(vm, n0)[:1]}")

print("UPADOVER -- a click well clear of every point is the place itself")
vm = fresh()
per = rect(vm)
ab_pt(vm, 60, 0, 4)
n0 = len(vm.entities)
run(vm, [per, [100.0, 0.0, 0.0], [180.0, 0.0, 0.0]], "place")
check("the run starts where it was clicked",
      centres(vm, n0)[0] == (100.0, 0.0), f"{centres(vm, n0)[:1]}")
check("and the report names it as a click, not as a point",
      said(vm, "from the start you clicked to the end you clicked"))

print("UPADOVER -- a pick off the wall is projected onto it, and said")
vm = fresh()
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, [100.0, -24.0, 0.0], [180.0, 0.0, 0.0]], "off the wall")
check("the run starts on the wall under the pick",
      centres(vm, n0)[0] == (100.0, 0.0), f"{centres(vm, n0)[:1]}")
check("and it said how far the pick had to come",
      said(vm, "off the wall - taken on the wall under it"))


# ---- the refusals -----------------------------------------------------

print("UPADOVER -- every refusal re-asks where it stands")
vm = fresh()
per = rect(vm)
ab_pt(vm, 60, 0, 4)
n0 = len(vm.entities)
run(vm, [per, "4", "4", [180.0, 0.0, 0.0]], "same place twice")
check("the same place twice is refused",
      said(vm, "That is where the run already starts"))
check("and the end question is put again, not the whole chain",
      len([p for p, _ in vm.prompts if "pads end" in p]) == 2
      and len([p for p, _ in vm.prompts if "pads start" in p]) == 1,
      f"{[p for p, _ in vm.prompts]}")
check("the run the second answer asked for is the one that went in",
      len(centres(vm, n0)) == 4, f"{centres(vm, n0)}")

vm = fresh()
per = rect(vm)
ab_pt(vm, 60, 0, 4)
n0 = len(vm.entities)
run(vm, [per, "9", "4", [180.0, 0.0, 0.0]], "no such number")
check("a number nothing carries is refused",
      said(vm, 'No survey point is numbered "9"'))
check("and nothing was guessed at", len(centres(vm, n0)) == 4)

vm = fresh()
per = rect(vm)
ab_pt(vm, 60, 0, 4)
ab_pt(vm, 120, 0, 4)            # the same number twice on the sheet
n0 = len(vm.entities)
run(vm, [per, "4", [60.0, 0.0, 0.0], [180.0, 0.0, 0.0]], "duplicate number")
check("a number two points share is asked about, not guessed at",
      said(vm, '2 points are numbered "4"'))

vm = fresh()
txt = Ent()
vm.entities.append(txt)
vm.entdata[txt] = [Dot(0, "TEXT"), Dot(8, "POOL"), [10, 0.0, 0.0, 0.0],
                   Dot(1, "not a wall")]
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [120.0, 0.0, 0.0]], "unreadable")
check("a perimeter selection that is refused re-asks for one",
      len(centres(vm, n0)) == 4, f"{centres(vm, n0)}")
vm = fresh()
txt = Ent()
vm.entities.append(txt)
vm.entdata[txt] = [Dot(0, "TEXT"), Dot(8, "POOL"), [10, 0.0, 0.0, 0.0],
                   Dot(1, "not a wall")]
per = rect(vm)
n0 = len(vm.entities)
run(vm, [txt, per, [0.0, 0.0, 0.0], [120.0, 0.0, 0.0]], "unreadable 2")
check("an entity nothing can measure along is named and refused",
      said(vm, "A TEXT is not something UPADOVER can measure along"))
check("and the run still happens once a wall is selected",
      len(centres(vm, n0)) == 4, f"{centres(vm, n0)}")


# ---- the block and the layer -----------------------------------------

print("UPADOVER -- the pad block, and the layer it lands on")
CORNER_BASED_BLOCK = '''
(entmake (list (cons 0 "BLOCK") (cons 2 "Pad36x36")
               (list 10 0.0 0.0 0.0) (cons 70 0)))
(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity") (cons 8 "0")
               (cons 100 "AcDbPolyline") (cons 90 4) (cons 70 1)
               (list 10 0.0 0.0) (list 10 36.0 0.0)
               (list 10 36.0 36.0) (list 10 0.0 36.0)))
(entmake (list (cons 0 "ENDBLK")))
'''
vm = fresh(CORNER_BASED_BLOCK)
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [72.0, 0.0, 0.0]], "corner-based block")
check("a block already in the drawing is used as it is",
      not said(vm, "created a plain"))
check("a block based at its CORNER still lands centred on the run",
      centres(vm, n0, (18.0, 18.0)) == [(0.0, 0.0), (36.0, 0.0), (72.0, 0.0)],
      f"{centres(vm, n0, (18.0, 18.0))}")
check("which means the insertion points are offset by the base",
      centres(vm, n0) == [(-18.0, -18.0), (18.0, -18.0), (54.0, -18.0)],
      f"{centres(vm, n0)}")

vm = fresh()
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [72.0, 0.0, 0.0]], "fallback block")
check("no pad block anywhere makes a plain square one",
      said(vm, "created a plain 36x36 square block"))
check("and the pads still go in", len(centres(vm, n0)) == 3)

FROZEN = '''
(entmakex (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")
                (cons 100 "AcDbLayerTableRecord") (cons 2 "PADS")
                (cons 70 5) (cons 62 -7) (cons 6 "Continuous")))
'''
vm = fresh(FROZEN)
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [72.0, 0.0, 0.0]], "frozen layer")
rec = vm.recdata[vm.tablerecs["LAYER"]["PADS"]]
flags = next(g.b for g in rec if isinstance(g, Dot) and g.a == 70)
col = next(g.b for g in rec if isinstance(g, Dot) and g.a == 62)
check("a PADS layer that is off, frozen or locked is put back",
      said(vm, "was off, frozen or locked") and flags & 5 == 0 and col > 0,
      f"flags {flags}, colour {col}")
check("and the pads still go in", len(centres(vm, n0)) == 3)


# ---- going back, and getting out -------------------------------------

print("UPADOVER -- Back steps one question, Esc leaves nothing behind")
vm = fresh()
per = rect(vm)
ab_pt(vm, 60, 0, 4)
ab_pt(vm, 180, 0, 5)
n0 = len(vm.entities)
run(vm, [per, "4", "Back", "5", "4"], "back")
check("Back at the end question re-opens the start question",
      [p for p, _ in vm.prompts].count(
          "\nWhere the pads start - click it, or type a point number [Back]: ")
      == 2)
check("and the run is the one the second pair of answers asked for",
      said(vm, "from Pt.5 to Pt.4"))

vm = fresh()
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [240.0, 120.0, 0.0], "Back",
         [120.0, 0.0, 0.0]], "back from the way-round click")
check("Back at the way-round click re-opens the end question",
      len([p for p, _ in vm.prompts if "pads end" in p]) == 2,
      f"{[p for p, _ in vm.prompts]}")
check("and answering it unambiguously never asks again",
      len([p for p, _ in vm.prompts if "passes through" in p]) == 1)

vm = fresh()
per = rect(vm)
vm.handle_errors = True
before = dict(vm.sysvars)
n0 = len(vm.entities)


def _esc(_vm):
    raise LispError("Function cancelled", _vm)


run(vm, [per, _esc], "cancel")
check("the handler saw the cancel",
      any("cancel" in m.lower() for m in vm.handled_errors),
      f"{vm.handled_errors}")
check("a plain cancel prints no error line", not said(vm, "UPADOVER error"))
check("nothing was drawn", not pad_ents(vm, n0))
check("every sysvar is back where it started", vm.sysvars == before)
check("no undo group was left open", vm.undo_groups == 0)

vm = fresh()
per = rect(vm)
before = dict(vm.sysvars)
run(vm, [per, [0.0, 0.0, 0.0], [120.0, 0.0, 0.0]], "clean exit")
check("a clean run hands the session back too",
      vm.sysvars == before and vm.undo_groups == 0,
      f"{vm.sysvars} / {vm.undo_groups}")


print("UPADOVERVER -- reports its own banner")
vm = fresh()
vm.run("c:UPADOVERVER", [])
check("UPADOVERVER prints the UPADOVER version",
      any("UPADOVER v" in s for s in vm.printed))


if failures:
    print(f"\n{len(failures)} UPADOVER check(s) FAILED")
    sys.exit(1)
print("\nall UPADOVER checks passed")
