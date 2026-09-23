#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_writes.py on made files: every rule fires on the shape it
exists for, and every exemption stays quiet on the shape that is right.

On a locked layer entmod and entdel answer nil and change nothing, and
an edit command skips the object without a word.  A write whose answer
is thrown away and then COUNTED or REPORTED is a false success -- ABHD
said "cleared N markers" over markers still on screen, SPACHECK "1 item
marked red" over a dimension that never changed colour, DIMCHECK "MOVED
onto the nearest object" over a point that never moved.  The fixtures
below are those shapes cut down to a few lines each, beside the shape
the fix turned them into.

The one that matters most is ROTASK: an unlock the drafter can refuse is
not a screen.  DIMCHECK offered "Unlock for this run?", and on No carried
on and reported every refused move as made -- the verified bug a check
that only looked for a lock reader in the command would have excused.

Every condition the check decides on has a fixture on each side of it:
the reach of a count and of a claim (at the bound, and one past it), the
claim after a loop (and the told count that takes it over), each way a
write is OBSERVED, each source of FRESH, how deep a lock reader may sit
and what is NOT one ((logand 7 ...), a helper that only calls one), and
each part of a baseline line -- the tool, the whole write, and the
needs= its reason rests on.  Break any one of them in the checker and
this goes red; that is what the fixtures are for.

Run: python3 tests/test_check_writes.py
"""

import os
import pathlib
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_writes  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


def run(text, base=None, show=False):
    """check_writes over one made file: (printed lines, baseline keys met,
    baseline keys whose needs= no longer hold)"""
    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / 'CASES.lsp'
        p.write_text(text, encoding='utf-8')
        out, met, broken = [], set(), {}
        check_writes.report([p], base or {}, out=out.append, show=show,
                            met=met, broken=broken)
        return out, met, broken


LINE = re.compile(r'^\S+:\d+: (W\d)(?: \(baselined\))? (\S+) ')


def rules(out, defun):
    """the rule tags printed against DEFUN"""
    return [m.group(1) for m in map(LINE.match, out)
            if m and m.group(2).lower() == defun.lower()]


CASES = r"""
;; ---- W1: the layer helper ------------------------------------------
(defun bad:layer (name)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 name) '(70 . 0)))))

(defun ok:layer (name / ed fl)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 name) '(70 . 0)))
    (progn
      (setq ed (entget (tblobjname "LAYER" name))
            fl (cdr (assoc 70 ed)))
      (if (/= 0 (logand 5 fl))
        (entmod (subst (cons 70 (logand fl (~ 5))) (assoc 70 ed) ed))))))

;; reading the lock to SAY so still leaves it on
(defun bad:layersay (name / rec)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 name) '(70 . 0)))
    (if (= 4 (logand 4 (cdr (assoc 70 (tblsearch "LAYER" name)))))
      (princ (strcat "\nLayer " name " is locked.")))))

