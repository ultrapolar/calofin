;;; ------------------------------------------------------------------
;;;  covercheck.lsp -- COVERCHECK: interactive dimension & arc QA review
;;;
;;;  Based on dimcheck.lsp (DIMCHECK), reworked into the cover
;;;  review: the same guided, one-at-a-time audit of dimensions,
;;;  arcs and overlapping lines, with COVER's own rules in place of
;;;  DIMCHECK's step, wall-height and liner checks.
;;;
;;;  VERSIONING. This file is distributed under two names at once:
;;;    - covercheck.lsp             the STATIC name, unchanged forever
;;;                                 so it stays a one-time entry in
;;;                                 everyone's AutoCAD app autoloader.
;;;    - covercheck_MMDDYY_REV##.lsp  a byte-identical copy saved under
;;;                                 a name that records exactly which
;;;                                 revision it is, so opening someone
;;;                                 else's support folder tells you at
;;;                                 a glance what they have loaded.
;;;  The two files must always carry the same content. Whenever
;;;  covercheck.lsp changes, bump *cchk-version* below and regenerate
;;;  the dated twin with python3 tools/release_lisp.py (the twin's
;;;  REV## is the version with the dot dropped, v0.2 -> REV02; git
;;;  history keeps the earlier dated copies).
;;;  *cchk-version* is also stamped into the load banner, into every
;;;  COVERCHECK/COVERSCAN report's title line, and is available on
;;;  demand via the COVERCHECKVER command - so even a renamed or
;;;  copy-pasted file always tells you which revision produced it.
;;;
;;;  Type COVERCHECK, then:
;;;
;;;  1. You are asked to highlight the drawing (any selection).
;;;     Everything selected is greyed out so only the item under
;;;     review stands out.
;;;
;;;  2. Dimensions are reviewed ONE AT A TIME, in a fixed marching
;;;     order: grouped by dimension style -- "STANDARD", then "SIDE
;;;     STANDARD", then "STANDARD INCHES", then "CROSS DIMENSIONS",
;;;     then whatever styles are left (tune *cchk-style-order*) --
;;;     and inside each group left to right, top to bottom (row by
;;;     row, like reading). Each dimension is zoomed to, shown in
;;;     its own colour and highlighted while the rest stays grey.
;;;     For linear/aligned dimensions the two definition points are
;;;     audited first: a point that does not sit on any object is
;;;     shown where COVERCHECK thinks it belongs, with BOTH spots
;;;     marked on screen and spelled out so there is no doubt which
;;;     is which --
;;;         a RED X   where you drew it,
;;;         a GREEN + where we would move it, joined by a line.
;;;     You then choose, one point at a time:
;;;         Enter / M  ->  MOVE it onto the nearest object (green +)
;;;         K          ->  KEEP it exactly where you drew it (red X);
;;;                        the point is put back and nothing changes
;;;         P          ->  PICK the spot yourself
;;;     A point TWO OR MORE DIMENSIONS measure to is an ANCHOR and is
;;;     never questioned, even with no geometry under it: dimensioning
;;;     twice to the same spot -- the pair of dims pinning down a
;;;     hypotenuse corner is the everyday case -- is how you say that
;;;     spot is the object. Anchors are read off the selection before
;;;     the review starts, so one cannot come and go partway through,
;;;     and a stray point nearer an anchor than any line is offered the
;;;     anchor instead of being dragged off to the line.
;;;     A construction line (XLINE) is drawn through the dimension's
;;;     original points on layer COVERCHECK-CONSTRUCTION so you can see
;;;     where it used to measure -- only when a point actually moved.
;;;     Then the overall question for every dimension:
;;;         "Is this dimension correct?"
;;;         Enter / Y  ->  correct, the dimension is left alone
;;;         N          ->  the dimension is recoloured RED so it is
;;;                        easy to find and fix afterwards
;;;
;;;  3. Arcs are reviewed the same way, one endpoint at a time, with
;;;     the same Move / Keep / Pick choice. An endpoint not attached
;;;     to the end of another object is snapped there and both spots
;;;     are marked; Keep puts the arc back exactly as you drew it
;;;     (its original shape is restored, not re-fitted), Pick re-fits
;;;     it through your spot. Arcs whose endpoints actually changed
;;;     are recoloured MAGENTA -- an arc you kept is left alone.
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
;;;  5. COVER CHECKS -- nothing here rewrites the drawing; every
;;;     disagreement is only SUGGESTED against, in the report:
;;;     - TECH TITLE DATE. The Date attribute of the "Tech Title"
;;;       block (tune *cchk-title-block* / *cchk-date-tag*) must read
;;;       TODAY, written MM/DD/YYYY - a sheet going out under an old
;;;       date is the mistake this catches. The block is looked for in
;;;       the selection and then across the drawing; with none in
;;;       reach the report says the date was not checked rather than
;;;       flagging it. LITECOVERSCAN keeps this one.
;;;     - FEET AND INCHES. Every text box in the selection - TEXT,
;;;       MTEXT and the ATTRIB values on blocks - must state its
;;;       inches wherever it states feet: 5' is flagged, 5'-0",
;;;       3'-2" and a plain 40" are fine. A feet mark is an
;;;       apostrophe straight after a digit, so "Water's Edge" is
;;;       prose and never flagged. LITECOVERSCAN keeps this one.
;;;     - DIMENSION LAYER. Every dimension must sit on the
;;;       "DIMENSION" layer (tune *cchk-dim-layer*). Any that do not
;;;       are counted, the layers they landed on are named, and the
;;;       report tells you to run CDIM (tune *cchk-dimfix-cmd*) to
;;;       move them. This one runs in LITECOVERSCAN too.
;;;     - POOL OUTLINE & AREA. Everything in the selection on layer
;;;       "POOL" (tune *cchk-pool-layer*) whose properties are all
;;;       ByLayer is the pool outline: a closed (lw)polyline, a
;;;       CIRCLE, or the same shape exploded into lines and arcs --
;;;       touching ends are chained back together and the largest
;;;       closed loop wins; leftover open chains or other closed loops
;;;       are reported as AMBIGUOUS. Its area (sq ft) and its straight
;;;       / arc segment split are given in the report on the side.
;;;     - COVER DETAILS. A block named (or containing) "Cover
;;;       Details" holds an OVERLAP value ("Overlap: 12''" -- only
;;;       12"/15"/18" exist) and a SPACING tag ("Spacing: 5x5" --
;;;       NxN). What they SHOULD say comes from the outline:
;;;         more arcs than straights           -> 18" overlap, 3x3
;;;         mostly straights, under 1,200 sqft -> 12" overlap, 5x5
;;;         mostly straights, 1,200-2,000      -> 15" overlap, 3x3
;;;         mostly straights, over 2,000       -> 18" overlap, 3x3
;;;       A value that disagrees, is blank or is unreadable gets a
;;;       SUGGEST line; the block itself is never touched.
;;;     - POOL SIZE SHOWN. With nothing drawn on the cover layer
;;;       (tune *cchk-cover-layer*) the note "Pool Size Shown" must
;;;       appear somewhere in the highlighted area -- missing is
;;;       suggested. With a cover drawn the note must NOT be there --
;;;       present suggests taking it off; absent is all good. If both
;;;       "Pool Size Shown" and "Spa Size Shown" (tune
;;;       *cchk-spa-note*) turn up in the same selection, that is
;;;       flagged as an error -- ONLY ONE SIZE CAN BE SHOWN.
;;;     - COVER LAYER = POLYLINES. Anything drawn on the cover layer
;;;       that is not a polyline is called out.
;;;     - OVERLAP NA <-> DASHED OUTLINE. Overlap reading NA means no
;;;       dashed polyline may sit on the pool layer; a stated overlap
;;;       demands one and its absence is reported - UNLESS the "Pool
;;;       Size Shown" note (above) is in the selection, in which case
;;;       this demand is skipped entirely.
;;;     - REPLACEMENT. A "Replacement Disclaimer" block should be in
;;;       the selection. Without one - and without a "Pool Size Shown"
;;;       note either - COVERCHECK asks whether the drawing is a
;;;       replacement; answering Yes asks you to point at the block,
;;;       and not finding it is reported. A "Pool Size Shown" note
;;;       skips the question outright (a full pool size drawing is
;;;       never a replacement). COVERSCAN cannot ask and just notes
;;;       the block is not there.
;;;     - Under any of these - a replacement, an NA overlap, or a
;;;       cover drawn on the cover layer - PADDLE pads are NOT
;;;       suggested.
;;;     - PADS. The pool outline is run through PADDLE's concave-
;;;       feature hunt at 36" pads (PADDLE v1.2 rules): an inside
;;;       corner gets a pad centered dead on the corner, a concave
;;;       radius of 4'-6" or less gets a row of pads starting on the
;;;       middle of the radius and marching flush (36" on center)
;;;       toward both ends, and geometry that bends 10 degrees or
;;;       less - a semi-straight kink, a gently sweeping arc - is
;;;       passed over. Suggested pads never overlap each other: a
;;;       pad on a sharp point holds its spot, the ones along curves
;;;       slide flush alongside or drop out. Every spot with no pad
;;;       already nearby (existing pads = *cchk-pad-blocks* inserts,
;;;       or any insert on *cchk-pads-layer*) is circled on the
;;;       construction layer and SUGGESTED in the report.
;;;
;;;  6. A COVERCHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;     drawing on layer COVERCHECK-REPORT, sized from the drawing's
;;;     extents so it sits to scale next to it.  The MAIN sheet leads
;;;     with what matters to the cover itself: a large title, the
;;;     date and version, a verdict line (ALL CLEAR, or the count of
;;;     red lines), the colour legend, a SUMMARY dashboard, then the
;;;     COVER CHECKS findings under underlined section headings.
;;;     The DIMCHECK-style findings -- every dimension with its
;;;     measured distance, every arc, every overlapping line pair
;;;     with its overlap length -- go in a separate DIMENSION AUDIT
;;;     column to the RIGHT of the main sheet, so the cover verdicts
;;;     lead and the mechanical audit reads alongside.  Any line
;;;     describing something questionable or that needs looking over
;;;     (a flagged/wrong item, a missing block, a "NOT" find, an
;;;     "add ..." note, a skipped check) is coloured RED in the
;;;     report; everything that checked out stays the report's
;;;     normal colour and is drawn at *cchk-green-scale* (3/4) of
;;;     the red text's height, so the problems are the big lines on
;;;     the sheet.
;;;
;;;  LITECOVERSCAN is COVERSCAN minus the DIMCHECK-style pass: no
;;;     dimension, arc or overlap audit and no DIMENSION AUDIT
;;;     column - just the cover rules, for a drawing DIMCHECK
;;;     already went over.
;;;
;;;  All original colours are restored when the review ends -- except
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
;;;    points are moved -- an associative point may re-anchor on its
;;;    own -- and their report line says so in red.
;;;  - Rerunning COVERCHECK replaces the previous report and marker
;;;    lines instead of stacking a second copy on top.
;;;  - Original colours are stashed in xdata before greying. If a
;;;    crash or kill ever leaves the drawing grey, COVERCHECKRESCUE
;;;    restores every stashed colour and clears COVERCHECK's report
;;;    and markers (flag colours included -- it is the full reset).
;;; ------------------------------------------------------------------

;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;

(vl-load-com)

;; --- version ---------------------------------------------------------
;; bump this on every change that reaches covercheck.lsp; see the
;; VERSIONING note above the file header for the two-file convention
(setq *cchk-version* "v1.9")

;; --- tunables ------------------------------------------------------
(setq *cchk-tol*          1.0e-4)  ; max gap (drawing units) that still counts as attached
(setq *cchk-grey-color*   8)       ; grey used to fade out everything not under review
(setq *cchk-flag-color*   1)       ; red: dimensions you answered "No" to
(setq *cchk-arc-color*    6)       ; magenta: arcs whose endpoints were moved
(setq *cchk-olap-color*   4)       ; cyan: merged or flagged overlapping lines
(setq *cchk-olap-fuzz*    1.0e-4)  ; max sideways offset that still counts as "same line"

;; dimension styles are reviewed in this order; styles not listed
;; come afterwards ("whatever else is left"), still left-to-right
(setq *cchk-style-order*
      '("STANDARD" "SIDE STANDARD" "STANDARD INCHES" "CROSS DIMENSIONS"))
;; every dimension belongs on this layer; CDIM is the command that
;; moves the strays there, and is what the report tells you to run
(setq *cchk-dim-layer*   "DIMENSION")
;; the sheet's title block, and the attribute in it carrying the date;
;; the date must read today, written MM/DD/YYYY
(setq *cchk-title-block* "Tech Title")  ; spaces optional in the name
(setq *cchk-date-tag*    "Date")
(setq *cchk-dimfix-cmd*  "CDIM")
(setq *cchk-constr-layer* "COVERCHECK-CONSTRUCTION")
(setq *cchk-constr-color* 2)       ; yellow
(setq *cchk-green-scale*  0.75)    ; report: all-clear text height, as a fraction of the red text
(setq *cchk-block-depth*  3)       ; how many levels of nested blocks to search for names/text
(setq *cchk-orig-color*   1)       ; red X: where you drew the point
(setq *cchk-sugg-color*   3)       ; green +: where COVERCHECK would move it
(setq *cchk-report-layer* "COVERCHECK-REPORT")
(setq *cchk-report-color* 3)       ; green
(setq *cchk-zoom-margin*  0.75)    ; empty space around the zoomed item (fraction of its size)
(setq *cchk-report-chars* 45.0)    ; report column width, in text heights
(setq *cchk-ask-all-arc-ends* nil) ; T = confirm EVERY arc endpoint, even already-attached ones
(setq *cchk-anchor-tol*   1.0e-4)  ; how close two dimension points must be to count as the same spot
(setq *cchk-anchor-min*   2)       ; that many dimensions meeting there make it an anchor

;; entity types dimension points and arc ends may attach to
(setq *cchk-curve-types*
      '("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"))

;; --- cover tunables ------------------------------------------------
(setq *cchk-pool-layer*  "POOL")   ; layer the pool outline is drawn on (ByLayer properties)
(setq *cchk-cover-layer* "COVER")  ; layer a drawn cover lives on
(setq *cchk-pool-note*   "Pool Size Shown") ; note demanded when no cover is drawn
(setq *cchk-spa-note*    "Spa Size Shown")  ; the pool note's spa counterpart - both together is an error
(setq *cchk-details-block* "Cover Details") ; block carrying Overlap & Spacing
(setq *cchk-overlap-vals* '(12.0 15.0 18.0)) ; the only overlaps that exist
(setq *cchk-area-small*  1200.0)   ; sq ft: under this -> 12" overlap, 5x5
(setq *cchk-area-large*  2000.0)   ; sq ft: over this -> 18" overlap, 3x3
(setq *cchk-pad-size*    36.0)     ; pads are suggested at 36" (PADDLE's big pad)
(setq *cchk-pad-blocks*  '("Pad36x36" "Pad24x24")) ; blocks that count as an existing pad
(setq *cchk-pads-layer*  "PADS")   ; layer existing pads sit on
(setq *cchk-pad-near*    18.0)     ; a pad center within this (Chebyshev) covers a spot
(setq *cchk-pad-maxrad*  54.0)     ; 4'-6": largest concave radius needing pads (PADDLE)
(setq *cchk-chain-fuzz*  0.05)     ; max gap when chaining an exploded outline
(setq *cchk-pad-angtol*  (/ (* 10.0 pi) 180.0)) ; 10 deg: a corner - or a whole arc - bending this little is semi-straight (PADDLE)
(setq *cchk-repl-block*  "Replacement Disclaimer") ; block demanded on replacement drawings
(setq *cchk-dashed-pat*  "*DASH*,*HIDDEN*") ; linetype names that count as dashed
(setq *cchk-tut-layer*   "TUTORIAL-COVERCHECK-DEMO") ; layer for TUTORIALCOVERCHECK's non-pool demo geometry

;; --- safety: xdata tags, colour stash, layer locks -----------------

(defun cchk:regapp ()
  (if (not (tblsearch "APPID" "COVERCHECK"))
    (regapp "COVERCHECK")))

(defun cchk:xd (ent / g)
  ;; COVERCHECK's xdata groups on ent, nil when none
  (setq g (assoc -3 (entget ent '("COVERCHECK"))))
  (if g (cdadr g)))

(defun cchk:tag (ent kind / ed)
  ;; stamp a COVERCHECK-created entity (report, marker line) so a rerun
  ;; or COVERCHECKRESCUE can find and clear it
  (cchk:regapp)
  (setq ed (entget ent '("COVERCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "COVERCHECK" (cons 1000 kind))))))))

(defun cchk:stash-color (ent col / ed)
  ;; remember the entity's own colour in xdata so COVERCHECKRESCUE can
  ;; put it back even after a crash; an existing stash (from an
  ;; interrupted run - the TRUE original) is never overwritten
  (cchk:regapp)
  (setq ed (entget ent '("COVERCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "COVERCHECK"
                                            '(1000 . "COLOR")
                                            (cons 1071 col))))))))

(defun cchk:unstash (ent / ed)
  ;; drop COVERCHECK's xdata once the run has restored things itself
  (setq ed (entget ent '("COVERCHECK")))
  (if (and ed (assoc -3 ed))
    (entmod (subst (list -3 (list "COVERCHECK")) (assoc -3 ed) ed))))

(defun cchk:clear-old (/ ss2 i e xd n)
  ;; erase the report and marker lines left by an earlier COVERCHECK
  ;; run, so a rerun replaces them instead of stacking on top
  (setq ss2 (ssget "_X" '((-3 ("COVERCHECK")))) n 0 i 0)
  (if ss2
    (repeat (sslength ss2)
      (setq e  (ssname ss2 i)
            i  (1+ i)
            xd (cchk:xd e))
      (if (member (cdr (assoc 1000 xd)) '("REPORT" "XLINE" "MARKER"))
        (progn (entdel e) (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\n(Removed " (itoa n)
                   " report/marker item(s) from an earlier COVERCHECK run.)"))))

(defun cchk:layer-locked-p (name / ld)
  (setq ld (tblsearch "LAYER" name))
  (and ld (= 4 (logand 4 (cdr (assoc 70 ld))))))

(defun cchk:set-layer-lock (name lock / ed old new)
  ;; set or clear a layer's locked flag; T when it actually changed
  (setq ed  (entget (tblobjname "LAYER" name))
        old (cdr (assoc 70 ed))
        new (if lock (logior old 4) (logand old (~ 4))))
  (if (/= old new)
    (progn (entmod (subst (cons 70 new) (assoc 70 ed) ed)) T)))

(defun cchk:dim-assoc-p (ent / found g)
  ;; T when the dimension carries persistent reactors - the mark of
  ;; an object-associative dim, whose definition points may re-anchor
  ;; on their own after being moved
  (foreach g (entget ent)
    (if (and (= 102 (car g)) (= "{ACAD_REACTORS" (cdr g)))
      (setq found T)))
  found)

(defun c:COVERCHECKRESCUE ( / *error* undo-open ss i e xd n)
  ;; entdel/entmod over the whole drawing was N undos deep and
  ;; had no handler at all -- now one group, closed on both exits,
  ;; and a cancel that says nothing
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCOVERCHECKRESCUE error: " msg)))
    (princ))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") (setq undo-open T)))
  ;; the way out after a crash or interrupted run: puts back every
  ;; colour COVERCHECK stashed (flag colours included) and removes its
  ;; report and marker lines
  (setq ss (ssget "_X" '((-3 ("COVERCHECK")))) n 0 i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            xd (cchk:xd e))
      (cond
        ((member (cdr (assoc 1000 xd)) '("REPORT" "XLINE" "MARKER"))
         (entdel e)
         (setq n (1+ n)))
        ((assoc 1071 xd)
         (cchk:set-color e (cdr (assoc 1071 xd)))
         (cchk:unstash e)
         (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\nCOVERCHECKRESCUE: restored or removed " (itoa n) " item(s)."))
    (princ "\nCOVERCHECKRESCUE: nothing to restore - no COVERCHECK markers in the drawing."))
  (if undo-open (progn (command "_.UNDO" "_End") (setq undo-open nil)))
  (princ))

;; --- small helpers -------------------------------------------------

(defun cchk:ent-color (ent / c)
  ;; the entity's explicit colour, 256 (ByLayer) when it has none
  (setq c (cdr (assoc 62 (entget ent))))
  (if c c 256))

(defun cchk:set-color (ent color / ed old)
  (setq ed  (entget ent)
        old (assoc 62 ed))
  (entmod (if old
            (subst (cons 62 color) old ed)
            (append ed (list (cons 62 color)))))
  (entupd ent))

(defun cchk:make-xline (p1 p2 / len)
  ;; infinite construction line through p1-p2 on the check layer,
  ;; tagged so reruns and COVERCHECKRESCUE can clear it
  (setq len (distance p1 p2))
  (if (and (> len 1e-8)
           (entmake (list '(0 . "XLINE")
                          '(100 . "AcDbEntity")
                          (cons 8 *cchk-constr-layer*)
                          '(100 . "AcDbXline")
                          (cons 10 p1)
                          (cons 11 (mapcar '(lambda (x) (/ x len))
                                           (mapcar '- p2 p1))))))
    (cchk:tag (entlast) "XLINE")))

(defun cchk:closest-on (ent pt / res)
  ;; closest point on ent to pt; nil when ent is not curve-like
  (setq res (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (vl-catch-all-error-p res) nil res))

(defun cchk:nearest-curve (pt exclude cands / best bestd cp d e)
  ;; (ent closest-point distance) for the candidate closest to pt
  (foreach e cands
    (if (and (not (eq e exclude)) (setq cp (cchk:closest-on e pt)))
      (progn
        (setq d (distance pt cp))
        (if (or (null bestd) (< d bestd))
          (setq bestd d
                best  (list e cp d))))))
  best)

(defun cchk:curve-ends (ent / cl sp ep)
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

(defun cchk:closest-of (pt pts / best bestd d q)
  (foreach q pts
    (setq d (distance pt q))
    (if (or (null bestd) (< d bestd)) (setq bestd d best q)))
  best)

(defun cchk:nearest-end (pt exclude cands / best bestd d e q)
  ;; closest endpoint over every open candidate curve
  (foreach e cands
    (if (not (eq e exclude))
      (foreach q (cchk:curve-ends e)
        (setq d (distance pt q))
        (if (or (null bestd) (< d bestd)) (setq bestd d best q)))))
  best)

(defun cchk:ptstr (p)
  ;; formatted with the drawing's own unit settings (LUNITS/LUPREC),
  ;; same as every measurement elsewhere in the report
  (strcat "(" (rtos (car p)) ", " (rtos (cadr p)) ")"))

(defun cchk:zoom-ent (ent / bb p1 p2 m)
  ;; zoom the current view onto ent with some breathing room
  (setq bb (cal:bbox-ent ent))
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *cchk-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

(defun cchk:zoom-2ents (e1 e2 / b1 b2 p1 p2 m)
  ;; zoom onto the combined box of two entities
  (setq b1 (cal:bbox-ent e1)
        b2 (cal:bbox-ent e2))
  (cond
    ((and b1 b2)
     (setq p1 (list (min (caar b1) (caar b2))
                    (min (cadar b1) (cadar b2)))
           p2 (list (max (caadr b1) (caadr b2))
                    (max (cadadr b1) (cadadr b2)))
           m  (* *cchk-zoom-margin*
                 (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
     (command "_.ZOOM" "_Window"
              (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
              (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))
    (b1 (cchk:zoom-ent e1))
    (b2 (cchk:zoom-ent e2))))

(defun cchk:stage (ent saved keep)
  ;; bring an entity back to its own colour for review -- unless it
  ;; already wears a COVERCHECK marker colour it must not lose
  (if (and (entget ent) (not (member ent keep)))
    (cchk:set-color ent (cdr (assoc ent saved)))))

(defun cchk:unstage (ent keep)
  ;; send a reviewed entity back into the grey background
  (if (and (entget ent) (not (member ent keep)))
    (cchk:set-color ent *cchk-grey-color*)))

(defun cchk:mark-x (pt col / p s)
  ;; diagonal cross - marks WHERE YOU DREW IT
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (- (cadr p) s)) (list (+ (car p) s) (+ (cadr p) s)) col 1)
  (grdraw (list (- (car p) s) (+ (cadr p) s)) (list (+ (car p) s) (- (cadr p) s)) col 1))

(defun cchk:mark-plus (pt col / p s)
  ;; upright cross - marks WHERE COVERCHECK WOULD PUT IT
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (cadr p)) (list (+ (car p) s) (cadr p)) col 1)
  (grdraw (list (car p) (- (cadr p) s)) (list (car p) (+ (cadr p) s)) col 1))

(defun cchk:mark-point (pt)
  ;; both strokes, for a point that is simply being pointed out
  (cchk:mark-x pt 2)
  (cchk:mark-plus pt 2))

(defun cchk:confirm-move (label orig sugg what / ans newp)
  ;; The point has been put where COVERCHECK thinks it belongs, but BOTH
  ;; spots are marked and spelled out so there is no doubt which is
  ;; which: a red X where you drew it, a green + where we would move
  ;; it, joined by a line. WHAT names what the green + sits on, so a
  ;; move onto a shared anchor point does not claim to be an object.
  ;; Returns
  ;;   'move - take our suggestion
  ;;   'keep - put it back exactly where you drew it
  ;;   <point> - a spot you picked yourself (current UCS)
  (cchk:mark-x    orig *cchk-orig-color*)
  (cchk:mark-plus sugg *cchk-sugg-color*)
  (if (> (distance orig sugg) 1e-8)
    (grdraw (trans orig 0 1) (trans sugg 0 1) *cchk-sugg-color* 1))
  (princ (strcat "\n  " label " - which spot is right?"
                 "\n    Keep = where you drew it   " (cchk:ptstr orig)
                 "  (red X)"
                 "\n    Move = onto " what " " (cchk:ptstr sugg)
                 "  (green +), " (rtos (distance orig sugg) 2 4) " away"
                 "\n    Pick = somewhere else you point at"))
  (initget "Move Keep Pick")
  (setq ans (getkword
              "\n  [Move/Keep/Pick] <Move>: "))
  (cond
    ((or (null ans) (= ans "Move")) 'move)
    ((= ans "Keep") 'keep)
    (t (setq newp (getpoint (strcat "\n  Pick the spot for " label
                                    " <Move to the green +>: ")))
       (if newp newp 'move))))

(defun cchk:mtext (ins height width text layer / e)
  ;; entmake an MTEXT, splitting text into 250-char DXF chunks
  (if (setq e (cal:mtext ins height width text layer))
    (cchk:tag e "REPORT")))

(defun cchk:attn-p (s)
  ;; T when a report line describes something questionable or that
  ;; needs looking over / fixing, so the report renders it in red
  (wcmatch (strcase s)
    "*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO BLOCK*,*WORD NOT*,*WORD ERROR*,* ADD *,*MISMATCH*,*NOT CONFIRMED*,*NOT ATTACHED*,*OVERLAP*,*ASSOCIATIVE*,*DISAGREE*,*SUGGEST*,*BLANK*,*UNREADABLE*,*NOT A POLYLINE*,*LOOK AT*,*NO DASHED*,*AMBIGUOUS*,*ONLY ONE SIZE*,*NO INCHES*,*NOT TODAY*,*EXPECTED MM/DD/YYYY*"))

(defun cchk:red (s)
  ;; wrap an MTEXT run so it renders in the flag colour, reverting
  ;; to the surrounding colour after (braces scope the change)
  (strcat "{\\C" (itoa *cchk-flag-color*) ";" s "}"))

(defun cchk:small (s)
  ;; all-clear text renders at *cchk-green-scale* of the height the
  ;; red attention text gets, so problems stand out on the sheet
  (strcat "{\\H" (rtos *cchk-green-scale* 2 4) "x;" s "}"))

(defun cchk:big (s)
  ;; the report's title line: half again the base height
  (strcat "{\\H1.5x;" s "}"))

(defun cchk:hdg (s)
  ;; a section heading: underlined, with a thin blank line above it
  ;; so the sections read as blocks (the \P inside the first group is
  ;; a paragraph break at 0.4x height - a narrow gap, not a full line)
  (strcat "{\\H0.4x;\\P}{\\L" s "}"))

(defun cchk:linegrp (s)
  ;; which underlined section a report line files under, keyed on the
  ;; fixed prefixes the review gives its lines
  (cond ((wcmatch s "Dim *,Dimensions:*") "DIMENSIONS")
        ((wcmatch s "Arc *")              "ARCS")
        ((wcmatch s "Lines *")            "OVERLAPPING LINES")
        ((wcmatch s "Text *")             "TEXT & UNITS")
        (t                                "COVER CHECKS")))

(defun cchk:dimline-p (s)
  ;; T for a line that belongs to the DIMENSION AUDIT column - the
  ;; DIMCHECK-style findings, as opposed to the cover's own checks
  (member (cchk:linegrp s) '("DIMENSIONS" "ARCS" "OVERLAPPING LINES")))

;; Every dimension belongs on the dimension layer.  This is the one
;; dimension check the lite scan keeps: it costs a layer read apiece,
;; and a sheet whose dimensions sit on the wrong layer plots wrong
;; however sound the dimensions themselves are - so the verdict, and
;; the suggestion to run CDIM over them, belong on the main sheet
;; rather than in the DIMENSION AUDIT column.  The offending layers
;; are named, since that is what you need to go fix them.
;; Returns (sentence . needs-attention).
(defun cchk:dimlayer-verdict (dims / n off lays lay e)
  (setq n 0 off 0 lays nil)
  (foreach e dims
    (if (entget e)
      (progn
        (setq n   (1+ n)
              lay (cdr (assoc 8 (entget e))))
        (if (/= (strcase lay) (strcase *cchk-dim-layer*))
          (progn
            (setq off (1+ off))
            (if (not (member (strcase lay) lays))
              (setq lays (cons (strcase lay) lays))))))))
  (cond
    ((= n 0)
     (cons "no dimensions in the selection" nil))
    ((= off 0)
     (cons (strcat "all " (itoa n) " on " *cchk-dim-layer*) nil))
    (t
     (cons (strcat (itoa off) " of " (itoa n) " NOT on layer "
                   *cchk-dim-layer* " ("
                   (cchk:join (reverse lays) ", ")
                   ") - run " *cchk-dimfix-cmd* " to move them")
           T))))

;; --- feet-and-inch text ----------------------------------------------
;; A distance written in feet must state its inches too: 5' is wrong,
;; 5'-0" (or 5'-0'') is right, and a plain 40" is right as it stands.
;;
;; A FEET MARK is an apostrophe standing straight after a DIGIT, and
;; that is what keeps prose out of this: "Water's Edge", "Owner's" and
;; "don't" are possessives, not measurements, and are never flagged.
;; Two apostrophes together are the inch mark AutoCAD text often uses
;; in place of ", so 5'-0'' closes exactly as 5'-0" does.
;;
;; T when some feet mark in s is never closed by an inch mark before
;; the next feet mark or the end of the string -- so "5' and 7'-0"" is
;; caught on its first value while "3'-2"" passes.
(defun cchk:feet-open-p (s / lst n i c prev open found)
  (setq lst   (vl-string->list s)
        n     (length lst)
        i     0
        prev  0
        open  nil
        found nil)
  (while (< i n)
    (setq c (nth i lst))
    (cond
      ((= c 34)                                    ; " closes it
       (setq open nil i (1+ i)))
      ((and (= c 39) (< (1+ i) n) (= (nth (1+ i) lst) 39))
       (setq open nil i (+ i 2)))                  ; '' closes it too
      ((and (= c 39) (>= prev 48) (<= prev 57))    ; digit then ' = feet
       (if open (setq found T))                    ; the one before never closed
       (setq open T i (1+ i)))
      (t (setq i (1+ i))))
    (setq prev (nth (1- i) lst)))
  (or found open))

;; MTEXT reads \, { and } as formatting, so a snippet quoted out of the
;; drawing has them blanked before it goes anywhere near the report.
(defun cchk:mtsafe (s)
  (vl-list->string
    (mapcar '(lambda (c) (if (member c '(92 123 125)) 32 c))
            (vl-string->list s))))

;; The text an entity carries: TEXT and ATTRIB keep it in group 1,
;; MTEXT spills the overflow into group 3 chunks ahead of that.
(defun cchk:ent-text (ent / ed g head tail)
  (setq ed (entget ent) head "" tail "")
  (foreach g ed
    (cond ((= 3 (car g)) (setq head (strcat head (cdr g))))
          ((= 1 (car g)) (setq tail (cdr g)))))
  (strcat head tail))

;; Every text box in the selection: TEXT and MTEXT, plus the ATTRIB
;; values on blocks -- the parts of a block someone types into.  Text
;; baked into a block DEFINITION is left alone: it reads the same on
;; every insert and is not fixable from this drawing.
;; Returns ((handle . string) ...).
(defun cchk:text-items (ss / i e ed et out a ad)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            ed (entget e)
            et (if ed (cdr (assoc 0 ed))))
      (cond
        ((member et '("TEXT" "MTEXT"))
         (setq out (cons (cons (cdr (assoc 5 ed)) (cchk:ent-text e)) out)))
        ((and (= et "INSERT") (assoc 66 ed) (= 1 (cdr (assoc 66 ed))))
         (setq a (entnext e))
         (while (and a (setq ad (entget a)) (= "ATTRIB" (cdr (assoc 0 ad))))
           (setq out (cons (cons (cdr (assoc 5 ad)) (cchk:ent-text a)) out)
                 a   (entnext a)))))))
  (reverse out))

;; The verdict over every text box, plus one report line per offender.
;; Returns (sentence needs-attention (line ...)).
(defun cchk:audit-units (ss / items it s n bad lines)
  (setq items (cchk:text-items ss) n 0 bad 0 lines nil)
  (foreach it items
    (setq s (cdr it))
    (if (and s (/= s ""))
      (progn
        (setq n (1+ n))
        (if (cchk:feet-open-p s)
          (setq bad   (1+ bad)
                lines (cons (strcat "Text " (car it) ": \""
                                    (cchk:mtsafe (cchk:clip s 40))
                                    "\" gives feet with NO INCHES"
                                    " - write it 5'-0\" not 5'")
                            lines))))))
  (list
    (cond
      ((= n 0) "no text in the selection")
      ((= bad 0) (strcat "all " (itoa n) " text item"
                         (if (= 1 n) "" "s") " OK"))
      (t (strcat (itoa bad) " of " (itoa n) " text item"
                 (if (= 1 n) "" "s") " give feet with NO INCHES"
                 " - write 5'-0\" not 5'")))
    (> bad 0)
    (reverse lines)))

;; --- the Tech Title date ---------------------------------------------
;; The sheet's Tech Title block carries a Date attribute, and it must
;; read TODAY in MM/DD/YYYY form.  A sheet going out under an old date
;; is the mistake this catches: the drawing was reworked and the title
;; block never caught up.

(defun cchk:datenorm (s)
  ;; a value may arrive labelled ("Date = 05/01/2024"); the date is
  ;; whatever follows the last "="
  (cchk:after-eq (if s s "")))

(defun cchk:all-digits-p (s / i n c ok)
  (setq n (strlen s) ok (> n 0) i 1)
  (while (and ok (<= i n))
    (setq c (ascii (substr s i 1)))
    (if (or (< c 48) (> c 57)) (setq ok nil))
    (setq i (1+ i)))
  ok)

(defun cchk:days-in-month (mo yr)
  (cond
    ((member mo '(1 3 5 7 8 10 12)) 31)
    ((member mo '(4 6 9 11)) 30)
    ((and (= 0 (rem yr 4)) (or (/= 0 (rem yr 100)) (= 0 (rem yr 400)))) 29)
    (t 28)))

(defun cchk:today-mdy ( / d)
  ;; (month day year) off the computer clock.  CDATE is
  ;; YYYYMMDD.HHMMSSmsec, decoded arithmetically so DIMZIN (which trims
  ;; rtos output) cannot mangle it.
  (setq d (fix (getvar "CDATE")))
  (list (rem (fix (/ d 100)) 100) (rem d 100) (fix (/ d 10000))))

(defun cchk:mdy-str (mdy)
  (strcat (cal:zeropad2 (car mdy)) "/" (cal:zeropad2 (cadr mdy)) "/"
          (itoa (caddr mdy))))

;; nil when raw is today's date written MM/DD/YYYY; otherwise a short
;; string saying what is wrong with it.
(defun cchk:date-verdict (raw / s mo dd yr now)
  (setq s (vl-string-trim " \t" (cchk:datenorm raw)))
  (cond
    ((= s "") "is blank - expected MM/DD/YYYY")
    ((or (/= (strlen s) 10)
         (/= (substr s 3 1) "/")
         (/= (substr s 6 1) "/")
         (not (cchk:all-digits-p (substr s 1 2)))
         (not (cchk:all-digits-p (substr s 4 2)))
         (not (cchk:all-digits-p (substr s 7 4))))
     (strcat "'" s "' is not in MM/DD/YYYY format - expected MM/DD/YYYY"))
    (t
     (setq mo (atoi (substr s 1 2))
           dd (atoi (substr s 4 2))
           yr (atoi (substr s 7 4)))
     (cond
       ((or (< mo 1) (> mo 12))
        (strcat "'" s "' - " (substr s 1 2)
                " is not a month (01-12) - expected MM/DD/YYYY"))
       ((or (< dd 1) (> dd (cchk:days-in-month mo yr)))
        (strcat "'" s "' - " (substr s 4 2)
                " is not a valid day for that month - expected MM/DD/YYYY"))
       ((progn (setq now (cchk:today-mdy))
               (not (and (= mo (car now)) (= dd (cadr now))
                         (= yr (caddr now)))))
        (strcat "'" s "' is NOT TODAY'S DATE (" (cchk:mdy-str now)
                ") - update it"))
       (t nil)))))

;; The Tech Title block: the first INSERT whose name carries it, looked
;; for in the selection and then across the drawing, since the title
;; block sits outside the area someone highlights as often as not.
(defun cchk:find-title (ss / pat i e ed out ss2)
  (setq pat (strcat "*" (cchk:squash *cchk-title-block*) "*") i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            ed (entget e))
      (if (and (null out) ed (= "INSERT" (cdr (assoc 0 ed)))
               (wcmatch (cchk:squash (cchk:block-name e)) pat))
        (setq out e))))
  (if (null out)
    (progn
      (setq ss2 (ssget "_X" '((0 . "INSERT"))) i 0)
      (if ss2
        (repeat (sslength ss2)
          (setq e (ssname ss2 i) i (1+ i))
          (if (and (null out)
                   (wcmatch (cchk:squash (cchk:block-name e)) pat))
            (setq out e))))))
  out)

;; The verdict: (sentence . needs-attention).  With no Tech Title in
;; reach there is nothing to read, and that is said plainly rather than
;; flagged -- a cover or spa sheet may well be checked on its own.
(defun cchk:audit-date (ss / blk ed raw bad)
  (setq blk (cchk:find-title ss))
  (if (null blk)
    (cons (strcat "no '" *cchk-title-block* "' block in reach - date NOT CHECKED")
          nil)
    (progn
      (setq ed  (entget blk)
            raw (if (and (assoc 66 ed) (= 1 (cdr (assoc 66 ed))))
                  (cchk:ins-attrib blk *cchk-date-tag*))
            bad (if raw
                  (cchk:date-verdict raw)
                  (strcat "is missing from the block"
                          " - expected MM/DD/YYYY")))
      (if bad
        (cons (strcat *cchk-date-tag* " " bad) T)
        (cons (strcat *cchk-date-tag* " = '"
                      (vl-string-trim " \t" (cchk:datenorm raw)) "' - OK")
              nil)))))

;; The whole report: the cover checks on the MAIN sheet - a large
;; title, the date and version, a verdict line, the colour legend, a
;; SUMMARY dashboard, then the findings under underlined headings -
;; and the DIMCHECK-style findings (dimensions, arcs, overlapping
;; lines) in a DIMENSION AUDIT column to its right.  A lite run
;; writes the main sheet alone.
;;   title   the report's big first line ("COVERCHECK REPORT", ...)
;;   note    extra legend sentence(s) up front, or nil
;;   hdr     (text . attn) pairs for the SUMMARY dashboard
;;   dhdr    (text . attn) pairs for the dimension column's dashboard
;;   lines   every finding line, report order
;;   lite    T = skip the dimension column
;; Returns the x of the report's right edge, for the caller's zoom.
(defun cchk:write-report (title note hdr dhdr lines lite
                          minx miny maxx maxy
                          / mainl diml l pr nred nmain ndim nlin grps grp
                            ref h ins ins2 txt right)
  (cal:ensure-layer *cchk-report-layer* *cchk-report-color*)
  (foreach l lines
    (if (cchk:dimline-p l)
      (setq diml (cons l diml))
      (setq mainl (cons l mainl))))
  (setq mainl (reverse mainl)
        diml  (reverse diml))
  ;; the verdict counts every line that will render red, either column
  (setq nred 0)
  (foreach pr (append hdr dhdr)
    (if (cdr pr) (setq nred (1+ nred))))
  (foreach l lines
    (if (cchk:attn-p l) (setq nred (1+ nred))))
  ;; sizing: weighted line count per column - the head is ~4.5 lines,
  ;; a heading is a line plus its 0.4 gap - and the taller column
  ;; drives the text height, clamped as before
  (setq nmain 4.5 grps nil)
  (foreach l mainl
    (if (not (member (cchk:linegrp l) grps))
      (setq grps (cons (cchk:linegrp l) grps))))
  (setq nmain (+ nmain (* 1.4 (1+ (length grps)))))   ; SUMMARY + sections
  (setq nmain (+ nmain (* (length hdr) *cchk-green-scale*)))
  (foreach l mainl
    (setq nmain (+ nmain (if (cchk:attn-p l) 1.0 *cchk-green-scale*))))
  (setq ndim 0.0)
  (if (not lite)
    (progn
      (setq ndim 2.5 grps nil)                        ; column title + legend
      (foreach l diml
        (if (not (member (cchk:linegrp l) grps))
          (setq grps (cons (cchk:linegrp l) grps))))
      (setq ndim (+ ndim (* 1.4 (length grps))))
      (setq ndim (+ ndim (* (length dhdr) *cchk-green-scale*)))
      (foreach l diml
        (setq ndim (+ ndim (if (cchk:attn-p l) 1.0 *cchk-green-scale*))))))
  (setq nlin (max nmain ndim))
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
  ;; --- the main sheet
  (setq txt (strcat (cchk:big title)
                    "\\P"
                    (cchk:small (strcat (cal:datestr)
                                        "  -  COVERCHECK "
                                        *cchk-version*))
                    "\\P"
                    "{\\H1.2x;"
                    (if (> nred 0)
                      (cchk:red (strcat (itoa nred) " LINE"
                                        (if (= 1 nred) "" "S")
                                        " NEED"
                                        (if (= 1 nred) "S" "")
                                        " ATTENTION"))
                      "ALL CLEAR - every check passed")
                    "}"
                    "\\P"
                    (cchk:small
                      (strcat (if note note "")
                              "Lines needing attention are in "
                              (cchk:red "red")
                              " at full size; lines that checked out"
                              " are smaller."))))
  (setq txt (strcat txt "\\P" (cchk:hdg "SUMMARY")))
  (foreach pr hdr
    (setq txt (strcat txt "\\P"
                      (if (cdr pr)
                        (cchk:red (strcat "  " (car pr)))
                        (cchk:small (strcat "  " (car pr)))))))
  (setq grp nil)
  (foreach l mainl
    (if (/= grp (cchk:linegrp l))
      (setq grp (cchk:linegrp l)
            txt (strcat txt "\\P" (cchk:hdg grp))))
    (setq txt (strcat txt "\\P"
                      (if (cchk:attn-p l)
                        (cchk:red (strcat "  " l))
                        (cchk:small (strcat "  " l))))))
  (cchk:mtext ins h (* *cchk-report-chars* h) txt *cchk-report-layer*)
  (setq right (+ (car ins) (* *cchk-report-chars* h)))
  ;; --- the DIMENSION AUDIT column
  (if (not lite)
    (progn
      (setq ins2 (list (+ (car ins) (* (+ *cchk-report-chars* 2.0) h))
                       (cadr ins) 0.0)
            txt  (strcat "{\\H1.2x;DIMENSION AUDIT}"
                         "\\P"
                         (cchk:small
                           (strcat "Dimensions, arcs and overlapping"
                                   " lines - DIMCHECK's ground, kept"
                                   " off the main sheet."))))
      (foreach pr dhdr
        (setq txt (strcat txt "\\P"
                          (if (cdr pr)
                            (cchk:red (strcat "  " (car pr)))
                            (cchk:small (strcat "  " (car pr)))))))
      (setq grp nil)
      (foreach l diml
        (if (/= grp (cchk:linegrp l))
          (setq grp (cchk:linegrp l)
                txt (strcat txt "\\P" (cchk:hdg grp))))
        (setq txt (strcat txt "\\P"
                          (if (cchk:attn-p l)
                            (cchk:red (strcat "  " l))
                            (cchk:small (strcat "  " l))))))
      (cchk:mtext ins2 h (* *cchk-report-chars* h) txt *cchk-report-layer*)
      (setq right (+ (car ins2) (* *cchk-report-chars* h)))))
  right)

;; --- geometry ------------------------------------------------------

(defun cchk:planar-arc-p (ed / n)
  ;; only arcs drawn in the world XY plane are handled
  (setq n (cdr (assoc 210 ed)))
  (or (null n)
      (and (< (abs (car n)) 1e-9)
           (< (abs (cadr n)) 1e-9)
           (> (caddr n) 0.0))))

(defun cchk:rebuild-arc (ent which fixed mid target / c r a1 a2 am tmp ed pair)
  ;; re-fit the arc through its fixed end, its old midpoint and the
  ;; target point; returns T on success
  (if (and (> (distance target fixed) 1e-8)
           (setq c (cal:circumcenter fixed mid target)))
    (progn
      (setq r  (distance c target)
            a1 (angle c (if (eq which 'start) target fixed))
            a2 (angle c (if (eq which 'start) fixed target))
            am (angle c mid))
      ;; ARC entities always sweep counter-clockwise from start to
      ;; end; keep the sweep that contains the old midpoint
      (if (> (cal:angnorm (- am a1)) (cal:angnorm (- a2 a1)))
        (setq tmp a1
              a1  a2
              a2  tmp))
      (setq ed (entget ent))
      (foreach pair (list (cons 10 c) (cons 40 r) (cons 50 a1) (cons 51 a2))
        (setq ed (subst pair (assoc (car pair) ed) ed)))
      (if (entmod ed)
        (progn (entupd ent) T)))))

(defun cchk:move-arc-end (ent which target / mid other)
  ;; re-fit the arc so the chosen endpoint lands on target (WCS)
  (setq mid   (vlax-curve-getPointAtDist
                ent
                (/ (vlax-curve-getDistAtParam ent (vlax-curve-getEndParam ent)) 2.0))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent)))
  (cchk:rebuild-arc ent which other mid target))

(defun cchk:overlap-info (la lb / a1 a2 b1 b2 u lena s1 s2 tmp lo hi)
  ;; when segments la and lb are collinear (within *cchk-olap-fuzz*)
  ;; and run on top of each other for more than *cchk-tol*, returns
  ;;   (ov-start ov-end ov-length union-start union-end)
  ;; nil when they do not overlap (touching end-to-end is fine)
  (setq a1 (cchk:seg-p1 la)
        a2 (cchk:seg-p2 la)
        b1 (cchk:seg-p1 lb)
        b2 (cchk:seg-p2 lb)
        u  (cal:unitn (mapcar '- a2 a1)))
  (if (and u
           (<= (cal:pt-line-dist b1 a1 u) *cchk-olap-fuzz*)
           (<= (cal:pt-line-dist b2 a1 u) *cchk-olap-fuzz*))
    (progn
      (setq lena (distance a1 a2)
            s1   (cal:proj-param b1 a1 u)
            s2   (cal:proj-param b2 a1 u))
      (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
      (setq lo (max 0.0 s1)
            hi (min lena s2))
      (if (> (- hi lo) *cchk-tol*)
        (list (cal:axis-pt a1 u lo)
              (cal:axis-pt a1 u hi)
              (- hi lo)
              (cal:axis-pt a1 u (min 0.0 s1))
              (cal:axis-pt a1 u (max lena s2)))))))

(defun cchk:merge-lines (la lb info / ed)
  ;; stretch la's LINE over the union of both, delete lb's LINE
  (setq ed (entget (cchk:seg-ent la))
        ed (subst (cons 10 (nth 3 info)) (assoc 10 ed) ed)
        ed (subst (cons 11 (nth 4 info)) (assoc 11 ed) ed))
  (entmod ed)
  (entupd (cchk:seg-ent la))
  (entdel (cchk:seg-ent lb)))

(defun cchk:whole-line-p (s / ed)
  ;; T when the segment IS its owner entity - only whole LINEs can be
  ;; merged; a polyline edge has to be fixed by hand
  (setq ed (entget (cchk:seg-ent s)))
  (= "LINE" (cdr (assoc 0 ed))))

(defun cchk:find-overlaps (segs / atol fams a placed fam recs e p1 p2 dx dy
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
    (setq a      (cchk:seg-dir-ang e)
          placed nil)
    (foreach fam fams
      (if (and (not placed)
               (or (<= (cal:ang-diff a (car fam)) atol)))
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
          (setq p1  (cchk:seg-p1 e)
                p2  (cchk:seg-p2 e)
                off (- (* (cadr p1) dx) (* (car p1) dy))
                s1  (+ (* (car p1) dx) (* (cadr p1) dy))
                s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
          (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
          (setq recs (cons (list off s1 s2 e) recs)))
        (setq recs (cchk:sort-recs recs))
        ;; sorted by offset: only sweep forward while still collinear
        (while recs
          (setq r    (car recs)
                rest (cdr recs))
          (while (and rest
                      (<= (- (car (car rest)) (car r)) *cchk-olap-fuzz*))
            (setq q (car rest))
            (if (and (not (eq (cchk:seg-ent (cadddr r))
                              (cchk:seg-ent (cadddr q))))
                     ;; spans must actually meet before the exact test
                     (> (min (caddr r) (caddr q)) (max (cadr r) (cadr q)))
                     (cchk:overlap-info (cadddr r) (cadddr q)))
              (progn
                (setq key (list (cchk:seg-ent (cadddr r))
                                (cchk:seg-ent (cadddr q))))
                (if (not (member key seen))
                  (setq seen  (cons key (cons (reverse key) seen))
                        pairs (cons (list (cadddr r) (cadddr q)) pairs)))))
            (setq rest (cdr rest)))
          (setq recs (cdr recs))))))
  (reverse pairs))

;; --- segments: lines AND polyline edges ----------------------------
;; Detection works on "segs" - (start end owner-entity) records - so a
;; run of edges drawn as one polyline counts exactly like the same
;; shape drawn as separate LINEs.

(defun cchk:seg-p1 (s) (car s))
(defun cchk:seg-p2 (s) (cadr s))
(defun cchk:seg-ent (s) (caddr s))

(defun cchk:ocs->wcs (p nz)
  (if (and nz (not (equal nz '(0.0 0.0 1.0) 1e-9))) (trans p nz 0) p))

(defun cchk:lwpoly-segs (ent / ed nz elev vs bl cls n i segs g)
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
       (setq vs (cons (cchk:ocs->wcs (list (car (cdr g)) (cadr (cdr g)) elev) nz) vs)
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

(defun cchk:heavy-poly-segs (ent / e ed vs bl cls n i segs)
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

(defun cchk:ent-segs (ent / ed et)
  ;; every straight segment an entity contributes, in WCS
  (setq ed (entget ent)
        et (cdr (assoc 0 ed)))
  (cond
    ((= et "LINE")       (list (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)) ent)))
    ((= et "LWPOLYLINE") (cchk:lwpoly-segs ent))
    ((= et "POLYLINE")   (cchk:heavy-poly-segs ent))))

(defun cchk:collect-segs (ents / segs e s)
  ;; all straight segments of a list of entities, longer than the
  ;; attachment tolerance (zero-length stubs help nothing)
  (foreach e ents
    (if (entget e)
      (foreach s (cchk:ent-segs e)
        (if (> (distance (car s) (cadr s)) *cchk-tol*)
          (setq segs (cons s segs))))))
  (reverse segs))

(defun cchk:seg-dir-ang (s / a)
  ;; segment direction folded into [0, pi)
  (setq a (angle (cchk:seg-p1 s) (cchk:seg-p2 s)))
  (if (>= a pi) (- a pi) a))

(defun cchk:sort-recs (recs / out r pre rest)
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

;; --- block & text helpers ------------------------------------------

(defun cchk:norm-text (s)
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

(defun cchk:block-name (ent / res)
  ;; effective block name (sees through dynamic blocks)
  (setq res (vl-catch-all-apply
              'vla-get-EffectiveName
              (list (vlax-ename->vla-object ent))))
  (if (vl-catch-all-error-p res)
    (cdr (assoc 2 (entget ent)))
    res))

(defun cchk:blockdef-texts (bname depth / lst e et g)
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
                 lst (append (cchk:blockdef-texts (cdr (assoc 2 (entget e)))
                                                  (1- depth))
                             lst))))
        (setq e (entnext e)))))
  lst)

(defun cchk:ins-texts (ent / ed lst e)
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
  (append lst (cchk:blockdef-texts (cdr (assoc 2 ed)) *cchk-block-depth*)))

(defun cchk:block-has-layer-p (bname layer depth / e et found)
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
          (if (cchk:block-has-layer-p (cdr (assoc 2 (entget e))) layer (1- depth))
            (setq found T)))
        (setq e (entnext e)))))
  found)

(defun cchk:ins-matches (ent phrase / pat found s)
  ;; T when the INSERT's (effective) name or any text it shows
  ;; contains the phrase, ignoring case and punctuation
  (setq pat   (strcat "*" (cchk:norm-text phrase) "*")
        found (wcmatch (cchk:norm-text (cchk:block-name ent)) pat))
  (foreach s (cchk:ins-texts ent)
    (if (wcmatch (cchk:norm-text s) pat)
      (setq found T)))
  found)

(defun cchk:clip (s n)
  (if (> (strlen s) n) (strcat (substr s 1 n) "...") s))

(defun cchk:join (lst sep / out s)
  ;; "A" + "B" + ... joined with sep
  (foreach s lst
    (setq out (if out (strcat out sep s) s)))
  out)

(defun cchk:squash (s)
  ;; norm-text with the spaces removed too, so "Cover Material" finds
  ;; a block that is actually named "CoverMaterial"
  (vl-list->string (vl-remove 32 (vl-string->list (cchk:norm-text s)))))

(defun cchk:ins-attrib (ent tag / e ed val)
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

(defun cchk:parse-num (s / p num den)
  ;; "4", "4.5", "1/2" -> real
  (setq p (vl-string-search "/" s))
  (if p
    (progn
      (setq num (atof (substr s 1 p))
            den (atof (substr s (+ p 2))))
      (if (> den 0.0) (/ num den) 0.0))
    (atof s)))

(defun cchk:after-eq (s / p)
  ;; the part after the last "=", so a label never contributes its
  ;; own digits: "Finished Wall Ht = 40''" -> " 40''"
  (while (setq p (vl-string-search "=" s))
    (setq s (substr s (+ p 2))))
  s)

(defun cchk:len-values (s / lst i n c numstr toks unit vals cur tok)
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
  (setq s    (cchk:after-eq s)
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
        (setq toks (append toks (list (cons (cchk:parse-num numstr) unit)))))
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

(defun cchk:parse-len (s)
  ;; the first length written in the text, in inches; nil when none
  (car (cchk:len-values s)))

;; --- dimension review ----------------------------------------------

(defun cchk:dim-style (ent / s)
  ;; the dimension's style name, "" when it has none
  (setq s (cdr (assoc 3 (entget ent))))
  (if s s ""))

(defun cchk:style-rank (style / i r s)
  ;; position of the style in *cchk-style-order* (exact name match,
  ;; case-blind); unlisted styles land after every listed one
  (setq style (strcase style)
        i     0
        r     nil)
  (foreach s *cchk-style-order*
    (if (and (null r) (= (strcase s) style)) (setq r i))
    (setq i (1+ i)))
  (if r r (length *cchk-style-order*)))

(defun cchk:ent-center (ent / bb)
  ;; (x y) centre of the entity's box; falls back to its group-10 point
  (setq bb (cal:bbox-ent ent))
  (if bb
    (list (* 0.5 (+ (caar bb) (caadr bb)))
          (* 0.5 (+ (cadar bb) (cadadr bb))))
    (progn
      (setq bb (cdr (assoc 10 (entget ent))))
      (if bb (list (car bb) (cadr bb)) (list 0.0 0.0)))))

(defun cchk:dim-order-p (r1 r2 rowtol)
  ;; strict "r1 reviews before r2" for recs (rank cx cy ent):
  ;; style rank first, then row (higher = earlier), then left first
  (cond
    ((< (car r1) (car r2)) T)
    ((> (car r1) (car r2)) nil)
    ((> (- (caddr r1) (caddr r2)) rowtol) T)   ; r1 sits a row above
    ((> (- (caddr r2) (caddr r1)) rowtol) nil) ; r2 sits a row above
    (t (< (cadr r1) (cadr r2)))))              ; same row: left first

(defun cchk:sort-dims (dims rowtol / recs cen r out pre rest e)
  ;; stable insertion sort into review order
  (setq recs nil)
  (foreach e dims
    (setq cen  (cchk:ent-center e)
          recs (cons (list (cchk:style-rank (cchk:dim-style e))
                           (car cen) (cadr cen) e)
                     recs)))
  (setq recs (reverse recs)
        out  nil)
  (foreach r recs
    (setq pre  nil
          rest out)
    (while (and rest (not (cchk:dim-order-p r (car rest) rowtol)))
      (setq pre  (cons (car rest) pre)
            rest (cdr rest)))
    (setq out (append (reverse pre) (list r) rest)))
  (mapcar '(lambda (r) (nth 3 r)) out))

(defun cchk:dim-meas (ent / ed dtype p13 p14 ang v meas)
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

(defun cchk:dim-def-pts (ent / ed dtype p13 p14)
  ;; the two definition points of a linear/aligned dimension (the ones
  ;; the audit moves); nil for every other kind of dimension
  (setq ed    (entget ent)
        dtype (logand 7 (cdr (assoc 70 ed))))
  (if (member dtype '(0 1))
    (progn
      (setq p13 (cdr (assoc 13 ed))
            p14 (cdr (assoc 14 ed)))
      (append (if p13 (list p13)) (if p14 (list p14))))))

(defun cchk:shared-anchors (dims / recs r e p found out)
  ;; Every spot where *cchk-anchor-min* or more DIMENSIONS put a
  ;; definition point.  Dimensioning twice to the same spot is how a
  ;; drafter says that spot matters -- the usual case is the pair of
  ;; dims that pin down a hypotenuse corner, which is a point in space
  ;; with no line running through it.  Such a spot counts as an
  ;; object: it is never questioned, and a stray point beside it can
  ;; be offered a move onto it.
  ;; Collected once, from the drawing as selected, so a point cannot
  ;; stop being an anchor partway through the review.
  ;; Returns the anchor points (WCS).
  (foreach e dims
    (foreach p (cchk:dim-def-pts e)
      (setq found nil)
      (foreach r recs
        (if (and (null found) (<= (distance p (car r)) *cchk-anchor-tol*))
          (setq found r)))
      (cond
        ((null found) (setq recs (cons (list p e) recs)))
        ;; a dimension's own two points landing together is one
        ;; dimension, not two -- it takes two to make an anchor
        ((not (member e (cdr found)))
         (setq recs (subst (cons (car found) (cons e (cdr found)))
                           found recs))))))
  (foreach r recs
    (if (>= (length (cdr r)) *cchk-anchor-min*)
      (setq out (cons (car r) out))))
  out)

(defun cchk:audit-dim-point (ent gcode label cands anchors
                             / ed pt near anch dnear danch sugg dsug what
                               ans final how)
  ;; audits one definition point: an off-object point is put where it
  ;; looks like it belongs, then you choose - Move (take it), Keep
  ;; (put it back exactly where you drew it) or Pick your own spot.
  ;; A point another dimension also measures to is an ANCHOR (see
  ;; cchk:shared-anchors): it counts as an object, so it is left alone
  ;; without a question, and a stray point nearer an anchor than any
  ;; line is offered the anchor instead of being dragged off to the
  ;; line.
  ;; Returns (original final how) when the point was looked at, where
  ;; how is 'auto / 'user / 'kept / 'anchor; nil when the point was
  ;; already fine.
  (setq ed (entget ent)
        pt (cdr (assoc gcode ed)))
  (if pt
    (progn
      (setq near  (cchk:nearest-curve pt nil cands)
            dnear (if near (caddr near))
            anch  (cchk:closest-of pt anchors)
            danch (if anch (distance pt anch)))
      (cond
        ;; a point sitting on an object needs no defending, shared or not
        ((and dnear (<= dnear *cchk-tol*)) nil)
        ;; ...and one that isn't is still fine if another dimension
        ;; measures to it too: that spot is settled, whether or not any
        ;; geometry runs through it
        ((and danch (<= danch *cchk-anchor-tol*))
         (princ (strcat "\n  " label " is shared with another dimension"
                        " - treated as an anchor point, left as drawn."))
         (list pt pt 'anchor))
        (t
         ;; otherwise the nearer of the two homes it could have: a line
         ;; to sit on, or an anchor it was very nearly snapped to
         (cond
           ((and danch (or (null dnear) (< danch dnear)))
            (setq sugg anch  dsug danch  what "the shared anchor point"))
           (near
            (setq sugg (cadr near)  dsug dnear  what "the nearest object")))
         (if (and sugg (> dsug *cchk-tol*))
           (progn
             ;; show the suggestion in place, but keep the original spot
             ;; marked so both are on screen while the question is asked
             (entmod (subst (cons gcode sugg) (assoc gcode ed) ed))
             (entupd ent)
             (princ (strcat "\n  " label " is not on any object - " what
                            " is " (rtos dsug 2 4) " away."))
             (setq ans (cchk:confirm-move label pt sugg what))
             (cond
               ((eq ans 'move)
                (setq final sugg
                      how   'auto)
                (princ (strcat "\n  " label " MOVED onto " what ", "
                               (cchk:ptstr final) ".")))
               ((eq ans 'keep)
                (setq ed    (entget ent)
                      final pt
                      how   'kept)
                (entmod (subst (cons gcode pt) (assoc gcode ed) ed))
                (entupd ent)
                (princ (strcat "\n  " label " KEPT where you drew it, "
                               (cchk:ptstr final) " - nothing changed.")))
               (t
                (setq final (trans ans 1 0)
                      how   'user
                      ed    (entget ent))
                (entmod (subst (cons gcode final) (assoc gcode ed) ed))
                (entupd ent)
                (princ (strcat "\n  " label " moved to the spot you picked, "
                               (cchk:ptstr final) "."))))
             (redraw)
             (list pt final how))))))))

(defun cchk:review-dim (ent cands anchors num total / ed dtype h sty p13 p14
                                              r1 r2 looked moved kept held
                                              ok note meas assocnote)
  ;; interactive review of one dimension.
  ;; Returns (handle ok-flag report-note moved-point-count measurement
  ;; anchor-held-point-count).
  (setq ed    (entget ent)
        h     (cdr (assoc 5 ed))
        sty   (cchk:dim-style ent)
        dtype (logand 7 (cdr (assoc 70 ed))))
  (cchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nDimension " (itoa num) " of " (itoa total)
                 " (handle " h
                 (if (= sty "") "" (strcat ", style " sty))
                 ")"))
  (if (member dtype '(0 1))                   ; rotated/linear or aligned
    (progn
      (if (cchk:dim-assoc-p ent)
        (princ "\n  Note: this dimension is object-associative - a moved point may re-anchor on its own."))
      (setq p13 (cdr (assoc 13 ed))           ; the two dimmed points
            p14 (cdr (assoc 14 ed))
            r1  (cchk:audit-dim-point ent 13 "dimension point 1" cands anchors)
            r2  (cchk:audit-dim-point ent 14 "dimension point 2" cands anchors))))
  ;; a point held at a shared anchor was looked at and deliberately not
  ;; touched - it is neither a move nor a Keep answer, so it is counted
  ;; on its own and kept out of both tallies
  (setq looked (append (if r1 (list r1)) (if r2 (list r2)))
        held   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'anchor)) looked)
        moved  (vl-remove-if '(lambda (x) (member (caddr x) '(kept anchor)))
                             looked)
        kept   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'kept)) looked))
  ;; only when something actually moved is there an old position worth
  ;; drawing a construction line through
  (if moved (cchk:make-xline p13 p14))        ; through the ORIGINAL points
  (if (and moved (cchk:dim-assoc-p ent))
    (setq assocnote " (ASSOCIATIVE - verify the moved point holds)"))
  (setq meas (cchk:dim-meas ent))             ; after any point moves
  (if meas (princ (strcat "\n  Measures " meas ".")))
  (redraw ent 3)
  (setq ok (cal:ask-yn-nav "\n  Is this dimension correct?"))
  (redraw ent 4)
  (redraw)
  (if (member ok '(back skip))
    (list h ok nil (length moved) meas (length held))  ; navigation: caller handles it
    (progn
      (setq ok (eq ok 'yes))
      (setq note (strcat
                   (if ok "OK" "FLAGGED to fix (red)")
                   (if moved
                     (strcat " - " (itoa (length moved))
                             " point(s) moved onto the nearest object/anchor")
                     "")
                   (if kept
                     (strcat " - " (itoa (length kept))
                             " point(s) kept where you drew them")
                     "")
                   (if held
                     (strcat " - " (itoa (length held))
                             " point(s) held at a shared anchor")
                     "")
                   (if assocnote assocnote "")))
      (if (not ok) (cchk:set-color ent *cchk-flag-color*))
      (list h ok note (length moved) meas (length held)))))

;; --- arc review ----------------------------------------------------

(defun cchk:arc-end-target (ent which cands / p other near ends target)
  ;; where the attachment audit says this endpoint should go;
  ;; nil when the endpoint is already fine (or nothing to attach to)
  (setq p     (if (eq which 'start)
                (vlax-curve-getStartPoint ent)
                (vlax-curve-getEndPoint ent))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent))
        near  (cchk:nearest-curve p ent cands))
  (cond
    ((null near) nil)                         ; nothing to attach to at all
    ((<= (caddr near) *cchk-tol*)             ; endpoint sits on an object...
     (setq ends (cchk:curve-ends (car near)))
     ;; never snap onto the arc's own other endpoint
     (setq ends (vl-remove-if '(lambda (q) (< (distance q other) 1e-8)) ends))
     (cond
       ((null ends) nil)                      ; closed curve: no ends to demand
       ((vl-some '(lambda (q) (<= (distance p q) *cchk-tol*)) ends)
        nil)                                  ; ...and at one of its ends: OK
       (t (cchk:closest-of p ends))))         ; ...but mid-object: closest end
    (t                                        ; floating: closest end anywhere,
     (setq target (cchk:nearest-end p ent cands))
     (if (or (null target) (< (distance target other) 1e-8))
       (cadr near)                            ; else closest point on closest object
       target))))

(defun cchk:arc-state (ent / ed)
  ;; the groups that define an arc's shape, for an exact put-it-back
  (setq ed (entget ent))
  (list (assoc 10 ed) (assoc 40 ed) (assoc 50 ed) (assoc 51 ed)))

(defun cchk:arc-restore (ent st / ed g)
  ;; restore a saved shape exactly, rather than re-fitting back to it
  (setq ed (entget ent))
  (foreach g st (setq ed (subst g (assoc (car g) ed) ed)))
  (entmod ed)
  (entupd ent))

(defun cchk:review-arc-end (ent which label cands / p target st ans final how)
  ;; audits one arc endpoint: a detached end is snapped where it looks
  ;; like it belongs, then you choose - Move (take it), Keep (put the
  ;; arc back exactly as drawn) or Pick your own spot.
  ;; Returns (original final how) when the end was looked at, where how
  ;; is 'auto / 'user / 'kept; nil when the end was already fine.
  (setq p      (if (eq which 'start)
                 (vlax-curve-getStartPoint ent)
                 (vlax-curve-getEndPoint ent))
        target (cchk:arc-end-target ent which cands)
        st     (cchk:arc-state ent))
  (cond
    (target
     (if (cchk:move-arc-end ent which target)
       (progn
         (princ (strcat "\n  " label " is not attached to an object end - nearest is "
                        (rtos (distance p target) 2 4) " away."))
         (setq ans (cchk:confirm-move label p target "the object end"))
         (cond
           ((eq ans 'move)
            (setq final target
                  how   'auto)
            (princ (strcat "\n  " label " SNAPPED to the object end, "
                           (cchk:ptstr final) ".")))
           ((eq ans 'keep)
            (cchk:arc-restore ent st)
            (setq final p
                  how   'kept)
            (princ (strcat "\n  " label " KEPT where you drew it, "
                           (cchk:ptstr final) " - the arc is unchanged.")))
           (t
            (setq ans (trans ans 1 0))
            (if (cchk:move-arc-end ent which ans)
              (progn
                (setq final ans
                      how   'user)
                (princ (strcat "\n  " label " moved to the spot you picked, "
                               (cchk:ptstr final) ".")))
              (progn
                (setq final target
                      how   'auto)
                (princ "\n  Could not re-fit the arc through that spot (collinear?); left it on the object end.")))))
         (redraw)
         (list p final how))
       (progn
         (princ (strcat "\n  " label " should attach at " (cchk:ptstr target)
                        " but the arc could not be re-fitted (points collinear?)."))
         nil)))
    (*cchk-ask-all-arc-ends*                  ; optional: confirm attached ends too
     (setq ans (cchk:confirm-move label p p "where it already is"))
     (redraw)
     (if (member ans '(move keep))
       nil
       (progn
         (setq ans (trans ans 1 0))
         (if (cchk:move-arc-end ent which ans)
           (list p ans 'user)
           (progn
             (princ "\n  Could not re-fit the arc through that spot (collinear?); unchanged.")
             nil)))))
    (t nil)))

(defun cchk:review-arc (ent cands num total / ed h planar r1 r2 looked moved kept note)
  ;; interactive review of one arc's endpoints.
  ;; Returns (handle untouched-flag report-note moved-point-count).
  (setq ed     (entget ent)
        h      (cdr (assoc 5 ed))
        planar (cchk:planar-arc-p ed))
  (cchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nArc " (itoa num) " of " (itoa total)
                 " (handle " h ")"))
  (if planar
    (setq r1 (cchk:review-arc-end ent 'start "arc start point" cands)
          r2 (cchk:review-arc-end ent 'end   "arc end point"   cands))
    (princ "\n  Arc is not in the world XY plane - endpoint audit skipped."))
  (redraw ent 4)
  (redraw)
  (setq looked (append (if r1 (list r1)) (if r2 (list r2)))
        moved  (vl-remove-if '(lambda (x) (eq (caddr x) 'kept)) looked)
        kept   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'kept)) looked))
  (if moved (cchk:set-color ent *cchk-arc-color*))
  (setq note (cond
               ((not planar) "not in world XY plane - skipped")
               ((and moved kept)
                (strcat (itoa (length moved)) " endpoint(s) moved (magenta), "
                        (itoa (length kept)) " kept where you drew them"))
               (moved (strcat (itoa (length moved))
                              " endpoint(s) moved (magenta)"))
               (kept (strcat (itoa (length kept))
                             " endpoint(s) kept where you drew them"))
               (t "endpoints OK")))
  (list h (null moved) note (length moved)))

;; --- overlapping line review ---------------------------------------

(defun cchk:review-olap (la lb num total / info ea eb h1 h2 lay1 lay2 label
                                           ans mergeable kinds)
  ;; interactive review of one overlapping segment pair.
  ;; Returns nil when the pair no longer overlaps (an earlier merge
  ;; absorbed it); otherwise (label report-note action ents...) where
  ;; action is merged / flagged / left and ents keep their cyan.
  (setq ea (cchk:seg-ent la)
        eb (cchk:seg-ent lb))
  (if (and (entget ea) (entget eb) (setq info (cchk:overlap-info la lb)))
    (progn
      (setq h1        (cdr (assoc 5 (entget ea)))
            h2        (cdr (assoc 5 (entget eb)))
            lay1      (cdr (assoc 8 (entget ea)))
            lay2      (cdr (assoc 8 (entget eb)))
            mergeable (and (cchk:whole-line-p la)
                           (cchk:whole-line-p lb)
                           (= (strcase lay1) (strcase lay2)))
            kinds     (if (and (cchk:whole-line-p la) (cchk:whole-line-p lb))
                        "lines"
                        "segments")
            label     (strcat h1 "+" h2 " (overlap " (rtos (caddr info)) ")"))
      (cchk:zoom-2ents ea eb)
      (redraw ea 3)
      (redraw eb 3)
      (cchk:mark-point (car info))
      (cchk:mark-point (cadr info))
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
         (cchk:merge-lines la lb info)
         (cchk:set-color ea *cchk-olap-color*)
         (princ "\n  Merged into one line (cyan).")
         (list label "merged into one line (cyan)" 'merged ea))
        ((= ans "Flag")
         (cchk:set-color ea *cchk-olap-color*)
         (cchk:set-color eb *cchk-olap-color*)
         (princ "\n  Flagged to fix (cyan).")
         (list label
               (if (cchk:whole-line-p la)
                 (if (= (strcase lay1) (strcase lay2))
                   "flagged to fix (cyan)"
                   "different layers - flagged to fix (cyan)")
                 "polyline edge - flagged to fix (cyan)")
               'flagged ea eb))
        (t
         (princ "\n  Left as drawn.")
         (list label "left as drawn" 'left))))))


;; --- pad geometry (ported from PADDLE.lsp v1.2) ---------------------
;; Keep in step with PADDLE whenever its pad rules change.
;; Bulge-aware outline handling and the concave-feature hunt, used to
;; measure the pool outline and suggest 36" pads along it. Accepts a
;; closed LWPOLYLINE / 2D POLYLINE or the same shape exploded into
;; loose LINEs and ARCs - touching segments (ends within
;; *cchk-chain-fuzz*) are chained back into closed loops.

(defun cchk:pv-dir (a) (list (cos a) (sin a))) ; unit vector at angle a
(defun cchk:pv-arcpt (cen r ang) (cal:v+ cen (cal:v* (cchk:pv-dir ang) r)))
(defun cchk:pv-cheb (v) (max (abs (car v)) (abs (cadr v)))) ; Chebyshev norm

;; Segment data for vertex A -> B with bulge b (b /= 0):
;; returns (theta radius center start-tangent end-tangent)
;; theta = signed included angle (CCW positive), tangents are angles.
(defun cchk:pv-arcdata (a b blg / theta chord r phi ts cen)
  (setq theta (* 4.0 (atan blg))
        chord (distance a b)
        r     (/ chord (* 2.0 (sin (/ (abs theta) 2.0))))
        phi   (angle a b)
        ts    (- phi (/ theta 2.0))
        cen   (cal:v+ a (cal:v* (cchk:pv-dir (+ ts (if (> blg 0.0) (/ pi 2.0) (/ pi -2.0)))) r)))
  (list theta r cen ts (+ phi (/ theta 2.0))))

;; Signed area of a closed vertex list (shoelace + circular segments).
;; vts = list of (x y bulge), bulge belongs to the segment leaving it.
(defun cchk:pv-area (vts / n i a b blg area theta r seg)
  (setq n (length vts) i 0 area 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq area (+ area (* 0.5 (- (* (car a) (cadr b)) (* (car b) (cadr a))))))
    (if (/= blg 0.0)
        (progn
          (setq seg   (cchk:pv-arcdata a b blg)
                theta (abs (car seg))
                r     (cadr seg))
          (setq area (+ area (* (if (> blg 0.0) 1.0 -1.0)
                                0.5 r r (- theta (sin theta)))))))
    (setq i (1+ i)))
  area)

;; Next pad along an arc: starting from arc-parameter CUR (previous
;; pad center PREV), find the parameter where the pad center is
;; exactly PADSIZE away from PREV in Chebyshev distance -- axis-
;; aligned pads of that size then touch edge-to-edge without ever
;; overlapping. Returns (parameter center), or nil when the rest of
;; the arc is too short for another flush pad.
(defun cchk:pv-next-flush (cen r sa sgn cur sweep prev padsize
                           / ds d p hit lo hi mid)
  (setq ds (/ padsize r 8.0))                ; ~1/8 pad per probe step
  (if (> ds (/ sweep 4.0)) (setq ds (/ sweep 4.0)))
  (setq d cur hit nil)
  (while (and (not hit) (< d (- sweep 1e-9))) ; walk until pads separate
    (setq lo d
          d  (min sweep (+ d ds))
          p  (cchk:pv-arcpt cen r (+ sa (* sgn d))))
    (if (>= (cchk:pv-cheb (cal:v- p prev)) padsize)
        (setq hit T)))
  (if hit
      (progn ; tighten the crossing between lo and d by bisection
        (setq hi d)
        (repeat 45
          (setq mid (/ (+ lo hi) 2.0)
                p   (cchk:pv-arcpt cen r (+ sa (* sgn mid))))
          (if (>= (cchk:pv-cheb (cal:v- p prev)) padsize)
              (setq hi mid)
              (setq lo mid)))
        (list hi (cchk:pv-arcpt cen r (+ sa (* sgn hi)))))))

;; Pad centers for one concave arc: the first pad is centered on the
;; MIDDLE of the arc; further pads march outward toward both ends,
;; each exactly one pad-size on center from the last. Marching stops
;; when the leftover end of the arc is too short for another flush
;; pad - the extreme ends of the radius are allowed to stay uncovered.
(defun cchk:pv-arc-pads (cen r sa sgn sweep padsize
                         / mid amid pmid fwd bwd cur prev nxt)
  (setq mid  (/ sweep 2.0)
        amid (+ sa (* sgn mid))
        pmid (cchk:pv-arcpt cen r amid))
  ;; march from the middle toward the arc's end...
  (setq cur 0.0 prev pmid fwd nil)
  (while (setq nxt (cchk:pv-next-flush cen r amid sgn cur (- sweep mid) prev padsize))
    (setq cur (car nxt) prev (cadr nxt) fwd (cons prev fwd)))
  ;; ...and from the middle back toward the arc's start
  (setq cur 0.0 prev pmid bwd nil)
  (while (setq nxt (cchk:pv-next-flush cen r amid (- sgn) cur mid prev padsize))
    (setq cur (car nxt) prev (cadr nxt) bwd (cons prev bwd)))
  (append bwd (list pmid) (reverse fwd)))

;; Direction (unit vector) of travel at the START / END of segment a->b.
(defun cchk:pv-tan-start (a b blg)
  (if (= blg 0.0)
      (cal:unit (cal:v- b a))
      (cchk:pv-dir (cadddr (cchk:pv-arcdata a b blg)))))
(defun cchk:pv-tan-end (a b blg)
  (if (= blg 0.0)
      (cal:unit (cal:v- b a))
      (cchk:pv-dir (last (cchk:pv-arcdata a b blg)))))

;; LWPOLYLINE -> (closed-flag . vts)
(defun cchk:pv-lwverts (ent / ed out grp)
  (setq ed (entget ent))
  (foreach grp ed
    (cond
      ((= (car grp) 10)
       (setq out (cons (list (cadr grp) (caddr grp) 0.0) out)))
      ((= (car grp) 42)
       (if out (setq out (cons (list (caar out) (cadr (car out)) (cdr grp)) (cdr out)))))))
  (cons (= 1 (logand 1 (cdr (assoc 70 ed)))) (reverse out)))

;; heavy 2D POLYLINE -> (closed-flag . vts), nil for 3D/mesh plines
(defun cchk:pv-plverts (ent / ed flags e ved out p)
  (setq ed (entget ent) flags (cdr (assoc 70 ed)))
  (if (zerop (logand 112 flags)) ; skip 3D polylines / meshes / polyfaces
      (progn
        (setq e (entnext ent))
        (while (and e (= "VERTEX" (cdr (assoc 0 (setq ved (entget e))))))
          (if (zerop (logand 16 (cond ((cdr (assoc 70 ved))) (0)))) ; skip spline frame pts
              (progn
                (setq p (cdr (assoc 10 ved)))
                (setq out (cons (list (car p) (cadr p)
                                      (cond ((cdr (assoc 42 ved))) (0.0)))
                                out))))
          (setq e (entnext e)))
        (cons (= 1 (logand 1 flags)) (reverse out)))))

;; vertex list -> segments (p1 p2 bulge), wrapping when closed
(defun cchk:pv-vts->segs (closed vts / n i segs a b)
  (setq n (length vts) i 0)
  (repeat (if closed n (max 0 (1- n)))
    (setq a (nth i vts)
          b (nth (rem (1+ i) n) vts))
    (setq segs (cons (list (cal:2d a) (cal:2d b) (caddr a)) segs))
    (setq i (1+ i)))
  (reverse segs))

;; any supported entity -> list of bulge-aware segments
(defun cchk:pv-ent-segs (ent / ed typ cen r sa ea sweep cv)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (cal:2d (cdr (assoc 10 ed)))
                 (cal:2d (cdr (assoc 11 ed))) 0.0)))
    ((= typ "ARC")
     (setq cen   (cal:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           sa    (cdr (assoc 50 ed))
           ea    (cdr (assoc 51 ed))
           sweep (- ea sa))
     (if (<= sweep 0.0) (setq sweep (+ sweep pi pi)))
     (list (list (cal:v+ cen (cal:v* (cchk:pv-dir sa) r))
                 (cal:v+ cen (cal:v* (cchk:pv-dir ea) r))
                 (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0)))))) ; tan(sweep/4)
    ((= typ "CIRCLE")
     ;; two flush half-circle arcs (east point -> west point -> east
     ;; point, both CCW) chain into the same closed loop a polyline
     ;; circle would, without any extra vertex-list plumbing
     (setq cen (cal:2d (cdr (assoc 10 ed)))
           r   (cdr (assoc 40 ed)))
     (list (list (cal:v+ cen (list r 0.0)) (cal:v+ cen (list (- r) 0.0)) 1.0)
           (list (cal:v+ cen (list (- r) 0.0)) (cal:v+ cen (list r 0.0)) 1.0)))
    ((= typ "LWPOLYLINE")
     (setq cv (cchk:pv-lwverts ent))
     (cchk:pv-vts->segs (car cv) (cdr cv)))
    ((= typ "POLYLINE")
     (setq cv (cchk:pv-plverts ent))
     (if cv (cchk:pv-vts->segs (car cv) (cdr cv))))))

;; Chains touching segments (ends within *cchk-chain-fuzz*) end-to-end.
;; Returns (loops . open-count); each loop is a vertex list (x y bulge).
(defun cchk:pv-chain (segs / loops nopen chain head tail done found rest s)
  (setq nopen 0)
  ;; drop degenerate slivers
  (setq segs (vl-remove-if
               '(lambda (s) (<= (distance (car s) (cadr s)) *cchk-chain-fuzz*))
               segs))
  (while segs
    (setq chain (list (car segs))
          head  (car (car segs))
          tail  (cadr (car segs))
          segs  (cdr segs)
          done  nil)
    (while (not done)
      (cond
        ;; loop closed back onto its start?
        ((and (> (length chain) 1) (<= (distance tail head) *cchk-chain-fuzz*))
         (setq loops (cons (mapcar '(lambda (s) (list (car (car s)) (cadr (car s)) (caddr s)))
                                   chain)
                           loops)
               done  T))
        (T ;; look for a segment continuing from the tail
         (setq found nil rest nil)
         (foreach s segs
           (if found
               (setq rest (cons s rest))
               (cond
                 ((<= (distance tail (car s)) *cchk-chain-fuzz*)
                  (setq found s))
                 ((<= (distance tail (cadr s)) *cchk-chain-fuzz*) ; reversed
                  (setq found (list (cadr s) (car s) (- (caddr s)))))
                 (T (setq rest (cons s rest))))))
         (if found
             (setq chain (append chain (list found))
                   tail  (cadr found)
                   segs  (reverse rest))
             (setq nopen (1+ nopen) done T)))))) ; dead end: open chain
  (cons (reverse loops) nopen))

;; Concave features of one closed loop: returns pads, each
;; (center rotation kind) with kind = "corner" / "arc". PADSIZE sets
;; the pad-grid pitch used to cover concave arcs.
(defun cchk:pv-features (vts padsize / s n i a b c blg pads din dout turn
                             seg theta r cen sa sgn sweep)
  (setq s (if (< (cchk:pv-area vts) 0.0) -1 1) ; -1 = clockwise
        n (length vts)
        i 0)
  (repeat n
    (setq a   (nth i vts)                     ; segment i : a -> b
          b   (nth (rem (1+ i) n) vts)
          c   (nth (rem (+ i (1- n)) n) vts)  ; previous vertex
          blg (caddr a))
    ;; --- concave vertex (inside corner) at a, between seg i-1 and i ---
    (setq din  (cchk:pv-tan-end (cal:2d c) (cal:2d a) (caddr c))
          dout (cchk:pv-tan-start (cal:2d a) (cal:2d b) blg))
    (if (and din dout)
        (progn
          (setq turn (atan (cal:cross din dout) (cal:dot din dout)))
          (if (< (* s turn) (- *cchk-pad-angtol*)) ; turns away from interior
              (setq pads (cons (list (cal:2d a) (angle '(0.0 0.0) din) "corner")
                               pads)))))
    ;; --- concave arc segment with radius <= *cchk-pad-maxrad* ---
    (if (and (/= blg 0.0)
             (< (* s blg) 0.0)) ; bulges into the interior
        (progn
          (setq seg   (cchk:pv-arcdata (cal:2d a) (cal:2d b) blg)
                theta (car seg)
                r     (cadr seg)
                cen   (caddr seg))
          (if (and (<= r (+ *cchk-pad-maxrad* 1e-6))
                   (> (abs theta) *cchk-pad-angtol*)) ; total bend over the
                                     ; tolerance, else it's a semi-straight line
              (progn
                (setq sa    (angle cen (cal:2d a))
                      sgn   (if (> theta 0.0) 1.0 -1.0)
                      sweep (abs theta))
                (foreach ctr (cchk:pv-arc-pads cen r sa sgn sweep padsize)
                  (setq pads (cons (list ctr 0.0 "arc") pads)))))))
    (setq i (1+ i)))
  (reverse pads))

;; Keep suggested pads from colliding where features crowd together,
;; without ever pulling a pad off a sharp point (PADDLE v1.2). Corner
;; pads commit first, dead-center on their vertex -- they NEVER slide;
;; one that would overlap an earlier corner pad is dropped (in a notch
;; that tight, the neighbour carries the area). Arc pads then dodge
;; around everything committed: one that would overlap slides along
;; one axis to sit flush alongside instead (pads are PADSIZE x
;; PADSIZE, so flush = exactly PADSIZE on center). An arc pad whose
;; center is already inside a committed pad -- or that cannot find a
;; clear flush spot within half a pad of where it wanted to be -- is
;; dropped: its area is covered by the neighbours it kept hitting.
(defun cchk:pv-dodge (pads padsize / out ctr orig tries done hit d ax sgn)
  (foreach pad pads ; sharp points first: exact centers, never slid
    (if (= (caddr pad) "corner")
        (progn
          (setq hit nil)
          (foreach q out
            (if (and (not hit)
                     (< (cchk:pv-cheb (cal:v- (car pad) (car q)))
                        (- padsize 1e-6)))
                (setq hit T)))
          (if (not hit) (setq out (cons pad out))))))
  (foreach pad pads ; arc pads dodge around what's committed
    (if (/= (caddr pad) "corner")
        (progn
          (setq ctr   (car pad)
                orig  ctr
                tries 0
                done  nil)
          (while (not done)
            (setq hit nil)
            (foreach q out
              (if (and (not hit)
                       (< (cchk:pv-cheb (cal:v- ctr (car q)))
                          (- padsize 1e-6)))
                  (setq hit (car q))))
            (cond
              ((not hit) ; clear: commit it here
               (setq out  (cons (list ctr (cadr pad) (caddr pad)) out)
                     done T))
              ((or (< (cchk:pv-cheb (cal:v- ctr hit)) (/ padsize 2.0))
                   (> tries 6)
                   (> (cchk:pv-cheb (cal:v- ctr orig)) (/ padsize 2.0)))
               (setq done T)) ; already covered there, or stuck: drop it
              (T ; slide along the more-separated axis until flush
               (setq d   (cal:v- ctr hit)
                     ax  (if (>= (abs (car d)) (abs (cadr d))) 0 1)
                     sgn (if (< (nth ax d) 0.0) -1.0 1.0))
               (setq ctr (if (= ax 0)
                             (list (+ (car hit) (* sgn padsize)) (cadr ctr))
                             (list (car ctr) (+ (cadr hit) (* sgn padsize)))))
               (setq tries (1+ tries))))))))
  (reverse out))

;; --- cover rules ----------------------------------------------------

(defun cchk:bylayer-p (ent col / ed)
  ;; T when the entity's properties are all ByLayer; COL is its TRUE
  ;; colour (256 = ByLayer) - passed in because during a review the
  ;; entity may be wearing the grey or a flag colour
  (setq ed (entget ent))
  (and (= 256 col)
       (or (null (assoc 6 ed))
           (= "BYLAYER" (strcase (cdr (assoc 6 ed)))))
       (or (null (assoc 370 ed))
           (= -1 (cdr (assoc 370 ed))))))

(defun cchk:pool-ents (ss saved / i e ed out nskip)
  ;; pool-outline candidates: LINE/ARC/LWPOLYLINE/POLYLINE on the pool
  ;; layer with every property ByLayer, from the selection. SAVED (the
  ;; review's colour stash) supplies the true colour of anything
  ;; currently greyed out. Returns (ents . skipped); skipped sit on
  ;; the layer but carry explicit properties.
  (setq i 0 nskip 0)
  (repeat (sslength ss)
    (setq e  (ssname ss i)
          i  (1+ i)
          ed (entget e))
    (if (and ed
             (member (cdr (assoc 0 ed)) '("LINE" "ARC" "LWPOLYLINE" "POLYLINE" "CIRCLE"))
             (= (strcase (cdr (assoc 8 ed))) (strcase *cchk-pool-layer*)))
      (if (cchk:bylayer-p e (cond ((assoc e saved) (cdr (assoc e saved)))
                                  ((cchk:ent-color e))))
        (setq out (cons e out))
        (setq nskip (1+ nskip)))))
  (cons (reverse out) nskip))

(defun cchk:pool-loop (pents / segs e res loops best bestarea a l)
  ;; the pool outline: the largest closed loop chained from the
  ;; candidates' bulge-aware segments. Returns
  ;;   (best-loop open-chain-count other-closed-loop-count)
  ;; best-loop is nil when nothing closes back on itself; the other
  ;; two counts flag an ambiguous outline (a gap, or extra geometry
  ;; on the pool layer) even when a loop was still found.
  (foreach e pents
    (setq segs (append segs (cchk:pv-ent-segs e))))
  (setq res      (cchk:pv-chain segs)
        loops    (car res)
        bestarea 0.0)
  (foreach l loops
    (setq a (abs (cchk:pv-area l)))
    (if (> a bestarea) (setq bestarea a best l)))
  (list best (cdr res) (max 0 (1- (length loops)))))

(defun cchk:parse-nxn (s / lst i n num a res)
  ;; the first "NxN" written in the text ("5x5", "3 X 3") as a list
  ;; (n1 n2); nil when none
  (if s
    (progn
      (setq lst (vl-string->list (cchk:squash s))
            i   0
            n   (length lst))
      (while (and (< i n) (null res))
        (if (and (>= (nth i lst) 48) (<= (nth i lst) 57))
          (progn
            (setq num 0)
            (while (and (< i n) (>= (nth i lst) 48) (<= (nth i lst) 57))
              (setq num (+ (* 10 num) (- (nth i lst) 48))
                    i   (1+ i)))
            (setq a num)
            (if (and (< i n) (= (nth i lst) 88))       ; X
              (progn
                (setq i (1+ i))
                (if (and (< i n) (>= (nth i lst) 48) (<= (nth i lst) 57))
                  (progn
                    (setq num 0)
                    (while (and (< i n) (>= (nth i lst) 48) (<= (nth i lst) 57))
                      (setq num (+ (* 10 num) (- (nth i lst) 48))
                            i   (1+ i)))
                    (setq res (list a num)))))))
          (setq i (1+ i))))))
  res)

(defun cchk:nxn-str (sp)
  (strcat (itoa (car sp)) "x" (itoa (cadr sp))))

(defun cchk:na-p (s)
  ;; T when the text reads NA / N/A instead of a value
  (and s (wcmatch (strcat " " (cchk:norm-text s) " ")
                  "* NA *,* N A *")))

(defun cchk:ent-linetype (ent / ed lt ld)
  ;; the entity's effective linetype name (ByLayer resolved through
  ;; its layer); "CONTINUOUS" when nothing says otherwise
  (setq ed (entget ent)
        lt (cdr (assoc 6 ed)))
  (if (or (null lt) (= "BYLAYER" (strcase lt)))
    (progn
      (setq ld (tblsearch "LAYER" (cdr (assoc 8 ed))))
      (setq lt (if ld (cdr (assoc 6 ld))))))
  (if lt lt "CONTINUOUS"))

(defun cchk:dashed-poly-on (ss lay / i e ed found)
  ;; T when the selection holds a polyline on the given layer drawn
  ;; with a dashed linetype (*cchk-dashed-pat*)
  (setq i 0 lay (strcase lay))
  (repeat (sslength ss)
    (setq e  (ssname ss i)
          i  (1+ i)
          ed (entget e))
    (if (and (not found) ed
             (member (cdr (assoc 0 ed)) '("LWPOLYLINE" "POLYLINE"))
             (= lay (strcase (cdr (assoc 8 ed))))
             (wcmatch (strcase (cchk:ent-linetype e)) *cchk-dashed-pat*))
      (setq found T)))
  found)

(defun cchk:cover-nonpoly (ss lay / i ed n bad)
  ;; (total . non-polylines) over everything in the selection on the
  ;; given layer - the drawn cover must be polylines only
  (setq i 0 n 0 bad 0 lay (strcase lay))
  (repeat (sslength ss)
    (setq ed (entget (ssname ss i))
          i  (1+ i))
    (if (and ed (= lay (strcase (cdr (assoc 8 ed)))))
      (progn
        (setq n (1+ n))
        (if (not (member (cdr (assoc 0 ed)) '("LWPOLYLINE" "POLYLINE")))
          (setq bad (1+ bad))))))
  (cons n bad))

(defun cchk:sel-has-phrase (ss blks phrase / pat found i e ed g b)
  ;; T when the phrase appears in the highlighted area: on a TEXT or
  ;; MTEXT entity, or in a block's name, attributes or definition
  ;; (case, spacing and punctuation ignored). COVERCHECK's own report
  ;; is skipped so a rerun never reads its own words back.
  (setq pat (strcat "*" (cchk:squash phrase) "*")
        i   0)
  (repeat (sslength ss)
    (setq e  (ssname ss i)
          i  (1+ i)
          ed (entget e))
    (if (and (not found) ed
             (/= (strcase (cdr (assoc 8 ed))) (strcase *cchk-report-layer*))
             (member (cdr (assoc 0 ed)) '("TEXT" "MTEXT")))
      (foreach g ed
        (if (and (member (car g) '(1 3))
                 (wcmatch (cchk:squash (cdr g)) pat))
          (setq found T)))))
  (foreach b blks
    (if (and (not found) (cchk:ins-matches b phrase))
      (setq found T)))
  found)

(defun cchk:pad-centers (/ ss2 i e ed nm bb out)
  ;; centers (extents middle) of every pad already in the drawing: an
  ;; INSERT on the pads layer, or one whose (effective) name is a pad
  ;; block from *cchk-pad-blocks* - scoped to the current layout tab
  ;; so a pad sitting in another tab is never counted as covering this one
  (setq ss2 (ssget "_X" (list '(0 . "INSERT") (cons 410 (getvar "CTAB"))))
        i   0)
  (if ss2
    (repeat (sslength ss2)
      (setq e  (ssname ss2 i)
            i  (1+ i)
            ed (entget e))
      (if ed
        (progn
          (setq nm (cchk:squash (cchk:block-name e)))
          (if (or (= (strcase (cdr (assoc 8 ed))) (strcase *cchk-pads-layer*))
                  (vl-some '(lambda (p) (= nm (cchk:squash p))) *cchk-pad-blocks*))
            (progn
              (setq bb (cal:bbox-ent e))
              (if bb
                (setq out (cons (list (* 0.5 (+ (caar bb) (caadr bb)))
                                      (* 0.5 (+ (cadar bb) (cadadr bb))))
                                out)))))))))
  out)

(defun cchk:mark-pad (ctr)
  ;; circle a suggested pad spot on the construction layer, tagged so
  ;; a rerun or COVERCHECKRESCUE clears it
  (if (entmake (list '(0 . "CIRCLE")
                     '(100 . "AcDbEntity")
                     (cons 8 *cchk-constr-layer*)
                     '(100 . "AcDbCircle")
                     (cons 10 (list (car ctr) (cadr ctr) 0.0))
                     (cons 40 (/ *cchk-pad-size* 2.0))))
    (cchk:tag (entlast) "MARKER")))

(defun cchk:cover-audit (ss blks live saved / pres pents lres vts narc nlin v
                          sqft det ovraw ovval ovok ovna spraw spval spna
                          arcy wantov wantsp why dashpoly cstat covered note
                          spanote replblk replp replsum padskip pk lines s f
                          feats padctrs miss poolsum detsum padsum notesum)
  ;; every cover rule, run over the selection. Returns
  ;;   (header-summaries detail-lines)
  ;; as plain report strings - cchk:attn-p decides which turn red.
  ;; Nothing in the drawing is rewritten; disagreements are only
  ;; SUGGESTED against. LIVE marks a real COVERCHECK run: suggested
  ;; pad spots are circled on the construction layer, and with no
  ;; Replacement Disclaimer selected the replacement question is
  ;; asked at the prompt (COVERSCAN never asks).

  ;; the 'Pool Size Shown' note is checked first: besides its own
  ;; verdict (below) it also silences the replacement prompt and the
  ;; NA-overlap dashed-outline demand, both of which assume a drawn
  ;; cover exists to check against
  (setq note    (cchk:sel-has-phrase ss blks *cchk-pool-note*)
        spanote (cchk:sel-has-phrase ss blks *cchk-spa-note*))
  ;; both notes at once is a contradiction, not two separate all-clears
  (if (and note spanote)
    (setq lines (append lines (list
      (strcat "Pool/Spa size: BOTH '" *cchk-pool-note* "' and '" *cchk-spa-note*
              "' are in the selection - ONLY ONE SIZE CAN BE SHOWN")))))

  ;; --- pool outline & area (ByLayer geometry on the pool layer) ----
  (setq pres  (cchk:pool-ents ss saved)
        pents (car pres)
        lres  (if pents (cchk:pool-loop pents))
        vts   (car lres)
        narc  0
        nlin  0)
  (if (> (cdr pres) 0)
    (setq lines
          (append lines
                  (list (strcat "Pool: " (itoa (cdr pres)) " item(s) on layer '"
                                *cchk-pool-layer*
                                "' SKIPPED - properties are not ByLayer")))))
  (if (and lres (or (> (cadr lres) 0) (> (caddr lres) 0)))
    (setq lines (append lines (list
      (strcat "Pool: outline on layer '" *cchk-pool-layer* "' is AMBIGUOUS -"
              (if (> (cadr lres) 0)
                (strcat " " (itoa (cadr lres)) " open chain(s) (check for gaps)")
                "")
              (if (> (caddr lres) 0)
                (strcat (if (> (cadr lres) 0) ";" "") " " (itoa (caddr lres))
                        " other closed loop(s) ignored (largest used)")
                ""))))))
  (if vts
    (progn
      (foreach v vts
        (if (equal 0.0 (caddr v) 1e-12)
          (setq nlin (1+ nlin))
          (setq narc (1+ narc))))
      (setq sqft    (/ (abs (cchk:pv-area vts)) 144.0)
            arcy    (> narc nlin)
            poolsum (strcat (rtos sqft 2 1) " sq ft - outline "
                            (itoa nlin) " straight / " (itoa narc)
                            " arc segment(s), mostly "
                            (if arcy "arcs" "straights")
                            (if (and lres (or (> (cadr lres) 0) (> (caddr lres) 0)))
                              " (AMBIGUOUS - see detail)"
                              "")))
      ;; what the cover SHOULD be for this pool
      (cond
        (arcy
         (setq wantov 18.0
               wantsp '(3 3)
               why    "outline is mostly arcs"))
        ((< sqft *cchk-area-small*)
         (setq wantov 12.0
               wantsp '(5 5)
               why    (strcat "under " (rtos *cchk-area-small* 2 0) " sq ft")))
        ((<= sqft *cchk-area-large*)
         (setq wantov 15.0
               wantsp '(3 3)
               why    (strcat (rtos *cchk-area-small* 2 0) "-"
                              (rtos *cchk-area-large* 2 0) " sq ft")))
        (t
         (setq wantov 18.0
               wantsp '(3 3)
               why    (strcat "over " (rtos *cchk-area-large* 2 0) " sq ft")))))
    (setq poolsum (strcat "NOTHING closed and ByLayer found on layer '"
                          *cchk-pool-layer*
                          "' - area not measured (check for gaps)")))

  ;; --- Cover Details: Overlap & Spacing vs what the pool needs -----
  (setq det (car (vl-remove-if-not
                   '(lambda (b) (cchk:ins-matches b *cchk-details-block*))
                   blks)))
  (if (null det)
    (progn
      (setq detsum (strcat "block MISSING"
                           (if wantov
                             (strcat " - SUGGEST Overlap "
                                     (rtos wantov 2 0) "\", Spacing "
                                     (cchk:nxn-str wantsp) " (" why ")")
                             "")))
      (setq lines (append lines (list (strcat "Cover Details: " detsum)))))
    (progn
      ;; the OVERLAP value: attribute tag first, any text carrying
      ;; the word next
      (setq ovraw (cchk:ins-attrib det "OVERLAP"))
      (if (null ovraw)
        (foreach s (cchk:ins-texts det)
          (if (and (null ovraw) s (wcmatch (cchk:norm-text s) "*OVERLAP*"))
            (setq ovraw s))))
      (setq ovval    (if ovraw (cchk:parse-len ovraw))
            ovna     (cchk:na-p ovraw)
            ovok     (and ovval
                          (vl-some '(lambda (x) (equal x ovval 1e-6))
                                   *cchk-overlap-vals*))
            dashpoly (cchk:dashed-poly-on ss *cchk-pool-layer*))
      ;; the SPACING tag, same hunt
      (setq spraw (cchk:ins-attrib det "SPACING"))
      (if (null spraw)
        (foreach s (cchk:ins-texts det)
          (if (and (null spraw) s (wcmatch (cchk:norm-text s) "*SPACING*"))
            (setq spraw s))))
      (setq spval (cchk:parse-nxn spraw)
            spna  (cchk:na-p spraw))
      (setq lines (append lines (list
        (cond
          (ovna
           (strcat "Cover Details: Overlap is NA"
                   (if dashpoly
                     (strcat " but a DASHED polyline sits on layer '"
                             *cchk-pool-layer* "' - LOOK AT it")
                     (strcat " and layer '" *cchk-pool-layer*
                             "' has no dashed polyline - OK"))))
          ((null ovval)
           (strcat "Cover Details: Overlap is "
                   (if (and ovraw (/= ovraw ""))
                     (strcat "UNREADABLE ('" (cchk:clip ovraw 20) "')")
                     "BLANK")
                   " - "
                   (if wantov
                     (strcat "SUGGEST " (rtos wantov 2 0) "\" (" why ")")
                     "fill it in")))
          ((not ovok)
           (strcat "Cover Details: Overlap reads '" (cchk:clip ovraw 20)
                   "' - not 12\"/15\"/18\""
                   (if wantov
                     (strcat " - SUGGEST " (rtos wantov 2 0) "\" (" why ")")
                     "")))
          ((and wantov (not (equal ovval wantov 1e-6)))
           (strcat "Cover Details: Overlap " (rtos ovval 2 0)
                   "\" - SUGGEST " (rtos wantov 2 0) "\" (" why ")"))
          (wantov
           (strcat "Cover Details: Overlap " (rtos ovval 2 0)
                   "\" - matches (" why ")"))
          (t
           (strcat "Cover Details: Overlap " (rtos ovval 2 0)
                   "\" - no pool outline to check it against"))))))
      ;; any stated overlap demands a dashed cover outline on the pool
      ;; layer - UNLESS the 'Pool Size Shown' note is present, which
      ;; means no drawn cover is expected in the first place
      (if (and ovval (not note))
        (setq lines (append lines (list
          (if dashpoly
            (strcat "Cover Details: overlap set and a dashed polyline sits on layer '"
                    *cchk-pool-layer* "' - OK")
            (strcat "Cover Details: overlap set but NO DASHED polyline on layer '"
                    *cchk-pool-layer*
                    "' - draw the cover outline dashed"))))))
      (setq lines (append lines (list
        (cond
          (spna "Cover Details: Spacing is NA")
          ((null spval)
           (strcat "Cover Details: Spacing is "
                   (if (and spraw (/= spraw ""))
                     (strcat "UNREADABLE ('" (cchk:clip spraw 20) "')")
                     "BLANK")
                   " - "
                   (if wantsp
                     (strcat "SUGGEST " (cchk:nxn-str wantsp) " (" why ")")
                     "fill it in (NxN)")))
          ((/= (car spval) (cadr spval))
           (strcat "Cover Details: Spacing reads '" (cchk:clip spraw 20)
                   "' - not NxN"
                   (if wantsp
                     (strcat " - SUGGEST " (cchk:nxn-str wantsp) " (" why ")")
                     "")))
          ((and wantsp (not (equal spval wantsp)))
           (strcat "Cover Details: Spacing " (cchk:nxn-str spval)
                   " - SUGGEST " (cchk:nxn-str wantsp) " (" why ")"))
          (wantsp
           (strcat "Cover Details: Spacing " (cchk:nxn-str spval)
                   " - matches (" why ")"))
          (t
           (strcat "Cover Details: Spacing " (cchk:nxn-str spval)
                   " - no pool outline to check it against"))))))
      (setq detsum
            (strcat "Overlap "
                    (cond (ovna "NA")
                          (ovval (strcat (rtos ovval 2 0) "\""))
                          (t "BLANK"))
                    (if (and ovval (not ovok)) " (not 12/15/18)" "")
                    (if (and wantov (not ovna)
                             (or (null ovval)
                                 (not (equal ovval wantov 1e-6))))
                      (strcat " - SUGGEST " (rtos wantov 2 0) "\"")
                      "")
                    (if (and ovval (not dashpoly) (not note)) " - NO DASHED outline" "")
                    (if (and ovna dashpoly) " - dashed outline present, LOOK AT it" "")
                    "; Spacing "
                    (cond (spna "NA")
                          (spval (cchk:nxn-str spval))
                          (t "BLANK"))
                    (if (and wantsp (not spna)
                             (or (null spval)
                                 (not (equal spval wantsp))))
                      (strcat " - SUGGEST " (cchk:nxn-str wantsp))
                      "")))))

  ;; --- the cover layer: polylines only + 'Pool Size Shown' note ----
  ;; (note itself was already read at the top of the function)
  (setq cstat   (cchk:cover-nonpoly ss *cchk-cover-layer*)
        covered (> (car cstat) 0))
  (if (and covered (> (cdr cstat) 0))
    (setq lines (append lines (list
      (strcat "Cover: " (itoa (cdr cstat)) " of " (itoa (car cstat))
              " item(s) on layer '" *cchk-cover-layer*
              "' are NOT A POLYLINE - redraw the cover as a polyline")))))
  (setq notesum
        (cond
          ((and covered note)
           (strcat "cover drawn on layer '" *cchk-cover-layer*
                   "' AND the '" *cchk-pool-note*
                   "' note is in - SUGGEST taking the note off"))
          (covered
           (strcat "cover drawn on layer '" *cchk-cover-layer*
                   "', no '" *cchk-pool-note* "' note - OK"))
          (note
           (strcat "no cover on layer '" *cchk-cover-layer*
                   "', '" *cchk-pool-note* "' note is in - OK"))
          (t
           (strcat "no cover on layer '" *cchk-cover-layer*
                   "' and the '" *cchk-pool-note*
                   "' note is nowhere in the selection - SUGGEST adding it"))))
  (if (and covered (> (cdr cstat) 0))
    (setq notesum (strcat notesum "; " (itoa (cdr cstat))
                          " item(s) NOT A POLYLINE")))
  (if (and note spanote)
    (setq notesum (strcat notesum "; ONLY ONE SIZE CAN BE SHOWN ('"
                          *cchk-pool-note* "' & '" *cchk-spa-note*
                          "' both present)")))

  ;; --- Replacement Disclaimer --------------------------------------
  (setq replblk (car (vl-remove-if-not
                       '(lambda (b) (cchk:ins-matches b *cchk-repl-block*))
                       blks)))
  (cond
    (replblk
     (setq replp   T
           replsum (strcat "'" *cchk-repl-block*
                           "' block present - replacement drawing")))
    (note
     ;; a full pool size drawing is never a replacement - do not ask
     (setq replsum (strcat "not asked - '" *cchk-pool-note*
                           "' note is present (full pool size shown)")))
    (live
     (if (cal:ask-yn (strcat "\nNo '" *cchk-repl-block*
                              "' block is selected - is this drawing a replacement?")
                     "No")
       (progn
         (setq replp T)
         (setq pk (entsel (strcat "\nPick the '" *cchk-repl-block*
                                  "' block <it is not placed>: ")))
         (cond
           ((and pk
                 (= "INSERT" (cdr (assoc 0 (entget (car pk)))))
                 (cchk:ins-matches (car pk) *cchk-repl-block*))
            (cchk:zoom-ent (car pk))
            (setq replsum (strcat "replacement; '" *cchk-repl-block*
                                  "' found where you pointed (outside the selection)")))
           (pk
            (setq replsum (strcat "replacement, but what you picked is not it - '"
                                  *cchk-repl-block* "' block MISSING, add it")))
           (t
            (setq replsum (strcat "replacement but the '" *cchk-repl-block*
                                  "' block is MISSING - add it")))))
       (setq replsum (strcat "not a replacement - '" *cchk-repl-block*
                             "' not needed"))))
    (t
     (setq replsum (strcat "no '" *cchk-repl-block*
                           "' in the selection - run COVERCHECK to confirm"))))
  (setq lines (append lines (list (strcat "Replacement: " replsum))))

  ;; --- pads along the pool outline (PADDLE logic, 36" pads) --------
  ;; a replacement, an NA overlap or a drawn cover all mean the pads
  ;; are not sized from the pool outline - PADDLE is not used there
  (setq padskip
        (cond
          (replp   "this is a replacement")
          (ovna    "the Overlap is NA")
          (covered (strcat "a cover is drawn on layer '"
                           *cchk-cover-layer* "'"))))
  (if (and vts (not padskip))
    (progn
      (setq feats   (if (> (length vts) 1)
                      (cchk:pv-dodge (cchk:pv-features vts *cchk-pad-size*)
                                     *cchk-pad-size*))
            padctrs (cchk:pad-centers)
            miss    nil)
      (foreach f feats
        (if (not (vl-some
                   '(lambda (p) (<= (cchk:pv-cheb (cal:v- p (car f)))
                                    *cchk-pad-near*))
                   padctrs))
          (setq miss (cons f miss))))
      (setq miss (reverse miss))
      (setq padsum
            (cond
              ((null feats) "outline has no concave features - none needed")
              ((null miss)  (strcat (itoa (length feats))
                                    " spot(s) checked - every one has a pad"))
              (t (strcat (itoa (length miss)) " of " (itoa (length feats))
                         " 36\" spot(s) have no pad - SUGGEST adding"
                         (if live " (circled)" "")))))
      (setq lines (append lines (list (strcat "Pads: " padsum))))
      (foreach f miss
        (if live (cchk:mark-pad (car f)))
        (setq lines (append lines (list
          (strcat "Pad SUGGESTED at " (cchk:ptstr (car f))
                  (if (= (caddr f) "corner")
                    " (inside corner)"
                    " (along a concave arc)")))))))
    (progn
      (setq padsum (if padskip
                     (strcat "not suggested - " padskip)
                     "pool outline not found - not checked"))
      (setq lines (append lines (list (strcat "Pads: " padsum))))))

  (list (list (strcat "Pool: " poolsum)
              (strcat "Cover Details: " detsum)
              (strcat "Cover: " notesum)
              (strcat "Replacement: " replsum)
              (strcat "Pads: " padsum))
        lines))

;; --- command -------------------------------------------------------

(defun c:COVERCHECK ( / *error* oldecho vc vs undo-open ss i e et
                      cands dims arcs plns segs blks olaps e1 e2 pr
                      saved keep res n total lines
                      anchors anchheld
                      ndok ndflag ndmoved ndanch naok namoved nasnap
                      nomerged noflag noleft
                      rowtol sty l pair hdr cres
                      laylist locked relock lay
                      dlines skiprest
                      minx miny maxx maxy bb m dhdr right dimlay units datev carried cmv)

  (defun *error* (msg)
    ;; put the greys back (flagged/moved items keep their colour),
    ;; re-lock what we unlocked, clear markers, close the undo group
    ;; The entity work stays INSIDE the group, so one U still takes the
    ;; whole run back -- but through the catch: an entmod that throws
    ;; (a colour on a layer the user declined to unlock is in saved
    ;; too) used to skip the close and the CMDECHO restore below, and
    ;; a throw inside *error* is the one error nothing catches.
    (vl-catch-all-apply
      '(lambda ()
         (foreach pair saved
           (if (and (not (member (car pair) keep)) (entget (car pair)))
             (cchk:set-color (car pair) (cdr pair))))
         (foreach l relock (cchk:set-layer-lock l T))
         (redraw))
      nil)
    (if undo-open
      (progn (setvar "CMDECHO" 0) (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCOVERCHECK error: " msg)))
    (princ))

  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I"))
  (if (null ss)
    (progn
      (prompt "\nHighlight the drawing to COVERCHECK: ")
      (setq ss (ssget))))
  (cond
    ((null ss)
     (prompt "\nNothing selected - COVERCHECK cancelled."))
    (t
     (setq cands nil dims nil arcs nil blks nil segs nil
           saved nil keep nil lines nil i 0
           ndok 0 ndflag 0 ndmoved 0 ndanch 0 naok 0 namoved 0 nasnap 0
           nomerged 0 noflag 0 noleft 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (member et '("LINE" "LWPOLYLINE" "POLYLINE"))
         (setq plns (cons e plns)))
       (if (= et "INSERT") (setq blks (cons e blks)))
       (if (member et *cchk-curve-types*) (setq cands (cons e cands))))
     (setq dims  (reverse dims)
           arcs  (reverse arcs)
           plns  (reverse plns)
           blks  (reverse blks)
           cands (reverse cands)
           ;; detection runs on segments, so a shape drawn as one
           ;; polyline counts like the same shape drawn as lines
           segs  (cchk:collect-segs plns))
     (cond
       ((and (null dims) (null arcs) (< (length segs) 2) (null blks))
        (prompt "\nSelection holds no dimensions, arcs, lines, or blocks to check - nothing to do."))
       (t
        (setq oldecho (getvar "CMDECHO"))
        (setvar "CMDECHO" 0)
        (setq vc (getvar "VIEWCTR")
              vs (getvar "VIEWSIZE"))
        ;; only when undo is recording - _Begin in a drawing with UNDO
        ;; off (bit 1 of UNDOCTL clear) errors out of the command
        (if (= 1 (logand 1 (getvar "UNDOCTL")))
          (progn
            (command "_.UNDO" "_Begin")
            (setq undo-open T)))
        (cal:ensure-layer *cchk-constr-layer* *cchk-constr-color*)
        (cal:ensure-layer *cchk-report-layer* *cchk-report-color*)

        ;; a locked layer swallows every fix and recolour silently -
        ;; surface that up front and offer to unlock for the run
        (setq laylist nil relock nil i 0)
        (repeat (sslength ss)
          (setq lay (cdr (assoc 8 (entget (ssname ss i))))
                i   (1+ i))
          (if (and lay (not (member lay laylist)))
            (setq laylist (cons lay laylist))))
        (setq locked (vl-remove-if-not 'cchk:layer-locked-p laylist))
        (if locked
          (if (cal:ask-yn
                (strcat "\n" (itoa (length locked))
                        " locked layer(s) in the selection ("
                        (cchk:join locked ", ")
                        ") - COVERCHECK cannot recolour or fix anything on them. Unlock for this run?")
                "Yes")
            (progn
              (foreach l locked (cchk:set-layer-lock l nil))
              (setq relock locked)
              (princ "\n  Unlocked; they will be re-locked when the run ends."))
            (princ "\n  Locked layers stay locked - items on them are reported but left untouched.")))

        ;; a rerun replaces the previous run's report and markers
        (cchk:clear-old)

        ;; extents of the selection (report goes to the right of them)
        (setq i 0)
        (repeat (sslength ss)
          (setq e  (ssname ss i)
                i  (1+ i)
                bb (cal:bbox-ent e))
          (if bb
            (setq minx (if minx (min minx (caar bb)) (caar bb))
                  miny (if miny (min miny (cadar bb)) (cadar bb))
                  maxx (if maxx (max maxx (caadr bb)) (caadr bb))
                  maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))

        ;; march order for the dimensions: style groups first
        ;; (*cchk-style-order*), then row by row, left to right
        (setq rowtol (if (and miny maxy (> (- maxy miny) 1e-8))
                       (* 0.05 (- maxy miny))
                       1.0))
        (setq dims (cchk:sort-dims dims rowtol))

        ;; spots two or more dimensions measure to are anchors: a
        ;; hypotenuse corner is dimmed twice precisely because there is
        ;; no line through it, so those points are objects as far as the
        ;; audit is concerned. Read once, off the drawing as selected.
        (setq anchors (cchk:shared-anchors dims))
        (if anchors
          (princ (strcat "\n" (itoa (length anchors))
                         " point(s) carry more than one dimension - treated"
                         " as anchors and not questioned.")))

        ;; grey out the whole selection so each item can take the
        ;; stage, stashing every original colour in xdata first so
        ;; COVERCHECKRESCUE can recover them even after a crash
        (setq i 0)
        (repeat (sslength ss)
          (setq e (ssname ss i)
                i (1+ i))
          (if (entget e)
            (progn
              (setq saved (cons (cons e (cchk:ent-color e)) saved))
              (cchk:stash-color e (cchk:ent-color e))
              (cchk:set-color e *cchk-grey-color*))))

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
          (cchk:set-color e (cdr (assoc e saved)))       ; step into the light
          (setq res (cchk:review-dim e cands anchors (1+ n) total))
          ;; points already moved count however the prompt was answered
          (setq ndmoved (+ ndmoved (cadddr res)))
          ;; anchor holds are recorded PER DIMENSION rather than added
          ;; up: an anchored point stays anchored, so a dimension sent
          ;; round again by Back reports it a second time and a running
          ;; total would count it twice. A moved point cannot do that --
          ;; moving it is what makes it attached.
          (if (> (nth 5 res) 0)
            (setq anchheld (cons (cons e (nth 5 res))
                                 (vl-remove (assoc e anchheld) anchheld))))
          (cond
            ((eq (cadr res) 'skip)
             (cchk:set-color e *cchk-grey-color*)
             (setq skiprest T)
             (princ (strcat "\n  Skipping the remaining "
                            (itoa (- total n)) " dimension(s).")))
            ((eq (cadr res) 'back)
             ;; undo what the previous item recorded, then redo it
             (cchk:set-color e *cchk-grey-color*)
             (if (> n 0)
               (progn
                 (setq n  (1- n)
                       e1 (nth n dims))
                 (if (car dlines)                        ; roll back its tally
                   (progn
                     (if (cadr (car dlines))
                       (setq ndok (1- ndok))
                       (setq ndflag (1- ndflag)))
                     ;; A MOVED POINT STAYS MOVED.  Back re-asks the
                     ;; question; it does not put the point back, and
                     ;; its construction line is still standing.  So
                     ;; the move is CARRIED to the re-review, not
                     ;; un-counted -- subtracting it made the report
                     ;; claim "points adjusted: 0" over a drawing
                     ;; whose points really had been adjusted, and
                     ;; the rebuilt line lost its "moved" note with
                     ;; it (the second pass finds them attached and
                     ;; has nothing to report).
                     (if (> (caddr (car dlines)) 0)
                       (setq carried (cons (cons e1 (caddr (car dlines)))
                                           (vl-remove (assoc e1 carried)
                                                      carried))))
                     (setq dlines (cdr dlines))))
                 (setq keep (vl-remove e1 keep))
                 (cchk:set-color e1 *cchk-grey-color*)
                 (princ "\n  Stepping back one dimension."))
               (princ "\n  Already at the first dimension."))
             (setq n (1- n)))                            ; loop's 1+ re-enters it
            (t
             (if (cadr res)
               (progn (setq ndok (1+ ndok))
                      (cchk:set-color e *cchk-grey-color*))
               (progn (setq ndflag (1+ ndflag))
                      (setq keep (cons e keep))))
             (setq sty (cchk:dim-style e))
             ;; moves this dim collected on an earlier pass, before a
             ;; Back sent us round again -- they are real and belong
             ;; in both the line and the tally
             (setq cmv (cond ((cdr (assoc e carried))) (0)))
             (setq dlines (cons (list (strcat "Dim " (car res)
                                              (if (= sty "") "" (strcat " [" sty "]"))
                                              (if (nth 4 res)
                                                (strcat " = " (nth 4 res))
                                                "")
                                              ": " (caddr res)
                                              (if (> cmv 0)
                                                (strcat " - " (itoa cmv)
                                                        " point(s) moved before"
                                                        " you stepped back")
                                                ""))
                                      (cadr res)
                                      (+ (cadddr res) cmv))
                                dlines))))
          (setq n (1+ n)))
        (foreach pair anchheld (setq ndanch (+ ndanch (cdr pair))))
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
          (cchk:set-color e (cdr (assoc e saved)))
          (setq res (cchk:review-arc e cands n total))
          (setq nasnap (+ nasnap (cadddr res)))
          (if (cadr res)
            (progn (setq naok (1+ naok))
                   (cchk:set-color e *cchk-grey-color*))
            (progn (setq namoved (1+ namoved))
                   (setq keep (cons e keep))))           ; moved: stays magenta
          (setq lines (cons (strcat "Arc " (car res) ": " (caddr res)) lines)))

        ;; --- overlapping lines, one pair at a time ------------------
        (setq olaps (cchk:find-overlaps segs))
        (if olaps
          (princ (strcat "\n--- Reviewing " (itoa (length olaps))
                         " overlapping line pair(s): Enter = merge, F = flag, L = leave ---")))
        (setq n 0 total (length olaps))
        (foreach pr olaps
          (setq n  (1+ n)
                e1 (cchk:seg-ent (car pr))
                e2 (cchk:seg-ent (cadr pr)))
          (cchk:stage e1 saved keep)
          (cchk:stage e2 saved keep)
          (setq res (cchk:review-olap (car pr) (cadr pr) n total))
          (cond
            ((null res)                       ; absorbed by an earlier merge
             (cchk:unstage e1 keep)
             (cchk:unstage e2 keep))
            ((eq (caddr res) 'left)
             (setq noleft (1+ noleft))
             (cchk:unstage e1 keep)
             (cchk:unstage e2 keep)
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))
            (t
             (if (eq (caddr res) 'merged)
               (setq nomerged (1+ nomerged))
               (setq noflag (1+ noflag)))
             (setq keep (append (cdddr res) keep))
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))))

        ;; --- restore colours (flagged/moved keep theirs) ------------
        ;; restored entities drop their rescue stash; flagged/moved
        ;; ones keep it so COVERCHECKRESCUE can clear the marks later
        (foreach pair saved
          (if (and (not (member (car pair) keep)) (entget (car pair)))
            (progn
              (cchk:set-color (car pair) (cdr pair))
              (cchk:unstash (car pair)))))
        (foreach l relock (cchk:set-layer-lock l T))
        (setq relock nil)

        ;; --- cover checks: pool area, Cover Details, note, pads -----
        (princ "\n--- Cover checks: pool outline & area, Cover Details, pads ---")
        (setq cres (cchk:cover-audit ss blks T saved))
        (foreach l (cadr cres)
          (princ (strcat "\n  " l))
          (setq lines (cons l lines)))

        ;; --- report on the right side, to scale with the drawing ----
        ;; the cover checks lead on the main sheet; the DIMCHECK-style
        ;; findings go in the DIMENSION AUDIT column beside it
        (setq dhdr
          (list
            (cons (strcat "Dimensions checked: " (itoa (length dims))
                          " (correct: " (itoa ndok)
                          ", flagged to fix: " (itoa ndflag)
                          ", points adjusted: " (itoa ndmoved)
                          (if (> ndanch 0)
                            (strcat ", held at a shared anchor: " (itoa ndanch))
                            "")
                          ")")
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
                  (> noflag 0))))
        (setq dimlay (cchk:dimlayer-verdict dims)
              units  (cchk:audit-units ss)
              datev  (cchk:audit-date ss))
        (foreach l (caddr units)
          (princ (strcat "\n  " l))
          (setq lines (cons l lines)))
        (setq hdr (cons (cons (strcat "Dimension layer: " (car dimlay))
                              (cdr dimlay))
                        (cons (cons (strcat "Feet & inches: " (car units))
                                    (cadr units))
                              (cons (cons (strcat "Tech Title date: "
                                                  (car datev))
                                          (cdr datev))
                                    (mapcar '(lambda (s)
                                               (cons s (cchk:attn-p s)))
                                            (car cres))))))
        (setq right (cchk:write-report "COVERCHECK REPORT" nil hdr dhdr
                                       (reverse lines) nil
                                       minx miny maxx maxy))

        ;; --- show the drawing plus the report -----------------------
        (if minx
          (progn
            (setq m (* 0.05 (max (- maxx minx) (- maxy miny) 1.0)))
            (command "_.ZOOM" "_Window"
                     (trans (list (- minx m) (- miny m) 0.0) 0 1)
                     (trans (list (+ right m) (+ maxy m) 0.0) 0 1)))
          (command "_.ZOOM" "_Center" vc vs))

        (command "_.UNDO" "_End")
        (setq undo-open nil)
        (setvar "CMDECHO" oldecho)
        (princ (strcat "\n\n--- COVERCHECK complete ---"
                       "\nDimensions: " (itoa (length dims)) " checked, "
                       (itoa ndok) " correct, "
                       (itoa ndflag) " flagged to fix (red)"
                       (if (> ndmoved 0)
                         (strcat ", " (itoa ndmoved) " point(s) adjusted")
                         "")
                       (if (> ndanch 0)
                         (strcat ", " (itoa ndanch)
                                 " point(s) held at a shared anchor")
                         "")
                       "\nArcs: " (itoa (length arcs)) " checked, "
                       (itoa namoved) " with endpoint(s) moved ("
                       (itoa nasnap) " endpoint(s), magenta)"
                       "\nOverlapping lines: " (itoa (length olaps)) " pair(s) found"
                       (if olaps
                         (strcat ", " (itoa nomerged) " merged, "
                                 (itoa noflag) " flagged (cyan), "
                                 (itoa noleft) " left as drawn")
                         "")))
        (foreach l (car cres) (princ (strcat "\n" l)))
        (princ (strcat "\nReport placed on the right side of the drawing (layer "
                       *cchk-report-layer* ")."
                       (if (> ndmoved 0)
                         (strcat "\nConstruction lines through moved dimensions' original points are on layer "
                                 *cchk-constr-layer* ".")
                         "")
                       "\nOne UNDO reverts everything COVERCHECK changed (including the report)."))))))
  (princ))

;; --- COVERSCAN / LITECOVERSCAN: the read-only twins -------------------
;;  Run every audit, ask nothing, and change nothing in the drawing
;;  except writing the report. Use them as a quick pre-flight, or when
;;  you want the findings without touching a released sheet.
;;  LITECOVERSCAN skips the DIMCHECK-style pass entirely - no
;;  dimension, arc or overlap audit and no DIMENSION AUDIT column -
;;  for a drawing DIMCHECK already went over.

(defun c:COVERSCAN () (cchk:scan nil))

(defun c:LITECOVERSCAN () (cchk:scan T))

(defun cchk:scan (lite / *error* oldecho name ss i e et ed cands dims arcs
                       plns segs blks lines olaps pr bb bad
                       nd ndbad na nabad ndanch anchors q dq held hdr dhdr l cres dimlay units datev
                       minx miny maxx maxy p13 p14 near s)

  (setq name (if lite "LITECOVERSCAN" "COVERSCAN"))
  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n" name " error: " msg)))
    (princ))

  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I"))
  (if (null ss)
    (progn
      (prompt (strcat "\nHighlight the drawing to " name
                      " (Enter = whole drawing): "))
      (setq ss (ssget))))
  (if (null ss) (setq ss (ssget "_X" (list (cons 410 (getvar "CTAB"))))))
  (cond
    ((null ss) (prompt "\nNothing to scan."))
    (t
     (setq oldecho (getvar "CMDECHO"))
     (setvar "CMDECHO" 0)
     ;; a rerun's leftover report/marker entities (e.g. suggested-pad
     ;; circles) must not pollute this scan's own attachment checks -
     ;; clear them before anything is collected, not after
     (cal:ensure-layer *cchk-report-layer* *cchk-report-color*)
     (cchk:clear-old)
     (setq i 0 nd 0 ndbad 0 na 0 nabad 0 ndanch 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (member et '("LINE" "LWPOLYLINE" "POLYLINE")) (setq plns (cons e plns)))
       (if (= et "INSERT") (setq blks (cons e blks)))
       (if (member et *cchk-curve-types*) (setq cands (cons e cands)))
       (setq bb (cal:bbox-ent e))
       (if bb
         (setq minx (if minx (min minx (caar bb)) (caar bb))
               miny (if miny (min miny (cadar bb)) (cadar bb))
               maxx (if maxx (max maxx (caadr bb)) (caadr bb))
               maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))
     (setq dims (reverse dims) arcs (reverse arcs)
           plns (reverse plns) blks (reverse blks) cands (reverse cands)
           segs (if lite nil (cchk:collect-segs plns)))

     ;; a spot two or more dimensions measure to is an anchor and
     ;; counts as an object -- the same rule the review works by, so
     ;; the scan cannot call stray what the review will not
     (setq anchors (cchk:shared-anchors dims))

     ;; --- dimensions: report stray definition points, move nothing
     ;;     (a lite scan leaves the DIMCHECK-style pass out entirely)
     (foreach e (if lite
                  nil
                  (cchk:sort-dims dims (if (and miny maxy)
                                         (* 0.05 (- maxy miny)) 1.0)))
       (setq ed  (entget e)
             nd  (1+ nd)
             p13 (cdr (assoc 13 ed))
             p14 (cdr (assoc 14 ed))
             bad nil
             held nil)
       (if (member (logand 7 (cdr (assoc 70 ed))) '(0 1))
         (foreach s (list (cons "point 1" p13) (cons "point 2" p14))
           (if (cdr s)
             (progn
               (setq near (cchk:nearest-curve (cdr s) nil cands)
                     q    (cchk:closest-of (cdr s) anchors)
                     dq   (if q (distance (cdr s) q)))
               (cond
                 ;; another dimension measures to this spot too: it is
                 ;; an anchor, not a stray point
                 ((and dq (<= dq *cchk-anchor-tol*))
                  (if (or (null near) (> (caddr near) *cchk-tol*))
                    (setq held (append held (list (car s))))))
                 ((and near (<= (caddr near) *cchk-tol*)) nil)   ; on an object
                 ;; stray: name the nearer of the two homes it missed,
                 ;; so the scan points where the review would offer
                 ((and dq (or (null near) (< dq (caddr near))))
                  (setq bad (append bad (list (strcat (car s)
                                                      " off the shared anchor by "
                                                      (rtos dq 2 4))))))
                 (near
                  (setq bad (append bad (list (strcat (car s) " off by "
                                                      (rtos (caddr near) 2 4)))))))))))
       (if bad (setq ndbad (1+ ndbad)))
       (if held (setq ndanch (+ ndanch (length held))))
       (setq lines (cons (strcat "Dim " (cdr (assoc 5 ed))
                                 (if (= (cchk:dim-style e) "") ""
                                   (strcat " [" (cchk:dim-style e) "]"))
                                 (if (cchk:dim-meas e)
                                   (strcat " = " (cchk:dim-meas e)) "")
                                 ": "
                                 (if bad
                                   (strcat "NOT attached - " (cchk:join bad ", "))
                                   "OK")
                                 (if held
                                   (strcat " - " (cchk:join held " & ")
                                           " on a shared anchor")
                                   "")
                                 (if (cchk:dim-assoc-p e) " (associative)" ""))
                         lines)))

     ;; --- arcs: report unattached endpoints, move nothing
     (foreach e (if lite nil arcs)
       (setq na  (1+ na)
             bad nil)
       (if (cchk:planar-arc-p (entget e))
         (foreach s '(("start" . start) ("end" . end))
           (if (cchk:arc-end-target e (cdr s) cands)
             (setq bad (append bad (list (car s)))))))
       (if bad (setq nabad (1+ nabad)))
       (setq lines (cons (strcat "Arc " (cdr (assoc 5 (entget e))) ": "
                                 (if bad
                                   (strcat (cchk:join bad " & ")
                                           " NOT attached to an object end")
                                   "endpoints OK"))
                         lines)))

     ;; --- overlaps
     (setq olaps (if lite nil (cchk:find-overlaps segs)))
     (foreach pr olaps
       (setq lines (cons (strcat "Lines "
                                 (cdr (assoc 5 (entget (cchk:seg-ent (car pr)))))
                                 "+"
                                 (cdr (assoc 5 (entget (cchk:seg-ent (cadr pr)))))
                                 ": OVERLAP of "
                                 (rtos (caddr (cchk:overlap-info (car pr) (cadr pr))))
                                 " - flagged")
                         lines)))

     ;; --- cover checks (read-only - no pad markers are drawn) -------
     (princ "\n--- Cover checks: pool outline & area, Cover Details, pads ---")
     (setq cres (cchk:cover-audit ss blks nil nil))
     (foreach l (cadr cres)
       (princ (strcat "\n  " l))
       (setq lines (cons l lines)))

     ;; --- report (the only thing the scan writes) -------------------
     (setq dhdr (if lite
                  nil
                  (list
                    (cons (strcat "Dimensions scanned: " (itoa nd) " ("
                                  (itoa ndbad)
                                  " with a stray definition point"
                                  (if (> ndanch 0)
                                    (strcat ", " (itoa ndanch)
                                            " point(s) on a shared anchor")
                                    "")
                                  ")")
                          (> ndbad 0))
                    (cons (strcat "Arcs scanned: " (itoa na) " ("
                                  (itoa nabad) " with an unattached end)")
                          (> nabad 0))
                    (cons (strcat "Overlapping line pairs: "
                                  (itoa (length olaps)))
                          (> (length olaps) 0)))))
     (setq dimlay (cchk:dimlayer-verdict dims)
           units  (cchk:audit-units ss)
           datev  (cchk:audit-date ss))
     (foreach l (caddr units)
       (princ (strcat "\n  " l))
       (setq lines (cons l lines)))
     (setq hdr (cons (cons (strcat "Dimension layer: " (car dimlay))
                           (cdr dimlay))
                     (cons (cons (strcat "Feet & inches: " (car units))
                                 (cadr units))
                           (cons (cons (strcat "Tech Title date: "
                                               (car datev))
                                       (cdr datev))
                                 (mapcar '(lambda (s)
                                            (cons s (cchk:attn-p s)))
                                         (car cres))))))
     (cchk:write-report (strcat name " REPORT")
                        (strcat "Read-only scan - nothing in the drawing"
                                " was changed.  "
                                (if lite
                                  (strcat "Lite: dimensions, arcs and"
                                          " overlaps were not audited -"
                                          " run DIMCHECK or COVERSCAN"
                                          " for those.  ")
                                  ""))
                        hdr dhdr (reverse lines) lite
                        minx miny maxx maxy)
     (setvar "CMDECHO" oldecho)
     (princ (strcat "\n--- " name " complete (read-only) ---"
                    (if lite
                      "\nLite: dimensions, arcs and overlaps were not audited."
                      (strcat "\nDimensions: " (itoa nd) " scanned, "
                              (itoa ndbad) " with a stray point"
                              "\nArcs: " (itoa na) " scanned, "
                              (itoa nabad) " with an unattached end"
                              "\nOverlapping line pairs: "
                              (itoa (length olaps))))))
     (foreach l (car cres) (princ (strcat "\n" l)))
     (princ (strcat "\nReport written on layer " *cchk-report-layer*
                    "; nothing else was changed."))))
  (princ))


;; --- TUTORIALCOVERCHECK: a guided, hands-on introduction ------------
;; TUTORIALCOVERCHECK prints the full list of everything COVERCHECK /
;; COVERSCAN check, then - if you say yes - builds a small demo scene
;; in this drawing (tagged so TUTORIALCOVERCHECKCLEAN can remove it
;; again) so you can window-select it and run COVERCHECK for real and
;; watch every step happen exactly as it would on a real sheet: an
;; off-object dimension point, a detached arc end, a pair of
;; overlapping lines, a concave pool corner that needs a pad, and a
;; Cover Details block whose Overlap/Spacing were set wrong on purpose
;; so you see a real SUGGEST line. The Replacement Disclaimer block is
;; deliberately left out of the demo, so the live Yes/No + point-at-it
;; prompt fires for real too.

(defun cchk:tut-checklist ()
  (princ "\n\n=== What COVERCHECK / COVERSCAN check ===")
  (princ (strcat "\n(this file: " *cchk-version* ")"))
  (princ "\n\nDIMENSIONS - each linear/aligned dimension's two definition")
  (princ "\n  points are checked against nearby geometry; an off-object point")
  (princ "\n  is offered Move (snap it), Keep (leave it), or Pick (place it")
  (princ "\n  yourself). You then confirm the dimension itself is correct;")
  (princ "\n  No recolours it red.")
  (princ "\n\nARCS - each arc's two endpoints get the same Move/Keep/Pick")
  (princ "\n  audit against nearby geometry; a moved endpoint recolours the")
  (princ "\n  arc magenta.")
  (princ "\n\nOVERLAPPING LINES - collinear LINEs that run on top of each")
  (princ "\n  other are found and offered Merge (into one line, cyan), Flag")
  (princ "\n  (cyan, fix by hand), or Leave (intentional).")
  (princ (strcat "\n\nPOOL OUTLINE & AREA - everything on layer '" *cchk-pool-layer*
                 "' with fully"))
  (princ "\n  ByLayer properties (a closed polyline, a circle, or the same shape")
  (princ "\n  exploded into lines/arcs) is chained into the pool's outline; its")
  (princ "\n  area (sq ft) and straight/arc segment mix are reported. An")
  (princ "\n  outline with gaps or extra closed loops is flagged AMBIGUOUS.")
  (princ (strcat "\n\nCOVER DETAILS - the '" *cchk-details-block*
                 "' block's OVERLAP"))
  (princ "\n  (12\"/15\"/18\") and SPACING (NxN) values are checked against what")
  (princ "\n  the pool's shape and size call for; a disagreement, blank, or")
  (princ "\n  unreadable value is SUGGESTED against - never rewritten.")
  (princ (strcat "\n\nCOVER LAYER = POLYLINES - anything on layer '"
                 *cchk-cover-layer* "' that"))
  (princ "\n  isn't a polyline is called out.")
  (princ "\n\nOVERLAP NA <-> DASHED OUTLINE - an NA overlap means no")
  (princ (strcat "\n  dashed polyline may sit on layer '" *cchk-pool-layer*
                 "'; any stated"))
  (princ "\n  overlap demands one - unless a \"Pool Size Shown\" note is")
  (princ "\n  present, meaning no drawn cover is expected at all.")
  (princ (strcat "\n\n\"" *cchk-pool-note* "\" / \"" *cchk-spa-note* "\" - with"))
  (princ (strcat "\n  nothing on layer '" *cchk-cover-layer*
                 "', the pool note must be"))
  (princ "\n  somewhere in the selection; with a cover drawn, it must NOT be.")
  (princ "\n  Finding both the pool note AND the spa note together is an")
  (princ "\n  error - only one size can be shown.")
  (princ (strcat "\n\nREPLACEMENT DISCLAIMER - the '" *cchk-repl-block*
                 "' block should"))
  (princ "\n  be selected; if it isn't (and no pool-size note explains why")
  (princ "\n  not), COVERCHECK asks whether this is a replacement and, if")
  (princ "\n  so, asks you to point at the block elsewhere in the drawing.")
  (princ "\n\nPADS - the pool outline is run through PADDLE's concave-")
  (princ (strcat "\n  feature hunt at " (rtos *cchk-pad-size* 2 0)
                 "\": every inside corner or tight"))
  (princ "\n  concave arc with no pad already nearby is SUGGESTED and")
  (princ "\n  circled - unless this is a replacement, the Overlap is NA, or")
  (princ "\n  a cover is drawn, in which case pads are not sized from the")
  (princ "\n  outline at all.")
  (princ "\n\nEverything lands in one COVERCHECK REPORT (or COVERSCAN REPORT")
  (princ "\nfor a read-only pass) placed beside the drawing, with anything")
  (princ "\nneeding a second look shown in red.")
  (princ))

;; --- demo-scene builders (all tagged "TUTORIAL" for cleanup) --------

(defun cchk:tut-label (pt height str)
  (if (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                     (cons 8 *cchk-tut-layer*)
                     '(100 . "AcDbText")
                     (cons 10 pt) (cons 40 height) (cons 1 str)))
    (cchk:tag (entlast) "TUTORIAL")))

(defun cchk:tut-line (p1 p2 layer)
  (if (entmake (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 layer)
                     '(100 . "AcDbLine") (cons 10 p1) (cons 11 p2)))
    (cchk:tag (entlast) "TUTORIAL")))

(defun cchk:tut-arc (cen r sa ea layer)
  (if (entmake (list '(0 . "ARC") '(100 . "AcDbEntity") (cons 8 layer)
                     '(100 . "AcDbCircle") (cons 10 cen) (cons 40 r)
                     (cons 50 sa) (cons 51 ea)))
    (cchk:tag (entlast) "TUTORIAL")))

(defun cchk:tut-poly (verts layer / dxf v)
  ;; VERTS a list of (x y) pairs; always closed
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
                  '(100 . "AcDbPolyline") (cons 90 (length verts)) '(70 . 1)))
  (foreach v verts (setq dxf (append dxf (list (list 10 (car v) (cadr v))))))
  (if (entmake dxf) (cchk:tag (entlast) "TUTORIAL")))

;; the demo "Cover Details" block: a minimal block with OVERLAP and
;; SPACING attributes, built only when the drawing has no block by
;; that name yet (never redefines an existing real one)
(defun cchk:tut-details-block (name / h)
  (setq h 6.0)
  (entmake (list '(0 . "BLOCK") (cons 2 name) '(10 0.0 0.0 0.0) '(70 . 0)))
  (entmake (list '(0 . "ATTDEF") '(100 . "AcDbEntity") (cons 8 "0")
                 '(100 . "AcDbText") (cons 10 (list 0.0 0.0 0.0)) (cons 40 h)
                 (cons 1 "12\"") '(100 . "AcDbAttribute")
                 (cons 2 "OVERLAP") (cons 3 "Overlap: ") (cons 70 0)))
  (entmake (list '(0 . "ATTDEF") '(100 . "AcDbEntity") (cons 8 "0")
                 '(100 . "AcDbText") (cons 10 (list 0.0 (- h) 0.0)) (cons 40 h)
                 (cons 1 "5x5") '(100 . "AcDbAttribute")
                 (cons 2 "SPACING") (cons 3 "Spacing: ") (cons 70 0)))
  (entmake '((0 . "ENDBLK")))
  (tblsearch "BLOCK" name))

;; inserts a Cover Details demo instance with OVVAL/SPVAL as its
;; attribute answers; returns the new INSERT, or nil if it couldn't
;; be built (a stuck/odd command sequence is not silently ignored)
(defun cchk:tut-insert-details (pt ovval spval
                                 / oldattdia oldattreq oldfiledia pre new)
  (if (not (tblsearch "BLOCK" *cchk-details-block*))
    (cchk:tut-details-block *cchk-details-block*))
  (setq oldattdia  (getvar "ATTDIA")
        oldattreq  (getvar "ATTREQ")
        oldfiledia (getvar "FILEDIA"))
  (setvar "ATTDIA" 0) (setvar "ATTREQ" 1) (setvar "FILEDIA" 0)
  (setq pre (entlast))
  (vl-catch-all-apply
    '(lambda ()
       (command "_.-INSERT" *cchk-details-block* pt "1" "1" "0" ovval spval "")) '())
  (setvar "ATTDIA" oldattdia) (setvar "ATTREQ" oldattreq) (setvar "FILEDIA" oldfiledia)
  (setq new (if pre (entnext pre) (entnext)))
  (if (and new (entget new) (= "INSERT" (cdr (assoc 0 (entget new)))))
    (progn (cchk:tag new "TUTORIAL") new)))

;; the whole demo scene, anchored at BP (WCS, z=0). Each piece is
;; independent - one failing (e.g. no DASHED linetype available)
;; never stops the rest from being built.
(defun cchk:tut-build (bp / bx by oldfiledia oldosmode pre newdim detpt ins)
  (setq bx (car bp) by (cadr bp))
  (cal:ensure-layer *cchk-pool-layer* 7)
  (cal:ensure-layer *cchk-tut-layer* 5)

  ;; pool outline: an L-shape, ByLayer, exactly one concave (inside)
  ;; corner, area well under 1,200 sq ft (wants 12" overlap, 5x5)
  (cchk:tut-poly
    (list (list bx by) (list (+ bx 180.0) by)
          (list (+ bx 180.0) (+ by 72.0)) (list (+ bx 108.0) (+ by 72.0))
          (list (+ bx 108.0) (+ by 120.0)) (list bx (+ by 120.0)))
    *cchk-pool-layer*)
  (princ "\n  Built: pool outline (L-shape, one inside corner) on layer '")
  (princ *cchk-pool-layer*) (princ "'.")

  ;; a dashed cover outline on the same layer, so the NA/dashed check
  ;; has something to find (skips cleanly if DASHED can't be loaded)
  (setq oldfiledia (getvar "FILEDIA"))
  (setvar "FILEDIA" 0)
  (vl-catch-all-apply '(lambda () (command "_.-LINETYPE" "_Load" "DASHED" "acad.lin" "")) '())
  (setvar "FILEDIA" oldfiledia)
  (if (tblsearch "LTYPE" "DASHED")
    (progn
      (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                     (cons 8 *cchk-pool-layer*) (cons 6 "DASHED")
                     '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                     (list 10 (+ bx 6.0) (+ by 6.0))
                     (list 10 (+ bx 174.0) (+ by 6.0))
                     (list 10 (+ bx 174.0) (+ by 66.0))
                     (list 10 (+ bx 6.0) (+ by 66.0))))
      (cchk:tag (entlast) "TUTORIAL")
      (princ "\n  Built: dashed cover outline on the pool layer."))
    (princ "\n  Skipped: could not load the DASHED linetype - the dashed-outline check has nothing to find in this demo."))

  ;; Cover Details block, Overlap/Spacing set WRONG on purpose (this
  ;; pool wants 12"/5x5; the block says 15"/3x3) so the report shows
  ;; a real SUGGEST line instead of a bland pass
  (setq detpt (list (+ bx 210.0) (+ by 60.0) 0.0))
  (if (tblsearch "BLOCK" *cchk-details-block*)
    (princ (strcat "\n  Skipped: a '" *cchk-details-block*
                   "' block already exists in this drawing - not redefining it."))
    (progn
      (setq ins (cchk:tut-insert-details detpt "15\"" "3x3"))
      (if ins
        (princ "\n  Built: 'Cover Details' block (Overlap/Spacing set wrong on purpose).")
        (princ "\n  Skipped: could not insert the 'Cover Details' demo block (-INSERT did not complete as expected)."))))

  ;; an off-object dimension point: point 1 sits 4" below the pool's
  ;; true bottom-left corner instead of on it
  (setq oldosmode (getvar "OSMODE"))
  (setvar "OSMODE" 0)
  (setq pre (entlast))
  ;; the args list is required - without it vl-catch-all-apply itself
  ;; errors instead of catching, killing the tutorial at this line
  (vl-catch-all-apply
    '(lambda ()
       (command "_.DIMLINEAR"
                (list bx (- by 4.0) 0.0)
                (list (+ bx 180.0) by 0.0)
                (list (+ bx 90.0) (- by 40.0) 0.0)))
    nil)
  (setvar "OSMODE" oldosmode)
  (setq newdim (if pre (entnext pre) (entnext)))
  (if (and newdim (entget newdim) (= "DIMENSION" (cdr (assoc 0 (entget newdim)))))
    (progn (cchk:tag newdim "TUTORIAL")
           (princ "\n  Built: dimension with one point 4\" off the pool edge."))
    (princ "\n  Skipped: could not create the demo dimension (DIMLINEAR did not complete as expected)."))

  ;; a detached arc end: the arc's start point sits 3" from the
  ;; nearest line end instead of touching it
  (cchk:tut-arc (list (+ bx 220.0) (+ by 150.0) 0.0) 20.0 0.0 pi *cchk-tut-layer*)
  (cchk:tut-line (list (+ bx 240.0) (+ by 147.0)) (list (+ bx 280.0) (+ by 147.0)) *cchk-tut-layer*)
  (princ "\n  Built: arc with a detached end, 3\" from the nearest line.")

  ;; two overlapping lines
  (cchk:tut-line (list bx (+ by 250.0)) (list (+ bx 100.0) (+ by 250.0)) *cchk-tut-layer*)
  (cchk:tut-line (list (+ bx 60.0) (+ by 250.0)) (list (+ bx 160.0) (+ by 250.0)) *cchk-tut-layer*)
  (princ "\n  Built: two overlapping lines.")

  ;; callouts
  (cchk:tut-label (list bx (+ by 290.0) 0.0) 6.0
    "COVERCHECK TUTORIAL DEMO - window-select everything here, then type COVERCHECK (or COVERSCAN to preview).")
  (cchk:tut-label (list (+ bx 100.0) (+ by 78.0) 0.0) 4.0 "(1) inside corner -> pad SUGGESTED")
  (cchk:tut-label (list (+ bx 20.0) (- by 55.0) 0.0) 4.0 "(2) dimension point 4\" off the edge")
  (cchk:tut-label (list (+ bx 195.0) (+ by 168.0) 0.0) 4.0 "(3) arc end detached 3\"")
  (cchk:tut-label (list bx (+ by 258.0) 0.0) 4.0 "(4) overlapping lines")
  (cchk:tut-label (list (+ bx 195.0) (+ by 78.0) 0.0) 4.0 "(5) Cover Details set wrong on purpose")
  T)

(defun c:TUTORIALCOVERCHECK ( / *error* oldecho att0 req0 fil0 undo-open bp)
  (defun *error* (msg)
    (if undo-open (progn (setvar "CMDECHO" 0) (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))))
    (if oldecho (setvar "CMDECHO" oldecho))
    ;; cchk:tut-insert-details drops ATTDIA/ATTREQ/FILEDIA round its
    ;; -INSERT and puts them back inline; a throw inside that window
    ;; left FILEDIA at 0, which turns every OPEN into a command-line
    ;; prompt -- so the tutorial holds the three itself
    (if att0 (setvar "ATTDIA" att0))
    (if req0 (setvar "ATTREQ" req0))
    (if fil0 (setvar "FILEDIA" fil0))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTUTORIALCOVERCHECK error: " msg)))
    (princ))

  (cchk:tut-checklist)

  (if (cal:ask-yn "\nBuild a small demo scene in this drawing so you can watch it live?" "Yes")
    (progn
      (setq bp (getpoint "\nPick a base point for the demo, clear of your real geometry <0,0>: "))
      (if (null bp) (setq bp (list 0.0 0.0 0.0)))
      (setq oldecho (getvar "CMDECHO")
            att0 (getvar "ATTDIA") req0 (getvar "ATTREQ") fil0 (getvar "FILEDIA"))
      (setvar "CMDECHO" 0)
      ;; only when undo is recording - _Begin in a drawing with UNDO
      ;; off (bit 1 of UNDOCTL clear) errors out of the command
      (if (= 1 (logand 1 (getvar "UNDOCTL")))
        (progn
          (command "_.UNDO" "_Begin")
          (setq undo-open T)))
      (princ "\n--- Building the demo scene ---")
      (cchk:tut-build bp)
      (command "_.UNDO" "_End")
      (setq undo-open nil)
      (setvar "CMDECHO" oldecho)
      (command "_.ZOOM" "_Window"
               (trans (list (- (car bp) 20.0) (- (cadr bp) 60.0) 0.0) 0 1)
               (trans (list (+ (car bp) 300.0) (+ (cadr bp) 310.0) 0.0) 0 1))
      (princ "\n\nDemo scene built. Window-select all of it and type COVERCHECK")
      (princ "\n(or COVERSCAN to preview read-only first) to watch every check")
      (princ "\nrun on real geometry, one step at a time.")
      (princ "\nWhen you're done, type TUTORIALCOVERCHECKCLEAN to erase the demo -")
      (princ "\nit only removes what the tutorial built (tagged), plus whatever")
      (princ "\nreport and markers COVERCHECK/COVERSCAN left behind on it.")))
  (princ))

(defun c:TUTORIALCOVERCHECKCLEAN ( / *error* undo-open ss i e xd n)
  ;; entdel/entmod over the whole drawing was N undos deep and
  ;; had no handler at all -- now one group, closed on both exits,
  ;; and a cancel that says nothing
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTUTORIALCOVERCHECKCLEAN error: " msg)))
    (princ))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") (setq undo-open T)))
  ;; erases everything TUTORIALCOVERCHECK built (tagged "TUTORIAL"),
  ;; then clears any COVERCHECK/COVERSCAN report and markers left on
  ;; it too, so a demo run leaves nothing behind
  (setq ss (ssget "_X" '((-3 ("COVERCHECK")))) n 0 i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            xd (cchk:xd e))
      (if (= (cdr (assoc 1000 xd)) "TUTORIAL")
        (progn (entdel e) (setq n (1+ n))))))
  (cchk:clear-old)
  (if (> n 0)
    (princ (strcat "\nTUTORIALCOVERCHECKCLEAN: removed " (itoa n)
                   " demo item(s), plus any report/markers left on them."))
    (princ "\nTUTORIALCOVERCHECKCLEAN: nothing tagged TUTORIAL was found."))
  (if undo-open (progn (command "_.UNDO" "_End") (setq undo-open nil)))
  (princ))

(defun c:COVERCHECKVER ()
  (princ (strcat "\nThis file's COVERCHECK / COVERSCAN: " *cchk-version*))
  (princ "\n(covercheck.lsp and its dated covercheck_MMDDYY_REV##.lsp twin should always match this.)")
  (princ))

;; the pre-standard name, kept as an alias - STANDARDS section 5 names
;; the version reporter TOOLNAMEVER, and muscle memory keeps the old one
(defun c:COVERCHECKVERSION () (c:COVERCHECKVER))

(princ (strcat "\ncovercheck.lsp loaded (" *cchk-version* ") - COVERCHECK reviews dims, arcs & the cover rules,"))
(princ "\n  COVERSCAN reports everything read-only, COVERCHECKRESCUE undoes COVERCHECK's marks.")
(princ "\n  TUTORIALCOVERCHECK walks a new user through it; COVERCHECKVER prints this file's version.")
(princ)
