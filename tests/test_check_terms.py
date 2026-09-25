#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_terms.py on made files: every rule fires on the shape it
exists for and stays quiet on the shapes that are right.

The class is a SHOP TERM written around its knob: a tool that spells
" Typ." or "Not Given" itself draws the shipped wording in a shop that
chose another, beside callouts that follow the shop's -- and no test
that runs with an empty profile can see it.  The tree is not read here
(check_terms itself does that, and tests/test_terms.py asserts it is
clean); this pins what each rule means.

Run: python3 tests/test_check_terms.py
"""

import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_terms  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + str(detail)) if detail else ''))
        FAILS.append(label)


TERMS = [dict(id='typ-note', default=' Typ.', kind='label', meaning='m',
              members=['tt:*typ-note*']),
         dict(id='ng-note', default='Not Given', kind='label', meaning='m',
              members=['tt:*ng-note*'])]

READER = check_terms.READER.format(p='tt:')

GOOD = (READER + "\n\n"
        ";;; -------------------- tunables ------------------------------\n"
        ";; the suffix on the one callout that stands for its group\n"
        '(setq tt:*typ-note* (tt:term "typ-note" " Typ."))\n'
        ";; the note on a corner never given\n"
        '(setq tt:*ng-note* (tt:term "ng-note" "Not Given"))\n'
        ";;; -------------------- code ----------------------------------\n"
        '(defun tt:draw () (command "_.LEADER" p q "" tt:*ng-note* ""))\n'
        ';; a comment naming " Typ." is not code\n'
        '(defun tt:say () (princ))\n')
TWIN = GOOD.replace(READER + "\n\n", "").replace('(tt:term ', '(cal:term ')
SWAPS = {'lisp/tt/TT.lsp': {'tt:term': 'cal:term'}}
TWINS = {'shared/parts/TT.lsp': 'lisp/tt/TT.lsp'}


def run(lisp, twin=None, baseline='', swaps=SWAPS):
    files = {'lisp/tt/TT.lsp': lisp}
    if twin is not None:
        files['shared/parts/TT.lsp'] = twin
    with tempfile.TemporaryDirectory() as d:
        b = pathlib.Path(d) / 'terms_baseline.txt'
        b.write_text(baseline)
        problems, _ = check_terms.run(files=files, baseline=b, terms=TERMS,
                                      twin_src=TWINS, swaps=swaps)
    return problems


def has(problems, tag):
    return [p for p in problems if p.startswith(tag) or (' ' + tag) in p[:12]]


print("== quiet: a tool that reads both terms through its knobs ==")
p = run(GOOD, TWIN)
check("the good file and its twin are clean", not p, p)
# a comment spelling the wording is not code
check("a ;; comment naming \" Typ.\" is not read",
      not check_terms.scan_text('; " Typ." here\n(princ)\n', 'x', TERMS))

print("== T1: a member not read through its term ==")
bad = GOOD.replace('(setq tt:*typ-note* (tt:term "typ-note" " Typ."))',
                   '(setq tt:*typ-note* " Typ.")')
p = run(bad, TWIN)
check("a bare literal on a member fires T1", has(p, 'T1'), p)
bad = GOOD.replace('(tt:term "typ-note" " Typ.")', '(tt:term "typ-note" " TYP")')
p = run(bad, TWIN.replace('(cal:term "typ-note" " Typ.")', '(cal:term "typ-note" " TYP")'))
check("a member shipping another literal fires T1", any('default' in x for x in has(p, 'T1')), p)
bad = GOOD.replace('(tt:term "typ-note" " Typ.")', '(tt:term "ng-note" " Typ.")')
p = run(bad, TWIN)
check("a member reading the wrong term fires T1", any('reads term ng-note' in x for x in p), p)
p = run(GOOD, GOOD.replace(READER + "\n\n", ""))
check("a twin still calling tt:term fires T1", any('cal:term' in x for x in has(p, 'T1')), p)
p = run(GOOD, TWIN.replace('(setq tt:*ng-note* (cal:term "ng-note" "Not Given"))\n', ''))
check("a member missing from its twin fires T1", any('twin' in x for x in has(p, 'T1')), p)
p = run(GOOD.replace('(setq tt:*ng-note* (tt:term "ng-note" "Not Given"))\n', ''),
        TWIN.replace('(setq tt:*ng-note* (cal:term "ng-note" "Not Given"))\n', ''))
check("a member no block declares fires T1", any('no tunables' in x for x in p), p)

print("== T2: a knob that ships a term's default but is not a member ==")
bad = GOOD.replace(";;; -------------------- code",
                   ";; another tool's own note\n(setq tt:*corner-note* \"Not Given\")\n"
                   ";;; -------------------- code")
p = run(bad, TWIN)
check("a non-member shipping 'Not Given' fires 'join term ng-note'",
      any('join term ng-note' in x for x in has(p, 'T2')), p)
bad = GOOD.replace(";;; -------------------- code",
                   ";; a different word\n(setq tt:*other* \"Given\")\n"
                   ";;; -------------------- code")
check("...and a different literal does not", not has(run(bad, TWIN), 'T2'))

print("== T3: the wording spelt in code outside the block ==")
bad = GOOD + '(defun tt:mark () (command "_.DIMRADIUS" e p "_T" (strcat "?" " Typ.") q))\n'
p = run(bad, TWIN)
check("a hard-coded ' Typ.' in a drawing defun fires T3",
      any('tt:mark' in x for x in has(p, 'T3')), p)
bad2 = GOOD + '(defun tt:mark () (list (cons 1 "<> Typ.")))\n'
check("...and '<> Typ.' (it CONTAINS the term) fires too",
      any('tt:mark' in x for x in has(run(bad2, TWIN), 'T3')))
line = 'lisp/tt/TT.lsp|tt:mark| Typ.|a reason given'
p = run(bad, TWIN, baseline=line + '\n')
check("a reasoned baseline line quiets it", not has(p, 'T3'), p)
p = run(bad, TWIN, baseline='lisp/tt/TT.lsp|tt:mark| Typ.|\n')
check("a baseline line with no reason fails", any('reason' in x for x in p), p)
p = run(GOOD, TWIN, baseline=line + '\n')
check("a stale baseline line fails", any('stale' in x for x in p), p)
twin_bad = TWIN + '(defun tt:mark () (command "_T" " Typ."))\n'
p = run(bad, twin_bad, baseline=line + '\n')
check("a twin's finding maps to its lisp/ source's baseline line", not has(p, 'T3'), p)
guarded = GOOD + '(defun tt:typ () (if (= (type tt:*typ-note*) (quote STR)) tt:*typ-note* (tt:term "typ-note" " Typ.")))\n'
check("the fallback argument of a term-reader call is not a T3 site",
      not has(run(guarded, TWIN), 'T3'), run(guarded, TWIN))
# a block whose end rule sits far below: knobs.block_of runs over the
# defuns in between (FITABHD's ran over 217) -- they are code all the same
long_block = GOOD.replace(
    ";;; -------------------- code ----------------------------------\n", "") \
    .replace("(defun tt:say () (princ))\n",
             "(defun tt:say () (princ))\n"
             '(defun tt:mutant (p) (command "_.DIMRADIUS" p "_T" "<> Typ." p))\n'
             ";;; -------------------- code ----------------------------------\n")
p = run(long_block, TWIN)
check("a literal in a defun INSIDE a long tunables block's span fires T3",
      any('tt:mutant' in x for x in has(p, 'T3')), p)
check("...while the block's own knob forms stay quiet",
      not any('<top>' in x for x in has(p, 'T3')), p)
bare = GOOD.replace('tt:*ng-note* ""))', '(tt:term "ng-note" "Not Given") ""))')
p = run(bare, TWIN)
check("a bare reader call IN PLACE of the knob fires T3 (it passes a LAZTUNE value by)",
      any('tt:draw' in x for x in has(p, 'T3')), p)
crossed = GOOD + ('(defun tt:typ () (if (= (type tt:*typ-note*) (quote STR)) '
                  'tt:*typ-note* (tt:term "typ-note" "Not Given")))\n')
p = run(crossed, TWIN)
check("a fallback that is ANOTHER term's default fires T3",
      any('tt:typ' in x for x in has(p, 'T3')), p)
check("LAZPANEL's generated catalog is not read",
      not check_terms.scan_text(check_terms.PANEL_BEGIN + ' x\n(setq a " Typ.")\n'
                                + check_terms.PANEL_END + '\n', 'x', TERMS))

print("== T4: the reader ==")
bad = GOOD.replace('(if (and v (/= v "")) v dflt)', '(if v v dflt)')
check("a reader that is not the six-line text fires T4",
      any('not the reader' in x for x in has(run(bad, TWIN), 'T4')))
moved = GOOD.replace(READER + "\n\n", "") + READER + "\n"
check("a reader BELOW the block fires T4",
      any('BELOW' in x for x in has(run(moved, TWIN), 'T4')))
check("a reader the mirror does not swap fires T4",
      any('swap' in x for x in has(run(GOOD, TWIN, swaps={}), 'T4')))

print()
if FAILS:
    print("test_check_terms: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("test_check_terms: all checks passed")
