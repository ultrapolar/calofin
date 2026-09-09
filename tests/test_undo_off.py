#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""No command closes an undo group it never opened.

AutoCAD refuses "_.UNDO _Begin" when undo recording is off (bit 1 of
UNDOCTL clear), so every routine here opens its group conditionally:

    (if (= 1 (logand 1 (getvar "UNDOCTL")))
      (progn (command "_.UNDO" "_Begin") (setq undo-open T)))

The close has to be conditional too, because "_End" on no open group is
an error of its own -- and it lands at the END of the command, after
everything has been drawn, so what the drafter gets is a finished job
followed by an error message, with the settings restore and the
sysvar putback behind it never reached.  CORNERSTP says exactly that
beside its own guard: "close only a group this run opened: in a drawing
with UNDO off none was, and _End on no group is an error of its own".

Eleven commands over six files closed unconditionally.  Nothing caught
it because every other suite runs at AutoCAD's default UNDOCTL of 5,
where the group is always open and the two spellings behave alike.

The roster is computed, never typed: every command in the tree is run
twice, once with undo recording on and once with it off, and any
command that survives the first and dies on the second is the bug.
Commands that need real input to get anywhere are driven as far as
plain Enters take them -- that is enough to reach the close on all but
a handful, and FITABHD, which needs its seven settings, is driven by
name below.

Run: python3 tests/test_undo_off.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_undo_off.py
"""

import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

from callib import COMMAND, LISP_DIR, NOT_A_TOOL, lsp_files, read  # noqa: E402
from lispvm import VM, LispError  # noqa: E402

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


#: the file-dialog and environment answers a bare VM has no way to give
STUBS = '''
  (defun getfiled (title dflt ext flags) nil)
  (defun getenv (name) nil)
  (defun vl-file-directory-p (d) nil)
'''

#: UNDOCTL 5 is AutoCAD's default (undo on, one command at a time); 4 is
#: the same with bit 1 -- the recording bit -- cleared.
UNDO_ON, UNDO_OFF = 5, 4

#: "_End with no group open" is what the VM raises for the bug; the
#: message is matched rather than the exception type so a routine that
#: fails for some other reason with undo off is reported as itself.
BUG = "no group open"


def drive(cmd, sibs, undoctl, script=None):
    """Run one command, answering Enter as often as it takes.  Returns
    ('ok', n) or ('err', message)."""
    tries = [script] if script is not None else [[None] * n for n in range(12)]
    for answers in tries:
        vm = VM()
        try:
            for q in sibs:
                vm.load(q)
            vm.loads(STUBS)
        except LispError as e:
            return ("err", "load: " + str(e).split("\n")[0])
        vm.sysvars["UNDOCTL"] = undoctl
        try:
            vm.run("c:" + cmd, list(answers))
            return ("ok", len(answers))
        except LispError as e:
            msg = str(e).split("\n")[0]
            if "SCRIPT EXHAUSTED" in msg or "left over" in msg:
                continue
            return ("err", msg)
    return ("skip", "no plain-Enter path")


ROSTER = []
for _p in lsp_files(LISP_DIR):
    if NOT_A_TOOL in _p.parts:
        continue
    _sibs = [str(q) for q in lsp_files(_p.parent)]
    for _m in COMMAND.finditer(read(_p)):
        ROSTER.append((_m.group(1).upper(), _p.name, _sibs))

#: commands that need more than Enters to reach their close, with the
#: script that gets them there
NAMED = {
    "FITABHD": [None, "Rectangle", "Square", 1.0, 15, "Insquare", "No", None],
}

print(f"driving {len(ROSTER)} command(s) with undo recording off")
bad, ran, skipped = [], 0, 0
for cmd, where, sibs in ROSTER:
    script = NAMED.get(cmd)
    on = drive(cmd, sibs, UNDO_ON, script)
    if on[0] != "ok":
        # it does not get through with undo ON either, so undo OFF says
        # nothing about it -- its own suite is what covers that path
        skipped += 1
        continue
    off = drive(cmd, sibs, UNDO_OFF, script)
    ran += 1
    if off[0] == "err" and BUG in off[1]:
        bad.append(f"{cmd} ({where})")
    elif off[0] == "err":
        bad.append(f"{cmd} ({where}) failed with undo off: {off[1][:70]}")

check(f"none of the {ran} command(s) reached closes a group it never opened",
      not bad, "\n         ".join(bad[:14]))
print(f"  ({skipped} command(s) need input a bare Enter cannot give; their "
      f"own suites drive those)")

# and the positive half: with undo ON the bracket really is opened and
# closed, so the guard has not simply turned the group off for everyone
vm = VM()
for _q in [str(q) for q in lsp_files(LISP_DIR / "fitabhd")]:
    vm.load(_q)
vm.loads(STUBS)
vm.sysvars["UNDOCTL"] = UNDO_ON
vm.run("c:FITABHD", list(NAMED["FITABHD"]))
undo = [c for c in vm.commands if c and c[0] == "_.UNDO"]
check("with undo ON the bracket is still opened and closed",
      undo == [["_.UNDO", "_Begin"], ["_.UNDO", "_End"]], f"{undo}")

vm = VM()
for _q in [str(q) for q in lsp_files(LISP_DIR / "fitabhd")]:
    vm.load(_q)
vm.loads(STUBS)
vm.sysvars["UNDOCTL"] = UNDO_OFF
vm.run("c:FITABHD", list(NAMED["FITABHD"]))
undo = [c for c in vm.commands if c and c[0] == "_.UNDO"]
check("with undo OFF neither half is sent", undo == [], f"{undo}")

if failures:
    print(f"\n{len(failures)} undo check(s) FAILED")
    sys.exit(1)
print("\nall undo-off checks passed")
