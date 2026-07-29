;;; ===================================================================
;;; ABHD.LSP  --  Fit a pool perimeter through surveyed points
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Command:  ABHD
;;;
;;; The user window-selects an area containing:
;;;   * On layer "POOL"   : (optional) a closed perimeter drawn as ONE
;;;                         closed polyline OR an exploded set of
;;;                         LINEs/ARCs.
;;;   * On layer "POINTS" : POINT entities surveyed on the real pool
;;;                         edge.
;;;
;;; TWO MODES, chosen automatically from the selection:
;;;   * GUIDED  - the selection contains POOL geometry: the drawn
;;;               shape is used as the guide and re-fitted through the
;;;               points (described below).
;;;   * POINTS-ONLY - the selection contains no POOL geometry: the
;;;               program orders the points into a closed loop by
;;;               itself (nearest-neighbour tour + 2-opt uncrossing)
;;;               and covers them with as FEW long, overarching ARCS
;;;               as possible - each arc is grown to take in as many
;;;               consecutive points as it can hold.  No straight
;;;               lines are drawn (organic shapes have none); the only
;;;               exception is a stretch between two sharp corners
;;;               with no points in between, where an arc would be
;;;               pure invention.
;;;
;;; ON THE POINTS FIRST: every arc endpoint sits ON a survey point,
;;; and each arc is chosen so its MIDDLE passes exactly through one of
;;; its interior points too (a true 3-point arc) whenever such an arc
;;; holds the span.  Arcs that float between the points are a last
;;; resort and must cover at least 2 more points to be chosen - they
;;; should be the rare exception (roughly 1 arc in 10), not the rule.
;;;
;;; NEAR-TANGENT SMOOTHNESS: at every joint the new arc must start
;;; within *PF-TANG-TOL* (8 degrees) of the previous arc's end
;;; tangent - close enough to look smooth, loose enough that the
;;; points stay in charge.  Sharp corners (over *PF-CORNER-ANG*) stay
;;; free kinks; the closing seam is held to the same window (the fit
;;; is re-run once with a seeded start tangent when the seam comes
;;; out worse).
;;;
;;; NICE RADII: arc radii are snapped to friendly increments before a
;;; free ("weird") number is accepted - whole feet first, then half
;;; feet, then whole inches (*PF-NICE-RADII*, drawing units = inches).
;;; The points outrank pretty radii: a snap may move covered points at
;;; most *PF-SNAP-EPS* beyond where they already sat and may never
;;; pull an arc off its anchor point; endpoints never move.
;;;
;;; THE MISS ALLOWANCE: the perimeter no longer has to thread every
;;; point exactly.  Up to *PF-MISS-PCT* (15%) of the points, rounded
;;; UP to the nearest whole point, may sit off the result by up to the
;;; tolerance (default 1 unit = about an inch); every other point
;;; stays on it (within *PF-ON-EPS*).  That slack is spent where it
;;; buys the most: longer arcs, fewer curves, nicer radii.
;;;
;;; THE CURVE CAP: the command also asks for a maximum number of
;;; curves ("None" = unlimited).  When a fit needs more, the whole
;;; loop is refitted with a progressively relaxed tolerance until the
;;; cap holds - merging arcs would break their tangency, so the chain
;;; is rebuilt instead and stays smooth.  The cap wins over the
;;; tolerance; whatever error it forces is shown in the hit report.
;;; The cap binds in EVERY mode: a guided run whose drawn perimeter
;;; needs more curves falls back to fitting from the points (the
;;; drawn shape still orders them), and an unreachably small cap
;;; returns the fewest-curves fit found - never the full-size one.
;;;
;;; The command rebuilds the perimeter as a single closed LWPOLYLINE
;;; (lines + arcs only, no splines) on layer "POOL-FIT":
;;;   * Every polyline vertex is snapped to the nearest surveyed point
;;;     within the tolerance (default 1 unit = 1 inch), so corners land
;;;     exactly on points whenever one is close enough.
;;;   * Every curved (arc/bulge) segment is re-fitted so that the arc
;;;     passes through the surveyed points lying along it.  A single
;;;     replacement arc is tried first (the best of the exact 3-point
;;;     arcs through the two snapped endpoints and the points, plus
;;;     their average), with its radius snapped to a nice increment
;;;     when possible; if it keeps every point within the tolerance
;;;     and the miss allowance can absorb the off ones, that ONE arc
;;;     is kept.  Only when that fails is the segment SUBDIVIDED into
;;;     a tangent-continuous chain of arcs through every point.
;;;   * Straight segments the user drew are trusted and kept straight
;;;     (only their endpoints snap to points); where the user found a
;;;     straight wall, the result has a straight wall.
;;;   * A point that turns more than *PF-CORNER-ANG* (45 deg) is a
;;;     sharp corner: it can start or end a span but is never buried
;;;     inside one, so polygonal shapes keep their corners as lines.
;;; Everything is fitted on the 2D plane - Z coordinates are ignored.
;;; Every segment shares its endpoints with its neighbours, so the
;;; result stays closed.
;;;
;;; A hit report is printed: how many points the new perimeter passes
;;; through exactly, how many are within tolerance, how many missed.
;;; ===================================================================

;; ---- configuration -------------------------------------------------
(setq *PF-POOL-LAYER*   "POOL")     ; layer holding the drawn perimeter
(setq *PF-POINT-LAYER*  "POINTS")   ; layer holding the survey points
(setq *PF-POINT-BLOCK*  "ab_pt")    ; block name whose INSERTs mark survey
                                    ; points; the block's insertion point
                                    ; is taken as the point location
(setq *PF-OUT-LAYER*    "POOL-FIT") ; layer the fitted polyline goes on
(setq *PF-MISS-LAYER*   "POOL-MISS"); layer the "could not hold this
                                    ; point" markers go on
(setq *PF-COMPARE*                  ; the three candidate fits offered:
  '((0.5 1 "red"    "tighter - hugs the points")
    (1.0 2 "yellow" "as asked")
    (2.0 4 "cyan"   "looser - fewer curves")))
                                    ; (tolerance factor, AutoCAD colour,
                                    ; colour name, description).  Edit
                                    ; the factors to change the spread.
(setq *PF-EXACT-EPS*    0.001)      ; "exactly on" threshold (units)
(setq *PF-FIT-EPS*      0.01)       ; if a single arc misses any of its
                                    ; points by more than this, split it
                                    ; into several arcs that hit exactly
(setq *PF-ON-EPS*       0.25)       ; a point within this of the result
                                    ; counts as ON it; only points off by
                                    ; more than this eat into the miss
                                    ; allowance below.  Calibrated from a
                                    ; hand-drawn reference trace: ~87% of
                                    ; its points sat within a quarter inch
(setq *PF-MISS-PCT*     0.15)       ; share of the points (rounded UP to
                                    ; a whole point) that may sit off the
                                    ; result by up to the tolerance
                                    ; (about an inch by default) - this
                                    ; slack is what buys longer spans and
                                    ; fewer curves
(setq *PF-CORNER-ANG*   (/ pi 4.0)) ; a point that turns more than this
                                    ; (45 deg) is a sharp corner: it may
                                    ; start or end a span but never gets
                                    ; buried inside one, so polygonal
                                    ; shapes keep their corners.  Sample
                                    ; real tight curves with at least ~3
                                    ; points per quarter turn to stay
                                    ; under it.
