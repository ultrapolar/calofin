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
from lispvm import VM, LispError, Dot, Sym, BUILTINS, NIL  # noqa: E402

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
                 '(8 . "POOL") '(410 . "Model") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 240.0 0.0)   '(42 . 0.0)
                 '(10 240.0 120.0) '(42 . 0.0)
                 '(10 0.0 120.0)   '(42 . 0.0)))'''

#: the same rectangle with its vertex order reversed, so it is DRAWN
#: clockwise -- the user's Clockwise must mean the same thing on both
RECT_CW = '''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(410 . "Model") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 0.0 120.0)   '(42 . 0.0)
                 '(10 240.0 120.0) '(42 . 0.0)
                 '(10 240.0 0.0)   '(42 . 0.0)))'''

#: a stadium: straight top and bottom, semicircular ends carried as
#: bulge-1 segments (radius 50), counter-clockwise
STADIUM = '''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(410 . "Model") '(100 . "AcDbPolyline")
                 '(90 . 4) '(70 . 1)
                 '(10 0.0 0.0)     '(42 . 0.0)
                 '(10 200.0 0.0)   '(42 . 1.0)
                 '(10 200.0 100.0) '(42 . 0.0)
                 '(10 0.0 100.0)   '(42 . 1.0)))'''

CIRCLE = '''
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(410 . "Model") '(100 . "AcDbCircle")
                 '(10 500.0 500.0 0.0) '(40 . 100.0)))'''

SPLINE = '''
  (entmake (list '(0 . "SPLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(410 . "Model") '(100 . "AcDbSpline")
                 '(10 0.0 0.0 0.0) '(10 50.0 20.0 0.0)))'''

LINE = '''
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(410 . "Model") '(100 . "AcDbLine")
                 '(10 0.0 0.0 0.0) '(11 100.0 0.0 0.0)))'''


def ab_pt(x, y, number, tab='Model', layer='POINTS', block='ab_pt',
          tag='number'):
    """An ab_pt block with its surveyed number in the number attribute.
    Carries its tab (410) like a real database entity, so the
    current-tab filter -- in ptr:clash-count and now in the Enter =
    whole drawing fallback -- can see it.  The layer, block and tag are
    arguments so the same fixture can prove the knobs that name them."""
    return f'''
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 '(8 . "{layer}") '(410 . "{tab}")
                 '(100 . "AcDbBlockReference")
                 '(2 . "{block}") (list 10 {x} {y} 0.0) '(66 . 1)))
  (entmake (list '(0 . "ATTRIB") '(8 . "{layer}")
                 '(2 . "{tag}") '(1 . "{number}")))
  (entmake (list '(0 . "SEQEND") '(8 . "{layer}")))'''


def layer(name):
    return f'''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "{name}") '(70 . 0) '(62 . 4)
                 '(6 . "Continuous")))'''


#: a CLOSED polyline with two vertices on the same spot: it passes for a
#: perimeter candidate and has no length to sweep
DEGENERATE = '''
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                 '(8 . "POOL") '(410 . "Model") '(100 . "AcDbPolyline")
                 '(90 . 2) '(70 . 1)
                 '(10 10.0 10.0)   '(42 . 0.0)
                 '(10 10.0 10.0)   '(42 . 0.0)))'''


def heavy(flag_detour, flag_frame=16):
    """An old-style (heavy) POLYLINE rectangle with two extra vertices:
    a DETOUR out to (360,60) carrying flag_detour, and a far-away
    spline FRAME point carrying flag_frame.  Which of them the tool
    walks is what ptr:*vertex-skip* decides."""
    def vert(x, y, f):
        return f'''
  (entmake (list '(0 . "VERTEX") '(100 . "AcDbEntity") '(8 . "POOL")
                 '(410 . "Model") '(100 . "AcDbVertex")
                 (list 10 {x} {y} 0.0) '(42 . 0.0) '(70 . {f})))'''
    return ('''
  (entmake (list '(0 . "POLYLINE") '(100 . "AcDbEntity") '(8 . "POOL")
                 '(410 . "Model") '(100 . "AcDb2dPolyline")
                 '(66 . 1) '(70 . 1)))'''
            + vert(0.0, 0.0, 0) + vert(240.0, 0.0, 0)
            + vert(360.0, 60.0, flag_detour)
            + vert(240.0, 120.0, 0) + vert(0.0, 120.0, 0)
            + vert(0.0, 600.0, flag_frame)
            + '''
  (entmake (list '(0 . "SEQEND") '(8 . "POOL") '(410 . "Model")))''')


