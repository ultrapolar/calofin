# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the ABHD pool-perimeter fitter (pool_fit_lisp/abhd.lsp).

abhd.lsp is AutoLISP and only runs inside AutoCAD, so the functions
below are a faithful Python mirror of its geometry and fitting logic:
same algorithm, same constants, same control flow, same function names
(``pf:span-fit`` -> ``span_fit``).  Editing the fitter means editing
both, and ``test_constants_match_lisp`` fails loudly when the tuning
values drift apart.

This covers the maths.  The AutoLISP transcription itself is checked
inside AutoCAD by the ``ABHDTEST`` command that ships in abhd.lsp.

The defaults were calibrated against a real hand-drawn as-built trace
(55 survey points on a 37x16 ft pool).  That survey is client data and
is deliberately not committed here; the synthetic shapes below stand
in for it as regression fixtures.

Usage:  python3 tests/test_pool_fit.py
"""

import math
import os
import re

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
LISP_FILE = os.path.join(os.path.dirname(TESTS_DIR),
                         "pool_fit_lisp", "abhd.lsp")

# ---- tuning constants, mirrored from abhd.lsp ------------------------

ON_EPS = 0.25                      # *PF-ON-EPS*
MISS_PCT = 0.15                    # *PF-MISS-PCT*
TOL_MAX = 2.0                      # *PF-TOL-MAX*
SNAP_EPS = 0.02                    # *PF-SNAP-EPS*
FIT_EPS = 0.01                     # *PF-FIT-EPS*
CORNER_ANG = math.pi / 4.0         # *PF-CORNER-ANG*
TANG_TOL = math.pi / 22.5          # *PF-TANG-TOL*
NICE_RADII = (12.0, 6.0, 1.0)      # *PF-NICE-RADII*
ANG_CAP = 1.373                    # window-edge clamp, atan(5)

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


def pf_ceil(x):
    f = int(x)
    return f + 1 if x > f else f


def pf_tan(x):
    """Mirror of pf:tan - clamped so it can never divide by zero."""
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
        return pf_tan(dccw / 4.0)
    return -pf_tan((2.0 * math.pi - dccw) / 4.0)


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
    return pf_tan(signed_dang(tang, ang(a, b)) / 2.0)


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


def nice_radius_p(r):
    if r is None or r >= 1.0e6:
        return False
    return any(abs(r / tier - round(r / tier)) < 1.0e-6
               for tier in NICE_RADII)


# ---- span helpers ----------------------------------------------------


def span_dev(a, b, bul, qs):
    return max((seg_dist(q, (a, b, bul)) for q in qs), default=0.0)


# The "on the shape" threshold in force for the current pass; mirrors
# the pf-on-eps free variable in abhd.lsp.  It scales with the
# tolerance so a loose run does not count every point as a miss.
_ON_EPS = ON_EPS


def on_eps_for(tol):
    return max(ON_EPS, 0.25 * tol)


def span_misses(a, b, bul, qs):
    return sum(1 for q in qs if seg_dist(q, (a, b, bul)) > _ON_EPS)


def span_min(a, b, bul, qs):
    return min((seg_dist(q, (a, b, bul)) for q in qs), default=None)


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


# ---- near-tangent span fitting ---------------------------------------


def tang_window(te, a, b):
    phi = signed_dang(te, ang(a, b))
    alo = max(min((phi - TANG_TOL) / 2.0, ANG_CAP), -ANG_CAP)
    ahi = max(min((phi + TANG_TOL) / 2.0, ANG_CAP), -ANG_CAP)
    lo, hi = math.tan(alo), math.tan(ahi)
    return (lo, hi) if lo <= hi else (hi, lo)


def end_window(ts0, a, b):
    psi = signed_dang(ang(a, b), ts0)
    alo = max(min((psi - TANG_TOL) / 2.0, ANG_CAP), -ANG_CAP)
    ahi = max(min((psi + TANG_TOL) / 2.0, ANG_CAP), -ANG_CAP)
    lo, hi = math.tan(alo), math.tan(ahi)
    return (lo, hi) if lo <= hi else (hi, lo)


def merge_windows(win, win2):
    if win is None:
        return win2
    if win2 is None:
        return win
    lo, hi = max(win[0], win2[0]), min(win[1], win2[1])
    if lo <= hi:
        return (lo, hi)
    mid = ((win[1] + win2[0]) / 2.0 if win[1] < win2[0]
           else (win2[1] + win[0]) / 2.0)
    return (mid, mid)


def clamp_b(b, win):
    if win is None:
        return b
    return win[0] if b < win[0] else (win[1] if b > win[1] else b)


def span_fit(a, b, qs, win, tol, left):
    """Best bulge for A->B over QS inside WIN.

    Exact 3-point arcs - ones whose middle passes through one of the
    actual interior points - come first; compromise bulges that float
    between the points are the fallback.  Returns
    (bulge, dev, misses, exact).
    """
    bls = [bulge_3pt(a, q, b) for q in qs]
    best = None
    for bl in bls:
        if win and not (win[0] <= bl <= win[1]):
            continue
        d = span_dev(a, b, bl, qs)
        if d <= tol and (best is None or d < best[1]):
            mis = span_misses(a, b, bl, qs)
            if mis <= left:
                best = (bl, d, mis, True)
    if best:
        return best
    m = len(qs)
    cands = [sum(bls) / m, bls[m // 2]]
    if m >= 4:
        cands += [bls[m // 4], bls[(3 * m) // 4]]
    if win:
        cands = [clamp_b(c, win) for c in cands]
        cands += [win[0], win[1], (win[0] + win[1]) / 2.0]
    for bl in cands:
        d = span_dev(a, b, bl, qs)
        if best is None or d < best[1]:
            best = (bl, d, span_misses(a, b, bl, qs), False)
    return best


def sharp_flags(tour):
    n = len(tour)
    out = []
    for i in range(n):
        prev, cur, nxt = tour[(i + n - 1) % n], tour[i], tour[(i + 1) % n]
        turn = abs(signed_dang(ang(prev, cur), ang(cur, nxt)))
        out.append(turn > CORNER_ANG)
    return out


def rotate_to_corner(tour):
    n = len(tour)
    best, bi = -1.0, 0
    for i in range(n):
        prev, cur, nxt = tour[(i + n - 1) % n], tour[i], tour[(i + 1) % n]
        turn = abs(signed_dang(ang(prev, cur), ang(cur, nxt)))
        if turn > best:
            best, bi = turn, i
    return tour[bi:] + tour[:bi]


def tour_index(p, tour):
    for k, q in enumerate(tour):
        if dist(p, q) < 1.0e-3:
            return k
    return None


def rotate_to_point(tour, p):
    """Start the walk at P, so a declared wall never straddles the
    walk's origin."""
    i = tour_index(p, tour)
    return tour[i:] + tour[:i] if i else tour


