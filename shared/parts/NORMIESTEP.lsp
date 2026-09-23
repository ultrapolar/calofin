;;; ======================================================================
;;; NORMIESTEP.lsp
;;; ----------------------------------------------------------------------
;;; The most normal, boring pool steps of all time: straight, parallel
;;; treads of one constant width.
;;; Written for AutoCAD 2018 (plain AutoLISP + ActiveX for dim styles).
;;;
;;; LOAD:     APPLOAD this file (or drag it into the drawing window).
;;; COMMAND:  NORMIESTEP
;;;
;;; WHAT IT DOES
;;;   Every step is the same width - that is the whole point.  What you
;;;   select decides where the run sits:
;;;
;;;   ONE LINE ......... the steps are CENTERED on that line.  You pick
;;;                      which side they go, give the width once, then
;;;                      the step treads.  The side walls leave the wall
;;;                      square and run to the last tread; the corner
;;;                      treatment sits on the last step.
;;;   TWO LINES (a corner)
;;;                      the steps sit in a recess OUTSIDE the corner.
;;;                      The corner itself says which way that is: both
;;;                      lines run away from it into the pool, so the
;;;                      run goes the other way - out through the wall
;;;                      it comes off, never into the water between
;;;                      them.  You are asked which of the two lines
;;;                      the steps run off of - the same line the
;;;                      back-corner offset is measured on; the treads
;;;                      run parallel to it and butt against the other
;;;                      one, carried on past the corner.
;;;   A "U" ............ the outline the steps sit in is already drawn,
;;;                      so the treads are just filled in.  The BASE of
;;;                      the U - its closed end - is the wall the steps
;;;                      come off: the run STARTS there and marches out
;;;                      toward the open end, trimmed to the two arms.
;;;                      No width is asked for - the arms give it.  The
;;;                      U may already have its back corners drawn where
;;;                      the arms meet the base: three lines is a plain
;;;                      square-cornered U, five lines is one with Cut
;;;                      (diagonal) corners, and three lines plus two
;;;                      arcs is one with Radius (rounded) corners.
;;;                      Polylines work too, including bulged (rounded)
;;;                      corner segments.  Treads trim to whatever part
;;;                      of the side they land on - arm, diagonal, or
;;;                      arc.  A plain square U is asked for its back
;;;                      corners like the other modes.
;;;
;;; WORKFLOW
;;;   1.  Select the base line, the two lines of a corner, or a U-shaped
;;;       perimeter (LINEs or the straight segments of a POLYLINE).
;;;   2.  One-line mode asks which side the steps go.  Corner mode asks
;;;       which line the steps run off of.  The U needs neither.
;;;   3.  Unless it is a U, you give the step width ONCE - every step
;;;       gets it.  Then comes the corner treatment.  One-line mode asks
;;;       for the CORNERS OF THE LAST STEP - the two where the side
;;;       walls meet the last tread; the other modes ask for their BACK
;;;       CORNERS - the two where the sides of the run meet the wall it
;;;       comes off.  Either way a corner is
;;;         Square   - a true 90 degree corner (the default)
;;;         Radius   - a fillet arc, you give the radius
;;;         Cut      - a straight 45 degree diagonal, given as either
;;;                    its Offset back along each line or the Cut face
;;;                    length (each gives the other: cut = offset x
;;;                    root 2)
;;;         NotGiven - the order sheet never said.  The corner is drawn
;;;                    square, like Square, but a note on the drawing
;;;                    says it was never recorded, so nobody reads it
;;;                    as a measured 90.
;;;       In one-line mode the treatment is worked into the last step:
;;;       the last tread gives up the offset at each end, the side walls
;;;       stop that much short, and the corner piece bridges the two.
;;;       In corner mode the treatment stays at the wall and flares the
;;;       mouth of the recess the run sits in by that offset; in a U it
;;;       is cut into the corner and the treads trim to it.  A U that
;;;       already has its back corners drawn is not asked.
;;;   4.  Then step treads, one per step - each the plan-view spacing
;;;       measured FROM THE PREVIOUS TREAD (from the base line for the
;;;       first).  Distances read architectural style: a bare number is
;;;       inches (drawing units) and feet-inch entry like 1'4 (= 16")
;;;       works whatever the units setting.
;;;   5.  Enter at a step tread prompt = done.  Back steps back one
;;;       step: it removes the step just drawn (its line and its
;;;       dimensions).  Undo, the old keyword, is still accepted.  Same
;;;       repeats the previous step tread, which is what most runs want.
;;;       From the second step on the tread is asked beside the LENGTH
;;;       RULER (below): a click on a row is the tread.
;;;   6.  The side lines of the run are drawn for the one-line and
;;;       corner modes.  One-line mode draws plain side walls, square
;;;       off the base wall, running from the wall to the last tread -
;;;       the treatment sits on the last step's corners, so a Radius or
;;;       Cut one stops the walls an offset short and the corner
;;;       piece finishes the trip.  Corner mode draws BOTH sides of
;;;       the recess, because the line the treads sit against stops at
;;;       the corner and the run is on the far side of it: the inner
;;;       side carries that line on past the corner, and the outer one
;;;       is the same line offset by the step width.  Neither is square
;;;       to the base - the treads all start on the leaning line and
;;;       run out from it - so both still meet every tread end where
;;;       the corner is not a true 90.  Only the outer side takes the
;;;       back-corner flare: the inner one runs straight on out of the
;;;       wall it continues, so there is no corner there to treat.
;;;       The U already has its arms, so only a back corner asked for
;;;       there is drawn.
;;;   7.  Optional dimensions: the step treads chained along the run,
;;;       plus the step width once (it is the same for every step).
;;;   8.  Optionally a SIDE PROFILE: you give the STEP DEPTHS - the
;;;       vertical drops, top step first, one per step PLUS one more
;;;       for the drop after the last tread, so 3 steps take 4 depths
;;;       (Enter repeats the previous one, Back steps back, and from
;;;       the second one on the length ruler stands beside the prompt)
;;;       - then pick the top of the first tread.  The flight always runs
;;;       DOWN AND TO THE LEFT from there, so there is no side to
;;;       pick.  See "The side profile" below.
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
;;;   of the first tread and ending on the last depth - so the steps
;;;   rise to the right, the way the shop's own elevations read, and
;;;   stand upright in a turned UCS, where the dims measure the drops.
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
;;;   inches it is derived from, how close two ends must be to count as
;;;   joined when a U is chained together, the two dim styles and the
;;;   dim layer, how far the tread chain stands off the run and how far
;;;   the width dim nests behind it, the side profile's dim gap, and
;;;   the length ruler's colours, place and size.  setq one before
;;;   running the command and the next run picks it up.
;;;   They are shared with CORNERSTP and HEMISTEP, which is why they are
;;;   *cs- names: one set of knobs for the three step routines.
;;;
;;; NOTES
;;;   - Geometry is assumed to be drawn in plan view.  The routine warns
;;;     when the current UCS is not World, when a selected line is not
;;;     flat, and when the current layer is off/frozen/locked.
;;;   - Steps are drawn as LINEs on the current layer.
;;;   - One U / UNDO reverses the whole command; a bead run added at
;;;     the end is its own group, so it takes a U of its own.
;;;   - A form (the Calofin palette / LAZFORM) can pre-answer the
;;;     questions - the step COUNT included, which the prompts only
;;;     ever learn from Enter - by leaving (key . value) pairs in
;;;     *NS-FORM*; see "form answers" below.  Selections and point
;;;     picks are always made by hand.
;;; ======================================================================

