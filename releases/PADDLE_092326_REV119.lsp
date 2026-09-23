;;; ===================================================================
;;; PADDLE.lsp
;;;
;;; Scans the perimeter of a drawing for concave features that require
;;; pads, and inserts 36" x 36" pad blocks ("Pad36x36") centered on
;;; the affected areas, always parallel to the X/Y axes.
;;;
;;; Pad specification:
;;;   * Any CONCAVE arc / fillet with a radius of 4'-0" (48") or less
;;;     -- all the way down to sharp 90-degree inside corners --
;;;     requires pads along the affected arc.
;;;   * Any CONCAVE intersection of straight segments (an inside
;;;     corner) requires a pad centered on the corner.
;;;   * Semi-straight geometry is left alone, and a corner is judged
;;;     harder than a curve: a connection point counts as an inside
;;;     corner only once it bends more than 30 degrees away from
;;;     straight, and an arc is a feature only once its total bend is
;;;     more than 10 degrees.  Shallow drafting kinks and segmented
;;;     walls are not corners.
;;;   * Convex features and concave arcs larger than 4'-0" radius do
;;;     NOT require pads.
;;;   * Pads never overlap: where features crowd together, a pad on a
;;;     sharp point stays dead-center on that point, and the pads
;;;     along curves do the dodging -- sliding over to sit flush
;;;     alongside, or dropping out when a neighbour covers their spot.
;;;
;;; Accepted perimeter input (generous):
;;;   * a closed LWPOLYLINE or 2D POLYLINE, or
;;;   * loose LINEs / ARCs (or a mix of all of the above) -- PADDLE
;;;     chains touching segments end-to-end into closed loops.
;;;   * geometry that is a closed perimeter EXCEPT for a gap: PADDLE
;;;     recognises the near-miss (the chains and the gaps between them
;;;     go round once and come back), draws an arrow at every open
;;;     joint and offers to close it with a zero-radius FILLET.  Yes
;;;     closes it and the run carries straight on from the perimeter
;;;     that leaves; No leaves the arrow standing to work from.
;;;
;;; Usage:
;;;   Command: PADDLE
;;;   Highlight the perimeter geometry BEFORE typing the command and it
;;;   is taken as-is; otherwise select it at the prompt, or press Enter
;;;   to auto-detect the perimeter (the largest closed loop found in
;;;   the drawing).  LINGUTTER hands its freshly drawn perimeter over
;;;   that way.
;;;
;;;   Command: TUTORIALPADDLE
;;;   Guided tour for new users: lists everything PADDLE checks, then
;;;   optionally draws a labelled sample perimeter and pads it step by
;;;   step so you can watch what happens.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root. It reads
;;; *paddle-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;;
;;; Block resolution order for the chosen pad block:
;;;   1. A block definition already in the drawing.
;;;   2. Imported from "24inpad.dwg" found on the AutoCAD support
;;;      path (ships alongside this lisp -- add its folder to the
;;;      support file search path, or drop the dwg next to the
;;;      current drawing).
;;;   3. As a last resort a plain square block of the right size is
;;;      created so the command always works.
;;;
;;; Assumes drawing units are INCHES (architectural). Adjust the
;;; constants below for other setups.
;;; ===================================================================

(vl-load-com)

;; --------------------------- settings ------------------------------
;; Every knob PADDLE has lives in this block: change a value here,
;; save, and APPLOAD the file again.  Distances are drawing units
;; (inches on an architectural drawing); the two angles are typed in
;; degrees and converted to radians on the same line.  Nothing below
;; this block is meant to be edited to change behaviour.

;; Version banner.  Bump it on every change to this file: it is
;; printed on load and at command start, and tools/release_lisp.py
;; reads it to stamp the dated twin in releases/, so a loaded routine
;; and its release can never disagree.
(setq *paddle-version* "v1.19")

;; --- the pad itself ---
;; Name of the block inserted at every pad spot.  *paddle-blkfile*
;; ships two, Pad36x36 and Pad24x24; if you switch, set
;; *paddle-padsize* to match or the rows along arcs are spaced for
;; the wrong pad.
(setq *paddle-blkname* "Pad36x36")
;; Edge of the pad in drawing units (a 36" x 36" square).  This one
;; number sets the pitch of the flush rows along concave arcs, the
;; collision distance in the dodge pass, the size of the fallback
;; square block, and the wording of every message that quotes it.
(setq *paddle-padsize* 36.0)
;; The dwg the block definitions are imported from when the drawing
;; does not already hold them.  Looked up with findfile, so put its
;; folder on the AutoCAD support path or drop the dwg beside the
;; drawing.  If it cannot be found a plain square block is made.
(setq *paddle-blkfile* "24inpad.dwg")
;; Layer the pads land on.  Created when missing; an existing one is
;; thawed, unlocked and turned on so the result is visible.
(setq *paddle-layer* "PADS")
;; AutoCAD colour index the layer is created with.  An existing layer
;; keeps whatever colour it already has.
(setq *paddle-layer-color* 7)
;; nil = every pad stays parallel to the X/Y axes (the shop standard).
;; T   = each pad rotates to follow its stretch of perimeter instead.
(setq *paddle-align* nil)

;; --- what counts as a feature ---
;; Largest concave radius that still needs pads, 4'-0".  Concave arcs
;; this tight or tighter get a flush row of pads; bigger sweeps get
;; none.
(setq *paddle-maxrad* 48.0)
;; A connection point (line meets line, line meets arc, a polyline
;; vertex) counts as a sharp inside corner only when the perimeter
;; bends MORE than this many degrees away from straight, into the
;; pool, at that one point.  Gentler joints - drafting kinks, a wall
;; drawn as several nearly-collinear pieces, the mouth of a shallow
;; alcove - are semi-straight and get no pad.  Edit the 30.0; the
;; rest of the line converts it to radians.
(setq *paddle-cornertol* (/ (* 30.0 pi) 180.0))
;; A concave arc counts as a feature only when its total bend is MORE
;; than this many degrees; a gentler sweep is a semi-straight line
;; however tight its radius.  Judged separately from corners on
;; purpose: a curve earns its row of pads more easily than a joint
;; earns one pad.  Edit the 10.0.
(setq *paddle-arctol* (/ (* 10.0 pi) 180.0))

;; --- reading the perimeter ---
;; Largest gap between the end of one loose line/arc and the start of
;; the next that still counts as touching when PADDLE chains them into
;; a loop.  Segments shorter than this are dropped as slivers (a
;; doubled polyline vertex, a zero-length line), which is also what
;; keeps a corner drawn with a duplicate vertex from being missed.
(setq *paddle-fuzz* 0.05)

;; --- the gap in a perimeter that nearly closes ---
;; Furthest apart two loose ends may be and still read as a DRAFTING
;; GAP rather than a missing piece of perimeter.  Geometry that chains
;; into a loop except here is one arrow and one question away from
;; being paddable -- PADDLE offers the zero fillet that closes it.
;; Geometry short of a whole wall is not, and gets the plain report it
;; always got.  One pad wide: a hole a pad would fall through is not a
;; gap.  Ends closer together than *paddle-fuzz* are already chained
;; and are not a gap either.
(setq *paddle-gapmax* 36.0)
;; Layer the gap arrow is drawn on, and the colour index it is created
;; with.  A plain ACI number rather than 'auto on purpose: red reads
;; against any background a drafter can set, which is the one thing a
;; mark saying "it is open HERE" has to do.  The arrows are PADDLE's
;; own marks and nobody else's -- every run clears this layer and
;; re-marks whatever is still open, so an arrow does not outlive the
;; gap it pointed at -- so put nothing else on it.
(setq *paddle-gap-layer* "PADDLE-GAP")
(setq *paddle-gap-color* 1)
;; Length of that arrow, tail to tip, in drawing units.  Its head is a
;; third of that long and three times as wide as its shaft, which is
;; what makes it read as an arrow at the zoom the pads are seen at.
(setq *paddle-arrow* 36.0)

;; --- TUTORIALPADDLE ---
;; Layer the tutorial draws its labelled sample perimeter on, and the
;; colour index it is given.  Created if missing, recoloured either
;; way, and left behind unless the demo is erased at the end.
(setq *paddle-demo-layer* "PADDLE-DEMO")
(setq *paddle-demo-color* 3)

;; -------------------------- text helper ----------------------------
;; A length as inches with the mark, 36.0 -> 36" -- every message that
;; quotes the pad size goes through this so *paddle-padsize* is the
;; only place it is written.
(defun paddle--in (n)
  (strcat (rtos n 2 (if (equal n (float (fix n)) 1e-9) 0 2)) "\""))

