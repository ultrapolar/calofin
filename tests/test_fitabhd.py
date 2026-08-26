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
OOS_MAX = math.pi / 36.0           # fit:*oos-max*  (5 degrees: a wall
                                   # swung further than this is not the
                                   # template's wall any more)
CAP_OOS_MAX = math.pi / 18.0       # fit:*cap-oos-max*  (10 degrees: how
                                   # far a Roman or Oval side wall may
                                   # lean, and how far the two may
                                   # diverge - an arc-ended shell slumps
                                   # as it cures and the walls slant
                                   # away, so they are never held
                                   # parallel)
ARC_PTS_MIN = 3                    # fit:*arc-pts-min*  (points each arc
                                   # of a run needs to mean anything -
                                   # and so the only limit on how many
                                   # arcs a curve may become: N points
                                   # on it allow at most N/3 arcs, with
                                   # no fixed ceiling)
TANG_TOL = math.pi / 22.5          # fit:*tang-tol*  (8 degrees: ABHD's
                                   # own tangency window - how far a
                                   # joint in a run of arcs may depart
                                   # from smooth)
TANG_STEPS = (1.0, 1.25, 1.5)      # fit:*tang-steps*  (stretch the
                                   # window rather than abandon it)
OOS_MIN = 1.0                      # fit:*oos-min*  (the drift from one
                                   # end of a wall to the other, below
                                   # which the wall reads as true)
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


def solve_lin(m, rhs):
    """Small Gauss-Jordan with partial pivoting; None when singular."""
    n = len(rhs)
    aug = [list(m[i]) + [rhs[i]] for i in range(n)]
    for c in range(n):
        piv = c
        for r in range(c, n):
            if abs(aug[r][c]) > abs(aug[piv][c]):
                piv = r
        if abs(aug[piv][c]) < 1.0e-12:
            return None
        aug[c], aug[piv] = aug[piv], aug[c]
        d = aug[c][c]
        aug[c] = [v / d for v in aug[c]]
        for r in range(n):
            if r != c:
                f = aug[r][c]
                if f != 0.0:
                    aug[r] = [v - f * w for v, w in zip(aug[r], aug[c])]
    return [aug[i][n] for i in range(n)]


def fit_wall_line(wpts, a, b, want_swing, want_bow):
    """Least-squares wall through its own points, in the wall's own
    frame (t along the chord A->B, y outward).

        y = A + B*t + C*4t(1-t)

    A is where the wall sits, B how far it DRIFTS from one end to the
    other - the wall swinging off the template direction, which is what
    an out-of-square pool is made of - and C how far it BOWS at
    mid-wall.  Terms not asked for are held at zero and left out of the
    solve.  Returns (A B C), or None when the wall has too few points
    to tell any of it from noise."""
    c = dist(a, b)
    if c < 1.0e-9:
        return None
    use = [0] + ([1] if want_swing else []) + ([2] if want_bow else [])
    if len(wpts) < max(BOW_PTS_MIN, len(use) + 1):
        return None
    ux, uy = (b[0] - a[0]) / c, (b[1] - a[1]) / c
    nx, ny = uy, -ux                       # right of travel = outward
    k = len(use)
    m = [[0.0] * k for _ in range(k)]
    rhs = [0.0] * k
    for p in wpts:
        dx, dy = p[0] - a[0], p[1] - a[1]
        t = (dx * ux + dy * uy) / c
        f = (1.0, t, 4.0 * t * (1.0 - t))
        y = dx * nx + dy * ny
        for i in range(k):
            rhs[i] += f[use[i]] * y
            for j in range(k):
                m[i][j] += f[use[i]] * f[use[j]]
    got = solve_lin(m, rhs)
    if got is None:
        return None
    out = [0.0, 0.0, 0.0]
    for i in range(k):
        out[use[i]] = got[i]
    return out


def swung_wall(a, b, d, coef):
    """The wall line A->B (template direction D) after its fitted
    offset and drift are applied: (new direction, new outward offset).
    The drift is a rotation, so the wall stays a straight line - the
    pool goes out of square, it does not go crooked."""
    c = dist(a, b)
    ux, uy = (b[0] - a[0]) / c, (b[1] - a[1]) / c
    nx, ny = uy, -ux
    d2 = d - math.atan2(coef[1], c)        # drift B over chord c
    q = (a[0] + nx * coef[0], a[1] + ny * coef[0])   # a point on it
    n2 = wall_normal(d2)
    return d2, n2[0] * q[0] + n2[1] * q[1]


def wall_rms(wpts, a, b, bulge):
    if not wpts:
        return 0.0
    return outline_dev(wpts, [(a, b, bulge)])[1]


def refine_walls(pts, dirs, offs, zone, oos, bowed):
    """Let every wall answer to its own points.

    The template fixed each wall's DIRECTION, which is what makes the
    type mean anything - but a real as-built is never true, and holding
    a rectangle perfectly square just pushes the error into the points.
    So each wall is refitted here: its offset always, its direction when
    the pool may be out of square, its bow when the walls may be bowed.
    Each of those is then kept only where the points prove it, so a pool
    that really is square comes out square.

    Returns (dirs, offs, bows)."""
    n = len(dirs)
    base = list(dirs)
    dirs, offs = list(dirs), list(offs)
    coefs = [None] * n
    for _ in range(3):
        wallpts, _ = assign_walls(pts, dirs, offs, zone)
        corners = poly_corners(dirs, offs)
        if corners is None:
            return base, offs, None
        nd, no = list(dirs), list(offs)
        for i in range(n):
            a, b = corners[i], corners[(i + 1) % n]
            got = fit_wall_line(wallpts[i], a, b, oos, bowed)
            if got is None:
                continue
            coefs[i] = got
            d2, o2 = swung_wall(a, b, dirs[i], got)
            if abs(signed_dang(base[i], d2)) <= OOS_MAX:
                nd[i], no[i] = d2, o2
            else:
                no[i] = offs[i] + got[0]
        if n == 8:
            # the cut corners are not free walls: each bisects its own
            # corner and all four share one face, however the axis
            # walls have swung
            nd, no = grec_cuts(nd, no, grec_face(nd, no))
        if poly_valid(nd, no):
            dirs, offs = nd, no
    # ---- what did the points actually earn? --------------------------
    wallpts, _ = assign_walls(pts, dirs, offs, zone)
    corners = poly_corners(dirs, offs)
    if corners is None:
        return base, offs, None
    bows = [0.0] * n
    for i in range(n):
        wpts = wallpts[i]
        a, b = corners[i], corners[(i + 1) % n]
        # the drift the TOTAL swing represents, end to end, in inches -
        # not the residual the last pass measured, which is near zero
        # once the wall has already been swung onto its points
        swing = signed_dang(base[i], dirs[i])
        drift = abs(math.tan(swing)) * dist(a, b)
        if n == 8 and i % 2 == 1:
            swing = 0.0                     # a derived cut wall
        if abs(swing) > 1.0e-9:
            # measure this wall both ways: swung as fitted, and held to
            # the template direction at its own best offset
            nrm = wall_normal(base[i])
            flat = (sum(nrm[0] * p[0] + nrm[1] * p[1] for p in wpts)
                    / len(wpts)) if wpts else offs[i]
            keep = (drift >= OOS_MIN and wpts
                    and wall_rms(wpts, a, b, 0.0)
                    <= flat_rms(wpts, base[i], flat) * BOTH_EDGE)
            if not keep:
                dirs[i], offs[i] = base[i], flat
        if bowed and coefs[i]:
            bows[i] = keep_bow(wpts, a, b,
                               bow_cap(coefs[i][2], dist(a, b)))
    if n == 8:
        dirs, offs = grec_cuts(dirs, offs, grec_face(dirs, offs))
    if not poly_valid(dirs, offs):
        return base, offs, None
    return dirs, offs, (bows if any(bows) else None)


def flat_rms(wpts, d, off):
    """RMS of the points about the straight line with direction D at
    outward offset OFF - the wall as the template would hold it."""
    nrm = wall_normal(d)
    if not wpts:
        return 0.0
    return math.sqrt(sum((nrm[0] * p[0] + nrm[1] * p[1] - off) ** 2
                         for p in wpts) / len(wpts))


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


def wall_y(prm, side, x):
    """A cap body's side wall at X.  The template holds the two walls
    parallel; once the pool is allowed out of square each carries its
    own slope, and By/Ty are its height at the body's middle."""
    if side == "b":
        return prm["By"] + prm.get("sb", 0.0) * (x - prm.get("xm", 0.0))
    return prm["Ty"] + prm.get("st", 0.0) * (x - prm.get("xm", 0.0))


def cap_cy(prm, x):
    """The body's centreline at X - level on a true pool, tilted on one
    built wider at one end."""
    return (wall_y(prm, "b", x) + wall_y(prm, "t", x)) / 2.0


def cap_half(prm, x):
    """Half the body's width at X."""
    return (wall_y(prm, "t", x) - wall_y(prm, "b", x)) / 2.0


def cap_wall(wpts):
    """A side wall's own least-squares line through the points that
    chose it, as (base, mid, slope)."""
    n = len(wpts)
    mid = sum(p[0] for p in wpts) / n
    base = sum(p[1] for p in wpts) / n
    num = sum((p[0] - mid) * p[1] for p in wpts)
    den = sum((p[0] - mid) ** 2 for p in wpts)
    return base, mid, (num / den if den > 1.0e-9 else 0.0)


def cap_slopes(sb, st):
    """The angles the two side walls of an arc-ended body may really
    take.  They are not held parallel: a gunite shell slumps as it
    cures, so one wall very often slants away from the other, and
    forcing them parallel would push that lean back into the points.
    Two limits, both CAP_OOS_MAX: how far one wall may lean, and how
    far the two may diverge from each other.  Past either the offender
    is CLAMPED, never zeroed."""
    m = CAP_OOS_MAX
    ab = max(-m, min(m, math.atan(sb)))
    at = max(-m, min(m, math.atan(st)))
    dv = at - ab
    if abs(dv) > m:
        mid = (ab + at) / 2.0
        dv = m if dv > 0.0 else -m
        ab, at = mid - dv / 2.0, mid + dv / 2.0
    return math.tan(ab), math.tan(at)


def cap_divergence(prm):
    """How far off parallel the two side walls came out, in radians."""
    return math.atan(prm.get("st", 0.0)) - math.atan(prm.get("sb", 0.0))


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
        got = fit_wall_line(wpts, a, b, False, True)
        if got is None:
            continue
        shift, s = got[0], bow_cap(got[2], dist(a, b))
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


