#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for TYLERDRONESUITE -- TYDRN, PADDLE, AUTODIM, CDIM.

The suite adds no drawing logic of its own: every stage is the command
itself, asking its own questions.  So what is worth testing is the
ordering and the refusals, which is all it contributes:

  * THE ORDER, and that it is the order the work needs.  The points have
    to be on the right layer before PADDLE looks for features to pad,
    the pads have to be in before AUTODIM dimensions what is there, and
    CDIM tidies the dimensions AUTODIM just made.

  * CDIM IS NOT OURS, and is treated accordingly: it is not pre-checked
    (boundp sees only what AutoLISP defined, and an in-house command is
    as likely to be .NET, ARX or a PGP alias) and it is called WITHOUT
    the "." prefix, which would mean "the built-in of this name" and
    reach past the very redefinition we want.

  * THAT IT CHECKS BEFORE IT STARTS.  Half a suite is worse than none:
    TYDRN would have moved the points and PADDLE dropped the pads, and
    the operator would learn only at the end that the dimensioning they
    ran it for was never going to happen.  A missing stage is named, and
    nothing runs.

  * THAT IT DOES NOT WRAP THE STAGES IN ONE UNDO GROUP.  One U per
    stage backs the suite out, so a stage that went well is not undone
    to get at one that did not.

Usage:  python3 tests/test_tydrn_suite.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_tydrn_suite.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, LispError, Sym  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
LSP = os.path.join(REPO, 'lisp', 'tydrn', 'tydrn.lsp')

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


#: tydrn.lsp is an ActiveX file end to end; the suite touches none of
#: that, so the document object is all that has to exist for it to load.
STUBS = r'''
(defun vlax-get-acad-object () "ACAD")
(defun vla-get-activedocument (a) "DOC")
(defun vla-startundomark (d) (setq *undo* (cons "start" *undo*)) t)
(defun vla-endundomark (d) (setq *undo* (cons "end" *undo*)) t)
'''

#: PADDLE and AUTODIM live in other files, so the suite has to find
#: them at run time.  Defining them empty here is enough: the VM's
#: (command ...) RECORDS a command rather than dispatching to a c:
#: function, so what the run leaves behind to assert on is the command
#: log, and these only have to exist for the boundp check to pass.
STAGES = r'''
(defun c:PADDLE () (princ))
(defun c:AUTODIM () (princ))
'''


def run(stages=STAGES, extra_setup=None):
    vm = VM()
    # vl-cmdf is how the suite invokes each stage -- XYPLOT's idiom for
    # handing off to another tool, so a stage prompts and errors exactly
    # as it does when it is typed
    lispvm.BUILTINS[Sym('vl-cmdf')] = lispvm.BUILTINS[Sym('command')]
    vm.loads(STUBS)
    vm.load(LSP)
    vm.loads(stages)          # after the file, so c:TYDRN is the stub
    if extra_setup:
        vm.loads(extra_setup)
    vm.run('c:TYLERDRONESUITE', [])
    return vm


def said(vm):
    return "".join(str(x) for x in vm.printed)


def ran(vm):
    """The stages the suite actually issued, in order."""
    return [str(c[0]).lstrip("_.") for c in vm.commands if c]


def test_the_stages_run_in_the_order_the_work_needs():
    print("\nTYDRN, PADDLE, AUTODIM, then CDIM -- in that order")
    vm = run()
    check("all four ran",
          ran(vm) == ["TYDRN", "PADDLE", "AUTODIM", "CDIM"])
    check("each went through the command line, not a direct call",
          ["_.TYDRN"] in vm.commands and ["_.PADDLE"] in vm.commands
          and ["_.AUTODIM"] in vm.commands)
    check("it says which stage is which as it goes",
          "1 of 4: TYDRN" in said(vm)
          and "3 of 4: AUTODIM" in said(vm)
          and "4 of 4: CDIM" in said(vm))
    check("and says so when it is through", "all 4 stages ran"
          in said(vm))


