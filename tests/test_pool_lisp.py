"""Python mirror of the pool_layout_lisp/POOL.LSP geometry.

AutoLISP cannot be executed outside AutoCAD, so the fitting algorithms
(four-bar side-true fit, banded relaxation, exact triangle build,
Grecian end solver) are reimplemented here 1:1 and exercised against
known-good and known-bad measurement sets.  Run: python3 tests/test_pool_lisp.py
"""
import math

D2R = math.pi / 180.0

def dist(p, q):
    return math.hypot(p[0] - q[0], p[1] - q[1])

def circint(c1, r1, c2, r2, side):
    d = dist(c1, c2)
    if d <= 1e-9:
        return None
    ux = (c2[0] - c1[0]) / d
    uy = (c2[1] - c1[1]) / d
    a = (d * d + r1 * r1 - r2 * r2) / (2.0 * d)
    h2 = r1 * r1 - a * a
    if h2 <= -1e-6:
        return None
    h = math.sqrt(max(h2, 0.0))
    bx = c1[0] + a * ux
    by = c1[1] + a * uy
    return (bx + side * h * (-uy), by + side * h * ux)

def quadmeas(q):
    a, b, c, d = q
    return (dist(a, b), dist(d, c), dist(a, d), dist(b, c), dist(a, c), dist(b, d))

def diagerr(q, dac, dbd):
    e1 = (dist(q[0], q[2]) - dac) if dac else 0.0
    e2 = (dist(q[1], q[3]) - dbd) if dbd else 0.0
    return e1 * e1 + e2 * e2

def fourbar(bo, tp, le, ri, alfa):
    a = (0.0, 0.0)
    b = (bo, 0.0)
    d = (le * math.cos(alfa), le * math.sin(alfa))
    c1 = circint(b, ri, d, tp, 1.0)
    c2 = circint(b, ri, d, tp, -1.0)
    if c1 and c2:
        c = c1 if dist(a, c1) > dist(a, c2) else c2
    else:
        c = c1 or c2
    return (a, b, c, d) if c else None

def scanalfa(bo, tp, le, ri, dac, dbd, a0, a1, step):
    best, bestq = 1e30, None
    alfa = a0
    while alfa <= a1:
        q = fourbar(bo, tp, le, ri, alfa)
        if q:
            e = diagerr(q, dac, dbd)
            if e < best:
                best, bestq = e, (q, alfa)
        alfa += step
    return bestq

def fitsides(bo, tp, le, ri, dac, dbd):
    if dac is None and dbd is None:
        return fourbar(bo, tp, le, ri, 90 * D2R)
    r1 = scanalfa(bo, tp, le, ri, dac, dbd, 15 * D2R, 165 * D2R, 0.25 * D2R)
    if not r1:
        return None
    alfa = r1[1]
    r2 = scanalfa(bo, tp, le, ri, dac, dbd, alfa - 0.3 * D2R, alfa + 0.3 * D2R, 0.005 * D2R)
    return (r2 or r1)[0]

def relax1(pts, i, j, lo, hi, w):
    p, q = pts[i], pts[j]
    d = dist(p, q)
    if d > 1e-9:
        des = min(max(d, lo), hi)
        err = d - des
        if err != 0.0:
            ux = (q[0] - p[0]) / d
            uy = (q[1] - p[1]) / d
            e2 = 0.5 * w * err
            pts[i] = (p[0] + e2 * ux, p[1] + e2 * uy)
            pts[j] = (q[0] - e2 * ux, q[1] - e2 * uy)
    return pts

def normquad(pts):
    ax, ay = pts[0]
    pts = [(x - ax, y - ay) for x, y in pts]
    ang = -math.atan2(pts[1][1], pts[1][0])
    ca, sa = math.cos(ang), math.sin(ang)
    pts = [(x * ca - y * sa, x * sa + y * ca) for x, y in pts]
    if pts[3][1] < 0:
        pts = [(x, -y) for x, y in pts]
    return pts

def relaxquad(pts, bo, tp, le, ri, dac, dbd, stol, niter):
    pts = list(pts)
    cons = []
    if dac: cons.append((0, 2, dac, dac, 0.5))
    if dbd: cons.append((1, 3, dbd, dbd, 0.5))
    cons += [(0, 1, bo - stol, bo + stol, 1.0),
            (3, 2, tp - stol, tp + stol, 1.0),
            (0, 3, le - stol, le + stol, 1.0),
            (1, 2, ri - stol, ri + stol, 1.0)]
    for _ in range(niter):
        for c in cons:
            pts = relax1(pts, *c)
    return normquad(pts)

def fitquad(bo, tp, le, ri, dac, dbd, stol=1.0, xtol=2.0):
    q1 = fitsides(bo, tp, le, ri, dac, dbd)
    if q1 is None:
        q1 = [(0, 0), (bo, 0), (bo, 0.5 * (le + ri)), (0, le)]
    m1 = quadmeas(q1)
    if ((dac is None or abs(m1[4] - dac) <= xtol)
            and (dbd is None or abs(m1[5] - dbd) <= xtol)):
        return q1, False
    q2 = relaxquad(q1, bo, tp, le, ri, dac, dbd, stol, 2000)
    m2 = quadmeas(q2)
    sok = (abs(m2[0] - bo) <= stol + 0.05 and abs(m2[1] - tp) <= stol + 0.05
           and abs(m2[2] - le) <= stol + 0.05 and abs(m2[3] - ri) <= stol + 0.05)
    xok = ((dac is None or abs(m2[4] - dac) <= xtol + 0.05)
           and (dbd is None or abs(m2[5] - dbd) <= xtol + 0.05))
    if sok and xok:
        return q2, False
    return q1, True

def triquad(bo, tp, le, ri, dac):
    a = (0.0, 0.0)
    b = (bo, 0.0)
    c = circint(a, dac, b, ri, 1.0)
    if not c:
        return None
    d = circint(a, le, c, tp, 1.0)
    return (a, b, c, d) if d else None

def grecf(w, lt, lb, th):
    return math.hypot(w - (lt + lb) * math.sin(th), (lt - lb) * math.cos(th))

def grecth(w, lt, lb, e):
    best, berr = 0.7854, 1e30
    th = 0.0175
    while th < 1.5533:
        dd = abs(grecf(w, lt, lb, th) - e)
        if dd < berr:
            berr, best = dd, th
        th += 0.00087
    return best, berr

def grecfit(w, lt, lb, e, step=0.125, n=4):
    for s in range(0, 2 * n + 1):
        for i in range(-n, n + 1):
            for j in range(-n, n + 1):
                if abs(i) + abs(j) != s:
                    continue
                lt2, lb2 = lt + step * i, lb + step * j
                if lt2 <= 0 or lb2 <= 0:
                    continue
                th, err = grecth(w, lt2, lb2, e)
                if err <= 0.0625:
                    return lt2, lb2, th
    return None

def report(name, q, targets):
    m = quadmeas(q)
    labels = ("BOT", "TOP", "LEFT", "RIGHT", "AC", "BD")
    print(f"  {name}: " + "  ".join(f"{l}={v:.3f}({v-t:+.3f})"
                                    for l, v, t in zip(labels, m, targets)))

# ---------------- tests ----------------
print("== 1. perfect 240x120 rectangle ==")
diag = math.hypot(240, 120)
q, failed = fitquad(240, 240, 120, 120, diag, diag)
report("fit", q, (240, 240, 120, 120, diag, diag))
assert not failed
m = quadmeas(q)
assert all(abs(m[i] - t) < 0.01 for i, t in enumerate((240, 240, 120, 120, diag, diag)))

print("== 2. slightly out-of-square (consistent-ish field dims) ==")
# true quad: A=(0,0) B=(240.5,0) C=(239.8,120.4) D=(1.2,119.9)
A, B, C, D = (0, 0), (240.5, 0), (239.8, 120.4), (1.2, 119.9)
t = quadmeas((A, B, C, D))
# round to nearest 1/4" as a field crew would
t = tuple(round(v * 4) / 4 for v in t)
q, failed = fitquad(*t)
report("fit", q, t)
assert not failed, "should fit within tolerance"
m = quadmeas(q)
assert all(abs(m[i] - t[i]) < 1.02 for i in range(4)), "sides"
assert all(abs(m[i] - t[i]) < 2.02 for i in (4, 5)), "diags"

print("== 3. bad cross dims (impossible) -> CROSS DIMS FAILED ==")
# both diagonals 6" long in the same direction: even growing all sides
# by the full 1" band only buys ~1.5" of diagonal -> must fail
q, failed = fitquad(240, 240, 120, 120, diag + 6, diag + 6)
report("fit", q, (240, 240, 120, 120, diag + 6, diag + 6))
assert failed, "must flag failure"
m = quadmeas(q)
# sides must be held true in the failure case
assert all(abs(m[i] - t) < 0.01 for i, t in enumerate((240, 240, 120, 120)))

