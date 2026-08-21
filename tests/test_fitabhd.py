# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests for the FITABHD typed pool fitter (lisp/fitabhd/FITABHD.lsp).

FITABHD.lsp is AutoLISP and only runs inside AutoCAD, so the functions
below are a faithful Python mirror of its geometry and fitting logic:
same algorithm, same constants, same control flow, same function names
(``fit:fit-polygon`` -> ``fit_polygon``).  Editing the fitter means
editing both, and ``test_constants_match_lisp`` fails loudly when the
tuning values drift apart.

Where ABHD traces whatever shape the points make, FITABHD is told the
pool's TYPE up front - Rectangle, Grecian, Roman, Oval, L, Lazy L or
Round - and fits that type's parametric template to the survey: wall
directions come from the template, only their positions (and the
corner radius / cut, end arcs, and so on) come from the points.  The
synthetic surveys below are production-shaped pools with survey noise;
each test checks the engine recovers the pool that generated it.

Usage:  python3 tests/test_fitabhd.py
"""

import math
import os
import re

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
LISP_FILE = os.path.join(REPO_DIR, "lisp", "fitabhd", "FITABHD.lsp")
SHARED_FILE = os.path.join(REPO_DIR, "shared", "parts", "FITABHD.lsp")
RELEASES_DIR = os.path.join(REPO_DIR, "releases")

# ---- tuning constants, mirrored from FITABHD.lsp ---------------------

ON_EPS = 0.25                      # fit:*on-eps*
TOL_MAX = 2.0                      # fit:*tol-max*
EXACT_EPS = 0.001                  # fit:*exact-eps*
CORNER_ZONE = 18.0                 # fit:*corner-zone*  (starting radius)
ZONE_PAD = 4.0                     # fit:*zone-pad*
ICP_ITERS = 12                     # fit:*icp-iters*
RAD_ITERS = 15                     # fit:*rad-iters*
RAD_MAX = 120.0                    # fit:*rad-max*   (10' fillet ceiling)
BOTH_EDGE = 0.8                    # fit:*both-edge*
VSIZE_MIN = 1.0                    # fit:*vsize-min*  (a smaller fitted
                                   # vertex easing reads as sharp)
FEAT_SNAP = 0.1                    # fit:*feat-snap*  (snapping a measured
                                   # feature may grow the worst deviation
                                   # by at most this - a tenth of an inch)
MISS_PCT = 0.15                    # fit:*miss-pct*   (share of the points
                                   # allowed beyond the distance)
BOW_MIN = 1.0                      # fit:*bow-min*    (a shallower bow reads
                                   # as a straight wall - an inch over
                                   # thirty feet is drafting noise, and
                                   # survey scatter alone can fake it)
BOW_MAX = 12.0                     # fit:*bow-max*    (a wall bowed more than
                                   # a foot is not a straight wall)
BOW_MAX_FRAC = 0.04                # fit:*bow-max-frac*
BOW_PTS_MIN = 4                    # fit:*bow-pts-min*
FEATURE_KEYS = ("SIZE", "VSIZE", "CUT", "RAD")
RAD_TURN_MIN = math.pi / 3.0       # fit:*rad-turn-min* (gentler corners
                                   # cannot be measured for a radius)
NICE_DIMS = (12.0, 6.0, 1.0, 0.5)  # fit:*nice-dims*
NICE_RADII = (12.0, 6.0, 1.0)      # fit:*nice-radii*
TYPES = ("Rectangle", "Grecian", "ROman", "Oval", "L", "LAzyl", "ROUnd")

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


def rot(p, a):
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c)


def dedupe(pts):
    out = []
    for q in pts:
        if not any(dist(q, p) < EXACT_EPS for p in out):
            out.append(q)
    return out


# ---- circle / arc geometry (same as ABHD's mirror) -------------------


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


def arc_geom(p1, p2, b):
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


def outline_dists(pts, segs):
    """Every point's distance to the nearest piece of the outline."""
    return [min(seg_dist(q, s) for s in segs) for q in pts]


def outline_dev(pts, segs):
    """(worst, rms) distance of the points from the outline."""
    ds = outline_dists(pts, segs)
    return max(ds), math.sqrt(sum(d * d for d in ds) / len(ds))


def held_worst(dists, allow):
    """The worst deviation once the ALLOW worst points are set aside -
    what the fit actually has to hold.  ALLOW = 0 is the plain worst.
    This is where the percent answered at step 4 is spent: a snap to a
    whole foot only has to convince all but that share of the points."""
    ds = sorted(dists, reverse=True)
    return ds[allow] if allow < len(ds) else 0.0


def fit_ceil(x):
    f = int(x)
    return f + 1 if x > f else f


# ---- ordering (ABHD's, unchanged) ------------------------------------


def order_points(pts):
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


# ---- the frame: which way the pool lies ------------------------------


def frame_angle(tour, fold):
    """Dominant wall direction folded modulo (360/fold) degrees.

    Every edge of the ordered ring votes with its length; folding by
    4 makes parallel and perpendicular walls reinforce each other, and
    folding by 8 pulls the 45-degree walls of a Lazy L into the same
    vote instead of letting the two families cancel.
    """
    sx = sy = 0.0
    n = len(tour)
    for i in range(n):
        a, b = tour[i], tour[(i + 1) % n]
        ln = dist(a, b)
        if ln < 1.0e-9:
            continue
        d = fold * ang(a, b)
        sx += ln * math.cos(d)
        sy += ln * math.sin(d)
    if abs(sx) < 1.0e-12 and abs(sy) < 1.0e-12:
        return 0.0
    return norm_ang(math.atan2(sy, sx)) / fold % (2.0 * math.pi / fold)


def to_frame(pts, a, mirror):
    """World -> frame: rotate by -a, then mirror across X if asked."""
    out = []
    for p in pts:
        q = rot(p, -a)
        out.append((q[0], -q[1]) if mirror else q)
    return out


def from_frame(p, a, mirror):
    q = (p[0], -p[1]) if mirror else p
    return rot(q, a)


def bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


# ---- fixed-direction polygon fit (the ICP core) ----------------------
#
# A template polygon is a CCW ring of walls whose DIRECTIONS are fixed
# by the pool type; only each wall's offset along its outward normal is
# fitted.  That is what "knowing the type" buys: a Lazy L's bend walls
# are at exactly 45 degrees, so the survey only has to say WHERE they
# are, never what they are.


def wall_normal(d):
    """Outward normal of a CCW ring edge with direction angle D."""
    return (math.sin(d), -math.cos(d))


def poly_corners(dirs, offs):
    """Corner list: corner i joins wall i-1 to wall i."""
    n = len(dirs)
    out = []
    for i in range(n):
        n1, d1 = wall_normal(dirs[i - 1]), offs[i - 1]
        n2, d2 = wall_normal(dirs[i]), offs[i]
        det = n1[0] * n2[1] - n1[1] * n2[0]
        if abs(det) < 1.0e-12:          # parallel walls cannot meet
            return None
        out.append(((d1 * n2[1] - d2 * n1[1]) / det,
                    (d2 * n1[0] - d1 * n2[0]) / det))
    return out


def poly_valid(dirs, offs):
    """A fitted polygon is only believable when every edge still runs
    in its template direction - a collapsed or bow-tied fit reverses
    one, and can still hug the points, so it must be rejected."""
    c = poly_corners(dirs, offs)
    if c is None:
        return False
    n = len(c)
    for i in range(n):
        u = (math.cos(dirs[i]), math.sin(dirs[i]))
        v = (c[(i + 1) % n][0] - c[i][0], c[(i + 1) % n][1] - c[i][1])
        if u[0] * v[0] + u[1] * v[1] <= 1.0e-6:
            return False
    return True


def poly_segs(dirs, offs):
    c = poly_corners(dirs, offs)
    if c is None:
        return None
    n = len(c)
    return [(c[i], c[(i + 1) % n], 0.0) for i in range(n)]


def assign_walls(pts, dirs, offs, zone):
    """Nearest-wall buckets, with points inside a corner's ZONE pulled
    into that corner's bucket instead.  Returns (wallpts, cornerpts)."""
    corners = poly_corners(dirs, offs)
    n = len(dirs)
    wallpts = [[] for _ in range(n)]
    cornerpts = [[] for _ in range(n)]
    if corners is None:
        return wallpts, cornerpts
    segs = [(corners[i], corners[(i + 1) % n], 0.0) for i in range(n)]
    for p in pts:
        best, bd = 0, None
        for i in range(n):
            d = seg_dist(p, segs[i])
            if bd is None or d < bd:
                best, bd = i, d
        # corner i sits between wall i-1 and wall i
        dc1 = dist(p, corners[best])
        dc2 = dist(p, corners[(best + 1) % n])
        if dc1 < zone or dc2 < zone:
            k = best if dc1 <= dc2 else (best + 1) % n
            cornerpts[k].append(p)
        else:
            wallpts[best].append(p)
    return wallpts, cornerpts


def fit_polygon(pts, dirs, offs, zone, iters=ICP_ITERS):
    """Iterate assignment / offset update.  Offsets a wall never sees
    a point for stay where they are."""
    offs = list(offs)
    for _ in range(iters):
        wallpts, _ = assign_walls(pts, dirs, offs, zone)
        new = list(offs)
        for i in range(len(dirs)):
            if wallpts[i]:
                nrm = wall_normal(dirs[i])
                new[i] = sum(nrm[0] * p[0] + nrm[1] * p[1]
                             for p in wallpts[i]) / len(wallpts[i])
        c = poly_corners(dirs, new)
        if c is not None:
            offs = new
    return offs


# ---- corner features: radius / cut -----------------------------------


def corner_frame(dirs, i):
    """(turn angle, fillet-centre direction unit) at corner i (between
    wall i-1 and wall i).  A convex corner's fillet centre sits along
    the interior bisector; a concave (notch) corner's sits along the
    exterior one - the arc bows out of the pool there."""
    turn = signed_dang(dirs[i - 1], dirs[i])
    n1, n2 = wall_normal(dirs[i - 1]), wall_normal(dirs[i])
    s = -1.0 if turn > 0.0 else 1.0
    bx, by = s * (n1[0] + n2[0]), s * (n1[1] + n2[1])
    ln = math.hypot(bx, by)
    if ln < 1.0e-9:
        return turn, (0.0, 0.0)
    return turn, (bx / ln, by / ln)


def corner_err(allpts, corners, dirs, r):
    """Mean squared radial error of the shared fillet radius R over
    the corner-zone points."""
    ssum, n = 0.0, 0
    for i, p in allpts:
        turn, bis = corner_frame(dirs, i)
        half = abs(turn) / 2.0
        if math.cos(half) < 1.0e-9:
            continue
        # centre distance from the vertex is r / cos(turn/2) - the
        # interior half-angle is 90 - turn/2, so this equals the
        # familiar r*sqrt(2) only at a square corner
        cc = (corners[i][0] + bis[0] * r / math.cos(half),
              corners[i][1] + bis[1] * r / math.cos(half))
        e = dist(p, cc) - r
        ssum += e * e
        n += 1
    return ssum / n if n else None