def arc_count(segs):
    return sum(1 for s in segs if abs(s[2]) >= 1.0e-9)


def span_loop(tour, tol, left, te0=None, prorate=True, walls=None):
    """Cover the closed TOUR with arcs anchored on its points.

    When PRORATE is set each span may spend only its own fair share of
    the miss allowance, so one greedy span cannot exhaust the budget
    and starve the rest of the loop into single-point stubs.  The
    curve cap turns it off: there the whole point is to trade accuracy
    for few curves.

    WALLS is the list of user-declared straight walls, as pairs of
    tour points: each is emitted verbatim as a straight LINE span, and
    ordinary spans may neither swallow nor cross them.
    """
    n = len(tour)
    sharp = sharp_flags(tour)
    start_sharp = sharp[0]
    # map the declared walls onto tour indices, the short way around;
    # the tour was rotated so none straddles index 0
    wlist = []
    for w in (walls or []):
        i1, i2 = tour_index(w[0], tour), tour_index(w[1], tour)
        if i1 is None or i2 is None or i1 == i2:
            continue
        fwd = (i2 - i1) % n
        if 2 * fwd > n:
            i1, fwd = i2, n - fwd
        if i1 + fwd <= n:
            wlist.append((i1, i1 + fwd))
    nogrow = list(sharp)
    for w in wlist:
        for i in range(n):
            if w[0] <= i <= w[1]:
                nogrow[i] = True
        if w[1] == n:
            nogrow[0] = True
    segs = []
    pos = 0
    te = None if start_sharp else te0
    ts0 = None
    while pos < n:
        a = tour[pos]
        wrec = next((w for w in wlist if w[0] == pos), None)
        if wrec:
            # a declared straight wall starts here: emit it verbatim
            b_end = tour[wrec[1] % n]
            qs = tour[pos + 1:wrec[1]]
            mis = span_misses(a, b_end, 0.0, qs)
            segs.append((a, b_end, 0.0))
            left = max(0, left - mis)
            if ts0 is None and not start_sharp:
                ts0 = ang(a, b_end)
            pos = wrec[1]
            te = (None if pos < n and sharp[pos % n]
                  else ang(a, b_end))
            continue
        # one span may never swallow the whole loop, or the result
        # would be a single zero-length segment
        lim = n - pos - (1 if pos == 0 else 0)
        best = best_exact = None
        # first pass honours the tangent window; if nothing fits inside
        # it, retry without it rather than emitting a stub that
        # continues an unsuitable tangent and cascades
        for relaxed in (False, True):
            length = 2
            while length <= lim:
                if nogrow[(pos + length - 1) % n]:
                    break
                b_end = tour[(pos + length) % n]
                if relaxed:
                    win = None
                else:
                    win = (tang_window(te, a, b_end)
                           if te is not None else None)
                    if (pos + length == n and not start_sharp
                            and ts0 is not None):
                        win = merge_windows(win,
                                            end_window(ts0, a, b_end))
                qs = tour[pos + 1:pos + length]
                lm = (min(left, pf_ceil(MISS_PCT * length)) if prorate
                      else left)
                bl, dev, mis, exact = span_fit(a, b_end, qs, win, tol, lm)
                if dev <= tol and mis <= lm:
                    best = (length, bl, mis, win)
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
        if best is None:
            b_end = tour[(pos + 1) % n]
            if te is not None:
                bl = tangent_bulge(a, te, b_end)
                if pos + 1 == n and not start_sharp and ts0 is not None:
                    bl = (bl + pf_tan(
                        signed_dang(ang(a, b_end), ts0) / 2.0)) / 2.0
                bl = max(-1.0, min(1.0, bl))
            else:
                bl = 0.0
            best = (1, bl, 0, None)
        else:
            length, bl, mis, win = best
            b_end = tour[(pos + length) % n]
            qs = tour[pos + 1:pos + length]
            dev0 = span_dev(a, b_end, bl, qs)
            anchored = span_min(a, b_end, bl, qs) <= 2.0 * FIT_EPS
            sn = snap_arc(a, b_end, bl, qs,
                          max(dev0, SNAP_EPS), left, win)
            if sn and (not anchored
                       or span_min(a, b_end, sn[0], qs) <= 2.0 * FIT_EPS):
                best = (length, sn[0], sn[1], win)
        length, bl, mis, win = best
        b_end = tour[(pos + length) % n]
        segs.append((a, b_end, bl))
        left -= mis
        if ts0 is None and not start_sharp:
            ts0 = ang(a, b_end) - 2.0 * math.atan(bl)
        pos += length
        te = (None if sharp[pos % n]
              else ang(a, b_end) + 2.0 * math.atan(bl))
    return segs, left


