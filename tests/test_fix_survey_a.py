#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The survey fitters' shared helpers, held to what the drawing really
does -- the parts the VM's flat, unlocked world would otherwise hide.

ABHD, FITABHD, LHD, CABHD, ABLOBF, ABPCHECK, LOBF and ABCURCHECK each
carry their own copy of a handful of helpers, and each copy had the
same blind spot.  The VM used to keep every layer unlocked, every UCS
World and every entity in the world plane; it models all three the way
AutoCAD behaves now (tests/test_lispvm_values.py, test_lispvm_ucs.py),
and they were modelled here, in the test, first:

  * a LOCKED LAYER: entdel answers nil and erases nothing.  The purges
    that clear a tool's own markers counted the attempt, said "cleared"
    over markers still on screen, and the next run wrote beside them;
  * an entity whose PLANE faces down, extrusion (0 0 -1): its ARC,
    CIRCLE and polyline numbers are in that plane (X the other way
    round), and trans with its ename is how AutoCAD turns them into
    world numbers.  Read raw, the outline was mirrored through the Y
    axis with no warning, because the plane IS the world's.  A survey
    point BLOCK's insertion (and an LHD elevation label's) is kept in
    that plane too, so the points were mirrored the same way, and a
    block's Z, LHD's laser elevation, came back with its sign flipped;
  * a MOVED UCS: getpoint answers in it, and trans 1 -> 0 is how a
    click reaches the world numbers the survey is kept in.  Compared
    raw, the deep end of FITABHD's pool, ABCURCHECK's declared breaks
    and the wall a Remove took were all the wrong one, and
    TUTORIALABHD's demo was drawn away from the spot picked for it.

Plus two readings that needed no model: a heavy POLYLINE's curve-fit
extra vertices (flag 1) are ON the curve and were being dropped, and
ABHD's session state for its length ruler outlived the run.

Every check is POSITIVE -- a count, a coordinate, a message present.

Usage:  python3 tests/test_fix_survey_a.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_fix_survey_a.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Dot, Sym, BUILTINS, NIL, LispError  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LISP = os.path.join(REPO, 'lisp')

FILES = {
    'pf':   os.path.join(LISP, 'abhd', 'abhd.lsp'),
    'fit':  os.path.join(LISP, 'fitabhd', 'FITABHD.lsp'),
    'lh':   os.path.join(LISP, 'lhd', 'lhd.lsp'),
    'cab':  os.path.join(LISP, 'cabhd', 'CABHD.lsp'),
    'abl':  os.path.join(LISP, 'ablobf', 'ABLOBF.lsp'),
    'abp':  os.path.join(LISP, 'abpcheck', 'ABPCHECK.lsp'),
    'lobf': os.path.join(LISP, 'lobf', 'LOBF.lsp'),
    'acc':  os.path.join(LISP, 'abcurcheck', 'ABCURCHECK.lsp'),
}

FAILS = []


def check(label, cond, detail=''):
    print(('  ok   ' if cond else '  FAIL ') + label
          + (('  -- ' + str(detail)) if (detail and not cond) else ''))
    if not cond:
        FAILS.append(label)



def loaded(prefix):
    """A fresh VM with one tool loaded."""
    vm = VM()
    vm.load(FILES[prefix])
    return vm


def grp(d, code):
    for g in d or []:
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else g[1:]
    return None


def said(vm):
    return ''.join(vm.printed)


def live(vm, e):
    return e not in vm.deleted


def layer(vm, name, flags=0):
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") (cons 2 "%s") (cons 70 %d)'
             ' \'(62 . 7) \'(6 . "Continuous")))' % (name, flags))


def layer_flags(vm, name):
    rec = vm.tablerecs.get('LAYER', {}).get(name.upper())
    return int(grp(vm.recdata.get(rec, []), 70) or 0) if rec else 0


def text(vm, lay, s='x'):
    vm.loads('(entmake (list \'(0 . "TEXT") (cons 8 "%s")'
             ' \'(10 0.0 0.0 0.0) \'(40 . 1.0) (cons 1 "%s")))' % (lay, s))
    return vm.entities[-1]


# ---------------------------------------------------------------- models

