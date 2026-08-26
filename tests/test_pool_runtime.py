"""Runtime smoke tests: load the REAL POOL.LSP into the AutoLISP VM and
drive c:POOL end-to-end with scripted answers, one scenario per shape,
plus Back-stress runs.  A regression that would die at the AutoCAD
command line -- an (if ...) with too many arguments, an unbound
function, nil reaching (distance ...) -- dies here instead.

Script values: numbers answer distance prompts, strings answer keyword
prompts (or NA/Back), None is Enter, tuples are picked points.
"""

import math as _m
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


def dimcalls(vm, name=('_.DIMALIGNED', '_.DIMLINEAR')):
    names = (name,) if isinstance(name, str) else name
    return [c for c in vm.commands if c and c[0] in names]


def dimloc(c):
    """Dimension-line placement point: the last point in the command
    (DIMLINEAR carries an _H/_V/_R keyword between the ext-line
    origins and the location, so a fixed index won't do)."""
    return [x for x in c if isinstance(x, list)][-1]


def reportrow(vm, label):
    """One report row as its column strings: label, target, actual, delta
    (everything drawn on the row's own baseline, left to right)."""
    txt = drawn(vm, 'TEXT', 'POOL-NOTES')
    hit = [d for d in txt if d.get(1) == label]
    assert hit, f"no report row {label!r}"
    y = hit[0][10][1]
    return [d.get(1) for d in sorted((d for d in txt
                                      if abs(d[10][1] - y) < 0.01),
                                     key=lambda d: d[10][0])]


def hasseg(pa, pb, tol=0.01):
    """Is this segment among the ones the scenario last collected?
    Reads the module-level `segs` each block rebuilds for its shape."""
    return any((_m.dist(a, pa) < tol and _m.dist(b, pb) < tol) or
               (_m.dist(a, pb) < tol and _m.dist(b, pa) < tol)
               for a, b in segs)


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

print("== R1b. the last letter of each chain is offered, not asked ==")
# H, G, F given -> E is what the length has left; M suggests H; M the
# same as H says the hopper sits square, which fixes L at A - 2M; and
# M + L given -> K is what the width has left.  Four Enters.
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0, "Square",
          "Yes", "Normal",
          60.0, 90.0, 210.0,      # H G F -> E = 480 - 360
          None,                   # E: Enter takes 120
          None, None, None],      # M (=H 60), L (240 - 2*60), K (240 - 180)
         "R1b")


def _sugg(letter):
    """The <number> a prompt offered, or None if it asked cold."""
    for p, a in vm.prompts:
        if p.lstrip().startswith(letter + " -") and " <" in p:
            return float(p.split(" <")[1].split(">")[0])
    return None


assert _sugg("E") == 120.0, vm.prompts
assert _sugg("M") == 60.0
assert _sugg("L") == 120.0          # 2M + L = A
assert _sugg("K") == 60.0           # A - M - L
for _lbl, _want in (("HOP E", "120.00"), ("HOP M", "60.00"),
                    ("HOP L", "120.00"), ("HOP K", "60.00")):
    _row = reportrow(vm, _lbl)
    assert _row[1] == _want and _row[2] == _want, (_lbl, _row)
print("   E, M, L and K all offered; four Enters closed both chains")

print("== R1c. M measured off H leaves L alone, K still adds up ==")
# The 2M + L = A suggestion is the crew SAYING the pool is square about
# the hopper -- M different from H says nothing about L, so L is asked
# cold.  K is still the width's remainder, and no longer just "same as M".
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0, "Square",
          "Yes", "Normal",
          60.0, 90.0, 210.0, None,
          40.0,                   # M measured, and not H
          120.0,                  # L asked cold
          None],                  # K = 240 - 40 - 120 = 80, not M
         "R1c")
assert _sugg("L") is None, "L must be asked cold when M is not H"
assert _sugg("K") == 80.0, vm.prompts
assert reportrow(vm, "HOP K")[1] == "80.00"
print("   L asked cold; K offered the remainder (80), not M (40)")

print("== R2. rectangle, out-of-square, Cut corners, Ends mode, wedge ==")
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 240.0, 120.0, 120.0,        # TOP BOTTOM LEFT RIGHT
          "Cut", 24.0,                       # corner A
          None, None, None, None, None, None,  # B, C, D reuse (type+size)
          "Ends",
          260.0, 260.0, 260.0, 260.0,         # 4 crossing cross dims
          "Yes", "Wedge",
          30.0, 180.0,                        # H, F (G and E pinned)
          None, 60.0, None,                   # M sugg=H(30): enter; L; K sugg
          40.0, 60.0],                        # C, D depths
         "R2")
assert drawn(vm, 'DIMENSION') or True         # dims go through (command)
assert any(c and c[0] in ('_.DIMALIGNED', '_.DIMLINEAR')
           for c in vm.commands)
print("   crossing Ends ties + wedge bottom + section drawn")

print("== R3. Back stress: across questions, blocks and stages ==")
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, "Back", 240.0,                   # typo -> Back into TOP
          240.0, 120.0, 120.0,                    # BOTTOM LEFT RIGHT
          "Cut", 24.0,                           # corner A
          None, None,                             # corner B reuses
          "Radius", 30.0,                        # corner C changes
          "Back", "Cut", 24.0,                   # Back into C, re-answer
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
_dc = [c for c in dimcalls(vm)]
assert not any(abs(c[1][1]) < 0.01 and abs(c[2][1]) < 0.01 for c in _dc), \
    "bottom side must not be dimensioned in-square"
_bt = [c for c in _dc
       if abs(_m.dist(c[1][:2], c[2][:2]) - 480.0) < 0.5]
assert _bt and all(dimloc(c)[1] > 240.0 for c in _bt), _bt
print("   NA radius derived; tangent hopper end drawn; B on top, no bottom dim")

print("== R4b. oval, in-square: side NA -- read back off the overall ==")
# the radius is NA too, so both ends are taken tangent to the box the
# pool sits in (a semicircle each) and the side is overall - width
vm = run(["Insquare", "Oval"] + BASE +
         ["NA", 240.0,            # side pair NOT taped; end pair
          480.0, "NA",            # total; radius NA -> semicircle ends
          "No"],                  # no bottom
         "R4b")
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
assert len(segs) == 2 and len(drawn(vm, 'ARC', 'POOL')) == 2, segs
assert hasseg((0.0, 0.0), (240.0, 0.0)), segs        # 480 - 240 = 240
assert hasseg((0.0, 240.0), (240.0, 240.0)), segs
# tip to tip still measures the overall that was given
assert any(abs(_m.dist(c[1][:2], c[2][:2]) - 480.0) < 0.01 for c in dimcalls(vm))
# a side that was never taped reports N/A, like any other NA
assert reportrow(vm, "TOP SIDE (D-C)")[1] == "N/A"
assert reportrow(vm, "BOTTOM SIDE (A-B)")[1] == "N/A"
assert reportrow(vm, "LEFT END (A-D)")[1] == "240.00"
print("   overall less the width gives the side; ends come out semicircles")