def fit_corner_radius(pts_by_corner, corners, dirs, which):
    """One shared fillet radius over the corners listed in WHICH,
    fitted by golden-section search - the direct fixed-point update is
    unstable for this geometry.  None when nothing landed in a zone."""
    allpts = []
    for i in which:
        allpts.extend((i, p) for p in pts_by_corner[i])
    if not allpts:
        return None
    gr = 0.6180339887
    lo, hi = 0.25, RAD_MAX
    a = hi - gr * (hi - lo)
    b = lo + gr * (hi - lo)
    fa = corner_err(allpts, corners, dirs, a)
    fb = corner_err(allpts, corners, dirs, b)
    if fa is None or fb is None:
        return None
    for _ in range(48):
        if fa <= fb:
            hi, b, fb = b, a, fa
            a = hi - gr * (hi - lo)
            fa = corner_err(allpts, corners, dirs, a)
        else:
            lo, a, fa = a, b, fb
            b = lo + gr * (hi - lo)
            fb = corner_err(allpts, corners, dirs, b)
    return (lo + hi) / 2.0


def fit_corner_cut(pts_by_corner, corners, dirs, which):
    """One shared cut-face length: the chamfer line's perpendicular
    inset from each corner, fitted as a plain mean."""
    hsum, n = 0.0, 0
    for i in which:
        turn, bis = corner_frame(dirs, i)
        if turn <= 0.0:                 # a notch corner takes no cut
            continue
        half = abs(turn) / 2.0
        for p in pts_by_corner[i]:
            hsum += (bis[0] * (p[0] - corners[i][0])
                     + bis[1] * (p[1] - corners[i][1]))
            n += 1
    if n == 0:
        return None
    h = hsum / n
    if h <= 0.0:
        return None
    # face length from the perpendicular inset: f = 2h / tan(turn/2)
    # (the interior half-angle is 90 - turn/2; at a square corner this
    # is the familiar f = 2h)
    turn, _ = corner_frame(dirs, which[0])
    return 2.0 * h / math.tan(abs(turn) / 2.0)


# ---- building the drawn outline --------------------------------------


def corner_verts(vprev, v, vnext, turn, treat, size):
    """The vertex run replacing sharp corner V: [(pt bulge), ...].
    The bulge on an entry curves the segment LEAVING that point."""
    if treat == "Radius" and size and size > 1.0e-6:
        u1 = ang(vprev, v)
        u2 = ang(v, vnext)
        t = size * math.tan(abs(turn) / 2.0)
        t1 = (v[0] - math.cos(u1) * t, v[1] - math.sin(u1) * t)
        t2 = (v[0] + math.cos(u2) * t, v[1] + math.sin(u2) * t)
        b = math.tan(turn / 4.0)
        return [(t1, b), (t2, 0.0)]
    if treat == "Cut" and size and size > 1.0e-6 and turn > 0.0:
        s = size / (2.0 * math.cos(abs(turn) / 2.0))
        u1 = ang(vprev, v)
        u2 = ang(v, vnext)
        t1 = (v[0] - math.cos(u1) * s, v[1] - math.sin(u1) * s)
        t2 = (v[0] + math.cos(u2) * s, v[1] + math.sin(u2) * s)
        return [(t1, 0.0), (t2, 0.0)]
    return [(v, 0.0)]


def verts_to_segs(verts):
    n = len(verts)
    return [(verts[i][0], verts[(i + 1) % n][0], verts[i][1])
            for i in range(n)]


def bow_bulge(s, cfit, a, b):
    """Bulge for the drawn chord A->B carrying the bow fitted as
    sagitta S over the corner-to-corner chord CFIT.  The RADIUS is what
    is preserved, so an eased corner shortening the wall does not
    deepen its bow.  A positive sagitta bows outward: on a CCW ring a
    positive bulge puts the apex to the right of travel, which is the
    outward side."""
    c = dist(a, b)
    if not s or cfit < 1.0e-9 or c < 1.0e-9:
        return 0.0
    r = cfit * cfit / (8.0 * abs(s)) + abs(s) / 2.0
    x = c / (2.0 * r)
    if x >= 1.0:
        return 0.0
    half = math.atan(x / math.sqrt(1.0 - x * x))      # = asin(x)
    bl = math.tan(half / 2.0)
    return bl if s > 0.0 else -bl


def build_polygon(dirs, offs, treat, size, which, bows=None):
    """Closed vertex list for the fitted polygon with the corner
    treatment applied to the corners in WHICH and, when BOWS is given,
    each wall carrying its own fitted bow.  A bow never moves a corner:
    it vanishes at both ends of its wall by construction."""
    corners = poly_corners(dirs, offs)
    n = len(corners)
    verts = []
    leaves = []
    for i in range(n):
        turn, _ = corner_frame(dirs, i)
        if i in which:
            verts.extend(corner_verts(corners[i - 1], corners[i],
                                      corners[(i + 1) % n], turn,
                                      treat, size))
        else:
            verts.append((corners[i], 0.0))
        leaves.append(len(verts) - 1)      # wall i leaves this vertex
    if bows:
        m = len(verts)
        for i in range(n):
            if not bows[i]:
                continue
            k = leaves[i]
            a, b = verts[k][0], verts[(k + 1) % m][0]
            cfit = dist(corners[i], corners[(i + 1) % n])
            verts[k] = (a, bow_bulge(bows[i], cfit, a, b))
    return verts


# ---- bowed walls -----------------------------------------------------
#
# "Straight" is a drafting convention, not a site measurement: a gunite
# wall shot dead straight on the order sheet is very often a very long
# radius on the ground.  When the user says the walls may be bowed,
# each wall is refitted as a constant offset plus a parabolic bow that
# vanishes at both corners - so the corners, and every design dimension
# taken between them, stay exactly where the straight fit put them, and
# only the wall between them breathes.


def fit_wall_bow(wpts, a, b):
    """Least squares (chord shift outward, sagitta outward) for the
    wall A->B over its own points.  None when the wall has too few
    points to tell a bow from noise."""
    c = dist(a, b)
    if c < 1.0e-9 or len(wpts) < BOW_PTS_MIN:
        return None
    ux, uy = (b[0] - a[0]) / c, (b[1] - a[1]) / c
    nx, ny = uy, -ux                       # right of travel = outward
    s11 = s1g = sgg = sy = sgy = 0.0
    for p in wpts:
        dx, dy = p[0] - a[0], p[1] - a[1]
        x = (dx * ux + dy * uy) / c
        g = 4.0 * x * (1.0 - x)            # 1 at mid-wall, 0 at both ends
        y = dx * nx + dy * ny
        s11 += 1.0
        s1g += g
        sgg += g * g
        sy += y
        sgy += g * y
    det = s11 * sgg - s1g * s1g
    if abs(det) < 1.0e-9:
        return None
    return ((sy * sgg - s1g * sgy) / det,
            (s11 * sgy - s1g * sy) / det)


def keep_bow(wpts, a, b, s):
    """A bow is kept only when it is deep enough to read, shallow
    enough to still be a wall, and beats the straight wall on that
    wall's own points by a clear margin.  Noise is not a bow."""
    c = dist(a, b)
    if not s or c < 1.0e-9 or len(wpts) < BOW_PTS_MIN or abs(s) < BOW_MIN:
        return 0.0
    _, rms_s = outline_dev(wpts, [(a, b, 0.0)])
    _, rms_b = outline_dev(wpts, [(a, b, bow_bulge(s, c, a, b))])
    return s if rms_b <= rms_s * BOTH_EDGE else 0.0


def bow_cap(s, c):
    smax = min(BOW_MAX, BOW_MAX_FRAC * c)
    return max(-smax, min(smax, s))


def fit_wall_bows(pts, dirs, offs, zone):
    """Refit every wall of a settled polygon as a shallow arc through
    its own points.  Returns (offs, bows), with 0.0 on every wall the
    points do not prove bowed - and that wall's offset put back to the
    plain straight-wall mean, so a dropped bow leaves no trace."""
    n = len(dirs)
    bows = [0.0] * n
    for _ in range(2):
        wallpts, _ = assign_walls(pts, dirs, offs, zone)
        corners = poly_corners(dirs, offs)
        if corners is None:
            return offs, [0.0] * n
        new, bows = list(offs), [0.0] * n
        for i in range(n):
            a, b = corners[i], corners[(i + 1) % n]
            got = fit_wall_bow(wallpts[i], a, b)
            if got is None:
                continue
            new[i] = offs[i] + got[0]
            bows[i] = bow_cap(got[1], dist(a, b))
        if poly_corners(dirs, new):
            offs = new
    wallpts, _ = assign_walls(pts, dirs, offs, zone)
    corners = poly_corners(dirs, offs)
    if corners is None:
        return offs, [0.0] * n
    offs = list(offs)
    for i in range(n):
        bows[i] = keep_bow(wallpts[i], corners[i], corners[(i + 1) % n],
                           bows[i])
        if not bows[i] and wallpts[i]:
            # the bow term biases the offset it was fitted beside, so a
            # wall that stays straight goes back to the straight mean
            nrm = wall_normal(dirs[i])
            offs[i] = sum(nrm[0] * p[0] + nrm[1] * p[1]
                          for p in wallpts[i]) / len(wallpts[i])
    return offs, bows


# ---- type templates --------------------------------------------------

RECT_DIRS = [0.0, math.pi / 2.0, math.pi, math.pi * 1.5]
GREC_DIRS = [i * math.pi / 4.0 for i in range(8)]
L_DIRS = [0.0, math.pi / 2.0, math.pi, math.pi * 1.5,
          math.pi, math.pi * 1.5]
LAZY_DIRS = [0.0, math.pi / 4.0, math.pi * 0.75, math.pi * 1.25,
             math.pi, math.pi * 1.5]


def support(pts, d):
    """Largest n.p over the points for wall direction D - the outermost
    line the cloud supports in that normal direction."""
    n = wall_normal(d)
    return max(n[0] * p[0] + n[1] * p[1] for p in pts)


def rect_init(pts):
    return [support(pts, d) for d in RECT_DIRS]


def grec_init(pts):
    offs = []
    for i, d in enumerate(GREC_DIRS):
        s = support(pts, d)
        offs.append(s if i % 2 == 0 else s - 15.0)   # nominal 15" cut inset
    return offs


def l_init(pts, lazy):
    x0, y0, x1, y1 = bbox(pts)
    if not lazy:
        ex = x0 + 0.5 * (x1 - x0)
        ey = y0 + 0.5 * (y1 - y0)
        corners = [(x0, y0), (x1, y0), (x1, y1), (ex, y1), (ex, ey),
                   (x0, ey)]
        dirs = L_DIRS
    else:
        w0 = 0.45 * min(x1 - x0, y1 - y0)
        cyy = y0 + 0.5 * (y1 - y0)
        b = (x1 - (cyy - y0), y0)
        c = (x1, cyy)
        d = (x1 - (y1 - cyy), y1)
        t = (y1 - (y0 + w0)) / 0.7071067812
        e = (d[0] - t * 0.7071067812, y0 + w0)
        corners = [(x0, y0), b, c, d, e, (x0, y0 + w0)]
        dirs = LAZY_DIRS
    offs = []
    for i in range(6):
        n = wall_normal(dirs[i])
        offs.append(n[0] * corners[i][0] + n[1] * corners[i][1])
    return offs


