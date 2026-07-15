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
;;; SMOOTH (G1) EVERYWHERE: the result is built as a TANGENT CHAIN -
;;; every arc starts exactly where the previous one ended, WITH its
;;; end tangent, so consecutive arcs are always tangent to each other
;;; and the perimeter has no kinks.  The only intentional kinks are
;;; sharp corners (over *PF-CORNER-ANG*).  A fully smooth loop is
;;; sealed with a G1 biarc, so even the closing seam is tangent-
;;; continuous.  Because tangency pins each arc down, the chain's
;;; joints are allowed to float off the survey points - the points
;;; themselves still govern the fit through the tolerance and the
;;; miss allowance below.
;;;
;;; NICE RADII: arc radii are snapped to friendly increments before a
;;; free ("weird") number is accepted - whole feet first, then half
;;; feet, then whole inches (*PF-NICE-RADII*, drawing units = inches).
;;; A snapped radius is only used when the arc still holds every one
;;; of its points; the arc's endpoints stay exactly where they were.
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
(setq *PF-EXACT-EPS*    0.001)      ; "exactly on" threshold (units)
(setq *PF-FIT-EPS*      0.01)       ; if a single arc misses any of its
                                    ; points by more than this, split it
                                    ; into several arcs that hit exactly
(setq *PF-ON-EPS*       0.5)        ; a point within this of the result
                                    ; counts as ON it (half the default
                                    ; tolerance); only points off by more
                                    ; than this eat into the miss
                                    ; allowance below
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
(setq *PF-TANG-W*       20.0)       ; how much the fitter values an arc
                                    ; whose EXIT tangent stays aimed
                                    ; along the data (inches of point
                                    ; deviation traded per radian of
                                    ; tangent error).  Higher = longer,
                                    ; steadier arcs; this is what keeps
                                    ; the tangent chain from wobbling.
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
(defun pf:tan (x) (/ (sin x) (cos x)))

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
;; passes through Q.  0.0 when the three points are collinear.
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
      (if (< dccw 1.0e-10) (setq dccw (* 2.0 pi)))
      (if (<= dq dccw)
        (pf:tan (/ dccw 4.0))                       ; CCW arc through Q
        (- (pf:tan (/ (- (* 2.0 pi) dccw) 4.0)))))) ; CW arc through Q
)

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
     (list (list (polar c a1 r) (polar c a2 r) (pf:tan (/ delta 4.0)))))
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

