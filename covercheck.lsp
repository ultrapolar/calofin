;;; ------------------------------------------------------------------
;;;  covercheck.lsp — COVERCHECK: interactive dimension & arc QA review
;;;
;;;  Based on dimcheck.lsp (DIMCHECK), reworked into the cover
;;;  review: the same guided, one-at-a-time audit of dimensions,
;;;  arcs and overlapping lines, with COVER's own rules in place of
;;;  DIMCHECK's step, wall-height and liner checks.
;;;  Type COVERCHECK, then:
;;;
;;;  1. You are asked to highlight the drawing (any selection).
;;;     Everything selected is greyed out so only the item under
;;;     review stands out.
;;;
;;;  2. Dimensions are reviewed ONE AT A TIME, in a fixed marching
;;;     order: grouped by dimension style — "STANDARD", then "SIDE
;;;     STANDARD", then "STANDARD INCHES", then "CROSS DIMENSIONS",
;;;     then whatever styles are left (tune *cchk-style-order*) —
;;;     and inside each group left to right, top to bottom (row by
;;;     row, like reading). Each dimension is zoomed to, shown in
;;;     its own colour and highlighted while the rest stays grey.
;;;     For linear/aligned dimensions the two definition points are
;;;     audited first: a point that does not sit on any object is
;;;     shown where COVERCHECK thinks it belongs, with BOTH spots
;;;     marked on screen and spelled out so there is no doubt which
;;;     is which —
;;;         a RED X   where you drew it,
;;;         a GREEN + where we would move it, joined by a line.
;;;     You then choose, one point at a time:
;;;         Enter / M  ->  MOVE it onto the nearest object (green +)
;;;         K          ->  KEEP it exactly where you drew it (red X);
;;;                        the point is put back and nothing changes
;;;         P          ->  PICK the spot yourself
;;;     A construction line (XLINE) is drawn through the dimension's
;;;     original points on layer COVERCHECK-CONSTRUCTION so you can see
;;;     where it used to measure — only when a point actually moved.
;;;     Then the overall question for every dimension:
;;;         "Is this dimension correct?"
;;;         Enter / Y  ->  correct, the dimension is left alone
;;;         N          ->  the dimension is recoloured RED so it is
;;;                        easy to find and fix afterwards
;;;
;;;  3. Arcs are reviewed the same way, one endpoint at a time, with
;;;     the same Move / Keep / Pick choice. An endpoint not attached
;;;     to the end of another object is snapped there and both spots
;;;     are marked; Keep puts the arc back exactly as you drew it
;;;     (its original shape is restored, not re-fitted), Pick re-fits
;;;     it through your spot. Arcs whose endpoints actually changed
;;;     are recoloured MAGENTA — an arc you kept is left alone.
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
;;;  5. COVER-SPECIFIC CHECKS — to be added. COVERCHECK follows the
;;;     same shape as DIMCHECK but its own rules: the step /
;;;     staircase, Tech Title wall-height and Liner Material checks
;;;     are deliberately NOT part of it.
;;;
;;;  6. A COVERCHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;     drawing on layer COVERCHECK-REPORT listing every dimension —
;;;     with its measured distance (in the drawing's units; angular
;;;     dims show their angle) — every arc and every overlapping line
;;;     pair (with its overlap length), plus
;;;     totals. The report text is sized from the drawing's extents
;;;     so it sits to scale next to it. Any line describing something
;;;     questionable or that needs looking over (a flagged/wrong
;;;     item, a missing block, a "NOT" find, an "add ..." note, a
;;;     skipped check) is coloured RED in the report; everything
;;;     that checked out stays the report's normal colour and is
;;;     drawn at *cchk-green-scale* (3/4) of the red text's height,
;;;     so the problems are the big lines on the sheet.
;;;
;;;  All original colours are restored when the review ends — except
;;;  the red "fix me" dimensions, magenta moved arcs and cyan
;;;  merged/flagged lines, which stay marked on purpose. Everything
;;;  (including the report) runs inside one UNDO group, so a single U
;;;  reverts the whole review.
;;;
;;;  SAFETY NETS
;;;  - Locked layers in the selection are announced up front with an
;;;    offer to unlock for the run (re-locked afterwards, even on
;;;    error); left locked, their items are reported but untouched.
;;;  - Object-associative dimensions are warned about before their
;;;    points are moved — an associative point may re-anchor on its
;;;    own — and their report line says so in red.
;;;  - Rerunning COVERCHECK replaces the previous report and marker
;;;    lines instead of stacking a second copy on top.
;;;  - Original colours are stashed in xdata before greying. If a
;;;    crash or kill ever leaves the drawing grey, COVERCHECKRESCUE
;;;    restores every stashed colour and clears COVERCHECK's report
;;;    and markers (flag colours included — it is the full reset).
;;; ------------------------------------------------------------------

(vl-load-com)

;; --- tunables ------------------------------------------------------
(setq *cchk-tol*          1.0e-4)  ; max gap (drawing units) that still counts as attached
(setq *cchk-grey-color*   8)       ; grey used to fade out everything not under review
(setq *cchk-flag-color*   1)       ; red: dimensions you answered "No" to
(setq *cchk-arc-color*    6)       ; magenta: arcs whose endpoints were moved
(setq *cchk-olap-color*   4)       ; cyan: merged or flagged overlapping lines
(setq *cchk-olap-fuzz*    1.0e-4)  ; max sideways offset that still counts as "same line"