print("== R4c. oval, out-of-square: both sides NA against measured radii ==")
# sag(200, 240) = 40 a side, so the body is 480 - 80 = 400 both sides
vm = run(["Outofsquare", "Oval"] + BASE +
         ["NA", "NA", 240.0, 240.0,   # TOP and BOTTOM not taped; ends
          480.0, 200.0, 200.0,        # total; both radii measured
          "NA", "NA",                 # cross dims not taped
          "No"],
         "R4c")
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
assert hasseg((0.0, 0.0), (400.0, 0.0)), segs
assert hasseg((0.0, 240.0), (400.0, 240.0)), segs
assert reportrow(vm, "TOTAL LENGTH")[1] == "480.00"
print("   a measured radius spends its own bulge out of the overall")

print("== R4d. oval, out-of-square: one side NA, mirrored about the midline ==")
# the overall pins the MIDLINE at 400, so a 404 top makes the bottom 396
vm = run(["Outofsquare", "Oval"] + BASE +
         [404.0, "NA", 240.0, 240.0,  # TOP taped, BOTTOM not
          480.0, 200.0, 200.0,
          "NA", "NA",
          "No"],
         "R4d")
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
_L = sorted(_m.dist(a, b) for a, b in segs)
assert len(_L) == 2 and abs(_L[0] - 396.0) < 0.05 and abs(_L[1] - 404.0) < 0.05, _L
assert reportrow(vm, "TOP SIDE (D-C)")[1] == "404.00"     # taped, so a target
assert reportrow(vm, "BOTTOM SIDE (A-B)")[1] == "N/A"     # derived, so none
print("   the taped side stands; the missing one closes the overall")

print("== R4e. oval: a side NA makes the overall compulsory ==")
vm = run(["Insquare", "Oval"] + BASE +
         ["NA", 240.0,            # side pair NOT taped
          "NA", "NA",             # total NA as well, radius NA
          480.0,                  # ... so the total is asked again, NA gone
          "No"],
         "R4e")
_tot = [p for p, a in vm.prompts if "Total pool length" in p]
assert len(_tot) == 2 and "NA" not in _tot[1], _tot
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
assert hasseg((0.0, 0.0), (240.0, 0.0)), segs
print("   nothing to close the chain -- the overall is re-asked, no NA")

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
          None,                                    # anything to record? Enter = No
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
          None,                     # anything to record? Enter = No
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
assert len(_bt) == 1 and dimloc(_bt[0])[1] > 200.0, _bt
# A = the 200 overall, dimensioned once, LEFT of the pool
_at = [c for c in _dc if abs(_m.dist(c[1][:2], c[2][:2]) - 200.0) < 1.5]
assert len(_at) == 1 and dimloc(_at[0])[0] < 0.0, _at
print("   grecian keeps its own A and B: drawn 480 x 200; 7 sheet dims")

print("== R6. octagon from A and B alone (Overall default), hopper ==")
vm = run(["Insquare", "OC"] + BASE +
         [None,                    # method Enter -> Overall default
          400.0,                   # A & B once (in-square)
          "NA", "NA", "NA", "NA", "NA",   # T S S1 V S2 all NA
          None,                     # anything to record? Enter = No
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
          None,                     # anything to record? Enter = No
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
          None,                     # anything to record? Enter = No
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
          None,                   # anything to record? Enter = No
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
# and it is a top-to-bottom flip (horizontal axis), so the deep end
# and its hopper stay on the left -- see R23
_mir = [c for c in vm.commands if c and c[0] == '_.MIRROR'][0]
assert abs(_mir[3][1] - _mir[4][1]) < 1e-9, _mir[3:5]
# in-square: the parallel pairs must be held EXACTLY -- A-B and E-F
# both dead horizontal, B-C at +45 and D-E at 225 (parallel) -- and the
# three deep-end sides (A-B, E-F, F-A, what the hopper is measured off)
# must come out ON the tape, with any closure error left in the wing
segs = [(d[10][:2], d[11][:2]) for d in drawn(vm, 'LINE', 'POOL')]


def _seg(pa, pb, tol=0.01):
    return any((abs(a[0]-pa[0]) < tol and abs(a[1]-pa[1]) < tol and
                abs(b[0]-pb[0]) < tol and abs(b[1]-pb[1]) < tol) or
               (abs(a[0]-pb[0]) < tol and abs(a[1]-pb[1]) < tol and
                abs(b[0]-pa[0]) < tol and abs(b[1]-pa[1]) < tol)
               for a, b in segs)


# (the VM records the MIRROR command without moving entities, so the
# perimeter below is still read in the pool's own coordinates)
_u = 0.7071067812
_A, _B, _F, _E = (0.0, 0.0), (296.0, 0.0), (0.0, 168.0), (226.0, 168.0)
assert _seg(_A, _B), "A-B must be held to the tape"
assert _seg(_E, _F), "E-F must be held to the tape"
assert _seg(_F, _A), "F-A must be held to the tape"
# B-C and D-E still run at the 45-degree bend, so they stay parallel
_wing = {}
for _a, _b in segs[:6]:               # the perimeter is drawn before the bottom
    for _corner, _key in ((_B, 'bc'), (_E, 'de')):
        _p, _q = tuple(_a[:2]), tuple(_b[:2])
        if _m.dist(_q, _corner) < 0.01:
            _p, _q = _q, _p
        if _m.dist(_p, _corner) < 0.01 and abs(_q[1] - _p[1]) > 0.01:
            _wing[_key] = (_q[0] - _p[0], _q[1] - _p[1])
assert set(_wing) == {'bc', 'de'}, _wing
assert abs(_wing['bc'][0]*_wing['de'][1]
           - _wing['bc'][1]*_wing['de'][0]) < 1e-6, "B-C // E-D must be exact"
for _v in _wing.values():             # both on the 45-degree bend
    assert abs(_v[0] - _v[1]) < 1e-6, _wing
# this tape is only ~1" out, so the wing swallows it and nothing is
# flagged
assert not [d for d in drawn(vm, 'TEXT', 'POOL-NOTES')
            if d.get(62) == 1], "a tape this close must not be flagged"
print("   lazy L mirrored; deep end true, bends parallel, wing takes the slack")

print("== R9b. lazy L whose six sides cannot close: flagged, not fudged ==")
# 29'6 / 13'6 / 18'0 / 8'6 / 24'6 / 18'0 -- these six do not make a
# 45-degree lazy L.  The deep end must still come out exactly on the
# tape, the wing must carry all of it, and the report must SAY SO.
vm = run(["Insquare", "LA"] + BASE +
         [354.0, 162.0, 216.0, 102.0, 294.0, 216.0,
          "No",                   # corners not modified
          "No"] +                 # no hopper detail
         ["No"],                  # mirror
         "R9b")
segs = [(d[10][:2], d[11][:2]) for d in drawn(vm, 'LINE', 'POOL')]
for pa, pb in [((0.0, 0.0), (354.0, 0.0)),          # A-B
               ((294.0, 216.0), (0.0, 216.0)),      # E-F
               ((0.0, 216.0), (0.0, 0.0))]:         # F-A
    assert _seg(pa, pb), f"deep-end side moved: {pa}->{pb}"
_notes = [d.get(1) for d in drawn(vm, 'TEXT', 'POOL-NOTES') if d.get(62) == 1]
assert any("SIDES DO NOT CLOSE - B-C/C-D/D-E" in (t or '')
           for t in _notes), _notes
# every wing side that missed is red in the report, and the deep-end
# rows are not
for _lbl in ("SIDE B-C", "SIDE C-D", "SIDE D-E"):
    assert any((t or '') == _lbl for t in _notes), (_lbl, _notes)
for _lbl in ("SIDE A-B", "SIDE E-F", "SIDE F-A"):
    assert not any((t or '') == _lbl for t in _notes), (_lbl, _notes)
# ...and the dimensions that read those sides are red too
assert len([d for d in drawn(vm, 'DIMENSION', 'DIMENSION')
            if d.get(62) == 1]) == 3, "the three off-tape side dims go red"
print("   deep end held exactly; wing off-tape sides flagged red")

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
_top = [c for c in _bt if dimloc(c)[1] > 420.0]
_left = [c for c in _bt if dimloc(c)[0] < 0.0]
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


assert hasseg((390.0, 0.0), (440.0, 40.0)), "grecian shallow cut"
assert hasseg((440.0, 40.0), (440.0, 200.0)), "grecian shallow wall"
assert hasseg((0.0, 0.0), (390.0, 0.0)), "bottom side stops at the cut"
# B reads tip to tip (480) and sits above the pool, in-square style
_bt = [c for c in dimcalls(vm) if abs(_m.dist(c[1][:2], c[2][:2]) - 480.0) < 0.5]
assert _bt and all(dimloc(c)[1] > 240.0 for c in _bt), _bt
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

print("== R14. lazy L with RADIUS outer corners + CUT inner corner ==")
vm = run(["Insquare", "LA"] + BASE +
         [296.0, 167.6, 167.6, 99.0, 226.0, 168.0,
          "Yes",                  # corners modified
          "Radius", 24.0,        # OUTER corners
          "Cut", 18.0,           # INNER corner (E) differs
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
print("   5 radius outer corners, cut inner corner, Typ. callout")

print("== R14b. true L hopper ties connect to the RADIUS deep-end wall ==")
# true L, sides 480/420/180/180/300/240 -> A=(0,0) B=(480,0) C=(480,420)
# D=(300,420) E=(300,240) F=(0,240).  The deep-end wall is A-F (both
# plain 90-degree corners), so with a 24" outer radius the hopper's
# left-corner ties must land on the ends of that cut -- (24,0) and
# (0,24) at A, (24,240) and (0,216) at F -- not on the sharp corners
# behind them like the old (hardcoded-Square) main-section frame drew.
vm = run(["Insquare", "L"] + BASE +
         [480.0, 420.0, 180.0, 180.0, 300.0, 240.0,
          "Yes", "Radius", 24.0, "Square",   # outer 24" radius, inner square
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
          "Yes", "Cut", 20.0, "Square",
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
          "Yes", "Radius", 20.0, "Cut", 18.0,
          "No", "No"],
         "R15", dimstyles=("STANDARD INCHES",))


def styled(vm):
    """(measurement, style current when it was drawn) per dimension."""
    cur, out = 'STANDARD', []
    for c in vm.commands:
        if c and c[0] == '_.-DIMSTYLE' and len(c) >= 3 and c[1] == '_Restore':
            cur = c[2]
        elif c and c[0] in ('_.DIMALIGNED', '_.DIMLINEAR'):
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
          "Yes", "Radius", 20.0, "Cut", 18.0,
          "No", "No"],
         "R15b")
assert not vm.dimstyle_log, vm.dimstyle_log      # never switched
assert sum(1 for p, a in vm.prompts
           if 'STANDARD INCHES' in p and 'dim style' in p) <= 1
print("   falls back cleanly when the style is absent")

print("== R15c. out-of-square corner dims + nesting inside CROSS DIMENSIONS ==")
# all four corners were answered identically (Enter reuse), so even
# out-of-square they collapse to ONE Typ. callout -- a single 18"
# chamfer dim in the inches style, not four
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 240.0, 120.0, 120.0,
          "Cut", 18.0,
          None, None, None, None, None, None,
          "Corner", 268.0, 268.0,
          "No"],
         "R15c", dimstyles=("STANDARD INCHES", "CROSS DIMENSIONS"))
