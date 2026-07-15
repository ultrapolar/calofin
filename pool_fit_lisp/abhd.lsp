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
;;;               and draws a smooth closed polyline through EVERY
;;;               point exactly, using a tangent per point and a
;;;               G1-continuous biarc between consecutive points.
;;;               Runs of points that line up straight become LINE
;;;               segments.
;;;
;;; The command rebuilds the perimeter as a single closed LWPOLYLINE
;;; (lines + arcs only, no splines) on layer "POOL-FIT":
;;;   * Every polyline vertex is snapped to the nearest surveyed point
;;;     within the tolerance (default 1 unit = 1 inch), so corners land
;;;     exactly on points whenever one is close enough.
;;;   * Every curved (arc/bulge) segment is re-fitted so that the arc
;;;     passes through the surveyed points lying along it.  A single
;;;     replacement arc is tried first (the average of the exact
;;;     3-point arcs through the two snapped endpoints and each nearby
;;;     point); when that single arc cannot hold every point, the
;;;     segment is SUBDIVIDED into a tangent-continuous chain of arcs
;;;     that passes exactly through every one of its points.
;;;   * Straight segments the user drew are trusted and kept straight
;;;     (only their endpoints snap to points); where the user found a
;;;     straight wall, the result has a straight wall.
;;; Everything is fitted on the 2D plane - Z coordinates are ignored.
;;; Because every segment still shares its endpoints with its
;;; neighbours and arcs are true circular fits through the points, the
;;; result stays smooth and closed.
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
(setq *PF-STRAIGHT-ANG* (/ pi 60.0)) ; points-only mode: a span whose
                                    ; both end tangents are within this
                                    ; angle (3 deg) of its chord becomes
                                    ; a straight LINE segment - so gently
                                    ; wandering / noisy straight runs come
                                    ; out as lines, not a string of arcs
(setq *PF-CORNER-ANG*   (/ pi 8.0)) ; points-only mode: a point that turns
                                    ; more than this (22.5 deg) is treated
                                    ; as a sharp corner (straight lines on
                                    ; both sides).  Lower it for more
                                    ; corners/lines, raise it for smoother
                                    ; curves.  A shape defined by just its
                                    ; corner points therefore comes out as
                                    ; plain lines, not arcs.
(setq *PF-CHAIN-FUZZ*   1.0e-4)     ; endpoint-matching fuzz for
                                    ; chaining exploded segments
(if (null *PF-TOL*) (setq *PF-TOL* 1.0)) ; default tolerance, 1 inch

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

;; ---- arc segment re-fitting ------------------------------------------
;; Re-fit one curved segment from P1 to P2 (original bulge B) through
;; CANDS, its nearby survey points sorted along the segment.  Returns a
;; list of one or more segments (p1 p2 bulge):
;;   * no candidates          -> the original arc, endpoints updated
;;   * one arc holds them all -> a single averaged arc
;;   * otherwise              -> a tangent-continuous chain of arcs
;;                               passing exactly through every point
(defun pf:cap-bulge (b)
  (cond ((> b 5.0) 5.0) ((< b -5.0) -5.0) (T b)))