print("== 4. cross dims off but recoverable inside the 2\" band ==")
q, failed = fitquad(240, 240, 120, 120, diag - 1.5, diag + 1.5)
report("fit", q, (240, 240, 120, 120, diag - 1.5, diag + 1.5))
assert not failed
m = quadmeas(q)
assert abs(m[4] - (diag - 1.5)) <= 2.02 and abs(m[5] - (diag + 1.5)) <= 2.02

print("== 5. cross dims needing the side band (relax phase) ==")
# skew both diagonals the same way: impossible with exact sides,
# check the relax phase respects the 1" side band
q, failed = fitquad(240, 240, 120, 120, diag + 2.4, diag + 2.4)
report("fit", q, (240, 240, 120, 120, diag + 2.4, diag + 2.4))
m = quadmeas(q)
if not failed:
    assert all(abs(m[i] - t) <= 1.06 for i, t in enumerate((240, 240, 120, 120))), "side band"
    assert abs(m[4] - (diag + 2.4)) <= 2.06 and abs(m[5] - (diag + 2.4)) <= 2.06
print("   failed flag:", failed)

print("== 6. exact triangles ==")
tq = triquad(240, 240, 120, 120, diag)
report("tri", tq, (240, 240, 120, 120, diag, diag))
m = quadmeas(tq)
for i, t in zip((0, 1, 2, 3, 4), (240, 240, 120, 120, diag)):
    assert abs(m[i] - t) < 1e-6, "triangles must hold lengths exactly"

print("== 7. grecian: fits by angle only ==")
r = grecfit(120.0, 40.0, 40.0, 63.0)
assert r, "should fit"
lt2, lb2, th = r
print(f"   lt={lt2} lb={lb2} theta={th/D2R:.2f} deg  width={grecf(120, lt2, lb2, th):.3f}")
assert lt2 == 40.0 and lb2 == 40.0, "no length adjustment needed"
assert abs(grecf(120, lt2, lb2, th) - 63.0) <= 0.0625

print("== 8. grecian: needs 1/8\" length adjustments ==")
# W=120, lt=lb=28, e=63 -> need (W-e)/(lt+lb)=57/56>1: angle alone can't
r = grecfit(120.0, 28.0, 28.0, 63.0)
print("   result:", r)
assert r, "should fit after adjusting lengths within 1/2\""
lt2, lb2, th = r
assert abs(lt2 - 28.0) <= 0.5 + 1e-9 and abs(lb2 - 28.0) <= 0.5 + 1e-9
assert abs(grecf(120, lt2, lb2, th) - 63.0) <= 0.0625

print("== 9. grecian: impossible -> end failed ==")
r = grecfit(120.0, 28.0, 28.0, 40.0)   # needs (120-40)/56 = 1.43 > 1 even at +1/2"
print("   result:", r)
assert r is None

print("== 10. grecian: asymmetric diagonals ==")
r = grecfit(120.0, 42.0, 38.0, 62.5)
assert r
lt2, lb2, th = r
print(f"   lt={lt2} lb={lb2} theta={th/D2R:.2f} deg  width={grecf(120, lt2, lb2, th):.3f}")


# ---------------- hexagon (L / Lazy L) mirror ----------------
HEXSIDES = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)]
HEXDIAGS = [(0, 2), (1, 3), (2, 4), (3, 5), (0, 4), (1, 5), (0, 3), (1, 4), (2, 5)]

def normpoly(pts):
    ax, ay = pts[0]
    pts = [(x - ax, y - ay) for x, y in pts]
    ang = -math.atan2(pts[1][1], pts[1][0])
    ca, sa = math.cos(ang), math.sin(ang)
    pts = [(x * ca - y * sa, x * sa + y * ca) for x, y in pts]
    if sum(p[1] for p in pts) < 0:
        pts = [(x, -y) for x, y in pts]
    return pts

def relaxn(pts, cons, niter):
    pts = list(pts)
    for _ in range(niter):
        for c in cons:
            pts = relax1(pts, *c)
    return normpoly(pts)

def hexguess(sides, lazy):
    ab, bc, cd, de, ef, fa = sides
    a, b = (0.0, 0.0), (ab, 0.0)
    if lazy:
        c = (b[0] + bc * 0.7071067812, bc * 0.7071067812)
        d = (c[0] - cd * 0.7071067812, c[1] + cd * 0.7071067812)
        e = (d[0] - de * 0.7071067812, d[1] - de * 0.7071067812)
        f = (0.0, fa)
    else:
        c = (ab, bc)
        d = (ab - cd, bc)
        e = (d[0], d[1] - de)
        f = (e[0] - ef, e[1])
    return [a, b, c, d, e, f]

def hexsidecon(sides, band, w):
    return [(i, j, sides[k] - band, sides[k] + band, w)
            for k, (i, j) in enumerate(HEXSIDES)]

def hexdiagcon(diags, w):
    return [(i, j, diags[k], diags[k], w)
            for k, (i, j) in enumerate(HEXDIAGS) if diags[k] is not None]

def hexerr(pts, sides, diags):
    smax = max(abs(dist(pts[i], pts[j]) - sides[k])
               for k, (i, j) in enumerate(HEXSIDES))
    xds = [abs(dist(pts[i], pts[j]) - diags[k])
           for k, (i, j) in enumerate(HEXDIAGS) if diags[k] is not None]
    return smax, max(xds) if xds else 0.0

def fithex(sides, diags, lazy, stol=1.0, xtol=2.0):
    p1 = relaxn(hexguess(sides, lazy),
                hexdiagcon(diags, 0.4) + hexsidecon(sides, 0.0, 1.0), 3000)
    p1 = relaxn(p1, hexsidecon(sides, 0.0, 1.0), 400)
    e1 = hexerr(p1, sides, diags)
    if e1[1] <= xtol:
        return p1, False
    p2 = relaxn(p1, hexdiagcon(diags, 0.5) + hexsidecon(sides, stol, 1.0), 3000)
    e2 = hexerr(p2, sides, diags)
    if e2[0] <= stol + 0.05 and e2[1] <= xtol + 0.05:
        return p2, False
    return p1, True

def inpoly(p, poly):
    x, y = p
    n = len(poly)
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and x < xi + (xj - xi) * (y - yi) / (yj - yi):
            inside = not inside
        j = i
    return inside

def hexmeas(pts):
    sides = [dist(pts[i], pts[j]) for i, j in HEXSIDES]
    diags = [dist(pts[i], pts[j]) for i, j in HEXDIAGS]
    return sides, diags

print("== 11. quad with both cross dims NA -> squares up, no failure ==")
q, failed = fitquad(240, 240, 120, 120, None, None)
report("fit", q, (240, 240, 120, 120, dist(q[0], q[2]), dist(q[1], q[3])))
assert not failed
m = quadmeas(q)
assert all(abs(m[i] - t) < 0.01 for i, t in enumerate((240, 240, 120, 120)))
assert abs(m[4] - m[5]) < 0.01, "no cross dims -> symmetric (square) quad"

print("== 12. quad with one cross dim NA -> skews to match the other ==")
diag = math.hypot(240, 120)
q, failed = fitquad(240, 240, 120, 120, diag + 1.2, None)
assert not failed
m = quadmeas(q)
assert abs(m[4] - (diag + 1.2)) <= 2.0, "provided cross dim honoured"

print("== 13. perfect true L ==")
TRUE_L = [(0, 0), (480, 0), (480, 420), (300, 420), (300, 240), (0, 240)]
sides, diags = hexmeas(TRUE_L)
pts, failed = fithex(sides, diags, lazy=False)
s, x = hexerr(pts, sides, diags)
print(f"   max side delta {s:.4f}, max cross delta {x:.4f}")
assert not failed and s < 0.05 and x < 0.1

print("== 14. out-of-square true L (field dims, 1/4\" rounding) ==")
SKEW_L = [(0, 0), (480.7, 0.3), (479.2, 420.6), (300.4, 421.1), (299.6, 240.8), (-0.5, 239.9)]
sides, diags = hexmeas(SKEW_L)
sides = [round(v * 4) / 4 for v in sides]
diags = [round(v * 4) / 4 for v in diags]
pts, failed = fithex(sides, diags, lazy=False)
s, x = hexerr(pts, sides, diags)
print(f"   max side delta {s:.3f}, max cross delta {x:.3f}, failed={failed}")
assert not failed and s <= 1.05 and x <= 2.05

