;;; ===================================================================
;;; CDCALLOUT.lsp  --  cross-dimension from Pt.## to Pt.## by number
;;; -------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP; needs the Visual LISP
;;; engine that ships with full AutoCAD -- LT cannot run this).
;;;
;;; Command:  CDCALLOUT
;;;
;;; The dimensioning sister of BPCALLOUT.  Instead of clicking points,
;;; you name them: type the FROM point number and the TO point number,
;;; and an aligned dimension is drawn between those two survey points
;;; -- the dimension line sitting right inbetween, on the tie itself,
;;; exactly where CDCREATE puts its (nudge cdo:*offset* to push it
;;; off) -- in the "CROSS DIMENSIONS" dimension style, on the
;;; "DIMENSION" layer, ByLayer, the same convention CDCREATE and POOL
;;; use.  Rinse and repeat: EVERY TIE IS ITS OWN PAIR -- a drawn
;;; dimension returns to the FROM prompt, so the next tie names both
;;; of its own points.  Enter at the TO prompt skips that one and
;;; re-asks FROM; Enter at the FROM prompt finishes.  Nothing is ever
;;; clicked.
;;;
;;; v1.7 chained instead, anchoring the next tie on the last TO point
;;; so a run round the pool cost one number per tie.  That is not what
;;; cross dims are: they are whichever two points the drafter wants
;;; tied, in whatever order the sheet needs them, and guessing the
;;; next FROM was wrong more often than it was convenient.
;;;
;;; Point numbers are typed the way they read in the drawing: "35",
;;; "Pt.35", "pt 35", "#35" and "035" all name the same point -- the
;;; number is matched against the "number" attribute on the survey
;;; point blocks: an "ab_pt" INSERT on any layer, or any other INSERT
;;; on the POINTS layer.  That is BPCALLOUT's and LHD's classifier
;;; minus its third kind -- a plain POINT carries no attribute, so it
;;; has no number to be asked for by, and this tool only ever names
;;; points.  A block whose number cannot be read is left out for the
;;; same reason.
;;;
;;; A number that names no point in the drawing is reported and the
;;; prompt re-asks -- nothing is drawn from a typo.  The whole run is
;;; one undo group: a single U takes every dimension away.
;;;
;;; A NUMBER THE DRAWING CARRIES TWICE.  A sheet can hold two surveys --
;;; two pools in one yard, or two field sheets merged -- and each
;;; numbers its points from 1, so "1" names two different places.  A tie
;;; to the wrong one runs across the drawing and measures nothing
;;; anybody taped, so it is not guessed at: every point carrying the
;;; number is ringed on screen in cdo:*pick-color* on a throwaway layer
;;; of its own, labelled P1, P2, ... in drawing order, and the run says
;;; what tells them apart --
;;;
;;;     2 points are numbered "7" - each one is ringed and labelled
;;;     on screen.
;;;      tag   from Pt.1
;;;      ----  ------------
;;;      P1    8'-4"
;;;      P2    20'-0"
;;;
;;;     Which Pt.7 is meant - click it, or type its label [Back]
;;;     <Enter = none>:
;;;
;;; -- which at the TO prompt is how long the dimension each one would
;;; draw is, the number the drafter has on the sheet in front of them,
;;; and at the FROM prompt, where there is no other end yet, is where
;;; each one sits.  Click the one you want or type its label; Back
;;; re-asks the number, Enter takes none and draws nothing.  The rings
;;; go as soon as it is answered.
;;;
;;; A number only ONE point carries is taken exactly as it always was:
;;; nothing is ringed, nothing is asked, nothing is printed.
;;;
;;; Going back a step follows the shared Back convention (see the root
;;; README): B/BACK/U/UNDO at the TO prompt re-asks FROM, and Back at
;;; the FROM prompt (offered once something is drawn) un-draws the
;;; last dimension.  Back at the ringed points re-asks the number they
;;; came from - the FROM number at the FROM prompt, the TO number at
;;; the TO prompt - because that is the question in front of them.
;;;
;;; A missing "CROSS DIMENSIONS" style is NOT invented: the dims are
;;; drawn in whatever style is current and the routine says so, so a
;;; drawing started from the wrong template is obvious instead of
;;; silently producing wrong-looking dims (CDCREATE's rule, kept).
;;;
;;; Every knob - style, layer and its colour, the dimension-line
;;; offset, the same-spot tolerance, what counts as a survey point - is
;;; in the configuration block right below, each with its explanation.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *cdcallout-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ===================================================================

;;; -------------------- version ---------------------------------------
(setq *cdcallout-version* "v1.10")  ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------
;;; Every knob the routine has, in one place, so nothing below this
;;; block needs touching to adapt it.  Change a value here, or (setq ...)
;;; it after loading from a startup file.  Distances are DRAWING UNITS.

;; -- how the dimensions land (CDCREATE's and POOL's convention)
(setq cdo:*style* "CROSS DIMENSIONS") ; dimension style the dims are
                                    ; drawn in.  NOT invented when the
                                    ; drawing lacks it: the dims then
                                    ; take the current style and the run
                                    ; says so, because a wrong template
                                    ; should be obvious, not papered over
(setq cdo:*layer* "DIMENSION")      ; layer the dims land on, ByLayer
                                    ; (colour, linetype and lineweight
                                    ; overrides stripped).  Created when
                                    ; the drawing lacks it; thawed,
                                    ; unlocked and switched on when it
                                    ; is there but unusable
(setq cdo:*layer-color* 7)          ; ACI colour that layer is CREATED
                                    ; with (7 = white/black).  A layer
                                    ; already in the drawing keeps its
                                    ; own
(setq cdo:*offset* 0.0)             ; distance the dimension line is
                                    ; pushed off the tie it measures.
                                    ; 0.0 = right inbetween, on the tie
                                    ; itself (CDCREATE's convention);
                                    ; positive = to the left of the
                                    ; FROM->TO direction, negative = to
                                    ; the right
(setq cdo:*exact-eps* 0.001)        ; two survey points closer than
                                    ; this sit on the same spot: the
                                    ; tie is refused, nothing to measure

;; -- what counts as a survey point.  The classifier is shared with
;;    BPCALLOUT and LHD: change it in all three or the tools disagree
(setq cdo:*point-block* "ab_pt")    ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq cdo:*point-layer* "POINTS")   ; layer whose INSERTs are always
                                    ; points, whatever block they are
(setq cdo:*pt-tag* "number")        ; attribute tag on the point block
                                    ; naming the point.  A block without
                                    ; it lends its first attribute that
                                    ; reads as a number instead

;; -- how a number that names MORE THAN ONE point is asked about
(setq cdo:*pick-layer* "CDCALLOUT-PICK") ; the rings round the points a
                                    ; doubled number names get a layer
                                    ; of their OWN, never the points
                                    ; layer: they are throwaway, they
                                    ; would inherit the points layer's
                                    ; colour, and while they existed
                                    ; every other tool in the toolset
                                    ; would count them as real survey
                                    ; points.  Created when missing, and
                                    ; erased as soon as the question is
                                    ; answered
(setq cdo:*pick-color* 4)           ; colour of that layer, and an
                                    ; entity override to match: cyan, so
                                    ; a ring reads as a question and not
                                    ; as drawn work
(setq cdo:*pick-radius* 9.0)        ; radius of one of those rings, in
                                    ; drawing units - wide enough to
                                    ; stand clear of the point block's
                                    ; own number
(setq cdo:*pick-hgt* 5.0)           ; height of the label beside it -
                                    ; above the 4" point numbers
(setq cdo:*pick-prefix* "P")        ; what those labels are called, on
                                    ; screen and at the prompt: P1, P2,
                                    ; ... in drawing order
(setq cdo:*prec* 4)                 ; rtos precision for the distances
                                    ; printed in the table: 4 = 1/16"

;;; -------------------- point lookup ------------------------------------

;; The name carried by a point block, read from its cdo:*pt-tag*
;; attribute; when the block has no such attribute, the first
;; attribute whose value reads as a number is taken instead (survey
;; exports do not all use the ab_pt tag).  nil when neither exists.
(defun cdo:block-number (en / sub ed val fall v)
  (setq sub (entnext en) val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase cdo:*pt-tag*)))
      (setq val v))
    (if (and (null fall) v (distof v 2))
      (setq fall v))
    (setq sub (entnext sub)))
  (if val val fall))

