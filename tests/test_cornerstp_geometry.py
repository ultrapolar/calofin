# SPDX-License-Identifier: GPL-3.0-or-later
"""Geometry regression tests for the AutoLISP step routines.

Covers CORNERSTP.lsp, HEMISTEP.lsp and NORMIESTEP.lsp.

The AutoLISP routines cannot run outside AutoCAD, so this module mirrors
their geometry helpers in Python and asserts the invariants the drawings
depend on: tread depths held exactly, held widths centred on the wall
opening, outermost steps landing wall-to-wall, and bulge/arc conversions
round-tripping.  Keeping the maths here means a change to either .lsp can
be re-verified without opening AutoCAD.

It also guards the packaging: the three routines ship as ONE release,
releases/STEPS_MMDDYY_REV##-##-##.lsp, holding each source verbatim.

Usage:  python3 tests/test_cornerstp_geometry.py
"""

import glob
import math
import os
import re

TOL_INCH = 0.125  # *cs-width-tol* default, 1/8"

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LISP_DIR = os.path.join(REPO_DIR, "lisp", "cornerstp")
RELEASES_DIR = os.path.join(REPO_DIR, "releases")
BUNDLE_MEMBERS = ["CORNERSTP.lsp", "HEMISTEP.lsp", "NORMIESTEP.lsp"]


# ---------------------------------------------------------------- helpers
# Mirrors of the cs-/hs- vector helpers in the .lsp files.

def vec(a, b):
    return (b[0] - a[0], b[1] - a[1])


def add(p, v):
    return (p[0] + v[0], p[1] + v[1])


def scl(v, s):
    return (v[0] * s, v[1] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def unit(v):
    length = math.hypot(*v)
    assert length > 1e-10, "zero-length vector"
    return (v[0] / length, v[1] / length)


def perp90(v):
    """cs-perp90: rotate 90 degrees counterclockwise (left normal)."""
    return (-v[1], v[0])


def mid2(a, b):
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)


def dist(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1])


def inters(p1, p2, p3, p4):
    """AutoLISP (inters ... nil): infinite-line intersection, or None."""
    x1, y1 = p1
    x2, y2 = p2
    x3, y3 = p3
    x4, y4 = p4
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if abs(den) < 1e-12:
        return None
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))


def beyond(p, a, b):
    """cs-beyond: how far P lies past the ends of segment A-B."""
    d = vec(a, b)
    length = math.hypot(*d)
    if length < 1e-10:
        return dist(p, a)
    t = dot(vec(a, p), d) / (length * length)
    if t < 0.0:
        return -t * length
    if t > 1.0:
        return (t - 1.0) * length
    return 0.0


def inspan(a, a1, a2):
    """cs-inspan: is angle A on the counterclockwise span A1 -> A2?"""
    end = a2 - a1
    if end < 0.0:
        end += 2 * math.pi
    a = a - a1
    if a < 0.0:
        a += 2 * math.pi
    return a <= end + 1e-9


def bulgearc(p1, p2, b):
    """cs-bulgearc: polyline bulge segment -> (center, radius, a1, a2)."""
    th = 4.0 * math.atan(b)
    length = dist(p1, p2)
    r = abs(length / (2.0 * math.sin(th / 2.0)))
    h = r * math.cos(abs(th) / 2.0)
    nrm = unit(perp90(vec(p1, p2)))
    cen = add(mid2(p1, p2), scl(nrm, h if b > 0.0 else -h))
    if b > 0.0:
        a1, a2 = math.atan2(*reversed(vec(cen, p1))), math.atan2(*reversed(vec(cen, p2)))
    else:
        a1, a2 = math.atan2(*reversed(vec(cen, p2))), math.atan2(*reversed(vec(cen, p1)))
    if a2 < a1:
        a2 += 2 * math.pi
    return cen, r, a1, a2


def autotol(insunits):
    """cs-autotol: 1/8 inch expressed in the drawing's units."""
    return {1: 0.125, 2: 0.125 / 12.0, 4: 3.175, 5: 0.3175,
            6: 0.003175}.get(insunits, 0.125)


def resolve(wid, nat, h1, h2, p, perp, tol):
    """cs-resolve: returns (e1, e2, mode) or None when the step is skipped."""
    if wid is None:
        return (h1, h2, "fit") if nat is not None else None
    if nat is not None and abs(nat - wid) <= tol:
        return (h1, h2, "fit")
    if nat is not None:
        u = unit(vec(h2, h1))
        cen = mid2(h1, h2)
        return add(cen, scl(u, 0.5 * wid)), add(cen, scl(u, -0.5 * wid)), "held"
    return (add(p, scl(perp, 0.5 * wid)),
            add(p, scl(perp, -0.5 * wid)), "held")


def corner_setup(deg1, deg2, length=400.0):
    """Two walls meeting at the origin at the given headings."""
    w1 = ((0.0, 0.0), (length * math.cos(math.radians(deg1)),
                       length * math.sin(math.radians(deg1))))
    w2 = ((0.0, 0.0), (length * math.cos(math.radians(deg2)),
                       length * math.sin(math.radians(deg2))))
    return w1, w2


def bisector(w1, w2, corner=(0.0, 0.0)):
    """cs- bisector: equal angle from both walls, pointing into the pool."""
    d1 = unit(vec(corner, w1[1]))
    d2 = unit(vec(corner, w2[1]))
    return unit(add(d1, d2))


def wall_hits(p, perp, w1, w2):
    h1 = inters(p, add(p, perp), *w1)
    h2 = inters(p, add(p, perp), *w2)
    nat = dist(h1, h2) if (h1 and h2) else None
    return h1, h2, nat


# ------------------------------------------------------------------ tests

def test_inside_out_holds_tread_depths():
    """Depths are cumulative along the bisector and exact, whatever the width."""
    w1, w2 = corner_setup(0.0, 90.0)
    bis = bisector(w1, w2)
    perp = unit(perp90(bis))
    cum = 0.0
    previous = (0.0, 0.0)
    for depth, width in ((24.0, 48.0), (12.0, 72.0), (12.0, None)):
        cum += depth
        p = add((0.0, 0.0), scl(bis, cum))
        # perpendicular distance travelled must equal the depth entered
        assert abs(abs(dot(vec(previous, p), bis)) - depth) < 1e-9
        h1, h2, nat = wall_hits(p, perp, w1, w2)
        got = resolve(width, nat, h1, h2, p, perp, TOL_INCH)
        assert got is not None
        previous = p
    assert abs(cum - 48.0) < 1e-9


def test_held_width_is_centred_between_the_walls():
    """A held width overhangs both walls equally, even on a skewed corner."""
    for deg2 in (60.0, 90.0, 115.0):
        w1, w2 = corner_setup(0.0, deg2)
        bis = bisector(w1, w2)
        perp = unit(perp90(bis))
        p = add((0.0, 0.0), scl(bis, 30.0))
        h1, h2, nat = wall_hits(p, perp, w1, w2)
        e1, e2, mode = resolve(nat + 10.0, nat, h1, h2, p, perp, TOL_INCH)
        assert mode == "held"
        assert abs(dist(e1, e2) - (nat + 10.0)) < 1e-9, "width must be exact"
        # equal overhang past each wall hit
        assert abs(dist(e1, h1) - dist(e2, h2)) < 1e-9


def test_width_within_tolerance_snaps_to_the_walls():
    w1, w2 = corner_setup(0.0, 90.0)
    bis = bisector(w1, w2)
    perp = unit(perp90(bis))
    p = add((0.0, 0.0), scl(bis, 40.0))
    h1, h2, nat = wall_hits(p, perp, w1, w2)
    inside = resolve(nat + TOL_INCH * 0.5, nat, h1, h2, p, perp, TOL_INCH)
    outside = resolve(nat + TOL_INCH * 2.0, nat, h1, h2, p, perp, TOL_INCH)
    assert inside[2] == "fit", "within 1/8 inch must trim to the walls"
    assert outside[2] == "held", "beyond 1/8 inch must hold the width"


def test_outside_in_first_step_lands_wall_to_wall():
    """The outermost width alone positions the step, on skewed corners too."""
    for deg2 in (75.0, 90.0, 120.0):
        w1, w2 = corner_setup(0.0, deg2)
        bis = bisector(w1, w2)
        perp = unit(perp90(bis))
        # opening at unit distance scales linearly with distance
        _, _, op1 = wall_hits(add((0.0, 0.0), bis), perp, w1, w2)
        want = 96.0
        t = want / op1
        h1, h2, nat = wall_hits(add((0.0, 0.0), scl(bis, t)), perp, w1, w2)
        assert abs(nat - want) < 1e-6, f"{deg2}: got {nat}"


def test_outside_in_walks_in_by_exact_depths():
    w1, w2 = corner_setup(0.0, 75.0)
    bis = bisector(w1, w2)
    perp = unit(perp90(bis))
    _, _, op1 = wall_hits(add((0.0, 0.0), bis), perp, w1, w2)
    t = 96.0 / op1
    previous = add((0.0, 0.0), scl(bis, t))
    for depth in (12.0, 12.0, 10.0):
        t -= depth
        p = add((0.0, 0.0), scl(bis, t))
        assert abs(abs(dot(vec(previous, p), bis)) - depth) < 1e-9
        previous = p
    assert t > 0.0, "should not have reached the corner yet"