;; ------------------------ 2D vector helpers ------------------------
(defun paddle--sub (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun paddle--add (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun paddle--scl (v k) (list (* (car v) k) (* (cadr v) k)))
(defun paddle--len (v) (distance '(0.0 0.0) v))
(defun paddle--unit (v / l) (if (> (setq l (paddle--len v)) 1e-12) (paddle--scl v (/ 1.0 l))))
(defun paddle--cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))
(defun paddle--dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun paddle--dir (a) (list (cos a) (sin a))) ; unit vector at angle a
(defun paddle--rot (v a) ; rotate vector v by angle a
  (list (- (* (car v) (cos a)) (* (cadr v) (sin a)))
        (+ (* (car v) (sin a)) (* (cadr v) (cos a)))))
(defun paddle--2d (p) (list (car p) (cadr p)))
(defun paddle--arcpt (cen r ang) (paddle--add cen (paddle--scl (paddle--dir ang) r)))
(defun paddle--cheb (v) (max (abs (car v)) (abs (cadr v)))) ; Chebyshev norm

;; Segment data for vertex A -> B with bulge b (b /= 0):
;; returns (theta radius center start-tangent end-tangent)
;; theta = signed included angle (CCW positive), tangents are angles.
(defun paddle--arcdata (a b blg / theta chord r phi ts cen)
  (setq theta (* 4.0 (atan blg))
        chord (distance a b)
        r     (/ chord (* 2.0 (sin (/ (abs theta) 2.0))))
        phi   (angle a b)
        ts    (- phi (/ theta 2.0))
        cen   (paddle--add a (paddle--scl (paddle--dir (+ ts (if (> blg 0.0) (/ pi 2.0) (/ pi -2.0)))) r)))
  (list theta r cen ts (+ phi (/ theta 2.0))))

;; Signed area of a closed vertex list (shoelace + circular segments).
;; vts = list of (x y bulge), bulge belongs to the segment leaving it.
(defun paddle--area (vts / n i a b blg area theta r seg)
  (setq n (length vts) i 0 area 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq area (+ area (* 0.5 (- (* (car a) (cadr b)) (* (car b) (cadr a))))))
    (if (/= blg 0.0)
        (progn
          (setq seg   (paddle--arcdata a b blg)
                theta (abs (car seg))
                r     (cadr seg))
          (setq area (+ area (* (if (> blg 0.0) 1.0 -1.0)
                                0.5 r r (- theta (sin theta)))))))
    (setq i (1+ i)))
  area)

;; Next pad along an arc: starting from arc-parameter CUR (previous
;; pad center PREV), find the parameter where the pad center is
;; exactly PADSIZE away from PREV in Chebyshev distance -- axis-
;; aligned pads of that size then touch edge-to-edge without ever
;; overlapping. Returns (parameter center), or nil when the rest of
;; the arc is too short for another flush pad.
(defun paddle--next-flush (cen r sa sgn cur sweep prev padsize
                           / ds d p hit lo hi mid)
  (setq ds (/ padsize r 8.0))                ; ~1/8 pad per probe step
  (if (> ds (/ sweep 4.0)) (setq ds (/ sweep 4.0)))
  (setq d cur hit nil)
  (while (and (not hit) (< d (- sweep 1e-9))) ; walk until pads separate
    (setq lo d
          d  (min sweep (+ d ds))
          p  (paddle--arcpt cen r (+ sa (* sgn d))))
    (if (>= (paddle--cheb (paddle--sub p prev)) padsize)
        (setq hit T)))
  (if hit
      (progn ; tighten the crossing between lo and d by bisection
        (setq hi d)
        (repeat 45
          (setq mid (/ (+ lo hi) 2.0)
                p   (paddle--arcpt cen r (+ sa (* sgn mid))))
          (if (>= (paddle--cheb (paddle--sub p prev)) padsize)
              (setq hi mid)
              (setq lo mid)))
        (list hi (paddle--arcpt cen r (+ sa (* sgn hi)))))))

;; Pad centers for one concave arc: the fewest pads that matter most.
;; The first pad is centered on the MIDDLE of the arc (the part that
;; must be covered); further pads march outward toward both ends, each
;; exactly one pad-size on center from the last, so the row touches
;; edge-to-edge and stair-steps into a blocky representation of the
;; curve. Marching stops when the leftover end of the arc is too short
;; for another flush pad -- the extreme ends of the radius are allowed
;; to stay uncovered.
(defun paddle--arc-pads (cen r sa sgn sweep padsize
                         / mid amid pmid fwd bwd cur prev nxt)
  (setq mid  (/ sweep 2.0)
        amid (+ sa (* sgn mid))
        pmid (paddle--arcpt cen r amid))
  ;; march from the middle toward the arc's end...
  (setq cur 0.0 prev pmid fwd nil)
  (while (setq nxt (paddle--next-flush cen r amid sgn cur (- sweep mid) prev padsize))
    (setq cur (car nxt) prev (cadr nxt) fwd (cons prev fwd)))
  ;; ...and from the middle back toward the arc's start
  (setq cur 0.0 prev pmid bwd nil)
  (while (setq nxt (paddle--next-flush cen r amid (- sgn) cur mid prev padsize))
    (setq cur (car nxt) prev (cadr nxt) bwd (cons prev bwd)))
  (append bwd (list pmid) (reverse fwd)))

;; Direction (unit vector) of travel at the START / END of segment a->b.
(defun paddle--tan-start (a b blg)
  (if (= blg 0.0)
      (paddle--unit (paddle--sub b a))
      (paddle--dir (cadddr (paddle--arcdata a b blg)))))
(defun paddle--tan-end (a b blg)
  (if (= blg 0.0)
      (paddle--unit (paddle--sub b a))
      (paddle--dir (last (paddle--arcdata a b blg)))))

;; --------------------- entities -> segments ------------------------
;; A segment is (p1 p2 bulge) with 2D points.

;; LWPOLYLINE -> (closed-flag . vts)
(defun paddle--lwverts (ent / ed out grp)
  (setq ed (entget ent))
  (foreach grp ed
    (cond
      ((= (car grp) 10)
       (setq out (cons (list (cadr grp) (caddr grp) 0.0) out)))
      ((= (car grp) 42)
       (if out (setq out (cons (list (caar out) (cadr (car out)) (cdr grp)) (cdr out)))))))
  (cons (= 1 (logand 1 (cdr (assoc 70 ed)))) (reverse out)))

;; heavy 2D POLYLINE -> (closed-flag . vts), nil for 3D/mesh plines
(defun paddle--plverts (ent / ed flags e ved out p)
  (setq ed (entget ent) flags (cdr (assoc 70 ed)))
  (if (zerop (logand 112 flags)) ; skip 3D polylines / meshes / polyfaces
      (progn
        (setq e (entnext ent))
        (while (and e (= "VERTEX" (cdr (assoc 0 (setq ved (entget e))))))
          (if (zerop (logand 16 (cond ((cdr (assoc 70 ved))) (0)))) ; skip spline frame pts
              (progn
                (setq p (cdr (assoc 10 ved)))
                (setq out (cons (list (car p) (cadr p)
                                      (cond ((cdr (assoc 42 ved))) (0.0)))
                                out))))
          (setq e (entnext e)))
        (cons (= 1 (logand 1 flags)) (reverse out)))))

;; vertex list -> segments (wrapping when closed)
(defun paddle--vts->segs (closed vts / n i segs a b)
  (setq n (length vts) i 0)
  (repeat (if closed n (max 0 (1- n)))
    (setq a (nth i vts)
          b (nth (rem (1+ i) n) vts))
    (setq segs (cons (list (paddle--2d a) (paddle--2d b) (caddr a)) segs))
    (setq i (1+ i)))
  (reverse segs))

;; any supported entity -> list of segments
(defun paddle--ent-segs (ent / ed typ cen r sa ea sweep cv)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (paddle--2d (cdr (assoc 10 ed)))
                 (paddle--2d (cdr (assoc 11 ed))) 0.0)))
    ((= typ "ARC")
     (setq cen   (paddle--2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           sa    (cdr (assoc 50 ed))
           ea    (cdr (assoc 51 ed))
           sweep (- ea sa))
     (if (<= sweep 0.0) (setq sweep (+ sweep pi pi)))
     (list (list (paddle--add cen (paddle--scl (paddle--dir sa) r))
                 (paddle--add cen (paddle--scl (paddle--dir ea) r))
                 (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0)))))) ; tan(sweep/4)
    ((= typ "LWPOLYLINE")
     (setq cv (paddle--lwverts ent))
     (paddle--vts->segs (car cv) (cdr cv)))
    ((= typ "POLYLINE")
     (setq cv (paddle--plverts ent))
     (if cv (paddle--vts->segs (car cv) (cdr cv))))))

;; ------------------- chain segments into loops ---------------------
;; SEG walked the other way: the same geometry, so the bulge changes
;; sign with the direction, and still owned by the same entity.
(defun paddle--revseg (s)
  (list (cadr s) (car s) (- (caddr s)) (cadddr s)))

;; The first segment in SEGS with an end on PT (within *paddle-fuzz*),
;; turned so that it LEAVES pt, and the rest of SEGS without it, in
;; order: (segment rest).  (nil segs) when nothing touches pt.
;;
;; The scan stops at the hit, and only the segments before it are
;; copied: the ones after it are handed back as they stand.  The next
;; segment of a polyline sits at the front of the pool, so most takes
;; look at one segment and copy none -- where rebuilding the whole pool
;; on every step made chaining a sheet quadratic in its segments.
(defun paddle--take (segs pt / found before at s)
  (setq found nil before nil at segs)
  (while (and at (not found))
    (setq s  (car at)
          at (cdr at))
    (cond
      ((<= (distance pt (car s)) *paddle-fuzz*) (setq found s))
      ((<= (distance pt (cadr s)) *paddle-fuzz*) ; reversed
       (setq found (paddle--revseg s)))
      (T (setq before (cons s before)))))
  (if found
      (list found (append (reverse before) at))
      (list nil segs)))

