;;; ------------------------------------------------------------------
;;;  dimcheck.lsp — DIMCHECK: interactive dimension & arc QA review
;;;
;;;  Based on check_drawing.lsp (CHECK), reworked into a guided,
;;;  one-at-a-time review. Type DIMCHECK, then:
;;;
;;;  1. You are asked to highlight the drawing (any selection).
;;;     Everything selected is greyed out so only the item under
;;;     review stands out.
;;;
;;;  2. Dimensions are reviewed ONE AT A TIME. Each dimension is
;;;     zoomed to, shown in its own colour and highlighted while the
;;;     rest stays grey. For linear/aligned dimensions the two
;;;     definition points are audited first: a point that does not
;;;     sit on any object is moved onto the closest object, marked
;;;     with a cross on screen, and you are asked — one point at a
;;;     time — whether the moved location is correct:
;;;         Enter / Y  ->  keep it there
;;;         N          ->  you pick the correct location yourself
;;;     A construction line (XLINE) is drawn through the dimension's
;;;     original points on layer DIMCHECK-CONSTRUCTION so you can see
;;;     where it used to measure.
;;;     Then the overall question for every dimension:
;;;         "Is this dimension correct?"
;;;         Enter / Y  ->  correct, the dimension is left alone
;;;         N          ->  the dimension is recoloured RED so it is
;;;                        easy to find and fix afterwards
;;;
;;;  3. Arcs are reviewed the same way, one endpoint at a time. An
;;;     endpoint that is not attached to the end of another object is
;;;     snapped there (same rules as CHECK), marked with a cross, and
;;;     you confirm each moved point — Enter keeps it, N lets you
;;;     pick where it belongs (the arc is re-fitted through your
;;;     point). Arcs whose endpoints changed are recoloured MAGENTA.
;;;
;;;  4. A DIMCHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;     drawing on layer DIMCHECK-REPORT listing every dimension and
;;;     arc that was checked and what happened to it, plus totals.
;;;
;;;  All original colours are restored when the review ends — except
;;;  the red "fix me" dimensions and magenta moved arcs, which stay
;;;  marked on purpose. Everything (including the report) runs inside
;;;  one UNDO group, so a single U reverts the whole review.
;;; ------------------------------------------------------------------

(vl-load-com)

;; --- tunables ------------------------------------------------------
(setq *dchk-tol*          1.0e-4)  ; max gap (drawing units) that still counts as attached
(setq *dchk-grey-color*   8)       ; grey used to fade out everything not under review
(setq *dchk-flag-color*   1)       ; red: dimensions you answered "No" to
(setq *dchk-arc-color*    6)       ; magenta: arcs whose endpoints were moved
(setq *dchk-constr-layer* "DIMCHECK-CONSTRUCTION")
(setq *dchk-constr-color* 2)       ; yellow
(setq *dchk-report-layer* "DIMCHECK-REPORT")
(setq *dchk-report-color* 3)       ; green
(setq *dchk-zoom-margin*  0.75)    ; empty space around the zoomed item (fraction of its size)
(setq *dchk-report-chars* 45.0)    ; report column width, in text heights
(setq *dchk-ask-all-arc-ends* nil) ; T = confirm EVERY arc endpoint, even already-attached ones

;; entity types dimension points and arc ends may attach to
(setq *dchk-curve-types*
      '("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"))

;; --- small helpers -------------------------------------------------

(defun dchk:ensure-layer (name color)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   '(70 . 0)
                   (cons 62 color)))))

(defun dchk:ent-color (ent / c)
  ;; the entity's explicit colour, 256 (ByLayer) when it has none
  (setq c (cdr (assoc 62 (entget ent))))
  (if c c 256))

(defun dchk:set-color (ent color / ed old)
  (setq ed  (entget ent)
        old (assoc 62 ed))
  (entmod (if old
            (subst (cons 62 color) old ed)
            (append ed (list (cons 62 color)))))
  (entupd ent))

(defun dchk:make-xline (p1 p2 / len)
  ;; infinite construction line through p1-p2 on the check layer
  (setq len (distance p1 p2))
  (if (> len 1e-8)
    (entmake (list '(0 . "XLINE")
                   '(100 . "AcDbEntity")
                   (cons 8 *dchk-constr-layer*)
                   '(100 . "AcDbXline")
                   (cons 10 p1)
                   (cons 11 (mapcar '(lambda (x) (/ x len)) (mapcar '- p2 p1)))))))

