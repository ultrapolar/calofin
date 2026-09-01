#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime smoke tests for TUTORIALSPA.LSP: load the REAL SPA.LSP and
TUTORIALSPA.LSP into the AutoLISP VM and take the whole tour with
scripted Enters, so a helper rename or arity change in SPA.LSP that
would break the walkthrough at the AutoCAD command line breaks here
instead.  test_tutorialpool.py is the same suite for POOL's tutorial.

Two things differ from the round-3 suites and both are about this
file's age: the banner is the DATED form (tut:*version* is
"MMDDYY REV##", not "vN.N") and the releases twin keeps the source's
UPPERCASE .LSP extension.

Usage:  python3 tests/test_tutorialspa.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_tutorialspa.py
"""

import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
from lispvm import VM, LispError  # noqa: E402

SPA = os.path.join(REPO_DIR, 'lisp', 'spa', 'SPA.LSP')
TUT = os.path.join(REPO_DIR, 'lisp', 'spa', 'TUTORIALSPA.LSP')
RELEASES = os.path.join(REPO_DIR, 'releases')

#: the demo pauses after each of its steps, plus the one bare pause
#: before them; Enter carries on, "X" stops the tour
PAUSES = [''] * 9

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


def on_layer(vm, lay):
    return [e for e in vm.entdata if vm.layer_of(e) == lay]


def restored(vm, before):
    """Every sysvar that EXISTED before the run is back where it was.

    Not `vm.sysvars == before`: SPA's save list names the DIM* vars, and
    restoring one the drawing never had materialises the key at 0 --
    which is what an unknown sysvar already reads in the VM, so nothing
    actually moved.  A key that was set before and differs after is the
    real failure this is looking for."""
    return {k: v for k, v in before.items() if vm.sysvars.get(k) != v}


def newvm():
    vm = VM()
    vm.load(SPA)
    vm.load(TUT)
    return vm


def drive(script, label):
    vm = newvm()
    try:
        vm.run('c:TUTORIALSPA', list(script))
    except LispError as e:
        raise AssertionError(f'[{label}] {e}') from None
    return vm


print('tutorial -- the full tour, Enter at every pause')
vm = newvm()
before = dict(vm.sysvars)
try:
    vm.run('c:TUTORIALSPA', [None, None, (0.0, 0.0)] + PAUSES)
except LispError as e:
    raise AssertionError(f'[full tour] {e}') from None
check('drew the spa outline and its cover',
      on_layer(vm, 'POOL') and len(on_layer(vm, 'COVER')) >= 3)
check('drew dimensions', len(on_layer(vm, 'DIMENSION')) > 3)
check('drew its captions', len(on_layer(vm, 'SPA-NOTES')) > 3)
moved = restored(vm, before)
check('every sysvar it found is back where it started', not moved)
if moved:
    print('       moved:', moved)
check('the run is one undo group',
      [c for c in vm.commands if c and c[0] == '_.UNDO']
      == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']])

print('tutorial -- X at the first pause stops the tour')
vm = drive([None, None, (0.0, 0.0), 'X'] + PAUSES[:0], 'early stop')
check('it stopped before the tour finished',
      len(on_layer(vm, 'DIMENSION')) < 3)

print('tutorial -- Checks does the checklist, not the demo')
vm = drive(['Checks', None], 'checks only')
said = ''.join(vm.printed)
check('printed the checklist headings', 'WHAT SPA ASKS YOU' in said)
check('and never asked where to put the demo',
      not any('demo go' in p for p, _ in vm.prompts), )

print('tutorial -- Demo does the drawing, not the checklist')
vm = drive(['Demo', (0.0, 0.0)] + PAUSES, 'demo only')
check('drew the demo',
      on_layer(vm, 'POOL') and len(on_layer(vm, 'COVER')) >= 3)
check('and printed no checklist',
      'WHAT SPA ASKS YOU' not in ''.join(vm.printed))

print('tutorial -- CHECKLIST is the hidden legacy alias for Checks')
vm = drive(['CHECKLIST', None], 'alias')
check('the old word still reaches the checklist',
      'WHAT SPA ASKS YOU' in ''.join(vm.printed))

print('tutorial -- the reference sheet is optional')
vm = drive(['Checks', (100.0, 100.0)], 'sheet placed')
check('a point places the sheet', len(on_layer(vm, 'SPA-NOTES')) > 3)

print('tutorial -- without SPA.LSP it says which file is missing')
#: the real path for someone who APPLOADs the tutorial on its own
vm = VM()
vm.load(TUT)
vm.loads('(setq spa:*version* nil)')
try:
    vm.run('c:TUTORIALSPA', [])
except LispError as e:
    raise AssertionError(f'[gate] {e}') from None
check('it names SPA.LSP', 'Load SPA.LSP first' in ''.join(vm.printed))
check('and asked nothing', not vm.prompts)

print('statics -- banner and the dated twin')
for path, name in ((TUT, 'TUTORIALSPA.LSP'),):
    text = open(path, encoding='ascii').read()      # also asserts ASCII
    m = re.search(r'\*version\*\s+"(\d{6}) REV(\d{2})"', text)
    check(f'{name} carries a dated version banner', m is not None)
    if m:
        twin = f'{name[:-4]}_{m.group(1)}_REV{m.group(2)}.LSP'
        ok = os.path.exists(os.path.join(RELEASES, twin))
        check(f'releases/{twin} exists', ok)
        if ok:
            same = open(os.path.join(RELEASES, twin)).read() == text
            check(f'releases/{twin} is byte-identical', same)

if failures:
    print(f'\n{len(failures)} TUTORIALSPA check(s) FAILED')
    sys.exit(1)
print('\nall TUTORIALSPA checks passed')
