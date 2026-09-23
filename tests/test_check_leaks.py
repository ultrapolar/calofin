#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_leaks.py on made files: every rule fires on the leak it
exists for and goes quiet once the leak is fixed, and the shapes the
tree writes on purpose -- a close under its flag, a restore from a
global snapshot, a handoff the callee spends on entry -- stay quiet.

A leak is one way out that skips a release, and the drafter meets it in
the NEXT command: an undo group still open, CMDECHO still off, a flag a
dead run left up that the next run reads as its own.  Every test in the
tree stayed green over the ones this check was ported to catch -- the
VM runs one command at a time, and a leak is between two -- so each
rule is pinned here both ways, on the shape of the bug it found.

Run: python3 tests/test_check_leaks.py
"""

import contextlib
import io
import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_leaks  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def run(text, base=None, name='CASES.lsp'):
    """check_leaks over one made file: the lines it printed."""
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / name
        p.write_text(text, encoding='utf-8')
        out = []
        check_leaks.report([p], base or {}, False, out=out.append)
        return out


def flagged(out, cmd, rule):
    return any((' %s %s -- ' % (cmd, rule)) in ln for ln in out)


def both_ways(rule, cmd, why, bad, fixed_from, fixed_to):
    """RULE fires on CMD in BAD, and not once FIXED_FROM becomes FIXED_TO."""
    assert fixed_from in bad, (rule, fixed_from)
    out = run(bad)
    check("%s fires: %s" % (rule, why), flagged(out, cmd, rule), out)
    good = bad.replace(fixed_from, fixed_to)
    out = run(good)
    check("%s quiet once fixed: %s" % (rule, why),
          not flagged(out, cmd, rule), out)


print("== check_leaks: each rule both ways ==")

# EXIT -- XYPLOT's "nothing plotted" exits skipped the close that the
# plotting branch makes, and left the drafter inside the group
EXIT_UNDO = r"""
(defun c:EXU ( / *error* undo-open rows)
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if lzd:report (lzd:report "EXU" nil msg))
    (princ))
  (if lzd:begin (lzd:begin "EXU" nil))
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") (setq undo-open T)))
  (setq rows (getint "\nRows: "))
  (if (null rows)
    (princ "\nNothing plotted.")
    (progn
      (command "_.LINE" "0,0" "1,1" "")
      (if undo-open (progn (command "_.UNDO" "_End") (setq undo-open nil)))))
  (if lzd:end (lzd:end "EXU"))
  (princ))
"""
both_ways('EXIT', 'C:EXU', "an early exit leaves the undo group open",
          EXIT_UNDO, '(princ "\\nNothing plotted.")',
          '(progn (princ "\\nNothing plotted.") '
          '(command "_.UNDO" "_End") (setq undo-open nil))')

# ...and the finding names the way out, not only where the group was
# opened: the "nothing plotted" arm, at its own line
out = run(EXIT_UNDO)
exit_line = next(i for i, ln in enumerate(EXIT_UNDO.split('\n'), 1)
                 if 'Nothing plotted' in ln)
check("EXIT names the exit that skips the close, and is anchored there",
      any(':%d: C:EXU EXIT' % exit_line in ln
          and 'on the way out at c:exu:%d' % exit_line in ln for ln in out),
      out)

# EXIT -- the SAME bug with the arms the other way round: the close sits
# under (if rows ...), and a guard that is not the acquire's own flag
# is a path the release is not on.  Every close used to count on both
# arms of any two-armed if, and this XYPLOT went quiet
SWAPPED = r"""
(defun c:EXW ( / *error* undo-open rows)
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (princ))
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") (setq undo-open T)))
  (setq rows (getint "\nRows: "))
  (if rows
    (progn
      (command "_.LINE" "0,0" "1,1" "")
      (if undo-open (progn (command "_.UNDO" "_End") (setq undo-open nil)))))
  (princ))