def endcap_segs(prm, kind, both, bows=None, chains=None):
    """Outline segments of the fitted end-capped body, frame coords.
    prm = dict with By Ty Lx Re cx r (and Re2 cx2 r2 when BOTH).
    CHAINS, when given, is (right left): each end's single arc replaced
    by a run of arcs that follows the points."""
    verts = []

    def cap(re, cx, r, sign, chain=None):
        """Vertex run for one end cap; SIGN +1 = the +x end (walked
        bottom to top), -1 = the -x end (walked top to bottom).  The
        end line runs between the side walls AT THIS END, so a pool
        wider at one end still closes on both."""
        by = wall_y(prm, "b", re)
        ty = wall_y(prm, "t", re)
        cy = (by + ty) / 2.0
        h = endcap_h(re, cx, cy, r, by, ty)
        stub = (ty - by) / 2.0 - h > 0.25
        out = []
        if sign > 0:
            lo, hi = (re, cy - h), (re, cy + h)
            a1, a2 = ang((cx, cy), lo), ang((cx, cy), hi)
            b = math.tan(norm_ang(a2 - a1) / 4.0)
            if stub:
                out.append(((re, by), 0.0))
            out.extend(chain if chain else [(lo, b)])
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
            out.extend(chain if chain else [(hi, b)])
            if stub:
                out.append((lo, 0.0))
                out.append(((re, by), 0.0))
            else:
                out.append((lo, 0.0))
        return out

    verts.extend(cap(prm["Re"], prm["cx"], prm["r"], +1,
                     chains[0] if chains else None))
    itop = len(verts) - 1                  # the TOP wall leaves here
    if both:
        verts.extend(cap(prm["Re2"], prm["cx2"], prm["r2"], -1,
                         chains[1] if chains else None))
    else:
        verts.append(((prm["Lx"], wall_y(prm, "t", prm["Lx"])), 0.0))
        verts.append(((prm["Lx"], wall_y(prm, "b", prm["Lx"])), 0.0))
    ibot = len(verts) - 1                  # the BOTTOM wall leaves here
    if bows:
        m = len(verts)
        for k, i in ((1, itop), (0, ibot)):
            if not bows[k]:
                continue
            a, b = verts[i][0], verts[(i + 1) % m][0]
            verts[i] = (a, bow_bulge(bows[k], dist(a, b), a, b))
    return verts_to_segs(verts)


