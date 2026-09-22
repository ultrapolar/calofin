"""A handler that pushed the error mode may not use command-s before it pops.

Under *push-error-using-command* AutoCAD refuses command-s inside *error*,
and the refusal is not an ordinary error: vl-catch-all-apply does not
catch it, the drafter sees

    "INTERNAL error in FAIL\\nmessage lost, reset to top"

and every line of the handler after it is skipped -- the undo close, the
pop, the LAZDIAG report.  SPA did that on every Esc and every failure
from 092226 REV29 back: its -DIMSTYLE restore went through command-s
while the mode it pushed at the top was still on the stack.  The first
failure's own message was lost with it, and the mode stayed pushed for
the rest of the session.

The VM models the refusal now (lispvm.HandlerAbort); this file pins the
rule itself and drives SPA's handler from a point mid-run, where the
guide is up and the undo group is open, so the whole handler has work.

Run: python3 tests/test_handler_error_mode.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_handler_error_mode.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, HandlerAbort, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
SPA = os.path.join(HERE, '..', 'lisp', 'spa', 'SPA.LSP')
FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def esc(vm):
    raise LispError('Function cancelled', vm)


print("the VM refuses command-s inside a pushed handler, past the catch")
HANDLER = '''
  (defun c:T1 ( / *error*)
    (defun *error* (msg)
      %s
      (setq t1:*done* t)
      (princ))
    (if *push-error-using-command* (*push-error-using-command*))
    (getpoint "\\nPick: "))
'''
POP = '(if *pop-error-mode* (*pop-error-mode*))'
CMDS = '(vl-catch-all-apply (quote command-s) (list "_.REGEN"))'
for label, body, ok in (
        ("command-s before the pop kills the handler", CMDS + POP, False),
        ("command-s after the pop is legal", POP + CMDS, True)):
    vm = VM()
    vm.handle_errors = True
    vm.loads(HANDLER % body)
    try:
        vm.run('c:T1', [esc])
        got = bool(vm.get(Sym('t1:*done*')))
    except HandlerAbort:
        got = False
    check(label, got == ok)

print("SPA: Esc at the length, guide up and undo group open")
vm = VM()
vm.load(SPA)
vm.handle_errors = True
# a shop style whose name has a space: -DIMSTYLE could not have typed it
vm.tables['DIMSTYLE'].add('Shop Dims')
vm.sysvars['DIMSTYLE'] = 'Shop Dims'
before = dict(vm.sysvars)
try:
    vm.run('c:SPA', [None, 'C', 'R', None, 80.0, esc])
    ran = True
except LispError as e:
    ran = False
    check("the handler ran to its end", False, str(e).splitlines()[0])
if ran:
    changed = {k: (before.get(k), v) for k, v in vm.sysvars.items()
               if before.get(k) != v}
    check("the handler ran to its end (undo closed, mode popped)",
          vm.handled_errors == ['Function cancelled'],
          repr(vm.handled_errors))
    check("every setting back, the dim style included", not changed,
          repr(changed))

if FAILS:
    print("\n%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("\nALL HANDLER ERROR-MODE CHECKS PASSED")
