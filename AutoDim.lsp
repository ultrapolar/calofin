;;; ======================================================================
;;;  AutoDim.lsp
;;;
;;;  AUTODIM  - Step 1. Asks the user to highlight the stuff to
;;;                auto-dim (the plan geometry).  Everything else in
;;;                the drawing is ignored from then on.
;;;             Step 2. Dimensions the straight lines about the
;;;                perimeter of the highlighted geometry (LINE entities
;;;                and straight LWPOLYLINE segments) with aligned
;;;                dimensions placed at least a foot outside the plan.
;;;             Step 3. Asks the user to highlight the stairs.  The
;;;                treads (the largest group of parallel lines in the
;;;                selection) get their widths dimensioned and the
;;;                distances between them chained beside the stair.
;;;             Step 4. Asks the user to draw two "floor dims" lines.
;;;                Each one becomes a continued dimension chain
;;;                (DIMALIGNED + DIMCONTINUE) that breaks at every
;;;                highlighted object standing in its way.  A start or
;;;                end point picked outside the perimeter is trimmed
;;;                back to the perimeter so no dims hang outside the
;;;                plan.
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
;;;  Dimension styles (used only when the drawing has them, otherwise
;;;  the current style is kept; the style that was current before the
;;;  command ran is restored afterwards):
;;;    * Perimeter dims        -> "SIDE DIMENSION"
;;;    * Step widths           -> "SIDE STANDARD"
;;;    * Distance between steps-> "STANDARD INCHES"
;;;    * Floor dims chains     -> "STANDARD"
;;;
;;;  Notes:
;;;    * All dims go on the current layer.
;;;    * Perimeter dims are placed at least one foot away from the
;;;      perimeter, heading outwards (or 2 x DIMTXT x DIMSCALE when
;;;      that is larger).
;;;    * Equal step widths are dimensioned once instead of once per
;;;      tread; a width dim is repeated only when the width changes.
;;;    * The two floor dims lines are construction lines only - they
;;;      are erased once their dimension chain has been created.
;;;    * Break points closer together than 0.0001 drawing units are
;;;      merged so no zero-length dimensions are created.
;;; ======================================================================

(vl-load-com)

;; ---------------------------------------------------------------- helpers