def seam_kink(segs):
    s_last, s_first = segs[-1], segs[0]
    te = ang(s_last[0], s_last[1]) + 2.0 * math.atan(s_last[2])
    ts = ang(s_first[0], s_first[1]) - 2.0 * math.atan(s_first[2])
    return abs(signed_dang(te, ts))


def fit_pass(tour, tol, left, prorate=True, walls=None):
    """One full fit; the on-the-shape threshold tracks this tolerance."""
    global _ON_EPS
    saved, _ON_EPS = _ON_EPS, on_eps_for(tol)
    try:
        segs, l1 = span_loop(tour, tol, left, None, prorate, walls)
        k1 = seam_kink(segs)
        if k1 > TANG_TOL + 0.001:
            s_last = segs[-1]
            te0 = ang(s_last[0], s_last[1]) + 2.0 * math.atan(s_last[2])
            segs2, l2 = span_loop(tour, tol, left, te0, prorate, walls)
            if seam_kink(segs2) < k1:
                return segs2, l2
        return segs, l1
    finally:
        _ON_EPS = saved


def coarse_loop(tour, tol, maxarcs, allowance, walls=None):
    """Full fit; the curve cap relaxes the tolerance and refits."""
    # start the walk at a declared wall when there is one, so no wall
    # straddles the walk's origin; otherwise at the sharpest turn
    tour = (rotate_to_point(tour, walls[0][0]) if walls
            else rotate_to_corner(tour))
    segs, left = fit_pass(tour, tol, allowance, True, walls)
    # the cap buys few curves with accuracy, so its refits drop both
    # the miss allowance and the per-span fair share
    if maxarcs is not None:
        tol2 = tol
        tries = 0
        while arc_count(segs) > maxarcs and tries < 40:
            tol2 *= 1.4
            tries += 1
            segs2, _ = fit_pass(tour, tol2, 10 ** 9, False, walls)
            if arc_count(segs2) < arc_count(segs):
                segs = segs2
    return segs, left


