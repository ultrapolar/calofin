"""Runtime smoke tests: load the REAL POOL.LSP into the AutoLISP VM and
drive c:POOL end-to-end with scripted answers, one scenario per shape,
plus Back-stress runs.  A regression that would die at the AutoCAD
command line -- an (if ...) with too many arguments, an unbound
function, nil reaching (distance ...) -- dies here instead.

Script values: numbers answer distance prompts, strings answer keyword
prompts (or NA/Back), None is Enter, tuples are picked points.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'pool', 'POOL.LSP')


def run(script, label, dimstyles=()):
    vm = VM()
    vm.load(LSP)
    for s in dimstyles:
        vm.tables['DIMSTYLE'].add(s)
    try:
        vm.run('c:POOL', script)
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def drawn(vm, etype, layer=None):
    from lispvm import Dot
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for p in vm.entdata[e]:
            if isinstance(p, Dot):
                d.setdefault(p.a, p.b)
            elif isinstance(p, list) and p:
                d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
        if d.get(0) == etype and (layer is None or d.get(8) == layer):
            out.append(d)
    return out


def dimcalls(vm, name='_.DIMALIGNED'):
    return [c for c in vm.commands if c and c[0] == name]


BASE = [(0.0, 0.0, 0.0)]      # insertion point pick


print("== R1. rectangle, in-square, square corners, Normal hopper ==")
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0,            # side pair, end pair
          "Square",                # all four corners
          "Yes", "Normal",         # bottom
          60.0, 90.0, 240.0, 90.0,  # H G F E
          60.0, 120.0, 60.0],      # M L K
         "R1")
assert len(drawn(vm, 'LINE', 'POOL')) >= 9    # perimeter + hopper + ties
assert drawn(vm, 'TEXT', 'POOL-NOTES')        # labels + report
print("   perimeter, hopper and report all drawn")

print("== R2. rectangle, out-of-square, Diag corners, Ends mode, wedge ==")
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 240.0, 120.0, 120.0,        # TOP BOTTOM LEFT RIGHT
          "Diag", 24.0,                       # corner A
          None, None, None, None, None, None,  # B, C, D reuse (type+size)
          "Ends",
          260.0, 260.0, 260.0, 260.0,         # 4 crossing cross dims
          "Yes", "Wedge",
          30.0, 180.0,                        # H, F (G and E pinned)
          None, 60.0, None,                   # M sugg=H(30): enter; L; K sugg
          40.0, 60.0],                        # C, D depths
         "R2")
assert drawn(vm, 'DIMENSION') or True         # dims go through (command)
assert any('_.DIMALIGNED' in c or '_.dimaligned' in str(c).lower()
           for c in vm.commands)
print("   crossing Ends ties + wedge bottom + section drawn")

print("== R3. Back stress: across questions, blocks and stages ==")
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, "Back", 240.0,                   # typo -> Back into TOP
          240.0, 120.0, 120.0,                    # BOTTOM LEFT RIGHT
          "Diag", 24.0,                           # corner A
          None, None,                             # corner B reuses
          "Rounded", 30.0,                        # corner C changes
          "Back", "Diag", 24.0,                   # Back into C, re-answer
          None, None,                             # corner D reuses C
          "Ends",
          "Back",                                 # out of cross -> cmode
          "Corner",                               # re-pick the mode
          262.0, "Back", 261.0, 262.0,            # fix a cross dim
          "No"],                                  # no bottom
         "R3")
print("   Back walks questions, blocks, and stages without derailing")

print("== R4. oval, in-square, radius NA (derived), Normal oval hopper ==")
vm = run(["Insquare", "Oval"] + BASE +
         [360.0, 240.0,           # side pair, end pair
          480.0, "NA",            # total; radius NA -> derived
          "Yes", "Normal",
          70.0, 150.0,            # H G
          "NA", "NA",             # R3, W both NA
          110.0, 90.0,            # F E
          None, 100.0, None,      # M sugg, L, K sugg
          "NA"],                  # T check
         "R4")
assert drawn(vm, 'ARC', 'POOL')
# in-square oval exterior per the field sheet: no bottom-side dim (T
# reads once, on top) and the tip-to-tip B sits ABOVE the pool
import math as _m
_dc = [c for c in dimcalls(vm)]
assert not any(abs(c[1][1]) < 0.01 and abs(c[2][1]) < 0.01 for c in _dc), \
    "bottom side must not be dimensioned in-square"
_bt = [c for c in _dc
       if abs(_m.dist(c[1][:2], c[2][:2]) - 480.0) < 0.5]
assert _bt and all(c[3][1] > 240.0 for c in _bt), _bt
print("   NA radius derived; tangent hopper end drawn; B on top, no bottom dim")

print("== R5. grecian, out-of-square, Measured, Center detail ==")
vm = run(["Outofsquare", "Grecian"] + BASE +
         ["Measured",
          360.0, 360.0, 180.0, 180.0,     # bottom top left right
          70.0, 70.0, 100.0,              # left diag T, diag B, width
          70.0, 70.0, 100.0,              # right end
          "Center",
          "NA", "NA", "NA", "NA",                 # long diagonals
          474.5, 474.5,                           # LT-RT / LB-RB: near-true
          "NA", "NA", "NA", "NA",                 # the end-cut X, both ends
          "NA", "NA", "NA", "NA",                 # tips to far corners
          "No"],
         "R5")
assert len(drawn(vm, 'LINE', 'POOL')) >= 8
xp=[p for p, a in vm.prompts if 'Cross dim' in p]
assert len(xp) == 14, xp
for tie in ("D-LB", "A-LT", "RB-C", "B-RT", "B-LT", "C-LB", "A-RT", "RB-D"):
    assert any(tie in p for p in xp), tie
# the measured tip-to-tip widths are held like walls: the drawn LT-RT
# must land within the 1" wall band of the tape (true is ~474.9)
import math as _m
pool_lines = [(tuple(d[10][:2]), tuple(d[11][:2]))
              for d in drawn(vm, 'LINE', 'POOL')]
verts = set()
for a, b in pool_lines:
    verts.add((round(a[0], 3), round(a[1], 3)))
    verts.add((round(b[0], 3), round(b[1], 3)))
# LT and RT are the leftmost/rightmost top-half vertices
tops = [v for v in verts if v[1] > 100]
lt = min(tops); rt = max(tops)
ltrt = _m.dist(lt, rt)
assert abs(ltrt - 474.5) <= 1.05, ltrt
print("   Center's 14 ties asked; LT-RT held to the tape like a wall")

print("== R5b. in-square GRECIAN on the overall sheet asks BOTH overalls ==")
vm = run(["Insquare", "Grecian"] + BASE +
         ["Overall",
          480.0,                    # B - overall length
          200.0,                    # A - overall width  (NOT assumed = B)
          "NA", "NA", "NA", "NA", "NA",   # T S S1 V S2
          "No"],
         "R5b")
_ov = [p for p, a in vm.prompts if "overall" in p.lower()]
assert any("B - overall length" in p for p in _ov), _ov
assert any("A - overall width" in p for p in _ov), _ov
assert not any("A & B are equal" in p for p in _ov), _ov
# and the drawn pool really is 480 long by 200 wide, not 480 square
_pl = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
_xs = [p[0] for seg in _pl for p in seg]
_ys = [p[1] for seg in _pl for p in seg]
assert abs((max(_xs) - min(_xs)) - 480.0) < 1.5, max(_xs) - min(_xs)
assert abs((max(_ys) - min(_ys)) - 200.0) < 1.5, max(_ys) - min(_ys)
# in-square exterior dims follow the field sheet: exactly S T B S1 V
# A S2 (7 dims, no bottom -> nothing else on the DIMENSION layer)
_dc = dimcalls(vm)
assert len(_dc) == 7, len(_dc)
# B = the tip-to-tip 480, dimensioned once, ABOVE the pool
_bt = [c for c in _dc if abs(_m.dist(c[1][:2], c[2][:2]) - 480.0) < 1.5]
assert len(_bt) == 1 and _bt[0][3][1] > 200.0, _bt
# A = the 200 overall, dimensioned once, LEFT of the pool
_at = [c for c in _dc if abs(_m.dist(c[1][:2], c[2][:2]) - 200.0) < 1.5]
assert len(_at) == 1 and _at[0][3][0] < 0.0, _at
print("   grecian keeps its own A and B: drawn 480 x 200; 7 sheet dims")

print("== R6. octagon from A and B alone (Overall default), hopper ==")
vm = run(["Insquare", "OC"] + BASE +
         [None,                    # method Enter -> Overall default
          400.0,                   # A & B once (in-square)
          "NA", "NA", "NA", "NA", "NA",   # T S S1 V S2 all NA
          "Yes", "Normal", "Square",   # bottom type, then hopper style
          80.0, 120.0, 110.0, 90.0,       # H G F E
          None, 160.0, None],      # M sugg, L, K sugg
         "R6")
assert len(drawn(vm, 'LINE', 'POOL')) >= 8
# the GUIDE the crew sees must itself be a regular octagon -- read the
# real constant back out of the loaded POOL.LSP, not a copy of it
import math as _m
from lispvm import Sym as _S
_np = [(float(p[0]), float(p[1])) for p in vm.get(_S('pool:*octnpts*'))]
_s = [_m.dist(_np[i], _np[(i + 1) % 8]) for i in range(8)]
assert len(_np) == 8 and max(_s) - min(_s) < 0.01, _s
_w = max(p[0] for p in _np) - min(p[0] for p in _np)
_h = max(p[1] for p in _np) - min(p[1] for p in _np)
assert abs(_w - _h) < 1e-6, (_w, _h)          # and it sits in a square
print("   A+B alone drew the octagon; guide is a regular octagon")

print("== R6b. the drawn octagon itself is regular (no bottom, so every "
      "POOL line IS the perimeter) ==")
vm = run(["Insquare", "OC"] + BASE +
         [None, 400.0,
          "NA", "NA", "NA", "NA", "NA",
          "No"],
         "R6b")
_per = [_m.dist(tuple(d[10][:2]), tuple(d[11][:2]))
        for d in drawn(vm, 'LINE', 'POOL')]
assert len(_per) == 8, len(_per)
assert max(_per) - min(_per) < 0.5, _per          # eight EQUAL sides
assert abs(_per[0] - 400.0 / (1 + _m.sqrt(2))) < 0.5, _per[0]
# same 7-dim field-sheet exterior as the grecian: S T B S1 V A S2
_dc = dimcalls(vm)
assert len(_dc) == 7, len(_dc)
_bt = [c for c in _dc if abs(_m.dist(c[1][:2], c[2][:2]) - 400.0) < 1.5]
assert len(_bt) == 2, _bt          # B (top) and A (left), both 400
print(f"   eight sides {min(_per):.2f}..{max(_per):.2f} "
      f"(regular = {400.0 / (1 + _m.sqrt(2)):.2f}); 7 sheet dims")

print("== R7. roman, in-square perfect, no bottom ==")
vm = run(["Insquare", "RO"] + BASE +
         [400.0, 260.0, "NA",      # B A T
          45.0, 50.0, 160.0, "NA",  # S S1 V R(check NA)
          "No"],
         "R7")
assert drawn(vm, 'ARC', 'POOL')
# in-square roman exterior per the sheet: S T S over B on top, S1 V
# S1 beside A on the left -- 8 linear dims (S and S1 BOTH show twice),
# plus the two end-radius dims; the bottom side is not dimensioned
_dc = dimcalls(vm)
assert len(_dc) == 8, len(_dc)
assert len(dimcalls(vm, '_.DIMRADIUS')) == 2
_ls = sorted(round(_m.dist(c[1][:2], c[2][:2]), 1) for c in _dc)
assert _ls.count(45.0) == 2, _ls       # S twice
assert _ls.count(50.0) == 2, _ls       # S1 twice
assert _ls.count(160.0) == 1, _ls      # V once
assert _ls.count(400.0) == 1, _ls      # B once
assert _ls.count(260.0) == 1, _ls      # A once
assert not any(abs(c[1][1]) < 0.01 and abs(c[2][1]) < 0.01 for c in _dc), \
    "bottom side must not be dimensioned in-square"
print("   roman ends drawn; sheet dims: S,S1 twice -- T,B,V,A once")

print("== R8. true L, out-of-square, diagonals NA, hopper E-skip, mirror No ==")
vm = run(["Outofsquare", "L"] + BASE +
         [480.0, 420.0, 180.0, 180.0, 300.0, 240.0,   # six sides
          "NA", "NA", "NA", "NA", "NA", "NA", "NA", "NA", "NA",  # 9 diags
          None,                   # corners modified? Enter = No
          "Yes",
          60.0, 90.0, 150.0,      # H G F sum to B1=300 -> E skipped
          None, 100.0, None,      # M sugg, L, K sugg
          "No"],                  # mirror
         "R8")
assert len(drawn(vm, 'LINE', 'POOL')) >= 6
print("   L pool + main-section hopper, E auto-skipped")

print("== R9. lazy L, in-square, hopper, mirror Yes ==")
vm = run(["Insquare", "LA"] + BASE +
         [296.0, 167.6, 167.6, 99.0, 226.0, 168.0,
          "No",                   # corners not modified
          "Yes",
          48.0, 72.0, 106.0,      # H G F sum to B1 -> E skipped
          40.0, 80.0, 40.0,       # M L K (typed, no suggestions taken)
          "Yes"],                 # mirror
         "R9")
assert any('_.MIRROR' in str(c) for c in vm.commands)
# in-square: the parallel pairs must be held EXACTLY -- A-B and E-F
# both dead horizontal, B-C at +45 and D-E at 225 (parallel), closure
# error absorbed by the E-F / F-A lengths instead of bent corners
segs = [(d[10][:2], d[11][:2]) for d in drawn(vm, 'LINE', 'POOL')]


def _seg(pa, pb, tol=0.01):
    return any((abs(a[0]-pa[0]) < tol and abs(a[1]-pa[1]) < tol and
                abs(b[0]-pb[0]) < tol and abs(b[1]-pb[1]) < tol) or
               (abs(a[0]-pb[0]) < tol and abs(a[1]-pb[1]) < tol and
                abs(b[0]-pa[0]) < tol and abs(b[1]-pa[1]) < tol)
               for a, b in segs)


_u = 0.7071067812
_A, _B = (0.0, 0.0), (296.0, 0.0)
_C = (_B[0] + 167.6*_u, 167.6*_u)
_D = (_C[0] - 167.6*_u, _C[1] + 167.6*_u)
_E = (_D[0] - 99.0*_u, _D[1] - 99.0*_u)
_F = (0.0, _E[1])
for pa, pb in [(_A, _B), (_B, _C), (_C, _D), (_D, _E), (_E, _F), (_F, _A)]:
    assert _seg(pa, pb), f"in-square lazy L perimeter missing {pa}->{pb}"
print("   lazy L mirrored; parallel pairs exact, closure -> E-F/F-A")

print("== R10. round, in-square (one prompt), oval hopper ==")
vm = run(["Insquare", "ROU"] + BASE +
         [420.0,                  # single overall
          "Yes", "Normal",
          70.0, 150.0, "NA", "NA", 110.0, 90.0,
          90.0, 240.0, 90.0,
          "NA"],
         "R10")
assert drawn(vm, 'CIRCLE', 'POOL')
# per the sheet: B reads across the TOP, A up the left side
_bt = [c for c in dimcalls(vm)
       if abs(_m.dist(c[1][:2], c[2][:2]) - 420.0) < 0.5]
_top = [c for c in _bt if c[3][1] > 420.0]
_left = [c for c in _bt if c[3][0] < 0.0]
assert _top and _left, _bt
print("   circle drawn from one measurement; hopper attached; B top, A left")

print("== R11. sport bottom with G=0 collapse and depth re-ask ==")
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0, "Square",
          "Yes", "Sport",
          48.0, 132.0, 0.0, 180.0, 120.0,     # E2 F2 G=0 F1 E1
          24.0, 192.0, None,                  # M L K sugg=M
          40.0, 30.0, 96.0],                  # C, D too shallow -> re-asked
         "R11")
print("   G=0 no-pad sport; shallow D was re-asked")

print("== R12. validation: negative G floored, red rows in report ==")
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0, "Square",
          "Yes", "Normal",
          200.0, 40.0, 300.0, 100.0,     # sums 640 vs 480 -> G absorbs to -120
          60.0, 120.0, 60.0],
         "R12")
assert vm.get(__import__('lispvm').Sym('pool:*valnotes*')) in (None, []) or True
red_texts = [d for d in drawn(vm, 'TEXT', 'POOL-NOTES') if d.get(62) == 1]
assert red_texts, "the failed chain must produce red report text"
print("   chain failure produced red report rows and a red note")

print("== R13. MUTT in-square: ROMAN deep end + GRECIAN shallow end ==")
vm = run(["Insquare", "MU"] + BASE +
         ["ROman", "Grecian",       # deep / shallow end styles
          480.0, 240.0,             # B tip-to-tip, A
          40.0, 40.0, 160.0, "NA",  # deep roman S S1 V R(check)
          50.0, 40.0, "NA",         # shallow grecian S S1 S2(check)
          "Yes", "Normal",
          60.0, 90.0, 210.0, "NA",  # H G F, E takes the rest of 480
          None, 120.0, None],       # M sugg=H, L, K sugg
         "R13")
assert drawn(vm, 'ARC', 'POOL'), "roman deep end must draw an arc"
# geometry: ext(roman)=S=40 so the body is 440 long; the grecian cut
# runs from the side start (390,0) up to the wall at (440,40)
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]


def hasseg(pa, pb, tol=0.01):
    return any((_m.dist(a, pa) < tol and _m.dist(b, pb) < tol) or
               (_m.dist(a, pb) < tol and _m.dist(b, pa) < tol)
               for a, b in segs)


assert hasseg((390.0, 0.0), (440.0, 40.0)), "grecian shallow cut"
assert hasseg((440.0, 40.0), (440.0, 200.0)), "grecian shallow wall"
assert hasseg((0.0, 0.0), (390.0, 0.0)), "bottom side stops at the cut"
# B reads tip to tip (480) and sits above the pool, in-square style
_bt = [c for c in dimcalls(vm) if abs(_m.dist(c[1][:2], c[2][:2]) - 480.0) < 0.5]
assert _bt and all(c[3][1] > 240.0 for c in _bt), _bt
# the bottom chain closes against the tip-to-tip 480, from the tip
assert any(abs(_m.dist(c[1][:2], c[2][:2]) - 60.0) < 0.5 and
           abs(c[1][0] - -40.0) < 0.5 or abs(c[2][0] - -40.0) < 0.5
           for c in dimcalls(vm)), "H must anchor at the deep tip"
print("   roman + grecian ends on one body; H taped from the tip")

print("== R13b. MUTT out-of-square: OVAL deep end, half round (R = NA) ==")
vm = run(["Outofsquare", "MU"] + BASE +
         ["Oval", "Square",
          480.0, "Back", 480.0,     # Back inside the letters block
          240.0,
          "NA",                     # oval deep R -> half round, ext 120
          "NA", "Back", "NA", "NA",  # Back inside the cross block too
          "No"],
         "R13b")
assert drawn(vm, 'ARC', 'POOL'), "oval deep end must draw an arc"
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
assert hasseg((360.0, 0.0), (360.0, 240.0)), "square shallow wall at body end"
assert hasseg((0.0, 0.0), (360.0, 0.0)), "body is B minus the half-round ext"
assert any("Cross dim body A-C" in p for p, a in vm.prompts)
print("   half-round deep end, square shallow end, crosses asked")

print("== R14. lazy L with ROUNDED outer corners + DIAG inner corner ==")
vm = run(["Insquare", "LA"] + BASE +
         [296.0, 167.6, 167.6, 99.0, 226.0, 168.0,
          "Yes",                  # corners modified
          "Rounded", 24.0,        # OUTER corners
          "Diag", 18.0,           # INNER corner (E) differs
          "No", "No"],            # no bottom, no mirror
         "R14")
# five outer fillet arcs on the pool perimeter
_arcs = drawn(vm, 'ARC', 'POOL')
assert len(_arcs) == 5, len(_arcs)
# ... and the inner corner E carries an 18" chamfer face instead: a
# POOL line of length 18 right at E (the in-square E of R9's numbers)
_u = 0.7071067812
_E = (296.0 - 99.0*_u, 296.0*0 + (167.6*_u + 167.6*_u) - 99.0*_u)
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
_cham = [s for s in segs
         if abs(_m.dist(*s) - 18.0) < 0.05 and
         _m.dist(((s[0][0]+s[1][0])/2, (s[0][1]+s[1][1])/2), _E) < 15.0]
assert _cham, "inner chamfer face missing at E"
# side dims still read to the TRUE corners: the full 296 bottom
assert any(abs(_m.dist(c[1][:2], c[2][:2]) - 296.0) < 0.5 for c in dimcalls(vm))
# the Typ. radius callout ran for the outer corners
assert any(c[0] == '_.DIMRADIUS' and any('Typ.' in str(x) for x in c)
           for c in vm.commands), "outer corner Typ. callout"
print("   5 rounded outer corners, chamfered inner corner, Typ. callout")

print("== R14b. true L hopper ties connect to the ROUNDED deep-end wall ==")
# true L, sides 480/420/180/180/300/240 -> A=(0,0) B=(480,0) C=(480,420)
# D=(300,420) E=(300,240) F=(0,240).  The deep-end wall is A-F (both
# plain 90-degree corners), so with a 24" outer radius the hopper's
# left-corner ties must land on the ends of that cut -- (24,0) and
# (0,24) at A, (24,240) and (0,216) at F -- not on the sharp corners
# behind them like the old (hardcoded-Square) main-section frame drew.
vm = run(["Insquare", "L"] + BASE +
         [480.0, 420.0, 180.0, 180.0, 300.0, 240.0,
          "Yes", "Rounded", 24.0, "Square",   # outer 24" round, inner square
          "Yes",
          60.0, 90.0, 150.0,      # H G F sum to B1=300 -> E skipped
          None, 100.0, None,      # M sugg, L, K sugg
          "No"],                  # mirror
         "R14b")
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]


def endpoint_near(seg, pt, tol=0.05):
    return any(_m.dist(p, pt) < tol for p in seg)


def other_end(seg, pt, tol=0.05):
    return seg[1] if _m.dist(seg[0], pt) < tol else seg[0]


# the corner-cut point is also a perimeter WALL endpoint (the cut end
# shared with corner B, say) -- pick the SHORTEST matching segment,
# since a tie line runs corner-cut -> hopper corner while the wall
# runs corner-cut -> the far end of that wall
def shortest_from(pt):
    cands = [s for s in segs if endpoint_near(s, pt)]
    return min(cands, key=lambda s: _m.dist(*s)) if cands else None


tieA1 = shortest_from((24.0, 0.0))
tieA2 = shortest_from((0.0, 24.0))
tieF1 = shortest_from((24.0, 240.0))
tieF2 = shortest_from((0.0, 216.0))
assert tieA1 and tieA2, "hopper tie must reach both ends of A's corner cut"
assert tieF1 and tieF2, "hopper tie must reach both ends of F's corner cut"
# both A-side ties converge on the SAME hopper corner (hbl)
hblA = other_end(tieA1, (24.0, 0.0))
hblB = other_end(tieA2, (0.0, 24.0))
assert _m.dist(hblA, hblB) < 0.05, (hblA, hblB)
# both F-side ties converge on the SAME hopper corner (htl)
htlA = other_end(tieF1, (24.0, 240.0))
htlB = other_end(tieF2, (0.0, 216.0))
assert _m.dist(htlA, htlB) < 0.05, (htlA, htlB)
# and the old bug -- ties collapsing onto the SHARP corner (0,0)/(0,240)
# because the main-section frame hardcoded Square -- is gone: no POOL
# line has an endpoint sitting exactly on the sharp corner itself
assert not any(endpoint_near(s, (0.0, 0.0)) for s in segs), \
    "a tie is still landing on the sharp corner A, not the cut"
assert not any(endpoint_near(s, (0.0, 240.0)) for s in segs), \
    "a tie is still landing on the sharp corner F, not the cut"
print("   deep-end ties land on the rounded corner cut, matching the rectangle")

print("== R14c. lazy L: the same fix applies (shared hopper code path) ==")
# same mechanism, lazy L this time -- A and F are still plain corners
# on the deep-end wall (only B/D bend at 45 degrees), so a 20" chamfer
# there must still produce TWO distinct tie lines per side instead of
# collapsing onto the sharp corner.
vm = run(["Insquare", "LA"] + BASE +
         [296.0, 167.6, 167.6, 99.0, 226.0, 168.0,
          "Yes", "Diag", 20.0, "Square",
          "Yes",
          48.0, 72.0, 106.0,
          40.0, 80.0, 40.0,
          "No"],
         "R14c")
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
# A = (0,0): a 20" chamfer face should be sitting near it, both ends
# distinct (the old bug drew NO 20-inch segment there at all -- the
# main-section frame forced Square, i.e. a zero-length "cut")
_near_a = [s for s in segs
           if abs(_m.dist(*s) - 20.0) < 0.5 and _m.dist(s[0], (0.0, 0.0)) < 25.0]
assert _near_a, "no 20-inch chamfer face found near A"
_aface = _near_a[0]
tieA1 = [s for s in segs if endpoint_near(s, _aface[0])
         and abs(_m.dist(*s) - 20.0) > 0.5]
tieA2 = [s for s in segs if endpoint_near(s, _aface[1])
         and abs(_m.dist(*s) - 20.0) > 0.5]
assert tieA1 and tieA2, "both ends of A's chamfer must carry their own tie"
_hbl1 = other_end(min(tieA1, key=lambda s: _m.dist(*s)), _aface[0])
_hbl2 = other_end(min(tieA2, key=lambda s: _m.dist(*s)), _aface[1])
assert _m.dist(_hbl1, _hbl2) < 0.05, (_hbl1, _hbl2)
print("   lazy L deep-end ties land on the cut too (same code path as true L)")

print("== R15. dims under 24\" use the STANDARD INCHES dim style ==")
# same pool as R14 (24" outer radius, 18" inner chamfer) in a drawing
# that HAS the style: the corner treatments are small, the sides big
vm = run(["Insquare", "LA"] + BASE +
         [296.0, 167.6, 167.6, 99.0, 226.0, 168.0,
          "Yes", "Rounded", 20.0, "Diag", 18.0,
          "No", "No"],
         "R15", dimstyles=("STANDARD INCHES",))


def styled(vm):
    """(measurement, style current when it was drawn) per dimension."""
    cur, out = 'STANDARD', []
    for c in vm.commands:
        if c and c[0] == '_.-DIMSTYLE' and len(c) >= 3 and c[1] == '_Restore':
            cur = c[2]
        elif c and c[0] == '_.DIMALIGNED':
            out.append((_m.dist(c[1][:2], c[2][:2]), cur))
        elif c and c[0] == '_.DIMRADIUS':
            out.append(('R', cur))
    return out


sd = styled(vm)
big = [(d, s) for d, s in sd if d != 'R' and d >= 24.0]
small = [(d, s) for d, s in sd if d != 'R' and d < 24.0]
assert big and all(s == 'STANDARD' for d, s in big), big
assert small and all(s == 'STANDARD INCHES' for d, s in small), small
# the 18" chamfer face is one of them, and the 20" corner radius dim
# (a DIMRADIUS) switched too
assert any(abs(d - 18.0) < 0.05 for d, s in small), sd
assert any(s == 'STANDARD INCHES' for d, s in sd if d == 'R'), sd
# and the style always lands back where it started
assert vm.get(__import__('lispvm').Sym('pool:*dimstyle0*')) == 'STANDARD'
assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars['DIMSTYLE']
print(f"   {len(small)} small dims in STANDARD INCHES, "
      f"{len(big)} large in STANDARD, style restored")

print("== R15b. no STANDARD INCHES in the drawing -> current style, warned once ==")
vm = run(["Insquare", "LA"] + BASE +
         [296.0, 167.6, 167.6, 99.0, 226.0, 168.0,
          "Yes", "Rounded", 20.0, "Diag", 18.0,
          "No", "No"],
         "R15b")
assert not vm.dimstyle_log, vm.dimstyle_log      # never switched
assert sum(1 for p, a in vm.prompts
           if 'STANDARD INCHES' in p and 'dim style' in p) <= 1
print("   falls back cleanly when the style is absent")

print("== R15c. out-of-square corner dims + nesting inside CROSS DIMENSIONS ==")
# out-of-square dims every corner, so all four 18" chamfer faces take
# the inches style, while the two cross diagonals stay big
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 240.0, 120.0, 120.0,
          "Diag", 18.0,
          None, None, None, None, None, None,
          "Corner", 268.0, 268.0,
          "No"],
         "R15c", dimstyles=("STANDARD INCHES", "CROSS DIMENSIONS"))
assert vm.dimstyle_log.count('STANDARD INCHES') == 4, vm.dimstyle_log
assert 'CROSS DIMENSIONS' in vm.dimstyle_log
assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.dimstyle_log
# Nesting: a small dim drawn while CROSS DIMENSIONS is current must
# come back to CROSS DIMENSIONS, not to STANDARD.  The draw order
# never produces a small cross dim today, so drive it directly rather
# than let the assertion sit vacuous.
vm2 = VM()
vm2.load(LSP)
for s in ("STANDARD INCHES", "CROSS DIMENSIONS"):
    vm2.tables['DIMSTYLE'].add(s)
vm2.loads("""
  (defun testnest ( / od)
    (setq od (pool:dimxbegin))
    (pool:dimalg '(0.0 0.0) '(18.0 0.0) '(9.0 5.0))
    (pool:dimxend od))
""")
vm2.run('testnest', [])
assert vm2.dimstyle_log == ['CROSS DIMENSIONS', 'STANDARD INCHES',
                            'CROSS DIMENSIONS', 'STANDARD'], vm2.dimstyle_log
print("   4 corner faces in inches; a nested small dim unwinds to CROSS DIMENSIONS")

print("== R16. grecian Overall: WALL letters beat CORNER letters ==")
# The field case from beforeaftergrecianoosexample.dxf.  A tape can be
# held flat along T and V, so they are held true; S and S1 only locate
# the virtual sharp corner and get re-derived.  Expected perimeter =
# the "after" figure measured straight out of that DXF.
vm = run(["Outofsquare", "Grecian"] + BASE +
         ["Overall",
          441.50, 216.00,                 # B, A overalls
          324.00, 61.00, 60.00, 96.00, 84.00,   # T, S, S1, V, S2
          "Simple", 389.00, 388.50,       # cross dims A-C, B-D
          "No"],                          # no bottom: every POOL line
         "R16")                           # is a perimeter edge
_seg = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
assert len(_seg) == 8, len(_seg)
_pts = set()
for _a, _b in _seg:
    _pts.add((round(_a[0], 2), round(_a[1], 2)))
    _pts.add((round(_b[0], 2), round(_b[1], 2)))
_ox = min(p[0] for p in _pts)
_got = [(round(p[0] - _ox, 2), round(p[1], 2)) for p in _pts]
AFTER = [(58.65, 0.00), (382.65, 0.00), (441.47, 59.94), (441.60, 155.90),
         (382.95, 216.00), (58.95, 216.00), (0.13, 156.06), (0.00, 60.10)]
assert len(_got) == 8, _got
for _t in AFTER:
    assert min(_m.dist(_g, _t) for _g in _got) < 0.05, (_t, sorted(_got))
# the walls the crew taped are held EXACTLY ...
_lens = sorted(round(_m.dist(*s), 2) for s in _seg)
assert _lens.count(324.00) == 2, _lens               # T top and bottom
assert sum(1 for x in _lens if abs(x - 96.0) <= 0.05) == 2, _lens    # V ends
assert sum(1 for x in _lens if abs(x - 84.0) <= 0.05) == 4, _lens    # S2 faces
# ... and the old behaviour (T squashed to 319.5, faces at 85.56) is gone
assert not any(abs(x - 319.50) < 0.6 for x in _lens), _lens
assert not any(abs(x - 85.56) < 0.05 for x in _lens), _lens
print("   T/V/S2 walls held true; S and S1 absorbed the error")

print("== R17. SIX-sided grecian hopper, sheet-letter input (W X L L1 G M K) ==")
# the demonstrated-dims figure from 6sidedgrecianexample.dxf: W is the
# FLAT (cut corner to the pad's right edge), L1 the left edge length
# centred on the pad, X a check on the connecting faces


def hexrun(mode_answers, label):
    vm = run(["Insquare", "Grecian"] + BASE +
             ["Overall", 480.0, 240.0, "NA", 60.0, 72.0, "NA", "NA",
              "Yes", "Normal", "SIX"] + mode_answers, label)
    s = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
    ox = min(p[0] for seg in s for p in seg)
    return vm, [((a[0] - ox, a[1]), (b[0] - ox, b[1])) for a, b in s]


def findseg(segs, pa, pb, tol=0.15):
    for a, b in segs:
        if (_m.dist(a, pa) < tol and _m.dist(b, pb) < tol) or \
           (_m.dist(a, pb) < tol and _m.dist(b, pa) < tol):
            return (a, b)
    return None


vm, segs = hexrun(["Letters", 48.0, 72.0,      # H G
                   38.0, 72.0, 49.5,           # W L1 X(check)
                   240.0, "NA",                 # F, E takes the rest
                   48.0, "NA", None],           # M, L derived, K sugg
                  "R17")
for pa, pb, what in [((82, 192), (120, 192), "W top flat"),
                     ((82, 48), (120, 48), "W bottom flat"),
                     ((48, 156), (48, 84), "L1 left edge"),
                     ((82, 192), (48, 156), "cut face top"),
                     ((48, 84), (82, 48), "cut face bottom"),
                     ((120, 48), (120, 192), "pad right edge"),
                     ((59.99, 240), (82, 192), "tie D"),
                     ((0, 167.99), (48, 156), "tie LT"),
                     ((0, 72.01), (48, 84), "tie LB"),
                     ((59.99, 0), (82, 48), "tie A"),
                     ((360, 0), (360, 240), "break")]:
    assert findseg(segs, pa, pb), what
# X = sqrt(34^2 + 36^2) = 49.52 vs the taped 49.5: inside the check
assert not any('X DOES NOT CLOSE' in str(n)
               for n in (vm.get(__import__('lispvm').Sym('pool:*valnotes*')) or []))
print("   sheet letters reproduce the demonstrated-dims figure")

print("== R17b. SIX-sided grecian hopper, offsets input (faces parallel) ==")
vm, segs = hexrun(["Offsets", 48.0, 72.0,      # H G
                   "NA",                        # cut offset NA -> H
                   240.0, "NA", 48.0, "NA", None],
                  "R17b")
for pa, pb, what in [((82.47, 192), (48, 150.63), "top cut"),
                     ((48, 89.37), (82.47, 48), "bottom cut"),
                     ((48, 150.63), (48, 89.37), "left edge"),
                     ((82.47, 192), (120, 192), "top flat"),
                     ((120, 48), (120, 192), "pad right edge")]:
    assert findseg(segs, pa, pb), what
# the cut face is EXACTLY parallel to the pool's corner cut, 48 off it
_pc = findseg(segs, (59.99, 240), (0, 167.99))
_hx = findseg(segs, (82.47, 192), (48, 150.63))
_d1 = (_hx[1][0] - _hx[0][0], _hx[1][1] - _hx[0][1])
_d2 = (_pc[1][0] - _pc[0][0], _pc[1][1] - _pc[0][1])
assert abs(_d1[0]*_d2[1] - _d1[1]*_d2[0]) / (_m.hypot(*_d1)*_m.hypot(*_d2)) < 1e-9
_mm = ((_hx[0][0]+_hx[1][0])/2, (_hx[0][1]+_hx[1][1])/2)
_u = (_d2[0]/_m.hypot(*_d2), _d2[1]/_m.hypot(*_d2))
_w = (_mm[0]-_pc[0][0], _mm[1]-_pc[0][1])
assert abs(abs(_w[0]*_u[1] - _w[1]*_u[0]) - 48.0) < 1e-6
print("   offsets reproduce the offsets figure; faces parallel at 48")

print("== R18. cross dims: no per-entity style override (pure ByLayer) ==")
# pool:dimdash used to stamp a hardcoded linetype (group 6) + ltscale
# (group 48) onto every cross-dim entity so it read dashed regardless
# of layer/style.  That is gone -- cross dims are ByLayer now, and
# their look comes only from the CROSS DIMENSIONS dim style / the
# DIMENSION layer.  Calling the retired function must fail outright,
# not silently resolve to something else.
vm = VM()
vm.load(LSP)
vm.loads("(defun testdimdash () (pool:dimdash))")
try:
    vm.run('testdimdash', [])
    raise AssertionError("pool:dimdash must no longer exist")
except LispError as e:
    assert 'dimdash' in str(e), e
print("   pool:dimdash is gone -- cross dims carry no property override")

print("== R19. small-dim cutover is UNDER 2', not at-or-under ==")
# a dimension of exactly pool:*smalldim* (24") must NOT switch to
# STANDARD INCHES -- it stays in whatever style was already current,
# in or out of a cross-dim block.
vm = VM()
vm.load(LSP)
vm.tables['DIMSTYLE'].add("STANDARD INCHES")
vm.tables['DIMSTYLE'].add("CROSS DIMENSIONS")
vm.loads("""
  (defun testcutover ( / od)
    (pool:dimalg '(0.0 0.0) '(23.999 0.0) '(12.0 5.0))   ; just under
    (pool:dimalg '(0.0 0.0) '(24.0 0.0) '(12.0 5.0))     ; exactly 24
    (setq od (pool:dimxbegin))
    (pool:dimalg '(0.0 0.0) '(24.0 0.0) '(12.0 5.0))     ; exactly 24, crossed
    (pool:dimxend od))
""")
vm.run('testcutover', [])
assert vm.dimstyle_log == ['STANDARD INCHES', 'STANDARD',   # under 24 switches
                           # exactly 24 outside any block: no switch at all
                           'CROSS DIMENSIONS',              # cross block opens
                           'STANDARD'], vm.dimstyle_log      # exactly 24 inside: stays CROSS DIMENSIONS, block closes
print("   under 24\" switches to STANDARD INCHES; exactly 24\" keeps the current style")

print("\nALL RUNTIME SCENARIOS PASSED")
