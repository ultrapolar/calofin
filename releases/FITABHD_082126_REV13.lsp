;;; ======================================================================
;;; FITABHD.lsp  --  fit a TYPED pool template through surveyed points
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  FITABHD     ask what type of pool the survey is, fit that
;;;                        type's template through the points, then
;;;                        offer the standard-hopper pool bottom
;;;            FITABHDVER  print the loaded version
;;;
;;; ABHD traces whatever shape the survey points make.  FITABHD is its
;;; typed sibling: you TELL it what kind of typical pool was surveyed -
;;; Rectangle, Grecian, Roman, Oval, L, Lazy L or Round (POOL's own
;;; shape vocabulary) - and the type does half the work:
;;;
;;;   * Wall DIRECTIONS come from the template, never from the points.
;;;     A rectangle's walls come out dead parallel and square; a Lazy
;;;     L's bend walls sit at exactly 45 degrees.  The survey only says
;;;     WHERE each wall is, by an iterative nearest-wall fit.
;;;   * The pool's rotation is found automatically (every survey edge
;;;     votes, folded so parallel and perpendicular walls agree), and
;;;     every placement the type allows - four rotations, mirrored for
;;;     the chiral L shapes, eight rotations for the Lazy L - is tried;
;;;     the one that hugs the points best wins.  A placement whose
;;;     template collapsed (a wall fitted backwards) is thrown out
;;;     however well it scores.
;;;   * Corner treatments use the standard question (Square / Radius /
;;;     Cut / NotGiven) and the SIZE is measured from the points: one
;;;     shared fillet radius (or cut face) fitted over every corner
;;;     that turns hard enough to measure.  A Rectangle with Cut
;;;     corners rides the same eight-wall template as a Grecian.
;;;   * A GRECIAN'S CUT CORNERS MAY BE EASED: the nominal drawing is
;;;     sharp, but an as-built very often rounds the eight vertices.
;;;     Answer Radius (or Cut) at step 2 and one shared easing is
;;;     measured over all eight 45-degree corners, with the zone sized
;;;     to that gentler turn - and kept only when it beats the sharp
;;;     outline on the corner points by a clear margin, so noise never
;;;     invents a radius on a genuinely sharp pool.
;;;   * Roman and Oval ends are found, not declared: square-end and
;;;     arc-end placements (one end and both ends) all compete, and a
;;;     both-ends fit must beat a single-ended one by a clear margin -
;;;     extra freedom is not evidence.  A Roman end reports its bulge
;;;     (S) and stubs (S1) like POOL draws them.
;;;   * NICE DIMENSIONS: each headline dimension - length, width,
;;;     corner radius, cut face, body length - is snapped to the first
;;;     friendly increment (whole feet, half feet, inches, half
;;;     inches) the points can live with: the snapped outline must
;;;     stay within the run tolerance, or move nothing more than
;;;     fit:*snap-eps* when an outlier already sits beyond it.  The
;;;     points outrank pretty numbers.
;;;
;;; The fitted outline previews on POOL-FIT with a hit report (points
;;; on the line, off within tolerance, beyond it - the strays ringed
;;; on FGStep, only FITABHD's own rings ever erased) and the fitted
;;; dimensions printed in feet and inches.  Keep it and it moves to
;;; the POOL layer in ByLayer colour, like ABHD's.
;;;
;;; THE POOL BOTTOM assumes a STANDARD HOPPER, so it is generated, not
;;; traced: pick which end is deep, type where the two breaks fall and
;;; the hopper's side and back offsets, and the bottom is drawn square
;;; to the pool's own frame - the deep break as the classic three
;;; collinear pieces (dashed stubs, solid run between the hopper
;;; corners), the hopper as the offset rectangle, dead-straight slope
;;; lines to the shallow break ends, and the K/L/M dimension string a
;;; foot off the deep break on the shallow side.  On an L or Lazy L
;;; the deep end picks which leg the hopper lives in, angled leg
;;; included.  A Round pool gets a concentric hopper ring instead.
;;; Anything fancier than a standard hopper is ABHD/ADAB's job.
;;;
;;; Everything is fitted on the 2D plane - Z coordinates are ignored.
;;; tests/test_fitabhd.py mirrors the whole engine in Python, and its
;;; structural checks hold this file to the conventions above.
;;; ======================================================================

(setq *fitabhd-version* "v1.3")    ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

;; ---- configuration ---------------------------------------------------
(setq fit:*pool-layer*  "POOL")    ; layer the kept fit and bottom go on
(setq fit:*point-layer* "POINTS")  ; layer holding plain survey POINTs
(setq fit:*point-block* "ab_pt")   ; block whose INSERTs mark survey
                                   ; points; insertion point = location
(setq fit:*pt-tag*      "number")  ; attribute tag carrying the point
                                   ; number, for the miss report
(setq fit:*out-layer*   "POOL-FIT"); layer the preview outline goes on
(setq fit:*miss-layer*  "FGStep")  ; layer the stray-point rings go on;
                                   ; may already be in use, so FITABHD
                                   ; stamps its objects and only ever
                                   ; erases its own
(setq fit:*miss-radius* 4.0)       ; radius of those rings (4 inches)
(setq fit:*exact-eps*   0.001)     ; duplicate-point fuzz (units)
(setq fit:*on-eps*      0.25)      ; a point within this of the outline
                                   ; counts as ON it (ABHD's threshold)
(setq fit:*tol-max*     2.0)       ; ceiling on the max-distance prompt
                                   ; (2 inches): looser than that and
                                   ; the fit is no longer a trace
(setq fit:*corner-zone* 18.0)      ; starting radius of the corner
                                   ; zones: points inside belong to the
                                   ; corner feature, not the walls
(setq fit:*zone-pad*    4.0)       ; the zone refit sizes itself to
                                   ; 1.2 x the fitted radius plus this
(setq fit:*icp-iters*   12)        ; assignment/update rounds per
                                   ; placement - each is cheap and the
                                   ; walls settle in well under this
(setq fit:*rad-iters*   15)        ; centre/radius rounds for a Round
(setq fit:*rad-max*     120.0)     ; fillet-radius search ceiling (10')
(setq fit:*rad-turn-min* (/ pi 3.0)) ; only corners turning at least
                                   ; this (60 deg) vote for the shared
                                   ; radius or cut: a 45-degree bend's
                                   ; fillet apex sits under an inch off
                                   ; the sharp corner, so its zone
                                   ; holds mostly wall points, which
                                   ; would drag the fit way off
(setq fit:*both-edge*   0.8)       ; a both-ends cap fit must beat the
                                   ; best single-ended one by this
                                   ; factor: a big flat arc can always
                                   ; shave a little error off a
                                   ; genuinely square end
(setq fit:*snap-eps*    0.02)      ; a nice-dim snap may move the fit
                                   ; at most this far beyond where it
                                   ; already sat when a stray point is
                                   ; past the tolerance anyway
(setq fit:*vsize-min*   1.0)       ; a fitted corner easing smaller
                                   ; than this reads as sharp
(setq fit:*miss-pct*    0.15)      ; the standard share of the points
                                   ; allowed to sit beyond the distance;
                                   ; asked per run, and what a snap to a
                                   ; whole foot is allowed to spend
(setq fit:*bow-min*     1.0)       ; a bow shallower than this reads as
                                   ; a straight wall - an inch over
                                   ; thirty feet is drafting noise, and
                                   ; survey scatter alone can fake it
(setq fit:*bow-max*     12.0)      ; a wall bowed more than a foot is
                                   ; not a straight wall any more
(setq fit:*bow-max-frac* 0.04)     ; nor one bowed more than this share
                                   ; of its own length
(setq fit:*bow-pts-min* 4)         ; and one shot fewer times than this
                                   ; cannot tell a bow from noise
(setq fit:*oos-max* (/ pi 36.0))   ; how far a wall may swing off its
                                   ; template direction (5 degrees):
                                   ; further than that and the survey
                                   ; is not this type of pool at all
(setq fit:*oos-min*     1.0)       ; the drift from one end of a wall
                                   ; to the other below which the wall
                                   ; reads as true and is held there
(setq fit:*feat-snap*   0.1)       ; snapping a MEASURED feature (a
                                   ; corner radius, a cut face, a
                                   ; roman end radius) may grow the
                                   ; worst deviation by at most this -
                                   ; an 8" as-built corner must not
                                   ; become a foot just because the
                                   ; tolerance would absorb it
(setq fit:*nice-dims* '(12.0 6.0 1.0 0.5)) ; snapping increments, tried
                                   ; in order: whole feet, half feet,
                                   ; inches, half inches
(setq fit:*types* "Rectangle Grecian ROman Oval L LAzyl ROUnd")
                                   ; POOL's shape vocabulary, minus the
                                   ; shapes a template cannot say
                                   ; (Octagon rides Grecian, Mutt and
                                   ; freeform are ABHD's job)
(setq fit:*dim-off*     12.0)      ; the K/L/M string sits this far off
                                   ; the deep break, on the shallow side
(if (null fit:*tol*) (setq fit:*tol* 1.0))       ; remembered per session
(if (null fit:*oos*) (setq fit:*oos* T))  ; as-builts are never true
(if (null fit:*brk-deep*) (setq fit:*brk-deep* (cons 96.0 T)))
(if (null fit:*brk-shal*) (setq fit:*brk-shal* (cons 240.0 T)))
(if (null fit:*hop-side*) (setq fit:*hop-side* (cons 18.0 nil)))
(if (null fit:*hop-back*) (setq fit:*hop-back* (cons 18.0 nil)))

;; the template wall directions, one CCW ring per type (see below)
(setq fit:*rect-dirs* (list 0.0 (/ pi 2.0) pi (* pi 1.5)))
(setq fit:*grec-dirs* (list 0.0 (/ pi 4.0) (/ pi 2.0) (* pi 0.75)
                            pi (* pi 1.25) (* pi 1.5) (* pi 1.75)))
(setq fit:*l-dirs*    (list 0.0 (/ pi 2.0) pi (* pi 1.5) pi (* pi 1.5)))
(setq fit:*lazy-dirs* (list 0.0 (/ pi 4.0) (* pi 0.75) (* pi 1.25)
                            pi (* pi 1.5)))

;; ---- embedded shared helpers -----------------------------------------
;; Copies of the CALOFIN-LIB helpers this tool uses, under its own
;; prefix so the file loads alone with APPLOAD (the shared/ twin calls
;; cal: instead).  Bodies identical to the library's.

;; Keyword question.  kws is the initget string, shown the bracketed
;; list, dflt the Enter answer (nil = an answer is required).  Returns
;; the keyword or FIT-BACK.  Undo is a hidden synonym for Back.
(defun fit:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'FIT-BACK)
        ((null v) (if dflt dflt (fit:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No that can be backed out of.  Returns T, nil or FIT-BACK.
(defun fit:askyn (msg dflt back / v)
  (setq v (fit:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'FIT-BACK) v (= v "Yes")))

;; The Treatment question of STANDARDS.md section 2: "How should
;; <subject> be treated?"  Returns "Square", "Radius", "Cut" or
;; "NotGiven" - the legacy words and NG are accepted typed in full and
;; normalized HERE, never downstream - or FIT-BACK.
(defun fit:asktreat (subject dflt back / v)
  (setq v (fit:askkw (strcat "How should " subject " be treated?")
                     "Square Radius Cut NotGiven NG 90 ROUNDED DIAG DIAGONAL"
                     "Square/Radius/Cut/NotGiven"
                     dflt back))
  (cond ((= v "NG") "NotGiven")
        ((= v "90") "Square")
        ((= v "ROUNDED") "Radius")
        ((member v '("DIAG" "DIAGONAL")) "Cut")
        (t v)))

;; System-variable snapshot in a GLOBAL, taken only when none is
;; pending, so a run that died before restoring cannot make the next
;; run "restore" its zeroed settings.  OSMODE first in the list.
(defun fit:syssave (vars / v)
  (if (not fit:*sysold*)
      (foreach v vars
        (if (/= nil (getvar v))
            (setq fit:*sysold*
                  (append fit:*sysold* (list (cons v (getvar v)))))))))

(defun fit:sysrestore ( / p)
  (foreach p fit:*sysold* (setvar (car p) (cdr p)))
  (setq fit:*sysold* nil))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Returns the layer name.
(defun fit:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
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
                         " result is visible."))))))
  name)

;; 2-D vector helpers; inputs may be 2- or 3-element (the Z is dropped)
(defun fit:2d (p) (list (car p) (cadr p)))
(defun fit:dist (a b) (distance (fit:2d a) (fit:2d b)))
(defun fit:v- (a b) (mapcar '- (fit:2d a) (fit:2d b)))
(defun fit:v+ (a b) (mapcar '+ (fit:2d a) (fit:2d b)))
(defun fit:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun fit:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun fit:mid (a b) (fit:v* (fit:v+ a b) 0.5))
(defun fit:perp (v) (list (- (cadr v)) (car v))) ; rotate 90 deg CCW

;; normalize an angle into [0, 2pi)
(defun fit:angnorm (a)
  (while (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (while (>= a (* 2.0 pi)) (setq a (- a (* 2.0 pi))))
  a)

;; smallest signed angular difference (to - from), in (-pi, pi]
(defun fit:signed-dang (from to / d)
  (setq d (fit:angnorm (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

;; drop every point within EPS of a kept one, order preserved
(defun fit:dedupe (pts eps / out q p dup)
  (foreach q pts
    (setq dup nil)
    (foreach p out
      (if (< (fit:dist p q) eps) (setq dup T)))
    (if (not dup) (setq out (cons q out))))
  (reverse out))

;; smallest integer >= X (X non-negative)
(defun fit:ceil (x / f)
  (setq f (fix x))
  (if (> x f) (1+ f) f))

;; Tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn bulge yields a huge but finite number instead
;; of dividing by zero.
(defun fit:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;; The name carried by a point block, read from its TAG attribute; when
;; the block has no such attribute, the first attribute whose value
;; reads as a number is taken instead.  nil when neither exists.
(defun fit:block-number (en tag / sub ed val fall v)
  (setq sub (entnext en) val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase tag)))
      (setq val v))
    (if (and (null fall) v (distof v 2))
      (setq fall v))
    (setq sub (entnext sub)))
  (if val val fall))

;; ---- circle / arc geometry -------------------------------------------
;; The 2-element circumcenter abhd and lhd also keep locally - the
;; library's 3-element form is deliberately not used here (the fitter
;; is strictly 2D).

(defun fit:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
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

;; Arc geometry of a bulged segment: (center radius angStart angEnd);
;; nil for a straight segment.
(defun fit:arc-geom (p1 p2 b / ch dir apex c)
  (if (< (abs b) 1.0e-9)
    nil
    (progn
      (setq p1   (fit:2d p1)
            p2   (fit:2d p2)
            ch   (fit:dist p1 p2))
      (if (< ch 1.0e-12)
        nil
        (progn
          (setq dir  (fit:v* (fit:v- p2 p1) (/ 1.0 ch))
                ;; a positive (CCW) bulge apex lies to the RIGHT of the
                ;; p1->p2 chord direction
                apex (fit:v+ (fit:mid p1 p2)
                             (fit:v* (fit:perp dir) (* -0.5 ch b)))
                c    (fit:circumcenter p1 apex p2))
          (if (null c)
            nil
            (list c (fit:dist c p1) (angle c p1) (angle c p2))))))))

;; Distance from point P to segment (p1 p2 bulge).
(defun fit:seg-dist (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep rel)
  (setq p  (fit:2d p)
        p1 (fit:2d (car seg))
        p2 (fit:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    (progn
      (setq v    (fit:v- p2 p1)
            w    (fit:v- p p1)
            len2 (fit:dot v v))
      (if (< len2 1.0e-20)
        (fit:dist p p1)
        (progn
          (setq t2 (/ (fit:dot w v) len2))
          (if (< t2 0.0) (setq t2 0.0))
          (if (> t2 1.0) (setq t2 1.0))
          (fit:dist p (fit:v+ p1 (fit:v* v t2))))))
    (progn
      (setq g (fit:arc-geom p1 p2 b))
      (if (null g)
        (min (fit:dist p p1) (fit:dist p p2))
        (progn
          (setq c  (car g)  r (cadr g)
                a1 (caddr g) a2 (cadddr g)
                ap (angle c p))
          (if (> b 0.0)
            (setq sweep (fit:angnorm (- a2 a1)) rel (fit:angnorm (- ap a1)))
            (setq sweep (fit:angnorm (- a1 a2)) rel (fit:angnorm (- ap a2))))
          (if (<= rel sweep)
            (abs (- (fit:dist p c) r))
            (min (fit:dist p p1) (fit:dist p p2))))))))

;; Every point's distance to the nearest piece of the outline.
(defun fit:outline-dists (pts segs / out q s d dmin)
  (setq out nil)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (fit:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (setq out (cons dmin out)))
  (reverse out))

;; (worst rms) distance of the points from an outline.
(defun fit:outline-dev (pts segs / ds worst ssum d)
  (setq ds (fit:outline-dists pts segs) worst 0.0 ssum 0.0)
  (foreach d ds
    (if (> d worst) (setq worst d))
    (setq ssum (+ ssum (* d d))))
  (list worst (sqrt (/ ssum (length ds)))))

;; LST without ONE element equal to V.
(defun fit:drop-one (v lst / out done x)
  (setq out nil done nil)
  (foreach x lst
    (if (and (not done) (equal x v 1.0e-12))
      (setq done T)
      (setq out (cons x out))))
  (reverse out))

;; The worst deviation once the ALLOW worst points are set aside - what
;; the fit actually has to hold.  ALLOW = 0 is the plain worst.  This
;; is where the percent answered at step 4 gets spent: a snap to a
;; whole foot only has to convince all but that share of the points.
(defun fit:held-worst (dists allow / rest best d)
  (setq rest dists)
  (repeat allow
    (if rest
      (progn
        (setq best nil)
        (foreach d rest (if (or (null best) (> d best)) (setq best d)))
        (setq rest (fit:drop-one best rest)))))
  (setq best 0.0)
  (foreach d rest (if (> d best) (setq best d)))
  best)

;; What counts as ON the outline for this run.  It scales with the
;; tolerance (a quarter of it, never below fit:*on-eps*), exactly as
;; ABHD's does: if the user accepts 2 inches of error, a point half an
;; inch off is plainly still on the wall, and counting it against the
;; allowance would spend the whole budget on the first snap.
(defun fit:on-eps (tol)
  (max fit:*on-eps* (/ tol 4.0)))

;; Can the points live with this snap?
;;
;; A measured FEATURE - a corner radius, a cut face, an end radius -
;; may not grow the worst deviation at all beyond fit:*feat-snap*: it
;; is what it is.  A DESIGN dimension may spend the allowance: at most
;; ALLOW points may be pushed further off, and the snap may never push
;; a point past the tolerance that was not already there.  What
;; matters is what the snap CHANGES, not where the survey noise
;; already sits.
(defun fit:snap-ok (before after tol allow feature / on pushed badb bada
                                                    rest a b)
  (if feature
    (<= (fit:held-worst after 0)
        (+ (fit:held-worst before 0) fit:*feat-snap*))
    (progn
      (setq on     (fit:on-eps tol)
            pushed 0 badb 0 bada 0
            rest   after)
      (foreach b before
        (setq a    (car rest)
              rest (cdr rest))
        (if (> a (+ b on)) (setq pushed (1+ pushed)))
        (if (> b tol) (setq badb (1+ badb)))
        (if (> a tol) (setq bada (1+ bada))))
      (and (<= pushed allow) (<= bada badb)))))

;; ---- ordering and the frame ------------------------------------------

;; Remove every element equal (within fuzz) to VAL from LST.
(defun fit:remove (val lst / out x)
  (foreach x lst
    (if (not (equal x val 1.0e-9)) (setq out (cons x out))))
  (reverse out))

;; The member of LST nearest to P.
(defun fit:nearest (p lst / best bd q d)
  (setq best nil bd nil)
  (foreach q lst
    (setq d (fit:dist p q))
    (if (or (null bd) (< d bd)) (setq best q bd d)))
  best)

;; Order points into a closed tour: nearest-neighbour walk from the
;; leftmost point, then 2-opt passes to remove crossings (ABHD's).
(defun fit:order-points (pts / start cur tour rest best bd q d n i j k
                               pass improved ti ti1 tj tj1 delta head
                               midl taill)
  (setq start (car pts))
  (foreach q (cdr pts)
    (if (or (< (car q) (car start))
            (and (= (car q) (car start)) (< (cadr q) (cadr start))))
      (setq start q)))
  (setq cur  start
        rest (fit:remove start pts)
        tour (list start))
  (while rest
    (setq best nil bd nil)
    (foreach q rest
      (setq d (fit:dist cur q))
      (if (or (null bd) (< d bd)) (setq best q bd d)))
    (setq tour (cons best tour)
          cur  best
          rest (fit:remove best rest)))
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
                  delta (- (+ (fit:dist ti tj) (fit:dist ti1 tj1))
                           (+ (fit:dist ti ti1) (fit:dist tj tj1))))
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

;; Dominant wall direction folded modulo (2pi/fold).  Every edge of the
;; ordered ring votes with its length; folding by 4 makes parallel and
;; perpendicular walls reinforce each other, and folding by 8 pulls the
;; 45-degree walls of a Lazy L into the same vote instead of letting
;; the two families cancel.
(defun fit:frame-angle (tour fold / sx sy n i a b ln d)
  (setq sx 0.0 sy 0.0 n (length tour) i 0)
  (while (< i n)
    (setq a  (nth i tour)
          b  (nth (rem (1+ i) n) tour)
          ln (fit:dist a b))
    (if (> ln 1.0e-9)
      (progn
        (setq d (* fold (angle a b)))
        (setq sx (+ sx (* ln (cos d)))
              sy (+ sy (* ln (sin d))))))
    (setq i (1+ i)))
  (if (and (< (abs sx) 1.0e-12) (< (abs sy) 1.0e-12))
    0.0
    (rem (/ (fit:angnorm (atan sy sx)) fold) (/ (* 2.0 pi) fold))))

;; rotate P by angle A about the origin
(defun fit:rot (p a / c s)
  (setq c (cos a) s (sin a))
  (list (- (* (car p) c) (* (cadr p) s))
        (+ (* (car p) s) (* (cadr p) c))))

;; World -> frame: rotate by -A, then mirror across X if asked.
(defun fit:to-frame (pts a mirror / out p q)
  (setq out nil)
  (foreach p pts
    (setq q (fit:rot (fit:2d p) (- a)))
    (setq out (cons (if mirror (list (car q) (- (cadr q))) q) out)))
  (reverse out))

;; one point back out of the frame
(defun fit:from-frame (p a mirror)
  (fit:rot (if mirror (list (car p) (- (cadr p))) p) a))

;; Bounding box of a point list, as (minx miny maxx maxy).
(defun fit:bbox (pts / x0 y0 x1 y1 q)
  (foreach q pts
    (if (null x0)
      (setq x0 (car q) x1 (car q) y0 (cadr q) y1 (cadr q))
      (setq x0 (min x0 (car q)) x1 (max x1 (car q))
            y0 (min y0 (cadr q)) y1 (max y1 (cadr q)))))
  (list x0 y0 x1 y1))

;; ---- the fixed-direction polygon fit (the ICP core) ------------------
;; A template polygon is a CCW ring of walls whose DIRECTIONS are fixed
;; by the pool type; only each wall's offset along its outward normal
;; is fitted.  That is what knowing the type buys: a Lazy L's bend
;; walls are at exactly 45 degrees, so the survey only has to say
;; WHERE they are, never what they are.

;; Outward normal of a CCW ring edge with direction angle D.
(defun fit:wall-normal (d)
  (list (sin d) (- (cos d))))

;; Corner list: corner i joins wall i-1 to wall i.  nil when two
;; neighbouring walls are parallel.
(defun fit:poly-corners (dirs offs / n i n1 n2 d1 d2 det out prev bad)
  (setq n (length dirs) i 0 out nil bad nil)
  (while (and (< i n) (not bad))
    (setq prev (rem (+ i n -1) n)
          n1   (fit:wall-normal (nth prev dirs))
          d1   (nth prev offs)
          n2   (fit:wall-normal (nth i dirs))
          d2   (nth i offs)
          det  (- (* (car n1) (cadr n2)) (* (cadr n1) (car n2))))
    (if (< (abs det) 1.0e-12)
      (setq bad T)
      (setq out (cons (list (/ (- (* d1 (cadr n2)) (* d2 (cadr n1))) det)
                            (/ (- (* d2 (car n1)) (* d1 (car n2))) det))
                      out)))
    (setq i (1+ i)))
  (if bad nil (reverse out)))

;; A fitted polygon is only believable when every edge still runs in
;; its template direction - a collapsed or bow-tied fit reverses one,
;; and can still hug the points, so it must be rejected.
(defun fit:poly-valid (dirs offs / c n i u v ok)
  (setq c (fit:poly-corners dirs offs))
  (if (null c)
    nil
    (progn
      (setq n (length c) i 0 ok T)
      (while (< i n)
        (setq u (list (cos (nth i dirs)) (sin (nth i dirs)))
              v (fit:v- (nth (rem (1+ i) n) c) (nth i c)))
        (if (<= (fit:dot u v) 1.0e-6) (setq ok nil))
        (setq i (1+ i)))
      ok)))

;; N empty buckets / cons P onto bucket I.
(defun fit:empty-buckets (n / out)
  (repeat n (setq out (cons nil out)))
  out)
(defun fit:bucket-add (bkts i p / out k b)
  (setq out nil k 0)
  (foreach b bkts
    (setq out (cons (if (= k i) (cons p b) b) out)
          k   (1+ k)))
  (reverse out))

;; Nearest-wall buckets, with points inside a corner's ZONE pulled into
;; that corner's bucket instead.  Returns (wallpts cornerpts), each a
;; list of per-index point lists.  Corner i sits between wall i-1 and
;; wall i.
(defun fit:assign-walls (pts dirs offs zone / corners n wallpts cornerpts
                                              segs i p best bd d dc1 dc2 k)
  (setq corners (fit:poly-corners dirs offs)
        n       (length dirs)
        wallpts (fit:empty-buckets n)
        cornerpts (fit:empty-buckets n))
  (if corners
    (progn
      (setq segs nil i 0)
      (while (< i n)
        (setq segs (cons (list (nth i corners)
                               (nth (rem (1+ i) n) corners) 0.0) segs)
              i    (1+ i)))
      (setq segs (reverse segs))
      (foreach p pts
        (setq best 0 bd nil i 0)
        (foreach d (mapcar '(lambda (s) (fit:seg-dist p s)) segs)
          (if (or (null bd) (< d bd)) (setq best i bd d))
          (setq i (1+ i)))
        (setq dc1 (fit:dist p (nth best corners))
              dc2 (fit:dist p (nth (rem (1+ best) n) corners)))
        (if (or (< dc1 zone) (< dc2 zone))
          (progn
            (setq k (if (<= dc1 dc2) best (rem (1+ best) n)))
            (setq cornerpts (fit:bucket-add cornerpts k p)))
          (setq wallpts (fit:bucket-add wallpts best p))))))
  (list wallpts cornerpts))

;; Iterate assignment / offset update.  Offsets a wall never sees a
;; point for stay where they are.
(defun fit:fit-polygon (pts dirs offs zone iters / wallpts new i nrm b
                                                   ssum c)
  (repeat iters
    (setq wallpts (car (fit:assign-walls pts dirs offs zone)))
    (setq new nil i 0)
    (foreach b wallpts
      (if b
        (progn
          (setq nrm  (fit:wall-normal (nth i dirs))
                ssum 0.0)
          (foreach c b
            (setq ssum (+ ssum (fit:dot nrm c))))
          (setq new (cons (/ ssum (length b)) new)))
        (setq new (cons (nth i offs) new)))
      (setq i (1+ i)))
    (setq new (reverse new))
    (if (fit:poly-corners dirs new) (setq offs new)))
  offs)

;; (turn angle, fillet-centre direction unit) at corner i (between wall
;; i-1 and wall i).  A convex corner's fillet centre sits along the
;; interior bisector; a concave (notch) corner's sits along the
;; exterior one - the arc bows out of the pool there.
(defun fit:corner-frame (dirs i / n prev turn n1 n2 s bx by ln)
  (setq n    (length dirs)
        prev (rem (+ i n -1) n)
        turn (fit:signed-dang (nth prev dirs) (nth i dirs))
        n1   (fit:wall-normal (nth prev dirs))
        n2   (fit:wall-normal (nth i dirs))
        s    (if (> turn 0.0) -1.0 1.0)
        bx   (* s (+ (car n1) (car n2)))
        by   (* s (+ (cadr n1) (cadr n2)))
        ln   (sqrt (+ (* bx bx) (* by by))))
  (if (< ln 1.0e-9)
    (list turn (list 0.0 0.0))
    (list turn (list (/ bx ln) (/ by ln)))))

;; Mean squared radial error of the shared fillet radius R over the
;; corner-zone points (a list of (index . point) pairs).
(defun fit:corner-err (allpts corners dirs r / ssum n ip cf turn bis half
                                               cc e)
  (setq ssum 0.0 n 0)
  (foreach ip allpts
    (setq cf   (fit:corner-frame dirs (car ip))
          turn (car cf)
          bis  (cadr cf)
          half (/ (abs turn) 2.0))
    ;; the centre sits r / cos(turn/2) from the vertex - the interior
    ;; half-angle is 90 - turn/2, so this equals the familiar r*sqrt(2)
    ;; only at a square corner
    (if (>= (cos half) 1.0e-9)
      (progn
        (setq cc (fit:v+ (nth (car ip) corners)
                         (fit:v* bis (/ r (cos half))))
              e  (- (fit:dist (cdr ip) cc) r))
        (setq ssum (+ ssum (* e e))
              n    (1+ n)))))
  (if (> n 0) (/ ssum n)))

;; One shared fillet radius over the corners listed in VOTERS, fitted
;; by golden-section search - the direct fixed-point update is unstable
;; for this geometry.  nil when nothing landed in a zone.
(defun fit:fit-corner-radius (cpts corners dirs voters / allpts i p gr lo
                                                         hi a b fa fb)
  (setq allpts nil)
  (foreach i voters
    (foreach p (nth i cpts)
      (setq allpts (cons (cons i p) allpts))))
  (if (null allpts)
    nil
    (progn
      (setq gr 0.6180339887
            lo 0.25
            hi fit:*rad-max*
            a  (- hi (* gr (- hi lo)))
            b  (+ lo (* gr (- hi lo)))
            fa (fit:corner-err allpts corners dirs a)
            fb (fit:corner-err allpts corners dirs b))
      (if (or (null fa) (null fb))
        nil
        (progn
          (repeat 48
            (if (<= fa fb)
              (setq hi b  b a  fb fa
                    a  (- hi (* gr (- hi lo)))
                    fa (fit:corner-err allpts corners dirs a))
              (setq lo a  a b  fa fb
                    b  (+ lo (* gr (- hi lo)))
                    fb (fit:corner-err allpts corners dirs b))))
          (/ (+ lo hi) 2.0))))))

;; One shared cut-face length: the chamfer line's perpendicular inset
;; from each corner, fitted as a plain mean.  Notch corners take no
;; cut.  nil when nothing landed in a zone.
(defun fit:fit-corner-cut (cpts corners dirs voters / hsum n i cf turn bis
                                                      p h)
  (setq hsum 0.0 n 0 turn nil)
  (foreach i voters
    (setq cf (fit:corner-frame dirs i))
    (if (> (car cf) 0.0)
      (progn
        (setq turn (car cf)
              bis  (cadr cf))
        (foreach p (nth i cpts)
          (setq hsum (+ hsum (fit:dot bis (fit:v- p (nth i corners))))
                n    (1+ n))))))
  (if (or (= n 0) (null turn))
    nil
    (progn
      (setq h (/ hsum n))
      ;; face length from the perpendicular inset: f = 2h / tan(turn/2)
      ;; (the familiar f = 2h only at a square corner)
      (if (<= h 0.0)
        nil
        (/ (* 2.0 h) (fit:tan (/ (abs turn) 2.0)))))))

;; ---- building the drawn outline --------------------------------------

;; The vertex run replacing sharp corner V: a list of (pt bulge).  The
;; bulge on an entry curves the segment LEAVING that point.
(defun fit:corner-verts (vprev v vnext turn treat size / u1 u2 t2 s p1 p2)
  (cond
    ((and (= treat "Radius") size (> size 1.0e-6))
     (setq u1 (angle vprev v)
           u2 (angle v vnext)
           t2 (* size (fit:tan (/ (abs turn) 2.0)))
           p1 (list (- (car v) (* (cos u1) t2))
                    (- (cadr v) (* (sin u1) t2)))
           p2 (list (+ (car v) (* (cos u2) t2))
                    (+ (cadr v) (* (sin u2) t2))))
     (list (list p1 (fit:tan (/ turn 4.0))) (list p2 0.0)))
    ((and (= treat "Cut") size (> size 1.0e-6) (> turn 0.0))
     (setq u1 (angle vprev v)
           u2 (angle v vnext)
           s  (/ size (* 2.0 (cos (/ (abs turn) 2.0))))
           p1 (list (- (car v) (* (cos u1) s))
                    (- (cadr v) (* (sin u1) s)))
           p2 (list (+ (car v) (* (cos u2) s))
                    (+ (cadr v) (* (sin u2) s))))
     (list (list p1 0.0) (list p2 0.0)))
    (T (list (list v 0.0)))))

;; Bulge for the drawn chord A->B carrying the bow fitted as sagitta S
;; over the corner-to-corner chord CFIT.  The RADIUS is what is
;; preserved, so an eased corner shortening the wall does not deepen
;; its bow.  A positive sagitta bows OUTWARD: on a CCW ring a positive
;; bulge puts the arc's apex to the right of travel, which is the
;; outward side.
(defun fit:bow-bulge (s cfit a b / c r x half bl)
  (setq c (fit:dist a b))
  (if (or (null s) (equal s 0.0 1.0e-12) (< cfit 1.0e-9) (< c 1.0e-9))
    0.0
    (progn
      (setq r (+ (/ (* cfit cfit) (* 8.0 (abs s))) (/ (abs s) 2.0))
            x (/ c (* 2.0 r)))
      (if (>= x 1.0)
        0.0
        (progn
          ;; half the included angle: asin(x), written with atan
          (setq half (atan (/ x (sqrt (- 1.0 (* x x)))))
                bl   (fit:tan (/ half 2.0)))
          (if (> s 0.0) bl (- bl)))))))

;; closed (pt bulge) vertex list -> (p1 p2 bulge) segment list
(defun fit:verts-to-segs (verts / n i out)
  (setq n (length verts) i 0 out nil)
  (while (< i n)
    (setq out (cons (list (car (nth i verts))
                          (car (nth (rem (1+ i) n) verts))
                          (cadr (nth i verts)))
                    out)
          i   (1+ i)))
  (reverse out))

;; Closed vertex list for the fitted polygon; WHICH non-nil applies the
;; corner treatment to every corner (nil leaves them all sharp), and
;; BOWS (nil = none) gives each wall its own fitted bow.  A bow never
;; moves a corner: it vanishes at both ends of its wall by
;; construction, so every design dimension taken between corners
;; survives it untouched.
(defun fit:build-polygon (dirs offs treat size which bows / corners n
                                                            verts leaves
                                                            i cf m k a b
                                                            cfit)
  (setq corners (fit:poly-corners dirs offs)
        n       (length corners)
        verts   nil
        leaves  nil
        i       0)
  (while (< i n)
    (setq cf (fit:corner-frame dirs i))
    (if which
      (setq verts (append verts
                          (fit:corner-verts
                            (nth (rem (+ i n -1) n) corners)
                            (nth i corners)
                            (nth (rem (1+ i) n) corners)
                            (car cf) treat size)))
      (setq verts (append verts (list (list (nth i corners) 0.0)))))
    (setq leaves (cons (1- (length verts)) leaves)   ; wall i leaves here
          i      (1+ i)))
  (setq leaves (reverse leaves))
  (if bows
    (progn
      (setq m (length verts) i 0)
      (while (< i n)
        (if (and (nth i bows) (not (equal (nth i bows) 0.0 1.0e-12)))
          (setq k     (nth i leaves)
                a     (car (nth k verts))
                b     (car (nth (rem (1+ k) m) verts))
                cfit  (fit:dist (nth i corners)
                                (nth (rem (1+ i) n) corners))
                verts (fit:setnth verts k
                                  (list a (fit:bow-bulge (nth i bows)
                                                         cfit a b)))))
        (setq i (1+ i)))))
  verts)

;; ---- bowed walls -----------------------------------------------------
;; "Straight" is a drafting convention, not a site measurement: a
;; gunite wall shot dead straight on the order sheet is very often a
;; very long radius on the ground.  When the user says the walls may
;; be bowed, each wall is refitted as a constant offset plus a
;; parabolic bow that vanishes at both corners - so the corners, and
;; every dimension taken between them, stay exactly where the straight
;; fit put them, and only the wall between them breathes.

;; Small Gauss-Jordan with partial pivoting; nil when singular.  MAT is
;; a list of rows, RHS a list; both N long.
(defun fit:solve-lin (mat rhs n / aug i c r piv d f row cr out)
  (setq aug nil i 0)
  (while (< i n)
    (setq aug (cons (append (nth i mat) (list (nth i rhs))) aug)
          i   (1+ i)))
  (setq aug (reverse aug) c 0)
  (while (and aug (< c n))
    (setq piv c r c)
    (while (< r n)
      (if (> (abs (nth c (nth r aug))) (abs (nth c (nth piv aug))))
        (setq piv r))
      (setq r (1+ r)))
    (if (< (abs (nth c (nth piv aug))) 1.0e-12)
      (setq aug nil)                        ; singular
      (progn
        ;; swap rows c and piv
        (setq row (nth c aug)
              aug (fit:setnth aug c (nth piv aug))
              aug (fit:setnth aug piv row)
              d   (nth c (nth c aug))
              aug (fit:setnth aug c
                              (mapcar '(lambda (v) (/ v d)) (nth c aug)))
              cr  (nth c aug)
              r   0)
        (while (< r n)
          (if (/= r c)
            (progn
              (setq f (nth c (nth r aug)))
              (if (/= f 0.0)
                (setq aug (fit:setnth
                            aug r
                            (mapcar '(lambda (v w) (- v (* f w)))
                                    (nth r aug) cr))))))
          (setq r (1+ r)))
        (setq c (1+ c)))))
  (if (null aug)
    nil
    (progn
      (setq out nil i 0)
      (while (< i n)
        (setq out (cons (nth n (nth i aug)) out) i (1+ i)))
      (reverse out))))

;; Least-squares wall through its own points, in the wall's own frame
;; (t along the chord A->B, y outward):
;;
;;     y = A + B*t + C*4t(1-t)
;;
;; A is where the wall sits, B how far it DRIFTS from one end to the
;; other - the wall swinging off its template direction, which is what
;; an out-of-square pool is made of - and C how far it BOWS at
;; mid-wall.  Terms not asked for are held at zero and left out of the
;; solve.  Returns (A B C), or nil when the wall has too few points to
;; tell any of it from noise.
(defun fit:fit-wall-line (wpts a b want-swing want-bow / c ux uy nx ny use
                                                        k mat rhs row i j
                                                        p dx dy tt f y got
                                                        out)
  (setq c (fit:dist a b))
  (if (< c 1.0e-9)
    nil
    (progn
      (setq use (list 0))
      (if want-swing (setq use (append use (list 1))))
      (if want-bow (setq use (append use (list 2))))
      (setq k (length use))
      (if (< (length wpts) (max fit:*bow-pts-min* (1+ k)))
        nil
        (progn
          (setq ux (/ (- (car b) (car a)) c)
                uy (/ (- (cadr b) (cadr a)) c)
                nx uy                       ; right of travel = outward
                ny (- ux)
                mat nil rhs nil i 0)
          (while (< i k)
            (setq row nil j 0)
            (while (< j k) (setq row (cons 0.0 row) j (1+ j)))
            (setq mat (cons row mat)
                  rhs (cons 0.0 rhs)
                  i   (1+ i)))
          (foreach p wpts
            (setq dx (- (car p) (car a))
                  dy (- (cadr p) (cadr a))
                  tt (/ (+ (* dx ux) (* dy uy)) c)
                  f  (list 1.0 tt (* 4.0 tt (- 1.0 tt)))
                  y  (+ (* dx nx) (* dy ny))
                  i  0)
            (while (< i k)
              (setq rhs (fit:setnth
                          rhs i (+ (nth i rhs)
                                   (* (nth (nth i use) f) y)))
                    j   0)
              (while (< j k)
                (setq mat (fit:setnth
                            mat i
                            (fit:setnth (nth i mat) j
                                        (+ (nth j (nth i mat))
                                           (* (nth (nth i use) f)
                                              (nth (nth j use) f)))))
                      j   (1+ j)))
              (setq i (1+ i))))
          (setq got (fit:solve-lin mat rhs k))
          (if (null got)
            nil
            (progn
              (setq out (list 0.0 0.0 0.0) i 0)
              (while (< i k)
                (setq out (fit:setnth out (nth i use) (nth i got))
                      i   (1+ i)))
              out)))))))

;; The wall line A->B (template direction D) after its fitted offset
;; and drift are applied: (new-direction new-outward-offset).  The
;; drift is a ROTATION, so the wall stays a straight line - the pool
;; goes out of square, it does not go crooked.
(defun fit:swung-wall (a b d coef / c ux uy nx ny d2 q n2)
  (setq c  (fit:dist a b)
        ux (/ (- (car b) (car a)) c)
        uy (/ (- (cadr b) (cadr a)) c)
        nx uy
        ny (- ux)
        d2 (- d (atan (cadr coef) c))
        q  (list (+ (car a) (* nx (car coef)))
                 (+ (cadr a) (* ny (car coef))))
        n2 (fit:wall-normal d2))
  (list d2 (fit:dot n2 q)))

;; RMS of the points about the straight line with direction D at
;; outward offset OFF - the wall as the template would hold it.
(defun fit:flat-rms (wpts d off / nrm ssum p e)
  (setq nrm (fit:wall-normal d) ssum 0.0)
  (if (null wpts)
    0.0
    (progn
      (foreach p wpts
        (setq e (- (fit:dot nrm p) off) ssum (+ ssum (* e e))))
      (sqrt (/ ssum (length wpts))))))

;; RMS of the points about the drawn segment A->B with this bulge.
(defun fit:wall-rms (wpts a b bulge)
  (if (null wpts) 0.0 (cadr (fit:outline-dev wpts (list (list a b bulge))))))

;; The mean outward offset of a wall's own points - the wall as the
;; template holds it, with no drift and no bow.
(defun fit:flat-off (wpts d dflt / nrm ssum p)
  (if (null wpts)
    dflt
    (progn
      (setq nrm (fit:wall-normal d) ssum 0.0)
      (foreach p wpts (setq ssum (+ ssum (fit:dot nrm p))))
      (/ ssum (length wpts)))))

;; A bow may not be deeper than a wall can bow and still be a wall.
(defun fit:bow-cap (s c / smax)
  (setq smax (min fit:*bow-max* (* fit:*bow-max-frac* c)))
  (max (- smax) (min smax s)))

;; A bow is kept only when it is deep enough to read, shallow enough to
;; still be a wall, and beats the straight wall on that wall's own
;; points by a clear margin.  Noise is not a bow.
(defun fit:keep-bow (wpts a b s / c rs rb)
  (setq c (fit:dist a b))
  (if (or (null s) (equal s 0.0 1.0e-12) (< c 1.0e-9)
          (< (length wpts) fit:*bow-pts-min*)
          (< (abs s) fit:*bow-min*))
    0.0
    (progn
      (setq rs (cadr (fit:outline-dev wpts (list (list a b 0.0))))
            rb (cadr (fit:outline-dev
                       wpts
                       (list (list a b (fit:bow-bulge s c a b))))))
      (if (<= rb (* rs fit:*both-edge*)) s 0.0))))

;; ---- template starting guesses ---------------------------------------

;; Largest n.p over the points for wall direction D - the outermost
;; line the cloud supports in that normal direction.
(defun fit:support (pts d / nrm best p v)
  (setq nrm (fit:wall-normal d) best nil)
  (foreach p pts
    (setq v (fit:dot nrm p))
    (if (or (null best) (> v best)) (setq best v)))
  best)

(defun fit:rect-init (pts / d out)
  (setq out nil)
  (foreach d fit:*rect-dirs*
    (setq out (cons (fit:support pts d) out)))
  (reverse out))

(defun fit:grec-init (pts / i d out)
  (setq out nil i 0)
  (foreach d fit:*grec-dirs*
    ;; axis walls at their support line, cut walls a nominal 15" in
    (setq out (cons (if (= 0 (rem i 2))
                      (fit:support pts d)
                      (- (fit:support pts d) 15.0))
                    out)
          i   (1+ i))
    )
  (reverse out))

;; Starting hexagon for the L shapes, from the bounding box: the true L
;; guesses its notch at the middle, the lazy L a constant-width channel
;; bent at 45 degrees.
(defun fit:l-init (pts lazy / bb x0 y0 x1 y1 ex ey w0 cyy b c d t2 e
                             corners dirs offs i nrm)
  (setq bb (fit:bbox pts)
        x0 (car bb) y0 (cadr bb) x1 (caddr bb) y1 (cadddr bb))
  (if (not lazy)
    (progn
      (setq ex (+ x0 (* 0.5 (- x1 x0)))
            ey (+ y0 (* 0.5 (- y1 y0)))
            corners (list (list x0 y0) (list x1 y0) (list x1 y1)
                          (list ex y1) (list ex ey) (list x0 ey))
            dirs fit:*l-dirs*))
    (progn
      (setq w0  (* 0.45 (min (- x1 x0) (- y1 y0)))
            cyy (+ y0 (* 0.5 (- y1 y0)))
            b   (list (- x1 (- cyy y0)) y0)
            c   (list x1 cyy)
            d   (list (- x1 (- y1 cyy)) y1)
            t2  (/ (- y1 (+ y0 w0)) 0.7071067812)
            e   (list (- (car d) (* t2 0.7071067812)) (+ y0 w0))
            corners (list (list x0 y0) b c d e (list x0 (+ y0 w0)))
            dirs fit:*lazy-dirs*)))
  (setq offs nil i 0)
  (while (< i 6)
    (setq nrm  (fit:wall-normal (nth i dirs))
          offs (cons (fit:dot nrm (nth i corners)) offs)
          i    (1+ i)))
  (reverse offs))

;; Where the four AXIS walls of an eight-wall template would meet if
;; the cuts were not there - the pool's nominal corners.  Taken from
;; the walls themselves, so it still means something once they have
;; swung out of square.
(defun fit:grec-axis-corners (dirs offs)
  (fit:poly-corners (list (nth 0 dirs) (nth 2 dirs)
                          (nth 4 dirs) (nth 6 dirs))
                    (list (nth 0 offs) (nth 2 offs)
                          (nth 4 offs) (nth 6 offs))))

;; A cut wall bisects the corner it crosses, whatever the two axis
;; walls are doing - exactly 45 degrees on a true pool, and still a
;; real cut on an out-of-square one.
(defun fit:grec-cut-dir (dirs k / d0 d1)
  (setq d0 (nth (* 2 k) dirs)
        d1 (nth (rem (+ (* 2 k) 2) 8) dirs))
  (+ d0 (/ (fit:signed-dang d0 d1) 2.0)))

;; The mean cut-face length the four fitted cut walls imply.
(defun fit:grec-face (dirs offs / sq k i nrm vc hsum)
  (setq sq (fit:grec-axis-corners dirs offs))
  (if (null sq)
    0.0
    (progn
      (setq hsum 0.0 k 0)
      (while (< k 4)
        (setq i   (1+ (* 2 k))
              nrm (fit:wall-normal (nth i dirs))
              vc  (nth (rem (1+ k) 4) sq))
        (setq hsum (+ hsum (- (fit:dot nrm vc) (nth i offs)))
              k    (1+ k)))
      (* 2.0 (/ hsum 4.0)))))

;; Re-derive the four cut walls from the four axis walls: each bisects
;; its corner and sits the same perpendicular inset (face/2) in from
;; where the axis walls would meet.  Returns (dirs offs).
(defun fit:grec-cuts (dirs offs face / sq k i nrm vc h)
  (setq sq (fit:grec-axis-corners dirs offs))
  (if (null sq)
    (list dirs offs)
    (progn
      (setq h (/ face 2.0) k 0)
      (while (< k 4)
        (setq i    (1+ (* 2 k))
              dirs (fit:setnth dirs i (fit:grec-cut-dir dirs k))
              nrm  (fit:wall-normal (nth i dirs))
              vc   (nth (rem (1+ k) 4) sq)
              offs (fit:setnth offs i (- (fit:dot nrm vc) h))
              k    (1+ k)))
      (list dirs offs))))

(defun fit:setnth (lst i v / out k x)
  (setq out nil k 0)
  (foreach x lst
    (setq out (cons (if (= k i) v x) out)
          k   (1+ k)))
  (reverse out))

;; The as-built easing of an 8-wall template's vertices: one shared
;; fillet radius (or chamfer face) over all eight 45-degree corners.
;; A nominal grecian is drawn sharp, but an as-built very often is
;; not.  The corner zone is sized to the 45-degree turn (tangent
;; length 0.414r), so wall points stay out of the vote, and the easing
;; is kept only when it beats the sharp outline on the corner points
;; by a clear margin - noise is not evidence, and neither is a fit
;; below fit:*vsize-min*.  Returns (vsize offs face).
(defun fit:fit-vertex-feature (pts dirs offs treat / tanh cosh which zone
                                                    vs cpts face asg got2
                                                    corners czpts b p
                                                    sharp eased rs re2)
  (setq tanh  (fit:tan (/ pi 8.0))
        cosh  (cos (/ pi 8.0))
        which '(0 1 2 3 4 5 6 7)
        zone  (* fit:*corner-zone* tanh)
        vs    nil
        cpts  nil
        face  (fit:grec-face dirs offs))
  (repeat 2
    (setq asg     (fit:assign-walls pts dirs offs zone)
          cpts    (cadr asg)
          corners (fit:poly-corners dirs offs)
          vs      (if (= treat "Radius")
                    (fit:fit-corner-radius cpts corners dirs which)
                    (fit:fit-corner-cut cpts corners dirs which)))
    (if vs
      (progn
        ;; a fillet longer than the cut face cannot exist
        (setq vs   (min vs (/ face (* 2.0 tanh)))
              zone (if (= treat "Radius")
                     (+ (* 1.2 vs tanh) fit:*zone-pad*)
                     (+ (/ (* 1.2 vs) (* 2.0 cosh)) fit:*zone-pad*))
              offs (fit:fit-polygon pts dirs offs zone fit:*icp-iters*)
              face (fit:grec-face dirs offs)
              got2 (fit:grec-cuts dirs offs face)
              dirs (car got2)
              offs (cadr got2)))))
  (if (and vs (>= vs fit:*vsize-min*) cpts)
    (progn
      (setq czpts nil)
      (foreach b cpts
        (foreach p b (setq czpts (cons p czpts))))
      (if czpts
        (progn
          (setq sharp (fit:verts-to-segs
                        (fit:build-polygon dirs offs treat nil nil
                                           nil))
                eased (fit:verts-to-segs
                        (fit:build-polygon dirs offs treat vs T nil))
                rs    (cadr (fit:outline-dev czpts sharp))
                re2   (cadr (fit:outline-dev czpts eased)))
          (if (> re2 (* rs fit:*both-edge*)) (setq vs nil)))
        (setq vs nil)))
    (setq vs nil))
  (setq face (fit:grec-face dirs offs)
        got2 (fit:grec-cuts dirs offs face)
        dirs (car got2)
        offs (cadr got2))
  (list vs offs face))

;; Shared fit for the all-straight-wall types: walls, then the corner
;; feature, then walls again with the zone sized to it.  Returns
;; (offs size).
(defun fit:fit-polytype (pts dirs offs0 treat / zone offs size voters n i
                                                cpts corners)
  (setq zone (if (member treat '("Radius" "Cut")) fit:*corner-zone* 0.0)
        offs (fit:fit-polygon pts dirs offs0 zone fit:*icp-iters*)
        size nil)
  (if (member treat '("Radius" "Cut"))
    (progn
      ;; only corners that turn hard enough vote for the size (see
      ;; fit:*rad-turn-min*)
      (setq voters nil n (length dirs) i 0)
      (while (< i n)
        (if (>= (abs (fit:signed-dang (nth (rem (+ i n -1) n) dirs)
                                      (nth i dirs)))
                (- fit:*rad-turn-min* 1.0e-9))
          (setq voters (cons i voters)))
        (setq i (1+ i)))
      (setq voters  (reverse voters)
            cpts    (cadr (fit:assign-walls pts dirs offs zone))
            corners (fit:poly-corners dirs offs)
            size    (if (= treat "Radius")
                      (fit:fit-corner-radius cpts corners dirs voters)
                      (fit:fit-corner-cut cpts corners dirs voters)))
      (if (and size (= treat "Radius"))
        (progn
          ;; the zone refit: size the corner zones to the radius found,
          ;; refit the walls without their fillet points, re-fit the
          ;; radius.  (A cut keeps its first pass - a wide second zone
          ;; would drag wall points into the face estimate.)
          (setq zone    (+ (* 1.2 size) fit:*zone-pad*)
                offs    (fit:fit-polygon pts dirs offs zone
                                         fit:*icp-iters*)
                cpts    (cadr (fit:assign-walls pts dirs offs zone))
                corners (fit:poly-corners dirs offs)
                size    (fit:fit-corner-radius cpts corners dirs
                                               voters))))))
  (list offs size))

;; Let every wall answer to its own points.
;;
;; The template fixed each wall's DIRECTION, which is what makes the
;; type mean anything - but a real as-built is never true, and holding
;; a rectangle perfectly square just pushes the error into the points.
;; So each wall is refitted here: its offset always, its direction when
;; the pool may be out of square, its bow when the walls may be bowed.
;; Each of those is then kept only where the points prove it, so a pool
;; that really is square comes out square.
;;
;; Returns (dirs offs bows).
(defun fit:refine-walls (pts dirs offs zone oos bowed / n base coefs
                                                       wallpts corners nd
                                                       no i a b got d2o
                                                       bows wpts swing
                                                       drift flat got2)
  (setq n     (length dirs)
        base  dirs
        coefs nil
        i     0)
  (repeat n (setq coefs (cons nil coefs)))
  (repeat 3
    (setq wallpts (car (fit:assign-walls pts dirs offs zone))
          corners (fit:poly-corners dirs offs))
    (if corners
      (progn
        (setq nd dirs no offs i 0)
        (while (< i n)
          (setq a   (nth i corners)
                b   (nth (rem (1+ i) n) corners)
                got (fit:fit-wall-line (nth i wallpts) a b oos bowed))
          (if got
            (progn
              (setq coefs (fit:setnth coefs i got)
                    d2o   (fit:swung-wall a b (nth i dirs) got))
              (if (<= (abs (fit:signed-dang (nth i base) (car d2o)))
                      fit:*oos-max*)
                (setq nd (fit:setnth nd i (car d2o))
                      no (fit:setnth no i (cadr d2o)))
                (setq no (fit:setnth no i (+ (nth i offs) (car got)))))))
          (setq i (1+ i)))
        ;; on an eight-wall template the cut corners are not free
        ;; walls: each bisects its own corner and all four share one
        ;; face, however far the axis walls have swung
        (if (= n 8)
          (setq got2 (fit:grec-cuts nd no (fit:grec-face nd no))
                nd   (car got2)
                no   (cadr got2)))
        (if (fit:poly-valid nd no) (setq dirs nd offs no)))))
  ;; ---- what did the points actually earn? --------------------------
  (setq wallpts (car (fit:assign-walls pts dirs offs zone))
        corners (fit:poly-corners dirs offs))
  (if (null corners)
    (list base offs nil)
    (progn
      (setq bows nil i 0)
      (while (< i n)
        (setq wpts  (nth i wallpts)
              a     (nth i corners)
              b     (nth (rem (1+ i) n) corners)
              swing (fit:signed-dang (nth i base) (nth i dirs))
              ;; the drift the TOTAL swing represents, end to end, in
              ;; inches - not the residual the last pass measured,
              ;; which is near zero once the wall has already been
              ;; swung onto its points
              drift (* (abs (fit:tan swing)) (fit:dist a b)))
        (if (and (= n 8) (= 1 (rem i 2)))
          (setq swing 0.0))                 ; a derived cut wall
        (if (> (abs swing) 1.0e-9)
          (progn
            (setq flat (fit:flat-off wpts (nth i base) (nth i offs)))
            (if (not (and (>= drift fit:*oos-min*)
                          wpts
                          (<= (fit:wall-rms wpts a b 0.0)
                              (* (fit:flat-rms wpts (nth i base) flat)
                                 fit:*both-edge*))))
              (setq dirs (fit:setnth dirs i (nth i base))
                    offs (fit:setnth offs i flat)))))
        (setq bows (cons (if (and bowed (nth i coefs))
                           (fit:keep-bow wpts a b
                                         (fit:bow-cap
                                           (caddr (nth i coefs))
                                           (fit:dist a b)))
                           0.0)
                         bows)
              i    (1+ i)))
      (setq bows (reverse bows))
      (if (= n 8)
        (setq got2 (fit:grec-cuts dirs offs (fit:grec-face dirs offs))
              dirs (car got2)
              offs (cadr got2)))
      (if (fit:poly-valid dirs offs)
        (list dirs offs (if (fit:any-bow bows) bows nil))
        (list base offs nil)))))

;; ---- the arc-ended types (Roman / Oval) ------------------------------

;; Half-height of the spring points where the end arc leaves the end
;; line, clamped inside the side walls.
(defun fit:endcap-h (re cx r by ty / d)
  (setq d (- (* r r) (* (- re cx) (- re cx))))
  (if (<= d 0.0)
    0.0
    (min (sqrt d) (- (/ (- ty by) 2.0) 1.0e-6))))

;; endcap parameter access: PRM is an assoc list keyed by symbols
(defun fit:pget (prm key) (cdr (assoc key prm)))
(defun fit:pput (prm key val)
  (if (assoc key prm)
    (subst (cons key val) (assoc key prm) prm)
    (cons (cons key val) prm)))

;; Vertex run for one end cap: SIGN +1 = the +x end (walked bottom to
;; top), -1 = the -x end (walked top to bottom).  Stubs appear when the
;; arc springs meaningfully inside the corners.
(defun fit:cap-verts (re cx r sign by ty / cy h stub lo hi a1 a2 b out)
  (setq cy   (/ (+ by ty) 2.0)
        h    (fit:endcap-h re cx r by ty)
        stub (> (- (/ (- ty by) 2.0) h) 0.25)
        out  nil)
  (if (> sign 0)
    (progn
      (setq lo (list re (- cy h))
            hi (list re (+ cy h))
            a1 (angle (list cx cy) lo)
            a2 (angle (list cx cy) hi)
            b  (fit:tan (/ (fit:angnorm (- a2 a1)) 4.0)))
      (if stub (setq out (list (list (list re by) 0.0))))
      (setq out (append out (list (list lo b))))
      (if stub
        (setq out (append out (list (list hi 0.0)
                                    (list (list re ty) 0.0))))
        (setq out (append out (list (list hi 0.0))))))
    (progn
      (setq hi (list re (+ cy h))
            lo (list re (- cy h))
            a1 (angle (list cx cy) hi)
            a2 (angle (list cx cy) lo)
            b  (fit:tan (/ (fit:angnorm (- a2 a1)) 4.0)))
      (if stub (setq out (list (list (list re ty) 0.0))))
      (setq out (append out (list (list hi b))))
      (if stub
        (setq out (append out (list (list lo 0.0)
                                    (list (list re by) 0.0))))
        (setq out (append out (list (list lo 0.0)))))))
  out)

;; Outline vertex list of the fitted end-capped body, frame coords.
;; BOWS (nil = none) is (bottom top): the two side walls may bow like
;; any other straight wall; the cap ends are never touched.
(defun fit:endcap-verts (prm kind both bows / yb yt verts itop ibot m a b)
  (setq yb    (fit:pget prm 'By)
        yt    (fit:pget prm 'Ty)
        verts (fit:cap-verts (fit:pget prm 'Re) (fit:pget prm 'cx)
                             (fit:pget prm 'r) 1 yb yt)
        itop  (1- (length verts)))        ; the TOP wall leaves here
  (if both
    (setq verts (append verts
                        (fit:cap-verts (fit:pget prm 'Re2)
                                       (fit:pget prm 'cx2)
                                       (fit:pget prm 'r2) -1 yb yt)))
    (setq verts (append verts
                        (list (list (list (fit:pget prm 'Lx) yt) 0.0)
                              (list (list (fit:pget prm 'Lx) yb) 0.0)))))
  (setq ibot (1- (length verts)))         ; the BOTTOM wall leaves here
  (if bows
    (progn
      (setq m (length verts))
      (foreach a (list (cons 1 itop) (cons 0 ibot))
        (if (not (equal (nth (car a) bows) 0.0 1.0e-12))
          (setq b     (car (nth (rem (1+ (cdr a)) m) verts))
                verts (fit:setnth
                        verts (cdr a)
                        (list (car (nth (cdr a) verts))
                              (fit:bow-bulge
                                (nth (car a) bows)
                                (fit:dist (car (nth (cdr a) verts)) b)
                                (car (nth (cdr a) verts)) b))))))))
  verts)

;; (xl xr) - the x range the two side walls of a cap body run over.
(defun fit:cap-wall-span (prm both)
  (list (if both (fit:pget prm 'Re2) (fit:pget prm 'Lx))
        (fit:pget prm 'Re)))

;; The Roman/Oval side walls, refitted as shallow arcs.  Returns
;; (prm (bow-bottom bow-top)); the cap ends are left exactly as the
;; template fit left them.
(defun fit:fit-cap-bows (pts prm both / span lo hi yb yt bot top p k wpts
                                        a b got shift s bows)
  (setq span (fit:cap-wall-span prm both)
        lo   (min (car span) (cadr span))
        hi   (max (car span) (cadr span))
        yb   (fit:pget prm 'By)
        yt   (fit:pget prm 'Ty)
        bot  nil top nil)
  (foreach p pts
    (if (and (<= lo (car p)) (<= (car p) hi))
      (if (< (abs (- (cadr p) yb)) (abs (- (cadr p) yt)))
        (setq bot (cons p bot))
        (setq top (cons p top)))))
  (setq bows (list 0.0 0.0) k 0)
  (foreach wpts (list bot top)
    (setq a   (if (= k 0) (list lo yb) (list hi yt))
          b   (if (= k 0) (list hi yb) (list lo yt))
          got (fit:fit-wall-line wpts a b nil T))
    (if got
      (progn
        (setq shift (car got)
              s     (fit:bow-cap (caddr got) (fit:dist a b)))
        (if (= k 0)
          (setq yb  (- yb shift)
                prm (fit:pput prm 'By yb)
                a   (list (car a) yb)
                b   (list (car b) yb))
          (setq yt  (+ yt shift)
                prm (fit:pput prm 'Ty yt)
                a   (list (car a) yt)
                b   (list (car b) yt)))
        (setq bows (fit:setnth bows k (fit:keep-bow wpts a b s)))))
    (setq k (1+ k)))
  (list prm bows))

;; ICP for a rectangle body with a Roman or radius (Oval) end cap on
;; the +x end - and on the -x end too when BOTH.  Returns the fitted
;; parameter assoc list.
(defun fit:fit-endcap (pts kind both / bb x0 y0 x1 y1 w prm r0 yb yt cy
                                       xr xl bpts tpts lpts a1pts a2pts e1pts
                                       e2pts p darc1 darc2 dbot dtop dlft
                                       dend1 dend2 h1 h2 best bd cand cc
                                       ssum n d q)
  (setq bb (fit:bbox pts)
        x0 (car bb) y0 (cadr bb) x1 (caddr bb) y1 (cadddr bb)
        w  (- y1 y0)
        r0 (if (= kind "Oval") (/ w 2.0) (* 0.6 w))
        prm (list (cons 'By y0) (cons 'Ty y1) (cons 'Lx x0)
                  (cons 'r r0) (cons 'cx (- x1 r0))))
  (setq prm (fit:pput prm 'Re
              (if (= kind "Oval")
                (fit:pget prm 'cx)
                (+ (fit:pget prm 'cx)
                   (sqrt (max 0.0 (- (* r0 r0) (* 0.16 w w))))))))
  (if both
    (progn
      (setq prm (fit:pput prm 'r2 r0)
            prm (fit:pput prm 'cx2 (+ x0 r0)))
      (setq prm (fit:pput prm 'Re2
                  (if (= kind "Oval")
                    (fit:pget prm 'cx2)
                    (- (fit:pget prm 'cx2)
                       (sqrt (max 0.0 (- (* r0 r0) (* 0.16 w w))))))))))
  (repeat fit:*icp-iters*
    (setq yb (fit:pget prm 'By)
          yt (fit:pget prm 'Ty)
          cy (/ (+ yb yt) 2.0)
          xr (fit:pget prm 'Re)
          xl (if both (fit:pget prm 'Re2) (fit:pget prm 'Lx))
          h1 (fit:endcap-h (fit:pget prm 'Re) (fit:pget prm 'cx)
                           (fit:pget prm 'r) yb yt)
          h2 (if both
               (fit:endcap-h (fit:pget prm 'Re2) (fit:pget prm 'cx2)
                             (fit:pget prm 'r2) yb yt))
          bpts nil tpts nil lpts nil a1pts nil a2pts nil e1pts nil e2pts nil)
    (foreach p pts
      ;; distance to each feature; a point left of an arc's centre
      ;; falls back to its spring corners so side points never claim it
      (setq darc1 (if (< (car p) (fit:pget prm 'cx))
                    (min (fit:dist p (list (fit:pget prm 'Re) yb))
                         (fit:dist p (list (fit:pget prm 'Re) yt)))
                    (abs (- (fit:dist p (list (fit:pget prm 'cx) cy))
                            (fit:pget prm 'r))))
            darc2 (if both
                    (if (> (car p) (fit:pget prm 'cx2))
                      (min (fit:dist p (list (fit:pget prm 'Re2) yb))
                           (fit:dist p (list (fit:pget prm 'Re2) yt)))
                      (abs (- (fit:dist p (list (fit:pget prm 'cx2) cy))
                              (fit:pget prm 'r2)))))
            dbot  (if (and (<= xl (car p)) (<= (car p) xr))
                    (abs (- (cadr p) yb)) 1.0e9)
            dtop  (if (and (<= xl (car p)) (<= (car p) xr))
                    (abs (- (cadr p) yt)) 1.0e9)
            dlft  (if both 1.0e9 (abs (- (car p) (fit:pget prm 'Lx))))
            dend1 (if (> (abs (- (cadr p) cy)) h1)
                    (abs (- (car p) (fit:pget prm 'Re))) 1.0e9)
            dend2 (if (and both (> (abs (- (cadr p) cy)) h2))
                    (abs (- (car p) (fit:pget prm 'Re2))) 1.0e9))
      (setq cand (list (list dbot 'K-BOT) (list dtop 'K-TOP)
                       (list darc1 'K-ARC1)))
      (if both
        (setq cand (cons (list darc2 'K-ARC2) cand))
        (setq cand (cons (list dlft 'K-LFT) cand)))
      (if (= kind "ROman")
        (progn
          (setq cand (cons (list dend1 'K-END1) cand))
          (if both (setq cand (cons (list dend2 'K-END2) cand)))))
      (setq best nil bd nil)
      (foreach q cand
        (if (or (null bd) (< (car q) bd))
          (setq best (cadr q) bd (car q))))
      (cond
        ((eq best 'K-BOT)  (setq bpts (cons p bpts)))
        ((eq best 'K-TOP)  (setq tpts (cons p tpts)))
        ((eq best 'K-LFT)  (setq lpts (cons p lpts)))
        ((eq best 'K-ARC1) (setq a1pts (cons p a1pts)))
        ((eq best 'K-ARC2) (setq a2pts (cons p a2pts)))
        ((eq best 'K-END1) (setq e1pts (cons p e1pts)))
        ((eq best 'K-END2) (setq e2pts (cons p e2pts)))))
    ;; wall updates
    (if bpts
      (progn
        (setq ssum 0.0)
        (foreach p bpts (setq ssum (+ ssum (cadr p))))
        (setq prm (fit:pput prm 'By (/ ssum (length bpts))))))
    (if tpts
      (progn
        (setq ssum 0.0)
        (foreach p tpts (setq ssum (+ ssum (cadr p))))
        (setq prm (fit:pput prm 'Ty (/ ssum (length tpts))))))
    (if (and lpts (not both))
      (progn
        (setq ssum 0.0)
        (foreach p lpts (setq ssum (+ ssum (car p))))
        (setq prm (fit:pput prm 'Lx (/ ssum (length lpts))))))
    (setq yb (fit:pget prm 'By)
          yt (fit:pget prm 'Ty)
          cy (/ (+ yb yt) 2.0)
          w  (- yt yb))
    ;; the +x cap
    (if a1pts
      (progn
        (if (/= kind "Oval")
          (progn
            (setq ssum 0.0 cc (list (fit:pget prm 'cx) cy))
            (foreach p a1pts (setq ssum (+ ssum (fit:dist p cc))))
            (setq prm (fit:pput prm 'r (/ ssum (length a1pts))))))
        (setq ssum 0.0 n 0)
        (foreach p a1pts
          (setq d (- (* (fit:pget prm 'r) (fit:pget prm 'r))
                     (* (- (cadr p) cy) (- (cadr p) cy))))
          (if (> d 0.0)
            (setq ssum (+ ssum (- (car p) (sqrt d)))
                  n    (1+ n))))
        (if (> n 0) (setq prm (fit:pput prm 'cx (/ ssum n))))))
    (if (= kind "Oval")
      (setq prm (fit:pput prm 'r (/ w 2.0))
            prm (fit:pput prm 'Re (fit:pget prm 'cx)))
      (if e1pts
        (progn
          (setq ssum 0.0)
          (foreach p e1pts (setq ssum (+ ssum (car p))))
          (setq prm (fit:pput prm 'Re (/ ssum (length e1pts)))))))
    (setq prm (fit:pput prm 'Re
                (min (fit:pget prm 'Re)
                     (- (+ (fit:pget prm 'cx) (fit:pget prm 'r)) 0.5))))
    ;; the -x cap
    (if both
      (progn
        (if a2pts
          (progn
            (if (/= kind "Oval")
              (progn
                (setq ssum 0.0 cc (list (fit:pget prm 'cx2) cy))
                (foreach p a2pts (setq ssum (+ ssum (fit:dist p cc))))
                (setq prm (fit:pput prm 'r2 (/ ssum (length a2pts))))))
            (setq ssum 0.0 n 0)
            (foreach p a2pts
              (setq d (- (* (fit:pget prm 'r2) (fit:pget prm 'r2))
                         (* (- (cadr p) cy) (- (cadr p) cy))))
              (if (> d 0.0)
                (setq ssum (+ ssum (+ (car p) (sqrt d)))
                      n    (1+ n))))
            (if (> n 0) (setq prm (fit:pput prm 'cx2 (/ ssum n))))))
        (if (= kind "Oval")
          (setq prm (fit:pput prm 'r2 (/ w 2.0))
                prm (fit:pput prm 'Re2 (fit:pget prm 'cx2)))
          (if e2pts
            (progn
              (setq ssum 0.0)
              (foreach p e2pts (setq ssum (+ ssum (car p))))
              (setq prm (fit:pput prm 'Re2 (/ ssum (length e2pts)))))))
        (setq prm (fit:pput prm 'Re2
                    (max (fit:pget prm 'Re2)
                         (+ (- (fit:pget prm 'cx2) (fit:pget prm 'r2))
                            0.5)))))))
  prm)

;; ---- the Round pool --------------------------------------------------

(defun fit:fit-round (pts / cx cy r ssum sx sy p d n)
  (setq n  (length pts) sx 0.0 sy 0.0)
  (foreach p pts (setq sx (+ sx (car p)) sy (+ sy (cadr p))))
  (setq cx (/ sx n) cy (/ sy n))
  (repeat fit:*rad-iters*
    (setq ssum 0.0)
    (foreach p pts (setq ssum (+ ssum (fit:dist p (list cx cy)))))
    (setq r (/ ssum n) sx 0.0 sy 0.0)
    (foreach p pts
      (setq d (fit:dist p (list cx cy)))
      (if (< d 1.0e-9)
        (setq sx (+ sx (car p)) sy (+ sy (cadr p)))
        (setq sx (+ sx (- (car p) (* r (/ (- (car p) cx) d))))
              sy (+ sy (- (cadr p) (* r (/ (- (cadr p) cy) d)))))))
    (setq cx (/ sx n) cy (/ sy n)))
  (list (cons 'cx cx) (cons 'cy cy) (cons 'r r)))

;; the circle as two bulge-1 semicircles, as ABHD draws a CIRCLE
(defun fit:round-verts (prm / c r)
  (setq c (list (fit:pget prm 'cx) (fit:pget prm 'cy))
        r (fit:pget prm 'r))
  (list (list (list (+ (car c) r) (cadr c)) 1.0)
        (list (list (- (car c) r) (cadr c)) 1.0)))

;; ---- one result to rule them all -------------------------------------
;; A fit result is an assoc list keyed by symbols: kind (poly / cap /
;; round), type, angle, mirror, and the kind's own parameters.  The
;; outline always lives under 'verts as a closed (pt bulge) list in
;; FRAME coordinates.

(defun fit:rget (res key) (cdr (assoc key res)))
(defun fit:rput (res key val)
  (if (assoc key res)
    (subst (cons key val) (assoc key res) res)
    (cons (cons key val) res)))

(defun fit:res-fsegs (res) (fit:verts-to-segs (fit:rget res 'verts)))

;; the outline carried into world coordinates, still (pt bulge)
(defun fit:res-world-verts (res / a m out v)
  (setq a (fit:rget res 'angle)
        m (fit:rget res 'mirror)
        out nil)
  (foreach v (fit:rget res 'verts)
    (setq out (cons (list (fit:from-frame (car v) a m)
                          (if m (- (cadr v)) (cadr v)))
                    out)))
  (reverse out))

(defun fit:poly-result (ptype fpts dirs offs0 treat / fitres offs size
                                                      vsize which verts got2)
  (if (= 8 (length dirs))
    (progn
      ;; the cut corners are walls of their own here (Grecian, and a
      ;; Rectangle whose corners are Cut) - one shared face for all 4.
      ;; TREAT is the treatment of the eight VERTICES: a nominal
      ;; grecian is sharp, an as-built may well be rounded, so Radius
      ;; (or Cut) measures a shared easing from the points.
      (setq fitres (fit:fit-polytype fpts dirs offs0 "Square")
            offs   (car fitres)
            size   (fit:grec-face dirs offs)
            got2   (fit:grec-cuts dirs offs size)
            dirs   (car got2)
            offs   (cadr got2)
            vsize  nil)
      (if (member treat '("Radius" "Cut"))
        (setq fitres (fit:fit-vertex-feature fpts dirs offs treat)
              vsize  (car fitres)
              offs   (cadr fitres)
              size   (caddr fitres)))
      (setq which (if vsize T nil)
            verts (fit:build-polygon dirs offs treat vsize which nil))
      (list (cons 'kind 'poly) (cons 'type ptype) (cons 'dirs dirs)
            (cons 'offs offs) (cons 'treat treat) (cons 'size size)
            (cons 'vsize vsize) (cons 'which which) (cons 'verts verts)
            (cons 'bows nil) (cons 'valid (fit:poly-valid dirs offs))))
    (progn
      (setq fitres (fit:fit-polytype fpts dirs offs0 treat)
            offs   (car fitres)
            size   (cadr fitres)
            which  (if (member treat '("Radius" "Cut")) T nil)
            verts  (fit:build-polygon dirs offs treat size which nil))
      (list (cons 'kind 'poly) (cons 'type ptype) (cons 'dirs dirs)
            (cons 'offs offs) (cons 'treat treat) (cons 'size size)
            (cons 'which which) (cons 'verts verts) (cons 'bows nil)
            (cons 'valid (fit:poly-valid dirs offs))))))

(defun fit:cap-result (ptype fpts both / prm)
  (setq prm (fit:fit-endcap fpts ptype both))
  (list (cons 'kind 'cap) (cons 'type ptype) (cons 'prm prm)
        (cons 'both both) (cons 'valid T) (cons 'bows nil)
        (cons 'verts (fit:endcap-verts prm ptype both nil))))

(defun fit:fit-config (ptype fpts treat both)
  (cond
    ((= ptype "Rectangle")
     (if (= treat "Cut")
       (fit:poly-result ptype fpts fit:*grec-dirs* (fit:grec-init fpts)
                        "Square")
       (fit:poly-result ptype fpts fit:*rect-dirs* (fit:rect-init fpts)
                        treat)))
    ((= ptype "Grecian")
     (fit:poly-result ptype fpts fit:*grec-dirs* (fit:grec-init fpts)
                      treat))
    ((= ptype "L")
     (fit:poly-result ptype fpts fit:*l-dirs* (fit:l-init fpts nil)
                      treat))
    ((= ptype "LAzyl")
     (fit:poly-result ptype fpts fit:*lazy-dirs* (fit:l-init fpts T)
                      treat))
    (T (fit:cap-result ptype fpts both))))

;; (extra-rotation mirror both-ends) candidates per type
(defun fit:configs-for (ptype / q e out k m)
  (setq q (/ pi 2.0))
  (cond
    ((member ptype '("Rectangle" "Grecian")) (list (list 0.0 nil nil)))
    ((member ptype '("ROman" "Oval"))
     (setq out nil k 0)
     (repeat 4
       (setq out (cons (list (* k q) nil nil) out) k (1+ k)))
     (reverse (cons (list q nil T) (cons (list 0.0 nil T) out))))
    ((= ptype "L")
     (setq out nil k 0)
     (repeat 4
       (foreach m '(nil T)
         (setq out (cons (list (* k q) m nil) out)))
       (setq k (1+ k)))
     (reverse out))
    ((= ptype "LAzyl")
     (setq e (/ pi 4.0) out nil k 0)
     (repeat 8
       (foreach m '(nil T)
         (setq out (cons (list (* k e) m nil) out)))
       (setq k (1+ k)))
     (reverse out))
    (T (list (list 0.0 nil nil)))))

;; Order, frame, and try every placement the type allows; the
;; lowest-RMS one wins.  Returns the winning result with its frame
;; recorded; the outline stays in frame coordinates.
(defun fit:fit-type (pts ptype treat / dpts prm tour a0 best cfg a fpts
                                       res dev worst rms edge)
  (setq dpts (fit:dedupe pts fit:*exact-eps*))
  (if (= ptype "ROUnd")
    (progn
      (setq prm (fit:fit-round dpts))
      (list (cons 'kind 'round) (cons 'type ptype) (cons 'prm prm)
            (cons 'angle 0.0) (cons 'mirror nil) (cons 'valid T)
            (cons 'verts (fit:round-verts prm))))
    (progn
      (setq tour (fit:order-points dpts)
            a0   (fit:frame-angle tour (if (= ptype "LAzyl") 8 4))
            best nil)
      (foreach cfg (fit:configs-for ptype)
        (setq a    (+ a0 (car cfg))
              fpts (fit:to-frame dpts a (cadr cfg))
              res  (fit:fit-config ptype fpts treat (caddr cfg)))
        (if (fit:rget res 'valid)
          (progn
            (setq dev   (fit:outline-dev fpts (fit:res-fsegs res))
                  worst (car dev)
                  rms   (cadr dev)
                  ;; a both-ends cap has more freedom than a single-
                  ;; ended one, so it only wins with a clear margin - a
                  ;; big flat arc can always shave a little rms off a
                  ;; genuinely square end
                  edge  (if (and (caddr cfg) best
                                 (not (fit:rget best 'both)))
                          fit:*both-edge*
                          1.0))
            (if (or (null best) (< rms (* (fit:rget best 'rms) edge)))
              (setq res  (fit:rput res 'angle a)
                    res  (fit:rput res 'mirror (cadr cfg))
                    res  (fit:rput res 'worst worst)
                    res  (fit:rput res 'rms rms)
                    best res)))))
      ;; a rectangle or grecian fits the same either way around -
      ;; report the long dimension as the length, deterministically
      (if (and best
               (member ptype '("Rectangle" "Grecian"))
               (> (fit:get-dim best 'WID) (fit:get-dim best 'LEN)))
        (progn
          (setq a    (+ (fit:rget best 'angle) (/ pi 2.0))
                fpts (fit:to-frame dpts a nil)
                res  (fit:fit-config ptype fpts treat nil)
                dev  (fit:outline-dev fpts (fit:res-fsegs res))
                res  (fit:rput res 'angle a)
                res  (fit:rput res 'mirror nil)
                res  (fit:rput res 'worst (car dev))
                res  (fit:rput res 'rms (cadr dev))
                best res)))
      best)))

;; ---- nice dimensions -------------------------------------------------
;; After the free fit, each headline dimension is snapped to the first
;; friendly increment - whole feet, half feet, inches, half inches -
;; that the points can live with: the snapped outline must stay within
;; the run tolerance (or, when an outlier already sits beyond it, move
;; nothing more than fit:*snap-eps*).  The points outrank pretty
;; numbers.

;; the snapping order per type: overall dims first, features after
(defun fit:dim-keys (res / t2)
  (setq t2 (fit:rget res 'type))
  (cond
    ((= t2 "Rectangle") '(LEN WID SIZE))
    ((= t2 "Grecian")
     (if (fit:rget res 'vsize) '(LEN WID CUT VSIZE) '(LEN WID CUT)))
    ((= t2 "L")         '(LEN WID WINGX WINGY SIZE))
    ((= t2 "LAzyl")     '(SIZE))
    ((= t2 "ROman")     '(WID BLEN RAD))
    ((= t2 "Oval")      '(WID BLEN))
    ((= t2 "ROUnd")     '(RAD))
    (T nil)))

(defun fit:get-dim (res key / t2 offs prm)
  (setq t2 (fit:rget res 'type))
  (cond
    ((eq (fit:rget res 'kind) 'poly)
     (setq offs (fit:rget res 'offs))
     (if (= 8 (length offs))
       (cond
         ((eq key 'LEN) (+ (nth 2 offs) (nth 6 offs)))
         ((eq key 'WID) (+ (nth 4 offs) (nth 0 offs)))
         ((member key '(CUT SIZE)) (fit:rget res 'size))
         ((eq key 'VSIZE) (fit:rget res 'vsize)))
       (cond
         ((eq key 'LEN)
          (+ (nth 1 offs)
             (nth (if (member t2 '("L" "LAzyl")) 5 3) offs)))
         ((eq key 'WID) (+ (nth 2 offs) (nth 0 offs)))
         ((eq key 'WINGX) (+ (nth 1 offs) (nth 3 offs)))
         ((eq key 'WINGY) (- (nth 2 offs) (nth 4 offs)))
         ((eq key 'SIZE) (fit:rget res 'size)))))
    ((eq (fit:rget res 'kind) 'cap)
     (setq prm (fit:rget res 'prm))
     (cond
       ((eq key 'WID) (- (fit:pget prm 'Ty) (fit:pget prm 'By)))
       ((eq key 'BLEN) (- (fit:pget prm 'Re)
                          (if (fit:rget res 'both)
                            (fit:pget prm 'Re2)
                            (fit:pget prm 'Lx))))
       ((eq key 'RAD) (fit:pget prm 'r))))
    ((eq key 'RAD) (fit:pget (fit:rget res 'prm) 'r))))

;; A copy of RES with the dimension forced to V and its outline
;; rebuilt.  Symmetric dims move both walls, keeping the centre.
(defun fit:set-dim (res key v / t2 offs prm d j w got2)
  (setq t2 (fit:rget res 'type))
  (cond
    ((eq (fit:rget res 'kind) 'poly)
     (setq offs (fit:rget res 'offs))
     (if (= 8 (length offs))
       (progn
         (cond
           ((eq key 'LEN)
            (setq d (/ (- v (+ (nth 2 offs) (nth 6 offs))) 2.0)
                  offs (fit:setnth offs 2 (+ (nth 2 offs) d))
                  offs (fit:setnth offs 6 (+ (nth 6 offs) d))))
           ((eq key 'WID)
            (setq d (/ (- v (+ (nth 4 offs) (nth 0 offs))) 2.0)
                  offs (fit:setnth offs 4 (+ (nth 4 offs) d))
                  offs (fit:setnth offs 0 (+ (nth 0 offs) d))))
           ((member key '(CUT SIZE))
            (setq res (fit:rput res 'size v)))
           ((eq key 'VSIZE)
            (setq res (fit:rput res 'vsize v))))
         (setq got2 (fit:grec-cuts (fit:rget res 'dirs) offs
                                   (fit:rget res 'size))
               res  (fit:rput res 'dirs (car got2))
               offs (cadr got2)))
       (cond
         ((eq key 'LEN)
          (setq j (if (member t2 '("L" "LAzyl")) 5 3)
                d (/ (- v (+ (nth 1 offs) (nth j offs))) 2.0)
                offs (fit:setnth offs 1 (+ (nth 1 offs) d))
                offs (fit:setnth offs j (+ (nth j offs) d)))
          (if (= t2 "L")                ; the wing dims ride on Rx
            (setq offs (fit:setnth offs 3 (- (nth 3 offs) d)))))
         ((eq key 'WID)
          (setq d (/ (- v (+ (nth 2 offs) (nth 0 offs))) 2.0)
                offs (fit:setnth offs 2 (+ (nth 2 offs) d))
                offs (fit:setnth offs 0 (+ (nth 0 offs) d)))
          (if (= t2 "L")
            (setq offs (fit:setnth offs 4 (+ (nth 4 offs) d)))))
         ((eq key 'WINGX)
          (setq offs (fit:setnth offs 3 (- v (nth 1 offs)))))
         ((eq key 'WINGY)
          (setq offs (fit:setnth offs 4 (- (nth 2 offs) v))))
         ((eq key 'SIZE)
          (setq res (fit:rput res 'size v)))))
     (setq res (fit:rput res 'offs offs))
     (fit:rput res 'verts
               (fit:build-polygon (fit:rget res 'dirs) offs
                                  (fit:rget res 'treat)
                                  (if (= 8 (length offs))
                                    (fit:rget res 'vsize)
                                    (fit:rget res 'size))
                                  (fit:rget res 'which)
                                  (fit:rget res 'bows))))
    ((eq (fit:rget res 'kind) 'cap)
     (setq prm (fit:rget res 'prm))
     (cond
       ((eq key 'WID)
        (setq w   (- (fit:pget prm 'Ty) (fit:pget prm 'By))
              d   (/ (- v w) 2.0)
              prm (fit:pput prm 'Ty (+ (fit:pget prm 'Ty) d))
              prm (fit:pput prm 'By (- (fit:pget prm 'By) d)))
        (if (= t2 "Oval")
          (progn
            (setq prm (fit:pput prm 'r (/ v 2.0)))
            (if (fit:rget res 'both)
              (setq prm (fit:pput prm 'r2 (/ v 2.0)))))))
       ((eq key 'BLEN)
        (if (fit:rget res 'both)
          (setq d   (/ (- v (- (fit:pget prm 'Re) (fit:pget prm 'Re2)))
                       2.0)
                prm (fit:pput prm 'Re (+ (fit:pget prm 'Re) d))
                prm (fit:pput prm 'cx (+ (fit:pget prm 'cx) d))
                prm (fit:pput prm 'Re2 (- (fit:pget prm 'Re2) d))
                prm (fit:pput prm 'cx2 (- (fit:pget prm 'cx2) d)))
          (setq prm (fit:pput prm 'Lx (- (fit:pget prm 'Re) v)))))
       ((eq key 'RAD)
        (setq prm (fit:pput prm 'r v))
        (if (fit:rget res 'both) (setq prm (fit:pput prm 'r2 v)))))
     (setq res (fit:rput res 'prm prm))
     (fit:rput res 'verts
               (fit:endcap-verts prm t2 (fit:rget res 'both)
                                 (fit:rget res 'bows))))
    (T
     (setq prm (fit:pput (fit:rget res 'prm) 'r v)
           res (fit:rput res 'prm prm))
     (fit:rput res 'verts (fit:round-verts prm)))))

;; Snap each headline dimension to the first friendly increment the
;; points allow; the free value stays when none do.  Whole dimensions
;; may spend the run tolerance, but a MEASURED feature - a corner
;; radius, a cut face, a roman end radius - may only grow the worst
;; deviation by fit:*feat-snap*: an 8-inch as-built corner must not
;; become a foot just because the tolerance would absorb it.  On each
;; tier the two neighbouring multiples are both tried and the one
;; that fits the points better wins.
(defun fit:snap-result (res fpts tol allow / key v feature spend before
                                             after inc lo v2 trial w done
                                             bw bt)
  (foreach key (fit:dim-keys res)
    (setq v (fit:get-dim res key))
    (if (and v (> v 0.0))
      (progn
        (setq feature (member key '(SIZE VSIZE CUT RAD))
              spend   (if feature 0 allow)
              before  (fit:outline-dists fpts (fit:res-fsegs res))
              done    nil)
        (foreach inc fit:*nice-dims*
          (if (not done)
            (progn
              (setq lo (* inc (fix (/ v inc)))
                    bw nil bt nil)
              (foreach v2 (list lo (+ lo inc))
                (if (> v2 0.0)
                  (progn
                    (setq trial (fit:set-dim res key v2)
                          after (fit:outline-dists
                                  fpts (fit:res-fsegs trial)))
                    (if (fit:snap-ok before after tol allow feature)
                      (progn
                        (setq w (fit:held-worst after spend))
                        (if (or (null bw) (< w bw))
                          (setq bw w bt trial)))))))
              (if bt (setq res bt done T))))))))
  res)

;; How far from a corner a point belongs to the corner feature rather
;; than to a wall.
(defun fit:corner-zone-of (res)
  (cond
    ((fit:rget res 'vsize)
     (+ (* 1.2 (fit:rget res 'vsize) (fit:tan (/ pi 8.0)))
        fit:*zone-pad*))
    ;; on an eight-wall template the cut corners ARE walls, and "size"
    ;; is their face length - not a corner feature at all
    ((= 8 (length (fit:rget res 'offs))) 0.0)
    ((fit:rget res 'size) (+ (* 1.2 (fit:rget res 'size))
                             fit:*zone-pad*))
    ((member (fit:rget res 'treat) '("Radius" "Cut")) fit:*corner-zone*)
    (T 0.0)))

;; Refine the placement that already WON: let the walls answer to the
;; points.  A refinement is never a competitor in the search - the
;; extra freedom would let a wrong rotation bend its way to a good
;; score - so it runs once, on the winner.
(defun fit:apply-refinement (res fpts oos bowed / got dirs offs bows
                                                 swung prm a b)
  (cond
    ((eq (fit:rget res 'kind) 'poly)
     (setq got  (fit:refine-walls fpts (fit:rget res 'dirs)
                                  (fit:rget res 'offs)
                                  (fit:corner-zone-of res) oos bowed)
           dirs (car got)
           offs (cadr got)
           bows (caddr got)
           swung nil)
     (setq a (fit:rget res 'dirs) b dirs)
     (while a
       (if (> (abs (fit:signed-dang (car a) (car b))) 1.0e-9)
         (setq swung T))
       (setq a (cdr a) b (cdr b)))
     (if (and (null swung) (null bows))
       res
       (progn
         (setq res (fit:rput res 'dirs dirs)
               res (fit:rput res 'offs offs)
               res (fit:rput res 'bows bows)
               res (fit:rput res 'swung swung))
         (if (= 8 (length offs))
           (setq res (fit:rput res 'size (fit:grec-face dirs offs))))
         (fit:rput res 'verts
                   (fit:build-polygon dirs offs (fit:rget res 'treat)
                                      (if (= 8 (length offs))
                                        (fit:rget res 'vsize)
                                        (fit:rget res 'size))
                                      (fit:rget res 'which) bows)))))
    ((and (eq (fit:rget res 'kind) 'cap) bowed)
     ;; an arc-ended body's SIDE walls can bow; swinging them would
     ;; take the end caps with them, so out-of-square stops here
     (setq got  (fit:fit-cap-bows fpts (fit:rget res 'prm)
                                  (fit:rget res 'both))
           prm  (car got)
           bows (cadr got))
     (if (null (fit:any-bow bows))
       res
       (progn
         (setq res (fit:rput res 'prm prm)
               res (fit:rput res 'bows bows))
         (fit:rput res 'verts
                   (fit:endcap-verts prm (fit:rget res 'type)
                                     (fit:rget res 'both) bows)))))
    (T res)))                             ; a round pool has no walls

;; T when any wall of BOWS came out bowed.
(defun fit:any-bow (bows / found b)
  (foreach b bows
    (if (and b (not (equal b 0.0 1.0e-12))) (setq found T)))
  found)

;; The whole engine: configuration search, the bow refinement when the
;; walls may be bowed, then nice-dim snapping against the share of the
;; points the user allows beyond the distance, then the final figures.  The outline stays in frame
;; coordinates under 'verts; fit:res-world-verts carries it out.
(defun fit:fit-and-snap (pts ptype treat tol pct oos bowed / dpts allow
                                                            res fpts dev)
  (setq dpts  (fit:dedupe pts fit:*exact-eps*)
        allow (fit:ceil (* pct (length dpts)))
        res   (fit:fit-type dpts ptype treat))
  (if (eq (fit:rget res 'kind) 'round)
    (setq fpts dpts)
    (setq fpts (fit:to-frame dpts (fit:rget res 'angle)
                             (fit:rget res 'mirror))))
  (if (or oos bowed)
    (setq res (fit:apply-refinement res fpts oos bowed)))
  (setq res (fit:snap-result res fpts tol allow)
        dev (fit:outline-dev fpts (fit:res-fsegs res))
        res (fit:rput res 'worst (car dev))
        res (fit:rput res 'rms (cadr dev))
        res (fit:rput res 'allow allow))
  res)

;; ---- entity creation and "this one is mine" stamping -----------------
;; FITABHD writes onto layers the drawing may already use - FGStep in
;; particular - so everything it creates carries a small piece of
;; extended data naming this command, and only stamped objects are
;; ever erased again.

(defun fit:tag-mine (en / ed)
  (if en
    (progn
      (regapp "FITABHD")
      (setq ed (entget en))
      (entmod (append ed (list (list -3 (list "FITABHD"
                                              (cons 1000 "FITABHD"))))))))
  en)

;; Erase only FITABHD's own objects on a layer.  Returns how many went.
(defun fit:purge-mine (name / ss i n en)
  (setq n 0)
  (if (tblsearch "LAYER" name)
    (progn
      (setq ss (ssget "_X" (list (cons 8 name))))
      (if ss
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq en (ssname ss i))
            (if (assoc -3 (entget en '("FITABHD")))
              (progn (entdel en) (setq n (1+ n))))
            (setq i (1+ i)))))))
  n)

;; verts: list of (pt bulge) in order, closed.  COL is an AutoCAD
;; colour index, or nil for BYLAYER.
(defun fit:make-pline (verts layer col / dxf v)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                  (cons 8 layer)))
  (if col (setq dxf (append dxf (list (cons 62 col)))))
  (setq dxf (append dxf (list '(100 . "AcDbPolyline")
                              (cons 90 (length verts)) '(70 . 1))))
  (foreach v verts
    (setq dxf (append dxf (list (cons 10 (car v)) (cons 42 (cadr v))))))
  (entmakex dxf))

;; The kept fit joins the POOL layer in ByLayer colour.
(defun fit:set-bylayer (en / ed)
  (fit:ensure-layer fit:*pool-layer* 4)
  (setq ed (entget en)
        ed (subst (cons 8 fit:*pool-layer*) (assoc 8 ed) ed))
  (if (assoc 62 ed) (setq ed (subst '(62 . 256) (assoc 62 ed) ed)))
  (entmod ed))

;; A LINE on the pool layer with linetype LTYP (nil = ByLayer).
(defun fit:make-line (p1 p2 ltyp / dxf)
  (setq dxf (list '(0 . "LINE") '(100 . "AcDbEntity")
                  (cons 8 fit:*pool-layer*)))
  (if ltyp (setq dxf (append dxf (list (cons 6 ltyp)))))
  (entmakex (append dxf
                    (list '(100 . "AcDbLine")
                          (cons 10 (list (car p1) (cadr p1) 0.0))
                          (cons 11 (list (car p2) (cadr p2) 0.0))))))

;; A CIRCLE on LAYER (the Round hopper ring and the miss rings).
(defun fit:make-circle (c r layer)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 layer) '(100 . "AcDbCircle")
                  (cons 10 (list (car c) (cadr c) 0.0))
                  (cons 40 r))))

;; Make sure the DASHED2 linetype (the half-size dashes marking the
;; underwater break stubs) exists - pure entmake, no command calls.
(defun fit:ensure-dashed2 ()
  (if (not (tblsearch "LTYPE" "DASHED2"))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   '(2 . "DASHED2") '(70 . 0)
                   '(3 . "Dashed (.5x) _ _ _ _ _")
                   '(72 . 65) '(73 . 2) '(40 . 9.0)
                   '(49 . 6.0) '(74 . 0)
                   '(49 . -3.0) '(74 . 0)))))

;; An aligned dimension measuring PA to PB in the current style, its
;; dimension line through PDL - or right on the measured stretch when
;; PDL is nil.  nil comes back when the drawing cannot take one.
(defun fit:make-dim (pa pb pdl / m)
  (setq m (if pdl pdl (fit:mid pa pb)))
  (entmakex (list '(0 . "DIMENSION") '(100 . "AcDbEntity")
                  (cons 8 fit:*pool-layer*)
                  '(100 . "AcDbDimension")
                  (cons 3 (getvar "DIMSTYLE"))
                  (cons 10 (list (car m) (cadr m) 0.0))
                  '(70 . 33)                     ; aligned + block flag
                  '(1 . "")                      ; text = the measurement
                  '(100 . "AcDbAlignedDimension")
                  (cons 13 (list (car pa) (cadr pa) 0.0))
                  (cons 14 (list (car pb) (cadr pb) 0.0)))))

;; ---- reading the selection -------------------------------------------
;; Same classifier as ABHD's: ab_pt blocks are points on any layer,
;; POINT entities and other blocks count on the POINTS layer.  The
;; run-scoped fit-pts / fit-npt / fit-ptnames are bound by the command.

(defun fit:add-point (p nm)
  (setq fit-npt     (1+ fit-npt)
        fit-pts     (cons p fit-pts)
        fit-ptnames (cons (cons p (if (and nm (/= nm "")) nm
                                    (itoa fit-npt)))
                          fit-ptnames)))

;; What to call the surveyed point at Q.
(defun fit:pt-name (q / nm p)
  (setq nm nil)
  (foreach p fit-ptnames
    (if (and (null nm) (< (fit:dist (car p) q) fit:*exact-eps*))
      (setq nm (cdr p))))
  (if nm nm "?"))

;; Sort the selection into survey points; anything else is counted and
;; ignored - the TYPE is the guide here, not drawn geometry.
(defun fit:gather (ss / i en ed lay typ nskip)
  (setq i 0 nskip 0)
  (while (< i (sslength ss))
    (setq en  (ssname ss i)
          ed  (entget en)
          lay (strcase (cdr (assoc 8 ed)))
          typ (cdr (assoc 0 ed))
          i   (1+ i))
    (cond
      ((and (= typ "INSERT")
            (= (strcase (cdr (assoc 2 ed))) (strcase fit:*point-block*)))
       (fit:add-point (fit:2d (cdr (assoc 10 ed)))
                      (fit:block-number en fit:*pt-tag*)))
      ((and (= lay (strcase fit:*point-layer*)) (= typ "POINT"))
       (fit:add-point (fit:2d (cdr (assoc 10 ed))) nil))
      ((and (= typ "INSERT") (= lay (strcase fit:*point-layer*)))
       (fit:add-point (fit:2d (cdr (assoc 10 ed))
                      )
                      (fit:block-number en fit:*pt-tag*)))
      (T (setq nskip (1+ nskip)))))
  (if (> nskip 0)
    (princ (strcat "\nFITABHD: " (itoa nskip)
                   " selected object(s) that are not survey points"
                   " were ignored - the pool TYPE is the guide here,"
                   " not drawn geometry.")))
  (length fit-pts))

;; ---- the report ------------------------------------------------------

;; a length in feet-and-inches, the way the sheets read
(defun fit:ftin (v) (rtos v 4 4))

;; The fitted dimensions, one line per figure, per type.
(defun fit:dims-lines (res / t2 out prm w co n i names size)
  (setq t2 (fit:rget res 'type) out nil)
  (cond
    ((eq (fit:rget res 'kind) 'poly)
     (if (member t2 '("L" "LAzyl"))
       (progn
         (setq co    (fit:poly-corners (fit:rget res 'dirs)
                                       (fit:rget res 'offs))
               n     (length co)
               names '("A-B" "B-C" "C-D" "D-E" "E-F" "F-A")
               i     0)
         (while (< i n)
           (setq out (cons (cons (strcat "Side " (nth i names))
                                 (fit:ftin (fit:dist
                                             (nth i co)
                                             (nth (rem (1+ i) n) co))))
                           out)
                 i   (1+ i))))
       (setq out (list (cons "Width" (fit:ftin (fit:get-dim res 'WID)))
                       (cons "Length" (fit:ftin (fit:get-dim res 'LEN))))))
     (setq size (fit:rget res 'size))
     (if (fit:rget res 'vsize)
       (setq out (cons (cons (if (= (fit:rget res 'treat) "Cut")
                               "Corner easing (cut)"
                               "Corner easing radius")
                             (fit:ftin (fit:rget res 'vsize)))
                       out)))
     (cond
       ((and (= 8 (length (fit:rget res 'offs))) size (> size 0.01))
        (if (and (member (fit:rget res 'treat) '("Radius" "Cut"))
                 (null (fit:rget res 'vsize)))
          (setq out (cons (cons "Corner easing"
                                "none measurable - drawn sharp")
                          out)))
        (setq out (cons (cons "Corner cut face" (fit:ftin size)) out)))
       ((and size (= (fit:rget res 'treat) "Radius"))
        (setq out (cons (cons "Corner radius" (fit:ftin size)) out)))
       ((and size (= (fit:rget res 'treat) "Cut"))
        (setq out (cons (cons "Corner cut face" (fit:ftin size)) out)))
       ((= (fit:rget res 'treat) "NotGiven")
        (setq out (cons (cons "Corners" "Not Given - drawn square")
                        out)))))
    ((eq (fit:rget res 'kind) 'cap)
     (setq prm (fit:rget res 'prm)
           w   (fit:get-dim res 'WID))
     (setq out (list (cons (if (= t2 "ROman") "Roman end(s)"
                             "Radius end(s)")
                           (if (fit:rget res 'both) "both ends"
                             "one end"))
                     (cons "End radius" (fit:ftin (fit:pget prm 'r)))
                     (cons "Straight length"
                           (fit:ftin (fit:get-dim res 'BLEN)))
                     (cons "Width" (fit:ftin w))))
     (if (= t2 "ROman")
       (setq out (cons (cons "Roman stub (S1)"
                             (fit:ftin (- (/ w 2.0)
                                          (fit:endcap-h
                                            (fit:pget prm 'Re)
                                            (fit:pget prm 'cx)
                                            (fit:pget prm 'r)
                                            (fit:pget prm 'By)
                                            (fit:pget prm 'Ty)))))
                       (cons (cons "Roman bulge (S)"
                                   (fit:ftin (- (+ (fit:pget prm 'cx)
                                                   (fit:pget prm 'r))
                                                (fit:pget prm 'Re))))
                             out)))))
    (T
     (setq out (list (cons "Diameter"
                           (fit:ftin (* 2.0 (fit:pget
                                              (fit:rget res 'prm) 'r))))))))
  (reverse out))

;; "A-B", "B-C", ... for wall I of an N-wall ring.
(defun fit:wall-name (i n)
  (strcat (chr (+ 65 i)) "-" (chr (+ 65 (rem (1+ i) n)))))

;; The radius a bow of sagitta S over a chord of C implies - the
;; "extremely high R" a wall drawn dead straight really has on site.
(defun fit:bow-radius (s c)
  (+ (/ (* c c) (* 8.0 (abs s))) (/ (abs s) 2.0)))

;; The lines an OUT-OF-SQUARE fit needs: every side by name, the
;; diagonals that pin the shape down (POOL's cross dims), and how far
;; off square the worst wall came out.  A pool held square needs none
;; of this - its sides are its two dimensions.
(defun fit:square-lines (res / dirs offs corners n i j out worst sw base
                               names)
  (setq dirs (fit:rget res 'dirs)
        offs (fit:rget res 'offs)
        out  nil)
  (if (or (null dirs) (null (fit:rget res 'swung)))
    nil
    (progn
      (setq corners (fit:poly-corners dirs offs)
            n       (length corners)
            base    (fit:template-dirs (fit:rget res 'type)
                                       (fit:rget res 'treat) n)
            worst   0.0
            i       0)
      (while (< i n)
        (setq sw (abs (fit:signed-dang (nth i base) (nth i dirs))))
        (if (> sw worst) (setq worst sw))
        (setq out (cons (cons (strcat "Side " (fit:wall-name i n))
                              (fit:ftin (fit:dist
                                          (nth i corners)
                                          (nth (rem (1+ i) n) corners))))
                        out)
              i   (1+ i)))
      ;; the diagonals: every corner to the one opposite it
      (setq i 0)
      (while (< i (/ n 2))
        (setq j (rem (+ i (/ n 2)) n)
              out (cons (cons (strcat "Diagonal "
                                      (chr (+ 65 i)) "-" (chr (+ 65 j)))
                              (fit:ftin (fit:dist (nth i corners)
                                                  (nth j corners))))
                        out)
              i   (1+ i)))
      (setq out (cons (cons "Out of square by"
                            (strcat (rtos (/ (* 180.0 worst) pi) 2 2)
                                    " deg at the worst wall"))
                      out))
      (reverse out))))

;; The template directions a type started from, for measuring how far
;; a wall has swung.
(defun fit:template-dirs (ptype treat n)
  (cond
    ((= n 8) fit:*grec-dirs*)
    ((= ptype "L") fit:*l-dirs*)
    ((= ptype "LAzyl") fit:*lazy-dirs*)
    (T fit:*rect-dirs*)))

;; One report line per wall the fit found bowed.
(defun fit:bow-lines (res / bows out i n corners s c span nm)
  (setq bows (fit:rget res 'bows) out nil)
  (if bows
    (if (eq (fit:rget res 'kind) 'poly)
      (progn
        (setq corners (fit:poly-corners (fit:rget res 'dirs)
                                        (fit:rget res 'offs))
              n       (length corners)
              i       0)
        (while (< i n)
          (setq s (nth i bows))
          (if (and s (not (equal s 0.0 1.0e-12)))
            (setq c   (fit:dist (nth i corners)
                                (nth (rem (1+ i) n) corners))
                  out (cons (cons (strcat "Wall " (fit:wall-name i n)
                                          " bowed")
                                  (strcat (fit:ftin (abs s))
                                          (if (> s 0.0) " out" " in")
                                          "  (R "
                                          (fit:ftin (fit:bow-radius s c))
                                          ")"))
                            out)))
          (setq i (1+ i))))
      (progn
        (setq span (fit:cap-wall-span (fit:rget res 'prm)
                                      (fit:rget res 'both))
              c    (abs (- (cadr span) (car span)))
              i    0)
        (foreach s bows
          (if (and s (not (equal s 0.0 1.0e-12)))
            (setq nm  (if (= i 0) "A" "B")
                  out (cons (cons (strcat "Side wall " nm " bowed")
                                  (strcat (fit:ftin (abs s))
                                          (if (> s 0.0) " out" " in")
                                          "  (R "
                                          (fit:ftin (fit:bow-radius s c))
                                          ")"))
                            out)))
          (setq i (1+ i))))))
  (reverse out))

;; Ring every point beyond the tolerance on the miss layer (stamped, so
;; only FITABHD's own rings are ever swept) and print the hit report.
(defun fit:report (res dpts tol allow / segs non noff nbad q d dmin s
                                        keyed pr worst line)
  (setq segs (fit:verts-to-segs (fit:res-world-verts res))
        non 0 noff 0 nbad 0 keyed nil worst 0.0)
  (foreach q dpts
    (setq dmin nil)
    (foreach s segs
      (setq d (fit:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin worst) (setq worst dmin))
    (cond
      ((<= dmin fit:*on-eps*) (setq non (1+ non)))
      ((<= dmin tol) (setq noff (1+ noff)))
      (T (setq nbad (1+ nbad)
               keyed (cons (cons dmin q) keyed)))))
  (princ (strcat "\n\nFITABHD: " (fit:rget res 'type)
                 " template fitted at "
                 (rtos (rem (/ (* 180.0 (fit:rget res 'angle)) pi) 180.0)
                       2 2)
                 " degrees."))
  (foreach pr (append (fit:dims-lines res) (fit:square-lines res)
                      (fit:bow-lines res))
    (setq line (car pr))
    (while (< (strlen line) 18) (setq line (strcat line " ")))
    (princ (strcat "\n  " line (cdr pr))))
  (princ (strcat "\n  Points on the outline:        " (itoa non)))
  (princ (strcat "\n  Points off within tolerance:  " (itoa noff)))
  (princ (strcat "\n  Points beyond tolerance:      " (itoa nbad)
                 "  (allowance " (itoa allow) ")"))
  (princ (strcat "\n  Worst point deviation:        " (rtos worst 2 3)))
  (if (> nbad allow)
    (princ (strcat "\n  MORE POINTS ARE BEYOND THE DISTANCE THAN YOU"
                   " ALLOWED (" (itoa nbad) " of " (itoa (length dpts))
                   ")."
                   "\n  Redo with a looser distance or a bigger"
                   " percentage, leave the strays out,"
                   "\n  or the survey may not be a " (fit:rget res 'type)
                   " at all.")))
  ;; rings from an earlier run describe a fit that no longer exists
  (fit:purge-mine fit:*miss-layer*)
  (if keyed
    (progn
      (fit:ensure-layer fit:*miss-layer* 1)
      (princ (strcat "\n  POINTS OFF THE FIT (" (itoa nbad)
                     "), ringed on " fit:*miss-layer* ", worst first:"))
      ;; insertion sort, worst first
      (setq keyed (fit:sort-desc keyed))
      (foreach pr keyed
        (fit:tag-mine (fit:make-circle (cdr pr) fit:*miss-radius*
                                       fit:*miss-layer*))
        (princ (strcat "\n    Pt." (fit:pt-name (cdr pr))
                       "   off by " (rtos (car pr) 4 4))))
      (princ (strcat "\n  A stray this far off is usually a mis-shot, a"
                     "\n  duplicate, or a feature the chosen type cannot"
                     "\n  say - ABHD traces those."))))
  nbad)

;; sort (key . val) pairs descending by key (insertion sort)
(defun fit:sort-desc (lst / out x)
  (foreach x lst (setq out (fit:ins-desc x out)))
  out)
(defun fit:ins-desc (x lst)
  (cond ((null lst) (list x))
        ((> (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (fit:ins-desc x (cdr lst))))))

;; ---- the standard-hopper bottom --------------------------------------
;; The bottom is GENERATED, not traced: the type gave us the pool's own
;; frame, so the breaks run dead square across the chosen leg, the
;; hopper is the offset rectangle every standard order sheet means, and
;; the slopes are straight lines.  Anything fancier is ABHD/ADAB's job.

;; T when a typed string means "go back a step"
(defun fit:back-word (s)
  (member (strcase s) '("B" "BACK" "U" "UNDO")))

;; Show an offset the way it was typed: architectural when it came in
;; as feet-and-inches, plain inches otherwise.  DEF is (value . ftin).
(defun fit:fmt-off (def)
  (if (cdr def) (rtos (car def) 4 4) (rtos (car def) 2 2)))

;; Read a distance, remembering HOW it was typed - as feet-and-inches
;; (3'6) or plain inches (42).  Returns (value . ftin); Enter takes
;; DEF, a pair from the previous entry.  Typing B goes back (FIT-BACK)
;; when BACK is on.
(defun fit:get-off (msg def back / s v res)
  (setq res nil)
  (while (null res)
    (setq s (getstring T (strcat "\n" msg " <" (fit:fmt-off def) ">"
                                 (if back " [Back]" "") ": ")))
    (cond
      ((= s "") (setq res def))
      ((and back (fit:back-word s)) (setq res 'FIT-BACK))
      (T
       (setq v (distof s 4))
       (cond
         ((null v)
          (princ "\n  (that is not a distance - type inches like 42, or feet and inches like 3'6)"))
         ((<= v 0.0)
          (princ "\n  (the distance must be positive)"))
         (T (setq res (cons v (if (wcmatch s "*'*") T nil))))))))
  res)

;; The standard hopper in LEG coordinates: x = distance into the pool
;; from the deep end wall, y = across, side walls at S1 < S2.  DB/SB =
;; the two break stations, SO/BO the side and back offsets.  Returns
;; (pts lines): pts = (W1 W2 H1 H2 B1 B2 P1 P2), lines = (pa pb dashed).
(defun fit:hopper-layout (db sb s1 s2 so bo / w1 w2 h1 h2 b1 b2 p1 p2)
  (setq w1 (list db s1) w2 (list db s2)
        h1 (list db (+ s1 so)) h2 (list db (- s2 so))
        b1 (list bo (+ s1 so)) b2 (list bo (- s2 so))
        p1 (list sb s1) p2 (list sb s2))
  (list (list w1 w2 h1 h2 b1 b2 p1 p2)
        (list (list w1 h1 T) (list h2 w2 T)     ; deep-break stubs
              (list h1 h2 nil)                  ; deep break, solid run
              (list h1 b1 nil) (list b1 b2 nil) (list b2 h2 nil)
              (list h1 p1 nil) (list h2 p2 nil) ; straight slope lines
              (list p1 p2 nil))))               ; shallow break

;; direction frame->world (no translation)
(defun fit:ffd (v a mirror)
  (fit:rot (if mirror (list (car v) (- (cadr v))) v) a))

;; The pool's candidate deep ends, one leg per end wall the type has:
;; ((origin u v s1 s2) ...) in WORLD coordinates - origin ON the end
;; wall at its middle, u pointing INTO the pool, v across, the side
;; walls at v-coordinates s1 < s2 relative to the origin.
(defun fit:legs (res / t2 a m dirs offs corners ends e n c1 c2 o u v s1
                       s2 out prm yb yt cy half)
  (setq t2 (fit:rget res 'type)
        a  (fit:rget res 'angle)
        m  (fit:rget res 'mirror)
        out nil)
  (if (eq (fit:rget res 'kind) 'poly)
    (progn
      (setq dirs    (fit:rget res 'dirs)
            offs    (fit:rget res 'offs)
            corners (fit:poly-corners dirs offs)
            n       (length dirs)
            ends    (cond ((= t2 "L") '(1 5))
                          ((= t2 "LAzyl") '(2 5))
                          ((= 8 n) '(2 6))
                          (T '(1 3))))
      (foreach e ends
        (setq c1 (nth e corners)
              c2 (nth (rem (1+ e) n) corners)
              o  (fit:mid c1 c2)
              u  (fit:v* (fit:wall-normal (nth e dirs)) -1.0)
              v  (fit:perp u)
              s1 (fit:dot v (fit:v- c1 o))
              s2 (fit:dot v (fit:v- c2 o)))
        (if (> s1 s2) (setq c1 s1 s1 s2 s2 c1))
        (setq out (cons (list (fit:from-frame o a m)
                              (fit:ffd u a m) (fit:ffd v a m) s1 s2)
                        out))))
    (progn                                ; cap types: end lines
      (setq prm  (fit:rget res 'prm)
            yb   (fit:pget prm 'By)
            yt   (fit:pget prm 'Ty)
            cy   (/ (+ yb yt) 2.0)
            half (/ (- yt yb) 2.0))
      (setq out (list (list (fit:from-frame
                              (list (fit:pget prm 'Re) cy) a m)
                            (fit:ffd '(-1.0 0.0) a m)
                            (fit:ffd '(0.0 1.0) a m)
                            (- half) half)))
      (if (fit:rget res 'both)
        (setq out (cons (list (fit:from-frame
                                (list (fit:pget prm 'Re2) cy) a m)
                              (fit:ffd '(1.0 0.0) a m)
                              (fit:ffd '(0.0 1.0) a m)
                              (- half) half)
                        out))
        (setq out (cons (list (fit:from-frame
                                (list (fit:pget prm 'Lx) cy) a m)
                              (fit:ffd '(1.0 0.0) a m)
                              (fit:ffd '(0.0 1.0) a m)
                              (- half) half)
                        out)))))
  out)

;; leg point -> world
(defun fit:leg-pt (leg p)
  (fit:v+ (car leg)
          (fit:v+ (fit:v* (cadr leg) (car p))
                  (fit:v* (caddr leg) (cadr p)))))

;; The standard-hopper flow over a kept fit.  Asks which end is deep,
;; the two break stations and the two offsets (Back steps backwards),
;; then draws the whole bottom square to the leg's own frame.
(defun fit:bottom (res / legs pick leg best bd lg d step go db sb so bo
                        v w lay pts lines ln p1w p2w h1 h2 w1 w2 mid)
  (setq legs (fit:legs res))
  (setq pick (getpoint "\nPick a point at the DEEP end of the pool: "))
  (if (null pick)
    (princ "\nFITABHD: no deep end picked - no bottom drawn.")
    (progn
      (setq best nil bd nil)
      (foreach lg legs
        (setq d (fit:dist (fit:2d pick) (car lg)))
        (if (or (null bd) (< d bd)) (setq best lg bd d)))
      (setq leg best
            w   (- (nth 4 leg) (nth 3 leg))
            step 1 go T)
      (while (and go (<= step 4))
        (cond
          ((= step 1)
           (setq v (fit:get-off
                     "Deep break - how far from the deep end wall?"
                     fit:*brk-deep* nil))
           (setq fit:*brk-deep* v db (car v) step 2))
          ((= step 2)
           (setq v (fit:get-off
                     "Shallow break - how far from the deep end wall?"
                     fit:*brk-shal* T))
           (cond
             ((eq v 'FIT-BACK)
              (princ "\nStepping back one step.")
              (setq step 1))
             ((<= (car v) (+ db 6.0))
              (princ "\n  (the shallow break must sit past the deep break - at least 6\" further from the deep end)"))
             (T (setq fit:*brk-shal* v sb (car v) step 3))))
          ((= step 3)
           (setq v (fit:get-off
                     "Hopper offset in from each side wall"
                     fit:*hop-side* T))
           (cond
             ((eq v 'FIT-BACK)
              (princ "\nStepping back one step.")
              (setq step 2))
             ((>= (* 2.0 (car v)) (- w 2.0))
              (princ (strcat "\n  (twice that offset leaves no hopper - the pool is only "
                             (fit:ftin w) " wide here)")))
             (T (setq fit:*hop-side* v so (car v) step 4))))
          ((= step 4)
           (setq v (fit:get-off
                     "Hopper offset in from the deep end wall"
                     fit:*hop-back* T))
           (cond
             ((eq v 'FIT-BACK)
              (princ "\nStepping back one step.")
              (setq step 3))
             ((>= (car v) (- db 1.0))
              (princ "\n  (the back offset must stay short of the deep break)"))
             (T (setq fit:*hop-back* v bo (car v) step 5))))))
      (if (> step 4)
        (progn
          (fit:ensure-layer fit:*pool-layer* 4)
          (fit:ensure-dashed2)
          (setq lay  (fit:hopper-layout db sb (nth 3 leg) (nth 4 leg)
                                        so bo)
                pts  (car lay)
                lines (cadr lay))
          (foreach ln lines
            (setq p1w (fit:leg-pt leg (car ln))
                  p2w (fit:leg-pt leg (cadr ln)))
            (fit:tag-mine
              (fit:make-line p1w p2w (if (caddr ln) "DASHED2" nil))))
          ;; the K/L/M string a foot off the deep break, shallow side
          (setq w1 (nth 0 pts) w2 (nth 1 pts)
                h1 (nth 2 pts) h2 (nth 3 pts)
                mid (+ db fit:*dim-off*))
          (foreach ln (list (list w1 h1) (list h1 h2) (list h2 w2))
            (fit:tag-mine
              (fit:make-dim (fit:leg-pt leg (car ln))
                            (fit:leg-pt leg (cadr ln))
                            (fit:leg-pt leg
                                        (list mid
                                              (/ (+ (cadr (car ln))
                                                    (cadr (cadr ln)))
                                                 2.0))))))
          ;; and one on the back offset, on the hopper's centreline
          (fit:tag-mine
            (fit:make-dim (fit:leg-pt leg (list 0.0 0.0))
                          (fit:leg-pt leg (list bo 0.0))
                          nil))
          (princ (strcat "\nFITABHD: standard hopper drawn on layer "
                         fit:*pool-layer* " - breaks at "
                         (fit:ftin db) " and " (fit:ftin sb)
                         " from the deep end, hopper "
                         (fit:ftin (- (- (nth 4 leg) so)
                                      (+ (nth 3 leg) so)))
                         " wide."))
          (princ "\nDeep-break stubs are dashed; the K/L/M string reads from the shallow side."))))))

;; A Round pool's bottom is a concentric hopper ring.
(defun fit:round-bottom (res / prm r v off c)
  (setq prm (fit:rget res 'prm)
        r   (fit:pget prm 'r)
        v   (fit:get-off "Hopper offset in from the wall"
                         fit:*hop-back* nil))
  (setq off (car v))
  (if (>= off (- r 1.0))
    (princ "\n  (that offset leaves no hopper - nothing drawn)")
    (progn
      (setq fit:*hop-back* v
            c (fit:from-frame (list (fit:pget prm 'cx)
                                    (fit:pget prm 'cy))
                              (fit:rget res 'angle)
                              (fit:rget res 'mirror)))
      (fit:ensure-layer fit:*pool-layer* 4)
      (fit:tag-mine (fit:make-circle c (- r off) fit:*pool-layer*))
      (fit:tag-mine (fit:make-dim c (fit:v+ c (list (- r off) 0.0)) nil))
      (princ (strcat "\nFITABHD: hopper ring drawn at "
                     (fit:ftin off) " in from the wall.")))))

;; ---- the questions ---------------------------------------------------
;; All five in one place, with Back stepping backwards through them,
;; so a Redo can re-open exactly the same questions without asking for
;; the selection again.  DEF is the current (ptype treat tol pct
;; bowed); Enter keeps each answer.  TOTAL is how many steps the run
;; has, so the labels read true on a first run (6, the selection last)
;; and on a Redo (5, the points already in hand).
(defun fit:ask-settings (def total / step ptype treat tol pct oos bowed v
                                    n)
  (setq ptype (nth 0 def)
        treat (nth 1 def)
        tol   (nth 2 def)
        pct   (nth 3 def)
        oos   (nth 4 def)
        bowed (nth 5 def)
        n     (itoa total)
        step  1)
  (while (<= step 6)
    (cond
      ((= step 1)
       (setq v (fit:askkw (strcat "\n  Step 1 of " n
                                  " - what type of pool is this?\nPool type")
                          fit:*types*
                          "Rectangle/Grecian/ROman/Oval/L/LAzyl/ROUnd"
                          ptype nil))
       (setq ptype v fit:*ptype* v step 2))
      ((= step 2)
       ;; the corner question - for a Grecian it asks about the eight
       ;; CUT-corner vertices: the nominal drawing is sharp, but an
       ;; as-built may well ease them, and Radius measures that easing
       ;; from the points (a fit too small to believe stays sharp).
       ;; The arc-ended and round templates keep their corners square.
       (cond
         ((member ptype '("Rectangle" "L" "LAzyl"))
          (princ (strcat "\n\n  Step 2 of " n
                         " - the pool corners.  The SIZE is not asked:"))
          (princ "\n  the radius or cut face is measured from the points.")
          (setq v (fit:asktreat "the pool corners"
                                (if fit:*treat* fit:*treat* "Radius") T)))
         ((= ptype "Grecian")
          (princ (strcat "\n\n  Step 2 of " n
                         " - the cut corners.  Nominal grecians are sharp,"))
          (princ "\n  but an as-built may ease them - Radius measures that easing")
          (princ "\n  from the points (too small to believe stays sharp).")
          (setq v (fit:asktreat "the cut corners"
                                (if fit:*gtreat* fit:*gtreat* "Radius") T)))
         (T (setq v "Square")))
       (if (eq v 'FIT-BACK)
         (progn (princ "\nStepping back one step.")
                (setq step 1))
         (progn
           (setq treat v)
           (if (member ptype '("Rectangle" "L" "LAzyl"))
             (setq fit:*treat* v))
           (if (= ptype "Grecian") (setq fit:*gtreat* v))
           (setq step 3))))
      ((= step 3)
       (princ (strcat "\n\n  Step 3 of " n
                      " - how far may the fitted outline sit from a"))
       (princ "\n  survey point?  Smaller hugs the survey; bigger lets the")
       (princ "\n  nice whole-foot dimensions win more often.")
       (initget 6 "Back Undo")
       (setq v (getdist (strcat "\nMaximum distance from a point <"
                                (rtos tol 2 3) "> [Back]: ")))
       (cond
         ((and (= (type v) 'STR) (member v '("Back" "Undo")))
          (princ "\nStepping back one step.")
          (setq step 2))
         (T
          (if (null v) (setq v tol))
          (if (> v fit:*tol-max*)
            (progn
              (princ (strcat "\n  (pulled back to "
                             (rtos fit:*tol-max* 2 1)
                             " - further than that and the fit is no"
                             " longer a trace of the points)"))
              (setq v fit:*tol-max*)))
          (setq tol v fit:*tol* v step 4))))
      ((= step 4)
       (princ (strcat "\n\n  Step 4 of " n
                      " - what percent of the points may sit BEYOND"))
       (princ "\n  that distance?  That slack is what buys whole-foot")
       (princ "\n  dimensions: a snap is kept when only this share of the")
       (princ "\n  points object to it.")
       (initget 6 "Back Undo")
       (setq v (getint (strcat "\nPercent of points allowed beyond <"
                               (itoa (fix (+ 0.5 (* 100.0 pct))))
                               "> [Back]: ")))
       (cond
         ((and (= (type v) 'STR) (member v '("Back" "Undo")))
          (princ "\nStepping back one step.")
          (setq step 3))
         ((null v) (setq step 5))
         ((> v 100)
          (princ "\n  (more than 100 makes no sense - using 100)")
          (setq pct 1.0 step 5))
         (T (setq pct (/ v 100.0) step 5))))
      ((= step 5)
       ;; POOL asks the same question of the same pools, in the same
       ;; words: an AB pool is built, not drawn, and almost none of
       ;; them come out true.  Outofsquare lets each wall swing a
       ;; little to answer its own points - and a pool that really is
       ;; square still comes out square, because a swing is kept only
       ;; where the points prove it.
       (if (member ptype '("ROman" "Oval" "ROUnd"))
         (setq v nil)                      ; no free straight walls
         (progn
           (princ (strcat "\n\n  Step 5 of " n
                          " - is the pool in-square, or out of square?"))
           (princ "\n  Outofsquare lets each wall swing a little to honour the")
           (princ "\n  points; Insquare holds the template true and shows you")
           (princ "\n  the error instead.")
           (setq v (fit:askkw "Is the pool in-square or out-of-square?"
                              "Insquare Outofsquare"
                              "Insquare/Outofsquare"
                              (if oos "Outofsquare" "Insquare") T))
           (if (not (eq v 'FIT-BACK)) (setq v (= v "Outofsquare")))))
       (if (eq v 'FIT-BACK)
         (progn (princ "\nStepping back one step.")
                (setq step 4))
         (setq oos v step 6)))
      ((= step 6)
       (if (= ptype "ROUnd")
         (setq v nil)                      ; a round pool has no walls
         (progn
           (princ (strcat "\n\n  Step 6 of " n
                          " - may the straight walls be bowed?"))
           (princ "\n  A wall drawn dead straight is very often a very long")
           (princ "\n  radius on site.  Yes measures a bow on every wall from")
           (princ "\n  the points and keeps it only where they prove one - a")
           (princ "\n  wall that really is straight stays straight, and no bow")
           (princ "\n  ever moves a corner.")
           (setq v (fit:askyn "Any bowed walls?"
                              (if bowed "Yes" "No") T))))
       (if (eq v 'FIT-BACK)
         (progn (princ "\nStepping back one step.")
                (setq step 5))
         (setq bowed v step 7)))))
  (setq fit:*oos* oos fit:*bowed* bowed)
  (list ptype treat tol pct oos bowed))

;; ---- leaving points out ----------------------------------------------
;; A fit that came out wrong is usually one bad shot dragging a wall.
;; On a Redo the user can set those points aside - and pick a ringed
;; one again to put it back.

;; T when Q is one of the points currently set aside.
(defun fit:omitted-p (q / found x)
  (foreach x fit-omit
    (if (< (fit:dist (car x) q) fit:*exact-eps*) (setq found T)))
  found)

;; The points the fit may use: everything gathered, less the ones set
;; aside.
(defun fit:active ( / out q)
  (setq out nil)
  (foreach q fit-pts
    (if (not (fit:omitted-p q)) (setq out (cons q out))))
  (reverse out))

;; The dashed ring marking a point left out of the fit.
(defun fit:omit-ring (p)
  (fit:ensure-dashed2)
  (fit:ensure-layer fit:*out-layer* 2)
  (fit:tag-mine
    (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                    (cons 8 fit:*out-layer*) '(6 . "DASHED2")
                    (cons 62 1) '(100 . "AcDbCircle")
                    (cons 10 (list (car p) (cadr p) 0.0))
                    (cons 40 fit:*miss-radius*)))))

;; Which way a pick goes: (RESTORE . pt) when it lands nearer a point
;; already set aside, (OMIT . pt) when it lands nearer one still in the
;; fit, nil when it lands near neither.  Every pick is a toggle.
(defun fit:omit-choose (wp / w1 w2)
  (setq w1 (fit:nearest wp (fit:active))
        w2 (fit:nearest wp (mapcar 'car fit-omit)))
  (cond
    ((and w2 (or (null w1) (<= (fit:dist wp w2) (fit:dist wp w1))))
     (cons 'RESTORE w2))
    (w1 (cons 'OMIT w1))))

;; fit-omit without the entry for point Q (and its ring erased).
(defun fit:omit-drop (q / out x)
  (setq out nil)
  (foreach x fit-omit
    (if (< (fit:dist (car x) q) fit:*exact-eps*)
      (if (and (cadr x) (entget (cadr x))) (entdel (cadr x)))
      (setq out (cons x out))))
  (reverse out))

;; The omit/restore loop.  Each pick toggles: a point in the fit goes
;; out and gets a ring, a ringed one comes back in and loses it.
(defun fit:omit-loop ( / wp pick)
  (princ "\n\n  Any points to leave out this time?")
  (princ "\n  Pick each one (Enter for none) - mis-shots, duplicates, or")
  (princ "\n  anything the outline should not chase; each gets a dashed ring.")
  (if fit-omit
    (princ (strcat "\n  " (itoa (length fit-omit))
                   " point(s) are already out - picking one of those puts"
                   " it BACK IN.")))
  (while (setq wp (getpoint "\n  Point to leave out - or a ringed one to restore (Enter when done): "))
    (setq pick (fit:omit-choose (fit:2d wp)))
    (cond
      ((null pick) (princ "  - (no survey point near that pick)"))
      ((eq (car pick) 'RESTORE)
       (setq fit-omit (fit:omit-drop (cdr pick)))
       (princ (strcat "  - Pt." (fit:pt-name (cdr pick)) " back in")))
      (T
       (setq fit-omit (cons (list (cdr pick) (fit:omit-ring (cdr pick)))
                            fit-omit))
       (princ (strcat "  - leaving out Pt."
                      (fit:pt-name (cdr pick))))))))

;; Erase the omission rings; they are scaffolding, not a result.
(defun fit:omit-clear ( / x)
  (foreach x fit-omit
    (if (and (cadr x) (entget (cadr x))) (entdel (cadr x))))
  (princ))

;; ---- the commands ----------------------------------------------------

(defun c:FITABHDVER ()
  (princ (strcat "\nFITABHD " *fitabhd-version* " loaded."))
  (princ))

(defun c:FITABHD ( / *error* undo-open set ptype treat tol pct oos bowed
                    ss n res verts en swept ans again dpts
                    fit-pts fit-npt fit-ptnames fit-omit)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (fit:sysrestore)
    (if undo-open (command "_.UNDO" "_End"))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nFITABHD error: " msg)))
    (princ))
  (fit:syssave '("OSMODE" "CMDECHO" "CLAYER"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  ;; a preview a dead run left behind describes nothing - sweep it
  (setq swept (fit:purge-mine fit:*out-layer*))
  (if (> swept 0)
    (princ (strcat "\nFITABHD: swept " (itoa swept)
                   " leftover preview outline(s) from an earlier run.")))
  (princ "\n\nFITABHD - fit a typical pool's template through the survey points.")
  (setq fit-pts nil fit-npt 0 fit-ptnames nil fit-omit nil
        set (fit:ask-settings (list fit:*ptype* "Square" fit:*tol*
                                    fit:*miss-pct* fit:*oos* fit:*bowed*)
                              7)
        ptype (nth 0 set))
  (princ (strcat "\n\n  Step 7 of 7 - select the survey points (POINTS layer or"
                 "\n  " fit:*point-block* " blocks)."))
  (princ "\n  Select objects: ")
  (setq ss (ssget '((0 . "POINT,INSERT"))))
  (cond
    ((null ss)
     (princ (strcat "\nNothing usable selected (POINT entities on layer "
                    fit:*point-layer* " or \"" fit:*point-block*
                    "\" block insertions).")))
    ((< (setq n (fit:gather ss)) (if (= ptype "ROUnd") 3 6))
     (princ (strcat "\nOnly " (itoa n) " survey point(s) found - a "
                    ptype " template needs at least "
                    (itoa (if (= ptype "ROUnd") 3 6)) ".")))
    (T
     (if (> n 150)
       (princ (strcat "\nFITABHD: " (itoa n)
                      " points - ordering and fitting will take a"
                      " little while, please wait...")))
     (setq again T)
     (while again
       (setq again nil
             ptype (nth 0 set) treat (nth 1 set) tol (nth 2 set)
             pct   (nth 3 set) oos   (nth 4 set) bowed (nth 5 set)
             dpts  (fit:dedupe (fit:active) fit:*exact-eps*))
       (if (< (length dpts) (if (= ptype "ROUnd") 3 6))
         (princ (strcat "\nToo few points left in the fit ("
                        (itoa (length dpts))
                        ") - put some back on the next Redo."))
         (progn
           (princ (strcat "\nFitting the " ptype
                          " template every way it can sit, keeping the"
                          " best..."))
           (setq res   (fit:fit-and-snap dpts ptype treat tol pct oos
                                         bowed)
                 verts (fit:res-world-verts res))
           (fit:ensure-layer fit:*out-layer* 2)
           (setq en (fit:tag-mine (fit:make-pline verts fit:*out-layer* 2)))
           (fit:report res dpts tol (fit:rget res 'allow))))
       (setq ans (fit:askkw "\nKeep this fit, or Redo it?"
                         "Keep Redo Erase" "Keep/Redo/Erase"
                         (if res "Keep" "Redo") nil))
       (cond
         ((= ans "Redo")
          ;; the preview and its rings describe a fit that is about to
          ;; stop existing
          (if (and en (entget en)) (entdel en))
          (fit:purge-mine fit:*miss-layer*)
          (setq en nil res nil)
          (princ "\n\nRedoing the fit - the same points, new settings.")
          (fit:omit-loop)
          (setq set   (fit:ask-settings set 6)
                again T))
         ((and (= ans "Keep") res)
          (fit:omit-clear)
          (fit:set-bylayer en)
          (princ (strcat "\nKept - the outline moved to layer "
                         fit:*pool-layer* " in ByLayer colour."))
          (if (fit:askyn (if (= ptype "ROUnd")
                           "Add the bottom of the pool (hopper ring)?"
                           "Add the bottom of the pool (standard hopper)?")
                         "No" nil)
            (if (= ptype "ROUnd")
              (fit:round-bottom res)
              (fit:bottom res))))
         (T
          (fit:omit-clear)
          (if (and en (entget en)) (entdel en))
          (fit:purge-mine fit:*miss-layer*)
          (princ "\nNothing kept - the drawing is unchanged."))))))
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (fit:sysrestore)
  (princ))

;; ----------------------------------------------------------------------
(princ (strcat "\nFITABHD " *fitabhd-version*
               " loaded.  Type FITABHD to run (FITABHDVER for the"
               " version)."))
(princ)
