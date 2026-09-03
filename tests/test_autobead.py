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

v1.5 gave the engine two ways to NOT bead something, and both are
covered here against real chains: skippts names step lines to hold back
(the step routines put the last step drawn there - the line that closes
a run has no riser behind it), and the side-wall answer grew a None
that leaves the walls bare.  The VM cannot offset, but it records every
._offset the run asks for, which is exactly the question: which chains
were handed to the offset engine and which were held back.

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
check("the engine takes the step lines to hold back",
      '(defun autobead-build (ss dirpt sidewalls treadpts skippts' in SRC)
check("the side-wall question offers None beside All and Some",
      '(initget "All Some None Yes No Back Undo")' in SRC
      and '[All/Some/None/Back] <All>' in SRC)
check("...and still answers to the Yes / No it used to take",
      '((= ans "Yes")  "Some")' in SRC and '((= ans "No")   "All")' in SRC)

STEPS = {
    'CORNERSTP': 'cs',
    'HEMISTEP': 'hs',
    'NORMIESTEP': 'ns',
}
for tool, px in STEPS.items():
    src = open(os.path.join(HERE, '..', 'lisp', 'cornerstp', tool + '.lsp'),
               encoding='ascii').read()
    check("%s offers All/Some/None for the side walls" % tool,
          '(initget "All Some None")' in src
          and '" [All/Some/None]"' in src)
    check("%s hands the answer straight to the engine" % tool,
          'bss bdir\n                      bside\n' in src)
    check("%s holds back the last step drawn" % tool,
          '(list (%s-entmid (cdr (last btreads))))' % px in src)

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
# A pocket the classifier can read: two walls, and two lines crossing
# between them (both ends landing mid-span) that come back as step
# lines.  Each is on a POOL* layer of its own, so the ._offset calls the
# run records say which chains were offset and which were held back.
POCKET = '''
  (foreach l (list "POOL-WALLA" "POOL-WALLB" "POOL-STEP1" "POOL-STEP2")
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 l) '(70 . 0) '(62 . 4) '(6 . "Continuous"))))
  (setq ab-wa (entmakex (list '(0 . "LINE") '(8 . "POOL-WALLA")
                              '(10 0.0 0.0 0.0) '(11 240.0 0.0 0.0)))
        ab-wb (entmakex (list '(0 . "LINE") '(8 . "POOL-WALLB")
                              '(10 0.0 120.0 0.0) '(11 240.0 120.0 0.0)))
        ab-s1 (entmakex (list '(0 . "LINE") '(8 . "POOL-STEP1")
                              '(10 60.0 0.0 0.0) '(11 60.0 120.0 0.0)))
        ab-s2 (entmakex (list '(0 . "LINE") '(8 . "POOL-STEP2")
                              '(10 120.0 0.0 0.0) '(11 120.0 120.0 0.0)))
        ab-ss (ssadd))
  (foreach e (list ab-wa ab-wb ab-s1 ab-s2) (ssadd e ab-ss))'''

# The VM has no vla-Copy, and the copy is not what these cases are
# about: a LINE duplicated by hand chains and classifies the same way.
COPY_BY_HAND = '''
  (defun autobead-copy (e / ed)
    (setq ed (entget e))
    (entmakex (list '(0 . "LINE") (cons 8 (cdr (assoc 8 ed)))
                    (assoc 10 ed) (assoc 11 ed))))'''


def pocket():
    vm = fresh()
    vm.loads(COPY_BY_HAND)
    vm.loads(POCKET)
    return vm


def layer_of(vm, e):
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == 8:
            return g.b
    return None


def offset_layers(vm):
    """The layers of the chains ._offset was actually asked to offset."""
    return sorted(layer_of(vm, c[2]) for c in vm.commands
                  if c and c[0] == '._offset')


ALL_FOUR = ['POOL-STEP1', 'POOL-STEP2', 'POOL-WALLA', 'POOL-WALLB']
DIR = '(list 120.0 200.0 0.0)'

# ----------------------------------------------------------------------
print("with nothing held back every chain goes to the offset engine")
vm = pocket()
vm.loads('(autobead-build ab-ss %s "All" nil nil)' % DIR)
check("all four chains offset", offset_layers(vm) == ALL_FOUR,
      repr(offset_layers(vm)))
