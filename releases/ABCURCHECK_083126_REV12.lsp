;;; ======================================================================
;;; ABCURCHECK.lsp  --  grade how continuous a drawn pool perimeter is
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  ABCURCHECK        measure a perimeter, mark it, report
;;;            ABCURCHECKSCAN    the same measurement, nothing drawn
;;;            ABCURCHECKRESCUE  erase the marks ABCURCHECK made
;;;            ABCURCHECKVER     print the loaded version
;;;
;;; A fork of ABHD's geometry reader.  ABHD BUILDS a smooth perimeter
;;; through surveyed points; this measures one that already exists and
;;; says how continuous it is - as a word a drafter can act on, not a
;;; pile of numbers.
;;;
;;; THE INPUT is the same either way: one closed LWPOLYLINE / POLYLINE,
;;; or that same shape exploded into LINEs and ARCs (a CIRCLE counts as
;;; a round spa perimeter).  Exploded input is walked back into a ring
;;; nearest-end first; unlike ABHD's pf:chain this never bails on a
;;; gap, because measuring the gap IS the job.
;;;
;;; CONTINUITY IS A LADDER, and each rung catches a different kind of
;;; bad drawing:
;;;
;;;   G0 - does it close?  Endpoint gaps between segments, zero-length
;;;        segments, duplicated segments, and chords that cross.  A
;;;        trace exploded and rejoined by hand is riddled with
;;;        sub-1/16" gaps that look perfect on screen and break every
;;;        tool downstream.  Any of these caps the grade at Broken.
;;;
;;;   G1 - tangent breaks.  At every joint, the signed angle between
;;;        the arriving tangent and the leaving one.  The bands are
;;;        ABHD's own numbers, so the two commands agree on what
;;;        "smooth" means:
;;;
;;;          <= acc:*tangent-eps*  (0.5 deg)  tangent - clean
;;;          <= acc:*kink-tol*     (8 deg)    soft break - reads smooth
;;;          <= acc:*corner-ang*   (45 deg)   VISIBLE KINK - the problem
;;;           > acc:*corner-ang*              corner - meant, if declared
;;;
;;;        That 8-45 band is the whole point of the command: too big to
;;;        look smooth, too small to read as an intentional corner.  It
;;;        is the kink a fabricator finds in the bead and nobody meant
;;;        to draw.
;;;
;;;   NOISE - the metrics that catch a TRACED perimeter, which is
;;;        tangent everywhere and still wrong.  Micro-segments (shorter
;;;        than acc:*micro-len*) and their share of the perimeter;
;;;        curvature sign changes (inflections); and the turning
;;;        excess.  For any simple closed loop the SIGNED turning is
;;;        exactly 360 deg, while the ABSOLUTE turning - every arc
;;;        sweep and every kink added up regardless of direction - is
;;;        at least that, and equal only for a convex shape.  So
;;;
;;;            excess = (total absolute turning / 360 deg) - 1
;;;
;;;        is one scale-free number folding kinks and wiggle together:
;;;        0 for an oval, a few tenths for a kidney's concave run, well
;;;        over 1 for a noisy trace.  The signed total is reported too,
;;;        because a value that is not 360 deg means the loop doubles
;;;        back or crosses itself.
;;;
;;; DECLARED DISCONTINUITIES.  The user picks the breaks that are meant
;;; to be there - a step corner, a spa dam wall, a beach entry.  One
;;; pick does three jobs:
;;;   * it snaps to the nearest joint within acc:*snap-dist* and takes
;;;     that joint out of the grade, listing it separately with its
;;;     measured angle, so a 90 deg corner stops dragging the score
;;;     down;
;;;   * a pick that lands nowhere near a joint is reported the other
;;;     way round - "declared here, but the geometry is continuous";
;;;   * everything left over is the real output: the UNDECLARED
;;;     discontinuities, which is the list to go and fix.
;;; Declarations are dashed rings on acc:*mark-layer*, stamped as this
;;; command's own, so a second run remembers what the first was told.
;;;
;;; THE VERDICT is two numbers on purpose.  The GRADE - Broken, Rough,
;;; Fair or Smooth - is set by the single worst thing found and names
;;; it, because a drafter has to know why.  The INDEX (0-100) is a
;;; weighted blend of integrity, tangency and noise; it settles nothing
;;; on its own and exists to compare two candidate perimeters.
;;;
;;; THE CURVATURE COMB is the qualitative answer in a form nobody needs
;;; a table to read: a tooth at every sample, its length proportional
;;; to curvature and its side set by which way the curve turns, with
;;; the tips strung into one envelope.  Every tangent break is a step
;;; in that envelope, every noisy stretch a fuzzy one, and every
;;; inflection a crossing.  Lines and arcs are never truly curvature-
;;; continuous, so the steps at a line-to-arc joint are expected - the
;;; comb shows their SIZE, which is the part that matters.
;;;
;;; WHAT IS NOT MEASURED: curvature jumps are drawn, not scored - a
;;; polyline of lines and arcs can never be G2-continuous, so grading
;;; it on that would fail every honest drawing.  Crossings are tested
;;; on segment CHORDS, so a bulged pair that overlaps only through its
;;; arcs is caught by the signed-turning total instead.
;;; ======================================================================

(setq *abcurcheck-version* "v1.2")   ; announced on load; release_lisp.py
                                     ; reads this banner and stamps the
                                     ; dated twin in releases/ from it

;; ---- configuration ---------------------------------------------------

(setq acc:*mark-layer*   "POOL-CONT")  ; findings and declarations go here
(setq acc:*comb-layer*   "POOL-COMB")  ; the curvature comb goes here
(setq acc:*fuzz*         1.0e-4)       ; endpoint-matching fuzz, as ABHD's
                                       ; *PF-CHAIN-FUZZ*: closer than this
                                       ; and two ends are the same point
(setq acc:*tangent-eps*  0.5)          ; deg - at or under this a joint is
                                       ; tangent
(setq acc:*kink-tol*     8.0)          ; deg - ABHD's *PF-TANG-TOL*: the
                                       ; most a joint may turn and still
                                       ; read as smooth
(setq acc:*corner-ang*   45.0)         ; deg - ABHD's *PF-CORNER-ANG*:
                                       ; over this it is a corner, not a
                                       ; kink
(setq acc:*micro-len*    3.0)          ; a segment shorter than this (3
                                       ; inches) is a micro-segment: the
                                       ; signature of a traced outline
(setq acc:*micro-share*  0.10)         ; share of the perimeter sitting in
                                       ; micro-segments that costs the
                                       ; whole noise score
