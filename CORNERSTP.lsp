;;; ======================================================================
;;; CORNERSTP.lsp
;;; ----------------------------------------------------------------------
;;; Corner step layout routine for swimming-pool corners.
;;; Written for AutoCAD 2018 (plain AutoLISP - no VLX/.NET dependencies).
;;;
;;; LOAD:     APPLOAD this file (or drag it into the drawing window).
;;; COMMAND:  CORNERSTP
;;;
;;; WHAT IT DOES
;;;   Draws a run of parallel corner steps (tread edges) fanning out from
;;;   a pool corner toward the pool.  Tread depths are always held
;;;   exactly; step widths are held to within 1/8" of the wall opening.
;;;
;;; WORKFLOW
;;;   1.  Select the two wall LINEs that form the corner.  A corner
;;;       diagonal (chamfer LINE) or a fillet ARC may be included in the
;;;       same selection.
;;;   2.  If the two wall lines intersect at a point, that intersection
;;;       is the starting point.
;;;   3.  Choose the draw direction [Inside out/Outside in]:
;;;         INSIDE OUT (default) - steps are built from the corner out
;;;         toward the pool from given tread depths and step widths.
;;;         OUTSIDE IN - the furthest (outermost) step is placed first
;;;         from its given width, bounded to the provided walls, and
;;;         the remaining steps walk back in toward the corner.
;;;
;;;   INSIDE OUT:
;;;   4a. If a diagonal/arc was selected, you are asked whether tread
;;;       depths are measured from the Middle of the diagonal/arc or
;;;       from the True corner.  The true corner is found by extending
;;;       the two wall lines surrounding the diagonal/arc to their
;;;       apparent intersection.
;;;   4b. If a diagonal LINE was selected you are also asked whether the
;;;       treads run Parallel to the diagonal, or perpendicular to the
;;;       bisector of the TRUE ANGLE the walls make (equal angle from
;;;       both wall lines).  With no diagonal the true-angle bisector is
;;;       always used.  Tread depths are measured from the starting
;;;       point toward the pool, square to the treads, so all steps are
;;;       parallel to each other either way.
;;;   4c. For each step you are prompted for the tread depth, then the
;;;       step width:
;;;         - The tread depth is ALWAYS held exactly.
;;;         - If the wall opening at that depth is within 1/8" of the
;;;           requested width, the step is trimmed to the walls.
;;;         - Otherwise the requested width is held, centered between
;;;           the two wall lines so the step runs EQUALLY past (or
;;;           equally short of) both walls, and the step breaks away
;;;           from the walls to hold the given dimensions.
;;;         - Enter at the width prompt fits that one step to the walls.
;;;
;;;   OUTSIDE IN:
;;;   5a. If a diagonal LINE was selected you are asked whether the
;;;       steps run Parallel to the diagonal, or with their endpoints
;;;       Equidistant from the true corner (square to the true-angle
;;;       bisector).  With no diagonal, equidistant is always used.
;;;   5b. You give the width of the furthest (outermost) step.  That
;;;       step is bounded to the provided walls, so its width alone
;;;       places it - it is just the starting point.  Each following
;;;       step asks for a tread depth (walking back in toward the
;;;       corner), then a step width, under the same rules as inside
;;;       out: Enter fits the step to the walls, a width within 1/8"
;;;       of the wall opening is trimmed to the walls, and any other
;;;       width is held, breaking the step away from the walls.
;;;       Drawing stops if the corner is reached.
;;;
;;;   6.  You are asked whether to dimension the steps [Yes/No].  If
;;;       Yes, aligned dimensions are added:
;;;         - Tread depths are chained along the bisector out from the
;;;           starting point (each link is one tread's depth, measured
;;;           to where that tread crosses the bisector), in dim style
;;;           "STANDARD INCHES".
;;;         - Step widths are the full width of each tread edge, placed
;;;           just outside the corner and nested so the wider (deeper)
;;;           steps sit progressively further out, in dim style
;;;           "SIDE STANDARD".
;;;       Both styles must already exist in the drawing; if one is
;;;       missing the current style is used and a note is printed.
;;;   7.  Enter at the depth prompt means no more depths/widths are
;;;       required; the routine finishes with what it was given.
;;;       Side (riser) lines are drawn between successive step ends
;;;       whenever the walls themselves do not already close that edge.
;;;
;;; NOTES
;;;   - The 1/8" width tolerance assumes the drawing unit is INCHES.
;;;     Change *CS-WIDTH-TOL* below if your drawings use another unit.
;;;   - Geometry is assumed to be drawn in plan view in the WCS.
;;;   - All new geometry is drawn as LINEs on the current layer.
;;;   - Depth dims use dim style "STANDARD INCHES" and width dims use
;;;     "SIDE STANDARD" (set *CS-DEPTH-DIMSTYLE* / *CS-WIDTH-DIMSTYLE*
;;;     below to rename).  DIMSCALE sets their size; grab a dimension
;;;     line to slide it if it lands awkwardly.
;;;   - One U / UNDO reverses the whole command.
;;; ======================================================================

