;;; ==================================================================
;;;  dim_continue.lsp
;;;
;;;  DIMCONTEND  ("Dimension - Continue to End")
;;;
;;;  Continue an existing linear/aligned dimension across a highlighted
;;;  part of the drawing.  The routine chains continued dimensions from
;;;  the seed dimension's far extension line to every feature point that
;;;  lies beyond it, marching in a straight line out to the last point
;;;  of the selection -- the "end of the drawing".  Each new dimension
;;;  inherits every property of the seed (dimension style, layer, text,
;;;  arrows, precision, ...) because it is created with AutoCAD's own
;;;  DIMCONTINUE command anchored on the seed.
;;;
;;;  Usage
;;;    Command: DIMCONTEND        (short alias: DCE)
;;;      1. Select the dimension to continue (a linear or aligned dim).
;;;      2. Highlight the drawing to dimension (window/crossing select).
;;;    The dimension chain is drawn automatically, then the command
;;;    offers to continue from another dimension (Enter finishes).
;;;
;;;  Notes
;;;    * "Linear/aligned" means DXF dimension type 0 (rotated /
;;;      horizontal / vertical) or 1 (aligned).  Angular, radial,
;;;      diameter and ordinate dimensions are rejected as seeds.
;;;    * The travel direction and the measurement axis are taken from
;;;      the seed, so the continuation follows the seed's orientation
;;;      even if the geometry is rotated.
;;;    * Requires Visual LISP (standard in full AutoCAD).  AutoCAD LT
;;;      has no LISP engine and cannot run this file.
;;; ==================================================================

;; --- measurement-axis angle (radians) of a linear/aligned dimension
(setq *dimcontinue-version* "v1.2")   ; announced on load; release_lisp.py
                                         ; stamps the dated twin in releases/