def test_equidistant_mode_is_symmetric_about_the_corner():
    """Equidistant option puts both step ends the same distance from the corner."""
    w1, w2 = corner_setup(0.0, 75.0)
    bis = bisector(w1, w2)
    perp = unit(perp90(bis))
    p = add((0.0, 0.0), scl(bis, 40.0))
    h1, h2, _ = wall_hits(p, perp, w1, w2)
    assert abs(dist((0.0, 0.0), h1) - dist((0.0, 0.0), h2)) < 1e-9


def test_beyond_flags_walls_that_had_to_be_extended():
    a, b = (0.0, 0.0), (10.0, 0.0)
    assert beyond((5.0, 0.0), a, b) == 0.0
    assert abs(beyond((13.0, 0.0), a, b) - 3.0) < 1e-12
    assert abs(beyond((-2.0, 0.0), a, b) - 2.0) < 1e-12
    # a point off to the side but within the span is still "on" the wall
    assert beyond((5.0, 4.0), a, b) == 0.0


def test_inspan_handles_wraparound():
    assert inspan(math.radians(10.0), math.radians(350.0), math.radians(20.0))
    assert not inspan(math.radians(180.0), math.radians(350.0),
                      math.radians(20.0))
    assert inspan(0.0, 0.0, math.radians(90.0)), "start angle is on the span"


def test_bulgearc_round_trips():
    """Bulge -> arc keeps both endpoints on the circle, for either direction."""
    cases = [
        ((1.0, 0.0), (0.0, 1.0), math.tan(math.radians(22.5)), 1.0),   # 90 CCW
        ((1.0, 0.0), (0.0, 1.0), math.tan(math.radians(67.5)), 1.0),   # 270 CCW
        ((1.0, 0.0), (0.0, 1.0), -math.tan(math.radians(22.5)), 1.0),  # 90 CW
        ((0.0, 0.0), (50.0, 0.0), 0.5, 31.25),                         # flat arc
    ]
    for p1, p2, b, want_r in cases:
        cen, r, a1, a2 = bulgearc(p1, p2, b)
        assert abs(r - want_r) < 1e-9, f"bulge {b}: r={r}"
        assert abs(dist(cen, p1) - r) < 1e-9
        assert abs(dist(cen, p2) - r) < 1e-9
        assert a2 > a1, "normalised span must run counterclockwise"
        span = a2 - a1
        assert abs(span - 4.0 * abs(math.atan(b))) < 1e-9


def test_bulgearc_quarter_circle_centre():
    cen, r, _, _ = bulgearc((1.0, 0.0), (0.0, 1.0),
                            math.tan(math.radians(22.5)))
    assert abs(cen[0]) < 1e-9 and abs(cen[1]) < 1e-9, cen
    assert abs(r - 1.0) < 1e-9


def test_autotol_tracks_insunits():
    assert autotol(1) == 0.125                       # inches
    assert abs(autotol(4) - 3.175) < 1e-12           # millimetres
    assert abs(autotol(2) - 0.125 / 12.0) < 1e-12    # feet
    assert autotol(0) == 0.125                       # unitless -> inches
    # 1/8 inch is the same physical size in every supported unit
    assert abs(autotol(4) / 25.4 - autotol(1)) < 1e-9
    assert abs(autotol(6) * 1000.0 - autotol(4)) < 1e-9


def test_dimension_chain_and_nesting():
    """Depth dims chain cumulatively; width dims nest further out as they grow."""
    w1, w2 = corner_setup(0.0, 90.0)
    bis = bisector(w1, w2)
    txth = 0.18 * 1.5
    cum = 0.0
    chain, offsets = [], []
    for depth, width in ((24.0, 48.0), (12.0, 72.0), (12.0, 96.0)):
        cum += depth
        p = add((0.0, 0.0), scl(bis, cum))
        start = add(p, scl(bis, -depth))
        chain.append(dist(start, p))
        # width dim sits behind the corner by half its own width
        thru = add((0.0, 0.0), scl(bis, -(0.5 * width + 1.5 * txth)))
        offsets.append(dot(vec((0.0, 0.0), thru), bis))
    assert [round(c, 9) for c in chain] == [24.0, 12.0, 12.0]
    assert all(b < a for a, b in zip(offsets, offsets[1:])), \
        "wider steps must nest further outside the corner"


def test_hemistep_chords_are_parallel_and_centred():
    """HEMISTEP: every chord is centred on the axis and parallel to the base."""
    base_mid = (0.0, 0.0)
    u = (0.0, 1.0)            # base line direction
    direction = (1.0, 0.0)    # steps march this way
    cum = 0.0
    for width, depth in ((240.0, 13.0), (216.0, 12.0), (168.0, 16.0)):
        cum += depth
        p = add(base_mid, scl(direction, cum))
        e1 = add(p, scl(u, 0.5 * width))
        e2 = add(p, scl(u, -0.5 * width))
        assert abs(dist(e1, e2) - width) < 1e-9
        assert abs(dot(unit(vec(e1, e2)), direction)) < 1e-9, "must be parallel"
        assert dist(mid2(e1, e2), p) < 1e-9, "must be centred on the axis"


def test_hemistep_arc_mode_breaks_curve_equally():
    """A held width overshoots the arc by the same amount at both ends."""
    centre, radius = (0.0, 0.0), 100.0
    crown = (100.0, 0.0)
    direction = unit(vec(crown, centre))   # into the curve
    u = perp90(direction)
    p = add(crown, scl(direction, 20.0))
    # chord of the circle at this depth
    half = math.sqrt(radius ** 2 - (radius - 20.0) ** 2)
    q1, q2 = add(p, scl(u, half)), add(p, scl(u, -half))
    opening = dist(q1, q2)
    held = opening + 6.0
    cen = mid2(q1, q2)
    e1, e2 = add(cen, scl(u, held / 2)), add(cen, scl(u, -held / 2))
    assert abs(dist(e1, e2) - held) < 1e-9
    assert abs((dist(e1, centre) - radius) - (dist(e2, centre) - radius)) < 1e-9


# --------------------------------------------- HEMISTEP curve pieces
# Mirrors of hs-hits / hs-open: the selected curve becomes a list of
# boundary pieces, ("A", centre, radius, a1, a2) or ("S", p1, p2), so an
# arc, a circle and a multi-arc polyline are all handled alike.

def linecirc(a, d, c, r):
    """hs-linecirc: the 2 crossings of line (a, unit d) with circle (c, r)."""
    f = vec(c, a)
    g = dot(d, f)
    disc = r * r + g * g - dot(f, f)
    if disc < 0.0:
        return []
    disc = math.sqrt(disc)
    return [add(a, scl(d, -g - disc)), add(a, scl(d, -g + disc))]


def hits(p, u, pieces):
    """hs-hits: every crossing of the line with the curve."""
    out = []
    for pc in pieces:
        if pc[0] == "A":
            _, c, r, a1, a2 = pc
            for q in linecirc(p, u, c, r):
                if inspan(math.atan2(q[1] - c[1], q[0] - c[0]), a1, a2):
                    out.append(q)
        else:
            q = inters(p, add(p, u), pc[1], pc[2])
            if q is not None and beyond(q, pc[1], pc[2]) < 1e-8:
                out.append(q)
    return out


def opening(p, u, pieces):
    """hs-open: the nearest crossing either side of P, as (h1, h2, width)."""
    sp = sn = h1 = h2 = None
    for q in hits(p, u, pieces):
        s = dot(vec(p, q), u)
        if s > 1e-9:
            if sp is None or s < sp:
                sp, h1 = s, q
        elif s < -1e-9:
            if sn is None or s > sn:
                sn, h2 = s, q
    if h1 is None or h2 is None:
        return None
    return h1, h2, sp - sn


def semicircle(radius=100.0, pieces_count=1):
    """The right half of a circle at the origin, split into N arc pieces."""
    start, sweep = -math.pi / 2, math.pi
    out = []
    for k in range(pieces_count):
        a1 = start + sweep * k / pieces_count
        a2 = start + sweep * (k + 1) / pieces_count
        out.append(("A", (0.0, 0.0), radius, a1 % (2 * math.pi),
                    a2 % (2 * math.pi) if a2 < 0 else a2))
    return out


def blgs(pts, k=None, fixed=None):
    """hs-blgs: one bulge per segment, fitted through consecutive triples.

    When k (the crown vertex index) is given, the arc across the crown is
    fitted first and the rest fan outward from it, so the apex sits inside
    a single arc instead of on a seam between two circles.  `fixed` maps a
    segment index to a bulge that wins over any fitting; when it holds the
    middle segment the rest are fitted outward from there.
    """

    def circum(a, b, q):
        ax, ay = a
        bx, by = b
        qx, qy = q
        d = 2 * (ax * (by - qy) + bx * (qy - ay) + qx * (ay - by))
        if abs(d) < 1e-12:
            return None
        ux = ((ax * ax + ay * ay) * (by - qy) + (bx * bx + by * by) * (qy - ay)
              + (qx * qx + qy * qy) * (ay - by)) / d
        uy = ((ax * ax + ay * ay) * (qx - bx) + (bx * bx + by * by) * (ax - qx)
              + (qx * qx + qy * qy) * (bx - ax)) / d
        return (ux, uy)

    def cross(a, b):
        return a[0] * b[1] - a[1] * b[0]

    def segb(a, b, o, ccw):
        t1 = math.atan2(a[1] - o[1], a[0] - o[0])
        t2 = math.atan2(b[1] - o[1], b[0] - o[0])
        th = (t2 - t1) if ccw else (t1 - t2)
        if th < 0:
            th += 2 * math.pi
        return (1 if ccw else -1) * math.tan(th / 4)

    nseg = len(pts) - 1
    if k is not None and not (1 <= k <= nseg - 1):
        k = None
    starts = []
    if k is not None:
        starts.append(k - 1)                 # the arc across the crown
        i = k - 3
        while i >= 0:
            starts.append(i)
            i -= 2
        i = k + 1
        while i + 2 <= nseg:
            starts.append(i)
            i += 2
    elif fixed:
        m = min(fixed)                       # outward from the fixed segment
        i = m - 2
        while i >= 0:
            starts.append(i)
            i -= 2
        i = m + 1
        while i + 2 <= nseg:
            starts.append(i)
            i += 2
    else:
        i = 0
        while i + 2 <= nseg:
            starts.append(i)
            i += 2
    i = 0                                    # fallback sweep for leftovers
    while i + 2 <= nseg:
        starts.append(i)
        i += 1
    res = dict(fixed) if fixed else {}
    for st in starts:
        p, q, s = pts[st], pts[st + 1], pts[st + 2]
        o = circum(p, q, s)
        if not o:
            continue
        ccw = cross(vec(p, q), vec(p, s)) > 0
        res.setdefault(st, safeb(segb(p, q, o, ccw)))
        res.setdefault(st + 1, safeb(segb(q, s, o, ccw)))
    return [res.get(i, 0.0) for i in range(nseg)]


