#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression tests for a pass over MOHAMADDLE, PADDLE and AUTODIM:
what each of them did quietly wrong, driven through the real files.

  * MOHAMADDLE's size prompt handed its default back on Enter without
    checking it against *mohamaddle-sizes*.  The default is a LAZTUNE
    knob, so an override applied after load ("48", a dwg path, a size
    dropped from the table) found no entry, died on arithmetic with nil,
    and was saved as the next default first -- every Enter after it died
    the same way.

  * PADDLE and MOHAMADDLE swept (410 . CTAB) and inserted into the
    ACTIVE LAYOUT's block.  From inside a layout's viewport both name
    the sheet: auto-detect found no perimeter and the pads would have
    gone into paper space over a model-space pool.

  * AUTODIM's measuring lines carry no layer of their own, so with
    ad:*layer* nil they land on the current layer -- and AutoCAD draws
    on a locked current layer but will not erase from one.  Every side
    of the plan left a full-length probe line behind with nothing said,
    and a Back left the dims it meant to roll back.  The VM does not
    model locked layers, so the two halves of that are modelled here:
    an entmake with no group 8 lands on CLAYER, and entdel refuses an
    entity whose layer is locked.

  * AUTODIM handed PADDLE the plan as a pickfirst set with PICKFIRST
    forced to 1 round the call -- and an Esc inside PADDLE runs only
    PADDLE's own handler, so a drafter who works with PICKFIRST at 0 was
    left at 1 for good.  The plan goes over in *calofin-handoff* now,
    and PICKFIRST is never touched.  Driven here against the REAL
    PADDLE, Esc'd at its own gap question.

Run: python3 tests/test_fix_annot_b.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_fix_annot_b.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, Dot, LispError, Sym, NIL, T  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
#: lispvm's VM.load remaps a lisp/ path to the tier CALOFIN_LISP_ROOT
#: names, so under `make parity` these are runs of the shared twins
ROOT = os.path.join(REPO, 'lisp')
MOHAMADDLE = os.path.join(ROOT, 'mohamaddle', 'MOHAMADDLE.lsp')
PADDLE = os.path.join(ROOT, 'paddle', 'PADDLE.lsp')
AUTODIM = os.path.join(ROOT, 'autodim', 'AutoDim.lsp')

FAILS = []


def check(label, cond, detail=''):
    print(('  ok   ' if cond else '  FAIL ') + label
          + (('  -- ' + str(detail)) if detail and not cond else ''))
    if not cond:
        FAILS.append(label)


def dxf(vm, e, code):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1:] if len(g) > 2 else g[1]
    return None


def live(vm, etype=None):
    return [e for e in vm.entities if e not in vm.deleted
            and (etype is None or dxf(vm, e, 0) == etype)]


def printed(vm):
    return ''.join(str(x) for x in vm.printed)


def esc(vm):
    raise LispError('Function cancelled', vm)


#: straight walls, a slot with two inside corners and a concave bite --
#: the sample test_mohamaddle.py pads, as one closed polyline
PERIMETER = '''
(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity") (cons 8 "DEMO")
               (cons 100 "AcDbPolyline") (cons 90 13) (cons 70 1)
               (list 10 0.0 0.0)     (list 10 150.0 3.0)  (list 10 300.0 0.0)
               (list 10 300.0 168.0) (list 10 264.0 168.0) (cons 42 -1.0)
               (list 10 168.0 168.0) (list 10 132.0 168.0)
               (list 10 132.0 120.0) (list 10 84.0 120.0)
               (list 10 84.0 168.0)  (list 10 0.0 168.0)
               (list 10 0.0 134.0)   (cons 42 -0.4038)
               (list 10 0.0 34.0)))
'''

DEMO_LAYER = '''
(entmakex (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")
                (cons 100 "AcDbLayerTableRecord") (cons 2 "DEMO")
                (cons 70 0) (cons 62 3) (cons 6 "Continuous")))
'''


