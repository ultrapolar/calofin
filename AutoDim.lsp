;;; ======================================================================
;;;  AutoDim.lsp
;;;
;;;  AUTODIM  - 1. Asks the user to highlight the stuff to auto-dim
;;;                (the plan geometry).  Everything else in the drawing
;;;                is ignored from then on.
;;;             2. Dimensions the straight lines about the perimeter of
;;;                the highlighted geometry (LINE entities and straight
;;;                LWPOLYLINE segments) with aligned dimensions placed
;;;                on the outside of the plan.
;;;             3. Asks the user to highlight the stairs - every
;;;                straight line in that selection is auto-dimmed too.
;;;             4. Asks the user to draw two "floor dims" lines.  Each
;;;                one becomes a continued dimension chain (DIMALIGNED
;;;                + DIMCONTINUE) that breaks at every highlighted
;;;                object standing in its way.
;;;
;;;  STAIRDIM - Runs just the stairs part again for another selection.
;;;  FLOORDIM - Runs just the floor dims part for one extra line
;;;             (breaks at everything in model space).
;;;
;;;  Usage:
;;;    1. APPLOAD this file (or drag it into the drawing window).
;;;    2. Type AUTODIM and follow the prompts.
;;;
;;;  How the perimeter is found:
;;;    From the midpoint of every straight segment a test ray is cast
;;;    perpendicular to each side, out past the extents of the
;;;    highlighted geometry.  If at least one side is completely clear
;;;    of highlighted geometry the segment is on the perimeter, and its
;;;    dimension is placed on that clear side.  Because only the
;;;    highlighted stuff blocks the rays, title borders, notes and
;;;    anything else in the drawing cannot get in the way.
;;;
;;;  Notes:
;;;    * Dimensions use the current dimension style and current layer.
;;;    * Perimeter and stair dims are offset from their line by
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

