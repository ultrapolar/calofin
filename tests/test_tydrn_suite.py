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

  * THAT ONE HIGHLIGHT REACHES EVERY STAGE.  All three calofin stages
    want the same trace picked, and AutoCAD clears the pickfirst set the
    moment a command consumes it -- so run by hand the trace is
    highlighted three times.  The suite reads it once and puts it back
    before each stage, grows it by what each stage draws (AUTODIM is
    meant to dimension the pads PADDLE just dropped), and hands CDIM a
    cleared one, because the dimensions it tidies are in nobody's
    original pick.

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

;; A trace already in the drawing and already highlighted, which is how
;; the command is normally reached.  Every set the suite hands over is
;; recorded, in stage order, so what each stage OPENED WITH is what the
;; tests get to look at.
(setq *trace* (list (entmakex '((0 . "LINE") (10 0.0 0.0) (11 10.0 0.0)))
                    (entmakex '((0 . "LINE") (10 10.0 0.0) (11 10.0 8.0)))
                    (entmakex '((0 . "TEXT") (1 . "A") (10 1.0 1.0)))))
(setq *pre* (ssadd))
(foreach e *trace* (ssadd e *pre*))

(defun ssgetfirst () (list nil *pre*))
(defun sssetfirst (a b) (setq *handed* (cons b *handed*)) t)
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

#: The VM's (command ...) records rather than dispatching, which is what
#: the ordering tests read.  This replaces it with one that records AND
#: lets PADDLE draw -- a user defun shadows a builtin here -- because the
#: pad it drops is the whole point of the carried set growing: AUTODIM's
#: filter takes INSERTs so that it dimensions those pads, and handing it
#: the operator's original pick alone would hide every one of them.
DRAWING_STAGES = r'''
(defun vl-cmdf (nm)
  (setq *ran* (cons nm *ran*))
  (if (= nm "_.PADDLE")
    (setq *pad* (entmakex '((0 . "INSERT") (2 . "Pad36x36") (10 5.0 4.0)))))
  t)
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


def handed(vm):
    """The set each stage was handed, in stage order.  nil means the
    suite cleared the selection before that stage."""
    return list(reversed(vm.get(Sym('*handed*')) or []))


def test_one_highlight_reaches_every_calofin_stage():
    print("\nthe trace is picked once, not once per command")
    vm = run()
    h = handed(vm)
    check("a set was handed to each of the four stages", len(h) == 4)
    pre = vm.get(Sym('*trace*'))
    check("TYDRN opens with the operator's own pick",
          h[0] is not None and all(e in h[0] for e in pre))
    check("so does PADDLE -- not an empty selection it has to re-ask for",
          h[1] is not None and all(e in h[1] for e in pre))
    check("and so does AUTODIM",
          h[2] is not None and all(e in h[2] for e in pre))
    check("it says the pick is carried, so the operator knows not to redo it",
          "carried through every stage" in said(vm))


def test_cdim_is_handed_a_cleared_selection():
    print("\nCDIM tidies what AUTODIM just drew, which nobody picked")
    vm = run()
    h = handed(vm)
    # Typed by hand after AUTODIM there is nothing selected either, so
    # clearing is what keeps CDIM behaving the way its operator knows it.
    check("the finisher gets nil, not the trace", h[3] is None)
    vm = run(extra_setup='(setq *tydrn-finish-cmd* nil)')
    check("with no finisher there is no fourth handoff",
          len(handed(vm)) == 3)


def test_the_carried_set_grows_by_what_a_stage_draws():
    print("\nAUTODIM is given the pads PADDLE dropped, not just the trace")
    vm = run(stages=STAGES + DRAWING_STAGES)
    h = handed(vm)
    pad = vm.get(Sym('*pad*'))
    check("PADDLE drew a pad", pad is not None)
    check("PADDLE itself did not get it - it did not exist yet",
          pad not in (h[1] or []))
    # ad:geomfilter takes INSERTs for exactly this reason.  Hand AUTODIM
    # the operator's original pick alone and every pad is invisible to it.
    check("AUTODIM opens with the pad in its selection", pad in (h[2] or []))
    check("and still with the trace", all(e in h[2]
                                          for e in vm.get(Sym('*trace*'))))
    check("the stages still ran in order",
          [str(x).lstrip("_.") for x in reversed(vm.get(Sym('*ran*')))]
          == ["TYDRN", "PADDLE", "AUTODIM", "CDIM"])


def test_an_erased_entity_is_not_handed_on():
    print("\na stage is free to erase what it replaces")
    # A set holding an erased ename is not one AutoCAD will hand to the
    # next command, so the set is rebuilt from what survives each time
    # rather than kept.
    vm = run(stages=STAGES + r'''
(defun vl-cmdf (nm)
  (setq *ran* (cons nm *ran*))
  (if (= nm "_.TYDRN") (entdel (car *trace*)))
  t)
''')
    h = handed(vm)
    gone = vm.get(Sym('*trace*'))[0]
    check("TYDRN was handed it", gone in (h[0] or []))
    check("PADDLE is not - it is gone", gone not in (h[1] or []))
    check("but the rest of the trace still is",
          all(e in h[1] for e in vm.get(Sym('*trace*'))[1:]))


def test_nothing_highlighted_means_one_prompt_not_three():
    print("\nhighlight nothing and it asks once, up front")
    vm = VM()
    lispvm.BUILTINS[Sym('vl-cmdf')] = lispvm.BUILTINS[Sym('command')]
    vm.loads(STUBS)
    vm.load(LSP)
    vm.loads(STAGES)
    vm.loads('(defun ssgetfirst () (list nil nil))')
    # ONE answer is all the run is allowed: what the operator picks at
    # the suite's own prompt.  The VM raises on a second ask (script
    # exhausted) and on an answer left over, so getting here at all is
    # the assertion -- no stage may ask for the trace again, and the
    # suite may not ask twice itself.
    vm.run('c:TYLERDRONESUITE', [vm.get(Sym('*trace*'))])
    check("it asks for the trace itself", "Highlight the trace once"
          in said(vm))
    check("and says Enter leaves each stage to ask on its own",
          "let each stage ask on its own" in said(vm))
    h = list(reversed(vm.get(Sym('*handed*')) or []))
    check("what was picked there reaches every calofin stage",
          all(h[i] is not None
              and all(e in h[i] for e in vm.get(Sym('*trace*')))
              for i in (0, 1, 2)))
    check("exactly one answer was asked for and used",
          len(vm.prompts) == 1 and not vm.script)


def test_pickfirst_is_forced_on_and_put_back():
    print("\nPICKFIRST at 0 would let the handoff go quietly missing")
    # sssetfirst still highlights with PICKFIRST at 0, but ssget "_I"
    # reads nothing - the failure would be silent, which is the one
    # worth spending a sysvar to rule out.
    vm = run(stages=STAGES + r'''
(defun vl-cmdf (nm)
  (setq *ran* (cons nm *ran*)
        *seen* (cons (getvar "PICKFIRST") *seen*))
  t)
''')
    check("every stage ran with it on",
          [x for x in (vm.get(Sym('*seen*')) or [])] == [1, 1, 1, 1])
    check("and it is back to what it was afterwards",
          vm.sysvars.get('PICKFIRST') == 0)


def main():
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print("TYLERDRONESUITE runtime tests -- tier: %s" % tier)
    for fn in (test_the_stages_run_in_the_order_the_work_needs,
               test_cdim_is_reached_the_way_a_shop_command_has_to_be,
               test_the_finisher_can_be_retuned_or_turned_off,
               test_one_highlight_reaches_every_calofin_stage,
               test_cdim_is_handed_a_cleared_selection,
               test_the_carried_set_grows_by_what_a_stage_draws,
               test_an_erased_entity_is_not_handed_on,
               test_nothing_highlighted_means_one_prompt_not_three,
               test_pickfirst_is_forced_on_and_put_back,
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
