#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_standards.py's one-session collision check, on made files.

LAZPASS.lsp loads every tool into ONE AutoLISP session, where a second
definition of a name does not fail -- it silently replaces the first,
and whichever tool loaded first then runs the other tool's function.
The check used to look only at lines beginning "(defun", so it never saw
a defun NESTED in another function's body, which is just as global the
first time that body runs (POOL and SPA carry dozens), nor two files
setting the same global to different values as they load.  This drives
the check over small files made for the purpose, so each rule is shown
to FIRE -- the real tree is clean, which proves nothing by itself.

Run: python3 tests/test_collisions.py
"""

import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_standards  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def problems_for(files):
    """check_no_collisions over FILES, a {name: text} of made parts."""
    with tempfile.TemporaryDirectory() as d:
        paths = []
        for name, text in files.items():
            p = pathlib.Path(d) / name
            p.write_text(text, encoding='utf-8')
            paths.append(p)
        real = check_standards.shared_members
        check_standards.shared_members = lambda: paths
        try:
            out = []
            check_standards.check_no_collisions(out)
            return out
        finally:
            check_standards.shared_members = real


print("== the one-session collision check ==")

# a top-level defun in two files: the rule that was already there
p = problems_for({'A.lsp': '(defun a:x () 1)\n(defun shared:f () 1)\n',
                  'B.lsp': '(defun b:y () 2)\n(defun shared:f () 2)\n'})
check("a top-level defun in two files fails",
      any('shared:f' in x and 'A.lsp' in x and 'B.lsp' in x for x in p), p)

# a NESTED defun, global once its body runs, against another file's
p = problems_for({
    'A.lsp': '(defun a:run ( / x)\n  (defun qf:geo (p) p)\n  (qf:geo 1))\n',
    'B.lsp': '(defun b:run ()\n  (if t (progn (defun qf:geo (p) (* 2 p)))))\n'})
check("a nested defun colliding with another file's fails",
      any('qf:geo' in x for x in p), p)

# ...but not when the enclosing defun declares it local
p = problems_for({
    'A.lsp': '(defun a:run ( / qf:geo)\n  (defun qf:geo (p) p)\n  (qf:geo 1))\n',
    'B.lsp': '(defun b:run ( / qf:geo)\n  (defun qf:geo (p) (* 2 p)))\n'})
check("a nested defun declared local is private, and passes", not p, p)

# every command nests its own *error*: never a collision
p = problems_for({
    'A.lsp': '(defun c:A ( / *error*) (defun *error* (m) (princ)))\n',
    'B.lsp': '(defun c:B ( / *error*) (defun *error* (m) (princ)))\n'})
check("*error* handlers are not collisions", not p, p)

# the same name twice in ONE file: the second silently wins
p = problems_for({'A.lsp': '(defun a:f () 1)\n(defun a:f () 2)\n'})
check("a name defined twice in one file fails",
      any('a:f' in x and 'twice' in x for x in p), p)

# a global set at load by two files, to different values
p = problems_for({'A.lsp': '(setq *lay* "POOL")\n',
                  'B.lsp': '(setq *lay* "WATER")\n'})
check("a global set to two different values at load fails",
      any('*lay*' in x and '"POOL"' in x and '"WATER"' in x for x in p), p)

# ...the same value twice is one decision, spelled twice: fine
p = problems_for({'A.lsp': '(setq *lay* "POOL")\n',
                  'B.lsp': '(setq *lay* "POOL")\n'})
check("the same value set by two files passes", not p, p)

# ...and a guarded default (the STEPS trio's shape) is not a load-time set
p = problems_for({
    'A.lsp': '(if (not (boundp \'*cs-x*)) (setq *cs-x* 1))\n',
    'B.lsp': '(if (not (boundp \'*cs-x*)) (setq *cs-x* 2))\n'})
check("a boundp-guarded default is not counted as a load-time set", not p, p)

# comments and strings are not code
p = problems_for({'A.lsp': ';; (defun shared:f () 1)\n(setq s "(defun shared:f")\n',
                  'B.lsp': '(defun shared:f () 2)\n'})
check("a defun inside a comment or a string is not a definition", not p, p)

# and the real grouped tier is clean under the wider rule
out = []
check_standards.check_no_collisions(out)
check("the real shared/parts/ tier has no collision", not out, out[:5])

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall collision checks passed")
