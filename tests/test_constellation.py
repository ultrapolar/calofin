#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for CONSTELLATION.lsp -- points placed from the dims
between them.

The whole of c:CONSTELLATION is driven in the AutoLISP VM.  Unlike
XYPLOT, which is handed the answer and only has to draw it, this command
has to WORK OUT where the points go, so most of what is checked here is
whether the answer is right:

  * THE SHAPE COMES BACK.  Feed in the distances of a shape that really
    exists and the drawing must reproduce it -- every dim given, drawn
    at what it was given as.

  * A PARTIAL CHART IS THE NORMAL CASE.  A field sheet carries some of
    the pairs, never all of them.  Drop a diagonal and the rest must
    still pin the shape down.

  * THE TWO THINGS DISTANCES CANNOT SAY.  A constellation and its mirror
    satisfy the same distances, and so does the same constellation
    turned any which way.  Handedness is settled clockwise, as the
    preview showed it; the angle is settled by fitting the space.  Both
    are asserted, because a solver that gets the shape right and the
    handedness wrong draws a pool nobody can build.

  * WHAT IS NOT ENOUGH TO GO ON.  A point with one dim sits anywhere on
    a circle; a group dimensioned only to itself floats free.  Both must
    be refused BY NAME, not solved into a plausible-looking wrong
    answer.

  * DIMS THAT CANNOT ALL BE TRUE.  Tape readings disagree.  The layout
    that misses by least is drawn and the misses are STARRED -- the
    failure this file most wants to catch is a bad dim quietly absorbed.

  * THE PREVIEW LEAVES NOTHING BEHIND.  The starting oval is a legend,
    not geometry, and a run must not leave it in the drawing.

Usage:  python3 tests/test_constellation.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_constellation.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LSP = os.path.join(REPO, 'lisp', 'constellation', 'CONSTELLATION.lsp')

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


#: a 240 x 120 rectangle, A top-left and running clockwise -- the shape
#: a four-corner pool's cross dims describe
RECT = [(0.0, 120.0), (240.0, 120.0), (240.0, 0.0), (0.0, 0.0)]

#: a five-point shape that is not symmetric about anything, so a mirror
#: or a quarter turn of it is unmistakable
BLOB = [(10.0, 190.0), (210.0, 200.0), (250.0, 90.0), (120.0, 10.0),
        (0.0, 60.0)]


def truth(pts):
    """Every pairwise distance of PTS, keyed (i, j) with i < j."""
    return {(i, j): math.dist(pts[i], pts[j])
            for i in range(len(pts)) for j in range(i + 1, len(pts))}


def pairs(n):
    return [(i, j) for i in range(n) for j in range(i + 1, n)]


def feed(have, n):
    """The chart half of a script.  Enter takes the NEXT BLANK pair in
    reading order, so it is only the right answer when every pair is
    being given; a partial chart names each pair instead, which is what
    an operator with a half-filled sheet does anyway."""
    out = []
    full = len(have) == len(pairs(n))
    for i, j in pairs(n):
        if (i, j) in have:
            out.append("" if full else "%s-%s" % (letters(n)[i],
                                                  letters(n)[j]))
            out.append(have[(i, j)])
    if not full:
        out.append("D")                  # a full chart closes itself
    return out


def arcfeed(arcs):
    """The arc half of a script.  Each arc is (run-spec, R) or
    (run-spec, R, bows-out) -- the bow question is only asked of a
    two-point run, where the two possible centres are mirror images and
    nothing in the distances chooses between them."""
    out = []
    for a in arcs:
        out.append(a[0])
        out.append(a[1])
        if len(a) > 2:
            out.append("Yes" if a[2] else "No")
    out.append("")                       # Enter closes the arc list
    return out


def run(shape=RECT, w=360.0, h=240.0, base=(0.0, 0.0), drop=(),
        given=None, arcs=(), outline="Yes", confirm="Yes", extra=None,
        after=None):
    """Drive one whole run.  GIVEN overrides the distances outright;
    otherwise they are the true distances of SHAPE less DROP.  EXTRA
    goes in before the arc list, AFTER goes in after the "does it look
    right" answer -- CONFIRM "No" reopens the questions, so a run that
    answers No must say what it does next."""
    n = len(shape)
    have = dict(given) if given else truth(shape)
    for k in drop:
        have.pop(k, None)
    vm = VM()
    vm.load(LSP)
    script = [w, h, n, [base[0], base[1], 0.0]] + feed(have, n)
    script.extend(extra or [])
    script += arcfeed(arcs)
    script.append(outline)
    script.append(confirm)
    script.extend(after or [])
    vm.run('c:CONSTELLATION', script)
    return vm


# ---------------------------------------------------------------- reading
# the drawing back


def dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return list(g[1:])
    return None


def live(vm, etype=None):
    return [e for e in vm.entities
            if e not in vm.deleted
            and (etype is None or dxf(vm, e, 0) == etype)]


def placed(vm):
    """The drawn points, letter -> (x, y), read off the ab_pt blocks and
    the attribute each carries."""
    out, pt = {}, None
    for e in live(vm):
        kind = dxf(vm, e, 0)
        if kind == 'INSERT':
            pt = dxf(vm, e, 10)[:2]
        elif kind == 'ATTRIB' and pt is not None:
            out[dxf(vm, e, 1)] = tuple(pt)
            pt = None
    return out


def said(vm):
    return "".join(str(x) for x in vm.printed)


def asked(vm):
    """Every prompt the run put up.  Kept apart from said(): a getkword
    prompt never reaches princ, so a question can only be asserted on
    here and an answer only there."""
    return "\n".join(str(q) for q, _ in vm.prompts)


def shoelace(pts):
    n = len(pts)
    return 0.5 * sum(pts[i][0] * pts[(i + 1) % n][1]
                     - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))


def letters(n):
    return [chr(ord('A') + i) for i in range(n)]


def as_ring(vm, n):
    p = placed(vm)
    return [p[c] for c in letters(n)]


# ---------------------------------------------------------------- the tests


def test_a_known_shape_comes_back():
    print("\na shape that really exists is reproduced from its distances")
    vm = run()
    ring = as_ring(vm, 4)
    want = truth(RECT)
    worst = max(abs(math.dist(ring[i], ring[j]) - d)
                for (i, j), d in want.items())
    check("every dim drawn within 0.01 of what was given (worst %.5f)"
          % worst, worst < 0.01)
    check("the report says nothing needs re-measuring",
          "nothing here needs re-measuring" in said(vm))


def test_a_partial_chart_still_places_everything():
    print("\nthe normal case: a sheet that carries some of the pairs")
    vm = run(drop=[(0, 2)])              # one diagonal missing
    ring = as_ring(vm, 4)
    want = truth(RECT)
    del want[(0, 2)]
    worst = max(abs(math.dist(ring[i], ring[j]) - d)
                for (i, j), d in want.items())
    check("the five dims given all come back (worst %.5f)" % worst,
          worst < 0.01)
    check("the missing diagonal is drawn true anyway",
          abs(math.dist(ring[0], ring[2]) - truth(RECT)[(0, 2)]) < 0.01)
    check("five dims given of six possible", "5 given of 6 possible"
          in said(vm))


def test_five_points_with_gaps_in_the_chart():
    print("\na five-point blob with three of its ten pairs never measured")
    vm = run(shape=BLOB, drop=[(0, 2), (1, 4), (0, 3)])
    ring = as_ring(vm, 5)
    want = {k: v for k, v in truth(BLOB).items()
            if k not in ((0, 2), (1, 4), (0, 3))}
    worst = max(abs(math.dist(ring[i], ring[j]) - d)
                for (i, j), d in want.items())
    check("the seven dims given all come back (worst %.5f)" % worst,
          worst < 0.01)
    # the three that were never measured are pinned by the other seven
    unmeasured = max(abs(math.dist(ring[i], ring[j]) - truth(BLOB)[(i, j)])
                     for (i, j) in ((0, 2), (1, 4), (0, 3)))
    check("and the three never measured land right too (worst %.5f)"
          % unmeasured, unmeasured < 0.01)


def test_the_letters_run_clockwise():
    print("\nhandedness: the mirror that reads clockwise is the one drawn")
    for label, shape in (("rectangle", RECT), ("blob", BLOB)):
        ring = as_ring(run(shape=shape), len(shape))
        check("%s: A B C ... runs clockwise" % label, shoelace(ring) < 0)
    # BLOB itself is clockwise, so the drawn ring must match it and not
    # its mirror: compare the shape of the ring to the shape of BLOB
    ring = as_ring(run(shape=BLOB), 5)
    check("the blob is not drawn mirrored",
          abs(shoelace(ring) - shoelace(BLOB)) < 1.0)


def test_the_result_is_centred_in_the_space():
    print("\nthe constellation is turned to fit and centred in the space")
    vm = run(base=(1000.0, -500.0))
    ring = as_ring(vm, 4)
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    check("centred across X", abs((min(xs) - 1000.0)
                                  - (1360.0 - max(xs))) < 0.01)
    check("centred across Y", abs((min(ys) + 500.0)
                                  - (-260.0 - max(ys))) < 0.01)
    check("every point inside the space",
          min(xs) >= 999.99 and max(xs) <= 1360.01
          and min(ys) >= -500.01 and max(ys) <= -259.99)
    check("and the report says so", "Every point landed inside the space"
          in said(vm))


