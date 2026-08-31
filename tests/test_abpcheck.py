"""Runtime tests for ABPCHECK: build a drawing with points at known
distances off a known outline, run the REAL ABPCHECK over it, and check
what the report says.

The whole tool is one measurement, so the tests are about that number
and about who gets called out for it: a point 2" off the line with a 1"
limit is a red row, the same point with a 3" limit is not.

Script values: numbers answer distance prompts, None is Enter (which at
the selection prompt means "the whole drawing").
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
CHK = os.path.join(HERE, '..', 'lisp', 'abpcheck', 'ABPCHECK.lsp')

#: the POOL layer itself -- made here rather than through the tool's own
#: ensure-layer, which is abp: in lisp/ and cal: in the shared build
LAYER_POOL = '''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "POOL") '(70 . 0) '(62 . 4)
                 '(6 . "Continuous")))'''

#: a 240 x 120 rectangle, closed, on the POOL layer
RECT = '''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 240.0 0.0)   '(42 . 0.0)
                 '(10 240.0 120.0) '(42 . 0.0)
                 '(10 0.0 120.0)   '(42 . 0.0)))'''


def vm_with(extra=''):
    """A VM holding ABPCHECK, the rectangle, and whatever else."""
    vm = VM()
    vm.load(CHK)
    vm.loads(RECT)
    if extra:
        vm.loads(extra)
    return vm


def point(x, y, layer='POINTS'):
    return f'''
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 '(8 . "{layer}") '(100 . "AcDbPoint")
                 (list 10 {x} {y} 0.0)))'''


def ab_pt(x, y, number):
    """An ab_pt block with its surveyed number in the number attribute."""
    return f'''
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(100 . "AcDbBlockReference")
                 '(2 . "ab_pt") (list 10 {x} {y} 0.0) '(66 . 1)))
  (entmake (list '(0 . "ATTRIB") '(8 . "POINTS")
                 '(2 . "number") '(1 . "{number}")))
  (entmake (list '(0 . "SEQEND") '(8 . "POINTS")))'''


def mtext_of(vm, e):
    """An MTEXT's full text, reassembled the way AutoCAD stores it: the
    leading 250-character group 3 chunks, then the group 1 tail."""
    head, tail = [], ''
    for p in vm.entdata[e]:
        if isinstance(p, Dot):
            if p.a == 3:
                head.append(p.b)
            elif p.a == 1 and not tail:
                tail = p.b
    return ''.join(head) + tail


def report_text(vm):
    """The ABPCHECK report MTEXT in the drawing, or None."""
    for e in vm.entities:
        if e in vm.deleted:
            continue
        if kind(vm, e) == 'MTEXT':
            return mtext_of(vm, e)
    return None


def grp(d, code):
    """A DXF group's value, however it was built: (cons 10 pt) makes a
    plain list, (cons 8 "L") a dotted pair, and entity data holds both."""
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


def kind(vm, e):
    return grp(vm.entdata.get(e, []), 0)


def rings(vm):
    """Every ABPCHECK ring still in the drawing, as (x, y, radius)."""
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'CIRCLE' and grp(d, 8) == 'ABPCHECK-MISS':
            ctr = grp(d, 10)
            out.append((ctr[0], ctr[1], grp(d, 40)))
    return out


def rows(txt):
    """The report's finding lines, in order, each as (text, is_red)."""
    out = []
    for chunk in txt.split('\\P'):
        i = chunk.find('closest line is')
        if i < 0:
            continue
        out.append((chunk[chunk.index('Pt.'):].rstrip('}'),
                    '\\C1;' in chunk))
    return out


def run(vm, script):
    # the leading None answers the pickfirst probe: no pre-selection,
    # so the command asks for one, as every scenario here expects
    try:
        vm.run('c:ABPCHECK', [None] + list(script))
    except LispError as e:
        raise AssertionError(f"ABPCHECK failed: {e}") from None
    txt = report_text(vm)
    assert txt is not None, "ABPCHECK wrote no report"
    return txt


FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


