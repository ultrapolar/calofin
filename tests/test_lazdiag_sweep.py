#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every headline command, failed for real, writes a report.

`tools/check_lazdiag.py` reads the tree and says the calls are there.
That is a claim about the TEXT.  This is the claim about the BEHAVIOUR:
each command is loaded beside LAZDIAG, driven to its first prompt, and
handed a genuine error instead of an answer -- the same shape as
`tests/test_cancel_paths.py`, with a real failure where that one sends
an Esc.  What has to come back:

  * a DXF, in the Downloads folder, that parses end to end;
  * the error text inside it, so the report is about THIS failure;
  * the drafter told, in words, that it was written and to send it in;
  * the drawing not written into, and no undo group or error mode left
    behind by the reporter.

The roster is computed from the tree, never typed, so a command added
later is swept by construction.  The exclusions are read straight out of
test_cancel_paths.py rather than restated here: a command with no prompt
for the failure to land at is that suite's business to classify, and two
lists that had to agree would eventually not.

Run: python3 tests/test_lazdiag_sweep.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_lazdiag_sweep.py
"""

import os
import re
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(TESTS_DIR)
sys.path.insert(0, TESTS_DIR)
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))

from lispvm import VM, LispError  # noqa: E402
from callib import COMMAND, LISP_DIR, NOT_A_TOOL, headline_commands, lsp_files  # noqa: E402

LAZDIAG = os.path.join(REPO_DIR, "lisp", "lazdiag", "LAZDIAG.lsp")
PROFILE = r"C:\Users\dm"

#: the message the sweep fails with -- not a cancel, and recognisable
#: inside the report
BOOM = "bad argument type: numberp: nil"

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


# ------------------------------------------------- the roster, computed

WHERE = {}
for _p in lsp_files(LISP_DIR):
    if NOT_A_TOOL in _p.parts:
        continue
    for _c in COMMAND.findall(open(_p).read()):
        WHERE.setdefault(_c.upper(), str(_p))


def _names(const):
    """A name list out of test_cancel_paths.py, read as text.

    Imported it would RUN that suite; restated here it would drift from
    it.  Read, so the one classification of "this command reaches no
    prompt" lives in one place."""
    src = open(os.path.join(TESTS_DIR, "test_cancel_paths.py")).read()
    m = re.search(r"^%s\s*=\s*[\{\[](.*?)[\}\]]" % const, src, re.S | re.M)
    return set(re.findall(r"'([A-Z0-9_-]+)'", m.group(1))) if m else set()


SKIP = (_names("NO_PROMPT") | _names("NEEDS_ACTIVEX") | _names("FILE_CANCEL")
        | _names("QUIET"))
ROSTER = sorted(headline_commands() - SKIP)

#: the file-dialog and environment answers a bare VM cannot give.  NOT
#: getenv: the folder walk needs a writable one, and TEMPPREFIX is it.
STUBS = '''
  (defun getfiled (title dflt ext flags) nil)
  (defun vl-file-directory-p (d) nil)
'''


def boom(vm):
    raise LispError(BOOM, vm)


def fresh(cmd):
    vm = VM()
    vm.load(LAZDIAG)
    vm.load(WHERE[cmd])
    vm.loads(STUBS)
    vm.env["USERPROFILE"] = PROFILE
    vm.handle_errors = True
    vm.printed.clear()
    return vm


# --------------------------------------------------------------- the DXF

def parses(body):
    lines = body.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if len(lines) % 2:
        return False
    for i in range(0, len(lines), 2):
        if not lines[i].strip().lstrip("-").isdigit():
            return False
    return lines[-2:] == ["  0", "EOF"]


# ------------------------------------------------------------- the sweep

print("every headline command, failed for real")
check("the roster is most of the panel", len(ROSTER) >= 50,
      "%d commands" % len(ROSTER))

no_report, unparsable, wrong_msg, silent, dirty = [], [], [], [], []
swept = 0

