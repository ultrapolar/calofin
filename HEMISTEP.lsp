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
;;;                      direction you pick.
;;;   ARC + LINE ....... inside-out mode with an axis line.  The line
;;;                      (through the arc or ending on it) is where the
;;;                      tread depths are measured from: depths run
;;;                      along the line starting where it meets the
;;;                      arc, going INTO the curve, and the step widths
;;;                      sit perpendicular to the line.
;;;   ARC only ......... inside-out mode from the middle of the arc.
;;;                      Depths are measured from the arc's midpoint
;;;                      going INTO the curve, and the step widths sit
;;;                      along the tangent of the arc at that point.
;;;
;;;   In the arc modes the routine holds as true to the curve as it
;;;   can, the same way CORNERSTP holds to the walls: a step width
;;;   within 1/8" of the curve's opening at that depth is snapped to
;;;   the arc; any other width is held, centered on the curve's chord
;;;   so it breaks the curve equally on both sides.
;;;
;;; WORKFLOW
;;;   1.  Select the base line, the base arc, or the arc plus its
;;;       axis line.
;;;   2.  LINE-only mode asks you to pick a point for the side the
;;;       steps go.  The arc modes assume the steps go into the curve.
;;;   3.  You are asked whether to dimension the steps [Yes/No]:
;;;         - Step widths across each chord, nested behind the start
;;;           of the measuring axis (wider steps further out), in dim
;;;           style "SIDE STANDARD".
;;;         - Step depths chained along the axis (start to step 1,
;;;           step 1 to step 2, ...), in dim style "STANDARD INCHES".
;;;       If a style is missing the current style is used instead.
;;;   4.  For each step you are asked for the step width, then the
;;;       step depth (measured from the previous step edge - from the
;;;       start of the axis for the first step).  The step is drawn
;;;       once both are given, so the last input is always a depth.
;;;   5.  Enter (or 0) at a width prompt means the steps are done.
;;;   6.  In LINE-only mode you are then asked for one last depth,
;;;       from the last step to the back of the curve, and the curve
;;;       itself is drawn: a polyline of arc segments through each end
;;;       of each step, bulging out to that crown point (the last
;;;       depth also gets the final link of the depth-dim chain).
;;;       Enter skips the crown and the polyline just chains the step
;;;       ends.  The arc modes skip this - their curve was selected.
;;;
;;; NOTES
;;;   - The 1/8" width tolerance assumes the drawing unit is INCHES.
;;;   - Geometry is assumed to be drawn in plan view in the WCS.
;;;   - Steps are drawn as LINEs on the current layer.
;;;   - DIMSCALE sets the dimension size; grab a dimension line to
;;;     slide it if it lands awkwardly.
;;;   - One U / UNDO reverses the whole command.
;;; ======================================================================

