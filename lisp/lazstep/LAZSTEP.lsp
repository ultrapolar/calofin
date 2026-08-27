;;; ======================================================================
;;; LAZSTEP.lsp  --  say how many steps, then fill the drawing in
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZSTEP        pick a step type, say how many steps, fill
;;;                           the drawing in and run the step routine
;;;            LAZSTEPVER     print the loaded version
;;;
;;; TWO PAGES, AND THE SECOND ONE IS BUILT FROM THE FIRST.  Page one
;;; asks which of the three step routines this is -- CORNERSTP,
;;; HEMISTEP or NORMIESTEP -- HOW MANY STEPS, and the handful of
;;; questions that routine asks once for the whole run.  Page two is a
;;; DRAWING GENERATED FOR THAT COUNT: three steps draw three treads,
;;; eight draw eight, and every dimension the count implies is on it
;;; with a box against it.  Nothing here is a stored picture; the chart
;;; is built by lzt:chart from the type and the number.
;;;
;;; That is the whole point.  At the command line the step count is
;;; never a question -- the tread loop repeats until Enter -- so the
;;; number of steps is emergent and the operator finds out what the
;;; sheet needs by being asked for it, one prompt at a time.  A form
;;; has the number as a field, so the routines' stores give it a key of
;;; its own (steps . N): the loop stops itself after N steps instead of
;;; waiting for an Enter nobody typed, and a form of N rows drives a
;;; run of N steps.
;;;
;;; WHAT THE DRAWING SHOWS.  A plan view of the type picked, and under
;;; it the side profile every one of the three draws the same way --
;;; the flight in elevation, reading down and to the left, N risers and
;;; N treads with N+1 depth dimensions: depth1..depthN against each
;;; drop and depthafter against the drop after the last tread.  The
;;; depth chain is the part that is hardest to hold in your head at the
;;; command line, and it is exactly what the routines ask for.
;;;
;;; ZERO INSTALL, like LAZFORM and LAZPANEL: the dialog is plain DCL
;;; written to the temp folder at run time and the chart is drawn with
;;; vector_image, so there is no artwork file to ship and nothing to
;;; NETLOAD.  Unlike LAZFORM the file is rewritten each time a page is
;;; opened, because page two's DCL depends on the count -- N rows of
;;; boxes cannot be a static dialog.
;;;
;;; DCL HEIGHT IS A HARD FAILURE MODE.  A dialog taller than the screen
;;; does not open, and nothing here can measure a screen: N rows of
;;; boxes grow the page linearly, so the count is capped (lzt:*max-
;;; steps*, 8) and the depth boxes are packed two to a row.  A larger
;;; number is refused on page one with a message rather than opening a
;;; page that might not fit.
;;;
;;; WHY THE BOXES SIT WHERE THEY DO.  DCL packs tiles into rows and
;;; columns -- no absolute positioning, no overlapping, no z-order --
;;; so an edit box cannot sit on an image tile.  The chart is therefore
;;; CUT INTO BANDS at the heights where its horizontal dimension rows
;;; run, and those rows are real edit boxes wedged between the bands,
;;; pushed to their letters' positions by spacers.  The tread chain is
;;; horizontal, so it becomes those rows; the widths and the depths run
;;; the other way and a box cannot stand sideways, so they keep boxes
;;; in the side column with their values drawn onto the chart in the
;;; letter's place.
;;;
;;; The chart is a PASSIVE image tile and must stay one.  A DCL image
;;; tile is not retained by AutoCAD: any repaint clears it to its own
;;; colour attribute and there is no expose callback to redraw from.
;;; An image_button repaints on mouse-enter and mouse-leave, so the
;;; drawing would vanish the first time the cursor crossed it.
;;;
;;; THE THREE STATES, which are LAZFORM's and STANDARDS.md's:
;;;
;;;    box left empty   the key is not sent  -> the routine asks
;;;    NA typed in it   (key . nil) is sent  -> what Enter means there
;;;    a measurement    (key . 84.0) is sent -> taken, no prompt
;;;
;;; For a step width NA means "fit to the walls" or "fit to the curve";
;;; for wallwidth and crown it means "none"; for a depth it means "the
;;; same as the one above".  A TREAD IS THE EXCEPTION: nil at a tread
;;; prompt is what ends the run, so NA there would stop the flight short
;;; of the count that built the drawing -- it counts as an empty box
;;; instead.  Anything that is neither NA nor a distance AutoCAD can
;;; read counts as empty too: a typo must leave the routine asking
;;; rather than quietly feeding it a nil that means something else.
;;;
;;; WHAT NEVER COMES OFF THE FORM.  The selections and the point picks:
;;; the two walls, the curve or base line, the side to draw toward, the
;;; profile's top-of-tread pick and the bead direction.  Those live in
;;; the drawing where the operator's own snaps are live, and the three
;;; routines ask for them there as always.
;;; ======================================================================

(vl-load-com)

(setq *lazstep-version* "v1.0")

;;; -------------------- the three routines -------------------------------
;;;  Name, what the tab calls it, and the entry point its store feeds.
;;;  The routines load together as one bundle, so in practice it is all
;;;  three or none -- but the gate is per type anyway, because that is
;;;  the one the operator picked.

(setq lzt:*types*
  '(("CORNERSTP"  "Corner steps"   "cs-run-with-answers")
    ("HEMISTEP"   "Hemi steps"     "hs-run-with-answers")
    ("NORMIESTEP" "Straight steps" "ns-run-with-answers")))

(defun lzt:title (ty / p)
  (if (setq p (assoc ty lzt:*types*)) (cadr p) ty))

;; Is that routine in this session?  An unbound symbol reads as nil, so
;; this is the same test LAZFORM makes of POOL.
(defun lzt:loaded (ty)
  (cond ((= ty "CORNERSTP")  (if cs-run-with-answers T))
        ((= ty "HEMISTEP")   (if hs-run-with-answers T))
        ((= ty "NORMIESTEP") (if ns-run-with-answers T))))

(defun lzt:first-loaded ( / out d)
  (foreach d lzt:*types*
    (if (and (not out) (lzt:loaded (car d))) (setq out (car d))))
  out)

;; Hand the chosen routine what the form collected.
(defun lzt:run (ty form)
  (cond
    ((= ty "CORNERSTP")  (cs-run-with-answers form))
    ((= ty "HEMISTEP")   (hs-run-with-answers form))
    ((= ty "NORMIESTEP") (ns-run-with-answers form))))

;;; -------------------- the stroke font ---------------------------------
;;;  DCL has no way to draw text into an image tile -- vector_image draws
;;;  line segments and that is the whole of it -- so the letters and the
;;;  numbers on the chart are stroked out of segments here.
;;;
;;;  One entry per character: the glyph as a list of polylines, each a
;;;  flat list of x y x y ... in TENTHS of a font unit, on a cell 4 wide
;;;  and 6 tall with y running DOWN the way image-tile pixels do.
;;;  Integers, so nothing here depends on float formatting.