;; How many of QS sit farther than *PF-ON-EPS* from the segment - the
;; points that would eat into the miss allowance.
(defun pf:span-misses (a b bul qs / seg c q)
  (setq seg (list a b bul) c 0)
  (foreach q qs
    (if (> (pf:seg-dist q seg) *PF-ON-EPS*) (setq c (1+ c))))
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
;; of them off by more than *PF-ON-EPS*.  The nearer multiple on each
;; tier is tried first; the arc's endpoints never move.  Returns
;; (bulge . misses) of the snapped arc, or nil when no nice radius
;; holds the points.
(defun pf:snap-arc (a b bl qs tol left / r0 h best tier lo hi cands r
                                          bl2 mis)
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
            sn     (pf:snap-arc p1 p2 bavg cands tol pf-miss-left))
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

;; ---- tangent-chain fitting (G1 everywhere) ----------------------------
;; The points-only / ordering-sketch result is built as a CHAIN: every
;; element starts exactly where the previous one ended, WITH ITS
;; TANGENT, so consecutive arcs are always tangent to each other and
;; the perimeter is smooth.  An element is described by its signed
;; center offset S: the circle's center sits S to the left of the
;; running tangent (negative = right); S = nil means a straight
;; continuation (only happens on dead-straight data).

;; Signed center offset of the circle through Q that leaves J with
;; tangent TG.  nil when Q lies (nearly) dead ahead - straight.
(defun pf:tan-circle-s (j tg q / nx ny dx dy dn d2)
  (setq nx (- (sin tg)) ny (cos tg)
        dx (- (car q) (car j)) dy (- (cadr q) (cadr j))
        dn (+ (* dx nx) (* dy ny))
        d2 (+ (* dx dx) (* dy dy)))
  (if (or (< (abs dn) 1.0e-12)
          (> (abs (/ d2 (* 2.0 dn))) 1.0e6))
    nil
    (/ d2 (* 2.0 dn))))

;; Worst deviation and miss count of QS against the element (J TG S).
;; Returns (maxdev . misses).
(defun pf:chain-eval (j tg s qs / mx c d dx dy nx ny cen r q)
  (setq mx 0.0 c 0)
  (if (null s)
    (progn
      (setq dx (cos tg) dy (sin tg))
      (foreach q qs
        (setq d (abs (- (* (- (cadr q) (cadr j)) dx)
                        (* (- (car q) (car j)) dy))))
        (if (> d mx) (setq mx d))
        (if (> d *PF-ON-EPS*) (setq c (1+ c)))))
    (progn
      (setq nx  (- (sin tg)) ny (cos tg)
            cen (list (+ (car j) (* s nx)) (+ (cadr j) (* s ny)))
            r   (abs s))
      (foreach q qs
        (setq d (abs (- (distance cen (pf:2d q)) r)))
        (if (> d mx) (setq mx d))
        (if (> d *PF-ON-EPS*) (setq c (1+ c))))))
  (cons mx c))

;; Snap the element's radius |S| to a nice increment (whole feet, half
;; feet, whole inches) that still holds QS within TOL and LEFT misses.
;; Returns (s . misses) or nil.
(defun pf:snap-s (j tg s qs tol left / r0 best tier lo hi cands r s2 ev)
  (setq r0 (abs s) best nil)
  (if (<= r0 1.0e6)
    (foreach tier *PF-NICE-RADII*
      (if (null best)
        (progn
          (setq lo    (* tier (fix (/ r0 tier)))
                hi    (+ lo tier)
                cands (if (< (- r0 lo) (- hi r0))
                        (list lo hi)
                        (list hi lo)))
          (foreach r cands
            (if (and (null best) (> r 0.0))
              (progn
                (setq s2 (if (> s 0.0) r (- r))
                      ev (pf:chain-eval j tg s2 qs))
                (if (and (<= (car ev) tol) (<= (cdr ev) left))
                  (setq best (cons s2 (cdr ev)))))))))))
  best)

;; Angle between the element's tangent at its end (the projection of
;; QLAST) and the direction of travel toward AIM.
(defun pf:exit-mism (j tg s qlast aim / nx ny cen tout)
  (if (null s)
    (setq tout tg)
    (progn
      (setq nx   (- (sin tg)) ny (cos tg)
            cen  (list (+ (car j) (* s nx)) (+ (cadr j) (* s ny)))
            tout (if (> s 0.0)
                   (+ (angle cen qlast) (/ pi 2.0))
                   (- (angle cen qlast) (/ pi 2.0))))))
  (abs (pf:signed-dang tout (angle qlast aim))))

;; Feasibility-gated goodness of element S over QS aiming at AIM:
;; deviation plus *PF-TANG-W* times the exit-tangent error.  Returns
;; (blend . misses); blend is 1e18 when the element can't hold QS.
(defun pf:chain-blend (j tg s qs aim tol left / ev)
  (setq ev (pf:chain-eval j tg s qs))
  (if (or (> (car ev) tol) (> (cdr ev) left))
    (cons 1.0e18 (cdr ev))
    (cons (+ (car ev)
             (* *PF-TANG-W* (pf:exit-mism j tg s (last qs) aim)))
          (cdr ev))))