print("== 15. true L with half the cross dims NA ==")
sides, diags = hexmeas(SKEW_L)
diags = [diags[0], None, diags[2], None, diags[4], None, diags[6], None, diags[8]]
pts, failed = fithex(sides, diags, lazy=False)
s, x = hexerr(pts, sides, diags)
print(f"   max side delta {s:.3f}, max cross delta {x:.3f}")
assert not failed and x <= 2.05

print("== 16. impossible L cross dims -> CROSS DIMS FAILED, sides true ==")
sides, diags = hexmeas(TRUE_L)
diags = [d + 8.0 for d in diags]      # every diagonal 8\" long: hopeless
pts, failed = fithex(sides, diags, lazy=False)
s, x = hexerr(pts, sides, diags)
print(f"   max side delta {s:.4f}, max cross delta {x:.3f}, failed={failed}")
assert failed and s < 0.05, "failure path must hold sides true"

print("== 17. perfect lazy L (reference DXF geometry) ==")
LAZY_L = [(0.0, 0.0), (422.28, 0.0), (591.98, 169.70),
          (422.28, 339.41), (322.87, 240.0), (0.0, 240.0)]
sides, diags = hexmeas(LAZY_L)
diags = list(diags)
diags[HEXDIAGS.index((1, 4))] = None      # the bend joint is not taped
pts, failed = fithex(sides, diags, lazy=True)
s, x = hexerr(pts, sides, diags)
print(f"   max side delta {s:.4f}, max cross delta {x:.4f}")
assert not failed and s < 0.05 and x < 0.15

print("== 18. point-in-polygon (dim placement) ==")
assert inpoly((180, 70), TRUE_L)          # main body
assert inpoly((400, 350), TRUE_L)         # wing (top right)
assert not inpoly((150, 350), TRUE_L)     # the notch (top left)
assert not inpoly((-10, 70), TRUE_L)      # outside left


# ---------------- Grecian 8-vertex mirror (Simple/Center/Complex) ----------------
def _sub(p,q): return (p[0]-q[0], p[1]-q[1])
def _add(p,q): return (p[0]+q[0], p[1]+q[1])
def _scl(p,s): return (p[0]*s, p[1]*s)
def _dot(p,q): return p[0]*q[0]+p[1]*q[1]
def _perp(p): return (-p[1], p[0])
def _mid(p,q): return ((p[0]+q[0])/2.0, (p[1]+q[1])/2.0)
def _unit(p):
    d=math.hypot(p[0],p[1]); return (p[0]/d, p[1]/d) if d>1e-12 else (0.0,0.0)

# index order: 0=A 1=B 2=RB 3=RT 4=C 5=D 6=LT 7=LB
GRECEDGES=[(0,1,1.0),(1,2,0.5),(2,3,0.1),(3,4,0.5),(4,5,1.0),
           (5,6,0.5),(6,7,0.1),(7,0,0.5),(0,5,1.0),(1,4,1.0)]
GREC_SIMPLE=[(0,4),(1,5)]
GREC_CENTER=[(0,4),(1,5),(7,3),(6,2)]
GREC_COMPLEX=[(0,2),(0,3),(0,4),(0,6),(1,3),(1,5),(1,6),(1,7),
              (2,4),(2,5),(2,6),(2,7),(3,5),(3,6),(3,7),(4,6),(4,7),(5,7)]

def grecendp(pbot, ptop, mdir, lt, lb, e):
    u=_unit(_sub(ptop,pbot))
    fit=grecfit(dist(pbot,ptop), lt, lb, e)
    if fit: lt2,lb2,th=fit; ok=True
    else:   lt2,lb2,th=lt,lb,math.radians(45); ok=False
    dtop=_sub(_scl(mdir,math.cos(th)), _scl(u,math.sin(th)))
    dbot=_add(_scl(mdir,math.cos(th)), _scl(u,math.sin(th)))
    return (_add(ptop,_scl(dtop,lt2)), _add(pbot,_scl(dbot,lb2)), lt2, lb2, th, ok)

def crossmax(pts, crosscons):
    mx=0.0
    for (i,j,t) in crosscons:
        if t is not None: mx=max(mx, abs(dist(pts[i],pts[j])-t))
    return mx
def edgemax(pts, edgecons):
    mx=-1e30
    for (i,j,t,b) in edgecons: mx=max(mx, abs(dist(pts[i],pts[j])-t)-b)
    return mx
def fitpoly(seed, edgecons, crosscons, xtol=2.0):
    xcon=[(i,j,t,t,0.5) for (i,j,t) in crosscons if t is not None]
    e0=[(i,j,t,t,1.0) for (i,j,t,b) in edgecons]
    eb=[(i,j,t-b,t+b,1.0) for (i,j,t,b) in edgecons]
    p1=relaxn(seed, xcon+e0, 3000); p1=relaxn(p1, e0, 400)
    if crossmax(p1,crosscons)<=xtol: return p1,False
    p2=relaxn(p1, xcon+eb, 3000)
    if edgemax(p2,edgecons)<=0.05 and crossmax(p2,crosscons)<=xtol+0.05:
        return p2,False
    return p1,True

def grec_body(P):
    d=lambda i,j: dist(P[i],P[j])
    edges=[(i,j,d(i,j),b) for (i,j,b) in GRECEDGES]
    body=(d(0,1),d(4,5),d(0,5),d(1,4),  # bo tp le ri
          d(5,6),d(7,0),d(6,7),d(3,4),d(1,2),d(2,3))  # ltd lbd lew rtd rbd rew
    return edges, body

def grec_fit(P, pairs, crossvals, mode):
    edges, body = grec_body(P)
    bo,tp,le,ri,ltd,lbd,lew,rtd,rbd,rew = body
    dac=crossvals.get((0,4)); dbd=crossvals.get((1,5))
    q,failed0 = fitquad(bo,tp,le,ri,dac,dbd)
    a,b,c,d=q
    cen0=((a[0]+b[0]+c[0]+d[0])/4.0,(a[1]+b[1]+c[1]+d[1])/4.0)
    ml=_unit(_perp(_sub(d,a)))
    if _dot(_sub(_mid(a,d),cen0),ml)<0: ml=_scl(ml,-1.0)
    mr=_unit(_perp(_sub(c,b)))
    if _dot(_sub(_mid(b,c),cen0),mr)<0: mr=_scl(mr,-1.0)
    lend=grecendp(a,d,ml,ltd,lbd,lew)
    rend=grecendp(b,c,mr,rtd,rbd,rew)
    seed=[a,b,rend[1],rend[0],c,d,lend[0],lend[1]]
    crosscons=[(i,j,crossvals.get((i,j))) for (i,j) in pairs]
    if mode=='Simple':
        return seed, failed0, edges, crosscons
    pts,failed=fitpoly(seed,edges,crosscons,2.0)
    return pts, failed, edges, crosscons

# a plausible slightly-out-of-square true Grecian, index order A B RB RT C D LT LB
TRUE_G=[(0,0),(400,0),(450,52),(452,148),(398,200),(2,201),(-48,150),(-50,55)]

def full_cross(P, pairs):
    return {(i,j): dist(P[i],P[j]) for (i,j) in pairs}

print("== 19. Grecian SIMPLE reproduces the shape ==")
pts,failed,edges,cc = grec_fit(TRUE_G, GREC_SIMPLE, full_cross(TRUE_G,GREC_SIMPLE), 'Simple')
em=edgemax(pts,edges); xm=crossmax(pts,cc)
print(f"   edgemax {em:.3f} (<=0 in band), crossmax {xm:.3f}, failed={failed}")
assert not failed and em<=0.06 and xm<=2.05

print("== 20. Grecian CENTER (adds long tip X) ==")
pts,failed,edges,cc = grec_fit(TRUE_G, GREC_CENTER, full_cross(TRUE_G,GREC_CENTER), 'Center')
em=edgemax(pts,edges); xm=crossmax(pts,cc)
print(f"   edgemax {em:.3f}, crossmax {xm:.3f}, failed={failed}")
assert not failed and em<=0.06 and xm<=2.05

print("== 21. Grecian COMPLEX (all 18 diagonals) ==")
cv=full_cross(TRUE_G,GREC_COMPLEX)
pts,failed,edges,cc = grec_fit(TRUE_G, GREC_COMPLEX, cv, 'Complex')
em=edgemax(pts,edges); xm=crossmax(pts,cc)
print(f"   edgemax {em:.3f}, crossmax {xm:.3f}, failed={failed}")
assert not failed and em<=0.06 and xm<=2.05