def arc_from_bulge(a, b, bulge):
    """Reconstruct (centre, radius) from a chord and its polyline bulge.

    Mirrors hs-bulgearc: a positive bulge is counterclockwise, so the
    centre lies to the left of a -> b.  h is signed via cos(theta/2), which
    flips the centre across the chord once the arc passes 180 degrees.
    """
    chord = dist(a, b)
    th = 4 * math.atan(abs(bulge))       # magnitude of the included angle
    r = chord / (2 * math.sin(th / 2))
    h = r * math.cos(th / 2)             # negative when th > pi
    mx, my = mid2(a, b)
    ux, uy = unit(vec(a, b))
    nx, ny = (-uy, ux)                   # left normal of a -> b
    sign = 1 if bulge > 0 else -1
    return (mx + sign * h * nx, my + sign * h * ny), r


def test_opening_matches_the_true_chord():
    pieces = semicircle()
    crown = (100.0, 0.0)
    direction = unit(vec(crown, (0.0, 0.0)))
    u = perp90(direction)
    for depth in (5.0, 20.0, 50.0, 90.0):
        p = add(crown, scl(direction, depth))
        got = opening(p, u, pieces)
        assert got is not None, depth
        want = 2 * math.sqrt(100.0 ** 2 - (100.0 - depth) ** 2)
        assert abs(got[2] - want) < 1e-9, f"depth {depth}: {got[2]} vs {want}"


def test_opening_uses_the_nearest_crossing_not_the_extremes():
    """A far-off boundary piece must not widen the local opening."""
    pieces = semicircle() + [("S", (-500.0, 300.0), (500.0, 300.0))]
    p = (80.0, 0.0)
    u = (0.0, 1.0)
    got = opening(p, u, pieces)
    assert abs(got[2] - 120.0) < 1e-9, got[2]
    assert abs(got[0][1] - 60.0) < 1e-9, "must stop at the arc, not the wall"


def test_composite_curve_matches_a_single_arc():
    """A hemisphere split into several arcs gives the same openings."""
    single = semicircle(pieces_count=1)
    for count in (2, 3, 5):
        split = semicircle(pieces_count=count)
        for depth in (10.0, 35.0, 75.0):
            p = add((100.0, 0.0), scl(unit(vec((100.0, 0.0), (0.0, 0.0))), depth))
            a = opening(p, (0.0, 1.0), single)
            b = opening(p, (0.0, 1.0), split)
            assert a is not None and b is not None, (count, depth)
            assert abs(a[2] - b[2]) < 1e-9, f"{count} pieces at {depth}"


def test_full_circle_piece_spans_everywhere():
    circle = [("A", (0.0, 0.0), 100.0, 0.0, 2 * math.pi)]
    for angle in (0.0, 1.0, 3.0, 5.0):
        d = (math.cos(angle), math.sin(angle))
        got = opening((0.0, 0.0), d, circle)
        assert got is not None
        assert abs(got[2] - 200.0) < 1e-9, "every chord through the centre"


def test_opening_is_none_outside_the_curve():
    pieces = semicircle()
    # well past the flat side of the semicircle: nothing brackets the point
    assert opening((-50.0, 0.0), (0.0, 1.0), pieces) is None


def test_boundary_polyline_bulges_are_real_arcs():
    """Each bulged segment reconstructs to a circle through its endpoints."""
    side_a = [(1247.298, 463.447), (1259.298, 451.447),
              (1275.298, 427.447), (1285.298, 403.447)]
    crown = (1294.751, 343.447)
    side_b = [(x, 2 * 343.447 - y) for (x, y) in side_a]
    pts = side_a + [crown] + list(reversed(side_b))
    bulges = blgs(pts)
    assert len(bulges) == len(pts) - 1
    for i, bulge in enumerate(bulges):
        if bulge == 0.0:
            continue
        centre, r = arc_from_bulge(pts[i], pts[i + 1], bulge)
        assert abs(dist(centre, pts[i]) - r) < 1e-6
        assert abs(dist(centre, pts[i + 1]) - r) < 1e-6
    # the curve must come out symmetric about the axis
    assert all(abs(abs(bulges[i]) - abs(bulges[-1 - i])) < 1e-9
               for i in range(len(bulges)))


def test_crown_anchored_fit_reproduces_the_original_curve():
    """Steps sitting on the arc must rebuild that exact arc beside the crown.

    This is the curve-mode boundary: deepest step -> side A -> the original
    point where the axis met the curve -> side B.  The crown's neighbours
    are the widest step's ends, which lie on the curve when that step was
    fitted, so the arc through them is the original circle.
    """
    radius = 100.0
    centre = (0.0, 0.0)
    crown = (radius, 0.0)
    direction = unit(vec(crown, centre))
    u = perp90(direction)
    # three steps fitted to the curve at increasing depth
    side_a, side_b = [], []
    for depth in (10.0, 26.0, 44.0):
        p = add(crown, scl(direction, depth))
        half = math.sqrt(radius ** 2 - (radius - depth) ** 2)
        side_a.append(add(p, scl(u, half)))
        side_b.append(add(p, scl(u, -half)))
    pts = list(reversed(side_a)) + [crown] + side_b
    k = len(side_a)
    bulges = blgs(pts, k)
    # the two segments touching the crown must lie on the original circle
    for seg in (k - 1, k):
        got_centre, got_r = arc_from_bulge(pts[seg], pts[seg + 1], bulges[seg])
        assert abs(got_r - radius) < 1e-6, f"seg {seg}: r={got_r}"
        assert dist(got_centre, centre) < 1e-6, f"seg {seg}: c={got_centre}"


def test_crown_anchored_fit_keeps_the_apex_on_one_arc():
    """Both crown segments share a circle; left-to-right pairing may not.

    Pairing from index 0 puts segments (0,1), (2,3), (4,5)... on one circle
    each, so an apex at an even vertex index lands on the seam between two
    circles - a kink at the crown.  Anchoring at the crown fixes that
    whatever the step count.
    """
    side_a = [(1247.298, 463.447), (1259.298, 451.447),
              (1275.298, 427.447), (1285.298, 403.447)]
    crown = (1294.751, 343.447)
    side_b = [(x, 2 * 343.447 - y) for (x, y) in side_a]
    pts = side_a + [crown] + list(reversed(side_b))
    k = len(side_a)                           # 4 - an even index
    anchored = blgs(pts, k)
    left = arc_from_bulge(pts[k - 1], pts[k], anchored[k - 1])
    right = arc_from_bulge(pts[k], pts[k + 1], anchored[k])
    assert abs(left[1] - right[1]) < 1e-6, "apex must sit inside one arc"
    assert dist(left[0], right[0]) < 1e-6
    # The un-anchored fit puts the apex on a seam between two circles.
    # They are mirror images, so they share a radius - only the centres
    # reveal the kink.
    plain = blgs(pts)
    lp = arc_from_bulge(pts[k - 1], pts[k], plain[k - 1])
    rp = arc_from_bulge(pts[k], pts[k + 1], plain[k])
    assert dist(lp[0], rp[0]) > 1e-6, "un-anchored fit should seam here"
    # anchoring must not break the symmetry the un-anchored fit had
    assert all(abs(abs(anchored[i]) - abs(anchored[-1 - i])) < 1e-9
               for i in range(len(anchored)))


def segb_about(a, b, centre, ccw):
    """hs-segb: the bulge for a -> b travelling round CENTRE."""
    t1 = math.atan2(a[1] - centre[1], a[0] - centre[0])
    t2 = math.atan2(b[1] - centre[1], b[0] - centre[0])
    th = (t2 - t1) if ccw else (t1 - t2)
    if th < 0:
        th += 2 * math.pi
    return (1 if ccw else -1) * math.tan(th / 4)


def bulgemid(a, b, bulge):
    """hs-bulgemid: midpoint of the arc a chord carries with this bulge."""
    d = vec(a, b)
    nrm = unit((d[1], -d[0]))            # right normal; +bulge bulges right
    return add(mid2(a, b), scl(nrm, 0.5 * dist(a, b) * bulge))


def safeb(bulge):
    """hs-safeb: a sweep past half a circle folds back, so draw it straight."""
    return 0.0 if bulge is None or abs(bulge) > 1.0 else bulge


