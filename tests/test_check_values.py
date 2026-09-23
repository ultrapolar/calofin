#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_values.py on made files: every rule fires on the shape it
exists for, and stays quiet on the shapes that are right -- the fixes
included, so a site repaired the recommended way stops failing.

The class is a builtin whose answer the test VM gave more kindly than
AutoCAD does: rtos ignoring DIMZIN (a whole foot printed 15'-0" in the
VM and 15' in acad.dwt), rtos rounding a shown limit up, vl-sort
dropping equal REALS (it drops only EQ items), vlax-get-object and
vlax-create-object throwing where they answer nil, angtos digits read
back through the drafter's angle settings.  The tree is not read here --
the check itself does that; this pins what each rule means.

Run: python3 tests/test_check_values.py
"""

import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_values  # noqa: E402

FAILS = []
COUNT = [0]


def check(label, cond, detail=''):
    COUNT[0] += 1
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def rules(text):
    """{defun: [rule, ...]} for one made file."""
    out = {}
    for h in check_values.scan_text(text, 'CASES.lsp'):
        out.setdefault(h.defun, []).append(h.rule)
    return out


def fires(got, d, rule, why):
    check(f"{d}: {why}", rule in got.get(d, []), got)


def quiet(got, d, rule, why):
    check(f"{d}: quiet -- {why}", rule not in got.get(d, []), got)


# ---------------------------------------------------------------------
print("== rtos-ftin: which modes can come out feet-inch ==")
#: every formatter below is written into the drawing by f:draw, so what
#: is pinned here is the MODE half of the rule
MODES = r"""
(defun f:put (s p)
  (entmakex (list '(0 . "TEXT") (cons 10 p) (cons 40 1.0) (cons 1 s))))
(defun f:arch (v) (rtos v 4 4))
(defun f:eng (v) (rtos v 3 2))
(defun f:knob (v) (rtos v f:*mode* 2))
(defun f:truthy (v) (if f:*mode* (rtos v f:*mode* 2) ""))
(defun f:numberp (v m) (if (and m (numberp m)) (rtos v m 2) ""))
(defun f:computed (v sty) (rtos v (f:mode-of sty) 2))
(defun f:then (v m) (if (member m '(3 4)) (rtos v m 2) ""))
(defun f:clause4 (v m)
  (cond ((= m 4) (f:ftin v 4 2))
        (T (rtos v m 2))))
(defun f:bare (v) (rtos v))
(defun f:decimal (v) (rtos v 2 2))
(defun f:dispatch (v m)
  (if (member m '(3 4)) (f:ftin v m 2) (rtos v m 2)))
(defun f:clause34 (v m)
  (cond ((member m '(4 3)) (f:ftin v m 2))
        (T (rtos v m 2))))
(defun f:own (v m) (cond ((= m 2) (rtos v m 2)) (T "")))
(defun f:not (v m) (if (not (member m '(3 4))) (rtos v m 2) ""))
(defun f:less (v m) (if (< m 3) (rtos v m 2) ""))
(defun f:lunits (v)
  (if (member (getvar "LUNITS") '(3 4))
    (f:ftin v (getvar "LUNITS") (getvar "LUPREC"))
    (rtos v)))
(defun f:alias (v / u)
  (setq u (getvar "LUNITS"))
  (if (or (= u 3) (= u 4)) (f:ftin v u 4) (rtos v)))
(defun f:nilor2 (v m) (if (or (null m) (= m 2)) (rtos v m 2) ""))
(defun f:ftin (v mode prec / den tot ft n in num g)
  (setq den (expt 2 prec)
        tot (fix (+ (* (abs v) den) 0.5))
        ft  (/ tot (* 12 den))
        n   (- tot (* ft 12 den))
        in  (/ n den)
        num (- n (* in den)))
  (strcat (if (minusp v) "-" "") (itoa ft) "'-" (itoa in)
          (if (= num 0) ""
              (progn (setq g (gcd num den))
                     (strcat " " (itoa (/ num g)) "/" (itoa (/ den g)))))
          "\""))
(defun f:draw (v m sty p)
  (foreach s (list (f:arch v) (f:eng v) (f:knob v) (f:truthy v)
                   (f:numberp v m) (f:computed v sty) (f:then v m)
                   (f:clause4 v m) (f:bare v) (f:decimal v)
                   (f:dispatch v m) (f:clause34 v m) (f:own v m)
                   (f:not v m) (f:less v m) (f:lunits v) (f:alias v)
                   (f:nilor2 v m))
    (f:put s p)))
"""
got = rules(MODES)
for d, why in (('f:arch', "mode 4, the 15' notation the review tools reject"),
               ('f:eng', 'mode 3 follows DIMZIN too'),
               ('f:knob', 'a knob mode nobody looked at'),
               ('f:truthy', 'a knob tested only for being set'),
               ('f:numberp', 'a knob tested only for being a number'),
               ('f:computed', 'a computed mode'),
               ('f:then', "rtos in the THEN branch of (member m '(3 4))"),
               ('f:clause4', 'a cond that sends 4 away still lets 3 through'),
               ('f:bare', "no mode: the drawing's LUNITS, feet-inch in a "
                          "pool drawing")):
    fires(got, d, 'rtos-ftin', why)
for d, why in (('f:decimal', 'decimal is not feet-inch'),
               ('f:dispatch', "a knob mode in the else of (member m '(3 4))"),
               ('f:clause34', 'a cond clause before it took 3 and 4'),
               ('f:own', "the rtos clause's own test pins the mode to 2"),
               ('f:not', "(not (member m '(3 4))) in front of it"),
               ('f:less', '(< m 3) in front of it'),
               ('f:lunits', "no mode, behind a test of (getvar \"LUNITS\")"),
               ('f:alias', 'no mode, behind a test of a local set from '
                           'LUNITS'),
               ('f:nilor2', 'a mode that is nil or 2 (a set mode is never '
                            'nil)'),
               ('f:ftin', 'the arithmetic :ftin the fix introduces')):
    quiet(got, d, 'rtos-ftin', why)

# ---------------------------------------------------------------------
print("== rtos-ftin: text written into the drawing, not text printed ==")
SINKS = r"""
(defun w:put (s p)
  (entmakex (list '(0 . "TEXT") (cons 10 p) (cons 40 1.0) (cons 1 s))))
(defun w:direct (v p)
  (entmakex (list '(0 . "TEXT") (cons 10 p) (cons 1 (strcat "L=" (rtos v 4 4))))))
(defun w:local (v p / s)
  (setq s (strcat "off by " (rtos v 4 4)))
  (entmakex (list '(0 . "TEXT") (cons 10 p) (cons 1 s))))
(defun w:param (v p) (w:put (rtos v 4 4) p))
(defun w:row (v) (setq w:*rows* (cons (strcat "Dim " (rtos v 4 4)) w:*rows*)))
(defun w:stash (v) (setq w:*draft* (cons (rtos v 4 4) w:*draft*)))
(defun w:publish () (setq w:*rows* (append w:*rows* w:*draft*)))
(defun w:add (s) (setq w:*log* (cons s w:*log*)))
(defun w:logged (v) (w:add (rtos v 4 4)))
(defun w:report (p / txt)
  (setq txt "")
  (foreach r (append w:*rows* w:*log*) (setq txt (strcat txt "\\P" r)))
  (w:mtext p txt))
(defun w:mtext (p text / dxf)
  (setq dxf (list '(0 . "MTEXT") (cons 10 p)))
  (while (> (strlen text) 250)
    (setq dxf  (append dxf (list (cons 3 (substr text 1 250))))
          text (substr text 251)))
  (entmakex (append dxf (list (cons 1 text)))))
(defun w:entmod (e v / ed)
  (setq ed (entget e))
  (entmod (subst (cons 1 (rtos v 4 3)) (assoc 1 ed) ed)))
(defun w:vla (o v) (vla-put-textstring o (rtos v 4 4)))
(defun w:addmtext (sp p v) (vla-addmtext sp p 10.0 (rtos v 4 4)))
(defun w:dimtext (p1 p2 p3 v)
  (command "_.DIMLINEAR" p1 p2 "_T" (rtos v 4 4) p3))
(defun w:leader (p1 p2 v) (command "_.LEADER" p1 p2 "" (rtos v 4 4) ""))
(defun w:mapcar (vs p)
  (mapcar '(lambda (s) (w:put s p)) (mapcar '(lambda (v) (rtos v 4 4)) vs)))
(defun w:apply (v p) (apply 'w:put (list (rtos v 4 4) p)))

(defun w:say (v) (princ (strcat "\nThe run is " (rtos v 4 4) ".")))
(defun w:prompt (v) (getdist (strcat "\nOffset <" (rtos v 4 4) ">: ")))
(defun w:alert (v) (alert (strcat "Too long by " (rtos v 4 4))))
(defun w:size (v) (* 0.75 (strlen (rtos v 4 4))))
(defun w:echo (s) s)
(defun w:echo-said (v) (princ (w:echo (rtos v 4 4))))
(defun w:echo-drawn (v p) (w:put (w:echo (rtos v 4 4)) p))
(defun w:colour (e v / row ed)
  (setq row (list (rtos v 4 4) 1)
        ed  (entget e))
  (entmod (subst (cons 62 (cadr row)) (assoc 62 ed) ed)))
(defun w:point (v / p)
  (setq p (list (rtos v 4 4) 0.0))
  (entmake (list '(0 . "POINT") (list 10 (car p) (cadr p) 0.0))))
(defun w:chunk (v p / s)
  (setq s (strcat "{\\H1.2x;" (rtos v 4 4) "}"))
  (entmakex (list '(0 . "MTEXT") (cons 10 p) (cons 3 s) (cons 1 ""))))
(defun w:label (s) (if (> (strlen s) 8) "long" "short"))
(defun w:labelled (v p) (w:put (w:label (rtos v 4 4)) p))
(defun w:xdata (e v)
  (entmod (append (entget e)
                  (list (list -3 (list "APP" (cons 1000 (rtos v 4 4))))))))
"""
got = rules(SINKS)
for d, why in (('w:direct', 'straight into a TEXT group 1'),
               ('w:local', 'through a local'),
               ('w:param', "through a helper's argument that it writes"),
               ('w:row', 'into a global row list a report writes'),
               ('w:stash', 'into a global that is later copied into that '
                           'row list'),
               ('w:logged', "through a helper's argument into a global"),
               ('w:entmod', 'an entmod that substitutes group 1'),
               ('w:vla', 'vla-put-textstring'),
               ('w:addmtext', 'vla-addmtext'),
               ('w:dimtext', 'the argument after "_T" in a DIM command'),
               ('w:leader', "a LEADER's note"),
               ('w:mapcar', 'through mapcar lambdas'),
               ('w:chunk', "an MTEXT's leading group 3 chunk"),
               ('w:apply', 'through apply')):
    fires(got, d, 'rtos-ftin', why)
for d, why in (('w:say', 'a princ is read by the drafter, in their DIMZIN'),
               ('w:prompt', 'a prompt default'),
               ('w:alert', 'an alert'),
               ('w:size', 'a width estimate, never written'),
               ('w:echo-said', 'a helper that returns its argument, '
                               'called here only to print'),
               ('w:colour', 'a list that also holds text, but only its '
                            'colour goes into the entity'),
               ('w:point', '(list 10 x y z) is a point, not text'),
               ('w:labelled', 'a helper reads the text and draws a word of '
                              'its own'),
               ('w:xdata', 'xdata (1000) is never shown')):
    quiet(got, d, 'rtos-ftin', why)
fires(got, 'w:echo-drawn', 'rtos-ftin',
      "the same pass-through helper, its answer drawn by this caller (and "
      "only this caller's site goes red: w:echo-said stays quiet)")
out = [h for h in check_values.scan_text(SINKS, 'CASES.lsp')
       if h.defun == 'w:param']
check("the finding names the way into the drawing",
      out and 'entmakex in w:put' in out[0].note, out)

# ---------------------------------------------------------------------
print("== rtos-shape: rtos text cut by position or read as a value ==")
SHAPE = r"""
(defun s:date () (rtos (getvar "CDATE") 2 6))
(defun s:datelocal (/ d) (setq d (getvar "CDATE")) (rtos d 2 6))
(defun s:slice (x) (substr (rtos x 2 6) 1 4))
(defun s:local (x / s) (setq s (rtos x 2 6)) (substr s 1 4))
(defun s:search (x) (vl-string-search "." (rtos x 2 3)))
(defun s:read (x) (read (rtos x 2 2)))
(defun s:atof (x) (atof (rtos x 2 2)))
(defun s:pad (x / s) (setq s (rtos x 2 2)) (while (< (strlen s) 8) (setq s (strcat " " s))) s)
(defun s:arith (/ d dd)
  (setq d (getvar "CDATE") dd (fix d))
  (strcat (itoa (fix (/ dd 10000))) "-" (itoa (rem (fix (/ dd 100)) 100))))
"""
got = rules(SHAPE)
for d, why in (('s:date', 'CDATE handed straight to rtos'),
               ('s:datelocal', 'CDATE through a local'),
               ('s:slice', 'substr of rtos text'),
               ('s:local', 'substr of a local set from rtos'),
               ('s:search', 'vl-string-search in rtos text'),
               ('s:read', 'read of rtos text: "12" reads as an INTEGER')):
    fires(got, d, 'rtos-shape', why)
for d, why in (('s:atof', 'atof reads the same value whatever DIMZIN trims'),
               ('s:pad', 'strlen for padding is not a position'),
               ('s:arith', 'CDATE decoded arithmetically, as cal:datestr')):
    quiet(got, d, 'rtos-shape', why)

# ---------------------------------------------------------------------
print("== rtos-bound: a shown limit the re-ask loop refuses ==")
BOUND = r"""
(defun b:max (msg cap / v)
  (setq v (getdist msg))
  (while (> v (+ cap 1e-6))
    (princ (strcat "\nToo large -- max " (rtos cap) ".  Re-enter."))
    (setq v (getdist msg)))
  v)
(defun b:between (msg lo hi / v)
  (setq v (b:ask msg))
  (while (or (< v lo) (> v hi))
    (princ (strcat "\nMust be between A (" (rtos lo) ") and B (" (rtos hi) ")."))
    (setq v (b:ask msg)))
  v)
(defun b:orless (msg h / v)
  (setq v (b:ask msg))
  (while (> (* 2.0 v) (+ h 1e-6))
    (princ (strcat "\nA " (rtos v) " bulge breaks out of a " (rtos h)
                   " envelope.  " (rtos (/ h 2.0)) " or less."))
    (setq v (b:ask msg)))
  v)
(defun b:echo (msg cap / v)
  (setq v (getdist msg))
  (while (> v cap)
    (princ (strcat "\nThe max is " (rtos cap) ", you typed " (rtos v)))
    (setq v (getdist msg)))
  v)
(defun b:prevsentence (msg cap / v)
  (setq v (getdist msg))
  (while (> v cap)
    (princ (strcat "\nThat is over the max.  " (rtos v) " was typed."))
    (setq v (getdist msg)))
  v)
(defun b:colon (msg cap / v)
  (setq v (getdist msg))
  (while (> v cap)
    (princ (strcat "\nRadius too large (maximum: " (rtos cap) ")."))
    (setq v (getdist msg)))
  v)
(defun b:newline (msg cap / v)
  (setq v (getdist msg))
  (while (> v cap)
    (princ (strcat "\nThat is over the max\n" (rtos v) " was typed."))
    (setq v (getdist msg)))
  v)
(defun b:maxpair (msg cap / v)
  (setq v (getdist msg))
  (while (> v cap)
    (princ (strcat "\nOver the max " (rtos cap) " and D (" (rtos v) ")."))
    (setq v (getdist msg)))
  v)
(defun b:helper (msg cap / v)
  (setq v (getdist msg))
  (while (not (b:fits v cap))
    (princ (strcat "\nToo large -- max " (rtos cap) "."))
    (setq v (getdist msg)))
  v)
(defun b:them (msg / v d)
  (setq v (getdist msg) d (b:gap))
  (while (> d 1.0)
    (princ (strcat "\nThe biggest jump between them is " (rtos d) "."))
    (setq v (getdist msg) d (b:gap v)))
  v)
(defun b:ftin (msg cap / v)
  (setq v (getdist msg))
  (while (> v cap)
    (princ (strcat "\nToo large -- max " (b:ftin cap 4 4) "."))
    (setq v (getdist msg)))
  v)
(defun b:fmt (d) (rtos d 2 3))
(defun b:viafmt (msg cap / v)
  (setq v (getdist msg))
  (while (> v cap)
    (princ (strcat "\nToo large -- max " (b:fmt cap) "."))
    (setq v (getdist msg)))
  v)
(defun b:floored (msg cap / v)
  (setq v (getdist msg))
  (while (> v (+ cap 1e-6))
    (princ (strcat "\nToo large -- max " (rtos (b:floor-shown cap)) "."))
    (setq v (getdist msg)))
  v)
(defun b:strict (msg mn / v)
  (setq v (getdist msg))
  (while (<= v mn)
    (princ (strcat "\nIt has to be more than " (rtos mn) "."))
    (setq v (getdist msg)))
  v)
(defun b:report (run cap)
  (if (> run cap)
    (princ (strcat "\nThe run exceeds the max " (rtos cap) "."))))
(defun b:noask (run cap)
  (while (> run cap)
    (princ (strcat "\nTrimming to the max " (rtos cap) "."))
    (setq run (- run 1.0))))
(defun b:flag (msg cap / v ok)
  (while (not ok)
    (princ (strcat "\nAnything up to the max " (rtos cap) "."))
    (setq v (getdist msg) ok (b:fits v)))
  v)
(defun b:othertest (msg cap / v)
  (setq v (getdist msg))
  (while (> v 100.0)
    (princ (strcat "\nThe max is " (rtos cap) "."))
    (setq v (getdist msg)))
  v)
"""
out = check_values.scan_text(BOUND, 'CASES.lsp')
hit = {(h.defun, h.text) for h in out if h.rule == 'rtos-bound'}
check("b:max: 'max' limit, rounded to nearest, in a loop comparing against it",
      ('b:max', '(rtos cap)') in hit, hit)
check("b:between: both ends of a 'between'",
      {('b:between', '(rtos lo)'), ('b:between', '(rtos hi)')} <= hit, hit)
check("b:orless: the number a trailing 'or less' governs",
      ('b:orless', "(rtos (/ h 2.0))") in hit, hit)
check("...and not the answer echoed, nor the envelope, in that sentence",
      not {('b:orless', '(rtos v)'), ('b:orless', '(rtos h)')} & hit, hit)
check("b:echo: the max, and not the answer echoed after 'max X,'",
      ('b:echo', '(rtos cap)') in hit and ('b:echo', '(rtos v)') not in hit,
      hit)
check("b:maxpair: 'max' governs its own number, not a second one after "
      "'and D ('", ('b:maxpair', '(rtos cap)') in hit
      and ('b:maxpair', '(rtos v)') not in hit, hit)
check("b:helper: a loop whose test hands the limit to a helper",
      ('b:helper', '(rtos cap)') in hit, hit)
check("b:colon: 'maximum: X' is the same limit",
      ('b:colon', '(rtos cap)') in hit, hit)
check("b:ftin: a limit spelled through the tool's own :ftin is read too",
      ('b:ftin', '(b:ftin cap 4 4)') in hit, hit)
check("b:viafmt: ...and through a formatter that returns rtos of its "
      "first argument", ('b:viafmt', '(b:fmt cap)') in hit, hit)
for d, why in (('b:prevsentence', 'the limit word is in the sentence '
                                  'before'),
               ('b:newline', 'the limit word is on the line before'),
               ('b:them', "'between' that governs 'them', not the number"),
               ('b:floored', 'the limit is floored for display (the fix)'),
               ('b:strict', "a strict 'more than' refuses its own number by "
                            "design"),
               ('b:report', 'a report, not a loop that asks again'),
               ('b:noask', 'a while that never asks'),
               ('b:flag', 'a loop whose test is a flag, not this number'),
               ('b:othertest', 'a loop whose test is not about this '
                               'number')):
    check(f"{d}: quiet -- {why}", not any(x == d for x, _ in hit), hit)

# ---------------------------------------------------------------------
print("== vl-sort-dedupe: a sort trusted to drop equal reals ==")
SORT = r"""
;; every radius, ascending.  vl-sort drops a duplicate, so an extra
;; already on the series is not offered twice.
(defun v:trusts (lst) (vl-sort lst '<))

;; the same belief, but the sort is given a tie-break, so nothing is
;; ever equal -- vl-sort drops a duplicate otherwise
(defun v:tiebreak (lst)
  (vl-sort lst '(lambda (a b) (or (< (car a) (car b)) (< (cadr a) (cadr b))))))

;; sorted break points, near-coincident ones merged
(defun v:merged (ds / prev out)
  (setq prev -1.0)
  (foreach d (vl-sort ds '<)
    (if (> (- d prev) 1e-6) (setq out (cons d out) prev d)))
  out)

;; Sorting here makes "tightest first" true however it was typed, and
;; drops anything that is not a usable tolerance.
(defun v:filter (lst) (vl-sort (vl-remove-if-not 'numberp lst) '<))
"""
got = rules(SORT)
fires(got, 'v:trusts', 'vl-sort-dedupe',
      'the comment relies on vl-sort to dedupe reals')
for d, why in (('v:tiebreak', 'a lambda comparator with a tie-break'),
               ('v:merged', 'the dedupe is the loop after the sort'),
               ('v:filter', "'drops' is about the filter, not the sort")):
    quiet(got, d, 'vl-sort-dedupe', why)

# ---------------------------------------------------------------------
print("== getobject-nil: nothing running answers nil, not an error ==")
GETOBJ = r"""
(defun g:bad (/ xl)
  (setq xl (vl-catch-all-apply 'vlax-get-object (list "Excel.Application")))
  (if (vl-catch-all-error-p xl)
    (setq xl (vl-catch-all-apply 'vlax-create-object (list "Excel.Application"))))
  xl)
(defun g:create (/ sh)
  (setq sh (vl-catch-all-apply 'vlax-create-object (list "WScript.Shell")))
  (cond ((vl-catch-all-error-p sh) nil)
        (t (vlax-invoke-method sh 'Run "cmd" 0 :vlax-true))))
(defun g:null (/ xl)
  (setq xl (vl-catch-all-apply 'vlax-get-object (list "Excel.Application")))
  (if (or (null xl) (vl-catch-all-error-p xl))
    (setq xl (vlax-create-object "Excel.Application")))
  xl)
(defun g:and (/ xl)
  (setq xl (vl-catch-all-apply 'vlax-get-object (list "Excel.Application")))
  (if (and xl (not (vl-catch-all-error-p xl))) xl))
(defun g:condnull (id / r)
  (setq r (vl-catch-all-apply 'vlax-create-object (list id)))
  (cond ((vl-catch-all-error-p r) (princ (vl-catch-all-error-message r)))
        ((null r) (princ "came back nil"))
        (t r)))
(defun g:ifelse (id / r)
  (setq r (vl-catch-all-apply 'vlax-create-object (list id)))
  (if (vl-catch-all-error-p r) nil (if r r)))
(defun g:lambda (/ sh err)
  (setq err (vl-catch-all-apply
              '(lambda ()
                 (setq sh (vlax-create-object "WScript.Shell"))
                 (vlax-invoke-method sh 'Run "cmd" 0 :vlax-true))
              '()))
  (if (vl-catch-all-error-p err) nil t))
"""
got = rules(GETOBJ)
fires(got, 'g:bad', 'getobject-nil',
      'vl-catch-all-error-p alone sends nil down the running branch')
fires(got, 'g:create', 'getobject-nil',
      'vlax-create-object answers nil too (nothing registered)')
for d, why in (('g:null', '(null xl) beside it'),
               ('g:and', 'xl tested for itself in the same (and ...)'),
               ('g:condnull', 'a later cond clause takes the nil'),
               ('g:ifelse', "the if's else branch tests it for itself"),
               ('g:lambda', 'err is the catch of a lambda, not the object')):
    quiet(got, d, 'getobject-nil', why)

# ---------------------------------------------------------------------
print("== typed-angle: angtos digits read through the drafter's settings ==")
ANGLE = r"""
(defun a:direct (p1 p2 p3 ang)
  (command "_.DIMLINEAR" p1 p2 "_R" (angtos ang 0 6) p3))
(defun a:local (p1 p2 p3 ang / s)
  (setq s (angtos ang 0 6))
  (vl-cmdf "_.DIMLINEAR" p1 p2 "_R" s p3))
(defun a:prose (ang) (princ (strcat "\nat " (angtos ang 0 2) " degrees")))
"""
got = rules(ANGLE)
fires(got, 'a:direct', 'typed-angle',
      'angtos typed into a command, angle settings not borrowed')
fires(got, 'a:local', 'typed-angle', '...through a local, into vl-cmdf')
quiet(got, 'a:prose', 'typed-angle', 'angtos only printed')
BORROWED = ANGLE + r"""
(defun a:borrow ()
  (setvar "ANGBASE" 0.0) (setvar "ANGDIR" 0) (setvar "AUNITS" 0))
"""
got = rules(BORROWED)
check("quiet in a file that borrows ANGBASE, ANGDIR and AUNITS",
      not any('typed-angle' in r for r in got.values()), got)

# ---------------------------------------------------------------------
print("== baseline: fine sites accepted with a reason, never silently ==")
TWICE = r"""
(defun k:two (v p)
  (entmakex (list '(0 . "TEXT") (cons 10 p)
                  (cons 1 (strcat (rtos v 4 4) " / " (rtos v 4 4))))))
(defun k:gone (v) (rtos v 2 2))
"""
hits = check_values.scan_text(TWICE, 'CASES.lsp')
k = check_values.key(hits[0])
line = "|".join(k) + "|"


def against(tmp, text):
    base = pathlib.Path(tmp) / 'values_baseline.txt'
    base.write_text(text, encoding='utf-8')
    return check_values.compare(hits, check_values.load_baseline(base))


with tempfile.TemporaryDirectory() as tmp:
    check("the two sites are one key (the case the pairing is for)",
          len(hits) == 2 and check_values.key(hits[1]) == k, hits)
    new, stale, ok = against(
        tmp, "# made\n" + line + "the reason\n"
        + "CASES.lsp|k:gone|rtos-ftin|(rtos v 4 4)|a site since fixed\n")
    check("one line accepts one of two identical sites, not both",
          len(ok) == 1 and len(new) == 1, (new, ok))
    check("a line whose site has gone is reported stale",
          [s[0][1] for s in stale] == ['k:gone'], stale)

    new, stale, ok = against(tmp, line + check_values.UNREVIEWED + "\n")
    check("an UNREVIEWED line accepts nothing", len(new) == 2 and not ok,
          (new, ok))
    new, stale, ok = against(tmp, line + "unreviewed\n")
    check("...in any case", len(new) == 2 and not ok, (new, ok))
    new, stale, ok = against(tmp, line + "   \n")
    check("a line with no reason accepts nothing", len(new) == 2 and not ok,
          (new, ok))
    new, stale, ok = against(tmp, line + check_values.UNREVIEWED + "\n"
                             + line + "a real reason\n")
    check("reasons pair with sites line by line: UNREVIEWED then a reason "
          "accepts the second site only",
          ok == {id(hits[1])} and new == [hits[0]], (new, ok))
    new, stale, ok = against(tmp, line + "a real reason\n"
                             + line + check_values.UNREVIEWED + "\n")
    check("...and a reason then UNREVIEWED the first only",
          ok == {id(hits[0])} and new == [hits[1]], (new, ok))

    pipe = check_values.scan_text(
        '(defun k:pipe (v) (substr (rtos v 2 2) 1 (strlen "a|b")))',
        'CASES.lsp')[0]
    base = pathlib.Path(tmp) / 'values_baseline.txt'
    base.write_text("|".join(check_values.key(pipe)) + "|piped\n",
                    encoding='utf-8')
    check("an excerpt holding a | survives the round trip",
          '|' in pipe.text and check_values.compare(
              [pipe], check_values.load_baseline(base))[0] == [], pipe)

    base.write_text(line + "kept reason\n", encoding='utf-8')
    n = check_values.write_baseline(hits, check_values.load_baseline(base),
                                    base)
    text = base.read_text(encoding='utf-8')
    check("--update-baseline keeps a reason and writes the new site "
          "UNREVIEWED", n == 1 and "|kept reason\n" in text
          and text.count("|" + check_values.UNREVIEWED + "\n") == 1, text)

# ---------------------------------------------------------------------
print("== what it reads: the hand-edited sources, once ==")
names = {p.name for p in check_values.sources()}
check("the library, the loader and LISPLAB's hand-kept twin are read",
      {'CALOFIN-LIB.lsp', 'CALOFIN-LOADER.lsp'} <= names
      and any(p.parts[-2] == 'parts' and p.name == 'LISPLAB.lsp'
              for p in check_values.sources()), sorted(names)[:5])
check("a generated twin is not (it is its lisp/ file, regenerated)",
      not any(p.parts[-2] == 'parts' and p.name == 'POOL.lsp'
              for p in check_values.sources()))
check("the deprecated acady matcher is not",
      not any('standards_checker' in p.parts for p in check_values.sources()))

if FAILS:
    print(f"\n{len(FAILS)} of {COUNT[0]} FAILED")
    sys.exit(1)
print(f"\nall {COUNT[0]} check_values checks pass: every rule fires, and "
      "the right shapes pass")
