# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the LHD laser-point outline fitter (lisp/lhd/lhd.lsp).

lhd.lsp is AutoLISP and only runs inside AutoCAD, so the functions
below are a faithful Python mirror of its geometry and fitting logic:
same algorithm, same constants, same control flow, same function names
(``lh:span-path`` -> ``span_path``).  Editing the fitter means editing
both, and ``test_constants_match_lisp`` fails loudly when the tuning
values drift apart.

LHD's CLOSED mode is ABHD's loop engine copied verbatim under the lh:
prefix, and that algorithm is already exercised end to end by
tests/test_pool_fit.py; what this file adds is the OPEN-path machinery
that is new in LHD - the fixed-end ordering, the linear-index span
walker, the open polyline vertex list, the open self-cross test and
the output-height pick - plus the structural checks on the .lsp file
itself.

Usage:  python3 tests/test_laser_fit.py
"""

import math
import os
import re

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
LISP_FILE = os.path.join(REPO_DIR, "lisp", "lhd", "lhd.lsp")
RELEASES_DIR = os.path.join(REPO_DIR, "releases")

# ---- tuning constants, mirrored from lhd.lsp -------------------------

ON_EPS = 0.25                      # *LH-ON-EPS*
MISS_PCT = 0.15                    # *LH-MISS-PCT*
TOL_MAX = 2.0                      # *LH-TOL-MAX*
SNAP_EPS = 0.02                    # *LH-SNAP-EPS*
FIT_EPS = 0.01                     # *LH-FIT-EPS*
CORNER_ANG = math.pi / 4.0         # *LH-CORNER-ANG*
TANG_TOL = math.pi / 22.5          # *LH-TANG-TOL*
NICE_RADII = (12.0, 6.0, 1.0)      # *LH-NICE-RADII*
TANG_STEPS = (1.0, 1.25, 1.5)      # *LH-TANG-STEPS*
ARC_SLACK = math.pi / 3.0          # *LH-ARC-SLACK*
DROP_PCT = 0.10                    # *LH-DROP-PCT*
DROP_MULT = 2.0                    # *LH-DROP-MULT*
ANG_CAP = 1.373                    # window-edge clamp, atan(5)
TIGHT_TOL = 0.01                   # *LH-TIGHT-TOL*
TEXT_EPS = 6.0                     # *LH-TEXT-EPS*
ANG_CAP = 1.373                    # window-edge clamp, atan-space
COMPARE_MODES = ("tight", "asked", "few")   # *LH-COMPARE*

# ---- small 2D helpers ------------------------------------------------


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def ang(a, b):
    return math.atan2(b[1] - a[1], b[0] - a[0])


def norm_ang(a):
    return a % (2.0 * math.pi)


def signed_dang(frm, to):
    d = norm_ang(to - frm)
    return d - 2.0 * math.pi if d > math.pi else d


def lh_ceil(x):
    f = int(x)
    return f + 1 if x > f else f


def lh_tan(x):
    """Mirror of lh:tan - clamped so it can never divide by zero."""
    x = max(-1.5697, min(1.5697, x))
    return math.tan(x)


# ---- circle / arc geometry -------------------------------------------


def circumcenter(pa, pb, pc):
    x1, y1 = pa
    x2, y2 = pb
    x3, y3 = pc
    d = 2.0 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
    if abs(d) < 1.0e-10:
        return None
    s1 = x1 * x1 + y1 * y1
    s2 = x2 * x2 + y2 * y2
    s3 = x3 * x3 + y3 * y3
    return ((s1 * (y2 - y3) + s2 * (y3 - y1) + s3 * (y1 - y2)) / d,
            (s1 * (x3 - x2) + s2 * (x1 - x3) + s3 * (x2 - x1)) / d)


def bulge_3pt(p1, q, p2):
    """Bulge of the arc P1 -> Q -> P2; 0.0 when degenerate."""
    c = circumcenter(p1, q, p2)
    if c is None:
        return 0.0
    a1, a2, aq = ang(c, p1), ang(c, p2), ang(c, q)
    dccw = norm_ang(a2 - a1)
    dq = norm_ang(aq - a1)
    if dccw < 1.0e-9 or dccw > 2.0 * math.pi - 1.0e-9:
        return 0.0
    if dq <= dccw:
        return lh_tan(dccw / 4.0)
    return -lh_tan((2.0 * math.pi - dccw) / 4.0)


def arc_geom(p1, p2, b):
    """(center, radius, angStart, angEnd) or None for a straight seg."""
    if abs(b) < 1.0e-9:
        return None
    ch = dist(p1, p2)
    if ch < 1.0e-12:
        return None
    ux, uy = (p2[0] - p1[0]) / ch, (p2[1] - p1[1]) / ch
    mid = ((p1[0] + p2[0]) / 2.0, (p1[1] + p2[1]) / 2.0)
    apex = (mid[0] + (-uy) * (-0.5 * ch * b),
            mid[1] + ux * (-0.5 * ch * b))
    c = circumcenter(p1, apex, p2)
    if c is None:
        return None
    return (c, dist(c, p1), ang(c, p1), ang(c, p2))


def seg_dist(p, seg):
    """Distance from P to the segment (p1, p2, bulge)."""
    p1, p2, b = seg
    if abs(b) < 1.0e-9:
        vx, vy = p2[0] - p1[0], p2[1] - p1[1]
        wx, wy = p[0] - p1[0], p[1] - p1[1]
        len2 = vx * vx + vy * vy
        if len2 < 1.0e-20:
            return dist(p, p1)
        t = max(0.0, min(1.0, (wx * vx + wy * vy) / len2))
        return dist(p, (p1[0] + vx * t, p1[1] + vy * t))
    g = arc_geom(p1, p2, b)
    if g is None:
        return min(dist(p, p1), dist(p, p2))
    c, r, a1, a2 = g
    ap = ang(c, p)
    if b > 0.0:
        sweep, rel = norm_ang(a2 - a1), norm_ang(ap - a1)
    else:
        sweep, rel = norm_ang(a1 - a2), norm_ang(ap - a2)
    if rel <= sweep:
        return abs(dist(p, c) - r)
    return min(dist(p, p1), dist(p, p2))


def tangent_bulge(a, tang, b):
    return lh_tan(signed_dang(tang, ang(a, b)) / 2.0)


def bulge_radius(a, b, bl):
    if abs(bl) < 1.0e-9:
        return None
    h = dist(a, b) / 2.0
    return h * (1.0 + bl * bl) / (2.0 * abs(bl))


def radius_bulge(a, b, r, bref):
    h = dist(a, b) / 2.0
    if r < h or h < 1.0e-9:
        return None
    s = math.sqrt(r * r - h * h)
    bl = (r + s) / h if abs(bref) > 1.0 else (r - s) / h
    return -bl if bref < 0.0 else bl


# ---- span helpers ----------------------------------------------------


def span_dev(a, b, bul, qs):
    return max((seg_dist(q, (a, b, bul)) for q in qs), default=0.0)


# The "on the shape" threshold in force for the current pass; mirrors
# the lh-on-eps free variable in lhd.lsp.
_ON_EPS = ON_EPS


def on_eps_for(tol):
    return max(ON_EPS, 0.25 * tol)


def span_misses(a, b, bul, qs):
    return sum(1 for q in qs if seg_dist(q, (a, b, bul)) > _ON_EPS)


def span_min(a, b, bul, qs):
    return min((seg_dist(q, (a, b, bul)) for q in qs), default=None)


def span_turn(a, b, qs):
    """Total turning of the polyline A -> QS... -> B, in radians."""
    chain = [a] + list(qs) + [b]
    return sum(abs(signed_dang(ang(chain[i - 1], chain[i]),
                               ang(chain[i], chain[i + 1])))
               for i in range(1, len(chain) - 1))


def max_bulge(a, b, qs):
    """The steepest bulge this span's own points justify: it may sweep
    as far as they turn, plus ARC_SLACK.  A span between two
    neighbours covers no turn, so it gets the slack alone - which is
    what stops a shaky scan coming back as a chain of loops."""
    return lh_tan(min((span_turn(a, b, qs) + ARC_SLACK) / 4.0, ANG_CAP))


def cap_b(bl, mx):
    return max(-mx, min(mx, bl))


def span_score(a, b, bul, qs, tol):
    """(written off, worst dev of the rest, misses among the rest).

    Only a point PLAINLY off - further than DROP_MULT times the
    tolerance - may be written off; that is what separates a bad shot
    from a feature.  A point that misses by merely a little still
    counts against the fit, so the span stops at it as it always
    did."""
    seg = (a, b, bul)
    drop, dev, mis = 0, 0.0, 0
    for q in qs:
        d = seg_dist(q, seg)
        if d > DROP_MULT * tol:
            drop += 1
        else:
            dev = max(dev, d)
            if d > _ON_EPS:
                mis += 1
    return drop, dev, mis


def span_kept(a, b, bul, qs, tol):
    """The points of QS this arc actually holds (within TOL)."""
    return [q for q in qs if seg_dist(q, (a, b, bul)) <= tol]


def snap_arc(a, b, bl, qs, tol, left, win):
    """Snap the radius to feet / half feet / inches inside WIN."""
    r0 = bulge_radius(a, b, bl)
    h = dist(a, b) / 2.0
    if r0 is None or r0 >= 1.0e6:
        return None
    for tier in NICE_RADII:
        lo = tier * int(r0 / tier)
        hi = lo + tier
        cands = [lo, hi] if (r0 - lo) < (hi - r0) else [hi, lo]
        for r in cands:
            if r < h or r <= 0.0:
                continue
            bl2 = radius_bulge(a, b, r, bl)
            if bl2 is None:
                continue
            if win and not (win[0] <= bl2 <= win[1]):
                continue
            if (span_dev(a, b, bl2, qs) <= tol
                    and span_misses(a, b, bl2, qs) <= left):
                return bl2, span_misses(a, b, bl2, qs)
    return None


def tang_window(te, a, b, wf=1.0):
    tt = TANG_TOL * wf
    phi = signed_dang(te, ang(a, b))
    alo = max(min((phi - tt) / 2.0, ANG_CAP), -ANG_CAP)
    ahi = max(min((phi + tt) / 2.0, ANG_CAP), -ANG_CAP)
    lo, hi = math.tan(alo), math.tan(ahi)
    return (lo, hi) if lo <= hi else (hi, lo)


def clamp_b(b, win):
    if win is None:
        return b
    return win[0] if b < win[0] else (win[1] if b > win[1] else b)


def span_fit(a, b, qs, win, tol, left, dlim=0):
    """Best bulge for A->B over QS inside WIN.

    Exact 3-point arcs - ones whose middle passes through one of the
    actual interior points - come first; compromise bulges that float
    between the points are the fallback.  No candidate may bulge
    further than the span's own points justify (max_bulge), so a span
    can never come back as a loop.  DLIM points may be written off
    (left plainly off - see span_score) instead of holding the span
    back; the fewer written off the better, and a tie goes to the
    closer fit.  Returns (bulge, dev, misses, exact, dropped).
    """
    bls = [bulge_3pt(a, q, b) for q in qs]
    mx = max_bulge(a, b, qs)
    best, bkey = None, None
    for bl in bls:
        if abs(bl) > mx:
            continue
        if win and not (win[0] <= bl <= win[1]):
            continue
        drop, d, mis = span_score(a, b, bl, qs, tol)
        # an exact arc still has to HOLD the span - the points it did
        # not write off must all be inside TOL - or the compromise
        # bulges below never get their turn
        if (d <= tol and drop <= dlim and mis <= left
                and (bkey is None or (drop, d) < bkey)):
            best, bkey = (bl, d, mis, True, drop), (drop, d)
    if best:
        return best
    m = len(qs)
    cands = [sum(bls) / m, bls[m // 2]]
    if m >= 4:
        cands += [bls[m // 4], bls[(3 * m) // 4]]
    if win:
        cands = [clamp_b(c, win) for c in cands]
        cands += [win[0], win[1], (win[0] + win[1]) / 2.0]
    for bl in [cap_b(c, mx) for c in cands]:
        drop, d, mis = span_score(a, b, bl, qs, tol)
        if bkey is None or (drop, d) < bkey:
            best, bkey = (bl, d, mis, False, drop), (drop, d)
    return best


def tour_index(p, tour):
    for k, q in enumerate(tour):
        if dist(p, q) < 1.0e-3:
            return k
    return None


def arc_count(segs):
    return sum(1 for s in segs if abs(s[2]) >= 1.0e-9)


# ---- open-path ordering ----------------------------------------------


def far_pair(pts):
    """The farthest-apart pair - the automatic ends of an open run."""
    best, a, b = -1.0, None, None
    for q in pts:
        for r in pts:
            d = dist(q, r)
            if d > best:
                best, a, b = d, q, r
    return a, b


def order_points_open(pts, e1=None, e2=None):
    """Order points into an OPEN run from E1 to E2 (None = pick the
    farthest-apart pair): nearest-neighbour walk from E1 with E2 forced
    last, then 2-opt with BOTH ENDS FIXED.

    Reversing tour[i+1..j] changes only the edges (i,i+1) and (j,j+1);
    with j capped at n-2 the index j+1 always exists, so there is no
    wraparound and no closing edge to price - porting the closed
    2-opt's delta would charge for an edge an open run does not have.
    """
    if e1 is None:
        e1, e2 = far_pair(pts)
    rest = [p for p in pts if p != e1 and p != e2]
    tour, cur = [e1], e1
    while rest:
        best = min(rest, key=lambda q: dist(cur, q))
        tour.append(best)
        rest.remove(best)
        cur = best
    tour.append(e2)
    n = len(tour)
    improved, passes = True, 0
    while improved and passes < 40:
        improved, passes = False, passes + 1
        for i in range(n - 2):
            for j in range(i + 1, n - 1):
                ti, ti1 = tour[i], tour[i + 1]
                tj, tj1 = tour[j], tour[j + 1]
                if (dist(ti, tj) + dist(ti1, tj1)
                        < dist(ti, ti1) + dist(tj, tj1) - 1.0e-9):
                    tour[i + 1:j + 1] = reversed(tour[i + 1:j + 1])
                    improved = True
    return tour


# ---- open-path span fitting ------------------------------------------


def sharp_flags_open(tour, corners=None):
    """Which tour points are kinks.  The two path ends have no joint,
    so they are never flagged - only interior points get a turn test."""
    n = len(tour)
    out = []
    for i in range(n):
        if i == 0 or i == n - 1:
            out.append(False)
            continue
        turn = abs(signed_dang(ang(tour[i - 1], tour[i]),
                               ang(tour[i], tour[i + 1])))
        declared = any(dist(tour[i], c) < 1.0e-3 for c in (corners or []))
        out.append(turn > CORNER_ANG or declared)
    return out


def grow_span(tour, pos, te, sharp, nogrow, lim, tol, left, dlim,
              prorate):
    """The longest feasible span from POS, written-off points allowed.

    The open twin of ABHD's grow_span: no wrap, no end window, because
    an open run has no seam to arrive at.  DLIM is how many of the
    covered points this span may give up on (see span_score); 0 means
    it must hold every one of them.  Returns
    (length, bulge, misses, window, dropped) or None."""
    a = tour[pos]
    best = best_exact = None
    for wf in TANG_STEPS:
        length = 2
        while length <= lim:
            if nogrow[pos + length - 1]:
                break
            b_end = tour[pos + length]
            win = (tang_window(te, a, b_end, wf)
                   if te is not None else None)
            qs = tour[pos + 1:pos + length]
            lm = (min(left, lh_ceil(MISS_PCT * length)) if prorate
                  else left)
            dm = min(dlim, lh_ceil(DROP_PCT * length)) if dlim else 0
            bl, dev, mis, exact, drop = span_fit(a, b_end, qs, win, tol,
                                                 lm, dm)
            if dev <= tol and mis <= lm and drop <= dm:
                best = (length, bl, mis, win, drop)
                if exact:
                    best_exact = best
                length += 1
            else:
                break
        if best:
            break
    # a floating arc must cover at least 2 more points than the
    # longest arc that passes through one
    if best_exact and best and best[0] < best_exact[0] + 2:
        best = best_exact
    return best


def span_path(tour, tol, left, prorate=True, walls=None, corners=None,
              holds=None, drops=0):
    """Cover the OPEN tour with arcs anchored on its points - the
    linear-index rewrite of span_loop.  No seam, no closing span, no
    start-tangent seeding: the first span starts free and the last
    simply ends at the final point.  A span may reach index n-1 and
    no further, so there is nothing to wrap around.

    DROPS is how many points the whole walk may leave unheld; it is
    spent only where a span has stopped growing and giving a point up
    buys at least two more points of span."""
    n = len(tour)
    sharp = sharp_flags_open(tour, corners)
    # declared straight stretches map straight onto linear indices
    wlist = []
    for w in (walls or []):
        i1, i2 = tour_index(w[0], tour), tour_index(w[1], tour)
        if i1 is None or i2 is None or i1 == i2:
            continue
        if i1 > i2:
            i1, i2 = i2, i1
        wlist.append((i1, i2))
    nogrow = list(sharp)
    for w in wlist:
        for i in range(n):
            if w[0] <= i <= w[1]:
                nogrow[i] = True
    # HELD points may end a span (landing on it exactly) but are
    # never buried inside one - mirror of the lh-holds check.  That
    # also puts them, the declared corners and the stretch points out
    # of reach of the write-off budget
    for h in (holds or []):
        hi = tour_index(h, tour)
        if hi is not None:
            nogrow[hi] = True
    segs = []
    pos = 0
    te = None
    stub = False           # was the span just emitted a one-point stub?
    while pos < n - 1:
        a = tour[pos]
        wrec = next((w for w in wlist if w[0] == pos), None)
        if wrec:
            # a declared straight stretch starts here: emit it verbatim
            b_end = tour[wrec[1]]
            qs = tour[pos + 1:wrec[1]]
            mis = span_misses(a, b_end, 0.0, qs)
            segs.append((a, b_end, 0.0))
            left = max(0, left - mis)
            pos = wrec[1]
            te = (None if pos < n - 1 and sharp[pos]
                  else ang(a, b_end))
            continue
        # one arc over the whole open run is legitimate: no stop-short
        lim = n - 1 - pos
        best = grow_span(tour, pos, te, sharp, nogrow, lim, tol, left, 0,
                         prorate)
        # writing a point off is a last resort: offered only where the
        # span stopped growing, and kept only when every point given
        # up bought at least two more points of span
        if drops > 0 and (best is None or best[0] < lim):
            alt = grow_span(tour, pos, te, sharp, nogrow, lim, tol, left,
                            drops, prorate)
            if (alt and alt[4] > 0
                    and alt[0] >= (best[0] if best else 1) + 2 * alt[4]):
                best = alt
        if best is None:
            # stub to the very next point.  One stub carries the
            # incoming tangent on exactly; a second straight after it
            # keeps only what the tangent window allows, so a mismatch
            # decays instead of doubling at every stub until the arcs
            # come back as semicircles
            b_end = tour[pos + 1]
            if te is not None:
                phi = signed_dang(te, ang(a, b_end))
                if stub:
                    phi = max(-TANG_TOL, min(TANG_TOL, phi))
                bl = cap_b(lh_tan(phi / 2.0), max_bulge(a, b_end, []))
            else:
                bl = 0.0
            best = (1, bl, 0, None, 0)
            stub = True
        else:
            length, bl, mis, win, drop = best
            b_end = tour[pos + length]
            # the points this arc gave up on are out of the picture
            # now: they must not drag the nice-radius snap around
            qs = span_kept(a, b_end, bl, tour[pos + 1:pos + length], tol)
            dev0 = span_dev(a, b_end, bl, qs)
            anchored = bool(qs) and span_min(a, b_end, bl, qs) <= 2.0 * FIT_EPS
            sn = snap_arc(a, b_end, bl, qs,
                          max(dev0, SNAP_EPS), left, win)
            if (sn and abs(sn[0]) <= max_bulge(a, b_end, qs)
                    and (not anchored
                         or span_min(a, b_end, sn[0], qs) <= 2.0 * FIT_EPS)):
                best = (length, sn[0], sn[1], win, drop)
            stub = False
        length, bl, mis, win, drop = best
        b_end = tour[pos + length]
        segs.append((a, b_end, bl))
        left -= mis
        drops -= drop
        pos += length
        te = (None if pos < n - 1 and sharp[pos]
              else ang(a, b_end) + 2.0 * math.atan(bl))
    return segs, left


def fit_pass_open(tour, tol, left, prorate=True, walls=None,
                  corners=None, holds=None, drops=0):
    """One full open fit; no seam, so no seam-kink re-run exists."""
    global _ON_EPS
    saved, _ON_EPS = _ON_EPS, on_eps_for(tol)
    try:
        return span_path(tour, tol, left, prorate, walls, corners,
                         holds, drops)
    finally:
        _ON_EPS = saved


def coarse_path(tour, tol, maxarcs, allowance, walls=None,
                corners=None, prorate=True, holds=None, droppct=None):
    """Open fit with the curve cap.  Unlike coarse_loop the tour is
    NOT rotated: an open run's start and end are its endpoints.
    DROPPCT is the share of the points the walk may leave unheld
    (DROP_PCT unless given; the "tight" candidate passes 0)."""
    drops = lh_ceil((DROP_PCT if droppct is None else droppct)
                    * len(tour))
    segs, left = fit_pass_open(tour, tol, allowance, prorate, walls,
                               corners, holds, drops)
    if maxarcs is not None:
        tol2 = tol
        tries = 0
        while arc_count(segs) > maxarcs and tries < 40:
            tol2 *= 1.4
            tries += 1
            segs2, _ = fit_pass_open(tour, tol2, 10 ** 9, False, walls,
                                     corners, holds, drops)
            if arc_count(segs2) < arc_count(segs):
                segs = segs2
    return segs, left


# ---- output ----------------------------------------------------------


def make_pline_verts(segs, closed):
    """The (point, bulge) vertex list lh:compare hands lh:make-pline.

    A closed polyline's last vertex curves back to vertex 0 by itself;
    an OPEN polyline needs the final end point as one more vertex
    (bulge 0) or its last segment silently vanishes."""
    verts = [(s[0], s[2]) for s in segs]
    if not closed:
        verts.append((segs[-1][1], 0.0))
    return verts


def loop_pts(segs):
    """Sample the chain into points; arcs get intermediate samples."""
    out = []
    for s in segs:
        out.append(s[0])
        if abs(s[2]) >= 1.0e-9:
            g = arc_geom(s[0], s[1], s[2])
            if g:
                c, r, a1, a2 = g
                sweep = (norm_ang(a2 - a1) if s[2] > 0.0
                         else -norm_ang(a1 - a2))
                for j in range(1, 4):
                    aa = a1 + sweep * j / 4.0
                    out.append((c[0] + r * math.cos(aa),
                                c[1] + r * math.sin(aa)))
    return out


def cross3(o, p, q):
    return ((p[0] - o[0]) * (q[1] - o[1])
            - (p[1] - o[1]) * (q[0] - o[0]))


def segs_cross(a, b, c, d):
    d1, d2 = cross3(a, b, c), cross3(a, b, d)
    d3, d4 = cross3(c, d, a), cross3(c, d, b)
    return d1 * d2 < 0.0 and d3 * d4 < 0.0


def self_crosses(segs, closed):
    """Mirror of lh:self-crosses: closed chains test the chord ring
    with the first/last pair exempt; open chains test the open run,
    whose real end point is appended instead of the closing repeat."""
    p = loop_pts(segs)
    if closed:
        p = p + [p[0]]
    else:
        p = p + [segs[-1][1]]
    if len(p) < 4:
        return False
    n = len(p) - 1
    for i in range(n - 2):
        for j in range(i + 2, n):
            if closed and i == 0 and j == n - 1:
                continue
            if segs_cross(p[i], p[i + 1], p[j], p[j + 1]):
                return True
    return False


def pick_elev(zmode, zs):
    """Mirror of lh:pick-elev - the height the outline is drawn at."""
    if not zs:
        return 0.0
    if zmode == "Top":
        return max(zs)
    if zmode == "Bottom":
        return min(zs)
    if zmode == "Average":
        return sum(zs) / len(zs)
    return 0.0                       # "Zero"


# ---- fixtures --------------------------------------------------------


def arc_samples(cx, cy, r, a_from, a_to, n):
    """N points along one arc, in order."""
    return [(cx + r * math.cos(a_from + (a_to - a_from) * k / (n - 1)),
             cy + r * math.sin(a_from + (a_to - a_from) * k / (n - 1)))
            for k in range(n)]


def shuffled(pts):
    """A deterministic scramble (no randomness in the tests)."""
    return pts[::3] + pts[1::3] + pts[2::3]


def s_curve(n_per_arc=9):
    """An open S: three tangent-continuous arcs, sampled in order."""
    a = arc_samples(0.0, 0.0, 60.0, math.pi, math.pi / 2.0, n_per_arc)
    b = arc_samples(0.0, 120.0, 60.0, -math.pi / 2.0, 0.0, n_per_arc)
    c = arc_samples(120.0, 120.0, 60.0, math.pi, math.pi / 2.0, n_per_arc)
    out = []
    for p in a + b + c:
        if not out or dist(out[-1], p) > 1.0e-6:
            out.append(p)
    return out


def shaky_run(n=60, noise=0.6, seed=5):
    """An open run with real scan scatter on it."""
    import random
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        t = math.pi * i / (n - 1)
        r = 120.0 + 20.0 * math.sin(3.0 * t)
        out.append((r * math.cos(t) + rnd.uniform(-noise, noise),
                    r * math.sin(t) * 0.8 + rnd.uniform(-noise, noise)))
    return out


# ---- tests -----------------------------------------------------------


def test_shaky_scan_does_not_spaghetti():
    """A scan with scatter on it must not come back as loops.

    The open walk carries ABHD's stub, and had ABHD's bug with it:
    a stub continued the previous tangent exactly, which turns the arc
    twice as far as the chord ran, so a mismatch doubled at every stub
    until the arcs saturated as semicircles.  This run used to come
    back as 49 hairpins of 2.5 inch radius.
    """
    pts = shaky_run()
    tour = order_points_open(pts)
    step = (sum(dist(tour[i], tour[i + 1]) for i in range(len(tour) - 1))
            / (len(tour) - 1))
    for mode, ftol, left, dp in (("tight", TIGHT_TOL, 0, 0.0),
                                 ("asked", 1.0, lh_ceil(MISS_PCT * len(pts)),
                                  None),
                                 ("few", 1.0, 10 ** 9, None)):
        segs, _ = coarse_path(tour, ftol, None, left,
                              prorate=(mode != "few"), droppct=dp)
        arcs = [s for s in segs if abs(s[2]) > 1.0e-9]
        sweeps = [math.degrees(4.0 * math.atan(abs(s[2]))) for s in arcs]
        radii = [bulge_radius(*s) for s in arcs]
        assert max(sweeps) < 150.0, (mode, max(sweeps))
        assert min(radii) >= 0.5 * step, (
            "%s: an arc of radius %.1f on points %.1f apart"
            % (mode, min(radii), step))
        assert len(segs) <= 0.75 * len(pts), (mode, len(segs))
        # the ends of an open run are exactly the ends of the fit
        assert dist(segs[0][0], tour[0]) < 1.0e-9
        assert dist(segs[-1][1], tour[-1]) < 1.0e-9
    print("  a shaky scan comes back as a shape, not as loops")


def test_open_ordering_recovers_the_run():
    pts = arc_samples(0.0, 0.0, 100.0, 0.2, math.pi - 0.2, 15)
    tour = order_points_open(shuffled(pts), None, None)
    assert len(tour) == len(pts)
    # the automatic ends are the farthest-apart pair - here the arc's
    # two extremes - and the recovered order is the sampled order,
    # one way or the other
    assert tour == pts or tour == pts[::-1], \
        "open ordering failed to recover an arc's sample order"
    print("  open ordering recovers a scrambled arc, ends at the extremes")


def test_open_ordering_honours_forced_ends():
    pts = arc_samples(0.0, 0.0, 100.0, 0.2, math.pi - 0.2, 15)
    e1, e2 = pts[-1], pts[0]
    tour = order_points_open(shuffled(pts), e1, e2)
    assert tour[0] == e1 and tour[-1] == e2, \
        "forced ends must stay the ends"
    assert tour == pts[::-1]
    print("  forced ends stay the ends of the run")


def test_open_2opt_unscrambles_the_interior():
    # a gentle open wave; the scramble builds a crossing NN walk that
    # only interior reversals can untangle
    pts = [(12.0 * k, 20.0 * math.sin(k * 0.45)) for k in range(14)]
    tour = order_points_open(shuffled(pts), pts[0], pts[-1])
    assert tour == pts, "2-opt did not restore the by-parameter order"
    # and the fixed-end 2-opt never prices a closing edge: the path
    # length of the recovered order matches the true order exactly
    true_len = sum(dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    tour_len = sum(dist(tour[i], tour[i + 1]) for i in range(len(tour) - 1))
    assert abs(true_len - tour_len) < 1.0e-9
    print("  open 2-opt unscrambles the interior with no phantom edge")


def test_single_arc_covers_the_whole_run():
    # every point on one arc: the open walker may (and should) cover
    # the run with ONE span - reaching index n-1 exactly, which is the
    # wraparound regression the linear rewrite exists to avoid
    pts = arc_samples(0.0, 0.0, 96.0, 0.3, math.pi - 0.3, 13)
    segs, _ = fit_pass_open(pts, 1.0, 2)
    assert len(segs) == 1, \
        "one arc holds every point - no stop-short rule applies open"
    assert segs[0][0] == pts[0] and segs[0][1] == pts[-1]
    assert span_dev(segs[0][0], segs[0][1], segs[0][2], pts) <= 1.0
    print("  a single arc may cover the whole open run")


def test_open_fit_covers_and_ends_on_the_endpoints():
    pts = s_curve()
    tol = 1.0
    allow = lh_ceil(MISS_PCT * len(pts))
    segs, _ = fit_pass_open(pts, tol, allow)
    assert segs[0][0] == pts[0], "the fit must start at the first point"
    assert segs[-1][1] == pts[-1], "the fit must end at the last point"
    # chained: each span starts where the previous ended
    for s1, s2 in zip(segs, segs[1:]):
        assert s1[1] == s2[0]
    # every point held within the tolerance, minus the allowance
    off = sum(1 for q in pts
              if min(seg_dist(q, s) for s in segs) > tol)
    assert off == 0, "%d point(s) beyond tolerance" % off
    print("  the open fit spans end to end and holds the points")


def test_open_vertex_list_keeps_the_last_segment():
    pts = s_curve()
    segs, _ = fit_pass_open(pts, 1.0, 2)
    verts = make_pline_verts(segs, closed=False)
    assert len(verts) == len(segs) + 1, \
        "an open polyline needs segs+1 vertices or the last one vanishes"
    assert verts[-1][0] == segs[-1][1]
    assert verts[-1][1] == 0.0, "the terminal vertex carries no bulge"
    closed_verts = make_pline_verts(segs, closed=True)
    assert len(closed_verts) == len(segs)
    print("  open vertex lists carry the terminal point, closed do not")


def test_declared_stretch_stays_straight_open():
    # a straight run between two arcs; declare it and it must come out
    # as one dead-straight segment between exactly those two points
    left = arc_samples(-40.0, 0.0, 40.0, math.pi, math.pi / 2.0, 7)
    right = arc_samples(140.0, 0.0, 40.0, math.pi / 2.0, 0.0, 7)
    flat = [(x, 40.0) for x in (-10.0, 25.0, 60.0, 95.0, 110.0)]
    pts = []
    for p in left + flat[1:-1] + right:
        if not pts or dist(pts[-1], p) > 1.0e-6:
            pts.append(p)
    tour = order_points_open(pts, left[0], right[-1])
    w1, w2 = left[-1], right[0]      # ends of the flat top
    segs, _ = fit_pass_open(tour, 1.0, 3, walls=[(w1, w2)])
    wall = [s for s in segs if s[0] == w1 and s[1] == w2]
    assert len(wall) == 1, "the declared stretch was not emitted"
    assert wall[0][2] == 0.0, "the declared stretch must stay straight"
    print("  a declared straight stretch survives the open fit verbatim")


def test_declared_corner_breaks_the_open_path():
    # a gentle interior elbow, declared a corner: the fit must break
    # there instead of rounding it off
    pts = ([(20.0 * k, 4.0 * k) for k in range(7)]
           + [(120.0 + 20.0 * k, 24.0 - 5.0 * k) for k in range(1, 7)])
    corner = pts[6]
    segs, _ = fit_pass_open(pts, 0.5, 2, corners=[corner])
    assert any(s[1] == corner for s in segs), \
        "the declared corner must end a span"
    print("  a declared corner breaks the open path")


def test_curve_cap_relaxes_the_open_fit():
    pts = s_curve()
    free, _ = coarse_path(pts, 0.05, None, 0)
    capped, _ = coarse_path(pts, 0.05, 1, 0)
    assert arc_count(free) >= 3, "the S needs several arcs when tight"
    assert arc_count(capped) < arc_count(free), \
        "the cap must trade accuracy for fewer curves"
    print("  the curve cap relaxes the open fit into fewer arcs")


def test_open_self_cross_detection():
    # an S does not cross itself
    segs, _ = fit_pass_open(s_curve(), 1.0, 2)
    assert not self_crosses(segs, closed=False)
    # a 3-segment chain whose last segment cuts back through the first
    bow = [((0.0, 0.0), (100.0, 0.0), 0.0),
           ((100.0, 0.0), (100.0, 50.0), 0.0),
           ((100.0, 50.0), (50.0, -50.0), 0.0)]
    assert self_crosses(bow, closed=False), "the cut-back must register"
    # a closed square: the seam chord pair is exempt, no false alarm
    sq = [((0.0, 0.0), (100.0, 0.0), 0.0),
          ((100.0, 0.0), (100.0, 100.0), 0.0),
          ((100.0, 100.0), (0.0, 100.0), 0.0),
          ((0.0, 100.0), (0.0, 0.0), 0.0)]
    assert not self_crosses(sq, closed=True)
    print("  self-cross detection: open cut-backs yes, closed seams no")


def test_held_point_splits_the_single_arc():
    """A held point is never buried: even when one arc would cover
    the whole open run, a hold in the middle forces the walker to
    land on it exactly and carry on from there."""
    pts = arc_samples(0.0, 0.0, 96.0, 0.3, math.pi - 0.3, 13)
    hold = pts[6]
    segs, _ = fit_pass_open(pts, 1.0, 2, holds=[hold])
    assert len(segs) >= 2, "the hold must break the single arc"
    assert any(s[1] == hold for s in segs) \
        and any(s[0] == hold for s in segs), \
        "the held point must be a span endpoint"
    assert min(seg_dist(hold, s) for s in segs) < 1.0e-9
    # the joint at the hold is still tangency-checked, not a corner:
    # both spans fit the same circle, so the kink stays tiny
    at = [s for s in segs if s[1] == hold][0]
    nx = [s for s in segs if s[0] == hold][0]
    te = ang(at[0], at[1]) + 2.0 * math.atan(at[2])
    ts = ang(nx[0], nx[1]) - 2.0 * math.atan(nx[2])
    assert abs(signed_dang(te, ts)) <= TANG_TOL * TANG_STEPS[-1] + 1e-6
    print("  a held point splits the single arc and stays tangent")


def test_held_point_cannot_be_fudged_open():
    """A point nudged off the curve - one the miss allowance would
    happily write off - must be hit exactly once held."""
    pts = s_curve()
    bump = (pts[10][0] + 0.5, pts[10][1] + 0.6)
    pts[10] = bump
    tol = 1.0
    segs, _ = fit_pass_open(pts, tol, lh_ceil(MISS_PCT * len(pts)),
                            holds=[bump])
    assert min(seg_dist(bump, s) for s in segs) < 1.0e-9, \
        "the held point must sit on the fit exactly"
    for q in pts:
        assert min(seg_dist(q, s) for s in segs) <= tol
    # and with the allowance lifted ("few" aim) the hold still binds
    segs2, _ = coarse_path(pts, tol, None, 10 ** 6, prorate=False,
                           holds=[bump])
    assert min(seg_dist(bump, s) for s in segs2) < 1.0e-9
    print("  a held point is hit exactly, even with misses free")


def test_output_height_modes():
    zs = [3.0, 9.0, 6.0]
    assert pick_elev("Top", zs) == 9.0
    assert pick_elev("Bottom", zs) == 3.0
    assert pick_elev("Average", zs) == 6.0
    assert pick_elev("Zero", zs) == 0.0
    assert pick_elev("Top", []) == 0.0, "no elevations = height 0"
    print("  the output height follows Top/Bottom/Average/Zero")


# ---- structural checks on the .lsp file ------------------------------


def paren_depth(src):
    """Net paren depth, recognising strings and comments in one pass."""
    depth, in_str, in_comment, escaped = 0, False, False, False
    for ch in src:
        if in_comment:
            if ch == "\n":
                in_comment = False
        elif in_str:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == ";":
            in_comment = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                raise AssertionError(
                    "lhd.lsp closes a paren that never opened")
    return depth


def test_lisp_file_is_well_formed():
    """Catch unbalanced parentheses before AutoCAD does."""
    src = open(LISP_FILE).read()
    depth = paren_depth(src)
    assert depth == 0, "lhd.lsp has %d unclosed paren(s)" % depth
    defined = set(re.findall(r"\(defun\s+((?:lh:|c:)[^\s(]+)", src))
    called = set(re.findall(r"\((lh:[a-z0-9-]+)", src))
    missing = called - defined
    assert not missing, "lhd.lsp calls undefined: %s" % sorted(missing)
    dead = {d for d in defined - called if not d.startswith("c:")}
    assert not dead, "lhd.lsp defines but never calls: %s" % sorted(dead)
    assert "c:LHD" in defined, "lhd.lsp no longer defines c:LHD"
    # the pieces the flow depends on: the open-path machinery that is
    # new here, and the closed engine carried over from ABHD
    for fn in ("lh:span-path", "lh:fit-pass-open", "lh:coarse-path",
               "lh:order-points-open", "lh:far-pair",
               "lh:span-loop", "lh:fit-pass", "lh:coarse-loop",
               "lh:order-points", "lh:loop-order", "lh:chain",
               "lh:compare", "lh:build", "lh:make-pline",
               "lh:self-crosses", "lh:report", "lh:mark-unheld",
               "lh:ask-tol", "lh:ask-pct", "lh:ask-cap",
               "lh:ask-shape", "lh:ask-zmode", "lh:pick-elev",
               "lh:zs-of", "lh:block-number", "lh:pt-name",
               "lh:edit-walls", "lh:edit-corners", "lh:edit-holds",
               "lh:draw-hold-marker", "lh:snap-break",
               "lh:tag-mine", "lh:purge-mine", "lh:temp-clear"):
        assert fn in defined, "lhd.lsp no longer defines %s" % fn
    print("  lhd.lsp is balanced and self-consistent")


def test_versioned_copy():
    """lhd.lsp uses the auto-stamped release convention: its banner
    matches release_lisp.py's regex, and the dated twin under
    releases/ is byte-identical with a REV that matches the banner."""
    src = open(LISP_FILE, "rb").read()
    m = re.search(rb'\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"', src)
    assert m, ("lhd.lsp lost its *lh-version* banner - release_lisp.py"
               " would silently skip it")
    rev = (m.group(1) + m.group(2)).decode()
    twins = [f for f in os.listdir(RELEASES_DIR)
             if re.match(r"lhd_\d{6}_REV\d+\.lsp$", f)]
    assert len(twins) == 1, \
        "expected exactly one lhd_MMDDYY_REV#.lsp - run " \
        "python3 tools/release_lisp.py (found %s)" % twins
    twin = twins[0]
    assert twin.endswith("_REV%s.lsp" % rev), \
        "twin %s does not carry the banner's REV%s" % (twin, rev)
    assert open(os.path.join(RELEASES_DIR, twin), "rb").read() == src, \
        "%s has drifted from lhd.lsp - re-run tools/release_lisp.py" % twin
    print("  versioned twin %s matches lhd.lsp" % twin)


def test_constants_match_lisp():
    """The LISP and this mirror must stay in step."""
    src = open(LISP_FILE).read()

    def setq_value(name):
        m = re.search(r"\(setq\s+\*LH-%s\*\s+([^)\n;]+)" % name, src)
        assert m, "could not find *LH-%s* in lhd.lsp" % name
        return m.group(1).strip()

    assert float(setq_value("ON-EPS")) == ON_EPS
    assert float(setq_value("MISS-PCT")) == MISS_PCT
    assert float(setq_value("SNAP-EPS")) == SNAP_EPS
    assert float(setq_value("FIT-EPS")) == FIT_EPS
    assert float(setq_value("TOL-MAX")) == TOL_MAX
    assert float(setq_value("TIGHT-TOL")) == TIGHT_TOL
    assert float(setq_value("TEXT-EPS")) == TEXT_EPS
    assert float(setq_value("DROP-PCT")) == DROP_PCT
    assert float(setq_value("DROP-MULT")) == DROP_MULT
    # the three candidate aims, in the order they are drawn
    m = re.search(r"\(setq \*LH-COMPARE\*[^']*'\((.*?)\)\)\)", src, re.S)
    assert m, "could not read *LH-COMPARE* from lhd.lsp"
    assert tuple(re.findall(r'\(\s*"([a-z]+)"', m.group(1))) \
        == COMPARE_MODES, "the candidate modes moved or were renamed"
    # angles are written as (/ pi N)
    for name, want in (("CORNER-ANG", CORNER_ANG), ("TANG-TOL", TANG_TOL),
                       ("ARC-SLACK", ARC_SLACK)):
        m = re.search(r"\(setq\s+\*LH-%s\*\s+\(/\s+pi\s+([0-9.]+)\)"
                      % name, src)
        assert m, "could not read *LH-%s* from lhd.lsp" % name
        assert abs(math.pi / float(m.group(1)) - want) < 1.0e-12, name
    for name, want in (("NICE-RADII", NICE_RADII),
                       ("TANG-STEPS", TANG_STEPS)):
        m = re.search(r"\(setq\s+\*LH-%s\*\s+'\(([^)]*)\)" % name, src)
        assert m, "could not read *LH-%s* from lhd.lsp" % name
        assert tuple(float(x) for x in m.group(1).split()) == want, name
    print("  constants match lhd.lsp")


# ---- the fitter is ABHD's, and has to stay ABHD's --------------------

ABHD_FILE = os.path.join(REPO_DIR, "lisp", "abhd", "abhd.lsp")

# the span fitter LHD carries over from ABHD.  Copied code drifts
# the moment one side is fixed and the other is forgotten - which is
# exactly what happened when ABHD's runaway-tangent fix landed - so
# every one of these is compared, code for code, against abhd.lsp.
SHARED_FITTER = ("span-dev", "span-misses", "span-min", "span-turn",
    "max-bulge", "cap-b", "span-score", "span-kept", "better",
    "snap-arc", "span-fit", "grow-span", "span-loop", "fit-pass",
    "coarse-loop", "tang-window", "end-window", "merge-windows",
    "clamp-b",)


def code_defuns(src, prefix):
    """Every defun under PREFIX as bare code: comments and blank lines
    stripped, so a difference in wording is not a difference in
    behaviour."""
    out, lines, i = {}, src.split("\n"), 0
    while i < len(lines):
        m = re.match(r"\(defun\s+%s([a-z0-9-]+)\s" % re.escape(prefix),
                     lines[i])
        if m:
            name, depth, body = m.group(1), 0, []
            while i < len(lines):
                raw = lines[i]
                masked = re.sub(r'"(\\.|[^"\\])*"',
                                lambda x: "S" * len(x.group()), raw)
                cut = masked.find(";")
                code = raw[:cut] if cut >= 0 else raw
                counted = masked[:cut] if cut >= 0 else masked
                if code.strip():
                    body.append(code.rstrip())
                depth += counted.count("(") - counted.count(")")
                i += 1
                if depth <= 0:
                    break
            out[name] = "\n".join(body)
        else:
            i += 1
    return out


def one_namespace(text, prefix):
    """Rewrite a tool's prefix to a neutral one, so two copies of the
    same function compare equal."""
    return (text.replace(prefix, "X:")
                .replace("*%s-" % prefix[:-1].upper(), "*X-")
                .replace("%s-" % prefix[:-1], "X-"))


def test_fitter_is_still_abhds():
    theirs = code_defuns(open(ABHD_FILE).read(), "pf:")
    ours = code_defuns(open(LISP_FILE).read(), "lh:")
    for name in SHARED_FITTER:
        assert name in ours, "LHD no longer defines lh:%s" % name
        assert name in theirs, "abhd.lsp no longer defines pf:%s" % name
        assert one_namespace(ours[name], "lh:") == \
            one_namespace(theirs[name], "pf:"), (
                "lh:%s has drifted from pf:%s - the two must be the"
                " same fitter" % (name, name))
    print("  the %d shared fitter helpers still match abhd.lsp"
          % len(SHARED_FITTER))


def main():
    print("LHD fitter tests")
    test_lisp_file_is_well_formed()
    test_versioned_copy()
    test_constants_match_lisp()
    test_fitter_is_still_abhds()
    test_shaky_scan_does_not_spaghetti()
    test_open_ordering_recovers_the_run()
    test_open_ordering_honours_forced_ends()
    test_open_2opt_unscrambles_the_interior()
    test_single_arc_covers_the_whole_run()
    test_open_fit_covers_and_ends_on_the_endpoints()
    test_open_vertex_list_keeps_the_last_segment()
    test_declared_stretch_stays_straight_open()
    test_declared_corner_breaks_the_open_path()
    test_curve_cap_relaxes_the_open_fit()
    test_open_self_cross_detection()
    test_held_point_splits_the_single_arc()
    test_held_point_cannot_be_fudged_open()
    test_output_height_modes()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
