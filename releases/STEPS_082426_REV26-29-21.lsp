;;; ======================================================================
;;; STEPS_082426_REV26-29-21.lsp
;;; ----------------------------------------------------------------------
;;; GENERATED - do not edit.  Rebuild it with:
;;;     python3 tools/release_lisp.py
;;;
;;; A one-file release of the pool-step layout routines.  Each one is
;;; included below verbatim from its source in lisp/cornerstp/, in the
;;; order its REV number appears in the filename above:
;;;
;;;     CORNERSTP.lsp   v2.6 -> REV26   CORNERSTP, TUTORIALCORNERSTP
;;;     HEMISTEP.lsp    v2.9 -> REV29   HEMISTEP, TUTORIALHEMISTEP
;;;     NORMIESTEP.lsp  v2.1 -> REV21   NORMIESTEP, TUTORIALNORMIESTEP
;;;
;;; LOAD:  APPLOAD this one file (or drag it into the drawing
;;;        window) and every command listed above comes with it.
;;;
;;; Each routine keeps its own helper namespace and its own
;;; version banner, and prints that banner as it loads, so this
;;; bundle behaves exactly like loading the sources one after
;;; another - it is only the packaging that differs.
;;; ======================================================================

;;; ======================================================================
;;; >>> CORNERSTP.lsp (v2.6) - verbatim from lisp/cornerstp/CORNERSTP.lsp
;;; ======================================================================
;;; ======================================================================
;;; CORNERSTP.lsp
;;; ----------------------------------------------------------------------
;;; Corner step layout routine for swimming-pool corners.
;;; Written for AutoCAD 2018 (plain AutoLISP + ActiveX for dim styles).
;;;
;;; LOAD:     APPLOAD this file (or drag it into the drawing window).
;;; COMMAND:  CORNERSTP
;;;
;;; WHAT IT DOES
;;;   Draws a run of parallel corner steps (tread edges) fanning out from
;;;   a pool corner toward the pool.  Step treads (the plan-view spacing
;;;   of each step) are always held exactly; step widths are held to
;;;   within the width tolerance of the wall opening (1/8" by default).
;;;   The step DEPTH, by contrast, is the vertical drop of a step - it is
;;;   only asked for by the optional side profile at the end of the run.
;;;
;;; WORKFLOW
;;;   1.  Select the two walls that form the corner.  Walls may be LINEs
;;;       or straight segments of a POLYLINE.  A corner diagonal
;;;       (chamfer) or a fillet ARC may be included in the same
;;;       selection.  If more than two straight walls are selected you
;;;       are asked to pick the two you mean.
;;;   2.  If the two walls intersect at a point, that intersection is
;;;       the starting point.
;;;   3.  Choose the draw direction [Inside out/Outside in]:
;;;         INSIDE OUT (default) - steps are built from the corner out
;;;         toward the pool from given step treads and step widths.
;;;         OUTSIDE IN - the furthest (outermost) step is placed first
;;;         from its given width, bounded to the provided walls, and
;;;         the remaining steps walk back in toward the corner.
;;;
;;;   INSIDE OUT:
;;;   4a. If a diagonal/arc was selected, you are asked whether step
;;;       treads are measured from the Middle of the diagonal/arc or
;;;       from the True corner.  The true corner is found by extending
;;;       the two walls surrounding the diagonal/arc to their apparent
;;;       intersection.
;;;   4b. If a diagonal was selected you are also asked whether the
;;;       treads run Parallel to the diagonal, or perpendicular to the
;;;       bisector of the TRUE ANGLE the walls make (equal angle from
;;;       both walls).  With no diagonal the true-angle bisector is
;;;       always used.  Step treads are measured from the starting
;;;       point toward the pool, square to the treads, so all steps are
;;;       parallel to each other either way.
;;;   4c. For each step you are prompted for the step tread, then the
;;;       step width:
;;;         - The step tread is ALWAYS held exactly.
;;;         - If the wall opening at that distance is within the width
;;;           tolerance of the requested width, the step is trimmed to
;;;           the walls.
;;;         - Otherwise the requested width is held, centered between
;;;           the two walls so the step runs EQUALLY past (or equally
;;;           short of) both walls, and the step breaks away from the
;;;           walls to hold the given dimensions.
;;;         - Enter at the width prompt fits that one step to the walls.
;;;
;;;   OUTSIDE IN:
;;;   5a. If a diagonal was selected you are asked whether the steps
;;;       run Parallel to the diagonal, or with their endpoints
;;;       Equidistant from the true corner (square to the true-angle
;;;       bisector).  With no diagonal, equidistant is always used.
;;;   5b. You give the width of the furthest (outermost) step.  That
;;;       step is bounded to the provided walls, so its width alone
;;;       places it - it is just the starting point.  Each following
;;;       step asks for a step tread (walking back in toward the
;;;       corner), then a step width, under the same rules as inside
;;;       out.  Drawing stops if the corner is reached.
;;;
;;;   6.  You are asked whether to dimension the steps [Yes/No].  If
;;;       Yes, aligned dimensions are added:
;;;         - Step treads are chained along the bisector out from the
;;;           starting point, in dim style "STANDARD INCHES".
;;;         - Step widths are the full width of each tread edge, placed
;;;           just outside the corner and nested so the wider (deeper)
;;;           steps sit progressively further out, in dim style
;;;           "SIDE STANDARD".
;;;       If a style is missing the current style is used and a note is
;;;       printed.
;;;   7.  Enter at a step tread prompt means no more steps are
;;;       required.  Back at a step tread prompt steps back one step:
;;;       it removes the step just drawn (its lines and its dimensions)
;;;       so a mistyped number does not cost the whole run (Undo, the
;;;       old keyword, is still accepted).  Same repeats the previous
;;;       step tread.  Side (riser) lines are drawn between successive step
;;;       ends whenever the walls do not already close that edge.
;;;   8.  When at least one step was drawn you may add a SIDE PROFILE.
;;;       If Yes, you give each step's step depth (its vertical drop),
;;;       top step first - Enter repeats the previous drop, Back (or
;;;       Undo) steps back - then pick the top of the wall and which
;;;       side the steps descend.  The staircase silhouette (drop, then
;;;       tread, per step) is drawn from the pick; when dimensioning is
;;;       on the drops are chained vertically behind the wall and the
;;;       step treads horizontally below the profile, in the depth dim
;;;       style.
;;;     9.  Finally, BEAD THE STEPS.  Every tread is beaded - that is the
;;;       assumption - so the only thing asked is which steps carry the
;;;       bead along their side walls: All of them, or Some, given by
;;;       step number.  AUTOBEAD does the work on its own rules (2"
;;;       toward the side you click, onto its Bead Track layer), so
;;;       AUTOBEAD.lsp has to be loaded; when it is not, the run says
;;;       so and finishes without beading.  The beads are their own
;;;       undo group - AutoCAD does not nest them - so one U undoes
;;;       the beads and the next undoes the steps.
;;;
;;; OPTIONAL SETTINGS (set these before running the command)
;;;   *CS-WIDTH-TOL*      step width tolerance in drawing units.  When
;;;                       nil (the default) it is 1/8" converted through
;;;                       the drawing's INSUNITS setting.
;;;   *CS-DEPTH-DIMSTYLE* dim style for step-tread dims (also used by
;;;                       the side-profile dims).
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
;;;   - One U / UNDO reverses the whole command; a bead run added at
;;;     the end is its own group, so it takes a U of its own.
;;; ======================================================================

;; Settings - only defined if not already set, so the two routines that
;; share them stay in sync no matter which file loads first.
(if (not (boundp '*cs-width-tol*))      (setq *cs-width-tol* nil))
(if (not (boundp '*cs-dim-layer*))      (setq *cs-dim-layer* nil))
(if (not (boundp '*cs-depth-dimstyle*)) (setq *cs-depth-dimstyle* "STANDARD INCHES"))
(if (not (boundp '*cs-width-dimstyle*)) (setq *cs-width-dimstyle* "SIDE STANDARD"))

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

(setq *cs-version* "v2.6") ; printed on load and at command start so a
                           ; stale APPLOADed copy is easy to spot

;;; ------------------------- vector helpers ----------------------------

(defun cs-dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun cs-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun cs-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun cs-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun cs-len (v) (sqrt (cs-dot v v)))

(defun cs-unit (v / l)
  (if (> (setq l (cs-len v)) 1e-10) (cs-scl v (/ 1.0 l))))

(defun cs-perp90 (v) (list (- (cadr v)) (car v) 0.0))

(defun cs-mid2 (a b) (list (* 0.5 (+ (car a) (car b)))
                           (* 0.5 (+ (cadr a) (cadr b)))
                           0.0))

;; perpendicular distance from point P to the infinite line through A-B
(defun cs-ptline (p a b / d)
  (setq d (cs-unit (cs-vec a b)))
  (if d
    (abs (- (* (car d) (- (cadr p) (cadr a)))
            (* (cadr d) (- (car p) (car a)))))
    (distance p a)))

;; distance from point P to the SEGMENT A-B
(defun cs-ptseg (p a b / d l2 t2)
  (setq d  (cs-vec a b)
        l2 (cs-dot d d))
  (if (< l2 1e-20)
    (distance p a)
    (progn
      (setq t2 (/ (cs-dot (cs-vec a p) d) l2))
      (cond ((< t2 0.0) (distance p a))
            ((> t2 1.0) (distance p b))
            (T (distance p (cs-add a (cs-scl d t2))))))))

;; how far point P lies beyond the ends of segment A-B (0.0 when on it)
(defun cs-beyond (p a b / d l t2)
  (setq d (cs-vec a b)
        l (cs-len d))
  (if (< l 1e-10)
    (distance p a)
    (progn
      (setq t2 (/ (cs-dot (cs-vec a p) d) (* l l)))
      (cond ((< t2 0.0) (* (- t2) l))
            ((> t2 1.0) (* (- t2 1.0) l))
            (T 0.0)))))

;; endpoint of wall/segment record LN farther from PT
(defun cs-far (ln pt)
  (if (> (distance (car ln) pt) (distance (cadr ln) pt)) (car ln) (cadr ln)))

;; point on a circle: center C, radius R, angle A
(defun cs-arcpt (c r a)
  (list (+ (car c) (* r (cos a))) (+ (cadr c) (* r (sin a))) 0.0))

;; T when angle A lies on the counterclockwise span A1 -> A2
(defun cs-inspan (a a1 a2 / e)
  (setq e (- a2 a1))
  (if (< e 0.0) (setq e (+ e pi pi)))
  (setq a (- a a1))
  (if (< a 0.0) (setq a (+ a pi pi)))
  (<= a (+ e 1e-9)))

;;; --------------------- geometry from entities ------------------------

;; Normalized arc record (center radius startang endang) in WCS, always
;; counterclockwise with endang > startang.  Built from the curve's own
;; start/mid/end points so mirrored arcs and OCS offsets are handled.
(defun cs-arcdata (en / ed c r sp ep mp a1 a2 sw)
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
  (if (not (cs-inspan (angle c mp) a1 a2))   ; wrong way round
    (setq sw a1 a1 a2 a2 sw))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list c r a1 a2))

;; Normalized arc record for a polyline bulge segment P1 -> P2
(defun cs-bulgearc (p1 p2 b / th l r h nrm cen a1 a2)
  (setq th  (* 4.0 (atan b))                  ; signed included angle
        l   (distance p1 p2)
        r   (abs (/ l (* 2.0 (sin (/ th 2.0)))))
        h   (* r (cos (/ (abs th) 2.0)))
        nrm (cs-unit (cs-perp90 (cs-vec p1 p2)))
        cen (cs-add (cs-mid2 p1 p2)
                    (cs-scl nrm (if (> b 0.0) h (- h)))))
  (if (> b 0.0)
    (setq a1 (angle cen p1) a2 (angle cen p2))
    (setq a1 (angle cen p2) a2 (angle cen p1)))
  (if (< a2 a1) (setq a2 (+ a2 pi pi)))
  (list cen r a1 a2))

;; Segments of a POLYLINE as records (p1 p2 bulge ename index).
;; Points are brought to WCS.  Handles LWPOLYLINE and old 2D POLYLINE.
(defun cs-plsegs (en / ed el cl vs bs i m out v1 v2 b sub pr)
  (setq ed (entget en)
        el (cond ((cdr (assoc 38 ed))) (0.0))
        cl (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))))
  (if (= "LWPOLYLINE" (cdr (assoc 0 ed)))
    (foreach pr ed                              ; walk 10/42 pairs in order
      (cond
        ((= 10 (car pr))
         (setq vs (cons (trans (list (car (cdr pr)) (cadr (cdr pr)) el) en 0) vs)
               bs (cons 0.0 bs)))
        ((= 42 (car pr))
         (if bs (setq bs (cons (cdr pr) (cdr bs)))))))
    (progn                                      ; heavy 2D polyline
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
      (setq out (cons (list v1 v2 b en i) out)))
    (setq i (1+ i)))
  (reverse out))

;; nearest record in SEGS to point PT
(defun cs-nearseg (segs pt / best bd d s)
  (foreach s segs
    (setq d (cs-ptseg pt (car s) (cadr s)))
    (if (or (null best) (< d bd)) (setq best s bd d)))
  best)


;;; --------------------------- bead helpers -----------------------------

;; The step numbers typed at a prompt - "1 3 4", "1,3,4" and "1, 3 and 4"
;; all read the same.  Anything that is not a digit separates.
(defun cs-numlist (str / out tok i c)
  (setq out '() tok "" i 0)
  (while (<= i (strlen str))
    (setq c (if (< i (strlen str)) (substr str (1+ i) 1) " "))
    (if (and (>= (ascii c) 48) (<= (ascii c) 57))
      (setq tok (strcat tok c))
      (progn
        (if (/= tok "") (setq out (cons (atoi tok) out)))
        (setq tok "")))
    (setq i (1+ i)))
  (reverse out))

;; The tread line of every step that was committed, as
;; (step-number . ename).  A step's log record carries its entities
;; first and its step number at index 6, and the only LINE among
;; those entities is its tread - any dimension beside it is a DIMENSION.
(defun cs-treadents (log / out rec e ln)
  (setq out '())
  (foreach rec log
    (setq ln nil)
    ;; ...-since lists newest first, and a step draws its tread before
    ;; any side line or dimension, so the LAST line seen is the tread
    (foreach e (car rec)
      (if (and e (entget e)
               (= "LINE" (cdr (assoc 0 (entget e)))))
        (setq ln e)))
    (if ln (setq out (cons (cons (nth 6 rec) ln) out))))
  ;; the log runs newest first, so consing through it already leaves
  ;; the pairs in step order - lowest first, the way they were drawn
  out)

;; The side (riser) lines the run drew: every LINE in the log that is
;; not its step's tread.  CORNERSTP closes a step edge with one only
;; when the walls do not already close it, so most runs have none.
(defun cs-sideents (log / out rec e ln lines)
  (setq out '())
  (foreach rec log
    (setq lines '() ln nil)
    (foreach e (car rec)
      (if (and e (entget e)
               (= "LINE" (cdr (assoc 0 (entget e)))))
        (setq lines (cons e lines) ln e)))    ; ln ends on the tread
    (foreach e lines
      (if (not (eq e ln)) (setq out (cons e out)))))
  out)

;; The step numbers on offer, as "1, 2, 3" - so the numbers prompt can
;; be answered without scrolling back through the run.
(defun cs-numsay (pairs / out pr)
  (setq out "")
  (foreach pr pairs
    (setq out (strcat out (if (= out "") "" ", ") (itoa (car pr)))))
  out)

;; Midpoint (WCS) of a LINE entity.
(defun cs-entmid (e / ed)
  (setq ed (entget e))
  (cs-mid2 (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))

;;; ------------------------- setting helpers ----------------------------

;; 1/8" expressed in the drawing's units (INSUNITS); inches if unitless
(defun cs-autotol ( / iu)
  (setq iu (getvar "INSUNITS"))
  (cond ((= iu 1) 0.125)            ; inches
        ((= iu 2) (/ 0.125 12.0))   ; feet
        ((= iu 4) 3.175)            ; millimeters
        ((= iu 5) 0.3175)           ; centimeters
        ((= iu 6) 0.003175)         ; meters
        (T        0.125)))          ; unitless - assume inches

(defun cs-tolerance ( )
  (if (numberp *cs-width-tol*) *cs-width-tol* (cs-autotol)))

;; annotation text height in drawing units; DIMSCALE is 0 for
;; annotative dim styles, where the annotation scale governs instead
(defun cs-txth ( / h s)
  (setq h (getvar "DIMTXT")
        s (getvar "DIMSCALE"))
  (if (or (null s) (<= s 0.0))
    (setq s (cond ((and (getvar "CANNOSCALEVALUE")
                        (> (getvar "CANNOSCALEVALUE") 0.0))
                   (/ 1.0 (getvar "CANNOSCALEVALUE")))
                  (1.0))))
  (if (and h (> (* h s) 0.0)) (* h s) 1.0))

;;; ------------------------- drawing helpers ---------------------------

(defun cs-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;; make dimension style NAME current, but only if it exists and is not
;; already current.  Uses ActiveX so style names containing spaces are
;; handled correctly (the -DIMSTYLE command would read a space as ENTER).
(defun cs-setstyle (name / doc)
  (if (and (tblsearch "DIMSTYLE" name)
           (/= (strcase name) (strcase (getvar "DIMSTYLE"))))
    (vl-catch-all-apply
      '(lambda ()
         (setq doc (vla-get-activedocument (vlax-get-acad-object)))
         (vla-put-activedimstyle
           doc (vla-item (vla-get-dimstyles doc) name))))))

;; T when layer NAME exists and can be drawn on right now
(defun cs-layerok (name / ld f cl)
  (if (setq ld (tblsearch "LAYER" name))
    (progn
      (setq f  (cond ((cdr (assoc 70 ld))) (0))
            cl (cond ((cdr (assoc 62 ld))) (7)))
      (and (zerop (logand 1 f))                  ; not frozen
           (zerop (logand 4 f))                  ; not locked
           (> cl 0)))))                          ; not off

;; aligned dimension between A and B in dim style STYLE, dim line
;; passing through THRU.  Points are WCS and are translated to the
;; current UCS for the command.  "_non" defeats running osnap.
(defun cs-dim (style a b thru / oldl)
  (cs-setstyle style)
  (if (and *cs-dim-layer* (cs-layerok *cs-dim-layer*))
    (progn (setq oldl (getvar "CLAYER"))
           (setvar "CLAYER" *cs-dim-layer*)))
  (command "_.DIMALIGNED" "_non" (trans a 0 1)
                          "_non" (trans b 0 1)
                          "_non" (trans thru 0 1))
  (if oldl (setvar "CLAYER" oldl)))

;; Draw the side (riser) line A-B unless it is degenerate or both points
;; already lie along the same wall (the wall provides that edge).
(defun cs-conn (a b w1 w2)
  (if (and a b (> (distance a b) 1e-8)
           (not (and (< (cs-ptline a (car w1) (cadr w1)) 1e-6)
                     (< (cs-ptline b (car w1) (cadr w1)) 1e-6)))
           (not (and (< (cs-ptline a (car w2) (cadr w2)) 1e-6)
                     (< (cs-ptline b (car w2) (cadr w2)) 1e-6))))
    (cs-mkline a b)))

;; entities created since MARK (nil = since the drawing was empty)
(defun cs-since (mark / e out)
  (setq e (if mark (entnext mark) (entnext)))
  (while e (setq out (cons e out) e (entnext e)))
  out)

;; Resolve a step's endpoints from the requested width WID (nil = fit
;; to the walls), the wall hits H1/H2 with opening NAT, the position P
;; on the measuring ray, and the tread direction PERP.  Returns the
;; list (e1 e2), or nil when the step must be skipped.  A width within
;; TOL of the wall opening is trimmed to the walls; any other width is
;; held, centered on the wall opening so the step runs equally past (or
;; equally short of) both walls.
(defun cs-resolve (wid nat h1 h2 p perp n tol / u cen e1 e2)
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
    ;; requested width within tolerance of the wall opening -> trim
    ((and nat (<= (abs (- nat wid)) tol))
     (princ (strcat "\n  Step " (itoa n) ": wall opening " (rtos nat)
                    " is within " (rtos tol) " of " (rtos wid)
                    " - fitted to walls."))
     (list h1 h2))
    ;; otherwise hold the exact width; the step breaks from the walls
    (T
     (if nat
       (setq u   (cs-unit (cs-vec h2 h1))
             cen (cs-mid2 h1 h2)
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

(defun c:CORNERSTP ( / *error* cs-popstep undoflag ss i en ed et zf
                       straights arcrecs lines diag arcr cand o1 o2
                       score best j k tmp w1 w2 corner ang c r a1 a2
                       mid key start d1 d2 bis perp reflen tol txth
                       dist n drawn dep wid p h1 h2 nat e1 e2 bey
                       prevL prevR dimflag w offd oldce oldstyle oldlu
                       outflag stopf op1 pprev tout tprev lastdep
                       slog mark svdist svl svr svp svt svn s
                       bsides btreads bnums bside bdir bss pr be
                       tlist tvals tds drops pd ix ppt pw p2 dx sgn
                       px py totr totd)

  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (cs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlu (setvar "LUNITS" oldlu))
    (redraw)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nCORNERSTP: " msg)))
    (princ))

  ;; remove the most recently drawn step and roll the state back
  (defun cs-popstep ( / rec e)
    (cond
      ((null slog) (princ "\n  Already at the first step.") nil)
      ((and outflag (= 1 (length slog)))
       (princ (strcat "\n  The outermost step sets the layout - restart"
                      " the command to change its width."))
       nil)
      (T
       (setq rec (car slog))
       (foreach e (car rec) (if (and e (entget e)) (entdel e)))
       (setq dist  (nth 1 rec)
             prevL (nth 2 rec)
             prevR (nth 3 rec)
             pprev (nth 4 rec)
             tprev (nth 5 rec)   ; outside-in walks from here again
             n     (nth 6 rec)
             drawn (1- drawn)
             slog  (cdr slog)
             tlist (cdr tlist))
       (redraw)                  ; clear the erased step from the screen
       (princ "\n  Stepping back one step.")
       T)))

  ;; ---- 0. environment checks ------------------------------------------
  (princ (strcat "\nCORNERSTP " *cs-version*))
  (setq tol  (cs-tolerance)
        txth (cs-txth))
  ;; Read distances architectural-style for the whole command: a bare
  ;; number is drawing units (inches in an inch-based drawing) and
  ;; feet-inch entry like 1'4 works whatever LUNITS was set to.
  (setq oldlu (getvar "LUNITS"))
  (setvar "LUNITS" 4)
  (if (not (equal (trans '(0.0 0.0 1.0) 1 0 T) '(0.0 0.0 1.0) 1e-8))
    (princ (strcat "\nWARNING: the current UCS is not parallel to the"
                   " World XY plane - results may be skewed."))
    (if (not (equal (trans '(0.0 0.0 0.0) 1 0) '(0.0 0.0 0.0) 1e-8))
      (princ "\nNote: a shifted/rotated UCS is in use; dimensions are placed to match.")))
  (if (not (cs-layerok (getvar "CLAYER")))
    (princ (strcat "\nWARNING: the current layer (" (getvar "CLAYER")
                   ") is off, frozen or locked - new steps may not"
                   " appear.")))
  (if (zerop (getvar "INSUNITS"))
    (princ (strcat "\nNote: drawing units are unitless; the width"
                   " tolerance is taken as " (rtos tol) ".")))

  ;; ---- 1. selection ---------------------------------------------------
  (princ "\nSelect the two walls forming the corner ")
  (princ "(a corner diagonal or fillet arc may be included):")
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
       (setq straights (cons (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))
                                   0.0 en nil)
                             straights)))
      ((= et "ARC")
       (setq arcrecs (cons (cs-arcdata en) arcrecs)))
      (T                                        ; polyline: take segments
       (foreach s (cs-plsegs en)
         (if (equal 0.0 (caddr s) 1e-9)
           (setq straights (cons s straights))
           (setq arcrecs (cons (cs-bulgearc (car s) (cadr s) (caddr s))
                               arcrecs)))))))
  (setq straights (reverse straights))
  (if zf
    (princ (strcat "\nWARNING: a selected line is not flat (its ends"
                   " differ in Z) - it is used as seen in plan.")))

  ;; drop duplicates of the same wall
  (setq tmp nil)
  (foreach s straights
    (if (not (vl-some '(lambda (q)
                         (or (and (equal (car s) (car q) 1e-8)
                                  (equal (cadr s) (cadr q) 1e-8))
                             (and (equal (car s) (cadr q) 1e-8)
                                  (equal (cadr s) (car q) 1e-8))))
                      tmp))
      (setq tmp (cons s tmp))))
  (setq straights (reverse tmp))

  ;; ---- 2. sort out walls / diagonal / fillet --------------------------
  (cond
    ((< (length straights) 2)
     (princ "\nSelect at least two straight walls forming the corner.")
     (exit))

    ;; two walls, optionally with a fillet arc
    ((= (length straights) 2)
     (setq lines straights
           arcr  (car arcrecs)))

    ;; three walls: the diagonal is the one whose ends sit closest to
    ;; the other two
    ((= (length straights) 3)
     (setq best 1e99 j 0 k 0)
     (repeat 3
       (setq cand  (nth k straights)
             o1    (nth (rem (+ k 1) 3) straights)
             o2    (nth (rem (+ k 2) 3) straights)
             score (+ (min (cs-ptline (car cand)  (car o1) (cadr o1))
                           (cs-ptline (car cand)  (car o2) (cadr o2)))
                      (min (cs-ptline (cadr cand) (car o1) (cadr o1))
                           (cs-ptline (cadr cand) (car o2) (cadr o2)))))
       (if (< score best) (setq best score j k))
       (setq k (1+ k)))
     (setq diag  (nth j straights)
           lines (list (nth (rem (+ j 1) 3) straights)
                       (nth (rem (+ j 2) 3) straights))))

    ;; more than three: too many to guess - let the user point them out
    (T
     (princ (strcat "\n" (itoa (length straights))
                    " straight walls were selected."))
     (while (null w1)
       (setq tmp (getpoint "\nPick the FIRST wall of the corner: "))
       (if (null tmp) (progn (princ "\nNothing picked.") (exit)))
       (setq w1 (cs-nearseg straights (trans tmp 1 0))))
     (while (null w2)
       (setq tmp (getpoint "\nPick the SECOND wall of the corner: "))
       (if (null tmp) (progn (princ "\nNothing picked.") (exit)))
       (setq w2 (cs-nearseg straights (trans tmp 1 0)))
       (if (equal w1 w2) (progn (princ "\nThat is the same wall.")
                                (setq w2 nil))))
     (setq lines (list w1 w2))
     ;; a straight segment sitting between the two picked walls on the
     ;; same polyline is the chamfer; otherwise look for a fillet arc
     (foreach s straights
       (if (and (null diag)
                (not (equal s w1)) (not (equal s w2))
                (nth 4 s) (nth 4 w1) (nth 4 w2)
                (eq (nth 3 s) (nth 3 w1)) (eq (nth 3 s) (nth 3 w2))
                (= 2 (abs (- (nth 4 w1) (nth 4 w2))))
                (= (nth 4 s) (/ (+ (nth 4 w1) (nth 4 w2)) 2)))
         (setq diag s)))
     (setq arcr (if diag nil (car arcrecs)))))

  (setq w1 (car lines)
        w2 (cadr lines))

  ;; ---- 3. true corner = apparent intersection of the walls -----------
  (setq corner (inters (car w1) (cadr w1) (car w2) (cadr w2) nil))
  (if (null corner)
    (progn (princ "\nThe two walls are parallel - no corner found.")
           (exit)))
  (setq ang (abs (- (angle (car w1) (cadr w1)) (angle (car w2) (cadr w2)))))
  (while (> ang pi) (setq ang (- ang pi)))
  (if (or (< ang 0.0175) (> ang (- pi 0.0175)))
    (princ (strcat "\nWARNING: the two walls are nearly parallel; the"
                   " corner is "
                   (rtos (distance corner (cs-mid2 (car w1) (cadr w1))))
                   " away - check the selection.")))

  ;; show what was classified so a wrong guess is obvious
  (foreach s lines (if (nth 3 s) (redraw (nth 3 s) 3)))
  (if (and diag (nth 3 diag)) (redraw (nth 3 diag) 3))
  (princ (strcat "\nUsing two walls"
                 (cond (diag " plus a corner diagonal")
                       (arcr " plus a fillet arc")
                       (T ""))
                 "."))

  ;; ---- 4. middle of the diagonal / fillet ----------------------------
  (if arcr
    (setq c  (car arcr)
          r  (cadr arcr)
          a1 (caddr arcr)
          a2 (cadddr arcr)))
  (cond
    (diag (setq mid (cs-mid2 (car diag) (cadr diag))))
    (arcr (setq mid (cs-arcpt c r (* 0.5 (+ a1 a2))))))

  ;; ---- 5. draw direction ----------------------------------------------
  (initget "Inside Outside")
  (setq key     (getkword "\nDraw steps [Inside out/Outside in] <Inside out>: ")
        outflag (= key "Outside"))

  ;; ---- 5a. starting point (inside out only) ---------------------------
  (if (and mid (not outflag))
    (progn
      (initget "Middle True")
      (setq key (getkword
        "\nMeasure step treads from [Middle of diagonal/True corner] <Middle>: "))
      (setq start (if (= key "True") corner mid)))
    (setq start corner))

  ;; ---- 6. tread orientation / measuring direction toward the pool ----
  ;; BIS  = direction the step treads are measured along
  ;; PERP = direction the step edges run (treads are drawn along PERP)
  (setq d1  (cs-unit (cs-vec corner (cs-far w1 corner)))
        d2  (cs-unit (cs-vec corner (cs-far w2 corner)))
        bis (cs-unit (mapcar '+ d1 d2)))
  (if (null bis)
    (progn (princ "\nThe walls are collinear - cannot find a step direction.")
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
          ;; treads parallel to the diagonal; step treads measured square to it
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

  ;; preview the measuring axis and the tread direction
  (setq reflen (max (distance corner (cs-far w1 corner))
                    (distance corner (cs-far w2 corner))))
  (grdraw (trans start 0 1)
          (trans (cs-add start (cs-scl bis reflen)) 0 1) 4 0)
  (grdraw (trans (cs-add start (cs-scl perp (* 0.25 reflen))) 0 1)
          (trans (cs-add start (cs-scl perp (* -0.25 reflen))) 0 1) 2 0)

  ;; previous edge ends, used to close the step sides (inside out only -
  ;; outside-in steps start out wall-bounded)
  (if (not outflag)
    (progn
      (cond
        (diag (setq prevL (car diag) prevR (cadr diag)))
        (arcr (setq prevL (cs-arcpt c r a1) prevR (cs-arcpt c r a2)))
        (T    (setq prevL corner prevR corner)))
      (if (> (cs-dot (cs-vec start prevL) perp)
             (cs-dot (cs-vec start prevR) perp))
        (setq tmp prevL prevL prevR prevR tmp))))

  ;; ---- 7. dimension the steps? ---------------------------------------
  (initget "Yes No")
  (setq dimflag (/= "No" (getkword "\nDimension the steps? [Yes/No] <Yes>: ")))
  (if dimflag
    (progn
      (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
      (if (not (tblsearch "DIMSTYLE" *cs-depth-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-depth-dimstyle*
                       "\" not found - step treads use the current style.")))
      (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                       "\" not found - step widths use the current style.")))
      (if (and *cs-dim-layer* (not (cs-layerok *cs-dim-layer*)))
        (princ (strcat "\nNote: dim layer \"" *cs-dim-layer*
                       "\" is missing or not drawable - using the"
                       " current layer.")))))

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
              (setq tout (/ wid op1)   ; outermost step's ray distance
                    wid  nil)          ; the first step fits the walls
              (while (and (not stopf) tout)
                (setq mark  (entlast)
                      svdist dist svl prevL svr prevR svp pprev
                      svt   tprev svn n)
                (setq p   (cs-add corner (cs-scl bis tout))
                      h1  (inters p (cs-add p perp) (car w1) (cadr w1) nil)
                      h2  (inters p (cs-add p perp) (car w2) (cadr w2) nil)
                      nat (if (and h1 h2) (distance h1 h2))
                      bey (if (and h1 h2)
                            (max (cs-beyond h1 (car w1) (cadr w1))
                                 (cs-beyond h2 (car w2) (cadr w2)))
                            0.0)
                      tmp (cs-resolve wid nat h1 h2 p perp n tol)
                      e1  (car tmp)
                      e2  (cadr tmp))
                (if (> bey 1e-6)
                  (princ (strcat "\n    (note: the wall had to be extended "
                                 (rtos bey) " to meet this step)")))
                (if (and mid (< (cs-dot (cs-vec corner p)
                                        (cs-vec corner mid))
                                (cs-dot (cs-vec corner mid)
                                        (cs-vec corner mid))))
                  (princ (strcat "\n    (note: this step is inside the"
                                 " diagonal/fillet region)")))
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
                        ;; step tread: chain link back out to the
                        ;; previous (next-further-out) tread
                        (if pprev
                          (cs-dim *cs-depth-dimstyle* p pprev
                                  (cs-add (cs-mid2 p pprev)
                                          (cs-scl perp offd))))))
                    (setq prevL e1 prevR e2 pprev p tprev tout
                          drawn (1+ drawn)
                          slog  (cons (list (cs-since mark) svdist svl svr
                                            svp svt svn)
                                      slog)
                          tlist (cons tout tlist))))
                ;; next step inward: step tread, then width - same rules as
                ;; inside out (a held width breaks from the walls)
                (if (not stopf)
                  (progn
                    (setq n (1+ n) dep 'RETRY)
                    (while (eq dep 'RETRY)
                      ;; Undo is the old keyword, kept as a hidden synonym
                      (initget 6 (if lastdep "Back Same Undo" "Back Undo"))
                      (setq dep (getdist (strcat "\nStep " (itoa n)
                                  " - step tread (going in) ["
                                  (if lastdep "Back/Same" "Back")
                                  "] <Enter = done>: ")))
                      (if (= (type dep) 'STR)
                        (cond
                          ((or (= dep "Back") (= dep "Undo"))
                           (cs-popstep)
                           (setq dep 'RETRY))
                          ((= dep "Same")
                           (if lastdep
                             (setq dep lastdep)
                             (progn (princ "\n  No previous step tread.")
                                    (setq dep 'RETRY))))
                          (T (setq dep 'RETRY)))))
                    (cond
                      ((null dep) (setq tout nil)) ; done
                      ((<= (setq tout (- tprev dep)) 1e-8)
                       (princ (strcat "\nReached the corner - no room"
                                      " for another step; stopping."))
                       (setq stopf T))
                      (T
                       (setq lastdep dep)
                       (initget 6)
                       (setq wid (getdist (strcat "\nStep " (itoa n)
                         " - step width <Enter = fit to walls>: ")))))))))))))

    ;; ========== INSIDE OUT: from the corner out toward the pool =========
    (while
      (progn
        (setq dep 'RETRY)
        (while (eq dep 'RETRY)
          ;; Undo is the old keyword, kept as a hidden synonym
          (initget 6 (if lastdep "Back Same Undo" "Back Undo"))
          (setq dep (getdist (strcat "\nStep " (itoa n) " - step tread ["
                                     (if lastdep "Back/Same" "Back")
                                     "] <Enter = done>: ")))
          (if (= (type dep) 'STR)
            (cond
              ((or (= dep "Back") (= dep "Undo")) (cs-popstep) (setq dep 'RETRY))
              ((= dep "Same")
               (if lastdep
                 (setq dep lastdep)
                 (progn (princ "\n  No previous step tread.") (setq dep 'RETRY))))
              (T (setq dep 'RETRY)))))
        dep)
      (setq mark  (entlast)
            svdist dist svl prevL svr prevR svp pprev svt tprev svn n
            lastdep dep)
      (initget 6)
      (setq wid (getdist (strcat "\nStep " (itoa n)
                                 " - step width <Enter = fit to walls>: ")))
      (setq dist (+ dist dep)                       ; step tread held exactly
            p    (cs-add start (cs-scl bis dist))
            h1   (inters p (cs-add p perp) (car w1) (cadr w1) nil)
            h2   (inters p (cs-add p perp) (car w2) (cadr w2) nil)
            nat  (if (and h1 h2) (distance h1 h2))  ; wall opening here
            bey  (if (and h1 h2)
                   (max (cs-beyond h1 (car w1) (cadr w1))
                        (cs-beyond h2 (car w2) (cadr w2)))
                   0.0)
            tmp  (cs-resolve wid nat h1 h2 p perp n tol)
            e1   (car tmp)
            e2   (cadr tmp))
      (if (> bey 1e-6)
        (princ (strcat "\n    (note: the wall had to be extended "
                       (rtos bey) " to meet this step)")))
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
              ;; fix the tread chain's side offset once, off the bisector
              (if (null offd) (setq offd (max (* 2.0 txth) (* 0.2 w))))
              ;; step tread: link of a chain along the bisector, from the
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
          (setq prevL e1 prevR e2 pprev p drawn (1+ drawn)
                slog (cons (list (cs-since mark) svdist svl svr svp svt svn)
                           slog)
                tlist (cons dist tlist))))
      (setq n (1+ n))))

  ;; ---- 9. optional side profile ---------------------------------------
  ;; Drawn while the UNDO group is still open and before the entry dim
  ;; style is restored - the profile places its own dims.
  (if (> drawn 0)
    (progn
      (initget "Yes No")
      (if (/= "No" (getkword "\nAdd a side profile? [Yes/No] <Yes>: "))
        (progn
          ;; treads, top step first: sort the axis distances ascending
          ;; (outside-in entered them outermost first) and take the
          ;; first value, then each successive difference
          (setq tvals (vl-sort tlist '<) tds nil pd 0.0)
          (foreach s tvals
            (if (> (- s pd) 1e-6) (setq tds (cons (- s pd) tds)))
            (setq pd s))
          (setq tds (reverse tds))
          (if (null tds)
            (princ "\nNo usable tread spacing - side profile skipped.")
            (progn
              ;; ask each step's drop, top step first, with Back support
              (setq drops nil ix 0)
              (while (< ix (length tds))
                (setq pd 'RETRY)
                (while (eq pd 'RETRY)
                  (if (zerop ix)
                    (progn
                      ;; Back/Undo hidden here: typing them only gets
                      ;; the already-at-the-first-step feedback
                      (initget 7 "Back Undo")
                      (setq pd (getdist "\nStep 1 - step depth (the drop): ")))
                    (progn
                      ;; Undo is the old keyword, kept as a hidden synonym
                      (initget 6 "Back Undo")
                      (setq pd (getdist (strcat "\nStep " (itoa (1+ ix))
                                  " - step depth [Back] <"
                                  (rtos (car drops)) ">: ")))))
                  (cond
                    ((= (type pd) 'STR)             ; Back or Undo
                     (if (zerop ix)
                       (princ "\n  Already at the first step.")
                       (progn (setq drops (cdr drops) ix (1- ix))
                              (princ "\n  Stepping back one step.")))
                     (setq pd 'RETRY))
                    ((null pd) (setq pd (car drops))))) ; Enter = previous
                (setq drops (cons pd drops) ix (1+ ix)))
              (setq drops (reverse drops))
              ;; place the profile
              (setq ppt (getpoint
                "\nPick the top of the wall for the side profile: "))
              (if (null ppt)
                (princ "\nNo point picked - side profile skipped.")
                (progn
                  (setq pw (trans ppt 1 0) sgn 0.0)
                  (while (and (zerop sgn)
                              (setq p2 (getpoint ppt
                                "\nPick a point on the side the steps descend: ")))
                    (setq dx (- (car (trans p2 1 0)) (car pw)))
                    (if (< (abs dx) 1e-10)
                      (princ "\nPick left or right of the wall, not on it.")
                      (setq sgn (if (> dx 0.0) 1.0 -1.0))))
                  (if (zerop sgn)
                    (princ "\nNo side picked - side profile skipped.")
                    (progn
                      ;; alternating drop/tread silhouette in world X/Y
                      (setq totd (apply '+ drops)
                            totr (apply '+ tds)
                            px   (car pw)
                            py   (cadr pw)
                            ix   0)
                      (foreach s tds
                        (setq pd (nth ix drops))
                        (cs-mkline (list px py 0.0)
                                   (list px (- py pd) 0.0))
                        (if dimflag   ; drop dims: one chain behind the wall
                          (cs-dim *cs-depth-dimstyle*
                                  (list px py 0.0)
                                  (list px (- py pd) 0.0)
                                  (list (- (car pw) (* sgn 2.0 txth))
                                        (- py (* 0.5 pd)) 0.0)))
                        (setq py (- py pd))
                        (cs-mkline (list px py 0.0)
                                   (list (+ px (* sgn s)) py 0.0))
                        (if dimflag   ; tread dims: one chain along the bottom
                          (cs-dim *cs-depth-dimstyle*
                                  (list px py 0.0)
                                  (list (+ px (* sgn s)) py 0.0)
                                  (list (+ px (* sgn 0.5 s))
                                        (- (- (cadr pw) totd) (* 2.0 txth))
                                        0.0)))
                        (setq px (+ px (* sgn s)) ix (1+ ix)))
                      (princ (strcat "\nSide profile drawn: "
                                     (itoa (length tds))
                                     " step(s), total run " (rtos totr)
                                     ", total drop " (rtos totd)
                                     "."))))))))))))

  ;; ---- 10. done --------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn)
                   " step(s) drawn - step treads held exactly.")))
  (foreach s lines (if (nth 3 s) (redraw (nth 3 s) 4)))
  (if (and diag (nth 3 diag)) (redraw (nth 3 diag) 4))
  (redraw)
  (if oldstyle (cs-setstyle oldstyle))   ; back to the entry dim style
  (command "_.UNDO" "_End")
  (if oldce (setvar "CMDECHO" oldce))
  (if oldlu (setvar "LUNITS" oldlu))
  (setq undoflag nil)

  ;; ---- 11. bead the steps -----------------------------------------------
  ;; AUTOBEAD does the beading, on its own rules and in its own undo
  ;; group - which is why this sits outside ours: AutoCAD does not nest
  ;; undo groups, so one U undoes the beads and the next undoes the
  ;; steps.  Every tread is beaded; the only question left is which
  ;; steps carry the bead along their side walls, and that is answered
  ;; by step number here instead of by clicking each one.
  (if (> drawn 0)
    (if (not (boundp 'autobead-build))
      (princ (strcat "\nAUTOBEAD is not loaded - APPLOAD AUTOBEAD.lsp"
                     " if you want these steps beaded."))
      (progn
        (initget "Yes No")
        (if (/= "No" (getkword "\nBead the steps? [Yes/No] <Yes>: "))
          (progn
            (setq btreads (cs-treadents slog)
                  bsides  (cs-sideents slog)
                  bnums   nil)
            (if (null btreads)
              (princ "\nNo tread lines to bead.")
              (progn
                ;; every tread is beaded - the side walls are the question
                (initget "All Some")
                (setq bside (cond ((getkword (strcat "\nWhich steps have"
                                                     " beaded side walls?"
                                                     " [All/Some] <All>: ")))
                                  ("All")))
                (if (= bside "Some")
                  (progn
                    (princ (strcat "\n  Steps drawn: "
                                   (cs-numsay btreads)))
                    (setq bnums (cs-numlist
                                  (getstring T (strcat "\nStep numbers with"
                                                       " beaded sides: "))))
                    (setq bnums (vl-remove-if-not
                                  '(lambda (k) (assoc k btreads)) bnums))
                    (if (null bnums)
                      (progn
                        (princ (strcat "\n  No step numbers recognized -"
                                       " beading every side wall full"
                                       " length."))
                        (setq bside "All")))))
                (setq bdir (getpoint "\nClick the side to bead toward: "))
                (if (null bdir)
                  (princ "\nNo direction picked - nothing beaded.")
                  (progn
                    ;; the treads, anything the run drew for its walls,
                    ;; and the lines it came off: the pool lines of this
                    ;; pocket, which is what AUTOBEAD beads
                    (setq bss (ssadd))
                    (foreach pr btreads (ssadd (cdr pr) bss))
                    (foreach be bsides
                      (if (and be (entget be)) (ssadd be bss)))
                    (setq i 0)
                    (while (< i (sslength ss))
                      (ssadd (ssname ss i) bss)
                      (setq i (1+ i)))
                    (autobead-ensure-layer *autobead-layer*)
                    (autobead-build
                      bss bdir
                      (= bside "Some")
                      (if (= bside "Some")
                        (mapcar '(lambda (k)
                                   (cs-entmid (cdr (assoc k btreads))))
                                bnums)
                        nil)))))))))))
  (princ))

;;; --------------------------- tutorial ---------------------------------

(defun cs-tut-pause ( )
  (princ "\n      --- press Enter to continue ---")
  (getstring)
  (princ))

(defun cs-tut-text (pt h s)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 s))))

;; Walkthrough for new users: pages of what CORNERSTP does and checks,
;; then a live demonstration drawn step by step with the same geometry
;; code the real command uses.
(defun c:TUTORIALCORNERSTP ( / *error* undoflag oldce oldstyle org w1 w2
                               bis perp txth dist p h1 h2 nat tmp e1 e2
                               prevL prevR w offd n pt lst dep wid)
  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (cs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (princ))

  (princ (strcat "\n================ CORNERSTP TUTORIAL " *cs-version*
                 " ================"))
  (princ "\nCORNERSTP draws parallel corner steps fanning out of a pool")
  (princ "\ncorner toward the pool.  Step treads are always held exactly;")
  (princ "\nstep widths are held to within 1/8\" of the wall opening -")
  (princ "\ncloser than that and the step trims to the walls, further and")
  (princ "\nit holds your width and BREAKS from the walls, running equally")
  (princ "\npast both sides.")
  (cs-tut-pause)
  (princ "\nWHAT YOU SELECT")
  (princ "\n  - the two walls of the corner (LINEs or polyline segments)")
  (princ "\n  - optionally a chamfer diagonal or a fillet arc with them")
  (princ "\n  - more than two straight walls: it asks you to pick the two")
  (princ "\nTHE PROMPTS, IN ORDER")
  (princ "\n  1. Draw steps [Inside out/Outside in]")
  (princ "\n     Inside out: corner outward - each step asks step tread,")
  (princ "\n       then width (Enter fits the step to the walls).")
  (princ "\n     Outside in: the width of the furthest step places it")
  (princ "\n       wall-to-wall, then tread/width pairs walk back in.")
  (princ "\n  2. With a diagonal/arc: measure from its Middle or the True")
  (princ "\n     corner, and treads Parallel to the diagonal or square to")
  (princ "\n     the true-angle bisector.")
  (princ "\n  3. Dimension the steps? [Yes/No]")
  (princ "\n  4. Add a side profile? [Yes/No] - give each step's drop")
  (princ "\n     (its step depth), top step first, then pick the wall top")
  (princ "\n     and which side the steps descend.")
  (princ "\n  5. Bead the steps? [Yes/No] - every tread is beaded, so the")
  (princ "\n     only question is which steps have beaded SIDE WALLS:")
  (princ "\n     [All/Some], and Some takes the step numbers (\"1 3 4\").")
  (princ "\n     Then click the side to bead toward and AUTOBEAD does the")
  (princ "\n     rest on its own rules - it has to be loaded for this.")
  (princ "\n  At any step tread prompt: Enter = done, Back = step back one")
  (princ "\n  step (removes it), Same = repeat the previous step tread.")
  (cs-tut-pause)
  (princ "\nWHAT IT CHECKS AND HANDLES FOR YOU")
  (princ "\n  - warns when the UCS is tilted, a line is not flat, or the")
  (princ "\n    current layer is off/frozen/locked")
  (princ "\n  - reads bare numbers as inches and accepts 1'4 style entry")
  (princ "\n    whatever the drawing's units setting")
  (princ "\n  - finds the true corner by extending the walls; warns when")
  (princ "\n    they are nearly parallel")
  (princ "\n  - picks out the chamfer among three lines and highlights")
  (princ "\n    what it classified before asking anything")
  (princ "\n  - reads arcs from their own geometry (mirrored arcs behave)")
  (princ "\n  - notes when a wall had to be extended to meet a step")
  (princ "\n  - dims go in \"STANDARD INCHES\" (step treads) and")
  (princ "\n    \"SIDE STANDARD\" (widths), falling back to the current")
  (princ "\n    style if missing; the whole run is ONE undo")
  (cs-tut-pause)

  (initget "Yes No")
  (if (= "No" (getkword (strcat "\nDraw a demonstration in this drawing?"
                                " [Yes/No] <Yes>: ")))
    (progn (princ "\nTutorial done - type CORNERSTP to use it for real.")
           (exit)))
  (setq pt (getpoint "\nPick a clear spot (about 250 x 250 needed): "))
  (if (null pt)
    (progn (princ "\nNo spot picked - tutorial done.") (exit)))
  (setq org  (trans pt 1 0)
        txth (cs-txth)
        w1   (list org (cs-add org '(200.0 0.0 0.0)))
        w2   (list org (cs-add org '(0.0 200.0 0.0)))
        bis  (cs-unit '(1.0 1.0 0.0))
        perp (cs-perp90 bis))
  (command "_.UNDO" "_Begin")
  (setq undoflag T
        oldce (getvar "CMDECHO")
        oldstyle (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)

  (cs-mkline (car w1) (cadr w1))
  (cs-mkline (car w2) (cadr w2))
  (cs-tut-text (cs-add org '(30.0 -18.0 0.0)) (* 1.2 txth)
               "CORNERSTP demo: an L corner - these two lines get selected")
  (princ "\n[1] Two WALLS drawn - this is what you select.  The corner is")
  (princ "\n    their intersection; the steps will fan out along the 45")
  (princ "\n    degree bisector between them.")
  (cs-tut-pause)

  (setq prevL org prevR org dist 0.0 n 1)
  (foreach lst '((24.0 . 48.0) (12.0 . 72.0) (12.0 . 100.0))
    (setq dep  (car lst)
          wid  (cdr lst)
          dist (+ dist dep)
          p    (cs-add org (cs-scl bis dist))
          h1   (inters p (cs-add p perp) (car w1) (cadr w1) nil)
          h2   (inters p (cs-add p perp) (car w2) (cadr w2) nil)
          nat  (if (and h1 h2) (distance h1 h2))
          tmp  (cs-resolve wid nat h1 h2 p perp n (cs-tolerance))
          e1   (car tmp)
          e2   (cadr tmp))
    (if (> (cs-dot (cs-vec org e1) perp) (cs-dot (cs-vec org e2) perp))
      (setq tmp e1 e1 e2 e2 tmp))
    (cs-mkline e1 e2)
    (cs-conn prevL e1 w1 w2)
    (cs-conn prevR e2 w1 w2)
    (setq w (distance e1 e2))
    (if (null offd) (setq offd (max (* 2.0 txth) (* 0.2 w))))
    (cs-dim *cs-depth-dimstyle*
            (cs-add p (cs-scl bis (- dep))) p
            (cs-add (cs-add p (cs-scl bis (* -0.5 dep)))
                    (cs-scl perp offd)))
    (cs-dim *cs-width-dimstyle* e1 e2
            (cs-add org (cs-scl bis (- (+ (* 0.5 w) (* 1.5 txth))))))
    (cond
      ((= n 1)
       (princ "\n[2] Step 1: step tread 24, width 48.  The wall opening")
       (princ "\n    at that distance IS 48, so it trims to the walls.  Its")
       (princ "\n    tread dim starts the chain along the bisector; its")
       (princ "\n    width dim nests outside the corner."))
      ((= n 2)
       (princ "\n[3] Step 2: step tread 12, width 72 - also fits.  Step")
       (princ "\n    treads are each measured from the previous step,")
       (princ "\n    never a total."))
      (T
       (princ "\n[4] Step 3: step tread 12, width 100 - the opening here is")
       (princ "\n    only 96.  More than 1/8\" apart, so the width is HELD")
       (princ "\n    and the step breaks the walls, running 2 past each")
       (princ "\n    side.  Riser lines close its ends.")))
    (cs-tut-pause)
    (setq prevL e1 prevR e2 n (1+ n)))

  (if oldstyle (cs-setstyle oldstyle))
  (command "_.UNDO" "_End")
  (setq undoflag nil)
  (setvar "CMDECHO" oldce)
  (princ "\n[5] Done.  One U removes this whole demo.  Now try it for")
  (princ "\n    real: type CORNERSTP, select two wall lines of a corner,")
  (princ "\n    and follow the same prompts you just watched.")
  (princ))

(princ (strcat "\nCORNERSTP.lsp " *cs-version*
               " loaded - CORNERSTP to draw corner steps,"
               " TUTORIALCORNERSTP to learn it."))
(princ)

;;; ======================================================================
;;; >>> HEMISTEP.lsp (v2.9) - verbatim from lisp/cornerstp/HEMISTEP.lsp
;;; ======================================================================
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
;;;                      the step treads are measured from: treads run
;;;                      along the line starting where it meets the
;;;                      curve, going INTO the curve, and the step
;;;                      widths sit perpendicular to the line.
;;;   CURVE only ....... inside-out mode from the middle of the curve.
;;;                      Treads are measured from there going INTO the
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
;;;   within the width tolerance of the curve's opening at that distance
;;;   is snapped to the curve; any other width is held, centered on the
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
;;;         - Step treads chained along the axis (start to step 1, step
;;;           1 to step 2, ...), in dim style "STANDARD INCHES".
;;;       If a style is missing the current style is used instead.
;;;   4.  LINE mode starts with the width of the step AT THE WALL: that
;;;       is the top of the run, so no chord is drawn there (the wall
;;;       already is one), but it is dimensioned and it anchors both
;;;       ends of the boundary curve.  The curve modes skip it, since
;;;       the width at the start is set by the curve itself.
;;;   5.  From there both modes run STEP TREAD then WIDTH, repeating.
;;;       Every step tread is measured FROM THE PREVIOUS STEP EDGE (from
;;;       the start of the axis for the first step) - never a running
;;;       total.
;;;       Distances read architectural style: a bare number is inches
;;;       (drawing units) and feet-inch entry like 1'4 (= 16") works
;;;       whatever the units setting.
;;;   6.  Ending and shortcuts:
;;;         - Enter at a step tread prompt = done.
;;;         - Back at a step tread prompt steps back one step: it
;;;           removes the step just drawn (its line and its dimensions).
;;;           Undo, the old keyword, is still accepted.  Same repeats
;;;           the previous step tread.
;;;         - Enter at a width prompt fits that step to the curve in
;;;           the curve modes, or repeats the previous width in LINE
;;;           mode.
;;;   7.  The hemisphere is then rebuilt as one polyline of arc segments
;;;       through every step end.  In LINE mode you are asked for one
;;;       last distance from the last step to the back of the curve, and
;;;       the polyline runs wall - side A - crown - side B - wall (the
;;;       last distance also gets the final link of the tread-dim chain).
;;;       In the curve modes the polyline runs from the deepest step
;;;       around the first one and back, and the segment spanning the
;;;       first step carries the SELECTED CURVE'S OWN bulge: a first
;;;       step sitting on the curve reproduces that curve exactly, and
;;;       a wider one still follows its curvature instead of spiking in
;;;       to the point where the axis met it.
;;;   8.  When steps were drawn you may add a SIDE PROFILE [Yes/No]:
;;;       give each step's step depth (the vertical drop), top step
;;;       first, with Back to re-ask the previous one; then pick the
;;;       top of the wall and the side the steps descend.  The
;;;       alternating drop/tread silhouette is drawn as lines and, when
;;;       the plan steps are dimensioned, every drop and tread is too.
;;;   9.  Finally, BEAD THE STEPS.  Every tread is beaded - that is the
;;;       assumption - so the only thing asked is which steps carry the
;;;       bead along their side walls: All of them, or Some, given by
;;;       step number.  AUTOBEAD does the work on its own rules (2"
;;;       toward the side you click, onto its Bead Track layer), so
;;;       AUTOBEAD.lsp has to be loaded; when it is not, the run says
;;;       so and finishes without beading.  The beads are their own
;;;       undo group - AutoCAD does not nest them - so one U undoes
;;;       the beads and the next undoes the steps.
;;;
;;; OPTIONAL SETTINGS (set these before running the command)
;;;   *CS-WIDTH-TOL*      width tolerance in drawing units.  When nil
;;;                       (the default) it is 1/8" converted through the
;;;                       drawing's INSUNITS setting.
;;;   *CS-DEPTH-DIMSTYLE* dim style for step-tread dims (the side
;;;                       profile's dims use it too).
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
;;;   - One U / UNDO reverses the whole command; a bead run added at
;;;     the end is its own group, so it takes a U of its own.
;;; ======================================================================

;; Settings - only defined if not already set, so this file and
;; CORNERSTP.lsp stay in sync no matter which one loads first.
(if (not (boundp '*cs-width-tol*))      (setq *cs-width-tol* nil))
(if (not (boundp '*cs-dim-layer*))      (setq *cs-dim-layer* nil))
(if (not (boundp '*cs-depth-dimstyle*)) (setq *cs-depth-dimstyle* "STANDARD INCHES"))
(if (not (boundp '*cs-width-dimstyle*)) (setq *cs-width-dimstyle* "SIDE STANDARD"))

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

(setq *hs-version* "v2.9") ; printed on load and at command start so a
                           ; stale APPLOADed copy is easy to spot

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

;; Midpoint of the arc that chord A-B carries with bulge BL.  A positive
;; bulge is counterclockwise, which bulges to the RIGHT of A->B.
(defun hs-bulgemid (a b bl / d nrm)
  (setq d   (hs-vec a b)
        nrm (hs-unit (list (cadr d) (- (car d)) 0.0)))
  (if nrm
    (hs-add (hs-mid2 a b) (hs-scl nrm (* 0.5 (distance a b) bl)))
    (hs-mid2 a b)))

;; Bulge for the boundary segment that spans the first step, A -> B,
;; taken from the arc piece PC that the start point REF sits on.  So the
;; boundary follows the ORIGINAL curve across the first step instead of
;; cutting in to a point on it.
;;
;; The side is chosen geometrically - whichever of the two possible arcs
;; bulges nearer REF - so no angle-wrap case can select the wrong one.
;; An arc sweeping more than half a circle would leave A heading back the
;; way the boundary came, folding the corner into a spike, so it is
;; rejected in favour of closing the span straight.
(defun hs-firstspan (a b pc ref / c b1 b2 bl)
  (setq c  (cadr pc)
        b1 (hs-segb a b c T)
        b2 (hs-segb a b c nil)
        bl (if (< (distance (hs-bulgemid a b b1) ref)
                  (distance (hs-bulgemid a b b2) ref))
             b1 b2))
  (if (> (abs bl) 1.0)
    (progn
      (princ (strcat "\n  Note: the curve wraps more than half a circle"
                     " across the first step - closing it straight."))
      0.0)
    bl))

;; A bulge past 1.0 sweeps more than half a circle, which folds the
;; boundary back on itself; such a segment is drawn straight instead.
(defun hs-safeb (bl)
  (if (or (null bl) (> (abs bl) 1.0)) 0.0 bl))

;; Circle through PTS[i], PTS[i+1], PTS[i+2] as (center . counterclockwise)
(defun hs-fit3 (pts i / a b c o)
  (setq a (nth i pts)
        b (nth (1+ i) pts)
        c (nth (+ i 2) pts)
        o (hs-circum a b c))
  (if o (cons o (> (hs-cross (hs-vec a b) (hs-vec a c)) 0.0))))

;; Bulges for a polyline through PTS, one per segment, by fitting a
;; circle through consecutive triples (a chain of 3-point arcs).
;;
;; K is the index of the crown vertex, or nil.  When given, the first
;; circle fitted is the one through the crown and its two neighbours,
;; and the rest are fitted outward from there.  That keeps the apex on
;; a single arc - so when those three points sit on the original curve
;; the reconstructed arc IS the original curve - instead of falling on
;; a seam between two circles.
;;
;; FIXED is an optional alist of (segment . bulge) that wins over any
;; fitting; when it holds the middle segment (the curve modes put the
;; original curve's own bulge there) the rest are fitted outward from
;; it, keeping both sides symmetric.
(defun hs-blgs (pts k fixed / nseg starts i res oc out st m)
  (setq nseg (1- (length pts))
        res  fixed)
  (if (or (null k) (< k 1) (> (1+ k) nseg)) (setq k nil))
  ;; the order triples are fitted in; earlier entries win
  (cond
    (k
     (setq starts (list (1- k))                ; the arc across the crown
           i      (- k 3))
     (while (>= i 0)                           ; outward, crown side A
       (setq starts (append starts (list i)) i (- i 2)))
     (setq i (1+ k))
     (while (<= (+ i 2) nseg)                  ; outward, crown side B
       (setq starts (append starts (list i)) i (+ i 2))))
    (fixed                                     ; outward from the fixed one
     (setq m (car (car fixed))
           i (- m 2))
     (while (>= i 0)
       (setq starts (append starts (list i)) i (- i 2)))
     (setq i (1+ m))
     (while (<= (+ i 2) nseg)
       (setq starts (append starts (list i)) i (+ i 2))))
    (T
     (setq i 0)
     (while (<= (+ i 2) nseg)
       (setq starts (append starts (list i)) i (+ i 2)))))
  ;; sweep every triple as a fallback so leftover end segments are
  ;; fitted through their own three points rather than a neighbour's
  (setq i 0)
  (while (<= (+ i 2) nseg)
    (setq starts (append starts (list i)) i (1+ i)))
  ;; A fitted segment sweeping more than half a circle leaves its start
  ;; heading back the way the boundary came - a fold, never right between
  ;; consecutive step ends - so such a segment is drawn straight.
  (foreach st starts
    (if (setq oc (hs-fit3 pts st))
      (progn
        (if (null (assoc st res))
          (setq res (cons (cons st (hs-safeb
                                     (hs-segb (nth st pts) (nth (1+ st) pts)
                                              (car oc) (cdr oc))))
                          res)))
        (if (null (assoc (1+ st) res))
          (setq res (cons (cons (1+ st) (hs-safeb
                                          (hs-segb (nth (1+ st) pts)
                                                   (nth (+ st 2) pts)
                                                   (car oc) (cdr oc))))
                          res))))))
  (setq i 0)
  (repeat nseg                                 ; 0.0 where nothing fitted
    (setq out (append out (list (cond ((cdr (assoc i res))) (0.0))))
          i   (1+ i)))
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


;;; --------------------------- bead helpers -----------------------------

;; The step numbers typed at a prompt - "1 3 4", "1,3,4" and "1, 3 and 4"
;; all read the same.  Anything that is not a digit separates.
(defun hs-numlist (str / out tok i c)
  (setq out '() tok "" i 0)
  (while (<= i (strlen str))
    (setq c (if (< i (strlen str)) (substr str (1+ i) 1) " "))
    (if (and (>= (ascii c) 48) (<= (ascii c) 57))
      (setq tok (strcat tok c))
      (progn
        (if (/= tok "") (setq out (cons (atoi tok) out)))
        (setq tok "")))
    (setq i (1+ i)))
  (reverse out))

;; The tread line of every step that was committed, as
;; (step-number . ename).  A step's log record carries its entities
;; first and its step number at index 3, and the only LINE among
;; those entities is its tread - any dimension beside it is a DIMENSION.
(defun hs-treadents (log / out rec e ln)
  (setq out '())
  (foreach rec log
    (setq ln nil)
    ;; ...-since lists newest first, and a step draws its tread before
    ;; any side line or dimension, so the LAST line seen is the tread
    (foreach e (car rec)
      (if (and e (entget e)
               (= "LINE" (cdr (assoc 0 (entget e)))))
        (setq ln e)))
    (if ln (setq out (cons (cons (nth 3 rec) ln) out))))
  ;; the log runs newest first, so consing through it already leaves
  ;; the pairs in step order - lowest first, the way they were drawn
  out)

;; The step numbers on offer, as "1, 2, 3" - so the numbers prompt can
;; be answered without scrolling back through the run.
(defun hs-numsay (pairs / out pr)
  (setq out "")
  (foreach pr pairs
    (setq out (strcat out (if (= out "") "" ", ") (itoa (car pr)))))
  out)

;; Midpoint (WCS) of a LINE entity.
(defun hs-entmid (e / ed)
  (setq ed (entget e))
  (hs-mid2 (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))

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
                      dimflag slog mark svcum svp svn svea sveb rec pc oldlu
                      bmark bsides btreads bnums bside bdir bss pr be
                      wallA wallB lastwid kx fx
                      tlist srt treads pv drops dd jx tcount ptop pu
                      pcancel pside dxs sgn px py lowy totrun totdrop td)

  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (hs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (if oldlu (setvar "LUNITS" oldlu))
    (redraw)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nHEMISTEP: " msg)))
    (princ))

  ;; remove the most recently drawn step and roll the state back
  (defun hs-popstep ( / e)
    (if (null slog)
      (progn (princ "\n  Already at the first step.") nil)
      (progn
        (setq rec (car slog))
        (foreach e (car rec) (if (and e (entget e)) (entdel e)))
        (setq cum   (nth 1 rec)
              pprev (nth 2 rec)
              n     (nth 3 rec)
              ea    (nth 4 rec)
              eb    (nth 5 rec)
              drawn (1- drawn)
              tlist (cdr tlist)
              slog  (cdr slog))
        (redraw)
        (princ "\n  Stepping back one step.")
        T)))

  ;; ---- 0. environment checks -------------------------------------------
  (princ (strcat "\nHEMISTEP " *hs-version* " - each step tread is measured"
                 " from the previous step."))
  (setq tol  (hs-tolerance)
        txth (hs-txth))
  ;; Read distances architectural-style for the whole command: a bare
  ;; number is drawing units (inches in an inch-based drawing) and
  ;; feet-inch entry like 1'4 works whatever LUNITS was set to.
  (setq oldlu (getvar "LUNITS"))
  (setvar "LUNITS" 4)
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
  ;; SP  = start point of the axis (treads measured from here)
  ;; DIR = direction the steps march (unit)
  ;; U   = direction the step widths run (unit, perpendicular to DIR)
  (cond

    ;; CURVE selected: steps go INTO the curve
    (cmode
     (if lin
       ;; axis line given: start where the line meets the curve, treads
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
                       "\" not found - step treads use the current style.")))
      (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                       "\" not found - step widths use the current style.")))
      (if (and *cs-dim-layer* (not (hs-layerok *cs-dim-layer*)))
        (princ (strcat "\nNote: dim layer \"" *cs-dim-layer*
                       "\" is missing or not drawable - using the"
                       " current layer.")))))

  ;; ---- 4. widths and step treads, chord by chord -----------------------
  (command "_.UNDO" "_Begin")
  (setq undoflag T cum 0.0 n 1 drawn 0
        pprev sp                        ; tread chain starts at the axis
        offd  (* 2.0 txth)              ; tread-dim offset off the axis
        oldce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)                  ; quiet the dimstyle/dim commands

  ;; In base-line mode the first width sits AT the wall: it is the top
  ;; of the run, so no chord is drawn there (the wall already is one),
  ;; but it is dimensioned and it anchors both ends of the boundary.
  ;; In the curve modes the width at the start is set by the curve, so
  ;; the run begins straight away with a step tread.
  (if (not cmode)
    (progn
      (initget 6)
      (setq wid (getdist "\nWidth of the step at the wall <Enter = none>: "))
      (if wid
        (progn
          (setq wallA   (hs-add sp (hs-scl u (* 0.5 wid)))
                wallB   (hs-add sp (hs-scl u (* -0.5 wid)))
                lastwid wid)
          (if dimflag
            (hs-dim *cs-width-dimstyle* wallA wallB
                    (hs-add sp (hs-scl dir (- (+ (* 0.5 wid)
                                                 (* 1.5 txth)))))))
          (princ (strcat "\n  Width at the wall: " (rtos wid) "."))))))

  (while
    (and (not stopf)
         (progn
           (setq dep 'RETRY)
           (while (eq dep 'RETRY)
             ;; Undo is the old keyword, kept as a hidden synonym
             (initget 6 (strcat "Back" (if lastdep " Same" "") " Undo"))
             (setq dep (getdist
                         (strcat "\nStep " (itoa n)
                                 " - step tread [Back"
                                 (if lastdep "/Same" "") "]"
                                 " <Enter = done>: ")))
             (if (= (type dep) 'STR)
               (cond
                 ((or (= dep "Back") (= dep "Undo"))
                  (hs-popstep) (setq dep 'RETRY))
                 ((= dep "Same")
                  (if lastdep
                    (setq dep lastdep)
                    (progn (princ "\n  No previous step tread.")
                           (setq dep 'RETRY))))
                 (T (setq dep 'RETRY)))))
           dep))
    (setq wid 'RETRY)
    (while (eq wid 'RETRY)
      (initget 6)
      (setq wid (getdist (strcat "\nStep " (itoa n) " - step width "
                                 (cond
                                   (cmode "<Enter = fit to the curve>: ")
                                   (lastwid (strcat "<Enter = "
                                                    (rtos lastwid) ">: "))
                                   (T ": ")))))
      (if (null wid)
        (cond
          (cmode   (setq wid 'FIT))
          (lastwid (setq wid lastwid))
          (T (princ "\n  A width is needed for this step.")
             (setq wid 'RETRY)))))
    (if (null dep)
      (progn
        (princ "\nNo step tread given - step discarded; finishing.")
        (setq stopf T))
      (progn
        (setq mark (entlast)
              svcum cum svp pprev svn n svea ea sveb eb
              lastdep dep
              ;; each step sits DEP past the PREVIOUS step edge, never
              ;; a running total from the start
              p    (hs-add pprev (hs-scl dir dep))
              e1   nil
              e2   nil)
        (if cmode
          ;; hold as true to the curve as the tolerance allows
          (progn
            (setq op  (hs-open p u pieces)
                  nat (if op (caddr op)))
            (cond
              ;; Enter on width -> fit this step to the curve
              ((eq wid 'FIT)
               (if op
                 (progn
                   (setq e1 (car op) e2 (cadr op))
                   (princ (strcat "\n  Step " (itoa n)
                                  ": fitted to the curve, width = "
                                  (rtos (caddr op)) ".")))
                 (princ (strcat "\n  Step " (itoa n)
                                ": the curve does not reach this distance"
                                " - step skipped."))))
              ((and nat (<= (abs (- nat wid)) tol))
               (setq e1 (car op) e2 (cadr op))
               (princ (strcat "\n  Step " (itoa n) ": curve opening "
                              (rtos nat) " is within " (rtos tol) " of "
                              (rtos wid) " - snapped to the curve.")))
              (T
               ;; center on the curve's opening so the step breaks it
               ;; equally on both sides; on the axis when there is none
               (setq cen (if op (hs-mid2 (car op) (cadr op)) p)
                     e1  (hs-add cen (hs-scl u (* 0.5 wid)))
                     e2  (hs-add cen (hs-scl u (* -0.5 wid))))
               (princ (strcat "\n  Step " (itoa n) ": width " (rtos wid)
                              " held"
                              (if nat
                                (strcat " (curve opening " (rtos nat) ")")
                                " (the curve does not reach this distance)")
                              " - step breaks from the curve.")))))
          ;; classic base-line mode: centered on the axis as given
          (progn
            (setq e1 (hs-add p (hs-scl u (* 0.5 wid)))
                  e2 (hs-add p (hs-scl u (* -0.5 wid))))))
        (if (and e1 e2)
          (progn
            (setq cum (+ cum dep))             ; running total (echo + profile)
            (princ (strcat "\n  Step " (itoa n) ": " (rtos dep)
                           " past the previous step ("
                           (rtos cum) " from the start)."))
            (hs-mkline e1 e2)                  ; the chord (step edge)
            (setq ea (append ea (list e1))     ; remember the ends for
                  eb (append eb (list e2)))    ; the boundary polyline
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
                ;; step tread: chain link along the axis, from the
                ;; previous step edge (the start for step 1) to here
                (hs-dim *cs-depth-dimstyle* pprev p
                        (hs-add (hs-mid2 pprev p) (hs-scl u offd)))))
            (setq pprev p drawn (1+ drawn)
                  lastwid (distance e1 e2)
                  tlist (cons cum tlist)       ; axis distances, newest first
                  slog  (cons (list (hs-since mark) svcum svp svn svea sveb)
                              slog))))
        (setq n (1+ n)))))

  ;; ---- 5. boundary curve through the step ends -------------------------
  ;; The hemisphere is rebuilt as one polyline of arc segments running
  ;; through every step end.  In base-line mode it starts and finishes
  ;; at the wall (the width given at the wall) and bulges out to a crown
  ;; set by one last distance.  In the curve modes the crown is the point
  ;; where the measuring axis meets the selected curve, so the arc
  ;; beside it is fitted through that original point.
  (if (> drawn 0)
    (progn
      (if (not cmode)
        (progn
          (initget 6)
          (setq dep (getdist (strcat "\nDistance from the last step to the back"
                                     " of the curve <Enter = none>: ")))
          (if (and dep (= (type dep) 'REAL))
            (progn
              (setq crown (hs-add pprev (hs-scl dir dep)))
              (if dimflag                    ; last link of the tread chain
                (hs-dim *cs-depth-dimstyle* pprev crown
                        (hs-add (hs-mid2 pprev crown)
                                (hs-scl u offd))))))
          ;; wallA - side A - crown - side B - wallB
          (setq pts (append (if wallA (list wallA))
                            ea
                            (if crown (list crown))
                            (reverse eb)
                            (if wallB (list wallB)))
                ;; index of the crown vertex, for the arc fitting
                kx  (if crown
                      (+ (length ea) (if wallA 1 0)))))
        (progn
          (initget "Yes No")
          (if (/= "No" (getkword (strcat "\nDraw the reconstructed boundary"
                                         " through the step ends? [Yes/No]"
                                         " <Yes>: ")))
            ;; Deepest step - side A - across the first step - side B.
            ;; The start point is NOT made a vertex: near the crown the
            ;; curve's opening is narrow, so forcing the boundary through
            ;; it would spike inward whenever the first step is wider
            ;; than the curve there.  Instead the segment spanning the
            ;; first step carries the ORIGINAL curve's own bulge, which
            ;; traces the crown exactly when that step sits on the curve.
            (progn
              (setq pts (append (reverse ea) eb))
              (if (and spc (= "A" (car spc)))
                (setq fx (list (cons (1- (length ea))
                                     (hs-firstspan (car ea) (car eb)
                                                   spc sp)))))))))
      (if (and pts (> (length pts) 1))
        (progn
          (setq bmark (entlast))       ; the boundary is this run's wall
          (hs-mkpoly pts (hs-blgs pts kx fx))
          (setq bsides (hs-since bmark))
          (princ (strcat "\nBoundary polyline drawn through the step ends"
                         (cond ((not cmode)
                                (if wallA ", held to the wall" ""))
                               (T ", held to the original point"))
                         "."))))))

  ;; ---- 6. side profile -------------------------------------------------
  ;; The plan run seen from the side: alternating vertical drops (the
  ;; step depths) and horizontal step treads, drawn in world X/Y from a
  ;; picked top-of-wall point.  Still inside the command's UNDO group,
  ;; and before the entry dim style is restored - the profile dims use
  ;; *cs-depth-dimstyle* too.
  (if (> drawn 0)
    (progn
      (initget "Yes No")
      (if (/= "No" (getkword "\nAdd a side profile? [Yes/No] <Yes>: "))
        (progn
          ;; step treads, top step first: sort the logged axis distances
          ;; ascending and take successive differences
          (setq srt    (vl-sort tlist '<)
                treads (list (car srt))
                pv     (car srt))
          (foreach td (cdr srt)
            (if (> (- td pv) 1e-6)
              (setq treads (append treads (list (- td pv)))))
            (setq pv td))
          (setq tcount (length treads))
          ;; the drops, top step first, with Back (Undo accepted too)
          (setq jx 1 drops nil)
          (while (<= jx tcount)
            (if (= jx 1)
              (initget 7 "Back Undo")
              (initget 6 "Back Undo"))
            (setq dd (getdist
                       (if (= jx 1)
                         "\nStep 1 - step depth (the drop): "
                         (strcat "\nStep " (itoa jx)
                                 " - step depth [Back] <"
                                 (rtos (car drops)) ">: "))))
            (cond
              ((and (= (type dd) 'STR)
                    (or (= dd "Back") (= dd "Undo")))
               (if (= jx 1)
                 (princ "\n  Already at the first step.")
                 (progn (princ "\n  Stepping back one step.")
                        (setq drops (cdr drops) jx (1- jx)))))
              ((null dd)                       ; Enter = same as previous
               (setq drops (cons (car drops) drops) jx (1+ jx)))
              (T
               (setq drops (cons dd drops) jx (1+ jx)))))
          (setq drops (reverse drops))
          ;; placement: the top of the wall, then which side it descends
          (setq ptop (getpoint
                       "\nPick the top of the wall for the side profile: "))
          (if (null ptop)
            (princ "\nNo point picked - side profile skipped.")
            (progn
              (setq pu      ptop               ; the pick, still in UCS
                    ptop    (trans ptop 1 0)
                    sgn     nil
                    pcancel nil)
              (while (and (null sgn) (not pcancel))
                (setq pside (getpoint pu
                              "\nPick a point on the side the steps descend: "))
                (cond
                  ((null pside)
                   (princ "\nNo side picked - side profile skipped.")
                   (setq pcancel T))
                  (T
                   (setq dxs (- (car (trans pside 1 0)) (car ptop)))
                   (if (< (abs dxs) 1e-10)
                     (princ "\nPick left or right of the wall, not on it.")
                     (setq sgn (if (< dxs 0.0) -1.0 1.0))))))
              (if sgn
                (progn
                  (setq totdrop 0.0 totrun 0.0)
                  (foreach dd drops (setq totdrop (+ totdrop dd)))
                  (foreach td treads (setq totrun (+ totrun td)))
                  (setq lowy (- (cadr ptop) totdrop)
                        px   (car ptop)
                        py   (cadr ptop)
                        jx   0)
                  (foreach td treads
                    (setq dd (nth jx drops)
                          e1 (list px py 0.0)
                          e2 (list px (- py dd) 0.0))
                    (hs-mkline e1 e2)          ; the drop
                    (if dimflag                ; one vertical chain, behind
                      (hs-dim *cs-depth-dimstyle* e1 e2   ; the wall
                              (list (- (car ptop) (* sgn 2.0 txth))
                                    (- py (* 0.5 dd)) 0.0)))
                    (setq py (- py dd)
                          e1 (list px py 0.0)
                          e2 (list (+ px (* sgn td)) py 0.0))
                    (hs-mkline e1 e2)          ; the tread
                    (if dimflag                ; one horizontal chain, below
                      (hs-dim *cs-depth-dimstyle* e1 e2
                              (list (+ px (* sgn 0.5 td))
                                    (- lowy (* 2.0 txth)) 0.0)))
                    (setq px (+ px (* sgn td))
                          jx (1+ jx)))
                  (princ (strcat "\nSide profile drawn: " (itoa tcount)
                                 " step(s), total run " (rtos totrun)
                                 ", total drop " (rtos totdrop)
                                 "."))))))))))

  ;; ---- 7. done ---------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn)
                   " step(s) drawn, parallel and centered on the axis.")))
  (redraw)
  (if oldstyle (hs-setstyle oldstyle))   ; back to the entry dim style
  (command "_.UNDO" "_End")
  (if oldce (setvar "CMDECHO" oldce))
  (if oldlu (setvar "LUNITS" oldlu))
  (setq undoflag nil)

  ;; ---- 8. bead the steps -----------------------------------------------
  ;; AUTOBEAD does the beading, on its own rules and in its own undo
  ;; group - which is why this sits outside ours: AutoCAD does not nest
  ;; undo groups, so one U undoes the beads and the next undoes the
  ;; steps.  Every tread is beaded; the only question left is which
  ;; steps carry the bead along their side walls, and that is answered
  ;; by step number here instead of by clicking each one.
  (if (> drawn 0)
    (if (not (boundp 'autobead-build))
      (princ (strcat "\nAUTOBEAD is not loaded - APPLOAD AUTOBEAD.lsp"
                     " if you want these steps beaded."))
      (progn
        (initget "Yes No")
        (if (/= "No" (getkword "\nBead the steps? [Yes/No] <Yes>: "))
          (progn
            (setq btreads (hs-treadents slog)
                  bnums   nil)
            (if (null btreads)
              (princ "\nNo tread lines to bead.")
              (progn
                ;; every tread is beaded - the side walls are the question
                (initget "All Some")
                (setq bside (cond ((getkword (strcat "\nWhich steps have"
                                                     " beaded side walls?"
                                                     " [All/Some] <All>: ")))
                                  ("All")))
                (if (= bside "Some")
                  (progn
                    (princ (strcat "\n  Steps drawn: "
                                   (hs-numsay btreads)))
                    (setq bnums (hs-numlist
                                  (getstring T (strcat "\nStep numbers with"
                                                       " beaded sides: "))))
                    (setq bnums (vl-remove-if-not
                                  '(lambda (k) (assoc k btreads)) bnums))
                    (if (null bnums)
                      (progn
                        (princ (strcat "\n  No step numbers recognized -"
                                       " beading every side wall full"
                                       " length."))
                        (setq bside "All")))))
                (setq bdir (getpoint "\nClick the side to bead toward: "))
                (if (null bdir)
                  (princ "\nNo direction picked - nothing beaded.")
                  (progn
                    ;; the treads, anything the run drew for its walls,
                    ;; and the lines it came off: the pool lines of this
                    ;; pocket, which is what AUTOBEAD beads
                    (setq bss (ssadd))
                    (foreach pr btreads (ssadd (cdr pr) bss))
                    (foreach be bsides
                      (if (and be (entget be)) (ssadd be bss)))
                    (setq i 0)
                    (while (< i (sslength ss))
                      (ssadd (ssname ss i) bss)
                      (setq i (1+ i)))
                    (autobead-ensure-layer *autobead-layer*)
                    (autobead-build
                      bss bdir
                      (= bside "Some")
                      (if (= bside "Some")
                        (mapcar '(lambda (k)
                                   (hs-entmid (cdr (assoc k btreads))))
                                bnums)
                        nil)))))))))))
  (princ))

;;; --------------------------- tutorial ---------------------------------

(defun hs-tut-pause ( )
  (princ "\n      --- press Enter to continue ---")
  (getstring)
  (princ))

(defun hs-tut-text (pt h s)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 s))))

;; Walkthrough for new users: pages of what HEMISTEP does and checks,
;; then a live demonstration drawn step by step with the same geometry
;; code the real command uses - the numbers are the reference example
;; this routine was built against.
(defun c:TUTORIALHEMISTEP ( / *error* undoflag oldce oldstyle org sp u dir
                              txth pt wallw wallA wallB ea eb pprev p cum
                              e1 e2 offd n lst wid dep crown pts kx)
  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (hs-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (princ))

  (princ (strcat "\n================ HEMISTEP TUTORIAL " *hs-version*
                 " ================"))
  (princ "\nHEMISTEP draws steps that act like chords inside a circle:")
  (princ "\nparallel step edges centered on a measuring axis, plus the")
  (princ "\nhemisphere boundary itself, rebuilt as one polyline of arc")
  (princ "\nsegments through every step end.")
  (hs-tut-pause)
  (princ "\nWHAT YOU SELECT DECIDES THE MODE")
  (princ "\n  LINE only ....... steps centered on the line, marching away")
  (princ "\n                    from it on the side you pick")
  (princ "\n  CURVE + LINE .... the line is the measuring axis; treads")
  (princ "\n                    start where it meets the curve, going in")
  (princ "\n  CURVE only ...... from the middle of the arc, going in")
  (princ "\n  (a curve may be an arc, circle, or polyline - including a")
  (princ "\n   composite hemisphere and a boundary this command drew)")
  (princ "\nTHE PROMPTS, IN ORDER")
  (princ "\n  1. LINE mode first asks the width of the step AT THE WALL -")
  (princ "\n     it anchors the boundary; no chord is drawn there.")
  (princ "\n  2. Then STEP TREAD, WIDTH, repeating.  Every step tread is")
  (princ "\n     from the previous step - never a running total.  Enter at")
  (princ "\n     a step tread = done; Back steps back one step; Same repeats.")
  (princ "\n     Enter at a width fits the step to the curve (curve modes)")
  (princ "\n     or repeats the previous width (line mode).")
  (princ "\n  3. One last distance to the back of the curve places the crown,")
  (princ "\n     and the boundary polyline is drawn through the step ends.")
  (princ "\n  4. Finally you may add a SIDE PROFILE: give each step depth")
  (princ "\n     (the vertical drop, top step first, Back supported), then")
  (princ "\n     pick the top of the wall and the side the steps descend.")
  (princ "\n  5. Bead the steps? [Yes/No] - every tread is beaded, so the")
  (princ "\n     only question is which steps have beaded SIDE WALLS:")
  (princ "\n     [All/Some], and Some takes the step numbers (\"1 3 4\").")
  (princ "\n     Then click the side to bead toward and AUTOBEAD does the")
  (princ "\n     rest on its own rules - it has to be loaded for this.")
  (hs-tut-pause)
  (princ "\nWHAT IT CHECKS AND HANDLES FOR YOU")
  (princ "\n  - warns on tilted UCS / non-flat lines / unusable layer")
  (princ "\n  - bare numbers read as inches; 1'4 style works anywhere")
  (princ "\n  - in the curve modes a width within 1/8\" of the curve's")
  (princ "\n    opening snaps to the curve; any other width is held and")
  (princ "\n    breaks the curve EQUALLY at both ends")
  (princ "\n  - each step measures against whichever part of a composite")
  (princ "\n    curve it lands on, nearest the axis")
  (princ "\n  - the boundary's arcs are fitted so the crown sits inside")
  (princ "\n    ONE arc, and a segment that would fold back is refused")
  (princ "\n  - dims: step treads chained along the axis (STANDARD INCHES),")
  (princ "\n    widths nested behind the start (SIDE STANDARD); one undo")
  (hs-tut-pause)

  (initget "Yes No")
  (if (= "No" (getkword (strcat "\nDraw a demonstration in this drawing?"
                                " [Yes/No] <Yes>: ")))
    (progn (princ "\nTutorial done - type HEMISTEP to use it for real.")
           (exit)))
  (setq pt (getpoint "\nPick a clear spot (about 300 x 150 needed): "))
  (if (null pt)
    (progn (princ "\nNo spot picked - tutorial done.") (exit)))
  (setq org  (trans pt 1 0)
        txth (hs-txth)
        sp   org                       ; middle of the base line
        u    '(1.0 0.0 0.0)
        dir  '(0.0 1.0 0.0)
        wallw 257.61)
  (command "_.UNDO" "_Begin")
  (setq undoflag T
        oldce (getvar "CMDECHO")
        oldstyle (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)

  (hs-mkline (hs-add sp (hs-scl u -140.0)) (hs-add sp (hs-scl u 140.0)))
  (hs-tut-text (hs-add org '(-135.0 -14.0 0.0)) (* 1.2 txth)
               "HEMISTEP demo: base-line mode - select this wall line")
  (princ "\n[1] The WALL drawn - in line mode this is all you select.")
  (princ "\n    Steps center on its middle and march off the side you")
  (princ "\n    pick.  The width at the wall here is 257.61 - it anchors")
  (princ "\n    both ends of the boundary but draws no chord.")
  (setq wallA (hs-add sp (hs-scl u (* 0.5 wallw)))
        wallB (hs-add sp (hs-scl u (* -0.5 wallw)))
        offd  (* 2.0 txth)
        pprev sp
        cum   0.0
        n     1)
  (hs-tut-pause)

  (foreach lst '((240.0 . 13.0) (216.0 . 12.0) (168.0 . 16.0)
                 (120.0 . 10.0))
    (setq wid (car lst)
          dep (cdr lst)
          p   (hs-add pprev (hs-scl dir dep))
          cum (+ cum dep)
          e1  (hs-add p (hs-scl u (* 0.5 wid)))
          e2  (hs-add p (hs-scl u (* -0.5 wid))))
    (hs-mkline e1 e2)
    (setq ea (append ea (list e1))
          eb (append eb (list e2)))
    (hs-dim *cs-width-dimstyle* e1 e2
            (hs-add sp (hs-scl dir (- (+ (* 0.5 wid) (* 1.5 txth))))))
    (hs-dim *cs-depth-dimstyle* pprev p
            (hs-add (hs-mid2 pprev p) (hs-scl u offd)))
    (princ (strcat "\n[" (itoa (1+ n)) "] Step " (itoa n) ": width "
                   (rtos wid) ", " (rtos dep) " past the previous edge ("
                   (rtos cum) " from the wall).  Parallel to the wall,"
                   " centered on the axis."))
    (hs-tut-pause)
    (setq pprev p n (1+ n)))

  (setq crown (hs-add pprev (hs-scl dir 9.45)))
  (hs-dim *cs-depth-dimstyle* pprev crown
          (hs-add (hs-mid2 pprev crown) (hs-scl u offd)))
  (setq pts (append (list wallA) ea (list crown) (reverse eb) (list wallB))
        kx  (+ 1 (length ea)))
  (hs-mkpoly pts (hs-blgs pts kx nil))
  (princ "\n[6] One last distance (9.45) places the CROWN, and the boundary")
  (princ "\n    polyline is drawn: wall - step ends - crown - step ends -")
  (princ "\n    wall, in arc segments fitted so the apex sits inside one")
  (princ "\n    arc.  This is the hemisphere the steps sit in.")
  (hs-tut-pause)

  (if oldstyle (hs-setstyle oldstyle))
  (command "_.UNDO" "_End")
  (setq undoflag nil)
  (setvar "CMDECHO" oldce)
  (princ "\n[7] Done.  One U removes the demo.  For the curve modes, draw")
  (princ "\n    an arc and run HEMISTEP selecting it (plus an axis line if")
  (princ "\n    you have one) - Enter at any width fits that step to the")
  (princ "\n    curve exactly.")
  (princ))

(princ (strcat "\nHEMISTEP.lsp " *hs-version*
               " loaded - HEMISTEP to draw hemisphere steps,"
               " TUTORIALHEMISTEP to learn it."))
(princ)

;;; ======================================================================
;;; >>> NORMIESTEP.lsp (v2.1) - verbatim from lisp/cornerstp/NORMIESTEP.lsp
;;; ======================================================================
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
;;;                      the step treads.  The side walls leave the wall
;;;                      square and run to the last tread; the corner
;;;                      treatment sits on the last step.
;;;   TWO LINES (a corner)
;;;                      the steps sit against the corner and always run
;;;                      OUTWARD from it.  You are asked which of the two
;;;                      lines the steps run off of - the same line the
;;;                      back-corner offset is measured on; the treads run
;;;                      parallel to it and butt against the other one.
;;;   A "U" ............ the outline the steps sit in is already drawn,
;;;                      so the treads are just filled in.  The BASE of
;;;                      the U - its closed end - is the wall the steps
;;;                      come off: the run STARTS there and marches out
;;;                      toward the open end, trimmed to the two arms.
;;;                      No width is asked for - the arms give it.  The
;;;                      U may already have its back corners drawn where
;;;                      the arms meet the base: three lines is a plain
;;;                      square-cornered U, five lines is one with Cut
;;;                      (diagonal) corners, and three lines plus two
;;;                      arcs is one with Radius (rounded) corners.
;;;                      Polylines work too, including bulged (rounded)
;;;                      corner segments.  Treads trim to whatever part
;;;                      of the side they land on - arm, diagonal, or
;;;                      arc.  A plain square U is asked for its back
;;;                      corners like the other modes.
;;;
;;; WORKFLOW
;;;   1.  Select the base line, the two lines of a corner, or a U-shaped
;;;       perimeter (LINEs or the straight segments of a POLYLINE).
;;;   2.  One-line mode asks which side the steps go.  Corner mode asks
;;;       which line the steps run off of.  The U needs neither.
;;;   3.  Unless it is a U, you give the step width ONCE - every step
;;;       gets it.  Then comes the corner treatment.  One-line mode asks
;;;       for the CORNERS OF THE LAST STEP - the two where the side
;;;       walls meet the last tread; the other modes ask for their BACK
;;;       CORNERS - the two where the sides of the run meet the wall it
;;;       comes off.  Either way a corner is
;;;         Square   - a true 90 degree corner (the default)
;;;         Radius   - a fillet arc, you give the radius
;;;         Cut      - a straight 45 degree diagonal, given as either
;;;                    its Offset back along each line or the Cut face
;;;                    length (each gives the other: cut = offset x
;;;                    root 2)
;;;         NotGiven - the order sheet never said.  The corner is drawn
;;;                    square, like Square, but a note on the drawing
;;;                    says it was never recorded, so nobody reads it
;;;                    as a measured 90.
;;;       In one-line mode the treatment is worked into the last step:
;;;       the last tread gives up the offset at each end, the side walls
;;;       stop that much short, and the corner piece bridges the two.
;;;       In corner mode the treatment stays at the wall and flares the
;;;       mouth of the recess the run sits in by that offset; in a U it
;;;       is cut into the corner and the treads trim to it.  A U that
;;;       already has its back corners drawn is not asked.
;;;   4.  Then step treads, one per step - each the plan-view spacing
;;;       measured FROM THE PREVIOUS TREAD (from the base line for the
;;;       first).  Distances read architectural style: a bare number is
;;;       inches (drawing units) and feet-inch entry like 1'4 (= 16")
;;;       works whatever the units setting.
;;;   5.  Enter at a step tread prompt = done.  Back steps back one
;;;       step: it removes the step just drawn (its line and its
;;;       dimensions).  Undo, the old keyword, is still accepted.  Same
;;;       repeats the previous step tread, which is what most runs want.
;;;   6.  The side lines of the run are drawn for the one-line and
;;;       corner modes.  One-line mode draws plain side walls, square
;;;       off the base wall, running from the wall to the last tread -
;;;       the treatment sits on the last step's corners, so a Radius or
;;;       Cut one stops the walls an offset short and the corner
;;;       piece finishes the trip.  In corner mode only the outer side
;;;       is drawn - with its back corner flare at the wall - since the
;;;       steps run outward from the corner and the picked line closes
;;;       the inner side.  The U already has its arms, so only a back
;;;       corner asked for there is drawn.
;;;   7.  Optional dimensions: the step treads chained along the run,
;;;       plus the step width once (it is the same for every step).
;;;   8.  Optionally a SIDE PROFILE: you give each step's STEP DEPTH -
;;;       its vertical drop, top step first (Enter repeats the previous
;;;       one, Back steps back) - then pick the top of the wall and the
;;;       side the steps descend, and the staircase silhouette is drawn
;;;       in world X/Y, with a drop-dim chain behind the wall and a
;;;       tread-dim chain along the bottom when dims are on.
;;;   9.  Finally, BEAD THE STEPS.  Every tread is beaded - that is the
;;;       assumption - so the only thing asked is which steps carry the
;;;       bead along their side walls: All of them, or Some, given by
;;;       step number.  AUTOBEAD does the work on its own rules (2"
;;;       toward the side you click, onto its Bead Track layer), so
;;;       AUTOBEAD.lsp has to be loaded; when it is not, the run says
;;;       so and finishes without beading.  The beads are their own
;;;       undo group - AutoCAD does not nest them - so one U undoes
;;;       the beads and the next undoes the steps.
;;;
;;; OPTIONAL SETTINGS (set these before running the command)
;;;   *CS-WIDTH-TOL*      width tolerance in drawing units.  When nil
;;;                       (the default) it is 1/8" converted through the
;;;                       drawing's INSUNITS setting.
;;;   *CS-DEPTH-DIMSTYLE* dim style for step-tread dims (the side
;;;                       profile's dims use it too).
;;;   *CS-WIDTH-DIMSTYLE* dim style for step-width dims.
;;;   *CS-DIM-LAYER*      layer for the dimensions.  When nil (the
;;;                       default) the current layer is used.
;;;
;;; NOTES
;;;   - Geometry is assumed to be drawn in plan view.  The routine warns
;;;     when the current UCS is not World, when a selected line is not
;;;     flat, and when the current layer is off/frozen/locked.
;;;   - Steps are drawn as LINEs on the current layer.
;;;   - One U / UNDO reverses the whole command; a bead run added at
;;;     the end is its own group, so it takes a U of its own.
;;; ======================================================================

;; Settings - only defined if not already set, so this file, CORNERSTP
;; and HEMISTEP stay in sync no matter which one loads first.
(if (not (boundp '*cs-width-tol*))      (setq *cs-width-tol* nil))
(if (not (boundp '*cs-dim-layer*))      (setq *cs-dim-layer* nil))
(if (not (boundp '*cs-depth-dimstyle*)) (setq *cs-depth-dimstyle* "STANDARD INCHES"))
(if (not (boundp '*cs-width-dimstyle*)) (setq *cs-width-dimstyle* "SIDE STANDARD"))

(vl-load-com) ; ActiveX is used to set styles (handles names with spaces)

(setq *ns-version* "v2.1") ; printed on load and at command start so a
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

;; Draw a U piece record - a straight cut or a corner arc.
(defun ns-drawpc (pc)
  (if (= "S" (car pc))
    (ns-mkline (cadr pc) (caddr pc))
    (entmake (list '(0 . "ARC")
                   (cons 10 (list (car (nth 3 pc)) (cadr (nth 3 pc)) 0.0))
                   (cons 40 (nth 4 pc))
                   (cons 50 (nth 5 pc))
                   (cons 51 (nth 6 pc))))))

;; The back corner where arm AP meets the base BS of a U, cut OFF back
;; along each of them - KIND "Cut" gives a 45 degree diagonal, "Radius"
;; a fillet arc tangent to both.  Unlike the recess corner of a run that
;; comes off an open wall, this one is cut INTO the U, since the arms
;; are the sides of the step itself.  The piece comes back in the same
;; form as the rest of the U so the treads trim to it; nil when the
;; offset will not fit inside the corner.
(defun ns-ucorner (bs ap kind off / b1 b2 fe ub ua t1 t2 o a1 a2 sw)
  (setq b1 (if (< (ns-ptseg (car bs) (car ap) (cadr ap))
                  (ns-ptseg (cadr bs) (car ap) (cadr ap)))
             (car bs)
             (cadr bs))
        b2 (if (equal b1 (car bs)) (cadr bs) (car bs))
        fe (ns-far ap b1)
        ub (ns-unit (ns-vec b1 b2))
        ua (ns-unit (ns-vec b1 fe)))
  (if (and ub ua (> off 0.0)
           (< off (distance b1 b2))
           (< off (distance b1 fe)))
    (progn
      (setq t1 (ns-add b1 (ns-scl ub off))     ; in along the base
            t2 (ns-add b1 (ns-scl ua off)))    ; out along the arm
      (if (= kind "Radius")
        (progn
          ;; centre sits one radius off each leg, so the arc is tangent
          ;; to both; the record spans counterclockwise t1 -> t2
          (setq o  (ns-add t1 (ns-scl ua off))
                a1 (angle o t1)
                a2 (angle o t2))
          (if (< a2 a1) (setq a2 (+ a2 pi pi)))
          (if (> (- a2 a1) pi)                 ; the other way round is the arc
            (setq sw a1 a1 (- a2 pi pi) a2 sw))
          (if (< a1 0.0) (setq a1 (+ a1 pi pi) a2 (+ a2 pi pi)))
          (list "A" t1 t2 o off a1 a2))
        (list "S" t1 t2)))))

;;; -------------------------- ask helpers -------------------------------

;; Keyword question of STANDARDS.md section 1.  KWS is the initget list
;; (hidden aliases included, spelled ALL-CAPS so they must be typed in
;; full and cannot steal a canonical hotkey); SHOWN is the bracket text,
;; which carries only the options a click may send.  DFLT nil = an
;; answer is required.
(defun ns-askkw (msg kws shown dflt / v)
  (initget (if dflt 0 1) kws)
  (setq v (getkword (strcat "\n" msg " [" shown "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((null v) (if dflt dflt (ns-askkw msg kws shown dflt)))
        (t v)))

;; The Treatment question of STANDARDS.md section 2: "How should
;; <subject> be treated?"  SUBJECT reads like prose ("the back
;; corners").  Returns "Square", "Radius", "Cut" or "NotGiven" - the
;; old words this tool used to store, and NG, are still accepted typed
;; in full and are normalized HERE, never downstream.
(defun ns-asktreat (subject dflt / v)
  (setq v (ns-askkw (strcat "How should " subject " be treated?")
                    "Square Radius Cut NotGiven NG 90 ROUNDED DIAG DIAGONAL"
                    "Square/Radius/Cut/NotGiven"
                    dflt))
  (cond ((= v "NG") "NotGiven")
        ((= v "90") "Square")
        ((= v "ROUNDED") "Radius")
        ((member v '("DIAG" "DIAGONAL")) "Cut")
        (t v)))

;;; --------------------------- bead helpers -----------------------------

;; The step numbers typed at a prompt - "1 3 4", "1,3,4" and "1, 3 and 4"
;; all read the same.  Anything that is not a digit separates.
(defun ns-numlist (str / out tok i c)
  (setq out '() tok "" i 0)
  (while (<= i (strlen str))
    (setq c (if (< i (strlen str)) (substr str (1+ i) 1) " "))
    (if (and (>= (ascii c) 48) (<= (ascii c) 57))
      (setq tok (strcat tok c))
      (progn
        (if (/= tok "") (setq out (cons (atoi tok) out)))
        (setq tok "")))
    (setq i (1+ i)))
  (reverse out))

;; The tread line of every step that was committed, newest first, as
;; (step-number . ename).  A step's log record is (entities cum pprev n),
;; and the only LINE among those entities is its tread - the dimensions
;; that may sit beside it are DIMENSIONs.
(defun ns-treadents (log / out rec e ln)
  (setq out '())
  (foreach rec log
    (setq ln nil)
    ;; ...-since lists newest first, and a step draws its tread before
    ;; any side line or dimension, so the LAST line seen is the tread
    (foreach e (car rec)
      (if (and e (entget e)
               (= "LINE" (cdr (assoc 0 (entget e)))))
        (setq ln e)))
    (if ln (setq out (cons (cons (nth 3 rec) ln) out))))
  ;; the log runs newest first, so consing through it already leaves
  ;; the pairs in step order - lowest first, the way they were drawn
  out)

;; The step numbers on offer, as "1, 2, 3" - so the numbers prompt can
;; be answered without scrolling back through the run.
(defun ns-numsay (pairs / out pr)
  (setq out "")
  (foreach pr pairs
    (setq out (strcat out (if (= out "") "" ", ") (itoa (car pr)))))
  out)

;; Midpoint (WCS) of a LINE entity.
(defun ns-entmid (e / ed)
  (setq ed (entget e))
  (ns-mid2 (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))

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

;; Draw one side of the run: the back corner where it meets the wall at
;; E - the wall carries on along WDIR, the run heads along DIR for LEN -
;; and then the side line down to the last tread.
;;   RTYPE nil / "Square"   - a plain 90 degree side line off the wall
;;   "Radius"               - a fillet arc of radius RRAD
;;   "Cut"                  - a 45 degree diagonal, ROFF back each leg
;; Either treatment flares the mouth of the recess by that offset.
(defun ns-side (e wdir dir len rtype roff rrad / off t1 t2 o)
  (setq off (cond ((and (= rtype "Cut") roff) roff)
                  ((and (= rtype "Radius") rrad) rrad)
                  (0.0)))
  (if (>= off len)
    (progn
      (princ (strcat "\n  Note: the back corner (" (rtos off)
                     ") is deeper than the whole run (" (rtos len)
                     ") - that side is drawn square."))
      (setq off 0.0 rtype "Square")))
  (setq t1 (ns-add e (ns-scl wdir off))      ; tangent/cut point on the wall
        t2 (ns-add e (ns-scl dir off)))      ; and on the side of the run
  (cond
    ((and (= rtype "Cut") (> off 0.0))
     (ns-mkline t1 t2))
    ((and (= rtype "Radius") (> off 0.0))
     ;; centre sits one radius off each leg, so the arc is tangent to both
     (setq o (ns-add t1 (ns-scl dir off)))
     (ns-mkfillet o off t1 t2)))
  (ns-mkline t2 (ns-add e (ns-scl dir len))))

;; The corner of the LAST step of a centered (one-line) run, where the
;; side wall meets the last tread.  E is where the side wall leaves the
;; base wall, UIN the unit vector along the tread toward the run's
;; centre, DIR the way the run heads, LEN the whole run - so the
;; theoretical square corner sits at C = E + DIR x LEN.
;;   "Cut"     - a 45 degree diagonal from OFF back along the side wall
;;               to OFF in along the last tread
;;   "Radius"  - a fillet arc of radius OFF tangent to both
;; The side wall and the trimmed tread are drawn by the caller; OFF 0
;; (a square corner) draws nothing.
(defun ns-outer (e uin dir len rtype off / c t1 t2 o)
  (setq c  (ns-add e (ns-scl dir len))       ; the theoretical square corner
        t1 (ns-add c (ns-scl dir (- off)))   ; back along the side wall
        t2 (ns-add c (ns-scl uin off)))      ; in along the last tread
  (cond
    ((and (= rtype "Cut") (> off 0.0))
     (ns-mkline t1 t2))
    ((and (= rtype "Radius") (> off 0.0))
     ;; centre sits one offset off each leg, so the arc is tangent to both
     (setq o (ns-add t1 (ns-scl uin off)))
     (ns-mkfillet o off t1 t2))))

;; A note on the drawing at PT (WCS), height H.  The geometry cannot
;; say that a corner treatment was never recorded - this does.
(defun ns-note (pt h str)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 str))))

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
                        pprev oldce oldstyle oldlu slog mark svcum svp svn
                        cum rec rtype roff rrad rcut mouth usquare
                        bc1 bc2 arcps pieces freep chain cure rest nxt
                        basepc side1 side2 pc qc e coff tent te1 te2
                        rsubj ngp ngv
                        bmark bsides btreads bnums bside bdir bss pr be
                        tlist svals treads prevv nsteps drops k dv
                        wpu wpt spt dx sgn totrun totdrop px0 cx cy
                        lowy tt)

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
      (progn (princ "\n  Already at the first step.") nil)
      (progn
        (setq rec (car slog))
        (foreach e (car rec) (if (and e (entget e)) (entdel e)))
        (setq cum   (nth 1 rec)
              pprev (nth 2 rec)
              n     (nth 3 rec)
              drawn (1- drawn)
              slog  (cdr slog)
              tlist (cdr tlist))
        (redraw)
        (princ "\n  Stepping back one step.")
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
     ;; keep DIR square to the treads so step treads measure true
     (setq dir (ns-unit (ns-scl (ns-perp u)
                                (if (< (ns-dot (ns-perp u) dir) 0.0)
                                  -1.0 1.0)))
           sp  corner)
     (princ (strcat "\nSteps against the corner, running OUTWARD from it"
                    " off the picked line.")))

    ;; ---------- a U: the outline is drawn, fill in the treads ----------
    ;; The parts - arms, an optional back corner on each side (diagonal
    ;; cut or fillet arc), and the base - are chained end to end from one
    ;; free end to the other; the middle of the chain is the base and
    ;; each half-chain is one side's trimming boundary.  The base is the
    ;; wall the steps come off, so the run STARTS there and marches out
    ;; toward the open end of the U.
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
     (setq base  (list (cadr basepc) (caddr basepc))
           u     (ns-unit (ns-vec (car base) (cadr base)))
           mouth (ns-mid2 f1 f2)                ; the open end of the U
           sp    (ns-mid2 (car base) (cadr base))) ; the base - the wall
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
     (setq usquare (= 3 d2))                    ; no back corners drawn yet
     (if (not usquare)
       (princ "\nU with its back corners drawn: treads trim to them."))
     ;; DIR runs from the base out toward the open end, square to the treads
     (setq dir (ns-unit (ns-scl (ns-perp u)
                                (if (< (ns-dot (ns-perp u)
                                               (ns-vec sp mouth))
                                       0.0)
                                  -1.0 1.0))))
     (princ (strcat "\nU outline: the run starts at its base - the wall -"
                    " and marches out, trimmed to its arms."))))

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

  ;; ---- 3b. the corner treatment ----------------------------------------
  ;; The corners are square (90 degrees), radiused, or cut at 45
  ;; degrees - but where they sit depends on the mode.  A centered
  ;; (one-line) run puts the treatment on the LAST step's two corners,
  ;; where the side walls meet the last tread: the tread gives up the
  ;; offset at each end, the side walls stop that much short, and the
  ;; corner piece bridges the two.  Corner mode keeps its BACK corners
  ;; at the wall the run comes off, where the treatment also flares the
  ;; mouth of the recess; in a U it is cut into the corner where the arm
  ;; meets the base and the treads trim to it.  A U that already has its
  ;; back corners drawn keeps them.
  (if (and (= mode "U") (not usquare))
    (princ (strcat "\nBack corners: already drawn on the U - using them"
                   " as they are."))
    (progn
      ;; the subject reads like prose, as STANDARDS.md section 2 has it
      (setq rsubj (if (= mode "LINE")
                    "the corners of the last step"
                    "the back corners")
            rtype (ns-asktreat rsubj "Square"))
      (cond
        ((= rtype "Radius")
         (initget 7)
         (setq rrad (getdist (strcat "\nRadius for " rsubj ": "))
               roff rrad))
        ((= rtype "Cut")
         ;; the offset and the cut face are the two legs and the
         ;; hypotenuse of the same 45 degree triangle, so either one
         ;; gives the other
         (initget "Offset Cut")
         (if (= "Cut" (getkword
                        (strcat "\nIs the cut given as its"
                                " [Offset/Cut] <Offset>: ")))
           (progn
             (initget 7)
             (setq rcut (getdist (strcat "\nCut face length for "
                                         rsubj ": "))
                   roff (/ rcut (sqrt 2.0))))
           (progn
             (initget 7)
             (setq roff (getdist "\nOffset back along each line: ")
                   rcut (* roff (sqrt 2.0)))))
         (princ (strcat "\n  A 45 degree cut on " rsubj ": offset "
                        (rtos roff) " each way, cut face "
                        (rtos rcut) ".")))
        ((= rtype "NotGiven")
         (princ (strcat "\n  Not Given: " rsubj " are drawn square, and"
                        " a note on the drawing says the treatment was"
                        " never recorded."))))
      ;; a U has its arms already, so the corner is built into the sides
      ;; the treads trim to - and drawn once the run is done.  NotGiven
      ;; is not cut in: its geometry is square, like Square's.
      (if (and (= mode "U") (member rtype '("Radius" "Cut")))
        (progn
          (setq bc1 (ns-ucorner base arm1 rtype roff)
                bc2 (ns-ucorner base arm2 rtype roff))
          (if (and bc1 bc2)
            (setq side1 (cons bc1 side1)
                  side2 (cons bc2 side2))
            (progn
              (princ (strcat "\n  That back corner does not fit inside the"
                             " U - the corners are left square."))
              (setq bc1 nil bc2 nil rtype "Square")))))))

  ;; ---- 4. dimension the steps? -----------------------------------------
  (initget "Yes No")
  (setq dimflag (/= "No" (getkword "\nDimension the steps? [Yes/No] <Yes>: ")))
  (if dimflag
    (progn
      (setq oldstyle (getvar "DIMSTYLE")) ; restored when the command ends
      (if (not (tblsearch "DIMSTYLE" *cs-depth-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-depth-dimstyle*
                       "\" not found - step treads use the current style.")))
      (if (not (tblsearch "DIMSTYLE" *cs-width-dimstyle*))
        (princ (strcat "\nNote: dim style \"" *cs-width-dimstyle*
                       "\" not found - the step width uses the current style.")))
      (if (and *cs-dim-layer* (not (ns-layerok *cs-dim-layer*)))
        (princ (strcat "\nNote: dim layer \"" *cs-dim-layer*
                       "\" is missing or not drawable - using the"
                       " current layer.")))))
  ;; The step-tread chain runs just off the run's axis, the way the corner
  ;; and hemisphere routines (and the shop's own example drawings) do -
  ;; NOT outside the whole run, which would drag every chain dim's
  ;; extension lines across the entire step field.
  (setq offd   (* 2.0 txth)
        dimoff (ns-scl u offd))

  ;; ---- 5. step treads, one per step ------------------------------------
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
             ;; Undo is the old keyword, kept as a hidden synonym
             (initget 6 (strcat "Back" (if lastdep " Same" "") " Undo"))
             (setq dep (getdist
                         (strcat "\nStep " (itoa n)
                                 " - step tread [Back"
                                 (if lastdep "/Same" "") "]"
                                 (if lastdep
                                   (strcat " <Enter = done, Same = "
                                           (rtos lastdep) ">: ")
                                   " <Enter = done>: "))))
             (if (= (type dep) 'STR)
               (cond
                 ((or (= dep "Back") (= dep "Undo"))
                  (ns-popstep) (setq dep 'RETRY))
                 ((= dep "Same")
                  (if lastdep
                    (setq dep lastdep)
                    (progn (princ "\n  No previous step tread.")
                           (setq dep 'RETRY))))
                 (T (setq dep 'RETRY)))))
           dep))
    (setq mark (entlast)
          svcum cum svp pprev svn n
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
         ;; out past the open end of the U: the run is full
         ((and (< (ns-dot (ns-vec p f1) dir) 0.0)
               (< (ns-dot (ns-vec p f2) dir) 0.0))
          (princ (strcat "\n  Step " (itoa n) " would fall past the open"
                         " end of the U - stopping."))
          (setq e1 nil e2 nil stopf T))
         ((or (null e1) (null e2))
          (princ (strcat "\n  Step " (itoa n)
                         ": cannot reach both sides - step skipped."))
          (setq e1 nil e2 nil)))))
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
              slog  (cons (list (ns-since mark) svcum svp svn) slog)
              tlist (cons cum tlist))))
    (setq n (1+ n)))

  ;; ---- 6. sides of the run, the corner treatment, and the width dim ---
  (if (> drawn 0)
    (progn
      (setq bmark (entlast))               ; the side geometry starts here
      (cond
        ;; both sides of a centered run: plain side walls, square off
        ;; the base wall, running to the last tread - the treatment sits
        ;; on the last step's corners, so the last tread gives up the
        ;; offset at each end and a corner piece bridges each side wall
        ;; to it
        ((= mode "LINE")
         ;; resolve the corner offset once for the whole run
         (setq coff (cond ((and (= rtype "Cut") roff) roff)
                          ((and (= rtype "Radius") rrad) rrad)
                          (0.0)))
         (cond
           ((<= coff 0.0))
           ((>= coff cum)
            (princ (strcat "\n  Note: the corner (" (rtos coff)
                           ") is deeper than the whole run (" (rtos cum)
                           ") - the last step is drawn square."))
            (setq coff 0.0))
           ((>= (* 2.0 coff) wid)
            (princ (strcat "\n  Note: two corners of " (rtos coff)
                           " would meet across the last tread ("
                           (rtos wid) " wide) - the last step is drawn"
                           " square."))
            (setq coff 0.0)))
         ;; trim the last tread by the offset at each end - the step
         ;; loop drew it full width and logged it with its step
         (if (> coff 0.0)
           (progn
             (setq te1  (ns-add pprev (ns-scl u (* 0.5 wid)))
                   te2  (ns-add pprev (ns-scl u (* -0.5 wid)))
                   tent nil)
             (foreach e (car (car slog))
               (if (and (null tent) e (setq ed (entget e))
                        (= "LINE" (cdr (assoc 0 ed)))
                        (or (and (equal (cdr (assoc 10 ed)) te1 1e-6)
                                 (equal (cdr (assoc 11 ed)) te2 1e-6))
                            (and (equal (cdr (assoc 10 ed)) te2 1e-6)
                                 (equal (cdr (assoc 11 ed)) te1 1e-6))))
                 (setq tent e)))
             (if tent
               (progn
                 (setq ed (entget tent)
                       p  (ns-add pprev (ns-scl u (- (* 0.5 wid) coff)))
                       pt (ns-add pprev (ns-scl u (- coff (* 0.5 wid)))))
                 (if (equal (cdr (assoc 10 ed)) te1 1e-6)
                   (setq ed (subst (cons 10 p)  (assoc 10 ed) ed)
                         ed (subst (cons 11 pt) (assoc 11 ed) ed))
                   (setq ed (subst (cons 10 pt) (assoc 10 ed) ed)
                         ed (subst (cons 11 p)  (assoc 11 ed) ed)))
                 (entmod ed))
               (progn
                 (princ (strcat "\n  Note: the last tread was not found"
                                " to trim - the sides are drawn square."))
                 (setq coff 0.0)))))
         ;; the side walls start ON the wall and stop one offset short
         ;; of the last tread (a square run goes the whole way); then
         ;; the corner pieces
         (setq e (ns-add sp (ns-scl u (* 0.5 wid))))
         (ns-mkline e (ns-add e (ns-scl dir (- cum coff))))
         (if (> coff 0.0)
           (ns-outer e (ns-scl u -1.0) dir cum rtype coff))
         (setq e (ns-add sp (ns-scl u (* -0.5 wid))))
         (ns-mkline e (ns-add e (ns-scl dir (- cum coff))))
         (if (> coff 0.0)
           (ns-outer e u dir cum rtype coff)))
        ;; the outer side only - the steps run outward from the corner,
        ;; so the picked line closes the inner side already
        ((= mode "CORNER")
         (ns-side (ns-add corner (ns-scl u wid))
                  u dir cum rtype roff rrad))
        ;; a U has its arms drawn already - only a back corner asked for
        ;; here is new geometry
        ((and (= mode "U") bc1 bc2)
         (ns-drawpc bc1)
         (ns-drawpc bc2)))
      ;; ... and ends here: the sides and their corner pieces, which is
      ;; what AUTOBEAD wants alongside the treads.  Taken before the
      ;; note and the width dim, which are annotation, not pool lines.
      (setq bsides (ns-since bmark))
      ;; A corner nobody recorded is drawn square, so the drawing must
      ;; say so or it reads as a measured 90.  One note carries both
      ;; corners - they share the one answer - and it sits just outside
      ;; the corner it speaks for.
      (if (= rtype "NotGiven")
        (progn
          (cond
            ((= mode "LINE")
             (setq ngp  (ns-add (ns-add sp (ns-scl u (* 0.5 wid)))
                                (ns-scl dir cum))
                   ngv  (ns-unit (ns-add u dir))))
            ((= mode "CORNER")
             (setq ngp (ns-add corner (ns-scl u wid))
                   ngv u))
            (T
             (setq ngp (ns-mid2 (car base) (cadr base))
                   ngv (ns-scl dir -1.0))))
          (ns-note (ns-add ngp (ns-scl ngv (* 2.0 txth))) txth
                   "CORNERS NOT GIVEN - DRAWN SQUARE")))
      (if dimflag
        (ns-dim *cs-width-dimstyle* first1 first2
                (ns-add sp (ns-scl dir (- (+ (* 0.5 (distance first1 first2))
                                             (* 1.5 txth)))))))))

  ;; ---- 6b. side profile ------------------------------------------------
  ;; The plan run gave each step's STEP TREAD; here each step's STEP
  ;; DEPTH - its vertical drop - is asked, top step first, and the
  ;; staircase silhouette is drawn in world X/Y off a picked wall-top
  ;; point.  Still inside the command's undo group, and its dims use
  ;; the depth dim style like the tread chain.
  (if (> drawn 0)
    (progn
      (initget "Yes No")
      (if (/= "No" (getkword "\nAdd a side profile? [Yes/No] <Yes>: "))
        (progn
          ;; the treads, top step first: sort the recorded distances
          ;; from the run start ascending - the first is the first
          ;; tread, each successive difference the next
          (setq svals  (vl-sort tlist '<)
                prevv  0.0
                treads nil)
          (foreach tt svals
            (if (> (- tt prevv) 1e-6)
              (setq treads (cons (- tt prevv) treads)))
            (setq prevv tt))
          (setq treads (reverse treads)
                nsteps (length treads))
          ;; the drops, top step first, with Back (Undo, the old
          ;; keyword, is a hidden synonym)
          (setq drops nil k 1)
          (while (<= k nsteps)
            (if (= k 1)
              (progn
                (initget 7 "Back Undo")
                (setq dv (getdist "\nStep 1 - step depth (the drop): ")))
              (progn
                (initget 6 "Back Undo")
                (setq dv (getdist
                           (strcat "\nStep " (itoa k)
                                   " - step depth [Back] <"
                                   (rtos (car drops)) ">: ")))))
            (cond
              ((and (= (type dv) 'STR)
                    (or (= dv "Back") (= dv "Undo")))
               (if (= k 1)
                 (princ "\n  Already at the first step.")
                 (progn
                   (setq k (1- k) drops (cdr drops))
                   (princ "\n  Stepping back one step."))))
              ((null dv)                         ; Enter = same as previous
               (setq drops (cons (car drops) drops) k (1+ k)))
              (T
               (setq drops (cons dv drops) k (1+ k)))))
          (setq drops (reverse drops))
          ;; where the profile goes and which way the steps descend
          (setq wpu (getpoint
                      "\nPick the top of the wall for the side profile: "))
          (if (null wpu)
            (princ "\nNo point picked - no side profile drawn.")
            (progn
              (setq wpt (ns-flat (trans wpu 1 0))
                    sgn nil)
              (while (and (null sgn)
                          (setq spt (getpoint wpu
                                      (strcat "\nPick a point on the side"
                                              " the steps descend: "))))
                (setq dx (- (car (trans spt 1 0)) (car wpt)))
                (if (< (abs dx) 1e-10)
                  (princ "\nPick left or right of the wall, not on it.")
                  (setq sgn (if (< dx 0.0) -1.0 1.0))))
              (if (null sgn)
                (princ "\nNo side picked - no side profile drawn.")
                (progn
                  (setq totrun  (apply '+ treads)
                        totdrop (apply '+ drops)
                        px0     (car wpt)
                        cx      px0
                        cy      (cadr wpt)
                        lowy    (- (cadr wpt) totdrop)
                        k       0)
                  (foreach tt treads
                    (setq dv (nth k drops))
                    ;; the drop, straight down ...
                    (ns-mkline (list cx cy 0.0) (list cx (- cy dv) 0.0))
                    (if dimflag                  ; one chain behind the wall
                      (ns-dim *cs-depth-dimstyle*
                              (list cx cy 0.0) (list cx (- cy dv) 0.0)
                              (list (- px0 (* sgn offd))
                                    (- cy (* 0.5 dv)) 0.0)))
                    (setq cy (- cy dv))
                    ;; ... then the tread, out the way the steps descend
                    (ns-mkline (list cx cy 0.0)
                               (list (+ cx (* sgn tt)) cy 0.0))
                    (if dimflag                  ; one chain along the bottom
                      (ns-dim *cs-depth-dimstyle*
                              (list cx cy 0.0)
                              (list (+ cx (* sgn tt)) cy 0.0)
                              (list (+ cx (* sgn 0.5 tt))
                                    (- lowy offd) 0.0)))
                    (setq cx (+ cx (* sgn tt))
                          k  (1+ k)))
                  (princ (strcat "\nSide profile drawn: " (itoa nsteps)
                                 " step(s), total run " (rtos totrun)
                                 ", total drop " (rtos totdrop)
                                 "."))))))))))

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

  ;; ---- 8. bead the steps -----------------------------------------------
  ;; AUTOBEAD does the beading, on its own rules and in its own undo
  ;; group - which is why this sits outside ours: AutoCAD does not nest
  ;; undo groups, so one U undoes the beads and the next undoes the
  ;; steps.  Every tread is beaded; the only question left is which
  ;; steps carry the bead along their side walls, and that is answered
  ;; by step number here instead of by clicking each one.
  (if (> drawn 0)
    (if (not (boundp 'autobead-build))
      (princ (strcat "\nAUTOBEAD is not loaded - APPLOAD AUTOBEAD.lsp"
                     " if you want these steps beaded."))
      (progn
        (initget "Yes No")
        (if (/= "No" (getkword "\nBead the steps? [Yes/No] <Yes>: "))
          (progn
            (setq btreads (ns-treadents slog)
                  bnums   nil)
            (if (null btreads)
              (princ "\nNo tread lines to bead.")
              (progn
                ;; every tread is beaded - the side walls are the question
                (initget "All Some")
                (setq bside (cond ((getkword (strcat "\nWhich steps have"
                                                     " beaded side walls?"
                                                     " [All/Some] <All>: ")))
                                  ("All")))
                (if (= bside "Some")
                  (progn
                    (princ (strcat "\n  Steps drawn: "
                                   (ns-numsay btreads)))
                    (setq bnums (ns-numlist
                                  (getstring T (strcat "\nStep numbers with"
                                                       " beaded sides: "))))
                    (setq bnums (vl-remove-if-not
                                  '(lambda (k) (assoc k btreads)) bnums))
                    (if (null bnums)
                      (progn
                        (princ (strcat "\n  No step numbers recognized -"
                                       " beading every side wall full"
                                       " length."))
                        (setq bside "All")))))
                (setq bdir (getpoint "\nClick the side to bead toward: "))
                (if (null bdir)
                  (princ "\nNo direction picked - nothing beaded.")
                  (progn
                    ;; the treads, the sides and their corner pieces, and
                    ;; the line(s) the run came off: the pool lines of
                    ;; this pocket, which is what AUTOBEAD beads
                    (setq bss (ssadd))
                    (foreach pr btreads (ssadd (cdr pr) bss))
                    (foreach be bsides
                      (if (and be (entget be)) (ssadd be bss)))
                    (setq i 0)
                    (while (< i (sslength ss))
                      (ssadd (ssname ss i) bss)
                      (setq i (1+ i)))
                    (autobead-ensure-layer *autobead-layer*)
                    (autobead-build
                      bss bdir
                      (= bside "Some")
                      (if (= bside "Some")
                        (mapcar '(lambda (k)
                                   (ns-entmid (cdr (assoc k btreads))))
                                bnums)
                        nil)))))))))))
  (princ))

;;; --------------------------- tutorial ---------------------------------

(defun ns-tut-pause ( )
  (princ "\n      --- press Enter to continue ---")
  (getstring)
  (princ))

(defun ns-tut-text (pt h s)
  (entmake (list '(0 . "TEXT")
                 (cons 10 (list (car pt) (cadr pt) 0.0))
                 (cons 40 h)
                 (cons 1 s))))

;; Walkthrough for new users: pages of what NORMIESTEP does and checks,
;; then a live demonstration drawn step by step with the same geometry
;; code the real command uses.
(defun c:TUTORIALNORMIESTEP ( / *error* undoflag oldce oldstyle org sp u dir
                                txth pt wid off n lst dep cum pprev p e1 e2
                                offd first1 first2 hw)
  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if oldstyle (ns-setstyle oldstyle))
    (if oldce (setvar "CMDECHO" oldce))
    (princ))

  (princ (strcat "\n================ NORMIESTEP TUTORIAL " *ns-version*
                 " ================"))
  (princ "\nNORMIESTEP draws the most normal steps of all: straight,")
  (princ "\nparallel treads, every one the SAME width.")
  (ns-tut-pause)
  (princ "\nWHAT YOU SELECT DECIDES THE MODE")
  (princ "\n  ONE LINE ........ steps centered on it, on the side you pick")
  (princ "\n  TWO LINES ....... a corner: the steps sit against it and run")
  (princ "\n                    OUTWARD, off the line you pick")
  (princ "\n  A U ............. the outline is drawn; treads fill in,")
  (princ "\n                    trimmed to its arms.  The BASE of the U is")
  (princ "\n                    the wall: the run starts there and marches")
  (princ "\n                    out to the open end.  Its back corners may")
  (princ "\n                    already be drawn square, diagonal (5 lines)")
  (princ "\n                    or rounded (arcs / bulged polyline corners)")
  (princ "\nTHE PROMPTS, IN ORDER")
  (princ "\n  1. The step width, ONCE (skipped for a U - its arms set it)")
  (princ "\n  2. How should the corners be treated? - the one question")
  (princ "\n     every Calofin tool asks the same way:")
  (princ "\n       Square   a true 90 degree corner")
  (princ "\n       Radius   a fillet arc, you give the radius")
  (princ "\n       Cut      a 45 degree diagonal, given as its Offset or")
  (princ "\n                its Cut face length (cut = offset x root 2)")
  (princ "\n       NotGiven never recorded: drawn square, and noted on")
  (princ "\n                the drawing so it is not read as a real 90")
  (princ "\n     In one-line mode the treatment sits on the corners of")
  (princ "\n     the LAST step, where the side walls meet the last tread;")
  (princ "\n     in corner mode on the BACK corners at the wall; a U cuts")
  (princ "\n     it into its base corners (one already drawn is not")
  (princ "\n     asked).  The old words still work typed in full: 90,")
  (princ "\n     ROUNDED, DIAG and DIAGONAL.")
  (princ "\n  3. Dimension the steps? [Yes/No]")
  (princ "\n  4. Step treads, one per step, each from the previous")
  (princ "\n     tread.  Enter = done, Back = step back one (removes")
  (princ "\n     it), Same = repeat the previous step tread.")
  (princ "\n  5. Add a side profile? [Yes/No] - each step's STEP DEPTH")
  (princ "\n     (its vertical drop), top step first, then pick the top")
  (princ "\n     of the wall and the side the steps descend; the")
  (princ "\n     silhouette is drawn in world X/Y, dims and all.")
  (princ "\n  6. Bead the steps? [Yes/No] - every tread is beaded, so")
  (princ "\n     the only question is which steps have beaded SIDE")
  (princ "\n     WALLS: [All/Some], and Some takes the step numbers")
  (princ "\n     (\"1 3 4\").  Then click the side to bead toward, and")
  (princ "\n     AUTOBEAD does the rest on its own rules.  It has to be")
  (princ "\n     loaded for this - the run says so if it is not.")
  (ns-tut-pause)
  (princ "\nWHAT IT CHECKS AND HANDLES FOR YOU")
  (princ "\n  - warns on tilted UCS / non-flat lines / unusable layer")
  (princ "\n  - bare numbers read as inches; 1'4 style works anywhere")
  (princ "\n  - corner mode keeps step treads square to the picked line,")
  (princ "\n    so a skewed corner still measures true")
  (princ "\n  - U treads trim to whatever the side is at that distance -")
  (princ "\n    arm, diagonal or arc - and the run stops at the open end")
  (princ "\n  - a corner deeper than the run - or two that would meet")
  (princ "\n    across the last tread - falls back to square")
  (princ "\n  - notes when a line had to be extended to meet a tread")
  (princ "\n  - dims: the step-tread chain plus the width once; all one undo")
  (princ "\n  - beads go to AUTOBEAD, so they follow ITS rules and land")
  (princ "\n    in their own undo group - a U of their own")
  (ns-tut-pause)

  (initget "Yes No")
  (if (= "No" (getkword (strcat "\nDraw a demonstration in this drawing?"
                                " [Yes/No] <Yes>: ")))
    (progn (princ "\nTutorial done - type NORMIESTEP to use it for real.")
           (exit)))
  (setq pt (getpoint "\nPick a clear spot (about 250 x 120 needed): "))
  (if (null pt)
    (progn (princ "\nNo spot picked - tutorial done.") (exit)))
  (setq org  (trans pt 1 0)
        txth (ns-txth)
        sp   org
        u    '(1.0 0.0 0.0)
        dir  '(0.0 1.0 0.0)
        wid  120.0
        off  9.0)
  (command "_.UNDO" "_Begin")
  (setq undoflag T
        oldce (getvar "CMDECHO")
        oldstyle (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)

  (ns-mkline (ns-add sp (ns-scl u -110.0)) (ns-add sp (ns-scl u 110.0)))
  (ns-tut-text (ns-add org '(-105.0 -14.0 0.0)) (* 1.2 txth)
               "NORMIESTEP demo: one-line mode - select this wall line")
  (princ "\n[1] The WALL drawn - one-line mode.  The steps center on its")
  (princ "\n    middle, all 120 wide, marching up from it.")
  (ns-tut-pause)

  (setq pprev sp cum 0.0 n 1
        offd  (ns-scl u (+ (* 0.5 wid) (* 2.0 txth))))
  (foreach lst '(12.0 12.0 12.0)
    ;; the LAST tread gives up the corner offset at each end - the real
    ;; command draws it full width and trims it once the run is known
    (setq dep  lst
          p    (ns-add pprev (ns-scl dir dep))
          cum  (+ cum dep)
          hw   (if (= n 3) (- (* 0.5 wid) off) (* 0.5 wid))
          e1   (ns-add p (ns-scl u hw))
          e2   (ns-add p (ns-scl u (- hw))))
    (ns-mkline e1 e2)
    (if (null first1) (setq first1 e1 first2 e2))
    (ns-dim *cs-depth-dimstyle* pprev p
            (ns-add (ns-mid2 pprev p) offd))
    (princ (strcat "\n[" (itoa (1+ n)) "] Step " (itoa n)
                   ": 12 past the previous tread (" (rtos cum)
                   " from the wall), "
                   (if (= n 3)
                     "trimmed to 102 - 9 goes to each corner."
                     "width 120 like every other.")))
    (ns-tut-pause)
    (setq pprev p n (1+ n)))

  ;; the side walls - square off the wall, one offset short of the last
  ;; tread - and the diagonal corners on the last step
  (setq e1 (ns-add sp (ns-scl u (* 0.5 wid))))
  (ns-mkline e1 (ns-add e1 (ns-scl dir (- cum off))))
  (ns-outer e1 (ns-scl u -1.0) dir cum "Cut" off)
  (setq e2 (ns-add sp (ns-scl u (* -0.5 wid))))
  (ns-mkline e2 (ns-add e2 (ns-scl dir (- cum off))))
  (ns-outer e2 u dir cum "Cut" off)
  (ns-dim *cs-width-dimstyle* first1 first2
          (ns-add sp (ns-scl dir (- (+ (* 0.5 wid) (* 1.5 txth))))))
  (princ "\n[5] The SIDE WALLS close the run - square off the wall, from")
  (princ "\n    the wall to the LAST step, whose corners take the")
  (princ "\n    treatment: here CUT, so each one runs 9 back along")
  (princ "\n    its side wall and 9 in along the last tread (cut length")
  (princ "\n    9 x root 2, about 12.73).  Radius would put a fillet arc")
  (princ "\n    there instead; Square keeps the full corner.  The width")
  (princ "\n    is dimensioned once - it is the same for every step.")
  (ns-tut-pause)

  (if oldstyle (ns-setstyle oldstyle))
  (command "_.UNDO" "_End")
  (setq undoflag nil)
  (setvar "CMDECHO" oldce)
  (princ "\n[6] Done.  One U removes the demo.  Try the other modes too:")
  (princ "\n    two lines of a corner, or a U outline (even one with")
  (princ "\n    rounded or diagonal back corners) - NORMIESTEP fills it in.")
  (princ))

(princ (strcat "\nNORMIESTEP.lsp " *ns-version*
               " loaded - NORMIESTEP to draw plain steps,"
               " TUTORIALNORMIESTEP to learn it."))
(princ)