;; midpoint of two points
(defun ad:mid (p1 p2) (mapcar '(lambda (a b) (* 0.5 (+ a b))) p1 p2))

;; dot product
(defun ad:dot (p q) (apply '+ (mapcar '* p q)))

;; angle of a segment folded into [0, pi) so opposite directions match
(defun ad:segang (seg / a)
  (setq a (angle (car seg) (cadr seg)))
  (if (>= a pi) (- a pi) a))

;; difference between two folded angles, allowing for wrap-around
(defun ad:angdiff (a b / d)
  (setq d (abs (- a b)))
  (min d (abs (- pi d))))

;; perpendicular offset used for the automatic dims
(defun ad:dimoff ()
  (* 2.0
     (getvar "DIMTXT")
     (if (zerop (getvar "DIMSCALE")) 1.0 (getvar "DIMSCALE"))))

;; one foot expressed in the current drawing units (INSUNITS),
;; assuming inches when unitless or unknown
(defun ad:onefoot (/ u)
  (setq u (getvar "INSUNITS"))
  (cond ((= u 2) 1.0)                   ; feet
        ((= u 4) 304.8)                 ; millimetres
        ((= u 5) 30.48)                 ; centimetres
        ((= u 6) 0.3048)                ; metres
        ((= u 10) (/ 1.0 3.0))          ; yards
        (t 12.0)))                      ; inches / unitless

;; restore a dimension style by name if the drawing has it,
;; return T when the style was set
(defun ad:setdimstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; place one aligned dimension - all points expected in WCS
(defun ad:aligned (p1 p2 loc)
  (command "_.DIMALIGNED"
           "_non" (trans p1 0 1)
           "_non" (trans p2 0 1)
           "_non" (trans loc 0 1)))

;; place a continued dimension chain through the given WCS points:
;; a first aligned dim, then DIMCONTINUE through the rest.
;; Returns the number of dimensions placed.
(defun ad:dimchain (pts loc)
  (ad:aligned (car pts) (cadr pts) loc)
  (if (cddr pts)
    (progn
      (command "_.DIMCONTINUE")
      (foreach p (cddr pts) (command "_non" (trans p 0 1)))
      (command "" "")))
  (1- (length pts)))

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
            ;; at least a foot away from the perimeter, heading outwards
            off  (max (ad:dimoff) (ad:onefoot)))
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

;; ask the user to highlight the stairs.  The treads - the largest
;; group of parallel straight lines in the selection - get their widths
;; dimensioned in the "SIDE STANDARD" style and the distances between
;; them chained beside the stair in the "STANDARD INCHES" style.
;; Returns the number of dimensions placed.
(defun ad:dimstairs (/ ss segs i en s a hit g out groups best u v off
                       tds td w lastw mid loc smax ts prev pts cnt)
  (prompt (strcat "\nHighlight the stairs (window or pick the tread"
                  " lines), then press Enter."
                  "\nStep widths get \"SIDE STANDARD\" dims, the"
                  " distances between steps \"STANDARD INCHES\"."
                  "  Press Enter without selecting to skip."))
  (setq ss   (ssget '((0 . "LINE,LWPOLYLINE")))
        segs '()
        cnt  0
        i    0)
  (if ss
    (progn
      ;; every straight segment in the selection
      (repeat (sslength ss)
        (setq en (ssname ss i)
              i  (1+ i))
        (foreach s (ad:segs en)
          (if (> (distance (car s) (cadr s)) 1e-8)
            (setq segs (cons s segs)))))
      ;; group the segments by direction - the biggest group of
      ;; parallel lines is taken as the treads
      (setq groups '())
      (foreach s segs
        (setq a   (ad:segang s)
              hit nil
              out '())
        (foreach g groups
          (if (and (not hit) (< (ad:angdiff a (car g)) 1e-3))
            (setq g   (cons (car g) (cons s (cdr g)))
                  hit t))
          (setq out (cons g out)))
        (if (not hit) (setq out (cons (list a s) out)))
        (setq groups out))
      (setq best nil)
      (foreach g groups
        (if (or (null best) (> (length (cdr g)) (length (cdr best))))
          (setq best g)))
      (if best
        (progn
          (setq a   (car best)
                u   (list (cos a) (sin a) 0.0)          ; along the treads
                v   (list (- (sin a)) (cos a) 0.0)      ; up the stair
                off (ad:dimoff)
                tds '()
                smax nil)
          ;; sort the treads up the stair and find the stair's side edge
          (foreach s (cdr best)
            (setq tds  (cons (cons (ad:dot (ad:mid (car s) (cadr s)) v) s) tds)
                  smax (apply 'max
                              (append (if smax (list smax))
                                      (list (ad:dot (car s) u)
                                            (ad:dot (cadr s) u))))))
          (setq tds (vl-sort tds '(lambda (x y) (< (car x) (car y)))))
          ;; widths of the steps -> "SIDE STANDARD" (repeated only when
          ;; the width changes)
          (ad:setdimstyle "SIDE STANDARD")
          (setq lastw nil)
          (foreach td tds
            (setq w (distance (cadr td) (caddr td)))
            (if (or (null lastw) (> (abs (- w lastw)) 1e-4))
              (progn
                (setq mid (ad:mid (cadr td) (caddr td))
                      loc (mapcar '(lambda (m vv) (- m (* off vv))) mid v))
                (ad:aligned (cadr td) (caddr td) loc)
                (setq lastw w
                      cnt   (1+ cnt)))))
          ;; distances between the steps -> "STANDARD INCHES", chained
          ;; beside the stair
          (setq ts   '()
                prev nil)
          (foreach td tds
            (if (or (null prev) (> (- (car td) prev) 1e-4))
              (setq ts   (cons (car td) ts)
                    prev (car td))))
          (setq ts (reverse ts))
          (if (cdr ts)
            (progn
              (ad:setdimstyle "STANDARD INCHES")
              (setq pts (mapcar
                          '(lambda (tv)
                             (mapcar '(lambda (uu vv)
                                        (+ (* smax uu) (* tv vv)))
                                     u v))
                          ts)
                    loc (mapcar '(lambda (uu vv)
                                   (+ (* (+ smax off) uu) (* (car ts) vv)))
                                u v))
              (setq cnt (+ cnt (ad:dimchain pts loc)))))))))
  cnt)

;; ------------------------------------------------- part 3: the floor dims

;; WCS intersection points between the line object and every object in ss
(defun ad:xpoints (lobj ss / i rtn pts res)
  (setq res '()
        i   0)
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
;; followed by DIMCONTINUE through every break point.  A start or end
;; point picked outside the perimeter of the obstacles is trimmed back
;; to the first/last crossing so no dims hang outside the plan.
;; Returns the number of dimensions placed.
(defun ad:floorchain (p1 p2 loc obstacles / ssx lin lobj len dir a ds d
                                            starton endon chain prev box
                                            raylen reps)
  (setq ssx (if obstacles obstacles (ad:geomss)))
  (entmake (list '(0 . "LINE") (cons 10 p1) (cons 11 p2)))
  (setq lin  (entlast)
        lobj (vlax-ename->vla-object lin))
  (if (and ssx (ssmemb lin ssx)) (ssdel lin ssx))
  (setq len (distance p1 p2)
        a   (angle p1 p2)
        dir (mapcar '(lambda (b c) (/ (- c b) len)) p1 p2)
        ds  '())
  ;; distance of every crossing object along the line, noting crossings
  ;; sitting right on the picked start / end points
  (foreach x (ad:xpoints lobj ssx)
    (setq d (apply '+ (mapcar '* dir (mapcar '- x p1))))
    (cond ((< (abs d) 1e-4)           (setq starton t))
          ((< (abs (- d len)) 1e-4)   (setq endon t))
          ((and (> d 1e-4) (< d (- len 1e-4))) (setq ds (cons d ds)))))
  (entdel lin)
  ;; sorted break points, near-coincident ones merged
  (setq chain (list p1)
        prev  0.0)
  (foreach d (vl-sort ds '<)
    (if (> (- d prev) 1e-4)
      (setq chain (cons (mapcar '(lambda (b v) (+ b (* d v))) p1 dir) chain)
            prev  d)))
  (setq chain (reverse (cons p2 chain)))
  ;; trim ends picked outside the perimeter: an end point is outside
  ;; when it is not on any highlighted object and nothing highlighted
  ;; lies behind it
  (if (and ssx (> (sslength ssx) 0))
    (progn
      (setq box    (ad:ssbox ssx)
            raylen (if box
                     (* 2.0 (+ (distance (car box) (cadr box)) len))
                     (* 4.0 len))
            reps   (* 1e-6 raylen))
      (if (and (not starton) (ad:sideclear p1 (+ a pi) raylen reps ssx))
        (progn
          (setq chain (cdr chain))
          (prompt "\n  (start point was outside the perimeter - chain trimmed)")))
      (if (and (cdr chain)
               (not endon)
               (ad:sideclear p2 a raylen reps ssx))
        (progn
          (setq chain (reverse (cdr (reverse chain))))
          (prompt "\n  (end point was outside the perimeter - chain trimmed)")))))
  (if (cdr chain)
    (ad:dimchain chain loc)
    0))

;; prompt the user to draw one floor dims line and dimension it,
;; breaking at the given obstacles (nil = all model space geometry)
(defun ad:getfloor (tag obstacles / p1 p2 loc n)
  (setq p1 (getpoint (strcat "\n" tag
                             " - pick the START point of the line to measure"
                             " along (Enter to skip): ")))
  (if p1
    (progn
      (setq p2 (getpoint p1 (strcat "\n" tag " - pick the END point: ")))
      (if (and p2 (> (distance p1 p2) 1e-8))
        (progn
          (setq loc (getpoint (strcat "\n" tag
                                      " - pick where the dimension chain"
                                      " should sit <on the drawn line>: ")))
          (if (null loc) (setq loc (ad:mid p1 p2)))
          (setq n (ad:floorchain (trans p1 1 0) (trans p2 1 0)
                                 (trans loc 1 0) obstacles))
          (if (> n 0)
            (prompt (strcat "\n" tag ": " (itoa n) " dimension(s) placed."))
            (prompt (strcat "\n" tag ": the drawn line lies outside the"
                            " plan - no dimensions placed.")))
          n)
        (prompt "\nNothing drawn - skipped.")))))

;; --------------------------------------------------------------- commands

(defun c:AUTODIM (/ *error* oldcmd olddim plan nper nstair)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg t) "*break*,*cancel*,*exit*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (prompt (strcat "\n=== AUTODIM step 1 of 4: highlight the plan ==="
                  "\nHighlight everything that makes up the plan (walls"
                  " etc.), then press Enter.  Only what you highlight is"
                  " dimensioned and used to find the perimeter."))
  (setq plan (ssget (ad:geomfilter)))
  (if (null plan)
    (prompt "\nNothing highlighted - AUTODIM cancelled.")
    (progn
      (setq oldcmd (getvar "CMDECHO")
            olddim (getvar "DIMSTYLE"))
      (setvar "CMDECHO" 0)
      (command "_.UNDO" "_Begin")
      (prompt (strcat "\n=== AUTODIM step 2 of 4: perimeter ==="
                      "\nDimensioning the straight lines about the"
                      " perimeter - no input needed..."))
      (ad:setdimstyle "SIDE DIMENSION")
      (setq nper (ad:dimperim plan))
      (prompt (strcat "\n" (itoa nper) " perimeter dimension(s) placed."))
      (ad:setdimstyle olddim)
      (prompt "\n=== AUTODIM step 3 of 4: stairs ===")
      (setq nstair (ad:dimstairs))
      (prompt (strcat "\n" (itoa nstair) " stair dimension(s) placed."))
      (ad:setdimstyle olddim)
      (prompt (strcat "\n=== AUTODIM step 4 of 4: floor dims ==="
                      "\nDraw two lines across the plan.  Each becomes a"
                      " dimension chain that breaks at every highlighted"
                      " object it crosses."))
      (ad:setdimstyle "STANDARD")
      (ad:getfloor "Floor dims 1 of 2" plan)
      (ad:getfloor "Floor dims 2 of 2" plan)
      (ad:setdimstyle olddim)
      (command "_.UNDO" "_End")
      (setvar "CMDECHO" oldcmd)
      (prompt "\nAUTODIM finished.")))
  (princ))

(defun c:STAIRDIM (/ *error* oldcmd olddim n)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg t) "*break*,*cancel*,*exit*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (setq oldcmd (getvar "CMDECHO")
        olddim (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (setq n (ad:dimstairs))
  (prompt (strcat "\n" (itoa n) " stair dimension(s) placed."))
  (ad:setdimstyle olddim)
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (princ))

(defun c:FLOORDIM (/ *error* oldcmd olddim)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg t) "*break*,*cancel*,*exit*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (setq oldcmd (getvar "CMDECHO")
        olddim (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)
  (command "_.UNDO" "_Begin")
  (ad:setdimstyle "STANDARD")
  (ad:getfloor "Floor dims" nil)
  (ad:setdimstyle olddim)
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (princ))

(princ "\nAutoDim.lsp loaded.  Commands: AUTODIM (highlight plan -> perimeter + stairs + two floor dims), STAIRDIM (dimension another stair selection), FLOORDIM (one extra floor dims chain).")
(princ)