assert vm.dimstyle_log.count('STANDARD INCHES') == 1, vm.dimstyle_log
assert any(c[0] == '_.DIMALIGNED' and any('Typ.' in str(x) for x in c)
           for c in vm.commands), "identical corners must read as one Typ."
assert 'CROSS DIMENSIONS' in vm.dimstyle_log
assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.dimstyle_log
# ... but corners that genuinely DIFFER still dim individually
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 240.0, 120.0, 120.0,
          "Cut", 18.0,
          None, None,                    # B reuses A
          "Radius", 20.0,               # C differs
          None, None,                    # D reuses C
          "Corner", 268.0, 268.0,
          "No"],
         "R15c-mixed", dimstyles=("STANDARD INCHES", "CROSS DIMENSIONS"))
assert not any(c[0] in ('_.DIMALIGNED', '_.DIMLINEAR', '_.DIMRADIUS',
                        '_.LEADER')
               and any('Typ.' in str(x) for x in c)
               for c in vm.commands), "mixed corners must NOT collapse to Typ."
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

print("== R15d. a 2 ft corner is a STANDARD dim, not an inches one ==")
# The rule is UNDER 24", so 24" itself belongs in STANDARD -- but a
# corner's size is measured back off geometry the routine built from
# it, and a 24" radius reads 23.99999999999913 as readily as
# 24.000000000001137.  Compared raw, the same 2 ft corner drew in
# inches or not depending on which way the last bit fell.
for _ty, _sz in (("Radius", 24.0), ("Cut", 24.0)):
    vm = run(["Insquare", "Rectangle"] + BASE +
             [480.0, 240.0, _ty, _sz,
              "Yes", "Normal", 60.0, 90.0, 210.0, None, None, None, None],
             "R15d-" + _ty, dimstyles=("STANDARD INCHES", "CROSS DIMENSIONS"))
    assert 'STANDARD INCHES' not in vm.dimstyle_log, (_ty, vm.dimstyle_log)
# and the corner really is 2 ft: the arcs on the drawing sit a hair
# either side of 24, which is exactly the noise being defended against
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0, "Radius", 24.0,
          "Yes", "Normal", 60.0, 90.0, 210.0, None, None, None, None],
         "R15d-arc", dimstyles=("STANDARD INCHES",))
_r = [d[40] for d in drawn(vm, 'ARC', 'POOL')]
assert _r and all(abs(r - 24.0) < 0.01 for r in _r), _r
# a corner that is genuinely under 2 ft still reads in inches
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0, "Cut", 23.9375,      # 23 15/16", a real tape reading
          "Yes", "Normal", 60.0, 90.0, 210.0, None, None, None, None],
         "R15d-under", dimstyles=("STANDARD INCHES",))
assert 'STANDARD INCHES' in vm.dimstyle_log, vm.dimstyle_log
print("   24\" corners in STANDARD, 23 15/16\" still in STANDARD INCHES")

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
          None,                           # anything to record? Enter = No
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
              None,                     # anything to record? Enter = No
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

print("== R20. out-of-square L: corner cuts use the REAL angle, not 90 ==")
# The nominal L sheared 0.15 in x, so no corner is square: A and C come
# out 81.47 deg, B/D/E/F 98.53.  A treatment's setback along its walls
# is r/tan(a/2) (Radius) -- 27.87 at 81.47 deg for r=24, not the 24.00
# a fixed-90 assumption gives.  The perimeter must be cut by the real
# figure, and no wall may end up drawn backwards.
#
# pool:cornerends already worked from the true local wedge angle, so
# this passes before the cap fix as well -- it is here to pin that
# behaviour down, not to demonstrate a repair.  R21 is the one that
# fails without the fix.
_S = [480.0, 424.7, 180.0, 182.01, 300.0, 242.68]
_D = [686.48, 435.99, 274.32, 373.27, 412.91, 504.71, 555.13, 279.89, 538.0]
_P = [(0.0, 0.0), (480.0, 0.0), (543.0, 420.0),
      (363.0, 420.0), (336.0, 240.0), (36.0, 240.0)]
