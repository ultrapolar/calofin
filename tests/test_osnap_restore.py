"""OSMODE comes back when a run dies PAST the point that muted it.

tests/test_cancel_paths.py Escs every headline command at its first
prompt, and asserts the settings read afterwards as they did before.
That is the cheapest cancel there is, and it is deliberately the one
the handler is least likely to get wrong -- at the first prompt most
commands have not muted anything yet, so a handler that restores
nothing still passes.

The failure this file is about is the other one: the drafter answers a
few questions, the run mutes OSMODE for a (command ...) of its own, and
THEN something throws.  That is the path where a restore living only at
the bottom of the command never runs, and where a value saved in a
helper's own local is out of the handler's reach however carefully the
helper puts it back inline.  Three commands were in that state --
TUTORIALCOVERCHECK, TUTORIALDIMCHECK and TUTORIALLINFINCHECK, each
muting OSMODE round a DIMLINEAR inside a tut-build/tut-dim helper --
and they are the three driven here.

The break is injected where the real one would be: the demo helper is
redefined to mute OSMODE the way the real one does and then fail,
which is what an AutoCAD that rejects the DIMLINEAR does.  What is
asserted is only what the drafter sees afterwards: the handler ran,
and their object snaps read exactly as they did before the command.

tools/check_osnap.py is the static half of the same rule, over all 43
commands that move OSMODE; this is the half that executes.

Run: python3 tests/test_osnap_restore.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_osnap_restore.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

#: a running-osnap setting a drafter would recognise: endpoint,
#: midpoint, center, intersection.  Any non-zero value would do; a
#: realistic one makes a failure read as what it is.
OSMODE = 175

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


#: one row per command: where it lives, the helper that does the
#: muting WITH ITS REAL ARGLIST, and the answers that get the run as
#: far as that helper.  The arglist matters -- a stub of the wrong
#: shape fails on arity at the call, BEFORE it has muted anything, and
#: the row then passes without testing a thing.
CASES = [
    ("TUTORIALCOVERCHECK", "lisp/covercheck/covercheck.lsp",
     "cchk:tut-build", "bp", ["Yes", [0.0, 0.0, 0.0]]),
    ("TUTORIALDIMCHECK", "lisp/dimcheck/dimcheck.lsp",
     "dchk:tut-demo", "", ["Demo"]),
    ("TUTORIALLINFINCHECK", "lisp/linfincheck/linfincheck.lsp",
     "lfc:tut-demo", "", ["Demo"]),
]

#: the break: a call to nothing, which is what the VM raises on and
#: what an AutoCAD that rejects the DIMLINEAR amounts to here
BREAK = "calofin--the-injected-failure"


def broken(helper, args):
    """The demo helper, muting OSMODE exactly as the real one does and
    then dying where its DIMLINEAR would."""
    return '(defun %s (%s / ) (setvar "OSMODE" 0) (%s))' % (helper, args, BREAK)


print("a run that dies after muting OSMODE still gives it back")
for cmd, path, helper, args, answers in CASES:
    vm = VM()
    vm.load(os.path.join(ROOT, path))
    vm.handle_errors = True
    vm.sysvars["OSMODE"] = OSMODE
    vm.loads(broken(helper, args))
    try:
        vm.run("c:" + cmd, list(answers))
    except LispError as e:
        check("%s: the failure went through the handler" % cmd, False,
              str(e).splitlines()[0])
        continue
    # the INJECTED failure, and no other: an arity or answer mismatch
    # would stop the run before the mute and pass this file for nothing
    check("%s: the run reached the injected failure" % cmd,
          vm.handled_errors == ["undefined function: " + BREAK],
          repr(vm.handled_errors))
    check("%s: object snaps read as they did before the run" % cmd,
          vm.sysvars.get("OSMODE") == OSMODE,
          "OSMODE is %r, not %r" % (vm.sysvars.get("OSMODE"), OSMODE))

# The other half of the complaint.  "My snaps got cleared" is what a
# drafter says when snaps are off where they expect them ON, too -- and
# SPA's base point, the one pick that places the whole spa, was made
# that way.  spa:readblock runs before SPA's three opening questions and
# ends on spa:osdown like every ask helper here, so snaps were already
# at 0 by the time the base-point prompt came up, thirty lines before
# the (setvar "OSMODE" 0) that was supposed to be what dropped them.
# The comment at that prompt has always said the pick is made with the
# drafter's own snaps live; the spa:osup that makes it true is new.
print("snaps are live again at the pick that places the spa")
vm = VM()
vm.load(os.path.join(ROOT, "lisp/spa/SPA.LSP"))
vm.sysvars["OSMODE"] = OSMODE
vm.loads('(defun entsel (m) nil)')            # Enter, skipping the block
# the grouped twin is mirrored onto the library, so the snapshot pair is
# spa:* in lisp/ and cal:* in shared/ -- ask the VM which one it loaded
vm.loads('''(if spa:syssave
              (spa:syssave)
              (cal:syssave (list "OSMODE" "LUNITS" "CMDECHO" "CLAYER")))''')
vm.loads('(spa:readblock)')
check("spa:readblock leaves snaps down, as every ask helper here does",
      vm.sysvars.get("OSMODE") == 0, "OSMODE is %r" % vm.sysvars.get("OSMODE"))
vm.loads('(if spa:osup (spa:osup) (cal:osup))')
check("spa:osup gives them back for the base-point pick",
      vm.sysvars.get("OSMODE") == OSMODE,
      "OSMODE is %r, not %r" % (vm.sysvars.get("OSMODE"), OSMODE))

# The test lies if the injected break never reached the mute: a command
# whose answers stopped short would "pass" with OSMODE untouched.  So
# prove the same harness SEES a handler that does not restore.
print("the harness would catch a handler that did not restore")
vm = VM()
vm.loads('''
  (defun bad:draw () (setvar "OSMODE" 0) (bad--no-such-call))
  (defun c:BADTUTORIAL ( / *error* oos)
    (defun *error* (msg) (princ))
    (setq oos (getvar "OSMODE"))
    (bad:draw)
    (setvar "OSMODE" oos)
    (princ))
''')
vm.handle_errors = True
vm.sysvars["OSMODE"] = OSMODE
try:
    vm.run("c:BADTUTORIAL", [])
    check("a handler that restores nothing leaves OSMODE at 0",
          vm.sysvars.get("OSMODE") == 0,
          "OSMODE is %r" % (vm.sysvars.get("OSMODE"),))
except LispError as e:
    check("a handler that restores nothing leaves OSMODE at 0", False,
          str(e).splitlines()[0])

if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL OSNAP-RESTORE CHECKS PASSED (%d commands, plus SPA's base point)"
      % len(CASES))
