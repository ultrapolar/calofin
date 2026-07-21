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
;;;  2. Dimensions are reviewed ONE AT A TIME, in a fixed marching
;;;     order: grouped by dimension style — "STANDARD", then "SIDE
;;;     STANDARD", then "STANDARD INCHES", then "CROSS DIMENSIONS",
;;;     then whatever styles are left (tune *dchk-style-order*) —
;;;     and inside each group left to right, top to bottom (row by
;;;     row, like reading). Each dimension is zoomed to, shown in
;;;     its own colour and highlighted while the rest stays grey. For linear/aligned dimensions the two
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
;;;  4. OVERLAPPING LINES are hunted down: two straight LINE entities
;;;     that are collinear and run on top of each other (a leftover
;;;     from drawing over an existing line to continue it and never
;;;     cleaning it up). Each overlapping pair is zoomed to and
;;;     highlighted, the overlapping stretch is marked with crosses,
;;;     and you choose:
;;;         Enter / M  ->  MERGE the two into one line spanning both
;;;                        (only when they share a layer; the merged
;;;                        line turns CYAN so you can see it changed)
;;;         F          ->  FLAG both lines CYAN to fix by hand
;;;         L          ->  LEAVE them as drawn (intentional)
;;;     Lines that merely touch end-to-end are fine and not reported.
;;;
;;;  5. STEP / STAIRCASE check. Groups of 3+ parallel lines stacked
;;;     less than 18 units apart (18" in inch drawings — tune
;;;     *dchk-step-maxgap*) look like steps. When such patterns are
;;;     found, DIMCHECK first looks for a staircase SIDE VIEW in the
;;;     selection (a side view reads as two step patterns at right
;;;     angles to each other — treads + risers — in the same spot).
;;;       - Side view found  -> steps are taken as real; skip ahead.
;;;       - No side view     -> each pattern is highlighted and you
;;;         are asked "Are these lines steps?". If any are, you are
;;;         asked whether a side view is drawn somewhere; if not, the
;;;         report tells you to ADD A SIDE VIEW.
;;;     Whenever steps + side view are present, the selection must
;;;     hold a block with the words "Step Attachment" (block name,
;;;     attribute or text inside it). None -> the report tells you to
;;;     add one. Found -> it is zoomed to and you confirm the CORRECT
;;;     one is placed; answering No flags it red and reports it.
;;;     When the attachment style is "BEAD Step Attachment", every
;;;     plan-view step pattern must also have something drawn on
;;;     layer "Bead Track" (tune *dchk-bead-layer*) within
;;;     *dchk-bead-dist* of it. The whole drawing is searched, not
;;;     just the selection. The side view itself is exempt — bead
;;;     track is only demanded next to the plan-view steps. Patterns
;;;     with nothing nearby are called out in the report.
;;;
;;;  6. LINER MATERIAL check. The selection must hold a block named
;;;     (or containing the words) "Liner Material" / "Liner Material
;;;     with Step". Missing -> reported. Each one found is scanned
;;;     for the standalone word "NOT" in its attributes and text
;;;     (e.g. "Not Selected", "Not Included"); any hit is reported
;;;     with the block's location so you can look at it.
;;;
;;;  7. A DIMCHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;     drawing on layer DIMCHECK-REPORT listing every dimension —
;;;     with its measured distance (in the drawing's units; angular
;;;     dims show their angle) — every arc, every overlapping line
;;;     pair (with its overlap length), every step pattern, the Step
;;;     Attachment verdict and the Liner Material verdict, plus
;;;     totals. The report text is sized from the drawing's extents
;;;     so it sits to scale next to it. Any line describing something
;;;     questionable or that needs looking over (a flagged/wrong
;;;     item, a missing block, a "NOT" find, an "add ..." note, a
;;;     skipped check) is coloured RED in the report; everything
;;;     that checked out stays the report's normal colour.
;;;
;;;  All original colours are restored when the review ends — except
;;;  the red "fix me" dimensions, magenta moved arcs and cyan
;;;  merged/flagged lines, which stay marked on purpose. Everything
;;;  (including the report) runs inside one UNDO group, so a single U
;;;  reverts the whole review.
;;; ------------------------------------------------------------------

(vl-load-com)

;; --- tunables ------------------------------------------------------
(setq *dchk-tol*          1.0e-4)  ; max gap (drawing units) that still counts as attached
(setq *dchk-grey-color*   8)       ; grey used to fade out everything not under review
(setq *dchk-flag-color*   1)       ; red: dimensions you answered "No" to
(setq *dchk-arc-color*    6)       ; magenta: arcs whose endpoints were moved
(setq *dchk-olap-color*   4)       ; cyan: merged or flagged overlapping lines
(setq *dchk-olap-fuzz*    1.0e-4)  ; max sideways offset that still counts as "same line"
(setq *dchk-step-maxgap*  18.0)    ; steps: max tread spacing (drawing units; 18 = 18" when 1 unit = 1")
(setq *dchk-step-minlines* 3)      ; steps: how many stacked parallel lines look like steps
(setq *dchk-step-angtol*  1.0)     ; steps: parallelism tolerance (degrees)
(setq *dchk-bead-layer*   "Bead Track") ; layer bead track must be drawn on
(setq *dchk-bead-dist*    18.0)    ; how close bead track must be to plan-view steps (units)

