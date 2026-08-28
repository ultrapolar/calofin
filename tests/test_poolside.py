"""Runtime tests: load the real POOLSIDE.lsp into the AutoLISP VM and
drive c:POOLSIDE end-to-end with scripted answers, one per bottom type,
plus the NA / slack / negative-run paths and a Back-stress run.

POOLSIDE is POOL's side profile with the plan taken away, so what these
tests mostly assert is that the section is the SAME section: the floor
lands at the depths the letters say, the runs add up to B, and a run
that resolves negative is floored and flagged rather than drawn
backwards.

Script values: numbers answer distance prompts, strings answer keyword
prompts (or NA/Back), tuples are picked points.

Run: python3 tests/test_poolside.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_poolside.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'poolside', 'POOLSIDE.lsp')

BASE = [(0.0, 0.0, 0.0)]      # insertion point pick


def run(script, label, dimstyles=()):
    vm = VM()
    vm.load(LSP)
    for s in dimstyles:
        vm.tables['DIMSTYLE'].add(s)
    try:
        vm.run('c:POOLSIDE', script)
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None
    return vm


def drawn(vm, etype, layer=None):
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


def section(vm):
    """The section outline as ((x1,y1),(x2,y2)) segments on layer POOL."""
    return [(tuple(d[10][:2]), tuple(d[11][:2]))
            for d in drawn(vm, 'LINE', 'POOL')]


def hasseg(segs, pa, pb, tol=0.01):
    return any((math.dist(a, pa) < tol and math.dist(b, pb) < tol) or
               (math.dist(a, pb) < tol and math.dist(b, pa) < tol)
               for a, b in segs)


def floorpts(segs):
    """Every point the section outline touches, deduped, left to right."""
    pts = []
    for a, b in segs:
        for p in (a, b):
            if not any(math.dist(p, q) < 0.01 for q in pts):
                pts.append(p)
    return sorted(pts)


def dims(vm):
    """(p1, p2, orientation) per dimension the run drew."""
    out = []
    for c in vm.commands:
        if c and c[0] == '_.DIMLINEAR':
            out.append((tuple(c[1][:2]), tuple(c[2][:2]), c[3]))
    return out


def hasdim(vm, p1, p2, tol=0.01):
    return any((math.dist(a, p1) < tol and math.dist(b, p2) < tol) or
               (math.dist(a, p2) < tol and math.dist(b, p1) < tol)
               for a, b, _o in dims(vm))


# ---------------------------------------------------------------- 1
print("== P1. Normal hopper: H G F E, the full four-station floor ==")
vm = run(["Normal"] + BASE +
         [480.0,                       # B
          60.0, 90.0, 240.0, 90.0,     # H G F E
          42.0, 96.0,                  # C D
          "No"],                       # deep end stays left
         "P1")
segs = section(vm)
# waterline, both walls, and the floor: slope down over H, pad G at D,
# slope up over F, shallow flat E
assert hasseg(segs, (0.0, 0.0), (480.0, 0.0)), "no waterline"
assert hasseg(segs, (0.0, 0.0), (0.0, -42.0)), "no left wall"
assert hasseg(segs, (480.0, 0.0), (480.0, -42.0)), "no right wall"
assert hasseg(segs, (0.0, -42.0), (60.0, -96.0)), "no deep-end slope"
assert hasseg(segs, (60.0, -96.0), (150.0, -96.0)), "no hopper pad"
assert hasseg(segs, (150.0, -96.0), (390.0, -42.0)), "no shallow slope"
assert hasseg(segs, (390.0, -42.0), (480.0, -42.0)), "no shallow flat"
# ...and every run is dimensioned, plus the overall and the two depths
for a, b in ((0.0, 60.0), (60.0, 150.0), (150.0, 390.0), (390.0, 480.0)):
    assert any(abs(p1[0] - a) < 0.01 and abs(p2[0] - b) < 0.01
               for p1, p2, o in dims(vm) if o == '_H'), \
        "run %s-%s not dimensioned" % (a, b)
assert hasdim(vm, (0.0, 0.0), (480.0, 0.0)), "no overall B"
assert hasdim(vm, (480.0, 0.0), (480.0, -42.0)), "no C at the wall"
assert hasdim(vm, (60.0, 0.0), (60.0, -96.0)), "no D at the deep end"
assert not drawn(vm, 'TEXT', 'POOL-NOTES'), "clean run left a note"
print("   floor, walls, waterline and 7 dimensions, no notes")

# ---------------------------------------------------------------- 2
print("== P2. the guide is gone, and it was there ==")
# every guide entity is deleted by the time the run ends; the tool
# would otherwise leave a gray pool sitting under the real one
assert not [d for d in drawn(vm, 'LINE', 'POOL-NOTES')], \
    "guide lines survived the run"
guide = [e for e in vm.entities if e in vm.deleted]
assert len(guide) > 10, "the guide never drew (%d entities deleted)" % len(guide)
print("   %d guide entities drawn and cleaned up" % len(guide))

# ---------------------------------------------------------------- 3
print("== P3. NA runs read back off B ==")
vm = run(["Normal"] + BASE +
         [480.0,
          60.0, 90.0, "NA", "NA",      # F and E split the remainder
          42.0, 96.0,
          "No"],
         "P3")
segs = section(vm)
# 480 - 60 - 90 = 330, split evenly: F = E = 165
assert hasseg(segs, (150.0, -96.0), (315.0, -42.0)), "F did not take its share"
assert hasseg(segs, (315.0, -42.0), (480.0, -42.0)), "E did not take its share"
print("   two NA runs split the remainder, floor still lands on the wall")

# ---------------------------------------------------------------- 4
print("== P4. every run given but short of B: the pad absorbs it ==")
vm = run(["Normal"] + BASE +
         [480.0,
          60.0, 60.0, 240.0, 90.0,     # sums to 450, 30 short
          42.0, 96.0,
          "No"],
         "P4")
segs = section(vm)
assert hasseg(segs, (60.0, -96.0), (150.0, -96.0)), \
    "G did not absorb the 30 it was short"
assert hasseg(segs, (390.0, -42.0), (480.0, -42.0)), "E moved instead"
print("   G took the slack, the rest of the chain held")

# ---------------------------------------------------------------- 5
print("== P5. a run that resolves negative is floored and flagged ==")
vm = run(["Normal"] + BASE +
         [480.0,
          60.0, 90.0, 400.0, "NA",     # E would be -70
          42.0, 96.0,
          "No"],
         "P5")
notes = [d[1] for d in drawn(vm, 'TEXT', 'POOL-NOTES')]
assert any("FLOOR RUNS FAILED" in n for n in notes), \
    "a negative run was drawn without a note: %r" % notes
assert any("E" in n for n in notes), "the note does not name E"
red = [c for c in vm.commands if c and c[0] == '_.DIMLINEAR']
assert red, "no dimensions at all"
xs = [p[0] for p, _q, _o in dims(vm)]
assert min(xs) >= -0.01, "a run was drawn backwards past the left wall"
print("   floored, donor trimmed, note written: %r" % notes[0])

# ---------------------------------------------------------------- 6
print("== P6. G = 0 collapses the pad to a slope bottom ==")
vm = run(["Normal"] + BASE +
         [480.0,
          60.0, 0.0, 330.0, 90.0,
          42.0, 96.0,
          "No"],
         "P6")
segs = section(vm)
assert hasseg(segs, (0.0, -42.0), (60.0, -96.0)), "no deep-end slope"
assert hasseg(segs, (60.0, -96.0), (390.0, -42.0)), "no rise off the deep line"
assert not any(abs(a[1] + 96.0) < 0.01 and abs(b[1] + 96.0) < 0.01
               for a, b in segs), "a zero-length pad was drawn anyway"
print("   the pad vanished, the deep line held, no zero-length segment")

# ---------------------------------------------------------------- 7
print("== P7. the other five bottom types draw their own floor ==")

vm = run(["Wedge"] + BASE + [480.0, 60.0, 420.0, 42.0, 96.0, "No"], "wedge")
segs = section(vm)
assert hasseg(segs, (60.0, -96.0), (480.0, -42.0)), "wedge floor wrong"
assert len(floorpts(segs)) == 5, "a wedge is 5 points, got %d" % len(floorpts(segs))

vm = run(["SLope"] + BASE + [480.0, 60.0, 330.0, 90.0, 42.0, 96.0, "No"],
         "slope")
segs = section(vm)
assert hasseg(segs, (60.0, -96.0), (390.0, -42.0)), "slope floor wrong"
assert hasseg(segs, (390.0, -42.0), (480.0, -42.0)), "slope flat missing"

vm = run(["MOdflat"] + BASE + [480.0, 48.0, 336.0, 96.0, 42.0, 96.0, "No"],
         "modflat")
segs = section(vm)
assert hasseg(segs, (48.0, -96.0), (384.0, -96.0)), "modflat pad wrong"
assert hasseg(segs, (384.0, -96.0), (480.0, -42.0)), "modflat rise wrong"

vm = run(["SHallow"] + BASE +
         [480.0, 60.0, 90.0, 240.0, 90.0, 42.0, 96.0, 60.0, "No"], "shallow")
segs = section(vm)
# the shallow floor is NOT flat: it leaves the break at C2 and rises to
# C at the wall, which is the whole of what SHallow means
assert hasseg(segs, (150.0, -96.0), (390.0, -60.0)), "C2 not at the break"
assert hasseg(segs, (390.0, -60.0), (480.0, -42.0)), "shallow floor not sloped"
assert hasdim(vm, (390.0, 0.0), (390.0, -60.0)), "C2 not dimensioned"

vm = run(["Sport"] + BASE +
         [480.0, 60.0, 96.0, 144.0, 96.0, 84.0, 42.0, 96.0, "No"], "sport")
segs = section(vm)
assert hasseg(segs, (0.0, -42.0), (60.0, -42.0)), "no left shallow flat"
assert hasseg(segs, (60.0, -42.0), (156.0, -96.0)), "left slope wrong"
assert hasseg(segs, (156.0, -96.0), (300.0, -96.0)), "deep flat wrong"
assert hasseg(segs, (300.0, -96.0), (396.0, -42.0)), "right slope wrong"
assert hasseg(segs, (396.0, -42.0), (480.0, -42.0)), "no right shallow flat"
print("   Wedge, SLope, MOdflat, SHallow and Sport all land where the "
      "letters say")

# ---------------------------------------------------------------- 8
print("== P8. a sport with G = 0 is a V bottom ==")
vm = run(["Sport"] + BASE +
         [480.0, 60.0, 168.0, 0.0, 168.0, 84.0, 42.0, 96.0, "No"], "sportv")
segs = section(vm)
assert hasseg(segs, (60.0, -42.0), (228.0, -96.0)), "left face of the V wrong"
assert hasseg(segs, (228.0, -96.0), (396.0, -42.0)), "right face of the V wrong"
assert not any(abs(a[1] + 96.0) < 0.01 and abs(b[1] + 96.0) < 0.01
               for a, b in segs), "the collapsed pad was drawn"
print("   the two slopes meet at a point, no flat between them")

# ---------------------------------------------------------------- 9
print("== P9. mirroring swaps the section end for end ==")
vm = run(["Normal"] + BASE +
         [480.0, 60.0, 90.0, 240.0, 90.0, 42.0, 96.0,
          "Yes"],                      # deep end to the right
         "P9")
segs = section(vm)
assert hasseg(segs, (480.0, -42.0), (420.0, -96.0)), "H did not mirror"
assert hasseg(segs, (420.0, -96.0), (330.0, -96.0)), "the pad did not mirror"
assert hasseg(segs, (0.0, -42.0), (90.0, -42.0)), "E did not mirror"
# the run dims mirror with it, and C now hangs off the LEFT wall
assert hasdim(vm, (420.0, 0.0), (420.0, -96.0)), "D not at the mirrored deep end"
assert hasdim(vm, (0.0, 0.0), (0.0, -42.0)), "C not on the mirrored shallow wall"
print("   floor, D and C all followed the mirror")

# ---------------------------------------------------------------- 10
print("== P10. the depth range checks re-ask instead of drawing nonsense ==")
vm = run(["Normal"] + BASE +
         [480.0, 60.0, 90.0, 240.0, 90.0,
          42.0, 30.0,                  # D shallower than C -- rejected
          96.0,                        # the re-ask
          "No"],
         "P10")
segs = section(vm)
assert hasseg(segs, (60.0, -96.0), (150.0, -96.0)), "the re-asked D was not used"

vm = run(["SHallow"] + BASE +
         [480.0, 60.0, 90.0, 240.0, 90.0,
          42.0, 96.0,
          120.0,                       # C2 deeper than D -- rejected
          60.0,                        # the re-ask
          "No"],
         "P10c2")
segs = section(vm)
assert hasseg(segs, (150.0, -96.0), (390.0, -60.0)), "the re-asked C2 was not used"
print("   D must beat C, C2 must sit between them, both re-ask")

# ---------------------------------------------------------------- 11
print("== P11. Back re-asks the previous question ==")
vm = run(["Normal"] + BASE +
         [480.0,
          60.0, 900.0, "Back", 90.0,   # a fat-fingered G, taken back
          240.0, 90.0,
          42.0, "Back", 42.0, 96.0,    # and a Back out of D into C
          "No"],
         "P11")
segs = section(vm)
assert hasseg(segs, (60.0, -96.0), (150.0, -96.0)), \
    "Back did not replace the mistyped G"
assert hasseg(segs, (390.0, -42.0), (480.0, -42.0)), "the chain lost its place"
print("   Back walks the run chain and the depths without derailing")

# ---------------------------------------------------------------- 12
print("== P12. small runs take the STANDARD INCHES style when there is one ==")
vm = run(["Normal"] + BASE +
         [480.0, 12.0, 90.0, 288.0, 90.0, 42.0, 96.0, "No"],
         "P12", dimstyles=("STANDARD INCHES",))
sw = [c for c in vm.commands if c and c[0] == '_.-DIMSTYLE']
assert sw, "the small-dim style was never switched in"
assert any(c[2] == 'STANDARD INCHES' for c in sw), \
    "switched to something else: %r" % sw
print("   %d dim-style switches, and the style comes back" % len(sw))

# ---------------------------------------------------------------- 13
print("== P13. the user's settings come back ==")
vm = VM()
vm.load(LSP)
vm.sysvars['OSMODE'] = 47
vm.sysvars['LUNITS'] = 2
vm.run('c:POOLSIDE',
       ["Normal"] + BASE + [480.0, 60.0, 90.0, 240.0, 90.0, 42.0, 96.0, "No"])
assert vm.sysvars['OSMODE'] == 47, "OSMODE not restored"
assert vm.sysvars['LUNITS'] == 2, "LUNITS not restored"
vm.run('c:POOLSIDEVER', [])
print("   OSMODE and LUNITS restored, POOLSIDEVER runs")

print("\nALL POOLSIDE TESTS PASSED (%s)"
      % (os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'))