def test_a_point_with_one_dim_will_not_close_the_chart():
    print("\na point with one dim sits anywhere on a circle - refused")
    # D is given only its dim to A; Done is typed, refused, then the
    # second dim is supplied and Done accepted
    have = truth(RECT)
    thin = {k: v for k, v in have.items() if k not in ((1, 3), (2, 3))}
    vm = VM()
    vm.load(LSP)
    script = [360.0, 240.0, 4, [0.0, 0.0, 0.0]] + feed(thin, 4)
    script += ["C-D", have[(2, 3)],      # give D a second dim
               "D",                      # now accepted
               "",                       # no arcs
               "Yes",                    # draw the outline
               "Yes"]                    # and it looks right
    vm.run('c:CONSTELLATION', script)
    out = said(vm)
    check("the refusal names the point that is short",
          "D has 1 dim" in out)
    check("it explains what one dim leaves open",
          "anywhere\n    on a circle" in out or "on a circle" in out)
    check("the run then completes", "Worst miss" in out)
    check("four points were drawn in the end", len(placed(vm)) == 4)


def test_two_groups_that_never_touch_are_refused():
    print("\na group dimensioned only to itself floats free - refused")
    # A-B-C is a triangle, D-E-F is another, and nothing bridges them:
    # every point has two dims, so only the reachability check catches it
    six = [(0.0, 100.0), (100.0, 100.0), (50.0, 20.0),
           (300.0, 100.0), (400.0, 100.0), (350.0, 20.0)]
    all_d = truth(six)
    keep = [(0, 1), (0, 2), (1, 2), (3, 4), (3, 5), (4, 5)]
    vm = VM()
    vm.load(LSP)
    script = ([600.0, 300.0, 6, [0.0, 0.0, 0.0]]
              + feed({k: all_d[k] for k in keep}, 6))
    script += ["C-D", all_d[(2, 3)],         # bridge the two islands
               "D", "", "No", "Yes"]
    vm.run('c:CONSTELLATION', script)
    out = said(vm)
    check("the cut-off group is named", "D, E, and F are only dimensioned"
          in out)
    check("no point was reported as short of dims",
          "cannot be placed" not in out)
    check("the run completes once one dim bridges the gap",
          "Worst miss" in out and len(placed(vm)) == 6)


def test_the_preview_is_erased():
    print("\nthe starting oval is a legend, and it leaves nothing behind")
    vm = run()
    made_circles = [e for e in vm.entities if dxf(vm, e, 0) == 'CIRCLE']
    check("the preview really was drawn", len(made_circles) == 4)
    check("and every bit of it is gone again",
          all(e in vm.deleted for e in made_circles))
    check("no entity is left on the guide layer",
          not [e for e in live(vm)
               if vm.layer_of(e) == 'CONSTELLATION-GUIDE'])
    check("the preview said which way the letters run",
          "clockwise from the top left" in said(vm))
    # the list the *error* handler sweeps is empty on a clean finish, so
    # the NEXT run cannot erase entities this one meant to keep
    check("the preview list is empty afterwards",
          vm.get('cst:*preview*') is None
          or vm.get('cst:*preview*') == [])


def test_the_preview_can_be_swept_at_any_time():
    print("\nthe sweep the *error* handler calls is safe to call twice")
    # this is the cancel path's mechanism: Esc part way through the
    # chart must leave nothing behind, and the handler cannot know
    # whether the normal exit already swept
    vm = VM()
    vm.load(LSP)
    vm.loads('(cst:preview 4 360.0 240.0 (list 0.0 0.0))')
    drawn = [e for e in live(vm) if vm.layer_of(e) == 'CONSTELLATION-GUIDE']
    check("the preview drew a marker and a label per point",
          len(drawn) == 8)
    vm.loads('(cst:unpreview)')
    check("one sweep takes all of it",
          not [e for e in live(vm)
               if vm.layer_of(e) == 'CONSTELLATION-GUIDE'])
    vm.loads('(cst:unpreview)')          # must not raise on a gone ename
    check("a second sweep is a no-op, not an error", True)


def test_points_are_ab_pt_blocks_named_by_letter():
    print("\nthe points are the survey block the rest of the toolkit reads")
    vm = run(shape=BLOB)
    ins = [e for e in live(vm, 'INSERT')]
    check("one INSERT per point", len(ins) == 5)
    check("all of them ab_pt", all(dxf(vm, e, 2) == 'ab_pt' for e in ins))
    check("all of them on POINTS",
          all(vm.layer_of(e) == 'POINTS' for e in ins))
    check("labelled A to E", sorted(placed(vm)) == list("ABCDE"))
    check("the report points at ABHD", "ABHD and" in said(vm))


