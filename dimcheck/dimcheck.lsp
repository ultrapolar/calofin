;;; ------------------------------------------------------------------
;;;  dimcheck.lsp — DIMCHECK: interactive dimension & arc QA review
;;;
;;;  Based on check_drawing.lsp (CHECK), reworked into a guided,
;;;  one-at-a-time review. Type DIMCHECK, then:
;;;
;;;  1. You are asked to highlight the drawing (any selection).
;;;     Everything selected is greyed out so only the item under
;;;     review stands out.
;;;
;;;  2. Dimensions are reviewed ONE AT A TIME, in a fixed marching
;;;     order: grouped by dimension style — "STANDARD", then "SIDE
;;;     STANDARD", then "STANDARD INCHES", then "CROSS DIMENSIONS",
;;;     then whatever styles are left (tune *dchk-style-order*) —
;;;     and inside each group left to right, top to bottom (row by
;;;     row, like reading). Each dimension is zoomed to, shown in
;;;     its own colour and highlighted while the rest stays grey. For linear/aligned dimensions the two
;;;     definition points are audited first: a point that does not
;;;     sit on any object is moved onto the closest object, marked
;;;     with a cross on screen, and you are asked — one point at a
;;;     time — whether the moved location is correct:
;;;         Enter / Y  ->  keep it there
;;;         N          ->  you pick the correct location yourself
;;;     A construction line (XLINE) is drawn through the dimension's
;;;     original points on layer DIMCHECK-CONSTRUCTION so you can see
;;;     where it used to measure.
;;;     Then the overall question for every dimension:
;;;         "Is this dimension correct?"
;;;         Enter / Y  ->  correct, the dimension is left alone
;;;         N          ->  the dimension is recoloured RED so it is
;;;                        easy to find and fix afterwards
;;;
;;;  3. Arcs are reviewed the same way, one endpoint at a time. An
;;;     endpoint that is not attached to the end of another object is
;;;     snapped there (same rules as CHECK), marked with a cross, and
;;;     you confirm each moved point — Enter keeps it, N lets you
;;;     pick where it belongs (the arc is re-fitted through your
;;;     point). Arcs whose endpoints changed are recoloured MAGENTA.
;;;
;;;  4. OVERLAPPING LINES are hunted down: two straight LINE entities
;;;     that are collinear and run on top of each other (a leftover
;;;     from drawing over an existing line to continue it and never
;;;     cleaning it up). Each overlapping pair is zoomed to and
;;;     highlighted, the overlapping stretch is marked with crosses,
;;;     and you choose:
;;;         Enter / M  ->  MERGE the two into one line spanning both
;;;                        (only when they share a layer; the merged
;;;                        line turns CYAN so you can see it changed)
;;;         F          ->  FLAG both lines CYAN to fix by hand
;;;         L          ->  LEAVE them as drawn (intentional)
;;;     Lines that merely touch end-to-end are fine and not reported.
;;;
;;;  5. STEP / STAIRCASE check. Groups of 3+ parallel lines stacked
;;;     less than 18 units apart (18" in inch drawings — tune
;;;     *dchk-step-maxgap*) look like steps. When such patterns are
;;;     found, DIMCHECK first looks for a SIDE VIEW in the selection
;;;     (a side view reads as two step patterns at right angles to
;;;     each other — treads + risers — in the same spot, each one
;;;     marching along like a profile rather than sitting stacked).
;;;     Benches count: their profile is only two treads deep, so
;;;     side-view halves are found down to *dchk-bench-minlines*
;;;     while the "are these steps?" prompt still needs a full-size
;;;     *dchk-step-minlines* pattern. Whatever the side view belongs
;;;     to — stairs or a bench — its overall height is confirmed
;;;     against the Finished Wall Ht (see below).
;;;       - Side view found  -> steps are taken as real; skip ahead.
;;;       - No side view     -> each pattern is highlighted and you
;;;         are asked "Are these lines steps?". If any are, you are
;;;         asked whether a side view is drawn somewhere; if not, the
;;;         report tells you to ADD A SIDE VIEW.
;;;     Whenever steps + side view are present, the selection must
;;;     hold a block with the words "Step Attachment" (block name,
;;;     attribute or text inside it). None -> the report tells you to
;;;     add one. Found -> it is zoomed to and you confirm the CORRECT
;;;     one is placed; answering No flags it red and reports it.
;;;     When the attachment style is "BEAD Step Attachment", every
;;;     plan-view step pattern must also have something drawn on
;;;     layer "Bead Track" (tune *dchk-bead-layer*) within
;;;     *dchk-bead-dist* of it. The whole drawing is searched, not
;;;     just the selection. The side view itself is exempt — bead
;;;     track is only demanded next to the plan-view steps. Patterns
;;;     with nothing nearby are called out in the report.
;;;     The OVERALL HEIGHT of the steps is confirmed too: measured
;;;     from the side view's geometry (its total rise), or typed /
;;;     picked as two points when the side view was not auto-found,
;;;     and compared against the WallHt attribute of the "Tech
;;;     Title" block (found space-insensitively, drawing-wide; tune
;;;     *dchk-title-block* / *dchk-wallht-tag*). Heights written as
;;;     40'', 3'-4'', 3' 4 1/2" or 40.5 are all understood, and a
;;;     label is ignored, so the attribute may read "Finished Wall
;;;     Ht = 40''" and still measure 40. When the side view carries
;;;     its own overall-height dimension (the one whose definition
;;;     points span the full rise), that dimension is what gets
;;;     compared — and if it disagrees with WallHt, or its text was
;;;     overridden to disagree with the geometry it spans, it is
;;;     MARKED RED AUTOMATICALLY and reported. Any difference beyond
;;;     *dchk-height-tol* is reported in red as a MISMATCH.
;;;     Two title-block answers give nothing to check against, so
;;;     the side view is LEFT ALONE (never marked red) in both:
;;;       - "Finished Wall Ht = Varies" — the height genuinely
;;;         varies; the report just notes it.
;;;       - several heights at once, e.g. "= 0'', 40'', 45''" — the
;;;         report tells you to CHECK THE WALL HEIGHT in the title
;;;         block. A compound height ( 3'-4'' ) is still one value,
;;;         not several.
;;;
;;;  6. LINER MATERIAL check. The selection must hold a block named
;;;     (or containing the words) "Liner Material" / "Liner Material
;;;     with Step". Missing -> reported. Each one found is scanned
;;;     for the standalone words "NOT" and "ERROR" in its attributes
;;;     and text (e.g. "Not Selected", "Not Included", "#ERROR");
;;;     any hit is reported with the block's location so you can
;;;     look at it. The liner pattern must also agree with how the
;;;     steps are built:
;;;       - a FIBERGLASS STEP anywhere in the highlighted area (as
;;;         text, a block, or the layer things sit on — see
;;;         *dchk-fgstep-words*) is its own unit, so the liner must
;;;         NOT carry a Step. One that does is reported.
;;;       - otherwise, when steps are drawn, the liner must cover
;;;         them: no liner block carrying a "Step" section (the
;;;         "Liner Material with Step" variant) is reported.
;;;
;;;  7. A DIMCHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;     drawing on layer DIMCHECK-REPORT listing every dimension —
;;;     with its measured distance (in the drawing's units; angular
;;;     dims show their angle) — every arc, every overlapping line
;;;     pair (with its overlap length), every step pattern, the Step
;;;     Attachment verdict and the Liner Material verdict, plus
;;;     totals. The report text is sized from the drawing's extents
;;;     so it sits to scale next to it. Any line describing something
;;;     questionable or that needs looking over (a flagged/wrong
;;;     item, a missing block, a "NOT" find, an "add ..." note, a
;;;     skipped check) is coloured RED in the report; everything
;;;     that checked out stays the report's normal colour and is
;;;     drawn at *dchk-green-scale* (3/4) of the red text's height,
;;;     so the problems are the big lines on the sheet.
;;;
;;;  All original colours are restored when the review ends — except
;;;  the red "fix me" dimensions, magenta moved arcs and cyan
;;;  merged/flagged lines, which stay marked on purpose. Everything
;;;  (including the report) runs inside one UNDO group, so a single U
;;;  reverts the whole review.
;;;
;;;  SAFETY NETS
;;;  - Locked layers in the selection are announced up front with an
;;;    offer to unlock for the run (re-locked afterwards, even on
;;;    error); left locked, their items are reported but untouched.
;;;  - Object-associative dimensions are warned about before their
;;;    points are moved — an associative point may re-anchor on its
;;;    own — and their report line says so in red.
;;;  - Rerunning DIMCHECK replaces the previous report and marker
;;;    lines instead of stacking a second copy on top.
;;;  - Original colours are stashed in xdata before greying. If a
;;;    crash or kill ever leaves the drawing grey, DIMCHECKRESCUE
;;;    restores every stashed colour and clears DIMCHECK's report
;;;    and markers (flag colours included — it is the full reset).
;;;  - With several Tech Title blocks on the sheet, the one nearest
;;;    the checked area is used; titles disagreeing on WallHt are
;;;    called out in red.
;;; ------------------------------------------------------------------

(vl-load-com)

;; --- tunables ------------------------------------------------------
(setq *dchk-tol*          1.0e-4)  ; max gap (drawing units) that still counts as attached
(setq *dchk-grey-color*   8)       ; grey used to fade out everything not under review
(setq *dchk-flag-color*   1)       ; red: dimensions you answered "No" to
(setq *dchk-arc-color*    6)       ; magenta: arcs whose endpoints were moved
(setq *dchk-olap-color*   4)       ; cyan: merged or flagged overlapping lines
(setq *dchk-olap-fuzz*    1.0e-4)  ; max sideways offset that still counts as "same line"
(setq *dchk-step-maxgap*  18.0)    ; steps: max tread spacing (drawing units; 18 = 18" when 1 unit = 1")
(setq *dchk-step-minlines* 3)      ; steps: how many stacked parallel lines look like steps
(setq *dchk-bench-minlines* 2)     ; side view: a bench profile is only two treads deep
(setq *dchk-step-angtol*  1.0)     ; steps: parallelism tolerance (degrees)
(setq *dchk-bead-layer*   "Bead Track") ; layer bead track must be drawn on
(setq *dchk-bead-dist*    18.0)    ; how close bead track must be to plan-view steps (units)
(setq *dchk-title-block*  "Tech Title") ; title block holding the wall height (spaces optional)
(setq *dchk-wallht-tag*   "WallHt")     ; attribute tag carrying the wall height
(setq *dchk-height-tol*   0.25)    ; steps height vs WallHt: allowed difference (units)

;; dimension styles are reviewed in this order; styles not listed
;; come afterwards ("whatever else is left"), still left-to-right
(setq *dchk-style-order*
      '("STANDARD" "SIDE STANDARD" "STANDARD INCHES" "CROSS DIMENSIONS"))
(setq *dchk-constr-layer* "DIMCHECK-CONSTRUCTION")
(setq *dchk-constr-color* 2)       ; yellow
(setq *dchk-green-scale*  0.75)    ; report: all-clear text height, as a fraction of the red text
(setq *dchk-block-depth*  3)       ; how many levels of nested blocks to search for names/text
(setq *dchk-fgstep-words*          ; a fiberglass step shows up under any of these
      '("Fiberglass Step" "FG Step"))
(setq *dchk-report-layer* "DIMCHECK-REPORT")
(setq *dchk-report-color* 3)       ; green
(setq *dchk-zoom-margin*  0.75)    ; empty space around the zoomed item (fraction of its size)
(setq *dchk-report-chars* 45.0)    ; report column width, in text heights
(setq *dchk-ask-all-arc-ends* nil) ; T = confirm EVERY arc endpoint, even already-attached ones

;; entity types dimension points and arc ends may attach to
(setq *dchk-curve-types*
      '("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"))

;; --- safety: xdata tags, colour stash, layer locks -----------------

(defun dchk:regapp ()
  (if (not (tblsearch "APPID" "DIMCHECK"))
    (regapp "DIMCHECK")))

(defun dchk:xd (ent / g)
  ;; DIMCHECK's xdata groups on ent, nil when none
  (setq g (assoc -3 (entget ent '("DIMCHECK"))))
  (if g (cdadr g)))

(defun dchk:tag (ent kind / ed)
  ;; stamp a DIMCHECK-created entity (report, marker line) so a rerun
  ;; or DIMCHECKRESCUE can find and clear it
  (dchk:regapp)
  (setq ed (entget ent '("DIMCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "DIMCHECK" (cons 1000 kind))))))))

(defun dchk:stash-color (ent col / ed)
  ;; remember the entity's own colour in xdata so DIMCHECKRESCUE can
  ;; put it back even after a crash; an existing stash (from an
  ;; interrupted run - the TRUE original) is never overwritten
  (dchk:regapp)
  (setq ed (entget ent '("DIMCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "DIMCHECK"
                                            '(1000 . "COLOR")
                                            (cons 1071 col))))))))

(defun dchk:unstash (ent / ed)
  ;; drop DIMCHECK's xdata once the run has restored things itself
  (setq ed (entget ent '("DIMCHECK")))
  (if (and ed (assoc -3 ed))
    (entmod (subst (list -3 (list "DIMCHECK")) (assoc -3 ed) ed))))

(defun dchk:clear-old (/ ss2 i e xd n)
  ;; erase the report and marker lines left by an earlier DIMCHECK
  ;; run, so a rerun replaces them instead of stacking on top
  (setq ss2 (ssget "_X" '((-3 ("DIMCHECK")))) n 0 i 0)
  (if ss2
    (repeat (sslength ss2)
      (setq e  (ssname ss2 i)
            i  (1+ i)
            xd (dchk:xd e))
      (if (member (cdr (assoc 1000 xd)) '("REPORT" "XLINE"))
        (progn (entdel e) (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\n(Removed " (itoa n)
                   " report/marker item(s) from an earlier DIMCHECK run.)"))))

(defun dchk:layer-locked-p (name / ld)
  (setq ld (tblsearch "LAYER" name))
  (and ld (= 4 (logand 4 (cdr (assoc 70 ld))))))

(defun dchk:set-layer-lock (name lock / ed old new)
  ;; set or clear a layer's locked flag; T when it actually changed
  (setq ed  (entget (tblobjname "LAYER" name))
        old (cdr (assoc 70 ed))
        new (if lock (logior old 4) (logand old (~ 4))))
  (if (/= old new)
    (progn (entmod (subst (cons 70 new) (assoc 70 ed) ed)) T)))

(defun dchk:dim-assoc-p (ent / found g)
  ;; T when the dimension carries persistent reactors - the mark of
  ;; an object-associative dim, whose definition points may re-anchor
  ;; on their own after being moved
  (foreach g (entget ent)
    (if (and (= 102 (car g)) (= "{ACAD_REACTORS" (cdr g)))
      (setq found T)))
  found)

(defun c:DIMCHECKRESCUE ( / ss i e xd n)
  ;; the way out after a crash or interrupted run: puts back every
  ;; colour DIMCHECK stashed (flag colours included) and removes its
  ;; report and marker lines
  (setq ss (ssget "_X" '((-3 ("DIMCHECK")))) n 0 i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            xd (dchk:xd e))
      (cond
        ((member (cdr (assoc 1000 xd)) '("REPORT" "XLINE"))
         (entdel e)
         (setq n (1+ n)))
        ((assoc 1071 xd)
         (dchk:set-color e (cdr (assoc 1071 xd)))
         (dchk:unstash e)
         (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\nDIMCHECKRESCUE: restored or removed " (itoa n) " item(s)."))
    (princ "\nDIMCHECKRESCUE: nothing to restore - no DIMCHECK markers in the drawing."))
  (princ))

;; --- small helpers -------------------------------------------------

(defun dchk:ensure-layer (name color)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   '(70 . 0)
                   (cons 62 color)))))

(defun dchk:ent-color (ent / c)
  ;; the entity's explicit colour, 256 (ByLayer) when it has none
  (setq c (cdr (assoc 62 (entget ent))))
  (if c c 256))

(defun dchk:set-color (ent color / ed old)
  (setq ed  (entget ent)
        old (assoc 62 ed))
  (entmod (if old
            (subst (cons 62 color) old ed)
            (append ed (list (cons 62 color)))))
  (entupd ent))

(defun dchk:make-xline (p1 p2 / len)
  ;; infinite construction line through p1-p2 on the check layer,
  ;; tagged so reruns and DIMCHECKRESCUE can clear it
  (setq len (distance p1 p2))
  (if (and (> len 1e-8)
           (entmake (list '(0 . "XLINE")
                          '(100 . "AcDbEntity")
                          (cons 8 *dchk-constr-layer*)
                          '(100 . "AcDbXline")
                          (cons 10 p1)
                          (cons 11 (mapcar '(lambda (x) (/ x len))
                                           (mapcar '- p2 p1))))))
    (dchk:tag (entlast) "XLINE")))

(defun dchk:closest-on (ent pt / res)
  ;; closest point on ent to pt; nil when ent is not curve-like
  (setq res (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (vl-catch-all-error-p res) nil res))

(defun dchk:nearest-curve (pt exclude cands / best bestd cp d e)
  ;; (ent closest-point distance) for the candidate closest to pt
  (foreach e cands
    (if (and (not (eq e exclude)) (setq cp (dchk:closest-on e pt)))
      (progn
        (setq d (distance pt cp))
        (if (or (null bestd) (< d bestd))
          (setq bestd d
                best  (list e cp d))))))
  best)

(defun dchk:curve-ends (ent / cl sp ep)
  ;; the curve's two endpoints; nil when closed (or not a curve)
  (setq cl (vl-catch-all-apply 'vlax-curve-isClosed (list ent)))
  (if (or (vl-catch-all-error-p cl) cl)
    nil
    (progn
      (setq sp (vl-catch-all-apply 'vlax-curve-getStartPoint (list ent))
            ep (vl-catch-all-apply 'vlax-curve-getEndPoint (list ent)))
      (if (or (vl-catch-all-error-p sp) (vl-catch-all-error-p ep))
        nil
        (list sp ep)))))

(defun dchk:closest-of (pt pts / best bestd d q)
  (foreach q pts
    (setq d (distance pt q))
    (if (or (null bestd) (< d bestd)) (setq bestd d best q)))
  best)

(defun dchk:nearest-end (pt exclude cands / best bestd d e q)
  ;; closest endpoint over every open candidate curve
  (foreach e cands
    (if (not (eq e exclude))
      (foreach q (dchk:curve-ends e)
        (setq d (distance pt q))
        (if (or (null bestd) (< d bestd)) (setq bestd d best q)))))
  best)

(defun dchk:ptstr (p)
  (strcat "(" (rtos (car p) 2 4) ", " (rtos (cadr p) 2 4) ")"))

(defun dchk:pad2 (n)
  (if (< n 10) (strcat "0" (itoa n)) (itoa n)))

(defun dchk:datestr (/ d dd tt)
  ;; CDATE is YYYYMMDD.HHMMSSmsec; decoded arithmetically so DIMZIN
  ;; (which trims rtos output) cannot mangle it
  (setq d  (getvar "CDATE")
        dd (fix d)
        tt (- d dd))
  (strcat (itoa (fix (/ dd 10000))) "-"
          (dchk:pad2 (rem (fix (/ dd 100)) 100)) "-"
          (dchk:pad2 (rem dd 100)) " "
          (dchk:pad2 (fix (+ (* tt 100) 1e-6))) ":"
          (dchk:pad2 (rem (fix (+ (* tt 10000) 1e-4)) 100))))

(defun dchk:bbox (ent / obj ll ur)
  ;; ((minx miny minz) (maxx maxy maxz)) in WCS, or nil
  (setq obj (vlax-ename->vla-object ent))
  (if (not (vl-catch-all-error-p
             (vl-catch-all-apply 'vla-getboundingbox (list obj 'll 'ur))))
    (list (vlax-safearray->list ll) (vlax-safearray->list ur))))

(defun dchk:zoom-ent (ent / bb p1 p2 m)
  ;; zoom the current view onto ent with some breathing room
  (setq bb (dchk:bbox ent))
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *dchk-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

(defun dchk:zoom-2ents (e1 e2 / b1 b2 p1 p2 m)
  ;; zoom onto the combined box of two entities
  (setq b1 (dchk:bbox e1)
        b2 (dchk:bbox e2))
  (cond
    ((and b1 b2)
     (setq p1 (list (min (caar b1) (caar b2))
                    (min (cadar b1) (cadar b2)))
           p2 (list (max (caadr b1) (caadr b2))
                    (max (cadadr b1) (cadadr b2)))
           m  (* *dchk-zoom-margin*
                 (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
     (command "_.ZOOM" "_Window"
              (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
              (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))
    (b1 (dchk:zoom-ent e1))
    (b2 (dchk:zoom-ent e2))))

(defun dchk:stage (ent saved keep)
  ;; bring an entity back to its own colour for review — unless it
  ;; already wears a DIMCHECK marker colour it must not lose
  (if (and (entget ent) (not (member ent keep)))
    (dchk:set-color ent (cdr (assoc ent saved)))))

(defun dchk:unstage (ent keep)
  ;; send a reviewed entity back into the grey background
  (if (and (entget ent) (not (member ent keep)))
    (dchk:set-color ent *dchk-grey-color*)))

(defun dchk:mark-point (pt / p s)
  ;; temporary cross + X over the point under review (WCS in, screen out)
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (cadr p)) (list (+ (car p) s) (cadr p)) 2 1)
  (grdraw (list (car p) (- (cadr p) s)) (list (car p) (+ (cadr p) s)) 2 1)
  (grdraw (list (- (car p) s) (- (cadr p) s)) (list (+ (car p) s) (+ (cadr p) s)) 2 1)
  (grdraw (list (- (car p) s) (+ (cadr p) s)) (list (+ (car p) s) (- (cadr p) s)) 2 1))

(defun dchk:ask-yn (msg / ans)
  ;; T = yes (Enter or Y), nil = no (N)
  (initget "Yes No")
  (setq ans (getkword (strcat msg " [Yes/No] <Yes>: ")))
  (or (null ans) (= ans "Yes")))

(defun dchk:ask-yn-nav (msg / ans)
  ;; the reviewing question, with a way out of a mis-press:
  ;; 'yes 'no 'back (redo the previous item) 'skip (stop asking,
  ;; finish the run and still write the report)
  (initget "Yes No Back Skip")
  (setq ans (getkword (strcat msg " [Yes/No/Back/Skip rest] <Yes>: ")))
  (cond ((null ans)      'yes)
        ((= ans "Yes")   'yes)
        ((= ans "No")    'no)
        ((= ans "Back")  'back)
        (t               'skip)))

(defun dchk:progress (what n total)
  (princ (strcat "\r  [" (itoa n) "/" (itoa total) "] " what "          ")))

(defun dchk:confirm-point (label pt / newp)
  ;; marks pt (WCS), asks whether the location is correct; returns the
  ;; user's replacement point (in the CURRENT UCS) or nil to keep pt
  (dchk:mark-point pt)
  (if (dchk:ask-yn (strcat "\n  " label " is now at " (dchk:ptstr pt)
                           ". Is this location correct?"))
    nil
    (getpoint (strcat "\n  Pick the correct location for " label
                      " <keep current>: "))))

(defun dchk:mtext (ins height width text layer / dxf)
  ;; entmake an MTEXT, splitting text into 250-char DXF chunks
  (setq dxf (list '(0 . "MTEXT")
                  '(100 . "AcDbEntity")
                  (cons 8 layer)
                  '(100 . "AcDbMText")
                  (cons 10 ins)
                  (cons 40 height)
                  (cons 41 width)
                  '(71 . 1)))                  ; attachment: top-left
  (while (> (strlen text) 250)
    (setq dxf  (append dxf (list (cons 3 (substr text 1 250))))
          text (substr text 251)))
  (if (entmake (append dxf (list (cons 1 text))))
    (dchk:tag (entlast) "REPORT")))

(defun dchk:attn-p (s)
  ;; T when a report line describes something questionable or that
  ;; needs looking over / fixing, so the report renders it in red
  (wcmatch (strcase s)
    "*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO SIDE VIEW*,*NO 'STEP*,*NO BLOCK*,*WORD NOT*,*WORD ERROR*,* ADD *,*MISMATCH*,*NOT CONFIRMED*,*CHECK THE WALL HEIGHT*,*FIBERGLASS STEP*,*ASSOCIATIVE*,*DISAGREE*"))

(defun dchk:red (s)
  ;; wrap an MTEXT run so it renders in the flag colour, reverting
  ;; to the surrounding colour after (braces scope the change)
  (strcat "{\\C" (itoa *dchk-flag-color*) ";" s "}"))

(defun dchk:small (s)
  ;; all-clear text renders at *dchk-green-scale* of the height the
  ;; red attention text gets, so problems stand out on the sheet
  (strcat "{\\H" (rtos *dchk-green-scale* 2 4) "x;" s "}"))

;; --- geometry ------------------------------------------------------

(defun dchk:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

(defun dchk:circumcenter (p1 p2 p3 / ax ay bx by cx cy d)
  ;; center of the circle through three points (plan view, z taken
  ;; from p1); nil when the points are collinear
  (setq ax (car p1) ay (cadr p1)
        bx (car p2) by (cadr p2)
        cx (car p3) cy (cadr p3)
        d  (* 2.0 (+ (* ax (- by cy)) (* bx (- cy ay)) (* cx (- ay by)))))
  (if (> (abs d) 1e-12)
    (list (/ (+ (* (+ (* ax ax) (* ay ay)) (- by cy))
                (* (+ (* bx bx) (* by by)) (- cy ay))
                (* (+ (* cx cx) (* cy cy)) (- ay by)))
             d)
          (/ (+ (* (+ (* ax ax) (* ay ay)) (- cx bx))
                (* (+ (* bx bx) (* by by)) (- ax cx))
                (* (+ (* cx cx) (* cy cy)) (- bx ax)))
             d)
          (caddr p1))))

(defun dchk:planar-arc-p (ed / n)
  ;; only arcs drawn in the world XY plane are handled
  (setq n (cdr (assoc 210 ed)))
  (or (null n)
      (and (< (abs (car n)) 1e-9)
           (< (abs (cadr n)) 1e-9)
           (> (caddr n) 0.0))))

(defun dchk:rebuild-arc (ent which fixed mid target / c r a1 a2 am tmp ed pair)
  ;; re-fit the arc through its fixed end, its old midpoint and the
  ;; target point; returns T on success
  (if (and (> (distance target fixed) 1e-8)
           (setq c (dchk:circumcenter fixed mid target)))
    (progn
      (setq r  (distance c target)
            a1 (angle c (if (eq which 'start) target fixed))
            a2 (angle c (if (eq which 'start) fixed target))
            am (angle c mid))
      ;; ARC entities always sweep counter-clockwise from start to
      ;; end; keep the sweep that contains the old midpoint
      (if (> (dchk:angnorm (- am a1)) (dchk:angnorm (- a2 a1)))
        (setq tmp a1
              a1  a2
              a2  tmp))
      (setq ed (entget ent))
      (foreach pair (list (cons 10 c) (cons 40 r) (cons 50 a1) (cons 51 a2))
        (setq ed (subst pair (assoc (car pair) ed) ed)))
      (if (entmod ed)
        (progn (entupd ent) T)))))

(defun dchk:move-arc-end (ent which target / mid other)
  ;; re-fit the arc so the chosen endpoint lands on target (WCS)
  (setq mid   (vlax-curve-getPointAtDist
                ent
                (/ (vlax-curve-getDistAtParam ent (vlax-curve-getEndParam ent)) 2.0))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent)))
  (dchk:rebuild-arc ent which other mid target))

(defun dchk:unit (v / l)
  ;; v scaled to length 1; nil for a (near-)zero vector
  (setq l (distance '(0.0 0.0 0.0) v))
  (if (> l 1e-12)
    (mapcar '(lambda (x) (/ x l)) v)))

(defun dchk:proj-param (p a u)
  ;; signed distance of p along the axis through a with unit dir u
  (apply '+ (mapcar '* (mapcar '- p a) u)))

(defun dchk:axis-pt (a u s)
  ;; the point at parameter s on that axis
  (mapcar '+ a (mapcar '(lambda (x) (* x s)) u)))

(defun dchk:pt-line-dist (p a u / s)
  ;; distance from p to the infinite line through a with unit dir u
  (setq s (dchk:proj-param p a u))
  (distance p (dchk:axis-pt a u s)))

(defun dchk:overlap-info (la lb / a1 a2 b1 b2 u lena s1 s2 tmp lo hi)
  ;; when segments la and lb are collinear (within *dchk-olap-fuzz*)
  ;; and run on top of each other for more than *dchk-tol*, returns
  ;;   (ov-start ov-end ov-length union-start union-end)
  ;; nil when they do not overlap (touching end-to-end is fine)
  (setq a1 (dchk:seg-p1 la)
        a2 (dchk:seg-p2 la)
        b1 (dchk:seg-p1 lb)
        b2 (dchk:seg-p2 lb)
        u  (dchk:unit (mapcar '- a2 a1)))
  (if (and u
           (<= (dchk:pt-line-dist b1 a1 u) *dchk-olap-fuzz*)
           (<= (dchk:pt-line-dist b2 a1 u) *dchk-olap-fuzz*))
    (progn
      (setq lena (distance a1 a2)
            s1   (dchk:proj-param b1 a1 u)
            s2   (dchk:proj-param b2 a1 u))
      (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
      (setq lo (max 0.0 s1)
            hi (min lena s2))
      (if (> (- hi lo) *dchk-tol*)
        (list (dchk:axis-pt a1 u lo)
              (dchk:axis-pt a1 u hi)
              (- hi lo)
              (dchk:axis-pt a1 u (min 0.0 s1))
              (dchk:axis-pt a1 u (max lena s2)))))))

(defun dchk:merge-lines (la lb info / ed)
  ;; stretch la's LINE over the union of both, delete lb's LINE
  (setq ed (entget (dchk:seg-ent la))
        ed (subst (cons 10 (nth 3 info)) (assoc 10 ed) ed)
        ed (subst (cons 11 (nth 4 info)) (assoc 11 ed) ed))
  (entmod ed)
  (entupd (dchk:seg-ent la))
  (entdel (dchk:seg-ent lb)))

(defun dchk:whole-line-p (s / ed)
  ;; T when the segment IS its owner entity - only whole LINEs can be
  ;; merged; a polyline edge has to be fixed by hand
  (setq ed (entget (dchk:seg-ent s)))
  (= "LINE" (cdr (assoc 0 ed))))

(defun dchk:find-overlaps (segs / atol fams a placed fam recs e p1 p2 dx dy
                                off s1 s2 tmp rest r q pairs seen key)
  ;; every overlapping segment pair, without comparing all pairs:
  ;; segments are bucketed by direction, then swept in offset order so
  ;; only genuinely collinear neighbours are ever tested. Segments of
  ;; the same entity are skipped (a polyline meeting itself is not a
  ;; duplicate), as are pairs already found through another segment.
  (setq atol  (* 0.5 (/ pi 180.0))              ; 0.5 deg is ample at this fuzz
        fams  nil
        pairs nil
        seen  nil)
  (foreach e segs
    (setq a      (dchk:seg-dir-ang e)
          placed nil)
    (foreach fam fams
      (if (and (not placed)
               (or (<= (dchk:ang-diff a (car fam)) atol)))
        (setq fams   (subst (cons (car fam) (cons e (cdr fam))) fam fams)
              placed T)))
    (if (not placed) (setq fams (cons (list a e) fams))))
  (foreach fam fams
    (if (cdr (cdr fam))                          ; two or more to compare
      (progn
        (setq a  (car fam)
              dx (cos a)
              dy (sin a)
              recs nil)
        (foreach e (cdr fam)
          (setq p1  (dchk:seg-p1 e)
                p2  (dchk:seg-p2 e)
                off (- (* (cadr p1) dx) (* (car p1) dy))
                s1  (+ (* (car p1) dx) (* (cadr p1) dy))
                s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
          (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
          (setq recs (cons (list off s1 s2 e) recs)))
        (setq recs (dchk:sort-recs recs))
        ;; sorted by offset: only sweep forward while still collinear
        (while recs
          (setq r    (car recs)
                rest (cdr recs))
          (while (and rest
                      (<= (- (car (car rest)) (car r)) *dchk-olap-fuzz*))
            (setq q (car rest))
            (if (and (not (eq (dchk:seg-ent (cadddr r))
                              (dchk:seg-ent (cadddr q))))
                     ;; spans must actually meet before the exact test
                     (> (min (caddr r) (caddr q)) (max (cadr r) (cadr q)))
                     (dchk:overlap-info (cadddr r) (cadddr q)))
              (progn
                (setq key (list (dchk:seg-ent (cadddr r))
                                (dchk:seg-ent (cadddr q))))
                (if (not (member key seen))
                  (setq seen  (cons key (cons (reverse key) seen))
                        pairs (cons (list (cadddr r) (cadddr q)) pairs)))))
            (setq rest (cdr rest)))
          (setq recs (cdr recs))))))
  (reverse pairs))

;; --- step pattern detection ----------------------------------------

;; --- segments: lines AND polyline edges ----------------------------
;; Detection works on "segs" - (start end owner-entity) records - so a
;; side view or a run of steps drawn as one polyline counts exactly
;; like the same shape drawn as separate LINEs.

(defun dchk:seg-p1 (s) (car s))
(defun dchk:seg-p2 (s) (cadr s))
(defun dchk:seg-ent (s) (caddr s))

(defun dchk:ocs->wcs (p nz)
  (if (and nz (not (equal nz '(0.0 0.0 1.0) 1e-9))) (trans p nz 0) p))

(defun dchk:lwpoly-segs (ent / ed nz elev vs bl cls n i segs g)
  ;; straight edges of an LWPOLYLINE; bulged (arc) edges are skipped
  (setq ed   (entget ent)
        nz   (cdr (assoc 210 ed))
        elev (cdr (assoc 38 ed))
        cls  (= 1 (logand 1 (cdr (assoc 70 ed))))
        vs   nil
        bl   nil)
  (if (null elev) (setq elev 0.0))
  (foreach g ed
    (cond
      ((= 10 (car g))
       (setq vs (cons (dchk:ocs->wcs (list (car (cdr g)) (cadr (cdr g)) elev) nz) vs)
             bl (cons 0.0 bl)))
      ((= 42 (car g))
       (if bl (setq bl (cons (cdr g) (cdr bl)))))))
  (setq vs (reverse vs)
        bl (reverse bl)
        n  (length vs)
        i  0)
  (while (< i (1- n))
    (if (equal 0.0 (nth i bl) 1e-12)
      (setq segs (cons (list (nth i vs) (nth (1+ i) vs) ent) segs)))
    (setq i (1+ i)))
  (if (and cls (> n 2) (equal 0.0 (nth (1- n) bl) 1e-12))
    (setq segs (cons (list (nth (1- n) vs) (car vs) ent) segs)))
  segs)

(defun dchk:heavy-poly-segs (ent / e ed vs bl cls n i segs)
  ;; straight edges of an old-style POLYLINE (VERTEX entities)
  (setq cls (= 1 (logand 1 (cdr (assoc 70 (entget ent)))))
        e   (entnext ent)
        vs  nil
        bl  nil)
  (while (and e (= "VERTEX" (cdr (assoc 0 (setq ed (entget e))))))
    (if (zerop (logand 16 (cdr (assoc 70 ed))))    ; skip spline frame points
      (setq vs (cons (cdr (assoc 10 ed)) vs)
            bl (cons (if (assoc 42 ed) (cdr (assoc 42 ed)) 0.0) bl)))
    (setq e (entnext e)))
  (setq vs (reverse vs)
        bl (reverse bl)
        n  (length vs)
        i  0)
  (while (< i (1- n))
    (if (equal 0.0 (nth i bl) 1e-12)
      (setq segs (cons (list (nth i vs) (nth (1+ i) vs) ent) segs)))
    (setq i (1+ i)))
  (if (and cls (> n 2) (equal 0.0 (nth (1- n) bl) 1e-12))
    (setq segs (cons (list (nth (1- n) vs) (car vs) ent) segs)))
  segs)

(defun dchk:ent-segs (ent / ed et)
  ;; every straight segment an entity contributes, in WCS
  (setq ed (entget ent)
        et (cdr (assoc 0 ed)))
  (cond
    ((= et "LINE")       (list (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)) ent)))
    ((= et "LWPOLYLINE") (dchk:lwpoly-segs ent))
    ((= et "POLYLINE")   (dchk:heavy-poly-segs ent))))

(defun dchk:collect-segs (ents / segs e s)
  ;; all straight segments of a list of entities, longer than the
  ;; attachment tolerance (zero-length stubs help nothing)
  (foreach e ents
    (if (entget e)
      (foreach s (dchk:ent-segs e)
        (if (> (distance (car s) (cadr s)) *dchk-tol*)
          (setq segs (cons s segs))))))
  (reverse segs))

(defun dchk:group-ents (g / out e s)
  ;; the distinct entities a group's segments belong to
  (foreach s (cdr g)
    (setq e (dchk:seg-ent s))
    (if (not (member e out)) (setq out (cons e out))))
  (reverse out))

(defun dchk:seg-dir-ang (s / a)
  ;; segment direction folded into [0, pi)
  (setq a (angle (dchk:seg-p1 s) (dchk:seg-p2 s)))
  (if (>= a pi) (- a pi) a))

(defun dchk:ang-diff (a b / d)
  ;; distance between two folded directions, in [0, pi/2]
  (setq d (abs (- a b)))
  (min d (- pi d)))

(defun dchk:sort-recs (recs / out r pre rest)
  ;; stable insertion sort by (car rec); keeps equal elements
  (setq out nil)
  (foreach r recs
    (setq pre  nil
          rest out)
    (while (and rest (>= (car r) (caar rest)))
      (setq pre  (cons (car rest) pre)
            rest (cdr rest)))
    (setq out (append (reverse pre) (list r) rest)))
  out)

(defun dchk:step-groups (lns minlines / atol fams a placed recs pts p1 p2 dx dy
                             off s1 s2 tmp cur chains gap groups e fam r)
  ;; hunt for step-like patterns: minlines or more parallel LINEs
  ;; stacked less than *dchk-step-maxgap* apart, each sideways-
  ;; overlapping the one before it (like stair treads).
  ;; Returns a list of groups, each (direction-angle ent ent ...)
  ;; ordered bottom tread to top.
  (setq atol   (* *dchk-step-angtol* (/ pi 180.0))
        fams   nil
        groups nil)
  ;; bucket the segments into parallel families
  (foreach e lns
    (progn
      (setq a      (dchk:seg-dir-ang e)
            placed nil)
      (foreach fam fams
        (if (and (not placed) (<= (dchk:ang-diff a (car fam)) atol))
          (setq fams   (subst (cons (car fam) (cons e (cdr fam))) fam fams)
                placed T)))
      (if (not placed)
        (setq fams (cons (list a e) fams)))))
  ;; inside each family, sort by sideways offset and chain the stack
  (foreach fam fams
    (if (>= (length (cdr fam)) minlines)
      (progn
        (setq a    (car fam)
              dx   (cos a)
              dy   (sin a)
              recs nil)
        (foreach e (cdr fam)
          (setq p1  (dchk:seg-p1 e)
                p2  (dchk:seg-p2 e)
                off (- (* (cadr p1) dx) (* (car p1) dy))
                s1  (+ (* (car p1) dx) (* (cadr p1) dy))
                s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
          (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
          (setq recs (cons (list off s1 s2 e) recs)))
        (setq recs (dchk:sort-recs recs))
        ;; cur = (ents distinct-tread-count span-lo span-hi last-off)
        (setq cur nil chains nil)
        (foreach r recs
          (cond
            ((null cur)
             (setq cur (list (list (cadddr r)) 1 (cadr r) (caddr r) (car r))))
            (t
             (setq gap (- (car r) (nth 4 cur)))
             (cond
               ((<= gap *dchk-tol*)           ; same tread drawn in pieces
                (setq cur (list (cons (cadddr r) (car cur))
                                (cadr cur)
                                (min (nth 2 cur) (cadr r))
                                (max (nth 3 cur) (caddr r))
                                (car r))))
               ;; next tread: plan-view treads overlap sideways, but in
               ;; a side view consecutive risers only touch corner to
               ;; corner (a zigzag), so allow a sideways gap up to one
               ;; tread depth as well
               ((and (<= gap *dchk-step-maxgap*)
                     (<= (- (max (nth 2 cur) (cadr r))
                            (min (nth 3 cur) (caddr r)))
                         *dchk-step-maxgap*))
                (setq cur (list (cons (cadddr r) (car cur))
                                (1+ (cadr cur))
                                (cadr r)
                                (caddr r)
                                (car r))))
               (t                             ; stack broken
                (if (>= (cadr cur) minlines)
                  (setq chains (cons (cons a (reverse (car cur))) chains)))
                (setq cur (list (list (cadddr r)) 1 (cadr r) (caddr r) (car r))))))))
        (if (and cur (>= (cadr cur) minlines))
          (setq chains (cons (cons a (reverse (car cur))) chains)))
        (setq groups (append groups (reverse chains))))))
  groups)

(defun dchk:staircase-p (g / a dx dy recs e pts p1 p2 off s1 s2 tmp
                           merged r prev sign d ov shorter ok)
  ;; T when the group's members march along like a stair or bench
  ;; profile - each tread shifted to the next, touching or barely
  ;; overlapping it - rather than sitting squarely on top of one
  ;; another like the two long sides of a rectangle, or nested like
  ;; plan-view step outlines. This is what separates a real side
  ;; view from any two parallel lines that happen to be close.
  (setq a    (car g)
        dx   (cos a)
        dy   (sin a)
        recs nil)
  (foreach e (cdr g)
    (setq p1  (dchk:seg-p1 e)
          p2  (dchk:seg-p2 e)
          off (- (* (cadr p1) dx) (* (car p1) dy))
          s1  (+ (* (car p1) dx) (* (cadr p1) dy))
          s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
    (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
    (setq recs (cons (list off s1 s2) recs)))
  (setq recs   (dchk:sort-recs recs)
        merged nil)
  (foreach r recs                              ; fuse pieces of one tread
    (if (and merged (<= (abs (- (car r) (caar merged))) *dchk-tol*))
      (setq merged (cons (list (caar merged)
                               (min (cadar merged) (cadr r))
                               (max (caddar merged) (caddr r)))
                         (cdr merged)))
      (setq merged (cons r merged))))
  (setq merged (reverse merged)
        ok     (> (length merged) 1)
        sign   0
        prev   nil)
  (foreach r merged
    (if (and ok prev)
      (progn
        (setq ov      (- (min (caddr prev) (caddr r))
                         (max (cadr prev) (cadr r)))
              shorter (min (- (caddr prev) (cadr prev))
                           (- (caddr r) (cadr r)))
              d       (- (cadr r) (cadr prev)))
        (cond
          ((> ov (* 0.5 shorter)) (setq ok nil))    ; stacked, not stepped
          ((<= (abs d) *dchk-tol*) (setq ok nil))   ; no march along
          ((= sign 0) (setq sign (if (> d 0.0) 1 -1)))
          ((/= sign (if (> d 0.0) 1 -1)) (setq ok nil)))))  ; direction flipped
    (setq prev r))
  ok)

(defun dchk:pts-bbox (segs / xs ys e p)
  ;; ((minx miny) (maxx maxy)) over the endpoints of a list of segments
  (setq xs nil ys nil)
  (foreach e segs
    (foreach p (list (dchk:seg-p1 e) (dchk:seg-p2 e))
      (setq xs (cons (car p) xs)
            ys (cons (cadr p) ys))))
  (if xs
    (list (list (apply 'min xs) (apply 'min ys))
          (list (apply 'max xs) (apply 'max ys)))))

(defun dchk:boxes-touch (b1 b2 m)
  ;; do two ((minx miny)(maxx maxy)) boxes overlap once grown by m?
  (and b1 b2
       (<= (- (caar b2) m) (caadr b1))
       (<= (- (caar b1) m) (caadr b2))
       (<= (- (cadar b2) m) (cadadr b1))
       (<= (- (cadar b1) m) (cadadr b2))))

(defun dchk:bead-near-p (gbb beadbbs / hit bb)
  ;; is any bead-track box within *dchk-bead-dist* of the group box?
  (setq hit nil)
  (foreach bb beadbbs
    (if (dchk:boxes-touch gbb bb *dchk-bead-dist*)
      (setq hit T)))
  hit)

(defun dchk:zoom-box (bb / p1 p2 m)
  ;; zoom the current view onto a ((minx miny)(maxx maxy)) box
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *dchk-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

;; --- block & text helpers ------------------------------------------

(defun dchk:norm-text (s)
  ;; uppercase, with every non-alphanumeric squashed to a space, so
  ;; word searches ignore case, punctuation and MTEXT format codes
  (if (null s)
    ""
    (vl-list->string
      (mapcar '(lambda (c)
                 (cond
                   ((and (>= c 48) (<= c 57)) c)         ; 0-9
                   ((and (>= c 65) (<= c 90)) c)         ; A-Z
                   ((and (>= c 97) (<= c 122)) (- c 32)) ; a-z -> A-Z
                   (t 32)))
               (vl-string->list s)))))

(defun dchk:block-name (ent / res)
  ;; effective block name (sees through dynamic blocks)
  (setq res (vl-catch-all-apply
              'vla-get-EffectiveName
              (list (vlax-ename->vla-object ent))))
  (if (vl-catch-all-error-p res)
    (cdr (assoc 2 (entget ent)))
    res))

(defun dchk:blockdef-texts (bname depth / lst e et g)
  ;; TEXT/MTEXT/ATTDEF inside a block definition, following nested
  ;; blocks down to depth so a title wrapped in a wrapper is found
  (setq e (tblobjname "BLOCK" bname))
  (if e
    (progn
      (setq e (entnext e))
      (while (and e (/= "ENDBLK" (setq et (cdr (assoc 0 (entget e))))))
        (cond
          ((member et '("TEXT" "ATTDEF"))
           (setq lst (cons (cdr (assoc 1 (entget e))) lst)))
          ((= et "MTEXT")
           (foreach g (entget e)
             (if (member (car g) '(1 3))
               (setq lst (cons (cdr g) lst)))))
          ((and (= et "INSERT") (> depth 1))
           (setq lst (cons (cdr (assoc 2 (entget e))) lst)  ; nested block NAME
                 lst (append (dchk:blockdef-texts (cdr (assoc 2 (entget e)))
                                                  (1- depth))
                             lst))))
        (setq e (entnext e)))))
  lst)

(defun dchk:ins-texts (ent / ed lst e)
  ;; every piece of text an INSERT shows: its attribute values plus
  ;; the text inside its block definition, nested blocks included
  (setq ed  (entget ent)
        lst nil)
  (if (= 1 (cdr (assoc 66 ed)))               ; attributes follow
    (progn
      (setq e (entnext ent))
      (while (and e (= "ATTRIB" (cdr (assoc 0 (entget e)))))
        (setq lst (cons (cdr (assoc 1 (entget e))) lst)
              e   (entnext e)))))
  (append lst (dchk:blockdef-texts (cdr (assoc 2 ed)) *dchk-block-depth*)))

(defun dchk:ins-attrib-deep (ent tag / val s)
  ;; the tag's value on the INSERT, or on a block nested inside it
  (setq val (dchk:ins-attrib ent tag))
  (if val
    val
    (foreach s (dchk:blockdef-texts (cdr (assoc 2 (entget ent)))
                                    *dchk-block-depth*)
      (if (and (null val)
               (wcmatch (dchk:squash s) (strcat "*" (dchk:squash tag) "*")))
        (setq val s)))))

(defun dchk:block-has-layer-p (bname layer depth / e et found)
  ;; does the block definition (or a block it nests, down to depth)
  ;; draw anything on the given layer?
  (setq e (tblobjname "BLOCK" bname))
  (if e
    (progn
      (setq e (entnext e))
      (while (and e (not found)
                  (/= "ENDBLK" (setq et (cdr (assoc 0 (entget e))))))
        (if (= (strcase (cdr (assoc 8 (entget e)))) (strcase layer))
          (setq found T))
        (if (and (not found) (= et "INSERT") (> depth 1))
          (if (dchk:block-has-layer-p (cdr (assoc 2 (entget e))) layer (1- depth))
            (setq found T)))
        (setq e (entnext e)))))
  found)

(defun dchk:ins-matches (ent phrase / pat found s)
  ;; T when the INSERT's (effective) name or any text it shows
  ;; contains the phrase, ignoring case and punctuation
  (setq pat   (strcat "*" (dchk:norm-text phrase) "*")
        found (wcmatch (dchk:norm-text (dchk:block-name ent)) pat))
  (foreach s (dchk:ins-texts ent)
    (if (wcmatch (dchk:norm-text s) pat)
      (setq found T)))
  found)

(defun dchk:ins-has-word (ent word / found s)
  ;; T when the INSERT's (effective) name or any text it shows
  ;; contains the given standalone word — "NOT" hits "Not Selected"
  ;; but never "NOTE"; "STEP" hits "with Step" but never "Stepstone"
  (setq word  (strcase word)
        found nil)
  (foreach s (cons (dchk:block-name ent) (dchk:ins-texts ent))
    (if (and s
             (wcmatch (strcat " " (dchk:norm-text s) " ")
                      (strcat "* " word " *")))
      (setq found T)))
  found)

(defun dchk:phrase-p (s / sq)
  ;; T when the text carries one of *dchk-fgstep-words*, with case,
  ;; spaces and punctuation ignored - so "FiberglassStep" (a layer
  ;; name) matches "Fiberglass Step" just as well
  (setq sq (dchk:squash s))
  (vl-some '(lambda (w) (wcmatch sq (strcat "*" (dchk:squash w) "*")))
           *dchk-fgstep-words*))

(defun dchk:clip (s n)
  (if (> (strlen s) n) (strcat (substr s 1 n) "...") s))

(defun dchk:fgstep-src (ss blks / found i e ed et g b s)
  ;; what makes a fiberglass step show up in the highlighted area:
  ;; a description of the first match ("block '8' Straight FG Step'",
  ;; "layer 'FiberglassStep'", "text 'FG Step'"), nil when there is
  ;; none. Blocks are matched on their name, their attributes and the
  ;; text inside their definition.
  (setq found nil
        i     0)
  (repeat (sslength ss)
    (setq e (ssname ss i)
          i (1+ i))
    (if (and (not found) (setq ed (entget e)))
      (progn
        (setq et (cdr (assoc 0 ed))
              s  (cdr (assoc 8 ed)))
        (if (dchk:phrase-p s)                    ; the layer it sits on
          (setq found (strcat "layer '" (dchk:clip s 40) "'")))
        (if (and (not found) (member et '("TEXT" "MTEXT")))
          (foreach g ed
            (if (and (not found)
                     (member (car g) '(1 3))
                     (dchk:phrase-p (cdr g)))
              (setq found (strcat "text '" (dchk:clip (cdr g) 40) "'"))))))))
  (foreach b blks                                ; block names & their text
    (if (not found)
      (progn
        (setq s (dchk:block-name b))
        (if (dchk:phrase-p s)
          (setq found (strcat "block '" (dchk:clip s 40) "'")))
        (if (not found)
          (foreach s (dchk:ins-texts b)
            (if (and (not found) (dchk:phrase-p s))
              (setq found (strcat "block text '" (dchk:clip s 40) "'"))))))))
  found)

(defun dchk:join (lst sep / out s)
  ;; "A" + "B" + ... joined with sep
  (foreach s lst
    (setq out (if out (strcat out sep s) s)))
  out)

(defun dchk:squash (s)
  ;; norm-text with the spaces removed too, so "Tech Title" finds a
  ;; block that is actually named "TechTitle"
  (vl-list->string (vl-remove 32 (vl-string->list (dchk:norm-text s)))))

(defun dchk:ins-attrib (ent tag / e ed val)
  ;; value of the attribute with the given tag on an INSERT; nil
  ;; when the block has no such attribute
  (setq tag (strcase tag))
  (if (= 1 (cdr (assoc 66 (entget ent))))
    (progn
      (setq e (entnext ent))
      (while (and e (null val) (= "ATTRIB" (cdr (assoc 0 (entget e)))))
        (setq ed (entget e))
        (if (= tag (strcase (cdr (assoc 2 ed))))
          (setq val (cdr (assoc 1 ed))))
        (setq e (entnext e)))))
  val)

(defun dchk:parse-num (s / p num den)
  ;; "4", "4.5", "1/2" -> real
  (setq p (vl-string-search "/" s))
  (if p
    (progn
      (setq num (atof (substr s 1 p))
            den (atof (substr s (+ p 2))))
      (if (> den 0.0) (/ num den) 0.0))
    (atof s)))

(defun dchk:after-eq (s / p)
  ;; the part after the last "=", so a label never contributes its
  ;; own digits: "Finished Wall Ht = 40''" -> " 40''"
  (while (setq p (vl-string-search "=" s))
    (setq s (substr s (+ p 2))))
  s)

(defun dchk:len-values (s / lst i n c numstr toks unit vals cur tok)
  ;; every length written in the text, as a list of numbers in inches
  ;; (drawing units). ' = feet, '' or " = inches, a bare number counts
  ;; as inches. Feet and bare numbers carry on into the same value, an
  ;; inch mark closes it, so a compound height stays ONE value while a
  ;; list stays several:
  ;;   "40''"          -> (40.0)
  ;;   "3'-4''"        -> (40.0)
  ;;   "3' 4 1/2\""    -> (40.5)
  ;;   "0'', 40'', 45''" -> (0.0 40.0 45.0)
  ;; A label before the last "=" is ignored, so the attribute may read
  ;; "Finished Wall Ht = 40''" and still measure 40.
  (setq s    (dchk:after-eq s)
        lst  (vl-string->list s)
        i    0
        n    (length lst)
        toks nil)
  (while (< i n)
    (setq c (nth i lst))
    (if (or (and (>= c 48) (<= c 57)) (= c 46) (= c 47))  ; digit . /
      (progn
        (setq numstr "")
        (while (and (< i n)
                    (setq c (nth i lst))
                    (or (and (>= c 48) (<= c 57)) (= c 46) (= c 47)))
          (setq numstr (strcat numstr (chr c))
                i      (1+ i)))
        (setq unit nil)
        (cond
          ((and (< i n) (= (nth i lst) 34))               ; "
           (setq unit 'in
                 i    (1+ i)))
          ((and (< i n) (= (nth i lst) 39))               ; '
           (if (and (< (1+ i) n) (= (nth (1+ i) lst) 39))
             (setq unit 'in                               ; ''
                   i    (+ i 2))
             (setq unit 'ft
                   i    (1+ i)))))
        (setq toks (append toks (list (cons (dchk:parse-num numstr) unit)))))
      (setq i (1+ i))))
  (setq vals nil
        cur  nil)
  (foreach tok toks
    (setq cur (+ (if cur cur 0.0)
                 (if (eq (cdr tok) 'ft) (* 12.0 (car tok)) (car tok))))
    (if (eq (cdr tok) 'in)                     ; inches close the value
      (setq vals (append vals (list cur))
            cur  nil)))
  (if cur (setq vals (append vals (list cur))))
  vals)

(defun dchk:parse-len (s)
  ;; the first length written in the text, in inches; nil when none
  (car (dchk:len-values s)))

(defun dchk:varies-p (s)
  ;; T when the height reads "Varies" instead of carrying a number
  (wcmatch (strcat " " (dchk:norm-text (dchk:after-eq s)) " ")
           "* VARIES *"))

;; --- dimension review ----------------------------------------------

(defun dchk:dim-style (ent / s)
  ;; the dimension's style name, "" when it has none
  (setq s (cdr (assoc 3 (entget ent))))
  (if s s ""))

(defun dchk:style-rank (style / i r s)
  ;; position of the style in *dchk-style-order* (exact name match,
  ;; case-blind); unlisted styles land after every listed one
  (setq style (strcase style)
        i     0
        r     nil)
  (foreach s *dchk-style-order*
    (if (and (null r) (= (strcase s) style)) (setq r i))
    (setq i (1+ i)))
  (if r r (length *dchk-style-order*)))

(defun dchk:ent-center (ent / bb)
  ;; (x y) centre of the entity's box; falls back to its group-10 point
  (setq bb (dchk:bbox ent))
  (if bb
    (list (* 0.5 (+ (caar bb) (caadr bb)))
          (* 0.5 (+ (cadar bb) (cadadr bb))))
    (progn
      (setq bb (cdr (assoc 10 (entget ent))))
      (if bb (list (car bb) (cadr bb)) (list 0.0 0.0)))))

(defun dchk:dim-order-p (r1 r2 rowtol)
  ;; strict "r1 reviews before r2" for recs (rank cx cy ent):
  ;; style rank first, then row (higher = earlier), then left first
  (cond
    ((< (car r1) (car r2)) T)
    ((> (car r1) (car r2)) nil)
    ((> (- (caddr r1) (caddr r2)) rowtol) T)   ; r1 sits a row above
    ((> (- (caddr r2) (caddr r1)) rowtol) nil) ; r2 sits a row above
    (t (< (cadr r1) (cadr r2)))))              ; same row: left first

(defun dchk:sort-dims (dims rowtol / recs cen r out pre rest e)
  ;; stable insertion sort into review order
  (setq recs nil)
  (foreach e dims
    (setq cen  (dchk:ent-center e)
          recs (cons (list (dchk:style-rank (dchk:dim-style e))
                           (car cen) (cadr cen) e)
                     recs)))
  (setq recs (reverse recs)
        out  nil)
  (foreach r recs
    (setq pre  nil
          rest out)
    (while (and rest (not (dchk:dim-order-p r (car rest) rowtol)))
      (setq pre  (cons (car rest) pre)
            rest (cdr rest)))
    (setq out (append (reverse pre) (list r) rest)))
  (mapcar '(lambda (r) (nth 3 r)) out))

(defun dchk:dim-meas (ent / ed dtype p13 p14 ang v meas)
  ;; the dimension's current measurement as display text, formatted
  ;; with the drawing's unit settings (LUNITS/AUNITS); nil if unknown.
  ;; Linear/aligned dims are recomputed from their definition points
  ;; so the value reflects any point that was just moved.
  (setq ed    (entget ent)
        dtype (logand 7 (cdr (assoc 70 ed)))
        meas  (cdr (assoc 42 ed)))            ; stored actual measurement
  (cond
    ((= dtype 1)                              ; aligned: point-to-point
     (setq p13 (cdr (assoc 13 ed))
           p14 (cdr (assoc 14 ed)))
     (if (and p13 p14) (rtos (distance p13 p14))))
    ((= dtype 0)                              ; rotated/linear: project the
     (setq p13 (cdr (assoc 13 ed))            ; points onto the dim direction
           p14 (cdr (assoc 14 ed))
           ang (cdr (assoc 50 ed)))
     (if (and p13 p14)
       (progn
         (if (null ang) (setq ang 0.0))
         (setq v (mapcar '- p14 p13))
         (rtos (abs (+ (* (car v) (cos ang))
                       (* (cadr v) (sin ang))))))))
    ((member dtype '(2 5))                    ; angular: show the angle
     (if (and meas (>= meas 0.0)) (angtos meas)))
    (t                                        ; radius/diameter/ordinate
     (if (and meas (>= meas 0.0)) (rtos meas)))))

(defun dchk:dim-num (ent / ed dtype p13 p14 ang v)
  ;; the dimension's linear measurement as a NUMBER, recomputed from
  ;; its definition points; falls back to the stored measurement
  (setq ed    (entget ent)
        dtype (logand 7 (cdr (assoc 70 ed)))
        p13   (cdr (assoc 13 ed))
        p14   (cdr (assoc 14 ed)))
  (cond
    ((and (= dtype 1) p13 p14) (distance p13 p14))
    ((and (= dtype 0) p13 p14)
     (setq ang (cdr (assoc 50 ed)))
     (if (null ang) (setq ang 0.0))
     (setq v (mapcar '- p14 p13))
     (abs (+ (* (car v) (cos ang)) (* (cadr v) (sin ang)))))
    (t (cdr (assoc 42 ed)))))

(defun dchk:dim-stated (ent / txt v)
  ;; the value the dimension actually STATES: its text override when
  ;; it carries a readable one, else what it measures
  (setq txt (cdr (assoc 1 (entget ent))))
  (if (and txt
           (/= txt "")
           (not (vl-string-search "<>" txt))    ; "<>" = show the measurement
           (setq v (dchk:parse-len txt)))
    v
    (dchk:dim-num ent)))

(defun dchk:pt-in-box (p bb m)
  ;; is point p inside the ((minx miny)(maxx maxy)) box grown by m?
  (and bb p
       (>= (car p)  (- (caar bb) m))
       (<= (car p)  (+ (caadr bb) m))
       (>= (cadr p) (- (cadar bb) m))
       (<= (cadr p) (+ (cadadr bb) m))))

(defun dchk:height-dim (dims bb rise / best bestdy ed p13 p14 dy e)
  ;; the side view's OVERALL-HEIGHT dimension: both definition points
  ;; sit in the side view and span its full rise. The widest such
  ;; dimension wins, so a single riser's dim is never mistaken for it.
  (foreach e dims
    (if (entget e)
      (progn
        (setq ed  (entget e)
              p13 (cdr (assoc 13 ed))
              p14 (cdr (assoc 14 ed)))
        (if (and p13 p14
                 (dchk:pt-in-box p13 bb *dchk-height-tol*)
                 (dchk:pt-in-box p14 bb *dchk-height-tol*))
          (progn
            (setq dy (abs (- (cadr p14) (cadr p13))))
            (if (and (>= dy (- rise *dchk-height-tol*))
                     (or (null bestdy) (> dy bestdy)))
              (setq bestdy dy
                    best   e)))))))
  best)

(defun dchk:audit-dim-point (ent gcode label cands / ed pt near final newp)
  ;; audits one definition point: off-object points are moved onto the
  ;; closest object, then the user confirms (Enter) or re-picks (N).
  ;; Returns (original final how) when the point moved, nil otherwise.
  (setq ed (entget ent)
        pt (cdr (assoc gcode ed)))
  (if pt
    (progn
      (setq near (dchk:nearest-curve pt nil cands))
      (if (and near (> (caddr near) *dchk-tol*))
        (progn
          (setq final (cadr near))
          (entmod (subst (cons gcode final) (assoc gcode ed) ed))
          (entupd ent)
          (princ (strcat "\n  " label " was not on any object; moved "
                         (rtos (caddr near) 2 4) " onto the nearest one."))
          (setq newp (dchk:confirm-point label final))
          (if newp
            (progn
              (setq final (trans newp 1 0)
                    ed    (entget ent))
              (entmod (subst (cons gcode final) (assoc gcode ed) ed))
              (entupd ent)
              (princ (strcat "\n  " label " moved to your point "
                             (dchk:ptstr final) "."))))
          (redraw)
          (list pt final (if newp 'user 'auto)))))))

(defun dchk:review-dim (ent cands num total / ed dtype h sty p13 p14 r1 r2 moved ok note meas assocnote)
  ;; interactive review of one dimension.
  ;; Returns (handle ok-flag report-note moved-point-count measurement).
  (setq ed    (entget ent)
        h     (cdr (assoc 5 ed))
        sty   (dchk:dim-style ent)
        dtype (logand 7 (cdr (assoc 70 ed))))
  (dchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nDimension " (itoa num) " of " (itoa total)
                 " (handle " h
                 (if (= sty "") "" (strcat ", style " sty))
                 ")"))
  (if (member dtype '(0 1))                   ; rotated/linear or aligned
    (progn
      (if (dchk:dim-assoc-p ent)
        (princ "\n  Note: this dimension is object-associative - a moved point may re-anchor on its own."))
      (setq p13 (cdr (assoc 13 ed))           ; the two dimmed points
            p14 (cdr (assoc 14 ed))
            r1  (dchk:audit-dim-point ent 13 "dimension point 1" cands)
            r2  (dchk:audit-dim-point ent 14 "dimension point 2" cands))
      (if (or r1 r2)
        (dchk:make-xline p13 p14))))          ; through the ORIGINAL points
  (setq moved (append (if r1 (list r1)) (if r2 (list r2))))
  (if (and moved (dchk:dim-assoc-p ent))
    (setq assocnote " (ASSOCIATIVE - verify the moved point holds)"))
  (setq meas (dchk:dim-meas ent))             ; after any point moves
  (if meas (princ (strcat "\n  Measures " meas ".")))
  (redraw ent 3)
  (setq ok (dchk:ask-yn-nav "\n  Is this dimension correct?"))
  (redraw ent 4)
  (redraw)
  (if (member ok '(back skip))
    (list h ok nil (length moved) meas)       ; navigation: caller handles it
    (progn
      (setq ok (eq ok 'yes))
      (setq note (strcat
                   (cond
                     ((and ok moved)
                      (strcat "OK (" (itoa (length moved)) " point(s) adjusted)"))
                     (ok "OK")
                     (moved
                      (strcat "FLAGGED to fix (red, " (itoa (length moved))
                              " point(s) adjusted)"))
                     (t "FLAGGED to fix (red)"))
                   (if assocnote assocnote "")))
      (if (not ok) (dchk:set-color ent *dchk-flag-color*))
      (list h ok note (length moved) meas))))

;; --- arc review ----------------------------------------------------

(defun dchk:arc-end-target (ent which cands / p other near ends target)
  ;; where the attachment audit says this endpoint should go;
  ;; nil when the endpoint is already fine (or nothing to attach to)
  (setq p     (if (eq which 'start)
                (vlax-curve-getStartPoint ent)
                (vlax-curve-getEndPoint ent))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent))
        near  (dchk:nearest-curve p ent cands))
  (cond
    ((null near) nil)                         ; nothing to attach to at all
    ((<= (caddr near) *dchk-tol*)             ; endpoint sits on an object...
     (setq ends (dchk:curve-ends (car near)))
     ;; never snap onto the arc's own other endpoint
     (setq ends (vl-remove-if '(lambda (q) (< (distance q other) 1e-8)) ends))
     (cond
       ((null ends) nil)                      ; closed curve: no ends to demand
       ((vl-some '(lambda (q) (<= (distance p q) *dchk-tol*)) ends)
        nil)                                  ; ...and at one of its ends: OK
       (t (dchk:closest-of p ends))))         ; ...but mid-object: closest end
    (t                                        ; floating: closest end anywhere,
     (setq target (dchk:nearest-end p ent cands))
     (if (or (null target) (< (distance target other) 1e-8))
       (cadr near)                            ; else closest point on closest object
       target))))

(defun dchk:review-arc-end (ent which label cands / p target newp final)
  ;; audits one arc endpoint, snaps it when detached, then lets the
  ;; user confirm (Enter) or re-pick (N) the moved point.
  ;; Returns (original final how) when the endpoint moved, nil otherwise.
  (setq p      (if (eq which 'start)
                 (vlax-curve-getStartPoint ent)
                 (vlax-curve-getEndPoint ent))
        target (dchk:arc-end-target ent which cands))
  (cond
    (target
     (if (dchk:move-arc-end ent which target)
       (progn
         (princ (strcat "\n  " label " was not attached to an object end; snapped "
                        (rtos (distance p target) 2 4) "."))
         (setq final target
               newp  (dchk:confirm-point label target))
         (if newp
           (progn
             (setq newp (trans newp 1 0))
             (if (dchk:move-arc-end ent which newp)
               (progn
                 (setq final newp)
                 (princ (strcat "\n  " label " moved to your point "
                                (dchk:ptstr final) ".")))
               (princ "\n  Could not re-fit the arc through that point (collinear?); kept the snapped position."))))
         (redraw)
         (list p final (if newp 'user 'auto)))
       (progn
         (princ (strcat "\n  " label " should attach at " (dchk:ptstr target)
                        " but the arc could not be re-fitted (points collinear?)."))
         nil)))
    (*dchk-ask-all-arc-ends*                  ; optional: confirm attached ends too
     (setq newp (dchk:confirm-point label p))
     (redraw)
     (if newp
       (progn
         (setq newp (trans newp 1 0))
         (if (dchk:move-arc-end ent which newp)
           (list p newp 'user)
           (progn
             (princ "\n  Could not re-fit the arc through that point (collinear?); unchanged.")
             nil)))))
    (t nil)))

(defun dchk:review-arc (ent cands num total / ed h planar r1 r2 moved note)
  ;; interactive review of one arc's endpoints.
  ;; Returns (handle untouched-flag report-note moved-point-count).
  (setq ed     (entget ent)
        h      (cdr (assoc 5 ed))
        planar (dchk:planar-arc-p ed))
  (dchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nArc " (itoa num) " of " (itoa total)
                 " (handle " h ")"))
  (if planar
    (setq r1 (dchk:review-arc-end ent 'start "arc start point" cands)
          r2 (dchk:review-arc-end ent 'end   "arc end point"   cands))
    (princ "\n  Arc is not in the world XY plane - endpoint audit skipped."))
  (redraw ent 4)
  (redraw)
  (setq moved (append (if r1 (list r1)) (if r2 (list r2))))
  (if moved (dchk:set-color ent *dchk-arc-color*))
  (setq note (cond
               ((not planar) "not in world XY plane - skipped")
               (moved (strcat (itoa (length moved))
                              " endpoint(s) moved (magenta)"))
               (t "endpoints OK")))
  (list h (null moved) note (length moved)))

;; --- overlapping line review ---------------------------------------

(defun dchk:review-olap (la lb num total / info ea eb h1 h2 lay1 lay2 label
                                           ans mergeable kinds)
  ;; interactive review of one overlapping segment pair.
  ;; Returns nil when the pair no longer overlaps (an earlier merge
  ;; absorbed it); otherwise (label report-note action ents...) where
  ;; action is merged / flagged / left and ents keep their cyan.
  (setq ea (dchk:seg-ent la)
        eb (dchk:seg-ent lb))
  (if (and (entget ea) (entget eb) (setq info (dchk:overlap-info la lb)))
    (progn
      (setq h1        (cdr (assoc 5 (entget ea)))
            h2        (cdr (assoc 5 (entget eb)))
            lay1      (cdr (assoc 8 (entget ea)))
            lay2      (cdr (assoc 8 (entget eb)))
            mergeable (and (dchk:whole-line-p la)
                           (dchk:whole-line-p lb)
                           (= (strcase lay1) (strcase lay2)))
            kinds     (if (and (dchk:whole-line-p la) (dchk:whole-line-p lb))
                        "lines"
                        "segments")
            label     (strcat h1 "+" h2 " (overlap " (rtos (caddr info)) ")"))
      (dchk:zoom-2ents ea eb)
      (redraw ea 3)
      (redraw eb 3)
      (dchk:mark-point (car info))
      (dchk:mark-point (cadr info))
      (princ (strcat "\n\nOverlap " (itoa num) " of " (itoa total)
                     ": " kinds " " h1 " + " h2
                     " run on top of each other for " (rtos (caddr info)) "."))
      (if mergeable
        (progn
          (initget "Merge Flag Leave")
          (setq ans (getkword
                      "\n  Merge into one line, Flag to fix, or Leave as is? [Merge/Flag/Leave] <Merge>: "))
          (if (null ans) (setq ans "Merge")))
        (progn
          (princ (if (= (strcase lay1) (strcase lay2))
                   "\n  (Polyline edge - cannot be merged automatically.)"
                   (strcat "\n  (Different layers: " lay1 " / " lay2
                           " - cannot be merged automatically.)")))
          (initget "Flag Leave")
          (setq ans (getkword
                      "\n  Flag to fix, or Leave as is? [Flag/Leave] <Flag>: "))
          (if (null ans) (setq ans "Flag"))))
      (redraw ea 4)
      (redraw eb 4)
      (redraw)
      (cond
        ((= ans "Merge")
         (dchk:merge-lines la lb info)
         (dchk:set-color ea *dchk-olap-color*)
         (princ "\n  Merged into one line (cyan).")
         (list label "merged into one line (cyan)" 'merged ea))
        ((= ans "Flag")
         (dchk:set-color ea *dchk-olap-color*)
         (dchk:set-color eb *dchk-olap-color*)
         (princ "\n  Flagged to fix (cyan).")
         (list label
               (if (dchk:whole-line-p la)
                 (if (= (strcase lay1) (strcase lay2))
                   "flagged to fix (cyan)"
                   "different layers - flagged to fix (cyan)")
                 "polyline edge - flagged to fix (cyan)")
               'flagged ea eb))
        (t
         (princ "\n  Left as drawn.")
         (list label "left as drawn" 'left))))))

;; --- command -------------------------------------------------------

(defun c:DIMCHECK ( / *error* oldecho vc vs undo-open ss i e et
                      cands dims arcs lns plns segs blks olaps rest e1 e2 pr
                      saved keep res n total lines ans
                      ndok ndflag ndmoved naok namoved nasnap
                      nomerged noflag noleft
                      sgroups scand svgroups pgroups g1 g2 stepsp svmode
                      satts attwrong liners linerbadw linernostep bad w bn bh bp
                      linerstep linerfg fgstep
                      bgroups beadneed beadok beadmiss beadss beadbbs gbb
                      stepsum linersum rowtol sty g b l pair hdr
                      htsum stepht wallht wallraw tins tpat tss
                      svbb hdim dimht htval htbad
                      wallvals wallvar wallmany htskip
                      laylist locked relock lay tlist tbest cx cy tvals s d
                      dlines skiprest
                      minx miny maxx maxy bb h m ins txt nlin ref)

  (defun *error* (msg)
    ;; put the greys back (flagged/moved items keep their colour),
    ;; re-lock what we unlocked, clear markers, close the undo group
    (foreach pair saved
      (if (and (not (member (car pair) keep)) (entget (car pair)))
        (dchk:set-color (car pair) (cdr pair))))
    (foreach l relock (dchk:set-layer-lock l T))
    (redraw)
    (if undo-open
      (progn (setvar "CMDECHO" 0) (command "_.UNDO" "_End")))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nDIMCHECK error: " msg)))
    (princ))

  (prompt "\nHighlight the drawing to DIMCHECK: ")
  (setq ss (ssget))
  (cond
    ((null ss)
     (prompt "\nNothing selected - DIMCHECK cancelled."))
    (t
     (setq cands nil dims nil arcs nil lns nil blks nil segs nil
           saved nil keep nil lines nil i 0
           ndok 0 ndflag 0 ndmoved 0 naok 0 namoved 0 nasnap 0
           nomerged 0 noflag 0 noleft 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (= et "LINE") (setq lns (cons e lns)))
       (if (member et '("LINE" "LWPOLYLINE" "POLYLINE"))
         (setq plns (cons e plns)))
       (if (= et "INSERT") (setq blks (cons e blks)))
       (if (member et *dchk-curve-types*) (setq cands (cons e cands))))
     (setq dims  (reverse dims)
           arcs  (reverse arcs)
           lns   (reverse lns)
           plns  (reverse plns)
           blks  (reverse blks)
           cands (reverse cands)
           ;; detection runs on segments, so a run of steps or a side
           ;; view drawn as one polyline counts like separate lines
           segs  (dchk:collect-segs plns))
     (cond
       ((and (null dims) (null arcs) (< (length segs) 2) (null blks))
        (prompt "\nSelection holds no dimensions, arcs, lines, or blocks to check - nothing to do."))
       (t
        (setq oldecho (getvar "CMDECHO"))
        (setvar "CMDECHO" 0)
        (setq vc (getvar "VIEWCTR")
              vs (getvar "VIEWSIZE"))
        (command "_.UNDO" "_Begin")
        (setq undo-open T)
        (dchk:ensure-layer *dchk-constr-layer* *dchk-constr-color*)
        (dchk:ensure-layer *dchk-report-layer* *dchk-report-color*)

        ;; a locked layer swallows every fix and recolour silently -
        ;; surface that up front and offer to unlock for the run
        (setq laylist nil relock nil i 0)
        (repeat (sslength ss)
          (setq lay (cdr (assoc 8 (entget (ssname ss i))))
                i   (1+ i))
          (if (and lay (not (member lay laylist)))
            (setq laylist (cons lay laylist))))
        (setq locked (vl-remove-if-not 'dchk:layer-locked-p laylist))
        (if locked
          (if (dchk:ask-yn
                (strcat "\n" (itoa (length locked))
                        " locked layer(s) in the selection ("
                        (dchk:join locked ", ")
                        ") - DIMCHECK cannot recolour or fix anything on them. Unlock for this run?"))
            (progn
              (foreach l locked (dchk:set-layer-lock l nil))
              (setq relock locked)
              (princ "\n  Unlocked; they will be re-locked when the run ends."))
            (princ "\n  Locked layers stay locked - items on them are reported but left untouched.")))

        ;; a rerun replaces the previous run's report and markers
        (dchk:clear-old)

        ;; extents of the selection (report goes to the right of them)
        (setq i 0)
        (repeat (sslength ss)
          (setq e  (ssname ss i)
                i  (1+ i)
                bb (dchk:bbox e))
          (if bb
            (setq minx (if minx (min minx (caar bb)) (caar bb))
                  miny (if miny (min miny (cadar bb)) (cadar bb))
                  maxx (if maxx (max maxx (caadr bb)) (caadr bb))
                  maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))

        ;; march order for the dimensions: style groups first
        ;; (*dchk-style-order*), then row by row, left to right
        (setq rowtol (if (and miny maxy (> (- maxy miny) 1e-8))
                       (* 0.05 (- maxy miny))
                       1.0))
        (setq dims (dchk:sort-dims dims rowtol))

        ;; grey out the whole selection so each item can take the
        ;; stage, stashing every original colour in xdata first so
        ;; DIMCHECKRESCUE can recover them even after a crash
        (setq i 0)
        (repeat (sslength ss)
          (setq e (ssname ss i)
                i (1+ i))
          (if (entget e)
            (progn
              (setq saved (cons (cons e (dchk:ent-color e)) saved))
              (dchk:stash-color e (dchk:ent-color e))
              (dchk:set-color e *dchk-grey-color*))))

        ;; --- dimensions, one at a time -----------------------------
        (if dims
          (princ (strcat "\n--- Reviewing " (itoa (length dims))
                         " dimension(s): Enter = correct, N = flag to fix, "
                         "B = back one, S = skip the rest ---")))
        ;; index-based so Back can step to the previous dimension and
        ;; Skip can leave the rest unreviewed without losing the report
        (setq n 0 total (length dims) dlines nil skiprest nil)
        (while (and (< n total) (not skiprest))
          (setq e   (nth n dims)
                res nil)
          (dchk:set-color e (cdr (assoc e saved)))       ; step into the light
          (setq res (dchk:review-dim e cands (1+ n) total))
          ;; points already moved count however the prompt was answered
          (setq ndmoved (+ ndmoved (cadddr res)))
          (cond
            ((eq (cadr res) 'skip)
             (dchk:set-color e *dchk-grey-color*)
             (setq skiprest T)
             (princ (strcat "\n  Skipping the remaining "
                            (itoa (- total n)) " dimension(s).")))
            ((eq (cadr res) 'back)
             ;; undo what the previous item recorded, then redo it
             (dchk:set-color e *dchk-grey-color*)
             (if (> n 0)
               (progn
                 (setq n  (1- n)
                       e1 (nth n dims))
                 (if (car dlines)                        ; roll back its tally
                   (progn
                     (if (cadr (car dlines))
                       (setq ndok (1- ndok))
                       (setq ndflag (1- ndflag)))
                     (setq ndmoved (- ndmoved (caddr (car dlines)))
                           dlines  (cdr dlines))))
                 (setq keep (vl-remove e1 keep))
                 (dchk:set-color e1 *dchk-grey-color*)
                 (princ "\n  Stepping back one dimension."))
               (princ "\n  Already at the first dimension."))
             (setq n (1- n)))                            ; loop's 1+ re-enters it
            (t
             (if (cadr res)
               (progn (setq ndok (1+ ndok))
                      (dchk:set-color e *dchk-grey-color*))
               (progn (setq ndflag (1+ ndflag))
                      (setq keep (cons e keep))))
             (setq sty (dchk:dim-style e))
             (setq dlines (cons (list (strcat "Dim " (car res)
                                              (if (= sty "") "" (strcat " [" sty "]"))
                                              (if (nth 4 res)
                                                (strcat " = " (nth 4 res))
                                                "")
                                              ": " (caddr res))
                                      (cadr res)
                                      (cadddr res))
                                dlines))))
          (setq n (1+ n)))
        (if skiprest
          (setq lines (cons (strcat "Dimensions: " (itoa (- total (length dlines)))
                                    " left UNREVIEWED (skipped by user)")
                            lines)))
        (foreach pair (reverse dlines)
          (setq lines (cons (car pair) lines)))

        ;; --- arcs, one endpoint at a time --------------------------
        (if arcs
          (princ (strcat "\n--- Reviewing " (itoa (length arcs))
                         " arc(s): checking endpoint attachment ---")))
        (setq n 0 total (length arcs))
        (foreach e arcs
          (setq n (1+ n))
          (dchk:set-color e (cdr (assoc e saved)))
          (setq res (dchk:review-arc e cands n total))
          (setq nasnap (+ nasnap (cadddr res)))
          (if (cadr res)
            (progn (setq naok (1+ naok))
                   (dchk:set-color e *dchk-grey-color*))
            (progn (setq namoved (1+ namoved))
                   (setq keep (cons e keep))))           ; moved: stays magenta
          (setq lines (cons (strcat "Arc " (car res) ": " (caddr res)) lines)))

        ;; --- overlapping lines, one pair at a time ------------------
        (setq olaps (dchk:find-overlaps segs))
        (if olaps
          (princ (strcat "\n--- Reviewing " (itoa (length olaps))
                         " overlapping line pair(s): Enter = merge, F = flag, L = leave ---")))
        (setq n 0 total (length olaps))
        (foreach pr olaps
          (setq n  (1+ n)
                e1 (dchk:seg-ent (car pr))
                e2 (dchk:seg-ent (cadr pr)))
          (dchk:stage e1 saved keep)
          (dchk:stage e2 saved keep)
          (setq res (dchk:review-olap (car pr) (cadr pr) n total))
          (cond
            ((null res)                       ; absorbed by an earlier merge
             (dchk:unstage e1 keep)
             (dchk:unstage e2 keep))
            ((eq (caddr res) 'left)
             (setq noleft (1+ noleft))
             (dchk:unstage e1 keep)
             (dchk:unstage e2 keep)
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))
            (t
             (if (eq (caddr res) 'merged)
               (setq nomerged (1+ nomerged))
               (setq noflag (1+ noflag)))
             (setq keep (append (cdddr res) keep))
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))))

        ;; --- step / staircase check ---------------------------------
        ;; hunt down to the bench minimum so a two-tread bench profile
        ;; is still found; the staircase test below keeps the extra
        ;; short groups from being mistaken for side views
        (setq sgroups  (dchk:step-groups
                         segs
                         (min *dchk-step-minlines* *dchk-bench-minlines*))
              svgroups nil
              stepsp   nil
              svmode   nil
              satts    nil
              attwrong nil
              bgroups  nil)
        ;; a staircase side view reads as two step patterns at right
        ;; angles to each other (treads + risers) in the same spot
        (setq scand (vl-remove-if-not 'dchk:staircase-p sgroups))
        (setq rest scand)
        (while rest
          (setq g1 (car rest))
          (foreach g2 (cdr rest)
            (if (and (> (dchk:ang-diff (car g1) (car g2)) (- (* 0.5 pi) 0.09))
                     (dchk:boxes-touch (dchk:pts-bbox (cdr g1))
                                       (dchk:pts-bbox (cdr g2))
                                       *dchk-step-maxgap*))
              (progn
                (if (not (member g1 svgroups)) (setq svgroups (cons g1 svgroups)))
                (if (not (member g2 svgroups)) (setq svgroups (cons g2 svgroups))))))
          (setq rest (cdr rest)))
        ;; only full-size patterns are worth asking about; the short
        ;; bench-sized ones matter solely as side-view halves
        (setq pgroups (vl-remove-if
                        '(lambda (g)
                           (or (member g svgroups)
                               (< (length (cdr g)) *dchk-step-minlines*)))
                        sgroups))
        (cond
          (svgroups                           ; staircase drawing found
           (setq stepsp  T
                 svmode  'auto
                 bgroups pgroups)             ; plan-view patterns
           (princ "\n--- Step check: staircase side view detected in the selection ---")
           (setq lines (cons (strcat "Steps: staircase side view detected ("
                                     (itoa (length svgroups)) " step pattern(s))")
                             lines))
           (foreach g pgroups
             (setq lines (cons (strcat "Steps: pattern of " (itoa (length (cdr g)))
                                       " parallel lines (side view already present)")
                               lines))))
          (pgroups                            ; possible steps, no staircase drawing
           (princ (strcat "\n--- Step check: " (itoa (length pgroups))
                          " possible step pattern(s), no staircase side view found ---"))
           (setq n 0 total (length pgroups))
           (foreach g pgroups
             (setq n (1+ n))
             (foreach e (dchk:group-ents g) (dchk:stage e saved keep))
             (dchk:zoom-box (dchk:pts-bbox (cdr g)))
             (foreach e (dchk:group-ents g) (if (entget e) (redraw e 3)))
             (princ (strcat "\n\nStep pattern " (itoa n) " of " (itoa total) ": "
                            (itoa (length (cdr g)))
                            " parallel lines stacked less than "
                            (rtos *dchk-step-maxgap*) " apart."))
             (setq ans (dchk:ask-yn "\n  Are these lines steps?"))
             (foreach e (dchk:group-ents g) (if (entget e) (redraw e 4)))
             (foreach e (dchk:group-ents g) (dchk:unstage e keep))
             (redraw)
             (if ans
               (setq stepsp  T
                     bgroups (cons g bgroups)))
             (setq lines (cons (strcat "Steps: pattern of " (itoa (length (cdr g)))
                                       " parallel lines - "
                                       (if ans "CONFIRMED as steps" "not steps"))
                               lines)))))
        (if stepsp
          (progn
            (if (null svmode)                 ; steps confirmed, no side view seen
              (progn
                (princ "\n  Steps confirmed but no staircase side view was detected.")
                (if (dchk:ask-yn "\n  Is a side view of the steps drawn somewhere?")
                  (setq svmode 'user))))
            (if (null svmode)
              (progn
                (princ "\n  Note: ADD A SIDE VIEW of the steps.")
                (setq lines (cons "Steps: NO SIDE VIEW - add a side view of the steps"
                                  lines)))
              (progn                          ; side view present: demand the block
                (setq satts (vl-remove-if-not
                              '(lambda (b) (dchk:ins-matches b "Step Attachment"))
                              blks))
                (if (null satts)
                  (progn
                    (princ "\n  Note: no 'Step Attachment' block found - add one.")
                    (setq lines (cons "Steps: side view present but NO 'Step Attachment' block - add one"
                                      lines)))
                  (foreach b satts
                    (dchk:stage b saved keep)
                    (dchk:zoom-ent b)
                    (redraw b 3)
                    (setq ans (dchk:ask-yn
                                (strcat "\n  Step Attachment block "
                                        (cdr (assoc 5 (entget b)))
                                        " - is the correct one placed?")))
                    (redraw b 4)
                    (redraw)
                    (if ans
                      (progn
                        (dchk:unstage b keep)
                        (setq lines (cons (strcat "Step Attachment "
                                                  (cdr (assoc 5 (entget b)))
                                                  ": confirmed correct")
                                          lines)))
                      (progn
                        (setq attwrong T)
                        (dchk:set-color b *dchk-flag-color*)
                        (setq keep (cons b keep))
                        (setq lines (cons (strcat "Step Attachment "
                                                  (cdr (assoc 5 (entget b)))
                                                  ": WRONG ONE - flagged to fix (red)")
                                          lines))))))))))

        ;; --- Bead Track check (bead step attachments only) ----------
        ;; when the attachment style is "Bead Step Attachment", each
        ;; plan-view step pattern needs bead track drawn nearby; the
        ;; side view is exempt. The WHOLE drawing is searched, not
        ;; just the selection.
        (setq beadneed nil beadok 0 beadmiss 0)
        (if (and satts
                 bgroups
                 (vl-some '(lambda (b) (dchk:ins-matches b "Bead Step Attachment"))
                          satts))
          (progn
            (setq beadneed T)
            (princ (strcat "\n--- Bead Track check: attachment style is 'Bead Step Attachment' ---"))
            (setq beadss  (ssget "_X" (list (cons 8 *dchk-bead-layer*)))
                  beadbbs nil
                  i       0)
            (if beadss
              (repeat (sslength beadss)
                (setq bb (dchk:bbox (ssname beadss i))
                      i  (1+ i))
                (if bb (setq beadbbs (cons bb beadbbs)))))
            ;; bead track drawn INSIDE a block never lands in that
            ;; layer filter, so take the box of any insert whose
            ;; definition carries the layer
            (setq beadss (ssget "_X" '((0 . "INSERT")))
                  i      0)
            (if beadss
              (repeat (sslength beadss)
                (setq b (ssname beadss i)
                      i (1+ i))
                (if (dchk:block-has-layer-p (cdr (assoc 2 (entget b)))
                                            *dchk-bead-layer* 2)
                  (progn
                    (setq bb (dchk:bbox b))
                    (if bb (setq beadbbs (cons bb beadbbs)))))))
            (foreach g bgroups
              (setq gbb (dchk:pts-bbox (cdr g)))
              (if (and gbb beadbbs (dchk:bead-near-p gbb beadbbs))
                (progn
                  (setq beadok (1+ beadok))
                  (setq lines (cons (strcat "Bead Track: present near step pattern of "
                                            (itoa (length (cdr g))) " lines")
                                    lines)))
                (progn
                  (setq beadmiss (1+ beadmiss))
                  (princ (strcat "\n  Note: nothing on layer '" *dchk-bead-layer*
                                 "' near a step pattern - add bead track."))
                  (setq lines (cons (strcat "Bead Track: NOTHING on layer '"
                                            *dchk-bead-layer*
                                            "' near step pattern of "
                                            (itoa (length (cdr g)))
                                            " lines - add bead track")
                                    lines)))))))

        ;; --- overall height vs Tech Title WallHt --------------------
        ;; the steps' total rise (side view) must match the WallHt
        ;; attribute of the Tech Title block
        (setq htsum nil stepht nil wallht nil wallraw nil tins nil
              svbb nil hdim nil dimht nil htval nil htbad nil
              wallvals nil wallvar nil wallmany nil htskip nil)
        (if stepsp
          (progn
            ;; overall height from the steps
            (cond
              ((eq svmode 'auto)               ; side view found: measure it
               (setq svbb (dchk:pts-bbox (apply 'append (mapcar 'cdr svgroups))))
               (if svbb (setq stepht (- (cadr (cadr svbb)) (cadr (car svbb))))))
              ((eq svmode 'user)               ; user says it exists elsewhere
               (princ "\n  Confirm the overall step height against the Tech Title.")
               (setq stepht (getdist "\n  Type the overall step height or pick two points <skip>: "))))
            ;; every Tech Title block: those in the selection, else
            ;; drawing-wide; the one nearest the checked area wins,
            ;; and titles that disagree on WallHt are called out
            (setq tpat  (strcat "*" (dchk:squash *dchk-title-block*) "*")
                  tlist nil)
            (foreach b blks
              (if (wcmatch (dchk:squash (dchk:block-name b)) tpat)
                (setq tlist (cons b tlist))))
            (if (null tlist)
              (progn
                (setq tss (ssget "_X" '((0 . "INSERT")))
                      i   0)
                (if tss
                  (repeat (sslength tss)
                    (setq b (ssname tss i)
                          i (1+ i))
                    (if (wcmatch (dchk:squash (dchk:block-name b)) tpat)
                      (setq tlist (cons b tlist)))))))
            (setq cx (if minx (* 0.5 (+ minx maxx)) 0.0)
                  cy (if miny (* 0.5 (+ miny maxy)) 0.0)
                  tbest nil)
            (foreach b tlist
              (setq bp (cdr (assoc 10 (entget b)))
                    d  (distance (list cx cy) (list (car bp) (cadr bp))))
              (if (or (null tbest) (< d tbest))
                (setq tbest d
                      tins  b)))
            (if (> (length tlist) 1)
              (progn
                (setq tvals nil)
                (foreach b tlist
                  (setq s (dchk:ins-attrib b *dchk-wallht-tag*))
                  (if s
                    (progn
                      (setq s (dchk:norm-text (dchk:after-eq s)))
                      (if (not (member s tvals))
                        (setq tvals (cons s tvals))))))
                (if (> (length tvals) 1)
                  (progn
                    (princ (strcat "\n  Note: " (itoa (length tlist)) " '"
                                   *dchk-title-block* "' blocks disagree on "
                                   *dchk-wallht-tag* "; using the nearest one."))
                    (setq lines (cons (strcat (itoa (length tlist)) " '"
                                              *dchk-title-block*
                                              "' blocks DISAGREE on "
                                              *dchk-wallht-tag*
                                              " - CHECK THE WALL HEIGHT (nearest one used)")
                                      lines))))))
            (if tins
              (setq wallraw  (dchk:ins-attrib-deep tins *dchk-wallht-tag*)
                    wallvals (if wallraw (dchk:len-values wallraw))
                    wallvar  (and wallraw (dchk:varies-p wallraw))
                    wallmany (> (length wallvals) 1)
                    wallht   (if (and wallvals (not wallmany))
                               (car wallvals))))
            ;; a height that Varies, or a title block holding several
            ;; heights, gives nothing to check the side view against -
            ;; leave it alone rather than marking it red
            (setq htskip (or wallvar wallmany))
            ;; the side view's own overall-height dimension, and the
            ;; height it states - that dimension is what gets compared
            (if (and svbb stepht (not htskip))
              (setq hdim (dchk:height-dim dims svbb stepht)))
            (if hdim (setq dimht (dchk:dim-stated hdim)))
            (setq htval (if dimht dimht stepht))
            (setq htbad (and htval wallht
                             (> (abs (- htval wallht)) *dchk-height-tol*)))
            ;; a dimension that disagrees with the title block is wrong:
            ;; mark it red automatically and keep it red
            (if (and htbad hdim)
              (progn
                (dchk:set-color hdim *dchk-flag-color*)
                (if (not (member hdim keep)) (setq keep (cons hdim keep)))
                (princ (strcat "\n  Side view height dimension "
                               (cdr (assoc 5 (entget hdim)))
                               " disagrees with " *dchk-wallht-tag*
                               " - marked red."))
                (setq lines (cons (strcat "Height dim "
                                          (cdr (assoc 5 (entget hdim)))
                                          " states " (rtos dimht)
                                          " but " *dchk-wallht-tag* " is '"
                                          wallraw "' - MISMATCH, marked red")
                                  lines))))
            ;; a dimension whose text was overridden to disagree with
            ;; the geometry it spans is wrong too
            (if (and hdim dimht stepht
                     (> (abs (- dimht stepht)) *dchk-height-tol*))
              (progn
                (dchk:set-color hdim *dchk-flag-color*)
                (if (not (member hdim keep)) (setq keep (cons hdim keep)))
                (setq lines (cons (strcat "Height dim "
                                          (cdr (assoc 5 (entget hdim)))
                                          " states " (rtos dimht)
                                          " but the side view is drawn "
                                          (rtos stepht)
                                          " tall - MISMATCH, marked red")
                                  lines))))
            (setq htsum
              (cond
                ((null htval)
                 "steps present but their overall height was NOT CONFIRMED (no side view measured)")
                ((null tins)
                 (strcat "steps rise " (rtos htval) " but no '"
                         *dchk-title-block* "' block was found - NOT CONFIRMED"))
                (wallvar
                 (strcat "steps rise " (rtos htval) " and " *dchk-wallht-tag*
                         " reads '" wallraw
                         "' - height varies, side view left alone"))
                (wallmany
                 (strcat "steps rise " (rtos htval) " but " *dchk-wallht-tag*
                         " holds " (itoa (length wallvals)) " heights ('"
                         wallraw "') - CHECK THE WALL HEIGHT in the "
                         *dchk-title-block* ", side view left alone"))
                ((null wallht)
                 (strcat "steps rise " (rtos htval) " but the "
                         *dchk-wallht-tag* " attribute "
                         (if wallraw
                           (strcat "'" wallraw "' is unreadable")
                           "is missing")
                         " - NOT CONFIRMED"))
                ((not htbad)
                 (strcat "steps rise " (rtos htval) " = WallHt '" wallraw
                         "' - MATCHES"))
                (t
                 (strcat "steps rise " (rtos htval) " but WallHt is '" wallraw
                         "' (" (rtos wallht) ") - MISMATCH"
                         (if hdim ", dimension marked red" ", look at it")))))
            (princ (strcat "\n  Overall height: " htsum))))

        ;; --- Liner Material check -----------------------------------
        (setq liners      (vl-remove-if-not
                            '(lambda (b) (dchk:ins-matches b "Liner Material"))
                            blks)
              linerbadw   nil
              linernostep nil
              linerstep   nil
              linerfg     nil
              fgstep      (dchk:fgstep-src ss blks))
        (if fgstep
          (princ (strcat "\n--- Fiberglass Step found in the highlighted area: "
                         fgstep " ---")))
        (if (null liners)
          (progn
            (princ "\n--- Liner check: no 'Liner Material' block in the selection ---")
            (setq lines (cons "Liner Material: NO block found - add 'Liner Material' or 'Liner Material with Step'"
                              lines)))
          (progn
            (princ (strcat "\n--- Liner check: " (itoa (length liners))
                           " 'Liner Material' block(s) found ---"))
            (foreach b liners
              (setq bn  (dchk:block-name b)
                    bh  (cdr (assoc 5 (entget b)))
                    bp  (cdr (assoc 10 (entget b)))
                    bad nil)
              (foreach w '("NOT" "ERROR")
                (if (dchk:ins-has-word b w)
                  (setq bad (append bad (list w)))))
              (foreach w bad
                (if (not (member w linerbadw))
                  (setq linerbadw (append linerbadw (list w)))))
              (if bad
                (progn
                  (princ (strcat "\n  Note: '" bn "' contains the word "
                                 (dchk:join bad " & ") " - look at it."))
                  (setq lines (cons (strcat "Liner Material (" bn ") " bh " at "
                                            (dchk:ptstr bp)
                                            ": contains the word "
                                            (dchk:join bad " & ")
                                            " - look at it")
                                    lines)))
                (setq lines (cons (strcat "Liner Material (" bn ") " bh ": OK")
                                  lines))))
            (setq linerstep (vl-some '(lambda (b) (dchk:ins-has-word b "STEP"))
                                     liners))
            (cond
              ;; a fiberglass step is its own unit - the liner pattern
              ;; must NOT carry a step of its own
              (fgstep
               (if linerstep
                 (progn
                   (setq linerfg T)
                   (princ "\n  Note: a Fiberglass Step is in the drawing but the liner pattern has a Step.")
                   (setq lines (cons (strcat "Liner Material: a Fiberglass Step ("
                                             fgstep
                                             ") is in the drawing but the liner pattern HAS a Step - it should not")
                                     lines)))))
              ;; otherwise steps drawn -> the liner pattern must cover them
              ((and stepsp (not linerstep))
               (setq linernostep T)
               (princ "\n  Note: steps are drawn but the liner pattern is MISSING its Step.")
               (setq lines (cons "Liner Material: steps are drawn but the liner pattern is MISSING its 'Step' - use 'Liner Material with Step'"
                                 lines))))))

        ;; --- restore colours (flagged/moved keep theirs) ------------
        ;; restored entities drop their rescue stash; flagged/moved
        ;; ones keep it so DIMCHECKRESCUE can clear the marks later
        (foreach pair saved
          (if (and (not (member (car pair) keep)) (entget (car pair)))
            (progn
              (dchk:set-color (car pair) (cdr pair))
              (dchk:unstash (car pair)))))
        (foreach l relock (dchk:set-layer-lock l T))
        (setq relock nil)

        ;; --- one-line verdicts for steps & liner --------------------
        (setq stepsum
              (cond
                ((null sgroups) "no step patterns detected")
                ((not stepsp)
                 (strcat (itoa (length sgroups))
                         " pattern(s) reviewed - none are steps"))
                (t
                 (strcat "steps present; side view "
                         (cond ((eq svmode 'auto) "detected")
                               ((eq svmode 'user) "confirmed by user")
                               (t "MISSING - add one"))
                         (cond ((null svmode) "")
                               ((null satts)
                                "; Step Attachment block MISSING - add one")
                               (attwrong
                                "; Step Attachment flagged WRONG (red)")
                               (t "; Step Attachment confirmed"))
                         (cond ((not beadneed) "")
                               ((> beadmiss 0)
                                (strcat "; Bead Track MISSING near "
                                        (itoa beadmiss) " pattern(s)"))
                               (t "; Bead Track present"))))))
        (setq linersum
              (cond
                ((null liners)
                 "block MISSING - add 'Liner Material' (or 'with Step')")
                (t
                 (strcat (itoa (length liners)) " block(s) found"
                         (if linerbadw
                           (strcat "; word " (dchk:join linerbadw " & ")
                                   " found - review")
                           "")
                         (if linernostep
                           "; steps drawn but liner MISSING its Step"
                           "")
                         (if linerfg
                           "; Fiberglass Step in the drawing but the liner HAS a Step"
                           "")
                         (if (and (null linerbadw) (not linernostep) (not linerfg))
                           " - OK"
                           "")))))

        ;; --- report on the right side, to scale with the drawing ----
        ;; text height picked from the drawing's extents so the whole
        ;; report roughly matches the drawing's height (MTEXT line
        ;; spacing is ~1.66 x text height), clamped so a short report
        ;; is not gigantic nor a long one unreadably small
        ;; all-clear lines are shorter, so weight them when sizing
        (setq nlin 3.0)                          ; title, legend, separator
        (foreach l lines
          (setq nlin (+ nlin (if (dchk:attn-p l) 1.0 *dchk-green-scale*))))
        (setq nlin (+ nlin (* 6.0 *dchk-green-scale*)))   ; the header dashboard
        (if (and minx (> (max (- maxy miny) (- maxx minx)) 1e-8))
          (progn
            (setq ref (max (- maxy miny) (* 0.25 (- maxx minx)))
                  h   (/ ref (* 1.66 nlin)))
            (if (> h (/ ref 30.0))  (setq h (/ ref 30.0)))
            (if (< h (/ ref 200.0)) (setq h (/ ref 200.0))))
          (progn
            (setq h (* (getvar "DIMTXT") (getvar "DIMSCALE")))
            (if (or (null h) (<= h 0.0)) (setq h 2.5))))
        (setq ins (if minx
                    (list (+ maxx (* 0.05 (max (- maxx minx) 1.0))) maxy 0.0)
                    (list 0.0 0.0 0.0)))
        ;; header dashboard: each line carries a "needs attention" flag
        ;; so a category with anything to look over turns red
        (setq hdr
          (list
            (cons (strcat "Dimensions checked: " (itoa (length dims))
                          " (correct: " (itoa ndok)
                          ", flagged to fix: " (itoa ndflag)
                          ", points adjusted: " (itoa ndmoved) ")")
                  (> ndflag 0))
            (cons (strcat "Arcs checked: " (itoa (length arcs))
                          " (OK: " (itoa naok)
                          ", with endpoints moved: " (itoa namoved)
                          ", endpoints moved in total: " (itoa nasnap) ")")
                  (> namoved 0))
            (cons (strcat "Overlapping line pairs: " (itoa (length olaps))
                          (if olaps
                            (strcat " (merged: " (itoa nomerged)
                                    ", flagged: " (itoa noflag)
                                    ", left as drawn: " (itoa noleft) ")")
                            " - none found"))
                  (> noflag 0))
            (cons (strcat "Steps: " stepsum)          (dchk:attn-p stepsum))
            (cons (strcat "Liner Material: " linersum) (dchk:attn-p linersum))))
        (if htsum
          (setq hdr (append hdr (list (cons (strcat "Overall height: " htsum)
                                            (dchk:attn-p htsum))))))
        (setq txt (strcat "DIMCHECK REPORT - " (dchk:datestr)
                          "\\P"
                          (dchk:small
                            (strcat "Items needing attention are shown in "
                                    (dchk:red "red") ", larger than the rest."))))
        (foreach pr hdr
          (setq txt (strcat txt "\\P"
                            (if (cdr pr)
                              (dchk:red (car pr))
                              (dchk:small (car pr))))))
        (setq txt (strcat txt "\\P"
                          (dchk:small "----------------------------------------")))
        (foreach l (reverse lines)
          (setq txt (strcat txt "\\P"
                            (if (dchk:attn-p l) (dchk:red l) (dchk:small l)))))
        (dchk:mtext ins h (* *dchk-report-chars* h) txt *dchk-report-layer*)

        ;; --- show the drawing plus the report -----------------------
        (if minx
          (progn
            (setq m (* 0.05 (max (- maxx minx) (- maxy miny) 1.0)))
            (command "_.ZOOM" "_Window"
                     (trans (list (- minx m) (- miny m) 0.0) 0 1)
                     (trans (list (+ (car ins) (* *dchk-report-chars* h) m)
                                  (+ maxy m) 0.0)
                            0 1)))
          (command "_.ZOOM" "_Center" vc vs))

        (command "_.UNDO" "_End")
        (setq undo-open nil)
        (setvar "CMDECHO" oldecho)
        (princ (strcat "\n\n--- DIMCHECK complete ---"
                       "\nDimensions: " (itoa (length dims)) " checked, "
                       (itoa ndok) " correct, "
                       (itoa ndflag) " flagged to fix (red)"
                       (if (> ndmoved 0)
                         (strcat ", " (itoa ndmoved) " point(s) adjusted")
                         "")
                       "\nArcs: " (itoa (length arcs)) " checked, "
                       (itoa namoved) " with endpoint(s) moved ("
                       (itoa nasnap) " endpoint(s), magenta)"
                       "\nOverlapping lines: " (itoa (length olaps)) " pair(s) found"
                       (if olaps
                         (strcat ", " (itoa nomerged) " merged, "
                                 (itoa noflag) " flagged (cyan), "
                                 (itoa noleft) " left as drawn")
                         "")
                       "\nSteps: " stepsum
                       (if htsum (strcat "\nOverall height: " htsum) "")
                       "\nLiner Material: " linersum
                       "\nReport placed on the right side of the drawing (layer "
                       *dchk-report-layer* ")."
                       (if (> ndmoved 0)
                         (strcat "\nConstruction lines through moved dimensions' original points are on layer "
                                 *dchk-constr-layer* ".")
                         "")
                       "\nOne UNDO reverts everything DIMCHECK changed (including the report)."))))))
  (princ))

;; --- DIMSCAN: the read-only twin -----------------------------------
;;  Runs every audit, asks nothing, and changes nothing in the drawing
;;  except writing the report. Use it as a quick pre-flight, or when
;;  you want the findings without touching a released sheet.

(defun c:DIMSCAN ( / *error* oldecho ss i e et ed cands dims arcs plns segs
                     blks lines olaps pr sgroups scand svgroups pgroups
                     g g1 g2 rest svbb stepht satts liners fgstep linerstep
                     beadss beadbbs bb gbb tlist tins bp cx cy d tbest
                     wallraw wallvals wallvar wallmany wallht hdim dimht
                     htval htbad htsum stepsum linersum bad wnd
                     nd ndbad na nabad h m ins txt nlin ref hdr l
                     minx miny maxx maxy p13 p14 near s b w)

  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nDIMSCAN error: " msg)))
    (princ))

  (prompt "\nHighlight the drawing to DIMSCAN (Enter = whole drawing): ")
  (setq ss (ssget))
  (if (null ss) (setq ss (ssget "_X")))
  (cond
    ((null ss) (prompt "\nNothing to scan."))
    (t
     (setq oldecho (getvar "CMDECHO"))
     (setvar "CMDECHO" 0)
     (setq i 0 nd 0 ndbad 0 na 0 nabad 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (member et '("LINE" "LWPOLYLINE" "POLYLINE")) (setq plns (cons e plns)))
       (if (= et "INSERT") (setq blks (cons e blks)))
       (if (member et *dchk-curve-types*) (setq cands (cons e cands)))
       (setq bb (dchk:bbox e))
       (if bb
         (setq minx (if minx (min minx (caar bb)) (caar bb))
               miny (if miny (min miny (cadar bb)) (cadar bb))
               maxx (if maxx (max maxx (caadr bb)) (caadr bb))
               maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))
     (setq dims (reverse dims) arcs (reverse arcs)
           plns (reverse plns) blks (reverse blks) cands (reverse cands)
           segs (dchk:collect-segs plns))

     ;; --- dimensions: report stray definition points, move nothing
     (foreach e (dchk:sort-dims dims (if (and miny maxy) (* 0.05 (- maxy miny)) 1.0))
       (setq ed  (entget e)
             nd  (1+ nd)
             p13 (cdr (assoc 13 ed))
             p14 (cdr (assoc 14 ed))
             bad nil)
       (if (member (logand 7 (cdr (assoc 70 ed))) '(0 1))
         (foreach s (list (cons "point 1" p13) (cons "point 2" p14))
           (if (cdr s)
             (progn
               (setq near (dchk:nearest-curve (cdr s) nil cands))
               (if (and near (> (caddr near) *dchk-tol*))
                 (setq bad (append bad (list (strcat (car s) " off by "
                                                     (rtos (caddr near) 2 4))))))))))
       (if bad (setq ndbad (1+ ndbad)))
       (setq lines (cons (strcat "Dim " (cdr (assoc 5 ed))
                                 (if (= (dchk:dim-style e) "") ""
                                   (strcat " [" (dchk:dim-style e) "]"))
                                 (if (dchk:dim-meas e)
                                   (strcat " = " (dchk:dim-meas e)) "")
                                 ": "
                                 (if bad
                                   (strcat "NOT attached - " (dchk:join bad ", "))
                                   "OK")
                                 (if (dchk:dim-assoc-p e) " (associative)" ""))
                         lines)))

     ;; --- arcs: report unattached endpoints, move nothing
     (foreach e arcs
       (setq na  (1+ na)
             bad nil)
       (if (dchk:planar-arc-p (entget e))
         (foreach s '(("start" . start) ("end" . end))
           (if (dchk:arc-end-target e (cdr s) cands)
             (setq bad (append bad (list (car s)))))))
       (if bad (setq nabad (1+ nabad)))
       (setq lines (cons (strcat "Arc " (cdr (assoc 5 (entget e))) ": "
                                 (if bad
                                   (strcat (dchk:join bad " & ")
                                           " NOT attached to an object end")
                                   "endpoints OK"))
                         lines)))

     ;; --- overlaps
     (setq olaps (dchk:find-overlaps segs))
     (foreach pr olaps
       (setq lines (cons (strcat "Lines "
                                 (cdr (assoc 5 (entget (dchk:seg-ent (car pr)))))
                                 "+"
                                 (cdr (assoc 5 (entget (dchk:seg-ent (cadr pr)))))
                                 ": OVERLAP of "
                                 (rtos (caddr (dchk:overlap-info (car pr) (cadr pr))))
                                 " - flagged")
                         lines)))

     ;; --- steps / side view (detection only, nothing asked)
     (setq sgroups (dchk:step-groups segs (min *dchk-step-minlines*
                                               *dchk-bench-minlines*))
           scand   (vl-remove-if-not 'dchk:staircase-p sgroups)
           rest    scand)
     (while rest
       (setq g1 (car rest))
       (foreach g2 (cdr rest)
         (if (and (> (dchk:ang-diff (car g1) (car g2)) (- (* 0.5 pi) 0.09))
                  (dchk:boxes-touch (dchk:pts-bbox (cdr g1))
                                    (dchk:pts-bbox (cdr g2))
                                    *dchk-step-maxgap*))
           (progn
             (if (not (member g1 svgroups)) (setq svgroups (cons g1 svgroups)))
             (if (not (member g2 svgroups)) (setq svgroups (cons g2 svgroups))))))
       (setq rest (cdr rest)))
     (setq pgroups (vl-remove-if
                     '(lambda (x) (or (member x svgroups)
                                      (< (length (cdr x)) *dchk-step-minlines*)))
                     sgroups))
     (if svgroups
       (setq svbb   (dchk:pts-bbox (apply 'append (mapcar 'cdr svgroups)))
             stepht (- (cadr (cadr svbb)) (cadr (car svbb)))))
     (setq satts (vl-remove-if-not
                   '(lambda (x) (dchk:ins-matches x "Step Attachment")) blks))
     (setq stepsum
           (cond
             ((and (null svgroups) (null pgroups)) "no step patterns detected")
             (svgroups
              (strcat "side view detected, rise " (rtos stepht)
                      (if satts "; Step Attachment present"
                        "; Step Attachment block MISSING - add one")))
             (t (strcat (itoa (length pgroups))
                        " possible step pattern(s) - run DIMCHECK to confirm"))))
     (foreach g pgroups
       (setq lines (cons (strcat "Steps: possible pattern of "
                                 (itoa (length (cdr g))) " parallel lines")
                         lines)))
     ;; bead track when the attachment is a bead one
     (if (and satts svgroups
              (vl-some '(lambda (x) (dchk:ins-matches x "Bead Step Attachment"))
                       satts))
       (progn
         (setq beadss (ssget "_X" (list (cons 8 *dchk-bead-layer*))) i 0)
         (if beadss
           (repeat (sslength beadss)
             (setq bb (dchk:bbox (ssname beadss i)) i (1+ i))
             (if bb (setq beadbbs (cons bb beadbbs)))))
         (foreach g pgroups
           (setq gbb (dchk:pts-bbox (cdr g)))
           (if (not (and gbb beadbbs (dchk:bead-near-p gbb beadbbs)))
             (setq lines (cons (strcat "Bead Track: NOTHING on layer '"
                                       *dchk-bead-layer*
                                       "' near a step pattern - add bead track")
                               lines))))))

     ;; --- wall height
     (setq tlist (vl-remove-if-not
                   '(lambda (x) (wcmatch (dchk:squash (dchk:block-name x))
                                         (strcat "*" (dchk:squash *dchk-title-block*) "*")))
                   blks))
     (if (null tlist)
       (progn
         (setq beadss (ssget "_X" '((0 . "INSERT"))) i 0)
         (if beadss
           (repeat (sslength beadss)
             (setq b (ssname beadss i) i (1+ i))
             (if (wcmatch (dchk:squash (dchk:block-name b))
                          (strcat "*" (dchk:squash *dchk-title-block*) "*"))
               (setq tlist (cons b tlist)))))))
     (setq cx (if minx (* 0.5 (+ minx maxx)) 0.0)
           cy (if miny (* 0.5 (+ miny maxy)) 0.0))
     (foreach b tlist
       (setq bp (cdr (assoc 10 (entget b)))
             d  (distance (list cx cy) (list (car bp) (cadr bp))))
       (if (or (null tbest) (< d tbest)) (setq tbest d tins b)))
     (if tins
       (setq wallraw  (dchk:ins-attrib-deep tins *dchk-wallht-tag*)
             wallvals (if wallraw (dchk:len-values wallraw))
             wallvar  (and wallraw (dchk:varies-p wallraw))
             wallmany (> (length wallvals) 1)
             wallht   (if (and wallvals (not wallmany)) (car wallvals))))
     (if (and svbb stepht (not (or wallvar wallmany)))
       (setq hdim (dchk:height-dim dims svbb stepht)))
     (if hdim (setq dimht (dchk:dim-stated hdim)))
     (setq htval (if dimht dimht stepht)
           htbad (and htval wallht (> (abs (- htval wallht)) *dchk-height-tol*)))
     (setq htsum
           (cond
             ((null htval) nil)
             ((null tins) (strcat "steps rise " (rtos htval) " but no '"
                                  *dchk-title-block* "' block found - NOT CONFIRMED"))
             (wallvar (strcat "steps rise " (rtos htval) " and " *dchk-wallht-tag*
                              " reads '" wallraw "' - height varies, not checked"))
             (wallmany (strcat "steps rise " (rtos htval) " but " *dchk-wallht-tag*
                               " holds " (itoa (length wallvals)) " heights ('" wallraw
                               "') - CHECK THE WALL HEIGHT in the " *dchk-title-block*))
             ((null wallht) (strcat "steps rise " (rtos htval) " but "
                                    *dchk-wallht-tag* " is unreadable - NOT CONFIRMED"))
             ((not htbad) (strcat "steps rise " (rtos htval) " = WallHt '"
                                  wallraw "' - MATCHES"))
             (t (strcat "steps rise " (rtos htval) " but WallHt is '" wallraw
                        "' (" (rtos wallht) ") - MISMATCH"))))

     ;; --- liner
     (setq liners (vl-remove-if-not
                    '(lambda (x) (dchk:ins-matches x "Liner Material")) blks)
           fgstep (dchk:fgstep-src ss blks))
     (if liners
       (setq linerstep (vl-some '(lambda (x) (dchk:ins-has-word x "STEP")) liners)))
     (foreach b liners
       (setq bad nil)
       (foreach w '("NOT" "ERROR")
         (if (dchk:ins-has-word b w)
           (progn (setq bad (append bad (list w)))
                  (if (not (member w wnd)) (setq wnd (append wnd (list w)))))))
       (setq lines (cons (strcat "Liner Material (" (dchk:block-name b) ") "
                                 (cdr (assoc 5 (entget b))) ": "
                                 (if bad
                                   (strcat "contains the word " (dchk:join bad " & ")
                                           " - look at it")
                                   "OK"))
                         lines)))
     (if (and fgstep linerstep)
       (setq lines (cons (strcat "Liner Material: a Fiberglass Step (" fgstep
                                 ") is in the drawing but the liner pattern HAS a Step - it should not")
                         lines)))
     (if (and (not fgstep) svgroups liners (not linerstep))
       (setq lines (cons "Liner Material: steps are drawn but the liner pattern is MISSING its 'Step'"
                         lines)))
     (setq linersum
           (cond
             ((null liners) "block MISSING - add 'Liner Material' (or 'with Step')")
             (t (strcat (itoa (length liners)) " block(s) found"
                        (if wnd (strcat "; word " (dchk:join wnd " & ") " found - review") "")
                        (if (and fgstep linerstep)
                          "; Fiberglass Step in the drawing but the liner HAS a Step" "")
                        (if (and (null wnd) (not (and fgstep linerstep))) " - OK" "")))))

     ;; --- report (the only thing DIMSCAN writes) ------------------
     (dchk:ensure-layer *dchk-report-layer* *dchk-report-color*)
     (dchk:clear-old)
     (setq hdr (list
                 (cons (strcat "Dimensions scanned: " (itoa nd) " ("
                               (itoa ndbad) " with a stray definition point)")
                       (> ndbad 0))
                 (cons (strcat "Arcs scanned: " (itoa na) " ("
                               (itoa nabad) " with an unattached end)")
                       (> nabad 0))
                 (cons (strcat "Overlapping line pairs: " (itoa (length olaps)))
                       (> (length olaps) 0))
                 (cons (strcat "Steps: " stepsum)           (dchk:attn-p stepsum))
                 (cons (strcat "Liner Material: " linersum) (dchk:attn-p linersum))))
     (if htsum
       (setq hdr (append hdr (list (cons (strcat "Overall height: " htsum)
                                         (dchk:attn-p htsum))))))
     (setq nlin 3.0)
     (foreach l lines
       (setq nlin (+ nlin (if (dchk:attn-p l) 1.0 *dchk-green-scale*))))
     (setq nlin (+ nlin (* 6.0 *dchk-green-scale*)))
     (if (and minx (> (max (- maxy miny) (- maxx minx)) 1e-8))
       (progn
         (setq ref (max (- maxy miny) (* 0.25 (- maxx minx)))
               h   (/ ref (* 1.66 nlin)))
         (if (> h (/ ref 30.0))  (setq h (/ ref 30.0)))
         (if (< h (/ ref 200.0)) (setq h (/ ref 200.0))))
       (setq h 2.5))
     (setq ins (if minx
                 (list (+ maxx (* 0.05 (max (- maxx minx) 1.0))) maxy 0.0)
                 (list 0.0 0.0 0.0)))
     (setq txt (strcat "DIMSCAN REPORT - " (dchk:datestr)
                       "\\P"
                       (dchk:small (strcat "Read-only scan - nothing in the drawing was changed. "
                                           "Items needing attention are shown in "
                                           (dchk:red "red") "."))))
     (foreach pr hdr
       (setq txt (strcat txt "\\P" (if (cdr pr) (dchk:red (car pr))
                                     (dchk:small (car pr))))))
     (setq txt (strcat txt "\\P" (dchk:small "----------------------------------------")))
     (foreach l (reverse lines)
       (setq txt (strcat txt "\\P" (if (dchk:attn-p l) (dchk:red l) (dchk:small l)))))
     (dchk:mtext ins h (* *dchk-report-chars* h) txt *dchk-report-layer*)
     (setvar "CMDECHO" oldecho)
     (princ (strcat "\n--- DIMSCAN complete (read-only) ---"
                    "\nDimensions: " (itoa nd) " scanned, " (itoa ndbad) " with a stray point"
                    "\nArcs: " (itoa na) " scanned, " (itoa nabad) " with an unattached end"
                    "\nOverlapping line pairs: " (itoa (length olaps))
                    "\nSteps: " stepsum
                    "\nLiner Material: " linersum
                    (if htsum (strcat "\nOverall height: " htsum) "")
                    "\nReport written on layer " *dchk-report-layer*
                    "; nothing else was changed."))))
  (princ))

(princ "\ndimcheck.lsp loaded - DIMCHECK reviews dimensions & arcs one at a time,")
(princ "\n  DIMSCAN reports everything read-only, DIMCHECKRESCUE undoes DIMCHECK's marks.")
(princ)
