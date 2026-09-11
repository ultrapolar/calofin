;;; ===================================================================
;;; ABLOBF.lsp  --  the line of best fit through points, as a POLYLINE
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  ABLOBF     fit an open run of arcs and lines through the
;;;                       points, between two ends you pick
;;;            ABLOBFVER  print the loaded version
;;;
;;; LOBF's bigger sibling.  LOBF answers a row of points with ONE
;;; STRAIGHT LINE; ABLOBF answers them with a POLYLINE - arcs and lines
;;; threaded through the points the way ABHD threads a pool perimeter,
;;; but OPEN.  A wall that bows, a coping run round one end of a pool,
;;; a bench or a step nose: anything the points trace that is not a
;;; closed loop and is not straight.
;;;
;;; WHAT MAKES IT DIFFERENT FROM ABHD.  ABHD fits a loop, and a loop
;;; needs no ends: it closes on itself and the seam is the only joint
;;; that has to be argued about.  A run that does not close has TWO
;;; ends, and nothing in a cloud of points says which they are - so
;;; ABLOBF asks.  Click the point the run starts at and the point it
;;; ends at, or type the survey numbers they already carry; Enter takes
;;; the farthest-apart pair, which is right for a run that does not
;;; double back and wrong exactly when it does.  Everything else is
;;; ordered BETWEEN those two: a nearest-neighbour walk from the start,
;;; the end forced last, then 2-opt uncrossing with both ends pinned.
;;;
;;; WHAT COUNTS AS A POINT - ABHD's survey classifier:
;;;   * an INSERT of the survey point block ("ab_pt"), on any layer;
;;;     the number attribute it carries names it in reports AND is what
;;;     you can type instead of clicking an end
;;;   * a plain POINT entity on ANY layer - the selection is explicit,
;;;     so there is nothing to guess at
;;;   * any other INSERT sitting on the POINTS layer
;;; Nothing else.  ABLOBF reads no drawn geometry at all: the order of
;;; the run comes from the two ends and the walk between them, so a
;;; window dragged over the whole sheet picks up the survey and leaves
;;; what is drawn alone.
;;;
;;; HELD POINTS: the user may declare points that must be held
;;; ABSOLUTELY - control shots, tie-ins, anything measured as an exact
;;; position.  A held point is never buried inside a span, so every
;;; span ends ON it and the fitted run passes through it exactly, in
;;; every candidate; it costs nothing from the miss allowance and the
;;; tangency window still applies at its joint (it is not a corner).
;;;
;;; The FITTER is ABHD's, walked in a straight line instead of round a
;;; loop: there is no seam, no closing span and no start tangent to
;;; arrive back at, so the first span starts free and the last simply
;;; ends at the final point.  The two ends of the run are free kinks by
;;; construction, and sharp corners are only ever flagged on interior
;;; points.  Everything else is the loop walker's, unchanged - the
;;; window widening, the exact-arc preference, the floating-arc rule
;;; and the nice-radius snap.
;;;
;;; And everything else is ABHD's behaviour, kept on purpose: the miss
;;; allowance, declared straight stretches and sharp corners, the curve
;;; cap with its relaxing refit, nice radii, and the three candidates
;;; (tight / as asked / few) drawn side by side to pick from.  The kept
;;; run lands on the POOL layer like ABHD's, as an OPEN polyline, so
;;; the rest of the toolset can read it.
;;; ===================================================================

;; ---- configuration -------------------------------------------------
;;  Every value ABLOBF reads that someone might want to change lives in
;;  this block, and nowhere else in the file.  Edit one and APPLOAD the
;;  file again; to try a value for one session, type the setq at the
;;  command line, because every knob is read when the command runs.
(setq *ablobf-version*   "v1.0")     ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it
(setq *ABL-POOL-LAYER*   "POOL")     ; layer the kept run ends up on -
                                    ; ABHD's, so the rest of the
                                    ; toolset can read the result
(setq *ABL-POINT-LAYER*  "POINTS")   ; layer whose POINTs/INSERTs are
                                    ; always points
(setq *ABL-POINT-BLOCK*  "ab_pt")    ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq *ABL-OUT-LAYER*    "ABLOBF-FIT")  ; layer the candidate fits go on
(setq *ABL-MISS-LAYER*   "FGStep")   ; layer the "could not hold this
                                    ; point" rings go on; ABLOBF stamps
                                    ; its objects and only erases its
                                    ; own (see abl:tag-mine)
(setq *ABL-MISS-RADIUS*  4.0)        ; radius of those rings (4 inches)
(setq *ABL-PT-TAG*       "number")   ; attribute tag on the point block
                                    ; naming the point, as in "Pt.17"
(setq *ABL-WALL-LAYER*   "POOL-WALLS") ; layer for the dashed markers of
                                    ; declared straight stretches
(setq *ABL-TOL-MAX*      2.0)        ; hard ceiling on the max-distance
                                    ; prompt (2 inches)
(setq *ABL-COMPARE*                  ; the three candidate fits offered:
  '(("tight" 1 "red"    "most curves - least error")
    ("asked" 2 "yellow" "as asked")
    ("few"   4 "cyan"   "fewest curves - still within the distance")))
                                    ; same three aims as ABHD: "tight"
                                    ; fits to *ABL-TIGHT-TOL* with no
                                    ; miss allowance and no cap;
                                    ; "asked" is the settings as
                                    ; typed; "few" lifts the miss
                                    ; allowance so arcs run as long as
                                    ; the typed distance permits
(setq *ABL-TIGHT-TOL*    0.01)       ; the "tight" candidate's accuracy
                                    ; target (units)
(setq *ABL-EXACT-EPS*    0.001)      ; "exactly on" threshold (units)
(setq *ABL-FIT-EPS*      0.01)       ; an arc through an interior point
                                    ; must pass within twice this of it
                                    ; to count as anchored
(setq *ABL-ON-EPS*       0.25)       ; a point within this of the result
                                    ; counts as ON it; only points off
                                    ; by more eat into the allowance
(setq *ABL-MISS-PCT*     0.15)       ; share of the points (rounded UP)
                                    ; that may sit off the result by up
                                    ; to the tolerance
(setq *ABL-CORNER-ANG*   (/ pi 4.0)) ; a point that turns more than this
                                    ; (45 deg) is a sharp corner: it
                                    ; may start or end a span but never
                                    ; gets buried inside one
