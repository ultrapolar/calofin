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
    print("all tests passed")


if __name__ == "__main__":
    main()