def test_one_aligned_dim_per_dim_given():
    print("\none aligned dimension per dim given, and not one more")
    vm = run(drop=[(0, 2)])
    dims = live(vm, 'DIMENSION')
    check("five dims drawn for five given", len(dims) == 5)
    check("every one aligned (group 70 = 33)",
          all(dxf(vm, e, 70) == 33 for e in dims))
    check("every one on DIMENSION",
          all(vm.layer_of(e) == 'DIMENSION' for e in dims))
    check("none carries a text override -- they measure the geometry",
          all(dxf(vm, e, 1) == "" for e in dims))


def test_a_dim_measures_the_points_it_belongs_to():
    print("\nevery dimension's ends sit on the two points it names")
    vm = run(shape=BLOB)
    ring = as_ring(vm, 5)
    want = {round(d, 4) for d in truth(BLOB).values()}
    for e in live(vm, 'DIMENSION'):
        p1, p2 = dxf(vm, e, 13)[:2], dxf(vm, e, 14)[:2]
        near1 = min(math.dist(p1, q) for q in ring)
        near2 = min(math.dist(p2, q) for q in ring)
        if max(near1, near2) > 0.01:
            check("a dim's ends are both drawn points", False)
            return
    check("every dim's ends are both drawn points", True)
    drawn = {round(math.dist(dxf(vm, e, 13)[:2], dxf(vm, e, 14)[:2]), 4)
             for e in live(vm, 'DIMENSION')}
    check("and each spans a distance that was actually given",
          all(any(abs(d - t) < 0.01 for t in want) for d in drawn))


def test_cross_dims_lie_on_the_chord_and_perimeter_dims_stand_off():
    print("\ncross dims run down the chord; perimeter dims stand clear")
    vm = run()
    ring = as_ring(vm, 4)
    on_chord = off_chord = 0
    for e in live(vm, 'DIMENSION'):
        p1, p2, loc = (dxf(vm, e, 13)[:2], dxf(vm, e, 14)[:2],
                       dxf(vm, e, 10)[:2])
        mid = ((p1[0] + p2[0]) / 2.0, (p1[1] + p2[1]) / 2.0)
        span = math.dist(p1, p2)
        # a neighbour in the label ring is a perimeter dim
        idx = sorted(min(range(4), key=lambda k: math.dist(ring[k], p))
                     for p in (p1, p2))
        neighbour = (idx[1] - idx[0] == 1) or idx == [0, 3]
        if neighbour:
            off_chord += math.dist(loc, mid) > 0.05 * span
        else:
            on_chord += math.dist(loc, mid) < 1e-6
    check("both cross dims sit exactly on their chord", on_chord == 2)
    check("all four perimeter dims stand off it", off_chord == 4)


#: five points with B, C and D sitting on one 150 circle.  Six dims are
#: given, which is one short of pinning five points down -- so the arc
#: is what makes the difference, and the difference is measurable.
ARC_C, ARC_R = (180.0, 120.0), 150.0


def on_circle(deg):
    return (ARC_C[0] + ARC_R * math.cos(math.radians(deg)),
            ARC_C[1] + ARC_R * math.sin(math.radians(deg)))


BOWL = [(30.0, 240.0), on_circle(60), on_circle(0), on_circle(-60),
        (30.0, 0.0)]
BOWL_DIMS = [(0, 1), (0, 4), (1, 2), (2, 3), (3, 4), (1, 4)]


def circumradius(p, q, r):
    (ax, ay), (bx, by), (cx, cy) = p, q, r
    d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay)
          + (cx * cx + cy * cy) * (ay - by)) / d
    uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx)
          + (cx * cx + cy * cy) * (bx - ax)) / d
    return math.dist((ux, uy), p)


def bowl(arcs=(), **kw):
    only = {k: v for k, v in truth(BOWL).items() if k in BOWL_DIMS}
    return run(shape=BOWL, w=500.0, h=400.0, given=only, arcs=arcs, **kw)


def test_an_arc_pins_what_dims_alone_leave_loose():
    print("\nan arc constrains the shape where cross dims run out")
    loose = as_ring(bowl(), 5)
    tight = as_ring(bowl(arcs=[("B-D", ARC_R)]), 5)
    r_loose = circumradius(loose[1], loose[2], loose[3])
    r_tight = circumradius(tight[1], tight[2], tight[3])
    # six dims on five points is one short of rigid, so B C D are free to
    # settle on the wrong radius -- and do
    check("without the arc B C D land off the radius (R %.2f)" % r_loose,
          abs(r_loose - ARC_R) > 1.0)
    check("with it declared they land on it exactly (R %.4f)" % r_tight,
          abs(r_tight - ARC_R) < 0.01)
    check("and the dims that were given still come back",
          max(abs(math.dist(tight[i], tight[j]) - d)
              for (i, j), d in truth(BOWL).items()
              if (i, j) in BOWL_DIMS) < 0.01)