def firstspan(a, b, centre, ref):
    """hs-firstspan: span a -> b on the original circle, on REF's side.

    The side is chosen geometrically - whichever arc bulges nearer REF -
    so no angle-wrap case can pick the wrong one, and the choice does not
    depend on the order a/b are given in.
    """
    b1 = segb_about(a, b, centre, True)
    b2 = segb_about(a, b, centre, False)
    bulge = b1 if dist(bulgemid(a, b, b1), ref) < dist(bulgemid(a, b, b2),
                                                       ref) else b2
    return safeb(bulge)


def curve_mode_steps(radius, plan, centre=(0.0, 0.0)):
    """Steps marched into a circle from its crown; plan is (depth, width|None).

    A width of None means the step was fitted to the curve at that depth.
    Returns (crown, direction, u, side_a, side_b).
    """
    crown = (radius, 0.0)
    direction = unit(vec(crown, centre))
    u = perp90(direction)
    prev, side_a, side_b = crown, [], []
    for depth, width in plan:
        p = add(prev, scl(direction, depth))
        travelled = dist(crown, p)
        if width is None:                    # fitted: use the true chord
            half = math.sqrt(radius ** 2 - (radius - travelled) ** 2)
        else:
            half = width / 2.0
        side_a.append(add(p, scl(u, half)))
        side_b.append(add(p, scl(u, -half)))
        prev = p
    return crown, direction, u, side_a, side_b


def test_curve_mode_boundary_spans_the_first_step_on_the_original_arc():
    """A first step fitted to the curve must rebuild that curve exactly."""
    radius, centre = 500.0, (0.0, 0.0)
    crown, _, _, side_a, side_b = curve_mode_steps(
        radius, [(12.0, None), (12.0, None), (12.0, None)])
    pts = list(reversed(side_a)) + side_b
    m = len(side_a) - 1                      # the segment across step 1
    fixed = {m: firstspan(side_a[0], side_b[0], centre, crown)}
    bulges = blgs(pts, None, fixed)
    got_centre, got_r = arc_from_bulge(pts[m], pts[m + 1], bulges[m])
    assert abs(got_r - radius) < 1e-6, got_r
    assert dist(got_centre, centre) < 1e-6, got_centre
    # and it still passes through the crown of the original arc
    assert abs(dist(got_centre, crown) - got_r) < 1e-6


def test_curve_mode_boundary_does_not_spike_at_the_crown():
    """A held width wider than the curve must not drag the boundary inward.

    Inserting the crown as a vertex made the boundary dive from the wide
    first step to a point only one depth away - the spike.  Spanning the
    first step with the original curve's own bulge keeps the arc concentric
    with the curve instead.
    """
    radius, centre = 500.0, (0.0, 0.0)
    plan = [(12.0, 300.0), (12.0, 360.0), (12.0, 420.0), (12.0, 470.0)]
    crown, _, _, side_a, side_b = curve_mode_steps(radius, plan)
    # the first step is far wider than the curve's opening at that depth
    opening = 2 * math.sqrt(radius ** 2 - (radius - 12.0) ** 2)
    assert 300.0 > opening, "test needs a step that breaks the curve"

    # old behaviour: crown inserted as a vertex
    old_pts = list(reversed(side_a)) + [crown] + side_b
    n = len(side_a)
    old = blgs(old_pts, n)
    _, old_r = arc_from_bulge(old_pts[n - 1], old_pts[n], old[n - 1])

    # new behaviour: no crown vertex, original curve spans the first step
    pts = list(reversed(side_a)) + side_b
    m = n - 1
    fixed = {m: firstspan(side_a[0], side_b[0], centre, crown)}
    new = blgs(pts, None, fixed)
    new_centre, new_r = arc_from_bulge(pts[m], pts[m + 1], new[m])

    assert dist(new_centre, centre) < 1e-6, "must stay concentric"
    assert abs(new_r - radius) < 0.05 * radius, f"r={new_r} vs {radius}"
    assert abs(old_r - radius) > 0.5 * radius, \
        "the old fit should have deviated wildly"
    assert all(abs(abs(new[i]) - abs(new[-1 - i])) < 1e-9
               for i in range(len(new))), "boundary must stay symmetric"


def test_first_span_picks_the_crown_side_either_way_round():
    """The side is chosen geometrically, so a/b order cannot flip the arc."""
    radius, centre = 500.0, (0.0, 0.0)
    crown = (radius, 0.0)
    half = math.sqrt(radius ** 2 - (radius - 12.0) ** 2)
    a, b = (488.0, -half), (488.0, half)
    forward = firstspan(a, b, centre, crown)
    backward = firstspan(b, a, centre, crown)
    # same arc, described from either end
    assert dist(bulgemid(a, b, forward), bulgemid(b, a, backward)) < 1e-9
    # and it bulges toward the crown, not away from it
    assert bulgemid(a, b, forward)[0] > 488.0
    assert dist(bulgemid(a, b, forward), crown) < 1e-9
    assert abs(forward) <= 1.0, "must be the minor arc"


def test_first_span_rejects_a_fold():
    """An arc sweeping past half a circle would spike, so it closes straight."""
    radius, centre = 500.0, (0.0, 0.0)
    # a chord subtending 120 degrees: the arc away from it sweeps 240
    a = (radius * math.cos(math.radians(-60)), radius * math.sin(math.radians(-60)))
    b = (radius * math.cos(math.radians(60)), radius * math.sin(math.radians(60)))
    near_side = (radius, 0.0)                # the 120-degree arc
    far_side = (-radius, 0.0)                # the 240-degree arc - a fold
    assert abs(firstspan(a, b, centre, near_side) - math.tan(math.radians(30))) < 1e-9
    assert firstspan(a, b, centre, far_side) == 0.0
    # an exact semicircle is not a fold and is kept
    assert abs(abs(firstspan((0.0, -radius), (0.0, radius), centre,
                             (-radius, 0.0))) - 1.0) < 1e-9
    # a genuine shallow arc is kept untouched
    half = math.sqrt(radius ** 2 - (radius - 12.0) ** 2)
    kept = firstspan((488.0, -half), (488.0, half), centre, (radius, 0.0))
    assert kept != 0.0 and abs(kept) < 0.2


def test_safeb_clamps_folding_segments():
    assert safeb(0.5) == 0.5
    assert safeb(-0.5) == -0.5
    assert safeb(1.0) == 1.0                 # exactly a semicircle is fine
    assert safeb(1.4) == 0.0
    assert safeb(-3.0) == 0.0
    assert safeb(None) == 0.0


def test_no_boundary_segment_folds_back():
    """Every segment of a rebuilt boundary must turn the same way as the run."""
    radius, centre = 500.0, (0.0, 0.0)
    plan = [(12.0, None), (12.0, 360.0), (12.0, 420.0), (12.0, 470.0)]
    crown, _, _, side_a, side_b = curve_mode_steps(radius, plan)
    pts = list(reversed(side_a)) + side_b
    m = len(side_a) - 1
    fixed = {m: firstspan(side_a[0], side_b[0], centre, crown)}
    bulges = blgs(pts, None, fixed)
    for i, bulge in enumerate(bulges):
        assert abs(bulge) <= 1.0, f"segment {i} folds: bulge={bulge}"


def test_line_mode_boundary_is_anchored_at_the_wall():
    """The base-line boundary starts and ends on the wall, not at step 1."""
    base_mid = (0.0, 0.0)
    u = (0.0, 1.0)
    direction = (1.0, 0.0)
    wall_width = 257.6
    wall_a = add(base_mid, scl(u, wall_width / 2))
    wall_b = add(base_mid, scl(u, -wall_width / 2))
    side_a, side_b, prev = [], [], base_mid
    for depth, width in ((13.0, 240.0), (12.0, 216.0), (16.0, 168.0)):
        p = add(prev, scl(direction, depth))
        side_a.append(add(p, scl(u, width / 2)))
        side_b.append(add(p, scl(u, -width / 2)))
        prev = p
    crown = add(prev, scl(direction, 9.45))
    pts = [wall_a] + side_a + [crown] + list(reversed(side_b)) + [wall_b]
    k = 1 + len(side_a)
    assert pts[0] == wall_a and pts[-1] == wall_b
    assert pts[k] == crown, "crown index must point at the crown vertex"
    # both wall vertices sit exactly on the base line (x = 0 here)
    assert abs(pts[0][0]) < 1e-12 and abs(pts[-1][0]) < 1e-12
    bulges = blgs(pts, k)
    assert len(bulges) == len(pts) - 1
    # the first arc leaves the wall and passes through step 1's end
    centre, r = arc_from_bulge(pts[0], pts[1], bulges[0])
    assert abs(dist(centre, pts[0]) - r) < 1e-6
    assert abs(dist(centre, pts[1]) - r) < 1e-6
    # and the whole curve stays symmetric about the axis
    assert all(abs(abs(bulges[i]) - abs(bulges[-1 - i])) < 1e-9
               for i in range(len(bulges)))


def test_depths_are_measured_from_the_previous_step():
    """12, 12, 12, 14 must give those spacings, not a running total."""
    start, prev, positions, spacings = 0.0, 0.0, [], []
    for depth in (12.0, 12.0, 12.0, 14.0):
        p = prev + depth              # p = previous edge + depth
        spacings.append(p - prev)
        positions.append(p - start)
        prev = p
    assert spacings == [12.0, 12.0, 12.0, 14.0]
    assert positions == [12.0, 24.0, 36.0, 50.0]