def fit_polytype(pts, dirs, offs0, treat):
    """Shared fit for the all-straight-wall types: walls, then the
    corner feature, then walls again with the zone sized to it."""
    zone = CORNER_ZONE if treat in ("Radius", "Cut") else 0.0
    offs = fit_polygon(pts, dirs, offs0, zone)
    size = None
    if treat in ("Radius", "Cut"):
        # only corners that turn hard enough vote for the size: a 45
        # degree corner's fillet apex sits under an inch off the sharp
        # corner, so its zone holds mostly wall points, which would
        # drag a shared radius fit way off
        voters = [i for i in range(len(dirs))
                  if abs(signed_dang(dirs[i - 1], dirs[i]))
                  >= RAD_TURN_MIN - 1.0e-9]
        _, cpts = assign_walls(pts, dirs, offs, zone)
        corners = poly_corners(dirs, offs)
        if treat == "Radius":
            size = fit_corner_radius(cpts, corners, dirs, voters)
        else:
            size = fit_corner_cut(cpts, corners, dirs, voters)
        if size and treat == "Radius":
            zone = 1.2 * size + ZONE_PAD
            offs = fit_polygon(pts, dirs, offs, zone)
            _, cpts = assign_walls(pts, dirs, offs, zone)
            corners = poly_corners(dirs, offs)
            size = fit_corner_radius(cpts, corners, dirs, voters)
    return offs, size


# ---- the arc-ended types (Roman / Oval) ------------------------------


def endcap_h(re, cx, cy, r, by, ty):
    """Half-height of the spring points where the end arc leaves the
    end line, clamped inside the side walls."""
    d = r * r - (re - cx) * (re - cx)
    if d <= 0.0:
        return 0.0
    return min(math.sqrt(d), (ty - by) / 2.0 - 1.0e-6)


def cap_wall_span(prm, both):
    """(xl, xr) - the x range the two side walls run over."""
    return ((prm["Re2"] if both else prm["Lx"]), prm["Re"])


def fit_cap_bows(pts, prm, both):
    """The Roman/Oval side walls, refitted as shallow arcs.  Returns
    (prm, (bow_bottom, bow_top)); the cap ends are untouched."""
    xl, xr = cap_wall_span(prm, both)
    lo, hi = min(xl, xr), max(xl, xr)
    by, ty = prm["By"], prm["Ty"]
    bot = [p for p in pts
           if lo <= p[0] <= hi and abs(p[1] - by) < abs(p[1] - ty)]
    top = [p for p in pts
           if lo <= p[0] <= hi and abs(p[1] - ty) <= abs(p[1] - by)]
    prm = dict(prm)
    bows = [0.0, 0.0]
    for k, (wpts, a, b) in enumerate(
            ((bot, (lo, by), (hi, by)), (top, (hi, ty), (lo, ty)))):
        got = fit_wall_bow(wpts, a, b)
        if got is None:
            continue
        shift, s = got[0], bow_cap(got[1], dist(a, b))
        if k == 0:
            a = (a[0], by - shift)
            b = (b[0], by - shift)
            prm["By"] = by - shift
        else:
            a = (a[0], ty + shift)
            b = (b[0], ty + shift)
            prm["Ty"] = ty + shift
        bows[k] = keep_bow(wpts, a, b, s)
    return prm, bows


def endcap_segs(prm, kind, both, bows=None):
    """Outline segments of the fitted end-capped body, frame coords.
    prm = dict with By Ty Lx Re cx r (and Re2 cx2 r2 when BOTH)."""
    by, ty = prm["By"], prm["Ty"]
    cy = (by + ty) / 2.0
    verts = []

    def cap(re, cx, r, sign):
        """Vertex run for one end cap; SIGN +1 = the +x end (walked
        bottom to top), -1 = the -x end (walked top to bottom)."""
        h = endcap_h(re, cx, cy, r, by, ty)
        stub = (ty - by) / 2.0 - h > 0.25
        out = []
        if sign > 0:
            lo, hi = (re, cy - h), (re, cy + h)
            a1, a2 = ang((cx, cy), lo), ang((cx, cy), hi)
            b = math.tan(norm_ang(a2 - a1) / 4.0)
            if stub:
                out.append(((re, by), 0.0))
            out.append((lo, b))
            if stub:
                out.append((hi, 0.0))
                out.append(((re, ty), 0.0))
            else:
                out.append((hi, 0.0))
        else:
            hi, lo = (re, cy + h), (re, cy - h)
            a1, a2 = ang((cx, cy), hi), ang((cx, cy), lo)
            b = math.tan(norm_ang(a2 - a1) / 4.0)
            if stub:
                out.append(((re, ty), 0.0))
            out.append((hi, b))
            if stub:
                out.append((lo, 0.0))
                out.append(((re, by), 0.0))
            else:
                out.append((lo, 0.0))
        return out

    verts.extend(cap(prm["Re"], prm["cx"], prm["r"], +1))
    itop = len(verts) - 1                  # the TOP wall leaves here
    if both:
        verts.extend(cap(prm["Re2"], prm["cx2"], prm["r2"], -1))
    else:
        verts.append(((prm["Lx"], ty), 0.0))
        verts.append(((prm["Lx"], by), 0.0))
    ibot = len(verts) - 1                  # the BOTTOM wall leaves here
    if bows:
        m = len(verts)
        for k, i in ((1, itop), (0, ibot)):
            if not bows[k]:
                continue
            a, b = verts[i][0], verts[(i + 1) % m][0]
            verts[i] = (a, bow_bulge(bows[k], dist(a, b), a, b))
    return verts_to_segs(verts)


def fit_endcap(pts, kind, both):
    """ICP for a rectangle body with a Roman or radius (Oval) end cap
    on the +x end - and on the -x end too when BOTH."""
    x0, y0, x1, y1 = bbox(pts)
    w = y1 - y0
    prm = {"By": y0, "Ty": y1, "Lx": x0}
    r0 = w / 2.0 if kind == "Oval" else 0.6 * w
    prm["r"] = r0
    prm["cx"] = x1 - r0
    prm["Re"] = (prm["cx"] if kind == "Oval"
                 else prm["cx"] + math.sqrt(max(0.0, r0 * r0
                                                - (0.4 * w) ** 2)))
    if both:
        prm["r2"] = r0
        prm["cx2"] = x0 + r0
        prm["Re2"] = (prm["cx2"] if kind == "Oval"
                      else prm["cx2"] - math.sqrt(max(0.0, r0 * r0
                                                      - (0.4 * w) ** 2)))
    for _ in range(ICP_ITERS):
        by, ty = prm["By"], prm["Ty"]
        cy = (by + ty) / 2.0
        # feature spans along x for the straight walls
        xr = prm["Re"]
        xl = prm["Re2"] if both else prm["Lx"]
        bot, top, lft, arc1, arc2, end1, end2 = [], [], [], [], [], [], []
        for p in pts:
            # nearest feature by construction, not by segment list:
            # classify by x band first, then by side
            d_arc1 = abs(dist(p, (prm["cx"], cy)) - prm["r"])
            if p[0] < prm["cx"]:
                d_arc1 = min(dist(p, (prm["Re"], by)),
                             dist(p, (prm["Re"], ty)))
            d_arc2 = None
            if both:
                d_arc2 = abs(dist(p, (prm["cx2"], cy)) - prm["r2"])
                if p[0] > prm["cx2"]:
                    d_arc2 = min(dist(p, (prm["Re2"], by)),
                                 dist(p, (prm["Re2"], ty)))
            d_bot = abs(p[1] - by) if xl <= p[0] <= xr else 1.0e9
            d_top = abs(p[1] - ty) if xl <= p[0] <= xr else 1.0e9
            d_lft = 1.0e9 if both else abs(p[0] - prm["Lx"])
            d_end1 = abs(p[0] - prm["Re"]) if abs(p[1] - cy) > \
                endcap_h(prm["Re"], prm["cx"], cy, prm["r"], by, ty) \
                else 1.0e9
            d_end2 = 1.0e9
            if both:
                d_end2 = (abs(p[0] - prm["Re2"])
                          if abs(p[1] - cy) > endcap_h(prm["Re2"],
                                                       prm["cx2"], cy,
                                                       prm["r2"], by, ty)
                          else 1.0e9)
            cand = [(d_bot, bot), (d_top, top), (d_arc1, arc1)]
            if both:
                cand.append((d_arc2, arc2))
            else:
                cand.append((d_lft, lft))
            if kind == "ROman":
                cand.append((d_end1, end1))
                if both:
                    cand.append((d_end2, end2))
            cand.sort(key=lambda cv: cv[0])
            cand[0][1].append(p)
        if bot:
            prm["By"] = sum(p[1] for p in bot) / len(bot)
        if top:
            prm["Ty"] = sum(p[1] for p in top) / len(top)
        if lft and not both:
            prm["Lx"] = sum(p[0] for p in lft) / len(lft)
        cy = (prm["By"] + prm["Ty"]) / 2.0
        w = prm["Ty"] - prm["By"]
        # right cap
        if arc1:
            if kind == "Oval":
                prm["r"] = w / 2.0
            else:
                cc = (prm["cx"], cy)
                prm["r"] = sum(dist(p, cc) for p in arc1) / len(arc1)
            ssum = n = 0
            for p in arc1:
                d = prm["r"] ** 2 - (p[1] - cy) ** 2
                if d > 0.0:
                    ssum += p[0] - math.sqrt(d)
                    n += 1
            if n:
                prm["cx"] = ssum / n
        if kind == "Oval":
            prm["r"] = w / 2.0
            prm["Re"] = prm["cx"]
        elif end1:
            prm["Re"] = sum(p[0] for p in end1) / len(end1)
        prm["Re"] = min(prm["Re"], prm["cx"] + prm["r"] - 0.5)
        # left cap
        if both:
            if arc2:
                if kind == "Oval":
                    prm["r2"] = w / 2.0
                else:
                    cc = (prm["cx2"], cy)
                    prm["r2"] = sum(dist(p, cc) for p in arc2) / len(arc2)
                ssum = n = 0
                for p in arc2:
                    d = prm["r2"] ** 2 - (p[1] - cy) ** 2
                    if d > 0.0:
                        ssum += p[0] + math.sqrt(d)
                        n += 1
                if n:
                    prm["cx2"] = ssum / n
            if kind == "Oval":
                prm["r2"] = w / 2.0
                prm["Re2"] = prm["cx2"]
            elif end2:
                prm["Re2"] = sum(p[0] for p in end2) / len(end2)
            prm["Re2"] = max(prm["Re2"], prm["cx2"] - prm["r2"] + 0.5)
    return prm


def fit_round(pts):
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    r = sum(dist(p, (cx, cy)) for p in pts) / len(pts)
    for _ in range(RAD_ITERS):
        r = sum(dist(p, (cx, cy)) for p in pts) / len(pts)
        sx = sy = 0.0
        for p in pts:
            d = dist(p, (cx, cy))
            if d < 1.0e-9:
                sx += p[0]
                sy += p[1]
            else:
                sx += p[0] - r * (p[0] - cx) / d
                sy += p[1] - r * (p[1] - cy) / d
        cx, cy = sx / len(pts), sy / len(pts)
    return {"cx": cx, "cy": cy, "r": r}


def round_segs(prm):
    c = (prm["cx"], prm["cy"])
    a = (c[0] + prm["r"], c[1])
    b = (c[0] - prm["r"], c[1])
    return [(a, b, 1.0), (b, a, 1.0)]


# ---- putting a whole type together -----------------------------------


