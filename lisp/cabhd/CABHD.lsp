;;; ===================================================================
;;; CABHD.LSP  --  Fit a pool perimeter through PART of a survey
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Command:  CABHD - fit the perimeter, and only the perimeter
;;;
;;; CABHD is ABHD's perimeter half, with one rule added and one whole
;;; half left out.
;;;
;;;   ADDED - THE POINT CUTOFF.  A survey run rarely stops where the
;;;     pool edge does.  The shots that trace the edge come first, and
;;;     the rest - steps, benches, deck, depth shots, the neighbour's
;;;     fence - carry on in the same numbering, so a 137-point survey
;;;     may hold a 20-point perimeter.  After the selection CABHD asks
;;;     how far up the numbers the edge runs, and everything past that
;;;     answer is out of the perimeter ENTIRELY: not ordered into the
;;;     loop, not fitted, not counted against the miss allowance, and
;;;     never reported as a point the line failed to hold.  Select the
;;;     whole survey and say where the pool stops.
;;;
;;;   LEFT OUT - THE POOL BOTTOM.  ABHD offers to draw the floor once a
;;;     perimeter is kept: shallow and deep breaks, the hopper, the
;;;     slope lines and their dimensions.  CABHD does none of it and
;;;     never asks.  It ends with the kept perimeter and its hit
;;;     report.  For the floor, run ABHD or ADAB.
;;;
;;; Everything else is ABHD's, rule for rule, so a fit from either
;;; command is the same fit.  What follows describes those rules.
;;;
;;; The user window-selects an area containing:
;;;   * On layer "POOL"   : (optional) a closed perimeter drawn as ONE
;;;                         closed polyline OR an exploded set of
;;;                         LINEs/ARCs.
;;;   * On layer "POINTS" : POINT entities surveyed on the real pool
;;;                         edge.  Survey points saved as "ab_pt" block
;;;                         inserts count on any layer, and the number
;;;                         attribute they carry is what the cutoff
;;;                         reads.
;;;
;;; THE CUTOFF, EXACTLY: the prompt takes the LAST point number that
;;; belongs to the pool edge - type it, or Pick that point in the
;;; drawing and CABHD reads its number off the block.  Enter (or All)
;;; keeps every point, which is ABHD's behaviour.  The number is read
;;; from the point's label as the first run of digits in it, so "17",
;;; "P17" and "17A" all read as seventeen; a point whose label holds no
;;; digit at all falls back to its place in the selection, and CABHD
;;; says so before asking.  A cutoff that would starve the fit is
;;; refused and re-asked, and it can be moved (either way) at a Redo -
;;; setting it too low costs one prompt, not a run.  A straight wall,
;;; sharp corner or held point declared on a point the cutoff drops is
;;; dropped with it and said so, rather than being quietly snapped onto
;;; some other point.
;;;
;;; TWO MODES, chosen automatically from the selection:
;;;   * GUIDED  - the selection contains POOL geometry: the drawn
;;;               shape is used as the guide and re-fitted through the
;;;               points (described below).
;;;   * POINTS-ONLY - the selection contains no POOL geometry: the
;;;               program orders the points into a closed loop by
;;;               itself (nearest-neighbour tour + 2-opt uncrossing)
;;;               and covers them with as FEW long, overarching ARCS
;;;               as possible - each arc is grown to take in as many
;;;               consecutive points as it can hold.  No straight
;;;               lines are drawn (organic shapes have none); the only
;;;               exception is a stretch between two sharp corners
;;;               with no points in between, where an arc would be
;;;               pure invention.
;;;
;;; ON THE POINTS FIRST: every arc endpoint sits ON a survey point,
;;; and each arc is chosen so its MIDDLE passes exactly through one of
;;; its interior points too (a true 3-point arc) whenever such an arc
;;; holds the span.  Arcs that float between the points are a last
;;; resort and must cover at least 2 more points to be chosen - they
;;; should be the rare exception (roughly 1 arc in 10), not the rule.
;;;
;;; NEAR-TANGENT SMOOTHNESS: at every joint the new arc must start
;;; within *CAB-TANG-TOL* (8 degrees) of the previous arc's end
;;; tangent - close enough to look smooth, loose enough that the
;;; points stay in charge.  Sharp corners (over *CAB-CORNER-ANG*) stay
;;; free kinks; the closing seam is held to the same window (the fit
;;; is re-run once with a seeded start tangent when the seam comes
;;; out worse).
;;;
;;; NICE RADII: arc radii are snapped to friendly increments before a
;;; free ("weird") number is accepted - whole feet first, then half
;;; feet, then whole inches (*CAB-NICE-RADII*, drawing units = inches).
;;; The points outrank pretty radii: a snap may move covered points at
;;; most *CAB-SNAP-EPS* beyond where they already sat and may never
;;; pull an arc off its anchor point; endpoints never move.
;;;
;;; THE MISS ALLOWANCE: the perimeter does not have to thread every
;;; point exactly.  A share of the points - asked per run, standard
;;; *CAB-MISS-PCT* (15%), rounded UP to the nearest whole point - may
;;; sit off the result by up to the max distance (default 1 unit =
;;; about an inch, capped at *CAB-TOL-MAX*); every other point stays on
;;; it (within *CAB-ON-EPS*).  That slack is spent where it buys the
;;; most: longer arcs, fewer curves, nicer radii.  It is a share of the
;;; points the CUTOFF KEPT - the ones it dropped buy no slack, since
;;; the line was never asked to go near them.
;;;
;;; DECLARED STRAIGHT WALLS: the user may declare dead-straight walls
;;; up front by picking their two end points; each is marked with a
;;; dashed line on *CAB-WALL-LAYER* and comes out of the points-built
;;; fit as a straight LINE between exactly those two survey points -
;;; arcs never swallow or cross a declared wall.
;;;
;;; HELD POINTS: the user may also declare points that must be held
;;; ABSOLUTELY - control shots, tie-ins, anything surveyed as an
;;; exact position.  A held point is never buried inside a span, so
;;; every span ends ON it and the fitted line passes through it
;;; exactly, in every candidate; it costs nothing from the miss
;;; allowance and the tangency window still applies at its joint (it
;;; is not a corner).  In guided mode the drawn shape wins, as with
;;; declared walls - held points steer the points-built fit - and the
;;; report flags any held point the kept fit did not land on.
;;;
;;; THE CURVE CAP: the command also asks for a maximum number of
;;; curves ("None" = unlimited).  When a fit needs more, the whole
;;; loop is refitted with a progressively relaxed tolerance until the
;;; cap holds - merging arcs would break their tangency, so the chain
;;; is rebuilt instead and stays smooth.  The cap wins over the
;;; tolerance; whatever error it forces is shown in the hit report.
;;; The cap binds in EVERY mode: a guided run whose drawn perimeter
;;; needs more curves falls back to fitting from the points (the
;;; drawn shape still orders them), and an unreachably small cap
;;; returns the fewest-curves fit found - never the full-size one.
;;;
;;; THE THREE CANDIDATES: how much curve to spend on how much accuracy
;;; is a judgement, not a setting, so all three answers are drawn and
;;; the user points at one (*CAB-COMPARE*).  Fit 1 is the accurate end:
;;; it fits to *CAB-TIGHT-TOL*, writes off no point at all, and obeys
;;; neither the typed distance nor the curve cap - the most curves for
;;; the least error there is.  Fit 2 is the settings exactly as typed,
;;; cap included.  Fit 3 is the economical end: the same typed
;;; distance, but with the miss allowance and its per-span fair share
;;; lifted, so arcs run as long as that distance allows - the fewest
;;; curves that still hold it.  All three are then MEASURED against
;;; the typed distance, so the table compares like for like.
;;;
;;; The command rebuilds the perimeter as a single closed LWPOLYLINE
;;; (lines + arcs only, no splines); the candidates preview on layer
;;; "POOL-FIT" and the kept one moves onto the POOL layer:
;;;   * Every polyline vertex is snapped to the nearest surveyed point
;;;     within the tolerance (default 1 unit = 1 inch), so corners land
;;;     exactly on points whenever one is close enough.
;;;   * Every curved (arc/bulge) segment is re-fitted so that the arc
;;;     passes through the surveyed points lying along it.  A single
;;;     replacement arc is tried first (the best of the exact 3-point
;;;     arcs through the two snapped endpoints and the points, plus
;;;     their average), with its radius snapped to a nice increment
;;;     when possible; if it keeps every point within the tolerance
;;;     and the miss allowance can absorb the off ones, that ONE arc
;;;     is kept.  Only when that fails is the segment SUBDIVIDED into
;;;     a tangent-continuous chain of arcs through every point.
;;;   * Straight segments the user drew are trusted and kept straight
;;;     (only their endpoints snap to points); where the user found a
;;;     straight wall, the result has a straight wall.
;;;   * A point that turns more than *CAB-CORNER-ANG* (45 deg) is a
;;;     sharp corner: it can start or end a span but is never buried
;;;     inside one, so polygonal shapes keep their corners as lines.
;;; Everything is fitted on the 2D plane - Z coordinates are ignored.
;;; Every segment shares its endpoints with its neighbours, so the
;;; result stays closed.
;;;
;;; A hit report is printed: how many points the new perimeter passes
;;; through exactly, how many are within tolerance, how many missed.
;;; The points the cutoff left out are in none of those counts.
;;;
;;; WHEN A CANDIDATE WILL NOT DRAW: a fit can come out too degenerate
;;; for AutoCAD to accept - fewer than two segments is no closed
;;; outline, and AutoCAD answers entmake with nil rather than an error.
;;; The tight fit is the likeliest, since it must thread every point at
;;; *CAB-TIGHT-TOL* with no miss allowance and no curve cap, and a
;;; survey read whole (Enter at the cutoff) is where it happens.  One
;;; candidate failing costs only that candidate: the table marks it
;;; "would not draw", Enter defaults to one that did, and picking the
;;; missing one says so.  Only when NONE of them draws is that a dead
;;; end, and it says which cutoff to try.  Nothing here is ever silent:
;;; every run signs off naming the last step it reached, and the error
;;; handler names that step for cancels too.
;;;
;;; REDO: at the choose prompt, Redo refits without leaving the
;;; command.  Points can be omitted by clicking them (clicking a ringed
;;; one puts it back), the cutoff can move either way, straight walls,
;;; sharp corners and held points can be added or removed, and the
;;; three numbers are asked again with Enter keeping each.  The omit
;;; list picks out strays one at a time; the cutoff draws a line across
;;; the whole survey at once.  Either way, a declaration whose point
;;; has left the fit leaves with it.
;;;
;;; Everything CABHD draws to help you decide - dashed markers, the
;;; three candidate outlines, their labels - is stamped as its own and
;;; sweeps itself when the command ends, ESC included.  ABHD's stamped
;;; work is left alone, and never read back as guide geometry.
;;; ===================================================================

;; ---- configuration -------------------------------------------------
(setq *cabhd-version* "v1.7")       ; announced on load; release_lisp.py
                                    ; stamps the dated twin in releases/
                                    ; from it (vN.N -> CABHD_MMDDYY_
                                    ; REVNN), so the filename and the
                                    ; banner can never disagree - bump
                                    ; it with every revision
(setq *CAB-POOL-LAYER*   "POOL")     ; layer holding the drawn perimeter
(setq *CAB-POINT-LAYER*  "POINTS")   ; layer holding the survey points
(setq *CAB-POINT-BLOCK*  "ab_pt")    ; block name whose INSERTs mark survey
                                    ; points; the block's insertion point
                                    ; is taken as the point location
(setq *CAB-OUT-LAYER*    "POOL-FIT") ; layer the fitted polyline goes on
(setq *CAB-MISS-LAYER*   "FGStep")   ; layer the "could not hold this
                                    ; point" circles and their list go
                                    ; on.  This may well be a layer you
                                    ; already use, so CABHD stamps the
                                    ; objects it makes and only ever
                                    ; erases its own (see cab:tag-mine)
(setq *CAB-MISS-RADIUS*  4.0)        ; radius of those circles (4 inches)
(setq *CAB-PT-TAG*       "number")   ; attribute tag on the point block
                                    ; holding the surveyed point number,
                                    ; used to label it as "Pt.17"
(setq *CAB-WALL-LAYER*   "POOL-WALLS"); layer the dashed markers for
                                    ; user-declared straight walls go on
(setq *CAB-TOL-MAX*      2.0)        ; hard ceiling on the max-distance
                                    ; prompt (2 inches): further than
                                    ; that and the line is no longer a
                                    ; trace of the points
(setq *CAB-COMPARE*                  ; the three candidate fits offered:
  '(("tight" 1 "red"    "most curves - least error")
    ("asked" 2 "yellow" "as asked")
    ("few"   4 "cyan"   "fewest curves - still within the distance")))
                                    ; (mode, AutoCAD colour, colour name,
                                    ; description).  The three ask three
                                    ; different questions of the same
                                    ; points, so what is being chosen is
                                    ; an aim, not a tolerance:
                                    ;   "tight" - accuracy above all: it
                                    ;     fits to *CAB-TIGHT-TOL*, lets no
                                    ;     point miss and ignores both the
                                    ;     distance typed at step 2 and
                                    ;     the curve cap, so it draws the
                                    ;     most curves and the least error
                                    ;   "asked" - the settings exactly as
                                    ;     typed, curve cap and all
                                    ;   "few" - the fewest curves that
                                    ;     still hold every point within
                                    ;     the distance typed: the same
                                    ;     distance, but with the miss
                                    ;     allowance lifted so arcs run as
                                    ;     long as that distance permits
                                    ; Colours and wording are yours to
                                    ; edit; the three mode names are not
(setq *CAB-TIGHT-TOL*    0.01)       ; the "tight" candidate's accuracy
                                    ; target (units) - what it fits to
                                    ; instead of the distance typed at
                                    ; step 2, or that distance when it
                                    ; happens to be tighter still
(setq *CAB-EXACT-EPS*    0.001)      ; "exactly on" threshold (units)
(setq *CAB-FIT-EPS*      0.01)       ; if a single arc misses any of its
                                    ; points by more than this, split it
                                    ; into several arcs that hit exactly
(setq *CAB-ON-EPS*       0.25)       ; a point within this of the result
                                    ; counts as ON it; only points off by
                                    ; more than this eat into the miss
                                    ; allowance below.  Calibrated from a
                                    ; hand-drawn reference trace: ~87% of
                                    ; its points sat within a quarter inch
(setq *CAB-MISS-PCT*     0.15)       ; share of the points (rounded UP to
                                    ; a whole point) that may sit off the
                                    ; result by up to the tolerance
                                    ; (about an inch by default) - this
                                    ; slack is what buys longer spans and
                                    ; fewer curves
(setq *CAB-CORNER-ANG*   (/ pi 4.0)) ; a point that turns more than this
                                    ; (45 deg) is a sharp corner: it may
                                    ; start or end a span but never gets
                                    ; buried inside one, so polygonal
                                    ; shapes keep their corners.  Sample
                                    ; real tight curves with at least ~3
                                    ; points per quarter turn to stay
                                    ; under it.