def test_cdim_is_reached_the_way_a_shop_command_has_to_be():
    print("\nCDIM is not ours, and is called as though it is not")
    vm = run()
    # "_." means the BUILT-IN command of this name, whatever anyone has
    # redefined.  A shop command is exactly that redefinition, so the
    # dot would reach straight past it.
    check("CDIM goes through _ without the dot", ["_CDIM"] in vm.commands)
    check("and calofin's own still go through _.",
          ["_.TYDRN"] in vm.commands and ["_.CDIM"] not in vm.commands)
    # it is NOT pre-checked: boundp sees only what AutoLISP defined, and
    # an in-house command is as likely to be .NET, ARX or a PGP alias.
    # Refusing to run over a check that cannot see it would be worse
    # than the failure it guards against.
    check("it is not in the pre-flight list",
          "CDIM" not in [str(x) for x in (vm.get(Sym('*tydrn-suite*')) or [])])
    check("but it IS in the stages that run",
          "CDIM" in [str(x) for x in (vm.get(Sym('*tydrn-finish-cmd*'))
                                      and vm.get(Sym('*tydrn-suite*')) or [])]
          or ran(vm)[-1] == "CDIM")


def test_the_finisher_can_be_retuned_or_turned_off():
    print("\na shop without CDIM, or with another name for it")
    vm = run(extra_setup='(setq *tydrn-finish-cmd* nil)')
    check("nil runs the three and stops",
          ran(vm) == ["TYDRN", "PADDLE", "AUTODIM"])
    check("and the counting follows it", "1 of 3: TYDRN" in said(vm)
          and "all 3 stages ran" in said(vm))
    vm = run(extra_setup='(setq *tydrn-finish-cmd* "DIMFIX")')
    check("another name is run instead",
          ran(vm) == ["TYDRN", "PADDLE", "AUTODIM", "DIMFIX"])
    check("still without the dot", ["_DIMFIX"] in vm.commands)


def test_a_missing_stage_is_named_and_nothing_runs():
    print("\na stage that is not loaded stops it before it starts")
    # TYDRN is not in this list: it is defined by the very file the
    # suite lives in, so it cannot be the missing one.  PADDLE and
    # AUTODIM are the two that really can be absent.
    for drop in ("PADDLE", "AUTODIM"):
        stages = "\n".join(l for l in STAGES.strip().split("\n")
                           if ("c:" + drop + " ") not in l)
        vm = run(stages)
        out = said(vm)
        check("%s missing: it is named" % drop,
              ("needs " + drop) in out or (" and " + drop) in out
              or (", and " + drop) in out)
        check("%s missing: nothing ran at all" % drop, ran(vm) == [])
        check("%s missing: it says nothing was changed" % drop,
              "Nothing has been" in out)


def test_two_missing_stages_read_as_a_sentence():
    print("\ntwo missing stages are named as a list, not a dump")
    vm = run("")          # neither PADDLE nor AUTODIM loaded
    check("both named, joined with and",
          "PADDLE and AUTODIM" in said(vm))
    check("and the verb agrees", "which are not loaded" in said(vm))
    # one missing takes the singular
    check("one missing takes the singular",
          "which is not loaded"
          in said(run("(defun c:PADDLE () (princ))")))


def test_the_suite_opens_no_undo_group_of_its_own():
    print("\nthree U's back it out, one per stage -- not one for the lot")
    vm = run()
    # the stages are stubs here, so any undo mark seen would be the
    # suite's own.  It must not open one: nesting a group around three
    # commands that each open their own is what would make the whole
    # suite a single U, and a good stage undone with a bad one.
    check("no undo mark opened by the suite",
          not (vm.get(Sym('*undo*')) or []))
    check("and it tells the operator that is how it works",
          "own undo group" in said(vm))


def test_the_stage_list_is_what_drives_it():
    print("\nthe order lives in one list, not spelled out three times")
    vm = run()
    stages = [str(x) for x in (vm.get(Sym('*tydrn-suite*')) or [])]
    check("*tydrn-suite* names the three stages in order",
          stages == ["TYDRN", "PADDLE", "AUTODIM"])
    check("and the count in the messages comes off it, finisher included",
          ("of " + str(len(stages) + 1) + ": TYDRN") in said(vm))


def main():
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print("TYLERDRONESUITE runtime tests -- tier: %s" % tier)
    for fn in (test_the_stages_run_in_the_order_the_work_needs,
               test_cdim_is_reached_the_way_a_shop_command_has_to_be,
               test_the_finisher_can_be_retuned_or_turned_off,
               test_a_missing_stage_is_named_and_nothing_runs,
               test_two_missing_stages_read_as_a_sentence,
               test_the_suite_opens_no_undo_group_of_its_own,
               test_the_stage_list_is_what_drives_it):
        try:
            fn()
        except LispError as e:
            check("%s raised: %s" % (fn.__name__, e), False)

    print("\n%d check(s) failed" % len(failures) if failures
          else "\nall checks passed")
    for f in failures:
        print("  - " + f)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
