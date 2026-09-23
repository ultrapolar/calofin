#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""First VM contact for c:LHD, the laser-scan outline fitter.

tests/test_laser_fit.py is a Python transcription of the fit and owns
the geometry; it never loads lispvm at all, so until now nothing had
run the command itself.  This file covers the WRAPPER - the wizard's
shape, the pickfirst probe, the undo bracket, the declare loop and its
self-clearing markers - and deliberately does not re-check the fit.

It also drives the multi-fit pick loop: a click that misses every
outline, and the Redo branch that re-enters the fit (a typed Back at
its omit prompt, a point left out, Enter through the edits, the fit
drawn again) -- and the POOL-layer sketch that orders the points, as
one polyline and as loose lines.  Covered elsewhere, and so not here:
the *error*/Esc path (tests/test_cancel_paths.py runs the handler) and
the height question for points that carry elevations
(tests/test_back_nav.py, section 9b).

One rule this file keeps: every assertion is POSITIVE - something is
in the output, some list has a length.  vl-catch-all-apply swallows an
"undefined function", so a test shaped as "no error was raised" can
pass against a routine that silently did nothing.

Usage:  python3 tests/test_lhd_runtime.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_lhd_runtime.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..',
                   'lisp', 'lhd', 'lhd.lsp')

#: steps 1-4 taking their Enter defaults, then Done at the declare loop
#: and Enter at the step-6 selection
WIZARD = [1.0, None, None, 'Open', 'Done', None]

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


print('lhd -- the wizard runs end to end with nothing selected')
vm = newvm()
try:
    vm.run('c:LHD', [None] + WIZARD)
except LispError as e:
    raise AssertionError(f'[wizard] {e}') from None
said = ''.join(vm.printed)
check('it walks all six steps', 'Step 1 of 6' in said and 'Step 6 of 6' in said)
check('and says nothing usable was selected',
      'Nothing usable selected' in said or 'nothing' in said.lower(),
      said[-160:])