def layer(vm, name, flags=0):
    vm.loads('(entmake (list (cons 0 "LAYER") (cons 100 "AcDbSymbolTableRecord")'
             ' (cons 100 "AcDbLayerTableRecord") (cons 2 "%s") (cons 70 %d)'
             ' (cons 62 7) (cons 6 "Continuous")))' % (name, flags))


def layer_flags(vm, name):
    rec = vm.tablerecs['LAYER'][name.upper()]
    for g in vm.recdata[rec]:
        if isinstance(g, Dot) and g.a == 70:
            return g.b
    return 0


# ---------------------------------------------------------------------
print("MOHAMADDLE -- a default the size table does not offer")
# ---------------------------------------------------------------------
for label, setup, want in (
        ('a dwg path typed into the knob',
         '(setq *mohamaddle-defaultkw* "C:\\\\Pads\\\\pads.dwg")', 'Pad36x36'),
        ('a size the table never had',
         '(setq *mohamaddle-defaultkw* "48")', 'Pad36x36'),
        ('the right size in the wrong case',
         '(setq *mohamaddle-sizes* (list (list "S24" "Pad24x24" 24.0)'
         ' (list "L36" "Pad36x36" 36.0)) *mohamaddle-defaultkw* "s24")',
         'Pad24x24'),
        ('the shipped default dropped from the table',
         '(setq *mohamaddle-sizes* (list (list "24" "Pad24x24" 24.0)'
         ' (list "48" "Pad36x36" 48.0)))', 'Pad24x24')):
    vm = VM()
    vm.load(MOHAMADDLE)
    vm.loads(DEMO_LAYER)
    vm.loads(PERIMETER)
    vm.loads(setup)
    n0 = len(vm.entities)
    try:
        vm.run('c:MOHAMADDLE', [None, None, None])
        err = None
    except LispError as e:
        err = str(e)
    pads = [e for e in live(vm, 'INSERT') if e in vm.entities[n0:]]
    check('%s: Enter places pads instead of failing' % label,
          err is None and pads, err)
    check('%s: ...of a size the table offers' % label,
          {dxf(vm, e, 2) for e in pads} == {want},
          {dxf(vm, e, 2) for e in pads})
    kw = vm.get(Sym('*mohamaddle-defaultkw*'))
    sizes = vm.get(Sym('*mohamaddle-sizes*'))
    check('%s: and what is remembered is a keyword the prompt offers' % label,
          any(s[0] == kw for s in sizes), kw)
    shown = vm.prompts[0][0] if vm.prompts else ''
    check('%s: the bracket default is one of the offered sizes' % label,
          any('<%s>' % s[0] in shown for s in sizes), shown)


# ---------------------------------------------------------------------
print("PADDLE / MOHAMADDLE -- run from inside a layout's viewport")
# ---------------------------------------------------------------------
# From a viewport CTAB and the active layout both name the SHEET.  The
# VM has one space, so the two halves of AutoCAD are modelled: the
# active layout's block is paper space when TILEMODE is 0, and model
# space is what vla-get-ModelSpace hands back.  Every insert records the
# space it was aimed at.
PAPER = '<paper-space>'


def viewport_vm(path, extra=''):
    vm = VM()
    vm.load(path)
    vm.loads(DEMO_LAYER)
    vm.loads(PERIMETER)
    # the sheet's own frame, in paper space: a bigger loop than the pool
    vm.loads('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
             ' (cons 8 "DEMO") (cons 410 "Layout1") (cons 100 "AcDbPolyline")'
             ' (cons 90 4) (cons 70 1) (list 10 -500.0 -500.0)'
             ' (list 10 900.0 -500.0) (list 10 900.0 700.0)'
             ' (list 10 -500.0 700.0)))')
    if extra:
        vm.loads(extra)
    vm.sysvars['TILEMODE'] = 0
    vm.sysvars['CTAB'] = 'Layout1'
    vm.sysvars['CVPORT'] = 2               # inside the viewport
    return vm


