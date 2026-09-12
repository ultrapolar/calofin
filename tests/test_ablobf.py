#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for ABLOBF, the OPEN polyline of best fit.

ABLOBF is ABHD's fitter walked in a straight line instead of round a
loop, so the arc math is already covered by test_abhd_runtime.py and
test_laser_fit.py.  What is new here, and what these tests are about,
is the open run itself:

  * the two ENDS -- picked, typed by survey number, or left to the
    farthest-apart pair -- and the fact that picking them CHANGES the
    run, which is the whole reason the command exists;
  * the result being an OPEN polyline: 70-bit clear, and one more
    vertex than it has segments, because there is no closing curve back
    to vertex 0 to supply the last one;
  * the wizard around it -- six steps, the pickfirst probe, the undo
    bracket, the declare loop and its self-clearing markers.

Every assertion is POSITIVE - something is in the output, some list has
a length.  vl-catch-all-apply swallows an "undefined function", so a
test shaped as "no error was raised" can pass against a routine that
silently did nothing.

Usage:  python3 tests/test_ablobf.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_ablobf.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, LispError, Dot  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
LSP = os.path.join(ROOT, 'lisp', 'ablobf', 'ABLOBF.lsp')

#: steps 1-4 on their Enter defaults, then Done at the declare loop.
#: What follows is the selection, the two ends, and the fit pick.
WIZARD = [1.0, None, None, 'Done']

FAILS = []


def check(label, cond, detail=''):
    print(('  ok   ' if cond else '  FAIL ') + label
          + (('  -- ' + str(detail)) if not cond and detail else ''))
    if not cond:
        FAILS.append(label)


def newvm():
    vm = VM()
    vm.load(LSP)
    vm.sysvars['CMDECHO'] = 1
    vm.sysvars['OSMODE'] = 4133
    return vm


def points(vm, pts, layer='POINTS'):
    vm.loads('''(entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord") (cons 2 "%s")
                    '(70 . 0) '(62 . 7) '(6 . "Continuous")))''' % layer)
    made = []
    for x, y in pts:
        before = len(vm.entities)
        vm.loads('(entmake (list \'(0 . "POINT") (cons 8 "%s")'
                 ' (list 10 %r %r 0.0)))' % (layer, x, y))
        made += vm.entities[before:]
    return made


def ab_pts(vm, pts):
    """ab_pt blocks carrying survey numbers, the way ABHD reads them."""
    made = []
    for n, (x, y) in enumerate(pts, 1):
        before = len(vm.entities)
        vm.loads('''
          (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                         '(8 . "POINTS") '(100 . "AcDbBlockReference")
                         '(2 . "ab_pt") (list 10 %r %r 0.0) '(66 . 1)))
          (entmake (list '(0 . "ATTRIB") '(8 . "POINTS")
                         '(2 . "number") (cons 1 "%d")))
          (entmake (list '(0 . "SEQEND") '(8 . "POINTS")))''' % (x, y, n))
        made += vm.entities[before:]
    return made


def grp(d, code):
    for p in d:
        if isinstance(p, Dot) and p.a == code:
            return p.b
        if isinstance(p, list) and p and p[0] == code:
            return p[1] if len(p) == 2 else p[1:]
    return None


def live(vm, kind=None, layer=None):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = vm.entdata.get(e, [])
        if kind and grp(d, 0) != kind:
            continue
        if layer and vm.layer_of(e) != layer:
            continue
        out.append((e, d))
    return out


def verts(d):
    """Every (10 . pt) vertex of an LWPOLYLINE, in order."""
    out = []
    for p in d:
        if isinstance(p, Dot) and p.a == 10:
            out.append(p.b)
        elif isinstance(p, list) and p and p[0] == 10:
            out.append(p[1:] if len(p) > 2 else p[1])
    return out


def said(vm):
    return ''.join(vm.printed)


def run(vm, script):
    try:
        vm.run('c:ABLOBF', script)
    except LispError as e:
        raise AssertionError(f'ABLOBF failed: {e}') from None
    return said(vm)


#: a gentle bow, nine points every 25 units along x
BOW = [(float(x), x * (200.0 - x) / 1000.0) for x in range(0, 201, 25)]

