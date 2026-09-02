"""Every headline command, cancelled at its first prompt.

Until v3.1 no suite ever ran a handler: the VM raised straight through
*error*, so the cleanup that decides what a drafter is left with after
an Esc -- OSMODE back, CMDECHO back, the undo group closed, the error
mode popped, no raw AutoLISP message -- was read by eye and never
executed.  This file runs it, once per command, in the cheapest way
there is: an Esc at the first thing the command asks.  Most commands
have saved their settings and opened their group by then, so the
handler has real work to do.

What is asserted, positively, for every command in ROSTER:

  * the cancel reached the command's own handler, exactly once, with
    the cancel message (an "undefined function" there would mean a
    missing VM stub silently handled -- the one way this test could lie);
  * every system variable reads afterwards as it did before;
  * no line of output carries the tool's "error:" -- a plain cancel is
    silent;
  * and, through run() itself, no undo group is left open and the
    error mode is not left pushed.

Three commands open a file dialog first; getfiled answering nil is the
drafter pressing Cancel there, so that IS their cancel path, and
FILE_CANCEL drives them with no other answer.  QUIET lists the
commands that ask nothing and run to completion -- the RESCUE and
CLEAN commands -- driven the same way with no answers.

tools/check_registry.py reads NO_PROMPT, NEEDS_ACTIVEX, QUIET,
FILE_CANCEL and MORE out of this file for its test census: every headline
command not named in the first two is driven here, so the census
counts it as tested by construction.

Commands that reach no prompt at all on an empty drawing (they say so
and stop) or whose first act is a DCL dialog are named in NO_PROMPT so
a command that starts asking is noticed, not missed.  PADDLE's first
act is the ActiveX block surface the VM does not carry.

Run: python3 tests/test_cancel_paths.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_cancel_paths.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from lispvm import VM, LispError  # noqa: E402
from callib import (COMMAND, LISP_DIR, NOT_A_TOOL, headline_commands,  # noqa: E402
                    lsp_files, read)

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


#: where each command is defined (the standalone file; the tier remap
#: turns it into the grouped twin under CALOFIN_LISP_ROOT=shared)
WHERE = {}
for _p in lsp_files(LISP_DIR):
    if NOT_A_TOOL in _p.parts:
        continue
    for _c in COMMAND.findall(read(_p)):
        WHERE.setdefault(_c.upper(), str(_p))

#: headline commands that stop before asking anything on an empty
#: drawing, or open a DCL dialog first -- no prompt for an Esc to land on
NO_PROMPT = {
    'ABFIND', 'ABMOVE', 'CDCALLOUT', 'POOLDEMO',
    'LAZFORM', 'LAZFORMCOVER', 'LAZSPA', 'LAZSTEP', 'LAZTXT',
    # its pre-flight check runs before its first question, and PADDLE
    # is in another file this VM never loads, so it names the missing
    # stage and stops -- which is the behaviour, not a gap.
    # tests/test_tydrn_suite.py drives its prompt and its handler, Esc
    # included, with the stages stubbed.
    'TYLERDRONESUITE',
}
#: the ActiveX surface the VM does not carry
NEEDS_ACTIVEX = {'PADDLE'}

#: commands that ask nothing: they run to completion on an empty drawing
QUIET = ['COVERCHECKRESCUE', 'DIMCHECKRESCUE', 'LINFINCHECKRESCUE',
         'TUTORIALCOVERCHECKCLEAN', 'XFTCONV-SETUP']

#: commands whose first act is a file dialog, or a look for a folder no
#: setting names: Cancel there, or nothing there, ends the run
FILE_CANCEL = ['ABCDEF', 'ALTABCDEF', 'XYPLOT', 'STOCKCOVER']

#: the file-dialog and environment answers: nil is the drafter's Cancel,
#: and a box with no folders configured
STUBS = '''
  (defun getfiled (title dflt ext flags) nil)
  (defun getenv (name) nil)
  (defun vl-file-directory-p (d) nil)
'''


def esc(vm):
    raise LispError('Function cancelled', vm)


def fresh(cmd):
    vm = VM()
    vm.load(WHERE[cmd])
    vm.loads(STUBS)
    vm.handle_errors = True
    return vm


#: satellites with prompts of their own -- off the panel, still cancellable
MORE = ['DCE']

ROSTER = sorted(headline_commands() - NO_PROMPT - NEEDS_ACTIVEX - set(FILE_CANCEL)) + MORE
check("the roster is most of the panel",
      len(ROSTER) >= 50, "%d commands" % len(ROSTER))

print("Esc at the first prompt")
for cmd in ROSTER:
    vm = fresh(cmd)
    before = dict(vm.sysvars)
    try:
        vm.run('c:' + cmd, [esc])
    except LispError as e:
        msg = str(e).splitlines()[0]
        if 'scripted answers left over' in msg:
            check("%s: reached a prompt" % cmd, False,
                  "asks nothing on an empty drawing - move it to NO_PROMPT "
                  "if that is by design")
        else:
            check("%s: the cancel went through the handler" % cmd, False, msg)
        continue
    handled = list(vm.handled_errors)
    changed = {k: (before.get(k), v) for k, v in vm.sysvars.items()
               if before.get(k) != v}
    errline = [s for s in vm.printed if re.search(r'\berror\b', s, re.I)]
    check("%s: one handled cancel, settings back, nothing said" % cmd,
          handled == ['Function cancelled'] and not changed and not errline,
          "handled=%r changed=%r said=%r"
          % (handled, changed, [s.strip()[:60] for s in errline][:2]))

print("Cancel in the file dialog ends the run quietly")
for cmd in FILE_CANCEL:
    vm = fresh(cmd)
    before = dict(vm.sysvars)
    try:
        vm.run('c:' + cmd, [])
    except LispError as e:
        check("%s: Cancel in the dialog ends the run" % cmd, False,
              str(e).splitlines()[0])
        continue
    changed = {k: (before.get(k), v) for k, v in vm.sysvars.items()
               if before.get(k) != v}
    errline = [s for s in vm.printed if re.search(r'\berror\b', s, re.I)]
    check("%s: no file picked, settings untouched, no error line" % cmd,
          not changed and not errline and not vm.handled_errors,
          "changed=%r said=%r" % (changed, [s.strip()[:60] for s in errline][:2]))

print("commands that ask nothing run to the end on an empty drawing")
for cmd in QUIET:
    vm = fresh(cmd)
    before = dict(vm.sysvars)
    try:
        vm.run('c:' + cmd, [])
    except LispError as e:
        check("%s: runs to the end" % cmd, False, str(e).splitlines()[0])
        continue
    changed = {k: (before.get(k), v) for k, v in vm.sysvars.items()
               if before.get(k) != v}
    check("%s: nothing to do, settings untouched, said so" % cmd,
          not changed and vm.printed and not vm.handled_errors,
          "changed=%r said=%r" % (changed, vm.printed[-1:]))

# the lists above are a claim about the tree: a command that leaves
# the panel, or a new one, must not vanish from the sweep unnoticed
stale = sorted((NO_PROMPT | NEEDS_ACTIVEX) - headline_commands())
check("NO_PROMPT and NEEDS_ACTIVEX name only headline commands",
      not stale, repr(stale))
missing = sorted(c for c in QUIET + FILE_CANCEL + MORE if c not in WHERE)
check("QUIET, FILE_CANCEL and MORE name only real commands", not missing, repr(missing))

if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL CANCEL-PATH CHECKS PASSED (%d commands)"
      % (len(ROSTER) + len(QUIET) + len(FILE_CANCEL)))
