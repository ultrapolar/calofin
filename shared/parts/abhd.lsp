;;; ===================================================================
;;; ABHD.LSP  --  Fit a pool perimeter through surveyed points
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  ABHD - fit the perimeter, then optionally the bottom
;;;            ADAB - the pool bottom on its own, over an existing
;;;                   perimeter (select the closed polyline or its
;;;                   exploded lines/arcs; the survey points sitting
;;;                   on it are found automatically)
;;;
;;; The user window-selects an area containing:
;;;   * On layer "POOL"   : (optional) a closed perimeter drawn as ONE
;;;                         closed polyline OR an exploded set of
;;;                         LINEs/ARCs.
;;;   * On layer "POINTS" : POINT entities surveyed on the real pool
;;;                         edge.
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
;;; within *PF-TANG-TOL* (8 degrees) of the previous arc's end
;;; tangent - close enough to look smooth, loose enough that the
;;; points stay in charge.  Sharp corners (over *PF-CORNER-ANG*) stay
;;; free kinks; the closing seam is held to the same window (the fit
;;; is re-run once with a seeded start tangent when the seam comes
;;; out worse).
;;;
;;; NICE RADII: arc radii are snapped to friendly increments before a
;;; free ("weird") number is accepted - whole feet first, then half
;;; feet, then whole inches (*PF-NICE-RADII*, drawing units = inches).
;;; The points outrank pretty radii: a snap may move covered points at
;;; most *PF-SNAP-EPS* beyond where they already sat and may never
;;; pull an arc off its anchor point; endpoints never move.
;;;
;;; THE MISS ALLOWANCE: the perimeter no longer has to thread every
;;; point exactly.  A share of the points - asked per run, standard
;;; *PF-MISS-PCT* (15%), rounded UP to the nearest whole point - may
;;; sit off the result by up to the max distance (default 1 unit =
;;; about an inch, capped at *PF-TOL-MAX*); every other point stays on
;;; it (within *PF-ON-EPS*).  That slack is spent where it buys the
;;; most: longer arcs, fewer curves, nicer radii.
;;;
;;; DECLARED STRAIGHT WALLS: the user may declare dead-straight walls
;;; up front by picking their two end points; each is marked with a
;;; dashed line on *PF-WALL-LAYER* and comes out of the points-built
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
;;; the user points at one (*PF-COMPARE*).  Fit 1 is the accurate end:
;;; it fits to *PF-TIGHT-TOL*, writes off no point at all, and obeys
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
;;;   * A point that turns more than *PF-CORNER-ANG* (45 deg) is a
;;;     sharp corner: it can start or end a span but is never buried
;;;     inside one, so polygonal shapes keep their corners as lines.
;;; Everything is fitted on the 2D plane - Z coordinates are ignored.
;;; Every segment shares its endpoints with its neighbours, so the
;;; result stays closed.
;;;
;;; A hit report is printed: how many points the new perimeter passes
;;; through exactly, how many are within tolerance, how many missed.
;;;
;;; THE POOL BOTTOM: once a perimeter is kept, the command offers to
;;; draw the floor too (Enter = No).  The user picks the two ends of
;;; the SHALLOW BREAK and the DEEP BREAK; the hopper - the flat
;;; deep-end floor - lies beyond the deep break, away from the
;;; shallow.  Its back is found automatically (the survey point
;;; nearest a perpendicular ray cast from the middle of the deep
;;; break), and three offsets - asked by point number, one at each
;;; deep break point, one at the back - pull the hopper in from the
;;; perimeter, blending gradually where they differ.  Slope lines
;;; join the hopper's ends to the shallow break points - each side is
;;; asked whether its line runs STRAIGHT, GUIDED (following the
;;; perimeter's curve, the offset easing to nothing at the shallow
;;; break), or through POINTS the user picks along that side, each
;;; with its own offset measured square off the wall - the line still
;;; runs guided between them.  Every prompt in the flow after the
;;; first offers Back ([Back] at the picks and choices, B typed at
;;; the offsets; Undo works too), re-opening the previous question -
;;; and in the POINTS loop, Back un-picks the last waypoint.  The
;;; hopper and the guided slopes are merged into as FEW long arcs as
;;; hold their shape (within *PF-BOTTOM-FIT*) - curves, not facets,
;;; and not many of them.
;;; Everything - the bottom's lines, the dimensions, and the kept
;;; perimeter itself - ends up on *PF-POOL-LAYER* (the deep break
;;; stubs dashed).
;;; ===================================================================
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.

;; ---- configuration -------------------------------------------------
(setq pf:*version*      "082726 REV07") ; announced on load.  The
                                    ; versioned twin of this file is
                                    ; named ABHD_<MMDDYY>_REV<##>.lsp
                                    ; so anyone can see which iteration
                                    ; is in a colleague's stack; bump
                                    ; this with every revision and
                                    ; re-copy the file so the twins
                                    ; stay identical (the tests check
                                    ; the name, the match, and this)
;; Cover mode: the pool-bottom question in pf:bottom answers No without
;; being asked, so a cover sheet is fitted to its perimeter and stops
;; there.  Set by ABHDCOVER, cleared on both exits from c:ABHD; nil for
;; a typed ABHD, always.
(setq abhd:*nobottom* nil)

(setq *PF-POOL-LAYER*   "POOL")     ; layer holding the drawn perimeter
(setq *PF-POINT-LAYER*  "POINTS")   ; layer holding the survey points
(setq *PF-POINT-BLOCK*  "ab_pt")    ; block name whose INSERTs mark survey
                                    ; points; the block's insertion point
                                    ; is taken as the point location
(setq *PF-OUT-LAYER*    "POOL-FIT") ; layer the fitted polyline goes on
(setq *PF-MISS-LAYER*   "FGStep")   ; layer the "could not hold this
                                    ; point" circles and their list go
                                    ; on.  This may well be a layer you
                                    ; already use, so ABHD stamps the
                                    ; objects it makes and only ever
                                    ; erases its own (see pf:tag-mine)
(setq *PF-MISS-RADIUS*  4.0)        ; radius of those circles (4 inches)
(setq *PF-PT-TAG*       "number")   ; attribute tag on the point block
                                    ; holding the surveyed point number,
                                    ; used to label it as "Pt.17"
(setq *PF-WALL-LAYER*   "POOL-WALLS"); layer the dashed markers for
                                    ; user-declared straight walls go on
(setq *PF-TOL-MAX*      2.0)        ; hard ceiling on the max-distance
                                    ; prompt (2 inches): further than
                                    ; that and the line is no longer a
                                    ; trace of the points
(setq *PF-BOTTOM-LAYER* "POOL-BOTTOM") ; legacy: where earlier versions
                                    ; of this command put the bottom
                                    ; geometry and dims.  Everything
                                    ; goes on *PF-POOL-LAYER* now, but
                                    ; ADAB still skips this layer when
                                    ; reading a selection
(setq *PF-BOTTOM-STEP*  6.0)        ; sampling step for the hopper
                                    ; offset curve (6 inches keeps it
                                    ; smooth without a heavy polyline)
(setq *PF-BOTTOM-FIT*   0.25)       ; merging those samples into long
                                    ; arcs may leave no sample further
                                    ; than this off the drawn curve (a
                                    ; quarter inch - invisible at pool
                                    ; scale, a big cut in arc count)
(setq *PF-PICKUP-EPS*   3.0)        ; a survey point within this of the
                                    ; selected perimeter counts as one
                                    ; of ITS points when ADAB gathers
                                    ; or trims them (3 in - genuine
                                    ; edge points sit within the fit
                                    ; tolerance, depth shots and deck
                                    ; points are feet away)
(if (null *PF-HOP-OFF*) (setq *PF-HOP-OFF* 18.0)) ; default hopper
                                    ; offset (18 in), remembered per
                                    ; session like the tolerance
(setq *PF-DIM-FTIN* "SIDE DIMENSION") ; dimension style stamped on the
                                    ; offset dims NOT anchored to a
                                    ; break point (hopper back, slope
                                    ; waypoints) when the offset was
                                    ; typed as feet-and-inches (3'6)
(setq *PF-DIM-IN* "STANDARD INCHES") ; same dims when the offset was
                                    ; typed in plain inches (42).
                                    ; Either style missing from the
                                    ; drawing falls back to the
                                    ; current style, with a note
(setq *PF-DIM-OFF* 12.0)            ; the deep-end dimension string
                                    ; (wall-to-hopper, hopper width,
                                    ; hopper-to-wall) sits this far off
                                    ; the deep break line (a foot), on
                                    ; the shallow-end side
(setq *PF-COMPARE*                  ; the three candidate fits offered:
  '(("tight" 1 "red"    "most curves - least error")
    ("asked" 2 "yellow" "as asked")
    ("few"   4 "cyan"   "fewest curves - still within the distance")))
                                    ; (mode, AutoCAD colour, colour name,
                                    ; description).  The three ask three
                                    ; different questions of the same
                                    ; points, so what is being chosen is
                                    ; an aim, not a tolerance:
                                    ;   "tight" - accuracy above all: it
                                    ;     fits to *PF-TIGHT-TOL*, lets no
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
(setq *PF-TIGHT-TOL*    0.01)       ; the "tight" candidate's accuracy
                                    ; target (units) - what it fits to
                                    ; instead of the distance typed at
                                    ; step 2, or that distance when it
                                    ; happens to be tighter still
(setq *PF-EXACT-EPS*    0.001)      ; "exactly on" threshold (units)
(setq *PF-FIT-EPS*      0.01)       ; if a single arc misses any of its
                                    ; points by more than this, split it
                                    ; into several arcs that hit exactly
(setq *PF-ON-EPS*       0.25)       ; a point within this of the result
                                    ; counts as ON it; only points off by
                                    ; more than this eat into the miss
                                    ; allowance below.  Calibrated from a
                                    ; hand-drawn reference trace: ~87% of
                                    ; its points sat within a quarter inch
(setq *PF-MISS-PCT*     0.15)       ; share of the points (rounded UP to
                                    ; a whole point) that may sit off the
                                    ; result by up to the tolerance
                                    ; (about an inch by default) - this
                                    ; slack is what buys longer spans and
                                    ; fewer curves
(setq *PF-CORNER-ANG*   (/ pi 4.0)) ; a point that turns more than this
                                    ; (45 deg) is a sharp corner: it may
                                    ; start or end a span but never gets
                                    ; buried inside one, so polygonal
                                    ; shapes keep their corners.  Sample
                                    ; real tight curves with at least ~3
                                    ; points per quarter turn to stay
                                    ; under it.
