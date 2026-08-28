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
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; WHAT THE TYPE IS FOR.  The type is not a promise about the shape,
;;; it is what lets the survey be READ: it says which walls belong
;;; together, which corner is a corner, which end is an end.  The
;;; POINTS decide where all of that actually goes.  An AB pool is
;;; built, not drawn, so the points are imperfect - and the shape that
;;; comes out of them is meant to be imperfect too.  Every deviation
;;; the tool can draw is fitted FROM the points and kept only where
;;; they prove it: out of square, bowed walls, eased corners, an end
;;; that caved in.  Hold the template rigid and the error does not go
;;; away, it just moves into the points, where nobody can see it.
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
;;;   * A ROMAN OR OVAL'S SIDE WALLS ARE NOT HELD PARALLEL.  A gunite
;;;     shell slumps as it cures, so one wall very often slants away
;;;     from the other; out of square, each answers its own points and
;;;     the two may lean up to fit:*cap-oos-max* (10 degrees) apart.
;;;     Each end cap is then fitted across the body AT ITS OWN END, and
;;;     the frame angle is fitted too - the edge vote cannot find the
;;;     body's axis when the walls disagree, and a crooked axis draws a
;;;     crooked flat end.
;;;   * AN ARC IS NOT PROMISED TO BE ONE RADIUS.  What a drawing
;;;     calls one R is, on a built shell, very often a run of arcs -
;;;     it slumps as it cures.  An arc a single radius cannot hold
;;;     within the typed tolerance is rebuilt as a polyline of arcs
;;;     whose joints sit on survey points, and the run keeps going
;;;     while each extra arc clearly earns its place, not just until
;;;     it scrapes inside the tolerance.  Every joint is held to
;;;     ABHD's own tangency window - fit:*tang-tol*, 8 degrees,
;;;     stretched through fit:*tang-steps* rather than abandoned - so
;;;     the run reads as a curve rather than a row of facets while
;;;     the POINTS still choose inside that window.  An end that
;;;     really is one radius stays one arc.
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

;; Cover mode: the pool-bottom question answers No without being asked,
;; so a cover sheet is fitted to its perimeter and stops there.  Set by
;; FITABHDCOVER, cleared on both exits from c:FITABHD.
(setq fit:*nobottom* nil)

(setq *fitabhd-version* "v2.0")    ; announced on load; release_lisp.py
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
(setq fit:*cap-oos-max* (/ pi 18.0)); how far a Roman or Oval side
                                   ; wall may lean, and how far the two
                                   ; may diverge from each other (10
                                   ; degrees).  An arc-ended shell
                                   ; slumps as it cures and the walls
                                   ; slant away, so they are NEVER held
                                   ; parallel the way a rectangle's
                                   ; template holds its own: they are
                                   ; two independent walls that happen
                                   ; to start out parallel
(setq fit:*arc-pts-min* 3)         ; points each arc of a run needs
                                   ; before it means anything - and so,
                                   ; the only thing that limits how many
                                   ; arcs a curve may be broken into: a
                                   ; curve carrying N points may become
                                   ; at most N/3 arcs.  There is no
                                   ; fixed ceiling.  A shell that
                                   ; wandered over forty shots has
                                   ; earned more arcs than one shot ten
                                   ; times, and the earning rule below
                                   ; stops the run long before this
                                   ; limit on anything that is really
                                   ; one radius
(setq fit:*tang-tol* (/ pi 22.5))  ; ABHD's own tangency window (8
                                   ; degrees): how far the next arc of
                                   ; a run may start off the tangent
                                   ; the last one ended on.  A run that
                                   ; only shares its joints is
                                   ; continuous but not SMOOTH - the
                                   ; end of the pool reads as a row of
                                   ; facets - and holding the joints
                                   ; perfectly tangent would take them
                                   ; off the survey points.  A window
                                   ; keeps both: smooth to the eye,
                                   ; with the points still choosing
                                   ; inside it
(setq fit:*tang-steps* '(1.0 1.25 1.5)) ; when nothing inside the window
                                   ; holds the points, stretch it by
                                   ; these in turn rather than abandon
                                   ; it - ABHD's rule, and for ABHD's
                                   ; reason: smoothness is worth more
                                   ; than an exact hit
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
(setq fit:*oas-fuzz*    1.0e-6)    ; OASIS's own fuzz, for the ring
(setq fit:*oas-huge*    1.0e18)    ; the score of a ring that will not build
(setq fit:*oas-line*    20.0)      ; a joiner radius past this many
                                   ; envelope-sides has flattened into the
                                   ; straight run it is drawn as - the
                                   ; reverse arc with an infinite radius,
                                   ; which is what a cloud's flat bottom is
(setq fit:*oas-rmin*    0.04)      ; and the smallest joiner radius worth
                                   ; hunting, as a share of that side
(setq fit:*oas-astep* (/ pi 12.0)) ; the coarse frame sweep's step (15
                                   ; degrees).  An oasis has no walls to
                                   ; vote on its rotation the way every
                                   ; other type does, so the frame is
                                   ; searched rather than measured
(setq fit:*oas-aspan* (/ pi 9.0))  ; how far the angle hunts either way on
                                   ; the first round (20 degrees), halving
                                   ; on each one after it
(setq fit:*oas-apart* (/ pi 7.2))  ; and how far apart two coarse
                                   ; placements have to sit (25 degrees) to
                                   ; count as different tries: three tries
                                   ; a few degrees apart are one try
(setq fit:*oas-tries*   3)         ; how many of them get a real fit
(setq fit:*oas-coarse*  26)        ; points the coarse sweep works on, and
(setq fit:*oas-rough*   40)        ; the early rounds of a real fit: where
                                   ; a pool SITS is a question about the
                                   ; shape of the survey, not about how
                                   ; many times the crew shot each wall
(setq fit:*oas-grid*    6)         ; grid samples per parameter per pass
(setq fit:*oas-gold*    8)         ; golden-section rounds after the grid
(setq fit:*oas-rounds*  5)         ; shape/envelope/angle rounds per fit
(setq fit:*oas-narrow* '(nil nil 0.35 0.20)) ; the band each round hunts,
                                   ; as a share of the full range.  TWO
                                   ; rounds look over the whole range
                                   ; before any narrowing: the first fits
                                   ; each radius against joiners still at
                                   ; their starting guess, which parks a
                                   ; top bulge too big and its two joiners
                                   ; too tight - a real optimum, and a
                                   ; whole inch worse than the pool.  The
                                   ; second, with the joiners now roughly
                                   ; right, walks back out of it
(setq fit:*oas-edge*    0.8)       ; a kidney fitted the freer way must
                                   ; beat the tighter one by this, like a
                                   ; both-ends cap: extra freedom is not
                                   ; evidence

(setq fit:*types* "Rectangle Grecian ROman Oval L LAzyl ROUnd OAsis")
                                   ; POOL's shape vocabulary, minus the
                                   ; shapes a template cannot say
                                   ; (Octagon rides Grecian, Mutt and
                                   ; freeform are ABHD's job) - and OASIS's
                                   ; on the end, which POOL has no word for
                                   ; because it is not POOL that draws one
(setq fit:*oas-fams* "Center TopRight CLoud Kidney NXTcloud")
                                   ; OASIS's own first question, in OASIS's
                                   ; own words.  The sub-type each of two
                                   ; of them asks for is NOT here: which
                                   ; way a cloud's bottom goes and which
                                   ; way a kidney is given are found from
                                   ; the points
(setq fit:*dim-off*     12.0)      ; the K/L/M string sits this far off
                                   ; the deep break, on the shallow side
(if (null fit:*tol*) (setq fit:*tol* 1.0))       ; remembered per session
;; The rest of the answers a session remembers, so a second run is
;; mostly Enter.  Reading an unset symbol yields nil, so this declares
;; them beside the others without clobbering what a run put there.
(setq fit:*ptype*  fit:*ptype*)
(setq fit:*treat*  fit:*treat*)
(setq fit:*gtreat* fit:*gtreat*)
(setq fit:*oasfam* fit:*oasfam*)
(if (null fit:*oos*) (setq fit:*oos* T))  ; as-builts are never true
(if (null fit:*bowed*) (setq fit:*bowed* T))  ; nor are their walls
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
      (setq p1   (cal:2d p1)
            p2   (cal:2d p2)
            ch   (cal:dist p1 p2))
      (if (< ch 1.0e-12)
        nil
        (progn
          (setq dir  (cal:v* (cal:v- p2 p1) (/ 1.0 ch))
                ;; a positive (CCW) bulge apex lies to the RIGHT of the
                ;; p1->p2 chord direction
                apex (cal:v+ (cal:mid p1 p2)
                             (cal:v* (cal:perp dir) (* -0.5 ch b)))
                c    (fit:circumcenter p1 apex p2))
          (if (null c)
            nil
            (list c (cal:dist c p1) (angle c p1) (angle c p2))))))))

;; Distance from point P to segment (p1 p2 bulge).
(defun fit:seg-dist (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep rel)
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
      (setq g (fit:arc-geom p1 p2 b))
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
    (setq d (cal:dist p q))
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
      (setq d (cal:dist cur q))
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
          ln (cal:dist a b))
    (if (> ln 1.0e-9)
      (progn
        (setq d (* fold (angle a b)))
        (setq sx (+ sx (* ln (cos d)))
              sy (+ sy (* ln (sin d))))))
    (setq i (1+ i)))
  (if (and (< (abs sx) 1.0e-12) (< (abs sy) 1.0e-12))
    0.0
    (rem (/ (cal:angnorm (atan sy sx)) fold) (/ (* 2.0 pi) fold))))

;; rotate P by angle A about the origin
(defun fit:rot (p a / c s)
  (setq c (cos a) s (sin a))
  (list (- (* (car p) c) (* (cadr p) s))
        (+ (* (car p) s) (* (cadr p) c))))

;; World -> frame: rotate by -A, then mirror across X if asked.
(defun fit:to-frame (pts a mirror / out p q)
  (setq out nil)
  (foreach p pts
    (setq q (fit:rot (cal:2d p) (- a)))
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
              v (cal:v- (nth (rem (1+ i) n) c) (nth i c)))
        (if (<= (cal:dot u v) 1.0e-6) (setq ok nil))
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
        (setq dc1 (cal:dist p (nth best corners))
              dc2 (cal:dist p (nth (rem (1+ best) n) corners)))
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
            (setq ssum (+ ssum (cal:dot nrm c))))
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
        turn (cal:signed-dang (nth prev dirs) (nth i dirs))
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
        (setq cc (cal:v+ (nth (car ip) corners)
                         (cal:v* bis (/ r (cos half))))
              e  (- (cal:dist (cdr ip) cc) r))
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
          (setq hsum (+ hsum (cal:dot bis (cal:v- p (nth i corners))))
                n    (1+ n))))))
  (if (or (= n 0) (null turn))
    nil
    (progn
      (setq h (/ hsum n))
      ;; face length from the perpendicular inset: f = 2h / tan(turn/2)
      ;; (the familiar f = 2h only at a square corner)
      (if (<= h 0.0)
        nil
        (/ (* 2.0 h) (cal:tan (/ (abs turn) 2.0)))))))

;; ---- building the drawn outline --------------------------------------