;;; ------------------------------ SETTINGS ------------------------------
;;;  THE KNOBS, all of them, in one place.  Each is defined only if it
;;;  is not already set, so this file, CORNERSTP.lsp and HEMISTEP.lsp
;;;  share ONE set of settings whichever loads first and a value set
;;;  before loading them stands.  setq one at the command line - or in
;;;  acaddoc.lsp - and the next run picks it up.
;;;
;;;  Deliberately NOT settings: the epsilons the geometry compares
;;;  against (a point is on a line or it is not), the temporary vectors
;;;  the run previews itself with, the direction the side profile reads
;;;  (down and to the left, the way the shop's elevations do), and the
;;;  bead - that is AUTOBEAD's work, on AUTOBEAD's own settings.

;; Width tolerance, in drawing units.  Every step here is the one width
;; you give, so this does not size a step: it is the slack the U mode
;; measures with, and *cs-join-fuzz* below is derived from it.
;; nil = derive it from *cs-tol-inch* through the drawing's INSUNITS.
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;

(if (not (boundp '*cs-width-tol*)) (setq *cs-width-tol* nil))

;; What that tolerance is in INCHES when it is derived - the shop reads
;; it as 1/8".
(if (not (boundp '*cs-tol-inch*)) (setq *cs-tol-inch* 0.125))

;; NORMIESTEP only.  How far apart two ends may be, in drawing units,
;; and still count as JOINED when the parts of a U are chained together
;; - the setting that decides whether a U traced by hand is read as one
;; outline or refused as parts that do not connect.  nil = four times
;; the width tolerance; raise it for a sloppier outline, at the risk of
;; joining two ends that were meant to stay apart.
(if (not (boundp '*cs-join-fuzz*)) (setq *cs-join-fuzz* nil))

;; Dim style for the step-tread dims - the side profile's depth dims
;; use it too.  A style the drawing does not have is reported at the
;; start of the run and the current style is used instead.
(if (not (boundp '*cs-depth-dimstyle*)) (setq *cs-depth-dimstyle* "STANDARD INCHES"))

;; Dim style for the step-width dim, with the same fallback.
(if (not (boundp '*cs-width-dimstyle*)) (setq *cs-width-dimstyle* "SIDE STANDARD"))

;; Dim style for the CORNER MARK (STANDARDS.md section 2).  The sample
;; sheet carries the mark at two sizes and this is the smaller of them:
;; a step's corners are a detail inside somebody else's plan, not the
;; plan's own corners, so their mark reads one size down.  Same
;; fallback as the two above.
(if (not (boundp '*cs-mark-dimstyle*)) (setq *cs-mark-dimstyle* "STANDARD INCHES"))

;; Radius of the circle that mark is drawn on, in TEXT HEIGHTS - so it
;; tracks DIMSCALE (or the annotation scale) like the dim chain does
;; instead of the drawing's size.  Everything else about the mark is a
;; multiple of this radius, the way the sample sheet reads back.
(if (not (boundp '*cs-mark-r*)) (setq *cs-mark-r* 0.5))

;; How far off 90 a corner may sit, in DEGREES, and still be marked
;; "90%%d".  The mark ASSERTS a right angle, so a corner that is not
;; one goes unmarked: a run off a wall that leans, or a U picked with a
;; splayed arm, has a back corner that is not 90, and saying it is
;; would be a lie.  ("?" asserts nothing about the angle and is drawn
;; at any.)  20 is POOL's own tolerance, so the two tools read a corner
;; alike: it sits between the two populations -- a corner a tape calls
;; square, and a 135 bend nobody would.
(if (not (boundp '*cs-sq90-deg*)) (setq *cs-sq90-deg* 20.0))

;; Layer the dimensions are drawn on.  nil = the current layer; a layer
;; that is missing, off, frozen or locked is reported and the current
;; layer is used, so a run never draws dims where they cannot be seen.
(if (not (boundp '*cs-dim-layer*)) (setq *cs-dim-layer* nil))

;; How far the step-tread dim chain stands off the run's axis, in TEXT
;; HEIGHTS - so it tracks DIMSCALE (or the annotation scale) instead of
;; the drawing's size.  2.0 keeps the chain clear of its own text.
;; (A corner mark stands off by its own multiples - see *cs-mark-r*.)
(if (not (boundp '*cs-dim-offset*)) (setq *cs-dim-offset* 2.0))

;; How far the step-width dim sits behind the wall, in text heights, on
;; top of half the run's own width.
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

;; ...and the one the CORNER TREATMENT's size stands on.  A corner
;; radius, a cut face and the offset behind it all come off an order
;; sheet in quarter feet -- 3" to 2'-0" by 3" is the whole vocabulary --
;; so the rungs stand from the first prompt rather than waiting for a
;; second answer there will never be: a run treats one corner.  nil
;; leaves those three prompts the plain typed ones they were.
(if (not (boundp '*cs-corner-ladder*))
  (setq *cs-corner-ladder* '(3.0 24.0 3.0)))

;; NORMIESTEP only.  What the FIRST corner-treatment question offers
;; on Enter - one of "Square", "Radius", "Cut" or "NotGiven", in any
;; case.  A re-ask behind a size question still offers the answer
;; before it, as it always has; this only decides where that chain
;; starts.
(if (not (boundp '*cs-treat-default*)) (setq *cs-treat-default* "Square"))

;; NORMIESTEP only.  Which of a Cut corner's two sizes Enter asks for:
;; the "Offset" back along each line, or the "Cut" face across them.
;; Either gives the other, so this is the one the shop's order sheets
;; quote.
(if (not (boundp '*cs-cut-given-default*)) (setq *cs-cut-given-default* "Offset"))

;; What Enter answers at "Dimension the steps?".  "No" makes a bare
;; run the quick one and leaves the dims to be asked for by name.
(if (not (boundp '*cs-dims-default*)) (setq *cs-dims-default* "Yes"))

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

(setq *ns-version* "v3.21") ; printed on load and at command start so a
                           ; stale APPLOADed copy is easy to spot

;;; ------------------------- vector helpers -----------------------------

(defun ns-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun ns-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun ns-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun ns-unit (v / l)
  (if (> (setq l (sqrt (cal:dot v v))) 1e-10) (ns-scl v (/ 1.0 l))))

(defun ns-perp (v) (list (- (cadr v)) (car v) 0.0))

(defun ns-mid2 (a b) (list (* 0.5 (+ (car a) (car b)))
                           (* 0.5 (+ (cadr a) (cadr b)))
                           0.0))

;; distance from point P to the segment A-B
(defun ns-ptseg (p a b / d l2 t2)
  (setq d  (ns-vec a b)
        l2 (cal:dot d d))
  (if (< l2 1e-20)
    (distance p a)
    (progn
      (setq t2 (/ (cal:dot (ns-vec a p) d) l2))
      (cond ((< t2 0.0) (distance p a))
            ((> t2 1.0) (distance p b))
            (T (distance p (ns-add a (ns-scl d t2))))))))

;; how far point P lies beyond the ends of segment A-B (0.0 when on it)
(defun ns-beyond (p a b / d l t2)
  (setq d (ns-vec a b)
        l (sqrt (cal:dot d d)))
  (if (< l 1e-10)
    (distance p a)
    (progn
      (setq t2 (/ (cal:dot (ns-vec a p) d) (* l l)))
      (cond ((< t2 0.0) (* (- t2) l))
            ((> t2 1.0) (* (- t2 1.0) l))
            (T 0.0)))))

;; endpoint of segment S farther from PT
(defun ns-far (s pt)
  (if (> (distance (car s) pt) (distance (cadr s) pt)) (car s) (cadr s)))

;; nearest segment in SEGS to point PT
(defun ns-nearseg (segs pt / best bd d s)
  (foreach s segs
    (setq d (ns-ptseg pt (car s) (cadr s)))
    (if (or (null best) (< d bd)) (setq best s bd d)))
  best)

;;; --------------------- geometry from entities -------------------------

;; Straight segments of a POLYLINE as (p1 p2 ename), points in WCS.
;; Bulged segments are skipped - this routine is all straight lines.
(defun ns-plsegs (en / ed el cl vs bs i m out v1 v2 pr sub)
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
          v2 (nth (rem (1+ i) m) vs))
    (if (and (> (distance v1 v2) 1e-10) (equal 0.0 (nth i bs) 1e-9))
      (setq out (cons (list v1 v2 en) out)))
    (setq i (1+ i)))
  (reverse out))

(defun ns-flat (p) (list (car p) (cadr p) 0.0))

;; point on a circle: center C, radius R, angle A
(defun ns-arcpt (c r a)
  (list (+ (car c) (* r (cos a))) (+ (cadr c) (* r (sin a))) 0.0))

;; T when angle A lies on the counterclockwise span A1 -> A2
(defun ns-inspan (a a1 a2 / e)
  (setq e (- a2 a1))
  (if (< e 0.0) (setq e (+ e pi pi)))
  (setq a (- a a1))
  (if (< a 0.0) (setq a (+ a pi pi)))
  (<= a (+ e 1e-6)))

;; intersections of the circle (C,R) with the infinite line through A
;; along the UNIT direction D; a list of 0 or 2 points
(defun ns-linecirc (a d c r / f g disc)
  (setq f    (ns-vec c a)
        g    (cal:dot d f)
        disc (+ (* r r) (- (* g g) (cal:dot f f))))
  (if (>= disc 0.0)
    (progn
      (setq disc (sqrt disc))
      (list (ns-add a (ns-scl d (- (- g) disc)))
            (ns-add a (ns-scl d (+ (- g) disc)))))))

;;; U pieces: every part of a U perimeter as a uniform record so lines
;;; and corner arcs chain and trim alike -
;;;   ("S" p1 p2)                 a straight part
;;;   ("A" p1 p2 center r a1 a2)  a corner arc, counterclockwise

;; arc piece from an ARC entity, normalized from the curve's own
;; start/mid/end points and its OCS center so mirrored arcs behave
(defun ns-arcent (en / ed c r ep mp a1 a2 sw)
  (setq ed (entget en)
        c  (trans (cdr (assoc 10 ed)) en 0)
        r  (cdr (assoc 40 ed))
        ep (vlax-curve-getendpoint en)
        mp (vlax-curve-getpointatdist
             en (* 0.5 (vlax-curve-getdistatparam
                         en (vlax-curve-getendparam en))))
        a1 (angle c (vlax-curve-getstartpoint en))
        a2 (angle c ep))
  (if (not (ns-inspan (angle c mp) a1 a2))
    (setq sw a1 a1 a2 a2 sw))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list "A" (ns-arcpt c r a1) (ns-arcpt c r a2) (ns-flat c) r a1 a2))

;; arc piece from a polyline bulge segment P1 -> P2
(defun ns-bulgepc (p1 p2 b / th l r h nrm cen a1 a2)
  (setq p1  (ns-flat p1)
        p2  (ns-flat p2)
        th  (* 4.0 (atan b))
        l   (distance p1 p2)
        r   (abs (/ l (* 2.0 (sin (/ th 2.0)))))
        h   (* r (cos (/ (abs th) 2.0)))
        nrm (ns-unit (ns-perp (ns-vec p1 p2)))
        cen (ns-add (ns-mid2 p1 p2)
                    (ns-scl nrm (if (> b 0.0) h (- h)))))
  (if (> b 0.0)
    (setq a1 (angle cen p1) a2 (angle cen p2))
    (setq a1 (angle cen p2) a2 (angle cen p1)))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list "A" p1 p2 cen r a1 a2))

;; Bulged segments of a POLYLINE as arc pieces (the straight ones come
;; from ns-plsegs)
(defun ns-plarcs (en / ed el cl vs bs i m out v1 v2 pr sub)
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
          v2 (nth (rem (1+ i) m) vs))
    (if (and (> (distance v1 v2) 1e-10)
             (not (equal 0.0 (nth i bs) 1e-9)))
      (setq out (cons (ns-bulgepc v1 v2 (nth i bs)) out)))
    (setq i (1+ i)))
  (reverse out))

;; The on-piece hit of the tread line (P along U) nearest to P among
;; SIDE's pieces - the arm, and the corner treatment when there is one.
(defun ns-sidehit (p u side fuzz / best bd q pc)
  (foreach pc side
    (if (= "S" (car pc))
      (progn
        (setq q (inters p (ns-add p u) (cadr pc) (caddr pc) nil))
        (if (and q (< (ns-beyond q (cadr pc) (caddr pc)) fuzz)
                 (or (null best) (< (distance p q) bd)))
          (setq best q bd (distance p q))))
      (foreach q (ns-linecirc p u (nth 3 pc) (nth 4 pc))
        (if (and (ns-inspan (angle (nth 3 pc) q) (nth 5 pc) (nth 6 pc))
                 (or (null best) (< (distance p q) bd)))
          (setq best q bd (distance p q))))))
  best)

;; Draw a U piece record - a straight cut or a corner arc.
(defun ns-drawpc (pc)
  (if (= "S" (car pc))
    (ns-mkline (cadr pc) (caddr pc))
    (entmake (list '(0 . "ARC")
                   (cons 10 (list (car (nth 3 pc)) (cadr (nth 3 pc)) 0.0))
                   (cons 40 (nth 4 pc))
                   (cons 50 (nth 5 pc))
                   (cons 51 (nth 6 pc))))))

;; Where arm AP meets the base BS of a U, and the two legs that leave
;; it: the joint, the unit vector IN along the base, the unit vector
;; OUT along the arm, and the far end of each.  The corner piece below
;; is cut from exactly these, and the corner MARK sits on the same
;; joint, so the two read the geometry the one way.
(defun ns-ujoint (bs ap / b1 b2 fe ub ua)
  (setq b1 (if (< (ns-ptseg (car bs) (car ap) (cadr ap))
                  (ns-ptseg (cadr bs) (car ap) (cadr ap)))
             (car bs)
             (cadr bs))
        b2 (if (equal b1 (car bs)) (cadr bs) (car bs))
        fe (ns-far ap b1)
        ub (ns-unit (ns-vec b1 b2))
        ua (ns-unit (ns-vec b1 fe)))
  (if (and ub ua) (list b1 ub ua b2 fe)))

;; The back corner where arm AP meets the base BS of a U, cut OFF back
;; along each of them - KIND "Cut" gives a 45 degree diagonal, "Radius"
;; a fillet arc tangent to both.  Unlike the recess corner of a run that
;; comes off an open wall, this one is cut INTO the U, since the arms
;; are the sides of the step itself.  The piece comes back in the same
;; form as the rest of the U so the treads trim to it; nil when the
;; offset will not fit inside the corner.
(defun ns-ucorner (bs ap kind off / j b1 b2 fe ub ua t1 t2 o a1 a2 sw)
  (setq j (ns-ujoint bs ap))
  (if j
    (setq b1 (car j) ub (cadr j) ua (caddr j)
          b2 (nth 3 j) fe (nth 4 j)))
  (if (and j (> off 0.0)
           (< off (distance b1 b2))
           (< off (distance b1 fe)))
    (progn
      (setq t1 (ns-add b1 (ns-scl ub off))     ; in along the base
            t2 (ns-add b1 (ns-scl ua off)))    ; out along the arm
      (if (= kind "Radius")
        (progn
          ;; centre sits one radius off each leg, so the arc is tangent
          ;; to both; the record spans counterclockwise t1 -> t2
          (setq o  (ns-add t1 (ns-scl ua off))
                a1 (angle o t1)
                a2 (angle o t2))
          (if (< a2 a1) (setq a2 (+ a2 pi pi)))
          (if (> (- a2 a1) pi)                 ; the other way round is the arc
            (setq sw a1 a1 (- a2 pi pi) a2 sw))
          (if (< a1 0.0) (setq a1 (+ a1 pi pi) a2 (+ a2 pi pi)))
          (list "A" t1 t2 o off a1 a2))
        (list "S" t1 t2)))))

;;; -------------------------- ask helpers -------------------------------

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
(defun ns-numlist (str / toks tok i c out r a b bad)
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
      ((setq r (ns-numrange tok))
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
(defun ns-numrange (tok / p lft rgt)
  (setq p (vl-string-search "-" tok))
  (if p
    (setq lft (substr tok 1 p)
          rgt (substr tok (+ p 2)))
    (setq lft tok
          rgt tok))
  (if (and (ns-digits-p lft) (ns-digits-p rgt)
           (<= (strlen lft) 3) (<= (strlen rgt) 3)
           (<= (atoi lft) (atoi rgt)))
    (list (atoi lft) (atoi rgt))))

;; T when S is one or more of 0-9 and nothing else.
(defun ns-digits-p (s / i ok)
  (setq ok (> (strlen s) 0) i 1)
  (while (and ok (<= i (strlen s)))
    (if (not (cal:len-digit-p (substr s i 1))) (setq ok nil))
    (setq i (1+ i)))
  ok)

;; The tread line of every step that was committed, newest first, as
;; (step-number . ename).  A step's log record is (entities cum pprev n),
;; and the only LINE among those entities is its tread - the dimensions
;; that may sit beside it are DIMENSIONs.
(defun ns-treadents (log / out rec e ln)
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
(defun ns-numsay (pairs / out pr)
  (setq out "")
  (foreach pr pairs
    (setq out (strcat out (if (= out "") "" ", ")
                      (itoa (if (numberp pr) pr (car pr))))))
  out)

;; Midpoint (WCS) of a LINE entity.
(defun ns-entmid (e / ed)
  (setq ed (entget e))
  (ns-mid2 (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))

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
(defun ns-num (v dflt) (if (numberp v) v dflt))

;; A setting that has to be one of a prompt's KEYWORDS: the canonical
;; spelling S stands for, in any case, or nil for anything that is not
;; one of them, so the caller can fall back to the word it ships with.
;; ns-fkw, ns-askkw and a bare Enter all hand a default straight back
;; unchecked, and "radius" set in acaddoc.lsp must not reach the
;; corner table unspelled.
(defun ns-kwcanon (s kws / u out w)
  (setq u (if (= (type s) 'STR) (strcase s) ""))
  (foreach w kws (if (= u (strcase w)) (setq out w)))
  out)

;; A setting that has to be a NAME - a layer, a dim style: V when it is
;; a string, DFLT when it is not.  The third guard, beside ns-num's for
;; a number and ns-kwcanon's for a keyword, and the one that was
;; missing.  A name does not stay in Lisp: it reaches tblsearch, setvar
;; "CLAYER" and strcat, and every one of those is "bad argument type:
;; stringp" thrown in the middle of a run on anything else.  That is
;; reachable rather than theoretical -- LAZTUNE reads a knob SHIPPED
;; nil as "off, or a value" and so lets any atom into it, and nil in
;; *cs-dim-layer* means "the current layer" rather than "off", so a T
;; put there sails past the (and *cs-dim-layer* ...) guard and dies at
;; the tblsearch behind it.
(defun ns-name (v dflt) (if (= (type v) 'STR) v dflt))

;; A setting NAME as a note says it back: quoted when it is one, and
;; named for what it is when it is not - a note that quotes T as a name
;; reads like a layer somebody forgot to make, rather than a setting
;; nobody can use.
(defun ns-showname (v)
  (if (= (type v) 'STR) (strcat "\"" v "\"") "(not a name)"))

;; T when a prompt that DOES take keywords was answered Back - or its
;; hidden synonym Undo.  getpoint/getdist/getint hand a keyword back as
;; a string where a value would be a list or a number.
(defun ns-back-kw (v)
  (and (= (type v) 'STR) (member v '("Back" "Undo"))))

;; T when a TYPED string means "go back a step" - typed prompts cannot
;; take initget keywords, so there Back is typed like a value.
(defun ns-back-word (s)
  (and s (member (strcase s) '("B" "BACK" "U" "UNDO"))))

;; *cs-tol-inch* expressed in the drawing's units (INSUNITS); inches
;; when the drawing is unitless
(defun ns-autotol ( / iu b)
  (setq iu (getvar "INSUNITS")
        b  (ns-num *cs-tol-inch* 0.125))
  (cond ((= iu 2) (/ b 12.0))     ; feet
        ((= iu 4) (* b 25.4))     ; millimeters
        ((= iu 5) (* b 2.54))     ; centimeters
        ((= iu 6) (* b 0.0254))   ; meters
        (T        b)))            ; inches, or unitless - assume inches

(defun ns-tolerance ( )
  (if (numberp *cs-width-tol*) *cs-width-tol* (ns-autotol)))

;; How far apart two ends may be and still count as joined when the
;; parts of a U are chained together.  Never less than 1e-6: two ends
;; at the same point have to join whatever the setting says.
(defun ns-fuzz (tol)
  (max (ns-num *cs-join-fuzz* (* 4.0 tol)) 1e-6))

;; How far the step-tread dim chain stands off the run's axis.
(defun ns-dimoff (txth) (* (ns-num *cs-dim-offset* 2.0) txth))

;; How far the step-width dim sits behind the wall: half the run's own
;; width plus the standoff on top of it.
(defun ns-nestoff (w txth)
  (+ (* 0.5 w) (* (ns-num *cs-dim-nest* 1.5) txth)))

;; How far the side profile's dims stand off the flight, WIDEST being
;; the widest tread in it.
(defun ns-pgap (txth widest)
  (if (numberp *cs-profile-dimgap*)
    *cs-profile-dimgap*
    (max (* (ns-num *cs-profile-gap-txt* 4.0) txth)
         (* (ns-num *cs-profile-gap-tread* 0.75) widest))))

;; The widest tread, for spacing the side profile's dimensions.  The
;; list is empty when every logged step landed within 1e-6 of the one
;; before it -- (apply 'max nil) is an error, so a degenerate run
;; falls back to plain text-height spacing.  CORNERSTP skips its whole
;; profile in that case (CORNERSTP.lsp, "No usable tread spacing").
(defun ns-maxtread (treads)
  (if treads (apply 'max treads) 0.0))

;; annotation text height in drawing units; DIMSCALE is 0 for
;; annotative dim styles, where the annotation scale governs instead
(defun ns-txth ( / h s)
  (setq h (getvar "DIMTXT")
        s (getvar "DIMSCALE"))
  (if (or (null s) (<= s 0.0))
    (setq s (cond ((and (getvar "CANNOSCALEVALUE")
                        (> (getvar "CANNOSCALEVALUE") 0.0))
                   (/ 1.0 (getvar "CANNOSCALEVALUE")))
                  (1.0))))
  (if (and h (> (* h s) 0.0)) (* h s) 1.0))

;;; ------------------------- drawing helpers ----------------------------

(defun ns-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;; A LINE between two points given in the current UCS.  entmake keeps
;; World, so each end goes through trans on the way in.  The side
;; profile is laid out in the drafter's UCS, where its forced "_V" dims
;; measure - built in World under a turned UCS, every depth read short.
(defun ns-uline (a b)
  (ns-mkline (trans a 1 0) (trans b 1 0)))

;; Fillet arc of radius R about centre O between tangent points T1 and
;; T2.  The minor arc is taken, so a quarter-round comes out as one.
(defun ns-mkfillet (o r t1 t2 / a1 a2 sw)
  (setq a1 (angle o t1)
        a2 (angle o t2)
        sw (- a2 a1))
  (if (< sw 0.0) (setq sw (+ sw pi pi)))
  (if (> sw pi) (setq sw a1 a1 a2 a2 sw))    ; the other way round is shorter
  (entmake (list '(0 . "ARC")
                 (cons 10 (list (car o) (cadr o) 0.0))
                 (cons 40 r)
                 (cons 50 a1)
                 (cons 51 a2))))

;; Draw one side of the run: the back corner where it meets the wall at
;; E - the wall carries on along WDIR, the run heads along DIR for LEN -
;; and then the side line down to the last tread.
;;   RTYPE nil / "Square"   - a plain 90 degree side line off the wall
;;   "Radius"               - a fillet arc of radius RRAD
;;   "Cut"                  - a 45 degree diagonal, ROFF back each leg
;; Either treatment flares the mouth of the recess by that offset.
(defun ns-side (e wdir dir len rtype roff rrad / off t1 t2 o)
  (setq off (cond ((and (= rtype "Cut") roff) roff)
                  ((and (= rtype "Radius") rrad) rrad)
                  (0.0)))
  (if (>= off len)
    (progn
      (princ (strcat "\n  Note: the back corner (" (rtos off)
                     ") is deeper than the whole run (" (rtos len)
                     ") - that side is drawn square."))
      (setq off 0.0 rtype "Square")))
  (setq t1 (ns-add e (ns-scl wdir off))      ; tangent/cut point on the wall
        t2 (ns-add e (ns-scl dir off)))      ; and on the side of the run
  (cond
    ((and (= rtype "Cut") (> off 0.0))
     (ns-mkline t1 t2))
    ((and (= rtype "Radius") (> off 0.0))
     ;; centre sits one radius off each leg, so the arc is tangent to both
     (setq o (ns-add t1 (ns-scl dir off)))
     (ns-mkfillet o off t1 t2)))
  (ns-mkline t2 (ns-add e (ns-scl dir len))))

;; The corner of the LAST step of a centered (one-line) run, where the
;; side wall meets the last tread.  E is where the side wall leaves the
;; base wall, UIN the unit vector along the tread toward the run's
;; centre, DIR the way the run heads, LEN the whole run - so the
;; theoretical square corner sits at C = E + DIR x LEN.
;;   "Cut"     - a 45 degree diagonal from OFF back along the side wall
;;               to OFF in along the last tread
;;   "Radius"  - a fillet arc of radius OFF tangent to both
;; The side wall and the trimmed tread are drawn by the caller; OFF 0
;; (a square corner) draws nothing.
(defun ns-outer (e uin dir len rtype off / c t1 t2 o)
  (setq c  (ns-add e (ns-scl dir len))       ; the theoretical square corner
        t1 (ns-add c (ns-scl dir (- off)))   ; back along the side wall
        t2 (ns-add c (ns-scl uin off)))      ; in along the last tread
  (cond
    ((and (= rtype "Cut") (> off 0.0))
     (ns-mkline t1 t2))
    ((and (= rtype "Radius") (> off 0.0))
     ;; centre sits one offset off each leg, so the arc is tangent to both
     (setq o (ns-add t1 (ns-scl uin off)))
     (ns-mkfillet o off t1 t2))))

;; make dimension style NAME current, but only if it exists and is not
;; already current.  Uses ActiveX so style names containing spaces are
;; handled correctly (the -DIMSTYLE command would read a space as ENTER).
(defun ns-setstyle (name / doc)
  (if (and (ns-name name nil)
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
(defun ns-dim (style a b thru / oldl)
  (ns-setstyle style)
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
(defun ns-dimv (style a b thru / oldl)
  (ns-setstyle style)
  (if (and *cs-dim-layer* (cal:layer-usable-p *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.DIMLINEAR" "_non" a
                         "_non" b
                         "_V"
                         "_non" thru)
  (if oldl (setvar "CLAYER" oldl)))

;;; ---- the corner mark of STANDARDS.md section 2 ------------------------
;;;
;;;  A step's corners take the same mark a pool's do: a small circle on
;;;  the corner point with a RADIUS DIMENSION on that circle, its
;;;  measurement replaced by what the mark says -- "90%%d" where the
;;;  corner really is one, a boxed "?" where the sheet never said, and
;;;  a "Not Given" note on a leader off that box.  The treatment is ONE
;;;  answer for both corners of a run, so one mark carries it with a
;;;  " Typ." suffix; a mode with a single treated corner marks that one
;;;  on its own.
;;;
;;;  It is drawn in *cs-mark-dimstyle*, the SMALLER of the two sizes
;;;  the sample sheet carries, and every distance in it is a multiple
;;;  of the mark circle, the way that sheet reads back: the mark's own
;;;  text at 6.7 r, the note's leader leaving the box at 8.4 r, the
;;;  note itself at 11.4 r.

;; The mark circle's radius, in drawing units.
(defun ns-markr (txth) (* (ns-num *cs-mark-r* 0.5) txth))

;; T when the two legs meeting at a corner really are square, read at
;; the tolerance a picked outline is worth.
(defun ns-sq90p (v1 v2 / a b)
  (setq a (ns-unit v1)
        b (ns-unit v2))
  (if (and a b)
    (< (abs (cal:dot a b))
       (sin (/ (* pi (ns-num *cs-sq90-deg* 20.0)) 180.0)))))

;; The corners one treatment answer speaks for, the one a single Typ.
;; mark should prefer first: each as (point outward-direction square-p).
;; Where the modes put them:
;;
;;   LINE    the two corners of the LAST tread, where the side walls
;;           meet it.  DIR is held square to the treads, so these are
;;           90 by construction.
;;   CORNER  the ONE back corner at the wall, where the outer side
;;           leaves it -- the inner side runs straight on out of the
;;           line it continues, so there is no corner there to treat.
;;           Its angle is the angle the two picked lines make, which is
;;           whatever the pool is, 90 or not.
;;   U       the two joints where the arms meet the base, again at
;;           whatever angle they were drawn.
;;
;; Outward is the way the mark leads: the bisector pointing away from
;; the two legs, so the mark and its note land outside the step.
(defun ns-markpts (mode sp u dir wid cum corner lastinn base arm1 arm2
                   / run j out)
  (cond
    ((= mode "LINE")
     (list (list (ns-add (ns-add sp (ns-scl u (* 0.5 wid))) (ns-scl dir cum))
                 (ns-unit (ns-add u dir))
                 (ns-sq90p u dir))
           (list (ns-add (ns-add sp (ns-scl u (* -0.5 wid))) (ns-scl dir cum))
                 (ns-unit (ns-add (ns-scl u -1.0) dir))
                 (ns-sq90p u dir))))
    ((= mode "CORNER")
     (if (and lastinn (setq run (ns-unit (ns-vec corner lastinn))))
       (list (list (ns-add corner (ns-scl u wid))
                   (ns-unit (ns-add u (ns-scl run -1.0)))
                   (ns-sq90p u run)))))
    ((= mode "U")
     (foreach j (list (if (and base arm1) (ns-ujoint base arm1))
                      (if (and base arm2) (ns-ujoint base arm2)))
       (if j
         (setq out (cons (list (car j)
                               (ns-unit (ns-scl (ns-add (cadr j) (caddr j))
                                                -1.0))
                               (ns-sq90p (cadr j) (caddr j)))
                         out))))
     (reverse out))))

;; One mark: the circle on PT, and a radius dim on it that SAYS TXT
;; instead of measuring, dragged out along OUTD.  The dim style and the
;; layer both come back before it returns, so a mark cannot leave the
;; drawing in the mark's style for whatever is dimensioned next.
(defun ns-mark (pt outd txth txt / r old oldl)
  (setq r   (ns-markr txth)
        old (getvar "DIMSTYLE"))
  (if (and *cs-dim-layer* (cal:layer-usable-p *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (entmake (list '(0 . "CIRCLE")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 r)))
  (ns-setstyle *cs-mark-dimstyle*)
  (command "_.DIMRADIUS"
           (list (entlast) (trans (ns-add pt (ns-scl outd r)) 0 1))
           "_T" txt
           "_non" (trans (ns-add pt (ns-scl outd (* 6.7 r))) 0 1))
  (ns-setstyle old)
  (if oldl (setvar "CLAYER" oldl)))

;; A corner nobody recorded: the same mark asking a question instead of
;; asserting an angle, its "?" in a BOX -- which is what a negative
;; DIMGAP draws -- and the "Not Given" note on a leader off that box.
;; The gap is handed back immediately, and the run saved it at the top
;; (OLDGAP) so an Esc inside the mark cannot leave the next dimension
;; boxed too.
(defun ns-markng (pt outd txth sfx / r og oldl)
  (setq r  (ns-markr txth)
        og (getvar "DIMGAP"))
  (setvar "DIMGAP" (- (abs og)))
  (ns-mark pt outd txth (strcat "?" sfx))
  (setvar "DIMGAP" og)
  (if (and *cs-dim-layer* (cal:layer-usable-p *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.LEADER"
           "_non" (trans (ns-add pt (ns-scl outd (* 8.4 r))) 0 1)
           "_non" (trans (ns-add pt (ns-scl outd (* 11.4 r))) 0 1)
           "" "Not Given" "")
  (if oldl (setvar "CLAYER" oldl)))

;; entities created since MARK (nil = since the drawing was empty)
(defun ns-since (mark / e out)
  (setq e (if mark (entnext mark) (entnext)))
  (while e (setq out (cons e out) e (entnext e)))
  out)

;;; --------------------------- form answers -----------------------------
;;;
;;;  A form - the Calofin palette, or LAZFORM - can answer some or all
;;;  of NORMIESTEP's questions before the run starts.  It leaves them
;;;  in *ns-form* as (key . value) pairs and the question sites look
;;;  there first, so a filled-in sheet drives the whole run and a
;;;  half-filled one simply shortens it.
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
;;;  tread1..treadN feed the per-step prompts; depth1..depthN and
;;;  depthafter feed the side profile's depths; width is the one width
;;;  every step gets.  treat answers the corner-treatment question
;;;  (the hidden aliases are accepted and normalized exactly as typing
;;;  them would be), treat-sz its number - the radius, or the cut's
;;;  face/offset value, whichever cutgiven ("Offset"/"Cut") says it
;;;  is.  dims, profile and bead answer the named gates; a keyword is
;;;  checked against the live prompt's own list and falls through to
;;;  the prompt when it does not fit.  Selections and point picks are
;;;  never form-answered.
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

(setq *ns-form* nil)

;; Did the form answer KEY at all?  This is the absent/nil distinction
;; that (cdr (assoc ...)) throws away.
(defun ns-fhas (key) (if (assoc key *ns-form*) t nil))

;; The form's answer for KEY, removed from the store as it is read.
(defun ns-ftake (key / p)
  (setq p (assoc key *ns-form*))
  (setq *ns-form* (vl-remove p *ns-form*))
  (cdr p))

(defun ns-fclear () (setq *ns-form* nil))

;; The form's numeric answer for KEY, spent as it is read: the number
;; as a REAL (the way getdist hands one back), nil for anything else.
;; Only a POSITIVE number is an answer -- every prompt this stands in
;; for refuses zero and negatives, and a sheet must not talk the run
;; into what the keyboard could not (a tread of -24 drew step 1
;; outside the corner).  POOLSIDE's psd:fnum is the same rule.
(defun ns-fnum (key / v)
  (setq v (ns-ftake key))
  (if (and (numberp v) (> v 0)) (* 1.0 v)))

;; ...and such a number is taken OUT of the store before anything reads
;; it, so the question it answered is ASKED rather than read as the nil
;; ns-fnum would make of it -- nil is Enter, which ends a tread chain,
;; and a sheet's typo is not the drafter saying "done" (STANDARDS 7.5:
;; an invalid value falls through to the prompt).  Every number this
;; form carries is a length or a count and every prompt behind one
;; refuses zero and negatives, so the rule needs no list of keys.
(defun ns-fprune ()
  (setq *ns-form*
        (vl-remove-if '(lambda (pr) (and (numberp (cdr pr)) (<= (cdr pr) 0)))
                      *ns-form*)))

;; The key of a numbered question: (ns-fnkey "tread" 3) -> tread3.
(defun ns-fnkey (stem i) (read (strcat stem (itoa i))))

;; V as the question would spell it, or nil when the question does not
;; accept it at all: an answer the live prompt does not offer falls
;; through to the prompt instead of being handed on to fail later, and
;; the canonical SPELLING comes back, not the caller's, so downstream
;; (= rtype "Cut") tests keep working.
(defun ns-fkword (v kws / i n c w out)
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
(defun ns-fkw (key kws dflt / v)
  (if (ns-fhas key)
    (progn
      (setq v (ns-ftake key))
      (cond ((null v) dflt)
            ((and (= (type v) 'STR) (setq v (ns-fkword v kws))) v)))))

;; The Treatment question a form can answer: the form's word runs
;; through the same alias list and the same normalization typing it
;; would get (NG, 90, ROUNDED, DIAG and DIAGONAL all land on their
;; canonical words), nil reads as the Enter default, and a word the
;; question does not offer falls through to the prompt.  A WRAPPER
;; around the ask helper, not an argument on it: the grouped build
;; swaps that helper for the library's, so this defun is what the
;; mirror leaves alone while the ask call inside it is rewritten like
;; any other call site.
(defun ns-ftreat (subject dflt back / v)
  (cond
    ((not (ns-fhas 'treat)) (cal:asktreat subject dflt back))
    ((null (setq v (ns-ftake 'treat))) dflt)
    ((and (= (type v) 'STR)
          (setq v (ns-fkword
                    v
                    "Square Radius Cut NotGiven NG 90 ROUNDED DIAG DIAGONAL")))
     (cond ((= v "NG") "NotGiven")
           ((= v "90") "Square")
           ((= v "ROUNDED") "Radius")
           ((member v '("DIAG" "DIAGONAL")) "Cut")
           (t v)))
    (T (cal:asktreat subject dflt back))))

;; Run NORMIESTEP with a form's answers already in hand.  Nothing
;; happens here that the direct path misses: a caller may equally set
;; *ns-form* itself and call c:NORMIESTEP, which is what the tests do.
(defun ns-run-with-answers (answers)
  (setq *ns-form* answers)
  (c:NORMIESTEP)
  (ns-fclear)
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
(defun ns-ladder (last ladder) (if last nil ladder))

(defun ns-ruler-style ()
  (list (ns-num *cs-ruler-color* 3) (ns-num *cs-ruler-current-color* 7)
        (ns-num *cs-ruler-screen-x* 0.88) (ns-num *cs-ruler-row-frac* 0.042)
        (ns-num *cs-ruler-txt-frac* 0.5) (ns-num *cs-ruler-tick-frac* 0.6)
        (ns-num *cs-ruler-ring-frac* 0.26) (ns-num *cs-ruler-reach* 6.0)))

;;; --------------------------- main command -----------------------------

(defun c:NORMIESTEP ( / *error* ns-popstep ns-ask-size undoflag ss i en ed et zf
                        segs mode base side arm1 arm2 corner fuzz
                        sp u dir pt s d1 d2 f1 f2 reflen tol txth
                        wid dep n drawn p inn outp e1 e2 bey stopf
                        first1 first2 lastdep dimflag dimoff offd treatback
                        pprev oldce oldlay oldstyle oldlu oldgap slog mark
                        svcum svp svn
                        cum rec rtype roff rrad rcut mouth usquare
                        bc1 bc2 arcps pieces freep chain cure rest nxt
                        basepc side1 side2 pc qc e coff tent te1 te2
                        rsubj mcs mc msfx m outv
                        bmark bsides btreads bnums bside bdir bss pr be
                        tlist svals treads prevv nsteps drops k dv
                        wpu wpt totrun totdrop px0 cx cy
                        tt cnrs ca cb pfo pgap lastinn fsteps fkey
                        bstep bmiss rredo rl rr szv dflt)

  (defun *error* (msg)
    (ns-fclear)                     ; both exits clear the form store
    (if undoflag (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if oldstyle (ns-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlay (setvar "CLAYER" oldlay))
    (if oldlu (setvar "LUNITS" oldlu))
    ;; a NotGiven mark boxes its "?" by turning DIMGAP negative, and an
    ;; Esc inside that one command is the path that would leave every
    ;; later dimension in the drawing boxed too
    (if oldgap (setvar "DIMGAP" oldgap))
    (if rl (setq rl (cal:ruler-off rl)))
    (redraw)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nNORMIESTEP: " msg)))
    (if lzd:report (lzd:report "NORMIESTEP" *ns-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "NORMIESTEP" *ns-version*))
  (if lzd:state (lzd:state '(*ns-form*)))
  (ns-fprune)

  ;; remove the most recently drawn step and roll the state back
  ;; One corner-size prompt beside the LENGTH RULER: the same question
  ;; initget 7 and getdist asked, with the ladder of the sizes a corner
  ;; is built to standing beside it and a click on a rung for an answer.
  ;; Enter stays refused where initget 7 refused it, Back and Undo come
  ;; back as the strings ns-back-kw already reads, and the ruler is down
  ;; before the answer is used -- nothing after this question takes one.
  ;; Nested here, like ns-popstep, because the ruler it moves is rl, a
  ;; local of this command: what c:NORMIESTEP's *error* can take down is
  ;; what c:NORMIESTEP can see.
  (defun ns-ask-size (msg / szv rr)
    (setq szv nil)
    (while (null szv)
      (setq rl  (cal:ruler-show rl nil *cs-corner-ladder*)
            rr  (cal:ask-len msg "Back Undo" rl nil)
            szv (car rr)
            rl  (cadr rr))
      (if (null szv)
        (princ "\n  A size is required - type it, or click a ruler row.")))
    (setq rl (cal:ruler-off rl))
    szv)

  (defun ns-popstep ( / e)
    (if (null slog)
      (progn (princ "\n  Already at the first step.") nil)
      (progn
        (setq rec (car slog))
        (foreach e (car rec) (if (and e (entget e)) (entdel e)))
        (setq cum   (nth 1 rec)
              pprev (nth 2 rec)
              n     (nth 3 rec)
              drawn (1- drawn)
              slog  (cdr slog)
              tlist (cdr tlist))
        (redraw)
        (princ "\n  Stepping back one step.")
        T)))

  ;; ---- 0. environment checks -------------------------------------------
  (princ (strcat "\nNORMIESTEP " *ns-version*
                 " - every step the same width."))
  ;; the form's step COUNT, spent here once for the whole run: when it
  ;; is known the tread loop stops itself after that many steps
  (if (ns-fhas 'steps)
    (progn
      (setq fsteps (ns-ftake 'steps))
      (if (not (and (numberp fsteps) (> fsteps 0))) (setq fsteps nil))))
  (setq tol  (ns-tolerance)
        txth (ns-txth)
        ;; how far apart two ends may be and still count as joined
        ;; when the parts of a U are chained together
        fuzz (ns-fuzz tol))
  ;; Read distances architectural-style for the whole command: a bare
  ;; number is drawing units (inches in an inch-based drawing) and
  ;; feet-inch entry like 1'4 works whatever LUNITS was set to.
  (setq oldlu (getvar "LUNITS"))
  (setvar "LUNITS" 4)
  ;; the length ruler, not up yet: it stands beside the step tread and
  ;; step depth prompts on the current layer, and comes down again
  ;; before any prompt that does not take it and on every way out
  (setq rl (cal:ruler-new (getvar "CLAYER") (ns-ruler-style)))
  (if (not (equal (trans '(0.0 0.0 1.0) 1 0 T) '(0.0 0.0 1.0) 1e-8))
    (princ (strcat "\nWARNING: the current UCS is not parallel to the"
                   " World XY plane - results may be skewed.")))
  (if (not (cal:layer-usable-p (getvar "CLAYER")))
    (princ (strcat "\nWARNING: the current layer (" (getvar "CLAYER")
                   ") is off, frozen or locked - new steps may not"
                   " appear.")))
  (if (zerop (getvar "INSUNITS"))
    (princ (strcat "\nNote: drawing units are unitless; the width"
                   " tolerance is taken as " (rtos tol)
                   ", so ends within " (rtos fuzz) " count as joined.")))

  ;; ---- 1. selection ----------------------------------------------------
  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I" '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE"))))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
    (progn
      (princ (strcat "\nSelect the base line, the two lines of a corner,"
                     " or a U-shaped step perimeter:"))
      (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE"))))
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
       (if (> (abs (- (caddr (cdr (assoc 10 ed)))
                      (caddr (cdr (assoc 11 ed))))) 1e-6)
         (setq zf T))
       (setq segs (cons (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)) en)
                        segs)))
      ((= et "ARC")
       (setq arcps (cons (ns-arcent en) arcps)))
      (T
       (setq segs  (append (ns-plsegs en) segs)
             arcps (append (ns-plarcs en) arcps)))))
  (setq segs (reverse segs))
  (if zf
    (princ (strcat "\nWARNING: a selected line is not flat (its ends"
                   " differ in Z) - it is used as seen in plan.")))
  (cond
    ((null segs)
     (princ "\nNo straight lines in the selection.") (exit))
    ((and (= 1 (length segs)) (null arcps)) (setq mode "LINE"))
    ((and (= 2 (length segs)) (null arcps)) (setq mode "CORNER"))
    ;; a U: three straights; five when its corners are cut diagonally;
    ;; three straights plus two arcs when its corners are rounded
    ((and (member (length segs) '(3 5)) (null arcps)) (setq mode "U"))
    ((and (= 3 (length segs)) (= 2 (length arcps)))   (setq mode "U"))
    (T
     (princ (strcat "\nThat selection does not fit - NORMIESTEP takes one"
                    " line, two lines forming a corner, or a U (three"
                    " lines; five with diagonal corners; three lines and"
                    " two arcs with rounded corners)."))
     (exit)))

  ;; ---- 2. work out the run from what was selected ----------------------
  (cond

    ;; ---------- one line: the steps are centered on it ----------
    ((= mode "LINE")
     (setq base (car segs)
           sp   (ns-mid2 (car base) (cadr base))
           u    (ns-unit (ns-vec (car base) (cadr base))))
     (if (null u)
       (progn (princ "\nThe selected line has zero length.") (exit)))
     (while (null dir)
       (setq pt (getpoint (trans sp 0 1)
                          "\nPick a point on the side the steps go: "))
       (if lzd:ask (lzd:ask "\nPick a point on the side the steps go: " pt) pt)
       (if (null pt)
         (progn (princ "\nNo direction picked - nothing drawn.") (exit)))
       (setq d1 (cal:dot (ns-vec sp (trans pt 1 0)) (ns-perp u)))
       (if (< (abs d1) 1e-10)
         (princ "\nThat point is on the line - pick a point to one side.")
         (setq dir (ns-unit (ns-scl (ns-perp u) (if (< d1 0.0) -1.0 1.0))))))
     (princ "\nSteps centered on the line."))

    ;; ---------- two lines: the steps sit against the corner ----------
    ((= mode "CORNER")
     (setq d1     (car segs)
           d2     (cadr segs)
           corner (inters (car d1) (cadr d1) (car d2) (cadr d2) nil))
     (if (null corner)
       (progn (princ "\nThe two lines are parallel - no corner found.")
              (exit)))
     (while (null base)
       (setq pt (getpoint "\nPick the line the steps run OFF OF: "))
       (if lzd:ask (lzd:ask "\nPick the line the steps run OFF OF: " pt) pt)
       (if (null pt)
         (progn (princ "\nNothing picked - nothing drawn.") (exit)))
       (setq base (ns-nearseg segs (trans pt 1 0))
             side (if (equal base d1) d2 d1)))
     ;; U runs along the base, away from the corner.  Which way the run
     ;; goes is not asked and not guessed: the corner says it.  Both
     ;; lines run away from the corner into the pool, so the water is
     ;; the side they span and OUTSIDE is the other one - the run heads
     ;; away from the line it butts against, out through the wall it
     ;; comes off, into the recess it sits in.
     (setq u    (ns-unit (ns-vec corner (ns-far base corner)))
           outv (ns-unit (ns-vec corner (ns-far side corner))))
     (if (or (null u) (null outv))
       (progn (princ "\nA selected line has zero length.") (exit)))
     ;; keep DIR square to the treads so step treads measure true
     (setq dir (ns-unit (ns-scl (ns-perp u)
                                (if (< (cal:dot (ns-perp u) outv) 0.0)
                                  1.0 -1.0)))
           sp   corner)
     (princ (strcat "\nSteps against the corner, running OUT through the"
                    " picked line - the two lines say which way that is.")))

    ;; ---------- a U: the outline is drawn, fill in the treads ----------
    ;; The parts - arms, an optional back corner on each side (diagonal
    ;; cut or fillet arc), and the base - are chained end to end from one
    ;; free end to the other; the middle of the chain is the base and
    ;; each half-chain is one side's trimming boundary.  The base is the
    ;; wall the steps come off, so the run STARTS there and marches out
    ;; toward the open end of the U.
    (T
     (setq pieces (append (mapcar '(lambda (s)
                                     (list "S" (ns-flat (car s))
                                               (ns-flat (cadr s))))
                                  segs)
                          arcps))
     ;; the two free endpoints (shared with nothing) mark the arms
     (foreach pc pieces
       (foreach e (list (cadr pc) (caddr pc))
         (setq d1 0)
         (foreach qc pieces
           (if (not (eq qc pc))
             (progn
               (if (< (distance e (cadr qc)) fuzz) (setq d1 (1+ d1)))
               (if (< (distance e (caddr qc)) fuzz) (setq d1 (1+ d1))))))
         (if (zerop d1) (setq freep (cons (list pc e) freep)))))
     (if (/= 2 (length freep))
       (progn (princ (strcat "\nThose parts do not form a U - they must"
                             " chain end to end with two open ends."))
              (exit)))
     ;; walk the chain from one free end to the other
     (setq arm1 (car (car freep))
           f1   (cadr (car freep))
           chain (list arm1)
           cure  (if (< (distance f1 (cadr arm1)) fuzz)
                   (caddr arm1)
                   (cadr arm1))
           rest  (vl-remove arm1 pieces))
     (while (setq nxt (car (vl-remove-if-not
                             '(lambda (pc)
                                (or (< (distance cure (cadr pc)) fuzz)
                                    (< (distance cure (caddr pc)) fuzz)))
                             rest)))
       (setq chain (append chain (list nxt))
             cure  (if (< (distance cure (cadr nxt)) fuzz)
                     (caddr nxt)
                     (cadr nxt))
             rest  (vl-remove nxt rest)))
     (if rest
       (progn (princ "\nThose parts do not all connect - not a U.")
              (exit)))
     (setq f2     cure                          ; the other free end
           d2     (length chain)
           basepc (nth (/ d2 2) chain))         ; the middle of the chain
     (if (/= "S" (car basepc))
       (progn (princ "\nThe middle of the U (its base) must be straight.")
              (exit)))
     (setq base  (list (cadr basepc) (caddr basepc))
           u     (ns-unit (ns-vec (car base) (cadr base)))
           mouth (ns-mid2 f1 f2)                ; the open end of the U
           sp    (ns-mid2 (car base) (cadr base))) ; the base - the wall
     ;; each half of the chain is one side's boundary
     (setq i 0)
     (foreach pc chain
       (cond ((< i (/ d2 2)) (setq side1 (cons pc side1)))
             ((> i (/ d2 2)) (setq side2 (cons pc side2))))
       (setq i (1+ i)))
     (setq arm1 (list (cadr (car chain)) (caddr (car chain)))
           arm2 (list (cadr (last chain)) (caddr (last chain))))
     (if (null u)
       (progn (princ "\nThe base of the U has zero length.") (exit)))
     (setq usquare (= 3 d2))                    ; no back corners drawn yet
     (if (not usquare)
       (princ "\nU with its back corners drawn: treads trim to them."))
     ;; DIR runs from the base out toward the open end, square to the treads
     (setq dir (ns-unit (ns-scl (ns-perp u)
                                (if (< (cal:dot (ns-perp u)
                                               (ns-vec sp mouth))
                                       0.0)
                                  -1.0 1.0))))
     (princ (strcat "\nU outline: the run starts at its base - the wall -"
                    " and marches out, trimmed to its arms."))))

  ;; preview the run direction and the tread direction
  (setq reflen (distance (car base) (cadr base)))
  (grdraw (trans sp 0 1)
          (trans (ns-add sp (ns-scl dir (* 0.75 reflen))) 0 1) 4 0)
  (grdraw (trans (ns-add sp (ns-scl u (* 0.4 reflen))) 0 1)
          (trans (ns-add sp (ns-scl u (* -0.4 reflen))) 0 1) 2 0)

  ;; ---- 3. the one width every step gets --------------------------------
  ;; Asked in one loop with the corner-treatment keyword below: Back at
  ;; the treatment re-opens this width.  A form-answered width is spent
  ;; on the first pass, so the re-ask falls to the keyboard - the
  ;; go-back the user asked for.
  (setq treatback T)
  (while treatback
    (setq treatback nil)
    (if (/= mode "U")
      (progn
        ;; the width can come off the form; the prompt refuses Enter, so
        ;; nil (or anything not a number) falls back to the keyboard
        (if (ns-fhas 'width) (setq wid (ns-fnum 'width)))
        (if (not (numberp wid))
          (progn
            (initget 7)                        ; required, no zero/negative
            (setq wid (getdist
                        "\nStep width (the same for every step): "))
            (if lzd:ask (lzd:ask "\nStep width (the same for every step): " wid) wid)))))
    ;; the treatment KEYWORD is asked inside the loop so its Back can
    ;; re-open the width; the size follow-ups wait below until the
    ;; answer stands.  In a U no width came first, so Back is not
    ;; offered there (and a U with corners already drawn skips the
    ;; question entirely).
    (if (and (= mode "U") (not usquare))
      (setq rtype nil)
      (progn
        ;; the subject reads like prose, as STANDARDS.md section 2 has it
        ;; the chain reads the knob only here: a re-ask below offers
        ;; the answer before it, the way it always has
        (setq rsubj (if (= mode "LINE")
                      "the corners of the last step"
                      "the back corners")
              rtype (ns-ftreat rsubj
                               (cond ((ns-kwcanon *cs-treat-default*
                                                  '("Square" "Radius"
                                                    "Cut" "NotGiven")))
                                     ("Square"))
                               (/= mode "U")))
        (if (eq rtype 'CAL-BACK)
          (setq wid nil rtype nil treatback T)))))

  ;; ---- 3b. the corner treatment ----------------------------------------
  ;; The corners are square (90 degrees), radiused, or cut at 45
  ;; degrees - but where they sit depends on the mode.  A centered
  ;; (one-line) run puts the treatment on the LAST step's two corners,
  ;; where the side walls meet the last tread: the tread gives up the
  ;; offset at each end, the side walls stop that much short, and the
  ;; corner piece bridges the two.  Corner mode keeps its BACK corners
  ;; at the wall the run comes off, where the treatment also flares the
  ;; mouth of the recess; in a U it is cut into the corner where the arm
  ;; meets the base and the treads trim to it.  A U that already has its
  ;; back corners drawn keeps them.
  (if (and (= mode "U") (not usquare))
    (princ (strcat "\nBack corners: already drawn on the U - using them"
                   " as they are."))
    (progn
      ;; The size questions below only mean anything beside the treatment
      ;; keyword, so Back at any of them re-asks the keyword and comes
      ;; round again - Square or NotGiven then need no size at all.  The
      ;; re-ask offers no Back of its own: the width behind it settled
      ;; when the loop above let the treatment stand.
      (setq rredo T)
      (while rredo
       (setq rredo nil)
       (cond
        ((= rtype "Radius")
         ;; treat-sz is its radius; the prompt refuses Enter, so nil
         ;; falls back to the keyboard
         (if (ns-fhas 'treat-sz) (setq rrad (ns-fnum 'treat-sz)))
         (if (not (numberp rrad))
           (setq rrad (ns-ask-size (strcat "\nRadius for " rsubj
                                           " [Back]: "))))
         (if (ns-back-kw rrad)
           (progn (princ "\n  Stepping back one question.")
                  (setq rrad  nil
                        rtype (ns-ftreat rsubj rtype nil)
                        rredo T))
           (setq roff rrad)))
        ((= rtype "Cut")
         ;; the offset and the cut face are the two legs and the
         ;; hypotenuse of the same 45 degree triangle, so either one
         ;; gives the other; cutgiven says which one treat-sz is
         (setq dflt (cond ((ns-kwcanon *cs-cut-given-default*
                                       '("Offset" "Cut")))
                          ("Offset")))
         (if (null (setq fkey (ns-fkw 'cutgiven "Offset Cut" dflt)))
           (progn
             (initget "Offset Cut Back Undo")
             (setq fkey (getkword
                          (strcat "\nIs the cut given as its"
                                  " [Offset/Cut/Back] <" dflt ">: ")))
             (if lzd:ask (lzd:ask (getvar "LASTPROMPT") fkey) fkey)
             (if (null fkey) (setq fkey dflt))))
         (if (member fkey '("Back" "Undo"))
           (progn (princ "\n  Stepping back one question.")
                  (setq rtype (ns-ftreat rsubj rtype nil)
                        rredo T))
           (progn
             (if (= "Cut" fkey)
               (progn
                 (if (ns-fhas 'treat-sz) (setq rcut (ns-fnum 'treat-sz)))
                 (if (not (numberp rcut))
                   (setq rcut (ns-ask-size
                                (strcat "\nCut face length for "
                                        rsubj " [Back]: "))))
                 (if (ns-back-kw rcut)
                   (setq rcut nil rredo T)
                   (setq roff (/ rcut (sqrt 2.0)))))
               (progn
                 (if (ns-fhas 'treat-sz) (setq roff (ns-fnum 'treat-sz)))
                 (if (not (numberp roff))
                   (setq roff (ns-ask-size
                                "\nOffset back along each line [Back]: ")))
                 (if (ns-back-kw roff)
                   (setq roff nil rredo T)
                   (setq rcut (* roff (sqrt 2.0))))))
             ;; a Back on the size re-asks which of the two was given,
             ;; not the treatment keyword: that IS the question before it
             (if rredo
               (princ "\n  Stepping back one question.")
               (princ (strcat "\n  A 45 degree cut on " rsubj ": offset "
                              (rtos roff) " each way, cut face "
                              (rtos rcut) "."))))))
        ((= rtype "NotGiven")
         (princ (strcat "\n  Not Given: " rsubj " are drawn square, and"
                        " a note on the drawing says the treatment was"
                        " never recorded.")))))
      ;; a U has its arms already, so the corner is built into the sides
      ;; the treads trim to - and drawn once the run is done.  NotGiven
      ;; is not cut in: its geometry is square, like Square's.
      (if (and (= mode "U") (member rtype '("Radius" "Cut")))
        (progn
          (setq bc1 (ns-ucorner base arm1 rtype roff)
                bc2 (ns-ucorner base arm2 rtype roff))
          (if (and bc1 bc2)
            (setq side1 (cons bc1 side1)
                  side2 (cons bc2 side2))
            (progn
              (princ (strcat "\n  That back corner does not fit inside the"
                             " U - the corners are left square."))
              (setq bc1 nil bc2 nil rtype "Square")))))))

  ;; ---- 4. dimension the steps? -----------------------------------------
  (setq dflt (cond ((ns-kwcanon *cs-dims-default* '("Yes" "No"))) ("Yes")))
  (if (null (setq fkey (ns-fkw 'dims "Yes No" dflt)))
    (progn
      (initget "Yes No")
      (setq fkey (getkword (strcat "\nDimension the steps? [Yes/No] <" dflt ">: ")))
      (if lzd:ask (lzd:ask (getvar "LASTPROMPT") fkey) fkey)
      (if (null fkey) (setq fkey dflt))))
  (setq dimflag (/= "No" fkey))
  (if dimflag
    (progn
      (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
      (if (not (tblsearch "DIMSTYLE" (ns-name *cs-depth-dimstyle* "")))
        (princ (strcat "\nNote: dim style " (ns-showname *cs-depth-dimstyle*)
                       " not found - step treads use the current style.")))
      (if (not (tblsearch "DIMSTYLE" (ns-name *cs-width-dimstyle* "")))
        (princ (strcat "\nNote: dim style " (ns-showname *cs-width-dimstyle*)
                       " not found - the step width uses the current style.")))
      (if (and *cs-dim-layer* (not (cal:layer-usable-p *cs-dim-layer*)))
        (princ (strcat "\nNote: dim layer " (ns-showname *cs-dim-layer*)
                       " is missing, not drawable,"
                       " or not a layer name - using the current layer.")))))
  ;; The step-tread chain runs just off the run's axis, the way the corner
  ;; and hemisphere routines (and the shop's own example drawings) do -
  ;; NOT outside the whole run, which would drag every chain dim's
  ;; extension lines across the entire step field.
  (setq offd   (ns-dimoff txth)
        dimoff (ns-scl u offd))

  ;; ---- 5. step treads, one per step ------------------------------------
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undoflag T)))
  (setq cum 0.0 n 1 drawn 0
        pprev sp
        oldce (getvar "CMDECHO")
        oldlay (getvar "CLAYER")
        oldgap (getvar "DIMGAP"))
  (setvar "CMDECHO" 0)

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
               ((ns-fhas (ns-fnkey "tread" n))
                (setq dep (ns-fnum (ns-fnkey "tread" n))))
               (T
                ;; Undo is the old keyword, kept as a hidden synonym; the
                ;; length ruler stands round the last tread
                (setq rl  (cal:ruler-show rl lastdep (ns-ladder lastdep *cs-tread-ladder*))
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
                     (ns-popstep) (setq dep 'RETRY))
                    ((= dep "Same")
                     (if lastdep
                       (setq dep lastdep)
                       (progn (princ "\n  No previous step tread.")
                              (setq dep 'RETRY))))
                    (T (setq dep 'RETRY)))))))
           dep))
    (setq mark (entlast)
          svcum cum svp pprev svn n
          lastdep dep
          ;; each tread sits DEP past the PREVIOUS one, never a total
          p    (ns-add pprev (ns-scl dir dep))
          e1   nil
          e2   nil)
    (cond
      ;; centered on the base line
      ((= mode "LINE")
       (setq e1 (ns-add p (ns-scl u (* 0.5 wid)))
             e2 (ns-add p (ns-scl u (* -0.5 wid)))))
      ;; from the side line outward by the width.  The run sits on the
      ;; far side of the corner, so every tread meets that line past
      ;; the end of the drawn segment - which is the recess's inner
      ;; wall, not a line that had to be stretched to reach.  BEY stays
      ;; nil: there is nothing to report.
      ((= mode "CORNER")
       (setq inn (inters p (ns-add p u) (car side) (cadr side) nil))
       (if (null inn)
         (princ (strcat "\n  Step " (itoa n)
                        ": cannot reach the side line - step skipped."))
         (setq e1 inn
               e2 (ns-add inn (ns-scl u wid)))))
      ;; trimmed to the sides of the U - arm, diagonal or fillet,
      ;; whichever the tread actually lands on
      (T
       (setq e1  (ns-sidehit p u side1 fuzz)
             e2  (ns-sidehit p u side2 fuzz)
             bey 0.0)
       ;; nothing on-piece on a side: fall back to the arm extended
       (if (null e1)
         (progn
           (setq e1 (inters p (ns-add p u) (car arm1) (cadr arm1) nil))
           (if e1 (setq bey (ns-beyond e1 (car arm1) (cadr arm1))))))
       (if (null e2)
         (progn
           (setq e2 (inters p (ns-add p u) (car arm2) (cadr arm2) nil))
           (if e2 (setq bey (max bey (ns-beyond e2 (car arm2)
                                                (cadr arm2)))))))
       (cond
         ;; out past the open end of the U: the run is full
         ((and (< (cal:dot (ns-vec p f1) dir) 0.0)
               (< (cal:dot (ns-vec p f2) dir) 0.0))
          (princ (strcat "\n  Step " (itoa n) " would fall past the open"
                         " end of the U - stopping."))
          (setq e1 nil e2 nil stopf T))
         ((or (null e1) (null e2))
          (princ (strcat "\n  Step " (itoa n)
                         ": cannot reach both sides - step skipped."))
          (setq e1 nil e2 nil)))))
    (if (and e1 e2)
      (progn
        (setq cum (+ cum dep))
        (if (and bey (> bey 1e-6))
          (princ (strcat "\n    (note: a line had to be extended "
                         (rtos bey) " to meet this tread)")))
        (ns-mkline e1 e2)
        (princ (strcat "\n  Step " (itoa n) ": width " (rtos (distance e1 e2))
                       ", " (rtos dep) " past the previous tread ("
                       (rtos cum) " from the start)."))
        (if (null first1) (setq first1 e1 first2 e2))
        (if dimflag
          (ns-dim *cs-depth-dimstyle* pprev p
                  (ns-add (ns-mid2 pprev p) dimoff)))
        (setq pprev p drawn (1+ drawn)
              slog  (cons (list (ns-since mark) svcum svp svn) slog)
              tlist (cons cum tlist))))
    (setq n (1+ n)))

  ;; the tread prompts are behind us: the ruler comes down
  (setq rl (cal:ruler-off rl))

  ;; ---- 6. sides of the run, the corner treatment, and the width dim ---
  (if (> drawn 0)
    (progn
      (setq bmark (entlast))               ; the side geometry starts here
      (cond
        ;; both sides of a centered run: plain side walls, square off
        ;; the base wall, running to the last tread - the treatment sits
        ;; on the last step's corners, so the last tread gives up the
        ;; offset at each end and a corner piece bridges each side wall
        ;; to it
        ((= mode "LINE")
         ;; resolve the corner offset once for the whole run
         (setq coff (cond ((and (= rtype "Cut") roff) roff)
                          ((and (= rtype "Radius") rrad) rrad)
                          (0.0)))
         (cond
           ((<= coff 0.0))
           ((>= coff cum)
            (princ (strcat "\n  Note: the corner (" (rtos coff)
                           ") is deeper than the whole run (" (rtos cum)
                           ") - the last step is drawn square."))
            (setq coff 0.0))
           ((>= (* 2.0 coff) wid)
            (princ (strcat "\n  Note: two corners of " (rtos coff)
                           " would meet across the last tread ("
                           (rtos wid) " wide) - the last step is drawn"
                           " square."))
            (setq coff 0.0)))
         ;; trim the last tread by the offset at each end - the step
         ;; loop drew it full width and logged it with its step
         (if (> coff 0.0)
           (progn
             (setq te1  (ns-add pprev (ns-scl u (* 0.5 wid)))
                   te2  (ns-add pprev (ns-scl u (* -0.5 wid)))
                   tent nil)
             (foreach e (car (car slog))
               (if (and (null tent) e (setq ed (entget e))
                        (= "LINE" (cdr (assoc 0 ed)))
                        (or (and (equal (cdr (assoc 10 ed)) te1 1e-6)
                                 (equal (cdr (assoc 11 ed)) te2 1e-6))
                            (and (equal (cdr (assoc 10 ed)) te2 1e-6)
                                 (equal (cdr (assoc 11 ed)) te1 1e-6))))
                 (setq tent e)))
             (if tent
               (progn
                 (setq ed (entget tent)
                       p  (ns-add pprev (ns-scl u (- (* 0.5 wid) coff)))
                       pt (ns-add pprev (ns-scl u (- coff (* 0.5 wid)))))
                 (if (equal (cdr (assoc 10 ed)) te1 1e-6)
                   (setq ed (subst (cons 10 p)  (assoc 10 ed) ed)
                         ed (subst (cons 11 pt) (assoc 11 ed) ed))
                   (setq ed (subst (cons 10 pt) (assoc 10 ed) ed)
                         ed (subst (cons 11 p)  (assoc 11 ed) ed)))
                 (entmod ed))
               (progn
                 (princ (strcat "\n  Note: the last tread was not found"
                                " to trim - the sides are drawn square."))
                 (setq coff 0.0)))))
         ;; the side walls start ON the wall and stop one offset short
         ;; of the last tread (a square run goes the whole way); then
         ;; the corner pieces
         (setq e (ns-add sp (ns-scl u (* 0.5 wid))))
         (ns-mkline e (ns-add e (ns-scl dir (- cum coff))))
         (if (> coff 0.0)
           (ns-outer e (ns-scl u -1.0) dir cum rtype coff))
         (setq e (ns-add sp (ns-scl u (* -0.5 wid))))
         (ns-mkline e (ns-add e (ns-scl dir (- cum coff))))
         (if (> coff 0.0)
           (ns-outer e u dir cum rtype coff)))
        ;; BOTH sides of the recess.  The run is on the far side of
        ;; the corner from the water, so the line the treads sit
        ;; against stops dead at the wall: its inner side has to be
        ;; drawn, carrying that line on past the corner.  The outer
        ;; side is the same line OFFSET by the step width, NOT a line
        ;; square to the base - the treads all start on the leaning
        ;; line and run out from it, so a square side wall would lean
        ;; into the run and miss every tread end but the first.  Only
        ;; the outer side takes the back-corner flare; the inner one
        ;; runs straight on out of the wall it continues, so there is
        ;; no corner there to treat.  PPREV is the last tread that
        ;; actually landed, so a step taken Back cannot leave these
        ;; pointing at one that was undone.
        ((= mode "CORNER")
         (setq lastinn (inters pprev (ns-add pprev u)
                               (car side) (cadr side) nil))
         (if (null lastinn)
           (princ (strcat "\n  Note: the run does not reach the line it"
                          " sits against - no sides drawn."))
           (progn
             (ns-mkline corner lastinn)
             (ns-side (ns-add corner (ns-scl u wid))
                      u
                      (ns-unit (ns-vec corner lastinn))
                      (distance corner lastinn)
                      rtype roff rrad))))
        ;; a U has its arms drawn already - only a back corner asked for
        ;; here is new geometry
        ((and (= mode "U") bc1 bc2)
         (ns-drawpc bc1)
         (ns-drawpc bc2)))
      ;; ... and ends here: the sides and their corner pieces, which is
      ;; what AUTOBEAD wants alongside the treads.  Taken before the
      ;; note and the width dim, which are annotation, not pool lines.
      (setq bsides (ns-since bmark))
      ;; The corner mark of STANDARDS.md section 2, one size down (see
      ;; ns-mark).  The treatment is ONE answer for both corners of a
      ;; run, so one mark carries it and says " Typ."; a mode with a
      ;; single treated corner marks that one on its own.
      ;;
      ;; A corner nobody recorded is drawn square, so the sheet has to
      ;; SAY so or it reads as a measured 90 -- that is the boxed "?"
      ;; and its "Not Given" note, and "?" asserts nothing about the
      ;; angle, so it is drawn on whatever corner comes first.  The
      ;; "90%%d" mark does assert one, so it goes only on a corner that
      ;; really is square: a run off a wall that leans, or a U with a
      ;; splayed arm, is left unmarked rather than told a lie.
      (if (member rtype '("Square" "NotGiven"))
        (progn
          (setq mcs  (ns-markpts mode sp u dir wid cum corner lastinn
                                 base arm1 arm2)
                msfx (if (cdr mcs) " Typ." "")
                mc   nil)
          (foreach m mcs
            (if (and (null mc) (or (= rtype "NotGiven") (caddr m)))
              (setq mc m)))
          (if mc
            (if (= rtype "NotGiven")
              (ns-markng (car mc) (cadr mc) txth msfx)
              (ns-mark (car mc) (cadr mc) txth (strcat "90%%d" msfx))))))
      (if dimflag
        (ns-dim *cs-width-dimstyle* first1 first2
                (ns-add sp (ns-scl dir
                                   (- (ns-nestoff (distance first1 first2)
                                                  txth))))))))

  ;; ---- 6b. side profile ------------------------------------------------
  ;; The plan run gave each step's STEP TREAD; here each step's STEP
  ;; DEPTH - its vertical drop - is asked, top step first, and the
  ;; staircase silhouette is drawn in the drafter's UCS off a picked
  ;; wall-top point.  Still inside the command's undo group, and its dims use
  ;; the depth dim style like the tread chain.
  (if (> drawn 0)
    (progn
      (setq dflt (cond ((ns-kwcanon *cs-profile-default* '("Yes" "No"))) ("Yes")))
      (if (null (setq fkey (ns-fkw 'profile "Yes No" dflt)))
        (progn
          (initget "Yes No")
          (setq fkey (getkword (strcat "\nAdd a side profile? [Yes/No] <" dflt ">: ")))
          (if lzd:ask (lzd:ask (getvar "LASTPROMPT") fkey) fkey)
          (if (null fkey) (setq fkey dflt))))
      (if (/= "No" fkey)
        (progn
          ;; the treads, top step first: sort the recorded distances
          ;; from the run start ascending - the first is the first
          ;; tread, each successive difference the next
          (setq svals  (vl-sort tlist '<)
                prevv  0.0
                treads nil)
          (foreach tt svals
            (if (> (- tt prevv) 1e-6)
              (setq treads (cons (- tt prevv) treads)))
            (setq prevv tt))
          (setq treads (reverse treads)
                nsteps (length treads))
          ;; the depths, top step first, with Back (Undo, the old
          ;; keyword, is a hidden synonym): one per step PLUS one
          ;; more for the drop after the last tread, so 3 steps
          ;; take 4 depths
          ;; the depths and the pick are one chain: Back at the pick
          ;; re-opens the LAST depth rather than starting the ladder again
          (setq drops nil k 1 wpu 'RETRY)
          (while (eq wpu 'RETRY)
           (while (<= k (1+ nsteps))
            ;; depth1..depthN and depthafter can come off the form,
            ;; spent as they are read; nil reads as Enter, which the
            ;; first depth refuses - that one falls back to the
            ;; keyboard, its key now spent
            (setq fkey (if (> k nsteps) 'depthafter (ns-fnkey "depth" k)))
            (setq dv (if (ns-fhas fkey) (ns-fnum fkey) 'RETRY))
            (if (or (eq dv 'RETRY) (and (null dv) (= k 1)))
              ;; Back/Undo hidden at the first step: typing them only
              ;; gets the already-at-the-first-step feedback.  The
              ;; length ruler stands round the previous depth
              (setq rl (cal:ruler-show rl (car drops)
                                (ns-ladder (car drops) *cs-drop-ladder*))
                    rr (cal:ask-len
                         (if (= k 1)
                           "\nStep 1 - step depth (the drop): "
                           (if (> k nsteps)
                             (strcat "\nDepth after the last tread [Back] <"
                                     (rtos (car drops)) ">: ")
                             (strcat "\nStep " (itoa k)
                                     " - step depth [Back] <"
                                     (rtos (car drops)) ">: ")))
                         "Back Undo" rl nil)
                    dv (car rr)
                    rl (cadr rr)))
            (cond
              ((and (= (type dv) 'STR)
                    (or (= dv "Back") (= dv "Undo")))
               (if (= k 1)
                 (princ "\n  Already at the first step.")
                 (progn
                   (setq k (1- k) drops (cdr drops))
                   (princ "\n  Stepping back one step."))))
              ((and (null dv) (= k 1))           ; Enter, nothing to repeat
               (princ "\n  A depth is required."))
              ((null dv)                         ; Enter = same as previous
               (setq drops (cons (car drops) drops) k (1+ k)))
              (T
               (setq drops (cons dv drops) k (1+ k)))))
           ;; Where the profile goes.  It always runs DOWN AND TO THE
           ;; LEFT from the pick, so there is no side to ask about.
           ;; the depths are behind us: the ruler comes down before the pick
           (setq rl (cal:ruler-off rl))
           (initget "Back Undo")
           (setq wpu (getpoint (strcat "\nPick the top of the first tread"
                                       " for the side profile [Back]: ")))
           (if lzd:ask (lzd:ask (getvar "LASTPROMPT") wpu) wpu)
           (if (ns-back-kw wpu)
             (progn (princ "\n  Stepping back one step.")
                    (setq drops (cdr drops)
                          k     (1- k)
                          wpu   'RETRY))))
          (setq drops (reverse drops))
          (if (null wpu)
            (princ "\nNo point picked - no side profile drawn.")
            (progn
              ;; The alternating drop/tread silhouette in the
              ;; drafter's UCS, keeping the corner down its high side
              ;; at every level: the pick, then the foot of each drop.
              ;; Those corners are what the dims bind to.  UCS numbers
              ;; throughout, and World only as a line is made: "down
              ;; and to the left" is the drafter's, and the "_V" dims
              ;; measure the drop.  Laid out in World under a UCS
              ;; turned 30 degrees, a 7.5 drop was dimensioned 6.495.
              ;; WPT is WPU flattened - still UCS numbers, not the
              ;; World copy it once was.
              (setq wpt     (ns-flat wpu)
                    totrun  (apply '+ treads)
                    totdrop (apply '+ drops)
                    px0     (car wpt)
                    cx      px0
                    cy      (cadr wpt)
                    k       0
                    cnrs    (list (list cx cy 0.0)))
              (foreach tt treads
                (setq dv (nth k drops))
                ;; the drop, straight down ...
                (ns-uline (list cx cy 0.0) (list cx (- cy dv) 0.0))
                (setq cy   (- cy dv)
                      cnrs (cons (list cx cy 0.0) cnrs))
                ;; ... then the tread, running left - no dim of its
                ;; own: the depths and the overall depth say it all
                (ns-uline (list cx cy 0.0) (list (- cx tt) cy 0.0))
                (setq cx (- cx tt)
                      k  (1+ k)))
              ;; the last depth: the drop after the last tread
              (setq dv (nth k drops))
              (ns-uline (list cx cy 0.0) (list cx (- cy dv) 0.0))
              (setq cy   (- cy dv)
                    cnrs (reverse (cons (list cx cy 0.0) cnrs)))
              (if dimflag
                (progn
                  ;; Every depth dim stands the same distance right of
                  ;; the corner its drop lands on, so the dims climb up
                  ;; and to the right with the steps instead of stacking
                  ;; in one chain.  Clearing the widest tread is what
                  ;; keeps BOTH extension lines running forward, out of
                  ;; the flight; the gap on top of that is what makes
                  ;; the fan readable, and ns-pgap - *cs-profile-dimgap*
                  ;; and the two terms of its default - is what sets it
                  (setq pgap (ns-pgap txth (ns-maxtread treads))
                        pfo  (+ (ns-maxtread treads) pgap)
                        k    1)
                  (while (< k (length cnrs))
                    (setq ca (nth (1- k) cnrs)
                          cb (nth k cnrs))
                    (ns-dimv *cs-depth-dimstyle* ca cb
                             (list (+ (car cb) pfo)
                                   (* 0.5 (+ (cadr ca) (cadr cb))) 0.0))
                    (setq k (1+ k)))
                  ;; the overall depth, further out again - the whole
                  ;; diagonal, top corner to bottom corner
                  (ns-dimv *cs-depth-dimstyle* (car cnrs) (last cnrs)
                           (list (+ px0 pfo pgap)
                                 (- (cadr wpt) (* 0.5 totdrop)) 0.0))))
              (princ (strcat "\nSide profile drawn: " (itoa nsteps)
                             " step(s), " (itoa (length drops))
                             " depths, down to the left; total run "
                             (rtos totrun) ", overall depth "
                             (rtos totdrop) "."))))))))

  ;; ---- 7. done ---------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn) " step(s) drawn"
                   (if (/= mode "U")
                     (strcat ", all " (rtos wid) " wide")
                     " between the arms of the U")
                   ".")))
  (redraw)
  (if oldstyle (ns-setstyle oldstyle))
  ;; close only a group this run opened: in a drawing with UNDO off
  ;; none was, and _End on no group is an error of its own
  (if undoflag
    (progn (command "_.UNDO" "_End")
           (setq undoflag nil)))
  (if oldce (setvar "CMDECHO" oldce))
  (if oldlay (setvar "CLAYER" oldlay))
  (if oldlu (setvar "LUNITS" oldlu))
  (if oldgap (setvar "DIMGAP" oldgap))

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
             (setq dflt (cond ((ns-kwcanon *cs-bead-default* '("Yes" "No")))
                              ("Yes")))
             (if (null (setq fkey (ns-fkw 'bead "Yes No" dflt)))
               (progn
                 (initget "Yes No")
                 (setq fkey (getkword (strcat "\nBead the steps? [Yes/No] <" dflt ">: ")))
                 (if lzd:ask (lzd:ask (getvar "LASTPROMPT") fkey) fkey)
                 (if (null fkey) (setq fkey dflt))))
             (setq bstep (if (/= "No" fkey) 2 5)))
            ((= bstep 2)
             (setq btreads (ns-treadents slog)
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
                 (setq dflt (cond ((ns-kwcanon *cs-beadsides-default*
                                               '("All" "Some" "None")))
                                  ("All")))
                 (if (null (setq bside (ns-fkw 'beadsides
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
                 (princ (strcat "\n  Steps drawn: " (ns-numsay btreads)))
                 ;; ...and this one, as the string the prompt would
                 ;; have taken: "1 3 5" or "1-3".  Anything that is not
                 ;; a string is no answer at all rather than one the
                 ;; number reader would have to guess at
                 (if (ns-fhas 'beadnums)
                   (progn (setq s (ns-ftake 'beadnums))
                          (if (/= (type s) 'STR) (setq s "")))
                   (progn
                     (setq s (getstring T (strcat "\nStep numbers with"
                                                  " beaded sides (B = back): ")))
                     (if lzd:ask (lzd:ask (getvar "LASTPROMPT") s) s)))
                 (if (ns-back-word s)
                   (progn (princ "\n  Stepping back one question.")
                          (setq bstep 2))
                   (progn
                     (setq bnums (ns-numlist s)
                           bmiss (vl-remove-if
                                   '(lambda (k) (assoc k btreads)) bnums)
                           bnums (vl-remove-if-not
                                   '(lambda (k) (assoc k btreads)) bnums))
                     ;; the steps taken are read back, and a number this
                     ;; run did not draw is named -- both used to be
                     ;; dropped without a word
                     (if bmiss
                       (princ (strcat "\n  Not drawn in this run, left out:"
                                      " step " (ns-numsay bmiss) ".")))
                     (if bnums
                       (progn
                         (princ (strcat "\n  Beading the side walls of step "
                                        (ns-numsay bnums) "."))
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
             (if (ns-back-kw bdir)
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
                    (ns-fclear)
                    (autobead-build
                      bss bdir
                      bside
                      (if (= bside "Some")
                        (mapcar '(lambda (k)
                                   (ns-entmid (cdr (assoc k btreads))))
                                bnums)
                        nil)
                      ;; the last step drawn still goes over as a step
                      ;; line - it is a breakline like any other - but
                      ;; it is named here so AUTOBEAD leaves it unbeaded
                      (list (ns-entmid (cdr (last btreads)))))))))))))))
  (ns-fclear)                       ; both exits clear the form store
  (if lzd:end (lzd:end "NORMIESTEP"))
  (princ))

;;; --------------------------- tutorial ---------------------------------

(defun ns-tut-pause ( )
  (princ "\n      --- press Enter to continue ---")
  ((lambda (v) (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v))
    (getstring))
  (princ))

(defun ns-tut-text (pt h s)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 s))))

;; Walkthrough for new users: pages of what NORMIESTEP does and checks,
;; then a live demonstration drawn step by step with the same geometry
;; code the real command uses.
(defun c:TUTORIALNORMIESTEP ( / *error* undoflag oldce oldlay oldstyle org sp u dir
                                txth pt wid off n lst dep cum pprev p e1 e2
                                offd first1 first2 hw)
  (defun *error* (msg)
    (if undoflag (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if oldstyle (ns-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlay (setvar "CLAYER" oldlay))
    (if lzd:report (lzd:report "TUTORIALNORMIESTEP" *ns-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TUTORIALNORMIESTEP" *ns-version*))

  (princ (strcat "\n================ NORMIESTEP TUTORIAL " *ns-version*
                 " ================"))
  (princ "\nNORMIESTEP draws the most normal steps of all: straight,")
  (princ "\nparallel treads, every one the SAME width.")
  (ns-tut-pause)
  (princ "\nWHAT YOU SELECT DECIDES THE MODE")
  (princ "\n  ONE LINE ........ steps centered on it, on the side you pick")
  (princ "\n  TWO LINES ....... a corner: the steps sit in a recess OUTSIDE")
  (princ "\n                    it, off the line you pick - the two lines")
  (princ "\n                    themselves say which way out is")
  (princ "\n  A U ............. the outline is drawn; treads fill in,")
  (princ "\n                    trimmed to its arms.  The BASE of the U is")
  (princ "\n                    the wall: the run starts there and marches")
  (princ "\n                    out to the open end.  Its back corners may")
  (princ "\n                    already be drawn square, diagonal (5 lines)")
  (princ "\n                    or rounded (arcs / bulged polyline corners)")
  (princ "\nTHE PROMPTS, IN ORDER")
  (princ "\n  1. The step width, ONCE (skipped for a U - its arms set it)")
  (princ "\n  2. How should the corners be treated? - the one question")
  (princ "\n     every Calofin tool asks the same way:")
  (princ "\n       Square   a true 90 degree corner")
  (princ "\n       Radius   a fillet arc, you give the radius")
  (princ "\n       Cut      a 45 degree diagonal, given as its Offset or")
  (princ "\n                its Cut face length (cut = offset x root 2)")
  (princ "\n       NotGiven never recorded: drawn square, and noted on")
  (princ "\n                the drawing so it is not read as a real 90")
  (princ "\n     In one-line mode the treatment sits on the corners of")
  (princ "\n     the LAST step, where the side walls meet the last tread;")
  (princ "\n     in corner mode on the BACK corners at the wall; a U cuts")
  (princ "\n     it into its base corners (one already drawn is not")
  (princ "\n     asked).  The old words still work typed in full: 90,")
  (princ "\n     ROUNDED, DIAG and DIAGONAL.")
  (princ "\n  3. Dimension the steps? [Yes/No]")
  (princ "\n  4. Step treads, one per step, each from the previous")
  (princ "\n     tread.  Enter = done, Back = step back one (removes")
  (princ "\n     it), Same (S) = repeat the previous step tread.")
  (princ "\n  5. Add a side profile? [Yes/No] - the STEP DEPTHS, top")
  (princ "\n     step first: one per step plus the drop after the last")
  (princ "\n     tread (3 steps take 4 depths).  Then pick the top of")
  (princ "\n     the first tread - the flight always runs down and to")
  (princ "\n     the LEFT from there, so the steps rise to the right")
  (princ "\n     and the dims climb with them: each depth beside its")
  (princ "\n     own step, the overall further out, treads not dimmed.")
  (princ "\n  6. Bead the steps? [Yes/No] - every tread but the LAST is")
  (princ "\n     beaded (the line that closes the run has no riser), so")
  (princ "\n     the only question is which steps have beaded SIDE")
  (princ "\n     WALLS: [All/Some/None].  Some takes the step numbers")
  (princ "\n     (\"1 3 4\"), None leaves them bare.  Then click the")
  (princ "\n     side to bead toward and AUTOBEAD does the rest on its")
  (princ "\n     own rules.  It has to be loaded for this - the run")
  (princ "\n     says so if it is not.")
  (ns-tut-pause)
  (princ "\nWHAT IT CHECKS AND HANDLES FOR YOU")
  (princ "\n  - warns on tilted UCS / non-flat lines / unusable layer")
  (princ "\n  - bare numbers read as inches; 1'4 style works anywhere")
  (princ "\n  - corner mode keeps step treads square to the picked line,")
  (princ "\n    so a skewed corner still measures true, and draws both")
  (princ "\n    sides of the recess - the line the treads sit against")
  (princ "\n    carried past the corner, and that line offset by the width")
  (princ "\n  - U treads trim to whatever the side is at that distance -")
  (princ "\n    arm, diagonal or arc - and the run stops at the open end")
  (princ "\n  - a corner deeper than the run - or two that would meet")
  (princ "\n    across the last tread - falls back to square")
  (princ "\n  - notes when a line had to be extended to meet a tread")
  (princ "\n  - dims: the step-tread chain plus the width once; all one undo")
  (princ "\n  - beads go to AUTOBEAD, so they follow ITS rules and land")
  (princ "\n    in their own undo group - a U of their own")
  (ns-tut-pause)

  (initget "Yes No")
  (if (= "No" ((lambda (v) (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v))
                (getkword (strcat "\nDraw a demonstration in this drawing?"
                                  " [Yes/No] <Yes>: "))))
    (progn (princ "\nTutorial done - type NORMIESTEP to use it for real.")
           (exit)))
  (setq pt (getpoint "\nPick a clear spot (about 250 x 120 needed): "))
  (if lzd:ask (lzd:ask "\nPick a clear spot (about 250 x 120 needed): " pt) pt)
  (if (null pt)
    (progn (princ "\nNo spot picked - tutorial done.") (exit)))
  (setq org  (trans pt 1 0)
        txth (ns-txth)
        sp   org
        u    '(1.0 0.0 0.0)
        dir  '(0.0 1.0 0.0)
        wid  120.0
        off  9.0)
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

  (ns-mkline (ns-add sp (ns-scl u -110.0)) (ns-add sp (ns-scl u 110.0)))
  (ns-tut-text (ns-add org '(-105.0 -14.0 0.0)) (* 1.2 txth)
               "NORMIESTEP demo: one-line mode - select this wall line")
  (princ "\n[1] The WALL drawn - one-line mode.  The steps center on its")
  (princ "\n    middle, all 120 wide, marching up from it.")
  (ns-tut-pause)

  (setq pprev sp cum 0.0 n 1
        ;; the demo puts its tread chain where the command puts it -
        ;; just off the run's axis, not outside the whole run
        offd  (ns-scl u (ns-dimoff txth)))
  (foreach lst '(12.0 12.0 12.0)
    ;; the LAST tread gives up the corner offset at each end - the real
    ;; command draws it full width and trims it once the run is known
    (setq dep  lst
          p    (ns-add pprev (ns-scl dir dep))
          cum  (+ cum dep)
          hw   (if (= n 3) (- (* 0.5 wid) off) (* 0.5 wid))
          e1   (ns-add p (ns-scl u hw))
          e2   (ns-add p (ns-scl u (- hw))))
    (ns-mkline e1 e2)
    (if (null first1) (setq first1 e1 first2 e2))
    (ns-dim *cs-depth-dimstyle* pprev p
            (ns-add (ns-mid2 pprev p) offd))
    (princ (strcat "\n[" (itoa (1+ n)) "] Step " (itoa n)
                   ": 12 past the previous tread (" (rtos cum)
                   " from the wall), "
                   (if (= n 3)
                     "trimmed to 102 - 9 goes to each corner."
                     "width 120 like every other.")))
    (ns-tut-pause)
    (setq pprev p n (1+ n)))

  ;; the side walls - square off the wall, one offset short of the last
  ;; tread - and the diagonal corners on the last step
  (setq e1 (ns-add sp (ns-scl u (* 0.5 wid))))
  (ns-mkline e1 (ns-add e1 (ns-scl dir (- cum off))))
  (ns-outer e1 (ns-scl u -1.0) dir cum "Cut" off)
  (setq e2 (ns-add sp (ns-scl u (* -0.5 wid))))
  (ns-mkline e2 (ns-add e2 (ns-scl dir (- cum off))))
  (ns-outer e2 u dir cum "Cut" off)
  (ns-dim *cs-width-dimstyle* first1 first2
          (ns-add sp (ns-scl dir (- (ns-nestoff wid txth)))))
  (princ "\n[5] The SIDE WALLS close the run - square off the wall, from")
  (princ "\n    the wall to the LAST step, whose corners take the")
  (princ "\n    treatment: here CUT, so each one runs 9 back along")
  (princ "\n    its side wall and 9 in along the last tread (cut length")
  (princ "\n    9 x root 2, about 12.73).  Radius would put a fillet arc")
  (princ "\n    there instead; Square keeps the full corner.  The width")
  (princ "\n    is dimensioned once - it is the same for every step.")
  (ns-tut-pause)

  (if oldstyle (ns-setstyle oldstyle))
  (if undoflag                           ; only a group this run opened
    (progn (command "_.UNDO" "_End")
           (setq undoflag nil)))
  (setvar "CMDECHO" oldce)
  (princ "\n[6] Done.  One U removes the demo.  Try the other modes too:")
  (princ "\n    two lines of a corner, or a U outline (even one with")
  (princ "\n    rounded or diagonal back corners) - NORMIESTEP fills it in.")
  (if lzd:end (lzd:end "TUTORIALNORMIESTEP"))
  (princ))

(defun c:NORMIESTEPVER ()
  (princ (strcat "\nNORMIESTEP " *ns-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nNORMIESTEP.lsp " *ns-version*
                 " loaded - NORMIESTEP to draw plain steps,"
                 " TUTORIALNORMIESTEP to learn it.")))
(princ)