#: the shape that caught the solver out.  Six points, and a chart of the
#: ring plus two diagonals -- just rigid, and a very ordinary field
#: sheet.  The dims are exactly consistent, so a zero-miss layout exists;
#: the old solver stopped at a fixed sweep count and left a given dim
#: 0.19in out, then blamed a tape for it.
JUSTRIGID = [(130.5351, 219.4649), (235.8919, 283.9503), (281.8186, 171.9232),
             (313.2685, 36.7315), (155.5482, -15.8963), (56.3059, 111.4973)]
JUSTRIGID_DIMS = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (0, 5),
                  (0, 2), (1, 3)]


def test_a_barely_rigid_chart_still_holds_every_dim():
    print("\na chart that is only just rigid is still held to the inch")
    only = {k: v for k, v in truth(JUSTRIGID).items() if k in JUSTRIGID_DIMS}
    vm = run(shape=JUSTRIGID, w=600.0, h=500.0, given=only, outline="No")
    ring = as_ring(vm, 6)
    worst = max(abs(math.dist(ring[i], ring[j]) - d)
                for (i, j), d in only.items())
    # 0.19 was what the fixed-sweep solver left here.  A thousandth of
    # an inch is far below anything a drawing can show, and is the
    # difference between a report that can be trusted and one that
    # cannot.
    check("every given dim comes back within 0.001 (worst %.6f)" % worst,
          worst < 0.001)
    check("so nothing is starred and no tape is blamed",
          "**" not in said(vm)
          and "is the one to re-measure" not in said(vm))
    # what is NOT asserted: the two diagonals never given.  A chart that
    # is only just rigid can have more than one realization, so a
    # distance nobody measured is not something this command promises.


def test_a_run_is_read_clockwise():
    print("\nA-C, ABC and the wrap D-B all name the run they should")
    vm = VM()
    vm.load(LSP)
    for typed, want in (("A-C", [0, 1, 2]),     # from A clockwise to C
                        ("ABC", [0, 1, 2]),     # spelled out, same run
                        ("AC", [0, 1, 2]),      # no separator, same run
                        ("D-B", [3, 0, 1]),     # wraps: D A B
                        ("a c", [0, 1, 2])):
        vm.loads('(setq got (cst:parserun "%s" 4))' % typed)
        got = [int(x) for x in (vm.get('got') or [])]
        check('"%s" reads as %s' % (typed, "".join("ABCD"[i] for i in want)),
              got == want)
    for bad in ("A", "AA", "AX", "", "12"):
        vm.loads('(setq got (cst:parserun "%s" 4))' % bad)
        check('"%s" is refused' % bad, vm.get('got') is None)
    # the wrap is the whole reason the order is asked for clockwise: B-D
    # and D-B are DIFFERENT runs, and the letters say which
    vm.loads('(setq got (cst:parserun "B-D" 4))')
    check('"B-D" is B C D, not D A B',
          [int(x) for x in vm.get('got')] == [1, 2, 3])


def test_an_arc_that_disagrees_with_the_dims_is_starred():
    print("\na radius the dims cannot support is reported, not absorbed")
    # the FULL chart, so the shape is rigid and the arc has nothing to
    # flex into.  (On the six-dim chart above there is a degree of
    # freedom left, and the shape obligingly bends to whatever radius is
    # asked for -- correct, and the same redundancy argument as a bad
    # tape on a bare-minimum chart.)
    rigid = run(shape=BOWL, w=500.0, h=400.0,
                arcs=[("B-D", 260.0)])     # the shape is a 150 radius
    out = said(rigid)
    check("the arc gets its own line in the report", "R given" in out
          and "B-C-D" in out)
    check("and it is starred", "260.0000" in out and out.count("**") > 0)
    check("the headline counts the arc alongside the dims",
          "over 10 dims and 1 arc." in out)
    check("an arc that fits is not starred at all",
          "**" not in said(run(shape=BOWL, w=500.0, h=400.0,
                               arcs=[("B-D", ARC_R)])))
    check("and a chart with room to flex simply meets the arc instead",
          "**" not in said(bowl(arcs=[("B-D", 260.0)])))