def poly_result(ptype, fpts, dirs, offs0, treat):
    if len(dirs) == 8:
        # the cut corners are walls of their own here (Grecian, and a
        # Rectangle whose corners are Cut) - one shared face for all
        # 4.  TREAT is the treatment of the eight VERTICES: a nominal
        # grecian is sharp, an as-built may well be rounded, so Radius
        # (or Cut) measures a shared easing from the points.
        offs, _ = fit_polytype(fpts, dirs, offs0, "Square")
        size = grec_face(offs)
        offs = grec_cuts(offs, size)
        vsize = None
        if treat in ("Radius", "Cut"):
            vsize, offs, size = fit_vertex_feature(fpts, dirs, offs,
                                                   treat)
        which = set(range(8)) if vsize else set()
        verts = build_polygon(dirs, offs, treat, vsize, which)
        return {"kind": "poly", "type": ptype, "dirs": dirs,
                "offs": offs, "treat": treat, "size": size,
                "vsize": vsize, "which": which, "verts": verts,
                "bows": None, "valid": poly_valid(dirs, offs),
                "segs": verts_to_segs(verts)}
    offs, size = fit_polytype(fpts, dirs, offs0, treat)
    which = set(range(len(dirs))) if treat in ("Radius", "Cut") else set()
    verts = build_polygon(dirs, offs, treat, size, which)
    return {"kind": "poly", "type": ptype, "dirs": dirs, "offs": offs,
            "treat": treat, "size": size, "which": which, "verts": verts,
            "bows": None, "valid": poly_valid(dirs, offs),
            "segs": verts_to_segs(verts)}


def endcap_result(ptype, fpts, both):
    prm = fit_endcap(fpts, ptype, both)
    segs = endcap_segs(prm, ptype, both)
    return {"kind": "cap", "type": ptype, "prm": prm, "both": both,
            "bows": None, "segs": segs}


def fit_config(ptype, fpts, treat, both):
    if ptype == "Rectangle":
        if treat == "Cut":
            return poly_result(ptype, fpts, GREC_DIRS, grec_init(fpts),
                               "Square")
        return poly_result(ptype, fpts, RECT_DIRS, rect_init(fpts), treat)
    if ptype == "Grecian":
        return poly_result(ptype, fpts, GREC_DIRS, grec_init(fpts),
                           treat)
    if ptype == "L":
        return poly_result(ptype, fpts, L_DIRS, l_init(fpts, False),
                           treat)
    if ptype == "LAzyl":
        return poly_result(ptype, fpts, LAZY_DIRS, l_init(fpts, True),
                           treat)
    if ptype in ("ROman", "Oval"):
        return endcap_result(ptype, fpts, both)
    raise ValueError(ptype)


def configs_for(ptype):
    """(extra rotation, mirror, both-ends) candidates per type."""
    q = math.pi / 2.0
    if ptype in ("Rectangle", "Grecian"):
        return [(0.0, False, False)]
    if ptype in ("ROman", "Oval"):
        out = [(k * q, False, False) for k in range(4)]
        out += [(0.0, False, True), (q, False, True)]
        return out
    if ptype == "L":
        return [(k * q, m, False) for k in range(4)
                for m in (False, True)]
    if ptype == "LAzyl":
        e = math.pi / 4.0
        return [(k * e, m, False) for k in range(8)
                for m in (False, True)]
    return [(0.0, False, False)]


def fit_type(pts, ptype, treat):
    """Order, frame, and try every placement the type allows; the
    lowest-RMS one wins.  Returns the winning result dict with its
    frame (angle, mirror) and its outline in WORLD coordinates."""
    dpts = dedupe(pts)
    if ptype == "ROUnd":
        prm = fit_round(dpts)
        segs = round_segs(prm)
        worst, rms = outline_dev(dpts, segs)
        return {"kind": "round", "type": ptype, "prm": prm,
                "angle": 0.0, "mirror": False, "segs": segs,
                "worst": worst, "rms": rms}
    tour = order_points(dpts)
    a0 = frame_angle(tour, 8 if ptype == "LAzyl" else 4)
    best = None
    for extra, mirror, both in configs_for(ptype):
        a = a0 + extra
        fpts = to_frame(dpts, a, mirror)
        res = fit_config(ptype, fpts, treat, both)
        if res.get("valid") is False:
            continue
        worst, rms = outline_dev(fpts, res["segs"])
        # a both-ends cap has more freedom than a single-ended one, so
        # it only wins with a clear margin - a big flat arc can always
        # shave a little rms off a genuinely square end
        edge = BOTH_EDGE if (both and best is not None
                             and not best.get("both")) else 1.0
        if best is None or rms < best["rms"] * edge:
            res.update({"angle": a, "mirror": mirror,
                        "worst": worst, "rms": rms})
            best = res
    # a rectangle or grecian fits the same either way around - report
    # the long dimension as the length, deterministically
    if ptype in ("Rectangle", "Grecian")             and get_dim(best, "WID") > get_dim(best, "LEN"):
        a = best["angle"] + math.pi / 2.0
        fpts = to_frame(dpts, a, False)
        res = fit_config(ptype, fpts, treat, False)
        worst, rms = outline_dev(fpts, res["segs"])
        res.update({"angle": a, "mirror": False,
                    "worst": worst, "rms": rms})
        best = res
    return best


def world_segs(res):
    """The frame outline carried into world coordinates."""
    a, m = res["angle"], res["mirror"]
    out = []
    for p1, p2, b in frame_segs(res):
        out.append((from_frame(p1, a, m), from_frame(p2, a, m),
                    -b if m else b))
    return out


def frame_segs(res):
    if res["kind"] == "poly":
        return verts_to_segs(res["verts"])
    if res["kind"] == "cap":
        return endcap_segs(res["prm"], res["type"], res["both"])
    return round_segs(res["prm"])


# ---- nice dimensions -------------------------------------------------
#
# After the free fit, each headline dimension is snapped to the first
# friendly increment - whole feet, half feet, inches, half inches -
# that the points can live with: the snapped outline must stay within
# the run tolerance (or, when an outlier already sits beyond it, move
# nothing more than SNAP_EPS).  The points outrank pretty numbers.

SNAP_EPS = 0.02                    # fit:*snap-eps*


def grec_cuts(offs, face):
    """Recompute the four 45-degree cut walls so each sits the same
    perpendicular inset (face/2) from its own nominal square corner."""
    sq = poly_corners(RECT_DIRS, [offs[0], offs[2], offs[4], offs[6]])
    if sq is None:
        return offs
    out = list(offs)
    h = face / 2.0
    for k in range(4):
        i = 2 * k + 1
        n = wall_normal(GREC_DIRS[i])
        vc = sq[(k + 1) % 4]
        out[i] = n[0] * vc[0] + n[1] * vc[1] - h
    return out


def grec_face(offs):
    """The mean cut-face length the four fitted cut walls imply."""
    sq = poly_corners(RECT_DIRS, [offs[0], offs[2], offs[4], offs[6]])
    if sq is None:
        return 0.0
    hsum = 0.0
    for k in range(4):
        i = 2 * k + 1
        n = wall_normal(GREC_DIRS[i])
        vc = sq[(k + 1) % 4]
        hsum += n[0] * vc[0] + n[1] * vc[1] - offs[i]
    return 2.0 * hsum / 4.0


def fit_vertex_feature(pts, dirs, offs, treat):
    """The as-built easing of an 8-wall template's vertices: one shared
    fillet radius (or chamfer face) over all eight 45-degree corners.
    A nominal grecian is drawn sharp, but an as-built very often is
    not.  The corner zone is sized to the 45-degree turn (tangent
    length 0.414r), so wall points stay out of the vote, and the
    easing is kept only when it beats the sharp outline on the corner
    points by a clear margin - noise is not evidence, and neither is
    a fit below VSIZE_MIN.  Returns (vsize, offs, face)."""
    tanh = math.tan(math.pi / 8.0)
    cosh = math.cos(math.pi / 8.0)
    which = list(range(8))
    zone = CORNER_ZONE * tanh
    vs = None
    cpts = None
    face = grec_face(offs)
    for _ in range(2):
        _, cpts = assign_walls(pts, dirs, offs, zone)
        corners = poly_corners(dirs, offs)
        if treat == "Radius":
            vs = fit_corner_radius(cpts, corners, dirs, which)
        else:
            vs = fit_corner_cut(cpts, corners, dirs, which)
        if not vs:
            break
        # a fillet longer than the cut face cannot exist
        vs = min(vs, face / (2.0 * tanh))
        zone = (1.2 * vs * tanh + ZONE_PAD if treat == "Radius"
                else 1.2 * vs / (2.0 * cosh) + ZONE_PAD)
        offs = fit_polygon(pts, dirs, offs, zone)
        face = grec_face(offs)
        offs = grec_cuts(offs, face)
    if vs and vs >= VSIZE_MIN and cpts:
        czpts = [p for bucket in cpts for p in bucket]
        if czpts:
            sharp = verts_to_segs(build_polygon(dirs, offs, treat,
                                                None, set()))
            eased = verts_to_segs(build_polygon(dirs, offs, treat, vs,
                                                set(which)))
            _, rms_s = outline_dev(czpts, sharp)
            _, rms_e = outline_dev(czpts, eased)
            if rms_e > rms_s * BOTH_EDGE:
                vs = None
        else:
            vs = None
    else:
        vs = None
    return vs, offs, face


def dim_keys(res):
    ptype = res["type"]
    if ptype == "Rectangle":
        return ["LEN", "WID", "SIZE"]
    if ptype == "Grecian":
        keys = ["LEN", "WID", "CUT"]
        if res.get("vsize"):
            keys.append("VSIZE")
        return keys
    if ptype == "L":
        return ["LEN", "WID", "WINGX", "WINGY", "SIZE"]
    if ptype == "LAzyl":
        return ["SIZE"]
    if ptype == "ROman":
        return ["WID", "BLEN", "RAD"]
    if ptype == "Oval":
        return ["WID", "BLEN"]
    if ptype == "ROUnd":
        return ["RAD"]
    return []


def get_dim(res, key):
    t = res["type"]
    if res["kind"] == "poly":
        offs = res["offs"]
        if len(offs) == 8:
            if key == "LEN":
                return offs[2] + offs[6]
            if key == "WID":
                return offs[4] + offs[0]
            if key in ("CUT", "SIZE"):
                return res.get("size")
            if key == "VSIZE":
                return res.get("vsize")
        if key == "LEN":
            return offs[1] + offs[5 if t in ("L", "LAzyl") else 3]
        if key == "WID":
            return offs[2] + offs[0]
        if key == "WINGX":
            return offs[1] + offs[3]
        if key == "WINGY":
            return offs[2] - offs[4]
        if key == "SIZE":
            return res.get("size")
    if res["kind"] == "cap":
        prm = res["prm"]
        if key == "WID":
            return prm["Ty"] - prm["By"]
        if key == "BLEN":
            return prm["Re"] - (prm["Re2"] if res["both"] else prm["Lx"])
        if key == "RAD":
            return prm["r"]
    if res["kind"] == "round" and key == "RAD":
        return res["prm"]["r"]
    return None