;; Every NAMED survey point in the drawing, as ((x y z) . name) pairs.
;; What counts as a point matches BPCALLOUT/LHD; a point whose number
;; cannot be read is left out -- it cannot be asked for by name.
(defun cdo:collect-points (/ ss i en ed typ p nm out)
  (setq out nil
        ss  (ssget "_X" '((0 . "INSERT"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en (ssname ss i)
              ed (entget en)
              p  (cdr (assoc 10 ed)))
        (if (or (= (strcase (cdr (assoc 2 ed)))
                   (strcase cdo:*point-block*))
                (= (strcase (cdr (assoc 8 ed)))
                   (strcase cdo:*point-layer*)))
          (progn
            (setq nm (cdo:block-number en))
            (if (and nm (/= nm ""))
              (setq out (cons (cons (list (car p) (cadr p) 0.0) nm)
                              out)))))
        (setq i (1+ i)))))
  (reverse out))

;; One comparable form for a point number, so "35", "Pt.35", "pt 35",
;; "#35" and "035" all meet in the middle: uppercase, spaces and
;; hashes dropped, a leading "PT" / "PT." dropped, and a value that
;; reads as a number rendered numerically (so leading zeros don't
;; matter).  Only the dot right after PT is a prefix dot - a point
;; genuinely named "40.5" keeps its decimal.
(defun cdo:canon (s / out i ch)
  (setq s (strcase s) out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (not (member ch '(" " "#")))
      (setq out (strcat out ch)))
    (setq i (1+ i)))
  (if (and (>= (strlen out) 2) (= (substr out 1 2) "PT"))
    (progn
      (setq out (substr out 3))
      (if (= (substr out 1 1) ".") (setq out (substr out 2)))))
  (if (distof out 2)
    (rtos (distof out 2) 2 8)
    out))

;; T when a typed answer is the shared Back convention: B, BACK, U or
;; UNDO alone, any case (typed prompts cannot take keywords, so Back
;; is typed like a value - see "Going back a step" in the root README).
(defun cdo:backp (s)
  (member (strcase s) '("B" "BACK" "U" "UNDO")))

;; EVERY survey point a typed number names, in drawing order.  A
;; drawing CAN carry the same number twice - two surveys merged onto one
;; sheet, each numbering its points from 1 - and then which of them the
;; tie runs to is a real question with a wrong answer, so the caller
;; asks it rather than taking the first.
(defun cdo:matches (s cands / want out c)
  (setq want (cdo:canon s) out nil)
  (foreach c cands
    (if (= (cdo:canon (cdr c)) want) (setq out (cons c out))))
  (reverse out))

;; Leading and trailing blanks off a typed answer.
(defun cdo:trim (s / i n)
  (setq i 1 n (strlen s))
  (while (and (<= i n) (= " " (substr s i 1))) (setq i (1+ i)))
  (while (and (>= n i) (= " " (substr s n 1))) (setq n (1- n)))
  (if (> i n) "" (substr s i (1+ (- n i)))))

;; A distance as the drawing reads it: feet and inches to cdo:*prec*.
(defun cdo:fmt (d) (rtos d 4 cdo:*prec*))

;; S padded out to W characters, so the table below lines up.
(defun cdo:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;;; -------------------- dimension helpers (CDCREATE's, kept) ------------

;; midpoint of p1->p2, pushed perpendicular to the tie by dist
;; (dist 0.0 puts the dimension line straight inbetween, on the tie)
(defun cdo:loc (p1 p2 dist / dx dy d m)
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

;; make a layer current, creating it first when the drawing lacks it
(defun cdo:ensure-layer (name color / rec ed flags col fixed)
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

;; make that layer current, creating or repairing it on the way
(defun cdo:setlayer (name)
  (setvar "CLAYER" (cdo:ensure-layer name cdo:*layer-color*)))

;; restore a dimension style by name when the drawing has it;
;; returns T when the style was set
(defun cdo:setstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; a copy of an entget list with every entry for group CODE dropped
(defun cdo:strip (code lst / out g)
  (foreach g lst (if (/= code (car g)) (setq out (cons g out))))
  (reverse out))

;; force a freshly drawn dimension onto the layer and style CDCALLOUT
;; promises, ByLayer -- DIMLAYER, a style-owned layer or a leftover
;; per-entity override would otherwise have the last word
(defun cdo:fixdim (en havestyle / ed code)
  (if (and en (setq ed (entget en))
           (= "DIMENSION" (cdr (assoc 0 ed))))
    (progn
      (setq ed (if (assoc 8 ed)
                 (subst (cons 8 cdo:*layer*) (assoc 8 ed) ed)
                 (append ed (list (cons 8 cdo:*layer*)))))
      (if havestyle
        (setq ed (if (assoc 3 ed)
                   (subst (cons 3 cdo:*style*) (assoc 3 ed) ed)
                   (append ed (list (cons 3 cdo:*style*))))))
      (foreach code '(62 6 370) (setq ed (cdo:strip code ed)))
      (entmod ed)
      (entupd en)
      t)))

;;; -------------------- which of several points -------------------------
;;; A number that names ONE point is simply taken, and none of this is
;;; ever seen.  A number that names several is a sheet carrying two
;;; surveys, each numbered from 1, and picking the wrong one draws a
;;; dimension across the drawing that measures nothing anybody taped.
;;; So every one of them is ringed on screen, labelled P1, P2, ... in
;;; drawing order, and the label is what you type - or you click the one
;;; you want, which is the same answer.

;; A ring round one of the points a doubled number names, and the label
;; that says which it is, up and to the right of the ring so it clears
;; both the ring and the point's own number underneath it.  Scaffolding:
;; its own layer, erased the moment the question is answered.
(defun cdo:mark-pick (p tag / out)
  (setq out nil)
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 (cons 8 cdo:*pick-layer*)
                 (cons 62 cdo:*pick-color*) '(100 . "AcDbCircle")
                 (list 10 (car p) (cadr p) 0.0)
                 (cons 40 cdo:*pick-radius*)))
  (setq out (cons (entlast) out))
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 (cons 8 cdo:*pick-layer*)
                 (cons 62 cdo:*pick-color*) '(100 . "AcDbText")
                 (list 10 (+ (car  p) cdo:*pick-radius*)
                          (+ (cadr p) cdo:*pick-radius*) 0.0)
                 (cons 40 cdo:*pick-hgt*) (cons 1 tag)))
  (cons (entlast) out))

;; Erase a list of entities, skipping any that has gone already.
(defun cdo:drop (lst / e)
  (foreach e lst (if (and e (entget e)) (entdel e))))

;; Everything on the pick layer, gone.  The rings are erased as soon as
;; the question is answered; this is the path Esc takes, where the erase
;; never runs - and sweeping the LAYER rather than a list is what makes
;; it safe to call from the error handler, which has no list.
(defun cdo:sweep ( / ss i)
  (if (setq ss (ssget "_X" (list (cons 8 cdo:*pick-layer*))))
    (progn
      (setq i (sslength ss))
      (while (> i 0) (entdel (ssname ss (setq i (1- i))))))))

;; The label the Nth candidate carries.
(defun cdo:pick-tag (n)
  (strcat cdo:*pick-prefix* (itoa n)))

;; Ring every point HITS names and print what tells them apart: where
;; each one sits, and - at the TO prompt, where the other end is already
;; settled - how long the dimension choosing it would draw, which is the
;; number the drafter is checking against the sheet.  Returns what was
;; drawn, for the caller to erase.
(defun cdo:show-picks (nm hits from / out n c)
  (cdo:ensure-layer cdo:*pick-layer* cdo:*pick-color*)
  (setq out nil n 0)
  (foreach c hits
    (setq n   (1+ n)
          out (append out (cdo:mark-pick (car c) (cdo:pick-tag n)))))
  (princ (strcat "\n  " (itoa (length hits)) " points are numbered \""
                 nm "\" - each one is ringed and labelled on screen."))
  (princ (strcat "\n   " (cdo:pad "tag" 6)
                 (if from
                   (strcat "from Pt." (cdr from))
                   "at")))
  (princ (strcat "\n   " (cdo:pad "----" 6)
                 (if from "------------" "--------------------------")))
  (setq n 0)
  (foreach c hits
    (setq n (1+ n))
    (princ (strcat "\n   " (cdo:pad (cdo:pick-tag n) 6)
                   (if from
                     (cdo:fmt (distance (car from) (car c)))
                     (strcat (cdo:fmt (car  (car c))) ", "
                             (cdo:fmt (cadr (car c))))))))
  out)

;; Which of them was meant.  ONE prompt, two ways to answer it: click
;; the one you want, or type its label.  (initget 128) hands typed text
;; back from getpoint as the string it is while a click comes back as
;; the point it is, which is how the AB tools take both at one prompt
;; too.  A click takes the NEAREST - there is nothing else on that layer
;; to hit - and what was taken is read back before anything is drawn.
;; Returns the point, 'CDO-BACK, or nil for Enter.
(defun cdo:ask-pick (nm hits / ans best bd n d c)
  (initget 128)
  (setq ans (getpoint (strcat "\n  Which Pt." nm
                              " is meant - click it, or type its"
                              " label [Back] <Enter = none>: ")))
  (cond
    ((null ans) nil)
    ((and (not (listp ans)) (cdo:backp ans)) 'CDO-BACK)
    ((listp ans)
     (setq best nil bd nil n 0)
     (foreach c hits
       (setq n (1+ n)
             d (distance (list (car ans) (cadr ans) 0.0) (car c)))
       (if (or (null bd) (< d bd)) (setq best (list n c) bd d)))
     best)
    (t
     (setq best nil n 0)
     (foreach c hits
       (setq n (1+ n))
       (if (and (null best)
                (= (strcase (cdo:trim ans)) (cdo:pick-tag n)))
         (setq best (list n c))))
     (if best
       best
       (progn (princ (strcat "\n  \"" ans "\" is not one of the labels"
                             " - type one of them, or click the point"
                             " you want."))
              'CDO-AGAIN)))))

;; The one of HITS the typed number names: itself when only one point
;; carries it, otherwise the one the drafter picked out of the ringed
;; set.  TEMPS is where the rings are registered so the error handler
;; can take them away; the caller passes the list it keeps.  Returns
;; the point, 'CDO-BACK, or nil.
(defun cdo:settle (s cands from / hits nm drawn out)
  (setq hits (cdo:matches s cands)
        ;; the number as the DRAWING spells it, not as it was typed:
        ;; "pt 01" asks about Pt.1, which is what the rings are beside
        nm   (if hits (cdr (car hits)) (cdo:trim s)))
  (cond
    ((null hits) nil)
    ((= (length hits) 1) (car hits))
    (t
     (setq drawn (cdo:show-picks nm hits from) out 'CDO-AGAIN)
     (while (eq out 'CDO-AGAIN) (setq out (cdo:ask-pick nm hits)))
     (cdo:drop drawn)
     (cond
       ((eq out 'CDO-BACK) 'CDO-BACK)
       ((null out)
        (princ "\n  None taken - nothing drawn.")
        nil)
       (t
        (princ (strcat "\n  " (cdo:pick-tag (car out)) " taken: Pt."
                       (cdr (cadr out)) " at "
                       (cdo:fmt (car  (car (cadr out)))) ", "
                       (cdo:fmt (cadr (car (cadr out)))) "."))
        (cadr out))))))

;;; -------------------- the command ------------------------------------
;; NOTE: no local here may be named after a function this routine
;; calls - an AutoLISP local SHADOWS the function of the same name for
;; the whole call (the BPCALLOUT v1.0 lesson).
(defun c:CDCALLOUT (/ *error* olderr oce ocl oos odim grouped havestyle
                      cands s1 s2 a b pre new made d dimlist stage
                      done)

  ;; -- restore drawing state on error / Esc.  A dimension command may
  ;;    still be open, so talk to AutoCAD through command-s -- and close
  ;;    the undo group, or the next U would swallow the user's own work
  (setq olderr *error*)
  (defun *error* (m)
    ;; the rings round a doubled number are scaffolding, and Esc at the
    ;; prompt that asks about them is the one way out that never reaches
    ;; the erase
    (vl-catch-all-apply 'cdo:sweep nil)
    (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" odim)))
    (if ocl (setvar "CLAYER"  ocl))
    (if oos (setvar "OSMODE"  oos))
    (if oce (setvar "CMDECHO" oce))
    (if grouped (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n** Error: " m)))
    (princ))

  (vl-load-com)
  (setq oce  (getvar "CMDECHO")
        ocl  (getvar "CLAYER")
        oos  (getvar "OSMODE")
        odim (getvar "DIMSTYLE"))

  (princ (strcat "\nCDCALLOUT " *cdcallout-version*))
  (setq cands (cdo:collect-points))
  (if (null cands)
    (princ "\nNo named survey points found in the drawing -- nothing to dimension between.")
    (progn
      (princ (strcat "\n" (itoa (length cands)) " named survey point(s)"
                     " found.  Type numbers as they read in the"
                     " drawing (\"35\" or \"Pt.35\")."))
      (setvar "CMDECHO" 0)
      (setvar "OSMODE"  0)
      ;; only when undo is recording - _Begin in a drawing with UNDO
      ;; off (bit 1 of UNDOCTL clear) errors out of the command
      (if (= 1 (logand 1 (getvar "UNDOCTL")))
        (progn
          (command "_.UNDO" "_Begin")
          (setq grouped t)))
      (cdo:setlayer cdo:*layer*)
      (setq havestyle (cdo:setstyle cdo:*style*))
      (if (not havestyle)
        (princ (strcat "\n** This drawing has no \"" cdo:*style*
                       "\" dimension style -- dims drawn in \""
                       (getvar "DIMSTYLE")
                       "\" instead.  Create the style (or start"
                       " from the standard template) and re-run.")))

      ;; -- the rinse-repeat loop, as two stages so Back can re-ask
      ;;    the previous question: FROM -> TO, per the shared Back
      ;;    convention.  B/BACK/U/UNDO at TO re-asks FROM; Back at
      ;;    FROM (offered once something is drawn) un-draws the last
      ;;    dimension.
      ;;
      ;;    EVERY TIE IS ITS OWN PAIR.  A drawn dimension returns to
      ;;    the FROM prompt rather than anchoring the next tie on its
      ;;    TO point: cross dims are not a chain round the pool, they
      ;;    are whichever two points the drafter wants tied, and
      ;;    guessing the next FROM was wrong more often than it was
      ;;    convenient.  Both numbers, every time.  The dimension line
      ;;    goes right inbetween the two points -- nothing to pick.
      (setq made 0 dimlist nil stage 1 done nil)
      (while (not done)
        (cond
          ;; -- FROM: the loop head
          ((= stage 1)
           (setq s1 (getstring
                      (if dimlist
                        "\nFrom point number (Enter when done) [Back]: "
                        "\nFrom point number (Enter when done): ")))
           (cond
             ((= s1 "") (setq done t))
             ((cdo:backp s1)
              (if dimlist
                (progn
                  (entdel (car dimlist))
                  (setq dimlist (cdr dimlist)
                        made    (1- made))
                  (princ "\nStepping back one dimension."))
                (princ "\nAlready at the first dimension.")))
             ;; a number the drawing carries TWICE is two surveys on one
             ;; sheet, and the tie can only run to one of them: every
             ;; point that carries it is ringed and the question asked.
             ;; A number only one point carries is simply taken, exactly
             ;; as it always was
             ((null (setq a (cdo:settle s1 cands nil)))
              (if (null (cdo:matches s1 cands))
                (princ (strcat "\n  No point numbered \"" s1
                               "\" in the drawing -- nothing drawn."))))
             ;; Back at the ringed points re-asks the number itself:
             ;; that is the question in front of it
             ((eq a 'CDO-BACK)
              (princ "\n  Back to the point number."))
             (t (setq stage 2))))
          ;; -- TO: a good answer draws the dimension right away and
          ;;    the loop goes back to FROM for the next pair
          (t
           (setq s2 (getstring (strcat "\nTo point number (from Pt."
                                       (cdr a) ") [Back]: ")))
           (cond
             ((= s2 "")
              (princ "\n  No second point -- this one skipped.")
              (setq stage 1))
             ((cdo:backp s2) (setq stage 1))
             ;; the same question, with the other end of the tie already
             ;; settled - so the table can say how long the dimension
             ;; each candidate would draw is, which is the number the
             ;; drafter has on the sheet
             ((null (setq b (cdo:settle s2 cands a)))
              (if (null (cdo:matches s2 cands))
                (princ (strcat "\n  No point numbered \"" s2
                               "\" in the drawing -- nothing drawn."))))
             ;; Back at the ringed points re-asks the TO number, which
             ;; is the question in front of them - NOT the FROM number,
             ;; which is two questions back and still settled
             ((eq b 'CDO-BACK) (princ "\n  Back to the point number."))
             ((< (distance (car a) (car b)) cdo:*exact-eps*)
              (princ (strcat "\n  Pt." (cdr a) " and Pt." (cdr b)
                             " sit on the same spot -- nothing to"
                             " measure.")))
             (t
              (setq pre (entlast))
              (command "_.DIMALIGNED"
                       "_non" (trans (car a) 0 1)
                       "_non" (trans (car b) 0 1)
                       "_non" (trans (cdo:loc (car a) (car b)
                                              cdo:*offset*) 0 1))
              (setq new (entlast))
              (if (and new (not (eq new pre)))
                (progn
                  (cdo:fixdim new havestyle)
                  (setq made    (1+ made)
                        dimlist (cons new dimlist)
                        d       (distance (car a) (car b)))
                  (princ (strcat "\n  Pt." (cdr a) " - Pt." (cdr b)
                                 " dimensioned (" (rtos d 4 4) ")."))))
              ;; and back to the FROM prompt: the next tie names both
              ;; its own points
              (setq stage 1))))))

      ;; -- put the drawing back the way it was
      (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
        (cdo:setstyle odim))
      (setvar "CLAYER"  ocl)
      (setvar "OSMODE"  oos)
      (setvar "CMDECHO" oce)
      (if grouped (command "_.UNDO" "_End"))
      (setq grouped nil)

      (princ (strcat "\nCDCALLOUT: " (itoa made) " cross dimension"
                     (if (= made 1) "" "s") " created on layer "
                     cdo:*layer*
                     (if havestyle
                       (strcat " in style " cdo:*style* ".")
                       " (current style).")))))

  (setq *error* olderr)
  (princ))

(defun c:CDCALLOUTVER ()
  (princ (strcat "\nCDCALLOUT " *cdcallout-version*))
  (princ))

(princ (strcat "\nCDCALLOUT " *cdcallout-version*
               " loaded. Command: CDCALLOUT (cross-dimension from"
               " Pt.## to Pt.## by number, style \"" cdo:*style*
               "\", layer \"" cdo:*layer* "\")."))
(princ)