(setq *ABL-NICE-RADII* '(12.0 6.0 1.0)) ; preferred arc-radius tiers,
                                    ; tried in order: whole feet, half
                                    ; feet, whole inches
(setq *ABL-TANG-TOL* (/ pi 22.5))    ; wiggle room from perfect tangency
                                    ; at each joint (8 degrees)
(setq *ABL-TANG-STEPS* '(1.0 1.25 1.5)) ; when nothing fits inside the
                                    ; tangent window, stretch it by
                                    ; these multiples before falling
                                    ; back to a one-point stub
(setq *ABL-ARC-SLACK* (/ pi 3.0))    ; how much further than its own
                                    ; points actually turn one arc may
                                    ; sweep (60 degrees).  An arc is
                                    ; allowed to curve about as much as
                                    ; the run of points it covers
                                    ; curves, and no more - which is
                                    ; what stops a shaky survey coming
                                    ; back as a chain of loops.  A span
                                    ; between two neighbouring points
                                    ; covers no turn at all, so it gets
                                    ; the slack alone.
(setq *ABL-DROP-PCT*     0.10)       ; share of the points (rounded UP)
                                    ; the fit may give up on entirely:
                                    ; left further off than the max
                                    ; distance, counted as "not held"
                                    ; and ringed in the drawing.  Spent
                                    ; only where the walk would
                                    ; otherwise shatter into one-point
                                    ; stubs, and only when each point
                                    ; given up buys at least two more
                                    ; points of span.  Declared
                                    ; corners, stretch points and held
                                    ; points are never given up, and
                                    ; the "tight" candidate is granted
                                    ; none of this at all.
(setq *ABL-DROP-MULT*    2.0)        ; how far past the max distance a
                                    ; point has to be before the fit
                                    ; may give up on it at all - what
                                    ; separates a bad shot from a
                                    ; feature.  A point that misses by
                                    ; a little is still fought for and
                                    ; still stops the span, exactly as
                                    ; before.
(setq *ABL-SNAP-EPS*     0.02)       ; a nice-radius snap may move the
                                    ; covered points at most this far
                                    ; beyond where they already sat
(setq *ABL-CHAIN-FUZZ*   1.0e-4)     ; endpoint-matching fuzz for
                                    ; chaining sketch segments
(setq *ABL-FLOAT-GAIN*   2)          ; an arc that floats between the
                                    ; points (its middle on no survey
                                    ; point) is taken only when it
                                    ; covers at least this many more
                                    ; points than the longest arc that
                                    ; passes exactly through one
(setq *ABL-DROP-GAIN*    2)          ; and every point given up must buy
                                    ; at least this many more points of
                                    ; span, or it is held after all
(setq *ABL-ON-FRAC*      0.25)       ; the on-the-shape threshold scales
                                    ; with the distance typed: this
                                    ; fraction of it, or *ABL-ON-EPS*,
                                    ; whichever is larger.  If 4 inches
                                    ; of error is accepted, a point an
                                    ; inch off is plainly still ON the
                                    ; shape - counting it as a miss
                                    ; would burn the whole allowance on
                                    ; the first span
(setq *ABL-ANCHOR-EPS*   (* 2.0 *ABL-FIT-EPS*)) ; an arc "passes
                                    ; through" an interior survey point
                                    ; when the point sits within this
                                    ; of it - twice the fit epsilon, so
                                    ; a nice-radius snap of a hair
                                    ; still counts as anchored
(setq *ABL-CAP-RELAX*    1.4)        ; when a fit needs more curves
                                    ; than the cap allows, the whole
                                    ; run is refitted with the distance
                                    ; multiplied by this, again and
                                    ; again, until the cap holds.
                                    ; Nearer 1 = finer steps, more
                                    ; refits, a result closer to the cap
(setq *ABL-CAP-TRIES*    40)         ; ...and at most this many refits;
                                    ; the fewest-curves result seen is
                                    ; kept when the cap is still unmet
(setq *ABL-BULGE-CLAMP*  1.373)      ; the half-angle a tangent-window
                                    ; edge, or a span's own permitted
                                    ; turn, may reach (radians): its
                                    ; tangent is a bulge of about 5, an
                                    ; arc sweeping some 314 degrees.
                                    ; Keeps U-turn geometry finite
(setq *ABL-STRAIGHT-R*   1.0e6)      ; an arc whose radius reaches this
                                    ; is a straight line for every
                                    ; practical purpose: it is not
                                    ; snapped to a nice radius
(if (null *ABL-TOL*)   (setq *ABL-TOL* 1.0))      ; default tolerance
;; *ABL-MAX-ARCS* : cap on the number of curved segments in the output;
;; nil = no cap.  Prompted for and remembered per session, like
;; *ABL-TOL*.

;; ---- small 2D vector helpers ---------------------------------------
(defun abl:2d (p) (list (car p) (cadr p)))
(defun abl:dist (a b) (distance (abl:2d a) (abl:2d b)))
(defun abl:sub (a b) (mapcar '- (abl:2d a) (abl:2d b)))
(defun abl:add (a b) (mapcar '+ (abl:2d a) (abl:2d b)))
(defun abl:scl (v s) (list (* (car v) s) (* (cadr v) s)))
(defun abl:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun abl:mid (a b) (abl:scl (abl:add a b) 0.5))
(defun abl:perp (v) (list (- (cadr v)) (car v))) ; rotate 90 deg CCW

;; Tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn quarter-sweep yields a huge but finite bulge
;; instead of dividing by zero.
(defun abl:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;; smallest integer >= X (X non-negative)
(defun abl:ceil (x / f)
  (setq f (fix x))
  (if (> x f) (1+ f) f))

;; the list from index K on / COUNT elements of LST starting at index K
(defun abl:nthcdr (k lst)
  (while (> k 0) (setq lst (cdr lst) k (1- k)))
  lst)
(defun abl:sublist (lst k count / out)
  (setq lst (abl:nthcdr k lst))
  (while (> count 0)
    (setq out   (cons (car lst) out)
          lst   (cdr lst)
          count (1- count)))
  (reverse out))

;; normalize an angle into [0, 2pi)
(defun abl:norm-ang (a)
  (while (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (while (>= a (* 2.0 pi)) (setq a (- a (* 2.0 pi))))
  a)

;; smallest signed angular difference (to - from), in (-pi, pi]
(defun abl:signed-dang (from to / d)
  (setq d (abl:norm-ang (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

;; ---- circle / arc geometry -----------------------------------------

;; Circumcenter of three points, nil when (nearly) collinear.
(defun abl:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
  (setq x1 (car pa) y1 (cadr pa)
        x2 (car pb) y2 (cadr pb)
        x3 (car pc) y3 (cadr pc)
        d  (* 2.0 (+ (* x1 (- y2 y3)) (* x2 (- y3 y1)) (* x3 (- y1 y2)))))
  (if (< (abs d) 1.0e-10)
    nil
    (progn
      (setq s1 (+ (* x1 x1) (* y1 y1))
            s2 (+ (* x2 x2) (* y2 y2))
            s3 (+ (* x3 x3) (* y3 y3)))
      (list (/ (+ (* s1 (- y2 y3)) (* s2 (- y3 y1)) (* s3 (- y1 y2))) d)
            (/ (+ (* s1 (- x3 x2)) (* s2 (- x1 x3)) (* s3 (- x2 x1))) d)))))

;; Bulge of the unique circular arc that starts at P1, ends at P2 and
;; passes through Q.  0.0 when collinear or a (near) full circle.
(defun abl:bulge-3pt (p1 q p2 / c a1 a2 aq dccw dq)
  (setq p1 (abl:2d p1) q (abl:2d q) p2 (abl:2d p2)
        c  (abl:circumcenter p1 q p2))
  (if (null c)
    0.0
    (progn
      (setq a1   (angle c p1)
            a2   (angle c p2)
            aq   (angle c q)
            dccw (abl:norm-ang (- a2 a1))
            dq   (abl:norm-ang (- aq a1)))
      (cond
        ((< dccw 1.0e-9) 0.0)                       ; degenerate sweep
        ((> dccw (- (* 2.0 pi) 1.0e-9)) 0.0)        ; degenerate sweep
        ((<= dq dccw) (abl:tan (/ dccw 4.0)))        ; CCW arc through Q
        (T (- (abl:tan (/ (- (* 2.0 pi) dccw) 4.0)))))))) ; CW through Q

;; Arc geometry of a bulged segment: (center radius angStart angEnd).
;; nil for a straight segment.
(defun abl:arc-geom (p1 p2 b / ch dir apex c)
  (if (< (abs b) 1.0e-9)
    nil
    (progn
      (setq p1   (abl:2d p1)
            p2   (abl:2d p2)
            ch   (abl:dist p1 p2)
            dir  (abl:scl (abl:sub p2 p1) (/ 1.0 ch))
            apex (abl:add (abl:mid p1 p2)
                         (abl:scl (abl:perp dir) (* -0.5 ch b)))
            c    (abl:circumcenter p1 apex p2))
      (if (null c)
        nil
        (list c (abl:dist c p1) (angle c p1) (angle c p2))))))

;; Distance from point P to segment (p1 p2 bulge).
(defun abl:seg-dist (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep rel)
  (setq p  (abl:2d p)
        p1 (abl:2d (car seg))
        p2 (abl:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    (progn
      (setq v    (abl:sub p2 p1)
            w    (abl:sub p p1)
            len2 (abl:dot v v))
      (if (< len2 1.0e-20)
        (abl:dist p p1)
        (progn
          (setq t2 (/ (abl:dot w v) len2))
          (if (< t2 0.0) (setq t2 0.0))
          (if (> t2 1.0) (setq t2 1.0))
          (abl:dist p (abl:add p1 (abl:scl v t2))))))
    (progn
      (setq g (abl:arc-geom p1 p2 b))
      (if (null g)
        (min (abl:dist p p1) (abl:dist p p2))
        (progn
          (setq c  (car g)  r (cadr g)
                a1 (caddr g) a2 (cadddr g)
                ap (angle c p))
          (if (> b 0.0)
            (setq sweep (abl:norm-ang (- a2 a1)) rel (abl:norm-ang (- ap a1)))
            (setq sweep (abl:norm-ang (- a1 a2)) rel (abl:norm-ang (- ap a2))))
          (if (<= rel sweep)
            (abs (- (abl:dist p c) r))
            (min (abl:dist p p1) (abl:dist p p2))))))))


;; ---- entity -> segment extraction ----------------------------------
;; A segment is (startPt endPt bulge), 2D points.

;; ---- span fitting helpers --------------------------------------------
;; A "span" is one candidate segment from A to B judged against QS, the
;; survey points it is supposed to represent.

;; Worst distance from any of QS to the segment (A B bulge).
(defun abl:span-dev (a b bul qs / seg mx d q)
  (setq seg (list a b bul) mx 0.0)
  (foreach q qs
    (setq d (abl:seg-dist q seg))
    (if (> d mx) (setq mx d)))
  mx)

;; The miss percentage in force for the current run.
(defun abl:misspct ()
  (if abl-miss-pct abl-miss-pct *ABL-MISS-PCT*))

;; The "on the shape" threshold in force for the current run; scales
;; with the tolerance (a quarter of it, never below *ABL-ON-EPS*).
;; abl-on-eps is bound per pass by abl:fit-pass / abl:fit-pass-open.
(defun abl:oneps ()
  (if abl-on-eps abl-on-eps *ABL-ON-EPS*))

;; How many of QS sit farther than the on-the-shape threshold from the
;; segment - the points that would eat into the miss allowance.
(defun abl:span-misses (a b bul qs / seg c q lim)
  (setq seg (list a b bul) c 0 lim (abl:oneps))
  (foreach q qs
    (if (> (abl:seg-dist q seg) lim) (setq c (1+ c))))
  c)

;; Radius of the arc (A B bulge); nil for a straight segment.
(defun abl:bulge-radius (a b bl / h)
  (if (< (abs bl) 1.0e-9)
    nil
    (progn
      (setq h (/ (abl:dist a b) 2.0))
      (/ (* h (1+ (* bl bl))) (* 2.0 (abs bl))))))

;; Bulge of the arc from A to B with radius R, on the same side and
;; with the same minor/major-arc character as reference bulge BREF.
(defun abl:radius-bulge (a b r bref / h s bl)
  (setq h (/ (abl:dist a b) 2.0))
  (if (or (< r h) (< h 1.0e-9))
    nil
    (progn
      (setq s  (sqrt (- (* r r) (* h h)))
            bl (if (> (abs bref) 1.0)
                 (/ (+ r s) h)              ; major arc
                 (/ (- r s) h)))            ; minor arc
      (if (< bref 0.0) (- bl) bl))))

;; Try to snap the arc A->B (free-fit bulge BL over points QS) to a
;; nice radius, keeping every point within TOL and at most LEFT of
;; them off by more than the on-the-shape threshold.  When WIN (a
;; bulge interval) is given the snapped bulge must stay inside it.
;; Returns (bulge . misses) of the snapped arc, or nil.
(defun abl:snap-arc (a b bl qs tol left win / r0 h best tier lo hi
                                              cands r bl2 mis)
  (setq r0   (abl:bulge-radius a b bl)
        h    (/ (abl:dist a b) 2.0)
        best nil)
  (if (and r0 (< r0 *ABL-STRAIGHT-R*))       ; a huge radius is basically straight
    (foreach tier *ABL-NICE-RADII*
      (if (null best)
        (progn
          (setq lo    (* tier (fix (/ r0 tier)))
                hi    (+ lo tier)
                cands (if (< (- r0 lo) (- hi r0))
                        (list lo hi)
                        (list hi lo)))
          (foreach r cands
            (if (and (null best) (>= r h) (> r 0.0))
              (progn
                (setq bl2 (abl:radius-bulge a b r bl))
                (if (and bl2
                         (or (null win)
                             (and (>= bl2 (car win)) (<= bl2 (cdr win))))
                         (<= (abl:span-dev a b bl2 qs) tol)
                         (<= (setq mis (abl:span-misses a b bl2 qs))
                             left))
                  (setq best (cons bl2 mis))))))))))
  best)

;; ---- point ordering and naming ---------------------------------------

;; Remove every element equal (within fuzz) to VAL from LST.
(defun abl:remove (val lst / out x)
  (foreach x lst
    (if (not (equal x val 1.0e-9)) (setq out (cons x out))))
  (reverse out))

;; Insert (key . val) pair X into the already-sorted list LST.
(defun abl:ins-car (x lst)
  (cond ((null lst) (list x))
        ((< (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (abl:ins-car x (cdr lst))))))

;; Insertion-sort a list of (key . val) pairs ascending by key.
(defun abl:sort-car (lst / out x)
  (foreach x lst (setq out (abl:ins-car x out)))
  out)

(defun abl:dedupe (pts / out q p dup)
  (foreach q pts
    (setq dup nil)
    (foreach p out
      (if (< (abl:dist p q) *ABL-EXACT-EPS*) (setq dup T)))
    (if (not dup) (setq out (cons q out))))
  (reverse out))

;; The farthest-apart pair of points, as (a b) - the automatic choice
;; of ends for an open run.
(defun abl:far-pair (pts / a b best q r d)
  (setq best -1.0 a nil b nil)
  (foreach q pts
    (foreach r pts
      (setq d (abl:dist q r))
      (if (> d best) (setq best d a q b r))))
  (list a b))

;; The point in QS farthest from P.  QS holds at least two distinct
;; points, so this is never P itself - which is what makes it the safe
;; thing to OFFER as the second end once the first one is taken.
(defun abl:far-from (p qs / best bd q d)
  (foreach q qs
    (setq d (abl:dist p q))
    (if (or (null bd) (> d bd)) (setq best q bd d)))
  best)

;; Order points into an OPEN run from E1 to E2 (nil = pick the
;; farthest-apart pair automatically): nearest-neighbour walk from E1,
;; E2 forced last, then 2-opt with BOTH ENDS FIXED.  Reversing
;; tour[i+1..j] changes only the edges (i,i+1) and (j,j+1); with j
;; capped at n-2 the index j+1 always exists, so there is no
;; wraparound and no closing edge to price - the closed 2-opt's delta
;; would charge for an edge an open run does not have.
(defun abl:order-points-open (pts e1 e2 / pr cur tour rest best bd q d n
                                          i j k ti ti1 tj tj1 delta head
                                          midl taill pass improved)
  (if (null e1)
    (progn
      (setq pr (abl:far-pair pts)
            e1 (car pr)
            e2 (cadr pr))))
  (setq cur  e1
        rest (abl:remove e2 (abl:remove e1 pts))
        tour (list e1))
  (while rest
    (setq best nil bd nil)
    (foreach q rest
      (setq d (abl:dist cur q))
      (if (or (null bd) (< d bd)) (setq best q bd d)))
    (setq tour (cons best tour)
          cur  best
          rest (abl:remove best rest)))
  (setq tour (reverse (cons e2 tour))
        n    (length tour)
        pass 0
        improved T)
  (while (and improved (< pass 40))
    (setq improved nil pass (1+ pass) i 0)
    (while (< i (- n 2))
      (setq j (1+ i))
      (while (< j (1- n))
        (setq ti    (nth i tour)
              ti1   (nth (1+ i) tour)
              tj    (nth j tour)
              tj1   (nth (1+ j) tour)
              delta (- (+ (abl:dist ti tj) (abl:dist ti1 tj1))
                       (+ (abl:dist ti ti1) (abl:dist tj tj1))))
        (if (< delta -1.0e-9)
          (progn                        ; reverse tour[i+1 .. j]
            (setq head nil midl nil taill nil k 0)
            (foreach q tour
              (cond ((<= k i) (setq head (cons q head)))
                    ((<= k j) (setq midl (cons q midl)))
                    (T        (setq taill (cons q taill))))
              (setq k (1+ k)))
            (setq tour     (append (reverse head) midl (reverse taill))
                  improved T)))
        (setq j (1+ j)))
      (setq i (1+ i))))
  tour)

;; The name carried by a point block, read from its *ABL-PT-TAG*
;; attribute; when the block has no such attribute, the first
;; attribute whose value reads as a number is taken instead (survey
;; exports do not all use the ab_pt tag).  nil when neither exists.
(defun abl:block-number (en / sub ed val fall v)
  (setq sub (entnext en) val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase *ABL-PT-TAG*)))
      (setq val v))
    (if (and (null fall) v (distof v 2))
      (setq fall v))
    (setq sub (entnext sub)))
  (if val val fall))

;; Remember a point, what to call it, and the number the survey gives
;; it, so a miss reports as "Pt.17" using the number in the drawing and
;; an end can be named by typing that number instead of hunting for the
;; point.  Points with no number of their own get the next count.
(defun abl:add-point (p nm / num)
  (setq num         (abl:num-in nm)
        npt         (1+ npt)
        pts         (cons p pts)
        abl-ptnames (cons (cons p (if (and nm (/= nm "")) nm (itoa npt)))
                          abl-ptnames)
        abl-ptkeys  (cons (cons p (if num num npt)) abl-ptkeys))
  (if num (setq abl-numbered (1+ abl-numbered))))

;; The whole number a surveyed label carries: the FIRST run of digits in
;; it, so "17", "P17" and "17A" all read as seventeen.  nil when the
;; label holds no digit at all - such a point falls back to its place in
;; the selection (see abl:add-point).  (cab:num-in, CABHD.lsp.)
(defun abl:num-in (s / i n c out done)
  (setq out "" done nil i 1 n (if s (strlen s) 0))
  (while (and (<= i n) (null done))
    (setq c (substr s i 1))
    (cond ((and (>= c "0") (<= c "9")) (setq out (strcat out c)))
          ((/= out "") (setq done T)))
    (setq i (1+ i)))
  (if (= out "") nil (atoi out)))

;; The survey number of the point at Q, or 0 when it has none.
(defun abl:pt-key (q / k p)
  (setq k nil)
  (foreach p abl-ptkeys
    (if (and (null k) (< (abl:dist (car p) q) *ABL-EXACT-EPS*))
      (setq k (cdr p))))
  (if k k 0))

;; The lowest and highest survey number in QS, as (lo . hi).
(defun abl:key-range (qs / lo hi k q)
  (foreach q qs
    (setq k (abl:pt-key q))
    (if (or (null lo) (< k lo)) (setq lo k))
    (if (or (null hi) (> k hi)) (setq hi k)))
  (if lo (cons lo hi)))

;; The point in QS whose survey number is N, or nil when no point
;; carries it.  Two points cannot share a number in a sane survey; if
;; they do, the first one read wins and the caller says which it took.
(defun abl:pt-of-key (n qs / out q)
  (foreach q qs
    (if (and (null out) (= (abl:pt-key q) n)) (setq out q)))
  out)

;; What to call the survey point at Q.
(defun abl:pt-name (q / nm p)
  (setq nm nil)
  (foreach p abl-ptnames
    (if (and (null nm) (< (abl:dist (car p) q) *ABL-EXACT-EPS*))
      (setq nm (cdr p))))
  (if nm nm "?"))

;; The member of LST nearest to P.
(defun abl:nearest (p lst / best bd q d)
  (setq best nil bd nil)
  (foreach q lst
    (setq d (abl:dist p q))
    (if (or (null bd) (< d bd)) (setq best q bd d)))
  best)

;; Index of point P in TOUR (exact-point fuzz), or nil.
(defun abl:tour-index (p tour / i k q)
  (setq i nil k 0)
  (foreach q tour
    (if (and (null i) (< (abl:dist p q) *ABL-EXACT-EPS*)) (setq i k))
    (setq k (1+ k)))
  i)

;; Number of curved segments in a span list.
(defun abl:arc-count (spans / c sp)
  (setq c 0)
  (foreach sp spans (if (>= (abs (caddr sp)) 1.0e-9) (setq c (1+ c))))
  c)

;; ---- near-tangent span fitting ---------------------------------------
;; Arcs sit ON the survey points: every span runs from tour point to
;; tour point and its interior is fitted through the points with exact
;; 3-point arcs.  Tangency is a WINDOW: at each joint the new arc's
;; start tangent may differ from the previous arc's end tangent by at
;; most *ABL-TANG-TOL*.  A bulge window is a cons (lo . hi); nil means
;; unconstrained.

;; Allowed bulge interval for the span A->B whose START tangent must
;; lie within *ABL-TANG-TOL* (times WF) of the incoming tangent TE.
(defun abl:tang-window (te a b wf / tt phi alo ahi lo hi)
  (setq tt  (* *ABL-TANG-TOL* wf)
        phi (abl:signed-dang te (angle a b))
        alo (max (min (/ (- phi tt) 2.0) *ABL-BULGE-CLAMP*) (- *ABL-BULGE-CLAMP*))
        ahi (max (min (/ (+ phi tt) 2.0) *ABL-BULGE-CLAMP*) (- *ABL-BULGE-CLAMP*))
        lo  (abl:tan alo)
        hi  (abl:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Clamp bulge B into window WIN (nil = unconstrained).
(defun abl:clamp-b (b win)
  (cond ((null win) b)
        ((< b (car win)) (car win))
        ((> b (cdr win)) (cdr win))
        (T b)))

;; Closest any of QS comes to the segment (A B bulge).
(defun abl:span-min (a b bul qs / seg mn d q)
  (setq seg (list a b bul) mn nil)
  (foreach q qs
    (setq d (abl:seg-dist q seg))
    (if (or (null mn) (< d mn)) (setq mn d)))
  mn)

;; ---- how far an arc is allowed to curve ---------------------------
;; The fitter used to accept any bulge the tangent window let through,
;; and the window opens all the way to a near-full circle once the
;; incoming tangent has swung round.  On a survey with real scatter
;; that let one bad joint spiral: every arc came back a semicircle,
;; each one flinging the tangent further round, until the outline
;; read as a string of loops.  So an arc now has to justify its
;; curvature with the points it covers.

;; Total turning of the polyline A -> QS... -> B, in radians - how far
;; round the run of points this span sits on actually swings.
(defun abl:span-turn (a b qs / chain tot)
  (setq chain (cons a (append qs (list b)))
        tot   0.0)
  (while (cddr chain)
    (setq tot   (+ tot (abs (abl:signed-dang
                              (angle (car chain) (cadr chain))
                              (angle (cadr chain) (caddr chain)))))
          chain (cdr chain)))
  tot)

;; The steepest bulge this span's own points justify: it may sweep as
;; far as they turn, plus *ABL-ARC-SLACK*.  A span between two
;; neighbours covers no turn, so it gets the slack alone.
(defun abl:max-bulge (a b qs)
  (abl:tan (min (/ (+ (abl:span-turn a b qs) *ABL-ARC-SLACK*) 4.0) *ABL-BULGE-CLAMP*)))

;; Clamp bulge B to +/- MX.
(defun abl:cap-b (b mx)
  (cond ((> b mx) mx) ((< b (- mx)) (- mx)) (T b)))

;; How the arc (A B BUL) treats the points QS, in one pass:
;;   (written-off  worst deviation of the rest  misses among the rest)
;; Only a point PLAINLY off - further than *ABL-DROP-MULT* times TOL -
;; may be written off; that is what separates a bad shot from a
;; feature, and writing one off is what keeps a bad shot from
;; shattering the span into stubs.  A point that misses by merely a
;; little still counts against the fit, so the span stops at it as it
;; always did.  The caller rations how many may go.
(defun abl:span-score (a b bul qs tol / seg drop dev mis lim d q)
  (setq seg (list a b bul) drop 0 dev 0.0 mis 0 lim (abl:oneps))
  (foreach q qs
    (setq d (abl:seg-dist q seg))
    (if (> d (* *ABL-DROP-MULT* tol))
      (setq drop (1+ drop))
      (progn
        (if (> d dev) (setq dev d))
        (if (> d lim) (setq mis (1+ mis))))))
  (list drop dev mis))

;; The points of QS this arc actually holds (within TOL) - the ones it
;; wrote off must not go on to steer the nice-radius snap.
(defun abl:span-kept (a b bul qs tol / seg out q)
  (setq seg (list a b bul))
  (foreach q qs
    (if (<= (abl:seg-dist q seg) tol) (setq out (cons q out))))
  (reverse out))

;; T when score SC beats KEY: fewer points written off, or as few and
;; a closer fit.
(defun abl:better (sc key)
  (or (< (car sc) (car key))
      (and (= (car sc) (car key)) (< (cadr sc) (cadr key)))))

;; Best bulge for the span A->B over interior points QS, restricted to
;; the tangent window WIN (nil = free) and to what the span's own
;; points justify (abl:max-bulge - no arc may come back as a loop).
;; EXACT 3-POINT ARCS COME FIRST: an unclamped 3-point bulge through
;; one of the actual interior points - so the arc's middle lands ON a
;; survey point - is preferred whenever one holds the span within TOL
;; and LEFT misses.  Compromise bulges (average / window-clamped /
;; window edges), which float between the points, are used only when
;; no exact arc works.  DLIM points may be written off - left plainly
;; off, see abl:span-score - instead of holding the span back; the
;; fewer written off the better, and a tie goes to the closer fit.
;; Returns (bulge dev misses exactflag written-off).
(defun abl:span-fit (a b qs win tol left dlim / bls m sum bl cands best
                                               bkey mx sc)
  (setq bls  (mapcar '(lambda (q) (abl:bulge-3pt a q b)) qs)
        m    (length qs)
        mx   (abl:max-bulge a b qs)
        best nil
        bkey nil)
  ;; exact candidates: through an interior point, inside the window,
  ;; and no steeper than the points themselves justify
  (foreach bl bls
    (if (and (<= (abs bl) mx)
             (or (null win)
                 (and (>= bl (car win)) (<= bl (cdr win)))))
      (progn
        (setq sc (abl:span-score a b bl qs tol))
        ;; an exact arc still has to HOLD the span - the points it did
        ;; not write off must all be inside TOL - or the compromise
        ;; bulges below never get their turn
        (if (and (<= (cadr sc) tol)
                 (<= (car sc) dlim)
                 (<= (caddr sc) left)
                 (or (null bkey) (abl:better sc bkey)))
          (setq best (list bl (cadr sc) (caddr sc) T (car sc))
                bkey sc)))))
  ;; compromise candidates, only when no exact arc holds the span
  (if (null best)
    (progn
      (setq sum 0.0)
      (foreach bl bls (setq sum (+ sum bl)))
      (setq cands (list (/ sum m) (nth (/ m 2) bls)))
      (if (>= m 4)
        (setq cands (append cands (list (nth (/ m 4) bls)
                                        (nth (/ (* 3 m) 4) bls)))))
      (if win
        (setq cands (append (mapcar '(lambda (bl) (abl:clamp-b bl win))
                                    cands)
                            (list (car win) (cdr win)
                                  (/ (+ (car win) (cdr win)) 2.0)))))
      (setq cands (mapcar '(lambda (bl) (abl:cap-b bl mx)) cands))
      (foreach bl cands
        (setq sc (abl:span-score a b bl qs tol))
        (if (or (null bkey) (abl:better sc bkey))
          (setq best (list bl (cadr sc) (caddr sc) nil (car sc))
                bkey sc)))))
  best)

;; The longest feasible span from POS, allowing DLIM of the points it
;; covers to be written off (0 = it must hold every one of them).  The
;; tangent window is stretched by degrees rather than abandoned; only
;; when even the widest step finds nothing does this return nil and
;; the stub in abl:span-loop take over.  Returns
;; (length bulge misses window written-off) or nil.
(defun abl:grow-span (tour pos te sharp nogrow lim tol left dlim pro
                     / a best bstx steps wf len go bnd win qs lm dm
                       fr)
  (setq a     (nth pos tour)
        best  nil
        bstx  nil
        steps *ABL-TANG-STEPS*)
  (while (and (null best) steps)
    (setq wf    (car steps)
          steps (cdr steps)
          len   2
          go    T)
    (while (and go (<= len lim))
      ;; plain indices, not the loop walker's (rem ... n): LIM caps
      ;; pos+len at the last point, so there is nothing to wrap and a
      ;; wrap here would grow a span back through the start
      (if (nth (+ pos len -1) nogrow)
        (setq go nil)             ; never bury a corner or a stretch pt
        (progn
          (setq bnd (nth (+ pos len) tour)
                win (if te (abl:tang-window te a bnd wf)))
          (setq qs (abl:sublist tour (1+ pos) (1- len))
                lm (if pro
                     (min left (abl:ceil (* (abl:misspct) len)))
                     left)
                dm (if (> dlim 0)
                     (min dlim (abl:ceil (* *ABL-DROP-PCT* len)))
                     0)
                fr (abl:span-fit a bnd qs win tol lm dm))
          (if (and (<= (cadr fr) tol) (<= (caddr fr) lm)
                   (<= (nth 4 fr) dm))
            (progn
              (setq best (list len (car fr) (caddr fr) win (nth 4 fr)))
              (if (cadddr fr) (setq bstx best))
              (setq len (1+ len)))
            (setq go nil))))))
  ;; an arc that floats between the points has to earn its keep:
  ;; only take it when it covers at least 2 more points than the
  ;; longest arc that passes exactly through a point
  (if (and bstx best (< (car best) (+ (car bstx) *ABL-FLOAT-GAIN*)))
    (setq best bstx))
  best)

;; Cover the OPEN tour with arcs, walking it once from end to end.
;; This is abl:span-loop rebuilt with LINEAR indices - not a stripped
;; copy, because the loop walker's modular arithmetic (rem ... n) is
;; exactly what an open run must not do: there is no seam, no closing
;; span, no start-tangent seeding, and the last span simply ends at
;; the final point.  The two path ends are free kinks by construction;
;; sharp corners are flagged on interior points only.  Everything else
;; - the window widening, exact-arc preference, floating-arc rule and
;; nice-radius snap - is the loop walker's, unchanged.
(defun abl:span-path (tour tol left drop pro / n sharp i prev cur next
                                              turn segs pos te lim a
                                              best alt len bnd win qs
                                              bl mis sn dev0 anch phi
                                              stub walls w i1 i2 nogrow
                                              f wrec)
  (setq n (length tour))
  ;; sharp corners: interior points only - the ends have no joint
  (setq sharp nil i 0)
  (repeat n
    (if (or (= i 0) (= i (1- n)))
      (setq sharp (cons nil sharp))
      (progn
        (setq prev (nth (1- i) tour)
              cur  (nth i tour)
              next (nth (1+ i) tour)
              turn (abs (abl:signed-dang (angle prev cur)
                                        (angle cur next))))
        (setq sharp (cons (or (> turn *ABL-CORNER-ANG*)
                              (abl:memb cur abl-corners))
                          sharp))))
    (setq i (1+ i)))
  (setq sharp (reverse sharp))
  ;; declared straight stretches map straight onto linear indices -
  ;; no short-way-around: an open run has only one way between them
  (setq walls nil)
  (foreach w abl-walls
    (setq i1 (abl:tour-index (car w) tour)
          i2 (abl:tour-index (cadr w) tour))
    (if (and i1 i2 (/= i1 i2))
      (progn
        (if (> i1 i2) (setq f i1 i1 i2 i2 f))
        (setq walls (cons (list i1 i2) walls)))))
  ;; indices ordinary spans may not swallow - including every HELD
  ;; point: a span may end on one (landing exactly) but never bury it
  (setq nogrow nil i 0)
  (repeat n
    (setq f (nth i sharp))
    (foreach w walls
      (if (and (>= i (car w)) (<= i (cadr w))) (setq f T)))
    (if (abl:memb (nth i tour) abl-holds) (setq f T))
    (setq nogrow (cons f nogrow)
          i      (1+ i)))
  (setq nogrow (reverse nogrow)
        segs   nil
        pos    0
        te     nil
        stub   nil)                 ; was the span just emitted a stub?
  (while (< pos (1- n))
    (setq a    (nth pos tour)
          wrec (assoc pos walls))
    (if wrec
      ;; ---- a declared straight stretch starts here: emit verbatim --
      (progn
        (setq len  (- (cadr wrec) pos)
              bnd  (nth (cadr wrec) tour)
              qs   (abl:sublist tour (1+ pos) (1- len))
              mis  (abl:span-misses a bnd 0.0 qs)
              segs (cons (list a bnd 0.0) segs)
              left (max 0 (- left mis))
              pos  (cadr wrec)
              te   (if (and (< pos (1- n)) (nth pos sharp))
                     nil
                     (angle a bnd))))
      ;; ---- an ordinary span --------------------------------------
      (progn
    ;; a span may reach the last point and no further; one arc over
    ;; the whole open run is legitimate, so no stop-short rule here.
    ;; With no seam to close there is no start tangent to arrive at,
    ;; so abl:grow-span is handed a nil one and never merges an end
    ;; window - the closed walk's growth, minus the loop
    (setq lim  (- (1- n) pos)
          best (abl:grow-span tour pos te sharp nogrow lim tol
                             left 0 pro))
    ;; writing a point off: a last resort, offered only where the span
    ;; stopped growing and kept only when every point given up bought
    ;; at least two more points of span
    (if (and (> drop 0) (or (null best) (< (car best) lim)))
      (progn
        (setq alt (abl:grow-span tour pos te sharp nogrow lim tol
                                left drop pro))
        (if (and alt
                 (> (nth 4 alt) 0)
                 (>= (car alt) (+ (if best (car best) 1)
                                  (* *ABL-DROP-GAIN* (nth 4 alt)))))
          (setq best alt))))
    (if (null best)
      ;; stub to the very next point.  One stub carries the incoming
      ;; tangent on exactly; a second straight after it keeps only
      ;; what the tangent window allows, so a mismatch decays instead
      ;; of doubling at every stub until the arcs come back as loops
      (progn
        (setq bnd (nth (1+ pos) tour))
        (if te
          (progn
            (setq phi (abl:signed-dang te (angle a bnd)))
            (if stub
              (setq phi (max (- *ABL-TANG-TOL*)
                             (min *ABL-TANG-TOL* phi))))
            (setq bl (abl:tan (/ phi 2.0))
                  bl (abl:cap-b bl (abl:max-bulge a bnd nil))))
          (setq bl 0.0))
        (setq best (list 1 bl 0 nil 0)
              stub T))
      ;; nice-radius snap inside the same tangent window, over the
      ;; points the arc actually holds
      (progn
        (setq len  (car best)
              bl   (cadr best)
              win  (cadddr best)
              bnd  (nth (+ pos len) tour)
              qs   (abl:span-kept a bnd bl
                                 (abl:sublist tour (1+ pos) (1- len))
                                 tol)
              dev0 (abl:span-dev a bnd bl qs)
              anch (and qs
                        (<= (abl:span-min a bnd bl qs)
                            *ABL-ANCHOR-EPS*))
              sn   (abl:snap-arc a bnd bl qs
                                (max dev0 *ABL-SNAP-EPS*) left win))
        (if (and sn
                 (<= (abs (car sn)) (abl:max-bulge a bnd qs))
                 (or (not anch)
                     (<= (abl:span-min a bnd (car sn) qs)
                         *ABL-ANCHOR-EPS*)))
          (setq best (list len (car sn) (cdr sn) win (nth 4 best))))
        (setq stub nil)))
    (setq len  (car best)
          bl   (cadr best)
          mis  (caddr best)
          bnd  (nth (+ pos len) tour)
          segs (cons (list a bnd bl) segs)
          left (- left mis)
          drop (- drop (nth 4 best))
          pos  (+ pos len)
          te   (if (and (< pos (1- n)) (nth pos sharp))
                 nil
                 (+ (angle a bnd) (* 2.0 (atan bl))))))))
  (reverse segs))

;; One full OPEN fit.  A single walk is the whole job: there is no
;; seam to close, so the seam-kink re-run has nothing to do here.
(defun abl:fit-pass-open (tour tol left drop pro / abl-on-eps)
  (setq abl-on-eps (max *ABL-ON-EPS* (* *ABL-ON-FRAC* tol)))
  (abl:span-path tour tol left drop pro))

;; The open counterpart: same relaxing cap loop, but the tour is NOT
;; rotated - an open run's start and end are its endpoints, and
;; rotating them away would corrupt the path.
(defun abl:coarse-path (tour tol maxarcs left drop pro / segs segs2 tol2
                                                       tries)
  (setq segs (abl:fit-pass-open tour tol left drop pro))
  (if maxarcs
    (progn
      (setq tol2 tol tries 0)
      (while (and (> (abl:arc-count segs) maxarcs) (< tries *ABL-CAP-TRIES*))
        (setq tol2  (* tol2 *ABL-CAP-RELAX*)
              tries (1+ tries)
              segs2 (abl:fit-pass-open tour tol2 1000000 drop nil))
        (if (< (abl:arc-count segs2) (abl:arc-count segs))
          (setq segs segs2)))))
  segs)

;; ---- self-intersection check -----------------------------------------

;; Cross product of (P-O) x (Q-O); its sign says which side Q is on.
(defun abl:cross3 (o p q)
  (- (* (- (car p) (car o)) (- (cadr q) (cadr o)))
     (* (- (cadr p) (cadr o)) (- (car q) (car o)))))

;; T when segments A-B and C-D properly cross.
(defun abl:segs-cross (a b c d / d1 d2 d3 d4)
  (setq d1 (abl:cross3 a b c) d2 (abl:cross3 a b d)
        d3 (abl:cross3 c d a) d4 (abl:cross3 c d b))
  (and (< (* d1 d2) 0.0) (< (* d3 d4) 0.0)))

;; Sample the fitted chain into a point list; arcs get intermediate
;; points so a bulging arc's real path is tested, not just its chord.
(defun abl:loop-pts (segs / out s g c r a1 a2 sweep k j aa)
  (setq out nil)
  (foreach s segs
    (setq out (cons (abl:2d (car s)) out))
    (if (>= (abs (caddr s)) 1.0e-9)
      (progn
        (setq g (abl:arc-geom (car s) (cadr s) (caddr s)))
        (if g
          (progn
            (setq c  (car g)   r  (cadr g)
                  a1 (caddr g) a2 (cadddr g))
            (if (> (caddr s) 0.0)
              (setq sweep (abl:norm-ang (- a2 a1)))
              (setq sweep (- (abl:norm-ang (- a1 a2)))))
            (setq k 4 j 1)
            (while (< j k)
              (setq aa  (+ a1 (* sweep (/ (float j) (float k))))
                    out (cons (list (+ (car c) (* r (cos aa)))
                                    (+ (cadr c) (* r (sin aa))))
                              out)
                    j   (1+ j))))))))
  (reverse out))

;; T when the fitted result crosses itself.  Closed results test the
;; ring of chords with the first/last pair exempt (they legitimately
;; share a vertex); open results test the open chain, whose real end
;; point is appended instead of the ring-closing repeat.
(defun abl:self-crosses (segs / p n found ti tj i j a b c d)
  (setq p (append (abl:loop-pts segs)
                  (list (abl:2d (cadr (last segs))))))
  (if (< (length p) 4)
    nil
    (progn
      (setq n     (1- (length p))            ; number of chords
            found nil
            ti    p
            i     0)
      (while (and (not found) (< i (- n 2)))
        (setq a  (car ti)
              b  (cadr ti)
              tj (cddr ti)
              j  (+ i 2))
        (while (and (not found) (< j n))
          (setq c (car tj) d (cadr tj))
          (if (abl:segs-cross a b c d) (setq found T))
          (setq tj (cdr tj) j (1+ j)))
        (setq ti (cdr ti) i (1+ i)))
      found)))

;; ---- output helpers --------------------------------------------------

;; Create the output layer, or make sure it is on, thawed, unlocked.
(defun abl:ensure-layer (name colour / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 colour)
                    '(6 . "Continuous")))
    (progn
      (setq rec   (tblobjname "LAYER" name)
            ed    (entget rec)
            flags (cdr (assoc 70 ed))
            col   (cdr (assoc 62 ed))
            fixed nil)
      (if (/= 0 (logand 5 flags))          ; frozen (1) or locked (4)
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)                        ; layer switched off
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nLayer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;; How many fitted polylines are already on the output layer.
(defun abl:prior-fits (/ ss)
  (setq ss (ssget "_X" (list (cons 8 *ABL-OUT-LAYER*)
                             '(0 . "LWPOLYLINE"))))
  (if ss (sslength ss) 0))

;; T when R is a whole multiple of one of the *ABL-NICE-RADII* tiers.
(defun abl:nice-radius-p (r / found tier q)
  (setq found nil)
  (if (and r (< r *ABL-STRAIGHT-R*))
    (foreach tier *ABL-NICE-RADII*
      (setq q (/ r tier))
      (if (< (abs (- q (fix (+ q 0.5)))) 1.0e-6) (setq found T))))
  found)

;; VERTS: list of (pt bulge) in order.  For a CLOSED polyline the last
;; vertex's bulge curves back to the first; an OPEN polyline needs the
;; final end point as one more vertex (bulge 0) or its last segment
;; silently vanishes - the callers append it.  ELEV is the single
;; height the whole polyline sits at (LWPOLYLINE group 38); COL is an
;; AutoCAD colour index, or nil for BYLAYER.
(defun abl:make-pline (verts layer col / dxf v)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                  (cons 8 layer)))
  (if col (setq dxf (append dxf (list (cons 62 col)))))
  (setq dxf (append dxf (list '(100 . "AcDbPolyline")
                              (cons 90 (length verts))
                              '(70 . 0))))
  (foreach v verts
    (setq dxf (append dxf (list (cons 10 (car v)) (cons 42 (cadr v))))))
  (entmakex dxf))

;; The kept fit joins the POOL layer in ByLayer colour: the preview
;; colour and layer belonged to the comparison - the result belongs
;; with the rest of the drawing.
(defun abl:set-bylayer (en / ed)
  (abl:ensure-layer *ABL-POOL-LAYER* 4)
  (setq ed (entget en)
        ed (subst (cons 8 *ABL-POOL-LAYER*) (assoc 8 ed) ed))
  (if (assoc 62 ed) (setq ed (subst '(62 . 256) (assoc 62 ed) ed)))
  (entmod ed))

;; Pad S with spaces to width W, for the comparison table.
(defun abl:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; The points SEGS fails to hold within TOL.
(defun abl:unheld (segs pts tol / out q s d dmin)
  (setq out nil)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (abl:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin tol) (setq out (cons q out))))
  (reverse out))

;; List membership by position, within the exact-point fuzz.
(defun abl:memb (q lst / found p)
  (setq found nil)
  (foreach p lst
    (if (< (abl:dist p q) *ABL-EXACT-EPS*) (setq found T)))
  found)

(defun abl:isect (a b / out q)
  (setq out nil)
  (foreach q a
    (if (abl:memb q b) (setq out (cons q out))))
  (reverse out))

;; ---- temporary preview geometry --------------------------------------
;; Every piece of scaffolding - dashed markers, candidate outlines,
;; labels - registers here as it is created and is swept away when the
;; command ends, however it ends.  Whatever the user keeps is dropped
;; from the list first.

(defun abl:temp-add (en)
  (if en (setq abl-temp (cons en abl-temp)))
  en)

(defun abl:temp-drop (en / out x)
  (setq out nil)
  (foreach x abl-temp
    (if (not (eq x en)) (setq out (cons x out))))
  (setq abl-temp (reverse out))
  en)

;; Scaffolding removed early - when a Back re-opens the step that drew
;; it - rather than at command end.
(defun abl:temp-kill (en)
  (if (and en (entget en)) (entdel en))
  (abl:temp-drop en))

;; T when a prompt that DOES take keywords was answered Back - or its
;; hidden synonym Undo.  getpoint/getdist/getint hand a keyword back as
;; a string where a value would be a list or a number, so the type test
;; is what separates the two.
(defun abl:back-kw (v)
  (and (= (type v) 'STR) (member v '("Back" "Undo"))))

(defun abl:temp-clear ( / en)
  (foreach en abl-temp
    (if (and en (entget en)) (entdel en)))
  (setq abl-temp nil))

;; ---- "this one is mine" stamping -------------------------------------
;; ABLOBF writes onto layers the drawing may already be using, so it must
;; never clear a layer wholesale: everything it creates carries xdata
;; naming this command, and only stamped objects are ever erased.

(defun abl:tag-mine (en / ed)
  (if en
    (progn
      (regapp "ABLOBF")
      (setq ed (entget en))
      (entmod (append ed (list (list -3 (list "ABLOBF" (cons 1000 "ABLOBF"))))))))
  en)

;; Erase only ABLOBF's own objects on a layer.  Returns how many went.
(defun abl:purge-mine (name / ss i n en)
  (setq n 0)
  (if (tblsearch "LAYER" name)
    (progn
      (setq ss (ssget "_X" (list (cons 8 name))))
      (if ss
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq en (ssname ss i))
            (if (assoc -3 (entget en '("ABLOBF")))
              (progn (entdel en) (setq n (1+ n))))
            (setq i (1+ i)))))))
  n)

;; Make sure the DASHED linetype exists (pure entmake).
(defun abl:ensure-dashed ()
  (if (not (tblsearch "LTYPE" "DASHED"))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   '(2 . "DASHED") '(70 . 0)
                   '(3 . "Dashed __ __ __ __ __")
                   '(72 . 65) '(73 . 2) '(40 . 18.0)
                   '(49 . 12.0) '(74 . 0)
                   '(49 . -6.0) '(74 . 0)))))

;; Draw the dashed ring marking a declared sharp corner.
(defun abl:draw-corner-marker (p)
  (abl:ensure-dashed)
  (abl:ensure-layer *ABL-WALL-LAYER* 8)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *ABL-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 *ABL-MISS-RADIUS*))))

;; Draw the marker for a declared HELD point: a dashed ring at half
;; the miss-ring radius, so it reads apart from corner rings.
(defun abl:draw-hold-marker (p)
  (abl:ensure-dashed)
  (abl:ensure-layer *ABL-WALL-LAYER* 8)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *ABL-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 (* 0.5 *ABL-MISS-RADIUS*)))))

;; Draw the dashed marker for a declared straight stretch.
(defun abl:draw-wall-marker (p1 p2)
  (abl:ensure-dashed)
  (abl:ensure-layer *ABL-WALL-LAYER* 8)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                  (cons 8 *ABL-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbLine")
                  (cons 10 (list (car p1) (cadr p1) 0.0))
                  (cons 11 (list (car p2) (cadr p2) 0.0)))))

;; Bounding box of a point list, as (minx miny maxx maxy).
(defun abl:bbox (pts / x0 y0 x1 y1 q)
  (foreach q pts
    (if (null x0)
      (setq x0 (car q) x1 (car q) y0 (cadr q) y1 (cadr q))
      (setq x0 (min x0 (car q)) x1 (max x1 (car q))
            y0 (min y0 (cadr q)) y1 (max y1 (cadr q)))))
  (list x0 y0 x1 y1))

;; Draw "1", "2", "3" beside each candidate, in that candidate's own
;; colour, with that fit's numbers spelled out beside it.
(defun abl:label (num colour bb hgt row top bot / x y out e pr)
  (setq x   (+ (caddr bb) (* 0.6 hgt))
        y   (- (cadddr bb) (* row hgt 2.1))
        out nil)
  (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *ABL-OUT-LAYER*) (cons 62 colour)
                          '(100 . "AcDbText")
                          (cons 10 (list x y 0.0))
                          (cons 40 hgt)
                          (cons 1 num))))
  (if e (setq out (cons e out)))
  (foreach pr (list (cons top (* 0.55 hgt)) (cons bot (* -0.05 hgt)))
    (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                            (cons 8 *ABL-OUT-LAYER*) (cons 62 colour)
                            '(100 . "AcDbText")
                            (cons 10 (list (+ x (* 1.4 hgt))
                                           (+ y (cdr pr))
                                           0.0))
                            (cons 40 (* 0.42 hgt))
                            (cons 1 (car pr)))))
    (if e (setq out (cons e out))))
  (reverse out))

;; Ring every point the chosen fit could not hold and list them beside
;; the shape, worst first.
(defun abl:mark-unheld (bad segs bb hgt / q d s dmin keyed pair th x y
                                         line)
  (abl:purge-mine *ABL-MISS-LAYER*)
  (if bad
    (progn
      (abl:ensure-layer *ABL-MISS-LAYER* 1)
      (foreach q bad
        (abl:tag-mine
          (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                          (cons 8 *ABL-MISS-LAYER*) '(100 . "AcDbCircle")
                          (cons 10 (list (car q) (cadr q) 0.0))
                          (cons 40 *ABL-MISS-RADIUS*)))))
      (setq keyed nil)
      (foreach q bad
        (setq dmin nil)
        (foreach s segs
          (setq d (abl:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (setq keyed (cons (cons dmin q) keyed)))
      (setq keyed (reverse (abl:sort-car keyed))
            th    (* 0.5 hgt)
            x     (+ (caddr bb) (* 0.6 hgt))
            y     (cadddr bb))
      (abl:tag-mine
        (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                        (cons 8 *ABL-MISS-LAYER*) '(100 . "AcDbText")
                        (cons 10 (list x y 0.0))
                        (cons 40 th)
                        (cons 1 (strcat "POINTS OFF THE LINE ("
                                        (itoa (length bad)) ")")))))
      (foreach pair keyed
        (setq y    (- y (* th 1.6))
              line (strcat "Pt." (abl:pt-name (cdr pair))
                           "   off by " (rtos (car pair) 4 4)))
        (abl:tag-mine
          (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *ABL-MISS-LAYER*) '(100 . "AcDbText")
                          (cons 10 (list x y 0.0))
                          (cons 40 th)
                          (cons 1 line)))))))
  keyed)

;; Print the hit report for the fit the user kept.  ALLOW is the run's
;; miss allowance; CLOSED says which joint the chain has none of.
(defun abl:report (newsegs pts tol allow prior
                  / nl na hiton hitok miss q s s2 d dmin worst sum
                    sumo no nice onpt inner ns nj i te ts kk mk nk
                    hw hq abl-on-eps)
  ;; report against the same on-the-shape threshold the fit used
  (setq abl-on-eps (max *ABL-ON-EPS* (* *ABL-ON-FRAC* tol)))
  (progn
      ;; -- segment mix, nice radii, arcs anchored on a point --------
      (setq nl 0 na 0 nice 0 onpt 0)
      (foreach s newsegs
        (if (< (abs (caddr s)) 1.0e-9)
          (setq nl (1+ nl))
          (progn
            (setq na (1+ na))
            (if (abl:nice-radius-p
                  (abl:bulge-radius (car s) (cadr s) (caddr s)))
              (setq nice (1+ nice)))
            (setq inner nil)
            (foreach q pts
              (if (and (> (abl:dist q (car s)) *ABL-EXACT-EPS*)
                       (> (abl:dist q (cadr s)) *ABL-EXACT-EPS*)
                       (<= (abl:seg-dist q s) *ABL-ANCHOR-EPS*))
                (setq inner T)))
            (if inner (setq onpt (1+ onpt))))))
      ;; -- how the survey points landed ------------------------------
      (setq hiton 0 hitok 0 miss 0 worst 0.0 sum 0.0 sumo 0.0 no 0)
      (foreach q pts
        (setq dmin nil)
        (foreach s newsegs
          (setq d (abl:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (if (> dmin worst) (setq worst dmin))
        (setq sum (+ sum dmin))
        (if (> dmin (abl:oneps))
          (setq sumo (+ sumo dmin) no (1+ no)))
        (cond
          ((<= dmin (abl:oneps)) (setq hiton (1+ hiton)))
          ((<= dmin tol)        (setq hitok (1+ hitok)))
          (T                    (setq miss  (1+ miss)))))
      ;; -- smoothness: worst kink at a joint that is not a corner ----
      ;; an open chain has one joint fewer - its seam does not exist
      (setq ns (length newsegs)
            nj (1- ns)
            i 0 mk 0.0 nk 0)
      (while (< i nj)
        (setq s  (nth i newsegs)
              s2 (nth (rem (1+ i) ns) newsegs)
              te (+ (angle (car s) (cadr s)) (* 2.0 (atan (caddr s))))
              ts (- (angle (car s2) (cadr s2)) (* 2.0 (atan (caddr s2))))
              kk (abs (abl:signed-dang te ts)))
        (if (<= kk *ABL-CORNER-ANG*)     ; bigger = an intentional corner
          (progn
            (if (> kk mk) (setq mk kk))
            (if (> kk (+ *ABL-TANG-TOL* 1.0e-6)) (setq nk (1+ nk)))))
        (setq i (1+ i)))
      (princ (strcat "\nABLOBF: " (itoa ns) " segments ("
                     (itoa nl) " lines + " (itoa na)
                     " curves) written to layer " *ABL-POOL-LAYER* "."
                     "\n  Points on the outline:        " (itoa hiton)
                     "\n  Points off within tolerance:  " (itoa hitok)
                     "  (allowance " (itoa allow) ")"
                     "\n  Points beyond tolerance:      " (itoa miss)
                     "\n  Worst point deviation:        " (rtos worst 2 3)
                     "\n  Average off, all points:      "
                     (rtos (if (> (length pts) 0)
                             (/ sum (length pts))
                             0.0)
                           2 3)
                     "\n  Average off, off points only: "
                     (if (> no 0)
                       (strcat (rtos (/ sumo no) 2 3)
                               "  (" (itoa no) " point(s))")
                       "-  (every point is on the line)")
                     "\n  Curves through a point:       " (itoa onpt)
                     " of " (itoa na)
                     "\n  Curves on foot/half/inch radii:" (itoa nice)
                     " of " (itoa na)
                     "\n  Largest joint kink:           "
                     (rtos (* 180.0 (/ mk pi)) 2 1) " deg  (limit "
                     (rtos (* 180.0 (/ *ABL-TANG-TOL* pi)) 2 1) ")"))
      (if (> nk 0)
        (princ (strcat "\n  (" (itoa nk)
                       " joint(s) needed more than the tangent limit)")))
      (if abl-walls
        (princ (strcat "\n  (" (itoa (length abl-walls))
                       " declared straight stretch(es) kept dead"
                       " straight)")))
      (if abl-holds
        (progn
          ;; every held point must sit ON the kept fit exactly; one
          ;; that does not means a declared stretch overruled it, and
          ;; that deserves a loud line of its own
          (setq hw 0.0)
          (foreach q abl-holds
            (setq dmin nil)
            (foreach s newsegs
              (setq d (abl:seg-dist q s))
              (if (or (null dmin) (< d dmin)) (setq dmin d)))
            (if (> dmin hw) (setq hw dmin hq q)))
          (if (<= hw *ABL-EXACT-EPS*)
            (princ (strcat "\n  (" (itoa (length abl-holds))
                           " held point(s) all landed on the line"
                           " exactly)"))
            (princ (strcat "\n  WARNING: held Pt." (abl:pt-name hq)
                           " is off by " (rtos hw 2 4)
                           " - a declared stretch overruled it.")))))
      (if (and *ABL-MAX-ARCS* (> na *ABL-MAX-ARCS*))
        (princ (strcat "\n  (the curve cap is " (itoa *ABL-MAX-ARCS*)
                       " but " (itoa na) " curves was the fewest"
                       " reachable)")))
      (if (> miss 0)
        (princ "\n  (points beyond tolerance: the curve cap overruled them)"))
      (if (abl:self-crosses newsegs)
        (princ (strcat "\n  WARNING: the result crosses itself - the"
                       " automatic point order is probably wrong."
                       "  Draw a rough lines-only sketch on layer "
                       *ABL-POOL-LAYER*
                       " through the points in the right order and"
                       " select it too.")))
      (if (> prior 0)
        (princ (strcat "\n  (" (itoa prior)
                       " earlier fit(s) were already on layer "
                       *ABL-OUT-LAYER* " - erase them if you only want"
                       " the new one)"))))
  (princ))

;; Build one candidate fit in MODE - "tight", "asked" or "few".  TOL
;; is always the distance the user typed; the mode sets what differs:
;; the fit tolerance, the miss allowance, and whether the curve cap
;; binds (only "asked" honours it).  CLOSED picks the engine.
(defun abl:build (tour tol allow mode / ftol left cap drop)
  (setq ftol (if (= mode "tight") (min tol *ABL-TIGHT-TOL*) tol)
        left (cond ((= mode "tight") 0)
                   ((= mode "few")   1000000)
                   (T                allow))
        cap  (if (= mode "asked") *ABL-MAX-ARCS*)
        ;; the tight candidate gives up no point at all - that is the
        ;; whole of its aim, and what makes it the reference the other
        ;; two are read against
        drop (if (= mode "tight")
               0
               (abl:ceil (* *ABL-DROP-PCT* (length tour)))))
  (abl:coarse-path tour ftol cap left drop (not (= mode "few"))))

;; Deviation summary for SEGS against PTS: (worst avg avg-off).
(defun abl:devstats (segs pts on / w q s d dmin sum n sumo no)
  (setq w 0.0 sum 0.0 n 0 sumo 0.0 no 0)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (abl:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin w) (setq w dmin))
    (setq sum (+ sum dmin) n (1+ n))
    (if (> dmin on) (setq sumo (+ sumo dmin) no (1+ no))))
  (list w
        (if (> n 0) (/ sum n) 0.0)
        (if (> no 0) (/ sumo no) nil)))

;; A deviation for a table cell; "-" when there is nothing to average.
(defun abl:fmt-dev (x)
  (if x (rtos x 2 2) "-"))

;; ---- offer three fits and let the user pick ---------------------------
;; The two ends of the curve-versus-accuracy trade and the middle, all
;; drawn, each in its own colour with what it costs; the one the user
;; points at is kept.  ELEV is the height every candidate is drawn at.
(defun abl:compare (tour pts tol allow
                   / prior vars v e ent lab st onv segs verts bad allbad
                     first i pick idx keep ce bb hgt sel picked keyed pr
                     res)
  (setq prior (abl:prior-fits))
  (abl:ensure-layer *ABL-OUT-LAYER* 3)
  (setq onv (max *ABL-ON-EPS* (* *ABL-ON-FRAC* tol)))
  (setq bb  (abl:bbox pts)
        hgt (/ (max (- (caddr bb) (car bb))
                    (- (cadddr bb) (cadr bb)))
               20.0))
  (if (<= hgt 0.0) (setq hgt 1.0))
  (setq abl-phase "building the three candidate fits"
        vars     nil
        allbad   nil
        first    T
        i        1)
  (foreach v *ABL-COMPARE*
    (setq segs  (abl:build tour tol allow (car v))
          verts (mapcar '(lambda (s) (list (car s) (caddr s))) segs))
    ;; an open polyline's last segment needs its end point as one more
    ;; vertex -- there is no closing curve back to vertex 0 to supply it
    (setq verts (append verts (list (list (cadr (last segs)) 0.0))))
    (setq ent  (abl:temp-add
                 (abl:make-pline verts *ABL-OUT-LAYER* (cadr v)))
          bad  (abl:unheld segs pts tol)
          st   (abl:devstats segs pts onv)
          lab  (abl:label
                 (itoa i) (cadr v) bb hgt i
                 (strcat (itoa (length segs)) " segs    "
                         (itoa (abl:arc-count segs)) " curves    "
                         (itoa (length bad)) " not held    "
                         (cadddr v))
                 (strcat "worst " (abl:fmt-dev (car st))
                         "    avg all " (abl:fmt-dev (cadr st))
                         "    avg off " (abl:fmt-dev (caddr st))))
          vars (cons (list segs ent bad v lab st) vars)
          i    (1+ i))
    (foreach e lab (abl:temp-add e))
    ;; only fits built to the user's distance vote on the "no fit
    ;; could hold these" note - the tight one threads everything
    (if (not (= (car v) "tight"))
      (if first
        (setq allbad bad first nil)
        (setq allbad (abl:isect allbad bad)))))
  (setq vars (reverse vars))
  (if (null (cadr (car vars)))
    (princ "\nABLOBF: could not draw the result - is the drawing read-only?")
    (progn
      (princ (strcat "\n\nThree candidate fits are now drawn on layer "
                     *ABL-OUT-LAYER*
                     ",\neach numbered on screen in its own colour:\n"))
      (princ "\n   #  segs  curves  worst off  avg all  avg off  not held  ")
      (princ "\n   -  ----  ------  ---------  -------  -------  --------  ")
      (setq i 1)
      (foreach v vars
        (setq segs (car v) bad (caddr v) ce (cadddr v) st (nth 5 v))
        (princ (strcat "\n   " (itoa i) "  "
                       (abl:pad (itoa (length segs)) 6)
                       (abl:pad (itoa (abl:arc-count segs)) 8)
                       (abl:pad (abl:fmt-dev (car st)) 11)
                       (abl:pad (abl:fmt-dev (cadr st)) 9)
                       (abl:pad (abl:fmt-dev (caddr st)) 9)
                       (abl:pad (itoa (length bad)) 10)
                       (cadddr ce)))
        (setq i (1+ i)))
      (princ (strcat "\n\n  \"not held\" = points further than "
                     (rtos tol 2 3) " from that fit - some of them"
                     " given up on purpose,"
                     "\n  to keep the shape whole where holding them"
                     " would break it into stubs."
                     "\n  \"avg all\" averages every point; \"avg off\""
                     " averages only the points that are off the line"
                     "\n  (further than " (rtos onv 2 3) " from it)."))
      (princ (strcat "\n  All three are measured against the "
                     (rtos tol 2 3) " you typed, but only one is built"
                     " to it:"
                     "\n  the tight fit spends curves to drive the error"
                     " towards nothing (it"
                     "\n  ignores that distance"
                     (if *ABL-MAX-ARCS* " and the curve cap" "")
                     " and gives up no point at all), the middle one is"
                     "\n  your settings exactly, and the few fit holds"
                     " the same distance with as few"
                     "\n  curves as it can - those two may write off up"
                     " to " (itoa (abl:ceil (* *ABL-DROP-PCT*
                                              (length pts))))
                     " stray point(s) between them."))
      (if allbad
        (princ (strcat "\n  NOTE: " (itoa (length allbad))
                       " point(s) could not be held by ANY fit built to"
                       " that distance - likely a mis-shot, a duplicate,"
                       " or a corner that needs more points around it."
                       "\n  (the tight fit threads every point it can"
                       " reach, so it does not get a vote here.)")))
      (setq abl-phase "waiting for the choice of fit")
      (princ "\n\n  Click the outline you want to keep, or type its number.")
      (princ "\n  Redo refits with new settings, and lets you omit points first.")
      (initget "1 2 3 All None Redo")
      (setq pick (getkword
                   "\n  Keep which fit - click one, or [1/2/3/All/None/Redo] <2>: "))
      (if (null pick)
        (progn
          (setq sel (entsel "\n  Pick the outline to keep (or Enter for 2): "))
          (if sel
            (progn
              (setq picked (car sel) i 1)
              (foreach v vars
                (if (or (eq picked (cadr v))
                        (member picked (nth 4 v)))
                  (setq pick (itoa i)))
                (setq i (1+ i)))
              (if (null pick)
                (progn
                  (princ "\n  (that is not one of the three - keeping 2)")
                  (setq pick "2"))))
            (setq pick "2"))))
      (cond
        ((= pick "Redo")
         (foreach v vars
           (if (and (cadr v) (entget (cadr v))) (entdel (cadr v)))
           (foreach e (nth 4 v)
             (if (and e (entget e)) (entdel e))))
         (setq res 'REDO))
        ((= pick "All")
         (foreach v vars
           (abl:temp-drop (cadr v))
           (foreach e (nth 4 v) (abl:temp-drop e)))
         (princ "\nKeeping all three, in their preview colours.")
         (princ "\n  (the number labels are kept too - erase them when done)"))
        ((= pick "None")
         (princ "\nAll three erased - nothing was added to the drawing."))
        (T
         (setq idx (atoi pick) i 1)
         (foreach v vars
           (if (= i idx)
             (setq keep v)
             (if (and (cadr v) (entget (cadr v))) (entdel (cadr v))))
           (setq i (1+ i)))
         (if keep
           (princ (strcat "\n  Keeping fit " pick " - "
                          (cadddr (cadddr keep)) ".")))
         (if (cadr keep)
           (progn
             (abl:temp-drop (cadr keep))
             (abl:set-bylayer (cadr keep))))))
      (if keep
        (progn
          (setq keyed (abl:mark-unheld (caddr keep) (car keep) bb hgt))
          (abl:report (car keep) pts tol allow prior)
          (if keyed
            (progn
              (princ (strcat "\n  " (itoa (length keyed))
                             " point(s) beyond the distance are ringed"
                             " on layer " *ABL-MISS-LAYER*
                             " and listed beside the shape, worst"
                             " first:"))
              (foreach pr keyed
                (princ (strcat "\n    Pt." (abl:pt-name (cdr pr))
                               "   off by " (rtos (car pr) 4 4))))))))))
  (princ)
  res)

;; ---- the numeric parameters ------------------------------------------

;; Each takes BACK: non-nil adds Back (and its hidden Undo synonym) to
;; the prompt and returns ABL-BACK when it is answered, so the caller
;; can re-open the step before it.  Offering Back never loosens the
;; value check - initget keeps its bits either way.

;; Maximum distance from a point; remembered in *ABL-TOL*.
(defun abl:ask-tol (back / tol)
  (if back (initget 6 "Back Undo") (initget 6))
  (setq tol (getdist (strcat "\n  Maximum distance from a point <"
                             (rtos *ABL-TOL* 2 3) ">"
                             (if back " [Back]" "") ": ")))
  (cond
    ((abl:back-kw tol) 'ABL-BACK)
    (T
     (if (null tol) (setq tol *ABL-TOL*))
     (if (> tol *ABL-TOL-MAX*)
       (progn
         (princ (strcat "\n  (more than " (rtos *ABL-TOL-MAX* 2 1)
                        " and the line is no longer a trace of the points"
                        " - using " (rtos *ABL-TOL-MAX* 2 1) ")"))
         (setq tol *ABL-TOL-MAX*)))
     (setq *ABL-TOL* tol)
     tol)))

;; Share of the points allowed off the line, returned as a fraction;
;; DEF is the fraction Enter keeps.
(defun abl:ask-pct (def back / pct)
  (if back (initget 4 "Back Undo") (initget 4))
  (setq pct (getint (strcat "\n  Percent of points allowed off <"
                            (itoa (fix (+ 0.5 (* 100.0 def))))
                            ">"
                            (if back " [Back]" "") ": ")))
  (cond
    ((abl:back-kw pct) 'ABL-BACK)
    ((null pct) def)
    ((> pct 100)
     (princ "\n  (more than 100 makes no sense - using 100)")
     1.0)
    (T (/ pct 100.0))))

;; Curve cap; remembered in *ABL-MAX-ARCS* (nil = no cap).
(defun abl:ask-cap (back / mx)
  (if back (initget 4 "None Back Undo") (initget 4 "None"))
  (setq mx (getint (strcat "\n  Maximum curves <"
                           (if *ABL-MAX-ARCS* (itoa *ABL-MAX-ARCS*) "None")
                           ">"
                           (if back " [None/Back]" "") ": ")))
  (cond
    ((abl:back-kw mx) 'ABL-BACK)
    (T
     (cond ((null mx) nil)                         ; Enter: keep as-is
           ((eq 'STR (type mx)) (setq *ABL-MAX-ARCS* nil))
           (T (setq *ABL-MAX-ARCS* mx)))
     *ABL-MAX-ARCS*)))

;; ---- the two ends ----------------------------------------------------
;; The one thing ABLOBF asks that neither ABHD nor LHD does up front: a
;; run that does not close has to start somewhere and stop somewhere,
;; and only the drafter knows where.  An end is named by clicking it or
;; by typing the survey number it already carries in the drawing --
;; typing wins where the points crowd and a click cannot separate two of
;; them.  Enter takes the automatic choice, which is the farthest-apart
;; pair: right often enough to be the default, and wrong exactly when
;; the run doubles back on itself, which is when you pick by hand.

;; One end of the run.  DFLT is the point Enter takes.  OTHER, when
;; given, is the end already chosen -- picking it twice would ask for a
;; run of no length, so it is refused and re-asked rather than fitted.
;; Returns the point, or ABL-BACK.
(defun abl:ask-end (msg dpts dflt other back / v q done out rng)
  (setq done nil out nil rng (abl:key-range dpts))
  (while (null done)
    (setq done T)
    (if back (initget "Number Back Undo") (initget "Number"))
    (setq v (getpoint (strcat "\n  " msg " [Number"
                              (if back "/Back" "") "] <Pt."
                              (abl:pt-name dflt) ">: ")))
    (cond
      ((abl:back-kw v) (setq out 'ABL-BACK))
      ((null v) (setq out dflt))                  ; Enter: the offer
      ((and (eq 'STR (type v)) (= v "Number"))
       (initget 4)
       (setq v (getint (strcat "\n    Survey number"
                               (if rng
                                 (strcat " (" (itoa (car rng)) " to "
                                         (itoa (cdr rng)) ")")
                                 "")
                               ", or Enter to pick instead: ")))
       (cond
         ((null v) (setq done nil))               ; Enter: back to the pick
         ((setq q (abl:pt-of-key v dpts))
          (setq out q)
          (princ (strcat "  - Pt." (abl:pt-name q))))
         (T
          (princ (strcat "\n  No selected point carries the number "
                         (itoa v) " - try again."))
          (setq done nil))))
      (T (setq out (abl:snap-break v dpts)))))
  ;; a run from a point to itself is not a run
  (if (and out other (not (eq out 'ABL-BACK))
           (< (abl:dist out other) *ABL-EXACT-EPS*))
    (progn
      (princ "\n  That is the other end - the run needs two different points.")
      (abl:ask-end msg dpts dflt other back))
    out))

;; ---- redo-time editing of walls and corners --------------------------

;; Erase this run's scaffolding markers of one entity type on the
;; marker layer, so the set can be redrawn to match an edited list.
(defun abl:sweep-marks (etype / keep en ed)
  (setq keep nil)
  (foreach en abl-temp
    (setq ed (if (and en (entget en)) (entget en)))
    (if (and ed
             (= etype (cdr (assoc 0 ed)))
             (= (strcase *ABL-WALL-LAYER*)
                (strcase (cdr (assoc 8 ed)))))
      (entdel en)
      (setq keep (cons en keep))))
  (setq abl-temp (reverse keep)))

;; Snap a picked point onto the nearest survey point.
(defun abl:snap-break (p dpts / q)
  (setq p (abl:2d p)
        q (abl:nearest p dpts))
  (if (null q)
    p
    (progn
      (if (> (abl:dist p q) (* 3.0 *ABL-TOL*))
        (princ "\n  (picked well away from any survey point - snapped to the nearest one)"))
      q)))

;; Add or remove declared straight stretches.
(defun abl:edit-walls (dpts / ans wp1 wp2 w1 w2 best bd w d res)
  (setq ans T res nil)
  (while ans
    (initget "Add Remove Keep Back Undo")
    (setq ans (getkword (strcat
                "\n  Straight stretches (" (itoa (length abl-walls))
                " declared) - [Add/Remove/Keep/Back] <Keep>: ")))
    (cond
      ((member ans '("Back" "Undo")) (setq ans nil res T))
      ((= ans "Add")
       (setq abl-phase "picking a straight stretch")
       (initget "Back Undo")
       (setq wp1 (getpoint "\n  First end of the straight stretch [Back]: "))
       (if (abl:back-kw wp1) (setq wp1 nil wp2 nil)
         (progn
           (initget "Back Undo")
           (setq wp2 (if wp1 (getpoint wp1 "\n  Second end [Back]: ")))
           (if (abl:back-kw wp2) (setq wp2 nil))))
       (if wp2
         (progn
           (setq w1 (abl:snap-break wp1 dpts)
                 w2 (abl:snap-break wp2 dpts))
           (if (< (abl:dist w1 w2) *ABL-EXACT-EPS*)
             (princ "\n  (both ends landed on the same survey point - ignored)")
             (progn
               (setq abl-walls (append abl-walls (list (list w1 w2))))
               (abl:temp-add (abl:tag-mine (abl:draw-wall-marker w1 w2)))
               (princ (strcat "\n  stretch Pt." (abl:pt-name w1)
                              " - Pt." (abl:pt-name w2) " added")))))))
      ((= ans "Remove")
       (if (null abl-walls)
         (princ "\n  (no straight stretches to remove)")
         (progn
           (setq abl-phase "removing a straight stretch")
           (initget "Back Undo")
           (setq wp1 (getpoint "\n  Pick near the straight stretch to remove [Back]: "))
           (if (abl:back-kw wp1) (setq wp1 nil))
           (if wp1
             (progn
               (setq wp1 (abl:2d wp1) best nil bd nil)
               (foreach w abl-walls
                 (setq d (abl:seg-dist wp1 (list (car w) (cadr w) 0.0)))
                 (if (or (null bd) (< d bd)) (setq best w bd d)))
               (setq abl-walls (abl:remove best abl-walls))
               ;; redraw the stretch markers to match what is left
               (abl:sweep-marks "LINE")
               (foreach w abl-walls
                 (abl:temp-add (abl:tag-mine
                   (abl:draw-wall-marker (car w) (cadr w)))))
               (princ (strcat "\n  stretch Pt." (abl:pt-name (car best))
                              " - Pt." (abl:pt-name (cadr best))
                              " removed")))))))
      (T (setq ans nil))))
  (if res 'ABL-BACK))

;; Add or remove declared sharp corners the same way.
(defun abl:edit-corners (dpts / ans wp1 w1 best bd w res)
  (setq ans T res nil)
  (while ans
    (initget "Add Remove Keep Back Undo")
    (setq ans (getkword (strcat
                "\n  Sharp corners (" (itoa (length abl-corners))
                " declared) - [Add/Remove/Keep/Back] <Keep>: ")))
    (cond
      ((member ans '("Back" "Undo")) (setq ans nil res T))
      ((= ans "Add")
       (setq abl-phase "picking a sharp corner")
       (initget "Back Undo")
       (setq wp1 (getpoint "\n  Corner point [Back]: "))
       (if (abl:back-kw wp1) (setq wp1 nil))
       (if wp1
         (progn
           (setq w1 (abl:snap-break wp1 dpts))
           (if (abl:memb w1 abl-corners)
             (princ "\n  (that corner is already declared)")
             (progn
               (setq abl-corners (append abl-corners (list w1)))
               (abl:temp-add (abl:tag-mine (abl:draw-corner-marker w1)))
               (princ (strcat "\n  corner Pt." (abl:pt-name w1)
                              " added")))))))
      ((= ans "Remove")
       (if (null abl-corners)
         (princ "\n  (no declared corners to remove)")
         (progn
           (setq abl-phase "removing a sharp corner")
           (initget "Back Undo")
           (setq wp1 (getpoint "\n  Pick the declared corner to remove [Back]: "))
           (if (abl:back-kw wp1) (setq wp1 nil))
           (if wp1
             (progn
               (setq wp1 (abl:2d wp1) best nil bd nil)
               (foreach w abl-corners
                 (if (or (null bd) (< (abl:dist wp1 w) bd))
                   (setq best w bd (abl:dist wp1 w))))
               (setq abl-corners (abl:remove best abl-corners))
               ;; the rings share their look with the omit markers;
               ;; redraw the corner and hold rings (spent omit rings
               ;; go quietly - the omissions already happened)
               (abl:sweep-marks "CIRCLE")
               (foreach w abl-corners
                 (abl:temp-add (abl:tag-mine (abl:draw-corner-marker w))))
               (foreach w abl-holds
                 (abl:temp-add (abl:tag-mine (abl:draw-hold-marker w))))
               (princ (strcat "\n  corner Pt." (abl:pt-name best)
                              " removed")))))))
      (T (setq ans nil))))
  (if res 'ABL-BACK))

;; Add or remove HELD points the same way.
(defun abl:edit-holds (dpts / ans wp1 w1 best bd w res)
  (setq ans T res nil)
  (while ans
    (initget "Add Remove Keep Back Undo")
    (setq ans (getkword (strcat
                "\n  Held points (" (itoa (length abl-holds))
                " declared) - [Add/Remove/Keep/Back] <Keep>: ")))
    (cond
      ((member ans '("Back" "Undo")) (setq ans nil res T))
      ((= ans "Add")
       (setq abl-phase "picking a held point")
       (initget "Back Undo")
       (setq wp1 (getpoint "\n  Point to hold exactly [Back]: "))
       (if (abl:back-kw wp1) (setq wp1 nil))
       (if wp1
         (progn
           (setq w1 (abl:snap-break wp1 dpts))
           (if (abl:memb w1 abl-holds)
             (princ "\n  (that point is already held)")
             (progn
               (setq abl-holds (append abl-holds (list w1)))
               (abl:temp-add (abl:tag-mine (abl:draw-hold-marker w1)))
               (princ (strcat "\n  held Pt." (abl:pt-name w1)
                              " added")))))))
      ((= ans "Remove")
       (if (null abl-holds)
         (princ "\n  (no held points to remove)")
         (progn
           (setq abl-phase "removing a held point")
           (initget "Back Undo")
           (setq wp1 (getpoint "\n  Pick the held point to release [Back]: "))
           (if (abl:back-kw wp1) (setq wp1 nil))
           (if wp1
             (progn
               (setq wp1 (abl:2d wp1) best nil bd nil)
               (foreach w abl-holds
                 (if (or (null bd) (< (abl:dist wp1 w) bd))
                   (setq best w bd (abl:dist wp1 w))))
               (setq abl-holds (abl:remove best abl-holds))
               ;; redraw the rings to match what is left
               (abl:sweep-marks "CIRCLE")
               (foreach w abl-corners
                 (abl:temp-add (abl:tag-mine (abl:draw-corner-marker w))))
               (foreach w abl-holds
                 (abl:temp-add (abl:tag-mine (abl:draw-hold-marker w))))
               (princ (strcat "\n  held Pt." (abl:pt-name best)
                              " released")))))))
      (T (setq ans nil))))
  (if res 'ABL-BACK))

;; ---- the command -----------------------------------------------------
(defun c:ABLOBF ( / tol ans go wp1 wp2 rawwalls rawcnrs rawholds w w1 w2
                   step rstep estep mk decls reselect
                   ss i en ed lay typ ext nocs far
                   pts dpts allow tour stale npt
                   v e1 e2
                   again omits pts2 ent ring abl-omitted
                   abl-miss-pct abl-walls abl-corners abl-holds
                   abl-temp abl-ptnames abl-ptkeys abl-numbered
                   *error* abl-old-err abl-phase undo-open
                   abl-pick)
  ;; report which step failed if anything goes wrong, sweep away any
  ;; preview geometry drawn so far, then restore the old handler
  (setq abl-temp   nil
        abl-old-err *error*
        *error*
          (lambda (m)
            (if (and m (not (wcmatch (strcase m)
                     "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
              (princ (strcat "\nABLOBF stopped while "
                             (if abl-phase abl-phase "starting up")
                             " -- " m)))
            (abl:temp-clear)
            ;; close the group after the sweep so one U takes back the
            ;; whole run, previews included; only if it ever opened
            (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
            (setq undo-open nil)
            (setq *error* abl-old-err)
            (princ)))

  ;; sweep leftovers from a run that was interrupted before it could
  ;; tidy up after itself
  (setq stale (abl:purge-mine *ABL-WALL-LAYER*))
  (if (> stale 0)
    (princ (strcat "\nABLOBF: cleared " (itoa stale)
                   " leftover marker(s) from layer " *ABL-WALL-LAYER*
                   ".")))

  ;; a pickfirst selection if there is one - kept for step 6, probed
  ;; before the undo group opens, which would clear the set
  (setq abl-pick (ssget "_I" '((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE,TEXT"))))

  ;; one undo group around the whole fit - a U after ABLOBF takes back
  ;; the outline, the labels and the markers in one step (the stale
  ;; purge above stays outside it, so U does not resurrect old junk)
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))

  (princ "\n\nABLOBF - fit an open run of arcs and lines through survey points.")

  ;; -- steps 1 to 5: the settings, walked as one chain --------------
  ;; Every question after the first offers Back (Undo is its hidden
  ;; synonym), so a mistyped percentage costs one keystroke instead of
  ;; the whole run.  STEP is the position in the chain and the only way
  ;; through it.
  (setq step 1)
  (while (<= step 4)
    (cond

      ;; -- step 1: how close must the line stay to the points? ------
      ((= step 1)
       (setq abl-phase "reading the tolerance")
       (princ "\n\n  Step 1 of 6 - how far may the fitted run sit from a survey point?")
       (princ "\n  Type a distance in drawing units (1 = one inch, 2 at most), or")
       (princ "\n  pick two points in the drawing to measure one.")
       (princ "\n  Smaller = hugs the points.  Bigger = smoother, with fewer curves.")
       ;; the first question of the command: nothing to go back to
       (setq tol  (abl:ask-tol nil)
             step 2))

      ;; -- step 2: how many of the points may sit off the line? -----
      ((= step 2)
       (setq abl-phase "reading the miss percentage")
       (princ "\n\n  Step 2 of 6 - what percent of the points may sit OFF the line")
       (princ "\n  (off, but still within the distance above)?")
       (princ (strcat "\n  Press Enter for the standard "
                      (itoa (fix (+ 0.5 (* 100.0 *ABL-MISS-PCT*))))
                      " percent."))
       (setq v (abl:ask-pct *ABL-MISS-PCT* T))
       (if (eq v 'ABL-BACK)
         (progn (princ "\n  Stepping back one question.")
                (setq step 1))
         (setq abl-miss-pct v
               step         3)))

      ;; -- step 3: optional cap on how many curves the result may use
      ((= step 3)
       (setq abl-phase "reading the curve limit")
       (princ "\n\n  Step 3 of 6 - limit how many curves the result may use?")
       (princ "\n  Type a whole number, or None for no limit.")
       (if (eq (abl:ask-cap T) 'ABL-BACK)
         (progn (princ "\n  Stepping back one question.")
                (setq step 2))
         (setq step 4)))

      ;; -- step 4: straight stretches and sharp corners --------------
      ;; ABHD's steps 4 and 5 folded into one loop: a declared straight
      ;; stretch comes out as a dead-straight LINE between its two
      ;; points; a declared corner is exempt from the tangency rule.
      ;;
      ;; One loop means one history: DECLS remembers what was declared
      ;; and in what order, so Back takes back the LAST declaration of
      ;; any kind - marker and all - rather than guessing at a kind.
      ;; With nothing left to take back it re-opens step 3 instead.
      ((= step 4)
       (setq abl-phase "asking about stretches, corners and held points"
             rawwalls nil
             rawcnrs  nil
             rawholds nil
             decls    nil
             go       T)
       (princ "\n\n  Step 4 of 6 - any dead-straight stretches, sharp corners, or points")
       (princ "\n  to hold ABSOLUTELY?  A held point can never be fudged: the line")
       (princ "\n  passes through it exactly, in every candidate.  Each is picked by")
       (princ "\n  its point(s), snapping to the survey points; dashed markers")
       (princ "\n  confirm them and clear themselves afterwards.")
       (setq step 5)                    ; unless a Back below says otherwise
       (while go
         (initget "Stretch Corner Hold Done Back Undo")
         (setq ans (getkword
                     "\n  Declare a stretch, corner or held point - or Done to fit? [Stretch/Corner/Hold/Done/Back] <Done>: "))
         (cond
           ((member ans '("Back" "Undo"))
            (if decls
              (progn
                (abl:temp-kill (cdar decls))
                (cond
                  ((= (caar decls) "Stretch")
                   (setq rawwalls (cdr rawwalls))
                   (princ "\n  Stepping back one stretch."))
                  ((= (caar decls) "Corner")
                   (setq rawcnrs (cdr rawcnrs))
                   (princ "\n  Stepping back one corner."))
                  (T
                   (setq rawholds (cdr rawholds))
                   (princ "\n  Stepping back one held point.")))
                (setq decls (cdr decls)))
              (progn (princ "\n  Already at the first declaration.")
                     (setq go nil step 3))))
           ((= ans "Hold")
            (setq abl-phase "picking a held point")
            (initget "Back Undo")
            (setq wp1 (getpoint "\n  Point to hold exactly [Back]: "))
            (if (and wp1 (not (abl:back-kw wp1)))
              (progn
                (setq wp1      (abl:2d wp1)
                      rawholds (cons wp1 rawholds)
                      mk       (abl:temp-add (abl:tag-mine (abl:draw-hold-marker wp1)))
                      decls    (cons (cons "Hold" mk) decls)))))
           ((= ans "Stretch")
            (setq abl-phase "picking a straight stretch")
            (initget "Back Undo")
            (setq wp1 (getpoint "\n  First end of the straight stretch [Back]: "))
            (if (abl:back-kw wp1) (setq wp1 nil wp2 nil)
              (progn
                (initget "Back Undo")
                (setq wp2 (if wp1 (getpoint wp1 "\n  Second end [Back]: ")))
                (if (abl:back-kw wp2) (setq wp2 nil))))
            (if wp2
              (progn
                (setq wp1      (abl:2d wp1)
                      wp2      (abl:2d wp2)
                      mk       (abl:temp-add (abl:tag-mine (abl:draw-wall-marker wp1 wp2)))
                      rawwalls (cons (list wp1 wp2) rawwalls)
                      decls    (cons (cons "Stretch" mk) decls)))))
           ((= ans "Corner")
            (setq abl-phase "picking a sharp corner")
            (initget "Back Undo")
            (setq wp1 (getpoint "\n  Corner point [Back]: "))
            (if (and wp1 (not (abl:back-kw wp1)))
              (progn
                (setq wp1     (abl:2d wp1)
                      mk      (abl:temp-add (abl:tag-mine (abl:draw-corner-marker wp1)))
                      rawcnrs (cons wp1 rawcnrs)
                      decls   (cons (cons "Corner" mk) decls)))))
           (T (setq go nil))))
       (if (= step 5)
         (progn
           (setq rawwalls (reverse rawwalls)
                 rawcnrs  (reverse rawcnrs)
                 rawholds (reverse rawholds))
           (if (or rawwalls rawcnrs rawholds)
             (princ (strcat "\n  " (itoa (length rawwalls))
                            " stretch(es), " (itoa (length rawcnrs))
                            " corner(s) and " (itoa (length rawholds))
                            " held point(s) noted - the dashed markers on "
                            *ABL-WALL-LAYER*
                            " clear themselves when the command finishes."))))))))

  ;; -- steps 5 and 6, as one chain -----------------------------------
  ;; RESELECT is set by a Back at the first end, which is the only
  ;; question the selection has in front of it.  Classification rebuilds
  ;; every list it fills, so a second pass starts clean.
  (setq reselect T)
  (while reselect
    (setq reselect nil)
    ;; -- step 5: the selection ----------------------------------------
    ;; Points only.  ABLOBF reads no geometry: the order of the run
    ;; comes from the two ends and the walk between them, so a window
    ;; dragged over the whole sheet picks up the survey and leaves what
    ;; is drawn alone.
    (setq abl-phase "waiting for the selection")
    (if abl-pick
      (setq ss abl-pick)
      (progn
        (princ "\n\n  Step 5 of 6 - select the survey points (POINT entities on any layer,")
        (princ (strcat "\n  \"" *ABL-POINT-BLOCK* "\" blocks anywhere, and blocks on layer "
                       *ABL-POINT-LAYER* ")."))
        (princ "\n  Select objects: ")
        (setq ss (ssget '((0 . "POINT,INSERT"))))))
    (if (null ss)
      (princ "\nNo points selected - there is nothing to fit a run through.")
      (progn
        ;; -- sort the selection into points ----------------------------
        (setq abl-phase "reading the selected entities")
        (setq pts nil i 0 nocs 0
              npt 0 abl-ptnames nil abl-ptkeys nil abl-numbered 0)
        (while (< i (sslength ss))
          (setq en  (ssname ss i)
                ed  (entget en)
                lay (strcase (cdr (assoc 8 ed)))
                typ (cdr (assoc 0 ed))
                ext (cdr (assoc 210 ed))
                i   (1+ i))
          ;; geometry drawn in a tilted UCS reads back in its own plane,
          ;; so a flat 2D fit of it would be wrong - count and warn
          (if (and ext (< (abs (caddr ext)) 0.999)) (setq nocs (1+ nocs)))
          (cond
            ;; the survey point block is ALWAYS a point, on any layer
            ((and (= typ "INSERT")
                  (= (strcase (cdr (assoc 2 ed))) (strcase *ABL-POINT-BLOCK*)))
             (abl:add-point (abl:2d (cdr (assoc 10 ed)))
                            (abl:block-number en)))
            ;; a plain POINT counts on ANY layer - the selection is
            ;; explicit, so there is no guessing involved
            ((= typ "POINT")
             (abl:add-point (abl:2d (cdr (assoc 10 ed))) nil))
            ;; any other block dropped on the POINTS layer -> a point
            ((and (= typ "INSERT") (= lay (strcase *ABL-POINT-LAYER*)))
             (abl:add-point (abl:2d (cdr (assoc 10 ed)))
                            (abl:block-number en)))))
        (if (> nocs 0)
          (princ (strcat "\nABLOBF: warning - " (itoa nocs)
                         " selected object(s) are not drawn in the world"
                         " plane; the fit is flat (XY) and may be wrong."
                         "  Set UCS to World and flatten them first.")))
        (setq dpts  (if pts (abl:dedupe pts))
              allow (abl:ceil (* (abl:misspct) (length dpts))))
        ;; snap the declared stretch ends and corners onto actual points
        (setq abl-walls nil)
        (foreach w rawwalls
          (setq w1 (abl:nearest (car w) dpts)
                w2 (abl:nearest (cadr w) dpts))
          (cond
            ((or (null w1) (null w2)) nil)
            ((< (abl:dist w1 w2) *ABL-EXACT-EPS*)
             (princ "\n  (both ends of a declared stretch landed on the same survey point - that stretch is ignored)"))
            (T
             (if (or (> (abl:dist (car w) w1) (* 3.0 tol))
                     (> (abl:dist (cadr w) w2) (* 3.0 tol)))
               (princ "\n  (a declared stretch end was picked well away from any survey point - snapped to the nearest one)"))
             (setq abl-walls (cons (list w1 w2) abl-walls)))))
        (setq abl-walls (reverse abl-walls))
        (setq abl-corners nil)
        (foreach w rawcnrs
          (setq w1 (abl:nearest w dpts))
          (if w1
            (progn
              (if (> (abl:dist w w1) (* 3.0 tol))
                (princ "\n  (a declared corner was picked well away from any survey point - snapped to the nearest one)"))
              (setq abl-corners (cons w1 abl-corners)))))
        (setq abl-corners (reverse abl-corners))
        ;; held points snap onto survey points the same way; duplicates
        ;; collapse to one
        (setq abl-holds nil)
        (foreach w rawholds
          (setq w1 (abl:nearest w dpts))
          (if w1
            (progn
              (if (> (abl:dist w w1) (* 3.0 tol))
                (princ "\n  (a held point was picked well away from any survey point - snapped to the nearest one)"))
              (if (not (abl:memb w1 abl-holds))
                (setq abl-holds (cons w1 abl-holds))))))
        (setq abl-holds (reverse abl-holds))
        (if (> (length dpts) 150)
          (princ (strcat "\nABLOBF: " (itoa (length dpts))
                         " points - ordering and fitting will take a"
                         " little while, please wait...")))
        (cond
          ((null pts)
           (princ (strcat "\nNo survey points found (looked for POINT"
                          " entities, \"" *ABL-POINT-BLOCK*
                          "\" block insertions, and blocks on layer "
                          *ABL-POINT-LAYER* ").")))
          ((< (length dpts) 2)
           (princ "\nAt least 2 distinct points are needed for a run."))
          (T
           ;; -- step 6: the two ends -----------------------------------
           ;; The question ABHD never has to ask.  A closed loop has no
           ;; ends; an open run has two, and nothing in the points
           ;; themselves says which they are.  Enter takes the
           ;; farthest-apart pair - right for a run that does not double
           ;; back, and wrong exactly when it does, which is when you
           ;; pick by hand.  The two are a chain of their own: Back at
           ;; the second re-opens the first, and Back at the first hands
           ;; the whole selection back, since nothing is drawn yet and
           ;; the classifier rebuilds every list it fills.
           (setq far   (abl:far-pair dpts)
                 e1    nil
                 e2    nil
                 estep 1)
           ;; offer the pair the way the survey reads: a run from Pt.9
           ;; back to Pt.1 is the same run, and the lower number first
           ;; is the one a drafter expects to see
           (if (> (abl:pt-key (car far)) (abl:pt-key (cadr far)))
             (setq far (list (cadr far) (car far))))
           (princ "\n\n  Step 6 of 6 - where does the run START, and where does it END?")
           (princ "\n  Click a point or type the survey number it carries; Enter takes")
           (princ "\n  the farthest-apart pair.  Everything else is ordered between them.")
           (if (> abl-numbered 0)
             (princ (strcat "\n  (" (itoa abl-numbered) " of " (itoa npt)
                            " selected point(s) carry a number of their own;"
                            " the rest are numbered in the order they were"
                            " read.)")))
           (while (<= estep 2)
             (cond
               ((= estep 1)
                (setq abl-phase "picking the point the run starts at"
                      v (abl:ask-end "Point the run STARTS at" dpts
                                     (car far) nil T))
                (if (eq v 'ABL-BACK)
                  (progn (princ "\n  Stepping back to the selection.")
                         (setq reselect T abl-pick nil estep 3))
                  (setq e1 v estep 2)))
               ((= estep 2)
                (setq abl-phase "picking the point the run ends at"
                      v (abl:ask-end
                          "Point the run ENDS at" dpts
                          ;; never offer the end already taken
                          (abl:far-from e1 dpts) e1 T))
                (if (eq v 'ABL-BACK)
                  (progn (princ "\n  Stepping back one question.")
                         (setq estep 1))
                  (setq e2 v estep 3)))))
           (if (not reselect)
             (progn
               (princ (strcat "\n  Run: Pt." (abl:pt-name e1) " to Pt."
                              (abl:pt-name e2) ", through "
                              (itoa (- (length dpts) 2)) " point(s)"
                              " between them."))
               (setq abl-phase "ordering the points"
                     tour (abl:order-points-open dpts e1 e2))
               (setq again T)
               (while again
                 (setq again nil)
                 (if (eq 'REDO (abl:compare tour pts tol allow))
                       (progn
                         ;; -- redo: maybe omit points, then re-ask ---------
                         (setq abl-phase "picking points to omit"
                               omits    nil)
                         (princ "\n\nRedoing the fit.  Any points to leave out this time?")
                         (princ "\n  Pick each one (Enter for none) - mis-shots, duplicates, or")
                         (princ "\n  anything the line should not chase; each gets a dashed ring.")
                         (if abl-omitted
                           (princ (strcat "\n  " (itoa (length abl-omitted))
                                          " point(s) are already out -"
                                          " picking one of those puts it"
                                          " BACK IN.")))
                         (while (setq wp1 (getpoint
                                            "\n  Point to omit - or a ringed one to restore (Enter when done): "))
                           (setq wp1 (abl:2d wp1)
                                 w1  (abl:nearest wp1 dpts)
                                 w2  (abl:nearest wp1 (mapcar 'car abl-omitted)))
                           (cond
                             ((and w2 (or (null w1)
                                          (<= (abl:dist wp1 w2)
                                              (abl:dist wp1 w1))))
                              (setq ent        (assoc w2 abl-omitted)
                                    pts        (append pts (cadr ent))
                                    dpts       (abl:dedupe pts)
                                    abl-omitted (abl:remove ent abl-omitted)
                                    omits      (abl:remove w2 omits))
                              (if (and (caddr ent) (entget (caddr ent)))
                                (progn
                                  (abl:temp-drop (caddr ent))
                                  (entdel (caddr ent))))
                              (princ (strcat "  - Pt." (abl:pt-name w2)
                                             " back in")))
                             (w1
                              (setq pts2 nil ent nil)
                              (foreach w pts
                                (if (< (abl:dist w w1) *ABL-EXACT-EPS*)
                                  (setq ent (cons w ent))
                                  (setq pts2 (cons w pts2))))
                              (setq pts  (reverse pts2)
                                    dpts (abl:dedupe pts)
                                    ring (abl:temp-add (abl:tag-mine
                                           (abl:draw-corner-marker w1)))
                                    abl-omitted (cons (list w1 ent ring)
                                                     abl-omitted)
                                    omits      (cons w1 omits))
                              (princ (strcat "  - omitting Pt."
                                             (abl:pt-name w1))))))
                         (if omits
                           (progn
                             ;; declared stretches and corners anchored on
                             ;; an omitted point make no sense any more
                             (setq pts2 nil)
                             (foreach w abl-walls
                               (if (not (or (abl:memb (car w) omits)
                                            (abl:memb (cadr w) omits)))
                                 (setq pts2 (cons w pts2))))
                             (if (< (length pts2) (length abl-walls))
                               (princ "\n  (a declared stretch lost an end and was dropped)"))
                             (setq abl-walls (reverse pts2)
                                   pts2     nil)
                             (foreach w abl-corners
                               (if (not (abl:memb w omits))
                                 (setq pts2 (cons w pts2))))
                             (setq abl-corners (reverse pts2)
                                   pts2       nil)
                             ;; a held point that was just omitted is out of
                             ;; the fit entirely - nothing left to hold
                             (foreach w abl-holds
                               (if (not (abl:memb w omits))
                                 (setq pts2 (cons w pts2))))
                             (if (< (length pts2) (length abl-holds))
                               (princ "\n  (an omitted point was held - its hold went with it)"))
                             (setq abl-holds (reverse pts2))))
                         (if abl-omitted
                           (princ (strcat "\n  " (itoa (length abl-omitted))
                                          " point(s) omitted in total - "
                                          (itoa (length dpts))
                                          " in the fit.")))
                         (if (< (length dpts) 2)
                           (princ "\nToo few points remain for a fit - nothing redone.")
                           (progn
                             ;; stretches and corners may change for the retry
                             (princ "\n\n  Straight stretches and sharp corners can change too -")
                             (princ "\n  Enter keeps each list as it is.")
                             ;; An end that was just omitted is not a point
                             ;; any more, so the offer has to be replaced
                             ;; BEFORE the chain below re-asks for it -
                             ;; otherwise Enter takes a point that is no
                             ;; longer in the fit.
                             (if (not (and (abl:memb e1 dpts)
                                           (abl:memb e2 dpts)))
                               (progn
                                 (princ "\n  (an end point was omitted - offering the farthest-apart pair instead)")
                                 (setq far (abl:far-pair dpts)
                                       e1  (car far)
                                       e2  (cadr far))))
                             ;; the Redo settings are a chain like the opening
                             ;; questions, and walk back the same way: Back at
                             ;; any of them re-opens the one before it, and
                             ;; Back at the first has nowhere to go
                             (setq rstep 1)
                             (while (<= rstep 7)
                               (cond
                                 ((= rstep 1)
                                  (setq abl-phase "editing straight stretches")
                                  (abl:edit-walls dpts)      ; first: no Back out
                                  (setq rstep 2))
                                 ((= rstep 2)
                                  (setq abl-phase "editing sharp corners")
                                  (setq rstep (if (eq (abl:edit-corners dpts) 'ABL-BACK)
                                                (progn (princ "\n  Stepping back one question.") 1)
                                                3)))
                                 ((= rstep 3)
                                  (setq abl-phase "editing held points")
                                  (setq rstep (if (eq (abl:edit-holds dpts) 'ABL-BACK)
                                                (progn (princ "\n  Stepping back one question.") 2)
                                                4)))
                                 ((= rstep 4)
                                  ;; the ends can move on a Redo, and an
                                  ;; end that has just been omitted MUST.
                                  ;; Enter keeps the one standing, so
                                  ;; saying nothing changes nothing
                                  (setq abl-phase "picking the run's ends"
                                        v (abl:ask-end
                                            "Point the run STARTS at"
                                            dpts e1 nil T))
                                  (cond
                                    ((eq v 'ABL-BACK)
                                     (princ "\n  Stepping back one question.")
                                     (setq rstep 3))
                                    (T
                                     (setq e1 v
                                           v  (abl:ask-end
                                                "Point the run ENDS at"
                                                dpts
                                                (if (< (abl:dist e2 e1)
                                                       *ABL-EXACT-EPS*)
                                                  (abl:far-from e1 dpts)
                                                  e2)
                                                e1 T))
                                     (if (eq v 'ABL-BACK)
                                       ;; back to the START ask, which is
                                       ;; the top of this same step
                                       (progn (princ "\n  Stepping back one question.")
                                              (setq rstep 4))
                                       (setq e2 v rstep 5)))))
                                 ((= rstep 5)
                                  (princ "\n\n  New settings - Enter keeps each one as it is.")
                                  (setq abl-phase "reading the tolerance"
                                        v        (abl:ask-tol T))
                                  (if (eq v 'ABL-BACK)
                                    (progn (princ "\n  Stepping back one question.")
                                           (setq rstep 4))
                                    (setq tol v rstep 6)))
                                 ((= rstep 6)
                                  (setq abl-phase "reading the miss percentage"
                                        v        (abl:ask-pct abl-miss-pct T))
                                  (if (eq v 'ABL-BACK)
                                    (progn (princ "\n  Stepping back one question.")
                                           (setq rstep 5))
                                    (setq abl-miss-pct v rstep 7)))
                                 ((= rstep 7)
                                  (setq abl-phase "reading the curve limit")
                                  (setq rstep (if (eq (abl:ask-cap T) 'ABL-BACK)
                                                (progn (princ "\n  Stepping back one question.") 6)
                                                8)))))
                             (setq allow (abl:ceil (* (abl:misspct)
                                                     (length dpts))))
                             ;; the point order must forget the omitted ones
                             (setq abl-phase "ordering the points"
                                   tour (abl:order-points-open dpts e1 e2))
                             ;; say what the run is NOW.  The ends can
                             ;; have moved, or been replaced because one
                             ;; was omitted, and a refit that quietly
                             ;; ran between two different points would
                             ;; be read as the same run drawn better
                             (princ (strcat "\n  Run: Pt." (abl:pt-name e1)
                                            " to Pt." (abl:pt-name e2)
                                            ", through "
                                            (itoa (- (length dpts) 2))
                                            " point(s) between them."))
                             (setq again T)))))))))))))
  ;; sweep the dashed markers and any candidate the user did not keep
  (abl:temp-clear)
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (setq *error* abl-old-err)   ; restore the previous error handler
  (princ))

(defun c:ABLOBFVER ()
  (princ (strcat "\nABLOBF " *ablobf-version*))
  (princ))

(princ (strcat "\nABLOBF " *ablobf-version*
               " loaded.  Type ABLOBF to fit an open run of arcs and"
               " lines through survey points."))
(princ)