def set_dim(res, key, v):
    """A copy of RES with the dimension forced to V and its outline
    rebuilt.  Symmetric dims move both walls, keeping the centre."""
    import copy
    res = copy.deepcopy(res)
    t = res["type"]
    if res["kind"] == "poly":
        offs = res["offs"]
        if len(offs) == 8:
            if key == "LEN":
                d = (v - (offs[2] + offs[6])) / 2.0
                offs[2] += d
                offs[6] += d
            elif key == "WID":
                d = (v - (offs[4] + offs[0])) / 2.0
                offs[4] += d
                offs[0] += d
            elif key in ("CUT", "SIZE"):
                res["size"] = v
            elif key == "VSIZE":
                res["vsize"] = v
            res["offs"] = grec_cuts(offs, res["size"])
        elif key == "LEN":
            j = 5 if t in ("L", "LAzyl") else 3
            d = (v - (offs[1] + offs[j])) / 2.0
            offs[1] += d
            offs[j] += d
            if t == "L":
                offs[3] -= d          # the wing dims ride on Rx
        elif key == "WID":
            d = (v - (offs[2] + offs[0])) / 2.0
            offs[2] += d
            offs[0] += d
            if t == "L":
                offs[4] += d
        elif key == "WINGX":
            offs[3] = v - offs[1]
        elif key == "WINGY":
            offs[4] = offs[2] - v
        elif key == "SIZE":
            res["size"] = v
        res["verts"] = build_polygon(res["dirs"], res["offs"],
                                     res["treat"],
                                     res.get("vsize")
                                     if len(res["offs"]) == 8
                                     else res["size"],
                                     res["which"], res.get("bows"))
        res["segs"] = verts_to_segs(res["verts"])
        return res
    if res["kind"] == "cap":
        prm = res["prm"]
        if key == "WID":
            d = (v - (prm["Ty"] - prm["By"])) / 2.0
            prm["Ty"] += d
            prm["By"] -= d
            if t == "Oval":
                prm["r"] = v / 2.0
                if res["both"]:
                    prm["r2"] = v / 2.0
        elif key == "BLEN":
            if res["both"]:
                d = (v - (prm["Re"] - prm["Re2"])) / 2.0
                prm["Re"] += d
                prm["cx"] += d
                prm["Re2"] -= d
                prm["cx2"] -= d
            else:
                prm["Lx"] = prm["Re"] - v
        elif key == "RAD":
            prm["r"] = v
            if res["both"]:
                prm["r2"] = v
        res["segs"] = endcap_segs(prm, t, res["both"], res.get("bows"))
        return res
    if res["kind"] == "round" and key == "RAD":
        res["prm"]["r"] = v
        res["segs"] = round_segs(res["prm"])
    return res


def on_eps(tol):
    """What counts as ON the outline for this run.  It scales with the
    tolerance (a quarter of it, never below ON_EPS), exactly as ABHD's
    does: if the user accepts 2 inches of error, a point half an inch
    off is plainly still on the wall, and counting it against the
    allowance would spend the whole budget on the first snap."""
    return max(ON_EPS, tol / 4.0)


def snap_ok(before, after, tol, allow, feature):
    """Can the points live with this snap?

    A measured FEATURE - a corner radius, a cut face, an end radius -
    may not grow the worst deviation at all beyond FEAT_SNAP: it is
    what it is.  A DESIGN dimension may spend the allowance: at most
    ALLOW points may end up further than on_eps from the outline, and
    the snap may never push a point past the tolerance that was not
    already there.  That is the percentage answered at step 4 doing
    its job - buying whole-foot dimensions with the points that do not
    object."""
    if feature:
        return held_worst(after, 0) <= held_worst(before, 0) + FEAT_SNAP
    on = on_eps(tol)
    # what matters is what the snap CHANGES, not where the survey noise
    # already sits: a point the snap pushes more than on_eps further
    # off has been spent, and only ALLOW of them may be
    pushed = sum(1 for b, a in zip(before, after) if a > b + on)
    bad_b = sum(1 for d in before if d > tol)
    bad_a = sum(1 for d in after if d > tol)
    return pushed <= allow and bad_a <= bad_b


def snap_result(res, fpts, tol, allow):
    """Snap each headline dimension to the first friendly increment the
    points allow; the free value stays when none do.  Whole dimensions
    may spend the run tolerance, but a measured FEATURE - a corner
    radius, a cut face, a roman end radius - may only grow the worst
    deviation by FEAT_SNAP: an 8-inch as-built corner must not become
    a foot just because the tolerance would absorb it.  On each tier
    the two neighbouring multiples are both tried and the one that
    fits the points better wins."""
    for key in dim_keys(res):
        v = get_dim(res, key)
        if v is None or v <= 0.0:
            continue
        feature = key in FEATURE_KEYS
        spend = 0 if feature else allow
        before = outline_dists(fpts, res["segs"])
        done = False
        for inc in NICE_DIMS:
            if done:
                break
            lo = math.floor(v / inc) * inc
            best_w, best_trial = None, None
            for v2 in (lo, lo + inc):
                if v2 <= 0.0:
                    continue
                trial = set_dim(res, key, v2)
                after = outline_dists(fpts, trial["segs"])
                if not snap_ok(before, after, tol, allow, feature):
                    continue
                w = held_worst(after, spend)
                if best_w is None or w < best_w:
                    best_w, best_trial = w, trial
            if best_trial is not None:
                res = best_trial
                done = True
    return res


def apply_bows(res, fpts):
    """Fit the bows on the placement that already won.  Bows are a
    refinement of the chosen template, never a competitor in the
    search: extra freedom would let a wrong rotation bend its way to a
    good score."""
    if res["kind"] == "poly":
        zone = (CORNER_ZONE if res["treat"] in ("Radius", "Cut")
                else 0.0)
        if res.get("vsize"):
            zone = 1.2 * res["vsize"] * math.tan(math.pi / 8.0) + ZONE_PAD
        elif res.get("size"):
            zone = 1.2 * res["size"] + ZONE_PAD
        offs, bows = fit_wall_bows(fpts, res["dirs"], res["offs"], zone)
        if not any(bows):
            return res
        res = dict(res)
        res["offs"], res["bows"] = offs, bows
        if len(offs) == 8:
            res["size"] = grec_face(offs)
        res["verts"] = build_polygon(
            res["dirs"], offs, res["treat"],
            res.get("vsize") if len(offs) == 8 else res["size"],
            res["which"], bows)
        res["segs"] = verts_to_segs(res["verts"])
        return res
    if res["kind"] == "cap":
        prm, bows = fit_cap_bows(fpts, res["prm"], res["both"])
        if not any(bows):
            return res
        res = dict(res)
        res["prm"], res["bows"] = prm, bows
        res["segs"] = endcap_segs(prm, res["type"], res["both"], bows)
        return res
    return res                              # a round pool has no walls


def fit_and_snap(pts, ptype, treat, tol, pct, bowed):
    """The whole engine: configuration search, the bow refinement when
    the walls may be bowed, then nice-dim snapping against the share of
    the points the user allows beyond the distance."""
    dpts = dedupe(pts)
    allow = fit_ceil(pct * len(dpts))
    res = fit_type(dpts, ptype, treat)
    fpts = (dpts if res["kind"] == "round"
            else to_frame(dpts, res["angle"], res["mirror"]))
    if bowed:
        res = apply_bows(res, fpts)
    res = snap_result(res, fpts, tol, allow)
    res["worst"], res["rms"] = outline_dev(fpts, res["segs"])
    res["allow"] = allow
    if res["kind"] != "round":
        res["fsegs"] = res["segs"]
        res["segs"] = world_segs(res)
    return res

# ---- the standard-hopper bottom --------------------------------------
#
# Mirror of fit:hopper-layout: the bottom is generated, not traced -
# the breaks run dead square across the leg, the hopper is the offset
# rectangle every standard order sheet means, and the slopes are
# straight lines.  Everything happens in the LEG FRAME: x = distance
# into the pool from the deep end wall, y = the cross direction with
# the side walls at s1 < s2.


def hopper_layout(db, sb, s1, s2, so, bo):
    """(named points, lines) of the standard hopper: DB/SB = the two
    break stations, S1/S2 = the side walls, SO/BO = side and back
    offsets.  Lines marked True draw dashed (the deep-break stubs)."""
    w1, w2 = (db, s1), (db, s2)
    h1, h2 = (db, s1 + so), (db, s2 - so)
    b1, b2 = (bo, s1 + so), (bo, s2 - so)
    p1, p2 = (sb, s1), (sb, s2)
    pts = {"W1": w1, "W2": w2, "H1": h1, "H2": h2,
           "B1": b1, "B2": b2, "S1": p1, "S2": p2}
    lines = [(w1, h1, True), (h2, w2, True),      # deep-break stubs
             (h1, h2, False),                     # deep break, solid run
             (h1, b1, False), (b1, b2, False), (b2, h2, False),  # hopper
             (h1, p1, False), (h2, p2, False),    # slope lines
             (p1, p2, False)]                     # shallow break
    return pts, lines


# ---- synthetic surveys -----------------------------------------------


def lcg(seed):
    """Deterministic noise in [-1, 1) - the fixtures must not drift."""
    s = seed
    while True:
        s = (s * 1103515245 + 12345) % 2147483648
        yield (s / 2147483648.0) * 2.0 - 1.0


def arc_len(p1, p2, b):
    if abs(b) < 1.0e-9:
        return dist(p1, p2)
    g = arc_geom(p1, p2, b)
    if g is None:
        return dist(p1, p2)
    c, r, a1, a2 = g
    sweep = norm_ang(a2 - a1) if b > 0 else norm_ang(a1 - a2)
    return r * sweep


def survey(segs, spacing, noise, seed):
    """Shoot the outline the way a crew would: a point roughly every
    SPACING inches, each off the true edge by up to NOISE inches."""
    rng = lcg(seed)
    pts = []
    for p1, p2, b in segs:
        n = max(1, int(round(arc_len(p1, p2, b) / spacing)))
        for k in range(n):
            t = (k + 0.5) / float(n)
            if abs(b) < 1.0e-9:
                p = (p1[0] + (p2[0] - p1[0]) * t,
                     p1[1] + (p2[1] - p1[1]) * t)
                na = ang(p1, p2) + math.pi / 2.0
            else:
                c, r, a1, a2 = arc_geom(p1, p2, b)
                sweep = (norm_ang(a2 - a1) if b > 0
                         else -norm_ang(a1 - a2))
                na = a1 + sweep * t
                p = (c[0] + r * math.cos(na), c[1] + r * math.sin(na))
            e = next(rng) * noise
            pts.append((p[0] + e * math.cos(na), p[1] + e * math.sin(na)))
    return pts


def place(segs, ang_deg, dx, dy):
    """Rotate and shift a frame outline out into world coordinates."""
    a = math.radians(ang_deg)
    out = []
    for p1, p2, b in segs:
        q1, q2 = rot(p1, a), rot(p2, a)
        out.append(((q1[0] + dx, q1[1] + dy),
                    (q2[0] + dx, q2[1] + dy), b))
    return out


def ring_sides(res):
    """The fitted polygon's side lengths, walked around the ring."""
    co = poly_corners(res["dirs"], res["offs"])
    n = len(co)
    return [dist(co[i], co[(i + 1) % n]) for i in range(n)]


def close(a, b, tol=0.75):
    return abs(a - b) <= tol


# ---- the tests -------------------------------------------------------


def test_frame_angle_recovers_rotation():
    segs = place(verts_to_segs(build_polygon(
        RECT_DIRS, [0.0, 300.0, 150.0, 0.0], "Square", None, set())),
        33.0, 40.0, -70.0)
    pts = survey(segs, 20.0, 0.25, seed=2)
    tour = order_points(dedupe(pts))
    a = math.degrees(frame_angle(tour, 4))
    assert min(abs(a - 33.0), abs(a - 33.0 + 90.0),
               abs(a - 33.0 - 90.0)) < 0.5, a
    print("  frame angle recovered: %.2f deg" % a)