(defun dchk:closest-on (ent pt / res)
  ;; closest point on ent to pt; nil when ent is not curve-like
  (setq res (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (vl-catch-all-error-p res) nil res))

(defun dchk:nearest-curve (pt exclude cands / best bestd cp d)
  ;; (ent closest-point distance) for the candidate closest to pt
  (foreach e cands
    (if (and (not (eq e exclude)) (setq cp (dchk:closest-on e pt)))
      (progn
        (setq d (distance pt cp))
        (if (or (null bestd) (< d bestd))
          (setq bestd d
                best  (list e cp d))))))
  best)

(defun dchk:curve-ends (ent / cl sp ep)
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

(defun dchk:closest-of (pt pts / best bestd d)
  (foreach q pts
    (setq d (distance pt q))
    (if (or (null bestd) (< d bestd)) (setq bestd d best q)))
  best)

(defun dchk:nearest-end (pt exclude cands / best bestd d)
  ;; closest endpoint over every open candidate curve
  (foreach e cands
    (if (not (eq e exclude))
      (foreach q (dchk:curve-ends e)
        (setq d (distance pt q))
        (if (or (null bestd) (< d bestd)) (setq bestd d best q)))))
  best)

(defun dchk:ptstr (p)
  (strcat "(" (rtos (car p) 2 4) ", " (rtos (cadr p) 2 4) ")"))

(defun dchk:pad2 (n)
  (if (< n 10) (strcat "0" (itoa n)) (itoa n)))

(defun dchk:datestr (/ d dd tt)
  ;; CDATE is YYYYMMDD.HHMMSSmsec; decoded arithmetically so DIMZIN
  ;; (which trims rtos output) cannot mangle it
  (setq d  (getvar "CDATE")
        dd (fix d)
        tt (- d dd))
  (strcat (itoa (fix (/ dd 10000))) "-"
          (dchk:pad2 (rem (fix (/ dd 100)) 100)) "-"
          (dchk:pad2 (rem dd 100)) " "
          (dchk:pad2 (fix (+ (* tt 100) 1e-6))) ":"
          (dchk:pad2 (rem (fix (+ (* tt 10000) 1e-4)) 100))))

(defun dchk:bbox (ent / obj ll ur)
  ;; ((minx miny minz) (maxx maxy maxz)) in WCS, or nil
  (setq obj (vlax-ename->vla-object ent))
  (if (not (vl-catch-all-error-p
             (vl-catch-all-apply 'vla-getboundingbox (list obj 'll 'ur))))
    (list (vlax-safearray->list ll) (vlax-safearray->list ur))))

(defun dchk:zoom-ent (ent / bb p1 p2 m)
  ;; zoom the current view onto ent with some breathing room
  (setq bb (dchk:bbox ent))
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *dchk-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

(defun dchk:mark-point (pt / p s)
  ;; temporary cross + X over the point under review (WCS in, screen out)
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (cadr p)) (list (+ (car p) s) (cadr p)) 2 1)
  (grdraw (list (car p) (- (cadr p) s)) (list (car p) (+ (cadr p) s)) 2 1)
  (grdraw (list (- (car p) s) (- (cadr p) s)) (list (+ (car p) s) (+ (cadr p) s)) 2 1)
  (grdraw (list (- (car p) s) (+ (cadr p) s)) (list (+ (car p) s) (- (cadr p) s)) 2 1))

(defun dchk:ask-yn (msg / ans)
  ;; T = yes (Enter or Y), nil = no (N)
  (initget "Yes No")
  (setq ans (getkword (strcat msg " [Yes/No] <Yes>: ")))
  (or (null ans) (= ans "Yes")))

(defun dchk:confirm-point (label pt / newp)
  ;; marks pt (WCS), asks whether the location is correct; returns the
  ;; user's replacement point (in the CURRENT UCS) or nil to keep pt
  (dchk:mark-point pt)
  (if (dchk:ask-yn (strcat "\n  " label " is now at " (dchk:ptstr pt)
                           ". Is this location correct?"))
    nil
    (getpoint (strcat "\n  Pick the correct location for " label
                      " <keep current>: "))))

(defun dchk:mtext (ins height width text layer / dxf)
  ;; entmake an MTEXT, splitting text into 250-char DXF chunks
  (setq dxf (list '(0 . "MTEXT")
                  '(100 . "AcDbEntity")
                  (cons 8 layer)
                  '(100 . "AcDbMText")
                  (cons 10 ins)
                  (cons 40 height)
                  (cons 41 width)
                  '(71 . 1)))                  ; attachment: top-left
  (while (> (strlen text) 250)
    (setq dxf  (append dxf (list (cons 3 (substr text 1 250))))
          text (substr text 251)))
  (entmake (append dxf (list (cons 1 text)))))

;; --- geometry ------------------------------------------------------

(defun dchk:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

(defun dchk:circumcenter (p1 p2 p3 / ax ay bx by cx cy d)
  ;; center of the circle through three points (plan view, z taken
  ;; from p1); nil when the points are collinear
  (setq ax (car p1) ay (cadr p1)
        bx (car p2) by (cadr p2)
        cx (car p3) cy (cadr p3)
        d  (* 2.0 (+ (* ax (- by cy)) (* bx (- cy ay)) (* cx (- ay by)))))
  (if (> (abs d) 1e-12)
    (list (/ (+ (* (+ (* ax ax) (* ay ay)) (- by cy))
                (* (+ (* bx bx) (* by by)) (- cy ay))
                (* (+ (* cx cx) (* cy cy)) (- ay by)))
             d)
          (/ (+ (* (+ (* ax ax) (* ay ay)) (- cx bx))
                (* (+ (* bx bx) (* by by)) (- ax cx))
                (* (+ (* cx cx) (* cy cy)) (- bx ax)))
             d)
          (caddr p1))))

(defun dchk:planar-arc-p (ed / n)
  ;; only arcs drawn in the world XY plane are handled
  (setq n (cdr (assoc 210 ed)))
  (or (null n)
      (and (< (abs (car n)) 1e-9)
           (< (abs (cadr n)) 1e-9)
           (> (caddr n) 0.0))))

(defun dchk:rebuild-arc (ent which fixed mid target / c r a1 a2 am tmp ed)
  ;; re-fit the arc through its fixed end, its old midpoint and the
  ;; target point; returns T on success
  (if (and (> (distance target fixed) 1e-8)
           (setq c (dchk:circumcenter fixed mid target)))
    (progn
      (setq r  (distance c target)
            a1 (angle c (if (eq which 'start) target fixed))
            a2 (angle c (if (eq which 'start) fixed target))
            am (angle c mid))
      ;; ARC entities always sweep counter-clockwise from start to
      ;; end; keep the sweep that contains the old midpoint
      (if (> (dchk:angnorm (- am a1)) (dchk:angnorm (- a2 a1)))
        (setq tmp a1
              a1  a2
              a2  tmp))
      (setq ed (entget ent))
      (foreach pair (list (cons 10 c) (cons 40 r) (cons 50 a1) (cons 51 a2))
        (setq ed (subst pair (assoc (car pair) ed) ed)))
      (if (entmod ed)
        (progn (entupd ent) T)))))

(defun dchk:move-arc-end (ent which target / mid other)
  ;; re-fit the arc so the chosen endpoint lands on target (WCS)
  (setq mid   (vlax-curve-getPointAtDist
                ent
                (/ (vlax-curve-getDistAtParam ent (vlax-curve-getEndParam ent)) 2.0))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent)))
  (dchk:rebuild-arc ent which other mid target))

;; --- dimension review ----------------------------------------------

(defun dchk:audit-dim-point (ent gcode label cands / ed pt near final newp)
  ;; audits one definition point: off-object points are moved onto the
  ;; closest object, then the user confirms (Enter) or re-picks (N).
  ;; Returns (original final how) when the point moved, nil otherwise.
  (setq ed (entget ent)
        pt (cdr (assoc gcode ed)))
  (if pt
    (progn
      (setq near (dchk:nearest-curve pt nil cands))
      (if (and near (> (caddr near) *dchk-tol*))
        (progn
          (setq final (cadr near))
          (entmod (subst (cons gcode final) (assoc gcode ed) ed))
          (entupd ent)
          (princ (strcat "\n  " label " was not on any object; moved "
                         (rtos (caddr near) 2 4) " onto the nearest one."))
          (setq newp (dchk:confirm-point label final))
          (if newp
            (progn
              (setq final (trans newp 1 0)
                    ed    (entget ent))
              (entmod (subst (cons gcode final) (assoc gcode ed) ed))
              (entupd ent)
              (princ (strcat "\n  " label " moved to your point "
                             (dchk:ptstr final) "."))))
          (redraw)
          (list pt final (if newp 'user 'auto)))))))

(defun dchk:review-dim (ent cands num total / ed dtype h p13 p14 r1 r2 moved ok note)
  ;; interactive review of one dimension.
  ;; Returns (handle ok-flag report-note moved-point-count).
  (setq ed    (entget ent)
        h     (cdr (assoc 5 ed))
        dtype (logand 7 (cdr (assoc 70 ed))))
  (dchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nDimension " (itoa num) " of " (itoa total)
                 " (handle " h ")"))
  (if (member dtype '(0 1))                   ; rotated/linear or aligned
    (progn
      (setq p13 (cdr (assoc 13 ed))           ; the two dimmed points
            p14 (cdr (assoc 14 ed))
            r1  (dchk:audit-dim-point ent 13 "dimension point 1" cands)
            r2  (dchk:audit-dim-point ent 14 "dimension point 2" cands))
      (if (or r1 r2)
        (dchk:make-xline p13 p14))))          ; through the ORIGINAL points
  (setq moved (append (if r1 (list r1)) (if r2 (list r2))))
  (redraw ent 3)
  (setq ok (dchk:ask-yn "\n  Is this dimension correct?"))
  (redraw ent 4)
  (redraw)
  (setq note (cond
               ((and ok moved)
                (strcat "OK (" (itoa (length moved)) " point(s) adjusted)"))
               (ok "OK")
               (moved
                (strcat "FLAGGED to fix (red, " (itoa (length moved))
                        " point(s) adjusted)"))
               (t "FLAGGED to fix (red)")))
  (if (not ok) (dchk:set-color ent *dchk-flag-color*))
  (list h ok note (length moved)))

;; --- arc review ----------------------------------------------------

(defun dchk:arc-end-target (ent which cands / p other near ends target)
  ;; where the attachment audit says this endpoint should go;
  ;; nil when the endpoint is already fine (or nothing to attach to)
  (setq p     (if (eq which 'start)
                (vlax-curve-getStartPoint ent)
                (vlax-curve-getEndPoint ent))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent))
        near  (dchk:nearest-curve p ent cands))
  (cond
    ((null near) nil)                         ; nothing to attach to at all
    ((<= (caddr near) *dchk-tol*)             ; endpoint sits on an object...
     (setq ends (dchk:curve-ends (car near)))
     ;; never snap onto the arc's own other endpoint
     (setq ends (vl-remove-if '(lambda (q) (< (distance q other) 1e-8)) ends))
     (cond
       ((null ends) nil)                      ; closed curve: no ends to demand
       ((vl-some '(lambda (q) (<= (distance p q) *dchk-tol*)) ends)
        nil)                                  ; ...and at one of its ends: OK
       (t (dchk:closest-of p ends))))         ; ...but mid-object: closest end
    (t                                        ; floating: closest end anywhere,
     (setq target (dchk:nearest-end p ent cands))
     (if (or (null target) (< (distance target other) 1e-8))
       (cadr near)                            ; else closest point on closest object
       target))))

(defun dchk:review-arc-end (ent which label cands / p target newp final)
  ;; audits one arc endpoint, snaps it when detached, then lets the
  ;; user confirm (Enter) or re-pick (N) the moved point.
  ;; Returns (original final how) when the endpoint moved, nil otherwise.
  (setq p      (if (eq which 'start)
                 (vlax-curve-getStartPoint ent)
                 (vlax-curve-getEndPoint ent))
        target (dchk:arc-end-target ent which cands))
  (cond
    (target
     (if (dchk:move-arc-end ent which target)
       (progn
         (princ (strcat "\n  " label " was not attached to an object end; snapped "
                        (rtos (distance p target) 2 4) "."))
         (setq final target
               newp  (dchk:confirm-point label target))
         (if newp
           (progn
             (setq newp (trans newp 1 0))
             (if (dchk:move-arc-end ent which newp)
               (progn
                 (setq final newp)
                 (princ (strcat "\n  " label " moved to your point "
                                (dchk:ptstr final) ".")))
               (princ "\n  Could not re-fit the arc through that point (collinear?); kept the snapped position."))))
         (redraw)
         (list p final (if newp 'user 'auto)))
       (progn
         (princ (strcat "\n  " label " should attach at " (dchk:ptstr target)
                        " but the arc could not be re-fitted (points collinear?)."))
         nil)))
    (*dchk-ask-all-arc-ends*                  ; optional: confirm attached ends too
     (setq newp (dchk:confirm-point label p))
     (redraw)
     (if newp
       (progn
         (setq newp (trans newp 1 0))
         (if (dchk:move-arc-end ent which newp)
           (list p newp 'user)
           (progn
             (princ "\n  Could not re-fit the arc through that point (collinear?); unchanged.")
             nil)))))
    (t nil)))

(defun dchk:review-arc (ent cands num total / ed h planar r1 r2 moved note)
  ;; interactive review of one arc's endpoints.
  ;; Returns (handle untouched-flag report-note moved-point-count).
  (setq ed     (entget ent)
        h      (cdr (assoc 5 ed))
        planar (dchk:planar-arc-p ed))
  (dchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nArc " (itoa num) " of " (itoa total)
                 " (handle " h ")"))
  (if planar
    (setq r1 (dchk:review-arc-end ent 'start "arc start point" cands)
          r2 (dchk:review-arc-end ent 'end   "arc end point"   cands))
    (princ "\n  Arc is not in the world XY plane - endpoint audit skipped."))
  (redraw ent 4)
  (redraw)
  (setq moved (append (if r1 (list r1)) (if r2 (list r2))))
  (if moved (dchk:set-color ent *dchk-arc-color*))
  (setq note (cond
               ((not planar) "not in world XY plane - skipped")
               (moved (strcat (itoa (length moved))
                              " endpoint(s) moved (magenta)"))
               (t "endpoints OK")))
  (list h (null moved) note (length moved)))

;; --- command -------------------------------------------------------

(defun c:DIMCHECK ( / *error* oldecho vc vs undo-open ss i e et
                      cands dims arcs saved keep res n total lines
                      ndok ndflag ndmoved naok namoved nasnap
                      minx miny maxx maxy bb h m ins txt)

  (defun *error* (msg)
    ;; put the greys back (flagged/moved items keep their colour),
    ;; clear markers, close the undo group
    (foreach pair saved
      (if (and (not (member (car pair) keep)) (entget (car pair)))
        (dchk:set-color (car pair) (cdr pair))))
    (redraw)
    (if undo-open
      (progn (setvar "CMDECHO" 0) (command "_.UNDO" "_End")))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nDIMCHECK error: " msg)))
    (princ))

  (prompt "\nHighlight the drawing to DIMCHECK: ")
  (setq ss (ssget))
  (cond
    ((null ss)
     (prompt "\nNothing selected - DIMCHECK cancelled."))
    (t
     (setq cands nil dims nil arcs nil saved nil keep nil lines nil i 0
           ndok 0 ndflag 0 ndmoved 0 naok 0 namoved 0 nasnap 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (member et *dchk-curve-types*) (setq cands (cons e cands))))
     (setq dims  (reverse dims)
           arcs  (reverse arcs)
           cands (reverse cands))
     (cond
       ((and (null dims) (null arcs))
        (prompt "\nSelection holds no dimensions or arcs - nothing to check."))
       (t
        (setq oldecho (getvar "CMDECHO"))
        (setvar "CMDECHO" 0)
        (setq vc (getvar "VIEWCTR")
              vs (getvar "VIEWSIZE"))
        (command "_.UNDO" "_Begin")
        (setq undo-open T)
        (dchk:ensure-layer *dchk-constr-layer* *dchk-constr-color*)
        (dchk:ensure-layer *dchk-report-layer* *dchk-report-color*)

        ;; extents of the selection (report goes to the right of them)
        (setq i 0)
        (repeat (sslength ss)
          (setq e  (ssname ss i)
                i  (1+ i)
                bb (dchk:bbox e))
          (if bb
            (setq minx (if minx (min minx (caar bb)) (caar bb))
                  miny (if miny (min miny (cadar bb)) (cadar bb))
                  maxx (if maxx (max maxx (caadr bb)) (caadr bb))
                  maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))

        ;; grey out the whole selection so each item can take the stage
        (setq i 0)
        (repeat (sslength ss)
          (setq e (ssname ss i)
                i (1+ i))
          (setq saved (cons (cons e (dchk:ent-color e)) saved))
          (dchk:set-color e *dchk-grey-color*))

        ;; --- dimensions, one at a time -----------------------------
        (if dims
          (princ (strcat "\n--- Reviewing " (itoa (length dims))
                         " dimension(s): Enter = correct, N = flag to fix ---")))
        (setq n 0 total (length dims))
        (foreach e dims
          (setq n (1+ n))
          (dchk:set-color e (cdr (assoc e saved)))       ; step into the light
          (setq res (dchk:review-dim e cands n total))
          (setq ndmoved (+ ndmoved (cadddr res)))
          (if (cadr res)
            (progn (setq ndok (1+ ndok))
                   (dchk:set-color e *dchk-grey-color*)) ; done: back to grey
            (progn (setq ndflag (1+ ndflag))
                   (setq keep (cons e keep))))           ; flagged: stays red
          (setq lines (cons (strcat "Dim " (car res) ": " (caddr res)) lines)))

        ;; --- arcs, one endpoint at a time --------------------------
        (if arcs
          (princ (strcat "\n--- Reviewing " (itoa (length arcs))
                         " arc(s): checking endpoint attachment ---")))
        (setq n 0 total (length arcs))
        (foreach e arcs
          (setq n (1+ n))
          (dchk:set-color e (cdr (assoc e saved)))
          (setq res (dchk:review-arc e cands n total))
          (setq nasnap (+ nasnap (cadddr res)))
          (if (cadr res)
            (progn (setq naok (1+ naok))
                   (dchk:set-color e *dchk-grey-color*))
            (progn (setq namoved (1+ namoved))
                   (setq keep (cons e keep))))           ; moved: stays magenta
          (setq lines (cons (strcat "Arc " (car res) ": " (caddr res)) lines)))

        ;; --- restore colours (flagged/moved keep theirs) ------------
        (foreach pair saved
          (if (and (not (member (car pair) keep)) (entget (car pair)))
            (dchk:set-color (car pair) (cdr pair))))

        ;; --- report on the right side -------------------------------
        (setq h (* (getvar "DIMTXT") (getvar "DIMSCALE")))
        (if (and (or (null h) (<= h 0.0)) minx)
          (setq h (/ (max (- maxx minx) (- maxy miny)) 60.0)))
        (if (or (null h) (<= h 0.0)) (setq h 2.5))
        (setq ins (if minx
                    (list (+ maxx (* 0.05 (max (- maxx minx) 1.0))) maxy 0.0)
                    (list 0.0 0.0 0.0)))
        (setq txt (strcat "DIMCHECK REPORT - " (dchk:datestr)
                          "\\PDimensions checked: " (itoa (length dims))
                          " (correct: " (itoa ndok)
                          ", flagged to fix: " (itoa ndflag)
                          ", points adjusted: " (itoa ndmoved) ")"
                          "\\PArcs checked: " (itoa (length arcs))
                          " (OK: " (itoa naok)
                          ", with endpoints moved: " (itoa namoved)
                          ", endpoints moved in total: " (itoa nasnap) ")"
                          "\\P----------------------------------------"))
        (foreach l (reverse lines)
          (setq txt (strcat txt "\\P" l)))
        (dchk:mtext ins h (* *dchk-report-chars* h) txt *dchk-report-layer*)

        ;; --- show the drawing plus the report -----------------------
        (if minx
          (progn
            (setq m (* 0.05 (max (- maxx minx) (- maxy miny) 1.0)))
            (command "_.ZOOM" "_Window"
                     (trans (list (- minx m) (- miny m) 0.0) 0 1)
                     (trans (list (+ (car ins) (* *dchk-report-chars* h) m)
                                  (+ maxy m) 0.0)
                            0 1)))
          (command "_.ZOOM" "_Center" vc vs))

        (command "_.UNDO" "_End")
        (setq undo-open nil)
        (setvar "CMDECHO" oldecho)
        (princ (strcat "\n\n--- DIMCHECK complete ---"
                       "\nDimensions: " (itoa (length dims)) " checked, "
                       (itoa ndok) " correct, "
                       (itoa ndflag) " flagged to fix (red)"
                       (if (> ndmoved 0)
                         (strcat ", " (itoa ndmoved) " point(s) adjusted")
                         "")
                       "\nArcs: " (itoa (length arcs)) " checked, "
                       (itoa namoved) " with endpoint(s) moved ("
                       (itoa nasnap) " endpoint(s), magenta)"
                       "\nReport placed on the right side of the drawing (layer "
                       *dchk-report-layer* ")."
                       (if (> ndmoved 0)
                         (strcat "\nConstruction lines through moved dimensions' original points are on layer "
                                 *dchk-constr-layer* ".")
                         "")
                       "\nOne UNDO reverts everything DIMCHECK changed (including the report)."))))))
  (princ))

(princ "\ndimcheck.lsp loaded - type DIMCHECK to review dimensions & arcs one at a time.")
(princ)
