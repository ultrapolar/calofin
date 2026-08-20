;;; ===================================================================
;;; LHD.LSP  --  Fit a top-down outline through laser-scanned points
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Command:  LHD - fit an outline (closed or open) through the points
;;;
;;; The laser-point sibling of ABHD.  ABHD fits a pool perimeter
;;; through ab_pt survey blocks; LHD fits the same kind of arcs-on-the-
;;; points outline through points that came off a laser scan of an
;;; uneven surface.  The fit itself is a flat TOP-DOWN PROJECTION:
;;; every coordinate is flattened to the XY plane before anything is
;;; fitted, exactly as ABHD does.  What the elevations DO decide -
;;; when the points carry any - is the single height the finished
;;; outline is drawn at: the command asks whether that should be the
;;; TOPMOST point, the BOTTOMMOST, the AVERAGE of them all, or zero.
;;;
;;; WHAT COUNTS AS A LASER POINT - the classifier is deliberately
;;; looser than ABHD's, because scan exports land in many shapes:
;;;   * an INSERT of the survey point block ("ab_pt"), on any layer;
;;;     its number attribute names the point in reports
;;;   * a plain POINT entity on ANY layer (ABHD insists on the POINTS
;;;     layer; laser exports rarely land there) - its Z, when nonzero,
;;;     is that point's elevation
;;;   * any other INSERT sitting on the POINTS layer
;;;   * a TEXT entity whose value reads as a number and that sits
;;;     within *LH-TEXT-EPS* of a point names that point's elevation
;;;     (the DRONE convention: elevation labels share the point's spot)
;;;
;;; CLOSED OR OPEN - asked per run.  Closed is ABHD's loop engine
;;; unchanged: nearest-neighbour tour + 2-opt, arcs grown span by span
;;; inside the tangent window, the seam held closed.  Open drops the
;;; loop: the two ends of the run are the farthest-apart pair of
;;; points (or two points you pick on a Redo), the ordering keeps both
;;; ends fixed, and the fitter walks the path once with no seam - the
;;; first span starts free and the last simply ends.
;;;
;;; HELD POINTS: the user may declare points that must be held
;;; ABSOLUTELY - control shots, tie-ins, anything scanned as an exact
;;; position.  A held point is never buried inside a span, so every
;;; span ends ON it and the fitted line passes through it exactly, in
;;; every candidate; it costs nothing from the miss allowance and the
;;; tangency window still applies at its joint (it is not a corner).
;;;
;;; Everything else is ABHD's behaviour, kept on purpose: the miss
;;; allowance, declared straight stretches and sharp corners, the
;;; curve cap with its relaxing refit, nice radii, and the three
;;; candidates (tight / as asked / few) drawn side by side to pick
;;; from.  A lines-only sketch on the POOL layer orders the points
;;; when the automatic order goes wrong; the kept outline lands on the
;;; POOL layer like ABHD's, so the rest of the toolset can read it.
;;; ===================================================================
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.

;; ---- configuration -------------------------------------------------
(setq *lh-version*      "v1.1")     ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it
(setq *LH-POOL-LAYER*   "POOL")     ; layer of the ordering sketch, and
                                    ; where the kept outline ends up
(setq *LH-POINT-LAYER*  "POINTS")   ; layer whose POINTs/INSERTs are
                                    ; always points
(setq *LH-POINT-BLOCK*  "ab_pt")    ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq *LH-OUT-LAYER*    "LHD-FIT")  ; layer the candidate fits go on
(setq *LH-MISS-LAYER*   "FGStep")   ; layer the "could not hold this
                                    ; point" rings go on; LHD stamps
                                    ; its objects and only erases its
                                    ; own (see lh:tag-mine)
(setq *LH-MISS-RADIUS*  4.0)        ; radius of those rings (4 inches)
(setq *LH-PT-TAG*       "number")   ; attribute tag on the point block
                                    ; naming the point, as in "Pt.17"
(setq *LH-WALL-LAYER*   "POOL-WALLS") ; layer for the dashed markers of
                                    ; declared straight stretches
(setq *LH-TOL-MAX*      2.0)        ; hard ceiling on the max-distance
                                    ; prompt (2 inches)
(setq *LH-TEXT-EPS*     6.0)        ; a numeric TEXT within this of a
                                    ; point is that point's elevation
                                    ; label (6 in; labels sit right on
                                    ; their points, so keep it small -
                                    ; a mispair would only nudge the
                                    ; output height, never the shape)
(setq *LH-COMPARE*                  ; the three candidate fits offered:
  '(("tight" 1 "red"    "most curves - least error")
    ("asked" 2 "yellow" "as asked")
    ("few"   4 "cyan"   "fewest curves - still within the distance")))
                                    ; same three aims as ABHD: "tight"
                                    ; fits to *LH-TIGHT-TOL* with no
                                    ; miss allowance and no cap;
                                    ; "asked" is the settings as
                                    ; typed; "few" lifts the miss
                                    ; allowance so arcs run as long as
                                    ; the typed distance permits
(setq *LH-TIGHT-TOL*    0.01)       ; the "tight" candidate's accuracy
                                    ; target (units)
(setq *LH-EXACT-EPS*    0.001)      ; "exactly on" threshold (units)
(setq *LH-FIT-EPS*      0.01)       ; an arc through an interior point
                                    ; must pass within twice this of it
                                    ; to count as anchored
(setq *LH-ON-EPS*       0.25)       ; a point within this of the result
                                    ; counts as ON it; only points off
                                    ; by more eat into the allowance
(setq *LH-MISS-PCT*     0.15)       ; share of the points (rounded UP)
                                    ; that may sit off the result by up
                                    ; to the tolerance
(setq *LH-CORNER-ANG*   (/ pi 4.0)) ; a point that turns more than this
                                    ; (45 deg) is a sharp corner: it
                                    ; may start or end a span but never
                                    ; gets buried inside one