(defun dce:axis (ed)
  (if (and (member '(100 . "AcDbRotatedDimension") ed) (assoc 50 ed))
    (cdr (assoc 50 ed))                       ; rotated dim: explicit angle
    (angle (cdr (assoc 13 ed)) (cdr (assoc 14 ed))))) ; aligned: 1st->2nd ext

;; --- signed distance of point P from ORIGIN along the axis at angle A
(defun dce:proj (p origin a)
  (+ (* (- (car  p) (car  origin)) (cos a))
     (* (- (cadr p) (cadr origin)) (sin a))))

;; --- feature points of one entity that are worth dimensioning
(defun dce:pts (en / ed typ pts en2 res)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed))
        pts nil)
  (cond
    ((= typ "LINE")
       (setq pts (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)))))
    ((= typ "LWPOLYLINE")
       (foreach g ed (if (= 10 (car g)) (setq pts (cons (cdr g) pts)))))
    ((= typ "POLYLINE")                       ; old-style / 3D polyline
       (setq en2 (entnext en))
       (while (and en2 (= "VERTEX" (cdr (assoc 0 (entget en2)))))
         (setq pts (cons (cdr (assoc 10 (entget en2))) pts)
               en2 (entnext en2))))
    ((member typ '("POINT" "CIRCLE"))
       (setq pts (list (cdr (assoc 10 ed)))))
    (t                                        ; any other curve object
       (setq res (vl-catch-all-apply
                   'vlax-curve-getStartPoint (list en)))
       (if (not (vl-catch-all-error-p res))
         (setq pts (list res (vlax-curve-getEndPoint en))))))
  pts)

;; ------------------------------------------------------------------
(defun c:DIMCONTEND ( / *error* olderr oce ocl oos odim
                        tref en ed a p14 seedstyle seedlayer seedt
                        ss i pl proj sorted kept prev pt tol
                        again ans undo-open )

  ;; -- restore state on error / cancel
  (setq olderr *error*)
  (defun *error* (m)
    (if oce (setvar "CMDECHO" oce))
    (if ocl (setvar "CLAYER"  ocl))
    (if oos (setvar "OSMODE"  oos))
    ;; the seed's dimension style must not outlive the run
    (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" odim)))
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n** Error: " m)))
    (princ))

  (setq oce  (getvar "CMDECHO")
        ocl  (getvar "CLAYER")
        oos  (getvar "OSMODE")
        odim (getvar "DIMSTYLE")
        tol  1e-6)
  (vl-load-com)

  (setq again T)
  (while again

    ;; -- 1. pick the seed dimension --------------------------------
    (setq en nil ss nil pl nil kept nil)
    (while (null en)
      (setq tref (entsel "\nSelect the dimension to continue: "))
      (cond
        ((null tref)                                 ; Enter / miss -> quit
           ;; a quoted symbol, not :none - a colon symbol evaluates to
           ;; nil in AutoLISP, which left en empty and re-asked forever
           (setq en 'quit))
        ((/= "DIMENSION" (cdr (assoc 0 (entget (car tref)))))
           (princ " -- that is not a dimension, try again."))
        ((> (logand (cdr (assoc 70 (entget (car tref)))) 7) 1)
           (princ " -- only linear/aligned dimensions can be continued."))
        (t (setq en (car tref)))))

    (if (eq en 'quit)
      (princ "\nNo dimension selected -- nothing to do.")
      (progn
        (setq ed        (entget en)
              a         (dce:axis ed)
              p14       (cdr (assoc 14 ed))          ; seed far ext-line origin
              seedt     (dce:proj p14 p14 a)         ; == 0, kept for clarity
              seedstyle (cdr (assoc 3 ed))
              seedlayer (cdr (assoc 8 ed)))

        ;; -- 2. highlight the drawing to dimension -----------------
        (princ "\nHighlight the drawing to dimension (window/crossing): ")
        (setq ss (ssget))

        (if (null ss)
          (princ "\nNothing highlighted -- nothing to do.")
          (progn
            ;; -- gather candidate points beyond the seed's far ext line
            (setq pl nil i 0)
            (while (< i (sslength ss))
              (foreach p (dce:pts (ssname ss i))
                (setq proj (dce:proj p p14 a))
                (if (> proj tol)                     ; strictly beyond seed
                  (setq pl (cons (cons proj p) pl))))
              (setq i (1+ i)))

            (if (null pl)
              (princ "\nNo feature points lie beyond the dimension -- nothing to continue.")
              (progn
                ;; -- sort by distance, drop duplicates within tolerance
                (setq sorted (vl-sort pl
                               (function (lambda (u v) (< (car u) (car v)))))
                      kept   nil
                      prev   nil)
                (foreach pr sorted
                  (if (or (null prev) (> (- (car pr) prev) tol))
                    (setq kept (cons (cdr pr) kept)
                          prev (car pr))))
                (setq kept (reverse kept))

                ;; -- 3. draw the continued chain from the seed ------
                ;; one undo group per chain, so a U takes the whole
                ;; chain back rather than one dimension at a time
                (command "_.UNDO" "_Begin")
                (setq undo-open T)
                (setvar "CMDECHO" 0)
                (setvar "CLAYER"  seedlayer)
                (setvar "OSMODE"  0)
                (vl-catch-all-apply
                  'command (list "_.-DIMSTYLE" "_Restore" seedstyle))
                (command "._DIMCONTINUE" "_Select" (list en p14))
                (foreach pt kept (command pt))
                (command "" "")                      ; end + exit DIMCONTINUE

                (setvar "OSMODE"  oos)
                (setvar "CLAYER"  ocl)
                (setvar "CMDECHO" oce)
                (command "_.UNDO" "_End")
                (setq undo-open nil)
                (princ (strcat "\n" (itoa (length kept))
                               " continued dimension(s) added."))))))))

    ;; an Entered/missed seed pick already means quit; after a real
    ;; pass offer the next chain without retyping the command
    (if (eq en 'quit)
      (setq again nil)
      (progn
        (initget "Yes No")
        (setq ans (getkword
          "\nContinue from another dimension? [Yes/No] <No>: "))
        (setq again (equal ans "Yes")))))

  ;; put the user's dimension style back if any pass moved it
  (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
    (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" odim)))

  (setq *error* olderr)
  (princ))

;; short alias
(defun c:DCE () (c:DIMCONTEND))

(defun c:DIMCONTENDVER ()
  (princ (strcat "\nDIMCONTEND " *dimcontinue-version*))
  (princ))

(princ (strcat "\nDIMCONTEND / DCE " *dimcontinue-version*
               " loaded -- continue a dimension to the end of the drawing."))
(princ)