(setq lzt:*font* '(
    ("A" (0 60 20 0 40 60) (8 40 32 40))
    ("B" (0 0 0 60) (0 0 30 0 40 10 40 20 30 30 0 30) (30 30 40 40 40 50 30 60 0 60))
    ("C" (40 10 30 0 10 0 0 10 0 50 10 60 30 60 40 50))
    ("D" (0 0 0 60) (0 0 30 0 40 10 40 50 30 60 0 60))
    ("E" (40 0 0 0 0 60 40 60) (0 30 30 30))
    ("F" (40 0 0 0 0 60) (0 30 30 30))
    ("G" (40 10 30 0 10 0 0 10 0 50 10 60 30 60 40 50 40 30 20 30))
    ("H" (0 0 0 60) (40 0 40 60) (0 30 40 30))
    ("I" (10 0 30 0) (20 0 20 60) (10 60 30 60))
    ("J" (30 0 30 50 20 60 10 60 0 50))
    ("K" (0 0 0 60) (40 0 0 35) (14 25 40 60))
    ("L" (0 0 0 60 40 60))
    ("M" (0 60 0 0 20 30 40 0 40 60))
    ("N" (0 60 0 0 40 60 40 0))
    ("O" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0))
    ("P" (0 60 0 0 30 0 40 10 40 20 30 30 0 30))
    ("Q" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0) (25 45 40 60))
    ("R" (0 60 0 0 30 0 40 10 40 20 30 30 0 30) (20 30 40 60))
    ("S" (40 10 30 0 10 0 0 10 0 20 10 30 30 30 40 40 40 50 30 60 10 60 0 50))
    ("T" (0 0 40 0) (20 0 20 60))
    ("U" (0 0 0 50 10 60 30 60 40 50 40 0))
    ("V" (0 0 20 60 40 0))
    ("W" (0 0 10 60 20 20 30 60 40 0))
    ("X" (0 0 40 60) (40 0 0 60))
    ("Y" (0 0 20 30 40 0) (20 30 20 60))
    ("Z" (0 0 40 0 0 60 40 60))
    ("0" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0) (5 55 35 5))
    ("1" (10 10 20 0 20 60) (10 60 30 60))
    ("2" (0 10 10 0 30 0 40 10 40 20 0 60 40 60))
    ("3" (0 0 40 0 20 25) (20 25 40 35 40 50 30 60 10 60 0 50))
    ("4" (30 60 30 0 0 40 40 40))
    ("5" (40 0 0 0 0 25 30 25 40 35 40 50 30 60 10 60 0 50))
    ("6" (40 0 20 0 0 20 0 50 10 60 30 60 40 50 40 40 30 30 10 30 0 40))
    ("7" (0 0 40 0 15 60))
    ("8" (10 30 0 20 0 10 10 0 30 0 40 10 40 20 30 30 10 30 0 40 0 50 10 60 30 60 40 50 40 40 30 30))
    ("9" (0 60 20 60 40 40 40 10 30 0 10 0 0 10 0 20 10 30 30 30 40 20))
    ("." (17 54 23 54 23 60 17 60 17 54))
    ("-" (5 30 35 30))
    ("'" (20 0 20 16))
    ("\"" (13 0 13 16) (27 0 27 16))
    ("/" (0 60 40 0))
    (":" (20 16 20 22) (20 40 20 46))
    ("%" (0 60 40 0) (5 5 12 5) (28 55 35 55))
    ("#" (10 0 6 60) (30 0 26 60) (0 20 40 20) (0 40 40 40))
    (" ")
))

(setq lzt:*font-w* 40)          ; glyph cell width, tenths
(setq lzt:*font-h* 60)          ; glyph cell height, tenths
(setq lzt:*font-adv* 56)        ; pen advance per character, tenths

;;; -------------------- the frame the chart is drawn in ------------------
;;;  Everything is in PER-MILLE of the picture, x and y, y down -- the
;;;  same convention as an image tile, so the only conversion at draw
;;;  time is a multiply.  Integers, so nothing depends on float
;;;  formatting and two runs of the generator agree to the unit.
;;;
;;;  The picture is one tall frame with the PLAN in the top third, the
;;;  tread dimension row(s) under it, and the SIDE PROFILE below that.
;;;  One coordinate space, one drawing engine, one set of bands.

(setq lzt:*plan-x0*   100)      ; the wall, or the corner
(setq lzt:*plan-x1*   860)      ; the far end of the run
(setq lzt:*plan-yc*   180)      ; the run's centre line
(setq lzt:*plan-hh*   120)      ; half the plan's opening at the far end
(setq lzt:*width-x*   930)      ; where a whole-run width dim stands
(setq lzt:*chord-x1*  860)      ; the last chord across a hemi curve
(setq lzt:*curve-rx*  840)      ; ...whose crown sits beyond it, at x0 + this
(setq lzt:*tread-y0*  385)      ; the tread dimension row
(setq lzt:*tread-y1*  445)      ; ...and the second one, when N needs it
(setq lzt:*one-row*     4)      ; treads that fit one row of boxes
(setq lzt:*prof-x*    860)      ; top of the flight
(setq lzt:*prof-y*    540)
(setq lzt:*prof-w*    760)      ; the flight's whole run...
(setq lzt:*prof-h*    450)      ; ...and its whole drop
(setq lzt:*prof-gap*   40)      ; how far a depth dim stands off its step

;;  THE CEILING.  DCL will not scroll and a dialog taller than the
;;  screen does not open at all, so the count has to stop somewhere.
;;  Eight steps is one row of eight width boxes plus five rows of
;;  paired depth boxes beside a twenty-cell chart, which fits a laptop
;;  screen; nine does not reliably, and nothing here can ask the screen
;;  how tall it is.
(setq lzt:*max-steps* 8)

;;; -------------------- generating the chart -----------------------------
;;;  A chart is (type title (outline ...) (dimension ...) (cut ...)).
;;;
;;;  A dimension is (letter key x1 y1 x2 y2 side label), where side is
;;;  "h" or "v" -- which way the measurement runs, and so where its text
;;;  sits.  The arrow, the letter and the typed value all come off those
;;;  two endpoints, so there is no separate position table that could
;;;  fall out of step with the drawing.
;;;
;;;  A cut is a per-mille y that lands EXACTLY on a horizontal
;;;  dimension's line; every "h" dimension at that y becomes a wedge box
;;;  and loses its drawn arrow, because the row of boxes IS that row of
;;;  the drawing now.

;; The i'th step boundary along a run of N, per-mille x.
(defun lzt:runx (i n x1)
  (+ lzt:*plan-x0* (/ (* (- x1 lzt:*plan-x0*) i) n)))

;; Half the corner fan's opening at per-mille x: nothing at the corner,
;; the full half-height at the far end.
(defun lzt:fanh (x)
  (/ (* lzt:*plan-hh* (- x lzt:*plan-x0*))
     (- lzt:*plan-x1* lzt:*plan-x0*)))

;; Half the hemi curve's opening at per-mille x -- the ellipse the
;; chords are drawn across, so a chord always lands ON the curve.
(defun lzt:curveh (x / u)
  (setq u (/ (- x lzt:*plan-x0*) (float lzt:*curve-rx*)))
  (if (>= u 1.0) 0 (fix (* lzt:*plan-hh* (sqrt (- 1.0 (* u u)))))))

;; Which dimension row step I's tread is drawn on.  One row while the
;; boxes fit across the chart; past that they STAGGER onto two, the way
;; a tight dimension chain is drawn on paper -- eight boxes on one line
;; run about 96 character cells against a chart of 58, and a row that
;; wide drags the whole dialog past the screen.
(defun lzt:tready (i n)
  (if (or (<= n lzt:*one-row*) (= 1 (rem i 2)))
      lzt:*tread-y0*
      lzt:*tread-y1*))

(defun lzt:cutlist (n)
  (if (> n lzt:*one-row*)
      (list lzt:*tread-y0* lzt:*tread-y1*)
      (list lzt:*tread-y0*)))

;; The tread chain: one horizontal dimension per step, end to end.
(defun lzt:treaddims (n x1 / i out y)
  (setq i 1)
  (while (<= i n)
    (setq y (lzt:tready i n)
          out (cons (list (strcat "T" (itoa i))
                          (strcat "tread" (itoa i))
                          (lzt:runx (1- i) n x1) y
                          (lzt:runx i n x1) y
                          "h"
                          (strcat "Step " (itoa i) " tread"))
                    out)
          i (1+ i)))
  (reverse out))

;; The x of the corner at the foot of drop I, per-mille.  The flight
;; reads DOWN AND TO THE LEFT, so each drop stands one tread further
;; left than the one above it -- which is how all three routines draw
;; the profile, and why the depth dims fan out rather than stacking.
(defun lzt:profx (i n)
  (- lzt:*prof-x* (/ (* lzt:*prof-w* (max 0 (1- i))) n)))

;; ...and the y of the level J drops down to.
(defun lzt:profy (j n)
  (+ lzt:*prof-y* (/ (* lzt:*prof-h* j) (1+ n))))

;; The silhouette: N+1 drops with a tread off the foot of each but the
;; last, exactly as the routines draw it.
(defun lzt:profile (n / i out x1 x2 y0 y1)
  (setq i 1)
  (while (<= i (1+ n))
    (setq x1 (lzt:profx i n)
          y0 (lzt:profy (1- i) n)
          y1 (lzt:profy i n)
          out (cons (list x1 y0 x1 y1) out))
    (if (<= i n)
      (setq x2  (lzt:profx (1+ i) n)
            out (cons (list x1 y1 x2 y1) out)))
    (setq i (1+ i)))
  (reverse out))