(setq *LH-NICE-RADII* '(12.0 6.0 1.0)) ; preferred arc-radius tiers,
                                    ; tried in order: whole feet, half
                                    ; feet, whole inches
(setq *LH-TANG-TOL* (/ pi 22.5))    ; wiggle room from perfect tangency
                                    ; at each joint (8 degrees)
(setq *LH-TANG-STEPS* '(1.0 1.25 1.5)) ; when nothing fits inside the
                                    ; tangent window, stretch it by
                                    ; these multiples before falling
                                    ; back to a one-point stub
(setq *LH-SNAP-EPS*     0.02)       ; a nice-radius snap may move the
                                    ; covered points at most this far
                                    ; beyond where they already sat
(setq *LH-CHAIN-FUZZ*   1.0e-4)     ; endpoint-matching fuzz for
                                    ; chaining sketch segments
(if (null *LH-TOL*)   (setq *LH-TOL* 1.0))      ; default tolerance
(if (null *LH-SHAPE*) (setq *LH-SHAPE* "Closed")) ; closed or open,
                                    ; remembered per session
(if (null *LH-ZMODE*) (setq *LH-ZMODE* "Average")) ; where the outline
                                    ; sits in Z when the points carry
                                    ; elevations: Top / Bottom /
                                    ; Average / Zero, remembered
;; *LH-MAX-ARCS* : cap on the number of curved segments in the output;
;; nil = no cap.  Prompted for and remembered per session, like
;; *LH-TOL*.

;; ---- circle / arc geometry -----------------------------------------

;; Circumcenter of three points, nil when (nearly) collinear.
(defun lh:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
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
(defun lh:bulge-3pt (p1 q p2 / c a1 a2 aq dccw dq)
  (setq p1 (cal:2d p1) q (cal:2d q) p2 (cal:2d p2)
        c  (lh:circumcenter p1 q p2))
  (if (null c)
    0.0
    (progn
      (setq a1   (angle c p1)
            a2   (angle c p2)
            aq   (angle c q)
            dccw (cal:angnorm (- a2 a1))
            dq   (cal:angnorm (- aq a1)))
      (cond
        ((< dccw 1.0e-9) 0.0)                       ; degenerate sweep
        ((> dccw (- (* 2.0 pi) 1.0e-9)) 0.0)        ; degenerate sweep
        ((<= dq dccw) (cal:tan (/ dccw 4.0)))        ; CCW arc through Q
        (T (- (cal:tan (/ (- (* 2.0 pi) dccw) 4.0)))))))) ; CW through Q

;; Arc geometry of a bulged segment: (center radius angStart angEnd).
;; nil for a straight segment.
(defun lh:arc-geom (p1 p2 b / ch dir apex c)
  (if (< (abs b) 1.0e-9)
    nil
    (progn
      (setq p1   (cal:2d p1)
            p2   (cal:2d p2)
            ch   (cal:dist p1 p2)
            dir  (cal:v* (cal:v- p2 p1) (/ 1.0 ch))
            apex (cal:v+ (cal:mid p1 p2)
                         (cal:v* (cal:perp dir) (* -0.5 ch b)))
            c    (lh:circumcenter p1 apex p2))
      (if (null c)
        nil
        (list c (cal:dist c p1) (angle c p1) (angle c p2))))))

;; Distance from point P to segment (p1 p2 bulge).
(defun lh:seg-dist (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep rel)
  (setq p  (cal:2d p)
        p1 (cal:2d (car seg))
        p2 (cal:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    (progn
      (setq v    (cal:v- p2 p1)
            w    (cal:v- p p1)
            len2 (cal:dot v v))
      (if (< len2 1.0e-20)
        (cal:dist p p1)
        (progn
          (setq t2 (/ (cal:dot w v) len2))
          (if (< t2 0.0) (setq t2 0.0))
          (if (> t2 1.0) (setq t2 1.0))
          (cal:dist p (cal:v+ p1 (cal:v* v t2))))))
    (progn
      (setq g (lh:arc-geom p1 p2 b))
      (if (null g)
        (min (cal:dist p p1) (cal:dist p p2))
        (progn
          (setq c  (car g)  r (cadr g)
                a1 (caddr g) a2 (cadddr g)
                ap (angle c p))
          (if (> b 0.0)
            (setq sweep (cal:angnorm (- a2 a1)) rel (cal:angnorm (- ap a1)))
            (setq sweep (cal:angnorm (- a1 a2)) rel (cal:angnorm (- ap a2))))
          (if (<= rel sweep)
            (abs (- (cal:dist p c) r))
            (min (cal:dist p p1) (cal:dist p p2))))))))

;; Bulge of the arc that starts at A with tangent direction TANG
;; (radians) and ends at B.
(defun lh:tangent-bulge (a tang b / phi)
  (setq phi (cal:signed-dang tang (angle (cal:2d a) (cal:2d b))))
  (cal:tan (/ phi 2.0)))

;; Position of P along segment (p1 p2 bulge) as a 0..1 parameter,
;; used only to ORDER candidate points along the segment.
(defun lh:seg-param (p seg / p1 p2 b v w len2 g c a1 a2 ap sweep rel)
  (setq p  (cal:2d p)
        p1 (cal:2d (car seg))
        p2 (cal:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    (progn
      (setq v (cal:v- p2 p1) w (cal:v- p p1) len2 (cal:dot v v))
      (if (< len2 1.0e-20) 0.0 (/ (cal:dot w v) len2)))
    (progn
      (setq g (lh:arc-geom p1 p2 b))
      (if (null g)
        0.0
        (progn
          (setq c (car g) a1 (caddr g) a2 (cadddr g) ap (angle c p))
          (if (> b 0.0)
            (setq sweep (cal:angnorm (- a2 a1))
                  rel   (cal:angnorm (- ap a1)))
            (setq sweep (cal:angnorm (- a1 a2))
                  rel   (- (cal:angnorm (- a1 a2))
                           (cal:angnorm (- ap a2)))))
          (if (< sweep 1.0e-10) 0.0 (/ rel sweep)))))))

;; ---- entity -> segment extraction ----------------------------------
;; A segment is (startPt endPt bulge), 2D points.

(defun lh:lw-segs (ed / pts bls item segs n closed)
  (setq pts nil bls nil)
  (foreach item ed
    (cond
      ((= (car item) 10)
       (setq pts (cons (cal:2d (cdr item)) pts)
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
               (< (cal:dist (last pts) (car pts)) *LH-CHAIN-FUZZ*)))
    (if (>= (cal:dist (last pts) (car pts)) *LH-CHAIN-FUZZ*)
      (setq segs (cons (list (last pts) (car pts) (last bls)) segs))))
  (reverse segs))

(defun lh:pl-segs (en / ed sub pts bls segs n closed)
  ;; heavy (old-style) 2D POLYLINE: walk its VERTEX sub-entities
  (setq ed (entget en)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        pts nil bls nil
        sub (entnext en))
  (while (and sub (= "VERTEX" (cdr (assoc 0 (setq ed (entget sub))))))
    (if (= 0 (logand 17 (cond ((cdr (assoc 70 ed))) (0))))
      (setq pts (cons (cal:2d (cdr (assoc 10 ed))) pts)
            bls (cons (cond ((cdr (assoc 42 ed))) (0.0)) bls)))
    (setq sub (entnext sub)))
  (setq pts (reverse pts) bls (reverse bls) segs nil n 0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  (if (and closed (> (length pts) 2))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun lh:ent-segs (en / ed typ c r a1 a2 delta)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (cal:2d (cdr (assoc 10 ed)))
                 (cal:2d (cdr (assoc 11 ed)))
                 0.0)))
    ((= typ "ARC")
     (setq c  (cal:2d (cdr (assoc 10 ed)))
           r  (cdr (assoc 40 ed))
           a1 (cdr (assoc 50 ed))
           a2 (cdr (assoc 51 ed))
           delta (cal:angnorm (- a2 a1)))
     (if (< delta 1.0e-10) (setq delta (* 2.0 pi)))
     ;; a full-circle arc cannot be one bulged segment: two semis
     (if (> delta (- (* 2.0 pi) 1.0e-9))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r) (cal:tan (/ delta 4.0))))))
    ((= typ "CIRCLE")
     (setq c (cal:2d (cdr (assoc 10 ed)))
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
    ((= typ "LWPOLYLINE") (lh:lw-segs ed))
    ((= typ "POLYLINE") (lh:pl-segs en))
    (T nil)))

;; ---- chain loose sketch segments into one run ------------------------
;; The chain of SEGS in forward order, reversed segment by segment.
(defun lh:rev-segs (segs)
  (mapcar '(lambda (s) (list (cadr s) (car s) (- (caddr s)))) (reverse segs)))

;; Chain loose segments into one run, closed or open.  Unlike ABHD's
;; chainer this one accepts a chain that does not close: when nothing
;; joins the growing end any more, the chain is turned around once and
;; grown from its other end (an open sketch has two).  Returns
;; (closedflag . orderedSegs), or nil for an empty input; pieces that
;; join neither end are reported and ignored.
(defun lh:chain (segs / fwd start end found s rest flipped go)
  (if (null segs)
    nil
    (progn
      (setq fwd     (list (car segs))
            start   (car (car segs))
            end     (cadr (car segs))
            segs    (cdr segs)
            flipped nil
            go      T)
      (while (and go segs (>= (cal:dist end start) *LH-CHAIN-FUZZ*))
        (setq found nil rest nil)
        (foreach s segs
          (cond
            (found (setq rest (cons s rest)))
            ((< (cal:dist end (car s)) *LH-CHAIN-FUZZ*)
             (setq found s))
            ((< (cal:dist end (cadr s)) *LH-CHAIN-FUZZ*)
             (setq found (list (cadr s) (car s) (- (caddr s)))))
            (T (setq rest (cons s rest)))))
        (cond
          (found
           (setq fwd  (append fwd (list found))
                 end  (cadr found)
                 segs (reverse rest)))
          ((not flipped)
           (setq fwd     (lh:rev-segs fwd)
                 start   (car (car fwd))
                 end     (cadr (last fwd))
                 flipped T))
          (T (setq go nil))))
      (if segs
        (princ (strcat "\nLHD: warning - " (itoa (length segs))
                       " sketch segment(s) that join neither end of the"
                       " chain were ignored.")))
      (cons (< (cal:dist (cadr (last fwd)) (car (car fwd))) *LH-CHAIN-FUZZ*)
            fwd))))

;; ---- span fitting helpers --------------------------------------------
;; A "span" is one candidate segment from A to B judged against QS, the
;; scanned points it is supposed to represent.

;; Worst distance from any of QS to the segment (A B bulge).
(defun lh:span-dev (a b bul qs / seg mx d q)
  (setq seg (list a b bul) mx 0.0)
  (foreach q qs
    (setq d (lh:seg-dist q seg))
    (if (> d mx) (setq mx d)))
  mx)

;; The miss percentage in force for the current run.
(defun lh:misspct ()
  (if lh-miss-pct lh-miss-pct *LH-MISS-PCT*))

;; The "on the shape" threshold in force for the current run; scales
;; with the tolerance (a quarter of it, never below *LH-ON-EPS*).
;; lh-on-eps is bound per pass by lh:fit-pass / lh:fit-pass-open.
(defun lh:oneps ()
  (if lh-on-eps lh-on-eps *LH-ON-EPS*))

;; How many of QS sit farther than the on-the-shape threshold from the
;; segment - the points that would eat into the miss allowance.
(defun lh:span-misses (a b bul qs / seg c q lim)
  (setq seg (list a b bul) c 0 lim (lh:oneps))
  (foreach q qs
    (if (> (lh:seg-dist q seg) lim) (setq c (1+ c))))
  c)

;; Radius of the arc (A B bulge); nil for a straight segment.
(defun lh:bulge-radius (a b bl / h)
  (if (< (abs bl) 1.0e-9)
    nil
    (progn
      (setq h (/ (cal:dist a b) 2.0))
      (/ (* h (1+ (* bl bl))) (* 2.0 (abs bl))))))

;; Bulge of the arc from A to B with radius R, on the same side and
;; with the same minor/major-arc character as reference bulge BREF.
(defun lh:radius-bulge (a b r bref / h s bl)
  (setq h (/ (cal:dist a b) 2.0))
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
(defun lh:snap-arc (a b bl qs tol left win / r0 h best tier lo hi
                                              cands r bl2 mis)
  (setq r0   (lh:bulge-radius a b bl)
        h    (/ (cal:dist a b) 2.0)
        best nil)
  (if (and r0 (< r0 1.0e6))       ; a huge radius is basically straight
    (foreach tier *LH-NICE-RADII*
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
                (setq bl2 (lh:radius-bulge a b r bl))
                (if (and bl2
                         (or (null win)
                             (and (>= bl2 (car win)) (<= bl2 (cdr win))))
                         (<= (lh:span-dev a b bl2 qs) tol)
                         (<= (setq mis (lh:span-misses a b bl2 qs))
                             left))
                  (setq best (cons bl2 mis))))))))))
  best)

;; ---- point ordering and naming ---------------------------------------

;; Remove every element equal (within fuzz) to VAL from LST.
(defun lh:remove (val lst / out x)
  (foreach x lst
    (if (not (equal x val 1.0e-9)) (setq out (cons x out))))
  (reverse out))

;; Insert (key . val) pair X into the already-sorted list LST.
(defun lh:ins-car (x lst)
  (cond ((null lst) (list x))
        ((< (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (lh:ins-car x (cdr lst))))))

;; Insertion-sort a list of (key . val) pairs ascending by key.
(defun lh:sort-car (lst / out x)
  (foreach x lst (setq out (lh:ins-car x out)))
  out)

;; T when the chained sketch contains at least one curved segment.
(defun lh:has-arcs (loop / r)
  (foreach s loop (if (>= (abs (caddr s)) 1.0e-9) (setq r T)))
  r)

;; Order points into a closed tour: nearest-neighbour walk from the
;; leftmost point, then 2-opt passes to remove crossings.  (ABHD's
;; closed-mode ordering, unchanged.)
(defun lh:order-points (pts / start cur tour rest best bd q d n i j k
                              pass improved ti ti1 tj tj1 delta head midl
                              taill)
  (setq start (car pts))
  (foreach q (cdr pts)
    (if (or (< (car q) (car start))
            (and (= (car q) (car start)) (< (cadr q) (cadr start))))
      (setq start q)))
  (setq cur  start
        rest (lh:remove start pts)
        tour (list start))
  (while rest
    (setq best nil bd nil)
    (foreach q rest
      (setq d (cal:dist cur q))
      (if (or (null bd) (< d bd)) (setq best q bd d)))
    (setq tour (cons best tour)
          cur  best
          rest (lh:remove best rest)))
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
                  delta (- (+ (cal:dist ti tj) (cal:dist ti1 tj1))
                           (+ (cal:dist ti ti1) (cal:dist tj tj1))))
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

;; The farthest-apart pair of points, as (a b) - the automatic choice
;; of ends for an open run.
(defun lh:far-pair (pts / a b best q r d)
  (setq best -1.0 a nil b nil)
  (foreach q pts
    (foreach r pts
      (setq d (cal:dist q r))
      (if (> d best) (setq best d a q b r))))
  (list a b))

;; Order points into an OPEN run from E1 to E2 (nil = pick the
;; farthest-apart pair automatically): nearest-neighbour walk from E1,
;; E2 forced last, then 2-opt with BOTH ENDS FIXED.  Reversing
;; tour[i+1..j] changes only the edges (i,i+1) and (j,j+1); with j
;; capped at n-2 the index j+1 always exists, so there is no
;; wraparound and no closing edge to price - the closed 2-opt's delta
;; would charge for an edge an open run does not have.
(defun lh:order-points-open (pts e1 e2 / pr cur tour rest best bd q d n
                                          i j k ti ti1 tj tj1 delta head
                                          midl taill pass improved)
  (if (null e1)
    (progn
      (setq pr (lh:far-pair pts)
            e1 (car pr)
            e2 (cadr pr))))
  (setq cur  e1
        rest (lh:remove e2 (lh:remove e1 pts))
        tour (list e1))
  (while rest
    (setq best nil bd nil)
    (foreach q rest
      (setq d (cal:dist cur q))
      (if (or (null bd) (< d bd)) (setq best q bd d)))
    (setq tour (cons best tour)
          cur  best
          rest (lh:remove best rest)))
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
              delta (- (+ (cal:dist ti tj) (cal:dist ti1 tj1))
                       (+ (cal:dist ti ti1) (cal:dist tj tj1))))
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

;; Order points by their position along a chained ordering sketch:
;; each point keys on segment-index + parameter.
(defun lh:loop-order (loop pts / keyed q best bd d i s tp)
  (foreach q pts
    (setq best 0 bd nil i 0)
    (foreach s loop
      (setq d (lh:seg-dist q s))
      (if (or (null bd) (< d bd)) (setq bd d best i))
      (setq i (1+ i)))
    (setq tp (lh:seg-param q (nth best loop)))
    (if (< tp 0.0) (setq tp 0.0))
    (if (> tp 1.0) (setq tp 1.0))
    (setq keyed (cons (cons (+ best tp) q) keyed)))
  (mapcar 'cdr (lh:sort-car keyed)))

;; Remember a point, what to call it, and - when it has one - its
;; elevation, so a miss reports as "Pt.17" and the output height can
;; be taken from the points.  Points with no name get the next count.
(defun lh:add-point (p nm z)
  (setq npt        (1+ npt)
        pts        (cons p pts)
        lh-ptnames (cons (cons p (if (and nm (/= nm "")) nm (itoa npt)))
                         lh-ptnames))
  (if (and z (> (abs z) 1.0e-9))
    (setq lh-zvals (cons (cons p z) lh-zvals))))

;; What to call the scanned point at Q.
(defun lh:pt-name (q / nm p)
  (setq nm nil)
  (foreach p lh-ptnames
    (if (and (null nm) (< (cal:dist (car p) q) *LH-EXACT-EPS*))
      (setq nm (cdr p))))
  (if nm nm "?"))

;; The member of LST nearest to P.
(defun lh:nearest (p lst / best bd q d)
  (setq best nil bd nil)
  (foreach q lst
    (setq d (cal:dist p q))
    (if (or (null bd) (< d bd)) (setq best q bd d)))
  best)

;; Index of point P in TOUR (exact-point fuzz), or nil.
(defun lh:tour-index (p tour / i k q)
  (setq i nil k 0)
  (foreach q tour
    (if (and (null i) (< (cal:dist p q) *LH-EXACT-EPS*)) (setq i k))
    (setq k (1+ k)))
  i)

;; Rotate the closed TOUR so it starts at point P.
(defun lh:rotate-to-point (tour p / i)
  (setq i (lh:tour-index p tour))
  (if (and i (> i 0))
    (append (cal:nthcdr i tour) (cal:sublist tour 0 i))
    tour))

;; Rotate the closed TOUR so it starts at its sharpest turn.
(defun lh:rotate-to-corner (tour / n i prev cur next turn best bi)
  (setq n (length tour) i 0 best -1.0 bi 0)
  (repeat n
    (setq prev (nth (rem (+ i n -1) n) tour)
          cur  (nth i tour)
          next (nth (rem (1+ i) n) tour)
          turn (abs (cal:signed-dang (angle prev cur) (angle cur next))))
    (if (> turn best) (setq best turn bi i))
    (setq i (1+ i)))
  (append (cal:nthcdr bi tour) (cal:sublist tour 0 bi)))

;; Number of curved segments in a span list.
(defun lh:arc-count (spans / c sp)
  (setq c 0)
  (foreach sp spans (if (>= (abs (caddr sp)) 1.0e-9) (setq c (1+ c))))
  c)

;; ---- near-tangent span fitting ---------------------------------------
;; Arcs sit ON the scanned points: every span runs from tour point to
;; tour point and its interior is fitted through the points with exact
;; 3-point arcs.  Tangency is a WINDOW: at each joint the new arc's
;; start tangent may differ from the previous arc's end tangent by at
;; most *LH-TANG-TOL*.  A bulge window is a cons (lo . hi); nil means
;; unconstrained.

;; Allowed bulge interval for the span A->B whose START tangent must
;; lie within *LH-TANG-TOL* (times WF) of the incoming tangent TE.
(defun lh:tang-window (te a b wf / tt phi alo ahi lo hi)
  (setq tt  (* *LH-TANG-TOL* wf)
        phi (cal:signed-dang te (angle a b))
        alo (max (min (/ (- phi tt) 2.0) 1.373) -1.373)
        ahi (max (min (/ (+ phi tt) 2.0) 1.373) -1.373)
        lo  (cal:tan alo)
        hi  (cal:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Allowed bulge interval for the CLOSING span A->B whose END tangent
;; must lie within *LH-TANG-TOL* (times WF) of the loop's start
;; tangent TS0.  Closed mode only - an open run has no closing span.
(defun lh:end-window (ts0 a b wf / tt psi alo ahi lo hi)
  (setq tt  (* *LH-TANG-TOL* wf)
        psi (cal:signed-dang (angle a b) ts0)
        alo (max (min (/ (- psi tt) 2.0) 1.373) -1.373)
        ahi (max (min (/ (+ psi tt) 2.0) 1.373) -1.373)
        lo  (cal:tan alo)
        hi  (cal:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Intersect two bulge windows; when they don't overlap, split the
;; difference so the leftover kink shares across the two joints.
(defun lh:merge-windows (win win2 / lo hi)
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
(defun lh:clamp-b (b win)
  (cond ((null win) b)
        ((< b (car win)) (car win))
        ((> b (cdr win)) (cdr win))
        (T b)))

;; Closest any of QS comes to the segment (A B bulge).
(defun lh:span-min (a b bul qs / seg mn d q)
  (setq seg (list a b bul) mn nil)
  (foreach q qs
    (setq d (lh:seg-dist q seg))
    (if (or (null mn) (< d mn)) (setq mn d)))
  mn)

;; Best bulge for the span A->B over interior points QS, restricted to
;; the tangent window WIN (nil = free).  Exact 3-point arcs come
;; first; compromise bulges only when no exact arc works.  Returns
;; (bulge dev misses exactflag).
(defun lh:span-fit (a b qs win tol left / bls m sum bl cands best d mis)
  (setq bls  (mapcar '(lambda (q) (lh:bulge-3pt a q b)) qs)
        m    (length qs)
        best nil)
  (foreach bl bls
    (if (or (null win)
            (and (>= bl (car win)) (<= bl (cdr win))))
      (progn
        (setq d (lh:span-dev a b bl qs))
        (if (and (<= d tol)
                 (or (null best) (< d (cadr best))))
          (progn
            (setq mis (lh:span-misses a b bl qs))
            (if (<= mis left)
              (setq best (list bl d mis T))))))))
  (if (null best)
    (progn
      (setq sum 0.0)
      (foreach bl bls (setq sum (+ sum bl)))
      (setq cands (list (/ sum m) (nth (/ m 2) bls)))
      (if (>= m 4)
        (setq cands (append cands (list (nth (/ m 4) bls)
                                        (nth (/ (* 3 m) 4) bls)))))
      (if win
        (setq cands (append (mapcar '(lambda (bl) (lh:clamp-b bl win))
                                    cands)
                            (list (car win) (cdr win)
                                  (/ (+ (car win) (cdr win)) 2.0)))))
      (foreach bl cands
        (setq d (lh:span-dev a b bl qs))
        (if (or (null best) (< d (cadr best)))
          (setq best (list bl d (lh:span-misses a b bl qs) nil))))))
  best)

;; Cover the rotated CLOSED tour with arcs whose endpoints sit ON the
;; tour points.  ABHD's loop walker, unchanged: modular indices, the
;; seam held inside the tangent window, TE0 seeding the first span to
;; close the seam on a re-run.
(defun lh:span-loop (tour tol left te0 pro / n sharp i prev cur next
                                             turn strtshp segs pos te
                                             ts0 lim a best bstx len go
                                             bnd win qs fr bl mis sn
                                             dev0 anch steps wf lm
                                             walls w i1 i2 fwd nogrow f
                                             wrec)
  (setq n (length tour))
  ;; sharp corners: intentional kinks, window resets
  (setq sharp nil i 0)
  (repeat n
    (setq prev (nth (rem (+ i n -1) n) tour)
          cur  (nth i tour)
          next (nth (rem (1+ i) n) tour)
          turn (abs (cal:signed-dang (angle prev cur) (angle cur next))))
    (setq sharp (cons (or (> turn *LH-CORNER-ANG*)
                          (lh:memb cur lh-corners))
                      sharp)
          i     (1+ i)))
  (setq sharp (reverse sharp))
  ;; declared straight stretches onto tour indices, short way around
  (setq walls nil)
  (foreach w lh-walls
    (setq i1 (lh:tour-index (car w) tour)
          i2 (lh:tour-index (cadr w) tour))
    (if (and i1 i2 (/= i1 i2))
      (progn
        (setq fwd (rem (+ (- i2 i1) n) n))
        (if (> (* 2 fwd) n)
          (setq i1 i2 fwd (- n fwd)))
        (if (<= (+ i1 fwd) n)
          (setq walls (cons (list i1 (+ i1 fwd)) walls))))))
  ;; indices ordinary spans may not swallow - including every HELD
  ;; point: a span may end on one (landing exactly) but never bury it
  (setq nogrow nil i 0)
  (repeat n
    (setq f (nth i sharp))
    (foreach w walls
      (if (and (>= i (car w)) (<= i (cadr w))) (setq f T))
      (if (and (= (cadr w) n) (= i 0)) (setq f T)))
    (if (lh:memb (nth i tour) lh-holds) (setq f T))
    (setq nogrow (cons f nogrow)
          i      (1+ i)))
  (setq nogrow  (reverse nogrow)
        strtshp (car sharp)
        segs    nil
        pos     0
        te      (if strtshp nil te0)
        ts0     nil)
  (while (< pos n)
    (setq a    (nth pos tour)
          wrec (assoc pos walls))
    (if wrec
      ;; ---- a declared straight stretch starts here: emit verbatim --
      (progn
        (setq len  (- (cadr wrec) pos)
              bnd  (nth (rem (cadr wrec) n) tour)
              qs   (cal:sublist tour (1+ pos) (1- len))
              mis  (lh:span-misses a bnd 0.0 qs)
              segs (cons (list a bnd 0.0) segs)
              left (max 0 (- left mis)))
        (if (and (null ts0) (not strtshp))
          (setq ts0 (angle a bnd)))
        (setq pos (cadr wrec)
              te  (if (and (< pos n) (nth (rem pos n) sharp))
                    nil
                    (angle a bnd))))
      ;; ---- an ordinary span --------------------------------------
      (progn
    ;; the first span stops one point short so the result always has
    ;; at least two real segments
    (setq lim  (if (= pos 0) (1- (- n pos)) (- n pos))
          best nil                   ; longest feasible span of any kind
          bstx nil                   ; longest span through an interior point
          steps *LH-TANG-STEPS*)
    (while (and (null best) steps)
      (setq wf    (car steps)
            steps (cdr steps)
            len   2
            go    T)
      (while (and go (<= len lim))
        (if (nth (rem (+ pos len -1) n) nogrow)
          (setq go nil)         ; never bury a corner or a wall point
          (progn
            (setq bnd (nth (rem (+ pos len) n) tour)
                  win (if te (lh:tang-window te a bnd wf)))
            ;; the span that closes the loop must also end within the
            ;; tangent window of the loop's start
            (if (and (= (+ pos len) n) (not strtshp) ts0)
              (setq win (lh:merge-windows win
                                          (lh:end-window ts0 a bnd wf))))
            (setq qs (cal:sublist tour (1+ pos) (1- len))
                  lm (if pro
                       (min left (cal:ceil (* (lh:misspct) len)))
                       left)
                  fr (lh:span-fit a bnd qs win tol lm))
            (if (and (<= (cadr fr) tol) (<= (caddr fr) lm))
              (progn
                (setq best (list len (car fr) (caddr fr) win))
                (if (cadddr fr) (setq bstx best))
                (setq len (1+ len)))
              (setq go nil))))))
    ;; a floating arc must cover at least 2 more points than the
    ;; longest arc through an interior point to be chosen
    (if (and bstx best (< (car best) (+ (car bstx) 2)))
      (setq best bstx))
    (if (null best)
      ;; stub to the very next point: continue the incoming tangent
      (progn
        (setq bnd (nth (rem (1+ pos) n) tour))
        (if te
          (progn
            (setq bl (lh:tangent-bulge a te bnd))
            (if (and (= (1+ pos) n) (not strtshp) ts0)
              ;; closing stub: split the kink between both joints
              (setq bl (/ (+ bl (cal:tan (/ (cal:signed-dang (angle a bnd)
                                                           ts0)
                                           2.0)))
                          2.0)))
            (if (> bl 1.0) (setq bl 1.0))
            (if (< bl -1.0) (setq bl -1.0)))
          (setq bl 0.0))
        (setq best (list 1 bl 0 nil)))
      ;; nice-radius snap inside the same tangent window
      (progn
        (setq len  (car best)
              bl   (cadr best)
              win  (cadddr best)
              bnd  (nth (rem (+ pos len) n) tour)
              qs   (cal:sublist tour (1+ pos) (1- len))
              dev0 (lh:span-dev a bnd bl qs)
              anch (<= (lh:span-min a bnd bl qs) (* 2.0 *LH-FIT-EPS*))
              sn   (lh:snap-arc a bnd bl qs
                                (max dev0 *LH-SNAP-EPS*) left win))
        (if (and sn
                 (or (not anch)
                     (<= (lh:span-min a bnd (car sn) qs)
                         (* 2.0 *LH-FIT-EPS*))))
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
                (+ (angle a bnd) (* 2.0 (atan bl))))))))
  (reverse segs))

;; Cover the OPEN tour with arcs, walking it once from end to end.
;; This is lh:span-loop rebuilt with LINEAR indices - not a stripped
;; copy, because the loop walker's modular arithmetic (rem ... n) is
;; exactly what an open run must not do: there is no seam, no closing
;; span, no start-tangent seeding, and the last span simply ends at
;; the final point.  The two path ends are free kinks by construction;
;; sharp corners are flagged on interior points only.  Everything else
;; - the window widening, exact-arc preference, floating-arc rule and
;; nice-radius snap - is the loop walker's, unchanged.
(defun lh:span-path (tour tol left pro / n sharp i prev cur next turn
                                         segs pos te lim a best bstx
                                         len go bnd win qs fr bl mis sn
                                         dev0 anch steps wf lm walls w
                                         i1 i2 nogrow f wrec)
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
              turn (abs (cal:signed-dang (angle prev cur)
                                        (angle cur next))))
        (setq sharp (cons (or (> turn *LH-CORNER-ANG*)
                              (lh:memb cur lh-corners))
                          sharp))))
    (setq i (1+ i)))
  (setq sharp (reverse sharp))
  ;; declared straight stretches map straight onto linear indices -
  ;; no short-way-around: an open run has only one way between them
  (setq walls nil)
  (foreach w lh-walls
    (setq i1 (lh:tour-index (car w) tour)
          i2 (lh:tour-index (cadr w) tour))
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
    (if (lh:memb (nth i tour) lh-holds) (setq f T))
    (setq nogrow (cons f nogrow)
          i      (1+ i)))
  (setq nogrow (reverse nogrow)
        segs   nil
        pos    0
        te     nil)
  (while (< pos (1- n))
    (setq a    (nth pos tour)
          wrec (assoc pos walls))
    (if wrec
      ;; ---- a declared straight stretch starts here: emit verbatim --
      (progn
        (setq len  (- (cadr wrec) pos)
              bnd  (nth (cadr wrec) tour)
              qs   (cal:sublist tour (1+ pos) (1- len))
              mis  (lh:span-misses a bnd 0.0 qs)
              segs (cons (list a bnd 0.0) segs)
              left (max 0 (- left mis))
              pos  (cadr wrec)
              te   (if (and (< pos (1- n)) (nth pos sharp))
                     nil
                     (angle a bnd))))
      ;; ---- an ordinary span --------------------------------------
      (progn
    ;; a span may reach the last point and no further; one arc over
    ;; the whole open run is legitimate, so no stop-short rule here
    (setq lim  (- (1- n) pos)
          best nil                   ; longest feasible span of any kind
          bstx nil                   ; longest span through an interior point
          steps *LH-TANG-STEPS*)
    (while (and (null best) steps)
      (setq wf    (car steps)
            steps (cdr steps)
            len   2
            go    T)
      (while (and go (<= len lim))
        (if (nth (+ pos len -1) nogrow)
          (setq go nil)         ; never bury a corner or a wall point
          (progn
            (setq bnd (nth (+ pos len) tour)
                  win (if te (lh:tang-window te a bnd wf))
                  qs  (cal:sublist tour (1+ pos) (1- len))
                  lm  (if pro
                        (min left (cal:ceil (* (lh:misspct) len)))
                        left)
                  fr  (lh:span-fit a bnd qs win tol lm))
            (if (and (<= (cadr fr) tol) (<= (caddr fr) lm))
              (progn
                (setq best (list len (car fr) (caddr fr) win))
                (if (cadddr fr) (setq bstx best))
                (setq len (1+ len)))
              (setq go nil))))))
    ;; a floating arc must cover at least 2 more points than the
    ;; longest arc through an interior point to be chosen
    (if (and bstx best (< (car best) (+ (car bstx) 2)))
      (setq best bstx))
    (if (null best)
      ;; stub to the very next point: continue the incoming tangent
      (progn
        (setq bnd (nth (1+ pos) tour))
        (if te
          (progn
            (setq bl (lh:tangent-bulge a te bnd))
            (if (> bl 1.0) (setq bl 1.0))
            (if (< bl -1.0) (setq bl -1.0)))
          (setq bl 0.0))
        (setq best (list 1 bl 0 nil)))
      ;; nice-radius snap inside the same tangent window
      (progn
        (setq len  (car best)
              bl   (cadr best)
              win  (cadddr best)
              bnd  (nth (+ pos len) tour)
              qs   (cal:sublist tour (1+ pos) (1- len))
              dev0 (lh:span-dev a bnd bl qs)
              anch (<= (lh:span-min a bnd bl qs) (* 2.0 *LH-FIT-EPS*))
              sn   (lh:snap-arc a bnd bl qs
                                (max dev0 *LH-SNAP-EPS*) left win))
        (if (and sn
                 (or (not anch)
                     (<= (lh:span-min a bnd (car sn) qs)
                         (* 2.0 *LH-FIT-EPS*))))
          (setq best (list len (car sn) (cdr sn) win)))))
    (setq len  (car best)
          bl   (cadr best)
          mis  (caddr best)
          bnd  (nth (+ pos len) tour)
          segs (cons (list a bnd bl) segs)
          left (- left mis)
          pos  (+ pos len)
          te   (if (and (< pos (1- n)) (nth pos sharp))
                 nil
                 (+ (angle a bnd) (* 2.0 (atan bl))))))))
  (reverse segs))

;; Tangent mismatch at the loop's closing joint (radians).
(defun lh:seam-kink (segs / sl sf te ts)
  (setq sl (last segs)
        sf (car segs)
        te (+ (angle (car sl) (cadr sl)) (* 2.0 (atan (caddr sl))))
        ts (- (angle (car sf) (cadr sf)) (* 2.0 (atan (caddr sf)))))
  (abs (cal:signed-dang te ts)))

;; One full CLOSED fit; when the seam closes with more than
;; *LH-TANG-TOL* of kink, refit once seeding the first span's window
;; with the arrival tangent and keep whichever seam is straighter.
(defun lh:fit-pass (tour tol left pro / segs k1 sl te0 segs2 lh-on-eps)
  (setq lh-on-eps (max *LH-ON-EPS* (* 0.25 tol))
        segs      (lh:span-loop tour tol left nil pro)
        k1        (lh:seam-kink segs))
  (if (> k1 (+ *LH-TANG-TOL* 0.001))
    (progn
      (setq sl    (last segs)
            te0   (+ (angle (car sl) (cadr sl))
                     (* 2.0 (atan (caddr sl))))
            segs2 (lh:span-loop tour tol left te0 pro))
      (if (< (lh:seam-kink segs2) k1) (setq segs segs2))))
  segs)

;; One full OPEN fit.  A single walk is the whole job: there is no
;; seam to close, so the seam-kink re-run has nothing to do here.
(defun lh:fit-pass-open (tour tol left pro / lh-on-eps)
  (setq lh-on-eps (max *LH-ON-EPS* (* 0.25 tol)))
  (lh:span-path tour tol left pro))

;; Closed points-driven fit with the curve cap: refit the whole loop
;; with a progressively relaxed tolerance until the cap holds, keeping
;; the fewest-curves result seen.  (ABHD's, unchanged.)
(defun lh:coarse-loop (tour tol maxarcs left pro / segs segs2 tol2 tries)
  ;; start the walk at a declared stretch or corner when there is one;
  ;; otherwise at the sharpest turn
  (setq tour (cond
               (lh-walls   (lh:rotate-to-point tour (car (car lh-walls))))
               (lh-corners (lh:rotate-to-point tour (car lh-corners)))
               (T          (lh:rotate-to-corner tour)))
        segs (lh:fit-pass tour tol left pro))
  (if maxarcs
    (progn
      (setq tol2 tol tries 0)
      (while (and (> (lh:arc-count segs) maxarcs) (< tries 40))
        (setq tol2  (* tol2 1.4)
              tries (1+ tries)
              segs2 (lh:fit-pass tour tol2 1000000 nil))
        (if (< (lh:arc-count segs2) (lh:arc-count segs))
          (setq segs segs2)))))
  segs)

;; The open counterpart: same relaxing cap loop, but the tour is NOT
;; rotated - an open run's start and end are its endpoints, and
;; rotating them away would corrupt the path.
(defun lh:coarse-path (tour tol maxarcs left pro / segs segs2 tol2 tries)
  (setq segs (lh:fit-pass-open tour tol left pro))
  (if maxarcs
    (progn
      (setq tol2 tol tries 0)
      (while (and (> (lh:arc-count segs) maxarcs) (< tries 40))
        (setq tol2  (* tol2 1.4)
              tries (1+ tries)
              segs2 (lh:fit-pass-open tour tol2 1000000 nil))
        (if (< (lh:arc-count segs2) (lh:arc-count segs))
          (setq segs segs2)))))
  segs)

;; ---- self-intersection check -----------------------------------------

;; Cross product of (P-O) x (Q-O); its sign says which side Q is on.
(defun lh:cross3 (o p q)
  (- (* (- (car p) (car o)) (- (cadr q) (cadr o)))
     (* (- (cadr p) (cadr o)) (- (car q) (car o)))))

;; T when segments A-B and C-D properly cross.
(defun lh:segs-cross (a b c d / d1 d2 d3 d4)
  (setq d1 (lh:cross3 a b c) d2 (lh:cross3 a b d)
        d3 (lh:cross3 c d a) d4 (lh:cross3 c d b))
  (and (< (* d1 d2) 0.0) (< (* d3 d4) 0.0)))

;; Sample the fitted chain into a point list; arcs get intermediate
;; points so a bulging arc's real path is tested, not just its chord.
(defun lh:loop-pts (segs / out s g c r a1 a2 sweep k j aa)
  (setq out nil)
  (foreach s segs
    (setq out (cons (cal:2d (car s)) out))
    (if (>= (abs (caddr s)) 1.0e-9)
      (progn
        (setq g (lh:arc-geom (car s) (cadr s) (caddr s)))
        (if g
          (progn
            (setq c  (car g)   r  (cadr g)
                  a1 (caddr g) a2 (cadddr g))
            (if (> (caddr s) 0.0)
              (setq sweep (cal:angnorm (- a2 a1)))
              (setq sweep (- (cal:angnorm (- a1 a2)))))
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
(defun lh:self-crosses (segs closed / p n found ti tj i j a b c d)
  (setq p (lh:loop-pts segs))
  (if closed
    (setq p (append p (list (car p))))
    (setq p (append p (list (cal:2d (cadr (last segs)))))))
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
          (if (not (and closed (= i 0) (= j (1- n))))
            (if (lh:segs-cross a b c d) (setq found T)))
          (setq tj (cdr tj) j (1+ j)))
        (setq ti (cdr ti) i (1+ i)))
      found)))

;; ---- output helpers --------------------------------------------------

;; How many fitted polylines are already on the output layer.
(defun lh:prior-fits (/ ss)
  (setq ss (ssget "_X" (list (cons 8 *LH-OUT-LAYER*)
                             '(0 . "LWPOLYLINE"))))
  (if ss (sslength ss) 0))

;; T when R is a whole multiple of one of the *LH-NICE-RADII* tiers.
(defun lh:nice-radius-p (r / found tier q)
  (setq found nil)
  (if (and r (< r 1.0e6))
    (foreach tier *LH-NICE-RADII*
      (setq q (/ r tier))
      (if (< (abs (- q (fix (+ q 0.5)))) 1.0e-6) (setq found T))))
  found)

;; VERTS: list of (pt bulge) in order.  For a CLOSED polyline the last
;; vertex's bulge curves back to the first; an OPEN polyline needs the
;; final end point as one more vertex (bulge 0) or its last segment
;; silently vanishes - the callers append it.  ELEV is the single
;; height the whole polyline sits at (LWPOLYLINE group 38); COL is an
;; AutoCAD colour index, or nil for BYLAYER.
(defun lh:make-pline (verts layer col closed elev / dxf v)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                  (cons 8 layer)))
  (if col (setq dxf (append dxf (list (cons 62 col)))))
  (setq dxf (append dxf (list '(100 . "AcDbPolyline")
                              (cons 90 (length verts))
                              (cons 70 (if closed 1 0))
                              (cons 38 elev))))
  (foreach v verts
    (setq dxf (append dxf (list (cons 10 (car v)) (cons 42 (cadr v))))))
  (entmakex dxf))

;; The kept fit joins the POOL layer in ByLayer colour: the preview
;; colour and layer belonged to the comparison - the result belongs
;; with the rest of the drawing.
(defun lh:set-bylayer (en / ed)
  (cal:ensure-layer *LH-POOL-LAYER* 4)
  (setq ed (entget en)
        ed (subst (cons 8 *LH-POOL-LAYER*) (assoc 8 ed) ed))
  (if (assoc 62 ed) (setq ed (subst '(62 . 256) (assoc 62 ed) ed)))
  (entmod ed))

;; The points SEGS fails to hold within TOL.
(defun lh:unheld (segs pts tol / out q s d dmin)
  (setq out nil)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (lh:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin tol) (setq out (cons q out))))
  (reverse out))

;; List membership by position, within the exact-point fuzz.
(defun lh:memb (q lst / found p)
  (setq found nil)
  (foreach p lst
    (if (< (cal:dist p q) *LH-EXACT-EPS*) (setq found T)))
  found)

(defun lh:isect (a b / out q)
  (setq out nil)
  (foreach q a
    (if (lh:memb q b) (setq out (cons q out))))
  (reverse out))

;; ---- temporary preview geometry --------------------------------------
;; Every piece of scaffolding - dashed markers, candidate outlines,
;; labels - registers here as it is created and is swept away when the
;; command ends, however it ends.  Whatever the user keeps is dropped
;; from the list first.

(defun lh:temp-add (en)
  (if en (setq lh-temp (cons en lh-temp)))
  en)

(defun lh:temp-drop (en / out x)
  (setq out nil)
  (foreach x lh-temp
    (if (not (eq x en)) (setq out (cons x out))))
  (setq lh-temp (reverse out))
  en)

(defun lh:temp-clear ( / en)
  (foreach en lh-temp
    (if (and en (entget en)) (entdel en)))
  (setq lh-temp nil))

;; ---- "this one is mine" stamping -------------------------------------
;; LHD writes onto layers the drawing may already be using, so it must
;; never clear a layer wholesale: everything it creates carries xdata
;; naming this command, and only stamped objects are ever erased.

(defun lh:tag-mine (en / ed)
  (if en
    (progn
      (regapp "LHD")
      (setq ed (entget en))
      (entmod (append ed (list (list -3 (list "LHD" (cons 1000 "LHD"))))))))
  en)

;; Erase only LHD's own objects on a layer.  Returns how many went.
(defun lh:purge-mine (name / ss i n en)
  (setq n 0)
  (if (tblsearch "LAYER" name)
    (progn
      (setq ss (ssget "_X" (list (cons 8 name))))
      (if ss
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq en (ssname ss i))
            (if (assoc -3 (entget en '("LHD")))
              (progn (entdel en) (setq n (1+ n))))
            (setq i (1+ i)))))))
  n)

;; Make sure the DASHED linetype exists (pure entmake).
(defun lh:ensure-dashed ()
  (if (not (tblsearch "LTYPE" "DASHED"))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   '(2 . "DASHED") '(70 . 0)
                   '(3 . "Dashed __ __ __ __ __")
                   '(72 . 65) '(73 . 2) '(40 . 18.0)
                   '(49 . 12.0) '(74 . 0)
                   '(49 . -6.0) '(74 . 0)))))

;; Draw the dashed ring marking a declared sharp corner.
(defun lh:draw-corner-marker (p)
  (lh:ensure-dashed)
  (cal:ensure-layer *LH-WALL-LAYER* 8)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *LH-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 *LH-MISS-RADIUS*))))

;; Draw the marker for a declared HELD point: a dashed ring at half
;; the miss-ring radius, so it reads apart from corner rings.
(defun lh:draw-hold-marker (p)
  (lh:ensure-dashed)
  (cal:ensure-layer *LH-WALL-LAYER* 8)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *LH-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 (* 0.5 *LH-MISS-RADIUS*)))))

;; Draw the dashed marker for a declared straight stretch.
(defun lh:draw-wall-marker (p1 p2)
  (lh:ensure-dashed)
  (cal:ensure-layer *LH-WALL-LAYER* 8)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                  (cons 8 *LH-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbLine")
                  (cons 10 (list (car p1) (cadr p1) 0.0))
                  (cons 11 (list (car p2) (cadr p2) 0.0)))))

;; Bounding box of a point list, as (minx miny maxx maxy).
(defun lh:bbox (pts / x0 y0 x1 y1 q)
  (foreach q pts
    (if (null x0)
      (setq x0 (car q) x1 (car q) y0 (cadr q) y1 (cadr q))
      (setq x0 (min x0 (car q)) x1 (max x1 (car q))
            y0 (min y0 (cadr q)) y1 (max y1 (cadr q)))))
  (list x0 y0 x1 y1))

;; Draw "1", "2", "3" beside each candidate, in that candidate's own
;; colour, with that fit's numbers spelled out beside it.
(defun lh:label (num colour bb hgt row top bot / x y out e pr)
  (setq x   (+ (caddr bb) (* 0.6 hgt))
        y   (- (cadddr bb) (* row hgt 2.1))
        out nil)
  (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *LH-OUT-LAYER*) (cons 62 colour)
                          '(100 . "AcDbText")
                          (cons 10 (list x y 0.0))
                          (cons 40 hgt)
                          (cons 1 num))))
  (if e (setq out (cons e out)))
  (foreach pr (list (cons top (* 0.55 hgt)) (cons bot (* -0.05 hgt)))
    (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                            (cons 8 *LH-OUT-LAYER*) (cons 62 colour)
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
(defun lh:mark-unheld (bad segs bb hgt / q d s dmin keyed pair th x y
                                         line)
  (lh:purge-mine *LH-MISS-LAYER*)
  (if bad
    (progn
      (cal:ensure-layer *LH-MISS-LAYER* 1)
      (foreach q bad
        (lh:tag-mine
          (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                          (cons 8 *LH-MISS-LAYER*) '(100 . "AcDbCircle")
                          (cons 10 (list (car q) (cadr q) 0.0))
                          (cons 40 *LH-MISS-RADIUS*)))))
      (setq keyed nil)
      (foreach q bad
        (setq dmin nil)
        (foreach s segs
          (setq d (lh:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (setq keyed (cons (cons dmin q) keyed)))
      (setq keyed (reverse (lh:sort-car keyed))
            th    (* 0.5 hgt)
            x     (+ (caddr bb) (* 0.6 hgt))
            y     (cadddr bb))
      (lh:tag-mine
        (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                        (cons 8 *LH-MISS-LAYER*) '(100 . "AcDbText")
                        (cons 10 (list x y 0.0))
                        (cons 40 th)
                        (cons 1 (strcat "POINTS OFF THE LINE ("
                                        (itoa (length bad)) ")")))))
      (foreach pair keyed
        (setq y    (- y (* th 1.6))
              line (strcat "Pt." (lh:pt-name (cdr pair))
                           "   off by " (rtos (car pair) 4 4)))
        (lh:tag-mine
          (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *LH-MISS-LAYER*) '(100 . "AcDbText")
                          (cons 10 (list x y 0.0))
                          (cons 40 th)
                          (cons 1 line)))))))
  keyed)

;; Print the hit report for the fit the user kept.  ALLOW is the run's
;; miss allowance; CLOSED says which joint the chain has none of.
(defun lh:report (newsegs pts tol allow prior closed
                  / nl na hiton hitok miss q s s2 d dmin worst sum
                    sumo no nice onpt inner ns nj i te ts kk mk nk
                    hw hq lh-on-eps)
  ;; report against the same on-the-shape threshold the fit used
  (setq lh-on-eps (max *LH-ON-EPS* (* 0.25 tol)))
  (progn
      ;; -- segment mix, nice radii, arcs anchored on a point --------
      (setq nl 0 na 0 nice 0 onpt 0)
      (foreach s newsegs
        (if (< (abs (caddr s)) 1.0e-9)
          (setq nl (1+ nl))
          (progn
            (setq na (1+ na))
            (if (lh:nice-radius-p
                  (lh:bulge-radius (car s) (cadr s) (caddr s)))
              (setq nice (1+ nice)))
            (setq inner nil)
            (foreach q pts
              (if (and (> (cal:dist q (car s)) *LH-EXACT-EPS*)
                       (> (cal:dist q (cadr s)) *LH-EXACT-EPS*)
                       (<= (lh:seg-dist q s) (* 2.0 *LH-FIT-EPS*)))
                (setq inner T)))
            (if inner (setq onpt (1+ onpt))))))
      ;; -- how the scanned points landed ------------------------------
      (setq hiton 0 hitok 0 miss 0 worst 0.0 sum 0.0 sumo 0.0 no 0)
      (foreach q pts
        (setq dmin nil)
        (foreach s newsegs
          (setq d (lh:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (if (> dmin worst) (setq worst dmin))
        (setq sum (+ sum dmin))
        (if (> dmin (lh:oneps))
          (setq sumo (+ sumo dmin) no (1+ no)))
        (cond
          ((<= dmin (lh:oneps)) (setq hiton (1+ hiton)))
          ((<= dmin tol)        (setq hitok (1+ hitok)))
          (T                    (setq miss  (1+ miss)))))
      ;; -- smoothness: worst kink at a joint that is not a corner ----
      ;; an open chain has one joint fewer - its seam does not exist
      (setq ns (length newsegs)
            nj (if closed ns (1- ns))
            i 0 mk 0.0 nk 0)
      (while (< i nj)
        (setq s  (nth i newsegs)
              s2 (nth (rem (1+ i) ns) newsegs)
              te (+ (angle (car s) (cadr s)) (* 2.0 (atan (caddr s))))
              ts (- (angle (car s2) (cadr s2)) (* 2.0 (atan (caddr s2))))
              kk (abs (cal:signed-dang te ts)))
        (if (<= kk *LH-CORNER-ANG*)     ; bigger = an intentional corner
          (progn
            (if (> kk mk) (setq mk kk))
            (if (> kk (+ *LH-TANG-TOL* 1.0e-6)) (setq nk (1+ nk)))))
        (setq i (1+ i)))
      (princ (strcat "\nLHD: " (itoa ns) " segments ("
                     (itoa nl) " lines + " (itoa na)
                     " curves) written to layer " *LH-POOL-LAYER* "."
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
                     (rtos (* 180.0 (/ *LH-TANG-TOL* pi)) 2 1) ")"))
      (if (> nk 0)
        (princ (strcat "\n  (" (itoa nk)
                       " joint(s) needed more than the tangent limit)")))
      (if lh-walls
        (princ (strcat "\n  (" (itoa (length lh-walls))
                       " declared straight stretch(es) kept dead"
                       " straight)")))
      (if lh-holds
        (progn
          ;; every held point must sit ON the kept fit exactly; one
          ;; that does not means a declared stretch overruled it, and
          ;; that deserves a loud line of its own
          (setq hw 0.0)
          (foreach q lh-holds
            (setq dmin nil)
            (foreach s newsegs
              (setq d (lh:seg-dist q s))
              (if (or (null dmin) (< d dmin)) (setq dmin d)))
            (if (> dmin hw) (setq hw dmin hq q)))
          (if (<= hw *LH-EXACT-EPS*)
            (princ (strcat "\n  (" (itoa (length lh-holds))
                           " held point(s) all landed on the line"
                           " exactly)"))
            (princ (strcat "\n  WARNING: held Pt." (lh:pt-name hq)
                           " is off by " (rtos hw 2 4)
                           " - a declared stretch overruled it.")))))
      (if (and *LH-MAX-ARCS* (> na *LH-MAX-ARCS*))
        (princ (strcat "\n  (the curve cap is " (itoa *LH-MAX-ARCS*)
                       " but " (itoa na) " curves was the fewest"
                       " reachable)")))
      (if (> miss 0)
        (princ "\n  (points beyond tolerance: the curve cap overruled them)"))
      (if (lh:self-crosses newsegs closed)
        (princ (strcat "\n  WARNING: the result crosses itself - the"
                       " automatic point order is probably wrong."
                       "  Draw a rough lines-only sketch on layer "
                       *LH-POOL-LAYER*
                       " through the points in the right order and"
                       " select it too.")))
      (if (> prior 0)
        (princ (strcat "\n  (" (itoa prior)
                       " earlier fit(s) were already on layer "
                       *LH-OUT-LAYER* " - erase them if you only want"
                       " the new one)"))))
  (princ))

;; Build one candidate fit in MODE - "tight", "asked" or "few".  TOL
;; is always the distance the user typed; the mode sets what differs:
;; the fit tolerance, the miss allowance, and whether the curve cap
;; binds (only "asked" honours it).  CLOSED picks the engine.
(defun lh:build (tour tol allow mode closed / ftol left cap)
  (setq ftol (if (= mode "tight") (min tol *LH-TIGHT-TOL*) tol)
        left (cond ((= mode "tight") 0)
                   ((= mode "few")   1000000)
                   (T                allow))
        cap  (if (= mode "asked") *LH-MAX-ARCS*))
  (if closed
    (lh:coarse-loop tour ftol cap left (not (= mode "few")))
    (lh:coarse-path tour ftol cap left (not (= mode "few")))))

;; Deviation summary for SEGS against PTS: (worst avg avg-off).
(defun lh:devstats (segs pts on / w q s d dmin sum n sumo no)
  (setq w 0.0 sum 0.0 n 0 sumo 0.0 no 0)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (lh:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin w) (setq w dmin))
    (setq sum (+ sum dmin) n (1+ n))
    (if (> dmin on) (setq sumo (+ sumo dmin) no (1+ no))))
  (list w
        (if (> n 0) (/ sum n) 0.0)
        (if (> no 0) (/ sumo no) nil)))

;; A deviation for a table cell; "-" when there is nothing to average.
(defun lh:fmt-dev (x)
  (if x (rtos x 2 2) "-"))

;; ---- offer three fits and let the user pick ---------------------------
;; The two ends of the curve-versus-accuracy trade and the middle, all
;; drawn, each in its own colour with what it costs; the one the user
;; points at is kept.  ELEV is the height every candidate is drawn at.
(defun lh:compare (tour pts tol allow closed elev
                   / prior vars v e ent lab st onv segs verts bad allbad
                     first i pick idx keep ce bb hgt sel picked keyed pr
                     res)
  (setq prior (lh:prior-fits))
  (cal:ensure-layer *LH-OUT-LAYER* 3)
  (setq onv (max *LH-ON-EPS* (* 0.25 tol)))
  (setq bb  (lh:bbox pts)
        hgt (/ (max (- (caddr bb) (car bb))
                    (- (cadddr bb) (cadr bb)))
               20.0))
  (if (<= hgt 0.0) (setq hgt 1.0))
  (setq lh-phase "building the three candidate fits"
        vars     nil
        allbad   nil
        first    T
        i        1)
  (foreach v *LH-COMPARE*
    (setq segs  (lh:build tour tol allow (car v) closed)
          verts (mapcar '(lambda (s) (list (car s) (caddr s))) segs))
    ;; an open polyline's last segment needs its end point as one more
    ;; vertex; a closed one curves back to vertex 0 by itself
    (if (not closed)
      (setq verts (append verts (list (list (cadr (last segs)) 0.0)))))
    (setq ent  (lh:temp-add
                 (lh:make-pline verts *LH-OUT-LAYER* (cadr v)
                                closed elev))
          bad  (lh:unheld segs pts tol)
          st   (lh:devstats segs pts onv)
          lab  (lh:label
                 (itoa i) (cadr v) bb hgt i
                 (strcat (itoa (length segs)) " segs    "
                         (itoa (lh:arc-count segs)) " curves    "
                         (itoa (length bad)) " not held    "
                         (cadddr v))
                 (strcat "worst " (lh:fmt-dev (car st))
                         "    avg all " (lh:fmt-dev (cadr st))
                         "    avg off " (lh:fmt-dev (caddr st))))
          vars (cons (list segs ent bad v lab st) vars)
          i    (1+ i))
    (foreach e lab (lh:temp-add e))
    ;; only fits built to the user's distance vote on the "no fit
    ;; could hold these" note - the tight one threads everything
    (if (not (= (car v) "tight"))
      (if first
        (setq allbad bad first nil)
        (setq allbad (lh:isect allbad bad)))))
  (setq vars (reverse vars))
  (if (null (cadr (car vars)))
    (princ "\nLHD: could not draw the result - is the drawing read-only?")
    (progn
      (princ (strcat "\n\nThree candidate fits are now drawn on layer "
                     *LH-OUT-LAYER*
                     ",\neach numbered on screen in its own colour:\n"))
      (princ "\n   #  segs  curves  worst off  avg all  avg off  not held  ")
      (princ "\n   -  ----  ------  ---------  -------  -------  --------  ")
      (setq i 1)
      (foreach v vars
        (setq segs (car v) bad (caddr v) ce (cadddr v) st (nth 5 v))
        (princ (strcat "\n   " (itoa i) "  "
                       (cal:pad (itoa (length segs)) 6)
                       (cal:pad (itoa (lh:arc-count segs)) 8)
                       (cal:pad (lh:fmt-dev (car st)) 11)
                       (cal:pad (lh:fmt-dev (cadr st)) 9)
                       (cal:pad (lh:fmt-dev (caddr st)) 9)
                       (cal:pad (itoa (length bad)) 10)
                       (cadddr ce)))
        (setq i (1+ i)))
      (princ (strcat "\n\n  \"not held\" = points further than "
                     (rtos tol 2 3) " from that fit."
                     "\n  \"avg all\" averages every point; \"avg off\""
                     " averages only the points that are off the line"
                     "\n  (further than " (rtos onv 2 3) " from it)."))
      (princ (strcat "\n  All three are measured against the "
                     (rtos tol 2 3) " you typed, but only one is built"
                     " to it:"
                     "\n  the tight fit spends curves to drive the error"
                     " towards nothing (it"
                     "\n  ignores that distance"
                     (if *LH-MAX-ARCS* " and the curve cap" "")
                     "), the middle one is your settings exactly,"
                     "\n  and the few fit holds the same distance with"
                     " as few curves as it can."))
      (if allbad
        (princ (strcat "\n  NOTE: " (itoa (length allbad))
                       " point(s) could not be held by ANY fit built to"
                       " that distance - likely a mis-shot, a duplicate,"
                       " or a corner that needs more points around it."
                       "\n  (the tight fit threads every point it can"
                       " reach, so it does not get a vote here.)")))
      (setq lh-phase "waiting for the choice of fit")
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
           (lh:temp-drop (cadr v))
           (foreach e (nth 4 v) (lh:temp-drop e)))
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
             (lh:temp-drop (cadr keep))
             (lh:set-bylayer (cadr keep))))))
      (if keep
        (progn
          (setq keyed (lh:mark-unheld (caddr keep) (car keep) bb hgt))
          (lh:report (car keep) pts tol allow prior closed)
          (if keyed
            (progn
              (princ (strcat "\n  " (itoa (length keyed))
                             " point(s) beyond the distance are ringed"
                             " on layer " *LH-MISS-LAYER*
                             " and listed beside the shape, worst"
                             " first:"))
              (foreach pr keyed
                (princ (strcat "\n    Pt." (lh:pt-name (cdr pr))
                               "   off by " (rtos (car pr) 4 4))))))))))
  (princ)
  res)

;; ---- the numeric parameters ------------------------------------------

;; Maximum distance from a point; remembered in *LH-TOL*.
(defun lh:ask-tol (/ tol)
  (initget 6)
  (setq tol (getdist (strcat "\n  Maximum distance from a point <"
                             (rtos *LH-TOL* 2 3) ">: ")))
  (if (null tol) (setq tol *LH-TOL*))
  (if (> tol *LH-TOL-MAX*)
    (progn
      (princ (strcat "\n  (more than " (rtos *LH-TOL-MAX* 2 1)
                     " and the line is no longer a trace of the points"
                     " - using " (rtos *LH-TOL-MAX* 2 1) ")"))
      (setq tol *LH-TOL-MAX*)))
  (setq *LH-TOL* tol)
  tol)

;; Share of the points allowed off the line, as a fraction.
(defun lh:ask-pct (def / pct)
  (initget 4)
  (setq pct (getint (strcat "\n  Percent of points allowed off <"
                            (itoa (fix (+ 0.5 (* 100.0 def))))
                            ">: ")))
  (cond
    ((null pct) def)
    ((> pct 100)
     (princ "\n  (more than 100 makes no sense - using 100)")
     1.0)
    (T (/ pct 100.0))))

;; Curve cap; remembered in *LH-MAX-ARCS* (nil = no cap).
(defun lh:ask-cap (/ mx)
  (initget 4 "None")
  (setq mx (getint (strcat "\n  Maximum curves <"
                           (if *LH-MAX-ARCS* (itoa *LH-MAX-ARCS*) "None")
                           ">: ")))
  (cond ((null mx) nil)                            ; Enter: keep as-is
        ((eq 'STR (type mx)) (setq *LH-MAX-ARCS* nil))
        (T (setq *LH-MAX-ARCS* mx)))
  *LH-MAX-ARCS*)

;; Closed outline or open polyline; remembered in *LH-SHAPE*.
;; Returns T for closed.
(defun lh:ask-shape (/ ans)
  (initget "Closed Open")
  (setq ans (getkword (strcat
              "\n  Closed outline or Open polyline? [Closed/Open] <"
              *LH-SHAPE* ">: ")))
  (if ans (setq *LH-SHAPE* ans))
  (= *LH-SHAPE* "Closed"))

;; Which elevation the outline is drawn at; remembered in *LH-ZMODE*.
(defun lh:ask-zmode (/ ans)
  (initget "Top Bottom Average Zero")
  (setq ans (getkword (strcat
              "\n  Draw the outline at which height - [Top/Bottom/Average/Zero] <"
              *LH-ZMODE* ">: ")))
  (if ans (setq *LH-ZMODE* ans))
  *LH-ZMODE*)

;; The output height ZMODE picks from the elevation list ZS.
(defun lh:pick-elev (zmode zs / e z sum)
  (if (null zs)
    0.0
    (progn
      (setq e (car zs) sum 0.0)
      (foreach z zs
        (setq sum (+ sum z))
        (cond ((and (= zmode "Top")    (> z e)) (setq e z))
              ((and (= zmode "Bottom") (< z e)) (setq e z))))
      (cond ((= zmode "Average") (/ sum (length zs)))
            ((= zmode "Zero")    0.0)
            (T                   e)))))

;; The elevations carried by the points still in DPTS.
(defun lh:zs-of (dpts / out pr)
  (setq out nil)
  (foreach pr lh-zvals
    (if (lh:memb (car pr) dpts) (setq out (cons (cdr pr) out))))
  (reverse out))

;; ---- redo-time editing of walls and corners --------------------------

;; Erase this run's scaffolding markers of one entity type on the
;; marker layer, so the set can be redrawn to match an edited list.
(defun lh:sweep-marks (etype / keep en ed)
  (setq keep nil)
  (foreach en lh-temp
    (setq ed (if (and en (entget en)) (entget en)))
    (if (and ed
             (= etype (cdr (assoc 0 ed)))
             (= (strcase *LH-WALL-LAYER*)
                (strcase (cdr (assoc 8 ed)))))
      (entdel en)
      (setq keep (cons en keep))))
  (setq lh-temp (reverse keep)))

;; Snap a picked point onto the nearest scanned point.
(defun lh:snap-break (p dpts / q)
  (setq p (cal:2d p)
        q (lh:nearest p dpts))
  (if (null q)
    p
    (progn
      (if (> (cal:dist p q) (* 3.0 *LH-TOL*))
        (princ "\n  (picked well away from any scanned point - snapped to the nearest one)"))
      q)))

;; Add or remove declared straight stretches.
(defun lh:edit-walls (dpts / ans wp1 wp2 w1 w2 best bd w d)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Straight stretches (" (itoa (length lh-walls))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq lh-phase "picking a straight stretch"
             wp1      (getpoint "\n  First end of the straight stretch: ")
             wp2      (if wp1 (getpoint wp1 "\n  Second end: ")))
       (if wp2
         (progn
           (setq w1 (lh:snap-break wp1 dpts)
                 w2 (lh:snap-break wp2 dpts))
           (if (< (cal:dist w1 w2) *LH-EXACT-EPS*)
             (princ "\n  (both ends landed on the same scanned point - ignored)")
             (progn
               (setq lh-walls (append lh-walls (list (list w1 w2))))
               (lh:temp-add (lh:tag-mine (lh:draw-wall-marker w1 w2)))
               (princ (strcat "\n  stretch Pt." (lh:pt-name w1)
                              " - Pt." (lh:pt-name w2) " added")))))))
      ((= ans "Remove")
       (if (null lh-walls)
         (princ "\n  (no straight stretches to remove)")
         (progn
           (setq lh-phase "removing a straight stretch"
                 wp1      (getpoint "\n  Pick near the straight stretch to remove: "))
           (if wp1
             (progn
               (setq wp1 (cal:2d wp1) best nil bd nil)
               (foreach w lh-walls
                 (setq d (lh:seg-dist wp1 (list (car w) (cadr w) 0.0)))
                 (if (or (null bd) (< d bd)) (setq best w bd d)))
               (setq lh-walls (lh:remove best lh-walls))
               (lh:sweep-marks "LINE")
               (foreach w lh-walls
                 (lh:temp-add (lh:tag-mine
                   (lh:draw-wall-marker (car w) (cadr w)))))
               (princ (strcat "\n  stretch Pt." (lh:pt-name (car best))
                              " - Pt." (lh:pt-name (cadr best))
                              " removed")))))))
      (T (setq ans nil)))))