#: An L: eight points down one wall and up another at right angles to
#: it.  The farthest-apart pair are the two free ends, so the automatic
#: choice is right here -- it is the HOOK below that breaks it.
ELL = ([(0.0, y) for y in (0.0, 30.0, 60.0, 90.0)]
       + [(x, 90.0) for x in (30.0, 60.0, 90.0, 120.0)])

#: A run that doubles back: a long straight leg, then a short hook
#: returning beside it.  The two ENDS of the run are the start of the
#: leg and the tip of the hook -- but the hook tip is NOT the point
#: farthest from the start, so the automatic pair gets it wrong and
#: only picking by hand puts it right.  This is the shape the command
#: exists for.
HOOK = ([(float(x), 0.0) for x in range(0, 181, 30)]
        + [(150.0, 25.0), (120.0, 25.0), (90.0, 25.0)])


# ----------------------------------------------------------------------
print('ablobf -- the wizard runs end to end')
# ----------------------------------------------------------------------
vm = newvm()
pts = points(vm, BOW)
vm.pickfirst = ['<ss>'] + pts
txt = run(vm, WIZARD + [None, None, '1'])

check('it walks all six steps',
      'Step 1 of 6' in txt and 'Step 6 of 6' in txt, txt[:200])
check('the sixth step is the two ends',
      'where does the run START, and where does it END' in txt, txt[-2000:])
check('the run it settled on is named end to end',
      re.search(r'Run: Pt\.\d+ to Pt\.\d+, through \d+ point\(s\)', txt)
      is not None, txt)
check('the default pair reads in survey order',
      'Run: Pt.1 to Pt.9' in txt, txt)
check('three candidates are drawn to choose from',
      'Three candidate fits' in txt, txt)
check('and the kept one is reported', 'written to layer POOL' in txt, txt[-600:])

