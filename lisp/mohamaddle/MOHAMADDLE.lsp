;;; ===================================================================
;;; MOHAMADDLE.lsp
;;;
;;; PADDLE's pad placer, with the pad size asked at run time instead of
;;; fixed at the top of the file.  Scans the perimeter of a drawing for
;;; concave features that require pads and inserts pad blocks centered
;;; on the affected areas, always parallel to the X/Y axes -- exactly
;;; PADDLE's rule set, just with a choice of block/size at the start of
;;; the run instead of one baked in.
;;;
;;; Pad specification (identical to PADDLE's):
;;;   * Any CONCAVE arc / fillet with a radius of 4'-6" (54") or less
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
;;;   * Convex features and concave arcs larger than 4'-6" radius do
;;;     NOT require pads.
;;;   * Pads never overlap: where features crowd together, a pad on a
;;;     sharp point stays dead-center on that point, and the pads
;;;     along curves do the dodging -- sliding over to sit flush
;;;     alongside, or dropping out when a neighbour covers their spot.
;;;
;;; Accepted perimeter input (generous):
;;;   * a closed LWPOLYLINE or 2D POLYLINE, or
;;;   * loose LINEs / ARCs (or a mix of all of the above) -- MOHAMADDLE
;;;     chains touching segments end-to-end into closed loops.
;;;
;;; Usage:
;;;   Command: MOHAMADDLE
;;;   First asks which pad size to place (the sizes *mohamaddle-blkfile*
;;;   ships block definitions for).  Highlight the perimeter geometry
;;;   BEFORE typing the command and it is taken as-is; otherwise select
;;;   it at the prompt, or press Enter to auto-detect the perimeter
;;;   (the largest closed loop found in the drawing).
;;;
;;; Versioning: see tools/release_lisp.py at the repo root. It reads
;;; *mohamaddle-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;;
;;; Block resolution order for the chosen pad block:
;;;   1. A block definition already in the drawing.
;;;   2. Imported from "24inpad.dwg" found on the AutoCAD support
;;;      path (ships alongside PADDLE.lsp in lisp/paddle/ -- add that
;;;      folder to the support file search path, or drop the dwg next
;;;      to the current drawing).
;;;   3. As a last resort a plain square block of the right size is
;;;      created so the command always works.
;;;
;;; The perimeter-reading and pad-placement geometry below is PADDLE's
;;; own engine, ported under the mohamaddle-- prefix the way LINGUTTER
;;; ports paddle--ent-segs and friends under lg: (see lisp/paddle/
;;; README.md) -- a second self-contained copy, not a shared library
;;; call, because every lisp/ tool has to load alone. Only the pad-size
;;; question at the top of c:MOHAMADDLE is new.
;;;
;;; Assumes drawing units are INCHES (architectural). Adjust the
;;; constants below for other setups.
;;; ===================================================================

(vl-load-com)

;; --------------------------- tunables -------------------------------
;; Every knob MOHAMADDLE has lives in this block: change a value here,
;; save, and APPLOAD the file again.  Distances are drawing units
;; (inches on an architectural drawing); the two angles are typed in
;; degrees and converted to radians on the same line.  Nothing below
;; this block is meant to be edited to change behaviour.

;; Version banner.  Bump it on every change to this file: it is
;; printed on load and at command start, and tools/release_lisp.py
;; reads it to stamp the dated twin in releases/, so a loaded routine
;; and its release can never disagree.
(setq *mohamaddle-version* "v1.0")

;; --- the pad itself ---
;; Pad sizes MOHAMADDLE offers, in the order shown at the prompt.  Each
;; entry is (KEYWORD BLOCKNAME SIZE-IN-INCHES); *mohamaddle-blkfile*
;; ships block definitions for both.  Add a third entry here to offer
;; a third size -- nothing else about the picker needs to change.
(setq *mohamaddle-sizes*
  '(("24" "Pad24x24" 24.0)
    ("36" "Pad36x36" 36.0)))