def with_spaces(run):
    B = lispvm.BUILTINS
    saved = {k: B[Sym(k)] for k in ('vla-get-block', 'vla-insertblock')}
    aimed = []

    def get_block(vm, a):
        saved['vla-get-block'](vm, a)
        return PAPER if vm.sysvars.get('TILEMODE') == 0 else lispvm.MODEL_SPACE

    def insert(vm, a):
        aimed.append(a[0])
        return saved['vla-insertblock'](vm, [lispvm.MODEL_SPACE] + list(a[1:]))
    B[Sym('vla-get-block')] = get_block
    B[Sym('vla-insertblock')] = insert
    B[Sym('vla-get-modelspace')] = lambda vm, a: lispvm.MODEL_SPACE
    try:
        run()
    finally:
        B.update({Sym(k): v for k, v in saved.items()})
        B.pop(Sym('vla-get-modelspace'), None)
    return aimed


for name, path, script in (('PADDLE', PADDLE, [None, None]),
                           ('MOHAMADDLE', MOHAMADDLE, ['36', None, None])):
    vm = viewport_vm(path)
    n0 = len(vm.entities)
    aimed = with_spaces(lambda: vm.run('c:' + name, script))
    out = printed(vm)
    pads = [e for e in live(vm, 'INSERT') if e in vm.entities[n0:]]
    check('%s: Enter auto-detects the model-space pool, not the sheet' % name,
          len(pads) == 5, '%d pads; %s' % (len(pads), out[-200:]))
    check('%s: every pad is aimed at model space, where the pool is' % name,
          aimed and set(aimed) == {lispvm.MODEL_SPACE}, aimed[:3])

# and with the paper itself active, the sheet is what is read.  The
# sheet's rectangle has no concave feature, so a run that padded it
# would insert nothing and a check on "every insert aimed at paper"
# would pass on no inserts at all -- so the sheet here also carries an
# L-shaped loop, bigger than the frame, with ONE inside corner.  Its one
# pad, and only that pad, is what a paper-space run places.
SHEET_L = ('(entmake (list (cons 0 "LWPOLYLINE") (cons 100 "AcDbEntity")'
           ' (cons 8 "DEMO") (cons 410 "Layout1") (cons 100 "AcDbPolyline")'
           ' (cons 90 6) (cons 70 1) (list 10 -600.0 -600.0)'
           ' (list 10 1000.0 -600.0) (list 10 1000.0 800.0)'
           ' (list 10 200.0 800.0) (list 10 200.0 300.0)'
           ' (list 10 -600.0 300.0)))')
vm = viewport_vm(PADDLE, SHEET_L)
vm.sysvars['CVPORT'] = 1
n0 = len(vm.entities)
aimed = with_spaces(lambda: vm.run('c:PADDLE', [None, None]))
pads = [e for e in live(vm, 'INSERT') if e in vm.entities[n0:]]
check('PADDLE: paper active -- the sheet is the space read and padded',
      aimed and set(aimed) == {PAPER}, aimed[:3])
check("PADDLE: paper active -- one pad, at the sheet loop's inside corner",
      len(pads) == 1 and dxf(vm, pads[0], 10)[:2] == [200.0, 300.0],
      [dxf(vm, p, 10) for p in pads])


# ---------------------------------------------------------------------
print("AUTODIM -- measuring lines on a locked current layer")
# ---------------------------------------------------------------------
PLAN = [((0, 0), (0, 60)), ((0, 60), (120, 60)),
        ((120, 60), (120, 0)), ((120, 0), (0, 0))]
STYLES = {'STANDARD', 'SIDE STANDARD', 'STANDARD INCHES'}