def test_rectangle_radius_corners():
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [96.0, 192.0, 96.0, 192.0], "Radius", 24.0,
        set(range(4))))
    pts = survey(place(true, 17.0, 100.0, 50.0), 22.0, 0.35, seed=7)
    res = fit_and_snap(pts, "Rectangle", "Radius", 1.0, MISS_PCT, False)
    assert close(get_dim(res, "LEN"), 384.0, 1e-6), get_dim(res, "LEN")
    assert close(get_dim(res, "WID"), 192.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "SIZE"), 24.0, 1e-6), get_dim(res, "SIZE")
    assert res["worst"] <= 1.0, res["worst"]
    print("  rectangle: 32' x 16', 24\" radius corners, worst %.2f"
          % res["worst"])


def test_rectangle_cut_corners():
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [90.0, 180.0, 90.0, 180.0], "Cut", 30.0,
        set(range(4))))
    pts = survey(place(true, -12.0, 0.0, 0.0), 18.0, 0.3, seed=21)
    res = fit_and_snap(pts, "Rectangle", "Cut", 1.0, MISS_PCT, False)
    assert close(get_dim(res, "LEN"), 360.0, 1e-6), get_dim(res, "LEN")
    assert close(get_dim(res, "WID"), 180.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "SIZE"), 30.0, 1.5), get_dim(res, "SIZE")
    print("  rectangle: 30' x 15', 30\" cut corners, worst %.2f"
          % res["worst"])


def test_rectangle_off_nice_stays_honest():
    # 380" is 4" off a whole foot: the foot and half-foot snaps must be
    # rejected (they would move the walls 2" against a 1" tolerance)
    # and the whole-inch snap kept.
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [84.0, 190.0, 84.0, 190.0], "Square", None, set()))
    pts = survey(place(true, 5.0, 0.0, 0.0), 20.0, 0.2, seed=31)
    res = fit_and_snap(pts, "Rectangle", "Square", 1.0, MISS_PCT, False)
    assert close(get_dim(res, "LEN"), 380.0, 1e-6), get_dim(res, "LEN")
    assert close(get_dim(res, "WID"), 168.0, 1e-6), get_dim(res, "WID")
    print("  the points outrank nice numbers: 380\" stays 380\"")


def test_grecian_cut_face():
    offs = grec_cuts([0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0], 36.0)
    true = verts_to_segs(build_polygon(GREC_DIRS, offs, "Square", None,
                                       set()))
    pts = survey(place(true, 71.0, -50.0, 800.0), 16.0, 0.3, seed=13)
    res = fit_and_snap(pts, "Grecian", "Square", 1.0, MISS_PCT, False)
    assert close(get_dim(res, "LEN"), 350.0, 1e-6), get_dim(res, "LEN")
    assert close(get_dim(res, "WID"), 180.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "CUT"), 36.0, 1e-6), get_dim(res, "CUT")
    print("  grecian: 350 x 180, 36\" corner cuts, worst %.2f"
          % res["worst"])


def test_grecian_rounded_as_built():
    # a nominal grecian is sharp, but an as-built may well ease the
    # eight cut corners - answering Radius measures one shared easing
    offs = grec_cuts([0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0], 36.0)
    true = verts_to_segs(build_polygon(GREC_DIRS, offs, "Radius", 8.0,
                                       set(range(8))))
    pts = survey(place(true, 71.0, -50.0, 800.0), 14.0, 0.3, seed=23)
    res = fit_and_snap(pts, "Grecian", "Radius", 1.0, MISS_PCT, False)
    assert close(get_dim(res, "LEN"), 350.0, 1e-6), get_dim(res, "LEN")
    assert close(get_dim(res, "WID"), 180.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "CUT"), 36.0, 1e-6), get_dim(res, "CUT")
    assert close(get_dim(res, "VSIZE"), 8.0, 1e-6), get_dim(res, "VSIZE")
    assert res["worst"] <= 1.0, res["worst"]
    print("  grecian as-built: 8\" eased cut corners found and held")


def test_grecian_sharp_stays_sharp():
    # answering Radius on a genuinely sharp grecian must not invent an
    # easing: noise is not evidence
    offs = grec_cuts([0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0], 36.0)
    true = verts_to_segs(build_polygon(GREC_DIRS, offs, "Square", None,
                                       set()))
    pts = survey(place(true, 71.0, -50.0, 800.0), 14.0, 0.3, seed=13)
    res = fit_and_snap(pts, "Grecian", "Radius", 1.0, MISS_PCT, False)
    assert get_dim(res, "VSIZE") is None, get_dim(res, "VSIZE")
    assert close(get_dim(res, "CUT"), 36.0, 1e-6), get_dim(res, "CUT")
    print("  a sharp grecian answered Radius stays sharp")


def test_roman_end_is_found():
    prm = {"By": -96.0, "Ty": 96.0, "Lx": 0.0, "cx": 300.0, "r": 120.0,
           "Re": 300.0 + math.sqrt(120.0 ** 2 - 72.0 ** 2)}
    true = endcap_segs(prm, "ROman", False)
    pts = survey(place(true, 197.0, 500.0, 300.0), 22.0, 0.3, seed=11)
    res = fit_and_snap(pts, "ROman", "Square", 1.0, MISS_PCT, False)
    assert not res["both"], "a square end was read as a roman end"
    assert close(get_dim(res, "WID"), 192.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "BLEN"), 396.0, 1e-6), get_dim(res, "BLEN")
    assert close(get_dim(res, "RAD"), 120.0, 6.0), get_dim(res, "RAD")
    p = res["prm"]
    bulge = p["cx"] + p["r"] - p["Re"]
    assert close(bulge, 24.0, 2.0), bulge
    # the roman end must have landed on the end the survey put it on:
    # the fitted apex sits where the true apex was placed
    apex = from_frame((p["cx"] + p["r"],
                       (p["By"] + p["Ty"]) / 2.0),
                      res["angle"], res["mirror"])
    tx = rot((prm["cx"] + prm["r"], 0.0), math.radians(197.0))
    true_apex = (tx[0] + 500.0, tx[1] + 300.0)
    assert dist(apex, true_apex) < 3.0, (apex, true_apex)
    print("  roman: single roman end found on the right end, S %.1f\""
          % bulge)


def test_oval_both_ends():
    prm = {"By": 0.0, "Ty": 168.0, "cx": 300.0, "r": 84.0, "Re": 300.0,
           "cx2": 84.0, "r2": 84.0, "Re2": 84.0}
    true = endcap_segs(prm, "Oval", True)
    pts = survey(place(true, 40.0, -200.0, 100.0), 20.0, 0.3, seed=5)
    res = fit_and_snap(pts, "Oval", "Square", 1.0, MISS_PCT, False)
    assert res["both"], "both radius ends expected"
    assert close(get_dim(res, "WID"), 168.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "BLEN"), 216.0, 1e-6), get_dim(res, "BLEN")
    print("  oval: both 84\" radius ends, straight run %.0f\""
          % get_dim(res, "BLEN"))


def test_true_l():
    true = verts_to_segs(build_polygon(
        L_DIRS, [0.0, 400.0, 200.0, -220.0, 100.0, 0.0], "Radius",
        18.0, set(range(6))))
    pts = survey(place(true, 107.0, 50.0, -400.0), 20.0, 0.3, seed=3)
    res = fit_and_snap(pts, "L", "Radius", 1.0, MISS_PCT, False)
    want = sorted([400.0, 200.0, 180.0, 100.0, 220.0, 100.0])
    got = sorted(ring_sides(res))
    assert all(close(a, b) for a, b in zip(got, want)), got
    assert close(get_dim(res, "SIZE"), 18.0, 1e-6), get_dim(res, "SIZE")
    assert res["worst"] <= 1.0, res["worst"]
    print("  true L: all six sides recovered, 18\" corners")


def test_lazy_l():
    offs = [0.0, 212.13203435596427, 452.1, -116.13203435596427,
            96.0, 0.0]
    true = verts_to_segs(build_polygon(LAZY_DIRS, offs, "Radius", 12.0,
                                       set(range(6))))
    pts = survey(place(true, -23.0, 900.0, 100.0), 18.0, 0.3, seed=9)
    res = fit_and_snap(pts, "LAzyl", "Radius", 1.0, MISS_PCT, False)
    want = sorted([300.0, 240.0, 96.0, 200.18, 260.18, 96.0])
    got = sorted(ring_sides(res))
    assert all(close(a, b, 1.0) for a, b in zip(got, want)), got
    assert close(get_dim(res, "SIZE"), 12.0, 1e-6), get_dim(res, "SIZE")
    assert res["worst"] <= 1.0, res["worst"]
    print("  lazy L: 45-degree bend held, sides and 12\" corners"
          " recovered")


def test_percent_buys_nice_dimensions():
    # 383" is an inch off a whole foot: at the standard 15% the end
    # walls outvote the snap and it stays 383; raise the share of
    # points allowed off and the same survey rounds to 32'-0".
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [84.0, 191.5, 84.0, 191.5], "Square", None, set()))
    pts = survey(place(true, 5.0, 0.0, 0.0), 20.0, 0.2, seed=31)
    tight = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, False)
    loose = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.40, False)
    assert close(get_dim(tight, "LEN"), 383.0, 1e-6), get_dim(tight, "LEN")
    assert close(get_dim(loose, "LEN"), 384.0, 1e-6), get_dim(loose, "LEN")
    assert loose["allow"] > tight["allow"]
    print("  the percent answered buys nice dimensions: 383 or 384,"
          " the user's call")


def test_snap_never_pushes_past_the_tolerance():
    dists = [0.1, 0.2, 0.9]
    assert snap_ok(dists, [0.1, 0.2, 0.95], 1.0, 3, False)
    # a snap that shoves a point beyond the distance is refused however
    # generous the allowance
    assert not snap_ok(dists, [0.1, 0.2, 1.4], 1.0, 99, False)
    # and the allowance caps how many points a snap may push off
    assert snap_ok(dists, [0.6, 0.7, 0.9], 1.0, 2, False)
    assert not snap_ok(dists, [0.6, 0.7, 0.9], 1.0, 1, False)
    # a measured feature spends no allowance at all: it may only grow
    # the worst deviation by FEAT_SNAP, however many points agree
    assert snap_ok(dists, [0.1, 0.2, 0.95], 1.0, 0, True)
    assert not snap_ok(dists, [0.1, 0.2, 1.2], 1.0, 99, True)
    print("  a snap may spend the allowance, never the tolerance")


def test_bowed_walls_are_found():
    # a 32' x 16' rectangle whose two long walls bow 3" out - the wall
    # a field crew would call straight and a laser calls R 205'
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [96.0, 192.0, 96.0, 192.0], "Square", None, set(),
        [3.0, 0.0, 3.0, 0.0]))
    pts = survey(place(true, 17.0, 100.0, 50.0), 18.0, 0.25, seed=41)
    straight = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, False)
    bowed = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, True)
    # held straight, the fit is dragged out by the bulging middles
    assert straight["worst"] > 1.5, straight["worst"]
    assert close(get_dim(straight, "WID"), 196.0, 1e-6)
    # allowed to bow, it recovers the true body and both bows
    assert close(get_dim(bowed, "LEN"), 384.0, 1e-6), get_dim(bowed, "LEN")
    assert close(get_dim(bowed, "WID"), 192.0, 1e-6), get_dim(bowed, "WID")
    assert bowed["worst"] < 0.5, bowed["worst"]
    got = sorted(abs(b) for b in bowed["bows"])
    assert got[0] == got[1] == 0.0 and all(close(b, 3.0, 0.3)
                                          for b in got[2:]), got
    print("  bowed walls: 3\" bows found, the body comes out true")


