"""AUTODIM's dimension rules, driven in the AutoLISP VM.

Covers what AutoDim.lsp promises about the dims it places:

  * every plan dim goes in "SIDE STANDARD", anything measuring under
    12" in "STANDARD INCHES" instead, and the two overall dims in
    "STANDARD"
  * a place that is dimensioned already is left alone - same two
    extension line origins either way round, dim line within a foot
  * the overall dims still go in when a side of the plan measures the
    same thing, because they sit two feet further out
  * a dim chain breaks where a span is taken and where the style has to
    change, instead of dragging a whole DIMCONTINUE run into one style
  * a style the drawing does not have falls back to the one that was
    current when the command started

The VM's (command "_.DIMALIGNED" ...) / "_.DIMLINEAR" stub leaves a
DIMENSION entity behind carrying groups 13, 14 and 10 and the style
that was current - which is exactly what these rules are made of.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'autodim', 'AutoDim.lsp')
STYLES = {'STANDARD', 'SIDE STANDARD', 'STANDARD INCHES'}

_probe = VM()
_probe.load(LSP)
#: The file's Back sentinel.  The grouped build calls the library's ask
#: helpers, which return CAL-BACK, so a stub standing in for a step that
#: can be backed out of has to hand back whichever one this tier uses.
BACK = 'CAL-BACK' if _probe.globals.get('cal:askkw') else 'AD-BACK'


def fresh(styles=STYLES):
    """A VM with AutoDim loaded, the named dim styles in the drawing and
    a run already begun on an empty drawing."""
    vm = VM()
    vm.load(LSP)                            # CALOFIN_LISP_ROOT picks the tier
    vm.tables['DIMSTYLE'] = set(styles)
    vm.script = [None]                      # ad:begin's ssget: no dims yet
    vm.loads('(ad:begin)')
    return vm


def dims(vm):
    """Every dimension the run has left behind, as
    (style, origin1, origin2, dimline-point)."""
    out = []
    for e in vm.entities:
        data = vm.entdata.get(e, [])
        if not any(isinstance(g, Dot) and g.a == 0 and g.b == 'DIMENSION'
                   for g in data):
            continue
        sty = next(g.b for g in data if isinstance(g, Dot) and g.a == 3)
        pts = {g[0]: tuple(g[1:3]) for g in data
               if isinstance(g, list) and g and g[0] in (13, 14, 10)}
        out.append((sty, pts.get(13), pts.get(14), pts.get(10)))
    return out


def rescan(vm):
    """Re-read the drawing the way a second command run would."""
    vm.script = [list(vm.entities) or None]
    vm.loads('(ad:dimscan)')


#: A 10ft x 6ft plan whose dims already reach a foot clear of it on the
#: top and the left.  ad:ssbox is cal:bbox-ss in the grouped build, so
#: both names are stubbed and the test reads the same on either tier.
PLANBOX = """
  (defun ad:ssbox    (ss) (list (list 0.0 0.0 0.0) (list 120.0 72.0 0.0)))
  (defun cal:bbox-ss (ss) (list (list 0.0 0.0 0.0) (list 120.0 72.0 0.0)))
  (defun ad:dimextents (plan) (list (list -15.0 -15.0 0.0)
                                    (list 135.0 87.0 0.0)))"""


def pt(x, y):
    return '(list %.4f %.4f 0.0)' % (x, y)


def aligned(vm, p1, p2, loc, base='ad:*style-plan*', note=''):
    return vm.loads('(ad:putaligned %s %s %s %s "%s")'
                    % (pt(*p1), pt(*p2), pt(*loc), base, note))


print('== the style follows what the dim measures ==')
vm = fresh()
# a 5' side, then an 8" step riser, both asked for in the plan style
assert aligned(vm, (0, 0), (60, 0), (0, -12)) == 1
assert aligned(vm, (0, 40), (8, 40), (0, 52)) == 1
got = [d[0] for d in dims(vm)]
assert got == ['SIDE STANDARD', 'STANDARD INCHES'], got
print('   60" -> SIDE STANDARD, 8" -> STANDARD INCHES')

# exactly 12" is not "under 12 inches"
assert vm.loads('(ad:styfor 12.0 ad:*style-plan*)') == 'SIDE STANDARD'
assert vm.loads('(ad:styfor 11.999 ad:*style-plan*)') == 'STANDARD INCHES'
print('   the cut is at 12" itself, not below it')


print('== a place that is dimensioned already is left alone ==')
vm = fresh()
assert aligned(vm, (0, 0), (60, 0), (30, -12)) == 1
assert aligned(vm, (0, 0), (60, 0), (30, -12)) == 0        # the same dim
assert aligned(vm, (60, 0), (0, 0), (30, -12)) == 0        # the other way round
assert aligned(vm, (0, 0), (60, 0), (30, -18)) == 0        # nudged 6", same dim
assert len(dims(vm)) == 1, dims(vm)
assert vm.loads('ad:*skipped*') == 3
print('   the same span, reversed, and nudged half a foot: all skipped')

# ...and the drawing's own dims count, not just this run's
rescan(vm)
assert aligned(vm, (0, 0), (60, 0), (30, -12)) == 0
assert len(dims(vm)) == 1
print('   a second run reads them back out of the drawing and skips them')

# a dim of the same span far enough out is its own dim, not a repeat
assert aligned(vm, (0, 0), (60, 0), (30, -36)) == 1
# and the other side of the span is never the same dim
assert aligned(vm, (0, 0), (60, 0), (30, 12)) == 1
assert len(dims(vm)) == 3, dims(vm)
print('   2ft out, and the far side, are dims of their own')


print('== the two overall dims ==')
vm = fresh()
# the plan is 10ft x 6ft; the dims around it already reach a foot
# clear of it on the top and the left
vm.loads(PLANBOX)
assert vm.loads('(ad:overall (list "<ss>"))') == 2
wide, tall = dims(vm)
assert wide[0] == 'STANDARD' and tall[0] == 'STANDARD', dims(vm)
# the width dim spans the plan, 2ft above the topmost dim (87 + 24)
assert wide[1] == (0.0, 72.0) and wide[2] == (120.0, 72.0), wide
assert wide[3] == (60.0, 111.0), wide
# the height dim spans the plan, 2ft left of the left-most dim (-15 - 24)
assert tall[1] == (0.0, 0.0) and tall[2] == (0.0, 72.0), tall
assert tall[3] == (-39.0, 36.0), tall
assert [c[0] for c in vm.commands if c[0].startswith('_.DIM')] == \
    ['_.DIMLINEAR', '_.DIMLINEAR']
assert '_H' in vm.commands[-2] and '_V' in vm.commands[-1]
print('   width 2ft above the topmost dim, height 2ft left of the left-most')
print('   both linear, both in STANDARD')

# a rectangular plan has a perimeter dim measuring the very same span:
# the overall dims still go in, because they are two feet further out
vm = fresh()
vm.loads(PLANBOX)
assert vm.loads('(ad:putlinear %s %s %s "_H" ad:*style-plan*)'
                % (pt(0, 72), pt(120, 72), pt(60, 84))) == 1
assert vm.loads('(ad:overall (list "<ss>"))') == 2
assert [d[0] for d in dims(vm)] == ['SIDE STANDARD', 'STANDARD', 'STANDARD']
print('   a rectangle already dimensioned side-by-side still gets both')

# run it twice and the second time adds nothing
assert vm.loads('(ad:overall (list "<ss>"))') == 0
assert len(dims(vm)) == 3
print('   asking a second time adds nothing')


print('== chains break where a span is taken or the style changes ==')
vm = fresh()
# four spans along one line: 24", 24", 6", 24"
chain = '(list %s %s %s %s %s)' % (pt(0, 0), pt(24, 0), pt(48, 0),
                                   pt(54, 0), pt(78, 0))
assert vm.loads('(ad:dimchain %s %s ad:*style-plan*)' % (chain, pt(39, -12))) == 4
placed = dims(vm)
# DIMCONTINUE leaves no entity in the VM, so the entities are the head
# of each run: 0-24 (chained on to 48), then 48-54, then 54-78
assert [d[0] for d in placed] == ['SIDE STANDARD', 'STANDARD INCHES',
                                  'SIDE STANDARD'], placed
assert [d[1] for d in placed] == [(0.0, 0.0), (48.0, 0.0), (54.0, 0.0)]
cont = [c for c in vm.commands if c and c[0] == '_.DIMCONTINUE']
assert len(cont) == 1, vm.commands            # only the first run continues
assert vm.loads('(ad:samestyle "side standard" "SIDE STANDARD")')
print('   the 6" span splits the run out into STANDARD INCHES')

# the same chain again: every span is taken now, nothing is placed
vm.loads('(setq ad:*skipped* 0)')
assert vm.loads('(ad:dimchain %s %s ad:*style-plan*)' % (chain, pt(39, -12))) == 0
assert vm.loads('ad:*skipped*') == 4
assert len(dims(vm)) == 3
print('   running it again places nothing and counts all four as skipped')

# one span taken in the middle breaks the chain around it
vm = fresh()
assert aligned(vm, (24, 0), (48, 0), (39, -12)) == 1
assert vm.loads('(ad:dimchain %s %s ad:*style-plan*)' % (chain, pt(39, -12))) == 3
assert len(dims(vm)) == 4, dims(vm)
heads = [d[1] for d in dims(vm)]
assert heads == [(24.0, 0.0), (0.0, 0.0), (48.0, 0.0), (54.0, 0.0)], heads
print('   a taken span in the middle leaves the pieces either side')


print('== a missing style falls back, it does not strand the next dim ==')
vm = fresh(styles={'STANDARD', 'STANDARD INCHES'})   # no "SIDE STANDARD"
vm.sysvars['DIMSTYLE'] = 'STANDARD'
vm.script = [None]
vm.loads('(ad:begin)')
assert aligned(vm, (0, 0), (60, 0), (30, -12)) == 1     # wants SIDE STANDARD
assert aligned(vm, (0, 40), (8, 40), (4, 52)) == 1      # wants STANDARD INCHES
assert aligned(vm, (0, 60), (60, 60), (30, 72)) == 1    # wants SIDE STANDARD
got = [d[0] for d in dims(vm)]
assert got == ['STANDARD', 'STANDARD INCHES', 'STANDARD'], got
print('   the long dims keep the style the run started in, both times')


def draw(vm, segs):
    """Draw the segments as LINEs and hand them back as a selection set."""
    for (x1, y1), (x2, y2) in segs:
        vm.loads('(entmake (list (cons 0 "LINE") '
                 '(cons 10 (list %.4f %.4f 0.0)) '
                 '(cons 11 (list %.4f %.4f 0.0))))' % (x1, y1, x2, y2))
    ents = list(vm.entities)                    # whatever else was drawn too
    vm.script = [ents]
    vm.loads('(setq SS (ssget))')
    return ents


#: Three 10"-deep steps on a 12" run, descending to the right, drawn
#: top down from the waterline: riser, tread, riser, tread, ...
FLIGHT = [((0, 0), (0, -10)), ((0, -10), (12, -10)),
          ((12, -10), (12, -20)), ((12, -20), (24, -20)),
          ((24, -20), (24, -30)), ((24, -30), (36, -30))]

#: The same flight the other way round - the top step on the right.
MIRRORED = [((36, 0), (36, -10)), ((36, -10), (24, -10)),
            ((24, -10), (24, -20)), ((24, -20), (12, -20)),
            ((12, -20), (12, -30)), ((12, -30), (0, -30))]

#: A plain rectangular pool in plan: 10ft x 5ft, drawn square.
PLAN = [((0, 0), (0, 60)), ((0, 60), (120, 60)),
        ((120, 60), (120, 0)), ((120, 0), (0, 0))]


def looks_like_steps(segs, extra=''):
    vm = fresh()
    if extra:
        vm.loads(extra)                         # drawn first, so it is selected
    draw(vm, segs)
    return vm, vm.loads('(ad:stepprofile-p SS)')


print('== it only takes the side-view route when it looks like steps ==')
_, risers = looks_like_steps(FLIGHT)
assert risers and len(risers) == 3, risers
print('   a flight of three steps: recognised')

_, risers = looks_like_steps(MIRRORED)
assert risers and len(risers) == 3, risers
print('   the same flight facing the other way: recognised')

# a sloping pool floor at the foot of the flight is still a flight
_, risers = looks_like_steps(FLIGHT + [((36, -30), (60, -40))])
assert risers and len(risers) == 3, risers
print('   with a sloping floor at its foot: still recognised')

# closed against a back wall: the full-height vertical is the wall
_, risers = looks_like_steps(FLIGHT + [((36, -30), (36, 0)), ((36, 0), (0, 0))])
assert risers and len(risers) == 3, risers
print('   closed against a back wall: the wall is not counted as a step')

assert looks_like_steps(PLAN)[1] is None
print('   a rectangular plan: not steps')

# two verticals at the same level are not a staircase
assert looks_like_steps([((0, 0), (0, 10)), ((20, 0), (20, 10)),
                         ((0, 30), (20, 30))])[1] is None
print('   two verticals side by side at the same level: not steps')

# one riser is not a flight
assert looks_like_steps([((0, 0), (0, -10)), ((0, -10), (12, -10))])[1] is None
print('   a single riser: not steps')

# anything curved and it is not read as a square-drawn profile
assert looks_like_steps(
    FLIGHT,
    '(entmake (list (cons 0 "ARC") (cons 10 (list 40.0 -30.0 0.0)) '
    '(cons 40 5.0) (cons 50 0.0) (cons 51 3.14)))')[1] is None
print('   one arc anywhere in the selection: not steps')

# a staircase with the risers left disconnected is not one either
assert looks_like_steps([((0, 0), (0, -10)), ((0, -10), (12, -10)),
                         ((12, -14), (12, -24)), ((12, -24), (24, -24)),
                         ((0, -40), (24, -40))])[1] is None
print('   risers that do not join up: not steps')


print('== AUTODIM dimensions the step depths on the right ==')
vm = fresh()
vm.sysvars['DIMTXT'] = 0.125
vm.sysvars['DIMSCALE'] = 48                      # 2 x 0.125 x 48 = 12" < 2ft
ents = draw(vm, FLIGHT)
# the plan pick, then ad:begin's read of the drawing's dims
vm.run('c:AUTODIM', [ents, None])
placed = dims(vm)
assert len(placed) == 4, placed
assert all(d[0] == 'STANDARD INCHES' for d in placed), placed
print('   3 step depths + 1 overall, all in STANDARD INCHES')

# every depth dim sits on one line two feet right of the flight (max x
# 24 + 24), the overall two feet right of that again
assert [d[3][0] for d in placed[:3]] == [48.0, 48.0, 48.0], placed
assert placed[3][3][0] == 72.0, placed[3]
print('   the depths on one line to the right, the overall further right')

# each one measures a step, the last one the whole flight
assert [(d[1], d[2]) for d in placed] == [
    ((0.0, 0.0), (0.0, -10.0)),
    ((0.0, -10.0), (12.0, -20.0)),
    ((12.0, -20.0), (24.0, -30.0)),
    ((24.0, -30.0), (0.0, 0.0))], placed
assert all('_V' in c for c in vm.commands if c[0] == '_.DIMLINEAR')
print('   three 10" depths and a 30" overall, all vertical')

# no perimeter, stairs or floor dims were asked for - the script would
# have been exhausted at the first prompt if they had been
assert not [c for c in vm.commands if c[0] == '_.DIMALIGNED']
print('   the plan steps were skipped, as they are about a plan')

# and it is idempotent, like everything else the tool places
vm.run('c:AUTODIM', [ents, list(vm.entities)])
assert len(dims(vm)) == 4
print('   a second run over the same flight adds nothing')


print('== the branch: a plan goes the plan route, a flight does not ==')
#: The plan route needs ActiveX for its bounding boxes, which the VM has
#: no stub for, so each step is replaced by a note of having been run.
TRACE = """
  (setq ran '())
  (defun ad:dimperim (ss) (setq ran (cons "perimeter" ran)) 0)
  (defun ad:dimstairs ()  (setq ran (cons "stairs" ran)) 0)
  (defun ad:getfloor (tag obstacles back) (setq ran (cons "floor" ran)) 0)
  (defun ad:overall (plan) (setq ran (cons "overall" ran)) 0)
  (defun ad:runsteps (risers) (setq ran (cons "step depths" ran)) (princ))"""


def route(segs, answers=('Yes',)):
    vm = fresh()
    ents = draw(vm, segs)
    vm.loads(TRACE)
    vm.run('c:AUTODIM', [ents, None] + list(answers))
    return [str(x) for x in reversed(vm.globals['ran'])]


assert route(PLAN) == ['perimeter', 'stairs', 'floor', 'floor', 'overall']
print('   a rectangular plan: all five plan steps, no step depths')
assert route(FLIGHT, answers=()) == ['step depths']
print('   a flight of steps: the step depths alone, no plan steps')


print('== step 4 asks first, and takes No, Enter and Back for an answer ==')
#: The floor dims step, with every other step of the plan flow replaced
#: by a note of having been run, and Back available at the floor lines.
FLOW = """
  (setq ran '() backon "")
  (defun ad:dimperim (ss) (setq ran (cons "perimeter" ran)) 0)
  (defun ad:dimstairs () (setq ran (cons "stairs" ran)) 0)
  (defun ad:overall (plan) (setq ran (cons "overall" ran)) 0)
  (defun ad:eraseafter (mark) (setq ran (cons "rolled back" ran)) (princ))
  (defun ad:getfloor (tag obstacles back)
    (setq ran (cons tag ran))
    (if (= tag backon)
      (progn (setq backon "") '%s)
      0))""" % BACK


def plan_flow(answers, backon=''):
    """Run the plan flow with `backon` naming the one floor line the
    user backs out of."""
    vm = fresh()
    vm.loads(FLOW)
    vm.loads('(setq backon "%s")' % backon)
    vm.script = list(answers)
    vm.loads('(ad:runplan nil)')
    assert not vm.script, 'answers left over: %r' % vm.script
    return [str(x) for x in reversed(vm.globals['ran'])]


assert plan_flow(['Yes']) == ['perimeter', 'stairs', 'Floor dims 1 of 2',
                              'Floor dims 2 of 2', 'overall']
print('   Yes: two lines asked for, then the overall dims')

assert plan_flow([None]) == ['perimeter', 'stairs', 'Floor dims 1 of 2',
                             'Floor dims 2 of 2', 'overall']
print('   Enter: takes the <Yes> default')

assert plan_flow(['No']) == ['perimeter', 'stairs', 'overall']
print('   No: straight on to the overall dims, no lines asked for')

# Back at the question re-opens the stairs, erasing what they drew
assert plan_flow(['Back', 'No']) == ['perimeter', 'stairs', 'rolled back',
                                     'stairs', 'overall']
print('   Back: the stairs re-open, and what they drew is rolled back')

# Back at the FIRST floor line goes to the question, not past it - and
# nothing is rolled back, because that line had not drawn anything yet
assert plan_flow(['Yes', 'No'], backon='Floor dims 1 of 2') == [
    'perimeter', 'stairs', 'Floor dims 1 of 2', 'overall']
print('   Back at the first line: back to the question, nothing rolled back')

# Back at the SECOND floor line re-opens the first, erasing its chain
assert plan_flow(['Yes'], backon='Floor dims 2 of 2') == [
    'perimeter', 'stairs', 'Floor dims 1 of 2', 'Floor dims 2 of 2',
    'rolled back', 'Floor dims 1 of 2', 'Floor dims 2 of 2', 'overall']
print('   Back at the second line: the first re-opens, its chain rolled back')


print('== a floor dims chain runs object to object ==')
def floorchain(crossings, p1=(0, 0), p2=(60, 0)):
    """One chain along p1->p2 over a line that crosses objects at the
    given distances along it.  ad:xpoints is what reaches ActiveX, so
    the crossings it would find are supplied directly."""
    vm = fresh()
    draw(vm, [((0, -50), (0, -49))])          # something to be the obstacles
    vm.loads('(defun ad:xpoints (lobj ss) (list %s))'
             % ' '.join('(list %.4f %.4f 0.0)'
                        % (p1[0] + (p2[0] - p1[0]) * d / 60.0,
                           p1[1] + (p2[1] - p1[1]) * d / 60.0)
                        for d in crossings))
    n = vm.loads('(ad:floorchain (list %.4f %.4f 0.0) (list %.4f %.4f 0.0) '
                 '(list 30.0 -12.0 0.0) SS)' % (p1[0], p1[1], p2[0], p2[1]))
    # DIMCONTINUE leaves no entity behind, so the points it was fed are
    # read back off the command log to see the whole chain
    cont, run = [], False
    for c in vm.commands:
        if c and c[0] == '_.DIMCONTINUE':
            run = True
        elif run and len(c) == 2 and c[0] == '_non':
            cont.append(tuple(c[1][:2]))
        elif run:
            run = False
    return n, [(d[1], d[2]) for d in dims(vm)], cont, [d[0] for d in dims(vm)]


# both ends landed on an object: every break point is dimensioned
n, spans, cont, styles = floorchain([0, 20, 40, 60])
assert n == 3, (n, spans, cont)
assert spans == [((0.0, 0.0), (20.0, 0.0))], spans
assert cont == [(40.0, 0.0), (60.0, 0.0)], cont
print('   both ends on an object: 3 dims, 0 -> 20 -> 40 -> 60')

# neither end on one: the chain pulls back to the objects it crossed
n, spans, cont, styles = floorchain([20, 40])
assert n == 1, (n, spans, cont)
assert spans == [((20.0, 0.0), (40.0, 0.0))] and cont == [], (spans, cont)
print('   neither end on one: it starts and stops at the objects it crossed')

# the end alone in open drawing: it stops at the previous object
n, spans, cont, styles = floorchain([0, 20, 40])
assert n == 2, (n, spans, cont)
assert spans == [((0.0, 0.0), (20.0, 0.0))] and cont == [(40.0, 0.0)], cont
print('   the end in open drawing: it stops at the previous object')

# the start alone in open drawing: it begins at the first object
n, spans, cont, styles = floorchain([20, 40, 60])
assert n == 2, (n, spans, cont)
assert spans == [((20.0, 0.0), (40.0, 0.0))] and cont == [(60.0, 0.0)], cont
print('   the start in open drawing: it begins at the first object')

# a line that crosses nothing, or only one thing, dimensions nothing
assert floorchain([]) == (0, [], [], [])
assert floorchain([30]) == (0, [], [], [])
print('   a line crossing nothing, or one object: no dims at all')

# the chains go in "STANDARD", and a span under a foot still drops into
# inches the way every other dim the tool places does
n, spans, cont, styles = floorchain([0, 20, 60])
assert styles == ['STANDARD'], styles
print('   the chain goes in STANDARD')

n, spans, cont, styles = floorchain([0, 20, 26, 60])
assert n == 3, (n, spans, cont)
assert styles == ['STANDARD', 'STANDARD INCHES', 'STANDARD'], styles
assert cont == [], cont                       # the short span broke the run
print('   a 6" span in the middle of one still breaks out into inches')


print('== a size that repeats is called out once and noted Typ. ==')
#: The perimeter step reaches ActiveX twice - for the plan's bounding
#: box and for the rays that decide which side of a segment is clear.
#: Both are replaced: every segment is on the perimeter, dimensioned
#: outwards along +Y, and every arc outwards from its centre.
PERIM = """
  (defun ad:ssbox (ss)    (list (list 0.0 0.0 0.0) (list 240.0 240.0 0.0)))
  (defun cal:bbox-ss (ss) (list (list 0.0 0.0 0.0) (list 240.0 240.0 0.0)))
  (defun ad:perimang (p1 p2 diag eps ss) (* 0.5 pi))
  (defun ad:arcang (centre mid diag eps ss) (angle centre mid))"""


def perim(segs=(), arcs=()):
    """Dimension a perimeter of the given straight sides and arcs, and
    report what came out as (note, measurement) per dim, in order."""
    vm = fresh()
    vm.sysvars['DIMTXT'] = 0.125
    vm.sysvars['DIMSCALE'] = 48
    for (x1, y1), (x2, y2) in segs:
        vm.loads('(entmake (list (cons 0 "LINE") '
                 '(cons 10 (list %.4f %.4f 0.0)) '
                 '(cons 11 (list %.4f %.4f 0.0))))' % (x1, y1, x2, y2))
    for (cx, cy), r in arcs:
        vm.loads('(entmake (list (cons 0 "CIRCLE") '
                 '(cons 10 (list %.4f %.4f 0.0)) (cons 40 %.4f)))'
                 % (cx, cy, r))
    ents = list(vm.entities)
    vm.script = [ents]
    vm.loads('(setq SS (ssget))')
    vm.loads(PERIM)
    n = vm.loads('(ad:dimperim SS)')
    out = []
    for c in vm.commands:
        if not c or c[0] not in ('_.DIMALIGNED', '_.DIMRADIUS'):
            continue
        note = c[c.index('_T') + 1] if '_T' in c else ''
        if c[0] == '_.DIMALIGNED':
            a, b = c[2], c[4]
            out.append((note, round(math.dist(a[:2], b[:2]), 4)))
        else:
            out.append((note, 'radius'))
    return n, out


# two sides the same: one dim, noted, and the second side left to it
n, got = perim(segs=[((0, 0), (60, 0)), ((0, 40), (60, 40))])
assert n == 1, (n, got)
assert got == [('<> Typ.', 60.0)], got
print('   two equal sides: one dim, noted Typ., the other left to it')

# sides of their own are dimensioned where they are, with no note
n, got = perim(segs=[((0, 0), (60, 0)), ((0, 40), (36, 40))])
assert n == 2, (n, got)
assert got == [('', 60.0), ('', 36.0)], got
print('   two sides of different lengths: both dimensioned, neither noted')

# the note goes on the first of its size, and the odd one out still
# gets its own dim
n, got = perim(segs=[((0, 0), (60, 0)), ((0, 20), (36, 20)),
                     ((0, 40), (60, 40)), ((0, 60), (60, 60))])
assert n == 2, (n, got)
assert got == [('<> Typ.', 60.0), ('', 36.0)], got
print('   three equal and one odd: one noted dim and one plain one')


print('== curves wait until there are more than three of a size ==')
n, got = perim(arcs=[((0, 0), 18.0), ((80, 0), 18.0)])
assert n == 2 and got == [('', 'radius'), ('', 'radius')], (n, got)
print('   two equal radii: both dimensioned, neither noted')

n, got = perim(arcs=[((0, 0), 18.0), ((80, 0), 18.0), ((160, 0), 18.0)])
assert n == 3 and [g[0] for g in got] == ['', '', ''], (n, got)
print('   three equal radii: still all three, still no note')

n, got = perim(arcs=[((0, 0), 18.0), ((80, 0), 18.0),
                     ((160, 0), 18.0), ((0, 80), 18.0)])
assert n == 1, (n, got)
assert got == [('<> Typ.', 'radius')], got
print('   four equal radii: one dim, noted Typ.')

# a size below the count is unaffected by another size that is over it
n, got = perim(arcs=[((0, 0), 18.0), ((80, 0), 18.0), ((160, 0), 18.0),
                     ((0, 80), 18.0), ((80, 80), 9.0), ((160, 80), 9.0)])
assert n == 3, (n, got)
assert [g[0] for g in got] == ['<> Typ.', '', ''], got
print('   four of one radius and two of another: noted once, then both')


print('== a radius dim counts as dimensioning that arc ==')
vm = fresh()
put = ('(ad:putradius 18.0 (entlast) (list 18.0 0.0 0.0) (list 0.0 0.0 0.0) '
       '(list 40.0 40.0 0.0) ad:*style-plan* "%s")')
vm.loads('(entmake (list (cons 0 "CIRCLE") (cons 10 (list 0.0 0.0 0.0)) '
         '(cons 40 18.0)))')
assert vm.loads(put % '') == 1
assert vm.loads(put % '') == 0                  # the same arc again
assert vm.loads('ad:*skipped*') == 1
print('   the same arc twice in one run: the second is skipped')

# and one already in the drawing is read back out of it
vm = fresh()
vm.loads('(entmake (list (cons 0 "DIMENSION") (cons 410 "Model") '
         '(cons 70 4) (cons 10 (list 0.0 0.0 0.0)) '
         '(cons 15 (list 18.0 0.0 0.0))))')
rescan(vm)
vm.loads('(entmake (list (cons 0 "CIRCLE") (cons 10 (list 0.0 0.0 0.0)) '
         '(cons 40 18.0)))')
assert vm.loads(put % '') == 0
assert vm.loads('(ad:raddimmed-p (list 0.0 0.0 0.0) 18.0)')
assert not vm.loads('(ad:raddimmed-p (list 0.0 0.0 0.0) 24.0)')
print('   a radius dim already in the drawing is read back and respected')


print('== the arc a polyline bulge describes ==')
vm = fresh()
# A bulge of 1 from (0,0) to (2,0) is a counter-clockwise semicircle:
# centre (1,0), radius 1.  Counter-clockwise means it leaves (0,0)
# heading DOWN and comes back up to (2,0), so it bulges to the right of
# the chord and the point half way round it is (1,-1).
c, r, m = vm.loads('(ad:bulgearc (list 0.0 0.0 0.0) (list 2.0 0.0 0.0) 1.0)')
assert round(r, 6) == 1.0, r
assert [round(v, 6) for v in c[:2]] == [1.0, 0.0], c
assert [round(v, 6) for v in m[:2]] == [1.0, -1.0], m
print('   a semicircle: centre, radius and the point half way round it')

# a quarter of the same turn puts the centre a full radius off the chord
c, r, m = vm.loads('(ad:bulgearc (list 0.0 0.0 0.0) (list 2.0 0.0 0.0) %.10f)'
                   % math.tan(math.pi / 8))
assert round(r, 6) == round(math.sqrt(2), 6), r
assert [round(v, 6) for v in c[:2]] == [1.0, 1.0], c
assert round(math.dist(c[:2], m[:2]), 6) == round(math.sqrt(2), 6), (c, m)
print('   a counter-clockwise quarter: centre to the left of the chord')

# and the other way round it lands on the other side
c, r, m = vm.loads('(ad:bulgearc (list 0.0 0.0 0.0) (list 2.0 0.0 0.0) %.10f)'
                   % -math.tan(math.pi / 8))
assert round(r, 6) == round(math.sqrt(2), 6), r
assert [round(v, 6) for v in c[:2]] == [1.0, -1.0], c
print('   a clockwise quarter: the centre lands on the other side')

assert vm.loads('(ad:bulgearc (list 0.0 0.0 0.0) (list 2.0 0.0 0.0) 0.0)') is None
print('   a straight segment: no arc')

# and a bulged polyline hands its arcs to the perimeter step
vm = fresh()
vm.loads('(entmake (list (cons 0 "LWPOLYLINE") (cons 90 3) (cons 70 0) '
         '(cons 10 (list 0.0 0.0)) (cons 42 1.0) '
         '(cons 10 (list 2.0 0.0)) (cons 42 0.0) '
         '(cons 10 (list 6.0 0.0)) (cons 42 0.0)))')
vm.script = [list(vm.entities)]
vm.loads('(setq SS (ssget))')
found = vm.loads('(ad:arcs SS)')
assert len(found) == 1, found
assert round(found[0][0], 6) == 1.0, found        # radius first, to group by
print('   one bulged segment of a polyline: one arc, radius first')


print('== AUTODIMSIDEPOV keeps stepping its dims out with the stairs ==')
vm = fresh()
vm.sysvars['DIMTXT'] = 0.125
vm.sysvars['DIMSCALE'] = 48
ents = draw(vm, FLIGHT)
vm.run('c:AUTODIMSIDEPOV', [ents, None])
placed = dims(vm)
assert len(placed) == 4, placed
assert all(d[0] == 'STANDARD INCHES' for d in placed), placed
# the flight descends to the right, so its high side is the left: each
# dim sits 2ft left of its own step and they walk down with the stairs
assert [d[3][0] for d in placed] == [-24.0, -24.0, -12.0, -48.0], placed
assert vm.layer_of(vm.entities[-1]) == 'DIMENSION'
print('   dims on the high side, one per step, overall furthest out')


print('ALL AUTODIM CHECKS PASSED')