def test_the_outline_bends_round_a_declared_arc():
    print("\nthe outline runs as an arc where an arc was declared")
    vm = bowl(arcs=[("B-D", ARC_R)])
    ring = [e for e in live(vm, 'LWPOLYLINE')
            if vm.layer_of(e) == 'CONSTELLATION'][0]
    # group 42 is a bulge on the segment LEAVING that vertex; B and C
    # each lead into the arc, nothing else does
    bulged = [g.b for g in vm.entdata[ring]
              if isinstance(g, Dot) and g.a == 42]
    check("two segments carry a bulge, B-C and C-D", len(bulged) == 2)
    check("both bend the same way, and clockwise (negative)",
          all(b < 0 for b in bulged))
    # a 60 degree segment of a circle bulges tan(15 deg)
    want = -math.tan(math.radians(15.0))
    check("each bulge is the 60-degree one the radius implies",
          all(abs(b - want) < 0.01 for b in bulged))
    plain = bowl()
    flat = [e for e in live(plain, 'LWPOLYLINE')
            if plain.layer_of(e) == 'CONSTELLATION'][0]
    check("no arc declared, no bulge anywhere",
          not [g for g in plain.entdata[flat]
               if isinstance(g, Dot) and g.a == 42])


def test_a_two_point_arc_is_asked_which_way_it_bows():
    print("\ntwo points and a radius leave two centres - the operator picks")
    # A-B is one wall of the rectangle; bowing out and bowing in put the
    # outline's bulge opposite ways round
    out = run(arcs=[("A-B", 200.0, True)])
    inn = run(arcs=[("A-B", 200.0, False)])

    def bulge_of(vm):
        ring = [e for e in live(vm, 'LWPOLYLINE')
                if vm.layer_of(e) == 'CONSTELLATION'][0]
        b = [g.b for g in vm.entdata[ring]
             if isinstance(g, Dot) and g.a == 42]
        return b[0] if b else 0.0
    check("bowing out and bowing in are opposite bulges",
          bulge_of(out) * bulge_of(inn) < 0)
    check("both are the same size", abs(abs(bulge_of(out))
                                        - abs(bulge_of(inn))) < 1e-6)
    check("the question was asked", "bow out from the shape"
          in asked(out))
    check("and it is NOT asked of a three-point run",
          "bow out from the shape"
          not in asked(bowl(arcs=[("B-D", ARC_R)])))


def test_a_pair_can_be_typed_any_way_round():
    print("\nAC, a c, A-C and C-A all name the same pair")
    have = truth(RECT)
    for typed in ("AC", "a c", "A-C", "C-A", "c,a"):
        vm = VM()
        vm.load(LSP)
        script = [360.0, 240.0, 4, [0.0, 0.0, 0.0]]
        # answer A-B and A-C's own turn by Enter, then jump about
        for pr, text in (((0, 1), ""), ((0, 2), typed)):
            script += [text, have[pr]]
        for pr in ((0, 3), (1, 2), (1, 3), (2, 3)):
            script += ["", have[pr]]
        script += ["", "No", "Yes"]
        vm.run('c:CONSTELLATION', script)
        check('"%s" reached A-C' % typed,
              "A-C = " in said(vm) and len(placed(vm)) == 4)


def test_back_blanks_the_last_dim():
    print("\nBack in the chart blanks the dim just given")
    have = truth(RECT)
    vm = VM()
    vm.load(LSP)
    script = [360.0, 240.0, 4, [0.0, 0.0, 0.0],
              "", have[(0, 1)],            # A-B
              "", have[(0, 2)],            # A-C
              "B",                         # ...take A-C back
              "", have[(0, 2)]]            # the prompt offers A-C again
    for pr in ((0, 3), (1, 2), (1, 3), (2, 3)):
        script += ["", have[pr]]
    script += ["", "No", "Yes"]
    vm.run('c:CONSTELLATION', script)
    out = said(vm)
    check("it says what it blanked",
          "Stepping back one dimension - A-C is blank again" in out)
    check("A-C came back round as the next pair on offer",
          len([p for p, _ in vm.prompts
               if isinstance(p, str) and "<A-C>" in p]) == 2)
    check("the run still ends with all six given",
          "6 given of 6 possible" in out)


def test_dims_that_cannot_all_be_true_are_starred():
    print("\ntape readings that disagree are starred, never absorbed")
    # a triangle that cannot exist: 100 + 100 does not reach 250
    bad = {(0, 1): 100.0, (1, 2): 100.0, (0, 2): 250.0}
    vm = run(shape=[(0, 0)] * 3, given=bad, outline="No")
    out = said(vm)
    check("the impossible dims are starred", "**" in out)
    check("and the report does not pretend to know which one is wrong",
          "No single one of them explains the rest" in out
          and "More cross dims settle either" in out)
    check("the worst miss is reported, not hidden",
          "Worst miss" in out
          and "nothing here needs re-measuring" not in out)
    ring = as_ring(vm, 3)
    check("the layout drawn is the closest one, not a refusal",
          abs(math.dist(ring[0], ring[2]) - 250.0) < 30.0
          and len(placed(vm)) == 3)
    # three dims on three points is exactly rigid: drop one and a point
    # is left on a circle, so there is no second opinion to be had and
    # no dim may be blamed
    check("with no redundancy no single dim is blamed",
          "is the one to re-measure" not in out)


