;;; ======================================================================
;;; CORNERSTP.lsp
;;; ----------------------------------------------------------------------
;;; Corner step layout routine for swimming-pool corners.
;;; Written for AutoCAD 2018 (plain AutoLISP + ActiveX for dim styles).
;;;
;;; LOAD:     APPLOAD this file (or drag it into the drawing window).
;;; COMMAND:  CORNERSTP
;;;
;;; WHAT IT DOES
;;;   Draws a run of parallel corner steps (tread edges) fanning out from
;;;   a pool corner toward the pool.  Step treads (the plan-view spacing
;;;   of each step) are always held exactly; step widths are held to
;;;   within the width tolerance of the wall opening (1/8" by default).
;;;   The step DEPTH, by contrast, is the vertical drop of a step - it is
;;;   only asked for by the optional side profile at the end of the run.
;;;   A BENCH can ride along one of the two walls (inside out only): you
;;;   say which wall, its offset off that wall, and which step it is
;;;   attached to, and every step past that tread runs to the bench's
;;;   front edge instead of the wall it stands in for.
;;;
;;; WORKFLOW
;;;   1.  Select the two walls that form the corner.  Walls may be LINEs
;;;       or straight segments of a POLYLINE.  A corner diagonal
;;;       (chamfer) or a fillet ARC may be included in the same
;;;       selection.  If more than two straight walls are selected you
;;;       are asked to pick the two you mean.
;;;   2.  If the two walls intersect at a point, that intersection is
;;;       the starting point.
;;;   3.  Choose the draw direction [Inside/Outside]:
;;;         INSIDE OUT (default) - steps are built from the corner out
;;;         toward the pool from given step treads and step widths.
;;;         OUTSIDE IN - the furthest (outermost) step is placed first
;;;         from its given width, bounded to the provided walls, and
;;;         the remaining steps walk back in toward the corner.
;;;
;;;   INSIDE OUT:
;;;   4a. If a diagonal/arc was selected, you are asked whether step
;;;       treads are measured from the Middle of the diagonal/arc or
;;;       from the True corner.  The true corner is found by extending
;;;       the two walls surrounding the diagonal/arc to their apparent
;;;       intersection.
;;;   4b. If a diagonal was selected you are also asked whether the
;;;       treads run Parallel to the diagonal, or perpendicular to the
;;;       bisector of the TRUE ANGLE the walls make (equal angle from
;;;       both walls).  With no diagonal the true-angle bisector is
;;;       always used.  Step treads are measured from the starting
;;;       point toward the pool, square to the treads, so all steps are
;;;       parallel to each other either way.
;;;   4c. For each step you are prompted for the step tread, then the
;;;       step width:
;;;         - The step tread is ALWAYS held exactly.
;;;         - If the wall opening at that distance is within the width
;;;           tolerance of the requested width, the step is trimmed to
;;;           the walls.
;;;         - Otherwise the requested width is held, centered between
;;;           the two walls so the step runs EQUALLY past (or equally
;;;           short of) both walls, and the step breaks away from the
;;;           walls to hold the given dimensions.
;;;         - Enter at the width prompt fits that one step to the walls.
;;;
;;;   OUTSIDE IN:
;;;   5a. If a diagonal was selected you are asked whether the steps
;;;       run Parallel to the diagonal, or with their endpoints
;;;       Equidistant from the true corner (square to the true-angle
;;;       bisector).  With no diagonal, equidistant is always used.
;;;   5b. You give the width of the furthest (outermost) step.  That
;;;       step is bounded to the provided walls, so its width alone
;;;       places it - it is just the starting point.  Each following
;;;       step asks for a step tread (walking back in toward the
;;;       corner), then a step width, under the same rules as inside
;;;       out.  Drawing stops if the corner is reached.
;;;
;;;   6.  You are asked whether to dimension the steps [Yes/No].  If
;;;       Yes, aligned dimensions are added:
;;;         - Step treads are chained along the bisector out from the
;;;           starting point, in dim style "STANDARD INCHES".
;;;         - Step widths are the full width of each tread edge, placed
;;;           just outside the corner and nested so the wider (deeper)
;;;           steps sit progressively further out, in dim style
;;;           "SIDE STANDARD".
;;;       If a style is missing the current style is used and a note is
;;;       printed.
;;;   7.  Inside out you may add a BENCH along one of the walls
;;;       [Yes/No]: pick the wall it sits against, give its offset off
;;;       that wall (its depth), then the step it is attached to.
;;;       Steps up to that one meet the wall as usual; the bench's
;;;       front edge starts on that tread and runs to the far end of
;;;       its wall, capped there, and every later step is bounded by
;;;       the front edge instead of the wall - a fitted width now runs
;;;       wall to bench.  When dimensioning is on the bench's length
;;;       and offset are dimensioned too.
;;;   8.  Enter at a step tread prompt means no more steps are
;;;       required.  Back at a step tread prompt steps back one step:
;;;       it removes the step just drawn (its lines and its dimensions)
;;;       so a mistyped number does not cost the whole run (Undo, the
;;;       old keyword, is still accepted).  Same - typed S - repeats the
;;;       previous step tread, and repeats the previous step WIDTH at the
;;;       width prompt, where Enter is spoken for by "fit to the walls".
;;;       Side (riser) lines are drawn between successive step
;;;       ends whenever the walls do not already close that edge.
;;;   9.  When at least one step was drawn you may add a SIDE PROFILE.
;;;       If Yes, you give the step depths (the vertical drops), top
;;;       step first - one per step PLUS one more for the drop after
;;;       the last tread, so 3 steps take 4 depths.  Enter repeats the
;;;       previous drop, Back (or Undo) steps back.  Then pick the top
;;;       of the first tread: the flight always runs DOWN AND TO THE
;;;       LEFT from there, so there is no side to pick.  See "The side
;;;       profile" below for what is drawn and how it is dimensioned.
;;;     10. Finally, BEAD THE STEPS.  Every tread is beaded - that is the
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
;;;   world X/Y, always descending to the LEFT of the picked top of the
;;;   first tread and ending on the last depth - so the steps rise to
;;;   the right, the way the shop's own elevations read.
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
;;;   while the dim still reads the drop, not the slope.  The offset
;;;   clears the widest tread in the flight, which is what keeps both
;;;   extension lines running forward, out of the steps.
;;;
;;; THE SETTINGS
;;;   Every number this routine can be told to draw differently is a
;;;   setting at the top of the file, under SETTINGS, one per knob with
;;;   what it does and what it defaults to - the width tolerance and the
;;;   inches it is derived from, the two dim styles and the dim layer,
;;;   how far the tread chain stands off the run and how far the width
;;;   dims nest behind it, the nearly-parallel warning, and the side
;;;   profile's dim gap.  setq one before running the command and the
;;;   next run picks it up.  There is nothing to change further down:
;;;   the code reads every one of them through a helper that falls back
;;;   to the shipped default when the value cannot be used.
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
;;;     *CS-FORM*; see "form answers" below.  Selections and point
;;;     picks are always made by hand.
;;; ======================================================================

;;; ------------------------------ SETTINGS ------------------------------
;;;  THE KNOBS, all of them, in one place.  Each is defined only if it
;;;  is not already set, so the three step routines share ONE set of
;;;  settings whichever file loads first and a value set before loading
;;;  them stands.  setq one at the command line - or in acaddoc.lsp -
;;;  and the next run picks it up.
;;;
;;;  Deliberately NOT settings: the epsilons the geometry compares
;;;  against (a point is on a line or it is not), the temporary vectors
;;;  the run previews itself with, the direction the side profile reads
;;;  (down and to the left, the way the shop's elevations do), and the
;;;  bead itself - that is AUTOBEAD's work, on AUTOBEAD's own settings.

;; Step width tolerance, in drawing units: a step whose requested width
;; is within this of the wall opening it lands in is snapped to the
;; walls; any other width is held exactly and breaks away from them.
;; nil = derive it from *cs-tol-inch* through the drawing's INSUNITS.
(if (not (boundp '*cs-width-tol*)) (setq *cs-width-tol* nil))

;; What that tolerance is in INCHES when it is derived - the shop reads
;; it as 1/8".  Raise it to let a wider mismatch still snap to the
;; walls; 0.0 snaps only an exact fit.
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

;; How far the step-tread dim chain stands off the run's axis, in TEXT
;; HEIGHTS - so it tracks DIMSCALE (or the annotation scale) instead of
;; the drawing's size.  2.0 keeps the chain clear of its own text.
(if (not (boundp '*cs-dim-offset*)) (setq *cs-dim-offset* 2.0))

;; How far a step-width dim sits behind the corner, in text heights, on
;; top of half that step's own width.  The half-width is what nests the
;; wider steps progressively further out; this is the gap on top of it.
(if (not (boundp '*cs-dim-nest*)) (setq *cs-dim-nest* 1.5))

;; CORNERSTP only.  The tread chain also clears this fraction of the
;; first step's width, so a wide run does not run its chain through the
;; steps; the larger of it and *cs-dim-offset* wins.
(if (not (boundp '*cs-chain-frac*)) (setq *cs-chain-frac* 0.2))

;; CORNERSTP only.  How close to parallel, in DEGREES, the two selected
;; walls may be before the run says the corner it found is a long way
;; off.  It warns and carries on - it never refuses the selection.
(if (not (boundp '*cs-parallel-tol*)) (setq *cs-parallel-tol* 1.0))

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

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

(setq *cs-version* "v4.5") ; printed on load and at command start so a
                           ; stale APPLOADed copy is easy to spot

;;; ------------------------- vector helpers ----------------------------

(defun cs-dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun cs-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun cs-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun cs-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun cs-len (v) (sqrt (cs-dot v v)))

(defun cs-unit (v / l)
  (if (> (setq l (cs-len v)) 1e-10) (cs-scl v (/ 1.0 l))))

(defun cs-perp90 (v) (list (- (cadr v)) (car v) 0.0))

(defun cs-mid2 (a b) (list (* 0.5 (+ (car a) (car b)))
                           (* 0.5 (+ (cadr a) (cadr b)))
                           0.0))

;; perpendicular distance from point P to the infinite line through A-B
(defun cs-ptline (p a b / d)
  (setq d (cs-unit (cs-vec a b)))
  (if d
    (abs (- (* (car d) (- (cadr p) (cadr a)))
            (* (cadr d) (- (car p) (car a)))))
    (distance p a)))

;; distance from point P to the SEGMENT A-B
(defun cs-ptseg (p a b / d l2 t2)
  (setq d  (cs-vec a b)
        l2 (cs-dot d d))
  (if (< l2 1e-20)
    (distance p a)
    (progn
      (setq t2 (/ (cs-dot (cs-vec a p) d) l2))
      (cond ((< t2 0.0) (distance p a))
            ((> t2 1.0) (distance p b))
            (T (distance p (cs-add a (cs-scl d t2))))))))

;; how far point P lies beyond the ends of segment A-B (0.0 when on it)
(defun cs-beyond (p a b / d l t2)
  (setq d (cs-vec a b)
        l (cs-len d))
  (if (< l 1e-10)
    (distance p a)
    (progn
      (setq t2 (/ (cs-dot (cs-vec a p) d) (* l l)))
      (cond ((< t2 0.0) (* (- t2) l))
            ((> t2 1.0) (* (- t2 1.0) l))
            (T 0.0)))))

;; endpoint of wall/segment record LN farther from PT
(defun cs-far (ln pt)
  (if (> (distance (car ln) pt) (distance (cadr ln) pt)) (car ln) (cadr ln)))

;; point on a circle: center C, radius R, angle A
(defun cs-arcpt (c r a)
  (list (+ (car c) (* r (cos a))) (+ (cadr c) (* r (sin a))) 0.0))

;; T when angle A lies on the counterclockwise span A1 -> A2
(defun cs-inspan (a a1 a2 / e)
  (setq e (- a2 a1))
  (if (< e 0.0) (setq e (+ e pi pi)))
  (setq a (- a a1))
  (if (< a 0.0) (setq a (+ a pi pi)))
  (<= a (+ e 1e-9)))

;;; --------------------- geometry from entities ------------------------

;; Normalized arc record (center radius startang endang) in WCS, always
;; counterclockwise with endang > startang.  Built from the curve's own
;; start/mid/end points so mirrored arcs and OCS offsets are handled.
(defun cs-arcdata (en / ed c r sp ep mp a1 a2 sw)
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
  (if (not (cs-inspan (angle c mp) a1 a2))   ; wrong way round
    (setq sw a1 a1 a2 a2 sw))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list c r a1 a2))

;; Normalized arc record for a polyline bulge segment P1 -> P2
(defun cs-bulgearc (p1 p2 b / th l r h nrm cen a1 a2)
  (setq th  (* 4.0 (atan b))                  ; signed included angle
        l   (distance p1 p2)
        r   (abs (/ l (* 2.0 (sin (/ th 2.0)))))
        h   (* r (cos (/ (abs th) 2.0)))
        nrm (cs-unit (cs-perp90 (cs-vec p1 p2)))
        cen (cs-add (cs-mid2 p1 p2)
                    (cs-scl nrm (if (> b 0.0) h (- h)))))
  (if (> b 0.0)
    (setq a1 (angle cen p1) a2 (angle cen p2))
    (setq a1 (angle cen p2) a2 (angle cen p1)))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list cen r a1 a2))

;; Segments of a POLYLINE as records (p1 p2 bulge ename index).
;; Points are brought to WCS.  Handles LWPOLYLINE and old 2D POLYLINE.
(defun cs-plsegs (en / ed el cl vs bs i m out v1 v2 b sub pr)
  (setq ed (entget en)
        el (cond ((cdr (assoc 38 ed))) (0.0))
        cl (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))))
  (if (= "LWPOLYLINE" (cdr (assoc 0 ed)))
    (foreach pr ed                              ; walk 10/42 pairs in order
      (cond
        ((= 10 (car pr))
         (setq vs (cons (trans (list (car (cdr pr)) (cadr (cdr pr)) el) en 0) vs)
               bs (cons 0.0 bs)))
        ((= 42 (car pr))
         (if bs (setq bs (cons (cdr pr) (cdr bs)))))))
    (progn                                      ; heavy 2D polyline
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
      (setq out (cons (list v1 v2 b en i) out)))
    (setq i (1+ i)))
  (reverse out))

;; nearest record in SEGS to point PT
(defun cs-nearseg (segs pt / best bd d s)
  (foreach s segs
    (setq d (cs-ptseg pt (car s) (cadr s)))
    (if (or (null best) (< d bd)) (setq best s bd d)))
  best)


;;; --------------------------- bead helpers -----------------------------

;; The step numbers typed at a prompt - "1 3 4", "1,3,4" and "1, 3 and 4"
;; all read the same.  Anything that is not a digit separates.
(defun cs-numlist (str / out tok i c)
  (setq out '() tok "" i 0)
  (while (<= i (strlen str))
    (setq c (if (< i (strlen str)) (substr str (1+ i) 1) " "))
    (if (and (>= (ascii c) 48) (<= (ascii c) 57))
      (setq tok (strcat tok c))
      (progn
        (if (/= tok "") (setq out (cons (atoi tok) out)))
        (setq tok "")))
    (setq i (1+ i)))
  (reverse out))

;; The tread line of every step that was committed, as
;; (step-number . ename).  A step's log record carries its entities
;; first and its step number at index 6, and the only LINE among
;; those entities is its tread - any dimension beside it is a DIMENSION.
(defun cs-treadents (log / out rec e ln)
  (setq out '())
  (foreach rec log
    (setq ln nil)
    ;; ...-since lists newest first, and a step draws its tread before
    ;; any side line or dimension, so the LAST line seen is the tread
    (foreach e (car rec)
      (if (and e (entget e)
               (= "LINE" (cdr (assoc 0 (entget e)))))
        (setq ln e)))
    (if ln (setq out (cons (cons (nth 6 rec) ln) out))))
  ;; the log runs newest first, so consing through it already leaves
  ;; the pairs in step order - lowest first, the way they were drawn
  out)

;; The side (riser) lines the run drew: every LINE in the log that is
;; not its step's tread.  CORNERSTP closes a step edge with one only
;; when the walls do not already close it, so most runs have none.
(defun cs-sideents (log / out rec e ln lines)
  (setq out '())
  (foreach rec log
    (setq lines '() ln nil)
    (foreach e (car rec)
      (if (and e (entget e)
               (= "LINE" (cdr (assoc 0 (entget e)))))
        (setq lines (cons e lines) ln e)))    ; ln ends on the tread
    (foreach e lines
      (if (not (eq e ln)) (setq out (cons e out)))))
  out)

;; The step numbers on offer, as "1, 2, 3" - so the numbers prompt can
;; be answered without scrolling back through the run.
(defun cs-numsay (pairs / out pr)
  (setq out "")
  (foreach pr pairs
    (setq out (strcat out (if (= out "") "" ", ") (itoa (car pr)))))
  out)

;; Midpoint (WCS) of a LINE entity.
(defun cs-entmid (e / ed)
  (setq ed (entget e))
  (cs-mid2 (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))

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
(defun cs-num (v dflt) (if (numberp v) v dflt))

;; T when a prompt that DOES take keywords was answered Back - or its
;; hidden synonym Undo.  getpoint/getdist/getint hand a keyword back as
;; a string where a value would be a list or a number.
(defun cs-back-kw (v)
  (and (= (type v) 'STR) (member v '("Back" "Undo"))))

;; T when a TYPED string means "go back a step" - typed prompts cannot
;; take initget keywords, so there Back is typed like a value.
(defun cs-back-word (s)
  (and s (member (strcase s) '("B" "BACK" "U" "UNDO"))))

;; *cs-tol-inch* expressed in the drawing's units (INSUNITS); inches
;; when the drawing is unitless
(defun cs-autotol ( / iu b)
  (setq iu (getvar "INSUNITS")
        b  (cs-num *cs-tol-inch* 0.125))
  (cond ((= iu 2) (/ b 12.0))     ; feet
        ((= iu 4) (* b 25.4))     ; millimeters
        ((= iu 5) (* b 2.54))     ; centimeters
        ((= iu 6) (* b 0.0254))   ; meters
        (T        b)))            ; inches, or unitless - assume inches

(defun cs-tolerance ( )
  (if (numberp *cs-width-tol*) *cs-width-tol* (cs-autotol)))

;; The nearly-parallel warning threshold in RADIANS, which is what the
;; angle test has; the setting is in degrees, which is how a drafter
;; reads it.
(defun cs-partol ( ) (* pi (/ (cs-num *cs-parallel-tol* 1.0) 180.0)))

;; How far the step-tread dim chain stands off the run's axis.
(defun cs-dimoff (txth) (* (cs-num *cs-dim-offset* 2.0) txth))

;; How far a step-width dim sits behind the corner: half that step's
;; own width - which is what nests the wider steps further out - plus
;; the standoff on top of it.
(defun cs-nestoff (w txth)
  (+ (* 0.5 w) (* (cs-num *cs-dim-nest* 1.5) txth)))

;; The tread chain's standoff off the bisector, which also clears a
;; fraction of the first step's width so a wide run keeps its chain out
;; of the steps.
(defun cs-chainoff (w txth)
  (max (cs-dimoff txth) (* (cs-num *cs-chain-frac* 0.2) w)))

;; How far the side profile's dims stand off the flight, WIDEST being
;; the widest tread in it.
(defun cs-pgap (txth widest)
  (if (numberp *cs-profile-dimgap*)
    *cs-profile-dimgap*
    (max (* (cs-num *cs-profile-gap-txt* 4.0) txth)
         (* (cs-num *cs-profile-gap-tread* 0.75) widest))))

;; annotation text height in drawing units; DIMSCALE is 0 for
;; annotative dim styles, where the annotation scale governs instead
(defun cs-txth ( / h s)
  (setq h (getvar "DIMTXT")
        s (getvar "DIMSCALE"))
  (if (or (null s) (<= s 0.0))
    (setq s (cond ((and (getvar "CANNOSCALEVALUE")
                        (> (getvar "CANNOSCALEVALUE") 0.0))
                   (/ 1.0 (getvar "CANNOSCALEVALUE")))
                  (1.0))))
  (if (and h (> (* h s) 0.0)) (* h s) 1.0))

;;; ------------------------- drawing helpers ---------------------------

(defun cs-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;; make dimension style NAME current, but only if it exists and is not
;; already current.  Uses ActiveX so style names containing spaces are
;; handled correctly (the -DIMSTYLE command would read a space as ENTER).
(defun cs-setstyle (name / doc)
  (if (and (tblsearch "DIMSTYLE" name)
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

;; T when layer NAME exists and can be drawn on right now
(defun cs-layerok (name / ld f cl)
  (if (setq ld (tblsearch "LAYER" name))
    (progn
      (setq f  (cond ((cdr (assoc 70 ld))) (0))
            cl (cond ((cdr (assoc 62 ld))) (7)))
      (and (zerop (logand 1 f))                  ; not frozen
           (zerop (logand 4 f))                  ; not locked
           (> cl 0)))))                          ; not off

;; aligned dimension between A and B in dim style STYLE, dim line
;; passing through THRU.  Points are WCS and are translated to the
;; current UCS for the command.  "_non" defeats running osnap.
(defun cs-dim (style a b thru / oldl)
  (cs-setstyle style)
  (if (and *cs-dim-layer* (cs-layerok *cs-dim-layer*))
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
;; across to it.  Points are WCS.
(defun cs-dimv (style a b thru / oldl)
  (cs-setstyle style)
  (if (and *cs-dim-layer* (cs-layerok *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.DIMLINEAR" "_non" (trans a 0 1)
                         "_non" (trans b 0 1)
                         "_V"
                         "_non" (trans thru 0 1))
  (if oldl (setvar "CLAYER" oldl)))

;; Draw the side (riser) line A-B unless it is degenerate or both points
;; already lie along the same wall (the wall provides that edge).
(defun cs-conn (a b w1 w2)
  (if (and a b (> (distance a b) 1e-8)
           (not (and (< (cs-ptline a (car w1) (cadr w1)) 1e-6)
                     (< (cs-ptline b (car w1) (cadr w1)) 1e-6)))
           (not (and (< (cs-ptline a (car w2) (cadr w2)) 1e-6)
                     (< (cs-ptline b (car w2) (cadr w2)) 1e-6))))
    (cs-mkline a b)))

;; entities created since MARK (nil = since the drawing was empty)
(defun cs-since (mark / e out)
  (setq e (if mark (entnext mark) (entnext)))
  (while e (setq out (cons e out) e (entnext e)))
  out)

;; Resolve a step's endpoints from the requested width WID (nil = fit
;; to the walls), the wall hits H1/H2 with opening NAT, the position P
;; on the measuring ray, and the tread direction PERP.  Returns the
;; list (e1 e2), or nil when the step must be skipped.  A width within
;; TOL of the wall opening is trimmed to the walls; any other width is
;; held, centered on the wall opening so the step runs equally past (or
;; equally short of) both walls.
(defun cs-resolve (wid nat h1 h2 p perp n tol / u cen e1 e2)
  (cond
    ;; Enter on width -> fit this step to the walls
    ((null wid)
     (if nat
       (progn
         (princ (strcat "\n  Step " (itoa n) ": fitted to walls, width = "
                        (rtos nat) "."))
         (list h1 h2))
       (progn
         (princ (strcat "\n  Step " (itoa n)
                        ": cannot reach both walls here - step skipped."))
         nil)))
    ;; requested width within tolerance of the wall opening -> trim
    ((and nat (<= (abs (- nat wid)) tol))
     (princ (strcat "\n  Step " (itoa n) ": wall opening " (rtos nat)
                    " is within " (rtos tol) " of " (rtos wid)
                    " - fitted to walls."))
     (list h1 h2))
    ;; otherwise hold the exact width; the step breaks from the walls
    (T
     (if nat
       (setq u   (cs-unit (cs-vec h2 h1))
             cen (cs-mid2 h1 h2)
             e1  (cs-add cen (cs-scl u (* 0.5 wid)))
             e2  (cs-add cen (cs-scl u (* -0.5 wid))))
       ;; no wall opening here - fall back to the measuring ray
       (setq e1 (cs-add p (cs-scl perp (* 0.5 wid)))
             e2 (cs-add p (cs-scl perp (* -0.5 wid)))))
     (princ (strcat "\n  Step " (itoa n) ": width " (rtos wid) " held"
                    (if nat (strcat " (wall opening " (rtos nat) ")") "")
                    " - step breaks from the walls."))
     (list e1 e2))))

;;; --------------------------- form answers -----------------------------
;;;
;;;  A form - the Calofin palette, or LAZFORM - can answer some or all
;;;  of CORNERSTP's questions before the run starts.  It leaves them in
;;;  *cs-form* as (key . value) pairs and the question sites look there
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
;;;  width of nil = fit to the walls, what Enter means there);
;;;  depth1..depthN and depthafter feed the side profile's depths.
;;;  direction, measure, treadmode, dims, bench, benchoffset,
;;;  benchstep, outerwidth, profile and bead answer the named
;;;  questions; a keyword is checked against the live prompt's own
;;;  list and falls through to the prompt when it does not fit.
;;;  Selections and point picks are never form-answered.
;;;
;;;  AN ANSWER IS REMOVED AS IT IS USED.  Not marked used - removed.
;;;  Otherwise Back deadlocks: step back onto a form-answered question,
;;;  it answers itself instantly and walks forward again, and there is
;;;  no key the user can press to get out.  The store is cleared on
;;;  both exits from the command, so nothing leaks into the next run.

(setq *cs-form* nil)

;; Did the form answer KEY at all?  This is the absent/nil distinction
;; that (cdr (assoc ...)) throws away.
(defun cs-fhas (key) (if (assoc key *cs-form*) t nil))

;; The form's answer for KEY, removed from the store as it is read.
(defun cs-ftake (key / p)
  (setq p (assoc key *cs-form*))
  (setq *cs-form* (vl-remove p *cs-form*))
  (cdr p))

(defun cs-fclear () (setq *cs-form* nil))

;; The form's numeric answer for KEY, spent as it is read: the number
;; as a REAL (the way getdist hands one back), nil for anything else.
(defun cs-fnum (key / v)
  (setq v (cs-ftake key))
  (if (numberp v) (* 1.0 v)))

;; The key of a numbered question: (cs-fnkey "tread" 3) -> tread3.
(defun cs-fnkey (stem i) (read (strcat stem (itoa i))))

;; V as the question would spell it, or nil when the question does not
;; accept it at all: an answer the live prompt does not offer falls
;; through to the prompt instead of being handed on to fail later, and
;; the canonical SPELLING comes back, not the caller's, so downstream
;; (= key "Outside") tests keep working.
(defun cs-fkword (v kws / i n c w out)
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
(defun cs-fkw (key kws dflt / v)
  (if (cs-fhas key)
    (progn
      (setq v (cs-ftake key))
      (cond ((null v) dflt)
            ((and (= (type v) 'STR) (setq v (cs-fkword v kws))) v)))))

;; Run CORNERSTP with a form's answers already in hand.  Nothing
;; happens here that the direct path misses: a caller may equally set
;; *cs-form* itself and call c:CORNERSTP, which is what the tests do.
(defun cs-run-with-answers (answers)
  (setq *cs-form* answers)
  (c:CORNERSTP)
  (cs-fclear)
  (princ))

;;; --------------------------- main command ----------------------------

(defun c:CORNERSTP ( / *error* cs-popstep undoflag ss i en ed et zf
                       straights arcrecs lines diag arcr cand o1 o2
                       score best j k tmp w1 w2 corner ang c r a1 a2
                       mid key start d1 d2 bis perp reflen tol txth
                       dist n drawn dep wid p h1 h2 nat e1 e2 bey
                       prevL prevR dimflag w offd oldce oldlay oldstyle oldlu
                       outflag stopf op1 pprev tout tprev lastdep
                       slog mark svdist svl svr svp svt svn s
                       bsides btreads bnums bside bdir bss pr be
                       bnw bno bnk bnsd bnrm bnf bnpe bact bu1 bu2
                       bns bnfar bnff bnl
                       tlist tvals tds drops pd ix ppt pw
                       px py totr totd cnrs ca cb pfo pgap fsteps fkey
                       qstep qdir bstep lastwid)

  (defun *error* (msg)
    (cs-fclear)                     ; both exits clear the form store
    (if undoflag (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if oldstyle (cs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlay (setvar "CLAYER" oldlay))
    (if oldlu (setvar "LUNITS" oldlu))
    (redraw)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCORNERSTP: " msg)))
    (if lzd:report (lzd:report "CORNERSTP" *cs-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CORNERSTP" *cs-version*))

  ;; remove the most recently drawn step and roll the state back
  (defun cs-popstep ( / rec e)
    (cond
      ((null slog) (princ "\n  Already at the first step.") nil)
      ((and outflag (= 1 (length slog)))
       (princ (strcat "\n  The outermost step sets the layout - restart"
                      " the command to change its width."))
       nil)
      (T
       (setq rec (car slog))
       (foreach e (car rec) (if (and e (entget e)) (entdel e)))
       (setq dist  (nth 1 rec)
             prevL (nth 2 rec)
             prevR (nth 3 rec)
             pprev (nth 4 rec)
             tprev (nth 5 rec)   ; outside-in walks from here again
             n     (nth 6 rec)
             drawn (1- drawn)
             slog  (cdr slog)
             tlist (cdr tlist))
       (redraw)                  ; clear the erased step from the screen
       (princ "\n  Stepping back one step.")
       T)))

  ;; ---- 0. environment checks ------------------------------------------
  (princ (strcat "\nCORNERSTP " *cs-version*))
  ;; the form's step COUNT, spent here once for the whole run: when it
  ;; is known the tread loop stops itself after that many steps
  (if (cs-fhas 'steps)
    (progn
      (setq fsteps (cs-ftake 'steps))
      (if (not (and (numberp fsteps) (> fsteps 0))) (setq fsteps nil))))
  (setq tol  (cs-tolerance)
        txth (cs-txth))
  ;; Read distances architectural-style for the whole command: a bare
  ;; number is drawing units (inches in an inch-based drawing) and
  ;; feet-inch entry like 1'4 works whatever LUNITS was set to.
  (setq oldlu (getvar "LUNITS"))
  (setvar "LUNITS" 4)
  (if (not (equal (trans '(0.0 0.0 1.0) 1 0 T) '(0.0 0.0 1.0) 1e-8))
    (princ (strcat "\nWARNING: the current UCS is not parallel to the"
                   " World XY plane - results may be skewed."))
    (if (not (equal (trans '(0.0 0.0 0.0) 1 0) '(0.0 0.0 0.0) 1e-8))
      (princ "\nNote: a shifted/rotated UCS is in use; dimensions are placed to match.")))
  (if (not (cs-layerok (getvar "CLAYER")))
    (princ (strcat "\nWARNING: the current layer (" (getvar "CLAYER")
                   ") is off, frozen or locked - new steps may not"
                   " appear.")))
  (if (zerop (getvar "INSUNITS"))
    (princ (strcat "\nNote: drawing units are unitless; the width"
                   " tolerance is taken as " (rtos tol) ".")))

  ;; ---- 1. selection ---------------------------------------------------
  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I" '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE"))))
  (if lzd:watch (lzd:watch ss))
  (if (null ss)
    (progn
      (princ "\nSelect the two walls forming the corner ")
      (princ "(a corner diagonal or fillet arc may be included):")
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE"))))
      (if lzd:watch (lzd:watch ss))))
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
       (if (> (abs (- (caddr (cdr (assoc 10 ed)))
                      (caddr (cdr (assoc 11 ed))))) 1e-6)
         (setq zf T))
       (setq straights (cons (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))
                                   0.0 en nil)
                             straights)))
      ((= et "ARC")
       (setq arcrecs (cons (cs-arcdata en) arcrecs)))
      (T                                        ; polyline: take segments
       (foreach s (cs-plsegs en)
         (if (equal 0.0 (caddr s) 1e-9)
           (setq straights (cons s straights))
           (setq arcrecs (cons (cs-bulgearc (car s) (cadr s) (caddr s))
                               arcrecs)))))))
  (setq straights (reverse straights))
  (if zf
    (princ (strcat "\nWARNING: a selected line is not flat (its ends"
                   " differ in Z) - it is used as seen in plan.")))

  ;; drop duplicates of the same wall
  (setq tmp nil)
  (foreach s straights
    (if (not (vl-some '(lambda (q)
                         (or (and (equal (car s) (car q) 1e-8)
                                  (equal (cadr s) (cadr q) 1e-8))
                             (and (equal (car s) (cadr q) 1e-8)
                                  (equal (cadr s) (car q) 1e-8))))
                      tmp))
      (setq tmp (cons s tmp))))
  (setq straights (reverse tmp))

  ;; ---- 2. sort out walls / diagonal / fillet --------------------------
  (cond
    ((< (length straights) 2)
     (princ "\nSelect at least two straight walls forming the corner.")
     (exit))

    ;; two walls, optionally with a fillet arc
    ((= (length straights) 2)
     (setq lines straights
           arcr  (car arcrecs)))

    ;; three walls: the diagonal is the one whose ends sit closest to
    ;; the other two
    ((= (length straights) 3)
     (setq best 1e99 j 0 k 0)
     (repeat 3
       (setq cand  (nth k straights)
             o1    (nth (rem (+ k 1) 3) straights)
             o2    (nth (rem (+ k 2) 3) straights)
             score (+ (min (cs-ptline (car cand)  (car o1) (cadr o1))
                           (cs-ptline (car cand)  (car o2) (cadr o2)))
                      (min (cs-ptline (cadr cand) (car o1) (cadr o1))
                           (cs-ptline (cadr cand) (car o2) (cadr o2)))))
       (if (< score best) (setq best score j k))
       (setq k (1+ k)))
     (setq diag  (nth j straights)
           lines (list (nth (rem (+ j 1) 3) straights)
                       (nth (rem (+ j 2) 3) straights))))

    ;; more than three: too many to guess - let the user point them out
    (T
     (princ (strcat "\n" (itoa (length straights))
                    " straight walls were selected."))
     (while (null w2)
       (while (null w1)
         (setq tmp (getpoint "\nPick the FIRST wall of the corner: "))
         (if (null tmp) (progn (princ "\nNothing picked.") (exit)))
         (setq w1 (cs-nearseg straights (trans tmp 1 0))))
       ;; the second pick only means anything beside the first, so Back
       ;; here re-asks the first rather than ending the command
       (initget "Back Undo")
       (setq tmp (getpoint "\nPick the SECOND wall of the corner [Back]: "))
       (cond
         ((cs-back-kw tmp)
          (princ "\n  Stepping back one question.")
          (setq w1 nil))
         ((null tmp) (princ "\nNothing picked.") (exit))
         (T
          (setq w2 (cs-nearseg straights (trans tmp 1 0)))
          (if (equal w1 w2) (progn (princ "\nThat is the same wall.")
                                   (setq w2 nil))))))
     (setq lines (list w1 w2))
     ;; a straight segment sitting between the two picked walls on the
     ;; same polyline is the chamfer; otherwise look for a fillet arc
     (foreach s straights
       (if (and (null diag)
                (not (equal s w1)) (not (equal s w2))
                (nth 4 s) (nth 4 w1) (nth 4 w2)
                (eq (nth 3 s) (nth 3 w1)) (eq (nth 3 s) (nth 3 w2))
                (= 2 (abs (- (nth 4 w1) (nth 4 w2))))
                (= (nth 4 s) (/ (+ (nth 4 w1) (nth 4 w2)) 2)))
         (setq diag s)))
     (setq arcr (if diag nil (car arcrecs)))))

  (setq w1 (car lines)
        w2 (cadr lines))

  ;; ---- 3. true corner = apparent intersection of the walls -----------
  (setq corner (inters (car w1) (cadr w1) (car w2) (cadr w2) nil))
  (if (null corner)
    (progn (princ "\nThe two walls are parallel - no corner found.")
           (exit)))
  (setq ang (abs (- (angle (car w1) (cadr w1)) (angle (car w2) (cadr w2)))))
  (while (> ang pi) (setq ang (- ang pi)))
  (if (or (< ang (cs-partol)) (> ang (- pi (cs-partol))))
    (princ (strcat "\nWARNING: the two walls are nearly parallel; the"
                   " corner is "
                   (rtos (distance corner (cs-mid2 (car w1) (cadr w1))))
                   " away - check the selection.")))

  ;; show what was classified so a wrong guess is obvious
  (foreach s lines (if (nth 3 s) (redraw (nth 3 s) 3)))
  (if (and diag (nth 3 diag)) (redraw (nth 3 diag) 3))
  (princ (strcat "\nUsing two walls"
                 (cond (diag " plus a corner diagonal")
                       (arcr " plus a fillet arc")
                       (T ""))
                 "."))

  ;; ---- 4. middle of the diagonal / fillet ----------------------------
  (if arcr
    (setq c  (car arcr)
          r  (cadr arcr)
          a1 (caddr arcr)
          a2 (cadddr arcr)))
  (cond
    (diag (setq mid (cs-mid2 (car diag) (cadr diag))))
    (arcr (setq mid (cs-arcpt c r (* 0.5 (+ a1 a2))))))

  ;; ---- 5 to 7b: the option questions, walked as one chain -------------
  ;; Nothing is drawn until section 8, so these five decisions can be
  ;; taken over: every one after the first offers Back (Undo is its
  ;; hidden synonym) and re-opens the one before it, re-running the
  ;; geometry that sits between them - the measuring axis in particular,
  ;; which the tread-mode answer turns, so a second pass has to start
  ;; from the unturned one.
  ;;
  ;; Not every run asks every question: the measuring point needs a
  ;; diagonal or a fillet, the tread mode needs a diagonal, and the
  ;; bench is inside-out only.  QDIR remembers which way the chain is
  ;; travelling so a question this run does not put is stepped straight
  ;; over rather than stopped on.
  ;;
  ;; A form-supplied answer is consumed as it is used (STANDARDS 7.2),
  ;; so backing into a question the form filled in re-asks it at the
  ;; keyboard instead of answering it again and walking forward.
  (setq qstep 1 qdir 1)
  (while (<= qstep 6)
    (cond

      ;; -- 5. draw direction ------------------------------------------
      ;; the form answers first; when it does not, the bracket is exactly
      ;; the keyword list (STANDARDS section 1 rule 1) and the
      ;; explanation lives in the question text.  This is the first
      ;; question of the command, so it offers no Back.
      ((= qstep 1)
       (if (null (setq key (cs-fkw 'direction "Inside Outside" "Inside")))
         (progn
           (initget "Inside Outside")
           (setq key (getkword "\nDraw steps from the inside out, or the outside in? [Inside/Outside] <Inside>: "))))
       (setq outflag (= key "Outside")
             qstep   2
             qdir    1))

      ;; -- 5a. starting point (inside out only) -----------------------
      ((= qstep 2)
       (if (and mid (not outflag))
         (progn
           (if (null (setq key (cs-fkw 'measure "Middle True" "Middle")))
             (progn
               (initget "Middle True Back Undo")
               (setq key (getkword
                 "\nMeasure step treads from the middle of the diagonal, or the true corner? [Middle/True/Back] <Middle>: "))))
           (if (member key '("Back" "Undo"))
             (progn (princ "\n  Stepping back one question.")
                    (setq qstep 1 qdir -1))
             (setq start (if (= key "True") corner mid)
                   qstep 3
                   qdir  1)))
         ;; not asked this run - carry on the way the chain was going
         (progn (setq start corner)
                (setq qstep (+ qstep qdir)))))

      ;; -- 6. tread orientation / measuring direction toward the pool --
      ;; BIS  = direction the step treads are measured along
      ;; PERP = direction the step edges run (treads are drawn along PERP)
      ((= qstep 3)
       (setq d1   (cs-unit (cs-vec corner (cs-far w1 corner)))
             d2   (cs-unit (cs-vec corner (cs-far w2 corner)))
             bis  (cs-unit (mapcar '+ d1 d2))
             perp nil)
       (if (null bis)
         (progn (princ "\nThe walls are collinear - cannot find a step direction.")
                (exit)))
       (if (and mid (< (cs-dot bis (cs-vec corner mid)) 0.0))
         (setq bis (cs-scl bis -1.0)))
       (if diag
         (progn
           ;; one key answers whichever pair this run offers; a word the
           ;; live prompt does not list falls through to the prompt
           (if (null (setq key (cs-fkw 'treadmode
                                       (if outflag "Parallel Equidistant"
                                                   "Parallel True")
                                       "Parallel")))
             (if outflag
               (progn
                 (initget "Parallel Equidistant Back Undo")
                 (setq key (getkword (strcat
                   "\nSteps parallel to the diagonal, or equidistant"
                   " from the true corner? [Parallel/Equidistant/Back] <Parallel>: "))))
               (progn
                 (initget "Parallel True Back Undo")
                 (setq key (getkword
                   "\nTreads parallel to the diagonal, or at the true angle? [Parallel/True/Back] <Parallel>: ")))))
           (if (member key '("Back" "Undo"))
             (progn (princ "\n  Stepping back one question.")
                    (setq qstep 2 qdir -1))
             (if (not (member key '("True" "Equidistant")))
               (progn
                 ;; treads parallel to the diagonal; step treads measured
                 ;; square to it
                 (setq perp (cs-unit (cs-vec (car diag) (cadr diag)))
                       bis  (cs-perp90 perp))
                 (if (< (cs-dot bis (cs-vec corner mid)) 0.0)
                   (setq bis (cs-scl bis -1.0)))))))
         ;; no diagonal, so no question here: on the way back, keep going
         (if (< qdir 0) (setq qstep 2)))
       (if (= qstep 3)                  ; still here: the axis is settled
         (progn
           (if (null perp)
             ;; treads perpendicular to the true-angle (equal-angle) bisector
             (setq perp (cs-unit (cs-perp90 bis))))
           (if outflag
             (princ (strcat "\nOutermost step is bounded to the walls; drawing"
                            " back in toward the corner (direction "
                            (angtos (angle '(0.0 0.0 0.0) bis)) ")."))
             (princ (strcat "\nMeasuring from "
                            (if (equal start corner 1e-9)
                              "the true corner"
                              "the middle of the diagonal/arc")
                            " toward the pool (direction "
                            (angtos (angle '(0.0 0.0 0.0) bis)) ").")))
           ;; preview the measuring axis and the tread direction
           (setq reflen (max (distance corner (cs-far w1 corner))
                             (distance corner (cs-far w2 corner))))
           (grdraw (trans start 0 1)
                   (trans (cs-add start (cs-scl bis reflen)) 0 1) 4 0)
           (grdraw (trans (cs-add start (cs-scl perp (* 0.25 reflen))) 0 1)
                   (trans (cs-add start (cs-scl perp (* -0.25 reflen))) 0 1) 2 0)
           ;; previous edge ends, used to close the step sides (inside out
           ;; only - outside-in steps start out wall-bounded)
           (if (not outflag)
             (progn
               (cond
                 (diag (setq prevL (car diag) prevR (cadr diag)))
                 (arcr (setq prevL (cs-arcpt c r a1) prevR (cs-arcpt c r a2)))
                 (T    (setq prevL corner prevR corner)))
               (if (> (cs-dot (cs-vec start prevL) perp)
                      (cs-dot (cs-vec start prevR) perp))
                 (setq tmp prevL prevL prevR prevR tmp))))
           (setq qstep 4 qdir 1))))

      ;; -- 7. dimension the steps? ------------------------------------
      ((= qstep 4)
       (if (null (setq fkey (cs-fkw 'dims "Yes No" "Yes")))
         (progn
           (initget "Yes No Back Undo")
           (setq fkey (getkword "\nDimension the steps? [Yes/No/Back] <Yes>: "))))
       (if (member fkey '("Back" "Undo"))
         (progn (princ "\n  Stepping back one question.")
                (setq qstep 3 qdir -1))
         (progn
           (setq dimflag (/= "No" fkey))
           (if dimflag
             (progn
               (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
               (if (not (tblsearch "DIMSTYLE" *cs-depth-dimstyle*))
                 (princ (strcat "\nNote: dim style \"" *cs-depth-dimstyle*
                                "\" not found - step treads use the current style.")))
               (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
                 (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                                "\" not found - step widths use the current style.")))
               (if (and *cs-dim-layer* (not (cs-layerok *cs-dim-layer*)))
                 (princ (strcat "\nNote: dim layer \"" *cs-dim-layer*
                                "\" is missing or not drawable - using the"
                                " current layer.")))))
           (setq qstep 5 qdir 1))))

      ;; -- 7b. a bench along one wall? (inside out only) --------------
      ;; The bench stands in for a stretch of its wall: steps up to the
      ;; attachment tread meet the wall, the bench's front edge starts on
      ;; that tread, and every later step is bounded by the front edge
      ;; instead.  Outside in walks toward the corner without knowing its
      ;; step count in advance, so the bench is an inside-out feature.
      ((= qstep 5)
       (if outflag
         (setq qstep (+ qstep qdir))
         (progn
           (if (null (setq fkey (cs-fkw 'bench "Yes No" "No")))
             (progn
               (initget "Yes No Back Undo")
               (setq fkey (getkword "\nAdd a bench along a wall? [Yes/No/Back] <No>: "))))
           (cond
             ((member fkey '("Back" "Undo"))
              (princ "\n  Stepping back one question.")
              (setq qstep 4 qdir -1))
             ((= "Yes" fkey)
              (setq bnw nil bno nil bnk nil)
              (initget "Back Undo")
              (setq tmp (getpoint "\nPick the wall the bench sits against [Back]: "))
              (cond
                ((and (= (type tmp) 'STR) (member tmp '("Back" "Undo")))
                 (princ "\n  Stepping back one question."))  ; re-ask the bench
                ((null tmp)
                 (princ "\nNo wall picked - no bench added.")
                 (setq qstep 6 qdir 1))
                (T
                 (setq tmp  (trans tmp 1 0)
                       bnsd (if (<= (cs-ptseg tmp (car w1) (cadr w1))
                                    (cs-ptseg tmp (car w2) (cadr w2)))
                              1 2)
                       bnw  (if (= bnsd 1) w1 w2))
                 ;; its offset and step number can come off the form; both
                 ;; prompts refuse Enter, so nil falls back to the keyboard
                 (if (cs-fhas 'benchoffset) (setq bno (cs-fnum 'benchoffset)))
                 (if (not (numberp bno))
                   (progn
                     (initget 7 "Back Undo")
                     (setq bno (getdist "\nBench offset off the wall (its depth) [Back]: "))))
                 (if (and (= (type bno) 'STR) (member bno '("Back" "Undo")))
                   (princ "\n  Stepping back one question.")   ; re-ask the wall
                   (progn
                     (if (cs-fhas 'benchstep) (setq bnk (cs-ftake 'benchstep)))
                     (if (not (= (type bnk) 'INT))
                       (progn
                         (initget 7 "Back Undo")
                         (setq bnk (getint (strcat "\nWhich step is the bench attached"
                                                   " to (it ends on that tread) [Back]: ")))))
                     (if (and (= (type bnk) 'STR) (member bnk '("Back" "Undo")))
                       (progn (princ "\n  Stepping back one question.")
                              (setq bno nil))          ; re-ask the offset
                       (progn
                         ;; the front edge: the bench's wall shifted into the pool
                         (setq bnrm (cs-unit (cs-perp90 (cs-vec (car bnw) (cadr bnw)))))
                         (if (< (cs-dot bnrm bis) 0.0) (setq bnrm (cs-scl bnrm -1.0)))
                         (setq bnf  (list (cs-add (car bnw) (cs-scl bnrm bno))
                                          (cs-add (cadr bnw) (cs-scl bnrm bno)))
                               ;; which end of a normalized step that wall bounds
                               ;; (1 = the E1 end, 2 = the E2 end)
                               bnpe (if (> (cs-dot (if (= bnsd 1) d1 d2) perp) 0.0)
                                      2 1))
                         (princ (strcat "\n  Bench: " (rtos bno) " off that wall;"
                                        " steps past step " (itoa bnk)
                                        " run to its front edge."))
                         (setq qstep 6 qdir 1))))))))
             (T (setq qstep 6 qdir 1))))))

      ;; -- 7c. the outermost step's width (outside in only) -----------
      ;; Outside in starts at the far end, so its first step's width is a
      ;; setting like the rest of these rather than part of the tread
      ;; loop.  It is asked HERE, in front of the undo group, so Back can
      ;; re-open the question before it - inside the group it could not,
      ;; and a second _Begin is not an option.
      ((= qstep 6)
       (if (not outflag)
         (setq qstep (+ qstep qdir))
         (if (cs-fhas 'outerwidth)
           (setq wid   (cs-fnum 'outerwidth)
                 qstep 7)
           (progn
             (initget 6 "Back Undo")
             (setq wid (getdist
                         "\nWidth of the furthest (outermost) step [Back]: "))
             (if (cs-back-kw wid)
               (progn (princ "\n  Stepping back one question.")
                      (setq wid   nil
                            qstep 5
                            qdir  -1))
               (setq qstep 7 qdir 1))))))))

  ;; ---- 8. prompt for each step and draw it ----------------------------
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undoflag T)))
  (setq dist 0.0 n 1 drawn 0
        oldce (getvar "CMDECHO")
        oldlay (getvar "CLAYER"))
  (setvar "CMDECHO" 0)                    ; quiet the dimstyle/dim commands

  (if outflag

    ;; ========== OUTSIDE IN: outermost step first, then walk in ==========
    (progn
      ;; WID came off step 7c above, where it could still be taken back
      (if (null wid)
        (princ "\nNo width given - nothing drawn.")
        (progn
          ;; the wall opening grows linearly with distance from the
          ;; corner, so the opening at distance 1 fixes where a step of
          ;; the given width must sit to be bounded by both walls
          (setq p   (cs-add corner bis)
                h1  (inters p (cs-add p perp) (car w1) (cadr w1) nil)
                h2  (inters p (cs-add p perp) (car w2) (cadr w2) nil)
                op1 (if (and h1 h2) (distance h1 h2)))
          (if (or (null op1) (<= op1 1e-10))
            (princ "\nCannot measure the wall opening - nothing drawn.")
            (progn
              (setq tout (/ wid op1)   ; outermost step's ray distance
                    wid  nil)          ; the first step fits the walls
              (while (and (not stopf) tout)
                (setq mark  (entlast)
                      svdist dist svl prevL svr prevR svp pprev
                      svt   tprev svn n)
                (setq p   (cs-add corner (cs-scl bis tout))
                      h1  (inters p (cs-add p perp) (car w1) (cadr w1) nil)
                      h2  (inters p (cs-add p perp) (car w2) (cadr w2) nil)
                      nat (if (and h1 h2) (distance h1 h2))
                      bey (if (and h1 h2)
                            (max (cs-beyond h1 (car w1) (cadr w1))
                                 (cs-beyond h2 (car w2) (cadr w2)))
                            0.0)
                      tmp (cs-resolve wid nat h1 h2 p perp n tol)
                      e1  (car tmp)
                      e2  (cadr tmp))
                (if (> bey 1e-6)
                  (princ (strcat "\n    (note: the wall had to be extended "
                                 (rtos bey) " to meet this step)")))
                (if (and mid (< (cs-dot (cs-vec corner p)
                                        (cs-vec corner mid))
                                (cs-dot (cs-vec corner mid)
                                        (cs-vec corner mid))))
                  (princ (strcat "\n    (note: this step is inside the"
                                 " diagonal/fillet region)")))
                (if (and e1 e2)
                  (progn
                    ;; keep a consistent left/right orientation
                    (if (> (cs-dot (cs-vec corner e1) perp)
                           (cs-dot (cs-vec corner e2) perp))
                      (setq tmp e1 e1 e2 e2 tmp))
                    (cs-mkline e1 e2)          ; the step (tread) edge
                    (cs-conn prevL e1 w1 w2)   ; side lines where the walls
                    (cs-conn prevR e2 w1 w2)   ; do not already close them
                    (setq w (distance e1 e2))
                    (if dimflag
                      (progn
                        (if (null offd)
                          (setq offd (cs-chainoff w txth)))
                        ;; step width: nested just outside the corner
                        (cs-dim *cs-width-dimstyle* e1 e2
                                (cs-add corner
                                        (cs-scl bis
                                                (- (cs-nestoff w txth)))))
                        ;; step tread: chain link back out to the
                        ;; previous (next-further-out) tread
                        (if pprev
                          (cs-dim *cs-depth-dimstyle* p pprev
                                  (cs-add (cs-mid2 p pprev)
                                          (cs-scl perp offd))))))
                    (setq prevL e1 prevR e2 pprev p tprev tout
                          drawn (1+ drawn)
                          slog  (cons (list (cs-since mark) svdist svl svr
                                            svp svt svn)
                                      slog)
                          tlist (cons tout tlist))))
                ;; next step inward: step tread, then width - same rules as
                ;; inside out (a held width breaks from the walls)
                (if (not stopf)
                  (progn
                    (setq n (1+ n) dep 'RETRY)
                    (while (eq dep 'RETRY)
                      (cond
                        ;; the form gave the step COUNT: past it the
                        ;; run stops itself - the auto-done no prompt
                        ;; ever offered
                        ((and fsteps (> n fsteps)) (setq dep nil))
                        ;; this step's tread from the form, spent as
                        ;; it is read - a Back onto it re-asks at the
                        ;; keyboard
                        ((cs-fhas (cs-fnkey "tread" n))
                         (setq dep (cs-fnum (cs-fnkey "tread" n))))
                        (T
                         ;; Undo is the old keyword, kept as a hidden synonym
                         (initget 6 (if lastdep "Back Same Undo" "Back Undo"))
                         (setq dep (getdist (strcat "\nStep " (itoa n)
                                     " - step tread (going in) ["
                                     (if lastdep "Back/Same" "Back")
                                     "] <Enter = done>: ")))
                         (if (= (type dep) 'STR)
                           (cond
                             ((or (= dep "Back") (= dep "Undo"))
                              (cs-popstep)
                              (setq dep 'RETRY))
                             ((= dep "Same")
                              (if lastdep
                                (setq dep lastdep)
                                (progn (princ "\n  No previous step tread.")
                                       (setq dep 'RETRY))))
                             (T (setq dep 'RETRY)))))))
                    (cond
                      ((null dep) (setq tout nil)) ; done
                      ((<= (setq tout (- tprev dep)) 1e-8)
                       (princ (strcat "\nReached the corner - no room"
                                      " for another step; stopping."))
                       (setq stopf T))
                      (T
                       (setq lastdep dep)
                       (if (cs-fhas (cs-fnkey "width" n))
                         ;; nil = fit to the walls, what Enter means
                         (setq wid (cs-fnum (cs-fnkey "width" n)))
                         (progn
                           ;; Enter is already spoken for here - it fits the
                           ;; step to the walls - so repeating the last width
                           ;; needs a word of its own, and Same is the one the
                           ;; tread prompt above already uses (S, per
                           ;; STANDARDS section 2)
                           (if lastwid (initget 6 "Same") (initget 6))
                           (setq wid (getdist (strcat "\nStep " (itoa n)
                             " - step width"
                             (if lastwid " [Same]" "")
                             " <Enter = fit to walls"
                             (if lastwid (strcat ", Same = " (rtos lastwid)) "")
                             ">: ")))
                           (if (= (type wid) 'STR) (setq wid lastwid))))
                       ;; only a width the user GAVE is one Same can repeat;
                       ;; a step fitted to the walls has no number to reuse
                       (if (numberp wid) (setq lastwid wid))))))))))))

    ;; ========== INSIDE OUT: from the corner out toward the pool =========
    (while
      (progn
        (setq dep 'RETRY)
        (while (eq dep 'RETRY)
          (cond
            ;; the form gave the step COUNT: past it the run stops
            ;; itself - the auto-done no prompt ever offered
            ((and fsteps (> n fsteps)) (setq dep nil))
            ;; this step's tread from the form, spent as it is read -
            ;; a Back onto it re-asks at the keyboard
            ((cs-fhas (cs-fnkey "tread" n))
             (setq dep (cs-fnum (cs-fnkey "tread" n))))
            (T
             ;; Undo is the old keyword, kept as a hidden synonym
             (initget 6 (if lastdep "Back Same Undo" "Back Undo"))
             (setq dep (getdist (strcat "\nStep " (itoa n) " - step tread ["
                                        (if lastdep "Back/Same" "Back")
                                        "]"
                                        (if lastdep
                                          (strcat " <Enter = done, Same = "
                                                  (rtos lastdep) ">: ")
                                          " <Enter = done>: "))))
             (if (= (type dep) 'STR)
               (cond
                 ((or (= dep "Back") (= dep "Undo")) (cs-popstep) (setq dep 'RETRY))
                 ((= dep "Same")
                  (if lastdep
                    (setq dep lastdep)
                    (progn (princ "\n  No previous step tread.") (setq dep 'RETRY))))
                 (T (setq dep 'RETRY)))))))
        dep)
      (setq mark  (entlast)
            svdist dist svl prevL svr prevR svp pprev svt tprev svn n
            lastdep dep)
      (if (cs-fhas (cs-fnkey "width" n))
        ;; the form's width, nil = fit to the walls (what Enter means)
        (setq wid (cs-fnum (cs-fnkey "width" n)))
        (progn
          ;; Enter fits the step to the walls, so Same is what repeats the
          ;; last width given (S, per STANDARDS section 2)
          (if lastwid (initget 6 "Same") (initget 6))
          (setq wid (getdist (strcat "\nStep " (itoa n)
                                     " - step width"
                                     (if lastwid " [Same]" "")
                                     " <Enter = fit to walls"
                                     (if lastwid
                                       (strcat ", Same = " (rtos lastwid))
                                       "")
                                     ">: ")))
          (if (= (type wid) 'STR) (setq wid lastwid))))
      ;; only a width the user GAVE is one Same can repeat
      (if (numberp wid) (setq lastwid wid))
      (setq dist (+ dist dep)                       ; step tread held exactly
            p    (cs-add start (cs-scl bis dist))
            ;; past the bench tread the bench's front edge stands in
            ;; for the wall it rides along
            bact (and bnf (> n bnk))
            bu1  (if (and bact (= bnsd 1)) bnf w1)
            bu2  (if (and bact (= bnsd 2)) bnf w2)
            h1   (inters p (cs-add p perp) (car bu1) (cadr bu1) nil)
            h2   (inters p (cs-add p perp) (car bu2) (cadr bu2) nil)
            nat  (if (and h1 h2) (distance h1 h2))  ; wall opening here
            bey  (if (and h1 h2)
                   (max (cs-beyond h1 (car bu1) (cadr bu1))
                        (cs-beyond h2 (car bu2) (cadr bu2)))
                   0.0)
            tmp  (cs-resolve wid nat h1 h2 p perp n tol)
            e1   (car tmp)
            e2   (cadr tmp))
      (if (> bey 1e-6)
        (princ (strcat "\n    (note: the wall had to be extended "
                       (rtos bey) " to meet this step)")))
      (if (and e1 e2)
        (progn
          ;; keep a consistent left/right orientation for the side lines
          (if (> (cs-dot (cs-vec start e1) perp)
                 (cs-dot (cs-vec start e2) perp))
            (setq tmp e1 e1 e2 e2 tmp))
          (cs-mkline e1 e2)          ; the step (tread) edge
          ;; side lines where the walls do not already close the step;
          ;; past the bench tread its front edge closes the bench side
          (if (not (and bact (= bnpe 1))) (cs-conn prevL e1 w1 w2))
          (if (not (and bact (= bnpe 2))) (cs-conn prevR e2 w1 w2))
          (if dimflag
            (progn
              (setq w (distance e1 e2))
              ;; fix the tread chain's side offset once, off the bisector
              (if (null offd) (setq offd (cs-chainoff w txth)))
              ;; step tread: link of a chain along the bisector, from the
              ;; previous tread crossing (p - bis*dep) to this one (p)
              (cs-dim *cs-depth-dimstyle*
                      (cs-add p (cs-scl bis (- dep))) p
                      (cs-add (cs-add p (cs-scl bis (* -0.5 dep)))
                              (cs-scl perp offd)))
              ;; step width: full tread edge, placed just outside the
              ;; corner and nested by half the tread's own width so the
              ;; wider (deeper) steps stack progressively further out
              (cs-dim *cs-width-dimstyle*
                      e1 e2
                      (cs-add corner (cs-scl bis (- (cs-nestoff w txth)))))))
          (setq prevL e1 prevR e2 pprev p drawn (1+ drawn)
                slog (cons (list (cs-since mark) svdist svl svr svp svt svn)
                           slog)
                tlist (cons dist tlist))))
      (setq n (1+ n))))

  ;; ---- 8b. the bench ---------------------------------------------------
  ;; Drawn once the treads exist: the front edge starts where the
  ;; attachment tread crosses it, runs to the far end of its wall and
  ;; is capped there; the attachment tread itself closes the near end.
  (if bnf
    (progn
      (foreach pr (cs-treadents slog)
        (if (= (car pr) bnk) (setq bnl (cdr pr))))
      (cond
        ((null bnl)
         (princ (strcat "\nOnly " (itoa drawn) " step(s) landed - step "
                        (itoa bnk) " does not exist, so no bench was"
                        " drawn.")))
        ((progn
           (setq ed  (entget bnl)
                 bns (inters (cdr (assoc 10 ed)) (cdr (assoc 11 ed))
                             (car bnf) (cadr bnf) nil))
           (null bns))
         (princ (strcat "\nStep " (itoa bnk) " runs parallel to the"
                        " bench's front edge - no bench drawn.")))
        (T
         (setq bnfar (cs-far bnw corner)
               bnff  (cs-add bnfar (cs-scl bnrm bno)))
         (cs-mkline bns bnff)             ; the front edge
         (cs-mkline bnff bnfar)           ; the cap at the wall's far end
         (if dimflag
           (progn
             ;; its length, placed behind the wall
             (cs-dim *cs-width-dimstyle* bns bnff
                     (cs-add (cs-mid2 bns bnff)
                             (cs-scl bnrm (- (+ bno (cs-dimoff txth))))))
             ;; its offset off the wall, just past the cap
             (cs-dim *cs-depth-dimstyle* bnfar bnff
                     (cs-add (cs-mid2 bnfar bnff)
                             (cs-scl (cs-unit (cs-vec corner bnfar))
                                     (cs-dimoff txth))))))
         (princ (strcat "\nBench drawn: " (rtos (distance bns bnff))
                        " along the wall, " (rtos bno)
                        " off it, ending on step " (itoa bnk) "."))))))

  ;; ---- 9. optional side profile ---------------------------------------
  ;; Drawn while the UNDO group is still open and before the entry dim
  ;; style is restored - the profile places its own dims.
  (if (> drawn 0)
    (progn
      (if (null (setq fkey (cs-fkw 'profile "Yes No" "Yes")))
        (progn
          (initget "Yes No")
          (setq fkey (getkword "\nAdd a side profile? [Yes/No] <Yes>: "))))
      (if (/= "No" fkey)
        (progn
          ;; treads, top step first: sort the axis distances ascending
          ;; (outside-in entered them outermost first) and take the
          ;; first value, then each successive difference
          (setq tvals (vl-sort tlist '<) tds nil pd 0.0)
          (foreach s tvals
            (if (> (- s pd) 1e-6) (setq tds (cons (- s pd) tds)))
            (setq pd s))
          (setq tds (reverse tds))
          (if (null tds)
            (princ "\nNo usable tread spacing - side profile skipped.")
            (progn
              ;; ask the depths, top step first, with Back support:
              ;; one per step PLUS one more for the drop after the
              ;; last tread, so 3 steps take 4 depths
              ;; the depths and the pick are one chain: Back at the
              ;; pick re-opens the LAST depth rather than starting the
              ;; whole ladder again
              (setq drops nil ix 0 ppt 'RETRY)
              (while (eq ppt 'RETRY)
               (while (<= ix (length tds))
                (setq pd 'RETRY)
                (while (eq pd 'RETRY)
                  ;; depth1..depthN and depthafter can come off the
                  ;; form, spent as they are read; nil reads as Enter,
                  ;; which the first depth refuses - that one falls
                  ;; back to the keyboard on the next pass, key spent
                  (setq fkey (if (= ix (length tds))
                               'depthafter
                               (cs-fnkey "depth" (1+ ix))))
                  (if (cs-fhas fkey)
                    (progn
                      (setq pd (cs-fnum fkey))
                      (if (null pd)
                        (setq pd (if (zerop ix) 'RETRY (car drops)))))
                    (progn
                      (if (zerop ix)
                        (progn
                          ;; Back/Undo hidden here: typing them only gets
                          ;; the already-at-the-first-step feedback
                          (initget 7 "Back Undo")
                          (setq pd (getdist "\nStep 1 - step depth (the drop): ")))
                        (progn
                          ;; Undo is the old keyword, kept as a hidden synonym
                          (initget 6 "Back Undo")
                          (setq pd (getdist (strcat
                                      (if (= ix (length tds))
                                        "\nDepth after the last tread [Back] <"
                                        (strcat "\nStep " (itoa (1+ ix))
                                                " - step depth [Back] <"))
                                      (rtos (car drops)) ">: ")))))
                      (cond
                        ((= (type pd) 'STR)             ; Back or Undo
                         (if (zerop ix)
                           (princ "\n  Already at the first step.")
                           (progn (setq drops (cdr drops) ix (1- ix))
                                  (princ "\n  Stepping back one step.")))
                         (setq pd 'RETRY))
                        ((null pd) (setq pd (car drops))))))) ; Enter = previous
                (setq drops (cons pd drops) ix (1+ ix)))
               ;; Place the profile.  It always runs DOWN AND TO THE
               ;; LEFT from the pick, so there is no side to ask about.
               (initget "Back Undo")
               (setq ppt (getpoint (strcat "\nPick the top of the first"
                                           " tread for the side profile [Back]: ")))
               (if (cs-back-kw ppt)
                 (progn (princ "\n  Stepping back one step.")
                        (setq drops (cdr drops)
                              ix    (1- ix)
                              ppt   'RETRY))))
              (setq drops (reverse drops))
              (if (null ppt)
                (princ "\nNo point picked - side profile skipped.")
                (progn
                  ;; The alternating drop/tread silhouette in world
                  ;; X/Y, keeping the corner down its high side at
                  ;; every level: the pick, then the foot of each
                  ;; drop.  Those corners are what the dims bind to.
                  (setq totd (apply '+ drops)
                        totr (apply '+ tds)
                        pw   (trans ppt 1 0)
                        px   (car pw)
                        py   (cadr pw)
                        ix   0
                        cnrs (list (list px py 0.0)))
                  (foreach s tds
                    (setq pd (nth ix drops))
                    (cs-mkline (list px py 0.0) (list px (- py pd) 0.0))
                    (setq py   (- py pd)
                          cnrs (cons (list px py 0.0) cnrs))
                    ;; the tread runs left, and carries no dim of its
                    ;; own - the depths and the overall depth say it all
                    (cs-mkline (list px py 0.0) (list (- px s) py 0.0))
                    (setq px (- px s) ix (1+ ix)))
                  ;; the last depth: the drop after the last tread
                  (setq pd (nth ix drops))
                  (cs-mkline (list px py 0.0) (list px (- py pd) 0.0))
                  (setq py   (- py pd)
                        cnrs (reverse (cons (list px py 0.0) cnrs)))
                  (if dimflag
                    (progn
                      ;; Every depth dim stands the same distance right of
                      ;; the corner its drop lands on, so the dims climb up
                      ;; and to the right with the steps instead of stacking
                      ;; in one chain.  Clearing the widest tread is what
                      ;; keeps BOTH extension lines running forward, out of
                      ;; the flight; the gap on top of that is what makes
                      ;; the fan readable, and cs-pgap - *cs-profile-dimgap*
                      ;; and the two terms of its default - is what sets it
                      (setq pgap (cs-pgap txth (apply 'max tds))
                            pfo  (+ (apply 'max tds) pgap)
                            ix   1)
                      (while (< ix (length cnrs))
                        (setq ca (nth (1- ix) cnrs)
                              cb (nth ix cnrs))
                        (cs-dimv *cs-depth-dimstyle* ca cb
                                 (list (+ (car cb) pfo)
                                       (* 0.5 (+ (cadr ca) (cadr cb)))
                                       0.0))
                        (setq ix (1+ ix)))
                      ;; the overall depth, further out again - the
                      ;; whole diagonal, top corner to bottom corner
                      (cs-dimv *cs-depth-dimstyle*
                               (car cnrs) (last cnrs)
                               (list (+ (car pw) pfo pgap)
                                     (- (cadr pw) (* 0.5 totd)) 0.0))))
                  (princ (strcat "\nSide profile drawn: "
                                 (itoa (length tds))
                                 " step(s), " (itoa (length drops))
                                 " depths, down to the left; total run "
                                 (rtos totr) ", overall depth "
                                 (rtos totd) "."))))))))))

  ;; ---- 10. done --------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn)
                   " step(s) drawn - step treads held exactly.")))
  (foreach s lines (if (nth 3 s) (redraw (nth 3 s) 4)))
  (if (and diag (nth 3 diag)) (redraw (nth 3 diag) 4))
  (redraw)
  (if oldstyle (cs-setstyle oldstyle))   ; back to the entry dim style
  ;; close only a group this run opened: in a drawing with UNDO off
  ;; none was, and _End on no group is an error of its own
  (if undoflag
    (progn (command "_.UNDO" "_End")
           (setq undoflag nil)))
  (if oldce (setvar "CMDECHO" oldce))
  (if oldlay (setvar "CLAYER" oldlay))
  (if oldlu (setvar "LUNITS" oldlu))

  ;; ---- 11. bead the steps -----------------------------------------------
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
             (if (null (setq fkey (cs-fkw 'bead "Yes No" "Yes")))
               (progn
                 (initget "Yes No")
                 (setq fkey (getkword "\nBead the steps? [Yes/No] <Yes>: "))))
             (setq bstep (if (/= "No" fkey) 2 5)))
            ((= bstep 2)
             (setq btreads (cs-treadents slog)
                   bsides  (cs-sideents slog)
                   bnums   nil)
             (if (null btreads)
               (progn (princ "\nNo tread lines to bead.") (setq bstep 5))
               (progn
                 ;; every tread but the last is beaded - the side walls
                 ;; are the question, and None leaves them bare
                 (initget "All Some None Back Undo")
                 (setq bside (cond ((getkword (strcat "\nWhich steps have"
                                                      " beaded side walls?"
                                                      " [All/Some/None/Back]"
                                                      " <All>: ")))
                                   ("All")))
                 (if (member bside '("Back" "Undo"))
                   (progn (princ "\n  Stepping back one question.")
                          (setq bstep 1))
                   (setq bstep 3)))))
            ((= bstep 3)
             (if (/= bside "Some")
               (setq bstep 4)
               (progn
                 (princ (strcat "\n  Steps drawn: " (cs-numsay btreads)))
                 (setq s (getstring T (strcat "\nStep numbers with"
                                              " beaded sides (B = back): ")))
                 (if (cs-back-word s)
                   (progn (princ "\n  Stepping back one question.")
                          (setq bstep 2))
                   (progn
                     (setq bnums (cs-numlist s))
                     (setq bnums (vl-remove-if-not
                                   '(lambda (k) (assoc k btreads)) bnums))
                     (if (null bnums)
                       (progn
                         (princ (strcat "\n  No step numbers recognized -"
                                        " beading every side wall full"
                                        " length."))
                         (setq bside "All")))
                     (setq bstep 4))))))
            ((= bstep 4)
             (initget "Back Undo")
             (setq bdir (getpoint "\nClick the side to bead toward [Back]: "))
             (if (cs-back-kw bdir)
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
                    (autobead-build
                      bss bdir
                      bside
                      (if (= bside "Some")
                        (mapcar '(lambda (k)
                                   (cs-entmid (cdr (assoc k btreads))))
                                bnums)
                        nil)
                      ;; the last step drawn still goes over as a step
                      ;; line - it is a breakline like any other - but
                      ;; it is named here so AUTOBEAD leaves it unbeaded
                      (list (cs-entmid (cdr (last btreads)))))))))))))))
  (cs-fclear)                       ; both exits clear the form store
  (princ))

;;; --------------------------- tutorial ---------------------------------

(defun cs-tut-pause ( )
  (princ "\n      --- press Enter to continue ---")
  (getstring)
  (princ))

(defun cs-tut-text (pt h s)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 s))))

;; Walkthrough for new users: pages of what CORNERSTP does and checks,
;; then a live demonstration drawn step by step with the same geometry
;; code the real command uses.
(defun c:TUTORIALCORNERSTP ( / *error* undoflag oldce oldlay oldstyle org w1 w2
                               bis perp txth dist p h1 h2 nat tmp e1 e2
                               prevL prevR w offd n pt lst dep wid)
  (defun *error* (msg)
    (if undoflag (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if oldstyle (cs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlay (setvar "CLAYER" oldlay))
    (if lzd:report (lzd:report "TUTORIALCORNERSTP" *cs-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TUTORIALCORNERSTP" *cs-version*))

  (princ (strcat "\n================ CORNERSTP TUTORIAL " *cs-version*
                 " ================"))
  (princ "\nCORNERSTP draws parallel corner steps fanning out of a pool")
  (princ "\ncorner toward the pool.  Step treads are always held exactly;")
  (princ "\nstep widths are held to within 1/8\" of the wall opening -")
  (princ "\ncloser than that and the step trims to the walls, further and")
  (princ "\nit holds your width and BREAKS from the walls, running equally")
  (princ "\npast both sides.")
  (cs-tut-pause)
  (princ "\nWHAT YOU SELECT")
  (princ "\n  - the two walls of the corner (LINEs or polyline segments)")
  (princ "\n  - optionally a chamfer diagonal or a fillet arc with them")
  (princ "\n  - more than two straight walls: it asks you to pick the two")
  (princ "\nTHE PROMPTS, IN ORDER")
  (princ "\n  1. Draw steps [Inside/Outside]")
  (princ "\n     Inside out: corner outward - each step asks step tread,")
  (princ "\n       then width (Enter fits the step to the walls).")
  (princ "\n     Outside in: the width of the furthest step places it")
  (princ "\n       wall-to-wall, then tread/width pairs walk back in.")
  (princ "\n  2. With a diagonal/arc: measure from its Middle or the True")
  (princ "\n     corner, and treads Parallel to the diagonal or square to")
  (princ "\n     the true-angle bisector.")
  (princ "\n  3. Dimension the steps? [Yes/No]")
  (princ "\n  4. Add a bench along a wall? [Yes/No] (inside out) - pick")
  (princ "\n     the wall it sits against, give its offset off that wall,")
  (princ "\n     then the step it is attached to.  Steps past that tread")
  (princ "\n     are bounded by the bench's front edge instead of the")
  (princ "\n     wall; the bench ends on that tread and runs out to the")
  (princ "\n     far end of its wall.")
  (princ "\n  5. Add a side profile? [Yes/No] - give the step depths, top")
  (princ "\n     step first: one per step plus the drop after the last")
  (princ "\n     tread (3 steps take 4 depths).  Then pick the top of the")
  (princ "\n     first tread - the flight always runs down and to the")
  (princ "\n     LEFT from there, so the steps rise to the right and the")
  (princ "\n     dims climb with them.  Each depth is dimensioned beside")
  (princ "\n     its own step and the overall depth further out; the")
  (princ "\n     treads are not dimensioned.")
  (princ "\n  6. Bead the steps? [Yes/No] - every tread but the LAST is")
  (princ "\n     beaded (the line that closes the run has no riser), so")
  (princ "\n     the only question is which steps have beaded SIDE")
  (princ "\n     WALLS: [All/Some/None].  Some takes the step numbers")
  (princ "\n     (\"1 3 4\"); None leaves the side walls bare.")
  (princ "\n     Then click the side to bead toward and AUTOBEAD does the")
  (princ "\n     rest on its own rules - it has to be loaded for this.")
  (princ "\n  At any step tread prompt: Enter = done, Back = step back one")
  (princ "\n  step (removes it), Same (S) = repeat the previous step tread.")
  (princ "\n  At a step WIDTH prompt Enter fits the step to the walls, so")
  (princ "\n  Same (S) is what repeats the last width you typed - and the")
  (princ "\n  prompt names the number it would repeat.")
  (cs-tut-pause)
  (princ "\nWHAT IT CHECKS AND HANDLES FOR YOU")
  (princ "\n  - warns when the UCS is tilted, a line is not flat, or the")
  (princ "\n    current layer is off/frozen/locked")
  (princ "\n  - reads bare numbers as inches and accepts 1'4 style entry")
  (princ "\n    whatever the drawing's units setting")
  (princ "\n  - finds the true corner by extending the walls; warns when")
  (princ "\n    they are nearly parallel")
  (princ "\n  - picks out the chamfer among three lines and highlights")
  (princ "\n    what it classified before asking anything")
  (princ "\n  - reads arcs from their own geometry (mirrored arcs behave)")
  (princ "\n  - notes when a wall had to be extended to meet a step")
  (princ "\n  - dims go in \"STANDARD INCHES\" (step treads) and")
  (princ "\n    \"SIDE STANDARD\" (widths), falling back to the current")
  (princ "\n    style if missing; the whole run is ONE undo")
  (cs-tut-pause)

  (initget "Yes No")
  (if (= "No" (getkword (strcat "\nDraw a demonstration in this drawing?"
                                " [Yes/No] <Yes>: ")))
    (progn (princ "\nTutorial done - type CORNERSTP to use it for real.")
           (exit)))
  (setq pt (getpoint "\nPick a clear spot (about 250 x 250 needed): "))
  (if (null pt)
    (progn (princ "\nNo spot picked - tutorial done.") (exit)))
  (setq org  (trans pt 1 0)
        txth (cs-txth)
        w1   (list org (cs-add org '(200.0 0.0 0.0)))
        w2   (list org (cs-add org '(0.0 200.0 0.0)))
        bis  (cs-unit '(1.0 1.0 0.0))
        perp (cs-perp90 bis))
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

  (cs-mkline (car w1) (cadr w1))
  (cs-mkline (car w2) (cadr w2))
  (cs-tut-text (cs-add org '(30.0 -18.0 0.0)) (* 1.2 txth)
               "CORNERSTP demo: an L corner - these two lines get selected")
  (princ "\n[1] Two WALLS drawn - this is what you select.  The corner is")
  (princ "\n    their intersection; the steps will fan out along the 45")
  (princ "\n    degree bisector between them.")
  (cs-tut-pause)

  (setq prevL org prevR org dist 0.0 n 1)
  (foreach lst '((24.0 . 48.0) (12.0 . 72.0) (12.0 . 100.0))
    (setq dep  (car lst)
          wid  (cdr lst)
          dist (+ dist dep)
          p    (cs-add org (cs-scl bis dist))
          h1   (inters p (cs-add p perp) (car w1) (cadr w1) nil)
          h2   (inters p (cs-add p perp) (car w2) (cadr w2) nil)
          nat  (if (and h1 h2) (distance h1 h2))
          tmp  (cs-resolve wid nat h1 h2 p perp n (cs-tolerance))
          e1   (car tmp)
          e2   (cadr tmp))
    (if (> (cs-dot (cs-vec org e1) perp) (cs-dot (cs-vec org e2) perp))
      (setq tmp e1 e1 e2 e2 tmp))
    (cs-mkline e1 e2)
    (cs-conn prevL e1 w1 w2)
    (cs-conn prevR e2 w1 w2)
    (setq w (distance e1 e2))
    (if (null offd) (setq offd (cs-chainoff w txth)))
    (cs-dim *cs-depth-dimstyle*
            (cs-add p (cs-scl bis (- dep))) p
            (cs-add (cs-add p (cs-scl bis (* -0.5 dep)))
                    (cs-scl perp offd)))
    (cs-dim *cs-width-dimstyle* e1 e2
            (cs-add org (cs-scl bis (- (cs-nestoff w txth)))))
    (cond
      ((= n 1)
       (princ "\n[2] Step 1: step tread 24, width 48.  The wall opening")
       (princ "\n    at that distance IS 48, so it trims to the walls.  Its")
       (princ "\n    tread dim starts the chain along the bisector; its")
       (princ "\n    width dim nests outside the corner."))
      ((= n 2)
       (princ "\n[3] Step 2: step tread 12, width 72 - also fits.  Step")
       (princ "\n    treads are each measured from the previous step,")
       (princ "\n    never a total."))
      (T
       (princ "\n[4] Step 3: step tread 12, width 100 - the opening here is")
       (princ "\n    only 96.  More than 1/8\" apart, so the width is HELD")
       (princ "\n    and the step breaks the walls, running 2 past each")
       (princ "\n    side.  Riser lines close its ends.")))
    (cs-tut-pause)
    (setq prevL e1 prevR e2 n (1+ n)))

  (if oldstyle (cs-setstyle oldstyle))
  (if undoflag                           ; only a group this run opened
    (progn (command "_.UNDO" "_End")
           (setq undoflag nil)))
  (setvar "CMDECHO" oldce)
  (princ "\n[5] Done.  One U removes this whole demo.  Now try it for")
  (princ "\n    real: type CORNERSTP, select two wall lines of a corner,")
  (princ "\n    and follow the same prompts you just watched.")
  (princ))

(defun c:CORNERSTPVER ()
  (princ (strcat "\nCORNERSTP " *cs-version*))
  (princ))

(princ (strcat "\nCORNERSTP.lsp " *cs-version*
               " loaded - CORNERSTP to draw corner steps,"
               " TUTORIALCORNERSTP to learn it."))
(princ)