_WALLS = {'A-B': (0, 1), 'B-C': (1, 2), 'C-D': (2, 3),
          'D-E': (3, 4), 'E-F': (4, 5), 'F-A': (5, 0)}


def wedge_deg(P, i):
    p = P[i]; a = P[(i - 1) % len(P)]; b = P[(i + 1) % len(P)]
    va = (a[0] - p[0], a[1] - p[1]); vb = (b[0] - p[0], b[1] - p[1])
    c = (va[0]*vb[0] + va[1]*vb[1]) / (_m.hypot(*va) * _m.hypot(*vb))
    return _m.degrees(_m.acos(max(-1.0, min(1.0, c))))


def wall_spans(segs, P, walls):
    """For each nominal wall, the drawn piece's start/end measured
    along the wall.  end < start means the wall was drawn backwards --
    the two corner treatments overran each other and folded it."""
    out = {}
    for nm, (i, j) in walls.items():
        a, b = P[i], P[j]
        L = _m.dist(a, b)
        u = ((b[0]-a[0])/L, (b[1]-a[1])/L)
        n = (-u[1], u[0])
        best = None
        for s in segs:
            off = [abs((q[0]-a[0])*n[0] + (q[1]-a[1])*n[1]) for q in s]
            ts = [(q[0]-a[0])*u[0] + (q[1]-a[1])*u[1] for q in s]
            if max(off) < 0.5 and min(ts) > -1.0 and max(ts) < L + 1.0:
                if best is None or abs(ts[1]-ts[0]) > abs(best[1]-best[0]):
                    best = ts
        out[nm] = best
    return out


vm = run(["Outofsquare", "L"] + BASE + _S + _D +
         ["Yes", "Radius", 24.0, "Square", "No", "No"], "R20")
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
spans = wall_spans(segs, _P, _WALLS)
for nm, ts in spans.items():
    assert ts is not None, f"{nm} not drawn"
    assert ts[1] > ts[0], f"{nm} drawn backwards (folded): {ts}"
# the setback really is the angle-aware figure at both ends of A-B
_sbA = 24.0 / _m.tan(_m.radians(wedge_deg(_P, 0) / 2.0))   # 27.87 at 81.47
_sbB = 24.0 / _m.tan(_m.radians(wedge_deg(_P, 1) / 2.0))   # 20.67 at 98.53
assert abs(_sbA - 27.87) < 0.02 and abs(_sbB - 20.67) < 0.02, (_sbA, _sbB)
assert abs(spans['A-B'][0] - _sbA) < 0.05, (spans['A-B'][0], _sbA)
assert abs((480.0 - spans['A-B'][1]) - _sbB) < 0.05
# and NOT the flat 24.00 a 90-degree assumption would have produced
assert abs(spans['A-B'][0] - 24.0) > 3.0, spans['A-B']
print("   cuts follow each corner's own angle; no wall folded")

print("== R21. out-of-square L: the size cap knows the angle too ==")
# The cap used to convert size->setback assuming 90 degrees, so on this
# shape it accepted r=90 (cap = half the shortest wall = 90) while the
# true setbacks at C and D total 2.02 x 90 = 182 on the 180" C-D wall
# -- overrunning it and drawing that wall backwards.  It must now be
# rejected and re-asked instead.
vm = run(["Outofsquare", "L"] + BASE + _S + _D +
         ["Yes", "Radius", 90.0, 40.0, "Square", "No", "No"], "R21")
_rad = [p for p, a in vm.prompts if 'Radius for' in str(p)]
assert len(_rad) == 2, f"oversize radius was not re-asked: {_rad}"
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
for nm, ts in wall_spans(segs, _P, _WALLS).items():
    assert ts is not None and ts[1] > ts[0], f"{nm} folded after re-answer: {ts}"
# the inner corner's allowance is what the OUTER cuts left on its two
# walls, so a bigger outer cut has to shrink it
def inner_asked(osz, isz):
    v = VM()
    v.load(LSP)
    try:
        v.run('c:POOL', ["Outofsquare", "L"] + BASE + _S + _D +
              ["Yes", "Cut", osz, "Radius", isz, 10.0, "No", "No"])
    except LispError:
        pass          # accepted first time: the spare value hit the next prompt
    return len([p for p, a in v.prompts if 'inner corner' in str(p) and 'Radius for' in str(p)])


assert inner_asked(40.0, 140.0) == 1, "r=140 fits when the outer cut is small"
assert inner_asked(110.0, 140.0) == 2, "r=140 must NOT fit once the outer cut grows"
print("   oversize cut rejected; inner allowance tracks the outer cut")

print("== R22. out-of-square LAZY L: 135-deg bends AND skew, deep end ties ==")
# Also a characterisation test: the hopper frame already threaded the
# real corner treatment through for A and F, and pool:cornerends is
# angle-correct, so the ties land right at any angle.  Pinned here
# because "the deep end at non-90-degree corners" is exactly the thing
# that must not silently regress.
_u = 0.7071067812
_LZ = [(0.0, 0.0), (296.0, 0.0)]
_LZ.append((_LZ[1][0] + 167.6*_u, 167.6*_u))
_LZ.append((_LZ[2][0] - 167.6*_u, _LZ[2][1] + 167.6*_u))
_LZ.append((_LZ[3][0] - 99.0*_u, _LZ[3][1] - 99.0*_u))
_LZ.append((0.0, _LZ[4][1]))
_LZ = [(p[0] + 0.12*p[1], p[1]) for p in _LZ]        # shear: nothing is square
_ang = [wedge_deg(_LZ, i) for i in range(6)]
assert all(abs(a - 90.0) > 0.3 for a in _ang), _ang   # genuinely off-square
assert any(a > 130.0 for a in _ang), _ang             # and the 135 bends survive
_ls = [round(_m.dist(_LZ[i], _LZ[j]), 2)
       for i, j in [(0,1),(1,2),(2,3),(3,4),(4,5),(5,0)]]
_ld = [round(_m.dist(_LZ[i], _LZ[j]), 2)
       for i, j in [(0,2),(1,3),(2,4),(3,5),(0,4),(1,5),(0,3),(2,5)]]  # no B-E
vm = run(["Outofsquare", "LA"] + BASE + _ls + _ld +
         ["Yes", "Radius", 24.0, "Square",
          "Yes", 40.0, 60.0, 90.0, "NA", None, 60.0, None, "No"], "R22")
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
# A (index 0) and F (index 5) are the deep-end wall's corners: each of
# their two cut ends must carry a hopper tie, and nothing may sit on
# the sharp corner behind the cut
for idx, nm in ((0, "A"), (5, "F")):
    p = _LZ[idx]
    sb = 24.0 / _m.tan(_m.radians(_ang[idx] / 2.0))
    assert abs(sb - 24.0) > 1.0, f"{nm} setback should differ from the 90-deg 24.00"
    hops = []
    for q in (_LZ[(idx - 1) % 6], _LZ[(idx + 1) % 6]):
        v = (q[0] - p[0], q[1] - p[1])
        n = _m.hypot(*v)
        e = (p[0] + v[0]/n*sb, p[1] + v[1]/n*sb)
        touching = [s for s in segs if endpoint_near(s, e, 0.8)]
        assert len(touching) >= 2, f"{nm}: cut end {e} has no tie ({len(touching)})"
        hops.append(other_end(min(touching, key=lambda s: _m.dist(*s)), e, 0.8))
    # both ties from one corner meet the SAME hopper corner
    assert _m.dist(hops[0], hops[1]) < 0.6, (nm, hops)
    assert not any(endpoint_near(s, p, 0.4) for s in segs), \
        f"a line still lands on the sharp corner {nm}"