;; Best feasible offset for the first M points of AHEAD, or nil.
;; Candidates pass exactly through sampled points, then a small
;; multiplicative hill-climb refines the winner.  Returns
;; (s . misses); a car of nil means a straight element.
(defun pf:chain-opt (j tg m ahead tol left aim / qs idx k s bs bb bmis b
                                                 step improved s2)
  (setq qs  (pf:sublist ahead 0 m)
        bs  nil bb 1.0e18 bmis 0
        idx (list 0 (/ m 4) (/ m 2) (/ (* 3 m) 4) (1- m)))
  (foreach k idx
    (setq s (pf:tan-circle-s j tg (nth k qs))
          b (pf:chain-blend j tg s qs aim tol left))
    (if (< (car b) bb)
      (setq bs s bb (car b) bmis (cdr b))))
  (if (and bs (< bb 1.0e17))
    (foreach step '(1.3 1.1 1.03 1.01)
      (setq improved T)
      (while improved
        (setq improved nil)
        (foreach s2 (list (* bs step) (/ bs step))
          (setq b (pf:chain-blend j tg s2 qs aim tol left))
          (if (< (car b) bb)
            (setq bs s2 bb (car b) bmis (cdr b) improved T))))))
  (if (< bb 1.0e17) (cons bs bmis)))

;; Longest prefix of AHEAD held by one tangent element at (J TG),
;; preferring elements whose exit tangent stays aimed along the data -
;; that keeps the chain from oscillating.  AIMPT is where the chain
;; heads after AHEAD runs out (the section corner or the loop seam).
;; Returns (m s misses); m >= 1 always.
(defun pf:grow-arc (j tg ahead tol left aimpt / nn best m go got aim qs
                                                base sn)
  (setq nn   (length ahead)
        best (list 1 (pf:tan-circle-s j tg (car ahead)) 0)
        m    1
        go   T)
  (while (and go (<= m nn))
    (setq aim (if (< m nn) (nth m ahead) aimpt)
          got (pf:chain-opt j tg m ahead tol left aim))
    (if got
      (setq best (list m (car got) (cdr got))
            m    (1+ m))
      (setq go nil)))
  ;; prefer a nice radius that still holds the covered points and
  ;; doesn't throw the exit tangent noticeably off aim
  (setq m (car best))
  (if (cadr best)
    (progn
      (setq qs   (pf:sublist ahead 0 m)
            aim  (if (< m nn) (nth m ahead) aimpt)
            base (pf:exit-mism j tg (cadr best) (nth (1- m) ahead) aim)
            sn   (pf:snap-s j tg (cadr best) qs tol left))
      (if (and sn
               (<= (pf:exit-mism j tg (car sn) (nth (1- m) ahead) aim)
                   (+ base 0.05)))
        (setq best (list m (car sn) (cdr sn))))))
  best)

;; Emit the element from (J TG) - circle offset S (nil = straight) -
;; ending at the projection of QLAST.  Returns ((p1 p2 bulge) . tang),
;; the drawn segment and the tangent handed to the next element.
(defun pf:emit-chain (j tg s qlast / dx dy u e nx ny cen r ae a0 delta
                                     bl)
  (if (null s)
    (progn
      (setq dx (cos tg) dy (sin tg)
            u  (max 1.0e-6 (+ (* (- (car qlast) (car j)) dx)
                              (* (- (cadr qlast) (cadr j)) dy)))
            e  (list (+ (car j) (* u dx)) (+ (cadr j) (* u dy))))
      (cons (list j e 0.0) tg))
    (progn
      (setq nx    (- (sin tg)) ny (cos tg)
            cen   (list (+ (car j) (* s nx)) (+ (cadr j) (* s ny)))
            r     (abs s)
            ae    (angle cen qlast)
            e     (list (+ (car cen) (* r (cos ae)))
                        (+ (cadr cen) (* r (sin ae))))
            a0    (angle cen j)
            delta (if (> s 0.0)
                    (pf:norm-ang (- ae a0))
                    (pf:norm-ang (- a0 ae)))
            bl    (pf:tan (/ delta 4.0)))
      (if (< s 0.0) (setq bl (- bl)))
      (cons (list j e bl) (+ (angle j e) (* 2.0 (atan bl)))))))