(defun pf:fit-arc-seg (p1 p2 b cands / blist sum nb bavg maxres d q segs
                                        prev tang)
  (if (null cands)
    (list (list p1 p2 b))
    (progn
      ;; try a single arc: average of the exact 3-point bulges
      (setq blist (mapcar '(lambda (q) (pf:bulge-3pt p1 q p2)) cands)
            sum   0.0)
      (foreach nb blist (setq sum (+ sum nb)))
      (setq bavg   (/ sum (length blist))
            maxres 0.0)
      (foreach q cands
        (setq d (pf:seg-dist q (list p1 p2 bavg)))
        (if (> d maxres) (setq maxres d)))
      (if (<= maxres *PF-FIT-EPS*)
        (list (list p1 p2 bavg))
        ;; single arc can't hold every point: subdivide.  First arc runs
        ;; from P1 through the 1st point to the 2nd; every further arc
        ;; starts tangent to the previous one and lands exactly on the
        ;; next point; the last lands on P2.  All points are hit exactly
        ;; and every internal joint is tangent-continuous (smooth).
        (progn
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

;; Tangent directions per tour point, as (in . out) pairs (radians).
;; Smooth points get the tangent of the circumcircle through them and
;; their two neighbours (in = out).  A point that turns more than
;; *PF-CORNER-ANG* is kept as a SHARP CORNER (in/out follow the chords)
;; so straight lines meet at it - this is what keeps a shape defined by
;; just its corner points from being rounded into a mess of arcs, while
;; gently sampled curves (small per-point turns) still come out smooth.
(defun pf:vertex-tangents (tour / n i prev cur next cin cout turn
                                  c tc chord tangs)
  (setq n (length tour) i 0)
  (repeat n
    (setq prev  (nth (rem (+ i n -1) n) tour)
          cur   (nth i tour)
          next  (nth (rem (1+ i) n) tour)
          cin   (angle prev cur)
          cout  (angle cur next)
          turn  (pf:signed-dang cin cout)
          chord (angle prev next))
    (if (> (abs turn) *PF-CORNER-ANG*)
      (setq tangs (cons (cons cin cout) tangs))
      (progn
        (setq c (pf:circumcenter prev cur next))
        (if c
          (progn
            (setq tc (+ (angle c cur) (/ pi 2.0)))
            (if (> (abs (pf:signed-dang tc chord)) (/ pi 2.0))
              (setq tc (+ tc pi)))
            (setq tc (pf:norm-ang tc)))
          (setq tc chord))
        (setq tangs (cons (cons tc tc) tangs))))
    (setq i (1+ i)))
  (reverse tangs))

;; One span from A (leaving tangent TA) to B (arriving tangent TB):
;; a LINE when both tangents line up with the chord, one arc when a
;; single arc matches both tangents, otherwise a G1 biarc (two arcs
;; meeting tangentially at an equal-chord joint).
(defun pf:biarc (a ta b tb / phi aa bb d tt psi1 lj j)
  (setq phi (angle a b)
        aa  (pf:signed-dang ta phi)
        bb  (pf:signed-dang phi tb)
        d   (pf:dist a b))
  (cond
    ((and (< (abs aa) *PF-STRAIGHT-ANG*) (< (abs bb) *PF-STRAIGHT-ANG*))
     (list (list a b 0.0)))                    ; straight wall
    ((< (abs (- aa bb)) 1.0e-6)
     (list (list a b (pf:tan (/ aa 2.0)))))    ; one arc fits both ends
    (T
     (setq tt (+ aa bb))                       ; total turning
     (if (> (abs tt) (* 1.9 pi))
       ;; tangents nearly U-turn: give up on G1 for this span
       (list (list a b (pf:cap-bulge (pf:tan (/ aa 2.0)))))
       (progn
         (setq psi1 (- phi (/ tt 4.0))
               lj   (if (< (abs (sin (/ tt 2.0))) 1.0e-9)
                      (/ d 2.0)
                      (/ (* d (sin (/ tt 4.0))) (sin (/ tt 2.0))))
               j    (list (+ (car a)  (* lj (cos psi1)))
                          (+ (cadr a) (* lj (sin psi1)))))
         (if (or (< (pf:dist a j) *PF-EXACT-EPS*)
                 (< (pf:dist j b) *PF-EXACT-EPS*))
           (list (list a b (pf:cap-bulge (pf:tan (/ aa 2.0)))))
           (list (list a j (pf:tan (/ (pf:signed-dang ta psi1) 2.0)))
                 (list j b (pf:tan (/ (pf:signed-dang (angle j b) tb)
                                      2.0))))))))))

;; Build the smooth closed segment list through the ordered TOUR.
(defun pf:points-loop (tour / tangs n i sub segs s)
  (setq tangs (pf:vertex-tangents tour)
        n     (length tour)
        i     0)
  (repeat n
    (setq sub (pf:biarc (nth i tour)
                        (cdr (nth i tangs))               ; leaving tangent
                        (nth (rem (1+ i) n) tour)
                        (car (nth (rem (1+ i) n) tangs))  ; arriving tangent
              ))
    (foreach s sub (setq segs (cons s segs)))
    (setq i (1+ i)))
  (reverse segs))

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

;; Draw the fitted polyline and print the hit report.
(defun pf:finish (newsegs pts tol / hitex hitok miss q s d dmin)
  (pf:ensure-layer *PF-OUT-LAYER*)
  (pf:make-pline
    (mapcar '(lambda (s) (list (car s) (caddr s))) newsegs)
    *PF-OUT-LAYER*)
  (setq hitex 0 hitok 0 miss 0)
  (foreach q pts
    (setq dmin nil)
    (foreach s newsegs
      (setq d (pf:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (cond
      ((<= dmin *PF-EXACT-EPS*) (setq hitex (1+ hitex)))
      ((<= dmin tol)            (setq hitok (1+ hitok)))
      (T                        (setq miss  (1+ miss)))))
  (princ (strcat "\nABHD: " (itoa (length newsegs))
                 " segments written to layer " *PF-OUT-LAYER* "."
                 "\n  Points ON the perimeter:      " (itoa hitex)
                 "\n  Points within tolerance:      " (itoa hitok)
                 "\n  Points beyond tolerance:      " (itoa miss)))
  (if (> miss 0)
    (princ "\n  (points beyond tolerance were left where the drawn shape disagrees with them)"))
  (princ))

;; ---- the command -----------------------------------------------------
(defun c:ABHD ( / tol ss i en ed lay typ segs pts loop n verts used
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
      (cond
        ((null pts)
         (princ (strcat "\nNo survey points found (looked for POINT entities on layer "
                        *PF-POINT-LAYER* " and \"" *PF-POINT-BLOCK*
                        "\" block insertions).")))
        ((and (null segs) (< (length (pf:dedupe pts)) 3))
         (princ "\nPoints-only mode needs at least 3 distinct points."))
        ((null segs)
         ;; ---- POINTS-ONLY mode: order the points ourselves ---------
         (princ "\nNo POOL geometry selected - ordering the points automatically.")
         (setq pf-phase "ordering the points and building the polyline")
         (pf:finish (pf:points-loop (pf:order-points (pf:dedupe pts)))
                    pts tol))
        ((null (setq loop (pf:chain segs))) nil)
        ((not (pf:has-arcs loop))
         ;; ---- ORDERING-SKETCH mode: the drawn loop is all straight
         ;; lines, so treat it as connect-the-dots that only tells us
         ;; the ORDER of the points; the shape comes from the points
         (princ "\nPOOL sketch is lines only - using it just to order the points.")
         (setq pf-phase "following the sketch order and building the polyline")
         (pf:finish (pf:points-loop (pf:loop-order loop (pf:dedupe pts)))
                    pts tol))
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
               (foreach ns (pf:fit-arc-seg p1 p2 b (reverse clean))
                 (setq newsegs (cons ns newsegs)))))
           (setq n (1+ n)))
         (setq newsegs (reverse newsegs))
         ;; -- 3. draw the fitted polyline and report ------------------
         (pf:finish newsegs pts tol)))))
  (setq *error* pf-old-err)   ; restore the previous error handler
  (princ))

(princ "\nABHD loaded.  Type ABHD to fit the pool perimeter through its points.")
(princ)