;; Which size the prompt defaults to the first time it is asked in a
;; session.  MOHAMADDLE remembers whatever was picked last after that
;; and offers it instead, so this only matters once per drawing session.
(setq *mohamaddle-defaultkw* "36")
;; The dwg the block definitions are imported from when the drawing
;; does not already hold them.  Looked up with findfile, so put its
;; folder on the AutoCAD support path or drop the dwg beside the
;; drawing.  If it cannot be found a plain square block is made.
(setq *mohamaddle-blkfile* "24inpad.dwg")
;; Layer the pads land on.  Created when missing; an existing one is
;; thawed, unlocked and turned on so the result is visible.
(setq *mohamaddle-layer* "PADS")
;; AutoCAD colour index the layer is created with.  An existing layer
;; keeps whatever colour it already has.
(setq *mohamaddle-layer-color* 7)
;; nil = every pad stays parallel to the X/Y axes (the shop standard).
;; T   = each pad rotates to follow its stretch of perimeter instead.
(setq *mohamaddle-align* nil)

;; --- what counts as a feature ---
;; Largest concave radius that still needs pads, 4'-6".  Concave arcs
;; this tight or tighter get a flush row of pads; bigger sweeps get
;; none.  Independent of which pad size was picked -- it is a
;; drafting-standard threshold, not a property of the block.
(setq *mohamaddle-maxrad* 54.0)
;; A connection point (line meets line, line meets arc, a polyline
;; vertex) counts as a sharp inside corner only when the perimeter
;; bends MORE than this many degrees away from straight, into the
;; pool, at that one point.  Gentler joints - drafting kinks, a wall
;; drawn as several nearly-collinear pieces, the mouth of a shallow
;; alcove - are semi-straight and get no pad.  Edit the 30.0; the
;; rest of the line converts it to radians.
(setq *mohamaddle-cornertol* (/ (* 30.0 pi) 180.0))
;; A concave arc counts as a feature only when its total bend is MORE
;; than this many degrees; a gentler sweep is a semi-straight line
;; however tight its radius.  Judged separately from corners on
;; purpose: a curve earns its row of pads more easily than a joint
;; earns one pad.  Edit the 10.0.
(setq *mohamaddle-arctol* (/ (* 10.0 pi) 180.0))

;; --- reading the perimeter ---
;; Largest gap between the end of one loose line/arc and the start of
;; the next that still counts as touching when MOHAMADDLE chains them
;; into a loop.  Segments shorter than this are dropped as slivers (a
;; doubled polyline vertex, a zero-length line), which is also what
;; keeps a corner drawn with a duplicate vertex from being missed.
(setq *mohamaddle-fuzz* 0.05)

;; -------------------------- text helper ------------------------------
;; A length as inches with the mark, 36.0 -> 36" -- every message that
;; quotes a pad size goes through this, whichever size was picked.
(defun mohamaddle--in (n)
  (strcat (rtos n 2 (if (equal n (float (fix n)) 1e-9) 0 2)) "\""))

;; -------------------------- size picker -------------------------------
;; Ask which pad size to place, from *mohamaddle-sizes* above.  This is
;; the FIRST thing MOHAMADDLE asks -- there is nothing in front of it
;; to go back to, so it offers no Back (tools/back_baseline.txt).  The
;; keyword string and the bracket shown are both built off the table,
;; so a third size needs no other edit here.
(defun mohamaddle--asksize (dflt / kws shown v)
  (setq kws (apply 'strcat (mapcar '(lambda (s) (strcat (car s) " "))
                                   *mohamaddle-sizes*)))
  (setq shown (vl-string-translate " " "/" (substr kws 1 (1- (strlen kws)))))
  (initget 0 kws)
  (setq v (getkword (strcat "\nPad size (inches)? [" shown "] <" dflt ">: ")))
  (if lzd:ask (lzd:ask "Pad size (inches)?" v) v)
  (if v v dflt))