def order_points(pts):
    """Nearest-neighbour tour from the leftmost point, then 2-opt."""
    start = min(pts, key=lambda p: (p[0], p[1]))
    rest = [p for p in pts if p != start]
    tour, cur = [start], start
    while rest:
        best = min(rest, key=lambda q: dist(cur, q))
        tour.append(best)
        rest.remove(best)
        cur = best
    n = len(tour)
    improved, passes = True, 0
    while improved and passes < 40:
        improved, passes = False, passes + 1
        for i in range(n - 1):
            for j in range(i + 1, n):
                if i == 0 and j == n - 1:
                    continue
                ti, ti1 = tour[i], tour[i + 1]
                tj, tj1 = tour[j], tour[(j + 1) % n]
                if (dist(ti, tj) + dist(ti1, tj1)
                        < dist(ti, ti1) + dist(tj, tj1) - 1.0e-9):
                    tour[i + 1:j + 1] = reversed(tour[i + 1:j + 1])
                    improved = True
    return tour


# ---- self-intersection -----------------------------------------------


def cross3(o, p, q):
    return ((p[0] - o[0]) * (q[1] - o[1])
            - (p[1] - o[1]) * (q[0] - o[0]))


def segs_cross(a, b, c, d):
    d1, d2 = cross3(a, b, c), cross3(a, b, d)
    d3, d4 = cross3(c, d, a), cross3(c, d, b)
    return d1 * d2 < 0.0 and d3 * d4 < 0.0


def loop_pts(segs):
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


def self_crosses(segs):
    p = loop_pts(segs)
    if len(p) < 4:
        return False
    p = p + [p[0]]
    n = len(p) - 1
    for i in range(n - 2):
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            if segs_cross(p[i], p[i + 1], p[j], p[j + 1]):
                return True
    return False


# ---- measurements used by the tests ----------------------------------


def fit(pts, tol=1.0, maxarcs=None, walls=None):
    allowance = pf_ceil(MISS_PCT * len(pts))
    tour = order_points(list(pts))
    return coarse_loop(tour, tol, maxarcs, allowance, walls)


def closed(segs):
    return all(dist(s[1], segs[(i + 1) % len(segs)][0]) < 1.0e-9
               for i, s in enumerate(segs))


def worst_dev(segs, pts):
    return max(min(seg_dist(p, s) for s in segs) for p in pts)


