#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""SPA, TUTORIALSPA and OASIS clean up on an Esc with the stack UNWOUND.

All three push the error mode (*push-error-using-command*) so their
handlers may drive a command -- the UNDO close, OASIS's CMDACTIVE
drain.  Under that mode AutoCAD resets the evaluator BEFORE *error*
runs: the handler function is the one in force at the failure, but
every binding the command made is gone, and a local of the command
reads its GLOBAL value (nil) there.  The stock VM runs every handler
with every frame live, which is why these three passed their own
cancel tests while, in AutoCAD:

  * SPA and TUTORIALSPA left the drafter's undo group open on every Esc
    -- the flag that said one was open was a local of the command;
  * OASIS left its half-drawn preview on the drawing (part of it on the
    real POOL layer, where it looks like work) and its undo group open
    -- both were locals.

pushed_unwind() below models the unwind for the length of a with-block
(the same model as the audit's vmpatch.py prototype), so each test
drives the command to a point where the handler has real work and
checks the work got done.

Run: python3 tests/test_fix_spa_handlers.py
"""

import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
import lispvm  # noqa: E402
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


class HandlerDeath(LispError):
    """The handler itself threw: what the drafter sees is a raw error
    line and no report."""


class pushed_unwind(object):
    """AutoCAD's pushed-mode unwind, for the length of a with-block.

    While the error mode is pushed, the handler is looked up with the
    stack live (it is the one in force at the failure) and then CALLED
    with the stack emptied, so it sees globals only.  In default mode
    nothing changes: the stack stays live, as AutoCAD keeps it."""

    def __enter__(self):
        self.saved = VM.call_defun

        def call_defun(self_, name, fn, args):
            _, params, locals_, body = fn
            if len(args) != len(params):
                raise LispError(f"{name}: expected {len(params)} args, "
                                f"got {len(args)}", self_)
            frame = dict(zip(params, args))
            for l in locals_:
                frame[l] = NIL
            self_.stack.append(frame)
            self_.calls.append(name)
            try:
                r = NIL
                for form in body:
                    r = self_.eval(form)
                return r
            except LispError as e:
                if (self_.handle_errors and not self_._catch_depth
                        and not self_._in_handler
                        and not getattr(e, 'handled', False)):
                    h = self_.get(Sym('*error*'))    # BEFORE the unwind
                    if (isinstance(h, tuple) and h[0] == 'defun') or (
                            isinstance(h, list) and h and h[0] == 'lambda'):
                        e.handled = True
                        msg = str(e).split('\n')[0]
                        self_.handled_errors.append(msg)
                        self_._in_handler = True
                        unwind = self_.error_mode_depth > 0
                        live = self_.stack
                        if unwind:
                            self_.stack = []
                        try:
                            if isinstance(h, tuple):
                                self_.call_defun(Sym('*error*'), h, [msg])
                            else:
                                self_.call_lambda(h, [msg])
                        except LispError as inner:
                            if isinstance(inner, lispvm.HandlerAbort):
                                raise
                            raise HandlerDeath(
                                "*error* handler died: %s"
                                % str(inner).splitlines()[0], self_)
                        finally:
                            if unwind:
                                self_.stack = live
                            self_._in_handler = False
                raise
            finally:
                self_.stack.pop()
                self_.calls.pop()

        VM.call_defun = call_defun
        return self

    def __exit__(self, *exc):
        VM.call_defun = self.saved
        return False


def drive(vm, cmd, script):
    """Run CMD under the unwind; the first line of any error, or None."""
    try:
        with pushed_unwind():
            vm.run(cmd, list(script))
    except LispError as e:
        return str(e).splitlines()[0]
    return None


def undos(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def test_the_model_unwinds():
    """The model itself: a pushed handler reads the command's local as
    nil, a default-mode one still sees it."""
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
        with pushed_unwind():
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