;; dimension styles are reviewed in this order; styles not listed
;; come afterwards ("whatever else is left"), still left-to-right
(setq *cchk-style-order*
      '("STANDARD" "SIDE STANDARD" "STANDARD INCHES" "CROSS DIMENSIONS"))
(setq *cchk-constr-layer* "COVERCHECK-CONSTRUCTION")
(setq *cchk-constr-color* 2)       ; yellow
(setq *cchk-green-scale*  0.75)    ; report: all-clear text height, as a fraction of the red text
(setq *cchk-block-depth*  3)       ; how many levels of nested blocks to search for names/text
(setq *cchk-orig-color*   1)       ; red X: where you drew the point
(setq *cchk-sugg-color*   3)       ; green +: where COVERCHECK would move it
(setq *cchk-report-layer* "COVERCHECK-REPORT")
(setq *cchk-report-color* 3)       ; green
(setq *cchk-zoom-margin*  0.75)    ; empty space around the zoomed item (fraction of its size)
(setq *cchk-report-chars* 45.0)    ; report column width, in text heights
(setq *cchk-ask-all-arc-ends* nil) ; T = confirm EVERY arc endpoint, even already-attached ones

;; entity types dimension points and arc ends may attach to
(setq *cchk-curve-types*
      '("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"))

;; --- safety: xdata tags, colour stash, layer locks -----------------

(defun cchk:regapp ()
  (if (not (tblsearch "APPID" "COVERCHECK"))
    (regapp "COVERCHECK")))

(defun cchk:xd (ent / g)
  ;; COVERCHECK's xdata groups on ent, nil when none
  (setq g (assoc -3 (entget ent '("COVERCHECK"))))
  (if g (cdadr g)))

(defun cchk:tag (ent kind / ed)
  ;; stamp a COVERCHECK-created entity (report, marker line) so a rerun
  ;; or COVERCHECKRESCUE can find and clear it
  (cchk:regapp)
  (setq ed (entget ent '("COVERCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "COVERCHECK" (cons 1000 kind))))))))

(defun cchk:stash-color (ent col / ed)
  ;; remember the entity's own colour in xdata so COVERCHECKRESCUE can
  ;; put it back even after a crash; an existing stash (from an
  ;; interrupted run - the TRUE original) is never overwritten
  (cchk:regapp)
  (setq ed (entget ent '("COVERCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "COVERCHECK"
                                            '(1000 . "COLOR")
                                            (cons 1071 col))))))))

(defun cchk:unstash (ent / ed)
  ;; drop COVERCHECK's xdata once the run has restored things itself
  (setq ed (entget ent '("COVERCHECK")))
  (if (and ed (assoc -3 ed))
    (entmod (subst (list -3 (list "COVERCHECK")) (assoc -3 ed) ed))))

(defun cchk:clear-old (/ ss2 i e xd n)
  ;; erase the report and marker lines left by an earlier COVERCHECK
  ;; run, so a rerun replaces them instead of stacking on top
  (setq ss2 (ssget "_X" '((-3 ("COVERCHECK")))) n 0 i 0)
  (if ss2
    (repeat (sslength ss2)
      (setq e  (ssname ss2 i)
            i  (1+ i)
            xd (cchk:xd e))
      (if (member (cdr (assoc 1000 xd)) '("REPORT" "XLINE"))
        (progn (entdel e) (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\n(Removed " (itoa n)
                   " report/marker item(s) from an earlier COVERCHECK run.)"))))

(defun cchk:layer-locked-p (name / ld)
  (setq ld (tblsearch "LAYER" name))
  (and ld (= 4 (logand 4 (cdr (assoc 70 ld))))))

(defun cchk:set-layer-lock (name lock / ed old new)
  ;; set or clear a layer's locked flag; T when it actually changed
  (setq ed  (entget (tblobjname "LAYER" name))
        old (cdr (assoc 70 ed))
        new (if lock (logior old 4) (logand old (~ 4))))
  (if (/= old new)
    (progn (entmod (subst (cons 70 new) (assoc 70 ed) ed)) T)))

(defun cchk:dim-assoc-p (ent / found g)
  ;; T when the dimension carries persistent reactors - the mark of
  ;; an object-associative dim, whose definition points may re-anchor
  ;; on their own after being moved
  (foreach g (entget ent)
    (if (and (= 102 (car g)) (= "{ACAD_REACTORS" (cdr g)))
      (setq found T)))
  found)

(defun c:COVERCHECKRESCUE ( / ss i e xd n)
  ;; the way out after a crash or interrupted run: puts back every
  ;; colour COVERCHECK stashed (flag colours included) and removes its
  ;; report and marker lines
  (setq ss (ssget "_X" '((-3 ("COVERCHECK")))) n 0 i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            xd (cchk:xd e))
      (cond
        ((member (cdr (assoc 1000 xd)) '("REPORT" "XLINE"))
         (entdel e)
         (setq n (1+ n)))
        ((assoc 1071 xd)
         (cchk:set-color e (cdr (assoc 1071 xd)))
         (cchk:unstash e)
         (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\nCOVERCHECKRESCUE: restored or removed " (itoa n) " item(s)."))
    (princ "\nCOVERCHECKRESCUE: nothing to restore - no COVERCHECK markers in the drawing."))
  (princ))

;; --- small helpers -------------------------------------------------

(defun cchk:ensure-layer (name color)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   '(70 . 0)
                   (cons 62 color)))))

(defun cchk:ent-color (ent / c)
  ;; the entity's explicit colour, 256 (ByLayer) when it has none
  (setq c (cdr (assoc 62 (entget ent))))
  (if c c 256))

(defun cchk:set-color (ent color / ed old)
  (setq ed  (entget ent)
        old (assoc 62 ed))
  (entmod (if old
            (subst (cons 62 color) old ed)
            (append ed (list (cons 62 color)))))
  (entupd ent))

(defun cchk:make-xline (p1 p2 / len)
  ;; infinite construction line through p1-p2 on the check layer,
  ;; tagged so reruns and COVERCHECKRESCUE can clear it
  (setq len (distance p1 p2))
  (if (and (> len 1e-8)
           (entmake (list '(0 . "XLINE")
                          '(100 . "AcDbEntity")
                          (cons 8 *cchk-constr-layer*)
                          '(100 . "AcDbXline")
                          (cons 10 p1)
                          (cons 11 (mapcar '(lambda (x) (/ x len))
                                           (mapcar '- p2 p1))))))
    (cchk:tag (entlast) "XLINE")))

(defun cchk:closest-on (ent pt / res)
  ;; closest point on ent to pt; nil when ent is not curve-like
  (setq res (vl-catch-all-apply 'vlax-curve-getClosestPointTo (list ent pt)))
  (if (vl-catch-all-error-p res) nil res))

(defun cchk:nearest-curve (pt exclude cands / best bestd cp d e)
  ;; (ent closest-point distance) for the candidate closest to pt
  (foreach e cands
    (if (and (not (eq e exclude)) (setq cp (cchk:closest-on e pt)))
      (progn
        (setq d (distance pt cp))
        (if (or (null bestd) (< d bestd))
          (setq bestd d
                best  (list e cp d))))))
  best)

(defun cchk:curve-ends (ent / cl sp ep)
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

(defun cchk:closest-of (pt pts / best bestd d q)
  (foreach q pts
    (setq d (distance pt q))
    (if (or (null bestd) (< d bestd)) (setq bestd d best q)))
  best)

(defun cchk:nearest-end (pt exclude cands / best bestd d e q)
  ;; closest endpoint over every open candidate curve
  (foreach e cands
    (if (not (eq e exclude))
      (foreach q (cchk:curve-ends e)
        (setq d (distance pt q))
        (if (or (null bestd) (< d bestd)) (setq bestd d best q)))))
  best)

(defun cchk:ptstr (p)
  (strcat "(" (rtos (car p) 2 4) ", " (rtos (cadr p) 2 4) ")"))

(defun cchk:pad2 (n)
  (if (< n 10) (strcat "0" (itoa n)) (itoa n)))

(defun cchk:datestr (/ d dd tt)
  ;; CDATE is YYYYMMDD.HHMMSSmsec; decoded arithmetically so DIMZIN
  ;; (which trims rtos output) cannot mangle it
  (setq d  (getvar "CDATE")
        dd (fix d)
        tt (- d dd))
  (strcat (itoa (fix (/ dd 10000))) "-"
          (cchk:pad2 (rem (fix (/ dd 100)) 100)) "-"
          (cchk:pad2 (rem dd 100)) " "
          (cchk:pad2 (fix (+ (* tt 100) 1e-6))) ":"
          (cchk:pad2 (rem (fix (+ (* tt 10000) 1e-4)) 100))))

(defun cchk:bbox (ent / obj ll ur)
  ;; ((minx miny minz) (maxx maxy maxz)) in WCS, or nil
  (setq obj (vlax-ename->vla-object ent))
  (if (not (vl-catch-all-error-p
             (vl-catch-all-apply 'vla-getboundingbox (list obj 'll 'ur))))
    (list (vlax-safearray->list ll) (vlax-safearray->list ur))))

(defun cchk:zoom-ent (ent / bb p1 p2 m)
  ;; zoom the current view onto ent with some breathing room
  (setq bb (cchk:bbox ent))
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *cchk-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

(defun cchk:zoom-2ents (e1 e2 / b1 b2 p1 p2 m)
  ;; zoom onto the combined box of two entities
  (setq b1 (cchk:bbox e1)
        b2 (cchk:bbox e2))
  (cond
    ((and b1 b2)
     (setq p1 (list (min (caar b1) (caar b2))
                    (min (cadar b1) (cadar b2)))
           p2 (list (max (caadr b1) (caadr b2))
                    (max (cadadr b1) (cadadr b2)))
           m  (* *cchk-zoom-margin*
                 (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
     (command "_.ZOOM" "_Window"
              (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
              (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))
    (b1 (cchk:zoom-ent e1))
    (b2 (cchk:zoom-ent e2))))

(defun cchk:stage (ent saved keep)
  ;; bring an entity back to its own colour for review — unless it
  ;; already wears a COVERCHECK marker colour it must not lose
  (if (and (entget ent) (not (member ent keep)))
    (cchk:set-color ent (cdr (assoc ent saved)))))

(defun cchk:unstage (ent keep)
  ;; send a reviewed entity back into the grey background
  (if (and (entget ent) (not (member ent keep)))
    (cchk:set-color ent *cchk-grey-color*)))

(defun cchk:mark-x (pt col / p s)
  ;; diagonal cross - marks WHERE YOU DREW IT
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (- (cadr p) s)) (list (+ (car p) s) (+ (cadr p) s)) col 1)
  (grdraw (list (- (car p) s) (+ (cadr p) s)) (list (+ (car p) s) (- (cadr p) s)) col 1))

(defun cchk:mark-plus (pt col / p s)
  ;; upright cross - marks WHERE COVERCHECK WOULD PUT IT
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (cadr p)) (list (+ (car p) s) (cadr p)) col 1)
  (grdraw (list (car p) (- (cadr p) s)) (list (car p) (+ (cadr p) s)) col 1))

(defun cchk:mark-point (pt)
  ;; both strokes, for a point that is simply being pointed out
  (cchk:mark-x pt 2)
  (cchk:mark-plus pt 2))

(defun cchk:ask-yn (msg / ans)
  ;; T = yes (Enter or Y), nil = no (N)
  (initget "Yes No")
  (setq ans (getkword (strcat msg " [Yes/No] <Yes>: ")))
  (or (null ans) (= ans "Yes")))

(defun cchk:ask-yn-nav (msg / ans)
  ;; the reviewing question, with a way out of a mis-press:
  ;; 'yes 'no 'back (redo the previous item) 'skip (stop asking,
  ;; finish the run and still write the report)
  (initget "Yes No Back Skip")
  (setq ans (getkword (strcat msg " [Yes/No/Back/Skip rest] <Yes>: ")))
  (cond ((null ans)      'yes)
        ((= ans "Yes")   'yes)
        ((= ans "No")    'no)
        ((= ans "Back")  'back)
        (t               'skip)))

(defun cchk:progress (what n total)
  (princ (strcat "\r  [" (itoa n) "/" (itoa total) "] " what "          ")))

(defun cchk:confirm-move (label orig sugg / ans newp)
  ;; The point has been put where COVERCHECK thinks it belongs, but BOTH
  ;; spots are marked and spelled out so there is no doubt which is
  ;; which: a red X where you drew it, a green + where we would move
  ;; it, joined by a line. Returns
  ;;   'move - take our suggestion
  ;;   'keep - put it back exactly where you drew it
  ;;   <point> - a spot you picked yourself (current UCS)
  (cchk:mark-x    orig *cchk-orig-color*)
  (cchk:mark-plus sugg *cchk-sugg-color*)
  (if (> (distance orig sugg) 1e-8)
    (grdraw (trans orig 0 1) (trans sugg 0 1) *cchk-sugg-color* 1))
  (princ (strcat "\n  " label " - which spot is right?"
                 "\n    Keep = where you drew it   " (cchk:ptstr orig)
                 "  (red X)"
                 "\n    Move = onto nearest object " (cchk:ptstr sugg)
                 "  (green +), " (rtos (distance orig sugg) 2 4) " away"))
  (initget "Move Keep Pick")
  (setq ans (getkword
              "\n  [Move to the green +/Keep at the red X/Pick a spot] <Move>: "))
  (cond
    ((or (null ans) (= ans "Move")) 'move)
    ((= ans "Keep") 'keep)
    (t (setq newp (getpoint (strcat "\n  Pick the spot for " label
                                    " <Move to the green +>: ")))
       (if newp newp 'move))))

(defun cchk:mtext (ins height width text layer / dxf)
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
  (if (entmake (append dxf (list (cons 1 text))))
    (cchk:tag (entlast) "REPORT")))

(defun cchk:attn-p (s)
  ;; T when a report line describes something questionable or that
  ;; needs looking over / fixing, so the report renders it in red
  (wcmatch (strcase s)
    "*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO BLOCK*,*WORD NOT*,*WORD ERROR*,* ADD *,*MISMATCH*,*NOT CONFIRMED*,*ASSOCIATIVE*,*DISAGREE*"))

(defun cchk:red (s)
  ;; wrap an MTEXT run so it renders in the flag colour, reverting
  ;; to the surrounding colour after (braces scope the change)
  (strcat "{\\C" (itoa *cchk-flag-color*) ";" s "}"))

(defun cchk:small (s)
  ;; all-clear text renders at *cchk-green-scale* of the height the
  ;; red attention text gets, so problems stand out on the sheet
  (strcat "{\\H" (rtos *cchk-green-scale* 2 4) "x;" s "}"))

;; --- geometry ------------------------------------------------------

(defun cchk:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

(defun cchk:circumcenter (p1 p2 p3 / ax ay bx by cx cy d)
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

(defun cchk:planar-arc-p (ed / n)
  ;; only arcs drawn in the world XY plane are handled
  (setq n (cdr (assoc 210 ed)))
  (or (null n)
      (and (< (abs (car n)) 1e-9)
           (< (abs (cadr n)) 1e-9)
           (> (caddr n) 0.0))))

(defun cchk:rebuild-arc (ent which fixed mid target / c r a1 a2 am tmp ed pair)
  ;; re-fit the arc through its fixed end, its old midpoint and the
  ;; target point; returns T on success
  (if (and (> (distance target fixed) 1e-8)
           (setq c (cchk:circumcenter fixed mid target)))
    (progn
      (setq r  (distance c target)
            a1 (angle c (if (eq which 'start) target fixed))
            a2 (angle c (if (eq which 'start) fixed target))
            am (angle c mid))
      ;; ARC entities always sweep counter-clockwise from start to
      ;; end; keep the sweep that contains the old midpoint
      (if (> (cchk:angnorm (- am a1)) (cchk:angnorm (- a2 a1)))
        (setq tmp a1
              a1  a2
              a2  tmp))
      (setq ed (entget ent))
      (foreach pair (list (cons 10 c) (cons 40 r) (cons 50 a1) (cons 51 a2))
        (setq ed (subst pair (assoc (car pair) ed) ed)))
      (if (entmod ed)
        (progn (entupd ent) T)))))

(defun cchk:move-arc-end (ent which target / mid other)
  ;; re-fit the arc so the chosen endpoint lands on target (WCS)
  (setq mid   (vlax-curve-getPointAtDist
                ent
                (/ (vlax-curve-getDistAtParam ent (vlax-curve-getEndParam ent)) 2.0))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent)))
  (cchk:rebuild-arc ent which other mid target))

(defun cchk:unit (v / l)
  ;; v scaled to length 1; nil for a (near-)zero vector
  (setq l (distance '(0.0 0.0 0.0) v))
  (if (> l 1e-12)
    (mapcar '(lambda (x) (/ x l)) v)))

(defun cchk:proj-param (p a u)
  ;; signed distance of p along the axis through a with unit dir u
  (apply '+ (mapcar '* (mapcar '- p a) u)))

(defun cchk:axis-pt (a u s)
  ;; the point at parameter s on that axis
  (mapcar '+ a (mapcar '(lambda (x) (* x s)) u)))

(defun cchk:pt-line-dist (p a u / s)
  ;; distance from p to the infinite line through a with unit dir u
  (setq s (cchk:proj-param p a u))
  (distance p (cchk:axis-pt a u s)))

(defun cchk:overlap-info (la lb / a1 a2 b1 b2 u lena s1 s2 tmp lo hi)
  ;; when segments la and lb are collinear (within *cchk-olap-fuzz*)
  ;; and run on top of each other for more than *cchk-tol*, returns
  ;;   (ov-start ov-end ov-length union-start union-end)
  ;; nil when they do not overlap (touching end-to-end is fine)
  (setq a1 (cchk:seg-p1 la)
        a2 (cchk:seg-p2 la)
        b1 (cchk:seg-p1 lb)
        b2 (cchk:seg-p2 lb)
        u  (cchk:unit (mapcar '- a2 a1)))
  (if (and u
           (<= (cchk:pt-line-dist b1 a1 u) *cchk-olap-fuzz*)
           (<= (cchk:pt-line-dist b2 a1 u) *cchk-olap-fuzz*))
    (progn
      (setq lena (distance a1 a2)
            s1   (cchk:proj-param b1 a1 u)
            s2   (cchk:proj-param b2 a1 u))
      (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
      (setq lo (max 0.0 s1)
            hi (min lena s2))
      (if (> (- hi lo) *cchk-tol*)
        (list (cchk:axis-pt a1 u lo)
              (cchk:axis-pt a1 u hi)
              (- hi lo)
              (cchk:axis-pt a1 u (min 0.0 s1))
              (cchk:axis-pt a1 u (max lena s2)))))))

(defun cchk:merge-lines (la lb info / ed)
  ;; stretch la's LINE over the union of both, delete lb's LINE
  (setq ed (entget (cchk:seg-ent la))
        ed (subst (cons 10 (nth 3 info)) (assoc 10 ed) ed)
        ed (subst (cons 11 (nth 4 info)) (assoc 11 ed) ed))
  (entmod ed)
  (entupd (cchk:seg-ent la))
  (entdel (cchk:seg-ent lb)))

(defun cchk:whole-line-p (s / ed)
  ;; T when the segment IS its owner entity - only whole LINEs can be
  ;; merged; a polyline edge has to be fixed by hand
  (setq ed (entget (cchk:seg-ent s)))
  (= "LINE" (cdr (assoc 0 ed))))

(defun cchk:find-overlaps (segs / atol fams a placed fam recs e p1 p2 dx dy
                                off s1 s2 tmp rest r q pairs seen key)
  ;; every overlapping segment pair, without comparing all pairs:
  ;; segments are bucketed by direction, then swept in offset order so
  ;; only genuinely collinear neighbours are ever tested. Segments of
  ;; the same entity are skipped (a polyline meeting itself is not a
  ;; duplicate), as are pairs already found through another segment.
  (setq atol  (* 0.5 (/ pi 180.0))              ; 0.5 deg is ample at this fuzz
        fams  nil
        pairs nil
        seen  nil)
  (foreach e segs
    (setq a      (cchk:seg-dir-ang e)
          placed nil)
    (foreach fam fams
      (if (and (not placed)
               (or (<= (cchk:ang-diff a (car fam)) atol)))
        (setq fams   (subst (cons (car fam) (cons e (cdr fam))) fam fams)
              placed T)))
    (if (not placed) (setq fams (cons (list a e) fams))))
  (foreach fam fams
    (if (cdr (cdr fam))                          ; two or more to compare
      (progn
        (setq a  (car fam)
              dx (cos a)
              dy (sin a)
              recs nil)
        (foreach e (cdr fam)
          (setq p1  (cchk:seg-p1 e)
                p2  (cchk:seg-p2 e)
                off (- (* (cadr p1) dx) (* (car p1) dy))
                s1  (+ (* (car p1) dx) (* (cadr p1) dy))
                s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
          (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
          (setq recs (cons (list off s1 s2 e) recs)))
        (setq recs (cchk:sort-recs recs))
        ;; sorted by offset: only sweep forward while still collinear
        (while recs
          (setq r    (car recs)
                rest (cdr recs))
          (while (and rest
                      (<= (- (car (car rest)) (car r)) *cchk-olap-fuzz*))
            (setq q (car rest))
            (if (and (not (eq (cchk:seg-ent (cadddr r))
                              (cchk:seg-ent (cadddr q))))
                     ;; spans must actually meet before the exact test
                     (> (min (caddr r) (caddr q)) (max (cadr r) (cadr q)))
                     (cchk:overlap-info (cadddr r) (cadddr q)))
              (progn
                (setq key (list (cchk:seg-ent (cadddr r))
                                (cchk:seg-ent (cadddr q))))
                (if (not (member key seen))
                  (setq seen  (cons key (cons (reverse key) seen))
                        pairs (cons (list (cadddr r) (cadddr q)) pairs)))))
            (setq rest (cdr rest)))
          (setq recs (cdr recs))))))
  (reverse pairs))

;; --- segments: lines AND polyline edges ----------------------------
;; Detection works on "segs" - (start end owner-entity) records - so a
;; run of edges drawn as one polyline counts exactly like the same
;; shape drawn as separate LINEs.

(defun cchk:seg-p1 (s) (car s))
(defun cchk:seg-p2 (s) (cadr s))
(defun cchk:seg-ent (s) (caddr s))

(defun cchk:ocs->wcs (p nz)
  (if (and nz (not (equal nz '(0.0 0.0 1.0) 1e-9))) (trans p nz 0) p))

(defun cchk:lwpoly-segs (ent / ed nz elev vs bl cls n i segs g)
  ;; straight edges of an LWPOLYLINE; bulged (arc) edges are skipped
  (setq ed   (entget ent)
        nz   (cdr (assoc 210 ed))
        elev (cdr (assoc 38 ed))
        cls  (= 1 (logand 1 (cdr (assoc 70 ed))))
        vs   nil
        bl   nil)
  (if (null elev) (setq elev 0.0))
  (foreach g ed
    (cond
      ((= 10 (car g))
       (setq vs (cons (cchk:ocs->wcs (list (car (cdr g)) (cadr (cdr g)) elev) nz) vs)
             bl (cons 0.0 bl)))
      ((= 42 (car g))
       (if bl (setq bl (cons (cdr g) (cdr bl)))))))
  (setq vs (reverse vs)
        bl (reverse bl)
        n  (length vs)
        i  0)
  (while (< i (1- n))
    (if (equal 0.0 (nth i bl) 1e-12)
      (setq segs (cons (list (nth i vs) (nth (1+ i) vs) ent) segs)))
    (setq i (1+ i)))
  (if (and cls (> n 2) (equal 0.0 (nth (1- n) bl) 1e-12))
    (setq segs (cons (list (nth (1- n) vs) (car vs) ent) segs)))
  segs)

(defun cchk:heavy-poly-segs (ent / e ed vs bl cls n i segs)
  ;; straight edges of an old-style POLYLINE (VERTEX entities)
  (setq cls (= 1 (logand 1 (cdr (assoc 70 (entget ent)))))
        e   (entnext ent)
        vs  nil
        bl  nil)
  (while (and e (= "VERTEX" (cdr (assoc 0 (setq ed (entget e))))))
    (if (zerop (logand 16 (cdr (assoc 70 ed))))    ; skip spline frame points
      (setq vs (cons (cdr (assoc 10 ed)) vs)
            bl (cons (if (assoc 42 ed) (cdr (assoc 42 ed)) 0.0) bl)))
    (setq e (entnext e)))
  (setq vs (reverse vs)
        bl (reverse bl)
        n  (length vs)
        i  0)
  (while (< i (1- n))
    (if (equal 0.0 (nth i bl) 1e-12)
      (setq segs (cons (list (nth i vs) (nth (1+ i) vs) ent) segs)))
    (setq i (1+ i)))
  (if (and cls (> n 2) (equal 0.0 (nth (1- n) bl) 1e-12))
    (setq segs (cons (list (nth (1- n) vs) (car vs) ent) segs)))
  segs)

(defun cchk:ent-segs (ent / ed et)
  ;; every straight segment an entity contributes, in WCS
  (setq ed (entget ent)
        et (cdr (assoc 0 ed)))
  (cond
    ((= et "LINE")       (list (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)) ent)))
    ((= et "LWPOLYLINE") (cchk:lwpoly-segs ent))
    ((= et "POLYLINE")   (cchk:heavy-poly-segs ent))))

(defun cchk:collect-segs (ents / segs e s)
  ;; all straight segments of a list of entities, longer than the
  ;; attachment tolerance (zero-length stubs help nothing)
  (foreach e ents
    (if (entget e)
      (foreach s (cchk:ent-segs e)
        (if (> (distance (car s) (cadr s)) *cchk-tol*)
          (setq segs (cons s segs))))))
  (reverse segs))

(defun cchk:group-ents (g / out e s)
  ;; the distinct entities a group's segments belong to
  (foreach s (cdr g)
    (setq e (cchk:seg-ent s))
    (if (not (member e out)) (setq out (cons e out))))
  (reverse out))

(defun cchk:seg-dir-ang (s / a)
  ;; segment direction folded into [0, pi)
  (setq a (angle (cchk:seg-p1 s) (cchk:seg-p2 s)))
  (if (>= a pi) (- a pi) a))

(defun cchk:ang-diff (a b / d)
  ;; distance between two folded directions, in [0, pi/2]
  (setq d (abs (- a b)))
  (min d (- pi d)))

(defun cchk:sort-recs (recs / out r pre rest)
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

(defun cchk:pts-bbox (segs / xs ys e p)
  ;; ((minx miny) (maxx maxy)) over the endpoints of a list of segments
  (setq xs nil ys nil)
  (foreach e segs
    (foreach p (list (cchk:seg-p1 e) (cchk:seg-p2 e))
      (setq xs (cons (car p) xs)
            ys (cons (cadr p) ys))))
  (if xs
    (list (list (apply 'min xs) (apply 'min ys))
          (list (apply 'max xs) (apply 'max ys)))))

(defun cchk:boxes-touch (b1 b2 m)
  ;; do two ((minx miny)(maxx maxy)) boxes overlap once grown by m?
  (and b1 b2
       (<= (- (caar b2) m) (caadr b1))
       (<= (- (caar b1) m) (caadr b2))
       (<= (- (cadar b2) m) (cadadr b1))
       (<= (- (cadar b1) m) (cadadr b2))))

(defun cchk:zoom-box (bb / p1 p2 m)
  ;; zoom the current view onto a ((minx miny)(maxx maxy)) box
  (if bb
    (progn
      (setq p1 (car bb)
            p2 (cadr bb)
            m  (* *cchk-zoom-margin*
                  (max (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) 1e-6)))
      (command "_.ZOOM" "_Window"
               (trans (list (- (car p1) m) (- (cadr p1) m) 0.0) 0 1)
               (trans (list (+ (car p2) m) (+ (cadr p2) m) 0.0) 0 1)))))

;; --- block & text helpers ------------------------------------------

(defun cchk:norm-text (s)
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

(defun cchk:block-name (ent / res)
  ;; effective block name (sees through dynamic blocks)
  (setq res (vl-catch-all-apply
              'vla-get-EffectiveName
              (list (vlax-ename->vla-object ent))))
  (if (vl-catch-all-error-p res)
    (cdr (assoc 2 (entget ent)))
    res))

(defun cchk:blockdef-texts (bname depth / lst e et g)
  ;; TEXT/MTEXT/ATTDEF inside a block definition, following nested
  ;; blocks down to depth so a title wrapped in a wrapper is found
  (setq e (tblobjname "BLOCK" bname))
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
               (setq lst (cons (cdr g) lst)))))
          ((and (= et "INSERT") (> depth 1))
           (setq lst (cons (cdr (assoc 2 (entget e))) lst)  ; nested block NAME
                 lst (append (cchk:blockdef-texts (cdr (assoc 2 (entget e)))
                                                  (1- depth))
                             lst))))
        (setq e (entnext e)))))
  lst)

(defun cchk:ins-texts (ent / ed lst e)
  ;; every piece of text an INSERT shows: its attribute values plus
  ;; the text inside its block definition, nested blocks included
  (setq ed  (entget ent)
        lst nil)
  (if (= 1 (cdr (assoc 66 ed)))               ; attributes follow
    (progn
      (setq e (entnext ent))
      (while (and e (= "ATTRIB" (cdr (assoc 0 (entget e)))))
        (setq lst (cons (cdr (assoc 1 (entget e))) lst)
              e   (entnext e)))))
  (append lst (cchk:blockdef-texts (cdr (assoc 2 ed)) *cchk-block-depth*)))

(defun cchk:ins-attrib-deep (ent tag / val s)
  ;; the tag's value on the INSERT, or on a block nested inside it
  (setq val (cchk:ins-attrib ent tag))
  (if val
    val
    (foreach s (cchk:blockdef-texts (cdr (assoc 2 (entget ent)))
                                    *cchk-block-depth*)
      (if (and (null val)
               (wcmatch (cchk:squash s) (strcat "*" (cchk:squash tag) "*")))
        (setq val s)))))

(defun cchk:block-has-layer-p (bname layer depth / e et found)
  ;; does the block definition (or a block it nests, down to depth)
  ;; draw anything on the given layer?
  (setq e (tblobjname "BLOCK" bname))
  (if e
    (progn
      (setq e (entnext e))
      (while (and e (not found)
                  (/= "ENDBLK" (setq et (cdr (assoc 0 (entget e))))))
        (if (= (strcase (cdr (assoc 8 (entget e)))) (strcase layer))
          (setq found T))
        (if (and (not found) (= et "INSERT") (> depth 1))
          (if (cchk:block-has-layer-p (cdr (assoc 2 (entget e))) layer (1- depth))
            (setq found T)))
        (setq e (entnext e)))))
  found)

(defun cchk:ins-matches (ent phrase / pat found s)
  ;; T when the INSERT's (effective) name or any text it shows
  ;; contains the phrase, ignoring case and punctuation
  (setq pat   (strcat "*" (cchk:norm-text phrase) "*")
        found (wcmatch (cchk:norm-text (cchk:block-name ent)) pat))
  (foreach s (cchk:ins-texts ent)
    (if (wcmatch (cchk:norm-text s) pat)
      (setq found T)))
  found)

(defun cchk:ins-has-word (ent word / found s)
  ;; T when the INSERT's (effective) name or any text it shows
  ;; contains the given standalone word — "NOT" hits "Not Selected"
  ;; but never "NOTE"; "STEP" hits "with Step" but never "Stepstone"
  (setq word  (strcase word)
        found nil)
  (foreach s (cons (cchk:block-name ent) (cchk:ins-texts ent))
    (if (and s
             (wcmatch (strcat " " (cchk:norm-text s) " ")
                      (strcat "* " word " *")))
      (setq found T)))
  found)

(defun cchk:clip (s n)
  (if (> (strlen s) n) (strcat (substr s 1 n) "...") s))

(defun cchk:join (lst sep / out s)
  ;; "A" + "B" + ... joined with sep
  (foreach s lst
    (setq out (if out (strcat out sep s) s)))
  out)

(defun cchk:squash (s)
  ;; norm-text with the spaces removed too, so "Cover Material" finds
  ;; a block that is actually named "CoverMaterial"
  (vl-list->string (vl-remove 32 (vl-string->list (cchk:norm-text s)))))

(defun cchk:ins-attrib (ent tag / e ed val)
  ;; value of the attribute with the given tag on an INSERT; nil
  ;; when the block has no such attribute
  (setq tag (strcase tag))
  (if (= 1 (cdr (assoc 66 (entget ent))))
    (progn
      (setq e (entnext ent))
      (while (and e (null val) (= "ATTRIB" (cdr (assoc 0 (entget e)))))
        (setq ed (entget e))
        (if (= tag (strcase (cdr (assoc 2 ed))))
          (setq val (cdr (assoc 1 ed))))
        (setq e (entnext e)))))
  val)

(defun cchk:parse-num (s / p num den)
  ;; "4", "4.5", "1/2" -> real
  (setq p (vl-string-search "/" s))
  (if p
    (progn
      (setq num (atof (substr s 1 p))
            den (atof (substr s (+ p 2))))
      (if (> den 0.0) (/ num den) 0.0))
    (atof s)))

(defun cchk:after-eq (s / p)
  ;; the part after the last "=", so a label never contributes its
  ;; own digits: "Finished Wall Ht = 40''" -> " 40''"
  (while (setq p (vl-string-search "=" s))
    (setq s (substr s (+ p 2))))
  s)

(defun cchk:len-values (s / lst i n c numstr toks unit vals cur tok)
  ;; every length written in the text, as a list of numbers in inches
  ;; (drawing units). ' = feet, '' or " = inches, a bare number counts
  ;; as inches. Feet and bare numbers carry on into the same value, an
  ;; inch mark closes it, so a compound height stays ONE value while a
  ;; list stays several:
  ;;   "40''"          -> (40.0)
  ;;   "3'-4''"        -> (40.0)
  ;;   "3' 4 1/2\""    -> (40.5)
  ;;   "0'', 40'', 45''" -> (0.0 40.0 45.0)
  ;; A label before the last "=" is ignored, so the attribute may read
  ;; "Finished Wall Ht = 40''" and still measure 40.
  (setq s    (cchk:after-eq s)
        lst  (vl-string->list s)
        i    0
        n    (length lst)
        toks nil)
  (while (< i n)
    (setq c (nth i lst))
    (if (or (and (>= c 48) (<= c 57)) (= c 46) (= c 47))  ; digit . /
      (progn
        (setq numstr "")
        (while (and (< i n)
                    (setq c (nth i lst))
                    (or (and (>= c 48) (<= c 57)) (= c 46) (= c 47)))
          (setq numstr (strcat numstr (chr c))
                i      (1+ i)))
        (setq unit nil)
        (cond
          ((and (< i n) (= (nth i lst) 34))               ; "
           (setq unit 'in
                 i    (1+ i)))
          ((and (< i n) (= (nth i lst) 39))               ; '
           (if (and (< (1+ i) n) (= (nth (1+ i) lst) 39))
             (setq unit 'in                               ; ''
                   i    (+ i 2))
             (setq unit 'ft
                   i    (1+ i)))))
        (setq toks (append toks (list (cons (cchk:parse-num numstr) unit)))))
      (setq i (1+ i))))
  (setq vals nil
        cur  nil)
  (foreach tok toks
    (setq cur (+ (if cur cur 0.0)
                 (if (eq (cdr tok) 'ft) (* 12.0 (car tok)) (car tok))))
    (if (eq (cdr tok) 'in)                     ; inches close the value
      (setq vals (append vals (list cur))
            cur  nil)))
  (if cur (setq vals (append vals (list cur))))
  vals)

(defun cchk:parse-len (s)
  ;; the first length written in the text, in inches; nil when none
  (car (cchk:len-values s)))

;; --- dimension review ----------------------------------------------

(defun cchk:dim-style (ent / s)
  ;; the dimension's style name, "" when it has none
  (setq s (cdr (assoc 3 (entget ent))))
  (if s s ""))

(defun cchk:style-rank (style / i r s)
  ;; position of the style in *cchk-style-order* (exact name match,
  ;; case-blind); unlisted styles land after every listed one
  (setq style (strcase style)
        i     0
        r     nil)
  (foreach s *cchk-style-order*
    (if (and (null r) (= (strcase s) style)) (setq r i))
    (setq i (1+ i)))
  (if r r (length *cchk-style-order*)))

(defun cchk:ent-center (ent / bb)
  ;; (x y) centre of the entity's box; falls back to its group-10 point
  (setq bb (cchk:bbox ent))
  (if bb
    (list (* 0.5 (+ (caar bb) (caadr bb)))
          (* 0.5 (+ (cadar bb) (cadadr bb))))
    (progn
      (setq bb (cdr (assoc 10 (entget ent))))
      (if bb (list (car bb) (cadr bb)) (list 0.0 0.0)))))

(defun cchk:dim-order-p (r1 r2 rowtol)
  ;; strict "r1 reviews before r2" for recs (rank cx cy ent):
  ;; style rank first, then row (higher = earlier), then left first
  (cond
    ((< (car r1) (car r2)) T)
    ((> (car r1) (car r2)) nil)
    ((> (- (caddr r1) (caddr r2)) rowtol) T)   ; r1 sits a row above
    ((> (- (caddr r2) (caddr r1)) rowtol) nil) ; r2 sits a row above
    (t (< (cadr r1) (cadr r2)))))              ; same row: left first

(defun cchk:sort-dims (dims rowtol / recs cen r out pre rest e)
  ;; stable insertion sort into review order
  (setq recs nil)
  (foreach e dims
    (setq cen  (cchk:ent-center e)
          recs (cons (list (cchk:style-rank (cchk:dim-style e))
                           (car cen) (cadr cen) e)
                     recs)))
  (setq recs (reverse recs)
        out  nil)
  (foreach r recs
    (setq pre  nil
          rest out)
    (while (and rest (not (cchk:dim-order-p r (car rest) rowtol)))
      (setq pre  (cons (car rest) pre)
            rest (cdr rest)))
    (setq out (append (reverse pre) (list r) rest)))
  (mapcar '(lambda (r) (nth 3 r)) out))

(defun cchk:dim-meas (ent / ed dtype p13 p14 ang v meas)
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

(defun cchk:dim-num (ent / ed dtype p13 p14 ang v)
  ;; the dimension's linear measurement as a NUMBER, recomputed from
  ;; its definition points; falls back to the stored measurement
  (setq ed    (entget ent)
        dtype (logand 7 (cdr (assoc 70 ed)))
        p13   (cdr (assoc 13 ed))
        p14   (cdr (assoc 14 ed)))
  (cond
    ((and (= dtype 1) p13 p14) (distance p13 p14))
    ((and (= dtype 0) p13 p14)
     (setq ang (cdr (assoc 50 ed)))
     (if (null ang) (setq ang 0.0))
     (setq v (mapcar '- p14 p13))
     (abs (+ (* (car v) (cos ang)) (* (cadr v) (sin ang)))))
    (t (cdr (assoc 42 ed)))))

(defun cchk:dim-stated (ent / txt v)
  ;; the value the dimension actually STATES: its text override when
  ;; it carries a readable one, else what it measures
  (setq txt (cdr (assoc 1 (entget ent))))
  (if (and txt
           (/= txt "")
           (not (vl-string-search "<>" txt))    ; "<>" = show the measurement
           (setq v (cchk:parse-len txt)))
    v
    (cchk:dim-num ent)))

(defun cchk:pt-in-box (p bb m)
  ;; is point p inside the ((minx miny)(maxx maxy)) box grown by m?
  (and bb p
       (>= (car p)  (- (caar bb) m))
       (<= (car p)  (+ (caadr bb) m))
       (>= (cadr p) (- (cadar bb) m))
       (<= (cadr p) (+ (cadadr bb) m))))

(defun cchk:audit-dim-point (ent gcode label cands / ed pt near sugg ans final how)
  ;; audits one definition point: an off-object point is put where it
  ;; looks like it belongs, then you choose - Move (take it), Keep
  ;; (put it back exactly where you drew it) or Pick your own spot.
  ;; Returns (original final how) when the point was looked at, where
  ;; how is 'auto / 'user / 'kept; nil when the point was already fine.
  (setq ed (entget ent)
        pt (cdr (assoc gcode ed)))
  (if pt
    (progn
      (setq near (cchk:nearest-curve pt nil cands))
      (if (and near (> (caddr near) *cchk-tol*))
        (progn
          (setq sugg (cadr near))
          ;; show the suggestion in place, but keep the original spot
          ;; marked so both are on screen while the question is asked
          (entmod (subst (cons gcode sugg) (assoc gcode ed) ed))
          (entupd ent)
          (princ (strcat "\n  " label " is not on any object - nearest one is "
                         (rtos (caddr near) 2 4) " away."))
          (setq ans (cchk:confirm-move label pt sugg))
          (cond
            ((eq ans 'move)
             (setq final sugg
                   how   'auto)
             (princ (strcat "\n  " label " MOVED onto the nearest object, "
                            (cchk:ptstr final) ".")))
            ((eq ans 'keep)
             (setq ed    (entget ent)
                   final pt
                   how   'kept)
             (entmod (subst (cons gcode pt) (assoc gcode ed) ed))
             (entupd ent)
             (princ (strcat "\n  " label " KEPT where you drew it, "
                            (cchk:ptstr final) " - nothing changed.")))
            (t
             (setq final (trans ans 1 0)
                   how   'user
                   ed    (entget ent))
             (entmod (subst (cons gcode final) (assoc gcode ed) ed))
             (entupd ent)
             (princ (strcat "\n  " label " moved to the spot you picked, "
                            (cchk:ptstr final) "."))))
          (redraw)
          (list pt final how))))))

(defun cchk:review-dim (ent cands num total / ed dtype h sty p13 p14 r1 r2
                                              looked moved kept ok note meas assocnote)
  ;; interactive review of one dimension.
  ;; Returns (handle ok-flag report-note moved-point-count measurement).
  (setq ed    (entget ent)
        h     (cdr (assoc 5 ed))
        sty   (cchk:dim-style ent)
        dtype (logand 7 (cdr (assoc 70 ed))))
  (cchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nDimension " (itoa num) " of " (itoa total)
                 " (handle " h
                 (if (= sty "") "" (strcat ", style " sty))
                 ")"))
  (if (member dtype '(0 1))                   ; rotated/linear or aligned
    (progn
      (if (cchk:dim-assoc-p ent)
        (princ "\n  Note: this dimension is object-associative - a moved point may re-anchor on its own."))
      (setq p13 (cdr (assoc 13 ed))           ; the two dimmed points
            p14 (cdr (assoc 14 ed))
            r1  (cchk:audit-dim-point ent 13 "dimension point 1" cands)
            r2  (cchk:audit-dim-point ent 14 "dimension point 2" cands))))
  (setq looked (append (if r1 (list r1)) (if r2 (list r2)))
        moved  (vl-remove-if '(lambda (x) (eq (caddr x) 'kept)) looked)
        kept   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'kept)) looked))
  ;; only when something actually moved is there an old position worth
  ;; drawing a construction line through
  (if moved (cchk:make-xline p13 p14))        ; through the ORIGINAL points
  (if (and moved (cchk:dim-assoc-p ent))
    (setq assocnote " (ASSOCIATIVE - verify the moved point holds)"))
  (setq meas (cchk:dim-meas ent))             ; after any point moves
  (if meas (princ (strcat "\n  Measures " meas ".")))
  (redraw ent 3)
  (setq ok (cchk:ask-yn-nav "\n  Is this dimension correct?"))
  (redraw ent 4)
  (redraw)
  (if (member ok '(back skip))
    (list h ok nil (length moved) meas)       ; navigation: caller handles it
    (progn
      (setq ok (eq ok 'yes))
      (setq note (strcat
                   (if ok "OK" "FLAGGED to fix (red)")
                   (if moved
                     (strcat " - " (itoa (length moved))
                             " point(s) moved onto the nearest object")
                     "")
                   (if kept
                     (strcat " - " (itoa (length kept))
                             " point(s) kept where you drew them")
                     "")
                   (if assocnote assocnote "")))
      (if (not ok) (cchk:set-color ent *cchk-flag-color*))
      (list h ok note (length moved) meas))))

;; --- arc review ----------------------------------------------------

(defun cchk:arc-end-target (ent which cands / p other near ends target)
  ;; where the attachment audit says this endpoint should go;
  ;; nil when the endpoint is already fine (or nothing to attach to)
  (setq p     (if (eq which 'start)
                (vlax-curve-getStartPoint ent)
                (vlax-curve-getEndPoint ent))
        other (if (eq which 'start)
                (vlax-curve-getEndPoint ent)
                (vlax-curve-getStartPoint ent))
        near  (cchk:nearest-curve p ent cands))
  (cond
    ((null near) nil)                         ; nothing to attach to at all
    ((<= (caddr near) *cchk-tol*)             ; endpoint sits on an object...
     (setq ends (cchk:curve-ends (car near)))
     ;; never snap onto the arc's own other endpoint
     (setq ends (vl-remove-if '(lambda (q) (< (distance q other) 1e-8)) ends))
     (cond
       ((null ends) nil)                      ; closed curve: no ends to demand
       ((vl-some '(lambda (q) (<= (distance p q) *cchk-tol*)) ends)
        nil)                                  ; ...and at one of its ends: OK
       (t (cchk:closest-of p ends))))         ; ...but mid-object: closest end
    (t                                        ; floating: closest end anywhere,
     (setq target (cchk:nearest-end p ent cands))
     (if (or (null target) (< (distance target other) 1e-8))
       (cadr near)                            ; else closest point on closest object
       target))))

(defun cchk:arc-state (ent / ed)
  ;; the groups that define an arc's shape, for an exact put-it-back
  (setq ed (entget ent))
  (list (assoc 10 ed) (assoc 40 ed) (assoc 50 ed) (assoc 51 ed)))

(defun cchk:arc-restore (ent st / ed g)
  ;; restore a saved shape exactly, rather than re-fitting back to it
  (setq ed (entget ent))
  (foreach g st (setq ed (subst g (assoc (car g) ed) ed)))
  (entmod ed)
  (entupd ent))

(defun cchk:review-arc-end (ent which label cands / p target st ans final how)
  ;; audits one arc endpoint: a detached end is snapped where it looks
  ;; like it belongs, then you choose - Move (take it), Keep (put the
  ;; arc back exactly as drawn) or Pick your own spot.
  ;; Returns (original final how) when the end was looked at, where how
  ;; is 'auto / 'user / 'kept; nil when the end was already fine.
  (setq p      (if (eq which 'start)
                 (vlax-curve-getStartPoint ent)
                 (vlax-curve-getEndPoint ent))
        target (cchk:arc-end-target ent which cands)
        st     (cchk:arc-state ent))
  (cond
    (target
     (if (cchk:move-arc-end ent which target)
       (progn
         (princ (strcat "\n  " label " is not attached to an object end - nearest is "
                        (rtos (distance p target) 2 4) " away."))
         (setq ans (cchk:confirm-move label p target))
         (cond
           ((eq ans 'move)
            (setq final target
                  how   'auto)
            (princ (strcat "\n  " label " SNAPPED to the object end, "
                           (cchk:ptstr final) ".")))
           ((eq ans 'keep)
            (cchk:arc-restore ent st)
            (setq final p
                  how   'kept)
            (princ (strcat "\n  " label " KEPT where you drew it, "
                           (cchk:ptstr final) " - the arc is unchanged.")))
           (t
            (setq ans (trans ans 1 0))
            (if (cchk:move-arc-end ent which ans)
              (progn
                (setq final ans
                      how   'user)
                (princ (strcat "\n  " label " moved to the spot you picked, "
                               (cchk:ptstr final) ".")))
              (progn
                (setq final target
                      how   'auto)
                (princ "\n  Could not re-fit the arc through that spot (collinear?); left it on the object end.")))))
         (redraw)
         (list p final how))
       (progn
         (princ (strcat "\n  " label " should attach at " (cchk:ptstr target)
                        " but the arc could not be re-fitted (points collinear?)."))
         nil)))
    (*cchk-ask-all-arc-ends*                  ; optional: confirm attached ends too
     (setq ans (cchk:confirm-move label p p))
     (redraw)
     (if (member ans '(move keep))
       nil
       (progn
         (setq ans (trans ans 1 0))
         (if (cchk:move-arc-end ent which ans)
           (list p ans 'user)
           (progn
             (princ "\n  Could not re-fit the arc through that spot (collinear?); unchanged.")
             nil)))))
    (t nil)))

(defun cchk:review-arc (ent cands num total / ed h planar r1 r2 looked moved kept note)
  ;; interactive review of one arc's endpoints.
  ;; Returns (handle untouched-flag report-note moved-point-count).
  (setq ed     (entget ent)
        h      (cdr (assoc 5 ed))
        planar (cchk:planar-arc-p ed))
  (cchk:zoom-ent ent)
  (redraw ent 3)
  (princ (strcat "\n\nArc " (itoa num) " of " (itoa total)
                 " (handle " h ")"))
  (if planar
    (setq r1 (cchk:review-arc-end ent 'start "arc start point" cands)
          r2 (cchk:review-arc-end ent 'end   "arc end point"   cands))
    (princ "\n  Arc is not in the world XY plane - endpoint audit skipped."))
  (redraw ent 4)
  (redraw)
  (setq looked (append (if r1 (list r1)) (if r2 (list r2)))
        moved  (vl-remove-if '(lambda (x) (eq (caddr x) 'kept)) looked)
        kept   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'kept)) looked))
  (if moved (cchk:set-color ent *cchk-arc-color*))
  (setq note (cond
               ((not planar) "not in world XY plane - skipped")
               ((and moved kept)
                (strcat (itoa (length moved)) " endpoint(s) moved (magenta), "
                        (itoa (length kept)) " kept where you drew them"))
               (moved (strcat (itoa (length moved))
                              " endpoint(s) moved (magenta)"))
               (kept (strcat (itoa (length kept))
                             " endpoint(s) kept where you drew them"))
               (t "endpoints OK")))
  (list h (null moved) note (length moved)))

;; --- overlapping line review ---------------------------------------

(defun cchk:review-olap (la lb num total / info ea eb h1 h2 lay1 lay2 label
                                           ans mergeable kinds)
  ;; interactive review of one overlapping segment pair.
  ;; Returns nil when the pair no longer overlaps (an earlier merge
  ;; absorbed it); otherwise (label report-note action ents...) where
  ;; action is merged / flagged / left and ents keep their cyan.
  (setq ea (cchk:seg-ent la)
        eb (cchk:seg-ent lb))
  (if (and (entget ea) (entget eb) (setq info (cchk:overlap-info la lb)))
    (progn
      (setq h1        (cdr (assoc 5 (entget ea)))
            h2        (cdr (assoc 5 (entget eb)))
            lay1      (cdr (assoc 8 (entget ea)))
            lay2      (cdr (assoc 8 (entget eb)))
            mergeable (and (cchk:whole-line-p la)
                           (cchk:whole-line-p lb)
                           (= (strcase lay1) (strcase lay2)))
            kinds     (if (and (cchk:whole-line-p la) (cchk:whole-line-p lb))
                        "lines"
                        "segments")
            label     (strcat h1 "+" h2 " (overlap " (rtos (caddr info)) ")"))
      (cchk:zoom-2ents ea eb)
      (redraw ea 3)
      (redraw eb 3)
      (cchk:mark-point (car info))
      (cchk:mark-point (cadr info))
      (princ (strcat "\n\nOverlap " (itoa num) " of " (itoa total)
                     ": " kinds " " h1 " + " h2
                     " run on top of each other for " (rtos (caddr info)) "."))
      (if mergeable
        (progn
          (initget "Merge Flag Leave")
          (setq ans (getkword
                      "\n  Merge into one line, Flag to fix, or Leave as is? [Merge/Flag/Leave] <Merge>: "))
          (if (null ans) (setq ans "Merge")))
        (progn
          (princ (if (= (strcase lay1) (strcase lay2))
                   "\n  (Polyline edge - cannot be merged automatically.)"
                   (strcat "\n  (Different layers: " lay1 " / " lay2
                           " - cannot be merged automatically.)")))
          (initget "Flag Leave")
          (setq ans (getkword
                      "\n  Flag to fix, or Leave as is? [Flag/Leave] <Flag>: "))
          (if (null ans) (setq ans "Flag"))))
      (redraw ea 4)
      (redraw eb 4)
      (redraw)
      (cond
        ((= ans "Merge")
         (cchk:merge-lines la lb info)
         (cchk:set-color ea *cchk-olap-color*)
         (princ "\n  Merged into one line (cyan).")
         (list label "merged into one line (cyan)" 'merged ea))
        ((= ans "Flag")
         (cchk:set-color ea *cchk-olap-color*)
         (cchk:set-color eb *cchk-olap-color*)
         (princ "\n  Flagged to fix (cyan).")
         (list label
               (if (cchk:whole-line-p la)
                 (if (= (strcase lay1) (strcase lay2))
                   "flagged to fix (cyan)"
                   "different layers - flagged to fix (cyan)")
                 "polyline edge - flagged to fix (cyan)")
               'flagged ea eb))
        (t
         (princ "\n  Left as drawn.")
         (list label "left as drawn" 'left))))))

;; --- command -------------------------------------------------------

(defun c:COVERCHECK ( / *error* oldecho vc vs undo-open ss i e et
                      cands dims arcs plns segs blks olaps e1 e2 pr
                      saved keep res n total lines
                      ndok ndflag ndmoved naok namoved nasnap
                      nomerged noflag noleft
                      rowtol sty l pair hdr
                      laylist locked relock lay
                      dlines skiprest
                      minx miny maxx maxy bb h m ins txt nlin ref)

  (defun *error* (msg)
    ;; put the greys back (flagged/moved items keep their colour),
    ;; re-lock what we unlocked, clear markers, close the undo group
    (foreach pair saved
      (if (and (not (member (car pair) keep)) (entget (car pair)))
        (cchk:set-color (car pair) (cdr pair))))
    (foreach l relock (cchk:set-layer-lock l T))
    (redraw)
    (if undo-open
      (progn (setvar "CMDECHO" 0) (command "_.UNDO" "_End")))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCOVERCHECK error: " msg)))
    (princ))

  (prompt "\nHighlight the drawing to COVERCHECK: ")
  (setq ss (ssget))
  (cond
    ((null ss)
     (prompt "\nNothing selected - COVERCHECK cancelled."))
    (t
     (setq cands nil dims nil arcs nil blks nil segs nil
           saved nil keep nil lines nil i 0
           ndok 0 ndflag 0 ndmoved 0 naok 0 namoved 0 nasnap 0
           nomerged 0 noflag 0 noleft 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (member et '("LINE" "LWPOLYLINE" "POLYLINE"))
         (setq plns (cons e plns)))
       (if (= et "INSERT") (setq blks (cons e blks)))
       (if (member et *cchk-curve-types*) (setq cands (cons e cands))))
     (setq dims  (reverse dims)
           arcs  (reverse arcs)
           plns  (reverse plns)
           blks  (reverse blks)
           cands (reverse cands)
           ;; detection runs on segments, so a shape drawn as one
           ;; polyline counts like the same shape drawn as lines
           segs  (cchk:collect-segs plns))
     (cond
       ((and (null dims) (null arcs) (< (length segs) 2) (null blks))
        (prompt "\nSelection holds no dimensions, arcs, lines, or blocks to check - nothing to do."))
       (t
        (setq oldecho (getvar "CMDECHO"))
        (setvar "CMDECHO" 0)
        (setq vc (getvar "VIEWCTR")
              vs (getvar "VIEWSIZE"))
        (command "_.UNDO" "_Begin")
        (setq undo-open T)
        (cchk:ensure-layer *cchk-constr-layer* *cchk-constr-color*)
        (cchk:ensure-layer *cchk-report-layer* *cchk-report-color*)

        ;; a locked layer swallows every fix and recolour silently -
        ;; surface that up front and offer to unlock for the run
        (setq laylist nil relock nil i 0)
        (repeat (sslength ss)
          (setq lay (cdr (assoc 8 (entget (ssname ss i))))
                i   (1+ i))
          (if (and lay (not (member lay laylist)))
            (setq laylist (cons lay laylist))))
        (setq locked (vl-remove-if-not 'cchk:layer-locked-p laylist))
        (if locked
          (if (cchk:ask-yn
                (strcat "\n" (itoa (length locked))
                        " locked layer(s) in the selection ("
                        (cchk:join locked ", ")
                        ") - COVERCHECK cannot recolour or fix anything on them. Unlock for this run?"))
            (progn
              (foreach l locked (cchk:set-layer-lock l nil))
              (setq relock locked)
              (princ "\n  Unlocked; they will be re-locked when the run ends."))
            (princ "\n  Locked layers stay locked - items on them are reported but left untouched.")))

        ;; a rerun replaces the previous run's report and markers
        (cchk:clear-old)

        ;; extents of the selection (report goes to the right of them)
        (setq i 0)
        (repeat (sslength ss)
          (setq e  (ssname ss i)
                i  (1+ i)
                bb (cchk:bbox e))
          (if bb
            (setq minx (if minx (min minx (caar bb)) (caar bb))
                  miny (if miny (min miny (cadar bb)) (cadar bb))
                  maxx (if maxx (max maxx (caadr bb)) (caadr bb))
                  maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))

        ;; march order for the dimensions: style groups first
        ;; (*cchk-style-order*), then row by row, left to right
        (setq rowtol (if (and miny maxy (> (- maxy miny) 1e-8))
                       (* 0.05 (- maxy miny))
                       1.0))
        (setq dims (cchk:sort-dims dims rowtol))

        ;; grey out the whole selection so each item can take the
        ;; stage, stashing every original colour in xdata first so
        ;; COVERCHECKRESCUE can recover them even after a crash
        (setq i 0)
        (repeat (sslength ss)
          (setq e (ssname ss i)
                i (1+ i))
          (if (entget e)
            (progn
              (setq saved (cons (cons e (cchk:ent-color e)) saved))
              (cchk:stash-color e (cchk:ent-color e))
              (cchk:set-color e *cchk-grey-color*))))

        ;; --- dimensions, one at a time -----------------------------
        (if dims
          (princ (strcat "\n--- Reviewing " (itoa (length dims))
                         " dimension(s): Enter = correct, N = flag to fix, "
                         "B = back one, S = skip the rest ---")))
        ;; index-based so Back can step to the previous dimension and
        ;; Skip can leave the rest unreviewed without losing the report
        (setq n 0 total (length dims) dlines nil skiprest nil)
        (while (and (< n total) (not skiprest))
          (setq e   (nth n dims)
                res nil)
          (cchk:set-color e (cdr (assoc e saved)))       ; step into the light
          (setq res (cchk:review-dim e cands (1+ n) total))
          ;; points already moved count however the prompt was answered
          (setq ndmoved (+ ndmoved (cadddr res)))
          (cond
            ((eq (cadr res) 'skip)
             (cchk:set-color e *cchk-grey-color*)
             (setq skiprest T)
             (princ (strcat "\n  Skipping the remaining "
                            (itoa (- total n)) " dimension(s).")))
            ((eq (cadr res) 'back)
             ;; undo what the previous item recorded, then redo it
             (cchk:set-color e *cchk-grey-color*)
             (if (> n 0)
               (progn
                 (setq n  (1- n)
                       e1 (nth n dims))
                 (if (car dlines)                        ; roll back its tally
                   (progn
                     (if (cadr (car dlines))
                       (setq ndok (1- ndok))
                       (setq ndflag (1- ndflag)))
                     (setq ndmoved (- ndmoved (caddr (car dlines)))
                           dlines  (cdr dlines))))
                 (setq keep (vl-remove e1 keep))
                 (cchk:set-color e1 *cchk-grey-color*)
                 (princ "\n  Stepping back one dimension."))
               (princ "\n  Already at the first dimension."))
             (setq n (1- n)))                            ; loop's 1+ re-enters it
            (t
             (if (cadr res)
               (progn (setq ndok (1+ ndok))
                      (cchk:set-color e *cchk-grey-color*))
               (progn (setq ndflag (1+ ndflag))
                      (setq keep (cons e keep))))
             (setq sty (cchk:dim-style e))
             (setq dlines (cons (list (strcat "Dim " (car res)
                                              (if (= sty "") "" (strcat " [" sty "]"))
                                              (if (nth 4 res)
                                                (strcat " = " (nth 4 res))
                                                "")
                                              ": " (caddr res))
                                      (cadr res)
                                      (cadddr res))
                                dlines))))
          (setq n (1+ n)))
        (if skiprest
          (setq lines (cons (strcat "Dimensions: " (itoa (- total (length dlines)))
                                    " left UNREVIEWED (skipped by user)")
                            lines)))
        (foreach pair (reverse dlines)
          (setq lines (cons (car pair) lines)))

        ;; --- arcs, one endpoint at a time --------------------------
        (if arcs
          (princ (strcat "\n--- Reviewing " (itoa (length arcs))
                         " arc(s): checking endpoint attachment ---")))
        (setq n 0 total (length arcs))
        (foreach e arcs
          (setq n (1+ n))
          (cchk:set-color e (cdr (assoc e saved)))
          (setq res (cchk:review-arc e cands n total))
          (setq nasnap (+ nasnap (cadddr res)))
          (if (cadr res)
            (progn (setq naok (1+ naok))
                   (cchk:set-color e *cchk-grey-color*))
            (progn (setq namoved (1+ namoved))
                   (setq keep (cons e keep))))           ; moved: stays magenta
          (setq lines (cons (strcat "Arc " (car res) ": " (caddr res)) lines)))

        ;; --- overlapping lines, one pair at a time ------------------
        (setq olaps (cchk:find-overlaps segs))
        (if olaps
          (princ (strcat "\n--- Reviewing " (itoa (length olaps))
                         " overlapping line pair(s): Enter = merge, F = flag, L = leave ---")))
        (setq n 0 total (length olaps))
        (foreach pr olaps
          (setq n  (1+ n)
                e1 (cchk:seg-ent (car pr))
                e2 (cchk:seg-ent (cadr pr)))
          (cchk:stage e1 saved keep)
          (cchk:stage e2 saved keep)
          (setq res (cchk:review-olap (car pr) (cadr pr) n total))
          (cond
            ((null res)                       ; absorbed by an earlier merge
             (cchk:unstage e1 keep)
             (cchk:unstage e2 keep))
            ((eq (caddr res) 'left)
             (setq noleft (1+ noleft))
             (cchk:unstage e1 keep)
             (cchk:unstage e2 keep)
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))
            (t
             (if (eq (caddr res) 'merged)
               (setq nomerged (1+ nomerged))
               (setq noflag (1+ noflag)))
             (setq keep (append (cdddr res) keep))
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))))

        ;; --- cover-specific checks ----------------------------------
        ;; COVER's own rules go here; each one adds its findings to
        ;; `lines` (and its verdict to the header dashboard below).
        ;; The blocks in the selection are already collected in `blks`
        ;; and every straight segment in `segs`.

        ;; --- restore colours (flagged/moved keep theirs) ------------
        ;; restored entities drop their rescue stash; flagged/moved
        ;; ones keep it so COVERCHECKRESCUE can clear the marks later
        (foreach pair saved
          (if (and (not (member (car pair) keep)) (entget (car pair)))
            (progn
              (cchk:set-color (car pair) (cdr pair))
              (cchk:unstash (car pair)))))
        (foreach l relock (cchk:set-layer-lock l T))
        (setq relock nil)

        ;; --- report on the right side, to scale with the drawing ----
        ;; text height picked from the drawing's extents so the whole
        ;; report roughly matches the drawing's height (MTEXT line
        ;; spacing is ~1.66 x text height), clamped so a short report
        ;; is not gigantic nor a long one unreadably small
        ;; all-clear lines are shorter, so weight them when sizing
        (setq nlin 3.0)                          ; title, legend, separator
        (foreach l lines
          (setq nlin (+ nlin (if (cchk:attn-p l) 1.0 *cchk-green-scale*))))
        (setq nlin (+ nlin (* 3.0 *cchk-green-scale*)))   ; the header dashboard
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
                  (> noflag 0))))
        (setq txt (strcat "COVERCHECK REPORT - " (cchk:datestr)
                          "\\P"
                          (cchk:small
                            (strcat "Items needing attention are shown in "
                                    (cchk:red "red") ", larger than the rest."))))
        (foreach pr hdr
          (setq txt (strcat txt "\\P"
                            (if (cdr pr)
                              (cchk:red (car pr))
                              (cchk:small (car pr))))))
        (setq txt (strcat txt "\\P"
                          (cchk:small "----------------------------------------")))
        (foreach l (reverse lines)
          (setq txt (strcat txt "\\P"
                            (if (cchk:attn-p l) (cchk:red l) (cchk:small l)))))
        (cchk:mtext ins h (* *cchk-report-chars* h) txt *cchk-report-layer*)

        ;; --- show the drawing plus the report -----------------------
        (if minx
          (progn
            (setq m (* 0.05 (max (- maxx minx) (- maxy miny) 1.0)))
            (command "_.ZOOM" "_Window"
                     (trans (list (- minx m) (- miny m) 0.0) 0 1)
                     (trans (list (+ (car ins) (* *cchk-report-chars* h) m)
                                  (+ maxy m) 0.0)
                            0 1)))
          (command "_.ZOOM" "_Center" vc vs))

        (command "_.UNDO" "_End")
        (setq undo-open nil)
        (setvar "CMDECHO" oldecho)
        (princ (strcat "\n\n--- COVERCHECK complete ---"
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
                       "\nReport placed on the right side of the drawing (layer "
                       *cchk-report-layer* ")."
                       (if (> ndmoved 0)
                         (strcat "\nConstruction lines through moved dimensions' original points are on layer "
                                 *cchk-constr-layer* ".")
                         "")
                       "\nOne UNDO reverts everything COVERCHECK changed (including the report)."))))))
  (princ))

;; --- COVERSCAN: the read-only twin -----------------------------------
;;  Runs every audit, asks nothing, and changes nothing in the drawing
;;  except writing the report. Use it as a quick pre-flight, or when
;;  you want the findings without touching a released sheet.

(defun c:COVERSCAN ( / *error* oldecho ss i e et ed cands dims arcs plns segs
                     blks lines olaps pr bb bad
                     nd ndbad na nabad h ins txt nlin ref hdr l
                     minx miny maxx maxy p13 p14 near s)

  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCOVERSCAN error: " msg)))
    (princ))

  (prompt "\nHighlight the drawing to COVERSCAN (Enter = whole drawing): ")
  (setq ss (ssget))
  (if (null ss) (setq ss (ssget "_X")))
  (cond
    ((null ss) (prompt "\nNothing to scan."))
    (t
     (setq oldecho (getvar "CMDECHO"))
     (setvar "CMDECHO" 0)
     (setq i 0 nd 0 ndbad 0 na 0 nabad 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (member et '("LINE" "LWPOLYLINE" "POLYLINE")) (setq plns (cons e plns)))
       (if (= et "INSERT") (setq blks (cons e blks)))
       (if (member et *cchk-curve-types*) (setq cands (cons e cands)))
       (setq bb (cchk:bbox e))
       (if bb
         (setq minx (if minx (min minx (caar bb)) (caar bb))
               miny (if miny (min miny (cadar bb)) (cadar bb))
               maxx (if maxx (max maxx (caadr bb)) (caadr bb))
               maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))
     (setq dims (reverse dims) arcs (reverse arcs)
           plns (reverse plns) blks (reverse blks) cands (reverse cands)
           segs (cchk:collect-segs plns))

     ;; --- dimensions: report stray definition points, move nothing
     (foreach e (cchk:sort-dims dims (if (and miny maxy) (* 0.05 (- maxy miny)) 1.0))
       (setq ed  (entget e)
             nd  (1+ nd)
             p13 (cdr (assoc 13 ed))
             p14 (cdr (assoc 14 ed))
             bad nil)
       (if (member (logand 7 (cdr (assoc 70 ed))) '(0 1))
         (foreach s (list (cons "point 1" p13) (cons "point 2" p14))
           (if (cdr s)
             (progn
               (setq near (cchk:nearest-curve (cdr s) nil cands))
               (if (and near (> (caddr near) *cchk-tol*))
                 (setq bad (append bad (list (strcat (car s) " off by "
                                                     (rtos (caddr near) 2 4))))))))))
       (if bad (setq ndbad (1+ ndbad)))
       (setq lines (cons (strcat "Dim " (cdr (assoc 5 ed))
                                 (if (= (cchk:dim-style e) "") ""
                                   (strcat " [" (cchk:dim-style e) "]"))
                                 (if (cchk:dim-meas e)
                                   (strcat " = " (cchk:dim-meas e)) "")
                                 ": "
                                 (if bad
                                   (strcat "NOT attached - " (cchk:join bad ", "))
                                   "OK")
                                 (if (cchk:dim-assoc-p e) " (associative)" ""))
                         lines)))

     ;; --- arcs: report unattached endpoints, move nothing
     (foreach e arcs
       (setq na  (1+ na)
             bad nil)
       (if (cchk:planar-arc-p (entget e))
         (foreach s '(("start" . start) ("end" . end))
           (if (cchk:arc-end-target e (cdr s) cands)
             (setq bad (append bad (list (car s)))))))
       (if bad (setq nabad (1+ nabad)))
       (setq lines (cons (strcat "Arc " (cdr (assoc 5 (entget e))) ": "
                                 (if bad
                                   (strcat (cchk:join bad " & ")
                                           " NOT attached to an object end")
                                   "endpoints OK"))
                         lines)))

     ;; --- overlaps
     (setq olaps (cchk:find-overlaps segs))
     (foreach pr olaps
       (setq lines (cons (strcat "Lines "
                                 (cdr (assoc 5 (entget (cchk:seg-ent (car pr)))))
                                 "+"
                                 (cdr (assoc 5 (entget (cchk:seg-ent (cadr pr)))))
                                 ": OVERLAP of "
                                 (rtos (caddr (cchk:overlap-info (car pr) (cadr pr))))
                                 " - flagged")
                         lines)))

     ;; --- cover-specific checks (read-only twins of COVERCHECK's) ---

     ;; --- report (the only thing COVERSCAN writes) ------------------
     (cchk:ensure-layer *cchk-report-layer* *cchk-report-color*)
     (cchk:clear-old)
     (setq hdr (list
                 (cons (strcat "Dimensions scanned: " (itoa nd) " ("
                               (itoa ndbad) " with a stray definition point)")
                       (> ndbad 0))
                 (cons (strcat "Arcs scanned: " (itoa na) " ("
                               (itoa nabad) " with an unattached end)")
                       (> nabad 0))
                 (cons (strcat "Overlapping line pairs: " (itoa (length olaps)))
                       (> (length olaps) 0))))
     (setq nlin 3.0)
     (foreach l lines
       (setq nlin (+ nlin (if (cchk:attn-p l) 1.0 *cchk-green-scale*))))
     (setq nlin (+ nlin (* 3.0 *cchk-green-scale*)))
     (if (and minx (> (max (- maxy miny) (- maxx minx)) 1e-8))
       (progn
         (setq ref (max (- maxy miny) (* 0.25 (- maxx minx)))
               h   (/ ref (* 1.66 nlin)))
         (if (> h (/ ref 30.0))  (setq h (/ ref 30.0)))
         (if (< h (/ ref 200.0)) (setq h (/ ref 200.0))))
       (setq h 2.5))
     (setq ins (if minx
                 (list (+ maxx (* 0.05 (max (- maxx minx) 1.0))) maxy 0.0)
                 (list 0.0 0.0 0.0)))
     (setq txt (strcat "COVERSCAN REPORT - " (cchk:datestr)
                       "\\P"
                       (cchk:small (strcat "Read-only scan - nothing in the drawing was changed. "
                                           "Items needing attention are shown in "
                                           (cchk:red "red") "."))))
     (foreach pr hdr
       (setq txt (strcat txt "\\P" (if (cdr pr) (cchk:red (car pr))
                                     (cchk:small (car pr))))))
     (setq txt (strcat txt "\\P" (cchk:small "----------------------------------------")))
     (foreach l (reverse lines)
       (setq txt (strcat txt "\\P" (if (cchk:attn-p l) (cchk:red l) (cchk:small l)))))
     (cchk:mtext ins h (* *cchk-report-chars* h) txt *cchk-report-layer*)
     (setvar "CMDECHO" oldecho)
     (princ (strcat "\n--- COVERSCAN complete (read-only) ---"
                    "\nDimensions: " (itoa nd) " scanned, " (itoa ndbad) " with a stray point"
                    "\nArcs: " (itoa na) " scanned, " (itoa nabad) " with an unattached end"
                    "\nOverlapping line pairs: " (itoa (length olaps))
                    "\nReport written on layer " *cchk-report-layer*
                    "; nothing else was changed."))))
  (princ))

(princ "\ncovercheck.lsp loaded - COVERCHECK reviews dimensions & arcs one at a time,")
(princ "\n  COVERSCAN reports everything read-only, COVERCHECKRESCUE undoes COVERCHECK's marks.")
(princ)
