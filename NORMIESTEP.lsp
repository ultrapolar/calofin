;;; ======================================================================
;;; NORMIESTEP.lsp
;;; ----------------------------------------------------------------------
;;; The most normal, boring pool steps of all time: straight, parallel
;;; treads of one constant width.
;;; Written for AutoCAD 2018 (plain AutoLISP + ActiveX for dim styles).
;;;
;;; LOAD:     APPLOAD this file (or drag it into the drawing window).
;;; COMMAND:  NORMIESTEP
;;;
;;; WHAT IT DOES
;;;   Every step is the same width - that is the whole point.  What you
;;;   select decides where the run sits:
;;;
;;;   ONE LINE ......... the steps are CENTERED on that line.  You pick
;;;                      which side they go, give the width once, then
;;;                      the tread depths.
;;;   TWO LINES (a corner)
;;;                      the steps sit against the corner and always run
;;;                      OUTWARD from it.  You are asked which of the two
;;;                      lines the steps run off of - the same line the
;;;                      recess offset is measured on; the treads run
;;;                      parallel to it and butt against the other one.
;;;   A "U" ............ the perimeter of the steps is already drawn, so
;;;                      the treads are just filled in: parallel to the
;;;                      base of the U and trimmed to its sides.  No
;;;                      width is asked for - the sides give it.  The U
;;;                      may have corner treatments where the arms meet
;;;                      the base: three lines is a plain U, five lines
;;;                      is one with diagonal (cut) corners, and three
;;;                      lines plus two arcs is one with rounded
;;;                      corners.  Polylines work too, including bulged
;;;                      (rounded) corner segments.  Treads trim to
;;;                      whatever part of the side they land on - arm,
;;;                      diagonal, or arc.
;;;
;;; WORKFLOW
;;;   1.  Select the base line, the two lines of a corner, or a U-shaped
;;;       perimeter (LINEs or the straight segments of a POLYLINE).
;;;   2.  One-line mode asks which side the steps go.  Corner mode asks
;;;       which line the steps run off of.  The U needs neither.
;;;   3.  Unless it is a U, you give the step width ONCE - every step
;;;       gets it - and are asked whether there is a RECESS: the pocket
;;;       the run sits in.  Its corners, where the sides of the pocket
;;;       meet the wall, are then either
;;;         Straight - square, the plain side lines
;;;         Rounded  - a fillet arc, you give the radius
;;;         Diagonal - a 45 degree cut, given as either its Offset back
;;;                    along each line or the length of the Cut itself
;;;                    (each gives the other: cut = offset x root 2)
;;;       Either treatment flares the mouth of the recess by that
;;;       offset.  A U is not asked - its perimeter is already drawn.
;;;   4.  Then tread depths, one per step, each measured FROM THE
;;;       PREVIOUS TREAD (from the base line for the first).  Distances
;;;       read architectural style: a bare number is inches (drawing
;;;       units) and feet-inch entry like 1'4 (= 16") works whatever the
;;;       units setting.
;;;   5.  Enter at a depth prompt = done.  Undo removes the step just
;;;       drawn (its line and its dimensions).  Same repeats the previous
;;;       depth, which is what most runs want.
;;;   6.  The side lines of the run - with the recess corners worked in -
;;;       are drawn for the one-line and corner modes.  In corner mode
;;;       only the outer side is drawn, since the steps run outward from
;;;       the corner and the picked line closes the inner side.  The U
;;;       already has its perimeter.
;;;   7.  Optional dimensions: the depths chained along the run, plus the
;;;       step width once (it is the same for every step).
;;;
;;; OPTIONAL SETTINGS (set these before running the command)
;;;   *CS-WIDTH-TOL*      width tolerance in drawing units.  When nil
;;;                       (the default) it is 1/8" converted through the
;;;                       drawing's INSUNITS setting.
;;;   *CS-DEPTH-DIMSTYLE* dim style for tread-depth dims.
;;;   *CS-WIDTH-DIMSTYLE* dim style for step-width dims.
;;;   *CS-DIM-LAYER*      layer for the dimensions.  When nil (the
;;;                       default) the current layer is used.
;;;
;;; NOTES
;;;   - Geometry is assumed to be drawn in plan view.  The routine warns
;;;     when the current UCS is not World, when a selected line is not
;;;     flat, and when the current layer is off/frozen/locked.
;;;   - Steps are drawn as LINEs on the current layer.
;;;   - One U / UNDO reverses the whole command.
;;; ======================================================================

