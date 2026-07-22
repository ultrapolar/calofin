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

;; Give the just-drawn dimension a dashed linetype override so cross
;; dims read apart from the regular dims at a glance.
(defun pool:dimdash ( / e ed)
  (setq e (entlast))
  (if (and e (setq ed (entget e)) (/= pool:*dashlt* "CONTINUOUS"))
      (progn
        (setq ed (if (assoc 6 ed)
                     (subst (cons 6 pool:*dashlt*) (assoc 6 ed) ed)
                     (append ed (list (cons 6 pool:*dashlt*)))))
        (setq ed (if (assoc 48 ed)
                     (subst (cons 48 pool:*lts*) (assoc 48 ed) ed)
                     (append ed (list (cons 48 pool:*lts*)))))
        (entmod ed)
        (entupd e))))

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
(setq pool:*grecnpts* (list (list 0.0 0.0) (list 360.0 0.0) (list 410.0 55.0)
                            (list 410.0 125.0) (list 360.0 180.0)
                            (list 0.0 180.0) (list -50.0 125.0)
                            (list -50.0 55.0)))

(defun pool:grecpreview (crosses / npts cen p q e c ent all pv k)
  (setq npts pool:*grecnpts*
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
;; Resolve the overall-sheet letters against the overalls: S/T close
;; against B (T absorbs any difference), S1/V against A (V absorbs);
;; NA entries are derived, and with a whole pair NA a nominal split is
;; used.  Returns (S T S1 V).
(defun pool:grecov (aov bov sraw traw s1raw vraw / s tv s1 v)
  (cond
    (sraw (setq s sraw tv (- bov (* 2.0 sraw))))
    (traw (setq s (/ (- bov traw) 2.0) tv traw))
    (t (setq s (/ bov 8.0) tv (* 0.75 bov))))
  (cond
    (s1raw (setq s1 s1raw v (- aov (* 2.0 s1raw))))
    (vraw (setq s1 (/ (- aov vraw) 2.0) v vraw))
    (t (setq s1 (/ aov 6.0) v (* aov (/ 2.0 3.0)))))
  (list s tv s1 v))

;; Overall-sheet guide ties (B T S A S1 V S2) laid around the nominal
;; grecian guide like the field sheet.  Returns the highlight assoc.
(defun pool:grecovties ( / pv)
  (setq pv (list
    (pool:pvtie (list -50.0 240.0) (list 410.0 240.0) "B" 10.0)
    (pool:pvtie (list 0.0 215.0) (list 360.0 215.0) "T" 10.0)
    (pool:pvtie (list -50.0 215.0) (list 0.0 215.0) "S" 10.0)
    (pool:pvtie (list -95.0 0.0) (list -95.0 180.0) "A" 10.0)
    (pool:pvtie (list -72.0 125.0) (list -72.0 180.0) "S1" 10.0)
    (pool:pvtie (list -72.0 55.0) (list -72.0 125.0) "V" 10.0)
    (pool:pvtie (list 375.0 -15.0) (list 425.0 40.0) "S2" 10.0)))
  pv)

(defun pool:grecflow ( / oldclay mode crosses pv imeth pvo
                       braw araw traw sraw s1raw vraw s2raw
                       ovres sv tv s1v vov hyp u2 vv2 bact aact sact s1act
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

  ;; perimeter input method: measure every edge, or the overall sheet
  ;; (A/B overalls with the sides assumed symmetric)
  (initget 1 "Measured Overall")
  (setq imeth (getkword "\nGrecian perimeter input [Measured/Overall]: "))

  (setq pv (pool:grecpreview crosses))
  (if (= imeth "Overall") (setq pvo (pool:grecovties)))
  (command "_.ZOOM" "_Window"
           (pool:wp (list -130.0 -80.0)) (pool:wp (list 470.0 310.0)))
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A/B bottom, C/D top, LT/LB left tips, RT/RB right tips.")

  ;; -------- body + ends: measured edges, or the overall sheet
  (if (= imeth "Overall")
      (progn
        (princ "\nOverall sheet -- symmetric grecian; the RED tie is being asked for.")
        (setq braw (pool:askh "B - overall length" (cdr (assoc "B" pvo)))
              araw (pool:askh "A - overall width" (cdr (assoc "A" pvo)))
              traw (pool:askhx "T - top side length" (cdr (assoc "T" pvo)))
              sraw (pool:askhx "S - corner cut along the side" (cdr (assoc "S" pvo)))
              s1raw (pool:askhx "S1 - corner cut down the end" (cdr (assoc "S1" pvo)))
              vraw (pool:askhx "V - end width" (cdr (assoc "V" pvo)))
              s2raw (pool:askhx "S2 - corner cut face (check)" (cdr (assoc "S2" pvo)))
              ovres (pool:grecov araw braw sraw traw s1raw vraw)
              sv (car ovres) tv (cadr ovres)
              s1v (caddr ovres) vov (cadddr ovres)
              hyp (sqrt (+ (* sv sv) (* s1v s1v)))
              bo tv tp tv le araw ri araw
              ltd hyp lbd hyp rtd hyp rbd hyp
              lew vov rew vov))
      (if pool:*insq*
      (setq bo  (pool:askh "Side (top & bottom)"
                           (append (cdr (assoc 'ab pv)) (cdr (assoc 'cd pv))))
            tp  bo
            le  (pool:askh "Body end (left & right, A-D / B-C)"
                           (append (cdr (assoc 'ad pv)) (cdr (assoc 'bc pv))))
            ri  le
            ltd (pool:askh "LEFT end diagonals (top & bottom)"
                           (append (cdr (assoc 'ltd pv)) (cdr (assoc 'lbd pv))))
            lbd ltd
            lew (pool:askh "LEFT end width (LT-LB)" (cdr (assoc 'lew pv)))
            rtd (pool:askh "RIGHT end diagonals (top & bottom)"
                           (append (cdr (assoc 'rtd pv)) (cdr (assoc 'rbd pv))))
            rbd rtd
            rew (pool:askh "RIGHT end width (RT-RB)" (cdr (assoc 'rew pv))))
      (setq bo  (pool:askh "Side BOTTOM (A-B)" (cdr (assoc 'ab pv)))
            tp  (pool:askh "Side TOP (D-C)" (cdr (assoc 'cd pv)))
            le  (pool:askh "End LEFT (A-D)" (cdr (assoc 'ad pv)))
            ri  (pool:askh "End RIGHT (B-C)" (cdr (assoc 'bc pv)))
            ltd (pool:askh "LEFT end diagonal TOP (D-LT)" (cdr (assoc 'ltd pv)))
            lbd (pool:askh "LEFT end diagonal BOTTOM (A-LB)" (cdr (assoc 'lbd pv)))
            lew (pool:askh "LEFT end width (LT-LB)" (cdr (assoc 'lew pv)))
            rtd (pool:askh "RIGHT end diagonal TOP (C-RT)" (cdr (assoc 'rtd pv)))
            rbd (pool:askh "RIGHT end diagonal BOTTOM (B-RB)" (cdr (assoc 'rbd pv)))
            rew (pool:askh "RIGHT end width (RT-RB)" (cdr (assoc 'rew pv))))))

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
        (progn
          (pool:dimalg (nth (car cc) pts) (nth (cadr cc) pts)
                       (pool:v+ (pool:mid (nth (car cc) pts) (nth (cadr cc) pts))
                                (pool:v* (pool:unit
                                           (pool:perp (pool:v- (nth (cadr cc) pts)
                                                               (nth (car cc) pts))))
                                         (* (if (= 0 (rem k 2)) 0.12 -0.12) doff))))
          (pool:dimdash)))
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
  ;; overall-sheet letters vs the fitted shape
  (if (= imeth "Overall")
      (progn
        (setq u2 (pool:v- (nth 1 pts) (nth 0 pts))
              vv2 (pool:v- (nth 5 pts) (nth 0 pts))
              bact (distance
                     (pool:linex cen u2 (nth 7 pts) (pool:v- (nth 6 pts) (nth 7 pts)))
                     (pool:linex cen u2 (nth 2 pts) (pool:v- (nth 3 pts) (nth 2 pts))))
              aact (distance
                     (pool:linex cen vv2 (nth 0 pts) u2)
                     (pool:linex cen vv2 (nth 5 pts) (pool:v- (nth 4 pts) (nth 5 pts))))
              sact (abs (pool:dot (pool:v- (nth 6 pts) (nth 5 pts)) (pool:unit u2)))
              s1act (abs (pool:dot (pool:v- (nth 6 pts) (nth 5 pts)) (pool:unit vv2))))
        (setq rows (append rows (list
          (list "OV B" braw bact)
          (list "OV A" araw aact)
          (list "OV T" traw (distance (nth 5 pts) (nth 4 pts)))
          (list "OV S" sraw sact)
          (list "OV S1" s1raw s1act)
          (list "OV V" vraw (distance (nth 6 pts) (nth 7 pts)))
          (list "OV S2" s2raw (distance (nth 5 pts) (nth 6 pts))))))))
  ;; -------- pool bottom (interior pipeline)
  (setq rows (append rows (pool:hopgrecdsp pts doff th)))
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
(setq pool:*hexdiags* (list '(0 2) '(1 3) '(2 4) '(3 5) '(0 4) '(1 5)
                            '(0 3) '(1 4) '(2 5)))
(setq pool:*hexdiagnames* (list "A-C" "B-D" "C-E" "D-F" "A-E" "B-F"
                                "A-D" "B-E" "C-F"))

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
        (setq keys (list 'ac 'bd 'ce 'df 'ae 'bf 'ad 'be 'cf) k 0)
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
                            odim rows lbls dv mquad sq4)
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
            (list nil nil nil nil nil nil nil nil nil)
            (list (pool:askhx "Cross dim A-C" (cdr (assoc 'ac pv)))
                  (pool:askhx "Cross dim B-D" (cdr (assoc 'bd pv)))
                  (pool:askhx "Cross dim C-E" (cdr (assoc 'ce pv)))
                  (pool:askhx "Cross dim D-F" (cdr (assoc 'df pv)))
                  (pool:askhx "Cross dim A-E" (cdr (assoc 'ae pv)))
                  (pool:askhx "Cross dim B-F" (cdr (assoc 'bf pv)))
                  (pool:askhx "Cross dim A-D" (cdr (assoc 'ad pv)))
                  (pool:askhx "Cross dim B-E" (cdr (assoc 'be pv)))
                  (pool:askhx "Cross dim C-F" (cdr (assoc 'cf pv))))))
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
        (progn
          (pool:dimalg (nth (car pr) pts) (nth (cadr pr) pts)
                       (pool:v+ (pool:mid (nth (car pr) pts) (nth (cadr pr) pts))
                                (pool:v* (pool:unit
                                           (pool:perp
                                             (pool:v- (nth (cadr pr) pts)
                                                      (nth (car pr) pts))))
                                         (* (if (= 0 (rem k 2)) 0.15 -0.15)
                                            doff))))
          (pool:dimdash)))
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

  ;; -------- standard hopper in the main section (no sport for L).
  ;; D' = the virtual main-section corner where the left side (F-A)
  ;; meets the main-top line (C-D); the hopper anchors off the main
  ;; rectangle A-B-C-D' and its left corners tie to A and D'.
  (initget "Yes No")
  (if (/= "No" (getkword "\nAdd pool bottom (hopper) detail? [Yes/No] <Yes>: "))
      (progn
        (setq dv (pool:linex (nth 5 pts) (pool:v- (nth 0 pts) (nth 5 pts))
                             (nth 3 pts) (pool:v- (nth 2 pts) (nth 3 pts)))
              mquad (list (nth 0 pts) (nth 1 pts) (nth 2 pts) dv)
              sq4 (list (list "Square" 0.0) (list "Square" 0.0)
                        (list "Square" 0.0) (list "Square" 0.0)))
        (command "_.ZOOM" "_Window"
                 (pool:wp (list (- (apply 'min (mapcar 'car mquad)) doff)
                                (- (apply 'min (mapcar 'cadr mquad)) doff)))
                 (pool:wp (list (+ (apply 'max (mapcar 'car mquad)) doff)
                                (+ (apply 'max (mapcar 'cadr mquad)) doff))))
        (setq rows (append rows (pool:hopnormal mquad sq4 doff th)))))

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
(defun pool:cornerends (p pp pn ctype size / uprev unext dp ang sb bis cen)
  (setq uprev (pool:unit (pool:v- pp p))
        unext (pool:unit (pool:v- pn p))
        dp (pool:dot uprev unext)
        ang (atan (sqrt (max 0.0 (- 1.0 (* dp dp)))) dp))   ; interior angle
  (cond
    ((= ctype "Diag")
     (setq sb (/ size (* 2.0 (sin (/ ang 2.0)))))           ; face -> edge setback
     (list (pool:v+ p (pool:v* uprev sb))
           (pool:v+ p (pool:v* unext sb)) nil))
    ((= ctype "Rounded")
     (setq sb (/ (* size (cos (/ ang 2.0))) (sin (/ ang 2.0)))  ; r/tan(ang/2)
           bis (pool:unit (pool:v+ uprev unext))
           cen (pool:v+ p (pool:v* bis (/ size (sin (/ ang 2.0))))))
     (list (pool:v+ p (pool:v* uprev sb))
           (pool:v+ p (pool:v* unext sb))
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
;; Returns the list of fillet-arc entity names per corner (nil where
;; the corner is square or chamfered) for the corner dimensions.
(defun pool:drawrect (q corners / ce i tyi arcs)
  (setq ce (mapcar '(lambda (i)
                      (pool:cornerends (nth i q)
                                       (nth (rem (+ i 3) 4) q)
                                       (nth (rem (+ i 1) 4) q)
                                       (car (nth i corners)) (cadr (nth i corners))))
                   (list 0 1 2 3)))
  (foreach i (list 0 1 2 3)             ; straight sides (eNext(i) -> ePrev(i+1))
    (pool:line (cadr (nth i ce)) (car (nth (rem (+ i 1) 4) ce)) "POOL"))
  (setq arcs nil)
  (foreach i (list 0 1 2 3)             ; corner treatments
    (setq tyi (car (nth i corners)))
    (cond
      ((= tyi "Diag")
       (pool:line (car (nth i ce)) (cadr (nth i ce)) "POOL")
       (setq arcs (cons nil arcs)))
      ((= tyi "Rounded")
       (pool:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce)) "POOL")
       (setq arcs (cons (entlast) arcs)))
      (t (setq arcs (cons nil arcs)))))
  (reverse arcs))

;; Corner annotations for the rectangle.  In-square pools get a single
;; "Typ." note at the bottom-right corner (B): the radius or chamfer
;; measurement with a Typ. suffix, or a 90-degree leader for square
;; corners.  Out-of-square pools dim every corner individually --
;; radius dim, chamfer dim, or the ACTUAL angular dimension for a
;; square corner.  Assumes CLAYER is already DIMENSION.
(defun pool:dimcorners (quad corners arcs cen doff / ilist sfx i cc ce p pp pn
                                                    ty outd am fm p1 p2)
  (if pool:*insq*
      (setq ilist (list 1) sfx " Typ.")
      (setq ilist (list 0 1 2 3) sfx ""))
  (foreach i ilist
    (setq p (nth i quad)
          pp (nth (rem (+ i 3) 4) quad)
          pn (nth (rem (+ i 1) 4) quad)
          cc (nth i corners)
          ty (car cc)
          ce (pool:cornerends p pp pn ty (cadr cc))
          outd (pool:unit (pool:v- p cen)))
    (cond
      ((= ty "Rounded")
       (setq am (caddr ce))
       (if (= sfx "")
           (command "_.DIMRADIUS" (list (nth i arcs) (pool:wp am))
                    (pool:wp (pool:v+ am (pool:v* outd (* 0.9 doff)))))
           (command "_.DIMRADIUS" (list (nth i arcs) (pool:wp am))
                    "_T" (strcat "<>" sfx)
                    (pool:wp (pool:v+ am (pool:v* outd (* 0.9 doff)))))))
      ((= ty "Diag")
       (setq fm (pool:mid (car ce) (cadr ce)))
       (if (= sfx "")
           (command "_.DIMALIGNED" (pool:wp (car ce)) (pool:wp (cadr ce))
                    (pool:wp (pool:v+ fm (pool:v* outd (* 0.5 doff)))))
           (command "_.DIMALIGNED" (pool:wp (car ce)) (pool:wp (cadr ce))
                    "_T" (strcat "<>" sfx)
                    (pool:wp (pool:v+ fm (pool:v* outd (* 0.5 doff)))))))
      (t                                ; Square
       (if (= sfx "")
           (progn                       ; the actual corner angle
             (setq p1 (pool:v+ p (pool:v* (pool:unit (pool:v- pp p)) (* 0.8 doff)))
                   p2 (pool:v+ p (pool:v* (pool:unit (pool:v- pn p)) (* 0.8 doff)))
                   fm (pool:v+ p (pool:v* (pool:unit (pool:v- cen p)) doff)))
             (command "_.DIMANGULAR" ""
                      (pool:wp p) (pool:wp p1) (pool:wp p2) (pool:wp fm)))
           (command "_.LEADER" (pool:wp p)
                    (pool:wp (pool:v+ p (pool:v* outd (* 1.2 doff))))
                    "" "90%%d Typ." ""))))))

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
                                              lab1 lab2 lat1 lat2 hc hdir vdir
                                              hc2 rc)
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
        ;; both ends of each left corner treatment (Square -> both ends
        ;; coincide with the true corner)
        lab1 (pool:cornerpoint quad corners 0 'prev)
        lab2 (pool:cornerpoint quad corners 0 'next)
        lat1 (pool:cornerpoint quad corners 3 'next)
        lat2 (pool:cornerpoint quad corners 3 'prev)
        hc (pool:v* (pool:v+ (pool:v+ hbl htl) (pool:v+ hbr htr)) 0.25)
        hdir (pool:v- b a)
        vdir (pool:v- d a)
        ;; H/G/F/E chain sits below the hopper centre by 12" or L/6
        ;; (2/3 down from the top of L), whichever is closer; the
        ;; M/L/K chain sits 12" right of the hopper's right edge
        hc2 (pool:v- hc (pool:v* (pool:unit vdir)
                                 (min 12.0 (/ (distance hbr htr) 6.0))))
        rc (pool:offline a d cen (+ h g 12.0)))
  (list (list 'hbl hbl) (list 'htl htl) (list 'hbr hbr) (list 'htr htr)
        (list 'brkb brkb) (list 'brkt brkt)
        (list 'lab1 lab1) (list 'lab2 lab2)
        (list 'lat1 lat1) (list 'lat2 lat2)
        (list 'pl (pool:linex hc2 hdir a (pool:v- d a)))
        (list 'phl (pool:linex hc2 hdir (car hl) (cadr hl)))
        (list 'phr (pool:linex hc2 hdir (car hr) (cadr hr)))
        (list 'pbrk (pool:linex hc2 hdir (car brk) (cadr brk)))
        (list 'pr (pool:linex hc2 hdir b (pool:v- c b)))
        (list 'pb (pool:linex (car rc) (cadr rc) a (pool:v- b a)))
        (list 'phb (pool:linex (car rc) (cadr rc) (car hb) (cadr hb)))
        (list 'pht (pool:linex (car rc) (cadr rc) (car ht) (cadr ht)))
        (list 'pt (pool:linex (car rc) (cadr rc) d (pool:v- c d)))))

;; Draw the hopper, slope break and corner ties on layer lay.  Each
;; hopper left corner ties to BOTH ends of its pool corner treatment
;; (one line when the corner is square and the ends coincide).
(defun pool:hopdraw (gg lay / hbl htl hbr htr brkb brkt lab1 lab2 lat1 lat2)
  (setq hbl (cadr (assoc 'hbl gg)) htl (cadr (assoc 'htl gg))
        hbr (cadr (assoc 'hbr gg)) htr (cadr (assoc 'htr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg))
        lab1 (cadr (assoc 'lab1 gg)) lab2 (cadr (assoc 'lab2 gg))
        lat1 (cadr (assoc 'lat1 gg)) lat2 (cadr (assoc 'lat2 gg)))
  (pool:line hbl htl lay)
  (pool:line htl htr lay)
  (pool:line htr hbr lay)
  (pool:line hbr hbl lay)
  (pool:line brkb brkt lay)
  (pool:line lab1 hbl lay)
  (if (> (distance lab1 lab2) 1.0e-6) (pool:line lab2 hbl lay))
  (pool:line lat1 htl lay)
  (if (> (distance lat1 lat2) 1.0e-6) (pool:line lat2 htl lay))
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
                    (list 'hbr 'hbl) (list 'brkb 'brkt)
                    (list 'lab1 'hbl) (list 'lab2 'hbl)
                    (list 'lat1 'htl) (list 'lat2 'htl)
                    (list 'htr 'brkt) (list 'hbr 'brkb))
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

;; Resolve a bottom measurement chain against the pool total:
;;   * NA (nil) entries take the remainder -- split evenly when there
;;     is more than one
;;   * when every value is provided but the sum misses the total, the
;;     slack member at index islack (G on the horizontal chain, L on
;;     the vertical) absorbs the difference; islack -1 = nobody (the
;;     caller handles the residual itself)
;; Returns the resolved list.
(defun pool:chainfix (vals total islack / sum n share out k v)
  (setq sum 0.0 n 0)
  (foreach v vals (if v (setq sum (+ sum v)) (setq n (1+ n))))
  (setq out nil k 0)
  (if (> n 0)
      (progn
        (setq share (/ (- total sum) n))
        (foreach v vals (setq out (cons (if v v share) out))))
      (foreach v vals
        (setq out (cons (if (and (= k islack)
                                 (> (abs (- sum total)) 1.0e-6))
                            (+ v (- total sum))
                            v)
                        out)
              k (1+ k))))
  (reverse out))

;; Normal (hopper pad) bottom for the rectangle: lettered guide,
;; prompts H G F E M L K, plan hopper + chain dims, then the side
;; profile below (asks wall height C and hopper depth D).
(defun pool:hopnormal (quad corners doff th / pv h g f e m l k gg tl odl
                                              hraw graw fraw eraw mraw lraw kraw
                                              a b c d cen toth totv hres vres)
  (setq pv (pool:hopguide quad corners th))
  (princ "\nPool bottom -- offsets from the perimeter; the RED tie is the one being asked for.")
  (setq hraw (pool:askhx "H - left end to hopper" (cdr (assoc "H" pv)))
        graw (pool:askhx "G - hopper length" (cdr (assoc "G" pv)))
        fraw (pool:askhx "F - hopper to slope break" (cdr (assoc "F" pv)))
        eraw (pool:askhx "E - slope break to right end" (cdr (assoc "E" pv)))
        mraw (pool:askhx "M - top side to hopper" (cdr (assoc "M" pv)))
        lraw (pool:askhx "L - hopper width" (cdr (assoc "L" pv)))
        kraw (pool:askhx "K - hopper to bottom side" (cdr (assoc "K" pv))))
  (pool:pvkill)
  ;; resolve the chains against the wall-to-wall totals: NA takes the
  ;; remainder (split when several); G / L absorb any leftover
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        toth (distance (pool:linex cen (pool:v- b a) a (pool:v- d a))
                       (pool:linex cen (pool:v- b a) b (pool:v- c b)))
        totv (distance (pool:linex cen (pool:v- d a) a (pool:v- b a))
                       (pool:linex cen (pool:v- d a) d (pool:v- c d)))
        hres (pool:chainfix (list hraw graw fraw eraw) toth 1)
        vres (pool:chainfix (list mraw lraw kraw) totv 1)
        h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
        m (car vres) l (cadr vres) k (caddr vres))
  (setq gg (pool:hopcalc quad corners h g e m k))
  (pool:hopdraw gg "POOL")
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
  (list
    (list "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))))
    (list "HOP G" graw (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))))
    (list "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))))
    (list "HOP E" eraw (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))))
    (list "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))))
    (list "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))))
    (list "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))))))

;; Sport bottoms (per the field sheet, which IS a side profile):
;; letters E2 F2 [G] F1 E1 along the bottom plus wall height C and
;; depth D.  Sport has a flat deep section G (reported as a check);
;; NOhopper runs the two slopes to a point (F1 is the check).  The
;; plan view gets a full-width break line at every slope change.
(defun pool:hopsport (total wid x0 y0 ymax nopad doff th / whn hdn pv
                                           e2 f2 g f1 e1 wh hd brks xs xd
                                           e2r f2r gr f1r e1r res resid
                                           rows odl prev xi)
  (setq whn (* 0.25 wid)
        hdn (* 0.55 wid))
  ;; nominal gray profile guide below the plan
  (pool:profdraw x0 y0 total whn
                 (if nopad
                     (list (cons (* 0.15 total) whn)
                           (cons (* 0.50 total) hdn)
                           (cons (* 0.85 total) whn))
                     (list (cons (* 0.12 total) whn)
                           (cons (* 0.32 total) hdn)
                           (cons (* 0.68 total) hdn)
                           (cons (* 0.88 total) whn)))
                 "POOL-NOTES" t)
  (setq pv (append
    (list (pool:pvtie (list x0 (- y0 hdn (* 1.0 doff)))
                      (list (+ x0 (* (if nopad 0.15 0.12) total)) (- y0 hdn (* 1.0 doff)))
                      "E2" th)
          (pool:pvtie (list (+ x0 (* (if nopad 0.15 0.12) total)) (- y0 hdn (* 1.0 doff)))
                      (list (+ x0 (* (if nopad 0.50 0.32) total)) (- y0 hdn (* 1.0 doff)))
                      "F2" th))
    (if nopad nil
        (list (pool:pvtie (list (+ x0 (* 0.32 total)) (- y0 hdn (* 1.0 doff)))
                          (list (+ x0 (* 0.68 total)) (- y0 hdn (* 1.0 doff)))
                          "G" th)))
    (list (pool:pvtie (list (+ x0 (* (if nopad 0.50 0.68) total)) (- y0 hdn (* 1.0 doff)))
                      (list (+ x0 (* (if nopad 0.85 0.88) total)) (- y0 hdn (* 1.0 doff)))
                      "F1" th)
          (pool:pvtie (list (+ x0 (* (if nopad 0.85 0.88) total)) (- y0 hdn (* 1.0 doff)))
                      (list (+ x0 total) (- y0 hdn (* 1.0 doff)))
                      "E1" th)
          (pool:pvtie (list (+ x0 total (* 0.6 doff)) y0)
                      (list (+ x0 total (* 0.6 doff)) (- y0 whn))
                      "C" th)
          (pool:pvtie (list (+ x0 (* 0.5 total)) y0)
                      (list (+ x0 (* 0.5 total)) (- y0 hdn))
                      "D" th))))
  (command "_.ZOOM" "_Window"
           (pool:wp (list (- x0 doff) (- y0 hdn (* 3.0 doff))))
           (pool:wp (list (+ x0 total (* 3.0 doff)) (+ ymax doff))))
  (princ "\nSport bottom -- profile letters per the sheet; the RED tie is being asked for.")
  (setq e2r (pool:askhx "E2 - left end shallow flat" (cdr (assoc "E2" pv)))
        f2r (pool:askhx "F2 - left slope" (cdr (assoc "F2" pv))))
  (if (not nopad)
      (setq gr (pool:askhx "G - deep flat length" (cdr (assoc "G" pv)))))
  (setq f1r (pool:askhx "F1 - right slope" (cdr (assoc "F1" pv)))
        e1r (pool:askhx "E1 - right end shallow flat" (cdr (assoc "E1" pv)))
        wh (pool:askh "C - wall height (shallow depth)" (cdr (assoc "C" pv)))
        hd (pool:askh "D - deep depth" (cdr (assoc "D" pv))))
  (pool:pvkill)
  ;; resolve the bottom chain: NA takes the remainder (split evenly);
  ;; leftover slack goes to G, or is split across F2/F1 when there is
  ;; no hopper pad
  (if nopad
      (progn
        (setq res (pool:chainfix (list e2r f2r f1r e1r) total -1)
              e2 (car res) f2 (cadr res) f1 (caddr res) e1 (cadddr res)
              resid (- total e2 f2 f1 e1))
        (if (> (abs resid) 1.0e-6)
            (setq f2 (+ f2 (* 0.5 resid))
                  f1 (+ f1 (* 0.5 resid)))))
      (setq res (pool:chainfix (list e2r f2r gr f1r e1r) total 2)
            e2 (car res) f2 (cadr res) g (caddr res)
            f1 (cadddr res) e1 (nth 4 res)))
  (setq brks (if nopad
                 (list (cons e2 wh) (cons (+ e2 f2) hd) (cons (- total e1) wh))
                 (list (cons e2 wh) (cons (+ e2 f2) hd)
                       (cons (- total e1 f1) hd) (cons (- total e1) wh)))
        xs (mapcar 'car brks))
  (pool:profdraw x0 y0 total wh brks "POOL" nil)
  ;; dims: bottom chain + C + D, like the sheet
  (setq odl (getvar "CLAYER"))
  (setvar "CLAYER" "DIMENSION")
  (setq prev 0.0)
  (foreach xi (append xs (list total))
    (pool:dimalg (list (+ x0 prev) (- y0 hd)) (list (+ x0 xi) (- y0 hd))
                 (list (+ x0 (* 0.5 (+ prev xi))) (- y0 hd (* 1.0 doff))))
    (setq prev xi))
  (pool:dimalg (list (+ x0 total) y0) (list (+ x0 total) (- y0 wh))
               (list (+ x0 total (* 0.8 doff)) (- y0 (* 0.5 wh))))
  (setq xd (if nopad (+ x0 e2 f2) (+ x0 (* 0.5 (+ (+ e2 f2) (- total e1 f1))))))
  (pool:dimalg (list xd y0) (list xd (- y0 hd))
               (list (+ xd (* 0.3 doff)) (- y0 (* 0.5 hd))))
  (setvar "CLAYER" odl)
  (setq rows (list
    (list "SPT E2" e2r e2)
    (list "SPT F2" f2r f2)))
  (if nopad
      (setq rows (append rows (list
        (list "SPT F1" f1r f1)
        (list "SPT E1" e1r e1))))
      (setq rows (append rows (list
        (list "SPT G" gr g)
        (list "SPT F1" f1r f1)
        (list "SPT E1" e1r e1)))))
  (list (append rows (list (list "WALL HT C" wh wh) (list "DEPTH D" hd hd)))
        xs))

;; Pool-bottom dispatcher for the rectangle: Normal (hopper pad),
;; Sport (flat deep section) or Sport with no hopper pad (V bottom).
;; Returns the report rows (nil if skipped).
(defun pool:hopper (quad corners doff th / btype xmin xmax ymin ymax
                                           a b c d cen sres ln xi)
  (initget "Yes No")
  (if (= "No" (getkword "\nAdd pool bottom (hopper) detail? [Yes/No] <Yes>: "))
      nil
      (progn
        (setq xmin (apply 'min (mapcar 'car quad))
              xmax (apply 'max (mapcar 'car quad))
              ymin (apply 'min (mapcar 'cadr quad))
              ymax (apply 'max (mapcar 'cadr quad)))
        (command "_.ZOOM" "_Window"
                 (pool:wp (list (- xmin doff) (- ymin doff)))
                 (pool:wp (list (+ xmax doff) (+ ymax doff))))
        (initget 1 "Normal Sport NOhopper")
        (setq btype (getkword "\nBottom type [Normal/Sport/NOhopper pad sport]: "))
        (if (= btype "Normal")
            (pool:hopnormal quad corners doff th)
            (progn
              (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
                    cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
                    sres (pool:hopsport (distance a b) (distance a d)
                                        xmin (- ymin (* 2.2 doff)) ymax
                                        (= btype "NOhopper") doff th))
              ;; full-width plan break line at every slope change
              (foreach xi (cadr sres)
                (setq ln (pool:offline a d cen xi))
                (pool:line (pool:linex (car ln) (cadr ln) a (pool:v- b a))
                           (pool:linex (car ln) (cadr ln) d (pool:v- c d))
                           "POOL"))
              (car sres))))))

;;; -------------------- side profile -----------------------------------
;;;
;;;  Section view under the plan: waterline across the top, walls of
;;;  height C at both ends, and the bottom running through the given
;;;  break vertices.  Used by the normal hoppers and by the Sport
;;;  bottoms (whose field sheets ARE this profile).

;; Draw the profile outline.  x0/y0 = top-left, total = pool length,
;; wh = wall height, brks = bottom vertices ((dist . depth) ...) from
;; the left wall, left to right.
(defun pool:profdraw (x0 y0 total wh brks lay pvflag / pts prev p)
  (setq pts (append (list (list x0 y0)
                          (list (+ x0 total) y0)
                          (list (+ x0 total) (- y0 wh)))
                    (mapcar '(lambda (p) (list (+ x0 (car p)) (- y0 (cdr p))))
                            (reverse brks))
                    (list (list x0 (- y0 wh))
                          (list x0 y0)))
        prev (car pts))
  (foreach p (cdr pts)
    (pool:hgl prev p lay pvflag)
    (setq prev p)))

;; Dashed lettered guide tie from p to q; returns the (lbl ent...)
;; highlight assoc entry.
(defun pool:pvtie (p q lbl th / e)
  (setq e (pool:pvadd (pool:pvlined p q)))
  (pool:text (pool:v+ (pool:mid p q) (list (* 0.5 th) (* 0.5 th)))
             (* 1.2 th) lbl "POOL-NOTES")
  (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))
  (cons lbl (list e)))

;; Line/arc makers used by the shape-specific hopper draws: when
;; pvflag is set they draw tracked gray guide entities instead.
(defun pool:hgl (p q lay pvflag)
  (if pvflag
      (pool:pvadd (pool:pvline p q))
      (pool:line p q lay)))

(defun pool:hga (p mm q lay pvflag)
  (if pvflag
      (progn
        (pool:arc3p p mm q "POOL-NOTES")
        (pool:pvadd (pool:setcol (entlast) pool:*pv-col*)))
      (pool:arc3p p mm q lay)))

;;; ---------------- oval pool bottom (True Oval sheet) -----------------
;;;
;;;  The hopper is a box with a radius (R3) left end, set out along
;;;  the pool axis (arc tip to arc tip):
;;;    H = pool left tip -> hopper tip      E = break -> pool right tip
;;;    G = hopper tip -> hopper right edge  M/K = top/bottom offsets
;;;    R3 = hopper end radius               L = hopper width (CHECK)
;;;    W = hopper flat top, tangent -> right edge (CHECK, = G - R3)
;;;    F = hopper -> slope break (CHECK)    T = straight side (CHECK)
;;;  No left ties (the radius IS the end); the right corners tie to
;;;  the slope-break ends as usual.

(defun pool:hopovalc (quad tipl tipr h g e m k r3 / a b c d cen u v ht hb
                                                    lt re tan brk tt tb tip vc
                                                    tip2)
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        u (pool:unit (pool:v- tipr tipl))
        v (pool:perp u)
        ht (pool:offline d c cen m)
        hb (pool:offline a b cen k)
        lt (list (pool:v+ tipl (pool:v* u h)) v)
        re (list (pool:v+ tipl (pool:v* u (+ h g))) v)
        tan (list (pool:v+ tipl (pool:v* u (+ h r3))) v)
        brk (list (pool:v- tipr (pool:v* u e)) v)
        tt (pool:linex (car tan) (cadr tan) (car ht) (cadr ht))
        tb (pool:linex (car tan) (cadr tan) (car hb) (cadr hb))
        tip (pool:mid (pool:linex (car lt) (cadr lt) (car ht) (cadr ht))
                      (pool:linex (car lt) (cadr lt) (car hb) (cadr hb)))
        ;; M/L/K chain 12" right of the hopper's right edge
        vc (pool:v+ tipl (pool:v* u (+ h g 12.0)))
        ;; H/G/F/E chain below the hopper centre by 12" or L/6,
        ;; whichever is closer
        tip2 (pool:v- tip
                      (pool:v* (pool:unit v)
                               (min 12.0
                                    (/ (distance
                                         (pool:linex vc v (car hb) (cadr hb))
                                         (pool:linex vc v (car ht) (cadr ht)))
                                       6.0)))))
  (list (list 'tip tip) (list 'ttop tt) (list 'tbot tb)
        (list 'htr (pool:linex (car re) (cadr re) (car ht) (cadr ht)))
        (list 'hbr (pool:linex (car re) (cadr re) (car hb) (cadr hb)))
        (list 'brkb (pool:linex (car brk) (cadr brk) a (pool:v- b a)))
        (list 'brkt (pool:linex (car brk) (cadr brk) d (pool:v- c d)))
        (list 'ptan (pool:linex tip2 u (car tan) v))
        (list 'pl (pool:linex tip2 u tipl v))
        (list 'phl (pool:linex tip2 u (car lt) (cadr lt)))
        (list 'phr (pool:linex tip2 u (car re) v))
        (list 'pbrk (pool:linex tip2 u (car brk) v))
        (list 'pr (pool:linex tip2 u tipr v))
        (list 'pb (pool:linex vc v a (pool:v- b a)))
        (list 'phb (pool:linex vc v (car hb) (cadr hb)))
        (list 'pht (pool:linex vc v (car ht) (cadr ht)))
        (list 'pt (pool:linex vc v d (pool:v- c d)))))

(defun pool:hopovaldraw (gg lay pvflag / tt tb tip htr hbr brkb brkt)
  (setq tt (cadr (assoc 'ttop gg)) tb (cadr (assoc 'tbot gg))
        tip (cadr (assoc 'tip gg))
        htr (cadr (assoc 'htr gg)) hbr (cadr (assoc 'hbr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg)))
  (pool:hgl tt htr lay pvflag)
  (pool:hgl tb hbr lay pvflag)
  (pool:hgl htr hbr lay pvflag)
  (pool:hga tt tip tb lay pvflag)
  (pool:hgl brkb brkt lay pvflag)
  (pool:hgl htr brkt lay pvflag)
  (pool:hgl hbr brkb lay pvflag))

;; Guided oval bottom phase.  Returns report rows (nil if skipped).
(defun pool:hopoval (quad tipl tipr doff th / len wid ggn pv gg rows tl odl
                                              h g f e m l k r3 w tt o
                                              hraw graw fraw eraw mraw lraw kraw
                                              totv hres vres
                                              xmin xmax ymin ymax)
  (if nil                               ; Yes/No now lives in the dispatcher
      nil
      (progn
        (setq xmin (- (min (car tipl) (car tipr)) doff)
              xmax (+ (max (car tipl) (car tipr)) doff)
              ymin (- (apply 'min (mapcar 'cadr quad)) doff)
              ymax (+ (apply 'max (mapcar 'cadr quad)) doff))
        (command "_.ZOOM" "_Window" (pool:wp (list xmin ymin))
                 (pool:wp (list xmax ymax)))
        ;; nominal guide
        (setq len (distance tipl tipr)
              wid (distance (car quad) (cadddr quad))
              ggn (pool:hopovalc quad tipl tipr (* 0.10 len) (* 0.24 len)
                                 (* 0.38 len) (* 0.25 wid) (* 0.25 wid)
                                 (* 0.20 wid)))
        (pool:hopovaldraw ggn "POOL-NOTES" t)
        (setq pv (list
          (pool:pvtie (cadr (assoc 'pl ggn)) (cadr (assoc 'phl ggn)) "H" th)
          (pool:pvtie (cadr (assoc 'phl ggn)) (cadr (assoc 'phr ggn)) "G" th)
          (pool:pvtie (cadr (assoc 'phl ggn)) (cadr (assoc 'ptan ggn)) "R3" th)
          (pool:pvtie (cadr (assoc 'ttop ggn)) (cadr (assoc 'htr ggn)) "W" th)
          (pool:pvtie (cadr (assoc 'phr ggn)) (cadr (assoc 'pbrk ggn)) "F" th)
          (pool:pvtie (cadr (assoc 'pbrk ggn)) (cadr (assoc 'pr ggn)) "E" th)
          (pool:pvtie (cadr (assoc 'pht ggn)) (cadr (assoc 'pt ggn)) "M" th)
          (pool:pvtie (cadr (assoc 'phb ggn)) (cadr (assoc 'pht ggn)) "L" th)
          (pool:pvtie (cadr (assoc 'pb ggn)) (cadr (assoc 'phb ggn)) "K" th)
          (pool:pvtie (cadddr quad) (caddr quad) "T" th)))
        (princ "\nPool bottom -- offsets along the pool axis; the RED tie is being asked for.")
        (setq hraw (pool:askhx "H - pool left tip to hopper tip" (cdr (assoc "H" pv)))
              graw (pool:askhx "G - hopper length (tip to right edge)" (cdr (assoc "G" pv)))
              r3 (pool:askh "R3 - hopper end radius" (cdr (assoc "R3" pv)))
              w (pool:askhx "W - hopper flat top (check)" (cdr (assoc "W" pv)))
              fraw (pool:askhx "F - hopper to slope break" (cdr (assoc "F" pv)))
              eraw (pool:askhx "E - slope break to pool right tip" (cdr (assoc "E" pv)))
              mraw (pool:askhx "M - top side to hopper" (cdr (assoc "M" pv)))
              lraw (pool:askhx "L - hopper width" (cdr (assoc "L" pv)))
              kraw (pool:askhx "K - hopper to bottom side" (cdr (assoc "K" pv)))
              tt (pool:askhx "T - straight side length (check)" (cdr (assoc "T" pv))))
        (pool:pvkill)
        ;; resolve against tip-to-tip length and side-to-side width
        (setq totv (distance
                     (pool:linex (pool:mid (car quad) (caddr quad))
                                 (pool:v- (cadddr quad) (car quad))
                                 (car quad) (pool:v- (cadr quad) (car quad)))
                     (pool:linex (pool:mid (car quad) (caddr quad))
                                 (pool:v- (cadddr quad) (car quad))
                                 (cadddr quad) (pool:v- (caddr quad) (cadddr quad))))
              hres (pool:chainfix (list hraw graw fraw eraw) (distance tipl tipr) 1)
              vres (pool:chainfix (list mraw lraw kraw) totv 1)
              h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
              m (car vres) l (cadr vres) k (caddr vres))
        (setq gg (pool:hopovalc quad tipl tipr h g e m k r3))
        (pool:hopovaldraw gg "POOL" nil)
        (setq odl (getvar "CLAYER"))
        (setvar "CLAYER" "DIMENSION")
        (foreach tl (list (list 'pl 'phl) (list 'phl 'phr) (list 'phr 'pbrk)
                          (list 'pbrk 'pr) (list 'phl 'ptan)
                          (list 'ttop 'htr) (list 'pht 'pt) (list 'phb 'pht)
                          (list 'pb 'phb))
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:mid (cadr (assoc (car tl) gg))
                                 (cadr (assoc (cadr tl) gg)))))
        (setvar "CLAYER" odl)
        (setq o (pool:circum (cadr (assoc 'ttop gg)) (cadr (assoc 'tip gg))
                             (cadr (assoc 'tbot gg)))
              rows (list
          (list "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))))
          (list "HOP G" graw (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))))
          (list "HOP R3" r3 (if o (distance o (cadr (assoc 'tip gg))) r3))
          (list "HOP W" w (distance (cadr (assoc 'ttop gg)) (cadr (assoc 'htr gg))))
          (list "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))))
          (list "HOP E" eraw (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))))
          (list "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))))
          (list "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))))
          (list "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))))
          (list "HOP T" tt (distance (cadddr quad) (caddr quad)))))
        rows)))

;;; ---------------- grecian pool bottom (Square / 6-sided) -------------
;;;
;;;  Square hopper = the rectangle letters (H G F E M L K), anchored
;;;  off the end walls; each hopper left corner ties to BOTH ends of
;;;  its pool corner cut.  The 6-sided hopper adds cut left corners:
;;;    W  = cut setback along the hopper top/bottom edges
;;;    L1 = cut setback down the hopper left edge
;;;    X  = cut face length (CHECK, = sqrt(W^2 + L1^2) when square)
;;;  and the pool cut ends tie to the matching hopper cut ends.

(defun pool:hopgrecc (pts h g e m k w l1 / aa bb rb rt cc dd ltp lbp cen p
                                           hl hr ht hb brk hbl htl hbr htr
                                           hlw htl1 hbl1 hc u v hc2 rc out)
  (setq aa (nth 0 pts) bb (nth 1 pts) rb (nth 2 pts) rt (nth 3 pts)
        cc (nth 4 pts) dd (nth 5 pts) ltp (nth 6 pts) lbp (nth 7 pts)
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen 0.125)
        hl (pool:offline lbp ltp cen h)
        hr (pool:offline lbp ltp cen (+ h g))
        ht (pool:offline dd cc cen m)
        hb (pool:offline aa bb cen k)
        brk (pool:offline rb rt cen e)
        hbl (pool:linex (car hl) (cadr hl) (car hb) (cadr hb))
        htl (pool:linex (car hl) (cadr hl) (car ht) (cadr ht))
        hbr (pool:linex (car hr) (cadr hr) (car hb) (cadr hb))
        htr (pool:linex (car hr) (cadr hr) (car ht) (cadr ht))
        hc (pool:v* (pool:v+ (pool:v+ hbl htl) (pool:v+ hbr htr)) 0.25)
        u (pool:v- bb aa)
        v (pool:v- dd aa)
        ;; chain placement: H/G/F/E below the hopper centre by 12" or
        ;; L/6 (whichever is closer); M/L/K 12" right of the hopper
        hc2 (pool:v- hc (pool:v* (pool:unit v)
                                 (min 12.0 (/ (distance hbr htr) 6.0))))
        rc (pool:offline lbp ltp cen (+ h g 12.0))
        out (list
          (list 'hbl hbl) (list 'htl htl) (list 'hbr hbr) (list 'htr htr)
          (list 'brkb (pool:linex (car brk) (cadr brk) aa (pool:v- bb aa)))
          (list 'brkt (pool:linex (car brk) (cadr brk) dd (pool:v- cc dd)))
          (list 'aa aa) (list 'dd dd) (list 'ltp ltp) (list 'lbp lbp)
          (list 'pl (pool:linex hc2 u lbp (pool:v- ltp lbp)))
          (list 'phl (pool:linex hc2 u (car hl) (cadr hl)))
          (list 'phr (pool:linex hc2 u (car hr) (cadr hr)))
          (list 'pbrk (pool:linex hc2 u (car brk) (cadr brk)))
          (list 'pr (pool:linex hc2 u rb (pool:v- rt rb)))
          (list 'pb (pool:linex (car rc) (cadr rc) aa (pool:v- bb aa)))
          (list 'phb (pool:linex (car rc) (cadr rc) (car hb) (cadr hb)))
          (list 'pht (pool:linex (car rc) (cadr rc) (car ht) (cadr ht)))
          (list 'pt (pool:linex (car rc) (cadr rc) dd (pool:v- cc dd)))))
  (if w
      (setq hlw (pool:offline lbp ltp cen (+ h w))
            htl1 (pool:offline dd cc cen (+ m l1))
            hbl1 (pool:offline aa bb cen (+ k l1))
            out (append out (list
              (list 'ct1 (pool:linex (car hlw) (cadr hlw) (car ht) (cadr ht)))
              (list 'ct2 (pool:linex (car hl) (cadr hl) (car htl1) (cadr htl1)))
              (list 'cb1 (pool:linex (car hlw) (cadr hlw) (car hb) (cadr hb)))
              (list 'cb2 (pool:linex (car hl) (cadr hl) (car hbl1) (cadr hbl1)))))))
  out)

(defun pool:hopgrecdraw (gg lay six pvflag / hbl htl hbr htr brkb brkt
                                             aa dd ltp lbp ct1 ct2 cb1 cb2)
  (setq hbl (cadr (assoc 'hbl gg)) htl (cadr (assoc 'htl gg))
        hbr (cadr (assoc 'hbr gg)) htr (cadr (assoc 'htr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg))
        aa (cadr (assoc 'aa gg)) dd (cadr (assoc 'dd gg))
        ltp (cadr (assoc 'ltp gg)) lbp (cadr (assoc 'lbp gg)))
  (pool:hgl htr hbr lay pvflag)
  (pool:hgl brkb brkt lay pvflag)
  (pool:hgl htr brkt lay pvflag)
  (pool:hgl hbr brkb lay pvflag)
  (if six
      (progn
        (setq ct1 (cadr (assoc 'ct1 gg)) ct2 (cadr (assoc 'ct2 gg))
              cb1 (cadr (assoc 'cb1 gg)) cb2 (cadr (assoc 'cb2 gg)))
        (pool:hgl ct1 htr lay pvflag)
        (pool:hgl cb1 hbr lay pvflag)
        (pool:hgl ct2 cb2 lay pvflag)
        (pool:hgl ct2 ct1 lay pvflag)
        (pool:hgl cb2 cb1 lay pvflag)
        (pool:hgl dd ct1 lay pvflag)
        (pool:hgl ltp ct2 lay pvflag)
        (pool:hgl aa cb1 lay pvflag)
        (pool:hgl lbp cb2 lay pvflag))
      (progn
        (pool:hgl htl htr lay pvflag)
        (pool:hgl hbl hbr lay pvflag)
        (pool:hgl htl hbl lay pvflag)
        (pool:hgl dd htl lay pvflag)
        (pool:hgl ltp htl lay pvflag)
        (pool:hgl aa hbl lay pvflag)
        (pool:hgl lbp hbl lay pvflag))))

;; Guided grecian bottom phase.  Returns report rows (nil if skipped).
(defun pool:hopgrec (pts doff th / htype six len wid ggn pv gg rows tl odl
                                   h g f e m l k w l1 x wp
                                   hraw graw fraw eraw mraw lraw kraw
                                   cen p u vv toth totv hres vres
                                   xmin xmax ymin ymax)
  (if nil                               ; Yes/No now lives in the dispatcher
      nil
      (progn
        (initget 1 "Square SIX")
        (setq htype (getkword "\nHopper type [Square/SIX-sided]: ")
              six (= htype "SIX")
              xmin (- (apply 'min (mapcar 'car pts)) doff)
              xmax (+ (apply 'max (mapcar 'car pts)) doff)
              ymin (- (apply 'min (mapcar 'cadr pts)) doff)
              ymax (+ (apply 'max (mapcar 'cadr pts)) doff))
        (command "_.ZOOM" "_Window" (pool:wp (list xmin ymin))
                 (pool:wp (list xmax ymax)))
        ;; nominal guide
        (setq len (distance (nth 0 pts) (nth 1 pts))
              wid (distance (nth 0 pts) (nth 5 pts))
              ggn (pool:hopgrecc pts (* 0.10 len) (* 0.20 len) (* 0.38 len)
                                 (* 0.27 wid) (* 0.27 wid)
                                 (if six (* 0.05 len) nil)
                                 (if six (* 0.08 wid) nil)))
        (pool:hopgrecdraw ggn "POOL-NOTES" six t)
        (setq pv (list
          (pool:pvtie (cadr (assoc 'pl ggn)) (cadr (assoc 'phl ggn)) "H" th)
          (pool:pvtie (cadr (assoc 'phl ggn)) (cadr (assoc 'phr ggn)) "G" th)
          (pool:pvtie (cadr (assoc 'phr ggn)) (cadr (assoc 'pbrk ggn)) "F" th)
          (pool:pvtie (cadr (assoc 'pbrk ggn)) (cadr (assoc 'pr ggn)) "E" th)
          (pool:pvtie (cadr (assoc 'pht ggn)) (cadr (assoc 'pt ggn)) "M" th)
          (pool:pvtie (cadr (assoc 'phb ggn)) (cadr (assoc 'pht ggn)) "L" th)
          (pool:pvtie (cadr (assoc 'pb ggn)) (cadr (assoc 'phb ggn)) "K" th)))
        (if six
            (setq wp (cadr (assoc 'htl ggn))   ; hopper's virtual top-left corner
                  pv (append pv (list
                    (pool:pvtie wp (cadr (assoc 'ct1 ggn)) "W" th)
                    (pool:pvtie wp (cadr (assoc 'ct2 ggn)) "L1" th)
                    (pool:pvtie (cadr (assoc 'ct2 ggn)) (cadr (assoc 'ct1 ggn)) "X" th)))))
        (princ "\nPool bottom -- offsets from the end walls; the RED tie is being asked for.")
        (setq hraw (pool:askhx "H - left end to hopper" (cdr (assoc "H" pv)))
              graw (pool:askhx "G - hopper length" (cdr (assoc "G" pv))))
        (if six
            (setq w (pool:askh "W - hopper cut along top/bottom edges" (cdr (assoc "W" pv)))
                  l1 (pool:askh "L1 - hopper cut down the left edge" (cdr (assoc "L1" pv)))
                  x (pool:askhx "X - hopper cut face length (check)" (cdr (assoc "X" pv)))))
        (setq fraw (pool:askhx "F - hopper to slope break" (cdr (assoc "F" pv)))
              eraw (pool:askhx "E - slope break to right end" (cdr (assoc "E" pv)))
              mraw (pool:askhx "M - top side to hopper" (cdr (assoc "M" pv)))
              lraw (pool:askhx "L - hopper width" (cdr (assoc "L" pv)))
              kraw (pool:askhx "K - hopper to bottom side" (cdr (assoc "K" pv))))
        (pool:pvkill)
        ;; resolve against wall-to-wall totals (end wall to end wall,
        ;; side to side) through the pool centre
        (setq cen (list 0.0 0.0))
        (foreach p pts (setq cen (pool:v+ cen p)))
        (setq cen (pool:v* cen 0.125)
              u (pool:v- (nth 1 pts) (nth 0 pts))
              vv (pool:v- (nth 5 pts) (nth 0 pts))
              toth (distance
                     (pool:linex cen u (nth 7 pts) (pool:v- (nth 6 pts) (nth 7 pts)))
                     (pool:linex cen u (nth 2 pts) (pool:v- (nth 3 pts) (nth 2 pts))))
              totv (distance
                     (pool:linex cen vv (nth 0 pts) (pool:v- (nth 1 pts) (nth 0 pts)))
                     (pool:linex cen vv (nth 5 pts) (pool:v- (nth 4 pts) (nth 5 pts))))
              hres (pool:chainfix (list hraw graw fraw eraw) toth 1)
              vres (pool:chainfix (list mraw lraw kraw) totv 1)
              h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
              m (car vres) l (cadr vres) k (caddr vres))
        (setq gg (pool:hopgrecc pts h g e m k (if six w nil) (if six l1 nil)))
        (pool:hopgrecdraw gg "POOL" six nil)
        (setq odl (getvar "CLAYER"))
        (setvar "CLAYER" "DIMENSION")
        (foreach tl (list (list 'pl 'phl) (list 'phl 'phr) (list 'phr 'pbrk)
                          (list 'pbrk 'pr) (list 'pht 'pt) (list 'phb 'pht)
                          (list 'pb 'phb))
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:mid (cadr (assoc (car tl) gg))
                                 (cadr (assoc (cadr tl) gg)))))
        (if six
            (progn
              (pool:dimalg (cadr (assoc 'htl gg)) (cadr (assoc 'ct1 gg))
                           (pool:mid (cadr (assoc 'htl gg)) (cadr (assoc 'ct1 gg))))
              (pool:dimalg (cadr (assoc 'htl gg)) (cadr (assoc 'ct2 gg))
                           (pool:mid (cadr (assoc 'htl gg)) (cadr (assoc 'ct2 gg))))
              (pool:dimalg (cadr (assoc 'ct2 gg)) (cadr (assoc 'ct1 gg))
                           (pool:mid (cadr (assoc 'ct2 gg)) (cadr (assoc 'ct1 gg))))))
        (setvar "CLAYER" odl)
        (setq rows (list
          (list "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))))
          (list "HOP G" graw (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))))
          (list "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))))
          (list "HOP E" eraw (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))))
          (list "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))))
          (list "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))))
          (list "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))))))
        (if six
            (setq rows (append rows (list
              (list "HOP W" w (distance (cadr (assoc 'htl gg)) (cadr (assoc 'ct1 gg))))
              (list "HOP L1" l1 (distance (cadr (assoc 'htl gg)) (cadr (assoc 'ct2 gg))))
              (list "HOP X" x (distance (cadr (assoc 'ct2 gg)) (cadr (assoc 'ct1 gg))))))))
        rows)))

;; Bottom-type dispatchers: Normal / Sport / NOhopper for oval and
;; grecian pools (L pools are standard-hopper only).

(defun pool:hopovaldsp (quad tipl tipr doff th / btype u v sres p xi)
  (initget "Yes No")
  (if (= "No" (getkword "\nAdd pool bottom (hopper) detail? [Yes/No] <Yes>: "))
      nil
      (progn
        (initget 1 "Normal Sport NOhopper")
        (setq btype (getkword "\nBottom type [Normal/Sport/NOhopper pad sport]: "))
        (if (= btype "Normal")
            (pool:hopoval quad tipl tipr doff th)
            (progn
              (setq u (pool:unit (pool:v- tipr tipl))
                    v (pool:perp u)
                    sres (pool:hopsport (distance tipl tipr)
                                        (distance (car quad) (cadddr quad))
                                        (min (car tipl) (car tipr))
                                        (- (apply 'min (mapcar 'cadr quad))
                                           (* 2.2 doff))
                                        (apply 'max (mapcar 'cadr quad))
                                        (= btype "NOhopper") doff th))
              ;; plan break line across the pool at every slope change
              (foreach xi (cadr sres)
                (setq p (pool:v+ tipl (pool:v* u xi)))
                (pool:line (pool:linex p v (car quad)
                                       (pool:v- (cadr quad) (car quad)))
                           (pool:linex p v (cadddr quad)
                                       (pool:v- (caddr quad) (cadddr quad)))
                           "POOL"))
              (car sres))))))

(defun pool:hopgrecdsp (pts doff th / btype cen p u pl pr sres xi ln)
  (initget "Yes No")
  (if (= "No" (getkword "\nAdd pool bottom (hopper) detail? [Yes/No] <Yes>: "))
      nil
      (progn
        (initget 1 "Normal Sport NOhopper")
        (setq btype (getkword "\nBottom type [Normal/Sport/NOhopper pad sport]: "))
        (if (= btype "Normal")
            (pool:hopgrec pts doff th)
            (progn
              (setq cen (list 0.0 0.0))
              (foreach p pts (setq cen (pool:v+ cen p)))
              (setq cen (pool:v* cen 0.125)
                    u (pool:v- (nth 1 pts) (nth 0 pts))
                    pl (pool:linex cen u (nth 7 pts)
                                   (pool:v- (nth 6 pts) (nth 7 pts)))
                    pr (pool:linex cen u (nth 2 pts)
                                   (pool:v- (nth 3 pts) (nth 2 pts)))
                    sres (pool:hopsport (distance pl pr)
                                        (distance (nth 0 pts) (nth 5 pts))
                                        (apply 'min (mapcar 'car pts))
                                        (- (apply 'min (mapcar 'cadr pts))
                                           (* 2.2 doff))
                                        (apply 'max (mapcar 'cadr pts))
                                        (= btype "NOhopper") doff th))
              (foreach xi (cadr sres)
                (setq ln (pool:offline (nth 7 pts) (nth 6 pts) cen xi))
                (pool:line (pool:linex (car ln) (cadr ln) (nth 0 pts)
                                       (pool:v- (nth 1 pts) (nth 0 pts)))
                           (pool:linex (car ln) (cadr ln) (nth 5 pts)
                                       (pool:v- (nth 4 pts) (nth 5 pts)))
                           "POOL"))
              (car sres))))))

;;; -------------------- rectangle / oval flow --------------------------

;; Full guided flow for the quad-based pools: preview, prompts, fit,
;; draw, dimension and report.  Caller handles sysvars/undo/zoom.
(defun pool:quadflow (ptype / oldclay pv arcs
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

  ;; in-square: opposing sides are equal, ask each pair once
  (if pool:*insq*
      (setq tp (pool:askh "Side length (top & bottom)"
                          (append (cdr (assoc 'dc pv)) (cdr (assoc 'ab pv))))
            bo tp
            le (pool:askh "End length (left & right)"
                          (append (cdr (assoc 'da pv)) (cdr (assoc 'bc pv))))
            ri le)
      (setq tp  (pool:askh "Side length TOP (D-C)" (cdr (assoc 'dc pv)))
            bo  (pool:askh "Side length BOTTOM (A-B)" (cdr (assoc 'ab pv)))
            le  (pool:askh "End length LEFT (A-D)" (cdr (assoc 'da pv)))
            ri  (pool:askh "End length RIGHT (B-C)" (cdr (assoc 'bc pv)))))

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
      (setq arcs (pool:drawrect quad corners))
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
  ;; corner annotations: one "Typ." at B when in-square, every corner
  ;; individually when out-of-square
  (if (= ptype "Rectangle")
      (pool:dimcorners quad corners arcs cen doff))
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
                                         (* (if (= 0 (rem k 2)) 0.2 -0.2) doff))))
          (pool:dimdash)))
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
  ;; -------------------------------- pool bottom (interior pipeline)
  (cond
    ((= ptype "Rectangle")
     (setq rows (append rows (pool:hopper quad corners doff th))))
    ((= ptype "Oval")
     (setq rows (append rows (pool:hopovaldsp quad tipl tipr doff th)))))
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

(defun c:POOL ( / *error* oldcmd oldos oldclay oldlun ptype base)

  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg t) "function cancelled")
             (/= (strcase msg t) "quit / exit abort"))
        (princ (strcat "\nPOOL error: " msg)))
    (pool:pvkill)
    (if oldclay (setvar "CLAYER" oldclay))
    (if oldos (setvar "OSMODE" oldos))
    (if oldlun (setvar "LUNITS" oldlun))
    (command "_.UNDO" "_End")
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if *pop-error-mode* (*pop-error-mode*))
    (princ))

  ;; AutoCAD 2012+ requires this so *error* may call (command);
  ;; harmless no-op guard on older releases where it doesn't exist
  (if *push-error-using-command* (*push-error-using-command*))

  (setq oldcmd (getvar "CMDECHO")
        oldos (getvar "OSMODE")
        oldclay (getvar "CLAYER")
        oldlun (getvar "LUNITS"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setvar "OSMODE" 0)
  ;; architectural units while prompting so every distance can be
  ;; typed as 25'6", 25'-6-1/2" or 25'6.5 as well as plain inches
  (setvar "LUNITS" 4)
  (princ "\nDistances may be typed as 25'6\", 25'-6-1/2\" or 25'6.5 (plain numbers = inches).")

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
  (setvar "LUNITS" oldlun)
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (if *pop-error-mode* (*pop-error-mode*))
  (princ))


(princ "\nPOOL.LSP loaded.  Type POOL to lay out a pool.")
(princ)
