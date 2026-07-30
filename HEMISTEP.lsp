;;; ======================================================================
;;; HEMISTEP.lsp
;;; ----------------------------------------------------------------------
;;; Hemisphere (semicircle) step layout routine.
;;; Written for AutoCAD 2018 (plain AutoLISP + ActiveX for dim styles).
;;;
;;; LOAD:     APPLOAD this file (or drag it into the drawing window).
;;; COMMAND:  HEMISTEP
;;;
;;; WHAT IT DOES
;;;   Draws pool steps that act like chords inside a circle: parallel
;;;   step edges centered on a measuring axis.  What you select decides
;;;   how the axis is found:
;;;
;;;   LINE only ........ the classic base-line mode.  Steps are centered
;;;                      on the middle of the line, run parallel to it,
;;;                      and march perpendicular away from it in a
;;;                      direction you pick.  The hemisphere boundary is
;;;                      drawn for you (see step 6).
;;;   CURVE + LINE ..... inside-out mode with an axis line.  The line
;;;                      (through the curve or ending on it) is where
;;;                      the tread depths are measured from: depths run
;;;                      along the line starting where it meets the
;;;                      curve, going INTO the curve, and the step
;;;                      widths sit perpendicular to the line.
;;;   CURVE only ....... inside-out mode from the middle of the curve.
;;;                      Depths are measured from there going INTO the
;;;                      curve, and the step widths sit along the
;;;                      tangent at that point.
;;;
;;;   A CURVE may be an ARC, a CIRCLE, or a POLYLINE - including a
;;;   composite hemisphere built from several arc segments, and
;;;   including a boundary this command drew earlier.  Each step is
;;;   measured against whichever part of the curve it actually lands
;;;   on, using the opening nearest the axis on each side.
;;;
;;;   In the curve modes the routine holds as true to the curve as it
;;;   can, the same way CORNERSTP holds to the walls: a step width
;;;   within the width tolerance of the curve's opening at that depth is
;;;   snapped to the curve; any other width is held, centered on the
;;;   opening so it breaks the curve equally on both sides.
;;;
;;; WORKFLOW
;;;   1.  Select the base line, the base curve, or the curve plus its
;;;       axis line.
;;;   2.  LINE-only mode asks you to pick a point for the side the
;;;       steps go.  The curve modes assume the steps go into the curve
;;;       and only ask for a side when the geometry is ambiguous.
;;;   3.  You are asked whether to dimension the steps [Yes/No]:
;;;         - Step widths across each chord, nested behind the start of
;;;           the measuring axis (wider steps further out), in dim style
;;;           "SIDE STANDARD".
;;;         - Step depths chained along the axis (start to step 1, step
;;;           1 to step 2, ...), in dim style "STANDARD INCHES".
;;;       If a style is missing the current style is used instead.
;;;   4.  For each step you are asked for the step width, then the step
;;;       depth (measured from the previous step edge - from the start
;;;       of the axis for the first step).  The step is drawn once both
;;;       are given, so the last input is always a depth.
;;;   5.  Enter (or 0) at a width prompt means the steps are done.
;;;       Undo at a width prompt removes the step just drawn (its line
;;;       and its dimensions); Same at a depth prompt repeats the
;;;       previous depth.
;;;   6.  In LINE-only mode you are then asked for one last depth, from
;;;       the last step to the back of the curve, and the curve itself
;;;       is drawn: a polyline of arc segments through each end of each
;;;       step, bulging out to that crown point (the last depth also
;;;       gets the final link of the depth-dim chain).  Enter skips the
;;;       crown and the polyline just chains the step ends.  The curve
;;;       modes skip this - their curve was selected.
;;;
;;; OPTIONAL SETTINGS (set these before running the command)
;;;   *CS-WIDTH-TOL*      width tolerance in drawing units.  When nil
;;;                       (the default) it is 1/8" converted through the
;;;                       drawing's INSUNITS setting.
;;;   *CS-DEPTH-DIMSTYLE* dim style for step-depth dims.
;;;   *CS-WIDTH-DIMSTYLE* dim style for step-width dims.
;;;   *CS-DIM-LAYER*      layer for the dimensions.  When nil (the
;;;                       default) the current layer is used.
;;;
;;; NOTES
;;;   - Geometry is assumed to be drawn in plan view.  The routine warns
;;;     when the current UCS is not World, when selected geometry is not
;;;     flat, and when the current layer is off/frozen/locked.
;;;   - Steps are drawn as LINEs on the current layer.
;;;   - DIMSCALE (or the annotation scale for annotative styles) sets
;;;     the dimension size; grab a dimension line to slide it if it
;;;     lands awkwardly.
;;;   - One U / UNDO reverses the whole command.
;;; ======================================================================