def autodim_vm():
    vm = VM()
    vm.load(AUTODIM)
    vm.tables['DIMSTYLE'] = set(STYLES)
    vm.script = [None]                      # ad:begin's ssget: no dims yet
    vm.loads('(ad:begin)')
    return vm


def locked_world(run):
    """AutoCAD's two halves the VM leaves out: an entmake with no group
    8 lands on CLAYER, and entdel will not erase from a locked layer."""
    B = lispvm.BUILTINS
    real_make, real_del = B[Sym('entmake')], B[Sym('entdel')]

    def make(vm, a):
        alist = a[0]
        if (isinstance(alist, list) and alist
                and not any(isinstance(g, Dot) and g.a == 8 for g in alist)
                and any(isinstance(g, Dot) and g.a == 0 and g.b == 'LINE'
                        for g in alist)):
            alist = list(alist) + [Dot(8, vm.sysvars.get('CLAYER', '0'))]
        return real_make(vm, [alist] + list(a[1:]))

    def delete(vm, a):
        lay = dxf(vm, a[0], 8)
        rec = vm.tablerecs.get('LAYER', {}).get(str(lay or '').upper())
        if rec is not None:
            fl = [g.b for g in vm.recdata[rec]
                  if isinstance(g, Dot) and g.a == 70]
            if fl and fl[0] & 4 and a[0] not in vm.deleted:
                return NIL                  # refused, without a word
        return real_del(vm, a)
    B[Sym('entmake')], B[Sym('entdel')] = make, delete
    try:
        return run()
    finally:
        B[Sym('entmake')], B[Sym('entdel')] = real_make, real_del


vm = autodim_vm()
layer(vm, 'MINE', 4)                        # locked, and current
vm.sysvars['CLAYER'] = 'MINE'


def _perim():
    for (x1, y1), (x2, y2) in PLAN:
        vm.loads('(entmake (list (cons 0 "LINE") (cons 8 "MINE")'
                 ' (cons 10 (list %.4f %.4f 0.0))'
                 ' (cons 11 (list %.4f %.4f 0.0))))' % (x1, y1, x2, y2))
    vm.script = [list(vm.entities)]
    vm.loads('(setq SS (ssget))')
    return vm.loads('(ad:dimperim SS T)')


n = locked_world(_perim)
lines = live(vm, 'LINE')
check('the perimeter was dimensioned', n == 4, n)
check('no measuring line is left behind on the locked layer',
      len(lines) == 4, '%d LINEs live' % len(lines))
check('and the layer is locked again after each one went',
      layer_flags(vm, 'MINE') & 4 == 4, layer_flags(vm, 'MINE'))


print("AUTODIM -- a measuring line that still will not go is SAID")
# Unlocking is the one refusal ad:scrap can talk its way past.  Any
# other -- modelled here as a layer whose objects entdel will not take
# at all -- left the probe line standing with nothing said, a stray LINE
# the next floor dims run sweeps in as a wall.  The count of them goes
# out with the end-of-run skip report, and must be the number left.


def stuck_world(run):
    B = lispvm.BUILTINS
    real_make, real_del = B[Sym('entmake')], B[Sym('entdel')]

    def make(vm, a):
        alist = a[0]
        if (isinstance(alist, list) and alist
                and not any(isinstance(g, Dot) and g.a == 8 for g in alist)
                and any(isinstance(g, Dot) and g.a == 0 and g.b == 'LINE'
                        for g in alist)):
            alist = list(alist) + [Dot(8, vm.sysvars.get('CLAYER', '0'))]
        return real_make(vm, [alist] + list(a[1:]))

    def delete(vm, a):
        return NIL if dxf(vm, a[0], 8) == 'STUCK' else real_del(vm, a)
    B[Sym('entmake')], B[Sym('entdel')] = make, delete
    try:
        return run()
    finally:
        B[Sym('entmake')], B[Sym('entdel')] = real_make, real_del


