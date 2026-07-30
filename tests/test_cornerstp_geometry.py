# SPDX-License-Identifier: GPL-3.0-or-later
"""Geometry regression tests for CORNERSTP.lsp and HEMISTEP.lsp.

The AutoLISP routines cannot run outside AutoCAD, so this module mirrors
their geometry helpers in Python and asserts the invariants the drawings
depend on: tread depths held exactly, held widths centred on the wall
opening, outermost steps landing wall-to-wall, and bulge/arc conversions
round-tripping.  Keeping the maths here means a change to either .lsp can
be re-verified without opening AutoCAD.

Usage:  python3 tests/test_cornerstp_geometry.py
"""

import math

TOL_INCH = 0.125  # *cs-width-tol* default, 1/8"


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


def blgs(pts):
    """hs-blgs: one bulge per segment, fitted through consecutive triples."""

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

    m, i, out = len(pts) - 1, 0, []
    while i < m:
        if i + 2 <= m:
            p, q, s = pts[i], pts[i + 1], pts[i + 2]
            o = circum(p, q, s)
            if o:
                ccw = cross(vec(p, q), vec(p, s)) > 0
                out += [segb(p, q, o, ccw), segb(q, s, o, ccw)]
            else:
                out += [0.0, 0.0]
            i += 2
        elif i > 0:
            p, q, s = pts[i - 1], pts[i], pts[i + 1]
            o = circum(p, q, s)
            if o:
                ccw = cross(vec(p, q), vec(p, s)) > 0
                out.append(segb(q, s, o, ccw))
            else:
                out.append(0.0)
            i += 1
        else:
            out.append(0.0)
            i += 1
    return out


def arc_from_bulge(a, b, bulge):
    """Reconstruct (centre, radius) from a chord and its polyline bulge."""
    chord = dist(a, b)
    th = 4 * math.atan(abs(bulge))
    r = chord / (2 * math.sin(th / 2))
    mx, my = mid2(a, b)
    h = math.sqrt(max(0.0, r * r - (chord / 2) ** 2))
    ux, uy = unit(vec(a, b))
    nx, ny = (-uy, ux)
    sign = -1 if bulge > 0 else 1
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


def test_boundary_polyline_pairs_share_a_circle():
    """Segments fitted from one triple lie on the same arc, as 3-point arcs do."""
    pts = [(0.0, 0.0), (10.0, 6.0), (24.0, 8.0), (40.0, 6.0), (50.0, 0.0)]
    bulges = blgs(pts)
    first = arc_from_bulge(pts[0], pts[1], bulges[0])[1]
    second = arc_from_bulge(pts[1], pts[2], bulges[1])[1]
    assert abs(first - second) < 1e-6, "a triple's two segments share a radius"


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
    test_boundary_polyline_pairs_share_a_circle()
    print("all tests passed")


if __name__ == "__main__":
    main()
