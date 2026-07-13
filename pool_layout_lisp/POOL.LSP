;;; ====================================================================
;;;  POOL.LSP -- Swimming-pool as-built layout tool
;;;
;;;  Command:  POOL
;;;
;;;  Draws a pool plan (Rectangle, Oval or Grecian) from field
;;;  measurements:
;;;
;;;    * A gray nominal "guide" pool appears as soon as the shape is
;;;      chosen; while each measurement is prompted for, the matching
;;;      element of the guide turns red so you can see which dimension
;;;      is being asked for.  Once every dimension is in, the guide
;;;      deletes itself and is replaced by the true out-of-square pool.
;;;    * The full pool PERIMETER on layer POOL -- around the whole
;;;      shape including the Grecian corner cuts and oval end arcs
;;;      (drawn as individual lines/arcs, i.e. an exploded polyline).
;;;      Field measurements carry human error, so side lengths may be
;;;      held within +/-1" and cross dimensions within +/-2" of the
;;;      given values.
;;;    * Reference lines that are not part of the perimeter (the body
;;;      end lines under oval/Grecian ends, the oval radius
;;;      construction lines) go on POOL-NOTES with a DASHED linetype
;;;      (when acad.lin / acadiso.lin can be found).
;;;    * An exact as-measured check figure built from two triangles
;;;      (each triangle uses one side, one end and the shared A-C
;;;      cross dimension -- held EXACTLY, no tolerance) on its own
;;;      layer POOL-TRIANGLES.
;;;    * Aligned dimensions for all sides and cross dims on layer
;;;      DIMENSION.  The two cross dims are drawn in the "CROSS
;;;      DIMENSION" dimension style when the drawing has one.
;;;    * A target / actual / delta report table to the right of the
;;;      drawing on POOL-NOTES.  When the cross dimensions cannot be
;;;      met within tolerance the sides are held true, the cross dims
;;;      get as close as possible, and "CROSS DIMS FAILED" is written
;;;      under the table.
;;;
;;;  Corner naming (plan view):   D ---------- C
;;;                               |            |     cross dims:
;;;                               |            |     A-C and B-D
;;;                               A ---------- B
;;;
;;;  Oval:    adds a radius line perpendicular to each end and a
;;;           three-point arc (end corner -> radius tip -> other end
;;;           corner) on both ends, plus a total-length check.
;;;  Grecian: adds 45-degree corner diagonals on both ends; the
;;;           diagonal angle is adjusted so the given end width fits
;;;           between the diagonal end points, and if it cannot fit
;;;           the diagonal lengths are adjusted in 1/8" increments up
;;;           to +/-1/2" of the given lengths.
;;;
;;;  Drawing units are assumed to be INCHES (tolerances: 1" sides,
;;;  2" cross dims, 1/2" max Grecian diagonal adjustment in 1/8"
;;;  steps).  Values may be typed in the current drawing units, e.g.
;;;  20'6-1/2" when units are set to Architectural.
;;;
;;;  Written in plain AutoLISP (entmake + classic commands, no
;;;  ActiveX/VLA), so it loads in AutoCAD 2018 as well as older
;;;  releases.
;;; ====================================================================

;;; -------------------- adjustable constants --------------------------

(setq pool:*side-tol*  1.0)     ; side length tolerance (drawing units)
(setq pool:*cross-tol* 2.0)     ; cross dimension tolerance
(setq pool:*grec-step* 0.125)   ; Grecian diagonal adjustment increment
(setq pool:*grec-max*  4)       ; max increments each way (4 * 1/8 = 1/2)
(setq pool:*base*      (list 0.0 0.0))
(setq pool:*dashlt*    "CONTINUOUS")  ; resolved to DASHED per run
(setq pool:*lts*       1.0)           ; linetype scale for dashed refs

;;; -------------------- small vector helpers --------------------------

(defun pool:d2r (a) (* pi (/ a 180.0)))

(defun pool:v+ (p q) (list (+ (car p) (car q)) (+ (cadr p) (cadr q))))

(defun pool:v- (p q) (list (- (car p) (car q)) (- (cadr p) (cadr q))))

(defun pool:v* (p s) (list (* (car p) s) (* (cadr p) s)))

(defun pool:dot (p q) (+ (* (car p) (car q)) (* (cadr p) (cadr q))))

(defun pool:perp (p) (list (- (cadr p)) (car p)))

(defun pool:mid (p q) (pool:v* (pool:v+ p q) 0.5))

(defun pool:unit (p / d)
  (setq d (sqrt (pool:dot p p)))
  (if (> d 1.0e-12) (pool:v* p (/ 1.0 d)) (list 0.0 0.0)))

;; local 2D point -> world 3D point (applies the insertion base)
(defun pool:wp (p)
  (list (+ (car p) (car pool:*base*))
        (+ (cadr p) (cadr pool:*base*))
        0.0))

;;; -------------------- geometry ---------------------------------------