# ----------------------------------------------------------------------
# 1. the distances themselves, and the shape of the line they are
#    reported on
# ----------------------------------------------------------------------
print("distances and report lines")

vm = vm_with(point(60, 0)       # on the bottom run
             + point(120, 2)    # 2" above it
             + point(240, 60)   # on the right run
             + point(0, 130)    # 10" above the top-left corner
             + ab_pt(200, 0.5, 17))
txt = run(vm, [None, 1.0])      # Enter = whole drawing, 1" is too far
found = rows(txt)

check("every point gets a line", len(found) == 5, repr(found))
check("worst first",
      found[0][0].startswith('Pt. 4 '), found[0][0] if found else '')
check('the "Pt. NN closest line is D away" shape',
      found[0][0] == 'Pt. 4     closest line is 0\'-10" away',
      repr(found[0][0]) if found else '')
check("a 2in miss measures 2in",
      any(r[0] == 'Pt. 2     closest line is 0\'-2" away' for r in found),
      repr(found))
check("a point ON the line measures zero",
      any(r[0] == 'Pt. 1     closest line is 0\'-0" away' for r in found),
      repr(found))
check("distance to a run, not to its ends: the point over the middle "
      "of the bottom run measures 2in, not 60in",
      not any('0\'-60"' in r[0] for r in found), repr(found))

# ----------------------------------------------------------------------
# 2. the limit decides who is red
# ----------------------------------------------------------------------
print("the limit decides who is red")

red = [r[0] for r in found if r[1]]
check("both points over 1in are red", len(red) == 2, repr(red))
check("the 10in point is red", any(r.startswith('Pt. 4 ') for r in red))
check("the 2in point is red", any(r.startswith('Pt. 2 ') for r in red))
check("the 1/2in point is not red",
      not any(r.startswith('Pt. 17') for r in red), repr(red))
check("the verdict counts them", '2 POINTS MORE THAN 0\'-1"' in txt,
      txt[:400])
check("the report says what too far meant",
      'Too far = more than 0\'-1"' in txt)

vm2 = vm_with(point(60, 0) + point(120, 2) + point(240, 60)
              + point(0, 130) + ab_pt(200, 0.5, 17))
txt2 = run(vm2, [None, 36.0])   # 3 feet is too far -- nothing is
check("a loose limit clears everything",
      'ALL CLEAR - every point is within 3\'-0"' in txt2, txt2[:400])
check("a clear run rings nothing", rings(vm2) == [], repr(rings(vm2)))

vm3 = vm_with(point(60, 0) + point(120, 2) + point(240, 60)
              + point(0, 130) + ab_pt(200, 0.5, 17))
txt3 = run(vm3, [None, 0.25])   # a quarter inch -- the 1/2in point joins
red3 = [r[0] for r in rows(txt3) if r[1]]
check("a tight limit catches the 1/2in point", len(red3) == 3, repr(red3))
check("and it is the block's OWN number that is called out",
      any(r.startswith('Pt. 17') for r in red3), repr(red3))

# ----------------------------------------------------------------------
# 3. the rings, and taking them away again
# ----------------------------------------------------------------------
print("rings and ABPCHECKRESCUE")

got = rings(vm)
check("one ring per point over the limit", len(got) == 2, repr(got))
check("rings sit on the points",
      sorted((round(x), round(y)) for x, y, _ in got) == [(0, 130), (120, 2)],
      repr(got))
check("rings have a real radius", all(r > 0.0 for _, _, r in got), repr(got))

vm.run('c:ABPCHECKRESCUE', [])
check("RESCUE takes the rings", rings(vm) == [], repr(rings(vm)))
check("RESCUE takes the report", report_text(vm) is None)
check("RESCUE leaves the drawing alone",
      len([e for e in vm.entities
           if e not in vm.deleted and kind(vm, e) == 'POINT']) == 4)

# ----------------------------------------------------------------------
# 4. running twice does not stack, and a stale ring is never the
#    "nearest line"
# ----------------------------------------------------------------------
print("a second run replaces the first")

