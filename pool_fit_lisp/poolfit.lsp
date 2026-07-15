;;; ===================================================================
;;; POOLFIT.LSP  --  Fit a pool perimeter through surveyed points
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Command:  POOLFIT
;;;
;;; The user window-selects an area containing:
;;;   * On layer "POOL"   : a closed perimeter drawn as ONE closed
;;;                         polyline OR an exploded set of LINEs/ARCs.
;;;   * On layer "POINTS" : POINT entities surveyed on the real pool
;;;                         edge.
;;;
;;; The command rebuilds the perimeter as a single closed LWPOLYLINE
;;; (lines + arcs only, no splines) on layer "POOL-FIT":
;;;   * Every polyline vertex is snapped to the nearest surveyed point
;;;     within the tolerance (default 1 unit = 1 inch), so corners land
;;;     exactly on points whenever one is close enough.
;;;   * Every curved (arc/bulge) segment is re-fitted so that the arc
;;;     passes through the surveyed points lying along it - the new
;;;     bulge is the average of the exact 3-point arcs through the two
;;;     (snapped) endpoints and each nearby survey point.
;;;   * Straight segments the user drew are trusted and kept straight
;;;     (only their endpoints snap to points); where the user found a
;;;     straight wall, the result has a straight wall.
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
(setq *PF-OUT-LAYER*    "POOL-FIT") ; layer the fitted polyline goes on
(setq *PF-EXACT-EPS*    0.001)      ; "exactly on" threshold (units)
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
            ;; sagitta = (chord/2)*bulge, to the left of p1->p2
            apex (pf:add (pf:mid p1 p2)
                         (pf:scl (pf:perp dir) (* 0.5 ch b)))
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

;; ---- entity -> segment extraction ----------------------------------
;; A segment is (startPt endPt bulge), 2D points.

(defun pf:lw-segs (ed / pts bls last item pt segs n closed)
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
         (princ "\nPOOLFIT: gap in the POOL perimeter - could not close the loop.")
         nil)
        ((>= (pf:dist end start) *PF-CHAIN-FUZZ*)
         (princ "\nPOOLFIT: the POOL perimeter does not close.")
         nil)
        (T
         (if segs
           (princ (strcat "\nPOOLFIT: warning - "
                          (itoa (length segs))
                          " POOL segment(s) not part of the closed loop were ignored.")))
         (reverse loop))))))

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

;; ---- the command -----------------------------------------------------
(defun c:POOLFIT ( / tol ss i en ed lay typ segs pts loop n verts used
                    v vp best bd d q p1 p2 b cands blist sum newb
                    newsegs hitex hitok miss dmin s)
  ;; tolerance (drawing units; 1 = 1 inch in an inch drawing)
  (setq tol (getdist (strcat "\nTolerance <" (rtos *PF-TOL* 2 3) ">: ")))
  (if tol (setq *PF-TOL* tol) (setq tol *PF-TOL*))

  (princ "\nSelect the pool perimeter (POOL layer) and its points (POINTS layer): ")
  (setq ss (ssget))
  (if (null ss)
    (princ "\nNothing selected.")
    (progn
      ;; -- sort the selection into perimeter segments and points -----
      (setq segs nil pts nil i 0)
      (while (< i (sslength ss))
        (setq en  (ssname ss i)
              ed  (entget en)
              lay (strcase (cdr (assoc 8 ed)))
              typ (cdr (assoc 0 ed))
              i   (1+ i))
        (cond
          ((= lay (strcase *PF-POOL-LAYER*))
           (setq segs (append segs (pf:ent-segs en))))
          ((and (= lay (strcase *PF-POINT-LAYER*)) (= typ "POINT"))
           (setq pts (cons (pf:2d (cdr (assoc 10 ed))) pts)))))
      (cond
        ((null segs)
         (princ (strcat "\nNo perimeter found on layer " *PF-POOL-LAYER* ".")))
        ((null pts)
         (princ (strcat "\nNo POINT entities found on layer " *PF-POINT-LAYER* ".")))
        ((null (setq loop (pf:chain segs))) nil)
        (T
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
         (setq newsegs nil n 0)
         (repeat (length loop)
           (setq s  (nth n loop)
                 p1 (nth n verts)
                 p2 (nth (rem (1+ n) (length verts)) verts)
                 b  (caddr s))
           (if (>= (abs b) 1.0e-9)
             (progn
               ;; survey points lying near the ORIGINAL arc, excluding
               ;; the ones already consumed as vertices
               (setq cands nil)
               (foreach q pts
                 (if (and (not (member q used))
                          (<= (pf:seg-dist q s) tol)
                          (> (pf:dist q p1) *PF-EXACT-EPS*)
                          (> (pf:dist q p2) *PF-EXACT-EPS*))
                   (setq cands (cons q cands))))
               ;; average the exact 3-point bulges through each point
               (if cands
                 (progn
                   (setq blist (mapcar '(lambda (q) (pf:bulge-3pt p1 q p2))
                                       cands)
                         sum 0.0)
                   (foreach newb blist (setq sum (+ sum newb)))
                   (setq b (/ sum (length blist)))))))
           (setq newsegs (cons (list p1 p2 b) newsegs)
                 n (1+ n)))
         (setq newsegs (reverse newsegs))
         ;; -- 3. draw the fitted polyline -----------------------------
         (pf:ensure-layer *PF-OUT-LAYER*)
         (pf:make-pline
           (mapcar '(lambda (s) (list (car s) (caddr s))) newsegs)
           *PF-OUT-LAYER*)
         ;; -- 4. hit report -------------------------------------------
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
         (princ (strcat "\nPOOLFIT: " (itoa (length newsegs))
                        " segments written to layer " *PF-OUT-LAYER* "."
                        "\n  Points ON the perimeter:      " (itoa hitex)
                        "\n  Points within tolerance:      " (itoa hitok)
                        "\n  Points beyond tolerance:      " (itoa miss)))
         (if (> miss 0)
           (princ "\n  (points beyond tolerance were left where the drawn shape disagrees with them)"))))))
  (princ))

(princ "\nPOOLFIT loaded.  Type POOLFIT to fit the pool perimeter through its points.")
(princ)