# AutoCAD's entdel on a LOCKED layer -- nil, and nothing erased -- is
# tests/lispvm.py's own now (test_lispvm_values.py); an entdel_locked
# model used to be patched in here for it.
# The UCS and an entity's own plane are tests/lispvm.py's now too
# (test_lispvm_ucs.py): vm.set_ucs moves the UCS, and trans takes a
# point through an ename's 210 by the arbitrary axis algorithm.  A
# trans_model used to be patched in here for both.


def entdel_refused(vm, a):
    """An entdel that refuses whatever it is handed."""
    return NIL


class patched:
    """BUILTINS[name] replaced for the length of a with-block."""

    def __init__(self, **fns):
        self.fns = fns
        self.saved = {}

    def __enter__(self):
        for k, fn in self.fns.items():
            self.saved[k] = BUILTINS[Sym(k)]
            BUILTINS[Sym(k)] = fn
        return self

    def __exit__(self, *exc):
        for k, fn in self.saved.items():
            BUILTINS[Sym(k)] = fn
        return False


# ======================================================================
# 1. the purges count what they ERASED, and a lock does not stop them
# ======================================================================
print("\nthe marker purges, over a locked layer")

#: (prefix, purge call, tag call) -- each tool's own stamp and sweep
PURGES = [
    ('pf',   '(pf:purge-mine "L")',       '(pf:tag-mine E)'),
    ('fit',  '(fit:purge-mine "L")',      '(fit:tag-mine E)'),
    ('lh',   '(lh:purge-mine "L")',       '(lh:tag-mine E)'),
    ('cab',  '(cab:purge-mine "L")',      '(cab:tag-mine E)'),
    ('abl',  '(abl:purge-mine "L")',      '(abl:tag-mine E)'),
    ('abp',  '(abp:purge-mine "L")',      '(abp:tag-mine E)'),
    ('lobf', '(lobf:purge-mine "L")',     '(lobf:tag-mine E)'),
    ('acc',  '(acc:purge "L" "MARK")',    '(acc:tag E "MARK")'),
]

for prefix, purge, tag in PURGES:
    vm = loaded(prefix)
    layer(vm, 'L', 0)
    mine = text(vm, 'L', 'POINTS OFF THE LINE (3)')
    vm.globals[Sym('e')] = mine
    vm.loads(tag)
    theirs = text(vm, 'L', "the drafter's own note")
    # the drafter locked it AFTER the tool tagged its marker: tagged on
    # a locked layer, the tag's own entmod would be refused
    vm.loads('(setq t:rec (entget (tblobjname "LAYER" "L")))'
             '(entmod (subst (cons 70 4) (assoc 70 t:rec) t:rec))')
    n = vm.loads(purge)
    check("%s: a locked layer's own marker is erased and counted" % prefix,
          n == 1 and not live(vm, mine), (n, live(vm, mine)))
    check("%s: ...the drafter's own object on it is left alone" % prefix,
          live(vm, theirs))
    check("%s: ...and the drafter's lock is put back" % prefix,
          layer_flags(vm, 'L') & 4 == 4, layer_flags(vm, 'L'))

    # an erase that is refused however the layer stands is NOT counted,
    # and is said
    vm = loaded(prefix)
    layer(vm, 'L', 0)
    mine = text(vm, 'L')
    vm.globals[Sym('e')] = mine
    vm.loads(tag)
    with patched(entdel=entdel_refused):
        n = vm.loads(purge)
    check("%s: a refused erase is not counted as cleared" % prefix,
          n == 0, n)
    check("%s: ...and is said, naming the layer" % prefix,
          'could not be erased - NOT removed' in said(vm)
          and 'layer L' in said(vm), said(vm)[-200:])

# ABPCHECKRESCUE: nothing erased and something stuck is not "nothing
# of ABPCHECK's left to remove"
vm = loaded('abp')
miss = vm.loads('abp:*miss-layer*')
layer(vm, miss, 0)
mine = text(vm, miss)
vm.globals[Sym('e')] = mine
vm.loads('(abp:tag-mine E)')
with patched(entdel=entdel_refused):
    vm.run('c:ABPCHECKRESCUE', [])
