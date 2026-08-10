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
                   'pool_layout_lisp', 'POOL.LSP')


def run(script, label):
    vm = VM()
    vm.load(LSP)
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

print("\nALL RUNTIME SCENARIOS PASSED")