def test_a_straight_wall_stays_straight():
    # answering Yes on a genuinely straight pool must not invent bows
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [96.0, 192.0, 96.0, 192.0], "Radius", 24.0,
        set(range(4))))
    pts = survey(place(true, 17.0, 100.0, 50.0), 22.0, 0.35, seed=7)
    res = fit_and_snap(pts, "Rectangle", "Radius", 1.0, 0.15, True)
    assert not res.get("bows"), res.get("bows")
    assert close(get_dim(res, "LEN"), 384.0, 1e-6)
    assert close(get_dim(res, "SIZE"), 24.0, 1e-6)
    print("  a straight wall answered Yes stays straight")


def test_bow_never_moves_a_corner():
    # the bow vanishes at both ends by construction, so every design
    # dimension taken between corners survives it untouched
    offs = [96.0, 192.0, 96.0, 192.0]
    sharp = poly_corners(RECT_DIRS, offs)
    verts = build_polygon(RECT_DIRS, offs, "Square", None, set(),
                          [3.0, -2.0, 0.0, 1.5])
    assert [v[0] for v in verts] == sharp, "a bow moved a corner"
    # and the bow is exactly as deep as it was fitted, on the outside
    segs = verts_to_segs(verts)
    mid = ((sharp[0][0] + sharp[1][0]) / 2.0,
           (sharp[0][1] + sharp[1][1]) / 2.0)
    out = (mid[0], mid[1] - 3.0)            # wall 0 runs +x, outward -y
    assert seg_dist(out, segs[0]) < 1.0e-6, seg_dist(out, segs[0])
    print("  a bow bulges the wall and leaves the corners alone")


def test_oval_side_walls_bow():
    prm = {"By": 0.0, "Ty": 168.0, "cx": 300.0, "r": 84.0, "Re": 300.0,
           "cx2": 84.0, "r2": 84.0, "Re2": 84.0}
    true = endcap_segs(prm, "Oval", True, [2.0, 2.0])
    pts = survey(place(true, 40.0, -200.0, 100.0), 16.0, 0.25, seed=5)
    straight = fit_and_snap(pts, "Oval", "Square", 1.0, 0.15, False)
    bowed = fit_and_snap(pts, "Oval", "Square", 1.0, 0.15, True)
    assert straight["worst"] > 1.5, straight["worst"]
    assert close(get_dim(bowed, "WID"), 168.0, 1e-6), get_dim(bowed, "WID")
    assert close(get_dim(bowed, "BLEN"), 216.0, 1e-6)
    assert all(close(b, 2.0, 0.4) for b in bowed["bows"]), bowed["bows"]
    assert bowed["worst"] < 0.6, bowed["worst"]
    print("  an oval's side walls bow too, its ends left alone")


def test_round():
    c = (77.0, -33.0)
    true = [((c[0] + 108.0, c[1]), (c[0] - 108.0, c[1]), 1.0),
            ((c[0] - 108.0, c[1]), (c[0] + 108.0, c[1]), 1.0)]
    pts = survey(true, 20.0, 0.3, seed=17)
    res = fit_and_snap(pts, "ROUnd", "Square", 1.0, MISS_PCT, False)
    assert close(get_dim(res, "RAD"), 108.0, 1e-6), get_dim(res, "RAD")
    assert dist((res["prm"]["cx"], res["prm"]["cy"]), c) < 0.5
    print("  round: 18' spa, centre within half an inch")


def test_bowtie_configs_are_rejected():
    # a reversed edge means the template collapsed; such a fit can
    # still hug the points, so validity has to be checked explicitly
    assert poly_valid(RECT_DIRS, [0.0, 300.0, 150.0, 0.0])
    assert not poly_valid(RECT_DIRS, [0.0, -10.0, 150.0, 0.0])
    assert not poly_valid(L_DIRS, [0.0, 400.0, 200.0, -220.0,
                                   220.0, 0.0])
    print("  collapsed template placements are rejected")


def test_hopper_layout():
    pts, lines = hopper_layout(96.0, 240.0, 0.0, 192.0, 18.0, 24.0)
    # the deep break is three collinear pieces spanning wall to wall
    assert pts["W1"] == (96.0, 0.0) and pts["W2"] == (96.0, 192.0)
    assert pts["H1"] == (96.0, 18.0) and pts["H2"] == (96.0, 174.0)
    stubs = [ln for ln in lines if ln[2]]
    assert len(stubs) == 2
    k = dist(*stubs[0][:2])
    m = dist(*stubs[1][:2])
    span = dist(pts["H1"], pts["H2"])
    assert k == m == 18.0 and k + m + span == 192.0
    # the hopper's back edge sits at the back offset off the deep wall
    assert pts["B1"][0] == pts["B2"][0] == 24.0
    # the slopes run straight to the shallow break's wall ends
    assert (pts["H1"], pts["S1"], False) in lines
    assert (pts["H2"], pts["S2"], False) in lines
    print("  standard hopper: K/L/M spans the width, back at its"
          " offset")


def test_lisp_engine_matches_mirror():
    """Load the real FITABHD.lsp into the pure-Python AutoLISP VM and
    run the fitting engine on the fixtures - the transcription and this
    mirror must agree to floating-point noise.  CALOFIN_LISP_ROOT=shared
    reruns this against the grouped build."""
    from lispvm import VM

    def vmfit(pts, ptype, treat, pct=MISS_PCT, bowed=False):
        vm = VM()
        vm.load(LISP_FILE)
        lst = "(list " + " ".join("(list %r %r)" % (p[0], p[1])
                                  for p in pts) + ")"
        vm.loads('(setq fit-test-res (fit:fit-and-snap %s "%s" "%s" '
                 '1.0 %r %s))'
                 % (lst, ptype, treat, pct, "T" if bowed else "nil"))
        return vm

    # rectangle with radius corners
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [96.0, 192.0, 96.0, 192.0], "Radius", 24.0,
        set(range(4))))
    pts = survey(place(true, 17.0, 100.0, 50.0), 22.0, 0.35, seed=7)
    py = fit_and_snap(pts, "Rectangle", "Radius", 1.0, MISS_PCT, False)
    vm = vmfit(pts, "Rectangle", "Radius")
    for key in ("LEN", "WID", "SIZE"):
        lv = vm.loads("(fit:get-dim fit-test-res '%s)" % key)
        assert abs(lv - get_dim(py, key)) < 1.0e-6, (key, lv)
    lv = vm.loads("(fit:rget fit-test-res 'worst)")
    assert abs(lv - py["worst"]) < 1.0e-6, lv

    # single roman end
    prm = {"By": -96.0, "Ty": 96.0, "Lx": 0.0, "cx": 300.0, "r": 120.0,
           "Re": 300.0 + math.sqrt(120.0 ** 2 - 72.0 ** 2)}
    pts = survey(place(endcap_segs(prm, "ROman", False),
                       197.0, 500.0, 300.0), 22.0, 0.3, seed=11)
    py = fit_and_snap(pts, "ROman", "Square", 1.0, MISS_PCT, False)
    vm = vmfit(pts, "ROman", "Square")
    assert vm.loads("(fit:rget fit-test-res 'both)") is None
    for key in ("WID", "BLEN", "RAD"):
        lv = vm.loads("(fit:get-dim fit-test-res '%s)" % key)
        assert abs(lv - get_dim(py, key)) < 1.0e-6, (key, lv)

    # lazy L - the heaviest search (16 placements, 8-fold frame)
    offs = [0.0, 212.13203435596427, 452.1, -116.13203435596427,
            96.0, 0.0]
    true = verts_to_segs(build_polygon(LAZY_DIRS, offs, "Radius", 12.0,
                                       set(range(6))))
    pts = survey(place(true, -23.0, 900.0, 100.0), 18.0, 0.3, seed=9)
    py = fit_and_snap(pts, "LAzyl", "Radius", 1.0, MISS_PCT, False)
    vm = vmfit(pts, "LAzyl", "Radius")
    lv = vm.loads("(fit:get-dim fit-test-res 'SIZE)")
    assert abs(lv - get_dim(py, "SIZE")) < 1.0e-6, lv
    lv = vm.loads("(fit:rget fit-test-res 'worst)")
    assert abs(lv - py["worst"]) < 1.0e-6, lv

    # a grecian with eased as-built corners - the vertex-easing path
    offs = grec_cuts([0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0], 36.0)
    true = verts_to_segs(build_polygon(GREC_DIRS, offs, "Radius", 8.0,
                                       set(range(8))))
    pts = survey(place(true, 71.0, -50.0, 800.0), 14.0, 0.3, seed=23)
    py = fit_and_snap(pts, "Grecian", "Radius", 1.0, MISS_PCT, False)
    vm = vmfit(pts, "Grecian", "Radius")
    for key in ("LEN", "WID", "CUT", "VSIZE"):
        lv = vm.loads("(fit:get-dim fit-test-res '%s)" % key)
        assert abs(lv - get_dim(py, key)) < 1.0e-6, (key, lv)

    # bowed walls - the whole bow pass through the real .lsp
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [96.0, 192.0, 96.0, 192.0], "Square", None, set(),
        [3.0, 0.0, 3.0, 0.0]))
    pts = survey(place(true, 17.0, 100.0, 50.0), 18.0, 0.25, seed=41)
    py = fit_and_snap(pts, "Rectangle", "Square", 1.0, MISS_PCT, True)
    vm = vmfit(pts, "Rectangle", "Square", MISS_PCT, True)
    for key in ("LEN", "WID"):
        lv = vm.loads("(fit:get-dim fit-test-res '%s)" % key)
        assert abs(lv - get_dim(py, key)) < 1.0e-6, (key, lv)
    lb = vm.loads("(fit:rget fit-test-res 'bows)")
    assert lb and len(lb) == 4, lb
    for a, b in zip(lb, py["bows"]):
        assert abs(a - b) < 1.0e-6, (lb, py["bows"])

    # and the percent knob, which only the LISP's own allowance can show
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [84.0, 191.5, 84.0, 191.5], "Square", None, set()))
    pts = survey(place(true, 5.0, 0.0, 0.0), 20.0, 0.2, seed=31)
    for pct in (0.15, 0.40):
        py = fit_and_snap(pts, "Rectangle", "Square", 1.0, pct, False)
        vm = vmfit(pts, "Rectangle", "Square", pct, False)
        lv = vm.loads("(fit:get-dim fit-test-res 'LEN)")
        assert abs(lv - get_dim(py, "LEN")) < 1.0e-6, (pct, lv)
        assert vm.loads("(fit:rget fit-test-res 'allow)") == py["allow"]

    # the standard-hopper layout, straight out of the LISP
    lay = vm.loads("(fit:hopper-layout 96.0 240.0 0.0 192.0 18.0 24.0)")
    pts_l, lines = lay
    assert pts_l[2] == [96.0, 18.0] and pts_l[3] == [96.0, 174.0]
    assert len([ln for ln in lines if ln[2]]) == 2
    print("  the LISP engine agrees with this mirror in the VM")