;; Intersection of circle (c1 r1) with circle (c2 r2).
;; side = 1.0 -> point on the left of the c1->c2 direction, -1.0 -> right.
;; Returns a 2D point or nil when the circles do not intersect.
(defun pool:circint (c1 r1 c2 r2 side / d ux uy a h2 h bx by)
  (setq d (distance c1 c2))
  (if (> d 1.0e-9)
      (progn
        (setq ux (/ (- (car c2) (car c1)) d)
              uy (/ (- (cadr c2) (cadr c1)) d)
              a  (/ (+ (* d d) (* r1 r1) (- (* r2 r2))) (* 2.0 d))
              h2 (- (* r1 r1) (* a a)))
        (if (> h2 -1.0e-6)
            (progn
              (setq h  (sqrt (max h2 0.0))
                    bx (+ (car c1) (* a ux))
                    by (+ (cadr c1) (* a uy)))
              (list (+ bx (* side h (- uy)))
                    (+ by (* side h ux))))))))

;; Circumcenter of three points, or nil when collinear.
(defun pool:circum (p1 p2 p3 / ax ay bx by cx cy dd)
  (setq ax (car p1) ay (cadr p1)
        bx (car p2) by (cadr p2)
        cx (car p3) cy (cadr p3)
        dd (* 2.0 (+ (* ax (- by cy)) (* bx (- cy ay)) (* cx (- ay by)))))
  (if (> (abs dd) 1.0e-9)
      (list (/ (+ (* (+ (* ax ax) (* ay ay)) (- by cy))
                  (* (+ (* bx bx) (* by by)) (- cy ay))
                  (* (+ (* cx cx) (* cy cy)) (- ay by)))
               dd)
            (/ (+ (* (+ (* ax ax) (* ay ay)) (- cx bx))
                  (* (+ (* bx bx) (* by by)) (- ax cx))
                  (* (+ (* cx cx) (* cy cy)) (- bx ax)))
               dd))))