;; Single element from (J TG) ending EXACTLY at C (a sharp corner),
;; covering all of AHEAD within TOL and LEFT misses.  Returns
;; (seg misses tang) or nil.
(defun pf:finish-arc (j tg c ahead tol left / s nx ny cen a0 ae delta bl
                                              seg mx mis d q)
  (setq s (pf:tan-circle-s j tg c))
  (if (null s)
    (setq bl 0.0)
    (progn
      (setq nx    (- (sin tg)) ny (cos tg)
            cen   (list (+ (car j) (* s nx)) (+ (cadr j) (* s ny)))
            a0    (angle cen j)
            ae    (angle cen c)
            delta (if (> s 0.0)
                    (pf:norm-ang (- ae a0))
                    (pf:norm-ang (- a0 ae)))
            bl    (pf:tan (/ delta 4.0)))
      (if (< s 0.0) (setq bl (- bl)))))
  (setq seg (list j c bl) mx 0.0 mis 0)
  (foreach q ahead
    (setq d (pf:seg-dist q seg))
    (if (> d mx) (setq mx d))
    (if (> d *PF-ON-EPS*) (setq mis (1+ mis))))
  (if (and (<= mx tol) (<= mis left))
    (list seg mis (+ (angle j c) (* 2.0 (atan bl))))))

;; G1 pair of arcs from A (tangent TA) to B (tangent TB); falls back
;; to a single arc when the geometry degenerates.  Seals the smooth
;; closed loop - its radii are whatever the closure demands.
(defun pf:biarc (a ta b tb / phi aa bb d tt psi1 lj jp)
  (setq phi (angle a b)
        aa  (pf:signed-dang ta phi)
        bb  (pf:signed-dang phi tb)
        d   (pf:dist a b))
  (cond
    ((and (< (abs aa) 1.0e-9) (< (abs bb) 1.0e-9))
     (list (list a b 0.0)))
    ((< (abs (- aa bb)) 1.0e-6)
     (list (list a b (pf:tan (/ aa 2.0)))))
    (T
     (setq tt (+ aa bb))
     (if (> (abs tt) (* 1.9 pi))
       ;; tangents nearly U-turn: give up on G1 for this seam
       (list (list a b (pf:cap-bulge (pf:tan (/ aa 2.0)))))
       (progn
         (setq psi1 (- phi (/ tt 4.0))
               lj   (if (< (abs (sin (/ tt 2.0))) 1.0e-9)
                      (/ d 2.0)
                      (/ (* d (sin (/ tt 4.0))) (sin (/ tt 2.0))))
               jp   (list (+ (car a) (* lj (cos psi1)))
                          (+ (cadr a) (* lj (sin psi1)))))
         (if (or (< (pf:dist a jp) 1.0e-3) (< (pf:dist jp b) 1.0e-3))
           (list (list a b (pf:cap-bulge (pf:tan (/ aa 2.0)))))
           (list (list a jp (pf:tan (/ (pf:signed-dang ta psi1) 2.0)))
                 (list jp b (pf:tan (/ (pf:signed-dang (angle jp b) tb)
                                       2.0))))))))))

;; Tangent at P0 of the circle through P0 P1 P2 (chord direction when
;; collinear), oriented toward P1.
(defun pf:start-tang (p0 p1 p2 / c tc)
  (setq c (pf:circumcenter (pf:2d p0) (pf:2d p1) (pf:2d p2)))
  (if (null c)
    (angle p0 p1)
    (progn
      (setq tc (+ (angle c p0) (/ pi 2.0)))
      (if (> (abs (pf:signed-dang tc (angle p0 p1))) (/ pi 2.0))
        (setq tc (+ tc pi)))
      (pf:norm-ang tc))))

