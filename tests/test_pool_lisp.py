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
HEXDIAGS = [(0, 2), (1, 3), (2, 4), (3, 5), (0, 4), (1, 5)]

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
    a, b, c = (0.0, 0.0), (ab, 0.0), (ab, bc)
    d = (ab - cd, bc)
    if lazy:
        e = (d[0] - de * 0.7071067812, d[1] + de * 0.7071067812)
    else:
        e = (d[0], d[1] + de)
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
TRUE_L = [(0, 0), (360, 0), (360, 140), (160, 140), (160, 260), (0, 260)]
sides, diags = hexmeas(TRUE_L)
pts, failed = fithex(sides, diags, lazy=False)
s, x = hexerr(pts, sides, diags)
print(f"   max side delta {s:.4f}, max cross delta {x:.4f}")
assert not failed and s < 0.05 and x < 0.1

print("== 14. out-of-square true L (field dims, 1/4\" rounding) ==")
SKEW_L = [(0, 0), (360.7, 0.3), (359.9, 140.6), (160.4, 141.1), (159.6, 260.8), (-0.5, 259.9)]
sides, diags = hexmeas(SKEW_L)
sides = [round(v * 4) / 4 for v in sides]
diags = [round(v * 4) / 4 for v in diags]
pts, failed = fithex(sides, diags, lazy=False)
s, x = hexerr(pts, sides, diags)
print(f"   max side delta {s:.3f}, max cross delta {x:.3f}, failed={failed}")
assert not failed and s <= 1.05 and x <= 2.05

print("== 15. true L with half the cross dims NA ==")
sides, diags = hexmeas(SKEW_L)
diags = [diags[0], None, diags[2], None, diags[4], None]
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

print("== 17. perfect lazy L ==")
LAZY_L = [(0, 0), (360, 0), (360, 140), (220, 140), (120, 240), (0, 240)]
sides, diags = hexmeas(LAZY_L)
pts, failed = fithex(sides, diags, lazy=True)
s, x = hexerr(pts, sides, diags)
print(f"   max side delta {s:.4f}, max cross delta {x:.4f}")
assert not failed and s < 0.05 and x < 0.1

print("== 18. point-in-polygon (dim placement) ==")
assert inpoly((180, 70), TRUE_L)          # main body
assert inpoly((80, 200), TRUE_L)          # wing
assert not inpoly((260, 200), TRUE_L)     # the notch
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
pts,failed=fithex(sides,[None]*6,lazy=False)
s,x=hexerr(pts,sides,[None]*6)
print(f"   max side delta {s:.4f}, failed={failed}")
assert not failed and s<0.05

print("== 26. Grecian in-square (no cross dims) builds from sides ==")
pts,failed,edges,cc=grec_fit(TRUE_G, [], {}, 'Simple')
em=edgemax(pts,edges)
print(f"   edgemax {em:.3f} (<=0 in band), n cross rows {len(cc)}, failed={failed}")
assert not failed and em<=0.06 and len(cc)==0

print("\nALL CHECKS PASSED")