def max_kink(segs):
    """Worst tangent break at a joint that is not an intended corner."""
    worst = 0.0
    for i, s in enumerate(segs):
        s2 = segs[(i + 1) % len(segs)]
        te = ang(s[0], s[1]) + 2.0 * math.atan(s[2])
        ts = ang(s2[0], s2[1]) - 2.0 * math.atan(s2[2])
        k = abs(signed_dang(te, ts))
        if k <= CORNER_ANG:
            worst = max(worst, k)
    return worst


def floating_arcs(segs, pts):
    """(floating, total) arcs that cover points but touch none of them."""
    floating = total = 0
    for s in segs:
        if abs(s[2]) < 1.0e-9:
            continue
        inner = [p for p in pts
                 if dist(p, s[0]) > 0.01 and dist(p, s[1]) > 0.01
                 and seg_dist(p, s) < 2.0]
        if not inner:
            continue
        total += 1
        if min(seg_dist(p, s) for p in inner) > 2.0 * FIT_EPS:
            floating += 1
    return floating, total


# ---- synthetic shapes ------------------------------------------------


def circle_pts(n=36, r=150.0):
    return [(r * math.cos(2 * math.pi * i / n),
             r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def blob_pts(n=56, noise=0.0, seed=3):
    """A kidney-shaped organic pool, like a real survey."""
    import random
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        r = (110.0 + 35.0 * math.cos(t) + 18.0 * math.sin(2 * t)
             - 12.0 * math.cos(3 * t))
        out.append((r * math.cos(t) * 1.15 + rnd.uniform(-noise, noise),
                    r * math.sin(t) * 0.8 + rnd.uniform(-noise, noise)))
    return out


def rounded_rect_pts(w=240.0, h=120.0, r=24.0, step=14.0):
    pts = []

    def wall(x0, y0, x1, y1):
        length = math.hypot(x1 - x0, y1 - y0)
        k = max(1, int(length / step))
        for i in range(k):
            t = i / k
            pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))

    def corner(cx, cy, a0):
        k = max(2, int(r * math.pi / 2 / step))
        for i in range(k):
            t = a0 + (math.pi / 2) * i / k
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))

    wall(r, 0, w - r, 0)
    corner(w - r, r, -math.pi / 2)
    wall(w, r, w, h - r)
    corner(w - r, h - r, 0)
    wall(w - r, h, r, h)
    corner(r, h - r, math.pi / 2)
    wall(0, h - r, 0, r)
    corner(r, r, math.pi)
    return pts


# ---- tests -----------------------------------------------------------


def test_geometry_helpers():
    # an arc built through three points really passes through them
    b = bulge_3pt((0.0, 0.0), (5.0, 5.0), (10.0, 0.0))
    assert seg_dist((5.0, 5.0), ((0.0, 0.0), (10.0, 0.0), b)) < 1.0e-9

    # collinear and degenerate inputs are straight, never a crash
    assert abs(bulge_3pt((0.0, 0.0), (5.0, 0.0), (10.0, 0.0))) < 1.0e-9
    assert bulge_3pt((0.0, 0.0), (5.0, 5.0), (0.0, 0.0)) == 0.0
    assert isinstance(
        bulge_3pt((0.0, 0.0), (5.0, 5.0), (1.0e-11, 0.0)), float)

    # the tangent helper is clamped instead of dividing by zero
    assert math.isfinite(pf_tan(math.pi / 2.0))
    assert math.isfinite(pf_tan(-math.pi / 2.0))

    # radius <-> bulge round-trip
    bl = radius_bulge((0.0, 0.0), (10.0, 0.0), 13.0, 0.5)
    assert abs(bulge_radius((0.0, 0.0), (10.0, 0.0), bl) - 13.0) < 1.0e-9
    assert nice_radius_p(24.0) and nice_radius_p(18.0)
    assert not nice_radius_p(23.71)
    print("  geometry helpers ok")