vm4 = vm_with(point(60, 0) + point(120, 2) + point(0, 130))
run(vm4, [None, 1.0])
first = len(rings(vm4))
txt4 = run(vm4, [None, 1.0])
check("the rings are replaced, not doubled",
      len(rings(vm4)) == first == 2, f"{first} then {len(rings(vm4))}")
check("only one report is left",
      len([e for e in vm4.entities
           if e not in vm4.deleted and kind(vm4, e) == 'MTEXT']) == 1)
check("the second run measures the same distances as the first",
      rows(txt4) == rows(report_text(vm4)))
check("a ring from the first run is not read back as geometry",
      any(r[0] == 'Pt. 3     closest line is 0\'-10" away'
          for r in rows(txt4)), repr(rows(txt4)))

# ----------------------------------------------------------------------
# 5. curved geometry, since the segment math is the forked half of ABHD
# ----------------------------------------------------------------------
print("arcs and circles")

CIRC = '''
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbCircle")
                 '(10 0.0 0.0 0.0) '(40 . 100.0)))'''
vm5 = VM()
vm5.load(CHK)
vm5.loads(LAYER_POOL)   # the VM refuses a CIRCLE on a layer not yet made
vm5.loads(CIRC)
vm5.loads(point(100, 0) + point(0, 106) + point(0, 0))
txt5 = run(vm5, [None, 1.0])
found5 = rows(txt5)
check("a point on the circle measures zero",
      any(r[0] == 'Pt. 1     closest line is 0\'-0" away' for r in found5),
      repr(found5))
check("a point 6in outside it measures 6in",
      any(r[0] == 'Pt. 2     closest line is 0\'-6" away' for r in found5),
      repr(found5))
check("the centre is a full radius from the ring, not zero",
      any(r[0] == 'Pt. 3     closest line is 8\'-4" away' for r in found5),
      repr(found5))

# ----------------------------------------------------------------------
# 6. what it will not measure, it says out loud
# ----------------------------------------------------------------------
print("what it will not measure")

SPLINE = '''
  (entmake (list '(0 . "SPLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbSpline")
                 '(10 0.0 0.0 0.0) '(10 50.0 20.0 0.0)))'''
vm6 = vm_with(point(120, 2) + SPLINE)
txt6 = run(vm6, [None, 1.0])
check("a spline in the selection is reported, not swallowed",
      'spline/ellipse object(s) were not measured' in txt6, txt6[-500:])

# ----------------------------------------------------------------------
# 7. the two ways there is nothing to do
# ----------------------------------------------------------------------
print("nothing to measure")

vm7 = vm_with()                  # the rectangle, no points
vm7.run('c:ABPCHECK', [None, None])  # no limit is asked for -- it stops first
check("no points: it says so and asks nothing",
      any('No survey points' in p for p in vm7.printed),
      repr(vm7.printed[-3:]))
check("no points: no report is written", report_text(vm7) is None)

vm8 = VM()
vm8.load(CHK)
vm8.loads(point(10, 10) + point(20, 20))
vm8.run('c:ABPCHECK', [None, None])  # points, but nothing to measure against
check("no lines: it says so and asks nothing",
      any('no' in p and 'lines, arcs or polylines' in p
          for p in vm8.printed),
      repr(vm8.printed[-3:]))
check("no lines: no report is written", report_text(vm8) is None)

# ----------------------------------------------------------------------
print("pickfirst")

vm9 = vm_with(point(120, 2))
sel9 = [e for e in vm9.entities if e not in vm9.deleted]
vm9.run('c:ABPCHECK', [sel9, 1.0])   # only the "_I" probe and the limit
check("a selection made before the command answers the probe",
      vm9.prompts[0][0] == 'ssget _I', repr(vm9.prompts[0]))
check("the Highlight prompt is never asked",
      not any(p[0] == 'ssget' for p in vm9.prompts), repr(vm9.prompts))
check("and the report still lands", report_text(vm9) is not None)

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all ABPCHECK checks passed")