undo = [c for c in vm.commands if c and c[0] == '_.UNDO']
check('one undo group brackets the run',
      undo == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']], undo)
check('CMDECHO and OSMODE come back',
      vm.sysvars['CMDECHO'] == 1 and vm.sysvars['OSMODE'] == 4133)

kept = live(vm, 'LWPOLYLINE', 'POOL')
check('exactly one polyline is kept, on the POOL layer', len(kept) == 1,
      len(kept))
check('nothing is left on the candidate layer',
      live(vm, layer='ABLOBF-FIT') == [],
      [grp(d, 0) for _, d in live(vm, layer='ABLOBF-FIT')])

# ----------------------------------------------------------------------
print('ablobf -- the result is an OPEN polyline')
# ----------------------------------------------------------------------
d = kept[0][1]
check('the closed bit of DXF 70 is clear', grp(d, 70) == 0, grp(d, 70))
vs = verts(d)
check('it carries one more vertex than DXF 90 counts segments',
      len(vs) == grp(d, 90), f'{len(vs)} vertices, 90={grp(d, 90)}')
check('it starts on the first point of the run',
      abs(vs[0][0] - BOW[0][0]) < 1e-6 and abs(vs[0][1] - BOW[0][1]) < 1e-6,
      vs[0])
check('and ENDS on the last one, rather than curving back to the start',
      abs(vs[-1][0] - BOW[-1][0]) < 1e-6
      and abs(vs[-1][1] - BOW[-1][1]) < 1e-6, vs[-1])
check('so the two ends are different points',
      abs(vs[0][0] - vs[-1][0]) > 1.0, (vs[0], vs[-1]))

# ----------------------------------------------------------------------
print('ablobf -- the ends are the control, and picking them changes the run')
# ----------------------------------------------------------------------
# left to itself, the HOOK's ends are the two points farthest apart --
# which is NOT where the run really stops
vm = newvm()
pts = ab_pts(vm, HOOK)
vm.pickfirst = ['<ss>'] + pts
auto = run(vm, WIZARD + [None, None, '1'])
m = re.search(r'Run: Pt\.(\d+) to Pt\.(\d+)', auto)
check('the automatic pair is the farthest-apart two', m is not None, auto)
auto_ends = (int(m.group(1)), int(m.group(2))) if m else None
check('...and on a run that doubles back it is NOT the real end',
      auto_ends != (1, 10), auto_ends)

# named by hand, by the survey numbers the points carry: Pt.1 is the
# start of the leg, Pt.10 the tip of the hook
vm = newvm()
pts = ab_pts(vm, HOOK)
vm.pickfirst = ['<ss>'] + pts
hand = run(vm, WIZARD + ['Number', 1, 'Number', 10, '1'])
check('a typed survey number names an end',
      'Run: Pt.1 to Pt.10' in hand, hand[hand.find('Run:'):][:80])
check('and the run really is fitted between them',
      'written to layer POOL' in hand, hand[-400:])

kept2 = live(vm, 'LWPOLYLINE', 'POOL')
vs2 = verts(kept2[0][1])
check('the kept run starts at Pt.1',
      abs(vs2[0][0] - HOOK[0][0]) < 1e-6
      and abs(vs2[0][1] - HOOK[0][1]) < 1e-6, vs2[0])
check('and stops at Pt.10, the hook tip',
      abs(vs2[-1][0] - HOOK[9][0]) < 1e-6
      and abs(vs2[-1][1] - HOOK[9][1]) < 1e-6, vs2[-1])

# a clicked point snaps to the nearest survey point
vm = newvm()
pts = ab_pts(vm, HOOK)
vm.pickfirst = ['<ss>'] + pts
clicked = run(vm, WIZARD + [(2.0, 1.0, 0.0), (88.0, 26.0, 0.0), '1'])
check('a click near a point takes that point',
      'Run: Pt.1 to Pt.10' in clicked,
      clicked[clicked.find('Run:'):][:80])

# ----------------------------------------------------------------------
print('ablobf -- the ends are refused when they are the same point')
# ----------------------------------------------------------------------
vm = newvm()
pts = ab_pts(vm, HOOK)
vm.pickfirst = ['<ss>'] + pts
same = run(vm, WIZARD + ['Number', 4, 'Number', 4, 'Number', 10, '1'])
check('naming one point twice is refused, not fitted',
      'the run needs two different points' in same,
      same[same.find('STARTS'):][:300])
check('...and the re-ask is taken', 'Run: Pt.4 to Pt.10' in same, same)

# a number nothing carries is re-asked rather than guessed at
vm = newvm()
pts = ab_pts(vm, HOOK)
vm.pickfirst = ['<ss>'] + pts
nope = run(vm, WIZARD + ['Number', 99, 'Number', 1, None, '1'])
check('a number no point carries is named and re-asked',
      'No selected point carries the number 99' in nope, nope[:900])

# ----------------------------------------------------------------------
print('ablobf -- stepping back through the chain')
# ----------------------------------------------------------------------
vm = newvm()
pts = points(vm, BOW)
vm.pickfirst = ['<ss>'] + pts
back = run(vm, [1.0, None, None, 'Done',
                None, 'Back',          # second end -> back to the first
                None, None, '1'])
check('Back at the second end re-opens the first',
      back.count('Stepping back one question.') >= 1, back[-1500:])
check('and the run still completes', 'written to layer POOL' in back,
      back[-300:])

vm = newvm()
pts = points(vm, BOW)
vm.pickfirst = ['<ss>'] + pts
# the selection is asked again after that Back, so the script has to
# hand it over a second time - which is the point of the test
back2 = run(vm, [1.0, None, None, 'Done',
                 'Back',               # first end -> back to the selection
                 pts,                  # ...and it really does re-ask
                 None, None, '1'])
check('Back at the FIRST end hands the selection back',
      'Stepping back to the selection' in back2, back2[-1500:])
check('...the selection is genuinely asked for again',
      [p for p, _ in vm.prompts].count('ssget') == 1,
      [p for p, _ in vm.prompts])
check('and the run completes on the second pass',
      'written to layer POOL' in back2, back2[-300:])

# ----------------------------------------------------------------------
print('ablobf -- the declare loop, and its markers clearing themselves')
# ----------------------------------------------------------------------
vm = newvm()
pts = points(vm, ELL)
vm.pickfirst = ['<ss>'] + pts
held = run(vm, [1.0, None, None,
                'Hold', (0.0, 90.0, 0.0), 'Done',
                None, None, '1'])
check('a held point is counted back', 'held point' in held, held[:900])
onwall = live(vm, layer='POOL-WALLS')
check('its dashed marker cleared itself afterwards', onwall == [],
      [grp(d, 0) for _, d in onwall])

vm = newvm()
pts = points(vm, ELL)
vm.pickfirst = ['<ss>'] + pts
cnr = run(vm, [1.0, None, None,
               'Corner', (0.0, 90.0, 0.0), 'Done',
               None, None, '1'])
check('a declared corner is counted back', 'corner(s)' in cnr, cnr[:900])

# ----------------------------------------------------------------------
print('ablobf -- the pickfirst probe, and the empty cases')
# ----------------------------------------------------------------------
vm = newvm()
vm.run('c:ABLOBF', [None] + WIZARD + [None])
order = [p for p, _ in vm.prompts]
check('the pickfirst probe is asked before anything else',
      order and order[0] == 'ssget _I', order[:2])
check('an empty selection is refused by name',
      'No points selected' in said(vm), said(vm)[-200:])

vm = newvm()
pts = points(vm, [(0.0, 0.0)])
vm.pickfirst = ['<ss>'] + pts
one = run(vm, WIZARD)
check('one point is not a run, and it says so',
      'At least 2 distinct points' in one, one[-200:])

vm = newvm()
pts = points(vm, [(5.0, 5.0), (5.0, 5.0), (5.0, 5.0)])
vm.pickfirst = ['<ss>'] + pts
dup = run(vm, WIZARD)
check('three shots on one spot dedupe to one point, and are refused',
      'At least 2 distinct points' in dup, dup[-200:])

# ----------------------------------------------------------------------
print('ablobf -- None keeps nothing, All keeps the three')
# ----------------------------------------------------------------------
vm = newvm()
pts = points(vm, BOW)
vm.pickfirst = ['<ss>'] + pts
run(vm, WIZARD + [None, None, 'None'])
check('None leaves the drawing as it was',
      live(vm, 'LWPOLYLINE') == [],
      [vm.layer_of(e) for e, _ in live(vm, 'LWPOLYLINE')])

vm = newvm()
pts = points(vm, BOW)
vm.pickfirst = ['<ss>'] + pts
run(vm, WIZARD + [None, None, 'All'])
check('All keeps all three candidates',
      len(live(vm, 'LWPOLYLINE')) == 3, len(live(vm, 'LWPOLYLINE')))

# ----------------------------------------------------------------------
print("ablobf -- the file's own rules")
# ----------------------------------------------------------------------
src = open(LSP, encoding='utf-8').read()
check('ASCII only', all(ord(c) < 128 for c in src),
      [c for c in src if ord(c) >= 128][:5])
check('the version banner is the shape release_lisp.py reads',
      re.search(r'\(setq \*ablobf-version\*\s+"v\d+\.\d+"\)', src)
      is not None)
check('no tabs', '\t' not in src)
check('the closed-loop half of the fork is gone',
      not re.search(r'\(defun abl:(span-loop|order-points|coarse-loop)'
                    r'(?![-\w])', src),
      [l for l in src.splitlines() if l.startswith('(defun abl:order')])
check('so is the elevation half',
      not re.search(r'\(defun abl:(ask-zmode|pick-elev|zs-of)(?![-\w])',
                    src))
# LHD is named in one comment on purpose -- it is where this fitter came
# from and the sibling that still does the closed case.  What must NOT
# survive is anything LHD's own runs would answer to: its xdata stamp
# and its candidate layer, which would make the two tools clear each
# other's work.
check("nothing answers to LHD's stamp or its layer any more",
      '"LHD"' not in src and 'LHD-FIT' not in src,
      [l for l in src.splitlines() if 'LHD' in l])

# ----------------------------------------------------------------------
print('ablobf -- the fitted run really does pass through the points')
# ----------------------------------------------------------------------
# Everything above reads what the command SAYS.  This measures what it
# DREW, with arc geometry written here rather than borrowed from the
# file under test - a report generated by the same code that generated
# the geometry cannot catch the two being wrong together.


def circumcentre(a, b, c):
    (x1, y1), (x2, y2), (x3, y3) = a, b, c
    d = 2.0 * (x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2))
    if abs(d) < 1e-12:
        return None
    s1, s2, s3 = x1 * x1 + y1 * y1, x2 * x2 + y2 * y2, x3 * x3 + y3 * y3
    return ((s1 * (y2 - y3) + s2 * (y3 - y1) + s3 * (y1 - y2)) / d,
            (s1 * (x3 - x2) + s2 * (x1 - x3) + s3 * (x2 - x1)) / d)


