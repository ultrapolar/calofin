;;; ====================================================================
;;;  POOL.LSP -- Swimming-pool as-built layout tool
;;;
;;;  Command:  POOL
;;;
;;;  Draws a pool plan (Rectangle, Oval, Grecian, L or Lazy L) from
;;;  field measurements.
;;;
;;;  First asks whether the pool is IN-SQUARE or OUT-OF-SQUARE.  An
;;;  in-square pool is built true to the side/end measurements and no
;;;  cross dims (diagonals) are asked for or drawn.  An out-of-square
;;;  pool takes the full cross-dim route described below.
;;;
;;;  Rectangle corners may be Square, Rounded (radius) or Diag
;;;  (chamfer, sized by its face length).  Side lengths are always to
;;;  the TRUE corner; the treatment cuts inward.  In-square assumes all
;;;  four corners identical; out-of-square asks per corner (Enter
;;;  reuses the previous corner).  When corners are cut and the pool is
;;;  out-of-square, the cross dims are measured from one of: the true
;;;  Corner, the Middle of the cut/arc, or its Ends (both endpoints of
;;;  each diagonal).  Square corners -> cross dims from the true corner.
;;;
;;;  Out-of-square details:
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
;;;  Grecian: 8-corner pool (body A/B/C/D plus angled-end tips
;;;           LT/LB left and RT/RB right).  Prompts for the six body
;;;           sides/ends, the four end diagonals and two end widths,
;;;           then cross dims at one of three detail levels:
;;;             Simple  = A-C, B-D            (2)
;;;             Center  = + LB-RT, LT-RB      (4, long tip-to-tip X)
;;;             Complex = every diagonal      (18, all pairs; NA any)
;;;           All 8 corners are best-fit against every provided cross
;;;           dim, so more cross dims pin the out-of-square shape down
;;;           more tightly.
;;;  L/LazyL: six-corner pools with one wing (square step joint for
;;;           the true L, angled joint for the lazy L); six sides plus
;;;           up to six cross dims, best-fit the same way.
;;;
;;;  Every cross-dim prompt also accepts NA when that measurement was
;;;  not taken in the field: the fitter skips it and the report shows
;;;  N/A for its target and delta.
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
(setq pool:*pvents*    nil)           ; live guide-preview entities
(setq pool:*insq*      nil)           ; T = in-square pool (no cross dims)

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

;; Switch to the CROSS DIMENSION dim style when the drawing has one.
;; Returns the previous style name (for pool:dimxend), or nil.
(defun pool:dimxbegin ( / odim)
  (if (tblsearch "DIMSTYLE" "CROSS DIMENSION")
      (progn
        (setq odim (getvar "DIMSTYLE"))
        (command "_.-DIMSTYLE" "_Restore" "CROSS DIMENSION")
        odim)))

(defun pool:dimxend (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim))
      (command "_.-DIMSTYLE" "_Restore" odim)))

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

