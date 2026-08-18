;;; ==================================================================
;;;  CDCREATE.lsp
;;;
;;;  CDCREATE  ("Cross Dimension - Create")
;;;
;;;  Turns highlighted lines into cross dimensions in one pass:
;;;
;;;    1. Highlight the lines (or pre-select them before typing the
;;;       command -- a pickfirst selection is used as-is).
;;;    2. Every LINE in the selection gets an aligned dimension along
;;;       it, measuring end to end, with the dimension line sitting on
;;;       the line itself.
;;;    3. Each new dimension is put in the "CROSS DIMENSIONS" dimension
;;;       style and on the "DIMENSION" layer, ByLayer, with no
;;;       per-entity colour / linetype / lineweight override -- the
;;;       same convention POOL uses for the cross dims it draws.
;;;
;;;  The source lines are left alone: a cross dim tie normally stays in
;;;  the drawing underneath its dimension.  Erase them yourself if the
;;;  lines were only construction geometry.
;;;
;;;  Usage
;;;    Command: CDCREATE
;;;    Command: CDCREATEVER      prints the version
;;;
;;;  Tunables (setq them after loading if a drawing needs different
;;;  names, e.g. in a startup file):
;;;    cdc:*style*   dimension style to use   ("CROSS DIMENSIONS")
;;;    cdc:*layer*   layer to create dims on  ("DIMENSION")
;;;    cdc:*offset*  distance the dimension line is pushed off the
;;;                  line it measures, drawing units (0.0 = on it)
;;;
;;;  Notes
;;;    * Only LINE entities are dimensioned.  Anything else in the
;;;      selection (polylines, arcs, text, blocks, ...) is counted and
;;;      reported, not dimensioned -- explode a polyline first if its
;;;      segments need cross dims.
;;;    * Zero-length lines are skipped; they have nothing to measure.
;;;    * The "DIMENSION" layer is created when the drawing lacks it.
;;;      A missing "CROSS DIMENSIONS" style is NOT invented: the dims
;;;      are drawn in whatever style is current and the routine says so,
;;;      so a drawing started from the wrong template is obvious
;;;      instead of silently producing wrong-looking dims.
;;;    * The dimension style, current layer, CMDECHO and OSMODE in
;;;      force before the command are restored afterwards, on a clean
;;;      finish, an error, or Esc.
;;;    * Requires the Visual LISP engine, which ships with full
;;;      AutoCAD.  AutoCAD LT has no LISP engine and cannot run this.
;;; ==================================================================

(setq *cdcreate-version* "v1.0")   ; announced on load; release_lisp.py
                                   ; turns v1.0 into the REV10 suffix

(setq cdc:*style*  "CROSS DIMENSIONS")
(setq cdc:*layer*  "DIMENSION")
(setq cdc:*offset* 0.0)

;;; -------------------- helpers ------------------------------------

;; make a layer current, creating it first when the drawing lacks it
(defun cdc:setlayer (name)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   '(70 . 0)
                   '(62 . 7)
                   '(6 . "Continuous"))))
  (setvar "CLAYER" name))