;; N+1 depth dimensions: depth1..depthN against each drop, depthafter
;; against the drop after the last tread.  Each stands a fixed gap off
;; its own step, so they climb with the flight.
(defun lzt:depthdims (n / i out x ya yb ltr key lbl)
  (setq i 1)
  (while (<= i (1+ n))
    (setq x   (+ (lzt:profx i n) lzt:*prof-gap*)
          ya  (lzt:profy (1- i) n)
          yb  (lzt:profy i n)
          ltr (if (> i n) "DA" (strcat "D" (itoa i)))
          key (if (> i n) "depthafter" (strcat "depth" (itoa i)))
          lbl (if (> i n) "after the last tread"
                          (strcat "Step " (itoa i) " drop"))
          out (cons (list ltr key x ya x yb "v" lbl) out)
          i   (1+ i)))
  (reverse out))

;; ---- CORNERSTP: two walls meeting at a corner, treads fanning out ----
;;  The bisector runs to the right, so the tread chain measured along it
;;  is horizontal and becomes a row of real boxes.  Each step's width is
;;  the length of its own tread line, dimensioned on the line itself.
(defun lzt:chart-corner (n / out i x h dims)
  (setq out (list (list lzt:*plan-x0* lzt:*plan-yc*
                        lzt:*plan-x1* (- lzt:*plan-yc* lzt:*plan-hh*))
                  (list lzt:*plan-x0* lzt:*plan-yc*
                        lzt:*plan-x1* (+ lzt:*plan-yc* lzt:*plan-hh*)))
        i 1)
  (while (<= i n)
    (setq x    (lzt:runx i n lzt:*plan-x1*)
          h    (lzt:fanh x)
          out  (append out (list (list x (- lzt:*plan-yc* h)
                                       x (+ lzt:*plan-yc* h))))
          dims (cons (list (strcat "W" (itoa i))
                           (strcat "width" (itoa i))
                           x (- lzt:*plan-yc* h) x (+ lzt:*plan-yc* h) "v"
                           (strcat "Step " (itoa i) " width"))
                     dims)
          i    (1+ i)))
  (list "CORNERSTP" "Corner steps"
        (append out (lzt:profile n))
        (append (lzt:treaddims n lzt:*plan-x1*)
                (reverse dims)
                (lzt:depthdims n))
        (lzt:cutlist n)))

;; ---- HEMISTEP: a curve with N chords across it ----------------------
;;  The wall is the left edge, the curve bulges away from it, and tread
;;  I is measured between chord I-1 and chord I along the axis.
(defun lzt:chart-hemi (n / out i x h dims)
  (setq out (list (list lzt:*plan-x0* (- lzt:*plan-yc* lzt:*plan-hh*)
                        lzt:*plan-x0* (+ lzt:*plan-yc* lzt:*plan-hh*))
                  (list "A" lzt:*plan-x0* lzt:*plan-yc*
                        lzt:*curve-rx* lzt:*plan-hh* 90 -90))
        i 1)
  (while (<= i n)
    (setq x    (lzt:runx i n lzt:*chord-x1*)
          h    (lzt:curveh x)
          out  (append out (list (list x (- lzt:*plan-yc* h)
                                       x (+ lzt:*plan-yc* h))))
          dims (cons (list (strcat "W" (itoa i))
                           (strcat "width" (itoa i))
                           x (- lzt:*plan-yc* h) x (+ lzt:*plan-yc* h) "v"
                           (strcat "Step " (itoa i) " width"))
                     dims)
          i    (1+ i)))
  (list "HEMISTEP" "Hemi steps"
        (append out (lzt:profile n))
        (append (lzt:treaddims n lzt:*chord-x1*)
                (reverse dims)
                (lzt:depthdims n))
        (lzt:cutlist n)))

;; ---- NORMIESTEP: a straight run, ONE width for the whole of it ------
(defun lzt:chart-normie (n / out i x ytop ybot)
  (setq ytop (- lzt:*plan-yc* lzt:*plan-hh*)
        ybot (+ lzt:*plan-yc* lzt:*plan-hh*)
        out  (list (list lzt:*plan-x0* ytop lzt:*plan-x1* ytop)
                   (list lzt:*plan-x0* ybot lzt:*plan-x1* ybot))
        i    0)
  (while (<= i n)
    (setq x   (lzt:runx i n lzt:*plan-x1*)
          out (append out (list (list x ytop x ybot)))
          i   (1+ i)))
  (list "NORMIESTEP" "Straight steps"
        (append out (lzt:profile n))
        (append (lzt:treaddims n lzt:*plan-x1*)
                (list (list "W" "width" lzt:*width-x* ytop
                            lzt:*width-x* ybot "v"
                            "One width, the whole run"))
                (lzt:depthdims n))
        (lzt:cutlist n)))

;; The chart for a type and a count.  This is the whole of the "drawing
;; generated from the count" -- everything downstream reads it as data.
(defun lzt:chart (ty n)
  (cond
    ((= ty "CORNERSTP")  (lzt:chart-corner n))
    ((= ty "HEMISTEP")   (lzt:chart-hemi n))
    ((= ty "NORMIESTEP") (lzt:chart-normie n))))

;;; -------------------- chart access ------------------------------------

(defun lzt:c-type (c) (nth 0 c))
(defun lzt:c-title (c) (nth 1 c))
(defun lzt:c-outline (c) (nth 2 c))
(defun lzt:c-dims (c) (nth 3 c))
(defun lzt:c-cuts (c) (nth 4 c))

;; Is this key a tread?  A depth?  Both are asked in loops, so they are
;; recognised by their stem rather than listed twice.
(defun lzt:treadkey (k) (= (substr k 1 5) "tread"))
(defun lzt:depthkey (k) (= (substr k 1 5) "depth"))

;; The horizontal dims whose line IS this cut.
(defun lzt:cutdims (c y / d out)
  (foreach d (lzt:c-dims c)
    (if (and (= (nth 6 d) "h") (= (nth 3 d) y) (= (nth 5 d) y))
        (setq out (cons d out))))
  (reverse out))

;; Keys of every dim that lives in a wedge row rather than the column.
(defun lzt:wedge-keys (c / y d out)
  (foreach y (lzt:c-cuts c)
    (foreach d (lzt:cutdims c y)
      (setq out (cons (cadr d) out))))
  (reverse out))

;; The bands between the cuts: ((y0 . y1) ...).
(defun lzt:bands (c / ys prev out y)
  (setq ys   (append (list 0) (lzt:c-cuts c) (list 1000))
        prev (car ys))
  (foreach y (cdr ys)
    (setq out  (cons (cons prev y) out)
          prev y))
  (reverse out))

;; Every key the chart can answer, in drawing order.
(defun lzt:keys (c / d out)
  (foreach d (lzt:c-dims c) (setq out (cons (cadr d) out)))
  (reverse out))

;;; -------------------- page one's questions ----------------------------
;;;  The once-only answers, per type: what a routine asks before the
;;;  step loop starts, and what it asks after it ends.  A row is
;;;  (key kind label (choices ...)); kind is LIST (a dropdown), DIST (a
;;;  distance box) or INT (a whole number).
;;;
;;;  A dropdown's first entry is "(ask)" -- the form's version of an
;;;  empty box, and the only honest default, since the routines offer a
;;;  keyboard default of their own at every one of these prompts.
;;;
;;;  MEASURE AND TREADMODE ARE OFFERED ON EVERY CORNER RUN, and are not
;;;  greyed.  CORNERSTP asks them only when the selection turned up a
;;;  corner diagonal or fillet, which is a fact about the drawing and
;;;  not about the form -- so they are offered, an answer the live
;;;  prompt does not list falls through to the prompt anyway, and the
;;;  hint says they are ignored on a plain corner.

(setq lzt:*ask-common*
  '(("dims"    "LIST" "Dimension the steps"   ("(ask)" "Yes" "No"))
    ("profile" "LIST" "Add a side profile"    ("(ask)" "Yes" "No"))
    ("bead"    "LIST" "Bead the steps"        ("(ask)" "Yes" "No"))))