print("== 22. Grecian COMPLEX with field rounding (1/4\") still fits ==")
cv2={k: round(v*4)/4 for k,v in cv.items()}
Pr=[(round(x*4)/4, round(y*4)/4) for (x,y) in TRUE_G]  # rounded edges too
pts,failed,edges,cc = grec_fit(Pr, GREC_COMPLEX, cv2, 'Complex')
em=edgemax(pts,edges); xm=crossmax(pts,cc)
print(f"   edgemax {em:.3f}, crossmax {xm:.3f}, failed={failed}")
assert not failed and xm<=2.05

print("== 23. Grecian COMPLEX with some NA cross dims ==")
cv3=dict(cv)
for k in [(0,2),(2,7),(3,6),(4,7),(5,7)]: cv3[k]=None
pairs=GREC_COMPLEX
crossvals={p:(cv3[p] if cv3.get(p) is not None else None) for p in pairs}
pts,failed,edges,cc = grec_fit(TRUE_G, pairs, crossvals, 'Complex')
xm=crossmax(pts,cc)
print(f"   crossmax(provided) {xm:.3f}, failed={failed}, NA count={sum(1 for _,_,t in cc if t is None)}")
assert not failed and xm<=2.05

print("== 24. Grecian CENTER impossible cross -> CROSS DIMS FAILED, edges true ==")
cv4=full_cross(TRUE_G,GREC_CENTER); cv4[(7,3)]=cv4[(7,3)]+25.0   # tip diagonal 25\" off
pts,failed,edges,cc = grec_fit(TRUE_G, GREC_CENTER, cv4, 'Center')
em=edgemax(pts,edges)
print(f"   edgemax {em:.3f}, failed={failed}")
assert failed and em<=0.06   # sides/edges held true on failure


print("== 25. L in-square (no diags) squares up ==")
sides,_=hexmeas(TRUE_L)
pts,failed=fithex(sides,[None]*9,lazy=False)
s,x=hexerr(pts,sides,[None]*9)
print(f"   max side delta {s:.4f}, failed={failed}")
assert not failed and s<0.05

print("== 26. Grecian in-square (no cross dims) builds from sides ==")
pts,failed,edges,cc=grec_fit(TRUE_G, [], {}, 'Simple')
em=edgemax(pts,edges)
print(f"   edgemax {em:.3f} (<=0 in band), n cross rows {len(cc)}, failed={failed}")
assert not failed and em<=0.06 and len(cc)==0


# ---------------- rectangle corner treatments + cross-dim reference ----------------
def _u(p,q):
    d=math.hypot(q[0]-p[0],q[1]-p[1]); return ((q[0]-p[0])/d,(q[1]-p[1])/d) if d>1e-12 else (0,0)
def _vadd(p,v,s): return (p[0]+v[0]*s, p[1]+v[1]*s)

def cornerends(P,Pp,Pn,typ,size):
    up=_u(P,Pp); un=_u(P,Pn)
    dp=up[0]*un[0]+up[1]*un[1]
    ang=math.atan2(math.sqrt(max(0.0,1-dp*dp)), dp)
    if typ=="Diag":
        t=size/(2.0*math.sin(ang/2.0))
        return (_vadd(P,up,t), _vadd(P,un,t), None)
    if typ=="Rounded":
        t=size*math.cos(ang/2.0)/math.sin(ang/2.0)
        bx,by=up[0]+un[0], up[1]+un[1]
        bl=math.hypot(bx,by); bis=(bx/bl,by/bl)
        cen=_vadd(P,bis, size/math.sin(ang/2.0))
        return (_vadd(P,up,t), _vadd(P,un,t), _vadd(cen,bis,-size))
    return (P,P,None)

def cornerpoint(q,corners,i,spec):
    ce=cornerends(q[i], q[(i+3)%4], q[(i+1)%4], corners[i][0], corners[i][1])
    if spec=='prev': return ce[0]
    if spec=='next': return ce[1]
    if spec=='mid':  return ce[2] if ce[2] else ((ce[0][0]+ce[1][0])/2,(ce[0][1]+ce[1][1])/2)
    return q[i]

def crosstemplate(cmode):
    if cmode=="Middle":
        return [('ac',0,'mid',2,'mid'),('bd',1,'mid',3,'mid')]
    if cmode=="Ends":
        return [('ac',0,'next',2,'prev'),('ac',0,'prev',2,'next'),
                ('bd',1,'prev',3,'next'),('bd',1,'next',3,'prev')]
    return [('ac',0,'true',2,'true'),('bd',1,'true',3,'true')]

def effcross(q,corners,xmeas,diag):
    vals=[]
    for (d,iA,sA,iC,sC,val) in xmeas:
        if d==diag and val is not None:
            ra=cornerpoint(q,corners,iA,sA); rc=cornerpoint(q,corners,iC,sC)
            vals.append(val + (dist(q[iA],q[iC]) - dist(ra,rc)))
    return sum(vals)/len(vals) if vals else None

def rawavg(xmeas,diag):
    vals=[val for (d,iA,sA,iC,sC,val) in xmeas if d==diag and val is not None]
    return sum(vals)/len(vals) if vals else None

def rect_fit(TRUE, corners, cmode):
    # measure sides from true corners
    A,B,C,D=TRUE
    bo=dist(A,B); tp=dist(D,C); le=dist(A,D); ri=dist(B,C)
    # build measurements from the true shape at the reference points
    xmeas=[]
    for (d,iA,sA,iC,sC) in crosstemplate(cmode):
        pa=cornerpoint(TRUE,corners,iA,sA); pc=cornerpoint(TRUE,corners,iC,sC)
        xmeas.append((d,iA,sA,iC,sC, dist(pa,pc)))
    dac=rawavg(xmeas,'ac'); dbd=rawavg(xmeas,'bd')
    q,failed=fitquad(bo,tp,le,ri,dac,dbd)
    if cmode!="Corner":
        for _ in range(2):
            dac=effcross(q,corners,xmeas,'ac'); dbd=effcross(q,corners,xmeas,'bd')
            q,failed=fitquad(bo,tp,le,ri,dac,dbd)
    return q, xmeas, (bo,tp,le,ri)

# a mildly out-of-square rectangle (true corners)
RECT=[(0,0),(400.5,0),(399.0,239.6),(1.2,240.4)]
def check(q, RECT, sides):
    m=quadmeas(q)
    for k,t in enumerate(sides):
        assert abs(m[k]-t)<1.05, f"side {k} {m[k]} vs {t}"
def refmatch(q, corners, xmeas):
    mx=0.0
    for (d,iA,sA,iC,sC,val) in xmeas:
        act=dist(cornerpoint(q,corners,iA,sA), cornerpoint(q,corners,iC,sC))
        mx=max(mx, abs(act-val))
    return mx

print("== 27. Rounded corners, reference = true CORNER ==")
cor=[("Rounded",18.0)]*4
q,xm,sides=rect_fit(RECT,cor,"Corner"); check(q,RECT,sides)
print(f"   ref match {refmatch(q,cor,xm):.4f}")
assert refmatch(q,cor,xm)<0.06

print("== 28. Diag (chamfer face) corners, reference = MIDDLE ==")
cor=[("Diag",24.0)]*4
q,xm,sides=rect_fit(RECT,cor,"Middle"); check(q,RECT,sides)
print(f"   ref match {refmatch(q,cor,xm):.4f}")
assert refmatch(q,cor,xm)<0.10

print("== 29. Rounded corners, reference = ENDS (4 ties) ==")
cor=[("Rounded",20.0)]*4
q,xm,sides=rect_fit(RECT,cor,"Ends"); check(q,RECT,sides)
print(f"   {len(xm)} ties, ref match {refmatch(q,cor,xm):.4f}")
assert len(xm)==4 and refmatch(q,cor,xm)<0.10

print("== 30. Mixed corners (2 square, 1 diag, 1 rounded), ENDS ==")
cor=[("Square",0.0),("Diag",22.0),("Rounded",16.0),("Square",0.0)]
q,xm,sides=rect_fit(RECT,cor,"Ends"); check(q,RECT,sides)
print(f"   ref match {refmatch(q,cor,xm):.4f}")
assert refmatch(q,cor,xm)<0.12

print("== 31. Chamfer face-length geometry sanity (90deg corner) ==")
# square corner, face f -> setback f/sqrt2 along each edge
ce=cornerends((0,0),(0,100),(100,0),"Diag",20.0)  # P origin, prev up, next right
import math as _m
assert abs(dist((0,0),ce[0]) - 20.0/_m.sqrt(2))<1e-6
assert abs(dist(ce[0],ce[1]) - 20.0)<1e-6   # face length reproduced
print("   setback = face/sqrt2 and face length reproduced")