def seg_dist(p, p1, p2, bulge):
    """Distance from P to one (start end bulge) segment.  The bulge
    convention is AutoCAD's, as the file's own header states it: the
    apex of a positive (counterclockwise) bulge lies to the RIGHT of
    the p1 -> p2 chord."""
    if abs(bulge) < 1e-9:
        vx, vy = p2[0] - p1[0], p2[1] - p1[1]
        l2 = vx * vx + vy * vy
        t = 0.0 if l2 == 0 else max(0.0, min(
            1.0, ((p[0] - p1[0]) * vx + (p[1] - p1[1]) * vy) / l2))
        return math.hypot(p[0] - (p1[0] + t * vx), p[1] - (p1[1] + t * vy))
    ch = math.dist(p1, p2)
    dx, dy = (p2[0] - p1[0]) / ch, (p2[1] - p1[1]) / ch
    px, py = -dy, dx
    mid = ((p1[0] + p2[0]) / 2.0, (p1[1] + p2[1]) / 2.0)
    apex = (mid[0] + px * (-0.5 * ch * bulge),
            mid[1] + py * (-0.5 * ch * bulge))
    c = circumcentre(p1, apex, p2)
    if c is None:
        return min(math.dist(p, p1), math.dist(p, p2))
    r = math.dist(c, p1)
    a1 = math.atan2(p1[1] - c[1], p1[0] - c[0])
    a2 = math.atan2(p2[1] - c[1], p2[0] - c[0])
    ap = math.atan2(p[1] - c[1], p[0] - c[0])
    turn = (lambda x: x % (2 * math.pi))
    sweep, rel = ((turn(a2 - a1), turn(ap - a1)) if bulge > 0
                  else (turn(a1 - a2), turn(ap - a2)))
    if rel <= sweep:
        return abs(math.dist(p, c) - r)
    return min(math.dist(p, p1), math.dist(p, p2))


