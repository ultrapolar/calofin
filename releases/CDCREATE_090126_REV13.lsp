;;; ===================================================================
;;; CDCREATE.lsp  --  cross dimensions from every highlighted line
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP; needs the Visual LISP
;;; engine that ships with full AutoCAD -- LT cannot run this).
;;;
;;; Commands:  CDCREATE       dimension every highlighted line
;;;            CDCREATEVER    print the loaded version
;;;
;;;  Turns highlighted lines into cross dimensions in one pass:
;;;
;;;    1. Highlight the lines (or pre-select them before typing the
;;;       command -- a pickfirst selection is used as-is).
;;;    2. Every LINE in the selection gets an aligned dimension along
;;;       it, measuring end to end, with the dimension line sitting on
;;;       the line itself and the text slid along it, about 80% of the
;;;       way toward the right-hand end -- the bottom end on a line
;;;       standing near vertical -- rather than sitting centred.
;;;    3. Each new dimension is put in the "CROSS DIMENSIONS" dimension
;;;       style and on the "DIMENSION" layer, ByLayer, with no
;;;       per-entity colour / linetype / lineweight override -- the
;;;       same convention POOL uses for the cross dims it draws.
;;;    4. A line whose two ends already carry a dimension is left
;;;       alone -- no second dim on top of the first, and the line
;;;       stays put so you can see what was skipped.  Two coincident
;;;       lines in one selection count as the same tie.
;;;    5. The line each dimension was made from is erased, so the tie
;;;       measurement is left as a dimension and nothing else.  Only
;;;       lines that really did get a dimension are erased, and the
;;;       report says how many went and off which layers (they are
;;;       normally POOL or POINTS).  Set cdc:*erase* to nil to keep
;;;       them.
;;;
;;;  The whole run is one undo group: a single U puts the lines back
;;;  and takes the dimensions away.
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
;;;    cdc:*erase*   T to erase each dimensioned line, nil to keep it
;;;    cdc:*skipdimmed*  T to leave a tie that is dimensioned already,
;;;                  nil to dimension it again anyway
;;;    cdc:*dupetol* how close two extension line origins have to be to
;;;                  count as the same point; nil = a sixteenth of an
;;;                  inch in the drawing's own units
;;;    cdc:*textpos* where the text sits along the dimension, 0.0 at the
;;;                  far end, 0.5 centred, 1.0 at the right/bottom end
;;;    cdc:*vertang* how near vertical (degrees) a line has to stand
;;;                  before the text goes to its bottom end instead of
;;;                  its right-hand one
;;;
;;;  Notes
;;;    * Only LINE entities are dimensioned.  Anything else in the
;;;      selection (polylines, arcs, text, blocks, ...) is counted and
;;;      reported, not dimensioned -- explode a polyline first if its
;;;      segments need cross dims.
;;;    * Zero-length lines are skipped; they have nothing to measure.
;;;    * "Dimensioned already" means SOME dimension in model space
;;;      carries those same two extension line origins, either way
;;;      round -- whatever its style, layer, or where its dimension
;;;      line sits.  A dim of the same tie pushed out to one side still
;;;      counts as that tie being dimensioned.
;;;    * The "DIMENSION" layer is created when the drawing lacks it,
;;;      and thawed / unlocked / switched back on when it is there but
;;;      not usable -- a run onto a frozen layer would otherwise look
;;;      like the command did nothing.
;;;      A missing "CROSS DIMENSIONS" style is NOT invented: the dims
;;;      are drawn in whatever style is current and the routine says so,
;;;      so a drawing started from the wrong template is obvious
;;;      instead of silently producing wrong-looking dims.
;;;    * The dimension style, current layer, CMDECHO and OSMODE in
;;;      force before the command are restored afterwards, on a clean
;;;      finish, an error, or Esc.
;;; ===================================================================

(setq *cdcreate-version* "v1.3")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

(setq cdc:*style*  "CROSS DIMENSIONS")
(setq cdc:*layer*  "DIMENSION")
(setq cdc:*offset* 0.0)
(setq cdc:*erase*  t)
(setq cdc:*textpos* 0.8)
(setq cdc:*vertang* 15.0)
(setq cdc:*skipdimmed* t)
(setq cdc:*dupetol* nil)           ; nil = 1/16" in the drawing's units
(setq cdc:*sysold*  nil)           ; sysvar snapshot, live only mid-run