print("== 32. Rounded tangent geometry sanity (90deg corner) ==")
ce=cornerends((0,0),(0,100),(100,0),"Rounded",15.0)
assert abs(dist((0,0),ce[0]) - 15.0)<1e-6   # tangent dist = r on square corner
print("   tangent dist = r on a square corner")


# ---------------- pool bottom / hopper (rectangle pipeline) ----------------
def linex(p1,d1,p2,d2):
    den=d1[0]*d2[1]-d1[1]*d2[0]
    if abs(den)<1e-9: return None
    s=((p2[0]-p1[0])*d2[1]-(p2[1]-p1[1])*d2[0])/den
    return (p1[0]+d1[0]*s, p1[1]+d1[1]*s)

def offline(p,q,cen,d):
    n=_unit(_perp(_sub(q,p)))
    if _dot(_sub(_mid(p,q),cen),n)>0: n=_scl(n,-1.0)
    return (_add(p,_scl(n,d)), _sub(q,p))

def hopcalc(quad,corners,h,g,e,m,k):
    a,b,c,d=quad
    cen=((a[0]+b[0]+c[0]+d[0])/4.0,(a[1]+b[1]+c[1]+d[1])/4.0)
    hl=offline(a,d,cen,h); hr=offline(a,d,cen,h+g)
    ht=offline(d,c,cen,m); hb=offline(a,b,cen,k)
    brk=offline(b,c,cen,e)
    gg={}
    gg['hbl']=linex(*hl,*hb); gg['htl']=linex(*hl,*ht)
    gg['hbr']=linex(*hr,*hb); gg['htr']=linex(*hr,*ht)
    gg['brkb']=linex(*brk,a,_sub(b,a)); gg['brkt']=linex(*brk,d,_sub(c,d))
    gg['lab1']=cornerpoint(quad,corners,0,'prev')
    gg['lab2']=cornerpoint(quad,corners,0,'next')
    gg['lat1']=cornerpoint(quad,corners,3,'next')
    gg['lat2']=cornerpoint(quad,corners,3,'prev')
    hc=tuple(sum(gg[kk][i] for kk in ('hbl','htl','hbr','htr'))/4.0 for i in (0,1))
    hdir=_sub(b,a); vdir=_sub(d,a)
    off=min(12.0, dist(gg['hbr'],gg['htr'])/6.0)
    hc2=_sub(hc,_scl(_unit(vdir),off))
    gg['pl']=linex(hc2,hdir,a,_sub(d,a)); gg['phl']=linex(hc2,hdir,*hl)
    gg['phr']=linex(hc2,hdir,*hr); gg['pbrk']=linex(hc2,hdir,*brk)
    gg['pr']=linex(hc2,hdir,b,_sub(c,b))
    gg['pb']=linex(*hr,a,_sub(b,a)); gg['phb']=gg['hbr']
    gg['pht']=gg['htr']; gg['pt']=linex(*hr,d,_sub(c,d))
    gg['voff']=_scl(_unit(hdir),12.0)
    return gg

def ptlinedist(p, lp, ld):
    n=_unit(_perp(ld))
    return abs((p[0]-lp[0])*n[0]+(p[1]-lp[1])*n[1])

print("== 33. hopper on axis-aligned 400x240, square corners ==")
Q=[(0,0),(400,0),(400,240),(0,240)]
SQ=[("Square",0.0)]*4
gg=hopcalc(Q,SQ,30,60,100,45,50)
assert gg['hbl']==(30,50) and gg['htl']==(30,195)
assert gg['hbr']==(90,50) and gg['htr']==(90,195)
assert gg['brkb']==(300,0) and gg['brkt']==(300,240)
assert gg['lab1']==(0,0) and gg['lat1']==(0,240)
# chain checks
assert abs(dist(gg['pl'],gg['phl'])-30)<1e-9      # H
assert abs(dist(gg['phl'],gg['phr'])-60)<1e-9     # G
assert abs(dist(gg['phr'],gg['pbrk'])-210)<1e-9   # F check
assert abs(dist(gg['pbrk'],gg['pr'])-100)<1e-9    # E
assert abs(dist(gg['pht'],gg['pt'])-45)<1e-9      # M
assert abs(dist(gg['phb'],gg['pht'])-145)<1e-9    # L check
assert abs(dist(gg['pb'],gg['phb'])-50)<1e-9      # K
print("   all seven chain values exact")

print("== 34. hopper ties honor rounded/diag corner end-wall points ==")
COR=[("Rounded",20.0),("Square",0.0),("Square",0.0),("Diag",24.0)]
gg=hopcalc(Q,COR,30,60,100,45,50)
assert abs(gg['lab1'][0]-0)<1e-9 and abs(gg['lab1'][1]-20.0)<1e-9  # tangent point on end wall
dsb=24.0/math.sqrt(2)
assert abs(gg['lat1'][0]-0)<1e-9 and abs(gg['lat1'][1]-(240-dsb))<1e-6  # chamfer end on end wall
print(f"   lab1=(0,20) lat1=(0,{240-dsb:.3f}) -- both on the left end wall")

print("== 35. hopper offsets stay perpendicular on an out-of-square quad ==")
Q2=[(0,0),(400.5,0),(399.0,239.6),(1.2,240.4)]
gg=hopcalc(Q2,SQ,30,60,100,45,50)
a,b,c,d=Q2
# each hopper edge point sits at the exact offset from its wall
assert abs(ptlinedist(gg['hbl'],a,_sub(d,a))-30)<1e-6    # H from left end
assert abs(ptlinedist(gg['htr'],a,_sub(d,a))-90)<1e-6    # H+G
assert abs(ptlinedist(gg['htl'],d,_sub(c,d))-45)<1e-6    # M from top
assert abs(ptlinedist(gg['hbr'],a,_sub(b,a))-50)<1e-6    # K from bottom
assert abs(ptlinedist(gg['brkb'],b,_sub(c,b))-100)<1e-6  # E from right end
print("   perpendicular offsets exact on the skewed quad")


# ---------------- oval + grecian hopper geometry ----------------
def hopovalc(quad,tipl,tipr,h,g,e,m,k,r3):
    a,b,c,d=quad
    cen=((a[0]+b[0]+c[0]+d[0])/4.0,(a[1]+b[1]+c[1]+d[1])/4.0)
    u=_unit(_sub(tipr,tipl)); v=_perp(u)
    ht=offline(d,c,cen,m); hb=offline(a,b,cen,k)
    lt=(_add(tipl,_scl(u,h)),v); re=(_add(tipl,_scl(u,h+g)),v)
    tan=(_add(tipl,_scl(u,h+r3)),v); brk=(_sub(tipr,_scl(u,e)),v)
    tt=linex(*tan,*ht); tb=linex(*tan,*hb)
    tip=_mid(linex(*lt,*ht), linex(*lt,*hb))
    vc=_add(tipl,_scl(u,h+g))
    off=min(12.0, dist(linex(vc,v,*hb), linex(vc,v,*ht))/6.0)
    tip2=_sub(tip,_scl(_unit(v),off))
    gg={'tip':tip,'ttop':tt,'tbot':tb,
        'htr':linex(*re,*ht),'hbr':linex(*re,*hb),
        'brkb':linex(*brk,a,_sub(b,a)),'brkt':linex(*brk,d,_sub(c,d)),
        'ptan':linex(tip2,u,*tan),
        'pl':linex(tip2,u,tipl,v),'phl':linex(tip2,u,*lt),'phr':linex(tip2,u,*re),
        'pbrk':linex(tip2,u,*brk),'pr':linex(tip2,u,tipr,v),
        'pb':linex(vc,v,a,_sub(b,a)),'phb':linex(vc,v,*hb),
        'pht':linex(vc,v,*ht),'pt':linex(vc,v,d,_sub(c,d))}
    return gg

