;;; ======================================================================
;;; HEMISTEP.lsp
;;; ----------------------------------------------------------------------
;;; Hemisphere (semicircle) step layout routine.
;;; Written for AutoCAD 2018 (plain AutoLISP + ActiveX for dim styles).
;;;
;;; LOAD:     APPLOAD this file (or drag it into the drawing window).
;;; COMMAND:  HEMISTEP
;;;
;;; WHAT IT DOES
;;;   Draws pool steps that act like chords inside a circle: parallel
;;;   step edges centered on a measuring axis.  What you select decides
;;;   how the axis is found:
;;;
;;;   LINE only ........ the classic base-line mode.  Steps are centered
;;;                      on the middle of the line, run parallel to it,
;;;                      and march perpendicular away from it in a
;;;                      direction you pick.  The hemisphere boundary is
;;;                      drawn for you (see step 6).
;;;   CURVE + LINE ..... inside-out mode with an axis line.  The line
;;;                      (through the curve or ending on it) is where
;;;                      the step treads are measured from: treads run
;;;                      along the line starting where it meets the
;;;                      curve, going INTO the curve, and the step
;;;                      widths sit perpendicular to the line.
;;;   CURVE only ....... inside-out mode from the middle of the curve.
;;;                      Treads are measured from there going INTO the
;;;                      curve, and the step widths sit along the
;;;                      tangent at that point.
;;;
;;;   A CURVE may be an ARC, a CIRCLE, or a POLYLINE - including a
;;;   composite hemisphere built from several arc segments, and
;;;   including a boundary this command drew earlier.  Each step is
;;;   measured against whichever part of the curve it actually lands
;;;   on, using the opening nearest the axis on each side.
;;;
;;;   In the curve modes the routine holds as true to the curve as it
;;;   can, the same way CORNERSTP holds to the walls: a step width
;;;   within the width tolerance of the curve's opening at that distance
;;;   is snapped to the curve; any other width is held, centered on the
;;;   opening so it breaks the curve equally on both sides.
;;;
;;; WORKFLOW
;;;   1.  Select the base line, the base curve, or the curve plus its
;;;       axis line.
;;;   2.  LINE-only mode asks you to pick a point for the side the
;;;       steps go.  The curve modes assume the steps go into the curve
;;;       and only ask for a side when the geometry is ambiguous.
;;;   3.  You are asked whether to dimension the steps [Yes/No]:
;;;         - Step widths across each chord, nested behind the start of
;;;           the measuring axis (wider steps further out), in dim style
;;;           "SIDE STANDARD".
;;;         - Step treads chained along the axis (start to step 1, step
;;;           1 to step 2, ...), in dim style "STANDARD INCHES".
;;;       If a style is missing the current style is used instead.
;;;   4.  LINE mode starts with the width of the step AT THE WALL: that
;;;       is the top of the run, so no chord is drawn there (the wall
;;;       already is one), but it is dimensioned and it anchors both
;;;       ends of the boundary curve.  The curve modes skip it, since
;;;       the width at the start is set by the curve itself.
;;;   5.  From there both modes run STEP TREAD then WIDTH, repeating.
;;;       Every step tread is measured FROM THE PREVIOUS STEP EDGE (from
;;;       the start of the axis for the first step) - never a running
;;;       total.
;;;       Distances read architectural style: a bare number is inches
;;;       (drawing units) and feet-inch entry like 1'4 (= 16") works
;;;       whatever the units setting.
;;;   6.  Ending and shortcuts:
;;;         - Enter at a step tread prompt = done.
;;;         - Back at a step tread prompt steps back one step: it
;;;           removes the step just drawn (its line and its dimensions).
;;;           Undo, the old keyword, is still accepted.  Same - typed
;;;           S - repeats the previous step tread.
;;;         - From the second step on the step tread is asked beside
;;;           the LENGTH RULER (below): a click on a row is the tread.
;;;         - Enter at a width prompt fits that step to the curve in
;;;           the curve modes, where Same (S) is then what repeats the
;;;           previous width; or repeats the previous width in LINE
;;;           mode.
;;;   7.  The hemisphere is then rebuilt as one polyline of arc segments
;;;       through every step end.  In LINE mode you are asked for one
;;;       last distance from the last step to the back of the curve, and
;;;       the polyline runs wall - side A - crown - side B - wall (the
;;;       last distance also gets the final link of the tread-dim chain).
;;;       In the curve modes the polyline runs from the deepest step
;;;       around the first one and back, and the segment spanning the
;;;       first step carries the SELECTED CURVE'S OWN bulge: a first
;;;       step sitting on the curve reproduces that curve exactly, and
;;;       a wider one still follows its curvature instead of spiking in
;;;       to the point where the axis met it.
;;;   8.  When steps were drawn you may add a SIDE PROFILE [Yes/No]:
;;;       give the step depths (the vertical drops), top step first -
;;;       one per step PLUS one more for the drop after the last
;;;       tread, so 3 steps take 4 depths - with Back to re-ask the
;;;       previous one, and the length ruler beside every depth after
;;;       the first; then pick the top of the wall (the curve, in
;;;       the curve modes).  The flight READS FROM THE WALL: the first
;;;       depth asked is the drop AT THE WALL and the first tread it
;;;       draws is the flat against it - the one the plan measured
;;;       from the wall to the first chord.  It always runs DOWN AND
;;;       TO THE LEFT from the pick, so there is no side to pick.
;;;       See "The side profile" below.
;;;   9.  Finally, BEAD THE STEPS.  Every tread is beaded - that is the
;;;       assumption - EXCEPT the last one drawn: the line that closes
;;;       the run has no riser behind it, so it is handed to AUTOBEAD
;;;       and held back there unbeaded.  The only thing asked is which
;;;       steps carry the bead along their side walls: All of them,
;;;       Some, given by step number, or None at all.  AUTOBEAD does
;;;       the work on its own rules (2" toward the side you click, onto
;;;       its Bead Track layer), so AUTOBEAD.lsp has to be loaded; when
;;;       it is not, the run says so and finishes without beading.  The
;;;       beads are their own undo group - AutoCAD does not nest them -
;;;       so one U undoes the beads and the next undoes the steps.
;;;
;;; THE SIDE PROFILE
;;;   The flight is drawn as an alternating drop/tread silhouette in
;;;   the current UCS, always descending to the LEFT of the picked top
;;;   of the WALL and ending on the last depth - so the steps rise to
;;;   the right, the way the shop's own elevations read, and stand
;;;   upright in a turned UCS, where the dims measure the drops.  It
;;;   starts where the run starts: the pick is the top of the wall, the
;;;   first drop is the drop at the wall, and the first tread is the
;;;   flat between the wall and the first chord.  Every tread after
;;;   that is the gap between two chords, so the flight covers the same
;;;   distances the plan's tread chain does, in the same order.  (In
;;;   the curve modes the run starts at the curve instead, and the
;;;   flight says so.)
;;;   The dims climb with them, up and to the right, on the high side:
;;;     * every depth is a dim of its own, standing the same distance
;;;       right of the corner its drop lands on, so they step out with
;;;       the flight instead of stacking in one chain;
;;;     * the overall depth sits further out again;
;;;     * the treads carry no dims - the depths and the overall say it.
;;;   How far out the fan sits is *CS-PROFILE-DIMGAP* - the gap on top
;;;   of the clearance the geometry needs.  Raise it to open the dims
;;;   out further, lower it to tuck them in.
;;;   Each one is a VERTICAL LINEAR dim bound to the two step corners
;;;   that bracket the drop.  Those corners run diagonally to each
;;;   other, so binding the diagonal (rather than dimensioning the
;;;   riser line) keeps the extension lines hooked to the geometry
;;;   while the dim still reads the drop, not the slope.
;;;
;;; THE LENGTH RULER
;;;   From the second step tread on - and from the second step depth
;;;   on, in the side profile - the prompt stands beside DIMSTAMP's
;;;   ruler: the eighths of an inch for a whole inch either side of
;;;   the last answer, drawn down a strip near the right edge of the
;;;   view, graded like a tape with the last answer ringed.  Click a
;;;   row and that is the answer; type one and it reads as DIMSTAMP
;;;   reads (24, 24.5, 24-1/8, 2', 1'4-1/2", kept exactly as typed --
;;;   dash a fraction, since the spacebar is Enter at a prompt that
;;;   also takes a click: 24 1/8 enters 24, and the 1/8 answers the
;;;   question after it without a word); click empty space and it is
;;;   the first of two points to measure between, as getdist always
;;;   offered.  Enter, Back and Same mean
;;;   what they always did, and the prompt's wording is unchanged, so
;;;   a form answers it exactly as before.  The ruler is scratch on
;;;   the current layer: down again before the width prompt (which
;;;   cannot take it) and before the profile's pick, and swept on
;;;   every way out, Esc included.  Its knobs are the *cs-ruler-*
;;;   settings, shared by the three step routines.
;;;
;;; THE SETTINGS
;;;   Every number this routine can be told to draw differently is a
;;;   setting at the top of the file, under SETTINGS, one per knob with
;;;   what it does and what it defaults to - the width tolerance and the
;;;   inches it is derived from, the two dim styles and the dim layer,
;;;   how far the tread chain stands off the axis and how far the width
;;;   dims nest behind the start of it, the side profile's dim gap, and
;;;   the length ruler's colours, place and size.  setq one before
;;;   running the command and the next run picks it up.
;;;   They are shared with CORNERSTP and NORMIESTEP, which is why they
;;;   are *cs- names: one set of knobs for the three step routines.
;;;
;;; NOTES
;;;   - Geometry is assumed to be drawn in plan view.  The routine warns
;;;     when the current UCS is not World, when selected geometry is not
;;;     flat, and when the current layer is off/frozen/locked.
;;;   - Steps are drawn as LINEs on the current layer.
;;;   - DIMSCALE (or the annotation scale for annotative styles) sets
;;;     the dimension size; grab a dimension line to slide it if it
;;;     lands awkwardly.
;;;   - One U / UNDO reverses the whole command; a bead run added at
;;;     the end is its own group, so it takes a U of its own.
;;;   - A form (the Calofin palette / LAZFORM) can pre-answer the
;;;     questions - the step COUNT included, which the prompts only
;;;     ever learn from Enter - by leaving (key . value) pairs in
;;;     *HS-FORM*; see "form answers" below.  Selections and point
;;;     picks are always made by hand.
;;; ======================================================================

;;; ------------------------------ SETTINGS ------------------------------
;;;  THE KNOBS, all of them, in one place.  Each is defined only if it
;;;  is not already set, so this file, CORNERSTP.lsp and NORMIESTEP.lsp
;;;  share ONE set of settings whichever loads first and a value set
;;;  before loading them stands.  setq one at the command line - or in
;;;  acaddoc.lsp - and the next run picks it up.
;;;
;;;  Deliberately NOT settings: the epsilons the geometry compares
;;;  against (a point is on the curve or it is not), the temporary
;;;  vectors the run previews itself with, the direction the side
;;;  profile reads (down and to the left, the way the shop's elevations
;;;  do), and the bead - that is AUTOBEAD's work, on its own settings.

;; Step width tolerance, in drawing units: a step whose requested width
;; is within this of the curve's opening at that distance is snapped to
;; the curve; any other width is held exactly and breaks away from it.
;; nil = derive it from *cs-tol-inch* through the drawing's INSUNITS.
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;