(setq *cs-width-tol* 0.125) ; step width tolerance: 1/8 inch

;; Dimension styles the routine switches to (they must already exist in
;; the drawing - if one is missing, the current style is used instead).
(setq *cs-depth-dimstyle* "STANDARD INCHES") ; for tread-depth dims
(setq *cs-width-dimstyle* "SIDE STANDARD")   ; for step-width dims

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

;;; ------------------------- vector helpers ----------------------------

(defun cs-dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun cs-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun cs-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun cs-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun cs-len (v) (sqrt (cs-dot v v)))

(defun cs-unit (v / l)
  (if (> (setq l (cs-len v)) 1e-10) (cs-scl v (/ 1.0 l))))

(defun cs-perp90 (v) (list (- (cadr v)) (car v) 0.0))

;; perpendicular distance from point P to the infinite line through A-B
(defun cs-ptline (p a b / d)
  (setq d (cs-unit (cs-vec a b)))
  (if d
    (abs (- (* (car d) (- (cadr p) (cadr a)))
            (* (cadr d) (- (car p) (car a)))))
    (distance p a)))

;; endpoint of line LN (list of two points) farther from PT
(defun cs-far (ln pt)
  (if (> (distance (car ln) pt) (distance (cadr ln) pt)) (car ln) (cadr ln)))

;; point on a circle: center C, radius R, angle A
(defun cs-arcpt (c r a)
  (list (+ (car c) (* r (cos a))) (+ (cadr c) (* r (sin a))) 0.0))

;;; ------------------------- drawing helpers ---------------------------

(defun cs-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;; make dimension style NAME current, but only if it exists and is not
;; already current (avoids needless work while alternating styles).
;; Uses ActiveX so style names containing spaces are handled correctly
;; (the -DIMSTYLE command would read a space as ENTER).
(defun cs-setstyle (name / doc)
  (if (and (tblsearch "DIMSTYLE" name)
           (/= (strcase name) (strcase (getvar "DIMSTYLE"))))
    (vl-catch-all-apply
      '(lambda ()
         (setq doc (vla-get-activedocument (vlax-get-acad-object)))
         (vla-put-activedimstyle
           doc (vla-item (vla-get-dimstyles doc) name))))))

;; aligned dimension between A and B in dim style STYLE, dim line
;; passing through THRU.  "_non" disables running osnap for each fed
;; point so nothing snaps.
(defun cs-dim (style a b thru)
  (cs-setstyle style)
  (command "_.DIMALIGNED" "_non" a "_non" b "_non" thru))

;; Draw the side (riser) line A-B unless it is degenerate or both points
;; already lie along the same wall line (the wall provides that edge).
(defun cs-conn (a b w1 w2)
  (if (and a b (> (distance a b) 1e-8)
           (not (and (< (cs-ptline a (car w1) (cadr w1)) 1e-6)
                     (< (cs-ptline b (car w1) (cadr w1)) 1e-6)))
           (not (and (< (cs-ptline a (car w2) (cadr w2)) 1e-6)
                     (< (cs-ptline b (car w2) (cadr w2)) 1e-6))))
    (cs-mkline a b)))