;; Add or remove declared sharp corners the same way.
(defun lh:edit-corners (dpts / ans wp1 w1 best bd w)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Sharp corners (" (itoa (length lh-corners))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq lh-phase "picking a sharp corner"
             wp1      (getpoint "\n  Corner point: "))
       (if wp1
         (progn
           (setq w1 (lh:snap-break wp1 dpts))
           (if (lh:memb w1 lh-corners)
             (princ "\n  (that corner is already declared)")
             (progn
               (setq lh-corners (append lh-corners (list w1)))
               (lh:temp-add (lh:tag-mine (lh:draw-corner-marker w1)))
               (princ (strcat "\n  corner Pt." (lh:pt-name w1)
                              " added")))))))
      ((= ans "Remove")
       (if (null lh-corners)
         (princ "\n  (no declared corners to remove)")
         (progn
           (setq lh-phase "removing a sharp corner"
                 wp1      (getpoint "\n  Pick the declared corner to remove: "))
           (if wp1
             (progn
               (setq wp1 (cal:2d wp1) best nil bd nil)
               (foreach w lh-corners
                 (if (or (null bd) (< (cal:dist wp1 w) bd))
                   (setq best w bd (cal:dist wp1 w))))
               (setq lh-corners (lh:remove best lh-corners))
               (lh:sweep-marks "CIRCLE")
               (foreach w lh-corners
                 (lh:temp-add (lh:tag-mine (lh:draw-corner-marker w))))
               (foreach w lh-holds
                 (lh:temp-add (lh:tag-mine (lh:draw-hold-marker w))))
               (princ (strcat "\n  corner Pt." (lh:pt-name best)
                              " removed")))))))
      (T (setq ans nil)))))

