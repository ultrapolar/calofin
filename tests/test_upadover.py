#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for UPADOVER: the real file loaded into the repo's
AutoLISP interpreter and c:UPADOVER driven end to end from a script.

UPADOVER makes one promise and the promise is geometric, so most of this
file is geometry: from the point you name round to the point you name,
the wall comes out UNDER pads -- no overlap anywhere, no gap between one
pad and the next, and nothing of the run left bare.  Each of those is
checked here as a fact about the pads that landed: none lying over
another, all of them one block joined along edges at least
upad:*mincontact* wide (a pair meeting at a corner is a joint with no
width, and does not count as joined), no sampled point of the run
outside every pad, and no pad laid where the run does not go.

The counts are pinned too, on the shapes where they are the point.  The
first version laid the pads on a grid, and a grid stair-steps whatever
the wall is doing: it took 13 pads down a 45-degree wall and 13 round a
half circle where laying them ACROSS the wall takes 7 and 9, and it put
them up to half a pad off the wall where these sit on it.  That is the
difference the drafter asked for, so it is written down as numbers
rather than left to be noticed.

The shapes, each of which breaks covers in a different way:

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

import lispvm  # noqa: E402
from lispvm import VM, Ent, Dot, LispError, Sym  # noqa: E402

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


def line(vm, a, b, layer="POOL"):
    """A plain LINE -- the stretch somebody drew because it is the bit
    that needs pads."""
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, "LINE"), Dot(8, layer),
                     [10, float(a[0]), float(a[1]), 0.0],
                     [11, float(b[0]), float(b[1]), 0.0]]
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


#: How much of their shared edge two neighbours must have in common --
#: upad:*mincontact*.  Nothing here reads the knob: the number is what
#: the tool promises, so the test says it out loud.
MINCONTACT = 6.0


def contact(a, b):
    """How much edge two pads actually share, in inches.

    Pads are laid one pad ACROSS from each other on one axis, so they
    meet on that line; what they share of it is a pad's width less the
    step along the other axis.  0.0 is two pads touching at a corner --
    a joint with no width, and a break in everything but topology -- and
    None is two pads that do not meet at all."""
    d = sorted((abs(a[0] - b[0]), abs(a[1] - b[1])))
    if abs(d[1] - PAD) > 1e-6 or d[0] > PAD - 1e-6:
        return None
    return PAD - d[0]


def loose_seams(cs):
    """Consecutive pads, in the order they went in, that do not meet
    along an edge of at least MINCONTACT.

    (A run that doubles back can land two pads in a row that each meet
    an EARLIER pad and not each other -- which is still a sound cover,
    and why the connectivity check below is the one that speaks for
    every run.)"""
    return [(a, b, contact(a, b)) for a, b in zip(cs, cs[1:])
            if contact(a, b) is None or contact(a, b) < MINCONTACT - 1e-6]


def loose_pads(cs):
    """Pads no chain of shared edges reaches from the first one.

    This is "no breaks between pads" as a property of the finished
    cover rather than of the order it went in: every pad is joined to
    every other through edges they share, and an edge has to have
    MINCONTACT of width to count -- so two pads meeting at a corner
    with the wall threading the junction between them cannot pass.
    """
    seen, stack = {0}, [0]
    while stack:
        i = stack.pop()
        for j, b in enumerate(cs):
            if j in seen:
                continue
            w = contact(cs[i], b)
            if w is not None and w >= MINCONTACT - 1e-6:
                seen.add(j)
                stack.append(j)
    return [c for j, c in enumerate(cs) if j not in seen]


def off_wall(cs, samples):
    """How far the furthest pad centre sits from the run.

    The point of laying pads across from each other rather than on a
    grid is that they FOLLOW the wall; this is the number that says so.
    The end pads are allowed their overshoot, so the run is measured
    with its own ends included."""
    return max(min(math.dist(c, p) for p in samples) for c in cs)


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
    #: Every pad is laid across from the one the run came out of, to
    #: cover the wall from there on -- so every pad has a piece of the
    #: run under it.  A grid could not say this: the pads it put in to
    #: bridge a corner touched the run at one point or not at all.
    idle = [c for c in cs
            if not any(max(abs(p[0] - c[0]), abs(p[1] - c[1])) <= HALF + 1e-9
                       for p in samples)]
    check(f"{label}: no pad is laid where the run does not go", not idle,
          f"{idle[:2]}")
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
check("and every pad sits ON the wall, not beside it",
      all(abs(c[1]) < 1e-9 for c in cs), f"{cs}")
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
samples = walk_pts(((0, 0), (200, 200)))
cs = covers("45 degrees", vm, n0, samples)
#: A grid laid this run in 13 pads, stair-stepping through a grid corner
#: every pad and needing one more beside each of them to stop the pair
#: meeting at a point.  Laid across the wall instead it takes 7, and no
#: two of them meet at a corner -- which is what the count is here to
#: hold on to.
check("the diagonal takes seven pads, not a grid's thirteen",
      len(cs) == 7, f"{len(cs)}")