;; Resolve a step's endpoints from the requested width WID (nil = fit
;; to the walls), the wall hits H1/H2 with opening NAT, the position P
;; on the measuring ray, and the tread direction PERP.  Returns the
;; list (e1 e2), or nil when the step must be skipped.  A width within
;; the tolerance of the wall opening is trimmed to the walls; any
;; other width is held, centered on the wall opening so the step runs
;; equally past (or equally short of) both walls.
(defun cs-resolve (wid nat h1 h2 p perp n / u cen e1 e2)
  (cond
    ;; Enter on width -> fit this step to the walls
    ((null wid)
     (if nat
       (progn
         (princ (strcat "\n  Step " (itoa n) ": fitted to walls, width = "
                        (rtos nat) "."))
         (list h1 h2))
       (progn
         (princ (strcat "\n  Step " (itoa n)
                        ": cannot reach both walls here - step skipped."))
         nil)))
    ;; requested width within 1/8" of the wall opening -> trim to walls
    ((and nat (<= (abs (- nat wid)) *cs-width-tol*))
     (princ (strcat "\n  Step " (itoa n) ": wall opening " (rtos nat)
                    " is within 1/8\" of " (rtos wid)
                    " - fitted to walls."))
     (list h1 h2))
    ;; otherwise hold the exact width; the step breaks from the walls
    (T
     (if nat
       (setq u   (cs-unit (cs-vec h2 h1))
             cen (mapcar '(lambda (x y) (* 0.5 (+ x y))) h1 h2)
             e1  (cs-add cen (cs-scl u (* 0.5 wid)))
             e2  (cs-add cen (cs-scl u (* -0.5 wid))))
       ;; no wall opening here - fall back to the measuring ray
       (setq e1 (cs-add p (cs-scl perp (* 0.5 wid)))
             e2 (cs-add p (cs-scl perp (* -0.5 wid)))))
     (princ (strcat "\n  Step " (itoa n) ": width " (rtos wid) " held"
                    (if nat (strcat " (wall opening " (rtos nat) ")") "")
                    " - step breaks from the walls."))
     (list e1 e2))))

;;; --------------------------- main command ----------------------------

(defun c:CORNERSTP ( / *error* undoflag ss i ed lines arcs diag arcd
                       cand o1 o2 score best j k tmp w1 w2 corner
                       c r a1 a2 mid key start d1 d2 bis perp
                       dist n drawn dep wid p h1 h2 nat e1 e2
                       prevL prevR dimflag txth w offd oldce oldstyle
                       outflag stopf op1 pprev tout)

  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (cs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nCORNERSTP: " msg)))
    (princ))

  ;; ---- 1. selection --------------------------------------------------
  (princ "\nSelect the two wall lines forming the corner ")
  (princ "(a corner diagonal line or fillet arc may be included):")
  (setq ss (ssget '((0 . "LINE,ARC"))))
  (if (null ss)
    (progn (princ "\nNothing selected.") (exit)))

  (setq lines nil arcs nil i 0)
  (repeat (sslength ss)
    (setq ed (entget (ssname ss i))
          i  (1+ i))
    (if (= "LINE" (cdr (assoc 0 ed)))
      (setq lines (cons (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))) lines))
      (setq arcs (cons ed arcs))))

  ;; ---- 2. sort out walls / diagonal / arc ----------------------------
  (cond
    ;; two walls only
    ((and (= (length lines) 2) (null arcs)) nil)

    ;; two walls plus a chamfer (diagonal) line: the diagonal is the
    ;; line whose endpoints sit closest to the other two lines
    ((and (= (length lines) 3) (null arcs))
     (setq best 1e99 j 0 k 0)
     (repeat 3
       (setq cand  (nth k lines)
             o1    (nth (rem (+ k 1) 3) lines)
             o2    (nth (rem (+ k 2) 3) lines)
             score (+ (min (cs-ptline (car cand)  (car o1) (cadr o1))
                           (cs-ptline (car cand)  (car o2) (cadr o2)))
                      (min (cs-ptline (cadr cand) (car o1) (cadr o1))
                           (cs-ptline (cadr cand) (car o2) (cadr o2)))))
       (if (< score best) (setq best score j k))
       (setq k (1+ k)))
     (setq diag  (nth j lines)
           lines (list (nth (rem (+ j 1) 3) lines)
                       (nth (rem (+ j 2) 3) lines))))

    ;; two walls plus a fillet arc
    ((and (= (length lines) 2) (= (length arcs) 1))
     (setq arcd (car arcs)))

    (T
     (princ "\nSelect exactly two wall lines, optionally plus ONE ")
     (princ "diagonal line or ONE fillet arc.")
     (exit)))

  ;; ---- 3. true corner = apparent intersection of the walls -----------
  (setq w1 (car lines)
        w2 (cadr lines)
        corner (inters (car w1) (cadr w1) (car w2) (cadr w2) nil))
  (if (null corner)
    (progn (princ "\nThe two wall lines are parallel - no corner found.")
           (exit)))

  ;; ---- 4. middle of the diagonal / arc, if one was selected ----------
  (if arcd
    (progn
      (setq c  (cdr (assoc 10 arcd))
            r  (cdr (assoc 40 arcd))
            a1 (cdr (assoc 50 arcd))
            a2 (cdr (assoc 51 arcd)))
      (if (< a2 a1) (setq a2 (+ a2 pi pi)))))
  (cond
    (diag (setq mid (mapcar '(lambda (x y) (* 0.5 (+ x y)))
                            (car diag) (cadr diag))))
    (arcd (setq mid (cs-arcpt c r (* 0.5 (+ a1 a2))))))

  ;; ---- 5. draw direction ----------------------------------------------
  ;; INSIDE OUT: build from the corner out toward the pool from given
  ;;             tread depths and step widths.
  ;; OUTSIDE IN: place the furthest step first from its given width
  ;;             (bounded to the walls) and walk back in by tread depth.
  (initget "Inside Outside")
  (setq key     (getkword "\nDraw steps [Inside out/Outside in] <Inside out>: ")
        outflag (= key "Outside"))

  ;; ---- 5a. starting point (inside out only) ---------------------------
  (if (and mid (not outflag))
    (progn
      (initget "Middle True")
      (setq key (getkword
        "\nMeasure tread depths from [Middle of diagonal/True corner] <Middle>: "))
      (setq start (if (= key "True") corner mid)))
    (setq start corner))

  ;; ---- 6. tread orientation / measuring direction toward the pool ----
  ;; BIS  = direction the tread depths are measured along
  ;; PERP = direction the step edges run (treads are drawn along PERP)
  (setq d1  (cs-unit (cs-vec corner (cs-far w1 corner)))
        d2  (cs-unit (cs-vec corner (cs-far w2 corner)))
        bis (cs-unit (mapcar '+ d1 d2)))
  (if (null bis)
    (progn (princ "\nWall lines are collinear - cannot find step direction.")
           (exit)))
  (if (and mid (< (cs-dot bis (cs-vec corner mid)) 0.0))
    (setq bis (cs-scl bis -1.0)))
  (if diag
    (progn
      (if outflag
        (progn
          (initget "Parallel Equidistant")
          (setq key (getkword (strcat
            "\nSteps [Parallel to diagonal"
            "/Equidistant from true corner] <Parallel>: "))))
        (progn
          (initget "Parallel True")
          (setq key (getkword
            "\nTreads [Parallel to diagonal/True angle] <Parallel>: "))))
      (if (not (member key '("True" "Equidistant")))
        (progn
          ;; treads parallel to the diagonal; depths measured square to it
          (setq perp (cs-unit (cs-vec (car diag) (cadr diag)))
                bis  (cs-perp90 perp))
          (if (< (cs-dot bis (cs-vec corner mid)) 0.0)
            (setq bis (cs-scl bis -1.0)))))))
  (if (null perp)
    ;; treads perpendicular to the true-angle (equal-angle) bisector
    (setq perp (cs-unit (cs-perp90 bis))))

  (if outflag
    (princ (strcat "\nOutermost step is bounded to the walls; drawing"
                   " back in toward the corner (direction "
                   (angtos (angle '(0.0 0.0 0.0) bis)) ")."))
    (princ (strcat "\nMeasuring from "
                   (if (equal start corner 1e-9)
                     "the true corner"
                     "the middle of the diagonal/arc")
                   " toward the pool (direction "
                   (angtos (angle '(0.0 0.0 0.0) bis)) ").")))

  ;; previous edge ends, used to close the step sides (inside out only -
  ;; outside-in steps are all wall-bounded, so the walls close them)
  (if (not outflag)
    (progn
      (cond
        (diag (setq prevL (car diag) prevR (cadr diag)))
        (arcd (setq prevL (cs-arcpt c r a1) prevR (cs-arcpt c r a2)))
        (T    (setq prevL corner prevR corner)))
      (if (> (cs-dot (cs-vec start prevL) perp)
             (cs-dot (cs-vec start prevR) perp))
        (setq tmp prevL prevL prevR prevR tmp))))

  ;; ---- 7. dimension the steps? ---------------------------------------
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
                       "\" not found - tread depths use the current style.")))
      (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                       "\" not found - step widths use the current style.")))))

  ;; ---- 8. prompt for each step and draw it ----------------------------
  (command "_.UNDO" "_Begin")
  (setq undoflag T dist 0.0 n 1 drawn 0
        oldce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)                    ; quiet the dimstyle/dim commands

  (if outflag

    ;; ========== OUTSIDE IN: outermost step first, then walk in ==========
    (progn
      (initget 6)
      (setq wid (getdist "\nWidth of the furthest (outermost) step: "))
      (if (null wid)
        (princ "\nNo width given - nothing drawn.")
        (progn
          ;; the wall opening grows linearly with distance from the
          ;; corner, so the opening at distance 1 fixes where a step of
          ;; the given width must sit to be bounded by both walls
          (setq p   (cs-add corner bis)
                h1  (inters p (cs-add p perp) (car w1) (cadr w1) nil)
                h2  (inters p (cs-add p perp) (car w2) (cadr w2) nil)
                op1 (if (and h1 h2) (distance h1 h2)))
          (if (or (null op1) (<= op1 1e-10))
            (princ "\nCannot measure the wall opening - nothing drawn.")
            (progn
              (setq tout (/ wid op1)     ; outermost step's ray distance
                    wid  nil)            ; the first step fits the walls
              (while (and (not stopf) tout)
                (setq p   (cs-add corner (cs-scl bis tout))
                      h1  (inters p (cs-add p perp) (car w1) (cadr w1) nil)
                      h2  (inters p (cs-add p perp) (car w2) (cadr w2) nil)
                      nat (if (and h1 h2) (distance h1 h2))
                      tmp (cs-resolve wid nat h1 h2 p perp n)
                      e1  (car tmp)
                      e2  (cadr tmp))
                (if (and e1 e2)
                  (progn
                    ;; keep a consistent left/right orientation
                    (if (> (cs-dot (cs-vec corner e1) perp)
                           (cs-dot (cs-vec corner e2) perp))
                      (setq tmp e1 e1 e2 e2 tmp))
                    (cs-mkline e1 e2)          ; the step (tread) edge
                    (cs-conn prevL e1 w1 w2)   ; side lines where the walls
                    (cs-conn prevR e2 w1 w2)   ; do not already close them
                    (setq w (distance e1 e2))
                    (if dimflag
                      (progn
                        (if (null offd)
                          (setq offd (max (* 2.0 txth) (* 0.2 w))))
                        ;; step width: nested just outside the corner
                        (cs-dim *cs-width-dimstyle* e1 e2
                                (cs-add corner
                                        (cs-scl bis
                                                (- (+ (* 0.5 w)
                                                      (* 1.5 txth))))))
                        ;; tread depth: chain link back out to the
                        ;; previous (next-further-out) tread
                        (if pprev
                          (cs-dim *cs-depth-dimstyle* p pprev
                                  (cs-add (mapcar '(lambda (x y)
                                                     (* 0.5 (+ x y)))
                                                  p pprev)
                                          (cs-scl perp offd))))))
                    (setq prevL e1 prevR e2 pprev p drawn (1+ drawn))))
                ;; next step inward: depth, then width - same rules as
                ;; inside out (a held width breaks from the walls)
                (if (not stopf)
                  (progn
                    (setq n (1+ n))
                    (initget 6)
                    (setq dep (getdist (strcat "\nStep " (itoa n)
                      " - tread depth (going in) <Enter = done>: ")))
                    (cond
                      ((null dep) (setq tout nil)) ; done
                      ((<= (setq tout (- tout dep)) 1e-8)
                       (princ (strcat "\nReached the corner - no room"
                                      " for another step; stopping."))
                       (setq stopf T))
                      (T
                       (initget 6)
                       (setq wid (getdist (strcat "\nStep " (itoa n)
                         " - step width <Enter = fit to walls>: ")))))))))))))

    ;; ========== INSIDE OUT: from the corner out toward the pool =========
    (while
      (progn
        (initget 6) ; no zero, no negative; Enter = done
        (setq dep (getdist (strcat "\nStep " (itoa n)
                                   " - tread depth <Enter = done>: "))))
    (initget 6)
    (setq wid (getdist (strcat "\nStep " (itoa n)
                               " - step width <Enter = fit to walls>: ")))
    (setq dist (+ dist dep)                       ; tread depth held exactly
          p    (cs-add start (cs-scl bis dist))
          h1   (inters p (cs-add p perp) (car w1) (cadr w1) nil)
          h2   (inters p (cs-add p perp) (car w2) (cadr w2) nil)
          nat  (if (and h1 h2) (distance h1 h2))  ; wall opening at this depth
          tmp  (cs-resolve wid nat h1 h2 p perp n)
          e1   (car tmp)
          e2   (cadr tmp))
    (if (and e1 e2)
      (progn
        ;; keep a consistent left/right orientation for the side lines
        (if (> (cs-dot (cs-vec start e1) perp)
               (cs-dot (cs-vec start e2) perp))
          (setq tmp e1 e1 e2 e2 tmp))
        (cs-mkline e1 e2)          ; the step (tread) edge
        (cs-conn prevL e1 w1 w2)   ; side lines where the walls
        (cs-conn prevR e2 w1 w2)   ; do not already close the step
        (if dimflag
          (progn
            (setq w (distance e1 e2))
            ;; fix the depth chain's side offset once, off the bisector
            (if (null offd) (setq offd (max (* 2.0 txth) (* 0.2 w))))
            ;; tread depth: link of a chain along the bisector, from the
            ;; previous tread crossing (p - bis*dep) to this one (p)
            (cs-dim *cs-depth-dimstyle*
                    (cs-add p (cs-scl bis (- dep))) p
                    (cs-add (cs-add p (cs-scl bis (* -0.5 dep)))
                            (cs-scl perp offd)))
            ;; step width: full tread edge, placed just outside the
            ;; corner and nested by half the tread's own width so the
            ;; wider (deeper) steps stack progressively further out
            (cs-dim *cs-width-dimstyle*
                    e1 e2
                    (cs-add corner
                            (cs-scl bis (- (+ (* 0.5 w) (* 1.5 txth))))))))
        (setq prevL e1 prevR e2 drawn (1+ drawn))))
    (setq n (1+ n))))

  ;; ---- 9. done ---------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn)
                   " step(s) drawn - tread depths held exactly.")))
  (if oldstyle (cs-setstyle oldstyle))   ; back to the entry dim style
  (command "_.UNDO" "_End")
  (if oldce (setvar "CMDECHO" oldce))
  (setq undoflag nil)
  (princ))

(princ "\nCORNERSTP.lsp loaded - type CORNERSTP to draw corner steps.")
(princ)