def fit_endcap(pts, kind, both, oos=False):
    """ICP for a rectangle body with a Roman or radius (Oval) end cap
    on the +x end - and on the -x end too when BOTH.  With OOS the two
    side walls may also swing, so a pool built wider at one end than
    the other comes out that way; the caps are fitted against the walls
    as they go, which is why the swing belongs here and not in a pass
    bolted on afterwards."""
    x0, y0, x1, y1 = bbox(pts)
    w = y1 - y0
    prm = {"By": y0, "Ty": y1, "Lx": x0, "sb": 0.0, "st": 0.0,
           "xm": (x0 + x1) / 2.0}
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
        prm["xm"] = (xl + xr) / 2.0
        cy1 = cap_cy(prm, prm["cx"])
        cy2 = cap_cy(prm, prm["cx2"]) if both else cy
        byr, tyr = wall_y(prm, "b", xr), wall_y(prm, "t", xr)
        byl, tyl = wall_y(prm, "b", xl), wall_y(prm, "t", xl)
        bot, top, lft, arc1, arc2, end1, end2 = [], [], [], [], [], [], []
        for p in pts:
            # nearest feature by construction, not by segment list:
            # classify by x band first, then by side
            d_arc1 = abs(dist(p, (prm["cx"], cy1)) - prm["r"])
            if p[0] < prm["cx"]:
                d_arc1 = min(dist(p, (prm["Re"], byr)),
                             dist(p, (prm["Re"], tyr)))
            d_arc2 = None
            if both:
                d_arc2 = abs(dist(p, (prm["cx2"], cy2)) - prm["r2"])
                if p[0] > prm["cx2"]:
                    d_arc2 = min(dist(p, (prm["Re2"], byl)),
                                 dist(p, (prm["Re2"], tyl)))
            inband = xl <= p[0] <= xr
            d_bot = (abs(p[1] - wall_y(prm, "b", p[0])) if inband
                     else 1.0e9)
            d_top = (abs(p[1] - wall_y(prm, "t", p[0])) if inband
                     else 1.0e9)
            d_lft = 1.0e9 if both else abs(p[0] - prm["Lx"])
            d_end1 = abs(p[0] - prm["Re"]) if abs(p[1] - cy1) > \
                endcap_h(prm["Re"], prm["cx"], cy1, prm["r"], byr, tyr) \
                else 1.0e9
            d_end2 = 1.0e9
            if both:
                d_end2 = (abs(p[0] - prm["Re2"])
                          if abs(p[1] - cy2) > endcap_h(prm["Re2"],
                                                        prm["cx2"], cy2,
                                                        prm["r2"], byl,
                                                        tyl)
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
        # two INDEPENDENT wall lines once the pool may be out of
        # square: each answers its own points and neither is tied to
        # the other's direction; cap_slopes only says how far either
        # may go
        if not oos:
            for wpts, key in ((bot, "By"), (top, "Ty")):
                if wpts:
                    prm[key] = sum(p[1] for p in wpts) / len(wpts)
        else:
            lb = cap_wall(bot) if bot else None
            lt = cap_wall(top) if top else None
            sb, st = cap_slopes(lb[2] if lb else prm.get("sb", 0.0),
                                lt[2] if lt else prm.get("st", 0.0))
            prm["sb"], prm["st"] = sb, st
            # the offset is the fitted line read at the body's middle,
            # so it has to follow the slope the clamp actually allowed
            if lb:
                prm["By"] = lb[0] + sb * (prm["xm"] - lb[1])
            if lt:
                prm["Ty"] = lt[0] + st * (prm["xm"] - lt[1])
        if lft and not both:
            prm["Lx"] = sum(p[0] for p in lft) / len(lft)
        cy1 = cap_cy(prm, prm["cx"])
        # right cap
        if arc1:
            if kind == "Oval":
                prm["r"] = cap_half(prm, prm["cx"])
            else:
                cc = (prm["cx"], cy1)
                prm["r"] = sum(dist(p, cc) for p in arc1) / len(arc1)
            ssum = n = 0
            for p in arc1:
                d = prm["r"] ** 2 - (p[1] - cy1) ** 2
                if d > 0.0:
                    ssum += p[0] - math.sqrt(d)
                    n += 1
            if n:
                prm["cx"] = ssum / n
        if kind == "Oval":
            prm["r"] = cap_half(prm, prm["cx"])
            prm["Re"] = prm["cx"]
        elif end1:
            prm["Re"] = sum(p[0] for p in end1) / len(end1)
        prm["Re"] = min(prm["Re"], prm["cx"] + prm["r"] - 0.5)
        # left cap
        if both:
            cy2 = cap_cy(prm, prm["cx2"])
            if arc2:
                if kind == "Oval":
                    prm["r2"] = cap_half(prm, prm["cx2"])
                else:
                    cc = (prm["cx2"], cy2)
                    prm["r2"] = sum(dist(p, cc) for p in arc2) / len(arc2)
                ssum = n = 0
                for p in arc2:
                    d = prm["r2"] ** 2 - (p[1] - cy2) ** 2
                    if d > 0.0:
                        ssum += p[0] + math.sqrt(d)
                        n += 1
                if n:
                    prm["cx2"] = ssum / n
            if kind == "Oval":
                prm["r2"] = cap_half(prm, prm["cx2"])
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


# ---- arcs that are not one arc ---------------------------------------
#
# A drawn end is one clean radius.  A built one very often is not: a
# gunite shell caves in a little as it cures, and a single arc through
# those points either misses them or lies about them.  So an end that a
# single arc cannot hold within the distance the user typed is rebuilt
# as a POLYLINE OF ARCS - each joint sitting on a survey point, so the
# chain is continuous by construction and every joint is a real
# measurement.  Extra arcs have to earn their place: the run keeps the
# fewest that hold the points.


def bulge_3pt(p1, q, p2):
    """Bulge of the arc P1 -> Q -> P2; 0.0 when degenerate.  ABHD's,
    unchanged."""
    c = circumcenter(p1, q, p2)
    if c is None:
        return 0.0
    a1, a2, aq = ang(c, p1), ang(c, p2), ang(c, q)
    dccw = norm_ang(a2 - a1)
    dq = norm_ang(aq - a1)
    if dccw < 1.0e-9 or dccw > 2.0 * math.pi - 1.0e-9:
        return 0.0
    if dq <= dccw:
        return fit_tan(dccw / 4.0)
    return -fit_tan((2.0 * math.pi - dccw) / 4.0)


def fit_tan(x):
    x = max(-1.5697, min(1.5697, x))
    return math.tan(x)


def best_bulge(a, b, qs):
    """The one arc from A to B that best fits QS: the exact 3-point
    arcs through each point, plus their average, judged on worst
    deviation."""
    if not qs:
        return 0.0
    bls = [bulge_3pt(a, q, b) for q in qs]
    cands = bls + [sum(bls) / len(bls)]
    best, bd = 0.0, None
    for bl in cands:
        d = span_dev(a, b, bl, qs)
        if bd is None or d < bd:
            best, bd = bl, d
    return best


def span_dev(a, b, bul, qs):
    return max((seg_dist(q, (a, b, bul)) for q in qs), default=0.0)


# ---- tangency: ABHD's continuity, on FITABHD's runs -------------------
# A run of arcs that merely shares its joints is continuous but not
# SMOOTH - each arc can arrive at a joint pointing somewhere else, and
# the end of a pool reads as a row of facets.  ABHD solved this with a
# window rather than a chain: at each joint the next arc's start
# tangent may differ from the previous arc's end tangent by at most
# TANG_TOL, so the curve stays smooth while the POINTS still choose
# inside that window.  The same window governs a run here.


def end_tangent(a, b, bul):
    """Tangent direction at the END of the arc A -> B: the chord
    direction plus half the included angle."""
    return ang(a, b) + 2.0 * math.atan(bul)


def start_tangent(a, b, bul):
    """Tangent direction where the arc A -> B leaves A."""
    return ang(a, b) - 2.0 * math.atan(bul)


def tang_window(te, a, b, wf):
    """The bulges the span A -> B may take if its start tangent is to
    stay within WF * TANG_TOL of the incoming tangent TE.  The edges are
    clamped so U-turn geometry stays finite."""
    tt = TANG_TOL * wf
    phi = signed_dang(te, ang(a, b))
    lo = fit_tan(max(-1.373, min(1.373, (phi - tt) / 2.0)))
    hi = fit_tan(max(-1.373, min(1.373, (phi + tt) / 2.0)))
    return (lo, hi) if lo <= hi else (hi, lo)


def end_window(ts0, a, b, wf):
    """The bulges the CLOSING span A -> B may take if its end tangent is
    to stay within WF * TANG_TOL of the ring's start tangent TS0."""
    tt = TANG_TOL * wf
    psi = signed_dang(ang(a, b), ts0)
    lo = fit_tan(max(-1.373, min(1.373, (psi - tt) / 2.0)))
    hi = fit_tan(max(-1.373, min(1.373, (psi + tt) / 2.0)))
    return (lo, hi) if lo <= hi else (hi, lo)


def isect_win(w1, w2):
    """Where two bulge windows overlap; None when they do not."""
    if w1 is None:
        return w2
    if w2 is None:
        return w1
    lo, hi = max(w1[0], w2[0]), min(w1[1], w2[1])
    return (lo, hi) if lo <= hi else None


def best_bulge_win(a, b, qs, win):
    """best_bulge, but every candidate held inside the window WIN - so
    the arc answers its points as well as it can WITHOUT leaving the
    joint visibly kinked."""
    if win is None:
        return best_bulge(a, b, qs)
    if not qs:
        return max(win[0], min(win[1], 0.0))
    cands = [bulge_3pt(a, q, b) for q in qs]
    cands.append(sum(cands) / len(cands))
    cands = [max(win[0], min(win[1], c)) for c in cands]
    best, bd = cands[0], None
    for bl in cands:
        d = span_dev(a, b, bl, qs)
        if bd is None or d < bd:
            best, bd = bl, d
    return best


def smooth_bulge(te, a, b, qs, tol, ts0=None):
    """The arc that continues the tangent TE smoothly and still answers
    QS.  The window is STRETCHED through TANG_STEPS rather than
    abandoned - smoothness is worth more than an exact hit - and the
    first stretch whose arc holds the points within TOL wins.  TS0, on
    the closing span of a ring, also holds the far end to the tangent
    the ring started with."""
    out = None
    for wf in TANG_STEPS:
        win = tang_window(te, a, b, wf)
        if ts0 is not None:
            win = isect_win(win, end_window(ts0, a, b, wf))
            if win is None:
                continue
        out = best_bulge_win(a, b, qs, win)
        if span_dev(a, b, out, qs) <= tol:
            return out
    if out is None:                        # the two ends cannot agree
        out = best_bulge_win(a, b, qs,
                             tang_window(te, a, b, TANG_STEPS[-1]))
    return out


def chain_kink(chain, z, closed=False):
    """The worst joint in a run: how far the next arc's start tangent
    departs from the previous arc's end tangent, in radians."""
    segs = chain_segs(chain, z)
    worst = 0.0
    for i in range(1, len(segs)):
        k = abs(signed_dang(end_tangent(*segs[i - 1]),
                            start_tangent(*segs[i])))
        worst = max(worst, k)
    if closed and len(segs) > 1:
        worst = max(worst, abs(signed_dang(end_tangent(*segs[-1]),
                                           start_tangent(*segs[0]))))
    return worst


def chain_segs(chain, z):
    """The (p1 p2 bulge) segments of a (point bulge) run ending at Z."""
    pts = [c[0] for c in chain] + [z]
    return [(pts[i], pts[i + 1], chain[i][1]) for i in range(len(chain))]


def round_chain_of(qs, k, tol):
    """The whole outline of a Round pool as one closed run of K arcs,
    the joints spaced evenly round the (already rotated) survey.  The
    first arc is free; each one after it leaves its joint smooth, and
    the last has to close on the tangent the ring started with."""
    n = len(qs)
    trial = [(qs[s * n // k], 0.0) for s in range(k)]
    te = ts0 = None
    for s in range(k):
        lo = s * n // k
        hi = (s + 1) * n // k if s < k - 1 else n
        a, nxt = trial[s][0], trial[(s + 1) % k][0]
        if te is None:
            bl = best_bulge(a, nxt, qs[lo:hi])
            ts0 = start_tangent(a, nxt, bl)
        else:
            bl = smooth_bulge(te, a, nxt, qs[lo:hi], tol,
                              ts0 if s == k - 1 else None)
        trial[s] = (a, bl)
        te = end_tangent(a, nxt, bl)
    return trial


def arc_chain(qs, a, z, k, tol):
    """A run of K arcs from A to Z through the ordered points QS.  The
    K-1 joints are survey points themselves, and every one of them is
    smooth: the first arc is free, each one after it starts within the
    tangency window of the arc before it."""
    n = len(qs)
    bounds = [0] + [s * n // k for s in range(1, k)] + [n]
    out = []
    te = None
    for s in range(k):
        lo, hi = bounds[s], bounds[s + 1]
        start = a if s == 0 else qs[lo]
        end = z if s == k - 1 else qs[hi]
        if te is None:
            bl = best_bulge(start, end, qs[lo:hi])
        else:
            bl = smooth_bulge(te, start, end, qs[lo:hi], tol)
        out.append((start, bl))
        te = end_tangent(start, end, bl)
    return out


def chain_worst(chain, z, qs):
    segs = chain_segs(chain, z)
    return max((min(seg_dist(q, s) for s in segs) for q in qs),
               default=0.0)


def fit_arc_run(qs, a, z, tol):
    """The run of arcs from A to Z that best answers the ordered points
    QS.  ONE arc if one holds them within TOL - an end that really is
    one radius stays one radius, and no chain appears.  Once a single
    arc has failed, though, the run keeps going while each extra arc
    clearly earns its place: stopping the moment it scrapes inside the
    tolerance would leave the shell's real shape on the table, and the
    tangency window is what keeps the result a curve rather than a row
    of facets.  Returns the (point, bulge) run from A up to but not
    including Z."""
    best = [(a, best_bulge(a, z, qs))]
    if not qs:
        return best
    worst = chain_worst(best, z, qs)
    if worst <= tol:                       # one radius holds them
        return best
    kmax = max(1, len(qs) // ARC_PTS_MIN)
    for k in range(2, kmax + 1):
        if worst <= ON_EPS:
            break            # every point is ON it: nothing left to
        trial = arc_chain(qs, a, z, k, tol)   # chase but the noise
        w = chain_worst(trial, z, qs)
        if w > worst * BOTH_EDGE:          # not a clear enough gain -
            continue                       # but a plateau is not the
        best, worst = trial, w             # end of the curve either
    return best


def order_along_arc(qs, seg):
    """The points sorted along the arc SEG, start to end."""
    g = arc_geom(seg[0], seg[1], seg[2])
    if g is None:
        return list(qs)
    c, _r, a1, _a2 = g
    ccw = seg[2] > 0.0
    return sorted(qs, key=lambda p: (norm_ang(ang(c, p) - a1) if ccw
                                     else norm_ang(a1 - ang(c, p))))


def nearest_seg(p, segs):
    best, bd = 0, None
    for i, s in enumerate(segs):
        d = seg_dist(p, s)
        if bd is None or d < bd:
            best, bd = i, d
    return best


def arc_seg_points(pts, segs, i):
    """The points whose nearest piece of the outline is segment I."""
    return [p for p in pts if nearest_seg(p, segs) == i]


def round_segs(prm, chain=None):
    if chain:
        return chain_segs(chain, chain[0][0])
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
        size = grec_face(dirs, offs)
        dirs, offs = grec_cuts(dirs, offs, size)
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


def endcap_result(ptype, fpts, both, oos=False):
    prm = fit_endcap(fpts, ptype, both, oos)
    segs = endcap_segs(prm, ptype, both)
    return {"kind": "cap", "type": ptype, "prm": prm, "both": both,
            "bows": None, "segs": segs}


def fit_config(ptype, fpts, treat, both, oos=False):
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
        return endcap_result(ptype, fpts, both, oos)
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


def refine_cap_angle(dpts, ptype, treat, best):
    """Fit the FRAME ANGLE of an arc-ended body, not just its walls.

    The frame is the body's own axis, and the edge vote cannot find it
    once the two side walls lean by different amounts: every edge pulls
    the vote towards its own direction, so the axis lands between the
    walls and the flat end is drawn crooked.  The walls do not care -
    each has its own slope - but the end does, so the angle is fitted
    too: a one-degree sweep to find the basin, then golden section
    inside it.  Kept only if it beats the voted angle."""
    both, mirror = best.get("both"), best["mirror"]

    def at(a):
        fpts = to_frame(dpts, a, mirror)
        res = fit_config(ptype, fpts, treat, both, True)
        worst, rms = outline_dev(fpts, res["segs"])
        return rms, res, worst

    step = math.pi / 180.0
    n = int(round(CAP_OOS_MAX / step))
    ba, (brms, bres, bworst) = best["angle"], at(best["angle"])
    for k in range(-n, n + 1):
        if k == 0:
            continue
        a = best["angle"] + k * step
        rms, res, worst = at(a)
        if rms < brms:
            ba, brms, bres, bworst = a, rms, res, worst
    gr = 0.6180339887
    lo, hi = ba - step, ba + step
    x1 = hi - gr * (hi - lo)
    x2 = lo + gr * (hi - lo)
    f1, f2 = at(x1), at(x2)
    for _ in range(16):
        if f1[0] <= f2[0]:
            hi, x2, f2 = x2, x1, f1
            x1 = hi - gr * (hi - lo)
            f1 = at(x1)
        else:
            lo, x1, f1 = x1, x2, f2
            x2 = lo + gr * (hi - lo)
            f2 = at(x2)
    a = (lo + hi) / 2.0
    rms, res, worst = at(a)
    if rms >= brms:
        a, rms, res, worst = ba, brms, bres, bworst
    if rms >= best["rms"]:
        return best
    res.update({"angle": a, "mirror": mirror, "worst": worst, "rms": rms})
    return res


def fit_type(pts, ptype, treat, oos=False):
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
        res = fit_config(ptype, fpts, treat, both, oos)
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
        res = fit_config(ptype, fpts, treat, False, oos)
        worst, rms = outline_dev(fpts, res["segs"])
        res.update({"angle": a, "mirror": False,
                    "worst": worst, "rms": rms})
        best = res
    # an arc-ended body whose walls lean unequally needs its frame
    # angle fitted as well, or the flat end comes out crooked
    if oos and best is not None and best["kind"] == "cap":
        best = refine_cap_angle(dpts, ptype, treat, best)
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
        return endcap_segs(res["prm"], res["type"], res["both"],
                           res.get("bows"), res.get("chains"))
    return round_segs(res["prm"], res.get("chain"))


# ---- nice dimensions -------------------------------------------------
#
# After the free fit, each headline dimension is snapped to the first
# friendly increment - whole feet, half feet, inches, half inches -
# that the points can live with: the snapped outline must stay within
# the run tolerance (or, when an outlier already sits beyond it, move
# nothing more than SNAP_EPS).  The points outrank pretty numbers.

SNAP_EPS = 0.02                    # fit:*snap-eps*


def grec_axis_corners(dirs, offs):
    """Where the four AXIS walls of an eight-wall template would meet
    if the cuts were not there - the pool's nominal corners.  Taken
    from the walls themselves, so it still means something once they
    have swung out of square."""
    return poly_corners([dirs[0], dirs[2], dirs[4], dirs[6]],
                        [offs[0], offs[2], offs[4], offs[6]])


def grec_cut_dir(dirs, k):
    """A cut wall bisects the corner it crosses, whatever the two axis
    walls are doing - exactly 45 degrees on a true pool, and still a
    real cut on an out-of-square one."""
    d0, d1 = dirs[2 * k], dirs[(2 * k + 2) % 8]
    return d0 + signed_dang(d0, d1) / 2.0


def grec_cuts(dirs, offs, face):
    """Re-derive the four cut walls from the four axis walls: each
    bisects its corner and sits the same perpendicular inset (face/2)
    in from where the axis walls would meet."""
    sq = grec_axis_corners(dirs, offs)
    if sq is None:
        return dirs, offs
    dirs, offs = list(dirs), list(offs)
    h = face / 2.0
    for k in range(4):
        i = 2 * k + 1
        dirs[i] = grec_cut_dir(dirs, k)
        n = wall_normal(dirs[i])
        vc = sq[(k + 1) % 4]
        offs[i] = n[0] * vc[0] + n[1] * vc[1] - h
    return dirs, offs


def grec_face(dirs, offs):
    """The mean cut-face length the four fitted cut walls imply."""
    sq = grec_axis_corners(dirs, offs)
    if sq is None:
        return 0.0
    hsum = 0.0
    for k in range(4):
        i = 2 * k + 1
        n = wall_normal(dirs[i])
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
    face = grec_face(dirs, offs)
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
        face = grec_face(dirs, offs)
        dirs, offs = grec_cuts(dirs, offs, face)
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
            res["dirs"], res["offs"] = grec_cuts(res["dirs"], offs,
                                                 res["size"])
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
        res["segs"] = endcap_segs(prm, t, res["both"], res.get("bows"),
                                  res.get("chains"))
        return res
    if res["kind"] == "round" and key == "RAD":
        res["prm"]["r"] = v
        res["segs"] = round_segs(res["prm"], res.get("chain"))
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


def corner_zone_of(res):
    """How far from a corner a point belongs to the corner feature
    rather than to a wall."""
    if res.get("vsize"):
        return 1.2 * res["vsize"] * math.tan(math.pi / 8.0) + ZONE_PAD
    if len(res["offs"]) == 8:
        # on an eight-wall template the cut corners ARE walls, and
        # "size" is their face length - not a corner feature at all
        return 0.0
    if res.get("size"):
        return 1.2 * res["size"] + ZONE_PAD
    return CORNER_ZONE if res["treat"] in ("Radius", "Cut") else 0.0


def apply_refinement(res, fpts, oos, bowed):
    """Refine the placement that already WON: let the walls answer to
    the points.  A refinement is never a competitor in the search - the
    extra freedom would let a wrong rotation bend its way to a good
    score - so it runs once, on the winner."""
    if res["kind"] == "poly":
        dirs, offs, bows = refine_walls(fpts, res["dirs"], res["offs"],
                                        corner_zone_of(res), oos, bowed)
        swung = any(abs(signed_dang(a, b)) > 1.0e-9
                    for a, b in zip(res["dirs"], dirs))
        if not swung and not bows:
            return res
        res = dict(res)
        res["dirs"], res["offs"], res["bows"] = dirs, offs, bows
        res["swung"] = swung
        if len(offs) == 8:
            res["size"] = grec_face(dirs, offs)
        res["verts"] = build_polygon(
            dirs, offs, res["treat"],
            res.get("vsize") if len(offs) == 8 else res["size"],
            res["which"], bows)
        res["segs"] = verts_to_segs(res["verts"])
        return res
    if res["kind"] == "cap" and bowed:
        # an arc-ended body's SIDE walls can bow; swinging them would
        # take the end caps with them, so out-of-square stops here
        prm, bows = fit_cap_bows(fpts, res["prm"], res["both"])
        if not any(bows):
            return res
        res = dict(res)
        res["prm"], res["bows"] = prm, bows
        res["segs"] = endcap_segs(prm, res["type"], res["both"], bows)
        return res
    return res                              # a round pool has no walls


def poly_vert_map(dirs, offs, treat, size, which):
    """Which vert each wall leaves from, and which vert each corner's
    own curve starts at - the same walk build_polygon does, so a run
    can say WHICH corner or wall it rebuilt."""
    corners = poly_corners(dirs, offs)
    n = len(corners)
    leaves, starts, k = [], [], 0
    for i in range(n):
        turn, _bis = corner_frame(dirs, i)
        m = len(corner_verts(corners[(i - 1) % n], corners[i],
                             corners[(i + 1) % n], turn, treat,
                             size)) if which else 1
        starts.append(k)
        k += m
        leaves.append(k - 1)
    return leaves, starts


def splice_run(verts, k, run):
    """The run's arcs replace the single one at vert K."""
    return verts[:k] + list(run) + verts[k + 1:]


def poly_chains(res, fpts, segs, bulged, tol):
    """Rebuild every curve of a polygon outline that one arc cannot
    hold.  Back to front, so an earlier splice cannot move a later
    index."""
    verts = list(res["verts"])
    leaves, starts = poly_vert_map(
        res["dirs"], res["offs"], res["treat"],
        res.get("vsize") if len(res["offs"]) == 8 else res.get("size"),
        res["which"])
    runs = []
    for k in reversed(bulged):
        s = segs[k]
        qs = order_along_arc(arc_seg_points(fpts, segs, k), s)
        if len(qs) < 2 * ARC_PTS_MIN:
            continue
        run = fit_arc_run(qs, s[0], s[1], tol)
        if len(run) > 1:
            nm = (("wall", leaves.index(k)) if k in leaves
                  else ("corner", starts.index(k)))
            runs.append((nm, len(run), chain_kink(run, s[1]),
                         chain_segs(run, s[1])))
            verts = splice_run(verts, k, run)
    if not runs:
        return res
    res = dict(res)
    res["runs"] = runs
    res["verts"] = verts
    res["segs"] = verts_to_segs(verts)
    return res


def apply_arc_chains(res, fpts, tol):
    """Rebuild any arc a single radius cannot hold as a run of arcs
    through the points.  This runs LAST, after the dimensions are
    settled: a chain changes no dimension, it just stops the outline
    lying about where the shell actually went.  A corner fillet and a
    bowed wall are drawn as one R for the same reason an oval's end is
    - because that is how the shape is DESCRIBED - so the same rules
    reach them too.  A straight wall has no bulge to break up."""
    if res["kind"] not in ("cap", "round", "poly"):
        return res
    segs = frame_segs(res)
    bulged = [i for i, s in enumerate(segs) if abs(s[2]) > 1.0e-9]
    if not bulged:
        return res
    if res["kind"] == "poly":
        return poly_chains(res, fpts, segs, bulged, tol)
    if res["kind"] == "round":
        qs = list(fpts)
        if len(qs) < 2 * ARC_PTS_MIN:
            return res
        c = (res["prm"]["cx"], res["prm"]["cy"])
        # AutoLISP's (angle) runs 0..2pi, so the ring starts where the
        # LISP starts it - a closed run is sensitive to that
        qs.sort(key=lambda p: norm_ang(ang(c, p)))
        best, worst = None, max(min(seg_dist(q, s) for s in segs)
                                for q in qs)
        n = len(qs)
        k = 2
        # the ring only STARTS breaking up when one circle misses; from
        # there it keeps going while each extra arc earns its place,
        # exactly as an end cap's run does
        if worst <= tol:
            return res
        while k < n // ARC_PTS_MIN:
            k += 1
            if worst <= ON_EPS:
                break
            # a closed ring has no natural first joint, and where the
            # joints land decides how well they bracket the cave-in, so
            # try the aligned run and one shifted half a span
            tw, tc = None, None
            for off in (0, n // (2 * k)):
                trial = round_chain_of(qs[off:] + qs[:off], k, tol)
                w = chain_worst(trial, trial[0][0], qs)
                if tw is None or w < tw:
                    tw, tc = w, trial
            if tw > worst * BOTH_EDGE:
                continue
            best, worst = tc, tw
        if best is None:
            return res
        res = dict(res)
        res["chain"] = best
        res["kink"] = chain_kink(best, best[0][0], True)
        res["segs"] = round_segs(res["prm"], best)
        return res
    chains, kinks = [None, None], [0.0, 0.0]
    for side, i in enumerate(bulged[:2]):
        qs = order_along_arc(arc_seg_points(fpts, segs, i), segs[i])
        if len(qs) < 2 * ARC_PTS_MIN:
            continue
        run = fit_arc_run(qs, segs[i][0], segs[i][1], tol)
        if len(run) > 1:
            chains[side] = run
            kinks[side] = chain_kink(run, segs[i][1])
    if not any(chains):
        return res
    res = dict(res)
    res["chains"] = chains
    res["kinks"] = kinks
    res["segs"] = endcap_segs(res["prm"], res["type"], res["both"],
                              res.get("bows"), chains)
    return res


def fit_and_snap(pts, ptype, treat, tol, pct, oos, bowed):
    """The whole engine: configuration search, the bow refinement when
    the walls may be bowed, then nice-dim snapping against the share of
    the points the user allows beyond the distance."""
    dpts = dedupe(pts)
    allow = fit_ceil(pct * len(dpts))
    res = fit_type(dpts, ptype, treat, oos)
    fpts = (dpts if res["kind"] == "round"
            else to_frame(dpts, res["angle"], res["mirror"]))
    if oos or bowed:
        res = apply_refinement(res, fpts, oos, bowed)
    res = snap_result(res, fpts, tol, allow)
    res = apply_arc_chains(res, fpts, tol)
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
    res = fit_and_snap(pts, "Rectangle", "Radius", 1.0, MISS_PCT, False, False)
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
    res = fit_and_snap(pts, "Rectangle", "Cut", 1.0, MISS_PCT, False, False)
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
    res = fit_and_snap(pts, "Rectangle", "Square", 1.0, MISS_PCT, False, False)
    assert close(get_dim(res, "LEN"), 380.0, 1e-6), get_dim(res, "LEN")
    assert close(get_dim(res, "WID"), 168.0, 1e-6), get_dim(res, "WID")
    print("  the points outrank nice numbers: 380\" stays 380\"")


def test_grecian_cut_face():
    offs = grec_cuts(GREC_DIRS,
                     [0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0],
                     36.0)[1]
    true = verts_to_segs(build_polygon(GREC_DIRS, offs, "Square", None,
                                       set()))
    pts = survey(place(true, 71.0, -50.0, 800.0), 16.0, 0.3, seed=13)
    res = fit_and_snap(pts, "Grecian", "Square", 1.0, MISS_PCT, False, False)
    assert close(get_dim(res, "LEN"), 350.0, 1e-6), get_dim(res, "LEN")
    assert close(get_dim(res, "WID"), 180.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "CUT"), 36.0, 1e-6), get_dim(res, "CUT")
    print("  grecian: 350 x 180, 36\" corner cuts, worst %.2f"
          % res["worst"])


def test_grecian_rounded_as_built():
    # a nominal grecian is sharp, but an as-built may well ease the
    # eight cut corners - answering Radius measures one shared easing
    offs = grec_cuts(GREC_DIRS,
                     [0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0],
                     36.0)[1]
    true = verts_to_segs(build_polygon(GREC_DIRS, offs, "Radius", 8.0,
                                       set(range(8))))
    pts = survey(place(true, 71.0, -50.0, 800.0), 14.0, 0.3, seed=23)
    res = fit_and_snap(pts, "Grecian", "Radius", 1.0, MISS_PCT, False, False)
    assert close(get_dim(res, "LEN"), 350.0, 1e-6), get_dim(res, "LEN")
    assert close(get_dim(res, "WID"), 180.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "CUT"), 36.0, 1e-6), get_dim(res, "CUT")
    assert close(get_dim(res, "VSIZE"), 8.0, 1e-6), get_dim(res, "VSIZE")
    assert res["worst"] <= 1.0, res["worst"]
    print("  grecian as-built: 8\" eased cut corners found and held")


def test_grecian_sharp_stays_sharp():
    # answering Radius on a genuinely sharp grecian must not invent an
    # easing: noise is not evidence
    offs = grec_cuts(GREC_DIRS,
                     [0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0],
                     36.0)[1]
    true = verts_to_segs(build_polygon(GREC_DIRS, offs, "Square", None,
                                       set()))
    pts = survey(place(true, 71.0, -50.0, 800.0), 14.0, 0.3, seed=13)
    res = fit_and_snap(pts, "Grecian", "Radius", 1.0, MISS_PCT, False, False)
    assert get_dim(res, "VSIZE") is None, get_dim(res, "VSIZE")
    assert close(get_dim(res, "CUT"), 36.0, 1e-6), get_dim(res, "CUT")
    print("  a sharp grecian answered Radius stays sharp")


def test_roman_end_is_found():
    prm = {"By": -96.0, "Ty": 96.0, "Lx": 0.0, "cx": 300.0, "r": 120.0,
           "Re": 300.0 + math.sqrt(120.0 ** 2 - 72.0 ** 2)}
    true = endcap_segs(prm, "ROman", False)
    pts = survey(place(true, 197.0, 500.0, 300.0), 22.0, 0.3, seed=11)
    res = fit_and_snap(pts, "ROman", "Square", 1.0, MISS_PCT, False, False)
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
    res = fit_and_snap(pts, "Oval", "Square", 1.0, MISS_PCT, False, False)
    assert res["both"], "both radius ends expected"
    assert close(get_dim(res, "WID"), 168.0, 1e-6), get_dim(res, "WID")
    assert close(get_dim(res, "BLEN"), 216.0, 1e-6), get_dim(res, "BLEN")
    print("  oval: both 84\" radius ends, straight run %.0f\""
          % get_dim(res, "BLEN"))


def tapered_cap(taper, kind):
    """A cap body built wider at one end than the other - the side
    walls not quite parallel, which is what an out-of-square arc-ended
    pool actually is.  Each end is the arc that fits between the walls
    AT THAT END, so the fixture is a shape that can really exist."""
    if kind == "Oval":
        prm = {"By": 0.0, "Ty": 168.0, "Lx": 0.0, "xm": 192.0,
               "cx": 300.0, "cx2": 84.0,
               "sb": -taper / 2 / 216.0, "st": taper / 2 / 216.0}
        prm["r"] = cap_half(prm, prm["cx"])
        prm["Re"] = prm["cx"]
        prm["r2"] = cap_half(prm, prm["cx2"])
        prm["Re2"] = prm["cx2"]
        return endcap_segs(prm, "Oval", True), True
    prm = {"By": -96.0, "Ty": 96.0, "Lx": 0.0, "cx": 300.0, "r": 120.0,
           "Re": 300.0 + math.sqrt(120.0 ** 2 - 72.0 ** 2)}
    prm["xm"] = (prm["Lx"] + prm["Re"]) / 2.0
    span = prm["Re"] - prm["Lx"]
    prm["sb"], prm["st"] = -taper / 2 / span, taper / 2 / span
    return endcap_segs(prm, "ROman", False), False


def leaning_cap(kind, deg_b, deg_t):
    """A cap body whose two side walls lean by their OWN angles - a
    shell that slumped to one side, which is what an as-built arc-ended
    pool does as it cures.  Each end is again the arc that fits between
    the walls at that end, so the fixture is a shape that can exist."""
    sb, st = math.tan(math.radians(deg_b)), math.tan(math.radians(deg_t))
    if kind == "Oval":
        prm = {"By": 0.0, "Ty": 168.0, "Lx": 0.0, "xm": 192.0,
               "cx": 300.0, "cx2": 84.0, "sb": sb, "st": st}
        prm["r"] = cap_half(prm, prm["cx"])
        prm["Re"] = prm["cx"]
        prm["r2"] = cap_half(prm, prm["cx2"])
        prm["Re2"] = prm["cx2"]
        return endcap_segs(prm, "Oval", True)
    prm = {"By": -96.0, "Ty": 96.0, "Lx": 0.0, "cx": 300.0, "r": 120.0,
           "Re": 300.0 + math.sqrt(120.0 ** 2 - 72.0 ** 2)}
    prm["xm"] = (prm["Lx"] + prm["Re"]) / 2.0
    prm["sb"], prm["st"] = sb, st
    return endcap_segs(prm, "ROman", False)


def cap_divergence_of(res):
    """How far off parallel the fitted side walls came out, in
    degrees."""
    return math.degrees(cap_divergence(res["prm"]))


def cap_taper_of(res):
    """How much wider one end came out than the other."""
    p = res["prm"]
    xl = p["Re2"] if res["both"] else p["Lx"]
    return (cap_half(p, p["Re"]) - cap_half(p, xl)) * 2.0


def test_a_tapered_cap_body_is_honoured():
    # an arc-ended pool built wider at one end: held parallel the
    # template pushes the error into the points, allowed out of square
    # the walls answer them - and the ends spring where the walls are
    for kind, place_at in (("Oval", (40.0, -200.0, 100.0)),
                           ("ROman", (197.0, 500.0, 300.0))):
        segs, _both = tapered_cap(9.0, kind)
        sp = 14.0 if kind == "Oval" else 22.0
        pts = survey(place(segs, *place_at), sp, 0.25, seed=131)
        held = fit_and_snap(pts, kind, "Square", 1.0, 0.15, False, False)
        swung = fit_and_snap(pts, kind, "Square", 1.0, 0.15, True, False)
        assert held["worst"] > 1.5, (kind, held["worst"])
        assert swung["worst"] < 0.8, (kind, swung["worst"])
        assert close(cap_taper_of(held), 0.0, 1e-9), kind
        assert close(cap_taper_of(swung), 9.0, 1.0), \
            (kind, cap_taper_of(swung))
        print("  %-5s built 9\" wider at one end: %.2f\" -> %.2f\""
              % (kind, held["worst"], swung["worst"]))


def test_a_true_cap_body_stays_parallel():
    for kind, place_at in (("Oval", (40.0, -200.0, 100.0)),
                           ("ROman", (197.0, 500.0, 300.0))):
        segs, _both = tapered_cap(0.0, kind)
        sp = 14.0 if kind == "Oval" else 22.0
        pts = survey(place(segs, *place_at), sp, 0.25, seed=131)
        res = fit_and_snap(pts, kind, "Square", 1.0, 0.15, True, False)
        assert abs(cap_taper_of(res)) < 0.5, (kind, cap_taper_of(res))
        assert res["worst"] < 0.8, (kind, res["worst"])
    print("  a cap body whose walls really are parallel stays parallel")


def test_side_walls_need_not_be_parallel():
    # a shell that slumped to one side: one wall leans 8 degrees away
    # from the other, well past anything a rectangle's template would
    # allow, and still inside what an arc-ended pool really does
    for kind, place_at in (("Oval", (40.0, -200.0, 100.0)),
                           ("ROman", (197.0, 500.0, 300.0))):
        segs = leaning_cap(kind, 0.0, 8.0)
        sp = 14.0 if kind == "Oval" else 22.0
        pts = survey(place(segs, *place_at), sp, 0.25, seed=907)
        held = fit_and_snap(pts, kind, "Square", 1.0, 0.15, False, False)
        swung = fit_and_snap(pts, kind, "Square", 1.0, 0.15, True, False)
        assert held["worst"] > 5.0, (kind, held["worst"])
        assert swung["worst"] < 1.0, (kind, swung["worst"])
        assert close(cap_divergence_of(swung), 8.0, 0.6), \
            (kind, cap_divergence_of(swung))
        print("  %-5s one wall leaning 8 deg: %.2f\" -> %.2f\" "
              "(fitted %.1f deg apart)"
              % (kind, held["worst"], swung["worst"],
                 cap_divergence_of(swung)))


def test_walls_further_apart_than_the_limit_are_clamped():
    # 16 degrees apart is not a pool that slumped, it is a shape this
    # template cannot hold: the lean is clamped at the limit rather
    # than thrown away, and the points that no longer fit say so
    for kind, place_at in (("Oval", (40.0, -200.0, 100.0)),
                           ("ROman", (197.0, 500.0, 300.0))):
        segs = leaning_cap(kind, -8.0, 8.0)
        sp = 14.0 if kind == "Oval" else 22.0
        pts = survey(place(segs, *place_at), sp, 0.25, seed=907)
        res = fit_and_snap(pts, kind, "Square", 1.0, 0.15, True, False)
        dv = abs(cap_divergence_of(res))
        assert dv <= math.degrees(CAP_OOS_MAX) + 1.0e-6, (kind, dv)
        assert dv > math.degrees(CAP_OOS_MAX) - 1.5, (kind, dv)
        assert res["worst"] > 2.0, (kind, res["worst"])
        print("  %-5s 16 deg apart: clamped to %.1f deg, worst point "
              "%.2f\" off" % (kind, dv, res["worst"]))


def test_true_l():
    true = verts_to_segs(build_polygon(
        L_DIRS, [0.0, 400.0, 200.0, -220.0, 100.0, 0.0], "Radius",
        18.0, set(range(6))))
    pts = survey(place(true, 107.0, 50.0, -400.0), 20.0, 0.3, seed=3)
    res = fit_and_snap(pts, "L", "Radius", 1.0, MISS_PCT, False, False)
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
    res = fit_and_snap(pts, "LAzyl", "Radius", 1.0, MISS_PCT, False, False)
    want = sorted([300.0, 240.0, 96.0, 200.18, 260.18, 96.0])
    got = sorted(ring_sides(res))
    assert all(close(a, b, 1.0) for a, b in zip(got, want)), got
    assert close(get_dim(res, "SIZE"), 12.0, 1e-6), get_dim(res, "SIZE")
    assert res["worst"] <= 1.0, res["worst"]
    print("  lazy L: 45-degree bend held, sides and 12\" corners"
          " recovered")


def skew_rect(skew_deg, wall=1):
    """A 32' x 16' rectangle with one wall swung out of square - the
    classic as-built: three walls true, the fourth off."""
    dirs = list(RECT_DIRS)
    dirs[wall] = dirs[wall] + math.radians(skew_deg)
    return dirs, [96.0, 192.0, 96.0, 192.0]


def sides_of(dirs, offs):
    co = poly_corners(dirs, offs)
    n = len(co)
    return [dist(co[i], co[(i + 1) % n]) for i in range(n)]


def test_out_of_square_is_honoured():
    # AB pools are built, not drawn: nothing comes out true.  Held
    # square, the template pushes its error into the points; allowed
    # out of square, the walls swing to answer them.
    dirs, offs = skew_rect(2.5)
    true = sides_of(dirs, offs)
    segs = verts_to_segs(build_polygon(dirs, offs, "Square", None, set()))
    pts = survey(place(segs, 17.0, 100.0, 50.0), 18.0, 0.25, seed=61)
    square = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, False,
                          False)
    swung = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, True,
                         False)
    assert square["worst"] > 3.0, square["worst"]
    assert swung["worst"] < 0.6, swung["worst"]
    # held square every side comes out the same; swung, each side is
    # its own length again
    got = sides_of(swung["dirs"], swung["offs"])
    assert all(close(a, b) for a, b in zip(got, true)), (got, true)
    assert swung["swung"], "the fit did not record that it swung"
    print("  out of square: 2.5 degrees of skew answered, %.2f\" -> "
          "%.2f\"" % (square["worst"], swung["worst"]))


def test_a_square_pool_stays_square():
    # the same permission on a pool that really is true must change
    # nothing - the walls stay exactly on the template
    dirs, offs = skew_rect(0.0)
    segs = verts_to_segs(build_polygon(dirs, offs, "Radius", 24.0,
                                       set(range(4))))
    pts = survey(place(segs, 17.0, 100.0, 50.0), 22.0, 0.35, seed=7)
    res = fit_and_snap(pts, "Rectangle", "Radius", 1.0, 0.15, True,
                       False)
    for a, b in zip(RECT_DIRS, res["dirs"]):
        assert abs(signed_dang(a, b)) < 1.0e-9, res["dirs"]
    assert close(get_dim(res, "LEN"), 384.0, 1e-6)
    assert close(get_dim(res, "WID"), 192.0, 1e-6)
    assert close(get_dim(res, "SIZE"), 24.0, 1e-6)
    print("  a pool that really is square stays square")


def test_a_swing_too_far_is_refused():
    # 9 degrees is not an out-of-square rectangle, it is a different
    # shape: the cap holds and the error is reported loudly rather
    # than quietly swallowed
    dirs, offs = skew_rect(9.0)
    segs = verts_to_segs(build_polygon(dirs, offs, "Square", None, set()))
    pts = survey(place(segs, 17.0, 100.0, 50.0), 18.0, 0.25, seed=61)
    res = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, True,
                       False)
    worst_swing = max(abs(signed_dang(a, b))
                      for a, b in zip(RECT_DIRS, res["dirs"]))
    assert worst_swing <= OOS_MAX + 1.0e-9, math.degrees(worst_swing)
    assert res["worst"] > 5.0, res["worst"]
    print("  a swing past the cap is refused, and says so")


def test_out_of_square_l_and_grecian():
    # the concave corner of an L, and a grecian whose cut corners have
    # to follow their axis walls out of square
    dirs = list(L_DIRS)
    dirs[1] += math.radians(1.8)
    dirs[4] -= math.radians(1.2)
    offs = [0.0, 400.0, 200.0, -220.0, 100.0, 0.0]
    segs = verts_to_segs(build_polygon(dirs, offs, "Radius", 18.0,
                                       set(range(6))))
    pts = survey(place(segs, 107.0, 50.0, -400.0), 18.0, 0.25, seed=71)
    square = fit_and_snap(pts, "L", "Radius", 1.0, 0.15, False, False)
    swung = fit_and_snap(pts, "L", "Radius", 1.0, 0.15, True, False)
    assert square["worst"] > 2.0 and swung["worst"] < 0.8, \
        (square["worst"], swung["worst"])
    assert close(get_dim(swung, "SIZE"), 18.0, 1e-6)

    dirs, offs = grec_cuts(GREC_DIRS,
                           [0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0],
                           36.0)
    dirs = list(dirs)
    dirs[2] += math.radians(1.5)
    dirs, offs = grec_cuts(dirs, offs, 36.0)
    segs = verts_to_segs(build_polygon(dirs, offs, "Square", None, set()))
    pts = survey(place(segs, 71.0, -50.0, 800.0), 14.0, 0.25, seed=91)
    square = fit_and_snap(pts, "Grecian", "Square", 1.0, 0.15, False,
                          False)
    swung = fit_and_snap(pts, "Grecian", "Square", 1.0, 0.15, True,
                         False)
    assert square["worst"] > 1.5 and swung["worst"] < 0.8, \
        (square["worst"], swung["worst"])
    # the four cuts still share one face and still bisect their corners
    assert close(get_dim(swung, "CUT"), 36.0, 1e-6), get_dim(swung, "CUT")
    for k in range(4):
        assert abs(signed_dang(grec_cut_dir(swung["dirs"], k),
                               swung["dirs"][2 * k + 1])) < 1.0e-9
    print("  an out-of-square L and grecian: cuts follow their walls")


def test_percent_buys_nice_dimensions():
    # 383" is an inch off a whole foot: at the standard 15% the end
    # walls outvote the snap and it stays 383; raise the share of
    # points allowed off and the same survey rounds to 32'-0".
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [84.0, 191.5, 84.0, 191.5], "Square", None, set()))
    pts = survey(place(true, 5.0, 0.0, 0.0), 20.0, 0.2, seed=31)
    tight = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, False, False)
    loose = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.40, False, False)
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
    straight = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, False, False)
    bowed = fit_and_snap(pts, "Rectangle", "Square", 1.0, 0.15, False, True)
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
    res = fit_and_snap(pts, "Rectangle", "Radius", 1.0, 0.15, False, True)
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
    straight = fit_and_snap(pts, "Oval", "Square", 1.0, 0.15, False, False)
    bowed = fit_and_snap(pts, "Oval", "Square", 1.0, 0.15, False, True)
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
    res = fit_and_snap(pts, "ROUnd", "Square", 1.0, MISS_PCT, False, False)
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