(defun pool:npos (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;;; -------------------- entity makers ----------------------------------

(defun pool:layer (name color)
  (if (not (tblsearch "LAYER" name))
      (entmake (list '(0 . "LAYER")
                     '(100 . "AcDbSymbolTableRecord")
                     '(100 . "AcDbLayerTableRecord")
                     (cons 2 name)
                     '(70 . 0)
                     (cons 62 color)
                     '(6 . "Continuous"))))
  name)

(defun pool:line (p1 p2 lay)
  (entmake (list '(0 . "LINE")
                 (cons 8 lay)
                 (cons 10 (pool:wp p1))
                 (cons 11 (pool:wp p2)))))

;; Make sure a linetype is loaded (from acad.lin / acadiso.lin).
;; Returns the linetype name when available, else "CONTINUOUS".
(defun pool:ltload (name / f fd)
  (if (not (tblsearch "LTYPE" name))
      (progn
        (setq f (findfile "acad.lin"))
        (if (null f) (setq f (findfile "acadiso.lin")))
        (if f
            (progn
              (setq fd (getvar "FILEDIA"))
              (setvar "FILEDIA" 0)
              (command "_.-LINETYPE" "_Load" name f "")
              (setvar "FILEDIA" fd)))))
  (if (tblsearch "LTYPE" name) name "CONTINUOUS"))

;; Dashed reference line on POOL-NOTES (falls back to continuous when
;; no DASHED linetype could be loaded).
(defun pool:lined (p1 p2)
  (entmake (append (list '(0 . "LINE")
                         (cons 8 "POOL-NOTES")
                         (cons 10 (pool:wp p1))
                         (cons 11 (pool:wp p2)))
                   (if (/= pool:*dashlt* "CONTINUOUS")
                       (list (cons 6 pool:*dashlt*)
                             (cons 48 pool:*lts*))))))

(defun pool:text (pt h str lay)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 10 (pool:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

(defun pool:textc (pt h str lay col)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 62 col)
                 (cons 10 (pool:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

;; Three-point arc through p1 -> p2 -> p3 (falls back to a line when
;; the points are collinear).
(defun pool:arc3p (p1 p2 p3 lay / o r a1 a2 a3 da2 da3 s e)
  (setq o (pool:circum p1 p2 p3))
  (if o
      (progn
        (setq r  (distance o p1)
              a1 (angle o p1)
              a2 (angle o p2)
              a3 (angle o p3)
              da2 (pool:npos (- a2 a1))
              da3 (pool:npos (- a3 a1)))
        (if (< da2 da3)
            (setq s a1 e a3)
            (setq s a3 e a1))
        (entmake (list '(0 . "ARC")
                       (cons 8 lay)
                       (cons 10 (pool:wp o))
                       (cons 40 r)
                       (cons 50 s)
                       (cons 51 e))))
      (pool:line p1 p3 lay)))

(defun pool:dimalg (p1 p2 pt)
  (command "_.DIMALIGNED" (pool:wp p1) (pool:wp p2) (pool:wp pt)))

;; Point offset outward (away from cen) from the midpoint of p->q.
;; A negative dist offsets inward instead.
(defun pool:outoff (p q cen dist / m n)
  (setq m (pool:mid p q)
        n (pool:unit (pool:perp (pool:v- q p))))
  (if (< (pool:dot (pool:v- m cen) n) 0.0)
      (setq n (pool:v* n -1.0)))
  (pool:v+ m (pool:v* n dist)))

;;; -------------------- user input -------------------------------------

(defun pool:ask (msg)
  (initget 7)                           ; no null, no zero, no negative
  (getdist (strcat "\n" msg ": ")))

;;; -------------------- guide preview ----------------------------------
;;; A gray nominal pool of the chosen shape is drawn as soon as the
;;; shape is picked.  While each measurement is prompted for, the
;;; matching element of the guide turns red so the user can see exactly
;;; which dimension is being asked for.  Once all inputs are in, the
;;; guide deletes itself and is replaced by the true out-of-square pool.

(setq pool:*pv-col* 8)                  ; guide color (gray)
(setq pool:*hi-col* 1)                  ; highlight color (red)

;; Override (or set) the color of an entity, refresh it, return it.
(defun pool:setcol (e col / ed old)
  (if (and e (setq ed (entget e)))
      (progn
        (setq old (assoc 62 ed))
        (if old
            (setq ed (subst (cons 62 col) old ed))
            (setq ed (append ed (list (cons 62 col)))))
        (entmod ed)
        (entupd e)))
  e)

(defun pool:pvline (p1 p2)
  (pool:line p1 p2 "POOL-NOTES")
  (pool:setcol (entlast) pool:*pv-col*))

;; Ask for a distance while the matching guide elements glow red.
(defun pool:askh (msg ents / v)
  (foreach e ents (pool:setcol e pool:*hi-col*))
  (setq v (pool:ask msg))
  (foreach e ents (pool:setcol e pool:*pv-col*))
  v)

;; Draw the nominal guide pool for the chosen shape (fixed 360 x 180
;; body).  Returns an assoc list mapping each input key to the list of
;; guide entities to highlight, plus an ALL entry with every guide
;; entity for later deletion.
(defun pool:preview (ptype / pw ph a b c d cen pr all pv
                             eab ebc ecd eda eac ebd
                             midl midr tipl tipr elrad errad elarc erarc etot
                             lp1 lp2 rp1 rp2 elt elb elw ert erb erw)
  (setq pw 360.0 ph 180.0
        a (list 0.0 0.0) b (list pw 0.0) c (list pw ph) d (list 0.0 ph)
        cen (list (* 0.5 pw) (* 0.5 ph))
        eab (pool:pvline a b)
        ebc (pool:pvline b c)
        ecd (pool:pvline d c)
        eda (pool:pvline d a)
        eac (pool:pvline a c)
        ebd (pool:pvline b d)
        all (list eab ebc ecd eda eac ebd)
        pv (list (cons 'ab (list eab)) (cons 'bc (list ebc))
                 (cons 'dc (list ecd)) (cons 'da (list eda))
                 (cons 'ac (list eac)) (cons 'bd (list ebd))))
  (foreach pr (list (list a "A") (list b "B") (list c "C") (list d "D"))
    (pool:text (pool:v+ (car pr)
                        (pool:v* (pool:unit (pool:v- (car pr) cen)) 14.0))
               10.0 (cadr pr) "POOL-NOTES")
    (setq all (cons (pool:setcol (entlast) pool:*pv-col*) all)))
  (cond
    ((= ptype "Oval")
     (setq midl (list 0.0 (* 0.5 ph)) tipl (list -80.0 (* 0.5 ph))
           midr (list pw (* 0.5 ph)) tipr (list (+ pw 80.0) (* 0.5 ph))
           elrad (pool:pvline midl tipl)
           errad (pool:pvline midr tipr))
     (pool:arc3p a tipl d "POOL-NOTES")
     (setq elarc (pool:setcol (entlast) pool:*pv-col*))
     (pool:arc3p b tipr c "POOL-NOTES")
     (setq erarc (pool:setcol (entlast) pool:*pv-col*))
     (setq etot (pool:pvline tipl tipr)
           all (append all (list elrad errad elarc erarc etot))
           pv (append pv (list (cons 'lrad (list elrad elarc))
                               (cons 'rrad (list errad erarc))
                               (cons 'tot (list etot))))))
    ((= ptype "Grecian")
     (setq lp1 (list -42.0 (- ph 42.0)) lp2 (list -42.0 42.0)
           rp1 (list (+ pw 42.0) (- ph 42.0)) rp2 (list (+ pw 42.0) 42.0)
           elt (pool:pvline d lp1)
           elb (pool:pvline a lp2)
           elw (pool:pvline lp1 lp2)
           ert (pool:pvline c rp1)
           erb (pool:pvline b rp2)
           erw (pool:pvline rp1 rp2)
           all (append all (list elt elb elw ert erb erw))
           pv (append pv (list (cons 'lt (list elt)) (cons 'lb (list elb))
                               (cons 'lw (list elw)) (cons 'rt (list ert))
                               (cons 'rb (list erb)) (cons 'rw (list erw)))))))
  (cons (cons 'all all) pv))

;;; -------------------- quadrilateral fitting --------------------------

;; Measured lengths of quad (A B C D):
;; (bottom top left right crossAC crossBD)
(defun pool:quadmeas (q / a b c d)
  (setq a (car q) b (cadr q) c (caddr q) d (cadddr q))
  (list (distance a b) (distance d c) (distance a d) (distance b c)
        (distance a c) (distance b d)))

(defun pool:diagerr (q dac dbd / e1 e2)
  (setq e1 (- (distance (car q) (caddr q)) dac)
        e2 (- (distance (cadr q) (cadddr q)) dbd))
  (+ (* e1 e1) (* e2 e2)))

;; Quad with all four sides EXACT, parameterised by the interior angle
;; at corner A (four-bar linkage).  Returns (A B C D) or nil.
(defun pool:4bar (bo tp le ri alfa / a b d c1 c2)
  (setq a (list 0.0 0.0)
        b (list bo 0.0)
        d (list (* le (cos alfa)) (* le (sin alfa)))
        c1 (pool:circint b ri d tp 1.0)
        c2 (pool:circint b ri d tp -1.0))
  (cond
    ((and c1 c2)
     (list a b (if (> (distance a c1) (distance a c2)) c1 c2) d))
    (c1 (list a b c1 d))
    (c2 (list a b c2 d))
    (t nil)))

;; Scan the angle at A over [a0 a1], returning (quad alfa) with the
;; smallest cross-dim error, or nil.
(defun pool:scanalfa (bo tp le ri dac dbd a0 a1 step / alfa q e best bestq)
  (setq alfa a0 best 1.0e30 bestq nil)
  (while (<= alfa a1)
    (setq q (pool:4bar bo tp le ri alfa))
    (if q
        (progn
          (setq e (pool:diagerr q dac dbd))
          (if (< e best) (setq best e bestq (list q alfa)))))
    (setq alfa (+ alfa step)))
  bestq)

;; Best quad with sides held EXACTLY true, cross dims as close as
;; possible.  Coarse scan then fine refine.  Returns quad or nil.
(defun pool:fitsides (bo tp le ri dac dbd / r1 r2 alfa)
  (setq r1 (pool:scanalfa bo tp le ri dac dbd
                          (pool:d2r 15.0) (pool:d2r 165.0) (pool:d2r 0.25)))
  (if r1
      (progn
        (setq alfa (cadr r1)
              r2 (pool:scanalfa bo tp le ri dac dbd
                                (- alfa (pool:d2r 0.3)) (+ alfa (pool:d2r 0.3))
                                (pool:d2r 0.005)))
        (car (if r2 r2 r1)))))

(defun pool:setnth (lst i val / k out)
  (setq k 0 out nil)
  (foreach x lst
    (setq out (cons (if (= k i) val x) out)
          k (1+ k)))
  (reverse out))

;; One distance-constraint relaxation step: pull points i and j of pts
;; so their distance moves into [lo hi] (lo = hi -> exact pull).
(defun pool:relax1 (pts i j lo hi w / p q d des err ux uy e2)
  (setq p (nth i pts)
        q (nth j pts)
        d (distance p q))
  (if (> d 1.0e-9)
      (progn
        (setq des (min (max d lo) hi)
              err (- d des))
        (if (/= err 0.0)
            (progn
              (setq ux (/ (- (car q) (car p)) d)
                    uy (/ (- (cadr q) (cadr p)) d)
                    e2 (* 0.5 w err))
              (setq pts (pool:setnth pts i
                          (list (+ (car p) (* e2 ux)) (+ (cadr p) (* e2 uy)))))
              (setq pts (pool:setnth pts j
                          (list (- (car q) (* e2 ux)) (- (cadr q) (* e2 uy)))))))))
  pts)

(defun pool:rot (p ang)
  (list (- (* (car p) (cos ang)) (* (cadr p) (sin ang)))
        (+ (* (car p) (sin ang)) (* (cadr p) (cos ang)))))

;; Re-gauge a quad: A at the origin, B on the +X axis, D above.
(defun pool:normquad (pts / a ang)
  (setq a (car pts)
        pts (mapcar '(lambda (p) (pool:v- p a)) pts)
        ang (- (angle (list 0.0 0.0) (cadr pts)))
        pts (mapcar '(lambda (p) (pool:rot p ang)) pts))
  (if (< (cadr (cadddr pts)) 0.0)
      (setq pts (mapcar '(lambda (p) (list (car p) (- (cadr p)))) pts)))
  pts)

;; Iterative relaxation: sides banded to +/-stol, cross dims pulled to
;; their exact targets.
(defun pool:relaxquad (pts bo tp le ri dac dbd stol niter / conlst k c)
  ;; cross dims pull first, side bands clamp last so each sweep ends
  ;; with the sides back inside their +/-stol band
  (setq conlst (list (list 0 2 dac dac 0.5)
                     (list 1 3 dbd dbd 0.5)
                     (list 0 1 (- bo stol) (+ bo stol) 1.0)
                     (list 3 2 (- tp stol) (+ tp stol) 1.0)
                     (list 0 3 (- le stol) (+ le stol) 1.0)
                     (list 1 2 (- ri stol) (+ ri stol) 1.0))
        k 0)
  (while (< k niter)
    (foreach c conlst
      (setq pts (pool:relax1 pts (car c) (cadr c) (caddr c) (cadddr c) (nth 4 c))))
    (setq k (1+ k)))
  (pool:normquad pts))

;; Fit the parametric quad.  Returns (quad failedflag):
;;  1. hold sides exact, pick the angle whose cross dims are closest;
;;     if both cross dims land inside xtol -> done, no failure.
;;  2. otherwise let the sides flex inside +/-stol and pull the cross
;;     dims to their targets; if everything then fits -> done.
;;  3. otherwise: sides held true (result of step 1), cross dims as
;;     close as possible, failure flag set.
(defun pool:fitquad (bo tp le ri dac dbd stol xtol / q1 m1 q2 m2 sok xok)
  (setq q1 (pool:fitsides bo tp le ri dac dbd))
  (if (null q1)                         ; degenerate input fallback
      (setq q1 (list (list 0.0 0.0) (list bo 0.0)
                     (list bo (* 0.5 (+ le ri))) (list 0.0 le))))
  (setq m1 (pool:quadmeas q1))
  (if (and (<= (abs (- (nth 4 m1) dac)) xtol)
           (<= (abs (- (nth 5 m1) dbd)) xtol))
      (list q1 nil)
      (progn
        (setq q2 (pool:relaxquad q1 bo tp le ri dac dbd stol 2000)
              m2 (pool:quadmeas q2)
              sok (and (<= (abs (- (car m2) bo)) (+ stol 0.05))
                       (<= (abs (- (cadr m2) tp)) (+ stol 0.05))
                       (<= (abs (- (caddr m2) le)) (+ stol 0.05))
                       (<= (abs (- (cadddr m2) ri)) (+ stol 0.05)))
              xok (and (<= (abs (- (nth 4 m2) dac)) (+ xtol 0.05))
                       (<= (abs (- (nth 5 m2) dbd)) (+ xtol 0.05))))
        (if (and sok xok)
            (list q2 nil)
            (list q1 t)))))

;; Exact two-triangle check figure:
;;   triangle 1 = A B C  (bottom side, right end, cross A-C)
;;   triangle 2 = A C D  (top side, left end, shared cross A-C)
;; All lengths held exactly.  Returns (A B C D) or nil when the given
;; lengths cannot form the triangles.
(defun pool:triquad (bo tp le ri dac / a b c d)
  (setq a (list 0.0 0.0)
        b (list bo 0.0)
        c (pool:circint a dac b ri 1.0))
  (if c (setq d (pool:circint a le c tp 1.0)))
  (if (and c d) (list a b c d)))

;;; -------------------- grecian ends -----------------------------------

;; Distance between the two diagonal end points for end width w,
;; diagonal lengths lt/lb and diagonal angle th (from the end line's
;; outward normal).
(defun pool:grecf (w lt lb th)
  (sqrt (+ (expt (- w (* (+ lt lb) (sin th))) 2)
           (expt (* (- lt lb) (cos th)) 2))))

;; Best diagonal angle for target end width e: scan 1..89 degrees.
;; Returns (theta err).
(defun pool:grecth (w lt lb e / th best berr dd)
  (setq th 0.0175 best 0.7854 berr 1.0e30)
  (while (< th 1.5533)
    (setq dd (abs (- (pool:grecf w lt lb th) e)))
    (if (< dd berr) (setq berr dd best th))
    (setq th (+ th 0.00087)))           ; ~ 0.05 degree steps
  (list best berr))

;; Try to fit the end width by adjusting the angle; when that is not
;; enough, adjust the diagonal lengths in 1/8" increments (smallest
;; total adjustment first) up to +/-1/2".
;; Returns (ltUsed lbUsed theta) or nil.
(defun pool:grecfit (w lt lb e / s i j lt2 lb2 r out n)
  (setq n pool:*grec-max* s 0 out nil)
  (while (and (null out) (<= s (* 2 n)))
    (setq i (- n))
    (while (and (null out) (<= i n))
      (setq j (- n))
      (while (and (null out) (<= j n))
        (if (= (+ (abs i) (abs j)) s)
            (progn
              (setq lt2 (+ lt (* pool:*grec-step* i))
                    lb2 (+ lb (* pool:*grec-step* j)))
              (if (and (> lt2 0.0) (> lb2 0.0))
                  (progn
                    (setq r (pool:grecth w lt2 lb2 e))
                    (if (<= (cadr r) 0.0625)   ; within 1/16"
                        (setq out (list lt2 lb2 (car r))))))))
        (setq j (1+ j)))
      (setq i (1+ i)))
    (setq s (1+ s)))
  out)

;; Build and draw one Grecian end.  pbot/ptop = end line corners,
;; mdir = unit normal pointing away from the pool body.
;; Returns (p1 p2 ltUsed lbUsed theta okflag); p1 joins ptop, p2 joins
;; pbot.  When the fit fails the end is still drawn at 45 degrees with
;; the given lengths, okflag nil.
(defun pool:grecend (pbot ptop mdir lt lb e lay / u fit lt2 lb2 th ok dtop dbot p1 p2)
  (setq u (pool:unit (pool:v- ptop pbot))
        fit (pool:grecfit (distance pbot ptop) lt lb e))
  (if fit
      (setq lt2 (car fit) lb2 (cadr fit) th (caddr fit) ok t)
      (setq lt2 lt lb2 lb th (pool:d2r 45.0) ok nil))
  (setq dtop (pool:v- (pool:v* mdir (cos th)) (pool:v* u (sin th)))
        dbot (pool:v+ (pool:v* mdir (cos th)) (pool:v* u (sin th)))
        p1 (pool:v+ ptop (pool:v* dtop lt2))
        p2 (pool:v+ pbot (pool:v* dbot lb2)))
  (pool:line ptop p1 lay)
  (pool:line p1 p2 lay)
  (pool:line p2 pbot lay)
  (list p1 p2 lt2 lb2 th ok))

;;; -------------------- report table -----------------------------------

;; rows  = list of (label target actual)
;; notes = list of failure strings (written big and red)
(defun pool:report (rows notes x y h lay / lh ytop y0 xr r tgt act dl ds n)
  (setq lh (* 2.2 h)
        ytop (+ y lh)
        xr (+ x (* 46.0 h))
        y ytop)
  (setq y (- y lh))
  (pool:text (list x y) (* 1.25 h) "POOL LAYOUT REPORT" lay)
  (setq y (- y lh))
  (pool:text (list x y) h "MEASUREMENT" lay)
  (pool:text (list (+ x (* 20.0 h)) y) h "TARGET" lay)
  (pool:text (list (+ x (* 29.0 h)) y) h "ACTUAL" lay)
  (pool:text (list (+ x (* 38.0 h)) y) h "DELTA" lay)
  (foreach r rows
    (setq y (- y lh)
          tgt (cadr r)
          act (caddr r)
          dl (- act tgt)
          ds (strcat (if (< dl 0.0) "" "+") (rtos dl 2 2)))
    (pool:text (list x y) h (car r) lay)
    (pool:text (list (+ x (* 20.0 h)) y) h (rtos tgt 2 2) lay)
    (pool:text (list (+ x (* 29.0 h)) y) h (rtos act 2 2) lay)
    (pool:text (list (+ x (* 38.0 h)) y) h ds lay))
  (foreach n notes
    (setq y (- y (* 1.5 lh)))
    (pool:textc (list x y) (* 1.4 h) n lay 1))
  (setq y0 (- y lh)
        ytop (+ ytop (* 0.6 lh)))
  (pool:line (list (- x h) y0) (list xr y0) lay)
  (pool:line (list xr y0) (list xr ytop) lay)
  (pool:line (list xr ytop) (list (- x h) ytop) lay)
  (pool:line (list (- x h) ytop) (list (- x h) y0) lay)
  (princ))

;;; -------------------- main command -----------------------------------

(defun c:POOL ( / *error* oldcmd oldos oldclay ptype base r2d pv pvall
                  odim xsty
                  tp bo le ri dac dbd totl lrad rrad
                  ltd lbd lew rtd rbd rew
                  fitres quad failed a b c d cen meas notes tri
                  doff th endoff pr
                  midl midr ml mr tipl tipr
                  lend rend lp1 lp2 rp1 rp2
                  allpts xmax ymax ymin rows)

  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg t) "function cancelled")
             (/= (strcase msg t) "quit / exit abort"))
        (princ (strcat "\nPOOL error: " msg)))
    (foreach e pvall (if (and e (entget e)) (entdel e)))
    (if oldclay (setvar "CLAYER" oldclay))
    (if oldos (setvar "OSMODE" oldos))
    (command "_.UNDO" "_End")
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (princ))

  (setq oldcmd (getvar "CMDECHO")
        oldos (getvar "OSMODE")
        oldclay (getvar "CLAYER")
        r2d (/ 180.0 pi))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setvar "OSMODE" 0)

  ;; ------------------------------------------------ user input
  (initget 1 "Rectangle Oval Grecian")
  (setq ptype (getkword "\nPool shape [Rectangle/Oval/Grecian]: "))

  (setq base (getpoint "\nInsertion base point <0,0>: ")
        pool:*base* (if base (list (car base) (cadr base)) (list 0.0 0.0)))

  ;; ------------------------------------------------ layers
  (pool:layer "POOL" 4)
  (pool:layer "POOL-TRIANGLES" 1)
  (pool:layer "DIMENSION" 2)
  (pool:layer "POOL-NOTES" 3)

  ;; -------------------------------------- guide preview + input
  (setq pv (pool:preview ptype)
        pvall (cdr (assoc 'all pv)))
  (command "_.ZOOM" "_Window"
           (pool:wp (list -170.0 -60.0)) (pool:wp (list 530.0 240.0)))
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C top-right, D top-left.")

  (setq tp  (pool:askh "Side length TOP (D-C)" (cdr (assoc 'dc pv)))
        bo  (pool:askh "Side length BOTTOM (A-B)" (cdr (assoc 'ab pv)))
        le  (pool:askh "End length LEFT (A-D)" (cdr (assoc 'da pv)))
        ri  (pool:askh "End length RIGHT (B-C)" (cdr (assoc 'bc pv)))
        dac (pool:askh "Cross dim bottom-left to top-right (A-C)" (cdr (assoc 'ac pv)))
        dbd (pool:askh "Cross dim bottom-right to top-left (B-D)" (cdr (assoc 'bd pv))))

  (cond
    ((= ptype "Oval")
     (setq totl (pool:askh "Total pool length (arc tip to arc tip)" (cdr (assoc 'tot pv)))
           lrad (pool:askh "LEFT oval end radius" (cdr (assoc 'lrad pv)))
           rrad (pool:askh "RIGHT oval end radius" (cdr (assoc 'rrad pv)))))
    ((= ptype "Grecian")
     (setq ltd (pool:askh "LEFT end diagonal TOP" (cdr (assoc 'lt pv)))
           lbd (pool:askh "LEFT end diagonal BOTTOM" (cdr (assoc 'lb pv)))
           lew (pool:askh "LEFT end width (between diagonal end points)" (cdr (assoc 'lw pv)))
           rtd (pool:askh "RIGHT end diagonal TOP" (cdr (assoc 'rt pv)))
           rbd (pool:askh "RIGHT end diagonal BOTTOM" (cdr (assoc 'rb pv)))
           rew (pool:askh "RIGHT end width (between diagonal end points)" (cdr (assoc 'rw pv))))))

  ;; the guide has served its purpose -- replace it with the true pool
  (foreach e pvall (if (entget e) (entdel e)))
  (setq pvall nil)

  ;; ------------------------------------------------ fit the body
  (princ "\nFitting pool body to the measurements ...")
  (setq fitres (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
        quad (car fitres)
        failed (cadr fitres)
        a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        meas (pool:quadmeas quad)
        notes nil)

  ;; dashed linetype + scale for the reference lines
  (setq pool:*dashlt* (pool:ltload "DASHED")
        pool:*lts* (max 1.0 (/ (max bo tp le ri) 15.0)))

  ;; -------------------------------- pool body / perimeter (layer POOL)
  ;; The perimeter runs around the WHOLE pool: for ovals and Grecians
  ;; the body end lines are reference only (dashed, POOL-NOTES) and the
  ;; perimeter closes through the arcs / corner cuts instead.
  (pool:line a b "POOL")
  (pool:line c d "POOL")
  (if (= ptype "Rectangle")
      (progn
        (pool:line b c "POOL")
        (pool:line d a "POOL"))
      (progn
        (pool:lined b c)
        (pool:lined d a)))

  ;; -------------------------------------- exact two-triangle figure
  (setq tri (pool:triquad bo tp le ri dac))
  (if tri
      (progn
        (pool:line (car tri) (cadr tri) "POOL-TRIANGLES")
        (pool:line (cadr tri) (caddr tri) "POOL-TRIANGLES")
        (pool:line (car tri) (caddr tri) "POOL-TRIANGLES") ; shared A-C
        (pool:line (caddr tri) (cadddr tri) "POOL-TRIANGLES")
        (pool:line (cadddr tri) (car tri) "POOL-TRIANGLES"))
      (setq notes (cons "TRIANGLE CHECK IMPOSSIBLE - VERIFY MEASUREMENTS" notes)))

  (setq doff (max 12.0 (/ (max bo tp le ri) 18.0))
        th (max 3.0 (/ (max bo tp le ri) 70.0)))

  ;; ------------------------------------------------ oval ends
  (if (= ptype "Oval")
      (progn
        (setq midl (pool:mid a d)
              ml (pool:unit (pool:perp (pool:v- d a))))
        (if (< (pool:dot (pool:v- midl cen) ml) 0.0)
            (setq ml (pool:v* ml -1.0)))
        (setq tipl (pool:v+ midl (pool:v* ml lrad)))
        (pool:lined midl tipl)
        (pool:arc3p a tipl d "POOL")
        (setq midr (pool:mid b c)
              mr (pool:unit (pool:perp (pool:v- c b))))
        (if (< (pool:dot (pool:v- midr cen) mr) 0.0)
            (setq mr (pool:v* mr -1.0)))
        (setq tipr (pool:v+ midr (pool:v* mr rrad)))
        (pool:lined midr tipr)
        (pool:arc3p b tipr c "POOL")))

  ;; ------------------------------------------------ grecian ends
  (if (= ptype "Grecian")
      (progn
        (setq ml (pool:unit (pool:perp (pool:v- d a))))
        (if (< (pool:dot (pool:v- (pool:mid a d) cen) ml) 0.0)
            (setq ml (pool:v* ml -1.0)))
        (setq lend (pool:grecend a d ml ltd lbd lew "POOL")
              lp1 (car lend)
              lp2 (cadr lend))
        (if (not (nth 5 lend))
            (setq notes (cons "LEFT END FAILED - DIAGONALS/WIDTH DO NOT FIT" notes)))
        (setq mr (pool:unit (pool:perp (pool:v- c b))))
        (if (< (pool:dot (pool:v- (pool:mid b c) cen) mr) 0.0)
            (setq mr (pool:v* mr -1.0)))
        (setq rend (pool:grecend b c mr rtd rbd rew "POOL")
              rp1 (car rend)
              rp2 (cadr rend))
        (if (not (nth 5 rend))
            (setq notes (cons "RIGHT END FAILED - DIAGONALS/WIDTH DO NOT FIT" notes)))))

  ;; ------------------------------------------------ extents
  (setq allpts (append quad
                       (if tri tri nil)
                       (if tipl (list tipl tipr) nil)
                       (if lp1 (list lp1 lp2) nil)
                       (if rp1 (list rp1 rp2) nil))
        xmax (apply 'max (mapcar 'car allpts))
        ymax (apply 'max (mapcar 'cadr allpts))
        ymin (apply 'min (mapcar 'cadr allpts)))

  ;; ------------------------------------------------ dimensions
  (setvar "CLAYER" "DIMENSION")
  (setq endoff (if (= ptype "Rectangle") doff (* -0.6 doff)))
  (pool:dimalg a b (pool:outoff a b cen doff))
  (pool:dimalg d c (pool:outoff d c cen doff))
  (pool:dimalg a d (pool:outoff a d cen endoff))
  (pool:dimalg b c (pool:outoff b c cen endoff))
  (if (= ptype "Oval")
      (progn
        (pool:dimalg midl tipl (pool:v+ (pool:mid midl tipl)
                                        (pool:v* (pool:unit (pool:perp ml))
                                                 (* 0.3 doff))))
        (pool:dimalg midr tipr (pool:v+ (pool:mid midr tipr)
                                        (pool:v* (pool:unit (pool:perp mr))
                                                 (* 0.3 doff))))
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (- ymin (* 1.5 doff))))))
  (if (= ptype "Grecian")
      (progn
        (pool:dimalg d lp1 (pool:outoff d lp1 cen doff))
        (pool:dimalg lp1 lp2 (pool:outoff lp1 lp2 cen doff))
        (pool:dimalg lp2 a (pool:outoff lp2 a cen doff))
        (pool:dimalg c rp1 (pool:outoff c rp1 cen doff))
        (pool:dimalg rp1 rp2 (pool:outoff rp1 rp2 cen doff))
        (pool:dimalg rp2 b (pool:outoff rp2 b cen doff))))
  ;; cross dims last, in the CROSS DIMENSION style when the drawing
  ;; has one (current style restored afterwards)
  (setq odim (getvar "DIMSTYLE")
        xsty (if (tblsearch "DIMSTYLE" "CROSS DIMENSION") t nil))
  (if xsty (command "_.-DIMSTYLE" "_Restore" "CROSS DIMENSION"))
  (pool:dimalg a c (pool:v+ (pool:mid a c)
                            (pool:v* (pool:unit (pool:perp (pool:v- c a)))
                                     (* 0.2 doff))))
  (pool:dimalg b d (pool:v+ (pool:mid b d)
                            (pool:v* (pool:unit (pool:perp (pool:v- d b)))
                                     (* 0.2 doff))))
  (if (and xsty odim (tblsearch "DIMSTYLE" odim))
      (command "_.-DIMSTYLE" "_Restore" odim))
  (setvar "CLAYER" oldclay)

  ;; ------------------------------------------------ corner labels
  (foreach pr (list (list a "A") (list b "B") (list c "C") (list d "D"))
    (pool:text (pool:v+ (car pr)
                        (pool:v* (pool:unit (pool:v- (car pr) cen)) (* 1.5 th)))
               th (cadr pr) "POOL-NOTES"))

  ;; ------------------------------------------------ report table
  (setq rows (list (list "TOP SIDE (D-C)" tp (cadr meas))
                   (list "BOTTOM SIDE (A-B)" bo (car meas))
                   (list "LEFT END (A-D)" le (caddr meas))
                   (list "RIGHT END (B-C)" ri (cadddr meas))
                   (list "CROSS A-C" dac (nth 4 meas))
                   (list "CROSS B-D" dbd (nth 5 meas))))
  (if tri
      (setq rows (append rows
                         (list (list "TRI CHECK B-D" dbd
                                     (distance (cadr tri) (cadddr tri)))))))
  (if (= ptype "Oval")
      (setq rows (append rows
                         (list (list "TOTAL LENGTH" totl (distance tipl tipr))))))
  (if (= ptype "Grecian")
      (setq rows (append rows
                         (list (list "L DIAG TOP" ltd (nth 2 lend))
                               (list "L DIAG BOTTOM" lbd (nth 3 lend))
                               (list "L END WIDTH" lew (distance lp1 lp2))
                               (list "L DIAG ANGLE" 45.0 (* (nth 4 lend) r2d))
                               (list "R DIAG TOP" rtd (nth 2 rend))
                               (list "R DIAG BOTTOM" rbd (nth 3 rend))
                               (list "R END WIDTH" rew (distance rp1 rp2))
                               (list "R DIAG ANGLE" 45.0 (* (nth 4 rend) r2d))))))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")

  ;; ------------------------------------------------ finish
  (command "_.ZOOM" "_Extents")
  (setvar "OSMODE" oldos)
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

(princ "\nPOOL.LSP loaded.  Type POOL to lay out a pool.")
(princ)