def miss(vm):
    """A click that hit nothing: entsel answers nil, exactly as Enter
    does, and AutoCAD sets ERRNO 7 to say which of the two it was."""
    vm.sysvars['ERRNO'] = 7
    return None


#: a point block with NO attribute chain at all -- nowhere to write
BARE = '''
  (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(410 . "Model")
                 '(100 . "AcDbBlockReference")
                 '(2 . "ab_pt") (list 10 7.0 7.0 0.0)))'''

POINT = '''
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 '(8 . "POINTS") '(410 . "Model") '(100 . "AcDbPoint")
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
    # the leading None answers the pickfirst probe (ssget "_I") every
    # run starts with - no selection made before the command was typed
    try:
        vm.run('c:POINTRENAMER', [None] + list(script))
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
vm.sysvars['CTAB'] = 'Model'    # the clash sweep is current-tab only
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
# 11. pickfirst, and the undo bracket around the run
# ----------------------------------------------------------------------
print("pickfirst and the undo group")

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
sel = list(vm.entities)
vm.run('c:POINTRENAMER',            # bypass run(): the probe gets fed
       [sel, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'])
check("the probe is asked before anything else",
      vm.prompts[0][0] == 'ssget _I', repr(vm.prompts[0]))
check("the highlight is never asked",
      not any(p[0] == 'ssget' for p in vm.prompts), repr(vm.prompts[:3]))
got = numbers(vm)
check("the probe selection was renumbered",
      got[(0.0, 60.0)] == '1' and got[(60.0, 0.0)] == '2', repr(got))
undo = [c for c in vm.commands if c and c[0] == '_.UNDO']
check("one undo group brackets the run",
      undo == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']], repr(undo))

# ----------------------------------------------------------------------
# 12. the direction and band are remembered within the session
# ----------------------------------------------------------------------
print("session memory")

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
run(vm, [None, None, (0.0, 0.0, 0.0), 'COunterclockwise', 12.0, 1,
         'Yes'], 'memory-first')
# Enter at the direction now means COunterclockwise, not the built-in
# Clockwise start value: the bottom-run point gets 1 again
run(vm, [None, None, (0.0, 0.0, 0.0), None, None, 1, 'Yes'],
    'memory-second')
asked = '|'.join(p for p, _ in vm.prompts)
check("the second run offers the last direction",
      '<COunterclockwise>' in asked, asked[-700:])
want = vm.loads('(rtos 12.0 4 4)')
check("the second run offers the last band",
      f'<{want}>' in asked, f"wanted <{want}> in {asked[-700:]}")
got = numbers(vm)
check("Enter took the remembered direction",
      got[(60.0, 0.0)] == '1' and got[(0.0, 60.0)] == '2', repr(got))

# ----------------------------------------------------------------------
# 13. the confirm is destructive, so Enter means No
# ----------------------------------------------------------------------
print("the confirm defaults to No")

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, None],
          'default-no')
check("Enter at the confirm renames nothing",
      'Nothing renamed' in txt, txt[-400:])
got = numbers(vm)
check("the numbers are untouched",
      got[(60.0, 0.0)] == '17' and got[(0.0, 60.0)] == '9', repr(got))

# ----------------------------------------------------------------------
# 14. a number reused on another tab is not a clash
# ----------------------------------------------------------------------
print("the clash sweep is current-tab only")

vm = VM()
vm.load(LSP)
vm.loads(LAYER_POOL)
vm.sysvars['CTAB'] = 'Model'
rect = made(vm, RECT_CCW)
ins = []
for f in (ab_pt(60, 0, 17), ab_pt(0, 60, 9)):
    ins += made(vm, f)
made(vm, ab_pt(900, 900, 11, tab='Layout1'))    # a detail-sheet reuse
txt = run(vm, [rect + ins, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 10,
               'Yes'], 'clash-other-tab')
check("a Layout1 block already on 11 is not warned about",
      'Warning:' not in txt, txt[-400:])

# ----------------------------------------------------------------------
# 15. a click that MISSED is not an Enter.  entsel answers nil to both;
#     ERRNO 7 is the only thing that tells them apart, and without
#     asking, a mis-click silently accepts the very perimeter the user
#     was reaching past it to override
# ----------------------------------------------------------------------
print("a mis-click at the perimeter pick")

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
txt = run(vm, [None,       # highlight: whole drawing
               miss,       # a click that hit nothing
               None,       # NOW Enter, which does take the found loop
               (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'], 'mis-click')
check("a click that hit nothing says so instead of taking the candidate",
      'Nothing there - click on the perimeter itself, or press Enter'
      in txt, txt[-800:])
got = numbers(vm)
check("and the run carries on normally once the pick lands",
      got[(0.0, 60.0)] == '1' and got[(60.0, 0.0)] == '2', repr(got))

vm = VM()
vm.load(LSP)
vm.loads(LAYER_POOL)
lin = made(vm, LINE)[0]
vm.loads(ab_pt(20, 0, 'a') + ab_pt(80, 0, 'b'))
txt = run(vm, [None, miss, [lin, (0.0, 0.0, 0.0)],
               (0.0, 0.0, 0.0), 'CO', 6.0, 1, 'Yes'], 'mis-click-nocand')
check("with nothing found, the miss does not offer an Enter that would "
      "not work",
      'Nothing there - click on the perimeter itself.' in txt, txt[-800:])

# ----------------------------------------------------------------------
# 16. a perimeter with no length is refused -- and STOPS BEING OFFERED,
#     or Enter hands the same unusable loop back for ever
# ----------------------------------------------------------------------
print("a perimeter with no length to sweep")

vm = VM()
vm.load(LSP)
vm.loads(LAYER_POOL)
vm.loads(DEGENERATE)
lin = made(vm, LINE)[0]
vm.loads(ab_pt(20, 0, 'a') + ab_pt(80, 0, 'b'))
txt = run(vm, [None,      # highlight: whole drawing
               None,      # Enter takes the degenerate candidate...
               None,      # ...which is now gone, so Enter has nothing
               [lin, (0.0, 0.0, 0.0)],
               (0.0, 0.0, 0.0), 'CO', 6.0, 1, 'Yes'], 'degenerate')
check("a zero-length perimeter is refused by name",
      'That perimeter has no length' in txt, txt[-900:])
check("and is not offered a second time",
      'no closed polyline to fall back on' in txt, txt[-900:])
got = numbers(vm)
check("the pick that follows still works",
      got[(20.0, 0.0)] == '1' and got[(80.0, 0.0)] == '2', repr(got))

# ----------------------------------------------------------------------
# 17. a heavy POLYLINE that has been fitted: the vertices fitting ADDED
#     are the curve the sheet shows and are walked; a spline FRAME
#     control point is not on the curve and is skipped.  ptr:*vertex-skip*
#     is the mask, and flipping it back to 17 restores the old walk
# ----------------------------------------------------------------------
print("a fitted heavy POLYLINE")

FITTED = [ab_pt(120, 0, 1),      # on the bottom run
          ab_pt(360, 60, 2),     # the curve-fit detour apex
          ab_pt(120, 120, 3)]    # on the top run

vm = newvm([heavy(1)] + FITTED)   # detour flagged 1 = added by curve fit
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'CO', 6.0, 1, 'Yes'],
          'curve-fit')
check("a curve-fit vertex is part of the run, so a shot on it is ON the "
      "perimeter",
      '3 point(s) to renumber: 3 within' in txt, txt[-900:])
check("and the far-off spline frame point is skipped, or the loop would "
      "balloon past every one of them",
      '0 beyond' in txt, txt[-900:])

vm = newvm([heavy(1)] + FITTED)
vm.loads('(setq ptr:*vertex-skip* 17)')     # the pre-v1.4 walk
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'CO', 6.0, 1, 'Yes'],
          'curve-fit-old-mask')
check("with the mask set back to 17 the detour is dropped and the shot "
      "on it falls outside the band -- which is the bug the knob names",
      '2 within' in txt and '1 beyond' in txt, txt[-900:])

# ----------------------------------------------------------------------
# 18. a write that cannot land (a locked layer is the everyday reason)
#     is named in the table and counted, never reported as a rename
# ----------------------------------------------------------------------
print("a write that does not land")

real_entmod = BUILTINS[Sym('entmod')]
state = {'n': 0}


def _entmod_second_fails(vm, a):
    state['n'] += 1
    return NIL if state['n'] == 2 else real_entmod(vm, a)


BUILTINS[Sym('entmod')] = _entmod_second_fails
try:
    vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
    txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
              'locked')
finally:
    BUILTINS[Sym('entmod')] = real_entmod

check("the row that did not land says so", 'NOT WRITTEN' in txt, txt[-900:])
check("the count is what actually landed, not what was attempted",
      '1 point(s) renumbered 1-2' in txt, txt[-900:])
check("and the reason is named",
      'Warning: 1 of them could not be written' in txt
      and 'most likely locked' in txt, txt[-900:])
got = numbers(vm)
check("the point that could not be written keeps its old number",
      got[(60.0, 0.0)] == '17', repr(got))
check("the one that could is renumbered", got[(0.0, 60.0)] == '1', repr(got))

# ----------------------------------------------------------------------
# 19. nothing within the band: the "Around the perimeter" heading used
#     to print anyway, immediately followed by the "Beyond" one, over a
#     single list
# ----------------------------------------------------------------------
print("an empty band")

vm = newvm([RECT_CCW, ab_pt(120, 60, 1), ab_pt(100, 60, 2)])
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
          'empty-band')
check("with nothing near, the near heading is not printed",
      'Around the perimeter' not in txt, txt[-900:])
check("only the one that describes the list that follows",
      'Beyond 0\'-6" off the perimeter' in txt, txt[-900:])
check("and every point is still renumbered",
      '2 point(s) renumbered 1-2' in txt, txt[-900:])

# ----------------------------------------------------------------------
# 20. Enter = whole drawing means the tab you are looking at -- the same
#     scope the clash check sweeps.  Renumbering points in a layout you
#     cannot see, which the clash check would not even warn about, is
#     not what Enter was meant to say
# ----------------------------------------------------------------------
print("Enter = whole drawing stays in this tab")

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9),
            ab_pt(120, 118, 5, tab='Layout1')])
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
          'this-tab')
got = numbers(vm)
check("a point on another tab is left out of the count",
      '2 point(s) to renumber' in txt, txt[-900:])
check("and keeps its number", got[(120.0, 118.0)] == '5', repr(got))
check("the model-space points are renumbered as usual",
      got[(0.0, 60.0)] == '1' and got[(60.0, 0.0)] == '2', repr(got))

# ----------------------------------------------------------------------
# 21. the knobs at the top of the file are the ones the code reads --
#     every one set to something else, and the run follows it
# ----------------------------------------------------------------------
print("every knob is the one the code reads")

# what counts as a point, and where the number lives
vm = VM()
vm.load(LSP)
vm.loads(LAYER_POOL + layer('SHOTS') + layer('SPA'))
vm.loads('(setq ptr:*pt-layer* "SHOTS" ptr:*pt-block* "survey_pt"'
         '      ptr:*pt-tag* "PTNUM" ptr:*perim-layer* "SPA")')
vm.loads(RECT_CCW.replace('"POOL"', '"SPA"'))
vm.loads(ab_pt(60, 0, 17, layer='SHOTS', block='survey_pt', tag='PTNUM')
         + ab_pt(0, 60, 9, layer='SHOTS', block='survey_pt', tag='PTNUM'))
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
          'knobs-point')
got = numbers(vm)
check("*pt-layer*, *pt-block* and *pt-tag* name what is renumbered",
      got[(0.0, 60.0)] == '1' and got[(60.0, 0.0)] == '2', repr(got))
check("*perim-layer* names where the perimeter is looked for",
      'Enter = the highlighted closed polyline on SPA'
      in '|'.join(p for p, _ in vm.prompts), repr(vm.prompts[:4]))

# what the questions start at
vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
vm.loads('(setq ptr:*first* 100 ptr:*dir* "COunterclockwise"'
         '      ptr:*band* 24.0)')
txt = run(vm, [None, None, (0.0, 0.0, 0.0), None, None, None, 'Yes'],
          'knobs-questions')
asked = '|'.join(p for p, _ in vm.prompts)
check("*first* is the number the count is offered at",
      '<100>' in asked, asked[-700:])
check("*dir* is the direction offered", '<COunterclockwise>' in asked,
      asked[-700:])
check("*band* is the band offered", "<2'-0\">" in asked, asked[-700:])
check("and Enter at all three takes them",
      '2 point(s) renumbered 100-101' in txt, txt[-500:])

# what the report looks like
vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
vm.loads('(setq ptr:*far-pick* 500.0)')
txt = run(vm, [None, None, (100.0, 60.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
          'knobs-farpick')
check("*far-pick* raised past the miss quietens the note",
      'Note: the pick sits' not in txt, txt[-600:])

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
vm.loads('(setq ptr:*name-width* 14)')
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
          'knobs-width')
check("*name-width* is the column the old number is padded to",
      'Pt. 17            ->  Pt. 2' in txt, txt[-600:])

vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
vm.loads('(setq ptr:*dist-mode* 2 ptr:*dist-prec* 2)')
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
          'knobs-dist')
check("*dist-mode* / *dist-prec* are how every distance is written",
      'within 6.00 of the perimeter' in txt, txt[-800:])

# the sysvars saved and put back
vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
vm.loads('(setq ptr:*sysvars* (list "CMDECHO" "OSMODE"))')
vm.sysvars['OSMODE'] = 4133
run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
    'knobs-sysvars')
check("*sysvars* is the list saved and restored",
      vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1,
      repr((vm.sysvars['OSMODE'], vm.sysvars['CMDECHO'])))

# ----------------------------------------------------------------------
# 22. what the two numeric prompts refuse.  Offering Back never loosens
#     what counts as a valid answer (STANDARDS 3)
# ----------------------------------------------------------------------
print("what the numeric prompts refuse")

for label, script, why in (
        ("a band of zero", [None, None, (0.0, 0.0, 0.0), 'Clockwise', 0.0],
         'zero not allowed'),
        ("a negative band", [None, None, (0.0, 0.0, 0.0), 'Clockwise', -6.0],
         'negative not allowed'),
        ("a first number of zero",
         [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 0],
         'zero not allowed')):
    vm = newvm([RECT_CCW, ab_pt(60, 0, 17), ab_pt(0, 60, 9)])
    try:
        vm.run('c:POINTRENAMER', [None] + script)
        check(label + " is refused", False, "it was accepted")
    except LispError as e:
        check(label + " is refused", why in str(e), str(e))

# ----------------------------------------------------------------------
# 23. the band is inclusive: a point exactly at it counts as ON the
#     perimeter, which is what "within 6 inches" reads as
# ----------------------------------------------------------------------
print("the band edge")

vm = newvm([RECT_CCW, ab_pt(60, 6, 1), ab_pt(120, 7, 2)])
txt = run(vm, [None, None, (0.0, 0.0, 0.0), 'Clockwise', 6.0, 1, 'Yes'],
          'band-edge')
check("a point exactly one band off is within it, one past it is not",
      '2 point(s) to renumber: 1 within' in txt and '1 beyond' in txt,
      txt[-800:])

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all POINTRENAMER checks passed")