;; Settings - only defined if not already set, so this file, CORNERSTP
;; and HEMISTEP stay in sync no matter which one loads first.
(if (not (boundp '*cs-width-tol*))      (setq *cs-width-tol* nil))
(if (not (boundp '*cs-dim-layer*))      (setq *cs-dim-layer* nil))
(if (not (boundp '*cs-depth-dimstyle*)) (setq *cs-depth-dimstyle* "STANDARD INCHES"))
(if (not (boundp '*cs-width-dimstyle*)) (setq *cs-width-dimstyle* "SIDE STANDARD"))

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

(setq *ns-version* "v1.2") ; printed on load and at command start so a
                           ; stale APPLOADed copy is easy to spot

;;; ------------------------- vector helpers -----------------------------

(defun ns-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun ns-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun ns-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun ns-dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun ns-unit (v / l)
  (if (> (setq l (sqrt (ns-dot v v))) 1e-10) (ns-scl v (/ 1.0 l))))

(defun ns-perp (v) (list (- (cadr v)) (car v) 0.0))

(defun ns-mid2 (a b) (list (* 0.5 (+ (car a) (car b)))
                           (* 0.5 (+ (cadr a) (cadr b)))
                           0.0))

;; distance from point P to the segment A-B
(defun ns-ptseg (p a b / d l2 t2)
  (setq d  (ns-vec a b)
        l2 (ns-dot d d))
  (if (< l2 1e-20)
    (distance p a)
    (progn
      (setq t2 (/ (ns-dot (ns-vec a p) d) l2))
      (cond ((< t2 0.0) (distance p a))
            ((> t2 1.0) (distance p b))
            (T (distance p (ns-add a (ns-scl d t2))))))))

;; how far point P lies beyond the ends of segment A-B (0.0 when on it)
(defun ns-beyond (p a b / d l t2)
  (setq d (ns-vec a b)
        l (sqrt (ns-dot d d)))
  (if (< l 1e-10)
    (distance p a)
    (progn
      (setq t2 (/ (ns-dot (ns-vec a p) d) (* l l)))
      (cond ((< t2 0.0) (* (- t2) l))
            ((> t2 1.0) (* (- t2 1.0) l))
            (T 0.0)))))

;; endpoint of segment S farther from PT
(defun ns-far (s pt)
  (if (> (distance (car s) pt) (distance (cadr s) pt)) (car s) (cadr s)))

;; nearest segment in SEGS to point PT
(defun ns-nearseg (segs pt / best bd d s)
  (foreach s segs
    (setq d (ns-ptseg pt (car s) (cadr s)))
    (if (or (null best) (< d bd)) (setq best s bd d)))
  best)

;;; --------------------- geometry from entities -------------------------

;; Straight segments of a POLYLINE as (p1 p2 ename), points in WCS.
;; Bulged segments are skipped - this routine is all straight lines.
(defun ns-plsegs (en / ed el cl vs bs i m out v1 v2 pr sub)
  (setq ed (entget en)
        el (cond ((cdr (assoc 38 ed))) (0.0))
        cl (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))))
  (if (= "LWPOLYLINE" (cdr (assoc 0 ed)))
    (foreach pr ed
      (cond
        ((= 10 (car pr))
         (setq vs (cons (trans (list (car (cdr pr)) (cadr (cdr pr)) el) en 0) vs)
               bs (cons 0.0 bs)))
        ((= 42 (car pr))
         (if bs (setq bs (cons (cdr pr) (cdr bs)))))))
    (progn
      (setq sub (entnext en))
      (while (and sub (= "VERTEX" (cdr (assoc 0 (entget sub)))))
        (setq ed  (entget sub)
              vs  (cons (trans (cdr (assoc 10 ed)) en 0) vs)
              bs  (cons (cond ((cdr (assoc 42 ed))) (0.0)) bs)
              sub (entnext sub)))))
  (setq vs (reverse vs) bs (reverse bs) m (length vs) i 0)
  (while (< i (if cl m (1- m)))
    (setq v1 (nth i vs)
          v2 (nth (rem (1+ i) m) vs))
    (if (and (> (distance v1 v2) 1e-10) (equal 0.0 (nth i bs) 1e-9))
      (setq out (cons (list v1 v2 en) out)))
    (setq i (1+ i)))
  (reverse out))

(defun ns-flat (p) (list (car p) (cadr p) 0.0))

;; point on a circle: center C, radius R, angle A
(defun ns-arcpt (c r a)
  (list (+ (car c) (* r (cos a))) (+ (cadr c) (* r (sin a))) 0.0))

;; T when angle A lies on the counterclockwise span A1 -> A2
(defun ns-inspan (a a1 a2 / e)
  (setq e (- a2 a1))
  (if (< e 0.0) (setq e (+ e pi pi)))
  (setq a (- a a1))
  (if (< a 0.0) (setq a (+ a pi pi)))
  (<= a (+ e 1e-6)))

;; intersections of the circle (C,R) with the infinite line through A
;; along the UNIT direction D; a list of 0 or 2 points
(defun ns-linecirc (a d c r / f g disc)
  (setq f    (ns-vec c a)
        g    (ns-dot d f)
        disc (+ (* r r) (- (* g g) (ns-dot f f))))
  (if (>= disc 0.0)
    (progn
      (setq disc (sqrt disc))
      (list (ns-add a (ns-scl d (- (- g) disc)))
            (ns-add a (ns-scl d (+ (- g) disc)))))))

;;; U pieces: every part of a U perimeter as a uniform record so lines
;;; and corner arcs chain and trim alike -
;;;   ("S" p1 p2)                 a straight part
;;;   ("A" p1 p2 center r a1 a2)  a corner arc, counterclockwise

;; arc piece from an ARC entity, normalized from the curve's own
;; start/mid/end points and its OCS center so mirrored arcs behave
(defun ns-arcent (en / ed c r ep mp a1 a2 sw)
  (setq ed (entget en)
        c  (trans (cdr (assoc 10 ed)) en 0)
        r  (cdr (assoc 40 ed))
        ep (vlax-curve-getendpoint en)
        mp (vlax-curve-getpointatdist
             en (* 0.5 (vlax-curve-getdistatparam
                         en (vlax-curve-getendparam en))))
        a1 (angle c (vlax-curve-getstartpoint en))
        a2 (angle c ep))
  (if (not (ns-inspan (angle c mp) a1 a2))
    (setq sw a1 a1 a2 a2 sw))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list "A" (ns-arcpt c r a1) (ns-arcpt c r a2) (ns-flat c) r a1 a2))

;; arc piece from a polyline bulge segment P1 -> P2
(defun ns-bulgepc (p1 p2 b / th l r h nrm cen a1 a2)
  (setq p1  (ns-flat p1)
        p2  (ns-flat p2)
        th  (* 4.0 (atan b))
        l   (distance p1 p2)
        r   (abs (/ l (* 2.0 (sin (/ th 2.0)))))
        h   (* r (cos (/ (abs th) 2.0)))
        nrm (ns-unit (ns-perp (ns-vec p1 p2)))
        cen (ns-add (ns-mid2 p1 p2)
                    (ns-scl nrm (if (> b 0.0) h (- h)))))
  (if (> b 0.0)
    (setq a1 (angle cen p1) a2 (angle cen p2))
    (setq a1 (angle cen p2) a2 (angle cen p1)))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list "A" p1 p2 cen r a1 a2))

;; Bulged segments of a POLYLINE as arc pieces (the straight ones come
;; from ns-plsegs)
(defun ns-plarcs (en / ed el cl vs bs i m out v1 v2 pr sub)
  (setq ed (entget en)
        el (cond ((cdr (assoc 38 ed))) (0.0))
        cl (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))))
  (if (= "LWPOLYLINE" (cdr (assoc 0 ed)))
    (foreach pr ed
      (cond
        ((= 10 (car pr))
         (setq vs (cons (trans (list (car (cdr pr)) (cadr (cdr pr)) el) en 0) vs)
               bs (cons 0.0 bs)))
        ((= 42 (car pr))
         (if bs (setq bs (cons (cdr pr) (cdr bs)))))))
    (progn
      (setq sub (entnext en))
      (while (and sub (= "VERTEX" (cdr (assoc 0 (entget sub)))))
        (setq ed  (entget sub)
              vs  (cons (trans (cdr (assoc 10 ed)) en 0) vs)
              bs  (cons (cond ((cdr (assoc 42 ed))) (0.0)) bs)
              sub (entnext sub)))))
  (setq vs (reverse vs) bs (reverse bs) m (length vs) i 0)
  (while (< i (if cl m (1- m)))
    (setq v1 (nth i vs)
          v2 (nth (rem (1+ i) m) vs))
    (if (and (> (distance v1 v2) 1e-10)
             (not (equal 0.0 (nth i bs) 1e-9)))
      (setq out (cons (ns-bulgepc v1 v2 (nth i bs)) out)))
    (setq i (1+ i)))
  (reverse out))

;; The on-piece hit of the tread line (P along U) nearest to P among
;; SIDE's pieces - the arm, and the corner treatment when there is one.
(defun ns-sidehit (p u side fuzz / best bd q pc)
  (foreach pc side
    (if (= "S" (car pc))
      (progn
        (setq q (inters p (ns-add p u) (cadr pc) (caddr pc) nil))
        (if (and q (< (ns-beyond q (cadr pc) (caddr pc)) fuzz)
                 (or (null best) (< (distance p q) bd)))
          (setq best q bd (distance p q))))
      (foreach q (ns-linecirc p u (nth 3 pc) (nth 4 pc))
        (if (and (ns-inspan (angle (nth 3 pc) q) (nth 5 pc) (nth 6 pc))
                 (or (null best) (< (distance p q) bd)))
          (setq best q bd (distance p q))))))
  best)

;;; ------------------------- setting helpers ----------------------------

;; 1/8" expressed in the drawing's units (INSUNITS); inches if unitless
(defun ns-autotol ( / iu)
  (setq iu (getvar "INSUNITS"))
  (cond ((= iu 1) 0.125)            ; inches
        ((= iu 2) (/ 0.125 12.0))   ; feet
        ((= iu 4) 3.175)            ; millimeters
        ((= iu 5) 0.3175)           ; centimeters
        ((= iu 6) 0.003175)         ; meters
        (T        0.125)))          ; unitless - assume inches

(defun ns-tolerance ( )
  (if (numberp *cs-width-tol*) *cs-width-tol* (ns-autotol)))

;; annotation text height in drawing units; DIMSCALE is 0 for
;; annotative dim styles, where the annotation scale governs instead
(defun ns-txth ( / h s)
  (setq h (getvar "DIMTXT")
        s (getvar "DIMSCALE"))
  (if (or (null s) (<= s 0.0))
    (setq s (cond ((and (getvar "CANNOSCALEVALUE")
                        (> (getvar "CANNOSCALEVALUE") 0.0))
                   (/ 1.0 (getvar "CANNOSCALEVALUE")))
                  (1.0))))
  (if (and h (> (* h s) 0.0)) (* h s) 1.0))

;;; ------------------------- drawing helpers ----------------------------

(defun ns-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;; Fillet arc of radius R about centre O between tangent points T1 and
;; T2.  The minor arc is taken, so a quarter-round comes out as one.
(defun ns-mkfillet (o r t1 t2 / a1 a2 sw)
  (setq a1 (angle o t1)
        a2 (angle o t2)
        sw (- a2 a1))
  (if (< sw 0.0) (setq sw (+ sw pi pi)))
  (if (> sw pi) (setq sw a1 a1 a2 a2 sw))    ; the other way round is shorter
  (entmake (list '(0 . "ARC")
                 (cons 10 (list (car o) (cadr o) 0.0))
                 (cons 40 r)
                 (cons 50 a1)
                 (cons 51 a2))))

;; Draw one side of the run: the recess corner where it meets the wall at
;; E - the wall carries on along WDIR, the run heads along DIR for LEN -
;; and then the side line down to the last tread.
;;   RTYPE nil / "Straight" - a plain side line straight off the wall
;;   "Rounded"              - a fillet arc of radius RRAD
;;   "Diagonal"             - a 45 degree cut, ROFF back along each leg
;; Either treatment flares the mouth of the recess by that offset.
(defun ns-side (e wdir dir len rtype roff rrad / off t1 t2 o)
  (setq off (cond ((and (= rtype "Diagonal") roff) roff)
                  ((and (= rtype "Rounded") rrad) rrad)
                  (0.0)))
  (if (>= off len)
    (progn
      (princ (strcat "\n  Note: the recess corner (" (rtos off)
                     ") is deeper than the whole run (" (rtos len)
                     ") - that side is drawn square."))
      (setq off 0.0 rtype "Straight")))
  (setq t1 (ns-add e (ns-scl wdir off))      ; tangent/cut point on the wall
        t2 (ns-add e (ns-scl dir off)))      ; and on the side of the recess
  (cond
    ((and (= rtype "Diagonal") (> off 0.0))
     (ns-mkline t1 t2))
    ((and (= rtype "Rounded") (> off 0.0))
     ;; centre sits one radius off each leg, so the arc is tangent to both
     (setq o (ns-add t1 (ns-scl dir off)))
     (ns-mkfillet o off t1 t2)))
  (ns-mkline t2 (ns-add e (ns-scl dir len))))

;; T when layer NAME exists and can be drawn on right now
(defun ns-layerok (name / ld f cl)
  (if (setq ld (tblsearch "LAYER" name))
    (progn
      (setq f  (cond ((cdr (assoc 70 ld))) (0))
            cl (cond ((cdr (assoc 62 ld))) (7)))
      (and (zerop (logand 1 f))
           (zerop (logand 4 f))
           (> cl 0)))))

;; make dimension style NAME current, but only if it exists and is not
;; already current.  Uses ActiveX so style names containing spaces are
;; handled correctly (the -DIMSTYLE command would read a space as ENTER).
(defun ns-setstyle (name / doc)
  (if (and (tblsearch "DIMSTYLE" name)
           (/= (strcase name) (strcase (getvar "DIMSTYLE"))))
    (vl-catch-all-apply
      '(lambda ()
         (setq doc (vla-get-activedocument (vlax-get-acad-object)))
         (vla-put-activedimstyle
           doc (vla-item (vla-get-dimstyles doc) name))))))

;; aligned dimension between A and B in dim style STYLE, dim line
;; passing through THRU.  Points are WCS and are translated to the
;; current UCS for the command.  "_non" defeats running osnap.
(defun ns-dim (style a b thru / oldl)
  (ns-setstyle style)
  (if (and *cs-dim-layer* (ns-layerok *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.DIMALIGNED" "_non" (trans a 0 1)
                          "_non" (trans b 0 1)
                          "_non" (trans thru 0 1))
  (if oldl (setvar "CLAYER" oldl)))

;; entities created since MARK (nil = since the drawing was empty)
(defun ns-since (mark / e out)
  (setq e (if mark (entnext mark) (entnext)))
  (while e (setq out (cons e out) e (entnext e)))
  out)

;;; --------------------------- main command -----------------------------

(defun c:NORMIESTEP ( / *error* ns-popstep undoflag ss i en ed et zf
                        segs mode base side arm1 arm2 corner fuzz
                        sp u dir pt s d1 d2 f1 f2 reflen tol txth
                        wid dep n drawn p inn outp e1 e2 bey stopf
                        first1 first2 lastdep dimflag dimoff offd
                        pprev oldce oldstyle oldlu slog mark scum sP sN
                        cum rec rtype roff rrad rcut
                        arcps pieces freep chain cure rest nxt basepc
                        side1 side2 pc qc e)

  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (ns-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlu (setvar "LUNITS" oldlu))
    (redraw)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nNORMIESTEP: " msg)))
    (princ))

  ;; remove the most recently drawn step and roll the state back
  (defun ns-popstep ( / e)
    (if (null slog)
      (progn (princ "\n  Nothing to undo.") nil)
      (progn
        (setq rec (car slog))
        (foreach e (car rec) (if (and e (entget e)) (entdel e)))
        (setq cum   (nth 1 rec)
              pprev (nth 2 rec)
              n     (nth 3 rec)
              drawn (1- drawn)
              slog  (cdr slog))
        (redraw)
        (princ "\n  Last step removed.")
        T)))

  ;; ---- 0. environment checks -------------------------------------------
  (princ (strcat "\nNORMIESTEP " *ns-version*
                 " - every step the same width."))
  (setq tol  (ns-tolerance)
        txth (ns-txth))
  ;; Read distances architectural-style for the whole command: a bare
  ;; number is drawing units (inches in an inch-based drawing) and
  ;; feet-inch entry like 1'4 works whatever LUNITS was set to.
  (setq oldlu (getvar "LUNITS"))
  (setvar "LUNITS" 4)
  (if (not (equal (trans '(0.0 0.0 1.0) 1 0 T) '(0.0 0.0 1.0) 1e-8))
    (princ (strcat "\nWARNING: the current UCS is not parallel to the"
                   " World XY plane - results may be skewed.")))
  (if (not (ns-layerok (getvar "CLAYER")))
    (princ (strcat "\nWARNING: the current layer (" (getvar "CLAYER")
                   ") is off, frozen or locked - new steps may not"
                   " appear.")))

  ;; ---- 1. selection ----------------------------------------------------
  (princ (strcat "\nSelect the base line, the two lines of a corner,"
                 " or a U-shaped step perimeter:"))
  (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE"))))
  (if (null ss)
    (progn (princ "\nNothing selected.") (exit)))
  (setq i 0)
  (repeat (sslength ss)
    (setq en (ssname ss i)
          ed (entget en)
          et (cdr (assoc 0 ed))
          i  (1+ i))
    (cond
      ((= et "LINE")
       (if (> (abs (- (caddr (cdr (assoc 10 ed)))
                      (caddr (cdr (assoc 11 ed))))) 1e-6)
         (setq zf T))
       (setq segs (cons (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)) en)
                        segs)))
      ((= et "ARC")
       (setq arcps (cons (ns-arcent en) arcps)))
      (T
       (setq segs  (append (ns-plsegs en) segs)
             arcps (append (ns-plarcs en) arcps)))))
  (setq segs (reverse segs))
  (if zf
    (princ (strcat "\nWARNING: a selected line is not flat (its ends"
                   " differ in Z) - it is used as seen in plan.")))
  ;; endpoint fuzz for deciding what joins what
  (setq fuzz (max (* 4.0 tol) 1e-6))

  (cond
    ((null segs)
     (princ "\nNo straight lines in the selection.") (exit))
    ((and (= 1 (length segs)) (null arcps)) (setq mode "LINE"))
    ((and (= 2 (length segs)) (null arcps)) (setq mode "CORNER"))
    ;; a U: three straights; five when its corners are cut diagonally;
    ;; three straights plus two arcs when its corners are rounded
    ((and (member (length segs) '(3 5)) (null arcps)) (setq mode "U"))
    ((and (= 3 (length segs)) (= 2 (length arcps)))   (setq mode "U"))
    (T
     (princ (strcat "\nThat selection does not fit - NORMIESTEP takes one"
                    " line, two lines forming a corner, or a U (three"
                    " lines; five with diagonal corners; three lines and"
                    " two arcs with rounded corners)."))
     (exit)))

  ;; ---- 2. work out the run from what was selected ----------------------
  (cond

    ;; ---------- one line: the steps are centered on it ----------
    ((= mode "LINE")
     (setq base (car segs)
           sp   (ns-mid2 (car base) (cadr base))
           u    (ns-unit (ns-vec (car base) (cadr base))))
     (if (null u)
       (progn (princ "\nThe selected line has zero length.") (exit)))
     (while (null dir)
       (setq pt (getpoint (trans sp 0 1)
                          "\nPick a point on the side the steps go: "))
       (if (null pt)
         (progn (princ "\nNo direction picked - nothing drawn.") (exit)))
       (setq d1 (ns-dot (ns-vec sp (trans pt 1 0)) (ns-perp u)))
       (if (< (abs d1) 1e-10)
         (princ "\nThat point is on the line - pick a point to one side.")
         (setq dir (ns-unit (ns-scl (ns-perp u) (if (< d1 0.0) -1.0 1.0))))))
     (princ "\nSteps centered on the line."))

    ;; ---------- two lines: the steps sit against the corner ----------
    ((= mode "CORNER")
     (setq d1     (car segs)
           d2     (cadr segs)
           corner (inters (car d1) (cadr d1) (car d2) (cadr d2) nil))
     (if (null corner)
       (progn (princ "\nThe two lines are parallel - no corner found.")
              (exit)))
     (while (null base)
       (setq pt (getpoint "\nPick the line the steps run OFF OF: "))
       (if (null pt)
         (progn (princ "\nNothing picked - nothing drawn.") (exit)))
       (setq base (ns-nearseg segs (trans pt 1 0))
             side (if (equal base d1) d2 d1)))
     ;; U runs along the base, away from the corner; DIR heads away from
     ;; the base on the side the other line goes
     (setq u   (ns-unit (ns-vec corner (ns-far base corner)))
           dir (ns-unit (ns-vec corner (ns-far side corner))))
     (if (or (null u) (null dir))
       (progn (princ "\nA selected line has zero length.") (exit)))
     ;; keep DIR square to the treads so depths measure true
     (setq dir (ns-unit (ns-scl (ns-perp u)
                                (if (< (ns-dot (ns-perp u) dir) 0.0)
                                  -1.0 1.0)))
           sp  corner)
     (princ (strcat "\nSteps against the corner, running OUTWARD from it"
                    " off the picked line.")))

    ;; ---------- a U: the perimeter is drawn, fill in the treads ----------
    ;; The parts - arms, an optional corner treatment on each side
    ;; (diagonal cut or fillet arc), and the base - are chained end to
    ;; end from one free end to the other; the middle of the chain is
    ;; the base and each half-chain is one side's trimming boundary.
    (T
     (setq pieces (append (mapcar '(lambda (s)
                                     (list "S" (ns-flat (car s))
                                               (ns-flat (cadr s))))
                                  segs)
                          arcps))
     ;; the two free endpoints (shared with nothing) mark the arms
     (foreach pc pieces
       (foreach e (list (cadr pc) (caddr pc))
         (setq d1 0)
         (foreach qc pieces
           (if (not (eq qc pc))
             (progn
               (if (< (distance e (cadr qc)) fuzz) (setq d1 (1+ d1)))
               (if (< (distance e (caddr qc)) fuzz) (setq d1 (1+ d1))))))
         (if (zerop d1) (setq freep (cons (list pc e) freep)))))
     (if (/= 2 (length freep))
       (progn (princ (strcat "\nThose parts do not form a U - they must"
                             " chain end to end with two open ends."))
              (exit)))
     ;; walk the chain from one free end to the other
     (setq arm1 (car (car freep))
           f1   (cadr (car freep))
           chain (list arm1)
           cure  (if (< (distance f1 (cadr arm1)) fuzz)
                   (caddr arm1)
                   (cadr arm1))
           rest  (vl-remove arm1 pieces))
     (while (setq nxt (car (vl-remove-if-not
                             '(lambda (pc)
                                (or (< (distance cure (cadr pc)) fuzz)
                                    (< (distance cure (caddr pc)) fuzz)))
                             rest)))
       (setq chain (append chain (list nxt))
             cure  (if (< (distance cure (cadr nxt)) fuzz)
                     (caddr nxt)
                     (cadr nxt))
             rest  (vl-remove nxt rest)))
     (if rest
       (progn (princ "\nThose parts do not all connect - not a U.")
              (exit)))
     (setq f2     cure                          ; the other free end
           d2     (length chain)
           basepc (nth (/ d2 2) chain))         ; the middle of the chain
     (if (/= "S" (car basepc))
       (progn (princ "\nThe middle of the U (its base) must be straight.")
              (exit)))
     (setq base (list (cadr basepc) (caddr basepc))
           u    (ns-unit (ns-vec (car base) (cadr base)))
           sp   (ns-mid2 f1 f2))                ; the mouth of the U
     ;; each half of the chain is one side's boundary
     (setq i 0)
     (foreach pc chain
       (cond ((< i (/ d2 2)) (setq side1 (cons pc side1)))
             ((> i (/ d2 2)) (setq side2 (cons pc side2))))
       (setq i (1+ i)))
     (setq arm1 (list (cadr (car chain)) (caddr (car chain)))
           arm2 (list (cadr (last chain)) (caddr (last chain))))
     (if (null u)
       (progn (princ "\nThe base of the U has zero length.") (exit)))
     (if (= 5 d2)
       (princ "\nU with corner treatments: treads trim to them."))
     ;; DIR runs from the mouth toward the base, square to the treads
     (setq dir (ns-unit (ns-scl (ns-perp u)
                                (if (< (ns-dot (ns-perp u)
                                               (ns-vec sp (ns-mid2 (car base)
                                                                   (cadr base))))
                                       0.0)
                                  -1.0 1.0))))
     (princ (strcat "\nU perimeter: treads run parallel to its base and"
                    " are trimmed to its arms."))))

  ;; preview the run direction and the tread direction
  (setq reflen (distance (car base) (cadr base)))
  (grdraw (trans sp 0 1)
          (trans (ns-add sp (ns-scl dir (* 0.75 reflen))) 0 1) 4 0)
  (grdraw (trans (ns-add sp (ns-scl u (* 0.4 reflen))) 0 1)
          (trans (ns-add sp (ns-scl u (* -0.4 reflen))) 0 1) 2 0)

  ;; ---- 3. the one width every step gets --------------------------------
  (if (/= mode "U")
    (progn
      (initget 7)                              ; required, no zero/negative
      (setq wid (getdist "\nStep width (the same for every step): "))))

  ;; ---- 3b. a recess at the wall? ----------------------------------------
  ;; The recess is the pocket the run sits in.  Its corners - where the
  ;; sides of the pocket meet the wall - can be square, radiused, or cut
  ;; at 45 degrees.  A U already has its perimeter drawn, so it is not
  ;; asked.
  (if (/= mode "U")
    (progn
      (initget "Yes No")
      (if (= "Yes" (getkword "\nIs there a recess? [Yes/No] <No>: "))
        (progn
          (initget "Straight Rounded Diagonal")
          (setq rtype (cond ((getkword (strcat "\nRecess corners"
                                               " [Straight/Rounded/Diagonal]"
                                               " <Straight>: ")))
                            ("Straight")))
          (cond
            ((= rtype "Rounded")
             (initget 7)
             (setq rrad (getdist "\nCorner radius: ")))
            ((= rtype "Diagonal")
             ;; offset and cut are the two legs and the hypotenuse of the
             ;; same 45 degree triangle, so either one gives the other
             (initget "Offset Cut")
             (if (= "Cut" (getkword
                            (strcat "\nIs the diagonal given as its"
                                    " [Offset/Cut] <Offset>: ")))
               (progn
                 (initget 7)
                 (setq rcut (getdist "\nLength of the diagonal cut: ")
                       roff (/ rcut (sqrt 2.0))))
               (progn
                 (initget 7)
                 (setq roff (getdist "\nOffset back along each line: ")
                       rcut (* roff (sqrt 2.0)))))
             (princ (strcat "\n  45 degree diagonal: offset " (rtos roff)
                            " each way, cut " (rtos rcut) "."))))))))

  ;; ---- 4. dimension the steps? -----------------------------------------
  (initget "Yes No")
  (setq dimflag (/= "No" (getkword "\nDimension the steps? [Yes/No] <Yes>: ")))
  (if dimflag
    (progn
      (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
      (if (not (tblsearch "DIMSTYLE" *cs-depth-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-depth-dimstyle*
                       "\" not found - tread depths use the current style.")))
      (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                       "\" not found - the step width uses the current style.")))
      (if (and *cs-dim-layer* (not (ns-layerok *cs-dim-layer*)))
        (princ (strcat "\nNote: dim layer \"" *cs-dim-layer*
                       "\" is missing or not drawable - using the"
                       " current layer.")))))
  ;; where the depth chain sits, clear of the treads
  (setq offd   (* 2.0 txth)
        dimoff (cond
                 ((= mode "LINE")   (ns-scl u (+ (* 0.5 wid) offd)))
                 ((= mode "CORNER") (ns-scl u (+ wid offd)))
                 (T (ns-scl u (+ (* 0.5 (max (distance f1 f2)
                                             (distance (car base)
                                                       (cadr base))))
                                 offd)))))

  ;; ---- 5. tread depths, one per step -----------------------------------
  (command "_.UNDO" "_Begin")
  (setq undoflag T cum 0.0 n 1 drawn 0
        pprev sp
        oldce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  (while
    (and (not stopf)
         (progn
           (setq dep 'RETRY)
           (while (eq dep 'RETRY)
             (initget 6 (strcat "Undo" (if lastdep " Same" "")))
             (setq dep (getdist
                         (strcat "\nStep " (itoa n)
                                 " - tread depth [Undo"
                                 (if lastdep "/Same" "") "]"
                                 (if lastdep
                                   (strcat " <Enter = done, Same = "
                                           (rtos lastdep) ">: ")
                                   " <Enter = done>: "))))
             (if (= (type dep) 'STR)
               (cond
                 ((= dep "Undo") (ns-popstep) (setq dep 'RETRY))
                 ((= dep "Same")
                  (if lastdep
                    (setq dep lastdep)
                    (progn (princ "\n  No previous depth.")
                           (setq dep 'RETRY))))
                 (T (setq dep 'RETRY)))))
           dep))
    (setq mark (entlast)
          scum cum sP pprev sN n
          lastdep dep
          ;; each tread sits DEP past the PREVIOUS one, never a total
          p    (ns-add pprev (ns-scl dir dep))
          e1   nil
          e2   nil)
    (cond
      ;; centered on the base line
      ((= mode "LINE")
       (setq e1 (ns-add p (ns-scl u (* 0.5 wid)))
             e2 (ns-add p (ns-scl u (* -0.5 wid)))))
      ;; from the side line outward by the width
      ((= mode "CORNER")
       (setq inn (inters p (ns-add p u) (car side) (cadr side) nil))
       (if (null inn)
         (princ (strcat "\n  Step " (itoa n)
                        ": cannot reach the side line - step skipped."))
         (setq e1  inn
               e2  (ns-add inn (ns-scl u wid))
               bey (ns-beyond inn (car side) (cadr side)))))
      ;; trimmed to the sides of the U - arm, diagonal or fillet,
      ;; whichever the tread actually lands on
      (T
       (setq e1  (ns-sidehit p u side1 fuzz)
             e2  (ns-sidehit p u side2 fuzz)
             bey 0.0)
       ;; nothing on-piece on a side: fall back to the arm extended
       (if (null e1)
         (progn
           (setq e1 (inters p (ns-add p u) (car arm1) (cadr arm1) nil))
           (if e1 (setq bey (ns-beyond e1 (car arm1) (cadr arm1))))))
       (if (null e2)
         (progn
           (setq e2 (inters p (ns-add p u) (car arm2) (cadr arm2) nil))
           (if e2 (setq bey (max bey (ns-beyond e2 (car arm2)
                                                (cadr arm2)))))))
       (cond
         ((or (null e1) (null e2))
          (princ (strcat "\n  Step " (itoa n)
                         ": cannot reach both sides - step skipped."))
          (setq e1 nil e2 nil))
         ;; past the base of the U: the run is full
         ((< (ns-dot (ns-vec p (ns-mid2 (car base) (cadr base))) dir) 0.0)
          (princ (strcat "\n  Step " (itoa n) " would fall past the base"
                         " of the U - stopping."))
          (setq e1 nil e2 nil stopf T)))))
    (if (and e1 e2)
      (progn
        (setq cum (+ cum dep))
        (if (and bey (> bey 1e-6))
          (princ (strcat "\n    (note: a line had to be extended "
                         (rtos bey) " to meet this tread)")))
        (ns-mkline e1 e2)
        (princ (strcat "\n  Step " (itoa n) ": width " (rtos (distance e1 e2))
                       ", " (rtos dep) " past the previous tread ("
                       (rtos cum) " from the start)."))
        (if (null first1) (setq first1 e1 first2 e2))
        (if dimflag
          (ns-dim *cs-depth-dimstyle* pprev p
                  (ns-add (ns-mid2 pprev p) dimoff)))
        (setq pprev p drawn (1+ drawn)
              slog  (cons (list (ns-since mark) scum sP sN) slog))))
    (setq n (1+ n)))

  ;; ---- 6. sides of the run (with the recess corners) and the width dim -
  (if (> drawn 0)
    (progn
      (cond
        ;; both sides of a centered run; the wall carries on outward
        ;; past each edge, so WDIR is +u on one side and -u on the other
        ((= mode "LINE")
         (ns-side (ns-add sp (ns-scl u (* 0.5 wid)))
                  u dir cum rtype roff rrad)
         (ns-side (ns-add sp (ns-scl u (* -0.5 wid)))
                  (ns-scl u -1.0) dir cum rtype roff rrad))
        ;; the outer side only - the steps run outward from the corner,
        ;; so the picked line closes the inner side already
        ((= mode "CORNER")
         (ns-side (ns-add corner (ns-scl u wid))
                  u dir cum rtype roff rrad)))
      (if dimflag
        (ns-dim *cs-width-dimstyle* first1 first2
                (ns-add sp (ns-scl dir (- (+ (* 0.5 (distance first1 first2))
                                             (* 1.5 txth)))))))))

  ;; ---- 7. done ---------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn) " step(s) drawn"
                   (if (/= mode "U")
                     (strcat ", all " (rtos wid) " wide")
                     " between the arms of the U")
                   ".")))
  (redraw)
  (if oldstyle (ns-setstyle oldstyle))
  (command "_.UNDO" "_End")
  (if oldce (setvar "CMDECHO" oldce))
  (if oldlu (setvar "LUNITS" oldlu))
  (setq undoflag nil)
  (princ))

(princ (strcat "\nNORMIESTEP.lsp " *ns-version*
               " loaded - type NORMIESTEP to draw plain steps."))
(princ)