def stuck_report(vm):
    vm.printed = []
    vm.loads('(ad:skipreport)')
    m = re.search(r'(\d+) measuring line\(s\) could NOT be erased',
                  printed(vm))
    return int(m.group(1)) if m else 0


vm = autodim_vm()
layer(vm, 'MINE')
layer(vm, 'STUCK')
vm.sysvars['CLAYER'] = 'STUCK'
stuck_world(_perim)
left = len(live(vm, 'LINE')) - len(PLAN)
check('perimeter: the probe lines that stayed are counted, all of them',
      left > 0 and stuck_report(vm) == left,
      (left, printed(vm)[-200:]))

vm = autodim_vm()
layer(vm, 'MINE')
layer(vm, 'STUCK')
vm.sysvars['CLAYER'] = 'STUCK'


def _floor():
    for (x1, y1), (x2, y2) in PLAN:
        vm.loads('(entmake (list (cons 0 "LINE") (cons 8 "MINE")'
                 ' (cons 10 (list %.4f %.4f 0.0))'
                 ' (cons 11 (list %.4f %.4f 0.0))))' % (x1, y1, x2, y2))
    vm.script = [list(vm.entities)]
    vm.loads('(setq SS (ssget))')
    return vm.loads("(ad:floorchain '(0.0 30.0 0.0) '(120.0 30.0 0.0)"
                    " '(60.0 40.0 0.0) SS)")


stuck_world(_floor)
check('floor dims: the measuring line that stayed is said',
      len(live(vm, 'LINE')) == len(PLAN) + 1 and stuck_report(vm) == 1,
      (len(live(vm, 'LINE')), printed(vm)[-200:]))
vm.script = [None]
vm.loads('(ad:begin)')
check('and the count starts again with the next run',
      stuck_report(vm) == 0, printed(vm)[-200:])


print("AUTODIM -- a Back rolls back what it drew, or says what it could not")
vm = autodim_vm()
layer(vm, 'MINE', 4)
vm.sysvars['CLAYER'] = 'MINE'
vm.loads('(entmake (list (cons 0 "LINE") (cons 8 "MINE")'
         ' (cons 10 (list 0.0 0.0 0.0)) (cons 11 (list 1.0 0.0 0.0))))')
vm.loads('(setq mark (entlast))')
vm.loads('(entmake (list (cons 0 "LINE") (cons 8 "MINE")'
         ' (cons 10 (list 0.0 5.0 0.0)) (cons 11 (list 9.0 5.0 0.0))))')
drawn = vm.entities[-1]
vm.script = [None]                          # ad:dimscan's re-read
locked_world(lambda: vm.loads('(ad:eraseafter mark)'))
check('what the step drew on the locked layer is rolled back',
      drawn in vm.deleted)
check('what came before the mark is left alone',
      vm.entities[-2] not in vm.deleted)
check('and nothing is reported stuck', 'could NOT be erased'
      not in printed(vm), printed(vm)[-200:])

vm = autodim_vm()
vm.loads('(setq mark (entlast))')
vm.loads('(entmake (list (cons 0 "LINE")'
         ' (cons 10 (list 0.0 5.0 0.0)) (cons 11 (list 9.0 5.0 0.0))))')
stuck = vm.entities[-1]
real_del = lispvm.BUILTINS[Sym('entdel')]
lispvm.BUILTINS[Sym('entdel')] = \
    lambda vm, a: NIL if a[0] is stuck else real_del(vm, a)
try:
    vm.script = [None]
    vm.loads('(ad:eraseafter mark)')
finally:
    lispvm.BUILTINS[Sym('entdel')] = real_del
check('an erase that will not take is SAID, not skipped',
      '1 object(s) from that step could NOT be erased' in printed(vm),
      printed(vm)[-200:])


