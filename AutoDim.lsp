;;; ======================================================================
;;;  AutoDim.lsp
;;;
;;;  AUTODIM  - Dimensions every straight line in model space (LINE
;;;             entities and straight LWPOLYLINE segments) with an
;;;             aligned dimension, then asks the user to draw two
;;;             "floor dims" lines.  Each floor dims line becomes a
;;;             continued dimension chain (DIMALIGNED + DIMCONTINUE)
;;;             that breaks at every object standing in its way.
;;;
;;;  FLOORDIM - Runs just the floor dims part for one extra line.
;;;
;;;  Usage:
;;;    1. APPLOAD this file (or drag it into the drawing window).
;;;    2. Type AUTODIM.
;;;    3. After the automatic dims are placed, draw the two floor dims
;;;       lines straight through the plan.  Every object the line
;;;       crosses becomes a break point in the dimension chain.  A
;;;       third click sets where the chain is placed (Enter puts the
;;;       chain directly on the drawn line).
;;;
;;;  Notes:
;;;    * Dimensions use the current dimension style and current layer.
;;;    * The automatic dims are offset to the left of each line by
;;;      2 x DIMTXT x DIMSCALE.
;;;    * The two floor dims lines are construction lines only - they
;;;      are erased once their dimension chain has been created.
;;;    * Break points closer together than 0.0001 drawing units are
;;;      merged so no zero-length dimensions are created.
;;; ======================================================================

(vl-load-com)

;; ---------------------------------------------------------------- helpers

(defun ad:dxf (code ent) (cdr (assoc code (entget ent))))

