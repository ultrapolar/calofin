"""Runtime tests for POINTRENAMER: build a drawing with point blocks at
known stations round a known perimeter, run the REAL POINTRENAMER over
it, and check who ended up with which number.

The whole tool is one ordering, so the tests are about that order: the
sweep from the picked start in the asked direction, the band deciding
who is ON the perimeter, and the count carrying on over the leftovers
in the same sweep.  Every expected sequence below is worked out by hand
from the stations (bottom run s=x, right run s=240+y, and so on).

Script values answer the interactive calls in order: None is Enter, a
tuple is a click, a list of entities answers a highlight, [entity,
point] answers an entsel pick, and strings answer keywords -- validated
against the live initget list by the VM, so a keyword rename fails
loudly here.

Run: python3 tests/test_pointrenamer.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_pointrenamer.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

HERE = os.path.dirname(__file__)
LSP = os.path.join(HERE, '..', 'lisp', 'pointrenamer', 'POINTRENAMER.lsp')

#: the POOL layer plus a 240 x 120 rectangle, closed, drawn
#: counter-clockwise (bottom, right, top, left)
LAYER_POOL = '''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "POOL") '(70 . 0) '(62 . 4)
                 '(6 . "Continuous")))'''

RECT_CCW = '''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 240.0 0.0)   '(42 . 0.0)
                 '(10 240.0 120.0) '(42 . 0.0)
                 '(10 0.0 120.0)   '(42 . 0.0)))'''

#: the same rectangle with its vertex order reversed, so it is DRAWN
#: clockwise -- the user's Clockwise must mean the same thing on both
RECT_CW = '''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 0.0 120.0)   '(42 . 0.0)
                 '(10 240.0 120.0) '(42 . 0.0)
                 '(10 240.0 0.0)   '(42 . 0.0)))'''

#: a stadium: straight top and bottom, semicircular ends carried as
#: bulge-1 segments (radius 50), counter-clockwise
STADIUM = '''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 200.0 0.0)   '(42 . 1.0)
                 '(10 200.0 100.0) '(42 . 0.0)
                 '(10 0.0 100.0)   '(42 . 1.0)))'''

CIRCLE = '''
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbCircle")
                 '(10 500.0 500.0 0.0) '(40 . 100.0)))'''

SPLINE = '''
  (entmake (list '(0 . "SPLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbSpline")
                 '(10 0.0 0.0 0.0) '(10 50.0 20.0 0.0)))'''

LINE = '''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(100 . "AcDbLine")
                 '(10 0.0 0.0 0.0) '(11 100.0 0.0 0.0)))'''


def ab_pt(x, y, number):
    """An ab_pt block with its surveyed number in the number attribute."""
    return f'''
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(100 . "AcDbBlockReference")
                 '(2 . "ab_pt") (list 10 {x} {y} 0.0) '(66 . 1)))
  (entmake (list '(0 . "ATTRIB") '(8 . "POINTS")
                 '(2 . "number") '(1 . "{number}")))
  (entmake (list '(0 . "SEQEND") '(8 . "POINTS")))'''


#: a point block with NO attribute chain at all -- nowhere to write
BARE = '''
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(100 . "AcDbBlockReference")
                 '(2 . "ab_pt") (list 10 7.0 7.0 0.0)))'''

POINT = '''
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(100 . "AcDbPoint")
                 (list 10 5.0 5.0 0.0)))'''


def made(vm, src):
    """Evaluate SRC and hand back the entities it added, in order."""
    before = len(vm.entities)
    vm.loads(src)
    return vm.entities[before:]


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


def numbers(vm):
    """{(x, y): attribute value} for every attributed ab_pt INSERT."""
    out = {}
    ents = [e for e in vm.entities if e not in vm.deleted]
    for i, e in enumerate(ents):
        d = vm.entdata.get(e, [])
        if grp(d, 0) == 'INSERT' and grp(d, 66) == 1:
            ins = grp(d, 10)
            att = vm.entdata.get(ents[i + 1], [])
            out[(ins[0], ins[1])] = grp(att, 1)
    return out


def newvm(fixtures):
    vm = VM()
    vm.load(LSP)
    vm.loads(LAYER_POOL)
    for f in fixtures:
        vm.loads(f)
    return vm


def run(vm, script, label):
    try:
        vm.run('c:POINTRENAMER', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] POINTRENAMER died: {e}\n"
                             f"printed: {''.join(vm.printed)[-1500:]}"
                             ) from None
    return ''.join(vm.printed)


FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


# ----------------------------------------------------------------------
# 1. the sweep itself, both ways round, band split and the carried-on
#    count -- stations worked by hand: bottom s=x, right s=240+y,
#    top s=480+(240-x), left s=720-y
# ----------------------------------------------------------------------
print("the sweep, the band, and the carried-on count")

FIELD = [ab_pt(60, 0, 17),       # bottom       s=60
         ab_pt(240, 60, 3),      # right        s=300
         ab_pt(120, 118, 8),     # 2in in from the top   s=600
         ab_pt(0, 60, 9),        # left         s=660
         ab_pt(120, 60, 5),      # centre       60in off -> beyond
         ab_pt(230, 130, ''),    # 10in above the top    -> beyond
         BARE, POINT]

vm = newvm([RECT_CCW] + FIELD)
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
          'clockwise')
got = numbers(vm)
check("clockwise from the bottom-left corner walks up the left side",
      got[(0.0, 60.0)] == '1', repr(got))
check("then across the top", got[(120.0, 118.0)] == '2', repr(got))
check("then down the right", got[(240.0, 60.0)] == '3', repr(got))
check("then along the bottom", got[(60.0, 0.0)] == '4', repr(got))
check("the count carries on beyond the band, same sweep: the top stray "
      "before the centre",
      got[(230.0, 130.0)] == '5' and got[(120.0, 60.0)] == '6', repr(got))
check("a block with no attribute keeps none", got.get((7.0, 7.0)) is None)
check("the split is shown before anything is written",
      '6 point(s) to renumber: 4 within 0\'-6" of the perimeter, 2 beyond'
      in txt, txt[-900:])
check("what carries no number is counted out loud",
      '2 more carry no number at all' in txt, txt[-900:])
check("the old-to-new table names the old number",
      'Pt. 17      ->  Pt. 4' in txt, txt[-900:])
check("an empty old number prints as ?",
      'Pt. ?       ->  Pt. 5' in txt, txt[-900:])
check("the run is announced as one U", 'one U' in txt)

vm = newvm([RECT_CCW] + FIELD)
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'CO', 6.0, 1, 'Yes'],
          'counterclockwise')
got = numbers(vm)
check("counterclockwise reverses the loop: bottom, right, top, left",
      [got[(60.0, 0.0)], got[(240.0, 60.0)], got[(120.0, 118.0)],
       got[(0.0, 60.0)]] == ['1', '2', '3', '4'], repr(got))
check("and the leftovers swap too: the centre's station comes first now",
      got[(120.0, 60.0)] == '5' and got[(230.0, 130.0)] == '6', repr(got))

# ----------------------------------------------------------------------
# 2. clockwise means clockwise ON THE SHEET, however the polyline was
#    drawn -- the same drawing with the vertex order reversed must hand
#    out the same numbers
# ----------------------------------------------------------------------
print("winding: the drawn order does not change what Clockwise means")

vm = newvm([RECT_CW] + FIELD)
run(vm, [None, None, (0.0, 0.0, 0.0), 'CW', 6.0, 1, 'Yes'], 'cw-drawn')
got = numbers(vm)
check("a clockwise-drawn perimeter swept Clockwise gives the same order "
      "(and the hidden CW alias is accepted)",
      [got[(0.0, 60.0)], got[(120.0, 118.0)], got[(240.0, 60.0)],
       got[(60.0, 0.0)]] == ['1', '2', '3', '4'], repr(got))

# ----------------------------------------------------------------------
# 3. arcs: a bulged perimeter, stations measured along the sweep
# ----------------------------------------------------------------------
print("a bulged perimeter")

vm = newvm([STADIUM,
            ab_pt(100, 0, 1),     # bottom run     s=100
            ab_pt(250, 50, 2),    # right arc apex s=278.5
            ab_pt(100, 100, 3),   # top run        s=457.1
            ab_pt(-50, 50, 4)])   # left arc apex  s=635.6
run(vm, [None, None, (0.0, 0.0, 0.0), 'CO', 6.0, 1, 'Yes'], 'stadium-ccw')
got = numbers(vm)
check("counter-clockwise round the stadium: bottom, right apex, top, "
      "left apex",
      [got[(100.0, 0.0)], got[(250.0, 50.0)], got[(100.0, 100.0)],
       got[(-50.0, 50.0)]] == ['1', '2', '3', '4'], repr(got))

vm = newvm([STADIUM,
            ab_pt(100, 0, 1), ab_pt(250, 50, 2),
            ab_pt(100, 100, 3), ab_pt(-50, 50, 4)])
run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
    'stadium-cw')
got = numbers(vm)
check("clockwise reverses it: left apex, top, right apex, bottom",
      [got[(-50.0, 50.0)], got[(100.0, 100.0)], got[(250.0, 50.0)],
       got[(100.0, 0.0)]] == ['1', '2', '3', '4'], repr(got))

# ----------------------------------------------------------------------
# 4. a circle picked by hand: no closed polyline anywhere, so the pick
#    is the only way in, and a point ON the ring measures zero
# ----------------------------------------------------------------------
print("a circle perimeter, picked")

vm = VM()
vm.load(LSP)
vm.loads(LAYER_POOL)
circ = made(vm, CIRCLE)[0]
vm.loads(ab_pt(500, 600, 'T') + ab_pt(600, 500, 'R')
         + ab_pt(500, 400, 'B') + ab_pt(400, 500, 'L')
         + ab_pt(500, 500, 'C'))
txt = run(vm, [None, [circ, (500.0, 600.0, 0.0)], (500.0, 600.0, 0.0),
               'Clockwise', 6.0, 1, 'Yes'], 'circle')
got = numbers(vm)
check("clockwise from the top of the ring: top, right, bottom, left",
      [got[(500.0, 600.0)], got[(600.0, 500.0)], got[(500.0, 400.0)],
       got[(400.0, 500.0)]] == ['1', '2', '3', '4'], repr(got))
check("the centre is a full radius off, so it continues the count",
      got[(500.0, 500.0)] == '5', repr(got))

# ----------------------------------------------------------------------
# 5. the perimeter pick: Enter with nothing to offer explains itself, a
#    spline is refused by name, a line is accepted
# ----------------------------------------------------------------------
print("perimeter picks the tool refuses or explains")

vm = VM()
vm.load(LSP)
vm.loads(LAYER_POOL)
spl = made(vm, SPLINE)[0]
lin = made(vm, LINE)[0]
vm.loads(ab_pt(20, 0, 'a') + ab_pt(80, 0, 'b'))
txt = run(vm, [None, None, [spl, (0.0, 0.0, 0.0)], [lin, (0.0, 0.0, 0.0)],
               (0.0, 0.0, 0.0), 'CO', 6.0, 1, 'Yes'], 'refused-picks')
check("Enter with no closed polyline in the highlight explains itself",
      'no closed polyline to fall back on' in txt, txt[-1200:])
check("a spline is refused by name",
      'A SPLINE cannot be the perimeter' in txt, txt[-1200:])
got = numbers(vm)
check("the line is accepted and orders the points along it",
      got[(20.0, 0.0)] == '1' and got[(80.0, 0.0)] == '2', repr(got))

# ----------------------------------------------------------------------
# 6. the Back chain: every question walks back to the one before it,
#    and the perimeter pick reopens the highlight
# ----------------------------------------------------------------------
print("the Back chain")

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
txt = run(vm, [None,            # highlight: whole drawing
               'Back',          # perimeter -> reopen the highlight
               None,            # highlight again
               None,            # perimeter: Enter takes the POOL loop
               'Back',          # start point -> re-pick the perimeter
               None,            # perimeter again
               (0.0, 0.0, 0.0),  # start point
               'Back',          # direction -> start point
               (0.0, 0.0, 0.0),
               'Clockwise',
               'Back',          # band -> direction
               'CO',
               6.0,
               'Back',          # first number -> band
               6.0,
               5,
               'Back',          # confirm -> first number
               1,
               'Yes'], 'back-chain')
got = numbers(vm)
check("after all that walking the final answers hold: CCW from 1",
      got[(60.0, 0.0)] == '1' and got[(0.0, 60.0)] == '2', repr(got))
check("the re-asked first number is the one handed out",
      '2 point(s) renumbered 1-2' in txt, txt[-600:])

# ----------------------------------------------------------------------
# 7. No writes nothing; the numbers stay exactly as surveyed
# ----------------------------------------------------------------------
print("answering No")

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'No'],
          'no')
got = numbers(vm)
check("No leaves every number alone",
      got[(60.0, 0.0)] == '17' and got[(0.0, 60.0)] == '9', repr(got))
check("and says so", 'Nothing renamed.' in txt, txt[-400:])

# ----------------------------------------------------------------------
# 8. a different first number, and the clash warning for a point the
#    highlight never saw
# ----------------------------------------------------------------------
print("first number and the outside-the-highlight clash")

vm = VM()
vm.load(LSP)
vm.loads(LAYER_POOL)
rect = made(vm, RECT_CCW)
ins = []
for f in (ab_pt(60, 0, 17), ab_pt(0, 60, 9)):
    ins += made(vm, f)
outside = made(vm, ab_pt(900, 900, 11))     # already holds 11
txt = run(vm, [rect + ins,     # the highlight leaves the far block out
               None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 10, 'Yes'],
          'clash')
got = numbers(vm)
check("the count starts where asked",
      got[(0.0, 60.0)] == '10' and got[(60.0, 0.0)] == '11', repr(got))
asked = '|'.join(p for p, _ in vm.prompts)
check("the confirm names the range",
      'Renumber them 10 to 11?' in asked, asked[-500:])
check("a point outside the highlight already on 11 is warned about",
      'Warning: 1 point(s) OUTSIDE the highlight already carry a number'
      ' between 10 and 11' in txt, txt[-600:])
check("and it is not renamed", got[(900.0, 900.0)] == '11', repr(got))

# ----------------------------------------------------------------------
# 9. the two ways there is nothing to do
# ----------------------------------------------------------------------
print("nothing to do")

vm = newvm([RECT_CCW])
txt = run(vm, [None], 'no-points')
check("no points: it says what it looked for and asks nothing more",
      'No renumberable points in the highlight' in txt, txt[-500:])

vm = VM()
vm.load(LSP)
txt = run(vm, [None], 'empty')
check("an empty drawing: it says so and stops",
      'Nothing to renumber' in txt, txt[-300:])

# ----------------------------------------------------------------------
# 10. a mis-click far off the perimeter is noted, not silently accepted
# ----------------------------------------------------------------------
print("a far-off start pick")

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
txt = run(vm, [None, None, (100.0, 60.0, 0.0), 'Clockwise', 6.0, 1,
               'Yes'], 'far-pick')
check("a start pick well inside the pool is noted",
      'Note: the pick sits' in txt, txt[-800:])

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all POINTRENAMER checks passed")