;; Cover the rotated closed TOUR with a G1 tangent chain of arcs.
;; Sharp corners split the loop into sections: each section starts and
;; ends exactly ON its corner points and is chained smoothly between
;; them; a loop with no corners is one chain sealed by a G1 biarc.
;; LEFT is the miss allowance for this pass.  Returns the segments.
(defun pf:smooth-loop (tour tol left / n sharp i prev cur next turn
                                       corners segs ends cs ce pts j tg
                                       cpt ahead go fin got m em j0 t0
                                       bi mx mis d dd q seg)
  (setq n (length tour))
  ;; flag the sharp corners (intentional kinks, chain break points)
  (setq sharp nil i 0)
  (repeat n
    (setq prev (nth (rem (+ i n -1) n) tour)
          cur  (nth i tour)
          next (nth (rem (1+ i) n) tour)
          turn (abs (pf:signed-dang (angle prev cur) (angle cur next))))
    (setq sharp (cons (> turn *PF-CORNER-ANG*) sharp)
          i     (1+ i)))
  (setq sharp (reverse sharp))
  (setq corners nil i 0)
  (repeat n
    (if (nth i sharp) (setq corners (cons i corners)))
    (setq i (1+ i)))
  (setq corners (reverse corners) segs nil)
  (if corners
    (progn
      ;; the tour is rotated so index 0 is the sharpest corner
      (setq ends (append (cdr corners) (list n))
            cs   (car corners))
      (foreach ce ends
        (setq pts nil i cs)
        (while (<= i ce)
          (setq pts (cons (nth (rem i n) tour) pts)
                i   (1+ i)))
        (setq pts   (reverse pts)
              j     (car pts)
              tg    (if (> (length pts) 2)
                      (pf:start-tang (car pts) (cadr pts) (caddr pts))
                      (angle (car pts) (cadr pts)))
              cpt   (last pts)
              ahead (reverse (cdr (reverse (cdr pts))))
              go    T)
        (while go
          (setq fin (pf:finish-arc j tg cpt ahead tol left))
          (if fin
            (setq segs (cons (car fin) segs)
                  left (- left (cadr fin))
                  go   nil)
            (progn
              (setq got (pf:grow-arc j tg ahead tol left cpt)
                    m   (car got)
                    em  (pf:emit-chain j tg (cadr got)
                                       (nth (1- m) ahead)))
              (setq segs  (cons (car em) segs)
                    j     (cadr (car em))
                    tg    (cdr em)
                    left  (- left (caddr got))
                    ahead (pf:nthcdr m ahead)))))
        (setq cs ce)))
    (progn
      ;; no corners: one smooth chain, sealed with a G1 biarc
      (setq j0    (car tour)
            t0    (pf:start-tang (car tour) (cadr tour) (caddr tour))
            j     j0
            tg    t0
            ahead (cdr tour)
            go    T)
      (while go
        (setq fin nil)
        (if (> (pf:dist j j0) 1.0e-9)
          (progn
            (setq bi (pf:biarc j tg j0 t0) mx 0.0 mis 0)
            (foreach q ahead
              (setq d nil)
              (foreach seg bi
                (setq dd (pf:seg-dist q seg))
                (if (or (null d) (< dd d)) (setq d dd)))
              (if (> d mx) (setq mx d))
              (if (> d *PF-ON-EPS*) (setq mis (1+ mis))))
            (if (and (<= mx tol) (<= mis left))
              (setq fin T))))
        (if fin
          (progn
            (foreach seg bi (setq segs (cons seg segs)))
            (setq left (- left mis)
                  go   nil))
          (progn
            (setq got (pf:grow-arc j tg ahead tol left j0)
                  m   (car got)
                  em  (pf:emit-chain j tg (cadr got)
                                     (nth (1- m) ahead)))
            (setq segs  (cons (car em) segs)
                  j     (cadr (car em))
                  tg    (cdr em)
                  left  (- left (caddr got))
                  ahead (pf:nthcdr m ahead)))))))
  (reverse segs))

;; Points-only / ordering-sketch fit: a G1 tangent chain with nice
;; radii.  The curve cap is enforced by refitting the whole loop with
;; a progressively relaxed tolerance - merging arcs would break their
;; tangency, so the chain is rebuilt instead and stays smooth.
(defun pf:coarse-loop (tour tol maxarcs / segs tol2 tries)
  (setq tour (pf:rotate-to-corner tour)
        segs (pf:smooth-loop tour tol pf-miss-left))
  (if maxarcs
    (progn
      (setq tol2 tol tries 0)
      (while (and (> (pf:arc-count segs) maxarcs) (< tries 40))
        (setq tol2  (* tol2 1.25)
              tries (1+ tries)
              segs  (pf:smooth-loop tour tol2 1000000)))))
  segs)

;; ---- output helpers --------------------------------------------------
(defun pf:ensure-layer (name)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) '(62 . 3)
                    '(6 . "Continuous")))))