OVAL_PRM = {"By": 0.0, "Ty": 168.0, "cx": 300.0, "r": 84.0,
            "Re": 300.0, "cx2": 84.0, "r2": 84.0, "Re2": 84.0}


def caved_oval(depth, peak=0.3, seed=101):
    """A true oval whose right end has caved in off-centre - the dip a
    shell takes when it slumps to one side as it cures.  A symmetric
    cave-in is still a circle and a single arc handles it; this one no
    single radius can hold."""
    pts = survey(endcap_segs(OVAL_PRM, "Oval", True), 12.0, 0.2, seed)
    c = (OVAL_PRM["cx"], (OVAL_PRM["By"] + OVAL_PRM["Ty"]) / 2.0)
    out = []
    for p in pts:
        if p[0] > c[0]:
            rel = (ang(c, p) + math.pi / 2.0) / math.pi
            pull = depth * math.exp(-((rel - peak) / 0.18) ** 2)
            d = dist(c, p)
            out.append((c[0] + (p[0] - c[0]) * (d - pull) / d,
                        c[1] + (p[1] - c[1]) * (d - pull) / d))
        else:
            out.append(p)
    return out


def no_chains(pts, ptype, treat, tol):
    """The same fit with the arc-chain pass held off, for comparison."""
    keep = globals()["apply_arc_chains"]
    globals()["apply_arc_chains"] = lambda r, f, t2: r
    try:
        return fit_and_snap(pts, ptype, treat, tol, 0.15, False, False)
    finally:
        globals()["apply_arc_chains"] = keep