def hopgrecc(pts,h,g,e,m,k,w=None,l1=None):
    aa,bb,rb,rt,cc,dd,ltp,lbp=pts
    cen=(sum(p[0] for p in pts)/8.0, sum(p[1] for p in pts)/8.0)
    hl=offline(lbp,ltp,cen,h); hr=offline(lbp,ltp,cen,h+g)
    ht=offline(dd,cc,cen,m); hb=offline(aa,bb,cen,k)
    brk=offline(rb,rt,cen,e)
    hbl=linex(*hl,*hb); htl=linex(*hl,*ht); hbr=linex(*hr,*hb); htr=linex(*hr,*ht)
    hc=tuple(sum(p[i] for p in (hbl,htl,hbr,htr))/4.0 for i in (0,1))
    u=_sub(bb,aa); v=_sub(dd,aa)
    off=min(12.0, dist(hbr,htr)/6.0)
    hc2=_sub(hc,_scl(_unit(v),off))
    gg={'hbl':hbl,'htl':htl,'hbr':hbr,'htr':htr,
        'brkb':linex(*brk,aa,_sub(bb,aa)),'brkt':linex(*brk,dd,_sub(cc,dd)),
        'pl':linex(hc2,u,lbp,_sub(ltp,lbp)),'phl':linex(hc2,u,*hl),
        'phr':linex(hc2,u,*hr),'pbrk':linex(hc2,u,*brk),
        'pr':linex(hc2,u,rb,_sub(rt,rb)),
        'pb':linex(*hr,aa,_sub(bb,aa)),'phb':hbr,
        'pht':htr,'pt':linex(*hr,dd,_sub(cc,dd))}
    if w is not None:
        hlw=offline(lbp,ltp,cen,h+w); htl1=offline(dd,cc,cen,m+l1); hbl1=offline(aa,bb,cen,k+l1)
        gg['ct1']=linex(*hlw,*ht); gg['ct2']=linex(*hl,*htl1)
        gg['cb1']=linex(*hlw,*hb); gg['cb2']=linex(*hl,*hbl1)
    return gg

print("== 36. oval hopper on symmetric 400x240 oval ==")
QO=[(0,0),(400,0),(400,240),(0,240)]
gg=hopovalc(QO,(-80,120),(480,120),40,100,120,50,60,65)
assert gg['tip']==(-40.0,125.0)
assert gg['ttop']==(25.0,190.0) and gg['tbot']==(25.0,60.0)
assert gg['htr']==(60.0,190.0) and gg['hbr']==(60.0,60.0)
assert gg['brkb']==(360.0,0.0) and gg['brkt']==(360.0,240.0)
assert abs(dist(gg['pl'],gg['phl'])-40)<1e-9      # H
assert abs(dist(gg['phl'],gg['phr'])-100)<1e-9    # G
assert abs(dist(gg['phr'],gg['pbrk'])-300)<1e-9   # F check
assert abs(dist(gg['pbrk'],gg['pr'])-120)<1e-9    # E
assert abs(dist(gg['phl'],gg['ptan'])-65)<1e-9    # R3 setback
assert abs(dist(gg['ttop'],gg['htr'])-35)<1e-9    # W check = G - R3
assert abs(dist(gg['pht'],gg['pt'])-50)<1e-9      # M
assert abs(dist(gg['phb'],gg['pht'])-130)<1e-9    # L check
assert abs(dist(gg['pb'],gg['phb'])-60)<1e-9      # K
# with R3 = half hopper width the 3-point arc radius equals R3
import math as _mm
ax,ay=gg['ttop']; bx,by=gg['tip']; cx,cy=gg['tbot']
dd2=2*(ax*(by-cy)+bx*(cy-ay)+cx*(ay-by))
ux=((ax*ax+ay*ay)*(by-cy)+(bx*bx+by*by)*(cy-ay)+(cx*cx+cy*cy)*(ay-by))/dd2
uy=((ax*ax+ay*ay)*(cx-bx)+(bx*bx+by*by)*(ax-cx)+(cx*cx+cy*cy)*(bx-ax))/dd2
assert abs(dist((ux,uy),gg['tip'])-65)<1e-6
print("   tip/tangents/corners/chains and arc radius all exact")

print("== 37. grecian square hopper on symmetric 8-corner pool ==")
PG=[(0,0),(400,0),(450,50),(450,150),(400,200),(0,200),(-50,150),(-50,50)]
gg=hopgrecc(PG,30,80,110,50,45)
assert gg['hbl']==(-20.0,45.0) and gg['htl']==(-20.0,150.0)
assert gg['hbr']==(60.0,45.0) and gg['htr']==(60.0,150.0)
assert gg['brkb']==(340.0,0.0) and gg['brkt']==(340.0,200.0)
assert abs(dist(gg['pl'],gg['phl'])-30)<1e-9      # H from end wall
assert abs(dist(gg['phl'],gg['phr'])-80)<1e-9     # G
assert abs(dist(gg['phr'],gg['pbrk'])-280)<1e-9   # F check
assert abs(dist(gg['pbrk'],gg['pr'])-110)<1e-9    # E from end wall
assert abs(dist(gg['pht'],gg['pt'])-50)<1e-9      # M
assert abs(dist(gg['phb'],gg['pht'])-105)<1e-9    # L check
assert abs(dist(gg['pb'],gg['phb'])-45)<1e-9      # K
print("   square hopper chains exact, ties go to D/LT and A/LB ends")

print("== 38. grecian 6-sided hopper cuts (W, L1, X check) ==")
gg=hopgrecc(PG,30,80,110,50,45,w=25,l1=20)
assert gg['ct1']==(5.0,150.0) and gg['cb1']==(5.0,45.0)
assert gg['ct2']==(-20.0,130.0) and gg['cb2']==(-20.0,65.0)
assert abs(dist(gg['htl'],gg['ct1'])-25)<1e-9     # W
assert abs(dist(gg['htl'],gg['ct2'])-20)<1e-9     # L1
assert abs(dist(gg['ct2'],gg['ct1'])-math.sqrt(25*25+20*20))<1e-9  # X check
print(f"   cut corners exact; X = sqrt(W^2+L1^2) = {math.sqrt(1025):.4f}")


print("== 39. sport bottom profile arithmetic ==")
# Sport: anchors E2,F2 from left, F1,E1 from right; G closes the check
total=400.0; e2,f2,f1,e1=50.0,80.0,90.0,40.0
g_check=total-e2-f2-f1-e1
assert g_check==140.0
brks=[(e2,'wh'),(e2+f2,'hd'),(total-e1-f1,'hd'),(total-e1,'wh')]
assert [b[0] for b in brks]==[50.0,130.0,270.0,360.0]
# No hopper pad: anchors E2,F2,E1; F1 closes the check at the V
e2,f2,e1=60.0,140.0,50.0
f1_check=total-e1-(e2+f2)
assert f1_check==150.0
brks=[(e2,'wh'),(e2+f2,'hd'),(total-e1,'wh')]
assert [b[0] for b in brks]==[60.0,200.0,350.0]
# Normal hopper profile: slope from left wall to hopper at H, flat to
# H+G, slope up to the plan break at total-E
h,g,e=30.0,60.0,100.0
brks=[(h,'hd'),(h+g,'hd'),(total-e,'wh')]
assert [b[0] for b in brks]==[30.0,90.0,300.0]
print("   sport, no-pad and normal profile break chains verified")


print("== 40. L main-section hopper quad (break drops from inner corner E) ==")
# reference true L and lazy L both: break line from E down to the bottom
for name,Lp,wantB1,wantV1 in (("true L",TRUE_L,300.0,240.0),
                              ("lazy L",[(0,0),(296,0),(414,119),(296,238),(226,168),(0,168)],
                               226.0,168.0)):
    bb=linex(Lp[4],_sub(Lp[5],Lp[0]),Lp[0],_sub(Lp[1],Lp[0]))   # break bottom
    mquad=[Lp[0],bb,Lp[4],Lp[5]]
    b1=dist(mquad[0],mquad[1]); v1=dist(mquad[0],mquad[3])
    assert abs(b1-wantB1)<1e-6 and abs(v1-wantV1)<1e-6, name
    # the reference hopper chains sum exactly to B1 -> E is not needed
    if name=="true L": h,g,f=60.0,90.0,150.0
    else:              h,g,f=48.0,72.0,106.0
    assert abs(h+g+f-b1)<1e-6, name
    gg=hopcalc(mquad,[("Square",0.0)]*4,h,g,0.0,30.0,35.0)
    assert abs(dist(gg['pl'],gg['phl'])-h)<1e-9
    assert abs(dist(gg['phl'],gg['phr'])-g)<1e-9
    # E = 0 -> the break coincides with the main section's right edge
    assert abs(gg['brkb'][0]-bb[0])<1e-6 and abs(gg['brkt'][0]-Lp[4][0])<1e-6
    print(f"   {name}: B1={b1:.0f} V1={v1:.0f}, H+G+F=B1 so E skipped, break on E")

print("== 41. bottom chain resolution (NA fill / even split / G-L absorb) ==")
def chainfix(vals,total,islack):
    s=sum(v for v in vals if v is not None)
    n=sum(1 for v in vals if v is None)
    if n>0:
        share=(total-s)/n
        return [v if v is not None else share for v in vals]
    if abs(s-total)>1e-6:
        return [v+(total-s) if i==islack else v for i,v in enumerate(vals)]
    return list(vals)