def test_boundary_polyline_pairs_share_a_circle():
    """Segments fitted from one triple lie on the same arc, as 3-point arcs do."""
    pts = [(0.0, 0.0), (10.0, 6.0), (24.0, 8.0), (40.0, 6.0), (50.0, 0.0)]
    bulges = blgs(pts)
    first = arc_from_bulge(pts[0], pts[1], bulges[0])[1]
    second = arc_from_bulge(pts[1], pts[2], bulges[1])[1]
    assert abs(first - second) < 1e-6, "a triple's two segments share a radius"


# ------------------------------------------------- NORMIESTEP modes
# Mirrors of the three ways NORMIESTEP places its constant-width treads.

def ptline(p, a, b):
    """ns-ptline: perpendicular distance from P to the line through A-B."""
    d = unit(vec(a, b))
    return abs(d[0] * (p[1] - a[1]) - d[1] * (p[0] - a[0]))


def normie_line_mode(base, side_point, width, depths):
    """One line: treads centred on it, marching toward SIDE_POINT."""
    sp = mid2(*base)
    u = unit(vec(*base))
    signed = dot(vec(sp, side_point), perp90(u))
    direction = unit(scl(perp90(u), 1.0 if signed > 0 else -1.0))
    prev, out = sp, []
    for depth in depths:
        p = add(prev, scl(direction, depth))
        out.append((add(p, scl(u, width / 2)), add(p, scl(u, -width / 2)), p))
        prev = p
    return sp, u, direction, out


def normie_corner_mode(base, side, width, depths, corner=(0.0, 0.0)):
    """Two lines: treads parallel to BASE, butting against SIDE.

    The run sits in a recess OUTSIDE the corner.  Both lines run away
    from the corner into the pool, so the water is the side they span
    and the steps go the other way - away from SIDE, out through the
    wall they come off.  The treads meet SIDE past its end, on the
    stretch of it that closes the recess.
    """
    u = unit(vec(corner, base[1]))
    toward = unit(vec(corner, side[1]))
    pd = perp90(u)
    direction = unit(scl(pd, -1.0 if dot(pd, toward) > 0 else 1.0))
    prev, out = corner, []
    for depth in depths:
        p = add(prev, scl(direction, depth))
        inner = inters(p, add(p, u), *side)
        out.append((inner, add(inner, scl(u, width)), p))
        prev = p
    return u, direction, out


def normie_u_mode(arm1, arm2, base, depths):
    """A U: the BASE is the wall the steps come off.

    The run starts on the base and marches out toward the open end,
    treads parallel to the base and trimmed to the arms.  ARM1[0] and
    ARM2[0] are the free ends.
    """
    u = unit(vec(*base))
    mouth = mid2(arm1[0], arm2[0])
    base_mid = mid2(*base)
    pd = perp90(u)
    direction = unit(scl(pd, 1.0 if dot(pd, vec(base_mid, mouth)) > 0 else -1.0))
    prev, out, stopped = base_mid, [], False
    for depth in depths:
        p = add(prev, scl(direction, depth))
        # out past BOTH free ends: the U is used up
        if (dot(vec(p, arm1[0]), direction) < 0.0
                and dot(vec(p, arm2[0]), direction) < 0.0):
            stopped = True
            break
        out.append((inters(p, add(p, u), *arm1),
                    inters(p, add(p, u), *arm2), p))
        prev = p
    return u, direction, out, stopped


def u_back_corner(base, arm, kind, off):
    """ns-ucorner: the back corner where ARM meets the base of a U.

    Returns (on_base, on_arm[, centre]) - a diagonal joins the two
    tangent points, a fillet arc of radius OFF is tangent at them.  The
    corner is cut INTO the U, so both points sit inboard of the square
    corner they replace.
    """
    def to_arm(q):
        return min(dist(q, arm[0]), dist(q, arm[1]))
    b1, b2 = (base if to_arm(base[0]) < to_arm(base[1]) else base[::-1])
    far = arm[0] if dist(arm[0], b1) > dist(arm[1], b1) else arm[1]
    ub, ua = unit(vec(b1, b2)), unit(vec(b1, far))
    t1, t2 = add(b1, scl(ub, off)), add(b1, scl(ua, off))
    if kind == "Radius":
        return t1, t2, add(t1, scl(ua, off))
    return t1, t2


def test_normie_line_mode_is_centred_and_constant():
    base = ((0.0, 0.0), (200.0, 0.0))
    width = 120.0
    sp, u, direction, steps = normie_line_mode(
        base, (100.0, 50.0), width, (12.0, 12.0, 12.0, 14.0))
    for e1, e2, p in steps:
        assert abs(dist(e1, e2) - width) < 1e-9, "every step the same width"
        assert dist(mid2(e1, e2), p) < 1e-9, "centred on the line's midpoint"
        assert abs(dot(unit(vec(e1, e2)), direction)) < 1e-12, "parallel"
    # depths are per-step, not a running total
    previous = [sp] + [s[2] for s in steps[:-1]]
    spacings = [abs(dot(vec(a, s[2]), direction))
                for a, s in zip(previous, steps)]
    assert [round(s, 9) for s in spacings] == [12.0, 12.0, 12.0, 14.0]


def test_normie_corner_mode_butts_the_side_line():
    """On a skewed corner each tread still starts on the side line."""
    for deg in (70.0, 90.0, 115.0):
        corner = (0.0, 0.0)
        base = (corner, (300.0, 0.0))
        rad = math.radians(deg)
        side = (corner, (300 * math.cos(rad), 300 * math.sin(rad)))
        width = 100.0
        u, direction, steps = normie_corner_mode(
            base, side, width, (12.0, 12.0, 12.0))
        cum = 0.0
        for inner, outer, _ in steps:
            cum += 12.0
            assert abs(dist(inner, outer) - width) < 1e-9, f"{deg}: width held"
            assert ptline(inner, *side) < 1e-9, "inner end lies on the side"
            assert abs(ptline(inner, *base) - cum) < 1e-9, \
                "depth measured square to the base line"
            assert abs(abs(dot(unit(vec(inner, outer)), u)) - 1.0) < 1e-12, \
                "tread runs parallel to the base line"
            # ...and the run is OUTSIDE the corner: the side line runs
            # one way from it, every tread the other
            assert dot(vec(corner, inner), vec(corner, side[1])) < 0.0, \
                f"{deg}: the run must sit outside the corner, not in it"


def test_normie_u_mode_trims_to_the_arms():
    arm1 = ((-100.0, 200.0), (-70.0, 0.0))
    arm2 = ((100.0, 200.0), (70.0, 0.0))
    base = ((-70.0, 0.0), (70.0, 0.0))
    u, direction, steps, stopped = normie_u_mode(arm1, arm2, base, [40.0] * 6)
    assert stopped, "must stop once a tread would fall past the open end"
    assert len(steps) == 5
    widths = []
    for e1, e2, _ in steps:
        assert ptline(e1, *arm1) < 1e-9, "left end lies on the left arm"
        assert ptline(e2, *arm2) < 1e-9, "right end lies on the right arm"
        assert abs(abs(dot(unit(vec(e1, e2)), u)) - 1.0) < 1e-12
        widths.append(dist(e1, e2))
    # the run marches out from the base, so splaying arms widen the treads
    assert all(b > a for a, b in zip(widths, widths[1:])), widths


def test_normie_u_mode_starts_on_the_base_not_the_mouth():
    """The base of the U is the wall - step 1 sits one depth off it.

    Regression: the run used to start at the open end of the U and march
    back toward the base, which put the first tread at the wrong end.
    """
    arm1 = ((-80.0, 150.0), (-80.0, 0.0))
    arm2 = ((80.0, 260.0), (80.0, 0.0))          # arms of unequal length
    base = ((-80.0, 0.0), (80.0, 0.0))
    _, direction, steps, _ = normie_u_mode(arm1, arm2, base, (12.0, 12.0, 14.0))
    assert direction == (0.0, 1.0), "the run heads from the base outward"
    base_mid = mid2(*base)
    offsets = [dot(vec(base_mid, p), direction) for _, _, p in steps]
    assert [round(o, 9) for o in offsets] == [12.0, 24.0, 38.0], offsets


def test_normie_u_back_corner_is_cut_into_the_corner():
    """A diagonal back corner sits inboard of the square corner it replaces."""
    arm = ((-80.0, 150.0), (-80.0, 0.0))
    base = ((-80.0, 0.0), (80.0, 0.0))
    off = 9.0
    on_base, on_arm = u_back_corner(base, arm, "Cut", off)
    assert on_base == (-80.0 + off, 0.0), on_base       # in along the base
    assert on_arm == (-80.0, off), on_arm               # out along the arm
    assert abs(dist(on_base, on_arm) - off * ROOT2) < 1e-9, "45 degree cut"
    # a tread at depth d < off trims to the diagonal, (off - d) inboard
    for depth in (0.0, 3.0, 6.0, 9.0):
        hit = inters((0.0, depth), (1.0, depth), on_base, on_arm)
        assert abs(hit[0] - (-80.0 + off - depth)) < 1e-9, hit


def test_normie_u_back_corner_fillet_is_tangent_to_both_legs():
    arm = ((80.0, 150.0), (80.0, 0.0))
    base = ((-80.0, 0.0), (80.0, 0.0))
    rad = 12.0
    on_base, on_arm, centre = u_back_corner(base, arm, "Radius", rad)
    assert abs(dist(centre, on_base) - rad) < 1e-9
    assert abs(dist(centre, on_arm) - rad) < 1e-9
    assert abs(centre[1] - rad) < 1e-9, "one radius off the base"
    assert abs(abs(centre[0] - 80.0) - rad) < 1e-9, "one radius off the arm"
    # the arc stays inboard of the square corner at every depth it covers
    for depth in (0.0, 4.0, 8.0, 12.0):
        half = math.sqrt(max(rad * rad - (depth - rad) ** 2, 0.0))
        x = centre[0] + half
        assert x <= 80.0 + 1e-9 and x >= centre[0] - 1e-9, x