;; Add or remove HELD points the same way.
(defun lh:edit-holds (dpts / ans wp1 w1 best bd w)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Held points (" (itoa (length lh-holds))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq lh-phase "picking a held point"
             wp1      (getpoint "\n  Point to hold exactly: "))
       (if wp1
         (progn
           (setq w1 (lh:snap-break wp1 dpts))
           (if (lh:memb w1 lh-holds)
             (princ "\n  (that point is already held)")
             (progn
               (setq lh-holds (append lh-holds (list w1)))
               (lh:temp-add (lh:tag-mine (lh:draw-hold-marker w1)))
               (princ (strcat "\n  held Pt." (lh:pt-name w1)
                              " added")))))))
      ((= ans "Remove")
       (if (null lh-holds)
         (princ "\n  (no held points to remove)")
         (progn
           (setq lh-phase "removing a held point"
                 wp1      (getpoint "\n  Pick the held point to release: "))
           (if wp1
             (progn
               (setq wp1 (cal:2d wp1) best nil bd nil)
               (foreach w lh-holds
                 (if (or (null bd) (< (cal:dist wp1 w) bd))
                   (setq best w bd (cal:dist wp1 w))))
               (setq lh-holds (lh:remove best lh-holds))
               ;; redraw the rings to match what is left
               (lh:sweep-marks "CIRCLE")
               (foreach w lh-corners
                 (lh:temp-add (lh:tag-mine (lh:draw-corner-marker w))))
               (foreach w lh-holds
                 (lh:temp-add (lh:tag-mine (lh:draw-hold-marker w))))
               (princ (strcat "\n  held Pt." (lh:pt-name best)
                              " released")))))))
      (T (setq ans nil)))))

