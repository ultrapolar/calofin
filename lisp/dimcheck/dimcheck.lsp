;;; ------------------------------------------------------------------
;;;  dimcheck.lsp -- DIMCHECK: dims, arcs & overlaps QA review
;;;
;;;  The lean pass -- dimension placement, arc-end attachment, and
;;;  overlapping lines, with nothing else touched. For the full
;;;  liner-finish review (this plus steps/side views, wall height,
;;;  the liner pattern, and the title block border), load
;;;  linfincheck.lsp instead and run LINFINCHECK; it shares this
;;;  file's Move/Keep/Pick review and report machinery. Type DIMCHECK,
;;;  then:
;;;
;;;  1. You are asked to highlight the drawing (any selection).
;;;     Everything selected is greyed out so only the item under
;;;     review stands out.
;;;
;;;  2. Dimensions are reviewed ONE AT A TIME, in a fixed marching
;;;     order: grouped by dimension style -- "STANDARD", then "SIDE
;;;     STANDARD", then "STANDARD INCHES", then "CROSS DIMENSIONS",
;;;     then whatever styles are left (tune *dchk-style-order*) --
;;;     and inside each group left to right, top to bottom (row by
;;;     row, like reading). Each dimension is zoomed to, shown in
;;;     its own colour and highlighted while the rest stays grey.
;;;     For linear/aligned dimensions the two definition points are
;;;     audited first: a point that does not sit on any object is
;;;     shown where DIMCHECK thinks it belongs, with BOTH spots
;;;     marked on screen and spelled out so there is no doubt which
;;;     is which --
;;;         a RED X   where you drew it,
;;;         a GREEN + where we would move it, joined by a line.
;;;     You then choose, one point at a time:
;;;         Enter / M  ->  MOVE it onto the nearest object (green +)
;;;         K          ->  KEEP it exactly where you drew it (red X);
;;;                        the point is put back and nothing changes
;;;         P          ->  PICK the spot yourself
;;;     A point TWO OR MORE DIMENSIONS measure to is an ANCHOR and is
;;;     never questioned, even with no geometry under it: dimensioning
;;;     twice to the same spot -- the pair of dims pinning down a
;;;     hypotenuse corner is the everyday case -- is how you say that
;;;     spot is the object. Anchors are read off the selection before
;;;     the review starts, so one cannot come and go partway through,
;;;     and a stray point nearer an anchor than any line is offered the
;;;     anchor instead of being dragged off to the line.
;;;     A construction line (XLINE) is drawn through the dimension's
;;;     original points on layer DIMCHECK-CONSTRUCTION so you can see
;;;     where it used to measure -- only when a point actually moved.
;;;     Then the overall question for every dimension:
;;;         "Is this dimension correct?"
;;;         Enter / Y  ->  correct, the dimension is left alone
;;;         N          ->  the dimension is recoloured RED so it is
;;;                        easy to find and fix afterwards
;;;         B          ->  back one dimension, redo it
;;;         S          ->  skip the rest, still write the report
;;;
;;;  3. Arcs are reviewed the same way, one endpoint at a time, with
;;;     the same Move / Keep / Pick choice. An endpoint not attached
;;;     to the end of another object is snapped there and both spots
;;;     are marked; Keep puts the arc back exactly as you drew it
;;;     (its original shape is restored, not re-fitted), Pick re-fits
;;;     it through your spot. Arcs whose endpoints actually changed
;;;     are recoloured MAGENTA -- an arc you kept is left alone.
;;;
;;;  4. OVERLAPPING LINES are hunted down: two straight LINE entities
;;;     (or polyline edges) that are collinear and run on top of each
;;;     other (a leftover from drawing over an existing line to
;;;     continue it and never cleaning it up). Each overlapping pair
;;;     is zoomed to and highlighted, the overlapping stretch is
;;;     marked with crosses, and you choose:
;;;         Enter / M  ->  MERGE the two into one line spanning both
;;;                        (only when they are two whole LINEs on one
;;;                        layer; the merged line turns CYAN)
;;;         F          ->  FLAG both CYAN to fix by hand
;;;         L          ->  LEAVE them as drawn (intentional)
;;;     Lines that merely touch end-to-end are fine and not reported.
;;;
;;;  5. A DIMCHECK REPORT (MTEXT) is placed to the RIGHT of the
;;;     drawing on layer DIMCHECK-REPORT listing every dimension --
;;;     with its measured distance (in the drawing's units; angular
;;;     dims show their angle) -- every arc, and every overlapping
;;;     line pair (with its overlap length), plus totals. The report
;;;     text is sized from the drawing's extents so it sits to scale
;;;     next to it. Any line describing something questionable (a
;;;     flagged/moved item, a skipped check) is coloured RED in the
;;;     report; everything that checked out stays the report's normal
;;;     colour and is drawn at *dchk-green-scale* (3/4) of the red
;;;     text's height, so the problems are the big lines on the sheet.
;;;
;;;  All original colours are restored when the review ends -- except
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
;;;    points are moved -- an associative point may re-anchor on its
;;;    own -- and their report line says so in red.
;;;  - Rerunning DIMCHECK replaces the previous report and marker
;;;    lines instead of stacking a second copy on top.
;;;  - Original colours are stashed in xdata before greying. If a
;;;    crash or kill ever leaves the drawing grey, DIMCHECKRESCUE
;;;    restores every stashed colour and clears DIMCHECK's report
;;;    and markers (flag colours included -- it is the full reset).
;;;  - Loading both dimcheck.lsp and linfincheck.lsp in the same
;;;    session is safe: distinct dchk:/lfc: function prefixes,
;;;    *dchk-/*lfc- globals, layer names and xdata tags mean neither
;;;    tool's rescue command touches the other's markers.
;;; ------------------------------------------------------------------

(vl-load-com)

;; ---- configuration -------------------------------------------------
(setq *dchk-version* "v1.12")        ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it

(defun c:DIMCHECKVER ()
  (princ (strcat "\nDIMCHECK " *dchk-version*))
  (princ))

;; --- tunables ------------------------------------------------------
(setq *dchk-tol*          1.0e-4)  ; max gap (drawing units) that still counts as attached
(setq *dchk-grey-color*   8)       ; grey used to fade out everything not under review
(setq *dchk-flag-color*   1)       ; red: dimensions you answered "No" to
(setq *dchk-arc-color*    6)       ; magenta: arcs whose endpoints were moved
(setq *dchk-olap-color*   4)       ; cyan: merged or flagged overlapping lines
(setq *dchk-olap-fuzz*    1.0e-4)  ; max sideways offset that still counts as "same line"
(setq *dchk-constr-layer* "DIMCHECK-CONSTRUCTION")
(setq *dchk-constr-color* 2)       ; yellow
(setq *dchk-green-scale*  0.75)    ; report: all-clear text height, as a fraction of the red text
(setq *dchk-orig-color*   1)       ; red X: where you drew the point
(setq *dchk-sugg-color*   3)       ; green +: where DIMCHECK would move it
(setq *dchk-report-layer* "DIMCHECK-REPORT")
(setq *dchk-report-color* 3)       ; green
(setq *dchk-zoom-margin*  0.75)    ; empty space around the zoomed item (fraction of its size)
(setq *dchk-report-chars* 45.0)    ; report column width, in text heights
(setq *dchk-ask-all-arc-ends* nil) ; T = confirm EVERY arc endpoint, even already-attached ones
(setq *dchk-anchor-tol*   1.0e-4)  ; how close two dimension points must be to count as the same spot
(setq *dchk-anchor-min*   2)       ; that many dimensions meeting there make it an anchor

;; dimension styles are reviewed in this order; styles not listed
;; come afterwards ("whatever else is left"), still left-to-right
(setq *dchk-style-order*
      '("STANDARD" "SIDE STANDARD" "STANDARD INCHES" "CROSS DIMENSIONS"))

;; entity types dimension points and arc ends may attach to
(setq *dchk-curve-types*
      '("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"))

;; --- safety: xdata tags, colour stash, layer locks -----------------

(defun dchk:regapp ()
  (if (not (tblsearch "APPID" "DIMCHECK"))
    (regapp "DIMCHECK")))

(defun dchk:xd (ent / g)
  ;; DIMCHECK's xdata groups on ent, nil when none
  (setq g (assoc -3 (entget ent '("DIMCHECK"))))
  (if g (cdadr g)))

(defun dchk:tag (ent kind / ed)
  ;; stamp a DIMCHECK-created entity (report, marker line) so a rerun
  ;; or DIMCHECKRESCUE can find and clear it
  (dchk:regapp)
  (setq ed (entget ent '("DIMCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "DIMCHECK" (cons 1000 kind))))))))

(defun dchk:stash-color (ent col / ed)
  ;; remember the entity's own colour in xdata so DIMCHECKRESCUE can
  ;; put it back even after a crash; an existing stash (from an
  ;; interrupted run - the TRUE original) is never overwritten
  (dchk:regapp)
  (setq ed (entget ent '("DIMCHECK")))
  (if (and ed (not (assoc -3 ed)))
    (entmod (append ed (list (list -3 (list "DIMCHECK"
                                            '(1000 . "COLOR")
                                            (cons 1071 col))))))))

(defun dchk:unstash (ent / ed)
  ;; drop DIMCHECK's xdata once the run has restored things itself
  (setq ed (entget ent '("DIMCHECK")))
  (if (and ed (assoc -3 ed))
    (entmod (subst (list -3 (list "DIMCHECK")) (assoc -3 ed) ed))))

(defun dchk:clear-old (/ ss2 i e xd n)
  ;; erase the report and marker lines left by an earlier DIMCHECK
  ;; run, so a rerun replaces them instead of stacking on top
  (setq ss2 (ssget "_X" '((-3 ("DIMCHECK")))) n 0 i 0)
  (if ss2
    (repeat (sslength ss2)
      (setq e  (ssname ss2 i)
            i  (1+ i)
            xd (dchk:xd e))
      (if (member (cdr (assoc 1000 xd)) '("REPORT" "XLINE"))
        (progn (entdel e) (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\n(Removed " (itoa n)
                   " report/marker item(s) from an earlier DIMCHECK run.)"))))

(defun dchk:layer-locked-p (name / ld)
  (setq ld (tblsearch "LAYER" name))
  (and ld (= 4 (logand 4 (cdr (assoc 70 ld))))))

(defun dchk:set-layer-lock (name lock / ed old new)
  ;; set or clear a layer's locked flag; T when it actually changed
  (setq ed  (entget (tblobjname "LAYER" name))
        old (cdr (assoc 70 ed))
        new (if lock (logior old 4) (logand old (~ 4))))
  (if (/= old new)
    (progn (entmod (subst (cons 70 new) (assoc 70 ed) ed)) T)))

(defun dchk:dim-assoc-p (ent / found g)
  ;; T when the dimension carries persistent reactors - the mark of
  ;; an object-associative dim, whose definition points may re-anchor
  ;; on their own after being moved
  (foreach g (entget ent)
    (if (and (= 102 (car g)) (= "{ACAD_REACTORS" (cdr g)))
      (setq found T)))
  found)

(defun c:DIMCHECKRESCUE ( / *error* undo-open ss i e xd n)
  ;; entdel/entmod over the whole drawing was N undos deep and
  ;; had no handler at all -- now one group, closed on both exits,
  ;; and a cancel that says nothing
  (defun *error* (msg)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nDIMCHECKRESCUE error: " msg)))
    (princ))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") (setq undo-open T)))
  ;; the way out after a crash or interrupted run: puts back every
  ;; colour DIMCHECK stashed (flag colours included) and removes its
  ;; report and marker lines
  (setq ss (ssget "_X" '((-3 ("DIMCHECK")))) n 0 i 0)
  (if ss
    (repeat (sslength ss)
      (setq e  (ssname ss i)
            i  (1+ i)
            xd (dchk:xd e))
      (cond
        ((member (cdr (assoc 1000 xd)) '("REPORT" "XLINE"))
         (entdel e)
         (setq n (1+ n)))
        ((assoc 1071 xd)
         (dchk:set-color e (cdr (assoc 1071 xd)))
         (dchk:unstash e)
         (setq n (1+ n))))))
  (if (> n 0)
    (princ (strcat "\nDIMCHECKRESCUE: restored or removed " (itoa n) " item(s)."))
    (princ "\nDIMCHECKRESCUE: nothing to restore - no DIMCHECK markers in the drawing."))
  (if undo-open (progn (command "_.UNDO" "_End") (setq undo-open nil)))
  (princ))

;; --- small helpers -------------------------------------------------

;; Create the report layer, or - when it already exists - make sure it
;; is on, thawed and unlocked (STANDARDS section 5).  The shared build
;; has repaired for a while (cal:ensure-layer); without it here a report
;; written onto a frozen report layer is silently invisible.
(defun dchk:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   '(70 . 0)
                   (cons 62 color)
                   '(6 . "Continuous")))
    (progn
      (setq rec   (tblobjname "LAYER" name)
            ed    (entget rec)
            flags (cdr (assoc 70 ed))
            col   (cdr (assoc 62 ed))
            fixed nil)
      (if (/= 0 (logand 5 flags))          ; frozen (1) or locked (4)
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)                        ; layer switched off
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nDIMCHECK: layer " name
                         " was off, frozen or locked - restored so the"
                         " report is visible.")))))))

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
  ;; infinite construction line through p1-p2 on the check layer,
  ;; tagged so reruns and DIMCHECKRESCUE can clear it
  (setq len (distance p1 p2))
  (if (and (> len 1e-8)
           (entmake (list '(0 . "XLINE")
                          '(100 . "AcDbEntity")
                          (cons 8 *dchk-constr-layer*)
                          '(100 . "AcDbXline")
                          (cons 10 p1)
                          (cons 11 (mapcar '(lambda (x) (/ x len))
                                           (mapcar '- p2 p1))))))
    (dchk:tag (entlast) "XLINE")))

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
  ;; bring an entity back to its own colour for review -- unless it
  ;; already wears a DIMCHECK marker colour it must not lose
  (if (and (entget ent) (not (member ent keep)))
    (dchk:set-color ent (cdr (assoc ent saved)))))

(defun dchk:unstage (ent keep)
  ;; send a reviewed entity back into the grey background
  (if (and (entget ent) (not (member ent keep)))
    (dchk:set-color ent *dchk-grey-color*)))

(defun dchk:mark-x (pt col / p s)
  ;; diagonal cross - marks WHERE YOU DREW IT
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (- (cadr p) s)) (list (+ (car p) s) (+ (cadr p) s)) col 1)
  (grdraw (list (- (car p) s) (+ (cadr p) s)) (list (+ (car p) s) (- (cadr p) s)) col 1))

(defun dchk:mark-plus (pt col / p s)
  ;; upright cross - marks WHERE DIMCHECK WOULD PUT IT
  (setq p (trans pt 0 1)
        s (* 0.02 (getvar "VIEWSIZE")))
  (grdraw (list (- (car p) s) (cadr p)) (list (+ (car p) s) (cadr p)) col 1)
  (grdraw (list (car p) (- (cadr p) s)) (list (car p) (+ (cadr p) s)) col 1))

(defun dchk:mark-point (pt)
  ;; both strokes, for a point that is simply being pointed out
  (dchk:mark-x pt 2)
  (dchk:mark-plus pt 2))

(defun dchk:ask-yn (msg / ans)
  ;; T = yes (Enter or Y), nil = no (N)
  (initget "Yes No")
  (setq ans (getkword (strcat msg " [Yes/No] <Yes>: ")))
  (or (null ans) (= ans "Yes")))

(defun dchk:ask-yn-nav (msg / ans)
  ;; the reviewing question, with a way out of a mis-press:
  ;; 'yes 'no 'back (redo the previous item) 'skip (stop asking,
  ;; finish the run and still write the report)
  (initget "Yes No Back Skip Undo")   ; Undo = hidden synonym for Back
  ;; the bracket is exactly the keyword list (STANDARDS section 1 rule
  ;; 1): a click sends the bracket text, and "Skip rest" was a click
  ;; the initget list could not accept
  (setq ans (getkword (strcat msg " [Yes/No/Back/Skip] <Yes>: ")))
  (cond ((null ans)      'yes)
        ((= ans "Yes")   'yes)
        ((= ans "No")    'no)
        ((= ans "Back")  'back)
        ((= ans "Undo")  'back)
        (t               'skip)))

(defun dchk:confirm-move (label orig sugg what / ans newp)
  ;; The point has been put where DIMCHECK thinks it belongs, but BOTH
  ;; spots are marked and spelled out so there is no doubt which is
  ;; which: a red X where you drew it, a green + where we would move
  ;; it, joined by a line. WHAT names what the green + sits on, so a
  ;; move onto a shared anchor point does not claim to be an object.
  ;; Returns
  ;;   'move - take our suggestion
  ;;   'keep - put it back exactly where you drew it
  ;;   <point> - a spot you picked yourself (current UCS)
  (dchk:mark-x    orig *dchk-orig-color*)
  (dchk:mark-plus sugg *dchk-sugg-color*)
  (if (> (distance orig sugg) 1e-8)
    (grdraw (trans orig 0 1) (trans sugg 0 1) *dchk-sugg-color* 1))
  (princ (strcat "\n  " label " - which spot is right?"
                 "\n    Keep = where you drew it   " (dchk:ptstr orig)
                 "  (red X)"
                 "\n    Move = onto " what " " (dchk:ptstr sugg)
                 "  (green +), " (rtos (distance orig sugg) 2 4) " away"
                 "\n    Pick = somewhere else you point at"))
  (initget "Move Keep Pick")
  (setq ans (getkword
              "\n  [Move/Keep/Pick] <Move>: "))
  (cond
    ((or (null ans) (= ans "Move")) 'move)
    ((= ans "Keep") 'keep)
    (t (setq newp (getpoint (strcat "\n  Pick the spot for " label
                                    " <Move to the green +>: ")))
       (if newp newp 'move))))

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
  (if (entmake (append dxf (list (cons 1 text))))
    (dchk:tag (entlast) "REPORT")))

(defun dchk:join (lst sep / out s)
  ;; "A" + "B" + ... joined with sep
  (foreach s lst
    (setq out (if out (strcat out sep s) s)))
  out)

(defun dchk:attn-p (s)
  ;; T when a report line describes something questionable or that
  ;; needs looking over / fixing, so the report renders it in red
  (wcmatch (strcase s)
    "*FLAGGED*,*SKIPPED*,*MAGENTA*,*ASSOCIATIVE*,*NOT ATTACHED*,*OVERLAP*"))

(defun dchk:red (s)
  ;; wrap an MTEXT run so it renders in the flag colour, reverting
  ;; to the surrounding colour after (braces scope the change)
  (strcat "{\\C" (itoa *dchk-flag-color*) ";" s "}"))

(defun dchk:small (s)
  ;; all-clear text renders at *dchk-green-scale* of the height the
  ;; red attention text gets, so problems stand out on the sheet
  (strcat "{\\H" (rtos *dchk-green-scale* 2 4) "x;" s "}"))

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

;; --- overlap detection ----------------------------------------------

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

(defun dchk:overlap-info (la lb / a1 a2 b1 b2 u lena s1 s2 tmp lo hi)
  ;; when segments la and lb are collinear (within *dchk-olap-fuzz*)
  ;; and run on top of each other for more than *dchk-tol*, returns
  ;;   (ov-start ov-end ov-length union-start union-end)
  ;; nil when they do not overlap (touching end-to-end is fine)
  (setq a1 (dchk:seg-p1 la)
        a2 (dchk:seg-p2 la)
        b1 (dchk:seg-p1 lb)
        b2 (dchk:seg-p2 lb)
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
  ;; stretch la's LINE over the union of both, delete lb's LINE
  (setq ed (entget (dchk:seg-ent la))
        ed (subst (cons 10 (nth 3 info)) (assoc 10 ed) ed)
        ed (subst (cons 11 (nth 4 info)) (assoc 11 ed) ed))
  (entmod ed)
  (entupd (dchk:seg-ent la))
  (entdel (dchk:seg-ent lb)))

(defun dchk:whole-line-p (s / ed)
  ;; T when the segment IS its owner entity - only whole LINEs can be
  ;; merged; a polyline edge has to be fixed by hand
  (setq ed (entget (dchk:seg-ent s)))
  (= "LINE" (cdr (assoc 0 ed))))

;; --- segments: lines AND polyline edges ----------------------------
;; Detection works on "segs" - (start end owner-entity) records - so a
;; run of overlapping geometry drawn as ONE polyline counts exactly
;; like the same shape drawn as separate LINEs.

(defun dchk:seg-p1 (s) (car s))

(defun dchk:seg-p2 (s) (cadr s))

(defun dchk:seg-ent (s) (caddr s))

(defun dchk:ocs->wcs (p nz)
  (if (and nz (not (equal nz '(0.0 0.0 1.0) 1e-9))) (trans p nz 0) p))

(defun dchk:lwpoly-segs (ent / ed nz elev vs bl cls n i segs g)
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
       (setq vs (cons (dchk:ocs->wcs (list (car (cdr g)) (cadr (cdr g)) elev) nz) vs)
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

(defun dchk:heavy-poly-segs (ent / e ed vs bl cls n i segs)
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

(defun dchk:ent-segs (ent / ed et)
  ;; every straight segment an entity contributes, in WCS
  (setq ed (entget ent)
        et (cdr (assoc 0 ed)))
  (cond
    ((= et "LINE")       (list (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed)) ent)))
    ((= et "LWPOLYLINE") (dchk:lwpoly-segs ent))
    ((= et "POLYLINE")   (dchk:heavy-poly-segs ent))))

(defun dchk:collect-segs (ents / segs e s)
  ;; all straight segments of a list of entities, longer than the
  ;; attachment tolerance (zero-length stubs help nothing)
  (foreach e ents
    (if (entget e)
      (foreach s (dchk:ent-segs e)
        (if (> (distance (car s) (cadr s)) *dchk-tol*)
          (setq segs (cons s segs))))))
  (reverse segs))

(defun dchk:seg-dir-ang (s / a)
  ;; segment direction folded into [0, pi)
  (setq a (angle (dchk:seg-p1 s) (dchk:seg-p2 s)))
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

(defun dchk:find-overlaps (segs / atol fams a placed fam recs e p1 p2 dx dy
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
    (setq a      (dchk:seg-dir-ang e)
          placed nil)
    (foreach fam fams
      (if (and (not placed)
               (or (<= (dchk:ang-diff a (car fam)) atol)))
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
          (setq p1  (dchk:seg-p1 e)
                p2  (dchk:seg-p2 e)
                off (- (* (cadr p1) dx) (* (car p1) dy))
                s1  (+ (* (car p1) dx) (* (cadr p1) dy))
                s2  (+ (* (car p2) dx) (* (cadr p2) dy)))
          (if (> s1 s2) (setq tmp s1 s1 s2 s2 tmp))
          (setq recs (cons (list off s1 s2 e) recs)))
        (setq recs (dchk:sort-recs recs))
        ;; sorted by offset: only sweep forward while still collinear
        (while recs
          (setq r    (car recs)
                rest (cdr recs))
          (while (and rest
                      (<= (- (car (car rest)) (car r)) *dchk-olap-fuzz*))
            (setq q (car rest))
            (if (and (not (eq (dchk:seg-ent (cadddr r))
                              (dchk:seg-ent (cadddr q))))
                     ;; spans must actually meet before the exact test
                     (> (min (caddr r) (caddr q)) (max (cadr r) (cadr q)))
                     (dchk:overlap-info (cadddr r) (cadddr q)))
              (progn
                (setq key (list (dchk:seg-ent (cadddr r))
                                (dchk:seg-ent (cadddr q))))
                (if (not (member key seen))
                  (setq seen  (cons key (cons (reverse key) seen))
                        pairs (cons (list (cadddr r) (cadddr q)) pairs)))))
            (setq rest (cdr rest)))
          (setq recs (cdr recs))))))
  (reverse pairs))

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
    (t (< (cadr r1) (cadr r2)))))

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

(defun dchk:dim-def-pts (ent / ed dtype p13 p14)
  ;; the two definition points of a linear/aligned dimension (the ones
  ;; the audit moves); nil for every other kind of dimension
  (setq ed    (entget ent)
        dtype (logand 7 (cdr (assoc 70 ed))))
  (if (member dtype '(0 1))
    (progn
      (setq p13 (cdr (assoc 13 ed))
            p14 (cdr (assoc 14 ed)))
      (append (if p13 (list p13)) (if p14 (list p14))))))

(defun dchk:shared-anchors (dims / recs r e p found out)
  ;; Every spot where *dchk-anchor-min* or more DIMENSIONS put a
  ;; definition point.  Dimensioning twice to the same spot is how a
  ;; drafter says that spot matters -- the usual case is the pair of
  ;; dims that pin down a hypotenuse corner, which is a point in space
  ;; with no line running through it.  DIMCHECK treats such a spot as
  ;; an object: it is never questioned, and a stray point beside it
  ;; can be offered a move onto it.
  ;; Collected once, from the drawing as selected, so a point cannot
  ;; stop being an anchor partway through the review.
  ;; Returns the anchor points (WCS).
  (foreach e dims
    (foreach p (dchk:dim-def-pts e)
      (setq found nil)
      (foreach r recs
        (if (and (null found) (<= (distance p (car r)) *dchk-anchor-tol*))
          (setq found r)))
      (cond
        ((null found) (setq recs (cons (list p e) recs)))
        ;; a dimension's own two points landing together is one
        ;; dimension, not two -- it takes two to make an anchor
        ((not (member e (cdr found)))
         (setq recs (subst (cons (car found) (cons e (cdr found)))
                           found recs))))))
  (foreach r recs
    (if (>= (length (cdr r)) *dchk-anchor-min*)
      (setq out (cons (car r) out))))
  out)

(defun dchk:audit-dim-point (ent gcode label cands anchors
                             / ed pt near anch dnear danch sugg dsug what
                               ans final how)
  ;; audits one definition point: an off-object point is put where it
  ;; looks like it belongs, then you choose - Move (take it), Keep
  ;; (put it back exactly where you drew it) or Pick your own spot.
  ;; A point another dimension also measures to is an ANCHOR (see
  ;; dchk:shared-anchors): it counts as an object, so it is left alone
  ;; without a question, and a stray point nearer an anchor than any
  ;; line is offered the anchor instead of being dragged off to the
  ;; line.
  ;; Returns (original final how) when the point was looked at, where
  ;; how is 'auto / 'user / 'kept / 'anchor; nil when the point was
  ;; already fine.
  (setq ed (entget ent)
        pt (cdr (assoc gcode ed)))
  (if pt
    (progn
      (setq near  (dchk:nearest-curve pt nil cands)
            dnear (if near (caddr near))
            anch  (dchk:closest-of pt anchors)
            danch (if anch (distance pt anch)))
      (cond
        ;; a point sitting on an object needs no defending, shared or not
        ((and dnear (<= dnear *dchk-tol*)) nil)
        ;; ...and one that isn't is still fine if another dimension
        ;; measures to it too: that spot is settled, whether or not any
        ;; geometry runs through it
        ((and danch (<= danch *dchk-anchor-tol*))
         (princ (strcat "\n  " label " is shared with another dimension"
                        " - treated as an anchor point, left as drawn."))
         (list pt pt 'anchor))
        (t
         ;; otherwise the nearer of the two homes it could have: a line
         ;; to sit on, or an anchor it was very nearly snapped to
         (cond
           ((and danch (or (null dnear) (< danch dnear)))
            (setq sugg anch  dsug danch  what "the shared anchor point"))
           (near
            (setq sugg (cadr near)  dsug dnear  what "the nearest object")))
         (if (and sugg (> dsug *dchk-tol*))
           (progn
             ;; show the suggestion in place, but keep the original spot
             ;; marked so both are on screen while the question is asked
             (entmod (subst (cons gcode sugg) (assoc gcode ed) ed))
             (entupd ent)
             (princ (strcat "\n  " label " is not on any object - " what
                            " is " (rtos dsug 2 4) " away."))
             (setq ans (dchk:confirm-move label pt sugg what))
             (cond
               ((eq ans 'move)
                (setq final sugg
                      how   'auto)
                (princ (strcat "\n  " label " MOVED onto " what ", "
                               (dchk:ptstr final) ".")))
               ((eq ans 'keep)
                (setq ed    (entget ent)
                      final pt
                      how   'kept)
                (entmod (subst (cons gcode pt) (assoc gcode ed) ed))
                (entupd ent)
                (princ (strcat "\n  " label " KEPT where you drew it, "
                               (dchk:ptstr final) " - nothing changed.")))
               (t
                (setq final (trans ans 1 0)
                      how   'user
                      ed    (entget ent))
                (entmod (subst (cons gcode final) (assoc gcode ed) ed))
                (entupd ent)
                (princ (strcat "\n  " label " moved to the spot you picked, "
                               (dchk:ptstr final) "."))))
             (redraw)
             (list pt final how))))))))

(defun dchk:review-dim (ent cands anchors num total / ed dtype h sty p13 p14
                                              r1 r2 looked moved kept held
                                              ok note meas assocnote)
  ;; interactive review of one dimension.
  ;; Returns (handle ok-flag report-note moved-point-count measurement
  ;; anchor-held-point-count).
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
      (if (dchk:dim-assoc-p ent)
        (princ "\n  Note: this dimension is object-associative - a moved point may re-anchor on its own."))
      (setq p13 (cdr (assoc 13 ed))           ; the two dimmed points
            p14 (cdr (assoc 14 ed))
            r1  (dchk:audit-dim-point ent 13 "dimension point 1" cands anchors)
            r2  (dchk:audit-dim-point ent 14 "dimension point 2" cands anchors))))
  ;; a point held at a shared anchor was looked at and deliberately not
  ;; touched - it is neither a move nor a Keep answer, so it is counted
  ;; on its own and kept out of both tallies
  (setq looked (append (if r1 (list r1)) (if r2 (list r2)))
        held   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'anchor)) looked)
        moved  (vl-remove-if '(lambda (x) (member (caddr x) '(kept anchor)))
                             looked)
        kept   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'kept)) looked))
  ;; only when something actually moved is there an old position worth
  ;; drawing a construction line through
  (if moved (dchk:make-xline p13 p14))        ; through the ORIGINAL points
  (if (and moved (dchk:dim-assoc-p ent))
    (setq assocnote " (ASSOCIATIVE - verify the moved point holds)"))
  (setq meas (dchk:dim-meas ent))             ; after any point moves
  (if meas (princ (strcat "\n  Measures " meas ".")))
  (redraw ent 3)
  (setq ok (dchk:ask-yn-nav "\n  Is this dimension correct?"))
  (redraw ent 4)
  (redraw)
  (if (member ok '(back skip))
    (list h ok nil (length moved) meas (length held))  ; navigation: caller handles it
    (progn
      (setq ok (eq ok 'yes))
      (setq note (strcat
                   (if ok "OK" "FLAGGED to fix (red)")
                   (if moved
                     (strcat " - " (itoa (length moved))
                             " point(s) moved onto the nearest object/anchor")
                     "")
                   (if kept
                     (strcat " - " (itoa (length kept))
                             " point(s) kept where you drew them")
                     "")
                   (if held
                     (strcat " - " (itoa (length held))
                             " point(s) held at a shared anchor")
                     "")
                   (if assocnote assocnote "")))
      (if (not ok) (dchk:set-color ent *dchk-flag-color*))
      (list h ok note (length moved) meas (length held)))))

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

(defun dchk:arc-state (ent / ed)
  ;; the groups that define an arc's shape, for an exact put-it-back
  (setq ed (entget ent))
  (list (assoc 10 ed) (assoc 40 ed) (assoc 50 ed) (assoc 51 ed)))

(defun dchk:arc-restore (ent st / ed g)
  ;; restore a saved shape exactly, rather than re-fitting back to it
  (setq ed (entget ent))
  (foreach g st (setq ed (subst g (assoc (car g) ed) ed)))
  (entmod ed)
  (entupd ent))

(defun dchk:review-arc-end (ent which label cands / p target st ans final how)
  ;; audits one arc endpoint: a detached end is snapped where it looks
  ;; like it belongs, then you choose - Move (take it), Keep (put the
  ;; arc back exactly as drawn) or Pick your own spot.
  ;; Returns (original final how) when the end was looked at, where how
  ;; is 'auto / 'user / 'kept; nil when the end was already fine.
  (setq p      (if (eq which 'start)
                 (vlax-curve-getStartPoint ent)
                 (vlax-curve-getEndPoint ent))
        target (dchk:arc-end-target ent which cands)
        st     (dchk:arc-state ent))
  (cond
    (target
     (if (dchk:move-arc-end ent which target)
       (progn
         (princ (strcat "\n  " label " is not attached to an object end - nearest is "
                        (rtos (distance p target) 2 4) " away."))
         (setq ans (dchk:confirm-move label p target "the object end"))
         (cond
           ((eq ans 'move)
            (setq final target
                  how   'auto)
            (princ (strcat "\n  " label " SNAPPED to the object end, "
                           (dchk:ptstr final) ".")))
           ((eq ans 'keep)
            (dchk:arc-restore ent st)
            (setq final p
                  how   'kept)
            (princ (strcat "\n  " label " KEPT where you drew it, "
                           (dchk:ptstr final) " - the arc is unchanged.")))
           (t
            (setq ans (trans ans 1 0))
            (if (dchk:move-arc-end ent which ans)
              (progn
                (setq final ans
                      how   'user)
                (princ (strcat "\n  " label " moved to the spot you picked, "
                               (dchk:ptstr final) ".")))
              (progn
                (setq final target
                      how   'auto)
                (princ "\n  Could not re-fit the arc through that spot (collinear?); left it on the object end.")))))
         (redraw)
         (list p final how))
       (progn
         (princ (strcat "\n  " label " should attach at " (dchk:ptstr target)
                        " but the arc could not be re-fitted (points collinear?)."))
         nil)))
    (*dchk-ask-all-arc-ends*                  ; optional: confirm attached ends too
     (setq ans (dchk:confirm-move label p p "where it already is"))
     (redraw)
     (if (member ans '(move keep))
       nil
       (progn
         (setq ans (trans ans 1 0))
         (if (dchk:move-arc-end ent which ans)
           (list p ans 'user)
           (progn
             (princ "\n  Could not re-fit the arc through that spot (collinear?); unchanged.")
             nil)))))
    (t nil)))

(defun dchk:review-arc (ent cands num total / ed h planar r1 r2 looked moved kept note)
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
  (setq looked (append (if r1 (list r1)) (if r2 (list r2)))
        moved  (vl-remove-if '(lambda (x) (eq (caddr x) 'kept)) looked)
        kept   (vl-remove-if-not '(lambda (x) (eq (caddr x) 'kept)) looked))
  (if moved (dchk:set-color ent *dchk-arc-color*))
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

(defun dchk:review-olap (la lb num total / info ea eb h1 h2 lay1 lay2 label
                                           ans mergeable kinds)
  ;; interactive review of one overlapping segment pair.
  ;; Returns nil when the pair no longer overlaps (an earlier merge
  ;; absorbed it); otherwise (label report-note action ents...) where
  ;; action is merged / flagged / left and ents keep their cyan.
  (setq ea (dchk:seg-ent la)
        eb (dchk:seg-ent lb))
  (if (and (entget ea) (entget eb) (setq info (dchk:overlap-info la lb)))
    (progn
      (setq h1        (cdr (assoc 5 (entget ea)))
            h2        (cdr (assoc 5 (entget eb)))
            lay1      (cdr (assoc 8 (entget ea)))
            lay2      (cdr (assoc 8 (entget eb)))
            mergeable (and (dchk:whole-line-p la)
                           (dchk:whole-line-p lb)
                           (= (strcase lay1) (strcase lay2)))
            kinds     (if (and (dchk:whole-line-p la) (dchk:whole-line-p lb))
                        "lines"
                        "segments")
            label     (strcat h1 "+" h2 " (overlap " (rtos (caddr info)) ")"))
      (dchk:zoom-2ents ea eb)
      (redraw ea 3)
      (redraw eb 3)
      (dchk:mark-point (car info))
      (dchk:mark-point (cadr info))
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
         (dchk:merge-lines la lb info)
         (dchk:set-color ea *dchk-olap-color*)
         (princ "\n  Merged into one line (cyan).")
         (list label "merged into one line (cyan)" 'merged ea))
        ((= ans "Flag")
         (dchk:set-color ea *dchk-olap-color*)
         (dchk:set-color eb *dchk-olap-color*)
         (princ "\n  Flagged to fix (cyan).")
         (list label
               (if (dchk:whole-line-p la)
                 (if (= (strcase lay1) (strcase lay2))
                   "flagged to fix (cyan)"
                   "different layers - flagged to fix (cyan)")
                 "polyline edge - flagged to fix (cyan)")
               'flagged ea eb))
        (t
         (princ "\n  Left as drawn.")
         (list label "left as drawn" 'left))))))

(defun c:DIMCHECK ( / *error* oldecho vc vs undo-open ss i e et
                      cands dims arcs lns plns segs olaps rest e1 e2 pr
                      anchors anchheld saved keep res n total lines ans
                      ndok ndflag ndmoved ndanch naok namoved nasnap
                      nomerged noflag noleft
                      rowtol sty pair dlines skiprest
                      laylist locked relock lay
                      minx miny maxx maxy bb h m ins txt nlin ref hdr l carried cmv)
  (defun *error* (msg)
    ;; put the greys back (flagged/moved items keep their colour),
    ;; re-lock what we unlocked, clear markers, close the undo group
    ;; The entity work stays INSIDE the group, so one U still takes the
    ;; whole run back -- but through the catch: an entmod that throws
    ;; (a colour on a layer the user declined to unlock is in saved
    ;; too) used to skip the close and the CMDECHO restore below, and
    ;; a throw inside *error* is the one error nothing catches.
    (vl-catch-all-apply
      '(lambda ()
         (foreach pair saved
           (if (and (not (member (car pair) keep)) (entget (car pair)))
             (dchk:set-color (car pair) (cdr pair))))
         (foreach l relock (dchk:set-layer-lock l T))
         (redraw))
      nil)
    (if undo-open
      (progn (setvar "CMDECHO" 0) (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nDIMCHECK error: " msg)))
    (princ))

  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I"))
  (if (null ss)
    (progn
      (prompt "\nHighlight the drawing to DIMCHECK: ")
      (setq ss (ssget))))
  (cond
    ((null ss)
     (prompt "\nNothing selected - DIMCHECK cancelled."))
    (t
     (setq cands nil dims nil arcs nil lns nil segs nil
           saved nil keep nil lines nil i 0
           ndok 0 ndflag 0 ndmoved 0 ndanch 0 naok 0 namoved 0 nasnap 0
           nomerged 0 noflag 0 noleft 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (= et "LINE") (setq lns (cons e lns)))
       (if (member et '("LINE" "LWPOLYLINE" "POLYLINE"))
         (setq plns (cons e plns)))
       (if (member et *dchk-curve-types*) (setq cands (cons e cands))))
     (setq dims  (reverse dims)
           arcs  (reverse arcs)
           lns   (reverse lns)
           plns  (reverse plns)
           cands (reverse cands)
           ;; overlap detection runs on segments, so a run of lines
           ;; drawn as one polyline counts like separate lines
           segs  (dchk:collect-segs plns))
     (cond
       ((and (null dims) (null arcs) (< (length segs) 2))
        (prompt "\nSelection holds no dimensions, arcs, or lines to check - nothing to do."))
       (t
        (setq oldecho (getvar "CMDECHO"))
        (setvar "CMDECHO" 0)
        (setq vc (getvar "VIEWCTR")
              vs (getvar "VIEWSIZE"))
        ;; only when undo is recording - _Begin in a drawing with UNDO
        ;; off (bit 1 of UNDOCTL clear) errors out of the command
        (if (= 1 (logand 1 (getvar "UNDOCTL")))
          (progn
            (command "_.UNDO" "_Begin")
            (setq undo-open T)))
        (dchk:ensure-layer *dchk-constr-layer* *dchk-constr-color*)
        (dchk:ensure-layer *dchk-report-layer* *dchk-report-color*)

        ;; a locked layer swallows every fix and recolour silently -
        ;; surface that up front and offer to unlock for the run
        (setq laylist nil relock nil i 0)
        (repeat (sslength ss)
          (setq lay (cdr (assoc 8 (entget (ssname ss i))))
                i   (1+ i))
          (if (and lay (not (member lay laylist)))
            (setq laylist (cons lay laylist))))
        (setq locked (vl-remove-if-not 'dchk:layer-locked-p laylist))
        (if locked
          (if (dchk:ask-yn
                (strcat "\n" (itoa (length locked))
                        " locked layer(s) in the selection ("
                        (dchk:join locked ", ")
                        ") - DIMCHECK cannot recolour or fix anything on them. Unlock for this run?"))
            (progn
              (foreach l locked (dchk:set-layer-lock l nil))
              (setq relock locked)
              (princ "\n  Unlocked; they will be re-locked when the run ends."))
            (princ "\n  Locked layers stay locked - items on them are reported but left untouched.")))

        ;; a rerun replaces the previous run's report and markers
        (dchk:clear-old)

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

        ;; spots two or more dimensions measure to are anchors: a
        ;; hypotenuse corner is dimmed twice precisely because there is
        ;; no line through it, so those points are objects as far as the
        ;; audit is concerned. Read once, off the drawing as selected.
        (setq anchors (dchk:shared-anchors dims))
        (if anchors
          (princ (strcat "\n" (itoa (length anchors))
                         " point(s) carry more than one dimension - treated"
                         " as anchors and not questioned.")))

        ;; grey out the whole selection so each item can take the
        ;; stage, stashing every original colour in xdata first so
        ;; DIMCHECKRESCUE can recover them even after a crash
        (setq i 0)
        (repeat (sslength ss)
          (setq e (ssname ss i)
                i (1+ i))
          (if (entget e)
            (progn
              (setq saved (cons (cons e (dchk:ent-color e)) saved))
              (dchk:stash-color e (dchk:ent-color e))
              (dchk:set-color e *dchk-grey-color*))))

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
          (dchk:set-color e (cdr (assoc e saved)))       ; step into the light
          (setq res (dchk:review-dim e cands anchors (1+ n) total))
          ;; points already moved count however the prompt was answered
          (setq ndmoved (+ ndmoved (cadddr res)))
          ;; anchor holds are recorded PER DIMENSION rather than added
          ;; up: an anchored point stays anchored, so a dimension sent
          ;; round again by Back reports it a second time and a running
          ;; total would count it twice. A moved point cannot do that --
          ;; moving it is what makes it attached.
          (if (> (nth 5 res) 0)
            (setq anchheld (cons (cons e (nth 5 res))
                                 (vl-remove (assoc e anchheld) anchheld))))
          (cond
            ((eq (cadr res) 'skip)
             (dchk:set-color e *dchk-grey-color*)
             (setq skiprest T)
             (princ (strcat "\n  Skipping the remaining "
                            (itoa (- total n)) " dimension(s).")))
            ((eq (cadr res) 'back)
             ;; undo what the previous item recorded, then redo it
             (dchk:set-color e *dchk-grey-color*)
             (if (> n 0)
               (progn
                 (setq n  (1- n)
                       e1 (nth n dims))
                 (if (car dlines)                        ; roll back its tally
                   (progn
                     (if (cadr (car dlines))
                       (setq ndok (1- ndok))
                       (setq ndflag (1- ndflag)))
                     ;; A MOVED POINT STAYS MOVED.  Back re-asks the
                     ;; question; it does not put the point back, and
                     ;; its construction line is still standing.  So
                     ;; the move is CARRIED to the re-review, not
                     ;; un-counted -- subtracting it made the report
                     ;; claim "points adjusted: 0" over a drawing
                     ;; whose points really had been adjusted, and
                     ;; the rebuilt line lost its "moved" note with
                     ;; it (the second pass finds them attached and
                     ;; has nothing to report).
                     (if (> (caddr (car dlines)) 0)
                       (setq carried (cons (cons e1 (caddr (car dlines)))
                                           (vl-remove (assoc e1 carried)
                                                      carried))))
                     (setq dlines (cdr dlines))))
                 (setq keep (vl-remove e1 keep))
                 (dchk:set-color e1 *dchk-grey-color*)
                 (princ "\n  Stepping back one dimension."))
               (princ "\n  Already at the first dimension."))
             (setq n (1- n)))                            ; loop's 1+ re-enters it
            (t
             (if (cadr res)
               (progn (setq ndok (1+ ndok))
                      (dchk:set-color e *dchk-grey-color*))
               (progn (setq ndflag (1+ ndflag))
                      (setq keep (cons e keep))))
             (setq sty (dchk:dim-style e))
             ;; moves this dim collected on an earlier pass, before a
             ;; Back sent us round again -- they are real and belong
             ;; in both the line and the tally
             (setq cmv (cond ((cdr (assoc e carried))) (0)))
             (setq dlines (cons (list (strcat "Dim " (car res)
                                              (if (= sty "") "" (strcat " [" sty "]"))
                                              (if (nth 4 res)
                                                (strcat " = " (nth 4 res))
                                                "")
                                              ": " (caddr res)
                                              (if (> cmv 0)
                                                (strcat " - " (itoa cmv)
                                                        " point(s) moved before"
                                                        " you stepped back")
                                                ""))
                                      (cadr res)
                                      (+ (cadddr res) cmv))
                                dlines))))
          (setq n (1+ n)))
        (foreach pair anchheld (setq ndanch (+ ndanch (cdr pair))))
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
        (setq olaps (dchk:find-overlaps segs))
        (if olaps
          (princ (strcat "\n--- Reviewing " (itoa (length olaps))
                         " overlapping line pair(s): Enter = merge, F = flag, L = leave ---")))
        (setq n 0 total (length olaps))
        (foreach pr olaps
          (setq n  (1+ n)
                e1 (dchk:seg-ent (car pr))
                e2 (dchk:seg-ent (cadr pr)))
          (dchk:stage e1 saved keep)
          (dchk:stage e2 saved keep)
          (setq res (dchk:review-olap (car pr) (cadr pr) n total))
          (cond
            ((null res)                       ; absorbed by an earlier merge
             (dchk:unstage e1 keep)
             (dchk:unstage e2 keep))
            ((eq (caddr res) 'left)
             (setq noleft (1+ noleft))
             (dchk:unstage e1 keep)
             (dchk:unstage e2 keep)
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))
            (t
             (if (eq (caddr res) 'merged)
               (setq nomerged (1+ nomerged))
               (setq noflag (1+ noflag)))
             (setq keep (append (cdddr res) keep))
             (setq lines (cons (strcat "Lines " (car res) ": " (cadr res)) lines)))))
        ;; --- restore colours (flagged/moved keep theirs) ------------
        ;; restored entities drop their rescue stash; flagged/moved
        ;; ones keep it so DIMCHECKRESCUE can clear the marks later
        (foreach pair saved
          (if (and (not (member (car pair) keep)) (entget (car pair)))
            (progn
              (dchk:set-color (car pair) (cdr pair))
              (dchk:unstash (car pair)))))
        (foreach l relock (dchk:set-layer-lock l T))
        (setq relock nil)

        ;; --- report on the right side, to scale with the drawing ----
        ;; text height picked from the drawing's extents so the whole
        ;; report roughly matches the drawing's height (MTEXT line
        ;; spacing is ~1.66 x text height), clamped so a short report
        ;; is not gigantic nor a long one unreadably small
        ;; all-clear lines are shorter, so weight them when sizing
        (setq nlin 3.0)                          ; title, legend, separator
        (foreach l lines
          (setq nlin (+ nlin (if (dchk:attn-p l) 1.0 *dchk-green-scale*))))
        (setq nlin (+ nlin (* 3.0 *dchk-green-scale*)))   ; the header dashboard
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
                          ", points adjusted: " (itoa ndmoved)
                          (if (> ndanch 0)
                            (strcat ", held at a shared anchor: " (itoa ndanch))
                            "")
                          ")")
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
        (setq txt (strcat "DIMCHECK REPORT - " (dchk:datestr)
                          "  [DIMCHECK " *dchk-version* "]"
                          "\\P"
                          (dchk:small
                            (strcat "Items needing attention are shown in "
                                    (dchk:red "red") ", larger than the rest."))))
        (foreach pr hdr
          (setq txt (strcat txt "\\P"
                            (if (cdr pr)
                              (dchk:red (car pr))
                              (dchk:small (car pr))))))
        (setq txt (strcat txt "\\P"
                          (dchk:small "----------------------------------------")))
        (foreach l (reverse lines)
          (setq txt (strcat txt "\\P"
                            (if (dchk:attn-p l) (dchk:red l) (dchk:small l)))))
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
                       (if (> ndanch 0)
                         (strcat ", " (itoa ndanch)
                                 " point(s) held at a shared anchor")
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
                       *dchk-report-layer* ")."
                       (if (> ndmoved 0)
                         (strcat "\nConstruction lines through moved dimensions' original points are on layer "
                                 *dchk-constr-layer* ".")
                         "")
                       "\nOne UNDO reverts everything DIMCHECK changed (including the report)."))))))
  (princ))

;; --- DIMSCAN: the read-only twin -----------------------------------
;;  Runs every audit, asks nothing, and changes nothing in the drawing
;;  except writing the report. Use it as a quick pre-flight, or when
;;  you want the findings without touching a released sheet.

(defun c:DIMSCAN ( / *error* oldecho ss i e et ed cands dims arcs plns segs
                     lines olaps pr anchors
                     nd ndbad na nabad ndanch h m ins txt nlin ref hdr l
                     minx miny maxx maxy bb p13 p14 near q dq s bad held w)
  (defun *error* (msg)
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nDIMSCAN error: " msg)))
    (princ))

  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I"))
  (if (null ss)
    (progn
      (prompt "\nHighlight the drawing to DIMSCAN (Enter = whole drawing): ")
      (setq ss (ssget))))
  (if (null ss) (setq ss (ssget "_X")))
  (cond
    ((null ss) (prompt "\nNothing to scan."))
    (t
     (setq oldecho (getvar "CMDECHO"))
     (setvar "CMDECHO" 0)
     (setq i 0 nd 0 ndbad 0 na 0 nabad 0 ndanch 0)
     (repeat (sslength ss)
       (setq e  (ssname ss i)
             i  (1+ i)
             et (cdr (assoc 0 (entget e))))
       (if (= et "DIMENSION") (setq dims (cons e dims)))
       (if (= et "ARC") (setq arcs (cons e arcs)))
       (if (member et '("LINE" "LWPOLYLINE" "POLYLINE")) (setq plns (cons e plns)))
       (if (member et *dchk-curve-types*) (setq cands (cons e cands)))
       (setq bb (dchk:bbox e))
       (if bb
         (setq minx (if minx (min minx (caar bb)) (caar bb))
               miny (if miny (min miny (cadar bb)) (cadar bb))
               maxx (if maxx (max maxx (caadr bb)) (caadr bb))
               maxy (if maxy (max maxy (cadadr bb)) (cadadr bb)))))
     (setq dims (reverse dims) arcs (reverse arcs)
           plns (reverse plns) cands (reverse cands)
           segs (dchk:collect-segs plns)
           ;; a spot two or more dimensions measure to is an anchor and
           ;; counts as an object -- the same rule DIMCHECK reviews by,
           ;; so the scan cannot call stray what the review will not
           anchors (dchk:shared-anchors dims))

     ;; --- dimensions: report stray definition points, move nothing
     (foreach e (dchk:sort-dims dims (if (and miny maxy) (* 0.05 (- maxy miny)) 1.0))
       (setq ed  (entget e)
             nd  (1+ nd)
             p13 (cdr (assoc 13 ed))
             p14 (cdr (assoc 14 ed))
             bad nil
             held nil)
       (if (member (logand 7 (cdr (assoc 70 ed))) '(0 1))
         (foreach s (list (cons "point 1" p13) (cons "point 2" p14))
           (if (cdr s)
             (progn
               (setq near (dchk:nearest-curve (cdr s) nil cands)
                     q    (dchk:closest-of (cdr s) anchors)
                     dq   (if q (distance (cdr s) q)))
               (cond
                 ;; another dimension measures to this spot too: it is
                 ;; an anchor, not a stray point
                 ((and dq (<= dq *dchk-anchor-tol*))
                  (if (or (null near) (> (caddr near) *dchk-tol*))
                    (setq held (append held (list (car s))))))
                 ((and near (<= (caddr near) *dchk-tol*)) nil)   ; on an object
                 ;; stray: name the nearer of the two homes it missed,
                 ;; so the scan points where the review would offer
                 ((and dq (or (null near) (< dq (caddr near))))
                  (setq bad (append bad (list (strcat (car s)
                                                      " off the shared anchor by "
                                                      (rtos dq 2 4))))))
                 (near
                  (setq bad (append bad (list (strcat (car s) " off by "
                                                      (rtos (caddr near) 2 4)))))))))))
       (if bad (setq ndbad (1+ ndbad)))
       (if held (setq ndanch (+ ndanch (length held))))
       (setq lines (cons (strcat "Dim " (cdr (assoc 5 ed))
                                 (if (= (dchk:dim-style e) "") ""
                                   (strcat " [" (dchk:dim-style e) "]"))
                                 (if (dchk:dim-meas e)
                                   (strcat " = " (dchk:dim-meas e)) "")
                                 ": "
                                 (if bad
                                   (strcat "NOT attached - " (dchk:join bad ", "))
                                   "OK")
                                 (if held
                                   (strcat " - " (dchk:join held " & ")
                                           " on a shared anchor")
                                   "")
                                 (if (dchk:dim-assoc-p e) " (associative)" ""))
                         lines)))

     ;; --- arcs: report unattached endpoints, move nothing
     (foreach e arcs
       (setq na  (1+ na)
             bad nil)
       (if (dchk:planar-arc-p (entget e))
         (foreach s '(("start" . start) ("end" . end))
           (if (dchk:arc-end-target e (cdr s) cands)
             (setq bad (append bad (list (car s)))))))
       (if bad (setq nabad (1+ nabad)))
       (setq lines (cons (strcat "Arc " (cdr (assoc 5 (entget e))) ": "
                                 (if bad
                                   (strcat (dchk:join bad " & ")
                                           " NOT attached to an object end")
                                   "endpoints OK"))
                         lines)))

     ;; --- overlaps
     (setq olaps (dchk:find-overlaps segs))
     (foreach pr olaps
       (setq lines (cons (strcat "Lines "
                                 (cdr (assoc 5 (entget (dchk:seg-ent (car pr)))))
                                 "+"
                                 (cdr (assoc 5 (entget (dchk:seg-ent (cadr pr)))))
                                 ": OVERLAP of "
                                 (rtos (caddr (dchk:overlap-info (car pr) (cadr pr))))
                                 " - flagged")
                         lines)))

     ;; --- report (the only thing DIMSCAN writes) ------------------
     (dchk:ensure-layer *dchk-report-layer* *dchk-report-color*)
     (dchk:clear-old)
     (setq hdr (list
                 (cons (strcat "Dimensions scanned: " (itoa nd) " ("
                               (itoa ndbad) " with a stray definition point"
                               (if (> ndanch 0)
                                 (strcat ", " (itoa ndanch)
                                         " point(s) on a shared anchor")
                                 "")
                               ")")
                       (> ndbad 0))
                 (cons (strcat "Arcs scanned: " (itoa na) " ("
                               (itoa nabad) " with an unattached end)")
                       (> nabad 0))
                 (cons (strcat "Overlapping line pairs: " (itoa (length olaps)))
                       (> (length olaps) 0))))
     (setq nlin 3.0)
     (foreach l lines
       (setq nlin (+ nlin (if (dchk:attn-p l) 1.0 *dchk-green-scale*))))
     (setq nlin (+ nlin (* 3.0 *dchk-green-scale*)))
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
     (setq txt (strcat "DIMSCAN REPORT - " (dchk:datestr)
                       "  [DIMCHECK " *dchk-version* "]"
                       "\\P"
                       (dchk:small (strcat "Read-only scan - nothing in the drawing was changed. "
                                           "Items needing attention are shown in "
                                           (dchk:red "red") "."))))
     (foreach pr hdr
       (setq txt (strcat txt "\\P" (if (cdr pr) (dchk:red (car pr))
                                     (dchk:small (car pr))))))
     (setq txt (strcat txt "\\P" (dchk:small "----------------------------------------")))
     (foreach l (reverse lines)
       (setq txt (strcat txt "\\P" (if (dchk:attn-p l) (dchk:red l) (dchk:small l)))))
     (dchk:mtext ins h (* *dchk-report-chars* h) txt *dchk-report-layer*)
     (setvar "CMDECHO" oldecho)
     (princ (strcat "\n--- DIMSCAN complete (read-only) ---"
                    "\nDimensions: " (itoa nd) " scanned, " (itoa ndbad) " with a stray point"
                    (if (> ndanch 0)
                      (strcat ", " (itoa ndanch) " point(s) on a shared anchor")
                      "")
                    "\nArcs: " (itoa na) " scanned, " (itoa nabad) " with an unattached end"
                    "\nOverlapping line pairs: " (itoa (length olaps))
                    "\nReport written on layer " *dchk-report-layer*
                    "; nothing else was changed."))))
  (princ))

;; --- TUTORIALDIMCHECK: learn it two ways ---------------------------
;;  List  - every check spelled out, at the command line and (if you
;;          want) dropped into the drawing as a reference sheet.
;;  Demo  - draws a small practice drawing with faults planted in it,
;;          walks you through each one showing what DIMCHECK sees and
;;          what the colours mean, then scans it so you see a report.
;;  Both  - the list, then the demo.
;;  Everything the demo draws is in one UNDO group and can be erased
;;  when you are done, so it never touches your real work.
(defun dchk:tut-checklist ()
  (list
    "WHAT DIMCHECK CHECKS"
    ""
    "1. DIMENSIONS - one at a time"
    (strcat "   Order: style groups " (dchk:join *dchk-style-order* " > ")
            " > anything else,")
    "     then left to right, top to bottom inside each group."
    "   Every other object greys out; the one under review is zoomed to."
    "   A definition point not touching any object: you choose"
    "     Move (green +, onto the nearest object) / Keep (red X, exactly"
    "     where you drew it) / Pick your own spot."
    (strcat "   A point "
            (if (= *dchk-anchor-min* 2) "two" (itoa *dchk-anchor-min*))
            " or more dimensions measure to is an ANCHOR - the")
    "     hypotenuse corner case - and is never questioned: dimming to"
    "     the same spot twice is how you say that spot is the object."
    "   Then 'Is this dimension correct?'  Enter = yes,  N = flag it RED,"
    "     B = back one dimension,  S = skip the rest."
    "   The measured distance is shown, and object-associative dims are"
    "     called out (a moved point can re-anchor itself)."
    ""
    "2. ARCS - one endpoint at a time"
    "   Each end must sit at the END of another object; a loose one gets"
    "     the same Move / Keep / Pick choice. Keep restores the arc"
    "     exactly. Arcs that changed turn MAGENTA."
    ""
    "3. OVERLAPPING LINES"
    "   Collinear geometry running on top of itself, in LINEs and in"
    "     polyline edges. Touching end-to-end is fine and is not"
    "     reported. Per pair: Merge into one / Flag CYAN / Leave."
    "     Merge is offered only for two whole LINEs on one layer."
    ""
    "4. THE REPORT"
    "   An MTEXT sheet to the right of the drawing, sized to scale with"
    (strcat "     it. Problems in RED at full size; all-clear in green at "
            (rtos (* 100.0 *dchk-green-scale*) 2 0) "%.")
    ""
    "COMMANDS"
    "   DIMCHECK         the full interactive review (fixes things)"
    "   DIMSCAN          the same audits, read-only - changes nothing"
    "   DIMCHECKRESCUE   put back every colour, remove the markers"
    "   DIMCHECKVER      which build is loaded"
    "   TUTORIALDIMCHECK this tutorial"
    ""
    "GOOD HABITS"
    "   Run DIMSCAN first if you want to look before anything is"
    "     touched. One U undoes an entire DIMCHECK run. Need steps,"
    "     wall height, the liner pattern or the title block border"
    "     checked too? Load linfincheck.lsp and run LINFINCHECK -"
    "     it shares this tool's review and report machinery."))

(defun dchk:tut-pause (msg)
  (princ (strcat "\n  " msg))
  (getstring "\n  --- press Enter to continue ---")
  (princ))

(defun dchk:tut-line (p1 p2 lay)
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                 '(100 . "AcDbLine") (cons 10 p1) (cons 11 p2)))
  (entlast))

(defun dchk:tut-dim (p1 p2 dimpt rot / old res)
  ;; a linear dimension, made with the command so it is valid in any
  ;; release; osnap is muted so the picks land exactly where told,
  ;; and the command is caught so a failure cannot skip the restore -
  ;; the tutorial's handler has no way to put OSMODE back
  (setq old (getvar "OSMODE"))
  (setvar "OSMODE" 0)
  (setq res (vl-catch-all-apply
              '(lambda ()
                 (if (zerop rot)
                   (command "_.DIMLINEAR" p1 p2 "_H" dimpt)
                   (command "_.DIMLINEAR" p1 p2 "_V" dimpt)))
              nil))
  (setvar "OSMODE" old)
  (entlast))

(defun dchk:tut-demo (/ org ox oy made e ss2 i)
  (princ "\n\n--- DEMO: a practice drawing with faults planted in it ---")
  (setq org (getpoint "\n  Pick an empty spot for the practice drawing: "))
  (if (null org)
    (princ "\n  Cancelled - nothing drawn.")
    (progn
      (setq org (trans org 1 0)
            ox  (car org)
            oy  (cadr org)
            made nil)

      ;; --- fault 1: two lines overlapping ------------------------
      (setq made (cons (dchk:tut-line (list ox oy 0.0)
                                      (list (+ ox 100.0) oy 0.0) "0") made))
      (setq made (cons (dchk:tut-line (list (+ ox 60.0) oy 0.0)
                                      (list (+ ox 180.0) oy 0.0) "0") made))
      (command "_.ZOOM" "_Object" (car made) "")
      (command "_.ZOOM" "_0.4x")
      (dchk:tut-pause
        (strcat "FAULT 1 - overlapping lines.\n  Two lines run on top of each other from "
                "60 to 100: someone drew over\n  an existing line to carry on and never cleaned it up. "
                "DIMCHECK\n  shows the overlap marked at both ends and offers Merge / Flag /\n"
                "  Leave. Lines that merely TOUCH end to end are fine and are\n  never reported."))

      ;; --- fault 2: a dim whose point misses the line -------------
      (setq made (cons (dchk:tut-line (list ox (+ oy 80.0) 0.0)
                                      (list (+ ox 120.0) (+ oy 80.0) 0.0) "0") made))
      (setq e (dchk:tut-dim (list ox (+ oy 80.0) 0.0)
                            (list (+ ox 120.0) (+ oy 88.0) 0.0)   ; 8 units OFF the line
                            (list (+ ox 60.0) (+ oy 110.0) 0.0) 0))
      (if e (setq made (cons e made)))
      (command "_.ZOOM" "_Window"
               (trans (list (- ox 20.0) (+ oy 50.0) 0.0) 0 1)
               (trans (list (+ ox 150.0) (+ oy 130.0) 0.0) 0 1))
      (dchk:tut-pause
        (strcat "FAULT 2 - a dimension point off the geometry.\n"
                "  The right-hand point of this dimension sits 8 units above the\n"
                "  line, so it is not measuring the line at all. DIMCHECK marks\n"
                "  BOTH spots - a RED X where you drew it, a GREEN + where it\n"
                "  belongs - and lets you Move it, Keep it exactly as drawn, or\n"
                "  Pick a spot yourself. Answer N to the 'is this correct?'\n"
                "  question and the whole dimension turns RED to fix later."))

      ;; --- fault 3: an arc floating free --------------------------
      (entmake (list '(0 . "ARC") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbCircle")
                     (cons 10 (list (+ ox 220.0) (+ oy 40.0) 0.0))
                     (cons 40 30.0) '(100 . "AcDbArc")
                     (cons 50 0.0) (cons 51 pi)))
      (setq made (cons (entlast) made))
      (command "_.ZOOM" "_Window"
               (trans (list (+ ox 175.0) (- oy 10.0) 0.0) 0 1)
               (trans (list (+ ox 265.0) (+ oy 90.0) 0.0) 0 1))
      (dchk:tut-pause
        (strcat "FAULT 3 - an arc that attaches to nothing.\n"
                "  Both ends of this arc float free. DIMCHECK wants every arc end\n"
                "  to land on the END of another object, so it offers to snap\n"
                "  each one - again with Move / Keep / Pick. An arc whose ends\n"
                "  actually moved turns MAGENTA so you can spot it afterwards."))

      ;; --- and now the report ------------------------------------
      (setq ss2 (ssadd))
      (foreach e made (if (entget e) (ssadd e ss2)))
      (command "_.ZOOM" "_Window"
               (trans (list (- ox 40.0) (- oy 40.0) 0.0) 0 1)
               (trans (list (+ ox 300.0) (+ oy 230.0) 0.0) 0 1))
      (princ (strcat "\n  " (itoa (sslength ss2))
                     " practice objects drawn. What DIMCHECK would say about"
                     "\n  them is easiest to see as a report."))
      (if (dchk:ask-yn "\n  Write a read-only DIMSCAN report for the practice drawing?")
        (progn
          (princ "\n  Running DIMSCAN - it changes nothing, it only reports.")
          (princ "\n  (In the report, RED lines at full size are the problems;")
          (princ "\n   green lines at three-quarter size are the all-clears.)")
          (dchk:tut-pause
            (strcat "DIMSCAN will ask you to highlight - window the practice\n"
                    "  drawing (or press Enter for the whole drawing). The report\n"
                    "  lands to the right of whatever you highlight."))
          (c:DIMSCAN)))
      (if (dchk:ask-yn "\n  Erase the practice drawing now?")
        (progn
          (setq i 0)
          (repeat (sslength ss2)
            (if (entget (ssname ss2 i)) (entdel (ssname ss2 i)))
            (setq i (1+ i)))
          (setq ss2 (ssget "_X" (list (cons 8 *dchk-report-layer*))))
          (if ss2
            (progn
              (setq i 0)
              (repeat (sslength ss2) (entdel (ssname ss2 i)) (setq i (1+ i)))))
          (princ "\n  Practice drawing erased."))
        (princ "\n  Left in place - one U removes the whole tutorial."))
      (princ))))

(defun c:TUTORIALDIMCHECK ( / *error* oldecho undo-open ans l ins h)
  (defun *error* (msg)
    (if undo-open (progn (setvar "CMDECHO" 0) (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))))
    (if oldecho (setvar "CMDECHO" oldecho))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTUTORIALDIMCHECK error: " msg)))
    (princ))

  (princ (strcat "\n=================================================="
                 "\n  DIMCHECK tutorial   [" *dchk-version* "]"
                 "\n=================================================="))
  ;; the tutorial selector of STANDARDS section 3; the old List stays
  ;; accepted typed in full, hidden
  (initget "Checks Demo Both LIST")
  (setq ans (getkword
              "\n  Read the Checks, Demo them on a practice drawing, or Both? [Checks/Demo/Both] <Both>: "))
  (if (null ans) (setq ans "Both"))
  (if (= ans "LIST") (setq ans "Checks"))
  (setq oldecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))

  (if (member ans '("Checks" "Both"))
    (progn
      (foreach l (dchk:tut-checklist) (princ (strcat "\n" l)))
      (princ "\n")
      (if (dchk:ask-yn "\n  Drop that list into the drawing as a reference sheet?")
        (progn
          (dchk:ensure-layer *dchk-report-layer* *dchk-report-color*)
          (setq ins (getpoint "\n  Pick the top-left corner for the sheet: "))
          (if ins
            (progn
              (setq h   (getdist (strcat "\n  Text height <" (rtos 2.5) ">: "))
                    h   (if h h 2.5)
                    ins (trans ins 1 0))
              (dchk:mtext ins h (* 70.0 h)
                          (dchk:join (dchk:tut-checklist) "\\P")
                          *dchk-report-layer*)
              (princ "\n  Reference sheet placed (one U removes it)."))
            (princ "\n  No point picked - sheet skipped."))))))

  (if (member ans '("Demo" "Both"))
    (dchk:tut-demo))

  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (setvar "CMDECHO" oldecho)
  (princ (strcat "\n\n--- Tutorial finished ---"
                 "\n  DIMSCAN first if you want to look without touching anything;"
                 "\n  DIMCHECK to review and fix; DIMCHECKRESCUE to undo the marks."
                 "\n  One U undoes everything this tutorial drew."))
  (princ))

(defun c:TUTORIALDIMSCAN () (c:TUTORIALDIMCHECK))

(princ (strcat "\ndimcheck.lsp " *dchk-version*
               " loaded - DIMCHECK reviews dimensions, arcs & overlapping"))
(princ "\n  lines one at a time; DIMSCAN reports it read-only; DIMCHECKRESCUE undoes")
(princ "\n  DIMCHECK's marks. For steps, wall height, the liner pattern and the")
(princ "\n  title block border too, load linfincheck.lsp and run LINFINCHECK.")
(princ)