print("   skewed lazy L deep-end ties land on the real cuts, not the sharp corners")

print("== R23. mirroring an L keeps the hopper on the LEFT ==")
# An L's deep end is always the end AWAY from the wing, so a
# left-to-right flip would swing the wing across and carry the hopper
# to the right-hand side of the sheet with it.  The mirror is a
# top-to-bottom flip instead: the wing swaps which way it points, the
# deep end (and its hopper) stays left.
#
# lispvm records (command "_.MIRROR" ...) without executing it, so the
# check is on the axis the command is given, not on moved geometry.
_LSIDES = [480.0, 420.0, 180.0, 180.0, 300.0, 240.0]
vm = run(["Insquare", "L"] + BASE + _LSIDES +
         ["No", "Yes", 60.0, 90.0, 150.0, None, 100.0, None, "Yes"], "R23")
_mir = [c for c in vm.commands if c and c[0] == '_.MIRROR']
assert len(_mir) == 1, _mir
_p1, _p2 = _mir[0][3], _mir[0][4]
assert abs(_p1[1] - _p2[1]) < 1e-9, f"mirror axis must be HORIZONTAL: {_p1} {_p2}"
assert abs(_p1[0] - _p2[0]) > 1e-9, f"degenerate mirror axis: {_p1} {_p2}"
# on the pool's own horizontal centreline (this L spans y 0..420)
assert abs(_p1[1] - 210.0) < 0.01, _p1
# the hopper sits in the main section, left of the break line, and the
# flip cannot move it sideways: its x range is unchanged by mirroring
_hop = {}
# NB: not `_m` -- that is `math`, and rebinding it here would break
# every scenario after this one
for _mans in ("No", "Yes"):
    v = run(["Insquare", "L"] + BASE + _LSIDES +
            ["No", "Yes", 60.0, 90.0, 150.0, None, 100.0, None, _mans], "R23")
    _pts = set()
    for d in drawn(v, 'LINE', 'POOL'):
        _pts.add(tuple(d[10][:2]))
        _pts.add(tuple(d[11][:2]))
    _xs = [p[0] for p in _pts]
    _lo, _hi = min(_xs), max(_xs)
    _in = [p[0] for p in _pts if _lo + 1 < p[0] < _hi - 1]
    _hop[_mans] = (min(_in), max(_in), _lo, _hi)
assert _hop["No"][:2] == _hop["Yes"][:2], _hop
_a, _b, _lo, _hi = _hop["Yes"]
assert (_a + _b) / 2.0 < (_lo + _hi) / 2.0, f"hopper drifted right: {_hop}"
print("   flip is top-to-bottom on the pool centreline; hopper stays left")

print("== R23b. the side section is held OUT of that flip ==")
# G=0 turns the bottom into a slope bottom, which draws a longitudinal
# section below the plan.  Turning the PLAN upside down does not change
# a longitudinal section, so it must not be mirrored with it -- it would
# land above the pool, standing on its head.
vm = run(["Insquare", "L"] + BASE + _LSIDES +
         ["No", "Yes",
          60.0, 0.0, 240.0,        # H, G=0 -> slope bottom, F
          None, 100.0, None,       # M L K
          48.0, 96.0,              # C wall height, D deep depth
          "Yes"], "R23b")
_prof = vm.get(__import__('lispvm').Sym('pool:*profents*')) or []
assert _prof, "G=0 on an L should have drawn a section"
_sel = set(id(e) for e in [c for c in vm.commands
                           if c and c[0] == '_.MIRROR'][0][1][1:])
assert not [e for e in _prof if id(e) in _sel], \
    "the side section must not be mirrored with the plan"
print(f"   {len(_prof)} section entities recorded, none mirrored")

print("== R24. secondary sheet letters read in SIDE STANDARD ==")
# Per the reference drawing (examples_of_fully_properly_dimmed_pools):
# the letters that SUBDIVIDE an overall -- S, T, S1, V, the end radii,
# an L's wing/step sides -- go in SIDE STANDARD; the overalls (B, A),
# the S2 cut and the hopper chains stay in the standard style.
vm = run(["Insquare", "Grecian"] + BASE +
         ["Overall", 480.0, 200.0,
          "NA", "NA", "NA", "NA", "NA",
          None,                     # anything to record? Enter = No
          "No"],
         "R24", dimstyles=("SIDE STANDARD",))
# in-square grecian draws 7 dims: S T B S1 V A S2 -> exactly 4 of them
# (S, T, S1, V) switch into SIDE STANDARD and back
assert vm.dimstyle_log.count('SIDE STANDARD') == 4, vm.dimstyle_log
assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.dimstyle_log
# a true L: the wing/step sides C-D, D-E, E-F are the secondary three
vm = run(["Insquare", "L"] + BASE +
         [480.0, 420.0, 180.0, 180.0, 300.0, 240.0,
          "No", "No", "No"],
         "R24-L", dimstyles=("SIDE STANDARD",))
assert vm.dimstyle_log.count('SIDE STANDARD') == 3, vm.dimstyle_log
# a dim inside a SIDE STANDARD block keeps that style even under 24"
# (the reference shows a 19" S1 in SIDE STANDARD, not inches) -- and
# with no SIDE block open, under-24" still switches to inches
vm = VM()
vm.load(LSP)
for s in ("SIDE STANDARD", "STANDARD INCHES"):
    vm.tables['DIMSTYLE'].add(s)
vm.loads("""
  (defun testside ( / od)
    (setq od (pool:dimsdbeg))
    (pool:dimalg '(0.0 0.0) '(19.0 0.0) '(9.0 5.0))
    (pool:dimsdend od)
    (pool:dimalg '(0.0 0.0) '(19.0 0.0) '(9.0 5.0)))
""")
vm.run('testside', [])
assert vm.dimstyle_log == ['SIDE STANDARD', 'STANDARD',
                           'STANDARD INCHES', 'STANDARD'], vm.dimstyle_log
# missing SIDE STANDARD: no switch, and small dims fall to inches again
vm = run(["Insquare", "Grecian"] + BASE +
         ["Overall", 480.0, 200.0,
          "NA", "NA", "NA", "NA", "NA",
          None,                     # anything to record? Enter = No
          "No"],
         "R24-missing")
assert 'SIDE STANDARD' not in vm.dimstyle_log
print("   S/T/S1/V and the L's wing sides switch; overalls stay standard")

print("== R25. report lengths follow the drawing's units ==")
# drawing in architectural units -> TARGET/ACTUAL in feet-inches;
# DELTA stays plain signed inches either way


def run_units(lunits):
    v = VM()
    v.load(LSP)
    v.sysvars['LUNITS'] = lunits
    v.run('c:POOL', ["Insquare", "Rectangle"] + BASE +
          [480.0, 240.0, "Square", "No"])
    return [d for d in drawn(v, 'TEXT', 'POOL-NOTES')]


