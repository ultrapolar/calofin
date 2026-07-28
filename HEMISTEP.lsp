;;; ======================================================================
;;; HEMISTEP.lsp
;;; ----------------------------------------------------------------------
;;; Hemisphere (semicircle) step layout routine.
;;; Written for AutoCAD 2018 (plain AutoLISP - no dependencies).
;;;
;;; LOAD:     APPLOAD this file (or drag it into the drawing window).
;;; COMMAND:  HEMISTEP
;;;
;;; WHAT IT DOES
;;;   Draws pool steps that act like chords inside a circle: every step
;;;   edge is parallel to a selected base line, centered on the
;;;   perpendicular axis through that line's midpoint, and marches away
;;;   from the line in a chosen direction.  The steps are drawn purely
;;;   from the widths and depths you give, so it is okay if they
;;;   slightly break out of the hemisphere they sit in.
;;;
;;; WORKFLOW
;;;   1.  Select the base LINE the hemisphere steps attach to.  Steps
;;;       are centered on the middle of that line, run parallel to it,
;;;       and step perpendicular away from it.
;;;   2.  Pick a point on the side of the line the steps should go.
;;;   3.  For each step you are asked for the step width, then the
;;;       step depth (measured from the previous step edge - from the
;;;       base line for the first step).  The step is drawn once both
;;;       are given, so the last input is always a step depth.
;;;   4.  Enter (or 0) at a width prompt means the steps are done and
;;;       the command finishes.
;;;
;;; NOTES
;;;   - Geometry is assumed to be drawn in plan view in the WCS.
;;;   - Steps are drawn as LINEs on the current layer.
;;;   - One U / UNDO reverses the whole command.
;;; ======================================================================

;;; ------------------------- small helpers ------------------------------

(defun hs-add (p v) (list (+ (car p) (car v)) (+ (cadr p) (cadr v)) 0.0))

(defun hs-vec (a b) (list (- (car b) (car a)) (- (cadr b) (cadr a)) 0.0))

(defun hs-scl (v s) (list (* (car v) s) (* (cadr v) s) 0.0))

(defun hs-dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun hs-unit (v / l)
  (if (> (setq l (sqrt (hs-dot v v))) 1e-10) (hs-scl v (/ 1.0 l))))

(defun hs-perp (v) (list (- (cadr v)) (car v) 0.0))

(defun hs-mkline (a b)
  (entmake (list '(0 . "LINE")
                 (cons 10 (list (car a) (cadr a) 0.0))
                 (cons 11 (list (car b) (cadr b) 0.0)))))

;;; --------------------------- main command -----------------------------

(defun c:HEMISTEP ( / *error* undoflag sel ed p1 p2 mid u dir side pt
                      stopf cum n wid dep p e1 e2 drawn)

  (defun *error* (msg)
    (if undoflag (command-s "_.UNDO" "_End"))
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nHEMISTEP: " msg)))
    (princ))

  ;; ---- 1. base line ---------------------------------------------------
  (while (null sel)
    (setq sel (entsel "\nSelect the base line for the hemisphere steps: "))
    (cond
      ((null sel)
       (princ "\nNothing selected - try again (Esc to quit)."))
      ((/= "LINE" (cdr (assoc 0 (entget (car sel)))))
       (princ "\nThat is not a LINE - try again.")
       (setq sel nil))))
  (setq ed  (entget (car sel))
        p1  (cdr (assoc 10 ed))
        p2  (cdr (assoc 11 ed))
        mid (mapcar '(lambda (x y) (* 0.5 (+ x y))) p1 p2)
        u   (hs-unit (hs-vec p1 p2)))
  (if (null u)
    (progn (princ "\nThe selected line has zero length.") (exit)))

  ;; ---- 2. direction the steps go --------------------------------------
  (while (null dir)
    (setq pt (getpoint mid "\nPick a point on the side the steps go: "))
    (if (null pt)
      (progn (princ "\nNo direction picked - nothing drawn.") (exit)))
    (setq side (hs-dot (hs-vec mid pt) (hs-perp u)))
    (if (< (abs side) 1e-10)
      (princ "\nThat point is on the line - pick a point to one side.")
      (setq dir (hs-unit (hs-scl (hs-perp u) (if (< side 0.0) -1.0 1.0))))))

  ;; ---- 3. widths and depths, chord by chord ---------------------------
  (command "_.UNDO" "_Begin")
  (setq undoflag T cum 0.0 n 1 drawn 0)

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
        (setq cum (+ cum dep)                  ; depth from the base line
              p   (hs-add mid (hs-scl dir cum))
              e1  (hs-add p (hs-scl u (* 0.5 wid)))
              e2  (hs-add p (hs-scl u (* -0.5 wid))))
        (hs-mkline e1 e2)                      ; the chord (step edge)
        (princ (strcat "\n  Step " (itoa n) ": width " (rtos wid)
                       " at depth " (rtos cum) " from the line."))
        (setq drawn (1+ drawn) n (1+ n)))))

  ;; ---- 4. done ---------------------------------------------------------
  (if (zerop drawn)
    (princ "\nNo steps drawn.")
    (princ (strcat "\n" (itoa drawn) " step(s) drawn, parallel to the"
                   " line and centered on its middle.")))
  (command "_.UNDO" "_End")
  (setq undoflag nil)
  (princ))

(princ "\nHEMISTEP.lsp loaded - type HEMISTEP to draw hemisphere steps.")
(princ)