;; restore a dimension style by name when the drawing has it;
;; returns T when the style was set
(defun cdc:setstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; put a saved dimension style back, but only when the style really did
;; move -- a run that never found "CROSS DIMENSIONS" should not leave a
;; pointless -DIMSTYLE Restore in the drawing's command history
(defun cdc:restyle (odim)
  (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
    (cdc:setstyle odim)))

;; the two endpoints of a LINE, in WCS (the entity's own OCS may be
;; tilted, so go through the entity coordinate system)
(defun cdc:ends (en / ed)
  (setq ed (entget en))
  (list (trans (cdr (assoc 10 ed)) en 0)
        (trans (cdr (assoc 11 ed)) en 0)))

;; midpoint of p1->p2, pushed perpendicular to the line by dist
;; (dist 0.0 puts the dimension line straight on the line)
(defun cdc:loc (p1 p2 dist / dx dy d m)
  (setq m (list (* 0.5 (+ (car  p1) (car  p2)))
                (* 0.5 (+ (cadr p1) (cadr p2)))
                (* 0.5 (+ (caddr p1) (caddr p2)))))
  (if (equal dist 0.0 1e-12)
    m
    (progn
      (setq dx (- (car  p2) (car  p1))
            dy (- (cadr p2) (cadr p1))
            d  (sqrt (+ (* dx dx) (* dy dy))))
      (if (> d 1e-9)
        (list (+ (car  m) (* dist (/ (- dy) d)))
              (+ (cadr m) (* dist (/ dx d)))
              (caddr m))
        m))))

;; a copy of an entget list with every entry for group CODE dropped
(defun cdc:strip (code lst / out)
  (foreach g lst (if (/= code (car g)) (setq out (cons g out))))
  (reverse out))

;; force a freshly drawn dimension onto the layer and style CDCREATE
;; promises, ByLayer -- DIMLAYER, a style-owned layer or a leftover
;; per-entity override would otherwise have the last word
(defun cdc:fixdim (en havestyle / ed)
  (if (and en (setq ed (entget en))
           (= "DIMENSION" (cdr (assoc 0 ed))))
    (progn
      (setq ed (if (assoc 8 ed)
                 (subst (cons 8 cdc:*layer*) (assoc 8 ed) ed)
                 (append ed (list (cons 8 cdc:*layer*)))))
      (if havestyle
        (setq ed (if (assoc 3 ed)
                   (subst (cons 3 cdc:*style*) (assoc 3 ed) ed)
                   (append ed (list (cons 3 cdc:*style*))))))
      (foreach code '(62 6 370) (setq ed (cdc:strip code ed)))
      (entmod ed)
      (entupd en)
      t)))

;;; -------------------- the command --------------------------------

(defun c:CDCREATE ( / *error* olderr oce ocl oos odim
                      ss i en ed typ ends pairs skipped plines
                      havestyle pre new made p1 p2 )

  ;; -- restore drawing state on error / Esc
  (setq olderr *error*)
  (defun *error* (m)
    (cdc:restyle odim)
    (if ocl (setvar "CLAYER"  ocl))
    (if oos (setvar "OSMODE"  oos))
    (if oce (setvar "CMDECHO" oce))
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*ABORT*")))
      (princ (strcat "\n** Error: " m)))
    (princ))

  (vl-load-com)
  (setq oce (getvar "CMDECHO")
        ocl (getvar "CLAYER")
        oos (getvar "OSMODE")
        odim (getvar "DIMSTYLE"))

  ;; -- 1. the highlighted lines: a pickfirst selection if there is
  ;;       one, otherwise ask for it
  (setq ss (ssget "_I"))
  (if (null ss)
    (progn
      (princ "\nHighlight the lines to cross-dimension: ")
      (setq ss (ssget))))

  (if (null ss)
    (princ "\nNothing highlighted -- nothing to dimension.")
    (progn
      ;; -- 2. keep the lines, count what was ignored
      (setq i 0 pairs nil skipped 0 plines 0)
      (while (< i (sslength ss))
        (setq en  (ssname ss i)
              ed  (entget en)
              typ (cdr (assoc 0 ed)))
        (cond
          ((not (= "LINE" typ))
             (setq skipped (1+ skipped))
             (if (member typ '("LWPOLYLINE" "POLYLINE"))
               (setq plines (1+ plines))))
          (t
             (setq ends (cdc:ends en)
                   p1   (car  ends)
                   p2   (cadr ends))
             (if (> (distance p1 p2) 1e-9)
               (setq pairs (cons (list p1 p2) pairs))
               (setq skipped (1+ skipped)))))
        (setq i (1+ i)))
      (setq pairs (reverse pairs))

      (if (null pairs)
        (princ "\nNo lines in the selection -- nothing to dimension.")
        (progn
          ;; -- 3. layer and style
          (setvar "CMDECHO" 0)
          (setvar "OSMODE"  0)
          (cdc:setlayer cdc:*layer*)
          (setq havestyle (cdc:setstyle cdc:*style*))
          (if (not havestyle)
            (princ (strcat "\n** This drawing has no \"" cdc:*style*
                           "\" dimension style -- dims drawn in \""
                           (getvar "DIMSTYLE")
                           "\" instead.  Create the style (or start"
                           " from the standard template) and re-run.")))

          ;; -- 4. one aligned dim per line, on the line
          (setq made 0)
          (foreach pr pairs
            (setq p1  (car  pr)
                  p2  (cadr pr)
                  pre (entlast))
            (command "_.DIMALIGNED"
                     "_non" (trans p1 0 1)
                     "_non" (trans p2 0 1)
                     "_non" (trans (cdc:loc p1 p2 cdc:*offset*) 0 1))
            (setq new (entlast))
            (if (and new (not (eq new pre)))
              (progn (cdc:fixdim new havestyle)
                     (setq made (1+ made)))))

          ;; -- 5. put the drawing back the way it was
          (cdc:restyle odim)
          (setvar "CLAYER"  ocl)
          (setvar "OSMODE"  oos)
          (setvar "CMDECHO" oce)

          (princ (strcat "\n" (itoa made) " cross dimension"
                         (if (= made 1) "" "s") " created on layer "
                         cdc:*layer*
                         (if havestyle
                           (strcat " in style " cdc:*style* ".")
                           " (current style).")))
          (if (> skipped 0)
            (princ (strcat "\n" (itoa skipped)
                           " selected object(s) were not lines and were"
                           " left alone."
                           (if (> plines 0)
                             " Explode a polyline to cross-dim its segments."
                             ""))))))))

  (setq *error* olderr)
  (princ))

(defun c:CDCREATEVER ()
  (princ (strcat "\nCDCREATE " *cdcreate-version*))
  (princ))

(princ (strcat "\nCDCREATE " *cdcreate-version*
               " loaded -- dimension highlighted lines as cross dims"
               " (style \"" cdc:*style* "\", layer \"" cdc:*layer* "\")."))
(princ)