;; ---- W2: a tally after an erase nobody looked at (purge-mine) --------
(defun c:BADPURGE ( / ss i n en)
  (setq ss (ssget "_X" '((8 . "MINE"))) n 0 i 0)
  (repeat (sslength ss)
    (setq en (ssname ss i) i (1+ i))
    (progn (entdel en) (setq n (1+ n))))
  (princ (strcat "\ncleared " (itoa n))))

(defun c:OKPURGE ( / ss i n en)
  (setq ss (ssget "_X" '((8 . "MINE"))) n 0 i 0)
  (repeat (sslength ss)
    (setq en (ssname ss i) i (1+ i))
    (if (entdel en) (setq n (1+ n))))
  (princ (strcat "\ncleared " (itoa n))))

;; ---- W2: a claim after a move nobody looked at (audit-dim-point) -----
(defun bad:nudge (ent gcode pt / ed)
  (setq ed (entget ent))
  (entmod (subst (cons gcode pt) (assoc gcode ed) ed))
  (entupd ent)
  (princ "\n  point MOVED onto the line."))

(defun ok:nudge (ent gcode pt / ed)
  (setq ed (entget ent))
  (if (entmod (subst (cons gcode pt) (assoc gcode ed) ed))
    (princ "\n  point MOVED onto the line.")
    (princ "\n  layer locked - NOT moved.")))

(defun ok:nudgesaid (ent gcode pt / ed)
  (setq ed (entget ent))
  (entmod (subst (cons gcode pt) (assoc gcode ed) ed))
  (princ "\n  (nothing was moved)"))

(defun c:NUDGE ( / e)
  (setq e (car (entsel)))
  (bad:nudge e 13 '(0.0 0.0 0.0))
  (ok:nudge e 13 '(0.0 0.0 0.0))
  (ok:nudgesaid e 13 '(0.0 0.0 0.0))
  (princ))

;; ---- W2: a success flag the defun hands back (set-attrib) ------------
(defun bad:setattr (ent val / e ed done)
  (setq e (entnext ent))
  (while (and e (null done))
    (setq ed (entget e))
    (entmod (subst (cons 1 val) (assoc 1 ed) ed))
    (setq done T)
    (setq e (entnext e)))
  done)

(defun ok:stopflag (ent / ed stop)
  (setq ed (entget ent))
  (entmod (subst '(62 . 1) (assoc 62 ed) ed))
  (setq stop T)
  (princ))

(defun c:SETATTR ( / ins)
  (setq ins (car (entsel)))
  (if (bad:setattr ins "X") (princ "\nset"))
  (ok:stopflag ins)
  (princ))

;; ---- W2: a helper's unlooked-at write, then a count (SPACHECK) -------
(defun sp:paint (ent / ed)
  (setq ed (entget ent))
  (entmod (append ed '((62 . 1))))
  (entupd ent))

(defun c:MARKALL ( / ss i marked e)
  (setq ss (ssget) i 0 marked 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i))
    (sp:paint e)
    (setq marked (1+ marked)))
  (princ (strcat "\n" (itoa marked) " marked red")))

;; ---- W2: a helper that ANSWERS its write, answer dropped (RESCUE) ----
(defun sc:color (ent c / ed)
  (setq ed (entget ent))
  (if (entmod (subst (cons 62 c) (assoc 62 ed) ed))
    (progn (entupd ent) T)))

(defun c:RESCUEBAD ( / ss i n e)
  (setq ss (ssget "_X") i 0 n 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i))
    (sc:color e 256)
    (setq n (1+ n)))
  (princ (strcat "\nrestored " (itoa n))))

(defun c:RESCUEOK ( / ss i n e)
  (setq ss (ssget "_X") i 0 n 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i))
    (if (sc:color e 256) (setq n (1+ n))))
  (princ (strcat "\nrestored " (itoa n))))

;; ---- W2: a helper that answers T whatever its write did (RESCUE) ----
(defun ls:unstash (ent / ed)
  (setq ed (entget ent))
  (entmod (subst '(62 . 256) (assoc 62 ed) ed))
  T)

(defun c:LIARBAD ( / ss i n e)
  (setq ss (ssget "_X") i 0 n 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i))
    (if (ls:unstash e) (setq n (1+ n))))
  (princ (strcat "\n" (itoa n) " colours put back")))

;; ---- W2: an edit command on the drafter's selection (STOCKCOVER) -----
(defun c:ERASEBAD ( / ss)
  (setq ss (ssget))
  (command "_.ERASE" ss "")
  (princ "\nerased"))

(defun c:ERASEFRESH ()
  (entmakex (list '(0 . "LINE") '(8 . "MINE")
                  '(10 0.0 0.0 0.0) '(11 1.0 0.0 0.0)))
  (command "_.ERASE" (entlast) "")
  (princ))

;; ---- SCREENED (a): an unlock for the run, not behind a question ------
(defun ul:free (ss / i lay rec ed fl)
  (setq i 0)
  (repeat (sslength ss)
    (setq lay (cdr (assoc 8 (entget (ssname ss i))))
          rec (tblobjname "LAYER" lay)
          ed  (entget rec)
          fl  (cdr (assoc 70 ed))
          i   (1+ i))
    (if (= 4 (logand 4 fl))
      (entmod (subst (cons 70 (- fl 4)) (assoc 70 ed) ed)))))

(defun c:ROTOK ( / ss)
  (setq ss (ssget))
  (ul:free ss)
  (command "_.ROTATE" ss "" '(0.0 0.0 0.0) 90)
  (princ "\nrotated"))

;; the DIMCHECK shape: an unlock the drafter can refuse is no screen
(defun c:ROTASK ( / ss)
  (setq ss (ssget))
  (initget "Yes No")
  (if (= "Yes" (getkword "\nUnlock for this run? [Yes/No]: "))
    (ul:free ss))
  (command "_.ROTATE" ss "" '(0.0 0.0 0.0) 90)
  (princ "\nrotated"))

;; ---- SCREENED (b): the write sits behind the lock reader's answer ----
(defun lk:locked (ss / i out lay)
  (setq i 0)
  (repeat (sslength ss)
    (setq lay (cdr (assoc 8 (entget (ssname ss i))))
          i   (1+ i))
    (if (= 4 (logand 4 (cdr (assoc 70 (tblsearch "LAYER" lay)))))
      (setq out (cons lay out))))
  out)

(defun c:SCALEOK ( / ss locked)
  (setq ss (ssget)
        locked (lk:locked ss))
  (if locked
    (princ "\nUnlock them first.")
    (progn (command "_.SCALE" ss "" '(0.0 0.0 0.0) 2.0)
           (princ "\nscaled")))
  (princ))

;; reads the lock, says so, and carries on regardless
(defun c:SCALESAY ( / ss)
  (setq ss (ssget))
  (if (lk:locked ss) (princ "\nSome layers are locked."))
  (command "_.SCALE" ss "" '(0.0 0.0 0.0) 2.0)
  (princ "\nscaled"))

;; ---- W2: scratch on the drafter's current layer (AUTODIM) ------------
(defun c:PROBEBAD ( / e)
  (setq e (if (entmake (list '(0 . "LINE") '(10 0.0 0.0 0.0)
                             '(11 1.0 0.0 0.0)))
            (entlast)))
  (if e (entdel e))
  (princ))

(defun c:PROBEOK ( / e)
  (setq e (if (entmake (list '(0 . "LINE") '(8 . "SCRATCH")
                             '(10 0.0 0.0 0.0) '(11 1.0 0.0 0.0)))
            (entlast)))
  (if e (entdel e))
  (princ))

;; ---- TABLE: a layer record is never refused by a lock ----------------
(defun c:RELOCK ( / ed n)
  (setq n 0
        ed (entget (tblobjname "LAYER" "MINE")))
  (entmod (subst '(70 . 4) (assoc 70 ed) ed))
  (setq n (1+ n))
  (princ (strcat "\nlocked " (itoa n))))

;; ---- FRESH: a global list only a drawing helper ever fills -----------
(defun pv:add (e) (setq pv:*ents* (cons e pv:*ents*)) e)
(defun pv:draw (p)
  (pv:add (entmakex (list '(0 . "POINT") '(8 . "PREVIEW") (cons 10 p)))))
(defun pv:kill ( / n)
  (setq n 0)
  (foreach e pv:*ents* (entdel e) (setq n (1+ n)))
  (setq pv:*ents* nil)
  (princ (strcat "\n" (itoa n) " erased")))
(defun c:PREVIEW () (pv:draw '(0.0 0.0 0.0)) (pv:kill) (princ))

;; ---- FRESH: everything drawn since a mark this run took --------------
(defun nw:since (mark / e out)
  (setq e (if mark (entnext mark) (entnext)))
  (while e (setq out (cons e out) e (entnext e)))
  out)
(defun c:SWEEPNEW ( / mark n)
  (setq mark (entlast) n 0)
  (command "_.LINE" '(0.0 0.0) '(1.0 1.0) "")
  (foreach e (nw:since mark) (entdel e) (setq n (1+ n)))
  (princ (strcat "\n" (itoa n) " removed")))

;; ---- GATED: past one tested write, the layer is writable -------------
(defun gt:move (ent pt / ed)
  (setq ed (entget ent))
  (if (entmod (subst (cons 10 pt) (assoc 10 ed) ed))
    (progn
      (setq ed (entget ent))
      (entmod (subst (cons 11 pt) (assoc 11 ed) ed))
      (princ "\nboth ends moved"))))
(defun c:GATE () (gt:move (car (entsel)) '(0.0 0.0 0.0)) (princ))

;; ...and past a tested write to the object's partner (merge-lines): the
;; branch runs only once the merge took, so their shared layer is open
(defun mg:merge (la lb / ed)
  (setq ed (entget la))
  (if (entmod (subst (assoc 11 (entget lb)) (assoc 11 ed) ed))
    (progn (entdel lb) T)))
(defun mg:paint (ent / ed)
  (setq ed (entget ent))
  (entmod (append ed '((62 . 4))))
  (entupd ent))
(defun mg:review (la lb ans)
  (cond
    ((and (= ans "Merge") (not (mg:merge la lb)))
     (princ "\n  Could NOT merge - the layer is locked."))
    ((= ans "Merge")
     (mg:paint la)
     (princ "\n  Merged into one line."))))
(defun c:MERGE ( / a b)
  (setq a (car (entsel)) b (car (entsel)))
  (mg:review a b "Merge")
  (princ))

;; ---- OBSERVED: the erase is looked at, not its answer ----------------
(defun ob:del (e)
  (entdel e)
  (if (entget e)
    (princ "\n  NOT erased - its layer is locked")
    (princ "\n  erased")))
(defun ob:bad (e)
  (entdel e)
  (princ "\n  erased"))
(defun c:OBS ( / e) (setq e (car (entsel))) (ob:del e) (ob:bad e) (princ))

;; ---- a loop's index is not a count -----------------------------------
(defun c:WALKDEL ( / ss i)
  (setq ss (ssget) i 0)
  (repeat (sslength ss)
    (entdel (ssname ss i))
    (setq i (1+ i)))
  (princ))

;; ---- a count nobody is told is not a claim ---------------------------
(defun uc:dropped ( / ss i n)
  (setq n 0 i 0 ss (ssget "_X" '((8 . "GAP"))))
  (if ss (repeat (sslength ss)
           (entdel (ssname ss i))
           (setq i (1+ i) n (1+ n))))
  n)
(defun uc:kept ( / ss i n)
  (setq n 0 i 0 ss (ssget "_X" '((8 . "GAP"))))
  (if ss (repeat (sslength ss)
           (entdel (ssname ss i))
           (setq i (1+ i) n (1+ n))))
  n)
(defun c:UNREPORTED ( / k)
  (uc:dropped)
  (setq k (uc:kept))
  (princ (strcat "\n" (itoa k) " cleared")))

;; ---- W2: the claim comes AFTER the loop (dchk:tut-demo) --------------
;; practice lines on layer 0, which nothing unlocks; the repeat drops
;; every answer and the line after it says they are gone
(defun c:LOOPTHENSAY ( / ss i)
  (setq ss (ssget "_X" '((8 . "0"))) i 0)
  (repeat (sslength ss)
    (entdel (ssname ss i))
    (setq i (1+ i)))
  (princ "\nPractice drawing erased."))

;; ...and out through the progn the loop ends (spachk:demo's report sweep)
(defun c:LOOPINBRANCH ( / ss i)
  (setq ss (ssget "_X" '((8 . "REPORT"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (entdel (ssname ss i))
        (setq i (1+ i)))))
  (princ "\nReport erased."))

;; a loop that keeps its own told count: the report after it is about
;; THAT count, and the colour write beside it claims nothing
(defun c:LOOPCOUNTS ( / ss i n ed)
  (setq ss (ssget "_X" '((8 . "0"))) i 0 n 0)
  (repeat (sslength ss)
    (if (entdel (ssname ss i)) (setq n (1+ n)))
    (setq ed (entget (ssname ss 0)))
    (entmod (subst '(62 . 1) (assoc 62 ed) ed))
    (setq i (1+ i)))
  (princ (strcat "\n" (itoa n) " erased")))

;; ...and the same for a helper whose write goes unlooked-at
(defun hb:paint (e / ed)
  (setq ed (entget e))
  (entmod (subst '(62 . 1) (assoc 62 ed) ed))
  (entupd e))
(defun c:PAINTLOOP ( / ss i)
  (setq ss (ssget) i 0)
  (repeat (sslength ss) (hb:paint (ssname ss i)) (setq i (1+ i)))
  (princ "\nAll marked red."))

;; ...and out of the loop around it: the claim after the OUTER loop is
;; about every erase the inner one made
(defun c:NESTEDLOOPS ( / groups ss i)
  (setq groups (list (ssget) (ssget)))
  (foreach ss groups
    (setq i 0)
    (repeat (sslength ss)
      (entdel (ssname ss i))
      (setq i (1+ i))))
  (princ "\nAll groups erased."))

;; ...unless that outer loop keeps a told count of its own
(defun c:NESTEDCOUNT ( / groups ss i n)
  (setq groups (list (ssget) (ssget)) n 0)
  (foreach ss groups
    (setq i 0)
    (repeat (sslength ss)
      (entdel (ssname ss i))
      (setq i (1+ i)))
    (if (not (entget (ssname ss 0))) (setq n (1+ n))))
  (princ (strcat "\n" (itoa n) " group(s) erased")))

;; the claim five statements after the loop is not this loop's
(defun c:LOOPFARSAY ( / ss i)
  (setq ss (ssget "_X" '((8 . "0"))) i 0)
  (repeat (sslength ss) (entdel (ssname ss i)) (setq i (1+ i)))
  (princ "1") (princ "2") (princ "3") (princ "4")
  (princ "\nerased"))

;; ---- FRESH: a foreach's own variable, whatever else shares its name --
(defun fb:draw (p)
  (setq fb:*made* (cons (entmakex (list '(0 . "POINT") '(8 . "DEMO")
                                        (cons 10 p)))
                        fb:*made*)))
(defun c:FOREACHBIND ( / e)
  (fb:draw '(0.0 0.0 0.0))
  (foreach e fb:*made* (if (entget e) (entdel e)))
  (setq e (ssget "_X" '((8 . "REPORT"))))
  (princ "\nPractice drawing erased."))

;; ---- claims: a strcat is one sentence, a question is not a claim -----
(defun c:LEFTALONE ( / e)
  (setq e (car (entsel)))
  (entdel e)
  (princ (strcat "\n" (itoa 1) " object left as drawn - not" " erased.")))
(defun c:ASKPLACED ( / e)
  (setq e (car (entsel)))
  (entdel e)
  (princ "\n  Step block - is the correct one placed?"))

;; ---- W1: a layer made by vla-Add keeps the lock it was found with ----
(defun c:VLALAYBAD ( / doc)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (vla-put-Color (vla-Add (vla-get-Layers doc) "DEMO") 3)
  (princ))
(defun c:VLALAYBAD2 ( / doc lays)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        lays (vla-get-Layers doc))
  (vla-Add lays "DEMO")
  (princ))
(defun c:VLALAYOK ( / doc lays lay)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))
        lays (vla-get-Layers doc)
        lay (vla-Add lays "DEMO"))
  (vla-put-Lock lay :vlax-false)
  (princ))

;; ...and a helper that unlocks through the LAYER command
(defun cu:layer (name)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord") (cons 2 name) '(70 . 0)))
    (command "_.-LAYER" "_Unlock" name "")))

;; ---- SCREENED (b), two deep: xft:locked < xft:ss-locked < the test ---
(defun rd:locked (lay)
  (= 4 (logand 4 (cdr (assoc 70 (tblsearch "LAYER" lay))))))
(defun rd:ss-locked (ss / i lay out)
  (setq i 0)
  (while (< i (sslength ss))
    (setq lay (cdr (assoc 8 (entget (ssname ss i)))))
    (if (rd:locked lay) (setq out (cons lay out)))
    (setq i (1+ i)))
  out)
(defun c:XSCALE ( / ss locked)
  (setq ss (ssget) locked (rd:ss-locked ss))
  (if locked
    (princ "\nUnlock them first.")
    (progn (command "_.SCALE" ss "" '(0.0 0.0 0.0) 2.0)
           (princ "\nscaled")))
  (princ))

;; a helper that CALLS a lock reader and answers something else is no
;; reader (dchk:review-dim): testing its answer is not testing the lock
(defun rv:review (ss)
  (if (lk:locked ss) (princ "\n  (some layers are locked)"))
  (sslength ss))
(defun c:REVIEWSCALE ( / ss)
  (setq ss (ssget))
  (if (rv:review ss)
    (progn (command "_.SCALE" ss "" '(0.0 0.0 0.0) 2.0)
           (princ "\nscaled")))
  (princ))

;; (logand 7 ...) of a DIMENSION's 70 is its TYPE, not a lock
(defun dt:kind (e) (logand 7 (cdr (assoc 70 (entget e)))))
(defun c:DIMTYPE ( / ss)
  (setq ss (ssget))
  (if (= 0 (dt:kind (ssname ss 0)))
    (progn (command "_.ERASE" ss "") (princ "\nerased")))
  (princ))

;; a lock reader about ANOTHER selection screens nothing
(defun c:SCALEOTHER ( / ss other)
  (setq ss (ssget) other (ssget))
  (if (lk:locked other)
    (princ "\nUnlock them first.")
    (progn (command "_.SCALE" ss "" '(0.0 0.0 0.0) 2.0)
           (princ "\nscaled")))
  (princ))

;; an offer to unlock made by a helper that asks -- two calls down -- is
;; still an offer
(defun ak:kw (msg kws) (initget kws) (getkword msg))
(defun ak:yes (msg) (= "Yes" (ak:kw msg "Yes No")))
(defun c:ROTASK2 ( / ss)
  (setq ss (ssget))
  (if (ak:yes "\nUnlock for this run? [Yes/No]: ") (ul:free ss))
  (command "_.ROTATE" ss "" '(0.0 0.0 0.0) 90)
  (princ "\nrotated"))

;; a parameter every caller passes an unlocked selection is SCREENED
(defun sc:rot (ss)
  (command "_.ROTATE" ss "" '(0.0 0.0 0.0) 90)
  (princ "\nrotated"))
(defun c:ROTVIA ( / ss)
  (setq ss (ssget))
  (ul:free ss)
  (sc:rot ss)
  (princ))

;; ---- a write whose answer is KEPT is not a site (review-olap) --------
(defun ck:paint (e c / ed)
  (setq ed (entget e))
  (if (entmod (subst (cons 62 c) (assoc 62 ed) ed))
    (progn (entupd e) T)))
(defun c:PAINTPAIR ( / ea eb ok1 ok2 n)
  (setq ea (car (entsel)) eb (car (entsel)) n 0)
  (setq ok1 (ck:paint ea 4)
        ok2 (ck:paint eb 4))
  (setq n (1+ n))
  (princ (if (and ok1 ok2) "\nboth marked" "\nNOT marked - a layer is locked"))
  (princ (itoa n)))

;; ---- OBSERVED, each way on its own ----------------------------------
;; the next statement, even on the write's own line
(defun ob:sameline (e)
  (entdel e) (if (entget e) (princ "\n  NOT erased - locked") (princ "\n  erased")))
;; an erase asked about any time later -- ad:scrap's (not (entget en))
(defun ob:late (e / n)
  (setq n 0)
  (entdel e)
  (setq n (1+ n))
  (princ "a") (princ "b") (princ "c")
  (if (entget e) (setq n (1- n)))
  n)
(defun c:OBSLATE ( / k) (setq k (ob:late (car (entsel)))) (princ (itoa k)))
;; a FILLET read back through (entlast)
(defun c:FILLETOBS ( / a b e)
  (setq a (entsel) b (entsel))
  (command "_.FILLET" a b)
  (princ "1") (princ "2") (princ "3")
  (setq e (entlast))
  (princ))

;; ---- the other write kinds ------------------------------------------
(defun c:VLADEL ( / ss o)
  (setq ss (ssget)
        o  (vlax-ename->vla-object (ssname ss 0)))
  (vl-catch-all-apply 'vla-delete (list o))
  (princ "\nerased"))
(defun c:MAPDEL ( / ss lst i)
  (setq ss (ssget) i 0)
  (repeat (sslength ss) (setq lst (cons (ssname ss i) lst) i (1+ i)))
  (mapcar 'entdel lst)
  (princ "\nerased"))

;; ---- the other tallies ----------------------------------------------
(defun c:CONSGONE ( / ss i e gone)
  (setq ss (ssget) i 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i))
    (entdel e)
    (setq gone (cons e gone)))
  (princ (strcat "\n" (itoa (length gone)) " gone")))
(defun c:SSADDDONE ( / ss i e done)
  (setq ss (ssget) i 0 done (ssadd))
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i))
    (entdel e)
    (ssadd e done))
  (sssetfirst nil done))
(defun c:PLUSONE ( / ss i e n)
  (setq ss (ssget) i 0 n 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i))
    (entdel e)
    (setq n (+ n 1)))
  (princ (itoa n)))
;; a report line consed onto a list is text, not a count
(defun c:CONSTEXT ( / ss i e ed notes)
  (setq ss (ssget) i 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i) ed (entget e))
    (entmod (subst '(62 . 1) (assoc 62 ed) ed))
    (setq notes (cons (strcat "item " (itoa i)) notes)))
  (foreach nt notes (princ nt)))
;; (+ total (cdr ...)) adds up a number read elsewhere; it counts nothing
(defun c:SUMUP ( / ss i e ed total)
  (setq ss (ssget) i 0 total 0)
  (repeat (sslength ss)
    (setq e (ssname ss i) i (1+ i) ed (entget e))
    (entmod (subst '(62 . 1) (assoc 62 ed) ed))
    (setq total (+ total (cdr (assoc 40 ed)))))
  (princ (strcat "\nlength " (rtos total))))

;; ---- where the object came from --------------------------------------
;; the last line this run drew, however it is reached
(defun c:MOVELAST ( / ss)
  (command "_.LINE" '(0.0 0.0) '(1.0 1.0) "")
  (setq ss (ssget "_L"))
  (command "_.MOVE" ss "" '(0.0 0.0) '(1.0 0.0))
  (princ "\nmoved"))
(defun c:COPYMOVE ( / o c)
  (setq o (vlax-ename->vla-object (car (entsel)))
        c (vla-Copy o))
  (vl-catch-all-apply 'vla-Move
                      (list c (vlax-3d-point 0 0 0) (vlax-3d-point 1 0 0)))
  (princ "\nmoved the copy"))
;; a helper every caller hands a new object
(defun ps:kill (e) (entdel e) (princ "\nerased"))
(defun c:PARAMFRESH ()
  (ps:kill (entmakex (list '(0 . "POINT") '(8 . "MARK") '(10 0.0 0.0 0.0))))
  (princ))
;; a local that is sometimes made and sometimes picked is the drafter's
(defun c:SOMETIMESPICKED ( / e)
  (setq e (entlast))
  (if (= 1 (getvar "PICKFIRST")) (setq e (car (entsel))))
  (entdel e)
  (princ "\nerased"))
;; a count and a point read off a picked object do not make a tuple the
;; drafter's: the marker in it is still this run's own
(defun c:TUPLEFIELD ( / ss item)
  (setq ss (ssget))
  (entmakex (list '(0 . "POINT") '(8 . "MARK") '(10 0.0 0.0 0.0)))
  (setq item (list (sslength ss) (cdr (assoc 10 (entget (ssname ss 0))))
                   (entlast)))
  (entdel (caddr item))
  (princ "\nmarker erased"))

;; ---- how far after the write a count or a claim is still its own -----
(defun c:TALLYAT3 ( / e n)
  (setq e (car (entsel)) n 0)
  (entdel e)
  (princ "a") (princ "b")
  (setq n (1+ n))
  (princ (itoa n)))
(defun c:TALLYAT4 ( / e n)
  (setq e (car (entsel)) n 0)
  (entdel e)
  (princ "a") (princ "b") (princ "c")
  (setq n (1+ n))
  (princ (itoa n)))
(defun c:CLAIMAT4 ( / e)
  (setq e (car (entsel)))
  (entdel e)
  (princ "a") (princ "b") (princ "c")
  (princ "\nerased"))
(defun c:CLAIMAT5 ( / e)
  (setq e (car (entsel)))
  (entdel e)
  (princ "a") (princ "b") (princ "c") (princ "d")
  (princ "\nerased"))

;; ---- two long writes that agree for eighty characters ---------------
(defun c:TWOFILLETS ( / a b)
  (setq a (entsel) b (entsel))
  (command "_.FILLET" a b "_Radius_zero_and_padding_to_carry_it_well_past_eighty" "one")
  (command "_.FILLET" a b "_Radius_zero_and_padding_to_carry_it_well_past_eighty" "two")
  (princ))
"""

print("== check_writes: one fixture per rule ==")
out, _, _ = run(CASES)

for defun, rule, why in (
        ('bad:layer', 'W1', "a layer maker that leaves the lock on"),
        ('bad:layersay', 'W1', "a layer maker that only reports the lock"),
        ('c:BADPURGE', 'W2', "an erase nobody looked at, then a count"),
        ('bad:nudge', 'W2', "a move nobody looked at, then 'MOVED'"),
        ('bad:setattr', 'W2', "a write, then a success flag handed back"),
        ('c:MARKALL', 'W2', "a helper's blind write, then 'marked'"),
        ('c:RESCUEBAD', 'W2', "a helper that answers its write, dropped"),
        ('c:LIARBAD', 'W2', "a helper answering T whatever, trusted"),
        ('c:ERASEBAD', 'W2', "ERASE on the drafter's selection"),
        ('c:ROTASK', 'W2', "an unlock the drafter can refuse (DIMCHECK)"),
        ('c:SCALESAY', 'W2', "a lock read, said, and carried past"),
        ('c:PROBEBAD', 'W2', "scratch drawn on the current layer"),
        ('ob:bad', 'W2', "an erase, then 'erased', never looked at"),
        ('uc:kept', 'W2', "a count a caller keeps and reports"),
        ('c:LOOPTHENSAY', 'W2', "a loop of erases, then 'erased' after it"),
        ('c:LOOPINBRANCH', 'W2', "...found past the progn the loop ends"),
        ('c:NESTEDLOOPS', 'W2', "...and past the loop around that loop"),
        ('c:PAINTLOOP', 'W2', "a loop of blind helper calls, then a claim"),
        ('c:VLALAYBAD', 'W1', "(vla-Add (vla-get-Layers doc) name)"),
        ('c:VLALAYBAD2', 'W1', "vla-Add through a local collection"),
        ('c:REVIEWSCALE', 'W2', "a gate on a helper that only calls a "
                                "lock reader"),
        ('c:DIMTYPE', 'W2', "a gate on (logand 7 ...), a dimension type"),
        ('c:SCALEOTHER', 'W2', "a lock reader about another selection"),
        ('c:ROTASK2', 'W2', "an unlock behind a helper that asks"),
        ('c:VLADEL', 'W2', "(vl-catch-all-apply 'vla-delete ...), claimed"),
        ('c:MAPDEL', 'W2', "(mapcar 'entdel lst), claimed"),
        ('c:CONSGONE', 'W2', "(setq gone (cons e gone)), told"),
        ('c:SSADDDONE', 'W2', "(ssadd e done)"),
        ('c:PLUSONE', 'W2', "(setq n (+ n 1)), told"),
        ('c:SOMETIMESPICKED', 'W2', "made OR picked is the drafter's"),
        ('c:TALLYAT3', 'W2', "a count three statements on"),
        ('c:CLAIMAT4', 'W2', "a claim four statements on")):
    check("%s fires: %s" % (rule, why), rule in rules(out, defun), out)

for defun, why in (
        ('ok:layer', "a layer maker that clears bit 4"),
        ('c:OKPURGE', "(if (entdel en) (setq n (1+ n)))"),
        ('ok:nudge', "the move's answer decides the message"),
        ('ok:nudgesaid', "a sentence that says it did NOT happen"),
        ('ok:stopflag', "a (setq stop T) nobody hands back"),
        ('c:RESCUEOK', "(if (sc:color e 256) (setq n (1+ n)))"),
        ('c:ERASEFRESH', "ERASE of what this run just drew"),
        ('c:ROTOK', "an unconditional unlock for the run"),
        ('c:SCALEOK', "the SCALE sits behind the lock reader's answer"),
        ('c:PROBEOK', "scratch on a named layer"),
        ('c:RELOCK', "a layer record (TABLE)"),
        ('pv:kill', "a preview list only a drawing helper fills (FRESH)"),
        ('c:SWEEPNEW', "everything drawn since an (entlast) mark"),
        ('gt:move', "a second write past a tested first (GATED)"),
        ('mg:review', "a colour past a tested merge of the pair (GATED)"),
        ('ob:del', "an erase looked at with (entget e) (OBSERVED)"),
        ('c:WALKDEL', "(setq i (1+ i)) walks the set, counts nothing"),
        ('uc:dropped', "a count every caller drops"),
        ('c:LOOPCOUNTS', "a loop whose own told count feeds the report"),
        ('c:LOOPFARSAY', "a claim five statements after the loop"),
        ('c:NESTEDCOUNT', "an outer loop whose told count feeds the report"),
        ('c:FOREACHBIND', "a foreach variable is the list's, not the "
                          "local of the same name"),
        ('c:LEFTALONE', "\"...not\" \" erased.\" is one denial"),
        ('c:ASKPLACED', "a question is not a claim"),
        ('c:VLALAYOK', "vla-Add, then vla-put-Lock :vlax-false"),
        ('cu:layer', "a layer helper that runs -LAYER _Unlock"),
        ('c:XSCALE', "a gate two readers deep (xft:ss-locked)"),
        ('c:ROTVIA', "a parameter every caller unlocked"),
        ('c:PAINTPAIR', "writes whose answers are kept and tested"),
        ('ob:sameline', "an erase looked at on its own line"),
        ('ob:late', "an erase looked at later on"),
        ('c:FILLETOBS', "a FILLET read back through (entlast)"),
        ('c:CONSTEXT', "report text consed on is not a count"),
        ('c:SUMUP', "(+ total (cdr ...)) counts no write"),
        ('c:MOVELAST', "(ssget \"_L\") after this run's LINE"),
        ('c:COPYMOVE', "a vla-Copy is not its source"),
        ('c:PARAMFRESH', "a parameter every caller makes new"),
        ('c:TUPLEFIELD', "a count and a point do not make a tuple found"),
        ('c:TALLYAT4', "a count four statements on"),
        ('c:CLAIMAT5', "a claim five statements on")):
    check("quiet: %s" % why, not rules(out, defun), rules(out, defun))

# the exemptions are named, so --list says WHY a write passed
out, _, _ = run(CASES, show=True)
listed = '\n'.join(out)
for reason, defun in (('TABLE', 'c:RELOCK'), ('FRESH', 'pv:kill'),
                      ('SCREENED', 'c:ROTOK'), ('SCREENED', 'c:SCALEOK'),
                      ('SCREENED', 'c:XSCALE'), ('SCREENED', 'sc:rot'),
                      ('GATED', 'gt:move'), ('OBSERVED', 'ob:del'),
                      ('OBSERVED', 'ob:sameline'), ('OBSERVED', 'ob:late'),
                      ('OBSERVED', 'c:FILLETOBS'), ('FRESH', 'c:FOREACHBIND'),
                      ('FRESH', 'c:MOVELAST'), ('FRESH', 'c:COPYMOVE'),
                      ('FRESH', 'ps:kill'), ('FRESH', 'c:TUPLEFIELD')):
    check("--list names %s for %s" % (reason, defun),
          re.search(r'exempt %s %s ' % (reason, re.escape(defun)), listed),
          [ln for ln in out if defun in ln])
check("--list shows the W3 a loop index leaves behind",
      'W3' in rules(out, 'c:WALKDEL'), rules(out, 'c:WALKDEL'))

print("== the baseline ==")
out, _, _ = run(CASES)


def what_of(defun, nth=0):
    """the fingerprint check_writes prints for DEFUN's NTH site"""
    site = [ln for ln in out if ' %s ' % defun in ln][nth]
    return site.split('what: ', 1)[1]


w_erase, w_rot, w_say = (what_of('c:ERASEBAD'), what_of('c:ROTASK'),
                         what_of('c:SCALESAY'))
w_f1, w_f2 = what_of('c:TWOFILLETS', 0), what_of('c:TWOFILLETS', 1)
check("two writes that agree for 80 characters are two fingerprints",
      w_f1 != w_f2 and w_f1[:80] == w_f2[:80], (w_f1, w_f2))
base, bad = check_writes.parse_baseline([
    '# a comment',
    'CASES.lsp|c:ERASEBAD|%s|needs=(ssget)|read and accepted' % w_erase,
    # the token lives in the site's own defun
    'CASES.lsp|c:ROTASK|%s|needs=(ul:free ss)|the unlock it rests on' % w_rot,
    # ...or in the one named after the @, and a called helper's
    # namespace is not compared: shared/ spells it cal:
    'CASES.lsp|c:SCALESAY|%s|needs=(cal:free ss)@c:rotok|elsewhere' % w_say,
    'CASES.lsp|c:TWOFILLETS|%s|needs=(entsel)|the first one only' % w_f1,
    # the protection a line rests on, removed
    'CASES.lsp|c:ERASEFRESH|(entdel e)|needs=(entlast)|no such write',
    'CASES.lsp|c:gone|(entdel e)|needs=(entget e)|a write since removed',
    'CASES.lsp|c:MARKALL|(sp:paint e)|needs=(sp:unlock-first ss)|the gate '
    'this line was written for, since taken out',
    # another tool's line excuses nothing here
    'lisp/other/OTHER.lsp|c:CLAIMAT4|%s|needs=(entsel)|wrong tool'
    % what_of('c:CLAIMAT4'),
    # no needs=: a line that cannot say what it rests on
    'CASES.lsp|c:PROBEBAD|(entdel e)|reads fine to me',
    'CASES.lsp|c:PROBEBAD|(entdel e)|needs=|an empty needs=',
])
out, met, broken = run(CASES, base)
check("a baselined site whose needs= holds is not a finding",
      not rules(out, 'c:ERASEBAD'), rules(out, 'c:ERASEBAD'))
check("...a needs= token found in the site's own defun",
      not rules(out, 'c:ROTASK'), rules(out, 'c:ROTASK'))
check("...or in the @defun, whatever namespace the helper is called by",
      not rules(out, 'c:SCALESAY'), rules(out, 'c:SCALESAY'))
check("a line for the first of two long writes excuses only the first",
      rules(out, 'c:TWOFILLETS') == ['W2'], rules(out, 'c:TWOFILLETS'))
check("a line whose needs= is gone excuses nothing",
      'W2' in rules(out, 'c:MARKALL'), rules(out, 'c:MARKALL'))
check("...and says so",
      any(' c:MARKALL ' in ln and 'no longer holds: (sp:unlock-first ss) '
          'is gone from c:markall' in ln for ln in out),
      [ln for ln in out if 'MARKALL' in ln])
check("...and is reported stale, with the token that went",
      ('CASES.lsp', 'c:MARKALL', '(sp:paint e)')
      in check_writes.stale(base, met) and
      broken.get(('cases', 'c:markall', '(sp:paint e)')) ==
      [('(sp:unlock-first ss)', 'c:markall')], broken)
check("a line whose write is gone is reported stale",
      ('CASES.lsp', 'c:gone', '(entdel e)') in check_writes.stale(base, met),
      check_writes.stale(base, met))
check("a line naming another tool's file excuses nothing, and is stale",
      'W2' in rules(out, 'c:CLAIMAT4') and any(
          d == 'c:CLAIMAT4' for f, d, w in check_writes.stale(base, met)),
      rules(out, 'c:CLAIMAT4'))
check("a line with no needs= (or an empty one) is refused as malformed",
      len(bad) == 2 and all('c:PROBEBAD' in b for b in bad), bad)
check("a baseline line cannot excuse W1",
      'W1' in rules(out, 'bad:layer'), rules(out, 'bad:layer'))
check("the three tiers' spellings of one tool are one tool",
      check_writes.tool_stem('releases/PADDLE_092326_REV117.lsp') ==
      check_writes.tool_stem('shared/parts/PADDLE.lsp') ==
      check_writes.tool_stem('lisp/paddle/PADDLE.lsp') == 'paddle' and
      check_writes.tool_stem('releases/STEPS_092326_REV415-325-320.lsp')
      == 'steps')

print("== the real baseline is read ==")
real, realbad = check_writes.load_baseline()
check("tools/write_baseline.txt parses: every line has a needs= and a "
      "reason", real and not realbad and all(
          needs and why.strip() for f, d, needs, why in real.values()),
      realbad or len(real))

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall check_writes rules fire, and the right shapes pass")