def test_a_caved_end_becomes_a_run_of_arcs():
    pts = caved_oval(3.0)
    one = no_chains(pts, "Oval", "Square", 1.0)
    run = fit_and_snap(pts, "Oval", "Square", 1.0, 0.15, False, False)
    assert one["worst"] > 2.0, one["worst"]
    assert run["worst"] < 1.0, run["worst"]
    chains = run["chains"]
    assert sum(1 for c in chains if c) == 1, chains
    assert max(len(c) for c in chains if c) >= 2
    # a chain changes the shape of the end, never the pool's dimensions
    assert close(get_dim(run, "WID"), 168.0, 1e-6), get_dim(run, "WID")
    assert close(get_dim(run, "WID"), get_dim(one, "WID"), 1e-6)
    print("  a caved end: one arc %.2f\" off, a run of arcs %.2f\""
          % (one["worst"], run["worst"]))


def test_a_true_end_stays_one_arc():
    pts = caved_oval(0.0)
    res = fit_and_snap(pts, "Oval", "Square", 1.0, 0.15, False, False)
    assert not res.get("chains"), res.get("chains")
    assert close(get_dim(res, "WID"), 168.0, 1e-6)
    assert close(get_dim(res, "BLEN"), 216.0, 1e-6)
    print("  an end that really is one radius stays one arc")