(setq *CAB-NICE-RADII* '(12.0 6.0 1.0)) ; preferred arc-radius increments,
                                    ; tried in order: whole feet, half
                                    ; feet, whole inches (drawing units
                                    ; are inches).  A radius is snapped
                                    ; to the first increment whose arc
                                    ; still holds the points; only when
                                    ; none does is the free-fit ("weird")
                                    ; radius kept.
(setq *CAB-TANG-TOL* (/ pi 22.5))    ; wiggle room from perfect
                                    ; tangency at each joint between two
                                    ; arcs (8 degrees).  Being ON the
                                    ; points matters more than perfect
                                    ; tangency; this slack is what lets
                                    ; every arc endpoint sit on a survey
                                    ; point and radii stay nice.
                                    ; Calibrated from a hand-drawn
                                    ; reference trace whose joints ran up
                                    ; to 7.9 deg (median 3 deg); tighter
                                    ; values shatter the fit into many
                                    ; short arcs (5 deg is workable,
                                    ; 6 deg and below is not).
(setq *CAB-TANG-STEPS* '(1.0 1.25 1.5)) ; when nothing fits inside the
                                    ; tangent window, stretch it by
                                    ; these multiples in turn rather
                                    ; than abandon it; if even the
                                    ; widest finds nothing, a one-point
                                    ; stub takes over, and that
                                    ; continues the previous tangent
                                    ; exactly.  Smoothness is worth
                                    ; more than one extra arc, so keep
                                    ; the last step small: dropping the
                                    ; window outright allowed joints to
                                    ; kink three times the limit.
(setq *CAB-ARC-SLACK* (/ pi 3.0))    ; how much further than its own
                                    ; points actually turn one arc may
                                    ; sweep (60 degrees).  An arc is
                                    ; allowed to curve about as much as
                                    ; the run of points it covers
                                    ; curves, and no more - which is
                                    ; what stops a shaky survey coming
                                    ; back as a chain of loops.  A span
                                    ; between two neighbouring points
                                    ; covers no turn at all, so it gets
                                    ; the slack alone: room for a
                                    ; quarter turn sampled only two
                                    ; points to the corner, nowhere
                                    ; near the semicircles this fitter
                                    ; used to draw when a tangent got
                                    ; away from it.
(setq *CAB-DROP-PCT*     0.10)       ; share of the points (rounded UP)
                                    ; the fit may give up on entirely:
                                    ; left further off than the max
                                    ; distance, counted as "not held"
                                    ; and ringed in the drawing.  It is
                                    ; spent only where the walk would
                                    ; otherwise shatter into one-point
                                    ; stubs, and only when each point
                                    ; given up buys at least two more
                                    ; points of span - a stray shot is
                                    ; worth less than the shape, but
                                    ; the points at large outrank both.
                                    ; Declared corners, wall points and
                                    ; held points are never given up.
                                    ; The "tight" candidate is granted
                                    ; none of this at all.
(setq *CAB-DROP-MULT*    2.0)        ; how far past the max distance a
                                    ; point has to be before the fit
                                    ; may give up on it at all.  This
                                    ; is what separates a bad shot from
                                    ; a feature: a point that misses by
                                    ; a little is still fought for - it
                                    ; stops the span exactly as it
                                    ; always did - and only one plainly
                                    ; off can be written off.  Without
                                    ; it the fit would give up the tip
                                    ; of a sparsely shot pool to save
                                    ; one segment.
(setq *CAB-SNAP-EPS*     0.02)       ; a nice-radius snap may move the
                                    ; covered points at most this far
                                    ; beyond where they already sat, and
                                    ; it may never pull an arc off its
                                    ; anchor point entirely - the points
                                    ; outrank pretty radii
(setq *CAB-CHAIN-FUZZ*   1.0e-4)     ; endpoint-matching fuzz for
                                    ; chaining exploded segments
(if (null *CAB-TOL*) (setq *CAB-TOL* 1.0)) ; default tolerance, 1 inch
;; *CAB-MAX-ARCS* : cap on the number of curved segments in the output;
;; nil = no cap.  The command prompts for it (Enter keeps the current
;; value, "None" removes the cap) and remembers it for the session,
;; like *CAB-TOL*.

;; ---- small 2D vector helpers ---------------------------------------
(defun cab:2d (p) (list (car p) (cadr p)))
(defun cab:dist (a b) (distance (cab:2d a) (cab:2d b)))
(defun cab:sub (a b) (mapcar '- (cab:2d a) (cab:2d b)))
(defun cab:add (a b) (mapcar '+ (cab:2d a) (cab:2d b)))
(defun cab:scl (v s) (list (* (car v) s) (* (cadr v) s)))
(defun cab:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun cab:mid (a b) (cab:scl (cab:add a b) 0.5))
(defun cab:perp (v) (list (- (cadr v)) (car v))) ; rotate 90 deg CCW

;; Tangent with the angle clamped just short of +/-90 degrees.  Every
;; bulge in this file is a tangent of a quarter-sweep, so a half-turn
;; quarter-sweep (a degenerate, full-circle segment) would otherwise
;; divide by zero and abort the command.  Clamping yields a huge but
;; finite bulge instead; the callers that can legitimately reach the
;; limit (full-circle ARCs and CIRCLEs) split themselves in half
;; before they get here, so this is purely a safety net.
(defun cab:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;; smallest integer >= X (X non-negative)
(defun cab:ceil (x / f)
  (setq f (fix x))
  (if (> x f) (1+ f) f))

;; the list from index K on / COUNT elements of LST starting at index K
(defun cab:nthcdr (k lst)
  (while (> k 0) (setq lst (cdr lst) k (1- k)))
  lst)
(defun cab:sublist (lst k count / out)
  (setq lst (cab:nthcdr k lst))
  (while (> count 0)
    (setq out   (cons (car lst) out)
          lst   (cdr lst)
          count (1- count)))
  (reverse out))

;; normalize an angle into [0, 2pi)
(defun cab:norm-ang (a)
  (while (< a 0.0) (setq a (+ a (* 2.0 pi))))
  (while (>= a (* 2.0 pi)) (setq a (- a (* 2.0 pi))))
  a)

;; smallest signed angular difference (to - from), in (-pi, pi]
(defun cab:signed-dang (from to / d)
  (setq d (cab:norm-ang (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

;; ---- circle / arc geometry -----------------------------------------

;; Circumcenter of three points, nil when (nearly) collinear.
(defun cab:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
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
;; passes through Q.  0.0 when the three points are collinear, and
;; also when the arc would be a (near) full circle - P1 and P2 lying
;; at the same angle from the center makes the sweep 0 or 2*pi, which
;; no single bulge can express.  Nearly-collinear noisy survey points
;; can produce exactly that, so both ends of the range are guarded.
(defun cab:bulge-3pt (p1 q p2 / c a1 a2 aq dccw dq)
  (setq p1 (cab:2d p1) q (cab:2d q) p2 (cab:2d p2)
        c  (cab:circumcenter p1 q p2))
  (if (null c)
    0.0
    (progn
      (setq a1   (angle c p1)
            a2   (angle c p2)
            aq   (angle c q)
            dccw (cab:norm-ang (- a2 a1))
            dq   (cab:norm-ang (- aq a1)))
      (cond
        ((< dccw 1.0e-9) 0.0)                       ; degenerate sweep
        ((> dccw (- (* 2.0 pi) 1.0e-9)) 0.0)        ; degenerate sweep
        ((<= dq dccw) (cab:tan (/ dccw 4.0)))        ; CCW arc through Q
        (T (- (cab:tan (/ (- (* 2.0 pi) dccw) 4.0)))))))) ; CW through Q

;; Arc geometry of a bulged segment: (center radius angStart angEnd)
;; where the arc runs CCW from angStart to angEnd when bulge > 0 and
;; CW when bulge < 0.  nil for a straight segment.
(defun cab:arc-geom (p1 p2 b / ch dir apex c)
  (if (< (abs b) 1.0e-9)
    nil
    (progn
      (setq p1   (cab:2d p1)
            p2   (cab:2d p2)
            ch   (cab:dist p1 p2)
            dir  (cab:scl (cab:sub p2 p1) (/ 1.0 ch))
            ;; sagitta = (chord/2)*bulge; a positive (CCW) bulge apex
            ;; lies to the RIGHT of the p1->p2 chord direction
            apex (cab:add (cab:mid p1 p2)
                         (cab:scl (cab:perp dir) (* -0.5 ch b)))
            c    (cab:circumcenter p1 apex p2))
      (if (null c)
        nil
        (list c (cab:dist c p1) (angle c p1) (angle c p2))))))

;; Distance from point P to segment (p1 p2 bulge).
(defun cab:seg-dist (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep rel)
  (setq p  (cab:2d p)
        p1 (cab:2d (car seg))
        p2 (cab:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    ;; straight: project onto the segment, clamp to its ends
    (progn
      (setq v    (cab:sub p2 p1)
            w    (cab:sub p p1)
            len2 (cab:dot v v))
      (if (< len2 1.0e-20)
        (cab:dist p p1)
        (progn
          (setq t2 (/ (cab:dot w v) len2))
          (if (< t2 0.0) (setq t2 0.0))
          (if (> t2 1.0) (setq t2 1.0))
          (cab:dist p (cab:add p1 (cab:scl v t2))))))
    ;; arc: radial distance when P falls inside the sweep, else the
    ;; nearer endpoint
    (progn
      (setq g (cab:arc-geom p1 p2 b))
      (if (null g)
        (min (cab:dist p p1) (cab:dist p p2))
        (progn
          (setq c  (car g)  r (cadr g)
                a1 (caddr g) a2 (cadddr g)
                ap (angle c p))
          (if (> b 0.0)
            (setq sweep (cab:norm-ang (- a2 a1)) rel (cab:norm-ang (- ap a1)))
            (setq sweep (cab:norm-ang (- a1 a2)) rel (cab:norm-ang (- ap a2))))
          (if (<= rel sweep)
            (abs (- (cab:dist p c) r))
            (min (cab:dist p p1) (cab:dist p p2))))))))

;; Bulge of the arc that starts at A with tangent direction TANG
;; (radians) and ends at B.  The angle between a chord and the tangent
;; at its end is half the included angle, so delta = 2*phi.
(defun cab:tangent-bulge (a tang b / phi)
  (setq phi (cab:signed-dang tang (angle (cab:2d a) (cab:2d b))))
  (cab:tan (/ phi 2.0)))

;; Tangent direction (radians) at the END of the arc from A to B with
;; the given bulge: chord direction + delta/2, delta = 4*atan(bulge).
(defun cab:end-tangent (a b bulge)
  (+ (angle (cab:2d a) (cab:2d b)) (* 2.0 (atan bulge))))

;; Position of P along segment (p1 p2 bulge) as a 0..1 parameter,
;; used only to ORDER candidate points along the segment.
(defun cab:seg-param (p seg / p1 p2 b v w len2 g c a1 a2 ap sweep rel)
  (setq p  (cab:2d p)
        p1 (cab:2d (car seg))
        p2 (cab:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    (progn
      (setq v (cab:sub p2 p1) w (cab:sub p p1) len2 (cab:dot v v))
      (if (< len2 1.0e-20) 0.0 (/ (cab:dot w v) len2)))
    (progn
      (setq g (cab:arc-geom p1 p2 b))
      (if (null g)
        0.0
        (progn
          (setq c (car g) a1 (caddr g) a2 (cadddr g) ap (angle c p))
          (if (> b 0.0)
            (setq sweep (cab:norm-ang (- a2 a1))
                  rel   (cab:norm-ang (- ap a1)))
            (setq sweep (cab:norm-ang (- a1 a2))
                  rel   (- (cab:norm-ang (- a1 a2))
                           (cab:norm-ang (- ap a2)))))
          (if (< sweep 1.0e-10) 0.0 (/ rel sweep)))))))

;; ---- entity -> segment extraction ----------------------------------
;; A segment is (startPt endPt bulge), 2D points.

(defun cab:lw-segs (ed / pts bls item segs n closed)
  ;; collect (10) vertices and their (42) bulges, in order
  (setq pts nil bls nil)
  (foreach item ed
    (cond
      ((= (car item) 10)
       (setq pts (cons (cab:2d (cdr item)) pts)
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
               (< (cab:dist (last pts) (car pts)) *CAB-CHAIN-FUZZ*)))
    (if (>= (cab:dist (last pts) (car pts)) *CAB-CHAIN-FUZZ*)
      (setq segs (cons (list (last pts) (car pts) (last bls)) segs))))
  (reverse segs))

(defun cab:pl-segs (en / ed sub pts bls segs n closed)
  ;; heavy (old-style) 2D POLYLINE: walk its VERTEX sub-entities
  (setq ed (entget en)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        pts nil bls nil
        sub (entnext en))
  (while (and sub (= "VERTEX" (cdr (assoc 0 (setq ed (entget sub))))))
    ;; skip spline/fit control vertices (flag bits 1 and 16)
    (if (= 0 (logand 17 (cond ((cdr (assoc 70 ed))) (0))))
      (setq pts (cons (cab:2d (cdr (assoc 10 ed))) pts)
            bls (cons (cond ((cdr (assoc 42 ed))) (0.0)) bls)))
    (setq sub (entnext sub)))
  (setq pts (reverse pts) bls (reverse bls) segs nil n 0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  (if (and closed (> (length pts) 2))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun cab:ent-segs (en / ed typ c r a1 a2 delta)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (cab:2d (cdr (assoc 10 ed)))
                 (cab:2d (cdr (assoc 11 ed)))
                 0.0)))
    ((= typ "ARC")
     (setq c  (cab:2d (cdr (assoc 10 ed)))
           r  (cdr (assoc 40 ed))
           a1 (cdr (assoc 50 ed))
           a2 (cdr (assoc 51 ed))
           delta (cab:norm-ang (- a2 a1)))
     (if (< delta 1.0e-10) (setq delta (* 2.0 pi)))
     ;; a full-circle arc cannot be one bulged segment (its bulge is
     ;; infinite): hand back two semicircles instead
     (if (> delta (- (* 2.0 pi) 1.0e-9))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r) (cab:tan (/ delta 4.0))))))
    ;; a CIRCLE is a legitimate pool perimeter (round spa): two
    ;; semicircles, so the chaining and fitting code sees a normal
    ;; closed loop instead of reporting a gap
    ((= typ "CIRCLE")
     (setq c (cab:2d (cdr (assoc 10 ed)))
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
    ((= typ "LWPOLYLINE") (cab:lw-segs ed))
    ((= typ "POLYLINE") (cab:pl-segs en))
    (T nil)))

;; ---- chain loose segments into one closed loop ----------------------
;; Returns the ordered segment list, or nil (with a message) on failure.
(defun cab:chain (segs / loop start end found s rest)
  (if (null segs)
    nil
    (progn
      (setq loop  (list (car segs))
            start (car (car segs))
            end   (cadr (car segs))
            segs  (cdr segs))
      (while (and segs
                  (>= (cab:dist end start) *CAB-CHAIN-FUZZ*))
        (setq found nil rest nil)
        (foreach s segs
          (cond
            (found (setq rest (cons s rest)))
            ((< (cab:dist end (car s)) *CAB-CHAIN-FUZZ*)
             (setq found s))
            ((< (cab:dist end (cadr s)) *CAB-CHAIN-FUZZ*)
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
         (princ "\nCABHD: gap in the POOL perimeter - could not close the loop.")
         nil)
        ((>= (cab:dist end start) *CAB-CHAIN-FUZZ*)
         (princ "\nCABHD: the POOL perimeter does not close.")
         nil)
        (T
         (if segs
           (princ (strcat "\nCABHD: warning - "
                          (itoa (length segs))
                          " POOL segment(s) not part of the closed loop were ignored.")))
         (reverse loop))))))

;; ---- span fitting helpers --------------------------------------------
;; A "span" is one candidate segment from A to B judged against QS, the
;; survey points it is supposed to represent.

;; Worst distance from any of QS to the segment (A B bulge).
(defun cab:span-dev (a b bul qs / seg mx d q)
  (setq seg (list a b bul) mx 0.0)
  (foreach q qs
    (setq d (cab:seg-dist q seg))
    (if (> d mx) (setq mx d)))
  mx)

;; The miss percentage in force for the current run: the command binds
;; cab-miss-pct from the user's answer; Enter keeps the standard value.
(defun cab:misspct ()
  (if cab-miss-pct cab-miss-pct *CAB-MISS-PCT*))

;; The "on the shape" threshold in force for the current run.  It
;; scales with the tolerance (a quarter of it, never below
;; *CAB-ON-EPS*): if the user accepts 4 inches of error, a point 1 inch
;; off is plainly still ON the shape, and counting it as a miss would
;; burn the whole allowance on the first span and starve the rest of
;; the loop into single-point stubs.  cab-on-eps is bound per run by
;; the command and per pass by cab:fit-pass.
(defun cab:oneps ()
  (if cab-on-eps cab-on-eps *CAB-ON-EPS*))

;; How many of QS sit farther than the on-the-shape threshold from the
;; segment - the points that would eat into the miss allowance.
(defun cab:span-misses (a b bul qs / seg c q lim)
  (setq seg (list a b bul) c 0 lim (cab:oneps))
  (foreach q qs
    (if (> (cab:seg-dist q seg) lim) (setq c (1+ c))))
  c)

;; Best single arc from A to B over the points QS: candidate bulges are
;; the exact 3-point fits through a few of the points plus the average
;; of them all; the one with the smallest worst-case deviation wins.
;; Returns (bulge . maxdev).
(defun cab:span-arc (a b qs / bls sum bl m cands best bd d)
  (setq bls (mapcar '(lambda (q) (cab:bulge-3pt a q b)) qs)
        sum 0.0
        m   (length qs))
  (foreach bl bls (setq sum (+ sum bl)))
  (setq cands (list (/ sum m) (nth (/ m 2) bls)))
  (if (>= m 4)
    (setq cands (append cands (list (nth (/ m 4) bls)
                                    (nth (/ (* 3 m) 4) bls)))))
  (setq best nil bd nil)
  (foreach bl cands
    (setq d (cab:span-dev a b bl qs))
    (if (or (null bd) (< d bd)) (setq best bl bd d)))
  (cons best bd))

;; Radius of the arc (A B bulge); nil for a straight segment.
(defun cab:bulge-radius (a b bl / h)
  (if (< (abs bl) 1.0e-9)
    nil
    (progn
      (setq h (/ (cab:dist a b) 2.0))
      (/ (* h (1+ (* bl bl))) (* 2.0 (abs bl))))))

;; Bulge of the arc from A to B with radius R, on the same side and
;; with the same minor/major-arc character as reference bulge BREF.
;; nil when R is too small to span the chord.
(defun cab:radius-bulge (a b r bref / h s bl)
  (setq h (/ (cab:dist a b) 2.0))
  (if (or (< r h) (< h 1.0e-9))
    nil
    (progn
      (setq s  (sqrt (- (* r r) (* h h)))
            bl (if (> (abs bref) 1.0)
                 (/ (+ r s) h)              ; major arc
                 (/ (- r s) h)))            ; minor arc
      (if (< bref 0.0) (- bl) bl))))

;; Try to snap the arc A->B (free-fit bulge BL over points QS) to a
;; "nice" radius - whole feet first, then half feet, then whole inches
;; (*CAB-NICE-RADII*) - keeping every point within TOL and at most LEFT
;; of them off by more than *CAB-ON-EPS*.  When WIN (a bulge interval)
;; is given the snapped bulge must stay inside it, so snapping never
;; breaks the tangency window.  The nearer multiple on each tier is
;; tried first; the arc's endpoints never move.  Returns
;; (bulge . misses) of the snapped arc, or nil.
(defun cab:snap-arc (a b bl qs tol left win / r0 h best tier lo hi
                                              cands r bl2 mis)
  (setq r0   (cab:bulge-radius a b bl)
        h    (/ (cab:dist a b) 2.0)
        best nil)
  (if (and r0 (< r0 1.0e6))       ; a huge radius is basically straight
    (foreach tier *CAB-NICE-RADII*
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
                (setq bl2 (cab:radius-bulge a b r bl))
                (if (and bl2
                         (or (null win)
                             (and (>= bl2 (car win)) (<= bl2 (cdr win))))
                         (<= (cab:span-dev a b bl2 qs) tol)
                         (<= (setq mis (cab:span-misses a b bl2 qs))
                             left))
                  (setq best (cons bl2 mis))))))))))
  best)

;; ---- arc segment re-fitting ------------------------------------------
;; Re-fit one curved segment from P1 to P2 (original bulge B) through
;; CANDS, its nearby survey points sorted along the segment.  Returns a
;; list of one or more segments (p1 p2 bulge):
;;   * no candidates          -> the original arc, endpoints updated
;;   * a nice-radius (foot / half-foot / inch) arc holds every point
;;     within TOL and the miss allowance (cab-miss-left, set by the
;;     command) can absorb the off points
;;                            -> that single snapped arc, preferred
;;                               even over an exact free fit
;;   * one arc holds them all -> that single arc
;;   * one free arc keeps every point within TOL and the allowance
;;     covers it              -> that single arc; fewer curves beats
;;                               exactness, by design
;;   * otherwise              -> a chain of arcs passing exactly
;;                               through every point, each carrying
;;                               the last one's tangent on as far as
;;                               it can without looping (cab:tame-bulge)
;; The bulge that carries tangent TANG on from PREV to Q, tamed: the
;; drawn arc's own bulge B is the shape being trusted here, so a
;; sub-arc may curve that far, or as far as two neighbouring points
;; justify, whichever is more - but no further.  Carrying a tangent on
;; unchecked is what let this subdivision spiral into loops of its own.
(defun cab:tame-bulge (prev tang q b)
  (cab:cap-b (cab:tangent-bulge prev tang q)
            (max (abs b) (cab:max-bulge prev q nil))))

(defun cab:fit-arc-seg (p1 p2 b cands tol / ar bavg maxres mis nb q segs
                                            prev tang sn)
  (if (null cands)
    (list (list p1 p2 b))
    (progn
      (setq ar     (cab:span-arc p1 p2 cands)
            bavg   (car ar)
            maxres (cdr ar)
            sn     (cab:snap-arc p1 p2 bavg cands tol cab-miss-left nil))
      (cond
        ;; a nice-radius arc holds every point: take it first
        (sn
         (setq cab-miss-left (- cab-miss-left (cdr sn)))
         (list (list p1 p2 (car sn))))
        ;; a single free arc genuinely holds every point
        ((<= maxres *CAB-FIT-EPS*)
         (list (list p1 p2 bavg)))
        ;; a single arc is close enough and the allowance covers it
        ((and (<= maxres tol)
              (<= (setq mis (cab:span-misses p1 p2 bavg cands))
                  cab-miss-left))
         (setq cab-miss-left (- cab-miss-left mis))
         (list (list p1 p2 bavg)))
        ;; subdivide.  First arc runs from P1 through the 1st point to
        ;; the 2nd; every further arc starts tangent to the previous one
        ;; and lands exactly on the next point; the last lands on P2.
        ;; All points are hit exactly and every internal joint is
        ;; tangent-continuous (smooth).
        (T
         (setq nb   (cab:bulge-3pt p1 (car cands) (cadr cands))
               segs (list (list p1 (cadr cands) nb))
               tang (cab:end-tangent p1 (cadr cands) nb)
               prev (cadr cands))
         (foreach q (cddr cands)
           (setq nb   (cab:tame-bulge prev tang q b)
                 segs (cons (list prev q nb) segs)
                 tang (cab:end-tangent prev q nb)
                 prev q))
         (setq nb (cab:tame-bulge prev tang p2 b))
         (reverse (cons (list prev p2 nb) segs)))))))

;; ---- points-only / ordering-sketch mode -------------------------------

;; Pure-AutoLISP list helpers (no Visual LISP / vl-* dependency, so the
;; command works even when (vl-load-com) has not been run).

;; Remove every element equal (within fuzz) to VAL from LST.
(defun cab:remove (val lst / out x)
  (foreach x lst
    (if (not (equal x val 1.0e-9)) (setq out (cons x out))))
  (reverse out))

;; Insert (key . val) pair X into the already-sorted list LST, keeping
;; ascending order by the pair's car (key).
(defun cab:ins-car (x lst)
  (cond ((null lst) (list x))
        ((< (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (cab:ins-car x (cdr lst))))))

;; Insertion-sort a list of (key . val) pairs ascending by key.
(defun cab:sort-car (lst / out x)
  (foreach x lst (setq out (cab:ins-car x out)))
  out)

(defun cab:dedupe (pts / out q p dup)
  (foreach q pts
    (setq dup nil)
    (foreach p out
      (if (< (cab:dist p q) *CAB-EXACT-EPS*) (setq dup T)))
    (if (not dup) (setq out (cons q out))))
  (reverse out))

;; T when the chained loop contains at least one curved segment
(defun cab:has-arcs (loop / r)
  (foreach s loop (if (>= (abs (caddr s)) 1.0e-9) (setq r T)))
  r)

;; Order points into a closed tour: nearest-neighbour walk from the
;; leftmost point, then 2-opt passes to remove crossings.
(defun cab:order-points (pts / start cur tour rest best bd q d n i j k
                              pass improved ti ti1 tj tj1 delta head midl
                              taill)
  (setq start (car pts))
  (foreach q (cdr pts)
    (if (or (< (car q) (car start))
            (and (= (car q) (car start)) (< (cadr q) (cadr start))))
      (setq start q)))
  (setq cur  start
        rest (cab:remove start pts)
        tour (list start))
  (while rest
    (setq best nil bd nil)
    (foreach q rest
      (setq d (cab:dist cur q))
      (if (or (null bd) (< d bd)) (setq best q bd d)))
    (setq tour (cons best tour)
          cur  best
          rest (cab:remove best rest)))
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
                  delta (- (+ (cab:dist ti tj) (cab:dist ti1 tj1))
                           (+ (cab:dist ti ti1) (cab:dist tj tj1))))
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
(defun cab:loop-order (loop pts / keyed q best bd d i s tp)
  (foreach q pts
    (setq best 0 bd nil i 0)
    (foreach s loop
      (setq d (cab:seg-dist q s))
      (if (or (null bd) (< d bd)) (setq bd d best i))
      (setq i (1+ i)))
    (setq tp (cab:seg-param q (nth best loop)))
    (if (< tp 0.0) (setq tp 0.0))
    (if (> tp 1.0) (setq tp 1.0))
    (setq keyed (cons (cons (+ best tp) q) keyed)))
  (mapcar 'cdr (cab:sort-car keyed)))

;; The surveyed number carried by a point block, read from its
;; *CAB-PT-TAG* attribute ("number" on ab_pt).  nil when the block has
;; no such attribute.
;;
;; DELIBERATELY strict: no first-numeric-attribute fallback, unlike
;; ABFIND/BPCALLOUT/LHD/FITABHD and cal:block-number.  The fitter
;; consumes every point it is handed, so a stray numbered block (a
;; detail bubble, a keynote) silently joining the survey would warp the
;; whole fit - a dropped untagged point is the visible, recoverable
;; failure.  Reviewed 2026-08-27 and kept on purpose; this is ABHD's
;; pf:block-number line, held here too.
(defun cab:block-number (en / sub ed val)
  (setq sub (entnext en) val nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase *CAB-PT-TAG*)))
      (setq val (cdr (assoc 1 ed))))
    (setq sub (entnext sub)))
  val)

;; Remember a point, what to call it, and the number the run sorts it
;; by, so a miss can be reported as "Pt.17" using the number in the
;; drawing rather than a private index, and the cutoff below knows how
;; far up the survey the point sits.  Points with no number of their
;; own get the next count.
(defun cab:add-point (p nm / num)
  (setq num         (cab:num-in nm)
        npt         (1+ npt)
        pts         (cons p pts)
        cab-allpts  (cons p cab-allpts)
        cab-ptnames (cons (cons p (if (and nm (/= nm "")) nm (itoa npt)))
                          cab-ptnames)
        cab-ptkeys  (cons (cons p (if num num npt)) cab-ptkeys))
  (if num (setq cab-numbered (1+ cab-numbered))))

;; The whole number a surveyed label carries: the FIRST run of digits
;; in it, so "17", "P17" and "17A" all read as seventeen.  nil when the
;; label holds no digit at all - such a point falls back to its place
;; in the selection (see cab:add-point).
(defun cab:num-in (s / i n c out done)
  (setq out "" done nil i 1 n (if s (strlen s) 0))
  (while (and (<= i n) (null done))
    (setq c (substr s i 1))
    (cond
      ((and (>= (ascii c) 48) (<= (ascii c) 57)) (setq out (strcat out c)))
      ((/= out "") (setq done T)))            ; the run of digits ended
    (setq i (1+ i)))
  (if (= out "") nil (atoi out)))

;; What to call the surveyed point at Q.
(defun cab:pt-name (q / nm p)
  (setq nm nil)
  (foreach p cab-ptnames
    (if (and (null nm) (< (cab:dist (car p) q) *CAB-EXACT-EPS*))
      (setq nm (cdr p))))
  (if nm nm "?"))

;; The number the cutoff sorts Q by.  0 for a point that was never
;; registered, so a stray can never be cut out by surprise.
(defun cab:pt-key (q / k p)
  (setq k nil)
  (foreach p cab-ptkeys
    (if (and (null k) (< (cab:dist (car p) q) *CAB-EXACT-EPS*))
      (setq k (cdr p))))
  (if k k 0))

;; ---- the point cutoff -------------------------------------------------
;; The one rule CABHD adds to ABHD's.  A survey run rarely stops where
;; the pool edge does: the shots tracing the edge come first and the
;; rest - steps, benches, deck, depth shots - carry on in the same
;; numbering, so a hundred-point survey may hold a twenty-point
;; perimeter.  The user says how far up the numbers the edge runs, and
;; everything past that is out of the perimeter ENTIRELY: not ordered,
;; not fitted, not counted against the miss allowance, and never
;; reported as a point the line failed to hold.  It is not the omit
;; list - that picks out strays one at a time and is undone by picking
;; them again; this draws a line across the whole survey at once.

;; T when Q is inside the cutoff (no cutoff = every point is).
(defun cab:in-cut (q)
  (or (null cab-cut) (<= (cab:pt-key q) cab-cut)))

;; T when Q has been picked out of the fit at a Redo.
(defun cab:omitted-p (q / found e)
  (setq found nil)
  (foreach e cab-omitted
    (if (< (cab:dist (car e) q) *CAB-EXACT-EPS*) (setq found T)))
  found)

;; The points actually in the fit: everything selected that the cutoff
;; keeps and the user has not omitted.  Rebuilt from cab-allpts rather
;; than whittled down, so a cutoff moved at a Redo can go either way.
;; The order matches the one cab:add-point built (cab-allpts is
;; selection order, this reverses it exactly as the consing did), so a
;; rebuilt list walks the tour the same way the first pass did.
(defun cab:live-pts ( / out q)
  (setq out nil)
  (foreach q (reverse cab-allpts)
    (if (and (cab:in-cut q) (not (cab:omitted-p q)))
      (setq out (cons q out))))
  out)

;; The numbers a point list spans, as (lowest . highest); nil when the
;; list is empty.
(defun cab:key-range (qs / lo hi k q)
  (foreach q qs
    (setq k (cab:pt-key q))
    (if (or (null lo) (< k lo)) (setq lo k))
    (if (or (null hi) (> k hi)) (setq hi k)))
  (if lo (cons lo hi)))

;; How many of QS a cutoff of CUT would keep (nil = all of them).
(defun cab:cut-count (qs cut / n q)
  (setq n 0)
  (foreach q qs
    (if (or (null cut) (<= (cab:pt-key q) cut)) (setq n (1+ n))))
  n)

;; Ask how far up the numbers the pool edge runs.  Enter keeps DEF
;; (nil = every point), All clears the cutoff, and Pick reads the
;; number off a point in the drawing - hunting for a number on screen
;; beats reading it out of the survey sheet.  A cutoff that would
;; starve the fit is refused and re-asked, so the answer that comes
;; back is always one the fitter can use.  DALL is every selected
;; point, cut or not.  Asked again at every Redo, so a cutoff set too
;; low or too high costs one prompt, not a whole run.
(defun cab:ask-cut (dall def / rng ans wp q cut lim done out)
  (setq rng  (cab:key-range dall)
        lim  (min 3 (length dall))
        out  def
        done nil)
  (if rng
    (princ (strcat "\n  " (itoa (length dall))
                   " point(s) selected, numbered " (itoa (car rng))
                   " to " (itoa (cdr rng)) ".")))
  (while (null done)
    (setq done T)
    (initget 6 "Pick All")
    (setq ans (getint (strcat "\n  Include points up to [Pick/All] <"
                              (if out (itoa out) "All") ">: ")))
    (cond
      ((null ans) (setq cut out))                     ; Enter: unchanged
      ((eq 'STR (type ans))
       (if (= ans "All")
         (setq cut nil)
         (progn
           (setq wp (getpoint "\n  Pick the LAST point that belongs to the pool edge: "))
           (cond
             ((null wp) (setq cut out))
             ((setq q (cab:nearest (cab:2d wp) dall))
              (setq cut (cab:pt-key q))
              (princ (strcat "  - Pt." (cab:pt-name q)
                             " (number " (itoa cut) ")")))
             (T (setq cut out))))))
      (T (setq cut ans)))
    (if (and cut (< (cab:cut-count dall cut) lim))
      (progn
        (princ (strcat "\n  (up to " (itoa cut) " leaves "
                       (itoa (cab:cut-count dall cut))
                       " point(s) and a fit needs at least " (itoa lim)
                       " - try a higher number, or All)"))
        (setq done nil))
      (setq out cut)))
  out)

;; T when P was picked at a point the cutoff has since left out.  A
;; wall, corner or hold declared there is not a near miss to be snapped
;; onto some other point - it is a declaration about a stretch of
;; survey that is no longer in the perimeter at all, so it goes.
(defun cab:cut-away-p (p dall dlive / q live)
  (setq q    (cab:nearest p dall)
        live (cab:nearest p dlive))
  (and q
       (not (cab:in-cut q))
       (or (null live) (< (cab:dist p q) (cab:dist p live)))))

;; Declarations only hold while the points they are anchored on are
;; still in the fit.  A point that leaves - omitted at a Redo, or left
;; out by a cutoff moved at one - takes its wall, corner or hold with
;; it.
(defun cab:prune-decls (dpts / out w)
  (setq out nil)
  (foreach w cab-walls
    (if (and (cab:memb (car w) dpts) (cab:memb (cadr w) dpts))
      (setq out (cons w out))))
  (if (< (length out) (length cab-walls))
    (princ "\n  (a declared wall lost an end and was dropped)"))
  (setq cab-walls (reverse out)
        out       nil)
  (foreach w cab-corners
    (if (cab:memb w dpts) (setq out (cons w out))))
  (setq cab-corners (reverse out)
        out         nil)
  (foreach w cab-holds
    (if (cab:memb w dpts) (setq out (cons w out))))
  (if (< (length out) (length cab-holds))
    (princ "\n  (a point that left the fit was held - its hold went with it)"))
  (setq cab-holds (reverse out))
  (princ))

;; The member of LST nearest to P.
(defun cab:nearest (p lst / best bd q d)
  (setq best nil bd nil)
  (foreach q lst
    (setq d (cab:dist p q))
    (if (or (null bd) (< d bd)) (setq best q bd d)))
  best)

;; Index of point P in TOUR (exact-point fuzz), or nil.
(defun cab:tour-index (p tour / i k q)
  (setq i nil k 0)
  (foreach q tour
    (if (and (null i) (< (cab:dist p q) *CAB-EXACT-EPS*)) (setq i k))
    (setq k (1+ k)))
  i)

;; Rotate the closed TOUR so it starts at point P (used so a declared
;; straight wall never straddles the walk's origin).
(defun cab:rotate-to-point (tour p / i)
  (setq i (cab:tour-index p tour))
  (if (and i (> i 0))
    (append (cab:nthcdr i tour) (cab:sublist tour 0 i))
    tour))

;; Rotate the closed TOUR so it starts at its sharpest turn: the fitter
;; walks the loop from there, so the most corner-like point is always a
;; span endpoint and never gets buried inside a span.
(defun cab:rotate-to-corner (tour / n i prev cur next turn best bi)
  (setq n (length tour) i 0 best -1.0 bi 0)
  (repeat n
    (setq prev (nth (rem (+ i n -1) n) tour)
          cur  (nth i tour)
          next (nth (rem (1+ i) n) tour)
          turn (abs (cab:signed-dang (angle prev cur) (angle cur next))))
    (if (> turn best) (setq best turn bi i))
    (setq i (1+ i)))
  (append (cab:nthcdr bi tour) (cab:sublist tour 0 bi)))

;; Number of curved segments in a span list.
(defun cab:arc-count (spans / c sp)
  (setq c 0)
  (foreach sp spans (if (>= (abs (caddr sp)) 1.0e-9) (setq c (1+ c))))
  c)

;; ---- near-tangent span fitting ---------------------------------------
;; Arcs sit ON the survey points: every span runs from tour point to
;; tour point and its interior is fitted through the points with exact
;; 3-point arcs.  Tangency is a WINDOW, not a chain: at each joint the
;; new arc's start tangent may differ from the previous arc's end
;; tangent by at most *CAB-TANG-TOL* (8 degrees), so the perimeter
;; stays visually smooth while the points stay in charge.  A bulge
;; window is a cons (lo . hi); nil means unconstrained.

;; Allowed bulge interval for the span A->B whose START tangent must
;; lie within *CAB-TANG-TOL* of the incoming tangent TE.  WF stretches
;; that limit (see *CAB-TANG-STEPS*).  The window edges are clamped so
;; extreme (U-turn) geometry stays finite.
(defun cab:tang-window (te a b wf / tt phi alo ahi lo hi)
  (setq tt  (* *CAB-TANG-TOL* wf)
        phi (cab:signed-dang te (angle a b))
        alo (max (min (/ (- phi tt) 2.0) 1.373) -1.373)
        ahi (max (min (/ (+ phi tt) 2.0) 1.373) -1.373)
        lo  (cab:tan alo)
        hi  (cab:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Allowed bulge interval for the CLOSING span A->B whose END tangent
;; must lie within *CAB-TANG-TOL* (times WF) of the loop's start
;; tangent TS0.
(defun cab:end-window (ts0 a b wf / tt psi alo ahi lo hi)
  (setq tt  (* *CAB-TANG-TOL* wf)
        psi (cab:signed-dang (angle a b) ts0)
        alo (max (min (/ (- psi tt) 2.0) 1.373) -1.373)
        ahi (max (min (/ (+ psi tt) 2.0) 1.373) -1.373)
        lo  (cab:tan alo)
        hi  (cab:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Intersect two bulge windows.  When they don't overlap no bulge can
;; satisfy both joints, so the bulge halfway between them is used and
;; the leftover kink is split evenly across the two joints.
(defun cab:merge-windows (win win2 / lo hi)
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
(defun cab:clamp-b (b win)
  (cond ((null win) b)
        ((< b (car win)) (car win))
        ((> b (cdr win)) (cdr win))
        (T b)))

;; Closest any of QS comes to the segment (A B bulge) - used to test
;; whether an arc still passes through one of its interior points.
(defun cab:span-min (a b bul qs / seg mn d q)
  (setq seg (list a b bul) mn nil)
  (foreach q qs
    (setq d (cab:seg-dist q seg))
    (if (or (null mn) (< d mn)) (setq mn d)))
  mn)

;; ---- how far an arc is allowed to curve ------------------------------
;; The fitter used to accept any bulge the tangent window let through,
;; and the window opens all the way to a near-full circle once the
;; incoming tangent has swung round.  On a survey with real scatter
;; that let one bad joint spiral: every arc came back a semicircle,
;; each one flinging the tangent further round, until the perimeter
;; read as a string of loops.  So an arc now has to justify its
;; curvature with the points it covers.

;; Total turning of the polyline A -> QS... -> B, in radians - how far
;; round the run of points this span sits on actually swings.
(defun cab:span-turn (a b qs / chain tot)
  (setq chain (cons a (append qs (list b)))
        tot   0.0)
  (while (cddr chain)
    (setq tot   (+ tot (abs (cab:signed-dang
                              (angle (car chain) (cadr chain))
                              (angle (cadr chain) (caddr chain)))))
          chain (cdr chain)))
  tot)

;; The steepest bulge this span's own points justify: it may sweep as
;; far as they turn, plus *CAB-ARC-SLACK*.  A span between two
;; neighbours covers no turn, so it gets the slack alone.
(defun cab:max-bulge (a b qs)
  (cab:tan (min (/ (+ (cab:span-turn a b qs) *CAB-ARC-SLACK*) 4.0) 1.373)))

;; Clamp bulge B to +/- MX.
(defun cab:cap-b (b mx)
  (cond ((> b mx) mx) ((< b (- mx)) (- mx)) (T b)))

;; How the arc (A B BUL) treats the points QS, in one pass:
;;   (written-off  worst deviation of the rest  misses among the rest)
;; Only a point PLAINLY off - further than *CAB-DROP-MULT* times TOL -
;; may be written off; that is what separates a bad shot from a
;; feature, and writing one off is what keeps a bad shot from
;; shattering the span into stubs.  A point that misses by merely a
;; little still counts against the fit, so the span stops at it as it
;; always did.  The caller rations how many may go.
(defun cab:span-score (a b bul qs tol / seg drop dev mis lim d q)
  (setq seg (list a b bul) drop 0 dev 0.0 mis 0 lim (cab:oneps))
  (foreach q qs
    (setq d (cab:seg-dist q seg))
    (if (> d (* *CAB-DROP-MULT* tol))
      (setq drop (1+ drop))
      (progn
        (if (> d dev) (setq dev d))
        (if (> d lim) (setq mis (1+ mis))))))
  (list drop dev mis))

;; The points of QS this arc actually holds (within TOL) - the ones it
;; wrote off must not go on to steer the nice-radius snap.
(defun cab:span-kept (a b bul qs tol / seg out q)
  (setq seg (list a b bul))
  (foreach q qs
    (if (<= (cab:seg-dist q seg) tol) (setq out (cons q out))))
  (reverse out))

;; T when score SC beats KEY: fewer points written off, or as few and
;; a closer fit.
(defun cab:better (sc key)
  (or (< (car sc) (car key))
      (and (= (car sc) (car key)) (< (cadr sc) (cadr key)))))

;; Best bulge for the span A->B over interior points QS, restricted to
;; the tangent window WIN (nil = free) and to what the span's own
;; points justify (cab:max-bulge - no arc may come back as a loop).
;; EXACT 3-POINT ARCS COME FIRST: an unclamped 3-point bulge through
;; one of the actual interior points - so the arc's middle lands ON a
;; survey point - is preferred whenever one holds the span within TOL
;; and LEFT misses.  Compromise bulges (average / window-clamped /
;; window edges), which float between the points, are used only when
;; no exact arc works.  DLIM points may be written off - left plainly
;; off, see cab:span-score - instead of holding the span back; the
;; fewer written off the better, and a tie goes to the closer fit.
;; Returns (bulge dev misses exactflag written-off).
(defun cab:span-fit (a b qs win tol left dlim / bls m sum bl cands best
                                               bkey mx sc)
  (setq bls  (mapcar '(lambda (q) (cab:bulge-3pt a q b)) qs)
        m    (length qs)
        mx   (cab:max-bulge a b qs)
        best nil
        bkey nil)
  ;; exact candidates: through an interior point, inside the window,
  ;; and no steeper than the points themselves justify
  (foreach bl bls
    (if (and (<= (abs bl) mx)
             (or (null win)
                 (and (>= bl (car win)) (<= bl (cdr win)))))
      (progn
        (setq sc (cab:span-score a b bl qs tol))
        ;; an exact arc still has to HOLD the span - the points it did
        ;; not write off must all be inside TOL - or the compromise
        ;; bulges below never get their turn
        (if (and (<= (cadr sc) tol)
                 (<= (car sc) dlim)
                 (<= (caddr sc) left)
                 (or (null bkey) (cab:better sc bkey)))
          (setq best (list bl (cadr sc) (caddr sc) T (car sc))
                bkey sc)))))
  ;; compromise candidates, only when no exact arc holds the span
  (if (null best)
    (progn
      (setq sum 0.0)
      (foreach bl bls (setq sum (+ sum bl)))
      (setq cands (list (/ sum m) (nth (/ m 2) bls)))
      (if (>= m 4)
        (setq cands (append cands (list (nth (/ m 4) bls)
                                        (nth (/ (* 3 m) 4) bls)))))
      (if win
        (setq cands (append (mapcar '(lambda (bl) (cab:clamp-b bl win))
                                    cands)
                            (list (car win) (cdr win)
                                  (/ (+ (car win) (cdr win)) 2.0)))))
      (setq cands (mapcar '(lambda (bl) (cab:cap-b bl mx)) cands))
      (foreach bl cands
        (setq sc (cab:span-score a b bl qs tol))
        (if (or (null bkey) (cab:better sc bkey))
          (setq best (list bl (cadr sc) (caddr sc) nil (car sc))
                bkey sc)))))
  best)

;; The longest feasible span from POS, allowing DLIM of the points it
;; covers to be written off (0 = it must hold every one of them).  The
;; tangent window is stretched by degrees rather than abandoned; only
;; when even the widest step finds nothing does this return nil and
;; the stub in cab:span-loop take over.  Returns
;; (length bulge misses window written-off) or nil.
(defun cab:grow-span (tour pos te ts0 sharp nogrow lim tol left dlim pro
                     / n a best bstx steps wf len go bnd win qs lm dm
                       fr)
  (setq n     (length tour)
        a     (nth pos tour)
        best  nil
        bstx  nil
        steps *CAB-TANG-STEPS*)
  (while (and (null best) steps)
    (setq wf    (car steps)
          steps (cdr steps)
          len   2
          go    T)
    (while (and go (<= len lim))
      (if (nth (rem (+ pos len -1) n) nogrow)
        (setq go nil)             ; never bury a corner or a wall point
        (progn
          (setq bnd (nth (rem (+ pos len) n) tour)
                win (if te (cab:tang-window te a bnd wf)))
          ;; the span that closes the loop must also end within the
          ;; tangent window of the loop's start
          (if (and (= (+ pos len) n) (not (car sharp)) ts0)
            (setq win (cab:merge-windows win
                                        (cab:end-window ts0 a bnd wf))))
          (setq qs (cab:sublist tour (1+ pos) (1- len))
                lm (if pro
                     (min left (cab:ceil (* (cab:misspct) len)))
                     left)
                dm (if (> dlim 0)
                     (min dlim (cab:ceil (* *CAB-DROP-PCT* len)))
                     0)
                fr (cab:span-fit a bnd qs win tol lm dm))
          (if (and (<= (cadr fr) tol) (<= (caddr fr) lm)
                   (<= (nth 4 fr) dm))
            (progn
              (setq best (list len (car fr) (caddr fr) win (nth 4 fr)))
              (if (cadddr fr) (setq bstx best))
              (setq len (1+ len)))
            (setq go nil))))))
  ;; an arc that floats between the points has to earn its keep:
  ;; only take it when it covers at least 2 more points than the
  ;; longest arc that passes exactly through a point
  (if (and bstx best (< (car best) (+ (car bstx) 2)))
    (setq best bstx))
  best)

;; Cover the rotated closed TOUR with arcs whose endpoints sit ON the
;; tour points, every joint within *CAB-TANG-TOL* of tangent.  Sharp
;; corners stay free kinks.  TE0 (may be nil) seeds the first span's
;; tangent window - used to close the seam.  LEFT is the miss
;; allowance for this pass; when PRO is true each span may spend only
;; its own fair share of it, so one greedy span cannot exhaust the
;; budget and starve the rest of the loop (the curve cap turns PRO off
;; because there the whole point is to trade accuracy for few curves).
;; Straight walls the user declared (cab-walls, bound by the command as
;; snapped point pairs) are emitted verbatim as LINE spans; ordinary
;; spans may neither swallow nor cross them.  Returns the segment list.
(defun cab:span-loop (tour tol left drop te0 pro / n sharp i prev cur
                                                  next turn strtshp
                                                  segs pos te ts0 lim a
                                                  best alt len bnd win
                                                  qs bl mis sn dev0
                                                  anch phi stub walls w
                                                  i1 i2 fwd nogrow f
                                                  wrec)
  (setq n (length tour))
  ;; flag the sharp corners (intentional kinks, window resets): turns
  ;; sharper than *CAB-CORNER-ANG*, plus every point the user declared
  ;; a corner - there the tangency rule is waived on purpose
  (setq sharp nil i 0)
  (repeat n
    (setq prev (nth (rem (+ i n -1) n) tour)
          cur  (nth i tour)
          next (nth (rem (1+ i) n) tour)
          turn (abs (cab:signed-dang (angle prev cur) (angle cur next))))
    (setq sharp (cons (or (> turn *CAB-CORNER-ANG*)
                          (cab:memb cur cab-corners))
                      sharp)
          i     (1+ i)))
  (setq sharp (reverse sharp))
  ;; map the declared straight walls onto tour indices, walking the
  ;; short way around; the tour was rotated so none straddles index 0
  (setq walls nil)
  (foreach w cab-walls
    (setq i1 (cab:tour-index (car w) tour)
          i2 (cab:tour-index (cadr w) tour))
    (if (and i1 i2 (/= i1 i2))
      (progn
        (setq fwd (rem (+ (- i2 i1) n) n))
        (if (> (* 2 fwd) n)
          (setq i1 i2 fwd (- n fwd)))
        (if (<= (+ i1 fwd) n)
          (setq walls (cons (list i1 (+ i1 fwd)) walls))))))
  ;; indices ordinary spans may not swallow: sharp corners, every
  ;; index a declared wall covers, and every HELD point - a span may
  ;; end on a held point (landing on it exactly) but never bury it
  (setq nogrow nil i 0)
  (repeat n
    (setq f (nth i sharp))
    (foreach w walls
      (if (and (>= i (car w)) (<= i (cadr w))) (setq f T))
      (if (and (= (cadr w) n) (= i 0)) (setq f T)))
    (if (cab:memb (nth i tour) cab-holds) (setq f T))
    (setq nogrow (cons f nogrow)
          i      (1+ i)))
  (setq nogrow  (reverse nogrow)
        strtshp (car sharp)
        segs    nil
        pos     0
        te      (if strtshp nil te0)
        ts0     nil
        stub    nil)                ; was the span just emitted a stub?
  (while (< pos n)
    (setq a    (nth pos tour)
          wrec (assoc pos walls))
    (if wrec
      ;; ---- a declared straight wall starts here: emit it verbatim --
      (progn
        (setq len  (- (cadr wrec) pos)
              bnd  (nth (rem (cadr wrec) n) tour)
              qs   (cab:sublist tour (1+ pos) (1- len))
              mis  (cab:span-misses a bnd 0.0 qs)
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
    ;; one span may never swallow the whole loop: the first span stops
    ;; one point short so the result always has at least two real
    ;; segments instead of a single zero-length one
    (setq lim  (if (= pos 0) (1- (- n pos)) (- n pos))
          best (cab:grow-span tour pos te ts0 sharp nogrow lim tol
                             left 0 pro))
    ;; Writing a point off is a last resort: it is offered only where
    ;; the span stopped growing - something is in the way - and kept
    ;; only when every point given up bought at least two more points
    ;; of span.  What may be given up at all is the narrow thing: a
    ;; point plainly off (cab:span-score), never one that merely costs
    ;; a segment.  A span that found nothing is worth one point (the
    ;; stub below), so the comparison always has a floor to beat - and
    ;; a span can never give up every point it covers.
    (if (and (> drop 0) (or (null best) (< (car best) lim)))
      (progn
        (setq alt (cab:grow-span tour pos te ts0 sharp nogrow lim tol
                                left drop pro))
        (if (and alt
                 (> (nth 4 alt) 0)
                 (>= (car alt) (+ (if best (car best) 1)
                                  (* 2 (nth 4 alt)))))
          (setq best alt))))
    (if (null best)
      ;; Stub to the very next point.  One stub carries the incoming
      ;; tangent on exactly, as it always has - but a stub turns its
      ;; arc twice as far as the chord ran, so a SECOND stub straight
      ;; after it doubles the mismatch, a third doubles it again, and
      ;; the bulges saturate as semicircles: that runaway is what
      ;; turned a shaky survey into spaghetti.  So once the walk is
      ;; stubbing along, a stub keeps only what the tangent window
      ;; allows and gives the rest up as a kink at the joint - and the
      ;; mismatch decays instead of running away.
      (progn
        (setq bnd (nth (rem (1+ pos) n) tour))
        (if te
          (progn
            (setq phi (cab:signed-dang te (angle a bnd)))
            (if stub
              (setq phi (max (- *CAB-TANG-TOL*)
                             (min *CAB-TANG-TOL* phi))))
            (setq bl (cab:tan (/ phi 2.0)))
            (if (and (= (1+ pos) n) (not strtshp) ts0)
              ;; closing stub: split the kink between both joints
              (setq bl (/ (+ bl (cab:tan (/ (cab:signed-dang (angle a bnd)
                                                           ts0)
                                           2.0)))
                          2.0)))
            (setq bl (cab:cap-b bl (cab:max-bulge a bnd nil))))
          (setq bl 0.0))
        (setq best (list 1 bl 0 nil 0)
              stub T))
      ;; nice-radius snap inside the same tangent window, over the
      ;; points the arc actually holds - the ones it wrote off must
      ;; not drag the snap around.  A snap may never pull the arc off
      ;; its points: covered points may only move a hair
      ;; (*CAB-SNAP-EPS*) beyond where they already sat, an arc that
      ;; passed through an interior point must still pass through one
      ;; after snapping, and it may not curve past what the points
      ;; justify.
      (progn
        (setq len  (car best)
              bl   (cadr best)
              win  (cadddr best)
              bnd  (nth (rem (+ pos len) n) tour)
              qs   (cab:span-kept a bnd bl
                                 (cab:sublist tour (1+ pos) (1- len))
                                 tol)
              dev0 (cab:span-dev a bnd bl qs)
              anch (and qs
                        (<= (cab:span-min a bnd bl qs)
                            (* 2.0 *CAB-FIT-EPS*)))
              sn   (cab:snap-arc a bnd bl qs
                                (max dev0 *CAB-SNAP-EPS*) left win))
        (if (and sn
                 (<= (abs (car sn)) (cab:max-bulge a bnd qs))
                 (or (not anch)
                     (<= (cab:span-min a bnd (car sn) qs)
                         (* 2.0 *CAB-FIT-EPS*))))
          (setq best (list len (car sn) (cdr sn) win (nth 4 best))))
        (setq stub nil)))
    (setq len  (car best)
          bl   (cadr best)
          mis  (caddr best)
          bnd  (nth (rem (+ pos len) n) tour)
          segs (cons (list a bnd bl) segs)
          left (- left mis)
          drop (- drop (nth 4 best)))
    (if (and (null ts0) (not strtshp))
      (setq ts0 (- (angle a bnd) (* 2.0 (atan bl)))))
    (setq pos (+ pos len)
          te  (if (nth (rem pos n) sharp)
                nil
                (+ (angle a bnd) (* 2.0 (atan bl))))))))
  (reverse segs))

;; Tangent mismatch at the loop's closing joint (radians).
(defun cab:seam-kink (segs / sl sf te ts)
  (setq sl (last segs)
        sf (car segs)
        te (+ (angle (car sl) (cadr sl)) (* 2.0 (atan (caddr sl))))
        ts (- (angle (car sf) (cadr sf)) (* 2.0 (atan (caddr sf)))))
  (abs (cab:signed-dang te ts)))

;; One full fit; if the seam closes with more than *CAB-TANG-TOL* of
;; kink, refit once seeding the first span's window with the arrival
;; tangent, and keep whichever seam is straighter.  The on-the-shape
;; threshold is bound here so it tracks this pass's tolerance.
(defun cab:fit-pass (tour tol left drop pro / segs k1 sl te0 segs2
                                             cab-on-eps)
  (setq cab-on-eps (max *CAB-ON-EPS* (* 0.25 tol))
        segs      (cab:span-loop tour tol left drop nil pro)
        k1        (cab:seam-kink segs))
  (if (> k1 (+ *CAB-TANG-TOL* 0.001))
    (progn
      (setq sl    (last segs)
            te0   (+ (angle (car sl) (cadr sl))
                     (* 2.0 (atan (caddr sl))))
            segs2 (cab:span-loop tour tol left drop te0 pro))
      (if (< (cab:seam-kink segs2) k1) (setq segs segs2))))
  segs)

;; Points-only / ordering-sketch fit: arcs on the points, joints
;; within *CAB-TANG-TOL* of tangent, nice radii.  LEFT is the miss
;; allowance the walk may spend and PRO whether each span is held to
;; its own fair share of it - lifting both is what buys long arcs at
;; an unchanged tolerance, which is how the "few" candidate trades
;; curves for nothing but slack the user already granted.  MAXARCS,
;; when set, is enforced by refitting the whole loop with a
;; progressively relaxed tolerance, which keeps the tangent windows
;; intact.  The fewest-curves result seen is kept, so an unreachably
;; small cap still returns the smallest fit possible - never the
;; biggest.
(defun cab:coarse-loop (tour tol maxarcs left drop pro / segs segs2 tol2
                                                        tries)
  ;; start the walk at a declared wall or corner when there is one, so
  ;; neither straddles the walk's origin; otherwise at the sharpest turn
  (setq tour (cond
               (cab-walls   (cab:rotate-to-point tour (car (car cab-walls))))
               (cab-corners (cab:rotate-to-point tour (car cab-corners)))
               (T          (cab:rotate-to-corner tour)))
        segs (cab:fit-pass tour tol left drop pro))
  ;; the cap deliberately buys few curves with accuracy, so the refits
  ;; drop both the miss allowance and the per-span fair share
  (if maxarcs
    (progn
      (setq tol2 tol tries 0)
      (while (and (> (cab:arc-count segs) maxarcs) (< tries 40))
        (setq tol2  (* tol2 1.4)
              tries (1+ tries)
              segs2 (cab:fit-pass tour tol2 1000000 drop nil))
        (if (< (cab:arc-count segs2) (cab:arc-count segs))
          (setq segs segs2)))))
  segs)

;; ---- self-intersection check -----------------------------------------
;; A loop that crosses itself almost always means the automatic point
;; ordering went around a narrow waist the wrong way.  We cannot fix
;; that from the points alone, but we can spot it and say so.

;; Cross product of (P-O) x (Q-O); its sign says which side Q is on.
(defun cab:cross3 (o p q)
  (- (* (- (car p) (car o)) (- (cadr q) (cadr o)))
     (* (- (cadr p) (cadr o)) (- (car q) (car o)))))

;; T when segments A-B and C-D properly cross.  Touching or shared
;; endpoints give a zero product and do not count.
(defun cab:segs-cross (a b c d / d1 d2 d3 d4)
  (setq d1 (cab:cross3 a b c) d2 (cab:cross3 a b d)
        d3 (cab:cross3 c d a) d4 (cab:cross3 c d b))
  (and (< (* d1 d2) 0.0) (< (* d3 d4) 0.0)))

;; Sample the fitted loop into a point list; arcs get intermediate
;; points so a bulging arc's real path is tested, not just its chord.
(defun cab:loop-pts (segs / out s g c r a1 a2 sweep k j aa)
  (setq out nil)
  (foreach s segs
    (setq out (cons (cab:2d (car s)) out))
    (if (>= (abs (caddr s)) 1.0e-9)
      (progn
        (setq g (cab:arc-geom (car s) (cadr s) (caddr s)))
        (if g
          (progn
            (setq c  (car g)   r  (cadr g)
                  a1 (caddr g) a2 (cadddr g))
            (if (> (caddr s) 0.0)
              (setq sweep (cab:norm-ang (- a2 a1)))
              (setq sweep (- (cab:norm-ang (- a1 a2)))))
            (setq k 4 j 1)
            (while (< j k)
              (setq aa  (+ a1 (* sweep (/ (float j) (float k))))
                    out (cons (list (+ (car c) (* r (cos aa)))
                                    (+ (cadr c) (* r (sin aa))))
                              out)
                    j   (1+ j))))))))
  (reverse out))

;; T when the fitted loop crosses itself.
(defun cab:self-crosses (segs / p n found ti tj i j a b c d)
  (setq p (cab:loop-pts segs))
  (if (< (length p) 4)
    nil
    (progn
      (setq p     (append p (list (car p)))  ; close the point ring
            n     (1- (length p))            ; number of chords
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
          ;; the first and last chords legitimately share a vertex
          (if (not (and (= i 0) (= j (1- n))))
            (if (cab:segs-cross a b c d) (setq found T)))
          (setq tj (cdr tj) j (1+ j)))
        (setq ti (cdr ti) i (1+ i)))
      found)))

;; ---- output helpers --------------------------------------------------
;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun cab:ensure-layer (name colour / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 colour)
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
          (princ (strcat "\nCABHD: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;; How many fitted polylines are already on the output layer (counted
;; before the new one is drawn).
(defun cab:prior-fits (/ ss)
  (setq ss (ssget "_X" (list (cons 8 *CAB-OUT-LAYER*)
                             '(0 . "LWPOLYLINE"))))
  (if ss (sslength ss) 0))

;; T when R is a whole multiple of one of the *CAB-NICE-RADII* tiers.
(defun cab:nice-radius-p (r / found tier q)
  (setq found nil)
  (if (and r (< r 1.0e6))
    (foreach tier *CAB-NICE-RADII*
      (setq q (/ r tier))
      (if (< (abs (- q (fix (+ q 0.5)))) 1.0e-6) (setq found T))))
  found)

;; verts: list of (pt bulge) in order, closed.  COL is an AutoCAD
;; colour index, or nil for BYLAYER.
(defun cab:make-pline (verts layer col / dxf v)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                  (cons 8 layer)))
  (if col (setq dxf (append dxf (list (cons 62 col)))))
  (setq dxf (append dxf (list '(100 . "AcDbPolyline")
                              (cons 90 (length verts)) '(70 . 1))))
  (foreach v verts
    (setq dxf (append dxf (list (cons 10 (car v)) (cons 42 (cadr v))))))
  (entmakex dxf))

;; The kept fit joins the POOL layer in ByLayer colour: the preview
;; colour and the preview layer both belonged to the comparison - the
;; result belongs with the pool.
(defun cab:set-bylayer (en / ed)
  (cab:ensure-layer *CAB-POOL-LAYER* 4)
  (setq ed (entget en)
        ed (subst (cons 8 *CAB-POOL-LAYER*) (assoc 8 ed) ed))
  (if (assoc 62 ed) (setq ed (subst '(62 . 256) (assoc 62 ed) ed)))
  (entmod ed))

;; Pad S with spaces to width W, for the comparison table.
(defun cab:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; The points SEGS fails to hold within TOL.
(defun cab:unheld (segs pts tol / out q s d dmin)
  (setq out nil)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (cab:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin tol) (setq out (cons q out))))
  (reverse out))

;; List membership by position, within the exact-point fuzz.
(defun cab:memb (q lst / found p)
  (setq found nil)
  (foreach p lst
    (if (< (cab:dist p q) *CAB-EXACT-EPS*) (setq found T)))
  found)

(defun cab:isect (a b / out q)
  (setq out nil)
  (foreach q a
    (if (cab:memb q b) (setq out (cons q out))))
  (reverse out))

;; ---- temporary preview geometry --------------------------------------
;; Everything CABHD draws to help you decide - the dashed straight-wall
;; markers, the three candidate outlines, their number labels - is
;; scaffolding, not a result.  Each piece is registered here as it is
;; created and swept away when the command ends, whether that is
;; normally, by ESC, or by an error, so no run leaves litter behind.
;; Whatever the user chooses to keep is dropped from the list first.

(defun cab:temp-add (en)
  (if en (setq cab-temp (cons en cab-temp)))
  en)

(defun cab:temp-drop (en / out x)
  (setq out nil)
  (foreach x cab-temp
    (if (not (eq x en)) (setq out (cons x out))))
  (setq cab-temp (reverse out))
  en)

;; entget returns nil for something already gone, so a piece erased
;; earlier is simply skipped instead of raising an error
(defun cab:temp-clear ( / en)
  (foreach en cab-temp
    (if (and en (entget en)) (entdel en)))
  (setq cab-temp nil))

;; ---- "this one is mine" stamping -------------------------------------
;; CABHD writes onto layers the drawing may already be using - FGStep in
;; particular - so it must never clear a layer wholesale.  Everything it
;; creates carries a small piece of extended data naming this command,
;; and only stamped objects are ever erased again.

(defun cab:tag-mine (en / ed)
  (if en
    (progn
      (regapp "CABHD")
      (setq ed (entget en))
      (entmod (append ed (list (list -3 (list "CABHD" (cons 1000 "CABHD"))))))))
  en)

;; Erase only CABHD's own objects on a layer; anything the user drew
;; there is left alone.  Returns how many went.
(defun cab:purge-mine (name / ss i n en)
  (setq n 0)
  (if (tblsearch "LAYER" name)
    (progn
      (setq ss (ssget "_X" (list (cons 8 name))))
      (if ss
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq en (ssname ss i))
            (if (assoc -3 (entget en '("CABHD")))
              (progn (entdel en) (setq n (1+ n))))
            (setq i (1+ i)))))))
  n)

;; Make sure the DASHED linetype exists (pure entmake, no command
;; calls).  Dash lengths are in drawing units - sized for an inch
;; drawing, so the dashes read at pool scale.
(defun cab:ensure-dashed ()
  (if (not (tblsearch "LTYPE" "DASHED"))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   '(2 . "DASHED") '(70 . 0)
                   '(3 . "Dashed __ __ __ __ __")
                   '(72 . 65) '(73 . 2) '(40 . 18.0)
                   '(49 . 12.0) '(74 . 0)
                   '(49 . -6.0) '(74 . 0)))))

;; Draw the dashed ring marking a user-declared sharp corner.
(defun cab:draw-corner-marker (p)
  (cab:ensure-dashed)
  (cab:ensure-layer *CAB-WALL-LAYER* 8)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *CAB-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 *CAB-MISS-RADIUS*))))

;; Draw the marker for a user-declared HELD point: a dashed ring at
;; half the miss-ring radius, so it reads apart from corner rings.
(defun cab:draw-hold-marker (p)
  (cab:ensure-dashed)
  (cab:ensure-layer *CAB-WALL-LAYER* 8)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *CAB-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 (* 0.5 *CAB-MISS-RADIUS*)))))

;; Draw the dashed marker for a user-declared straight wall.
(defun cab:draw-wall-marker (p1 p2)
  (cab:ensure-dashed)
  (cab:ensure-layer *CAB-WALL-LAYER* 8)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                  (cons 8 *CAB-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbLine")
                  (cons 10 (list (car p1) (cadr p1) 0.0))
                  (cons 11 (list (car p2) (cadr p2) 0.0)))))

;; Bounding box of a point list, as (minx miny maxx maxy).
(defun cab:bbox (pts / x0 y0 x1 y1 q)
  (foreach q pts
    (if (null x0)
      (setq x0 (car q) x1 (car q) y0 (cadr q) y1 (cadr q))
      (setq x0 (min x0 (car q)) x1 (max x1 (car q))
            y0 (min y0 (cadr q)) y1 (max y1 (cadr q)))))
  (list x0 y0 x1 y1))

;; Draw "1", "2", "3" beside each candidate, in that candidate's own
;; colour, with that fit's numbers spelled out to the right of it - so
;; the whole choice can be made from the drawing without reading the
;; command line at all.  The labels stack down the right-hand side of
;; the shape and are sized to the drawing, so they read at any zoom.
;; Returns the list of entities that make up the label.  The figures
;; go on two lines bracketing the number, so the label stays readable
;; instead of trailing a single very long line across the drawing.
(defun cab:label (num colour bb hgt row top bot / x y out e pr)
  (setq x   (+ (caddr bb) (* 0.6 hgt))
        y   (- (cadddr bb) (* row hgt 2.1))
        out nil)
  ;; the number itself, full height
  (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *CAB-OUT-LAYER*) (cons 62 colour)
                          '(100 . "AcDbText")
                          (cons 10 (list x y 0.0))
                          (cons 40 hgt)
                          (cons 1 num))))
  (if e (setq out (cons e out)))
  ;; its figures, smaller, on two lines to the right of the number
  (foreach pr (list (cons top (* 0.55 hgt)) (cons bot (* -0.05 hgt)))
    (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                            (cons 8 *CAB-OUT-LAYER*) (cons 62 colour)
                            '(100 . "AcDbText")
                            (cons 10 (list (+ x (* 1.4 hgt))
                                           (+ y (cdr pr))
                                           0.0))
                            (cons 40 (* 0.42 hgt))
                            (cons 1 (car pr)))))
    (if e (setq out (cons e out))))
  (reverse out))

;; Ring every point the chosen fit could not hold, on its own layer,
;; so they are easy to zoom to and judge: a mis-shot, a duplicate, or
;; a real feature the tolerance is too tight for.
;; Also writes the list of them to the side of the shape, worst first,
;; as "Pt.17   off by 1-7/8"" - so the misses can be worked through
;; without hunting for red circles.
(defun cab:mark-unheld (bad segs bb hgt / q d s dmin keyed pair th x y
                                         line)
  ;; markers from an earlier run describe a fit that no longer exists;
  ;; only CABHD's own are removed, never anything else on the layer
  (cab:purge-mine *CAB-MISS-LAYER*)
  (if bad
    (progn
      (cab:ensure-layer *CAB-MISS-LAYER* 1)
      ;; rings on the points themselves
      (foreach q bad
        (cab:tag-mine
          (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                          (cons 8 *CAB-MISS-LAYER*) '(100 . "AcDbCircle")
                          (cons 10 (list (car q) (cadr q) 0.0))
                          (cons 40 *CAB-MISS-RADIUS*)))))
      ;; how far off each one is, worst first
      (setq keyed nil)
      (foreach q bad
        (setq dmin nil)
        (foreach s segs
          (setq d (cab:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (setq keyed (cons (cons dmin q) keyed)))
      (setq keyed (reverse (cab:sort-car keyed))
            th    (* 0.5 hgt)
            x     (+ (caddr bb) (* 0.6 hgt))
            y     (cadddr bb))
      (cab:tag-mine
        (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                        (cons 8 *CAB-MISS-LAYER*) '(100 . "AcDbText")
                        (cons 10 (list x y 0.0))
                        (cons 40 th)
                        (cons 1 (strcat "POINTS OFF THE LINE ("
                                        (itoa (length bad)) ")")))))
      (foreach pair keyed
        (setq y    (- y (* th 1.6))
              line (strcat "Pt." (cab:pt-name (cdr pair))
                           "   off by " (rtos (car pair) 4 4)))
        (cab:tag-mine
          (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *CAB-MISS-LAYER*) '(100 . "AcDbText")
                          (cons 10 (list x y 0.0))
                          (cons 40 th)
                          (cons 1 line)))))))
  keyed)

;; Print the hit report for the fit the user kept.  ALLOW is the run's
;; miss allowance (how many points were permitted to sit between the
;; on-the-shape threshold and the tolerance off the result).
(defun cab:report (newsegs pts tol allow prior / nl na hiton hitok miss
                                                q s s2 d dmin worst sum
                                                sumo no nice onpt inner
                                                ns i te ts kk mk nk
                                                hw hq cab-on-eps)
  ;; report against the same on-the-shape threshold the fit used
  (setq cab-on-eps (max *CAB-ON-EPS* (* 0.25 tol)))
  (progn
      ;; -- segment mix, nice radii, arcs anchored on a point --------
      (setq nl 0 na 0 nice 0 onpt 0)
      (foreach s newsegs
        (if (< (abs (caddr s)) 1.0e-9)
          (setq nl (1+ nl))
          (progn
            (setq na (1+ na))
            (if (cab:nice-radius-p
                  (cab:bulge-radius (car s) (cadr s) (caddr s)))
              (setq nice (1+ nice)))
            ;; does this arc pass through a point other than its ends?
            (setq inner nil)
            (foreach q pts
              (if (and (> (cab:dist q (car s)) *CAB-EXACT-EPS*)
                       (> (cab:dist q (cadr s)) *CAB-EXACT-EPS*)
                       (<= (cab:seg-dist q s) (* 2.0 *CAB-FIT-EPS*)))
                (setq inner T)))
            (if inner (setq onpt (1+ onpt))))))
      ;; -- how the survey points landed ------------------------------
      (setq hiton 0 hitok 0 miss 0 worst 0.0 sum 0.0 sumo 0.0 no 0)
      (foreach q pts
        (setq dmin nil)
        (foreach s newsegs
          (setq d (cab:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (if (> dmin worst) (setq worst dmin))
        (setq sum (+ sum dmin))
        (if (> dmin (cab:oneps))
          (setq sumo (+ sumo dmin) no (1+ no)))
        (cond
          ((<= dmin (cab:oneps)) (setq hiton (1+ hiton)))
          ((<= dmin tol)        (setq hitok (1+ hitok)))
          (T                    (setq miss  (1+ miss)))))
      ;; -- smoothness: worst kink at a joint that is not a corner ----
      (setq ns (length newsegs) i 0 mk 0.0 nk 0)
      (while (< i ns)
        (setq s  (nth i newsegs)
              s2 (nth (rem (1+ i) ns) newsegs)
              te (+ (angle (car s) (cadr s)) (* 2.0 (atan (caddr s))))
              ts (- (angle (car s2) (cadr s2)) (* 2.0 (atan (caddr s2))))
              kk (abs (cab:signed-dang te ts)))
        (if (<= kk *CAB-CORNER-ANG*)     ; bigger = an intentional corner
          (progn
            (if (> kk mk) (setq mk kk))
            (if (> kk (+ *CAB-TANG-TOL* 1.0e-6)) (setq nk (1+ nk)))))
        (setq i (1+ i)))
      (princ (strcat "\nCABHD: " (itoa ns) " segments ("
                     (itoa nl) " lines + " (itoa na)
                     " curves) written to layer " *CAB-POOL-LAYER* "."
                     "\n  Points on the perimeter:      " (itoa hiton)
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
                     (rtos (* 180.0 (/ *CAB-TANG-TOL* pi)) 2 1) ")"))
      (if (> nk 0)
        (princ (strcat "\n  (" (itoa nk)
                       " joint(s) needed more than the tangent limit to"
                       " close the loop)")))
      (if cab-walls
        (princ (strcat "\n  (" (itoa (length cab-walls))
                       " declared straight wall(s) kept dead straight)")))
      (if cab-holds
        (progn
          ;; every held point must sit ON the kept fit exactly; one
          ;; that does not means the drawn shape or a declared wall
          ;; overruled it, and that deserves a loud line of its own
          (setq hw 0.0)
          (foreach q cab-holds
            (setq dmin nil)
            (foreach s newsegs
              (setq d (cab:seg-dist q s))
              (if (or (null dmin) (< d dmin)) (setq dmin d)))
            (if (> dmin hw) (setq hw dmin hq q)))
          (if (<= hw *CAB-EXACT-EPS*)
            (princ (strcat "\n  (" (itoa (length cab-holds))
                           " held point(s) all landed on the line"
                           " exactly)"))
            (princ (strcat "\n  WARNING: held Pt." (cab:pt-name hq)
                           " is off by " (rtos hw 2 4)
                           " - the drawn shape or a declared wall"
                           " overruled it.")))))
      (if (and *CAB-MAX-ARCS* (> na *CAB-MAX-ARCS*))
        (princ (strcat "\n  (the curve cap is " (itoa *CAB-MAX-ARCS*)
                       " but " (itoa na) " curves was the fewest"
                       " reachable: a closed loop needs at least 2"
                       " segments)")))
      (if (> miss 0)
        (princ (strcat "\n  (points beyond tolerance: given up to keep"
                       " the shape, or overruled by the curve cap"
                       " and/or the drawn shape)")))
      (if (cab:self-crosses newsegs)
        (princ (strcat "\n  WARNING: the result crosses itself - the"
                       " automatic point order is probably wrong."
                       "  Draw a rough lines-only loop on layer "
                       *CAB-POOL-LAYER*
                       " through the points in the right order and"
                       " select it too.")))
      (if (> prior 0)
        (princ (strcat "\n  (" (itoa prior)
                       " earlier fit(s) were already on layer "
                       *CAB-OUT-LAYER* " - erase them if you only want"
                       " the new one)"))))
  (princ))

;; ---- guided mode ------------------------------------------------------
;; Re-fit the drawn perimeter LOOP through the survey points: every
;; vertex snaps to the nearest point within TOL, every drawn arc is
;; re-fitted through the points lying along it, and drawn straight
;; walls stay straight.  TOL and FTOL are two different jobs one number
;; used to do: TOL is the reach - which point belongs to which vertex
;; and which drawn arc - and is always the distance the user typed, so
;; every candidate reads the drawn shape the same way; FTOL is how
;; exactly the re-fit then has to hold those points, and is what a
;; candidate varies.  If the result needs more curves than MAXARCS, the
;; fit falls back to the points-driven builder - the drawn loop still
;; supplies the point order.
(defun cab:guided-fit (loop pts dpts tol ftol allow drop maxarcs
                      / verts used n s p1 p2 b cands clean ns newsegs
                        q d)
  ;; -- 1. snap each vertex to its nearest point within tol ----------
  (setq verts (mapcar '(lambda (s) (car s)) loop)
        used  nil)
  (setq verts
    (mapcar
      '(lambda (v / best bd)
         (setq best nil bd tol)
         (foreach q pts
           (setq d (cab:dist v q))
           (if (and (<= d bd) (not (member q used)))
             (setq best q bd d)))
         (if best (progn (setq used (cons best used)) best) v))
      verts))
  ;; -- 2. re-fit every arc segment through the points near it -------
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
        ;; survey points lying near the ORIGINAL arc, excluding the
        ;; ones already consumed as vertices, sorted along the arc and
        ;; de-duplicated
        (setq cands nil)
        (foreach q pts
          (if (and (not (member q used))
                   (<= (cab:seg-dist q s) tol)
                   (> (cab:dist q p1) *CAB-EXACT-EPS*)
                   (> (cab:dist q p2) *CAB-EXACT-EPS*))
            (setq cands (cons (cons (cab:seg-param q s) q) cands))))
        (setq cands (mapcar 'cdr (cab:sort-car cands)))
        (setq clean nil)
        (foreach q cands
          (if (or (null clean)
                  (> (cab:dist q (car clean)) *CAB-EXACT-EPS*))
            (setq clean (cons q clean))))
        (foreach ns (cab:fit-arc-seg p1 p2 b (reverse clean) ftol)
          (setq newsegs (cons ns newsegs)))))
    (setq n (1+ n)))
  (setq newsegs (reverse newsegs))
  ;; -- 3. the drawn shape is trusted, but the curve cap still wins --
  (if (and maxarcs
           (> (cab:arc-count newsegs) maxarcs)
           (>= (length dpts) 3))
    (progn
      (princ (strcat "\n  (the drawn perimeter needs "
                     (itoa (cab:arc-count newsegs))
                     " curves but the cap is " (itoa maxarcs)
                     " - refitting from the points instead)"))
      (setq cab-miss-left allow
            newsegs (cab:coarse-loop (cab:loop-order loop dpts)
                                    ftol maxarcs allow drop T))))
  newsegs)

;; Build one candidate fit in MODE - "tight", "asked" or "few", the
;; three aims listed against *CAB-COMPARE*.  A non-nil TOUR means the
;; points drive the shape (points-only and ordering-sketch modes);
;; otherwise the drawn LOOP is re-fitted (guided mode).  TOL is always
;; the distance the user typed - it is what reads the drawn shape and
;; what the table judges every candidate against - and the mode sets
;; the three knobs that actually differ:
;;
;;   FTOL  how exactly the arcs must hold their points.  "tight" fits
;;         to *CAB-TIGHT-TOL* (or to TOL when that is tighter yet),
;;         which is what drives its error towards nothing and its
;;         curve count up; the other two fit to TOL.
;;   LEFT  the miss allowance.  "tight" grants none, so no point is
;;         written off; "few" lifts it (and the per-span fair share
;;         with it), which is the whole trick - the arcs run as long
;;         as TOL permits instead of stopping at the standard share,
;;         and every point is still held to TOL by the span fitter.
;;   CAP   the curve cap.  Only "asked" honours it: capping the other
;;         two would be asking for the most curves, or the fewest,
;;         and then overruling the answer.
;;
;; Each call gets its own miss allowance and on-the-shape threshold.
(defun cab:build (tour loop pts dpts tol allow mode
                 / cab-miss-left cab-on-eps ftol left cap drop)
  (setq ftol (if (= mode "tight") (min tol *CAB-TIGHT-TOL*) tol)
        left (cond ((= mode "tight") 0)
                   ((= mode "few")   1000000)
                   (T                allow))
        cap  (if (= mode "asked") *CAB-MAX-ARCS*)
        drop (if (= mode "tight")
               0
               (cab:ceil (* *CAB-DROP-PCT*
                           (length (if tour tour pts)))))
        cab-miss-left left
        cab-on-eps    (max *CAB-ON-EPS* (* 0.25 ftol)))
  (if tour
    (cab:coarse-loop tour ftol cap left drop (not (= mode "few")))
    (cab:guided-fit loop pts dpts tol ftol left drop cap)))

;; Deviation summary for SEGS against PTS: (worst avg avg-off).
;;   worst   - furthest any point sits from the line
;;   avg     - mean over ALL points, so it counts the ones sitting on
;;             the line as the zeros they are
;;   avg-off - mean over only the points that are actually OFF the
;;             line (further than ON from it), which says how far the
;;             strays really stray; nil when nothing is off
(defun cab:devstats (segs pts on / w q s d dmin sum n sumo no)
  (setq w 0.0 sum 0.0 n 0 sumo 0.0 no 0)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (cab:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    ;; dmin stays nil when there are no segments to measure against;
    ;; the returns below already report "nothing measured" correctly,
    ;; so the accumulators must simply not run
    (if dmin
      (progn
        (if (> dmin w) (setq w dmin))
        (setq sum (+ sum dmin) n (1+ n))
        (if (> dmin on) (setq sumo (+ sumo dmin) no (1+ no))))))
  (list w
        (if (> n 0) (/ sum n) 0.0)
        (if (> no 0) (/ sumo no) nil)))

;; A deviation for a table cell; "-" when there is nothing to average.
(defun cab:fmt-dev (x)
  (if x (rtos x 2 2) "-"))

;; ---- offer three fits and let the user pick ---------------------------
;; Knowing up front how much curve to spend on how much accuracy is the
;; hardest part of the command, so instead of asking the user to
;; imagine it, draw the two ends of that trade and the middle: the
;; most curves for the least error, the settings as typed, and the
;; fewest curves that still hold the distance.  Each goes on in its own
;; colour with what it costs, and the one they point at is kept.
;; Everything is judged against the tolerance the user actually typed,
;; so the columns compare like for like even though the three were not
;; built alike.

;; The candidates that actually reached the screen.  A fit can come out
;; too degenerate for AutoCAD to accept - fewer than two segments is no
;; closed outline - and the tight one is the likeliest to, since it must
;; thread every point at *CAB-TIGHT-TOL*.  Losing it is no reason to
;; throw away the two that drew, so this is what the chooser works from
;; and only an empty list is a dead end.
(defun cab:drawn (vars / out v)
  (foreach v vars (if (cadr v) (setq out (cons v out))))
  (reverse out))

(defun cab:compare (tour loop pts dpts tol allow
                   / prior vars v e ent lab st onv segs bad allbad first
                     i pick idx keep ce bb hgt sel picked keyed pr res
                     dflt)
  (setq prior (cab:prior-fits))
  (cab:ensure-layer *CAB-OUT-LAYER* 3)
  ;; every candidate is judged against the distance the user typed, so
  ;; "off the line" means the same thing in all three rows
  (setq onv (max *CAB-ON-EPS* (* 0.25 tol)))
  ;; label height: a twentieth of the shape, so it reads at any zoom
  (setq bb  (cab:bbox pts)
        hgt (/ (max (- (caddr bb) (car bb))
                    (- (cadddr bb) (cadr bb)))
               20.0))
  (if (<= hgt 0.0) (setq hgt 1.0))
  (setq cab-phase "building the three candidate fits"
        vars     nil
        allbad   nil
        first    T
        i        1)
  (foreach v *CAB-COMPARE*
    (setq segs (cab:build tour loop pts dpts tol allow (car v))
          ent  (cab:temp-add
                 (cab:make-pline
                   (mapcar '(lambda (s) (list (car s) (caddr s))) segs)
                   *CAB-OUT-LAYER* (cadr v)))
          bad  (cab:unheld segs pts tol)
          st   (cab:devstats segs pts onv)
          ;; the same figures the table prints, spelled out so they
          ;; stand on their own beside the number in the drawing
          lab  (cab:label
                 (itoa i) (cadr v) bb hgt i
                 (strcat (itoa (length segs)) " segs    "
                         (itoa (cab:arc-count segs)) " curves    "
                         (itoa (length bad)) " not held    "
                         (cadddr v))
                 (strcat "worst " (cab:fmt-dev (car st))
                         "    avg all " (cab:fmt-dev (cadr st))
                         "    avg off " (cab:fmt-dev (caddr st))))
          vars (cons (list segs ent bad v lab st) vars)
          i    (1+ i))
    (foreach e lab (cab:temp-add e))
    ;; the note below is about points NO fit could hold, so only the
    ;; fits actually built to the user's distance get a vote.  The
    ;; tight one threads every point by construction - counting it
    ;; would empty the intersection every time and quietly retire the
    ;; warning that catches mis-shots
    (if (not (= (car v) "tight"))
      (if first
        (setq allbad bad first nil)
        (setq allbad (cab:isect allbad bad)))))
  (setq vars (reverse vars))
  (if (null (cab:drawn vars))
    (progn
      (princ (strcat "\nCABHD: none of the " (itoa (length vars))
                     " candidate fits would draw ("
                     (itoa (length (car (car vars))))
                     " segment(s) in the first)."))
      (princ "\n  A closed outline needs at least two segments, so this is")
      (princ "\n  nearly always the points rather than the drawing: too few")
      (princ "\n  left after the cutoff, or points that all sit on one line.")
      (princ (strcat "\n  Check the cutoff (All puts every point back), and"
                     " that layer\n  " *CAB-OUT-LAYER*
                     " is not locked or read-only.")))
    (progn
      (princ (strcat "\n\n" (itoa (length (cab:drawn vars)))
                     " candidate fit(s) are now drawn on layer "
                     *CAB-OUT-LAYER*
                     ",\neach numbered on screen in its own colour:\n"))
      (princ "\n   #  segs  curves  worst off  avg all  avg off  not held  ")
      (princ "\n   -  ----  ------  ---------  -------  -------  --------  ")
      (setq i 1)
      (foreach v vars
        (setq segs (car v) bad (caddr v) ce (cadddr v) st (nth 5 v))
        (princ (strcat "\n   " (itoa i) "  "
                       (cab:pad (itoa (length segs)) 6)
                       (cab:pad (itoa (cab:arc-count segs)) 8)
                       (cab:pad (cab:fmt-dev (car st)) 11)
                       (cab:pad (cab:fmt-dev (cadr st)) 9)
                       (cab:pad (cab:fmt-dev (caddr st)) 9)
                       (cab:pad (itoa (length bad)) 10)
                       (cadddr ce)
                       (if (cadr v) "" "   -- would not draw")))
        (setq i (1+ i)))
      (princ (strcat "\n\n  \"not held\" = points further than "
                     (rtos tol 2 3) " from that fit - some of them"
                     " given up on purpose,"
                     "\n  to keep the shape whole where holding them"
                     " would break it into stubs."
                     "\n  \"avg all\" averages every point; \"avg off\""
                     " averages only the points that are off the line"
                     "\n  (further than " (rtos onv 2 3) " from it)."))
      (princ (strcat "\n  All three are measured against the "
                     (rtos tol 2 3) " you typed, but only one is built"
                     " to it:"
                     "\n  the tight fit spends curves to drive the error"
                     " towards nothing (it"
                     "\n  ignores that distance"
                     (if *CAB-MAX-ARCS* " and the curve cap" "")
                     " and gives up no point at all), the middle one is"
                     "\n  your settings exactly, and the few fit holds"
                     " the same distance with as few"
                     "\n  curves as it can - those two may write off up"
                     " to " (itoa (cab:ceil (* *CAB-DROP-PCT*
                                              (length (if tour
                                                        tour
                                                        pts)))))
                     " stray point(s) between them."))
      (if allbad
        (princ (strcat "\n  NOTE: " (itoa (length allbad))
                       " point(s) could not be held by ANY fit built to"
                       " that distance - likely a mis-shot, a duplicate,"
                       " or a corner that needs more points around it."
                       "\n  (the tight fit threads every point it can"
                       " reach, so it does not get a vote here.)")))
      ;; -- let the user choose ---------------------------------------
      ;; Clicking the outline you want beats translating a colour into
      ;; a number, so a pick on screen is offered first; typing the
      ;; number still works for anyone who prefers the keyboard.
      (setq cab-phase "waiting for the choice of fit")
      ;; Enter has to produce something that is actually on screen.  The
      ;; middle fit - the settings as typed - stays the default exactly
      ;; as long as it drew; only when it did not does the default move
      ;; to the first one that did.
      (setq dflt (if (and (nth 1 vars) (cadr (nth 1 vars)))
                   "2"
                   (itoa (1+ (- (length vars)
                                (length (member (car (cab:drawn vars))
                                                vars)))))))
      (princ "\n\n  Click the outline you want to keep, or type its number.")
      (princ "\n  Redo refits with new settings, and lets you omit points first.")
      (initget "1 2 3 All None Redo")
      (setq pick (getkword
                   (strcat "\n  Keep which fit - click one, or"
                           " [1/2/3/All/None/Redo] <" dflt ">: ")))
      (if (null pick)
        ;; no keyword typed: give them a click, and fall back to the
        ;; default above
        (progn
          (setq sel (entsel (strcat "\n  Pick the outline to keep (or Enter for "
                                    dflt "): ")))
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
                  (princ (strcat "\n  (that is not one of the three - keeping "
                                 dflt ")"))
                  (setq pick dflt))))
            (setq pick dflt))))
      ;; anything not explicitly kept stays registered as scaffolding
      ;; and is swept when the command ends
      (cond
        ((= pick "Redo")
         ;; clear this trio off the screen right away - the caller
         ;; asks its questions and draws a fresh one
         (foreach v vars
           (if (and (cadr v) (entget (cadr v))) (entdel (cadr v)))
           (foreach e (nth 4 v)
             (if (and e (entget e)) (entdel e))))
         (setq res 'REDO))
        ((= pick "All")
         (foreach v (cab:drawn vars)
           (cab:temp-drop (cadr v))
           (foreach e (nth 4 v) (cab:temp-drop e)))
         (princ (strcat "\nKeeping all "
                        (itoa (length (cab:drawn vars)))
                        " that drew, in their preview colours."))
         (princ "\n  (the number labels are kept too - erase them when done)"))
        ((= pick "None")
         (princ "\nAll three erased - nothing was added to the drawing."))
        (T
         (setq idx (atoi pick) i 1)
         (foreach v vars
           (if (= i idx)
             (setq keep v)
             ;; erase the losers now, so the keeper is clear on screen
             ;; while the report is read
             (if (and (cadr v) (entget (cadr v))) (entdel (cadr v))))
           (setq i (1+ i)))
         ;; name the aim that was kept, not just its number - the three
         ;; were built to different ends and the report that follows is
         ;; read against the settings as typed
         (if (and keep (null (cadr keep)))
           (progn
             (princ (strcat "\n  Fit " pick
                            " never drew - there is nothing to keep."))
             (princ "\n  Pick one the table shows on screen.")
             (setq keep nil)))
         (if keep
           (progn
             (princ (strcat "\n  Keeping fit " pick " - "
                            (cadddr (cadddr keep)) "."))
             (cab:temp-drop (cadr keep))
             (cab:set-bylayer (cadr keep))))))
      (if keep
        (progn
          (setq keyed (cab:mark-unheld (caddr keep) (car keep) bb hgt))
          (cab:report (car keep) pts tol allow prior)
          (if keyed
            (progn
              (princ (strcat "\n  " (itoa (length keyed))
                             " point(s) beyond the distance are ringed"
                             " on layer " *CAB-MISS-LAYER*
                             " and listed beside the pool, worst first:"))
              (foreach pr keyed
                (princ (strcat "\n    Pt." (cab:pt-name (cdr pr))
                               "   off by " (rtos (car pr) 4 4))))))))))
  (princ)
  res)

;; Snap a picked point onto the nearest survey point, warning when the
;; pick was nowhere near one (the rule declared walls are held to, used
;; again wherever a Redo re-picks a wall, a corner or a hold).
(defun cab:snap-pick (p dpts / q)
  (setq p (cab:2d p)
        q (cab:nearest p dpts))
  (if (null q)
    p
    (progn
      (if (> (cab:dist p q) (* 3.0 *CAB-TOL*))
        (princ "\n  (picked well away from any survey point - snapped to the nearest one)"))
      q)))

;; ---- the numeric parameters ------------------------------------------
;; Asked identically at the start of a run and again on a Redo -
;; Enter keeps the shown value each time.

;; Maximum distance from a point; remembered in *CAB-TOL*.
(defun cab:ask-tol (/ tol)
  (initget 6)
  (setq tol (getdist (strcat "\n  Maximum distance from a point <"
                             (rtos *CAB-TOL* 2 3) ">: ")))
  (if (null tol) (setq tol *CAB-TOL*))
  (if (> tol *CAB-TOL-MAX*)
    (progn
      (princ (strcat "\n  (more than " (rtos *CAB-TOL-MAX* 2 1)
                     " and the line is no longer a trace of the points"
                     " - using " (rtos *CAB-TOL-MAX* 2 1) ")"))
      (setq tol *CAB-TOL-MAX*)))
  (setq *CAB-TOL* tol)
  tol)

;; Share of the points allowed off the line, returned as a fraction;
;; DEF is the fraction Enter keeps.
(defun cab:ask-pct (def / pct)
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

;; Curve cap; remembered in *CAB-MAX-ARCS* (nil = no cap).
(defun cab:ask-cap (/ mx)
  (initget 4 "None")
  (setq mx (getint (strcat "\n  Maximum curves <"
                           (if *CAB-MAX-ARCS* (itoa *CAB-MAX-ARCS*) "None")
                           ">: ")))
  (cond ((null mx) nil)                            ; Enter: keep as-is
        ((eq 'STR (type mx)) (setq *CAB-MAX-ARCS* nil))
        (T (setq *CAB-MAX-ARCS* mx)))
  *CAB-MAX-ARCS*)

;; ---- redo-time editing of walls and corners --------------------------
;; A Redo may change more than the numbers: straight walls and sharp
;; corners can be added or removed before the refit.  Both editors
;; work on the run-scoped cab-walls / cab-corners lists and keep the
;; dashed markers in step with them.

;; Erase this run's scaffolding markers of one entity type on the
;; marker layer (walls are the LINEs, rings the CIRCLEs), so the set
;; can be redrawn to match an edited declaration list.
(defun cab:sweep-marks (etype / keep en ed)
  (setq keep nil)
  (foreach en cab-temp
    (setq ed (if (and en (entget en)) (entget en)))
    (if (and ed
             (= etype (cdr (assoc 0 ed)))
             (= (strcase *CAB-WALL-LAYER*)
                (strcase (cdr (assoc 8 ed)))))
      (entdel en)
      (setq keep (cons en keep))))
  (setq cab-temp (reverse keep)))

;; Add or remove declared straight walls.  Ends snap to the survey
;; points; each change is confirmed by name and the dashed markers
;; follow.
(defun cab:edit-walls (dpts / ans wp1 wp2 w1 w2 best bd w d)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Straight walls (" (itoa (length cab-walls))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq cab-phase "picking a straight wall"
             wp1      (getpoint "\n  First end of the straight wall: ")
             wp2      (if wp1 (getpoint wp1 "\n  Second end: ")))
       (if wp2
         (progn
           (setq w1 (cab:snap-pick wp1 dpts)
                 w2 (cab:snap-pick wp2 dpts))
           (if (< (cab:dist w1 w2) *CAB-EXACT-EPS*)
             (princ "\n  (both ends landed on the same survey point - ignored)")
             (progn
               (setq cab-walls (append cab-walls (list (list w1 w2))))
               (cab:temp-add (cab:tag-mine (cab:draw-wall-marker w1 w2)))
               (princ (strcat "\n  wall Pt." (cab:pt-name w1)
                              " - Pt." (cab:pt-name w2) " added")))))))
      ((= ans "Remove")
       (if (null cab-walls)
         (princ "\n  (no straight walls to remove)")
         (progn
           (setq cab-phase "removing a straight wall"
                 wp1      (getpoint "\n  Pick near the straight wall to remove: "))
           (if wp1
             (progn
               (setq wp1 (cab:2d wp1) best nil bd nil)
               (foreach w cab-walls
                 (setq d (cab:seg-dist wp1 (list (car w) (cadr w) 0.0)))
                 (if (or (null bd) (< d bd)) (setq best w bd d)))
               (setq cab-walls (cab:remove best cab-walls))
               ;; redraw the wall markers to match what is left
               (cab:sweep-marks "LINE")
               (foreach w cab-walls
                 (cab:temp-add (cab:tag-mine
                   (cab:draw-wall-marker (car w) (cadr w)))))
               (princ (strcat "\n  wall Pt." (cab:pt-name (car best))
                              " - Pt." (cab:pt-name (cadr best))
                              " removed")))))))
      (T (setq ans nil)))))

;; Add or remove declared sharp corners the same way.  (The corners
;; the fitter finds by itself - turns over *CAB-CORNER-ANG* - are not
;; declarations and cannot be removed here.)
(defun cab:edit-corners (dpts / ans wp1 w1 best bd w)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Sharp corners (" (itoa (length cab-corners))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq cab-phase "picking a sharp corner"
             wp1      (getpoint "\n  Corner point: "))
       (if wp1
         (progn
           (setq w1 (cab:snap-pick wp1 dpts))
           (if (cab:memb w1 cab-corners)
             (princ "\n  (that corner is already declared)")
             (progn
               (setq cab-corners (append cab-corners (list w1)))
               (cab:temp-add (cab:tag-mine (cab:draw-corner-marker w1)))
               (princ (strcat "\n  corner Pt." (cab:pt-name w1)
                              " added")))))))
      ((= ans "Remove")
       (if (null cab-corners)
         (princ "\n  (no declared corners to remove)")
         (progn
           (setq cab-phase "removing a sharp corner"
                 wp1      (getpoint "\n  Pick the declared corner to remove: "))
           (if wp1
             (progn
               (setq wp1 (cab:2d wp1) best nil bd nil)
               (foreach w cab-corners
                 (if (or (null bd) (< (cab:dist wp1 w) bd))
                   (setq best w bd (cab:dist wp1 w))))
               (setq cab-corners (cab:remove best cab-corners))
               ;; the rings share their look with the omit markers;
               ;; redraw the corner and hold rings (spent omit rings
               ;; go quietly - the omissions already happened)
               (cab:sweep-marks "CIRCLE")
               (foreach w cab-corners
                 (cab:temp-add (cab:tag-mine (cab:draw-corner-marker w))))
               (foreach w cab-holds
                 (cab:temp-add (cab:tag-mine (cab:draw-hold-marker w))))
               (princ (strcat "\n  corner Pt." (cab:pt-name best)
                              " removed")))))))
      (T (setq ans nil)))))

;; Add or remove HELD points the same way.
(defun cab:edit-holds (dpts / ans wp1 w1 best bd w)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Held points (" (itoa (length cab-holds))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq cab-phase "picking a held point"
             wp1      (getpoint "\n  Point to hold exactly: "))
       (if wp1
         (progn
           (setq w1 (cab:snap-pick wp1 dpts))
           (if (cab:memb w1 cab-holds)
             (princ "\n  (that point is already held)")
             (progn
               (setq cab-holds (append cab-holds (list w1)))
               (cab:temp-add (cab:tag-mine (cab:draw-hold-marker w1)))
               (princ (strcat "\n  held Pt." (cab:pt-name w1)
                              " added")))))))
      ((= ans "Remove")
       (if (null cab-holds)
         (princ "\n  (no held points to remove)")
         (progn
           (setq cab-phase "removing a held point"
                 wp1      (getpoint "\n  Pick the held point to release: "))
           (if wp1
             (progn
               (setq wp1 (cab:2d wp1) best nil bd nil)
               (foreach w cab-holds
                 (if (or (null bd) (< (cab:dist wp1 w) bd))
                   (setq best w bd (cab:dist wp1 w))))
               (setq cab-holds (cab:remove best cab-holds))
               ;; redraw the rings to match what is left
               (cab:sweep-marks "CIRCLE")
               (foreach w cab-corners
                 (cab:temp-add (cab:tag-mine (cab:draw-corner-marker w))))
               (foreach w cab-holds
                 (cab:temp-add (cab:tag-mine (cab:draw-hold-marker w))))
               (princ (strcat "\n  held Pt." (cab:pt-name best)
                              " released")))))))
      (T (setq ans nil)))))

;; Which build is loaded - the first thing to check when a run does
;; something the notes above say it should not.
(defun c:CABHDVER ()
  (princ (strcat "\nCABHD " *cabhd-version*))
  (princ))

;; ---- CABHD: the perimeter, and nothing but ---------------------------
(defun c:CABHD ( / tol ans go wp1 wp2 rawwalls rawcnrs rawholds w w1 w2
                    ss i en ed lay typ ext nunsup nocs dall cut0 ent
                    segs pts dpts allow loop tour ok stale npt
                    again ring cab-cut cab-allpts cab-ptkeys cab-numbered
                    cab-omitted cab-miss-pct cab-walls cab-corners
                    cab-holds cab-temp cab-ptnames
                    *error* cab-old-err cab-phase undo-open cab-pick)
  ;; report which step failed if anything goes wrong, sweep away any
  ;; preview geometry drawn so far, then restore the old handler - a
  ;; cancelled run must not leave dashed markers or candidate outlines
  ;; lying around
  (setq cab-temp    nil
        cab-numbered 0
        cab-old-err *error*
        *error*
          (lambda (m)
            ;; ALWAYS say where it stopped, cancels included: a
            ;; command that vanishes without a word is the one thing
            ;; nobody can debug from the other end of a phone
            (princ (strcat "\nCABHD stopped while "
                           (if cab-phase cab-phase "starting up")
                           (if (and m (not (wcmatch (strcase m)
                                    "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
                             (strcat " -- " m)
                             " (cancelled).")))
            (cab:temp-clear)
            ;; close the group after the sweep so one U takes back the
            ;; whole run, previews included; only if it ever opened
            (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
            (setq undo-open nil)
            (setq *error* cab-old-err)
            (princ)))

  ;; sweep leftovers from a run that was interrupted before it could
  ;; tidy up after itself
  (setq stale (cab:purge-mine *CAB-WALL-LAYER*))
  (if (> stale 0)
    (princ (strcat "\nCABHD: cleared " (itoa stale)
                   " leftover marker(s) from layer " *CAB-WALL-LAYER*
                   ".")))

  ;; a pickfirst selection if there is one - kept for step 7, probed
  ;; before the undo group opens, which would clear the set
  (setq cab-pick (ssget "_I" '((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE"))))

  ;; one undo group around the whole fit - a U after CABHD takes back
  ;; the edge, the markers and the previews in one step (the stale
  ;; purge above stays outside it, so U does not resurrect old junk)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)

  (princ "\n\nCABHD - fit a pool perimeter through the surveyed points,")
  (princ "\n        up to the point number where the edge stops.")

  ;; -- step 1: how close must the line stay to the points? ----------
  ;; This is the one prompt people misread, so it says in plain words
  ;; what the number means and which way it moves the result.
  ;; initget 6 refuses zero and negative values - a zero tolerance
  ;; would silently collapse the fit into single-point stubs.
  (setq cab-phase "reading the tolerance")
  (princ "\n\n  Step 1 of 8 - how far may the fitted line sit from a survey point?")
  (princ "\n  Type a distance in drawing units (1 = one inch, 2 at most), or")
  (princ "\n  pick two points in the drawing to measure one.")
  (princ "\n  Smaller = hugs the points.  Bigger = smoother, with fewer curves.")
  (setq tol (cab:ask-tol))

  ;; -- step 2: how many of the points may sit off the line? ---------
  ;; Enter means the standard share; the answer is per run, on purpose.
  (setq cab-phase "reading the miss percentage")
  (princ "\n\n  Step 2 of 8 - what percent of the points may sit OFF the line")
  (princ "\n  (off, but still within the distance above)?")
  (princ (strcat "\n  Press Enter for the standard "
                 (itoa (fix (+ 0.5 (* 100.0 *CAB-MISS-PCT*))))
                 " percent."))
  (setq cab-miss-pct (cab:ask-pct *CAB-MISS-PCT*))

  ;; -- step 3: optional cap on how many curves the result may use ---
  (setq cab-phase "reading the curve limit")
  (princ "\n\n  Step 3 of 8 - limit how many curves the result may use?")
  (princ "\n  Type a whole number, or None for no limit.")
  (cab:ask-cap)

  ;; -- step 4: any dead-straight walls to declare? ------------------
  ;; Each declared wall is marked with a dashed line right away and
  ;; comes out of the fit as a straight LINE between those two survey
  ;; points, no matter what the arcs around it are doing.
  (setq cab-phase "asking about straight lines")
  (princ "\n\n  Step 4 of 8 - does the pool edge have any dead-straight walls?")
  (princ "\n  If Yes you will pick the two end points of each (snap to the")
  (princ "\n  survey points); a dashed line marks each declared wall.")
  (princ "\n  Pick them among the points that trace the EDGE - a wall anchored")
  (princ "\n  past the cutoff asked at step 8 is dropped with the points it used.")
  (initget "Yes No")
  (setq ans      (getkword "\n  Any straight lines? [Yes/No] <No>: ")
        rawwalls nil)
  (if (= ans "Yes")
    (progn
      (setq go T)
      (while go
        (setq cab-phase "picking a straight wall"
              wp1       (getpoint "\n  First end of the straight wall: "))
        (if wp1
          (progn
            (setq wp2 (getpoint wp1 "\n  Second end: "))
            (if wp2
              (progn
                (setq wp1 (cab:2d wp1) wp2 (cab:2d wp2))
                ;; the dashed marker is scaffolding: it confirms what
                ;; you declared, and goes when the command ends
                (cab:temp-add (cab:tag-mine (cab:draw-wall-marker wp1 wp2)))
                (setq rawwalls (cons (list wp1 wp2) rawwalls))
                (initget "Yes No")
                (if (/= (getkword "\n  Another straight line? [Yes/No] <No>: ")
                        "Yes")
                  (setq go nil)))
              (setq go nil)))
          (setq go nil)))
      (setq rawwalls (reverse rawwalls))
      (if rawwalls
        (princ (strcat "\n  " (itoa (length rawwalls))
                       " straight wall(s) noted - the dashed markers on "
                       *CAB-WALL-LAYER*
                       " clear themselves when the command finishes.")))))

  ;; -- step 5: any sharp corners to declare? ------------------------
  ;; The fitter finds obvious corners itself (turns over
  ;; *CAB-CORNER-ANG*), but a gentler one still reads as a corner on
  ;; site.  A declared point is exempt from the tangency rule: the fit
  ;; breaks there instead of rounding it off.
  (setq cab-phase "asking about sharp corners")
  (princ "\n\n  Step 5 of 8 - are there any sharp corners the fit must not round off?")
  (princ "\n  Obvious ones are found automatically; declare the gentler ones here.")
  (princ "\n  If Yes you will pick each corner point (snap to the survey points).")
  (initget "Yes No")
  (setq ans     (getkword "\n  Any sharp corners? [Yes/No] <No>: ")
        rawcnrs nil)
  (if (= ans "Yes")
    (progn
      (setq go T)
      (while go
        (setq cab-phase "picking a sharp corner"
              wp1       (getpoint "\n  Corner point (Enter when done): "))
        (if wp1
          (progn
            (setq wp1     (cab:2d wp1)
                  rawcnrs (cons wp1 rawcnrs))
            (cab:temp-add (cab:tag-mine (cab:draw-corner-marker wp1))))
          (setq go nil)))
      (setq rawcnrs (reverse rawcnrs))
      (if rawcnrs
        (princ (strcat "\n  " (itoa (length rawcnrs))
                       " corner(s) noted - the markers clear themselves"
                       " when the command finishes.")))))

  ;; -- step 6: any points that must be held absolutely? -------------
  ;; Control shots and tie-ins are surveyed as exact positions: a held
  ;; point always ends a span, so the fit passes through it exactly
  ;; and the miss allowance can never write it off.
  (setq cab-phase "asking about held points")
  (princ "\n\n  Step 6 of 8 - any points that must be held ABSOLUTELY?")
  (princ "\n  A held point can never be fudged: the line passes through it")
  (princ "\n  exactly, in every candidate.  If Yes you will pick each one")
  (princ "\n  (snap to the survey points); a small dashed ring marks it.")
  (initget "Yes No")
  (setq ans      (getkword "\n  Any held points? [Yes/No] <No>: ")
        rawholds nil)
  (if (= ans "Yes")
    (progn
      (setq go T)
      (while go
        (setq cab-phase "picking a held point"
              wp1       (getpoint "\n  Point to hold exactly (Enter when done): "))
        (if wp1
          (progn
            (setq wp1      (cab:2d wp1)
                  rawholds (cons wp1 rawholds))
            (cab:temp-add (cab:tag-mine (cab:draw-hold-marker wp1))))
          (setq go nil)))
      (setq rawholds (reverse rawholds))
      (if rawholds
        (princ (strcat "\n  " (itoa (length rawholds))
                       " held point(s) noted - the markers clear"
                       " themselves when the command finishes.")))))

  ;; -- step 7: the selection ----------------------------------------
  ;; Select the WHOLE survey - the cutoff at step 8 is what decides how
  ;; much of it the perimeter uses, and it can be moved at a Redo, so
  ;; there is nothing to gain by window-selecting carefully here.
  ;; only entity types this command can actually read, so a sloppy
  ;; crossing window over dimensions, hatches or text is harmless.
  ;; SPLINE and ELLIPSE are let in ON PURPOSE - not to fit them, but
  ;; so the classifier below can name them in a useful message.
  (setq cab-phase "waiting for the selection")
  (if cab-pick
    (setq ss cab-pick)
    (progn
      (princ "\n\n  Step 7 of 8 - select the survey points (POINTS layer or ab_pt")
      (princ "\n  blocks) and, if you have one, the POOL perimeter or ordering sketch.")
      (princ "\n  Take the whole survey - step 8 says how much of it is the pool.")
      (princ "\n  Select objects: ")
      (setq ss (ssget '((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE"))))))
  (if (null ss)
    (princ "\nNothing usable selected (points, and optionally POOL lines/arcs/polylines).")
    (progn
      ;; -- sort the selection into perimeter segments and points -----
      (setq cab-phase "reading the selected entities")
      (setq segs nil pts nil i 0 nunsup 0 nocs 0
            npt 0 cab-ptnames nil cab-ptkeys nil cab-allpts nil
            cab-omitted nil cab-cut nil)
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
          ;; survey points stored as block references (e.g. "ab_pt"):
          ;; a block with this name is ALWAYS a point, on any layer, and
          ;; its insertion point is taken as the location (the blocks are
          ;; never exploded - non-destructive).  Checked first so such
          ;; blocks are never mistaken for perimeter geometry.
          ((and (= typ "INSERT")
                (= (strcase (cdr (assoc 2 ed))) (strcase *CAB-POINT-BLOCK*)))
           (cab:add-point (cab:2d (cdr (assoc 10 ed)))
                          (cab:block-number en)))
          ;; curve types we cannot fit, sitting on the POOL layer: count
          ;; them so the user gets told what to do, instead of a
          ;; mystifying "the perimeter does not close" later on
          ((and (= lay (strcase *CAB-POOL-LAYER*))
                (member typ '("SPLINE" "ELLIPSE")))
           (setq nunsup (1+ nunsup)))
          ;; CABHD's own stamped work on the POOL layer is never read
          ;; back as a guide - nor is ABHD's, whose pool-bottom lines
          ;; live there too and would wreck a fit read as perimeter
          ((and (= lay (strcase *CAB-POOL-LAYER*))
                (or (assoc -3 (entget en '("CABHD")))
                    (assoc -3 (entget en '("ABHD")))))
           nil)
          ;; perimeter / ordering sketch on the POOL layer
          ((= lay (strcase *CAB-POOL-LAYER*))
           (setq segs (append segs (cab:ent-segs en))))
          ;; plain POINT entities on the POINTS layer
          ((and (= lay (strcase *CAB-POINT-LAYER*)) (= typ "POINT"))
           (cab:add-point (cab:2d (cdr (assoc 10 ed))) nil))
          ;; any other block dropped on the POINTS layer -> a point too
          ((and (= typ "INSERT") (= lay (strcase *CAB-POINT-LAYER*)))
           (cab:add-point (cab:2d (cdr (assoc 10 ed)))
                          (cab:block-number en)))))
      (setq cab-allpts (reverse cab-allpts)      ; selection order
            dall       (if pts (cab:dedupe pts)))
      (if (> nunsup 0)
        (princ (strcat "\nCABHD: warning - " (itoa nunsup)
                       " SPLINE/ELLIPSE object(s) on layer "
                       *CAB-POOL-LAYER*
                       " were ignored (only lines, arcs, circles and"
                       " polylines can be read - explode or convert"
                       " them first).")))
      (if (> nocs 0)
        (princ (strcat "\nCABHD: warning - " (itoa nocs)
                       " selected object(s) are not drawn in the world"
                       " plane; the fit is flat (XY) and may be wrong."
                       "  Set UCS to World and flatten them first.")))
      (cond
        ((null pts)
         (princ (strcat "\nNo survey points found (looked for POINT entities on layer "
                        *CAB-POINT-LAYER* " and \"" *CAB-POINT-BLOCK*
                        "\" block insertions).")))
        ((and (null segs) (< (length dall) 3))
         (princ "\nPoints-only mode needs at least 3 distinct points."))
        (T
         ;; -- step 8: how far up the survey is the pool? -------------
         ;; The rule CABHD exists for.  Everything past the answer is
         ;; out of the perimeter entirely, so the fit never chases a
         ;; step, a bench or a depth shot it was never meant to trace.
         (setq cab-phase "reading the point cutoff")
         (princ "\n\n  Step 8 of 8 - how far up the point numbers does the pool edge run?")
         (princ "\n  A survey usually carries on past the pool - steps, benches, deck,")
         (princ "\n  depth shots - all numbered in the same run.  Everything past the")
         (princ "\n  number you give is left out of the perimeter: not fitted, not")
         (princ "\n  counted against the miss allowance, never reported as a miss.")
         (if (= cab-numbered 0)
           (princ (strcat "\n  NOTE: none of these points carry a "
                          *CAB-PT-TAG*
                          " attribute, so they are counted in the"
                          "\n  order they came out of the drawing -"
                          " usually the order they were created,"
                          "\n  but check the result before trusting it.")))
         (setq cab-cut  (cab:ask-cut dall nil)
               cab-phase "applying the point cutoff"
               pts     (cab:live-pts)
               dpts    (cab:dedupe pts))
         (if cab-cut
           (princ (strcat "\n  Up to Pt." (itoa cab-cut) " - "
                          (itoa (length dpts)) " point(s) in the perimeter, "
                          (itoa (- (length dall) (length dpts)))
                          " left out."))
           (princ (strcat "\n  Using all " (itoa (length dpts))
                          " point(s).")))
         ;; the miss allowance: this share of the points (the answer to
         ;; step 2, rounded UP to a whole point) may sit off the result
         ;; by up to TOL.  It is a share of the points the cutoff KEPT -
         ;; the ones it dropped buy no slack, since the line was never
         ;; asked to go near them
         (setq allow (cab:ceil (* (cab:misspct) (length dpts))))
         ;; snap the declared straight-wall ends onto actual survey
         ;; points - arc and wall endpoints always sit ON points
         (setq cab-phase "checking the declared walls, corners and holds"
               cab-walls nil)
         (foreach w rawwalls
           (setq w1 (cab:nearest (car w) dpts)
                 w2 (cab:nearest (cadr w) dpts))
           (cond
             ((or (cab:cut-away-p (car w) dall dpts)
                  (cab:cut-away-p (cadr w) dall dpts))
              (princ "\n  (a declared wall was anchored past the cutoff - that wall is ignored)"))
             ((or (null w1) (null w2)) nil)
             ((< (cab:dist w1 w2) *CAB-EXACT-EPS*)
              (princ "\n  (both ends of a declared wall landed on the same survey point - that wall is ignored)"))
             (T
              (if (or (> (cab:dist (car w) w1) (* 3.0 tol))
                      (> (cab:dist (cadr w) w2) (* 3.0 tol)))
                (princ "\n  (a declared wall end was picked well away from any survey point - snapped to the nearest one)"))
              (setq cab-walls (cons (list w1 w2) cab-walls)))))
         (setq cab-walls (reverse cab-walls))
         ;; declared corners snap onto survey points the same way
         (setq cab-corners nil)
         (foreach w rawcnrs
           (setq w1 (cab:nearest w dpts))
           (cond
             ((cab:cut-away-p w dall dpts)
              (princ "\n  (a declared corner was picked past the cutoff - it is ignored)"))
             (w1
              (if (> (cab:dist w w1) (* 3.0 tol))
                (princ "\n  (a declared corner was picked well away from any survey point - snapped to the nearest one)"))
              (setq cab-corners (cons w1 cab-corners)))))
         (setq cab-corners (reverse cab-corners))
         ;; held points snap onto survey points the same way; duplicates
         ;; collapse to one
         (setq cab-holds nil)
         (foreach w rawholds
           (setq w1 (cab:nearest w dpts))
           (cond
             ((cab:cut-away-p w dall dpts)
              (princ "\n  (a held point was picked past the cutoff - it is ignored)"))
             (w1
              (if (> (cab:dist w w1) (* 3.0 tol))
                (princ "\n  (a held point was picked well away from any survey point - snapped to the nearest one)"))
              (if (not (cab:memb w1 cab-holds))
                (setq cab-holds (cons w1 cab-holds))))))
         (setq cab-holds (reverse cab-holds))
         (if (> (length dpts) 150)
           (princ (strcat "\nCABHD: " (itoa (length dpts))
                          " points - ordering and fitting will take a"
                          " little while, please wait...")))
         ;; work out the mode, then hand all three modes to the same
         ;; compare-and-choose step
         (setq tour nil loop nil ok T)
         ;; below three points there is no perimeter to draw in ANY
         ;; mode; say so here rather than let the fitter hand back an
         ;; outline AutoCAD will refuse
         (if (< (length dpts) 3)
           (progn
             (princ (strcat "\nCABHD: only " (itoa (length dpts))
                            " point(s) are in the fit and a perimeter"
                            " needs at least 3."))
             (princ "\n  Run it again and give a higher cutoff, or All.")
             (setq ok nil)))
         (cond
           ((null ok) nil)
           ((null segs)
            ;; ---- POINTS-ONLY: order the points ourselves ----------
            (princ "\nNo POOL geometry selected - ordering the points automatically.")
            (setq cab-phase "ordering the points"
                  tour      (cab:order-points dpts)))
           ((null (setq loop (cab:chain segs)))
            (setq ok nil))                     ; cab:chain said why
           ((not (cab:has-arcs loop))
            ;; ---- ORDERING SKETCH: the drawn loop is all straight
            ;; lines, so it only tells us the ORDER of the points;
            ;; the shape itself comes from the points
            (if (< (length dpts) 3)
              (progn
                (princ (strcat "\nThe lines-only POOL sketch only orders"
                               " the points, and at least 3 distinct"
                               " points are needed to build a shape."))
                (setq ok nil))
              (progn
                (princ "\nPOOL sketch is lines only - using it just to order the points.")
                (setq cab-phase "following the sketch order"
                      tour      (cab:loop-order loop dpts)))))
           (T
            (princ "\nUsing the drawn POOL perimeter as the guide.")
            (princ "\n  (only the part of it the kept points reach is re-fitted)")
            (if cab-walls
              (princ (strcat "\n  (declared straight walls only steer"
                             " the points-built fit; here your drawn"
                             " straight segments are already kept)")))
            (if cab-holds
              (princ (strcat "\n  (held points only bind the"
                             " points-built fit; the drawn shape wins"
                             " here - the report flags any held point"
                             " the kept fit missed)")))))
         (if ok
           (progn
             (setq again T)
             (while again
               (setq again nil)
               (if (eq 'REDO (cab:compare tour loop pts dpts tol allow))
                 (progn
                   ;; -- redo: maybe omit points, move the cutoff,
                   ;; re-ask the numbers, draw a fresh trio ---------
                   (setq cab-phase "picking points to omit")
                   (princ "\n\nRedoing the fit.  Any points to leave out this time?")
                   (princ "\n  Pick each one (Enter for none) - mis-shots, duplicates, or")
                   (princ "\n  anything the line should not chase; each gets a dashed ring.")
                   (princ "\n  (this is for strays one at a time - the cutoff, asked next,")
                   (princ "\n  is what moves the end of the pool edge.)")
                   (if cab-omitted
                     (princ (strcat "\n  " (itoa (length cab-omitted))
                                    " point(s) are already out -"
                                    " picking one of those puts it"
                                    " BACK IN.")))
                   (while (setq wp1 (getpoint
                                      "\n  Point to omit - or a ringed one to restore (Enter when done): "))
                     (setq wp1 (cab:2d wp1)
                           w1  (cab:nearest wp1 dpts)
                           w2  (cab:nearest wp1 (mapcar 'car cab-omitted)))
                     (cond
                       ;; nearer to an already-omitted point: this
                       ;; click un-omits it - the point and its
                       ;; duplicates rejoin the fit, its ring goes
                       ((and w2 (or (null w1)
                                    (<= (cab:dist wp1 w2)
                                        (cab:dist wp1 w1))))
                        (setq ent (assoc w2 cab-omitted))
                        (if (and (cadr ent) (entget (cadr ent)))
                          (progn
                            (cab:temp-drop (cadr ent))
                            (entdel (cadr ent))))
                        (setq cab-omitted (cab:remove ent cab-omitted)
                              pts         (cab:live-pts)
                              dpts        (cab:dedupe pts))
                        (princ (strcat "  - Pt." (cab:pt-name w2)
                                       " back in")))
                       ;; otherwise omit: pull it - and its duplicates
                       ;; - out of the fit, the stats and the miss
                       ;; allowance alike, and remember how to undo it
                       (w1
                        (setq ring (cab:temp-add (cab:tag-mine
                                     (cab:draw-corner-marker w1)))
                              cab-omitted (cons (list w1 ring) cab-omitted)
                              pts         (cab:live-pts)
                              dpts        (cab:dedupe pts))
                        (princ (strcat "  - omitting Pt."
                                       (cab:pt-name w1))))))
                   ;; -- the cutoff can move too: the edge may run
                   ;; further up the survey than the first answer said,
                   ;; or stop short of it ---------------------------
                   (setq cab-phase "reading the point cutoff"
                         cut0      cab-cut)
                   (princ "\n\n  How far up the point numbers does the pool edge run?")
                   (princ "\n  Enter keeps the cutoff as it is; All puts every point back.")
                   (setq cab-cut (cab:ask-cut dall cab-cut))
                   (if (not (equal cut0 cab-cut))
                     (setq pts  (cab:live-pts)
                           dpts (cab:dedupe pts)))
                   (cab:prune-decls dpts)
                   (princ (strcat "\n  "
                                  (if cab-cut
                                    (strcat "Up to Pt." (itoa cab-cut))
                                    "Every point")
                                  ", "
                                  (if cab-omitted
                                    (strcat (itoa (length cab-omitted))
                                            " omitted, ")
                                    "")
                                  (itoa (length dpts))
                                  " point(s) in the fit."))
                   (if (< (length dpts) 3)
                     (princ "\nToo few points remain for a fit - nothing redone.")
                     (progn
                       ;; walls and corners may change for the retry
                       (princ "\n\n  Straight walls and sharp corners can change too -")
                       (princ "\n  Enter keeps each list as it is.")
                       (setq cab-phase "editing straight walls")
                       (cab:edit-walls dpts)
                       (setq cab-phase "editing sharp corners")
                       (cab:edit-corners dpts)
                       (setq cab-phase "editing held points")
                       (cab:edit-holds dpts)
                       (princ "\n\n  New settings - Enter keeps each one as it is.")
                       (setq cab-phase "reading the tolerance"
                             tol       (cab:ask-tol))
                       (setq cab-phase "reading the miss percentage"
                             cab-miss-pct (cab:ask-pct cab-miss-pct))
                       (setq cab-phase "reading the curve limit")
                       (cab:ask-cap)
                       (setq allow (cab:ceil (* (cab:misspct)
                                                (length dpts))))
                       ;; the point order must forget everything the
                       ;; omit list and the cutoff took out
                       (cond
                         ((null loop)
                          (setq cab-phase "ordering the points"
                                tour      (cab:order-points dpts)))
                         ((not (cab:has-arcs loop))
                          (setq tour (cab:loop-order loop dpts))))
                       (setq again T))))))))))))
  ;; sweep the dashed wall markers and any candidate the user did not
  ;; keep - the command tidies up after itself
  (cab:temp-clear)
  (if undo-open (command "_.UNDO" "_End"))
  (setq undo-open nil)
  ;; and sign off, naming the last step reached: a run that ends with
  ;; nothing on screen still has to say that it ended on purpose
  (princ (strcat "\nCABHD done (last step: "
                 (if cab-phase cab-phase "start") ")."))
  (setq *error* cab-old-err)   ; restore the previous error handler
  (princ))

;; ----------------------------------------------------------------------
(princ (strcat "\nCABHD " *cabhd-version*
               " loaded.  Type CABHD to fit a pool perimeter through"
               " the surveyed"))
(princ "\npoints, up to the point number where the pool edge stops.")
(princ "\nCABHDVER prints the version.")
(princ)