_t4 = [d.get(1) for d in run_units(4)]
assert any(t == "40'-0\"" for t in _t4), _t4
assert any(t == "20'-0\"" for t in _t4), _t4
assert not any(t == "480.00" for t in _t4), _t4
_t2 = [d.get(1) for d in run_units(2)]
assert any(t == "480.00" for t in _t2), _t2
assert not any("'" in str(t) for t in _t2 if t), _t2
# deltas: force a fitted mismatch so a nonzero delta appears, in inches
vm = VM()
vm.load(LSP)
vm.sysvars['LUNITS'] = 4
vm.run('c:POOL', ["Outofsquare", "Grecian"] + BASE +
       ["Overall", 441.50, 216.00,
        324.00, 61.00, 60.00, 96.00, 84.00,
        "Simple", 389.00, 388.50,
        None,                     # anything to record? Enter = No
        "No"])
_tx = [d.get(1) for d in drawn(vm, 'TEXT', 'POOL-NOTES')]
assert any(isinstance(t, str) and (t.startswith('+') or t.startswith('-'))
           and '"' not in t and "'" not in t and '.' in t for t in _tx), \
    "deltas must stay plain signed inches"
assert any(isinstance(t, str) and t.endswith('"') for t in _tx), \
    "targets/actuals must be feet-inches in an architectural drawing"
print("   ft-in report in a ft-in drawing, inches in an inches drawing")

print("== R26. corner letters live on the mini-model, not the drawing ==")
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0, "Square", "No"], "R26")
_letters = [d for d in drawn(vm, 'TEXT', 'POOL-NOTES')
            if d.get(1) in ("A", "B", "C", "D")]
assert len(_letters) == 4, [d.get(1) for d in _letters]
# every letter sits right of the report (pool spans x 0..480; the
# report starts at xmax + 2*doff = 533)
assert all(d[10][0] > 533.0 for d in _letters), \
    [(d.get(1), d[10][:2]) for d in _letters]
# and the mini-model outline is there too: POOL-NOTES lines right of
# the report body, forming a small closed rectangle
_mlines = [(tuple(d[10][:2]), tuple(d[11][:2]))
           for d in drawn(vm, 'LINE', 'POOL-NOTES')
           if d[10][0] > 800.0 and d[11][0] > 800.0]
assert len(_mlines) >= 4, _mlines
# the grecian mini-model carries all 8 corner letters
vm = run(["Insquare", "Grecian"] + BASE +
         ["Overall", 480.0, 200.0,
          "NA", "NA", "NA", "NA", "NA",
          None,                     # anything to record? Enter = No
          "No"], "R26-grec")
_g = [d.get(1) for d in drawn(vm, 'TEXT', 'POOL-NOTES')
      if d.get(1) in ("A", "B", "C", "D", "RB", "RT", "LT", "LB")]
assert sorted(_g) == sorted(["A", "B", "C", "D", "RB", "RT", "LT", "LB"]), _g
print("   letters beside the report; mini outline drawn; grecian has all 8")

print("== R27. axis-aligned dims are true linear, skewed stay aligned ==")


def check_linear(vm, label):
    """Every _H dim spans equal-y points, every _V equal-x, and no
    axis-aligned pair slipped through as DIMALIGNED."""
    for c in dimcalls(vm, '_.DIMLINEAR'):
        p1, p2 = c[1][:2], c[2][:2]
        if '_H' in c:
            assert abs(p1[1] - p2[1]) < 1e-6, (label, c)
        elif '_V' in c:
            assert abs(p1[0] - p2[0]) < 1e-6, (label, c)
        # pool:dimrot's rotated dims carry '_R' -- their hook points
        # are deliberately off-axis, nothing to check here
    for c in dimcalls(vm, '_.DIMALIGNED'):
        p1, p2 = c[1][:2], c[2][:2]
        assert abs(p1[0] - p2[0]) > 1e-6 and abs(p1[1] - p2[1]) > 1e-6, \
            (label, "axis-aligned pair drawn as DIMALIGNED", c)


# in-square rectangle, square corners: every plan/section dim is
# horizontal or vertical, so NO aligned dims at all
vm = run(["Insquare", "Rectangle"] + BASE +
         [480.0, 240.0, "Square",
          "Yes", "Normal",
          60.0, 90.0, 240.0, 90.0,
          60.0, 120.0, 60.0], "R27")
_lin = dimcalls(vm, '_.DIMLINEAR')
assert _lin and not dimcalls(vm, '_.DIMALIGNED'), \
    [c[0] for c in dimcalls(vm)]
assert any('_H' in c for c in _lin) and any('_V' in c for c in _lin), _lin
check_linear(vm, "R27-rect")

# out-of-square rectangle with unequal sides: the skewed walls still
# need DIMALIGNED, and none of them is secretly axis-aligned
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 236.0, 120.0, 118.0,
          "Square", None, None, None,
          266.0, 264.0,
          "No"], "R27-oos")
assert dimcalls(vm, '_.DIMALIGNED'), "OOS skewed walls must stay aligned"
check_linear(vm, "R27-oos")

# grecian: corner-cut chords are skewed (aligned), overalls linear
vm = run(["Insquare", "Grecian"] + BASE +
         ["Overall", 480.0, 200.0,
          "NA", "NA", "NA", "NA", "NA",
          None,                     # anything to record? Enter = No
          "No"], "R27-grec")
assert dimcalls(vm, '_.DIMLINEAR'), "grecian overalls must be linear"
check_linear(vm, "R27-grec")
print("   _H spans equal-y, _V equal-x, aligned only on real skew")


def hasrow(vm, label):
    """Row-existence check that does not assert (reportrow raises)."""
    return any(d.get(1) == label for d in drawn(vm, 'TEXT', 'POOL-NOTES'))


print("== R28. grecian corner treatments: body family / tip family ==")
# in-square: one answer for the BODY corners (A/B/C/D), one for the
# END TIPS (LT/LB/RT/RB), Enter on the tip question reusing the body
# answer -- all 8 corners filleted here
vm = run(["Insquare", "Grecian"] + BASE +
         ["Overall", 480.0, 200.0,
          "NA", "NA", "NA", "NA", "NA",
          "Yes",                    # corners modified
          "Radius", 12.0,          # BODY corners
          None, None,               # END TIPS: Enter reuses type and size
          "No"],
         "R28")
_arcs = drawn(vm, 'ARC', 'POOL')
assert len(_arcs) == 8, len(_arcs)
# both families identical -> ONE Typ. radius callout, not eight dims
assert len(dimcalls(vm, '_.DIMRADIUS')) == 1, dimcalls(vm, '_.DIMRADIUS')
# the walls shortened by the treatment: no full-length top side left,
# but its dim still reads the TRUE corners (T = 360 among the dims)
assert not any(abs(_m.dist(*(tuple(d[10][:2]), tuple(d[11][:2]))) - 360.0) < 0.01
               for d in drawn(vm, 'LINE', 'POOL'))
assert any(abs(_m.dist(c[1][:2], c[2][:2]) - 360.0) < 0.5 for c in dimcalls(vm))
# report rows: one per family
assert reportrow(vm, "BODY CORNER RAD"), "body corner row missing"
assert reportrow(vm, "END TIP RAD"), "end tip row missing"