check("ABPCHECKRESCUE does not call stuck objects 'nothing left'",
      "nothing of ABPCHECK's left to remove" not in said(vm)
      and 'could not be erased' in said(vm), said(vm)[-300:])


# ======================================================================
# 2. an entity whose plane faces down is read in the world's numbers
# ======================================================================
print("\nARC, CIRCLE and polylines drawn with extrusion (0 0 -1)")

READERS = ['pf', 'lh', 'cab', 'abp', 'acc']
DOWN = '(list 210 0.0 0.0 -1.0)'


def segs(vm, prefix, en):
    vm.globals[Sym('e')] = en
    out = vm.loads('(%s:ent-segs E)' % prefix)
    return [((float(s[0][0]), float(s[0][1])),
             (float(s[1][0]), float(s[1][1])), float(s[2])) for s in out]


def arc_mid(s):
    """Where the arc of segment S = (start end bulge) passes half-way:
    a positive bulge turns counter-clockwise, so its middle lies to
    the RIGHT of the chord, a sagitta of bulge x half-chord out."""
    (x1, y1), (x2, y2), b = s
    dx, dy = x2 - x1, y2 - y1
    return ((x1 + x2) / 2.0 + b * dy / 2.0, (y1 + y2) / 2.0 - b * dx / 2.0)


def near(p, q, eps=1e-6):
    return math.hypot(p[0] - q[0], p[1] - q[1]) < eps


for prefix in READERS:
    vm = loaded(prefix)
    layer(vm, 'POOL', 0)
    # an ARC in the downward plane: centre (100, 20), r 30, 0 -> 90 deg
    # in ITS numbers.  In the world that is centre (-100, 20), running
    # from (-130, 20) to (-100, 50) clockwise, through (-121.2, 41.2)
    vm.loads('(entmake (list \'(0 . "ARC") \'(8 . "POOL")'
             ' (list 10 100.0 20.0 0.0) \'(40 . 30.0)'
             ' \'(50 . 0.0) (cons 51 (/ pi 2.0)) %s))' % DOWN)
    arc = vm.entities[-1]
    got = segs(vm, prefix, arc)
    a = math.pi / 4.0
    want_mid = (-(100.0 + 30.0 * math.cos(a)), 20.0 + 30.0 * math.sin(a))
    check("%s: a downward ARC starts and ends where it is drawn" % prefix,
          len(got) == 1 and near(got[0][0], (-130.0, 20.0))
          and near(got[0][1], (-100.0, 50.0)), got)
    check("%s: ...and bulges the way it is drawn" % prefix,
          len(got) == 1 and near(arc_mid(got[0]), want_mid, 1e-4),
          (got, want_mid))

    # a CIRCLE: centre (50, 20) in its plane is (-50, 20) in the world
    vm.loads('(entmake (list \'(0 . "CIRCLE") \'(8 . "POOL")'
             ' (list 10 50.0 20.0 0.0) \'(40 . 10.0) %s))' % DOWN)
    circ = vm.entities[-1]
    got = segs(vm, prefix, circ)
    pts = [s[0] for s in got] + [s[1] for s in got] + [arc_mid(s) for s in got]
    check("%s: a downward CIRCLE is round the world centre" % prefix,
          len(got) == 2
          and all(abs(math.hypot(p[0] + 50.0, p[1] - 20.0) - 10.0) < 1e-6
                  for p in pts), got)

    # a closed LWPOLYLINE with one bulge, in the downward plane
    vm.loads('(entmake (list \'(0 . "LWPOLYLINE") \'(8 . "POOL")'
             ' \'(100 . "AcDbPolyline") \'(90 . 4) \'(70 . 1)'
             ' \'(10 0.0 0.0) \'(42 . 0.5) \'(10 100.0 0.0) \'(42 . 0.0)'
             ' \'(10 100.0 50.0) \'(42 . 0.0) \'(10 0.0 50.0) \'(42 . 0.0)'
             ' %s))' % DOWN)
    lw = vm.entities[-1]
    got = segs(vm, prefix, lw)
    # the first span runs (0,0) -> (-100,0) in the world, and its bulge,
    # +0.5 in the downward plane, sags to +y there -- the same side it
    # is drawn on
    first = got[0] if got else None
    check("%s: a downward LWPOLYLINE's vertices are world numbers" % prefix,
          len(got) == 4 and near(first[0], (0.0, 0.0))
          and near(first[1], (-100.0, 0.0))
          and near(got[1][1], (-100.0, 50.0)), got)
    ocs_mid = arc_mid(((0.0, 0.0), (100.0, 0.0), 0.5))
    check("%s: ...and each bulge turns the way it is drawn" % prefix,
          first is not None and near(arc_mid(first),
                                     (-ocs_mid[0], ocs_mid[1])),
          (first, ocs_mid))

    # a heavy 2D POLYLINE in the downward plane
    vm.loads('(entmake (list \'(0 . "POLYLINE") \'(8 . "POOL") \'(66 . 1)'
             ' \'(10 0.0 0.0 0.0) \'(70 . 0) %s))' % DOWN)
    heavy = vm.entities[-1]
    for x, y, b in ((0.0, 0.0, 0.25), (60.0, 0.0, 0.0), (60.0, 30.0, 0.0)):
        vm.loads('(entmake (list \'(0 . "VERTEX") \'(8 . "POOL")'
                 ' (list 10 %r %r 0.0) (cons 42 %r) \'(70 . 0)))' % (x, y, b))
    vm.loads('(entmake (list \'(0 . "SEQEND") \'(8 . "POOL")))')
    got = segs(vm, prefix, heavy)
    check("%s: a downward heavy POLYLINE is read in world numbers" % prefix,
          len(got) == 2 and near(got[0][1], (-60.0, 0.0))
          and near(got[1][1], (-60.0, 30.0)) and abs(got[0][2] + 0.25) < 1e-9,
          got)

    # the everyday case is untouched: no 210, the numbers as stored
    vm.loads('(entmake (list \'(0 . "ARC") \'(8 . "POOL")'
             ' (list 10 100.0 20.0 0.0) \'(40 . 30.0)'
             ' \'(50 . 0.0) (cons 51 (/ pi 2.0))))')
    flat = vm.entities[-1]
    got = segs(vm, prefix, flat)
    check("%s: a flat ARC reads exactly as before" % prefix,
          len(got) == 1 and near(got[0][0], (130.0, 20.0))
          and near(got[0][1], (100.0, 50.0)) and got[0][2] > 0.0, got)