(defun pf:make-pline (verts layer / dxf v)
  ;; verts: list of (pt bulge) in order, closed
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                  (cons 8 layer) '(100 . "AcDbPolyline")
                  (cons 90 (length verts)) '(70 . 1)))
  (foreach v verts
    (setq dxf (append dxf (list (cons 10 (car v)) (cons 42 (cadr v))))))
  (entmakex dxf))

;; Draw the fitted polyline and print the hit report.  ALLOW is the
;; run's miss allowance (how many points were permitted to sit between
;; *PF-ON-EPS* and the tolerance off the result).
(defun pf:finish (newsegs pts tol allow / nl na hiton hitok miss q s d
                                          dmin)
  (pf:ensure-layer *PF-OUT-LAYER*)
  (pf:make-pline
    (mapcar '(lambda (s) (list (car s) (caddr s))) newsegs)
    *PF-OUT-LAYER*)
  (setq nl 0 na 0)
  (foreach s newsegs
    (if (< (abs (caddr s)) 1.0e-9) (setq nl (1+ nl)) (setq na (1+ na))))
  (setq hiton 0 hitok 0 miss 0)
  (foreach q pts
    (setq dmin nil)
    (foreach s newsegs
      (setq d (pf:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (cond
      ((<= dmin *PF-ON-EPS*) (setq hiton (1+ hiton)))
      ((<= dmin tol)         (setq hitok (1+ hitok)))
      (T                     (setq miss  (1+ miss)))))
  (princ (strcat "\nABHD: " (itoa (length newsegs)) " segments ("
                 (itoa nl) " lines + " (itoa na)
                 " curves) written to layer " *PF-OUT-LAYER* "."
                 "\n  Points on the perimeter:      " (itoa hiton)
                 "\n  Points off within tolerance:  " (itoa hitok)
                 "  (allowance " (itoa allow) ")"
                 "\n  Points beyond tolerance:      " (itoa miss)))
  (if (and *PF-MAX-ARCS* (> na *PF-MAX-ARCS*))
    (princ (strcat "\n  (the curve cap is " (itoa *PF-MAX-ARCS*)
                   " but " (itoa na) " curves was the fewest this run"
                   " could do: drawn walls are trusted and a closed"
                   " loop needs at least 2 segments)")))
  (if (> miss 0)
    (princ "\n  (points beyond tolerance: the curve cap and/or the drawn shape overruled them)"))
  (princ))

;; ---- the command -----------------------------------------------------
(defun c:ABHD ( / tol mx ss i en ed lay typ segs pts dpts allow
                    pf-miss-left loop n verts used
                    v best bd d q p1 p2 b cands clean ns newsegs s
                    *error* pf-old-err pf-phase)
  ;; report which step failed if anything goes wrong, then restore
  (setq pf-old-err *error*
        *error*
          (lambda (m)
            (if (and m (/= m "Function cancelled") (/= m "quit / exit abort"))
              (princ (strcat "\nABHD stopped while "
                             (if pf-phase pf-phase "starting up")
                             " -- " m)))
            (setq *error* pf-old-err)
            (princ)))

  ;; tolerance (drawing units; 1 = 1 inch in an inch drawing)
  (setq pf-phase "reading the tolerance")
  (setq tol (getdist (strcat "\nTolerance <" (rtos *PF-TOL* 2 3) ">: ")))
  (if tol (setq *PF-TOL* tol) (setq tol *PF-TOL*))

  ;; optional cap on the number of curves (arc segments) in the result
  (setq pf-phase "reading the curve limit")
  (initget 4 "None")
  (setq mx (getint (strcat "\nMax curves, or None <"
                           (if *PF-MAX-ARCS* (itoa *PF-MAX-ARCS*) "None")
                           ">: ")))
  (cond ((null mx) nil)                            ; Enter: keep as-is
        ((eq 'STR (type mx)) (setq *PF-MAX-ARCS* nil))
        (T (setq *PF-MAX-ARCS* mx)))

  (princ "\nSelect the points (POINTS layer or ab_pt blocks) and, optionally, the POOL perimeter/sketch: ")
  (setq pf-phase "waiting for the selection")
  (setq ss (ssget))
  (if (null ss)
    (princ "\nNothing selected.")
    (progn
      ;; -- sort the selection into perimeter segments and points -----
      (setq pf-phase "reading the selected entities")
      (setq segs nil pts nil i 0)
      (while (< i (sslength ss))
        (setq en  (ssname ss i)
              ed  (entget en)
              lay (strcase (cdr (assoc 8 ed)))
              typ (cdr (assoc 0 ed))
              i   (1+ i))
        (cond
          ;; survey points stored as block references (e.g. "ab_pt"):
          ;; a block with this name is ALWAYS a point, on any layer, and
          ;; its insertion point is taken as the location (the blocks are
          ;; never exploded - non-destructive).  Checked first so such
          ;; blocks are never mistaken for perimeter geometry.
          ((and (= typ "INSERT")
                (= (strcase (cdr (assoc 2 ed))) (strcase *PF-POINT-BLOCK*)))
           (setq pts (cons (pf:2d (cdr (assoc 10 ed))) pts)))
          ;; perimeter / ordering sketch on the POOL layer
          ((= lay (strcase *PF-POOL-LAYER*))
           (setq segs (append segs (pf:ent-segs en))))
          ;; plain POINT entities on the POINTS layer
          ((and (= lay (strcase *PF-POINT-LAYER*)) (= typ "POINT"))
           (setq pts (cons (pf:2d (cdr (assoc 10 ed))) pts)))
          ;; any other block dropped on the POINTS layer -> a point too
          ((and (= typ "INSERT") (= lay (strcase *PF-POINT-LAYER*)))
           (setq pts (cons (pf:2d (cdr (assoc 10 ed))) pts)))))
      ;; the miss allowance: this many points (*PF-MISS-PCT*, rounded
      ;; UP to a whole point) may sit off the result by up to TOL
      (setq dpts  (if pts (pf:dedupe pts))
            allow (pf:ceil (* *PF-MISS-PCT* (length dpts)))
            pf-miss-left allow)
      (cond
        ((null pts)
         (princ (strcat "\nNo survey points found (looked for POINT entities on layer "
                        *PF-POINT-LAYER* " and \"" *PF-POINT-BLOCK*
                        "\" block insertions).")))
        ((and (null segs) (< (length dpts) 3))
         (princ "\nPoints-only mode needs at least 3 distinct points."))
        ((null segs)
         ;; ---- POINTS-ONLY mode: order the points ourselves ---------
         (princ "\nNo POOL geometry selected - ordering the points automatically.")
         (setq pf-phase "ordering the points and building the polyline")
         (pf:finish (pf:coarse-loop (pf:order-points dpts) tol *PF-MAX-ARCS*)
                    pts tol allow))
        ((null (setq loop (pf:chain segs))) nil)
        ((not (pf:has-arcs loop))
         ;; ---- ORDERING-SKETCH mode: the drawn loop is all straight
         ;; lines, so treat it as connect-the-dots that only tells us
         ;; the ORDER of the points; the shape comes from the points
         (princ "\nPOOL sketch is lines only - using it just to order the points.")
         (setq pf-phase "following the sketch order and building the polyline")
         (pf:finish (pf:coarse-loop (pf:loop-order loop dpts) tol *PF-MAX-ARCS*)
                    pts tol allow))
        (T
         (setq pf-phase "fitting the drawn perimeter through the points")
         ;; -- 1. snap each vertex to its nearest point within tol ----
         ;; vertex list from the loop's segment start points
         (setq verts (mapcar '(lambda (s) (car s)) loop)
               used  nil
               n     0)
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
         ;; -- 2. re-fit every arc segment through nearby points ------
         ;; (splitting into several arcs when one arc can't hold them)
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
               ;; survey points lying near the ORIGINAL arc, excluding
               ;; the ones already consumed as vertices, sorted along
               ;; the arc and de-duplicated
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
         ;; -- 3. draw the fitted polyline and report ------------------
         (pf:finish newsegs pts tol allow)))))
  (setq *error* pf-old-err)   ; restore the previous error handler
  (princ))

(princ "\nABHD loaded.  Type ABHD to fit the pool perimeter through its points.")
(princ)
