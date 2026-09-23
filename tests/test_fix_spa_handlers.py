#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""SPA, TUTORIALSPA and OASIS clean up on an Esc with the stack UNWOUND.

All three push the error mode (*push-error-using-command*) so their
handlers may drive a command -- the UNDO close, OASIS's CMDACTIVE
drain.  Under that mode AutoCAD resets the evaluator BEFORE *error*
runs: the handler function is the one in force at the failure, but
every binding the command made is gone, and a local of the command
reads its GLOBAL value (nil) there.  The stock VM ran every handler
with every frame live, which is why these three passed their own
cancel tests while, in AutoCAD:

  * SPA and TUTORIALSPA left the drafter's undo group open on every Esc
    -- the flag that said one was open was a local of the command;
  * OASIS left its half-drawn preview on the drawing (part of it on the
    real POOL layer, where it looks like work) and its undo group open
    -- both were locals.

tests/lispvm.py models the unwind itself now (tests/test_lispvm_errmode.py
pins it; this file used to install the audit's vmpatch.py model), so
each test drives the command to a point where the handler has real work
and checks the work got done.

Run: python3 tests/test_fix_spa_handlers.py
"""

import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
from lispvm import VM, LispError, Sym, NIL  # noqa: E402
import test_oasis  # noqa: E402  (its newvm/script/made, and entmakex)

SPA = os.path.join(REPO_DIR, 'lisp', 'spa', 'SPA.LSP')
TUT = os.path.join(REPO_DIR, 'lisp', 'spa', 'TUTORIALSPA.LSP')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def esc(vm):
    raise LispError('Function cancelled', vm)


def drive(vm, cmd, script):
    """Run CMD; the first line of any error, or None."""
    try:
        vm.run(cmd, list(script))
    except LispError as e:
        return str(e).splitlines()[0]
    return None


def undos(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def test_the_model_unwinds():
    """The VM's model: a pushed handler reads the command's local as
    nil, a default-mode one still sees it (tests/test_lispvm_errmode.py
    pins the rest)."""
    src = '''
      (defun c:T1 ( / *error* flag)
        (defun *error* (msg) (setq t1:*saw* flag) (princ))
        %s
        (setq flag T)
        (getpoint "\\nPick: "))'''
    for label, push, want in (
            ("pushed: the local is gone", "(*push-error-using-command*)",
             None),
            ("default: the local is live", "", True)):
        vm = VM()
        vm.handle_errors = True
        vm.loads(src % push)
        try:
            vm.run('c:T1', [esc])
        except LispError:
            pass        # the pushed case leaves the mode pushed
        got = vm.globals.get(Sym('t1:*saw*'))
        check("model -- " + label,
              (got not in (None, NIL)) == bool(want), repr(got))


def test_spa_esc_closes_its_undo_group():
    """test_handler_error_mode's drive: Enter at the block, Coversize,
    Rectangle, Enter at the base point, 80 for the width, then Esc at
    the length with the guide up and the group open."""
    vm = VM()
    vm.load(SPA)
    vm.handle_errors = True
    err = drive(vm, 'c:SPA', [None, 'C', 'R', None, 80.0, esc])
    check("SPA -- the run comes back clean", err is None, err)
    check("SPA -- the handler ran", vm.handled_errors ==
          ['Function cancelled'], vm.handled_errors)
    check("SPA -- the undo group it opened is closed",
          vm.undo_groups == 0 and undos(vm) == ['_Begin', '_End'],
          (vm.undo_groups, undos(vm)))
    check("SPA -- the error mode is popped", vm.error_mode_depth == 0,
          vm.error_mode_depth)
    check("SPA -- no flag left standing",
          not vm.globals.get(Sym('spa:*undo-open*')))


def test_spa_stale_flag_closes_nothing():
    """A flag an earlier run left standing is reset before the push: in
    a drawing with undo off this run opens no group, so its handler must
    close none -- an _End there closes someone else's group."""
    vm = VM()
    vm.load(SPA)
    vm.handle_errors = True
    vm.sysvars['UNDOCTL'] = 4                   # undo not recording
    vm.loads('(setq spa:*undo-open* T tut:*undo-open* T)')
    err = drive(vm, 'c:SPA', [None, 'C', 'R', None, 80.0, esc])
    check("SPA stale flag -- the run comes back clean", err is None, err)
    check("SPA stale flag -- no UNDO issued at all", undos(vm) == [],
          undos(vm))


def test_tutorialspa_esc_in_the_demo_closes_its_undo_group():
    """Demo, a spot for it, then Esc at the first pause -- inside the
    tutorial's undo group."""
    vm = VM()
    vm.load(SPA)
    vm.load(TUT)
    vm.handle_errors = True
    err = drive(vm, 'c:TUTORIALSPA', ['Demo', (0.0, 0.0), esc])
    check("TUTORIALSPA -- the run comes back clean", err is None, err)
    check("TUTORIALSPA -- the handler ran", vm.handled_errors ==
          ['Function cancelled'], vm.handled_errors)
    check("TUTORIALSPA -- the undo group it opened is closed",
          vm.undo_groups == 0 and undos(vm) == ['_Begin', '_End'],
          (vm.undo_groups, undos(vm)))
    check("TUTORIALSPA -- the error mode is popped",
          vm.error_mode_depth == 0, vm.error_mode_depth)


def test_tutorialspa_stale_flag_closes_nothing():
    vm = VM()
    vm.load(SPA)
    vm.load(TUT)
    vm.handle_errors = True
    vm.sysvars['UNDOCTL'] = 4
    vm.loads('(setq spa:*undo-open* T tut:*undo-open* T)')
    err = drive(vm, 'c:TUTORIALSPA', ['Demo', (0.0, 0.0), esc])
    check("TUTORIALSPA stale flag -- the run comes back clean",
          err is None, err)
    check("TUTORIALSPA stale flag -- no UNDO issued", undos(vm) == [],
          undos(vm))


def test_oasis_esc_takes_the_preview_and_closes_the_group():
    """test_oasis's canonical run, cut to an Esc at the right bulge --
    the preview is up with every circle answered so far."""
    vm = test_oasis.newvm()
    vm.handle_errors = True
    head = test_oasis.script()[:7]      # shape, detail, base, X Y L T
    err = drive(vm, 'c:OASIS', head + [esc])
    asked = vm.lastprompt or ''         # the prompt the Esc answered
    check("OASIS -- the Esc landed on the right bulge",
          'right' in asked.lower(), asked)
    check("OASIS -- the run comes back clean", err is None, err)
    check("OASIS -- the handler ran", vm.handled_errors ==
          ['Function cancelled'], vm.handled_errors)
    left = [d for d in (test_oasis.made(vm, t) for t in
                        ('ARC', 'CIRCLE', 'LINE', 'TEXT', 'LWPOLYLINE'))
            for d in d if d.get(8) in ('POOL', 'POOL-GUIDE')]
    check("OASIS -- nothing of the preview is left on the drawing",
          not left, "%d left: %s" % (len(left), sorted(
              {(d.get(0), d.get(8)) for d in left})))
    check("OASIS -- the undo group it opened is closed",
          vm.undo_groups == 0 and undos(vm) == ['_Begin', '_End'],
          (vm.undo_groups, undos(vm)))
    check("OASIS -- no preview or flag left standing",
          not vm.globals.get(Sym('oasis:*prev*'))
          and not vm.globals.get(Sym('oasis:*undo-open*')))


def test_oasis_stale_flag_closes_nothing():
    vm = test_oasis.newvm()
    vm.handle_errors = True
    vm.sysvars['UNDOCTL'] = 4
    vm.loads('(setq oasis:*undo-open* T)')
    err = drive(vm, 'c:OASIS', test_oasis.script()[:7] + [esc])
    check("OASIS stale flag -- the run comes back clean", err is None, err)
    check("OASIS stale flag -- no UNDO issued", undos(vm) == [], undos(vm))


TESTS = [test_the_model_unwinds,
         test_spa_esc_closes_its_undo_group,
         test_spa_stale_flag_closes_nothing,
         test_tutorialspa_esc_in_the_demo_closes_its_undo_group,
         test_tutorialspa_stale_flag_closes_nothing,
         test_oasis_esc_takes_the_preview_and_closes_the_group,
         test_oasis_stale_flag_closes_nothing]


def main():
    for t in TESTS:
        print(t.__name__)
        t()
    if FAILS:
        print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
        return 1
    print("\nALL PUSHED-HANDLER CHECKS PASSED")
    return 0


if __name__ == '__main__':
    sys.exit(main())