def test_normie_u_mode_handles_parallel_arms():
    """Parallel arms give the constant width the routine is named for."""
    arm1 = ((-80.0, 150.0), (-80.0, 0.0))
    arm2 = ((80.0, 150.0), (80.0, 0.0))
    base = ((-80.0, 0.0), (80.0, 0.0))
    _, _, steps, _ = normie_u_mode(arm1, arm2, base, (30.0, 30.0, 30.0))
    widths = [dist(e1, e2) for e1, e2, _ in steps]
    assert all(abs(w - 160.0) < 1e-9 for w in widths), widths


ROOT2 = math.sqrt(2.0)


def recess_corner(e, wdir, direction, kind, size):
    """ns-side: the two points a back corner runs between.

    E is where the side of the run meets the wall, WDIR is the way the
    wall carries on, DIRECTION is the way the run heads.  Returns
    (on_wall, on_side) - a diagonal joins them, a fillet arc is tangent at
    them, and a square (90 degree) corner has both at E.
    """
    off = size if kind in ("Cut", "Radius") else 0.0
    return add(e, scl(wdir, off)), add(e, scl(direction, off))


def test_recess_offset_and_cut_convert_both_ways():
    """A 45 degree cut and its offset each determine the other."""
    for offset in (3.0, 6.0, 12.0):
        cut = offset * ROOT2
        assert abs(cut / ROOT2 - offset) < 1e-12
    for cut in (8.485281374238571, 17.0):
        offset = cut / ROOT2
        assert abs(offset * ROOT2 - cut) < 1e-9


def test_recess_diagonal_is_45_degrees_to_both_lines():
    e, wdir, direction = (50.0, 0.0), (1.0, 0.0), (0.0, 1.0)
    for offset in (6.0, 12.0):
        on_wall, on_side = recess_corner(e, wdir, direction, "Cut", offset)
        cut = unit(vec(on_wall, on_side))
        assert abs(dist(on_wall, on_side) - offset * ROOT2) < 1e-12
        # equal angle to the wall and to the side of the recess
        to_wall = math.degrees(math.acos(abs(dot(cut, wdir))))
        to_side = math.degrees(math.acos(abs(dot(cut, direction))))
        assert abs(to_wall - 45.0) < 1e-9 and abs(to_side - 45.0) < 1e-9


def test_recess_rounded_corner_is_tangent_to_both_lines():
    e, wdir, direction = (50.0, 0.0), (1.0, 0.0), (0.0, 1.0)
    wall = (e, add(e, wdir))
    side = (e, add(e, direction))
    for radius in (4.0, 9.0):
        t1, t2 = recess_corner(e, wdir, direction, "Radius", radius)
        centre = add(t1, scl(direction, radius))     # ns-side's centre
        assert abs(ptline(centre, *wall) - radius) < 1e-12, "tangent to wall"
        assert abs(ptline(centre, *side) - radius) < 1e-12, "tangent to side"
        assert abs(dist(centre, t1) - radius) < 1e-12
        assert abs(dist(centre, t2) - radius) < 1e-12