check("and no two of them meet at a corner",
      not loose_seams(cs), f"{loose_seams(cs)[:2]}")
check("the pads follow the wall rather than a grid",
      off_wall(cs, samples) <= 12.0, f"{off_wall(cs, samples):.1f}\" off")


# ---- an arc -----------------------------------------------------------

print("UPADOVER -- a half circle, stair-stepped")
vm = fresh()
per = pline(vm, [(0, 0, 1.0), (200, 0)], closed=False)   # r=100, below
n0 = len(vm.entities)
run(vm, [per, [0.0, 0.0, 0.0], [200.0, 0.0, 0.0]], "arc")
samples = walk_pts((((100, 0), 100, math.pi, 2 * math.pi)))
cs = covers("half circle", vm, n0, samples)
check("the arc's own length is what it reports, not the chord's",
      said(vm, "covering 26'-2\""))
#: 13 pads on a grid, 9 laid across the wall -- and none of them more
#: than a third of a pad off the curve.
check("the curve takes nine pads, not a grid's thirteen",
      len(cs) == 9, f"{len(cs)}")
check("and they hug the curve", off_wall(cs, samples) <= 12.0,
      f"{off_wall(cs, samples):.1f}\" off")


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


# ---- Whole: the curve IS the stretch ---------------------------------

print("UPADOVER -- Whole pads a line end to end, and asks nothing else")
vm = fresh()
per = line(vm, (0, 0), (240, 0))
n0 = len(vm.entities)
run(vm, [per, "Whole"], "whole line")
cs = covers("a whole line", vm, n0, walk_pts(((0, 0), (240, 0))))
check("the Whole keyword is offered where the first end is asked for",
      asked(vm, "click it, or type a point number [Whole/Back]"),
      f"{[p for p, _ in vm.prompts]}")
check("and the second end is never asked for at all",
      not asked(vm, "Where the pads end"))
check("it covered the line exactly as the two-point run would",
      cs == [(x, 0.0) for x in (0, 36, 72, 108, 144, 180, 216, 252)], f"{cs}")
check("it said it padded the whole of it, end to end",
      said(vm, "covering the whole 20'-0\" of it, end to end"))
check("an open run says how long it is, and that Whole is there",
      said(vm, "an open run, 20'-0\" long.  Whole at the next question"))

print("UPADOVER -- Whole on a polyline follows its arcs too")
vm = fresh()
per = pline(vm, [(0, 0), (120, 0, 0.4142135623730951), (180, 60), (180, 200)],
            closed=False)
n0 = len(vm.entities)
run(vm, [per, "Whole"], "whole polyline")
covers("a whole polyline", vm, n0,
       walk_pts(((0, 0), (120, 0)),
                (((120, 60), 60, -math.pi / 2, 0.0)),
                ((180, 60), (180, 200))))
check("the whole of it is the arc's length too, not the chord's",
      said(vm, "covering the whole 29'-6\" of it"))

print("UPADOVER -- Whole on a closed perimeter goes all the way round")
vm = fresh()
per = rect(vm)
n0 = len(vm.entities)
run(vm, [per, "Whole"], "whole loop")
loop = walk_pts(((0, 0), (240, 0)), ((240, 0), (240, 120)),
                ((240, 120), (0, 120)), ((0, 120), (0, 0)))
cs = centres(vm, n0)
check("a whole loop: no two pads lie over each other", not overlaps(cs),
      f"{overlaps(cs)[:2]}")
check("the way round is not a question when the answer is both ways",
      not asked(vm, "Click a spot the run passes through"))
check("it said it came back round to where it started",
      said(vm, "the whole 60'-0\" of it, back round to where it started"))
