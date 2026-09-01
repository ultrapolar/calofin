#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""First VM contact for c:LHD, the laser-scan outline fitter.

tests/test_laser_fit.py is a Python transcription of the fit and owns
the geometry; it never loads lispvm at all, so until now nothing had
run the command itself.  This file covers the WRAPPER - the wizard's
shape, the pickfirst probe, the undo bracket, the declare loop and its
self-clearing markers - and deliberately does not re-check the fit.

Deliberately NOT covered yet, and worth saying so rather than leaving
it to look like an oversight: the *error*/Esc path (handler code never
executes in this VM, so it can only be read statically) and the
multi-fit pick loop, whose Redo branch re-enters the fit and needs
fixtures of its own.

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

print()
if FAILS:
    print(f'{len(FAILS)} LHD check(s) FAILED: ' + ', '.join(FAILS))
    sys.exit(1)
print('all LHD checks passed')
