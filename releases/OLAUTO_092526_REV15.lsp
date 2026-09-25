;;; ======================================================================
;;; OLAUTO.lsp  --  overlay two pool perimeters at the least error, and
;;;                 dimension where they still disagree
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  OLAUTO          overlay two perimeters and dimension the
;;;                            worst error
;;;            OLAUTOVER       print the loaded version
;;; ======================================================================
;;;
;;; The job.  A pool has been measured twice: once when the liner that is
;;; in it now was made (the ORIGINAL, drawn as the bead track the liner
;;; hooks into) and once just now (the NEW perimeter).  The two drawings
;;; are never in the same place on the sheet and never at the same angle,
;;; so before anyone can say whether the new measurement agrees with the
;;; pool that is already there, one has to be laid over the other.
;;;
;;; Laid over HOW is the whole question.  Slide it a little one way and
;;; the deep end lines up while the steps are out by three inches; slide
;;; it back and the fault moves to the other end.  Doing that by eye
;;; means the answer depends on who did the sliding.  OLAUTO does not
;;; slide by eye: it finds the one position -- the one rotation and the
;;; one translation -- where the total disagreement is as small as it can
;;; be made, and then dimensions what is left.
;;;
;;; What is left is the real news.  A perfect overlay with a 3" gap at
;;; the shallow end is not a bad overlay: it is a pool that is 3" out of
;;; shape there, and a liner cut to the new perimeter will fight the
;;; track at that spot.  The dimensions this command draws are that
;;; list, worst first.
;;;
;;; RIGID, never scaled.  The fit may turn and slide the perimeter and
;;; nothing else.  Stretching one outline onto the other would hide the
;;; one error nobody can afford to miss -- a pool measured 2% long --
;;; by absorbing it into the fit.  So a size difference stays a size
;;; difference and shows up in the dimensions where it belongs.
;;;
;;; How the fit is found, in two stages, because the obvious one method
;;; does not work on its own:
;;;
;;;   1. PHASE SEARCH.  Both perimeters are walked out into the same
;;;      number of points spaced evenly BY ARC LENGTH.  Two outlines of
;;;      the same pool then correspond point for point, up to where the
;;;      walk started and which way round it went.  Every starting point
;;;      and both directions are tried -- for each, the best rotation
;;;      and translation follow in closed form, so a whole candidate
;;;      costs one pass and nothing is iterated.  The best of them is
;;;      the starting pose.
;;;   2. ICP POLISH.  From there each point is re-matched to the nearest
;;;      place on the other curve (not to its opposite number) and the
;;;      transform re-solved, over and over until it stops moving.  This
;;;      is what takes the fit from "about right" to the least-squares
;;;      answer.
;;;
;;; Stage 1 exists because stage 2 alone is a local search and a pool is
;;; nearly symmetric: started at the wrong angle it settles happily into
;;; a fit five times worse and reports it as the answer.  Started from
;;; the phase search it lands on the same fit from any angle the two
;;; drawings happen to arrive at, which is the property that makes the
;;; result worth putting a dimension on.
;;;
;;; What it draws.  Nothing, until the fit is found and the perimeter is
;;; moved.  Then one aligned dimension at each of the worst spots --
;;; four by default (ola:*dimcount*) -- each one a local WORST, forced
;;; apart around the perimeter so that four dimensions describe four
;;; problems instead of crowding onto one bad corner.  The error is
;;; measured along the ORIGINAL, which is the one that did not move.
;;;
;;; Workflow
;;;   1. Select the first perimeter -- one polyline, or the same shape
;;;      exploded into lines and arcs.
;;;   2. Select the second.
;;;   3. Say which of the two is the NEW one.  The layers answer this
;;;      when they are the shop's own, so the question comes up already
;;;      answered and Enter takes it.
;;;   4. Say which one should move.  The other stays exactly where it
;;;      is, and by default that is the original -- it is the pool that
;;;      exists, and the rest of the sheet is drawn around it.
;;;   5. OLAUTO fits, moves, re-layers (new onto POOL, original onto
;;;      Bead Track) and dimensions.
;;;
;;; It reports the fit as three numbers -- worst, average and RMS error
;;; -- so two candidate measurements can be compared, and names the
;;; layer everything landed on.
;;; ======================================================================

(setq *olauto-version* "v1.5")       ; announced on load; release_lisp.py
                                     ; reads this banner and stamps the
                                     ; dated twin in releases/ from it

;;; ======================================================================
;;;  TUNABLES -- every value OLAUTO reads that someone might want to
;;;  change lives in this block, and nowhere else in the file.
;;;
;;;  How to change one: edit the value, save, and APPLOAD the file
;;;  again.  To try a value for one session only, type the setq at the
;;;  command line -- e.g. (setq ola:*dimcount* 6) -- because every knob
;;;  is read when the command runs, not when the file loads.
;;;
;;;  Units: distances are drawing units (1 unit = 1 inch on the shop's
;;;  sheets); colours are ACI numbers (1 red, 2 yellow, 3 green, 4 cyan,
;;;  5 blue, 6 magenta, 7 white, 8 grey).
;;; ----------------------------------------------------------------------

;; -- where everything lands ---------------------------------------------

;; The two perimeters are put onto the shop's own layers on the way out,
;; so the sheet reads the same whichever drawing they arrived in.  Point
;; either of these at a layer of your own and that is where they go.
(setq ola:*new-layer*   "POOL")        ; the NEW perimeter ends up here
(setq ola:*og-layer*    "Bead Track")  ; the ORIGINAL ends up here
(setq ola:*dim-layer*   "DIMENSION")   ; and the error dimensions here

;; Colours used only when a layer above has to be CREATED; a layer the
;; drawing already has keeps the colour it has.
(setq ola:*new-color*   3)             ; ACI for a created POOL layer
(setq ola:*og-color*    1)             ; ACI for a created Bead Track
(setq ola:*dim-color*   7)             ; ACI for a created DIMENSION

;; The dimension style the errors are drawn in.  A drawing without it
;; keeps whatever style is current and is told so rather than being
;; given a style it did not ask for.
(setq ola:*dim-style*   "STANDARD INCHES")

;; -- how many errors get dimensioned, and where --------------------------

;; How many of the worst spots to dimension.  Each one is a local worst,
;; so raising this finds the next distinct problem rather than more
;; dimensions on the one already drawn.
(setq ola:*dimcount*    4)             ; dimensions drawn

;; How far apart two dimensions have to be, as a fraction of the
;; perimeter.  This is what stops four dimensions describing one long
;; bad stretch: lower it to let them crowd, raise it to spread them.
(setq ola:*peak-gap*    0.07)          ; fraction of the perimeter