;; Settings - only defined if not already set, so this file and
;; CORNERSTP.lsp stay in sync no matter which one loads first.
(if (not (boundp '*cs-width-tol*))      (setq *cs-width-tol* nil))
(if (not (boundp '*cs-dim-layer*))      (setq *cs-dim-layer* nil))
(if (not (boundp '*cs-depth-dimstyle*)) (setq *cs-depth-dimstyle* "STANDARD INCHES"))
(if (not (boundp '*cs-width-dimstyle*)) (setq *cs-width-dimstyle* "SIDE STANDARD"))

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

;;; ------------------------- vector helpers -----------------------------

(defun hs-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun hs-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun hs-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun hs-dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun hs-unit (v / l)
  (if (> (setq l (sqrt (hs-dot v v))) 1e-10) (hs-scl v (/ 1.0 l))))

(defun hs-perp (v) (list (- (cadr v)) (car v) 0.0))

(defun hs-mid2 (a b) (list (* 0.5 (+ (car a) (car b)))
                           (* 0.5 (+ (cadr a) (cadr b)))
                           0.0))

(defun hs-cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))

;; distance from point P to the segment A-B
(defun hs-ptseg (p a b / d l2 t2)
  (setq d  (hs-vec a b)
        l2 (hs-dot d d))
  (if (< l2 1e-20)
    (distance p a)
    (progn
      (setq t2 (/ (hs-dot (hs-vec a p) d) l2))
      (cond ((< t2 0.0) (distance p a))
            ((> t2 1.0) (distance p b))
            (T (distance p (hs-add a (hs-scl d t2))))))))

;; how far point P lies beyond the ends of segment A-B (0.0 when on it)
(defun hs-beyond (p a b / d l t2)
  (setq d (hs-vec a b)
        l (sqrt (hs-dot d d)))
  (if (< l 1e-10)
    (distance p a)
    (progn
      (setq t2 (/ (hs-dot (hs-vec a p) d) (* l l)))
      (cond ((< t2 0.0) (* (- t2) l))
            ((> t2 1.0) (* (- t2 1.0) l))
            (T 0.0)))))

;; point on a circle: center C, radius R, angle A
(defun hs-arcpt (c r a)
  (list (+ (car c) (* r (cos a))) (+ (cadr c) (* r (sin a))) 0.0))

;; T when angle A lies on the counterclockwise span A1 -> A2
(defun hs-inspan (a a1 a2 / e)
  (setq e (- a2 a1))
  (if (< e 0.0) (setq e (+ e pi pi)))
  (setq a (- a a1))
  (if (< a 0.0) (setq a (+ a pi pi)))
  (<= a (+ e 1e-6)))

;;; ------------------------ curve description ---------------------------
;;; The selected curve becomes a list of boundary "pieces":
;;;   ("A" center radius startang endang)   arc, counterclockwise
;;;   ("S" p1 p2)                           straight segment
;;; so an arc, a circle and a multi-arc polyline are all handled alike.

;; intersections of the circle (C,R) with the infinite line through A
;; along the UNIT direction D; a list of 0 or 2 points
(defun hs-linecirc (a d c r / f g disc)
  (setq f    (hs-vec c a)
        g    (hs-dot d f)
        disc (+ (* r r) (- (* g g) (hs-dot f f))))
  (if (>= disc 0.0)
    (progn
      (setq disc (sqrt disc))
      (list (hs-add a (hs-scl d (- (- g) disc)))
            (hs-add a (hs-scl d (+ (- g) disc)))))))

;; Arc piece from an ARC entity.  Built from the curve's own start/mid/
;; end points and its OCS center, so mirrored arcs are handled.
(defun hs-arcpiece (en / ed c r sp ep mp a1 a2 sw)
  (setq ed (entget en)
        c  (trans (cdr (assoc 10 ed)) en 0)
        r  (cdr (assoc 40 ed))
        sp (vlax-curve-getstartpoint en)
        ep (vlax-curve-getendpoint en)
        mp (vlax-curve-getpointatdist
             en (* 0.5 (vlax-curve-getdistatparam
                         en (vlax-curve-getendparam en))))
        a1 (angle c sp)
        a2 (angle c ep))
  (if (not (hs-inspan (angle c mp) a1 a2))
    (setq sw a1 a1 a2 a2 sw))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list "A" c r a1 a2))

;; Arc piece for a polyline bulge segment P1 -> P2
(defun hs-bulgepiece (p1 p2 b / th l r h nrm cen a1 a2)
  (setq th  (* 4.0 (atan b))
        l   (distance p1 p2)
        r   (abs (/ l (* 2.0 (sin (/ th 2.0)))))
        h   (* r (cos (/ (abs th) 2.0)))
        nrm (hs-unit (hs-perp (hs-vec p1 p2)))
        cen (hs-add (hs-mid2 p1 p2)
                    (hs-scl nrm (if (> b 0.0) h (- h)))))
  (if (> b 0.0)
    (setq a1 (angle cen p1) a2 (angle cen p2))
    (setq a1 (angle cen p2) a2 (angle cen p1)))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list "A" cen r a1 a2))

;; Pieces of a POLYLINE (LWPOLYLINE or heavy 2D), points brought to WCS
(defun hs-plpieces (en / ed el cl vs bs i m out v1 v2 b sub pr)
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
          v2 (nth (rem (1+ i) m) vs)
          b  (nth i bs))
    (if (> (distance v1 v2) 1e-10)
      (setq out (cons (if (equal 0.0 b 1e-9)
                        (list "S" v1 v2)
                        (hs-bulgepiece v1 v2 b))
                      out)))
    (setq i (1+ i)))
  (reverse out))

;; every crossing of the line (P along unit U) with the curve, as a list
;; of (point . piece) pairs
(defun hs-hits (p u pieces / out q pc)
  (foreach pc pieces
    (if (= "A" (car pc))
      (foreach q (hs-linecirc p u (cadr pc) (caddr pc))
        (if (hs-inspan (angle (cadr pc) q) (cadddr pc) (nth 4 pc))
          (setq out (cons (cons q pc) out))))
      (progn
        (setq q (inters p (hs-add p u) (cadr pc) (caddr pc) nil))
        (if (and q (< (hs-beyond q (cadr pc) (caddr pc)) 1e-8))
          (setq out (cons (cons q pc) out))))))
  out)

;; The curve's opening across P along U: the nearest crossing on each
;; side of P, as (h1 h2 width).  nil when the curve does not bracket P.
(defun hs-open (p u pieces / s sp sn h1 h2 hp)
  (foreach hp (hs-hits p u pieces)
    (setq s (hs-dot (hs-vec p (car hp)) u))
    (cond
      ((> s 1e-9)  (if (or (null sp) (< s sp)) (setq sp s h1 (car hp))))
      ((< s -1e-9) (if (or (null sn) (> s sn)) (setq sn s h2 (car hp))))))
  (if (and h1 h2) (list h1 h2 (- sp sn))))

;;; ---------------------- boundary polyline output ----------------------

;; center of the circle through three points, nil if collinear
(defun hs-circum (a b q / ax ay bx by qx qy d)
  (setq ax (car a) ay (cadr a)
        bx (car b) by (cadr b)
        qx (car q) qy (cadr q)
        d  (* 2.0 (+ (* ax (- by qy)) (* bx (- qy ay)) (* qx (- ay by)))))
  (if (> (abs d) 1e-12)
    (list (/ (+ (* (+ (* ax ax) (* ay ay)) (- by qy))
                (* (+ (* bx bx) (* by by)) (- qy ay))
                (* (+ (* qx qx) (* qy qy)) (- ay by)))
             d)
          (/ (+ (* (+ (* ax ax) (* ay ay)) (- qx bx))
                (* (+ (* bx bx) (* by by)) (- ax qx))
                (* (+ (* qx qx) (* qy qy)) (- bx ax)))
             d)
          0.0)))

;; polyline bulge for the arc A->B on the circle centered O
(defun hs-segb (a b o ccw / t1 t2 th)
  (setq t1 (angle o a)
        t2 (angle o b)
        th (if ccw (- t2 t1) (- t1 t2)))
  (if (< th 0.0) (setq th (+ th pi pi)))
  (* (if ccw 1.0 -1.0) (/ (sin (/ th 4.0)) (cos (/ th 4.0)))))

;; Bulges for a polyline through PTS, one per segment, by fitting a
;; circle through each consecutive triple (a chain of 3-point arcs).
(defun hs-blgs (pts / m i p q s o ccw out)
  (setq m (1- (length pts)) i 0)
  (while (< i m)
    (cond
      ((<= (+ i 2) m)
       (setq p (nth i pts) q (nth (1+ i) pts) s (nth (+ i 2) pts)
             o (hs-circum p q s))
       (if o
         (progn
           (setq ccw (> (hs-cross (hs-vec p q) (hs-vec p s)) 0.0))
           (setq out (append out (list (hs-segb p q o ccw)
                                       (hs-segb q s o ccw)))))
         (setq out (append out (list 0.0 0.0))))
       (setq i (+ i 2)))
      ((> i 0)
       (setq p (nth (1- i) pts) q (nth i pts) s (nth (1+ i) pts)
             o (hs-circum p q s))
       (if o
         (progn
           (setq ccw (> (hs-cross (hs-vec p q) (hs-vec p s)) 0.0))
           (setq out (append out (list (hs-segb q s o ccw)))))
         (setq out (append out (list 0.0))))
       (setq i (1+ i)))
      (T
       (setq out (append out (list 0.0)))
       (setq i (1+ i)))))
  out)

;; open LWPOLYLINE through PTS with one bulge per segment
(defun hs-mkpoly (pts blgs)
  (entmake (append
             (list '(0 . "LWPOLYLINE")
                   '(100 . "AcDbEntity")
                   '(100 . "AcDbPolyline")
                   (cons 90 (length pts))
                   '(70 . 0))
             (apply 'append
                    (mapcar '(lambda (p b)
                               (list (cons 10 (list (car p) (cadr p)))
                                     (cons 42 b)))
                            pts
                            (append blgs '(0.0)))))))

;;; ------------------------- drawing helpers ----------------------------

(defun hs-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;; 1/8" expressed in the drawing's units (INSUNITS); inches if unitless
(defun hs-autotol ( / iu)
  (setq iu (getvar "INSUNITS"))
  (cond ((= iu 1) 0.125)            ; inches
        ((= iu 2) (/ 0.125 12.0))   ; feet
        ((= iu 4) 3.175)            ; millimeters
        ((= iu 5) 0.3175)           ; centimeters
        ((= iu 6) 0.003175)         ; meters
        (T        0.125)))          ; unitless - assume inches

(defun hs-tolerance ( )
  (if (numberp *cs-width-tol*) *cs-width-tol* (hs-autotol)))

;; annotation text height in drawing units; DIMSCALE is 0 for
;; annotative dim styles, where the annotation scale governs instead
(defun hs-txth ( / h s)
  (setq h (getvar "DIMTXT")
        s (getvar "DIMSCALE"))
  (if (or (null s) (<= s 0.0))
    (setq s (cond ((and (getvar "CANNOSCALEVALUE")
                        (> (getvar "CANNOSCALEVALUE") 0.0))
                   (/ 1.0 (getvar "CANNOSCALEVALUE")))
                  (1.0))))
  (if (and h (> (* h s) 0.0)) (* h s) 1.0))

;; T when layer NAME exists and can be drawn on right now
(defun hs-layerok (name / ld f cl)
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
(defun hs-setstyle (name / doc)
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
(defun hs-dim (style a b thru / oldl)
  (hs-setstyle style)
  (if (and *cs-dim-layer* (hs-layerok *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.DIMALIGNED" "_non" (trans a 0 1)
                          "_non" (trans b 0 1)
                          "_non" (trans thru 0 1))
  (if oldl (setvar "CLAYER" oldl)))

;; entities created since MARK (nil = since the drawing was empty)
(defun hs-since (mark / e out)
  (setq e (if mark (entnext mark) (entnext)))
  (while e (setq out (cons e out) e (entnext e)))
  out)

;;; --------------------------- main command -----------------------------

(defun c:HEMISTEP ( / *error* hs-popstep undoflag ss i en ed et zf
                      lin lp1 lp2 pieces arcs cmode sp spc dir u
                      q hp bscr best side pt inref stopf cum n wid dep
                      p op nat cen e1 e2 drawn tol txth offd pprev
                      oldce oldstyle ea eb crown pts reflen lastdep
                      dimflag slog mark scum sP sN sEA sEB rec pc)

  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (hs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (redraw)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nHEMISTEP: " msg)))
    (princ))

  ;; remove the most recently drawn step and roll the state back
  (defun hs-popstep ( / e)
    (if (null slog)
      (progn (princ "\n  Nothing to undo.") nil)
      (progn
        (setq rec (car slog))
        (foreach e (car rec) (if (and e (entget e)) (entdel e)))
        (setq cum   (nth 1 rec)
              pprev (nth 2 rec)
              n     (nth 3 rec)
              ea    (nth 4 rec)
              eb    (nth 5 rec)
              drawn (1- drawn)
              slog  (cdr slog))
        (redraw)
        (princ "\n  Last step removed.")
        T)))

  ;; ---- 0. environment checks -------------------------------------------
  (setq tol  (hs-tolerance)
        txth (hs-txth))
  (if (not (equal (trans '(0.0 0.0 1.0) 1 0 T) '(0.0 0.0 1.0) 1e-8))
    (princ (strcat "\nWARNING: the current UCS is not parallel to the"
                   " World XY plane - results may be skewed.")))
  (if (not (hs-layerok (getvar "CLAYER")))
    (princ (strcat "\nWARNING: the current layer (" (getvar "CLAYER")
                   ") is off, frozen or locked - new steps may not"
                   " appear.")))
  (if (zerop (getvar "INSUNITS"))
    (princ (strcat "\nNote: drawing units are unitless; the width"
                   " tolerance is taken as " (rtos tol) ".")))

  ;; ---- 1. selection ----------------------------------------------------
  (princ (strcat "\nSelect the base line, the base curve (arc, circle or"
                 " polyline), or the curve plus its axis line:"))
  (setq ss (ssget '((0 . "LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE"))))
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
       (if lin
         (progn (princ "\nSelect only ONE line.") (exit)))
       (if (> (abs (- (caddr (cdr (assoc 10 ed)))
                      (caddr (cdr (assoc 11 ed))))) 1e-6)
         (setq zf T))
       (setq lin ed
             lp1 (cdr (assoc 10 ed))
             lp2 (cdr (assoc 11 ed))))
      ((= et "ARC")
       (setq pieces (cons (hs-arcpiece en) pieces)))
      ((= et "CIRCLE")
       (setq pieces (cons (list "A" (trans (cdr (assoc 10 ed)) en 0)
                                (cdr (assoc 40 ed)) 0.0 (+ pi pi))
                          pieces)))
      (T
       (setq pieces (append (hs-plpieces en) pieces)))))
  (if zf
    (princ (strcat "\nWARNING: the selected line is not flat (its ends"
                   " differ in Z) - it is used as seen in plan.")))
  (setq arcs  (vl-remove-if-not '(lambda (pc) (= "A" (car pc))) pieces)
        cmode (if arcs T nil))
  (cond
    ((and (null lin) (null pieces))
     (princ "\nSelect a line and/or a curve.") (exit))
    ((and (null cmode) (null lin))
     (princ (strcat "\nNo arc was selected and there is no base line -"
                    " select an arc, a circle, or the base line."))
     (exit))
    ((and (null cmode) pieces)
     (princ (strcat "\nNote: the selected polyline has no arc segments;"
                    " using the line as the base line."))))
  (if lin
    (setq lp1 (list (car lp1) (cadr lp1) 0.0)
          lp2 (list (car lp2) (cadr lp2) 0.0)))

  ;; ---- 2. measuring axis -----------------------------------------------
  ;; SP  = start point of the axis (depths measured from here)
  ;; DIR = direction the steps march (unit)
  ;; U   = direction the step widths run (unit, perpendicular to DIR)
  (cond

    ;; CURVE selected: steps go INTO the curve
    (cmode
     (if lin
       ;; axis line given: start where the line meets the curve, depths
       ;; run along the line, widths perpendicular to it
       (progn
         (setq dir (hs-unit (hs-vec lp1 lp2)))
         (if (null dir)
           (progn (princ "\nThe selected line has zero length.") (exit)))
         ;; prefer a crossing on the drawn segment, then an arc piece,
         ;; then the crossing nearest the line's far end
         (foreach hp (hs-hits lp1 dir pieces)
           (setq bscr (+ (* 1e6 (hs-ptseg (car hp) lp1 lp2))
                         (if (= "A" (car (cdr hp))) 0.0 1e3)
                         (* 1e-3 (distance (car hp) lp2))))
           (if (or (null sp) (< bscr best))
             (setq sp (car hp) spc (cdr hp) best bscr)))
         (if (null sp)
           (progn (princ "\nThe line does not reach the curve.") (exit)))
         (setq inref (if (= "A" (car spc)) (cadr spc)))
         (if inref
           (progn
             (if (< (abs (hs-dot dir (hs-vec sp inref))) 1e-9)
               (progn (princ (strcat "\nThe line is tangent to the curve"
                                     " - cannot tell which way is into it."))
                      (exit)))
             (if (< (hs-dot dir (hs-vec sp inref)) 0.0)
               (setq dir (hs-scl dir -1.0))))
           ;; the line lands on a straight part - ask which way to go
           (progn
             (princ "\nThe line meets a straight part of the curve.")
             (while (null side)
               (setq pt (getpoint (trans sp 0 1)
                          "\nPick a point on the side the steps go: "))
               (if (null pt)
                 (progn (princ "\nNo direction picked - nothing drawn.")
                        (exit)))
               (setq side (hs-dot (hs-vec sp (trans pt 1 0)) dir))
               (if (< (abs side) 1e-10)
                 (progn (princ "\nThat point is square to the line - pick again.")
                        (setq side nil))))
             (if (< side 0.0) (setq dir (hs-scl dir -1.0)))))
         (princ "\nMeasuring from where the line meets the curve, into the curve."))
       ;; no axis line
       (if (= 1 (length arcs))
         ;; a single arc: start at its middle, widths along the tangent
         (progn
           (setq spc (car arcs)
                 sp  (hs-arcpt (cadr spc) (caddr spc)
                               (* 0.5 (+ (cadddr spc) (nth 4 spc))))
                 dir (hs-unit (hs-vec sp (cadr spc))))
           (princ "\nMeasuring from the middle of the arc, into the curve."))
         ;; a composite curve: too many arcs to guess a middle
         (progn
           (while (null sp)
             (setq pt (getpoint
                        "\nPick the point on the curve to measure from: "))
             (if (null pt)
               (progn (princ "\nNothing picked - nothing drawn.") (exit)))
             (setq pt   (trans pt 1 0)
                   best nil)
             (foreach pc arcs                    ; nearest arc piece
               (setq bscr (abs (- (distance (cadr pc) pt) (caddr pc))))
               (if (or (null best) (< bscr best)) (setq best bscr spc pc)))
             (setq sp  (hs-arcpt (cadr spc) (caddr spc)
                                 (angle (cadr spc) pt))
                   dir (hs-unit (hs-vec sp (cadr spc)))))
           (princ "\nMeasuring from the picked point on the curve, into the curve."))))
     (setq u (hs-unit (hs-perp dir))))

    ;; LINE only: the classic base-line mode
    (T
     (setq sp (hs-mid2 lp1 lp2)
           u  (hs-unit (hs-vec lp1 lp2)))
     (if (null u)
       (progn (princ "\nThe selected line has zero length.") (exit)))
     (while (null dir)
       (setq pt (getpoint (trans sp 0 1)
                          "\nPick a point on the side the steps go: "))
       (if (null pt)
         (progn (princ "\nNo direction picked - nothing drawn.") (exit)))
       (setq side (hs-dot (hs-vec sp (trans pt 1 0)) (hs-perp u)))
       (if (< (abs side) 1e-10)
         (princ "\nThat point is on the line - pick a point to one side.")
         (setq dir (hs-unit (hs-scl (hs-perp u)
                                    (if (< side 0.0) -1.0 1.0))))))))

  ;; preview the measuring axis and the step direction
  (setq reflen (if lin (distance lp1 lp2) (* 2.0 (caddr (car arcs)))))
  (grdraw (trans sp 0 1)
          (trans (hs-add sp (hs-scl dir (* 0.75 reflen))) 0 1) 4 0)
  (grdraw (trans (hs-add sp (hs-scl u (* 0.25 reflen))) 0 1)
          (trans (hs-add sp (hs-scl u (* -0.25 reflen))) 0 1) 2 0)

  ;; ---- 3. dimension the steps? -----------------------------------------
  (initget "Yes No")
  (setq dimflag (/= "No" (getkword "\nDimension the steps? [Yes/No] <Yes>: ")))
  (if dimflag
    (progn
      (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
      (if (not (tblsearch "DIMSTYLE" *cs-depth-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-depth-dimstyle*
                       "\" not found - step depths use the current style.")))
      (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                       "\" not found - step widths use the current style.")))
      (if (and *cs-dim-layer* (not (hs-layerok *cs-dim-layer*)))
        (princ (strcat "\nNote: dim layer \"" *cs-dim-layer*
                       "\" is missing or not drawable - using the"
                       " current layer.")))))

  ;; ---- 4. widths and depths, chord by chord ----------------------------
  (command "_.UNDO" "_Begin")
  (setq undoflag T cum 0.0 n 1 drawn 0
        pprev sp                        ; depth chain starts at the axis
        offd  (* 2.0 txth)              ; depth-dim offset off the axis
        oldce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)                  ; quiet the dimstyle/dim commands

  (while
    (and (not stopf)
         (progn
           (setq wid 'RETRY)
           (while (eq wid 'RETRY)
             (initget 4 "Undo")         ; no negative; Enter or 0 = done
             (setq wid (getdist (strcat "\nStep " (itoa n)
                                        " - step width [Undo]"
                                        " <Enter = done>: ")))
             (if (= (type wid) 'STR)
               (progn (if (= wid "Undo") (hs-popstep))
                      (setq wid 'RETRY))))
           (and wid (> wid 1e-10))))
    (setq dep 'RETRY)
    (while (eq dep 'RETRY)
      (initget 6 (if lastdep "Same" ""))
      (setq dep (getdist (strcat "\nStep " (itoa n) " - step depth"
                                 (if lastdep " [Same]" "") ": ")))
      (if (= (type dep) 'STR)
        (if (and (= dep "Same") lastdep)
          (setq dep lastdep)
          (setq dep 'RETRY))))
    (if (null dep)
      (progn
        (princ "\nNo depth given - step discarded; finishing.")
        (setq stopf T))
      (progn
        (setq mark (entlast)
              scum cum sP pprev sN n sEA ea sEB eb
              lastdep dep
              cum  (+ cum dep)               ; depth from the start point
              p    (hs-add sp (hs-scl dir cum))
              e1   nil
              e2   nil)
        (if cmode
          ;; hold as true to the curve as the tolerance allows
          (progn
            (setq op  (hs-open p u pieces)
                  nat (if op (caddr op)))
            (if (and nat (<= (abs (- nat wid)) tol))
              (progn
                (setq e1 (car op) e2 (cadr op))
                (princ (strcat "\n  Step " (itoa n) ": curve opening "
                               (rtos nat) " is within " (rtos tol) " of "
                               (rtos wid) " - snapped to the curve.")))
              (progn
                ;; center on the curve's opening so the step breaks it
                ;; equally on both sides; on the axis when there is none
                (setq cen (if op (hs-mid2 (car op) (cadr op)) p)
                      e1  (hs-add cen (hs-scl u (* 0.5 wid)))
                      e2  (hs-add cen (hs-scl u (* -0.5 wid))))
                (princ (strcat "\n  Step " (itoa n) ": width " (rtos wid)
                               " held"
                               (if nat
                                 (strcat " (curve opening " (rtos nat) ")")
                                 " (the curve does not reach this depth)")
                               " - step breaks from the curve.")))))
          ;; classic base-line mode: centered on the axis as given
          (progn
            (setq e1 (hs-add p (hs-scl u (* 0.5 wid)))
                  e2 (hs-add p (hs-scl u (* -0.5 wid))))
            (princ (strcat "\n  Step " (itoa n) ": width " (rtos wid)
                           " at depth " (rtos cum) " from the line."))))
        (if (and e1 e2)
          (progn
            (hs-mkline e1 e2)                  ; the chord (step edge)
            (if (not cmode)                    ; remember the ends for the
              (setq ea (append ea (list e1))   ; boundary polyline
                    eb (append eb (list e2))))
            (if dimflag
              (progn
                ;; step width: across the chord, nested behind the start
                ;; of the axis by half the chord's own width so the
                ;; wider steps sit progressively further out
                (hs-dim *cs-width-dimstyle* e1 e2
                        (hs-add sp
                                (hs-scl dir
                                        (- (+ (* 0.5 (distance e1 e2))
                                              (* 1.5 txth))))))
                ;; step depth: chain link along the axis, from the
                ;; previous step edge (the start for step 1) to here
                (hs-dim *cs-depth-dimstyle* pprev p
                        (hs-add (hs-mid2 pprev p) (hs-scl u offd)))))
            (setq pprev p drawn (1+ drawn)
                  slog  (cons (list (hs-since mark) scum sP sN sEA sEB)
                              slog))))
        (setq n (1+ n)))))

  ;; ---- 5. boundary curve through the step ends (line mode only) --------
  ;; In the curve modes the curve already exists (it was selected); in
  ;; the base-line mode the curve is drawn as a polyline of arc
  ;; segments through each end of each step, bulging out to a crown
  ;; point set by one last depth.
  (if (and (not cmode) (> drawn 0))
    (progn
      (initget 6)
      (setq dep (getdist (strcat "\nDepth from the last step to the back"
                                 " of the curve <Enter = none>: ")))
      (if (and dep (= (type dep) 'REAL))
        (progn
          (setq crown (hs-add sp (hs-scl dir (+ cum dep))))
          (if dimflag                        ; last link of the depth chain
            (hs-dim *cs-depth-dimstyle* pprev crown
                    (hs-add (hs-mid2 pprev crown) (hs-scl u offd))))))
      (setq pts (append ea
                        (if crown (list crown))
                        (reverse eb)))
      (if (> (length pts) 1)
        (progn
          (hs-mkpoly pts (hs-blgs pts))
          (princ "\nBoundary polyline drawn through the step ends.")))))

  ;; ---- 6. done ---------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn)
                   " step(s) drawn, parallel and centered on the axis.")))
  (redraw)
  (if oldstyle (hs-setstyle oldstyle))   ; back to the entry dim style
  (command "_.UNDO" "_End")
  (if oldce (setvar "CMDECHO" oldce))
  (setq undoflag nil)
  (princ))

(princ "\nHEMISTEP.lsp loaded - type HEMISTEP to draw hemisphere steps.")
(princ)