# ======================================================================
# 3. a curve-fit heavy POLYLINE keeps the vertices that are ON the curve
# ======================================================================
print("\nheavy POLYLINE vertex flags")

for prefix in READERS:
    vm = loaded(prefix)
    layer(vm, 'POOL', 0)
    # PEDIT Fit: original vertices, an EXTRA vertex (flag 1) joining the
    # arc pair between them, and -- as a spline-fit one would carry -- a
    # FRAME control point (flag 16) that is off the curve altogether
    vm.loads('(entmake (list \'(0 . "POLYLINE") \'(8 . "POOL") \'(66 . 1)'
             ' \'(10 0.0 0.0 0.0) \'(70 . 2)))')
    heavy = vm.entities[-1]
    for x, y, b, f in ((0.0, 0.0, 0.2, 0), (50.0, 10.0, 0.3, 1),
                       (100.0, 0.0, 0.0, 0), (500.0, 500.0, 0.0, 16)):
        vm.loads('(entmake (list \'(0 . "VERTEX") \'(8 . "POOL")'
                 ' (list 10 %r %r 0.0) (cons 42 %r) (cons 70 %d)))'
                 % (x, y, b, f))
    vm.loads('(entmake (list \'(0 . "SEQEND") \'(8 . "POOL")))')
    got = segs(vm, prefix, heavy)
    check("%s: the curve-fit vertex is kept, with its own bulge" % prefix,
          len(got) == 2 and near(got[0][1], (50.0, 10.0))
          and abs(got[0][2] - 0.2) < 1e-9 and abs(got[1][2] - 0.3) < 1e-9,
          got)
    check("%s: ...and the frame point is still skipped" % prefix,
          not any(near(s[0], (500.0, 500.0)) or near(s[1], (500.0, 500.0))
                  for s in got), got)


# ======================================================================
# 4. a click under a moved UCS is taken to world before it is compared
# ======================================================================
print("\nclicks under a moved UCS")