def test_one_bad_tape_is_named_not_smeared():
    print("\nthe leave-one-out test names the tape that is wrong")
    # least squares gives a little on EVERY dim touching the bad pair,
    # so ten dims come out slightly wrong and the stars alone say
    # nothing.  Leaving the worst out has to settle the other nine.
    bad = dict(truth(BLOB))
    bad[(0, 2)] += 3.5                    # A-C read three and a half long
    vm = run(shape=BLOB, given=bad, outline="No")
    out = said(vm)
    check("the smearing really happened -- most dims are starred",
          out.count("**") > 6)
    check("and the culprit is named anyway",
          "Leave A-C out and every other dim settles" in out)
    check("it names A-C as the one to re-measure",
          "so A-C is the one to re-measure" in out)
    check("and that nothing was dropped from the drawing",
          "still honours every dim given" in out
          and len(live(vm, 'DIMENSION')) == 10)
    check("an honest chart is not blamed on anything",
          "is the one to re-measure" not in said(run(shape=BLOB,
                                                     outline="No")))


def test_a_constellation_too_big_for_its_space_is_said_so():
    print("\na shape that will not fit the space is drawn and flagged")
    vm = run(w=120.0, h=120.0)           # the rectangle is 240 x 120
    out = said(vm)
    check("the overhang is reported", "past the space across its two axes"
          in out)
    check("it is still drawn", len(placed(vm)) == 4)
    check("and the shape is still right",
          abs(math.dist(as_ring(vm, 4)[0], as_ring(vm, 4)[1]) - 240.0)
          < 0.01)


def test_the_outline_is_optional():
    print("\nthe ring through the points is asked for, not assumed")
    on = [e for e in live(run(outline="Yes"), 'LWPOLYLINE')]
    off = [e for e in live(run(outline="No"), 'LWPOLYLINE')]
    check("Yes draws it", len(on) == 2)          # the space, and the ring
    check("No leaves only the space rectangle", len(off) == 1)
    vm = run(outline="No")
    check("and that one is the space",
          live(vm, 'LWPOLYLINE')[0] is not None
          and vm.layer_of(live(vm, 'LWPOLYLINE')[0])
          == 'CONSTELLATION-SPACE')


def test_an_outline_that_crosses_itself_is_reported():
    print("\na ring that crosses itself means two letters got swapped")
    # BLOB with C and D swapped on the sheet: the distances are all
    # true, the clockwise ORDER they were labelled in is not
    swapped = [BLOB[0], BLOB[1], BLOB[3], BLOB[2], BLOB[4]]
    vm = run(shape=swapped)
    check("the crossing is called out",
          "The outline crosses itself" in said(vm))
    check("the honest run does not claim one",
          "The outline crosses itself" not in said(run(shape=BLOB)))


def test_a_wrong_number_can_be_put_right_after_seeing_the_drawing():
    print("\nNo at the end reopens the questions and redraws")
    have = dict(truth(RECT))
    have[(0, 1)] = 300.0                  # A-B typed 300 instead of 240
    vm = run(given=have, confirm="No",
             after=["Dims",               # the dims are what is wrong
                    "A-B", 240.0,         # put it right
                    "D",                  # done
                    "Yes"])               # now it looks right
    out = said(vm)
    check("it asked whether the drawing looked right",
          "Does the drawing look right? [Yes/No] <Yes>: " in asked(vm))
    check("and what needed changing",
          "What needs changing? [Dims/Arcs/Both] <Dims>: " in asked(vm))
    check("the corrected value is what got drawn",
          abs(math.dist(as_ring(vm, 4)[0], as_ring(vm, 4)[1]) - 240.0)
          < 0.01)
    check("the report ran twice, once per attempt",
          out.count("Worst miss") == 2)
    check("the wrong drawing was taken away, not left underneath",
          len(live(vm, 'INSERT')) == 4
          and len([e for e in live(vm, 'LWPOLYLINE')]) == 2)
    check("every entity of the first attempt is deleted",
          len([e for e in vm.entities if e in vm.deleted
               and dxf(vm, e, 0) == 'INSERT']) == 4)