;; ---- the command -----------------------------------------------------
(defun c:LHD ( / tol ans go wp1 wp2 rawwalls rawcnrs rawholds w w1 w2
                   ss i en ed lay typ ext nunsup nocs closed
                   segs pts dpts allow tour ok stale npt chn sketch
                   texts tx q v zs elev e1 e2
                   again omits pts2 ent ring lh-omitted
                   lh-miss-pct lh-walls lh-corners lh-holds
                   lh-temp lh-ptnames
                   lh-zvals *error* lh-old-err lh-phase)
  ;; report which step failed if anything goes wrong, sweep away any
  ;; preview geometry drawn so far, then restore the old handler
  (setq lh-temp   nil
        lh-old-err *error*
        *error*
          (lambda (m)
            (if (and m
                     (/= m "Function cancelled")
                     (/= m "quit / exit abort")
                     (/= m "console break"))
              (princ (strcat "\nLHD stopped while "
                             (if lh-phase lh-phase "starting up")
                             " -- " m)))
            (lh:temp-clear)
            (setq *error* lh-old-err)
            (princ)))

  ;; sweep leftovers from a run that was interrupted before it could
  ;; tidy up after itself
  (setq stale (lh:purge-mine *LH-WALL-LAYER*))
  (if (> stale 0)
    (princ (strcat "\nLHD: cleared " (itoa stale)
                   " leftover marker(s) from layer " *LH-WALL-LAYER*
                   ".")))

  (princ "\n\nLHD - fit a top-down outline through laser-scanned points.")

  ;; -- step 1: how close must the line stay to the points? ----------
  (setq lh-phase "reading the tolerance")
  (princ "\n\n  Step 1 of 6 - how far may the fitted line sit from a scanned point?")
  (princ "\n  Type a distance in drawing units (1 = one inch, 2 at most), or")
  (princ "\n  pick two points in the drawing to measure one.")
  (princ "\n  Smaller = hugs the points.  Bigger = smoother, with fewer curves.")
  (setq tol (lh:ask-tol))

  ;; -- step 2: how many of the points may sit off the line? ---------
  (setq lh-phase "reading the miss percentage")
  (princ "\n\n  Step 2 of 6 - what percent of the points may sit OFF the line")
  (princ "\n  (off, but still within the distance above)?")
  (princ (strcat "\n  Press Enter for the standard "
                 (itoa (fix (+ 0.5 (* 100.0 *LH-MISS-PCT*))))
                 " percent."))
  (setq lh-miss-pct (lh:ask-pct *LH-MISS-PCT*))

  ;; -- step 3: optional cap on how many curves the result may use ---
  (setq lh-phase "reading the curve limit")
  (princ "\n\n  Step 3 of 6 - limit how many curves the result may use?")
  (princ "\n  Type a whole number, or None for no limit.")
  (lh:ask-cap)

  ;; -- step 4: closed outline or open polyline? ---------------------
  (setq lh-phase "reading the shape kind")
  (princ "\n\n  Step 4 of 6 - should the result close back on itself, or run open")
  (princ "\n  from one end of the scan to the other?")
  (setq closed (lh:ask-shape))

  ;; -- step 5: straight stretches and sharp corners -----------------
  ;; ABHD's steps 4 and 5 folded into one loop: a declared straight
  ;; stretch comes out as a dead-straight LINE between its two points;
  ;; a declared corner is exempt from the tangency rule.
  (setq lh-phase "asking about stretches, corners and held points"
        rawwalls nil
        rawcnrs  nil
        rawholds nil
        go       T)
  (princ "\n\n  Step 5 of 6 - any dead-straight stretches, sharp corners, or points")
  (princ "\n  to hold ABSOLUTELY?  A held point can never be fudged: the line")
  (princ "\n  passes through it exactly, in every candidate.  Each is picked by")
  (princ "\n  its point(s), snapping to the scanned points; dashed markers")
  (princ "\n  confirm them and clear themselves afterwards.")
  (while go
    (initget "Stretch Corner Hold Done")
    (setq ans (getkword
                "\n  Declare a [Stretch/Corner/Hold] or [Done]? <Done>: "))
    (cond
      ((= ans "Hold")
       (setq lh-phase "picking a held point"
             wp1      (getpoint "\n  Point to hold exactly: "))
       (if wp1
         (progn
           (setq wp1      (cal:2d wp1)
                 rawholds (cons wp1 rawholds))
           (lh:temp-add (lh:tag-mine (lh:draw-hold-marker wp1))))))
      ((= ans "Stretch")
       (setq lh-phase "picking a straight stretch"
             wp1      (getpoint "\n  First end of the straight stretch: ")
             wp2      (if wp1 (getpoint wp1 "\n  Second end: ")))
       (if wp2
         (progn
           (setq wp1 (cal:2d wp1) wp2 (cal:2d wp2))
           (lh:temp-add (lh:tag-mine (lh:draw-wall-marker wp1 wp2)))
           (setq rawwalls (cons (list wp1 wp2) rawwalls)))))
      ((= ans "Corner")
       (setq lh-phase "picking a sharp corner"
             wp1      (getpoint "\n  Corner point: "))
       (if wp1
         (progn
           (setq wp1     (cal:2d wp1)
                 rawcnrs (cons wp1 rawcnrs))
           (lh:temp-add (lh:tag-mine (lh:draw-corner-marker wp1))))))
      (T (setq go nil))))
  (setq rawwalls (reverse rawwalls)
        rawcnrs  (reverse rawcnrs)
        rawholds (reverse rawholds))
  (if (or rawwalls rawcnrs rawholds)
    (princ (strcat "\n  " (itoa (length rawwalls))
                   " stretch(es), " (itoa (length rawcnrs))
                   " corner(s) and " (itoa (length rawholds))
                   " held point(s) noted - the dashed markers on "
                   *LH-WALL-LAYER*
                   " clear themselves when the command finishes.")))

  ;; -- step 6: the selection ----------------------------------------
  (princ "\n\n  Step 6 of 6 - select the laser points (POINT entities on any layer,")
  (princ (strcat "\n  \"" *LH-POINT-BLOCK* "\" blocks, elevation text) and, if you have one, a rough"))
  (princ (strcat "\n  ordering sketch on layer " *LH-POOL-LAYER* "."))
  (princ "\n  Select objects: ")
  (setq lh-phase "waiting for the selection")
  ;; SPLINE and ELLIPSE are let in on purpose - not to fit them, but
  ;; so the classifier can name them in a useful message; TEXT is let
  ;; in so elevation labels can ride along with their points.
  (setq ss (ssget '((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE,TEXT"))))
  (if (null ss)
    (princ "\nNothing usable selected (points, and optionally a sketch on the POOL layer).")
    (progn
      ;; -- sort the selection into points, elevations and sketch -----
      (setq lh-phase "reading the selected entities")
      (setq segs nil pts nil texts nil i 0 nunsup 0 nocs 0
            npt 0 lh-ptnames nil lh-zvals nil)
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
                (= (strcase (cdr (assoc 2 ed))) (strcase *LH-POINT-BLOCK*)))
           (lh:add-point (cal:2d (cdr (assoc 10 ed)))
                         (cal:block-number en *LH-PT-TAG*)
                         (caddr (cdr (assoc 10 ed)))))
          ;; a plain POINT counts on ANY layer - laser exports land
          ;; wherever the converter put them; its Z is its elevation
          ((= typ "POINT")
           (lh:add-point (cal:2d (cdr (assoc 10 ed)))
                         nil
                         (caddr (cdr (assoc 10 ed)))))
          ;; a numeric TEXT may be an elevation label - set aside and
          ;; paired with its nearest point after the pass
          ((= typ "TEXT")
           (setq v (cond ((distof (cdr (assoc 1 ed)) 2))
                         ((distof (cdr (assoc 1 ed)) 4))))
           (if v
             (setq texts (cons (cons v (cal:2d (cdr (assoc 10 ed))))
                               texts))))
          ;; curve types we cannot read, on the sketch layer: count
          ;; them so the user gets told what to do
          ((and (= lay (strcase *LH-POOL-LAYER*))
                (member typ '("SPLINE" "ELLIPSE")))
           (setq nunsup (1+ nunsup)))
          ;; LHD's or ABHD's own output lives on the POOL layer too
          ;; (stamped) - never read it back as a sketch
          ((and (= lay (strcase *LH-POOL-LAYER*))
                (or (assoc -3 (entget en '("LHD")))
                    (assoc -3 (entget en '("ABHD")))))
           nil)
          ;; ordering sketch on the POOL layer
          ((= lay (strcase *LH-POOL-LAYER*))
           (setq segs (append segs (lh:ent-segs en))))
          ;; any other block dropped on the POINTS layer -> a point
          ((and (= typ "INSERT") (= lay (strcase *LH-POINT-LAYER*)))
           (lh:add-point (cal:2d (cdr (assoc 10 ed)))
                         (cal:block-number en *LH-PT-TAG*)
                         (caddr (cdr (assoc 10 ed)))))))
      (if (> nunsup 0)
        (princ (strcat "\nLHD: warning - " (itoa nunsup)
                       " SPLINE/ELLIPSE object(s) on layer "
                       *LH-POOL-LAYER*
                       " were ignored (only lines, arcs, circles and"
                       " polylines can be read - explode or convert"
                       " them first).")))
      (if (> nocs 0)
        (princ (strcat "\nLHD: warning - " (itoa nocs)
                       " selected object(s) are not drawn in the world"
                       " plane; the fit is flat (XY) and may be wrong."
                       "  Set UCS to World and flatten them first.")))
      (setq dpts  (if pts (cal:dedupe pts *LH-EXACT-EPS*))
            allow (cal:ceil (* (lh:misspct) (length dpts))))
      ;; pair the elevation labels with their points: nearest point
      ;; within *LH-TEXT-EPS*, and a point's own Z outranks a label
      (foreach tx texts
        (setq q (lh:nearest (cdr tx) dpts))
        (if (and q
                 (< (cal:dist q (cdr tx)) *LH-TEXT-EPS*)
                 (not (assoc q lh-zvals)))
          (setq lh-zvals (cons (cons q (car tx)) lh-zvals))))
      ;; snap the declared stretch ends and corners onto actual points
      (setq lh-walls nil)
      (foreach w rawwalls
        (setq w1 (lh:nearest (car w) dpts)
              w2 (lh:nearest (cadr w) dpts))
        (cond
          ((or (null w1) (null w2)) nil)
          ((< (cal:dist w1 w2) *LH-EXACT-EPS*)
           (princ "\n  (both ends of a declared stretch landed on the same scanned point - that stretch is ignored)"))
          (T
           (if (or (> (cal:dist (car w) w1) (* 3.0 tol))
                   (> (cal:dist (cadr w) w2) (* 3.0 tol)))
             (princ "\n  (a declared stretch end was picked well away from any scanned point - snapped to the nearest one)"))
           (setq lh-walls (cons (list w1 w2) lh-walls)))))
      (setq lh-walls (reverse lh-walls))
      (setq lh-corners nil)
      (foreach w rawcnrs
        (setq w1 (lh:nearest w dpts))
        (if w1
          (progn
            (if (> (cal:dist w w1) (* 3.0 tol))
              (princ "\n  (a declared corner was picked well away from any scanned point - snapped to the nearest one)"))
            (setq lh-corners (cons w1 lh-corners)))))
      (setq lh-corners (reverse lh-corners))
      ;; held points snap onto scanned points the same way; duplicates
      ;; collapse to one
      (setq lh-holds nil)
      (foreach w rawholds
        (setq w1 (lh:nearest w dpts))
        (if w1
          (progn
            (if (> (cal:dist w w1) (* 3.0 tol))
              (princ "\n  (a held point was picked well away from any scanned point - snapped to the nearest one)"))
            (if (not (lh:memb w1 lh-holds))
              (setq lh-holds (cons w1 lh-holds))))))
      (setq lh-holds (reverse lh-holds))
      (if (> (length dpts) 150)
        (princ (strcat "\nLHD: " (itoa (length dpts))
                       " points - ordering and fitting will take a"
                       " little while, please wait...")))
      (cond
        ((null pts)
         (princ (strcat "\nNo laser points found (looked for POINT"
                        " entities, \"" *LH-POINT-BLOCK*
                        "\" block insertions, and blocks on layer "
                        *LH-POINT-LAYER* ").")))
        ((< (length dpts) (if closed 3 2))
         (princ (strcat "\nAt least "
                        (if closed "3 distinct points are needed for a closed outline."
                                   "2 distinct points are needed for an open run."))))
        (T
         ;; -- order the points ---------------------------------------
         (setq ok T sketch nil e1 nil e2 nil)
         (if segs
           (progn
             (setq chn (lh:chain segs))
             (if chn
               (progn
                 (setq sketch (cdr chn))
                 (if (lh:has-arcs sketch)
                   (princ "\nPOOL sketch found - it only ORDERS the points; the shape comes from the points."))
                 (if (and closed (not (car chn)))
                   (princ "\n  (the sketch does not close - fine for ordering, the fit still closes)"))))))
         (cond
           (sketch
            (setq lh-phase "following the sketch order"
                  tour     (lh:loop-order sketch dpts)))
           (closed
            (princ "\nNo sketch selected - ordering the points into a loop automatically.")
            (setq lh-phase "ordering the points"
                  tour     (lh:order-points dpts)))
           (T
            (princ "\nNo sketch selected - the run's ends are the farthest-apart pair.")
            (princ "\n  (Redo lets you pick the two ends yourself.)")
            (setq lh-phase "ordering the points"
                  tour     (lh:order-points-open dpts nil nil))))
         ;; -- the output height, when the points carry elevations ----
         (setq zs (lh:zs-of dpts))
         (if zs
           (progn
             (setq lh-phase "reading the output height")
             (princ (strcat "\n\n  " (itoa (length zs))
                            " point(s) carry elevations.  The fit is a flat top-down"))
             (princ "\n  projection; the elevations only set the height the outline is")
             (princ "\n  drawn at - the highest point, the lowest, their average, or 0.")
             (setq elev (lh:pick-elev (lh:ask-zmode) zs)))
           (setq elev 0.0))
         (if ok
           (progn
             (setq again T)
             (while again
               (setq again nil)
               (if (eq 'REDO (lh:compare tour pts tol allow closed elev))
                 (progn
                   ;; -- redo: maybe omit points, then re-ask ---------
                   (setq lh-phase "picking points to omit"
                         omits    nil)
                   (princ "\n\nRedoing the fit.  Any points to leave out this time?")
                   (princ "\n  Pick each one (Enter for none) - mis-shots, duplicates, or")
                   (princ "\n  anything the line should not chase; each gets a dashed ring.")
                   (if lh-omitted
                     (princ (strcat "\n  " (itoa (length lh-omitted))
                                    " point(s) are already out -"
                                    " picking one of those puts it"
                                    " BACK IN.")))
                   (while (setq wp1 (getpoint
                                      "\n  Point to omit - or a ringed one to restore (Enter when done): "))
                     (setq wp1 (cal:2d wp1)
                           w1  (lh:nearest wp1 dpts)
                           w2  (lh:nearest wp1 (mapcar 'car lh-omitted)))
                     (cond
                       ((and w2 (or (null w1)
                                    (<= (cal:dist wp1 w2)
                                        (cal:dist wp1 w1))))
                        (setq ent        (assoc w2 lh-omitted)
                              pts        (append pts (cadr ent))
                              dpts       (cal:dedupe pts *LH-EXACT-EPS*)
                              lh-omitted (lh:remove ent lh-omitted)
                              omits      (lh:remove w2 omits))
                        (if (and (caddr ent) (entget (caddr ent)))
                          (progn
                            (lh:temp-drop (caddr ent))
                            (entdel (caddr ent))))
                        (princ (strcat "  - Pt." (lh:pt-name w2)
                                       " back in")))
                       (w1
                        (setq pts2 nil ent nil)
                        (foreach w pts
                          (if (< (cal:dist w w1) *LH-EXACT-EPS*)
                            (setq ent (cons w ent))
                            (setq pts2 (cons w pts2))))
                        (setq pts  (reverse pts2)
                              dpts (cal:dedupe pts *LH-EXACT-EPS*)
                              ring (lh:temp-add (lh:tag-mine
                                     (lh:draw-corner-marker w1)))
                              lh-omitted (cons (list w1 ent ring)
                                               lh-omitted)
                              omits      (cons w1 omits))
                        (princ (strcat "  - omitting Pt."
                                       (lh:pt-name w1))))))
                   (if omits
                     (progn
                       ;; declared stretches and corners anchored on
                       ;; an omitted point make no sense any more
                       (setq pts2 nil)
                       (foreach w lh-walls
                         (if (not (or (lh:memb (car w) omits)
                                      (lh:memb (cadr w) omits)))
                           (setq pts2 (cons w pts2))))
                       (if (< (length pts2) (length lh-walls))
                         (princ "\n  (a declared stretch lost an end and was dropped)"))
                       (setq lh-walls (reverse pts2)
                             pts2     nil)
                       (foreach w lh-corners
                         (if (not (lh:memb w omits))
                           (setq pts2 (cons w pts2))))
                       (setq lh-corners (reverse pts2)
                             pts2       nil)
                       ;; a held point that was just omitted is out of
                       ;; the fit entirely - nothing left to hold
                       (foreach w lh-holds
                         (if (not (lh:memb w omits))
                           (setq pts2 (cons w pts2))))
                       (if (< (length pts2) (length lh-holds))
                         (princ "\n  (an omitted point was held - its hold went with it)"))
                       (setq lh-holds (reverse pts2))))
                   (if lh-omitted
                     (princ (strcat "\n  " (itoa (length lh-omitted))
                                    " point(s) omitted in total - "
                                    (itoa (length dpts))
                                    " in the fit.")))
                   (if (< (length dpts) (if closed 3 2))
                     (princ "\nToo few points remain for a fit - nothing redone.")
                     (progn
                       ;; stretches and corners may change for the retry
                       (princ "\n\n  Straight stretches and sharp corners can change too -")
                       (princ "\n  Enter keeps each list as it is.")
                       (setq lh-phase "editing straight stretches")
                       (lh:edit-walls dpts)
                       (setq lh-phase "editing sharp corners")
                       (lh:edit-corners dpts)
                       (setq lh-phase "editing held points")
                       (lh:edit-holds dpts)
                       ;; an open run's ends can be picked by hand
                       (if (not closed)
                         (progn
                           (setq lh-phase "picking the run's ends")
                           (initget "Yes No")
                           (setq ans (getkword
                                       "\n  Pick the two END points of the open run? [Yes/No] <No>: "))
                           (if (= ans "Yes")
                             (progn
                               (setq wp1 (getpoint "\n  First end: ")
                                     wp2 (if wp1 (getpoint wp1 "\n  Second end: ")))
                               (if wp2
                                 (setq e1 (lh:snap-break wp1 dpts)
                                       e2 (lh:snap-break wp2 dpts)))))))
                       (princ "\n\n  New settings - Enter keeps each one as it is.")
                       (setq lh-phase "reading the tolerance"
                             tol      (lh:ask-tol))
                       (setq lh-phase "reading the miss percentage"
                             lh-miss-pct (lh:ask-pct lh-miss-pct))
                       (setq lh-phase "reading the curve limit")
                       (lh:ask-cap)
                       (setq allow (cal:ceil (* (lh:misspct)
                                               (length dpts))))
                       ;; forced ends that were omitted are forgotten
                       (if (and e1
                                (not (and (lh:memb e1 dpts)
                                          (lh:memb e2 dpts))))
                         (setq e1 nil e2 nil))
                       ;; the point order must forget the omitted ones
                       (setq lh-phase "ordering the points")
                       (cond
                         (sketch (setq tour (lh:loop-order sketch dpts)))
                         (closed (setq tour (lh:order-points dpts)))
                         (T      (setq tour (lh:order-points-open
                                              dpts e1 e2))))
                       ;; the output height follows the surviving points
                       (setq zs   (lh:zs-of dpts)
                             elev (lh:pick-elev *LH-ZMODE* zs))
                       (setq again T))))))))))))
  ;; sweep the dashed markers and any candidate the user did not keep
  (lh:temp-clear)
  (setq *error* lh-old-err)   ; restore the previous error handler
  (princ))

(princ (strcat "\nLHD " *lh-version*
               " loaded.  LHD fits a top-down outline (closed or open)"
               " through laser-scanned points."))
(princ)