# FITABHD: the deep end.  An oasis envelope 384 x 216 with its left
# wall at world x 1000, the UCS origin moved onto that wall, and the
# RIGHT-hand end clicked: UCS (384, 108) is world (1384, 108).
vm = loaded('fit')
vm.loads("""(setq P (list (cons 'variant "RoundedBottom")
                          (cons 'x0 1000.0) (cons 'y0 0.0)
                          (cons 'w 384.0) (cons 'h 216.0)
                          (cons 'rl nil) (cons 'rt nil)
                          (cons 'rr 96.0) (cons 'off 0.0)
                          (cons 'utl (fit:u-of 200.0 216.0))
                          (cons 'utr 0.0) (cons 'ubr 0.0)
                          (cons 'ubc (fit:u-of 300.0 216.0)))
                  R (list (cons 'kind 'oasis) (cons 'type "OAsis")
                          (cons 'prm P) (cons 'angle 0.0)
                          (cons 'mirror nil)))""")
before = len(vm.entities)
vm.script = [(384.0, 108.0, 0.0), None, None, None, None]
vm.set_ucs((1000.0, 0.0, 0.0))
vm.loads('(fit:bottom R)')
xs = []
for e in vm.entities[before:]:
    d = vm.entdata.get(e, [])
    if live(vm, e) and grp(d, 0) == 'LINE' and grp(d, 8) == 'POOL':
        xs += [float(grp(d, 10)[0]), float(grp(d, 11)[0])]
# the breaks sit 8' and 20' in from the deep wall and the hopper runs
# up to it: x 1144..1366 from the right-hand end, 1018..1240 from the
# left
check("FITABHD: the bottom is drawn at the end that was clicked",
      bool(xs) and abs(min(xs) - 1144.0) < 1e-6
      and abs(max(xs) - 1366.0) < 1e-6
      and 'standard hopper drawn' in said(vm),
      (min(xs) if xs else None, max(xs) if xs else None))

# ABCURCHECK: a declared break, added by clicking it, and one dropped
# by clicking it -- the UCS origin moved up to (0, 50)
vm = loaded('acc')
vm.set_ucs((0.0, 50.0, 0.0))
vm.script = ['Add', (10.0, -2.0, 0.0), None, None]
got = vm.loads('(acc:declare-loop nil)')
check("ABCURCHECK: a declaration is kept in world numbers",
      got and near(got[0], (10.0, 48.0)), got)
# a declaration read back off the drawing is in world numbers, and
# a click on it under the moved UCS drops it
vm.script = ['Remove', (10.0, -2.0, 0.0), None, None]
got = vm.loads("(acc:declare-loop (list '(10.0 48.0)))")
check("ABCURCHECK: ...and a click on a declaration drops it",
      not got and 'Nothing declared to drop' not in said(vm), got)

# the wall a Remove takes: two walls in world numbers, y 0 and y 50,
# the UCS origin moved up to (0, 50), and a click just under the UPPER
# wall -- UCS (50, -2), world (50, 48).  Raw, (50, -2) is by the lower.
WALLS = [('pf', 'pf-walls', 'pf:edit-walls'),
         ('cab', 'cab-walls', 'cab:edit-walls'),
         ('abl', 'abl-walls', 'abl:edit-walls'),
         ('lh', 'lh-walls', 'lh:edit-walls')]
for prefix, var, fn in WALLS:
    vm = loaded(prefix)
    vm.loads('(setq %s (list (list \'(0.0 0.0) \'(100.0 0.0))'
             ' (list \'(0.0 50.0) \'(100.0 50.0))))' % var)
    vm.script = ['Remove', (50.0, -2.0, 0.0), None]
    vm.set_ucs((0.0, 50.0, 0.0))
    vm.loads("(%s (list '(0.0 0.0) '(100.0 0.0) '(0.0 50.0)"
             " '(100.0 50.0)))" % fn)
    left = vm.loads(var)
    check("%s: Remove takes the wall that was clicked" % fn,
          left and len(left) == 1 and near(left[0][0], (0.0, 0.0)), left)


# ======================================================================
# 5. ABHD's length ruler starts each run afresh
# ======================================================================
print("\nABHD's ruler state")