;; ------------------------ 2D vector helpers ------------------------
(defun mohamaddle--sub (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun mohamaddle--add (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun mohamaddle--scl (v k) (list (* (car v) k) (* (cadr v) k)))
(defun mohamaddle--len (v) (distance '(0.0 0.0) v))
(defun mohamaddle--unit (v / l) (if (> (setq l (mohamaddle--len v)) 1e-12) (mohamaddle--scl v (/ 1.0 l))))
(defun mohamaddle--cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))
(defun mohamaddle--dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun mohamaddle--dir (a) (list (cos a) (sin a))) ; unit vector at angle a
(defun mohamaddle--rot (v a) ; rotate vector v by angle a
  (list (- (* (car v) (cos a)) (* (cadr v) (sin a)))
        (+ (* (car v) (sin a)) (* (cadr v) (cos a)))))
(defun mohamaddle--2d (p) (list (car p) (cadr p)))
(defun mohamaddle--arcpt (cen r ang) (mohamaddle--add cen (mohamaddle--scl (mohamaddle--dir ang) r)))
(defun mohamaddle--cheb (v) (max (abs (car v)) (abs (cadr v)))) ; Chebyshev norm

;; Segment data for vertex A -> B with bulge b (b /= 0):
;; returns (theta radius center start-tangent end-tangent)
;; theta = signed included angle (CCW positive), tangents are angles.
(defun mohamaddle--arcdata (a b blg / theta chord r phi ts cen)
  (setq theta (* 4.0 (atan blg))
        chord (distance a b)
        r     (/ chord (* 2.0 (sin (/ (abs theta) 2.0))))
        phi   (angle a b)
        ts    (- phi (/ theta 2.0))
        cen   (mohamaddle--add a (mohamaddle--scl (mohamaddle--dir (+ ts (if (> blg 0.0) (/ pi 2.0) (/ pi -2.0)))) r)))
  (list theta r cen ts (+ phi (/ theta 2.0))))

;; Signed area of a closed vertex list (shoelace + circular segments).
;; vts = list of (x y bulge), bulge belongs to the segment leaving it.
(defun mohamaddle--area (vts / n i a b blg area theta r seg)
  (setq n (length vts) i 0 area 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq area (+ area (* 0.5 (- (* (car a) (cadr b)) (* (car b) (cadr a))))))
    (if (/= blg 0.0)
        (progn
          (setq seg   (mohamaddle--arcdata a b blg)
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
(defun mohamaddle--next-flush (cen r sa sgn cur sweep prev padsize
                               / ds d p hit lo hi mid)
  (setq ds (/ padsize r 8.0))                ; ~1/8 pad per probe step
  (if (> ds (/ sweep 4.0)) (setq ds (/ sweep 4.0)))
  (setq d cur hit nil)
  (while (and (not hit) (< d (- sweep 1e-9))) ; walk until pads separate
    (setq lo d
          d  (min sweep (+ d ds))
          p  (mohamaddle--arcpt cen r (+ sa (* sgn d))))
    (if (>= (mohamaddle--cheb (mohamaddle--sub p prev)) padsize)
        (setq hit T)))
  (if hit
      (progn ; tighten the crossing between lo and d by bisection
        (setq hi d)
        (repeat 45
          (setq mid (/ (+ lo hi) 2.0)
                p   (mohamaddle--arcpt cen r (+ sa (* sgn mid))))
          (if (>= (mohamaddle--cheb (mohamaddle--sub p prev)) padsize)
              (setq hi mid)
              (setq lo mid)))
        (list hi (mohamaddle--arcpt cen r (+ sa (* sgn hi)))))))

;; Pad centers for one concave arc: the fewest pads that matter most.
;; The first pad is centered on the MIDDLE of the arc (the part that
;; must be covered); further pads march outward toward both ends, each
;; exactly one pad-size on center from the last, so the row touches
;; edge-to-edge and stair-steps into a blocky representation of the
;; curve. Marching stops when the leftover end of the arc is too short
;; for another flush pad -- the extreme ends of the radius are allowed
;; to stay uncovered.
(defun mohamaddle--arc-pads (cen r sa sgn sweep padsize
                             / mid amid pmid fwd bwd cur prev nxt)
  (setq mid  (/ sweep 2.0)
        amid (+ sa (* sgn mid))
        pmid (mohamaddle--arcpt cen r amid))
  ;; march from the middle toward the arc's end...
  (setq cur 0.0 prev pmid fwd nil)
  (while (setq nxt (mohamaddle--next-flush cen r amid sgn cur (- sweep mid) prev padsize))
    (setq cur (car nxt) prev (cadr nxt) fwd (cons prev fwd)))
  ;; ...and from the middle back toward the arc's start
  (setq cur 0.0 prev pmid bwd nil)
  (while (setq nxt (mohamaddle--next-flush cen r amid (- sgn) cur mid prev padsize))
    (setq cur (car nxt) prev (cadr nxt) bwd (cons prev bwd)))
  (append bwd (list pmid) (reverse fwd)))

;; Direction (unit vector) of travel at the START / END of segment a->b.
(defun mohamaddle--tan-start (a b blg)
  (if (= blg 0.0)
      (mohamaddle--unit (mohamaddle--sub b a))
      (mohamaddle--dir (cadddr (mohamaddle--arcdata a b blg)))))
(defun mohamaddle--tan-end (a b blg)
  (if (= blg 0.0)
      (mohamaddle--unit (mohamaddle--sub b a))
      (mohamaddle--dir (last (mohamaddle--arcdata a b blg)))))

;; --------------------- entities -> segments ------------------------
;; A segment is (p1 p2 bulge) with 2D points.

;; LWPOLYLINE -> (closed-flag . vts)
(defun mohamaddle--lwverts (ent / ed out grp)
  (setq ed (entget ent))
  (foreach grp ed
    (cond
      ((= (car grp) 10)
       (setq out (cons (list (cadr grp) (caddr grp) 0.0) out)))
      ((= (car grp) 42)
       (if out (setq out (cons (list (caar out) (cadr (car out)) (cdr grp)) (cdr out)))))))
  (cons (= 1 (logand 1 (cdr (assoc 70 ed)))) (reverse out)))

;; heavy 2D POLYLINE -> (closed-flag . vts), nil for 3D/mesh plines
(defun mohamaddle--plverts (ent / ed flags e ved out p)
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
(defun mohamaddle--vts->segs (closed vts / n i segs a b)
  (setq n (length vts) i 0)
  (repeat (if closed n (max 0 (1- n)))
    (setq a (nth i vts)
          b (nth (rem (1+ i) n) vts))
    (setq segs (cons (list (mohamaddle--2d a) (mohamaddle--2d b) (caddr a)) segs))
    (setq i (1+ i)))
  (reverse segs))

;; any supported entity -> list of segments
(defun mohamaddle--ent-segs (ent / ed typ cen r sa ea sweep cv)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (mohamaddle--2d (cdr (assoc 10 ed)))
                 (mohamaddle--2d (cdr (assoc 11 ed))) 0.0)))
    ((= typ "ARC")
     (setq cen   (mohamaddle--2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           sa    (cdr (assoc 50 ed))
           ea    (cdr (assoc 51 ed))
           sweep (- ea sa))
     (if (<= sweep 0.0) (setq sweep (+ sweep pi pi)))
     (list (list (mohamaddle--add cen (mohamaddle--scl (mohamaddle--dir sa) r))
                 (mohamaddle--add cen (mohamaddle--scl (mohamaddle--dir ea) r))
                 (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0)))))) ; tan(sweep/4)
    ((= typ "LWPOLYLINE")
     (setq cv (mohamaddle--lwverts ent))
     (mohamaddle--vts->segs (car cv) (cdr cv)))
    ((= typ "POLYLINE")
     (setq cv (mohamaddle--plverts ent))
     (if cv (mohamaddle--vts->segs (car cv) (cdr cv))))))

;; ------------------- chain segments into loops ---------------------
;; Chains touching segments (ends within *mohamaddle-fuzz*) end-to-end.
;; Returns (loops . open-count); each loop is a vertex list (x y bulge).
(defun mohamaddle--chain (segs / loops nopen chain head tail done found rest s)
  (setq nopen 0)
  ;; drop degenerate slivers
  (setq segs (vl-remove-if
               '(lambda (s) (<= (distance (car s) (cadr s)) *mohamaddle-fuzz*))
               segs))
  (while segs
    (setq chain (list (car segs))
          head  (car (car segs))
          tail  (cadr (car segs))
          segs  (cdr segs)
          done  nil)
    (while (not done)
      (cond
        ;; loop closed back onto its start?
        ((and (> (length chain) 1) (<= (distance tail head) *mohamaddle-fuzz*))
         (setq loops (cons (mapcar '(lambda (s) (list (car (car s)) (cadr (car s)) (caddr s)))
                                   chain)
                           loops)
               done  T))
        (T ;; look for a segment continuing from the tail
         (setq found nil rest nil)
         (foreach s segs
           (if found
               (setq rest (cons s rest))
               (cond
                 ((<= (distance tail (car s)) *mohamaddle-fuzz*)
                  (setq found s))
                 ((<= (distance tail (cadr s)) *mohamaddle-fuzz*) ; reversed
                  (setq found (list (cadr s) (car s) (- (caddr s)))))
                 (T (setq rest (cons s rest))))))
         (if found
             (setq chain (append chain (list found))
                   tail  (cadr found)
                   segs  (reverse rest))
             (setq nopen (1+ nopen) done T)))))) ; dead end: open chain
  (cons (reverse loops) nopen))

;; ------------------------ feature detection ------------------------
;; Returns a list of pads: (center rotation kind), kind = "corner"/"arc".
;; PADSIZE sets the pad-grid pitch used to cover concave arcs.
(defun mohamaddle--features (vts padsize / s n i a b c blg pads din dout turn
                                 seg theta r cen sa sgn sweep)
  (setq s (if (< (mohamaddle--area vts) 0.0) -1 1) ; -1 = clockwise
        n (length vts)
        i 0)
  (repeat n
    (setq a   (nth i vts)                     ; segment i : a -> b
          b   (nth (rem (1+ i) n) vts)
          c   (nth (rem (+ i (1- n)) n) vts)  ; previous vertex
          blg (caddr a))

    ;; --- concave vertex (inside corner) at a, between seg i-1 and i ---
    (setq din  (mohamaddle--tan-end (mohamaddle--2d c) (mohamaddle--2d a) (caddr c))
          dout (mohamaddle--tan-start (mohamaddle--2d a) (mohamaddle--2d b) blg))
    (if (and din dout)
        (progn
          (setq turn (atan (mohamaddle--cross din dout) (mohamaddle--dot din dout)))
          (if (< (* s turn) (- *mohamaddle-cornertol*)) ; turns away from
                                                        ; the interior by
                                                        ; more than 30 deg
              (setq pads (cons (list (mohamaddle--2d a) (angle '(0.0 0.0) din) "corner")
                               pads)))))

    ;; --- concave arc segment with radius <= 4'-6" ---
    (if (and (/= blg 0.0)
             (< (* s blg) 0.0)) ; bulges into the interior
        (progn
          (setq seg   (mohamaddle--arcdata (mohamaddle--2d a) (mohamaddle--2d b) blg)
                theta (car seg)
                r     (cadr seg)
                cen   (caddr seg))
          (if (and (<= r (+ *mohamaddle-maxrad* 1e-6))
                   (> (abs theta) *mohamaddle-arctol*)) ; total bend over 10
                                                       ; deg, else it's a
                                                       ; semi-straight line
              (progn
                (setq sa    (angle cen (mohamaddle--2d a))
                      sgn   (if (> theta 0.0) 1.0 -1.0)
                      sweep (abs theta))
                (foreach ctr (mohamaddle--arc-pads cen r sa sgn sweep padsize)
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
(defun mohamaddle--dodge (pads padsize / out ctr orig tries done hit d ax sgn)
  (foreach pad pads ; sharp points first: exact centers, never slid
    (if (= (caddr pad) "corner")
        (progn
          (setq hit nil)
          (foreach q out
            (if (and (not hit)
                     (< (mohamaddle--cheb (mohamaddle--sub (car pad) (car q)))
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
                       (< (mohamaddle--cheb (mohamaddle--sub ctr (car q)))
                          (- padsize 1e-6)))
                  (setq hit (car q))))
            (cond
              ((not hit) ; clear: commit it here
               (setq out  (cons (list ctr (cadr pad) (caddr pad)) out)
                     done T))
              ((or (< (mohamaddle--cheb (mohamaddle--sub ctr hit)) (/ padsize 2.0))
                   (> tries 6)
                   (> (mohamaddle--cheb (mohamaddle--sub ctr orig)) (/ padsize 2.0)))
               (setq done T)) ; already covered there, or stuck: drop it
              (T ; slide along the more-separated axis until flush
               (setq d   (mohamaddle--sub ctr hit)
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
(defun mohamaddle--ensure-block (doc name size / path oldcmd oldatt tmpname)
  (cond
    ((tblsearch "BLOCK" name) T)
    ;; pull the definitions in from the pad dwg if it can be found --
    ;; inserting the file (under a throwaway name, then cancelling)
    ;; imports every block definition it contains
    ((setq path (findfile *mohamaddle-blkfile*))
     (setq oldcmd (getvar "CMDECHO") oldatt (getvar "ATTREQ")
           tmpname "MOHAMADDLE-TEMP-IMPORT")
     (setvar "CMDECHO" 0) (setvar "ATTREQ" 0)
     ;; the restore below must run even if the insert throws: oldcmd
     ;; and oldatt are locals of THIS helper, so c:MOHAMADDLE's *error*
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
         (mohamaddle--make-fallback-block name size)))
    (T (mohamaddle--make-fallback-block name size))))

;; Last-resort pad: a plain size x size square block, base at center.
(defun mohamaddle--make-fallback-block (name size / h)
  (setq h (/ size 2.0))
  (entmake (list '(0 . "BLOCK") (cons 2 name)
                 '(10 0.0 0.0 0.0) '(70 . 0)))
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0")
                 '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                 (list 10 (- h) (- h)) (list 10 h (- h))
                 (list 10 h h) (list 10 (- h) h)))
  (entmake '((0 . "ENDBLK")))
  (princ (strcat "\nMOHAMADDLE: block \"" name "\" not found; created a plain "
                 (rtos size 2 0) "x" (rtos size 2 0) " square block instead."))
  (tblsearch "BLOCK" name))

;; Offset from the block's insertion point to the center of its extents
;; (measured at 0 rotation), so pads land centered no matter where the
;; block's base point was drawn.
(defun mohamaddle--block-delta (space name / tmp mn mx d)
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
(defun mohamaddle--ensure-layer (name color / rec ed flags col fixed)
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
;; parallel to the X/Y axes unless *mohamaddle-align* is set.
(defun mohamaddle--insert-pad (space name ctr rot delta / ip obj)
  (if (not *mohamaddle-align*) (setq rot 0.0))
  (setq ip  (mohamaddle--sub ctr (mohamaddle--rot delta rot))
        obj (vla-InsertBlock space
              (vlax-3d-point (car ip) (cadr ip) 0.0)
              name 1.0 1.0 1.0 rot))
  (vla-put-Layer obj *mohamaddle-layer*)
  obj)

;; Loops that enclose no area - two lines lying on top of each other,
;; a polyline that doubles straight back on itself - have no inside
;; for anything to be concave toward, and the sign of their zero area
;; is float noise, so the 180-degree reversal at each end could be
;; called an inside corner on the strength of a -0.0.  Returns LOOPS
;; without them.  (Auto-detect never picks one, since it keeps the
;; largest area; an explicit selection would have padded it.)
(defun mohamaddle--solid-loops (loops)
  (vl-remove-if '(lambda (l) (< (abs (mohamaddle--area l)) 1e-6)) loops))

;; --------------------------- selection -----------------------------
;; Turns a selection set (or the whole current tab when SS is nil) into
;; a list of closed perimeter loops (vertex lists). Auto-detect keeps
;; only the largest loop.
(defun mohamaddle--perimeters (ss / auto i segs res loops nopen nflat best
                                  bestarea a)
  (setq auto (not ss))
  (if auto
      (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,POLYLINE,LINE,ARC")
                                 (cons 410 (getvar "CTAB"))))))
  (if ss
      (progn
        (setq i 0)
        (repeat (sslength ss)
          (setq segs (append segs (mohamaddle--ent-segs (ssname ss i)))
                i    (1+ i)))
        (setq res   (mohamaddle--chain segs)
              loops (mohamaddle--solid-loops (car res))
              nflat (- (length (car res)) (length loops))
              nopen (cdr res))
        (if (> nopen 0)
            (princ (strcat "\nMOHAMADDLE: ignored " (itoa nopen)
                           " open chain(s) that never close back on themselves"
                           " (check for gaps; chaining tolerance is "
                           (rtos *mohamaddle-fuzz* 2 2) ").")))
        (if (> nflat 0)
            (princ (strcat "\nMOHAMADDLE: ignored " (itoa nflat)
                           " closed loop(s) that enclose no area"
                           " (lines doubling back on themselves).")))
        (if auto
            (progn ; keep only the biggest closed loop
              (setq bestarea 0.0)
              (foreach l loops
                (setq a (abs (mohamaddle--area l)))
                (if (> a bestarea) (setq bestarea a best l)))
              (if best
                  (progn
                    (princ "\nMOHAMADDLE: auto-detected the largest closed loop as the perimeter.")
                    (list best))))
            loops))))

;; ---------------------------- command ------------------------------
(defun c:MOHAMADDLE (/ *error* doc space mark-open sizekw picked padsize
                       blkname ss perims vts allpads delta ndodge ncorner narc)
  (defun *error* (msg)
    ;; close only the mark THIS run opened: an Esc at the size or
    ;; perimeter prompt comes before StartUndoMark, and closing a mark
    ;; nothing opened throws -- from inside the handler, where nothing
    ;; catches it.  command-s style: the close itself goes through
    ;; vl-catch-all-apply so it can never be the second error.
    (if mark-open (vl-catch-all-apply 'vla-EndUndoMark (list doc)))
    (setq mark-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nMOHAMADDLE error: " msg)))
    (if lzd:report (lzd:report "MOHAMADDLE" *mohamaddle-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "MOHAMADDLE" *mohamaddle-version*))

  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-Block (vla-get-ActiveLayout doc)))

  (princ (strcat "\nMOHAMADDLE " *mohamaddle-version*))

  ;; ask which size to place -- see mohamaddle--asksize above for why
  ;; this one prompt is allowed to offer no Back
  (setq sizekw  (mohamaddle--asksize *mohamaddle-defaultkw*)
        picked  (assoc sizekw *mohamaddle-sizes*)
        blkname (cadr picked)
        padsize (caddr picked))
  (setq *mohamaddle-defaultkw* sizekw) ; remember the pick for next time

  (princ (strcat "\nMOHAMADDLE - " (mohamaddle--in padsize)
                 " pads at concave perimeter features (R <= "
                 (rtos *mohamaddle-maxrad* 4 0) " and inside corners)."))

  ;; A pickfirst selection is taken as-is.  A user who highlighted the
  ;; outline before typing MOHAMADDLE meant the same thing. It matters
  ;; because auto-detect reads the WHOLE drawing for its largest closed
  ;; loop -- being handed the loop beats guessing at it beside a title
  ;; block border.
  (setq ss (ssget "_I" '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC"))))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
      (progn
        (princ "\nSelect perimeter (polylines, lines and arcs) or press Enter to auto-detect: ")
        (setq ss (ssget '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC"))))
        (if lzd:watch (lzd:watch ss) ss)))
  (setq perims (mohamaddle--perimeters ss))

  (if (not perims)
      (princ "\nMOHAMADDLE: no closed perimeter loop found.")
      (progn
        (vla-StartUndoMark doc)
        (setq mark-open T)
        (mohamaddle--ensure-block doc blkname padsize)
        (mohamaddle--ensure-layer *mohamaddle-layer* *mohamaddle-layer-color*)
        (setq delta (mohamaddle--block-delta space blkname))
        (foreach vts perims
          (if (> (length vts) 1)
              (setq allpads (append allpads (mohamaddle--features vts padsize)))))
        (setq ndodge  (length allpads)
              allpads (mohamaddle--dodge allpads padsize)
              ndodge  (- ndodge (length allpads)))
        (setq ncorner 0 narc 0)
        (foreach pad allpads
          (mohamaddle--insert-pad space blkname (car pad) (cadr pad) delta)
          (if (= (caddr pad) "corner") (setq ncorner (1+ ncorner)) (setq narc (1+ narc))))
        (vla-EndUndoMark doc)
        (setq mark-open nil)
        (if allpads
            (progn
              (princ (strcat "\nMOHAMADDLE: inserted " (itoa (length allpads))
                             " " (mohamaddle--in padsize) " pad(s) on layer \""
                             *mohamaddle-layer* "\" ("
                             (itoa ncorner) " at inside corners, "
                             (itoa narc) " along concave arcs)."))
              (if (> ndodge 0)
                  (princ (strcat "\nMOHAMADDLE: " (itoa ndodge)
                                 " overlapping pad(s) merged into their"
                                 " neighbours where features crowd together."))))
            (princ "\nMOHAMADDLE: perimeter checked - no concave features need pads."))))
  (if lzd:end (lzd:end "MOHAMADDLE"))
  (princ))

(defun c:MOHAMADDLEVER ()
  (princ (strcat "\nMOHAMADDLE " *mohamaddle-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and CALOFIN-LOADER.lsp set
;; the flag while they load their members, because one file's greeting
;; is a greeting and every tool's is a wall the drafter scrolls past in
;; every drawing they open.  APPLOADed alone the flag is nil and this
;; prints, which is the one time somebody wants to be told.  CALVER
;; reports the whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nMOHAMADDLE " *mohamaddle-version*
                 " loaded. Command: MOHAMADDLE (pick a pad size, then place pads).")))
(princ)