def test_arc_chain_joints_sit_on_survey_points():
    pts = caved_oval(6.0)
    res = fit_and_snap(pts, "Oval", "Square", 1.0, 0.15, False, False)
    fpts = to_frame(dedupe(pts), res["angle"], res["mirror"])
    joints = [v for c in res["chains"] if c for v in c[1:]]
    assert joints, "expected a chain with at least one joint"
    for q, _b in joints:
        assert min(dist(q, p) for p in fpts) < 1.0e-9, q
    print("  every joint of a run sits on a surveyed point")


def rough_caved_oval(depth, sigma, noise, seed):
    """A caved end shot the way a site really is: a narrow slump and
    noise that a run of arcs will chase if nothing holds it back."""
    pts = survey(endcap_segs(OVAL_PRM, "Oval", True), 10.0, noise, seed)
    c = (OVAL_PRM["cx"], (OVAL_PRM["By"] + OVAL_PRM["Ty"]) / 2.0)
    out = []
    for p in pts:
        if p[0] > c[0]:
            rel = (ang(c, p) + math.pi / 2.0) / math.pi
            pull = depth * math.exp(-((rel - 0.30) / sigma) ** 2)
            d = dist(c, p)
            out.append((c[0] + (p[0] - c[0]) * (d - pull) / d,
                        c[1] + (p[1] - c[1]) * (d - pull) / d))
        else:
            out.append(p)
    return out