vm = loaded('pf')
vm.script = ["3'6"]
vm.loads('(pf:get-off "\\n  Offset?" (cons 24.0 nil) nil T'
         ' *PF-HOP-OFF-LADDER*)')
vm.loads('(pf:temp-clear)')               # the run ends, as every exit does
check("the run's end forgets the ruler, not only takes it down",
      vm.loads('pf:*ruler*') in (None, NIL, []), vm.loads('pf:*ruler*'))
vm.loads('(setq *PF-RULER-COLOR* 1)')     # a LAZTUNE retune between runs
vm.printed = []
before = len(vm.entities)
vm.script = [None]
vm.loads('(pf:get-off "\\n  Offset?" (cons 24.0 nil) nil T'
         ' *PF-HOP-OFF-LADDER*)')
cols = {grp(vm.entdata.get(e, []), 62) for e in vm.entities[before:]
        if vm.layer_of(e) == 'ABHD-RULER'}
check("the next run's ruler wears the retuned colour", 1 in cols
      and 3 not in cols, cols)
check("...and says its one-line hint again", 'A ruler of' in said(vm),
      said(vm)[:200])


# ======================================================================
# 6. a survey point inserted from below is read in the world's numbers
# ======================================================================
print("\nsurvey-point blocks (and LHD's labels) with extrusion (0 0 -1)")

# An INSERT's (and a TEXT's) 10 is in its own plane, as an ARC's centre
# is; a POINT's is in world numbers already.  Each block below sits at
# OCS (x, y, z) and so, in the world, at (-x, y, -z).
WORLD = {(-100.0, 20.0), (-50.0, 10.0), (30.0, 40.0)}


def insert(vm, name, lay, x, y, z=0.0, down=True):
    vm.loads('(entmake (list \'(0 . "INSERT") (cons 2 "%s") (cons 8 "%s")'
             ' (list 10 %r %r %r) %s))'
             % (name, lay, x, y, z, DOWN if down else ''))
    return vm.entities[-1]


def survey(vm):
    """An ab_pt and a plain block on POINTS inserted from below, and one
    ab_pt inserted the ordinary way.  Returns the three enames."""
    layer(vm, 'POINTS', 0)
    layer(vm, 'POOL', 0)
    return [insert(vm, 'ab_pt', 'POINTS', 100.0, 20.0),
            insert(vm, 'MARK', 'POINTS', 50.0, 10.0),
            insert(vm, 'ab_pt', 'POINTS', 30.0, 40.0, down=False)]


def xy(pts):
    return {(round(float(p[0]), 6), round(float(p[1]), 6)) for p in pts}


def record(vm, fn):
    """Wrap FN (a point-remembering helper) so every call's arguments
    are kept in t:seen, then hand them on to the real one."""
    orig = vm.globals[Sym(fn)]
    vm.globals[Sym('t:orig')] = orig
    vm.globals[Sym('t:seen')] = NIL
    args = ' '.join(str(p) for p in orig[1])
    vm.loads('(defun %s (%s) (setq t:seen (cons (list %s) t:seen))'
             ' (t:orig %s))' % (fn, args, args, args))


def seen(vm):
    return [list(r) for r in (vm.globals.get(Sym('t:seen')) or [])]


def drive(vm, cmd, script):
    """Run CMD as far as SCRIPT reaches; running out of answers after
    the read is the expected way to stop."""
    try:
        vm.run(cmd, script)
    except LispError:
        pass