;; every straight segment of a LINE or plan-view LWPOLYLINE as a list
;; of (p1 p2) pairs - other entity types return nil
(defun ad:segs (en / el pts blg segs n g)
  (setq el (entget en))
  (cond
    ((= "LINE" (cdr (assoc 0 el)))
     (list (list (cdr (assoc 10 el)) (cdr (assoc 11 el)))))
    ((and (= "LWPOLYLINE" (cdr (assoc 0 el)))
          (or (null (assoc 210 el))
              (equal (cdr (assoc 210 el)) '(0.0 0.0 1.0) 1e-6)))
     (setq pts '()
           blg '())
     (foreach g el
       (cond ((= 10 (car g)) (setq pts (cons (append (cdr g) '(0.0)) pts)))
             ((= 42 (car g)) (setq blg (cons (cdr g) blg)))))
     (setq pts (reverse pts)
           blg (reverse blg))
     ;; closed polylines also get their last->first segment
     (if (= 1 (logand 1 (cdr (assoc 70 el))))
       (setq pts (append pts (list (car pts)))))
     (setq segs '()
           n    0)
     (while (< (1+ n) (length pts))
       (if (or (null (nth n blg)) (equal 0.0 (nth n blg) 1e-8))
         (setq segs (cons (list (nth n pts) (nth (1+ n) pts)) segs)))
       (setq n (1+ n)))
     (reverse segs))))

;; dxf filter for geometry that can be dimensioned / block a ray /
;; break a dim chain
(defun ad:geomfilter ()
  '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE,INSERT")))

;; everything in model space matching the geometry filter
(defun ad:geomss ()
  (ssget "_X" (append (ad:geomfilter) '((410 . "Model")))))

;; WCS bounding box of a selection set as (min max), nil if none
(defun ad:ssbox (ss / i obj ll ur mn mx)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq obj (vlax-ename->vla-object (ssname ss i))
            i   (1+ i))
      (if (not (vl-catch-all-error-p
                 (vl-catch-all-apply 'vla-getboundingbox (list obj 'll 'ur))))
        (progn
          (setq ll (vlax-safearray->list ll)
                ur (vlax-safearray->list ur)
                mn (if mn (mapcar 'min mn ll) ll)
                mx (if mx (mapcar 'max mx ur) ur))))))
  (if mn (list mn mx)))

;; ------------------------------------------ part 1: perimeter dimensions

;; T if nothing in ss lies between pt and pt + dist along direction ang
(defun ad:sideclear (pt ang dist eps ss / lin lobj i rtn clear)
  (entmake (list '(0 . "LINE")
                 (cons 10 (polar pt ang eps))
                 (cons 11 (polar pt ang dist))))
  (setq lin   (entlast)
        lobj  (vlax-ename->vla-object lin)
        clear t
        i     0)
  (if ss
    (while (and clear (< i (sslength ss)))
      (setq rtn (vl-catch-all-apply
                  'vlax-invoke
                  (list lobj 'IntersectWith
                        (vlax-ename->vla-object (ssname ss i)) acextendnone)))
      (if (and (not (vl-catch-all-error-p rtn)) rtn)
        (setq clear nil))
      (setq i (1+ i))))
  (entdel lin)
  clear)

;; if segment p1-p2 lies on the perimeter of the highlighted geometry,
;; return the angle pointing to its clear (outside) side, else nil
(defun ad:perimang (p1 p2 diag eps ss / mid a)
  (setq mid (ad:mid p1 p2)
        a   (angle p1 p2))
  (cond ((ad:sideclear mid (+ a (* 0.5 pi)) diag eps ss) (+ a (* 0.5 pi)))
        ((ad:sideclear mid (- a (* 0.5 pi)) diag eps ss) (- a (* 0.5 pi)))))

;; dimension every straight segment about the perimeter of the
;; highlighted geometry in ss, return how many
(defun ad:dimperim (ss / box diag eps off cnt i en seg pa)
  (setq box  (ad:ssbox ss)
        cnt  0
        i    0)
  (if box
    (progn
      (setq diag (* 2.0 (distance (car box) (cadr box)))
            eps  (* 1e-6 diag)
            off  (ad:dimoff))
      (repeat (sslength ss)
        (setq en (ssname ss i)
              i  (1+ i))
        (foreach seg (ad:segs en)
          (if (and (> (distance (car seg) (cadr seg)) 1e-8)
                   (setq pa (ad:perimang (car seg) (cadr seg) diag eps ss)))
            (progn
              (ad:aligned (car seg) (cadr seg)
                          (polar (ad:mid (car seg) (cadr seg)) pa off))
              (setq cnt (1+ cnt))))))))
  cnt)

;; --------------------------------------------- part 2: stairs dimensions

;; ask the user to highlight the stairs and dimension every straight
;; line in the selection, return how many
(defun ad:dimstairs (/ ss off cnt i en seg)
  (prompt "\nHighlight the stairs to dimension (Enter to skip).")
  (setq ss  (ssget '((0 . "LINE,LWPOLYLINE")))
        off (ad:dimoff)
        cnt 0
        i   0)
  (if ss
    (repeat (sslength ss)
      (setq en (ssname ss i)
            i  (1+ i))
      (foreach seg (ad:segs en)
        (if (ad:dimseg (car seg) (cadr seg) off)
          (setq cnt (1+ cnt))))))
  cnt)

;; ------------------------------------------------- part 3: the floor dims

;; WCS intersection points between the floor dims line and every object
;; in obstacles that stands in its way (nil = all model space geometry)
(defun ad:xpoints (lin lobj obstacles / ss i rtn pts res)
  (setq ss  (if obstacles obstacles (ad:geomss))
        res '()
        i   0)
  (if (and ss (ssmemb lin ss)) (ssdel lin ss))
  (if ss
    (repeat (sslength ss)
      (setq rtn (vl-catch-all-apply
                  'vlax-invoke
                  (list lobj 'IntersectWith
                        (vlax-ename->vla-object (ssname ss i)) acextendnone)))
      (setq i (1+ i))
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
(defun ad:floorchain (p1 p2 loc obstacles / lin lobj len dir ds d chain prev)
  (entmake (list '(0 . "LINE") (cons 10 p1) (cons 11 p2)))
  (setq lin  (entlast)
        lobj (vlax-ename->vla-object lin)
        len  (distance p1 p2)
        dir  (mapcar '(lambda (a b) (/ (- b a) len)) p1 p2)
        ds   '())
  ;; distance of every crossing object along the line
  (foreach x (ad:xpoints lin lobj obstacles)
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

;; prompt the user to draw one floor dims line and dimension it,
;; breaking at the given obstacles (nil = all model space geometry)
(defun ad:getfloor (tag obstacles / p1 p2 loc n)
  (setq p1 (getpoint (strcat "\n" tag " - first point (Enter to skip): ")))
  (if p1
    (progn
      (setq p2 (getpoint p1 (strcat "\n" tag " - second point: ")))
      (if (and p2 (> (distance p1 p2) 1e-8))
        (progn
          (setq loc (getpoint (strcat "\n" tag
                                      " - dimension line location <on the line>: ")))
          (if (null loc) (setq loc (ad:mid p1 p2)))
          (setq n (ad:floorchain (trans p1 1 0) (trans p2 1 0)
                                 (trans loc 1 0) obstacles))
          (prompt (strcat "\n" tag ": " (itoa n) " dimension(s) placed."))
          n)
        (prompt "\nNothing drawn - skipped.")))))

;; --------------------------------------------------------------- commands

(defun c:AUTODIM (/ *error* oldcmd plan nper nstair)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg t) "*break*,*cancel*,*exit*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (prompt "\nHighlight the stuff to auto-dimension (the plan geometry).")
  (setq plan (ssget (ad:geomfilter)))
  (if (null plan)
    (prompt "\nNothing highlighted - AUTODIM cancelled.")
    (progn
      (setq oldcmd (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (command "_.UNDO" "_Begin")
      (prompt "\nDimensioning the straight lines about the perimeter...")
      (setq nper (ad:dimperim plan))
      (prompt (strcat "\n" (itoa nper) " perimeter dimension(s) placed."))
      (setq nstair (ad:dimstairs))
      (prompt (strcat "\n" (itoa nstair) " stair dimension(s) placed."))
      (prompt (strcat "\nNow draw the two floor dims lines - the dimension"
                      " chain breaks at every highlighted object standing"
                      " in its way."))
      (ad:getfloor "Floor dims 1" plan)
      (ad:getfloor "Floor dims 2" plan)
      (command "_.UNDO" "_End")
      (setvar "CMDECHO" oldcmd)))
  (princ))

(defun c:STAIRDIM (/ *error* oldcmd n)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg t) "*break*,*cancel*,*exit*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (setq oldcmd (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq n (ad:dimstairs))
  (prompt (strcat "\n" (itoa n) " stair dimension(s) placed."))
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
  (ad:getfloor "Floor dims" nil)
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (princ))

(princ "\nAutoDim.lsp loaded.  Commands: AUTODIM (highlight plan -> perimeter + stairs + two floor dims), STAIRDIM (dimension another stair selection), FLOORDIM (one extra floor dims chain).")
(princ)