;; An error smaller than this is not worth a dimension and the spot is
;; skipped -- so a fit that came out clean draws two dimensions, or
;; none, instead of four dimensions of nothing.
(setq ola:*peak-min*    0.0625)        ; drawing units (1/16")

;; ...and neither is one this much smaller than the worst error found.
;; A fit always leaves a little residue spread around the perimeter, and
;; without this floor a pool with ONE real 3" fault gets that fault
;; dimensioned and then three more dimensions reading 1/16" -- which
;; says "four problems" about a pool that has one.  Raise it to report
;; only faults of the same order as the worst; set it to 0.0 to let
;; ola:*peak-min* alone decide.
(setq ola:*peak-share*  0.10)          ; fraction of the worst error

;; How far the dimension TEXT is dragged clear of the geometry, as a
;; fraction of the perimeter's bounding-box diagonal.  The gap being
;; measured is an inch or two on a forty-foot pool, so the text cannot
;; live where the dimension line is and be read.
(setq ola:*text-push*   0.045)         ; fraction of the bbox diagonal

;; -- the fit -------------------------------------------------------------

;; Points each perimeter is walked out into for the fit.  The phase
;; search costs this SQUARED, so it is the one knob here that is worth
;; money: 96 is ample for a pool and 48 is enough for a spa.
(setq ola:*fitpts*      96)            ; samples per perimeter

;; Points along the ORIGINAL at which the error is measured once the
;; fit is in.  Higher finds a narrow spike that a coarser walk steps
;; over; the cost is this times the number of segments in the new
;; perimeter.
(setq ola:*devpts*      240)           ; samples along the original

;; How far along the curve the polish may look for a better match, in
;; samples either way.  The phase search hands it a correspondence that
;; is already close, so this only has to cover the sliding the polish
;; itself does.  Widening it costs time and buys nothing; narrowing it
;; below about 3 can pin the fit before it has finished settling.
(setq ola:*icp-win*     6)             ; samples either side

;; The polish stops when no point moved further than this, or after
;; this many passes, whichever comes first.  The tolerance is in
;; drawing units and 0.001" is far below anything a tape can see.
(setq ola:*fit-tol*     0.001)         ; drawing units
(setq ola:*fit-max*     60)            ; passes

;; -- numerical guards (rarely changed) -----------------------------------

;; Closer than this and two ends are the same point -- ABHD's
;; *PF-CHAIN-FUZZ*, so a perimeter reads the same here as it does
;; there.  It is also what decides whether a chain came out CLOSED,
;; which is what puts the cyclic half of the phase search in play.
(setq ola:*fuzz*        1.0e-4)        ; drawing units

;; ...and the gap that still counts as closed, as a fraction of the
;; chain's own length.  Raise it to forgive a rougher rejoin; lower it
;; if a genuinely open run of yours comes back on itself so far that
;; OLAUTO reads it as a loop.  1% is 14" on a forty-foot pool: bigger
;; than any accidental gap, smaller than a break left at the steps.
(setq ola:*close-frac*  0.01)          ; fraction of the chain length

;; -- sanity: is this fit worth believing? --------------------------------
;;
;; OLAUTO will fit ANY two curves -- it has no idea what a pool looks
;; like -- so a mis-pick (the deck edge instead of the bead track) comes
;; back as a confident set of dimensions off a meaningless overlay.
;; These two say so instead.  Both only ever print; neither stops a run,
;; because a pool really can be measured wrong by a lot and that is
;; exactly the run somebody needs the numbers from.

;; How far apart the two PERIMETER LENGTHS may be before the pick itself
;; looks wrong.  Two measurements of one pool agree to a few percent;
;; ten percent is a different outline.
(setq ola:*len-warn*    0.10)          ; fraction of the longer perimeter

;; ...and how big the worst error may be, against the diagonal of the
;; original's bounding box, before the overlay stops meaning anything.
(setq ola:*fit-warn*    0.05)          ; fraction of the bbox diagonal

;; A pick that came in as more than one piece -- a stray deck line or
;; coping arc caught by the window -- is chained end to end with the
;; perimeter and poisons the fit.  A jump between consecutive pieces
;; bigger than this share of the whole chain is called out as a piece.
;; It is looser than ola:*close-frac* on purpose: a skimmer gap of a
;; foot in a forty-foot bead track is one perimeter drawn with a break,
;; not two objects.
(setq ola:*piece-frac*  0.05)          ; fraction of the chain length

;; -- mirror images ----------------------------------------------------------
;;
;; A rigid fit can turn and slide but never flip, so a perimeter that
;; arrived as a MIRROR image -- a survey read from the far side, a DXF
;; brought in with its Y axis reversed -- fits as badly as it possibly
;; can and every dimension is nonsense.  OLAUTO tries the flipped walk
;; as well and, when that fits this much better than the unflipped one,
;; offers to mirror the perimeter before fitting.
(setq ola:*mirror-ratio* 0.5)         ; flipped residual / unflipped, at most

;;; ----------------------------------------------------------------------
;;;  END TUNABLES.  The sysvar list and its snapshot below are not
;;;  knobs: they are what the run puts back on the way out.
;; OSMODE is deliberately NOT in this list.  OLAUTO never
;; changes it, and a list is a promise to WRITE the value back: the run
;; would put its opening snapshot back over any snap the drafter ticked
;; on while it was up -- on a clean exit, with no error involved, which
;; is the likeliest way anyone meets it.  Borrow only what you move.
(setq ola:*sysvars* '("CMDECHO" "CLAYER"))  ; saved and put back
(setq ola:*sysold* nil)                ; the snapshot itself
(setq ola:*odstyle* nil)               ; the dimension style to put back
;;; ======================================================================

;; ---- small 2D vector helpers -----------------------------------------
;; Local copies of the generic library helpers, as the standalone tier
;; requires (STANDARDS section 6): same bodies, this file's prefix.

(defun ola:2d (p) (list (car p) (cadr p)))
(defun ola:dist (a b) (distance (ola:2d a) (ola:2d b)))
(defun ola:v- (a b) (mapcar '- (ola:2d a) (ola:2d b)))
(defun ola:v+ (a b) (mapcar '+ (ola:2d a) (ola:2d b)))
(defun ola:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun ola:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun ola:vlen (v) (sqrt (ola:dot v v)))

(defun ola:unit (v / l)
  (setq v (ola:2d v)
        l (ola:vlen v))
  (if (> l 1e-12) (ola:v* v (/ 1.0 l))))

;; normalize an angle into [0, 2pi)
(defun ola:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

(defun ola:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;; centre of the circle through three points; nil when they are colinear
(defun ola:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
  (setq x1 (car pa) y1 (cadr pa)
        x2 (car pb) y2 (cadr pb)
        x3 (car pc) y3 (cadr pc)
        d  (* 2.0 (+ (* x1 (- y2 y3)) (* x2 (- y3 y1)) (* x3 (- y1 y2)))))
  (if (equal d 0.0 1e-12)
    nil
    (progn
      (setq s1 (+ (* x1 x1) (* y1 y1))
            s2 (+ (* x2 x2) (* y2 y2))
            s3 (+ (* x3 x3) (* y3 y3)))
      (list (/ (+ (* s1 (- y2 y3)) (* s2 (- y3 y1)) (* s3 (- y1 y2))) d)
            (/ (+ (* s1 (- x3 x2)) (* s2 (- x1 x3)) (* s3 (- x2 x1))) d)))))

(defun ola:remove (val lst / out hit x)
  (setq out nil hit nil)
  (foreach x lst
    (if (and (not hit) (eq x val))
      (setq hit T)
      (setq out (cons x out))))
  (reverse out))

;; ---- segment geometry ------------------------------------------------
;; A segment is (startPt endPt bulge), 2D points -- ABHD's shape and
;; ABCURCHECK's, so all three read a drawing the same way.

;; signed sweep of a bulged segment: bulge = tan(sweep/4), positive CCW
(defun ola:sweep (b) (* 4.0 (atan b)))

;; Radius of the arc (A B bulge); nil for a straight segment.
(defun ola:bulge-radius (a b bl / h)
  (if (< (abs bl) 1.0e-9)
    nil
    (progn
      (setq h (/ (ola:dist a b) 2.0))
      (/ (* h (1+ (* bl bl))) (* 2.0 (abs bl))))))

;; Length along a segment -- the chord when straight, the arc otherwise.
(defun ola:seg-len (s / r)
  (setq r (ola:bulge-radius (car s) (cadr s) (caddr s)))
  (if r
    (* r (abs (ola:sweep (caddr s))))
    (ola:dist (car s) (cadr s))))

;; Arc geometry of a bulged segment: (center radius angStart), nil when
;; the segment is straight.
(defun ola:arc-geom (s / p1 p2 b ch dir apex c)
  (setq p1 (ola:2d (car s))
        p2 (ola:2d (cadr s))
        b  (caddr s))
  (if (or (< (abs b) 1.0e-9)
          (< (setq ch (ola:dist p1 p2)) 1.0e-12))
    nil
    (progn
      (setq dir  (ola:v* (ola:v- p2 p1) (/ 1.0 ch))
            ;; sagitta = (chord/2)*bulge; a positive (CCW) bulge apex
            ;; lies to the RIGHT of the p1->p2 chord direction
            apex (ola:v+ (ola:v* (ola:v+ p1 p2) 0.5)
                         (ola:v* (list (- (cadr dir)) (car dir))
                                 (* -0.5 ch b)))
            c    (ola:circumcenter p1 apex p2))
      (if (null c)
        nil
        (list c (ola:dist c p1) (angle c p1))))))

;; The point at parameter U (0..1) along a segment.  U is arc length on
;; an arc as much as on a line -- the sweep is proportional to it --
;; which is what lets the walk below space its samples evenly.
(defun ola:seg-pt (s u / gm)
  (setq gm (ola:arc-geom s))
  (if (null gm)
    (ola:v+ (ola:2d (car s))
            (ola:v* (ola:v- (cadr s) (car s)) u))
    (polar (car gm) (+ (caddr gm) (* u (ola:sweep (caddr s)))) (cadr gm))))

;; The point of the straight span A->B nearest to P.  Written out rather
;; than called through the segment form because this is the inner loop
;; of the polish, run tens of thousands of times in a fit.
(defun ola:chord-close (a b p / vx vy wx wy l2 u)
  (setq vx (- (car b) (car a))   vy (- (cadr b) (cadr a))
        wx (- (car p) (car a))   wy (- (cadr p) (cadr a))
        l2 (+ (* vx vx) (* vy vy))
        u  (if (< l2 1.0e-18) 0.0 (/ (+ (* wx vx) (* wy vy)) l2)))
  (cond ((< u 0.0) (setq u 0.0)) ((> u 1.0) (setq u 1.0)))
  (list (+ (car a) (* u vx)) (+ (cadr a) (* u vy))))

;; A segment PREPARED for repeated measurement: the segment, its arc
;; geometry worked out once, and its two endpoints.  ola:profile
;; measures every sample against every segment, so working the arc out
;; inside that double loop -- a circumcentre each time -- would be most
;; of what the command costs.
(defun ola:prep (segs)
  (mapcar '(lambda (s)
             (list s (ola:arc-geom s) (ola:2d (car s)) (ola:2d (cadr s))))
          segs))

;; The point on a prepared segment nearest to P -- exactly, on the arc
;; itself rather than on a chord standing in for it.  On an arc that is
;; where the line from the centre through P crosses it, unless P is off
;; the end of the sweep, and then it is the nearer end.
(defun ola:pclose (ps p / gm s c r a0 th da q)
  (setq s  (car ps)
        gm (cadr ps)
        p  (ola:2d p))
  (if (null gm)
    (ola:chord-close (caddr ps) (cadddr ps) p)
    (progn
      (setq c  (car gm)
            r  (cadr gm)
            a0 (caddr gm)
            th (ola:sweep (caddr s)))
      (if (< (ola:dist c p) 1.0e-12)
        ;; dead on the centre: every point of the arc is as near as
        ;; every other, so hand back the one at the start
        (polar c a0 r)
        (progn
          (setq da (ola:angnorm (- (angle c p) a0)))
          ;; fold DA onto the same side of zero the sweep runs
          (if (< th 0.0) (setq da (- da pi pi)))
          (if (if (< th 0.0) (>= da th) (<= da th))
            (polar c (angle c p) r)
            ;; off the end: whichever end is nearer
            (progn
              (setq q (polar c (+ a0 th) r))
              (if (< (ola:dist p (caddr ps)) (ola:dist p q))
                (caddr ps)
                q))))))))

;; ---- entity -> segment extraction ------------------------------------

(defun ola:lw-segs (ed / pts bls item segs n closed cur nxt bl)
  (setq pts nil bls nil)
  (foreach item ed
    (cond
      ((= (car item) 10)
       (setq pts (cons (ola:2d (cdr item)) pts)
             bls (cons 0.0 bls)))
      ((and (= (car item) 42) bls)
       (setq bls (cons (cdr item) (cdr bls))))))
  (setq pts    (reverse pts)
        bls    (reverse bls)
        closed (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
        segs   nil)
  ;; walked with two pointers rather than (nth n pts): nth is a walk of
  ;; its own, and a traced perimeter can carry a few hundred vertices
  (setq cur pts nxt (cdr pts) n bls)
  (while nxt
    (setq segs (cons (list (car cur) (car nxt) (car n)) segs)
          cur  nxt
          nxt  (cdr nxt)
          n    (cdr n)))
  ;; The closing span of a CLOSED polyline is real geometry and carries
  ;; the last vertex's bulge; an OPEN one is left open, and the walk
  ;; below will simply find the chain unclosed.
  (if (and closed (> (length pts) 1)
           (>= (ola:dist (last pts) (car pts)) ola:*fuzz*))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun ola:pl-segs (en / ed sub pts bls segs closed cur nxt n)
  ;; heavy (old-style) 2D POLYLINE: walk its VERTEX sub-entities
  (setq ed     (entget en)
        closed (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
        pts    nil
        bls    nil
        sub    (entnext en))
  (while (and sub (= "VERTEX" (cdr (assoc 0 (setq ed (entget sub))))))
    ;; skip spline/fit control vertices (flag bits 1 and 16)
    (if (= 0 (logand 17 (cond ((cdr (assoc 70 ed))) (0))))
      (setq pts (cons (ola:2d (cdr (assoc 10 ed))) pts)
            bls (cons (cond ((cdr (assoc 42 ed))) (0.0)) bls)))
    (setq sub (entnext sub)))
  (setq pts (reverse pts) bls (reverse bls) segs nil)
  (setq cur pts nxt (cdr pts) n bls)
  (while nxt
    (setq segs (cons (list (car cur) (car nxt) (car n)) segs)
          cur  nxt
          nxt  (cdr nxt)
          n    (cdr n)))
  (if (and closed (> (length pts) 1)
           (>= (ola:dist (last pts) (car pts)) ola:*fuzz*))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun ola:ent-segs (en / ed typ c r a1 a2 delta)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (ola:2d (cdr (assoc 10 ed)))
                 (ola:2d (cdr (assoc 11 ed)))
                 0.0)))
    ((= typ "ARC")
     (setq c     (ola:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           a1    (cdr (assoc 50 ed))
           a2    (cdr (assoc 51 ed))
           delta (ola:angnorm (- a2 a1)))
     (if (< delta 1.0e-10) (setq delta (* 2.0 pi)))
     ;; a full-circle arc cannot be one bulged segment (its bulge is
     ;; infinite): hand back two semicircles instead
     (if (> delta (- (* 2.0 pi) 1.0e-9))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r) (ola:tan (/ delta 4.0))))))
    ;; a CIRCLE is a legitimate perimeter (a round spa): two semicircles,
    ;; so the walk sees a normal closed loop instead of a gap
    ((= typ "CIRCLE")
     (setq c (ola:2d (cdr (assoc 10 ed)))
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
    ((= typ "LWPOLYLINE") (ola:lw-segs ed))
    ((= typ "POLYLINE") (ola:pl-segs en))
    (T nil)))

;; ---- ordering loose segments into a ring -----------------------------
;; ABCURCHECK's acc:chain, and for the same reason: a perimeter handed
;; over as loose arcs and lines has no order of its own, so one is made
;; by always walking to whichever end is nearest, reversing the segment
;; when it is its far end that is nearer.

(defun ola:chain (segs / loop cur rest best orig bd s d dr)
  (if (null segs)
    nil
    (progn
      (setq loop (list (car segs))
            cur  (cadr (car segs))
            rest (cdr segs))
      (while rest
        (setq best nil orig nil bd nil)
        (foreach s rest
          (setq d  (ola:dist cur (car s))
                dr (ola:dist cur (cadr s)))
          (if (or (null bd) (< d bd))
            (setq bd d best s orig s))
          (if (< dr bd)
            (setq bd   dr
                  best (list (cadr s) (car s) (- (caddr s)))
                  orig s)))
        (setq loop (cons best loop)
              cur  (cadr best)
              rest (ola:remove orig rest)))
      (reverse loop))))

;; The pieces a chain is really in: one more than the number of jumps
;; between consecutive segments that are bigger than ola:*piece-frac*
;; of the whole, and the biggest such jump.  Returns (pieces jump).
(defun ola:chain-pieces (segs / L tol n big prev s d)
  (setq L    (ola:chain-len segs)
        tol  (* ola:*piece-frac* L)
        n    1
        big  0.0
        prev nil)
  (foreach s segs
    (if prev
      (progn
        (setq d (ola:dist (cadr prev) (car s)))
        (if (> d tol) (setq n (1+ n)))
        (if (> d big) (setq big d))))
    (setq prev s))
  (list n big))

;; Total length of a chain.
(defun ola:chain-len (segs / L s)
  (setq L 0.0)
  (foreach s segs (setq L (+ L (ola:seg-len s))))
  L)

;; T when the chain comes back to where it started -- judged against the
;; chain's OWN length, not against an absolute fuzz.
;;
;; This is not fussiness.  A perimeter exploded and rejoined by hand is
;; riddled with sub-1/16" gaps (ABCURCHECK exists to find them), and a
;; gap of a twentieth of an inch on a fifty-foot pool is a drawing
;; defect, not an open run.  But CLOSED is what puts the cyclic half of
;; the phase search in play, and without that half the two walks have to
;; start at corresponding points or no alignment can be found at all.
;; Measured, with an absolute 1e-4 tolerance: a 0.05" gap in a 640"
;; outline that was also drawn the other way round fitted 55.7 units
;; out, where the same pair with the cyclic search running fitted to
;; 0.002.  So the test is relative, and an accidental gap stays closed
;; while a bead track that really stops at the steps -- ends a good
;; fraction of the loop apart -- still reads open.
(defun ola:closed-p (segs / L)
  (and segs
       (< (ola:dist (car (car segs)) (cadr (last segs)))
          (max ola:*fuzz* (* ola:*close-frac* (ola:chain-len segs))))))

;; ---- walking a chain out into evenly spaced points --------------------
;; Evenly spaced BY ARC LENGTH, which is the whole trick behind the
;; phase search: two outlines of one pool, walked this way, line up
;; point for point wherever the walks happen to have started.
;;
;; A closed chain gets N points around the loop (the last one does not
;; repeat the first); an open one gets N points from end to end.

(defun ola:walk (segs n closed / L step out k t0 acc s rest slen u)
  (setq L (ola:chain-len segs))
  (if (or (null segs) (< L 1.0e-9) (< n 2))
    nil
    (progn
      (setq step (/ L (float (if closed n (1- n))))
            out  nil
            k    0
            acc  0.0
            rest segs
            s    (car segs)
            slen (ola:seg-len s))
      (while (< k n)
        (setq t0 (* step k))
        ;; advance to the segment this distance falls in.  The walk only
        ;; ever moves forward, so the whole of it costs one pass over
        ;; the chain, not one pass per sample.
        (while (and (cdr rest) (> t0 (+ acc slen)))
          (setq acc  (+ acc slen)
                rest (cdr rest)
                s    (car rest)
                slen (ola:seg-len s)))
        (setq u (if (< slen 1.0e-12) 0.0 (/ (- t0 acc) slen)))
        (cond ((< u 0.0) (setq u 0.0)) ((> u 1.0) (setq u 1.0)))
        (setq out (cons (ola:seg-pt s u) out)
              k   (1+ k)))
      (reverse out))))

;; ---- the transform ----------------------------------------------------
;; One is (angle dx dy), meaning "turn by ANGLE about the origin, then
;; move by (DX DY)".  Kept this way because they COMPOSE: the fit is a
;; phase search followed by dozens of polish steps, and the entities in
;; the drawing are moved once, by the product of all of them, rather
;; than dragged through every intermediate pose.

(defun ola:xid () (list 0.0 0.0 0.0))

(defun ola:xapply (x p / c s)
  (setq c (cos (car x)) s (sin (car x)) p (ola:2d p))
  (list (+ (- (* c (car p)) (* s (cadr p))) (cadr x))
        (+ (+ (* s (car p)) (* c (cadr p))) (caddr x))))

;; The step "turn by TH about CA, then put CA onto CB" as one of the
;; above.
(defun ola:xstep (th ca cb / c s)
  (setq c (cos th) s (sin th))
  (list th
        (- (car cb)  (- (* c (car ca)) (* s (cadr ca))))
        (- (cadr cb) (+ (* s (car ca)) (* c (cadr ca))))))

;; X1 and then X2, as one transform.
(defun ola:xthen (x1 x2 / c s)
  (setq c (cos (car x2)) s (sin (car x2)))
  (list (+ (car x1) (car x2))
        (+ (- (* c (cadr x1)) (* s (caddr x1))) (cadr x2))
        (+ (+ (* s (cadr x1)) (* c (caddr x1))) (caddr x2))))

;; ---- the fit ----------------------------------------------------------

(defun ola:centroid (pts / sx sy n p)
  (setq sx 0.0 sy 0.0 n 0)
  (foreach p pts
    (setq sx (+ sx (car p)) sy (+ sy (cadr p)) n (1+ n)))
  (if (= n 0) nil (list (/ sx n) (/ sy n))))

;; The rigid transform taking the paired points A onto B, in closed
;; form -- the 2D Kabsch solution.  Rotation only: no scale term is
;; computed and none is applied, which is the promise in the header.
(defun ola:kabsch (a b / ca cb sxx sxy pa pb ax ay bx by)
  (setq ca  (ola:centroid a)
        cb  (ola:centroid b)
        sxx 0.0
        sxy 0.0
        pa  a
        pb  b)
  (while pa
    (setq ax (- (car (car pa)) (car ca))   ay (- (cadr (car pa)) (cadr ca))
          bx (- (car (car pb)) (car cb))   by (- (cadr (car pb)) (cadr cb))
          sxx (+ sxx (* ax bx) (* ay by))
          sxy (+ sxy (- (* ax by) (* ay bx)))
          pa  (cdr pa)
          pb  (cdr pb)))
  (ola:xstep (if (and (equal sxx 0.0 1e-15) (equal sxy 0.0 1e-15))
               0.0
               (atan sxy sxx))
             ca cb))

;; PHASE SEARCH.  A and B are the two walks, the same length.  Every
;; starting offset and both directions are scored; the winner is the
;; one whose best rotation leaves the least squared error, and because
;; the two point sets and their centroids do not change as the offset
;; slides, that reduces to the largest (sxx^2 + sxy^2) -- one pass each
;; and no iteration anywhere.
;;
;; Returns (transform fixed-reordered), the second being B renumbered so
;; that its point J is the one facing A's point J.  The polish then has
;; its correspondence for free.
(defun ola:phase (a b closed / n ca cb ac bc rev bd bb pa qb sxx sxy m
                               best bestk bestrev k lim saa sbb p)
  (setq n    (length a)
        ca   (ola:centroid a)
        cb   (ola:centroid b)
        ;; centred once; the centroids are the same for every offset and
        ;; either direction, because the point SET never changes
        ac   (mapcar '(lambda (p) (ola:v- p ca)) a)
        best nil bestk 0 bestrev 0
        rev  0
        lim  (if closed n 1)
        saa  0.0
        sbb  0.0)
  ;; the two self-terms of the residual, once: they do not move either
  (foreach p ac (setq saa (+ saa (ola:dot p p))))
  (foreach p b  (setq p (ola:v- p cb) sbb (+ sbb (ola:dot p p))))
  (while (< rev 2)
    (setq bd (if (= rev 0) b (reverse b))
          bc (mapcar '(lambda (p) (ola:v- p cb)) bd)
          ;; doubled, so an offset is a cdr rather than an index
          bb (append bc bc)
          k  0)
    (while (< k lim)
      (setq pa ac qb bb sxx 0.0 sxy 0.0)
      (while pa
        (setq sxx (+ sxx (* (car (car pa)) (car (car qb)))
                         (* (cadr (car pa)) (cadr (car qb))))
              sxy (+ sxy (- (* (car (car pa)) (cadr (car qb)))
                            (* (cadr (car pa)) (car (car qb)))))
              pa  (cdr pa)
              qb  (cdr qb)))
      (setq m (+ (* sxx sxx) (* sxy sxy)))
      (if (or (null best) (> m best))
        (setq best m bestk k bestrev rev))
      (setq bb (cdr bb)
            k  (1+ k)))
    (setq rev (1+ rev)))
  ;; rebuild the winner and solve it once more for the transform itself
  (setq bd (if (= bestrev 0) b (reverse b))
        bb (append bd bd)
        qb bb
        k  0)
  (while (< k bestk) (setq qb (cdr qb) k (1+ k)))
  (setq bd nil k 0)
  (while (< k n) (setq bd (cons (car qb) bd) qb (cdr qb) k (1+ k)))
  (setq bd (reverse bd))
  ;; The residual the winner leaves, as an RMS over the walk: with the
  ;; best rotation applied the summed squared error is
  ;; sum|a|^2 + sum|b|^2 - 2 sqrt(sxx^2 + sxy^2), and that is what the
  ;; mirror test compares between the flipped walk and the unflipped.
  (list (ola:kabsch a bd) bd
        (sqrt (/ (max 0.0 (- (+ saa sbb) (* 2.0 (sqrt best)))) n))))

;; ICP POLISH.  Re-match every point to the nearest place on the fixed
;; walk, re-solve, repeat until nothing moves.  Returns the transform
;; that carries the phase-search pose the rest of the way in.
;;
;; The match for point J is looked for only among the spans within
;; ola:*icp-win* of span J -- the phase search has already put J beside
;; its opposite number, and the polish never slides a correspondence
;; more than a sample or two from there.  So the window sits on J
;; itself rather than chasing the last match, and the whole pass walks
;; ONE pointer down a doubled copy of the fixed walk: no indexing, and
;; no re-walking the list for every sample.
(defun ola:polish (a bs closed / n win cur pass corr shift new acc
                                 bb wp j p q best bd cand nxt step
                                 lim head)
  (setq n    (length a)
        win  (max 1 (fix ola:*icp-win*))
        cur  a
        acc  (ola:xid)
        pass 0
        shift (* 2.0 ola:*fit-tol*))
  (if (>= (* 2 win) (- n 2)) (setq win (max 1 (/ (- n 2) 2))))
  ;; a closed walk wraps, so three copies laid end to end let the window
  ;; start WIN before the first sample and still read a span past the
  ;; last; an open one simply clamps at its two ends.  Built once: the
  ;; fixed walk does not move, only the one being fitted to it does.
  (setq bb  (if closed (append bs bs bs) bs)
        lim (- n 2 win))
  (while (and (< pass ola:*fit-max*) (> shift ola:*fit-tol*))
    (setq wp bb
          j  (if closed (- n win) 0))
    (while (> j 0) (setq wp (cdr wp) j (1- j)))
    (setq corr nil
          p    cur
          j    0)
    (while p
      (setq head wp
            best nil
            cand (1+ (* 2 win)))
      ;; measure against the spans of the window, in order
      (while (and (> cand 0) (cdr head))
        (setq q  (ola:chord-close (car head) (cadr head) (car p))
              bd (ola:dist (car p) q))
        (if (or (null best) (< bd (car best))) (setq best (list bd q)))
        (setq head (cdr head)
              cand (1- cand)))
      (setq corr (cons (cadr best) corr)
            p    (cdr p)
            j    (1+ j))
      ;; the window start never moves backwards, so it is one cdr a
      ;; sample -- and on an open walk it holds still at both ends,
      ;; where there are no spans beyond to slide onto
      (if (or closed (and (> j win) (<= j lim)))
        (setq wp (cdr wp))))
    (setq corr (reverse corr)
          step (ola:kabsch cur corr)
          new  (mapcar '(lambda (v) (ola:xapply step v)) cur)
          acc  (ola:xthen acc step)
          shift 0.0
          p    cur)
    (foreach nxt new
      (setq shift (max shift (ola:dist nxt (car p)))
            p     (cdr p)))
    (setq cur new
          pass (1+ pass)))
  acc)

;; Does MSEG fit FSEG far better as a mirror image than as itself?
;;
;; Run the phase search twice, once on the walk and once on the walk
;; with its X reversed, and compare what each leaves behind.  A shape
;; with a mirror line of its own -- a rectangle, a round spa -- leaves
;; the same residual both ways, so the flipped one has to be BETTER by
;; ola:*mirror-ratio* before anything is said, and the unflipped
;; residual has to be more than sampling noise to begin with.
;;
;; Returns (unflipped-rms flipped-rms) when the mirror is the better
;; fit, nil otherwise.
(defun ola:mirror-p (mseg fseg / n closed a b r0 r1 span)
  (setq n      (max 8 (fix ola:*fitpts*))
        closed (and (ola:closed-p mseg) (ola:closed-p fseg))
        a      (ola:walk mseg n closed)
        b      (ola:walk fseg n closed))
  (if (and a b)
    (progn
      (setq r0   (caddr (ola:phase a b closed))
            r1   (caddr (ola:phase (mapcar '(lambda (p) (list (- (car p)) (cadr p)))
                                           a)
                                   b closed))
            span (ola:span fseg))
      (if (and (> r0 (* 0.01 span))
               (< r1 (* ola:*mirror-ratio* r0)))
        (list r0 r1)))))

;; Reflect a chain about the vertical line x = X0: every point goes
;; across, and every bulge changes sign because a reflection runs each
;; arc the other way round.
(defun ola:mirror-segs (segs x0)
  (mapcar '(lambda (s)
             (list (list (- (* 2.0 x0) (car (car s))) (cadr (car s)))
                   (list (- (* 2.0 x0) (car (cadr s))) (cadr (cadr s)))
                   (- (caddr s))))
          segs))

;; ...and one entity, in place.  An ARC is the one that needs thought:
;; reflecting turns the direction angle t into pi - t and runs the
;; sweep the other way, and an AutoCAD arc always goes counter-
;; clockwise from 50 to 51, so the reflected arc starts where the old
;; END was reflected to and ends at the old START's reflection.
(defun ola:mirror-ed (ed x0 / out item code p a0 a1)
  (setq out nil)
  (foreach item ed
    (setq code (car item))
    (setq out
          (cons
            (cond
              ((member code '(10 11))
               (setq p (cdr item))
               (cons code (append (list (- (* 2.0 x0) (car p)) (cadr p))
                                  (if (caddr p) (list (caddr p)) nil))))
              ((= code 42) (cons 42 (- (cdr item))))
              (T item))
            out)))
  (setq out (reverse out))
  (if (and (assoc 50 out) (assoc 51 out))
    (progn
      (setq a0 (cdr (assoc 50 out))
            a1 (cdr (assoc 51 out)))
      (setq out (subst (cons 50 (ola:angnorm (- pi a1))) (assoc 50 out) out)
            out (subst (cons 51 (ola:angnorm (- pi a0))) (assoc 51 out) out))))
  out)

(defun ola:mirror-ent (en x0 / ed typ sub)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "POLYLINE")
     (setq sub (entnext en))
     (while (and sub (= "VERTEX" (cdr (assoc 0 (entget sub)))))
       (entmod (ola:mirror-ed (entget sub) x0))
       (setq sub (entnext sub)))
     (entupd en))
    (T (entmod (ola:mirror-ed ed x0)))))

(defun ola:mirror-ss (ss x0 / i)
  (setq i 0)
  (repeat (sslength ss)
    (ola:mirror-ent (ssname ss i) x0)
    (setq i (1+ i))))

;; The whole fit: walk both, phase-search, polish.  Returns the
;; transform that carries MSEG's perimeter onto FSEG's.
;; (Neither argument is called FIX: that is the built-in this defun
;; needs two lines down, and a local of the same name would shadow it.)
(defun ola:fit (mseg fseg / n closed a b ph x1 bs x2)
  (setq n      (max 8 (fix ola:*fitpts*))
        closed (and (ola:closed-p mseg) (ola:closed-p fseg))
        a      (ola:walk mseg n closed)
        b      (ola:walk fseg n closed))
  (if (or (null a) (null b))
    nil
    (progn
      (setq ph (ola:phase a b closed)
            x1 (car ph)
            bs (cadr ph)
            a  (mapcar '(lambda (p) (ola:xapply x1 p)) a)
            x2 (ola:polish a bs closed))
      (ola:xthen x1 x2))))

;; ---- moving the drawing to match --------------------------------------
;; The entities are rewritten in place with entmod rather than driven
;; through MOVE and ROTATE: two commands would round the geometry twice
;; through the command line and leave the result depending on snaps and
;; on the current UCS.  A rigid transform leaves a bulge alone -- it is
;; a shape, not a position -- so only points and arc angles move.

(defun ola:xform-ed (x ed / out item code p q)
  (setq out nil)
  (foreach item ed
    (setq code (car item))
    (setq out
          (cons
            (cond
              ;; every point group a curve of ours carries.  A LINE's
              ;; are 3D and an LWPOLYLINE's are 2D, so whatever third
              ;; ordinate came in goes back out: handing entmod a
              ;; flattened point would quietly drop the elevation of a
              ;; perimeter drawn off the Z zero.
              ((member code '(10 11))
               (setq p (cdr item)
                     q (ola:xapply x p))
               (cons code (if (caddr p) (append q (list (caddr p))) q)))
              ;; arc start/end angles turn with it
              ((member code '(50 51))
               (cons code (ola:angnorm (+ (cdr item) (car x)))))
              (T item))
            out)))
  (reverse out))

(defun ola:xform-ent (x en / ed typ sub)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ;; a heavy POLYLINE keeps its points in VERTEX sub-entities, and the
    ;; header itself carries a 10 that is an elevation, not a position
    ((= typ "POLYLINE")
     (setq sub (entnext en))
     (while (and sub (= "VERTEX" (cdr (assoc 0 (entget sub)))))
       (entmod (ola:xform-ed x (entget sub)))
       (setq sub (entnext sub)))
     (entupd en))
    (T (entmod (ola:xform-ed x ed)))))

(defun ola:xform-ss (x ss / i)
  (setq i 0)
  (repeat (sslength ss)
    (ola:xform-ent x (ssname ss i))
    (setq i (1+ i))))

;; ---- where the two still disagree -------------------------------------

;; The error at each of DEVPTS points along the ORIGINAL: how far that
;; point is from the new perimeter.  Measured on the original because
;; the original is the one that did not move -- the dimensions then hang
;; off geometry that is still exactly where the drawing put it.
;;
;; Each sample is measured against every segment of the new perimeter,
;; on the real arcs rather than on a chord standing in for them, so a
;; reading is the true distance and not a sampling of one.
(defun ola:profile (og new / n closed pts ps out p best s q d)
  (setq n      (max 8 (fix ola:*devpts*))
        closed (ola:closed-p og)
        pts    (ola:walk og n closed)
        ;; the arcs of the new perimeter are worked out ONCE, here,
        ;; rather than inside the double loop below
        ps     (ola:prep new)
        out    nil)
  (foreach p pts
    (setq best nil)
    (foreach s ps
      (setq q (ola:pclose s p)
            d (ola:dist p q))
      (if (or (null best) (< d (car best)))
        (setq best (list d p q))))
    (setq out (cons best out)))
  (reverse out))

;; The worst spots, worst first.  Taken greedily: the biggest error
;; anywhere, then the biggest that is still GAPN samples clear of it,
;; and so on.  The separation is what makes four dimensions describe
;; four problems -- without it one long bad stretch takes every slot
;; and the other three faults on the pool go undrawn.  WANT at most,
;; and a spot is skipped when it is under ola:*peak-min* outright or
;; under ola:*peak-share* of the worst error there is, which is what
;; keeps the fit's own residue from being dimensioned as a finding.
(defun ola:peaks (prof want closed / n gapn out taken i v ok j k
                                     bestd besti more floor)
  (setq n     (length prof)
        gapn  (max 1 (fix (* n ola:*peak-gap*)))
        out   nil
        taken nil
        more  T
        floor 0.0)
  (foreach v prof (setq floor (max floor (car v))))
  (setq floor (max ola:*peak-min* (* floor ola:*peak-share*)))
  (while (and more (< (length out) want))
    (setq i 0 bestd nil besti nil)
    (foreach v prof
      (setq v (car v))
      (if (and (>= v floor) (or (null bestd) (> v bestd)))
        (progn
          (setq ok T)
          (foreach j taken
            (setq k (abs (- i j)))
            ;; round a closed perimeter the two ends of the profile are
            ;; neighbours, so the separation is measured the short way
            (if (and closed (> k (/ n 2))) (setq k (- n k)))
            (if (< k gapn) (setq ok nil)))
          (if ok (setq bestd v besti i))))
      (setq i (1+ i)))
    (if besti
      (setq out   (cons (nth besti prof) out)
            taken (cons besti taken))
      (setq more nil)))
  (reverse out))

;; ---- layers and drawing ------------------------------------------------

(defun ola:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nOLAUTO: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;; Put one entity onto a layer.
(defun ola:relayer-ent (en name / ed)
  (setq ed (entget en))
  (if (assoc 8 ed)
    (entmod (subst (cons 8 name) (assoc 8 ed) ed))))

;; Put a whole selection onto a layer.  A heavy POLYLINE carries a layer
;; on every VERTEX as well as on its header, so those move too -- left
;; behind, they say one thing where the polyline says another, and a
;; later sweep that reads vertices rather than headers reads the old
;; answer.
(defun ola:relayer (ss name / i en sub)
  (setq i 0)
  (repeat (sslength ss)
    (setq en (ssname ss i))
    (ola:relayer-ent en name)
    (if (= "POLYLINE" (cdr (assoc 0 (entget en))))
      (progn
        (setq sub (entnext en))
        (while (and sub (member (cdr (assoc 0 (entget sub)))
                                '("VERTEX" "SEQEND")))
          (ola:relayer-ent sub name)
          (setq sub (entnext sub)))
        (entupd en)))
    (setq i (1+ i))))

;; How many entities the two selections have in common.
;;
;; Worth counting, because picking one perimeter twice is a mis-pick
;; that LOOKS like the best possible news: a curve fitted to itself
;; reports a perfect overlay and nothing to dimension, which is the one
;; answer a drafter will not question.  And where the sets only overlap
;; in part, the shared entity is moved by the fit while still being
;; read as the thing that held still, so the reference the dimensions
;; hang off is quietly wrong.
(defun ola:ss-shared (ssa ssb / i n en)
  (setq i 0 n 0)
  (repeat (sslength ssa)
    (setq en (ssname ssa i))
    (if (ssmemb en ssb) (setq n (1+ n)))
    (setq i (1+ i)))
  n)

;; The first entity in SS that is NOT drawn in the world XY plane, or
;; nil when they all are.
;;
;; Everything below reads group 10 as a world coordinate.  For a LINE
;; that is true whatever its extrusion, but an ARC, CIRCLE or POLYLINE
;; keeps its points in the OBJECT plane, and a mirrored one (extrusion
;; 0,0,-1) has its X axis reversed against the world.  Read that as
;; world and the outline comes out mirrored -- so the fit would be
;; computed on geometry that is not what is on the screen, and the move
;; written back through the same mistake.  Nothing downstream can
;; notice, which is why it is caught here.
(defun ola:ss-not-flat (ss / i en ed ex typ)
  (setq i 0)
  (while (and (< i (sslength ss)) (not typ))
    (setq ed  (entget (setq en (ssname ss i)))
          ex  (cdr (assoc 210 ed)))
    (if (and ex
             (member (cdr (assoc 0 ed))
                     '("ARC" "CIRCLE" "LWPOLYLINE" "POLYLINE"))
             (not (and (equal (car ex) 0.0 1e-8)
                       (equal (cadr ex) 0.0 1e-8)
                       (equal (caddr ex) 1.0 1e-8))))
      (setq typ (cdr (assoc 0 ed))))
    (setq i (1+ i)))
  typ)

;; The locked layers a selection sits on, added to OUT, each once.
;; OLAUTO writes to everything picked -- the moving perimeter is moved,
;; both are put on the shop's layers -- and entmod refuses an object on
;; a locked layer by answering nil.  Nothing read that answer, so the
;; fit, the deviation dimensions and the report all went ahead off the
;; copy in memory as if the perimeter had moved, while the drawing still
;; showed it where it was.  The selection is walked, not the layer
;; table: a locked layer with nothing picked on it is in nobody's way.
(defun ola:ss-locked (ss out / i lay rec)
  (setq i 0)
  (repeat (sslength ss)
    (setq lay (cdr (assoc 8 (entget (ssname ss i)))))
    (if (and lay
             (not (member (strcase lay) (mapcar 'strcase out)))
             (setq rec (tblsearch "LAYER" lay))
             (= 4 (logand 4 (cond ((cdr (assoc 70 rec))) (0)))))
      (setq out (append out (list lay))))
    (setq i (1+ i)))
  out)

;; "A", "B" and "C" -- layer names for a sentence.
(defun ola:names (lst / out n lay)
  (setq out "" n (length lst))
  (foreach lay lst
    (setq out (strcat out
                      (cond ((= out "") "")
                            ((= n 1) " and ")
                            (T ", "))
                      "\"" lay "\"")
          n   (1- n)))
  out)

;; The dominant layer of a selection -- what the new/original question
;; is answered with before it is asked.
(defun ola:ss-layer (ss / i counts en lay hit best bestn p)
  (setq i 0 counts nil)
  (repeat (sslength ss)
    (setq en  (ssname ss i)
          lay (cdr (assoc 8 (entget en)))
          hit (assoc lay counts))
    (if hit
      (setq counts (subst (cons lay (1+ (cdr hit))) hit counts))
      (setq counts (cons (cons lay 1) counts)))
    (setq i (1+ i)))
  (setq best nil bestn 0)
  (foreach p counts
    (if (> (cdr p) bestn) (setq best (car p) bestn (cdr p))))
  best)

;; What a chain spans, as (lower-left upper-right).  The midpoint of an
;; arc is taken as well as its ends: an arc bulges past both of them,
;; and a box drawn round the ends alone would be too small by the
;; sagitta on every curve in the pool.
(defun ola:bbox (segs / lo hi s p)
  (setq lo nil hi nil)
  (foreach s segs
    (foreach p (list (car s) (cadr s) (ola:seg-pt s 0.5))
      (if (null lo)
        (setq lo (ola:2d p) hi (ola:2d p))
        (setq lo (list (min (car lo) (car p)) (min (cadr lo) (cadr p)))
              hi (list (max (car hi) (car p)) (max (cadr hi) (cadr p)))))))
  (if lo (list lo hi)))

;; Its diagonal -- the scale everything drawn is sized against, so a
;; dimension reads the same on a spa and on a pool.
(defun ola:span (segs / bb)
  (if (setq bb (ola:bbox segs)) (ola:dist (car bb) (cadr bb)) 0.0))

;; ...and its middle, which is the side of a dimension the text is
;; pushed AWAY from.
(defun ola:middle (segs / bb)
  (if (setq bb (ola:bbox segs))
    (ola:v* (ola:v+ (car bb) (cadr bb)) 0.5)
    '(0.0 0.0)))

;; One error dimension: from the point on the original to the point on
;; the new perimeter, with the text dragged clear along the line the two
;; make, because the gap itself is an inch on a forty-foot pool and
;; nothing would be readable sitting on it.
(defun ola:dim (pog pnew push mid / pre new dir loc a b)
  (setq pre (entlast)
        dir (ola:unit (ola:v- pnew pog)))
  ;; a zero-length gap has no direction to push along
  (if (null dir) (setq dir '(0.0 1.0)))
  ;; DIMTEDIT slides the text ALONG the dimension line, so the push has
  ;; to run that way too -- but which of the two ways is free, and the
  ;; one leading AWAY from the middle of the pool is the one that puts
  ;; the text outside the shape rather than into it
  (setq a (ola:v+ pog (ola:v* dir push))
        b (ola:v- pog (ola:v* dir push))
        loc (if (> (ola:dist a mid) (ola:dist b mid)) a b))
  (command "_.DIMALIGNED"
           "_non" (trans (ola:2d pog) 0 1)
           "_non" (trans (ola:2d pnew) 0 1)
           "_non" (trans (ola:2d pnew) 0 1))
  (setq new (entlast))
  (if (and new (not (eq new pre)))
    (progn
      ;; DIMTEDIT moves the TEXT alone -- the dimension line stays on
      ;; the geometry, which is what makes the reading traceable back
      ;; to the two points it came from
      (command "_.DIMTEDIT" new "_non" (trans (ola:2d loc) 0 1))
      new)))

;; ---- housekeeping ------------------------------------------------------

(defun ola:syssave (vars / v)
  (if (not ola:*sysold*)
    (foreach v vars
      (if (/= nil (getvar v))
        (setq ola:*sysold*
              (append ola:*sysold* (list (cons v (getvar v)))))))))

(defun ola:sysrestore ( / p)
  ;; restore runs in the saved order, so OSMODE leads ola:*sysvars* --
  ;; object snaps are the setting the user misses most if a run is ever
  ;; cut short partway
  (foreach p ola:*sysold* (setvar (car p) (cdr p)))
  (setq ola:*sysold* nil))

(defun ola:dimstysave ()
  (if (not ola:*odstyle*) (setq ola:*odstyle* (getvar "DIMSTYLE"))))

(defun ola:dimstyrestore ()
  ;; DIMSTYLE cannot be setvar'd back, and this is called from *error*
  ;; where a bare (command ...) can itself fail (STANDARDS section 5)
  (if (and ola:*odstyle* (tblsearch "DIMSTYLE" ola:*odstyle*))
    (vl-catch-all-apply 'command-s
                        (list "_.-DIMSTYLE" "_Restore" ola:*odstyle*)))
  (setq ola:*odstyle* nil))

;; ---- asking ------------------------------------------------------------
;; The section 4 reference helper: KWS is BOTH the initget list and the
;; bracket text, so the two cannot drift.

(defun ola:askkw (msg kws hidden dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (strcat kws
                   (if hidden (strcat " " hidden) "")
                   (if back " Back Undo" "")))
  (setq v (getkword (strcat "\n" msg " ["
                            (vl-string-translate " " "/" kws)
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'OLA-BACK)
        ((null v) (if dflt dflt (ola:askkw msg kws hidden dflt back)))
        (T v)))

;; ---- reading a selection ------------------------------------------------

(defun ola:collect (ss / i en all)
  (setq i 0 all nil)
  (repeat (sslength ss)
    (setq en  (ssname ss i)
          all (append all (ola:ent-segs en))
          i   (1+ i)))
  ;; one polyline carries its own vertex order and is trusted; anything
  ;; else is loose geometry and gets walked into a ring
  (if (and (= 1 (sslength ss)) (> (length all) 1))
    all
    (ola:chain all)))

(defun ola:select (which / all ss i en typ bad)
  (princ (strcat "\n\nSelect the " which
                 " perimeter - one polyline, or the same"))
  (princ "\nshape exploded into lines and arcs.")
  ;; Picked WITHOUT a type filter, so that what cannot be read can be
  ;; named.  A filter would quietly drop a spline or a block, and the
  ;; command would then end as if nothing had been picked at all --
  ;; which is what it did, and what a drafter with a SPLINE perimeter
  ;; saw: nothing.  Text, dimensions and hatches caught by the window
  ;; are dropped without comment; only the things somebody might
  ;; reasonably expect to work are called out.
  (setq all (ssget))
  (if lzd:watch (lzd:watch all) all)
  (if all
    (progn
      (setq ss (ssadd) bad nil i 0)
      (repeat (sslength all)
        (setq en  (ssname all i)
              typ (cdr (assoc 0 (entget en))))
        (cond
          ((member typ '("LWPOLYLINE" "POLYLINE" "LINE" "ARC" "CIRCLE"))
           (ssadd en ss))
          ((and (member typ '("SPLINE" "ELLIPSE" "INSERT"))
                (not (member typ bad)))
           (setq bad (cons typ bad))))
        (setq i (1+ i)))
      (foreach typ bad
        (princ (strcat "\nOLAUTO: the " which " pick has "
                       (cond ((= typ "SPLINE") "a SPLINE")
                             ((= typ "ELLIPSE") "an ELLIPSE")
                             (T "a block (INSERT)"))
                       " in it, which cannot be read - "
                       (cond ((= typ "SPLINE")
                              "PEDIT it into a polyline first.")
                             ((= typ "ELLIPSE")
                              "redraw it as arcs, or PEDIT it, first.")
                             (T (strcat "EXPLODE it, or pick the"
                                        " perimeter inside it, first.")))
                       (if (> (sslength ss) 0)
                         "  Going on with the rest of the pick."
                         ""))))
      (if (> (sslength ss) 0)
        ss
        (progn
          (if (null bad)
            (princ (strcat "\nOLAUTO: nothing in the " which
                           " pick can be read - it wants a polyline,"
                           " or lines and arcs.")))
          nil)))))

;; ---- the report ---------------------------------------------------------

(defun ola:rtos1 (v) (rtos v 2 3))

(defun ola:report (prof drawn span warn / n worst sum rms d p w)
  (setq n (length prof) worst 0.0 sum 0.0 rms 0.0)
  (foreach p prof
    (setq d     (car p)
          worst (max worst d)
          sum   (+ sum d)
          rms   (+ rms (* d d))))
  (if (> n 0) (setq sum (/ sum n) rms (sqrt (/ rms n))))
  (princ (strcat "\n\nOLAUTO: best overlay found - worst error "
                 (ola:rtos1 worst) ", average " (ola:rtos1 sum)
                 ", RMS " (ola:rtos1 rms) "."))
  (princ (strcat "\n        Measured at " (itoa n)
                 " points around the original."))
  (if drawn
    (princ (strcat "\n        " (itoa (length drawn))
                   " dimension(s) drawn on layer \"" ola:*dim-layer*
                   "\" at the worst spots."))
    (princ (strcat "\n        Nothing over " (ola:rtos1 ola:*peak-min*)
                   " to dimension - the two agree everywhere.")))
  ;; The warnings go HERE as well as where they were found.  A drafter
  ;; reads the last four lines of a run; a caution printed before a
  ;; twenty-second fit has scrolled off by the time the numbers land,
  ;; and an unbelievable number that looks believable is the whole
  ;; failure this command has to avoid.
  (if (and (> span 0.0) (> worst (* ola:*fit-warn* span)))
    (setq warn
          (cons (strcat "the worst error is "
                        (itoa (fix (+ 0.5 (* 100.0 (/ worst span)))))
                        "% of the pool's own size.  An overlay that far"
                        " out is not two measurements of one pool - check"
                        " that the right two outlines were picked.")
                warn)))
  (foreach w (reverse warn)
    (princ (strcat "\n\nOLAUTO: *** " w)))
  (list worst sum rms))

;; ---- the command ---------------------------------------------------------

(defun ola:run ( / ssa ssb newss ogss movss fixss laya layb qstep ans
                   whichnew whichmove segnew segog x prof pk drawn push
                   havestyle p dimlist mid shared flat lnew log_ warn w
                   pcs mir mseg fseg ratio hint locked)
  ;; The selections and the questions are ONE chain, walked with a step
  ;; counter (STANDARDS section 3).  A selection cannot be armed with
  ;; initget, so Back cannot be typed AT one -- which is why Back at the
  ;; question sitting straight after the selections re-opens them
  ;; instead, the way WCALST and AUTOBEAD have always done.  Nothing
  ;; has been drawn before step 4, and every step rebuilds what it
  ;; fills, so a second pass through any of them starts clean.
  ;;
  ;;   0  the two picks (and the picks OLAUTO refuses)
  ;;   1  which one is the NEW perimeter
  ;;   2  which one should move
  ;;   3  read both, say what looks wrong, and -- only when the flipped
  ;;      walk fits far better -- offer the mirror
  ;;   4  fit, move, re-layer, dimension, report
  (setq qstep 0)
  (while (and qstep (< qstep 4))
    (cond
      ((= qstep 0)
       ;; Two picks, then two refusals that leave QSTEP where it is --
       ;; which sends the run straight back to the picking, because that
       ;; is where the mistake was made.
       (cond
         ((not (and (setq ssa (ola:select "FIRST"))
                    (setq ssb (ola:select "SECOND"))))
          (setq qstep nil))                    ; nothing picked - done
         ((> (setq shared (ola:ss-shared ssa ssb)) 0)
          (princ (strcat "\nOLAUTO: those two picks share "
                         (itoa shared) " object(s)"
                         (if (= shared (sslength ssa))
                           " - that is the same perimeter twice, and"
                           " -")
                         " a perimeter cannot be overlaid on itself."
                         "  It would report a perfect overlay and"
                         " nothing to dimension.  Pick the two"
                         " separately.")))
         ((setq flat (ola:ss-not-flat ssa))
          (princ (strcat "\nOLAUTO: the FIRST pick has a " flat
                         " that is not drawn in the world XY plane."
                         "  Its points are kept in the object's own"
                         " plane, so reading them as world would fit a"
                         " mirrored outline.  Flatten it first.")))
         ((setq flat (ola:ss-not-flat ssb))
          (princ (strcat "\nOLAUTO: the SECOND pick has a " flat
                         " that is not drawn in the world XY plane."
                         "  Its points are kept in the object's own"
                         " plane, so reading them as world would fit a"
                         " mirrored outline.  Flatten it first.")))
         ;; refused before a question is asked or anything is moved: a
         ;; locked layer refuses the move and the re-layer both, and a
         ;; run past it reported an overlay the drawing does not show
         ((setq locked (ola:ss-locked ssb (ola:ss-locked ssa nil)))
          (princ (strcat "\nOLAUTO: layer" (if (cdr locked) "s " " ")
                         (ola:names locked)
                         (if (cdr locked) " are" " is") " locked.  OLAUTO"
                         " moves one perimeter and puts both on its own"
                         " layers, and a locked layer refuses both -"
                         " nothing would move, and the dimensions would"
                         " be of an overlay the drawing does not show."
                         "\nUnlock " (ola:names locked)
                         " first, then run OLAUTO again."))
          (setq qstep nil))
         (T
          (setq laya (ola:ss-layer ssa)
                layb (ola:ss-layer ssb)
                ;; the layers answer the next question before it is
                ;; asked: the selection already sitting on the pool
                ;; layer is the new one, and if neither is, the first
                ;; one asked for leads
                whichnew (cond ((and laya (= (strcase laya)
                                             (strcase ola:*new-layer*)))
                                "First")
                               ((and layb (= (strcase layb)
                                             (strcase ola:*new-layer*)))
                                "Second")
                               ((and layb (= (strcase layb)
                                             (strcase ola:*og-layer*)))
                                "First")
                               ((and laya (= (strcase laya)
                                             (strcase ola:*og-layer*)))
                                "Second")
                               (T "First"))
                qstep 1))))
      ((= qstep 1)
       (setq ans (ola:askkw
                   (strcat "Which selection is the NEW perimeter?"
                           " (first on \"" (cond (laya) ("?"))
                           "\", second on \"" (cond (layb) ("?")) "\")")
                   "First Second" nil whichnew T))
       (if (eq ans 'OLA-BACK)
         ;; the canonical wording (README, "Going back a step"); the
         ;; select prompt that follows says what re-opened
         (progn (princ "\nStepping back one question.")
                (setq qstep 0))
         (setq whichnew ans qstep 2)))
      ((= qstep 2)
       (setq ans (ola:askkw
                   "Which perimeter should move onto the other?"
                   "New OG" nil (cond (whichmove) ("New")) T))
       (if (eq ans 'OLA-BACK)
         (progn (princ "\nStepping back one question.")
                (setq qstep 1))
         (setq whichmove ans qstep 3)))
      ((= qstep 3)
       (setq newss  (if (= whichnew "First") ssa ssb)
             ogss   (if (= whichnew "First") ssb ssa)
             movss  (if (= whichmove "New") newss ogss)
             fixss  (if (= whichmove "New") ogss newss)
             segnew (ola:collect newss)
             segog  (ola:collect ogss)
             warn   nil)
       (if (or (< (length segnew) 1) (< (length segog) 1))
         (progn
           (princ "\nOLAUTO: one of those selections has no curve in it.")
           (setq qstep nil))
         (progn
           ;; Before anything moves: do these two even look like the
           ;; same pool?  OLAUTO has no idea what a pool is and will fit
           ;; any two curves, so a mis-pick comes back as a confident
           ;; set of dimensions off a meaningless overlay unless
           ;; something says otherwise.  Warnings, not refusals -- a
           ;; pool really can be measured wrong by a lot, and that is
           ;; the run somebody needs the numbers from.
           ;;
           ;; First: is either pick really several objects?  A stray
           ;; deck line caught by the window is chained end to end with
           ;; the perimeter, and the fit that follows is of the junk.
           (foreach p (list (list "new" segnew) (list "original" segog))
             (setq pcs (ola:chain-pieces (cadr p)))
             (if (> (car pcs) 1)
               (setq warn
                     (cons (strcat "the " (car p) " perimeter came in as "
                                   (itoa (car pcs)) " separate pieces - the"
                                   " biggest jump between them is "
                                   (ola:rtos1 (cadr pcs))
                                   ".  A stray line or arc caught by the"
                                   " window?  It is fitted along with the"
                                   " rest.")
                           warn))))
           (setq lnew (ola:chain-len segnew)
                 log_ (ola:chain-len segog))
           (if (and (> (max lnew log_) 0.0)
                    (> (/ (abs (- lnew log_)) (max lnew log_))
                       ola:*len-warn*))
             (progn
               ;; a ratio that is a units factor is worth naming: it is
               ;; the one mis-pick that is not a mis-pick at all
               (setq ratio (/ (max lnew log_) (max 1.0e-12 (min lnew log_)))
                     hint  (cond
                             ((equal ratio 25.4 0.8)
                              "  That is the ratio of inches to millimetres.")
                             ((equal ratio 12.0 0.4)
                              "  That is the ratio of feet to inches.")
                             ((equal ratio 2.54 0.08)
                              "  That is the ratio of inches to centimetres.")
                             ((or (equal ratio 10.0 0.3) (equal ratio 100.0 3.0))
                              "  That is a power of ten: a scale factor?")
                             (T "")))
               (setq warn
                     (cons (strcat "the two perimeters are "
                                   (ola:rtos1 lnew) " and " (ola:rtos1 log_)
                                   " round - "
                                   (itoa (fix (+ 0.5 (* 100.0
                                                        (/ (abs (- lnew log_))
                                                           (max lnew log_))))))
                                   "% apart.  Two measurements of one pool"
                                   " agree far closer than that: check the"
                                   " pick." hint)
                           warn))))
           (if (not (eq (not (ola:closed-p segnew))
                        (not (ola:closed-p segog))))
             (setq warn
                   (cons (strcat "one of these perimeters closes and the"
                                 " other does not, so they cannot be walked"
                                 " against each other end for end.  The fit"
                                 " below is the best of a bad job.")
                         warn)))
           (foreach w (reverse warn) (princ (strcat "\nOLAUTO: " w)))
           ;; Then: is it a mirror image?  A rigid fit can turn and slide
           ;; but never flip, so a perimeter that arrived flipped fits as
           ;; badly as it possibly can and every dimension is nonsense.
           ;; The flipped walk is tried too, and when it fits far better
           ;; the mirror is offered -- offered, because it changes the
           ;; drawing, and Enter must not do that by itself.
           (setq mseg (if (= whichmove "New") segnew segog)
                 fseg (if (= whichmove "New") segog segnew)
                 mir  (ola:mirror-p mseg fseg))
           (if mir
             (progn
               ;; the ratio is capped for the sentence: a mirrored fit
               ;; that lands dead on divides by next to nothing
               (setq ratio (/ (car mir) (max 1.0e-9 (cadr mir))))
               (princ (strcat "\n\nOLAUTO: the "
                              (if (= whichmove "New") "new" "original")
                              " perimeter fits the other "
                              (if (> ratio 100.0)
                                "more than 100"
                                (strcat "about "
                                        (itoa (max 2 (fix (+ 0.5 ratio))))))
                              " times better as a MIRROR image than as it"
                              " is.  One of the two was probably drawn from"
                              " the far side, or brought in with an axis"
                              " reversed.  Without the mirror the overlay"
                              " will be about " (ola:rtos1 (car mir))
                              " out everywhere."))
               (setq ans (ola:askkw
                           (strcat "Mirror the "
                                   (if (= whichmove "New") "new" "original")
                                   " perimeter before fitting?")
                           "Yes No" nil "No" T))
               (cond
                 ((eq ans 'OLA-BACK)
                  (princ "\nStepping back one question.")
                  (setq qstep 2))
                 ((= ans "Yes")
                  ;; about the vertical through its own middle -- any
                  ;; line would do, the rigid fit puts it where it goes
                  (setq mid (car (ola:middle mseg)))
                  (ola:mirror-ss movss mid)
                  (if (= whichmove "New")
                    (setq segnew (ola:mirror-segs segnew mid))
                    (setq segog  (ola:mirror-segs segog mid)))
                  (setq qstep 4))
                 (T
                  (setq warn (cons "fitted WITHOUT the mirror it asked for."
                                   warn)
                        qstep 4))))
             (setq qstep 4)))))))
  (if (= qstep 4)
    (progn
      (princ "\n\nFitting...")
      (setq x (ola:fit (if (= whichmove "New") segnew segog)
                       (if (= whichmove "New") segog segnew)))
      (if (null x)
        (princ "\nOLAUTO: those two perimeters cannot be walked - one of them has no length.")
        (progn
          ;; the drawing moves ONCE, by the whole transform
          (ola:xform-ss x movss)
          (if (= whichmove "New")
            (setq segnew (mapcar '(lambda (s)
                                    (list (ola:xapply x (car s))
                                          (ola:xapply x (cadr s))
                                          (caddr s)))
                                 segnew))
            (setq segog (mapcar '(lambda (s)
                                   (list (ola:xapply x (car s))
                                         (ola:xapply x (cadr s))
                                         (caddr s)))
                                segog)))
          ;; onto the shop's layers, so the sheet reads the same
          ;; whichever drawing the two arrived in
          (ola:ensure-layer ola:*new-layer* ola:*new-color*)
          (ola:ensure-layer ola:*og-layer* ola:*og-color*)
          (ola:relayer newss ola:*new-layer*)
          (ola:relayer ogss ola:*og-layer*)
          ;; the error, and the worst of it
          (setq prof (ola:profile segog segnew)
                pk   (ola:peaks prof (max 0 (fix ola:*dimcount*))
                                (ola:closed-p segog))
                push (* ola:*text-push* (ola:span segog))
                mid  (ola:middle segog))
          (if pk
            (progn
              (ola:ensure-layer ola:*dim-layer* ola:*dim-color*)
              (ola:dimstysave)
              (setq havestyle (tblsearch "DIMSTYLE" ola:*dim-style*))
              (if havestyle
                (command "_.-DIMSTYLE" "_Restore" ola:*dim-style*)
                (princ (strcat "\nOLAUTO: dimension style \""
                               ola:*dim-style*
                               "\" is not in this drawing - using the"
                               " current style \"" (getvar "DIMSTYLE")
                               "\" instead.")))
              (setvar "CLAYER" ola:*dim-layer*)
              (setq drawn nil)
              (foreach p pk
                (setq dimlist (ola:dim (cadr p) (caddr p) push mid))
                (if dimlist (setq drawn (cons dimlist drawn))))
              (ola:dimstyrestore)))
          (ola:report prof drawn (ola:span segog) warn)))))
  (princ))

(defun c:OLAUTO ( / *error* undo-open)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (ola:sysrestore)
    (ola:dimstyrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nOLAUTO error: " msg)))
    (if lzd:report (lzd:report "OLAUTO" *olauto-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "OLAUTO" *olauto-version*))
  (ola:syssave ola:*sysvars*)
  (setvar "CMDECHO" 0)
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))
  (ola:run)
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  (ola:sysrestore)
  (if lzd:end (lzd:end "OLAUTO"))
  (princ))

(defun c:OLAUTOVER ()
  (princ (strcat "\nOLAUTO " *olauto-version* " loaded."))
  (princ))

;; -------------------- self tests ---------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun ola:selftests ()
  (list
    (list "sweep of bulge 1 is a half turn"        '(ola:sweep 1.0)              pi)
    (list "bulge-radius: a semicircle on a 10 chord has radius 5"
          '(ola:bulge-radius '(0 0) '(10 0) 1.0)  5.0)
    (list "seg-len measures the arc, not its chord"
          '(ola:seg-len '((0 0) (10 0) 1.0))      (* 5.0 pi))
    (list "arc-geom centres a semicircle on its chord"
          '(car (ola:arc-geom '((0 0) (10 0) 1.0)))  '(5.0 0.0))
    (list "seg-pt halfway round a CCW arc lies right of the chord"
          '(ola:seg-pt '((0 0) (10 0) 1.0) 0.5)   '(5.0 -5.0))
    (list "pclose lands on the arc itself, not on its chord"
          '(ola:pclose (car (ola:prep '(((0 0) (10 0) 1.0)))) '(5 -20))  '(5.0 -5.0))
    (list "chain turns a segment drawn the other way round"
          '(cadr (ola:chain '(((0 0) (10 0) 0.0) ((10 10) (10 0) 0.5))))
          '((10 0) (10 10) -0.5))
    (list "closed-p: a square that meets itself reads closed"
          '(ola:closed-p '(((0 0) (10 0) 0.0) ((10 0) (10 10) 0.0)
                          ((10 10) (0 10) 0.0) ((0 10) (0 0) 0.0)))  T)
    (list "walk spaces a closed square at its corners"
          '(nth 2 (ola:walk '(((0 0) (10 0) 0.0) ((10 0) (10 10) 0.0)
                              ((10 10) (0 10) 0.0) ((0 10) (0 0) 0.0)) 4 T))
          '(10.0 10.0))
    (list "kabsch recovers a quarter turn and a shift"
          '(ola:xapply (ola:kabsch '((0 0) (1 0) (0 1)) '((5 5) (5 6) (4 5))) '(1 0))
          '(5.0 6.0))
    (list "chain-pieces counts a far jump as a second piece"
          '(car (ola:chain-pieces '(((0 0) (10 0) 0.0) ((50 50) (60 50) 0.0))))  2)
    (list "names joins three layers in prose"
          '(ola:names '("A" "B" "C"))  "\"A\", \"B\" and \"C\"")))

(foreach c '("OLAUTO")
  (setq *calofin-selftests*
        (cons (cons c 'ola:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nOLAUTO " *olauto-version*
                 " loaded.  Type OLAUTO to run.")))
(princ)