"""
both_ways('EXIT', 'C:EXW', "the close under (if rows ...), arms swapped",
          SWAPPED, '(setq undo-open nil)))))\n  (princ))',
          '(setq undo-open nil)))))\n'
          '  (if undo-open (progn (command "_.UNDO" "_End") '
          '(setq undo-open nil)))\n  (princ))')
SWAPPED_SV = r"""
(defun c:EXV ( / *error* oe rows)
  (defun *error* (msg) (if oe (setvar "CMDECHO" oe)) (princ))
  (setq oe (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq rows (getint "\nRows: "))
  (if rows (progn (command "_.LINE" "0,0" "1,1" "") (setvar "CMDECHO" oe)))
  (princ))
"""
both_ways('EXIT', 'C:EXV', "a CMDECHO restore under (if rows ...)",
          SWAPPED_SV, '(setvar "CMDECHO" oe)))\n  (princ))',
          '(princ)))\n  (setvar "CMDECHO" oe)\n  (princ))')
SWAPPED_LZD = r"""
(defun c:EXZ ( / *error* rows)
  (defun *error* (msg) (if lzd:report (lzd:report "EXZ" nil msg)) (princ))
  (if lzd:begin (lzd:begin "EXZ" nil))
  (setq rows (getint "\nRows: "))
  (if rows
    (progn (command "_.LINE" "0,0" "1,1" "") (if lzd:end (lzd:end "EXZ"))))
  (princ))
"""
both_ways('EXIT', 'C:EXZ', "an lzd:end under (if rows ...)",
          SWAPPED_LZD, '(if lzd:end (lzd:end "EXZ"))))\n  (princ))',
          '(princ)))\n  (if lzd:end (lzd:end "EXZ"))\n  (princ))')

# EXIT -- a close under a run-state flag the run already dropped: the
# interpreter follows the global's truth, so the close is on no path
DROPPED = r"""
(setq r:*open* nil)
(defun r:tidy () (setq r:*open* nil))
(defun c:EXD ( / *error*)
  (defun *error* (msg)
    (if r:*open* (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq r:*open* nil)
    (princ))
  (command "_.UNDO" "_Begin")
  (setq r:*open* T)
  (getpoint "\nPick: ")
  (r:tidy)
  (if r:*open* (command "_.UNDO" "_End"))
  (princ))
"""
both_ways('EXIT', 'C:EXD', "a close under a flag dropped before it",
          DROPPED,
          '  (r:tidy)\n  (if r:*open* (command "_.UNDO" "_End"))',
          '  (if r:*open* (command "_.UNDO" "_End"))\n  (r:tidy)')

# EXIT -- (mapcar 'setvar names literals) is a mute, not a restore
MAPMUTE = r"""
(defun c:EXM ( / *error* old)
  (defun *error* (msg) (princ))
  (setq old (mapcar 'getvar '("CMDECHO" "OSMODE")))
  (mapcar 'setvar '("CMDECHO" "OSMODE") '(0 0))
  (if (getpoint "\nPick: ")
    (progn (command "_.LINE" "0,0" "1,1" "")
           (mapcar 'setvar '("CMDECHO" "OSMODE") old))
    (princ "\nNothing."))
  (princ))
"""
both_ways('EXIT', 'C:EXM', "a (mapcar 'setvar ...) mute kept on one arm",
          MAPMUTE, '(princ "\\nNothing."))',
          '(progn (princ "\\nNothing.") '
          '(mapcar \'setvar \'("CMDECHO" "OSMODE") old)))')

# EXIT -- a setvar by a computed name (spa:setv's (setvar v val)) moves
# a sysvar it cannot name; it is not a table restore that frees every
# one the run holds
SETV = r"""
(defun t9:setv (v val) (setvar v val))
(defun c:EXC ( / *error* oos)
  (defun *error* (msg) (if oos (setvar "OSMODE" oos)) (princ))
  (setq oos (getvar "OSMODE"))
  (setvar "OSMODE" 0)
  (t9:setv "DIMLUNIT" 5)
  (if (getpoint "\nPick: ") (setvar "OSMODE" oos) (princ "\nNone."))
  (princ))
"""
both_ways('EXIT', 'C:EXC', "OSMODE kept on one arm, a computed setv after",
          SETV, '(princ "\\nNone."))',
          '(progn (princ "\\nNone.") (setvar "OSMODE" oos)))')

# EXIT -- TUTORIALSPA's body was one (if ...), and neither arm ended the
# LAZDIAG run it began
EXIT_LZD = r"""
(defun c:EXL ( / *error*)
  (defun *error* (msg) (if lzd:report (lzd:report "EXL" nil msg)) (princ))
  (if lzd:begin (lzd:begin "EXL" nil))
  (if (getpoint "\nPick: ") (princ "\na") (princ "\nb")))
"""
both_ways('EXIT', 'C:EXL', "neither arm ends the LAZDIAG run",
          EXIT_LZD, '(princ "\\nb")))',
          '(princ "\\nb"))\n  (if lzd:end (lzd:end "EXL"))\n  (princ))')

# EXIT -- a sysvar muted for the run and put back on one arm only
EXIT_SV = r"""
(defun c:EXS ( / *error* oe)
  (defun *error* (msg) (if oe (setvar "CMDECHO" oe)) (princ))
  (setq oe (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (if (getpoint "\nPick: ")
    (progn (command "_.LINE" "0,0" "1,1" "") (setvar "CMDECHO" oe))
    (princ "\nNothing picked."))
  (princ))
"""
both_ways('EXIT', 'C:EXS', "CMDECHO put back on one arm only",
          EXIT_SV, '(princ "\\nNothing picked.")',
          '(progn (princ "\\nNothing picked.") (setvar "CMDECHO" oe))')

# HANDLER -- the handler forgets a sysvar the run holds at a prompt
HANDLER = r"""
(defun c:HND ( / *error* oe)
  (defun *error* (msg) (if lzd:report (lzd:report "HND" nil msg)) (princ))
  (setq oe (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (getpoint "\nPick: ")
  (setvar "CMDECHO" oe)
  (princ))
"""
both_ways('HANDLER', 'C:HND', "Esc at the prompt leaves CMDECHO off",
          HANDLER, '(defun *error* (msg) (if lzd:report',
          '(defun *error* (msg) (if oe (setvar "CMDECHO" oe)) (if lzd:report')

# HANDLER -- a sysvar set from a local that holds a NEW value is a mute:
# perp's srcLtype, taken off the source entity, is not a snapshot
NEWVAL = r"""
(defun c:HNV ( / *error* ocl lay)
  (defun *error* (msg) (princ))
  (setq ocl (getvar "CLAYER"))
  (setq lay (cdr (assoc 8 (entget (car (entsel "\nSource: "))))))
  (setvar "CLAYER" lay)
  (getpoint "\nPick: ")
  (setvar "CLAYER" ocl)
  (princ))
"""
both_ways('HANDLER', 'C:HNV', "a layer taken off an entity is a new value",
          NEWVAL, '(defun *error* (msg) (princ))',
          '(defun *error* (msg) (if ocl (setvar "CLAYER" ocl)) (princ))')

# HANDLER -- SPA's death: command-s under the pushed mode kills the
# handler, so the pop and the report after it never run
DEATH = r"""
(defun c:HDT ( / *error*)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" "X"))
    (if *pop-error-mode* (*pop-error-mode*))
    (if lzd:report (lzd:report "HDT" nil msg))
    (princ))
  (if lzd:begin (lzd:begin "HDT" nil))
  (if *push-error-using-command* (*push-error-using-command*))
  (getpoint "\nPick: ")
  (if *pop-error-mode* (*pop-error-mode*))
  (if lzd:end (lzd:end "HDT"))
  (princ))
"""
out = run(DEATH)
check("HANDLER fires: a handler that dies at command-s under the push",
      flagged(out, 'C:HDT', 'HANDLER') and any('dies at' in ln for ln in out),
      out)
fixed = DEATH.replace(
    """    (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" "X"))
    (if *pop-error-mode* (*pop-error-mode*))""",
    """    (if *pop-error-mode* (*pop-error-mode*))
    (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" "X"))""")
out = run(fixed)
check("HANDLER quiet once the pop comes first", not flagged(out, 'C:HDT',
                                                            'HANDLER'), out)

# BYPASS -- the three check tutorials called their scan as a c: function
# while holding CMDECHO and the undo group; an Esc in the scan runs only
# the scan's handler
BYPASS = r"""
(defun c:BSCAN ( / *error*)
  (defun *error* (msg) (princ))
  (getpoint "\nScan: ")
  (princ))
(defun c:BYP ( / *error* oe)
  (defun *error* (msg) (if oe (setvar "CMDECHO" oe)) (princ))
  (setq oe (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (c:BSCAN)
  (setvar "CMDECHO" oe)
  (princ))
"""
both_ways('BYPASS', 'C:BYP', "a scan called holding CMDECHO",
          BYPASS, '  (c:BSCAN)\n  (setvar "CMDECHO" oe)',
          '  (setvar "CMDECHO" oe)\n  (c:BSCAN)')

# BYPASS -- a stage chosen at run time cannot be simulated: it is
# charged the settings held (TYLERDRONESUITE's PICKFIRST), never a
# handoff global the stage is written to consume
DYN = r"""
(setq *dyn-hand* nil)
(defun c:DYNST ( / *error* h)
  (defun *error* (msg) (setq *dyn-hand* nil) (princ))
  (setq h *dyn-hand* *dyn-hand* nil)
  (getpoint "\nStage: ")
  (princ))
(defun c:DYN ( / *error* pf nm)
  (defun *error* (msg) (if pf (setvar "PICKFIRST" pf)) (princ))
  (setq pf (getvar "PICKFIRST"))
  (setvar "PICKFIRST" 1)
  (foreach nm '("DYNST")
    (setq *dyn-hand* (list nm 1))
    (apply (read (strcat "c:" nm)) nil)
    (setq *dyn-hand* nil))
  (setvar "PICKFIRST" pf)
  (princ))
"""
both_ways('BYPASS', 'C:DYN', "a run-time stage called holding PICKFIRST",
          DYN, '  (setvar "PICKFIRST" 1)\n', '')
out = run(DYN.replace('  (setvar "PICKFIRST" 1)\n', ''))
check("...and the handoff global it hands the stage is not charged",
      not any('dyn-hand' in ln for ln in out), out)

# STALE -- OASIS: dimstysave refuses to save over a standing snapshot,
# and a refusal exit never dropped it, so the next clean run restored
# the dead run's style over the drafter's
STALE_LATCH = r"""
(setq t1:*odstyle* nil)
(defun t1:save ()
  (if (not t1:*odstyle*) (setq t1:*odstyle* (getvar "DIMSTYLE"))))
(defun t1:restore ()
  (if t1:*odstyle* (setvar "DIMSTYLE" t1:*odstyle*))
  (setq t1:*odstyle* nil))
(defun c:STL ( / *error*)
  (defun *error* (msg) (t1:restore) (princ))
  (t1:save)
  (if (getpoint "\nPick: ")
    (princ "\nRefused: the UCS is tilted.")
    (progn (command "_.LINE" "0,0" "1,1" "") (t1:restore)))
  (princ))
"""
both_ways('STALE', 'C:STL', "a latched snapshot a refusal exit keeps",
          STALE_LATCH, '(princ "\\nRefused: the UCS is tilted.")',
          '(progn (princ "\\nRefused: the UCS is tilted.") (t1:restore))')

# STALE -- POOL: a flag set mid-run, cleared on the clean path only, and
# read by the next run before it writes it
STALE_ESC = r"""
(setq t2:*ask* nil)
(defun c:STE ( / *error*)
  (defun *error* (msg) (princ))
  (if t2:*ask* (princ "\nMarking the given dimensions."))
  (setq t2:*ask* (getkword "\nMark them? "))
  (getpoint "\nPick: ")
  (setq t2:*ask* nil)
  (princ))
"""
both_ways('STALE', 'C:STE', "a flag an Esc leaves up, read first next run",
          STALE_ESC, '  (if t2:*ask*',
          '  (setq t2:*ask* nil)\n  (if t2:*ask*')

# STALE -- a handoff the callee does NOT spend on entry, and whose
# handler does not clear it: an Esc at the callee's prompt leaves it
# for the next run
HANDOFF_BAD = r"""
(setq *q3-hand* nil)
(defun c:Q3PAD ( / *error* h)
  (defun *error* (msg) (princ))
  (getpoint "\nPad: ")
  (setq h *q3-hand* *q3-hand* nil)
  (princ))
(defun c:Q3 ( / *error*)
  (defun *error* (msg) (princ))
  (getpoint "\nGut: ")
  (setq *q3-hand* (list "Q3PAD" 1))
  (c:Q3PAD)
  (setq *q3-hand* nil)
  (princ))
"""
both_ways('STALE', 'C:Q3PAD', "a handoff an Esc in the callee leaves",
          HANDOFF_BAD,
          '  (getpoint "\\nPad: ")\n  (setq h *q3-hand* *q3-hand* nil)',
          '  (setq h *q3-hand* *q3-hand* nil)\n  (getpoint "\\nPad: ")')

# SIBLING -- pf:*ruler*: every other tool's ruler is cleared at run
# time, ABHD's never was, and the next run started from the last one's
SIBLING = r"""
(setq a:*ruler* nil)
(defun c:SIA () (setq a:*ruler* nil) (setq a:*ruler* (getpoint)) (princ))
(setq b:*ruler* nil)
(defun c:SIB () (setq b:*ruler* nil) (setq b:*ruler* (getpoint)) (princ))
(setq p:*ruler* nil)
(defun c:SIP ()
  (if p:*ruler* (princ "\nLast run's ruler."))
  (setq p:*ruler* (getpoint))
  (princ))
"""
both_ways('SIBLING', 'C:SIP', "a ruler nothing ever clears",
          SIBLING, '(defun c:SIP ()\n',
          '(defun c:SIP ()\n  (setq p:*ruler* nil)\n')

# ERRNO -- sticky: an earlier command's missed pick reads as this one's
ERRNO = r"""
(defun t7:pick ( / s)
  (setq s (entsel "\nPick: "))
  (if (= 7 (getvar "ERRNO")) nil s))
"""
out = run(ERRNO)
check("ERRNO fires: ERRNO read with no reset before it",
      flagged(out, 'T7:PICK', 'ERRNO'), out)
out = run(ERRNO.replace('(setq s (entsel',
                        '(setvar "ERRNO" 0) (setq s (entsel'))
check("ERRNO quiet once reset before the pick",
      not flagged(out, 'T7:PICK', 'ERRNO'), out)

# HANDOFF -- (vl-cmdf "_.ABHD"): the command processor cannot reach an
# AutoLISP command, so ABHD never started while ABCDEF said it had
HANDOFF = r"""
(defun c:HOSCAN () (princ))
(defun c:HOF () (vl-cmdf "_.HOSCAN") (princ))
"""
both_ways('HANDOFF', 'C:HOF', "(vl-cmdf) of an AutoLISP command",
          HANDOFF, '(vl-cmdf "_.HOSCAN")', '(c:HOSCAN)')


print("== the shapes written on purpose stay quiet ==")

# autobead-build under a push: everything its handler reads is a global,
# the settings come back from global snapshots, and the group is closed
# under its global flag
GLOBALS = r"""
(setq q1:*oldos* nil q1:*undo-open* nil)
(defun c:Q1 ( / *error*)
  (defun *error* (msg)
    (if q1:*oldos* (setvar "OSMODE" q1:*oldos*))
    (setq q1:*oldos* nil)
    (if *pop-error-mode* (*pop-error-mode*))
    (if q1:*undo-open* (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq q1:*undo-open* nil)
    (if lzd:report (lzd:report "Q1" nil msg))
    (princ))
  (setq q1:*oldos* nil q1:*undo-open* nil)
  (if lzd:begin (lzd:begin "Q1" nil))
  (if *push-error-using-command* (*push-error-using-command*))
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") (setq q1:*undo-open* T)))
  (setq q1:*oldos* (getvar "OSMODE"))
  (setvar "OSMODE" 0)
  (getpoint "\nPick: ")
  (setvar "OSMODE" q1:*oldos*)
  (setq q1:*oldos* nil)
  (if q1:*undo-open* (command "_.UNDO" "_End"))
  (setq q1:*undo-open* nil)
  (if *pop-error-mode* (*pop-error-mode*))
  (if lzd:end (lzd:end "Q1"))
  (princ))
"""
out = run(GLOBALS)
check("global snapshots and a close under a global flag are clean",
      not out, out)

# XFTCONV: the close is the then-arm of a three-armed if on its flag
THREE = r"""
(defun c:Q2 ( / *error* undone begun)
  (defun *error* (msg)
    (if undone
      (progn (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
             (setq undone nil))
      (if begun (princ "\nStopped part-way.")))
    (princ))
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") (setq undone t)))
  (setq begun t)
  (getpoint "\nPick: ")
  (if undone (command "_.UNDO" "_End"))
  (princ))
"""
out = run(THREE)
check("a close in the then-arm of (if flag ... else) is clean",
      not out, out)

# LINGUTTER -> PADDLE, and the tutorial demo -> autobead-build: a
# handoff set just before the call and spent by the callee on entry.
# The call itself is not a place the caller's handler can run from.
SPENT = HANDOFF_BAD.replace(
    '  (getpoint "\\nPad: ")\n  (setq h *q3-hand* *q3-hand* nil)',
    '  (setq h *q3-hand* *q3-hand* nil)\n  (getpoint "\\nPad: ")')
out = run(SPENT)
check("a handoff the callee spends on entry is not a leftover",
      not out, out)


print("== the baseline ==")

out = run(STALE_ESC, {('cases.lsp', 'c:ste', 'STALE', 't2:*ask*'): 'r'})
check("a baselined finding is not reported", not flagged(out, 'C:STE',
                                                         'STALE'), out)
out = run(STALE_ESC, {('cases.lsp', '*', 'STALE', 't2:*ask*'): 'r'})
check("...nor under a * line for a global kept between runs",
      not flagged(out, 'C:STE', 'STALE'), out)
out = run(STALE_ESC, {('cases.lsp', '*', 'EXIT', 't2:*ask*'): 'r'})
check("...and a * line accepts its own rule only",
      flagged(out, 'C:STE', 'STALE'), out)
out = run(EXIT_UNDO, {('cases.lsp', '*', 'EXIT', 'undo'): 'r'})
check("* is not a wildcard for an EXIT: the site is still reported",
      flagged(out, 'C:EXU', 'EXIT'), out)
out = run(EXIT_UNDO, {('cases.lsp', 'c:exu', 'EXIT', 'undo'): 'r'},
          name='CASES_092326_REV1.lsp')
check("a releases/ twin's dated name matches the file's own line",
      not flagged(out, 'C:EXU', 'EXIT'), out)

with tempfile.TemporaryDirectory() as d:
    bl = pathlib.Path(d) / 'base.txt'
    bl.write_text("# a comment\n"
                  "CASES.lsp|*|STALE|t2:*ask*|kept between runs\n"
                  "CASES.lsp|*|EXIT|undo|an exit is one site\n"
                  "CASES.lsp|c:q2|NOSUCH|undo|no such rule\n"
                  "CASES.lsp|c:q2|EXIT|undo|\n"
                  "CASES.lsp|c:q2|EXIT\n", encoding='utf-8')
    base, bad = check_leaks.load_baseline(bl)
check("load_baseline keeps a * STALE line",
      ('cases.lsp', '*', 'STALE', 't2:*ask*') in base, base)
check("...and calls a * EXIT line, an unknown rule, a missing reason "
      "and a short line malformed", [n for n, _ in bad] == [3, 4, 5, 6], bad)


def run_main(text, baseline):
    """check_leaks.main() over TEXT as every tier, with BASELINE as its
    baseline file: the exit code and what it printed."""
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        tiers = {}
        for t in ('lisp', 'shared', 'releases'):
            (d / t).mkdir()
            (d / t / 'CASES.lsp').write_text(text, encoding='utf-8')
            tiers[t] = (d / t, t + '/')
        bl = d / 'base.txt'
        bl.write_text(baseline, encoding='utf-8')
        saved = check_leaks.BASELINE, check_leaks.TIERS
        check_leaks.BASELINE, check_leaks.TIERS = bl, tiers
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                rc = check_leaks.main([])
        finally:
            check_leaks.BASELINE, check_leaks.TIERS = saved
        return rc, buf.getvalue()


# the exit code, one cause at a time: each of the three reasons to fail
# is the ONLY thing wrong in its run, and a clean run passes
rc, said = run_main(EXIT_UNDO, "")
check("a finding outside the baseline fails the run (exit 1)",
      rc == 1 and ' C:EXU EXIT -- ' in said, said)
rc, said = run_main(EXIT_UNDO, "CASES.lsp|c:exu|EXIT|undo|read, fine\n")
check("...and passes once a line accepts it (exit 0)",
      rc == 0 and 'EXIT' not in said.replace('[baselined]', ''), said)
rc, said = run_main(THREE, "CASES.lsp|c:q2|EXIT|undo|nothing matches\n")
check("a baseline line nothing matches is reported stale, and fails",
      rc == 1 and 'nothing matches this line' in said, said)
rc, said = run_main(THREE, "CASES.lsp|c:q2|NOSUCH|undo|no such rule\n")
check("a malformed baseline line is reported, and fails",
      rc == 1 and 'is not file|defun' in said, said)
rc, said = run_main(THREE, "")
check("a clean tree with an empty baseline passes", rc == 0, said)

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nevery check_leaks rule fires on its leak, and the right shapes pass")