def test_the_questions_run_and_step_back():
    """Drive fit:ask-settings in the VM: the five questions, and Back
    re-opening the previous one with the answers already given as its
    defaults."""
    from lispvm import VM
    vm = VM()
    vm.load(LISP_FILE)
    vm.script = ["Rectangle", "Radius", 1.5, 25, "Yes"]
    vm.prompts = []
    got = vm.loads('(fit:ask-settings (list "Rectangle" "Square" 1.0'
                   ' 0.15 nil) 6)')
    assert got[0] == "Rectangle" and got[1] == "Radius"
    assert abs(got[2] - 1.5) < 1e-9 and abs(got[3] - 0.25) < 1e-9
    assert got[4] and not vm.script, (got, vm.script)
    asked = " ".join(p for p, _ in vm.prompts)
    for want in ("Step 1 of 6", "Percent of points allowed beyond",
                 "Any bowed walls?"):
        assert want in asked, want

    # Back steps back exactly one question, every time
    vm = VM()
    vm.load(LISP_FILE)
    vm.script = ["Grecian", "Cut", "Back", "Radius", 2.0, "Back",
                 2.0, 40, "Back", 55, "No"]
    vm.prompts = []
    got = vm.loads('(fit:ask-settings (list "Rectangle" "Square" 1.0'
                   ' 0.15 nil) 5)')
    assert got[0] == "Grecian" and got[1] == "Radius"
    assert abs(got[2] - 2.0) < 1e-9 and abs(got[3] - 0.55) < 1e-9
    assert got[4] is None and not vm.script, (got, vm.script)
    # the way back offers what was already answered
    assert any("<40>" in p for p, _ in vm.prompts), \
        "the percent question did not offer the previous answer"
    # a round pool is never asked about bowed walls
    vm = VM()
    vm.load(LISP_FILE)
    vm.script = ["ROUnd", 1.0, None]
    vm.prompts = []
    got = vm.loads('(fit:ask-settings (list "ROUnd" "Square" 1.0 0.15'
                   ' nil) 5)')
    assert got[4] is None and not vm.script
    assert not any("bowed" in p for p, _ in vm.prompts)
    print("  the questions run, and Back re-opens the last one")


def test_leaving_points_out_toggles():
    """Every pick in the Redo omit loop toggles: a point in the fit
    goes out, a ringed one comes back in."""
    from lispvm import VM
    vm = VM()
    vm.load(LISP_FILE)
    vm.loads("(setq fit-pts (list (list 0.0 0.0) (list 100.0 0.0)"
             " (list 100.0 50.0)) fit-omit nil)")
    assert len(vm.loads("(fit:active)")) == 3
    pick = vm.loads("(fit:omit-choose (list 98.0 3.0))")
    assert pick[0] == "omit" and pick[1:] == [100.0, 0.0], pick
    # set it aside, and the fit no longer sees it
    vm.loads("(setq fit-omit (list (list (list 100.0 0.0) nil)))")
    assert len(vm.loads("(fit:active)")) == 2
    assert vm.loads("(fit:omitted-p (list 100.0 0.0))")
    # the same pick now restores it
    pick = vm.loads("(fit:omit-choose (list 98.0 3.0))")
    assert pick[0] == "restore" and pick[1:] == [100.0, 0.0], pick
    # while a pick elsewhere still omits
    pick = vm.loads("(fit:omit-choose (list 2.0 2.0))")
    assert pick[0] == "omit" and pick[1:] == [0.0, 0.0], pick
    vm.loads("(setq fit-omit (fit:omit-drop (list 100.0 0.0)))")
    assert len(vm.loads("(fit:active)")) == 3
    assert vm.loads("fit-omit") is None
    print("  points can be left out of a Redo, and put back")


def paren_depth(src):
    depth = 0
    in_str = in_comment = esc = False
    for ch in src:
        if in_comment:
            if ch == "\n":
                in_comment = False
        elif in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == ";":
            in_comment = True
        elif ch == '"':
            in_str = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                raise AssertionError(
                    "FITABHD.lsp closes a paren that never opened")
    return depth


def test_lisp_file_is_well_formed():
    """Catch unbalanced parentheses before AutoCAD does."""
    src = open(LISP_FILE).read()
    depth = paren_depth(src)
    assert depth == 0, "FITABHD.lsp has %d unclosed paren(s)" % depth
    defined = set(re.findall(r"\(defun\s+((?:fit:|c:)[^\s(]+)", src))
    called = set(re.findall(r"\((fit:[a-z0-9*+-]+)", src))
    missing = called - defined
    assert not missing, "FITABHD.lsp calls undefined: %s" % sorted(missing)
    dead = {d for d in defined - called if not d.startswith("c:")}
    assert not dead, "FITABHD.lsp defines but never calls: %s" % sorted(dead)
    assert "c:FITABHD" in defined, "c:FITABHD is gone"
    assert "c:FITABHDVER" in defined, "c:FITABHDVER is gone"
    for fn in ("fit:order-points", "fit:frame-angle", "fit:to-frame",
               "fit:poly-corners", "fit:poly-valid", "fit:assign-walls",
               "fit:fit-polygon", "fit:corner-frame", "fit:corner-err",
               "fit:fit-corner-radius", "fit:fit-corner-cut",
               "fit:corner-verts", "fit:build-polygon",
               "fit:fit-polytype", "fit:grec-face", "fit:grec-cuts",
               "fit:fit-vertex-feature",
               "fit:endcap-h", "fit:endcap-verts", "fit:fit-endcap",
               "fit:fit-round", "fit:configs-for", "fit:fit-type",
               "fit:get-dim", "fit:set-dim", "fit:snap-result",
               "fit:fit-and-snap", "fit:outline-dev", "fit:seg-dist",
               "fit:hopper-layout", "fit:gather", "fit:report",
               "fit:fit-wall-bow", "fit:fit-wall-bows", "fit:keep-bow",
               "fit:bow-bulge", "fit:fit-cap-bows", "fit:apply-bows",
               "fit:held-worst", "fit:snap-ok", "fit:on-eps",
               "fit:ask-settings", "fit:omit-choose", "fit:omit-loop",
               "fit:active", "fit:bow-lines",
               "fit:make-pline", "fit:ensure-layer", "fit:askkw",
               "fit:asktreat", "fit:tag-mine", "fit:purge-mine",
               "fit:bottom"):
        assert fn in defined, "FITABHD.lsp no longer defines %s" % fn
    # the shared twin exists and defines the same commands
    shared = open(SHARED_FILE).read()
    assert "c:FITABHD" in shared and "c:FITABHDVER" in shared
    assert not re.search(r"^\(defun\s+cal:", shared, re.M), \
        "the shared twin must not define cal: symbols"
    print("  FITABHD.lsp is balanced and self-consistent")


def test_versioned_copy():
    """FITABHD.lsp uses the auto-stamped release convention: its
    banner matches release_lisp.py's regex, and the dated twin under
    releases/ is byte-identical with a REV that matches the banner."""
    src = open(LISP_FILE, "rb").read()
    m = re.search(rb'\*[a-z]+-version\*\s+"v(\d+)\.(\d+)"', src)
    assert m, ("FITABHD.lsp lost its *fitabhd-version* banner - "
               "release_lisp.py would silently skip it")
    rev = (m.group(1) + m.group(2)).decode()
    twins = [f for f in os.listdir(RELEASES_DIR)
             if re.match(r"FITABHD_\d{6}_REV\d+\.lsp$", f)]
    assert len(twins) == 1, \
        "expected exactly one FITABHD_MMDDYY_REV#.lsp - run " \
        "python3 tools/release_lisp.py (found %s)" % twins
    twin = twins[0]
    assert twin.endswith("_REV%s.lsp" % rev), \
        "twin %s does not carry the banner's REV%s" % (twin, rev)
    assert open(os.path.join(RELEASES_DIR, twin), "rb").read() == src, \
        "%s has drifted - re-run tools/release_lisp.py" % twin
    print("  versioned twin %s matches FITABHD.lsp" % twin)


def test_constants_match_lisp():
    """The LISP and this mirror must stay in step."""
    src = open(LISP_FILE).read()

    def setq_value(name):
        m = re.search(r"\(setq\s+fit:\*%s\*\s+([^)\n;]+)" % name, src)
        assert m, "could not find fit:*%s* in FITABHD.lsp" % name
        return m.group(1).strip()

    assert float(setq_value("on-eps")) == ON_EPS
    assert float(setq_value("tol-max")) == TOL_MAX
    assert float(setq_value("corner-zone")) == CORNER_ZONE
    assert float(setq_value("zone-pad")) == ZONE_PAD
    assert float(setq_value("snap-eps")) == SNAP_EPS
    assert float(setq_value("rad-max")) == RAD_MAX
    assert float(setq_value("both-edge")) == BOTH_EDGE
    assert float(setq_value("vsize-min")) == VSIZE_MIN
    assert float(setq_value("feat-snap")) == FEAT_SNAP
    assert float(setq_value("miss-pct")) == MISS_PCT
    assert float(setq_value("bow-min")) == BOW_MIN
    assert float(setq_value("bow-max")) == BOW_MAX
    assert float(setq_value("bow-max-frac")) == BOW_MAX_FRAC
    assert int(setq_value("bow-pts-min")) == BOW_PTS_MIN
    assert int(setq_value("icp-iters")) == ICP_ITERS
    m = re.search(r"\(setq\s+fit:\*rad-turn-min\*\s+\(/\s+pi\s+([0-9.]+)\)",
                  src)
    assert m and abs(math.pi / float(m.group(1)) - RAD_TURN_MIN) < 1e-12
    m = re.search(r"\(setq\s+fit:\*nice-dims\*\s+'\(([^)]*)\)", src)
    assert m, "could not read fit:*nice-dims*"
    assert tuple(float(x) for x in m.group(1).split()) == NICE_DIMS
    # the type keywords stay POOL's vocabulary, and the Treatment
    # question keeps the canonical set (STANDARDS.md section 2)
    assert '"Rectangle Grecian ROman Oval L LAzyl ROUnd"' in src, \
        "the pool-type keyword set moved or was renamed"
    assert '"Square Radius Cut NotGiven NG 90 ROUNDED DIAG DIAGONAL"' \
        in src, "the Treatment keyword set is no longer canonical"
    print("  constants match FITABHD.lsp")


def main():
    print("FITABHD typed-fit tests")
    test_lisp_file_is_well_formed()
    test_versioned_copy()
    test_constants_match_lisp()
    test_frame_angle_recovers_rotation()
    test_bowtie_configs_are_rejected()
    test_rectangle_radius_corners()
    test_rectangle_cut_corners()
    test_rectangle_off_nice_stays_honest()
    test_grecian_cut_face()
    test_grecian_rounded_as_built()
    test_grecian_sharp_stays_sharp()
    test_roman_end_is_found()
    test_oval_both_ends()
    test_true_l()
    test_lazy_l()
    test_round()
    test_percent_buys_nice_dimensions()
    test_snap_never_pushes_past_the_tolerance()
    test_bowed_walls_are_found()
    test_a_straight_wall_stays_straight()
    test_bow_never_moves_a_corner()
    test_oval_side_walls_bow()
    test_hopper_layout()
    test_lisp_engine_matches_mirror()
    test_the_questions_run_and_step_back()
    test_leaving_points_out_toggles()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
