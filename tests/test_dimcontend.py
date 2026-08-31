"""Runtime tests: load the real dim_continue.lsp into the AutoLISP VM
and drive c:DIMCONTEND with scripted answers.

The VM does not model DIMCONTINUE itself (the call is logged, nothing
is drawn), so these scenarios pin the command's FLOW: the seed pick and
its validation, the undo group around each chain, the repeat question,
and that the user's dimension style survives the run even though the
chain is drawn in the seed's style.  Run:

    python3 tests/test_dimcontend.py
    CALOFIN_LISP_ROOT=shared python3 tests/test_dimcontend.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'dim_continue', 'dim_continue.lsp')

#: builds one seed dimension (in SEED STYLE, ext-line origins (0,0) and
#: (10,0)) and one LINE lying wholly beyond the seed's far origin
SEED = '''
(defun c:T-SEED ()
  (command "_.-DIMSTYLE" "_Restore" "SEED STYLE")
  (command "_.DIMLINEAR" (list 0.0 0.0) (list 10.0 0.0) (list 5.0 -2.0))
  (entmake (list '(0 . "LINE") '(8 . "0")
                 (cons 10 (list 20.0 0.0 0.0))
                 (cons 11 (list 30.0 0.0 0.0))))
  (princ))
'''


def newvm():
    vm = VM()
    vm.load(LSP)                        # CALOFIN_LISP_ROOT picks the tier
    vm.tables['LAYER'].add('0')
    vm.tables['DIMSTYLE'].add('SEED STYLE')
    vm.loads(SEED)
    vm.run('c:T-SEED', [])
    # the operator's own current style, distinct from the seed's
    vm.sysvars['DIMSTYLE'] = 'STANDARD'
    return vm


def ent_of(vm, dxf0):
    for e in vm.entities:
        for g in vm.entdata[e]:
            if isinstance(g, Dot) and g.a == 0 and g.b == dxf0:
                return e
    raise AssertionError('no %s entity in the drawing' % dxf0)


def run(vm, script, label):
    try:
        vm.run('c:DIMCONTEND', list(script))
    except LispError as e:
        raise AssertionError('[%s] %s' % (label, e)) from None
    return vm


def test_one_chain():
    vm = newvm()
    seed, line = ent_of(vm, 'DIMENSION'), ent_of(vm, 'LINE')
    run(vm, [seed, [line], None], 'one chain')
    names = [c[0] for c in vm.commands]
    # the chain sits inside one undo group
    i_beg = names.index('_.UNDO')
    i_dc = names.index('._DIMCONTINUE')
    i_end = len(names) - 1 - names[::-1].index('_.UNDO')
    assert vm.commands[i_beg] == ['_.UNDO', '_Begin'], vm.commands[i_beg]
    assert vm.commands[i_end] == ['_.UNDO', '_End'], vm.commands[i_end]
    assert i_beg < i_dc < i_end, (i_beg, i_dc, i_end)
    # both LINE endpoints (beyond the seed) were fed to DIMCONTINUE
    chain = vm.commands[i_dc + 1:i_end]
    assert [[20.0, 0.0, 0.0]] in chain and [[30.0, 0.0, 0.0]] in chain, chain
    # the chain was drawn in the seed's style, the user's came back
    assert 'SEED STYLE' in vm.dimstyle_log, vm.dimstyle_log
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars['DIMSTYLE']
    # the repeat question was asked once, with the standard shape
    q = [p for p, _ in vm.prompts if p.startswith('\nContinue from')]
    assert q == ['\nContinue from another dimension? [Yes/No] <No>: '], q
    print('one chain: undo group, seed style, restore, repeat ask - ok')


def test_yes_loops_again():
    vm = newvm()
    seed, line = ent_of(vm, 'DIMENSION'), ent_of(vm, 'LINE')
    # first pass draws, Yes re-enters, Enter at the seed pick quits
    run(vm, [seed, [line], 'Yes', None], 'yes loop')
    picks = [p for p, _ in vm.prompts
             if p.startswith('\nSelect the dimension')]
    assert len(picks) == 2, picks
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars['DIMSTYLE']
    print('yes loop: second seed pick offered, style still restored - ok')


def test_enter_quits_in_one_keystroke():
    vm = newvm()
    run(vm, [None], 'enter quits')
    # no chain, no undo group, no repeat question
    assert ['_.UNDO', '_Begin'] not in vm.commands, vm.commands
    assert not any(p.startswith('\nContinue from') for p, _ in vm.prompts)
    assert vm.sysvars['DIMSTYLE'] == 'STANDARD', vm.sysvars['DIMSTYLE']
    print('enter at the seed pick: one keystroke, nothing touched - ok')


if __name__ == '__main__':
    test_one_chain()
    test_yes_loops_again()
    test_enter_quits_in_one_keystroke()
    print('all tests passed')