(if (not (boundp '*cs-width-tol*)) (setq *cs-width-tol* nil))

;; What that tolerance is in INCHES when it is derived - the shop reads
;; it as 1/8".  Raise it to let a wider mismatch still snap to the
;; curve; 0.0 snaps only an exact fit.
(if (not (boundp '*cs-tol-inch*)) (setq *cs-tol-inch* 0.125))

;; Dim style for the step-tread dims - the side profile's depth dims
;; use it too.  A style the drawing does not have is reported at the
;; start of the run and the current style is used instead.
(if (not (boundp '*cs-depth-dimstyle*)) (setq *cs-depth-dimstyle* "STANDARD INCHES"))

;; Dim style for the step-width dims, with the same fallback.
(if (not (boundp '*cs-width-dimstyle*)) (setq *cs-width-dimstyle* "SIDE STANDARD"))

;; Layer the dimensions are drawn on.  nil = the current layer; a layer
;; that is missing, off, frozen or locked is reported and the current
;; layer is used, so a run never draws dims where they cannot be seen.
(if (not (boundp '*cs-dim-layer*)) (setq *cs-dim-layer* nil))

;; How far the step-tread dim chain stands off the measuring axis, in
;; TEXT HEIGHTS - so it tracks DIMSCALE (or the annotation scale)
;; instead of the drawing's size.  2.0 keeps it clear of its own text.
(if (not (boundp '*cs-dim-offset*)) (setq *cs-dim-offset* 2.0))

;; How far a step-width dim sits behind the start of the axis, in text
;; heights, on top of half that step's own width.  The half-width is
;; what nests the wider steps progressively further out; this is the
;; gap on top of it.
(if (not (boundp '*cs-dim-nest*)) (setq *cs-dim-nest* 1.5))

;; How far the side profile's dims stand off the flight, in drawing
;; units, on top of the clearance the geometry itself needs.  nil = the
;; larger of the two terms below, which is what the shop's own
;; elevations read like; raise it to open the fan out further, lower it
;; to tuck the dims in.  It also sets how much further out again the
;; overall depth sits.
(if (not (boundp '*cs-profile-dimgap*)) (setq *cs-profile-dimgap* nil))

;; The two terms of that default: text heights, and a fraction of the
;; widest tread in the flight.  Keeping both is what makes the fan hold
;; its proportions whether or not the drawing has a dim scale set up.
(if (not (boundp '*cs-profile-gap-txt*)) (setq *cs-profile-gap-txt* 4.0))
(if (not (boundp '*cs-profile-gap-tread*)) (setq *cs-profile-gap-tread* 0.75))

;; The LENGTH RULER beside the step tread and step depth prompts: from
;; the second answer on, DIMSTAMP's ruler stands near the right edge of
;; the view - the eighths for an inch either side of the last length,
;; graded like a tape, the last one ringed - and a click on a row is the
;; answer.  Scratch on the current layer, down again before any prompt
;; that does not take it and on every way out.  Each size is a fraction
;; of the current view, so the ruler reads the same at any zoom.  The
;; first two are ACI colours: the rows you can pick, and the ringed
;; current row (7 is AutoCAD's black/white swap).
(if (not (boundp '*cs-ruler-color*)) (setq *cs-ruler-color* 3))
(if (not (boundp '*cs-ruler-current-color*)) (setq *cs-ruler-current-color* 7))

;; Where the spine sits across the view, as a fraction of its width in
;; from the left; past 0.5 the rows reach left, short of it right, so
;; the ruler is always inside the view.
(if (not (boundp '*cs-ruler-screen-x*)) (setq *cs-ruler-screen-x* 0.88))

;; One row's share of the view's height - the ruler's size knob - then
;; the biggest label, the longest tick and the ring round the current
;; row, each as a fraction of that row spacing.
(if (not (boundp '*cs-ruler-row-frac*)) (setq *cs-ruler-row-frac* 0.042))
(if (not (boundp '*cs-ruler-txt-frac*)) (setq *cs-ruler-txt-frac* 0.5))
(if (not (boundp '*cs-ruler-tick-frac*)) (setq *cs-ruler-tick-frac* 0.6))
(if (not (boundp '*cs-ruler-ring-frac*)) (setq *cs-ruler-ring-frac* 0.26))

;; How far inboard of the spine, in row spacings, a click still counts
;; as picking a row rather than as the first point of a measured length.
(if (not (boundp '*cs-ruler-reach*)) (setq *cs-ruler-reach* 6.0))

;; The two LADDERS those prompts stand on before there is a last answer
;; to build a tape round -- and beside it afterwards, with the answer
;; ringed among the rungs.  A flight is not built out of arbitrary
;; numbers: treads come in half-feet and drops in whole inches, so those
;; are the rows offered, as (LOW HIGH STEP) in inches.  A shop whose
;; steps run to some other measure sets its own here; nil on either
;; leaves that prompt the plain tape it was, with nothing offered until
;; the second answer.
(if (not (boundp '*cs-tread-ladder*)) (setq *cs-tread-ladder* '(6.0 36.0 6.0)))
(if (not (boundp '*cs-drop-ladder*)) (setq *cs-drop-ladder* '(6.0 12.0 1.0)))

;; What Enter answers at "Dimension the steps?".  "No" makes a bare
;; run the quick one and leaves the dims to be asked for by name.
(if (not (boundp '*cs-dims-default*)) (setq *cs-dims-default* "Yes"))

;; HEMISTEP only.  What Enter answers at "Draw the reconstructed
;; boundary through the step ends?".  "No" leaves the steps standing
;; on their own and rebuilds no hemisphere through them.
(if (not (boundp '*cs-boundary-default*)) (setq *cs-boundary-default* "Yes"))

;; What Enter answers at "Add a side profile?".  "No" ends a run at
;; the plan, so the step-depth questions behind it are reached only by
;; typing Yes.
(if (not (boundp '*cs-profile-default*)) (setq *cs-profile-default* "Yes"))

;; What Enter answers at "Bead the steps?".  "No" suits a shop that
;; runs AUTOBEAD itself once the drawing is finished.
(if (not (boundp '*cs-bead-default*)) (setq *cs-bead-default* "Yes"))

;; What Enter answers at the side-wall question once beading is on:
;; "All", "Some" (which then asks which step numbers) or "None", which
;; beads the step faces and leaves the walls bare.
(if (not (boundp '*cs-beadsides-default*)) (setq *cs-beadsides-default* "All"))

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

(setq *hs-version* "v3.28") ; printed on load and at command start so a
                           ; stale APPLOADed copy is easy to spot

;;; ------------------------- vector helpers -----------------------------

(defun hs-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun hs-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun hs-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun hs-unit (v / l)
  (if (> (setq l (sqrt (cal:dot v v))) 1e-10) (hs-scl v (/ 1.0 l))))

(defun hs-perp (v) (list (- (cadr v)) (car v) 0.0))

(defun hs-mid2 (a b) (list (* 0.5 (+ (car a) (car b)))
                           (* 0.5 (+ (cadr a) (cadr b)))
                           0.0))

;; distance from point P to the segment A-B
(defun hs-ptseg (p a b / d l2 t2)
  (setq d  (hs-vec a b)
        l2 (cal:dot d d))
  (if (< l2 1e-20)
    (distance p a)
    (progn
      (setq t2 (/ (cal:dot (hs-vec a p) d) l2))
      (cond ((< t2 0.0) (distance p a))
            ((> t2 1.0) (distance p b))
            (T (distance p (hs-add a (hs-scl d t2))))))))

;; how far point P lies beyond the ends of segment A-B (0.0 when on it)
(defun hs-beyond (p a b / d l t2)
  (setq d (hs-vec a b)
        l (sqrt (cal:dot d d)))
  (if (< l 1e-10)
    (distance p a)
    (progn
      (setq t2 (/ (cal:dot (hs-vec a p) d) (* l l)))
      (cond ((< t2 0.0) (* (- t2) l))
            ((> t2 1.0) (* (- t2 1.0) l))
            (T 0.0)))))

;; point on a circle: center C, radius R, angle A
(defun hs-arcpt (c r a)
  (list (+ (car c) (* r (cos a))) (+ (cadr c) (* r (sin a))) 0.0))

;; T when angle A lies on the counterclockwise span A1 -> A2
(defun hs-inspan (a a1 a2 / e)
  (setq e (- a2 a1))
  (if (< e 0.0) (setq e (+ e pi pi)))
  (setq a (- a a1))
  (if (< a 0.0) (setq a (+ a pi pi)))
  (<= a (+ e 1e-6)))

;;; ------------------------ curve description ---------------------------
;;; The selected curve becomes a list of boundary "pieces":
;;;   ("A" center radius startang endang)   arc, counterclockwise
;;;   ("S" p1 p2)                           straight segment
;;; so an arc, a circle and a multi-arc polyline are all handled alike.

;; intersections of the circle (C,R) with the infinite line through A
;; along the UNIT direction D; a list of 0 or 2 points
(defun hs-linecirc (a d c r / f g disc)
  (setq f    (hs-vec c a)
        g    (cal:dot d f)
        disc (+ (* r r) (- (* g g) (cal:dot f f))))
  (if (>= disc 0.0)
    (progn
      (setq disc (sqrt disc))
      (list (hs-add a (hs-scl d (- (- g) disc)))
            (hs-add a (hs-scl d (+ (- g) disc)))))))

;; Arc piece from an ARC entity.  Built from the curve's own start/mid/
;; end points and its OCS center, so mirrored arcs are handled.
(defun hs-arcpiece (en / ed c r sp ep mp a1 a2 sw)
  (setq ed (entget en)
        c  (trans (cdr (assoc 10 ed)) en 0)
        r  (cdr (assoc 40 ed))
        sp (vlax-curve-getstartpoint en)
        ep (vlax-curve-getendpoint en)
        mp (vlax-curve-getpointatdist
             en (* 0.5 (vlax-curve-getdistatparam
                         en (vlax-curve-getendparam en))))
        a1 (angle c sp)
        a2 (angle c ep))
  (if (not (hs-inspan (angle c mp) a1 a2))
    (setq sw a1 a1 a2 a2 sw))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list "A" c r a1 a2))

;; Arc piece for a polyline bulge segment P1 -> P2
(defun hs-bulgepiece (p1 p2 b / th l r h nrm cen a1 a2)
  (setq th  (* 4.0 (atan b))
        l   (distance p1 p2)
        r   (abs (/ l (* 2.0 (sin (/ th 2.0)))))
        h   (* r (cos (/ (abs th) 2.0)))
        nrm (hs-unit (hs-perp (hs-vec p1 p2)))
        cen (hs-add (hs-mid2 p1 p2)
                    (hs-scl nrm (if (> b 0.0) h (- h)))))
  (if (> b 0.0)
    (setq a1 (angle cen p1) a2 (angle cen p2))
    (setq a1 (angle cen p2) a2 (angle cen p1)))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list "A" cen r a1 a2))

;; Pieces of a POLYLINE (LWPOLYLINE or heavy 2D), points brought to WCS
(defun hs-plpieces (en / ed el cl vs bs i m out v1 v2 b sub pr)
  (setq ed (entget en)
        el (cond ((cdr (assoc 38 ed))) (0.0))
        cl (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))))
  (if (= "LWPOLYLINE" (cdr (assoc 0 ed)))
    (foreach pr ed
      (cond
        ((= 10 (car pr))
         (setq vs (cons (trans (list (car (cdr pr)) (cadr (cdr pr)) el) en 0) vs)
               bs (cons 0.0 bs)))
        ((= 42 (car pr))
         (if bs (setq bs (cons (cdr pr) (cdr bs)))))))
    (progn
      (setq sub (entnext en))
      (while (and sub (= "VERTEX" (cdr (assoc 0 (entget sub)))))
        (setq ed  (entget sub)
              vs  (cons (trans (cdr (assoc 10 ed)) en 0) vs)
              bs  (cons (cond ((cdr (assoc 42 ed))) (0.0)) bs)
              sub (entnext sub)))))
  (setq vs (reverse vs) bs (reverse bs) m (length vs) i 0)
  (while (< i (if cl m (1- m)))
    (setq v1 (nth i vs)
          v2 (nth (rem (1+ i) m) vs)
          b  (nth i bs))
    (if (> (distance v1 v2) 1e-10)
      (setq out (cons (if (equal 0.0 b 1e-9)
                        (list "S" v1 v2)
                        (hs-bulgepiece v1 v2 b))
                      out)))
    (setq i (1+ i)))
  (reverse out))

;; every crossing of the line (P along unit U) with the curve, as a list
;; of (point . piece) pairs
(defun hs-hits (p u pieces / out q pc)
  (foreach pc pieces
    (if (= "A" (car pc))
      (foreach q (hs-linecirc p u (cadr pc) (caddr pc))
        (if (hs-inspan (angle (cadr pc) q) (cadddr pc) (nth 4 pc))
          (setq out (cons (cons q pc) out))))
      (progn
        (setq q (inters p (hs-add p u) (cadr pc) (caddr pc) nil))
        (if (and q (< (hs-beyond q (cadr pc) (caddr pc)) 1e-8))
          (setq out (cons (cons q pc) out))))))
  out)

;; The curve's opening across P along U: the nearest crossing on each
;; side of P, as (h1 h2 width).  nil when the curve does not bracket P.
(defun hs-open (p u pieces / s sp sn h1 h2 hp)
  (foreach hp (hs-hits p u pieces)
    (setq s (cal:dot (hs-vec p (car hp)) u))
    (cond
      ((> s 1e-9)  (if (or (null sp) (< s sp)) (setq sp s h1 (car hp))))
      ((< s -1e-9) (if (or (null sn) (> s sn)) (setq sn s h2 (car hp))))))
  (if (and h1 h2) (list h1 h2 (- sp sn))))

;;; ---------------------- boundary polyline output ----------------------

;; center of the circle through three points, nil if collinear
(defun hs-circum (a b q / ax ay bx by qx qy d)
  (setq ax (car a) ay (cadr a)
        bx (car b) by (cadr b)
        qx (car q) qy (cadr q)
        d  (* 2.0 (+ (* ax (- by qy)) (* bx (- qy ay)) (* qx (- ay by)))))
  (if (> (abs d) 1e-12)
    (list (/ (+ (* (+ (* ax ax) (* ay ay)) (- by qy))
                (* (+ (* bx bx) (* by by)) (- qy ay))
                (* (+ (* qx qx) (* qy qy)) (- ay by)))
             d)
          (/ (+ (* (+ (* ax ax) (* ay ay)) (- qx bx))
                (* (+ (* bx bx) (* by by)) (- ax qx))
                (* (+ (* qx qx) (* qy qy)) (- bx ax)))
             d)
          0.0)))

;; polyline bulge for the arc A->B on the circle centered O
(defun hs-segb (a b o ccw / t1 t2 th)
  (setq t1 (angle o a)
        t2 (angle o b)
        th (if ccw (- t2 t1) (- t1 t2)))
  (if (< th 0.0) (setq th (+ th pi pi)))
  (* (if ccw 1.0 -1.0) (/ (sin (/ th 4.0)) (cos (/ th 4.0)))))

;; Midpoint of the arc that chord A-B carries with bulge BL.  A positive
;; bulge is counterclockwise, which bulges to the RIGHT of A->B.
(defun hs-bulgemid (a b bl / d nrm)
  (setq d   (hs-vec a b)
        nrm (hs-unit (list (cadr d) (- (car d)) 0.0)))
  (if nrm
    (hs-add (hs-mid2 a b) (hs-scl nrm (* 0.5 (distance a b) bl)))
    (hs-mid2 a b)))

;; Bulge for the boundary segment that spans the first step, A -> B,
;; taken from the arc piece PC that the start point REF sits on.  So the
;; boundary follows the ORIGINAL curve across the first step instead of
;; cutting in to a point on it.
;;
;; The side is chosen geometrically - whichever of the two possible arcs
;; bulges nearer REF - so no angle-wrap case can select the wrong one.
;; An arc sweeping more than half a circle would leave A heading back the
;; way the boundary came, folding the corner into a spike, so it is
;; rejected in favour of closing the span straight.
(defun hs-firstspan (a b pc ref / c b1 b2 bl)
  (setq c  (cadr pc)
        b1 (hs-segb a b c T)
        b2 (hs-segb a b c nil)
        bl (if (< (distance (hs-bulgemid a b b1) ref)
                  (distance (hs-bulgemid a b b2) ref))
             b1 b2))
  (if (> (abs bl) 1.0)
    (progn
      (princ (strcat "\n  Note: the curve wraps more than half a circle"
                     " across the first step - closing it straight."))
      0.0)
    bl))

;; A bulge past 1.0 sweeps more than half a circle, which folds the
;; boundary back on itself; such a segment is drawn straight instead.
(defun hs-safeb (bl)
  (if (or (null bl) (> (abs bl) 1.0)) 0.0 bl))

;; Circle through PTS[i], PTS[i+1], PTS[i+2] as (center . counterclockwise)
(defun hs-fit3 (pts i / a b c o)
  (setq a (nth i pts)
        b (nth (1+ i) pts)
        c (nth (+ i 2) pts)
        o (hs-circum a b c))
  (if o (cons o (> (cal:cross (hs-vec a b) (hs-vec a c)) 0.0))))

;; Bulges for a polyline through PTS, one per segment, by fitting a
;; circle through consecutive triples (a chain of 3-point arcs).
;;
;; K is the index of the crown vertex, or nil.  When given, the first
;; circle fitted is the one through the crown and its two neighbours,
;; and the rest are fitted outward from there.  That keeps the apex on
;; a single arc - so when those three points sit on the original curve
;; the reconstructed arc IS the original curve - instead of falling on
;; a seam between two circles.
;;
;; FIXED is an optional alist of (segment . bulge) that wins over any
;; fitting; when it holds the middle segment (the curve modes put the
;; original curve's own bulge there) the rest are fitted outward from
;; it, keeping both sides symmetric.
(defun hs-blgs (pts k fixed / nseg starts i res oc out st m)
  (setq nseg (1- (length pts))
        res  fixed)
  (if (or (null k) (< k 1) (> (1+ k) nseg)) (setq k nil))
  ;; the order triples are fitted in; earlier entries win
  (cond
    (k
     (setq starts (list (1- k))                ; the arc across the crown
           i      (- k 3))
     (while (>= i 0)                           ; outward, crown side A
       (setq starts (append starts (list i)) i (- i 2)))
     (setq i (1+ k))
     (while (<= (+ i 2) nseg)                  ; outward, crown side B
       (setq starts (append starts (list i)) i (+ i 2))))
    (fixed                                     ; outward from the fixed one
     (setq m (car (car fixed))
           i (- m 2))
     (while (>= i 0)
       (setq starts (append starts (list i)) i (- i 2)))
     (setq i (1+ m))
     (while (<= (+ i 2) nseg)
       (setq starts (append starts (list i)) i (+ i 2))))
    (T
     (setq i 0)
     (while (<= (+ i 2) nseg)
       (setq starts (append starts (list i)) i (+ i 2)))))
  ;; sweep every triple as a fallback so leftover end segments are
  ;; fitted through their own three points rather than a neighbour's
  (setq i 0)
  (while (<= (+ i 2) nseg)
    (setq starts (append starts (list i)) i (1+ i)))
  ;; A fitted segment sweeping more than half a circle leaves its start
  ;; heading back the way the boundary came - a fold, never right between
  ;; consecutive step ends - so such a segment is drawn straight.
  (foreach st starts
    (if (setq oc (hs-fit3 pts st))
      (progn
        (if (null (assoc st res))
          (setq res (cons (cons st (hs-safeb
                                     (hs-segb (nth st pts) (nth (1+ st) pts)
                                              (car oc) (cdr oc))))
                          res)))
        (if (null (assoc (1+ st) res))
          (setq res (cons (cons (1+ st) (hs-safeb
                                          (hs-segb (nth (1+ st) pts)
                                                   (nth (+ st 2) pts)
                                                   (car oc) (cdr oc))))
                          res))))))
  (setq i 0)
  (repeat nseg                                 ; 0.0 where nothing fitted
    (setq out (append out (list (cond ((cdr (assoc i res))) (0.0))))
          i   (1+ i)))
  out)

;; open LWPOLYLINE through PTS with one bulge per segment
(defun hs-mkpoly (pts blgs)
  (entmake (append
             (list '(0 . "LWPOLYLINE")
                   '(100 . "AcDbEntity")
                   '(100 . "AcDbPolyline")
                   (cons 90 (length pts))
                   '(70 . 0))
             (apply 'append
                    (mapcar '(lambda (p b)
                               (list (cons 10 (list (car p) (cadr p)))
                                     (cons 42 b)))
                            pts
                            (append blgs '(0.0)))))))


;;; --------------------------- bead helpers -----------------------------

;; The step numbers typed at a prompt, in the order typed: "1 3 4",
;; "1,3,4" and "1, 3 and 4" all read the same, and "1-3" is steps 1, 2
;; and 3 -- the range spelling PERPPTS's segment prompt takes, so a
;; drafter used to it types it here too.  Every non-digit used to be a
;; separator, which read 1-3 as steps 1 and 3 and left step 2 bare
;; without a word.  Spaces and commas separate and "and" is a
;; separator word; anything else -- another word, a backwards range, a
;; stray dash -- makes the whole answer unreadable, and nil comes back
;; so the question is asked again rather than beading a guess.
(defun hs-numlist (str / toks tok i c out r a b bad)
  (setq toks '() tok "" i 1)
  (while (<= i (1+ (strlen str)))
    (setq c (if (<= i (strlen str)) (substr str i 1) " "))
    (if (or (= c " ") (= c ","))
      (progn
        (if (/= tok "") (setq toks (cons tok toks)))
        (setq tok ""))
      (setq tok (strcat tok c)))
    (setq i (1+ i)))
  (setq out '() bad nil)
  (foreach tok (reverse toks)
    (cond
      ((= (strcase tok) "AND") nil)
      ((setq r (hs-numrange tok))
       (setq a (car r) b (cadr r))
       (while (<= a b)
         (if (not (member a out)) (setq out (cons a out)))
         (setq a (1+ a))))
      (T (setq bad T))))
  (if bad nil (reverse out)))

;; One token of that answer as (FROM TO): "3" is (3 3), "1-3" is (1 3).
;; nil for anything else, a range that runs backwards included.  Each
;; end is three digits at most: no run draws a thousand steps, and a
;; slip like 1-100000 was expanded one step at a time against every
;; step already read -- billions of comparisons, in a loop Esc does not
;; reliably break.  Refused here, it is asked again like any answer the
;; reader cannot read.
(defun hs-numrange (tok / p lft rgt)
  (setq p (vl-string-search "-" tok))
  (if p
    (setq lft (substr tok 1 p)
          rgt (substr tok (+ p 2)))
    (setq lft tok
          rgt tok))
  (if (and (hs-digits-p lft) (hs-digits-p rgt)
           (<= (strlen lft) 3) (<= (strlen rgt) 3)
           (<= (atoi lft) (atoi rgt)))
    (list (atoi lft) (atoi rgt))))

;; T when S is one or more of 0-9 and nothing else.
(defun hs-digits-p (s / i ok)
  (setq ok (> (strlen s) 0) i 1)
  (while (and ok (<= i (strlen s)))
    (if (not (cal:len-digit-p (substr s i 1))) (setq ok nil))
    (setq i (1+ i)))
  ok)

;; The tread line of every step that was committed, as
;; (step-number . ename).  A step's log record carries its entities
;; first and its step number at index 3, and the only LINE among
;; those entities is its tread - any dimension beside it is a DIMENSION.
(defun hs-treadents (log / out rec e ln)
  (setq out '())
  (foreach rec log
    (setq ln nil)
    ;; ...-since lists newest first, and a step draws its tread before
    ;; any side line or dimension, so the LAST line seen is the tread
    (foreach e (car rec)
      (if (and e (entget e)
               (= "LINE" (cdr (assoc 0 (entget e)))))
        (setq ln e)))
    (if ln (setq out (cons (cons (nth 3 rec) ln) out))))
  ;; the log runs newest first, so consing through it already leaves
  ;; the pairs in step order - lowest first, the way they were drawn
  out)

;; The step numbers on offer, as "1, 2, 3" - so the numbers prompt can
;; be answered without scrolling back through the run.  PAIRS is the
;; (step-number . tread) list, or a plain list of step numbers -- the
;; readback of what an answer was taken to mean.
(defun hs-numsay (pairs / out pr)
  (setq out "")
  (foreach pr pairs
    (setq out (strcat out (if (= out "") "" ", ")
                      (itoa (if (numberp pr) pr (car pr))))))
  out)

;; Midpoint (WCS) of a LINE entity.
(defun hs-entmid (e / ed)
  (setq ed (entget e))
  (hs-mid2 (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))

;;; ------------------------- setting helpers ----------------------------
;;;  Every setting is read through one of these rather than straight out
;;;  of the global, and the fallback in each is the value the SETTINGS
;;;  block initialises that setting to: a setting somebody set to
;;;  something unusable - a string where a number belongs, a symbol -
;;;  then costs the shipped behaviour and nothing else, instead of
;;;  failing in the middle of a run.  tests/test_steps_settings.py holds
;;;  the two copies of each number together.

;; A setting that has to be a number: V when it is one, DFLT when it is
;; not.
(defun hs-num (v dflt) (if (numberp v) v dflt))

;; A setting that has to be one of a prompt's KEYWORDS: the canonical
;; spelling S stands for, in any case, or nil for anything that is not
;; one of them, so the caller can fall back to the word it ships with.
;; hs-fkw and a bare Enter both hand a default straight back unchecked,
;; and "no" set in acaddoc.lsp must not reach a (/= "No" fkey) test
;; unspelled.
(defun hs-kwcanon (s kws / u out w)
  (setq u (if (= (type s) 'STR) (strcase s) ""))
  (foreach w kws (if (= u (strcase w)) (setq out w)))
  out)

;; A setting that has to be a NAME - a layer, a dim style: V when it is
;; a string, DFLT when it is not.  The third guard, beside hs-num's for
;; a number and hs-kwcanon's for a keyword, and the one that was
;; missing.  A name does not stay in Lisp: it reaches tblsearch, setvar
;; "CLAYER" and strcat, and every one of those is "bad argument type:
;; stringp" thrown in the middle of a run on anything else.  That is
;; reachable rather than theoretical -- LAZTUNE reads a knob SHIPPED
;; nil as "off, or a value" and so lets any atom into it, and nil in
;; *cs-dim-layer* means "the current layer" rather than "off", so a T
;; put there sails past the (and *cs-dim-layer* ...) guard and dies at
;; the tblsearch behind it.
(defun hs-name (v dflt) (if (= (type v) 'STR) v dflt))

;; A setting NAME as a note says it back: quoted when it is one, and
;; named for what it is when it is not - a note that quotes T as a name
;; reads like a layer somebody forgot to make, rather than a setting
;; nobody can use.
(defun hs-showname (v)
  (if (= (type v) 'STR) (strcat "\"" v "\"") "(not a name)"))

;; T when a prompt that DOES take keywords was answered Back - or its
;; hidden synonym Undo.  getpoint/getdist/getint hand a keyword back as
;; a string where a value would be a list or a number.
(defun hs-back-kw (v)
  (and (= (type v) 'STR) (member v '("Back" "Undo"))))

;; T when a TYPED string means "go back a step" - typed prompts cannot
;; take initget keywords, so there Back is typed like a value.
(defun hs-back-word (s)
  (and s (member (strcase s) '("B" "BACK" "U" "UNDO"))))

;; *cs-tol-inch* expressed in the drawing's units (INSUNITS); inches
;; when the drawing is unitless
(defun hs-autotol ( / iu b)
  (setq iu (getvar "INSUNITS")
        b  (hs-num *cs-tol-inch* 0.125))
  (cond ((= iu 2) (/ b 12.0))     ; feet
        ((= iu 4) (* b 25.4))     ; millimeters
        ((= iu 5) (* b 2.54))     ; centimeters
        ((= iu 6) (* b 0.0254))   ; meters
        (T        b)))            ; inches, or unitless - assume inches

(defun hs-tolerance ( )
  (if (numberp *cs-width-tol*) *cs-width-tol* (hs-autotol)))

;; How far the step-tread dim chain stands off the measuring axis.
(defun hs-dimoff (txth) (* (hs-num *cs-dim-offset* 2.0) txth))

;; How far a step-width dim sits behind the start of the axis: half
;; that step's own width - which is what nests the wider steps further
;; out - plus the standoff on top of it.
(defun hs-nestoff (w txth)
  (+ (* 0.5 w) (* (hs-num *cs-dim-nest* 1.5) txth)))

;; How far the side profile's dims stand off the flight, WIDEST being
;; the widest tread in it.
(defun hs-pgap (txth widest)
  (if (numberp *cs-profile-dimgap*)
    *cs-profile-dimgap*
    (max (* (hs-num *cs-profile-gap-txt* 4.0) txth)
         (* (hs-num *cs-profile-gap-tread* 0.75) widest))))

;; The widest tread, for spacing the side profile's dimensions.  The
;; list is empty when every logged step landed within 1e-6 of the one
;; before it -- (apply 'max nil) is an error, so a degenerate run
;; falls back to plain text-height spacing.  CORNERSTP skips its whole
;; profile in that case (CORNERSTP.lsp, "No usable tread spacing").
(defun hs-maxtread (treads)
  (if treads (apply 'max treads) 0.0))

;; annotation text height in drawing units; DIMSCALE is 0 for
;; annotative dim styles, where the annotation scale governs instead
(defun hs-txth ( / h s)
  (setq h (getvar "DIMTXT")
        s (getvar "DIMSCALE"))
  (if (or (null s) (<= s 0.0))
    (setq s (cond ((and (getvar "CANNOSCALEVALUE")
                        (> (getvar "CANNOSCALEVALUE") 0.0))
                   (/ 1.0 (getvar "CANNOSCALEVALUE")))
                  (1.0))))
  (if (and h (> (* h s) 0.0)) (* h s) 1.0))

;;; ------------------------- drawing helpers ----------------------------

(defun hs-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;; A LINE between two points given in the current UCS.  entmake keeps
;; World, so each end goes through trans on the way in.  The side
;; profile is laid out in the drafter's UCS, where its forced "_V" dims
;; measure - built in World under a turned UCS, every depth read short.
(defun hs-uline (a b)
  (hs-mkline (trans a 1 0) (trans b 1 0)))

;; make dimension style NAME current, but only if it exists and is not
;; already current.  Uses ActiveX so style names containing spaces are
;; handled correctly (the -DIMSTYLE command would read a space as ENTER).
(defun hs-setstyle (name / doc)
  (if (and (hs-name name nil)
           (tblsearch "DIMSTYLE" name)
           (/= (strcase name) (strcase (getvar "DIMSTYLE"))))
    ;; the argument list is required, even for a lambda that takes
    ;; none - without it this is a "too few arguments" error every
    ;; time a style really has to be switched
    (vl-catch-all-apply
      '(lambda ()
         (setq doc (vla-get-activedocument (vlax-get-acad-object)))
         (vla-put-activedimstyle
           doc (vla-item (vla-get-dimstyles doc) name)))
      '())))

;; aligned dimension between A and B in dim style STYLE, dim line
;; passing through THRU.  Points are WCS and are translated to the
;; current UCS for the command.  "_non" defeats running osnap.
(defun hs-dim (style a b thru / oldl)
  (hs-setstyle style)
  (if (and *cs-dim-layer* (cal:layer-usable-p *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.DIMALIGNED" "_non" (trans a 0 1)
                          "_non" (trans b 0 1)
                          "_non" (trans thru 0 1))
  (if oldl (setvar "CLAYER" oldl)))

;; Vertical linear dimension between A and B in dim style STYLE, dim
;; line passing through THRU.  A and B are the real step corners, which
;; run diagonally to each other, so "_V" is forced: the dimension
;; measures the DROP between them while its extension lines still hook
;; the corners themselves.  Cleaner than dimensioning the riser line,
;; which leaves the dim marooned beside the step instead of reading
;; across to it.  Points are UCS, as (command) reads them: "_V" is
;; the UCS Y, so the profile they come from is built in the UCS too.
(defun hs-dimv (style a b thru / oldl)
  (hs-setstyle style)
  (if (and *cs-dim-layer* (cal:layer-usable-p *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.DIMLINEAR" "_non" a
                         "_non" b
                         "_V"
                         "_non" thru)
  (if oldl (setvar "CLAYER" oldl)))

;; entities created since MARK (nil = since the drawing was empty)
(defun hs-since (mark / e out)
  (setq e (if mark (entnext mark) (entnext)))
  (while e (setq out (cons e out) e (entnext e)))
  out)

;;; --------------------------- form answers -----------------------------
;;;
;;;  A form - the Calofin palette, or LAZFORM - can answer some or all
;;;  of HEMISTEP's questions before the run starts.  It leaves them in
;;;  *hs-form* as (key . value) pairs and the question sites look there
;;;  first, so a filled-in sheet drives the whole run and a half-filled
;;;  one simply shortens it.
;;;
;;;  Three states, and the difference between the last two IS the
;;;  feature:
;;;
;;;    key absent      the form did not answer it  -> ask, as usual
;;;    (key . nil)     what Enter means there      -> taken, no prompt
;;;    (key . 24.0)    the form answered it        -> 24.0, no prompt
;;;
;;;  (assoc key ...) tells those apart; (cdr (assoc ...)) alone cannot.
;;;
;;;  THE KEYS.  steps is the STEP COUNT - the one answer the prompts
;;;  never ask for directly: when it is known the tread loop stops
;;;  itself after that many steps instead of waiting for Enter.
;;;  tread1..treadN and width1..widthN feed the per-step prompts (a
;;;  width of nil = what Enter means there: fit to the curve, or
;;;  repeat the previous width in line mode); depth1..depthN and
;;;  depthafter feed the side profile's depths.  wallwidth and crown
;;;  (nil = none, either) answer line mode's two extra distances;
;;;  dims, boundary, profile and bead answer the named questions; a
;;;  keyword is checked against the live prompt's own list and falls
;;;  through to the prompt when it does not fit.  Selections and
;;;  point picks are never form-answered.
;;;
;;;  BEADING IS THREE KEYS, not one.  bead is whether to bead at all,
;;;  beadsides is All/Some/None along the step side walls, and
;;;  beadnums is the step numbers Some asks for, as the string the
;;;  prompt would have taken ("1 3 5").  The whole chain comes off a
;;;  sheet now; the side to bead TOWARD is a pick and stays here.
;;;
;;;  AN ANSWER IS REMOVED AS IT IS USED.  Not marked used - removed.
;;;  Otherwise Back deadlocks: step back onto a form-answered question,
;;;  it answers itself instantly and walks forward again, and there is
;;;  no key the user can press to get out.  The store is cleared on
;;;  both exits from the command, so nothing leaks into the next run.

(setq *hs-form* nil)

;; Did the form answer KEY at all?  This is the absent/nil distinction
;; that (cdr (assoc ...)) throws away.
(defun hs-fhas (key) (if (assoc key *hs-form*) t nil))

;; The form's answer for KEY, removed from the store as it is read.
(defun hs-ftake (key / p)
  (setq p (assoc key *hs-form*))
  (setq *hs-form* (vl-remove p *hs-form*))
  (cdr p))

(defun hs-fclear () (setq *hs-form* nil))

;; The form's numeric answer for KEY, spent as it is read: the number
;; as a REAL (the way getdist hands one back), nil for anything else.
;; Only a POSITIVE number is an answer -- every prompt this stands in
;; for refuses zero and negatives, and a sheet must not talk the run
;; into what the keyboard could not (a tread of -24 drew step 1
;; outside the corner).  POOLSIDE's psd:fnum is the same rule.
(defun hs-fnum (key / v)
  (setq v (hs-ftake key))
  (if (and (numberp v) (> v 0)) (* 1.0 v)))

;; ...and such a number is taken OUT of the store before anything reads
;; it, so the question it answered is ASKED rather than read as the nil
;; hs-fnum would make of it -- nil is Enter, which ends a tread chain,
;; and a sheet's typo is not the drafter saying "done" (STANDARDS 7.5:
;; an invalid value falls through to the prompt).  Every number this
;; form carries is a length or a count and every prompt behind one
;; refuses zero and negatives, so the rule needs no list of keys.
(defun hs-fprune ()
  (setq *hs-form*
        (vl-remove-if '(lambda (pr) (and (numberp (cdr pr)) (<= (cdr pr) 0)))
                      *hs-form*)))

;; The key of a numbered question: (hs-fnkey "tread" 3) -> tread3.
(defun hs-fnkey (stem i) (read (strcat stem (itoa i))))

;; V as the question would spell it, or nil when the question does not
;; accept it at all: an answer the live prompt does not offer falls
;; through to the prompt instead of being handed on to fail later, and
;; the canonical SPELLING comes back, not the caller's, so downstream
;; (= v "No") tests keep working.
(defun hs-fkword (v kws / i n c w out)
  (setq i 1 n (strlen kws) w "" v (strcase v))
  (while (<= i (1+ n))
    (setq c (if (<= i n) (substr kws i 1) " "))
    (if (= c " ")
        (progn
          (if (and (/= w "") (= (strcase w) v)) (setq out w))
          (setq w ""))
        (setq w (strcat w c)))
    (setq i (1+ i)))
  out)

;; The form's keyword answer for KEY against the live list KWS: the
;; canonical keyword, DFLT when the form said nil (what Enter means at
;; every keyword prompt here), or nil when the form did not answer -
;; or answered a word the prompt does not offer - so the caller asks
;; as always.
(defun hs-fkw (key kws dflt / v)
  (if (hs-fhas key)
    (progn
      (setq v (hs-ftake key))
      (cond ((null v) dflt)
            ((and (= (type v) 'STR) (setq v (hs-fkword v kws))) v)))))

;; Run HEMISTEP with a form's answers already in hand.  Nothing
;; happens here that the direct path misses: a caller may equally set
;; *hs-form* itself and call c:HEMISTEP, which is what the tests do.
(defun hs-run-with-answers (answers)
  (setq *hs-form* answers)
  (c:HEMISTEP)
  (hs-fclear)
  (princ))

;;; -------------------- the length ruler --------------------------------
;;;  DIMSTAMP's ruler, as a helper any LENGTH prompt can stand beside.
;;;  Once a first length has been given, the prompt draws the eighths
;;;  of an inch for a whole inch either side of the last one down a
;;;  strip near the right edge of the view, graded like a tape with the
;;;  last length ringed in the middle -- and one prompt then takes a
;;;  click on a row (that row's value), a typed measurement in any
;;;  spelling (44, 44.5, 44-1/2, 4'4.5, 4'-4-1/2"), Enter, a keyword,
;;;  or a click on empty space as the first of two points to measure
;;;  between, which is what getdist always offered.  A run of
;;;  near-equal lengths is clicked rather than typed over and over.
;;;  The fractions are DASHED because the prompt is a getpoint, where
;;;  the spacebar is Enter: 44 1/2 is two answers there, 44 to this
;;;  question and 1/2 to the next, so a bare fraction is refused
;;;  rather than taken as a length of its own.
;;;
;;;  PERPPTS, CPERPPTS, PERPMARK, CORNERSTP, HEMISTEP and NORMIESTEP
;;;  ask their lengths through it.  Each carries this block under its
;;;  own prefix so the standalone file loads alone, the grouped build
;;;  swaps the copy for the library's, and tests/test_ruler_copies.py
;;;  holds every copy to this one text.  DIMSTAMP keeps its own ruler:
;;;  its current row is drawn as the stamp it would make, on the
;;;  stamp's layer in the stamp's style, which is a different thing
;;;  from a row of nearby lengths.
;;;
;;;  A ruler comes in two families, and the prompt picks which.
;;;
;;;  The TAPE is the one above: the eighths of an inch for a whole inch
;;;  either side of the LAST answer, which is what a run of near-equal
;;;  numbers wants.  It needs a last answer to be built round, so the
;;;  first prompt of a run stands alone.
;;;
;;;  The LADDER is the other: a fixed (LO HI STEP) of the values that
;;;  prompt is actually answered with, every one of them offered from
;;;  the first prompt on.  A corner radius is 3" to 2'-0" by 3" and a
;;;  tape of eighths round nothing helps nobody -- 3, 6, 9, 12 is the
;;;  whole vocabulary, and a drafter picks out of it rather than types
;;;  into it.  Its rows are graded off the VALUE, not off a distance
;;;  from the current row: the foot marks are the deep ones and the
;;;  half-foot next, which is where a tape's deep marks are too.  A
;;;  ladder still takes a typed measurement that is not on it, and the
;;;  answer is then ringed among the rungs as the current row.
;;;
;;;  Nothing in here reads a knob.  A tool hands its knobs in as one
;;;  STYLE list and keeps the ruler between prompts as one STATE list:
;;;    STYLE  (COLOR CURRENT-COLOR SCREEN-X ROW-FRAC TXT-FRAC TICK-FRAC
;;;            RING-FRAC REACH) -- a caller's tunables block says what
;;;            each one moves
;;;    STATE  (LEN FEET ENTS BOX ROWS LAY STYLE SAID LADDER) -- the
;;;            length the ruler stands round (nil = none), the family it
;;;            is labelled in (T = feet), what is drawn, its layer, the
;;;            style, whether the one-line hint has been said, and the
;;;            ladder it is standing on (nil = a tape)
;;;  Values are INCHES, the unit this shop draws in, and the ruler
;;;  steps in eighths of one, which is what a tape reads in.

;; The ruler is laid out in the UCS -- VIEWCTR is a UCS point, and so
;; is every click the hit test reads -- and entmake takes the WORLD.
;; So each point goes through trans on its way into the drawing: under
;; a UCS whose origin a drafter has moved to the pool's corner, the
;; ruler was drawn that far away from the view it was measured off,
;; out of sight, while the prompt still answered clicks on the empty
;; strip where it should have been.

;;; -------------------- end of the length ruler -------------------------

;; The shared step settings, in the order the ruler reads them -- each
;; through the same guard every other knob is read through, so a
;; mistyped setting draws the default rather than nothing.
;; Which ruler the next length prompt stands beside: the LADDER while
;; there is no last answer, nothing once there is one.  A tape of
;; eighths is the finer offer and wins wherever it can be built -- a
;; flight's second tread is 24, 24 1/2, 24 -- but it has to be built
;; round something, and the ladder is what stands there until it can be.
(defun hs-ladder (last ladder) (if last nil ladder))

(defun hs-ruler-style ()
  (list (hs-num *cs-ruler-color* 3) (hs-num *cs-ruler-current-color* 7)
        (hs-num *cs-ruler-screen-x* 0.88) (hs-num *cs-ruler-row-frac* 0.042)
        (hs-num *cs-ruler-txt-frac* 0.5) (hs-num *cs-ruler-tick-frac* 0.6)
        (hs-num *cs-ruler-ring-frac* 0.26) (hs-num *cs-ruler-reach* 6.0)))

;;; --------------------------- main command -----------------------------

;; A selection another command hands HEMISTEP -- POOL's shallow-end
;; wall, when a pool is drawn with steps -- through the global
;; *calofin-handoff*, which PADDLE, AUTODIM and TYDRN read the same
;; way.  It holds ("HEMISTEP" SELECTION), is read only here, and is
;; cleared at the read whoever it was for (and by the handler, for a
;; failure before the read), so a handoff never outlives its call.
;; The selection comes back narrowed to what is still in the drawing,
;; or nil -- and nil falls through to the pickfirst probe and the
;; prompt, exactly as a typed HEMISTEP does.
(setq *calofin-handoff* nil)

(defun hs-handed ( / h ss i e)
  (setq h                 *calofin-handoff*
        *calofin-handoff* nil)
  (if (and (listp h) (= (car h) "HEMISTEP") (cadr h))
    (progn
      (setq ss (ssadd) i 0)
      (repeat (sslength (cadr h))
        (setq e (ssname (cadr h) i)
              i (1+ i))
        (if (entget e) (ssadd e ss)))
      (if (< 0 (sslength ss)) ss))))

(defun c:HEMISTEP ( / *error* hs-popstep undoflag ss i en ed et zf
                      lin lp1 lp2 pieces arcs cmode sp spc dir u
                      q hp bscr best side pt inref stopf cum n wid dep
                      p op nat cen e1 e2 drawn tol txth offd pprev
                      oldce oldlay oldstyle ea eb crown pts reflen lastdep
                      dimflag slog mark svcum svp svn svea sveb rec pc oldlu
                      bmark bsides btreads bnums bside bdir bss pr be
                      wallA wallB lastwid kx fx
                      tlist srt treads pv drops dd jx tcount ptop
                      px py totrun totdrop td cnrs pfo pgap fsteps fkey
                      wnoun bstep bmiss s hstep rl rr dflt)

  (defun *error* (msg)
    (setq *calofin-handoff* nil)     ; one never read goes with the run
    (hs-fclear)                     ; both exits clear the form store
    (if undoflag (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if oldstyle (hs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlay (setvar "CLAYER" oldlay))
    (if oldlu (setvar "LUNITS" oldlu))
    (if rl (setq rl (cal:ruler-off rl)))
    (redraw)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nHEMISTEP: " msg)))
    (if lzd:report (lzd:report "HEMISTEP" *hs-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "HEMISTEP" *hs-version*))
  (if lzd:state (lzd:state '(*hs-form*)))
  (hs-fprune)

  ;; remove the most recently drawn step and roll the state back
  (defun hs-popstep ( / e)
    (if (null slog)
      (progn (princ "\n  Already at the first step.") nil)
      (progn
        (setq rec (car slog))
        (foreach e (car rec) (if (and e (entget e)) (entdel e)))
        (setq cum   (nth 1 rec)
              pprev (nth 2 rec)
              n     (nth 3 rec)
              ea    (nth 4 rec)
              eb    (nth 5 rec)
              drawn (1- drawn)
              tlist (cdr tlist)
              slog  (cdr slog))
        (redraw)
        (princ "\n  Stepping back one step.")
        T)))

  ;; ---- 0. environment checks -------------------------------------------
  (princ (strcat "\nHEMISTEP " *hs-version* " - each step tread is measured"
                 " from the previous step."))
  ;; the form's step COUNT, spent here once for the whole run: when it
  ;; is known the tread loop stops itself after that many steps
  (if (hs-fhas 'steps)
    (progn
      (setq fsteps (hs-ftake 'steps))
      (if (not (and (numberp fsteps) (> fsteps 0))) (setq fsteps nil))))
  (setq tol  (hs-tolerance)
        txth (hs-txth))
  ;; Read distances architectural-style for the whole command: a bare
  ;; number is drawing units (inches in an inch-based drawing) and
  ;; feet-inch entry like 1'4 works whatever LUNITS was set to.
  (setq oldlu (getvar "LUNITS"))
  (setvar "LUNITS" 4)
  ;; the length ruler, not up yet: it stands beside the step tread and
  ;; step depth prompts on the current layer, and comes down again
  ;; before any prompt that does not take it and on every way out
  (setq rl (cal:ruler-new (getvar "CLAYER") (hs-ruler-style)))
  (if (not (equal (trans '(0.0 0.0 1.0) 1 0 T) '(0.0 0.0 1.0) 1e-8))
    (princ (strcat "\nWARNING: the current UCS is not parallel to the"
                   " World XY plane - results may be skewed.")))
  (if (not (cal:layer-usable-p (getvar "CLAYER")))
    (princ (strcat "\nWARNING: the current layer (" (getvar "CLAYER")
                   ") is off, frozen or locked - new steps may not"
                   " appear.")))
  (if (zerop (getvar "INSUNITS"))
    (princ (strcat "\nNote: drawing units are unitless; the width"
                   " tolerance is taken as " (rtos tol) ".")))

  ;; ---- 1. selection ----------------------------------------------------
  ;; a selection POOL handed over (its shallow-end wall), else a
  ;; pickfirst selection if there is one, otherwise ask for it
  (setq ss (cond ((hs-handed)) ((ssget "_I" '((0 . "LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE"))))))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
    (progn
      (princ (strcat "\nSelect the base line, the base curve (arc, circle"
                     " or polyline), or the curve plus its axis line:"))
      (setq ss (ssget '((0 . "LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE"))))
      (if lzd:watch (lzd:watch ss) ss)))
  (if (null ss)
    (progn (princ "\nNothing selected.") (exit)))
  (setq i 0)
  (repeat (sslength ss)
    (setq en (ssname ss i)
          ed (entget en)
          et (cdr (assoc 0 ed))
          i  (1+ i))
    (cond
      ((= et "LINE")
       (if lin
         (progn (princ "\nSelect only ONE line.") (exit)))
       (if (> (abs (- (caddr (cdr (assoc 10 ed)))
                      (caddr (cdr (assoc 11 ed))))) 1e-6)
         (setq zf T))
       (setq lin ed
             lp1 (cdr (assoc 10 ed))
             lp2 (cdr (assoc 11 ed))))
      ((= et "ARC")
       (setq pieces (cons (hs-arcpiece en) pieces)))
      ((= et "CIRCLE")
       (setq pieces (cons (list "A" (trans (cdr (assoc 10 ed)) en 0)
                                (cdr (assoc 40 ed)) 0.0 (+ pi pi))
                          pieces)))
      (T
       (setq pieces (append (hs-plpieces en) pieces)))))
  (if zf
    (princ (strcat "\nWARNING: the selected line is not flat (its ends"
                   " differ in Z) - it is used as seen in plan.")))
  (setq arcs  (vl-remove-if-not '(lambda (pc) (= "A" (car pc))) pieces)
        cmode (if arcs T nil))
  (cond
    ((and (null lin) (null pieces))
     (princ "\nSelect a line and/or a curve.") (exit))
    ((and (null cmode) (null lin))
     (princ (strcat "\nNo arc was selected and there is no base line -"
                    " select an arc, a circle, or the base line."))
     (exit))
    ((and (null cmode) pieces)
     (princ (strcat "\nNote: the selected polyline has no arc segments;"
                    " using the line as the base line."))))
  (if lin
    (setq lp1 (list (car lp1) (cadr lp1) 0.0)
          lp2 (list (car lp2) (cadr lp2) 0.0)))

  ;; ---- 2. measuring axis -----------------------------------------------
  ;; SP  = start point of the axis (treads measured from here)
  ;; DIR = direction the steps march (unit)
  ;; U   = direction the step widths run (unit, perpendicular to DIR)
  (cond

    ;; CURVE selected: steps go INTO the curve
    (cmode
     (if lin
       ;; axis line given: start where the line meets the curve, treads
       ;; run along the line, widths perpendicular to it
       (progn
         (setq dir (hs-unit (hs-vec lp1 lp2)))
         (if (null dir)
           (progn (princ "\nThe selected line has zero length.") (exit)))
         ;; prefer a crossing on the drawn segment, then an arc piece,
         ;; then the crossing nearest the line's far end
         (foreach hp (hs-hits lp1 dir pieces)
           (setq bscr (+ (* 1e6 (hs-ptseg (car hp) lp1 lp2))
                         (if (= "A" (car (cdr hp))) 0.0 1e3)
                         (* 1e-3 (distance (car hp) lp2))))
           (if (or (null sp) (< bscr best))
             (setq sp (car hp) spc (cdr hp) best bscr)))
         (if (null sp)
           (progn (princ "\nThe line does not reach the curve.") (exit)))
         (setq inref (if (= "A" (car spc)) (cadr spc)))
         (if inref
           (progn
             (if (< (abs (cal:dot dir (hs-vec sp inref))) 1e-9)
               (progn (princ (strcat "\nThe line is tangent to the curve"
                                     " - cannot tell which way is into it."))
                      (exit)))
             (if (< (cal:dot dir (hs-vec sp inref)) 0.0)
               (setq dir (hs-scl dir -1.0))))
           ;; the line lands on a straight part - ask which way to go
           (progn
             (princ "\nThe line meets a straight part of the curve.")
             (while (null side)
               (setq pt (getpoint (trans sp 0 1)
                          "\nPick a point on the side the steps go: "))
               (if lzd:ask (lzd:ask "\nPick a point on the side the steps go: " pt) pt)
               (if (null pt)
                 (progn (princ "\nNo direction picked - nothing drawn.")
                        (exit)))
               (setq side (cal:dot (hs-vec sp (trans pt 1 0)) dir))
               (if (< (abs side) 1e-10)
                 (progn (princ "\nThat point is square to the line - pick again.")
                        (setq side nil))))
             (if (< side 0.0) (setq dir (hs-scl dir -1.0)))))
         (princ "\nMeasuring from where the line meets the curve, into the curve."))
       ;; no axis line
       (if (= 1 (length arcs))
         ;; a single arc: start at its middle, widths along the tangent
         (progn
           (setq spc (car arcs)
                 sp  (hs-arcpt (cadr spc) (caddr spc)
                               (* 0.5 (+ (cadddr spc) (nth 4 spc))))
                 dir (hs-unit (hs-vec sp (cadr spc))))
           (princ "\nMeasuring from the middle of the arc, into the curve."))
         ;; a composite curve: too many arcs to guess a middle
         (progn
           (while (null sp)
             (setq pt (getpoint
                        "\nPick the point on the curve to measure from: "))
             (if lzd:ask (lzd:ask "\nPick the point on the curve to measure from: " pt) pt)
             (if (null pt)
               (progn (princ "\nNothing picked - nothing drawn.") (exit)))
             (setq pt   (trans pt 1 0)
                   best nil)
             (foreach pc arcs                    ; nearest arc piece
               (setq bscr (abs (- (distance (cadr pc) pt) (caddr pc))))
               (if (or (null best) (< bscr best)) (setq best bscr spc pc)))
             (setq sp  (hs-arcpt (cadr spc) (caddr spc)
                                 (angle (cadr spc) pt))
                   dir (hs-unit (hs-vec sp (cadr spc)))))
           (princ "\nMeasuring from the picked point on the curve, into the curve."))))
     (setq u (hs-unit (hs-perp dir))))

    ;; LINE only: the classic base-line mode
    (T
     (setq sp (hs-mid2 lp1 lp2)
           u  (hs-unit (hs-vec lp1 lp2)))
     (if (null u)
       (progn (princ "\nThe selected line has zero length.") (exit)))
     (while (null dir)
       (setq pt (getpoint (trans sp 0 1)
                          "\nPick a point on the side the steps go: "))
       (if lzd:ask (lzd:ask "\nPick a point on the side the steps go: " pt) pt)
       (if (null pt)
         (progn (princ "\nNo direction picked - nothing drawn.") (exit)))
       (setq side (cal:dot (hs-vec sp (trans pt 1 0)) (hs-perp u)))
       (if (< (abs side) 1e-10)
         (princ "\nThat point is on the line - pick a point to one side.")
         (setq dir (hs-unit (hs-scl (hs-perp u)
                                    (if (< side 0.0) -1.0 1.0))))))))

  ;; preview the measuring axis and the step direction
  (setq reflen (if lin (distance lp1 lp2) (* 2.0 (caddr (car arcs)))))
  (grdraw (trans sp 0 1)
          (trans (hs-add sp (hs-scl dir (* 0.75 reflen))) 0 1) 4 0)
  (grdraw (trans (hs-add sp (hs-scl u (* 0.25 reflen))) 0 1)
          (trans (hs-add sp (hs-scl u (* -0.25 reflen))) 0 1) 2 0)

  ;; ---- 3. dimension the steps?, then the width at the wall -------------
  ;; Two decisions and nothing drawn between them, so they are one chain:
  ;; Back at the width re-asks whether to dimension.  Both are settled
  ;; BEFORE the undo group opens - a question asked inside it could not
  ;; re-open the one in front without a second _Begin.
  ;;
  ;; In base-line mode the first width sits AT the wall: it is the top
  ;; of the run, so no chord is drawn there (the wall already is one),
  ;; but it is dimensioned and it anchors both ends of the boundary.
  ;; In the curve modes the width at the start is set by the curve, so
  ;; the run begins straight away with a step tread.
  (setq hstep 1)
  (while (<= hstep 2)
    (cond
      ((= hstep 1)
       (setq dflt (cond ((hs-kwcanon *cs-dims-default* '("Yes" "No"))) ("Yes")))
       (if (null (setq fkey (hs-fkw 'dims "Yes No" dflt)))
         (progn
           (initget "Yes No")
           (setq fkey (getkword (strcat "\nDimension the steps? [Yes/No] <" dflt ">: ")))
           (if lzd:ask (lzd:ask (getvar "LASTPROMPT") fkey) fkey)
           (if (null fkey) (setq fkey dflt))))
       (setq dimflag (/= "No" fkey))
       (if dimflag
         (progn
           (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
           (if (not (tblsearch "DIMSTYLE" (hs-name *cs-depth-dimstyle* "")))
             (princ (strcat "\nNote: dim style " (hs-showname *cs-depth-dimstyle*)
                            " not found - step treads use the current style.")))
           (if (not (tblsearch "DIMSTYLE" (hs-name *cs-width-dimstyle* "")))
             (princ (strcat "\nNote: dim style " (hs-showname *cs-width-dimstyle*)
                            " not found - step widths use the current style.")))
           (if (and *cs-dim-layer* (not (cal:layer-usable-p *cs-dim-layer*)))
             (princ (strcat "\nNote: dim layer " (hs-showname *cs-dim-layer*)
                            " is missing, not drawable,"
                            " or not a layer name - using the current layer.")))))
       (setq hstep 2))
      ((= hstep 2)
       ;; the curve modes never put this question, so there is nothing
       ;; here to stop on
       (if cmode
         (setq hstep 3)
         (if (hs-fhas 'wallwidth)
           ;; nil = no width at the wall, what Enter means there
           (setq wid   (hs-fnum 'wallwidth)
                 hstep 3)
           (progn
             (initget 6 "Back Undo")
             (setq wid (getdist
                         "\nWidth of the step at the wall [Back] <Enter = none>: "))
             (if lzd:ask (lzd:ask "\nWidth of the step at the wall [Back] <Enter = none>: " wid) wid)
             (if (hs-back-kw wid)
               (progn (princ "\n  Stepping back one question.")
                      (setq wid nil hstep 1))
               (setq hstep 3))))))))

  ;; ---- 4. widths and step treads, chord by chord -----------------------
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undoflag T)))
  (setq cum 0.0 n 1 drawn 0
        pprev sp                        ; tread chain starts at the axis
        offd  (hs-dimoff txth)          ; tread-dim offset off the axis
        oldce (getvar "CMDECHO")
        oldlay (getvar "CLAYER"))
  (setvar "CMDECHO" 0)                  ; quiet the dimstyle/dim commands

  (if (and (not cmode) wid)
    (progn
      (setq wallA   (hs-add sp (hs-scl u (* 0.5 wid)))
            wallB   (hs-add sp (hs-scl u (* -0.5 wid)))
            lastwid wid)
      (if dimflag
        (hs-dim *cs-width-dimstyle* wallA wallB
                (hs-add sp (hs-scl dir (- (hs-nestoff wid txth))))))
      (princ (strcat "\n  Width at the wall: " (rtos wid) "."))))

  (while
    (and (not stopf)
         (progn
           (setq dep 'RETRY)
           (while (eq dep 'RETRY)
             (cond
               ;; the form gave the step COUNT: past it the run stops
               ;; itself - the auto-done no prompt ever offered
               ((and fsteps (> n fsteps)) (setq dep nil))
               ;; this step's tread from the form, spent as it is
               ;; read - a Back onto it re-asks at the keyboard
               ((hs-fhas (hs-fnkey "tread" n))
                (setq dep (hs-fnum (hs-fnkey "tread" n))))
               (T
                ;; Undo is the old keyword, kept as a hidden synonym; the
                ;; length ruler stands round the last tread
                (setq rl  (cal:ruler-show rl lastdep (hs-ladder lastdep *cs-tread-ladder*))
                      rr  (cal:ask-len
                            (strcat "\nStep " (itoa n)
                                    " - step tread [Back"
                                    (if lastdep "/Same" "") "]"
                                    (if lastdep
                                      (strcat " <Enter = done, Same = "
                                              (rtos lastdep) ">: ")
                                      " <Enter = done>: "))
                            (strcat "Back" (if lastdep " Same" "") " Undo")
                            rl nil)
                      dep (car rr)
                      rl  (cadr rr))
                (if (= (type dep) 'STR)
                  (cond
                    ((or (= dep "Back") (= dep "Undo"))
                     (hs-popstep) (setq dep 'RETRY))
                    ((= dep "Same")
                     (if lastdep
                       (setq dep lastdep)
                       (progn (princ "\n  No previous step tread.")
                              (setq dep 'RETRY))))
                    (T (setq dep 'RETRY)))))))
           dep))
    (setq wid 'RETRY)
    (while (eq wid 'RETRY)
      (if (hs-fhas (hs-fnkey "width" n))
        ;; the form's width, spent as it is read; nil reads as Enter -
        ;; fit to the curve, repeat the previous width, or (line mode,
        ;; first step) fall back to the keyboard, its key now spent
        (setq wid (hs-fnum (hs-fnkey "width" n)))
        (progn
          ;; In the curve modes Enter is spoken for - it fits the step to
          ;; the curve - so repeating the last width needs Same (S, per
          ;; STANDARDS section 2).  In base-line mode Enter IS the last
          ;; width, so there is nothing for Same to add and it is not
          ;; offered.
          ;; the ruler is the tread prompt's, not this one's
          (setq rl (cal:ruler-off rl))
          (if (and cmode lastwid) (initget 6 "Same") (initget 6))
          (setq wid (getdist (strcat "\nStep " (itoa n) " - step width "
                                     (cond
                                       (cmode
                                        (strcat
                                          (if lastwid "[Same] " "")
                                          "<Enter = fit to the curve"
                                          (if lastwid
                                            (strcat ", Same = " (rtos lastwid))
                                            "")
                                          ">: "))
                                       (lastwid (strcat "<Enter = "
                                                        (rtos lastwid) ">: "))
                                       (T ": ")))))
          (if lzd:ask (lzd:ask (getvar "LASTPROMPT") wid) wid)
          (if (= (type wid) 'STR) (setq wid lastwid))))
      (if (null wid)
        (cond
          (cmode   (setq wid 'FIT))
          (lastwid (setq wid lastwid))
          (T (princ "\n  A width is needed for this step.")
             (setq wid 'RETRY)))))
    (if (null dep)
      (progn
        (princ "\nNo step tread given - step discarded; finishing.")
        (setq stopf T))
      (progn
        (setq mark (entlast)
              svcum cum svp pprev svn n svea ea sveb eb
              lastdep dep
              ;; each step sits DEP past the PREVIOUS step edge, never
              ;; a running total from the start
              p    (hs-add pprev (hs-scl dir dep))
              e1   nil
              e2   nil)
        (if cmode
          ;; hold as true to the curve as the tolerance allows
          (progn
            (setq op  (hs-open p u pieces)
                  nat (if op (caddr op)))
            (cond
              ;; Enter on width -> fit this step to the curve
              ((eq wid 'FIT)
               (if op
                 (progn
                   (setq e1 (car op) e2 (cadr op))
                   (princ (strcat "\n  Step " (itoa n)
                                  ": fitted to the curve, width = "
                                  (rtos (caddr op)) ".")))
                 (princ (strcat "\n  Step " (itoa n)
                                ": the curve does not reach this distance"
                                " - step skipped."))))
              ((and nat (<= (abs (- nat wid)) tol))
               (setq e1 (car op) e2 (cadr op))
               (princ (strcat "\n  Step " (itoa n) ": curve opening "
                              (rtos nat) " is within " (rtos tol) " of "
                              (rtos wid) " - snapped to the curve.")))
              (T
               ;; center on the curve's opening so the step breaks it
               ;; equally on both sides; on the axis when there is none
               (setq cen (if op (hs-mid2 (car op) (cadr op)) p)
                     e1  (hs-add cen (hs-scl u (* 0.5 wid)))
                     e2  (hs-add cen (hs-scl u (* -0.5 wid))))
               (princ (strcat "\n  Step " (itoa n) ": width " (rtos wid)
                              " held"
                              (if nat
                                (strcat " (curve opening " (rtos nat) ")")
                                " (the curve does not reach this distance)")
                              " - step breaks from the curve.")))))
          ;; classic base-line mode: centered on the axis as given
          (progn
            (setq e1 (hs-add p (hs-scl u (* 0.5 wid)))
                  e2 (hs-add p (hs-scl u (* -0.5 wid))))))
        (if (and e1 e2)
          (progn
            (setq cum (+ cum dep))             ; running total (echo + profile)
            (princ (strcat "\n  Step " (itoa n) ": " (rtos dep)
                           " past the previous step ("
                           (rtos cum) " from the start)."))
            (hs-mkline e1 e2)                  ; the chord (step edge)
            (setq ea (append ea (list e1))     ; remember the ends for
                  eb (append eb (list e2)))    ; the boundary polyline
            (if dimflag
              (progn
                ;; step width: across the chord, nested behind the start
                ;; of the axis by half the chord's own width so the
                ;; wider steps sit progressively further out
                (hs-dim *cs-width-dimstyle* e1 e2
                        (hs-add sp
                                (hs-scl dir
                                        (- (hs-nestoff (distance e1 e2)
                                                       txth)))))
                ;; step tread: chain link along the axis, from the
                ;; previous step edge (the start for step 1) to here
                (hs-dim *cs-depth-dimstyle* pprev p
                        (hs-add (hs-mid2 pprev p) (hs-scl u offd)))))
            (setq pprev p drawn (1+ drawn)
                  lastwid (distance e1 e2)
                  tlist (cons cum tlist)       ; axis distances, newest first
                  slog  (cons (list (hs-since mark) svcum svp svn svea sveb)
                              slog))))
        (setq n (1+ n)))))

  ;; the tread prompts are behind us: the ruler comes down
  (setq rl (cal:ruler-off rl))

  ;; ---- 5. boundary curve through the step ends -------------------------
  ;; The hemisphere is rebuilt as one polyline of arc segments running
  ;; through every step end.  In base-line mode it starts and finishes
  ;; at the wall (the width given at the wall) and bulges out to a crown
  ;; set by one last distance.  In the curve modes the crown is the point
  ;; where the measuring axis meets the selected curve, so the arc
  ;; beside it is fitted through that original point.
  (if (> drawn 0)
    (progn
      (if (not cmode)
        (progn
          (if (hs-fhas 'crown)
            ;; nil = no crown distance, what Enter means there
            (setq dep (hs-fnum 'crown))
            (progn
              (initget 6)
              (setq dep (getdist (strcat "\nDistance from the last step to the back"
                                         " of the curve <Enter = none>: ")))
              (if lzd:ask (lzd:ask (getvar "LASTPROMPT") dep) dep)))
          (if (and dep (= (type dep) 'REAL))
            (progn
              (setq crown (hs-add pprev (hs-scl dir dep)))
              (if dimflag                    ; last link of the tread chain
                (hs-dim *cs-depth-dimstyle* pprev crown
                        (hs-add (hs-mid2 pprev crown)
                                (hs-scl u offd))))))
          ;; wallA - side A - crown - side B - wallB
          (setq pts (append (if wallA (list wallA))
                            ea
                            (if crown (list crown))
                            (reverse eb)
                            (if wallB (list wallB)))
                ;; index of the crown vertex, for the arc fitting
                kx  (if crown
                      (+ (length ea) (if wallA 1 0)))))
        (progn
          (setq dflt (cond ((hs-kwcanon *cs-boundary-default* '("Yes" "No")))
                           ("Yes")))
          (if (null (setq fkey (hs-fkw 'boundary "Yes No" dflt)))
            (progn
              (initget "Yes No")
              (setq fkey (getkword (strcat "\nDraw the reconstructed boundary"
                                           " through the step ends? [Yes/No]"
                                           " <" dflt ">: ")))
              (if lzd:ask (lzd:ask (getvar "LASTPROMPT") fkey) fkey)
              (if (null fkey) (setq fkey dflt))))
          (if (/= "No" fkey)
            ;; Deepest step - side A - across the first step - side B.
            ;; The start point is NOT made a vertex: near the crown the
            ;; curve's opening is narrow, so forcing the boundary through
            ;; it would spike inward whenever the first step is wider
            ;; than the curve there.  Instead the segment spanning the
            ;; first step carries the ORIGINAL curve's own bulge, which
            ;; traces the crown exactly when that step sits on the curve.
            (progn
              (setq pts (append (reverse ea) eb))
              (if (and spc (= "A" (car spc)))
                (setq fx (list (cons (1- (length ea))
                                     (hs-firstspan (car ea) (car eb)
                                                   spc sp)))))))))
      (if (and pts (> (length pts) 1))
        (progn
          (setq bmark (entlast))       ; the boundary is this run's wall
          (hs-mkpoly pts (hs-blgs pts kx fx))
          (setq bsides (hs-since bmark))
          (princ (strcat "\nBoundary polyline drawn through the step ends"
                         (cond ((not cmode)
                                (if wallA ", held to the wall" ""))
                               (T ", held to the original point"))
                         "."))))))

  ;; ---- 6. side profile -------------------------------------------------
  ;; The plan run seen from the side: alternating vertical drops (the
  ;; step depths) and horizontal step treads, drawn in the drafter's
  ;; UCS from a picked top-of-wall point.  Still inside the command's
  ;; UNDO group, and before the entry dim style is restored - the
  ;; profile dims use *cs-depth-dimstyle* too.
  (if (> drawn 0)
    (progn
      ;; what the run starts at, and so what the flight starts at: the
      ;; wall in base-line mode, the curve itself in the curve modes
      (setq wnoun (if cmode "the curve" "the wall"))
      (setq dflt (cond ((hs-kwcanon *cs-profile-default* '("Yes" "No"))) ("Yes")))
      (if (null (setq fkey (hs-fkw 'profile "Yes No" dflt)))
        (progn
          (initget "Yes No")
          (setq fkey (getkword (strcat "\nAdd a side profile? [Yes/No] <" dflt ">: ")))
          (if lzd:ask (lzd:ask (getvar "LASTPROMPT") fkey) fkey)
          (if (null fkey) (setq fkey dflt))))
      (if (/= "No" fkey)
        (progn
          ;; step treads, top step first: sort the logged axis distances
          ;; ascending and take successive differences
          ;; the first difference is measured from zero and filtered
          ;; like every other one -- CORNERSTP and NORMIESTEP both drop
          ;; a sub-1e-6 opener, and an unfiltered seed here let a zero
          ;; through where they would not
          (setq srt    (vl-sort tlist '<)
                treads (if (> (car srt) 1e-6) (list (car srt)))
                pv     (car srt))
          (foreach td (cdr srt)
            (if (> (- td pv) 1e-6)
              (setq treads (append treads (list (- td pv)))))
            (setq pv td))
          (setq tcount (length treads))
          ;; the depths, top step first, with Back (Undo accepted
          ;; too): one per step PLUS one more for the drop after the
          ;; last tread, so 3 steps take 4 depths
          ;; the depths and the pick are one chain: Back at the pick
          ;; re-opens the LAST depth rather than starting the ladder again
          (setq jx 1 drops nil ptop 'RETRY)
          (while (eq ptop 'RETRY)
           (while (<= jx (1+ tcount))
            ;; depth1..depthN and depthafter can come off the form,
            ;; spent as they are read; nil reads as Enter, which the
            ;; first depth refuses - that one falls back to the
            ;; keyboard, its key now spent
            (setq fkey (if (> jx tcount) 'depthafter (hs-fnkey "depth" jx)))
            (setq dd (if (hs-fhas fkey) (hs-fnum fkey) 'RETRY))
            (if (or (eq dd 'RETRY) (and (null dd) (= jx 1)))
              (progn
                ;; Back/Undo hidden at the first depth: typing them only
                ;; gets the already-at-the-first-step feedback.  The
                ;; length ruler stands round the previous depth
                (setq rl (cal:ruler-show rl (car drops)
                                  (hs-ladder (car drops) *cs-drop-ladder*))
                      rr (cal:ask-len
                           (cond
                             ;; the flight starts where the run does, so
                             ;; the first drop is the one AT THE WALL -
                             ;; not step 1's, which is the drop off the
                             ;; tread the wall already gave
                             ((= jx 1)
                              (strcat "\nDepth at " wnoun
                                      " - the drop onto the first tread: "))
                             ((> jx tcount)
                              (strcat "\nDepth after the last tread [Back] <"
                                      (rtos (car drops)) ">: "))
                             (T (strcat "\nStep " (itoa jx)
                                        " - step depth [Back] <"
                                        (rtos (car drops)) ">: ")))
                           "Back Undo" rl nil)
                      dd (car rr)
                      rl (cadr rr))))
            (cond
              ((and (= (type dd) 'STR)
                    (or (= dd "Back") (= dd "Undo")))
               (if (= jx 1)
                 (princ "\n  Already at the first step.")
                 (progn (princ "\n  Stepping back one step.")
                        (setq drops (cdr drops) jx (1- jx)))))
              ((and (null dd) (= jx 1))        ; Enter, nothing to repeat
               (princ "\n  A depth is required."))
              ((null dd)                       ; Enter = same as previous
               (setq drops (cons (car drops) drops) jx (1+ jx)))
              (T
               (setq drops (cons dd drops) jx (1+ jx)))))
           ;; Placement.  The profile always runs DOWN AND TO THE LEFT
           ;; from the pick, so there is no side to ask about.
           ;; the depths are behind us: the ruler comes down before the pick
           (setq rl (cal:ruler-off rl))
           (initget "Back Undo")
           (setq ptop (getpoint (strcat "\nPick the top of " wnoun
                                        " for the side profile [Back]: ")))
           (if lzd:ask (lzd:ask (getvar "LASTPROMPT") ptop) ptop)
           (if (hs-back-kw ptop)
             (progn (princ "\n  Stepping back one step.")
                    (setq drops (cdr drops)
                          jx    (1- jx)
                          ptop  'RETRY))))
          (setq drops (reverse drops))
          (if (null ptop)
            (princ "\nNo point picked - side profile skipped.")
            (progn
              (setq totdrop 0.0 totrun 0.0)
              (foreach dd drops (setq totdrop (+ totdrop dd)))
              (foreach td treads (setq totrun (+ totrun td)))
              ;; The alternating drop/tread silhouette in the
              ;; drafter's UCS, keeping the corner down its high side
              ;; at every level: the pick, then the foot of each drop.
              ;; Those corners are what the dims bind to.  UCS numbers
              ;; throughout, and World only as a line is made: "down
              ;; and to the left" is the drafter's, and the "_V" dims
              ;; measure the drop.  Laid out in World under a UCS
              ;; turned 30 degrees, a 7.5 drop was dimensioned 6.495.
              (setq px   (car ptop)
                    py   (cadr ptop)
                    jx   0
                    cnrs (list (list px py 0.0)))
              (foreach td treads
                (setq dd (nth jx drops))
                (hs-uline (list px py 0.0) (list px (- py dd) 0.0))
                (setq py   (- py dd)
                      cnrs (cons (list px py 0.0) cnrs))
                ;; the tread runs left, and carries no dim of its own -
                ;; the depths and the overall depth say it all
                (hs-uline (list px py 0.0) (list (- px td) py 0.0))
                (setq px (- px td)
                      jx (1+ jx)))
              ;; the last depth: the drop after the last tread
              (setq dd (nth jx drops))
              (hs-uline (list px py 0.0) (list px (- py dd) 0.0))
              (setq py   (- py dd)
                    cnrs (reverse (cons (list px py 0.0) cnrs)))
              (if dimflag
                (progn
                  ;; Every depth dim stands the same distance right of
                  ;; the corner its drop lands on, so the dims climb up
                  ;; and to the right with the steps instead of stacking
                  ;; in one chain.  Clearing the widest tread is what
                  ;; keeps BOTH extension lines running forward, out of
                  ;; the flight; the gap on top of that is what makes
                  ;; the fan readable, and hs-pgap - *cs-profile-dimgap*
                  ;; and the two terms of its default - is what sets it
                  (setq pgap (hs-pgap txth (hs-maxtread treads))
                        pfo  (+ (hs-maxtread treads) pgap)
                        jx   1)
                  (while (< jx (length cnrs))
                    (setq e1 (nth (1- jx) cnrs)
                          e2 (nth jx cnrs))
                    (hs-dimv *cs-depth-dimstyle* e1 e2
                             (list (+ (car e2) pfo)
                                   (* 0.5 (+ (cadr e1) (cadr e2))) 0.0))
                    (setq jx (1+ jx)))
                  ;; the overall depth, further out again - the whole
                  ;; diagonal, top corner to bottom corner
                  (hs-dimv *cs-depth-dimstyle* (car cnrs) (last cnrs)
                           (list (+ (car ptop) pfo pgap)
                                 (- (cadr ptop) (* 0.5 totdrop)) 0.0))))
              (princ (strcat "\nSide profile drawn from " wnoun ": "
                             (itoa tcount)
                             " step(s), " (itoa (length drops))
                             " depths, down to the left; total run "
                             (rtos totrun) ", overall depth "
                             (rtos totdrop) "."))))))))

  ;; ---- 7. done ---------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn)
                   " step(s) drawn, parallel and centered on the axis.")))
  (redraw)
  (if oldstyle (hs-setstyle oldstyle))   ; back to the entry dim style
  ;; close only a group this run opened: in a drawing with UNDO off
  ;; none was, and _End on no group is an error of its own
  (if undoflag
    (progn (command "_.UNDO" "_End")
           (setq undoflag nil)))
  (if oldce (setvar "CMDECHO" oldce))
  (if oldlay (setvar "CLAYER" oldlay))
  (if oldlu (setvar "LUNITS" oldlu))

  ;; ---- 8. bead the steps -----------------------------------------------
  ;; AUTOBEAD does the beading, on its own rules and in its own undo
  ;; group - which is why this sits outside ours: AutoCAD does not nest
  ;; undo groups, so one U undoes the beads and the next undoes the
  ;; steps.  Every tread but the last drawn is beaded - that one closes
  ;; the run and has no riser behind it - so the only question left is
  ;; which steps carry the bead along their side walls, and that is
  ;; answered by step number here instead of by clicking each one.
  (if (> drawn 0)
    (if (not (boundp 'autobead-build))
      (princ (strcat "\nAUTOBEAD is not loaded - APPLOAD AUTOBEAD.lsp"
                     " if you want these steps beaded."))
      (progn
        ;; the bead questions are a chain of their own: which steps,
        ;; which numbers when that answer is Some, and which side to
        ;; bead toward.  Each offers Back and re-opens the one before
        ;; it; Back at the first re-asks whether to bead at all.
        (setq bstep 1)
        (while (<= bstep 4)
          (cond
            ((= bstep 1)
             (setq dflt (cond ((hs-kwcanon *cs-bead-default* '("Yes" "No")))
                              ("Yes")))
             (if (null (setq fkey (hs-fkw 'bead "Yes No" dflt)))
               (progn
                 (initget "Yes No")
                 (setq fkey (getkword (strcat "\nBead the steps? [Yes/No] <" dflt ">: ")))
                 (if lzd:ask (lzd:ask (getvar "LASTPROMPT") fkey) fkey)
                 (if (null fkey) (setq fkey dflt))))
             (setq bstep (if (/= "No" fkey) 2 5)))
            ((= bstep 2)
             (setq btreads (hs-treadents slog)
                   bnums   nil)
             (if (null btreads)
               (progn (princ "\nNo tread lines to bead.") (setq bstep 5))
               (progn
                 ;; every tread but the last is beaded - the side walls
                 ;; are the question, and None leaves them bare
                 ;; the form can answer this one: a sheet that said
                 ;; All or None has nothing left to ask here.  Back is
                 ;; not reachable from a form answer -- there is no
                 ;; prompt to step back from, and the question above it
                 ;; came off the same sheet
                 (setq dflt (cond ((hs-kwcanon *cs-beadsides-default*
                                               '("All" "Some" "None")))
                                  ("All")))
                 (if (null (setq bside (hs-fkw 'beadsides
                                               "All Some None" dflt)))
                   (progn
                     (initget "All Some None Back Undo")
                     (setq bside (cond (((lambda (v) (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v))
                                          (getkword (strcat "\nWhich steps have"
                                                            " beaded side walls?"
                                                            " [All/Some/None/Back]"
                                                            " <" dflt ">: "))))
                                       (dflt)))))
                 (if (member bside '("Back" "Undo"))
                   (progn (princ "\n  Stepping back one question.")
                          (setq bstep 1))
                   (setq bstep 3)))))
            ((= bstep 3)
             (if (/= bside "Some")
               (setq bstep 4)
               (progn
                 (princ (strcat "\n  Steps drawn: " (hs-numsay btreads)))
                 ;; ...and this one, as the string the prompt would
                 ;; have taken: "1 3 5" or "1-3".  Anything that is not
                 ;; a string is no answer at all rather than one the
                 ;; number reader would have to guess at
                 (if (hs-fhas 'beadnums)
                   (progn (setq s (hs-ftake 'beadnums))
                          (if (/= (type s) 'STR) (setq s "")))
                   (progn
                     (setq s (getstring T (strcat "\nStep numbers with"
                                                  " beaded sides (B = back): ")))
                     (if lzd:ask (lzd:ask (getvar "LASTPROMPT") s) s)))
                 (if (hs-back-word s)
                   (progn (princ "\n  Stepping back one question.")
                          (setq bstep 2))
                   (progn
                     (setq bnums (hs-numlist s)
                           bmiss (vl-remove-if
                                   '(lambda (k) (assoc k btreads)) bnums)
                           bnums (vl-remove-if-not
                                   '(lambda (k) (assoc k btreads)) bnums))
                     ;; the steps taken are read back, and a number this
                     ;; run did not draw is named -- both used to be
                     ;; dropped without a word
                     (if bmiss
                       (princ (strcat "\n  Not drawn in this run, left out:"
                                      " step " (hs-numsay bmiss) ".")))
                     (if bnums
                       (progn
                         (princ (strcat "\n  Beading the side walls of step "
                                        (hs-numsay bnums) "."))
                         (setq bstep 4))
                       ;; nothing here names a step drawn.  This used to
                       ;; switch to All and bead EVERY side wall -- the
                       ;; opposite of the Some just given -- so the
                       ;; numbers are asked again (a sheet's answer falls
                       ;; through to the prompt the same way), and B
                       ;; steps back to the question above them.  Numbers
                       ;; read but none of them drawn (bmiss, named just
                       ;; above) are said apart from an answer the reader
                       ;; could not read at all ("1 thru 3"), which is a
                       ;; spelling to fix, not a step that is missing
                       (princ (strcat (cond
                                        ((= s "")
                                         "\n  No step numbers given")
                                        (bmiss
                                         (strcat "\n  \"" s "\" names no"
                                                 " step drawn here"))
                                        (T
                                         (strcat "\n  \"" s "\" could not"
                                                 " be read as step numbers")))
                                      " - type step numbers like 1 3"
                                      " or 1-3, or B to go back."))))))))
            ((= bstep 4)
             (initget "Back Undo")
             (setq bdir (getpoint "\nClick the side to bead toward [Back]: "))
             (if lzd:ask (lzd:ask "\nClick the side to bead toward [Back]: " bdir) bdir)
             (if (hs-back-kw bdir)
               (progn (princ "\n  Stepping back one question.")
                      (setq bstep (if (= bside "Some") 3 2)))
               (progn
                (setq bstep 5)
                (if (null bdir)
                  (princ "\nNo direction picked - nothing beaded.")
                  (progn
                    ;; the treads, anything the run drew for its walls,
                    ;; and the lines it came off: the pool lines of this
                    ;; pocket, which is what AUTOBEAD beads
                    (setq bss (ssadd))
                    (foreach pr btreads (ssadd (cdr pr) bss))
                    (foreach be bsides
                      (if (and be (entget be)) (ssadd be bss)))
                    (setq i 0)
                    (while (< i (sslength ss))
                      (ssadd (ssname ss i) bss)
                      (setq i (1+ i)))
                    (autobead-ensure-layer *autobead-layer*)
                    ;; the store is spent -- the three bead keys were
                    ;; taken above -- and is cleared BEFORE the hand-off:
                    ;; a failure in the build runs only the build's
                    ;; handler and never comes back here, and a key it
                    ;; left standing answered the next typed run
                    (hs-fclear)
                    (autobead-build
                      bss bdir
                      bside
                      (if (= bside "Some")
                        (mapcar '(lambda (k)
                                   (hs-entmid (cdr (assoc k btreads))))
                                bnums)
                        nil)
                      ;; the last step drawn still goes over as a step
                      ;; line - it is a breakline like any other - but
                      ;; it is named here so AUTOBEAD leaves it unbeaded
                      (list (hs-entmid (cdr (last btreads)))))))))))))))
  (hs-fclear)                       ; both exits clear the form store
  (if lzd:end (lzd:end "HEMISTEP"))
  (princ))

;;; --------------------------- tutorial ---------------------------------

(defun hs-tut-pause ( )
  (princ "\n      --- press Enter to continue ---")
  ((lambda (v) (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v))
    (getstring))
  (princ))

(defun hs-tut-text (pt h s)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 s))))

;; Walkthrough for new users: pages of what HEMISTEP does and checks,
;; then a live demonstration drawn step by step with the same geometry
;; code the real command uses - the numbers are the reference example
;; this routine was built against.
(defun c:TUTORIALHEMISTEP ( / *error* undoflag oldce oldlay oldstyle org sp u dir
                              txth pt wallw wallA wallB ea eb pprev p cum
                              e1 e2 offd n lst wid dep crown pts kx)
  (defun *error* (msg)
    (if undoflag (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if oldstyle (hs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlay (setvar "CLAYER" oldlay))
    (if lzd:report (lzd:report "TUTORIALHEMISTEP" *hs-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TUTORIALHEMISTEP" *hs-version*))

  (princ (strcat "\n================ HEMISTEP TUTORIAL " *hs-version*
                 " ================"))
  (princ "\nHEMISTEP draws steps that act like chords inside a circle:")
  (princ "\nparallel step edges centered on a measuring axis, plus the")
  (princ "\nhemisphere boundary itself, rebuilt as one polyline of arc")
  (princ "\nsegments through every step end.")
  (hs-tut-pause)
  (princ "\nWHAT YOU SELECT DECIDES THE MODE")
  (princ "\n  LINE only ....... steps centered on the line, marching away")
  (princ "\n                    from it on the side you pick")
  (princ "\n  CURVE + LINE .... the line is the measuring axis; treads")
  (princ "\n                    start where it meets the curve, going in")
  (princ "\n  CURVE only ...... from the middle of the arc, going in")
  (princ "\n  (a curve may be an arc, circle, or polyline - including a")
  (princ "\n   composite hemisphere and a boundary this command drew)")
  (princ "\nTHE PROMPTS, IN ORDER")
  (princ "\n  1. LINE mode first asks the width of the step AT THE WALL -")
  (princ "\n     it anchors the boundary; no chord is drawn there.")
  (princ "\n  2. Then STEP TREAD, WIDTH, repeating.  Every step tread is")
  (princ "\n     from the previous step - never a running total.  Enter at")
  (princ "\n     a step tread = done; Back steps back one step; Same (S)")
  (princ "\n     repeats.  Enter at a width fits the step to the curve (curve")
  (princ "\n     modes) - Same (S) repeats the previous width there - or")
  (princ "\n     repeats the previous width itself (line mode).")
  (princ "\n  3. One last distance to the back of the curve places the crown,")
  (princ "\n     and the boundary polyline is drawn through the step ends.")
  (princ "\n  4. Finally you may add a SIDE PROFILE, read FROM THE WALL:")
  (princ "\n     the first depth is the drop AT THE WALL and the first")
  (princ "\n     tread the flat between the wall and the first chord.")
  (princ "\n     Give the step depths")
  (princ "\n     (top step first, plus the drop after the last tread, so")
  (princ "\n     3 steps take 4 depths; Back supported), then pick the")
  (princ "\n     top of the WALL.  The flight always runs down and")
  (princ "\n     to the LEFT from there, so the steps rise to the right")
  (princ "\n     and the dims climb with them - each depth beside its own")
  (princ "\n     step, the overall further out; the treads are not dimmed.")
  (princ "\n  5. Bead the steps? [Yes/No] - every tread but the LAST is")
  (princ "\n     beaded (the line that closes the run has no riser), so")
  (princ "\n     the only question is which steps have beaded SIDE")
  (princ "\n     WALLS: [All/Some/None].  Some takes the step numbers")
  (princ "\n     (\"1 3 4\"); None leaves the side walls bare.")
  (princ "\n     Then click the side to bead toward and AUTOBEAD does the")
  (princ "\n     rest on its own rules - it has to be loaded for this.")
  (hs-tut-pause)
  (princ "\nWHAT IT CHECKS AND HANDLES FOR YOU")
  (princ "\n  - warns on tilted UCS / non-flat lines / unusable layer")
  (princ "\n  - bare numbers read as inches; 1'4 style works anywhere")
  (princ "\n  - in the curve modes a width within 1/8\" of the curve's")
  (princ "\n    opening snaps to the curve; any other width is held and")
  (princ "\n    breaks the curve EQUALLY at both ends")
  (princ "\n  - each step measures against whichever part of a composite")
  (princ "\n    curve it lands on, nearest the axis")
  (princ "\n  - the boundary's arcs are fitted so the crown sits inside")
  (princ "\n    ONE arc, and a segment that would fold back is refused")
  (princ "\n  - dims: step treads chained along the axis (STANDARD INCHES),")
  (princ "\n    widths nested behind the start (SIDE STANDARD); one undo")
  (hs-tut-pause)

  (initget "Yes No")
  (if (= "No" ((lambda (v) (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v))
                (getkword (strcat "\nDraw a demonstration in this drawing?"
                                  " [Yes/No] <Yes>: "))))
    (progn (princ "\nTutorial done - type HEMISTEP to use it for real.")
           (exit)))
  (setq pt (getpoint "\nPick a clear spot (about 300 x 150 needed): "))
  (if lzd:ask (lzd:ask "\nPick a clear spot (about 300 x 150 needed): " pt) pt)
  (if (null pt)
    (progn (princ "\nNo spot picked - tutorial done.") (exit)))
  (setq org  (trans pt 1 0)
        txth (hs-txth)
        sp   org                       ; middle of the base line
        u    '(1.0 0.0 0.0)
        dir  '(0.0 1.0 0.0)
        wallw 257.61)
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undoflag T)))
  (setq 
        oldce (getvar "CMDECHO")
        oldlay (getvar "CLAYER")
        oldstyle (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)

  (hs-mkline (hs-add sp (hs-scl u -140.0)) (hs-add sp (hs-scl u 140.0)))
  (hs-tut-text (hs-add org '(-135.0 -14.0 0.0)) (* 1.2 txth)
               "HEMISTEP demo: base-line mode - select this wall line")
  (princ "\n[1] The WALL drawn - in line mode this is all you select.")
  (princ "\n    Steps center on its middle and march off the side you")
  (princ "\n    pick.  The width at the wall here is 257.61 - it anchors")
  (princ "\n    both ends of the boundary but draws no chord.")
  (setq wallA (hs-add sp (hs-scl u (* 0.5 wallw)))
        wallB (hs-add sp (hs-scl u (* -0.5 wallw)))
        offd  (hs-dimoff txth)
        pprev sp
        cum   0.0
        n     1)
  (hs-tut-pause)

  (foreach lst '((240.0 . 13.0) (216.0 . 12.0) (168.0 . 16.0)
                 (120.0 . 10.0))
    (setq wid (car lst)
          dep (cdr lst)
          p   (hs-add pprev (hs-scl dir dep))
          cum (+ cum dep)
          e1  (hs-add p (hs-scl u (* 0.5 wid)))
          e2  (hs-add p (hs-scl u (* -0.5 wid))))
    (hs-mkline e1 e2)
    (setq ea (append ea (list e1))
          eb (append eb (list e2)))
    (hs-dim *cs-width-dimstyle* e1 e2
            (hs-add sp (hs-scl dir (- (hs-nestoff wid txth)))))
    (hs-dim *cs-depth-dimstyle* pprev p
            (hs-add (hs-mid2 pprev p) (hs-scl u offd)))
    (princ (strcat "\n[" (itoa (1+ n)) "] Step " (itoa n) ": width "
                   (rtos wid) ", " (rtos dep) " past the previous edge ("
                   (rtos cum) " from the wall).  Parallel to the wall,"
                   " centered on the axis."))
    (hs-tut-pause)
    (setq pprev p n (1+ n)))

  (setq crown (hs-add pprev (hs-scl dir 9.45)))
  (hs-dim *cs-depth-dimstyle* pprev crown
          (hs-add (hs-mid2 pprev crown) (hs-scl u offd)))
  (setq pts (append (list wallA) ea (list crown) (reverse eb) (list wallB))
        kx  (+ 1 (length ea)))
  (hs-mkpoly pts (hs-blgs pts kx nil))
  (princ "\n[6] One last distance (9.45) places the CROWN, and the boundary")
  (princ "\n    polyline is drawn: wall - step ends - crown - step ends -")
  (princ "\n    wall, in arc segments fitted so the apex sits inside one")
  (princ "\n    arc.  This is the hemisphere the steps sit in.")
  (hs-tut-pause)

  (if oldstyle (hs-setstyle oldstyle))
  (if undoflag                           ; only a group this run opened
    (progn (command "_.UNDO" "_End")
           (setq undoflag nil)))
  (setvar "CMDECHO" oldce)
  (princ "\n[7] Done.  One U removes the demo.  For the curve modes, draw")
  (princ "\n    an arc and run HEMISTEP selecting it (plus an axis line if")
  (princ "\n    you have one) - Enter at any width fits that step to the")
  (princ "\n    curve exactly.")
  (if lzd:end (lzd:end "TUTORIALHEMISTEP"))
  (princ))

(defun c:HEMISTEPVER ()
  (princ (strcat "\nHEMISTEP " *hs-version*))
  (princ))

;;; -------------------- self tests --------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun hs-selftests ()
  (list
    (list "cross is positive for a left turn"
          '(cal:cross '(1.0 0.0 0.0) '(0.0 1.0 0.0))  1.0)
    (list "circum: the circle through (5,1) (2,4) (-1,1) is centred on (2,1)"
          '(hs-circum '(5.0 1.0 0.0) '(2.0 4.0 0.0) '(-1.0 1.0 0.0))  '(2.0 1.0 0.0))
    (list "circum: three points on a line have no circle"
          '(hs-circum '(0.0 0.0 0.0) '(1.0 1.0 0.0) '(2.0 2.0 0.0))  nil)
    (list "segb: a quarter turn counterclockwise is bulge tan 22.5"
          '(hs-segb '(1.0 0.0 0.0) '(0.0 1.0 0.0) '(0.0 0.0 0.0) T)  0.4142136)
    (list "segb: the same ends clockwise go the long way round, bulge -tan 67.5"
          '(hs-segb '(1.0 0.0 0.0) '(0.0 1.0 0.0) '(0.0 0.0 0.0) nil)  -2.4142136)
    (list "bulgemid: a bulge of 1 peaks half a chord to the right of A->B"
          '(hs-bulgemid '(0.0 0.0 0.0) '(2.0 0.0 0.0) 1.0)  '(1.0 -1.0 0.0))
    (list "fit3: three points on the unit circle, counterclockwise"
          '(hs-fit3 '((1.0 0.0 0.0) (0.0 1.0 0.0) (-1.0 0.0 0.0)) 0)
          '((0.0 0.0 0.0) . T))
    (list "blgs: a half circle in three points is two quarter-turn bulges"
          '(hs-blgs '((1.0 0.0 0.0) (0.0 1.0 0.0) (-1.0 0.0 0.0)) nil nil)
          '(0.4142136 0.4142136))
    (list "safeb straightens a bulge past a half circle, and a missing one"
          '(list (hs-safeb 1.5) (hs-safeb -0.5) (hs-safeb nil))  '(0.0 -0.5 0.0))
    (list "open: an r=5 circle opens 10 across its centre"
          '(caddr (hs-open '(0.0 0.0 0.0) '(1.0 0.0 0.0)
                           (list (list "A" '(0.0 0.0 0.0) 5.0 0.0 (* 2.0 pi)))))
          10.0)
    (list "firstspan follows the original arc across the first step"
          '(hs-firstspan '(1.0 0.0 0.0) '(0.0 1.0 0.0)
                         (list "A" '(0.0 0.0 0.0) 1.0 0.0 (* 2.0 pi))
                         '(0.7071 0.7071 0.0))
          0.4142136)
    (list "numlist reads commas, 'and' and a range"
          '(hs-numlist "1, 3 and 5-7")  '(1 3 5 6 7))))

(foreach c '("HEMISTEP" "TUTORIALHEMISTEP")
  (setq *calofin-selftests*
        (cons (cons c 'hs-selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nHEMISTEP.lsp " *hs-version*
                 " loaded - HEMISTEP to draw hemisphere steps,"
                 " TUTORIALHEMISTEP to learn it.")))
(princ)
