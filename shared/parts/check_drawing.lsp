;;; ------------------------------------------------------------------
;;;  check_drawing.lsp — CHECK: attachment QA for AutoCAD drawings
;;;
;;;  Adds the CHECK command (alias DIMARCCHECK). After asking you to
;;;  highlight the drawing, it runs two audits over the selection:
;;;
;;;  1. Dimensions (linear / aligned / rotated): both definition
;;;     points must lie on an object of some kind (line, arc, circle,
;;;     polyline, ellipse, spline). A dimension with a stray
;;;     definition point gets:
;;;       - a construction line (XLINE) drawn through its two dimmed
;;;         points on layer CHECK-CONSTRUCTION (yellow),
;;;       - the stray point shifted onto the closest point of the
;;;         closest object,
;;;       - its color changed to red so you can see it was shifted.
;;;
;;;  2. Arcs: each arc endpoint must sit at the END of another object.
;;;       - On an object but not at its end -> endpoint moved to the
;;;         closest end of that object.
;;;       - Not on anything -> endpoint moved to the closest endpoint
;;;         of any object in the selection (or, when every nearby
;;;         object is closed, the closest point on the closest one).
;;;     A moved arc is re-fitted through its fixed end, its old
;;;     midpoint and the new end, then recolored magenta.
;;;
;;;  Everything runs inside one UNDO group; a single U reverts every
;;;  change CHECK made. Tunables are just below.
;;; ------------------------------------------------------------------

;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;

(setq *checkdrawing-version* "v1.0")   ; announced on load; release_lisp.py
                                          ; stamps the dated twin in releases/

(vl-load-com)

;; --- tunables ------------------------------------------------------
(setq *cfchk-tol*          1.0e-4)  ; max gap (drawing units) that still counts as attached
(setq *cfchk-dim-color*    1)       ; red: dimensions whose points were shifted
(setq *cfchk-arc-color*    6)       ; magenta: arcs whose endpoints were snapped
(setq *cfchk-constr-layer* "CHECK-CONSTRUCTION")
(setq *cfchk-constr-color* 2)       ; yellow

;; entity types dimensions and arc ends may attach to
(setq *cfchk-curve-types*
      '("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"))

;; --- small helpers -------------------------------------------------

(defun cfchk:set-color (ent color / ed old)
  (setq ed  (entget ent)
        old (assoc 62 ed))
  (entmod (if old
            (subst (cons 62 color) old ed)
            (append ed (list (cons 62 color)))))
  (entupd ent))

(defun cfchk:make-xline (p1 p2 / len)
  ;; infinite construction line through p1-p2 on the check layer
  (setq len (distance p1 p2))
  (if (> len 1e-8)
    (entmake (list '(0 . "XLINE")
                   '(100 . "AcDbEntity")
                   (cons 8 *cfchk-constr-layer*)
                   '(100 . "AcDbXline")
                   (cons 10 p1)
                   (cons 11 (mapcar '(lambda (x) (/ x len)) (mapcar '- p2 p1)))))))

