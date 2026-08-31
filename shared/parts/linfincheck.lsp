;;; ------------------------------------------------------------------
;;;  linfincheck.lsp -- LINFINCHECK: the full liner-finish drawing QA
;;;
;;;  Grew from a dimension/arc auditor (based on check_drawing.lsp) into
;;;  a guided, one-at-a-time review of the whole title block: dims,
;;;  arcs, overlapping lines, steps and their side views, wall height,
;;;  the liner pattern, and the title block border. For just the first
;;;  three of those -- the quick pass someone wants without going
;;;  through the whole liner-finish gauntlet -- see dimcheck.lsp
;;;  instead; it shares this file's Move/Keep/Pick and report machinery
;;;  but leaves out steps, wall height, liner and border. Type
;;;  LINFINCHECK, then:
;;;
;;;  1. You are asked to highlight the drawing (any selection).
;;;     Everything selected is greyed out so only the item under
;;;     review stands out.
;;;
;;;  2. Dimensions are reviewed ONE AT A TIME, in a fixed marching
;;;     order: grouped by dimension style -- "STANDARD", then "SIDE
;;;     STANDARD", then "STANDARD INCHES", then "CROSS DIMENSIONS",
;;;     then whatever styles are left (tune *lfc-style-order*) --
;;;     and inside each group left to right, top to bottom (row by
;;;     row, like reading). Each dimension is zoomed to, shown in
;;;     its own colour and highlighted while the rest stays grey.
;;;     For linear/aligned dimensions the two definition points are
;;;     audited first: a point that does not sit on any object is
;;;     shown where LINFINCHECK thinks it belongs, with BOTH spots
;;;     marked on screen and spelled out so there is no doubt which
;;;     is which --
;;;         a RED X   where you drew it,
;;;         a GREEN + where we would move it, joined by a line.
;;;     You then choose, one point at a time:
;;;         Enter / M  ->  MOVE it onto the nearest object (green +)
;;;         K          ->  KEEP it exactly where you drew it (red X);
;;;                        the point is put back and nothing changes
;;;         P          ->  PICK the spot yourself
;;;     A construction line (XLINE) is drawn through the dimension's
;;;     original points on layer LINFINCHECK-CONSTRUCTION so you can see
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
;;;  5. STEP / STAIRCASE check. Groups of 3+ parallel lines stacked
;;;     less than 18 units apart (18" in inch drawings -- tune
;;;     *lfc-step-maxgap*) look like steps. When such patterns are
;;;     found, LINFINCHECK first looks for a SIDE VIEW in the selection
;;;     (a side view reads as two step patterns at right angles to
;;;     each other -- treads + risers -- in the same spot, each one
;;;     marching along like a profile rather than sitting stacked).
;;;     Benches count: their profile is only two treads deep, so
;;;     side-view halves are found down to *lfc-bench-minlines*
;;;     while the "are these steps?" prompt still needs a full-size
;;;     *lfc-step-minlines* pattern. Whatever the side view belongs
;;;     to -- stairs or a bench -- its overall height is confirmed
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
;;;     A generic block still listing EVERY option ("Bead", "Flaps",
;;;     "Rod Pockets", "No Attachment" - tune *lfc-attach-options*)
;;;     means nobody picked one yet. That is only acceptable when the
;;;     drawing carries a "to be secured?" note (tune
;;;     *lfc-secured-phrase*) asking whoever it goes to; with the
;;;     note it reads as waiting on the customer, without it the
;;;     report says to add one. A block naming one option - or a
;;;     combination like Bead + Rod Pockets - counts as decided.
;;;     When the attachment style is "BEAD Step Attachment", every
;;;     plan-view step pattern must also have something drawn on
;;;     layer "Bead Track" (tune *lfc-bead-layer*) within
;;;     *lfc-bead-dist* of it. The whole drawing is searched, not
;;;     just the selection. The side view itself is exempt -- bead
;;;     track is only demanded next to the plan-view steps. Patterns
;;;     with nothing nearby are called out in the report.
;;;     The OVERALL HEIGHT of the steps is confirmed too: measured
;;;     from the side view's geometry (its total rise), or typed /
;;;     picked as two points when the side view was not auto-found,
;;;     and compared against the WallHt attribute of the "Tech
;;;     Title" block (found space-insensitively, drawing-wide; tune
;;;     *lfc-title-block* / *lfc-wallht-tag*). Heights written as
;;;     40'', 3'-4'', 3' 4 1/2" or 40.5 are all understood, and a
;;;     label is ignored, so the attribute may read "Finished Wall
;;;     Ht = 40''" and still measure 40. The WallHt itself is
;;;     validated whenever a Tech Title exists, steps or not:
;;;       - several heights at once ("0'', 35 3/4'', 37 1/4''") ->
;;;         CHECK THE WALL HEIGHT, side view left alone;
;;;       - a lone 0'' (below *lfc-min-wallht*) -> NONSENSICAL,
;;;         fix the title block - the dim is never blamed for it;
;;;       - "?" -> fine only when a "Wall height" note (tune
;;;         *lfc-ask-phrase*) asks the customer somewhere in the
;;;         drawing; otherwise the report says to add one;
;;;       - a single sensible value ("35 3/4''") -> no warning. When the side view carries
;;;     its own overall-height dimension (the one whose definition
;;;     points span the full rise), that dimension is what gets
;;;     compared -- and if it disagrees with WallHt, or its text was
;;;     overridden to disagree with the geometry it spans, it is
;;;     MARKED RED AUTOMATICALLY and reported. Any difference beyond
;;;     *lfc-height-tol* is reported in red as a MISMATCH.
;;;     Two title-block answers give nothing to check against, so
;;;     the side view is LEFT ALONE (never marked red) in both:
;;;       - "Finished Wall Ht = Varies" -- the height genuinely
;;;         varies; the report just notes it.
;;;       - several heights at once, e.g. "= 0'', 40'', 45''" -- the
;;;         report tells you to CHECK THE WALL HEIGHT in the title
;;;         block. A compound height ( 3'-4'' ) is still one value,
;;;         not several.
;;;
;;;  6. TECH TITLE DATE. The "Date" attribute of the Tech Title block
;;;     (same block as WallHt; tune *lfc-date-tag*) is checked whenever
;;;     a Tech Title exists, steps or not: it must read a real calendar
;;;     date in MM/DD/YYYY form -- two digits, slash, two digits, slash,
;;;     four digits, month 01-12, and a day valid for that month (leap
;;;     Februaries included). Missing, blank, wrong format ("5/1/24",
;;;     "05-01-2024"), an out-of-range month/day, or a made-up day like
;;;     "02/30" is reported in red with what is wrong. A well-formed
;;;     calendar date that is NOT TODAY is reported too - a sheet going
;;;     out under an old date is the mistake that catches. Only
;;;     today's date, written MM/DD/YYYY, is a quiet OK; with no Tech
;;;     Title in reach the report says the date was not checked.
;;;
;;;  7. LINER MATERIAL check. The selection must hold a block named
;;;     (or containing the words) "Liner Material" / "Liner Material
;;;     with Step". Missing -> reported. Each one found is scanned
;;;     for the standalone words "NOT" and "ERROR" in its attributes
;;;     and text (e.g. "Not Selected", "Not Included", "#ERROR");
;;;     A field that carries one of those words was never really
;;;     filled in ("Not Supplied", "#ERROR"), so LINFINCHECK WIPES IT
;;;     BACK TO BLANK and says which fields it cleared - the pattern
;;;     block reads clean afterwards. Only attribute VALUES are
;;;     cleared: the block's own labels ("Pattern:", "Wall:",
;;;     "Floor:", "Step:") live in its definition and are never
;;;     touched, and a real pattern name is left alone. A bad word
;;;     sitting in the block's static text cannot be cleared, so it
;;;     is reported instead. LINFINSCAN, being read-only, reports these
;;;     as NEEDS WIPING and changes nothing. The liner pattern must also agree with how the
;;;     steps are built:
;;;       - a FIBERGLASS STEP anywhere in the highlighted area (as
;;;         text, a block, or the layer things sit on -- see
;;;         *lfc-fgstep-words*) is its own unit, so the liner must
;;;         NOT carry a Step. One that does is reported.
;;;       - otherwise, when steps are drawn, the liner must cover
;;;         them: no liner block carrying a "Step" section (the
;;;         "Liner Material with Step" variant) is reported.
;;;
;;;  8. TITLE BLOCK BORDER. The outer drawing on layer "border"
;;;     (tune *lfc-border-layer*) must be the nominal sheet --
;;;     58'-8" wide by 45'-3 5/8" tall -- or a scaled-UP multiple of
;;;     it. Anything smaller is reported in red as
;;;         "Title block should not be SCALED DOWN for Liners".
;;;     A border out of proportion (scaled unevenly) is reported
;;;     separately as STRETCHED, and a missing border as NO BORDER.
;;;     Everything on the layer is measured together, so a frame
;;;     drawn as one polyline and one drawn as four lines both
;;;     measure the same. The selection is used when it holds the
;;;     border, otherwise the whole drawing is searched.
;;;
;;;  8a. FEET AND INCHES. Every text box in the selection - TEXT,
;;;     MTEXT and the ATTRIB values on blocks - must state its inches
;;;     wherever it states feet: 5' is flagged, 5'-0", 3'-2" and a
;;;     plain 40" are fine. A feet mark is an apostrophe straight
;;;     after a digit, so "Water's Edge" is prose and never flagged.
;;;     This one runs in LITELINFINSCAN too.
;;;
;;;  8b. DIMENSION LAYER. Every dimension must sit on the
;;;     "DIMENSION" layer (tune *lfc-dim-layer*). Any that do not are
;;;     counted, the layers they landed on are named, and the report
;;;     tells you to run CDIM (tune *lfc-dimfix-cmd*) to move them.
;;;     This one runs in LITELINFINSCAN too.
;;;
;;;  9. A LINFINCHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;     drawing on layer LINFINCHECK-REPORT, sized from the drawing's
;;;     extents so it sits to scale next to it.  The MAIN sheet leads
;;;     with what matters to the liner finish itself: a large title,
;;;     the date and version, a verdict line (ALL CLEAR, or the count
;;;     of red lines), the colour legend, a SUMMARY dashboard, then
;;;     the findings under underlined section headings (STEPS & SIDE
;;;     VIEWS, WALL HEIGHT, THE LINER, ...).  The DIMCHECK-style
;;;     findings -- every dimension with its measured distance, every
;;;     arc, every overlapping line pair with its overlap length -- go
;;;     in a separate DIMENSION AUDIT column to the RIGHT of the main
;;;     sheet, so the liner verdicts lead and the mechanical audit
;;;     reads alongside.  Any line describing something questionable
;;;     or that needs looking over (a flagged/wrong item, a missing
;;;     block, a "NOT" find, an "add ..." note, a skipped check) is
;;;     coloured RED in the report; everything that checked out stays
;;;     the report's normal colour and is drawn at *lfc-green-scale*
;;;     (3/4) of the red text's height, so the problems are the big
;;;     lines on the sheet.
;;;
;;;  LITELINFINSCAN is LINFINSCAN minus the DIMCHECK-style pass: no
;;;     dimension, arc or overlap audit and no DIMENSION AUDIT
;;;     column - just the liner-finish rules, for a drawing DIMCHECK
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
;;;  - Rerunning LINFINCHECK replaces the previous report and marker
;;;    lines instead of stacking a second copy on top.
;;;  - Original colours are stashed in xdata before greying. If a
;;;    crash or kill ever leaves the drawing grey, LINFINCHECKRESCUE
;;;    restores every stashed colour and clears LINFINCHECK's report
;;;    and markers (flag colours included -- it is the full reset).
;;;  - With several Tech Title blocks on the sheet, the one nearest
;;;    the checked area is used; titles disagreeing on WallHt are
;;;    called out in red.
;;; ------------------------------------------------------------------

;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;

(vl-load-com)

;; ---- configuration -------------------------------------------------
(setq *lfc-version* "v2.4")        ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it

(defun c:LINFINCHECKVER ()
  (princ (strcat "\nLINFINCHECK " *lfc-version*))
  (princ))

