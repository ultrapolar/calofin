;;; ===================================================================
;;; PADDLE.lsp
;;;
;;; Scans the perimeter of a drawing for concave features that require
;;; pads, and inserts 36" x 36" pad blocks ("Pad36x36") centered on
;;; the affected areas, always parallel to the X/Y axes.
;;;
;;; Pad specification:
;;;   * Any CONCAVE arc / fillet with a radius of 4'-6" (54") or less
;;;     -- all the way down to sharp 90-degree inside corners --
;;;     requires pads along the affected arc.
;;;   * Any CONCAVE intersection of straight segments (an inside
;;;     corner) requires a pad centered on the corner.
;;;   * Semi-straight geometry is left alone: a connection point or an
;;;     arc whose total bend is 10 degrees or less is not a feature.
;;;   * Convex features and concave arcs larger than 4'-6" radius do
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
;;;
;;; Usage:
;;;   Command: PADDLE
;;;   Select the perimeter geometry, or press Enter to auto-detect
;;;   the perimeter (the largest closed loop found in the drawing).
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
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
(setq *paddle-version* "v1.3") ; printed on load and at command start
                             ; so a loaded routine and its releases/
                             ; twin can never disagree
(setq *paddle-blkname* "Pad36x36") ; the 3'x3' pad block
(setq *paddle-padsize* 36.0) ; pads are 36" x 36"
(setq *paddle-blkfile* "24inpad.dwg") ; dwg holding the pad blocks
(setq *paddle-maxrad* 54.0)  ; 4'-6" : largest concave radius needing pads
(setq *paddle-layer* "PADS") ; layer pads are inserted on
(setq *paddle-align* nil)    ; nil = pads stay parallel to the X/Y axes,
                             ; T = rotate pads with the perimeter edge
(setq *paddle-fuzz* 0.05)    ; max gap between segment ends when
                             ; chaining loose lines/arcs into a loop
(setq *paddle-angtol* (/ (* 10.0 pi) 180.0)) ; a connection point or an
                             ; arc whose total bend is 10 degrees or
                             ; less is semi-straight - no pad

(defun paddle--dir (a) (list (cos a) (sin a))) ; unit vector at angle a
(defun paddle--rot (v a) ; rotate vector v by angle a
  (list (- (* (car v) (cos a)) (* (cadr v) (sin a)))
        (+ (* (car v) (sin a)) (* (cadr v) (cos a)))))
(defun paddle--arcpt (cen r ang) (cal:v+ cen (cal:v* (paddle--dir ang) r)))
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
        cen   (cal:v+ a (cal:v* (paddle--dir (+ ts (if (> blg 0.0) (/ pi 2.0) (/ pi -2.0)))) r)))
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
    (if (>= (paddle--cheb (cal:v- p prev)) padsize)
        (setq hit T)))
  (if hit
      (progn ; tighten the crossing between lo and d by bisection
        (setq hi d)
        (repeat 45
          (setq mid (/ (+ lo hi) 2.0)
                p   (paddle--arcpt cen r (+ sa (* sgn mid))))
          (if (>= (paddle--cheb (cal:v- p prev)) padsize)
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
      (cal:unit (cal:v- b a))
      (paddle--dir (cadddr (paddle--arcdata a b blg)))))
(defun paddle--tan-end (a b blg)
  (if (= blg 0.0)
      (cal:unit (cal:v- b a))
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
    (setq segs (cons (list (cal:2d a) (cal:2d b) (caddr a)) segs))
    (setq i (1+ i)))
  (reverse segs))

;; any supported entity -> list of segments
(defun paddle--ent-segs (ent / ed typ cen r sa ea sweep cv)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (cal:2d (cdr (assoc 10 ed)))
                 (cal:2d (cdr (assoc 11 ed))) 0.0)))
    ((= typ "ARC")
     (setq cen   (cal:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           sa    (cdr (assoc 50 ed))
           ea    (cdr (assoc 51 ed))
           sweep (- ea sa))
     (if (<= sweep 0.0) (setq sweep (+ sweep pi pi)))
     (list (list (cal:v+ cen (cal:v* (paddle--dir sa) r))
                 (cal:v+ cen (cal:v* (paddle--dir ea) r))
                 (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0)))))) ; tan(sweep/4)
    ((= typ "LWPOLYLINE")
     (setq cv (paddle--lwverts ent))
     (paddle--vts->segs (car cv) (cdr cv)))
    ((= typ "POLYLINE")
     (setq cv (paddle--plverts ent))
     (if cv (paddle--vts->segs (car cv) (cdr cv))))))

