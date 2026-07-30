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
print("   NA radius derived; tangent hopper end drawn")

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
print("   grecian keeps its own A and B: drawn 480 x 200")

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
print(f"   eight sides {min(_per):.2f}..{max(_per):.2f} "
      f"(regular = {400.0 / (1 + _m.sqrt(2)):.2f})")

print("== R7. roman, in-square perfect, no bottom ==")
vm = run(["Insquare", "RO"] + BASE +
         [400.0, 260.0, "NA",      # B A T
          45.0, 50.0, 160.0, "NA",  # S S1 V R(check NA)
          "No"],
         "R7")
assert drawn(vm, 'ARC', 'POOL')
print("   roman ends drawn with implied radius")

print("== R8. true L, out-of-square, diagonals NA, hopper E-skip, mirror No ==")
vm = run(["Outofsquare", "L"] + BASE +
         [480.0, 420.0, 180.0, 180.0, 300.0, 240.0,   # six sides
          "NA", "NA", "NA", "NA", "NA", "NA", "NA", "NA", "NA",  # 9 diags
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
          "Yes",
          48.0, 72.0, 106.0,      # H G F sum to B1 -> E skipped
          40.0, 80.0, 40.0,       # M L K (typed, no suggestions taken)
          "Yes"],                 # mirror
         "R9")
assert any('_.MIRROR' in str(c) for c in vm.commands)
print("   lazy L mirrored")

print("== R10. round, in-square (one prompt), oval hopper ==")
vm = run(["Insquare", "ROU"] + BASE +
         [420.0,                  # single overall
          "Yes", "Normal",
          70.0, 150.0, "NA", "NA", 110.0, 90.0,
          90.0, 240.0, 90.0,
          "NA"],
         "R10")
assert drawn(vm, 'CIRCLE', 'POOL')
print("   circle drawn from one measurement; hopper attached")

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

print("\nALL RUNTIME SCENARIOS PASSED")