(defun cfchk:closest-on (ent pt / res)
  ;; closest point on ent to pt; nil when ent is not curve-like
  (setq res (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (vl-catch-all-error-p res) nil res))

(defun cfchk:nearest-curve (pt exclude cands / best bestd cp d)
  ;; (ent closest-point distance) for the candidate closest to pt
  (foreach e cands
    (if (and (not (eq e exclude)) (setq cp (cfchk:closest-on e pt)))
      (progn
        (setq d (distance pt cp))
        (if (or (null bestd) (< d bestd))
          (setq bestd d
                best  (list e cp d))))))
  best)

(defun cfchk:curve-ends (ent / cl sp ep)
  ;; the curve's two endpoints; nil when closed (or not a curve)
  (setq cl (vl-catch-all-apply 'vlax-curve-isClosed (list ent)))
  (if (or (vl-catch-all-error-p cl) cl)
    nil
    (progn
      (setq sp (vl-catch-all-apply 'vlax-curve-getStartPoint (list ent))
            ep (vl-catch-all-apply 'vlax-curve-getEndPoint (list ent)))
      (if (or (vl-catch-all-error-p sp) (vl-catch-all-error-p ep))
        nil
        (list sp ep)))))

(defun cfchk:closest-of (pt pts / best bestd d)
  (foreach q pts
    (setq d (distance pt q))
    (if (or (null bestd) (< d bestd)) (setq bestd d best q)))
  best)

(defun cfchk:nearest-end (pt exclude cands / best bestd d)
  ;; closest endpoint over every open candidate curve
  (foreach e cands
    (if (not (eq e exclude))
      (foreach q (cfchk:curve-ends e)
        (setq d (distance pt q))
        (if (or (null bestd) (< d bestd)) (setq bestd d best q)))))
  best)

;; --- geometry ------------------------------------------------------

(defun cfchk:planar-arc-p (ed / n)
  ;; only arcs drawn in the world XY plane are handled
  (setq n (cdr (assoc 210 ed)))
  (or (null n)
      (and (< (abs (car n)) 1e-9)
           (< (abs (cadr n)) 1e-9)
           (> (caddr n) 0.0))))

(defun cfchk:rebuild-arc (ent which fixed mid target / c r a1 a2 am tmp ed)
  ;; re-fit the arc through its fixed end, its old midpoint and the
  ;; target point; returns T on success
  (if (and (> (distance target fixed) 1e-8)
           (setq c (cal:circumcenter fixed mid target)))
    (progn
      (setq r  (distance c target)
            a1 (angle c (if (eq which 'start) target fixed))
            a2 (angle c (if (eq which 'start) fixed target))
            am (angle c mid))
      ;; ARC entities always sweep counter-clockwise from start to
      ;; end; keep the sweep that contains the old midpoint
      (if (> (cal:angnorm (- am a1)) (cal:angnorm (- a2 a1)))
        (setq tmp a1
              a1  a2
              a2  tmp))
      (setq ed (entget ent))
      (foreach pair (list (cons 10 c) (cons 40 r) (cons 50 a1) (cons 51 a2))
        (setq ed (subst pair (assoc (car pair) ed) ed)))
      (if (entmod ed)
        (progn (entupd ent) T)))))

;; --- audit 1: dimension attachment ---------------------------------

(defun cfchk:fix-defpoint (ent gcode cands / ed pt near)
  ;; shift one definition point onto the closest object when it is
  ;; not already on one; returns the shift distance, nil if untouched
  (setq ed (entget ent)
        pt (cdr (assoc gcode ed)))
  (if pt
    (progn
      (setq near (cfchk:nearest-curve pt nil cands))
      (if (and near (> (caddr near) *cfchk-tol*))
        (if (entmod (subst (cons gcode (cadr near)) (assoc gcode ed) ed))
          (caddr near))))))

(defun cfchk:check-dim (ent cands / ed dtype p13 p14 d1 d2)
  (setq ed    (entget ent)
        dtype (logand 7 (cdr (assoc 70 ed))))
  (if (member dtype '(0 1))                 ; rotated/linear or aligned
    (progn
      (setq p13 (cdr (assoc 13 ed))         ; the two dimmed points
            p14 (cdr (assoc 14 ed))
            d1  (cfchk:fix-defpoint ent 13 cands)
            d2  (cfchk:fix-defpoint ent 14 cands))
      (if (or d1 d2)
        (progn
          (cfchk:make-xline p13 p14)        ; through the ORIGINAL points
          (cfchk:set-color ent *cfchk-dim-color*)
          (entupd ent)
          (princ (strcat "\n  Dimension " (cdr (assoc 5 ed)) ":"
                         (if d1 (strcat " point 1 shifted " (rtos d1 2 4)) "")
                         (if d2 (strcat " point 2 shifted " (rtos d2 2 4)) "")
                         " onto nearest object; recolored red."))
          'fixed)
        'ok))
    'skipped))

;; --- audit 2: arc endpoint attachment ------------------------------

(defun cfchk:fix-arc-end (ent which cands / p other mid near ends target)
  ;; returns the snap distance when the endpoint was moved, else nil
  (setq mid   (vlax-curve-getPointAtDist
                ent
                (/ (vlax-curve-getDistAtParam ent (vlax-curve-getEndParam ent)) 2.0))
        p     (if (eq which 'start)
                (vlax-curve-getStartPoint ent)
                (vlax-curve-getEndPoint ent))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent))
        near  (cfchk:nearest-curve p ent cands))
  (cond
    ((null near) nil)                       ; nothing to attach to at all
    ((<= (caddr near) *cfchk-tol*)          ; endpoint sits on an object...
     (setq ends (cfchk:curve-ends (car near)))
     ;; never snap onto the arc's own other endpoint
     (setq ends (vl-remove-if '(lambda (q) (< (distance q other) 1e-8)) ends))
     (cond
       ((null ends) nil)                    ; closed curve: no ends to demand
       ((vl-some '(lambda (q) (<= (distance p q) *cfchk-tol*)) ends)
        nil)                                ; ...and at one of its ends: OK
       (t                                   ; ...but mid-object: closest end of that object
        (setq target (cfchk:closest-of p ends))
        (if (cfchk:rebuild-arc ent which other mid target)
          (distance p target)))))
    (t                                      ; floating: closest end anywhere,
     (setq target (cfchk:nearest-end p ent cands))
     (if (or (null target) (< (distance target other) 1e-8))
       (setq target (cadr near)))           ; else closest point on closest object
     (if (cfchk:rebuild-arc ent which other mid target)
       (distance p target)))))

(defun cfchk:check-arc (ent cands / ed d1 d2)
  (setq ed (entget ent))
  (if (cfchk:planar-arc-p ed)
    (progn
      (setq d1 (cfchk:fix-arc-end ent 'start cands)
            d2 (cfchk:fix-arc-end ent 'end cands))
      (if (or d1 d2)
        (progn
          (cfchk:set-color ent *cfchk-arc-color*)
          (princ (strcat "\n  Arc " (cdr (assoc 5 ed)) ":"
                         (if d1 (strcat " start snapped " (rtos d1 2 4)) "")
                         (if d2 (strcat " end snapped " (rtos d2 2 4)) "")
                         " to nearest object end; recolored magenta."))
          'fixed)
        'ok))
    'skipped))

;; --- command -------------------------------------------------------

(defun c:CHECK ( / *error* oldecho undo-open ss i e et cands dims arcs res
                   ndf ndo nds naf nao nas)
  (defun *error* (msg)
    (if undo-open
      (progn (setvar "CMDECHO" 0) (command "_.UNDO" "_End")))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCHECK error: " msg)))
    (princ))

  (prompt "\nHighlight the drawing to CHECK: ")
  (setq ss (ssget))
  (cond
    ((null ss)
     (prompt "\nNothing selected - CHECK cancelled."))
    (t
     (setq cands nil dims nil arcs nil i 0
           ndf 0 ndo 0 nds 0 naf 0 nao 0 nas 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (member et *cfchk-curve-types*) (setq cands (cons e cands))))
     (setq dims  (reverse dims)
           arcs  (reverse arcs)
           cands (reverse cands))
     (cond
       ((and (null dims) (null arcs))
        (prompt "\nSelection holds no dimensions or arcs - nothing to check."))
       ((null cands)
        (prompt "\nSelection holds no lines/arcs/curves to attach to - nothing to check against."))
       (t
        (setq oldecho (getvar "CMDECHO"))
        (setvar "CMDECHO" 0)
        (command "_.UNDO" "_Begin")
        (setq undo-open T)
        (cal:ensure-layer *cfchk-constr-layer* *cfchk-constr-color*)
        (foreach e dims
          (setq res (cfchk:check-dim e cands))
          (cond ((eq res 'fixed)   (setq ndf (1+ ndf)))
                ((eq res 'skipped) (setq nds (1+ nds)))
                (t                 (setq ndo (1+ ndo)))))
        (foreach e arcs
          (setq res (cfchk:check-arc e cands))
          (cond ((eq res 'fixed)   (setq naf (1+ naf)))
                ((eq res 'skipped) (setq nas (1+ nas)))
                (t                 (setq nao (1+ nao)))))
        (command "_.UNDO" "_End")
        (setq undo-open nil)
        (setvar "CMDECHO" oldecho)
        (princ (strcat "\n--- CHECK complete (attachment tolerance "
                       (rtos *cfchk-tol* 2 6) ") ---"
                       "\nDimensions: " (itoa (+ ndf ndo)) " checked, "
                       (itoa ndf) " shifted onto nearest object (red)"
                       (if (> nds 0)
                         (strcat ", " (itoa nds) " unsupported type skipped")
                         "")
                       "\nArcs: " (itoa (+ naf nao)) " checked, "
                       (itoa naf) " with endpoint(s) snapped (magenta)"
                       (if (> nas 0)
                         (strcat ", " (itoa nas) " non-planar skipped")
                         "")
                       (if (> ndf 0)
                         (strcat "\nConstruction lines through the shifted dimensions' points are on layer "
                                 *cfchk-constr-layer* ".")
                         "")
                       "\nOne UNDO reverts everything CHECK changed."))))))
  (princ))

(defun c:DIMARCCHECK () (c:CHECK))

(princ "\ncheck_drawing.lsp loaded - type CHECK to audit dimension & arc attachment.")
(princ)