def test_self_crossing_detection():
    bowtie = [((0.0, 0.0), (10.0, 10.0), 0.0),
              ((10.0, 10.0), (10.0, 0.0), 0.0),
              ((10.0, 0.0), (0.0, 10.0), 0.0),
              ((0.0, 10.0), (0.0, 0.0), 0.0)]
    square = [((0.0, 0.0), (10.0, 0.0), 0.0),
              ((10.0, 0.0), (10.0, 10.0), 0.0),
              ((10.0, 10.0), (0.0, 10.0), 0.0),
              ((0.0, 10.0), (0.0, 0.0), 0.0)]
    assert self_crosses(bowtie)
    assert not self_crosses(square)
    print("  self-crossing detection ok")


def test_circle_becomes_two_arcs():
    pts = circle_pts(36, 150.0)
    segs, _ = fit(pts)
    assert closed(segs)
    assert len(segs) <= 4, len(segs)
    assert arc_count(segs) == len(segs)
    assert worst_dev(segs, pts) < 1.0e-6
    for s in segs:
        assert abs(bulge_radius(*s) - 150.0) < 1.0e-6
    print("  circle -> %d arcs on the exact radius" % len(segs))


def test_polygon_keeps_its_corners():
    for pts in ([(0.0, 0.0), (120.0, 0.0), (120.0, 120.0), (0.0, 120.0)],
                [(120.0 * math.cos(math.pi / 3 * i),
                  120.0 * math.sin(math.pi / 3 * i)) for i in range(6)]):
        segs, _ = fit(pts)
        assert closed(segs)
        assert len(segs) == len(pts), (len(segs), len(pts))
        assert arc_count(segs) == 0, "corner-only polygon should stay lines"
        assert worst_dev(segs, pts) < 1.0e-9
    print("  polygons stay polygons")


def test_organic_blob():
    for noise, seed in ((0.0, 3), (0.15, 11)):
        pts = blob_pts(56, noise, seed)
        allowance = pf_ceil(MISS_PCT * len(pts))
        segs, left = fit(pts)
        assert closed(segs), "loop is not closed"
        assert not self_crosses(segs), "fit crosses itself"
        assert worst_dev(segs, pts) <= 1.0, worst_dev(segs, pts)
        assert left >= 0, "miss allowance overspent"
        # every point either sits on the shape or uses the allowance
        off = sum(1 for p in pts
                  if min(seg_dist(p, s) for s in segs) > ON_EPS)
        assert off <= allowance, (off, allowance)
        # smooth: no joint may break tangency by more than the window
        assert max_kink(segs) <= TANG_TOL + 1.0e-6, math.degrees(
            max_kink(segs))
        # few curves: a 56-point organic pool must not need a curve per
        # point-and-a-half
        assert len(segs) <= 26, len(segs)
        print("  blob (noise %.2f): %d segments, worst %.2f, kink %.1f deg"
              % (noise, len(segs), worst_dev(segs, pts),
                 math.degrees(max_kink(segs))))


def test_arcs_sit_on_the_points():
    """Arcs floating between points are the exception, not the rule."""
    for pts in (blob_pts(56), blob_pts(56, 0.15, 11), rounded_rect_pts()):
        segs, _ = fit(pts)
        floating, total = floating_arcs(segs, pts)
        assert total > 0
        assert floating <= total / 3.0, (
            "%d of %d arcs float between the points" % (floating, total))
        print("  arcs through a point: %d of %d" % (total - floating, total))


def test_nice_radii_are_preferred():
    """Radii land on feet / half feet / inches when that is free.

    Snapping only fires when it costs the covered points (almost)
    nothing, so the rate depends on how much slack the data has.
    Real surveys are noisy and leave plenty - the reference as-built
    lands ~3/4 of its arcs on nice radii - while mathematically
    perfect points leave none, and there the fit correctly keeps the
    exact radius rather than pulling arcs off their points.  The
    floors below only prove snapping still works; they are not a
    target.
    """
    for label, pts, floor in (
            ("noisy", blob_pts(56, 0.15, 11), 0.15),
            ("perfectly smooth", blob_pts(56), 0.1)):
        segs, _ = fit(pts)
        arcs = [s for s in segs if abs(s[2]) >= 1.0e-9]
        nice = sum(1 for s in arcs if nice_radius_p(bulge_radius(*s)))
        assert nice >= len(arcs) * floor, (label, nice, len(arcs))
        print("  nice radii, %s: %d of %d arcs"
              % (label, nice, len(arcs)))