;; Shared settings (also used by CORNERSTP.lsp when both are loaded -
;; whichever file loads first defines them, so they stay in sync).
;; Width tolerance: left nil here so CORNERSTP.lsp can auto-detect it
;; from INSUNITS when both files are loaded; falls back to 1/8" below.
(if (not (boundp '*cs-width-tol*)) (setq *cs-width-tol* nil))
(if (null *cs-depth-dimstyle*)
  (setq *cs-depth-dimstyle* "STANDARD INCHES")) ; for step-depth dims
(if (null *cs-width-dimstyle*)
  (setq *cs-width-dimstyle* "SIDE STANDARD"))   ; for step-width dims

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

;;; ------------------------- small helpers ------------------------------

(defun hs-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun hs-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun hs-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun hs-dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun hs-unit (v / l)
  (if (> (setq l (sqrt (hs-dot v v))) 1e-10) (hs-scl v (/ 1.0 l))))

(defun hs-perp (v) (list (- (cadr v)) (car v) 0.0))

(defun hs-mid2 (a b) (mapcar '(lambda (x y) (* 0.5 (+ x y))) a b))

(defun hs-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;; point on a circle: center C, radius R, angle A
(defun hs-arcpt (c r a)
  (list (+ (car c) (* r (cos a))) (+ (cadr c) (* r (sin a))) 0.0))

;; intersections of the circle (C,R) with the infinite line through A
;; along the UNIT direction D; a list of 0 or 2 points
(defun hs-linecirc (a d c r / f g disc)
  (setq f    (hs-vec c a)              ; A relative to the center
        g    (hs-dot d f)
        disc (+ (* r r) (- (* g g) (hs-dot f f))))
  (if (>= disc 0.0)
    (progn
      (setq disc (sqrt disc))
      (list (hs-add a (hs-scl d (- (- g) disc)))
            (hs-add a (hs-scl d (+ (- g) disc)))))))

;; T if point P (assumed on the circle) lies on the arc span A1->A2 CCW
(defun hs-onarc (p c a1 a2 / an)
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (setq an (angle c p))
  (if (< an (- a1 1e-6)) (setq an (+ an pi pi)))
  (<= an (+ a2 1e-6)))

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

(defun hs-cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))

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

;; polyline bulge for the arc A->B on the circle centered O, going
;; counterclockwise when CCW is T (bulge = tan of a quarter of the
;; included angle, negative for clockwise)
(defun hs-segb (a b o ccw / t1 t2 th)
  (setq t1 (angle o a)
        t2 (angle o b)
        th (if ccw (- t2 t1) (- t1 t2)))
  (if (< th 0.0) (setq th (+ th pi pi)))
  (* (if ccw 1.0 -1.0) (/ (sin (/ th 4.0)) (cos (/ th 4.0)))))

;; Bulges for a polyline through PTS, one per segment, built by fitting
;; a circle through each consecutive triple of points (the same way a
;; chain of 3-point arcs is drawn).  Straight (0) where collinear.
(defun hs-blgs (pts / m i p q s o ccw out)
  (setq m (1- (length pts)) i 0)
  (while (< i m)
    (cond
      ;; a full triple ahead: this circle carries the next two segments
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
      ;; one leftover segment: reuse the circle of the last triple
      ((> i 0)
       (setq p (nth (1- i) pts) q (nth i pts) s (nth (1+ i) pts)
             o (hs-circum p q s))
       (if o
         (progn
           (setq ccw (> (hs-cross (hs-vec p q) (hs-vec p s)) 0.0))
           (setq out (append out (list (hs-segb q s o ccw)))))
         (setq out (append out (list 0.0))))
       (setq i (1+ i)))
      ;; a two-point polyline: just a straight segment
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
;; passing through THRU.  "_non" disables running osnap for each point.
(defun hs-dim (style a b thru)
  (hs-setstyle style)
  (command "_.DIMALIGNED" "_non" a "_non" b "_non" thru))

;;; --------------------------- main command -----------------------------

(defun c:HEMISTEP ( / *error* undoflag ss i ed lin lp1 lp2 arcd amode
                      c r a1 a2 m sp dir u dchk cand best bscr q q1 q2
                      side pt stopf cum n wid dep p nat cen e1 e2 drawn tol
                      dimflag txth offd pprev oldce oldstyle
                      ea eb crown pts)

  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (hs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nHEMISTEP: " msg)))
    (princ))

  ;; ---- 1. selection ---------------------------------------------------
  ;; width tolerance: the shared setting when set, else 1/8"
  (setq tol (if (numberp *cs-width-tol*) *cs-width-tol* 0.125))

  (princ "\nSelect the base line, the base arc, or the arc plus its axis line:")
  (setq ss (ssget '((0 . "LINE,ARC"))))
  (if (null ss)
    (progn (princ "\nNothing selected.") (exit)))
  (setq i 0)
  (repeat (sslength ss)
    (setq ed (entget (ssname ss i))
          i  (1+ i))
    (if (= "LINE" (cdr (assoc 0 ed)))
      (if lin
        (progn (princ "\nSelect only ONE line.") (exit))
        (setq lin ed))
      (if arcd
        (progn (princ "\nSelect only ONE arc.") (exit))
        (setq arcd ed))))
  (if lin
    (setq lp1 (cdr (assoc 10 lin))
          lp2 (cdr (assoc 11 lin))))
  (setq amode (if arcd T nil))
  (if (and (null lin) (null arcd))
    (progn (princ "\nSelect a line and/or an arc.") (exit)))

  ;; ---- 2. measuring axis ----------------------------------------------
  ;; SP  = start point of the axis (depths measured from here)
  ;; DIR = direction the steps march (unit)
  ;; U   = direction the step widths run (unit, perpendicular to DIR)
  (cond

    ;; ARC selected: steps go INTO the curve
    (amode
     (setq c  (cdr (assoc 10 arcd))
           r  (cdr (assoc 40 arcd))
           a1 (cdr (assoc 50 arcd))
           a2 (cdr (assoc 51 arcd)))
     (if (< a2 a1) (setq a2 (+ a2 pi pi)))
     (setq m (hs-arcpt c r (* 0.5 (+ a1 a2)))) ; middle of the arc
     (if lin
       ;; axis line given: start where the line meets the arc, depths
       ;; run along the line, widths perpendicular to it
       (progn
         (setq dir (hs-unit (hs-vec lp1 lp2)))
         (if (null dir)
           (progn (princ "\nThe selected line has zero length.") (exit)))
         (foreach q (hs-linecirc lp1 dir c r)
           (if (hs-onarc q c a1 a2)
             (progn
               ;; prefer a crossing on/near the segment, then the one
               ;; nearest the middle of the arc
               (setq bscr (+ (* 1e6 (hs-ptseg q lp1 lp2)) (distance q m)))
               (if (or (null sp) (< bscr best))
                 (setq sp q best bscr)))))
         (if (null sp)
           (progn (princ "\nThe line does not reach the arc.") (exit)))
         (setq dchk (hs-dot dir (hs-vec sp c)))
         (if (< (abs dchk) 1e-9)
           (progn (princ "\nThe line runs along the curve - cannot tell which way is into it.")
                  (exit)))
         (if (< dchk 0.0) (setq dir (hs-scl dir -1.0)))
         (princ "\nMeasuring from where the line meets the arc, into the curve."))
       ;; no axis line: start at the middle of the arc, widths along
       ;; the tangent of the arc at that point
       (progn
         (setq sp  m
               dir (hs-unit (hs-vec m c)))
         (princ "\nMeasuring from the middle of the arc, into the curve.")))
     (setq u (hs-unit (hs-perp dir))))

    ;; LINE only: the classic base-line mode
    (T
     (setq sp (hs-mid2 lp1 lp2)
           u  (hs-unit (hs-vec lp1 lp2)))
     (if (null u)
       (progn (princ "\nThe selected line has zero length.") (exit)))
     (while (null dir)
       (setq pt (getpoint sp "\nPick a point on the side the steps go: "))
       (if (null pt)
         (progn (princ "\nNo direction picked - nothing drawn.") (exit)))
       (setq side (hs-dot (hs-vec sp pt) (hs-perp u)))
       (if (< (abs side) 1e-10)
         (princ "\nThat point is on the line - pick a point to one side.")
         (setq dir (hs-unit (hs-scl (hs-perp u)
                                    (if (< side 0.0) -1.0 1.0))))))))

  ;; ---- 3. dimension the steps? ----------------------------------------
  (initget "Yes No")
  (setq dimflag (/= "No" (getkword "\nDimension the steps? [Yes/No] <Yes>: ")))
  ;; annotation text height in drawing units, used to space the dims
  (setq txth (* (getvar "DIMTXT") (getvar "DIMSCALE")))
  (if (<= txth 0.0) (setq txth 1.0))
  (if dimflag
    (progn
      (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
      (if (not (tblsearch "DIMSTYLE" *cs-depth-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-depth-dimstyle*
                       "\" not found - step depths use the current style.")))
      (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                       "\" not found - step widths use the current style.")))))

  ;; ---- 4. widths and depths, chord by chord ---------------------------
  (command "_.UNDO" "_Begin")
  (setq undoflag T cum 0.0 n 1 drawn 0
        pprev sp                        ; depth chain starts at the axis
        offd  (* 2.0 txth)              ; depth-dim offset off the axis
        oldce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)                  ; quiet the dimstyle/dim commands

  (while
    (and (not stopf)
         (progn
           (initget 4) ; no negative; Enter or 0 = done
           (setq wid (getdist (strcat "\nStep " (itoa n)
                                      " - step width <Enter = done>: ")))
           (and wid (> wid 1e-10))))
    (initget 6) ; depth must be a positive distance
    (setq dep (getdist (strcat "\nStep " (itoa n) " - step depth: ")))
    (if (null dep)
      (progn
        (princ "\nNo depth given - step discarded; finishing.")
        (setq stopf T))
      (progn
        (setq cum (+ cum dep)                  ; depth from the start point
              p   (hs-add sp (hs-scl dir cum))
              e1  nil
              e2  nil)
        (if amode
          ;; hold as true to the curve as the tolerance allows
          (progn
            (setq q   (hs-linecirc p u c r)
                  q1  (car q)
                  q2  (cadr q)
                  nat (if (and q1 q2
                               (hs-onarc q1 c a1 a2)
                               (hs-onarc q2 c a1 a2))
                        (distance q1 q2)))     ; curve opening here
            (if (and nat (<= (abs (- nat wid)) tol))
              (progn
                (setq e1 q1 e2 q2)
                (princ (strcat "\n  Step " (itoa n) ": curve opening "
                               (rtos nat) " is within " (rtos tol) " of "
                               (rtos wid) " - snapped to the curve.")))
              (progn
                ;; center on the circle's chord so the step breaks the
                ;; curve equally on both sides; on the axis otherwise
                (setq cen (if (and q1 q2) (hs-mid2 q1 q2) p)
                      e1  (hs-add cen (hs-scl u (* 0.5 wid)))
                      e2  (hs-add cen (hs-scl u (* -0.5 wid))))
                (princ (strcat "\n  Step " (itoa n) ": width " (rtos wid)
                               " held"
                               (if nat
                                 (strcat " (curve opening " (rtos nat) ")")
                                 "")
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
            (if (not amode)                    ; remember the ends for the
              (setq ea (append ea (list e1))   ; boundary polyline
                    eb (append eb (list e2))))
            (if dimflag
              (progn
                ;; step width: across the chord, nested behind the
                ;; start of the axis by half the chord's own width so
                ;; the wider steps sit progressively further out
                (hs-dim *cs-width-dimstyle* e1 e2
                        (hs-add sp
                                (hs-scl dir
                                        (- (+ (* 0.5 (distance e1 e2))
                                              (* 1.5 txth))))))
                ;; step depth: chain link along the axis, from the
                ;; previous step edge (the start for step 1) to here
                (hs-dim *cs-depth-dimstyle* pprev p
                        (hs-add (hs-mid2 pprev p) (hs-scl u offd)))))
            (setq pprev p drawn (1+ drawn))))
        (setq n (1+ n)))))

  ;; ---- 5. boundary curve through the step ends (line mode only) -------
  ;; In the arc modes the curve already exists (it was selected); in
  ;; the base-line mode the curve is drawn as a polyline of arc
  ;; segments through each end of each step, bulging out to a crown
  ;; point set by one last depth.
  (if (and (not amode) (> drawn 0))
    (progn
      (initget 6)
      (setq dep (getdist (strcat "\nDepth from the last step to the back"
                                 " of the curve <Enter = none>: ")))
      (if dep
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
  (if oldstyle (hs-setstyle oldstyle))   ; back to the entry dim style
  (command "_.UNDO" "_End")
  (if oldce (setvar "CMDECHO" oldce))
  (setq undoflag nil)
  (princ))

(princ "\nHEMISTEP.lsp loaded - type HEMISTEP to draw hemisphere steps.")
(princ)