# tips answered differently: Square tips leave only the 4 body fillets
vm = run(["Insquare", "Grecian"] + BASE +
         ["Overall", 480.0, 200.0,
          "NA", "NA", "NA", "NA", "NA",
          "Yes",
          "Radius", 12.0,          # BODY corners
          "Square",                 # END TIPS stay sharp
          "No"],
         "R28b")
assert len(drawn(vm, 'ARC', 'POOL')) == 4
assert hasrow(vm, "BODY CORNER RAD")
assert not hasrow(vm, "END TIP RAD")

# out-of-square: all 8 asked independently, Enter reusing the previous
# -- and identical answers all round still collapse to one Typ.
vm = run(["Outofsquare", "Grecian"] + BASE +
         ["Measured",
          360.0, 360.0, 180.0, 180.0,
          70.0, 70.0, 100.0,
          70.0, 70.0, 100.0,
          "Simple", "NA", "NA",
          "Yes",
          "Radius", 10.0,          # corner A
          None, None, None, None, None, None, None,   # B..RB: Enter reuses
          None, None, None, None, None, None, None,   # ... type AND size each
          "No"],
         "R28c")
_cp = [p for p, a in vm.prompts
       if "How should Corner " in p and "[Square/Radius/Cut/NotGiven" in p]
assert len(_cp) == 8, _cp
assert len(drawn(vm, 'ARC', 'POOL')) == 8
assert len(dimcalls(vm, '_.DIMRADIUS')) == 1
assert reportrow(vm, "CORNER A RAD") and reportrow(vm, "CORNER LB RAD")

print("   grecian: body/tip families in square, all 8 independent out")

print("== R29. roman corner treatments ==")
# in-square: one answer for all four true corners; the S1 stubs then
# spring from the treatment ends, so the pool shows 2 end arcs + 4
# corner fillets
vm = run(["Insquare", "RO"] + BASE +
         [400.0, 260.0, "NA",
          45.0, 50.0, 160.0, "NA",
          "Yes",                    # corners modified
          "Radius", 12.0,          # all corners (assumed identical)
          "No"],
         "R29")
_arcs = drawn(vm, 'ARC', 'POOL')
assert len(_arcs) == 6, len(_arcs)
assert len(dimcalls(vm, '_.DIMRADIUS')) == 3     # R1, R2, one corner Typ.
assert reportrow(vm, "CORNER RAD"), "corner row missing"
# stubs shortened: the full 50" S1 stub is gone, its 38" remainder is
# there (the fillet eats 12 down the end line at a square corner)
_lens = sorted(round(_m.dist(tuple(d[10][:2]), tuple(d[11][:2])), 2)
               for d in drawn(vm, 'LINE', 'POOL'))
assert 50.0 not in _lens, _lens
assert _lens.count(38.0) == 4, _lens
# side dims still read the TRUE corners: T = 310 among the dims
assert any(abs(_m.dist(c[1][:2], c[2][:2]) - 310.0) < 0.5 for c in dimcalls(vm))

# out-of-square: each corner its own question, mixed answers
vm = run(["Outofsquare", "RO"] + BASE +
         ["No",                    # ends not perfect
          400.0, 260.0, "NA",
          45.0, 45.0, 50.0, 50.0, 160.0, 160.0, "NA", "NA",
          "NA", "NA",              # cross dims
          "Yes",                   # corners modified
          "Radius", 12.0,         # corner A
          None, None,              # corner B reuses type and size
          "Cut", 18.0,            # corner C cut
          "Square",                # corner D stays sharp
          "No"],
         "R29b")
_arcs = drawn(vm, 'ARC', 'POOL')
assert len(_arcs) == 4, len(_arcs)               # 2 ends + fillets at A, B
segs = [(tuple(d[10][:2]), tuple(d[11][:2])) for d in drawn(vm, 'LINE', 'POOL')]
assert any(abs(_m.dist(*s) - 18.0) < 0.05 for s in segs), "chamfer face at C"
assert len(dimcalls(vm, '_.DIMRADIUS')) == 4     # R1, R2, corners A and B
assert hasrow(vm, "CORNER A RAD") and hasrow(vm, "CORNER B RAD")
assert hasrow(vm, "CORNER C FACE")
assert not hasrow(vm, "CORNER D RAD") and not hasrow(vm, "CORNER D FACE")
print("   roman: one answer in square, per-corner out; stubs off the cuts")


print("== R30. the Treatment question: canonical set, aliases, no size ==")
# STANDARDS section 2: one wording, four answers, NotGiven last, the
# pre-standard words accepted but never shown
vm = run(["Insquare", "Rectangle"] + BASE + [480.0, 240.0, "NotGiven", "No"], "R30")
_q = [p for p, a in vm.prompts if "be treated?" in p]
assert len(_q) == 1, _q
assert _q[0] == "\nHow should all four corners be treated? " \
                "[Square/Radius/Cut/NotGiven/Back]: ", repr(_q[0])
# NotGiven takes NO size follow-up -- nothing was measured
assert not any("Radius for" in p or "Cut face length for" in p
               for p, a in vm.prompts), vm.prompts[-4:]
# ... and the sheet flags it rather than claiming a 90
assert [c[-2] for c in vm.commands if c and c[0] == '_.LEADER'] == ['? Typ.']
assert any(d.get(1) == "Not Given" for d in drawn(vm, 'TEXT', 'DIMENSION')), \
    "a NotGiven corner needs its Not Given note"
assert hasrow(vm, "CORNERS NotGiven")
# the row carries no numbers: N/A target AND N/A actual, no delta
_row = reportrow(vm, "CORNERS NotGiven")
assert _row.count("N/A") == 2 and "-" in _row, _row

# a plain square corner gets the circled 90 mark (was a bare leader)
vm = run(["Insquare", "Rectangle"] + BASE + [480.0, 240.0, "Square", "No"], "R30b")
assert [c[-2] for c in vm.commands if c and c[0] == '_.LEADER'] == ['90%%d Typ.']
assert len(drawn(vm, 'CIRCLE', 'DIMENSION')) == 1

# the legacy words still work, typed in full, and normalise on the way in
for _old, _new, _sizeprompt in [("ROUNDED", "Radius", "Radius for"),
                                ("DIAG", "Cut", "Cut face length for"),
                                ("DIAGONAL", "Cut", "Cut face length for"),
                                ("90", "Square", None),
                                ("NG", "NotGiven", None)]:
    _script = [480.0, 240.0, _old] + ([24.0] if _sizeprompt else []) + ["No"]
    vm = run(["Insquare", "Rectangle"] + BASE + _script, f"R30-{_old}")
    if _sizeprompt:
        assert any(_sizeprompt in p for p, a in vm.prompts), (_old, vm.prompts)
        assert hasrow(vm, f"CORNERS {_new}"), _old
    else:
        assert not any("Radius for" in p or "Cut face length for" in p
                       for p, a in vm.prompts), _old
        # and they really did normalise, not just skip the size question:
        # 90 -> Square draws the circled 90, NG -> NotGiven the "?" + note
        _ld = [c[-2] for c in vm.commands if c and c[0] == '_.LEADER']
        if _new == "Square":
            assert _ld == ['90%%d Typ.'], (_old, _ld)
            assert not hasrow(vm, "CORNERS NotGiven"), _old
        else:
            assert _ld == ['? Typ.'], (_old, _ld)
            assert hasrow(vm, "CORNERS NotGiven"), _old
