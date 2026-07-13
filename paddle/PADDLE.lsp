;;; ===================================================================
;;; PADDLE.lsp
;;;
;;; Scans the perimeter of a drawing for concave features that require
;;; pads, and inserts pad blocks centered on the affected areas.
;;; Pads come in two sizes -- 24" x 24" ("Pad24x24") for normal work
;;; and 36" x 36" ("Pad36x36") for bigger locations -- chosen at the
;;; prompt. Pads are always inserted parallel to the X/Y axes.
;;;
;;; Pad specification:
;;;   * Any CONCAVE arc / fillet with a radius of 4'-6" (54") or less
;;;     -- all the way down to sharp 90-degree inside corners --
;;;     requires pads along the affected arc.
;;;   * Any CONCAVE intersection of straight segments (an inside
;;;     corner) requires a pad centered on the corner.
;;;   * Convex features and concave arcs larger than 4'-6" radius do
;;;     NOT require pads.
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
;; available pad sizes: (inches . block-name); PADDLE asks which one
(setq *paddle-sizes* '((24 . "Pad24x24")   ; standard 2'x2' pad
                       (36 . "Pad36x36"))) ; bigger 3'x3' pad
(setq *paddle-blkfile* "24inpad.dwg") ; dwg holding the pad blocks
(setq *paddle-maxrad* 54.0)  ; 4'-6" : largest concave radius needing pads
(setq *paddle-layer* "PADS") ; layer pads are inserted on
(setq *paddle-align* nil)    ; nil = pads stay parallel to the X/Y axes,
                             ; T = rotate pads with the perimeter edge
(setq *paddle-fuzz* 0.05)    ; max gap between segment ends when
                             ; chaining loose lines/arcs into a loop
(setq *paddle-angtol* (/ pi 180.0)) ; 1 deg: corners flatter than this
                                    ; are treated as straight-through

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
(defun paddle--cheb (v) (max (abs (car v)) (abs (cadr v)))) ; Chebyshev norm
(defun paddle--arcpt (cen r ang) (paddle--add cen (paddle--scl (paddle--dir ang) r)))

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

;; Next pad along an arc row: starting from arc-parameter CUR (pad
;; center PREV), find the parameter where the pad center is exactly
;; PADSIZE away from PREV in Chebyshev distance -- axis-aligned pads
;; of that size then sit flush (touching, never overlapping); on a
;; straight run this is exactly PADSIZE on center. Returns
;; (parameter center) or nil when the rest of the arc is too short.
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
;; PADSIZE controls the flush spacing of pad rows along concave arcs.
(defun paddle--features (vts padsize / s n i a b c blg pads din dout turn
                             seg theta r cen sa sgn sweep pstart pend
                             cur prev nxt)
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
          (if (< (* s turn) (- *paddle-angtol*)) ; turns away from interior
              (setq pads (cons (list (paddle--2d a) (angle '(0.0 0.0) din) "corner")
                               pads)))))

    ;; --- concave arc segment with radius <= 4'-6" ---
    (if (and (/= blg 0.0)
             (< (* s blg) 0.0)) ; bulges into the interior
        (progn
          (setq seg   (paddle--arcdata (paddle--2d a) (paddle--2d b) blg)
                theta (car seg)
                r     (cadr seg)
                cen   (caddr seg))
          (if (<= r (+ *paddle-maxrad* 1e-6))
              (progn
                (setq sa     (angle cen (paddle--2d a))
                      sgn    (if (> theta 0.0) 1.0 -1.0)
                      sweep  (abs theta)
                      pstart (paddle--arcpt cen r sa)
                      pend   (paddle--arcpt cen r (+ sa (* sgn sweep))))
                (if (<= (paddle--cheb (paddle--sub pend pstart)) padsize)
                    ;; short arc: a single pad centered on the arc
                    (setq pads (cons (list (paddle--arcpt cen r (+ sa (* sgn sweep 0.5)))
                                           0.0 "arc")
                                     pads))
                    ;; longer arc: a flush row of pads -- consecutive
                    ;; centers exactly one pad apart, starting where
                    ;; the arc leaves the wall
                    (progn
                      (setq cur 0.0 prev pstart)
                      (setq pads (cons (list prev 0.0 "arc") pads))
                      (while (setq nxt (paddle--next-flush cen r sa sgn cur sweep prev padsize))
                        (setq cur  (car nxt)
                              prev (cadr nxt))
                        (setq pads (cons (list prev 0.0 "arc") pads)))))))))
    (setq i (1+ i)))
  (reverse pads))

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
  (setq ip  (paddle--sub ctr (paddle--rot delta rot))
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
(defun c:PADDLE (/ *error* doc space kw padsize blkname ss perims vts
                   allpads delta ncorner narc)
  (defun *error* (msg)
    (if doc (vla-EndUndoMark doc))
    (if (and msg (not (wcmatch (strcase msg T) "*break,*cancel*,*exit*")))
        (princ (strcat "\nPADDLE error: " msg)))
    (princ))

  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-Block (vla-get-ActiveLayout doc)))

  (princ (strcat "\nPADDLE - pads at concave perimeter features (R <= "
                 (rtos *paddle-maxrad* 4 0) " and inside corners)."))

  ;; which pad? 2'x2' for normal work, 3'x3' for bigger locations
  (initget "24 36")
  (setq kw      (cond ((getkword "\nPad size in inches [24/36] <24>: ")) ("24"))
        padsize (atof kw)
        blkname (cdr (assoc (atoi kw) *paddle-sizes*)))

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
        (setq ncorner 0 narc 0)
        (foreach pad allpads
          (paddle--insert-pad space blkname (car pad) (cadr pad) delta)
          (if (= (caddr pad) "corner") (setq ncorner (1+ ncorner)) (setq narc (1+ narc))))
        (vla-EndUndoMark doc)
        (if allpads
            (princ (strcat "\nPADDLE: inserted " (itoa (length allpads))
                           " " kw "\" pad(s) on layer \"" *paddle-layer* "\" ("
                           (itoa ncorner) " centered on inside corners, "
                           (itoa narc) " centered along concave arcs)."))
            (princ "\nPADDLE: perimeter checked - no concave features need pads."))))
  (princ))

(princ "\nPADDLE.lsp loaded. Type PADDLE to place 24\" or 36\" pads at concave perimeter features.")
(princ)