for cmd in ROSTER:
    if cmd not in WHERE:
        continue
    vm = fresh(cmd)
    before = dict(vm.sysvars)
    ents_before = len(vm.entities)
    try:
        vm.run("c:" + cmd, [boom])
    except LispError as e:
        msg = str(e).splitlines()[0]
        if "scripted answers left over" in msg:
            continue          # never reached a prompt; cancel_paths owns that
        check("%s: the failure went through its handler" % cmd, False, msg)
        continue
    swept += 1
    if not vm.files:
        no_report.append(cmd)
        continue
    path, body = sorted(vm.files.items())[0]
    if not parses(body):
        unparsable.append(cmd)
    if BOOM not in body:
        wrong_msg.append(cmd)
    said = "".join(vm.printed)
    if "SEND THAT FILE IN" not in said or path not in said:
        silent.append(cmd)
    # the reporter itself must leave nothing behind
    if (vm.undo_groups or vm.error_mode_depth
            or len(vm.entities) != ents_before):
        dirty.append("%s (undo=%s mode=%s ents+%d)"
                     % (cmd, vm.undo_groups, vm.error_mode_depth,
                        len(vm.entities) - ents_before))

check("a real failure was driven through %d commands" % swept, swept >= 40,
      "only %d reached a prompt" % swept)
check("every one of them wrote a report", not no_report,
      "no report from: %s" % ", ".join(no_report))
check("every report is a DXF that parses end to end", not unparsable,
      "unparsable: %s" % ", ".join(unparsable))
check("every report carries the error it was written for", not wrong_msg,
      "missing the message: %s" % ", ".join(wrong_msg))
check("every drafter is told, and told to send the file", not silent,
      "said nothing useful: %s" % ", ".join(silent))
check("no report left an undo group, an error mode or a mark behind",
      not dirty, "; ".join(dirty))

print("\na real tool's own selection reaches its report")

# The sweep above fails every command at its FIRST prompt, which is
# before any of them has selected anything -- so it proves the report
# arrives and proves nothing about lzd:watch.  This is that half: a
# drafter's pickfirst selection, a real tool, and a failure after the
# selection has been taken.
vm = fresh("DIMCHECK")
vm.tables["LAYER"].update({"DIMENSION"})
for _i in range(3):
    vm.loads("""(entmakex (list '(0 . "LINE") '(8 . "DIMENSION")
      '(10 %d.0 0.0 0.0) '(11 240.0 %d.0 0.0)))""" % (_i, _i))
vm.loads('(sssetfirst nil (ssget "_X"))')
# break a helper DIMCHECK reaches only after it has taken the selection
vm.loads("(defun dchk:collect-segs (p) (car 1))")
vm.printed.clear()
vm.run("c:DIMCHECK", [])
check("a failure after the selection still writes a report", bool(vm.files),
      "no report")
if vm.files:
    lines = sorted(vm.files.items())[0][1].split("\n")
    copied = sum(1 for i in range(len(lines) - 1)
                 if lines[i].strip() == "0" and lines[i + 1] == "LINE")
    check("...carrying the geometry the drafter had selected, not just "
          "what the run drew", copied == 3, "%d of 3 lines copied" % copied)

print("\na cancel through the same commands writes nothing")

CANCEL = "Function cancelled"
littered = []
for cmd in ROSTER[:25]:           # a representative run: Esc is Esc
    if cmd not in WHERE:
        continue
    vm = fresh(cmd)

    def esc(_vm, _m=CANCEL):
        raise LispError(_m, _vm)
    try:
        vm.run("c:" + cmd, [esc])
    except LispError:
        continue
    if vm.files:
        littered.append(cmd)
check("Esc leaves the Downloads folder alone", not littered,
      "wrote a report for a cancel: %s" % ", ".join(littered))

if failures:
    print("\n%d sweep check(s) FAILED" % len(failures))
    sys.exit(1)
print("\nall LAZDIAG sweep checks passed")