(setq acc:*close-tol*    5.0)          ; deg - how far the signed turning
                                       ; total may sit off 360 before the
                                       ; loop is called self-crossing
(setq acc:*snap-dist*    6.0)          ; how near a declaration pick must
                                       ; land to a joint to claim it
(setq acc:*mark-radius*  4.0)          ; radius of the finding rings
(setq acc:*cross-max*    300)          ; skip the O(n^2) crossing scan
                                       ; above this many segments, and say
                                       ; so rather than pretend it ran
(setq acc:*comb-step*    12.0)         ; one comb tooth per foot of run
(setq acc:*comb-max*     24.0)         ; length of the tooth at the
                                       ; tightest curvature in the loop
(setq acc:*excess-free*  0.35)         ; turning excess a freeform pool is
                                       ; allowed before the noise score
                                       ; starts to fall...
(setq acc:*excess-cap*   1.00)         ; ...and where it reaches zero
(setq acc:*w-integrity*  40.0)         ; index weights: G0 is pass/fail,
(setq acc:*w-tangency*   35.0)         ; tangency scales with the total
(setq acc:*w-noise*      25.0)         ; undeclared kink, noise with the
                                       ; micro share and turning excess

(setq acc:*sysvars* '("OSMODE" "CMDECHO" "CLAYER"))  ; saved and put back
(setq acc:*sysold* nil)                ; the snapshot itself

;; ---- small 2D vector helpers -----------------------------------------
;; Local copies of the generic library helpers, as the standalone tier
;; requires (STANDARDS section 6): same bodies, this file's prefix.

(defun acc:2d (p) (list (car p) (cadr p)))
(defun acc:dist (a b) (distance (acc:2d a) (acc:2d b)))
(defun acc:v- (a b) (mapcar '- (acc:2d a) (acc:2d b)))
(defun acc:v+ (a b) (mapcar '+ (acc:2d a) (acc:2d b)))
(defun acc:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun acc:cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))

;; normalize an angle into [0, 2pi)
(defun acc:angnorm (a)
  (while (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (while (>= a (* 2.0 pi)) (setq a (- a (* 2.0 pi))))
  a)

;; smallest signed angular difference (to - from), in (-pi, pi]
(defun acc:signed-dang (from to / d)
  (setq d (acc:angnorm (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

(defun acc:deg (r) (* 180.0 (/ r pi)))
(defun acc:rad (d) (* pi (/ d 180.0)))

;; smallest integer >= X (X non-negative)
(defun acc:ceil (x / f)
  (setq f (fix x))
  (if (> x f) (1+ f) f))

;; tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn quarter-sweep yields a huge but finite bulge
;; instead of dividing by zero
(defun acc:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;; drop the first structurally equal member of LST
(defun acc:remove (val lst / out hit x)
  (setq out nil hit nil)
  (foreach x lst
    (if (and (not hit) (equal x val))
      (setq hit T)
      (setq out (cons x out))))
  (reverse out))

;; Circumcenter of three points, nil when (nearly) collinear.
(defun acc:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
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

;; ---- segment geometry ------------------------------------------------
;; A segment is (startPt endPt bulge), 2D points - ABHD's shape exactly,
;; so the two commands read a drawing the same way.

;; signed sweep of a bulged segment: bulge = tan(sweep/4), positive CCW
(defun acc:sweep (b) (* 4.0 (atan b)))

;; Radius of the arc (A B bulge); nil for a straight segment.
(defun acc:bulge-radius (a b bl / h)
  (if (< (abs bl) 1.0e-9)
    nil
    (progn
      (setq h (/ (acc:dist a b) 2.0))
      (/ (* h (1+ (* bl bl))) (* 2.0 (abs bl))))))

;; Signed curvature of a segment: 0.0 straight, +ve turning left (CCW).
;; The sign is what makes an inflection countable and what puts a comb
;; tooth on the correct side.
(defun acc:seg-curv (s / r)
  (setq r (acc:bulge-radius (car s) (cadr s) (caddr s)))
  (cond ((null r) 0.0)
        ((< r 1.0e-9) 0.0)
        ((< (caddr s) 0.0) (- (/ 1.0 r)))
        (T (/ 1.0 r))))

;; Length along a segment - the chord when straight, the arc otherwise.
(defun acc:seg-len (s / r)
  (setq r (acc:bulge-radius (car s) (cadr s) (caddr s)))
  (if r
    (* r (abs (acc:sweep (caddr s))))
    (acc:dist (car s) (cadr s))))

;; Tangent direction at the start of a segment: the chord direction
;; turned back by half the sweep.
(defun acc:seg-t0 (s)
  (- (angle (acc:2d (car s)) (acc:2d (cadr s)))
     (* 2.0 (atan (caddr s)))))

;; ...and at its end: the chord direction turned on by half the sweep.
(defun acc:seg-t1 (s)
  (+ (angle (acc:2d (car s)) (acc:2d (cadr s)))
     (* 2.0 (atan (caddr s)))))

;; Arc geometry of a bulged segment: (center radius angStart), nil when
;; the segment is straight.
(defun acc:arc-geom (s / p1 p2 b ch dir apex c)
  (setq p1 (acc:2d (car s))
        p2 (acc:2d (cadr s))
        b  (caddr s))
  (if (< (abs b) 1.0e-9)
    nil
    (progn
      (setq ch   (acc:dist p1 p2)
            dir  (acc:v* (acc:v- p2 p1) (/ 1.0 ch))
            ;; sagitta = (chord/2)*bulge; a positive (CCW) bulge apex
            ;; lies to the RIGHT of the p1->p2 chord direction
            apex (acc:v+ (acc:v* (acc:v+ p1 p2) 0.5)
                          (acc:v* (list (- (cadr dir)) (car dir))
                                   (* -0.5 ch b)))
            c    (acc:circumcenter p1 apex p2))
      (if (null c)
        nil
        (list c (acc:dist c p1) (angle c p1))))))

;; The point at parameter U (0..1) along a segment.
(defun acc:seg-pt (s u / g)
  (setq g (acc:arc-geom s))
  (if (null g)
    (acc:v+ (acc:2d (car s))
             (acc:v* (acc:v- (cadr s) (car s)) u))
    (polar (car g) (+ (caddr g) (* u (acc:sweep (caddr s)))) (cadr g))))

;; The tangent direction at parameter U: it rotates uniformly along an
;; arc, so this is the start tangent plus U of the sweep.
(defun acc:seg-tan (s u)
  (+ (acc:seg-t0 s) (* u (acc:sweep (caddr s)))))

;; ---- entity -> segment extraction ------------------------------------

(defun acc:lw-segs (ed / pts bls item segs n closed)
  ;; collect (10) vertices and their (42) bulges, in order
  (setq pts nil bls nil)
  (foreach item ed
    (cond
      ((= (car item) 10)
       (setq pts (cons (acc:2d (cdr item)) pts)
             bls (cons 0.0 bls)))
      ((and (= (car item) 42) bls)
       (setq bls (cons (cdr item) (cdr bls))))))
  (setq pts    (reverse pts)
        bls    (reverse bls)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        segs   nil
        n      0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  ;; The closing span of a CLOSED polyline is real geometry and carries
  ;; the last vertex's bulge.  An OPEN one is left open on purpose: the
  ;; ring is closed later with a recorded gap, which is the finding.
  ;; TWO vertices is enough here, where ABHD wants three: a round spa
  ;; is drawn as two bulged vertices, and dropping its closing span
  ;; would turn the smoothest shape in the drawing into a 180 deg kink.
  (if (and closed (> (length pts) 1)
           (>= (acc:dist (last pts) (car pts)) acc:*fuzz*))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun acc:pl-segs (en / ed sub pts bls segs n closed)
  ;; heavy (old-style) 2D POLYLINE: walk its VERTEX sub-entities
  (setq ed     (entget en)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        pts    nil
        bls    nil
        sub    (entnext en))
  (while (and sub (= "VERTEX" (cdr (assoc 0 (setq ed (entget sub))))))
    ;; skip spline/fit control vertices (flag bits 1 and 16)
    (if (= 0 (logand 17 (cond ((cdr (assoc 70 ed))) (0))))
      (setq pts (cons (acc:2d (cdr (assoc 10 ed))) pts)
            bls (cons (cond ((cdr (assoc 42 ed))) (0.0)) bls)))
    (setq sub (entnext sub)))
  (setq pts (reverse pts) bls (reverse bls) segs nil n 0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  (if (and closed (> (length pts) 1))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun acc:ent-segs (en / ed typ c r a1 a2 delta)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (acc:2d (cdr (assoc 10 ed)))
                 (acc:2d (cdr (assoc 11 ed)))
                 0.0)))
    ((= typ "ARC")
     (setq c     (acc:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           a1    (cdr (assoc 50 ed))
           a2    (cdr (assoc 51 ed))
           delta (acc:angnorm (- a2 a1)))
     (if (< delta 1.0e-10) (setq delta (* 2.0 pi)))
     ;; a full-circle arc cannot be one bulged segment (its bulge is
     ;; infinite): hand back two semicircles instead
     (if (> delta (- (* 2.0 pi) 1.0e-9))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r) (acc:tan (/ delta 4.0))))))
    ;; a CIRCLE is a legitimate perimeter (round spa): two semicircles,
    ;; so the ring walk sees a normal closed loop instead of a gap
    ((= typ "CIRCLE")
     (setq c (acc:2d (cdr (assoc 10 ed)))
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
    ((= typ "LWPOLYLINE") (acc:lw-segs ed))
    ((= typ "POLYLINE") (acc:pl-segs en))
    (T nil)))

;; ---- ordering loose segments into a ring -----------------------------
;; ABHD's pf:chain stops at the first gap because a gap means it cannot
;; fit.  Here the gap is the finding, so the walk always carries on:
;; take whichever remaining segment has an end nearest to where we are,
;; reversing it when it is its far end that is nearer, and let the jump
;; distance be recorded as the joint's gap.

(defun acc:chain (segs / loop cur rest best orig bd s d dr)
  (if (null segs)
    nil
    (progn
      (setq loop (list (car segs))
            cur  (cadr (car segs))
            rest (cdr segs))
      (while rest
        (setq best nil orig nil bd nil)
        (foreach s rest
          (setq d  (acc:dist cur (car s))
                dr (acc:dist cur (cadr s)))
          (if (or (null bd) (< d bd))
            (setq bd d best s orig s))
          (if (< dr bd)
            (setq bd   dr
                  best (list (cadr s) (car s) (- (caddr s)))
                  orig s)))
        (setq loop (cons best loop)
              cur  (cadr best)
              rest (acc:remove orig rest)))
      (reverse loop))))

;; ---- the joints ------------------------------------------------------
;; One record per joint of the ring, joint I sitting between segment I
;; and segment I+1 (the last one wrapping round to the first):
;;
;;   (index  position-along  gap  kink-angle  point  band
;;    declared-p)
;;
;; POSITION-ALONG is measured from the start of the first segment, so a
;; finding can be walked to.  BAND is the tangent classification, and
;; DECLARED-P says the user has already accounted for it.

(defun acc:j-idx  (j) (nth 0 j))
(defun acc:j-pos  (j) (nth 1 j))
(defun acc:j-gap  (j) (nth 2 j))
(defun acc:j-ang  (j) (nth 3 j))
(defun acc:j-pt   (j) (nth 4 j))
(defun acc:j-band (j) (nth 5 j))
(defun acc:j-decl (j) (nth 6 j))

;; Which band a turn of A radians (absolute) falls in.
(defun acc:band (a)
  (cond ((<= a (acc:rad acc:*tangent-eps*)) "tangent")
        ((<= a (acc:rad acc:*kink-tol*))    "soft")
        ((<= a (acc:rad acc:*corner-ang*))  "kink")
        (T                                  "corner")))

;; T when P is close enough to one of the declared picks to be claimed.
(defun acc:declared-p (p declared / hit q)
  (setq hit nil)
  (foreach q declared
    (if (<= (acc:dist p q) acc:*snap-dist*) (setq hit T)))
  hit)

(defun acc:joints (segs declared / n i k out this next pos gap ang p)
  (setq n   (length segs)
        i   0
        pos 0.0
        out nil)
  (while (< i n)
    (setq this (nth i segs)
          k    (if (= (1+ i) n) 0 (1+ i))
          next (nth k segs)
          pos  (+ pos (acc:seg-len this))
          gap  (acc:dist (cadr this) (car next))
          ang  (acc:signed-dang (acc:seg-t1 this) (acc:seg-t0 next))
          p    (acc:2d (cadr this))
          out  (cons (list (1+ i) pos gap ang p
                           (acc:band (abs ang))
                           (acc:declared-p p declared))
                     out)
          i    (1+ i)))
  (reverse out))

;; ---- G0: the defects that make a grade Broken ------------------------

;; Segments with no length left in them.  They carry no tangent of
;; their own, so every joint either side of one is reported against a
;; direction that means nothing - which is exactly why they matter.
(defun acc:zero-segs (segs / i out s)
  (setq i 0 out nil)
  (foreach s segs
    (setq i (1+ i))
    (if (< (acc:seg-len s) acc:*fuzz*) (setq out (cons i out))))
  (reverse out))

;; Segments drawn twice, either way round - the classic result of a
;; copy that landed back on its original.
(defun acc:dupe-segs (segs / n i k a b out)
  (setq n (length segs) i 0 out nil)
  (while (< i n)
    (setq a (nth i segs) k (1+ i))
    (while (< k n)
      (setq b (nth k segs))
      ;; The bulge has to agree as well as the ends, and reversing a
      ;; segment negates it.  Endpoints alone would call the two halves
      ;; of a round spa - one chord, two opposite arcs - a doubled
      ;; segment, and grade the smoothest shape in the drawing Broken.
      (if (or (and (< (acc:dist (car a) (car b)) acc:*fuzz*)
                   (< (acc:dist (cadr a) (cadr b)) acc:*fuzz*)
                   (< (abs (- (caddr a) (caddr b))) 1.0e-6))
              (and (< (acc:dist (car a) (cadr b)) acc:*fuzz*)
                   (< (acc:dist (cadr a) (car b)) acc:*fuzz*)
                   (< (abs (+ (caddr a) (caddr b))) 1.0e-6)))
        (setq out (cons (list (1+ i) (1+ k)) out)))
      (setq k (1+ k)))
    (setq i (1+ i)))
  (reverse out))

;; Do the open chords A-B and C-D properly cross?  Shared endpoints are
;; excluded by the strict bounds, so neighbours never register.
(defun acc:chords-cross-p (a b c d / r s den t1 u ac)
  (setq r   (acc:v- b a)
        s   (acc:v- d c)
        den (acc:cross r s))
  (if (< (abs den) 1.0e-12)
    nil
    (progn
      (setq ac (acc:v- c a)
            t1 (/ (acc:cross ac s) den)
            u  (/ (acc:cross ac r) den))
      (and (> t1 1.0e-9) (< t1 (- 1.0 1.0e-9))
           (> u  1.0e-9) (< u  (- 1.0 1.0e-9))))))

;; Every crossing pair of segment chords.  Adjacent segments are
;; skipped (they share a point by design) and the scan is quadratic, so
;; it stands down above acc:*cross-max* segments rather than hang - the
;; report says when it did.
(defun acc:crossings (segs / n i k a b out)
  (setq n (length segs) i 0 out nil)
  (while (< i n)
    (setq a (nth i segs) k (+ i 2))
    (while (< k n)
      (setq b (nth k segs))
      (if (not (and (= i 0) (= k (1- n))))   ; first and last are neighbours
        (if (acc:chords-cross-p (car a) (cadr a) (car b) (cadr b))
          (setq out (cons (list (1+ i) (1+ k)) out))))
      (setq k (1+ k)))
    (setq i (1+ i)))
  (reverse out))

;; ---- noise -----------------------------------------------------------

;; Curvature sign changes around the ring.  Straight segments carry no
;; sign, so they neither make nor mask an inflection; the walk is
;; cyclic, so the seam counts like any other.
(defun acc:inflections (segs / signs k n i out s)
  (setq signs nil)
  (foreach s segs
    (setq k (acc:seg-curv s))
    (if (> (abs k) 1.0e-12)
      (setq signs (cons (if (> k 0.0) 1 -1) signs))))
  (setq signs (reverse signs)
        n     (length signs)
        i     0
        out   0)
  (if (> n 1)
    (while (< i n)
      (if (/= (nth i signs) (nth (if (= (1+ i) n) 0 (1+ i)) signs))
        (setq out (1+ out)))
      (setq i (1+ i))))
  out)

;; ---- the measurement -------------------------------------------------
;; Everything the report, the grade and the marks are built from, as one
;; alist so a test can read any single number out of a run.

(defun acc:val (key res) (cdr (assoc key res)))

(defun acc:measure (segs declared / joints n perim gaps zeros dupes
                                    crosses crossrun tsign tabs excess
                                    micron microlen share inflect
                                    tangn softn kinkn cornn decln
                                    declj orphans worst und q hit j s)
  (setq joints (acc:joints segs declared)
        n      (length segs)
        perim  0.0
        tsign  0.0
        tabs   0.0
        micron 0
        microlen 0.0)
  (foreach s segs
    (setq perim (+ perim (acc:seg-len s))
          tsign (+ tsign (acc:sweep (caddr s)))
          tabs  (+ tabs (abs (acc:sweep (caddr s)))))
    (if (< (acc:seg-len s) acc:*micro-len*)
      (setq micron   (1+ micron)
            microlen (+ microlen (acc:seg-len s)))))
  (setq gaps nil tangn 0 softn 0 kinkn 0 cornn 0 decln 0
        declj nil und nil worst nil)
  (foreach j joints
    (setq tsign (+ tsign (acc:j-ang j))
          tabs  (+ tabs (abs (acc:j-ang j))))
    (if (>= (acc:j-gap j) acc:*fuzz*) (setq gaps (cons j gaps)))
    (if (acc:j-decl j)
      (setq decln (1+ decln) declj (cons j declj))
      (progn
        (setq und (cons j und))
        (cond ((= (acc:j-band j) "tangent") (setq tangn (1+ tangn)))
              ((= (acc:j-band j) "soft")    (setq softn (1+ softn)))
              ((= (acc:j-band j) "kink")    (setq kinkn (1+ kinkn)))
              (T                            (setq cornn (1+ cornn))))
        (if (or (null worst) (> (abs (acc:j-ang j)) (abs (acc:j-ang worst))))
          (setq worst j)))))
  ;; a pick that claimed no joint at all: the user says there is a break
  ;; here and the geometry disagrees, which is worth saying out loud
  (setq orphans nil)
  (foreach q declared
    (setq hit nil)
    (foreach j joints
      (if (<= (acc:dist q (acc:j-pt j)) acc:*snap-dist*) (setq hit T)))
    (if (not hit) (setq orphans (cons q orphans))))
  (setq zeros    (acc:zero-segs segs)
        dupes    (acc:dupe-segs segs)
        crossrun (<= n acc:*cross-max*)
        crosses  (if crossrun (acc:crossings segs) nil)
        excess   (- (/ tabs (* 2.0 pi)) 1.0)
        share    (if (> perim 0.0) (/ microlen perim) 0.0)
        inflect  (acc:inflections segs))
  (list (cons "segs" segs)          (cons "joints" joints)
        (cons "n" n)                (cons "perim" perim)
        (cons "gaps" (reverse gaps)) (cons "zeros" zeros)
        (cons "dupes" dupes)        (cons "crosses" crosses)
        (cons "crossrun" crossrun)
        (cons "turn-signed" tsign)  (cons "turn-abs" tabs)
        (cons "excess" excess)
        (cons "micro-n" micron)     (cons "micro-len" microlen)
        (cons "micro-share" share)  (cons "inflect" inflect)
        (cons "tangent-n" tangn)    (cons "soft-n" softn)
        (cons "kink-n" kinkn)       (cons "corner-n" cornn)
        (cons "decl-n" decln)       (cons "decl-joints" (reverse declj))
        (cons "undeclared" (reverse und))
        (cons "orphans" (reverse orphans))
        (cons "worst" worst)))

;; ---- the offenders ---------------------------------------------------
;; The joints the user has not accounted for and that break a
;; threshold: the list the report prints and the marks ring, gathered
;; in one place so the two can never disagree about what counts.

;; How badly one joint offends.  A gap outranks any kink outright - a
;; loop that is not joined up is a different order of problem from one
;; that is joined up roughly.
(defun acc:severity (j)
  (if (>= (acc:j-gap j) acc:*fuzz*)
    (+ 1000.0 (acc:j-gap j))
    (acc:deg (abs (acc:j-ang j)))))

(defun acc:ins (j lst / out done x)
  (setq out nil done nil)
  (foreach x lst
    (if (and (not done) (> (acc:severity j) (acc:severity x)))
      (setq out (cons x (cons j out)) done T)
      (setq out (cons x out))))
  (if done (reverse out) (reverse (cons j out))))

(defun acc:offenders (res / out j)
  (setq out nil)
  (foreach j (acc:val "undeclared" res)
    (if (or (>= (acc:j-gap j) acc:*fuzz*)
            (member (acc:j-band j) '("kink" "corner")))
      (setq out (acc:ins j out))))
  out)

;; ---- the verdict -----------------------------------------------------

;; T when the ring fails at the positional level: a gap, a dead
;; segment, a doubled one, a crossing, or a signed turning total that
;; is not one full revolution (which means it doubles back on itself
;; whether or not two chords happen to cross).
(defun acc:turn-ok-p (res)
  (< (abs (- (abs (acc:val "turn-signed" res)) (* 2.0 pi)))
     (acc:rad acc:*close-tol*)))

(defun acc:g0-fault (res)
  (cond
    ((acc:val "gaps" res)
     (strcat (itoa (length (acc:val "gaps" res)))
             " gap(s) in the loop"))
    ((acc:val "zeros" res)
     (strcat (itoa (length (acc:val "zeros" res)))
             " zero-length segment(s)"))
    ((acc:val "dupes" res)
     (strcat (itoa (length (acc:val "dupes" res)))
             " doubled segment(s)"))
    ((acc:val "crosses" res)
     (strcat (itoa (length (acc:val "crosses" res)))
             " crossing segment(s)"))
    ((not (acc:turn-ok-p res))
     (strcat "the loop turns "
             (rtos (acc:deg (acc:val "turn-signed" res)) 2 1)
             " deg, not 360 - it doubles back on itself"))
    (T nil)))

;; The grade is the worst thing found, and it names that thing.  A
;; weighted blend would be easier to compute and impossible to argue
;; with, which is the wrong way round for a drawing check.
(defun acc:grade (res / f)
  (cond
    ((setq f (acc:g0-fault res)) (list "Broken" f))
    ((> (acc:val "kink-n" res) 0)
     (list "Rough" (strcat (itoa (acc:val "kink-n" res))
                           " undeclared kink(s) over "
                           (rtos acc:*kink-tol* 2 1) " deg")))
    ((> (acc:val "corner-n" res) 0)
     (list "Rough" (strcat (itoa (acc:val "corner-n" res))
                           " undeclared corner(s) over "
                           (rtos acc:*corner-ang* 2 1) " deg")))
    ((> (acc:val "micro-share" res) acc:*micro-share*)
     (list "Rough" (strcat (rtos (* 100.0 (acc:val "micro-share" res)) 2 1)
                           "% of the perimeter is in micro-segments")))
    ((> (acc:val "soft-n" res) 0)
     (list "Fair" (strcat (itoa (acc:val "soft-n" res))
                          " soft break(s) - smooth to the eye, not tangent")))
    ((> (acc:val "excess" res) acc:*excess-free*)
     (list "Fair" (strcat "turning excess " (rtos (acc:val "excess" res) 2 2)
                          " - the outline wanders")))
    ((> (acc:val "micro-n" res) 0)
     (list "Fair" (strcat (itoa (acc:val "micro-n" res))
                          " micro-segment(s)")))
    (T (list "Smooth" "tangent at every joint, no defects"))))

;; The index exists to compare two candidate perimeters, not to settle
;; anything on its own: integrity is pass or fail, tangency falls with
;; the total undeclared turn (a whole revolution of kink scores zero -
;; that outline is a polygon), and noise splits between the micro-
;; segment share and the turning excess above what a freeform shape is
;; owed.
(defun acc:index (res / integ tang noise sum j nm nx)
  (setq integ (if (acc:g0-fault res) 0.0 acc:*w-integrity*)
        sum   0.0)
  (foreach j (acc:val "undeclared" res)
    (if (not (= (acc:j-band j) "tangent"))
      (setq sum (+ sum (abs (acc:j-ang j))))))
  (setq tang (* acc:*w-tangency*
                (- 1.0 (min 1.0 (/ sum (* 2.0 pi)))))
        nm   (- 1.0 (min 1.0 (/ (acc:val "micro-share" res)
                                acc:*micro-share*)))
        nx   (- 1.0 (min 1.0 (/ (max 0.0 (- (acc:val "excess" res)
                                            acc:*excess-free*))
                                (- acc:*excess-cap* acc:*excess-free*))))
        noise (* acc:*w-noise* 0.5 (+ nm nx)))
  (list (fix (+ 0.5 (+ integ tang noise)))
        (fix (+ 0.5 integ)) (fix (+ 0.5 tang)) (fix (+ 0.5 noise))))

;; ---- the report ------------------------------------------------------

;; Pad S out to W characters so the numbers line up in a column.
(defun acc:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; A count and its label, or "none" - a row of zeroes reads as noise in
;; a report someone has to scan.
(defun acc:count-str (n word)
  (if (= n 0) "none" (strcat (itoa n) " " word)))

(defun acc:row (label value)
  (princ (strcat "\n  " (acc:pad label 18) value)))

(defun acc:report (res / g ix j n)
  (princ "\n\n=== ABCURCHECK - perimeter continuity ===")
  (acc:row "Perimeter"
           (strcat (rtos (acc:val "perim" res) 4 4) "  over "
                   (itoa (acc:val "n" res)) " segment(s)"))
  (acc:row "Joints"
           (strcat (itoa (acc:val "n" res)) "  ("
                   (itoa (acc:val "decl-n" res)) " declared, "
                   (itoa (- (acc:val "n" res) (acc:val "decl-n" res)))
                   " measured)"))
  (princ "\n\n  -- the loop itself --")
  (acc:row "Gaps"
           (if (acc:val "gaps" res)
             (strcat (itoa (length (acc:val "gaps" res)))
                     ", worst " (rtos (apply 'max (mapcar 'acc:j-gap
                                                          (acc:val "gaps" res)))
                                      2 4))
             "none"))
  (acc:row "Zero-length" (acc:count-str (length (acc:val "zeros" res))
                                        "segment(s)"))
  (acc:row "Doubled" (acc:count-str (length (acc:val "dupes" res))
                                    "pair(s)"))
  (acc:row "Crossings"
           (if (acc:val "crossrun" res)
             (acc:count-str (length (acc:val "crosses" res)) "pair(s)")
             (strcat "not scanned - over " (itoa acc:*cross-max*)
                     " segments")))
  (acc:row "Turning total"
           (strcat (rtos (acc:deg (acc:val "turn-signed" res)) 2 1)
                   " deg"
                   (if (acc:turn-ok-p res)
                     "  (a simple closed loop turns 360)"
                     "  <-- not one revolution")))
  (princ "\n\n  -- tangency at the joints --")
  (acc:row "Tangent" (strcat (itoa (acc:val "tangent-n" res))
                             "   (within " (rtos acc:*tangent-eps* 2 1)
                             " deg)"))
  (acc:row "Soft breaks" (strcat (itoa (acc:val "soft-n" res))
                                 "   (" (rtos acc:*tangent-eps* 2 1) " - "
                                 (rtos acc:*kink-tol* 2 1) " deg)"))
  (acc:row "Visible kinks"
           (strcat (itoa (acc:val "kink-n" res))
                   "   (" (rtos acc:*kink-tol* 2 1) " - "
                   (rtos acc:*corner-ang* 2 1) " deg)"
                   (if (> (acc:val "kink-n" res) 0)
                     "  <-- these are the problem" "")))
  (acc:row "Corners" (strcat (itoa (acc:val "corner-n" res))
                             "   (over " (rtos acc:*corner-ang* 2 1)
                             " deg, undeclared)"))
  (if (setq j (acc:val "worst" res))
    (acc:row "Worst joint"
             (strcat (rtos (acc:deg (abs (acc:j-ang j))) 2 1)
                     " deg at joint " (itoa (acc:j-idx j))
                     ", " (rtos (acc:j-pos j) 4 4) " along")))
  (princ "\n\n  -- noise --")
  (acc:row "Micro-segments"
           (strcat (itoa (acc:val "micro-n" res)) "   under "
                   (rtos acc:*micro-len* 2 1) "\"  ("
                   (rtos (* 100.0 (acc:val "micro-share" res)) 2 1)
                   "% of the perimeter)"))
  (acc:row "Inflections" (itoa (acc:val "inflect" res)))
  (acc:row "Turning excess" (rtos (acc:val "excess" res) 2 2))
  ;; the offenders, worst first - the list to go and fix
  (setq n 0)
  (foreach j (acc:offenders res)
    (if (= n 0) (princ "\n\n  -- undeclared, worst first --"))
    (setq n (1+ n))
    (princ (strcat "\n    joint " (acc:pad (itoa (acc:j-idx j)) 5)
                   (if (>= (acc:j-gap j) acc:*fuzz*)
                     (strcat "gap " (rtos (acc:j-gap j) 2 4) "  ")
                     "")
                   "kink " (rtos (acc:deg (abs (acc:j-ang j))) 2 1)
                   " deg   at " (rtos (car (acc:j-pt j)) 2 2) ","
                   (rtos (cadr (acc:j-pt j)) 2 2))))
  (foreach j (acc:val "orphans" res)
    (princ (strcat "\n    declared at " (rtos (car j) 2 2) ","
                   (rtos (cadr j) 2 2)
                   " - but the geometry is continuous there")))
  (setq g  (acc:grade res)
        ix (acc:index res))
  (princ (strcat "\n\n  GRADE  " (acc:pad (car g) 10)
                 "set by: " (cadr g)))
  (princ (strcat "\n  Index  " (acc:pad (strcat (itoa (car ix)) " / 100") 10)
                 "(integrity " (itoa (cadr ix))
                 ", tangency " (itoa (caddr ix))
                 ", noise " (itoa (cadddr ix)) ")"))
  (princ)
  g)

;; ---- layers, stamping and marks --------------------------------------

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun acc:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nABCURCHECK: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;; Make sure the DASHED linetype exists (pure entmake, no command
;; calls).  Dash lengths are in drawing units - sized for an inch
;; drawing, so the dashes read at pool scale.
(defun acc:ensure-dashed ()
  (if (not (tblsearch "LTYPE" "DASHED"))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   '(2 . "DASHED") '(70 . 0)
                   '(3 . "Dashed __ __ __ __ __")
                   '(72 . 65) '(73 . 2) '(40 . 18.0)
                   '(49 . 12.0) '(74 . 0)
                   '(49 . -6.0) '(74 . 0)))))

;; ---- "this one is mine" stamping -------------------------------------
;; ABCURCHECK draws onto layers the drawing may already be using, so it
;; must never clear one wholesale.  Everything it makes carries a piece
;; of extended data naming this command and saying which KIND it is -
;; "MARK" for a finding, which a rescue sweeps away, and "DECL" for a
;; declared discontinuity, which survives so the next run remembers it.

(defun acc:tag (en kind / ed)
  (if en
    (progn
      (regapp "ABCURCHECK")
      (setq ed (entget en))
      (entmod (append ed (list (list -3 (list "ABCURCHECK"
                                              (cons 1000 kind))))))))
  en)

(defun acc:kind (en / x)
  (setq x (assoc -3 (entget en '("ABCURCHECK"))))
  (if x (cdr (assoc 1000 (cdr (assoc "ABCURCHECK" (cdr x)))))))

;; Erase this command's own objects of one KIND on a layer, leaving
;; anything the user drew there alone.  Returns how many went.
(defun acc:purge (name kind / ss i n en)
  (setq n 0)
  (if (tblsearch "LAYER" name)
    (progn
      (setq ss (ssget "_X" (list (cons 8 name))))
      (if ss
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq en (ssname ss i))
            (if (or (null kind) (= kind (acc:kind en)))
              (progn (entdel en) (setq n (1+ n))))
            (setq i (1+ i)))))))
  n)

;; The declarations a previous run was told about, read back off the
;; drawing so the user is never asked the same question twice.
(defun acc:read-declared ( / ss i en out ed)
  (setq out nil)
  (if (tblsearch "LAYER" acc:*mark-layer*)
    (progn
      (setq ss (ssget "_X" (list (cons 8 acc:*mark-layer*)))
            i  0)
      (if ss
        (repeat (sslength ss)
          (setq en (ssname ss i)
                ed (entget en))
          (if (and (= "CIRCLE" (cdr (assoc 0 ed)))
                   (= "DECL" (acc:kind en)))
            (setq out (cons (acc:2d (cdr (assoc 10 ed))) out)))
          (setq i (1+ i))))))
  (reverse out))

(defun acc:text (p h str col)
  (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                  (cons 8 acc:*mark-layer*) (cons 62 col)
                  '(100 . "AcDbText")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 h) (cons 1 str))))

(defun acc:ring (p r col dashed)
  (entmakex (append (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                          (cons 8 acc:*mark-layer*) (cons 62 col))
                    (if dashed (list '(6 . "DASHED")) nil)
                    (list '(100 . "AcDbCircle")
                          (cons 10 (list (car p) (cadr p) 0.0))
                          (cons 40 r)))))

;; Draw the dashed green ring that says "this break is meant to be
;; here".  Declarations are redrawn from scratch every run, so the
;; drawing and the answer list can never disagree.
(defun acc:draw-declared (declared / p)
  (acc:ensure-dashed)
  (acc:ensure-layer acc:*mark-layer* 3)
  (acc:purge acc:*mark-layer* "DECL")
  (foreach p declared
    (acc:tag (acc:ring p acc:*mark-radius* 3 T) "DECL")))

;; Ring and label every undeclared finding.  Only what fails is marked:
;; a ring on all 47 joints of a normal polyline says nothing, and a
;; drawing nobody can read is a check nobody runs.
(defun acc:draw-marks (res / h col lab n j)
  (acc:ensure-layer acc:*mark-layer* 3)
  (acc:purge acc:*mark-layer* "MARK")
  (setq h (max 4.0 (/ (acc:val "perim" res) 200.0))
        n 0)
  (foreach j (acc:offenders res)
    (setq col (if (or (>= (acc:j-gap j) acc:*fuzz*)
                      (= (acc:j-band j) "kink"))
                1     ; red - a gap, or the 8-45 deg band that hurts
                2)    ; yellow - a corner nobody declared
          lab (if (>= (acc:j-gap j) acc:*fuzz*)
                (strcat "gap " (rtos (acc:j-gap j) 2 3))
                (strcat (rtos (acc:deg (abs (acc:j-ang j))) 2 1) "%%d"))
          n   (1+ n))
    (acc:tag (acc:ring (acc:j-pt j) acc:*mark-radius* col nil) "MARK")
    (acc:tag (acc:text (polar (acc:j-pt j) (acc:rad 45.0)
                              (* 1.4 acc:*mark-radius*))
                       h lab col)
             "MARK"))
  n)

;; ---- the curvature comb ----------------------------------------------
;; A tooth every acc:*comb-step* of run, its length proportional to
;; curvature and its side set by which way the curve turns, with the
;; tips strung into one envelope.  Every tangent break shows as a step
;; in that envelope, every noisy stretch as a fuzzy one, and every
;; inflection as a crossing - the whole judgement in a picture, with no
;; table to read.

(defun acc:comb-tips (segs scale / out s k n i u p len)
  (setq out nil)
  (foreach s segs
    (setq k   (acc:seg-curv s)
          n   (max 1 (acc:ceil (/ (acc:seg-len s) acc:*comb-step*)))
          i   0)
    ;; both ends of every segment are sampled, so a joint contributes
    ;; two tips - and where the curvature jumps, they differ.  That
    ;; visible step is the finding, not an artefact.
    (while (<= i n)
      (setq u   (/ (float i) (float n))
            p   (acc:seg-pt s u)
            len (* k scale)
            out (cons (list p (polar p (+ (acc:seg-tan s u) (/ pi 2.0)) len))
                      out)
            i   (1+ i))))
  (reverse out))

(defun acc:draw-comb (res / segs kmax scale tips pts pr)
  (setq segs (acc:val "segs" res)
        kmax 0.0)
  (foreach pr segs
    (setq kmax (max kmax (abs (acc:seg-curv pr)))))
  (if (< kmax 1.0e-12)
    (progn
      (princ "\n  The comb was not drawn: this perimeter is all straight"
             )
      (princ "\n  lines, so every tooth would have zero length.")
      0)
    (progn
      (acc:ensure-layer acc:*comb-layer* 4)
      (acc:purge acc:*comb-layer* "MARK")
      (setq scale (/ acc:*comb-max* kmax)
            tips  (acc:comb-tips segs scale)
            pts   nil)
      (foreach pr tips
        (setq pts (cons (cadr pr) pts))
        ;; a zero-length tooth on a straight run would be a degenerate
        ;; line, so only real teeth are drawn - the envelope still runs
        ;; through the curve there, which is what flat should look like
        (if (> (acc:dist (car pr) (cadr pr)) 1.0e-6)
          (acc:tag
            (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                            (cons 8 acc:*comb-layer*) '(100 . "AcDbLine")
                            (cons 10 (list (car (car pr)) (cadr (car pr)) 0.0))
                            (cons 11 (list (car (cadr pr))
                                           (cadr (cadr pr)) 0.0))))
            "MARK")))
      (setq pts (reverse pts))
      (acc:tag
        (entmakex (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                                (cons 8 acc:*comb-layer*)
                                '(100 . "AcDbPolyline")
                                (cons 90 (length pts)) '(70 . 1))
                          (mapcar '(lambda (q) (cons 10 q)) pts)))
        "MARK")
      (length pts))))

;; ---- asking ----------------------------------------------------------
;; The bracket is built from the initget string, never written a second
;; time: a click on a bracketed option sends that exact text, so the two
;; can never be allowed to drift (STANDARDS section 1).

(defun acc:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'ACC-BACK)
        ((null v) (if dflt dflt (acc:askkw msg kws shown dflt back)))
        (t v)))

;; The bracket is the initget keyword list, built from it and never
;; written a second time: a click on a bracketed option sends that exact
;; text, so any difference between the two makes the click fail
;; (STANDARDS section 1).
(defun acc:ask (msg kws dflt back)
  (acc:askkw msg kws (vl-string-translate " " "/" kws) dflt back))

;; ---- declared discontinuities ----------------------------------------
;; One pick does three jobs: it excuses the joint it lands on, it is
;; checked back against the geometry when it lands on nothing, and what
;; it leaves behind is the undeclared list the report is really about.

(defun acc:declare-loop (declared / done ans p best bd q d)
  (setq done nil)
  (while (not done)
    (princ (strcat "\n  " (itoa (length declared))
                   " discontinuity(ies) declared - breaks that are"
                   " meant to be there."))
    (setq ans (acc:ask "Declared discontinuities" "Add Remove Keep" "Keep" nil))
    (cond
      ((= ans "Add")
       (setq p T)
       (while p
         (setq p (getpoint "\n  Pick a discontinuity (Enter = done): "))
         (if p (setq declared (cons (acc:2d p) declared)))))
      ((= ans "Remove")
       (setq p T)
       (while p
         (setq p (getpoint "\n  Pick the declaration to drop (Enter = done): "))
         (if p
           (progn
             (setq p (acc:2d p) best nil bd nil)
             (foreach q declared
               (setq d (acc:dist p q))
               (if (or (null bd) (< d bd)) (setq bd d best q)))
             (if best
               (setq declared (acc:remove best declared))
               (princ "\n  Nothing declared to drop."))))))
      (T (setq done T))))
  declared)

;; ---- reading the selection -------------------------------------------
;; One polyline carries its own vertex order and is trusted; anything
;; else is loose geometry and gets walked into a ring, gaps and all.

(defun acc:collect (ss / i en all)
  (setq i 0 all nil)
  (repeat (sslength ss)
    (setq en  (ssname ss i)
          all (append all (acc:ent-segs en))
          i   (1+ i)))
  (if (and (= 1 (sslength ss)) (> (length all) 1))
    all
    (acc:chain all)))

(defun acc:select ( / ss)
  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I" '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC,CIRCLE"))))
  (if (null ss)
    (progn
      (princ "\n\nSelect the closed perimeter - one polyline, or the same")
      (princ "\nshape exploded into lines and arcs.")
      (setq ss (ssget '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC,CIRCLE"))))))
  (if (null ss)
    (progn (princ "\nABCURCHECK: nothing selected.") nil)
    ss))

;; ---- housekeeping ----------------------------------------------------

(defun acc:syssave (vars / v)
  (if (not acc:*sysold*)
    (foreach v vars
      (if (/= nil (getvar v))
        (setq acc:*sysold*
              (append acc:*sysold* (list (cons v (getvar v)))))))))

(defun acc:sysrestore ( / p)
  ;; restore runs in the saved order, so OSMODE leads acc:*sysvars* --
  ;; object snaps are the setting the user misses most if a run is ever
  ;; cut short partway
  (foreach p acc:*sysold* (setvar (car p) (cdr p)))
  (setq acc:*sysold* nil))

;; ---- the commands ----------------------------------------------------

;; The measurement both commands share: select, read, ask what is meant
;; to be broken, measure, report.  DRAWP nil is the read-only scan -
;; the declarations already in the drawing still count, they just
;; cannot be edited and nothing new is drawn.
(defun acc:run (drawp / ss segs declared res ans again n)
  (if (setq ss (acc:select))
    (progn
      (setq segs (acc:collect ss))
      (if (< (length segs) 2)
        (princ "\nABCURCHECK: that is one segment - there is no joint to measure.")
        (progn
          (setq declared (acc:read-declared)
                again    T)
          (while again
            (setq again nil)
            (if drawp
              (progn
                (setq declared (acc:declare-loop declared))
                (acc:draw-declared declared)))
            (setq res (acc:measure segs declared))
            (acc:report res)
            (if drawp
              (progn
                (setq n (acc:draw-marks res))
                (princ (strcat "\n\n  " (itoa n) " finding(s) ringed on "
                               acc:*mark-layer* "."))
                (setq ans (acc:ask "Draw the curvature comb?"
                                   "Yes No" "Yes" T))
                (cond
                  ((eq ans 'ACC-BACK) (setq again T))
                  ((= ans "Yes")
                   (setq n (acc:draw-comb res))
                   (if (> n 0)
                     (princ (strcat "\n  Comb drawn on " acc:*comb-layer*
                                    " - " (itoa n)
                                    " teeth; the envelope steps where the"
                                    " curve breaks."))))))))))))
  (princ))

(defun c:ABCURCHECK ( / *error* undo-open)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (acc:sysrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nABCURCHECK error: " msg)))
    (princ))
  (acc:syssave acc:*sysvars*)
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  (acc:run T)
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (acc:sysrestore)
  (princ))

(defun c:ABCURCHECKSCAN ( / *error* undo-open)
  (defun *error* (msg)
    (acc:sysrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nABCURCHECKSCAN error: " msg)))
    (princ))
  (acc:syssave acc:*sysvars*)
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  (acc:run nil)
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (acc:sysrestore)
  (princ))

;; Sweep the marks away again.  Findings and the comb go; the
;; declarations stay unless asked for by name, because they are the
;; user's answers and re-picking them is the one thing this command
;; should never make anyone do twice.
(defun c:ABCURCHECKRESCUE ( / *error* undo-open ans n)
  (defun *error* (msg)
    (acc:sysrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nABCURCHECKRESCUE error: " msg)))
    (princ))
  (acc:syssave acc:*sysvars*)
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  (setq ans (acc:ask "Erase which of ABCURCHECK's objects?"
                     "Marks All" "Marks" nil)
        n   (+ (acc:purge acc:*mark-layer* "MARK")
               (acc:purge acc:*comb-layer* "MARK")))
  (if (= ans "All")
    (setq n (+ n (acc:purge acc:*mark-layer* "DECL"))))
  (princ (strcat "\nABCURCHECKRESCUE: " (itoa n)
                 " of this command's own object(s) erased"
                 (if (= ans "All") "" ", declarations kept") "."))
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (acc:sysrestore)
  (princ))

(defun c:ABCURCHECKVER ()
  (princ (strcat "\nABCURCHECK " *abcurcheck-version* " loaded."))
  (princ))

(princ (strcat "\nABCURCHECK " *abcurcheck-version*
               " loaded.  Type ABCURCHECK to run."))
(princ)