(setq lzt:*asks*
  '(("CORNERSTP"
     ("direction"   "LIST" "Draw steps"
      ("(ask)" "Inside" "Outside"))
     ("measure"     "LIST" "Measure treads from"
      ("(ask)" "Middle" "True"))
     ("treadmode"   "LIST" "Steps run"
      ("(ask)" "Parallel" "True" "Equidistant"))
     ("outerwidth"  "DIST" "Outermost step width" ())
     ("bench"       "LIST" "Bench along a wall"
      ("(ask)" "Yes" "No"))
     ("benchoffset" "DIST" "Bench offset off the wall" ())
     ("benchstep"   "INT"  "Bench ends on step number" ()))
    ("HEMISTEP"
     ("wallwidth"   "DIST" "Width at the wall (NA = none)" ())
     ("crown"       "DIST" "Last step to the crown (NA = none)" ())
     ("boundary"    "LIST" "Draw the boundary"
      ("(ask)" "Yes" "No")))
    ("NORMIESTEP"
     ("width"       "DIST" "Step width, the whole run" ())
     ("treat"       "LIST" "Corner treatment"
      ("(ask)" "Square" "Radius" "Cut" "NotGiven"))
     ("treat-sz"    "DIST" "Treatment size" ())
     ("cutgiven"    "LIST" "The cut is given as"
      ("(ask)" "Offset" "Cut")))))

(defun lzt:asks-of (ty)
  (append (cdr (assoc ty lzt:*asks*)) lzt:*ask-common*))

(defun lzt:asks ( ) (lzt:asks-of lzt:*type*))

;;; -------------------- the answers -------------------------------------
;;;  What is typed is kept as the STRING the user typed, so the chart can
;;;  show it back exactly as entered -- 2'6" stays 2'6" -- and it is only
;;;  turned into a number when the routine is handed the form.

(setq lzt:*vals* nil)           ; ((key . "typed") ...)
(setq lzt:*sel* nil)            ; ((stem . index) ...) for the dropdowns
(setq lzt:*type* "CORNERSTP")   ; which routine is being filled in
(setq lzt:*steps* nil)          ; the count, once it has been accepted
(setq lzt:*chart* nil)          ; the chart generated for that count
(setq lzt:*focus* nil)          ; the key whose box has the caret
(setq lzt:*pos* nil)            ; where the dialog was last standing
(setq lzt:*page* 1)             ; which page is open
(setq lzt:*go* nil)             ; the type a tab click asked for
(setq lzt:*msg* "")             ; what page one has to say about the count

(defun lzt:get (key / p)
  (if (setq p (assoc key lzt:*vals*)) (cdr p) ""))

(defun lzt:put (key v / out p)
  (foreach p lzt:*vals* (if (/= (car p) key) (setq out (cons p out))))
  (setq lzt:*vals* (reverse (cons (cons key v) out))))

(defun lzt:sel (stem / p)
  (if (setq p (assoc stem lzt:*sel*)) (cdr p) 0))

(defun lzt:sput (stem i / out p)
  (foreach p lzt:*sel* (if (/= (car p) stem) (setq out (cons p out))))
  (setq lzt:*sel* (reverse (cons (cons stem i) out))))

;; The word a dropdown is standing on, or nil when it is still on
;; "(ask)" -- which sends nothing at all.
(defun lzt:selword (stem / d i)
  (if (setq d (assoc stem (lzt:asks)))
    (if (> (setq i (lzt:sel stem)) 0) (nth i (nth 3 d)))))

(defun lzt:trim (s / i n)
  (setq i 1 n (strlen s))
  (while (and (<= i n) (= (substr s i 1) " ")) (setq i (1+ i)))
  (while (and (>= n i) (= (substr s n 1) " ")) (setq n (1- n)))
  (if (> i n) "" (substr s i (1+ (- n i)))))