def bulges(d):
    out = []
    for q in d:
        if isinstance(q, Dot) and q.a == 42:
            out.append(q.b)
        elif isinstance(q, list) and q and q[0] == 42:
            out.append(q[1])
    return out


def worst_off(pts, d):
    vs = [(v[0], v[1]) for v in verts(d)]
    bs = bulges(d)
    return max(min(seg_dist(p, vs[i], vs[i + 1], bs[i])
                   for i in range(len(vs) - 1))
               for p in pts)


# the sanity check on the measuring code itself, before it is trusted:
# a point on a known quarter arc is on it
check('the test\'s own arc math is sound',
      seg_dist((math.cos(math.pi / 4), math.sin(math.pi / 4)),
               (1.0, 0.0), (0.0, 1.0),
               math.tan(math.radians(90) / 4)) < 1e-12)

#: a quarter circle of R120 shot every 10 degrees, then a straight
#: tangent tail.  The right answer is exactly two segments - one arc,
#: one line - through every point with no error at all, so a fit that
#: is merely CLOSE is visibly not it.
ARCTAIL = [(120 * math.cos(math.radians(a)), 120 * math.sin(math.radians(a)))
           for a in range(0, 91, 10)] + [(-40.0, 120.0), (-80.0, 120.0),
                                         (-120.0, 120.0)]

vm = newvm()
pts = points(vm, ARCTAIL)
vm.pickfirst = ['<ss>'] + pts
run(vm, [0.25, None, None, 'Done', None, None, '2'])
d = live(vm, 'LWPOLYLINE', 'POOL')[0][1]
check('an arc and its tangent tail fit in exactly two segments',
      len(verts(d)) - 1 == 2, len(verts(d)) - 1)
check('one of them is a curve',
      sum(1 for b in bulges(d)[:-1] if abs(b) > 1e-9) == 1, bulges(d))
check('and MEASURED here, not reported there, every point is on it',
      worst_off(ARCTAIL, d) < 1e-6, worst_off(ARCTAIL, d))

# the bow, against the distance the operator actually asked for
vm = newvm()
pts = points(vm, BOW)
vm.pickfirst = ['<ss>'] + pts
run(vm, [1.0, None, None, 'Done', None, None, '2'])
d = live(vm, 'LWPOLYLINE', 'POOL')[0][1]
w = worst_off(BOW, d)
check('a bowed run is held inside the 1" that was asked for', w <= 1.0, w)

