#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_input.py on made files: every rule fires on the shape it
exists for, and stays quiet on the shapes that are right.

Two AutoCAD input facts the VM does not model.  A click on empty paper
at an entsel answers nil exactly as Enter does -- only ERRNO 7 tells
them apart, and ERRNO is sticky -- and at every input but
(getstring T ...) the spacebar is Enter.  SPA, SPACOVCREATE,
COVERCHECK, POOL's Given flip and five fit pickers took a missed click
for the Enter default with nothing said; PERPPTS read a 7 an earlier
miss had left and would not let Enter go; fifteen files taught '44 1/2'
at a prompt where the space hands the '1/2' to the next question.  The
check reads each pick's nil in evaluation order and each literal
against the input it prompts for; these fixtures pin each rule both
ways -- a passing shape to the verdict it passes BY, so a pass that
comes the wrong way round is a failure too -- and the baseline and the
exit code both ways.

Run: python3 tests/test_check_input.py
"""

import contextlib
import io
import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_input  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def sites(text, name='CASES.lsp', base=()):
    """check_input over one made file: {defun: [verdict, ...]} for every
    site it reports as failing, and the printed lines."""
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / name
        p.write_text(text, encoding='utf-8')
        out = []
        rows, bad, _ = check_input.report([p], list(base), False,
                                          out=out.append)
        got = {}
        for r in bad:
            got.setdefault(r.defun.lower(), []).append(r.verdict)
        allv = {}
        for r in rows:
            allv.setdefault(r.defun.lower(), []).append(r.verdict)
        return got, allv, out


# ---------------------------------------------------------------------
print("== PICK: a nil that decides, without telling a miss from Enter ==")

PICK = r"""
;; the Enter default taken for a miss: the fit pickers' old shape
(defun bad:default (dflt / sel pick)
  (setq sel (entsel "\nPick the line to keep: "))
  (if lzd:ask (lzd:ask "\nPick the line to keep: " sel) sel)
  (if sel (setq pick (car sel)) (setq pick dflt))
  pick)

;; a pick that IS the loop's test: a miss ends the loop (POOL's old flip)
(defun bad:whiletest ( / sel)
  (while (setq sel (entsel "\nSelect a mark (Enter when done): "))
    (princ "\nflipped"))
  (princ))

;; ...and the same through LAZDIAG's in-place wrapper
(defun bad:wrapped ( / sel)
  (while ((lambda (v) (if lzd:ask (lzd:ask "\nNext: " v) v))
          (setq sel (entsel "\nNext: ")))
    (princ "\nflipped"))
  (princ))