# ---------------------------------------------------------------------
print("AUTODIM -> PADDLE -- the plan is handed over, PICKFIRST untouched")
# ---------------------------------------------------------------------
# The dimensioning steps need ActiveX the VM has no stub for, so they are
# replaced by notes of having run (test_autodim.py's TRACE).  PADDLE is
# the real one: handed a perimeter with a gap in it, it arrows the gap
# and asks whether to close it -- and the drafter presses Esc there.
TRACE = """
  (defun ad:dimperim (ss all) 0)
  (defun ad:dimstairs (ss0) 0)
  (defun ad:getfloor (tag obstacles back) 0)
  (defun ad:overall (plan) 0)
  (defun ad:runsteps (risers) (princ))"""

GAPPY = [((0, 0), (300, 0)), ((300, 0), (300, 168)), ((300, 168), (132, 168)),
         ((132, 168), (132, 120)), ((132, 120), (84, 120)),
         ((84, 120), (84, 168)), ((84, 168), (0, 168)), ((0, 168), (0, 12))]


def autodim_paddle(answers):
    vm = autodim_vm()
    vm.load(PADDLE)
    vm.loads(DEMO_LAYER)
    for (x1, y1), (x2, y2) in GAPPY:
        vm.loads('(entmake (list (cons 0 "LINE") (cons 8 "DEMO")'
                 ' (list 10 %.4f %.4f 0.0) (list 11 %.4f %.4f 0.0)))'
                 % (x1, y1, x2, y2))
    ents = [e for e in vm.entities if dxf(vm, e, 0) == 'LINE']
    vm.loads(TRACE)
    vm.sysvars['PICKFIRST'] = 0             # a drafter who works verb-noun
    vm.handle_errors = True
    # the pickfirst probe, the plan, step 2's repeats question, No to
    # floor dims, Yes to pads -- then whatever PADDLE asks
    vm.run('c:AUTODIM', [None, ents, None, 'No', 'Yes'] + answers)
    return vm


vm = autodim_paddle([esc])
out = printed(vm)
check('PADDLE was handed the plan and asked nothing about the perimeter',
      'Select perimeter' not in out and 'gap(s) in it' in out, out[-300:])
check("the Esc went through PADDLE's own handler",
      vm.handled_errors == ['Function cancelled'], vm.handled_errors)
check("PICKFIRST is still the drafter's 0", vm.sysvars['PICKFIRST'] == 0,
      vm.sysvars['PICKFIRST'])
check('and no handoff is left for the next PADDLE to pick up',
      vm.get(Sym('*calofin-handoff*')) is None)

vm = autodim_paddle(['Yes'])
check('answered instead, the gap is closed and PICKFIRST is still 0',
      vm.sysvars['PICKFIRST'] == 0 and not vm.handled_errors,
      (vm.sysvars['PICKFIRST'], vm.handled_errors))


print("AUTODIM -- a set handed to AUTODIM itself (TYLERDRONESUITE's)")
vm = autodim_vm()
vm.loads('(entmake (list (cons 0 "LINE") (cons 10 (list 0.0 0.0 0.0))'
         ' (cons 11 (list 9.0 0.0 0.0))))')
vm.loads('(entmake (list (cons 0 "TEXT") (cons 1 "A")'
         ' (cons 10 (list 1.0 1.0 0.0))))')
vm.loads('(setq hs (ssadd)) (ssadd (entnext) hs) (ssadd (entlast) hs)')
got = vm.loads('(progn (setq *calofin-handoff* (list "AUTODIM" hs))'
               ' (ad:handed))')
check('only the geometry AUTODIM dimensions is taken',
      got is not NIL and got[1:] == [vm.entities[-2]], got)
check('and the handoff is cleared at the read',
      vm.get(Sym('*calofin-handoff*')) is None)


print()
if FAILS:
    print('test_fix_annot_b: %d FAILURE(S): %s' % (len(FAILS), ', '.join(FAILS)))
    sys.exit(1)
print('test_fix_annot_b: all checks passed')