# the helper itself, in all seven copies: a block from below, a flat
# block, a POINT (whose 10 is world already, whatever its 210 says) and
# a TEXT from below
for prefix in ('pf', 'cab', 'lh', 'abp', 'abl', 'lobf', 'fit'):
    vm = loaded(prefix)
    flat = survey(vm)[2]
    down = insert(vm, 'ab_pt', 'POINTS', 100.0, 20.0, -5.0)
    vm.loads('(entmake (list \'(0 . "POINT") \'(8 . "POINTS")'
             ' (list 10 7.0 8.0 9.0) %s))' % DOWN)
    pt = vm.entities[-1]
    vm.loads('(entmake (list \'(0 . "TEXT") \'(8 . "0") \'(40 . 1.0)'
             ' \'(1 . "12.5") (list 10 60.0 30.5 0.0) %s))' % DOWN)
    tx = vm.entities[-1]
    got = {}
    for k, e in (('down', down), ('flat', flat), ('pt', pt), ('tx', tx)):
        vm.globals[Sym('e')] = e
        got[k] = [float(c) for c in vm.loads('(%s:ins-w (entget E))'
                                              % prefix)]
    check("%s:ins-w takes a block from below to world, Z and all" % prefix,
          got['down'] == [-100.0, 20.0, 5.0], got['down'])
    check("%s:ins-w leaves a flat block, a POINT, as stored" % prefix,
          got['flat'][:2] == [30.0, 40.0] and got['pt'] == [7.0, 8.0, 9.0],
          got)
    check("%s:ins-w takes a TEXT from below to world" % prefix,
          got['tx'][:2] == [-60.0, 30.5], got['tx'])

# the "every point in the drawing" collectors the declarations click on
for prefix in ('pf', 'cab', 'lh', 'abl'):
    vm = loaded(prefix)
    survey(vm)
    got = vm.loads('(%s:collect-points)' % prefix)
    check("%s:collect-points offers each block where it is drawn" % prefix,
          xy([c[0] for c in got]) == WORLD, got)

# the selection readers that are functions of their own
for prefix, call in (('abp', '(car (abp:harvest SS))'),
                     ('lobf', '(lobf:harvest SS)')):
    vm = loaded(prefix)
    vm.globals[Sym('ss')] = ['<ss>'] + survey(vm)
    got = vm.loads(call)
    check("%s's harvest reads each block where it is drawn" % prefix,
          xy(got) == WORLD, got)

vm = loaded('fit')
vm.globals[Sym('ss')] = ['<ss>'] + survey(vm)
vm.loads('(setq fit-pts nil fit-ptnames nil fit-npt 0 fit-nmoved 0)')
vm.loads('(fit:gather SS)')
got = vm.loads('fit-pts')
check("fit:gather reads each block where it is drawn", xy(got) == WORLD, got)

# and the readers inside the commands themselves: every point handed to
# the tool's add-point is recorded, and the run stops where the script
# runs out, after the read
SETTINGS = [None, None, None, None, 'No', 'No', 'No']
vm = loaded('pf')
ents = survey(vm)
record(vm, 'pf:add-point')
drive(vm, 'c:ABHD', SETTINGS + [ents])
check("c:ABHD reads each block where it is drawn",
      xy(r[0] for r in seen(vm)) == WORLD, seen(vm))

vm = loaded('pf')
ents = survey(vm)
record(vm, 'pf:add-point')
drive(vm, 'c:ADAB', [None, ents])
check("c:ADAB reads each selected block where it is drawn",
      xy(r[0] for r in seen(vm)) == WORLD, seen(vm))

# ADAB handed the perimeter alone gathers the points itself: a 120 x 80
# rectangle right of the Y axis, and four ab_pt blocks from below that
# sit on it in the world.  Read raw they sit left of the axis, off it,
# and not one is picked up
vm = loaded('pf')
layer(vm, 'POINTS', 0)
layer(vm, 'POOL', 0)
vm.loads('(entmake (list \'(0 . "LWPOLYLINE") \'(8 . "POOL")'
         ' \'(100 . "AcDbPolyline") \'(90 . 4) \'(70 . 1)'
         ' \'(10 20.0 0.0) \'(10 140.0 0.0) \'(10 140.0 80.0)'
         ' \'(10 20.0 80.0)))')
pl = vm.entities[-1]
for x, y in ((80.0, 0.0), (140.0, 40.0), (80.0, 80.0), (20.0, 40.0)):
    insert(vm, 'ab_pt', 'POINTS', -x, y)
record(vm, 'pf:add-point')
drive(vm, 'c:ADAB', [None, [pl]])
check("c:ADAB gathers the perimeter's blocks where they are drawn",
      '4 survey point(s) sitting on the perimeter picked up' in said(vm)
      and xy(r[0] for r in seen(vm)) == {(80.0, 0.0), (140.0, 40.0),
                                         (80.0, 80.0), (20.0, 40.0)},
      (seen(vm), said(vm)[-300:]))