#: A loop is the one run that cannot come out whole: it closes on its
#: own first pad, and the stretch left over takes no pad without lying
#: over that one.  So the tool says how much -- and what it says is
#: measured here against what is actually bare, because a cover that
#: under-reports its own gap is worse than one that has a gap.
bare_len = len(bare(cs, loop)) * 0.25
check("the stretch it cannot pad is shorter than one pad",
      bare_len < PAD, f"{bare_len:.1f}\"")
check("and it says so, where the loop closes back on itself",
      said(vm, "of the run is left bare - a pad there would lie over one"
               " already down, where the loop closes back on itself."))
check("nothing else of the loop is bare",
      len(bare(cs, loop)) * 0.25 < PAD + 1.0)


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
          "\nWhere the pads start - click it, or type a point number"
          " [Whole/Back]: ") == 2)
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


print("UPADOVER -- from inside a layout's viewport, model space is the space")
# From a viewport CTAB and the active layout both name the SHEET.  The
# VM has one space, so the two halves of AutoCAD are modelled here: the
# active layout's block is the sheet's paper while TILEMODE is 0, model
# space is what vla-get-ModelSpace hands back, and every insert records
# the space it was aimed at.  The sheet carries a title block's point
# numbered 1 as well: a sweep of every space found two points numbered 1
# and asked which was meant, with only one of them anywhere near the
# pool.
PAPER = "<paper-space>"


def with_spaces(run_it):
    B = lispvm.BUILTINS
    saved = {k: B[Sym(k)] for k in ("vla-get-block", "vla-insertblock")}
    aimed = []

    def get_block(vm, a):
        saved["vla-get-block"](vm, a)
        return PAPER if vm.sysvars.get("TILEMODE") == 0 else lispvm.MODEL_SPACE

    def insert(vm, a):
        aimed.append(a[0])
        return saved["vla-insertblock"](vm, [lispvm.MODEL_SPACE] + list(a[1:]))
    B[Sym("vla-get-block")] = get_block
    B[Sym("vla-insertblock")] = insert
    B[Sym("vla-get-modelspace")] = lambda vm, a: lispvm.MODEL_SPACE
    try:
        run_it()
    finally:
        B.update({Sym(k): v for k, v in saved.items()})
        B.pop(Sym("vla-get-modelspace"), None)
    return aimed


vm = fresh()
per = rect(vm)
ab_pt(vm, 0, 0, 1)
ab_pt(vm, 240, 0, 2)
title = ab_pt(vm, 900, 600, 1)                  # the sheet's own point 1
vm.entdata[title].append(Dot(410, "Layout1"))
vm.sysvars.update({"TILEMODE": 0, "CTAB": "Layout1", "CVPORT": 2})
n0 = len(vm.entities)
err = []


def _viewport_run():
    try:
        vm.run("c:UPADOVER", [per, "1", "2"])
    except LispError as e:
        err.append(str(e).splitlines()[0])


aimed = with_spaces(_viewport_run)
check("a typed 1 is the model space point, not asked about",
      not err and not said(vm, "points are numbered"), f"{err}")
check("the eight pads of the straight wall went in",
      len(pad_ents(vm, n0)) == 8, f"{len(pad_ents(vm, n0))}")
check("and every insert was aimed at model space, where the pool is",
      aimed and set(aimed) == {lispvm.MODEL_SPACE}, f"{aimed[:3]}")

# the paper itself active: the sheet is the space read, and padded
vm = fresh()
per = rect(vm)
for e in (per, ab_pt(vm, 0, 0, 1), ab_pt(vm, 240, 0, 2)):
    vm.entdata[e].append(Dot(410, "Layout1"))
ab_pt(vm, 900, 600, 1)                          # a model space point 1
vm.sysvars.update({"TILEMODE": 0, "CTAB": "Layout1", "CVPORT": 1})
n0 = len(vm.entities)
err = []
aimed = with_spaces(_viewport_run)
check("paper active: a typed 1 is the sheet's point",
      not err and len(pad_ents(vm, n0)) == 8, f"{err}")
check("and the pads are aimed at the sheet",
      aimed and set(aimed) == {PAPER}, f"{aimed[:3]}")


print("UPADOVERVER -- reports its own banner")
vm = fresh()
vm.run("c:UPADOVERVER", [])
check("UPADOVERVER prints the UPADOVER version",
      any("UPADOVER v" in s for s in vm.printed))


if failures:
    print(f"\n{len(failures)} UPADOVER check(s) FAILED")
    sys.exit(1)
print("\nall UPADOVER checks passed")