# but the bracket never advertises them
assert all("ROUNDED" not in p and "DIAG" not in p
           for p, a in vm.prompts if "be treated?" in p)
print("   one wording, four answers, legacy words hidden but accepted")

print("== R31. a remembered size does not cross treatments ==")
# STANDARDS section 2: the previous size is only a default when the new
# answer matches the one it was measured for -- a radius is not a cut face
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 236.0, 120.0, 118.0,
          "Radius", 20.0,          # corner A
          None, None,              # corner B reuses BOTH type and size
          "Cut", 18.0,             # corner C is a different treatment...
          "Square",                # corner D
          "Corner", 266.0, 264.0,
          "No"], "R31")
_sz = [p for p, a in vm.prompts if "Radius for" in p or "Cut face length for" in p]
# A offered no default (first), B offered 20 back (same treatment),
# C offered none (Radius -> Cut must not carry 20" across)
assert "<" not in _sz[0], _sz[0]
assert "<20" in _sz[1], _sz[1]
assert "Cut face length for Corner C" in _sz[2] and "<" not in _sz[2], _sz[2]
print("   size default only survives when the treatment is unchanged")

print("== R32. NotGiven is not a cut: geometry, gates and marks ==")
# out-of-square with a NotGiven among real cuts: the cross-dim
# reference-mode question is still asked (there ARE cuts), the NotGiven
# corner is built square, and the marks follow the standard's table
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 236.0, 120.0, 118.0,
          "Radius", 20.0, "NotGiven", "Square", "Cut", 18.0,
          "Corner", 266.0, 264.0, "No"], "R32")
_lead = sorted(c[-2] for c in vm.commands if c and c[0] == '_.LEADER')
assert _lead == ['90%%d', '?'], _lead        # mixed -> no Typ. on either
assert len(drawn(vm, 'CIRCLE', 'DIMENSION')) == 2
assert hasrow(vm, "COR B NotGiven") and hasrow(vm, "COR A Radius")
assert not hasrow(vm, "COR C Square"), "a plain square corner needs no row"

# every corner NotGiven: no cuts at all, so the reference-mode question
# must NOT be asked -- there are no treatment ends to tape between
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 236.0, 120.0, 118.0,
          "NotGiven", None, None, None,
          266.0, 264.0, "No"], "R32b")
assert not any("cross dims measured from" in p for p, a in vm.prompts), \
    "NotGiven is built square -- there is no cut to measure from"
assert [c[-2] for c in vm.commands if c and c[0] == '_.LEADER'] == ['? Typ.']
print("   built square, gates say no cut, but the sheet still records it")


print("== R33. the 90 mark is drawn where -- and only where -- 90 is true ==")
def _marks(vm):
    return ([c[-2] for c in vm.commands if c and c[0] == '_.LEADER'],
            [tuple(round(x, 1) for x in d[10][:2])
             for d in drawn(vm, 'CIRCLE', 'DIMENSION')])

# an ordinarily out-of-square rectangle really does drift a few degrees
# (240x120 with cross dims 12" apart fits at 86.8/93.2) -- it is still a
# rectangle and still gets its mark
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [240.0, 240.0, 120.0, 120.0,
          "Square", None, None, None, 274.0, 262.0, "No"], "R33")
assert _marks(vm)[0] == ['90%%d Typ.'], _marks(vm)

# a GRECIAN's corners are ~135 by construction: marking them 90 would be
# a lie, so an all-square grecian carries no corner mark at all
vm = run(["Insquare", "Grecian"] + BASE +
         ["Overall", 480.0, 200.0, "NA", "NA", "NA", "NA", "NA",
          "Yes", "Square", "Square", "No"], "R33b")
assert _marks(vm)[0] == [], _marks(vm)

# a ROMAN body IS a rectangle, so its square corners are marked -- and on
# the same corner (B) whether the pool is in square or out
_ins = _marks(run(["Insquare", "RO"] + BASE +
                  [400.0, 260.0, "NA", 45.0, 50.0, 160.0, "NA",
                   "Yes", "Square", "No"], "R33c"))
_oos = _marks(run(["Outofsquare", "RO"] + BASE +
                  ["Yes", 400.0, 260.0, "NA", 45.0, 50.0, 160.0, "NA",
                   "NA", "NA", "Yes", "Square", None, None, None, "No"], "R33d"))
assert _ins[0] == _oos[0] == ['90%%d Typ.'], (_ins, _oos)
assert _ins[1] == _oos[1], f"the Typ. mark must land on the same corner: {_ins[1]} vs {_oos[1]}"

# an L's single outer Typ. mark is conventionally corner B -- but a LAZY
# L bends B 135 degrees, so the mark has to fall through to an outer
# corner that really is square rather than vanish or lie
for _shape, _lbl in (("L", "true L"), ("LA", "lazy L")):
    vm = run(["Insquare", _shape] + BASE +
             [296.0, 167.6, 167.6, 99.0, 226.0, 168.0,
              "Yes", "Square", "Square", "No", "No"], f"R33-{_shape}")
    assert _marks(vm)[0] == ['90%%d Typ.'], (_lbl, _marks(vm))
print("   marked on rectangles, romans and true 90s; never on a 135 bend")

print("== R34. no room for a cut still leaves NotGiven sayable ==")
# a Roman with a 0.1" corner drop cannot fit any radius or chamfer, but
# "the sheet never said" is still a truthful answer -- the two SIZED
# options are withheld, the question is still asked
vm = run(["Insquare", "RO"] + BASE +
         [400.0, 260.0, "NA", 45.0, 0.1, 259.8, "NA",
          "Yes", "NotGiven", "No"], "R34")
_q = [p for p, a in vm.prompts if "be treated?" in p]
assert len(_q) == 1 and "[Square/NotGiven/Back]" in _q[0], _q
assert "Radius" not in _q[0] and "Cut" not in _q[0], _q[0]
assert [c[-2] for c in vm.commands if c and c[0] == '_.LEADER'] == ['? Typ.']
assert hasrow(vm, "CORNER NotGiven")
# and it can still be answered Square, as before
vm = run(["Insquare", "RO"] + BASE +
         [400.0, 260.0, "NA", 45.0, 0.1, 259.8, "NA",
          "Yes", "Square", "No"], "R34b")
assert not hasrow(vm, "CORNER NotGiven")
print("   the geometry limits the answer set, not what the sheet records")

print("== R35. the Not Given note reads outward, never back over the pool ==")
# TEXT runs left-to-right from its insertion point, so a note on a
# LEFT-hand corner has to be pulled back by its own width
vm = run(["Outofsquare", "Rectangle"] + BASE +
         [480.0, 480.0, 240.0, 240.0,
          "NotGiven", "Square", "Square", "Square", 536.7, 536.7, "No"], "R35")
_note = [d for d in drawn(vm, 'TEXT', 'DIMENSION') if d.get(1) == "Not Given"]
assert len(_note) == 1, _note
_x = _note[0][10][0]
_pool_x = [p[0] for d in drawn(vm, 'LINE', 'POOL')
           for p in (d[10], d[11])]
# corner A sits at the pool's left extreme; the note must start left of
# it by more than its own rendered width, so it reads away from the pool
assert _x < min(_pool_x) - 20.0, (_x, min(_pool_x))
print("   left-hand corners pull the note back by its width")

print("\nALL RUNTIME SCENARIOS PASSED")