vm = loaded('cab')
ents = survey(vm)
record(vm, 'cab:add-point')
drive(vm, 'c:CABHD', [None, None, None, "None", "No", "No", "No", ents])
check("c:CABHD reads each block where it is drawn",
      xy(r[0] for r in seen(vm)) == WORLD, seen(vm))

vm = loaded('abl')
ents = survey(vm)
record(vm, 'abl:add-point')
vm.pickfirst = ['<ss>'] + ents
drive(vm, 'c:ABLOBF', [1.0, None, None, 'Done', None])
check("c:ABLOBF reads each block where it is drawn",
      xy(r[0] for r in seen(vm)) == WORLD, seen(vm))

# LHD takes a block's Z as its laser elevation, and pairs a numeric TEXT
# with the point beside it.  From below, the Z is -z in its plane, and
# the label is at (-x, y): read raw, the elevation came back with its
# sign flipped and the label paired with nothing
vm = loaded('lh')
layer(vm, 'POINTS', 0)
ents = [insert(vm, 'ab_pt', 'POINTS', 100.0, 20.0, -5.0),
        insert(vm, 'MARK', 'POINTS', 50.0, 10.0, -7.0)]
for x, y in ((-60.0, 30.0), (0.0, 0.0)):
    vm.loads('(entmake (list \'(0 . "POINT") \'(8 . "POINTS")'
             ' (list 10 %r %r 0.0)))' % (x, y))
    ents.append(vm.entities[-1])
vm.loads('(entmake (list \'(0 . "TEXT") \'(8 . "0") \'(40 . 1.0)'
         ' \'(1 . "12.5") (list 10 60.0 30.5 0.0) %s))' % DOWN)
ents.append(vm.entities[-1])
record(vm, 'lh:add-point')
zvals = []


def snap_zvals(vm):
    zvals.extend(vm.get(Sym('lh-zvals')) or [])
    return 'None'


vm.pickfirst = ['<ss>'] + ents
drive(vm, 'c:LHD', [1.0, None, None, 'Open', 'Done', snap_zvals])
read = {(round(float(r[0][0]), 6), round(float(r[0][1]), 6)):
        float(r[2]) for r in seen(vm)}
check("c:LHD reads each block where it is drawn",
      set(read) == {(-100.0, 20.0), (-50.0, 10.0), (-60.0, 30.0),
                    (0.0, 0.0)}, seen(vm))
blocks = read
check("...with its elevation the right way up",
      blocks.get((-100.0, 20.0)) == 5.0 and blocks.get((-50.0, 10.0)) == 7.0,
      blocks)
labelled = {(round(float(z.a[0]), 6), round(float(z.a[1]), 6)): float(z.b)
            for z in zvals if isinstance(z, Dot)}
check("...and a label from below names the point it stands by",
      labelled.get((-60.0, 30.0)) == 12.5, (zvals, said(vm)[-300:]))


# ======================================================================
# 7. TUTORIALABHD's demo is drawn where its spot was clicked
# ======================================================================
print("\nTUTORIALABHD's demo under a moved UCS")

# the UCS origin moved to world (1000, 0) and the spot clicked at its
# own origin: the practice survey rings world x 1000 (its kidney sits a
# little right of centre, about 26 over), not world x 0
vm = loaded('pf')
vm.script = [(0.0, 0.0, 0.0)]
before = len(vm.entities)
vm.set_ucs((1000.0, 0.0, 0.0))
try:
    vm.loads('(pf:tut-demo)')        # stops at its first pause
except LispError:
    pass
xs = [float(grp(vm.entdata.get(e, []), 10)[0]) for e in vm.entities[before:]
      if grp(vm.entdata.get(e, []), 0) == 'POINT' and live(vm, e)]
check("the practice survey is drawn round the spot that was picked",
      len(xs) == 44 and abs(sum(xs) / len(xs) - 1025.875) < 1e-6,
      (len(xs), sum(xs) / len(xs) if xs else None))


print()
if FAILS:
    print('%d check(s) FAILED: %s' % (len(FAILS), ', '.join(FAILS)))
    sys.exit(1)
print('all survey-fitter helper checks passed')