check("and the walls are reported as unrestricted", any(
    'full length (not restricted)' in s for s in vm.printed))

# ----------------------------------------------------------------------
print("a step line named in skippts is held back, not beaded")
vm = pocket()
vm.loads('(autobead-build ab-ss %s "All" nil (list (list 60.0 60.0 0.0)))'
         % DIR)
check("the named step line never reached the offset engine",
      offset_layers(vm) == ['POOL-STEP2', 'POOL-WALLA', 'POOL-WALLB'],
      repr(offset_layers(vm)))
check("and the report says one was held back", any(
    '1 step line(s) held back' in s for s in vm.printed), repr(vm.printed[-4:]))
# the VM has no offset engine, so every chain it IS handed comes back
# empty -- which makes the failure count a second reading of how many
# chains were offered: three, not four
check("a held-back chain is not counted as an offset failure", any(
    '3 chain(s) could not be offset' in s for s in vm.printed),
    repr(vm.printed[-4:]))

# ----------------------------------------------------------------------
print("None leaves the side walls bare and beads the step faces only")
vm = pocket()
vm.loads('(autobead-build ab-ss %s "None" nil nil)' % DIR)
check("only the step lines offset",
      offset_layers(vm) == ['POOL-STEP1', 'POOL-STEP2'],
      repr(offset_layers(vm)))
check("and the report names the answer", any(
    'None -- the side walls take no bead' in s for s in vm.printed),
    repr(vm.printed[-4:]))

# ----------------------------------------------------------------------
print("None and a held-back last step read together")
vm = pocket()
vm.loads('(autobead-build ab-ss %s "None" nil (list (list 120.0 60.0 0.0)))'
         % DIR)
check("one step line is all that is left to bead",
      offset_layers(vm) == ['POOL-STEP1'], repr(offset_layers(vm)))

# ----------------------------------------------------------------------
print("the T / nil the engine used to take still read the same way")
vm = pocket()
vm.loads('(autobead-build ab-ss %s nil nil nil)' % DIR)
check("nil is All: every chain offsets", offset_layers(vm) == ALL_FOUR,
      repr(offset_layers(vm)))
vm = pocket()
vm.loads('(autobead-build ab-ss %s T nil nil)' % DIR)
check("T is Some, and with no clicked step it restricts nothing",
      offset_layers(vm) == ALL_FOUR, repr(offset_layers(vm)))

# ----------------------------------------------------------------------
print("held-back is decided by the point, not by the order of the chains")
vm = pocket()
check("a point on the chain holds it",
      vm.loads('(if (autobead-held-p ab-s1 (list (list 60.0 12.0 0.0))) 1 0)')
      == 1)
check("a point off it does not",
      vm.loads('(if (autobead-held-p ab-s1 (list (list 61.0 12.0 0.0))) 1 0)')
      == 0)
check("and no points at all hold nothing",
      vm.loads('(if (autobead-held-p ab-s1 nil) 1 0)') == 0)

# ----------------------------------------------------------------------
print("the command's None answer reaches the engine")
vm = pocket()
vm.run('c:AUTOBEAD', [None, [vm.get('ab-wa'), vm.get('ab-wb'),
                             vm.get('ab-s1'), vm.get('ab-s2')],
                      (120.0, 200.0, 0.0), "None"])
check("only the step lines offset",
      offset_layers(vm) == ['POOL-STEP1', 'POOL-STEP2'],
      repr(offset_layers(vm)))
check("the run still balanced its mode and group",
      vm.error_mode_depth == 0 and undo_pairs(vm) == ['_Begin', '_End'])

print("...and No, the word it used to take, still means All")
vm = pocket()
vm.run('c:AUTOBEAD', [None, [vm.get('ab-wa'), vm.get('ab-wb'),
                             vm.get('ab-s1'), vm.get('ab-s2')],
                      (120.0, 200.0, 0.0), "No"])
check("every chain offsets", offset_layers(vm) == ALL_FOUR,
      repr(offset_layers(vm)))

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