;; midpoint of two points
(defun ad:mid (p1 p2) (mapcar '(lambda (a b) (* 0.5 (+ a b))) p1 p2))

;; perpendicular offset used for the automatic dims
(defun ad:dimoff ()
  (* 2.0
     (getvar "DIMTXT")
     (if (zerop (getvar "DIMSCALE")) 1.0 (getvar "DIMSCALE"))))

;; place one aligned dimension - all points expected in WCS
(defun ad:aligned (p1 p2 loc)
  (command "_.DIMALIGNED"
           "_non" (trans p1 0 1)
           "_non" (trans p2 0 1)
           "_non" (trans loc 0 1)))

;; dimension a single straight segment, offset perpendicular to its left
(defun ad:dimseg (p1 p2 off)
  (if (> (distance p1 p2) 1e-8)
    (progn
      (ad:aligned p1 p2
                  (polar (ad:mid p1 p2) (+ (angle p1 p2) (* 0.5 pi)) off))
      t)))

;; ------------------------------------------- part 1: dimension everything

;; dimension every LINE entity in model space, return how many
(defun ad:dimlines (/ ss i en off cnt)
  (setq off (ad:dimoff)
        ss  (ssget "_X" '((0 . "LINE") (410 . "Model")))
        i   0
        cnt 0)
  (if ss
    (repeat (sslength ss)
      (setq en (ssname ss i)
            i  (1+ i))
      (if (ad:dimseg (ad:dxf 10 en) (ad:dxf 11 en) off)
        (setq cnt (1+ cnt)))))
  cnt)

;; dimension every straight (zero bulge) LWPOLYLINE segment in model
;; space, return how many
(defun ad:dimplines (/ ss i en el pts blg off n g cnt)
  (setq off (ad:dimoff)
        ss  (ssget "_X" '((0 . "LWPOLYLINE") (410 . "Model")))
        i   0
        cnt 0)
  (if ss
    (repeat (sslength ss)
      (setq en  (ssname ss i)
            i   (1+ i)
            el  (entget en)
            pts '()
            blg '())
      ;; only plain plan-view polylines (normal along world Z)
      (if (or (null (assoc 210 el))
              (equal (cdr (assoc 210 el)) '(0.0 0.0 1.0) 1e-6))
        (progn
          (foreach g el
            (cond ((= 10 (car g)) (setq pts (cons (append (cdr g) '(0.0)) pts)))
                  ((= 42 (car g)) (setq blg (cons (cdr g) blg)))))
          (setq pts (reverse pts)
                blg (reverse blg))
          ;; closed polylines also get their last->first segment
          (if (= 1 (logand 1 (cdr (assoc 70 el))))
            (setq pts (append pts (list (car pts)))))
          (setq n 0)
          (while (< (1+ n) (length pts))
            (if (and (or (null (nth n blg)) (equal 0.0 (nth n blg) 1e-8))
                     (ad:dimseg (nth n pts) (nth (1+ n) pts) off))
              (setq cnt (1+ cnt)))
            (setq n (1+ n)))))))
  cnt)

;; ------------------------------------------------- part 2: the floor dims

;; WCS intersection points between the floor dims line and every object
;; in model space that stands in its way
(defun ad:xpoints (lin lobj / ss i en rtn pts res)
  (setq ss  (ssget "_X"
                   '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE,INSERT")
                     (410 . "Model")))
        res '()
        i   0)
  (if (and ss (ssmemb lin ss)) (ssdel lin ss))
  (if ss
    (repeat (sslength ss)
      (setq en  (ssname ss i)
            i   (1+ i)
            rtn (vl-catch-all-apply
                  'vlax-invoke
                  (list lobj 'IntersectWith
                        (vlax-ename->vla-object en) acextendnone)))
      (if (not (vl-catch-all-error-p rtn))
        (progn
          (setq pts rtn)
          (while (and pts (cddr pts))
            (setq res (cons (list (car pts) (cadr pts) (caddr pts)) res)
                  pts (cdddr pts)))))))
  res)

;; build one floor dims chain along p1->p2 (WCS): a first aligned dim
;; followed by DIMCONTINUE through every break point, then erase the
;; construction line.  Returns the number of dimensions placed.
(defun ad:floorchain (p1 p2 loc / lin lobj len dir ds d chain prev)
  (entmake (list '(0 . "LINE") (cons 10 p1) (cons 11 p2)))
  (setq lin  (entlast)
        lobj (vlax-ename->vla-object lin)
        len  (distance p1 p2)
        dir  (mapcar '(lambda (a b) (/ (- b a) len)) p1 p2)
        ds   '())
  ;; distance of every crossing object along the line
  (foreach x (ad:xpoints lin lobj)
    (setq d (apply '+ (mapcar '* dir (mapcar '- x p1))))
    (if (and (> d 1e-4) (< d (- len 1e-4)))
      (setq ds (cons d ds))))
  ;; sorted break points, near-coincident ones merged
  (setq chain (list p1)
        prev  0.0)
  (foreach d (vl-sort ds '<)
    (if (> (- d prev) 1e-4)
      (setq chain (cons (mapcar '(lambda (a v) (+ a (* d v))) p1 dir) chain)
            prev  d)))
  (setq chain (reverse (cons p2 chain)))
  ;; first dimension of the chain, then continue through the breaks
  (ad:aligned (car chain) (cadr chain) loc)
  (if (cddr chain)
    (progn
      (command "_.DIMCONTINUE")
      (foreach p (cddr chain) (command "_non" (trans p 0 1)))
      (command "" "")))
  (entdel lin)
  (1- (length chain)))

;; prompt the user to draw one floor dims line and dimension it
(defun ad:getfloor (tag / p1 p2 loc n)
  (setq p1 (getpoint (strcat "\n" tag " - first point (Enter to skip): ")))
  (if p1
    (progn
      (setq p2 (getpoint p1 (strcat "\n" tag " - second point: ")))
      (if (and p2 (> (distance p1 p2) 1e-8))
        (progn
          (setq loc (getpoint (strcat "\n" tag
                                      " - dimension line location <on the line>: ")))
          (if (null loc) (setq loc (ad:mid p1 p2)))
          (setq n (ad:floorchain (trans p1 1 0) (trans p2 1 0) (trans loc 1 0)))
          (prompt (strcat "\n" tag ": " (itoa n) " dimension(s) placed."))
          n)
        (prompt "\nNothing drawn - skipped.")))))

;; --------------------------------------------------------------- commands

(defun c:AUTODIM (/ *error* oldcmd nlin npl)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg t) "*break*,*cancel*,*exit*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (setq oldcmd (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (prompt "\nDimensioning all straight lines...")
  (setq nlin (ad:dimlines)
        npl  (ad:dimplines))
  (prompt (strcat "\n" (itoa nlin) " line(s) and " (itoa npl)
                  " polyline segment(s) dimensioned."))
  (prompt (strcat "\nNow draw the two floor dims lines - the dimension"
                  " chain breaks at everything standing in its way."))
  (ad:getfloor "Floor dims 1")
  (ad:getfloor "Floor dims 2")
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (princ))

(defun c:FLOORDIM (/ *error* oldcmd)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg t) "*break*,*cancel*,*exit*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (setq oldcmd (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (ad:getfloor "Floor dims")
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (princ))

(princ "\nAutoDim.lsp loaded.  Commands: AUTODIM (dimension all straight lines + two floor dims), FLOORDIM (one extra floor dims chain).")
(princ)