def test_recess_flares_the_mouth_by_the_offset():
    """Corner mode: the outer side's back corner flares the recess mouth.

    ns-side still serves CORNER mode, where the treatment stays at the
    wall the run comes off: the outer side line starts one offset OFF
    the wall and the flare piece bridges back to it, opening the mouth
    of the recess wider than the run.  (A centered one-line run no
    longer flares - its treatment sits on the last step's corners; see
    the outer_corner tests.)
    """
    width, offset = 120.0, 9.0
    corner, u, direction = (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
    e = add(corner, scl(u, width))       # the outer side meets the wall here
    on_wall, on_side = recess_corner(e, u, direction, "Cut", offset)
    assert abs(dot(vec(corner, on_wall), u) - (width + offset)) < 1e-12, \
        "mouth flares by the offset"
    assert abs(dot(vec(corner, on_side), u) - width) < 1e-12, \
        "closes back to the run width"
    # the outer side line starts one offset off the wall
    assert abs(dot(vec(corner, on_side), direction) - offset) < 1e-12


def test_recess_square_corner_leaves_the_side_at_the_wall():
    e, wdir, direction = (60.0, 0.0), (1.0, 0.0), (0.0, 1.0)
    for kind in ("Square", "NotGiven", None):
        on_wall, on_side = recess_corner(e, wdir, direction, kind, 9.0)
        assert on_wall == e and on_side == e, "no flare without a treatment"


def outer_corner(e, uin, direction, cum, off):
    """ns-outer: the last-step corner of a centered (one-line) run.

    E is where the side wall leaves the base wall, UIN the unit vector
    along the last tread toward the run's centre, DIRECTION the way the
    run heads, CUM the whole run.  With C the theoretical square corner
    at E + DIRECTION x CUM, returns (t1, t2): T1 one offset back along
    the side wall, T2 one offset in along the last tread - a diagonal
    joins them, a fillet arc of radius OFF is tangent at them.
    """
    c = add(e, scl(direction, cum))
    t1 = add(c, scl(direction, -off))
    t2 = add(c, scl(uin, off))
    return t1, t2


def outer_fillet_centre(t1, uin, off):
    """ns-outer's fillet centre: one offset in from T1 along the tread."""
    return add(t1, scl(uin, off))


def outer_offset(kind, size, cum, wid):
    """The resolved last-step corner offset of a centered run.

    Mirrors c:NORMIESTEP's LINE-mode resolution and its guards: Rounded
    and Diagonal give their size, anything else 0; an offset at least
    as deep as the whole run, or a pair that would meet across the last
    tread, falls back to square (0).
    """
    off = size if kind in ("Cut", "Radius") else 0.0
    if off <= 0.0:
        return 0.0
    if off >= cum:
        return 0.0
    if 2 * off >= wid:
        return 0.0
    return off


def test_outer_diagonal_is_45_degrees_to_wall_and_tread():
    """The last-step cut meets the side wall and the tread at 45."""
    e, uin, direction = (60.0, 0.0), (-1.0, 0.0), (0.0, 1.0)
    for off in (6.0, 9.0):
        t1, t2 = outer_corner(e, uin, direction, 36.0, off)
        cut = unit(vec(t1, t2))
        assert abs(dist(t1, t2) - off * ROOT2) < 1e-9, "cut = off x root 2"
        to_wall = math.degrees(math.acos(abs(dot(cut, direction))))
        to_tread = math.degrees(math.acos(abs(dot(cut, uin))))
        assert abs(to_wall - 45.0) < 1e-9 and abs(to_tread - 45.0) < 1e-9


def test_outer_fillet_centre_is_off_both_lines():
    """The fillet centre sits one offset off the side wall and the
    tread, one radius from each tangent point."""
    e, uin, direction = (60.0, 0.0), (-1.0, 0.0), (0.0, 1.0)
    cum, off = 36.0, 9.0
    t1, t2 = outer_corner(e, uin, direction, cum, off)
    centre = outer_fillet_centre(t1, uin, off)
    side_wall = (e, add(e, direction))
    c = add(e, scl(direction, cum))
    tread = (c, add(c, uin))
    assert abs(ptline(centre, *side_wall) - off) < 1e-9, "off the side wall"
    assert abs(ptline(centre, *tread) - off) < 1e-9, "off the tread"
    assert abs(dist(centre, t1) - off) < 1e-9
    assert abs(dist(centre, t2) - off) < 1e-9


def test_outer_side_wall_runs_from_the_wall_to_cum_minus_off():
    """The side wall starts ON the base wall and stops one offset short
    of the last tread."""
    sp, u, direction = (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
    wid, cum, off = 120.0, 36.0, 9.0
    for sign in (1.0, -1.0):
        e = add(sp, scl(u, sign * wid / 2))
        start, end = e, add(e, scl(direction, cum - off))
        assert abs(dot(vec(sp, start), direction)) < 1e-9, "starts on the wall"
        assert abs(dot(vec(sp, end), direction) - (cum - off)) < 1e-9


def test_outer_trimmed_tread_is_short_by_two_offsets_and_centred():
    sp, u, direction = (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
    wid, cum, off = 120.0, 36.0, 9.0
    p = add(sp, scl(direction, cum))          # the last tread's axis point
    te1 = add(p, scl(u, wid / 2 - off))       # trimmed in by OFF each end
    te2 = add(p, scl(u, off - wid / 2))
    assert abs(dist(te1, te2) - (wid - 2 * off)) < 1e-9
    assert dist(mid2(te1, te2), p) < 1e-9, "still centred on the axis"


def test_outer_square_side_wall_ends_on_the_tread_endpoint():
    """Square (or a resolved offset of 0): the side wall's far end IS
    the last tread's endpoint - no corner piece, no trim."""
    sp, u, direction = (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
    wid, cum = 120.0, 36.0
    off = outer_offset("Square", 9.0, cum, wid)
    assert off == 0.0
    for sign in (1.0, -1.0):
        e = add(sp, scl(u, sign * wid / 2))
        wall_end = add(e, scl(direction, cum - off))
        tread_end = add(add(sp, scl(direction, cum)),
                        scl(u, sign * (wid / 2 - off)))
        assert dist(wall_end, tread_end) < 1e-9


def test_outer_half_outline_connects_end_to_end():
    """Wall point -> side wall -> corner piece -> trimmed tread end,
    every junction coincident, on both sides of the run."""
    sp, u, direction = (0.0, 0.0), (1.0, 0.0), (0.0, 1.0)
    wid, cum, off = 120.0, 36.0, 9.0
    for sign in (1.0, -1.0):
        uin = scl(u, -sign)
        e = add(sp, scl(u, sign * wid / 2))          # on the base wall
        assert abs(dot(vec(sp, e), direction)) < 1e-9, "wall point"
        wall_end = add(e, scl(direction, cum - off)) # side wall stops here
        t1, t2 = outer_corner(e, uin, direction, cum, off)
        tread_end = add(add(sp, scl(direction, cum)),
                        scl(u, sign * (wid / 2 - off)))
        assert dist(wall_end, t1) < 1e-9, "side wall meets the corner piece"
        assert dist(t2, tread_end) < 1e-9, "corner piece meets the tread"


def test_outer_guards_fall_back_to_square():
    """A corner deeper than the run, or two that would meet across the
    last tread, resolves to a square (offset 0) last step."""
    assert outer_offset("Cut", 36.0, 36.0, 120.0) == 0.0  # off >= cum
    assert outer_offset("Cut", 40.0, 36.0, 120.0) == 0.0
    assert outer_offset("Radius", 60.0, 200.0, 120.0) == 0.0  # 2*off >= wid
    assert outer_offset("Radius", 61.0, 200.0, 120.0) == 0.0
    assert outer_offset("Square", 9.0, 36.0, 120.0) == 0.0     # no treatment
    assert outer_offset("Cut", 9.0, 36.0, 120.0) == 9.0   # fits
    assert outer_offset("Radius", 12.0, 36.0, 120.0) == 12.0


# ------------------------------------------------- AUTOBEAD hand-off
# The step routines hand their geometry to AUTOBEAD rather than making
# the user re-select it: every tread is beaded, and the steps whose side
# walls carry the bead are named by number instead of clicked.  These
# mirror the ...-numlist / ...-treadents / ...-sideents helpers.


def numlist(text):
    """ns-numlist: the step numbers in a typed answer, in order.

    Runs of digits are numbers; everything else separates, so "1 3 4",
    "1,3,4" and "1, 3 and 4" all read the same.
    """
    out, tok = [], ""
    for ch in text + " ":
        if ch.isdigit():
            tok += ch
        else:
            if tok:
                out.append(int(tok))
            tok = ""
    return out


def treadents(log):
    """ns-treadents: (step number, tread) per committed step.

    A log record is (entities, ..., n) with the entities newest first,
    and a step draws its tread BEFORE any side line or dimension - so
    the last LINE seen walking the record is the tread.  Consing through
    a newest-first log leaves the pairs in step order.
    """
    out = []
    for rec in log:
        tread = None
        for kind, ent in rec[0]:
            if kind == "LINE":
                tread = ent
        if tread is not None:
            out.insert(0, (rec[-1], tread))   # cons, like the lisp does
    return out


def sideents(log):
    """cs-sideents: every LINE in the log that is not its step's tread."""
    out = []
    for rec in log:
        lines = [e for kind, e in rec[0] if kind == "LINE"]
        tread = lines[-1] if lines else None
        for e in reversed(lines):
            if e != tread:
                out.append(e)
    return out


def test_numlist_reads_every_separator_the_same():
    assert numlist("1 3 4") == [1, 3, 4]
    assert numlist("1,3,4") == [1, 3, 4]
    assert numlist("1, 3 and 4") == [1, 3, 4]
    assert numlist("  2  ") == [2]
    assert numlist("10 2") == [10, 2], "multi-digit numbers stay whole"
    assert numlist("") == [] and numlist("none") == [], "nothing to read"


def test_treadents_picks_the_tread_not_a_riser_or_a_dim():
    """CORNERSTP draws tread, then risers, then dims - and the log lists
    them newest first, so the tread is the LAST line in the record."""
    step1 = ([("DIMENSION", "d1"), ("LINE", "r1b"), ("LINE", "r1a"),
              ("LINE", "tread1")], 0.0, None, None, None, None, 1)
    step2 = ([("LINE", "tread2")], 0.0, None, None, None, None, 2)
    log = [step2, step1]                      # newest first
    assert treadents(log) == [(1, "tread1"), (2, "tread2")]


def test_treadents_comes_back_in_step_order():
    log = [([("LINE", "t3")], 3), ([("LINE", "t2")], 2), ([("LINE", "t1")], 1)]
    assert [n for n, _ in treadents(log)] == [1, 2, 3]


def test_treadents_skips_a_record_that_drew_no_line():
    log = [([("LINE", "t2")], 2), ([("DIMENSION", "d")], 1)]
    assert treadents(log) == [(2, "t2")]


def test_sideents_returns_the_risers_only():
    step1 = ([("DIMENSION", "d1"), ("LINE", "r1b"), ("LINE", "r1a"),
              ("LINE", "tread1")], 1)
    step2 = ([("LINE", "tread2")], 2)
    assert sorted(sideents([step2, step1])) == ["r1a", "r1b"]


def test_named_steps_map_to_their_own_treads():
    """The numbers typed at the prompt pick out those steps' treads -
    what the routine hands AUTOBEAD as its clicked steps."""
    log = [([("LINE", "t%d" % k)], k) for k in (4, 3, 2, 1)]
    pairs = dict(treadents(log))
    named = [k for k in numlist("1, 3") if k in pairs]
    assert named == [1, 3]
    assert [pairs[k] for k in named] == ["t1", "t3"]
    unknown = [k for k in numlist("9") if k in pairs]
    assert unknown == [], "an unknown number is dropped, not beaded"


def linecirc_hits(a, d, c, r):
    """ns-linecirc: crossings of line (a, unit d) with circle (c, r)."""
    f = vec(c, a)
    g = dot(d, f)
    disc = r * r + g * g - dot(f, f)
    if disc < 0:
        return []
    disc = math.sqrt(disc)
    return [add(a, scl(d, -g - disc)), add(a, scl(d, -g + disc))]


def side_hit(p, u, side, fuzz):
    """ns-sidehit: nearest on-piece hit of the tread line on one side.

    A side is a list of pieces: ("S", p1, p2) or ("A", p1, p2, c, r, a1, a2).
    """
    best, bd = None, None
    for pc in side:
        if pc[0] == "S":
            q = inters(p, add(p, u), pc[1], pc[2])
            if q and beyond(q, pc[1], pc[2]) < fuzz and \
                    (best is None or dist(p, q) < bd):
                best, bd = q, dist(p, q)
        else:
            _, _, _, c, r, a1, a2 = pc
            for q in linecirc_hits(p, u, c, r):
                ang = math.atan2(q[1] - c[1], q[0] - c[0]) % (2 * math.pi)
                if inspan(ang, a1, a2) and (best is None or dist(p, q) < bd):
                    best, bd = q, dist(p, q)
    return best


def chain_pieces(pieces, fuzz):
    """The NORMIESTEP U chain walk: order pieces end to end.

    Returns (chain, free_end_1, free_end_2); raises if the parts do not
    form one open chain.
    """
    freep = []
    for pc in pieces:
        for e in (pc[1], pc[2]):
            hits = 0
            for qc in pieces:
                if qc is not pc:
                    if dist(e, qc[1]) < fuzz:
                        hits += 1
                    if dist(e, qc[2]) < fuzz:
                        hits += 1
            if hits == 0:
                freep.append((pc, e))
    assert len(freep) == 2, f"{len(freep)} free ends"
    arm1, f1 = freep[0]
    chain = [arm1]
    cure = arm1[2] if dist(f1, arm1[1]) < fuzz else arm1[1]
    rest = [pc for pc in pieces if pc is not arm1]
    while True:
        nxt = [pc for pc in rest
               if dist(cure, pc[1]) < fuzz or dist(cure, pc[2]) < fuzz]
        if not nxt:
            break
        nxt = nxt[0]
        chain.append(nxt)
        cure = nxt[2] if dist(cure, nxt[1]) < fuzz else nxt[1]
        rest.remove(nxt)
    assert not rest, "pieces do not all connect"
    return chain, f1, cure


def chamfered_u(offset=12.0, half=80.0, height=150.0):
    arm_l = ("S", (-half, height), (-half, offset))
    arm_r = ("S", (half, height), (half, offset))
    dg_l = ("S", (-half, offset), (-half + offset, 0.0))
    dg_r = ("S", (half, offset), (half - offset, 0.0))
    base = ("S", (-half + offset, 0.0), (half - offset, 0.0))
    return [dg_r, arm_l, base, arm_r, dg_l], base   # scrambled on purpose


def filleted_u(radius=12.0, half=80.0, height=150.0):
    arm_l = ("S", (-half, height), (-half, radius))
    arm_r = ("S", (half, height), (half, radius))
    c_l = (-half + radius, radius)
    c_r = (half - radius, radius)
    f_l = ("A", (-half, radius), (-half + radius, 0.0), c_l, radius,
           math.pi, 1.5 * math.pi)
    f_r = ("A", (half - radius, 0.0), (half, radius), c_r, radius,
           1.5 * math.pi, 2 * math.pi)
    base = ("S", (-half + radius, 0.0), (half - radius, 0.0))
    return [f_r, arm_l, base, arm_r, f_l], base     # scrambled on purpose


def test_u_chain_finds_the_base_whatever_the_selection_order():
    """The middle of the walked chain is the base, for 3 and 5 pieces."""
    fuzz = 0.5
    arm_l = ("S", (-80.0, 150.0), (-80.0, 0.0))
    arm_r = ("S", (80.0, 150.0), (80.0, 0.0))
    base = ("S", (-80.0, 0.0), (80.0, 0.0))
    chain, f1, f2 = chain_pieces([base, arm_l, arm_r], fuzz)
    assert chain[len(chain) // 2] is base
    assert sorted([f1, f2]) == [(-80.0, 150.0), (80.0, 150.0)]
    for build in (chamfered_u, filleted_u):
        pieces, want_base = build()
        chain, _, _ = chain_pieces(pieces, fuzz)
        assert len(chain) == 5
        assert chain[2] is want_base, "middle of the 5-chain is the base"


def test_u_treads_trim_to_diagonal_corners():
    """Below the chamfer start the treads narrow linearly with depth."""
    offset, half = 12.0, 80.0
    pieces, _ = chamfered_u(offset, half)
    chain, _, _ = chain_pieces(pieces, 0.5)
    side1, side2 = chain[:2], chain[3:]
    for y in (140.0, 20.0, 12.0, 10.0, 6.0, 2.0):
        e1 = side_hit((0.0, y), (1.0, 0.0), side1, 0.5)
        e2 = side_hit((0.0, y), (1.0, 0.0), side2, 0.5)
        want = 2 * half if y >= offset else 2 * (half - (offset - y))
        assert abs(dist(e1, e2) - want) < 1e-9, f"y={y}"


def test_u_treads_trim_to_rounded_corners():
    """Inside the fillet the treads follow the arc, not the arm."""
    radius, half = 12.0, 80.0
    pieces, _ = filleted_u(radius, half)
    chain, _, _ = chain_pieces(pieces, 0.5)
    side1, side2 = chain[:2], chain[3:]
    for y in (140.0, 20.0, 12.0, 10.0, 6.0, 2.0):
        e1 = side_hit((0.0, y), (1.0, 0.0), side1, 0.5)
        e2 = side_hit((0.0, y), (1.0, 0.0), side2, 0.5)
        if y >= radius:
            want = 2 * half
        else:
            dx = math.sqrt(radius ** 2 - (y - radius) ** 2)
            want = 2 * (half - radius + dx)
        assert abs(dist(e1, e2) - want) < 1e-9, f"y={y}"
        if y < radius:                        # the hit really sits on the arc
            c_l = (-half + radius, radius)
            assert abs(dist(e1, c_l) - radius) < 1e-9


def test_normie_u_base_detection():
    """The base of a U is the one segment joined to both of the others."""
    arm1 = ((-100.0, 200.0), (-70.0, 0.0))
    arm2 = ((100.0, 200.0), (70.0, 0.0))
    base = ((-70.0, 0.0), (70.0, 0.0))
    fuzz = 0.5

    def joined(a, b):
        return min(dist(a[0], b[0]), dist(a[0], b[1]),
                   dist(a[1], b[0]), dist(a[1], b[1])) < fuzz

    segs = [arm1, arm2, base]
    found = [s for s in segs
             if all(joined(s, o) for o in segs if o is not s)]
    assert found == [base], "only the base joins both arms"


# ------------------------------------------------------------- the release
# The three routines ship as ONE file, releases/STEPS_MMDDYY_REV##-##-##.lsp,
# not one release each.  Fix any failure here by running:
#     python3 tools/release_lisp.py


def newest_bundle():
    """The most recent STEPS_MMDDYY_REV##-##-##.lsp in releases/."""
    best, best_key = None, None
    for name in os.listdir(RELEASES_DIR):
        m = re.fullmatch(r"STEPS_(\d{2})(\d{2})(\d{2})_REV([\d-]+)\.lsp",
                         name, re.IGNORECASE)
        if not m:
            continue
        mm, dd, yy = (int(g) for g in m.groups()[:3])
        if best_key is None or (yy, mm, dd) > best_key:
            best, best_key = (name, m.group(4)), (yy, mm, dd)
    assert best, "no STEPS release found - run tools/release_lisp.py"
    return best


def test_the_steps_release_as_a_single_bundle():
    """One STEPS file holds all three routines, and no member has a
    dated release of its own."""
    name, _ = newest_bundle()
    with open(os.path.join(RELEASES_DIR, name)) as f:
        bundle = f.read()
    for member in BUNDLE_MEMBERS:
        with open(os.path.join(LISP_DIR, member)) as f:
            assert f.read() in bundle, \
                "%s is not in %s verbatim - run tools/release_lisp.py" \
                % (member, name)
        stray = glob.glob(os.path.join(
            RELEASES_DIR, "%s_[0-9]*_REV*.lsp" % os.path.splitext(member)[0]))
        assert not stray, \
            "%s still has its own release %s - the steps release as one " \
            "file; run tools/release_lisp.py" \
            % (member, [os.path.basename(s) for s in stray])
    for command in ("CORNERSTP", "HEMISTEP", "NORMIESTEP",
                    "TUTORIALCORNERSTP", "TUTORIALHEMISTEP",
                    "TUTORIALNORMIESTEP"):
        assert re.search(r"^\(defun\s+c:%s\b" % command, bundle, re.M), \
            "%s is missing from %s" % (command, name)
    print("release current: one bundle, %s" % name)


def test_bundle_revs_match_the_source_banners():
    """The REVs in the filename are the members' own version banners,
    in the order the bundle concatenates them."""
    name, revs = newest_bundle()
    got = revs.split("-")
    assert len(got) == len(BUNDLE_MEMBERS), \
        "%s names %d REVs for %d routines" % (name, len(got),
                                              len(BUNDLE_MEMBERS))
    for member, rev in zip(BUNDLE_MEMBERS, got):
        with open(os.path.join(LISP_DIR, member)) as f:
            m = re.search(r'\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"', f.read())
        assert m, "%s has no version banner" % member
        assert m.group(1) + m.group(2) == rev, \
            "%s is v%s.%s but %s says REV%s - run tools/release_lisp.py" \
            % (member, m.group(1), m.group(2), name, rev)
    print("release revs match: %s" % name)


def main():
    test_inside_out_holds_tread_depths()
    test_held_width_is_centred_between_the_walls()
    test_width_within_tolerance_snaps_to_the_walls()
    test_outside_in_first_step_lands_wall_to_wall()
    test_outside_in_walks_in_by_exact_depths()
    test_equidistant_mode_is_symmetric_about_the_corner()
    test_beyond_flags_walls_that_had_to_be_extended()
    test_inspan_handles_wraparound()
    test_bulgearc_round_trips()
    test_bulgearc_quarter_circle_centre()
    test_autotol_tracks_insunits()
    test_dimension_chain_and_nesting()
    test_hemistep_chords_are_parallel_and_centred()
    test_hemistep_arc_mode_breaks_curve_equally()
    test_opening_matches_the_true_chord()
    test_opening_uses_the_nearest_crossing_not_the_extremes()
    test_composite_curve_matches_a_single_arc()
    test_full_circle_piece_spans_everywhere()
    test_opening_is_none_outside_the_curve()
    test_boundary_polyline_bulges_are_real_arcs()
    test_crown_anchored_fit_reproduces_the_original_curve()
    test_crown_anchored_fit_keeps_the_apex_on_one_arc()
    test_curve_mode_boundary_spans_the_first_step_on_the_original_arc()
    test_curve_mode_boundary_does_not_spike_at_the_crown()
    test_first_span_picks_the_crown_side_either_way_round()
    test_first_span_rejects_a_fold()
    test_safeb_clamps_folding_segments()
    test_no_boundary_segment_folds_back()
    test_line_mode_boundary_is_anchored_at_the_wall()
    test_depths_are_measured_from_the_previous_step()
    test_boundary_polyline_pairs_share_a_circle()
    test_normie_line_mode_is_centred_and_constant()
    test_normie_corner_mode_butts_the_side_line()
    test_normie_u_mode_trims_to_the_arms()
    test_normie_u_mode_handles_parallel_arms()
    test_normie_u_base_detection()
    test_u_chain_finds_the_base_whatever_the_selection_order()
    test_u_treads_trim_to_diagonal_corners()
    test_u_treads_trim_to_rounded_corners()
    test_recess_offset_and_cut_convert_both_ways()
    test_recess_diagonal_is_45_degrees_to_both_lines()
    test_recess_rounded_corner_is_tangent_to_both_lines()
    test_recess_flares_the_mouth_by_the_offset()
    test_recess_square_corner_leaves_the_side_at_the_wall()
    test_outer_diagonal_is_45_degrees_to_wall_and_tread()
    test_outer_fillet_centre_is_off_both_lines()
    test_outer_side_wall_runs_from_the_wall_to_cum_minus_off()
    test_outer_trimmed_tread_is_short_by_two_offsets_and_centred()
    test_outer_square_side_wall_ends_on_the_tread_endpoint()
    test_outer_half_outline_connects_end_to_end()
    test_outer_guards_fall_back_to_square()
    test_numlist_reads_every_separator_the_same()
    test_treadents_picks_the_tread_not_a_riser_or_a_dim()
    test_treadents_comes_back_in_step_order()
    test_treadents_skips_a_record_that_drew_no_line()
    test_sideents_returns_the_risers_only()
    test_named_steps_map_to_their_own_treads()
    test_the_steps_release_as_a_single_bundle()
    test_bundle_revs_match_the_source_banners()
    print("all tests passed")


if __name__ == "__main__":
    main()