def test_curve_cap():
    for label, pts in (("blob", blob_pts(56)),
                       ("noisy", blob_pts(56, 0.15, 11)),
                       ("rect", rounded_rect_pts())):
        uncapped, _ = fit(pts)
        for cap in (1, 2, 3, 5, 8, 12):
            segs, _ = fit(pts, maxarcs=cap)
            assert closed(segs), (label, cap)
            # the cap is honoured, or the loop has bottomed out at the
            # 2 segments a closed shape cannot go below
            assert arc_count(segs) <= cap or len(segs) <= 2, (
                label, cap, arc_count(segs))
            assert len(segs) <= len(uncapped), (
                "%s: cap %d produced MORE segments than no cap at all"
                % (label, cap))
            # a cap must never collapse the loop into a zero-length
            # segment, which is what "one span swallowed everything"
            # used to produce
            assert min(dist(s[0], s[1]) for s in segs) > 1.0e-6, (
                label, cap)
        print("  curve cap honoured on %s (cap 1 -> %d segments)"
              % (label, len(fit(pts, maxarcs=1)[0])))


def test_tolerance_scales_the_fit():
    """A looser tolerance must never produce a busier result.

    This is the regression guard for allowance starvation: the miss
    budget used to be spent by the first few long spans, after which
    every remaining span collapsed to a one-point stub - so tol 4.0
    gave 46 segments where tol 1.0 gave 12.
    """
    pts = blob_pts(56)
    counts = []
    for tol in (0.25, 0.5, 1.0, 2.0, 4.0, 8.0):
        segs, _ = fit(pts, tol=tol)
        assert closed(segs)
        assert min(dist(s[0], s[1]) for s in segs) > 1.0e-6
        counts.append((tol, len(segs)))
    for (tol_a, n_a), (tol_b, n_b) in zip(counts, counts[1:]):
        assert n_b <= n_a + 1, (
            "tolerance %.2f gave %d segments but the looser %.2f gave %d"
            % (tol_a, n_a, tol_b, n_b))
    tight, _ = fit(pts, tol=0.25)
    assert worst_dev(tight, pts) <= 0.25 + 1.0e-6
    print("  segments by tolerance: "
          + ", ".join("%.2f->%d" % c for c in counts))


def test_declared_straight_walls():
    """A user-declared wall comes out as exactly one straight segment
    between its two survey points, whatever the arcs around it do."""
    pts = blob_pts(56)
    tour = order_points(list(pts))

    def wall_in(segs, w):
        return [s for s in segs if abs(s[2]) < 1.0e-9
                and ((dist(s[0], w[0]) < 1.0e-9
                      and dist(s[1], w[1]) < 1.0e-9)
                     or (dist(s[0], w[1]) < 1.0e-9
                         and dist(s[1], w[0]) < 1.0e-9))]

    w1 = (tour[10], tour[14])
    segs, _ = fit(pts, walls=[w1])
    assert closed(segs)
    assert len(wall_in(segs, w1)) == 1, "declared wall not one straight seg"
    assert all(math.isfinite(s[2]) for s in segs)

    # two walls at once, plus a curve cap on top
    w2 = (tour[30], tour[33])
    segs, _ = fit(pts, walls=[w1, w2])
    assert closed(segs)
    assert len(wall_in(segs, w1)) == 1
    assert len(wall_in(segs, w2)) == 1
    capped, _ = fit(pts, maxarcs=6, walls=[w1])
    assert closed(capped)
    assert len(wall_in(capped, w1)) == 1, "cap refit lost the wall"
    # a degenerate wall (same point twice) is simply ignored
    segs, _ = fit(pts, walls=[(tour[5], tour[5])])
    assert closed(segs)
    print("  declared straight walls survive fitting and the cap")