;; --- tunables ------------------------------------------------------
(setq *lfc-tol*          1.0e-4)  ; max gap (drawing units) that still counts as attached
(setq *lfc-grey-color*   8)       ; grey used to fade out everything not under review
(setq *lfc-flag-color*   1)       ; red: dimensions you answered "No" to
(setq *lfc-arc-color*    6)       ; magenta: arcs whose endpoints were moved
(setq *lfc-olap-color*   4)       ; cyan: merged or flagged overlapping lines
(setq *lfc-olap-fuzz*    1.0e-4)  ; max sideways offset that still counts as "same line"
(setq *lfc-step-maxgap*  18.0)    ; steps: max tread spacing (drawing units; 18 = 18" when 1 unit = 1")
(setq *lfc-step-minlines* 3)      ; steps: how many stacked parallel lines look like steps
(setq *lfc-bench-minlines* 2)     ; side view: a bench profile is only two treads deep
(setq *lfc-step-angtol*  1.0)     ; steps: parallelism tolerance (degrees)
(setq *lfc-bead-layer*   "Bead Track") ; layer bead track must be drawn on
(setq *lfc-bead-dist*    18.0)    ; how close bead track must be to plan-view steps (units)
(setq *lfc-title-block*  "Tech Title") ; title block holding the wall height (spaces optional)
(setq *lfc-wallht-tag*   "WallHt")     ; attribute tag carrying the wall height
(setq *lfc-date-tag*     "Date")       ; attribute tag carrying the drawing date
(setq *lfc-height-tol*   0.25)    ; steps height vs WallHt: allowed difference (units)
(setq *lfc-min-wallht*   1.0)     ; a WallHt below this is NONSENSICAL (0'' walls do not exist)
(setq *lfc-ask-phrase*   "Wall height") ; the question text expected when WallHt is "?"
;; the generic Step Attachment block lists every option with a box; if
;; ALL of them are still showing, nobody picked one, and the drawing
;; must carry the question note instead
(setq *lfc-attach-options*
      '("Bead" "Flaps" "Rod Pockets" "No Attachment"))
(setq *lfc-secured-phrase* "to be secured")

;; dimension styles are reviewed in this order; styles not listed
;; come afterwards ("whatever else is left"), still left-to-right
(setq *lfc-style-order*
      '("STANDARD" "SIDE STANDARD" "STANDARD INCHES" "CROSS DIMENSIONS"))
;; every dimension belongs on this layer; CDIM is the command that
;; moves the strays there, and is what the report tells you to run
(setq *lfc-dim-layer*   "DIMENSION")
(setq *lfc-dimfix-cmd*  "CDIM")
(setq *lfc-constr-layer* "LINFINCHECK-CONSTRUCTION")
(setq *lfc-constr-color* 2)       ; yellow
(setq *lfc-green-scale*  0.75)    ; report: all-clear text height, as a fraction of the red text
(setq *lfc-block-depth*  3)       ; how many levels of nested blocks to search for names/text
(setq *lfc-orig-color*   1)       ; red X: where you drew the point
(setq *lfc-sugg-color*   3)       ; green +: where LINFINCHECK would move it
;; title block border: nominal 58'-8" x 45'-3 5/8", or a scaled-UP multiple
(setq *lfc-border-layer* "border")
(setq *lfc-border-w*     704.0)   ; 58'-8"     in drawing units (1 unit = 1 inch)
(setq *lfc-border-h*     543.625) ; 45'-3 5/8" in drawing units
(setq *lfc-border-tol*   0.005)   ; 0.5% slack on both the scale and the aspect ratio
(setq *lfc-fgstep-words*          ; a fiberglass step shows up under any of these
      '("Fiberglass Step" "FG Step"))
;; a liner pattern field carrying one of these was never really filled
;; in ("Not Supplied", "#ERROR") - LINFINCHECK wipes it back to blank
(setq *lfc-badwords*     '("NOT" "ERROR"))
(setq *lfc-report-layer* "LINFINCHECK-REPORT")
(setq *lfc-report-color* 3)       ; green
(setq *lfc-zoom-margin*  0.75)    ; empty space around the zoomed item (fraction of its size)
(setq *lfc-report-chars* 45.0)    ; report column width, in text heights
(setq *lfc-ask-all-arc-ends* nil) ; T = confirm EVERY arc endpoint, even already-attached ones

;; entity types dimension points and arc ends may attach to
(setq *lfc-curve-types*
      '("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"))

;; --- safety: xdata tags, colour stash, layer locks -----------------

(defun lfc:regapp ()
  (if (not (tblsearch "APPID" "LINFINCHECK"))
    (regapp "LINFINCHECK")))

(defun lfc:xd (ent / g)
  ;; LINFINCHECK's xdata groups on ent, nil when none
  (setq g (assoc -3 (entget ent '("LINFINCHECK"))))
  (if g (cdadr g)))

(defun lfc:tag (ent kind / ed)
  ;; stamp a LINFINCHECK-created entity (report, marker line) so a rerun
  ;; or LINFINCHECKRESCUE can find and clear it
  (lfc:regapp)
  (setq ed (entget ent '("LINFINCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "LINFINCHECK" (cons 1000 kind))))))))

(defun lfc:stash-color (ent col / ed)
  ;; remember the entity's own colour in xdata so LINFINCHECKRESCUE can
  ;; put it back even after a crash; an existing stash (from an
  ;; interrupted run - the TRUE original) is never overwritten
  (lfc:regapp)
  (setq ed (entget ent '("LINFINCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "LINFINCHECK"
                                            '(1000 . "COLOR")
                                            (cons 1071 col))))))))

(defun lfc:unstash (ent / ed)
  ;; drop LINFINCHECK's xdata once the run has restored things itself
  (setq ed (entget ent '("LINFINCHECK")))
  (if (and ed (assoc -3 ed))
    (entmod (subst (list -3 (list "LINFINCHECK")) (assoc -3 ed) ed))))

(defun lfc:clear-old (/ ss2 i e xd n)
  ;; erase the report and marker lines left by an earlier LINFINCHECK
  ;; run, so a rerun replaces them instead of stacking on top
  (setq ss2 (ssget "_X" '((-3 ("LINFINCHECK")))) n 0 i 0)
  (if ss2
    (repeat (sslength ss2)
      (setq e  (ssname ss2 i)
            i  (1+ i)
            xd (lfc:xd e))
      (if (member (cdr (assoc 1000 xd)) '("REPORT" "XLINE"))
        (progn (entdel e) (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\n(Removed " (itoa n)
                   " report/marker item(s) from an earlier LINFINCHECK run.)"))))

(defun lfc:layer-locked-p (name / ld)
  (setq ld (tblsearch "LAYER" name))
  (and ld (= 4 (logand 4 (cdr (assoc 70 ld))))))

(defun lfc:set-layer-lock (name lock / ed old new)
  ;; set or clear a layer's locked flag; T when it actually changed
  (setq ed  (entget (tblobjname "LAYER" name))
        old (cdr (assoc 70 ed))
        new (if lock (logior old 4) (logand old (~ 4))))
  (if (/= old new)
    (progn (entmod (subst (cons 70 new) (assoc 70 ed) ed)) T)))

(defun lfc:dim-assoc-p (ent / found g)
  ;; T when the dimension carries persistent reactors - the mark of
  ;; an object-associative dim, whose definition points may re-anchor
  ;; on their own after being moved
  (foreach g (entget ent)
    (if (and (= 102 (car g)) (= "{ACAD_REACTORS" (cdr g)))
      (setq found T)))
  found)

(defun c:LINFINCHECKRESCUE ( / ss i e xd n)
  ;; the way out after a crash or interrupted run: puts back every
  ;; colour LINFINCHECK stashed (flag colours included) and removes its
  ;; report and marker lines
  (setq ss (ssget "_X" '((-3 ("LINFINCHECK")))) n 0 i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            xd (lfc:xd e))
      (cond
        ((member (cdr (assoc 1000 xd)) '("REPORT" "XLINE"))
         (entdel e)
         (setq n (1+ n)))
        ((assoc 1071 xd)
         (lfc:set-color e (cdr (assoc 1071 xd)))
         (lfc:unstash e)
         (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\nLINFINCHECKRESCUE: restored or removed " (itoa n) " item(s)."))
    (princ "\nLINFINCHECKRESCUE: nothing to restore - no LINFINCHECK markers in the drawing."))
  (princ))

;; --- small helpers -------------------------------------------------

(defun lfc:ent-color (ent / c)
  ;; the entity's explicit colour, 256 (ByLayer) when it has none
  (setq c (cdr (assoc 62 (entget ent))))
  (if c c 256))

(defun lfc:set-color (ent color / ed old)
  (setq ed  (entget ent)
        old (assoc 62 ed))
  (entmod (if old
            (subst (cons 62 color) old ed)
            (append ed (list (cons 62 color)))))
  (entupd ent))

(defun lfc:make-xline (p1 p2 / len)
  ;; infinite construction line through p1-p2 on the check layer,
  ;; tagged so reruns and LINFINCHECKRESCUE can clear it
  (setq len (distance p1 p2))
  (if (and (> len 1e-8)
           (entmake (list '(0 . "XLINE")
                          '(100 . "AcDbEntity")
                          (cons 8 *lfc-constr-layer*)
                          '(100 . "AcDbXline")
                          (cons 10 p1)
                          (cons 11 (mapcar '(lambda (x) (/ x len))
                                           (mapcar '- p2 p1))))))
    (lfc:tag (entlast) "XLINE")))

(defun lfc:closest-on (ent pt / res)
  ;; closest point on ent to pt; nil when ent is not curve-like
  (setq res (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (vl-catch-all-error-p res) nil res))

(defun lfc:nearest-curve (pt exclude cands / best bestd cp d e)
  ;; (ent closest-point distance) for the candidate closest to pt
  (foreach e cands
    (if (and (not (eq e exclude)) (setq cp (lfc:closest-on e pt)))
      (progn
        (setq d (distance pt cp))
        (if (or (null bestd) (< d bestd))
          (setq bestd d
                best  (list e cp d))))))
  best)

(defun lfc:curve-ends (ent / cl sp ep)
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

(defun lfc:closest-of (pt pts / best bestd d q)
  (foreach q pts
    (setq d (distance pt q))
    (if (or (null bestd) (< d bestd)) (setq bestd d best q)))
  best)

(defun lfc:nearest-end (pt exclude cands / best bestd d e q)
  ;; closest endpoint over every open candidate curve
  (foreach e cands
    (if (not (eq e exclude))
      (foreach q (lfc:curve-ends e)
        (setq d (distance pt q))
        (if (or (null bestd) (< d bestd)) (setq bestd d best q)))))
  best)

(defun lfc:ptstr (p)
  (strcat "(" (rtos (car p) 2 4) ", " (rtos (cadr p) 2 4) ")"))

(defun lfc:zoom-ent (ent / bb p1 p2 m)
  ;; zoom the current view onto ent with some breathing room
  (setq bb (cal:bbox-ent ent))
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *lfc-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

(defun lfc:zoom-2ents (e1 e2 / b1 b2 p1 p2 m)
  ;; zoom onto the combined box of two entities
  (setq b1 (cal:bbox-ent e1)
        b2 (cal:bbox-ent e2))
  (cond
    ((and b1 b2)
     (setq p1 (list (min (caar b1) (caar b2))
                    (min (cadar b1) (cadar b2)))
           p2 (list (max (caadr b1) (caadr b2))
                    (max (cadadr b1) (cadadr b2)))
           m  (* *lfc-zoom-margin*
                 (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
     (command "_.ZOOM" "_Window"
              (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
              (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))
    (b1 (lfc:zoom-ent e1))
    (b2 (lfc:zoom-ent e2))))

(defun lfc:stage (ent saved keep)
  ;; bring an entity back to its own colour for review -- unless it
  ;; already wears a LINFINCHECK marker colour it must not lose
  (if (and (entget ent) (not (member ent keep)))
    (lfc:set-color ent (cdr (assoc ent saved)))))

(defun lfc:unstage (ent keep)
  ;; send a reviewed entity back into the grey background
  (if (and (entget ent) (not (member ent keep)))
    (lfc:set-color ent *lfc-grey-color*)))

(defun lfc:mark-x (pt col / p s)
  ;; diagonal cross - marks WHERE YOU DREW IT
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (- (cadr p) s)) (list (+ (car p) s) (+ (cadr p) s)) col 1)
  (grdraw (list (- (car p) s) (+ (cadr p) s)) (list (+ (car p) s) (- (cadr p) s)) col 1))

(defun lfc:mark-plus (pt col / p s)
  ;; upright cross - marks WHERE LINFINCHECK WOULD PUT IT
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (cadr p)) (list (+ (car p) s) (cadr p)) col 1)
  (grdraw (list (car p) (- (cadr p) s)) (list (car p) (+ (cadr p) s)) col 1))

(defun lfc:mark-point (pt)
  ;; both strokes, for a point that is simply being pointed out
  (lfc:mark-x pt 2)
  (lfc:mark-plus pt 2))

(defun lfc:progress (what n total)
  (princ (strcat "\r  [" (itoa n) "/" (itoa total) "] " what "          ")))

(defun lfc:confirm-move (label orig sugg / ans newp)
  ;; The point has been put where LINFINCHECK thinks it belongs, but BOTH
  ;; spots are marked and spelled out so there is no doubt which is
  ;; which: a red X where you drew it, a green + where we would move
  ;; it, joined by a line. Returns
  ;;   'move - take our suggestion
  ;;   'keep - put it back exactly where you drew it
  ;;   <point> - a spot you picked yourself (current UCS)
  (lfc:mark-x    orig *lfc-orig-color*)
  (lfc:mark-plus sugg *lfc-sugg-color*)
  (if (> (distance orig sugg) 1e-8)
    (grdraw (trans orig 0 1) (trans sugg 0 1) *lfc-sugg-color* 1))
  (princ (strcat "\n  " label " - which spot is right?"
                 "\n    Keep = where you drew it   " (lfc:ptstr orig)
                 "  (red X)"
                 "\n    Move = onto nearest object " (lfc:ptstr sugg)
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

(defun lfc:mtext (ins height width text layer / e)
  ;; entmake an MTEXT, splitting text into 250-char DXF chunks
  (if (setq e (cal:mtext ins height width text layer))
    (lfc:tag e "REPORT")))

(defun lfc:border-box (ss / i e ed bb lo hi)
  ;; overall extents of everything on the border layer, so a frame
  ;; drawn as one polyline and one drawn as four separate lines both
  ;; measure the same
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            ed (entget e))
      (if (and ed
               (= (strcase (cdr (assoc 8 ed))) (strcase *lfc-border-layer*))
               (setq bb (cal:bbox-ent e)))
        (setq lo (if lo
                   (list (min (car lo) (caar bb)) (min (cadr lo) (cadar bb)))
                   (list (caar bb) (cadar bb)))
              hi (if hi
                   (list (max (car hi) (caadr bb)) (max (cadr hi) (cadadr bb)))
                   (list (caadr bb) (cadadr bb)))))))
  (if (and lo hi) (list lo hi)))

(defun lfc:border-verdict (bb / bw bh sw sh sc)
  ;; measure the border against the nominal sheet. Returns the report
  ;; sentence; the drawing may be the nominal size or any scaled-UP
  ;; multiple of it, but never smaller.
  (if (null bb)
    (strcat "NO BORDER found on layer '" *lfc-border-layer* "'")
    (progn
      (setq bw (- (car (cadr bb)) (car (car bb)))
            bh (- (cadr (cadr bb)) (cadr (car bb))))
      (if (or (<= bw 1e-6) (<= bh 1e-6))
        "border has no measurable size"
        (progn
          (setq sw (/ bw *lfc-border-w*)
                sh (/ bh *lfc-border-h*)
                sc (min sw sh))
          (cond
            ;; a border out of proportion is wrong whatever its size
            ((> (abs (- sw sh)) (* *lfc-border-tol* (max sw sh)))
             (strcat (rtos bw) " x " (rtos bh) " - STRETCHED out of proportion ("
                     (rtos sw 2 3) "x wide but " (rtos sh 2 3)
                     "x tall); nominal is " (rtos *lfc-border-w*) " x "
                     (rtos *lfc-border-h*)))
            ;; the one the user asked for by name
            ((< sc (- 1.0 *lfc-border-tol*))
             (strcat (rtos bw) " x " (rtos bh) " is only " (rtos sc 2 3)
                     "x the nominal " (rtos *lfc-border-w*) " x "
                     (rtos *lfc-border-h*)
                     " - Title block should not be SCALED DOWN for Liners"))
            ((< sc (+ 1.0 *lfc-border-tol*))
             (strcat (rtos bw) " x " (rtos bh) " - nominal size, OK"))
            (t
             (strcat (rtos bw) " x " (rtos bh) " - " (rtos sc 2 3)
                     "x the nominal size, OK"))))))))

(defun lfc:attn-p (s)
  ;; T when a report line describes something questionable or that
  ;; needs looking over / fixing, so the report renders it in red
  (wcmatch (strcase s)
    "*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO SIDE VIEW*,*NO 'STEP*,*NO BLOCK*,*WORD NOT*,*WORD ERROR*,* ADD *,*MISMATCH*,*NOT CONFIRMED*,*NOT ATTACHED*,*OVERLAP*,*CHECK THE WALL HEIGHT*,*FIBERGLASS STEP*,*ASSOCIATIVE*,*DISAGREE*,*SCALED DOWN*,*STRETCHED*,*NO BORDER*,*WIPED*,*NEEDS WIPING*,*NONSENSICAL*,*EXPECTED MM/DD/YYYY*,*NO INCHES*,*NOT TODAY*"))

(defun lfc:red (s)
  ;; wrap an MTEXT run so it renders in the flag colour, reverting
  ;; to the surrounding colour after (braces scope the change)
  (strcat "{\\C" (itoa *lfc-flag-color*) ";" s "}"))

(defun lfc:small (s)
  ;; all-clear text renders at *lfc-green-scale* of the height the
  ;; red attention text gets, so problems stand out on the sheet
  (strcat "{\\H" (rtos *lfc-green-scale* 2 4) "x;" s "}"))

(defun lfc:big (s)
  ;; the report's title line: half again the base height
  (strcat "{\\H1.5x;" s "}"))

(defun lfc:hdg (s)
  ;; a section heading: underlined, with a thin blank line above it
  ;; so the sections read as blocks (the \P inside the first group is
  ;; a paragraph break at 0.4x height - a narrow gap, not a full line)
  (strcat "{\\H0.4x;\\P}{\\L" s "}"))

(defun lfc:linegrp (s)
  ;; which underlined section a report line files under, keyed on the
  ;; fixed prefixes the review gives its lines
  (cond ((wcmatch s "Dim *,Dimensions:*") "DIMENSIONS")
        ((wcmatch s "Arc *")              "ARCS")
        ((wcmatch s "Lines *")            "OVERLAPPING LINES")
        ((wcmatch s "Steps:*,Step Attachment*,Bead Track:*")
         "STEPS & SIDE VIEWS")
        ((wcmatch s "Height dim *,*CHECK THE WALL HEIGHT*")
         "WALL HEIGHT")
        ((wcmatch s "Liner Material*")    "THE LINER")
        ((wcmatch s "Text *")             "TEXT & UNITS")
        (t                                "OTHER CHECKS")))

(defun lfc:dimline-p (s)
  ;; T for a line that belongs to the DIMENSION AUDIT column - the
  ;; DIMCHECK-style findings, as opposed to the liner's own checks
  (member (lfc:linegrp s) '("DIMENSIONS" "ARCS" "OVERLAPPING LINES")))

;; Every dimension belongs on the dimension layer.  This is the one
;; dimension check the lite scan keeps: it costs a layer read apiece,
;; and a sheet whose dimensions sit on the wrong layer plots wrong
;; however sound the dimensions themselves are - so the verdict, and
;; the suggestion to run CDIM over them, belong on the main sheet
;; rather than in the DIMENSION AUDIT column.  The offending layers
;; are named, since that is what you need to go fix them.
;; Returns (sentence . needs-attention).
(defun lfc:dimlayer-verdict (dims / n off lays lay e)
  (setq n 0 off 0 lays nil)
  (foreach e dims
    (if (entget e)
      (progn
        (setq n   (1+ n)
              lay (cdr (assoc 8 (entget e))))
        (if (/= (strcase lay) (strcase *lfc-dim-layer*))
          (progn
            (setq off (1+ off))
            (if (not (member (strcase lay) lays))
              (setq lays (cons (strcase lay) lays))))))))
  (cond
    ((= n 0)
     (cons "no dimensions in the selection" nil))
    ((= off 0)
     (cons (strcat "all " (itoa n) " on " *lfc-dim-layer*) nil))
    (t
     (cons (strcat (itoa off) " of " (itoa n) " NOT on layer "
                   *lfc-dim-layer* " ("
                   (lfc:join (reverse lays) ", ")
                   ") - run " *lfc-dimfix-cmd* " to move them")
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
(defun lfc:feet-open-p (s / lst n i c prev open found)
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
(defun lfc:mtsafe (s)
  (vl-list->string
    (mapcar '(lambda (c) (if (member c '(92 123 125)) 32 c))
            (vl-string->list s))))

;; The text an entity carries: TEXT and ATTRIB keep it in group 1,
;; MTEXT spills the overflow into group 3 chunks ahead of that.
(defun lfc:ent-text (ent / ed g head tail)
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
(defun lfc:text-items (ss / i e ed et out a ad)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            ed (entget e)
            et (if ed (cdr (assoc 0 ed))))
      (cond
        ((member et '("TEXT" "MTEXT"))
         (setq out (cons (cons (cdr (assoc 5 ed)) (lfc:ent-text e)) out)))
        ((and (= et "INSERT") (assoc 66 ed) (= 1 (cdr (assoc 66 ed))))
         (setq a (entnext e))
         (while (and a (setq ad (entget a)) (= "ATTRIB" (cdr (assoc 0 ad))))
           (setq out (cons (cons (cdr (assoc 5 ad)) (lfc:ent-text a)) out)
                 a   (entnext a)))))))
  (reverse out))

;; The verdict over every text box, plus one report line per offender.
;; Returns (sentence needs-attention (line ...)).
(defun lfc:audit-units (ss / items it s n bad lines)
  (setq items (lfc:text-items ss) n 0 bad 0 lines nil)
  (foreach it items
    (setq s (cdr it))
    (if (and s (/= s ""))
      (progn
        (setq n (1+ n))
        (if (lfc:feet-open-p s)
          (setq bad   (1+ bad)
                lines (cons (strcat "Text " (car it) ": \""
                                    (lfc:mtsafe (lfc:clip s 40))
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

;; The whole report: the liner-finish checks on the MAIN sheet - a
;; large title, the date and version, a verdict line, the colour
;; legend, a SUMMARY dashboard, then the findings under underlined
;; headings - and the DIMCHECK-style findings (dimensions, arcs,
;; overlapping lines) in a DIMENSION AUDIT column to its right.  A
;; lite run writes the main sheet alone.
;;   title   the report's big first line ("LINFINCHECK REPORT", ...)
;;   note    extra legend sentence(s) up front, or nil
;;   hdr     (text . attn) pairs for the SUMMARY dashboard
;;   dhdr    (text . attn) pairs for the dimension column's dashboard
;;   lines   every finding line, report order
;;   lite    T = skip the dimension column
;; Returns the x of the report's right edge, for the caller's zoom.
(defun lfc:write-report (title note hdr dhdr lines lite
                         minx miny maxx maxy
                         / mainl diml l pr nred nmain ndim nlin grps grp
                           ref h ins ins2 txt right)
  (cal:ensure-layer *lfc-report-layer* *lfc-report-color*)
  (foreach l lines
    (if (lfc:dimline-p l)
      (setq diml (cons l diml))
      (setq mainl (cons l mainl))))
  (setq mainl (reverse mainl)
        diml  (reverse diml))
  ;; the verdict counts every line that will render red, either column
  (setq nred 0)
  (foreach pr (append hdr dhdr)
    (if (cdr pr) (setq nred (1+ nred))))
  (foreach l lines
    (if (lfc:attn-p l) (setq nred (1+ nred))))
  ;; sizing: weighted line count per column - the head is ~4.5 lines,
  ;; a heading is a line plus its 0.4 gap - and the taller column
  ;; drives the text height, clamped as before
  (setq nmain 4.5 grps nil)
  (foreach l mainl
    (if (not (member (lfc:linegrp l) grps))
      (setq grps (cons (lfc:linegrp l) grps))))
  (setq nmain (+ nmain (* 1.4 (1+ (length grps)))))   ; SUMMARY + sections
  (setq nmain (+ nmain (* (length hdr) *lfc-green-scale*)))
  (foreach l mainl
    (setq nmain (+ nmain (if (lfc:attn-p l) 1.0 *lfc-green-scale*))))
  (setq ndim 0.0)
  (if (not lite)
    (progn
      (setq ndim 2.5 grps nil)                        ; column title + legend
      (foreach l diml
        (if (not (member (lfc:linegrp l) grps))
          (setq grps (cons (lfc:linegrp l) grps))))
      (setq ndim (+ ndim (* 1.4 (length grps))))
      (setq ndim (+ ndim (* (length dhdr) *lfc-green-scale*)))
      (foreach l diml
        (setq ndim (+ ndim (if (lfc:attn-p l) 1.0 *lfc-green-scale*))))))
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
  (setq txt (strcat (lfc:big title)
                    "\\P"
                    (lfc:small (strcat (cal:datestr)
                                       "  -  LINFINCHECK "
                                       *lfc-version*))
                    "\\P"
                    "{\\H1.2x;"
                    (if (> nred 0)
                      (lfc:red (strcat (itoa nred) " LINE"
                                       (if (= 1 nred) "" "S")
                                       " NEED"
                                       (if (= 1 nred) "S" "")
                                       " ATTENTION"))
                      "ALL CLEAR - every check passed")
                    "}"
                    "\\P"
                    (lfc:small
                      (strcat (if note note "")
                              "Lines needing attention are in "
                              (lfc:red "red")
                              " at full size; lines that checked out"
                              " are smaller."))))
  (setq txt (strcat txt "\\P" (lfc:hdg "SUMMARY")))
  (foreach pr hdr
    (setq txt (strcat txt "\\P"
                      (if (cdr pr)
                        (lfc:red (strcat "  " (car pr)))
                        (lfc:small (strcat "  " (car pr)))))))
  (setq grp nil)
  (foreach l mainl
    (if (/= grp (lfc:linegrp l))
      (setq grp (lfc:linegrp l)
            txt (strcat txt "\\P" (lfc:hdg grp))))
    (setq txt (strcat txt "\\P"
                      (if (lfc:attn-p l)
                        (lfc:red (strcat "  " l))
                        (lfc:small (strcat "  " l))))))
  (lfc:mtext ins h (* *lfc-report-chars* h) txt *lfc-report-layer*)
  (setq right (+ (car ins) (* *lfc-report-chars* h)))
  ;; --- the DIMENSION AUDIT column
  (if (not lite)
    (progn
      (setq ins2 (list (+ (car ins) (* (+ *lfc-report-chars* 2.0) h))
                       (cadr ins) 0.0)
            txt  (strcat "{\\H1.2x;DIMENSION AUDIT}"
                         "\\P"
                         (lfc:small
                           (strcat "Dimensions, arcs and overlapping"
                                   " lines - DIMCHECK's ground, kept"
                                   " off the main sheet."))))
      (foreach pr dhdr
        (setq txt (strcat txt "\\P"
                          (if (cdr pr)
                            (lfc:red (strcat "  " (car pr)))
                            (lfc:small (strcat "  " (car pr)))))))
      (setq grp nil)
      (foreach l diml
        (if (/= grp (lfc:linegrp l))
          (setq grp (lfc:linegrp l)
                txt (strcat txt "\\P" (lfc:hdg grp))))
        (setq txt (strcat txt "\\P"
                          (if (lfc:attn-p l)
                            (lfc:red (strcat "  " l))
                            (lfc:small (strcat "  " l))))))
      (lfc:mtext ins2 h (* *lfc-report-chars* h) txt *lfc-report-layer*)
      (setq right (+ (car ins2) (* *lfc-report-chars* h)))))
  right)

;; --- geometry ------------------------------------------------------

(defun lfc:planar-arc-p (ed / n)
  ;; only arcs drawn in the world XY plane are handled
  (setq n (cdr (assoc 210 ed)))
  (or (null n)
      (and (< (abs (car n)) 1e-9)
           (< (abs (cadr n)) 1e-9)
           (> (caddr n) 0.0))))

(defun lfc:rebuild-arc (ent which fixed mid target / c r a1 a2 am tmp ed pair)
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

(defun lfc:move-arc-end (ent which target / mid other)
  ;; re-fit the arc so the chosen endpoint lands on target (WCS)
  (setq mid   (vlax-curve-getPointAtDist
                ent
                (/ (vlax-curve-getDistAtParam ent (vlax-curve-getEndParam ent)) 2.0))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent)))
  (lfc:rebuild-arc ent which other mid target))

(defun lfc:overlap-info (la lb / a1 a2 b1 b2 u lena s1 s2 tmp lo hi)
  ;; when segments la and lb are collinear (within *lfc-olap-fuzz*)
  ;; and run on top of each other for more than *lfc-tol*, returns
  ;;   (ov-start ov-end ov-length union-start union-end)
  ;; nil when they do not overlap (touching end-to-end is fine)
  (setq a1 (lfc:seg-p1 la)
        a2 (lfc:seg-p2 la)
        b1 (lfc:seg-p1 lb)
        b2 (lfc:seg-p2 lb)
        u  (cal:unitn (mapcar '- a2 a1)))
  (if (and u
           (<= (cal:pt-line-dist b1 a1 u) *lfc-olap-fuzz*)
           (<= (cal:pt-line-dist b2 a1 u) *lfc-olap-fuzz*))
    (progn
      (setq lena (distance a1 a2)
            s1   (cal:proj-param b1 a1 u)
            s2   (cal:proj-param b2 a1 u))
      (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
      (setq lo (max 0.0 s1)
            hi (min lena s2))
      (if (> (- hi lo) *lfc-tol*)
        (list (cal:axis-pt a1 u lo)
              (cal:axis-pt a1 u hi)
              (- hi lo)
              (cal:axis-pt a1 u (min 0.0 s1))
              (cal:axis-pt a1 u (max lena s2)))))))

(defun lfc:merge-lines (la lb info / ed)
  ;; stretch la's LINE over the union of both, delete lb's LINE
  (setq ed (entget (lfc:seg-ent la))
        ed (subst (cons 10 (nth 3 info)) (assoc 10 ed) ed)
        ed (subst (cons 11 (nth 4 info)) (assoc 11 ed) ed))
  (entmod ed)
  (entupd (lfc:seg-ent la))
  (entdel (lfc:seg-ent lb)))

(defun lfc:whole-line-p (s / ed)
  ;; T when the segment IS its owner entity - only whole LINEs can be
  ;; merged; a polyline edge has to be fixed by hand
  (setq ed (entget (lfc:seg-ent s)))
  (= "LINE" (cdr (assoc 0 ed))))

(defun lfc:find-overlaps (segs / atol fams a placed fam recs e p1 p2 dx dy
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
    (setq a      (lfc:seg-dir-ang e)
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
          (setq p1  (lfc:seg-p1 e)
                p2  (lfc:seg-p2 e)
                off (- (* (cadr p1) dx) (* (car p1) dy))
                s1  (+ (* (car p1) dx) (* (cadr p1) dy))
                s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
          (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
          (setq recs (cons (list off s1 s2 e) recs)))
        (setq recs (lfc:sort-recs recs))
        ;; sorted by offset: only sweep forward while still collinear
        (while recs
          (setq r    (car recs)
                rest (cdr recs))
          (while (and rest
                      (<= (- (car (car rest)) (car r)) *lfc-olap-fuzz*))
            (setq q (car rest))
            (if (and (not (eq (lfc:seg-ent (cadddr r))
                              (lfc:seg-ent (cadddr q))))
                     ;; spans must actually meet before the exact test
                     (> (min (caddr r) (caddr q)) (max (cadr r) (cadr q)))
                     (lfc:overlap-info (cadddr r) (cadddr q)))
              (progn
                (setq key (list (lfc:seg-ent (cadddr r))
                                (lfc:seg-ent (cadddr q))))
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

(defun lfc:seg-p1 (s) (car s))
(defun lfc:seg-p2 (s) (cadr s))
(defun lfc:seg-ent (s) (caddr s))

(defun lfc:ocs->wcs (p nz)
  (if (and nz (not (equal nz '(0.0 0.0 1.0) 1e-9))) (trans p nz 0) p))

(defun lfc:lwpoly-segs (ent / ed nz elev vs bl cls n i segs g)
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
       (setq vs (cons (lfc:ocs->wcs (list (car (cdr g)) (cadr (cdr g)) elev) nz) vs)
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

(defun lfc:heavy-poly-segs (ent / e ed vs bl cls n i segs)
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

(defun lfc:ent-segs (ent / ed et)
  ;; every straight segment an entity contributes, in WCS
  (setq ed (entget ent)
        et (cdr (assoc 0 ed)))
  (cond
    ((= et "LINE")       (list (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)) ent)))
    ((= et "LWPOLYLINE") (lfc:lwpoly-segs ent))
    ((= et "POLYLINE")   (lfc:heavy-poly-segs ent))))

(defun lfc:collect-segs (ents / segs e s)
  ;; all straight segments of a list of entities, longer than the
  ;; attachment tolerance (zero-length stubs help nothing)
  (foreach e ents
    (if (entget e)
      (foreach s (lfc:ent-segs e)
        (if (> (distance (car s) (cadr s)) *lfc-tol*)
          (setq segs (cons s segs))))))
  (reverse segs))

(defun lfc:group-ents (g / out e s)
  ;; the distinct entities a group's segments belong to
  (foreach s (cdr g)
    (setq e (lfc:seg-ent s))
    (if (not (member e out)) (setq out (cons e out))))
  (reverse out))

(defun lfc:seg-dir-ang (s / a)
  ;; segment direction folded into [0, pi)
  (setq a (angle (lfc:seg-p1 s) (lfc:seg-p2 s)))
  (if (>= a pi) (- a pi) a))

(defun lfc:sort-recs (recs / out r pre rest)
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

(defun lfc:step-groups (lns minlines / atol fams a placed recs pts p1 p2 dx dy
                             off s1 s2 tmp cur chains gap groups e fam r)
  ;; hunt for step-like patterns: minlines or more parallel LINEs
  ;; stacked less than *lfc-step-maxgap* apart, each sideways-
  ;; overlapping the one before it (like stair treads).
  ;; Returns a list of groups, each (direction-angle ent ent ...)
  ;; ordered bottom tread to top.
  (setq atol   (* *lfc-step-angtol* (/ pi 180.0))
        fams   nil
        groups nil)
  ;; bucket the segments into parallel families
  (foreach e lns
    (progn
      (setq a      (lfc:seg-dir-ang e)
            placed nil)
      (foreach fam fams
        (if (and (not placed) (<= (cal:ang-diff a (car fam)) atol))
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
          (setq p1  (lfc:seg-p1 e)
                p2  (lfc:seg-p2 e)
                off (- (* (cadr p1) dx) (* (car p1) dy))
                s1  (+ (* (car p1) dx) (* (cadr p1) dy))
                s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
          (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
          (setq recs (cons (list off s1 s2 e) recs)))
        (setq recs (lfc:sort-recs recs))
        ;; cur = (ents distinct-tread-count span-lo span-hi last-off)
        (setq cur nil chains nil)
        (foreach r recs
          (cond
            ((null cur)
             (setq cur (list (list (cadddr r)) 1 (cadr r) (caddr r) (car r))))
            (t
             (setq gap (- (car r) (nth 4 cur)))
             (cond
               ((<= gap *lfc-tol*)           ; same tread drawn in pieces
                (setq cur (list (cons (cadddr r) (car cur))
                                (cadr cur)
                                (min (nth 2 cur) (cadr r))
                                (max (nth 3 cur) (caddr r))
                                (car r))))
               ;; next tread: plan-view treads overlap sideways, but in
               ;; a side view consecutive risers only touch corner to
               ;; corner (a zigzag), so allow a sideways gap up to one
               ;; tread depth as well
               ((and (<= gap *lfc-step-maxgap*)
                     (<= (- (max (nth 2 cur) (cadr r))
                            (min (nth 3 cur) (caddr r)))
                         *lfc-step-maxgap*))
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

(defun lfc:staircase-p (g / a dx dy recs e pts p1 p2 off s1 s2 tmp
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
    (setq p1  (lfc:seg-p1 e)
          p2  (lfc:seg-p2 e)
          off (- (* (cadr p1) dx) (* (car p1) dy))
          s1  (+ (* (car p1) dx) (* (cadr p1) dy))
          s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
    (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
    (setq recs (cons (list off s1 s2) recs)))
  (setq recs   (lfc:sort-recs recs)
        merged nil)
  (foreach r recs                              ; fuse pieces of one tread
    (if (and merged (<= (abs (- (car r) (caar merged))) *lfc-tol*))
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
          ((<= (abs d) *lfc-tol*) (setq ok nil))   ; no march along
          ((= sign 0) (setq sign (if (> d 0.0) 1 -1)))
          ((/= sign (if (> d 0.0) 1 -1)) (setq ok nil)))))  ; direction flipped
    (setq prev r))
  ok)

(defun lfc:pts-bbox (segs / xs ys e p)
  ;; ((minx miny) (maxx maxy)) over the endpoints of a list of segments
  (setq xs nil ys nil)
  (foreach e segs
    (foreach p (list (lfc:seg-p1 e) (lfc:seg-p2 e))
      (setq xs (cons (car p) xs)
            ys (cons (cadr p) ys))))
  (if xs
    (list (list (apply 'min xs) (apply 'min ys))
          (list (apply 'max xs) (apply 'max ys)))))

(defun lfc:boxes-touch (b1 b2 m)
  ;; do two ((minx miny)(maxx maxy)) boxes overlap once grown by m?
  (and b1 b2
       (<= (- (caar b2) m) (caadr b1))
       (<= (- (caar b1) m) (caadr b2))
       (<= (- (cadar b2) m) (cadadr b1))
       (<= (- (cadar b1) m) (cadadr b2))))

(defun lfc:bead-near-p (gbb beadbbs / hit bb)
  ;; is any bead-track box within *lfc-bead-dist* of the group box?
  (setq hit nil)
  (foreach bb beadbbs
    (if (lfc:boxes-touch gbb bb *lfc-bead-dist*)
      (setq hit T)))
  hit)

(defun lfc:zoom-box (bb / p1 p2 m)
  ;; zoom the current view onto a ((minx miny)(maxx maxy)) box
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *lfc-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

;; --- block & text helpers ------------------------------------------

(defun lfc:norm-text (s)
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

(defun lfc:block-name (ent / res)
  ;; effective block name (sees through dynamic blocks)
  (setq res (vl-catch-all-apply
              'vla-get-EffectiveName
              (list (vlax-ename->vla-object ent))))
  (if (vl-catch-all-error-p res)
    (cdr (assoc 2 (entget ent)))
    res))

(defun lfc:blockdef-texts (bname depth / lst e et g)
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
                 lst (append (lfc:blockdef-texts (cdr (assoc 2 (entget e)))
                                                  (1- depth))
                             lst))))
        (setq e (entnext e)))))
  lst)

(defun lfc:ins-texts (ent / ed lst e)
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
  (append lst (lfc:blockdef-texts (cdr (assoc 2 ed)) *lfc-block-depth*)))

(defun lfc:attrib-bad-tags (ent words / e ed val tags)
  ;; tags of the INSERT's ATTRIBUTES whose value carries one of the
  ;; standalone words. Only attribute VALUES are considered - the
  ;; block's own labels ("Wall:", "Floor:") live in its definition and
  ;; must never be touched.
  (if (= 1 (cdr (assoc 66 (entget ent))))
    (progn
      (setq e (entnext ent))
      (while (and e (= "ATTRIB" (cdr (assoc 0 (setq ed (entget e))))))
        (setq val (cdr (assoc 1 ed)))
        (if (vl-some '(lambda (w)
                        (wcmatch (strcat " " (lfc:norm-text val) " ")
                                 (strcat "* " (strcase w) " *")))
                     words)
          (setq tags (cons (cdr (assoc 2 ed)) tags)))
        (setq e (entnext e)))))
  (reverse tags))

(defun lfc:wipe-attribs (ent tags / e ed n)
  ;; blank the listed attribute values so the pattern reads clean:
  ;; the label stays, whatever was written after it goes
  (setq n 0)
  (if (= 1 (cdr (assoc 66 (entget ent))))
    (progn
      (setq e (entnext ent))
      (while (and e (= "ATTRIB" (cdr (assoc 0 (setq ed (entget e))))))
        (if (member (cdr (assoc 2 ed)) tags)
          (progn
            (entmod (subst '(1 . "") (assoc 1 ed) ed))
            (entupd e)
            (setq n (1+ n))))
        (setq e (entnext e)))))
  (if (> n 0) (entupd ent))
  n)

(defun lfc:ins-attrib-deep (ent tag / val s)
  ;; the tag's value on the INSERT, or on a block nested inside it
  (setq val (lfc:ins-attrib ent tag))
  (if val
    val
    (foreach s (lfc:blockdef-texts (cdr (assoc 2 (entget ent)))
                                    *lfc-block-depth*)
      (if (and (null val)
               (wcmatch (lfc:squash s) (strcat "*" (lfc:squash tag) "*")))
        (setq val s)))))

(defun lfc:block-has-layer-p (bname layer depth / e et found)
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
          (if (lfc:block-has-layer-p (cdr (assoc 2 (entget e))) layer (1- depth))
            (setq found T)))
        (setq e (entnext e)))))
  found)

(defun lfc:ins-matches (ent phrase / pat found s)
  ;; T when the INSERT's (effective) name or any text it shows
  ;; contains the phrase, ignoring case and punctuation
  (setq pat   (strcat "*" (lfc:norm-text phrase) "*")
        found (wcmatch (lfc:norm-text (lfc:block-name ent)) pat))
  (foreach s (lfc:ins-texts ent)
    (if (wcmatch (lfc:norm-text s) pat)
      (setq found T)))
  found)

(defun lfc:ins-text-has (ent phrase / pat found s)
  ;; T when any text the INSERT shows carries the phrase (its block
  ;; NAME is deliberately not consulted - an option label has to be
  ;; drawn in the block, not implied by what it is called)
  (setq pat   (strcat "*" (lfc:squash phrase) "*")
        found nil)
  (foreach s (lfc:ins-texts ent)
    (if (wcmatch (lfc:squash s) pat) (setq found T)))
  found)

(defun lfc:attach-undecided-p (ent / w undecided)
  ;; T when the block still shows EVERY attachment option, i.e. nobody
  ;; has picked one yet
  (setq undecided T)
  (foreach w *lfc-attach-options*
    (if (not (lfc:ins-text-has ent w)) (setq undecided nil)))
  undecided)

(defun lfc:ins-has-word (ent word / found s)
  ;; T when the INSERT's (effective) name or any text it shows
  ;; contains the given standalone word -- "NOT" hits "Not Selected"
  ;; but never "NOTE"; "STEP" hits "with Step" but never "Stepstone"
  (setq word  (strcase word)
        found nil)
  (foreach s (cons (lfc:block-name ent) (lfc:ins-texts ent))
    (if (and s
             (wcmatch (strcat " " (lfc:norm-text s) " ")
                      (strcat "* " word " *")))
      (setq found T)))
  found)

(defun lfc:phrase-p (s / sq)
  ;; T when the text carries one of *lfc-fgstep-words*, with case,
  ;; spaces and punctuation ignored - so "FiberglassStep" (a layer
  ;; name) matches "Fiberglass Step" just as well
  (setq sq (lfc:squash s))
  (vl-some '(lambda (w) (wcmatch sq (strcat "*" (lfc:squash w) "*")))
           *lfc-fgstep-words*))

(defun lfc:clip (s n)
  (if (> (strlen s) n) (strcat (substr s 1 n) "...") s))

(defun lfc:fgstep-src (ss blks / found i e ed et g b s)
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
        (if (lfc:phrase-p s)                    ; the layer it sits on
          (setq found (strcat "layer '" (lfc:clip s 40) "'")))
        (if (and (not found) (member et '("TEXT" "MTEXT")))
          (foreach g ed
            (if (and (not found)
                     (member (car g) '(1 3))
                     (lfc:phrase-p (cdr g)))
              (setq found (strcat "text '" (lfc:clip (cdr g) 40) "'"))))))))
  (foreach b blks                                ; block names & their text
    (if (not found)
      (progn
        (setq s (lfc:block-name b))
        (if (lfc:phrase-p s)
          (setq found (strcat "block '" (lfc:clip s 40) "'")))
        (if (not found)
          (foreach s (lfc:ins-texts b)
            (if (and (not found) (lfc:phrase-p s))
              (setq found (strcat "block text '" (lfc:clip s 40) "'"))))))))
  found)

(defun lfc:drawing-has-phrase (phrase / pat ss2 i e ed found g)
  ;; T when any TEXT or MTEXT in the drawing carries the phrase,
  ;; case and punctuation ignored
  (setq pat (strcat "*" (lfc:norm-text phrase) "*")
        ss2 (ssget "_X" '((0 . "TEXT,MTEXT")))
        i   0)
  (if ss2
    (repeat (sslength ss2)
      (setq e  (ssname ss2 i)
            i  (1+ i)
            ed (entget e))
      (foreach g ed
        (if (and (not found)
                 (member (car g) '(1 3))
                 (wcmatch (lfc:norm-text (cdr g)) pat))
          (setq found T)))))
  found)

(defun lfc:join (lst sep / out s)
  ;; "A" + "B" + ... joined with sep
  (foreach s lst
    (setq out (if out (strcat out sep s) s)))
  out)

(defun lfc:squash (s)
  ;; norm-text with the spaces removed too, so "Tech Title" finds a
  ;; block that is actually named "TechTitle"
  (vl-list->string (vl-remove 32 (vl-string->list (lfc:norm-text s)))))

(defun lfc:ins-attrib (ent tag / e ed val)
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

(defun lfc:parse-num (s / p num den)
  ;; "4", "4.5", "1/2" -> real
  (setq p (vl-string-search "/" s))
  (if p
    (progn
      (setq num (atof (substr s 1 p))
            den (atof (substr s (+ p 2))))
      (if (> den 0.0) (/ num den) 0.0))
    (atof s)))

(defun lfc:after-eq (s / p)
  ;; the part after the last "=", so a label never contributes its
  ;; own digits: "Finished Wall Ht = 40''" -> " 40''"
  (while (setq p (vl-string-search "=" s))
    (setq s (substr s (+ p 2))))
  s)

(defun lfc:len-values (s / lst i n c numstr toks unit vals cur tok)
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
  (setq s    (lfc:after-eq s)
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
        (setq toks (append toks (list (cons (lfc:parse-num numstr) unit)))))
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

(defun lfc:parse-len (s)
  ;; the first length written in the text, in inches; nil when none
  (car (lfc:len-values s)))

(defun lfc:varies-p (s)
  ;; T when the height reads "Varies" instead of carrying a number
  (wcmatch (strcat " " (lfc:norm-text (lfc:after-eq s)) " ")
           "* VARIES *"))

(defun lfc:all-digits-p (s / i n c ok)
  (setq n (strlen s) ok (> n 0) i 1)
  (while (and ok (<= i n))
    (setq c (ascii (substr s i 1)))
    (if (or (< c 48) (> c 57)) (setq ok nil))
    (setq i (1+ i)))
  ok)

(defun lfc:days-in-month (mo yr)
  (cond
    ((member mo '(1 3 5 7 8 10 12)) 31)
    ((member mo '(4 6 9 11)) 30)
    ((and (= 0 (rem yr 4)) (or (/= 0 (rem yr 100)) (= 0 (rem yr 400)))) 29) ; leap Feb
    (t 28)))

(defun lfc:today-mdy ( / d)
  ;; (month day year) off the computer clock.  CDATE is
  ;; YYYYMMDD.HHMMSSmsec, decoded arithmetically so DIMZIN (which trims
  ;; rtos output) cannot mangle it.
  (setq d (fix (getvar "CDATE")))
  (list (rem (fix (/ d 100)) 100) (rem d 100) (fix (/ d 10000))))

(defun lfc:mdy-str (mdy)
  (strcat (cal:zeropad2 (car mdy)) "/" (cal:zeropad2 (cadr mdy)) "/"
          (itoa (caddr mdy))))

(defun lfc:date-verdict (raw / s mo dd yr now)
  ;; nil when raw is a clean MM/DD/YYYY calendar date; otherwise a
  ;; short string saying what is wrong with it
  (setq s (vl-string-trim " \t" (lfc:after-eq raw)))
  (cond
    ((= s "") "is blank - expected MM/DD/YYYY")
    ((or (/= (strlen s) 10)
         (/= (substr s 3 1) "/")
         (/= (substr s 6 1) "/")
         (not (lfc:all-digits-p (substr s 1 2)))
         (not (lfc:all-digits-p (substr s 4 2)))
         (not (lfc:all-digits-p (substr s 7 4))))
     (strcat "'" raw "' is not in MM/DD/YYYY format - expected MM/DD/YYYY"))
    (t
     (setq mo (atoi (substr s 1 2))
           dd (atoi (substr s 4 2))
           yr (atoi (substr s 7 4)))
     (cond
       ((or (< mo 1) (> mo 12))
        (strcat "'" raw "' - " (substr s 1 2)
                " is not a month (01-12) - expected MM/DD/YYYY"))
       ((or (< dd 1) (> dd (lfc:days-in-month mo yr)))
        (strcat "'" raw "' - " (substr s 4 2)
                " is not a valid day for that month - expected MM/DD/YYYY"))
       ;; a real date, but is it TODAY?  A sheet going out under an old
       ;; date is the mistake this catches -- the drawing was reworked
       ;; and the title block never caught up.
       ((progn (setq now (lfc:today-mdy))
               (not (and (= mo (car now)) (= dd (cadr now))
                         (= yr (caddr now)))))
        (strcat "'" s "' is NOT TODAY'S DATE (" (lfc:mdy-str now)
                ") - update it"))
       (t nil)))))

;; --- dimension review ----------------------------------------------

(defun lfc:dim-style (ent / s)
  ;; the dimension's style name, "" when it has none
  (setq s (cdr (assoc 3 (entget ent))))
  (if s s ""))

(defun lfc:style-rank (style / i r s)
  ;; position of the style in *lfc-style-order* (exact name match,
  ;; case-blind); unlisted styles land after every listed one
  (setq style (strcase style)
        i     0
        r     nil)
  (foreach s *lfc-style-order*
    (if (and (null r) (= (strcase s) style)) (setq r i))
    (setq i (1+ i)))
  (if r r (length *lfc-style-order*)))

(defun lfc:ent-center (ent / bb)
  ;; (x y) centre of the entity's box; falls back to its group-10 point
  (setq bb (cal:bbox-ent ent))
  (if bb
    (list (* 0.5 (+ (caar bb) (caadr bb)))
          (* 0.5 (+ (cadar bb) (cadadr bb))))
    (progn
      (setq bb (cdr (assoc 10 (entget ent))))
      (if bb (list (car bb) (cadr bb)) (list 0.0 0.0)))))

(defun lfc:dim-order-p (r1 r2 rowtol)
  ;; strict "r1 reviews before r2" for recs (rank cx cy ent):
  ;; style rank first, then row (higher = earlier), then left first
  (cond
    ((< (car r1) (car r2)) T)
    ((> (car r1) (car r2)) nil)
    ((> (- (caddr r1) (caddr r2)) rowtol) T)   ; r1 sits a row above
    ((> (- (caddr r2) (caddr r1)) rowtol) nil) ; r2 sits a row above
    (t (< (cadr r1) (cadr r2)))))              ; same row: left first

(defun lfc:sort-dims (dims rowtol / recs cen r out pre rest e)
  ;; stable insertion sort into review order
  (setq recs nil)
  (foreach e dims
    (setq cen  (lfc:ent-center e)
          recs (cons (list (lfc:style-rank (lfc:dim-style e))
                           (car cen) (cadr cen) e)
                     recs)))
  (setq recs (reverse recs)
        out  nil)
  (foreach r recs
    (setq pre  nil
          rest out)
    (while (and rest (not (lfc:dim-order-p r (car rest) rowtol)))
      (setq pre  (cons (car rest) pre)
            rest (cdr rest)))
    (setq out (append (reverse pre) (list r) rest)))
  (mapcar '(lambda (r) (nth 3 r)) out))

(defun lfc:dim-meas (ent / ed dtype p13 p14 ang v meas)
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

(defun lfc:dim-num (ent / ed dtype p13 p14 ang v)
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

(defun lfc:dim-stated (ent / txt v)
  ;; the value the dimension actually STATES: its text override when
  ;; it carries a readable one, else what it measures
  (setq txt (cdr (assoc 1 (entget ent))))
  (if (and txt
           (/= txt "")
           (not (vl-string-search "<>" txt))    ; "<>" = show the measurement
           (setq v (lfc:parse-len txt)))
    v
    (lfc:dim-num ent)))

(defun lfc:pt-in-box (p bb m)
  ;; is point p inside the ((minx miny)(maxx maxy)) box grown by m?
  (and bb p
       (>= (car p)  (- (caar bb) m))
       (<= (car p)  (+ (caadr bb) m))
       (>= (cadr p) (- (cadar bb) m))
       (<= (cadr p) (+ (cadadr bb) m))))

(defun lfc:height-dim (dims bb rise / best bestdy ed p13 p14 dy e)
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
                 (lfc:pt-in-box p13 bb *lfc-height-tol*)
                 (lfc:pt-in-box p14 bb *lfc-height-tol*))
          (progn
            (setq dy (abs (- (cadr p14) (cadr p13))))
            (if (and (>= dy (- rise *lfc-height-tol*))
                     (or (null bestdy) (> dy bestdy)))
              (setq bestdy dy
                    best   e)))))))
  best)

(defun lfc:audit-dim-point (ent gcode label cands / ed pt near sugg ans final how)
  ;; audits one definition point: an off-object point is put where it
  ;; looks like it belongs, then you choose - Move (take it), Keep
  ;; (put it back exactly where you drew it) or Pick your own spot.
  ;; Returns (original final how) when the point was looked at, where
  ;; how is 'auto / 'user / 'kept; nil when the point was already fine.
  (setq ed (entget ent)
        pt (cdr (assoc gcode ed)))
  (if pt
    (progn
      (setq near (lfc:nearest-curve pt nil cands))
      (if (and near (> (caddr near) *lfc-tol*))
        (progn
          (setq sugg (cadr near))
          ;; show the suggestion in place, but keep the original spot
          ;; marked so both are on screen while the question is asked
          (entmod (subst (cons gcode sugg) (assoc gcode ed) ed))
          (entupd ent)
          (princ (strcat "\n  " label " is not on any object - nearest one is "
                         (rtos (caddr near) 2 4) " away."))
          (setq ans (lfc:confirm-move label pt sugg))
          (cond
            ((eq ans 'move)
             (setq final sugg
                   how   'auto)
             (princ (strcat "\n  " label " MOVED onto the nearest object, "
                            (lfc:ptstr final) ".")))
            ((eq ans 'keep)
             (setq ed    (entget ent)
                   final pt
                   how   'kept)
             (entmod (subst (cons gcode pt) (assoc gcode ed) ed))
             (entupd ent)
             (princ (strcat "\n  " label " KEPT where you drew it, "
                            (lfc:ptstr final) " - nothing changed.")))
            (t
             (setq final (trans ans 1 0)
                   how   'user
                   ed    (entget ent))
             (entmod (subst (cons gcode final) (assoc gcode ed) ed))
             (entupd ent)
             (princ (strcat "\n  " label " moved to the spot you picked, "
                            (lfc:ptstr final) "."))))
          (redraw)
          (list pt final how))))))

(defun lfc:review-dim (ent cands num total / ed dtype h sty p13 p14 r1 r2
                                              looked moved kept ok note meas assocnote)
  ;; interactive review of one dimension.
  ;; Returns (handle ok-flag report-note moved-point-count measurement).
  (setq ed    (entget ent)
        h     (cdr (assoc 5 ed))
        sty   (lfc:dim-style ent)
        dtype (logand 7 (cdr (assoc 70 ed))))
  (lfc:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nDimension " (itoa num) " of " (itoa total)
                 " (handle " h
                 (if (= sty "") "" (strcat ", style " sty))
                 ")"))
  (if (member dtype '(0 1))                   ; rotated/linear or aligned
    (progn
      (if (lfc:dim-assoc-p ent)
        (princ "\n  Note: this dimension is object-associative - a moved point may re-anchor on its own."))
      (setq p13 (cdr (assoc 13 ed))           ; the two dimmed points
            p14 (cdr (assoc 14 ed))
            r1  (lfc:audit-dim-point ent 13 "dimension point 1" cands)
            r2  (lfc:audit-dim-point ent 14 "dimension point 2" cands))))
  (setq looked (append (if r1 (list r1)) (if r2 (list r2)))
        moved  (vl-remove-if '(lambda (x) (eq (caddr x) 'kept)) looked)
        kept   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'kept)) looked))
  ;; only when something actually moved is there an old position worth
  ;; drawing a construction line through
  (if moved (lfc:make-xline p13 p14))        ; through the ORIGINAL points
  (if (and moved (lfc:dim-assoc-p ent))
    (setq assocnote " (ASSOCIATIVE - verify the moved point holds)"))
  (setq meas (lfc:dim-meas ent))             ; after any point moves
  (if meas (princ (strcat "\n  Measures " meas ".")))
  (redraw ent 3)
  (setq ok (cal:ask-yn-nav "\n  Is this dimension correct?"))
  (redraw ent 4)
  (redraw)
  (if (member ok '(back skip))
    (list h ok nil (length moved) meas)       ; navigation: caller handles it
    (progn
      (setq ok (eq ok 'yes))
      (setq note (strcat
                   (if ok "OK" "FLAGGED to fix (red)")
                   (if moved
                     (strcat " - " (itoa (length moved))
                             " point(s) moved onto the nearest object")
                     "")
                   (if kept
                     (strcat " - " (itoa (length kept))
                             " point(s) kept where you drew them")
                     "")
                   (if assocnote assocnote "")))
      (if (not ok) (lfc:set-color ent *lfc-flag-color*))
      (list h ok note (length moved) meas))))

;; --- arc review ----------------------------------------------------

(defun lfc:arc-end-target (ent which cands / p other near ends target)
  ;; where the attachment audit says this endpoint should go;
  ;; nil when the endpoint is already fine (or nothing to attach to)
  (setq p     (if (eq which 'start)
                (vlax-curve-getStartPoint ent)
                (vlax-curve-getEndPoint ent))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent))
        near  (lfc:nearest-curve p ent cands))
  (cond
    ((null near) nil)                         ; nothing to attach to at all
    ((<= (caddr near) *lfc-tol*)             ; endpoint sits on an object...
     (setq ends (lfc:curve-ends (car near)))
     ;; never snap onto the arc's own other endpoint
     (setq ends (vl-remove-if '(lambda (q) (< (distance q other) 1e-8)) ends))
     (cond
       ((null ends) nil)                      ; closed curve: no ends to demand
       ((vl-some '(lambda (q) (<= (distance p q) *lfc-tol*)) ends)
        nil)                                  ; ...and at one of its ends: OK
       (t (lfc:closest-of p ends))))         ; ...but mid-object: closest end
    (t                                        ; floating: closest end anywhere,
     (setq target (lfc:nearest-end p ent cands))
     (if (or (null target) (< (distance target other) 1e-8))
       (cadr near)                            ; else closest point on closest object
       target))))

(defun lfc:arc-state (ent / ed)
  ;; the groups that define an arc's shape, for an exact put-it-back
  (setq ed (entget ent))
  (list (assoc 10 ed) (assoc 40 ed) (assoc 50 ed) (assoc 51 ed)))

(defun lfc:arc-restore (ent st / ed g)
  ;; restore a saved shape exactly, rather than re-fitting back to it
  (setq ed (entget ent))
  (foreach g st (setq ed (subst g (assoc (car g) ed) ed)))
  (entmod ed)
  (entupd ent))

(defun lfc:review-arc-end (ent which label cands / p target st ans final how)
  ;; audits one arc endpoint: a detached end is snapped where it looks
  ;; like it belongs, then you choose - Move (take it), Keep (put the
  ;; arc back exactly as drawn) or Pick your own spot.
  ;; Returns (original final how) when the end was looked at, where how
  ;; is 'auto / 'user / 'kept; nil when the end was already fine.
  (setq p      (if (eq which 'start)
                 (vlax-curve-getStartPoint ent)
                 (vlax-curve-getEndPoint ent))
        target (lfc:arc-end-target ent which cands)
        st     (lfc:arc-state ent))
  (cond
    (target
     (if (lfc:move-arc-end ent which target)
       (progn
         (princ (strcat "\n  " label " is not attached to an object end - nearest is "
                        (rtos (distance p target) 2 4) " away."))
         (setq ans (lfc:confirm-move label p target))
         (cond
           ((eq ans 'move)
            (setq final target
                  how   'auto)
            (princ (strcat "\n  " label " SNAPPED to the object end, "
                           (lfc:ptstr final) ".")))
           ((eq ans 'keep)
            (lfc:arc-restore ent st)
            (setq final p
                  how   'kept)
            (princ (strcat "\n  " label " KEPT where you drew it, "
                           (lfc:ptstr final) " - the arc is unchanged.")))
           (t
            (setq ans (trans ans 1 0))
            (if (lfc:move-arc-end ent which ans)
              (progn
                (setq final ans
                      how   'user)
                (princ (strcat "\n  " label " moved to the spot you picked, "
                               (lfc:ptstr final) ".")))
              (progn
                (setq final target
                      how   'auto)
                (princ "\n  Could not re-fit the arc through that spot (collinear?); left it on the object end.")))))
         (redraw)
         (list p final how))
       (progn
         (princ (strcat "\n  " label " should attach at " (lfc:ptstr target)
                        " but the arc could not be re-fitted (points collinear?)."))
         nil)))
    (*lfc-ask-all-arc-ends*                  ; optional: confirm attached ends too
     (setq ans (lfc:confirm-move label p p))
     (redraw)
     (if (member ans '(move keep))
       nil
       (progn
         (setq ans (trans ans 1 0))
         (if (lfc:move-arc-end ent which ans)
           (list p ans 'user)
           (progn
             (princ "\n  Could not re-fit the arc through that spot (collinear?); unchanged.")
             nil)))))
    (t nil)))

(defun lfc:review-arc (ent cands num total / ed h planar r1 r2 looked moved kept note)
  ;; interactive review of one arc's endpoints.
  ;; Returns (handle untouched-flag report-note moved-point-count).
  (setq ed     (entget ent)
        h      (cdr (assoc 5 ed))
        planar (lfc:planar-arc-p ed))
  (lfc:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nArc " (itoa num) " of " (itoa total)
                 " (handle " h ")"))
  (if planar
    (setq r1 (lfc:review-arc-end ent 'start "arc start point" cands)
          r2 (lfc:review-arc-end ent 'end   "arc end point"   cands))
    (princ "\n  Arc is not in the world XY plane - endpoint audit skipped."))
  (redraw ent 4)
  (redraw)
  (setq looked (append (if r1 (list r1)) (if r2 (list r2)))
        moved  (vl-remove-if '(lambda (x) (eq (caddr x) 'kept)) looked)
        kept   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'kept)) looked))
  (if moved (lfc:set-color ent *lfc-arc-color*))
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

(defun lfc:review-olap (la lb num total / info ea eb h1 h2 lay1 lay2 label
                                           ans mergeable kinds)
  ;; interactive review of one overlapping segment pair.
  ;; Returns nil when the pair no longer overlaps (an earlier merge
  ;; absorbed it); otherwise (label report-note action ents...) where
  ;; action is merged / flagged / left and ents keep their cyan.
  (setq ea (lfc:seg-ent la)
        eb (lfc:seg-ent lb))
  (if (and (entget ea) (entget eb) (setq info (lfc:overlap-info la lb)))
    (progn
      (setq h1        (cdr (assoc 5 (entget ea)))
            h2        (cdr (assoc 5 (entget eb)))
            lay1      (cdr (assoc 8 (entget ea)))
            lay2      (cdr (assoc 8 (entget eb)))
            mergeable (and (lfc:whole-line-p la)
                           (lfc:whole-line-p lb)
                           (= (strcase lay1) (strcase lay2)))
            kinds     (if (and (lfc:whole-line-p la) (lfc:whole-line-p lb))
                        "lines"
                        "segments")
            label     (strcat h1 "+" h2 " (overlap " (rtos (caddr info)) ")"))
      (lfc:zoom-2ents ea eb)
      (redraw ea 3)
      (redraw eb 3)
      (lfc:mark-point (car info))
      (lfc:mark-point (cadr info))
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
         (lfc:merge-lines la lb info)
         (lfc:set-color ea *lfc-olap-color*)
         (princ "\n  Merged into one line (cyan).")
         (list label "merged into one line (cyan)" 'merged ea))
        ((= ans "Flag")
         (lfc:set-color ea *lfc-olap-color*)
         (lfc:set-color eb *lfc-olap-color*)
         (princ "\n  Flagged to fix (cyan).")
         (list label
               (if (lfc:whole-line-p la)
                 (if (= (strcase lay1) (strcase lay2))
                   "flagged to fix (cyan)"
                   "different layers - flagged to fix (cyan)")
                 "polyline edge - flagged to fix (cyan)")
               'flagged ea eb))
        (t
         (princ "\n  Left as drawn.")
         (list label "left as drawn" 'left))))))

;; --- command -------------------------------------------------------

(defun c:LINFINCHECK ( / *error* oldecho vc vs undo-open ss i e et
                      cands dims arcs lns plns segs blks olaps rest e1 e2 pr
                      saved keep res n total lines ans
                      ndok ndflag ndmoved naok namoved nasnap
                      nomerged noflag noleft
                      sgroups scand svgroups pgroups g1 g2 stepsp svmode
                      satts attwrong attundec liners linerbadw linernostep bad w bn bh bp
                      linerstep linerfg fgstep badtags linerwiped
                      bgroups beadneed beadok beadmiss beadss beadbbs gbb
                      stepsum linersum rowtol sty g b l pair hdr
                      htsum stepht wallht wallraw tins tpat tss
                      datesum dateraw datebad
                      svbb hdim dimht htval htbad
                      wallvals wallvar wallmany htskip wallzero wallask
                      laylist locked relock lay tlist tbest cx cy tvals s d
                      dlines skiprest bordbb bordsum
                      minx miny maxx maxy bb m dhdr right dimlay units carried cmv)

  (defun *error* (msg)
    ;; put the greys back (flagged/moved items keep their colour),
    ;; re-lock what we unlocked, clear markers, close the undo group
    (foreach pair saved
      (if (and (not (member (car pair) keep)) (entget (car pair)))
        (lfc:set-color (car pair) (cdr pair))))
    (foreach l relock (lfc:set-layer-lock l T))
    (redraw)
    (if undo-open
      (progn (setvar "CMDECHO" 0) (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLINFINCHECK error: " msg)))
    (princ))

  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I"))
  (if (null ss)
    (progn
      (prompt "\nHighlight the drawing to LINFINCHECK: ")
      (setq ss (ssget))))
  (cond
    ((null ss)
     (prompt "\nNothing selected - LINFINCHECK cancelled."))
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
       (if (member et *lfc-curve-types*) (setq cands (cons e cands))))
     (setq dims  (reverse dims)
           arcs  (reverse arcs)
           lns   (reverse lns)
           plns  (reverse plns)
           blks  (reverse blks)
           cands (reverse cands)
           ;; detection runs on segments, so a run of steps or a side
           ;; view drawn as one polyline counts like separate lines
           segs  (lfc:collect-segs plns))
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
        (cal:ensure-layer *lfc-constr-layer* *lfc-constr-color*)
        (cal:ensure-layer *lfc-report-layer* *lfc-report-color*)

        ;; a locked layer swallows every fix and recolour silently -
        ;; surface that up front and offer to unlock for the run
        (setq laylist nil relock nil i 0)
        (repeat (sslength ss)
          (setq lay (cdr (assoc 8 (entget (ssname ss i))))
                i   (1+ i))
          (if (and lay (not (member lay laylist)))
            (setq laylist (cons lay laylist))))
        (setq locked (vl-remove-if-not 'lfc:layer-locked-p laylist))
        (if locked
          (if (cal:ask-yn
                (strcat "\n" (itoa (length locked))
                        " locked layer(s) in the selection ("
                        (lfc:join locked ", ")
                        ") - LINFINCHECK cannot recolour or fix anything on them. Unlock for this run?")
                "Yes")
            (progn
              (foreach l locked (lfc:set-layer-lock l nil))
              (setq relock locked)
              (princ "\n  Unlocked; they will be re-locked when the run ends."))
            (princ "\n  Locked layers stay locked - items on them are reported but left untouched.")))

        ;; a rerun replaces the previous run's report and markers
        (lfc:clear-old)

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
        ;; (*lfc-style-order*), then row by row, left to right
        (setq rowtol (if (and miny maxy (> (- maxy miny) 1e-8))
                       (* 0.05 (- maxy miny))
                       1.0))
        (setq dims (lfc:sort-dims dims rowtol))

        ;; grey out the whole selection so each item can take the
        ;; stage, stashing every original colour in xdata first so
        ;; LINFINCHECKRESCUE can recover them even after a crash
        (setq i 0)
        (repeat (sslength ss)
          (setq e (ssname ss i)
                i (1+ i))
          (if (entget e)
            (progn
              (setq saved (cons (cons e (lfc:ent-color e)) saved))
              (lfc:stash-color e (lfc:ent-color e))
              (lfc:set-color e *lfc-grey-color*))))

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
          (lfc:set-color e (cdr (assoc e saved)))       ; step into the light
          (setq res (lfc:review-dim e cands (1+ n) total))
          ;; points already moved count however the prompt was answered
          (setq ndmoved (+ ndmoved (cadddr res)))
          (cond
            ((eq (cadr res) 'skip)
             (lfc:set-color e *lfc-grey-color*)
             (setq skiprest T)
             (princ (strcat "\n  Skipping the remaining "
                            (itoa (- total n)) " dimension(s).")))
            ((eq (cadr res) 'back)
             ;; undo what the previous item recorded, then redo it
             (lfc:set-color e *lfc-grey-color*)
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
                 (lfc:set-color e1 *lfc-grey-color*)
                 (princ "\n  Stepping back one dimension."))
               (princ "\n  Already at the first dimension."))
             (setq n (1- n)))                            ; loop's 1+ re-enters it
            (t
             (if (cadr res)
               (progn (setq ndok (1+ ndok))
                      (lfc:set-color e *lfc-grey-color*))
               (progn (setq ndflag (1+ ndflag))
                      (setq keep (cons e keep))))
             (setq sty (lfc:dim-style e))
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
          (lfc:set-color e (cdr (assoc e saved)))
          (setq res (lfc:review-arc e cands n total))
          (setq nasnap (+ nasnap (cadddr res)))
          (if (cadr res)
            (progn (setq naok (1+ naok))
                   (lfc:set-color e *lfc-grey-color*))
            (progn (setq namoved (1+ namoved))
                   (setq keep (cons e keep))))           ; moved: stays magenta
          (setq lines (cons (strcat "Arc " (car res) ": " (caddr res)) lines)))

        ;; --- overlapping lines, one pair at a time ------------------
        (setq olaps (lfc:find-overlaps segs))
        (if olaps
          (princ (strcat "\n--- Reviewing " (itoa (length olaps))
                         " overlapping line pair(s): Enter = merge, F = flag, L = leave ---")))
        (setq n 0 total (length olaps))
        (foreach pr olaps
          (setq n  (1+ n)
                e1 (lfc:seg-ent (car pr))
                e2 (lfc:seg-ent (cadr pr)))
          (lfc:stage e1 saved keep)
          (lfc:stage e2 saved keep)
          (setq res (lfc:review-olap (car pr) (cadr pr) n total))
          (cond
            ((null res)                       ; absorbed by an earlier merge
             (lfc:unstage e1 keep)
             (lfc:unstage e2 keep))
            ((eq (caddr res) 'left)
             (setq noleft (1+ noleft))
             (lfc:unstage e1 keep)
             (lfc:unstage e2 keep)
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
        (setq sgroups  (lfc:step-groups
                         segs
                         (min *lfc-step-minlines* *lfc-bench-minlines*))
              svgroups nil
              stepsp   nil
              svmode   nil
              satts    nil
              attwrong nil
              attundec nil
              bgroups  nil)
        ;; a staircase side view reads as two step patterns at right
        ;; angles to each other (treads + risers) in the same spot
        (setq scand (vl-remove-if-not 'lfc:staircase-p sgroups))
        (setq rest scand)
        (while rest
          (setq g1 (car rest))
          (foreach g2 (cdr rest)
            (if (and (> (cal:ang-diff (car g1) (car g2)) (- (* 0.5 pi) 0.09))
                     (lfc:boxes-touch (lfc:pts-bbox (cdr g1))
                                       (lfc:pts-bbox (cdr g2))
                                       *lfc-step-maxgap*))
              (progn
                (if (not (member g1 svgroups)) (setq svgroups (cons g1 svgroups)))
                (if (not (member g2 svgroups)) (setq svgroups (cons g2 svgroups))))))
          (setq rest (cdr rest)))
        ;; only full-size patterns are worth asking about; the short
        ;; bench-sized ones matter solely as side-view halves
        (setq pgroups (vl-remove-if
                        '(lambda (g)
                           (or (member g svgroups)
                               (< (length (cdr g)) *lfc-step-minlines*)))
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
             (foreach e (lfc:group-ents g) (lfc:stage e saved keep))
             (lfc:zoom-box (lfc:pts-bbox (cdr g)))
             (foreach e (lfc:group-ents g) (if (entget e) (redraw e 3)))
             (princ (strcat "\n\nStep pattern " (itoa n) " of " (itoa total) ": "
                            (itoa (length (cdr g)))
                            " parallel lines stacked less than "
                            (rtos *lfc-step-maxgap*) " apart."))
             (setq ans (cal:ask-yn "\n  Are these lines steps?" "Yes"))
             (foreach e (lfc:group-ents g) (if (entget e) (redraw e 4)))
             (foreach e (lfc:group-ents g) (lfc:unstage e keep))
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
                (if (cal:ask-yn "\n  Is a side view of the steps drawn somewhere?" "Yes")
                  (setq svmode 'user))))
            (if (null svmode)
              (progn
                (princ "\n  Note: ADD A SIDE VIEW of the steps.")
                (setq lines (cons "Steps: NO SIDE VIEW - add a side view of the steps"
                                  lines)))
              (progn                          ; side view present: demand the block
                (setq satts (vl-remove-if-not
                              '(lambda (b) (lfc:ins-matches b "Step Attachment"))
                              blks))
                (if (null satts)
                  (progn
                    (princ "\n  Note: no 'Step Attachment' block found - add one.")
                    (setq lines (cons "Steps: side view present but NO 'Step Attachment' block - add one"
                                      lines)))
                  (foreach b satts
                    (lfc:stage b saved keep)
                    (lfc:zoom-ent b)
                    (redraw b 3)
                    (setq ans (cal:ask-yn
                                (strcat "\n  Step Attachment block "
                                        (cdr (assoc 5 (entget b)))
                                        " - is the correct one placed?")
                                "Yes"))
                    (redraw b 4)
                    (redraw)
                    (if ans
                      (progn
                        (lfc:unstage b keep)
                        (setq lines (cons (strcat "Step Attachment "
                                                  (cdr (assoc 5 (entget b)))
                                                  ": confirmed correct")
                                          lines)))
                      (progn
                        (setq attwrong T)
                        (lfc:set-color b *lfc-flag-color*)
                        (setq keep (cons b keep))
                        (setq lines (cons (strcat "Step Attachment "
                                                  (cdr (assoc 5 (entget b)))
                                                  ": WRONG ONE - flagged to fix (red)")
                                          lines))))
                    ;; every option still showing = nobody picked one,
                    ;; so the drawing has to ask the question instead
                    (if (lfc:attach-undecided-p b)
                      (if (lfc:drawing-has-phrase *lfc-secured-phrase*)
                        (progn
                          (setq attundec 'asked)
                          (princ (strcat "\n  All "
                                         (itoa (length *lfc-attach-options*))
                                         " attachment options are still showing, and the drawing asks '"
                                         *lfc-secured-phrase* "?' - waiting on the customer."))
                          (setq lines (cons (strcat "Step Attachment "
                                                    (cdr (assoc 5 (entget b)))
                                                    ": all "
                                                    (itoa (length *lfc-attach-options*))
                                                    " options still shown ("
                                                    (lfc:join *lfc-attach-options* "/")
                                                    ") and a '" *lfc-secured-phrase*
                                                    "?' note is present - waiting on the customer")
                                            lines)))
                        (progn
                          (setq attundec 'unasked)
                          (princ (strcat "\n  Note: all attachment options are still showing but NOTHING asks '"
                                         *lfc-secured-phrase* "?' - add the note."))
                          (setq lines (cons (strcat "Step Attachment "
                                                    (cdr (assoc 5 (entget b)))
                                                    ": all "
                                                    (itoa (length *lfc-attach-options*))
                                                    " options still shown ("
                                                    (lfc:join *lfc-attach-options* "/")
                                                    ") but NOTHING asks '"
                                                    *lfc-secured-phrase*
                                                    "?' - add the note")
                                            lines)))))))))))

        ;; --- Bead Track check (bead step attachments only) ----------
        ;; when the attachment style is "Bead Step Attachment", each
        ;; plan-view step pattern needs bead track drawn nearby; the
        ;; side view is exempt. The WHOLE drawing is searched, not
        ;; just the selection.
        (setq beadneed nil beadok 0 beadmiss 0)
        (if (and satts
                 bgroups
                 (vl-some '(lambda (b) (lfc:ins-matches b "Bead Step Attachment"))
                          satts))
          (progn
            (setq beadneed T)
            (princ (strcat "\n--- Bead Track check: attachment style is 'Bead Step Attachment' ---"))
            (setq beadss  (ssget "_X" (list (cons 8 *lfc-bead-layer*)))
                  beadbbs nil
                  i       0)
            (if beadss
              (repeat (sslength beadss)
                (setq bb (cal:bbox-ent (ssname beadss i))
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
                (if (lfc:block-has-layer-p (cdr (assoc 2 (entget b)))
                                            *lfc-bead-layer* 2)
                  (progn
                    (setq bb (cal:bbox-ent b))
                    (if bb (setq beadbbs (cons bb beadbbs)))))))
            (foreach g bgroups
              (setq gbb (lfc:pts-bbox (cdr g)))
              (if (and gbb beadbbs (lfc:bead-near-p gbb beadbbs))
                (progn
                  (setq beadok (1+ beadok))
                  (setq lines (cons (strcat "Bead Track: present near step pattern of "
                                            (itoa (length (cdr g))) " lines")
                                    lines)))
                (progn
                  (setq beadmiss (1+ beadmiss))
                  (princ (strcat "\n  Note: nothing on layer '" *lfc-bead-layer*
                                 "' near a step pattern - add bead track."))
                  (setq lines (cons (strcat "Bead Track: NOTHING on layer '"
                                            *lfc-bead-layer*
                                            "' near step pattern of "
                                            (itoa (length (cdr g)))
                                            " lines - add bead track")
                                    lines)))))))

        ;; --- Tech Title WallHt & overall height ---------------------
        ;; the title block's wall height is validated whenever a Tech
        ;; Title exists - steps or no steps - and the side view's rise
        ;; is compared against it when steps are present
        (setq htsum nil stepht nil wallht nil wallraw nil tins nil
              svbb nil hdim nil dimht nil htval nil htbad nil
              wallvals nil wallvar nil wallmany nil htskip nil
              wallzero nil wallask nil)
        ;; overall height from the steps
        (if stepsp
          (cond
            ((eq svmode 'auto)               ; side view found: measure it
             (setq svbb (lfc:pts-bbox (apply 'append (mapcar 'cdr svgroups))))
             (if svbb (setq stepht (- (cadr (cadr svbb)) (cadr (car svbb))))))
            ((eq svmode 'user)               ; user says it exists elsewhere
             (princ "\n  Confirm the overall step height against the Tech Title.")
             (setq stepht (getdist "\n  Type the overall step height or pick two points <skip>: ")))))
        ;; every Tech Title block: those in the selection, else
        ;; drawing-wide; the one nearest the checked area wins, and
        ;; titles that disagree on WallHt are called out
        (setq tpat  (strcat "*" (lfc:squash *lfc-title-block*) "*")
              tlist nil)
        (foreach b blks
          (if (wcmatch (lfc:squash (lfc:block-name b)) tpat)
            (setq tlist (cons b tlist))))
        (if (null tlist)
          (progn
            (setq tss (ssget "_X" '((0 . "INSERT")))
                  i   0)
            (if tss
              (repeat (sslength tss)
                (setq b (ssname tss i)
                      i (1+ i))
                (if (wcmatch (lfc:squash (lfc:block-name b)) tpat)
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
              (setq s (lfc:ins-attrib b *lfc-wallht-tag*))
              (if s
                (progn
                  (setq s (lfc:norm-text (lfc:after-eq s)))
                  (if (not (member s tvals))
                    (setq tvals (cons s tvals))))))
            (if (> (length tvals) 1)
              (progn
                (princ (strcat "\n  Note: " (itoa (length tlist)) " '"
                               *lfc-title-block* "' blocks disagree on "
                               *lfc-wallht-tag* "; using the nearest one."))
                (setq lines (cons (strcat (itoa (length tlist)) " '"
                                          *lfc-title-block*
                                          "' blocks DISAGREE on "
                                          *lfc-wallht-tag*
                                          " - CHECK THE WALL HEIGHT (nearest one used)")
                                  lines))))))
        (if tins
          (setq wallraw  (lfc:ins-attrib-deep tins *lfc-wallht-tag*)
                wallvals (if wallraw (lfc:len-values wallraw))
                wallvar  (and wallraw (lfc:varies-p wallraw))
                wallmany (> (length wallvals) 1)
                wallzero (and wallvals (not wallmany)
                              (< (car wallvals) *lfc-min-wallht*))
                wallask  (and (null wallvals)
                              wallraw
                              (vl-string-search "?" (lfc:after-eq wallraw)))
                wallht   (if (and wallvals (not wallmany) (not wallzero))
                           (car wallvals))))
        ;; Varies, several heights, a nonsensical zero or a "?" give
        ;; nothing to check the side view against - leave it alone
        ;; rather than marking a dimension red
        (setq htskip (or wallvar wallmany wallzero wallask))
        ;; the side view's own overall-height dimension, and the
        ;; height it states - that dimension is what gets compared
        (if (and svbb stepht (not htskip))
          (setq hdim (lfc:height-dim dims svbb stepht)))
        (if hdim (setq dimht (lfc:dim-stated hdim)))
        (setq htval (if dimht dimht stepht))
        (setq htbad (and htval wallht
                         (> (abs (- htval wallht)) *lfc-height-tol*)))
        ;; a dimension that disagrees with the title block is wrong:
        ;; mark it red automatically and keep it red
        (if (and htbad hdim)
          (progn
            (lfc:set-color hdim *lfc-flag-color*)
            (if (not (member hdim keep)) (setq keep (cons hdim keep)))
            (princ (strcat "\n  Side view height dimension "
                           (cdr (assoc 5 (entget hdim)))
                           " disagrees with " *lfc-wallht-tag*
                           " - marked red."))
            (setq lines (cons (strcat "Height dim "
                                      (cdr (assoc 5 (entget hdim)))
                                      " states " (rtos dimht)
                                      " but " *lfc-wallht-tag* " is '"
                                      wallraw "' - MISMATCH, marked red")
                              lines))))
        ;; a dimension whose text was overridden to disagree with
        ;; the geometry it spans is wrong too
        (if (and hdim dimht stepht
                 (> (abs (- dimht stepht)) *lfc-height-tol*))
          (progn
            (lfc:set-color hdim *lfc-flag-color*)
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
            ((and (null tins) stepsp)
             (strcat "steps rise " (if htval (rtos htval) "?") " but no '"
                     *lfc-title-block* "' block was found - NOT CONFIRMED"))
            ((null tins) nil)                 ; no title, no steps: quiet
            (wallvar
             (strcat *lfc-wallht-tag* " reads '" wallraw "' - height varies"
                     (if htval ", side view left alone" "")))
            (wallmany
             (strcat *lfc-wallht-tag* " holds " (itoa (length wallvals))
                     " heights ('" wallraw "') - CHECK THE WALL HEIGHT in the "
                     *lfc-title-block*
                     (if htval ", side view left alone" "")))
            (wallzero
             (strcat *lfc-wallht-tag* " is '" wallraw
                     "' - a NONSENSICAL wall height, fix the "
                     *lfc-title-block*))
            (wallask
             (if (lfc:drawing-has-phrase *lfc-ask-phrase*)
               (strcat *lfc-wallht-tag* " reads '" wallraw
                       "' and the drawing asks for the wall height - waiting on the customer")
               (strcat *lfc-wallht-tag* " reads '" wallraw
                       "' but NOTHING in the drawing asks for it - add a '"
                       *lfc-ask-phrase* "' note for the customer")))
            ((null wallht)
             (strcat "the " *lfc-wallht-tag* " attribute "
                     (if wallraw
                       (strcat "'" wallraw "' is unreadable")
                       "is missing")
                     " - NOT CONFIRMED"))
            ((null htval)
             (if stepsp
               "steps present but their overall height was NOT CONFIRMED (no side view measured)"
               (strcat *lfc-wallht-tag* " = '" wallraw "' - OK")))
            ((not htbad)
             (strcat "steps rise " (rtos htval) " = WallHt '" wallraw
                     "' - MATCHES"))
            (t
             (strcat "steps rise " (rtos htval) " but WallHt is '" wallraw
                     "' (" (rtos wallht) ") - MISMATCH"
                     (if hdim ", dimension marked red" ", look at it")))))
        (if htsum (princ (strcat "\n  Wall height: " htsum)))

        ;; --- Tech Title Date ------------------------------------------
        ;; runs whenever a Tech Title exists, independent of steps
        (setq datesum nil dateraw nil datebad nil)
        (if tins
          (progn
            (setq dateraw (lfc:ins-attrib-deep tins *lfc-date-tag*))
            (setq datebad
              (if dateraw
                (lfc:date-verdict dateraw)
                "is missing - expected MM/DD/YYYY"))
            (setq datesum
              (if datebad
                (strcat *lfc-date-tag* " " datebad)
                (strcat *lfc-date-tag* " = '" dateraw "' - OK")))
            (princ (strcat "\n  Date: " datesum)))
          (setq datesum (strcat "no '" *lfc-title-block*
                                "' block in reach - date NOT CHECKED")))

        ;; --- Liner Material check -----------------------------------
        (setq liners      (vl-remove-if-not
                            '(lambda (b) (lfc:ins-matches b "Liner Material"))
                            blks)
              linerbadw   nil
              linernostep nil
              linerstep   nil
              linerfg     nil
              linerwiped  0
              fgstep      (lfc:fgstep-src ss blks))
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
              (setq bn      (lfc:block-name b)
                    bh      (cdr (assoc 5 (entget b)))
                    bp      (cdr (assoc 10 (entget b)))
                    badtags (lfc:attrib-bad-tags b *lfc-badwords*)
                    bad     nil)
              (foreach w *lfc-badwords*
                (if (lfc:ins-has-word b w)
                  (setq bad (append bad (list w)))))
              (foreach w bad
                (if (not (member w linerbadw))
                  (setq linerbadw (append linerbadw (list w)))))
              (cond
                ;; a pattern field that says "Not Supplied" or carries an
                ;; ERROR was never filled in - wipe it back to blank so
                ;; the block reads clean, and say which fields went
                (badtags
                 (lfc:wipe-attribs b badtags)
                 (setq linerwiped (+ linerwiped (length badtags)))
                 (princ (strcat "\n  '" bn "': wiped "
                                (lfc:join badtags ", ") " clean."))
                 (setq lines (cons (strcat "Liner Material (" bn ") " bh " at "
                                           (lfc:ptstr bp) ": "
                                           (lfc:join badtags ", ")
                                           " carried " (lfc:join bad " & ")
                                           " - WIPED clean")
                                   lines)))
                ;; the word sits in the block's own text, not in a field
                ;; we can clear - report it and leave it alone
                (bad
                 (princ (strcat "\n  Note: '" bn "' contains the word "
                                (lfc:join bad " & ") " - look at it."))
                 (setq lines (cons (strcat "Liner Material (" bn ") " bh " at "
                                           (lfc:ptstr bp)
                                           ": contains the word "
                                           (lfc:join bad " & ")
                                           " - look at it")
                                   lines)))
                (t
                 (setq lines (cons (strcat "Liner Material (" bn ") " bh ": OK")
                                   lines)))))
            (setq linerstep (vl-some '(lambda (b) (lfc:ins-has-word b "STEP"))
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
        ;; ones keep it so LINFINCHECKRESCUE can clear the marks later
        (foreach pair saved
          (if (and (not (member (car pair) keep)) (entget (car pair)))
            (progn
              (lfc:set-color (car pair) (cdr pair))
              (lfc:unstash (car pair)))))
        (foreach l relock (lfc:set-layer-lock l T))
        (setq relock nil)

        ;; --- title block border size --------------------------------
        ;; the whole title block is normally in the selection; fall
        ;; back to the drawing when the border was not highlighted
        (setq bordbb (lfc:border-box ss))
        (if (null bordbb)
          (setq bordbb (lfc:border-box
                         (ssget "_X" (list (cons 8 *lfc-border-layer*))))))
        (setq bordsum (lfc:border-verdict bordbb))
        (princ (strcat "\n--- Border: " bordsum " ---"))

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
                         (cond ((eq attundec 'unasked)
                                (strcat "; every attachment option still shown, NOTHING asks '"
                                        *lfc-secured-phrase* "?'"))
                               ((eq attundec 'asked)
                                "; attachment not chosen yet, the drawing asks the question")
                               (t ""))
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
                         (if (> linerwiped 0)
                           (strcat "; " (itoa linerwiped)
                                   " pattern field(s) WIPED clean")
                           (if linerbadw
                             (strcat "; word " (lfc:join linerbadw " & ")
                                     " found - review")
                             ""))
                         (if linernostep
                           "; steps drawn but liner MISSING its Step"
                           "")
                         (if linerfg
                           "; Fiberglass Step in the drawing but the liner HAS a Step"
                           "")
                         (if (and (null linerbadw) (not linernostep) (not linerfg)
                                  (= linerwiped 0))
                           " - OK"
                           "")))))

        ;; --- report on the right side, to scale with the drawing ----
        ;; the liner-finish checks lead on the main sheet; the
        ;; DIMCHECK-style findings go in the DIMENSION AUDIT column
        ;; beside it
        (setq dhdr
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
                  (> noflag 0))))
        (setq dimlay (lfc:dimlayer-verdict dims)
              units  (lfc:audit-units ss))
        (foreach l (caddr units)
          (princ (strcat "\n  " l))
          (setq lines (cons l lines)))
        (setq hdr
          (list
            (cons (strcat "Dimension layer: " (car dimlay)) (cdr dimlay))
            (cons (strcat "Feet & inches: " (car units)) (cadr units))
            (cons (strcat "Steps: " stepsum)          (lfc:attn-p stepsum))
            (cons (strcat "Liner Material: " linersum) (lfc:attn-p linersum))
            (cons (strcat "Title block border: " bordsum) (lfc:attn-p bordsum))))
        (if htsum
          (setq hdr (append hdr (list (cons (strcat "Wall height: " htsum)
                                            (lfc:attn-p htsum))))))
        (if datesum
          (setq hdr (append hdr (list (cons (strcat "Date: " datesum)
                                            (lfc:attn-p datesum))))))
        (setq right (lfc:write-report "LINFINCHECK REPORT" nil hdr dhdr
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
        (princ (strcat "\n\n--- LINFINCHECK complete ---"
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
                       (if htsum (strcat "\nWall height: " htsum) "")
                       (if datesum (strcat "\nDate: " datesum) "")
                       "\nLiner Material: " linersum
                       "\nTitle block border: " bordsum
                       "\nReport placed on the right side of the drawing (layer "
                       *lfc-report-layer* ")."
                       (if (> ndmoved 0)
                         (strcat "\nConstruction lines through moved dimensions' original points are on layer "
                                 *lfc-constr-layer* ".")
                         "")
                       "\nOne UNDO reverts everything LINFINCHECK changed (including the report)."))))))
  (princ))

;; --- LINFINSCAN / LITELINFINSCAN: the read-only twins -----------------
;;  LITELINFINSCAN skips the DIMCHECK-style pass entirely - no
;;  dimension, arc or overlap audit and no DIMENSION AUDIT column -
;;  for a drawing DIMCHECK already went over.
;;  Runs every audit, asks nothing, and changes nothing in the drawing
;;  except writing the report. Use it as a quick pre-flight, or when
;;  you want the findings without touching a released sheet.

(defun c:LINFINSCAN () (lfc:scan nil))

(defun c:LITELINFINSCAN () (lfc:scan T))

;; The read-only scan.  lite = T skips the DIMCHECK-style pass - no
;; dimension, arc or overlap audit and no DIMENSION AUDIT column -
;; for a drawing DIMCHECK already went over.
(defun lfc:scan (lite / *error* oldecho name ss i e et ed cands dims arcs
                     plns segs
                     blks lines olaps pr sgroups scand svgroups pgroups
                     g g1 g2 rest svbb stepht satts liners fgstep linerstep
                     beadss beadbbs bb gbb tlist tins bp cx cy d tbest
                     wallraw wallvals wallvar wallmany wallzero wallask
                     wallht hdim dimht
                     htval htbad htsum stepsum linersum bad wnd
                     datesum dateraw datebad
                     nd ndbad na nabad m hdr dhdr l badtags dimlay units
                     bordbb bordsum attundec
                     minx miny maxx maxy p13 p14 near s b w)

  (setq name (if lite "LITELINFINSCAN" "LINFINSCAN"))
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
       (if (member et *lfc-curve-types*) (setq cands (cons e cands)))
       (setq bb (cal:bbox-ent e))
       (if bb
         (setq minx (if minx (min minx (caar bb)) (caar bb))
               miny (if miny (min miny (cadar bb)) (cadar bb))
               maxx (if maxx (max maxx (caadr bb)) (caadr bb))
               maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))
     ;; segs feeds TWO passes: the DIMCHECK-style overlap hunt, which a
     ;; lite scan skips, and the steps / side-view rule, which is a
     ;; LINER rule a lite scan keeps.  Nil'ing it for lite took the
     ;; steps rule out with the overlaps, so a sheet with an obvious
     ;; staircase reported "no step patterns detected" and its
     ;; rise-vs-WallHt mismatch vanished.  Collect it either way; the
     ;; overlap pass keeps its own lite guard below.
     (setq dims (reverse dims) arcs (reverse arcs)
           plns (reverse plns) blks (reverse blks) cands (reverse cands)
           segs (lfc:collect-segs plns))

     ;; --- dimensions: report stray definition points, move nothing
     ;;     (a lite scan leaves the DIMCHECK-style pass out entirely)
     (foreach e (if lite
                  nil
                  (lfc:sort-dims dims (if (and miny maxy)
                                        (* 0.05 (- maxy miny)) 1.0)))
       (setq ed  (entget e)
             nd  (1+ nd)
             p13 (cdr (assoc 13 ed))
             p14 (cdr (assoc 14 ed))
             bad nil)
       (if (member (logand 7 (cdr (assoc 70 ed))) '(0 1))
         (foreach s (list (cons "point 1" p13) (cons "point 2" p14))
           (if (cdr s)
             (progn
               (setq near (lfc:nearest-curve (cdr s) nil cands))
               (if (and near (> (caddr near) *lfc-tol*))
                 (setq bad (append bad (list (strcat (car s) " off by "
                                                     (rtos (caddr near) 2 4))))))))))
       (if bad (setq ndbad (1+ ndbad)))
       (setq lines (cons (strcat "Dim " (cdr (assoc 5 ed))
                                 (if (= (lfc:dim-style e) "") ""
                                   (strcat " [" (lfc:dim-style e) "]"))
                                 (if (lfc:dim-meas e)
                                   (strcat " = " (lfc:dim-meas e)) "")
                                 ": "
                                 (if bad
                                   (strcat "NOT attached - " (lfc:join bad ", "))
                                   "OK")
                                 (if (lfc:dim-assoc-p e) " (associative)" ""))
                         lines)))

     ;; --- arcs: report unattached endpoints, move nothing
     (foreach e (if lite nil arcs)
       (setq na  (1+ na)
             bad nil)
       (if (lfc:planar-arc-p (entget e))
         (foreach s '(("start" . start) ("end" . end))
           (if (lfc:arc-end-target e (cdr s) cands)
             (setq bad (append bad (list (car s)))))))
       (if bad (setq nabad (1+ nabad)))
       (setq lines (cons (strcat "Arc " (cdr (assoc 5 (entget e))) ": "
                                 (if bad
                                   (strcat (lfc:join bad " & ")
                                           " NOT attached to an object end")
                                   "endpoints OK"))
                         lines)))

     ;; --- overlaps
     (setq olaps (if lite nil (lfc:find-overlaps segs)))
     (foreach pr olaps
       (setq lines (cons (strcat "Lines "
                                 (cdr (assoc 5 (entget (lfc:seg-ent (car pr)))))
                                 "+"
                                 (cdr (assoc 5 (entget (lfc:seg-ent (cadr pr)))))
                                 ": OVERLAP of "
                                 (rtos (caddr (lfc:overlap-info (car pr) (cadr pr))))
                                 " - flagged")
                         lines)))

     ;; --- steps / side view (detection only, nothing asked)
     (setq sgroups (lfc:step-groups segs (min *lfc-step-minlines*
                                               *lfc-bench-minlines*))
           scand   (vl-remove-if-not 'lfc:staircase-p sgroups)
           rest    scand)
     (while rest
       (setq g1 (car rest))
       (foreach g2 (cdr rest)
         (if (and (> (cal:ang-diff (car g1) (car g2)) (- (* 0.5 pi) 0.09))
                  (lfc:boxes-touch (lfc:pts-bbox (cdr g1))
                                    (lfc:pts-bbox (cdr g2))
                                    *lfc-step-maxgap*))
           (progn
             (if (not (member g1 svgroups)) (setq svgroups (cons g1 svgroups)))
             (if (not (member g2 svgroups)) (setq svgroups (cons g2 svgroups))))))
       (setq rest (cdr rest)))
     (setq pgroups (vl-remove-if
                     '(lambda (x) (or (member x svgroups)
                                      (< (length (cdr x)) *lfc-step-minlines*)))
                     sgroups))
     (if svgroups
       (setq svbb   (lfc:pts-bbox (apply 'append (mapcar 'cdr svgroups)))
             stepht (- (cadr (cadr svbb)) (cadr (car svbb)))))
     (setq satts (vl-remove-if-not
                   '(lambda (x) (lfc:ins-matches x "Step Attachment")) blks))
     ;; every attachment option still showing = nobody picked one
     (setq attundec nil)
     (foreach b satts
       (if (and (null attundec) (lfc:attach-undecided-p b))
         (progn
           (setq attundec (if (lfc:drawing-has-phrase *lfc-secured-phrase*)
                            'asked 'unasked))
           (setq lines (cons (strcat "Step Attachment "
                                     (cdr (assoc 5 (entget b)))
                                     ": all "
                                     (itoa (length *lfc-attach-options*))
                                     " options still shown ("
                                     (lfc:join *lfc-attach-options* "/")
                                     (if (eq attundec 'asked)
                                       (strcat ") and a '" *lfc-secured-phrase*
                                               "?' note is present - waiting on the customer")
                                       (strcat ") but NOTHING asks '"
                                               *lfc-secured-phrase*
                                               "?' - add the note")))
                             lines)))))
     (setq stepsum
           (cond
             ((and (null svgroups) (null pgroups)) "no step patterns detected")
             (svgroups
              (strcat "side view detected, rise " (rtos stepht)
                      (if satts "; Step Attachment present"
                        "; Step Attachment block MISSING - add one")
                      (cond ((eq attundec 'unasked)
                             (strcat "; every option still shown, NOTHING asks '"
                                     *lfc-secured-phrase* "?'"))
                            ((eq attundec 'asked)
                             "; attachment not chosen yet, the drawing asks the question")
                            (t ""))))
             (t (strcat (itoa (length pgroups))
                        " possible step pattern(s) - run LINFINCHECK to confirm"))))
     (foreach g pgroups
       (setq lines (cons (strcat "Steps: possible pattern of "
                                 (itoa (length (cdr g))) " parallel lines")
                         lines)))
     ;; bead track when the attachment is a bead one
     (if (and satts svgroups
              (vl-some '(lambda (x) (lfc:ins-matches x "Bead Step Attachment"))
                       satts))
       (progn
         (setq beadss (ssget "_X" (list (cons 8 *lfc-bead-layer*))) i 0)
         (if beadss
           (repeat (sslength beadss)
             (setq bb (cal:bbox-ent (ssname beadss i)) i (1+ i))
             (if bb (setq beadbbs (cons bb beadbbs)))))
         (foreach g pgroups
           (setq gbb (lfc:pts-bbox (cdr g)))
           (if (not (and gbb beadbbs (lfc:bead-near-p gbb beadbbs)))
             (setq lines (cons (strcat "Bead Track: NOTHING on layer '"
                                       *lfc-bead-layer*
                                       "' near a step pattern - add bead track")
                               lines))))))

     ;; --- wall height
     (setq tlist (vl-remove-if-not
                   '(lambda (x) (wcmatch (lfc:squash (lfc:block-name x))
                                         (strcat "*" (lfc:squash *lfc-title-block*) "*")))
                   blks))
     (if (null tlist)
       (progn
         (setq beadss (ssget "_X" '((0 . "INSERT"))) i 0)
         (if beadss
           (repeat (sslength beadss)
             (setq b (ssname beadss i) i (1+ i))
             (if (wcmatch (lfc:squash (lfc:block-name b))
                          (strcat "*" (lfc:squash *lfc-title-block*) "*"))
               (setq tlist (cons b tlist)))))))
     (setq cx (if minx (* 0.5 (+ minx maxx)) 0.0)
           cy (if miny (* 0.5 (+ miny maxy)) 0.0))
     (foreach b tlist
       (setq bp (cdr (assoc 10 (entget b)))
             d  (distance (list cx cy) (list (car bp) (cadr bp))))
       (if (or (null tbest) (< d tbest)) (setq tbest d tins b)))
     (if tins
       (setq wallraw  (lfc:ins-attrib-deep tins *lfc-wallht-tag*)
             wallvals (if wallraw (lfc:len-values wallraw))
             wallvar  (and wallraw (lfc:varies-p wallraw))
             wallmany (> (length wallvals) 1)
             wallzero (and wallvals (not wallmany)
                           (< (car wallvals) *lfc-min-wallht*))
             wallask  (and (null wallvals)
                           wallraw
                           (vl-string-search "?" (lfc:after-eq wallraw)))
             wallht   (if (and wallvals (not wallmany) (not wallzero))
                        (car wallvals))))
     (if (and svbb stepht (not (or wallvar wallmany wallzero wallask)))
       (setq hdim (lfc:height-dim dims svbb stepht)))
     (if hdim (setq dimht (lfc:dim-stated hdim)))
     (setq htval (if dimht dimht stepht)
           htbad (and htval wallht (> (abs (- htval wallht)) *lfc-height-tol*)))
     (setq htsum
           (cond
             ((and (null tins) (null htval)) nil)
             ((null tins) (strcat "steps rise " (rtos htval) " but no '"
                                  *lfc-title-block* "' block found - NOT CONFIRMED"))
             (wallvar (strcat *lfc-wallht-tag* " reads '" wallraw
                              "' - height varies, not checked"))
             (wallmany (strcat *lfc-wallht-tag* " holds "
                               (itoa (length wallvals)) " heights ('" wallraw
                               "') - CHECK THE WALL HEIGHT in the " *lfc-title-block*))
             (wallzero (strcat *lfc-wallht-tag* " is '" wallraw
                               "' - a NONSENSICAL wall height, fix the "
                               *lfc-title-block*))
             (wallask
              (if (lfc:drawing-has-phrase *lfc-ask-phrase*)
                (strcat *lfc-wallht-tag* " reads '" wallraw
                        "' and the drawing asks for the wall height - waiting on the customer")
                (strcat *lfc-wallht-tag* " reads '" wallraw
                        "' but NOTHING in the drawing asks for it - add a '"
                        *lfc-ask-phrase* "' note for the customer")))
             ((null wallht) (strcat "the " *lfc-wallht-tag* " attribute "
                                    (if wallraw
                                      (strcat "'" wallraw "' is unreadable")
                                      "is missing")
                                    " - NOT CONFIRMED"))
             ((null htval) (strcat *lfc-wallht-tag* " = '" wallraw "' - OK"))
             ((not htbad) (strcat "steps rise " (rtos htval) " = WallHt '"
                                  wallraw "' - MATCHES"))
             (t (strcat "steps rise " (rtos htval) " but WallHt is '" wallraw
                        "' (" (rtos wallht) ") - MISMATCH"))))

     ;; --- Tech Title Date (read-only twin of LINFINCHECK's check)
     (setq datesum nil dateraw nil datebad nil)
     (if tins
       (progn
         (setq dateraw (lfc:ins-attrib-deep tins *lfc-date-tag*))
         (setq datebad
           (if dateraw
             (lfc:date-verdict dateraw)
             "is missing - expected MM/DD/YYYY"))
         (setq datesum
           (if datebad
             (strcat *lfc-date-tag* " " datebad)
             (strcat *lfc-date-tag* " = '" dateraw "' - OK"))))
          (setq datesum (strcat "no '" *lfc-title-block*
                                "' block in reach - date NOT CHECKED")))

     ;; --- liner
     (setq liners (vl-remove-if-not
                    '(lambda (x) (lfc:ins-matches x "Liner Material")) blks)
           fgstep (lfc:fgstep-src ss blks))
     (if liners
       (setq linerstep (vl-some '(lambda (x) (lfc:ins-has-word x "STEP")) liners)))
     (foreach b liners
       (setq bad     nil
             badtags (lfc:attrib-bad-tags b *lfc-badwords*))
       (foreach w *lfc-badwords*
         (if (lfc:ins-has-word b w)
           (progn (setq bad (append bad (list w)))
                  (if (not (member w wnd)) (setq wnd (append wnd (list w)))))))
       ;; read-only: say which fields LINFINCHECK would clear, clear nothing
       (setq lines (cons (strcat "Liner Material (" (lfc:block-name b) ") "
                                 (cdr (assoc 5 (entget b))) ": "
                                 (cond
                                   (badtags
                                    (strcat (lfc:join badtags ", ")
                                            " carries " (lfc:join bad " & ")
                                            " - NEEDS WIPING (run LINFINCHECK)"))
                                   (bad
                                    (strcat "contains the word "
                                            (lfc:join bad " & ") " - look at it"))
                                   (t "OK")))
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
                        (if wnd (strcat "; word " (lfc:join wnd " & ") " found - review") "")
                        (if (and fgstep linerstep)
                          "; Fiberglass Step in the drawing but the liner HAS a Step" "")
                        (if (and (null wnd) (not (and fgstep linerstep))) " - OK" "")))))

     ;; --- title block border size
     (setq bordbb (lfc:border-box ss))
     (if (null bordbb)
       (setq bordbb (lfc:border-box
                      (ssget "_X" (list (cons 8 *lfc-border-layer*))))))
     (setq bordsum (lfc:border-verdict bordbb))

     ;; --- report (the only thing the scan writes) --------------------
     (cal:ensure-layer *lfc-report-layer* *lfc-report-color*)
     (lfc:clear-old)
     (setq dhdr (if lite
                  nil
                  (list
                    (cons (strcat "Dimensions scanned: " (itoa nd) " ("
                                  (itoa ndbad)
                                  " with a stray definition point)")
                          (> ndbad 0))
                    (cons (strcat "Arcs scanned: " (itoa na) " ("
                                  (itoa nabad) " with an unattached end)")
                          (> nabad 0))
                    (cons (strcat "Overlapping line pairs: "
                                  (itoa (length olaps)))
                          (> (length olaps) 0)))))
     (setq dimlay (lfc:dimlayer-verdict dims)
           units  (lfc:audit-units ss))
     (foreach l (caddr units)
       (princ (strcat "\n  " l))
       (setq lines (cons l lines)))
     (setq hdr (list
                 (cons (strcat "Dimension layer: " (car dimlay)) (cdr dimlay))
                 (cons (strcat "Feet & inches: " (car units)) (cadr units))
                 (cons (strcat "Steps: " stepsum)           (lfc:attn-p stepsum))
                 (cons (strcat "Liner Material: " linersum) (lfc:attn-p linersum))
                 (cons (strcat "Title block border: " bordsum) (lfc:attn-p bordsum))))
     (if htsum
       (setq hdr (append hdr (list (cons (strcat "Wall height: " htsum)
                                         (lfc:attn-p htsum))))))
     (if datesum
       (setq hdr (append hdr (list (cons (strcat "Date: " datesum)
                                         (lfc:attn-p datesum))))))
     (lfc:write-report (strcat name " REPORT")
                       (strcat "Read-only scan - nothing in the drawing"
                               " was changed.  "
                               (if lite
                                 (strcat "Lite: dimensions, arcs and"
                                         " overlaps were not audited -"
                                         " run DIMCHECK or LINFINSCAN"
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
                              (itoa (length olaps))))
                    "\nSteps: " stepsum
                    "\nLiner Material: " linersum
                    "\nTitle block border: " bordsum
                    (if htsum (strcat "\nWall height: " htsum) "")
                    (if datesum (strcat "\nDate: " datesum) "")
                    "\nReport written on layer " *lfc-report-layer*
                    "; nothing else was changed."))))
  (princ))


;; --- TUTORIALLINFINCHECK: learn it two ways ---------------------------
;;  List  - every check spelled out, at the command line and (if you
;;          want) dropped into the drawing as a reference sheet.
;;  Demo  - draws a small practice drawing with faults planted in it,
;;          walks you through each one showing what LINFINCHECK sees and
;;          what the colours mean, then scans it so you see a report.
;;  Both  - the list, then the demo.
;;  Everything the demo draws is in one UNDO group and can be erased
;;  when you are done, so it never touches your real work.

(defun lfc:tut-checklist ()
  (list
    "WHAT LINFINCHECK CHECKS"
    ""
    "1. DIMENSIONS - one at a time"
    (strcat "   Order: style groups " (lfc:join *lfc-style-order* " > ")
            " > anything else,")
    "     then left to right, top to bottom inside each group."
    "   Every other object greys out; the one under review is zoomed to."
    "   A definition point not touching any object: you choose"
    "     Move (green +, onto the nearest object) / Keep (red X, exactly"
    "     where you drew it) / Pick your own spot."
    "   Then 'Is this dimension correct?'  Enter = yes,  N = flag it RED,"
    "     B = back one dimension,  S = skip the rest."
    "   The measured distance is shown, and object-associative dims are"
    "     called out (a moved point can re-anchor itself)."
    ""
    "2. ARCS - one endpoint at a time"
    "   Each end must sit at the END of another object; a loose one gets"
    "     the same Move / Keep / Pick choice. Keep restores the arc"
    "     exactly. Arcs that changed turn MAGENTA."
    ""
    "3. OVERLAPPING LINES"
    "   Collinear geometry running on top of itself, in LINEs and in"
    "     polyline edges. Touching end-to-end is fine and is not"
    "     reported. Per pair: Merge into one / Flag CYAN / Leave."
    "     Merge is offered only for two whole LINEs on one layer."
    ""
    "4. STEPS, BENCHES AND SIDE VIEWS"
    (strcat "   Step pattern = " (itoa *lfc-step-minlines*)
            "+ parallel lines stacked under "
            (rtos *lfc-step-maxgap*) " apart.")
    "   A side view is two patterns at right angles that march along"
    "     like a profile - benches (two treads) count. A rectangle or"
    "     nested plan outlines are NOT mistaken for one."
    "   No side view -> you are asked if the lines are steps, then"
    "     whether a side view exists; if not, the report says ADD ONE."
    "   Steps + side view -> a 'Step Attachment' block is required and"
    "     you confirm the right one is placed."
    (strcat "   A block still listing every option ("
            (lfc:join *lfc-attach-options* "/") ") means")
    (strcat "     nobody chose one - fine only if a '" *lfc-secured-phrase*
            "?' note asks.")
    (strcat "   'Bead Step Attachment' -> something must be on layer '"
            *lfc-bead-layer* "' within " (rtos *lfc-bead-dist*)
            " of each")
    "     plan-view step pattern (the side view itself is exempt)."
    ""
    "5. WALL HEIGHT (Tech Title)"
    (strcat "   The '" *lfc-title-block* "' block's " *lfc-wallht-tag*
            " is read whether or not")
    "     steps are drawn. 40'', 3'-4'', 3' 4 1/2'' and 40.5 all parse,"
    "     and any label before '=' is ignored."
    "     one sensible value  -> OK, and it is compared to the side view"
    "     several values      -> CHECK THE WALL HEIGHT"
    "     0'' (or near zero)  -> NONSENSICAL, fix the title block"
    (strcat "     ?                   -> only OK if a '" *lfc-ask-phrase*
            "' note asks the customer")
    "     Varies              -> fine, nothing to compare"
    "   A side-view height dim that disagrees is marked RED on its own."
    ""
    "6. DATE (Tech Title)"
    (strcat "   The '" *lfc-title-block* "' block's " *lfc-date-tag*
            " must read a real calendar")
    "     date as MM/DD/YYYY (e.g. 05/01/2024). Missing, blank, the wrong"
    "     format, or an out-of-range month/day is reported in red with"
    "     what is wrong; a clean date is a quiet OK."
    ""
    "7. LINER MATERIAL"
    "   A 'Liner Material' / 'Liner Material with Step' block must be"
    "     present."
    (strcat "   A pattern field reading " (lfc:join *lfc-badwords* " or ")
            " (e.g. 'Not Supplied',")
    "     '#ERROR') is WIPED back to blank - the label stays, the junk"
    "     goes. Real names like 'Tex' are never touched."
    "   A Fiberglass Step in the drawing -> the liner must NOT carry a"
    "     Step. Otherwise steps drawn -> the liner MUST have its Step."
    ""
    "8. TITLE BLOCK BORDER"
    (strcat "   The outer drawing on layer '" *lfc-border-layer*
            "' must be " (rtos *lfc-border-w*) " x "
            (rtos *lfc-border-h*))
    "     (58'-8'' x 45'-3 5/8'') or any scaled-UP multiple. Smaller ->"
    "     'Title block should not be SCALED DOWN for Liners'."
    "     Uneven -> STRETCHED. Nothing there -> NO BORDER."
    ""
    "9. THE REPORT"
    "   An MTEXT sheet to the right of the drawing, sized to scale with"
    (strcat "     it. Problems in RED at full size; all-clear in green at "
            (rtos (* 100.0 *lfc-green-scale*) 2 0) "%.")
    ""
    "COMMANDS"
    "   LINFINCHECK         the full interactive review (fixes things)"
    "   LINFINSCAN          the same audits, read-only - changes nothing"
    "   LINFINCHECKRESCUE   put back every colour, remove the markers"
    "   LINFINCHECKVER      which build is loaded"
    "   TUTORIALLINFINCHECK this tutorial"
    ""
    "GOOD HABITS"
    "   Highlight the whole title block so the border and the Tech Title"
    "     are included. Run LINFINSCAN first if you want to look before"
    "     anything is touched. One U undoes an entire LINFINCHECK run."))

(defun lfc:tut-pause (msg)
  (princ (strcat "\n  " msg))
  (getstring "\n  --- press Enter to continue ---")
  (princ))

(defun lfc:tut-line (p1 p2 lay)
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                 '(100 . "AcDbLine") (cons 10 p1) (cons 11 p2)))
  (entlast))

(defun lfc:tut-dim (p1 p2 dimpt rot / old res)
  ;; a linear dimension, made with the command so it is valid in any
  ;; release; osnap is muted so the picks land exactly where told,
  ;; and the command is caught so a failure cannot skip the restore -
  ;; the tutorial's handler has no way to put OSMODE back
  (setq old (getvar "OSMODE"))
  (setvar "OSMODE" 0)
  (setq res (vl-catch-all-apply
              '(lambda ()
                 (if (zerop rot)
                   (command "_.DIMLINEAR" p1 p2 "_H" dimpt)
                   (command "_.DIMLINEAR" p1 p2 "_V" dimpt)))
              nil))
  (setvar "OSMODE" old)
  (entlast))

(defun lfc:tut-demo (/ org ox oy made e ss2 i)
  (princ "\n\n--- DEMO: a practice drawing with faults planted in it ---")
  (setq org (getpoint "\n  Pick an empty spot for the practice drawing: "))
  (if (null org)
    (princ "\n  Cancelled - nothing drawn.")
    (progn
      (setq org (trans org 1 0)
            ox  (car org)
            oy  (cadr org)
            made nil)

      ;; --- fault 1: two lines overlapping ------------------------
      (setq made (cons (lfc:tut-line (list ox oy 0.0)
                                      (list (+ ox 100.0) oy 0.0) "0") made))
      (setq made (cons (lfc:tut-line (list (+ ox 60.0) oy 0.0)
                                      (list (+ ox 180.0) oy 0.0) "0") made))
      (command "_.ZOOM" "_Object" (car made) "")
      (command "_.ZOOM" "_0.4x")
      (lfc:tut-pause
        (strcat "FAULT 1 - overlapping lines.\n  Two lines run on top of each other from "
                "60 to 100: someone drew over\n  an existing line to carry on and never cleaned it up. "
                "LINFINCHECK\n  shows the overlap marked at both ends and offers Merge / Flag /\n"
                "  Leave. Lines that merely TOUCH end to end are fine and are\n  never reported."))

      ;; --- fault 2: a dim whose point misses the line -------------
      (setq made (cons (lfc:tut-line (list ox (+ oy 80.0) 0.0)
                                      (list (+ ox 120.0) (+ oy 80.0) 0.0) "0") made))
      (setq e (lfc:tut-dim (list ox (+ oy 80.0) 0.0)
                            (list (+ ox 120.0) (+ oy 88.0) 0.0)   ; 8 units OFF the line
                            (list (+ ox 60.0) (+ oy 110.0) 0.0) 0))
      (if e (setq made (cons e made)))
      (command "_.ZOOM" "_Window"
               (trans (list (- ox 20.0) (+ oy 50.0) 0.0) 0 1)
               (trans (list (+ ox 150.0) (+ oy 130.0) 0.0) 0 1))
      (lfc:tut-pause
        (strcat "FAULT 2 - a dimension point off the geometry.\n"
                "  The right-hand point of this dimension sits 8 units above the\n"
                "  line, so it is not measuring the line at all. LINFINCHECK marks\n"
                "  BOTH spots - a RED X where you drew it, a GREEN + where it\n"
                "  belongs - and lets you Move it, Keep it exactly as drawn, or\n"
                "  Pick a spot yourself. Answer N to the 'is this correct?'\n"
                "  question and the whole dimension turns RED to fix later."))

      ;; --- fault 3: a step side view + its height dim -------------
      (setq made (cons (lfc:tut-line (list (+ ox 36.0) (+ oy 200.0) 0.0)
                                      (list (+ ox 36.0) (+ oy 190.0) 0.0) "0") made)
            made (cons (lfc:tut-line (list (+ ox 36.0) (+ oy 190.0) 0.0)
                                      (list (+ ox 24.0) (+ oy 190.0) 0.0) "0") made)
            made (cons (lfc:tut-line (list (+ ox 24.0) (+ oy 190.0) 0.0)
                                      (list (+ ox 24.0) (+ oy 180.0) 0.0) "0") made)
            made (cons (lfc:tut-line (list (+ ox 24.0) (+ oy 180.0) 0.0)
                                      (list (+ ox 12.0) (+ oy 180.0) 0.0) "0") made)
            made (cons (lfc:tut-line (list (+ ox 12.0) (+ oy 180.0) 0.0)
                                      (list (+ ox 12.0) (+ oy 170.0) 0.0) "0") made)
            made (cons (lfc:tut-line (list (+ ox 12.0) (+ oy 170.0) 0.0)
                                      (list ox (+ oy 170.0) 0.0) "0") made)
            made (cons (lfc:tut-line (list ox (+ oy 170.0) 0.0)
                                      (list ox (+ oy 160.0) 0.0) "0") made))
      (setq e (lfc:tut-dim (list ox (+ oy 160.0) 0.0)
                            (list (+ ox 36.0) (+ oy 200.0) 0.0)
                            (list (+ ox 60.0) (+ oy 180.0) 0.0) 1))
      (if e (setq made (cons e made)))
      (command "_.ZOOM" "_Window"
               (trans (list (- ox 20.0) (+ oy 145.0) 0.0) 0 1)
               (trans (list (+ ox 90.0) (+ oy 215.0) 0.0) 0 1))
      (lfc:tut-pause
        (strcat "FAULT 3 - a step side view.\n"
                "  Four risers and three treads: LINFINCHECK reads this as a side\n"
                "  view because the two families of parallel lines sit at right\n"
                "  angles and march along like a profile. A bench - only two\n"
                "  treads - counts too, while a plain rectangle does not.\n"
                "  The vertical dimension spanning the whole rise is the OVERALL\n"
                "  HEIGHT. It gets compared with the Tech Title's WallHt, and if\n"
                "  the two disagree that dimension is marked RED automatically."))

      ;; --- fault 4: an arc floating free --------------------------
      (entmake (list '(0 . "ARC") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbCircle")
                     (cons 10 (list (+ ox 220.0) (+ oy 40.0) 0.0))
                     (cons 40 30.0) '(100 . "AcDbArc")
                     (cons 50 0.0) (cons 51 pi)))
      (setq made (cons (entlast) made))
      (command "_.ZOOM" "_Window"
               (trans (list (+ ox 175.0) (- oy 10.0) 0.0) 0 1)
               (trans (list (+ ox 265.0) (+ oy 90.0) 0.0) 0 1))
      (lfc:tut-pause
        (strcat "FAULT 4 - an arc that attaches to nothing.\n"
                "  Both ends of this arc float free. LINFINCHECK wants every arc end\n"
                "  to land on the END of another object, so it offers to snap\n"
                "  each one - again with Move / Keep / Pick. An arc whose ends\n"
                "  actually moved turns MAGENTA so you can spot it afterwards."))

      ;; --- and now the report ------------------------------------
      (setq ss2 (ssadd))
      (foreach e made (if (entget e) (ssadd e ss2)))
      (command "_.ZOOM" "_Window"
               (trans (list (- ox 40.0) (- oy 40.0) 0.0) 0 1)
               (trans (list (+ ox 300.0) (+ oy 230.0) 0.0) 0 1))
      (princ (strcat "\n  " (itoa (sslength ss2))
                     " practice objects drawn. What LINFINCHECK would say about"
                     "\n  them is easiest to see as a report."))
      (if (cal:ask-yn "\n  Write a read-only LINFINSCAN report for the practice drawing?" "Yes")
        (progn
          (princ "\n  Running LINFINSCAN - it changes nothing, it only reports.")
          (princ "\n  (In the report, RED lines at full size are the problems;")
          (princ "\n   green lines at three-quarter size are the all-clears.)")
          (lfc:tut-pause
            (strcat "LINFINSCAN will ask you to highlight - window the practice\n"
                    "  drawing (or press Enter for the whole drawing). The report\n"
                    "  lands to the right of whatever you highlight."))
          (c:LINFINSCAN)))
      (if (cal:ask-yn "\n  Erase the practice drawing now?" "Yes")
        (progn
          (setq i 0)
          (repeat (sslength ss2)
            (if (entget (ssname ss2 i)) (entdel (ssname ss2 i)))
            (setq i (1+ i)))
          (setq ss2 (ssget "_X" (list (cons 8 *lfc-report-layer*))))
          (if ss2
            (progn
              (setq i 0)
              (repeat (sslength ss2) (entdel (ssname ss2 i)) (setq i (1+ i)))))
          (princ "\n  Practice drawing erased."))
        (princ "\n  Left in place - one U removes the whole tutorial."))
      (princ))))

(defun c:TUTORIALLINFINCHECK ( / *error* oldecho undo-open ans l ins h)
  (defun *error* (msg)
    (if undo-open (progn (setvar "CMDECHO" 0) (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTUTORIALLINFINCHECK error: " msg)))
    (princ))

  (princ (strcat "\n=================================================="
                 "\n  LINFINCHECK tutorial   [" *lfc-version* "]"
                 "\n=================================================="))
  ;; the tutorial selector of STANDARDS section 3; the old List stays
  ;; accepted typed in full, hidden
  (initget "Checks Demo Both LIST")
  (setq ans (getkword
              "\n  Read the Checks, Demo them on a practice drawing, or Both? [Checks/Demo/Both] <Both>: "))
  (if (null ans) (setq ans "Both"))
  (if (= ans "LIST") (setq ans "Checks"))
  (setq oldecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)

  (if (member ans '("Checks" "Both"))
    (progn
      (foreach l (lfc:tut-checklist) (princ (strcat "\n" l)))
      (princ "\n")
      (if (cal:ask-yn "\n  Drop that list into the drawing as a reference sheet?" "Yes")
        (progn
          (cal:ensure-layer *lfc-report-layer* *lfc-report-color*)
          (setq ins (getpoint "\n  Pick the top-left corner for the sheet: "))
          (if ins
            (progn
              (setq h   (getdist (strcat "\n  Text height <" (rtos 2.5) ">: "))
                    h   (if h h 2.5)
                    ins (trans ins 1 0))
              (lfc:mtext ins h (* 70.0 h)
                          (lfc:join (lfc:tut-checklist) "\\P")
                          *lfc-report-layer*)
              (princ "\n  Reference sheet placed (one U removes it)."))
            (princ "\n  No point picked - sheet skipped."))))))

  (if (member ans '("Demo" "Both"))
    (lfc:tut-demo))

  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (setvar "CMDECHO" oldecho)
  (princ (strcat "\n\n--- Tutorial finished ---"
                 "\n  LINFINSCAN first if you want to look without touching anything;"
                 "\n  LINFINCHECK to review and fix; LINFINCHECKRESCUE to undo the marks."
                 "\n  One U undoes everything this tutorial drew."))
  (princ))

(defun c:TUTORIALLINFINSCAN () (c:TUTORIALLINFINCHECK))

(princ (strcat "\nlinfincheck.lsp " *lfc-version*
               " loaded - LINFINCHECK reviews the whole title block one item at a"))
(princ "\n  time (dims, arcs, overlaps, steps, wall height, liner, border); LINFINSCAN reports")
(princ "\n  it read-only; LINFINCHECKRESCUE undoes LINFINCHECK's marks. For just dims, arcs")
(princ "\n  and overlaps, load dimcheck.lsp instead and run DIMCHECK.")
(princ)