;; Cross-dim prompt: also accepts NA when the measurement was not
;; taken in the field.  Returns a distance or nil for NA.
(defun pool:askx (msg / v)
  (initget 7 "NA")
  (setq v (getdist (strcat "\n" msg " (or NA if not measured): ")))
  (if (= (type v) 'STR) nil v))

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

;; Dashed guide line -- used for the cross dims so they read apart
;; from the pool outline at a glance.
(defun pool:pvlined (p1 p2)
  (pool:lined p1 p2)
  (pool:setcol (entlast) pool:*pv-col*))

;; Ask for a distance while the matching guide elements glow red.
(defun pool:askh (msg ents / v)
  (foreach e ents (pool:setcol e pool:*hi-col*))
  (setq v (pool:ask msg))
  (foreach e ents (pool:setcol e pool:*pv-col*))
  v)

;; Same, for cross dims: NA allowed, returns nil when not measured.
(defun pool:askhx (msg ents / v)
  (foreach e ents (pool:setcol e pool:*hi-col*))
  (setq v (pool:askx msg))
  (foreach e ents (pool:setcol e pool:*pv-col*))
  v)

;; Delete all guide entities (tracked globally so the *error* handler
;; can clean up after a cancel mid-prompt).
(defun pool:pvkill ()
  (foreach e pool:*pvents*
    (if (and e (entget e)) (entdel e)))
  (setq pool:*pvents* nil))

;; Remove an item (by equality) from a list.
(defun pool:lremove (x lst / out i)
  (foreach i lst (if (not (equal i x)) (setq out (cons i out))))
  (reverse out))

;; Track a freshly made guide entity so pool:pvkill / *error* find it.
(defun pool:pvadd (e)
  (setq pool:*pvents* (cons e pool:*pvents*))
  e)

;; Delete specific guide entities mid-flow and untrack them (used when
;; part of the guide is redrawn, e.g. corner treatments).
(defun pool:pvdel (ents / e)
  (foreach e ents
    (if (and e (entget e)) (entdel e))
    (setq pool:*pvents* (pool:lremove e pool:*pvents*))))

;; Draw the nominal guide pool for the chosen shape (fixed 360 x 180
;; body).  Returns an assoc list mapping each input key to the list of
;; guide entities to highlight, plus an ALL entry with every guide
;; entity for later deletion.
(defun pool:preview (ptype / pw ph a b c d cen pr all pv
                             eab ebc ecd eda eac ebd
                             midl midr tipl tipr elrad errad elarc erarc etot)
  (setq pw 360.0 ph 180.0
        a (list 0.0 0.0) b (list pw 0.0) c (list pw ph) d (list 0.0 ph)
        cen (list (* 0.5 pw) (* 0.5 ph))
        eab (pool:pvline a b)
        ebc (pool:pvline b c)
        ecd (pool:pvline d c)
        eda (pool:pvline d a)
        all (list eab ebc ecd eda)
        pv (list (cons 'ab (list eab)) (cons 'bc (list ebc))
                 (cons 'dc (list ecd)) (cons 'da (list eda))))
  ;; body diagonals only when out-of-square
  (if (not pool:*insq*)
      (setq eac (pool:pvlined a c)
            ebd (pool:pvlined b d)
            all (append all (list eac ebd))
            pv (append pv (list (cons 'ac (list eac)) (cons 'bd (list ebd))))))
  (foreach pr (list (list a "A") (list b "B") (list c "C") (list d "D"))
    (pool:text (pool:v+ (car pr)
                        (pool:v* (pool:unit (pool:v- (car pr) cen)) 20.0))
               12.0 (cadr pr) "POOL-NOTES")
    (setq all (cons (pool:setcol (entlast) pool:*pv-col*) all)))
  (cond
    ((= ptype "Oval")
     (setq midl (list 0.0 (* 0.5 ph)) tipl (list -80.0 (* 0.5 ph))
           midr (list pw (* 0.5 ph)) tipr (list (+ pw 80.0) (* 0.5 ph))
           elrad (pool:pvlined midl tipl)
           errad (pool:pvlined midr tipr))
     (pool:arc3p a tipl d "POOL-NOTES")
     (setq elarc (pool:setcol (entlast) pool:*pv-col*))
     (pool:arc3p b tipr c "POOL-NOTES")
     (setq erarc (pool:setcol (entlast) pool:*pv-col*))
     (setq etot (pool:pvlined tipl tipr)
           all (append all (list elrad errad elarc erarc etot))
           pv (append pv (list (cons 'lrad (list elrad elarc))
                               (cons 'rrad (list errad erarc))
                               (cons 'tot (list etot)))))))
  (setq pool:*pvents* all)
  pv)

;;; -------------------- quadrilateral fitting --------------------------

;; Measured lengths of quad (A B C D):
;; (bottom top left right crossAC crossBD)
(defun pool:quadmeas (q / a b c d)
  (setq a (car q) b (cadr q) c (caddr q) d (cadddr q))
  (list (distance a b) (distance d c) (distance a d) (distance b c)
        (distance a c) (distance b d)))

;; Cross-dim error of a quad; a nil target (NA) contributes nothing.
(defun pool:diagerr (q dac dbd / e1 e2)
  (setq e1 (if dac (- (distance (car q) (caddr q)) dac) 0.0)
        e2 (if dbd (- (distance (cadr q) (cadddr q)) dbd) 0.0))
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
;; With both cross dims NA there is nothing to skew for: square up.
(defun pool:fitsides (bo tp le ri dac dbd / r1 r2 alfa)
  (if (and (null dac) (null dbd))
      (pool:4bar bo tp le ri (pool:d2r 90.0))
      (progn
        (setq r1 (pool:scanalfa bo tp le ri dac dbd
                                (pool:d2r 15.0) (pool:d2r 165.0) (pool:d2r 0.25)))
        (if r1
            (progn
              (setq alfa (cadr r1)
                    r2 (pool:scanalfa bo tp le ri dac dbd
                                      (- alfa (pool:d2r 0.3)) (+ alfa (pool:d2r 0.3))
                                      (pool:d2r 0.005)))
              (car (if r2 r2 r1)))))))

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

;; Re-gauge a polygon: first point at the origin, second on the +X
;; axis, bulk of the shape above the axis.  Works for any point count.
(defun pool:normpoly (pts / a ang my)
  (setq a (car pts)
        pts (mapcar '(lambda (p) (pool:v- p a)) pts)
        ang (- (angle (list 0.0 0.0) (cadr pts)))
        pts (mapcar '(lambda (p) (pool:rot p ang)) pts)
        my 0.0)
  (foreach a pts (setq my (+ my (cadr a))))
  (if (< my 0.0)
      (setq pts (mapcar '(lambda (p) (list (car p) (- (cadr p)))) pts)))
  pts)

;; Iterative relaxation of an arbitrary point list against distance
;; constraints (i j lo hi weight); lo = hi -> exact pull.
(defun pool:relaxn (pts conlst niter / k c)
  (setq k 0)
  (while (< k niter)
    (foreach c conlst
      (setq pts (pool:relax1 pts (car c) (cadr c) (caddr c) (cadddr c) (nth 4 c))))
    (setq k (1+ k)))
  (pool:normpoly pts))

;; Quad relaxation: sides banded to +/-stol, provided cross dims
;; pulled to their exact targets.  Cross dims pull first, side bands
;; clamp last so each sweep ends with the sides inside their band.
(defun pool:relaxquad (pts bo tp le ri dac dbd stol niter / conlst)
  (setq conlst nil)
  (if dbd (setq conlst (cons (list 1 3 dbd dbd 0.5) conlst)))
  (if dac (setq conlst (cons (list 0 2 dac dac 0.5) conlst)))
  (setq conlst (append conlst
                       (list (list 0 1 (- bo stol) (+ bo stol) 1.0)
                             (list 3 2 (- tp stol) (+ tp stol) 1.0)
                             (list 0 3 (- le stol) (+ le stol) 1.0)
                             (list 1 2 (- ri stol) (+ ri stol) 1.0))))
  (pool:relaxn pts conlst niter))

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
  (if (and (or (null dac) (<= (abs (- (nth 4 m1) dac)) xtol))
           (or (null dbd) (<= (abs (- (nth 5 m1) dbd)) xtol)))
      (list q1 nil)
      (progn
        (setq q2 (pool:relaxquad q1 bo tp le ri dac dbd stol 2000)
              m2 (pool:quadmeas q2)
              sok (and (<= (abs (- (car m2) bo)) (+ stol 0.05))
                       (<= (abs (- (cadr m2) tp)) (+ stol 0.05))
                       (<= (abs (- (caddr m2) le)) (+ stol 0.05))
                       (<= (abs (- (cadddr m2) ri)) (+ stol 0.05)))
              xok (and (or (null dac) (<= (abs (- (nth 4 m2) dac)) (+ xtol 0.05)))
                       (or (null dbd) (<= (abs (- (nth 5 m2) dbd)) (+ xtol 0.05)))))
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

;; Compute one Grecian end (no drawing).  pbot/ptop = end line
;; corners, mdir = unit normal pointing away from the pool body.
;; Returns (p1 p2 ltUsed lbUsed theta okflag); p1 joins ptop, p2 joins
;; pbot.  When the fit fails the end falls back to 45 degrees with the
;; given lengths, okflag nil.
(defun pool:grecendp (pbot ptop mdir lt lb e / u fit lt2 lb2 th ok dtop dbot)
  (setq u (pool:unit (pool:v- ptop pbot))
        fit (pool:grecfit (distance pbot ptop) lt lb e))
  (if fit
      (setq lt2 (car fit) lb2 (cadr fit) th (caddr fit) ok t)
      (setq lt2 lt lb2 lb th (pool:d2r 45.0) ok nil))
  (setq dtop (pool:v- (pool:v* mdir (cos th)) (pool:v* u (sin th)))
        dbot (pool:v+ (pool:v* mdir (cos th)) (pool:v* u (sin th))))
  (list (pool:v+ ptop (pool:v* dtop lt2))
        (pool:v+ pbot (pool:v* dbot lb2))
        lt2 lb2 th ok))

;; Compute + draw one Grecian end on layer lay.
(defun pool:grecend (pbot ptop mdir lt lb e lay / r)
  (setq r (pool:grecendp pbot ptop mdir lt lb e))
  (pool:line ptop (car r) lay)
  (pool:line (car r) (cadr r) lay)
  (pool:line (cadr r) pbot lay)
  r)

;;; -------------------- grecian cross-dim modes -------------------------
;;;
;;;  A Grecian pool has 8 corners; from the bottom-left, clockwise:
;;;
;;;         D ------------------ C          body:  A B C D
;;;        /                      \         left tips:  LT (off D), LB (off A)
;;;      LT                        RT       right tips: RT (off C), RB (off B)
;;;        \                      /
;;;         LB                  RB          index order used below:
;;;           \                /             0=A 1=B 2=RB 3=RT 4=C 5=D 6=LT 7=LB
;;;            A ------------ B
;;;
;;;  Cross-dim modes (how many diagonals the user is asked for):
;;;    Simple  = A-C, B-D                       (2, the body diagonals)
;;;    Center  = Simple + LB-RT, LT-RB          (4, adds the long tip X)
;;;    Complex = every possible diagonal        (18, all pairs; NA any)
;;;  More provided cross dims -> the out-of-square shape is pinned down
;;;  more tightly.  Any cross dim may be answered NA.

(setq pool:*grecnames*
      (list "A" "B" "RB" "RT" "C" "D" "LT" "LB"))

;; perimeter edges + the two body-end chords as (i j prompt-key band):
;; body sides loose (1"), end diagonals held near the given 1/2", end
;; widths near-exact.  The prompt-key ties each edge to its guide
;; highlight and prompt.
(setq pool:*grecedges*
      (list '(0 1 ab  1.0)     ; A-B  bottom side
            '(1 2 rbd 0.5)     ; B-RB right diag bottom
            '(2 3 rew 0.1)     ; RB-RT right end width
            '(3 4 rtd 0.5)     ; RT-C right diag top
            '(4 5 cd  1.0)     ; C-D  top side
            '(5 6 ltd 0.5)     ; D-LT left diag top
            '(6 7 lew 0.1)     ; LT-LB left end width
            '(7 0 lbd 0.5)     ; LB-A left diag bottom
            '(0 5 ad  1.0)     ; A-D  left end (internal chord)
            '(1 4 bc  1.0)))   ; B-C  right end (internal chord)

(setq pool:*grec-simple*
      (list '(0 4 "A-C") '(1 5 "B-D")))
(setq pool:*grec-center*
      (list '(0 4 "A-C") '(1 5 "B-D") '(7 3 "LB-RT") '(6 2 "LT-RB")))
(setq pool:*grec-complex*
      (list '(0 2 "A-RB") '(0 3 "A-RT") '(0 4 "A-C")  '(0 6 "A-LT")
            '(1 3 "B-RT") '(1 5 "B-D")  '(1 6 "B-LT") '(1 7 "B-LB")
            '(2 4 "RB-C") '(2 5 "RB-D") '(2 6 "RB-LT") '(2 7 "RB-LB")
            '(3 5 "RT-D") '(3 6 "RT-LT") '(3 7 "RT-LB")
            '(4 6 "C-LT") '(4 7 "C-LB")
            '(5 7 "D-LB")))

(defun pool:grecmode (m)
  (cond ((= m "Center")  pool:*grec-center*)
        ((= m "Complex") pool:*grec-complex*)
        (t               pool:*grec-simple*)))

;; Worst cross-dim miss over the provided (non-nil) targets.
(defun pool:crossmax (pts crosscons / mx d)
  (setq mx 0.0)
  (foreach c crosscons
    (if (caddr c)
        (setq d (abs (- (distance (nth (car c) pts) (nth (cadr c) pts)) (caddr c)))
              mx (max mx d))))
  mx)

;; Worst amount any edge sits OUTSIDE its band (<=0 means all in band).
(defun pool:edgemax (pts edgecons / mx d)
  (setq mx -1.0e30)
  (foreach e edgecons
    (setq d (- (abs (- (distance (nth (car e) pts) (nth (cadr e) pts)) (caddr e)))
               (cadddr e))
          mx (max mx d)))
  mx)

;; Generic two-phase best fit of a point list:
;;   edgecons  = (i j target band)   crosscons = (i j target)
;;   1. pull crosses while holding edges EXACT; if crosses land inside
;;      xtol -> done, no failure.
;;   2. let edges flex within their bands and pull crosses; if edges
;;      stay in band and crosses land inside xtol -> done.
;;   3. otherwise edges held true (step-1 result), crosses as close as
;;      possible, failure flag set.
;; Returns (pts failed).
(defun pool:fitpoly (seed edgecons crosscons xtol / xcon e0 eb p1 p2)
  (setq xcon nil)
  (foreach c crosscons                  ; provided (non-NA) crosses only
    (if (caddr c)
        (setq xcon (cons (list (car c) (cadr c) (caddr c) (caddr c) 0.5) xcon))))
  (setq e0 (mapcar '(lambda (e) (list (car e) (cadr e) (caddr e) (caddr e) 1.0))
                   edgecons)
        eb (mapcar '(lambda (e) (list (car e) (cadr e)
                                      (- (caddr e) (cadddr e))
                                      (+ (caddr e) (cadddr e)) 1.0))
                   edgecons))
  (setq p1 (pool:relaxn seed (append xcon e0) 3000)
        p1 (pool:relaxn p1 e0 400))
  (if (<= (pool:crossmax p1 crosscons) xtol)
      (list p1 nil)
      (progn
        (setq p2 (pool:relaxn p1 (append xcon eb) 3000))
        (if (and (<= (pool:edgemax p2 edgecons) 0.05)
                 (<= (pool:crossmax p2 crosscons) (+ xtol 0.05)))
            (list p2 nil)
            (list p1 t)))))

;; Look up a provided cross target for corner pair (i j); nil if NA or
;; not in the active set.
(defun pool:crossget (crosscons i j / out)
  (foreach c crosscons
    (if (or (and (= (car c) i) (= (cadr c) j))
            (and (= (car c) j) (= (cadr c) i)))
        (setq out (caddr c))))
  out)

(defun pool:grecnm (i j)
  (strcat (nth i pool:*grecnames*) "-" (nth j pool:*grecnames*)))

;; Gray guide for a Grecian: 8-corner nominal body (solid perimeter,
;; dashed internal end chords), corner labels clear of the linework,
;; and the active mode's cross diagonals (dashed).  Returns the
;; highlight assoc (edge prompt-keys + one entry per cross name).
(defun pool:grecpreview (crosses / npts cen p q e c ent all pv k)
  (setq npts (list (list 0.0 0.0) (list 360.0 0.0) (list 410.0 55.0)
                   (list 410.0 125.0) (list 360.0 180.0) (list 0.0 180.0)
                   (list -50.0 125.0) (list -50.0 55.0))
        cen (list 0.0 0.0) all nil pv nil)
  (foreach p npts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 8.0)))
  (foreach e pool:*grecedges*
    (setq p (nth (car e) npts) q (nth (cadr e) npts)
          ent (if (member (caddr e) '(ad bc)) (pool:pvlined p q) (pool:pvline p q))
          pv (cons (cons (caddr e) (list ent)) pv)
          all (cons ent all)))
  (foreach c crosses
    (setq ent (pool:pvlined (nth (car c) npts) (nth (cadr c) npts))
          pv (cons (cons (caddr c) (list ent)) pv)
          all (cons ent all)))
  (setq k 0)
  (foreach p npts
    (pool:text (pool:lbloff p cen npts 22.0) 12.0 (nth k pool:*grecnames*) "POOL-NOTES")
    (setq all (cons (pool:setcol (entlast) pool:*pv-col*) all)
          k (1+ k)))
  (setq pool:*pvents* all)
  pv)

;; Full guided flow for a Grecian pool (all three cross-dim modes).
;; Caller handles sysvars / undo / zoom-extents.
(defun pool:grecflow ( / oldclay mode crosses pv
                       tp bo le ri ltd lbd lew rtd rbd rew
                       evals edgecons crosscons dac dbd fq q
                       a b c d cen0 ml mr lend rend seed
                       res pts failed notes
                       xmin xmax ymin ymax w hh doff th cen odim
                       e p qq cc nm tgt act rows k)
  (setq oldclay (getvar "CLAYER"))

  ;; in-square Grecians skip cross dims entirely; out-of-square pick a
  ;; cross-dim detail level
  (if pool:*insq*
      (setq mode "Simple" crosses nil)
      (progn
        (initget 1 "Simple Center Complex")
        (setq mode (getkword "\nGrecian cross-dim detail [Simple/Center/Complex]: ")
              crosses (pool:grecmode mode))))

  (setq pv (pool:grecpreview crosses))
  (command "_.ZOOM" "_Window"
           (pool:wp (list -110.0 -80.0)) (pool:wp (list 470.0 300.0)))
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A/B bottom, C/D top, LT/LB left tips, RT/RB right tips.")

  ;; -------- body + ends
  (setq bo  (pool:askh "Side BOTTOM (A-B)" (cdr (assoc 'ab pv)))
        tp  (pool:askh "Side TOP (D-C)" (cdr (assoc 'cd pv)))
        le  (pool:askh "End LEFT (A-D)" (cdr (assoc 'ad pv)))
        ri  (pool:askh "End RIGHT (B-C)" (cdr (assoc 'bc pv)))
        ltd (pool:askh "LEFT end diagonal TOP (D-LT)" (cdr (assoc 'ltd pv)))
        lbd (pool:askh "LEFT end diagonal BOTTOM (A-LB)" (cdr (assoc 'lbd pv)))
        lew (pool:askh "LEFT end width (LT-LB)" (cdr (assoc 'lew pv)))
        rtd (pool:askh "RIGHT end diagonal TOP (C-RT)" (cdr (assoc 'rtd pv)))
        rbd (pool:askh "RIGHT end diagonal BOTTOM (B-RB)" (cdr (assoc 'rbd pv)))
        rew (pool:askh "RIGHT end width (RT-RB)" (cdr (assoc 'rew pv))))

  ;; -------- cross dims for the chosen mode (NA allowed on each)
  (setq crosscons nil)
  (foreach e crosses
    (setq tgt (pool:askhx (strcat "Cross dim " (caddr e)) (cdr (assoc (caddr e) pv)))
          crosscons (cons (list (car e) (cadr e) tgt) crosscons)))
  (setq crosscons (reverse crosscons))
  (pool:pvkill)

  ;; -------- seed: fit the body quad, project nominal ends
  (setq evals (list (cons 'ab bo) (cons 'cd tp) (cons 'ad le) (cons 'bc ri)
                    (cons 'rbd rbd) (cons 'rew rew) (cons 'rtd rtd)
                    (cons 'ltd ltd) (cons 'lew lew) (cons 'lbd lbd))
        edgecons (mapcar '(lambda (e)
                            (list (car e) (cadr e) (cdr (assoc (caddr e) evals)) (cadddr e)))
                         pool:*grecedges*)
        dac (pool:crossget crosscons 0 4)
        dbd (pool:crossget crosscons 1 5)
        fq (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
        q (car fq)
        a (car q) b (cadr q) c (caddr q) d (cadddr q)
        cen0 (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        ml (pool:unit (pool:perp (pool:v- d a))))
  (if (< (pool:dot (pool:v- (pool:mid a d) cen0) ml) 0.0)
      (setq ml (pool:v* ml -1.0)))
  (setq mr (pool:unit (pool:perp (pool:v- c b))))
  (if (< (pool:dot (pool:v- (pool:mid b c) cen0) mr) 0.0)
      (setq mr (pool:v* mr -1.0)))
  (setq lend (pool:grecendp a d ml ltd lbd lew)
        rend (pool:grecendp b c mr rtd rbd rew)
        seed (list a b (cadr rend) (car rend) c d (car lend) (cadr lend))
        notes nil)
  (if (not (nth 5 lend))
      (setq notes (cons "LEFT END: diagonals/width did not fit -- 45 seed used" notes)))
  (if (not (nth 5 rend))
      (setq notes (cons "RIGHT END: diagonals/width did not fit -- 45 seed used" notes)))

  ;; -------- fit: Simple keeps the validated seed; Center/Complex
  ;; best-fit all 8 corners against every provided cross dim
  (if (= mode "Simple")
      (setq pts seed failed (cadr fq))
      (progn
        (setq res (pool:fitpoly seed edgecons crosscons pool:*cross-tol*)
              pts (car res)
              failed (cadr res))))

  ;; -------- extents / scale
  (setq xmin (apply 'min (mapcar 'car pts))
        xmax (apply 'max (mapcar 'car pts))
        ymin (apply 'min (mapcar 'cadr pts))
        ymax (apply 'max (mapcar 'cadr pts))
        w (- xmax xmin) hh (- ymax ymin)
        doff (max 12.0 (/ (max w hh) 18.0))
        th (max 3.0 (/ (max w hh) 70.0))
        pool:*dashlt* (pool:ltload "DASHED")
        pool:*lts* (max 1.0 (/ (max w hh) 15.0))
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 8.0)))

  ;; -------- perimeter (POOL) + internal end chords (dashed, POOL-NOTES)
  (foreach e pool:*grecedges*
    (setq p (nth (car e) pts) qq (nth (cadr e) pts))
    (if (member (caddr e) '(ad bc))
        (pool:lined p qq)
        (pool:line p qq "POOL")))

  ;; -------- dimensions (DIMENSION)
  (setvar "CLAYER" "DIMENSION")
  (foreach e pool:*grecedges*
    (setq p (nth (car e) pts) qq (nth (cadr e) pts))
    (cond
      ((= (caddr e) 'ad)                ; left end chord -> outboard left
       (pool:dimalg p qq (list (- xmin (* 0.6 doff)) (cadr (pool:mid p qq)))))
      ((= (caddr e) 'bc)                ; right end chord -> outboard right
       (pool:dimalg p qq (list (+ xmax (* 0.6 doff)) (cadr (pool:mid p qq)))))
      (t
       (pool:dimalg p qq (pool:outoffp p qq pts doff)))))
  ;; provided cross dims, in the CROSS DIMENSION style when available
  (setq odim (pool:dimxbegin) k 0)
  (foreach cc crosscons
    (if (caddr cc)
        (pool:dimalg (nth (car cc) pts) (nth (cadr cc) pts)
                     (pool:v+ (pool:mid (nth (car cc) pts) (nth (cadr cc) pts))
                              (pool:v* (pool:unit
                                         (pool:perp (pool:v- (nth (cadr cc) pts)
                                                             (nth (car cc) pts))))
                                       (* (if (= 0 (rem k 2)) 0.12 -0.12) doff)))))
    (setq k (1+ k)))
  (pool:dimxend odim)
  (setvar "CLAYER" oldclay)

  ;; -------- corner labels (kept outside the shape)
  (setq k 0)
  (foreach p pts
    (pool:text (pool:lbloff p cen pts (* 2.0 th)) th (nth k pool:*grecnames*) "POOL-NOTES")
    (setq k (1+ k)))

  ;; -------- report table
  (setq rows nil)
  (foreach e pool:*grecedges*
    (setq nm (pool:grecnm (car e) (cadr e))
          tgt (cdr (assoc (caddr e) evals))
          act (distance (nth (car e) pts) (nth (cadr e) pts))
          rows (cons (list nm tgt act) rows)))
  (foreach cc crosscons
    (setq nm (pool:grecnm (car cc) (cadr cc))
          act (distance (nth (car cc) pts) (nth (cadr cc) pts))
          rows (cons (list (strcat "X " nm) (caddr cc) act) rows)))
  (setq rows (reverse rows))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- L / Lazy L pools --------------------------------
;;;
;;;  Six-corner pools, one wing:      F -------- E
;;;                                   |           \
;;;    True L: joint D-E is a         |            D ------- C
;;;    square step; Lazy L: D-E       |                      |
;;;    is an angled joint.            A -------------------- B
;;;
;;;  Sides A-B, B-C, C-D, D-E, E-F, F-A plus up to six cross dims
;;;  (A-C, B-D, C-E, D-F, A-E, B-F -- any of them may be NA).

(setq pool:*hexsides* (list '(0 1) '(1 2) '(2 3) '(3 4) '(4 5) '(5 0)))
(setq pool:*hexsidenames* (list "A-B" "B-C" "C-D" "D-E" "E-F" "F-A"))
(setq pool:*hexdiags* (list '(0 2) '(1 3) '(2 4) '(3 5) '(0 4) '(1 5)))
(setq pool:*hexdiagnames* (list "A-C" "B-D" "C-E" "D-F" "A-E" "B-F"))

;; Nominal right-angle (or 45-degree jointed) L built from the given
;; side lengths -- the starting shape for the relaxation fit.
(defun pool:hexguess (sides lazy / ab bc cd de a b c d e f)
  (setq ab (nth 0 sides) bc (nth 1 sides) cd (nth 2 sides) de (nth 3 sides)
        a (list 0.0 0.0)
        b (list ab 0.0)
        c (list ab bc)
        d (list (- ab cd) bc)
        e (if lazy
              (pool:v+ d (list (* de -0.7071067812) (* de 0.7071067812)))
              (pool:v+ d (list 0.0 de)))
        f (pool:v- e (list (nth 4 sides) 0.0)))
  (list a b c d e f))

;; Side constraints (banded by +/-band) for the hexagon.
(defun pool:hexsidecon (sides band w / k out pr)
  (setq k 0 out nil)
  (foreach pr pool:*hexsides*
    (setq out (cons (list (car pr) (cadr pr)
                          (- (nth k sides) band) (+ (nth k sides) band) w)
                    out)
          k (1+ k)))
  (reverse out))

;; Exact-pull constraints for the provided (non-NA) cross dims.
(defun pool:hexdiagcon (diags w / k out pr tgt)
  (setq k 0 out nil)
  (foreach pr pool:*hexdiags*
    (setq tgt (nth k diags))
    (if tgt
        (setq out (cons (list (car pr) (cadr pr) tgt tgt w) out)))
    (setq k (1+ k)))
  (reverse out))

;; (max-side-delta max-cross-delta) of a fitted hexagon; NA cross dims
;; are ignored.
(defun pool:hexerr (pts sides diags / k pr smax xmax d)
  (setq smax 0.0 xmax 0.0 k 0)
  (foreach pr pool:*hexsides*
    (setq d (abs (- (distance (nth (car pr) pts) (nth (cadr pr) pts))
                    (nth k sides)))
          smax (max smax d)
          k (1+ k)))
  (setq k 0)
  (foreach pr pool:*hexdiags*
    (if (nth k diags)
        (setq d (abs (- (distance (nth (car pr) pts) (nth (cadr pr) pts))
                        (nth k diags)))
              xmax (max xmax d)))
    (setq k (1+ k)))
  (list smax xmax))

;; Fit the L hexagon (same policy as the quad):
;;  1. sides held true, provided cross dims pulled as close as they
;;     will come; inside tolerance -> done
;;  2. sides may flex inside +/-stol to pull the cross dims in
;;  3. otherwise sides held true, cross dims as close as possible,
;;     failure flag set
;; Returns (pts failed).
(defun pool:fithex (sides diags lazy stol xtol / guess p1 e1 p2 e2)
  (setq guess (pool:hexguess sides lazy)
        p1 (pool:relaxn guess
                        (append (pool:hexdiagcon diags 0.4)
                                (pool:hexsidecon sides 0.0 1.0))
                        3000))
  ;; polish: a sides-only pass so the sides land exactly true
  (setq p1 (pool:relaxn p1 (pool:hexsidecon sides 0.0 1.0) 400)
        e1 (pool:hexerr p1 sides diags))
  (if (<= (cadr e1) xtol)
      (list p1 nil)
      (progn
        (setq p2 (pool:relaxn p1
                              (append (pool:hexdiagcon diags 0.5)
                                      (pool:hexsidecon sides stol 1.0))
                              3000)
              e2 (pool:hexerr p2 sides diags))
        (if (and (<= (car e2) (+ stol 0.05)) (<= (cadr e2) (+ xtol 0.05)))
            (list p2 nil)
            (list p1 t)))))

;; Point-in-polygon (ray casting) -- the L is not convex, so side
;; dimensions find "outward" by testing against the actual shape.
(defun pool:inpoly (p poly / n i j xi yi xj yj in x y)
  (setq x (car p) y (cadr p)
        n (length poly)
        i 0 j (1- n) in nil)
  (while (< i n)
    (setq xi (car (nth i poly)) yi (cadr (nth i poly))
          xj (car (nth j poly)) yj (cadr (nth j poly)))
    (if (and (or (and (> yi y) (<= yj y))
                 (and (> yj y) (<= yi y)))
             (< x (+ xi (* (- xj xi) (/ (- y yi) (- yj yi))))))
        (setq in (not in)))
    (setq j i i (1+ i)))
  in)

;; Midpoint of p->q offset by dist to the side that lies OUTSIDE poly.
(defun pool:outoffp (p q poly dist / m n)
  (setq m (pool:mid p q)
        n (pool:unit (pool:perp (pool:v- q p))))
  (if (pool:inpoly (pool:v+ m (pool:v* n 1.0)) poly)
      (setq n (pool:v* n -1.0)))
  (pool:v+ m (pool:v* n dist)))

;; Corner-label position: away from the centroid, but flipped when
;; that lands inside the shape (the inner corner of an L).
(defun pool:lbloff (p cen poly dist / dir cand)
  (setq dir (pool:unit (pool:v- p cen))
        cand (pool:v+ p (pool:v* dir dist)))
  (if (pool:inpoly cand poly)
      (pool:v+ p (pool:v* dir (- dist)))
      cand))

;; Gray guide for the L shapes: nominal body (solid), the six cross
;; diagonals (DASHED, so outline and cross dims read apart), and
;; corner labels kept clear of the linework.
(defun pool:hexpreview (lazy / pts cen p pr k keys ent all pv lbls)
  (setq pts (if lazy
                (list (list 0.0 0.0) (list 360.0 0.0) (list 360.0 150.0)
                      (list 240.0 150.0) (list 140.0 250.0) (list 0.0 250.0))
                (list (list 0.0 0.0) (list 360.0 0.0) (list 360.0 150.0)
                      (list 200.0 150.0) (list 200.0 300.0) (list 0.0 300.0)))
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 6.0))
        all nil pv nil)
  (setq keys (list 'ab 'bc 'cd 'de 'ef 'fa) k 0)
  (foreach pr pool:*hexsides*
    (setq ent (pool:pvline (nth (car pr) pts) (nth (cadr pr) pts))
          pv (cons (cons (nth k keys) (list ent)) pv)
          all (cons ent all)
          k (1+ k)))
  ;; cross diagonals only when out-of-square
  (if (not pool:*insq*)
      (progn
        (setq keys (list 'ac 'bd 'ce 'df 'ae 'bf) k 0)
        (foreach pr pool:*hexdiags*
          (setq ent (pool:pvlined (nth (car pr) pts) (nth (cadr pr) pts))
                pv (cons (cons (nth k keys) (list ent)) pv)
                all (cons ent all)
                k (1+ k)))))
  (setq lbls (list "A" "B" "C" "D" "E" "F") k 0)
  (foreach p pts
    (pool:text (pool:lbloff p cen pts 20.0) 12.0 (nth k lbls) "POOL-NOTES")
    (setq all (cons (pool:setcol (entlast) pool:*pv-col*) all)
          k (1+ k)))
  (setq pool:*pvents* all)
  pv)

;; Full guided flow for L / Lazy L pools: preview, prompts, fit, draw,
;; dimension and report.  Caller handles sysvars / undo / zoom-extents.
(defun pool:hexflow (lazy / oldclay pv sides diags res pts failed notes
                            cen p pr k w hh xmin xmax ymax ymin doff th
                            odim rows lbls)
  (setq oldclay (getvar "CLAYER"))
  (setq pv (pool:hexpreview lazy))
  (command "_.ZOOM" "_Window"
           (pool:wp (list -80.0 -70.0)) (pool:wp (list 520.0 370.0)))
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C right end top, D inner corner, E wing corner, F top-left.")
  (setq sides
        (list (pool:askh "Side A-B (main side, bottom)" (cdr (assoc 'ab pv)))
              (pool:askh "End B-C (right end)" (cdr (assoc 'bc pv)))
              (pool:askh "Side C-D (top of main section)" (cdr (assoc 'cd pv)))
              (pool:askh (if lazy "Angled joint D-E" "Joint D-E (step)")
                         (cdr (assoc 'de pv)))
              (pool:askh "End E-F (end of wing)" (cdr (assoc 'ef pv)))
              (pool:askh "Side F-A (left side)" (cdr (assoc 'fa pv)))))
  ;; cross dims only when out-of-square; in-square squares up to sides
  (setq diags
        (if pool:*insq*
            (list nil nil nil nil nil nil)
            (list (pool:askhx "Cross dim A-C" (cdr (assoc 'ac pv)))
                  (pool:askhx "Cross dim B-D" (cdr (assoc 'bd pv)))
                  (pool:askhx "Cross dim C-E" (cdr (assoc 'ce pv)))
                  (pool:askhx "Cross dim D-F" (cdr (assoc 'df pv)))
                  (pool:askhx "Cross dim A-E" (cdr (assoc 'ae pv)))
                  (pool:askhx "Cross dim B-F" (cdr (assoc 'bf pv))))))
  (pool:pvkill)

  (princ "\nFitting pool body to the measurements ...")
  (setq res (pool:fithex sides diags lazy pool:*side-tol* pool:*cross-tol*)
        pts (car res)
        failed (cadr res)
        notes nil
        xmin (apply 'min (mapcar 'car pts))
        xmax (apply 'max (mapcar 'car pts))
        ymin (apply 'min (mapcar 'cadr pts))
        ymax (apply 'max (mapcar 'cadr pts))
        w (- xmax xmin)
        hh (- ymax ymin)
        doff (max 12.0 (/ (max w hh) 18.0))
        th (max 3.0 (/ (max w hh) 70.0))
        pool:*dashlt* (pool:ltload "DASHED")
        pool:*lts* (max 1.0 (/ (max w hh) 15.0))
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 6.0)))

  ;; perimeter (layer POOL)
  (foreach pr pool:*hexsides*
    (pool:line (nth (car pr) pts) (nth (cadr pr) pts) "POOL"))

  ;; dimensions (layer DIMENSION)
  (setvar "CLAYER" "DIMENSION")
  (foreach pr pool:*hexsides*
    (pool:dimalg (nth (car pr) pts) (nth (cadr pr) pts)
                 (pool:outoffp (nth (car pr) pts) (nth (cadr pr) pts)
                               pts doff)))
  ;; provided cross dims, in the CROSS DIMENSION style when available
  (setq odim (pool:dimxbegin) k 0)
  (foreach pr pool:*hexdiags*
    (if (nth k diags)
        (pool:dimalg (nth (car pr) pts) (nth (cadr pr) pts)
                     (pool:v+ (pool:mid (nth (car pr) pts) (nth (cadr pr) pts))
                              (pool:v* (pool:unit
                                         (pool:perp
                                           (pool:v- (nth (cadr pr) pts)
                                                    (nth (car pr) pts))))
                                       (* (if (= 0 (rem k 2)) 0.15 -0.15)
                                          doff)))))
    (setq k (1+ k)))
  (pool:dimxend odim)
  (setvar "CLAYER" oldclay)

  ;; corner labels (kept outside the shape -- D is a reflex corner)
  (setq lbls (list "A" "B" "C" "D" "E" "F") k 0)
  (foreach p pts
    (pool:text (pool:lbloff p cen pts (* 2.0 th)) th (nth k lbls) "POOL-NOTES")
    (setq k (1+ k)))

  ;; report table
  (setq rows nil k 0)
  (foreach pr pool:*hexsides*
    (setq rows (cons (list (strcat "SIDE " (nth k pool:*hexsidenames*))
                           (nth k sides)
                           (distance (nth (car pr) pts) (nth (cadr pr) pts)))
                     rows)
          k (1+ k)))
  (if (not pool:*insq*)
      (progn
        (setq k 0)
        (foreach pr pool:*hexdiags*
          (setq rows (cons (list (strcat "CROSS " (nth k pool:*hexdiagnames*))
                                 (nth k diags)
                                 (distance (nth (car pr) pts) (nth (cadr pr) pts)))
                           rows)
                k (1+ k)))))
  (setq rows (reverse rows))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

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
          act (caddr r))
    (pool:text (list x y) h (car r) lay)
    (if tgt
        (progn
          (setq dl (- act tgt)
                ds (strcat (if (< dl 0.0) "" "+") (rtos dl 2 2)))
          (pool:text (list (+ x (* 20.0 h)) y) h (rtos tgt 2 2) lay)
          (pool:text (list (+ x (* 38.0 h)) y) h ds lay))
        ;; NA target: measurement was not taken in the field
        (progn
          (pool:text (list (+ x (* 20.0 h)) y) h "N/A" lay)
          (pool:text (list (+ x (* 38.0 h)) y) h "-" lay)))
    (pool:text (list (+ x (* 29.0 h)) y) h (rtos act 2 2) lay))
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


;;; -------------------- rectangle corner treatments --------------------
;;;
;;;  A rectangle corner may be Square, Rounded (radius) or Diag
;;;  (chamfer).  Side lengths are always measured to the TRUE (sharp)
;;;  corner; the treatment cuts inward from there.  The size typed is:
;;;    Rounded -> the corner RADIUS
;;;    Diag    -> the CHAMFER FACE length (the cut itself)
;;;  In-square pools assume all four corners identical; out-of-square
;;;  pools ask per corner (Enter reuses the previous corner's answer).

;; The two points where a corner's treatment meets the straight sides
;; (toward the previous / next corner) plus, for Rounded, the arc mid.
;; Returns (ePrev eNext arcMid|nil).  Square -> (P P nil).
(defun pool:cornerends (p pp pn type size / uprev unext dp ang t bis cen)
  (setq uprev (pool:unit (pool:v- pp p))
        unext (pool:unit (pool:v- pn p))
        dp (pool:dot uprev unext)
        ang (atan (sqrt (max 0.0 (- 1.0 (* dp dp)))) dp))   ; interior angle
  (cond
    ((= type "Diag")
     (setq t (/ size (* 2.0 (sin (/ ang 2.0)))))            ; face -> edge setback
     (list (pool:v+ p (pool:v* uprev t))
           (pool:v+ p (pool:v* unext t)) nil))
    ((= type "Rounded")
     (setq t (/ (* size (cos (/ ang 2.0))) (sin (/ ang 2.0)))  ; r/tan(ang/2)
           bis (pool:unit (pool:v+ uprev unext))
           cen (pool:v+ p (pool:v* bis (/ size (sin (/ ang 2.0))))))
     (list (pool:v+ p (pool:v* uprev t))
           (pool:v+ p (pool:v* unext t))
           (pool:v- cen (pool:v* bis size))))              ; arc point nearest corner
    (t (list p p nil))))

;; A reference point at corner i of quad q for a cross-dim measurement:
;;   spec = 'true (sharp corner) | 'prev | 'next (treatment ends) |
;;          'mid (chamfer/arc middle).
(defun pool:cornerpoint (q corners i spec / ce)
  (setq ce (pool:cornerends (nth i q)
                            (nth (rem (+ i 3) 4) q)
                            (nth (rem (+ i 1) 4) q)
                            (car (nth i corners)) (cadr (nth i corners))))
  (cond ((eq spec 'prev) (car ce))
        ((eq spec 'next) (cadr ce))
        ((eq spec 'mid) (if (caddr ce) (caddr ce) (pool:mid (car ce) (cadr ce))))
        (t (nth i q))))

;; Draw the rectangle perimeter with corner treatments on layer POOL.
(defun pool:drawrect (q corners / ce i tyi)
  (setq ce (mapcar '(lambda (i)
                      (pool:cornerends (nth i q)
                                       (nth (rem (+ i 3) 4) q)
                                       (nth (rem (+ i 1) 4) q)
                                       (car (nth i corners)) (cadr (nth i corners))))
                   (list 0 1 2 3)))
  (foreach i (list 0 1 2 3)             ; straight sides (eNext(i) -> ePrev(i+1))
    (pool:line (cadr (nth i ce)) (car (nth (rem (+ i 1) 4) ce)) "POOL"))
  (foreach i (list 0 1 2 3)             ; corner treatments
    (setq tyi (car (nth i corners)))
    (cond
      ((= tyi "Diag") (pool:line (car (nth i ce)) (cadr (nth i ce)) "POOL"))
      ((= tyi "Rounded")
       (pool:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce)) "POOL"))))
  ce)

;; Re-draw the guide rectangle's corners with the chosen treatments so
;; the visual matches what will be built.  gq = the guide quad,
;; corners = per-corner (type size), sizes already clamped for display.
;; The four full-length guide sides are replaced by shortened sides
;; plus gray chamfer lines / fillet arcs; the pv assoc side keys are
;; re-pointed at the new side entities.  Returns the updated pv.
(defun pool:pvcorners (pv gq corners / ce i k cc ent)
  (foreach k (list 'ab 'bc 'dc 'da)
    (pool:pvdel (cdr (assoc k pv))))
  (setq ce (mapcar '(lambda (i)
                      (pool:cornerends (nth i gq)
                                       (nth (rem (+ i 3) 4) gq)
                                       (nth (rem (+ i 1) 4) gq)
                                       (car (nth i corners)) (cadr (nth i corners))))
                   (list 0 1 2 3)))
  ;; shortened straight sides (side i runs corner i -> corner i+1)
  (setq i 0)
  (foreach k (list 'ab 'bc 'dc 'da)
    (setq ent (pool:pvadd (pool:pvline (cadr (nth i ce))
                                       (car (nth (rem (+ i 1) 4) ce))))
          pv (subst (cons k (list ent)) (assoc k pv) pv)
          i (1+ i)))
  ;; the corner treatments themselves
  (setq i 0)
  (foreach cc corners
    (cond
      ((= (car cc) "Diag")
       (pool:pvadd (pool:pvline (car (nth i ce)) (cadr (nth i ce)))))
      ((= (car cc) "Rounded")
       (pool:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce))
                   "POOL-NOTES")
       (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))))
    (setq i (1+ i)))
  pv)

;; Prompt one corner's treatment (Enter reuses prevty/prevsz).
(defun pool:askcorner (label prevty prevsz / ty sz)
  (if prevty (initget "Square Rounded Diag") (initget 1 "Square Rounded Diag"))
  (setq ty (getkword (strcat "\n" label " [Square/Rounded/Diag]"
                             (if prevty (strcat " <" prevty ">") "") ": ")))
  (if (null ty) (setq ty prevty))
  (if (= ty "Square")
      (setq sz 0.0)
      (progn
        (initget (if (and prevsz (> prevsz 0.0)) 6 7))
        (setq sz (getdist (strcat "\n" label
                                  (if (= ty "Rounded") " corner radius" " chamfer face length")
                                  (if (and prevsz (> prevsz 0.0))
                                      (strcat " <" (rtos prevsz) ">") "")
                                  ": ")))
        (if (null sz) (setq sz prevsz))))
  (list ty sz))

;; Cross-dim measurement templates for the chosen reference mode.
;; Each entry: (diagkey prompt rowlabel iA specA iC specC).  Ends uses
;; both endpoints on each side of the diagonal.
(defun pool:crosstemplate (cmode)
  (cond
    ((= cmode "Middle")
     (list (list 'ac "Cross dim A-C (to corner middles)" "AC MID" 0 'mid 2 'mid)
           (list 'bd "Cross dim B-D (to corner middles)" "BD MID" 1 'mid 3 'mid)))
    ((= cmode "Ends")
     (list (list 'ac "Cross A-C, B-side (A>B end to C>B end)" "AC B-END" 0 'next 2 'prev)
           (list 'ac "Cross A-C, D-side (A>D end to C>D end)" "AC D-END" 0 'prev 2 'next)
           (list 'bd "Cross B-D, A-side (B>A end to D>A end)" "BD A-END" 1 'prev 3 'next)
           (list 'bd "Cross B-D, C-side (B>C end to D>C end)" "BD C-END" 1 'next 3 'prev)))
    (t
     (list (list 'ac "Cross dim bottom-left to top-right (A-C)" "CROSS A-C" 0 'true 2 'true)
           (list 'bd "Cross dim bottom-right to top-left (B-D)" "CROSS B-D" 1 'true 3 'true)))))

;; Average of a diagonal's raw measurements (bootstrap), or the
;; corner-corrected effective true-corner target using estimate q.
(defun pool:rawavg (xmeas diagkey / sum n)
  (setq sum 0.0 n 0)
  (foreach m xmeas
    (if (and (eq (car m) diagkey) (nth 7 m))
        (setq sum (+ sum (nth 7 m)) n (1+ n))))
  (if (> n 0) (/ sum n) nil))

(defun pool:effcross (q corners xmeas diagkey / sum n ra rc)
  (setq sum 0.0 n 0)
  (foreach m xmeas
    (if (and (eq (car m) diagkey) (nth 7 m))
        (progn
          (setq ra (pool:cornerpoint q corners (nth 3 m) (nth 4 m))
                rc (pool:cornerpoint q corners (nth 5 m) (nth 6 m))
                sum (+ sum (+ (nth 7 m)
                              (- (distance (nth (nth 3 m) q) (nth (nth 5 m) q))
                                 (distance ra rc))))
                n (1+ n)))))
  (if (> n 0) (/ sum n) nil))

;;; -------------------- pool bottom / hopper (rectangle) ---------------
;;;
;;;  Field-sheet letters (plan view):
;;;
;;;      D ------------------------------------ C
;;;      |\        M                           /|
;;;      | htl --------- htr                 /  |
;;;      |  |   hopper    |  \            brkt  |
;;;      |H |G    (G x L) |     \           |   |
;;;      | hbl --------- hbr       \        | E |
;;;      |/        K          \       \   brkb  |
;;;      A ------------------------------------ B
;;;
;;;  H = left end -> hopper, G = hopper length, F = hopper -> slope
;;;  break (CHECK), E = slope break -> right end, M = top -> hopper,
;;;  L = hopper width (CHECK), K = hopper -> bottom.  The primary dims
;;;  are perimeter OFFSETS (H, E, M, K) plus the hopper size G; F and
;;;  L are redundant and reported as checks with their deltas.
;;;  The hopper's left corners tie to the pool's left corners -- to the
;;;  end-wall end of the corner treatment when that corner is cut or
;;;  rounded -- and its right corners tie to the slope-break ends.

;; Intersection of two infinite lines (p1 along d1, p2 along d2).
(defun pool:linex (p1 d1 p2 d2 / den s)
  (setq den (- (* (car d1) (cadr d2)) (* (cadr d1) (car d2))))
  (if (> (abs den) 1.0e-9)
      (progn
        (setq s (/ (- (* (- (car p2) (car p1)) (cadr d2))
                      (* (- (cadr p2) (cadr p1)) (car d2)))
                   den))
        (pool:v+ p1 (pool:v* d1 s)))))

;; The side p->q offset inward (toward cen) by dist, as (point dir).
(defun pool:offline (p q cen dist / n)
  (setq n (pool:unit (pool:perp (pool:v- q p))))
  (if (> (pool:dot (pool:v- (pool:mid p q) cen) n) 0.0)
      (setq n (pool:v* n -1.0)))
  (list (pool:v+ p (pool:v* n dist)) (pool:v- q p)))

;; All hopper geometry for quad + corner treatments + the primary
;; offsets.  Returns an assoc list of named points: hopper corners
;; (hbl htl hbr htr), slope-break ends (brkb brkt), left tie anchors
;; (lab lat), and the measuring-chain points -- horizontal pl phl phr
;; pbrk pr, vertical pb phb pht pt (through the hopper centre).
(defun pool:hopcalc (quad corners h g e m k / a b c d cen hl hr ht hb brk
                                              hbl htl hbr htr brkb brkt
                                              lab lat hc hdir vdir)
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        hl (pool:offline a d cen h)
        hr (pool:offline a d cen (+ h g))
        ht (pool:offline d c cen m)
        hb (pool:offline a b cen k)
        brk (pool:offline b c cen e)
        hbl (pool:linex (car hl) (cadr hl) (car hb) (cadr hb))
        htl (pool:linex (car hl) (cadr hl) (car ht) (cadr ht))
        hbr (pool:linex (car hr) (cadr hr) (car hb) (cadr hb))
        htr (pool:linex (car hr) (cadr hr) (car ht) (cadr ht))
        brkb (pool:linex (car brk) (cadr brk) a (pool:v- b a))
        brkt (pool:linex (car brk) (cadr brk) d (pool:v- c d))
        lab (pool:cornerpoint quad corners 0
                              (if (= (car (nth 0 corners)) "Square") 'true 'prev))
        lat (pool:cornerpoint quad corners 3
                              (if (= (car (nth 3 corners)) "Square") 'true 'next))
        hc (pool:v* (pool:v+ (pool:v+ hbl htl) (pool:v+ hbr htr)) 0.25)
        hdir (pool:v- b a)
        vdir (pool:v- d a))
  (list (list 'hbl hbl) (list 'htl htl) (list 'hbr hbr) (list 'htr htr)
        (list 'brkb brkb) (list 'brkt brkt) (list 'lab lab) (list 'lat lat)
        (list 'pl (pool:linex hc hdir a (pool:v- d a)))
        (list 'phl (pool:linex hc hdir (car hl) (cadr hl)))
        (list 'phr (pool:linex hc hdir (car hr) (cadr hr)))
        (list 'pbrk (pool:linex hc hdir (car brk) (cadr brk)))
        (list 'pr (pool:linex hc hdir b (pool:v- c b)))
        (list 'pb (pool:linex hc vdir a (pool:v- b a)))
        (list 'phb (pool:linex hc vdir (car hb) (cadr hb)))
        (list 'pht (pool:linex hc vdir (car ht) (cadr ht)))
        (list 'pt (pool:linex hc vdir d (pool:v- c d)))))

;; Draw the hopper, slope break and corner ties on layer lay.
(defun pool:hopdraw (gg lay / hbl htl hbr htr brkb brkt lab lat)
  (setq hbl (cadr (assoc 'hbl gg)) htl (cadr (assoc 'htl gg))
        hbr (cadr (assoc 'hbr gg)) htr (cadr (assoc 'htr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg))
        lab (cadr (assoc 'lab gg)) lat (cadr (assoc 'lat gg)))
  (pool:line hbl htl lay)
  (pool:line htl htr lay)
  (pool:line htr hbr lay)
  (pool:line hbr hbl lay)
  (pool:line brkb brkt lay)
  (pool:line lab hbl lay)
  (pool:line lat htl lay)
  (pool:line htr brkt lay)
  (pool:line hbr brkb lay))

;; Gray field-sheet guide inside the fitted pool: nominal hopper,
;; break line and ties (solid), plus a dashed lettered measuring tie
;; per input.  Returns the highlight assoc keyed by letter.
(defun pool:hopguide (quad corners th / len wid gg pr tl e pv)
  (setq len (distance (car quad) (cadr quad))
        wid (distance (car quad) (cadddr quad))
        gg (pool:hopcalc quad corners
                         (* 0.12 len) (* 0.20 len) (* 0.40 len)
                         (* 0.25 wid) (* 0.25 wid)))
  (foreach pr (list (list 'hbl 'htl) (list 'htl 'htr) (list 'htr 'hbr)
                    (list 'hbr 'hbl) (list 'brkb 'brkt) (list 'lab 'hbl)
                    (list 'lat 'htl) (list 'htr 'brkt) (list 'hbr 'brkb))
    (pool:pvadd (pool:pvline (cadr (assoc (car pr) gg))
                             (cadr (assoc (cadr pr) gg)))))
  (setq pv nil)
  (foreach tl (list (list "H" 'pl 'phl) (list "G" 'phl 'phr)
                    (list "F" 'phr 'pbrk) (list "E" 'pbrk 'pr)
                    (list "M" 'pht 'pt) (list "L" 'phb 'pht)
                    (list "K" 'pb 'phb))
    (setq e (pool:pvadd (pool:pvlined (cadr (assoc (cadr tl) gg))
                                      (cadr (assoc (caddr tl) gg))))
          pv (cons (cons (car tl) (list e)) pv))
    (pool:text (pool:v+ (pool:mid (cadr (assoc (cadr tl) gg))
                                  (cadr (assoc (caddr tl) gg)))
                        (list (* 0.5 th) (* 0.5 th)))
               (* 1.2 th) (car tl) "POOL-NOTES")
    (pool:pvadd (pool:setcol (entlast) pool:*pv-col*)))
  pv)

;; Guided pool-bottom phase (rectangle pipeline).  Shows the lettered
;; guide, prompts H G F E M L K, draws the real bottom on POOL-BOTTOM
;; and chain-dimensions it.  Returns the report rows (nil if skipped).
(defun pool:hopper (quad corners doff th / pv h g f e m l k gg rows tl
                                           xmin xmax ymin ymax odl)
  (initget "Yes No")
  (if (= "No" (getkword "\nAdd pool bottom (hopper) detail? [Yes/No] <Yes>: "))
      nil
      (progn
        ;; make sure the whole pool is in view for the guide
        (setq xmin (apply 'min (mapcar 'car quad))
              xmax (apply 'max (mapcar 'car quad))
              ymin (apply 'min (mapcar 'cadr quad))
              ymax (apply 'max (mapcar 'cadr quad)))
        (command "_.ZOOM" "_Window"
                 (pool:wp (list (- xmin doff) (- ymin doff)))
                 (pool:wp (list (+ xmax doff) (+ ymax doff))))
        (setq pv (pool:hopguide quad corners th))
        (princ "\nPool bottom -- offsets from the perimeter; the RED tie is the one being asked for.")
        (setq h (pool:askh "H - left end to hopper" (cdr (assoc "H" pv)))
              g (pool:askh "G - hopper length" (cdr (assoc "G" pv)))
              f (pool:askh "F - hopper to slope break (check)" (cdr (assoc "F" pv)))
              e (pool:askh "E - slope break to right end" (cdr (assoc "E" pv)))
              m (pool:askh "M - top side to hopper" (cdr (assoc "M" pv)))
              l (pool:askh "L - hopper width (check)" (cdr (assoc "L" pv)))
              k (pool:askh "K - hopper to bottom side" (cdr (assoc "K" pv))))
        (pool:pvkill)
        (pool:layer "POOL-BOTTOM" 5)
        (setq gg (pool:hopcalc quad corners h g e m k))
        (pool:hopdraw gg "POOL-BOTTOM")
        ;; chain dimensions along the two centerlines, like the sheet
        (setq odl (getvar "CLAYER"))
        (setvar "CLAYER" "DIMENSION")
        (foreach tl (list (list 'pl 'phl) (list 'phl 'phr) (list 'phr 'pbrk)
                          (list 'pbrk 'pr) (list 'pht 'pt) (list 'phb 'pht)
                          (list 'pb 'phb))
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:mid (cadr (assoc (car tl) gg))
                                 (cadr (assoc (cadr tl) gg)))))
        (setvar "CLAYER" odl)
        (setq rows (list
          (list "HOP H" h (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))))
          (list "HOP G" g (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))))
          (list "HOP F CHECK" f (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))))
          (list "HOP E" e (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))))
          (list "HOP M" m (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))))
          (list "HOP L CHECK" l (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))))
          (list "HOP K" k (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))))))
        rows)))

;;; -------------------- rectangle / oval flow --------------------------

;; Full guided flow for the quad-based pools: preview, prompts, fit,
;; draw, dimension and report.  Caller handles sysvars/undo/zoom.
(defun pool:quadflow (ptype / oldclay pv
                             tp bo le ri dac dbd totl lrad rrad
                             corners cmode anycut cc prevty prevsz lbl
                             gq gcorners xmeas tm hl val m rpa rpb pass
                             fitres quad failed a b c d cen meas notes tri
                             doff th endoff pr odim k
                             midl midr ml mr tipl tipr
                             allpts xmax ymax ymin rows)
  (setq oldclay (getvar "CLAYER"))

  ;; -------------------------------------- guide preview + input
  (setq pv (pool:preview ptype))
  (command "_.ZOOM" "_Window"
           (pool:wp (list -170.0 -60.0)) (pool:wp (list 530.0 240.0)))
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C top-right, D top-left.")

  (setq tp  (pool:askh "Side length TOP (D-C)" (cdr (assoc 'dc pv)))
        bo  (pool:askh "Side length BOTTOM (A-B)" (cdr (assoc 'ab pv)))
        le  (pool:askh "End length LEFT (A-D)" (cdr (assoc 'da pv)))
        ri  (pool:askh "End length RIGHT (B-C)" (cdr (assoc 'bc pv))))

  ;; -------- corner treatments (rectangle only; side lengths are to
  ;; the TRUE corner, treatments cut inward)
  (if (= ptype "Rectangle")
      (if pool:*insq*
          (progn                        ; in-square: one answer for all 4
            (setq cc (pool:askcorner "All corners (assumed identical)" nil nil)
                  corners (list cc cc cc cc)))
          (progn                        ; out-of-square: per corner, Enter reuses
            (princ "\n(per-corner treatment; press Enter to reuse the previous corner)")
            (setq corners nil prevty nil prevsz nil)
            (foreach lbl (list "A" "B" "C" "D")
              (setq cc (pool:askcorner (strcat "Corner " lbl) prevty prevsz)
                    prevty (car cc) prevsz (cadr cc)
                    corners (cons cc corners)))
            (setq corners (reverse corners))))
      (setq corners (list (list "Square" 0.0) (list "Square" 0.0)
                          (list "Square" 0.0) (list "Square" 0.0))))
  (setq anycut nil)
  (foreach cc corners (if (/= (car cc) "Square") (setq anycut t)))

  ;; update the guide so the corners look like what will be built
  ;; (display sizes clamped so oversized inputs can't fold the guide)
  (setq gq (list (list 0.0 0.0) (list 360.0 0.0)
                 (list 360.0 180.0) (list 0.0 180.0))
        gcorners (mapcar '(lambda (cc) (list (car cc) (min (cadr cc) 60.0)))
                         corners))
  (if anycut (setq pv (pool:pvcorners pv gq gcorners)))

  ;; -------- cross-dim reference mode (only when corners are cut and
  ;; the pool is out-of-square)
  (setq cmode "Corner")
  (if (and (not pool:*insq*) anycut)
      (progn
        (initget 1 "Corner Middle Ends")
        (setq cmode (getkword
                      "\nCut corners -- cross dims measured from [Corner/Middle/Ends]: "))))

  ;; -------- cross dims (out-of-square only), per the reference mode.
  ;; The corner-to-corner guide diagonals are retired and one dashed
  ;; guide line is drawn per measurement between its actual reference
  ;; points, so Middle/Ends prompts highlight exactly what gets taped.
  (setq xmeas nil)
  (if (not pool:*insq*)
      (progn
        (pool:pvdel (cdr (assoc 'ac pv)))
        (pool:pvdel (cdr (assoc 'bd pv)))
        (foreach tm (pool:crosstemplate cmode)
          (setq rpa (pool:cornerpoint gq gcorners (nth 3 tm) (nth 4 tm))
                rpb (pool:cornerpoint gq gcorners (nth 5 tm) (nth 6 tm))
                hl (pool:pvadd (pool:pvlined rpa rpb))
                val (pool:askhx (cadr tm) (list hl))
                xmeas (cons (append tm (list val)) xmeas))))
      (princ "\nIn-square: building true to the side measurements (no cross dims)."))
  (setq xmeas (reverse xmeas))

  (if (= ptype "Oval")
      (setq totl (pool:askh "Total pool length (arc tip to arc tip)" (cdr (assoc 'tot pv)))
            lrad (pool:askh "LEFT oval end radius" (cdr (assoc 'lrad pv)))
            rrad (pool:askh "RIGHT oval end radius" (cdr (assoc 'rrad pv)))))

  ;; the guide has served its purpose -- replace it with the true pool
  (pool:pvkill)

  ;; ------------------------------------------------ fit the body
  ;; bootstrap the true-corner cross targets from the raw measurements,
  ;; then (for cut corners) refine them against the fitted corner
  ;; reference points and re-fit.
  (princ "\nFitting pool body to the measurements ...")
  (setq dac (pool:rawavg xmeas 'ac)
        dbd (pool:rawavg xmeas 'bd)
        fitres (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
        quad (car fitres)
        failed (cadr fitres))
  (if (/= cmode "Corner")
      (progn
        (setq pass 0)
        (while (< pass 2)
          (setq dac (pool:effcross quad corners xmeas 'ac)
                dbd (pool:effcross quad corners xmeas 'bd)
                fitres (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
                quad (car fitres)
                failed (cadr fitres)
                pass (1+ pass)))))
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        meas (pool:quadmeas quad)
        notes nil)

  ;; dashed linetype + scale for the reference lines
  (setq pool:*dashlt* (pool:ltload "DASHED")
        pool:*lts* (max 1.0 (/ (max bo tp le ri) 15.0)))

  ;; -------------------------------- pool body / perimeter (layer POOL)
  ;; Rectangle draws its perimeter with corner treatments; the oval
  ;; body end lines are reference only (dashed) and the perimeter
  ;; closes through the arcs instead.
  (if (= ptype "Rectangle")
      (pool:drawrect quad corners)
      (progn
        (pool:line a b "POOL")
        (pool:line c d "POOL")
        (pool:lined b c)
        (pool:lined d a)))

  ;; -------------------------------------- exact two-triangle figure
  ;; (needs the A-C cross dim -- skipped when it was NA)
  (setq tri (if dac (pool:triquad bo tp le ri dac) nil))
  (cond
    (tri
     (pool:line (car tri) (cadr tri) "POOL-TRIANGLES")
     (pool:line (cadr tri) (caddr tri) "POOL-TRIANGLES")
     (pool:line (car tri) (caddr tri) "POOL-TRIANGLES") ; shared A-C
     (pool:line (caddr tri) (cadddr tri) "POOL-TRIANGLES")
     (pool:line (cadddr tri) (car tri) "POOL-TRIANGLES"))
    (dac
     (setq notes (cons "TRIANGLE CHECK IMPOSSIBLE - VERIFY MEASUREMENTS" notes)))
    (t
     (princ "\nCross A-C not measured -- triangle check figure skipped.")))

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

  ;; ------------------------------------------------ extents
  (setq allpts (append quad
                       (if tri tri nil)
                       (if tipl (list tipl tipr) nil))
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
  ;; provided cross dims, between their reference points, in the CROSS
  ;; DIMENSION style when the drawing has one
  (setq odim (pool:dimxbegin) k 0)
  (foreach m xmeas
    (if (nth 7 m)
        (progn
          (setq rpa (pool:cornerpoint quad corners (nth 3 m) (nth 4 m))
                rpb (pool:cornerpoint quad corners (nth 5 m) (nth 6 m)))
          (pool:dimalg rpa rpb
                       (pool:v+ (pool:mid rpa rpb)
                                (pool:v* (pool:unit (pool:perp (pool:v- rpb rpa)))
                                         (* (if (= 0 (rem k 2)) 0.2 -0.2) doff))))))
    (setq k (1+ k)))
  (pool:dimxend odim)
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
                   (list "RIGHT END (B-C)" ri (cadddr meas))))
  ;; each cross measurement vs the actual distance between its
  ;; reference points in the fitted drawing
  (foreach m xmeas
    (setq rows (append rows
                       (list (list (nth 2 m) (nth 7 m)
                                   (distance (pool:cornerpoint quad corners (nth 3 m) (nth 4 m))
                                             (pool:cornerpoint quad corners (nth 5 m) (nth 6 m))))))))
  (if tri
      (setq rows (append rows
                         (list (list "TRI CHECK B-D" dbd
                                     (distance (cadr tri) (cadddr tri)))))))
  (if (= ptype "Oval")
      (setq rows (append rows
                         (list (list "TOTAL LENGTH" totl (distance tipl tipr))))))
  ;; -------------------------------- pool bottom (rectangle pipeline)
  (if (= ptype "Rectangle")
      (setq rows (append rows (pool:hopper quad corners doff th))))
  ;; corner treatments
  (if (and (= ptype "Rectangle") anycut)
      (if pool:*insq*
          (setq rows (append rows
                             (list (list (strcat "CORNERS " (car (car corners)))
                                         (cadr (car corners)) (cadr (car corners))))))
          (foreach lbl (list (list "A" 0) (list "B" 1) (list "C" 2) (list "D" 3))
            (if (/= (car (nth (cadr lbl) corners)) "Square")
                (setq rows (append rows
                                   (list (list (strcat "COR " (car lbl) " " (car (nth (cadr lbl) corners)))
                                               (cadr (nth (cadr lbl) corners))
                                               (cadr (nth (cadr lbl) corners))))))))))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES")
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- main command -----------------------------------

(defun c:POOL ( / *error* oldcmd oldos oldclay ptype base)

  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg t) "function cancelled")
             (/= (strcase msg t) "quit / exit abort"))
        (princ (strcat "\nPOOL error: " msg)))
    (pool:pvkill)
    (if oldclay (setvar "CLAYER" oldclay))
    (if oldos (setvar "OSMODE" oldos))
    (command "_.UNDO" "_End")
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (princ))

  (setq oldcmd (getvar "CMDECHO")
        oldos (getvar "OSMODE")
        oldclay (getvar "CLAYER"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setvar "OSMODE" 0)

  ;; In-square pools are built true to the side measurements and need
  ;; no diagonals; out-of-square pools take the usual cross-dim route.
  (initget 1 "Insquare Outofsquare")
  (setq pool:*insq* (= "Insquare"
                       (getkword "\nIs the pool in-square or out-of-square [Insquare/Outofsquare]: ")))
  (if pool:*insq*
      (princ "\nIn-square: building true to the side measurements (no cross dims needed)."))

  ;; L = true L; LAzyl = lazy L (type LA to select it)
  (initget 1 "Rectangle Oval Grecian L LAzyl")
  (setq ptype (getkword "\nPool shape [Rectangle/Oval/Grecian/L/LAzyl]: "))

  (setq base (getpoint "\nInsertion base point <0,0>: ")
        pool:*base* (if base (list (car base) (cadr base)) (list 0.0 0.0)))

  ;; ------------------------------------------------ layers
  (pool:layer "POOL" 4)
  (pool:layer "POOL-TRIANGLES" 1)
  (pool:layer "DIMENSION" 2)
  (pool:layer "POOL-NOTES" 3)

  ;; dashed linetype up front so the guide's cross dims draw dashed
  ;; (the flows re-scale pool:*lts* to the real pool size later)
  (setq pool:*dashlt* (pool:ltload "DASHED")
        pool:*lts* 12.0)

  (cond
    ((= ptype "L") (pool:hexflow nil))
    ((= ptype "LAzyl") (pool:hexflow t))
    ((= ptype "Grecian") (pool:grecflow))
    (t (pool:quadflow ptype)))

  ;; ------------------------------------------------ finish
  (command "_.ZOOM" "_Extents")
  (setvar "OSMODE" oldos)
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (princ))


(princ "\nPOOL.LSP loaded.  Type POOL to lay out a pool.")
(princ)