;; Chains touching segments (ends within *paddle-fuzz*) end-to-end.
;; Returns (loops opens): each loop is a vertex list (x y bulge), and
;; each open chain the SEGMENTS it ran out of geometry with, in walk
;; order -- which is what the gap pass below needs, because a segment
;; still knows which entity it came off and a vertex does not.
;;
;; The walk grows at BOTH ends.  Growing forward only splits a
;; perimeter with ONE gap in it into TWO open chains whenever the walk
;; starts in the middle of it: the half ahead of the starting segment
;; runs into the gap, and the half behind it then runs into the
;; segment already taken.  Two chains meeting at a point that is not a
;; gap is not what the drawing says -- there is one loop with one hole
;; in it, and the arrow belongs at the hole.
;;
;; CHAIN holds the seed and what grew at the head, in order; what grew
;; at the tail is kept newest first in GROWN and put on the end once,
;; when the chain is finished -- appending each one as it came copied
;; the whole chain every step.  N counts the segments for the same
;; reason.  And once nothing leaves the tail nothing ever will in this
;; chain: the tail does not move again and the pool only shrinks, so
;; TDEAD skips the scan that is bound to fail on every head step after.
(defun paddle--chain (segs / loops opens chain head tail done found rest
                             grown n tdead)
  ;; drop degenerate slivers
  (setq segs (vl-remove-if
               '(lambda (s) (<= (distance (car s) (cadr s)) *paddle-fuzz*))
               segs))
  (while segs
    (setq chain (list (car segs))
          grown nil
          n     1
          tdead nil
          head  (car (car segs))
          tail  (cadr (car segs))
          segs  (cdr segs)
          done  nil)
    (while (not done)
      (cond
        ;; loop closed back onto its start?
        ((and (> n 1) (<= (distance tail head) *paddle-fuzz*))
         (setq chain (append chain (reverse grown))
               loops (cons (mapcar '(lambda (s) (list (car (car s)) (cadr (car s)) (caddr s)))
                                   chain)
                           loops)
               done  T))
        (T ;; a segment leaving the tail, else one arriving at the head
         (if tdead
             (setq found nil)
             (setq rest  (paddle--take segs tail)
                   found (car rest)
                   rest  (cadr rest)))
         (cond
           (found (setq grown (cons found grown)
                        n     (1+ n)
                        tail  (cadr found)
                        segs  rest))
           (T
            (setq tdead T
                  rest  (paddle--take segs head)
                  found (car rest)
                  rest  (cadr rest))
            (if found
                (setq found (paddle--revseg found) ; turned to arrive at head
                      chain (cons found chain)
                      n     (1+ n)
                      head  (car found)
                      segs  rest)
                (setq opens (cons (append chain (reverse grown)) opens) ; dead end both ways
                      done  T))))))))
  (list (reverse loops) (reverse opens)))