# ----------------------------------------------------------------------
print('ablobf -- Redo re-opens the omits, the ends and the settings')
# ----------------------------------------------------------------------
vm = newvm()
pts = ab_pts(vm, HOOK)
vm.pickfirst = ['<ss>'] + pts
redo = run(vm, WIZARD + [
    'Number', 1, 'Number', 10,      # the ends
    'Redo',                         # ...and think again
    None,                           # omit nothing
    None, None, None,               # walls / corners / holds: Enter each
    'Number', 4, 'Number', 10,      # a different START
    None, None, None,               # tolerance / percent / cap: Enter
    '1'])
check('Redo re-opens the omit list', 'Any points to leave out' in redo,
      redo[redo.find('Redoing'):][:200])
check('and the ends can change on the way round',
      'Run: Pt.4 to Pt.10' in redo, redo[redo.rfind('Run:'):][:80])
check('the refit is the one that is kept',
      redo.count('written to layer POOL') == 1, redo[-400:])
vs3 = verts(live(vm, 'LWPOLYLINE', 'POOL')[0][1])
check('the kept run starts at the NEW start point',
      abs(vs3[0][0] - HOOK[3][0]) < 1e-6
      and abs(vs3[0][1] - HOOK[3][1]) < 1e-6, vs3[0])

# omitting an end point: the offer has to be replaced BEFORE the ends
# are re-asked, or Enter takes a point that is no longer in the fit
vm = newvm()
pts = ab_pts(vm, HOOK)
vm.pickfirst = ['<ss>'] + pts
gone = run(vm, WIZARD + [
    'Number', 1, 'Number', 10,
    'Redo',
    (90.0, 25.0, 0.0), None,        # omit Pt.10 - the run's own END
    None, None, None,
    None, None,                     # Enter at BOTH ends: take the offer
    None, None, None,
    '1'])
check('omitting an end is called out', 'an end point was omitted' in gone,
      gone[gone.find('Redoing'):][:700])
m = re.search(r'Run: Pt\.(\d+) to Pt\.(\d+)', gone[gone.rfind('Redoing'):])
check('and the offer Enter takes is NOT the omitted point',
      m is not None and '10' not in (m.group(1), m.group(2)),
      m.group(0) if m else gone[-500:])
vs4 = verts(live(vm, 'LWPOLYLINE', 'POOL')[0][1])
check('so the kept run never reaches the omitted point',
      all(abs(v[0] - HOOK[9][0]) > 1e-6 or abs(v[1] - HOOK[9][1]) > 1e-6
          for v in vs4), (HOOK[9], vs4))

# ----------------------------------------------------------------------
print('ablobf -- the README quotes the values the code actually holds')
# ----------------------------------------------------------------------
# A knob table is only worth having if its middle column is the value in
# the file: a default documented as 0.15 and set to 0.50 is worse than
# no table, because it is read and believed.
readme = open(os.path.join(ROOT, 'lisp', 'ablobf', 'README.md'),
              encoding='utf-8').read()
block = src[src.index(';; ---- configuration'):
            src.index(';; ---- small 2D vector helpers')]
knobs = re.findall(r'^\(setq (\*ABL-[A-Z0-9-]+\*)\s+(.+?)\)\s*(?:;.*)?$',
                   block, re.M)
knobs += re.findall(r'^\(if \(null (\*ABL-[A-Z0-9-]+\*)\)\s+'
                    r'\(setq \*ABL-[A-Z0-9-]+\*\s+(.+?)\)\)', block, re.M)
check('every knob in the block is a row in the README',
      len(knobs) > 25 and not [k for k, _ in knobs
                               if ('`%s`' % k) not in readme],
      [k for k, _ in knobs if ('`%s`' % k) not in readme])
wrong = []
for name, val in knobs:
    row = re.search(r'^\| `' + re.escape(name) + r'` \| `([^`]*)` \|',
                    readme, re.M)
    if row and row.group(1) != val.strip():
        wrong.append(f'{name}: code {val.strip()!r}, README {row.group(1)!r}')
check("and quotes the value the file actually holds", not wrong, wrong)

# ----------------------------------------------------------------------
print()
if FAILS:
    print(f'{len(FAILS)} ABLOBF check(s) FAILED: ' + ', '.join(FAILS))
    sys.exit(1)
print('all ABLOBF checks passed')