# one NA -> takes the remainder
assert chainfix([40.0,None,210.0,100.0],400.0,1)==[40.0,50.0,210.0,100.0]
# several NA -> split evenly
r=chainfix([40.0,None,None,100.0],400.0,1)
assert r[1]==r[2]==130.0
# all NA -> even split
assert chainfix([None,None,None],240.0,1)==[80.0,80.0,80.0]
# all provided, over the whole -> G absorbs (index 1)
assert chainfix([40.0,60.0,210.0,100.0],400.0,1)==[40.0,50.0,210.0,100.0]
# all provided, under the whole -> G grows
assert chainfix([40.0,50.0,200.0,100.0],400.0,1)==[40.0,60.0,200.0,100.0]
# vertical: L absorbs (index 1 of M L K)
assert chainfix([45.0,150.0,50.0],240.0,1)==[45.0,145.0,50.0]
# no-pad sport: islack -1 leaves values; residual split across F2/F1
vals=chainfix([60.0,140.0,148.0,50.0],400.0,-1)
resid=400.0-sum(vals)
f2,f1=vals[1]+resid/2, vals[2]+resid/2
assert abs(f2-141.0)<1e-9 and abs(f1-149.0)<1e-9
print("   remainder, even split, and G/L absorption all verified")


print("== 42. hopper dim-chain placement (below centre / right of G) ==")
Q=[(0,0),(400,0),(400,240),(0,240)]
SQ=[("Square",0.0)]*4
gg=hopcalc(Q,SQ,30,60,100,45,50)
# hopper spans y 50..195 -> L=145, centre 122.5; off=min(12,145/6)=12
assert abs(gg['pl'][1]-110.5)<1e-9 and abs(gg['phr'][1]-110.5)<1e-9
# M/L/K def points attached to the hopper right edge (x = H+G = 90)
assert abs(gg['pb'][0]-90.0)<1e-9 and abs(gg['pht'][0]-90.0)<1e-9
assert gg['voff']==(12.0,0.0)                         # dim line offset
# small hopper: L=30 -> off = 30/6 = 5 (less than 12)
gg2=hopcalc(Q,SQ,30,60,100,100,110)   # hopper y 110..140, centre 125
assert abs(gg2['pl'][1]-120.0)<1e-9
# distances unchanged by the shift (parallel walls)
assert abs(dist(gg['pl'],gg['phl'])-30)<1e-9
assert abs(dist(gg['pb'],gg['phb'])-50)<1e-9
print("   chain at centre-12 (or centre-L/6); M/L/K attached to the hopper edge")


print("== 43. Grecian overall-sheet input (A/B/T/S/S1/V/S2) ==")
def grecov(aov,bov,s,t,s1,v):
    if s is not None: S,T = s, bov-2*s          # T absorbs
    elif t is not None: S,T = (bov-t)/2.0, t
    else: S,T = bov/8.0, 0.75*bov
    if s1 is not None: S1,V = s1, aov-2*s1      # V absorbs
    elif v is not None: S1,V = (aov-v)/2.0, v
    else: S1,V = aov/6.0, aov*2.0/3.0
    return S,T,S1,V
# consistent sheet: B=500 A=200 T=400 S=50 S1=55 V=90
S,T,S1,V = grecov(200,500,50,400,55,90)
assert (S,T,S1,V)==(50,400,55,90)
# T and V absorb when the given values don't close
S,T,S1,V = grecov(200,500,50,398,55,88)
assert (S,T,S1,V)==(50,400,55,90)
# NA derivations
S,T,S1,V = grecov(200,500,None,400,None,90)
assert (S,T,S1,V)==(50.0,400,55.0,90)
# derived edges feed the existing pipeline and reproduce the sheet
hyp=math.hypot(50,55)
q,failed=fitquad(400,400,200,200,None,None)
a,b,c,d=q
cen0=((a[0]+b[0]+c[0]+d[0])/4.0,(a[1]+b[1]+c[1]+d[1])/4.0)
ml=_unit(_perp(_sub(d,a)))
if _dot(_sub(_mid(a,d),cen0),ml)<0: ml=_scl(ml,-1.0)
lend=grecendp(a,d,ml,hyp,hyp,90)
LT,LB=lend[0],lend[1]
# the end solver scans 0.05-degree steps with 1/16\" acceptance, so
# the seed lands within ~1/32\" of the sheet -- well inside tolerance
assert abs(LT[0]-(-50))<0.05 and abs(LT[1]-145)<0.05
assert abs(LB[0]-(-50))<0.05 and abs(LB[1]-55)<0.05
assert abs(dist(LT,LB)-90)<0.05                       # V
assert abs(dist(d,LT)-hyp)<1e-6                       # S2 face exact
print(f"   S/T/S1/V resolve + seed reproduces the sheet exactly (hyp={hyp:.3f})")


print("== 44. Roman end geometry (reference model: stubs + arc) ==")
def romend(pbot,ptop,m,s,v):
    u=_unit(_sub(ptop,pbot)); mide=_mid(pbot,ptop)
    tip=_add(mide,_scl(m,s)); half=v/2.0
    st=_add(mide,_scl(u,half)); sb=_sub(mide,_scl(u,half))
    return tip,st,sb,(s*s+half*half)/(2.0*s)
def circumr(p1,p2,p3):
    ax,ay=p1; bx,by=p2; cx,cy=p3
    dd=2*(ax*(by-cy)+bx*(cy-ay)+cx*(ay-by))
    ux=((ax*ax+ay*ay)*(by-cy)+(bx*bx+by*by)*(cy-ay)+(cx*cx+cy*cy)*(ay-by))/dd
    uy=((ax*ax+ay*ay)*(cx-bx)+(bx*bx+by*by)*(ax-cx)+(cx*cx+cy*cy)*(bx-ax))/dd
    return dist((ux,uy),p1)
# the reference: body 720x600, S=104.07, V=360 -> drawn R was 207.69
tip,st,sb,rimp=romend((0,0),(0,600),(-1,0),104.07,360.0)
assert tip==(-104.07,300.0)
assert st==(0.0,480.0) and sb==(0.0,120.0)             # springs ON the end line
assert abs(rimp-207.69)<0.01                           # implied R matches the drawing
assert abs(circumr(st,tip,sb)-rimp)<1e-6               # drawn arc = implied R
# sagitta inversion: S from R and V
S=rimp-math.sqrt(rimp*rimp-180.0*180.0)
assert abs(S-104.07)<0.01
print(f"   springs on end line, implied R={rimp:.2f} matches the reference drawing")


print("== 45. sport plan hopper (reference: 480x120, breaks + inset deep flat) ==")
def offln(ln,cen,dist):
    p,dv=ln
    n=_unit(_perp(dv))
    if _dot(_sub(p,cen),n)>0: n=_scl(n,-1.0)
    return (_add(p,_scl(n,dist)),dv)
def hopsportc(lline,rline,bline,tline,cen,e2,f2,g,f1,e1,m,k):
    obl=offln(lline,cen,e2); dfl=offln(lline,cen,e2+f2)
    dfr=offln(lline,cen,e2+f2+g); obr=offln(lline,cen,e2+f2+g+f1)
    dfb=offln(bline,cen,k); dft=offln(tline,cen,m)
    gg={}
    gg['oblb']=linex(*obl,*bline); gg['oblt']=linex(*obl,*tline)
    gg['obrb']=linex(*obr,*bline); gg['obrt']=linex(*obr,*tline)
    gg['dbl']=linex(*dfl,*dfb); gg['dtl']=linex(*dfl,*dft)
    gg['dbr']=linex(*dfr,*dfb); gg['dtr']=linex(*dfr,*dft)
    hc=tuple(sum(gg[kk][i] for kk in ('dbl','dtl','dbr','dtr'))/4.0 for i in (0,1))
    up=_unit(lline[1])
    hc2=_sub(hc,_scl(up,min(12.0,dist(gg['dbr'],gg['dtr'])/6.0)))
    gg['pl']=linex(hc2,bline[1],*lline); gg['pobl']=linex(hc2,bline[1],*obl)
    gg['pdfl']=linex(hc2,bline[1],*dfl); gg['pdfr']=linex(hc2,bline[1],*dfr)
    gg['pobr']=linex(hc2,bline[1],*obr); gg['pr']=linex(hc2,bline[1],*rline)
    gg['pb']=linex(*dfr,*bline); gg['pdb']=gg['dbr']
    gg['pdt']=gg['dtr']; gg['pt']=linex(*dfr,*tline)
    return gg
A,B,C,D=(0,0),(480,0),(480,120),(0,120)
cen=(240,60)
gg=hopsportc(((0,0),(0,120)), ((480,0),(0,120)), ((0,0),(480,0)), ((0,120),(480,0)),
             cen, 48,60,120,144,108, 24,24)