;; dimension styles are reviewed in this order; styles not listed
;; come afterwards ("whatever else is left"), still left-to-right
(setq *dchk-style-order*
      '("STANDARD" "SIDE STANDARD" "STANDARD INCHES" "CROSS DIMENSIONS"))
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

(defun dchk:nearest-curve (pt exclude cands / best bestd cp d e)
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

(defun dchk:closest-of (pt pts / best bestd d q)
  (foreach q pts
    (setq d (distance pt q))
    (if (or (null bestd) (< d bestd)) (setq bestd d best q)))
  best)

(defun dchk:nearest-end (pt exclude cands / best bestd d e q)
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

(defun dchk:zoom-2ents (e1 e2 / b1 b2 p1 p2 m)
  ;; zoom onto the combined box of two entities
  (setq b1 (dchk:bbox e1)
        b2 (dchk:bbox e2))
  (cond
    ((and b1 b2)
     (setq p1 (list (min (caar b1) (caar b2))
                    (min (cadar b1) (cadar b2)))
           p2 (list (max (caadr b1) (caadr b2))
                    (max (cadadr b1) (cadadr b2)))
           m  (* *dchk-zoom-margin*
                 (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
     (command "_.ZOOM" "_Window"
              (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
              (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))
    (b1 (dchk:zoom-ent e1))
    (b2 (dchk:zoom-ent e2))))

(defun dchk:stage (ent saved keep)
  ;; bring an entity back to its own colour for review — unless it
  ;; already wears a DIMCHECK marker colour it must not lose
  (if (and (entget ent) (not (member ent keep)))
    (dchk:set-color ent (cdr (assoc ent saved)))))

(defun dchk:unstage (ent keep)
  ;; send a reviewed entity back into the grey background
  (if (and (entget ent) (not (member ent keep)))
    (dchk:set-color ent *dchk-grey-color*)))

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

(defun dchk:attn-p (s)
  ;; T when a report line describes something questionable or that
  ;; needs looking over / fixing, so the report renders it in red
  (wcmatch (strcase s)
    "*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO SIDE VIEW*,*NO 'STEP*,*NO BLOCK*,*WORD NOT*,* ADD *"))

(defun dchk:red (s)
  ;; wrap an MTEXT run so it renders in the flag colour, reverting
  ;; to the surrounding colour after (braces scope the change)
  (strcat "{\\C" (itoa *dchk-flag-color*) ";" s "}"))

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

(defun dchk:rebuild-arc (ent which fixed mid target / c r a1 a2 am tmp ed pair)
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

(defun dchk:line-pts (ent / ed)
  ;; a LINE's two endpoints (WCS)
  (setq ed (entget ent))
  (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))

(defun dchk:unit (v / l)
  ;; v scaled to length 1; nil for a (near-)zero vector
  (setq l (distance '(0.0 0.0 0.0) v))
  (if (> l 1e-12)
    (mapcar '(lambda (x) (/ x l)) v)))

(defun dchk:proj-param (p a u)
  ;; signed distance of p along the axis through a with unit dir u
  (apply '+ (mapcar '* (mapcar '- p a) u)))

(defun dchk:axis-pt (a u s)
  ;; the point at parameter s on that axis
  (mapcar '+ a (mapcar '(lambda (x) (* x s)) u)))

(defun dchk:pt-line-dist (p a u / s)
  ;; distance from p to the infinite line through a with unit dir u
  (setq s (dchk:proj-param p a u))
  (distance p (dchk:axis-pt a u s)))

(defun dchk:overlap-info (la lb / pa pb a1 a2 b1 b2 u lena s1 s2 tmp lo hi)
  ;; when LINEs la and lb are collinear (within *dchk-olap-fuzz*) and
  ;; run on top of each other for more than *dchk-tol*, returns
  ;;   (ov-start ov-end ov-length union-start union-end)
  ;; nil when they do not overlap (touching end-to-end is fine)
  (setq pa (dchk:line-pts la)
        a1 (car pa)
        a2 (cadr pa)
        pb (dchk:line-pts lb)
        b1 (car pb)
        b2 (cadr pb)
        u  (dchk:unit (mapcar '- a2 a1)))
  (if (and u
           (<= (dchk:pt-line-dist b1 a1 u) *dchk-olap-fuzz*)
           (<= (dchk:pt-line-dist b2 a1 u) *dchk-olap-fuzz*))
    (progn
      (setq lena (distance a1 a2)
            s1   (dchk:proj-param b1 a1 u)
            s2   (dchk:proj-param b2 a1 u))
      (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
      (setq lo (max 0.0 s1)
            hi (min lena s2))
      (if (> (- hi lo) *dchk-tol*)
        (list (dchk:axis-pt a1 u lo)
              (dchk:axis-pt a1 u hi)
              (- hi lo)
              (dchk:axis-pt a1 u (min 0.0 s1))
              (dchk:axis-pt a1 u (max lena s2)))))))

(defun dchk:merge-lines (la lb info / ed)
  ;; stretch la over the union of both lines, delete lb
  (setq ed (entget la)
        ed (subst (cons 10 (nth 3 info)) (assoc 10 ed) ed)
        ed (subst (cons 11 (nth 4 info)) (assoc 11 ed) ed))
  (entmod ed)
  (entupd la)
  (entdel lb))

;; --- step pattern detection ----------------------------------------

(defun dchk:line-dir-ang (ent / pts a)
  ;; direction of a LINE folded into [0, pi)
  (setq pts (dchk:line-pts ent)
        a   (angle (car pts) (cadr pts)))
  (if (>= a pi) (- a pi) a))

(defun dchk:ang-diff (a b / d)
  ;; distance between two folded directions, in [0, pi/2]
  (setq d (abs (- a b)))
  (min d (- pi d)))

(defun dchk:sort-recs (recs / out r pre rest)
  ;; stable insertion sort by (car rec); keeps equal elements
  (setq out nil)
  (foreach r recs
    (setq pre  nil
          rest out)
    (while (and rest (>= (car r) (caar rest)))
      (setq pre  (cons (car rest) pre)
            rest (cdr rest)))
    (setq out (append (reverse pre) (list r) rest)))
  out)

(defun dchk:step-groups (lns / atol fams a placed recs pts p1 p2 dx dy
                             off s1 s2 tmp cur chains gap groups e fam r)
  ;; hunt for step-like patterns: *dchk-step-minlines* or more
  ;; parallel LINEs stacked less than *dchk-step-maxgap* apart, each
  ;; sideways-overlapping the one before it (like stair treads).
  ;; Returns a list of groups, each (direction-angle ent ent ...)
  ;; ordered bottom tread to top.
  (setq atol   (* *dchk-step-angtol* (/ pi 180.0))
        fams   nil
        groups nil)
  ;; bucket the lines into parallel families
  (foreach e lns
    (if (entget e)
      (progn
        (setq a      (dchk:line-dir-ang e)
              placed nil)
        (foreach fam fams
          (if (and (not placed) (<= (dchk:ang-diff a (car fam)) atol))
            (setq fams   (subst (cons (car fam) (cons e (cdr fam))) fam fams)
                  placed T)))
        (if (not placed)
          (setq fams (cons (list a e) fams))))))
  ;; inside each family, sort by sideways offset and chain the stack
  (foreach fam fams
    (if (>= (length (cdr fam)) *dchk-step-minlines*)
      (progn
        (setq a    (car fam)
              dx   (cos a)
              dy   (sin a)
              recs nil)
        (foreach e (cdr fam)
          (setq pts (dchk:line-pts e)
                p1  (car pts)
                p2  (cadr pts)
                off (- (* (cadr p1) dx) (* (car p1) dy))
                s1  (+ (* (car p1) dx) (* (cadr p1) dy))
                s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
          (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
          (setq recs (cons (list off s1 s2 e) recs)))
        (setq recs (dchk:sort-recs recs))
        ;; cur = (ents distinct-tread-count span-lo span-hi last-off)
        (setq cur nil chains nil)
        (foreach r recs
          (cond
            ((null cur)
             (setq cur (list (list (cadddr r)) 1 (cadr r) (caddr r) (car r))))
            (t
             (setq gap (- (car r) (nth 4 cur)))
             (cond
               ((<= gap *dchk-tol*)           ; same tread drawn in pieces
                (setq cur (list (cons (cadddr r) (car cur))
                                (cadr cur)
                                (min (nth 2 cur) (cadr r))
                                (max (nth 3 cur) (caddr r))
                                (car r))))
               ((and (<= gap *dchk-step-maxgap*)
                     (> (min (nth 3 cur) (caddr r))
                        (max (nth 2 cur) (cadr r)))) ; sideways overlap
                (setq cur (list (cons (cadddr r) (car cur))
                                (1+ (cadr cur))
                                (cadr r)
                                (caddr r)
                                (car r))))
               (t                             ; stack broken
                (if (>= (cadr cur) *dchk-step-minlines*)
                  (setq chains (cons (cons a (reverse (car cur))) chains)))
                (setq cur (list (list (cadddr r)) 1 (cadr r) (caddr r) (car r))))))))
        (if (and cur (>= (cadr cur) *dchk-step-minlines*))
          (setq chains (cons (cons a (reverse (car cur))) chains)))
        (setq groups (append groups (reverse chains))))))
  groups)

(defun dchk:pts-bbox (ents / xs ys pts e p)
  ;; ((minx miny) (maxx maxy)) over the endpoints of a list of LINEs
  (setq xs nil ys nil)
  (foreach e ents
    (if (entget e)
      (progn
        (setq pts (dchk:line-pts e))
        (foreach p pts
          (setq xs (cons (car p) xs)
                ys (cons (cadr p) ys))))))
  (if xs
    (list (list (apply 'min xs) (apply 'min ys))
          (list (apply 'max xs) (apply 'max ys)))))

(defun dchk:boxes-touch (b1 b2 m)
  ;; do two ((minx miny)(maxx maxy)) boxes overlap once grown by m?
  (and b1 b2
       (<= (- (caar b2) m) (caadr b1))
       (<= (- (caar b1) m) (caadr b2))
       (<= (- (cadar b2) m) (cadadr b1))
       (<= (- (cadar b1) m) (cadadr b2))))

(defun dchk:bead-near-p (gbb beadbbs / hit bb)
  ;; is any bead-track box within *dchk-bead-dist* of the group box?
  (setq hit nil)
  (foreach bb beadbbs
    (if (dchk:boxes-touch gbb bb *dchk-bead-dist*)
      (setq hit T)))
  hit)

(defun dchk:zoom-box (bb / p1 p2 m)
  ;; zoom the current view onto a ((minx miny)(maxx maxy)) box
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *dchk-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

;; --- block & text helpers ------------------------------------------

(defun dchk:norm-text (s)
  ;; uppercase, with every non-alphanumeric squashed to a space, so
  ;; word searches ignore case, punctuation and MTEXT format codes
  (if (null s)
    ""
    (vl-list->string
      (mapcar '(lambda (c)
                 (cond
                   ((and (>= c 48) (<= c 57)) c)         ; 0-9
                   ((and (>= c 65) (<= c 90)) c)         ; A-Z
                   ((and (>= c 97) (<= c 122)) (- c 32)) ; a-z -> A-Z
                   (t 32)))
               (vl-string->list s)))))

(defun dchk:block-name (ent / res)
  ;; effective block name (sees through dynamic blocks)
  (setq res (vl-catch-all-apply
              'vla-get-EffectiveName
              (list (vlax-ename->vla-object ent))))
  (if (vl-catch-all-error-p res)
    (cdr (assoc 2 (entget ent)))
    res))

(defun dchk:ins-texts (ent / ed lst e et g)
  ;; every piece of text an INSERT shows: its attribute values plus
  ;; TEXT/MTEXT/ATTDEF inside the block definition (one level deep)
  (setq ed  (entget ent)
        lst nil)
  (if (= 1 (cdr (assoc 66 ed)))               ; attributes follow
    (progn
      (setq e (entnext ent))
      (while (and e (= "ATTRIB" (cdr (assoc 0 (entget e)))))
        (setq lst (cons (cdr (assoc 1 (entget e))) lst)
              e   (entnext e)))))
  (setq e (tblobjname "BLOCK" (cdr (assoc 2 ed))))
  (if e
    (progn
      (setq e (entnext e))
      (while (and e (/= "ENDBLK" (setq et (cdr (assoc 0 (entget e))))))
        (cond
          ((member et '("TEXT" "ATTDEF"))
           (setq lst (cons (cdr (assoc 1 (entget e))) lst)))
          ((= et "MTEXT")
           (foreach g (entget e)
             (if (member (car g) '(1 3))
               (setq lst (cons (cdr g) lst))))))
        (setq e (entnext e)))))
  lst)

(defun dchk:ins-matches (ent phrase / pat found s)
  ;; T when the INSERT's (effective) name or any text it shows
  ;; contains the phrase, ignoring case and punctuation
  (setq pat   (strcat "*" (dchk:norm-text phrase) "*")
        found (wcmatch (dchk:norm-text (dchk:block-name ent)) pat))
  (foreach s (dchk:ins-texts ent)
    (if (wcmatch (dchk:norm-text s) pat)
      (setq found T)))
  found)

(defun dchk:has-word-not (ent / found s)
  ;; T when any text the INSERT shows contains the standalone word
  ;; NOT ("Not Selected", "NOT INCLUDED", ... but never "NOTE")
  (setq found nil)
  (foreach s (dchk:ins-texts ent)
    (if (wcmatch (strcat " " (dchk:norm-text s) " ") "* NOT *")
      (setq found T)))
  found)

;; --- dimension review ----------------------------------------------

(defun dchk:dim-style (ent / s)
  ;; the dimension's style name, "" when it has none
  (setq s (cdr (assoc 3 (entget ent))))
  (if s s ""))

(defun dchk:style-rank (style / i r s)
  ;; position of the style in *dchk-style-order* (exact name match,
  ;; case-blind); unlisted styles land after every listed one
  (setq style (strcase style)
        i     0
        r     nil)
  (foreach s *dchk-style-order*
    (if (and (null r) (= (strcase s) style)) (setq r i))
    (setq i (1+ i)))
  (if r r (length *dchk-style-order*)))

(defun dchk:ent-center (ent / bb)
  ;; (x y) centre of the entity's box; falls back to its group-10 point
  (setq bb (dchk:bbox ent))
  (if bb
    (list (* 0.5 (+ (caar bb) (caadr bb)))
          (* 0.5 (+ (cadar bb) (cadadr bb))))
    (progn
      (setq bb (cdr (assoc 10 (entget ent))))
      (if bb (list (car bb) (cadr bb)) (list 0.0 0.0)))))

(defun dchk:dim-order-p (r1 r2 rowtol)
  ;; strict "r1 reviews before r2" for recs (rank cx cy ent):
  ;; style rank first, then row (higher = earlier), then left first
  (cond
    ((< (car r1) (car r2)) T)
    ((> (car r1) (car r2)) nil)
    ((> (- (caddr r1) (caddr r2)) rowtol) T)   ; r1 sits a row above
    ((> (- (caddr r2) (caddr r1)) rowtol) nil) ; r2 sits a row above
    (t (< (cadr r1) (cadr r2)))))              ; same row: left first

(defun dchk:sort-dims (dims rowtol / recs cen r out pre rest e)
  ;; stable insertion sort into review order
  (setq recs nil)
  (foreach e dims
    (setq cen  (dchk:ent-center e)
          recs (cons (list (dchk:style-rank (dchk:dim-style e))
                           (car cen) (cadr cen) e)
                     recs)))
  (setq recs (reverse recs)
        out  nil)
  (foreach r recs
    (setq pre  nil
          rest out)
    (while (and rest (not (dchk:dim-order-p r (car rest) rowtol)))
      (setq pre  (cons (car rest) pre)
            rest (cdr rest)))
    (setq out (append (reverse pre) (list r) rest)))
  (mapcar '(lambda (r) (nth 3 r)) out))

(defun dchk:dim-meas (ent / ed dtype p13 p14 ang v meas)
  ;; the dimension's current measurement as display text, formatted
  ;; with the drawing's unit settings (LUNITS/AUNITS); nil if unknown.
  ;; Linear/aligned dims are recomputed from their definition points
  ;; so the value reflects any point that was just moved.
  (setq ed    (entget ent)
        dtype (logand 7 (cdr (assoc 70 ed)))
        meas  (cdr (assoc 42 ed)))            ; stored actual measurement
  (cond
    ((= dtype 1)                              ; aligned: point-to-point
     (setq p13 (cdr (assoc 13 ed))
           p14 (cdr (assoc 14 ed)))
     (if (and p13 p14) (rtos (distance p13 p14))))
    ((= dtype 0)                              ; rotated/linear: project the
     (setq p13 (cdr (assoc 13 ed))            ; points onto the dim direction
           p14 (cdr (assoc 14 ed))
           ang (cdr (assoc 50 ed)))
     (if (and p13 p14)
       (progn
         (if (null ang) (setq ang 0.0))
         (setq v (mapcar '- p14 p13))
         (rtos (abs (+ (* (car v) (cos ang))
                       (* (cadr v) (sin ang))))))))
    ((member dtype '(2 5))                    ; angular: show the angle
     (if (and meas (>= meas 0.0)) (angtos meas)))
    (t                                        ; radius/diameter/ordinate
     (if (and meas (>= meas 0.0)) (rtos meas)))))

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

(defun dchk:review-dim (ent cands num total / ed dtype h sty p13 p14 r1 r2 moved ok note meas)
  ;; interactive review of one dimension.
  ;; Returns (handle ok-flag report-note moved-point-count measurement).
  (setq ed    (entget ent)
        h     (cdr (assoc 5 ed))
        sty   (dchk:dim-style ent)
        dtype (logand 7 (cdr (assoc 70 ed))))
  (dchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nDimension " (itoa num) " of " (itoa total)
                 " (handle " h
                 (if (= sty "") "" (strcat ", style " sty))
                 ")"))
  (if (member dtype '(0 1))                   ; rotated/linear or aligned
    (progn
      (setq p13 (cdr (assoc 13 ed))           ; the two dimmed points
            p14 (cdr (assoc 14 ed))
            r1  (dchk:audit-dim-point ent 13 "dimension point 1" cands)
            r2  (dchk:audit-dim-point ent 14 "dimension point 2" cands))
      (if (or r1 r2)
        (dchk:make-xline p13 p14))))          ; through the ORIGINAL points
  (setq moved (append (if r1 (list r1)) (if r2 (list r2))))
  (setq meas (dchk:dim-meas ent))             ; after any point moves
  (if meas (princ (strcat "\n  Measures " meas ".")))
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
  (list h ok note (length moved) meas))

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

;; --- overlapping line review ---------------------------------------

(defun dchk:review-olap (la lb num total / info h1 h2 lay1 lay2 label ans)
  ;; interactive review of one overlapping LINE pair.
  ;; Returns nil when the pair no longer overlaps (an earlier merge
  ;; absorbed it); otherwise (label report-note action ents...) where
  ;; action is merged / flagged / left and ents keep their cyan.
  (if (and (entget la) (entget lb) (setq info (dchk:overlap-info la lb)))
    (progn
      (setq h1    (cdr (assoc 5 (entget la)))
            h2    (cdr (assoc 5 (entget lb)))
            lay1  (cdr (assoc 8 (entget la)))
            lay2  (cdr (assoc 8 (entget lb)))
            label (strcat h1 "+" h2 " (overlap " (rtos (caddr info)) ")"))
      (dchk:zoom-2ents la lb)
      (redraw la 3)
      (redraw lb 3)
      (dchk:mark-point (car info))
      (dchk:mark-point (cadr info))
      (princ (strcat "\n\nOverlap " (itoa num) " of " (itoa total)
                     ": lines " h1 " + " h2
                     " run on top of each other for " (rtos (caddr info)) "."))
      (initget "Merge Flag Leave")
      (setq ans (getkword
                  "\n  Merge into one line, Flag to fix, or Leave as is? [Merge/Flag/Leave] <Merge>: "))
      (if (null ans) (setq ans "Merge"))
      (redraw la 4)
      (redraw lb 4)
      (redraw)
      (cond
        ((and (= ans "Merge") (= (strcase lay1) (strcase lay2)))
         (dchk:merge-lines la lb info)
         (dchk:set-color la *dchk-olap-color*)
         (princ "\n  Merged into one line (cyan).")
         (list label "merged into one line (cyan)" 'merged la))
        ((= ans "Merge")
         (dchk:set-color la *dchk-olap-color*)
         (dchk:set-color lb *dchk-olap-color*)
         (princ (strcat "\n  Lines sit on different layers (" lay1 " / " lay2
                        ") - flagged to fix (cyan) instead of merging."))
         (list label "different layers - flagged to fix (cyan)" 'flagged la lb))
        ((= ans "Flag")
         (dchk:set-color la *dchk-olap-color*)
         (dchk:set-color lb *dchk-olap-color*)
         (princ "\n  Flagged to fix (cyan).")
         (list label "flagged to fix (cyan)" 'flagged la lb))
        (t
         (princ "\n  Left as drawn.")
         (list label "left as drawn" 'left))))))

;; --- command -------------------------------------------------------

(defun c:DIMCHECK ( / *error* oldecho vc vs undo-open ss i e et
                      cands dims arcs lns blks olaps rest e1 e2 pr
                      saved keep res n total lines ans
                      ndok ndflag ndmoved naok namoved nasnap
                      nomerged noflag noleft
                      sgroups svgroups pgroups g1 g2 stepsp svmode
                      satts attwrong liners linernot bn bh bp
                      bgroups beadneed beadok beadmiss beadss beadbbs gbb
                      stepsum linersum rowtol sty g b l pair hdr
                      minx miny maxx maxy bb h m ins txt nlin ref)

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
     (setq cands nil dims nil arcs nil lns nil blks nil
           saved nil keep nil lines nil i 0
           ndok 0 ndflag 0 ndmoved 0 naok 0 namoved 0 nasnap 0
           nomerged 0 noflag 0 noleft 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (= et "LINE") (setq lns (cons e lns)))
       (if (= et "INSERT") (setq blks (cons e blks)))
       (if (member et *dchk-curve-types*) (setq cands (cons e cands))))
     (setq dims  (reverse dims)
           arcs  (reverse arcs)
           lns   (reverse lns)
           blks  (reverse blks)
           cands (reverse cands))
     (cond
       ((and (null dims) (null arcs) (< (length lns) 2) (null blks))
        (prompt "\nSelection holds no dimensions, arcs, lines, or blocks to check - nothing to do."))
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

        ;; march order for the dimensions: style groups first
        ;; (*dchk-style-order*), then row by row, left to right
        (setq rowtol (if (and miny maxy (> (- maxy miny) 1e-8))
                       (* 0.05 (- maxy miny))
                       1.0))
        (setq dims (dchk:sort-dims dims rowtol))

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
          (setq sty (dchk:dim-style e))
          (setq lines (cons (strcat "Dim " (car res)
                                    (if (= sty "") "" (strcat " [" sty "]"))
                                    (if (nth 4 res)
                                      (strcat " = " (nth 4 res))
                                      "")
                                    ": " (caddr res))
                            lines)))

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

        ;; --- overlapping lines, one pair at a time ------------------
        (setq olaps nil
              rest  lns)
        (while rest
          (setq e1   (car rest)
                rest (cdr rest))
          (foreach e2 rest
            (if (dchk:overlap-info e1 e2)
              (setq olaps (cons (list e1 e2) olaps)))))
        (setq olaps (reverse olaps))
        (if olaps
          (princ (strcat "\n--- Reviewing " (itoa (length olaps))
                         " overlapping line pair(s): Enter = merge, F = flag, L = leave ---")))
        (setq n 0 total (length olaps))
        (foreach pr olaps
          (setq n (1+ n))
          (dchk:stage (car pr) saved keep)
          (dchk:stage (cadr pr) saved keep)
          (setq res (dchk:review-olap (car pr) (cadr pr) n total))
          (cond
            ((null res)                       ; absorbed by an earlier merge
             (dchk:unstage (car pr) keep)
             (dchk:unstage (cadr pr) keep))
            ((eq (caddr res) 'left)
             (setq noleft (1+ noleft))
             (dchk:unstage (car pr) keep)
             (dchk:unstage (cadr pr) keep)
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))
            (t
             (if (eq (caddr res) 'merged)
               (setq nomerged (1+ nomerged))
               (setq noflag (1+ noflag)))
             (setq keep (append (cdddr res) keep))
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))))

        ;; --- step / staircase check ---------------------------------
        (setq sgroups  (dchk:step-groups lns)
              svgroups nil
              stepsp   nil
              svmode   nil
              satts    nil
              attwrong nil
              bgroups  nil)
        ;; a staircase side view reads as two step patterns at right
        ;; angles to each other (treads + risers) in the same spot
        (setq rest sgroups)
        (while rest
          (setq g1 (car rest))
          (foreach g2 (cdr rest)
            (if (and (> (dchk:ang-diff (car g1) (car g2)) (- (* 0.5 pi) 0.09))
                     (dchk:boxes-touch (dchk:pts-bbox (cdr g1))
                                       (dchk:pts-bbox (cdr g2))
                                       *dchk-step-maxgap*))
              (progn
                (if (not (member g1 svgroups)) (setq svgroups (cons g1 svgroups)))
                (if (not (member g2 svgroups)) (setq svgroups (cons g2 svgroups))))))
          (setq rest (cdr rest)))
        (setq pgroups (vl-remove-if '(lambda (g) (member g svgroups)) sgroups))
        (cond
          (svgroups                           ; staircase drawing found
           (setq stepsp  T
                 svmode  'auto
                 bgroups pgroups)             ; plan-view patterns
           (princ "\n--- Step check: staircase side view detected in the selection ---")
           (setq lines (cons (strcat "Steps: staircase side view detected ("
                                     (itoa (length svgroups)) " step pattern(s))")
                             lines))
           (foreach g pgroups
             (setq lines (cons (strcat "Steps: pattern of " (itoa (length (cdr g)))
                                       " parallel lines (side view already present)")
                               lines))))
          (pgroups                            ; possible steps, no staircase drawing
           (princ (strcat "\n--- Step check: " (itoa (length pgroups))
                          " possible step pattern(s), no staircase side view found ---"))
           (setq n 0 total (length pgroups))
           (foreach g pgroups
             (setq n (1+ n))
             (foreach e (cdr g) (dchk:stage e saved keep))
             (dchk:zoom-box (dchk:pts-bbox (cdr g)))
             (foreach e (cdr g) (if (entget e) (redraw e 3)))
             (princ (strcat "\n\nStep pattern " (itoa n) " of " (itoa total) ": "
                            (itoa (length (cdr g)))
                            " parallel lines stacked less than "
                            (rtos *dchk-step-maxgap*) " apart."))
             (setq ans (dchk:ask-yn "\n  Are these lines steps?"))
             (foreach e (cdr g) (if (entget e) (redraw e 4)))
             (foreach e (cdr g) (dchk:unstage e keep))
             (redraw)
             (if ans
               (setq stepsp  T
                     bgroups (cons g bgroups)))
             (setq lines (cons (strcat "Steps: pattern of " (itoa (length (cdr g)))
                                       " parallel lines - "
                                       (if ans "CONFIRMED as steps" "not steps"))
                               lines)))))
        (if stepsp
          (progn
            (if (null svmode)                 ; steps confirmed, no side view seen
              (progn
                (princ "\n  Steps confirmed but no staircase side view was detected.")
                (if (dchk:ask-yn "\n  Is a side view of the steps drawn somewhere?")
                  (setq svmode 'user))))
            (if (null svmode)
              (progn
                (princ "\n  Note: ADD A SIDE VIEW of the steps.")
                (setq lines (cons "Steps: NO SIDE VIEW - add a side view of the steps"
                                  lines)))
              (progn                          ; side view present: demand the block
                (setq satts (vl-remove-if-not
                              '(lambda (b) (dchk:ins-matches b "Step Attachment"))
                              blks))
                (if (null satts)
                  (progn
                    (princ "\n  Note: no 'Step Attachment' block found - add one.")
                    (setq lines (cons "Steps: side view present but NO 'Step Attachment' block - add one"
                                      lines)))
                  (foreach b satts
                    (dchk:stage b saved keep)
                    (dchk:zoom-ent b)
                    (redraw b 3)
                    (setq ans (dchk:ask-yn
                                (strcat "\n  Step Attachment block "
                                        (cdr (assoc 5 (entget b)))
                                        " - is the correct one placed?")))
                    (redraw b 4)
                    (redraw)
                    (if ans
                      (progn
                        (dchk:unstage b keep)
                        (setq lines (cons (strcat "Step Attachment "
                                                  (cdr (assoc 5 (entget b)))
                                                  ": confirmed correct")
                                          lines)))
                      (progn
                        (setq attwrong T)
                        (dchk:set-color b *dchk-flag-color*)
                        (setq keep (cons b keep))
                        (setq lines (cons (strcat "Step Attachment "
                                                  (cdr (assoc 5 (entget b)))
                                                  ": WRONG ONE - flagged to fix (red)")
                                          lines))))))))))

        ;; --- Bead Track check (bead step attachments only) ----------
        ;; when the attachment style is "Bead Step Attachment", each
        ;; plan-view step pattern needs bead track drawn nearby; the
        ;; side view is exempt. The WHOLE drawing is searched, not
        ;; just the selection.
        (setq beadneed nil beadok 0 beadmiss 0)
        (if (and satts
                 bgroups
                 (vl-some '(lambda (b) (dchk:ins-matches b "Bead Step Attachment"))
                          satts))
          (progn
            (setq beadneed T)
            (princ (strcat "\n--- Bead Track check: attachment style is 'Bead Step Attachment' ---"))
            (setq beadss  (ssget "_X" (list (cons 8 *dchk-bead-layer*)))
                  beadbbs nil
                  i       0)
            (if beadss
              (repeat (sslength beadss)
                (setq bb (dchk:bbox (ssname beadss i))
                      i  (1+ i))
                (if bb (setq beadbbs (cons bb beadbbs)))))
            (foreach g bgroups
              (setq gbb (dchk:pts-bbox (cdr g)))
              (if (and gbb beadbbs (dchk:bead-near-p gbb beadbbs))
                (progn
                  (setq beadok (1+ beadok))
                  (setq lines (cons (strcat "Bead Track: present near step pattern of "
                                            (itoa (length (cdr g))) " lines")
                                    lines)))
                (progn
                  (setq beadmiss (1+ beadmiss))
                  (princ (strcat "\n  Note: nothing on layer '" *dchk-bead-layer*
                                 "' near a step pattern - add bead track."))
                  (setq lines (cons (strcat "Bead Track: NOTHING on layer '"
                                            *dchk-bead-layer*
                                            "' near step pattern of "
                                            (itoa (length (cdr g)))
                                            " lines - add bead track")
                                    lines)))))))

        ;; --- Liner Material check -----------------------------------
        (setq liners   (vl-remove-if-not
                         '(lambda (b) (dchk:ins-matches b "Liner Material"))
                         blks)
              linernot nil)
        (if (null liners)
          (progn
            (princ "\n--- Liner check: no 'Liner Material' block in the selection ---")
            (setq lines (cons "Liner Material: NO block found - add 'Liner Material' or 'Liner Material with Step'"
                              lines)))
          (progn
            (princ (strcat "\n--- Liner check: " (itoa (length liners))
                           " 'Liner Material' block(s) found ---"))
            (foreach b liners
              (setq bn (dchk:block-name b)
                    bh (cdr (assoc 5 (entget b)))
                    bp (cdr (assoc 10 (entget b))))
              (if (dchk:has-word-not b)
                (progn
                  (setq linernot T)
                  (setq lines (cons (strcat "Liner Material (" bn ") " bh " at "
                                            (dchk:ptstr bp)
                                            ": contains the word NOT - look at it")
                                    lines)))
                (setq lines (cons (strcat "Liner Material (" bn ") " bh ": OK")
                                  lines))))))

        ;; --- restore colours (flagged/moved keep theirs) ------------
        (foreach pair saved
          (if (and (not (member (car pair) keep)) (entget (car pair)))
            (dchk:set-color (car pair) (cdr pair))))

        ;; --- one-line verdicts for steps & liner --------------------
        (setq stepsum
              (cond
                ((null sgroups) "no step patterns detected")
                ((not stepsp)
                 (strcat (itoa (length sgroups))
                         " pattern(s) reviewed - none are steps"))
                (t
                 (strcat "steps present; side view "
                         (cond ((eq svmode 'auto) "detected")
                               ((eq svmode 'user) "confirmed by user")
                               (t "MISSING - add one"))
                         (cond ((null svmode) "")
                               ((null satts)
                                "; Step Attachment block MISSING - add one")
                               (attwrong
                                "; Step Attachment flagged WRONG (red)")
                               (t "; Step Attachment confirmed"))
                         (cond ((not beadneed) "")
                               ((> beadmiss 0)
                                (strcat "; Bead Track MISSING near "
                                        (itoa beadmiss) " pattern(s)"))
                               (t "; Bead Track present"))))))
        (setq linersum
              (cond
                ((null liners)
                 "block MISSING - add 'Liner Material' (or 'with Step')")
                (linernot
                 (strcat (itoa (length liners))
                         " block(s) found; word NOT found - review"))
                (t (strcat (itoa (length liners)) " block(s) found - OK"))))

        ;; --- report on the right side, to scale with the drawing ----
        ;; text height picked from the drawing's extents so the whole
        ;; report roughly matches the drawing's height (MTEXT line
        ;; spacing is ~1.66 x text height), clamped so a short report
        ;; is not gigantic nor a long one unreadably small
        (setq nlin (+ 7 (length lines)))
        (if (and minx (> (max (- maxy miny) (- maxx minx)) 1e-8))
          (progn
            (setq ref (max (- maxy miny) (* 0.25 (- maxx minx)))
                  h   (/ ref (* 1.66 nlin)))
            (if (> h (/ ref 30.0))  (setq h (/ ref 30.0)))
            (if (< h (/ ref 200.0)) (setq h (/ ref 200.0))))
          (progn
            (setq h (* (getvar "DIMTXT") (getvar "DIMSCALE")))
            (if (or (null h) (<= h 0.0)) (setq h 2.5))))
        (setq ins (if minx
                    (list (+ maxx (* 0.05 (max (- maxx minx) 1.0))) maxy 0.0)
                    (list 0.0 0.0 0.0)))
        ;; header dashboard: each line carries a "needs attention" flag
        ;; so a category with anything to look over turns red
        (setq hdr
          (list
            (cons (strcat "Dimensions checked: " (itoa (length dims))
                          " (correct: " (itoa ndok)
                          ", flagged to fix: " (itoa ndflag)
                          ", points adjusted: " (itoa ndmoved) ")")
                  (> ndflag 0))
            (cons (strcat "Arcs checked: " (itoa (length arcs))
                          " (OK: " (itoa naok)
                          ", with endpoints moved: " (itoa namoved)
                          ", endpoints moved in total: " (itoa nasnap) ")")
                  (> namoved 0))
            (cons (strcat "Overlapping line pairs: " (itoa (length olaps))
                          (if olaps
                            (strcat " (merged: " (itoa nomerged)
                                    ", flagged: " (itoa noflag)
                                    ", left as drawn: " (itoa noleft) ")")
                            " - none found"))
                  (> noflag 0))
            (cons (strcat "Steps: " stepsum)          (dchk:attn-p stepsum))
            (cons (strcat "Liner Material: " linersum) (dchk:attn-p linersum))))
        (setq txt (strcat "DIMCHECK REPORT - " (dchk:datestr)
                          "\\PItems needing attention are shown in "
                          (dchk:red "red") "."))
        (foreach pr hdr
          (setq txt (strcat txt "\\P"
                            (if (cdr pr) (dchk:red (car pr)) (car pr)))))
        (setq txt (strcat txt "\\P----------------------------------------"))
        (foreach l (reverse lines)
          (setq txt (strcat txt "\\P" (if (dchk:attn-p l) (dchk:red l) l))))
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
                       "\nOverlapping lines: " (itoa (length olaps)) " pair(s) found"
                       (if olaps
                         (strcat ", " (itoa nomerged) " merged, "
                                 (itoa noflag) " flagged (cyan), "
                                 (itoa noleft) " left as drawn")
                         "")
                       "\nSteps: " stepsum
                       "\nLiner Material: " linersum
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
