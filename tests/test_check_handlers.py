#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_handlers.py on made files: every rule fires on the defect
it exists for, and stays quiet on the two shapes that are right.

The SPA incident was a handler that died part-way -- undo group left
open, error mode left pushed, no LAZDIAG report, the message lost -- and
the tests stayed green because the VM ran every handler with the
command's frame still live.  AutoCAD does not: under
*push-error-using-command* it resets the evaluator before *error* runs,
so the handler sees globals only.  Eleven tools had that mix.  The
check reads each handler in evaluation order under the error mode its
command set; these fixtures pin each rule both ways.

Run: python3 tests/test_check_handlers.py
"""

import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_handlers  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def run(text, base=frozenset()):
    """check_handlers over one made file: the lines it printed."""
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / 'CASES.lsp'
        p.write_text(text, encoding='utf-8')
        out = []
        check_handlers.report([p], set(base), False, out=out.append)
        return out


def flagged(out, cmd):
    """The rule tags printed under the handler row of CMD."""
    tags, on = [], False
    for ln in out:
        if not ln.startswith('    '):
            on = (' %s ' % cmd) in ln or ln.endswith(' ' + cmd)
            if ('  H5  ' in ln or '  H6  ' in ln) and (' %s ' % cmd) in ln:
                tags.append('H5' if '  H5  ' in ln else 'H6')
            continue
        if on:
            tags.append(ln.split()[0])
    return tags


CASES = r""";; H1: pushed, handler calls a local helper
(defun c:H1CASE ( / *error* x:fin os)
  (defun x:fin () (if os (setvar "OSMODE" os)))
  (defun *error* (msg) (x:fin) (if lzd:report (lzd:report "H1CASE" nil msg)) (princ))
  (if *push-error-using-command* (*push-error-using-command*))
  (setq os (getvar "OSMODE")))

;; H2 via a global helper that reads the command's local free
(defun h2:close () (if undo-open (command "_.UNDO" "_End")))
(defun c:H2CASE ( / *error* undo-open)
  (defun *error* (msg) (h2:close) (if *pop-error-mode* (*pop-error-mode*))
    (if lzd:report (lzd:report "H2CASE" nil msg)) (princ))
  (if *push-error-using-command* (*push-error-using-command*))
  (setq undo-open T))

;; H3: SPA's old death -- command-s before the pop, inside a catch
(defun c:H3CASE ( / *error*)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" "X"))
    (if *pop-error-mode* (*pop-error-mode*))
    (if lzd:report (lzd:report "H3CASE" nil msg)) (princ))
  (if *push-error-using-command* (*push-error-using-command*)))

;; H3 through a helper
(defun h3:restyle () (command-s "_.-DIMSTYLE" "_Restore" "X"))
(defun c:H3BCASE ( / *error*)
  (defun *error* (msg) (h3:restyle)
    (if *pop-error-mode* (*pop-error-mode*))
    (if lzd:report (lzd:report "H3BCASE" nil msg)) (princ))
  (if *push-error-using-command* (*push-error-using-command*)))

;; H4: no push, bare command in the handler
(defun c:H4CASE ( / *error* undo-open)
  (defun *error* (msg) (if undo-open (command "_.UNDO" "_End"))
    (if lzd:report (lzd:report "H4CASE" nil msg)) (princ))
  (command "_.UNDO" "_Begin") (setq undo-open T))

;; H4 after the pop: mode is default again
(defun c:H4BCASE ( / *error*)
  (defun *error* (msg) (if *pop-error-mode* (*pop-error-mode*))
    (command "_.REGEN")
    (if lzd:report (lzd:report "H4BCASE" nil msg)) (princ))
  (if *push-error-using-command* (*push-error-using-command*)))

;; clean: pushed, globals only, write-before-read is fine
(defun c:OKCASE ( / *error* guard)
  (defun *error* (msg)
    (if ok:*os* (setvar "OSMODE" ok:*os*))
    (setq guard 0)
    (while (and (> (getvar "CMDACTIVE") 0) (< guard 10)) (command) (setq guard (1+ guard)))
    (if *pop-error-mode* (*pop-error-mode*))
    (if lzd:report (lzd:report "OKCASE" nil msg)) (princ))
  (if *push-error-using-command* (*push-error-using-command*))
  (setq ok:*os* (getvar "OSMODE")))

;; clean: no push, locals fine, command-s fine
(defun c:OK2CASE ( / *error* undo-open x:fin)
  (defun x:fin () (princ))
  (defun *error* (msg) (x:fin) (if undo-open (command-s "_.UNDO" "_End"))
    (if lzd:report (lzd:report "OK2CASE" nil msg)) (princ))
  (setq undo-open T))
"""

print("== check_handlers: one fixture per rule ==")
out = run(CASES)
for cmd, rule, why in (
        ('C:H1CASE', 'H1', "a pushed handler calling the command's local helper"),
        ('C:H2CASE', 'H2', "a pushed handler reading a command local through a global helper"),
        ('C:H3CASE', 'H3', "command-s under a push, even caught -- SPA's death"),
        ('C:H3BCASE', 'H3', "the same through a helper"),
        ('C:H4CASE', 'H4', "a bare (command) in a default-mode handler"),
        ('C:H4BCASE', 'H4', "a bare (command) after the handler's own pop")):
    check("%s: %s" % (rule, why), rule in flagged(out, cmd), out)
check("a pushed handler reading only globals is clean",
      not flagged(out, 'C:OKCASE'), out)
check("a default-mode handler using locals and command-s is clean",
      not flagged(out, 'C:OK2CASE'), out)

# H6: a pushing command whose finish pops, then (exit) -- the handler
# runs a second time, in default mode, with nothing left to pop
H6 = r"""
(defun h6:finish () (if *pop-error-mode* (*pop-error-mode*)))
(defun c:H6CASE ( / *error*)
  (defun *error* (msg) (h6:finish)
    (if lzd:report (lzd:report "H6CASE" nil msg)) (princ))
  (if *push-error-using-command* (*push-error-using-command*))
  (h6:finish)
  (exit))
"""
out = run(H6)
check("H6: pop through the finish helper, then (exit)",
      any('H6' in ln and 'C:H6CASE' in ln for ln in out), out)
H6OK = H6.replace("  (h6:finish)\n  (exit))", "  (h6:finish)\n  (princ))")
check("...and the same command ending in (princ) is clean",
      not any('H6' in ln for ln in run(H6OK)), run(H6OK))

# H5: a command that opened its own run calls a defun with its own
# *error* and its own lzd:begin -- a failure in there runs ONLY the inner
# handler, so the outer's undo group and settings are left behind
H5 = r"""
(defun inner:run ( / *error*)
  (defun *error* (msg) (if lzd:report (lzd:report "INNER" nil msg)) (princ))
  (if lzd:begin (lzd:begin "INNER" nil))
  (princ))
(defun c:OUTER ( / *error* os)
  (defun *error* (msg) (if os (setvar "OSMODE" os))
    (if lzd:report (lzd:report "OUTER" nil msg)) (princ))
  (if lzd:begin (lzd:begin "OUTER" nil))
  (setq os (getvar "OSMODE"))
  (setvar "OSMODE" 0)
  (inner:run)
  (setvar "OSMODE" os)
  (princ))
"""
out = run(H5)
check("H5: an outer command's handler shadowed by an inner one",
      any('  H5  ' in ln and 'C:OUTER' in ln for ln in out), out)
out = run(H5, {('C:OUTER', 'inner:run')})
check("...and a pair a person has read and baselined is not a finding",
      not any('  H5  ' in ln for ln in out), out)

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall check_handlers rules fire, and the right shapes pass")
