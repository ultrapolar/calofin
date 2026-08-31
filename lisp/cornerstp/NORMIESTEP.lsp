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
;;;                      the steps sit against the corner and always run
;;;                      OUTWARD from it.  You are asked which of the two
;;;                      lines the steps run off of - the same line the
;;;                      back-corner offset is measured on; the treads run
;;;                      parallel to it and butt against the other one.
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
;;;   6.  The side lines of the run are drawn for the one-line and
;;;       corner modes.  One-line mode draws plain side walls, square
;;;       off the base wall, running from the wall to the last tread -
;;;       the treatment sits on the last step's corners, so a Radius or
;;;       Cut one stops the walls an offset short and the corner
;;;       piece finishes the trip.  In corner mode only the outer side
;;;       is drawn - with its back corner flare at the wall - since the
;;;       steps run outward from the corner and the line they sit
;;;       against closes the inner side.  That outer side runs OUTWARD
;;;       with the treads: it is the line they sit against offset by
;;;       the step width, not a line square to the base, so it still
;;;       meets every tread end where the corner is not a true 90.
;;;       The U already has its arms, so only a back corner asked for
;;;       there is drawn.
;;;   7.  Optional dimensions: the step treads chained along the run,
;;;       plus the step width once (it is the same for every step).
;;;   8.  Optionally a SIDE PROFILE: you give the STEP DEPTHS - the
;;;       vertical drops, top step first, one per step PLUS one more
;;;       for the drop after the last tread, so 3 steps take 4 depths
;;;       (Enter repeats the previous one, Back steps back) - then
;;;       pick the top of the first tread.  The flight always runs
;;;       DOWN AND TO THE LEFT from there, so there is no side to
;;;       pick.  See "The side profile" below.
;;;   9.  Finally, BEAD THE STEPS.  Every tread is beaded - that is the
;;;       assumption - so the only thing asked is which steps carry the
;;;       bead along their side walls: All of them, or Some, given by
;;;       step number.  AUTOBEAD does the work on its own rules (2"
;;;       toward the side you click, onto its Bead Track layer), so
;;;       AUTOBEAD.lsp has to be loaded; when it is not, the run says
;;;       so and finishes without beading.  The beads are their own
;;;       undo group - AutoCAD does not nest them - so one U undoes
;;;       the beads and the next undoes the steps.
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
;;;   while the dim still reads the drop, not the slope.
;;;
;;; OPTIONAL SETTINGS (set these before running the command)
;;;   *CS-WIDTH-TOL*      width tolerance in drawing units.  When nil
;;;                       (the default) it is 1/8" converted through the
;;;                       drawing's INSUNITS setting.
;;;   *CS-DEPTH-DIMSTYLE* dim style for step-tread dims (the side
;;;                       profile's dims use it too).
;;;   *CS-WIDTH-DIMSTYLE* dim style for step-width dims.
;;;   *CS-DIM-LAYER*      layer for the dimensions.  When nil (the
;;;                       default) the current layer is used.
;;;   *CS-PROFILE-DIMGAP* how far the side profile's dims stand off the
;;;                       flight, on top of the clearance the geometry
;;;                       needs.  nil (the default) is four text
;;;                       heights or three quarters of a tread,
;;;                       whichever is more, so the fan keeps its
;;;                       proportions whether or not the drawing has a
;;;                       dim scale set up.  It also sets how much
;;;                       further out again the overall depth sits.
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

;; Settings - only defined if not already set, so this file, CORNERSTP
;; and HEMISTEP stay in sync no matter which one loads first.
(if (not (boundp '*cs-width-tol*))      (setq *cs-width-tol* nil))
(if (not (boundp '*cs-dim-layer*))      (setq *cs-dim-layer* nil))
(if (not (boundp '*cs-depth-dimstyle*)) (setq *cs-depth-dimstyle* "STANDARD INCHES"))
(if (not (boundp '*cs-width-dimstyle*)) (setq *cs-width-dimstyle* "SIDE STANDARD"))
;; How far the side profile's dims stand off the flight, on top of the
;; clearance the geometry itself needs.  nil = four text heights, which
;; is what the shop's own elevations read like; raise it to open the
;; fan out further, lower it to tuck the dims in.
(if (not (boundp '*cs-profile-dimgap*)) (setq *cs-profile-dimgap* nil))

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

(setq *ns-version* "v2.8") ; printed on load and at command start so a
                           ; stale APPLOADed copy is easy to spot

;;; ------------------------- vector helpers -----------------------------

(defun ns-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun ns-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun ns-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun ns-dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun ns-unit (v / l)
  (if (> (setq l (sqrt (ns-dot v v))) 1e-10) (ns-scl v (/ 1.0 l))))

(defun ns-perp (v) (list (- (cadr v)) (car v) 0.0))

(defun ns-mid2 (a b) (list (* 0.5 (+ (car a) (car b)))
                           (* 0.5 (+ (cadr a) (cadr b)))
                           0.0))

;; distance from point P to the segment A-B
(defun ns-ptseg (p a b / d l2 t2)
  (setq d  (ns-vec a b)
        l2 (ns-dot d d))
  (if (< l2 1e-20)
    (distance p a)
    (progn
      (setq t2 (/ (ns-dot (ns-vec a p) d) l2))
      (cond ((< t2 0.0) (distance p a))
            ((> t2 1.0) (distance p b))
            (T (distance p (ns-add a (ns-scl d t2))))))))

;; how far point P lies beyond the ends of segment A-B (0.0 when on it)
(defun ns-beyond (p a b / d l t2)
  (setq d (ns-vec a b)
        l (sqrt (ns-dot d d)))
  (if (< l 1e-10)
    (distance p a)
    (progn
      (setq t2 (/ (ns-dot (ns-vec a p) d) (* l l)))
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
        g    (ns-dot d f)
        disc (+ (* r r) (- (* g g) (ns-dot f f))))
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

;; The back corner where arm AP meets the base BS of a U, cut OFF back
;; along each of them - KIND "Cut" gives a 45 degree diagonal, "Radius"
;; a fillet arc tangent to both.  Unlike the recess corner of a run that
;; comes off an open wall, this one is cut INTO the U, since the arms
;; are the sides of the step itself.  The piece comes back in the same
;; form as the rest of the U so the treads trim to it; nil when the
;; offset will not fit inside the corner.
(defun ns-ucorner (bs ap kind off / b1 b2 fe ub ua t1 t2 o a1 a2 sw)
  (setq b1 (if (< (ns-ptseg (car bs) (car ap) (cadr ap))
                  (ns-ptseg (cadr bs) (car ap) (cadr ap)))
             (car bs)
             (cadr bs))
        b2 (if (equal b1 (car bs)) (cadr bs) (car bs))
        fe (ns-far ap b1)
        ub (ns-unit (ns-vec b1 b2))
        ua (ns-unit (ns-vec b1 fe)))
  (if (and ub ua (> off 0.0)
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

;; Keyword question of STANDARDS.md section 1.  KWS is the initget list
;; (hidden aliases included, spelled ALL-CAPS so they must be typed in
;; full and cannot steal a canonical hotkey); SHOWN is the bracket text,
;; which carries only the options a click may send.  DFLT nil = an
;; answer is required.
(defun ns-askkw (msg kws shown dflt / v)
  (initget (if dflt 0 1) kws)
  (setq v (getkword (strcat "\n" msg " [" shown "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((null v) (if dflt dflt (ns-askkw msg kws shown dflt)))
        (t v)))

;; The Treatment question of STANDARDS.md section 2: "How should
;; <subject> be treated?"  SUBJECT reads like prose ("the back
;; corners").  Returns "Square", "Radius", "Cut" or "NotGiven" - the
;; old words this tool used to store, and NG, are still accepted typed
;; in full and are normalized HERE, never downstream.
(defun ns-asktreat (subject dflt / v)
  (setq v (ns-askkw (strcat "How should " subject " be treated?")
                    "Square Radius Cut NotGiven NG 90 ROUNDED DIAG DIAGONAL"
                    "Square/Radius/Cut/NotGiven"
                    dflt))
  (cond ((= v "NG") "NotGiven")
        ((= v "90") "Square")
        ((= v "ROUNDED") "Radius")
        ((member v '("DIAG" "DIAGONAL")) "Cut")
        (t v)))

;;; --------------------------- bead helpers -----------------------------

;; The step numbers typed at a prompt - "1 3 4", "1,3,4" and "1, 3 and 4"
;; all read the same.  Anything that is not a digit separates.
(defun ns-numlist (str / out tok i c)
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
;; be answered without scrolling back through the run.
(defun ns-numsay (pairs / out pr)
  (setq out "")
  (foreach pr pairs
    (setq out (strcat out (if (= out "") "" ", ") (itoa (car pr)))))
  out)

;; Midpoint (WCS) of a LINE entity.
(defun ns-entmid (e / ed)
  (setq ed (entget e))
  (ns-mid2 (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))

;;; ------------------------- setting helpers ----------------------------

;; 1/8" expressed in the drawing's units (INSUNITS); inches if unitless
(defun ns-autotol ( / iu)
  (setq iu (getvar "INSUNITS"))
  (cond ((= iu 1) 0.125)            ; inches
        ((= iu 2) (/ 0.125 12.0))   ; feet
        ((= iu 4) 3.175)            ; millimeters
        ((= iu 5) 0.3175)           ; centimeters
        ((= iu 6) 0.003175)         ; meters
        (T        0.125)))          ; unitless - assume inches

(defun ns-tolerance ( )
  (if (numberp *cs-width-tol*) *cs-width-tol* (ns-autotol)))

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

;; A note on the drawing at PT (WCS), height H.  The geometry cannot
;; say that a corner treatment was never recorded - this does.
(defun ns-note (pt h str)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 str))))

;; T when layer NAME exists and can be drawn on right now
(defun ns-layerok (name / ld f cl)
  (if (setq ld (tblsearch "LAYER" name))
    (progn
      (setq f  (cond ((cdr (assoc 70 ld))) (0))
            cl (cond ((cdr (assoc 62 ld))) (7)))
      (and (zerop (logand 1 f))
           (zerop (logand 4 f))
           (> cl 0)))))

;; make dimension style NAME current, but only if it exists and is not
;; already current.  Uses ActiveX so style names containing spaces are
;; handled correctly (the -DIMSTYLE command would read a space as ENTER).
(defun ns-setstyle (name / doc)
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

;; aligned dimension between A and B in dim style STYLE, dim line
;; passing through THRU.  Points are WCS and are translated to the
;; current UCS for the command.  "_non" defeats running osnap.
(defun ns-dim (style a b thru / oldl)
  (ns-setstyle style)
  (if (and *cs-dim-layer* (ns-layerok *cs-dim-layer*))
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
(defun ns-dimv (style a b thru / oldl)
  (ns-setstyle style)
  (if (and *cs-dim-layer* (ns-layerok *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.DIMLINEAR" "_non" (trans a 0 1)
                         "_non" (trans b 0 1)
                         "_V"
                         "_non" (trans thru 0 1))
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
(defun ns-fnum (key / v)
  (setq v (ns-ftake key))
  (if (numberp v) (* 1.0 v)))

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
(defun ns-ftreat (subject dflt / v)
  (cond
    ((not (ns-fhas 'treat)) (ns-asktreat subject dflt))
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
    (T (ns-asktreat subject dflt))))

;; Run NORMIESTEP with a form's answers already in hand.  Nothing
;; happens here that the direct path misses: a caller may equally set
;; *ns-form* itself and call c:NORMIESTEP, which is what the tests do.
(defun ns-run-with-answers (answers)
  (setq *ns-form* answers)
  (c:NORMIESTEP)
  (ns-fclear)
  (princ))

;;; --------------------------- main command -----------------------------

(defun c:NORMIESTEP ( / *error* ns-popstep undoflag ss i en ed et zf
                        segs mode base side arm1 arm2 corner fuzz
                        sp u dir pt s d1 d2 f1 f2 reflen tol txth
                        wid dep n drawn p inn outp e1 e2 bey stopf
                        first1 first2 lastdep dimflag dimoff offd
                        pprev oldce oldstyle oldlu slog mark svcum svp svn
                        cum rec rtype roff rrad rcut mouth usquare
                        bc1 bc2 arcps pieces freep chain cure rest nxt
                        basepc side1 side2 pc qc e coff tent te1 te2
                        rsubj ngp ngv
                        bmark bsides btreads bnums bside bdir bss pr be
                        tlist svals treads prevv nsteps drops k dv
                        wpu wpt totrun totdrop px0 cx cy
                        tt cnrs ca cb pfo pgap lastinn fsteps fkey)

  (defun *error* (msg)
    (ns-fclear)                     ; both exits clear the form store
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (ns-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlu (setvar "LUNITS" oldlu))
    (redraw)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nNORMIESTEP: " msg)))
    (princ))

  ;; remove the most recently drawn step and roll the state back
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
        txth (ns-txth))
  ;; Read distances architectural-style for the whole command: a bare
  ;; number is drawing units (inches in an inch-based drawing) and
  ;; feet-inch entry like 1'4 works whatever LUNITS was set to.
  (setq oldlu (getvar "LUNITS"))
  (setvar "LUNITS" 4)
  (if (not (equal (trans '(0.0 0.0 1.0) 1 0 T) '(0.0 0.0 1.0) 1e-8))
    (princ (strcat "\nWARNING: the current UCS is not parallel to the"
                   " World XY plane - results may be skewed.")))
  (if (not (ns-layerok (getvar "CLAYER")))
    (princ (strcat "\nWARNING: the current layer (" (getvar "CLAYER")
                   ") is off, frozen or locked - new steps may not"
                   " appear.")))

  ;; ---- 1. selection ----------------------------------------------------
  (princ (strcat "\nSelect the base line, the two lines of a corner,"
                 " or a U-shaped step perimeter:"))
  (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE"))))
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
  ;; endpoint fuzz for deciding what joins what
  (setq fuzz (max (* 4.0 tol) 1e-6))

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
       (if (null pt)
         (progn (princ "\nNo direction picked - nothing drawn.") (exit)))
       (setq d1 (ns-dot (ns-vec sp (trans pt 1 0)) (ns-perp u)))
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
       (if (null pt)
         (progn (princ "\nNothing picked - nothing drawn.") (exit)))
       (setq base (ns-nearseg segs (trans pt 1 0))
             side (if (equal base d1) d2 d1)))
     ;; U runs along the base, away from the corner; DIR heads away from
     ;; the base on the side the other line goes
     (setq u   (ns-unit (ns-vec corner (ns-far base corner)))
           dir (ns-unit (ns-vec corner (ns-far side corner))))
     (if (or (null u) (null dir))
       (progn (princ "\nA selected line has zero length.") (exit)))
     ;; keep DIR square to the treads so step treads measure true
     (setq dir (ns-unit (ns-scl (ns-perp u)
                                (if (< (ns-dot (ns-perp u) dir) 0.0)
                                  -1.0 1.0)))
           sp  corner)
     (princ (strcat "\nSteps against the corner, running OUTWARD from it"
                    " off the picked line.")))

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
                                (if (< (ns-dot (ns-perp u)
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
  (if (/= mode "U")
    (progn
      ;; the width can come off the form; the prompt refuses Enter, so
      ;; nil (or anything not a number) falls back to the keyboard
      (if (ns-fhas 'width) (setq wid (ns-fnum 'width)))
      (if (not (numberp wid))
        (progn
          (initget 7)                          ; required, no zero/negative
          (setq wid (getdist "\nStep width (the same for every step): "))))))

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
      ;; the subject reads like prose, as STANDARDS.md section 2 has it
      (setq rsubj (if (= mode "LINE")
                    "the corners of the last step"
                    "the back corners")
            rtype (ns-ftreat rsubj "Square"))
      (cond
        ((= rtype "Radius")
         ;; treat-sz is its radius; the prompt refuses Enter, so nil
         ;; falls back to the keyboard
         (if (ns-fhas 'treat-sz) (setq rrad (ns-fnum 'treat-sz)))
         (if (not (numberp rrad))
           (progn
             (initget 7)
             (setq rrad (getdist (strcat "\nRadius for " rsubj ": ")))))
         (setq roff rrad))
        ((= rtype "Cut")
         ;; the offset and the cut face are the two legs and the
         ;; hypotenuse of the same 45 degree triangle, so either one
         ;; gives the other; cutgiven says which one treat-sz is
         (if (null (setq fkey (ns-fkw 'cutgiven "Offset Cut" "Offset")))
           (progn
             (initget "Offset Cut")
             (setq fkey (getkword
                          (strcat "\nIs the cut given as its"
                                  " [Offset/Cut] <Offset>: ")))))
         (if (= "Cut" fkey)
           (progn
             (if (ns-fhas 'treat-sz) (setq rcut (ns-fnum 'treat-sz)))
             (if (not (numberp rcut))
               (progn
                 (initget 7)
                 (setq rcut (getdist (strcat "\nCut face length for "
                                             rsubj ": ")))))
             (setq roff (/ rcut (sqrt 2.0))))
           (progn
             (if (ns-fhas 'treat-sz) (setq roff (ns-fnum 'treat-sz)))
             (if (not (numberp roff))
               (progn
                 (initget 7)
                 (setq roff (getdist "\nOffset back along each line: "))))
             (setq rcut (* roff (sqrt 2.0)))))
         (princ (strcat "\n  A 45 degree cut on " rsubj ": offset "
                        (rtos roff) " each way, cut face "
                        (rtos rcut) ".")))
        ((= rtype "NotGiven")
         (princ (strcat "\n  Not Given: " rsubj " are drawn square, and"
                        " a note on the drawing says the treatment was"
                        " never recorded."))))
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
  (if (null (setq fkey (ns-fkw 'dims "Yes No" "Yes")))
    (progn
      (initget "Yes No")
      (setq fkey (getkword "\nDimension the steps? [Yes/No] <Yes>: "))))
  (setq dimflag (/= "No" fkey))
  (if dimflag
    (progn
      (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
      (if (not (tblsearch "DIMSTYLE" *cs-depth-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-depth-dimstyle*
                       "\" not found - step treads use the current style.")))
      (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                       "\" not found - the step width uses the current style.")))
      (if (and *cs-dim-layer* (not (ns-layerok *cs-dim-layer*)))
        (princ (strcat "\nNote: dim layer \"" *cs-dim-layer*
                       "\" is missing or not drawable - using the"
                       " current layer.")))))
  ;; The step-tread chain runs just off the run's axis, the way the corner
  ;; and hemisphere routines (and the shop's own example drawings) do -
  ;; NOT outside the whole run, which would drag every chain dim's
  ;; extension lines across the entire step field.
  (setq offd   (* 2.0 txth)
        dimoff (ns-scl u offd))

  ;; ---- 5. step treads, one per step ------------------------------------
  (command "_.UNDO" "_Begin")
  (setq undoflag T cum 0.0 n 1 drawn 0
        pprev sp
        oldce (getvar "CMDECHO"))
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
                ;; Undo is the old keyword, kept as a hidden synonym
                (initget 6 (strcat "Back" (if lastdep " Same" "") " Undo"))
                (setq dep (getdist
                            (strcat "\nStep " (itoa n)
                                    " - step tread [Back"
                                    (if lastdep "/Same" "") "]"
                                    (if lastdep
                                      (strcat " <Enter = done, Same = "
                                              (rtos lastdep) ">: ")
                                      " <Enter = done>: "))))
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
      ;; from the side line outward by the width
      ((= mode "CORNER")
       (setq inn (inters p (ns-add p u) (car side) (cadr side) nil))
       (if (null inn)
         (princ (strcat "\n  Step " (itoa n)
                        ": cannot reach the side line - step skipped."))
         (setq e1  inn
               e2  (ns-add inn (ns-scl u wid))
               bey (ns-beyond inn (car side) (cadr side)))))
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
         ((and (< (ns-dot (ns-vec p f1) dir) 0.0)
               (< (ns-dot (ns-vec p f2) dir) 0.0))
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
        ;; The outer side only - the steps run outward from the
        ;; corner, so the line they sit against closes the inner side
        ;; already.  That outer side is the line they sit against
        ;; OFFSET by the step width, NOT a line square to the base:
        ;; the treads all start on the leaning line and run outward
        ;; from it, so a square side wall would lean into the run and
        ;; miss every tread end but the first.  PPREV is the last
        ;; tread that actually landed, so a step taken Back cannot
        ;; leave this pointing at one that was undone.
        ((= mode "CORNER")
         (setq lastinn (inters pprev (ns-add pprev u)
                               (car side) (cadr side) nil))
         (if (null lastinn)
           (princ (strcat "\n  Note: the run does not reach the line it"
                          " sits against - no outer side drawn."))
           (ns-side (ns-add corner (ns-scl u wid))
                    u
                    (ns-unit (ns-vec corner lastinn))
                    (distance corner lastinn)
                    rtype roff rrad)))
        ;; a U has its arms drawn already - only a back corner asked for
        ;; here is new geometry
        ((and (= mode "U") bc1 bc2)
         (ns-drawpc bc1)
         (ns-drawpc bc2)))
      ;; ... and ends here: the sides and their corner pieces, which is
      ;; what AUTOBEAD wants alongside the treads.  Taken before the
      ;; note and the width dim, which are annotation, not pool lines.
      (setq bsides (ns-since bmark))
      ;; A corner nobody recorded is drawn square, so the drawing must
      ;; say so or it reads as a measured 90.  One note carries both
      ;; corners - they share the one answer - and it sits just outside
      ;; the corner it speaks for.
      (if (= rtype "NotGiven")
        (progn
          (cond
            ((= mode "LINE")
             (setq ngp  (ns-add (ns-add sp (ns-scl u (* 0.5 wid)))
                                (ns-scl dir cum))
                   ngv  (ns-unit (ns-add u dir))))
            ((= mode "CORNER")
             (setq ngp (ns-add corner (ns-scl u wid))
                   ngv u))
            (T
             (setq ngp (ns-mid2 (car base) (cadr base))
                   ngv (ns-scl dir -1.0))))
          (ns-note (ns-add ngp (ns-scl ngv (* 2.0 txth))) txth
                   "CORNERS NOT GIVEN - DRAWN SQUARE")))
      (if dimflag
        (ns-dim *cs-width-dimstyle* first1 first2
                (ns-add sp (ns-scl dir (- (+ (* 0.5 (distance first1 first2))
                                             (* 1.5 txth)))))))))

  ;; ---- 6b. side profile ------------------------------------------------
  ;; The plan run gave each step's STEP TREAD; here each step's STEP
  ;; DEPTH - its vertical drop - is asked, top step first, and the
  ;; staircase silhouette is drawn in world X/Y off a picked wall-top
  ;; point.  Still inside the command's undo group, and its dims use
  ;; the depth dim style like the tread chain.
  (if (> drawn 0)
    (progn
      (if (null (setq fkey (ns-fkw 'profile "Yes No" "Yes")))
        (progn
          (initget "Yes No")
          (setq fkey (getkword "\nAdd a side profile? [Yes/No] <Yes>: "))))
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
          (setq drops nil k 1)
          (while (<= k (1+ nsteps))
            ;; depth1..depthN and depthafter can come off the form,
            ;; spent as they are read; nil reads as Enter, which the
            ;; first depth refuses - that one falls back to the
            ;; keyboard, its key now spent
            (setq fkey (if (> k nsteps) 'depthafter (ns-fnkey "depth" k)))
            (setq dv (if (ns-fhas fkey) (ns-fnum fkey) 'RETRY))
            (if (or (eq dv 'RETRY) (and (null dv) (= k 1)))
              (if (= k 1)
                (progn
                  (initget 7 "Back Undo")
                  (setq dv (getdist "\nStep 1 - step depth (the drop): ")))
                (progn
                  (initget 6 "Back Undo")
                  (setq dv (getdist
                             (if (> k nsteps)
                               (strcat "\nDepth after the last tread [Back] <"
                                       (rtos (car drops)) ">: ")
                               (strcat "\nStep " (itoa k)
                                       " - step depth [Back] <"
                                       (rtos (car drops)) ">: ")))))))
            (cond
              ((and (= (type dv) 'STR)
                    (or (= dv "Back") (= dv "Undo")))
               (if (= k 1)
                 (princ "\n  Already at the first step.")
                 (progn
                   (setq k (1- k) drops (cdr drops))
                   (princ "\n  Stepping back one step."))))
              ((null dv)                         ; Enter = same as previous
               (setq drops (cons (car drops) drops) k (1+ k)))
              (T
               (setq drops (cons dv drops) k (1+ k)))))
          (setq drops (reverse drops))
          ;; Where the profile goes.  It always runs DOWN AND TO THE
          ;; LEFT from the pick, so there is no side to ask about.
          (setq wpu (getpoint (strcat "\nPick the top of the first tread"
                                      " for the side profile: ")))
          (if (null wpu)
            (princ "\nNo point picked - no side profile drawn.")
            (progn
              ;; The alternating drop/tread silhouette in world X/Y,
              ;; keeping the corner down its high side at every level:
              ;; the pick, then the foot of each drop.  Those corners
              ;; are what the dims bind to.
              (setq wpt     (ns-flat (trans wpu 1 0))
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
                (ns-mkline (list cx cy 0.0) (list cx (- cy dv) 0.0))
                (setq cy   (- cy dv)
                      cnrs (cons (list cx cy 0.0) cnrs))
                ;; ... then the tread, running left - no dim of its
                ;; own: the depths and the overall depth say it all
                (ns-mkline (list cx cy 0.0) (list (- cx tt) cy 0.0))
                (setq cx (- cx tt)
                      k  (1+ k)))
              ;; the last depth: the drop after the last tread
              (setq dv (nth k drops))
              (ns-mkline (list cx cy 0.0) (list cx (- cy dv) 0.0))
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
                  ;; the fan readable, and *cs-profile-dimgap* sets it.
                  ;; four text heights, or three quarters of a tread -
                  ;; whichever is more, so the fan keeps its proportions
                  ;; whether or not the drawing has a dim scale set up
                  (setq pgap (cond ((numberp *cs-profile-dimgap*)
                                    *cs-profile-dimgap*)
                                   ((max (* 4.0 txth)
                                         (* 0.75 (apply 'max treads)))))
                        pfo  (+ (apply 'max treads) pgap)
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
  (command "_.UNDO" "_End")
  (if oldce (setvar "CMDECHO" oldce))
  (if oldlu (setvar "LUNITS" oldlu))
  (setq undoflag nil)

  ;; ---- 8. bead the steps -----------------------------------------------
  ;; AUTOBEAD does the beading, on its own rules and in its own undo
  ;; group - which is why this sits outside ours: AutoCAD does not nest
  ;; undo groups, so one U undoes the beads and the next undoes the
  ;; steps.  Every tread is beaded; the only question left is which
  ;; steps carry the bead along their side walls, and that is answered
  ;; by step number here instead of by clicking each one.
  (if (> drawn 0)
    (if (not (boundp 'autobead-build))
      (princ (strcat "\nAUTOBEAD is not loaded - APPLOAD AUTOBEAD.lsp"
                     " if you want these steps beaded."))
      (progn
        (if (null (setq fkey (ns-fkw 'bead "Yes No" "Yes")))
          (progn
            (initget "Yes No")
            (setq fkey (getkword "\nBead the steps? [Yes/No] <Yes>: "))))
        (if (/= "No" fkey)
          (progn
            (setq btreads (ns-treadents slog)
                  bnums   nil)
            (if (null btreads)
              (princ "\nNo tread lines to bead.")
              (progn
                ;; every tread is beaded - the side walls are the question
                (initget "All Some")
                (setq bside (cond ((getkword (strcat "\nWhich steps have"
                                                     " beaded side walls?"
                                                     " [All/Some] <All>: ")))
                                  ("All")))
                (if (= bside "Some")
                  (progn
                    (princ (strcat "\n  Steps drawn: "
                                   (ns-numsay btreads)))
                    (setq bnums (ns-numlist
                                  (getstring T (strcat "\nStep numbers with"
                                                       " beaded sides: "))))
                    (setq bnums (vl-remove-if-not
                                  '(lambda (k) (assoc k btreads)) bnums))
                    (if (null bnums)
                      (progn
                        (princ (strcat "\n  No step numbers recognized -"
                                       " beading every side wall full"
                                       " length."))
                        (setq bside "All")))))
                (setq bdir (getpoint "\nClick the side to bead toward: "))
                (if (null bdir)
                  (princ "\nNo direction picked - nothing beaded.")
                  (progn
                    ;; the treads, the sides and their corner pieces, and
                    ;; the line(s) the run came off: the pool lines of
                    ;; this pocket, which is what AUTOBEAD beads
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
                      (= bside "Some")
                      (if (= bside "Some")
                        (mapcar '(lambda (k)
                                   (ns-entmid (cdr (assoc k btreads))))
                                bnums)
                        nil)))))))))))
  (ns-fclear)                       ; both exits clear the form store
  (princ))

;;; --------------------------- tutorial ---------------------------------

(defun ns-tut-pause ( )
  (princ "\n      --- press Enter to continue ---")
  (getstring)
  (princ))

(defun ns-tut-text (pt h s)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 s))))

;; Walkthrough for new users: pages of what NORMIESTEP does and checks,
;; then a live demonstration drawn step by step with the same geometry
;; code the real command uses.
(defun c:TUTORIALNORMIESTEP ( / *error* undoflag oldce oldstyle org sp u dir
                                txth pt wid off n lst dep cum pprev p e1 e2
                                offd first1 first2 hw)
  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (ns-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (princ))

  (princ (strcat "\n================ NORMIESTEP TUTORIAL " *ns-version*
                 " ================"))
  (princ "\nNORMIESTEP draws the most normal steps of all: straight,")
  (princ "\nparallel treads, every one the SAME width.")
  (ns-tut-pause)
  (princ "\nWHAT YOU SELECT DECIDES THE MODE")
  (princ "\n  ONE LINE ........ steps centered on it, on the side you pick")
  (princ "\n  TWO LINES ....... a corner: the steps sit against it and run")
  (princ "\n                    OUTWARD, off the line you pick")
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
  (princ "\n     it), Same = repeat the previous step tread.")
  (princ "\n  5. Add a side profile? [Yes/No] - the STEP DEPTHS, top")
  (princ "\n     step first: one per step plus the drop after the last")
  (princ "\n     tread (3 steps take 4 depths).  Then pick the top of")
  (princ "\n     the first tread - the flight always runs down and to")
  (princ "\n     the LEFT from there, so the steps rise to the right")
  (princ "\n     and the dims climb with them: each depth beside its")
  (princ "\n     own step, the overall further out, treads not dimmed.")
  (princ "\n  6. Bead the steps? [Yes/No] - every tread is beaded, so")
  (princ "\n     the only question is which steps have beaded SIDE")
  (princ "\n     WALLS: [All/Some], and Some takes the step numbers")
  (princ "\n     (\"1 3 4\").  Then click the side to bead toward, and")
  (princ "\n     AUTOBEAD does the rest on its own rules.  It has to be")
  (princ "\n     loaded for this - the run says so if it is not.")
  (ns-tut-pause)
  (princ "\nWHAT IT CHECKS AND HANDLES FOR YOU")
  (princ "\n  - warns on tilted UCS / non-flat lines / unusable layer")
  (princ "\n  - bare numbers read as inches; 1'4 style works anywhere")
  (princ "\n  - corner mode keeps step treads square to the picked line,")
  (princ "\n    so a skewed corner still measures true")
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
  (if (= "No" (getkword (strcat "\nDraw a demonstration in this drawing?"
                                " [Yes/No] <Yes>: ")))
    (progn (princ "\nTutorial done - type NORMIESTEP to use it for real.")
           (exit)))
  (setq pt (getpoint "\nPick a clear spot (about 250 x 120 needed): "))
  (if (null pt)
    (progn (princ "\nNo spot picked - tutorial done.") (exit)))
  (setq org  (trans pt 1 0)
        txth (ns-txth)
        sp   org
        u    '(1.0 0.0 0.0)
        dir  '(0.0 1.0 0.0)
        wid  120.0
        off  9.0)
  (command "_.UNDO" "_Begin")
  (setq undoflag T
        oldce (getvar "CMDECHO")
        oldstyle (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)

  (ns-mkline (ns-add sp (ns-scl u -110.0)) (ns-add sp (ns-scl u 110.0)))
  (ns-tut-text (ns-add org '(-105.0 -14.0 0.0)) (* 1.2 txth)
               "NORMIESTEP demo: one-line mode - select this wall line")
  (princ "\n[1] The WALL drawn - one-line mode.  The steps center on its")
  (princ "\n    middle, all 120 wide, marching up from it.")
  (ns-tut-pause)

  (setq pprev sp cum 0.0 n 1
        offd  (ns-scl u (+ (* 0.5 wid) (* 2.0 txth))))
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
          (ns-add sp (ns-scl dir (- (+ (* 0.5 wid) (* 1.5 txth))))))
  (princ "\n[5] The SIDE WALLS close the run - square off the wall, from")
  (princ "\n    the wall to the LAST step, whose corners take the")
  (princ "\n    treatment: here CUT, so each one runs 9 back along")
  (princ "\n    its side wall and 9 in along the last tread (cut length")
  (princ "\n    9 x root 2, about 12.73).  Radius would put a fillet arc")
  (princ "\n    there instead; Square keeps the full corner.  The width")
  (princ "\n    is dimensioned once - it is the same for every step.")
  (ns-tut-pause)

  (if oldstyle (ns-setstyle oldstyle))
  (command "_.UNDO" "_End")
  (setq undoflag nil)
  (setvar "CMDECHO" oldce)
  (princ "\n[6] Done.  One U removes the demo.  Try the other modes too:")
  (princ "\n    two lines of a corner, or a U outline (even one with")
  (princ "\n    rounded or diagonal back corners) - NORMIESTEP fills it in.")
  (princ))

(defun c:NORMIESTEPVER ()
  (princ (strcat "\nNORMIESTEP " *ns-version*))
  (princ))

(princ (strcat "\nNORMIESTEP.lsp " *ns-version*
               " loaded - NORMIESTEP to draw plain steps,"
               " TUTORIALNORMIESTEP to learn it."))
(princ)