;;  The three states, decided here.  Anything that is neither NA nor a
;;  distance AutoCAD can read is treated as an empty box: a typo must
;;  leave the routine asking rather than quietly feeding it a nil that
;;  means something else entirely.  distof reads the architectural
;;  spellings, so 2'6" and 2'-6-1/2" arrive as the numbers they look
;;  like.
(defun lzt:answer (v / n)
  (cond
    ((or (null v) (= v "")) 'SKIP)
    ((= (strcase (lzt:trim v)) "NA") nil)
    ((setq n (distof (lzt:trim v) 4)) n)
    ((setq n (distof (lzt:trim v) 2)) n)
    (t 'SKIP)))

;; A box that has to hold a whole number.  The step count and the bench
;; step both refuse anything else, so a typo has to read as "not
;; answered" rather than as a zero.
(defun lzt:int (s / i c ok n)
  (setq s  (lzt:trim s)
        ok (> (strlen s) 0)
        i  1)
  (while (and ok (<= i (strlen s)))
    (setq c (substr s i 1))
    (if (or (< (ascii c) 48) (> (ascii c) 57)) (setq ok nil))
    (setq i (1+ i)))
  (if ok (setq n (atoi s)))
  (if (and n (> n 0)) n))

;;; -------------------- what does not apply ------------------------------
;;;  A question a run will never reach is greyed, and a greyed answer
;;;  does not travel: a number sitting in the store unread is harder to
;;;  reason about than one that was never sent.
;;;
;;;    outerwidth   only outside in places the outermost step by width
;;;    bench        a bench is an inside-out feature; outside in walks
;;;                 toward the corner without knowing its step count
;;;    benchoffset  }  no bench, no offset and no attachment step
;;;    benchstep    }
;;;    measure      the measuring choice is an inside-out question
;;;    treat-sz     only Radius and Cut take a size
;;;    cutgiven     only a Cut can be given as an offset or a face
;;;    depth1..DA   a run with no side profile asks for no depths

(defun lzt:skip ( / out d tr dd)
  (setq d  (lzt:selword "direction")
        tr (lzt:selword "treat"))
  (if (= lzt:*type* "CORNERSTP")
    (if (= d "Outside")
      (setq out (append (list "measure" "bench" "benchoffset" "benchstep")
                        out))
      (setq out (cons "outerwidth"
                      (if (= (lzt:selword "bench") "Yes")
                          out
                          (append (list "benchoffset" "benchstep") out))))))
  (if (= lzt:*type* "NORMIESTEP")
    (progn
      (if (not (member tr '("Radius" "Cut")))
        (setq out (cons "treat-sz" out)))
      (if (not (= tr "Cut")) (setq out (cons "cutgiven" out)))))
  (if (and lzt:*chart* (= (lzt:selword "profile") "No"))
    (foreach dd (lzt:c-dims lzt:*chart*)
      (if (lzt:depthkey (cadr dd)) (setq out (cons (cadr dd) out)))))
  out)

;; Grey what page one carries and this run will not ask about.  Only
;; keys ON this page are touched -- mode_tile on a key the dialog does
;; not have would error.
(defun lzt:p1grey ( / noask d)
  (setq noask (lzt:skip))
  (foreach d (lzt:asks)
    (mode_tile (car d) (if (member (car d) noask) 1 0))))

(defun lzt:p2grey ( / noask d)
  (setq noask (lzt:skip))
  (foreach d (lzt:keys lzt:*chart*)
    (mode_tile d (if (member d noask) 1 0))))

;; A dropdown changed: remember it, and re-grey what that answer opens
;; or closes.
(defun lzt:p1pick (stem v)
  (lzt:sput stem (atoi v))
  (lzt:p1grey)
  (princ))

;;; -------------------- what the routine is handed -----------------------

;;  THE COUNT GOES FIRST AND IS AN INTEGER.  It is the one answer the
;;  prompts never ask for: with it in hand the tread loop stops itself
;;  after that many steps instead of waiting for an Enter nobody typed,
;;  which is what lets a form of N rows drive a run of N steps.
(defun lzt:form ( / out noask k v a ck)
  (setq noask (lzt:skip)
        out   (list (cons 'steps lzt:*steps*)))
  (foreach k (lzt:asks)
    (if (not (member (car k) noask))
      (cond
        ((= (cadr k) "LIST")
         (if (setq v (lzt:selword (car k)))
           (setq out (cons (cons (read (car k)) v) out))))
        ((= (cadr k) "INT")
         (if (setq v (lzt:int (lzt:get (car k))))
           (setq out (cons (cons (read (car k)) v) out))))
        (t
         (setq a (lzt:answer (lzt:get (car k))))
         (if (not (eq a 'SKIP))
           (setq out (cons (cons (read (car k)) a) out)))))))
  (foreach k (lzt:c-dims lzt:*chart*)
    (setq ck (cadr k))
    (if (and (not (member ck noask)) (not (assoc (read ck) out)))
      (progn
        (setq a (lzt:answer (lzt:get ck)))
        ;; NA at a tread is what ENDS the run, so it would stop the
        ;; flight short of the count that built this drawing -- it
        ;; counts as an empty box instead
        (if (and (null a) (lzt:treadkey ck)) (setq a 'SKIP))
        (if (not (eq a 'SKIP))
          (setq out (cons (cons (read ck) a) out))))))
  (reverse out))

;;; -------------------- drawing the chart -------------------------------
;;;  Pixel coordinates, origin top-left, y down -- image-tile convention,
;;;  which is why the per-mille data is generated that way too and needs
;;;  no flipping here.  dimx_tile / dimy_tile report the LARGEST legal
;;;  coordinate, not the size, and are only answerable while the dialog
;;;  is up, so everything below runs between new_dialog and start_dialog.

(setq lzt:*dx* 0)               ; the tile's extent this time round
(setq lzt:*dy* 0)
(setq lzt:*y0* 0)               ; the band being drawn, in per-mille
(setq lzt:*y1* 1000)

(setq lzt:*col-line* -16)       ; dialog foreground: the outline
(setq lzt:*col-back* -15)       ; dialog background: the clear
(setq lzt:*col-dim* 8)          ; grey: the dimension arrows
(setq lzt:*col-val* 30)         ; orange: a value that has been typed
(setq lzt:*col-hi* 5)           ; blue: the box round the active one

(defun lzt:px (v) (fix (/ (* v lzt:*dx*) 1000.0)))
(defun lzt:py (v)
  (fix (/ (* (- v lzt:*y0*) lzt:*dy*) (float (- lzt:*y1* lzt:*y0*)))))

(defun lzt:iny (v) (and (<= lzt:*y0* v) (<= v lzt:*y1*)))

;; The segment, clipped to the band, or nil when none of it is inside.
;; Everything the bands draw goes through this, so a cut is one rule
;; applied everywhere rather than per-shape case work.
(defun lzt:clipseg (x1 y1 x2 y2 / ta tb lo hi)
  (cond
    ((= y1 y2)
     (if (lzt:iny y1) (list x1 y1 x2 y2)))
    (t
     (setq ta (/ (- lzt:*y0* y1) (float (- y2 y1)))
           tb (/ (- lzt:*y1* y1) (float (- y2 y1)))
           lo (max 0.0 (min ta tb))
           hi (min 1.0 (max ta tb)))
     (if (< lo hi)
         (list (+ x1 (* (- x2 x1) lo)) (+ y1 (* (- y2 y1) lo))
               (+ x1 (* (- x2 x1) hi)) (+ y1 (* (- y2 y1) hi)))))))

;;  An outline element is either a POLYLINE -- a flat list of per-mille
;;  numbers, x y x y ... -- or an ARC, written
;;
;;      ("A" cx cy rx ry from to)
;;
;;  with the centre and both radii in per-mille and the angles in
;;  degrees, 0 due east and counting anticlockwise ON SCREEN.  Since
;;  image-tile y runs DOWN, that is a minus on the y term and nowhere
;;  else.  Two radii rather than one because the hemi curve wants half
;;  of an ellipse more often than half of a circle.
(defun lzt:arcpts (a / cx cy rx ry f to n i ang out)
  (setq cx (nth 1 a) cy (nth 2 a) rx (nth 3 a) ry (nth 4 a)
        f (nth 5 a) to (nth 6 a))
  (setq n (fix (/ (abs (- to f)) 6.0)))
  (if (< n 4) (setq n 4))
  (setq i 0)
  (while (<= i n)
    ;; NB: the angle local is not called t -- a local of that name would
    ;; shadow TRUE for the length of the call
    (setq ang (/ (* pi (+ f (/ (* (- to f) i) (float n)))) 180.0)
          out (cons (fix (- cy (* ry (sin ang))))
                    (cons (fix (+ cx (* rx (cos ang)))) out))
          i (1+ i)))
  (reverse out))

;; An outline element as a flat per-mille polyline, whichever it was.
(defun lzt:flatten (e)
  (if (= (type (car e)) 'STR) (lzt:arcpts e) e))

;; A polyline given as a flat per-mille list, clipped to the band.
(defun lzt:pline (flat col / s)
  (while (and flat (cddr flat))
    (if (setq s (lzt:clipseg (car flat) (cadr flat)
                             (caddr flat) (cadddr flat)))
        (vector_image (lzt:px (car s)) (lzt:py (cadr s))
                      (lzt:px (caddr s)) (lzt:py (cadddr s)) col))
    (setq flat (cddr flat))))

;; A polyline already in pixels, given as (x y x y ...).
(defun lzt:plinepx (flat col)
  (while (and flat (cddr flat))
    (vector_image (car flat) (cadr flat) (caddr flat) (cadddr flat) col)
    (setq flat (cddr flat))))

(defun lzt:glyph (ch / p)
  (if (setq p (assoc (strcase ch) lzt:*font*)) (cdr p)))

;; The width one string will occupy, in pixels, at SC tenths per unit.
(defun lzt:textw (s sc)
  (if (= s "") 0
      (fix (/ (* (- (* (strlen s) lzt:*font-adv*)
                    (- lzt:*font-adv* lzt:*font-w*))
                 sc)
              100.0))))

(defun lzt:texth (sc) (fix (/ (* lzt:*font-h* sc) 100.0)))

;; The size to letter the chart at.  Derived from the tile rather than
;; fixed: an image tile's pixel size falls out of the user's dialog font
;; and display DPI, and is not knowable until the dialog is up.
(defun lzt:basesc ( / sc)
  (setq sc (/ (* lzt:*dy* 100) 1560))
  (if (< sc 12) 12 sc))

;; Stroke S with its top-left corner at pixel X Y.  SC is a percentage
;; of the font's own tenth-units, so the caller can size text to fit.
(defun lzt:text (s x y sc col / i ch pen poly out n)
  (setq i 1 pen x)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (foreach poly (lzt:glyph ch)
      (setq out nil n poly)
      (while n
        (setq out (cons (+ y (fix (/ (* (cadr n) sc) 100.0)))
                        (cons (+ pen (fix (/ (* (car n) sc) 100.0))) out))
              n (cddr n)))
      (lzt:plinepx (reverse out) col))
    (setq pen (+ pen (fix (/ (* lzt:*font-adv* sc) 100.0)))
          i (1+ i)))
  pen)

;; The dimension line with an arrowhead at each end, in per-mille,
;; clipped to the band.  A head is drawn only when its own end is
;; inside the band -- the shaft of a vertical dimension can run through
;; several bands, and each draws just its stretch.
(defun lzt:arrow (x1 y1 x2 y2 col / s a b p q)
  (if (setq s (lzt:clipseg x1 y1 x2 y2))
      (vector_image (lzt:px (car s)) (lzt:py (cadr s))
                    (lzt:px (caddr s)) (lzt:py (cadddr s)) col))
  (setq a 6 b 3)
  (cond
    ((= y1 y2)                          ; horizontal: heads point in
     (if (lzt:iny y1)
         (progn
           (setq p (list (lzt:px (min x1 x2)) (lzt:py y1))
                 q (list (lzt:px (max x1 x2)) (lzt:py y1)))
           (vector_image (car p) (cadr p) (+ (car p) a) (- (cadr p) b) col)
           (vector_image (car p) (cadr p) (+ (car p) a) (+ (cadr p) b) col)
           (vector_image (car q) (cadr q) (- (car q) a) (- (cadr q) b) col)
           (vector_image (car q) (cadr q) (- (car q) a) (+ (cadr q) b) col))))
    (t                                  ; vertical
     (if (lzt:iny (min y1 y2))
         (progn
           (setq p (list (lzt:px x1) (lzt:py (min y1 y2))))
           (vector_image (car p) (cadr p) (- (car p) b) (+ (cadr p) a) col)
           (vector_image (car p) (cadr p) (+ (car p) b) (+ (cadr p) a) col)))
     (if (lzt:iny (max y1 y2))
         (progn
           (setq q (list (lzt:px x1) (lzt:py (max y1 y2))))
           (vector_image (car q) (cadr q) (- (car q) b) (- (cadr q) a) col)
           (vector_image (car q) (cadr q) (+ (car q) b) (- (cadr q) a) col))))))

;; Where one dimension's text belongs, and what it says: the LETTER
;; until a value is typed, then the value in the letter's place.  A
;; value too wide for its own span is shrunk to fit rather than allowed
;; to run into its neighbours -- eight treads sit shoulder to shoulder
;; along the chain and every one of them can carry a feet-and-inches
;; number.
(defun lzt:label (d / letter key x1 y1 x2 y2 side txt sc w h lx ly span mx my)
  (setq letter (car d) key (cadr d)
        x1 (lzt:px (nth 2 d)) y1 (lzt:py (nth 3 d))
        x2 (lzt:px (nth 4 d)) y2 (lzt:py (nth 5 d))
        side (nth 6 d)
        txt (lzt:get key)
        mx (/ (+ x1 x2) 2) my (/ (+ y1 y2) 2))
  (if (= txt "")
      (setq txt letter sc (lzt:basesc))
      (setq sc (/ (* (lzt:basesc) 90) 100)))
  (setq w (lzt:textw txt sc))
  (if (and (= side "h") (> w 0))
      (progn
        (setq span (abs (- x2 x1)))
        (if (> w span)
            (progn
              (setq sc (/ (* sc span) w))
              (if (< sc (/ (* (lzt:basesc) 55) 100))
                  (setq sc (/ (* (lzt:basesc) 55) 100)))
              (setq w (lzt:textw txt sc))))))
  (setq h (lzt:texth sc))
  (if (= side "h")
      (setq lx (- mx (/ w 2)) ly (- y1 h 4))
      ;; a vertical dimension labels at the TOP of its span, centred on
      ;; its own line, EXCEPT when that would run off the left edge
      (progn
        (setq ly (+ (min y1 y2) 5))
        (setq lx (if (< (- mx (/ w 2)) 2) (+ mx 4) (- mx (/ w 2))))))
  ;; and nothing is allowed off the edge of the picture
  (if (< lx 2) (setq lx 2))
  (if (> (+ lx w) (- lzt:*dx* 2)) (setq lx (- lzt:*dx* w 2)))
  (if (< ly 2) (setq ly 2))
  (if (> (+ ly h) (- lzt:*dy* 2)) (setq ly (- lzt:*dy* h 2)))
  ;; blank the strip behind it so the dimension line does not run
  ;; through the characters
  (fill_image (- lx 3) (- ly 2) (+ w 6) (+ h 4) lzt:*col-back*)
  (if (= key lzt:*focus*)
      (lzt:plinepx (list (- lx 3) (- ly 2) (+ lx w 3) (- ly 2)
                         (+ lx w 3) (+ ly h 2) (- lx 3) (+ ly h 2)
                         (- lx 3) (- ly 2))
                   lzt:*col-hi*))
  (lzt:text txt lx ly sc
            (if (= (lzt:get key) "") lzt:*col-line* lzt:*col-val*)))

;; The band a dimension's TEXT belongs to.
(defun lzt:anchor (d)
  (if (= (nth 6 d) "h")
      (nth 3 d)
      (min (nth 3 d) (nth 5 d))))

(defun lzt:inband (v) (and (<= lzt:*y0* v) (< v lzt:*y1*)))

;; The whole picture: every band painted once, each between its own
;; start_image and end_image.  Wedge dims draw nothing at all -- their
;; row of the drawing IS a row of real boxes now -- while every other
;; dim draws its clipped arrow in every band it crosses and its text in
;; the band its anchor falls in.
(defun lzt:redraw ( / c wk bands b i key poly d)
  (setq c     lzt:*chart*
        wk    (lzt:wedge-keys c)
        bands (lzt:bands c)
        i     0)
  (foreach b bands
    (setq key       (strcat "chart" (itoa i))
          lzt:*y0*  (car b)
          lzt:*y1*  (cdr b)
          lzt:*dx*  (dimx_tile key)
          lzt:*dy*  (dimy_tile key))
    (start_image key)
    (fill_image 0 0 lzt:*dx* lzt:*dy* lzt:*col-back*)
    (foreach poly (lzt:c-outline c)
      (lzt:pline (lzt:flatten poly) lzt:*col-line*))
    (foreach d (lzt:c-dims c)
      (if (not (member (cadr d) wk))
          (lzt:arrow (nth 2 d) (nth 3 d) (nth 4 d) (nth 5 d)
                     lzt:*col-dim*)))
    (foreach d (lzt:c-dims c)
      (if (and (not (member (cadr d) wk))
               (lzt:inband (lzt:anchor d)))
          (lzt:label d)))
    (end_image)
    (setq i (1+ i)))
  (setq lzt:*y0* 0
        lzt:*y1* 1000)
  (princ))

;;; -------------------- the generated DCL --------------------------------

(setq lzt:*chart-w* 58)         ; the chart column, in character cells
(setq lzt:*chart-h* 20)         ; its total height, spread over the bands
(setq lzt:*wedge-ed* 5)         ; a wedge box's edit_width

;; character cells across for a per-mille x
(defun lzt:cellx (v) (/ (* v lzt:*chart-w*) 1000.0))

;; One wedge row: the cut's dims as real edit boxes, pushed to their
;; letters' positions by spacers.  Positions are in character cells and
;; a box has its own minimum size, so this is honest about being
;; approximate: a box lands within a cell or so of its letter, and two
;; that would collide get pushed apart rather than overlapped.
(defun lzt:wedgerow (c y / out d lbl w want pos)
  (setq out (list "      : row {")
        pos 0.0)
  ;; LEFT TO RIGHT, whatever order the chart lists them in: the row is
  ;; built by walking a cursor across it, and a dim listed before its
  ;; left-hand neighbour would shove that neighbour to the wrong side
  (foreach d (vl-sort (lzt:cutdims c y)
                      '(lambda (p q)
                         (< (+ (nth 2 p) (nth 4 p))
                            (+ (nth 2 q) (nth 4 q)))))
    (setq lbl  (car d)
          w    (+ (strlen lbl) 4.0 lzt:*wedge-ed*)
          want (- (lzt:cellx (/ (+ (nth 2 d) (nth 4 d)) 2)) (/ w 2)))
    (if (< want (+ pos 0.5)) (setq want (+ pos 0.5)))
    (setq out (cons (strcat "        : spacer { width = "
                            (rtos (- want pos) 2 1) "; }")
                    out))
    (setq out (cons (strcat "        : edit_box { key = \"" (cadr d)
                            "\"; label = \"" lbl
                            "\"; edit_width = " (itoa lzt:*wedge-ed*)
                            "; fixed_width = true; }")
                    out))
    (setq pos (+ want w)))
  (setq out (cons "        spacer;" out))
  (reverse (cons "      }" out)))

;; The chart as a stack: an image tile per band, a wedge row at every
;; cut, heights split in proportion to the bands they show.
(defun lzt:bandtiles (c / out bands b i h)
  (setq i     0
        bands (lzt:bands c))
  (foreach b bands
    (setq h (/ (* (- (cdr b) (car b)) lzt:*chart-h*) 1000.0))
    (if (< h 0.8) (setq h 0.8))
    (setq out (append out
                      (list (strcat "      : image { key = \"chart" (itoa i)
                                    "\"; width = " (itoa lzt:*chart-w*)
                                    "; height = " (rtos h 2 1)
                                    "; fixed_width = true; "
                                    "fixed_height = true; color = -15; }"))))
    (if (< (1+ i) (length bands))
        (setq out (append out (lzt:wedgerow c (cdr b)))))
    (setq i (1+ i)))
  out)

;; The DCL name of a page.
(defun lzt:dlgname (p ty)
  (strcat "lazstep_p" (itoa p) "_" (strcase ty t)))

;; One page-one field.
(defun lzt:p1tile (d)
  (if (= (cadr d) "LIST")
      (strcat "    : popup_list { key = \"" (car d) "\"; label = \""
              (caddr d) "\"; edit_width = 12; }")
      (strcat "    : edit_box { key = \"" (car d) "\"; label = \""
              (caddr d) "\"; edit_width = 8; }")))

;; PAGE ONE: the type, the count, and the questions asked once.
(defun lzt:dcl-p1 (ty / out d)
  ;; out is consed newest-first and reversed once at the end, so this
  ;; seed list reads BACKWARDS: the label second here puts it second in
  ;; the file, after the line that opens the dialog.  The other way
  ;; round emits an attribute before its own dialog, which is not DCL.
  (setq out (list (strcat "  label = \"LazStep - " (lzt:title ty) "\";")
                  (strcat (lzt:dlgname 1 ty) " : dialog {")))
  (setq out (cons "  : row {" out))
  (foreach d lzt:*types*
    (setq out (cons (strcat "    : button { key = \"tab_" (car d)
                            "\"; label = \"" (cadr d) "\"; }")
                    out)))
  (setq out (cons "  }" out))
  (setq out (cons "  : boxed_column {" out))
  (setq out (cons "    label = \"How many steps\";" out))
  (setq out (cons (strcat "    : edit_box { key = \"steps\"; label = \""
                          "Number of steps (1-" (itoa lzt:*max-steps*)
                          ")\"; edit_width = 4; fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : text { key = \"msg\"; width = 60; label = \""
                          "The next page is a drawing built for that many"
                          " steps, with a box on every dimension.\"; }")
                  out))
  (setq out (cons "  }" out))
  (setq out (cons "  : boxed_column {" out))
  (setq out (cons (strcat "    label = \"" (lzt:title ty) " (" ty
                          ") - asked once for the run\";")
                  out))
  (foreach d (lzt:asks-of ty)
    (setq out (cons (lzt:p1tile d) out)))
  (setq out (cons "  }" out))
  (setq out (cons "  spacer;" out))
  (foreach d (lzt:hints ty)
    (setq out (cons (strcat "  : text { width = 60; label = \"" d "\"; }")
                    out)))
  (setq out (cons "  : row {" out))
  (setq out (cons (strcat "    : button { key = \"accept\"; label = \"Next >\";"
                          " is_default = true; fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : button { key = \"cancel\"; label = \"Cancel\";"
                          " is_cancel = true; fixed_width = true; }")
                  out))
  (setq out (cons "  }" out))
  (reverse (cons "}" out)))

;; What page one has to say, per type.
(defun lzt:hints (ty / out)
  (setq out (list (strcat "The walls, the curve, the side to draw toward and"
                          " the profile's pick all stay")
                  "in the drawing.  Leave a box empty and the routine asks."))
  (if (= ty "CORNERSTP")
    (setq out (append out
                (list (strcat "Measure and Steps-run are asked only when the"
                              " selection turns up a corner diagonal or")
                      "fillet; on a plain corner they are ignored."))))
  (if (= ty "HEMISTEP")
    (setq out (append out
                (list "NA at the wall width or the crown means none."))))
  out)

;; One column row: the letter as a button, then the box.  Clicking the
;; letter puts the caret in that box and rings the dimension on the
;; chart -- which is as close to clicking the drawing itself as DCL
;; allows, and the button sits against the box it fills.
(defun lzt:colcell (d lbl ed)
  (list (strcat "          : button { key = \"pick_" (cadr d)
                "\"; label = \"" (car d) "\"; fixed_width = true; }")
        (strcat "          : edit_box { key = \"" (cadr d)
                "\"; edit_width = " (itoa ed) "; label = \"" lbl "\"; }")))

;; PAGE TWO: the drawing built for the count, with the boxes on it.
(defun lzt:dcl-p2 (c / out d wk widths depths pair l)
  (setq out (list (strcat "  label = \"LazStep - " (lzt:c-title c) ", "
                          (itoa (length (lzt:treads c))) " steps\";")
                  (strcat (lzt:dlgname 2 (lzt:c-type c)) " : dialog {")))
  (setq wk (lzt:wedge-keys c))
  (setq out (cons "  : row {" out))
  ;; PASSIVE image tiles, deliberately, stacked with the wedge rows
  ;; between them -- see the header for what an image_button costs.
  (setq out (cons "    : column {" out))
  (foreach l (lzt:bandtiles c)
    (setq out (cons l out)))
  (setq out (cons "    }" out))
  (setq out (cons "    : column {" out))
  ;; the widths: one row each, labelled, because what a width means
  ;; differs between the three types
  (foreach d (lzt:c-dims c)
    (if (and (not (member (cadr d) wk)) (not (lzt:depthkey (cadr d))))
      (setq widths (cons d widths))))
  (setq widths (reverse widths))
  (if widths
    (progn
      (setq out (cons "      : boxed_column {" out))
      (setq out (cons "        label = \"Step widths\";" out))
      (foreach d widths
        (setq out (cons "        : row {" out))
        (foreach l (lzt:colcell d (nth 7 d) 8) (setq out (cons l out)))
        (setq out (cons "        }" out)))
      (setq out (cons "      }" out))))
  ;; the depths: TWO TO A ROW.  One row each would add N+1 rows to a
  ;; page that already grows with N, and a dialog taller than the
  ;; screen does not open at all.
  (foreach d (lzt:c-dims c)
    (if (lzt:depthkey (cadr d)) (setq depths (cons d depths))))
  (setq depths (reverse depths))
  (if depths
    (progn
      (setq out (cons "      : boxed_column {" out))
      (setq out (cons "        label = \"Depths, top step first\";" out))
      (setq pair nil)
      (foreach d depths
        (if (null pair)
          (setq out  (cons "        : row {" out)
                pair d)
          (setq pair nil))
        (foreach l (lzt:colcell d "" 7) (setq out (cons l out)))
        (if (null pair) (setq out (cons "        }" out))))
      (if pair (setq out (cons "        }" out)))
      (setq out (cons "      }" out))))
  (setq out (cons "    }" out))
  (setq out (cons "  }" out))
  (setq out (cons "  spacer;" out))
  (foreach l (list (strcat "D1 is the drop into step 1; DA is the drop after"
                           " the last tread.")
                   (strcat "NA in a width means fit to the walls or the"
                           " curve.  An empty box is asked for at the")
                   "command line, where the picks and the selections are.")
    (setq out (cons (strcat "  : text { width = 66; label = \"" l "\"; }")
                    out)))
  (setq out (cons "  : row {" out))
  (setq out (cons (strcat "    : button { key = \"accept\"; label = \"Insert\";"
                          " is_default = true; fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : button { key = \"back\"; label = \"< Back\";"
                          " fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : button { key = \"cancel\"; label = \"Cancel\";"
                          " is_cancel = true; fixed_width = true; }")
                  out))
  (setq out (cons "  }" out))
  (reverse (cons "}" out)))

;; Every tread on the chart, whichever row it was staggered onto: the
;; step count the drawing was built for, read back off the drawing.
(defun lzt:treads (c / d out)
  (foreach d (lzt:c-dims c)
    (if (lzt:treadkey (cadr d)) (setq out (cons d out))))
  (reverse out))

;; Every page, in one file.  Page one for all three types -- so a tab
;; switch needs nothing from disk -- and page two for the chart the
;; count has generated, when there is one.
(defun lzt:dcl-lines ( / out ty)
  (foreach ty lzt:*types*
    (setq out (append out (lzt:dcl-p1 (car ty)) (list ""))))
  (if lzt:*chart*
    (setq out (append out (lzt:dcl-p2 lzt:*chart*) (list ""))))
  out)

(defun lzt:write-lines (fh / l)
  (foreach l (lzt:dcl-lines) (write-line l fh)))

(defun lzt:write-dcl ( / f fh err)
  (setq f (vl-filename-mktemp "lazstep" nil ".dcl"))
  (if (and f (setq fh (open f "w")))
    (progn
      (setq err (vl-catch-all-apply 'lzt:write-lines (list fh)))
      (close fh)
      (cond
        ((vl-catch-all-error-p err) (vl-file-delete f) nil)
        (t f)))))

;;; -------------------- the pages ---------------------------------------

;; Open a page where the user last had the dialog.  done_dialog reports
;; the position it was closed at and new_dialog takes one back, but only
;; as a 4-argument call -- and a build that answered done_dialog with
;; something other than a point would poison every reopen, so the shape
;; is checked before it is trusted and the plain 2-argument call is the
;; fallback.
(defun lzt:newdlg (name dcl)
  (if (and lzt:*pos* (listp lzt:*pos*) (= (length lzt:*pos*) 2)
           (numberp (car lzt:*pos*)) (numberp (cadr lzt:*pos*)))
      (new_dialog name dcl "" lzt:*pos*)
      (new_dialog name dcl)))

(defun lzt:page1 (dcl / d k)
  (cond
    ((not (lzt:newdlg (lzt:dlgname 1 lzt:*type*) dcl)) 9)
    (t
     ;; the tabs -- each closes this page and names the next.  A type
     ;; whose routine is not in this session is greyed rather than
     ;; offered: its Insert could only fail.
     (foreach d lzt:*types*
       (action_tile (strcat "tab_" (car d))
         (strcat "(setq lzt:*go* \"" (car d) "\" lzt:*pos* (done_dialog 4))"))
       (if (not (lzt:loaded (car d)))
         (mode_tile (strcat "tab_" (car d)) 1)))
     (set_tile "steps" (lzt:get "steps"))
     (action_tile "steps" "(lzt:put \"steps\" $value)")
     (if (/= lzt:*msg* "") (set_tile "msg" lzt:*msg*))
     (foreach d (lzt:asks)
       (cond
         ((= (cadr d) "LIST")
          (start_list (car d))
          (foreach k (nth 3 d) (add_list k))
          (end_list)
          (set_tile (car d) (itoa (lzt:sel (car d))))
          (action_tile (car d)
            (strcat "(lzt:p1pick \"" (car d) "\" $value)")))
         (t
          (set_tile (car d) (lzt:get (car d)))
          (action_tile (car d)
            (strcat "(lzt:put \"" (car d) "\" $value)")))))
     (action_tile "accept" "(setq lzt:*pos* (done_dialog 1))")
     (action_tile "cancel" "(setq lzt:*pos* (done_dialog 0))")
     (lzt:p1grey)
     (start_dialog))))

(defun lzt:page2 (dcl / d wk)
  (cond
    ((not (lzt:newdlg (lzt:dlgname 2 lzt:*type*) dcl)) 9)
    (t
     (setq wk (lzt:wedge-keys lzt:*chart*))
     ;; put back what was typed the last time this count was on screen
     (foreach d (lzt:keys lzt:*chart*)
       (set_tile d (lzt:get d))
       (action_tile d
         (strcat "(lzt:put \"" d "\" $value) (setq lzt:*focus* \"" d "\")"
                 " (lzt:redraw)")))
     ;; a wedge dim has no pick button -- its box already sits on the
     ;; drawing where the letter was
     (foreach d (lzt:c-dims lzt:*chart*)
       (if (not (member (cadr d) wk))
         (action_tile (strcat "pick_" (cadr d))
           (strcat "(setq lzt:*focus* \"" (cadr d) "\") (lzt:redraw)"
                   " (mode_tile \"" (cadr d) "\" 2)"
                   " (mode_tile \"" (cadr d) "\" 3)"))))
     ;; the chart takes no action at all -- it is a passive image tile
     (action_tile "back" "(setq lzt:*pos* (done_dialog 5))")
     (action_tile "accept" "(setq lzt:*pos* (done_dialog 1))")
     (action_tile "cancel" "(setq lzt:*pos* (done_dialog 0))")
     (lzt:redraw)
     (lzt:p2grey)
     (start_dialog))))

;; The count, checked before a page is built for it.  Nothing here can
;; measure a screen and N rows of boxes grow the page linearly, so a
;; number past the ceiling is refused with a message rather than
;; opening a dialog that might not fit on it.
(defun lzt:count-ok ( / n)
  (setq n (lzt:int (lzt:get "steps")))
  (cond
    ((null n)
     (setq lzt:*msg* (strcat "How many steps?  A whole number from 1 to "
                             (itoa lzt:*max-steps*) ", please."))
     (princ (strcat "\nLAZSTEP: " lzt:*msg*))
     nil)
    ((> n lzt:*max-steps*)
     (setq lzt:*msg* (strcat (itoa lzt:*max-steps*)
                             " steps is the ceiling - a taller dialog"
                             " will not open.  Run the rest by hand."))
     (princ (strcat "\nLAZSTEP: " lzt:*msg*))
     nil)
    (t (setq lzt:*steps* n) T)))

;;; -------------------- the run -----------------------------------------
;;  A helper rather than the command body, so its localized *error* is
;;  out of scope by the time the step routine is started: each of the
;;  three installs its own, and a CORNERSTP that fails must report as
;;  CORNERSTP.

(defun lzt:show ( / *error* f dcl rc done out)
  (defun *error* (msg)
    (term_dialog)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (setq dcl nil)
    (if f (vl-file-delete f))
    (setq f nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZSTEP error: " msg)))
    (princ))
  (setq lzt:*vals*  nil
        lzt:*sel*   nil
        lzt:*steps* nil
        lzt:*chart* nil
        lzt:*focus* nil
        lzt:*pos*   nil
        lzt:*msg*   ""
        lzt:*page*  1)
  ;; THE PAGE LOOP.  DCL has no tab tile and no way to rebuild a dialog
  ;; that is already up, so a page change closes this one and opens the
  ;; next -- and because done_dialog hands back where the dialog was
  ;; standing, it reopens exactly there instead of wandering off to the
  ;; middle of the screen.  Everything typed lives in lzt:*vals*, keyed,
  ;; so it survives the switch: change the count, come back, and the
  ;; steps that still exist still carry what was typed against them.
  (while (not done)
    (setq f (lzt:write-dcl))
    (cond
      ((null f)
       (princ "\nLAZSTEP error: could not write the dialog file.")
       (setq done T))
      ((< (setq dcl (load_dialog f)) 0)
       (princ "\nLAZSTEP error: could not load the dialog file.")
       (vl-file-delete f)
       (setq f nil done T))
      (t
       (setq rc (if (= lzt:*page* 1) (lzt:page1 dcl) (lzt:page2 dcl)))
       (unload_dialog dcl)
       (setq dcl nil)
       (vl-file-delete f)
       (setq f nil)
       (cond
         ((= rc 9)
          (princ "\nLAZSTEP error: could not open the form.")
          (setq done T))
         ((= rc 0) (setq done T))
         ((and (= lzt:*page* 1) (= rc 4))
          (setq lzt:*type* lzt:*go* lzt:*msg* ""))
         ((and (= lzt:*page* 1) (= rc 1))
          ;; the drawing is generated HERE, from the count that was
          ;; just accepted -- come back with a different number and a
          ;; different drawing is built for it
          (if (lzt:count-ok)
            (setq lzt:*chart* (lzt:chart lzt:*type* lzt:*steps*)
                  lzt:*focus* nil
                  lzt:*msg*   ""
                  lzt:*page*  2)))
         ((and (= lzt:*page* 2) (= rc 5))
          (setq lzt:*page* 1 lzt:*msg* "" lzt:*focus* nil))
         ((and (= lzt:*page* 2) (= rc 1))
          (setq out (lzt:form) done T))
         (t (setq done T))))))
  out)

;;; -------------------- commands ----------------------------------------

;; The form, then the step routine with what it collected.  The chart
;; fills that routine's answers in, so it has to be here to receive
;; them -- say so plainly rather than opening a form whose Insert
;; button could only fail.  The three load together as one bundle, so
;; the gate is checked per TYPE: the one the operator picked.
(defun c:LAZSTEP ( / form ty)
  (cond
    ((not (lzt:first-loaded))
     (princ "\nLAZSTEP: no step routine is loaded in this session -- APPLOAD")
     (princ "\n         lisp/cornerstp/CORNERSTP.lsp, HEMISTEP.lsp and")
     (princ "\n         NORMIESTEP.lsp, or LAZPASS.lsp, which has all three."))
    (t
     (if (not (lzt:loaded lzt:*type*))
       (setq lzt:*type* (lzt:first-loaded)))
     (setq form (lzt:show)
           ty   lzt:*type*)
     (cond
       ((null form) (princ "\nLAZSTEP: cancelled, nothing drawn."))
       ((not (lzt:loaded ty))
        (princ (strcat "\nLAZSTEP: " ty " is not loaded in this session"
                       " -- nothing drawn.")))
       (t
        (princ (strcat "\nLAZSTEP: " (itoa (length form)) " answers to " ty
                       " for " (itoa lzt:*steps*)
                       " steps; it will ask for whatever is left."))
        (lzt:run ty form)))))
  (princ))

(defun c:LAZSTEPVER ()
  (princ (strcat "\nLAZSTEP " *lazstep-version* " (LAZSTEP.lsp) - "
                 (itoa (length lzt:*types*)) " step routine(s), up to "
                 (itoa lzt:*max-steps*) " steps."))
  (princ))

(princ (strcat "\nLAZSTEP " *lazstep-version*
               " loaded.  Type LAZSTEP to fill a step drawing in."))
(princ)
