#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_scope.py on made files: a nested defun's or lambda's own
arglist declares its locals, and nothing else does.

The checker used to read only the OUTER defun's arglist, so every local
of a helper defined inside another function (POOL's pool:quadflow
carries dozens) was reported as an undeclared setq -- 469 false
findings, half the baseline, which is how a real one hides.  These
cases hold the narrower rule both ways: the inner declaration counts
inside the inner span, and only there.

Run: python3 tests/test_check_scope.py
"""

import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_scope  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def findings(src):
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / 'T.lsp'
        p.write_text(src, encoding='utf-8')
        return [(k, v) for _ln, _fn, k, v in check_scope.check_file(p)]


print("== check_scope: nested scopes ==")

f = findings('(defun t:run ( / a)\n'
             '  (defun t:inner (p / b) (setq b (* 2 p)) b)\n'
             '  (setq a (t:inner 1)))\n')
check("a nested defun's own local is declared", ('setq', 'b') not in f, f)

f = findings('(defun t:run ( / a)\n'
             '  (mapcar (function (lambda (x / y) (setq y x))) (list 1))\n'
             '  (setq a 1))\n')
check("a lambda's own local is declared", ('setq', 'y') not in f, f)

f = findings('(defun t:run ( / a)\n'
             '  (defun t:inner (p / b) (setq b p))\n'
             '  (setq b 2 a 1))\n')
check("the inner declaration does not cover the OUTER body",
      ('setq', 'b') in f, f)

f = findings('(defun t:run ( / a)\n  (setq a 1 zz 2))\n')
check("a plain undeclared setq is still reported", ('setq', 'zz') in f, f)

f = findings('(defun t:run ( / a)\n'
             '  (defun t:inner (p) (foreach q p (print q))))\n')
check("an undeclared foreach variable inside a nested defun is reported",
      ('foreach', 'q') in f, f)

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall check_scope cases passed")