;; ------------------------ feature detection ------------------------
;; Returns a list of pads: (center rotation kind), kind = "corner"/"arc".
;; PADSIZE sets the pad-grid pitch used to cover concave arcs.
(defun paddle--features (vts padsize / s n i a b c blg pads din dout turn
                             seg theta r cen sa sgn sweep)
  (setq s (if (< (paddle--area vts) 0.0) -1 1) ; -1 = clockwise
        n (length vts)
        i 0)
  (repeat n
    (setq a   (nth i vts)                     ; segment i : a -> b
          b   (nth (rem (1+ i) n) vts)
          c   (nth (rem (+ i (1- n)) n) vts)  ; previous vertex
          blg (caddr a))

    ;; --- concave vertex (inside corner) at a, between seg i-1 and i ---
    (setq din  (paddle--tan-end (paddle--2d c) (paddle--2d a) (caddr c))
          dout (paddle--tan-start (paddle--2d a) (paddle--2d b) blg))
    (if (and din dout)
        (progn
          (setq turn (atan (paddle--cross din dout) (paddle--dot din dout)))
          (if (< (* s turn) (- *paddle-cornertol*)) ; turns away from
                                                    ; the interior by
                                                    ; more than 30 deg
              (setq pads (cons (list (paddle--2d a) (angle '(0.0 0.0) din) "corner")
                               pads)))))

    ;; --- concave arc segment with radius <= 4'-0" ---
    (if (and (/= blg 0.0)
             (< (* s blg) 0.0)) ; bulges into the interior
        (progn
          (setq seg   (paddle--arcdata (paddle--2d a) (paddle--2d b) blg)
                theta (car seg)
                r     (cadr seg)
                cen   (caddr seg))
          (if (and (<= r (+ *paddle-maxrad* 1e-6))
                   (> (abs theta) *paddle-arctol*)) ; total bend over 10
                                                   ; deg, else it's a
                                                   ; semi-straight line
              (progn
                (setq sa    (angle cen (paddle--2d a))
                      sgn   (if (> theta 0.0) 1.0 -1.0)
                      sweep (abs theta))
                (foreach ctr (paddle--arc-pads cen r sa sgn sweep padsize)
                  (setq pads (cons (list ctr 0.0 "arc") pads)))))))
    (setq i (1+ i)))
  (reverse pads))

;; Keep pads from colliding where features crowd together, without
;; ever pulling a pad off a sharp point. Corner pads commit first,
;; dead-center on their vertex -- they NEVER slide; one that would
;; overlap an earlier corner pad is dropped (in a notch that tight,
;; the neighbour carries the area). Arc pads then dodge around
;; everything committed: one that would overlap a committed pad slides
;; along one axis to sit flush alongside it instead (pads are PADSIZE
;; x PADSIZE, so flush = exactly PADSIZE on center). An arc pad whose
;; center is already inside a committed pad -- or that cannot find a
;; clear flush spot within half a pad of where it wanted to be -- is
;; dropped: its area is covered by the neighbours it kept hitting.
;; Returns the committed pads, corner pads first.
(defun paddle--dodge (pads padsize / out ctr orig tries done hit d ax sgn)
  (foreach pad pads ; sharp points first: exact centers, never slid
    (if (= (caddr pad) "corner")
        (progn
          (setq hit nil)
          (foreach q out
            (if (and (not hit)
                     (< (paddle--cheb (paddle--sub (car pad) (car q)))
                        (- padsize 1e-6)))
                (setq hit T)))
          (if (not hit) (setq out (cons pad out))))))
  (foreach pad pads ; arc pads dodge around what's committed
    (if (/= (caddr pad) "corner")
        (progn
          (setq ctr   (car pad)
                orig  ctr
                tries 0
                done  nil)
          (while (not done)
            (setq hit nil)
            (foreach q out
              (if (and (not hit)
                       (< (paddle--cheb (paddle--sub ctr (car q)))
                          (- padsize 1e-6)))
                  (setq hit (car q))))
            (cond
              ((not hit) ; clear: commit it here
               (setq out  (cons (list ctr (cadr pad) (caddr pad)) out)
                     done T))
              ((or (< (paddle--cheb (paddle--sub ctr hit)) (/ padsize 2.0))
                   (> tries 6)
                   (> (paddle--cheb (paddle--sub ctr orig)) (/ padsize 2.0)))
               (setq done T)) ; already covered there, or stuck: drop it
              (T ; slide along the more-separated axis until flush
               (setq d   (paddle--sub ctr hit)
                     ax  (if (>= (abs (car d)) (abs (cadr d))) 0 1)
                     sgn (if (< (nth ax d) 0.0) -1.0 1.0))
               (setq ctr (if (= ax 0)
                             (list (+ (car hit) (* sgn padsize)) (cadr ctr))
                             (list (car ctr) (+ (cadr hit) (* sgn padsize)))))
               (setq tries (1+ tries))))))))
  (reverse out))

;; ------------------------- block handling --------------------------
;; Make sure block NAME (a SIZE-inch pad) is defined in the drawing.
;; Returns T.
(defun paddle--ensure-block (doc name size / path oldcmd oldatt tmpname)
  (cond
    ((tblsearch "BLOCK" name) T)
    ;; pull the definitions in from the pad dwg if it can be found --
    ;; inserting the file (under a throwaway name, then cancelling)
    ;; imports every block definition it contains
    ((setq path (findfile *paddle-blkfile*))
     (setq oldcmd (getvar "CMDECHO") oldatt (getvar "ATTREQ")
           tmpname "PADDLE-TEMP-IMPORT")
     (setvar "CMDECHO" 0) (setvar "ATTREQ" 0)
     ;; the restore below must run even if the insert throws: oldcmd
     ;; and oldatt are locals of THIS helper, so c:PADDLE's *error*
     ;; handler cannot put them back and the user would be left with
     ;; no command echo and no attribute prompts
     (vl-catch-all-apply
       '(lambda ()
          (command "_.-INSERT" (strcat tmpname "=" path))
          (command)) '())   ; cancel the insert -- the definitions stay behind
     (setvar "CMDECHO" oldcmd) (setvar "ATTREQ" oldatt)
     (vl-catch-all-apply ; drop the unused throwaway definition
       '(lambda () (vla-Delete (vla-Item (vla-get-Blocks doc) tmpname))) '())
     (if (tblsearch "BLOCK" name)
         T
         (paddle--make-fallback-block name size)))
    (T (paddle--make-fallback-block name size))))

;; Last-resort pad: a plain size x size square block, base at center.
(defun paddle--make-fallback-block (name size / h)
  (setq h (/ size 2.0))
  (entmake (list '(0 . "BLOCK") (cons 2 name)
                 '(10 0.0 0.0 0.0) '(70 . 0)))
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0")
                 '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                 (list 10 (- h) (- h)) (list 10 h (- h))
                 (list 10 h h) (list 10 (- h) h)))
  (entmake '((0 . "ENDBLK")))
  (princ (strcat "\nPADDLE: block \"" name "\" not found; created a plain "
                 (rtos size 2 0) "x" (rtos size 2 0) " square block instead."))
  (tblsearch "BLOCK" name))

;; Offset from the block's insertion point to the center of its extents
;; (measured at 0 rotation), so pads land centered no matter where the
;; block's base point was drawn.
(defun paddle--block-delta (space name / tmp mn mx d)
  (setq tmp (vla-InsertBlock space (vlax-3d-point 0.0 0.0 0.0)
                             name 1.0 1.0 1.0 0.0))
  (vla-GetBoundingBox tmp 'mn 'mx)
  (setq mn (vlax-safearray->list mn)
        mx (vlax-safearray->list mx)
        d  (list (/ (+ (car mn) (car mx)) 2.0)
                 (/ (+ (cadr mn) (cadr mx)) 2.0)))
  (vla-Delete tmp)
  d)

;; Create the pad layer, or - when it already exists - un-freeze,
;; unlock and switch it back on and say so.  Symbol-table (DXF) level,
;; so it needs no document object.
(defun paddle--ensure-layer (name color / rec ed flags col fixed)
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

;; Insert one pad so that its extents are centered on CTR. Pads stay
;; parallel to the X/Y axes unless *paddle-align* is set.
(defun paddle--insert-pad (space name ctr rot delta / ip obj)
  (if (not *paddle-align*) (setq rot 0.0))
  (setq ip  (paddle--sub ctr (paddle--rot delta rot))
        obj (vla-InsertBlock space
              (vlax-3d-point (car ip) (cadr ip) 0.0)
              name 1.0 1.0 1.0 rot))
  (vla-put-Layer obj *paddle-layer*)
  obj)

;; Loops that enclose no area - two lines lying on top of each other,
;; a polyline that doubles straight back on itself - have no inside
;; for anything to be concave toward, and the sign of their zero area
;; is float noise, so the 180-degree reversal at each end could be
;; called an inside corner on the strength of a -0.0.  Returns LOOPS
;; without them.  (Auto-detect never picks one, since it keeps the
;; largest area; an explicit selection would have padded it.)
(defun paddle--solid-loops (loops)
  (vl-remove-if '(lambda (l) (< (abs (paddle--area l)) 1e-6)) loops))

;; ============= a perimeter that nearly closes =======================
;; A drawing says "closed perimeter" long before it is one: two walls
;; that overshoot each other by an inch, a polyline that stops a hair
;; short of its own start, a fillet somebody erased and never redrew.
;; PADDLE chains everything that touches, so what is left over is a set
;; of OPEN chains -- and when those chains and the gaps between them go
;; round once and arrive back where they started, the drawing WAS one
;; closed perimeter with holes punched in it.  This section finds that
;; ring and marks every hole with an arrow; c:PADDLE offers the zero
;; fillet that closes one.

;; The point at U along segment S -- 0 at the start, 1 at the end, the
;; arc followed round when there is one.
(defun paddle--segpt (s u / a b blg seg cen)
  (setq a   (car s)
        b   (cadr s)
        blg (caddr s))
  (if (= blg 0.0)
      (paddle--add a (paddle--scl (paddle--sub b a) u))
      (progn
        (setq seg (paddle--arcdata a b blg)
              cen (caddr seg))
        (paddle--arcpt cen (cadr seg) (+ (angle cen a) (* (car seg) u))))))

;; A 2D point as the 3D one (command ...) and trans want.
(defun paddle--3d (p) (list (car p) (cadr p) 0.0))

;; Where the FILLET pick goes on an end segment, as a fraction of it
;; measured FROM the loose end: nine tenths of the way in, right up by
;; the end that is still attached to the rest of the perimeter.
;;
;; FILLET keeps the side of the pick and moves the other end, so the
;; pick has to land past the point where the two ends cross or it keeps
;; the wrong half.  Two ends that fall short of each other cross
;; outside both segments, and any pick at all is past it.  Two that
;; overshoot cross INSIDE them, as far in as the overshoot is long --
;; so the middle of the segment, the obvious pick, is on the wrong side
;; of the crossing as soon as a wall is run more than half its own
;; length past its neighbour, and FILLET would then trim the perimeter
;; and keep the overshoot.  Nine tenths is wrong only for an end
;; segment that is overshoot nearly end to end, and is still clear of
;; the neighbouring segment when the end belongs to a polyline.  It is
;; a fact about the way FILLET reads a pick rather than a knob, so it
;; is written where it is used and not in the settings block.

;; The two loose ends of open chain number I, each as
;; (point entity pick-point chain end segment): end 0 is the head the
;; walk started from, end 1 the tail it ran out at, and SEGMENT is the
;; one the end sits on, turned so that it always runs FROM the loose
;; end into the chain -- which makes the pick one rule for both, and
;; gives the gap the two lines it has to cross.
(defun paddle--ends (chain i / sf sl)
  (setq sf (car chain)                          ; the head's segment runs
        sl (paddle--revseg (last chain)))       ; in; the tail's is turned
                                                ; round so that it does too
  (list (list (car sf) (cadddr sf) (paddle--segpt sf 0.9) i 0 sf)
        (list (car sl) (cadddr sl) (paddle--segpt sl 0.9) i 1 sl)))

;; One number per loose end, and its index in paddle--endlist's answer,
;; so a pair, a partner and a visited mark are all comparable as
;; numbers rather than as the lists they name.
(defun paddle--endkey (e) (+ (* 2 (nth 3 e)) (nth 4 e)))

;; Every loose end in OPENS, in chain order -- so (nth key ends) finds
;; one again from its key.
(defun paddle--endlist (opens / out i c)
  (setq i 0)
  (foreach c opens
    (setq out (append out (paddle--ends c i))
          i   (1+ i)))
  out)

;; Pair the loose ends off, closest first: a gap is two ends that want
;; to be one point.  Ends further apart than *paddle-gapmax* are left
;; unpaired -- that is a missing wall, not a gap -- ends closer
;; together than *paddle-fuzz* are already chained and are not a gap
;; either, and an end already spoken for cannot be paired twice.  What
;; comes back is a set of disjoint pairs, each (end-a end-b distance).
(defun paddle--pairs (ends / cand taken out at a b ka d p)
  ;; each pair once: B runs over the ends AFTER A.  paddle--endlist
  ;; hands them back in key order, so that is every pair with the
  ;; smaller key first, and each candidate is (d key-a key-b a b).
  (setq at ends)
  (while at
    (setq a  (car at)
          ka (paddle--endkey a))
    (foreach b (cdr at)
      (if (and (> (setq d (distance (car a) (car b))) *paddle-fuzz*)
               (<= d *paddle-gapmax*))
          (setq cand (cons (list d ka (paddle--endkey b) a b) cand))))
    (setq at (cdr at)))
  ;; then take them closest first: sort once, and walk the sorted list
  ;; taking every pair whose two ends are both still free.  A pair
  ;; passed over has an end already spoken for, and a taken end is
  ;; never freed, so the walk takes exactly what rescanning for the
  ;; closest free pair after every pick would.
  ;;
  ;; The sort is on the distance AND the two keys, never the distance
  ;; alone: vl-sort DROPS an element that compares equal to another
  ;; under the predicate it is given -- and two gaps exactly as wide as
  ;; each other is not an oddity here, it is what the two ends of a
  ;; wall left short at both of them look like.  Losing one would leave
  ;; a ring with a gap missing, which is not a ring, so the arrow would
  ;; never be drawn.  No two pairs share both keys, so nothing compares
  ;; equal; and keys taken LARGEST first settle a tie in favour of the
  ;; pair nearest the front of CAND (the last one found above), which
  ;; is the one a closest-first scan of CAND comes to first.
  (foreach p (vl-sort cand
                      '(lambda (x y)
                         (cond ((< (car x) (car y)) T)
                               ((< (car y) (car x)) nil)
                               ((/= (cadr x) (cadr y)) (> (cadr x) (cadr y)))
                               (T (> (caddr x) (caddr y))))))
    (if (and (not (member (cadr p) taken))
             (not (member (caddr p) taken)))
        (setq taken (cons (cadr p) (cons (caddr p) taken))
              out   (cons (list (nth 3 p) (nth 4 p) (car p)) out))))
  (reverse out))

;; The end paired with E, or nil.
(defun paddle--partner (e pairs / k out p)
  (setq k (paddle--endkey e))
  (foreach p pairs
    (cond
      ((= k (paddle--endkey (car p)))  (setq out (cadr p)))
      ((= k (paddle--endkey (cadr p))) (setq out (car p)))))
  out)

;; One gap: the two ends that want to be one point, and how far apart
;; they are -- the number the drafter is told before being asked about
;; it, because an eighth of an inch and a foot are not the same
;; question even though they read the same on screen.
(defun paddle--gap (a b)
  (list a b (distance (car a) (car b))))

;; Walk the ring that leaves chain START by its tail: across the gap
;; waiting there, in at whichever end of whichever chain is on the far
;; side, out at that chain's other end, on across the next gap, and so
;; on until the walk arrives back at the head it set out from.  A walk
;; that does is a RING -- chain, gap, chain, gap, the whole way round.
;; Returns (chains gaps): the chains as (index . the-end-it-came-in-by)
;; in walk order, and the gaps as the (end end) pairs it crossed.  nil
;; when the walk meets a loose end nothing wants, or a chain it has
;; already walked -- a knot, not a ring.
(defun paddle--ring (start ends pairs / here goal chains gaps nxt ci ok done)
  (setq goal   (* 2 start)                   ; the head of START again
        here   (nth (1+ (* 2 start)) ends)   ; leaving START by its tail
        chains (list (cons start 0))
        ok     nil
        done   nil)
  (while (not done)
    (setq nxt (paddle--partner here pairs))
    (cond
      ((null nxt) (setq done T))                 ; a loose end: no ring
      ((= (paddle--endkey nxt) goal)             ; home: the ring closes
       (setq gaps (cons (paddle--gap here nxt) gaps)
             ok   T
             done T))
      ((assoc (nth 3 nxt) chains) (setq done T)) ; a chain walked twice
      (T (setq gaps   (cons (paddle--gap here nxt) gaps)
               ci     (nth 3 nxt)
               chains (cons (cons ci (nth 4 nxt)) chains)
               here   (nth (+ (* 2 ci) (- 1 (nth 4 nxt))) ends)))))
  (if ok (list (reverse chains) (reverse gaps))))

;; The vertex list that ring would be once its gaps are closed: every
;; chain in the order the walk met it, turned round when the walk came
;; in by its tail, and each gap left as the straight closing segment it
;; is about to become.  Enough to measure the area it encloses and find
;; the middle of it, which is all the ring is read for.
(defun paddle--ring-vts (opens chains / out c segs s end)
  (foreach c chains
    (setq segs (nth (car c) opens))
    (if (= (cdr c) 1)
        (setq segs (reverse (mapcar '(lambda (s) (paddle--revseg s)) segs))))
    (foreach s segs
      (setq out (cons (list (car (car s)) (cadr (car s)) (caddr s)) out)))
    ;; and the loose end the chain stops at.  A vertex carries the
    ;; bulge of the segment LEAVING it, and what leaves this one is the
    ;; gap -- straight, so 0.  Leaving the point out instead would
    ;; measure the loop with one segment per chain shortcut away, which
    ;; is most of it when the chain is a wall or two.
    (setq end (cadr (last segs))
          out (cons (list (car end) (cadr end) 0.0) out)))
  (reverse out))

;; The biggest of a set of closed loops by the area it encloses -- what
;; a ring of open chains has to beat before PADDLE reads it as the
;; perimeter rather than as something loose beside one.
(defun paddle--maxarea (loops / best a l)
  (setq best 0.0)
  (foreach l loops
    (if (> (setq a (abs (paddle--area l))) best) (setq best a)))
  best)

;; The ring the open chains make, or the biggest of them when they make
;; more than one -- the same rule auto-detect uses to pick between
;; closed loops.  A ring enclosing no area (chains doubling back on
;; each other) is not one.  Returns (vts chains gaps area).
(defun paddle--best-ring (opens / ends pairs i seen r vts a best bestarea)
  (setq ends     (paddle--endlist opens)
        pairs    (paddle--pairs ends)
        i        0
        bestarea 0.0)
  (repeat (length opens)
    (if (not (member i seen))
        (if (setq r (paddle--ring i ends pairs))
            (progn
              (setq seen (append seen (mapcar '(lambda (c) (car c)) (car r)))
                    vts  (paddle--ring-vts opens (car r))
                    a    (abs (paddle--area vts)))
              (if (> a bestarea)
                  (setq bestarea a
                        best     (list vts (car r) (cadr r) a))))))
    (setq i (1+ i)))
  (if (> bestarea 1e-6) best))

;; Where two straight segments would cross if both ran on for ever --
;; the point a zero fillet joins them at -- or nil when they never do.
(defun paddle--xsect (s1 s2 / a u c v den)
  (setq a   (car s1)
        u   (paddle--sub (cadr s1) a)
        c   (car s2)
        v   (paddle--sub (cadr s2) c)
        den (paddle--cross u v))
  (if (> (abs den) 1e-9)
      (paddle--add a (paddle--scl u (/ (paddle--cross (paddle--sub c a) v)
                                       den)))))

;; Is this gap the two ends of ONE open LWPOLYLINE, straight at both of
;; them?  That is the polyline somebody drew round the pool and never
;; closed, and it is the one gap FILLET must not be asked to close: two
;; picks on one polyline joins those two segments and throws away every
;; segment between them, which here is the whole perimeter.  It is
;; closed by editing the polyline instead (paddle--lwclose), so this
;; asks everything that edit needs to be safe -- one entity, its own
;; two ends, open, straight where it is being joined.
(defun paddle--lwgap-p (g / a b ent cv vts p q)
  (setq a   (car g)
        b   (cadr g)
        ent (cadr a))
  (and (eq ent (cadr b))
       (= "LWPOLYLINE" (cdr (assoc 0 (entget ent))))
       (= 0.0 (caddr (nth 5 a)))               ; straight at both ends
       (= 0.0 (caddr (nth 5 b)))
       (setq cv (paddle--lwverts ent))
       (not (car cv))                          ; and not closed already
       (> (length (cdr cv)) 2)
       (setq vts (cdr cv)
             p   (paddle--2d (car vts))
             q   (paddle--2d (last vts)))
       ;; the polyline's OWN two ends, and nothing else's
       (or (and (<= (distance p (car a)) *paddle-fuzz*)
                (<= (distance q (car b)) *paddle-fuzz*))
           (and (<= (distance p (car b)) *paddle-fuzz*)
                (<= (distance q (car a)) *paddle-fuzz*)))))

;; Close that polyline onto itself at X: its first vertex moves to the
;; crossing, its last one goes (it is the same point now, reached the
;; long way round) and the closed flag goes on.  That is exactly what a
;; zero fillet between its two end segments leaves behind -- both of
;; them run on or trimmed back to where they cross -- done as an edit
;; because FILLET cannot be asked for it.  Every group that is not a
;; vertex is carried over untouched, and so is each vertex's own width
;; and bulge.  Returns T.
(defun paddle--lwclose (ent x / ed g chunks cur head tail)
  (setq ed (entget ent))
  (foreach g ed
    (cond
      ((= (car g) 10)                          ; a vertex, and its own
       (if cur (setq chunks (cons (reverse cur) chunks)))   ; groups
       (setq cur (list g)))                                 ; follow it
      ((and cur (member (car g) '(40 41 42))) (setq cur (cons g cur)))
      (cur (setq tail (cons g tail)))          ; after the last vertex
      (T   (setq head (cons g head)))))        ; before the first
  (if cur (setq chunks (cons (reverse cur) chunks)))
  (setq chunks (reverse chunks)
        head   (reverse head)
        tail   (reverse tail))
  (if (> (length chunks) 2)
      (progn
        (setq chunks (cons (subst (list 10 (car x) (cadr x))
                                  (car (car chunks)) (car chunks))
                           (cdr chunks))
              chunks (reverse (cdr (reverse chunks))) ; the last one goes
              head   (subst (cons 70 (logior 1 (cdr (assoc 70 ed))))
                            (assoc 70 ed) head)
              head   (subst (cons 90 (length chunks)) (assoc 90 ed) head))
        (entmod (append head (apply 'append chunks) tail))
        (entupd ent)
        T)))

;; Where a gap is: halfway between the two ends that want to be one
;; point, which is where the arrow points and where the fillet lands.
(defun paddle--gap-mid (g)
  (paddle--scl (paddle--add (car (car g)) (car (cadr g))) 0.5))

;; The middle of a vertex list, near enough for "which side is the
;; inside of the loop": the arrow flies in from the other one.
(defun paddle--centroid (vts / n)
  (setq n (float (length vts)))
  (list (/ (apply '+ (mapcar '(lambda (v) (car v)) vts)) n)
        (/ (apply '+ (mapcar '(lambda (v) (cadr v)) vts)) n)))

;; The arrow that says IT IS OPEN HERE: one closed polyline, tip on the
;; gap and tail out on the side away from the inside of the loop, so it
;; points at the joint from clear space instead of across the drawing.
;; One entity, so taking it away again when the gap closes is one
;; entdel.  Returns it.
(defun paddle--arrow (tip dir lay / l h w sh nrm head back pts)
  (setq l    *paddle-arrow*
        h    (/ l 3.0)      ; head length
        w    (/ l 8.0)      ; half the head's width
        sh   (/ l 24.0)     ; half the shaft's width
        nrm  (list (- (cadr dir)) (car dir))
        head (paddle--sub tip (paddle--scl dir h))
        back (paddle--sub tip (paddle--scl dir l))
        pts  (list tip
                   (paddle--add head (paddle--scl nrm w))
                   (paddle--add head (paddle--scl nrm sh))
                   (paddle--add back (paddle--scl nrm sh))
                   (paddle--sub back (paddle--scl nrm sh))
                   (paddle--sub head (paddle--scl nrm sh))
                   (paddle--sub head (paddle--scl nrm w))))
  (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                         '(100 . "AcDbPolyline") (cons 90 (length pts)) '(70 . 1))
                   (mapcar '(lambda (p) (list 10 (car p) (cadr p))) pts)))
  (entlast))

;; The space the drafter is drawing in: model space from the Model tab
;; and from inside a layout's viewport, the layout's paper only when it
;; is the paper that is active.  CTAB and the active layout both name
;; the LAYOUT from inside a viewport, so the sweeps below read the
;; sheet and found no perimeter and no arrows there, while the pads
;; were inserted into paper space over a model-space pool.  Every sweep
;; and every insert goes through these two, so they cannot disagree.
;; (vla-get-ModelSpace is reached only inside a viewport; everywhere
;; else the active layout's block already is the right space.)
(defun paddle--tab ()
  (if (= 1 (getvar "CVPORT")) (getvar "CTAB") "Model"))

(defun paddle--space (doc)
  (if (and (= 0 (getvar "TILEMODE")) (/= 1 (getvar "CVPORT")))
      (vla-get-ModelSpace doc)
      (vla-get-Block (vla-get-ActiveLayout doc))))

;; PADDLE's own marks and nobody else's: every run clears the gap layer
;; and re-marks whatever is still open, so an arrow does not outlive
;; the gap it pointed at when the drafter closes one by hand.  Returns
;; how many it took away.
(defun paddle--clear-arrows ( / ss i n)
  (setq n 0)
  (if (setq ss (ssget "_X" (list (cons 8 *paddle-gap-layer*)
                                 (cons 410 (paddle--tab)))))
      (progn
        (setq i 0)
        (repeat (sslength ss)
          (entdel (ssname ss i))
          (setq i (1+ i)
                n (1+ n)))))
  n)

;; Close one gap the way a drafter would: FILLET at radius 0, picked on
;; each end segment up by the end of it that stays (paddle--ends).  Whether it took is read
;; back off the drawing afterwards rather than promised here -- FILLET
;; refuses a pair it cannot join (two ends that are parallel however
;; far they run on, two segments of one entity it will not close), and
;; a tool that says "if you say so" and then LOOKS is a tool that
;; cannot be wrong about it.
(defun paddle--dofillet (g / a b guard)
  (setq a (car g)
        b (cadr g))
  (setvar "FILLETRAD" 0.0)
  (setvar "TRIMMODE" 1)
  (command "_.FILLET"
           (list (cadr a) (trans (paddle--3d (caddr a)) 0 1))
           (list (cadr b) (trans (paddle--3d (caddr b)) 0 1)))
  ;; a FILLET that refused a pick is still asking: cancel it here, where
  ;; the refusal costs one message, rather than letting the next command
  ;; answer it
  (setq guard 0)
  (while (and (> (getvar "CMDACTIVE") 0) (< guard 10))
    (command)
    (setq guard (1+ guard))))

;; Is there still a loose end where this gap was?  A zero fillet that
;; took leaves none -- the two ends are one point now, and one point
;; chains -- and one AutoCAD refused leaves both of them exactly where
;; the arrow is pointing.  Read over *paddle-gapmax* of the gap's
;; middle rather than at the ends themselves, because a fillet MOVES
;; the ends it joins and the points the gap was measured between are
;; not where they are afterwards.
(defun paddle--still-open-p (mid opens / open i c e)
  (setq open nil
        i    0)
  (foreach c opens
    (foreach e (paddle--ends c i)
      (if (<= (distance (car e) mid) *paddle-gapmax*) (setq open T)))
    (setq i (1+ i)))
  open)

;; --------------------------- selection -----------------------------
;; Turns a selection set (or the whole current space when SS is nil) into
;; (loops opens): the closed perimeter loops, as vertex lists, and the
;; open chains that would not close, as segments.  Auto-detect keeps
;; only the largest loop.  Every segment carries the entity it came off
;; so the gap pass can hand two of them to FILLET, and entities on the
;; gap layer are skipped -- those are PADDLE's own arrows, and a run
;; that read its own marks back as geometry would pad them.
(defun paddle--perimeters (ss / auto i en ed segs res loops opens nflat best
                              bestarea a l s)
  (setq auto (not ss))
  (if auto
      (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,POLYLINE,LINE,ARC")
                                 (cons 410 (paddle--tab))))))
  (if ss
      (progn
        (setq i 0)
        (repeat (sslength ss)
          (setq en (ssname ss i)
                i  (1+ i))
          ;; entget is nil for an entity a fillet consumed, and this
          ;; same set is read again after the gap pass has filleted.
          ;; SEGS is collected newest first and turned round once
          ;; below: appending each entity's segments onto the end
          ;; copied everything read so far, once per entity.
          (if (and (setq ed (entget en))
                   (/= (strcase (cdr (assoc 8 ed)))
                       (strcase *paddle-gap-layer*)))
              (foreach s (paddle--ent-segs en)
                (setq segs (cons (append s (list en)) segs)))))
        (setq res   (paddle--chain (reverse segs))
              loops (paddle--solid-loops (car res))
              nflat (- (length (car res)) (length loops))
              opens (cadr res))
        (if (> nflat 0)
            (princ (strcat "\nPADDLE: ignored " (itoa nflat)
                           " closed loop(s) that enclose no area"
                           " (lines doubling back on themselves).")))
        (if auto
            (progn ; keep only the biggest closed loop
              (setq bestarea 0.0)
              (foreach l loops
                (setq a (abs (paddle--area l)))
                (if (> a bestarea) (setq bestarea a best l)))
              (setq loops nil)
              (if best
                  (progn
                    (princ "\nPADDLE: auto-detected the largest closed loop as the perimeter.")
                    (setq loops (list best))))))
        (list loops opens))))

;; ---------------------- a handed-over perimeter ---------------------
;; AUTODIM, LINGUTTER and TYLERDRONESUITE hand PADDLE the perimeter they
;; already hold through this global, not as a pickfirst set.  The
;; pickfirst route needs PICKFIRST at 1, so AUTODIM and the suite
;; switched it on round the call -- and an Esc inside PADDLE runs only
;; PADDLE's own handler, so a drafter who works with it at 0 was left
;; at 1 with nothing said.  LINGUTTER never switched it on, and at 0 its
;; handoff went missing and PADDLE fell back to guessing the perimeter.
;; The global borrows no setting of the drafter's.  It holds (NAME
;; SELECTION), is read only by the command NAME, and is cleared at the
;; read whoever it was for -- and by the handler, for a failure before
;; the read -- so a handoff can never outlive the call it was made for.
(setq *calofin-handoff* nil)

;; The handed-over selection, narrowed to the entity TYPES PADDLE's own
;; (ssget "_I") filter takes and to what is still in the drawing, or
;; nil when nothing was handed to PADDLE.
(defun paddle--handed (types / h ss i e)
  (setq h                 *calofin-handoff*
        *calofin-handoff* nil)
  (if (and (listp h) (= (car h) "PADDLE") (cadr h))
      (progn
        (setq ss (ssadd) i 0)
        (repeat (sslength (cadr h))
          (setq e (ssname (cadr h) i)
                i (1+ i))
          (if (and (entget e) (wcmatch (cdr (assoc 0 (entget e))) types))
              (ssadd e ss)))
        (if (< 0 (sslength ss)) ss))))

;; ---------------------------- command ------------------------------
(defun c:PADDLE (/ *error* doc space mark-open padsize blkname ss res perims
                   opens vts allpads delta ndodge ncorner narc ofrad otrim
                   oecho ring gaps ngap nring nopen marks mk g mid ctr ans
                   xsc tried nyes nclosed nrefused nleft pad)
  (defun *error* (msg)
    ;; the sysvars the gap pass borrows go back FIRST.  A setvar cannot
    ;; throw and everything below it can, and an error raised inside
    ;; *error* abandons every line after it -- the drafter would meet a
    ;; FILLETRAD of 0 in the NEXT command they ran, which does not look
    ;; like this one's doing.
    (if ofrad (setvar "FILLETRAD" ofrad))
    (if otrim (setvar "TRIMMODE" otrim))
    (if oecho (setvar "CMDECHO" oecho))
    (setq *calofin-handoff* nil)     ; one never read goes with the run
    ;; close only the mark THIS run opened: an Esc at the perimeter
    ;; prompt comes before StartUndoMark, and closing a mark nothing
    ;; opened throws -- from inside the handler, where nothing catches
    ;; it.  command-s style: the close itself goes through
    ;; vl-catch-all-apply so it can never be the second error.
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nPADDLE error: " msg)))
    (if lzd:report (lzd:report "PADDLE" *paddle-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "PADDLE" *paddle-version*))

  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        space (paddle--space doc))

  (princ (strcat "\nPADDLE " *paddle-version*))
  (princ (strcat "\nPADDLE - " (paddle--in *paddle-padsize*)
                 " pads at concave perimeter features (R <= "
                 (rtos *paddle-maxrad* 4 0) " and inside corners)."))

  (setq padsize *paddle-padsize*
        blkname *paddle-blkname*)

  ;; A perimeter handed over by another command (paddle--handed above),
  ;; else a pickfirst selection, is taken as-is.  LINGUTTER and AUTODIM
  ;; hand theirs over, and a user who highlighted the outline before
  ;; typing PADDLE meant the same thing.  It matters because auto-detect
  ;; reads the WHOLE drawing for its largest closed loop -- being handed
  ;; the loop beats guessing at it beside a title block border.
  (setq ss (paddle--handed "LWPOLYLINE,POLYLINE,LINE,ARC"))
  (if (null ss)
      (setq ss (ssget "_I" '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC")))))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
      (progn
        (princ "\nSelect perimeter (polylines, lines and arcs) or press Enter to auto-detect: ")
        (setq ss (ssget '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC"))))
        (if lzd:watch (lzd:watch ss) ss)))

  ;; One undo step covers the lot: the marks this run clears, the arrows
  ;; it draws at whatever is open, the gaps the drafter has it close,
  ;; and the pads that follow.  It opens here rather than at the pads
  ;; because the first thing below already writes to the drawing.
  (vla-StartUndoMark doc)
  (setq mark-open T)
  (paddle--clear-arrows)

  (setq res    (paddle--perimeters ss)
        perims (car res)
        opens  (cadr res)
        nring  0)

  ;; --- a perimeter that closes except for a gap ----------------------
  ;; The chains and the gaps between them go round once and come back:
  ;; that is one perimeter with holes in it, not a pile of loose lines.
  ;; It has to enclose more than any loop that DID close, or it is
  ;; something loose lying beside a perimeter PADDLE already has.
  (if (and opens
           (setq ring (paddle--best-ring opens))
           (> (nth 3 ring) (paddle--maxarea perims)))
      (setq gaps  (nth 2 ring)
            ngap  (length gaps)
            nring (length (nth 1 ring)))
      (setq ring nil ngap 0))

  (setq nopen (- (length opens) nring))
  (if (> nopen 0)
      (princ (strcat "\nPADDLE: ignored " (itoa nopen)
                     " open chain(s) that never close back on themselves"
                     " (check for gaps; chaining tolerance is "
                     (rtos *paddle-fuzz* 2 2) ").")))

  (if ring
      (progn
        (paddle--ensure-layer *paddle-gap-layer* *paddle-gap-color*)
        (princ (strcat "\nPADDLE: this reads as one closed perimeter with "
                       (itoa ngap) " gap(s) in it, not as loose geometry."
                       " Arrow(s) drawn on layer \"" *paddle-gap-layer*
                       "\" at the open joint(s)."))
        ;; every arrow goes in BEFORE the first question: a drafter who
        ;; answers No, or presses Esc at one, is left looking at the
        ;; whole picture rather than at the one gap that got as far as
        ;; being asked about
        (setq ctr (paddle--centroid (car ring))) ; the inside of the loop
        (foreach g gaps
          (setq mid   (paddle--gap-mid g)
                marks (cons (list (paddle--arrow
                                    mid
                                    (cond ((paddle--unit (paddle--sub ctr mid)))
                                          ('(0.0 1.0))) ; a gap dead on the
                                                        ; middle: any way in
                                    *paddle-gap-layer*)
                                  mid g)
                            marks)))
        (setq marks (reverse marks)
              oecho (getvar "CMDECHO")
              ofrad (getvar "FILLETRAD")
              otrim (getvar "TRIMMODE")
              nyes  0
              ngap  0)
        (foreach mk marks
          (setq ngap (1+ ngap)
                g    (caddr mk)
                mid  (cadr mk))
          (princ (strcat "\n  gap " (itoa ngap) " of " (itoa (length marks))
                         ": " (paddle--in (caddr g)) " wide, at "
                         (rtos (car mid) 2 2) "," (rtos (cadr mid) 2 2)))
          ;; Both loose ends on ONE entity is the polyline somebody
          ;; drew round the pool and never closed.  FILLET must not be
          ;; asked for that one -- two picks on one polyline joins
          ;; those two segments and throws away every segment between
          ;; them, which here is the perimeter -- so the same join is
          ;; made by editing the polyline: first vertex to the
          ;; crossing, last vertex away, closed flag on, which is what
          ;; the fillet would have left.  Anything else on one entity
          ;; (a heavy POLYLINE, an arc at either end, two ends that
          ;; never cross) is marked and named instead.
          (setq xsc (if (paddle--lwgap-p g)
                        (paddle--xsect (nth 5 (car g)) (nth 5 (cadr g)))))
          (if (and (eq (cadr (car g)) (cadr (cadr g))) (not xsc))
              (progn
                (princ "\n  both ends are on one entity, and PADDLE cannot join it in")
                (princ "\n  place. A zero fillet there is two picks on one polyline,")
                (princ "\n  which cuts away everything between them, so it is not")
                (princ "\n  offered. Close it (PEDIT > Close, or pull the two ends")
                (princ "\n  together) and run PADDLE again."))
              (progn
                (if xsc
                    (princ "\n  both ends are on one polyline: PADDLE joins them at the crossing itself."))
                (initget "Yes No")
                (setq ans (getkword "\nClose the gap the arrow points at with a zero fillet? [Yes/No] <Yes>: "))
                (if lzd:ask (lzd:ask "\nClose the gap the arrow points at with a zero fillet? [Yes/No] <Yes>: " ans) ans)
                (if (null ans) (setq ans "Yes"))
                (if (= ans "Yes")
                    (progn
                      (setvar "CMDECHO" 0)
                      (if xsc
                          (paddle--lwclose (cadr (car g)) xsc)
                          (paddle--dofillet g))
                      (setvar "CMDECHO" oecho)
                      (setq nyes  (1+ nyes)
                            tried (cons (car mk) tried)))))))  ; asked for, and tried
        (setvar "FILLETRAD" ofrad)
        (setvar "TRIMMODE" otrim)
        (setq nclosed 0 nrefused 0 nleft 0)
        ;; read the drawing again: a gap that closed is not there to be
        ;; found any more, and what it closed is a perimeter to pad
        (if (> nyes 0)
            (setq res    (paddle--perimeters ss)
                  perims (car res)
                  opens  (cadr res)))
        (foreach mk marks
          (if (paddle--still-open-p (cadr mk) opens)
              (if (member (car mk) tried)
                  (setq nrefused (1+ nrefused))
                  (setq nleft (1+ nleft)))
              (progn (entdel (car mk)) ; the arrow has nothing left to
                     (setq nclosed (1+ nclosed))))) ; point at
        (if (> nclosed 0)
            (princ (strcat "\nPADDLE: " (itoa nclosed)
                           " gap(s) closed with a zero fillet - carrying on"
                           " with what that leaves.")))
        (if (> nrefused 0)
            (princ (strcat "\nPADDLE: FILLET would not close " (itoa nrefused)
                           " gap(s) - the two ends do not meet even run on."
                           " Their arrow(s) stay.")))
        (if (> nleft 0)
            (princ (strcat "\nPADDLE: " (itoa nleft)
                           " gap(s) left as they are - the arrow(s) mark them."
                           " PADDLE pads the perimeter once it closes.")))))

  (if (not perims)
      (princ "\nPADDLE: no closed perimeter loop found.")
      (progn
        (paddle--ensure-block doc blkname padsize)
        (paddle--ensure-layer *paddle-layer* *paddle-layer-color*)
        (setq delta (paddle--block-delta space blkname))
        (foreach vts perims
          (if (> (length vts) 1)
              (setq allpads (append allpads (paddle--features vts padsize)))))
        (setq ndodge  (length allpads)
              allpads (paddle--dodge allpads padsize)
              ndodge  (- ndodge (length allpads)))
        (setq ncorner 0 narc 0)
        (foreach pad allpads
          (paddle--insert-pad space blkname (car pad) (cadr pad) delta)
          (if (= (caddr pad) "corner") (setq ncorner (1+ ncorner)) (setq narc (1+ narc))))
        (if allpads
            (progn
              (princ (strcat "\nPADDLE: inserted " (itoa (length allpads))
                             " " (paddle--in padsize) " pad(s) on layer \""
                             *paddle-layer* "\" ("
                             (itoa ncorner) " at inside corners, "
                             (itoa narc) " along concave arcs)."))
              (if (> ndodge 0)
                  (princ (strcat "\nPADDLE: " (itoa ndodge)
                                 " overlapping pad(s) merged into their"
                                 " neighbours where features crowd together."))))
            (princ "\nPADDLE: perimeter checked - no concave features need pads."))))
  (vla-EndUndoMark doc)
  (setq mark-open nil)
  (if lzd:end (lzd:end "PADDLE"))
  (princ))

;; --------------------------- tutorial ------------------------------
;; TUTORIALPADDLE walks a new user through what PADDLE checks, then
;; (optionally) draws a sample perimeter containing every kind of
;; feature and pads it step by step.

(defun paddle--pause ()
  ((lambda (v) (if lzd:ask (lzd:ask "\n  [ press ENTER to continue ]" v) v))
    (getstring "\n  [ press ENTER to continue ]"))
  (princ))

;; the sample perimeter: straight walls, a 2-degree kink (ignored),
;; convex corners (ignored), a rectangular slot with two 90-degree
;; inside corners (padded), a concave R4'-0" bite (padded row) and a
;; concave R6'-0" sweep (too big -- no pads)
(defun paddle--demo-pline (base lay / pts absv)
  (setq pts '((0 0 0) (150 3 0) (300 0 0) (300 168 0) (264 168 -1.0)
              (168 168 0) (132 168 0) (132 120 0) (84 120 0) (84 168 0)
              (0 168 0) (0 134 -0.4038) (0 34 0)))
  (setq absv (mapcar '(lambda (v) (list (+ (car base) (car v))
                                        (+ (cadr base) (cadr v))
                                        (caddr v)))
                     pts))
  (entmake (append
             (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                   '(100 . "AcDbPolyline") (cons 90 (length absv)) '(70 . 1))
             (apply 'append
                    (mapcar '(lambda (v) (list (list 10 (car v) (cadr v))
                                               (cons 42 (caddr v))))
                            absv))))
  (entlast))

;; ZOOM Window onto the World box LO-HI.  ZOOM reads its two corners
;; in the UCS and frames the SCREEN, so under a turned UCS the box's
;; own two corners, handed over as they stand, frame a box turned
;; against it and cut the demo's corners off.  All four corners go to
;; the display, are boxed there, and come back as the UCS numbers
;; ZOOM reads.
(defun paddle--zoom-box (lo hi / c q dlo dhi)
  (foreach c (list lo (list (car hi) (cadr lo)) hi (list (car lo) (cadr hi)))
    (setq q   (trans (list (car c) (cadr c) 0.0) 0 2)
          dlo (if dlo (mapcar 'min dlo q) q)
          dhi (if dhi (mapcar 'max dhi q) q)))
  (command "_.ZOOM" "_W" (trans dlo 2 1) (trans dhi 2 1)))

(defun paddle--demo-text (base lay pt str)
  (entmake (list '(0 . "TEXT") (cons 8 lay)
                 (list 10 (+ (car base) (car pt)) (+ (cadr base) (cadr pt)) 0.0)
                 '(40 . 6.0) (cons 1 str)))
  (entlast))

(defun c:TUTORIALPADDLE (/ *error* mark-open doc space base lay ents pl vts
                           feats blk delta pad ncorner narc left)
  ;; the demo draws a layer, a perimeter, labels and pads with pauses
  ;; between -- an Esc at a pause used to leave all of it behind, N
  ;; undos deep, with no handler.  One mark round the whole tour,
  ;; closed on both exits the way c:PADDLE closes its own.
  (defun *error* (msg)
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nTUTORIALPADDLE error: " msg)))
    (if lzd:report (lzd:report "TUTORIALPADDLE" *paddle-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TUTORIALPADDLE" *paddle-version*))
  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        space (paddle--space doc))
  (vla-StartUndoMark doc)
  (setq mark-open T)
  (princ (strcat "\n=== PADDLE TUTORIAL " *paddle-version* " ==="))
  (princ "\nPADDLE looks at the perimeter of a drawing and inserts pad blocks")
  (princ "\nwherever the perimeter caves inward. Everything it checks:")
  (princ "\n")
  (princ "\n 1. THE PERIMETER. Select it, or press ENTER and PADDLE finds the")
  (princ "\n    largest closed loop by itself. A closed polyline is ideal, but")
  (princ "\n    loose lines and arcs work too - touching ends (within ")
  (princ (strcat (rtos *paddle-fuzz* 2 2) "\") are"))
  (princ "\n    chained together automatically.  Ends that ALMOST meet are a")
  (princ (strcat "\n    GAP: up to " (paddle--in *paddle-gapmax*)
                 " apart, and with the rest of the geometry going"))
  (princ "\n    round once and coming back, PADDLE reads it as a perimeter with")
  (princ "\n    a hole in it - draws an arrow at the open joint, offers to close")
  (princ "\n    it with a zero fillet, and pads what that leaves.  Say No and the")
  (princ (strcat "\n    arrow stays on layer \"" *paddle-gap-layer*
                 "\" for you to work from."))
  (princ (strcat "\n 2. INSIDE CORNERS. A connection point that bends more than "
                 (rtos (/ (* *paddle-cornertol* 180.0) pi) 2 0) " degrees"))
  (princ "\n    away from straight gets one pad centered on the corner. Gentler")
  (princ "\n    kinks - semi-straight lines - and all convex (outside) corners")
  (princ "\n    are passed over.")
  (princ (strcat "\n 3. CONCAVE CURVES. A concave radius of " (rtos *paddle-maxrad* 4 0)
                 " or less, bending more"))
  (princ (strcat "\n    than " (rtos (/ (* *paddle-arctol* 180.0) pi) 2 0)
                 " degrees in total, gets a row of pads: the middle of the"))
  (princ "\n    curve is always covered, then pads march flush toward both ends")
  (princ (strcat "\n    (exactly " (paddle--in *paddle-padsize*)
                 " on center, touching, never overlapping) - a blocky"))
  (princ "\n    version of the curve. The extreme ends of the radius may stay")
  (princ "\n    uncovered; that is by design. Bigger concave radii, and curves")
  (princ (strcat "\n    bending " (rtos (/ (* *paddle-arctol* 180.0) pi) 2 0)
                 " degrees or less, need no pads at all."))
  (princ "\n 4. NO COLLISIONS. Where features crowd together, a pad on a sharp")
  (princ "\n    point stays dead-center on that point - it never moves. The pads")
  (princ "\n    along curves do the dodging: they slide over to sit flush")
  (princ "\n    alongside, or drop out when a neighbour already covers their spot.")
  (princ (strcat "\n 5. RESULT. " (paddle--in *paddle-padsize*) " x "
                 (paddle--in *paddle-padsize*) " pads (block " *paddle-blkname*
                 ", imported from"))
  (princ (strcat "\n    " *paddle-blkfile* " if needed), always square to the"
                 " X/Y axes, on layer"))
  (princ (strcat "\n    \"" *paddle-layer* "\", as a single undo step."))
  (paddle--pause)
  (initget "Yes No")
  (if (/= ((lambda (v) (if lzd:ask (lzd:ask "\nDraw a live demonstration in this drawing? [Yes/No] <Yes>: " v) v))
            (getkword "\nDraw a live demonstration in this drawing? [Yes/No] <Yes>: ")) "No")
      (progn
        (setq lay *paddle-demo-layer*)
        ;; vla-Add hands back a layer that is already there untouched,
        ;; lock and all, so a PADDLE-DEMO left locked took the whole demo
        ;; and then refused every erase at the end without a word.  The
        ;; helper thaws, unlocks and switches it on; the colour is still
        ;; put back every run, as it always was
        (paddle--ensure-layer lay *paddle-demo-color*)
        (vla-put-Color (vla-Item (vla-get-Layers doc) lay) *paddle-demo-color*)
        (setq base (getpoint "\nPick a clear spot for the demo <0,0>: "))
        (if lzd:ask (lzd:ask "\nPick a clear spot for the demo <0,0>: " base) base)
        (if (not base) (setq base '(0.0 0.0 0.0)))
        ;; The pick - and Enter's 0,0 - are the drafter's UCS, and the
        ;; demo is entmade, which keeps World: taken raw, a moved UCS
        ;; built the sample somewhere else while the ZOOM framed the
        ;; empty spot that was picked.  From here on BASE is World.
        (setq base (trans base 1 0))
        (setq pl   (paddle--demo-pline base lay)
              ents (list pl))
        (paddle--zoom-box (list (- (car base) 40.0) (- (cadr base) 40.0))
                          (list (+ (car base) 340.0) (+ (cadr base) 210.0)))
        (princ "\nThis sample perimeter (green) has one of everything. Labelling it...")
        (paddle--pause)
        (setq ents (cons (paddle--demo-text base lay '(96 14)
                     "2-deg kink here: 30 deg or less = ignored") ents))
        (setq ents (cons (paddle--demo-text base lay '(140 100)
                     "slot corners bend 90 deg: pad on each") ents))
        (setq ents (cons (paddle--demo-text base lay '(166 108)
                     "concave R4'-0\" (<= R4'-0\"): row of pads") ents))
        (setq ents (cons (paddle--demo-text base lay '(30 84)
                     "concave R6'-0\" (> R4'-0\"): no pads") ents))
        (setq ents (cons (paddle--demo-text base lay '(230 180)
                     "convex corners: never padded") ents))
        (princ "\nRead the labels on the drawing.")
        (paddle--pause)
        ;; run the real PADDLE pipeline on the demo
        (setq vts   (cdr (paddle--lwverts pl))
              feats (paddle--dodge (paddle--features vts *paddle-padsize*)
                                   *paddle-padsize*)
              blk   *paddle-blkname*)
        (paddle--ensure-block doc blk *paddle-padsize*)
        (paddle--ensure-layer *paddle-layer* *paddle-layer-color*)
        (setq delta (paddle--block-delta space blk)
              ncorner 0 narc 0)
        (princ "\nStep 1 - inside corners: one pad centered on each corner of the slot.")
        (foreach pad feats
          (if (= (caddr pad) "corner")
              (progn (paddle--insert-pad space blk (car pad) (cadr pad) delta)
                     (setq ents (cons (entlast) ents) ncorner (1+ ncorner)))))
        (paddle--pause)
        (princ "\nStep 2 - the R4'-0\" curve: first pad centered on the middle of the")
        (princ (strcat "\nradius, the rest flush at " (paddle--in *paddle-padsize*)
                       " on center, stair-stepping the curve."))
        (princ "\nNote the R6'-0\" curve and the kink get nothing.")
        (foreach pad feats
          (if (= (caddr pad) "arc")
              (progn (paddle--insert-pad space blk (car pad) (cadr pad) delta)
                     (setq ents (cons (entlast) ents) narc (1+ narc)))))
        (princ (strcat "\nDone: " (itoa ncorner) " corner pad(s) + " (itoa narc)
                       " pad(s) along the curve, on layer \"" *paddle-layer* "\"."))
        (paddle--pause)
        (initget "Yes No")
        (if (= ((lambda (v) (if lzd:ask (lzd:ask "\nErase the demonstration? [Yes/No] <No>: " v) v))
                 (getkword "\nErase the demonstration? [Yes/No] <No>: ")) "Yes")
            (progn
              ;; the layer can still be locked from the palette while a
              ;; pause waits, and entdel then refuses: say what stayed
              (setq left 0)
              (foreach e ents (if (not (entdel e)) (setq left (1+ left))))
              (if (> left 0)
                (princ (strcat "\n" (itoa left) " demo object(s) on a locked"
                               " layer - NOT erased.")))))))
  (princ "\nEnd of tutorial. Type PADDLE to run it on a real drawing.")
  (vla-EndUndoMark doc)
  (setq mark-open nil)
  (if lzd:end (lzd:end "TUTORIALPADDLE"))
  (princ))

(defun c:PADDLEVER ()
  (princ (strcat "\nPADDLE " *paddle-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nPADDLE " *paddle-version*
                 " loaded. Commands: PADDLE (place pads), TUTORIALPADDLE (guided demo).")))
(princ)