# reference geometry: outer breaks full-width at 48 / 372, deep flat
# x 108..228 inset 24 top and bottom
assert gg['oblb']==(48.0,0.0) and gg['oblt']==(48.0,120.0)
assert gg['obrb']==(372.0,0.0) and gg['obrt']==(372.0,120.0)
assert gg['dbl']==(108.0,24.0) and gg['dtl']==(108.0,96.0)
assert gg['dbr']==(228.0,24.0) and gg['dtr']==(228.0,96.0)
# chain values and placement (below centre by min(12, 72/6)=12; MLK at +12)
assert abs(gg['pl'][1]-48.0)<1e-9                     # 60 - 12
assert abs(gg['pb'][0]-228.0)<1e-9                    # attached to the deep-flat edge
for pair,want in ((('pl','pobl'),48),(('pobl','pdfl'),60),(('pdfl','pdfr'),120),
                  (('pdfr','pobr'),144),(('pobr','pr'),108),
                  (('pb','pdb'),24),(('pdb','pdt'),72),(('pdt','pt'),24)):
    assert abs(dist(gg[pair[0]],gg[pair[1]])-want)<1e-9
print("   breaks, inset deep flat, and all eight chain values exact")


print("== 46. hopper E-skip rule (L pools) ==")
def needs_e(h,g,f,b1,tol=0.5):
    if h is None or g is None or f is None: return True
    return abs(h+g+f-b1)>tol
assert not needs_e(60.0,90.0,150.0,300.0)      # exact -> skip E
assert not needs_e(60.0,90.0,150.3,300.0)      # within 1/2" -> skip E
assert needs_e(60.0,90.0,120.0,300.0)          # short -> ask E
assert needs_e(60.0,None,150.0,300.0)          # an NA -> ask E
assert needs_e(60.0,90.0,190.0,300.0)          # long -> ask E
# when E is asked the 4-chain still resolves against B1 (G absorbs)
r=chainfix([60.0,90.0,120.0,20.0],300.0,1)
assert r==[60.0,100.0,120.0,20.0]
print("   skip when H+G+F == B1 (1/2\" tol), otherwise E is prompted")

print("== 47. consolidated sport: G = 0 collapses to the no-pad V bottom ==")
def sport_resolve(e2r,f2r,gr,f1r,e1r,total):
    """Mirror of pool:hopsport's chain resolution: G=0 (or a G that
    resolves away) switches to the no-pad path."""
    nopad = gr is not None and gr < 1e-6
    if nopad:
        vals = chainfix([e2r,f2r,f1r,e1r], total, -1)
        e2,f2,f1,e1 = vals
        g = 0.0
        resid = total-e2-f2-f1-e1
        if abs(resid) > 1e-6:
            f2 += resid/2; f1 += resid/2
    else:
        e2,f2,g,f1,e1 = chainfix([e2r,f2r,gr,f1r,e1r], total, 2)
    if g < 1e-6:
        nopad, g = True, 0.0
    return e2,f2,g,f1,e1,nopad
# explicit 0 -> no-pad, residual split across F2/F1
e2,f2,g,f1,e1,nopad = sport_resolve(60.0,140.0,0.0,148.0,50.0,400.0)
assert nopad and g==0.0
assert abs(f2-141.0)<1e-9 and abs(f1-149.0)<1e-9
# positive G -> padded sport, G absorbs the mismatch as before
e2,f2,g,f1,e1,nopad = sport_resolve(40.0,60.0,220.0,90.0,50.0,400.0)
assert not nopad and abs(g-160.0)<1e-9
e2,f2,g,f1,e1,nopad = sport_resolve(40.0,60.0,None,90.0,50.0,400.0)
assert not nopad and abs(g-160.0)<1e-9        # NA G takes the remainder
# NA G with the other letters filling the length -> collapses to no-pad
e2,f2,g,f1,e1,nopad = sport_resolve(60.0,150.0,None,140.0,50.0,400.0)
assert nopad and g==0.0
print("   G=0 and G-resolves-to-0 both draw the V bottom; G>0 keeps the pad")

print("== 48. sysvar snapshot survives a dead run (snap restore) ==")
class Acad:
    def __init__(self): self.vars={"OSMODE":4133,"LUNITS":2,"CMDECHO":1,"CLAYER":"0"}
snapshot=[None]
def syssave(ac):
    # mirror of pool:syssave: only save when no snapshot is pending --
    # a stale one from a crashed run holds the user's TRUE settings
    if snapshot[0] is None:
        snapshot[0]=dict(ac.vars)
def sysrestore(ac):
    if snapshot[0] is not None:
        ac.vars.update(snapshot[0])
    snapshot[0]=None
def run_pool(ac, crash_before_restore=False):
    syssave(ac)
    ac.vars.update(OSMODE=0, LUNITS=4, CMDECHO=0)
    if crash_before_restore:
        return                       # died: settings left zeroed
    sysrestore(ac)
ac=Acad()
run_pool(ac)                         # clean run round-trips
assert ac.vars["OSMODE"]==4133 and ac.vars["LUNITS"]==2
run_pool(ac, crash_before_restore=True)
assert ac.vars["OSMODE"]==0          # crash leaves snaps off...
run_pool(ac)                         # ...but the NEXT run must not
assert ac.vars["OSMODE"]==4133       # save the zeroed state: prefs return
assert snapshot[0] is None
run_pool(ac)                         # and stays correct thereafter
assert ac.vars["OSMODE"]==4133 and ac.vars["CMDECHO"]==1
print("   crash between save and restore no longer wipes the user's snaps")

print("== 49. oval ends: true radii, NA chain, both-arcs-equal in-square ==")
def sag(r,c):
    half=c/2.0
    return half if r<=half else r-math.sqrt(r*r-half*half)
def sagr(s,c):
    half=c/2.0
    return None if s<=1e-9 else (s*s+half*half)/(2.0*s)
def ovalends(totl,lraw,rraw,axis,lc,rc):
    notes=[]
    if lraw is not None and rraw is not None:
        sl,sr = sag(lraw,lc), sag(rraw,rc)
    else:
        rem = totl-axis
        if lraw is None and rraw is None:
            sl=sr=rem/2.0
        elif lraw is None:
            sr=sag(rraw,rc); sl=rem-sr
        else:
            sl=sag(lraw,lc); sr=rem-sl
    if sl<=1e-6: sl=lc/2.0; notes.append("left")
    if sr<=1e-6: sr=rc/2.0; notes.append("right")
    return sagr(sl,lc), sagr(sr,rc), sl, sr, sl+axis+sr, notes

# sagitta round-trip: a drawn arc reads back the radius that was typed
for r,c in ((90.0,120.0),(200.0,144.0),(72.0,144.0)):
    s=sag(r,c)
    assert abs(sagr(s,c)-max(r,c/2.0))<1e-9
# in-square oval, both radii NA: total closes the chain, ends identical
lr,rr,sl,sr,tot,notes = ovalends(480.0,None,None,360.0,120.0,120.0)
assert not notes and abs(sl-60.0)<1e-9 and abs(sr-60.0)<1e-9
assert abs(lr-rr)<1e-9 and abs(lr-60.0)<1e-9      # 60 bulge on a 120 chord = semicircle
assert abs(tot-480.0)<1e-9
# one radius NA: it takes the remainder of the overall
lr,rr,sl,sr,tot,notes = ovalends(480.0,150.0,None,360.0,120.0,120.0)
assert abs(sl-sag(150.0,120.0))<1e-9
assert abs(sl+sr-120.0)<1e-9 and abs(lr-150.0)<1e-9
# total NA: computed from the two radii, both ends kept as measured
lr,rr,sl,sr,tot,notes = ovalends(None,150.0,90.0,360.0,120.0,120.0)
assert abs(lr-150.0)<1e-9 and abs(rr-90.0)<1e-9
assert abs(tot-(sag(150.0,120.0)+360.0+sag(90.0,120.0)))<1e-9
# out-of-square: both NA still splits the bulge evenly, so unequal end
# widths give unequal radii (same bulge) rather than a bogus fit
lr,rr,sl,sr,tot,notes = ovalends(480.0,None,None,360.0,120.0,132.0)
assert abs(sl-sr)<1e-9 and lr!=rr and not notes
# an overall too short for the body falls back to semicircles + a note
lr,rr,sl,sr,tot,notes = ovalends(360.0,None,None,360.0,120.0,120.0)
assert notes and abs(lr-60.0)<1e-9 and abs(rr-60.0)<1e-9
print("   radii round-trip through the arc; NA closes on the overall")

print("\nALL CHECKS PASSED")
