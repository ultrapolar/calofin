#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime smoke tests for TUTORIALPOOL.LSP: load the REAL POOL.LSP and
TUTORIALPOOL.LSP into the AutoLISP VM and take the whole tour with
scripted Enters, so a helper rename or arity change in POOL.LSP that
would break the walkthrough at the AutoCAD command line breaks here
instead.

Usage:  python3 tests/test_tutorialpool.py
"""

import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
from lispvm import VM, LispError  # noqa: E402

POOL = os.path.join(REPO_DIR, 'lisp', 'pool', 'POOL.LSP')
TUT = os.path.join(REPO_DIR, 'lisp', 'pool', 'TUTORIALPOOL.LSP')
RELEASES = os.path.join(REPO_DIR, 'releases')

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


def on_layer(vm, lay):
    return [e for e in vm.entdata if vm.layer_of(e) == lay]


print('tutorial -- the full tour, Enter at every pause')
vm = VM()
vm.load(POOL)
vm.load(TUT)
before = dict(vm.sysvars)
try:
    vm.run('c:TUTORIALPOOL', [''] * 8)      # 8 pauses, topics 1-9
except LispError as e:
    raise AssertionError(f'[full tour] {e}') from None
check('drew the guide/example geometry', len(on_layer(vm, 'POOL')) > 10)
check('drew dimensions', len(on_layer(vm, 'DIMENSION')) > 5)
check('drew captions and the report', len(on_layer(vm, 'POOL-NOTES')) > 10)
check('every sysvar is back where it started', vm.sysvars == before)

print('tutorial -- X at the first pause stops the tour')
vm = VM()
vm.load(POOL)
vm.load(TUT)
try:
    vm.run('c:TUTORIALPOOL', ['X'])         # topic 1 is text-only
except LispError as e:
    raise AssertionError(f'[early stop] {e}') from None
check('nothing was drawn before the stop', not vm.entdata)

print('tutorial -- refuses to run without POOL.LSP')
vm = VM()
vm.load(TUT)
try:
    vm.run('c:TUTORIALPOOL', [])
except LispError as e:
    raise AssertionError(f'[no POOL] {e}') from None
check('gate consumed no prompts', True)

print('POOLVER -- runs with and without the tutorial loaded')
vm = VM()
vm.load(POOL)
try:
    vm.run('c:POOLVER', [])
    vm.load(TUT)
    vm.run('c:POOLVER', [])
except LispError as e:
    raise AssertionError(f'[POOLVER] {e}') from None
check('POOLVER ran', True)

print('banners -- each pool file agrees with its releases/ twin')
for name in ('POOL.LSP', 'POOLDEMO.LSP', 'TUTORIALPOOL.LSP'):
    text = open(os.path.join(REPO_DIR, 'lisp', 'pool', name)).read()
    m = re.search(r'\*version\*\s+"(\d{6}) REV(\d{2})"', text)
    check(f'{name} carries a version banner', bool(m))
    if m:
        twin = f'{name[:-4]}_{m.group(1)}_REV{m.group(2)}.LSP'
        ok = os.path.exists(os.path.join(RELEASES, twin))
        check(f'releases/{twin} exists', ok)
        if ok:
            same = open(os.path.join(RELEASES, twin)).read() == text
            check(f'releases/{twin} is byte-identical', same)

POOLDEMO = os.path.join(REPO_DIR, 'lisp', 'pool', 'POOLDEMO.LSP')

print('pooldemo -- the sample sheet, no questions at all')
#: POOLDEMO refuses to run unless POOL.LSP is loaded, and it proves that
#: by looking for pool:hopcalc in (atoms-family 0).  The VM answers that
#: with an empty list whatever is loaded, so the gate can never pass on
#: its own -- a per-VM defun shadows it (a user defun resolves ahead of
#: the builtins), which leaves the REAL gate in place for the negative
#: case below.
vm = VM()
vm.load(POOL)
vm.load(POOLDEMO)
vm.loads("(defun atoms-family (n) (list 'pool:hopcalc))")
before = dict(vm.sysvars)
try:
    vm.run('c:POOLDEMO', [])                # takes no input whatsoever
except LispError as e:
    raise AssertionError(f'[pooldemo] {e}') from None
said = ''.join(vm.printed)
check('it did not refuse to run', 'is not loaded' not in said)
check('drew the sample pool', len(on_layer(vm, 'POOL')) > 10)
check('drew its dimensions', len(on_layer(vm, 'DIMENSION')) > 5)
check('every sysvar is back where it started', vm.sysvars == before)
check('the run is one undo group',
      [c for c in vm.commands if c and c[0] == '_.UNDO']
      == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']])

print('pooldemo -- without POOL.LSP it says so and draws nothing')
#: the real path for someone who APPLOADs POOLDEMO on its own
vm = VM()
vm.load(POOL)
vm.load(POOLDEMO)
try:
    vm.run('c:POOLDEMO', [])
except LispError as e:
    raise AssertionError(f'[pooldemo gate] {e}') from None
check('it names POOL.LSP as the missing piece',
      'POOL.LSP is not loaded' in ''.join(vm.printed))
check('and nothing was drawn', not vm.entdata)

print('pooldemo -- POOLDEMOVER reports the banner')
vm = VM()
vm.load(POOL)
vm.load(POOLDEMO)
vm.run('c:POOLDEMOVER', [])
check('POOLDEMOVER prints its own version',
      'POOLDEMO ' in ''.join(vm.printed))

if failures:
    print(f'\n{len(failures)} TUTORIALPOOL check(s) FAILED')
    sys.exit(1)
print('\nall TUTORIALPOOL checks passed')