(setq *PF-NICE-RADII* '(12.0 6.0 1.0)) ; preferred arc-radius increments,
                                    ; tried in order: whole feet, half
                                    ; feet, whole inches (drawing units
                                    ; are inches).  A radius is snapped
                                    ; to the first increment whose arc
                                    ; still holds the points; only when
                                    ; none does is the free-fit ("weird")
                                    ; radius kept.
(setq *PF-TANG-TOL* (/ pi 22.5))    ; wiggle room from perfect
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
(setq *PF-TANG-STEPS* '(1.0 1.25 1.5)) ; when nothing fits inside the
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
(setq *PF-SNAP-EPS*     0.02)       ; a nice-radius snap may move the
                                    ; covered points at most this far
                                    ; beyond where they already sat, and
                                    ; it may never pull an arc off its
                                    ; anchor point entirely - the points
                                    ; outrank pretty radii
(setq *PF-CHAIN-FUZZ*   1.0e-4)     ; endpoint-matching fuzz for
                                    ; chaining exploded segments
(if (null *PF-TOL*) (setq *PF-TOL* 1.0)) ; default tolerance, 1 inch
;; *PF-MAX-ARCS* : cap on the number of curved segments in the output;
;; nil = no cap.  The command prompts for it (Enter keeps the current
;; value, "None" removes the cap) and remembers it for the session,
;; like *PF-TOL*.

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
;; passes through Q.  0.0 when the three points are collinear, and
;; also when the arc would be a (near) full circle - P1 and P2 lying
;; at the same angle from the center makes the sweep 0 or 2*pi, which
;; no single bulge can express.  Nearly-collinear noisy survey points
;; can produce exactly that, so both ends of the range are guarded.
(defun pf:bulge-3pt (p1 q p2 / c a1 a2 aq dccw dq)
  (setq p1 (cal:2d p1) q (cal:2d q) p2 (cal:2d p2)
        c  (pf:circumcenter p1 q p2))
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

;; Arc geometry of a bulged segment: (center radius angStart angEnd)
;; where the arc runs CCW from angStart to angEnd when bulge > 0 and
;; CW when bulge < 0.  nil for a straight segment.
(defun pf:arc-geom (p1 p2 b / ch dir apex c)
  (if (< (abs b) 1.0e-9)
    nil
    (progn
      (setq p1   (cal:2d p1)
            p2   (cal:2d p2)
            ch   (cal:dist p1 p2)
            dir  (cal:v* (cal:v- p2 p1) (/ 1.0 ch))
            ;; sagitta = (chord/2)*bulge; a positive (CCW) bulge apex
            ;; lies to the RIGHT of the p1->p2 chord direction
            apex (cal:v+ (cal:mid p1 p2)
                         (cal:v* (cal:perp dir) (* -0.5 ch b)))
            c    (pf:circumcenter p1 apex p2))
      (if (null c)
        nil
        (list c (cal:dist c p1) (angle c p1) (angle c p2))))))

;; Distance from point P to segment (p1 p2 bulge).
(defun pf:seg-dist (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep rel)
  (setq p  (cal:2d p)
        p1 (cal:2d (car seg))
        p2 (cal:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    ;; straight: project onto the segment, clamp to its ends
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
    ;; arc: radial distance when P falls inside the sweep, else the
    ;; nearer endpoint
    (progn
      (setq g (pf:arc-geom p1 p2 b))
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
;; (radians) and ends at B.  The angle between a chord and the tangent
;; at its end is half the included angle, so delta = 2*phi.
(defun pf:tangent-bulge (a tang b / phi)
  (setq phi (cal:signed-dang tang (angle (cal:2d a) (cal:2d b))))
  (cal:tan (/ phi 2.0)))

;; Tangent direction (radians) at the END of the arc from A to B with
;; the given bulge: chord direction + delta/2, delta = 4*atan(bulge).
(defun pf:end-tangent (a b bulge)
  (+ (angle (cal:2d a) (cal:2d b)) (* 2.0 (atan bulge))))

;; Position of P along segment (p1 p2 bulge) as a 0..1 parameter,
;; used only to ORDER candidate points along the segment.
(defun pf:seg-param (p seg / p1 p2 b v w len2 g c a1 a2 ap sweep rel)
  (setq p  (cal:2d p)
        p1 (cal:2d (car seg))
        p2 (cal:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    (progn
      (setq v (cal:v- p2 p1) w (cal:v- p p1) len2 (cal:dot v v))
      (if (< len2 1.0e-20) 0.0 (/ (cal:dot w v) len2)))
    (progn
      (setq g (pf:arc-geom p1 p2 b))
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

(defun pf:lw-segs (ed / pts bls item segs n closed)
  ;; collect (10) vertices and their (42) bulges, in order
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
               (< (cal:dist (last pts) (car pts)) *PF-CHAIN-FUZZ*)))
    (if (>= (cal:dist (last pts) (car pts)) *PF-CHAIN-FUZZ*)
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

(defun pf:ent-segs (en / ed typ c r a1 a2 delta)
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
     ;; a full-circle arc cannot be one bulged segment (its bulge is
     ;; infinite): hand back two semicircles instead
     (if (> delta (- (* 2.0 pi) 1.0e-9))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r) (cal:tan (/ delta 4.0))))))
    ;; a CIRCLE is a legitimate pool perimeter (round spa): two
    ;; semicircles, so the chaining and fitting code sees a normal
    ;; closed loop instead of reporting a gap
    ((= typ "CIRCLE")
     (setq c (cal:2d (cdr (assoc 10 ed)))
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
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
                  (>= (cal:dist end start) *PF-CHAIN-FUZZ*))
        (setq found nil rest nil)
        (foreach s segs
          (cond
            (found (setq rest (cons s rest)))
            ((< (cal:dist end (car s)) *PF-CHAIN-FUZZ*)
             (setq found s))
            ((< (cal:dist end (cadr s)) *PF-CHAIN-FUZZ*)
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
         (princ "\nABHD: gap in the POOL perimeter - could not close the loop.")
         nil)
        ((>= (cal:dist end start) *PF-CHAIN-FUZZ*)
         (princ "\nABHD: the POOL perimeter does not close.")
         nil)
        (T
         (if segs
           (princ (strcat "\nABHD: warning - "
                          (itoa (length segs))
                          " POOL segment(s) not part of the closed loop were ignored.")))
         (reverse loop))))))

;; ---- span fitting helpers --------------------------------------------
;; A "span" is one candidate segment from A to B judged against QS, the
;; survey points it is supposed to represent.

;; Worst distance from any of QS to the segment (A B bulge).
(defun pf:span-dev (a b bul qs / seg mx d q)
  (setq seg (list a b bul) mx 0.0)
  (foreach q qs
    (setq d (pf:seg-dist q seg))
    (if (> d mx) (setq mx d)))
  mx)

;; The miss percentage in force for the current run: the command binds
;; pf-miss-pct from the user's answer; Enter keeps the standard value.
(defun pf:misspct ()
  (if pf-miss-pct pf-miss-pct *PF-MISS-PCT*))

;; The "on the shape" threshold in force for the current run.  It
;; scales with the tolerance (a quarter of it, never below
;; *PF-ON-EPS*): if the user accepts 4 inches of error, a point 1 inch
;; off is plainly still ON the shape, and counting it as a miss would
;; burn the whole allowance on the first span and starve the rest of
;; the loop into single-point stubs.  pf-on-eps is bound per run by
;; the command and per pass by pf:fit-pass.
(defun pf:oneps ()
  (if pf-on-eps pf-on-eps *PF-ON-EPS*))

;; How many of QS sit farther than the on-the-shape threshold from the
;; segment - the points that would eat into the miss allowance.
(defun pf:span-misses (a b bul qs / seg c q lim)
  (setq seg (list a b bul) c 0 lim (pf:oneps))
  (foreach q qs
    (if (> (pf:seg-dist q seg) lim) (setq c (1+ c))))
  c)

;; Best single arc from A to B over the points QS: candidate bulges are
;; the exact 3-point fits through a few of the points plus the average
;; of them all; the one with the smallest worst-case deviation wins.
;; Returns (bulge . maxdev).
(defun pf:span-arc (a b qs / bls sum bl m cands best bd d)
  (setq bls (mapcar '(lambda (q) (pf:bulge-3pt a q b)) qs)
        sum 0.0
        m   (length qs))
  (foreach bl bls (setq sum (+ sum bl)))
  (setq cands (list (/ sum m) (nth (/ m 2) bls)))
  (if (>= m 4)
    (setq cands (append cands (list (nth (/ m 4) bls)
                                    (nth (/ (* 3 m) 4) bls)))))
  (setq best nil bd nil)
  (foreach bl cands
    (setq d (pf:span-dev a b bl qs))
    (if (or (null bd) (< d bd)) (setq best bl bd d)))
  (cons best bd))

;; Radius of the arc (A B bulge); nil for a straight segment.
(defun pf:bulge-radius (a b bl / h)
  (if (< (abs bl) 1.0e-9)
    nil
    (progn
      (setq h (/ (cal:dist a b) 2.0))
      (/ (* h (1+ (* bl bl))) (* 2.0 (abs bl))))))

;; Bulge of the arc from A to B with radius R, on the same side and
;; with the same minor/major-arc character as reference bulge BREF.
;; nil when R is too small to span the chord.
(defun pf:radius-bulge (a b r bref / h s bl)
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
;; "nice" radius - whole feet first, then half feet, then whole inches
;; (*PF-NICE-RADII*) - keeping every point within TOL and at most LEFT
;; of them off by more than *PF-ON-EPS*.  When WIN (a bulge interval)
;; is given the snapped bulge must stay inside it, so snapping never
;; breaks the tangency window.  The nearer multiple on each tier is
;; tried first; the arc's endpoints never move.  Returns
;; (bulge . misses) of the snapped arc, or nil.
(defun pf:snap-arc (a b bl qs tol left win / r0 h best tier lo hi
                                              cands r bl2 mis)
  (setq r0   (pf:bulge-radius a b bl)
        h    (/ (cal:dist a b) 2.0)
        best nil)
  (if (and r0 (< r0 1.0e6))       ; a huge radius is basically straight
    (foreach tier *PF-NICE-RADII*
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
                (setq bl2 (pf:radius-bulge a b r bl))
                (if (and bl2
                         (or (null win)
                             (and (>= bl2 (car win)) (<= bl2 (cdr win))))
                         (<= (pf:span-dev a b bl2 qs) tol)
                         (<= (setq mis (pf:span-misses a b bl2 qs))
                             left))
                  (setq best (cons bl2 mis))))))))))
  best)

;; ---- arc segment re-fitting ------------------------------------------
;; Re-fit one curved segment from P1 to P2 (original bulge B) through
;; CANDS, its nearby survey points sorted along the segment.  Returns a
;; list of one or more segments (p1 p2 bulge):
;;   * no candidates          -> the original arc, endpoints updated
;;   * a nice-radius (foot / half-foot / inch) arc holds every point
;;     within TOL and the miss allowance (pf-miss-left, set by the
;;     command) can absorb the off points
;;                            -> that single snapped arc, preferred
;;                               even over an exact free fit
;;   * one arc holds them all -> that single arc
;;   * one free arc keeps every point within TOL and the allowance
;;     covers it              -> that single arc; fewer curves beats
;;                               exactness, by design
;;   * otherwise              -> a tangent-continuous chain of arcs
;;                               passing exactly through every point
(defun pf:cap-bulge (b)
  (cond ((> b 5.0) 5.0) ((< b -5.0) -5.0) (T b)))

(defun pf:fit-arc-seg (p1 p2 b cands tol / ar bavg maxres mis nb q segs
                                            prev tang sn)
  (if (null cands)
    (list (list p1 p2 b))
    (progn
      (setq ar     (pf:span-arc p1 p2 cands)
            bavg   (car ar)
            maxres (cdr ar)
            sn     (pf:snap-arc p1 p2 bavg cands tol pf-miss-left nil))
      (cond
        ;; a nice-radius arc holds every point: take it first
        (sn
         (setq pf-miss-left (- pf-miss-left (cdr sn)))
         (list (list p1 p2 (car sn))))
        ;; a single free arc genuinely holds every point
        ((<= maxres *PF-FIT-EPS*)
         (list (list p1 p2 bavg)))
        ;; a single arc is close enough and the allowance covers it
        ((and (<= maxres tol)
              (<= (setq mis (pf:span-misses p1 p2 bavg cands))
                  pf-miss-left))
         (setq pf-miss-left (- pf-miss-left mis))
         (list (list p1 p2 bavg)))
        ;; subdivide.  First arc runs from P1 through the 1st point to
        ;; the 2nd; every further arc starts tangent to the previous one
        ;; and lands exactly on the next point; the last lands on P2.
        ;; All points are hit exactly and every internal joint is
        ;; tangent-continuous (smooth).
        (T
         (setq nb   (pf:bulge-3pt p1 (car cands) (cadr cands))
               segs (list (list p1 (cadr cands) nb))
               tang (pf:end-tangent p1 (cadr cands) nb)
               prev (cadr cands))
         (foreach q (cddr cands)
           (setq nb   (pf:cap-bulge (pf:tangent-bulge prev tang q))
                 segs (cons (list prev q nb) segs)
                 tang (pf:end-tangent prev q nb)
                 prev q))
         (setq nb (pf:cap-bulge (pf:tangent-bulge prev tang p2)))
         (reverse (cons (list prev p2 nb) segs)))))))

;; ---- points-only / ordering-sketch mode -------------------------------

;; Pure-AutoLISP list helpers (no Visual LISP / vl-* dependency, so the
;; command works even when (vl-load-com) has not been run).

;; Remove every element equal (within fuzz) to VAL from LST.
(defun pf:remove (val lst / out x)
  (foreach x lst
    (if (not (equal x val 1.0e-9)) (setq out (cons x out))))
  (reverse out))

;; Insert (key . val) pair X into the already-sorted list LST, keeping
;; ascending order by the pair's car (key).
(defun pf:ins-car (x lst)
  (cond ((null lst) (list x))
        ((< (car x) (car (car lst))) (cons x lst))
        (T (cons (car lst) (pf:ins-car x (cdr lst))))))

;; Insertion-sort a list of (key . val) pairs ascending by key.
(defun pf:sort-car (lst / out x)
  (foreach x lst (setq out (pf:ins-car x out)))
  out)

;; T when the chained loop contains at least one curved segment
(defun pf:has-arcs (loop / r)
  (foreach s loop (if (>= (abs (caddr s)) 1.0e-9) (setq r T)))
  r)

;; Order points into a closed tour: nearest-neighbour walk from the
;; leftmost point, then 2-opt passes to remove crossings.
(defun pf:order-points (pts / start cur tour rest best bd q d n i j k
                              pass improved ti ti1 tj tj1 delta head midl
                              taill)
  (setq start (car pts))
  (foreach q (cdr pts)
    (if (or (< (car q) (car start))
            (and (= (car q) (car start)) (< (cadr q) (cadr start))))
      (setq start q)))
  (setq cur  start
        rest (pf:remove start pts)
        tour (list start))
  (while rest
    (setq best nil bd nil)
    (foreach q rest
      (setq d (cal:dist cur q))
      (if (or (null bd) (< d bd)) (setq best q bd d)))
    (setq tour (cons best tour)
          cur  best
          rest (pf:remove best rest)))
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

;; Order points by their position along a user-drawn ordering sketch
;; (the chained loop): each point keys on segment-index + parameter.
(defun pf:loop-order (loop pts / keyed q best bd d i s tp)
  (foreach q pts
    (setq best 0 bd nil i 0)
    (foreach s loop
      (setq d (pf:seg-dist q s))
      (if (or (null bd) (< d bd)) (setq bd d best i))
      (setq i (1+ i)))
    (setq tp (pf:seg-param q (nth best loop)))
    (if (< tp 0.0) (setq tp 0.0))
    (if (> tp 1.0) (setq tp 1.0))
    (setq keyed (cons (cons (+ best tp) q) keyed)))
  (mapcar 'cdr (pf:sort-car keyed)))

;; The surveyed number carried by a point block, read from its
;; *PF-PT-TAG* attribute ("number" on ab_pt).  nil when the block has
;; no such attribute.
;;
;; DELIBERATELY strict: no first-numeric-attribute fallback, unlike
;; ABFIND/BPCALLOUT/LHD/FITABHD and cal:block-number.  The fitter
;; consumes every point it is handed, so a stray numbered block (a
;; detail bubble, a keynote) silently joining the survey would warp the
;; whole fit - a dropped untagged point is the visible, recoverable
;; failure.  Reviewed 2026-08-27 and kept on purpose; CABHD's copy
;; holds the same line for the same reason.
(defun pf:block-number (en / sub ed val)
  (setq sub (entnext en) val nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase *PF-PT-TAG*)))
      (setq val (cdr (assoc 1 ed))))
    (setq sub (entnext sub)))
  val)

;; Remember a point and what to call it, so a miss can be reported as
;; "Pt.17" using the number in the drawing rather than a private
;; index.  Points with no number of their own get the next count.
(defun pf:add-point (p nm)
  (setq npt        (1+ npt)
        pts        (cons p pts)
        pf-ptnames (cons (cons p (if (and nm (/= nm "")) nm (itoa npt)))
                         pf-ptnames)))

;; What to call the surveyed point at Q.
(defun pf:pt-name (q / nm p)
  (setq nm nil)
  (foreach p pf-ptnames
    (if (and (null nm) (< (cal:dist (car p) q) *PF-EXACT-EPS*))
      (setq nm (cdr p))))
  (if nm nm "?"))

;; The member of LST nearest to P.
(defun pf:nearest (p lst / best bd q d)
  (setq best nil bd nil)
  (foreach q lst
    (setq d (cal:dist p q))
    (if (or (null bd) (< d bd)) (setq best q bd d)))
  best)

;; Index of point P in TOUR (exact-point fuzz), or nil.
(defun pf:tour-index (p tour / i k q)
  (setq i nil k 0)
  (foreach q tour
    (if (and (null i) (< (cal:dist p q) *PF-EXACT-EPS*)) (setq i k))
    (setq k (1+ k)))
  i)

;; Rotate the closed TOUR so it starts at point P (used so a declared
;; straight wall never straddles the walk's origin).
(defun pf:rotate-to-point (tour p / i)
  (setq i (pf:tour-index p tour))
  (if (and i (> i 0))
    (append (cal:nthcdr i tour) (cal:sublist tour 0 i))
    tour))

;; Rotate the closed TOUR so it starts at its sharpest turn: the fitter
;; walks the loop from there, so the most corner-like point is always a
;; span endpoint and never gets buried inside a span.
(defun pf:rotate-to-corner (tour / n i prev cur next turn best bi)
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
(defun pf:arc-count (spans / c sp)
  (setq c 0)
  (foreach sp spans (if (>= (abs (caddr sp)) 1.0e-9) (setq c (1+ c))))
  c)

;; ---- near-tangent span fitting ---------------------------------------
;; Arcs sit ON the survey points: every span runs from tour point to
;; tour point and its interior is fitted through the points with exact
;; 3-point arcs.  Tangency is a WINDOW, not a chain: at each joint the
;; new arc's start tangent may differ from the previous arc's end
;; tangent by at most *PF-TANG-TOL* (8 degrees), so the perimeter
;; stays visually smooth while the points stay in charge.  A bulge
;; window is a cons (lo . hi); nil means unconstrained.

;; Allowed bulge interval for the span A->B whose START tangent must
;; lie within *PF-TANG-TOL* of the incoming tangent TE.  WF stretches
;; that limit (see *PF-TANG-STEPS*).  The window edges are clamped so
;; extreme (U-turn) geometry stays finite.
(defun pf:tang-window (te a b wf / tt phi alo ahi lo hi)
  (setq tt  (* *PF-TANG-TOL* wf)
        phi (cal:signed-dang te (angle a b))
        alo (max (min (/ (- phi tt) 2.0) 1.373) -1.373)
        ahi (max (min (/ (+ phi tt) 2.0) 1.373) -1.373)
        lo  (cal:tan alo)
        hi  (cal:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Allowed bulge interval for the CLOSING span A->B whose END tangent
;; must lie within *PF-TANG-TOL* (times WF) of the loop's start
;; tangent TS0.
(defun pf:end-window (ts0 a b wf / tt psi alo ahi lo hi)
  (setq tt  (* *PF-TANG-TOL* wf)
        psi (cal:signed-dang (angle a b) ts0)
        alo (max (min (/ (- psi tt) 2.0) 1.373) -1.373)
        ahi (max (min (/ (+ psi tt) 2.0) 1.373) -1.373)
        lo  (cal:tan alo)
        hi  (cal:tan ahi))
  (if (<= lo hi) (cons lo hi) (cons hi lo)))

;; Intersect two bulge windows.  When they don't overlap no bulge can
;; satisfy both joints, so the bulge halfway between them is used and
;; the leftover kink is split evenly across the two joints.
(defun pf:merge-windows (win win2 / lo hi)
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
(defun pf:clamp-b (b win)
  (cond ((null win) b)
        ((< b (car win)) (car win))
        ((> b (cdr win)) (cdr win))
        (T b)))

;; Closest any of QS comes to the segment (A B bulge) - used to test
;; whether an arc still passes through one of its interior points.
(defun pf:span-min (a b bul qs / seg mn d q)
  (setq seg (list a b bul) mn nil)
  (foreach q qs
    (setq d (pf:seg-dist q seg))
    (if (or (null mn) (< d mn)) (setq mn d)))
  mn)

;; Best bulge for the span A->B over interior points QS, restricted to
;; the tangent window WIN (nil = free).  EXACT 3-POINT ARCS COME
;; FIRST: an unclamped 3-point bulge through one of the actual
;; interior points - so the arc's middle lands ON a survey point - is
;; preferred whenever one holds the span within TOL and LEFT misses.
;; Compromise bulges (average / window-clamped / window edges), which
;; float between the points, are used only when no exact arc works.
;; Returns (bulge dev misses exactflag).
(defun pf:span-fit (a b qs win tol left / bls m sum bl cands best d mis)
  (setq bls  (mapcar '(lambda (q) (pf:bulge-3pt a q b)) qs)
        m    (length qs)
        best nil)
  ;; exact candidates: through an interior point AND inside the window
  (foreach bl bls
    (if (or (null win)
            (and (>= bl (car win)) (<= bl (cdr win))))
      (progn
        (setq d (pf:span-dev a b bl qs))
        (if (and (<= d tol)
                 (or (null best) (< d (cadr best))))
          (progn
            (setq mis (pf:span-misses a b bl qs))
            (if (<= mis left)
              (setq best (list bl d mis T))))))))
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
        (setq cands (append (mapcar '(lambda (bl) (pf:clamp-b bl win))
                                    cands)
                            (list (car win) (cdr win)
                                  (/ (+ (car win) (cdr win)) 2.0)))))
      (foreach bl cands
        (setq d (pf:span-dev a b bl qs))
        (if (or (null best) (< d (cadr best)))
          (setq best (list bl d (pf:span-misses a b bl qs) nil))))))
  best)

;; Cover the rotated closed TOUR with arcs whose endpoints sit ON the
;; tour points, every joint within *PF-TANG-TOL* of tangent.  Sharp
;; corners stay free kinks.  TE0 (may be nil) seeds the first span's
;; tangent window - used to close the seam.  LEFT is the miss
;; allowance for this pass; when PRO is true each span may spend only
;; its own fair share of it, so one greedy span cannot exhaust the
;; budget and starve the rest of the loop (the curve cap turns PRO off
;; because there the whole point is to trade accuracy for few curves).
;; Straight walls the user declared (pf-walls, bound by the command as
;; snapped point pairs) are emitted verbatim as LINE spans; ordinary
;; spans may neither swallow nor cross them.  Returns the segment list.
(defun pf:span-loop (tour tol left te0 pro / n sharp i prev cur next
                                             turn strtshp segs pos te
                                             ts0 lim a best bstx len go
                                             bnd win qs fr bl mis sn
                                             dev0 anch steps wf lm
                                             walls w i1 i2 fwd nogrow f
                                             wrec)
  (setq n (length tour))
  ;; flag the sharp corners (intentional kinks, window resets): turns
  ;; sharper than *PF-CORNER-ANG*, plus every point the user declared
  ;; a corner - there the tangency rule is waived on purpose
  (setq sharp nil i 0)
  (repeat n
    (setq prev (nth (rem (+ i n -1) n) tour)
          cur  (nth i tour)
          next (nth (rem (1+ i) n) tour)
          turn (abs (cal:signed-dang (angle prev cur) (angle cur next))))
    (setq sharp (cons (or (> turn *PF-CORNER-ANG*)
                          (pf:memb cur pf-corners))
                      sharp)
          i     (1+ i)))
  (setq sharp (reverse sharp))
  ;; map the declared straight walls onto tour indices, walking the
  ;; short way around; the tour was rotated so none straddles index 0
  (setq walls nil)
  (foreach w pf-walls
    (setq i1 (pf:tour-index (car w) tour)
          i2 (pf:tour-index (cadr w) tour))
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
    (if (pf:memb (nth i tour) pf-holds) (setq f T))
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
      ;; ---- a declared straight wall starts here: emit it verbatim --
      (progn
        (setq len  (- (cadr wrec) pos)
              bnd  (nth (rem (cadr wrec) n) tour)
              qs   (cal:sublist tour (1+ pos) (1- len))
              mis  (pf:span-misses a bnd 0.0 qs)
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
          best nil                   ; longest feasible span of any kind
          bstx nil                   ; longest span through an interior point
          steps *PF-TANG-STEPS*)
    ;; Smoothness is worth more than one extra arc, so the tangent
    ;; window is stretched by degrees rather than thrown away.  Only
    ;; when even the widest step finds nothing does the stub below take
    ;; over, and that continues the previous tangent exactly - so the
    ;; tangency rule is never simply abandoned.
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
                  win (if te (pf:tang-window te a bnd wf)))
            ;; the span that closes the loop must also end within the
            ;; tangent window of the loop's start
            (if (and (= (+ pos len) n) (not strtshp) ts0)
              (setq win (pf:merge-windows win
                                          (pf:end-window ts0 a bnd wf))))
            (setq qs (cal:sublist tour (1+ pos) (1- len))
                  lm (if pro
                       (min left (cal:ceil (* (pf:misspct) len)))
                       left)
                  fr (pf:span-fit a bnd qs win tol lm))
            (if (and (<= (cadr fr) tol) (<= (caddr fr) lm))
              (progn
                (setq best (list len (car fr) (caddr fr) win))
                (if (cadddr fr) (setq bstx best))
                (setq len (1+ len)))
              (setq go nil))))))
    ;; an arc that floats between the points has to earn its keep:
    ;; only take it when it covers at least 2 more points than the
    ;; longest arc that passes exactly through a point
    (if (and bstx best (< (car best) (+ (car bstx) 2)))
      (setq best bstx))
    (if (null best)
      ;; stub to the very next point: continue the incoming tangent
      ;; (clamped to a semicircle); with no tangent it stays straight
      (progn
        (setq bnd (nth (rem (1+ pos) n) tour))
        (if te
          (progn
            (setq bl (pf:tangent-bulge a te bnd))
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
      ;; nice-radius snap inside the same tangent window.  A snap may
      ;; never pull the arc off its points: covered points may only
      ;; move a hair (*PF-SNAP-EPS*) beyond where they already sat,
      ;; and an arc that passed through an interior point must still
      ;; pass through one after snapping.
      (progn
        (setq len  (car best)
              bl   (cadr best)
              win  (cadddr best)
              bnd  (nth (rem (+ pos len) n) tour)
              qs   (cal:sublist tour (1+ pos) (1- len))
              dev0 (pf:span-dev a bnd bl qs)
              anch (<= (pf:span-min a bnd bl qs) (* 2.0 *PF-FIT-EPS*))
              sn   (pf:snap-arc a bnd bl qs
                                (max dev0 *PF-SNAP-EPS*) left win))
        (if (and sn
                 (or (not anch)
                     (<= (pf:span-min a bnd (car sn) qs)
                         (* 2.0 *PF-FIT-EPS*))))
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

;; Tangent mismatch at the loop's closing joint (radians).
(defun pf:seam-kink (segs / sl sf te ts)
  (setq sl (last segs)
        sf (car segs)
        te (+ (angle (car sl) (cadr sl)) (* 2.0 (atan (caddr sl))))
        ts (- (angle (car sf) (cadr sf)) (* 2.0 (atan (caddr sf)))))
  (abs (cal:signed-dang te ts)))

;; One full fit; if the seam closes with more than *PF-TANG-TOL* of
;; kink, refit once seeding the first span's window with the arrival
;; tangent, and keep whichever seam is straighter.  The on-the-shape
;; threshold is bound here so it tracks this pass's tolerance.
(defun pf:fit-pass (tour tol left pro / segs k1 sl te0 segs2 pf-on-eps)
  (setq pf-on-eps (max *PF-ON-EPS* (* 0.25 tol))
        segs      (pf:span-loop tour tol left nil pro)
        k1        (pf:seam-kink segs))
  (if (> k1 (+ *PF-TANG-TOL* 0.001))
    (progn
      (setq sl    (last segs)
            te0   (+ (angle (car sl) (cadr sl))
                     (* 2.0 (atan (caddr sl))))
            segs2 (pf:span-loop tour tol left te0 pro))
      (if (< (pf:seam-kink segs2) k1) (setq segs segs2))))
  segs)

;; Points-only / ordering-sketch fit: arcs on the points, joints
;; within *PF-TANG-TOL* of tangent, nice radii.  LEFT is the miss
;; allowance the walk may spend and PRO whether each span is held to
;; its own fair share of it - lifting both is what buys long arcs at
;; an unchanged tolerance, which is how the "few" candidate trades
;; curves for nothing but slack the user already granted.  MAXARCS,
;; when set, is enforced by refitting the whole loop with a
;; progressively relaxed tolerance, which keeps the tangent windows
;; intact.  The fewest-curves result seen is kept, so an unreachably
;; small cap still returns the smallest fit possible - never the
;; biggest.
(defun pf:coarse-loop (tour tol maxarcs left pro / segs segs2 tol2 tries)
  ;; start the walk at a declared wall or corner when there is one, so
  ;; neither straddles the walk's origin; otherwise at the sharpest turn
  (setq tour (cond
               (pf-walls   (pf:rotate-to-point tour (car (car pf-walls))))
               (pf-corners (pf:rotate-to-point tour (car pf-corners)))
               (T          (pf:rotate-to-corner tour)))
        segs (pf:fit-pass tour tol left pro))
  ;; the cap deliberately buys few curves with accuracy, so the refits
  ;; drop both the miss allowance and the per-span fair share
  (if maxarcs
    (progn
      (setq tol2 tol tries 0)
      (while (and (> (pf:arc-count segs) maxarcs) (< tries 40))
        (setq tol2  (* tol2 1.4)
              tries (1+ tries)
              segs2 (pf:fit-pass tour tol2 1000000 nil))
        (if (< (pf:arc-count segs2) (pf:arc-count segs))
          (setq segs segs2)))))
  segs)

;; ---- self-intersection check -----------------------------------------
;; A loop that crosses itself almost always means the automatic point
;; ordering went around a narrow waist the wrong way.  We cannot fix
;; that from the points alone, but we can spot it and say so.

;; Cross product of (P-O) x (Q-O); its sign says which side Q is on.
(defun pf:cross3 (o p q)
  (- (* (- (car p) (car o)) (- (cadr q) (cadr o)))
     (* (- (cadr p) (cadr o)) (- (car q) (car o)))))

;; T when segments A-B and C-D properly cross.  Touching or shared
;; endpoints give a zero product and do not count.
(defun pf:segs-cross (a b c d / d1 d2 d3 d4)
  (setq d1 (pf:cross3 a b c) d2 (pf:cross3 a b d)
        d3 (pf:cross3 c d a) d4 (pf:cross3 c d b))
  (and (< (* d1 d2) 0.0) (< (* d3 d4) 0.0)))

;; Sample the fitted loop into a point list; arcs get intermediate
;; points so a bulging arc's real path is tested, not just its chord.
(defun pf:loop-pts (segs / out s g c r a1 a2 sweep k j aa)
  (setq out nil)
  (foreach s segs
    (setq out (cons (cal:2d (car s)) out))
    (if (>= (abs (caddr s)) 1.0e-9)
      (progn
        (setq g (pf:arc-geom (car s) (cadr s) (caddr s)))
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

;; T when the fitted loop crosses itself.
(defun pf:self-crosses (segs / p n found ti tj i j a b c d)
  (setq p (pf:loop-pts segs))
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
            (if (pf:segs-cross a b c d) (setq found T)))
          (setq tj (cdr tj) j (1+ j)))
        (setq ti (cdr ti) i (1+ i)))
      found)))

;; ---- output helpers --------------------------------------------------

;; How many fitted polylines are already on the output layer (counted
;; before the new one is drawn).
(defun pf:prior-fits (/ ss)
  (setq ss (ssget "_X" (list (cons 8 *PF-OUT-LAYER*)
                             '(0 . "LWPOLYLINE"))))
  (if ss (sslength ss) 0))

;; T when R is a whole multiple of one of the *PF-NICE-RADII* tiers.
(defun pf:nice-radius-p (r / found tier q)
  (setq found nil)
  (if (and r (< r 1.0e6))
    (foreach tier *PF-NICE-RADII*
      (setq q (/ r tier))
      (if (< (abs (- q (fix (+ q 0.5)))) 1.0e-6) (setq found T))))
  found)

;; verts: list of (pt bulge) in order, closed.  COL is an AutoCAD
;; colour index, or nil for BYLAYER.
(defun pf:make-pline (verts layer col / dxf v)
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
(defun pf:set-bylayer (en / ed)
  (cal:ensure-layer *PF-POOL-LAYER* 4)
  (setq ed (entget en)
        ed (subst (cons 8 *PF-POOL-LAYER*) (assoc 8 ed) ed))
  (if (assoc 62 ed) (setq ed (subst '(62 . 256) (assoc 62 ed) ed)))
  (entmod ed))

;; The points SEGS fails to hold within TOL.
(defun pf:unheld (segs pts tol / out q s d dmin)
  (setq out nil)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (pf:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin tol) (setq out (cons q out))))
  (reverse out))

;; List membership by position, within the exact-point fuzz.
(defun pf:memb (q lst / found p)
  (setq found nil)
  (foreach p lst
    (if (< (cal:dist p q) *PF-EXACT-EPS*) (setq found T)))
  found)

(defun pf:isect (a b / out q)
  (setq out nil)
  (foreach q a
    (if (pf:memb q b) (setq out (cons q out))))
  (reverse out))

;; ---- temporary preview geometry --------------------------------------
;; Everything ABHD draws to help you decide - the dashed straight-wall
;; markers, the three candidate outlines, their number labels - is
;; scaffolding, not a result.  Each piece is registered here as it is
;; created and swept away when the command ends, whether that is
;; normally, by ESC, or by an error, so no run leaves litter behind.
;; Whatever the user chooses to keep is dropped from the list first.

(defun pf:temp-add (en)
  (if en (setq pf-temp (cons en pf-temp)))
  en)

(defun pf:temp-drop (en / out x)
  (setq out nil)
  (foreach x pf-temp
    (if (not (eq x en)) (setq out (cons x out))))
  (setq pf-temp (reverse out))
  en)

;; entget returns nil for something already gone, so a piece erased
;; earlier is simply skipped instead of raising an error
(defun pf:temp-clear ( / en)
  (foreach en pf-temp
    (if (and en (entget en)) (entdel en)))
  (setq pf-temp nil))

;; Scaffolding removed early - when a Back re-opens the step that
;; drew it - rather than at command end.
(defun pf:temp-kill (en)
  (if (and en (entget en)) (entdel en))
  (pf:temp-drop en))

;; ---- "this one is mine" stamping -------------------------------------
;; ABHD writes onto layers the drawing may already be using - FGStep in
;; particular - so it must never clear a layer wholesale.  Everything it
;; creates carries a small piece of extended data naming this command,
;; and only stamped objects are ever erased again.

(defun pf:tag-mine (en / ed)
  (if en
    (progn
      (regapp "ABHD")
      (setq ed (entget en))
      (entmod (append ed (list (list -3 (list "ABHD" (cons 1000 "ABHD"))))))))
  en)

;; Erase only ABHD's own objects on a layer; anything the user drew
;; there is left alone.  Returns how many went.
(defun pf:purge-mine (name / ss i n en)
  (setq n 0)
  (if (tblsearch "LAYER" name)
    (progn
      (setq ss (ssget "_X" (list (cons 8 name))))
      (if ss
        (progn
          (setq i 0)
          (repeat (sslength ss)
            (setq en (ssname ss i))
            (if (assoc -3 (entget en '("ABHD")))
              (progn (entdel en) (setq n (1+ n))))
            (setq i (1+ i)))))))
  n)

;; Make sure the DASHED linetype exists (pure entmake, no command
;; calls).  Dash lengths are in drawing units - sized for an inch
;; drawing, so the dashes read at pool scale.
(defun pf:ensure-dashed ()
  (if (not (tblsearch "LTYPE" "DASHED"))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   '(2 . "DASHED") '(70 . 0)
                   '(3 . "Dashed __ __ __ __ __")
                   '(72 . 65) '(73 . 2) '(40 . 18.0)
                   '(49 . 12.0) '(74 . 0)
                   '(49 . -6.0) '(74 . 0)))))

;; Draw the dashed ring marking a user-declared sharp corner.
(defun pf:draw-corner-marker (p)
  (pf:ensure-dashed)
  (cal:ensure-layer *PF-WALL-LAYER* 8)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *PF-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 *PF-MISS-RADIUS*))))

;; Draw the marker for a user-declared HELD point: a dashed ring at
;; half the miss-ring radius, so it reads apart from corner rings.
(defun pf:draw-hold-marker (p)
  (pf:ensure-dashed)
  (cal:ensure-layer *PF-WALL-LAYER* 8)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                  (cons 8 *PF-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car p) (cadr p) 0.0))
                  (cons 40 (* 0.5 *PF-MISS-RADIUS*)))))

;; Draw the dashed marker for a user-declared straight wall.
(defun pf:draw-wall-marker (p1 p2)
  (pf:ensure-dashed)
  (cal:ensure-layer *PF-WALL-LAYER* 8)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity")
                  (cons 8 *PF-WALL-LAYER*) '(6 . "DASHED")
                  '(100 . "AcDbLine")
                  (cons 10 (list (car p1) (cadr p1) 0.0))
                  (cons 11 (list (car p2) (cadr p2) 0.0)))))

;; Bounding box of a point list, as (minx miny maxx maxy).
(defun pf:bbox (pts / x0 y0 x1 y1 q)
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
(defun pf:label (num colour bb hgt row top bot / x y out e pr)
  (setq x   (+ (caddr bb) (* 0.6 hgt))
        y   (- (cadddr bb) (* row hgt 2.1))
        out nil)
  ;; the number itself, full height
  (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *PF-OUT-LAYER*) (cons 62 colour)
                          '(100 . "AcDbText")
                          (cons 10 (list x y 0.0))
                          (cons 40 hgt)
                          (cons 1 num))))
  (if e (setq out (cons e out)))
  ;; its figures, smaller, on two lines to the right of the number
  (foreach pr (list (cons top (* 0.55 hgt)) (cons bot (* -0.05 hgt)))
    (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                            (cons 8 *PF-OUT-LAYER*) (cons 62 colour)
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
(defun pf:mark-unheld (bad segs bb hgt / q d s dmin keyed pair th x y
                                         line)
  ;; markers from an earlier run describe a fit that no longer exists;
  ;; only ABHD's own are removed, never anything else on the layer
  (pf:purge-mine *PF-MISS-LAYER*)
  (if bad
    (progn
      (cal:ensure-layer *PF-MISS-LAYER* 1)
      ;; rings on the points themselves
      (foreach q bad
        (pf:tag-mine
          (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                          (cons 8 *PF-MISS-LAYER*) '(100 . "AcDbCircle")
                          (cons 10 (list (car q) (cadr q) 0.0))
                          (cons 40 *PF-MISS-RADIUS*)))))
      ;; how far off each one is, worst first
      (setq keyed nil)
      (foreach q bad
        (setq dmin nil)
        (foreach s segs
          (setq d (pf:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (setq keyed (cons (cons dmin q) keyed)))
      (setq keyed (reverse (pf:sort-car keyed))
            th    (* 0.5 hgt)
            x     (+ (caddr bb) (* 0.6 hgt))
            y     (cadddr bb))
      (pf:tag-mine
        (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                        (cons 8 *PF-MISS-LAYER*) '(100 . "AcDbText")
                        (cons 10 (list x y 0.0))
                        (cons 40 th)
                        (cons 1 (strcat "POINTS OFF THE LINE ("
                                        (itoa (length bad)) ")")))))
      (foreach pair keyed
        (setq y    (- y (* th 1.6))
              line (strcat "Pt." (pf:pt-name (cdr pair))
                           "   off by " (rtos (car pair) 4 4)))
        (pf:tag-mine
          (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *PF-MISS-LAYER*) '(100 . "AcDbText")
                          (cons 10 (list x y 0.0))
                          (cons 40 th)
                          (cons 1 line)))))))
  keyed)

;; Print the hit report for the fit the user kept.  ALLOW is the run's
;; miss allowance (how many points were permitted to sit between the
;; on-the-shape threshold and the tolerance off the result).
(defun pf:report (newsegs pts tol allow prior / nl na hiton hitok miss
                                                q s s2 d dmin worst sum
                                                sumo no nice onpt inner
                                                ns i te ts kk mk nk
                                                hw hq pf-on-eps)
  ;; report against the same on-the-shape threshold the fit used
  (setq pf-on-eps (max *PF-ON-EPS* (* 0.25 tol)))
  (progn
      ;; -- segment mix, nice radii, arcs anchored on a point --------
      (setq nl 0 na 0 nice 0 onpt 0)
      (foreach s newsegs
        (if (< (abs (caddr s)) 1.0e-9)
          (setq nl (1+ nl))
          (progn
            (setq na (1+ na))
            (if (pf:nice-radius-p
                  (pf:bulge-radius (car s) (cadr s) (caddr s)))
              (setq nice (1+ nice)))
            ;; does this arc pass through a point other than its ends?
            (setq inner nil)
            (foreach q pts
              (if (and (> (cal:dist q (car s)) *PF-EXACT-EPS*)
                       (> (cal:dist q (cadr s)) *PF-EXACT-EPS*)
                       (<= (pf:seg-dist q s) (* 2.0 *PF-FIT-EPS*)))
                (setq inner T)))
            (if inner (setq onpt (1+ onpt))))))
      ;; -- how the survey points landed ------------------------------
      (setq hiton 0 hitok 0 miss 0 worst 0.0 sum 0.0 sumo 0.0 no 0)
      (foreach q pts
        (setq dmin nil)
        (foreach s newsegs
          (setq d (pf:seg-dist q s))
          (if (or (null dmin) (< d dmin)) (setq dmin d)))
        (if (> dmin worst) (setq worst dmin))
        (setq sum (+ sum dmin))
        (if (> dmin (pf:oneps))
          (setq sumo (+ sumo dmin) no (1+ no)))
        (cond
          ((<= dmin (pf:oneps)) (setq hiton (1+ hiton)))
          ((<= dmin tol)        (setq hitok (1+ hitok)))
          (T                    (setq miss  (1+ miss)))))
      ;; -- smoothness: worst kink at a joint that is not a corner ----
      (setq ns (length newsegs) i 0 mk 0.0 nk 0)
      (while (< i ns)
        (setq s  (nth i newsegs)
              s2 (nth (rem (1+ i) ns) newsegs)
              te (+ (angle (car s) (cadr s)) (* 2.0 (atan (caddr s))))
              ts (- (angle (car s2) (cadr s2)) (* 2.0 (atan (caddr s2))))
              kk (abs (cal:signed-dang te ts)))
        (if (<= kk *PF-CORNER-ANG*)     ; bigger = an intentional corner
          (progn
            (if (> kk mk) (setq mk kk))
            (if (> kk (+ *PF-TANG-TOL* 1.0e-6)) (setq nk (1+ nk)))))
        (setq i (1+ i)))
      (princ (strcat "\nABHD: " (itoa ns) " segments ("
                     (itoa nl) " lines + " (itoa na)
                     " curves) written to layer " *PF-POOL-LAYER* "."
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
                     (rtos (* 180.0 (/ *PF-TANG-TOL* pi)) 2 1) ")"))
      (if (> nk 0)
        (princ (strcat "\n  (" (itoa nk)
                       " joint(s) needed more than the tangent limit to"
                       " close the loop)")))
      (if pf-walls
        (princ (strcat "\n  (" (itoa (length pf-walls))
                       " declared straight wall(s) kept dead straight)")))
      (if pf-holds
        (progn
          ;; every held point must sit ON the kept fit exactly; one
          ;; that does not means the drawn shape or a declared wall
          ;; overruled it, and that deserves a loud line of its own
          (setq hw 0.0)
          (foreach q pf-holds
            (setq dmin nil)
            (foreach s newsegs
              (setq d (pf:seg-dist q s))
              (if (or (null dmin) (< d dmin)) (setq dmin d)))
            (if (> dmin hw) (setq hw dmin hq q)))
          (if (<= hw *PF-EXACT-EPS*)
            (princ (strcat "\n  (" (itoa (length pf-holds))
                           " held point(s) all landed on the line"
                           " exactly)"))
            (princ (strcat "\n  WARNING: held Pt." (pf:pt-name hq)
                           " is off by " (rtos hw 2 4)
                           " - the drawn shape or a declared wall"
                           " overruled it.")))))
      (if (and *PF-MAX-ARCS* (> na *PF-MAX-ARCS*))
        (princ (strcat "\n  (the curve cap is " (itoa *PF-MAX-ARCS*)
                       " but " (itoa na) " curves was the fewest"
                       " reachable: a closed loop needs at least 2"
                       " segments)")))
      (if (> miss 0)
        (princ "\n  (points beyond tolerance: the curve cap and/or the drawn shape overruled them)"))
      (if (pf:self-crosses newsegs)
        (princ (strcat "\n  WARNING: the result crosses itself - the"
                       " automatic point order is probably wrong."
                       "  Draw a rough lines-only loop on layer "
                       *PF-POOL-LAYER*
                       " through the points in the right order and"
                       " select it too.")))
      (if (> prior 0)
        (princ (strcat "\n  (" (itoa prior)
                       " earlier fit(s) were already on layer "
                       *PF-OUT-LAYER* " - erase them if you only want"
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
(defun pf:guided-fit (loop pts dpts tol ftol allow maxarcs
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
           (setq d (cal:dist v q))
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
                   (<= (pf:seg-dist q s) tol)
                   (> (cal:dist q p1) *PF-EXACT-EPS*)
                   (> (cal:dist q p2) *PF-EXACT-EPS*))
            (setq cands (cons (cons (pf:seg-param q s) q) cands))))
        (setq cands (mapcar 'cdr (pf:sort-car cands)))
        (setq clean nil)
        (foreach q cands
          (if (or (null clean)
                  (> (cal:dist q (car clean)) *PF-EXACT-EPS*))
            (setq clean (cons q clean))))
        (foreach ns (pf:fit-arc-seg p1 p2 b (reverse clean) ftol)
          (setq newsegs (cons ns newsegs)))))
    (setq n (1+ n)))
  (setq newsegs (reverse newsegs))
  ;; -- 3. the drawn shape is trusted, but the curve cap still wins --
  (if (and maxarcs
           (> (pf:arc-count newsegs) maxarcs)
           (>= (length dpts) 3))
    (progn
      (princ (strcat "\n  (the drawn perimeter needs "
                     (itoa (pf:arc-count newsegs))
                     " curves but the cap is " (itoa maxarcs)
                     " - refitting from the points instead)"))
      (setq pf-miss-left allow
            newsegs (pf:coarse-loop (pf:loop-order loop dpts)
                                    ftol maxarcs allow T))))
  newsegs)

;; Build one candidate fit in MODE - "tight", "asked" or "few", the
;; three aims listed against *PF-COMPARE*.  A non-nil TOUR means the
;; points drive the shape (points-only and ordering-sketch modes);
;; otherwise the drawn LOOP is re-fitted (guided mode).  TOL is always
;; the distance the user typed - it is what reads the drawn shape and
;; what the table judges every candidate against - and the mode sets
;; the three knobs that actually differ:
;;
;;   FTOL  how exactly the arcs must hold their points.  "tight" fits
;;         to *PF-TIGHT-TOL* (or to TOL when that is tighter yet),
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
(defun pf:build (tour loop pts dpts tol allow mode
                 / pf-miss-left pf-on-eps ftol left cap)
  (setq ftol (if (= mode "tight") (min tol *PF-TIGHT-TOL*) tol)
        left (cond ((= mode "tight") 0)
                   ((= mode "few")   1000000)
                   (T                allow))
        cap  (if (= mode "asked") *PF-MAX-ARCS*)
        pf-miss-left left
        pf-on-eps    (max *PF-ON-EPS* (* 0.25 ftol)))
  (if tour
    (pf:coarse-loop tour ftol cap left (not (= mode "few")))
    (pf:guided-fit loop pts dpts tol ftol left cap)))

;; Deviation summary for SEGS against PTS: (worst avg avg-off).
;;   worst   - furthest any point sits from the line
;;   avg     - mean over ALL points, so it counts the ones sitting on
;;             the line as the zeros they are
;;   avg-off - mean over only the points that are actually OFF the
;;             line (further than ON from it), which says how far the
;;             strays really stray; nil when nothing is off
(defun pf:devstats (segs pts on / w q s d dmin sum n sumo no)
  (setq w 0.0 sum 0.0 n 0 sumo 0.0 no 0)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (pf:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (> dmin w) (setq w dmin))
    (setq sum (+ sum dmin) n (1+ n))
    (if (> dmin on) (setq sumo (+ sumo dmin) no (1+ no))))
  (list w
        (if (> n 0) (/ sum n) 0.0)
        (if (> no 0) (/ sumo no) nil)))

;; A deviation for a table cell; "-" when there is nothing to average.
(defun pf:fmt-dev (x)
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
(defun pf:compare (tour loop pts dpts tol allow
                   / prior vars v e ent lab st onv segs bad allbad first
                     i pick idx keep ce bb hgt sel picked keyed pr res)
  (setq prior (pf:prior-fits))
  (cal:ensure-layer *PF-OUT-LAYER* 3)
  ;; every candidate is judged against the distance the user typed, so
  ;; "off the line" means the same thing in all three rows
  (setq onv (max *PF-ON-EPS* (* 0.25 tol)))
  ;; label height: a twentieth of the shape, so it reads at any zoom
  (setq bb  (pf:bbox pts)
        hgt (/ (max (- (caddr bb) (car bb))
                    (- (cadddr bb) (cadr bb)))
               20.0))
  (if (<= hgt 0.0) (setq hgt 1.0))
  (setq pf-phase "building the three candidate fits"
        vars     nil
        allbad   nil
        first    T
        i        1)
  (foreach v *PF-COMPARE*
    (setq segs (pf:build tour loop pts dpts tol allow (car v))
          ent  (pf:temp-add
                 (pf:make-pline
                   (mapcar '(lambda (s) (list (car s) (caddr s))) segs)
                   *PF-OUT-LAYER* (cadr v)))
          bad  (pf:unheld segs pts tol)
          st   (pf:devstats segs pts onv)
          ;; the same figures the table prints, spelled out so they
          ;; stand on their own beside the number in the drawing
          lab  (pf:label
                 (itoa i) (cadr v) bb hgt i
                 (strcat (itoa (length segs)) " segs    "
                         (itoa (pf:arc-count segs)) " curves    "
                         (itoa (length bad)) " not held    "
                         (cadddr v))
                 (strcat "worst " (pf:fmt-dev (car st))
                         "    avg all " (pf:fmt-dev (cadr st))
                         "    avg off " (pf:fmt-dev (caddr st))))
          vars (cons (list segs ent bad v lab st) vars)
          i    (1+ i))
    (foreach e lab (pf:temp-add e))
    ;; the note below is about points NO fit could hold, so only the
    ;; fits actually built to the user's distance get a vote.  The
    ;; tight one threads every point by construction - counting it
    ;; would empty the intersection every time and quietly retire the
    ;; warning that catches mis-shots
    (if (not (= (car v) "tight"))
      (if first
        (setq allbad bad first nil)
        (setq allbad (pf:isect allbad bad)))))
  (setq vars (reverse vars))
  (if (null (cadr (car vars)))
    (princ "\nABHD: could not draw the result - is the drawing read-only?")
    (progn
      (princ (strcat "\n\nThree candidate fits are now drawn on layer "
                     *PF-OUT-LAYER*
                     ",\neach numbered on screen in its own colour:\n"))
      (princ "\n   #  segs  curves  worst off  avg all  avg off  not held  ")
      (princ "\n   -  ----  ------  ---------  -------  -------  --------  ")
      (setq i 1)
      (foreach v vars
        (setq segs (car v) bad (caddr v) ce (cadddr v) st (nth 5 v))
        (princ (strcat "\n   " (itoa i) "  "
                       (cal:pad (itoa (length segs)) 6)
                       (cal:pad (itoa (pf:arc-count segs)) 8)
                       (cal:pad (pf:fmt-dev (car st)) 11)
                       (cal:pad (pf:fmt-dev (cadr st)) 9)
                       (cal:pad (pf:fmt-dev (caddr st)) 9)
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
                     (if *PF-MAX-ARCS* " and the curve cap" "")
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
      ;; -- let the user choose ---------------------------------------
      ;; Clicking the outline you want beats translating a colour into
      ;; a number, so a pick on screen is offered first; typing the
      ;; number still works for anyone who prefers the keyboard.
      (setq pf-phase "waiting for the choice of fit")
      (princ "\n\n  Click the outline you want to keep, or type its number.")
      (princ "\n  Redo refits with new settings, and lets you omit points first.")
      (initget "1 2 3 All None Redo")
      (setq pick (getkword
                   "\n  Keep which fit - click one, or [1/2/3/All/None/Redo] <2>: "))
      (if (null pick)
        ;; no keyword typed: give them a click, and fall back to 2
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
         (foreach v vars
           (pf:temp-drop (cadr v))
           (foreach e (nth 4 v) (pf:temp-drop e)))
         (princ "\nKeeping all three, in their preview colours.")
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
         (if keep
           (princ (strcat "\n  Keeping fit " pick " - "
                          (cadddr (cadddr keep)) ".")))
         (if (cadr keep)
           (progn
             (pf:temp-drop (cadr keep))
             (pf:set-bylayer (cadr keep))))))
      (if keep
        (progn
          (setq keyed (pf:mark-unheld (caddr keep) (car keep) bb hgt))
          (pf:report (car keep) pts tol allow prior)
          (if keyed
            (progn
              (princ (strcat "\n  " (itoa (length keyed))
                             " point(s) beyond the distance are ringed"
                             " on layer " *PF-MISS-LAYER*
                             " and listed beside the pool, worst first:"))
              (foreach pr keyed
                (princ (strcat "\n    Pt." (pf:pt-name (cdr pr))
                               "   off by " (rtos (car pr) 4 4))))))
          ;; one perimeter was chosen, so the floor can be drawn too
          (pf:bottom (car keep) dpts T)))))
  (princ)
  res)

;; ---- the pool bottom (hopper) ----------------------------------------
;; After a perimeter is kept, the floor can be drawn in the same
;; sitting: the SHALLOW BREAK and DEEP BREAK lines across the pool,
;; and the hopper - the flat deep-end floor - as an inward offset of
;; the perimeter beyond the deep break.  Three offsets shape it,
;; asked by survey point number: one at each deep break point and one
;; at the back of the hopper, blending gradually in between when they
;; differ.  A slope line joins each of the hopper's ends to the
;; shallow break point on its side - straight, guided along the
;; perimeter's curve, or guided through points the user picks at
;; pinned offsets, asked per side.  The hopper and guided slopes are
;; drawn as few long arcs (merged within *PF-BOTTOM-FIT* - curved,
;; not faceted, not heavy).  Lines and dimensions all land on
;; *PF-POOL-LAYER*.

;; Closest point ON segment (p1 p2 bulge) to P - pf:seg-dist's twin,
;; returning the foot of the distance instead of the distance.
(defun pf:seg-near (p seg / p1 p2 b v w len2 t2 g c r a1 a2 ap sweep
                            rel)
  (setq p  (cal:2d p)
        p1 (cal:2d (car seg))
        p2 (cal:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) 1.0e-9)
    ;; straight: project onto the segment, clamp to its ends
    (progn
      (setq v    (cal:v- p2 p1)
            w    (cal:v- p p1)
            len2 (cal:dot v v))
      (if (< len2 1.0e-20)
        p1
        (progn
          (setq t2 (/ (cal:dot w v) len2))
          (if (< t2 0.0) (setq t2 0.0))
          (if (> t2 1.0) (setq t2 1.0))
          (cal:v+ p1 (cal:v* v t2)))))
    ;; arc: the radial foot when P falls inside the sweep, else the
    ;; nearer endpoint
    (progn
      (setq g (pf:arc-geom p1 p2 b))
      (if (null g)
        (if (<= (cal:dist p p1) (cal:dist p p2)) p1 p2)
        (progn
          (setq c  (car g)  r (cadr g)
                a1 (caddr g) a2 (cadddr g)
                ap (angle c p))
          (if (> b 0.0)
            (setq sweep (cal:angnorm (- a2 a1)) rel (cal:angnorm (- ap a1)))
            (setq sweep (cal:angnorm (- a1 a2)) rel (cal:angnorm (- ap a2))))
          (if (<= rel sweep)
            (cal:v+ c (cal:v* (list (cos ap) (sin ap)) r))
            (if (<= (cal:dist p p1) (cal:dist p p2)) p1 p2)))))))

;; Closest point on the whole loop to P.
(defun pf:curve-near (p segs / best bd s q d)
  (foreach s segs
    (setq q (pf:seg-near p s)
          d (cal:dist p q))
    (if (or (null bd) (< d bd)) (setq best q bd d)))
  best)

;; The subset of PTS sitting within EPS of the loop SEGS - the
;; perimeter's own survey points, as opposed to depth shots and deck
;; points that only happen to be nearby.
(defun pf:near-loop (pts segs eps / out q s d dmin)
  (foreach q pts
    (setq dmin nil)
    (foreach s segs
      (setq d (pf:seg-dist q s))
      (if (or (null dmin) (< d dmin)) (setq dmin d)))
    (if (and dmin (<= dmin eps)) (setq out (cons q out))))
  (reverse out))

;; Sample the closed loop into points spaced about STEP apart, walking
;; it in order: each segment contributes its start point plus enough
;; interior points that no gap exceeds STEP (its end is the next
;; segment's start, so nothing doubles up).
(defun pf:sample-loop (segs step / out s p1 p2 b g c r a1 a2 sweep
                                   len k j aa)
  (setq out nil)
  (foreach s segs
    (setq p1  (cal:2d (car s))
          p2  (cal:2d (cadr s))
          b   (caddr s)
          out (cons p1 out)
          g   (if (>= (abs b) 1.0e-9) (pf:arc-geom p1 p2 b)))
    (if g
      (progn
        (setq c  (car g)   r  (cadr g)
              a1 (caddr g) a2 (cadddr g))
        (if (> b 0.0)
          (setq sweep (cal:angnorm (- a2 a1)))
          (setq sweep (- (cal:angnorm (- a1 a2)))))
        (setq len (* r (abs sweep))
              k   (max 1 (fix (/ len step)))
              j   1)
        (while (< j k)
          (setq aa  (+ a1 (* sweep (/ (float j) (float k))))
                out (cons (list (+ (car c) (* r (cos aa)))
                                (+ (cadr c) (* r (sin aa))))
                          out)
                j   (1+ j))))
      (progn
        (setq len (cal:dist p1 p2)
              k   (max 1 (fix (/ len step)))
              j   1)
        (while (< j k)
          (setq out (cons (cal:v+ p1 (cal:v* (cal:v- p2 p1)
                                             (/ (float j) (float k))))
                          out)
                j   (1+ j))))))
  (reverse out))

;; Signed shoelace area of a point ring: positive = counter-clockwise.
;; Only the SIGN is used, to orient the inward normals.
(defun pf:loop-area (pts / sum prev q)
  (setq sum 0.0 prev (last pts))
  (foreach q pts
    (setq sum  (+ sum (- (* (car prev) (cadr q))
                         (* (car q) (cadr prev))))
          prev q))
  (/ sum 2.0))

;; Index of the sample nearest P.
(defun pf:near-idx (p pts / k best bd q d)
  (setq k 0 best 0 bd nil)
  (foreach q pts
    (setq d (cal:dist p q))
    (if (or (null bd) (< d bd)) (setq best k bd d))
    (setq k (1+ k)))
  best)

;; Inward unit normal of the sampled loop at index I.  The tangent
;; comes from the neighbouring samples; SGN is +1 for a counter-
;; clockwise ring (interior on the left of travel), -1 for clockwise.
(defun pf:samp-normal (i pts sgn / n u)
  (setq n (length pts)
        u (cal:unit (cal:v- (nth (rem (1+ i) n) pts)
                           (nth (rem (+ i n -1) n) pts))))
  (if (null u)
    (setq u (cal:unit (cal:v- (nth (rem (1+ i) n) pts) (nth i pts)))))
  (if (null u) (setq u '(1.0 0.0)))
  (cal:v* (cal:perp u) sgn))

;; A LINE on LAYER (nil = the pool layer) with linetype LTYP
;; (nil = ByLayer).
(defun pf:make-line (p1 p2 layer ltyp / dxf)
  (setq dxf (list '(0 . "LINE") '(100 . "AcDbEntity")
                  (cons 8 (if layer layer *PF-POOL-LAYER*))))
  (if ltyp (setq dxf (append dxf (list (cons 6 ltyp)))))
  (entmakex (append dxf
                    (list '(100 . "AcDbLine")
                          (cons 10 (list (car p1) (cadr p1) 0.0))
                          (cons 11 (list (car p2) (cadr p2) 0.0))))))

;; Make sure the DASHED2 linetype (the half-size dashes marking the
;; underwater break stubs) exists - pure entmake, like pf:ensure-dashed.
(defun pf:ensure-dashed2 ()
  (if (not (tblsearch "LTYPE" "DASHED2"))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   '(2 . "DASHED2") '(70 . 0)
                   '(3 . "Dashed (.5x) _ _ _ _ _")
                   '(72 . 65) '(73 . 2) '(40 . 9.0)
                   '(49 . 6.0) '(74 . 0)
                   '(49 . -3.0) '(74 . 0)))))

;; An OPEN polyline through PTS on the pool layer, with the segment
;; bulges BLS (one per segment, nil = all straight).
(defun pf:make-open-pline (pts bls / dxf q)
  (setq dxf (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                  (cons 8 *PF-POOL-LAYER*)
                  '(100 . "AcDbPolyline")
                  (cons 90 (length pts)) '(70 . 0)))
  (foreach q pts
    (setq dxf (append dxf (list (cons 10 q)
                                (cons 42 (if bls (car bls) 0.0))))
          bls (cdr bls)))
  (entmakex dxf))

;; One arc from sample I to sample J through their middle sample: its
;; bulge when every sample between them stays within *PF-BOTTOM-FIT*
;; of it, else nil.  (0.0 - a straight stretch - is a valid answer:
;; the offset of a dead-straight wall IS straight.)
(defun pf:arc-fits (pts i j / a b m bl seg k ok)
  (setq a   (nth i pts)
        b   (nth j pts)
        m   (nth (/ (+ i j) 2) pts)
        bl  (pf:bulge-3pt a m b)
        seg (list a b bl)
        ok  T
        k   (1+ i))
  (while (and ok (< k j))
    (if (> (pf:seg-dist (nth k pts) seg) *PF-BOTTOM-FIT*)
      (setq ok nil))
    (setq k (1+ k)))
  (if ok bl))

;; Replace a densely sampled run with as FEW arcs as hold every
;; sample within *PF-BOTTOM-FIT* of the drawn curve: spans grow
;; greedily (longest first), each drawn as the 3-point arc through
;; its middle sample, and every point in KEEP stays a vertex exactly,
;; so the dimension anchors sit ON the line.  Returns (verts bulges)
;; ready for pf:make-open-pline.
(defun pf:merge-arcs (pts keep / n idx q k i j bl verts bls prevk
                                stop rest)
  (setq n   (length pts)
        idx (list 0 (1- n)))
  (foreach q keep
    (setq k (pf:near-idx q pts))
    (if (and (> k 0) (< k (1- n)) (not (member k idx)))
      (setq idx (cons k idx))))
  (setq idx (mapcar 'car
                    (pf:sort-car (mapcar '(lambda (k) (cons k k))
                                         idx))))
  (setq verts (list (car pts))
        bls   nil
        prevk (car idx)
        rest  (cdr idx))
  (while rest
    (setq stop (car rest)
          i    prevk)
    (while (< i stop)
      (setq j stop bl nil)
      (while (and (null bl) (> j (1+ i)))
        (if (null (setq bl (pf:arc-fits pts i j)))
          (setq j (1- j))))
      (if (null bl)
        (setq j  (1+ i)
              bl (pf:arc-fits pts i j)))
      (setq verts (cons (nth j pts) verts)
            bls   (cons bl bls)
            i     j))
    (setq prevk stop
          rest  (cdr rest)))
  (list (reverse verts) (reverse bls)))

;; The dimension style to stamp on a new dim: NAME when the drawing
;; actually has it, else the current style - with a note the first
;; time each missing name comes up (pf-dim-warned is run-scoped).
(defun pf:dim-style (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    name
    (progn
      (if (and name (not (member name pf-dim-warned)))
        (progn
          (setq pf-dim-warned (cons name pf-dim-warned))
          (princ (strcat "\n  (dimension style \"" name
                         "\" is not in this drawing - using the"
                         " current style instead)"))))
      (getvar "DIMSTYLE"))))

;; An aligned dimension measuring PA to PB, in dimension style STY
;; (nil = current), its dimension line through PDL - or right on the
;; measured stretch when PDL is nil.  The empty group 1 makes AutoCAD
;; fill in the measured value (the "auto" dimension text) and build
;; the dimension block; nil comes back when the drawing cannot take a
;; dimension, and the caller says so once.
(defun pf:make-dim (pa pb sty pdl / m)
  (setq m (if pdl pdl (cal:mid pa pb)))
  (entmakex (list '(0 . "DIMENSION") '(100 . "AcDbEntity")
                  (cons 8 *PF-POOL-LAYER*)
                  '(100 . "AcDbDimension")
                  (cons 3 (pf:dim-style sty))
                  (cons 10 (list (car m) (cadr m) 0.0))
                  '(70 . 33)                     ; aligned + block flag
                  '(1 . "")                      ; text = the measurement
                  '(100 . "AcDbAlignedDimension")
                  (cons 13 (list (car pa) (cadr pa) 0.0))
                  (cons 14 (list (car pb) (cadr pb) 0.0)))))

;; Show an offset the way it was typed: architectural when it came in
;; as feet-and-inches, plain inches otherwise.  DEF is (value . ftin).
(defun pf:fmt-off (def)
  (if (cdr def) (rtos (car def) 4 4) (rtos (car def) 2 2)))

;; Read an offset distance, remembering HOW it was typed - as
;; feet-and-inches (3'6) or as plain inches (42) - because that
;; choice picks the dimension style later.  Returns (value . T) for
;; feet-and-inches, (value . nil) for inches; Enter takes DEF, a
;; (value . ftin) pair from the previous entry.  Negative input is
;; refused, zero too unless ALLOWZERO (a waypoint may pin the line
;; to the wall).  With BACK non-nil, typing B (Back; Undo works too)
;; returns the symbol PF-BACK instead.
(defun pf:get-off (msg def allowzero back / s v res)
  (setq res nil)
  (while (null res)
    (setq s (getstring T (strcat msg " <" (pf:fmt-off def) ">"
                                 (if back " [Back]" "") ": ")))
    (cond
      ((= s "") (setq res def))
      ((and back (cal:back-word-p s)) (setq res 'PF-BACK))
      (T
       (setq v (distof s 4))
       (cond
         ((null v)
          (princ "\n  (that is not a distance - type inches like 42, or feet and inches like 3'6)"))
         ((or (< v 0.0) (and (= v 0.0) (not allowzero)))
          (princ (strcat "\n  (the offset must be a positive distance"
                         (if allowzero " or zero" "") ")")))
         (T (setq res (cons v (if (wcmatch s "*'*") T nil))))))))
  res)

;; Snap a picked break point onto the nearest survey point, warning
;; when the pick was nowhere near one (same rule as declared walls).
(defun pf:snap-break (p dpts / q)
  (setq p (cal:2d p)
        q (pf:nearest p dpts))
  (if (null q)
    p
    (progn
      (if (> (cal:dist p q) (* 3.0 *PF-TOL*))
        (princ "\n  (picked well away from any survey point - snapped to the nearest one)"))
      q)))

;; The survey point marking the BACK of the hopper: cast a ray from
;; the middle of the deep break line, perpendicular to it, away from
;; the shallow break, and take the point closest to that ray on that
;; side.  nil when no survey point lies beyond the deep break at all.
(defun pf:hopper-back (dp1 dp2 sp1 sp2 dpts / mid u q t2 lat back bd)
  (setq mid (cal:mid dp1 dp2)
        u   (cal:unit (cal:perp (cal:v- dp2 dp1))))
  (if u
    (progn
      (if (> (cal:dot u (cal:v- (cal:mid sp1 sp2) mid)) 0.0)
        (setq u (cal:v* u -1.0)))
      (setq back nil bd nil)
      (foreach q dpts
        (setq t2  (cal:dot (cal:v- q mid) u)
              lat (abs (cal:dot (cal:v- q mid) (cal:perp u))))
        (if (and (> t2 *PF-EXACT-EPS*)
                 (or (null bd) (< lat bd)))
          (setq back q bd lat)))
      back)))

;; The hopper outline: walk the sampled perimeter from the deep break
;; point at sample I1 to the one at I2, whichever way round passes the
;; back point at IB, pushing every point inward by an offset that
;; blends OFF1 at the start through OFF3 at the back to OFF2 at the
;; end - a straight run over arc length, so differing offsets change
;; gradually.  P1 and P2 are the exact break positions and stand in
;; for their samples, so the hopper's ends land exactly off them.
;; Returns (hopperPts backPos perimeterPts walkDir), or nil when the
;; two deep break points share a sample.
(defun pf:hopper-pts (samps sgn i1 i2 ib p1 p2 off1 off2 off3
                      / n fwdb fwd2 dir cnt kb idxs i k base cum lt lb
                        prev q out j cj offv bl)
  (setq n    (length samps)
        fwdb (rem (+ (- ib i1) n) n)
        fwd2 (rem (+ (- i2 i1) n) n))
  ;; walk whichever way round passes the back of the hopper
  (if (<= fwdb fwd2)
    (setq dir 1  cnt fwd2 kb fwdb)
    (setq dir -1 cnt (rem (+ (- i1 i2) n) n)
          kb  (rem (+ (- i1 ib) n) n)))
  (if (< cnt 2)
    nil
    (progn
      ;; the perimeter points under the hopper, break to break
      (setq idxs nil i i1 k 0)
      (while (<= k cnt)
        (setq idxs (cons i idxs)
              i    (rem (+ i dir n) n)
              k    (1+ k)))
      (setq idxs (reverse idxs)
            base nil)
      (foreach i idxs (setq base (cons (nth i samps) base)))
      (setq base (reverse base)
            base (cons p1 (cdr base))
            base (reverse (cons p2 (cdr (reverse base)))))
      ;; arc length along the walk places the blend
      (setq cum nil lt 0.0 prev nil)
      (foreach q base
        (if prev (setq lt (+ lt (cal:dist prev q))))
        (setq cum (cons lt cum) prev q))
      (setq cum (reverse cum)
            lb  (nth kb cum))
      (if (< lt 1.0e-9)
        nil
        (progn
          (setq out nil j 0)
          (foreach q base
            (setq cj   (nth j cum)
                  offv (if (<= cj lb)
                         (+ off1 (* (- off3 off1)
                                    (if (> lb 1.0e-9) (/ cj lb) 1.0)))
                         (+ off3 (* (- off2 off3)
                                    (if (> (- lt lb) 1.0e-9)
                                      (/ (- cj lb) (- lt lb))
                                      1.0))))
                  out  (cons (cal:v+ q (cal:v*
                                         (pf:samp-normal (nth j idxs)
                                                         samps sgn)
                                         offv))
                             out)
                  j    (1+ j)))
          (setq out (reverse out))
          ;; the hopper's corners sit ON the deep break line itself,
          ;; OFF1 and OFF2 in from its ends - not merely near it
          (setq bl (cal:unit (cal:v- p2 p1)))
          (if bl
            (setq out (cons (cal:v+ p1 (cal:v* bl off1)) (cdr out))
                  out (reverse (cons (cal:v+ p2 (cal:v* bl (- off2)))
                                     (cdr (reverse out))))))
          (list out kb base dir))))))

;; Offset at arc position CJ, read off the piecewise profile ANCHORS
;; ((position . offset) ... sorted ascending, both ends included):
;; the offset runs straight between neighbouring anchors.
(defun pf:off-at (cj anchors / prev a res span)
  (setq prev (car anchors) res nil)
  (foreach a (cdr anchors)
    (if (and (null res) (<= cj (car a)))
      (setq span (- (car a) (car prev))
            res  (if (< span 1.0e-9)
                   (cdr a)
                   (+ (cdr prev)
                      (* (- (cdr a) (cdr prev))
                         (/ (- cj (car prev)) span))))))
    (if (null res) (setq prev a)))
  (if res res (cdr prev)))

;; A guided slope line: walk CNT samples from index IA in direction
;; DIR (the side away from the hopper), following the perimeter with
;; an inward offset that starts at OFFA on the hopper's end and eases
;; to nothing at the shallow break.  WAYPTS - (surveyPt offset ftin)
;; entries the user picked along this side - pin the offset to those
;; values where they sit, measured square off the wall (along the
;; local inward normal); between anchors the offset runs straight
;; over arc length, so the picked points steer the line and the curve
;; carries it the rest of the way.  PA and PB are the exact break
;; positions; the first point lands exactly on the hopper's corner EA
;; (which sits on the deep break line), the last exactly on the
;; shallow break point.
;; Returns (linePts dimTriples) - one (wallPt linePt ftin) per
;; accepted waypoint, so its offset can be dimensioned in the style
;; its format asks for - or nil when the walk is too short to bother
;; (the caller draws a straight line then).
(defun pf:slope-pts (samps sgn ia dir cnt pa pb offa waypts ea
                     / n idxs i k base cum lt prev q out j anchors wp
                       woff wfl bk bd d dims dv fade w cj out2)
  (setq n (length samps))
  (if (< cnt 2)
    nil
    (progn
      (setq idxs nil i ia k 0)
      (while (<= k cnt)
        (setq idxs (cons i idxs)
              i    (rem (+ i dir n) n)
              k    (1+ k)))
      (setq idxs (reverse idxs)
            base nil)
      (foreach i idxs (setq base (cons (nth i samps) base)))
      (setq base (reverse base)
            base (cons pa (cdr base))
            base (reverse (cons pb (cdr (reverse base)))))
      (setq cum nil lt 0.0 prev nil)
      (foreach q base
        (if prev (setq lt (+ lt (cal:dist prev q))))
        (setq cum (cons lt cum) prev q))
      (setq cum (reverse cum))
      (if (< lt 1.0e-9)
        nil
        (progn
          ;; the offset profile: pinned at both ends and at each
          ;; waypoint the user gave along this side
          (setq anchors (list (cons 0.0 offa)) dims nil)
          (foreach wp waypts
            (setq woff (cadr wp) wfl (caddr wp) wp (car wp)
                  bk nil bd nil k 0)
            (foreach q base
              (setq d (cal:dist wp q))
              (if (or (null bd) (< d bd)) (setq bk k bd d))
              (setq k (1+ k)))
            (cond
              ((> bd *PF-BOTTOM-STEP*)
               (princ (strcat "\n  (Pt." (pf:pt-name wp)
                              " is not on this side of the pool - its"
                              " offset is ignored)")))
              ((or (= bk 0) (= bk cnt))
               (princ (strcat "\n  (Pt." (pf:pt-name wp)
                              " sits on a break point - its offset is"
                              " ignored, the breaks rule there)")))
              (T
               (setq anchors (cons (cons (nth bk cum) woff) anchors)
                     dims    (cons (list (nth bk base) bk wfl)
                                   dims)))))
          (setq anchors (pf:sort-car anchors)
                anchors (append anchors (list (cons lt 0.0))))
          (setq out nil j 0)
          (foreach q base
            (setq out (cons (cal:v+ q (cal:v*
                                        (pf:samp-normal (nth j idxs)
                                                        samps sgn)
                                        (pf:off-at (nth j cum)
                                                   anchors)))
                            out)
                  j   (1+ j)))
          (setq out (reverse out))
          ;; the line must DEPART from the hopper's corner EA, not
          ;; merely have its first vertex moved there: pull the early
          ;; stretch by the gap between the corner and the plain
          ;; normal-offset start, fading the pull to nothing by the
          ;; first pinned anchor (or the shallow break when there is
          ;; none), so waypoint offsets stay exact
          (if ea
            (progn
              (setq dv   (cal:v- ea (car out))
                    fade (car (cadr anchors)))
              (if (< fade 1.0e-9) (setq fade lt))
              (setq out2 nil j 0)
              (foreach q out
                (setq cj   (nth j cum)
                      w    (if (< cj fade) (- 1.0 (/ cj fade)) 0.0)
                      out2 (cons (cal:v+ q (cal:v* dv w)) out2)
                      j    (1+ j)))
              (setq out (reverse out2))))
          (list out
                (mapcar '(lambda (pr) (list (car pr)
                                            (nth (cadr pr) out)
                                            (caddr pr)))
                        (reverse dims))))))))

;; Drop consecutive duplicates closer than a hundredth - a tight
;; offset can fold neighbouring samples onto each other.
(defun pf:thin-run (pts / out prev q)
  (foreach q pts
    (if (or (null prev) (> (cal:dist prev q) 0.01))
      (setq out (cons q out) prev q)))
  (reverse out))

;; Draw the rest of the bottom package: the hopper outline, the slope
;; lines, and an aligned dimension on each of the three hopper
;; offsets plus every waypoint offset.  GUIDED holds the user's
;; answer for each side: nil = straight, T = guided along the
;; perimeter's curve, or a list of (surveyPt offset ftin) waypoints =
;; guided through those pinned offsets.  Dims not anchored to a break
;; point (the hopper back, the waypoints) carry the dimension style
;; their typed format asks for: *PF-DIM-FTIN* when the offset came in
;; as feet-and-inches (BFL for the back one), *PF-DIM-IN* for plain
;; inches.  LINES holds the two break lines pf:bottom already drew;
;; everything stays scaffolding until the end, so an error in between
;; sweeps the lot - the bottom only ever lands complete.
(defun pf:bottom-draw (segs sp1 sp2 dp1 dp2 back off1 off2 off3 bfl
                       lines guided
                       / made samps sgn i1 i2 ib hp hpts base kb dir
                         n is1 is2 sl spec wdims desc1 desc2 e1 e2 q e
                         dimfail u)
  (setq pf-phase "building the hopper"
        samps    (pf:sample-loop segs *PF-BOTTOM-STEP*)
        sgn      (if (< (pf:loop-area samps) 0.0) -1.0 1.0)
        i1       (pf:near-idx dp1 samps)
        i2       (pf:near-idx dp2 samps)
        ib       (pf:near-idx (pf:curve-near back segs) samps)
        hp       (pf:hopper-pts samps sgn i1 i2 ib dp1 dp2
                                off1 off2 off3))
  (if (null hp)
    ;; the break lines stay scaffolding and are swept with the rest
    (princ "\n  (the deep break points sit on top of each other on the perimeter - the pool bottom was not added)")
    (progn
      (setq hpts (car hp)  kb  (cadr hp)
            base (caddr hp) dir (cadddr hp)
            e1   (car hpts) e2  (last hpts)
            made lines)
      (if (<= (cal:dist dp1 dp2) (+ off1 off2))
        (princ "\n  (warning: the two deep end offsets meet or overlap across the pool)"))
      ;; the deep break becomes THREE lines on the pool layer: dashed
      ;; stubs from each wall in to the hopper's corners, and a solid
      ;; (ByLayer) run across the hopper between them - the single
      ;; placeholder line drawn during the questions goes away
      (if (and (cadr lines) (entget (cadr lines)))
        (entdel (cadr lines)))
      (pf:ensure-dashed2)
      (cal:ensure-layer *PF-POOL-LAYER* 4)
      (setq made (cons (pf:temp-add (pf:tag-mine
                         (pf:make-line dp1 e1 nil "DASHED2")))
                       made)
            made (cons (pf:temp-add (pf:tag-mine
                         (pf:make-line e1 e2 nil nil)))
                       made)
            made (cons (pf:temp-add (pf:tag-mine
                         (pf:make-line e2 dp2 nil "DASHED2")))
                       made))
      ;; the hopper outline: the dense samples merge into as few long
      ;; arcs as hold the shape, the back anchor kept as a vertex so
      ;; its dimension sits on the line
      (setq sl   (pf:merge-arcs (pf:thin-run hpts)
                                (list (nth kb hpts)))
            made (cons (pf:temp-add (pf:tag-mine
                         (pf:make-open-pline (car sl) (cadr sl))))
                       made))
      ;; the slope lines: each hopper end joins the shallow break
      ;; point on its own side of the loop, so the two never cross -
      ;; walking away from the hopper from each deep break end, the
      ;; shallow projection met first is that side's partner
      (setq n   (length samps)
            is1 (pf:near-idx sp1 samps)
            is2 (pf:near-idx sp2 samps))
      (if (< (rem (+ (* dir (- i1 is2)) n n) n)
             (rem (+ (* dir (- i1 is1)) n n) n))
        (setq q sp1 sp1 sp2 sp2 q
              q is1 is1 is2 is2 q))
      ;; straight, eased in along the perimeter's own curve, or eased
      ;; through the offsets the user pinned at picked points
      (setq wdims nil
            spec  (car guided)
            sl    (if spec
                    (pf:slope-pts samps sgn i1 (- dir)
                                  (rem (+ (* dir (- i1 is1)) n n) n)
                                  dp1 sp1 off1
                                  (if (eq spec T) nil spec) e1)))
      (setq q     (if sl (pf:merge-arcs (pf:thin-run (car sl))
                                        (mapcar 'cadr (cadr sl)))))
      (setq made  (cons (pf:temp-add (pf:tag-mine
                          (if sl
                            (pf:make-open-pline (car q) (cadr q))
                            (pf:make-line e1 sp1 nil nil))))
                        made)
            wdims (if sl (append wdims (cadr sl)))
            desc1 (cond ((null sl) "straight")
                        ((cadr sl) (strcat "guided through "
                                           (itoa (length (cadr sl)))
                                           " point(s)"))
                        (T "guided")))
      (setq spec (cadr guided)
            sl   (if spec
                   (pf:slope-pts samps sgn i2 dir
                                 (rem (+ (* dir (- is2 i2)) n n) n)
                                 dp2 sp2 off2
                                 (if (eq spec T) nil spec) e2)))
      (setq q     (if sl (pf:merge-arcs (pf:thin-run (car sl))
                                        (mapcar 'cadr (cadr sl)))))
      (setq made  (cons (pf:temp-add (pf:tag-mine
                          (if sl
                            (pf:make-open-pline (car q) (cadr q))
                            (pf:make-line e2 sp2 nil nil))))
                        made)
            wdims (if sl (append wdims (cadr sl)) wdims)
            desc2 (cond ((null sl) "straight")
                        ((cadr sl) (strcat "guided through "
                                           (itoa (length (cadr sl)))
                                           " point(s)"))
                        (T "guided")))
      ;; dimension each offset right where it applies.  The deep end
      ;; gets the K/L/M-style string: wall-to-hopper, hopper width,
      ;; hopper-to-wall, all chained on one line a foot off the deep
      ;; break on the shallow-end side - the string reads from the
      ;; shallow end, not from over the deep end it measures.  Break-
      ;; point dims keep the current style; the back and waypoint dims
      ;; get the style their typed format asks for, on the measured
      ;; stretch itself
      (setq u (cal:unit (cal:perp (cal:v- dp2 dp1))))
      (if (and u
               (< (cal:dot u (cal:v- (cal:mid sp1 sp2) (cal:mid dp1 dp2)))
                  0.0))
        (setq u (cal:v* u -1.0)))       ; u points to the shallow side
      (setq dimfail nil)
      (foreach q (append
                   (list (list dp1 e1 nil
                               (if u (cal:v+ (cal:mid dp1 e1)
                                             (cal:v* u *PF-DIM-OFF*))))
                         (list e1 e2 nil
                               (if u (cal:v+ (cal:mid e1 e2)
                                             (cal:v* u *PF-DIM-OFF*))))
                         (list e2 dp2 nil
                               (if u (cal:v+ (cal:mid e2 dp2)
                                             (cal:v* u *PF-DIM-OFF*))))
                         (list (nth kb base) (nth kb hpts)
                               (if bfl *PF-DIM-FTIN* *PF-DIM-IN*)
                               nil))
                   (mapcar '(lambda (pr) (list (car pr) (cadr pr)
                                               (if (caddr pr)
                                                 *PF-DIM-FTIN*
                                                 *PF-DIM-IN*)
                                               nil))
                           wdims))
        (setq e (pf:make-dim (car q) (cadr q) (caddr q) (cadddr q)))
        (if e
          (setq made (cons (pf:temp-add e) made))
          (setq dimfail T)))
      (if dimfail
        (princ (strcat "\n  (a dimension could not be created - the"
                       " offsets are " (rtos off1 2 2) ", "
                       (rtos off2 2 2) " and " (rtos off3 2 2) ")")))
      ;; the flow finished: promote it all from scaffolding to result
      (foreach e made (if e (pf:temp-drop e)))
      (princ (strcat "\nPool bottom added on layer " *PF-POOL-LAYER*
                     ": the shallow break, the three-piece deep break"
                     " (dashed stubs, solid middle), the curved hopper"
                     " (offsets " (rtos off1 2 2) " / "
                     (rtos off3 2 2) " / " (rtos off2 2 2)
                     "), the slope lines (" desc1 " / " desc2
                     "), and every dimension - the deep-end string a"
                     " foot off the break, on the shallow side."))))
  (princ))

;; Ask how one slope line should run.  NM names the deep break point
;; whose side is being asked about; DPTS are the survey points and
;; DEFO - a (value . ftin) pair - seeds the offset default.  Returns
;; nil for straight, T for guided, or a list of (surveyPt offset
;; ftin) waypoints for a guided line that passes through picked
;; points at pinned offsets.
(defun pf:ask-slope (nm dpts defo / ans wp spec o seed marks mk done)
  (initget "Straight Guided Points Back Undo")
  (setq ans (getkword (strcat
              "\n  Slope line from the offset at Pt." nm
              " [Straight/Guided/Points/Back] <Straight>: ")))
  (setq slopemarks nil)     ; the caller's register of this side's rings
  (cond
    ((member ans '("Back" "Undo")) 'PF-BACK)
    ((= ans "Guided") T)
    ((/= ans "Points") nil)
    (T
     (princ "\n  Pick survey points along this side, between the breaks; each")
     (princ "\n  gets its own offset, measured square off the wall.  The line")
     (princ "\n  follows the curve through them and eases to the shallow break.")
     (setq spec     nil
           marks    nil
           seed     defo
           done     nil
           pf-phase "picking slope waypoints")
     (while (not done)
       (initget "Back Undo")
       (setq wp (getpoint (strcat
                  "\n  Point on the Pt." nm
                  " side (Enter when done) [Back]: ")))
       (cond
         ((null wp) (setq done T))
         ((= (type wp) 'STR)             ; Back: un-pick the last waypoint
          (if spec
            (progn
              (pf:temp-kill (car marks))
              (setq marks (cdr marks)
                    spec  (cdr spec)
                    seed  (if spec
                            (cons (cadr (car spec)) (caddr (car spec)))
                            defo))
              (princ "\n  Stepping back one point."))
            (setq done 'PF-BACK)))       ; none yet: back to the choice
         (T
          (setq wp (pf:snap-break wp dpts))
          ;; the dashed ring is scaffolding: it confirms the pick and
          ;; clears itself when the command ends (or on a Back)
          (setq mk (pf:temp-add (pf:tag-mine (pf:draw-corner-marker wp))))
          (setq pf-phase "reading a slope waypoint offset")
          (setq o (pf:get-off (strcat "\n  What is the offset at Pt."
                                      (pf:pt-name wp) "?")
                              seed T T))
          (if (eq o 'PF-BACK)
            (progn                       ; un-pick this waypoint, re-ask
              (pf:temp-kill mk)
              (princ "\n  Stepping back one point."))
            (setq spec  (cons (list wp (car o) (cdr o)) spec)
                  marks (cons mk marks)
                  seed  o))
          (setq pf-phase "picking slope waypoints"))))
     (cond
       ((eq done 'PF-BACK)               ; re-ask Straight/Guided/Points
        (pf:ask-slope nm dpts defo))
       (spec
        (setq slopemarks marks)
        (reverse spec))
       (T
        (princ "\n  (no points picked - guiding along the curve instead)")
        T)))))

;; The interactive flow, run once a perimeter is in hand.  SEGS is
;; the closed loop, DPTS the survey points.  With ASK the user is
;; first offered the bottom (Enter or No skips it - the ABHD ending);
;; without, the flow starts straight away (the ADAB command, which
;; exists only for this).
(defun pf:bottom (segs dpts ask / ans s1 s2 d1 d2 sp1 sp2 dp1 dp2
                                   back off1 off2 off3 o1 o2 o3 bfl
                                   lines nm1 nm2 g1 g2 g1m g2m
                                   slopemarks stage go quit v e)
  ;; Staged so every prompt after the first offers Back - [Back] at
  ;; the point picks, B typed at the offsets - re-opening the previous
  ;; question and removing the scaffolding it drew.  Enter at a pick
  ;; still cancels the whole bottom, as before.  A break line whose
  ;; ends land wrong re-opens its own pick instead of aborting.
  (setq stage (if ask 0 1) go T quit nil)
  (while (and go (not quit))
    (cond
      ;; -- offer the bottom (the ABHD ending; ADAB starts at 1)
      ((= stage 0)
       (setq pf-phase "asking about the pool bottom")
       (cond
         ;; cover mode: a cover sheet records the perimeter and nothing
         ;; below it, so this is answered No without being asked --
         ;; ABHDCOVER sets the flag and c:ABHD clears it again
         (abhd:*nobottom*
          (princ "\n\n  Cover sheet - skipping the bottom of the pool.")
          (setq go nil))
         (t
          (initget "Yes No")
          (setq ans (getkword
                      "\n\n  Add the bottom of the pool (breaks and hopper)? [Yes/No] <No>: "))
          (if (= ans "Yes") (setq stage 1) (setq go nil)))))

      ;; -- the shallow break, one end per stage
      ((= stage 1)
       (princ "\n\n  SHALLOW BREAK - where the flat shallow floor starts sloping down.")
       (princ "\n  Pick its two ends (snap to the survey points).")
       (setq pf-phase "picking the shallow break")
       (if ask (initget "Back Undo") (initget ""))
       (setq v (getpoint (strcat "\n  First shallow break point"
                                 (if ask " [Back]" "") ": ")))
       (cond
         ((null v)
          (princ "\n  (point pick cancelled - the pool bottom was not added)")
          (setq quit T))
         ((= (type v) 'STR) (setq stage 0))
         (T (setq s1 v stage 2))))
      ((= stage 2)
       (initget "Back Undo")
       (setq v (getpoint s1 "\n  Second shallow break point [Back]: "))
       (cond
         ((null v)
          (princ "\n  (point pick cancelled - the pool bottom was not added)")
          (setq quit T))
         ((= (type v) 'STR) (setq stage 1))
         (T (setq s2 v stage 3))))

      ;; -- the deep break
      ((= stage 3)
       (princ "\n  DEEP BREAK - where the slope levels out into the hopper.")
       (setq pf-phase "picking the deep break")
       (initget "Back Undo")
       (setq v (getpoint "\n  First deep break point [Back]: "))
       (cond
         ((null v)
          (princ "\n  (point pick cancelled - the pool bottom was not added)")
          (setq quit T))
         ((= (type v) 'STR) (setq stage 2))
         (T (setq d1 v stage 4))))
      ((= stage 4)
       (initget "Back Undo")
       (setq v (getpoint d1 "\n  Second deep break point [Back]: "))
       (cond
         ((null v)
          (princ "\n  (point pick cancelled - the pool bottom was not added)")
          (setq quit T))
         ((= (type v) 'STR) (setq stage 3))
         (T
          (setq d2 v)
          ;; break ends snap to survey points, like declared walls do
          (setq s1 (pf:snap-break s1 dpts) s2 (pf:snap-break s2 dpts)
                d1 (pf:snap-break d1 dpts) d2 (pf:snap-break d2 dpts))
          (cond
            ((< (cal:dist s1 s2) *PF-EXACT-EPS*)
             (princ "\n  (both ends of the shallow break landed on the same survey point - pick it again)")
             (setq stage 1))
            ((< (cal:dist d1 d2) *PF-EXACT-EPS*)
             (princ "\n  (both ends of the deep break landed on the same survey point - pick it again)")
             (setq stage 3))
            (T
             ;; the break ends land exactly on the kept perimeter
             (setq sp1  (pf:curve-near s1 segs)
                   sp2  (pf:curve-near s2 segs)
                   dp1  (pf:curve-near d1 segs)
                   dp2  (pf:curve-near d2 segs)
                   back (pf:hopper-back dp1 dp2 sp1 sp2 dpts))
             (cond
               ((null back)
                (princ (strcat "\n  (no survey point lies beyond the"
                               " deep break - are the two break lines"
                               " swapped?  Pick the deep break again)"))
                (setq stage 3))
               (T
                ;; both break lines go down now, solid, so what was
                ;; declared is visible while the offsets are typed;
                ;; they stay scaffolding until the whole flow lands.
                ;; A re-commit (after a Back) sweeps the old pair first.
                (foreach e lines (pf:temp-kill e))
                (cal:ensure-layer *PF-POOL-LAYER* 4)
                (setq lines (list (pf:temp-add (pf:tag-mine
                                    (pf:make-line sp1 sp2 nil nil)))
                                  (pf:temp-add (pf:tag-mine
                                    (pf:make-line dp1 dp2 nil nil)))))
                (princ (strcat "\n  Back of the hopper: Pt."
                               (pf:pt-name back)
                               " (the survey point straight out from"
                               " the deep break)."))
                (setq nm1 (pf:pt-name d1)
                      nm2 (pf:pt-name d2))
                (princ "\n  Three offsets pull the hopper in from the perimeter;")
                (princ "\n  they blend gradually where they differ.  Type inches (42)")
                (princ "\n  or feet and inches (3'6).")
                (setq stage 5))))))))

      ;; -- the three hopper offsets
      ((= stage 5)
       (setq pf-phase "reading the hopper offsets")
       (setq o1 (pf:get-off (strcat "\n  What is the deep end offset at Pt."
                                    nm1 "?")
                            (cons *PF-HOP-OFF* nil) nil T))
       (if (eq o1 'PF-BACK)
         (setq stage 4)
         (setq off1 (car o1) stage 6)))
      ((= stage 6)
       (setq o2 (pf:get-off (strcat "\n  What is the deep end offset at Pt."
                                    nm2 "?")
                            o1 nil T))
       (if (eq o2 'PF-BACK)
         (setq stage 5)
         (setq off2 (car o2) stage 7)))
      ((= stage 7)
       (setq o3 (pf:get-off (strcat "\n  What is the offset at the back of the"
                                    " hopper (Pt." (pf:pt-name back) ")?")
                            o1 nil T))
       (if (eq o3 'PF-BACK)
         (setq stage 6)
         (progn
           (setq off3 (car o3)
                 bfl  (cdr o3))
           (setq *PF-HOP-OFF* off1)
           ;; each slope line can run straight to the shallow break,
           ;; follow the perimeter's curve gently in, or pass through
           ;; picked points at pinned offsets
           (setq pf-phase "asking about the slope lines")
           (princ "\n  Each slope line can run STRAIGHT to the shallow break, be GUIDED")
           (princ "\n  by the perimeter - easing in along its curve - or pass through")
           (princ "\n  POINTS you pick along that side, each with its own offset.")
           (setq stage 8))))

      ;; -- one slope choice per side; Back at a choice re-opens the
      ;; -- previous question, sweeping that side's waypoint rings
      ((= stage 8)
       (foreach e g1m (pf:temp-kill e))
       (setq g1m nil
             v   (pf:ask-slope nm1 dpts o1))
       (if (eq v 'PF-BACK)
         (setq stage 7)
         (setq g1 v g1m slopemarks stage 9)))
      ((= stage 9)
       (foreach e g2m (pf:temp-kill e))
       (setq g2m nil
             v   (pf:ask-slope nm2 dpts o2))
       (if (eq v 'PF-BACK)
         (setq stage 8)
         (setq g2 v g2m slopemarks stage 10)))

      ;; -- everything is in hand: draw the bottom
      (T
       (pf:bottom-draw segs sp1 sp2 dp1 dp2 back
                       off1 off2 off3 bfl lines
                       (list g1 g2))
       (setq go nil))))
  (princ))

;; ---- the numeric parameters ------------------------------------------
;; Asked identically at the start of a run and again on a Redo -
;; Enter keeps the shown value each time.

;; Maximum distance from a point; remembered in *PF-TOL*.
(defun pf:ask-tol (/ tol)
  (initget 6)
  (setq tol (getdist (strcat "\n  Maximum distance from a point <"
                             (rtos *PF-TOL* 2 3) ">: ")))
  (if (null tol) (setq tol *PF-TOL*))
  (if (> tol *PF-TOL-MAX*)
    (progn
      (princ (strcat "\n  (more than " (rtos *PF-TOL-MAX* 2 1)
                     " and the line is no longer a trace of the points"
                     " - using " (rtos *PF-TOL-MAX* 2 1) ")"))
      (setq tol *PF-TOL-MAX*)))
  (setq *PF-TOL* tol)
  tol)

;; Share of the points allowed off the line, returned as a fraction;
;; DEF is the fraction Enter keeps.
(defun pf:ask-pct (def / pct)
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

;; Curve cap; remembered in *PF-MAX-ARCS* (nil = no cap).
(defun pf:ask-cap (/ mx)
  (initget 4 "None")
  (setq mx (getint (strcat "\n  Maximum curves <"
                           (if *PF-MAX-ARCS* (itoa *PF-MAX-ARCS*) "None")
                           ">: ")))
  (cond ((null mx) nil)                            ; Enter: keep as-is
        ((eq 'STR (type mx)) (setq *PF-MAX-ARCS* nil))
        (T (setq *PF-MAX-ARCS* mx)))
  *PF-MAX-ARCS*)

;; ---- redo-time editing of walls and corners --------------------------
;; A Redo may change more than the numbers: straight walls and sharp
;; corners can be added or removed before the refit.  Both editors
;; work on the run-scoped pf-walls / pf-corners lists and keep the
;; dashed markers in step with them.

;; Erase this run's scaffolding markers of one entity type on the
;; marker layer (walls are the LINEs, rings the CIRCLEs), so the set
;; can be redrawn to match an edited declaration list.
(defun pf:sweep-marks (etype / keep en ed)
  (setq keep nil)
  (foreach en pf-temp
    (setq ed (if (and en (entget en)) (entget en)))
    (if (and ed
             (= etype (cdr (assoc 0 ed)))
             (= (strcase *PF-WALL-LAYER*)
                (strcase (cdr (assoc 8 ed)))))
      (entdel en)
      (setq keep (cons en keep))))
  (setq pf-temp (reverse keep)))

;; Add or remove declared straight walls.  Ends snap to the survey
;; points; each change is confirmed by name and the dashed markers
;; follow.
(defun pf:edit-walls (dpts / ans wp1 wp2 w1 w2 best bd w d)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Straight walls (" (itoa (length pf-walls))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq pf-phase "picking a straight wall"
             wp1      (getpoint "\n  First end of the straight wall: ")
             wp2      (if wp1 (getpoint wp1 "\n  Second end: ")))
       (if wp2
         (progn
           (setq w1 (pf:snap-break wp1 dpts)
                 w2 (pf:snap-break wp2 dpts))
           (if (< (cal:dist w1 w2) *PF-EXACT-EPS*)
             (princ "\n  (both ends landed on the same survey point - ignored)")
             (progn
               (setq pf-walls (append pf-walls (list (list w1 w2))))
               (pf:temp-add (pf:tag-mine (pf:draw-wall-marker w1 w2)))
               (princ (strcat "\n  wall Pt." (pf:pt-name w1)
                              " - Pt." (pf:pt-name w2) " added")))))))
      ((= ans "Remove")
       (if (null pf-walls)
         (princ "\n  (no straight walls to remove)")
         (progn
           (setq pf-phase "removing a straight wall"
                 wp1      (getpoint "\n  Pick near the straight wall to remove: "))
           (if wp1
             (progn
               (setq wp1 (cal:2d wp1) best nil bd nil)
               (foreach w pf-walls
                 (setq d (pf:seg-dist wp1 (list (car w) (cadr w) 0.0)))
                 (if (or (null bd) (< d bd)) (setq best w bd d)))
               (setq pf-walls (pf:remove best pf-walls))
               ;; redraw the wall markers to match what is left
               (pf:sweep-marks "LINE")
               (foreach w pf-walls
                 (pf:temp-add (pf:tag-mine
                   (pf:draw-wall-marker (car w) (cadr w)))))
               (princ (strcat "\n  wall Pt." (pf:pt-name (car best))
                              " - Pt." (pf:pt-name (cadr best))
                              " removed")))))))
      (T (setq ans nil)))))

;; Add or remove declared sharp corners the same way.  (The corners
;; the fitter finds by itself - turns over *PF-CORNER-ANG* - are not
;; declarations and cannot be removed here.)
(defun pf:edit-corners (dpts / ans wp1 w1 best bd w)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Sharp corners (" (itoa (length pf-corners))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq pf-phase "picking a sharp corner"
             wp1      (getpoint "\n  Corner point: "))
       (if wp1
         (progn
           (setq w1 (pf:snap-break wp1 dpts))
           (if (pf:memb w1 pf-corners)
             (princ "\n  (that corner is already declared)")
             (progn
               (setq pf-corners (append pf-corners (list w1)))
               (pf:temp-add (pf:tag-mine (pf:draw-corner-marker w1)))
               (princ (strcat "\n  corner Pt." (pf:pt-name w1)
                              " added")))))))
      ((= ans "Remove")
       (if (null pf-corners)
         (princ "\n  (no declared corners to remove)")
         (progn
           (setq pf-phase "removing a sharp corner"
                 wp1      (getpoint "\n  Pick the declared corner to remove: "))
           (if wp1
             (progn
               (setq wp1 (cal:2d wp1) best nil bd nil)
               (foreach w pf-corners
                 (if (or (null bd) (< (cal:dist wp1 w) bd))
                   (setq best w bd (cal:dist wp1 w))))
               (setq pf-corners (pf:remove best pf-corners))
               ;; the rings share their look with the omit markers;
               ;; redraw the corner and hold rings (spent omit rings
               ;; go quietly - the omissions already happened)
               (pf:sweep-marks "CIRCLE")
               (foreach w pf-corners
                 (pf:temp-add (pf:tag-mine (pf:draw-corner-marker w))))
               (foreach w pf-holds
                 (pf:temp-add (pf:tag-mine (pf:draw-hold-marker w))))
               (princ (strcat "\n  corner Pt." (pf:pt-name best)
                              " removed")))))))
      (T (setq ans nil)))))

;; Add or remove HELD points the same way.
(defun pf:edit-holds (dpts / ans wp1 w1 best bd w)
  (setq ans T)
  (while ans
    (initget "Add Remove Keep")
    (setq ans (getkword (strcat
                "\n  Held points (" (itoa (length pf-holds))
                " declared) - [Add/Remove/Keep] <Keep>: ")))
    (cond
      ((= ans "Add")
       (setq pf-phase "picking a held point"
             wp1      (getpoint "\n  Point to hold exactly: "))
       (if wp1
         (progn
           (setq w1 (pf:snap-break wp1 dpts))
           (if (pf:memb w1 pf-holds)
             (princ "\n  (that point is already held)")
             (progn
               (setq pf-holds (append pf-holds (list w1)))
               (pf:temp-add (pf:tag-mine (pf:draw-hold-marker w1)))
               (princ (strcat "\n  held Pt." (pf:pt-name w1)
                              " added")))))))
      ((= ans "Remove")
       (if (null pf-holds)
         (princ "\n  (no held points to remove)")
         (progn
           (setq pf-phase "removing a held point"
                 wp1      (getpoint "\n  Pick the held point to release: "))
           (if wp1
             (progn
               (setq wp1 (cal:2d wp1) best nil bd nil)
               (foreach w pf-holds
                 (if (or (null bd) (< (cal:dist wp1 w) bd))
                   (setq best w bd (cal:dist wp1 w))))
               (setq pf-holds (pf:remove best pf-holds))
               ;; redraw the rings to match what is left
               (pf:sweep-marks "CIRCLE")
               (foreach w pf-corners
                 (pf:temp-add (pf:tag-mine (pf:draw-corner-marker w))))
               (foreach w pf-holds
                 (pf:temp-add (pf:tag-mine (pf:draw-hold-marker w))))
               (princ (strcat "\n  held Pt." (pf:pt-name best)
                              " released")))))))
      (T (setq ans nil)))))

;; ---- the command -----------------------------------------------------
(defun c:ABHD ( / tol ans go wp1 wp2 rawwalls rawcnrs rawholds w w1 w2
                    ss i en ed lay typ ext nunsup nocs
                    segs pts dpts allow loop tour ok stale npt
                    again omits pts2 ent ring pf-omitted
                    pf-miss-pct pf-walls pf-corners pf-holds
                    pf-temp pf-ptnames
                    pf-dim-warned *error* pf-old-err pf-phase)
  ;; report which step failed if anything goes wrong, sweep away any
  ;; preview geometry drawn so far, then restore the old handler - a
  ;; cancelled run must not leave dashed markers or candidate outlines
  ;; lying around
  (setq pf-temp   nil
        pf-old-err *error*
        *error*
          (lambda (m)
            (if (and m (not (wcmatch (strcase m)
                     "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
              (princ (strcat "\nABHD stopped while "
                             (if pf-phase pf-phase "starting up")
                             " -- " m)))
            (pf:temp-clear)
            (setq *error* pf-old-err)
            ;; cover mode must not outlive the run that asked for it,
            ;; or the next ABHD would skip its bottom without a word
            (setq abhd:*nobottom* nil)
            (princ)))

  ;; sweep leftovers from a run that was interrupted before it could
  ;; tidy up after itself
  (setq stale (pf:purge-mine *PF-WALL-LAYER*))
  (if (> stale 0)
    (princ (strcat "\nABHD: cleared " (itoa stale)
                   " leftover marker(s) from layer " *PF-WALL-LAYER*
                   ".")))

  (princ "\n\nABHD - fit a pool perimeter through the surveyed points.")

  ;; -- step 1: how close must the line stay to the points? ----------
  ;; This is the one prompt people misread, so it says in plain words
  ;; what the number means and which way it moves the result.
  ;; initget 6 refuses zero and negative values - a zero tolerance
  ;; would silently collapse the fit into single-point stubs.
  (setq pf-phase "reading the tolerance")
  (princ "\n\n  Step 1 of 7 - how far may the fitted line sit from a survey point?")
  (princ "\n  Type a distance in drawing units (1 = one inch, 2 at most), or")
  (princ "\n  pick two points in the drawing to measure one.")
  (princ "\n  Smaller = hugs the points.  Bigger = smoother, with fewer curves.")
  (setq tol (pf:ask-tol))

  ;; -- step 2: how many of the points may sit off the line? ---------
  ;; Enter means the standard share; the answer is per run, on purpose.
  (setq pf-phase "reading the miss percentage")
  (princ "\n\n  Step 2 of 7 - what percent of the points may sit OFF the line")
  (princ "\n  (off, but still within the distance above)?")
  (princ (strcat "\n  Press Enter for the standard "
                 (itoa (fix (+ 0.5 (* 100.0 *PF-MISS-PCT*))))
                 " percent."))
  (setq pf-miss-pct (pf:ask-pct *PF-MISS-PCT*))

  ;; -- step 3: optional cap on how many curves the result may use ---
  (setq pf-phase "reading the curve limit")
  (princ "\n\n  Step 3 of 7 - limit how many curves the result may use?")
  (princ "\n  Type a whole number, or None for no limit.")
  (pf:ask-cap)

  ;; -- step 4: any dead-straight walls to declare? ------------------
  ;; Each declared wall is marked with a dashed line right away and
  ;; comes out of the fit as a straight LINE between those two survey
  ;; points, no matter what the arcs around it are doing.
  (setq pf-phase "asking about straight lines")
  (princ "\n\n  Step 4 of 7 - does the pool edge have any dead-straight walls?")
  (princ "\n  If Yes you will pick the two end points of each (snap to the")
  (princ "\n  survey points); a dashed line marks each declared wall.")
  (initget "Yes No")
  (setq ans      (getkword "\n  Any straight lines? [Yes/No] <No>: ")
        rawwalls nil)
  (if (= ans "Yes")
    (progn
      (setq go T)
      (while go
        (setq pf-phase "picking a straight wall"
              wp1      (getpoint "\n  First end of the straight wall: "))
        (if wp1
          (progn
            (setq wp2 (getpoint wp1 "\n  Second end: "))
            (if wp2
              (progn
                (setq wp1 (cal:2d wp1) wp2 (cal:2d wp2))
                ;; the dashed marker is scaffolding: it confirms what
                ;; you declared, and goes when the command ends
                (pf:temp-add (pf:tag-mine (pf:draw-wall-marker wp1 wp2)))
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
                       *PF-WALL-LAYER*
                       " clear themselves when the command finishes.")))))

  ;; -- step 5: any sharp corners to declare? ------------------------
  ;; The fitter finds obvious corners itself (turns over
  ;; *PF-CORNER-ANG*), but a gentler one still reads as a corner on
  ;; site.  A declared point is exempt from the tangency rule: the fit
  ;; breaks there instead of rounding it off.
  (setq pf-phase "asking about sharp corners")
  (princ "\n\n  Step 5 of 7 - are there any sharp corners the fit must not round off?")
  (princ "\n  Obvious ones are found automatically; declare the gentler ones here.")
  (princ "\n  If Yes you will pick each corner point (snap to the survey points).")
  (initget "Yes No")
  (setq ans     (getkword "\n  Any sharp corners? [Yes/No] <No>: ")
        rawcnrs nil)
  (if (= ans "Yes")
    (progn
      (setq go T)
      (while go
        (setq pf-phase "picking a sharp corner"
              wp1      (getpoint "\n  Corner point (Enter when done): "))
        (if wp1
          (progn
            (setq wp1     (cal:2d wp1)
                  rawcnrs (cons wp1 rawcnrs))
            (pf:temp-add (pf:tag-mine (pf:draw-corner-marker wp1))))
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
  (setq pf-phase "asking about held points")
  (princ "\n\n  Step 6 of 7 - any points that must be held ABSOLUTELY?")
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
        (setq pf-phase "picking a held point"
              wp1      (getpoint "\n  Point to hold exactly (Enter when done): "))
        (if wp1
          (progn
            (setq wp1      (cal:2d wp1)
                  rawholds (cons wp1 rawholds))
            (pf:temp-add (pf:tag-mine (pf:draw-hold-marker wp1))))
          (setq go nil)))
      (setq rawholds (reverse rawholds))
      (if rawholds
        (princ (strcat "\n  " (itoa (length rawholds))
                       " held point(s) noted - the markers clear"
                       " themselves when the command finishes.")))))

  ;; -- step 7: the selection ----------------------------------------
  (princ "\n\n  Step 7 of 7 - select the survey points (POINTS layer or ab_pt")
  (princ "\n  blocks) and, if you have one, the POOL perimeter or ordering sketch.")
  (princ "\n  Select objects: ")
  (setq pf-phase "waiting for the selection")
  ;; only entity types this command can actually read, so a sloppy
  ;; crossing window over dimensions, hatches or text is harmless.
  ;; SPLINE and ELLIPSE are let in ON PURPOSE - not to fit them, but
  ;; so the classifier below can name them in a useful message.
  (setq ss (ssget '((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE"))))
  (if (null ss)
    (princ "\nNothing usable selected (points, and optionally POOL lines/arcs/polylines).")
    (progn
      ;; -- sort the selection into perimeter segments and points -----
      (setq pf-phase "reading the selected entities")
      (setq segs nil pts nil i 0 nunsup 0 nocs 0
            npt 0 pf-ptnames nil)
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
                (= (strcase (cdr (assoc 2 ed))) (strcase *PF-POINT-BLOCK*)))
           (pf:add-point (cal:2d (cdr (assoc 10 ed)))
                         (pf:block-number en)))
          ;; curve types we cannot fit, sitting on the POOL layer: count
          ;; them so the user gets told what to do, instead of a
          ;; mystifying "the perimeter does not close" later on
          ((and (= lay (strcase *PF-POOL-LAYER*))
                (member typ '("SPLINE" "ELLIPSE")))
           (setq nunsup (1+ nunsup)))
          ;; ABHD's own pool-bottom geometry lives on the POOL layer
          ;; too (stamped) - never read it back as a guide
          ((and (= lay (strcase *PF-POOL-LAYER*))
                (assoc -3 (entget en '("ABHD"))))
           nil)
          ;; perimeter / ordering sketch on the POOL layer
          ((= lay (strcase *PF-POOL-LAYER*))
           (setq segs (append segs (pf:ent-segs en))))
          ;; plain POINT entities on the POINTS layer
          ((and (= lay (strcase *PF-POINT-LAYER*)) (= typ "POINT"))
           (pf:add-point (cal:2d (cdr (assoc 10 ed))) nil))
          ;; any other block dropped on the POINTS layer -> a point too
          ((and (= typ "INSERT") (= lay (strcase *PF-POINT-LAYER*)))
           (pf:add-point (cal:2d (cdr (assoc 10 ed)))
                         (pf:block-number en)))))
      (if (> nunsup 0)
        (princ (strcat "\nABHD: warning - " (itoa nunsup)
                       " SPLINE/ELLIPSE object(s) on layer "
                       *PF-POOL-LAYER*
                       " were ignored (only lines, arcs, circles and"
                       " polylines can be read - explode or convert"
                       " them first).")))
      (if (> nocs 0)
        (princ (strcat "\nABHD: warning - " (itoa nocs)
                       " selected object(s) are not drawn in the world"
                       " plane; the fit is flat (XY) and may be wrong."
                       "  Set UCS to World and flatten them first.")))
      ;; the miss allowance: this share of the points (the answer to
      ;; step 2, rounded UP to a whole point) may sit off the result
      ;; by up to TOL
      (setq dpts  (if pts (cal:dedupe pts *PF-EXACT-EPS*))
            allow (cal:ceil (* (pf:misspct) (length dpts))))
      ;; snap the declared straight-wall ends onto actual survey
      ;; points - arc and wall endpoints always sit ON points
      (setq pf-walls nil)
      (foreach w rawwalls
        (setq w1 (pf:nearest (car w) dpts)
              w2 (pf:nearest (cadr w) dpts))
        (cond
          ((or (null w1) (null w2)) nil)
          ((< (cal:dist w1 w2) *PF-EXACT-EPS*)
           (princ "\n  (both ends of a declared wall landed on the same survey point - that wall is ignored)"))
          (T
           (if (or (> (cal:dist (car w) w1) (* 3.0 tol))
                   (> (cal:dist (cadr w) w2) (* 3.0 tol)))
             (princ "\n  (a declared wall end was picked well away from any survey point - snapped to the nearest one)"))
           (setq pf-walls (cons (list w1 w2) pf-walls)))))
      (setq pf-walls (reverse pf-walls))
      ;; declared corners snap onto survey points the same way
      (setq pf-corners nil)
      (foreach w rawcnrs
        (setq w1 (pf:nearest w dpts))
        (if w1
          (progn
            (if (> (cal:dist w w1) (* 3.0 tol))
              (princ "\n  (a declared corner was picked well away from any survey point - snapped to the nearest one)"))
            (setq pf-corners (cons w1 pf-corners)))))
      (setq pf-corners (reverse pf-corners))
      ;; held points snap onto survey points the same way; duplicates
      ;; collapse to one
      (setq pf-holds nil)
      (foreach w rawholds
        (setq w1 (pf:nearest w dpts))
        (if w1
          (progn
            (if (> (cal:dist w w1) (* 3.0 tol))
              (princ "\n  (a held point was picked well away from any survey point - snapped to the nearest one)"))
            (if (not (pf:memb w1 pf-holds))
              (setq pf-holds (cons w1 pf-holds))))))
      (setq pf-holds (reverse pf-holds))
      (if (> (length dpts) 150)
        (princ (strcat "\nABHD: " (itoa (length dpts))
                       " points - ordering and fitting will take a"
                       " little while, please wait...")))
      (cond
        ((null pts)
         (princ (strcat "\nNo survey points found (looked for POINT entities on layer "
                        *PF-POINT-LAYER* " and \"" *PF-POINT-BLOCK*
                        "\" block insertions).")))
        ((and (null segs) (< (length dpts) 3))
         (princ "\nPoints-only mode needs at least 3 distinct points."))
        (T
         ;; work out the mode, then hand all three modes to the same
         ;; compare-and-choose step
         (setq tour nil loop nil ok T)
         (cond
           ((null segs)
            ;; ---- POINTS-ONLY: order the points ourselves ----------
            (princ "\nNo POOL geometry selected - ordering the points automatically.")
            (setq pf-phase "ordering the points"
                  tour     (pf:order-points dpts)))
           ((null (setq loop (pf:chain segs)))
            (setq ok nil))                     ; pf:chain said why
           ((not (pf:has-arcs loop))
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
                (setq pf-phase "following the sketch order"
                      tour     (pf:loop-order loop dpts)))))
           (T
            (princ "\nUsing the drawn POOL perimeter as the guide.")
            (if pf-walls
              (princ (strcat "\n  (declared straight walls only steer"
                             " the points-built fit; here your drawn"
                             " straight segments are already kept)")))
            (if pf-holds
              (princ (strcat "\n  (held points only bind the"
                             " points-built fit; the drawn shape wins"
                             " here - the report flags any held point"
                             " the kept fit missed)")))))
         (if ok
           (progn
             (setq again T)
             (while again
               (setq again nil)
               (if (eq 'REDO (pf:compare tour loop pts dpts tol allow))
                 (progn
                   ;; -- redo: maybe omit points, then re-ask the
                   ;; numbers and draw a fresh trio -----------------
                   (setq pf-phase "picking points to omit"
                         omits    nil)
                   (princ "\n\nRedoing the fit.  Any points to leave out this time?")
                   (princ "\n  Pick each one (Enter for none) - mis-shots, duplicates, or")
                   (princ "\n  anything the line should not chase; each gets a dashed ring.")
                   (if pf-omitted
                     (princ (strcat "\n  " (itoa (length pf-omitted))
                                    " point(s) are already out -"
                                    " picking one of those puts it"
                                    " BACK IN.")))
                   (while (setq wp1 (getpoint
                                      "\n  Point to omit - or a ringed one to restore (Enter when done): "))
                     (setq wp1 (cal:2d wp1)
                           w1  (pf:nearest wp1 dpts)
                           w2  (pf:nearest wp1 (mapcar 'car pf-omitted)))
                     (cond
                       ;; nearer to an already-omitted point: this
                       ;; click un-omits it - the saved entries (its
                       ;; duplicates too) rejoin the fit, its ring goes
                       ((and w2 (or (null w1)
                                    (<= (cal:dist wp1 w2)
                                        (cal:dist wp1 w1))))
                        (setq ent        (assoc w2 pf-omitted)
                              pts        (append pts (cadr ent))
                              dpts       (cal:dedupe pts *PF-EXACT-EPS*)
                              pf-omitted (pf:remove ent pf-omitted)
                              omits      (pf:remove w2 omits))
                        (if (and (caddr ent) (entget (caddr ent)))
                          (progn
                            (pf:temp-drop (caddr ent))
                            (entdel (caddr ent))))
                        (princ (strcat "  - Pt." (pf:pt-name w2)
                                       " back in")))
                       ;; otherwise omit: pull it - and its duplicates
                       ;; - out of the fit, the stats and the miss
                       ;; allowance alike, and remember how to undo it
                       (w1
                        (setq pts2 nil ent nil)
                        (foreach w pts
                          (if (< (cal:dist w w1) *PF-EXACT-EPS*)
                            (setq ent (cons w ent))
                            (setq pts2 (cons w pts2))))
                        (setq pts  (reverse pts2)
                              dpts (cal:dedupe pts *PF-EXACT-EPS*)
                              ring (pf:temp-add (pf:tag-mine
                                     (pf:draw-corner-marker w1)))
                              pf-omitted (cons (list w1 ent ring)
                                               pf-omitted)
                              omits      (cons w1 omits))
                        (princ (strcat "  - omitting Pt."
                                       (pf:pt-name w1))))))
                   (if omits
                     (progn
                       ;; declared walls and corners anchored on a
                       ;; point omitted this round make no sense any
                       ;; more (a restored point keeps nothing - the
                       ;; wall went when it went out)
                       (setq pts2 nil)
                       (foreach w pf-walls
                         (if (not (or (pf:memb (car w) omits)
                                      (pf:memb (cadr w) omits)))
                           (setq pts2 (cons w pts2))))
                       (if (< (length pts2) (length pf-walls))
                         (princ "\n  (a declared wall lost an end and was dropped)"))
                       (setq pf-walls (reverse pts2)
                             pts2     nil)
                       (foreach w pf-corners
                         (if (not (pf:memb w omits))
                           (setq pts2 (cons w pts2))))
                       (setq pf-corners (reverse pts2)
                             pts2       nil)
                       ;; a held point that was just omitted is out of
                       ;; the fit entirely - nothing left to hold
                       (foreach w pf-holds
                         (if (not (pf:memb w omits))
                           (setq pts2 (cons w pts2))))
                       (if (< (length pts2) (length pf-holds))
                         (princ "\n  (an omitted point was held - its hold went with it)"))
                       (setq pf-holds (reverse pts2))))
                   (if pf-omitted
                     (princ (strcat "\n  " (itoa (length pf-omitted))
                                    " point(s) omitted in total - "
                                    (itoa (length dpts))
                                    " in the fit.")))
                   (if (< (length dpts) 3)
                     (princ "\nToo few points remain for a fit - nothing redone.")
                     (progn
                       ;; walls and corners may change for the retry
                       (princ "\n\n  Straight walls and sharp corners can change too -")
                       (princ "\n  Enter keeps each list as it is.")
                       (setq pf-phase "editing straight walls")
                       (pf:edit-walls dpts)
                       (setq pf-phase "editing sharp corners")
                       (pf:edit-corners dpts)
                       (setq pf-phase "editing held points")
                       (pf:edit-holds dpts)
                       (princ "\n\n  New settings - Enter keeps each one as it is.")
                       (setq pf-phase "reading the tolerance"
                             tol      (pf:ask-tol))
                       (setq pf-phase "reading the miss percentage"
                             pf-miss-pct (pf:ask-pct pf-miss-pct))
                       (setq pf-phase "reading the curve limit")
                       (pf:ask-cap)
                       (setq allow (cal:ceil (* (pf:misspct)
                                               (length dpts))))
                       ;; the point order must forget the omitted ones
                       (cond
                         ((null loop)
                          (setq pf-phase "ordering the points"
                                tour     (pf:order-points dpts)))
                         ((not (pf:has-arcs loop))
                          (setq tour (pf:loop-order loop dpts))))
                       (setq again T))))))))))))
  ;; sweep the dashed wall markers and any candidate the user did not
  ;; keep - the command tidies up after itself
  (pf:temp-clear)
  (setq *error* pf-old-err)   ; restore the previous error handler
  (setq abhd:*nobottom* nil)  ; cover mode lasts one run only
  (princ))

;; ABHD for a cover sheet: the same fit, with the pool-bottom question
;; answered No before it is asked.  A cover records the perimeter and
;; nothing below it, so the breaks, the hopper offsets and the slope
;; lines are work the sheet has no room for.
;;
;; A command of its own rather than a mode, so that a button runs
;; exactly the command named on it; the flag is cleared by c:ABHD on
;; both its exits, so it cannot leak into the next run.
(defun c:ABHDCOVER ()
  (setq abhd:*nobottom* t)
  (princ "\nABHDCOVER: cover sheet - the pool bottom will be skipped.")
  (c:ABHD)
  (princ))

;; ---- ADAB: the pool bottom on its own --------------------------------
;; The end of the ABHD flow as a command of its own: select an
;; existing perimeter - one closed polyline, or the exploded
;; lines/arcs that form one - and go straight to the breaks, the
;; hopper offsets and the slope lines.  The survey points do not have
;; to be selected: with none in the selection, every ab_pt block and
;; POINTS-layer point in the drawing is gathered and only those
;; sitting ON the loop (within *PF-PICKUP-EPS*) are used, so stray
;; depth shots and deck points stay out of it.  Points that ARE
;; selected are trimmed by the same rule.  For when the perimeter was
;; fitted (or drawn) some other day and only the floor is needed.
(defun c:ADAB ( / ss i en ed typ ext lay segs pts dpts loop nocs nskip
                    nall npt stale pf-temp pf-ptnames pf-dim-warned
                    *error* pf-old-err pf-phase)
  (setq pf-temp   nil
        pf-old-err *error*
        *error*
          (lambda (m)
            (if (and m (not (wcmatch (strcase m)
                     "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
              (princ (strcat "\nADAB stopped while "
                             (if pf-phase pf-phase "starting up")
                             " -- " m)))
            (pf:temp-clear)
            (setq *error* pf-old-err)
            (princ)))
  ;; sweep leftovers from a run interrupted before it could tidy up
  (setq stale (pf:purge-mine *PF-WALL-LAYER*))
  (if (> stale 0)
    (princ (strcat "\nADAB: cleared " (itoa stale)
                   " leftover marker(s) from layer " *PF-WALL-LAYER*
                   ".")))
  (princ "\n\nADAB - draw the pool bottom over an existing perimeter.")
  (princ "\n\n  Select the pool perimeter - one closed polyline, or its exploded")
  (princ "\n  lines/arcs.  The survey points sitting on it are found by")
  (princ "\n  themselves; select them too only if they live somewhere unusual.")
  (princ "\n  Select objects: ")
  (setq pf-phase "waiting for the selection")
  (setq ss (ssget '((0 . "POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE"))))
  (if (null ss)
    (princ "\nNothing usable selected (survey points and the perimeter geometry).")
    (progn
      (setq pf-phase "reading the selected entities")
      (setq segs nil pts nil i 0 nocs 0 nskip 0
            npt 0 pf-ptnames nil)
      (while (< i (sslength ss))
        (setq en  (ssname ss i)
              ed  (entget en)
              typ (cdr (assoc 0 ed))
              lay (strcase (cdr (assoc 8 ed)))
              ext (cdr (assoc 210 ed))
              i   (1+ i))
        (if (and ext (< (abs (caddr ext)) 0.999)) (setq nocs (1+ nocs)))
        (cond
          ;; ab_pt blocks are survey points wherever they sit
          ((and (= typ "INSERT")
                (= (strcase (cdr (assoc 2 ed))) (strcase *PF-POINT-BLOCK*)))
           (pf:add-point (cal:2d (cdr (assoc 10 ed)))
                         (pf:block-number en)))
          ;; a plain POINT counts on any layer here - the selection
          ;; is explicit, so there is no guessing involved
          ((= typ "POINT")
           (pf:add-point (cal:2d (cdr (assoc 10 ed))) nil))
          ;; other blocks only count as points on the points layer
          ((= typ "INSERT")
           (if (= lay (strcase *PF-POINT-LAYER*))
             (pf:add-point (cal:2d (cdr (assoc 10 ed)))
                           (pf:block-number en))))
          ;; ABHD's own scaffolding and results must never be read
          ;; back as perimeter: miss rings, dashed markers, and an
          ;; earlier bottom all live on known layers or carry the
          ;; ABHD stamp
          ((or (= lay (strcase *PF-MISS-LAYER*))
               (= lay (strcase *PF-WALL-LAYER*))
               (= lay (strcase *PF-BOTTOM-LAYER*))
               (assoc -3 (entget en '("ABHD"))))
           (setq nskip (1+ nskip)))
          (T
           (setq segs (append segs (pf:ent-segs en))))))
      (if (> nocs 0)
        (princ (strcat "\nADAB: warning - " (itoa nocs)
                       " selected object(s) are not drawn in the world"
                       " plane; the bottom is built flat (XY) and may"
                       " be wrong.  Set UCS to World and flatten them"
                       " first.")))
      (if (> nskip 0)
        (princ (strcat "\n  (" (itoa nskip)
                       " marker/bottom object(s) in the selection were"
                       " ignored)")))
      (setq dpts (if pts (cal:dedupe pts *PF-EXACT-EPS*)))
      (cond
        ((null segs)
         (princ "\nNo perimeter found in the selection - include the closed polyline or its exploded lines/arcs."))
        ((null (setq loop (pf:chain segs))) nil)   ; pf:chain said why
        (T
         (if (null dpts)
           ;; no points in the selection: the perimeter knows its own.
           ;; Gather every survey point in the drawing and keep the
           ;; ones sitting on the loop.
           (progn
             (setq pf-phase "gathering the perimeter's points"
                   ss (ssget "_X"
                        (list '(-4 . "<OR")
                              '(-4 . "<AND") '(0 . "INSERT")
                              (cons 2 *PF-POINT-BLOCK*) '(-4 . "AND>")
                              '(-4 . "<AND") '(0 . "POINT")
                              (cons 8 *PF-POINT-LAYER*) '(-4 . "AND>")
                              '(-4 . "<AND") '(0 . "INSERT")
                              (cons 8 *PF-POINT-LAYER*) '(-4 . "AND>")
                              '(-4 . "OR>"))))
             (if ss
               (progn
                 (setq i 0)
                 (while (< i (sslength ss))
                   (setq en  (ssname ss i)
                         ed  (entget en)
                         typ (cdr (assoc 0 ed))
                         i   (1+ i))
                   (pf:add-point (cal:2d (cdr (assoc 10 ed)))
                                 (if (= typ "INSERT")
                                   (pf:block-number en))))))
             (setq dpts (if pts (cal:dedupe pts *PF-EXACT-EPS*))
                   dpts (pf:near-loop dpts loop *PF-PICKUP-EPS*))
             (if dpts
               (princ (strcat "\n  " (itoa (length dpts))
                              " survey point(s) sitting on the"
                              " perimeter picked up automatically."))))
           ;; points WERE selected: trim them to the perimeter's own,
           ;; so depth shots and deck points caught by the window do
           ;; not get in the way of the break and waypoint snapping
           (progn
             (setq nall (length dpts)
                   dpts (pf:near-loop dpts loop *PF-PICKUP-EPS*))
             (if (< (length dpts) nall)
               (princ (strcat "\n  (" (itoa (- nall (length dpts)))
                              " selected point(s) well off the"
                              " perimeter were set aside)")))))
         (if (null dpts)
           (princ (strcat "\nNo survey points sit on this perimeter"
                          " (within " (rtos *PF-PICKUP-EPS* 2 1)
                          ") - looked for \"" *PF-POINT-BLOCK*
                          "\" blocks anywhere and points on layer "
                          *PF-POINT-LAYER*
                          ".  Select the points explicitly if they"
                          " live elsewhere."))
           (pf:bottom loop dpts nil))))))
  (pf:temp-clear)
  (setq *error* pf-old-err)
  (princ))

;; ---- TUTORIALABHD ----------------------------------------------------
;; A guided introduction for new users, two ways: Checks lists every
;; rule and safeguard the commands apply, for readers; Demo draws a
;; practice pool and walks it through the whole flow on screen, stage
;; by stage, for lookers - then cleans up after itself.

(defun pf:tut-pause ()
  (getstring "\n\n  --- press Enter to continue ---")
  (princ))

;; The stage caption above the demo, replaced at each stage.
(defun pf:tut-cap (p txt hgt / e)
  (setq e (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity")
                          (cons 8 *PF-OUT-LAYER*) '(62 . 2)
                          '(100 . "AcDbText")
                          (cons 10 (list (car p) (cadr p) 0.0))
                          (cons 40 hgt)
                          (cons 1 txt))))
  (if e (pf:temp-add (pf:tag-mine e)))
  e)

;; The practice survey: a kidney-shaped pool about 30 x 16 ft around
;; CP, drawn as POINTs on the points layer and numbered like ab_pt
;; blocks would be.  Returns the points in walking order.
(defun pf:tut-survey (cp / n i tt r p out)
  (cal:ensure-layer *PF-POINT-LAYER* 7)
  (setq n 44 i 0 out nil)
  (while (< i n)
    (setq tt  (* 2.0 pi (/ (float i) n))
          r   (+ 150.0 (* 45.0 (cos tt)) (* 22.0 (sin (* 2.0 tt)))
                 (* -14.0 (cos (* 3.0 tt))))
          p   (list (+ (car cp) (* r (cos tt) 1.15))
                    (+ (cadr cp) (* r (sin tt) 0.75)))
          i   (1+ i)
          out (cons p out))
    (pf:add-point p nil)
    (pf:temp-add (pf:tag-mine
      (entmakex (list '(0 . "POINT") '(100 . "AcDbEntity")
                      (cons 8 *PF-POINT-LAYER*)
                      '(100 . "AcDbPoint")
                      (cons 10 (list (car p) (cadr p) 0.0)))))))
  (reverse out))

;; The reading tour: every rule and safeguard, in the order the
;; commands apply them.
(defun pf:tut-checks ()
  (princ "\n\nWHAT ABHD NEEDS")
  (princ "\n  * Survey points: ab_pt block inserts (any layer, their number")
  (princ "\n    attribute names them) or POINT entities on layer POINTS.")
  (princ "\n  * Optionally on layer POOL: a drawn perimeter (guided mode) or a")
  (princ "\n    lines-only connect-the-dots sketch (sets the point order).")
  (princ "\n    With neither, the points are ordered automatically.")
  (pf:tut-pause)
  (princ "\nTHE SEVEN QUESTIONS")
  (princ "\n  1. Max distance a point may sit from the line (2 inch ceiling).")
  (princ "\n  2. Percent of points allowed off the line (Enter = 15, rounded")
  (princ "\n     UP to whole points - the slack that buys longer arcs).")
  (princ "\n  3. Curve cap (None = unlimited; binds in every mode).")
  (princ "\n  4. Dead-straight walls: pick both ends, dashed marker, comes out")
  (princ "\n     as a straight LINE no arc may swallow or cross.")
  (princ "\n  5. Sharp corners: pick points where tangency is waived.")
  (princ "\n  6. Held points: pick points the line must pass through EXACTLY -")
  (princ "\n     never fudged, never spent from the miss allowance; tangency")
  (princ "\n     still applies at them (they are not corners).")
  (princ "\n  7. Select the points (and the POOL guide if you have one).")
  (pf:tut-pause)
  (princ "\nWHAT THE FITTER GUARANTEES")
  (princ "\n  * Arc endpoints sit ON survey points; arc middles pass through a")
  (princ "\n    point too (3-point arcs) whenever such an arc holds the span;")
  (princ "\n    floating arcs are a rare last resort.")
  (princ "\n  * Joints meet within 8 degrees of tangent; when nothing fits the")
  (princ "\n    window it stretches 1.25x then 1.5x rather than being dropped.")
  (princ "\n  * Radii snap to whole feet, half feet, then inches - only when")
  (princ "\n    the points allow it; the points always outrank pretty radii.")
  (princ "\n  * Turns over 45 degrees are corners and are never buried inside")
  (princ "\n    an arc; the loop is checked for crossing itself.")
  (pf:tut-pause)
  (princ "\nCHOOSING A FIT")
  (princ "\n  Three candidates draw at once, the two ends of the curves-against-")
  (princ "\n  accuracy trade and the middle: red spends the most curves to get")
  (princ "\n  the error near nothing (it ignores your distance and the curve")
  (princ "\n  cap), yellow is your settings exactly, cyan holds that same")
  (princ "\n  distance with the fewest curves it can.  Each is numbered on")
  (princ "\n  screen with its figures, plus a table: segs, curves, worst off,")
  (princ "\n  avg all, avg off, not held - all measured against the distance")
  (princ "\n  you typed.  Click the one to keep, or type 1/2/3;")
  (princ "\n  All keeps the trio, None erases everything.")
  (princ "\n  The kept fit moves onto the POOL layer in ByLayer colour.")
  (pf:tut-pause)
  (princ "\nWHAT GETS FLAGGED")
  (princ "\n  Points no fit built to your distance can hold are called out")
  (princ "\n  before you choose (the tight fit threads every point it can")
  (princ "\n  reach, so it abstains from that count).  The kept fit rings its")
  (princ "\n  unheld points (4 inch circles on FGStep) and")
  (princ "\n  lists them beside the pool, worst first, by point number.  Only")
  (princ "\n  ABHD's own stamped objects on FGStep are ever replaced.")
  (pf:tut-pause)
  (princ "\nREDO")
  (princ "\n  Redo at the choose prompt refits without leaving the command:")
  (princ "\n  omit points by clicking them (clicking a ringed one restores")
  (princ "\n  it - omissions carry across redos), add/remove straight walls,")
  (princ "\n  sharp corners and held points, then the three numbers are asked")
  (princ "\n  again with Enter keeping each.  Repeat until a fit is kept.")
  (pf:tut-pause)
  (princ "\nTHE POOL BOTTOM")
  (princ "\n  After keeping one fit (or via ADAB over any existing perimeter):")
  (princ "\n  pick the SHALLOW BREAK ends, then the DEEP BREAK ends.  The back")
  (princ "\n  of the hopper is found automatically - the survey point nearest")
  (princ "\n  a ray cast from the deep break's middle, away from the shallow.")
  (princ "\n  Three offsets are asked by point number (type 42 or 3'6 - the")
  (princ "\n  format picks the dim style on the back/waypoint dims: SIDE")
  (princ "\n  DIMENSION for feet-inches, STANDARD INCHES for inches).")
  (pf:tut-pause)
  (princ "\n  The hopper's corners land ON the deep break line, which is drawn")
  (princ "\n  as three lines: DASHED2 stubs wall-to-corner, solid across.  Its")
  (princ "\n  dims form the K/L/M string a foot off the line on the shallow")
  (princ "\n  side.  Each slope line to the shallow break is asked Straight,")
  (princ "\n  Guided (follows the perimeter, easing to nothing), or Points")
  (princ "\n  (pick points with pinned offsets, square off the wall, each")
  (princ "\n  dimensioned).  Offsets draw as few merged arcs, not facets, and")
  (princ "\n  every line and dim lands on the POOL layer.")
  (pf:tut-pause)
  (princ "\nHOUSEKEEPING")
  (princ "\n  ADAB needs only the perimeter selected - the survey points on it")
  (princ "\n  are picked up automatically (strays are set aside).  Scaffolding")
  (princ "\n  - markers, previews, labels - sweeps itself on any exit, ESC")
  (princ "\n  included, and a run interrupted mid-flight is tidied by the next.")
  (princ (strcat "\n  This is ABHD " pf:*version*
                 " - the versioned twin file carries the same name."))
  (princ))

;; The watching tour: draw it, fit it, choose it, floor it, clean up.
(defun pf:tut-demo ( / cp tour dpts allow bb hgt cap v segs ent cand
                       kept d1 d2 s1 s2 sp1 sp2 dp1 dp2 back lines q
                       pts npt pf-ptnames pf-miss-pct pf-walls
                       pf-corners pf-holds pf-dim-warned)
  (setq pf-phase "picking a spot for the demo")
  (princ "\n\n  The demo draws a practice pool about 30 ft wide, walks it")
  (princ "\n  through the whole flow, and cleans up after itself.")
  (setq cp (getpoint "\n  Pick a clear spot for it: "))
  (if (null cp)
    (princ "\n  (no spot picked - tutorial ended, nothing drawn)")
    (progn
      (setq cp   (cal:2d cp)
            npt  0
            tour (pf:tut-survey cp)
            dpts (cal:dedupe pts *PF-EXACT-EPS*)
            bb   (pf:bbox dpts)
            hgt  (/ (- (caddr bb) (car bb)) 24.0)
            allow (cal:ceil (* (pf:misspct) (length dpts))))
      (setq cap (pf:tut-cap (list (car bb) (+ (cadddr bb) hgt))
                  "1. The survey: ab_pt blocks or POINTs on POINTS"
                  hgt))
      (princ "\n\n  1. A surveyor shot these points along the pool edge.")
      (pf:tut-pause)
      ;; the walking order
      (if (and cap (entget cap)) (entdel cap))
      (setq cap (pf:tut-cap (list (car bb) (+ (cadddr bb) hgt))
                  "2. The points are ordered into a loop" hgt)
            ent (pf:temp-add (pf:tag-mine
                  (pf:make-pline
                    (mapcar '(lambda (p) (list p 0.0)) tour)
                    *PF-OUT-LAYER* 8))))
      (princ "\n  2. ABHD orders them into a closed loop (a lines-only sketch")
      (princ "\n     on POOL can dictate this order instead).")
      (pf:tut-pause)
      (if (and ent (entget ent)) (entdel ent))
      ;; the three candidates
      (if (and cap (entget cap)) (entdel cap))
      (setq cap (pf:tut-cap (list (car bb) (+ (cadddr bb) hgt))
                  "3. Three candidates: red tight, yellow asked, cyan few"
                  hgt)
            cand nil)
      (foreach v *PF-COMPARE*
        (setq segs (pf:build tour nil pts dpts 1.0 allow (car v))
              ent  (pf:temp-add (pf:tag-mine
                     (pf:make-pline
                       (mapcar '(lambda (s) (list (car s) (caddr s)))
                               segs)
                       *PF-OUT-LAYER* (cadr v))))
              cand (cons (list segs ent) cand)))
      (setq cand (reverse cand))
      (princ "\n  3. Three fits draw at once - the most curves for the least")
      (princ "\n     error, your settings exactly, and the fewest curves that")
      (princ "\n     still hold your distance - each numbered with its figures,")
      (princ "\n     plus a table at the command line.  Every arc runs point to")
      (princ "\n     point, joints within 8 degrees of tangent, radii on feet")
      (princ "\n     and inches where the points allow.")
      (pf:tut-pause)
      ;; keep the middle one
      (if (and cap (entget cap)) (entdel cap))
      (setq cap (pf:tut-cap (list (car bb) (+ (cadddr bb) hgt))
                  "4. Click one to keep - Redo refits, omits points"
                  hgt))
      (setq q (cadr (car cand)))
      (if (and q (entget q)) (entdel q))
      (setq q (cadr (caddr cand)))
      (if (and q (entget q)) (entdel q))
      (setq kept (car (cadr cand)))
      (pf:set-bylayer (cadr (cadr cand)))
      (princ "\n  4. Click the outline you like (or type its number) - the")
      (princ "\n     rest are swept.  Unheld points would be ringed on FGStep")
      (princ "\n     and listed by number.  Redo refits with new settings,")
      (princ "\n     omitted points, and edited walls or corners.")
      (pf:tut-pause)
      ;; the bottom
      (if (and cap (entget cap)) (entdel cap))
      (setq cap (pf:tut-cap (list (car bb) (+ (cadddr bb) hgt))
                  "5. The bottom: breaks, hopper, K/L/M dims, slopes"
                  hgt))
      (setq d1  (nth 4 tour)  d2 (nth 40 tour)
            s1  (nth 18 tour) s2 (nth 26 tour)
            sp1 (pf:curve-near s1 kept) sp2 (pf:curve-near s2 kept)
            dp1 (pf:curve-near d1 kept) dp2 (pf:curve-near d2 kept)
            back (pf:hopper-back dp1 dp2 sp1 sp2 dpts))
      (cal:ensure-layer *PF-POOL-LAYER* 4)
      (setq lines (list (pf:temp-add (pf:tag-mine
                          (pf:make-line sp1 sp2 nil nil)))
                        (pf:temp-add (pf:tag-mine
                          (pf:make-line dp1 dp2 nil nil)))))
      (setq q (entlast))
      (pf:bottom-draw kept sp1 sp2 dp1 dp2 back 12.0 12.0 18.0 nil
                      lines (list T nil))
      ;; bottom-draw promotes its output out of the scaffolding
      ;; registry; a tutorial must still clean it, so re-register
      ;; everything it just made
      (while (setq q (entnext q)) (pf:temp-add q))
      (princ "\n\n  5. ADAB (or the offer after keeping a fit) added the")
      (princ "\n     breaks, found the back point by itself, pulled the")
      (princ "\n     hopper in at your three offsets (asked by point number),")
      (princ "\n     dimensioned them a foot off the deep break on the")
      (princ "\n     shallow side, and ran one")
      (princ "\n     slope guided along the curve, the other straight.")
      (pf:tut-pause)
      (if (and cap (entget cap)) (entdel cap))
      (princ "\n\n  That is the whole flow.  TUTORIALABHD Checks lists every")
      (princ "\n  rule; ABHD runs it on your survey; ADAB does just the")
      (princ "\n  bottom over any perimeter.")
      (initget "Yes No")
      (if (= "Yes" (getkword
                     "\n  Keep the demo drawing to poke at? [Yes/No] <No>: "))
        (progn
          (setq pf-temp nil)
          (princ "\n  Kept - erase it whenever; every piece is stamped ABHD."))
        (princ "\n  Swept - the drawing is as it was.")))))

(defun c:TUTORIALABHD ( / mode pf-temp pf-phase *error* pf-old-err)
  (setq pf-temp   nil
        pf-old-err *error*
        *error*
          (lambda (m)
            (if (and m (not (wcmatch (strcase m)
                     "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
              (princ (strcat "\nTUTORIALABHD stopped -- " m)))
            (pf:temp-clear)
            (setq *error* pf-old-err)
            (princ)))
  (princ (strcat "\n\nTUTORIALABHD - how the ABHD pool fitter works ("
                 pf:*version* ")."))
  (initget "Checks Demo")
  (setq mode (getkword
               "\n  Read the [Checks] it applies, or watch a drawn [Demo]? <Demo>: "))
  (if (= mode "Checks")
    (pf:tut-checks)
    (pf:tut-demo))
  (pf:temp-clear)
  (setq *error* pf-old-err)
  (princ))

;; The same tutorial under the bottom command's name, for whoever
;; goes looking for it there.
(defun c:TUTORIALADAB () (c:TUTORIALABHD))

(princ (strcat "\nABHD " pf:*version*
               " loaded.  ABHD fits the pool perimeter through its"
               " points;"))
(princ "\nADAB draws the pool bottom over an existing perimeter;")
(princ "\nTUTORIALABHD (or TUTORIALADAB) walks new users through everything.")
(princ)