;; a cond clause that turns the nil into a choice (SPACOVCREATE's Skip)
(defun bad:skip ( / v)
  (initget "Type Skip")
  (setq v (entsel "\nSelect the block [Type/Skip] <Skip>: "))
  (cond ((and (= (type v) 'STR) (= v "Type")) 'TYPE)
        ((or (null v) (= (type v) 'STR)) 'SKIP)
        (t (car v))))

;; ERRNO zeroed but never read: the zero alone tells nothing apart
(defun bad:zeronoread ( / sel done)
  (while (not done)
    (setvar "ERRNO" 0)
    (setq sel (entsel "\nPick: "))
    (if (null sel) (setq done T) (princ "\ngot it"))))

;; a nil that only speaks, but nothing comes round again
(defun bad:noloop ( / sel)
  (setq sel (entsel "\nPick: "))
  (if (null sel) (princ "\nNothing selected.") (princ "\nok")))

;; a nil branch that calls a helper which changes something
(defun bad:helper-sets () (setq bad:*gone* T))
(defun bad:sets ( / sel done)
  (while (not done)
    (setq sel (entsel "\nPick: "))
    (cond ((null sel) (bad:helper-sets))
          (t (setq done T)))))

;; in a loop, a nil branch that hands back a VALUE is still a decision
(defun bad:value ( / v r done)
  (while (not done)
    (setq v (entsel "\nSelect the block <Skip>: "))
    (setq r (cond ((null v) 'SKIP) (t (setq done T) (car v)))))
  r)

;; a nil that only speaks, in a loop that goes on to the NEXT item: the
;; miss is a skip of this one for good
(defun bad:use (e) (setq bad:*got* (cons e bad:*got*)))
(defun bad:foreach (names / sel)
  (foreach n names
    (setq sel (entsel (strcat "\nPick the " n " block <skip>: ")))
    (if (null sel) (princ "\n  skipped.") (bad:use (car sel)))))
(defun bad:repeat ( / sel)
  (repeat 3
    (setq sel (entsel "\nPick a mark <skip>: "))
    (if (null sel) (princ "\n  skipped.") (bad:use (car sel)))))
(defun bad:mapcar (names)
  (mapcar '(lambda (n / s) (setq s (entsel (strcat "\nPick " n ": ")))
             (if (null s) (princ "\n skipped") (car s)))
          names))

;; ...and the same in a while's clothes: it moves its own test on
;; every pass, whatever the pick answered
(defun bad:advance (todo / item sel)
  (while (setq item (car todo))
    (setq todo (cdr todo))
    (setq sel (entsel "\nPick the next one <skip>: "))
    (if (null sel) (princ "\n  skipped.") (bad:use (car sel)))))
(defun bad:oneshot ( / sel done)
  (while (not done)
    (setq sel (entsel "\nPick: "))
    (if (null sel) (princ "\n  nothing."))
    (setq done T))
  (if sel (bad:use (car sel))))

;; the pick is a cond clause's test: a nil goes on to the next clause,
;; and that one ends the loop
(defun bad:condtest ( / sel done)
  (while (not done)
    (cond ((setq sel (entsel "\nPick <done>: ")) (princ "\ngot one"))
          (t (setq done T)))))

;; the nil is replaced by a default before anything tests it
(defun bad:overwritten (dflt / sel done)
  (while (not done)
    (setq sel (entsel "\nPick the line <default>: "))
    (setq sel (cond (sel) (dflt)))
    (if (null sel) (princ "\nNothing to keep.") (setq done T))))

;; ...with the exit wrapped in a progn
(defun bad:advance-progn ( / sel done)
  (while (not done)
    (setq sel (entsel "\nPick: "))
    (if (null sel) (princ "\n  nothing."))
    (progn (princ "\nnext") (setq done T)))
  sel)

;; nentselp with a prompt asks the drafter; its nil decides
(defun bad:nentselp ( / sel)
  (setq sel (nentselp "\nPick the text: "))
  (if sel (car sel) bad:*dflt*))

;; --- the right shapes -------------------------------------------------

;; (nentselp pt) is a query at a point, not a question: no site at all
(defun ok:query (pt / hit)
  (setq hit (nentselp pt))
  (if hit (car hit) ok:*dflt*))

;; ERRNO zeroed before each pick, read after it: SPA's readblock
(defun ok:errno ( / sel done)
  (while (not done)
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (setq sel (entsel "\nSelect the block <Enter to skip>: "))
    (if lzd:ask (lzd:ask "\nSelect the block <Enter to skip>: " sel) sel)
    (if lzd:watch (lzd:watch sel) sel)
    (if (and (null sel) (= 7 (getvar "ERRNO")))
      (princ "\nNothing there - click the block, or press Enter to skip.")
      (setq done t)))
  sel)

;; ...and the recursive re-ask of SPACOVCREATE's askblock
(defun ok:recurse ( / v)
  (setvar "ERRNO" 0)
  (setq v (entsel "\nSelect the block <Skip>: "))
  (cond ((and (null v) (= 7 (getvar "ERRNO")))
         (princ "\nNothing there.") (ok:recurse))
        ((null v) 'SKIP)
        (t (car v))))

;; a nil that only says so, in a loop that comes round: UPADOVER
(defun ok:say (msg) (princ (strcat "\n" msg)))
(defun ok:reasks ( / sel stage)
  (setq stage 1)
  (while (= stage 1)
    (setq sel (entsel "\nSelect the perimeter: "))
    (if lzd:watch (lzd:watch sel) sel)
    (cond
      ((null sel) (ok:say "Nothing selected - try again, or press Esc."))
      (t (setq stage 2))))
  sel)

;; the classic idiom: the nil keeps the loop going
(defun ok:whilenot ( / sel)
  (while (not (setq sel (entsel "\nSelect a line: ")))
    (princ "\nMissed - try again."))
  sel)

;; ...and the same through LAZDIAG's in-place wrapper
(defun ok:wrapped ( / sel)
  (while (not ((lambda (v) (if lzd:ask (lzd:ask "\nSelect a line: " v) v))
               (setq sel (entsel "\nSelect a line: "))))
    (princ "\nMissed - try again."))
  sel)

;; a re-ask by recursion alone, no ERRNO anywhere
(defun ok:recurse-only ( / v)
  (setq v (entsel "\nSelect the block: "))
  (cond ((null v) (princ "\nNothing selected - try again.")
                  (ok:recurse-only))
        (t (car v))))

;; a nil that falls through every clause, in a while that comes round
(defun ok:fallthrough ( / sel ent)
  (while (null ent)
    (setq sel (entsel "\nSelect a line: "))
    (cond ((and sel (= "LINE" (cdr (assoc 0 (entget (car sel))))))
           (setq ent (car sel)))
          (sel (princ "\nNot a line."))))
  ent)

;; the pick is a cond clause's test, and the clause a nil goes on to
;; only speaks
(defun ok:condtest ( / sel ent)
  (while (not ent)
    (cond ((setq sel (entsel "\nSelect a line: ")) (setq ent (car sel)))
          (t (princ "\nMissed - try again."))))
  ent)

;; an (or (null sel) ...) clause that only speaks
(defun ok:orspeak ( / sel ent)
  (while (not ent)
    (setq sel (entsel "\nSelect a line: "))
    (cond ((or (null sel) (/= "LINE" (cdr (assoc 0 (entget (car sel))))))
           (princ "\nNot a line - try again."))
          (t (setq ent (car sel)))))
  ent)

;; a keyword clause first: a nil is not "Back", and goes on to the
;; clause that only speaks
(defun ok:keyfirst ( / sel ent)
  (while (not ent)
    (initget "Back")
    (setq sel (entsel "\nSelect a line [Back]: "))
    (cond ((= sel "Back") (setq ent 'BACK))
          ((null sel) (princ "\nNothing selected - try again."))
          (t (setq ent (car sel)))))
  ent)

;; a while whose test is fed by the pick moves on only when it hits
(defun ok:fed ( / sel ent)
  (while (null ent)
    (setq sel (entsel "\nSelect a line: "))
    (setq ent (if sel (car sel)))
    (if (null sel) (princ "\nMissed - try again.")))
  ent)
"""

got, allv, out = sites(PICK)
for name, why in (
        ('bad:default', "a nil that takes the Enter default"),
        ('bad:whiletest', "a pick that is its loop's test"),
        ('bad:wrapped', "...wrapped in LAZDIAG's in-place lambda"),
        ('bad:skip', "a cond clause that makes the nil a Skip"),
        ('bad:zeronoread', "ERRNO zeroed but never read"),
        ('bad:noloop', "a nil that speaks but is never asked again"),
        ('bad:sets', "a nil branch through a helper that sets a global"),
        ('bad:value', "a nil branch in a loop that hands back a value"),
        ('bad:foreach', "a nil that only speaks, in a foreach (next item)"),
        ('bad:repeat', "...in a repeat"),
        ('bad:mapcar', "...in a mapcar lambda"),
        ('bad:advance', "...in a while that advances its list first"),
        ('bad:oneshot', "...in a while that sets its exit every pass"),
        ('bad:advance-progn', "...with that setq inside a progn"),
        ('bad:condtest', "a cond-clause pick whose nil falls to a decision"),
        ('bad:overwritten', "a nil replaced by a default before its test"),
        ('bad:nentselp', "(nentselp \"prompt\") whose nil decides")):
    check("PICK: %s" % why, got.get(name) == ['PICK'], (got.get(name), out))
check("...and a per-item loop is named as a skip for good",
      any('bad:foreach' in ln and 'NEXT item' in ln for ln in out), out)
check("...and an advancing while names the setq that moves it on",
      any('bad:advance' in ln and 'setq todo' in ln for ln in out), out)
check("(nentselp pt) is a query, not a question: no site",
      'ok:query' not in allv, allv.get('ok:query'))
for name, verdict, why in (
        ('ok:errno', 'ok-errno',
         "ERRNO zeroed before each pick and read after"),
        ('ok:recurse', 'ok-errno', "...at the top of a defun that recurses"),
        ('ok:reasks', 'ok-reasks',
         "a nil that only speaks, through a print helper, in a while"),
        ('ok:whilenot', 'ok-reasks',
         "(while (not (setq sel (entsel))) (princ ...))"),
        ('ok:wrapped', 'ok-reasks', "...through LAZDIAG's in-place wrapper"),
        ('ok:recurse-only', 'ok-reasks', "a re-ask by recursion, no ERRNO"),
        ('ok:fallthrough', 'ok-reasks',
         "a nil that falls through the cond, in a while"),
        ('ok:condtest', 'ok-reasks',
         "a cond-clause pick whose nil goes on to a clause that speaks"),
        ('ok:fed', 'ok-reasks', "a while whose test the pick feeds"),
        ('ok:orspeak', 'ok-reasks',
         "an (or (null sel) ...) clause that only speaks"),
        ('ok:keyfirst', 'ok-reasks',
         "a nil that is not the keyword goes on to a clause that speaks")):
    check("passes (%s): %s" % (verdict, why),
          name not in got and allv.get(name) == [verdict],
          (got.get(name), allv.get(name)))


# ---------------------------------------------------------------------
print("== STICKY: ERRNO read without being zeroed in that same pass ==")

STICKY = r"""
;; PERPPTS' old boundary pick: reads 7, never zeroes
(defun bad:never ( / sel bnd)
  (setq bnd 'RETRY)
  (while (eq bnd 'RETRY)
    (setq sel (entsel "\nSelect a boundary [None] <None>: "))
    (cond ((and (null sel) (= 7 (getvar "ERRNO")))
           (princ "\nNothing there."))
          (t (setq bnd (car sel))))))

;; zeroed ONCE, before the loop: the second pass reads the first's 7
(defun bad:once ( / sel bnd)
  (setvar "ERRNO" 0)
  (setq bnd 'RETRY)
  (while (eq bnd 'RETRY)
    (setq sel (entsel "\nSelect a boundary [None] <None>: "))
    (cond ((and (null sel) (= 7 (getvar "ERRNO")))
           (princ "\nNothing there."))
          (t (setq bnd (car sel))))))

;; two picks in one command (PERPPTS): the first re-asks on its own and
;; must NOT borrow the second's zero and read
(defun c:TWOPICKS ( / sel ent bnd)
  (while (null ent)
    (setq sel (entsel "\nSelect a line: "))
    (cond ((null sel) (princ "\nNothing selected - try again."))
          (t (setq ent (car sel)))))
  (setq bnd 'RETRY)
  (while (eq bnd 'RETRY)
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (setq sel (entsel "\nSelect a boundary [None] <None>: "))
    (cond ((and (null sel) (= 7 (getvar "ERRNO")))
           (princ "\nNothing there."))
          (t (setq bnd (if sel (car sel)))))))

;; pick, THEN zero, then read: the miss's 7 is wiped before the read
(defun bad:zeroafter ( / sel done)
  (while (not done)
    (setq sel (entsel "\nPick <done>: "))
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (cond ((and (null sel) (= 7 (getvar "ERRNO"))) (princ "\nNothing there."))
          ((null sel) (setq done T))
          (t (princ "\ngot one")))))

;; ...and zeroed before the pick too: the second zero still wipes it
(defun bad:zerotwice ( / sel done)
  (while (not done)
    (setvar "ERRNO" 0)
    (setq sel (entsel "\nPick <done>: "))
    (setvar "ERRNO" 0)
    (cond ((and (null sel) (= 7 (getvar "ERRNO"))) (princ "\nNothing there."))
          ((null sel) (setq done T))
          (t (princ "\ngot one")))))

;; two picks in one pass, the zero before the FIRST only, the read after
;; the second: the first's nil is kept, and the second reads a 7 the
;; first may have left
(defun bad:twoinone ( / a b done)
  (while (not done)
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (setq a (entsel "\nFirst: "))
    (setq b (entsel "\nSecond: "))
    (cond ((and (null b) (= 7 (getvar "ERRNO"))) (princ "\nNothing there."))
          (t (setq done T)))))

;; zeroed once before a mapcar, read inside its lambda
(defun bad:mapper-once (names)
  (setvar "ERRNO" 0)
  (mapcar '(lambda (n / s)
             (setq s (entsel (strcat "\nPick " n ": ")))
             (if (and (null s) (= 7 (getvar "ERRNO"))) (princ "\nmissed") s))
          names))

;; zeroed at the END of the pass: every pass but the first reads its
;; own pick, and the first reads whatever came before the command
(defun bad:zero-at-end ( / sel done)
  (while (not done)
    (setq sel (entsel "\nPick <done>: "))
    (cond ((and (null sel) (= 7 (getvar "ERRNO"))) (princ "\nNothing there."))
          ((null sel) (setq done T))
          (t (princ "\ngot one")))
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))))

;; the caller zeroes, but the helper loops on its own: only its first
;; pass is covered
(defun bad:askloop ( / sel r)
  (while (null r)
    (setq sel (entsel "\nPick one: "))
    (cond ((and (null sel) (= 7 (getvar "ERRNO"))) (princ "\nNothing there."))
          (t (setq r (if sel sel 'NONE)))))
  r)
(defun bad:caller-loop ()
  (vl-catch-all-apply 'setvar (list "ERRNO" 0))
  (bad:askloop))

;; a helper that picks and reads, called by a loop that never zeroes
(defun bad:asknz ( / sel)
  (setq sel (entsel "\nPick one: "))
  (if (and (null sel) (= 7 (getvar "ERRNO"))) 'MISS sel))
(defun bad:caller-nz ( / r)
  (setq r 'MISS)
  (while (eq r 'MISS)
    (setq r (bad:asknz))
    (if (eq r 'MISS) (princ "\nNothing there.")))
  r)

;; --- the right shapes -------------------------------------------------

;; the zero and the read each through a helper of their own
(defun ok:clear () (vl-catch-all-apply 'setvar (list "ERRNO" 0)))
(defun ok:missed-p (s) (and (null s) (= 7 (getvar "ERRNO"))))
(defun ok:helpers ( / sel done)
  (while (not done)
    (ok:clear)
    (setq sel (entsel "\nPick <done>: "))
    (cond ((ok:missed-p sel) (princ "\nNothing there."))
          ((null sel) (setq done T))
          (t (princ "\ngot one")))))

;; the caller's loop zeroes right before asking a helper that picks
(defun ok:askone ( / sel)
  (setq sel (entsel "\nPick one: "))
  (if (and (null sel) (= 7 (getvar "ERRNO"))) 'MISS sel))
(defun ok:caller ( / r)
  (setq r 'MISS)
  (while (eq r 'MISS)
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (setq r (ok:askone))
    (if (eq r 'MISS) (princ "\nNothing there.")))
  r)

;; a zero on a keyword's own clause is not between the pick and a read
;; on another clause: the two never both run
(defun ok:branchzero ( / sel done)
  (while (not done)
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (initget "Reset")
    (setq sel (entsel "\nPick [Reset] <done>: "))
    (cond ((= (type sel) 'STR)
           (vl-catch-all-apply 'setvar (list "ERRNO" 0)) (princ "\nreset"))
          ((and (null sel) (= 7 (getvar "ERRNO"))) (princ "\nNothing there."))
          ((null sel) (setq done T))
          (t (princ "\ngot one")))))
"""

got, allv, out = sites(STICKY)
check("STICKY: an ERRNO read that was never zeroed",
      got.get('bad:never') == ['STICKY'], (got, out))
check("STICKY: zeroed once before the loop, not before each pick",
      got.get('bad:once') == ['STICKY']
      and any('once before the loop' in ln for ln in out), (got, out))
check("two picks in one defun are judged each on its own",
      'c:twopicks' not in got
      and sorted(allv.get('c:twopicks', [])) == ['ok-errno', 'ok-reasks'],
      (got.get('c:twopicks'), allv.get('c:twopicks')))
check("STICKY: pick, then zero, then read",
      got.get('bad:zeroafter') == ['STICKY']
      and any('bad:zeroafter' in ln and 'between the pick and' in ln
              for ln in out), (got.get('bad:zeroafter'), out))
check("STICKY: a zero after the pick wipes it, even with one before",
      got.get('bad:zerotwice') == ['STICKY'], got.get('bad:zerotwice'))
check("two picks, one zero: the first is a PICK, the second STICKY",
      sorted(got.get('bad:twoinone', [])) == ['PICK', 'STICKY'],
      got.get('bad:twoinone'))
check("STICKY: zeroed once before a mapcar, read in its lambda",
      got.get('bad:mapper-once') == ['STICKY']
      and any('bad:mapper-once' in ln and 'once before the loop' in ln
              for ln in out), (got.get('bad:mapper-once'), out))
check("STICKY: a picking helper whose caller never zeroes",
      got.get('bad:asknz') == ['STICKY'], got.get('bad:asknz'))
check("STICKY: zeroed at the end of the pass, not before the pick",
      got.get('bad:zero-at-end') == ['STICKY'], got.get('bad:zero-at-end'))
check("STICKY: the caller zeroes, but the helper loops on its own",
      got.get('bad:askloop') == ['STICKY'], got.get('bad:askloop'))
for name, why in (
        ('ok:helpers', "the zero and the read through helpers"),
        ('ok:askone', "the zero in every caller, right before the call"),
        ('ok:branchzero', "a zero on another clause's branch")):
    check("passes (ok-errno): %s" % why,
          name not in got and allv.get(name) == ['ok-errno'],
          (got.get(name), allv.get(name)))
got, _, out = sites(STICKY, base=[('cases', 'bad:never',
                                   'Select a boundary [None] <None>:',
                                   'x', 'x')])
check("...and a STICKY site cannot be baselined away",
      got.get('bad:never') == ['STICKY'], (got, out))


# ---------------------------------------------------------------------
print("== SPACE: an example with a space in it, where a space is Enter ==")

SPACE = r"""
(defun bad:prompt () (getpoint "\nTread (e.g. 24 1/8): "))
(defun bad:unit () (getdist "\nDiameter, e.g. 1524 MM: "))
(defun bad:lone () (getstring (strcat "\nLength, e.g. 44 1/2: ")))
(defun bad:hint ( / p)
  (setq p (getpoint "\nLength: "))
  (princ "\n  not a length - try 44, 44-1/2 or 4'-4 1/2\"")
  p)
(defun bad:unread (v)
  (princ (strcat "\n\"" v "\" is not a length - try 44, 44.5, 44 1/2.")))
(defun bad:wrap (msg / p) (initget 1) (setq p (getpoint (strcat "\n" msg))) p)
(defun bad:via-wrap () (bad:wrap "Offset (e.g. 3 1/2): "))
(setq bad:*caption* '(("TOOL" "Type 4'-4 1/2\" at the prompt")))

;; --- quiet ----------------------------------------------------------
(defun ok:line () (getstring T "\nText - 4'-4 1/2\" or a letter: "))
(defun ok:rawask (msg) (getstring T msg))
(defun ok:via-raw () (ok:rawask "\nWidth, e.g. 20'-6 1/2\": "))
(defun ok:twodeep (msg) (ok:rawask (strcat "\n" msg)))
(defun ok:via-two () (ok:twodeep "Width, e.g. 20'-6 1/2\": "))
(defun ok:getdim ( / s)
  (setq s (getstring T "\nDimension (e.g. 20'-6\"): "))
  (princ "  ** enter it as e.g. 20'-6 1/2\" or 246.5")
  s)
(defun ok:unit-hint () (princ "\nWARNING: over the 400 ft ceiling"))
(defun ok:dashed () (getpoint "\nTread (e.g. 24-1/8 or 2'-0-1/2\"): "))
(defun ok:transcript ( / p)
  (setq p (getpoint "\nTread: "))
  (if lzd:ask (lzd:ask "Tread (typed 24 1/8 in the log)" p) p))
(setq lzp:*knobs* '(("*x*" "543.625" "45'-3 5/8\" in drawing units")))
"""

got, allv, out = sites(SPACE)
for name, why in (
        ('bad:prompt', "a spaced fraction in a getpoint prompt"),
        ('bad:unit', "a spaced unit in a getdist prompt"),
        ('bad:lone', "(getstring (strcat ...)): the lone argument is the prompt"),
        ('bad:hint', "a hint beside a spacebar-ended prompt"),
        ('bad:unread', "a hint helper with no input of its own (len-unread)"),
        ('bad:via-wrap', "a prompt handed through a wrapper into getpoint"),
        ('bad:*caption*', "a top-level caption / tooltip")):
    check("SPACE: %s" % why, got.get(name) == ['SPACE'], (got.get(name), out))
for name, why in (
        ('ok:line', "the prompt of a (getstring T ...)"),
        ('ok:via-raw', "...through a wrapper's parameter (ds:ask-raw)"),
        ('ok:via-two', "...through two wrappers"),
        ('ok:getdim', "a hint beside a (getstring T ...) only (abcdef:getdim)"),
        ('ok:unit-hint', "a unit word in a hint, not a prompt"),
        ('ok:dashed', "the dashed spelling"),
        ('ok:transcript', "LAZDIAG's transcript copy of a prompt"),
        ('lzp:*knobs*', "the generated knob catalog")):
    check("passes: %s" % why, name not in got, (got.get(name), out))

# DIMSTAMP: the first prompt reads a whole line, but the same file reads
# free text at an (initget 128) point prompt too -- a spelling taught at
# the one is typed at the other
got, _, out = sites(SPACE + r"""
(defun typed:next ( / pk) (initget (+ 128 1)) (setq pk (getpoint "\nNext: ")) pk)
""")
check("withdrawn: a (getstring T) prompt in a file with (initget 128)",
      got.get('ok:line') == ['SPACE'], (got.get('ok:line'), out))
check("...and a hint beside one",
      got.get('ok:getdim') == ['SPACE'], (got.get('ok:getdim'), out))


# ---------------------------------------------------------------------
print("== the baseline: file|defun|what it asks|why, by stem, every tier ==")

base = [('cases', 'bad:noloop', 'Pick:', 'says so, ends before drawing',
         'lisp/cases/CASES.lsp|bad:noloop|Pick:|...'),
        ('cases', 'bad:gone', 'Pick:', 'a site that no longer exists',
         'lisp/cases/CASES.lsp|bad:gone|Pick:|...')]
got, _, out = sites(PICK, base=base)
check("a baselined PICK site is not a failure",
      'bad:noloop' not in got, (got, out))
check("...and every other one still is",
      got.get('bad:default') == ['PICK'], got)
got, _, out = sites(PICK, name='CASES_092326_REV12.lsp', base=base)
check("a dated releases/ twin matches its lisp/ file's line",
      'bad:noloop' not in got, (got, out))
got, _, out = sites(PICK, base=[('cases', 'bad:default', 'Pick:', 'x', 'x')])
check("a line with the right text but the wrong defun does not match",
      got.get('bad:noloop') == ['PICK'], got)
got, _, out = sites(PICK, base=[('cases', 'bad:noloop', 'Pick the line:',
                                 'x', 'x')])
check("...nor one with the right defun but the wrong text",
      got.get('bad:noloop') == ['PICK'], got)
got, _, out = sites(PICK, base=[('other', 'bad:noloop', 'Pick:', 'x', 'x')])
check("...nor one for another file",
      got.get('bad:noloop') == ['PICK'], got)

with tempfile.TemporaryDirectory() as d:
    p = pathlib.Path(d) / 'CASES.lsp'
    p.write_text(PICK, encoding='utf-8')
    q = pathlib.Path(d) / 'OTHER.lsp'
    q.write_text("(defun other:x () (princ))", encoding='utf-8')
    base_other = base + [('unread', 'x:y', 'Pick:', 'a file not read', 'z')]
    out = []
    nbad, stale = check_input.run([('t', [p, q])], base_other, out=out.append)
    check("a baseline line nothing matches is reported stale",
          stale == ['lisp/cases/CASES.lsp|bad:gone|Pick:|...'], (stale, out))
    check("...but not a line for a file this run did not read",
          'z' not in stale, stale)



# ---------------------------------------------------------------------
print("== main(): the exit code make check reads ==")

CLEAN = """
(defun ok:whilenot ( / sel)
  (while (not (setq sel (entsel "\\nSelect a line: ")))
    (princ "\\nMissed - try again."))
  sel)
"""
NOLOOP = """
(defun bad:noloop ( / sel)
  (setq sel (entsel "\\nPick: "))
  (if (null sel) (princ "\\nNothing selected.") (princ "\\nok")))
"""


def main_on(text, baseline):
    """check_input.main over a made tree with TEXT as its one lisp/ tool
    and BASELINE as the baseline file's lines: the exit code, and what
    it printed."""
    saved = (check_input.LISP_DIR, check_input.PARTS_DIR,
             check_input.RELEASES_DIR)
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        (d / 'lisp' / 'cases').mkdir(parents=True)
        (d / 'lisp' / 'cases' / 'CASES.lsp').write_text(text,
                                                         encoding='utf-8')
        bl = d / 'baseline.txt'
        bl.write_text('# made\n' + ''.join(ln + '\n' for ln in baseline),
                      encoding='utf-8')
        buf = io.StringIO()
        try:
            check_input.LISP_DIR = d / 'lisp'
            check_input.PARTS_DIR = d / 'shared' / 'parts'
            check_input.RELEASES_DIR = d / 'releases'
            with contextlib.redirect_stdout(buf):
                code = check_input.main(['--tier', 'lisp',
                                         '--baseline', str(bl)])
        finally:
            (check_input.LISP_DIR, check_input.PARTS_DIR,
             check_input.RELEASES_DIR) = saved
        return code, buf.getvalue()


code, said = main_on(CLEAN, [])
check("exit 0 on a clean tree", code == 0, (code, said))
code, said = main_on(NOLOOP, [])
check("exit 1 on a failing site", code == 1, (code, said))
code, said = main_on(NOLOOP, ['lisp/cases/CASES.lsp|bad:noloop|Pick:|'
                              'says so, ends before drawing'])
check("exit 0 once that site is baselined", code == 0, (code, said))
code, said = main_on(CLEAN, ['lisp/cases/CASES.lsp|bad:gone|Pick:|'
                             'a site that no longer exists'])
check("exit 1 on a stale baseline line alone",
      code == 1 and 'stale baseline line' in said, (code, said))

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall check_input rules fire, and the right shapes pass")