def test_an_arc_can_be_put_right_the_same_way():
    print("\nand so can a radius typed wrong")
    vm = bowl(arcs=[("B-D", 260.0)], confirm="No",
              after=["Arcs", "B-D", ARC_R, "", "Yes"])
    ring = as_ring(vm, 5)
    check("the corrected radius is the one drawn",
          abs(circumradius(ring[1], ring[2], ring[3]) - ARC_R) < 0.01)
    check("only the arcs were reopened, not the dims",
          said(vm).count("Cross dims - name the pair") == 0)
    check("the arc list was reopened", "Arcs - name the run" in said(vm))


def test_the_fix_pass_can_be_backed_out_of_without_emptying_the_chart():
    print("\nBack at the first dim of a fix pass stops, it does not escape")
    # on the way through, Back out of an empty chart means going back a
    # question; on a fix pass there is no question behind it, so it has
    # to stop rather than hand back a Back nobody can act on
    vm = run(confirm="No",
             after=["Dims"] + ["B"] * 6 + ["B", "D"]
                   + ["", "Yes"] * 0 + ["A-B", 240.0, "A-C", 268.32825,
                                        "A-D", 120.0, "B-C", 120.0,
                                        "B-D", 268.32825, "C-D", 240.0,
                                        "D", "Yes"])
    out = said(vm)
    check("it says it is already at the first dimension",
          "Already at the first dimension." in out)
    check("and the run still finishes", out.count("Worst miss") == 2
          and len(placed(vm)) == 4)


def test_the_space_rectangle_is_drawn_where_it_was_asked_for():
    print("\nthe space is drawn at the base point, at the size given")
    vm = run(w=300.0, h=200.0, base=(50.0, 25.0))
    box = [e for e in live(vm, 'LWPOLYLINE')
           if vm.layer_of(e) == 'CONSTELLATION-SPACE'][0]
    verts = [tuple(g[1:3]) for g in vm.entdata[box]
             if isinstance(g, list) and g[0] == 10]
    check("four corners, closed", len(verts) == 4
          and dxf(vm, box, 70) == 1)
    check("at the base point and the size asked for",
          verts == [(50.0, 25.0), (350.0, 25.0),
                    (350.0, 225.0), (50.0, 225.0)])


def test_the_run_leaves_the_drawing_as_it_found_it():
    print("\nsettings restored, one undo group, nothing left open")
    vm = run()
    check("CMDECHO is back", vm.sysvars['CMDECHO'] == 1)
    check("exactly one undo group, opened and closed",
          vm.commands.count(['_.UNDO', '_Begin']) == 1
          and vm.commands.count(['_.UNDO', '_End']) == 1)
    check("the undo group closed last",
          vm.commands[-1] == ['_.UNDO', '_End'])


def main():
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print("CONSTELLATION.lsp runtime tests -- tier: %s" % tier)
    for fn in (test_a_known_shape_comes_back,
               test_a_partial_chart_still_places_everything,
               test_five_points_with_gaps_in_the_chart,
               test_the_letters_run_clockwise,
               test_the_result_is_centred_in_the_space,
               test_a_point_with_one_dim_will_not_close_the_chart,
               test_two_groups_that_never_touch_are_refused,
               test_the_preview_is_erased,
               test_the_preview_can_be_swept_at_any_time,
               test_points_are_ab_pt_blocks_named_by_letter,
               test_one_aligned_dim_per_dim_given,
               test_a_dim_measures_the_points_it_belongs_to,
               test_cross_dims_lie_on_the_chord_and_perimeter_dims_stand_off,
               test_a_barely_rigid_chart_still_holds_every_dim,
               test_an_arc_pins_what_dims_alone_leave_loose,
               test_a_run_is_read_clockwise,
               test_an_arc_that_disagrees_with_the_dims_is_starred,
               test_the_outline_bends_round_a_declared_arc,
               test_a_two_point_arc_is_asked_which_way_it_bows,
               test_a_pair_can_be_typed_any_way_round,
               test_back_blanks_the_last_dim,
               test_dims_that_cannot_all_be_true_are_starred,
               test_one_bad_tape_is_named_not_smeared,
               test_a_constellation_too_big_for_its_space_is_said_so,
               test_a_wrong_number_can_be_put_right_after_seeing_the_drawing,
               test_an_arc_can_be_put_right_the_same_way,
               test_the_fix_pass_can_be_backed_out_of_without_emptying_the_chart,
               test_the_outline_is_optional,
               test_an_outline_that_crosses_itself_is_reported,
               test_the_space_rectangle_is_drawn_where_it_was_asked_for,
               test_the_run_leaves_the_drawing_as_it_found_it):
        try:
            fn()
        except LispError as e:
            check("%s raised: %s" % (fn.__name__, e), False)

    print("\n%d check(s) failed" % len(failures) if failures
          else "\nall checks passed")
    for f in failures:
        print("  - " + f)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