;; The vertex run replacing sharp corner V: a list of (pt bulge).  The
;; bulge on an entry curves the segment LEAVING that point.
(defun fit:corner-verts (vprev v vnext turn treat size / u1 u2 t2 s p1 p2)
  (cond
    ((and (= treat "Radius") size (> size 1.0e-6))
     (setq u1 (angle vprev v)
           u2 (angle v vnext)
           t2 (* size (cal:tan (/ (abs turn) 2.0)))
           p1 (list (- (car v) (* (cos u1) t2))
                    (- (cadr v) (* (sin u1) t2)))
           p2 (list (+ (car v) (* (cos u2) t2))
                    (+ (cadr v) (* (sin u2) t2))))
     (list (list p1 (cal:tan (/ turn 4.0))) (list p2 0.0)))
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
  (setq c (cal:dist a b))
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
                bl   (cal:tan (/ half 2.0)))
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
                cfit  (cal:dist (nth i corners)
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
  (setq c (cal:dist a b))
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
  (setq c  (cal:dist a b)
        ux (/ (- (car b) (car a)) c)
        uy (/ (- (cadr b) (cadr a)) c)
        nx uy
        ny (- ux)
        d2 (- d (atan (cadr coef) c))
        q  (list (+ (car a) (* nx (car coef)))
                 (+ (cadr a) (* ny (car coef))))
        n2 (fit:wall-normal d2))
  (list d2 (cal:dot n2 q)))

;; RMS of the points about the straight line with direction D at
;; outward offset OFF - the wall as the template would hold it.
(defun fit:flat-rms (wpts d off / nrm ssum p e)
  (setq nrm (fit:wall-normal d) ssum 0.0)
  (if (null wpts)
    0.0
    (progn
      (foreach p wpts
        (setq e (- (cal:dot nrm p) off) ssum (+ ssum (* e e))))
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
      (foreach p wpts (setq ssum (+ ssum (cal:dot nrm p))))
      (/ ssum (length wpts)))))

;; A bow may not be deeper than a wall can bow and still be a wall.
(defun fit:bow-cap (s c / smax)
  (setq smax (min fit:*bow-max* (* fit:*bow-max-frac* c)))
  (max (- smax) (min smax s)))

;; A bow is kept only when it is deep enough to read, shallow enough to
;; still be a wall, and beats the straight wall on that wall's own
;; points by a clear margin.  Noise is not a bow.
(defun fit:keep-bow (wpts a b s / c rs rb)
  (setq c (cal:dist a b))
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
    (setq v (cal:dot nrm p))
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
          offs (cons (cal:dot nrm (nth i corners)) offs)
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
  (+ d0 (/ (cal:signed-dang d0 d1) 2.0)))

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
        (setq hsum (+ hsum (- (cal:dot nrm vc) (nth i offs)))
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
              offs (fit:setnth offs i (- (cal:dot nrm vc) h))
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
  (setq tanh  (cal:tan (/ pi 8.0))
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
        (if (>= (abs (cal:signed-dang (nth (rem (+ i n -1) n) dirs)
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
              (if (<= (abs (cal:signed-dang (nth i base) (car d2o)))
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
              swing (cal:signed-dang (nth i base) (nth i dirs))
              ;; the drift the TOTAL swing represents, end to end, in
              ;; inches - not the residual the last pass measured,
              ;; which is near zero once the wall has already been
              ;; swung onto its points
              drift (* (abs (cal:tan swing)) (cal:dist a b)))
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
                                           (cal:dist a b)))
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

;; A cap body's side wall at X.  The template holds the two walls
;; parallel; once the pool is allowed out of square each carries its
;; own slope, and By/Ty are its height at the body's middle.
(defun fit:wall-y (prm side x / off slope)
  (if (= side "b")
    (setq off   (fit:pget prm 'By)
          slope (cond ((fit:pget prm 'sb)) (0.0)))
    (setq off   (fit:pget prm 'Ty)
          slope (cond ((fit:pget prm 'st)) (0.0))))
  (+ off (* slope (- x (cond ((fit:pget prm 'xm)) (0.0))))))

;; The body's centreline at X - level on a true pool, tilted on one
;; built wider at one end.
(defun fit:cap-cy (prm x)
  (/ (+ (fit:wall-y prm "b" x) (fit:wall-y prm "t" x)) 2.0))

;; Half the body's width at X.
(defun fit:cap-half (prm x)
  (/ (- (fit:wall-y prm "t" x) (fit:wall-y prm "b" x)) 2.0))

;; A side wall's own least-squares line through the points that chose
;; it, as (base mid slope): its height at MID, and how that height
;; rises with x.
(defun fit:cap-wall (wpts / n sx sy num den mid base p)
  (setq n   (length wpts)
        sx  0.0
        sy  0.0
        num 0.0
        den 0.0)
  (foreach p wpts (setq sx (+ sx (car p)) sy (+ sy (cadr p))))
  (setq mid (/ sx n) base (/ sy n))
  (foreach p wpts
    (setq num (+ num (* (- (car p) mid) (cadr p)))
          den (+ den (* (- (car p) mid) (- (car p) mid)))))
  (list base mid (if (> den 1.0e-9) (/ num den) 0.0)))

;; The angles the two side walls of an arc-ended body may really take.
;; They are not held parallel: a gunite shell slumps as it cures, so
;; one wall very often slants away from the other, and forcing them
;; parallel would push that lean straight back into the points.  Two
;; limits, both fit:*cap-oos-max* (10 degrees): how far one wall may
;; lean, and how far the two may diverge from each other.  Past either
;; the offender is CLAMPED, never zeroed - the points still know which
;; way the wall leans, only how far is in doubt.
(defun fit:cap-slopes (sb st / m ab at dv mid)
  (setq m  fit:*cap-oos-max*
        ab (max (- m) (min m (atan sb)))
        at (max (- m) (min m (atan st)))
        dv (- at ab))
  (if (> (abs dv) m)
    (setq mid (/ (+ ab at) 2.0)
          dv  (if (> dv 0.0) m (- m))
          ab  (- mid (/ dv 2.0))
          at  (+ mid (/ dv 2.0))))
  (list (cal:tan ab) (cal:tan at)))

;; How far off parallel the two side walls came out, in radians.
(defun fit:cap-divergence (prm)
  (- (atan (cond ((fit:pget prm 'st)) (0.0)))
     (atan (cond ((fit:pget prm 'sb)) (0.0)))))

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
;; arc springs meaningfully inside the corners.  CHAIN, when given,
;; replaces the single arc with the run of arcs the points asked for.
;; The end line runs between the side walls AT THIS END, so a pool
;; built wider at one end still closes on both.
(defun fit:cap-verts (re cx r sign prm chain / by ty cy h stub lo hi a1
                                              a2 b out)
  (setq by   (fit:wall-y prm "b" re)
        ty   (fit:wall-y prm "t" re)
        cy   (/ (+ by ty) 2.0)
        h    (fit:endcap-h re cx r by ty)
        stub (> (- (/ (- ty by) 2.0) h) 0.25)
        out  nil)
  (if (> sign 0)
    (progn
      (setq lo (list re (- cy h))
            hi (list re (+ cy h))
            a1 (angle (list cx cy) lo)
            a2 (angle (list cx cy) hi)
            b  (cal:tan (/ (cal:angnorm (- a2 a1)) 4.0)))
      (if stub (setq out (list (list (list re by) 0.0))))
      (setq out (append out (if chain chain (list (list lo b)))))
      (if stub
        (setq out (append out (list (list hi 0.0)
                                    (list (list re ty) 0.0))))
        (setq out (append out (list (list hi 0.0))))))
    (progn
      (setq hi (list re (+ cy h))
            lo (list re (- cy h))
            a1 (angle (list cx cy) hi)
            a2 (angle (list cx cy) lo)
            b  (cal:tan (/ (cal:angnorm (- a2 a1)) 4.0)))
      (if stub (setq out (list (list (list re ty) 0.0))))
      (setq out (append out (if chain chain (list (list hi b)))))
      (if stub
        (setq out (append out (list (list lo 0.0)
                                    (list (list re by) 0.0))))
        (setq out (append out (list (list lo 0.0)))))))
  out)

;; Outline vertex list of the fitted end-capped body, frame coords.
;; BOWS (nil = none) is (bottom top): the two side walls may bow like
;; any other straight wall.  CHAINS (nil = none) is (right left): an
;; end a single radius could not hold, rebuilt as a run of arcs.
(defun fit:endcap-verts (prm kind both bows chains / verts itop ibot
                                                    m a b)
  (setq verts (fit:cap-verts (fit:pget prm 'Re) (fit:pget prm 'cx)
                             (fit:pget prm 'r) 1 prm (car chains))
        itop  (1- (length verts)))        ; the TOP wall leaves here
  (if both
    (setq verts (append verts
                        (fit:cap-verts (fit:pget prm 'Re2)
                                       (fit:pget prm 'cx2)
                                       (fit:pget prm 'r2) -1 prm
                                       (cadr chains))))
    (setq verts (append verts
                        (list (list (list (fit:pget prm 'Lx)
                                          (fit:wall-y prm "t"
                                                      (fit:pget prm 'Lx)))
                                    0.0)
                              (list (list (fit:pget prm 'Lx)
                                          (fit:wall-y prm "b"
                                                      (fit:pget prm 'Lx)))
                                    0.0)))))
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
                                (cal:dist (car (nth (cdr a) verts)) b)
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
              s     (fit:bow-cap (caddr got) (cal:dist a b)))
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
(defun fit:fit-endcap (pts kind both oos / bb x0 y0 x1 y1 w prm r0 yb yt
                                          cy cy1 cy2 byr tyr byl tyl
                                          inband lb lt sl
                                       xr xl bpts tpts lpts a1pts a2pts e1pts
                                       e2pts p darc1 darc2 dbot dtop dlft
                                       dend1 dend2 h1 h2 best bd cand cc
                                       ssum n d q)
  (setq bb (fit:bbox pts)
        x0 (car bb) y0 (cadr bb) x1 (caddr bb) y1 (cadddr bb)
        w  (- y1 y0)
        r0 (if (= kind "Oval") (/ w 2.0) (* 0.6 w))
        prm (list (cons 'By y0) (cons 'Ty y1) (cons 'Lx x0)
                  (cons 'sb 0.0) (cons 'st 0.0)
                  (cons 'xm (/ (+ x0 x1) 2.0))
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
    (setq yb  (fit:pget prm 'By)
          yt  (fit:pget prm 'Ty)
          cy  (/ (+ yb yt) 2.0)
          xr  (fit:pget prm 'Re)
          xl  (if both (fit:pget prm 'Re2) (fit:pget prm 'Lx))
          prm (fit:pput prm 'xm (/ (+ xl xr) 2.0))
          cy1 (fit:cap-cy prm (fit:pget prm 'cx))
          cy2 (if both (fit:cap-cy prm (fit:pget prm 'cx2)) cy)
          byr (fit:wall-y prm "b" xr)
          tyr (fit:wall-y prm "t" xr)
          byl (fit:wall-y prm "b" xl)
          tyl (fit:wall-y prm "t" xl)
          h1  (fit:endcap-h (fit:pget prm 'Re) (fit:pget prm 'cx)
                            (fit:pget prm 'r) byr tyr)
          h2  (if both
                (fit:endcap-h (fit:pget prm 'Re2) (fit:pget prm 'cx2)
                              (fit:pget prm 'r2) byl tyl))
          bpts nil tpts nil lpts nil a1pts nil a2pts nil e1pts nil e2pts nil)
    (foreach p pts
      ;; distance to each feature; a point left of an arc's centre
      ;; falls back to its spring corners so side points never claim it
      (setq inband (and (<= xl (car p)) (<= (car p) xr))
            darc1 (if (< (car p) (fit:pget prm 'cx))
                    (min (cal:dist p (list (fit:pget prm 'Re) byr))
                         (cal:dist p (list (fit:pget prm 'Re) tyr)))
                    (abs (- (cal:dist p (list (fit:pget prm 'cx) cy1))
                            (fit:pget prm 'r))))
            darc2 (if both
                    (if (> (car p) (fit:pget prm 'cx2))
                      (min (cal:dist p (list (fit:pget prm 'Re2) byl))
                           (cal:dist p (list (fit:pget prm 'Re2) tyl)))
                      (abs (- (cal:dist p (list (fit:pget prm 'cx2) cy2))
                              (fit:pget prm 'r2)))))
            dbot  (if inband
                    (abs (- (cadr p) (fit:wall-y prm "b" (car p)))) 1.0e9)
            dtop  (if inband
                    (abs (- (cadr p) (fit:wall-y prm "t" (car p)))) 1.0e9)
            dlft  (if both 1.0e9 (abs (- (car p) (fit:pget prm 'Lx))))
            dend1 (if (> (abs (- (cadr p) cy1)) h1)
                    (abs (- (car p) (fit:pget prm 'Re))) 1.0e9)
            dend2 (if (and both (> (abs (- (cadr p) cy2)) h2))
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
    ;; wall updates: a plain mean while the walls are held parallel,
    ;; two INDEPENDENT lines once the pool may be out of square - the
    ;; swing has to be in here, with the caps refitting against it each
    ;; round, not bolted on after the caps have settled.  Each wall
    ;; answers its own points and neither is tied to the other's
    ;; direction; fit:cap-slopes only says how far either may go.
    (if (not oos)
      (progn
        (if bpts
          (progn
            (setq ssum 0.0)
            (foreach p bpts (setq ssum (+ ssum (cadr p))))
            (setq prm (fit:pput prm 'By (/ ssum (length bpts))))))
        (if tpts
          (progn
            (setq ssum 0.0)
            (foreach p tpts (setq ssum (+ ssum (cadr p))))
            (setq prm (fit:pput prm 'Ty (/ ssum (length tpts)))))))
      (progn
        (setq lb (if bpts (fit:cap-wall bpts))
              lt (if tpts (fit:cap-wall tpts))
              sl (fit:cap-slopes
                   (if lb (caddr lb) (cond ((fit:pget prm 'sb)) (0.0)))
                   (if lt (caddr lt) (cond ((fit:pget prm 'st)) (0.0))))
              prm (fit:pput prm 'sb (car sl))
              prm (fit:pput prm 'st (cadr sl)))
        ;; the offset is the fitted line read at the body's middle, so
        ;; it has to follow the slope the clamp actually allowed
        (if lb
          (setq prm (fit:pput prm 'By
                              (+ (car lb)
                                 (* (car sl) (- (fit:pget prm 'xm)
                                                (cadr lb)))))))
        (if lt
          (setq prm (fit:pput prm 'Ty
                              (+ (car lt)
                                 (* (cadr sl) (- (fit:pget prm 'xm)
                                                 (cadr lt)))))))))
    (if (and lpts (not both))
      (progn
        (setq ssum 0.0)
        (foreach p lpts (setq ssum (+ ssum (car p))))
        (setq prm (fit:pput prm 'Lx (/ ssum (length lpts))))))
    (setq cy1 (fit:cap-cy prm (fit:pget prm 'cx))
          cy2 (if both (fit:cap-cy prm (fit:pget prm 'cx2)) cy1))
    ;; the +x cap
    (if a1pts
      (progn
        (if (= kind "Oval")
          (setq prm (fit:pput prm 'r (fit:cap-half prm (fit:pget prm 'cx))))
          (progn
            (setq ssum 0.0 cc (list (fit:pget prm 'cx) cy1))
            (foreach p a1pts (setq ssum (+ ssum (cal:dist p cc))))
            (setq prm (fit:pput prm 'r (/ ssum (length a1pts))))))
        (setq ssum 0.0 n 0)
        (foreach p a1pts
          (setq d (- (* (fit:pget prm 'r) (fit:pget prm 'r))
                     (* (- (cadr p) cy1) (- (cadr p) cy1))))
          (if (> d 0.0)
            (setq ssum (+ ssum (- (car p) (sqrt d)))
                  n    (1+ n))))
        (if (> n 0) (setq prm (fit:pput prm 'cx (/ ssum n))))))
    (if (= kind "Oval")
      (setq prm (fit:pput prm 'r (fit:cap-half prm (fit:pget prm 'cx)))
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
            (if (= kind "Oval")
              (setq prm (fit:pput prm 'r2
                                  (fit:cap-half prm (fit:pget prm 'cx2))))
              (progn
                (setq ssum 0.0 cc (list (fit:pget prm 'cx2) cy2))
                (foreach p a2pts (setq ssum (+ ssum (cal:dist p cc))))
                (setq prm (fit:pput prm 'r2 (/ ssum (length a2pts))))))
            (setq ssum 0.0 n 0)
            (foreach p a2pts
              (setq d (- (* (fit:pget prm 'r2) (fit:pget prm 'r2))
                         (* (- (cadr p) cy2) (- (cadr p) cy2))))
              (if (> d 0.0)
                (setq ssum (+ ssum (+ (car p) (sqrt d)))
                      n    (1+ n))))
            (if (> n 0) (setq prm (fit:pput prm 'cx2 (/ ssum n))))))
        (if (= kind "Oval")
          (setq prm (fit:pput prm 'r2
                              (fit:cap-half prm (fit:pget prm 'cx2)))
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

;; ---- arcs that are not one arc ---------------------------------------
;;
;; A drawn end is one clean radius.  A built one very often is not: a
;; gunite shell caves in a little as it cures, and a single arc through
;; those points either misses them or lies about them.  So an end that
;; a single arc cannot hold within the distance the user typed is
;; rebuilt as a POLYLINE OF ARCS - each joint sitting on a survey
;; point, so the chain is continuous by construction and every joint is
;; a real measurement.  Extra arcs have to earn their place: the run
;; keeps the fewest that hold the points.  A symmetric cave-in is still
;; a circle and one arc handles it; this is for the ends that slumped
;; to one side.

;; Bulge of the arc P1 -> Q -> P2; 0.0 when degenerate.  ABHD's,
;; unchanged.
(defun fit:bulge-3pt (p1 q p2 / c a1 a2 aq dccw dq)
  (setq p1 (cal:2d p1) q (cal:2d q) p2 (cal:2d p2)
        c  (fit:circumcenter p1 q p2))
  (if (null c)
    0.0
    (progn
      (setq a1   (angle c p1)
            a2   (angle c p2)
            aq   (angle c q)
            dccw (cal:angnorm (- a2 a1))
            dq   (cal:angnorm (- aq a1)))
      (cond
        ((< dccw 1.0e-9) 0.0)
        ((> dccw (- (* 2.0 pi) 1.0e-9)) 0.0)
        ((<= dq dccw) (cal:tan (/ dccw 4.0)))
        (T (- (cal:tan (/ (- (* 2.0 pi) dccw) 4.0))))))))

;; Worst distance from any of QS to the arc (A B bulge).
(defun fit:span-dev (a b bul qs / seg mx d q)
  (setq seg (list a b bul) mx 0.0)
  (foreach q qs
    (setq d (fit:seg-dist q seg))
    (if (> d mx) (setq mx d)))
  mx)

;; The one arc from A to B that best fits QS: the exact 3-point arcs
;; through each point, plus their average, judged on worst deviation.
(defun fit:best-bulge (a b qs / bls sum q bl best bd d)
  (if (null qs)
    0.0
    (progn
      (setq bls (mapcar '(lambda (q) (fit:bulge-3pt a q b)) qs)
            sum 0.0)
      (foreach bl bls (setq sum (+ sum bl)))
      (setq bls (append bls (list (/ sum (length bls))))
            best 0.0 bd nil)
      (foreach bl bls
        (setq d (fit:span-dev a b bl qs))
        (if (or (null bd) (< d bd)) (setq best bl bd d)))
      best)))

;; ---- tangency: ABHD's continuity, on FITABHD's runs -----------------
;; At each joint the next arc's start tangent may differ from the
;; previous arc's end tangent by at most fit:*tang-tol*, so the curve
;; stays smooth while the POINTS still choose inside that window.

;; Tangent direction at the END of the arc A->B: the chord direction
;; plus half the included angle.
(defun fit:end-tangent (a b bul)
  (+ (angle (cal:2d a) (cal:2d b)) (* 2.0 (atan bul))))

;; Tangent direction where the arc A->B leaves A.
(defun fit:start-tangent (a b bul)
  (- (angle (cal:2d a) (cal:2d b)) (* 2.0 (atan bul))))

;; The bulges the span A->B may take if its START tangent is to stay
;; within WF * fit:*tang-tol* of the incoming tangent TE, as (lo . hi).
;; The edges are clamped so U-turn geometry stays finite.
(defun fit:tang-window (te a b wf / tt phi lo hi)
  (setq tt  (* fit:*tang-tol* wf)
        phi (cal:signed-dang te (angle (cal:2d a) (cal:2d b)))
        lo  (cal:tan (max -1.373 (min 1.373 (/ (- phi tt) 2.0))))
        hi  (cal:tan (max -1.373 (min 1.373 (/ (+ phi tt) 2.0)))))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; The bulges the CLOSING span A->B may take if its END tangent is to
;; stay within WF * fit:*tang-tol* of the ring's start tangent TS0.
(defun fit:end-window (ts0 a b wf / tt psi lo hi)
  (setq tt  (* fit:*tang-tol* wf)
        psi (cal:signed-dang (angle (cal:2d a) (cal:2d b)) ts0)
        lo  (cal:tan (max -1.373 (min 1.373 (/ (- psi tt) 2.0))))
        hi  (cal:tan (max -1.373 (min 1.373 (/ (+ psi tt) 2.0)))))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Where two bulge windows overlap; nil when they do not.
(defun fit:isect-win (w1 w2 / lo hi)
  (cond
    ((null w1) w2)
    ((null w2) w1)
    (T (setq lo (max (car w1) (car w2))
             hi (min (cdr w1) (cdr w2)))
       (if (<= lo hi) (cons lo hi)))))

;; BUL held inside the window W.
(defun fit:clamp-bulge (bul w)
  (max (car w) (min (cdr w) bul)))

;; fit:best-bulge, but every candidate held inside the window W - so
;; the arc answers its points as well as it can WITHOUT leaving the
;; joint visibly kinked.
(defun fit:best-bulge-win (a b qs w / bls sum q bl best bd d)
  (cond
    ((null w) (fit:best-bulge a b qs))
    ((null qs) (fit:clamp-bulge 0.0 w))
    (T
     (setq bls (mapcar '(lambda (q) (fit:bulge-3pt a q b)) qs)
           sum 0.0)
     (foreach bl bls (setq sum (+ sum bl)))
     (setq bls  (mapcar '(lambda (bl) (fit:clamp-bulge bl w))
                        (append bls (list (/ sum (length bls)))))
           best (car bls) bd nil)
     (foreach bl bls
       (setq d (fit:span-dev a b bl qs))
       (if (or (null bd) (< d bd)) (setq best bl bd d)))
     best)))

;; The arc that continues the tangent TE smoothly and still answers QS.
;; The window is STRETCHED through fit:*tang-steps* rather than
;; abandoned, and the first stretch whose arc holds the points within
;; TOL wins.  TS0, on the closing span of a ring, also holds the far
;; end to the tangent the ring started with.
(defun fit:smooth-bulge (te a b qs tol ts0 / out done wf w)
  (setq out nil done nil)
  (foreach wf fit:*tang-steps*
    (if (not done)
      (progn
        (setq w (fit:tang-window te a b wf))
        (if ts0 (setq w (fit:isect-win w (fit:end-window ts0 a b wf))))
        (if w
          (progn
            (setq out (fit:best-bulge-win a b qs w))
            (if (<= (fit:span-dev a b out qs) tol) (setq done T)))))))
  (if (null out)                       ; the two ends cannot agree
    (setq out (fit:best-bulge-win
                a b qs (fit:tang-window te a b (last fit:*tang-steps*)))))
  out)

;; The worst joint in a run: how far the next arc's start tangent
;; departs from the previous arc's end tangent, in radians.  CLOSED
;; counts the seam as a joint too.
(defun fit:chain-kink (chain z closed / segs worst n i s1 s2 k)
  (setq segs  (fit:chain-segs chain z)
        n     (length segs)
        worst 0.0
        i     1)
  (while (< i n)
    (setq s1 (nth (1- i) segs)
          s2 (nth i segs)
          k  (abs (cal:signed-dang
                    (fit:end-tangent (car s1) (cadr s1) (caddr s1))
                    (fit:start-tangent (car s2) (cadr s2) (caddr s2)))))
    (if (> k worst) (setq worst k))
    (setq i (1+ i)))
  (if (and closed (> n 1))
    (progn
      (setq s1 (nth (1- n) segs)
            s2 (car segs)
            k  (abs (cal:signed-dang
                      (fit:end-tangent (car s1) (cadr s1) (caddr s1))
                      (fit:start-tangent (car s2) (cadr s2) (caddr s2)))))
      (if (> k worst) (setq worst k))))
  worst)

;; The (p1 p2 bulge) segments of a (point bulge) run ending at Z.
(defun fit:chain-segs (chain z / pts out i n)
  (setq pts (append (mapcar 'car chain) (list z))
        n   (length chain)
        out nil i 0)
  (while (< i n)
    (setq out (cons (list (nth i pts) (nth (1+ i) pts)
                          (cadr (nth i chain)))
                    out)
          i   (1+ i)))
  (reverse out))

;; A run of K arcs from A to Z through the ordered points QS.  The K-1
;; joints are survey points themselves, and every one of them is
;; SMOOTH: the first arc is free, each one after it starts inside the
;; tangency window of the arc before it.
(defun fit:arc-chain (qs a z k tol / n bounds s lo hi start end sub bl te
                                     out)
  (setq n      (length qs)
        bounds (list 0)
        s      1)
  (while (< s k)
    (setq bounds (append bounds (list (/ (* s n) k))) s (1+ s)))
  (setq bounds (append bounds (list n))
        out    nil te nil s 0)
  (while (< s k)
    (setq lo    (nth s bounds)
          hi    (nth (1+ s) bounds)
          start (if (= s 0) a (nth lo qs))
          end   (if (= s (1- k)) z (nth hi qs))
          sub   (cal:sublist qs lo (- hi lo))
          bl    (if te
                  (fit:smooth-bulge te start end sub tol nil)
                  (fit:best-bulge start end sub))
          out   (cons (list start bl) out)
          te    (fit:end-tangent start end bl)
          s     (1+ s)))
  (reverse out))

;; Worst distance from QS to a whole run.
(defun fit:chain-worst (chain z qs / segs mx q s d dmin)
  (setq segs (fit:chain-segs chain z) mx 0.0)
  (foreach q qs
    (setq dmin nil)
    (foreach s segs
      (setq d (fit:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin mx) (setq mx dmin)))
  mx)

;; The run of arcs from A to Z that best answers the ordered points QS.
;; ONE arc if one holds them within TOL - an end that really is one
;; radius stays one radius, and no chain appears.  Once a single arc
;; has failed, though, the run keeps going while each extra arc clearly
;; earns its place: stopping the moment it scrapes inside the tolerance
;; would leave the shell's real shape on the table, and the tangency
;; window is what keeps the result a curve rather than a row of facets.
;; Returns the (point bulge) run from A up to but not including Z.
(defun fit:fit-arc-run (qs a z tol / best worst kmax k trial w done)
  (setq best (list (list a (fit:best-bulge a z qs))))
  (if (null qs)
    best
    (progn
      (setq worst (fit:chain-worst best z qs))
      (if (<= worst tol)
        best                                ; one radius holds them
        (progn
          (setq kmax (max 1 (/ (length qs) fit:*arc-pts-min*))
                k    1
                done nil)
          (while (and (not done) (< k kmax))
            (setq k (1+ k))
            (if (<= worst fit:*on-eps*)
              (setq done T)     ; every point is ON it: nothing left to
              (progn            ; chase but the noise
                (setq trial (fit:arc-chain qs a z k tol)
                      w     (fit:chain-worst trial z qs))
                ;; not a clear enough gain - but a plateau is not the
                ;; end of the curve either, so keep looking
                (if (<= w (* worst fit:*both-edge*))
                  (setq best trial worst w)))))
          best)))))

;; The points sorted along the arc SEG, start to end.
(defun fit:order-along-arc (qs seg / g c a1 ccw keyed q rel)
  (setq g (fit:arc-geom (car seg) (cadr seg) (caddr seg)))
  (if (null g)
    qs
    (progn
      (setq c   (car g)
            a1  (caddr g)
            ccw (> (caddr seg) 0.0)
            keyed nil)
      (foreach q qs
        (setq rel (if ccw
                    (cal:angnorm (- (angle c q) a1))
                    (cal:angnorm (- a1 (angle c q))))
              keyed (cons (cons rel q) keyed)))
      (mapcar 'cdr (fit:sort-asc keyed)))))

;; sort (key . val) pairs ascending by key (insertion sort)
(defun fit:sort-asc (lst / out x)
  (foreach x lst (setq out (fit:ins-asc x out)))
  out)
(defun fit:ins-asc (x lst)
  (cond ((null lst) (list x))
        ((< (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (fit:ins-asc x (cdr lst))))))

;; Index of the piece of SEGS that P is nearest to.
(defun fit:nearest-seg (p segs / best bd i s d)
  (setq best 0 bd nil i 0)
  (foreach s segs
    (setq d (fit:seg-dist p s))
    (if (or (null bd) (< d bd)) (setq best i bd d))
    (setq i (1+ i)))
  best)

;; The points whose nearest piece of the outline is segment I.
(defun fit:arc-seg-points (pts segs i / out p)
  (setq out nil)
  (foreach p pts
    (if (= i (fit:nearest-seg p segs)) (setq out (cons p out))))
  (reverse out))

;; ---- the Round pool --------------------------------------------------

(defun fit:fit-round (pts / cx cy r ssum sx sy p d n)
  (setq n  (length pts) sx 0.0 sy 0.0)
  (foreach p pts (setq sx (+ sx (car p)) sy (+ sy (cadr p))))
  (setq cx (/ sx n) cy (/ sy n))
  (repeat fit:*rad-iters*
    (setq ssum 0.0)
    (foreach p pts (setq ssum (+ ssum (cal:dist p (list cx cy)))))
    (setq r (/ ssum n) sx 0.0 sy 0.0)
    (foreach p pts
      (setq d (cal:dist p (list cx cy)))
      (if (< d 1.0e-9)
        (setq sx (+ sx (car p)) sy (+ sy (cadr p)))
        (setq sx (+ sx (- (car p) (* r (/ (- (car p) cx) d))))
              sy (+ sy (- (cadr p) (* r (/ (- (cadr p) cy) d)))))))
    (setq cx (/ sx n) cy (/ sy n)))
  (list (cons 'cx cx) (cons 'cy cy) (cons 'r r)))

;; the circle as two bulge-1 semicircles, as ABHD draws a CIRCLE - or
;; the run of arcs the points asked for, when it caved in
(defun fit:round-verts (prm chain / c r)
  (if chain
    chain
    (progn
      (setq c (list (fit:pget prm 'cx) (fit:pget prm 'cy))
            r (fit:pget prm 'r))
      (list (list (list (+ (car c) r) (cadr c)) 1.0)
            (list (list (- (car c) r) (cadr c)) 1.0)))))

;; ---- the oasis pools -------------------------------------------------
;; An oasis is arcs and nothing else: a ring of BULGES, each pinned
;; tangent to the envelope it was drawn in, with a JOINER between
;; each consecutive pair - a smaller reverse arc curving back in, or the
;; straight run of a bound the two share.  Every joint is smooth, which
;; is why the whole shape can be given as a handful of radii and two
;; overall dimensions.  OASIS draws one from those numbers; this fits
;; one to a survey, and the geometry below is OASIS's own solver,
;; transcribed under this file's prefix so the standalone build still
;; loads alone.  See lisp/oasis/README.md for what the five families
;; are and why a kidney hands over at a seam.

;; Intersection of circle (c1 r1) with circle (c2 r2).  side 1.0 is the
;; point left of the c1->c2 direction, -1.0 the one right of it.  nil
;; when the two circles never meet.
(defun fit:oas-circint (c1 r1 c2 r2 side / d ux uy a h2 h bx by)
  (setq d (distance c1 c2))
  (if (> d fit:*oas-fuzz*)
    (progn
      (setq ux (/ (- (car c2) (car c1)) d)
            uy (/ (- (cadr c2) (cadr c1)) d)
            a  (/ (+ (* d d) (* r1 r1) (- (* r2 r2))) (* 2.0 d))
            h2 (- (* r1 r1) (* a a)))
      (if (> h2 0.0)
        (progn
          (setq h  (sqrt h2)
                bx (+ (car c1) (* a ux))
                by (+ (cadr c1) (* a uy)))
          (list (+ bx (* side h (- uy)))
                (+ by (* side h ux))))))))

;; The unit normal along which two circles share an external tangent
;; line, on the RIGHT of c1->c2 - the outside of a counter-clockwise
;; ring.  Both tangent points lie along it from their own centre, so a
;; straight run between two bulges is entirely described by it.  nil
;; when one circle contains the other.
(defun fit:oas-extnorm (c1 r1 c2 r2 / d ux uy k q)
  (setq d (distance c1 c2))
  (if (> d fit:*oas-fuzz*)
    (progn
      (setq ux (/ (- (car c2) (car c1)) d)
            uy (/ (- (cadr c2) (cadr c1)) d)
            k  (/ (- r1 r2) d)
            q  (- 1.0 (* k k)))
      (if (> q 0.0)
        (progn
          (setq q (sqrt q))
          (list (+ (* k ux) (* q uy))
                (- (* k uy) (* q ux))))))))

;; Centre of the circle of radius RF externally tangent to both bulges
;; and lying OUTSIDE the pool, so its near side is the reverse curve.
(defun fit:oas-fillet (c1 r1 c2 r2 rf)
  (fit:oas-circint c1 (+ r1 rf) c2 (+ r2 rf) -1.0))

;; The joiner between two consecutive bulges, as
;;   (kind data angle-out angle-in)
;; kind nil for a reverse arc - data its centre - or "LINE" for a
;; straight run, data the outward normal along it.  RF says which: a
;; number is the reverse arc's radius, "SEAM" the internal tangency a
;; kidney hands over at, "LINE" (or nil) the straight run.  nil when the
;; two cannot be joined at all.
(defun fit:oas-joiner (c1 r1 c2 r2 rf / cf m a)
  (cond
    ((and (= (type rf) 'STR) (= rf "SEAM"))
     (setq a (if (> r1 r2) (angle c1 c2) (angle c2 c1)))
     (list "SEAM" nil a a))
    ((or (null rf) (and (= (type rf) 'STR) (= rf "LINE")))
     (setq m (fit:oas-extnorm c1 r1 c2 r2))
     (if m (progn (setq a (atan (cadr m) (car m)))
                  (list "LINE" m a a))))
    (T
     (setq cf (fit:oas-fillet c1 r1 c2 r2 rf))
     (if cf (list nil cf (angle c1 cf) (angle c2 cf))))))

;; T for the two-bulge cloud shapes, and for the kidneys.
(defun fit:oas-cloud-p (v)
  (member v '("StraightBottom" "RoundedBottom")))
(defun fit:oas-kidney-p (v)
  (member v '("TrueKidney" "AsymKidney")))

;; The smallest top-center radius a true kidney can take, and the
;; matching side radius it derives from one past that.
(defun fit:oas-ktrue-min (w h)
  (+ (/ h 2.0) (/ (* w w) (* 8.0 h))))
(defun fit:oas-ktrue-side (w h rt / b c disc r)
  (setq b    (+ w (* 2.0 h) (* -4.0 rt))
        c    (+ (/ (* w w) 4.0) (* (- h rt) (- h rt)) (- (* rt rt)))
        disc (- (* b b) (* 4.0 c)))
  (if (>= disc 0.0)
    (progn
      (setq r (/ (+ b (sqrt disc)) 2.0))
      (if (> r fit:*oas-fuzz*) r))))

;; The asymmetric kidney's top circle: tangent to the Y-max bound and
;; internally tangent to both given sides.  Returns (cx R) or nil.
(defun fit:oas-kidney-top (w h rl rr / sl sr a1 a2 b1 b2 qa qb qc d sd
                                       roots cx rt ty al ar sw best cin)
  (setq sl (float rl)
        sr (- w rr)
        a1 (- h (* 2.0 rl))
        a2 (- h (* 2.0 rr))
        b1 (+ (* sl sl) (* (- h rl) (- h rl)) (- (* rl rl)))
        b2 (+ (* sr sr) (* (- h rr) (- h rr)) (- (* rr rr)))
        qa (- a2 a1)
        qb (* -2.0 (- (* sl a2) (* sr a1)))
        qc (- (* a2 b1) (* a1 b2))
        roots nil)
  (if (< (abs qa) fit:*oas-fuzz*)
    (if (> (abs qb) fit:*oas-fuzz*)
      (setq roots (list (/ (- qc) qb))))
    (progn
      (setq d (- (* qb qb) (* 4.0 qa qc)))
      (if (>= d 0.0)
        (setq sd    (sqrt d)
              roots (list (/ (+ (- qb) sd) (* 2.0 qa))
                          (/ (- (- qb) sd) (* 2.0 qa)))))))
  (setq best nil)
  (foreach cx roots
    (setq rt (cond ((> (abs a1) fit:*oas-fuzz*)
                    (/ (+ (* cx cx) (* -2.0 sl cx) b1) (* 2.0 a1)))
                   ((> (abs a2) fit:*oas-fuzz*)
                    (/ (+ (* cx cx) (* -2.0 sr cx) b2) (* 2.0 a2)))))
    (if (and rt (> rt (+ (max rl rr) fit:*oas-fuzz*)))
      (progn
        (setq ty (- h rt)
              al (angle (list cx ty) (list sl rl))
              ar (angle (list cx ty) (list sr rr))
              sw (cal:angnorm (- al ar)))
        (if (<= (cal:angnorm (- (/ pi 2.0) ar)) sw)
          (progn
            (setq cin (and (<= sl cx) (<= cx sr)))
            (if (or (null best)
                    (and cin (not (caddr best)))
                    (and (eq cin (caddr best))
                         (< (abs (- cx (/ w 2.0)))
                            (abs (- (car best) (/ w 2.0))))))
              (setq best (list cx rt cin))))))))
  (if best (list (car best) (cadr best))))

;; What the ring's elements are called, in the order they run round the
;; pool: bulges at the even positions, joiners at the odd ones.
(defun fit:oas-names (variant)
  (cond
    ((fit:oas-cloud-p variant) '("left" "bottom" "right" "top"))
    ((fit:oas-kidney-p variant)
     '("left" "bottom-center" "right" "right-seam" "top-center"
       "left-seam"))
    ((= variant "NXTcloud")
     '("top-left" "left-bottom" "center-bottom" "right-bottom"
       "right" "right-top" "center-top" "left-top"))
    ((= variant "TopRight")
     '("left" "bottom-center" "right" "right-side" "top-right"
       "top-left"))
    (T '("left" "bottom-center" "right" "top-right" "top" "top-left"))))

;; Where a NXT cloud's three lobes sit - all pinned by the envelope.
(defun fit:oas-nxtcen (w h r which)
  (cond ((= which 0) (list r (- h r)))
        ((= which 1) (list (* 0.5 w) r))
        (T           (list (- w r) (* 0.5 h)))))

;; The outline, counter-clockwise, each element as
;;     (name centre radius start end kind)
;; with the angles in radians.  kind is T for a bulge, nil for a reverse
;; arc, "LINE" for a straight run - on which centre and radius hold the
;; run's two ends instead.  nil when a joiner does not exist.
(defun fit:oas-solve (w h rl rt rr ftl ftr fbc fbr off variant
                      / nm bc br jr kt n i j js2 jj ok jp jn jl jm out)
  (setq nm (fit:oas-names variant) ok T)
  (cond
    ((fit:oas-cloud-p variant)
     (setq rl (* 0.5 h)
           bc (list (list rl rl) (list (- w rr) rr))
           br (list rl rr)
           jr (list (if (= variant "StraightBottom") nil fbc) ftl)))
    ((fit:oas-kidney-p variant)
     (if (= variant "TrueKidney")
       (setq rl (fit:oas-ktrue-side w h rt)
             rr rl
             kt (if rl (list (* 0.5 w) rt)))
       (setq kt (fit:oas-kidney-top w h rl rr)))
     (if (and rl rr kt)
       (setq bc (list (list rl rl) (list (- w rr) rr)
                      (list (car kt) (- h (cadr kt))))
             br (list rl rr (cadr kt))
             jr (list fbc "SEAM" "SEAM"))
       (setq ok nil br '())))
    ((= variant "NXTcloud")
     (setq bc (list (fit:oas-nxtcen w h rl 0) (fit:oas-nxtcen w h rt 1)
                    (fit:oas-nxtcen w h rr 2) (fit:oas-nxtcen w h rt 1))
           br (list rl rt rr rt)
           jr (list fbc fbr ftr ftl)))
    (T
     (setq bc (list (list rl rl) (list (- w rr) rr)
                    (if (= variant "TopRight")
                      (list (- w rt) (- h rt))
                      (list (+ (* w 0.5) (cond (off) (0.0))) (- h rt))))
           br (list rl rr rt)
           jr (list fbc ftr ftl))))
  (setq n (length br) i 0 js2 nil)
  (while (< i n)
    (setq j  (rem (1+ i) n)
          jj (fit:oas-joiner (nth i bc) (nth i br) (nth j bc) (nth j br)
                             (nth i jr)))
    (if jj (setq js2 (cons jj js2)) (setq ok nil))
    (setq i (1+ i)))
  (setq js2 (reverse js2))
  (if ok
    (progn
      (setq i 0 out nil)
      (while (< i n)
        (setq j   (rem (1+ i) n)
              jp  (nth (rem (+ i n -1) n) js2)
              jn  (nth i js2)
              ;; the bulge: from where the joiner before it hands over to
              ;; where the joiner after it picks up.  Those two can be the
              ;; SAME point, and then the bulge is a point on the outline
              ;; rather than an arc of it, with nothing drawn for it
              out (if (> (cal:angnorm (- (nth 2 jn) (nth 3 jp)))
                         fit:*oas-fuzz*)
                    (cons (list (nth (* 2 i) nm) (nth i bc) (nth i br)
                                (nth 3 jp) (nth 2 jn) T)
                          out)
                    out)
              out (cond
                    ;; a seam draws nothing - the two arcs hand straight
                    ;; over at the touch point
                    ((and (= (type (nth 0 jn)) 'STR) (= (nth 0 jn) "SEAM"))
                     out)
                    ((and (= (type (nth 0 jn)) 'STR) (= (nth 0 jn) "LINE"))
                     (setq jl (cal:v+ (nth i bc)
                                      (cal:v* (nth 1 jn) (nth i br)))
                           jm (cal:v+ (nth j bc)
                                      (cal:v* (nth 1 jn) (nth j br))))
                     (if (> (distance jl jm) fit:*oas-fuzz*)
                       (cons (list (nth (1+ (* 2 i)) nm) jl jm
                                   (nth 2 jn) nil "LINE")
                             out)
                       out))
                    ((> (cal:angnorm (- (angle (nth 1 jn) (nth i bc))
                                        (angle (nth 1 jn) (nth j bc))))
                        fit:*oas-fuzz*)
                     (cons (list (nth (1+ (* 2 i)) nm) (nth 1 jn) (nth i jr)
                                 (angle (nth 1 jn) (nth j bc))
                                 (angle (nth 1 jn) (nth i bc))
                                 nil)
                           out))
                    (T out))
              i   (1+ i)))
      (reverse out))))

;; The ring as FITABHD's own closed (point bulge) list, shifted to where
;; the envelope sits in the frame.  A bulge runs with the angle and a
;; reverse arc against it, so the two take opposite bulge signs; a
;; straight run takes none.
(defun fit:oas-ring-verts (arcs x0 y0 / out a sw p)
  (setq out nil)
  (foreach a arcs
    (cond
      ((and (= (type (nth 5 a)) 'STR) (= (nth 5 a) "LINE"))
       (setq out (cons (list (cal:v+ (nth 1 a) (list x0 y0)) 0.0) out)))
      ((nth 5 a)
       (setq sw (cal:angnorm (- (nth 4 a) (nth 3 a)))
             p  (polar (nth 1 a) (nth 3 a) (nth 2 a))
             out (cons (list (cal:v+ p (list x0 y0)) (cal:tan (/ sw 4.0)))
                       out)))
      (T
       (setq sw (cal:angnorm (- (nth 4 a) (nth 3 a)))
             p  (polar (nth 1 a) (nth 4 a) (nth 2 a))
             out (cons (list (cal:v+ p (list x0 y0))
                             (- (cal:tan (/ sw 4.0))))
                       out)))))
  (reverse out))

;; ---- fitting an oasis ------------------------------------------------
;; An oasis has no walls, so nothing FITABHD uses to READ a survey - the
;; edge vote, the nearest-wall ICP, the corner zones - has anything to
;; work on.  What it has instead is an ENVELOPE: every bulge is tangent
;; to a bound, so the pool's bounding box IS the w x h it was drawn in,
;; and once the frame is known the envelope comes free.  So the search
;; is over the frame, and the radii answer to the points inside it.
;;
;; Every joiner is carried not as a radius but as U = h / (h + R), which
;; runs from 0 at an infinite radius to 1 at none.  Two things fall out
;; of that.  A straight run IS the reverse arc with an infinite radius
;; (OASIS's own words), so U = 0 is that run - one parameter, no special
;; case at either end, and a cloud's flat bottom is FOUND rather than
;; declared.  And an even grid in U spreads its samples over the radii a
;; pool actually has: in the radius itself the useful range has no top,
;; and in the curvature every radius past half the pool crowds into the
;; first cell.

;; the U a radius sits at, and the radius a U wants - or the straight
;; run it has flattened into
(defun fit:u-of (r h) (/ h (+ h r)))
(defun fit:oas-rad (u h m)
  (if (<= u (fit:u-of (* fit:*oas-line* m) h))
    "LINE"
    (/ (* h (- 1.0 u)) u)))

;; The parameters this variant fits, in the order they are swept.  What
;; is not here the envelope pins: a cloud's left bulge is tangent to
;; three bounds at once, a kidney's top or its sides are derived from
;; the other, and a NXT cloud's lobes have nowhere to go but their
;; corners.
(defun fit:oas-keys (variant)
  (cond
    ((fit:oas-cloud-p variant)  '(rr utl ubc))
    ((= variant "TrueKidney")   '(rt ubc))
    ((= variant "AsymKidney")   '(rl rr ubc))
    ((= variant "NXTcloud")     '(rl rt rr utl utr ubc ubr))
    ((= variant "TopRight")     '(rl rt rr utl utr ubc))
    (T                          '(rl rt rr off utl utr ubc))))

;; T when the shape cannot say its own mirror image, so the survey has
;; to be tried both ways round.  A Center oasis mirrored is another
;; Center oasis with its two sides swapped, and an asymmetric kidney the
;; same, so those two never need it.
(defun fit:oas-mirror-p (variant)
  (member variant '("TopRight" "StraightBottom" "RoundedBottom"
                    "NXTcloud")))

;; The ring these parameters describe, and its segments.
(defun fit:oas-ring (prm / w h m)
  (setq w (fit:pget prm 'w)
        h (fit:pget prm 'h))
  (if (and w h (> w fit:*oas-fuzz*) (> h fit:*oas-fuzz*))
    (progn
      (setq m (min w h))
      (fit:oas-solve w h (fit:pget prm 'rl) (fit:pget prm 'rt)
                     (fit:pget prm 'rr)
                     (fit:oas-rad (fit:pget prm 'utl) h m)
                     (fit:oas-rad (fit:pget prm 'utr) h m)
                     (fit:oas-rad (fit:pget prm 'ubc) h m)
                     (fit:oas-rad (fit:pget prm 'ubr) h m)
                     (fit:pget prm 'off)
                     (fit:pget prm 'variant)))))

(defun fit:oas-segs (prm / arcs)
  (setq arcs (fit:oas-ring prm))
  (if arcs
    (fit:verts-to-segs (fit:oas-ring-verts arcs (fit:pget prm 'x0)
                                           (fit:pget prm 'y0)))))

;; How far the points sit off the ring these parameters make.  A ring
;; that cannot be built at all scores worse than any that can.
(defun fit:oas-score (fpts prm / segs)
  (setq segs (fit:oas-segs prm))
  (if (or (null segs) (< (length segs) 2))
    fit:*oas-huge*
    (cadr (fit:outline-dev fpts segs))))

;; The envelope re-read off the bounding box - what every change of
;; frame costs, and nothing more.
(defun fit:oas-envelope (fpts prm / bb)
  (setq bb  (fit:bbox fpts)
        prm (fit:pput prm 'x0 (car bb))
        prm (fit:pput prm 'y0 (cadr bb))
        prm (fit:pput prm 'w  (- (caddr bb) (car bb)))
        prm (fit:pput prm 'h  (- (cadddr bb) (cadr bb))))
  prm)

;; The legal range of one parameter, given the rest.
(defun fit:oas-range (prm key / w h m v lo)
  (setq w (fit:pget prm 'w)
        h (fit:pget prm 'h)
        m (min w h)
        v (fit:pget prm key))
  (cond
    ((member key '(utl utr ubc ubr))
     (list 0.0 (fit:u-of (* fit:*oas-rmin* m) h)))
    ((eq key 'off) (list (* -0.45 w) (* 0.45 w)))
    ((member key '(x0 y0))
     (list (- v (* 0.06 m)) (+ v (* 0.06 m))))
    ((member key '(w h))
     (list (max fit:*oas-fuzz* (- v (* 0.06 m))) (+ v (* 0.06 m))))
    ((and (= (fit:pget prm 'variant) "TrueKidney") (eq key 'rt))
     (setq lo (fit:oas-ktrue-min w h))
     (list (* lo 1.0001) (* lo 4.0)))
    ((= (fit:pget prm 'variant) "NXTcloud") (list (* 0.04 m) (* 0.60 m)))
    ((= (fit:pget prm 'variant) "AsymKidney") (list (* 0.04 h) (* 0.60 h)))
    (T (list (* 0.04 h) (* 0.96 h)))))

;; One parameter: a coarse grid over the bracket, then golden section
;; inside it.  The grid is what finds the basin - these objectives are
;; not unimodal, and a golden section alone walks into the nearest ditch.
(defun fit:oas-sweep (fpts prm key lo hi grid gold / best bs step i v s gr
                                                    x1 x2 f1 f2 k)
  (setq best (fit:pget prm key)
        bs   (fit:oas-score fpts prm)
        step (/ (- hi lo) (float grid))
        i    0)
  (while (<= i grid)
    (setq v (+ lo (* step i))
          s (fit:oas-score fpts (fit:pput prm key v)))
    (if (< s bs) (setq bs s best v))
    (setq i (1+ i)))
  (if (<= gold 0)
    (list best bs)
    (progn
      (setq lo (max lo (- best step))
            hi (min hi (+ best step))
            gr 0.6180339887
            x1 (- hi (* gr (- hi lo)))
            x2 (+ lo (* gr (- hi lo)))
            f1 (fit:oas-score fpts (fit:pput prm key x1))
            f2 (fit:oas-score fpts (fit:pput prm key x2))
            k  0)
      (while (< k gold)
        (if (<= f1 f2)
          (setq hi x2 x2 x1 f2 f1                ; shrink from the top
                x1 (- hi (* gr (- hi lo)))
                f1 (fit:oas-score fpts (fit:pput prm key x1)))
          (setq lo x1 x1 x2 f1 f2
                x2 (+ lo (* gr (- hi lo)))
                f2 (fit:oas-score fpts (fit:pput prm key x2))))
        (setq k (1+ k)))
      (setq v (/ (+ lo hi) 2.0)
            s (fit:oas-score fpts (fit:pput prm key v)))
      (if (< s bs) (list v s) (list best bs)))))

;; One pass over a list of parameters.  NARROW nil looks over the whole
;; legal range; a number hunts that share of it either side of where the
;; parameter already sits.
(defun fit:oas-pass (fpts prm keys grid gold narrow / key rg lo hi v span)
  (foreach key keys
    (setq rg (fit:oas-range prm key)
          lo (car rg)
          hi (cadr rg))
    (if narrow
      (setq v    (fit:pget prm key)
            span (* narrow (- hi lo))
            lo   (max lo (- v span))
            hi   (min hi (+ v span))))
    (if (> (- hi lo) 1.0e-9)
      (setq prm (fit:pput prm key
                          (car (fit:oas-sweep fpts prm key lo hi grid
                                              gold))))))
  prm)

;; The envelope from the bounding box, the radii from typical
;; proportions - a place to start, not an answer.
(defun fit:oas-start (fpts variant / prm w h m u)
  (setq prm (fit:oas-envelope fpts (list (cons 'variant variant)
                                         (cons 'off 0.0)))
        w   (fit:pget prm 'w)
        h   (fit:pget prm 'h)
        m   (min w h)
        u   (fit:u-of (* 0.55 h) h)
        prm (fit:pput prm 'rl  (* 0.42 h))
        prm (fit:pput prm 'rt  (* 0.34 h))
        prm (fit:pput prm 'rr  (* 0.42 h))
        prm (fit:pput prm 'utl u)
        prm (fit:pput prm 'utr u)
        prm (fit:pput prm 'ubc u)
        prm (fit:pput prm 'ubr u))
  (cond
    ((= variant "NXTcloud")
     (setq prm (fit:pput prm 'rl (* 0.28 m))
           prm (fit:pput prm 'rt (* 0.28 m))
           prm (fit:pput prm 'rr (* 0.28 m))))
    ((= variant "TrueKidney")
     (setq prm (fit:pput prm 'rt (* 1.35 (fit:oas-ktrue-min w h)))))
    ((= variant "AsymKidney")
     (setq prm (fit:pput prm 'rl (* 0.30 h))
           prm (fit:pput prm 'rr (* 0.30 h)))))
  prm)

;; Every K'th point, so a search pays for the SHAPE of the survey rather
;; than for how many times the crew shot each wall.
(defun fit:oas-thin (pts n / k i out p)
  (if (<= (length pts) n)
    pts
    (progn
      (setq k (cal:ceil (/ (float (length pts)) (float n))) i 0 out nil)
      (foreach p pts
        (if (= 0 (rem i k)) (setq out (cons p out)))
        (setq i (1+ i)))
      (reverse out))))

;; Hunt the frame angle either side of A, re-reading the envelope off
;; each trial's own bounding box.  The shape parameters ride along
;; unchanged: a degree of rotation moves the frame, not the pool.
;; Returns (angle prm framed-points rms).
(defun fit:oas-at-angle (pts prm a mirror / fp p2)
  (setq fp (fit:to-frame pts a mirror)
        p2 (fit:oas-envelope fp prm))
  (list (fit:oas-score fp p2) p2 fp))

(defun fit:oas-angle-step (pts prm a mirror span grid gold
                           / ba bs bp bf lo hi step i t2 got gr x1 x2
                             f1 f2)
  (setq got (fit:oas-at-angle pts prm a mirror)
        ba  a
        bs  (car got)
        bp  (cadr got)
        bf  (caddr got)
        lo  (- a span)
        hi  (+ a span)
        step (/ (- hi lo) (float grid))
        i   0)
  (while (<= i grid)
    (setq t2  (+ lo (* step i))
          got (fit:oas-at-angle pts prm t2 mirror))
    (if (< (car got) bs)
      (setq bs (car got) ba t2 bp (cadr got) bf (caddr got)))
    (setq i (1+ i)))
  (setq lo (- ba step)
        hi (+ ba step)
        gr 0.6180339887
        x1 (- hi (* gr (- hi lo)))
        x2 (+ lo (* gr (- hi lo)))
        f1 (fit:oas-at-angle pts prm x1 mirror)
        f2 (fit:oas-at-angle pts prm x2 mirror)
        i  0)
  (while (< i gold)
    (if (<= (car f1) (car f2))
      (setq hi x2 x2 x1 f2 f1
            x1 (- hi (* gr (- hi lo)))
            f1 (fit:oas-at-angle pts prm x1 mirror))
      (setq lo x1 x1 x2 f1 f2
            x2 (+ lo (* gr (- hi lo)))
            f2 (fit:oas-at-angle pts prm x2 mirror)))
    (setq i (1+ i)))
  (setq t2 (/ (+ lo hi) 2.0) got (fit:oas-at-angle pts prm t2 mirror))
  (if (< (car got) bs)
    (setq bs (car got) ba t2 bp (cadr got) bf (caddr got)))
  (list ba bp bf bs))

;; One placement, fitted properly: the shape, the envelope and the frame
;; angle in turn.  The early rounds run on a thinned survey and the last
;; one puts every point back.
(defun fit:oas-fit-at (pts variant a mirror rounds grid gold
                       / allp fpts prm keys r nw got)
  (setq allp pts
        pts  (fit:oas-thin pts fit:*oas-rough*)
        fpts (fit:to-frame pts a mirror)
        prm  (fit:oas-start fpts variant)
        keys (fit:oas-keys variant)
        r    0)
  (while (< r rounds)
    (if (= r (1- rounds))
      (setq pts allp fpts (fit:to-frame pts a mirror)))
    (setq nw  (nth (min r (1- (length fit:*oas-narrow*))) fit:*oas-narrow*)
          prm (fit:oas-pass fpts prm keys grid gold nw)
          prm (fit:oas-pass fpts prm '(x0 y0 w h) 4 gold nil)
          got (fit:oas-angle-step pts prm a mirror
                                  (/ fit:*oas-aspan* (float (1+ r))) 6 gold)
          a    (car got)
          prm  (cadr got)
          fpts (caddr got)
          r    (1+ r)))
  (setq prm (fit:oas-pass fpts prm keys grid gold 0.12)
        prm (fit:oas-pass fpts prm '(x0 y0 w h) 4 gold nil))
  (list prm a (fit:oas-score fpts prm)))

;; The best N coarse placements that sit in DIFFERENT basins.  Three
;; tries all within a few degrees of each other are one try.
(defun fit:oas-spread (cands n / out c hit o)
  (setq out nil)
  (foreach c cands
    (if (< (length out) n)
      (progn
        (setq hit nil)
        (foreach o out
          (if (and (eq (caddr o) (caddr c))
                   (< (abs (cal:signed-dang (cadr o) (cadr c)))
                      fit:*oas-apart*))
            (setq hit T)))
        (if (not hit) (setq out (cons c out))))))
  (reverse out))

;; sort (score angle mirror) triples ascending by score (insertion sort)
(defun fit:oas-sort (lst / out x)
  (foreach x lst (setq out (fit:oas-ins x out)))
  out)
(defun fit:oas-ins (x lst)
  (cond ((null lst) (list x))
        ((< (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (fit:oas-ins x (cdr lst))))))

;; Which rings a family can come out as.  A cloud's flat bottom is not
;; one of them: it is the rounded bottom whose radius came out infinite,
;; and the fit finds that on its own.
(defun fit:oas-variants (family)
  (cond ((= family "CLoud")  '("RoundedBottom"))
        ((= family "Kidney") '("TrueKidney" "AsymKidney"))
        (T (list family))))

;; T when variant A has more freedom than variant B.
(defun fit:oas-freer (a b)
  (> (length (fit:oas-keys a)) (length (fit:oas-keys b))))

;; Every placement the family allows; the one that hugs the points wins.
;; Where a family comes two ways the two compete, and the freer one only
;; wins by a clear margin - extra freedom is not evidence.
(defun fit:fit-oasis (pts family / qs best variant cands k a mirror fq prm
                                   got rms edge n mirrors c)
  (setq qs   (fit:oas-thin pts fit:*oas-coarse*)
        best nil)
  (foreach variant (fit:oas-variants family)
    (setq cands   nil
          n       (cal:ceil (/ (* 2.0 pi) fit:*oas-astep*))
          mirrors (if (fit:oas-mirror-p variant) '(nil T) '(nil))
          k       0)
    (while (< k n)
      (setq a (* k fit:*oas-astep*))
      (foreach mirror mirrors
        ;; the JOINERS are in the coarse pass, not just the bulges: a
        ;; placement ranked on its bulges alone puts the pool's own
        ;; rotation outside the tries about as often as inside them
        (setq fq    (fit:to-frame qs a mirror)
              prm   (fit:oas-pass fq (fit:oas-start fq variant)
                                  (fit:oas-keys variant) 3 0 nil)
              cands (cons (list (fit:oas-score fq prm) a mirror) cands)))
      (setq k (1+ k)))
    (foreach c (fit:oas-spread (fit:oas-sort (reverse cands))
                               fit:*oas-tries*)
      (setq got  (fit:oas-fit-at pts variant (cadr c) (caddr c)
                                 fit:*oas-rounds* fit:*oas-grid*
                                 fit:*oas-gold*)
            prm  (car got)
            a    (cadr got)
            rms  (caddr got)
            edge (if (and best
                          (fit:oas-freer variant
                                         (fit:pget (car best) 'variant)))
                   fit:*oas-edge*
                   1.0))
      (if (or (null best) (< rms (* (cadr best) edge)))
        (setq best (list prm rms a (caddr c))))))
  best)

;; The whole result for an oasis survey, in FITABHD's own shape.
(defun fit:oas-result (pts family / got prm)
  (setq got (fit:fit-oasis pts family))
  (if got
    (progn
      (setq prm (car got))
      (list (cons 'kind 'oasis) (cons 'type "OAsis") (cons 'fam family)
            (cons 'prm prm) (cons 'angle (caddr got))
            (cons 'mirror (cadddr got)) (cons 'valid T) (cons 'bows nil)
            (cons 'rms (cadr got))
            (cons 'verts (fit:oas-ring-verts (fit:oas-ring prm)
                                             (fit:pget prm 'x0)
                                             (fit:pget prm 'y0)))))))

;; T when a joiner came out flat enough to be drawn as a straight run.
(defun fit:oas-line-p (prm key / h)
  (setq h (fit:pget prm 'h))
  (= (type (fit:oas-rad (fit:pget prm key) h
                        (min (fit:pget prm 'w) h)))
     'STR))

;; How the fitted shape is named in the report - OASIS's own words, with
;; the cloud's bottom read off the fit rather than declared.
(defun fit:oas-label (prm / v)
  (setq v (fit:pget prm 'variant))
  (cond ((= v "TopRight")   "top-right-bulge")
        ((= v "NXTcloud")   "NXT cloud")
        ((= v "TrueKidney") "true kidney")
        ((= v "AsymKidney") "asymmetric kidney")
        ((fit:oas-cloud-p v)
         (if (fit:oas-line-p prm 'ubc)
           "straight-bottom cloud"
           "rounded-bottom cloud"))
        (T "center-bulge")))

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

(defun fit:cap-result (ptype fpts both oos / prm)
  (setq prm (fit:fit-endcap fpts ptype both oos))
  (list (cons 'kind 'cap) (cons 'type ptype) (cons 'prm prm)
        (cons 'both both) (cons 'valid T) (cons 'bows nil)
        (cons 'chains nil)
        (cons 'verts (fit:endcap-verts prm ptype both nil nil))))

(defun fit:fit-config (ptype fpts treat both oos)
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
    (T (fit:cap-result ptype fpts both oos))))

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
;; ---- fitting the frame angle of an arc-ended body --------------------
;; The frame is the body's own axis, and the edge vote cannot find it
;; once the two side walls lean by different amounts: every edge pulls
;; the vote towards its own direction, so the axis lands between the
;; walls and the flat end is drawn crooked.  The walls do not care -
;; each carries its own slope - but the end does, so the angle is
;; fitted too, and kept only if it beats the voted one.

;; One trial: the fit at angle A, as (rms res worst).
(defun fit:cap-at (dpts ptype treat both mirror a / fpts res dev)
  (setq fpts (fit:to-frame dpts a mirror)
        res  (fit:fit-config ptype fpts treat both T)
        dev  (fit:outline-dev fpts (fit:res-fsegs res)))
  (list (cadr dev) res (car dev)))

;; A one-degree sweep to find the basin, then golden section inside it.
(defun fit:refine-cap-angle (dpts ptype treat best / both mirror step n k
                                   a ba got bgot gr lo hi x1 x2 f1 f2 i)
  (setq both   (fit:rget best 'both)
        mirror (fit:rget best 'mirror)
        step   (/ pi 180.0)
        n      (fix (+ 0.5 (/ fit:*cap-oos-max* step)))
        ba     (fit:rget best 'angle)
        bgot   (fit:cap-at dpts ptype treat both mirror ba)
        k      (- n))
  (while (<= k n)
    (if (/= k 0)
      (progn
        (setq a   (+ (fit:rget best 'angle) (* k step))
              got (fit:cap-at dpts ptype treat both mirror a))
        (if (< (car got) (car bgot)) (setq ba a bgot got))))
    (setq k (1+ k)))
  (setq gr 0.6180339887
        lo (- ba step)
        hi (+ ba step)
        x1 (- hi (* gr (- hi lo)))
        x2 (+ lo (* gr (- hi lo)))
        f1 (fit:cap-at dpts ptype treat both mirror x1)
        f2 (fit:cap-at dpts ptype treat both mirror x2)
        i  0)
  (while (< i 16)
    (if (<= (car f1) (car f2))
      (setq hi x2                      ; shrink from the top
            x2 x1
            f2 f1
            x1 (- hi (* gr (- hi lo)))
            f1 (fit:cap-at dpts ptype treat both mirror x1))
      (setq lo x1 x1 x2 f1 f2
            x2 (+ lo (* gr (- hi lo)))
            f2 (fit:cap-at dpts ptype treat both mirror x2)))
    (setq i (1+ i)))
  (setq a   (/ (+ lo hi) 2.0)
        got (fit:cap-at dpts ptype treat both mirror a))
  (if (>= (car got) (car bgot)) (setq a ba got bgot))
  (if (>= (car got) (fit:rget best 'rms))
    best
    (progn
      (setq best (cadr got)
            best (fit:rput best 'angle a)
            best (fit:rput best 'mirror mirror)
            best (fit:rput best 'worst (caddr got))
            best (fit:rput best 'rms (car got)))
      best)))

(defun fit:fit-type (pts ptype treat oos / dpts prm tour a0 best cfg a fpts
                                       res dev worst rms edge)
  (setq dpts (cal:dedupe pts fit:*exact-eps*))
  (if (= ptype "OAsis")
    ;; an oasis has no walls, so TREAT carries what step 2 asked for
    ;; instead: which of OASIS's five families the survey is
    (fit:oas-result dpts treat)
  (if (= ptype "ROUnd")
    (progn
      (setq prm (fit:fit-round dpts))
      (list (cons 'kind 'round) (cons 'type ptype) (cons 'prm prm)
            (cons 'angle 0.0) (cons 'mirror nil) (cons 'valid T)
            (cons 'chain nil)
            (cons 'verts (fit:round-verts prm nil))))
    (progn
      (setq tour (fit:order-points dpts)
            a0   (fit:frame-angle tour (if (= ptype "LAzyl") 8 4))
            best nil)
      (foreach cfg (fit:configs-for ptype)
        (setq a    (+ a0 (car cfg))
              fpts (fit:to-frame dpts a (cadr cfg))
              res  (fit:fit-config ptype fpts treat (caddr cfg) oos))
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
                res  (fit:fit-config ptype fpts treat nil oos)
                dev  (fit:outline-dev fpts (fit:res-fsegs res))
                res  (fit:rput res 'angle a)
                res  (fit:rput res 'mirror nil)
                res  (fit:rput res 'worst (car dev))
                res  (fit:rput res 'rms (cadr dev))
                best res)))
      ;; an arc-ended body whose walls lean unequally needs its frame
      ;; angle fitted as well, or the flat end comes out crooked
      (if (and oos best (eq (fit:rget best 'kind) 'cap))
        (setq best (fit:refine-cap-angle dpts ptype treat best)))
      best))))

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
    ((= t2 "OAsis")
     (cons 'LEN (cons 'WID (fit:oas-dimkeys (fit:rget res 'prm)))))
    (T nil)))

;; An oasis's headline dimensions are its envelope and then every radius
;; the fitted shape actually has - which is the shape's own parameter
;; list, read back.  A joiner that came out as a straight run has no
;; radius to snap, and drops out here.
(defun fit:oas-dimkeys (prm / out key)
  (setq out nil)
  (foreach key (fit:oas-keys (fit:pget prm 'variant))
    (if (and (fit:oas-dimkey key)
             (or (not (member key '(utl utr ubc ubr)))
                 (not (fit:oas-line-p prm key))))
      (setq out (cons (fit:oas-dimkey key) out))))
  (reverse out))

;; the dimension name of one oasis parameter, and back again
(defun fit:oas-dimkey (key)
  (cdr (assoc key '((rl . RL) (rt . RT) (rr . RR) (utl . FTL)
                    (utr . FTR) (ubc . FBC) (ubr . FBR)))))
(defun fit:oas-key (dim)
  (cdr (assoc dim '((RL . rl) (RT . rt) (RR . rr) (FTL . utl)
                    (FTR . utr) (FBC . ubc) (FBR . ubr)))))

(defun fit:get-dim (res key / t2 offs prm d)
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
    ((eq (fit:rget res 'kind) 'oasis)
     (setq prm (fit:rget res 'prm))
     (cond
       ((eq key 'LEN) (fit:pget prm 'w))
       ((eq key 'WID) (fit:pget prm 'h))
       ((member (fit:oas-key key) '(utl utr ubc ubr))
        ;; a joiner is carried as its U, and a straight run has no
        ;; radius to offer at all
        (setq d (fit:oas-rad (fit:pget prm (fit:oas-key key))
                             (fit:pget prm 'h)
                             (min (fit:pget prm 'w) (fit:pget prm 'h))))
        (if (= (type d) 'REAL) d))
       ((fit:oas-key key)                  ; a bulge radius is itself
        (fit:pget prm (fit:oas-key key)))))
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
                                 (fit:rget res 'bows)
                                 (fit:rget res 'chains))))
    ((eq (fit:rget res 'kind) 'oasis)
     ;; the envelope keeps its centre, so a snapped length grows each
     ;; way; a radius is just itself, carried back into the U the ring
     ;; is parameterised on
     (setq prm (fit:rget res 'prm))
     (cond
       ((eq key 'LEN)
        (setq d   (- v (fit:pget prm 'w))
              prm (fit:pput prm 'w v)
              prm (fit:pput prm 'x0 (- (fit:pget prm 'x0) (/ d 2.0)))))
       ((eq key 'WID)
        (setq d   (- v (fit:pget prm 'h))
              prm (fit:pput prm 'h v)
              prm (fit:pput prm 'y0 (- (fit:pget prm 'y0) (/ d 2.0)))))
       ((member (fit:oas-key key) '(utl utr ubc ubr))
        (setq prm (fit:pput prm (fit:oas-key key)
                            (fit:u-of v (fit:pget prm 'h)))))
       ((fit:oas-key key)
        (setq prm (fit:pput prm (fit:oas-key key) v))))
     (setq res (fit:rput res 'prm prm))
     (fit:rput res 'verts
               (fit:oas-ring-verts (fit:oas-ring prm) (fit:pget prm 'x0)
                                   (fit:pget prm 'y0))))
    (T
     (setq prm (fit:pput (fit:rget res 'prm) 'r v)
           res (fit:rput res 'prm prm))
     (fit:rput res 'verts (fit:round-verts prm
                                            (fit:rget res 'chain))))))

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
        (setq feature (member key '(SIZE VSIZE CUT RAD RL RT RR
                                    FTL FTR FBC FBR))
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
                          after (if (fit:rget trial 'verts)
                                  (fit:outline-dists
                                    fpts (fit:res-fsegs trial))))
                    (if (and after
                             (fit:snap-ok before after tol allow feature))
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
     (+ (* 1.2 (fit:rget res 'vsize) (cal:tan (/ pi 8.0)))
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
       (if (> (abs (cal:signed-dang (car a) (car b))) 1.0e-9)
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
     ;; the SWING of these walls is fitted inside fit:fit-endcap, with
     ;; the caps answering to it each round; only the bow is left to do
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
                                     (fit:rget res 'both) bows
                                     (fit:rget res 'chains))))))
    (T res)))                             ; a round pool has no walls

;; T when any wall of BOWS came out bowed.
(defun fit:any-bow (bows / found b)
  (foreach b bows
    (if (and b (not (equal b 0.0 1.0e-12))) (setq found T)))
  found)

;; Rebuild any arc a single radius cannot hold as a run of arcs
;; through the points.  This runs LAST, after the dimensions are
;; settled: a chain changes no dimension, it just stops the outline
;; lying about where the shell actually went.  The joints sit on
;; survey points and stay inside the tangency window, so the run is
;; both a real measurement and a smooth curve.

;; The whole outline of a Round pool as one closed run of K arcs, the
;; joints spaced evenly round the (already rotated) survey.
(defun fit:round-chain-of (qs n k tol / trial i lo hi a nxt sub bl te
                                       ts0)
  (setq trial nil i 0)
  (while (< i k)
    (setq trial (cons (list (nth (/ (* i n) k) qs) 0.0) trial)
          i     (1+ i)))
  (setq trial (reverse trial) i 0 te nil ts0 nil)
  (while (< i k)
    (setq lo  (/ (* i n) k)
          hi  (if (= i (1- k)) n (/ (* (1+ i) n) k))
          a   (car (nth i trial))
          nxt (car (nth (rem (1+ i) k) trial))
          sub (cal:sublist qs lo (- hi lo)))
    (if (null te)
      (setq bl  (fit:best-bulge a nxt sub)
            ts0 (fit:start-tangent a nxt bl))
      (setq bl (fit:smooth-bulge te a nxt sub tol
                                 (if (= i (1- k)) ts0))))
    (setq trial (fit:setnth trial i (list a bl))
          te    (fit:end-tangent a nxt bl)
          i     (1+ i)))
  trial)

(defun fit:round-chain (res fpts segs tol / qs n c keyed q best worst
                                           kmax k trial w done tw tc off)
  (setq qs (mapcar 'cal:2d fpts) n (length qs))
  (if (< n (* 2 fit:*arc-pts-min*))
    res
    (progn
      (setq c     (list (fit:pget (fit:rget res 'prm) 'cx)
                        (fit:pget (fit:rget res 'prm) 'cy))
            keyed nil)
      (foreach q qs (setq keyed (cons (cons (angle c q) q) keyed)))
      (setq qs    (mapcar 'cdr (fit:sort-asc keyed))
            worst (fit:outline-worst qs segs)
            best  nil
            kmax  (/ n fit:*arc-pts-min*)
            k     2
            done  nil)
      ;; the ring only STARTS breaking up when one circle misses; from
      ;; there it keeps going while each extra arc earns its place,
      ;; exactly as an end cap's run does
      (if (<= worst tol) (setq done T))
      (while (and (not done) (< k kmax))
        (setq k  (1+ k)
              tw nil tc nil)
        (if (<= worst fit:*on-eps*)
          (setq done T)                     ; every point is ON it
          (progn
            ;; a closed ring has no natural first joint, and where the
            ;; joints land decides how well they bracket the cave-in,
            ;; so try the aligned run and one shifted half a span
            (foreach off (list 0 (/ n (* 2 k)))
              (setq trial (fit:round-chain-of
                            (append (cal:sublist qs off (- n off))
                                    (cal:sublist qs 0 off))
                            n k tol)
                    w     (fit:chain-worst trial (car (car trial)) qs))
              (if (or (null tw) (< w tw)) (setq tw w tc trial)))
            (if (<= tw (* worst fit:*both-edge*))
              (setq best tc worst tw)))))
      (if (null best)
        res
        (progn
          (setq res (fit:rput res 'chain best)
                res (fit:rput res 'kink
                              (fit:chain-kink best (car (car best)) T)))
          (fit:rput res 'verts
                    (fit:round-verts (fit:rget res 'prm) best)))))))

(defun fit:cap-chains (res fpts segs bulged tol / chains kinks side i s
                                                 qs run)
  (setq chains (list nil nil) kinks (list 0.0 0.0) side 0)
  (foreach i bulged
    (if (< side 2)
      (progn
        (setq s  (nth i segs)
              qs (fit:order-along-arc (fit:arc-seg-points fpts segs i) s))
        (if (>= (length qs) (* 2 fit:*arc-pts-min*))
          (progn
            (setq run (fit:fit-arc-run qs (car s) (cadr s) tol))
            (if (> (length run) 1)
              (setq chains (fit:setnth chains side run)
                    kinks  (fit:setnth kinks side
                                       (fit:chain-kink run (cadr s) nil))))))
        (setq side (1+ side)))))
  (if (or (car chains) (cadr chains))
    (progn
      (setq res (fit:rput res 'chains chains)
            res (fit:rput res 'kinks kinks))
      (fit:rput res 'verts
                (fit:endcap-verts (fit:rget res 'prm)
                                  (fit:rget res 'type)
                                  (fit:rget res 'both)
                                  (fit:rget res 'bows) chains)))
    res))

;; ---- the same rule on a polygon's own curves -------------------------
;; A corner fillet and a bowed wall are drawn as ONE arc for the same
;; reason an oval's end is: that is how the shape is described, not how
;; it was built.  Anything the outline draws as a single R may become a
;; run of arcs under exactly the rules the ends follow - it only starts
;; when one arc cannot hold the points within the typed tolerance, the
;; joints sit on survey points, every joint stays inside the tangency
;; window, each extra arc has to earn its place, and a curve carrying N
;; points may become at most N/3 arcs.  A straight wall has no bulge to
;; break up, so nothing happens to one.

;; Which vert each wall leaves from, and which vert each corner's own
;; curve starts at - the same walk fit:build-polygon does, so a run can
;; say WHICH corner or wall it rebuilt.  Returns (leaves starts).
(defun fit:poly-vert-map (dirs offs treat size which / corners n leaves
                                                      starts i cf k m)
  (setq corners (fit:poly-corners dirs offs)
        n       (length corners)
        leaves  nil
        starts  nil
        k       0
        i       0)
  (while (< i n)
    (setq cf (fit:corner-frame dirs i)
          m  (if which
               (length (fit:corner-verts
                         (nth (rem (+ i n -1) n) corners)
                         (nth i corners)
                         (nth (rem (1+ i) n) corners)
                         (car cf) treat size))
               1)
          starts (cons k starts)             ; the corner's own curve
          k      (+ k m)
          leaves (cons (1- k) leaves)        ; wall i leaves here
          i      (1+ i)))
  (list (reverse leaves) (reverse starts)))

;; Splice the run RUN in for vert K: the run's arcs replace the single
;; one, and every vert after it shifts along.
(defun fit:splice-run (verts k run / out i n v)
  (setq out nil i 0 n (length verts))
  (while (< i n)
    (if (= i k)
      (foreach v run (setq out (cons v out)))
      (setq out (cons (nth i verts) out)))
    (setq i (1+ i)))
  (reverse out))

;; Rebuild every curve of a polygon outline that one arc cannot hold.
;; Works back to front so an earlier splice cannot move a later index.
(defun fit:poly-chains (res fpts segs bulged tol / verts map leaves
                                                  starts runs k s qs run
                                                  nm j rest)
  (setq verts (fit:rget res 'verts)
        map   (fit:poly-vert-map (fit:rget res 'dirs) (fit:rget res 'offs)
                                 (fit:rget res 'treat)
                                 (if (= 8 (length (fit:rget res 'offs)))
                                   (fit:rget res 'vsize)
                                   (fit:rget res 'size))
                                 (fit:rget res 'which))
        leaves (car map)
        starts (cadr map)
        runs   nil)
  (foreach k (reverse bulged)
    (setq s  (nth k segs)
          qs (fit:order-along-arc (fit:arc-seg-points fpts segs k) s))
    (if (>= (length qs) (* 2 fit:*arc-pts-min*))
      (progn
        (setq run (fit:fit-arc-run qs (car s) (cadr s) tol))
        (if (> (length run) 1)
          (progn
            ;; name it before the splice moves anything
            (setq j  (fit:index-of k leaves)
                  nm (if j
                       (cons 'wall j)
                       (cons 'corner (fit:index-of k starts))))
            (setq runs (cons (list nm (length run)
                                   (fit:chain-kink run (cadr s) nil)
                                   (fit:chain-segs run (cadr s)))
                             runs)
                  verts (fit:splice-run verts k run)))))))
  (if (null runs)
    res
    (progn
      (setq res (fit:rput res 'runs runs))
      (fit:rput res 'verts verts))))

;; Where VAL sits in LST, or nil.
(defun fit:index-of (val lst / i out x)
  (setq i 0)
  (foreach x lst
    (if (and (null out) (= x val)) (setq out i))
    (setq i (1+ i)))
  out)

(defun fit:apply-arc-chains (res fpts tol / segs bulged i s)
  (if (not (member (fit:rget res 'kind) '(cap round poly)))
    res
    (progn
      (setq segs (fit:res-fsegs res) bulged nil i 0)
      (foreach s segs
        (if (> (abs (caddr s)) 1.0e-9) (setq bulged (cons i bulged)))
        (setq i (1+ i)))
      (setq bulged (reverse bulged))
      (cond
        ((null bulged) res)
        ((eq (fit:rget res 'kind) 'round)
         (fit:round-chain res fpts segs tol))
        ((eq (fit:rget res 'kind) 'poly)
         (fit:poly-chains res fpts segs bulged tol))
        (T (fit:cap-chains res fpts segs bulged tol))))))

;; worst distance from QS to a whole outline
(defun fit:outline-worst (qs segs / mx q s d dmin)
  (setq mx 0.0)
  (foreach q qs
    (setq dmin nil)
    (foreach s segs
      (setq d (fit:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin mx) (setq mx dmin)))
  mx)

;; The whole engine: configuration search, the bow refinement when the
;; walls may be bowed, then nice-dim snapping against the share of the
;; points the user allows beyond the distance, then the final figures.  The outline stays in frame
;; coordinates under 'verts; fit:res-world-verts carries it out.
(defun fit:fit-and-snap (pts ptype treat tol pct oos bowed / dpts allow
                                                            res fpts dev)
  (setq dpts  (cal:dedupe pts fit:*exact-eps*)
        allow (cal:ceil (* pct (length dpts)))
        res   (fit:fit-type dpts ptype treat oos))
  (if (eq (fit:rget res 'kind) 'round)
    (setq fpts dpts)
    (setq fpts (fit:to-frame dpts (fit:rget res 'angle)
                             (fit:rget res 'mirror))))
  (if (or oos bowed)
    (setq res (fit:apply-refinement res fpts oos bowed)))
  (setq res (fit:snap-result res fpts tol allow)
        res (fit:apply-arc-chains res fpts tol)
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
  (cal:ensure-layer fit:*pool-layer* 4)
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
  (setq m (if pdl pdl (cal:mid pa pb)))
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
    (if (and (null nm) (< (cal:dist (car p) q) fit:*exact-eps*))
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
       (fit:add-point (cal:2d (cdr (assoc 10 ed)))
                      (cal:block-number en fit:*pt-tag*)))
      ((and (= lay (strcase fit:*point-layer*)) (= typ "POINT"))
       (fit:add-point (cal:2d (cdr (assoc 10 ed))) nil))
      ((and (= typ "INSERT") (= lay (strcase fit:*point-layer*)))
       (fit:add-point (cal:2d (cdr (assoc 10 ed))
                      )
                      (cal:block-number en fit:*pt-tag*)))
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
                                 (fit:ftin (cal:dist
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
    ((eq (fit:rget res 'kind) 'oasis)
     (setq out (fit:oas-lines res)))
    (T
     (setq out (list (cons "Diameter"
                           (fit:ftin (* 2.0 (fit:pget
                                              (fit:rget res 'prm) 'r))))))))
  (reverse out))

;; The lines an oasis fit needs: which of the five families it came out
;; as, the envelope it sits in, and then every radius the ring actually
;; has - a joiner that flattened out named as the straight run it is,
;; because that is what will be drawn.
(defun fit:oas-lines (res / prm out key nm v)
  (setq prm (fit:rget res 'prm)
        ;; "X bound" and "Y bound" are what OASIS calls these, and an
        ;; oasis has no length or width the way a rectangle does
        out (list (cons "Y bound" (fit:ftin (fit:pget prm 'h)))
                  (cons "X bound" (fit:ftin (fit:pget prm 'w)))
                  (cons "Oasis shape" (fit:oas-label prm))))
  (foreach key (fit:oas-keys (fit:pget prm 'variant))
    (setq nm (fit:oas-name key (fit:pget prm 'variant)))
    (cond
      ((null nm))
      ((eq key 'off)
       ;; the hump is centred unless the points put it somewhere else
       (setq v (fit:pget prm 'off))
       (if (> (abs v) 1.0)
         (setq out (cons (cons nm (strcat (fit:ftin (abs v))
                                          (if (< v 0.0) " left of centre"
                                            " right of centre")))
                         out))))
      ;; a JOINER is carried as its U, and may have flattened out
      ((member key '(utl utr ubc ubr))
       (setq out (cons (cons nm (if (fit:oas-line-p prm key)
                                  "straight run"
                                  (fit:ftin
                                    (fit:oas-rad
                                      (fit:pget prm key)
                                      (fit:pget prm 'h)
                                      (min (fit:pget prm 'w)
                                           (fit:pget prm 'h))))))
                       out)))
      ;; a bulge radius is itself
      (T (setq out (cons (cons nm (fit:ftin (fit:pget prm key))) out)))))
  out)                                  ; fit:dims-lines reverses this

;; What one oasis parameter is called on the sheet - OASIS's own
;; question wording, which follows the shape because "top-right" is the
;; joiner on one family and the bulge itself on another.
(defun fit:oas-name (key variant)
  (cond
    ((fit:oas-cloud-p variant)
     (cdr (assoc key '((rr . "Right bulge radius")
                       (utl . "Top tangent radius")
                       (ubc . "Bottom radius")))))
    ((= variant "NXTcloud")
     (cdr (assoc key '((rl . "Top-left lobe radius")
                       (rt . "Center lobe radius")
                       (rr . "Right lobe radius")
                       (ubc . "Left-bottom tangent radius")
                       (ubr . "Right-bottom tangent radius")
                       (utr . "Right-top tangent radius")
                       (utl . "Left-top tangent radius")))))
    ((fit:oas-kidney-p variant)
     (cdr (assoc key '((rl . "Left bulge radius")
                       (rt . "Top-center radius")
                       (rr . "Right bulge radius")
                       (ubc . "Bottom-center tangent radius")))))
    (T
     (cdr (assoc key
                 (list (cons 'rl "Left bulge radius")
                       (cons 'rt (if (= variant "TopRight")
                                   "Top-right bulge radius"
                                   "Top bulge radius"))
                       (cons 'rr "Right bulge radius")
                       (cons 'utl "Top-left tangent radius")
                       (cons 'utr (if (= variant "TopRight")
                                    "Right-side tangent radius"
                                    "Top-right tangent radius"))
                       (cons 'ubc "Bottom-center tangent radius")
                       (cons 'off "Top bulge off centre")))))))

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
                               names prm xl xr)
  (if (eq (fit:rget res 'kind) 'cap)
    (progn
      (setq prm (fit:rget res 'prm)
            xr  (fit:pget prm 'Re)
            xl  (if (fit:rget res 'both)
                  (fit:pget prm 'Re2)
                  (fit:pget prm 'Lx)))
      (if (< (abs (- (fit:cap-half prm xr) (fit:cap-half prm xl))) 0.25)
        nil
        (list (cons "Width at one end"
                    (fit:ftin (* 2.0 (fit:cap-half prm xr))))
              (cons "Width at the other"
                    (fit:ftin (* 2.0 (fit:cap-half prm xl))))
              (cons "Out of square by"
                    (strcat (fit:ftin (abs (* 2.0
                                              (- (fit:cap-half prm xr)
                                                 (fit:cap-half prm xl)))))
                            " wider at one end"))
              (cons "Side walls off parallel"
                    (strcat (rtos (abs (/ (* 180.0
                                             (fit:cap-divergence prm))
                                          pi))
                                  2 2)
                            " deg")))))
    (fit:square-lines-poly res)))

(defun fit:square-lines-poly (res / dirs offs corners n i j out worst sw
                                   base names)
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
        (setq sw (abs (cal:signed-dang (nth i base) (nth i dirs))))
        (if (> sw worst) (setq worst sw))
        (setq out (cons (cons (strcat "Side " (fit:wall-name i n))
                              (fit:ftin (cal:dist
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
                              (fit:ftin (cal:dist (nth i corners)
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

;; A line for any arc the fit had to rebuild as a run of arcs: how
;; many, and the radius of each - the shape a shell that caved in
;; actually took, instead of the one clean radius it was drawn with.
;; How smooth a run came out, for the report.  A joint is never
;; perfectly tangent - the arcs stay ON the survey points instead -
;; but it is always inside the window, and that is worth printing.
(defun fit:kink-text (k)
  (if (or (null k) (< k 1.0e-9))
    ""
    (strcat "  (joints smooth to "
            (rtos (/ (* 180.0 k) pi) 2 1) " deg)")))

(defun fit:chain-lines (res / out chains chain z segs s txt r r2 i nm)
  (setq out nil)
  (cond
    ((and (eq (fit:rget res 'kind) 'poly) (fit:rget res 'runs))
     (foreach r (fit:rget res 'runs)
       (setq segs (cadddr r) txt "")
       (foreach s segs
         (setq r2  (fit:bulge-radius (car s) (cadr s) (caddr s))
               txt (strcat txt (if (= txt "") "" " / ")
                           (if r2 (fit:ftin r2) "straight"))))
       (setq nm  (if (eq (car (car r)) 'wall)
                   (strcat "Wall "
                           (fit:wall-name (cdr (car r))
                                          (length (fit:rget res 'dirs))))
                   (strcat "Corner "
                           (chr (+ 65 (cdr (car r))))))
             out (cons (cons (strcat nm " is a run of")
                             (strcat (itoa (cadr r)) " arcs  R " txt
                                     (fit:kink-text (caddr r))))
                       out))))
    ((eq (fit:rget res 'kind) 'cap)
     (setq chains (fit:rget res 'chains) i 0)
     (foreach chain chains
       (if (and chain (> (length chain) 1))
         (progn
           (setq z    (fit:chain-close res i)
                 segs (fit:chain-segs chain z)
                 txt  "")
           (foreach s segs
             (setq r   (fit:bulge-radius (car s) (cadr s) (caddr s))
                   txt (strcat txt (if (= txt "") "" " / ")
                               (if r (fit:ftin r) "straight"))))
           (setq nm  (if (= i 0) "A" "B")
                 out (cons (cons (strcat "End " nm " is a run of")
                                 (strcat (itoa (length segs))
                                         " arcs  R " txt
                                         (fit:kink-text
                                           (nth i (fit:rget res 'kinks)))))
                           out))))
       (setq i (1+ i))))
    ((and (eq (fit:rget res 'kind) 'round) (fit:rget res 'chain))
     (setq chain (fit:rget res 'chain)
           segs  (fit:chain-segs chain (car (car chain)))
           txt   "")
     (foreach s segs
       (setq r   (fit:bulge-radius (car s) (cadr s) (caddr s))
             txt (strcat txt (if (= txt "") "" " / ")
                         (if r (fit:ftin r) "straight"))))
     (setq out (list (cons "Outline is a run of"
                           (strcat (itoa (length segs))
                                   " arcs  R " txt
                                   (fit:kink-text
                                     (fit:rget res 'kink))))))))
  (reverse out))

;; Where a cap's run of arcs lands: the far spring point of that end.
(defun fit:chain-close (res i / verts chain n j k)
  (setq verts (fit:rget res 'verts)
        chain (nth i (fit:rget res 'chains))
        n     (length verts)
        j     0 k nil)
  ;; the vertex after the run's last one closes it
  (while (< j n)
    (if (equal (car (nth j verts)) (car (last chain)) 1.0e-9)
      (setq k (rem (1+ j) n)))
    (setq j (1+ j)))
  (if k (car (nth k verts)) (car (car chain))))

;; Radius of the arc (A B bulge); nil when the segment is straight.
(defun fit:bulge-radius (a b bl / h)
  (if (< (abs bl) 1.0e-9)
    nil
    (progn
      (setq h (/ (cal:dist a b) 2.0))
      (/ (* h (1+ (* bl bl))) (* 2.0 (abs bl))))))

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
            (setq c   (cal:dist (nth i corners)
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
                      (fit:bow-lines res) (fit:chain-lines res))
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
      (cal:ensure-layer fit:*miss-layer* 1)
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

;; Show an offset the way it was typed: architectural when it came in
;; as feet-and-inches, plain inches otherwise.  DEF is (value . ftin).
(defun fit:fmt-off (def)
  (if (cdr def) (rtos (car def) 4 4) (rtos (car def) 2 2)))

;; Read a distance, remembering HOW it was typed - as feet-and-inches
;; (3'6) or plain inches (42).  Returns (value . ftin); Enter takes
;; DEF, a pair from the previous entry.  Typing B goes back (CAL-BACK)
;; when BACK is on.
(defun fit:get-off (msg def back / s v res)
  (setq res nil)
  (while (null res)
    (setq s (getstring T (strcat "\n" msg " <" (fit:fmt-off def) ">"
                                 (if back " [Back]" "") ": ")))
    (cond
      ((= s "") (setq res def))
      ((and back (cal:back-word-p s)) (setq res 'CAL-BACK))
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
                       s2 out prm)
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
              o  (cal:mid c1 c2)
              u  (cal:v* (fit:wall-normal (nth e dirs)) -1.0)
              v  (cal:perp u)
              s1 (cal:dot v (cal:v- c1 o))
              s2 (cal:dot v (cal:v- c2 o)))
        (if (> s1 s2) (setq c1 s1 s1 s2 s2 c1))
        (setq out (cons (list (fit:from-frame o a m)
                              (fit:ffd u a m) (fit:ffd v a m) s1 s2)
                        out))))
    (if (eq (fit:rget res 'kind) 'oasis)
      ;; an oasis is all curve, so there is no wall to square a hopper
      ;; to - the ENVELOPE is the pool's own frame, and all four of its
      ;; bounds are offered, so the picked deep end chooses which way
      ;; the hopper lies
      (progn
        (setq prm (fit:rget res 'prm)
              o   (list (fit:pget prm 'x0) (fit:pget prm 'y0))
              u   (fit:pget prm 'w)
              v   (fit:pget prm 'h))
        (setq out
          (list
            (list (fit:from-frame (cal:v+ o (list u (/ v 2.0))) a m)
                  (fit:ffd '(-1.0 0.0) a m) (fit:ffd '(0.0 1.0) a m)
                  (/ v -2.0) (/ v 2.0))
            (list (fit:from-frame (cal:v+ o (list 0.0 (/ v 2.0))) a m)
                  (fit:ffd '(1.0 0.0) a m) (fit:ffd '(0.0 1.0) a m)
                  (/ v -2.0) (/ v 2.0))
            (list (fit:from-frame (cal:v+ o (list (/ u 2.0) v)) a m)
                  (fit:ffd '(0.0 -1.0) a m) (fit:ffd '(1.0 0.0) a m)
                  (/ u -2.0) (/ u 2.0))
            (list (fit:from-frame (cal:v+ o (list (/ u 2.0) 0.0)) a m)
                  (fit:ffd '(0.0 1.0) a m) (fit:ffd '(1.0 0.0) a m)
                  (/ u -2.0) (/ u 2.0)))))
    (progn                                ; cap types: end lines
      ;; each leg takes its cross extent from the walls AT ITS OWN END,
      ;; so a pool built wider at one end gets a hopper square to the
      ;; wall that is really there
      (setq prm (fit:rget res 'prm))
      (setq out (list (list (fit:from-frame
                              (list (fit:pget prm 'Re)
                                    (fit:cap-cy prm (fit:pget prm 'Re)))
                              a m)
                            (fit:ffd '(-1.0 0.0) a m)
                            (fit:ffd '(0.0 1.0) a m)
                            (- (fit:cap-half prm (fit:pget prm 'Re)))
                            (fit:cap-half prm (fit:pget prm 'Re)))))
      (if (fit:rget res 'both)
        (setq out (cons (list (fit:from-frame
                                (list (fit:pget prm 'Re2)
                                      (fit:cap-cy prm (fit:pget prm 'Re2)))
                                a m)
                              (fit:ffd '(1.0 0.0) a m)
                              (fit:ffd '(0.0 1.0) a m)
                              (- (fit:cap-half prm (fit:pget prm 'Re2)))
                              (fit:cap-half prm (fit:pget prm 'Re2)))
                        out))
        (setq out (cons (list (fit:from-frame
                                (list (fit:pget prm 'Lx)
                                      (fit:cap-cy prm (fit:pget prm 'Lx)))
                                a m)
                              (fit:ffd '(1.0 0.0) a m)
                              (fit:ffd '(0.0 1.0) a m)
                              (- (fit:cap-half prm (fit:pget prm 'Lx)))
                              (fit:cap-half prm (fit:pget prm 'Lx)))
                        out))))))
  out)

;; leg point -> world
(defun fit:leg-pt (leg p)
  (cal:v+ (car leg)
          (cal:v+ (cal:v* (cadr leg) (car p))
                  (cal:v* (caddr leg) (cadr p)))))

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
        (setq d (cal:dist (cal:2d pick) (car lg)))
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
             ((eq v 'CAL-BACK)
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
             ((eq v 'CAL-BACK)
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
             ((eq v 'CAL-BACK)
              (princ "\nStepping back one step.")
              (setq step 3))
             ((>= (car v) (- db 1.0))
              (princ "\n  (the back offset must stay short of the deep break)"))
             (T (setq fit:*hop-back* v bo (car v) step 5))))))
      (if (> step 4)
        (progn
          (cal:ensure-layer fit:*pool-layer* 4)
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
      (cal:ensure-layer fit:*pool-layer* 4)
      (fit:tag-mine (fit:make-circle c (- r off) fit:*pool-layer*))
      (fit:tag-mine (fit:make-dim c (cal:v+ c (list (- r off) 0.0)) nil))
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
       (setq v (cal:askkw (strcat "\n  Step 1 of " n
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
          (setq v (cal:asktreat "the pool corners"
                                (if fit:*treat* fit:*treat* "Radius") T)))
         ((= ptype "Grecian")
          (princ (strcat "\n\n  Step 2 of " n
                         " - the cut corners.  Nominal grecians are sharp,"))
          (princ "\n  but an as-built may ease them - Radius measures that easing")
          (princ "\n  from the points (too small to believe stays sharp).")
          (setq v (cal:asktreat "the cut corners"
                                (if fit:*gtreat* fit:*gtreat* "Radius") T)))
         ((= ptype "OAsis")
          ;; an oasis has no corners at all, so step 2 asks the one
          ;; thing the points cannot be READ without: which of OASIS's
          ;; five families was surveyed.  Everything a family comes two
          ;; ways over - a cloud's bottom, which way a kidney is given -
          ;; is found rather than asked.
          (princ (strcat "\n\n  Step 2 of " n
                         " - which oasis is it?  The shape says how to"))
          (princ "\n  read the survey; the points put every radius where they")
          (princ "\n  want it.  A cloud's flat bottom and which way a kidney is")
          (princ "\n  given are measured, not asked.")
          (setq v (cal:askkw "Oasis shape" fit:*oas-fams*
                             "Center/TopRight/CLoud/Kidney/NXTcloud"
                             (if fit:*oasfam* fit:*oasfam* "Center") T)))
         (T (setq v "Square")))
       (if (eq v 'CAL-BACK)
         (progn (princ "\nStepping back one step.")
                (setq step 1))
         (progn
           (setq treat v)
           (if (member ptype '("Rectangle" "L" "LAzyl"))
             (setq fit:*treat* v))
           (if (= ptype "Grecian") (setq fit:*gtreat* v))
           (if (= ptype "OAsis") (setq fit:*oasfam* v))
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
       (if (member ptype '("ROUnd" "OAsis"))
         (setq v nil)                      ; neither one has any walls
         (progn
           (princ (strcat "\n\n  Step 5 of " n
                          " - is the pool in-square, or out of square?"))
           (princ "\n  Outofsquare lets each wall swing a little to honour the")
           (princ "\n  points; Insquare holds the template true and shows you")
           (princ "\n  the error instead.  A Roman or Oval's two side walls")
           (princ "\n  are not held parallel at all: a shell slumps as it")
           (princ "\n  cures, so one very often slants away from the other.")
           (setq v (cal:askkw "Is the pool in-square or out-of-square?"
                              "Insquare Outofsquare"
                              "Insquare/Outofsquare"
                              (if oos "Outofsquare" "Insquare") T))
           (if (not (eq v 'CAL-BACK)) (setq v (= v "Outofsquare")))))
       (if (eq v 'CAL-BACK)
         (progn (princ "\nStepping back one step.")
                (setq step 4))
         (setq oos v step 6)))
      ((= step 6)
       (if (member ptype '("ROUnd" "OAsis"))
         (setq v nil)                      ; nor has either one a wall
         (progn                            ; that could be bowed
           (princ (strcat "\n\n  Step 6 of " n
                          " - may the straight walls be bowed?"))
           (princ "\n  A wall drawn dead straight is very often a very long")
           (princ "\n  radius on site.  Yes measures a bow on every wall from")
           (princ "\n  the points and keeps it only where they prove one - a")
           (princ "\n  wall that really is straight stays straight, and no bow")
           (princ "\n  ever moves a corner.  No is the answer for a drawing that")
           (princ "\n  has to show clean straight walls whatever the site did.")
           (setq v (cal:askyn "Any bowed walls?"
                              (if bowed "Yes" "No") T))))
       (if (eq v 'CAL-BACK)
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
    (if (< (cal:dist (car x) q) fit:*exact-eps*) (setq found T)))
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
  (cal:ensure-layer fit:*out-layer* 2)
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
    ((and w2 (or (null w1) (<= (cal:dist wp w2) (cal:dist wp w1))))
     (cons 'RESTORE w2))
    (w1 (cons 'OMIT w1))))

;; fit-omit without the entry for point Q (and its ring erased).
(defun fit:omit-drop (q / out x)
  (setq out nil)
  (foreach x fit-omit
    (if (< (cal:dist (car x) q) fit:*exact-eps*)
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
    (setq pick (fit:omit-choose (cal:2d wp)))
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

;; How many survey points a type needs before its template means
;; anything: three for a circle, and an oasis carries up to ten fitted
;; parameters, so it wants a shot every few feet round the shell.
(defun fit:min-points (ptype)
  (cond ((= ptype "ROUnd") 3)
        ((= ptype "OAsis") 12)
        (T 6)))

(defun c:FITABHD ( / *error* undo-open set ptype treat tol pct oos bowed
                    ss n res verts en swept ans again dpts
                    fit-pts fit-npt fit-ptnames fit-omit)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:sysrestore)
    (if undo-open (command "_.UNDO" "_End"))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nFITABHD error: " msg)))
    ;; cover mode lasts one run: leaked, it would quietly cost the next
    ;; FITABHD its bottom
    (setq fit:*nobottom* nil)
    (princ))
  (cal:syssave '("OSMODE" "CMDECHO" "CLAYER"))
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
    ((< (setq n (fit:gather ss)) (fit:min-points ptype))
     (princ (strcat "\nOnly " (itoa n) " survey point(s) found - a "
                    ptype " template needs at least "
                    (itoa (fit:min-points ptype)) ".")))
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
             dpts  (cal:dedupe (fit:active) fit:*exact-eps*))
       (if (< (length dpts) (fit:min-points ptype))
         (princ (strcat "\nToo few points left in the fit ("
                        (itoa (length dpts))
                        ") - put some back on the next Redo."))
         (progn
           (princ (strcat "\nFitting the "
                          (if (= ptype "OAsis")
                            (strcat treat " oasis")
                            (strcat ptype " template"))
                          " every way it can sit, keeping the"
                          " best..."))
           (setq res   (fit:fit-and-snap dpts ptype treat tol pct oos
                                         bowed)
                 verts (if res (fit:res-world-verts res)))
           (if (null verts)
             ;; nothing the type can say passes through these points at
             ;; all - an oasis family that is not this pool, most often
             (progn
               (princ (strcat "\nFITABHD: no " ptype
                              " outline could be built from these points."))
               (princ "\n  Try another shape, or leave the strays out and Redo.")
               (setq res nil))
             (progn
               (cal:ensure-layer fit:*out-layer* 2)
               (setq en (fit:tag-mine (fit:make-pline verts
                                                      fit:*out-layer* 2)))
               (fit:report res dpts tol (fit:rget res 'allow))))))
       (setq ans (cal:askkw "\nKeep this fit, or Redo it?"
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
          ;; cover mode answers this No without asking: a cover sheet
          ;; is the perimeter and nothing below it
          (if (and (not fit:*nobottom*)
                   (cal:askyn (if (= ptype "ROUnd")
                                "Add the bottom of the pool (hopper ring)?"
                                "Add the bottom of the pool (standard hopper)?")
                              "No" nil))
            (if (= ptype "ROUnd")
              (fit:round-bottom res)
              (fit:bottom res))
            (if fit:*nobottom*
              (princ "\nCover sheet - the pool bottom was skipped."))))
         (T
          (fit:omit-clear)
          (if (and en (entget en)) (entdel en))
          (fit:purge-mine fit:*miss-layer*)
          (princ "\nNothing kept - the drawing is unchanged."))))))
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (cal:sysrestore)
  (setq fit:*nobottom* nil)
  (princ))

;; FITABHD for a cover sheet: the same template fit, with the
;; pool-bottom question answered No before it is asked.  A command of
;; its own rather than a mode, so a button runs exactly what it names;
;; c:FITABHD clears the flag on both exits so it cannot leak.
(defun c:FITABHDCOVER ()
  (setq fit:*nobottom* t)
  (princ "\nFITABHDCOVER: cover sheet - the pool bottom will be skipped.")
  (c:FITABHD)
  (princ))

;; ----------------------------------------------------------------------
(princ (strcat "\nFITABHD " *fitabhd-version*
               " loaded.  Type FITABHD to run (FITABHDVER for the"
               " version)."))
(princ)