undo = [c for c in vm.commands if c and c[0] == '_.UNDO']
check('one undo group brackets the run',
      undo == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']], undo)
check('CMDECHO and OSMODE come back',
      vm.sysvars['CMDECHO'] == 1 and vm.sysvars['OSMODE'] == 4133)

print('lhd -- the pickfirst probe is asked before anything else')
vm = newvm()
vm.run('c:LHD', [None] + WIZARD)
order = [p for p, _ in vm.prompts]
check('the probe comes first', order and order[0] == 'ssget _I', order[:2])

print('lhd -- a pre-typed selection skips step 6')
vm = newvm()
pts = points(vm, [(0.0, 0.0), (120.0, 0.0), (120.0, 60.0), (0.0, 60.0)])
vm.pickfirst = ['<ss>'] + pts
vm.run('c:LHD', WIZARD[:-1] + ['None'])
check('step 6 was never asked', 'Step 6 of 6' not in ''.join(vm.printed))
check('and no interactive selection prompt fired',
      not any(p == 'ssget' for p, _ in vm.prompts), vm.prompts)

def ab_pts(vm, pts, layer='POINTS'):
    """Scanned points carrying survey numbers, the way a converted
    export leaves them: an ab_pt insert with a numbered attribute."""
    made = []
    for n, (x, y) in enumerate(pts, 1):
        before = len(vm.entities)
        vm.loads("""
          (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                         (cons 8 "%s") '(100 . "AcDbBlockReference")
                         '(2 . "ab_pt") (list 10 %r %r 0.0) '(66 . 1)))
          (entmake (list '(0 . "ATTRIB") (cons 8 "%s")
                         '(2 . "number") (cons 1 "%d")))
          (entmake (list '(0 . "SEQEND") (cons 8 "%s")))"""
                 % (layer, x, y, layer, n, layer))
        made += vm.entities[before:]
    return made


print('lhd -- a declaration is named by its point, clicked or typed')
vm = newvm()
pts = ab_pts(vm, [(0.0, 0.0), (120.0, 0.0), (120.0, 60.0), (0.0, 60.0)])
vm.pickfirst = ['<ss>'] + pts
vm.run('c:LHD', [1.0, None, None, 'Open',
                 'Hold', "99", "3",            # a number nothing carries
                 'Corner', (118.0, 2.0, 0.0),  # a click within the snap
                 'Stretch', "1", "1", "2",     # one point twice, refused
                 'Done', 'None'])
said = ''.join(vm.printed)
check('a number no point carries is named and re-asked',
      'No survey point is numbered "99"' in said, said[:400])
check('a held point, a corner and a stretch are all counted back',
      '1 stretch(es), 1 corner(s) and 1 held point(s) noted' in said,
      said[-300:])
check('one point named for both ends of a stretch is refused',
      'a stretch needs two different points' in said, said[-300:])
live = [e for e in vm.entities if e not in vm.deleted]
check('every dashed marker cleared itself afterwards',
      not [e for e in live if vm.layer_of(e) == 'POOL-WALLS'])

print('lhd -- the declare loop takes a held point and reports it')
vm = newvm()
pts = points(vm, [(0.0, 0.0), (120.0, 0.0), (120.0, 60.0), (0.0, 60.0)])
vm.pickfirst = ['<ss>'] + pts
vm.run('c:LHD', [1.0, None, None, 'Open',
                 'Hold', (0.0, 0.0, 0.0), 'Done', 'None'])
said = ''.join(vm.printed)
check('the held point is counted', 'held point' in said, said[-200:])
live = [e for e in vm.entities if e not in vm.deleted]
onwall = [e for e in live if vm.layer_of(e) == 'POOL-WALLS']
check('its dashed marker cleared itself afterwards', not onwall, onwall)

print('lhd -- picking a candidate promotes it off the preview layer')
vm = newvm()
pts = points(vm, [(0.0, 0.0), (120.0, 0.0), (120.0, 60.0), (0.0, 60.0)])
vm.pickfirst = ['<ss>'] + pts
vm.run('c:LHD', [1.0, None, None, 'Closed', 'Done', '1'])
live = [e for e in vm.entities if e not in vm.deleted]
lays = [vm.layer_of(e) for e in live]
check('the kept fit is on the pool layer', 'POOL' in lays, lays)
check('and nothing is left on the candidate layer LHD-FIT',
      'LHD-FIT' not in lays, lays)

import math                                     # noqa: E402

#: ten scanned points round an ellipse, numbered 1-10, and a stray
#: shot beside it as Pt.11
RING = [(144.0 * math.cos(2.0 * math.pi * i / 10),
         84.0 * math.sin(2.0 * math.pi * i / 10)) for i in range(10)]
STRAY = [(170.0, 40.0)]


def said_of(vm):
    return ''.join(vm.printed)


def attempt(vm, script):
    """Run c:LHD; a LispError comes back as its first line, '' if none."""
    try:
        vm.run('c:LHD', script)
        return ''
    except LispError as e:
        return str(e).splitlines()[0]


def on_layer(vm, lay, kind=None):
    def etype(e):
        return next((g.b for g in vm.entdata.get(e, [])
                     if getattr(g, 'a', None) == 0), None)
    return [e for e in vm.entities if e not in vm.deleted
            and vm.layer_of(e) == lay
            and (kind is None or etype(e) == kind)]


print('lhd -- a click that misses the outlines is asked again')


def miss(vm):
    """entsel answers nil for Enter AND for a click on empty space; only
    ERRNO 7 tells them apart.  Taken as Enter, a near-miss kept fit 2
    and erased the fit reached for."""
    vm.sysvars['ERRNO'] = 7
    return None


def click_fit(n):
    """A click on candidate N, whose ename exists only once it is drawn."""
    def pick(vm):
        fits = on_layer(vm, 'LHD-FIT', 'LWPOLYLINE')
        return [fits[n - 1], [0.0, 0.0, 0.0]] if len(fits) >= n else None
    return pick


vm = newvm()
pts = ab_pts(vm, RING)
vm.pickfirst = ['<ss>'] + pts
err = attempt(vm, [1.0, None, None, 'Closed', 'Done', None, miss,
                   click_fit(3)])
check('the miss is named and the pick asked again',
      not err and 'nothing there - click one of the outlines' in said_of(vm),
      err)
check('...and the fit then clicked is the one kept',
      'Keeping fit 3' in said_of(vm), said_of(vm)[-300:])

print('lhd -- Redo: Back at the omit prompt, a point left out, a refit')
vm = newvm()
pts = ab_pts(vm, RING + STRAY)
vm.pickfirst = ['<ss>'] + pts
err = attempt(vm, [1.0, None, None, 'Closed', 'Done',
                   'Redo',
                   'Back',              # nothing to go back to: said, re-asked
                   '11', None,          # leave the stray out, then Enter
                   None, None, None,    # stretches, corners, held points
                   None, None, None,    # distance, percent, curve cap
                   '2'])
said = said_of(vm)
check('the Redo run went through', not err, err)
check('a typed Back at the omit prompt is refused where it stands',
      'Nothing to go back to here' in said, said[-600:])
check('the stray is named and left out of the refit',
      '- omitting Pt.11' in said
      and '1 point(s) omitted in total - 10 in the fit' in said, said[-900:])
check('the fit is drawn again and one of the new ones kept',
      said.count('Three candidate fits are now drawn') == 2
      and 'Keeping fit 2' in said
      and 'Points on the outline:        10' in said, said[-600:])
check('...leaving one outline on POOL and no scaffolding behind',
      len(on_layer(vm, 'POOL', 'LWPOLYLINE')) == 1
      and not on_layer(vm, 'LHD-FIT') and not on_layer(vm, 'POOL-WALLS'),
      (len(on_layer(vm, 'POOL', 'LWPOLYLINE')), len(on_layer(vm, 'LHD-FIT')),
       len(on_layer(vm, 'POOL-WALLS'))))

print('lhd -- a POOL-layer sketch orders the points')


def pool_layer(vm):
    vm.loads("(entmake (list '(0 . \"LAYER\") '(100 . \"AcDbSymbolTableRecord\")"
             " '(100 . \"AcDbLayerTableRecord\") '(2 . \"POOL\")"
             " '(70 . 0) '(62 . 4) '(6 . \"Continuous\")))")


def sketch_pline(vm, pts, bulge=0.1):
    pool_layer(vm)
    items = ''.join(' (list 10 %r %r) (cons 42 %r)' % (x, y, bulge)
                    for x, y in pts)
    vm.loads("(entmake (list '(0 . \"LWPOLYLINE\") '(8 . \"POOL\")"
             " '(100 . \"AcDbPolyline\") (cons 90 %d) '(70 . 1)%s))"
             % (len(pts), items))
    return [vm.entities[-1]]


def sketch_lines(vm, pts):
    pool_layer(vm)
    out = []
    for a, b in zip(pts, pts[1:] + pts[:1]):
        vm.loads("(entmake (list '(0 . \"LINE\") '(8 . \"POOL\")"
                 " (list 10 %r %r 0.0) (list 11 %r %r 0.0)))"
                 % (a[0], a[1], b[0], b[1]))
        out.append(vm.entities[-1])
    return out


for label, make, found in (('a bulged polyline', sketch_pline, True),
                           ('ten loose lines', sketch_lines, False)):
    vm = newvm()
    pts = ab_pts(vm, RING)
    sketch = make(vm, RING)
    vm.pickfirst = ['<ss>'] + pts + sketch
    err = attempt(vm, [1.0, None, None, 'Closed', 'Done', '2'])
    said = said_of(vm)
    check('%s: read as the ordering sketch, not auto-ordered' % label,
          not err and 'No sketch selected' not in said
          and (('POOL sketch found' in said) == found), err or said[-400:])
    # the sketch stays where it was drawn; the kept fit joins it on POOL
    check('%s: ...and the fit through all ten points is kept' % label,
          'Points on the outline:        10' in said
          and len(on_layer(vm, 'POOL', 'LWPOLYLINE'))
          == (2 if make is sketch_pline else 1),
          said[-400:])

print()
if FAILS:
    print(f'{len(FAILS)} LHD check(s) FAILED: ' + ', '.join(FAILS))
    sys.exit(1)
print('all LHD checks passed')