(setq *PF-NICE-RADII* '(12.0 6.0 1.0)) ; preferred arc-radius increments,
                                    ; tried in order: whole feet, half
                                    ; feet, whole inches (drawing units
                                    ; are inches).  A radius is snapped
                                    ; to the first increment whose arc
                                    ; still holds the points; only when
                                    ; none does is the free-fit ("weird")
                                    ; radius kept.
(setq *PF-TANG-TOL* (/ pi 22.5))    ; wiggle room from perfect
                                    ; tangency at each joint between two
                                    ; arcs (8 degrees).  Being ON the
                                    ; points matters more than perfect
                                    ; tangency; this slack is what lets
                                    ; every arc endpoint sit on a survey
                                    ; point and radii stay nice.
                                    ; Calibrated from a hand-drawn
                                    ; reference trace whose joints ran up
                                    ; to 7.9 deg (median 3 deg); tighter
                                    ; values shatter the fit into many
                                    ; short arcs (5 deg is workable,
                                    ; 6 deg and below is not).
(setq *PF-SNAP-EPS*     0.02)       ; a nice-radius snap may move the
                                    ; covered points at most this far
                                    ; beyond where they already sat, and
                                    ; it may never pull an arc off its
                                    ; anchor point entirely - the points
                                    ; outrank pretty radii
(setq *PF-CHAIN-FUZZ*   1.0e-4)     ; endpoint-matching fuzz for
                                    ; chaining exploded segments
(if (null *PF-TOL*) (setq *PF-TOL* 1.0)) ; default tolerance, 1 inch
;; *PF-MAX-ARCS* : cap on the number of curved segments in the output;
;; nil = no cap.  The command prompts for it (Enter keeps the current
;; value, "None" removes the cap) and remembers it for the session,
;; like *PF-TOL*.

;; ---- small 2D vector helpers ---------------------------------------
(defun pf:2d (p) (list (car p) (cadr p)))
(defun pf:dist (a b) (distance (pf:2d a) (pf:2d b)))
(defun pf:sub (a b) (mapcar '- (pf:2d a) (pf:2d b)))
(defun pf:add (a b) (mapcar '+ (pf:2d a) (pf:2d b)))
(defun pf:scl (v s) (list (* (car v) s) (* (cadr v) s)))
(defun pf:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun pf:mid (a b) (pf:scl (pf:add a b) 0.5))
(defun pf:perp (v) (list (- (cadr v)) (car v))) ; rotate 90 deg CCW

;; Tangent with the angle clamped just short of +/-90 degrees.  Every
;; bulge in this file is a tangent of a quarter-sweep, so a half-turn
;; quarter-sweep (a degenerate, full-circle segment) would otherwise
;; divide by zero and abort the command.  Clamping yields a huge but
;; finite bulge instead; the callers that can legitimately reach the
;; limit (full-circle ARCs and CIRCLEs) split themselves in half
;; before they get here, so this is purely a safety net.
(defun pf:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;; smallest integer >= X (X non-negative)
(defun pf:ceil (x / f)
  (setq f (fix x))
  (if (> x f) (1+ f) f))

;; the list from index K on / COUNT elements of LST starting at index K
(defun pf:nthcdr (k lst)
  (while (> k 0) (setq lst (cdr lst) k (1- k)))
  lst)
(defun pf:sublist (lst k count / out)
  (setq lst (pf:nthcdr k lst))
  (while (> count 0)
    (setq out   (cons (car lst) out)
          lst   (cdr lst)
          count (1- count)))
  (reverse out))

;; normalize an angle into [0, 2pi)
(defun pf:norm-ang (a)
  (while (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (while (>= a (* 2.0 pi)) (setq a (- a (* 2.0 pi))))
  a)

;; smallest signed angular difference (to - from), in (-pi, pi]
(defun pf:signed-dang (from to / d)
  (setq d (pf:norm-ang (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

;; ---- circle / arc geometry -----------------------------------------

;; Circumcenter of three points, nil when (nearly) collinear.
(defun pf:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
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
;; passes through Q.  0.0 when the three points are collinear, and
;; also when the arc would be a (near) full circle - P1 and P2 lying
;; at the same angle from the center makes the sweep 0 or 2*pi, which
;; no single bulge can express.  Nearly-collinear noisy survey points
;; can produce exactly that, so both ends of the range are guarded.
(defun pf:bulge-3pt (p1 q p2 / c a1 a2 aq dccw dq)
  (setq p1 (pf:2d p1) q (pf:2d q) p2 (pf:2d p2)
        c  (pf:circumcenter p1 q p2))
  (if (null c)
    0.0
    (progn
      (setq a1   (angle c p1)
            a2   (angle c p2)
            aq   (angle c q)
            dccw (pf:norm-ang (- a2 a1))
            dq   (pf:norm-ang (- aq a1)))
      (cond
        ((< dccw 1.0e-9) 0.0)                       ; degenerate sweep
        ((> dccw (- (* 2.0 pi) 1.0e-9)) 0.0)        ; degenerate sweep
        ((<= dq dccw) (pf:tan (/ dccw 4.0)))        ; CCW arc through Q
        (T (- (pf:tan (/ (- (* 2.0 pi) dccw) 4.0)))))))) ; CW through Q

;; Arc geometry of a bulged segment: (center radius angStart angEnd)
;; where the arc runs CCW from angStart to angEnd when bulge > 0 and
;; CW when bulge < 0.  nil for a straight segment.
(defun pf:arc-geom (p1 p2 b / ch dir apex c)
  (if (< (abs b) 1.0e-9)
    nil
    (progn
      (setq p1   (pf:2d p1)
            p2   (pf:2d p2)
            ch   (pf:dist p1 p2)
            dir  (pf:scl (pf:sub p2 p1) (/ 1.0 ch))
            ;; sagitta = (chord/2)*bulge; a positive (CCW) bulge apex
            ;; lies to the RIGHT of the p1->p2 chord direction
            apex (pf:add (pf:mid p1 p2)
                         (pf:scl (pf:perp dir) (* -0.5 ch b)))
            c    (pf:circumcenter p1 apex p2))
      (if (null c)
        nil
        (list c (pf:dist c p1) (angle c p1) (angle c p2))))))

;; Distance from point P to segment (p1 p2 bulge).
(defun pf:seg-dist (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep rel)
  (setq p  (pf:2d p)
        p1 (pf:2d (car seg))
        p2 (pf:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    ;; straight: project onto the segment, clamp to its ends
    (progn
      (setq v    (pf:sub p2 p1)
            w    (pf:sub p p1)
            len2 (pf:dot v v))
      (if (< len2 1.0e-20)
        (pf:dist p p1)
        (progn
          (setq t2 (/ (pf:dot w v) len2))
          (if (< t2 0.0) (setq t2 0.0))
          (if (> t2 1.0) (setq t2 1.0))
          (pf:dist p (pf:add p1 (pf:scl v t2))))))
    ;; arc: radial distance when P falls inside the sweep, else the
    ;; nearer endpoint
    (progn
      (setq g (pf:arc-geom p1 p2 b))
      (if (null g)
        (min (pf:dist p p1) (pf:dist p p2))
        (progn
          (setq c  (car g)  r (cadr g)
                a1 (caddr g) a2 (cadddr g)
                ap (angle c p))
          (if (> b 0.0)
            (setq sweep (pf:norm-ang (- a2 a1)) rel (pf:norm-ang (- ap a1)))
            (setq sweep (pf:norm-ang (- a1 a2)) rel (pf:norm-ang (- ap a2))))
          (if (<= rel sweep)
            (abs (- (pf:dist p c) r))
            (min (pf:dist p p1) (pf:dist p p2))))))))

;; Bulge of the arc that starts at A with tangent direction TANG
;; (radians) and ends at B.  The angle between a chord and the tangent
;; at its end is half the included angle, so delta = 2*phi.
(defun pf:tangent-bulge (a tang b / phi)
  (setq phi (pf:signed-dang tang (angle (pf:2d a) (pf:2d b))))
  (pf:tan (/ phi 2.0)))

;; Tangent direction (radians) at the END of the arc from A to B with
;; the given bulge: chord direction + delta/2, delta = 4*atan(bulge).
(defun pf:end-tangent (a b bulge)
  (+ (angle (pf:2d a) (pf:2d b)) (* 2.0 (atan bulge))))

;; Position of P along segment (p1 p2 bulge) as a 0..1 parameter,
;; used only to ORDER candidate points along the segment.
(defun pf:seg-param (p seg / p1 p2 b v w len2 g c a1 a2 ap sweep rel)
  (setq p  (pf:2d p)
        p1 (pf:2d (car seg))
        p2 (pf:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    (progn
      (setq v (pf:sub p2 p1) w (pf:sub p p1) len2 (pf:dot v v))
      (if (< len2 1.0e-20) 0.0 (/ (pf:dot w v) len2)))
    (progn
      (setq g (pf:arc-geom p1 p2 b))
      (if (null g)
        0.0
        (progn
          (setq c (car g) a1 (caddr g) a2 (cadddr g) ap (angle c p))
          (if (> b 0.0)
            (setq sweep (pf:norm-ang (- a2 a1))
                  rel   (pf:norm-ang (- ap a1)))
            (setq sweep (pf:norm-ang (- a1 a2))
                  rel   (- (pf:norm-ang (- a1 a2))
                           (pf:norm-ang (- ap a2)))))
          (if (< sweep 1.0e-10) 0.0 (/ rel sweep)))))))

;; ---- entity -> segment extraction ----------------------------------
;; A segment is (startPt endPt bulge), 2D points.

(defun pf:lw-segs (ed / pts bls item segs n closed)
  ;; collect (10) vertices and their (42) bulges, in order
  (setq pts nil bls nil)
  (foreach item ed
    (cond
      ((= (car item) 10)
       (setq pts (cons (pf:2d (cdr item)) pts)
             bls (cons 0.0 bls)))
      ((and (= (car item) 42) bls)
       (setq bls (cons (cdr item) (cdr bls))))))
  (setq pts (reverse pts) bls (reverse bls)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        segs nil n 0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  (if (and (> (length pts) 2)
           (or closed
               (< (pf:dist (last pts) (car pts)) *PF-CHAIN-FUZZ*)))
    (if (>= (pf:dist (last pts) (car pts)) *PF-CHAIN-FUZZ*)
      (setq segs (cons (list (last pts) (car pts) (last bls)) segs))))
  (reverse segs))

(defun pf:pl-segs (en / ed sub pts bls segs n closed)
  ;; heavy (old-style) 2D POLYLINE: walk its VERTEX sub-entities
  (setq ed (entget en)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        pts nil bls nil
        sub (entnext en))
  (while (and sub (= "VERTEX" (cdr (assoc 0 (setq ed (entget sub))))))
    ;; skip spline/fit control vertices (flag bits 1 and 16)
    (if (= 0 (logand 17 (cond ((cdr (assoc 70 ed))) (0))))
      (setq pts (cons (pf:2d (cdr (assoc 10 ed))) pts)
            bls (cons (cond ((cdr (assoc 42 ed))) (0.0)) bls)))
    (setq sub (entnext sub)))
  (setq pts (reverse pts) bls (reverse bls) segs nil n 0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  (if (and closed (> (length pts) 2))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun pf:ent-segs (en / ed typ c r a1 a2 delta)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (pf:2d (cdr (assoc 10 ed)))
                 (pf:2d (cdr (assoc 11 ed)))
                 0.0)))
    ((= typ "ARC")
     (setq c  (pf:2d (cdr (assoc 10 ed)))
           r  (cdr (assoc 40 ed))
           a1 (cdr (assoc 50 ed))
           a2 (cdr (assoc 51 ed))
           delta (pf:norm-ang (- a2 a1)))
     (if (< delta 1.0e-10) (setq delta (* 2.0 pi)))
     ;; a full-circle arc cannot be one bulged segment (its bulge is
     ;; infinite): hand back two semicircles instead
     (if (> delta (- (* 2.0 pi) 1.0e-9))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r) (pf:tan (/ delta 4.0))))))
    ;; a CIRCLE is a legitimate pool perimeter (round spa): two
    ;; semicircles, so the chaining and fitting code sees a normal
    ;; closed loop instead of reporting a gap
    ((= typ "CIRCLE")
     (setq c (pf:2d (cdr (assoc 10 ed)))
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
    ((= typ "LWPOLYLINE") (pf:lw-segs ed))
    ((= typ "POLYLINE") (pf:pl-segs en))
    (T nil)))

;; ---- chain loose segments into one closed loop ----------------------
;; Returns the ordered segment list, or nil (with a message) on failure.
(defun pf:chain (segs / loop start end found s rest)
  (if (null segs)
    nil
    (progn
      (setq loop  (list (car segs))
            start (car (car segs))
            end   (cadr (car segs))
            segs  (cdr segs))
      (while (and segs
                  (>= (pf:dist end start) *PF-CHAIN-FUZZ*))
        (setq found nil rest nil)
        (foreach s segs
          (cond
            (found (setq rest (cons s rest)))
            ((< (pf:dist end (car s)) *PF-CHAIN-FUZZ*)
             (setq found s))
            ((< (pf:dist end (cadr s)) *PF-CHAIN-FUZZ*)
             ;; reverse the segment: swap ends, negate the bulge
             (setq found (list (cadr s) (car s) (- (caddr s)))))
            (T (setq rest (cons s rest)))))
        (if found
          (setq loop (cons found loop)
                end  (cadr found)
                segs (reverse rest))
          (setq segs nil end nil)))  ; gap -> bail out
      (cond
        ((null end)
         (princ "\nABHD: gap in the POOL perimeter - could not close the loop.")
         nil)
        ((>= (pf:dist end start) *PF-CHAIN-FUZZ*)
         (princ "\nABHD: the POOL perimeter does not close.")
         nil)
        (T
         (if segs
           (princ (strcat "\nABHD: warning - "
                          (itoa (length segs))
                          " POOL segment(s) not part of the closed loop were ignored.")))
         (reverse loop))))))

;; ---- span fitting helpers --------------------------------------------
;; A "span" is one candidate segment from A to B judged against QS, the
;; survey points it is supposed to represent.

;; Worst distance from any of QS to the segment (A B bulge).
(defun pf:span-dev (a b bul qs / seg mx d q)
  (setq seg (list a b bul) mx 0.0)
  (foreach q qs
    (setq d (pf:seg-dist q seg))
    (if (> d mx) (setq mx d)))
  mx)

;; The "on the shape" threshold in force for the current run.  It
;; scales with the tolerance (a quarter of it, never below
;; *PF-ON-EPS*): if the user accepts 4 inches of error, a point 1 inch
;; off is plainly still ON the shape, and counting it as a miss would
;; burn the whole allowance on the first span and starve the rest of
;; the loop into single-point stubs.  pf-on-eps is bound per run by
;; the command and per pass by pf:fit-pass.
(defun pf:oneps ()
  (if pf-on-eps pf-on-eps *PF-ON-EPS*))

;; How many of QS sit farther than the on-the-shape threshold from the
;; segment - the points that would eat into the miss allowance.
(defun pf:span-misses (a b bul qs / seg c q lim)
  (setq seg (list a b bul) c 0 lim (pf:oneps))
  (foreach q qs
    (if (> (pf:seg-dist q seg) lim) (setq c (1+ c))))
  c)

;; Best single arc from A to B over the points QS: candidate bulges are
;; the exact 3-point fits through a few of the points plus the average
;; of them all; the one with the smallest worst-case deviation wins.
;; Returns (bulge . maxdev).
(defun pf:span-arc (a b qs / bls sum bl m cands best bd d)
  (setq bls (mapcar '(lambda (q) (pf:bulge-3pt a q b)) qs)
        sum 0.0
        m   (length qs))
  (foreach bl bls (setq sum (+ sum bl)))
  (setq cands (list (/ sum m) (nth (/ m 2) bls)))
  (if (>= m 4)
    (setq cands (append cands (list (nth (/ m 4) bls)
                                    (nth (/ (* 3 m) 4) bls)))))
  (setq best nil bd nil)
  (foreach bl cands
    (setq d (pf:span-dev a b bl qs))
    (if (or (null bd) (< d bd)) (setq best bl bd d)))
  (cons best bd))

;; Radius of the arc (A B bulge); nil for a straight segment.
(defun pf:bulge-radius (a b bl / h)
  (if (< (abs bl) 1.0e-9)
    nil
    (progn
      (setq h (/ (pf:dist a b) 2.0))
      (/ (* h (1+ (* bl bl))) (* 2.0 (abs bl))))))

;; Bulge of the arc from A to B with radius R, on the same side and
;; with the same minor/major-arc character as reference bulge BREF.
;; nil when R is too small to span the chord.
(defun pf:radius-bulge (a b r bref / h s bl)
  (setq h (/ (pf:dist a b) 2.0))
  (if (or (< r h) (< h 1.0e-9))
    nil
    (progn
      (setq s  (sqrt (- (* r r) (* h h)))
            bl (if (> (abs bref) 1.0)
                 (/ (+ r s) h)              ; major arc
                 (/ (- r s) h)))            ; minor arc
      (if (< bref 0.0) (- bl) bl))))

;; Try to snap the arc A->B (free-fit bulge BL over points QS) to a
;; "nice" radius - whole feet first, then half feet, then whole inches
;; (*PF-NICE-RADII*) - keeping every point within TOL and at most LEFT
;; of them off by more than *PF-ON-EPS*.  When WIN (a bulge interval)
;; is given the snapped bulge must stay inside it, so snapping never
;; breaks the tangency window.  The nearer multiple on each tier is
;; tried first; the arc's endpoints never move.  Returns
;; (bulge . misses) of the snapped arc, or nil.
(defun pf:snap-arc (a b bl qs tol left win / r0 h best tier lo hi
                                              cands r bl2 mis)
  (setq r0   (pf:bulge-radius a b bl)
        h    (/ (pf:dist a b) 2.0)
        best nil)
  (if (and r0 (< r0 1.0e6))       ; a huge radius is basically straight
    (foreach tier *PF-NICE-RADII*
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
                (setq bl2 (pf:radius-bulge a b r bl))
                (if (and bl2
                         (or (null win)
                             (and (>= bl2 (car win)) (<= bl2 (cdr win))))
                         (<= (pf:span-dev a b bl2 qs) tol)
                         (<= (setq mis (pf:span-misses a b bl2 qs))
                             left))
                  (setq best (cons bl2 mis))))))))))
  best)

;; ---- arc segment re-fitting ------------------------------------------
;; Re-fit one curved segment from P1 to P2 (original bulge B) through
;; CANDS, its nearby survey points sorted along the segment.  Returns a
;; list of one or more segments (p1 p2 bulge):
;;   * no candidates          -> the original arc, endpoints updated
;;   * a nice-radius (foot / half-foot / inch) arc holds every point
;;     within TOL and the miss allowance (pf-miss-left, set by the
;;     command) can absorb the off points
;;                            -> that single snapped arc, preferred
;;                               even over an exact free fit
;;   * one arc holds them all -> that single arc
;;   * one free arc keeps every point within TOL and the allowance
;;     covers it              -> that single arc; fewer curves beats
;;                               exactness, by design
;;   * otherwise              -> a tangent-continuous chain of arcs
;;                               passing exactly through every point
(defun pf:cap-bulge (b)
  (cond ((> b 5.0) 5.0) ((< b -5.0) -5.0) (T b)))

(defun pf:fit-arc-seg (p1 p2 b cands tol / ar bavg maxres mis nb q segs
                                            prev tang sn)
  (if (null cands)
    (list (list p1 p2 b))
    (progn
      (setq ar     (pf:span-arc p1 p2 cands)
            bavg   (car ar)
            maxres (cdr ar)
            sn     (pf:snap-arc p1 p2 bavg cands tol pf-miss-left nil))
      (cond
        ;; a nice-radius arc holds every point: take it first
        (sn
         (setq pf-miss-left (- pf-miss-left (cdr sn)))
         (list (list p1 p2 (car sn))))
        ;; a single free arc genuinely holds every point
        ((<= maxres *PF-FIT-EPS*)
         (list (list p1 p2 bavg)))
        ;; a single arc is close enough and the allowance covers it
        ((and (<= maxres tol)
              (<= (setq mis (pf:span-misses p1 p2 bavg cands))
                  pf-miss-left))
         (setq pf-miss-left (- pf-miss-left mis))
         (list (list p1 p2 bavg)))
        ;; subdivide.  First arc runs from P1 through the 1st point to
        ;; the 2nd; every further arc starts tangent to the previous one
        ;; and lands exactly on the next point; the last lands on P2.
        ;; All points are hit exactly and every internal joint is
        ;; tangent-continuous (smooth).
        (T
         (setq nb   (pf:bulge-3pt p1 (car cands) (cadr cands))
               segs (list (list p1 (cadr cands) nb))
               tang (pf:end-tangent p1 (cadr cands) nb)
               prev (cadr cands))
         (foreach q (cddr cands)
           (setq nb   (pf:cap-bulge (pf:tangent-bulge prev tang q))
                 segs (cons (list prev q nb) segs)
                 tang (pf:end-tangent prev q nb)
                 prev q))
         (setq nb (pf:cap-bulge (pf:tangent-bulge prev tang p2)))
         (reverse (cons (list prev p2 nb) segs)))))))

;; ---- points-only / ordering-sketch mode -------------------------------

;; Pure-AutoLISP list helpers (no Visual LISP / vl-* dependency, so the
;; command works even when (vl-load-com) has not been run).

;; Remove every element equal (within fuzz) to VAL from LST.
(defun pf:remove (val lst / out x)
  (foreach x lst
    (if (not (equal x val 1.0e-9)) (setq out (cons x out))))
  (reverse out))

;; Insert (key . val) pair X into the already-sorted list LST, keeping
;; ascending order by the pair's car (key).
(defun pf:ins-car (x lst)
  (cond ((null lst) (list x))
        ((< (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (pf:ins-car x (cdr lst))))))

;; Insertion-sort a list of (key . val) pairs ascending by key.
(defun pf:sort-car (lst / out x)
  (foreach x lst (setq out (pf:ins-car x out)))
  out)

(defun pf:dedupe (pts / out q p dup)
  (foreach q pts
    (setq dup nil)
    (foreach p out
      (if (< (pf:dist p q) *PF-EXACT-EPS*) (setq dup T)))
    (if (not dup) (setq out (cons q out))))
  (reverse out))

;; T when the chained loop contains at least one curved segment
(defun pf:has-arcs (loop / r)
  (foreach s loop (if (>= (abs (caddr s)) 1.0e-9) (setq r T)))
  r)

;; Order points into a closed tour: nearest-neighbour walk from the
;; leftmost point, then 2-opt passes to remove crossings.
(defun pf:order-points (pts / start cur tour rest best bd q d n i j k
                              pass improved ti ti1 tj tj1 delta head midl
                              taill)
  (setq start (car pts))
  (foreach q (cdr pts)
    (if (or (< (car q) (car start))
            (and (= (car q) (car start)) (< (cadr q) (cadr start))))
      (setq start q)))
  (setq cur  start
        rest (pf:remove start pts)
        tour (list start))
  (while rest
    (setq best nil bd nil)
    (foreach q rest
      (setq d (pf:dist cur q))
      (if (or (null bd) (< d bd)) (setq best q bd d)))
    (setq tour (cons best tour)
          cur  best
          rest (pf:remove best rest)))
  (setq tour (reverse tour)
        n    (length tour)
        pass 0
        improved T)
  (while (and improved (< pass 40))
    (setq improved nil pass (1+ pass) i 0)
    (while (< i (1- n))
      (setq j (1+ i))
      (while (< j n)
        (if (not (and (= i 0) (= j (1- n))))
          (progn
            (setq ti    (nth i tour)
                  ti1   (nth (1+ i) tour)
                  tj    (nth j tour)
                  tj1   (nth (rem (1+ j) n) tour)
                  delta (- (+ (pf:dist ti tj) (pf:dist ti1 tj1))
                           (+ (pf:dist ti ti1) (pf:dist tj tj1))))
            (if (< delta -1.0e-9)
              (progn                    ; reverse tour[i+1 .. j]
                (setq head nil midl nil taill nil k 0)
                (foreach q tour
                  (cond ((<= k i) (setq head (cons q head)))
                        ((<= k j) (setq midl (cons q midl)))
                        (T        (setq taill (cons q taill))))
                  (setq k (1+ k)))
                (setq tour     (append (reverse head) midl (reverse taill))
                      improved T)))))
        (setq j (1+ j)))
      (setq i (1+ i))))
  tour)

;; Order points by their position along a user-drawn ordering sketch
;; (the chained loop): each point keys on segment-index + parameter.
(defun pf:loop-order (loop pts / keyed q best bd d i s tp)
  (foreach q pts
    (setq best 0 bd nil i 0)
    (foreach s loop
      (setq d (pf:seg-dist q s))
      (if (or (null bd) (< d bd)) (setq bd d best i))
      (setq i (1+ i)))
    (setq tp (pf:seg-param q (nth best loop)))
    (if (< tp 0.0) (setq tp 0.0))
    (if (> tp 1.0) (setq tp 1.0))
    (setq keyed (cons (cons (+ best tp) q) keyed)))
  (mapcar 'cdr (pf:sort-car keyed)))

;; Rotate the closed TOUR so it starts at its sharpest turn: the fitter
;; walks the loop from there, so the most corner-like point is always a
;; span endpoint and never gets buried inside a span.
(defun pf:rotate-to-corner (tour / n i prev cur next turn best bi)
  (setq n (length tour) i 0 best -1.0 bi 0)
  (repeat n
    (setq prev (nth (rem (+ i n -1) n) tour)
          cur  (nth i tour)
          next (nth (rem (1+ i) n) tour)
          turn (abs (pf:signed-dang (angle prev cur) (angle cur next))))
    (if (> turn best) (setq best turn bi i))
    (setq i (1+ i)))
  (append (pf:nthcdr bi tour) (pf:sublist tour 0 bi)))

;; Number of curved segments in a span list.
(defun pf:arc-count (spans / c sp)
  (setq c 0)
  (foreach sp spans (if (>= (abs (caddr sp)) 1.0e-9) (setq c (1+ c))))
  c)

;; ---- near-tangent span fitting ---------------------------------------
;; Arcs sit ON the survey points: every span runs from tour point to
;; tour point and its interior is fitted through the points with exact
;; 3-point arcs.  Tangency is a WINDOW, not a chain: at each joint the
;; new arc's start tangent may differ from the previous arc's end
;; tangent by at most *PF-TANG-TOL* (8 degrees), so the perimeter
;; stays visually smooth while the points stay in charge.  A bulge
;; window is a cons (lo . hi); nil means unconstrained.

;; Allowed bulge interval for the span A->B whose START tangent must
;; lie within *PF-TANG-TOL* of the incoming tangent TE.  The window
;; edges are clamped so extreme (U-turn) geometry stays finite.
(defun pf:tang-window (te a b / phi alo ahi lo hi)
  (setq phi (pf:signed-dang te (angle a b))
        alo (max (min (/ (- phi *PF-TANG-TOL*) 2.0) 1.373) -1.373)
        ahi (max (min (/ (+ phi *PF-TANG-TOL*) 2.0) 1.373) -1.373)
        lo  (pf:tan alo)
        hi  (pf:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Allowed bulge interval for the CLOSING span A->B whose END tangent
;; must lie within *PF-TANG-TOL* of the loop's start tangent TS0.
(defun pf:end-window (ts0 a b / psi alo ahi lo hi)
  (setq psi (pf:signed-dang (angle a b) ts0)
        alo (max (min (/ (- psi *PF-TANG-TOL*) 2.0) 1.373) -1.373)
        ahi (max (min (/ (+ psi *PF-TANG-TOL*) 2.0) 1.373) -1.373)
        lo  (pf:tan alo)
        hi  (pf:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Intersect two bulge windows.  When they don't overlap no bulge can
;; satisfy both joints, so the bulge halfway between them is used and
;; the leftover kink is split evenly across the two joints.
(defun pf:merge-windows (win win2 / lo hi)
  (cond
    ((null win) win2)
    ((null win2) win)
    (T
     (setq lo (max (car win) (car win2))
           hi (min (cdr win) (cdr win2)))
     (if (<= lo hi)
       (cons lo hi)
       (progn
         (setq lo (if (< (cdr win) (car win2))
                    (/ (+ (cdr win) (car win2)) 2.0)
                    (/ (+ (cdr win2) (car win)) 2.0)))
         (cons lo lo))))))

;; Clamp bulge B into window WIN (nil = unconstrained).
(defun pf:clamp-b (b win)
  (cond ((null win) b)
        ((< b (car win)) (car win))
        ((> b (cdr win)) (cdr win))
        (T b)))

;; Closest any of QS comes to the segment (A B bulge) - used to test
;; whether an arc still passes through one of its interior points.
(defun pf:span-min (a b bul qs / seg mn d q)
  (setq seg (list a b bul) mn nil)
  (foreach q qs
    (setq d (pf:seg-dist q seg))
    (if (or (null mn) (< d mn)) (setq mn d)))
  mn)

;; Best bulge for the span A->B over interior points QS, restricted to
;; the tangent window WIN (nil = free).  EXACT 3-POINT ARCS COME
;; FIRST: an unclamped 3-point bulge through one of the actual
;; interior points - so the arc's middle lands ON a survey point - is
;; preferred whenever one holds the span within TOL and LEFT misses.
;; Compromise bulges (average / window-clamped / window edges), which
;; float between the points, are used only when no exact arc works.
;; Returns (bulge dev misses exactflag).
(defun pf:span-fit (a b qs win tol left / bls m sum bl cands best d mis)
  (setq bls  (mapcar '(lambda (q) (pf:bulge-3pt a q b)) qs)
        m    (length qs)
        best nil)
  ;; exact candidates: through an interior point AND inside the window
  (foreach bl bls
    (if (or (null win)
            (and (>= bl (car win)) (<= bl (cdr win))))
      (progn
        (setq d (pf:span-dev a b bl qs))
        (if (and (<= d tol)
                 (or (null best) (< d (cadr best))))
          (progn
            (setq mis (pf:span-misses a b bl qs))
            (if (<= mis left)
              (setq best (list bl d mis T))))))))
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
        (setq cands (append (mapcar '(lambda (bl) (pf:clamp-b bl win))
                                    cands)
                            (list (car win) (cdr win)
                                  (/ (+ (car win) (cdr win)) 2.0)))))
      (foreach bl cands
        (setq d (pf:span-dev a b bl qs))
        (if (or (null best) (< d (cadr best)))
          (setq best (list bl d (pf:span-misses a b bl qs) nil))))))
  best)

;; Cover the rotated closed TOUR with arcs whose endpoints sit ON the
;; tour points, every joint within *PF-TANG-TOL* of tangent.  Sharp
;; corners stay free kinks.  TE0 (may be nil) seeds the first span's
;; tangent window - used to close the seam.  LEFT is the miss
;; allowance for this pass; when PRO is true each span may spend only
;; its own fair share of it, so one greedy span cannot exhaust the
;; budget and starve the rest of the loop (the curve cap turns PRO off
;; because there the whole point is to trade accuracy for few curves).
;; Returns the segment list.
(defun pf:span-loop (tour tol left te0 pro / n sharp i prev cur next
                                             turn strtshp segs pos te
                                             ts0 lim a best bstx len go
                                             bnd win qs fr bl mis sn
                                             dev0 anch relax tries lm)
  (setq n (length tour))
  ;; flag the sharp corners (intentional kinks, window resets)
  (setq sharp nil i 0)
  (repeat n
    (setq prev (nth (rem (+ i n -1) n) tour)
          cur  (nth i tour)
          next (nth (rem (1+ i) n) tour)
          turn (abs (pf:signed-dang (angle prev cur) (angle cur next))))
    (setq sharp (cons (> turn *PF-CORNER-ANG*) sharp)
          i     (1+ i)))
  (setq sharp   (reverse sharp)
        strtshp (car sharp)
        segs    nil
        pos     0
        te      (if strtshp nil te0)
        ts0     nil)
  (while (< pos n)
    ;; one span may never swallow the whole loop: the first span stops
    ;; one point short so the result always has at least two real
    ;; segments instead of a single zero-length one
    (setq lim  (if (= pos 0) (1- (- n pos)) (- n pos))
          a    (nth pos tour)
          best nil                   ; longest feasible span of any kind
          bstx nil                   ; longest span through an interior point
          relax nil
          tries 0)
    ;; first pass honours the tangent window; if nothing at all fits
    ;; inside it, a second pass drops the window rather than emitting a
    ;; one-point stub, which would continue a tangent that clearly does
    ;; not suit the data and tends to cascade into a run of stubs
    (while (and (null best) (< tries 2))
      (setq len 2 go T)
      (while (and go (<= len lim))
        (if (nth (rem (+ pos len -1) n) sharp)
          (setq go nil)              ; never bury a corner in a span
          (progn
            (setq bnd (nth (rem (+ pos len) n) tour))
            (if relax
              (setq win nil)
              (progn
                (setq win (if te (pf:tang-window te a bnd)))
                ;; the span that closes the loop must also end within
                ;; the tangent window of the loop's start
                (if (and (= (+ pos len) n) (not strtshp) ts0)
                  (setq win (pf:merge-windows win
                                              (pf:end-window ts0 a bnd))))))
            (setq qs (pf:sublist tour (1+ pos) (1- len))
                  lm (if pro
                       (min left (pf:ceil (* *PF-MISS-PCT* len)))
                       left)
                  fr (pf:span-fit a bnd qs win tol lm))
            (if (and (<= (cadr fr) tol) (<= (caddr fr) lm))
              (progn
                (setq best (list len (car fr) (caddr fr) win))
                (if (cadddr fr) (setq bstx best))
                (setq len (1+ len)))
              (setq go nil)))))
      (setq relax T tries (1+ tries)))
    ;; an arc that floats between the points has to earn its keep:
    ;; only take it when it covers at least 2 more points than the
    ;; longest arc that passes exactly through a point
    (if (and bstx best (< (car best) (+ (car bstx) 2)))
      (setq best bstx))
    (if (null best)
      ;; stub to the very next point: continue the incoming tangent
      ;; (clamped to a semicircle); with no tangent it stays straight
      (progn
        (setq bnd (nth (rem (1+ pos) n) tour))
        (if te
          (progn
            (setq bl (pf:tangent-bulge a te bnd))
            (if (and (= (1+ pos) n) (not strtshp) ts0)
              ;; closing stub: split the kink between both joints
              (setq bl (/ (+ bl (pf:tan (/ (pf:signed-dang (angle a bnd)
                                                           ts0)
                                           2.0)))
                          2.0)))
            (if (> bl 1.0) (setq bl 1.0))
            (if (< bl -1.0) (setq bl -1.0)))
          (setq bl 0.0))
        (setq best (list 1 bl 0 nil)))
      ;; nice-radius snap inside the same tangent window.  A snap may
      ;; never pull the arc off its points: covered points may only
      ;; move a hair (*PF-SNAP-EPS*) beyond where they already sat,
      ;; and an arc that passed through an interior point must still
      ;; pass through one after snapping.
      (progn
        (setq len  (car best)
              bl   (cadr best)
              win  (cadddr best)
              bnd  (nth (rem (+ pos len) n) tour)
              qs   (pf:sublist tour (1+ pos) (1- len))
              dev0 (pf:span-dev a bnd bl qs)
              anch (<= (pf:span-min a bnd bl qs) (* 2.0 *PF-FIT-EPS*))
              sn   (pf:snap-arc a bnd bl qs
                                (max dev0 *PF-SNAP-EPS*) left win))
        (if (and sn
                 (or (not anch)
                     (<= (pf:span-min a bnd (car sn) qs)
                         (* 2.0 *PF-FIT-EPS*))))
          (setq best (list len (car sn) (cdr sn) win)))))
    (setq len  (car best)
          bl   (cadr best)
          mis  (caddr best)
          bnd  (nth (rem (+ pos len) n) tour)
          segs (cons (list a bnd bl) segs)
          left (- left mis))
    (if (and (null ts0) (not strtshp))
      (setq ts0 (- (angle a bnd) (* 2.0 (atan bl)))))
    (setq pos (+ pos len)
          te  (if (nth (rem pos n) sharp)
                nil
                (+ (angle a bnd) (* 2.0 (atan bl))))))
  (reverse segs))

;; Tangent mismatch at the loop's closing joint (radians).
(defun pf:seam-kink (segs / sl sf te ts)
  (setq sl (last segs)
        sf (car segs)
        te (+ (angle (car sl) (cadr sl)) (* 2.0 (atan (caddr sl))))
        ts (- (angle (car sf) (cadr sf)) (* 2.0 (atan (caddr sf)))))
  (abs (pf:signed-dang te ts)))

;; One full fit; if the seam closes with more than *PF-TANG-TOL* of
;; kink, refit once seeding the first span's window with the arrival
;; tangent, and keep whichever seam is straighter.  The on-the-shape
;; threshold is bound here so it tracks this pass's tolerance.
(defun pf:fit-pass (tour tol left pro / segs k1 sl te0 segs2 pf-on-eps)
  (setq pf-on-eps (max *PF-ON-EPS* (* 0.25 tol))
        segs      (pf:span-loop tour tol left nil pro)
        k1        (pf:seam-kink segs))
  (if (> k1 (+ *PF-TANG-TOL* 0.001))
    (progn
      (setq sl    (last segs)
            te0   (+ (angle (car sl) (cadr sl))
                     (* 2.0 (atan (caddr sl))))
            segs2 (pf:span-loop tour tol left te0 pro))
      (if (< (pf:seam-kink segs2) k1) (setq segs segs2))))
  segs)

;; Points-only / ordering-sketch fit: arcs on the points, joints
;; within *PF-TANG-TOL* of tangent, nice radii.  The curve cap is
;; enforced by refitting the whole loop with a progressively relaxed
;; tolerance, which keeps the tangent windows intact.  The
;; fewest-curves result seen is kept, so an unreachably small cap
;; still returns the smallest fit possible - never the biggest.
(defun pf:coarse-loop (tour tol maxarcs / segs segs2 tol2 tries)
  (setq tour (pf:rotate-to-corner tour)
        segs (pf:fit-pass tour tol pf-miss-left T))
  ;; the cap deliberately buys few curves with accuracy, so the refits
  ;; drop both the miss allowance and the per-span fair share
  (if maxarcs
    (progn
      (setq tol2 tol tries 0)
      (while (and (> (pf:arc-count segs) maxarcs) (< tries 40))
        (setq tol2  (* tol2 1.4)
              tries (1+ tries)
              segs2 (pf:fit-pass tour tol2 1000000 nil))
        (if (< (pf:arc-count segs2) (pf:arc-count segs))
          (setq segs segs2)))))
  segs)

;; ---- self-intersection check -----------------------------------------
;; A loop that crosses itself almost always means the automatic point
;; ordering went around a narrow waist the wrong way.  We cannot fix
;; that from the points alone, but we can spot it and say so.

;; Cross product of (P-O) x (Q-O); its sign says which side Q is on.
(defun pf:cross3 (o p q)
  (- (* (- (car p) (car o)) (- (cadr q) (cadr o)))
     (* (- (cadr p) (cadr o)) (- (car q) (car o)))))

;; T when segments A-B and C-D properly cross.  Touching or shared
;; endpoints give a zero product and do not count.
(defun pf:segs-cross (a b c d / d1 d2 d3 d4)
  (setq d1 (pf:cross3 a b c) d2 (pf:cross3 a b d)
        d3 (pf:cross3 c d a) d4 (pf:cross3 c d b))
  (and (< (* d1 d2) 0.0) (< (* d3 d4) 0.0)))

;; Sample the fitted loop into a point list; arcs get intermediate
;; points so a bulging arc's real path is tested, not just its chord.
(defun pf:loop-pts (segs / out s g c r a1 a2 sweep k j aa)
  (setq out nil)
  (foreach s segs
    (setq out (cons (pf:2d (car s)) out))
    (if (>= (abs (caddr s)) 1.0e-9)
      (progn
        (setq g (pf:arc-geom (car s) (cadr s) (caddr s)))
        (if g
          (progn
            (setq c  (car g)   r  (cadr g)
                  a1 (caddr g) a2 (cadddr g))
            (if (> (caddr s) 0.0)
              (setq sweep (pf:norm-ang (- a2 a1)))
              (setq sweep (- (pf:norm-ang (- a1 a2)))))
            (setq k 4 j 1)
            (while (< j k)
              (setq aa  (+ a1 (* sweep (/ (float j) (float k))))
                    out (cons (list (+ (car c) (* r (cos aa)))
                                    (+ (cadr c) (* r (sin aa))))
                              out)
                    j   (1+ j))))))))
  (reverse out))

;; T when the fitted loop crosses itself.
(defun pf:self-crosses (segs / p n found ti tj i j a b c d)
  (setq p (pf:loop-pts segs))
  (if (< (length p) 4)
    nil
    (progn
      (setq p     (append p (list (car p)))  ; close the point ring
            n     (1- (length p))            ; number of chords
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
          ;; the first and last chords legitimately share a vertex
          (if (not (and (= i 0) (= j (1- n))))
            (if (pf:segs-cross a b c d) (setq found T)))
          (setq tj (cdr tj) j (1+ j)))
        (setq ti (cdr ti) i (1+ i)))
      found)))

;; ---- output helpers --------------------------------------------------
;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun pf:ensure-layer (name colour / rec ed flags col fixed)
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
          (princ (strcat "\nABHD: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;; How many fitted polylines are already on the output layer (counted
;; before the new one is drawn).
(defun pf:prior-fits (/ ss)
  (setq ss (ssget "_X" (list (cons 8 *PF-OUT-LAYER*)
                             '(0 . "LWPOLYLINE"))))
  (if ss (sslength ss) 0))

;; T when R is a whole multiple of one of the *PF-NICE-RADII* tiers.
(defun pf:nice-radius-p (r / found tier q)
  (setq found nil)
  (if (and r (< r 1.0e6))
    (foreach tier *PF-NICE-RADII*
      (setq q (/ r tier))
      (if (< (abs (- q (fix (+ q 0.5)))) 1.0e-6) (setq found T))))
  found)

;; verts: list of (pt bulge) in order, closed.  COL is an AutoCAD
;; colour index, or nil for BYLAYER.
(defun pf:make-pline (verts layer col / dxf v)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                  (cons 8 layer)))
  (if col (setq dxf (append dxf (list (cons 62 col)))))
  (setq dxf (append dxf (list '(100 . "AcDbPolyline")
                              (cons 90 (length verts)) '(70 . 1))))
  (foreach v verts
    (setq dxf (append dxf (list (cons 10 (car v)) (cons 42 (cadr v))))))
  (entmakex dxf))

;; Put an entity's colour back to BYLAYER (used on the fit the user
;; keeps, so the preview colours do not linger in the drawing).
(defun pf:set-bylayer (en / ed)
  (setq ed (entget en))
  (if (assoc 62 ed) (entmod (subst '(62 . 256) (assoc 62 ed) ed))))

;; Pad S with spaces to width W, for the comparison table.
(defun pf:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; The points SEGS fails to hold within TOL.
(defun pf:unheld (segs pts tol / out q s d dmin)
  (setq out nil)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (pf:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin tol) (setq out (cons q out))))
  (reverse out))

;; List membership by position, within the exact-point fuzz.
(defun pf:memb (q lst / found p)
  (setq found nil)
  (foreach p lst
    (if (< (pf:dist p q) *PF-EXACT-EPS*) (setq found T)))
  found)

(defun pf:isect (a b / out q)
  (setq out nil)
  (foreach q a
    (if (pf:memb q b) (setq out (cons q out))))
  (reverse out))

;; Ring every point the chosen fit could not hold, on its own layer,
;; so they are easy to zoom to and judge: a mis-shot, a duplicate, or
;; a real feature the tolerance is too tight for.
(defun pf:mark-unheld (bad tol / r q)
  (if bad
    (progn
      (pf:ensure-layer *PF-MISS-LAYER* 1)
      (setq r (max (* 3.0 tol) 1.0))
      (foreach q bad
        (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                        (cons 8 *PF-MISS-LAYER*) '(100 . "AcDbCircle")
                        (cons 10 (list (car q) (cadr q) 0.0))
                        (cons 40 r)))))))

;; Print the hit report for the fit the user kept.  ALLOW is the run's
;; miss allowance (how many points were permitted to sit between the
;; on-the-shape threshold and the tolerance off the result).
(defun pf:report (newsegs pts tol allow prior / nl na hiton hitok miss
                                                q s s2 d dmin worst nice
                                                onpt inner ns i te ts kk
                                                mk nk pf-on-eps)
  ;; report against the same on-the-shape threshold the fit used
  (setq pf-on-eps (max *PF-ON-EPS* (* 0.25 tol)))
  (progn
      ;; -- segment mix, nice radii, arcs anchored on a point --------
      (setq nl 0 na 0 nice 0 onpt 0)
      (foreach s newsegs
        (if (< (abs (caddr s)) 1.0e-9)
          (setq nl (1+ nl))
          (progn
            (setq na (1+ na))
            (if (pf:nice-radius-p
                  (pf:bulge-radius (car s) (cadr s) (caddr s)))
              (setq nice (1+ nice)))
            ;; does this arc pass through a point other than its ends?
            (setq inner nil)
            (foreach q pts
              (if (and (> (pf:dist q (car s)) *PF-EXACT-EPS*)
                       (> (pf:dist q (cadr s)) *PF-EXACT-EPS*)
                       (<= (pf:seg-dist q s) (* 2.0 *PF-FIT-EPS*)))
                (setq inner T)))
            (if inner (setq onpt (1+ onpt))))))
      ;; -- how the survey points landed ------------------------------
      (setq hiton 0 hitok 0 miss 0 worst 0.0)
      (foreach q pts
        (setq dmin nil)
        (foreach s newsegs
          (setq d (pf:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (if (> dmin worst) (setq worst dmin))
        (cond
          ((<= dmin (pf:oneps)) (setq hiton (1+ hiton)))
          ((<= dmin tol)        (setq hitok (1+ hitok)))
          (T                    (setq miss  (1+ miss)))))
      ;; -- smoothness: worst kink at a joint that is not a corner ----
      (setq ns (length newsegs) i 0 mk 0.0 nk 0)
      (while (< i ns)
        (setq s  (nth i newsegs)
              s2 (nth (rem (1+ i) ns) newsegs)
              te (+ (angle (car s) (cadr s)) (* 2.0 (atan (caddr s))))
              ts (- (angle (car s2) (cadr s2)) (* 2.0 (atan (caddr s2))))
              kk (abs (pf:signed-dang te ts)))
        (if (<= kk *PF-CORNER-ANG*)     ; bigger = an intentional corner
          (progn
            (if (> kk mk) (setq mk kk))
            (if (> kk (+ *PF-TANG-TOL* 1.0e-6)) (setq nk (1+ nk)))))
        (setq i (1+ i)))
      (princ (strcat "\nABHD: " (itoa ns) " segments ("
                     (itoa nl) " lines + " (itoa na)
                     " curves) written to layer " *PF-OUT-LAYER* "."
                     "\n  Points on the perimeter:      " (itoa hiton)
                     "\n  Points off within tolerance:  " (itoa hitok)
                     "  (allowance " (itoa allow) ")"
                     "\n  Points beyond tolerance:      " (itoa miss)
                     "\n  Worst point deviation:        " (rtos worst 2 3)
                     "\n  Curves through a point:       " (itoa onpt)
                     " of " (itoa na)
                     "\n  Curves on foot/half/inch radii:" (itoa nice)
                     " of " (itoa na)
                     "\n  Largest joint kink:           "
                     (rtos (* 180.0 (/ mk pi)) 2 1) " deg  (limit "
                     (rtos (* 180.0 (/ *PF-TANG-TOL* pi)) 2 1) ")"))
      (if (> nk 0)
        (princ (strcat "\n  (" (itoa nk)
                       " joint(s) needed more than the tangent limit to"
                       " close the loop)")))
      (if (and *PF-MAX-ARCS* (> na *PF-MAX-ARCS*))
        (princ (strcat "\n  (the curve cap is " (itoa *PF-MAX-ARCS*)
                       " but " (itoa na) " curves was the fewest"
                       " reachable: a closed loop needs at least 2"
                       " segments)")))
      (if (> miss 0)
        (princ "\n  (points beyond tolerance: the curve cap and/or the drawn shape overruled them)"))
      (if (pf:self-crosses newsegs)
        (princ (strcat "\n  WARNING: the result crosses itself - the"
                       " automatic point order is probably wrong."
                       "  Draw a rough lines-only loop on layer "
                       *PF-POOL-LAYER*
                       " through the points in the right order and"
                       " select it too.")))
      (if (> prior 0)
        (princ (strcat "\n  (" (itoa prior)
                       " earlier fit(s) were already on layer "
                       *PF-OUT-LAYER* " - erase them if you only want"
                       " the new one)"))))
  (princ))

;; ---- guided mode ------------------------------------------------------
;; Re-fit the drawn perimeter LOOP through the survey points: every
;; vertex snaps to the nearest point within TOL, every drawn arc is
;; re-fitted through the points lying along it, and drawn straight
;; walls stay straight.  If the result needs more curves than the cap
;; allows, the fit falls back to the points-driven builder - the drawn
;; loop still supplies the point order.
(defun pf:guided-fit (loop pts dpts tol allow / verts used n s p1 p2 b
                                                cands clean ns newsegs
                                                q d)
  ;; -- 1. snap each vertex to its nearest point within tol ----------
  (setq verts (mapcar '(lambda (s) (car s)) loop)
        used  nil)
  (setq verts
    (mapcar
      '(lambda (v / best bd)
         (setq best nil bd tol)
         (foreach q pts
           (setq d (pf:dist v q))
           (if (and (<= d bd) (not (member q used)))
             (setq best q bd d)))
         (if best (progn (setq used (cons best used)) best) v))
      verts))
  ;; -- 2. re-fit every arc segment through the points near it -------
  (setq newsegs nil n 0)
  (repeat (length loop)
    (setq s  (nth n loop)
          p1 (nth n verts)
          p2 (nth (rem (1+ n) (length verts)) verts)
          b  (caddr s))
    (if (< (abs b) 1.0e-9)
      ;; straight wall: trust the user, keep it straight
      (setq newsegs (cons (list p1 p2 0.0) newsegs))
      (progn
        ;; survey points lying near the ORIGINAL arc, excluding the
        ;; ones already consumed as vertices, sorted along the arc and
        ;; de-duplicated
        (setq cands nil)
        (foreach q pts
          (if (and (not (member q used))
                   (<= (pf:seg-dist q s) tol)
                   (> (pf:dist q p1) *PF-EXACT-EPS*)
                   (> (pf:dist q p2) *PF-EXACT-EPS*))
            (setq cands (cons (cons (pf:seg-param q s) q) cands))))
        (setq cands (mapcar 'cdr (pf:sort-car cands)))
        (setq clean nil)
        (foreach q cands
          (if (or (null clean)
                  (> (pf:dist q (car clean)) *PF-EXACT-EPS*))
            (setq clean (cons q clean))))
        (foreach ns (pf:fit-arc-seg p1 p2 b (reverse clean) tol)
          (setq newsegs (cons ns newsegs)))))
    (setq n (1+ n)))
  (setq newsegs (reverse newsegs))
  ;; -- 3. the drawn shape is trusted, but the curve cap still wins --
  (if (and *PF-MAX-ARCS*
           (> (pf:arc-count newsegs) *PF-MAX-ARCS*)
           (>= (length dpts) 3))
    (progn
      (princ (strcat "\n  (the drawn perimeter needs "
                     (itoa (pf:arc-count newsegs))
                     " curves but the cap is " (itoa *PF-MAX-ARCS*)
                     " - refitting from the points instead)"))
      (setq pf-miss-left allow
            newsegs (pf:coarse-loop (pf:loop-order loop dpts)
                                    tol *PF-MAX-ARCS*))))
  newsegs)

;; Build one candidate fit at tolerance TOL.  A non-nil TOUR means the
;; points drive the shape (points-only and ordering-sketch modes);
;; otherwise the drawn LOOP is re-fitted (guided mode).  Each call gets
;; its own miss allowance and on-the-shape threshold.
(defun pf:build (tour loop pts dpts tol allow / pf-miss-left pf-on-eps)
  (setq pf-miss-left allow
        pf-on-eps    (max *PF-ON-EPS* (* 0.25 tol)))
  (if tour
    (pf:coarse-loop tour tol *PF-MAX-ARCS*)
    (pf:guided-fit loop pts dpts tol allow)))

;; Worst distance from any of PTS to the segment list.
(defun pf:worst (segs pts / w q s d dmin)
  (setq w 0.0)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (pf:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin w) (setq w dmin)))
  w)

;; ---- offer three fits and let the user pick ---------------------------
;; Guessing the right tolerance up front is the hardest part of the
;; command, so instead of asking the user to imagine it, draw three
;; candidates - tighter, as asked, looser - in different colours, show
;; what each one costs, and keep the one they point at.  Everything is
;; judged against the tolerance the user actually typed, so the columns
;; compare like for like.
(defun pf:compare (tour loop pts dpts tol allow
                   / prior vars v ent segs bad allbad first i pick idx
                     keep ce)
  (setq prior (pf:prior-fits))
  (pf:ensure-layer *PF-OUT-LAYER* 3)
  (setq pf-phase "building the three candidate fits"
        vars     nil
        allbad   nil
        first    T)
  (foreach v *PF-COMPARE*
    (setq segs (pf:build tour loop pts dpts (* tol (car v)) allow)
          ent  (pf:make-pline
                 (mapcar '(lambda (s) (list (car s) (caddr s))) segs)
                 *PF-OUT-LAYER* (cadr v))
          bad  (pf:unheld segs pts tol)
          vars (cons (list segs ent bad v) vars))
    (if first
      (setq allbad bad first nil)
      (setq allbad (pf:isect allbad bad))))
  (setq vars (reverse vars))
  (if (null (cadr (car vars)))
    (princ "\nABHD: could not draw the result - is the drawing read-only?")
    (progn
      (princ (strcat "\n\nThree candidate fits are now drawn on layer "
                     *PF-OUT-LAYER* ":\n"))
      (princ "\n   #  colour  segs  curves  worst off  not held  ")
      (princ "\n   -  ------  ----  ------  ---------  --------  ")
      (setq i 1)
      (foreach v vars
        (setq segs (car v) bad (caddr v) ce (cadddr v))
        (princ (strcat "\n   " (itoa i) "  "
                       (pf:pad (caddr ce) 8)
                       (pf:pad (itoa (length segs)) 6)
                       (pf:pad (itoa (pf:arc-count segs)) 8)
                       (pf:pad (rtos (pf:worst segs pts) 2 2) 11)
                       (pf:pad (itoa (length bad)) 10)
                       (cadddr ce)))
        (setq i (1+ i)))
      (princ (strcat "\n\n  \"not held\" = points further than "
                     (rtos tol 2 3) " from that fit."))
      (if allbad
        (princ (strcat "\n  NOTE: " (itoa (length allbad))
                       " point(s) could not be held by ANY of the three"
                       " - likely a mis-shot, a duplicate, or a corner"
                       " that needs more points around it.")))
      ;; -- let the user choose ---------------------------------------
      (setq pf-phase "waiting for the choice of fit")
      (initget "1 2 3 All None")
      (setq pick (getkword "\nKeep which fit [1/2/3/All/None] <2>: "))
      (if (null pick) (setq pick "2"))
      (cond
        ((= pick "All")
         (princ "\nKeeping all three, in their preview colours."))
        ((= pick "None")
         (foreach v vars (if (cadr v) (entdel (cadr v))))
         (princ "\nAll three erased - nothing was added to the drawing."))
        (T
         (setq idx (atoi pick) i 1)
         (foreach v vars
           (if (= i idx)
             (setq keep v)
             (if (cadr v) (entdel (cadr v))))
           (setq i (1+ i)))
         (if (cadr keep) (pf:set-bylayer (cadr keep)))))
      (if keep
        (progn
          (pf:mark-unheld (caddr keep) tol)
          (pf:report (car keep) pts tol allow prior)
          (if (caddr keep)
            (princ (strcat "\n  " (itoa (length (caddr keep)))
                           " point(s) beyond the tolerance are ringed on"
                           " layer " *PF-MISS-LAYER*
                           " - zoom to them to see why (delete that"
                           " layer when you are done).")))))))
  (princ))

;; ---- the command -----------------------------------------------------
(defun c:ABHD ( / tol mx ss i en ed lay typ ext nunsup nocs
                    segs pts dpts allow loop tour ok
                    *error* pf-old-err pf-phase)
  ;; report which step failed if anything goes wrong, then restore
  (setq pf-old-err *error*
        *error*
          (lambda (m)
            (if (and m
                     (/= m "Function cancelled")
                     (/= m "quit / exit abort")
                     (/= m "console break"))
              (princ (strcat "\nABHD stopped while "
                             (if pf-phase pf-phase "starting up")
                             " -- " m)))
            (setq *error* pf-old-err)
            (princ)))

  (princ "\n\nABHD - fit a pool perimeter through the surveyed points.")

  ;; -- step 1: how close must the line stay to the points? ----------
  ;; This is the one prompt people misread, so it says in plain words
  ;; what the number means and which way it moves the result.
  ;; initget 6 refuses zero and negative values - a zero tolerance
  ;; would silently collapse the fit into single-point stubs.
  (setq pf-phase "reading the tolerance")
  (princ "\n\n  Step 1 of 3 - how far may the fitted line sit from a survey point?")
  (princ "\n  Type a distance in drawing units (1 = one inch), or pick two")
  (princ "\n  points in the drawing to measure one.")
  (princ "\n  Smaller = hugs the points.  Bigger = smoother, with fewer curves.")
  (initget 6)
  (setq tol (getdist (strcat "\n  Maximum distance from a point <"
                             (rtos *PF-TOL* 2 3) ">: ")))
  (if tol (setq *PF-TOL* tol) (setq tol *PF-TOL*))

  ;; -- step 2: optional cap on how many curves the result may use ---
  (setq pf-phase "reading the curve limit")
  (princ "\n\n  Step 2 of 3 - limit how many curves the result may use?")
  (princ "\n  Type a whole number, or None for no limit.")
  (initget 4 "None")
  (setq mx (getint (strcat "\n  Maximum curves <"
                           (if *PF-MAX-ARCS* (itoa *PF-MAX-ARCS*) "None")
                           ">: ")))
  (cond ((null mx) nil)                            ; Enter: keep as-is
        ((eq 'STR (type mx)) (setq *PF-MAX-ARCS* nil))
        (T (setq *PF-MAX-ARCS* mx)))

  ;; -- step 3: the selection ----------------------------------------
  (princ "\n\n  Step 3 of 3 - select the survey points (POINTS layer or ab_pt")
  (princ "\n  blocks) and, if you have one, the POOL perimeter or ordering sketch.")
  (princ "\n  Select objects: ")
  (setq pf-phase "waiting for the selection")
  ;; only entity types this command can actually read, so a sloppy
  ;; crossing window over dimensions, hatches or text is harmless.
  ;; SPLINE and ELLIPSE are let in ON PURPOSE - not to fit them, but
  ;; so the classifier below can name them in a useful message.
  (setq ss (ssget '((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE"))))
  (if (null ss)
    (princ "\nNothing usable selected (points, and optionally POOL lines/arcs/polylines).")
    (progn
      ;; -- sort the selection into perimeter segments and points -----
      (setq pf-phase "reading the selected entities")
      (setq segs nil pts nil i 0 nunsup 0 nocs 0)
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
          ;; survey points stored as block references (e.g. "ab_pt"):
          ;; a block with this name is ALWAYS a point, on any layer, and
          ;; its insertion point is taken as the location (the blocks are
          ;; never exploded - non-destructive).  Checked first so such
          ;; blocks are never mistaken for perimeter geometry.
          ((and (= typ "INSERT")
                (= (strcase (cdr (assoc 2 ed))) (strcase *PF-POINT-BLOCK*)))
           (setq pts (cons (pf:2d (cdr (assoc 10 ed))) pts)))
          ;; curve types we cannot fit, sitting on the POOL layer: count
          ;; them so the user gets told what to do, instead of a
          ;; mystifying "the perimeter does not close" later on
          ((and (= lay (strcase *PF-POOL-LAYER*))
                (member typ '("SPLINE" "ELLIPSE")))
           (setq nunsup (1+ nunsup)))
          ;; perimeter / ordering sketch on the POOL layer
          ((= lay (strcase *PF-POOL-LAYER*))
           (setq segs (append segs (pf:ent-segs en))))
          ;; plain POINT entities on the POINTS layer
          ((and (= lay (strcase *PF-POINT-LAYER*)) (= typ "POINT"))
           (setq pts (cons (pf:2d (cdr (assoc 10 ed))) pts)))
          ;; any other block dropped on the POINTS layer -> a point too
          ((and (= typ "INSERT") (= lay (strcase *PF-POINT-LAYER*)))
           (setq pts (cons (pf:2d (cdr (assoc 10 ed))) pts)))))
      (if (> nunsup 0)
        (princ (strcat "\nABHD: warning - " (itoa nunsup)
                       " SPLINE/ELLIPSE object(s) on layer "
                       *PF-POOL-LAYER*
                       " were ignored (only lines, arcs, circles and"
                       " polylines can be read - explode or convert"
                       " them first).")))
      (if (> nocs 0)
        (princ (strcat "\nABHD: warning - " (itoa nocs)
                       " selected object(s) are not drawn in the world"
                       " plane; the fit is flat (XY) and may be wrong."
                       "  Set UCS to World and flatten them first.")))
      ;; the miss allowance: this many points (*PF-MISS-PCT*, rounded
      ;; UP to a whole point) may sit off the result by up to TOL
      (setq dpts  (if pts (pf:dedupe pts))
            allow (pf:ceil (* *PF-MISS-PCT* (length dpts))))
      (if (> (length dpts) 150)
        (princ (strcat "\nABHD: " (itoa (length dpts))
                       " points - ordering and fitting will take a"
                       " little while, please wait...")))
      (cond
        ((null pts)
         (princ (strcat "\nNo survey points found (looked for POINT entities on layer "
                        *PF-POINT-LAYER* " and \"" *PF-POINT-BLOCK*
                        "\" block insertions).")))
        ((and (null segs) (< (length dpts) 3))
         (princ "\nPoints-only mode needs at least 3 distinct points."))
        (T
         ;; work out the mode, then hand all three modes to the same
         ;; compare-and-choose step
         (setq tour nil loop nil ok T)
         (cond
           ((null segs)
            ;; ---- POINTS-ONLY: order the points ourselves ----------
            (princ "\nNo POOL geometry selected - ordering the points automatically.")
            (setq pf-phase "ordering the points"
                  tour     (pf:order-points dpts)))
           ((null (setq loop (pf:chain segs)))
            (setq ok nil))                     ; pf:chain said why
           ((not (pf:has-arcs loop))
            ;; ---- ORDERING SKETCH: the drawn loop is all straight
            ;; lines, so it only tells us the ORDER of the points;
            ;; the shape itself comes from the points
            (if (< (length dpts) 3)
              (progn
                (princ (strcat "\nThe lines-only POOL sketch only orders"
                               " the points, and at least 3 distinct"
                               " points are needed to build a shape."))
                (setq ok nil))
              (progn
                (princ "\nPOOL sketch is lines only - using it just to order the points.")
                (setq pf-phase "following the sketch order"
                      tour     (pf:loop-order loop dpts)))))
           (T
            (princ "\nUsing the drawn POOL perimeter as the guide.")))
         (if ok (pf:compare tour loop pts dpts tol allow))))))
  (setq *error* pf-old-err)   ; restore the previous error handler
  (princ))

(princ "\nABHD loaded.  Type ABHD to fit the pool perimeter through its points.")
(princ)