;; ------------------- chain segments into loops ---------------------
;; Chains touching segments (ends within *paddle-fuzz*) end-to-end.
;; Returns (loops . open-count); each loop is a vertex list (x y bulge).
(defun paddle--chain (segs / loops nopen chain head tail done found rest s)
  (setq nopen 0)
  ;; drop degenerate slivers
  (setq segs (vl-remove-if
               '(lambda (s) (<= (distance (car s) (cadr s)) *paddle-fuzz*))
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
        ((and (> (length chain) 1) (<= (distance tail head) *paddle-fuzz*))
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
                 ((<= (distance tail (car s)) *paddle-fuzz*)
                  (setq found s))
                 ((<= (distance tail (cadr s)) *paddle-fuzz*) ; reversed
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
    (setq din  (paddle--tan-end (cal:2d c) (cal:2d a) (caddr c))
          dout (paddle--tan-start (cal:2d a) (cal:2d b) blg))
    (if (and din dout)
        (progn
          (setq turn (atan (cal:cross din dout) (cal:dot din dout)))
          (if (< (* s turn) (- *paddle-angtol*)) ; turns away from interior
              (setq pads (cons (list (cal:2d a) (angle '(0.0 0.0) din) "corner")
                               pads)))))

    ;; --- concave arc segment with radius <= 4'-6" ---
    (if (and (/= blg 0.0)
             (< (* s blg) 0.0)) ; bulges into the interior
        (progn
          (setq seg   (paddle--arcdata (cal:2d a) (cal:2d b) blg)
                theta (car seg)
                r     (cadr seg)
                cen   (caddr seg))
          (if (and (<= r (+ *paddle-maxrad* 1e-6))
                   (> (abs theta) *paddle-angtol*)) ; total bend over 10
                                                    ; deg, else it's a
                                                    ; semi-straight line
              (progn
                (setq sa    (angle cen (cal:2d a))
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
                     (< (paddle--cheb (cal:v- (car pad) (car q)))
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
                       (< (paddle--cheb (cal:v- ctr (car q)))
                          (- padsize 1e-6)))
                  (setq hit (car q))))
            (cond
              ((not hit) ; clear: commit it here
               (setq out  (cons (list ctr (cadr pad) (caddr pad)) out)
                     done T))
              ((or (< (paddle--cheb (cal:v- ctr hit)) (/ padsize 2.0))
                   (> tries 6)
                   (> (paddle--cheb (cal:v- ctr orig)) (/ padsize 2.0)))
               (setq done T)) ; already covered there, or stuck: drop it
              (T ; slide along the more-separated axis until flush
               (setq d   (cal:v- ctr hit)
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
     (command "_.-INSERT" (strcat tmpname "=" path))
     (command) ; cancel the insert -- the definitions stay behind
     (setvar "CMDECHO" oldcmd) (setvar "ATTREQ" oldatt)
     (vl-catch-all-apply ; drop the unused throwaway definition
       '(lambda () (vla-Delete (vla-Item (vla-get-Blocks doc) tmpname))))
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

(defun paddle--ensure-layer (doc)
  (vla-Add (vla-get-Layers doc) *paddle-layer*))

;; Insert one pad so that its extents are centered on CTR. Pads stay
;; parallel to the X/Y axes unless *paddle-align* is set.
(defun paddle--insert-pad (space name ctr rot delta / ip obj)
  (if (not *paddle-align*) (setq rot 0.0))
  (setq ip  (cal:v- ctr (paddle--rot delta rot))
        obj (vla-InsertBlock space
              (vlax-3d-point (car ip) (cadr ip) 0.0)
              name 1.0 1.0 1.0 rot))
  (vla-put-Layer obj *paddle-layer*)
  obj)

;; --------------------------- selection -----------------------------
;; Turns a selection set (or the whole current tab when SS is nil) into
;; a list of closed perimeter loops (vertex lists). Auto-detect keeps
;; only the largest loop.
(defun paddle--perimeters (ss / auto i segs res loops nopen best bestarea a)
  (setq auto (not ss))
  (if auto
      (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,POLYLINE,LINE,ARC")
                                 (cons 410 (getvar "CTAB"))))))
  (if ss
      (progn
        (setq i 0)
        (repeat (sslength ss)
          (setq segs (append segs (paddle--ent-segs (ssname ss i)))
                i    (1+ i)))
        (setq res   (paddle--chain segs)
              loops (car res)
              nopen (cdr res))
        (if (> nopen 0)
            (princ (strcat "\nPADDLE: ignored " (itoa nopen)
                           " open chain(s) that never close back on themselves"
                           " (check for gaps; chaining tolerance is "
                           (rtos *paddle-fuzz* 2 2) ").")))
        (if auto
            (progn ; keep only the biggest closed loop
              (setq bestarea 0.0)
              (foreach l loops
                (setq a (abs (paddle--area l)))
                (if (> a bestarea) (setq bestarea a best l)))
              (if best
                  (progn
                    (princ "\nPADDLE: auto-detected the largest closed loop as the perimeter.")
                    (list best))))
            loops))))

;; ---------------------------- command ------------------------------
(defun c:PADDLE (/ *error* doc space padsize blkname ss perims vts
                   allpads delta ndodge ncorner narc)
  (defun *error* (msg)
    (if doc (vla-EndUndoMark doc))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nPADDLE error: " msg)))
    (princ))

  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-Block (vla-get-ActiveLayout doc)))

  (princ (strcat "\nPADDLE " *paddle-version*))
  (princ (strcat "\nPADDLE - 36\" pads at concave perimeter features (R <= "
                 (rtos *paddle-maxrad* 4 0) " and inside corners)."))

  (setq padsize *paddle-padsize*
        blkname *paddle-blkname*)

  (princ "\nSelect perimeter (polylines, lines and arcs) or press Enter to auto-detect: ")
  (setq ss (ssget '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC"))))
  (setq perims (paddle--perimeters ss))

  (if (not perims)
      (princ "\nPADDLE: no closed perimeter loop found.")
      (progn
        (vla-StartUndoMark doc)
        (paddle--ensure-block doc blkname padsize)
        (paddle--ensure-layer doc)
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
        (vla-EndUndoMark doc)
        (if allpads
            (progn
              (princ (strcat "\nPADDLE: inserted " (itoa (length allpads))
                             " 36\" pad(s) on layer \"" *paddle-layer* "\" ("
                             (itoa ncorner) " at inside corners, "
                             (itoa narc) " along concave arcs)."))
              (if (> ndodge 0)
                  (princ (strcat "\nPADDLE: " (itoa ndodge)
                                 " overlapping pad(s) merged into their"
                                 " neighbours where features crowd together."))))
            (princ "\nPADDLE: perimeter checked - no concave features need pads."))))
  (princ))

;; --------------------------- tutorial ------------------------------
;; TUTORIALPADDLE walks a new user through what PADDLE checks, then
;; (optionally) draws a sample perimeter containing every kind of
;; feature and pads it step by step.

(defun paddle--pause ()
  (getstring "\n  [ press ENTER to continue ]")
  (princ))

;; the sample perimeter: straight walls, a 2-degree kink (ignored),
;; convex corners (ignored), a rectangular slot with two >10-degree
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

(defun paddle--demo-text (base lay pt str)
  (entmake (list '(0 . "TEXT") (cons 8 lay)
                 (list 10 (+ (car base) (car pt)) (+ (cadr base) (cadr pt)) 0.0)
                 '(40 . 6.0) (cons 1 str)))
  (entlast))

(defun c:TUTORIALPADDLE (/ doc space base lay ents pl vts feats blk delta
                           pad ncorner narc)
  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-Block (vla-get-ActiveLayout doc)))
  (princ (strcat "\n=== PADDLE TUTORIAL " *paddle-version* " ==="))
  (princ "\nPADDLE looks at the perimeter of a drawing and inserts pad blocks")
  (princ "\nwherever the perimeter caves inward. Everything it checks:")
  (princ "\n")
  (princ "\n 1. THE PERIMETER. Select it, or press ENTER and PADDLE finds the")
  (princ "\n    largest closed loop by itself. A closed polyline is ideal, but")
  (princ "\n    loose lines and arcs work too - touching ends (within ")
  (princ (strcat (rtos *paddle-fuzz* 2 2) "\") are"))
  (princ "\n    chained together automatically.")
  (princ (strcat "\n 2. INSIDE CORNERS. A connection point that bends more than "
                 (rtos (/ (* *paddle-angtol* 180.0) pi) 2 0) " degrees"))
  (princ "\n    away from straight gets one pad centered on the corner. Gentler")
  (princ "\n    kinks - semi-straight lines - and all convex (outside) corners")
  (princ "\n    are passed over.")
  (princ (strcat "\n 3. CONCAVE CURVES. A concave radius of " (rtos *paddle-maxrad* 4 0)
                 " or less, bending more"))
  (princ "\n    than 10 degrees in total, gets a row of pads: the middle of the")
  (princ "\n    curve is always covered, then pads march flush toward both ends")
  (princ "\n    (exactly 36\" on center, touching, never overlapping) - a blocky")
  (princ "\n    version of the curve. The extreme ends of the radius may stay")
  (princ "\n    uncovered; that is by design. Bigger concave radii, and curves")
  (princ "\n    bending 10 degrees or less, need no pads at all.")
  (princ "\n 4. NO COLLISIONS. Where features crowd together, a pad on a sharp")
  (princ "\n    point stays dead-center on that point - it never moves. The pads")
  (princ "\n    along curves do the dodging: they slide over to sit flush")
  (princ "\n    alongside, or drop out when a neighbour already covers their spot.")
  (princ (strcat "\n 5. RESULT. 36\" x 36\" pads (block " *paddle-blkname*
                 ", imported from"))
  (princ (strcat "\n    " *paddle-blkfile* " if needed), always square to the"
                 " X/Y axes, on layer"))
  (princ (strcat "\n    \"" *paddle-layer* "\", as a single undo step."))
  (paddle--pause)
  (initget "Yes No")
  (if (/= (getkword "\nDraw a live demonstration in this drawing? [Yes/No] <Yes>: ") "No")
      (progn
        (setq lay "PADDLE-DEMO")
        (vla-put-Color (vla-Add (vla-get-Layers doc) lay) 3)
        (setq base (getpoint "\nPick a clear spot for the demo <0,0>: "))
        (if (not base) (setq base '(0.0 0.0 0.0)))
        (setq pl   (paddle--demo-pline base lay)
              ents (list pl))
        (command "_.ZOOM" "_W"
                 (list (- (car base) 40.0) (- (cadr base) 40.0))
                 (list (+ (car base) 340.0) (+ (cadr base) 210.0)))
        (princ "\nThis sample perimeter (green) has one of everything. Labelling it...")
        (paddle--pause)
        (setq ents (cons (paddle--demo-text base lay '(96 14)
                     "2-deg kink here: 10 deg or less = ignored") ents))
        (setq ents (cons (paddle--demo-text base lay '(140 100)
                     "slot corners bend >10 deg: pad on each") ents))
        (setq ents (cons (paddle--demo-text base lay '(166 108)
                     "concave R4'-0\" (<= R4'-6\"): row of pads") ents))
        (setq ents (cons (paddle--demo-text base lay '(30 84)
                     "concave R6'-0\" (> R4'-6\"): no pads") ents))
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
        (paddle--ensure-layer doc)
        (setq delta (paddle--block-delta space blk)
              ncorner 0 narc 0)
        (princ "\nStep 1 - inside corners: one pad centered on each corner of the slot.")
        (foreach pad feats
          (if (= (caddr pad) "corner")
              (progn (paddle--insert-pad space blk (car pad) (cadr pad) delta)
                     (setq ents (cons (entlast) ents) ncorner (1+ ncorner)))))
        (paddle--pause)
        (princ "\nStep 2 - the R4'-0\" curve: first pad centered on the middle of the")
        (princ "\nradius, the rest flush at 36\" on center, stair-stepping the curve.")
        (princ "\nNote the R6'-0\" curve and the kink get nothing.")
        (foreach pad feats
          (if (= (caddr pad) "arc")
              (progn (paddle--insert-pad space blk (car pad) (cadr pad) delta)
                     (setq ents (cons (entlast) ents) narc (1+ narc)))))
        (princ (strcat "\nDone: " (itoa ncorner) " corner pad(s) + " (itoa narc)
                       " pad(s) along the curve, on layer \"" *paddle-layer* "\"."))
        (paddle--pause)
        (initget "Yes No")
        (if (= (getkword "\nErase the demonstration? [Yes/No] <No>: ") "Yes")
            (foreach e ents (entdel e)))))
  (princ "\nEnd of tutorial. Type PADDLE to run it on a real drawing.")
  (princ))

(princ (strcat "\nPADDLE " *paddle-version*
               " loaded. Commands: PADDLE (place pads), TUTORIALPADDLE (guided demo)."))
(princ)