;;; -------------------- helpers ------------------------------------

;; The sysvars this tool moves, saved in restore order -- OSMODE first,
;; because object snaps are the setting the user misses most if a run is
;; ever cut short partway.
(defun cdc:syssave (vars / v)
  (if (not cdc:*sysold*)
    (foreach v vars
      (if (/= nil (getvar v))
        (setq cdc:*sysold*
              (append cdc:*sysold* (list (cons v (getvar v)))))))))

(defun cdc:sysrestore ( / p)
  (foreach p cdc:*sysold* (setvar (car p) (cdr p)))
  (setq cdc:*sysold* nil))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case.
(defun cdc:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
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
          (princ (strcat "\nLayer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; restore a dimension style by name when the drawing has it;
;; returns T when the style was set
(defun cdc:setstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; DIMSTYLE is read-only to setvar, so it goes back through a command --
;; and only when the style really did move: a run that never found
;; "CROSS DIMENSIONS" should not leave a pointless -DIMSTYLE Restore in
;; the drawing's command history.  command-s, so the same call is legal
;; from inside the error handler.
(defun cdc:restyle (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim)
           (not (equal odim (getvar "DIMSTYLE"))))
    (vl-catch-all-apply 'command-s
                        (list "_.-DIMSTYLE" "_Restore" odim))))

;; the two endpoints of a LINE, in WCS (the entity's own OCS may be
;; tilted, so go through the entity coordinate system)
(defun cdc:ends (en / ed)
  (setq ed (entget en))
  (list (trans (cdr (assoc 10 ed)) en 0)
        (trans (cdr (assoc 11 ed)) en 0)))

;; the point f of the way from p1 to p2 (f 0.5 = midpoint), pushed
;; perpendicular to the line by dist -- dist 0.0 leaves it on the line.
;; Everything CDCREATE places sits on this one line, so the dimension
;; line and its text can never drift onto opposite sides of it.
(defun cdc:loc (p1 p2 f dist / dx dy d b)
  (setq dx (- (car  p2) (car  p1))
        dy (- (cadr p2) (cadr p1))
        b  (list (+ (car   p1) (* f dx))
                 (+ (cadr  p1) (* f dy))
                 (+ (caddr p1) (* f (- (caddr p2) (caddr p1))))))
  (if (equal dist 0.0 1e-12)
    b
    (progn
      (setq d (sqrt (+ (* dx dx) (* dy dy))))
      (if (> d 1e-9)
        (list (+ (car  b) (* dist (/ (- dy) d)))
              (+ (cadr b) (* dist (/ dx d)))
              (caddr b))
        b))))

(defun cdc:d2r (a) (* pi (/ a 180.0)))

;; T when the text belongs at the p2 end rather than the p1 end: the
;; right-hand end, or -- for a line standing within cdc:*vertang* of
;; vertical, where "right-hand" is a coin toss a hair of drafting noise
;; could flip -- the bottom end
(defun cdc:top2 (p1 p2 / dx dy a)
  (setq dx (abs (- (car  p2) (car  p1)))
        dy (abs (- (cadr p2) (cadr p1)))
        a  (cdc:d2r cdc:*vertang*))
  (if (<= (* dx (cos a)) (* dy (sin a)))
    (< (cadr p2) (cadr p1))               ; standing up: the lower end
    (> (car  p2) (car  p1))))             ; lying over: the right end

;; cdc:*textpos* measured from the far end toward the end the text
;; belongs at, expressed as a fraction of p1->p2 so it can go straight
;; into cdc:loc whichever way round the line was drawn
(defun cdc:textfrac (p1 p2)
  (if (cdc:top2 p1 p2) cdc:*textpos* (- 1.0 cdc:*textpos*)))

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

;; one foot expressed in the current drawing units (INSUNITS), so the
;; tolerances below mean the same thing whatever the drawing works in
(defun cdc:onefoot (/ u)
  (setq u (getvar "INSUNITS"))
  (cond ((= u 2) 1.0)                   ; feet
        ((= u 4) 304.8)                 ; millimetres
        ((= u 5) 30.48)                 ; centimetres
        ((= u 6) 0.3048)                ; metres
        ((= u 10) (/ 1.0 3.0))          ; yards
        (t 12.0)))                      ; inches / unitless

;; how close two extension line origins have to be before they count as
;; the same point - a sixteenth of an inch, in the drawing's own units,
;; unless cdc:*dupetol* says otherwise
(defun cdc:dupetol ()
  (if cdc:*dupetol* cdc:*dupetol* (/ (cdc:onefoot) 192.0)))

;; T when a and b are the same point on the plan, within tol.  Compared
;; flat: a survey point carries an elevation, the dimension that
;; measures to it does not, and that difference must not read as two
;; different places.
(defun cdc:samept (a b tol)
  (and (<= (abs (- (car  a) (car  b))) tol)
       (<= (abs (- (cadr a) (cadr b))) tol)))

;; the pairs of extension line origins every dimension in model space
;; already carries.  A radial, angular or ordinate dim has no such pair
;; and is passed over.
(defun cdc:dimscan ( / ss i ed out)
  (setq out nil
        ss  (ssget "_X" '((0 . "DIMENSION") (410 . "Model")))
        i   0)
  (if ss
    (while (< i (sslength ss))
      (setq ed (entget (ssname ss i))
            i  (1+ i))
      (if (and (assoc 13 ed) (assoc 14 ed))
        (setq out (cons (list (cdr (assoc 13 ed)) (cdr (assoc 14 ed)))
                        out)))))
  out)

;; T when p1-p2 is one of the pairs in LST, either way round: the
;; "that tie is dimensioned already, leave it alone" test.  Where the
;; existing dim line sits is deliberately not part of it -- a dim of
;; this tie pushed off to one side is still a dim of this tie.
(defun cdc:dimmed-p (p1 p2 lst / tol q hit)
  (setq tol (cdc:dupetol))
  (while (and lst (not hit))
    (setq q   (car lst)
          lst (cdr lst))
    (if (or (and (cdc:samept (car q) p1 tol) (cdc:samept (cadr q) p2 tol))
            (and (cdc:samept (car q) p2 tol) (cdc:samept (cadr q) p1 tol)))
      (setq hit t)))
  hit)

;; "POOL, POINTS" from a list of layer names
(defun cdc:names (lst / out)
  (foreach n lst
    (setq out (if out (strcat out ", " n) n)))
  (if out out ""))

;;; -------------------- the command --------------------------------

(defun c:CDCREATE ( / *error* olderr odim
                      ss i en ed typ ends pairs skipped plines dimmed
                      already havestyle undo-open pre new made gone lays
                      p1 p2 )

  ;; -- restore drawing state on error / Esc.  The user's settings come
  ;;    back FIRST so nothing below can skip them; a dimension command
  ;;    may still be open, so AutoCAD is talked to through command-s --
  ;;    and the undo group is closed, or the next U would swallow the
  ;;    user's own work
  (setq olderr *error*)
  (defun *error* (m)
    (cdc:sysrestore)
    (cdc:restyle odim)
    (if undo-open
      (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCDCREATE error: " m)))
    (princ))

  (vl-load-com)
  (cdc:syssave '("OSMODE" "CMDECHO" "CLAYER"))
  (setq odim (getvar "DIMSTYLE"))

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
      ;; -- 2. keep the lines, count what was ignored.  What the
      ;;       drawing already carries is read once, up front, and each
      ;;       tie kept is added to it -- so two coincident lines in one
      ;;       selection are the same tie, dimensioned once
      (setq i 0 pairs nil skipped 0 plines 0 already 0
            dimmed (if cdc:*skipdimmed* (cdc:dimscan)))
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
             (cond
               ((<= (distance p1 p2) 1e-9)        ; nothing to measure
                  (setq skipped (1+ skipped)))
               ((and cdc:*skipdimmed* (cdc:dimmed-p p1 p2 dimmed))
                  (setq already (1+ already)))
               (t
                  (setq pairs  (cons (list en p1 p2 (cdr (assoc 8 ed)))
                                     pairs)
                        dimmed (cons (list p1 p2) dimmed))))))
        (setq i (1+ i)))
      (setq pairs (reverse pairs))

      (if (null pairs)
        (princ (if (> already 0)
                 (strcat "\n" (itoa already) " tie"
                         (if (= already 1) " is" "s are")
                         " dimensioned already -- nothing new to draw.")
                 "\nNo lines in the selection -- nothing to dimension."))
        (progn
          ;; -- 3. layer and style, all of it inside one undo group
          (setvar "CMDECHO" 0)
          (setvar "OSMODE"  0)
          ;; only when undo is recording - _Begin in a drawing with UNDO
          ;; off (bit 1 of UNDOCTL clear) errors out of the command
          (if (= 1 (logand 1 (getvar "UNDOCTL")))
            (progn
              (command "_.UNDO" "_Begin")
              (setq undo-open T)))
          (setvar "CLAYER" (cdc:ensure-layer cdc:*layer* 7))
          (setq havestyle (cdc:setstyle cdc:*style*))
          (if (not havestyle)
            (princ (strcat "\n** This drawing has no \"" cdc:*style*
                           "\" dimension style -- dims drawn in \""
                           (getvar "DIMSTYLE")
                           "\" instead.  Create the style (or start"
                           " from the standard template) and re-run.")))

          ;; -- 4. one aligned dim per line, on the line, and then the
          ;;       line itself goes: the tie is the dimension now
          (setq made 0 gone 0 lays nil)
          (foreach pr pairs
            (setq en  (car    pr)
                  p1  (cadr   pr)
                  p2  (caddr  pr)
                  pre (entlast))
            (command "_.DIMALIGNED"
                     "_non" (trans p1 0 1)
                     "_non" (trans p2 0 1)
                     "_non" (trans (cdc:loc p1 p2 0.5 cdc:*offset*) 0 1))
            (setq new (entlast))
            (if (and new (not (eq new pre)))
              (progn
                ;; slide the text down the dimension line, out of the
                ;; middle -- DIMTEDIT moves the text alone, and the move
                ;; is along the dimension line, so the line itself does
                ;; not shift whatever DIMTMOVE says
                (if (not (equal cdc:*textpos* 0.5 1e-6))
                  (command "_.DIMTEDIT" new
                           "_non" (trans (cdc:loc p1 p2
                                                  (cdc:textfrac p1 p2)
                                                  cdc:*offset*)
                                         0 1)))
                (cdc:fixdim new havestyle)
                (setq made (1+ made))
                ;; only a line that really did get its dimension is
                ;; erased -- a dim AutoCAD refused to draw leaves its
                ;; line in the drawing to be dealt with
                (if (and cdc:*erase* (entget en))
                  (progn (entdel en)
                         (setq gone (1+ gone))
                         (if (not (member (cadddr pr) lays))
                           (setq lays (cons (cadddr pr) lays))))))))

          ;; -- 5. put the drawing back the way it was
          (cdc:restyle odim)
          (command "_.UNDO" "_End")
          (setq undo-open nil)

          (princ (strcat "\n" (itoa made) " cross dimension"
                         (if (= made 1) "" "s") " created on layer "
                         cdc:*layer*
                         (if havestyle
                           (strcat " in style " cdc:*style* ".")
                           " (current style).")))
          (if (> gone 0)
            (princ (strcat "\n" (itoa gone) " dimensioned line"
                           (if (= gone 1) "" "s") " erased (layer"
                           (if (= 1 (length lays)) " " "s ")
                           (cdc:names (reverse lays)) ").")))
          (if (> already 0)
            (princ (strcat "\n" (itoa already) " line"
                           (if (= already 1) "" "s")
                           " left alone -- those two points carry a"
                           " dimension already.")))
          (if (> skipped 0)
            (princ (strcat "\n" (itoa skipped)
                           " selected object(s) were not lines and were"
                           " left alone."
                           (if (> plines 0)
                             " Explode a polyline to cross-dim its segments."
                             ""))))))))

  ;; every path out of the command drops the snapshot, the quiet ones
  ;; included: a run that found nothing to do and kept its snapshot
  ;; would hand it to the NEXT run, which would then put the user's
  ;; settings back to what they were two commands ago
  (cdc:sysrestore)
  (setq *error* olderr)
  (princ))

(defun c:CDCREATEVER ()
  (princ (strcat "\nCDCREATE " *cdcreate-version*))
  (princ))

(princ (strcat "\nCDCREATE " *cdcreate-version*
               " loaded -- dimension highlighted lines as cross dims"
               " (style \"" cdc:*style* "\", layer \"" cdc:*layer* "\")."))
(princ)