def test_degenerate_point_sets():
    """Three points, duplicates and near-collinear runs must not blow up."""
    segs, _ = fit([(0.0, 0.0), (100.0, 0.0), (50.0, 40.0)])
    assert closed(segs) and len(segs) >= 2
    line = [(float(i) * 10.0, 0.0) for i in range(6)]
    line += [(50.0, 5.0), (0.0, 5.0)]
    segs, _ = fit(line)
    assert closed(segs)
    assert all(math.isfinite(s[2]) for s in segs)
    print("  degenerate point sets survive")


def test_constants_match_lisp():
    """The LISP and this mirror must stay in step."""
    src = open(LISP_FILE).read()

    def setq_value(name):
        m = re.search(r"\(setq\s+\*PF-%s\*\s+([^)\n;]+)" % name, src)
        assert m, "could not find *PF-%s* in abhd.lsp" % name
        return m.group(1).strip()

    assert float(setq_value("ON-EPS")) == ON_EPS
    assert float(setq_value("MISS-PCT")) == MISS_PCT
    assert float(setq_value("SNAP-EPS")) == SNAP_EPS
    assert float(setq_value("FIT-EPS")) == FIT_EPS
    assert float(setq_value("TOL-MAX")) == TOL_MAX
    # angles are written as (/ pi N)
    for name, want in (("CORNER-ANG", CORNER_ANG), ("TANG-TOL", TANG_TOL)):
        m = re.search(r"\(setq\s+\*PF-%s\*\s+\(/\s+pi\s+([0-9.]+)\)"
                      % name, src)
        assert m, "could not read *PF-%s* from abhd.lsp" % name
        assert abs(math.pi / float(m.group(1)) - want) < 1.0e-12, name
    m = re.search(r"\(setq\s+\*PF-NICE-RADII\*\s+'\(([^)]*)\)", src)
    assert m
    assert tuple(float(x) for x in m.group(1).split()) == NICE_RADII
    print("  constants match abhd.lsp")


def test_lisp_file_is_well_formed():
    """Catch unbalanced parentheses before AutoCAD does."""
    src = open(LISP_FILE).read()
    stripped = re.sub(r'"(?:[^"\\]|\\.)*"', '""', src)
    stripped = re.sub(r";[^\n]*", "", stripped)
    depth = 0
    for ch in stripped:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            assert depth >= 0, "abhd.lsp closes a paren that never opened"
    assert depth == 0, "abhd.lsp has %d unclosed paren(s)" % depth
    defined = set(re.findall(r"\(defun\s+((?:pf:|c:)[^\s(]+)", src))
    called = set(re.findall(r"\((pf:[a-z0-9-]+)", src))
    missing = called - defined
    assert not missing, "abhd.lsp calls undefined: %s" % sorted(missing)
    dead = defined - called - {"c:ABHD"}
    assert not dead, "abhd.lsp defines but never calls: %s" % sorted(dead)
    assert "c:ABHD" in defined, "abhd.lsp no longer defines c:ABHD"
    # the pieces the interactive flow depends on
    for fn in ("pf:compare", "pf:build", "pf:guided-fit", "pf:unheld",
               "pf:mark-unheld", "pf:report"):
        assert fn in defined, "abhd.lsp no longer defines %s" % fn
    print("  abhd.lsp is balanced and self-consistent")


def main():
    print("ABHD fitter tests")
    test_lisp_file_is_well_formed()
    test_constants_match_lisp()
    test_geometry_helpers()
    test_self_crossing_detection()
    test_circle_becomes_two_arcs()
    test_polygon_keeps_its_corners()
    test_organic_blob()
    test_arcs_sit_on_the_points()
    test_nice_radii_are_preferred()
    test_curve_cap()
    test_tolerance_scales_the_fit()
    test_declared_straight_walls()
    test_degenerate_point_sets()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