def kinky_chain(qs, a, z, k):
    """The same run built with no tangency window at all - what the
    joints do when nothing holds them together."""
    n = len(qs)
    bounds = [0] + [s * n // k for s in range(1, k)] + [n]
    out = []
    for s in range(k):
        lo, hi = bounds[s], bounds[s + 1]
        start = a if s == 0 else qs[lo]
        end = z if s == k - 1 else qs[hi]
        out.append((start, best_bulge(start, end, qs[lo:hi])))
    return out


def arc_spans(pts, ptype, tol):
    """The end arcs of the UNCHAINED fit, as (points, a, z) - what the
    chain pass is handed."""
    res = no_chains(pts, ptype, "Square", tol)
    fpts = to_frame(dedupe(pts), res["angle"], res["mirror"])
    out = []
    for i, s in enumerate(res["fsegs"]):
        if abs(s[2]) < 1.0e-9:
            continue
        qs = order_along_arc(arc_seg_points(fpts, res["fsegs"], i), s)
        if len(qs) >= 2 * ARC_PTS_MIN:
            out.append((qs, s[0], s[1]))
    return out


def test_a_run_of_arcs_stays_smooth():
    # ABHD's continuity, on FITABHD's runs: a joint may depart from
    # tangent by the window, and the window may stretch, but nothing
    # past that - a run that only shares its joints draws facets
    lim = TANG_TOL * max(TANG_STEPS) + 1.0e-9
    loose, tight, seen = 0.0, 0.0, 0
    for sigma, noise, seed in ((0.10, 0.5, 77), (0.08, 0.6, 5),
                               (0.12, 0.45, 203)):
        pts = rough_caved_oval(6.0, sigma, noise, seed)
        res = fit_and_snap(pts, "Oval", "Square", 1.0, 0.15, False, False)
        for k in res.get("kinks", []):
            assert k <= lim, (math.degrees(k), seed)
            if k > 0.0:
                seen += 1
                tight = max(tight, k)
        # and the window really is doing the work: the same splits with
        # nothing holding the joints kink well past it
        for qs, a, z in arc_spans(pts, "Oval", 1.0):
            for kk in range(3, len(qs) // ARC_PTS_MIN + 1):
                loose = max(loose, chain_kink(kinky_chain(qs, a, z, kk), z))
                assert chain_kink(arc_chain(qs, a, z, kk, 1.0), z) <= lim
    assert seen, "expected at least one run of arcs"
    assert loose > TANG_TOL * max(TANG_STEPS), math.degrees(loose)
    print("  runs stay smooth: joints %.1f deg, %.1f deg without the "
          "window (limit %.1f)"
          % (math.degrees(tight), math.degrees(loose),
             math.degrees(TANG_TOL * max(TANG_STEPS))))


def test_a_run_keeps_hugging_while_it_earns():
    # one R that holds is left alone; one that does not is answered by
    # as many arcs as keep earning their place, not by the first count
    # that scrapes inside the tolerance
    tol, best = 1.0, None
    for qs, a, z in arc_spans(caved_oval(6.0), "Oval", tol):
        one = span_dev(a, z, best_bulge(a, z, qs), qs)
        run = fit_arc_run(qs, a, z, tol)
        if one <= tol:                     # this end is one radius
            assert len(run) == 1, len(run)
            continue
        two = chain_worst(arc_chain(qs, a, z, 2, tol), z, qs)
        got = chain_worst(run, z, qs)
        assert got <= two + 1.0e-9, (got, two)
        if len(run) > 2:
            # it went past the count that already met the tolerance,
            # and every arc it added earned its place
            assert two <= tol, (two, tol)
            assert got < two * BOTH_EDGE, (got, two)
        if best is None or len(run) > best[0]:
            best = (len(run), one, two, got)
    assert best, "expected an end a single radius could not hold"
    assert best[0] > 2, best               # kept hugging past "enough"
    n, one, two, got = best
    print("  a run keeps earning: one R %.2f\", 2 arcs %.2f\", "
          "%d arcs %.2f\"" % (one, two, n, got))


def oval_corner(sx, sy, sp=5.0, seed=19):
    """A rectangle whose first corner was not built as one radius: an
    as-built corner pulled a little oval.  Nothing exotic - a shell
    corner that came out of the ground slightly egg-shaped, which no
    single R can hold."""
    true = verts_to_segs(build_polygon(RECT_DIRS, [96.0, 192.0, 96.0,
                                                   192.0],
                                       "Radius", 30.0, set(range(4))))
    pts = survey(true, sp, 0.2, seed)
    seg = [s for s in true if abs(s[2]) > 1.0e-9][0]
    c, r, a1, a2 = arc_geom(seg[0], seg[1], seg[2])
    sweep = max(1.0e-9, norm_ang(a2 - a1))
    out = []
    for p in pts:
        d = dist(c, p)
        rel = norm_ang(ang(c, p) - a1) / sweep
        if abs(d - r) < 3.0 and 0.0 <= rel <= 1.0:
            out.append((c[0] + (p[0] - c[0]) * sx,
                        c[1] + (p[1] - c[1]) * sy))
        else:
            out.append(p)
    a = math.radians(11.0)
    return [(rot(q, a)[0] + 60.0, rot(q, a)[1] - 20.0) for q in out]


def test_a_corner_can_be_a_run_of_arcs():
    # a corner fillet is drawn as one R for the same reason an oval's
    # end is - that is how the shape is DESCRIBED - so the same rules
    # reach it: this one was not built that way and says so
    pts = oval_corner(1.12, 0.88)
    one = no_chains(pts, "Rectangle", "Radius", 1.0)
    run = fit_and_snap(pts, "Rectangle", "Radius", 1.0, 0.15, False,
                       False)
    runs = run.get("runs")
    assert runs, "the corner should not have stayed one arc"
    (kind, which), narcs, kink, _segs = runs[0]
    assert kind == "corner", runs
    assert narcs >= 2, runs
    assert kink <= TANG_TOL * max(TANG_STEPS) + 1.0e-9, math.degrees(kink)
    assert run["worst"] < one["worst"] * BOTH_EDGE, \
        (one["worst"], run["worst"])
    # a run changes the shape of the corner, never the dimensions
    assert close(get_dim(run, "SIZE"), get_dim(one, "SIZE"), 1.0e-9)
    assert close(get_dim(run, "LEN"), get_dim(one, "LEN"), 1.0e-9)
    # every joint of the run is a real shot, as on any other run
    fpts = to_frame(dedupe(pts), run["angle"], run["mirror"])
    for _nm, _n, _k, csegs in runs:
        for s in csegs[1:]:
            assert min(dist(s[0], p) for p in fpts) < 1.0e-9, s[0]
    print("  corner %s is a run of %d arcs: %.2f\" -> %.2f\""
          % (chr(65 + which), narcs, one["worst"], run["worst"]))


def test_a_true_corner_stays_one_arc():
    pts = oval_corner(1.0, 1.0)
    res = fit_and_snap(pts, "Rectangle", "Radius", 1.0, 0.15, False,
                       False)
    assert not res.get("runs"), res.get("runs")
    assert close(get_dim(res, "SIZE"), 30.0, 2.0), get_dim(res, "SIZE")
    print("  a corner that really is one radius stays one arc")


def test_a_run_may_reach_a_third_of_the_points():
    # the only ceiling is a third of the points on the curve: each arc
    # needs three of them to mean anything.  No fixed limit - a shell
    # shot forty times has earned more arcs than one shot ten times
    c = (77.0, -33.0)
    circle = [((c[0] + 108.0, c[1]), (c[0] - 108.0, c[1]), 1.0),
              ((c[0] - 108.0, c[1]), (c[0] + 108.0, c[1]), 1.0)]
    base = survey(circle, 8.0, 0.2, seed=17)
    pts = []
    for p in base:
        rel = (ang(c, p) + math.pi) / (2.0 * math.pi)
        pull = 8.0 * math.exp(-((rel - 0.35) / 0.10) ** 2)
        d = dist(c, p)
        pts.append((c[0] + (p[0] - c[0]) * (d - pull) / d,
                    c[1] + (p[1] - c[1]) * (d - pull) / d))
    n = len(dedupe(pts))
    one = no_chains(pts, "ROUnd", "Square", 1.0)
    run = fit_and_snap(pts, "ROUnd", "Square", 1.0, 0.15, False, False)
    got = len(run["chain"])
    assert got <= n // ARC_PTS_MIN, (got, n)
    assert got > 6, got                    # past every old fixed cap
    assert run["worst"] < one["worst"] * BOTH_EDGE
    assert run["kink"] <= TANG_TOL * max(TANG_STEPS) + 1.0e-9
    print("  %d points on the outline, %d arcs (a third of them would "
          "be %d): %.2f\" -> %.2f\""
          % (n, got, n // ARC_PTS_MIN, one["worst"], run["worst"]))


def test_a_caved_round_pool():
    c = (77.0, -33.0)
    circle = [((c[0] + 108.0, c[1]), (c[0] - 108.0, c[1]), 1.0),
              ((c[0] - 108.0, c[1]), (c[0] + 108.0, c[1]), 1.0)]
    base = survey(circle, 14.0, 0.2, seed=17)

    def dip(depth):
        out = []
        for p in base:
            rel = (ang(c, p) + math.pi) / (2.0 * math.pi)
            pull = depth * math.exp(-((rel - 0.35) / 0.10) ** 2)
            d = dist(c, p)
            out.append((c[0] + (p[0] - c[0]) * (d - pull) / d,
                        c[1] + (p[1] - c[1]) * (d - pull) / d))
        return out

    true = fit_and_snap(dip(0.0), "ROUnd", "Square", 1.0, 0.15, False,
                        False)
    assert not true.get("chain"), true.get("chain")
    assert close(get_dim(true, "RAD"), 108.0, 1e-6)
    caved = dip(5.0)
    one = no_chains(caved, "ROUnd", "Square", 1.0)
    run = fit_and_snap(caved, "ROUnd", "Square", 1.0, 0.15, False, False)
    assert one["worst"] > 2.0 and run["worst"] < 1.0, \
        (one["worst"], run["worst"])
    assert len(run["chain"]) >= 3, run["chain"]
    print("  a caved round pool: one circle %.2f\" off, %d arcs %.2f\""
          % (one["worst"], len(run["chain"]), run["worst"]))


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

    def vmfit(pts, ptype, treat, pct=MISS_PCT, oos=False, bowed=False):
        vm = VM()
        vm.load(LISP_FILE)
        lst = "(list " + " ".join("(list %r %r)" % (p[0], p[1])
                                  for p in pts) + ")"
        vm.loads('(setq fit-test-res (fit:fit-and-snap %s "%s" "%s" '
                 '1.0 %r %s %s))'
                 % (lst, ptype, treat, pct, "T" if oos else "nil",
                    "T" if bowed else "nil"))
        return vm

    # rectangle with radius corners
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [96.0, 192.0, 96.0, 192.0], "Radius", 24.0,
        set(range(4))))
    pts = survey(place(true, 17.0, 100.0, 50.0), 22.0, 0.35, seed=7)
    py = fit_and_snap(pts, "Rectangle", "Radius", 1.0, MISS_PCT, False, False)
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
    py = fit_and_snap(pts, "ROman", "Square", 1.0, MISS_PCT, False, False)
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
    py = fit_and_snap(pts, "LAzyl", "Radius", 1.0, MISS_PCT, False, False)
    vm = vmfit(pts, "LAzyl", "Radius")
    lv = vm.loads("(fit:get-dim fit-test-res 'SIZE)")
    assert abs(lv - get_dim(py, "SIZE")) < 1.0e-6, lv
    lv = vm.loads("(fit:rget fit-test-res 'worst)")
    assert abs(lv - py["worst"]) < 1.0e-6, lv

    # a grecian with eased as-built corners - the vertex-easing path
    offs = grec_cuts(GREC_DIRS,
                     [0.0, 0.0, 350.0, 0.0, 180.0, 0.0, 0.0, 0.0],
                     36.0)[1]
    true = verts_to_segs(build_polygon(GREC_DIRS, offs, "Radius", 8.0,
                                       set(range(8))))
    pts = survey(place(true, 71.0, -50.0, 800.0), 14.0, 0.3, seed=23)
    py = fit_and_snap(pts, "Grecian", "Radius", 1.0, MISS_PCT, False, False)
    vm = vmfit(pts, "Grecian", "Radius")
    for key in ("LEN", "WID", "CUT", "VSIZE"):
        lv = vm.loads("(fit:get-dim fit-test-res '%s)" % key)
        assert abs(lv - get_dim(py, key)) < 1.0e-6, (key, lv)

    # bowed walls - the whole bow pass through the real .lsp
    true = verts_to_segs(build_polygon(
        RECT_DIRS, [96.0, 192.0, 96.0, 192.0], "Square", None, set(),
        [3.0, 0.0, 3.0, 0.0]))
    pts = survey(place(true, 17.0, 100.0, 50.0), 18.0, 0.25, seed=41)
    py = fit_and_snap(pts, "Rectangle", "Square", 1.0, MISS_PCT, False, True)
    vm = vmfit(pts, "Rectangle", "Square", MISS_PCT, False, True)
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
        py = fit_and_snap(pts, "Rectangle", "Square", 1.0, pct, False,
                          False)
        vm = vmfit(pts, "Rectangle", "Square", pct, False, False)
        lv = vm.loads("(fit:get-dim fit-test-res 'LEN)")
        assert abs(lv - get_dim(py, "LEN")) < 1.0e-6, (pct, lv)
        assert vm.loads("(fit:rget fit-test-res 'allow)") == py["allow"]

    # out of square - the whole wall-swing refinement through the .lsp
    dirs = list(RECT_DIRS)
    dirs[1] += math.radians(2.5)
    true = verts_to_segs(build_polygon(dirs, [96.0, 192.0, 96.0, 192.0],
                                       "Square", None, set()))
    pts = survey(place(true, 17.0, 100.0, 50.0), 18.0, 0.25, seed=61)
    py = fit_and_snap(pts, "Rectangle", "Square", 1.0, MISS_PCT, True,
                      False)
    vm = vmfit(pts, "Rectangle", "Square", MISS_PCT, True, False)
    ld = vm.loads("(fit:rget fit-test-res 'dirs)")
    for a, b in zip(ld, py["dirs"]):
        assert abs(a - b) < 1.0e-9, (ld, py["dirs"])
    lw = vm.loads("(fit:rget fit-test-res 'worst)")
    assert abs(lw - py["worst"]) < 1.0e-6, (lw, py["worst"])
    assert lw < 0.6, lw
    # and the report it drives: every side, the diagonals, the skew
    lines = vm.loads("(fit:square-lines fit-test-res)")
    labels = [str(x.a) for x in lines]
    assert labels[:4] == ["Side A-B", "Side B-C", "Side C-D",
                          "Side D-A"], labels
    assert "Diagonal A-C" in labels and "Diagonal B-D" in labels
    assert labels[-1] == "Out of square by", labels

    # a Roman whose walls lean apart: the independent wall fit, the
    # clamp and the frame-angle search, all through the .lsp
    pts = survey(place(leaning_cap("ROman", 0.0, 8.0), 197.0, 500.0,
                       300.0), 22.0, 0.25, seed=907)
    py = fit_and_snap(pts, "ROman", "Square", 1.0, MISS_PCT, True, False)
    vm = vmfit(pts, "ROman", "Square", MISS_PCT, True, False)
    lw = vm.loads("(fit:rget fit-test-res 'worst)")
    assert abs(lw - py["worst"]) < 1.0e-6, (lw, py["worst"])
    la = vm.loads("(fit:rget fit-test-res 'angle)")
    assert abs(la - py["angle"]) < 1.0e-9, (la, py["angle"])
    for k in ("sb", "st"):
        lv = vm.loads("(fit:pget (fit:rget fit-test-res 'prm) '%s)" % k)
        assert abs(lv - py["prm"][k]) < 1.0e-9, (k, lv, py["prm"][k])
    ld = vm.loads("(fit:cap-divergence (fit:rget fit-test-res 'prm))")
    assert abs(ld - cap_divergence(py["prm"])) < 1.0e-9, ld
    assert abs(math.degrees(ld) - 8.0) < 0.6, math.degrees(ld)
    labels = [str(x.a) for x in vm.loads("(fit:square-lines fit-test-res)")]
    assert labels[-1] == "Side walls off parallel", labels

    # a corner a single radius cannot hold: the polygon run pass, the
    # vert map that names it and the splice, all through the .lsp
    pts = oval_corner(1.12, 0.88)
    py = fit_and_snap(pts, "Rectangle", "Radius", 1.0, MISS_PCT, False,
                      False)
    vm = vmfit(pts, "Rectangle", "Radius", MISS_PCT, False, False)
    lw = vm.loads("(fit:rget fit-test-res 'worst)")
    assert abs(lw - py["worst"]) < 1.0e-6, (lw, py["worst"])
    lr = vm.loads("(fit:rget fit-test-res 'runs)")
    assert lr and len(lr) == len(py["runs"]), (lr, py["runs"])
    for got, want in zip(lr, py["runs"]):
        assert str(got[0].a).lower() == want[0][0], (got[0], want[0])
        assert got[0].b == want[0][1], (got[0], want[0])
        assert got[1] == want[1], (got[1], want[1])
        assert abs(got[2] - want[2]) < 1.0e-9, (got[2], want[2])
    lines = vm.loads("(fit:chain-lines fit-test-res)")
    assert lines and "is a run of" in str(lines[0].a), lines
    assert "joints smooth to" in str(lines[0].b), lines

    # a caved end, and a caved round pool: the arc-chain pass end to end
    pts = caved_oval(6.0)
    py = fit_and_snap(pts, "Oval", "Square", 1.0, MISS_PCT, False, False)
    vm = vmfit(pts, "Oval", "Square", MISS_PCT, False, False)
    lw = vm.loads("(fit:rget fit-test-res 'worst)")
    assert abs(lw - py["worst"]) < 1.0e-6, (lw, py["worst"])
    lc = vm.loads("(fit:rget fit-test-res 'chains)")
    assert lc and [0 if c is None else len(c) for c in lc] == \
        [0 if c is None else len(c) for c in py["chains"]], lc
    # every arc of every run, and how smooth the joints came out
    for c, pc in zip(lc, py["chains"]):
        if not pc:
            continue
        for arc, parc in zip(c, pc):
            assert abs(arc[1] - parc[1]) < 1.0e-9, (arc, parc)
    lk = vm.loads("(fit:rget fit-test-res 'kinks)")
    for a, b in zip(lk, py["kinks"]):
        assert abs(a - b) < 1.0e-9, (lk, py["kinks"])
    assert max(lk) <= TANG_TOL * max(TANG_STEPS) + 1.0e-9, lk
    lines = vm.loads("(fit:chain-lines fit-test-res)")
    assert lines and all("run of" in str(x.a) for x in lines), lines

    c = (77.0, -33.0)
    circle = [((c[0] + 108.0, c[1]), (c[0] - 108.0, c[1]), 1.0),
              ((c[0] - 108.0, c[1]), (c[0] + 108.0, c[1]), 1.0)]
    pts = []
    for p in survey(circle, 14.0, 0.2, seed=17):
        rel = (ang(c, p) + math.pi) / (2.0 * math.pi)
        pull = 5.0 * math.exp(-((rel - 0.35) / 0.10) ** 2)
        d = dist(c, p)
        pts.append((c[0] + (p[0] - c[0]) * (d - pull) / d,
                    c[1] + (p[1] - c[1]) * (d - pull) / d))
    py = fit_and_snap(pts, "ROUnd", "Square", 1.0, MISS_PCT, False, False)
    vm = vmfit(pts, "ROUnd", "Square", MISS_PCT, False, False)
    lw = vm.loads("(fit:rget fit-test-res 'worst)")
    assert abs(lw - py["worst"]) < 1.0e-6, (lw, py["worst"])
    assert len(vm.loads("(fit:rget fit-test-res 'chain)")) == \
        len(py["chain"])

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
    vm.script = ["Rectangle", "Radius", 1.5, 25, "Outofsquare", "Yes"]
    vm.prompts = []
    got = vm.loads('(fit:ask-settings (list "Rectangle" "Square" 1.0'
                   ' 0.15 nil nil) 7)')
    assert got[0] == "Rectangle" and got[1] == "Radius"
    assert abs(got[2] - 1.5) < 1e-9 and abs(got[3] - 0.25) < 1e-9
    assert got[4] and got[5] and not vm.script, (got, vm.script)
    asked = " ".join(p for p, _ in vm.prompts)
    for want in ("Step 1 of 7", "Percent of points allowed beyond",
                 "Insquare/Outofsquare", "Any bowed walls?"):
        assert want in asked, want

    # Back steps back exactly one question, every time
    vm = VM()
    vm.load(LISP_FILE)
    vm.script = ["Grecian", "Cut", "Back", "Radius", 2.0, "Back",
                 2.0, 40, "Back", 55, "Insquare", "Back", "Outofsquare",
                 "No"]
    vm.prompts = []
    got = vm.loads('(fit:ask-settings (list "Rectangle" "Square" 1.0'
                   ' 0.15 nil nil) 6)')
    assert got[0] == "Grecian" and got[1] == "Radius"
    assert abs(got[2] - 2.0) < 1e-9 and abs(got[3] - 0.55) < 1e-9
    assert got[4] and got[5] is None and not vm.script, (got, vm.script)
    # the way back offers what was already answered
    assert any("<40>" in p for p, _ in vm.prompts), \
        "the percent question did not offer the previous answer"
    # a round pool is never asked about bowed walls
    vm = VM()
    vm.load(LISP_FILE)
    vm.script = ["ROUnd", 1.0, None]
    vm.prompts = []
    got = vm.loads('(fit:ask-settings (list "ROUnd" "Square" 1.0 0.15'
                   ' nil nil) 6)')
    assert got[4] is None and got[5] is None and not vm.script
    assert not any("bowed" in p or "square" in p for p, _ in vm.prompts)
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
               "fit:fit-wall-line", "fit:refine-walls", "fit:keep-bow",
               "fit:solve-lin", "fit:swung-wall", "fit:flat-rms",
               "fit:grec-cut-dir", "fit:grec-axis-corners",
               "fit:square-lines", "fit:corner-zone-of",
               "fit:fit-arc-run", "fit:arc-chain", "fit:round-chain",
               "fit:cap-chains", "fit:apply-arc-chains",
               "fit:best-bulge", "fit:bulge-3pt", "fit:chain-lines",
               "fit:order-along-arc",
               "fit:bow-bulge", "fit:fit-cap-bows",
               "fit:apply-refinement", "fit:square-lines-poly",
               "fit:wall-y", "fit:cap-cy", "fit:cap-half",
               "fit:poly-vert-map", "fit:splice-run", "fit:poly-chains",
               "fit:index-of",
               "fit:end-tangent", "fit:start-tangent", "fit:tang-window",
               "fit:end-window", "fit:isect-win", "fit:clamp-bulge",
               "fit:best-bulge-win", "fit:smooth-bulge", "fit:chain-kink",
               "fit:kink-text",
               "fit:cap-wall", "fit:cap-slopes", "fit:cap-divergence",
               "fit:cap-at", "fit:refine-cap-angle",
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
    assert float(setq_value("oos-min")) == OOS_MIN
    assert "fit:*arc-max*" not in src, \
        "the fixed ceiling on a run is gone - N/3 is the only limit"
    assert int(setq_value("arc-pts-min")) == ARC_PTS_MIN
    m = re.search(r"\(setq\s+fit:\*oos-max\*\s+\(/\s+pi\s+([0-9.]+)\)", src)
    assert m and abs(math.pi / float(m.group(1)) - OOS_MAX) < 1e-12
    m = re.search(r"\(setq\s+fit:\*cap-oos-max\*\s+\(/\s+pi\s+([0-9.]+)\)",
                  src)
    assert m and abs(math.pi / float(m.group(1)) - CAP_OOS_MAX) < 1e-12
    m = re.search(r"\(setq\s+fit:\*tang-tol\*\s+\(/\s+pi\s+([0-9.]+)\)",
                  src)
    assert m and abs(math.pi / float(m.group(1)) - TANG_TOL) < 1e-12
    m = re.search(r"\(setq\s+fit:\*tang-steps\*\s+'\(([^)]*)\)", src)
    assert m, "could not read fit:*tang-steps*"
    assert tuple(float(x) for x in m.group(1).split()) == TANG_STEPS
    assert '"Insquare Outofsquare"' in src, \
        "the squareness question no longer uses POOL's vocabulary"
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
    test_out_of_square_is_honoured()
    test_a_square_pool_stays_square()
    test_a_swing_too_far_is_refused()
    test_out_of_square_l_and_grecian()
    test_a_tapered_cap_body_is_honoured()
    test_a_true_cap_body_stays_parallel()
    test_side_walls_need_not_be_parallel()
    test_walls_further_apart_than_the_limit_are_clamped()
    test_percent_buys_nice_dimensions()
    test_snap_never_pushes_past_the_tolerance()
    test_bowed_walls_are_found()
    test_a_straight_wall_stays_straight()
    test_bow_never_moves_a_corner()
    test_oval_side_walls_bow()
    test_a_caved_end_becomes_a_run_of_arcs()
    test_a_true_end_stays_one_arc()
    test_arc_chain_joints_sit_on_survey_points()
    test_a_run_of_arcs_stays_smooth()
    test_a_run_keeps_hugging_while_it_earns()
    test_a_corner_can_be_a_run_of_arcs()
    test_a_true_corner_stays_one_arc()
    test_a_run_may_reach_a_third_of_the_points()
    test_a_caved_round_pool()
    test_hopper_layout()
    test_lisp_engine_matches_mirror()
    test_the_questions_run_and_step_back()
    test_leaving_points_out_toggles()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
