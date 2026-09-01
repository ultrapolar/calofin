"""Runtime tests for AUTOBEAD: the first time the command runs under
test at all.  The VM does not model OFFSET, PEDIT or vla-Copy, so a run
cannot bead anything -- and that is the path this file is about: the
run that finds nothing to do, and the run that dies, both have to put
the drawing's settings back, close the undo group they opened, and take
the error mode they pushed back off the stack.

autobead-build pushes AutoCAD's error mode so its handler may drain a
pending command with (command).  Until v1.4 it popped that mode only
from the handler: every CLEAN run left it stacked for the rest of the
session, and a stacked mode refuses command-s inside every later
handler -- the next tool's Esc then left its undo group open without
a word.  The three step routines call autobead-build too, so one bead
pass early in the day was enough.

Script values answer the interactive calls in order: None is Enter at
the pickfirst probe, a list of entities answers the selection, a tuple
is a click, strings answer keywords.

Run: python3 tests/test_autobead.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_autobead.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, LispError  # noqa: E402

HERE = os.path.dirname(__file__)
LSP = os.path.join(HERE, '..', 'lisp', 'autobead', 'AUTOBEAD.lsp')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


LAYER_POOL = '''
  (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                 '(100 . "AcDbLayerTableRecord")
                 '(2 . "POOL") '(70 . 0) '(62 . 4)
                 '(6 . "Continuous")))'''

WALL = '''
  (entmake (list '(0 . "LINE") '(8 . "POOL")
                 '(10 0.0 0.0 0.0) '(11 240.0 0.0 0.0)))'''


def fresh():
    vm = VM()
    vm.load(LSP)
    vm.loads(LAYER_POOL)
    vm.loads(WALL)
    vm.wall = [e for e in vm.entities if e not in vm.deleted][-1]
    vm.sysvars['OSMODE'] = 4133
    vm.sysvars['CMDECHO'] = 1
    vm.sysvars['PEDITACCEPT'] = 0
    return vm


def undo_pairs(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def settings_back(vm):
    return (vm.sysvars['OSMODE'] == 4133 and vm.sysvars['CMDECHO'] == 1
            and vm.sysvars['PEDITACCEPT'] == 0)


# ----------------------------------------------------------------------
print("statics")
SRC = open(LSP, encoding='ascii').read()
m = re.search(r'\*autobead-version\*\s+"v(\d+)\.(\d+)"', SRC)
check("version banner present", m is not None)
build = SRC[SRC.index('(defun autobead-build'):SRC.index('(defun c:AUTOBEAD')]
handler = build[build.index('(defun *error*'):]
handler = handler[:handler.index('(if *push-error-using-command*')]
check("the build pushes the error mode once",
      build.count('(*push-error-using-command*)') == 1)
check("...and pops it outside the handler as well as inside it",
      handler.count('(*pop-error-mode*)') == 1
      and build.count('(*pop-error-mode*)') == 2, str(build.count('(*pop-error-mode*)')))

# ----------------------------------------------------------------------
print("a run that finds nothing to bead still puts everything back")
vm = fresh()
vm.run('c:AUTOBEAD', [None, [vm.wall], (0.0, 24.0, 0.0), "No"])
check("the copies could not be made here, and the run said so", any(
    'Could not copy the selection' in s for s in vm.printed), repr(vm.printed[-3:]))
check("one undo group, opened and closed", undo_pairs(vm) == ['_Begin', '_End'],
      repr(undo_pairs(vm)))
check("OSMODE, CMDECHO and PEDITACCEPT are back", settings_back(vm),
      repr(vm.sysvars))
check("the error mode is back off the stack",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0,
      repr((vm.error_mode_depth, vm.error_mode_underflow)))
check("the Bead Track layer was created on the way",
      'Bead Track' in vm.tables['LAYER'])

# ----------------------------------------------------------------------
print("a run that dies mid-build goes through its own handler")
vm = fresh()
vm.handle_errors = True
# the in-place copy blows up after the push and the undo Begin -- inside
# autobead-build, whose handler is the one that has to clean up (c:AUTOBEAD
# itself only asks the questions and changes nothing)
vm.loads('(defun autobead-copy (e) (autobead-no-such-helper e))')
vm.run('c:AUTOBEAD', [None, [vm.wall], (0.0, 24.0, 0.0), "No"])
check("aborted through *error*, once",
      len(vm.handled_errors) == 1 and 'undefined function' in vm.handled_errors[0],
      repr(vm.handled_errors))
check("the handler closed the group it opened", undo_pairs(vm) == ['_Begin', '_End'],
      repr(undo_pairs(vm)))
check("settings back after the error", settings_back(vm), repr(vm.sysvars))
check("the error mode is popped by the handler, exactly once",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0,
      repr((vm.error_mode_depth, vm.error_mode_underflow)))
check("the error is reported under the tool's name", any(
    'AUTOBEAD error' in s for s in vm.printed), repr(vm.printed[-3:]))

# ----------------------------------------------------------------------
print("Esc at the direction click is a quiet cancel, before anything was pushed")
vm = fresh()
vm.handle_errors = True


def esc(vm):
    raise LispError('Function cancelled', vm)


vm.run('c:AUTOBEAD', [None, [vm.wall], esc])
check("the cancel went through the handler",
      vm.handled_errors == ['Function cancelled'], repr(vm.handled_errors))
check("nothing was pushed or opened, and nothing needs undoing",
      vm.error_mode_depth == 0 and vm.error_mode_underflow == 0
      and undo_pairs(vm) == [], repr((vm.error_mode_depth, undo_pairs(vm))))
check("and a plain cancel prints no error line", not any(
    'AUTOBEAD error' in s for s in vm.printed), repr(vm.printed[-2:]))

# ----------------------------------------------------------------------
print("Back at the direction click re-opens the selection")
vm = fresh()
vm.run('c:AUTOBEAD', [None, [vm.wall], "Back", [vm.wall], (0.0, 24.0, 0.0), "No"])
check("the selection prompt fired twice",
      sum(1 for p, _ in vm.prompts if p.startswith('ssget')) == 3,
      repr([p for p, _ in vm.prompts]))
check("and the run still balanced its mode and group",
      vm.error_mode_depth == 0 and undo_pairs(vm) == ['_Begin', '_End'])

# ----------------------------------------------------------------------
print("the tutorial's written route needs no drawing")
vm = fresh()
vm.run('c:TUTORIALAUTOBEAD', ["Checks"])
check("it walked the checks", any('AUTOBEAD' in s for s in vm.printed))
check("and touched nothing", undo_pairs(vm) == [] and vm.error_mode_depth == 0)

print("AUTOBEADVER")
vm = fresh()
vm.run('c:AUTOBEADVER', [])
check("reports the banner", any(('v%s.%s' % m.groups()) in s for s in vm.printed))

if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL AUTOBEAD TESTS PASSED")
