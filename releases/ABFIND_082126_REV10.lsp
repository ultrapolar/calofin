;;; ======================================================================
;;; ABFIND.lsp  --  tie a survey point back to the A and B stakes
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP; needs the Visual LISP
;;; engine that ships with full AutoCAD -- LT cannot run this).
;;;
;;; Commands:  ABFIND      dimension Pt.## from A and from B
;;;            ABMOVE      the same, and then offer every place the
;;;                        point could sit if one of the two tapes was
;;;                        written down wrong; pick one and it moves
;;;            ABFINDVER   print the loaded version
;;; ======================================================================
;;;
;;; A pool is surveyed off two stakes, A and B: every point on the sheet
;;; is two tape readings, one from each stake, and the point is wherever
;;; those two distances cross.  These two commands work that way round.
;;;
;;; ABFIND
;;;   Type a point number.  Two aligned dimensions are drawn, A to the
;;;   point and B to the point -- the pair of readings the point was
;;;   plotted from -- in the "CROSS DIMENSIONS" dimension style, on the
;;;   "DIMENSION" layer, ByLayer, the dimension line sitting right on
;;;   the tie, exactly the convention CDCALLOUT and CDCREATE use.  It
;;;   keeps asking for the next number until you press Enter.  Nothing
;;;   is clicked: the stakes are found by name and the point by number.
;;;
;;; ABMOVE
;;;   Everything ABFIND does, and then the question ABFIND raises: if
;;;   this point is in the wrong place, where SHOULD it be?  One tape
;;;   is held and the other's reading is varied to every number it
;;;   could have been misread from, and each pair of distances is
;;;   crossed to a position:
;;;
;;;     * the feet came out one out       21'-1"  ->  20'-1" / 22'-1"
;;;     * the inches lost or gained a leading 1     1"  <->  11"
;;;     * a digit was read as a look-alike          21'-1" -> 21'-7"
;;;       (abf:*digit-pairs*: 1/7, 1/4, 3/8, 3/5, 5/6, 6/8, 0/9, 4/9,
;;;       7/9), in the inches or in the feet
;;;     * two feet digits changed places            21' -> 12'
;;;
;;;   Both ways round: A held while B's reading moves, then B held
;;;   while A's moves.  Only misses up to abf:*max-shift* (2 feet as
;;;   shipped) are offered -- a bigger one is a different mistake, and
;;;   the feet-digit and transposed-digit cases only show up at all
;;;   when that is raised.  The candidates are drawn on the POINTS
;;;   layer, numbered on screen and listed on the command line nearest
;;;   miss first, and you pick one by number or by clicking it.
;;;
;;;   Picking one:
;;;     * a new point is made there, numbered "17m" -- the original
;;;       number with abf:*moved-suffix* on it, so the drawing says
;;;       plainly that this one was moved (an "ab_pt" block carrying
;;;       the new number when the drawing has that block, a POINT with
;;;       a text label beside it when it does not),
;;;     * the ORIGINAL point is ringed with a 5" radius circle on the
;;;       FGStep layer, so the spot it came off is still visible,
;;;     * a note is written on FGStep reading
;;;
;;;           Moved Pt.17 B from 21'-1" to 21'-7"
;;;
;;;       naming the tape that moved -- the one that was NOT held --
;;;       and both of its readings, and
;;;     * the two dimensions are redrawn to where the point now is, so
;;;       the sheet measures the position it is claiming.  The old
;;;       reading is not lost: the note carries it.
;;;
;;;   None (the Enter answer) leaves the point alone and keeps the two
;;;   dimensions -- ABMOVE has then done exactly what ABFIND does.
;;;
;;; THE STAKES.  A and B are looked up by name among the survey points,
;;; the same way any other point is: an "ab_pt" INSERT anywhere or any
;;; other INSERT on the POINTS layer, named by its "number" attribute
;;; (the classifier BPCALLOUT, CDCALLOUT and LHD all share).  A drawing
;;; that does not name them asks you to click each one instead, once
;;; per run, snapping to the nearest survey point within abf:*snap*.
;;;
;;; Point numbers are typed the way they read in the drawing: "35",
;;; "Pt.35", "pt 35", "#35" and "035" all name the same point.  A
;;; number that names nothing is reported and the prompt re-asks --
;;; nothing is drawn from a typo.
;;;
;;; Going back a step follows the shared Back convention (see the root
;;; README): B/BACK/U/UNDO typed at the point number un-does the whole
;;; of the last round -- its dimensions, and, if it moved a point, the
;;; moved point, the ring and the note, with the original dimensions
;;; put back.  Back at ABMOVE's later questions re-asks the one before.
;;;
;;; A missing "CROSS DIMENSIONS" style is NOT invented: the dims are
;;; drawn in whatever style is current and the routine says so, so a
;;; drawing started from the wrong template is obvious instead of
;;; silently producing wrong-looking dims (CDCREATE's rule, kept).
;;;
;;; The whole run is one undo group: a single U takes it all away.
;;;
;;; Assumes drawing units are INCHES (architectural) and plan north is
;;; +Y -- the compass letter in the table is read off that.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *abfind-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ======================================================================

(vl-load-com)

;;; ---------------------- configuration ---------------------------------

(setq *abfind-version* "v1.0")      ; announced on load; release_lisp.py
                                    ; reads this banner and stamps the
                                    ; dated twin in releases/ from it

(setq abf:*style*        "CROSS DIMENSIONS") ; dimension style to use
(setq abf:*layer*        "DIMENSION")   ; layer the dims land on
(setq abf:*offset*       0.0)       ; distance the dimension line is
                                    ; pushed off the tie it measures,
                                    ; drawing units (0.0 = right on the
                                    ; tie -- CDCREATE's convention)
(setq abf:*point-block*  "ab_pt")   ; block name whose INSERTs mark
                                    ; points wherever they sit
(setq abf:*point-layer*  "POINTS")  ; layer whose INSERTs are always
                                    ; points, and the layer the moved
                                    ; point and the suggestions go on
(setq abf:*pt-tag*       "number")  ; attribute tag on the point block
                                    ; naming the point, as in "Pt.17"
(setq abf:*a-name*       "A")       ; what the two stakes are numbered
(setq abf:*b-name*       "B")       ; in the drawing
(setq abf:*snap*         12.0)      ; a click within this of a survey
                                    ; point takes THAT point
(setq abf:*ring-layer*   "FGStep")  ; layer the ring round the point
                                    ; that moved, and its note, go on -
                                    ; the same layer BPCALLOUT rings
                                    ; bad points on
(setq abf:*ring-radius*  5.0)       ; ring RADIUS (5 inches)
(setq abf:*note-hgt*     6.0)       ; height of the "Moved Pt.##" note
(setq abf:*moved-suffix* "m")       ; added to the number of a point
                                    ; that moved: Pt.17 -> Pt.17m
(setq abf:*sug-radius*   3.0)       ; radius of a suggestion's marker
                                    ; circle - smaller than the ring so
                                    ; the two never read as the same
                                    ; mark
(setq abf:*sug-hgt*      6.0)       ; height of a suggestion's number
(setq abf:*max-shift*    24.0)      ; biggest misreading offered, in
                                    ; inches.  2 feet covers a foot
                                    ; out, the 1"/11" slip and every
                                    ; look-alike inch digit; raise it
                                    ; to let the feet digits in too
                                    ; (a 3 read as an 8 is 5 feet)
(setq abf:*max-sugg*     12)        ; most suggestions offered at once
(setq abf:*prec*         4)         ; rtos precision for every distance
                                    ; printed or written: 4 = 1/16"
(setq abf:*same-eps*     0.125)     ; two suggestions this close are
                                    ; the same place; only one is kept
(setq abf:*fuzz*         1e-6)      ; zero-length / same-spot tolerance
(setq abf:*att-height*   4.0)       ; height of the moved point's
(setq abf:*att-offset*   '(0.8697246 -3.5316825)) ; number, and where
                                    ; it sits relative to the point
                                    ; (both as the ab_pt block has it)
(setq abf:*digit-pairs*             ; digits a field sheet confuses for
  '(("1" "7") ("1" "4") ("3" "8")   ; each other, both ways round
    ("3" "5") ("5" "6") ("6" "8")
    ("0" "9") ("4" "9") ("7" "9")))

;;; ---------------------- ask helpers -----------------------------------
;;; Copied from CALOFIN-LIB.lsp (cal:askkw, cal:back-word-p) under this
;;; file's own prefix, so the standalone file loads alone -- see
;;; STANDARDS.md section 4.  Back sentinel: ABF-BACK.

;; Keyword question.  kws is the initget list, shown the bracketed text,
;; dflt the Enter answer (nil = an answer is required).  Returns the
;; keyword or ABF-BACK.  Undo is accepted everywhere Back is, unlisted.
(defun abf:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'ABF-BACK)
        ((null v) (if dflt dflt (abf:askkw msg kws shown dflt back)))
        (t v)))

;; Typed prompts cannot take keywords, so Back is typed like a value.
(defun abf:back-word-p (s)
  (member (strcase s) '("B" "BACK" "U" "UNDO")))

;;; ---------------------- layers ----------------------------------------

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; (cal:ensure-layer, copied under this file's prefix.)
(defun abf:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nABFIND: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; Make a layer current, creating it first when the drawing lacks it.
(defun abf:setlayer (name)
  (abf:ensure-layer name 7)
  (setvar "CLAYER" name))

;;; ---------------------- point lookup ----------------------------------

;; The name carried by a point block, read from its abf:*pt-tag*
;; attribute; when the block has no such attribute, the first attribute
;; whose value reads as a number is taken instead (survey exports do
;; not all use the ab_pt tag).  nil when neither exists.
;; (cal:block-number, copied under this file's prefix.)
(defun abf:block-number (en / sub ed val fall v)
  (setq sub (entnext en) val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase abf:*pt-tag*)))
      (setq val v))
    (if (and (null fall) v (distof v 2))
      (setq fall v))
    (setq sub (entnext sub)))
  (if val val fall))

;; Every NAMED survey point in the drawing, as ((x y z) . name) pairs.
;; What counts as a point matches BPCALLOUT/CDCALLOUT/LHD; a point
;; whose number cannot be read is left out -- it cannot be asked for by
;; name, and it cannot be a stake either.
(defun abf:collect-points (/ ss i en ed p nm out)
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
                   (strcase abf:*point-block*))
                (= (strcase (cdr (assoc 8 ed)))
                   (strcase abf:*point-layer*)))
          (progn
            (setq nm (abf:block-number en))
            (if (and nm (/= nm ""))
              (setq out (cons (cons (list (car p) (cadr p) 0.0) nm)
                              out)))))
        (setq i (1+ i)))))
  (reverse out))

;; One comparable form for a point number, so "35", "Pt.35", "pt 35",
;; "#35" and "035" all meet in the middle: uppercase, spaces and hashes
;; dropped, a leading "PT" / "PT." dropped, and a value that reads as a
;; number rendered numerically (so leading zeros do not matter).  Only
;; the dot right after PT is a prefix dot - a point genuinely named
;; "40.5" keeps its decimal.  (CDCALLOUT's cdo:canon.)
(defun abf:canon (s / out i ch)
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

;; The survey point the typed number names, or nil.  The first match
;; wins when a drawing carries the same number twice.
(defun abf:find-point (s cands / want found c)
  (setq want (abf:canon s) found nil)
  (foreach c cands
    (if (and (null found) (= (abf:canon (cdr c)) want))
      (setq found c)))
  found)

;; The survey point nearest to pick PK, when one sits within
;; abf:*snap* of it; nil otherwise.  Returns the ((x y z) . name) pair.
(defun abf:nearest (pk cands / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (abf:dist pk (car c)))
    (if (and (<= d abf:*snap*) (or (null bd) (< d bd)))
      (setq best c bd d)))
  best)

;; Where a stake is: the point named NAME when the drawing names one,
;; otherwise a click (snapped to the nearest survey point when there is
;; one under it).  nil when the user presses Enter instead.
(defun abf:stake (name cands / hit pk)
  (if (setq hit (abf:find-point name cands))
    (progn
      (princ (strcat "\n  Stake " name " found at Pt." (cdr hit) "."))
      (car hit))
    (progn
      (princ (strcat "\nNo point is numbered \"" name
                     "\" in this drawing - click the " name
                     " stake instead."))
      (if (setq pk (getpoint (strcat "\nPick the " name
                                     " stake (Enter to cancel): ")))
        (progn
          (setq hit (abf:nearest pk cands))
          (if hit
            (progn
              (princ (strcat "\n  Taken from Pt." (cdr hit) "."))
              (car hit))
            (progn
              (princ (strcat "\n  No survey point within "
                             (rtos abf:*snap* 4 0)
                             " of the click - using the click itself."))
              (list (car pk) (cadr pk) 0.0))))))))

;;; ---------------------- geometry --------------------------------------

(defun abf:2d (p) (list (car p) (cadr p)))
(defun abf:dist (a b) (distance (abf:2d a) (abf:2d b)))

;; An angle brought into [0, 2pi).
(defun abf:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;; The 8-point compass name for ANG (0 = east), reading the drawing the
;; way it is plotted: plan north is +Y.
(defun abf:compass (ang / i)
  (setq i (rem (fix (+ 0.5 (/ (abf:angnorm ang) (/ pi 4.0)))) 8))
  (nth i '("E" "NE" "N" "NW" "W" "SW" "S" "SE")))

;; Where circle (ca ra) meets circle (cb rb), as a 3-D point.  The two
;; circles meet twice, mirrored across the A-B line; a misread tape
;; never flips a point to the far side of the stakes, so the crossing
;; nearer NEAR - the point as it is drawn now - is the one meant.  nil
;; when the two circles never reach each other at all.
(defun abf:circint (ca ra cb rb near / d ux uy m h2 h bx by p1 p2)
  (setq d (abf:dist ca cb))
  (if (> d abf:*fuzz*)
    (progn
      (setq ux (/ (- (car cb) (car ca)) d)
            uy (/ (- (cadr cb) (cadr ca)) d)
            m  (/ (+ (* d d) (* ra ra) (- (* rb rb))) (* 2.0 d))
            h2 (- (* ra ra) (* m m)))
      (if (>= h2 0.0)
        (progn
          (setq h  (sqrt h2)
                bx (+ (car ca) (* m ux))
                by (+ (cadr ca) (* m uy))
                p1 (list (- bx (* h uy)) (+ by (* h ux)) 0.0)
                p2 (list (+ bx (* h uy)) (- by (* h ux)) 0.0))
          (if (< (abf:dist p1 near) (abf:dist p2 near)) p1 p2))))))

;; Midpoint of p1->p2, pushed perpendicular to the tie by dist (dist
;; 0.0 puts the dimension line straight inbetween, on the tie itself).
;; (CDCALLOUT's cdo:loc.)
(defun abf:loc (p1 p2 dist / dx dy d m)
  (setq m (list (* 0.5 (+ (car  p1) (car  p2)))
                (* 0.5 (+ (cadr p1) (cadr p2)))
                0.0))
  (if (equal dist 0.0 1e-12)
    m
    (progn
      (setq dx (- (car  p2) (car  p1))
            dy (- (cadr p2) (cadr p1))
            d  (sqrt (+ (* dx dx) (* dy dy))))
      (if (> d 1e-9)
        (list (+ (car  m) (* dist (/ (- dy) d)))
              (+ (cadr m) (* dist (/ dx d)))
              0.0)
        m))))

;;; ---------------------- readings and misreadings ----------------------

;; A distance the way the sheet writes it.
(defun abf:fmt (d) (rtos d 4 abf:*prec*))

;; Right-pad a string to WIDTH.
(defun abf:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; D's architectural reading as (feet whole-inches).  Rounded to the
;; nearest 1/16 first, so a distance a hair under a whole inch reads as
;; that inch and not as the one below it.
(defun abf:reading (d / w ft)
  (setq w  (fix (/ (+ (* (abs d) 16.0) 0.5) 16.0))
        ft (fix (/ (float w) 12.0)))
  (list ft (- w (* 12 ft))))

;; Every number N could have been, one digit at a time, when a digit is
;; read as its look-alike (abf:*digit-pairs*, both ways round).
(defun abf:digit-swaps (n / s i out ch pr alt new)
  (setq s (itoa n) i 1 out nil)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (foreach pr abf:*digit-pairs*
      (setq alt (cond ((= ch (car  pr)) (cadr pr))
                      ((= ch (cadr pr)) (car  pr))))
      (if alt
        (progn
          (setq new (atoi (strcat (substr s 1 (1- i)) alt (substr s (1+ i)))))
          (if (and (>= new 0) (/= new n) (not (member new out)))
            (setq out (cons new out))))))
    (setq i (1+ i)))
  (reverse out))

;; Every number N could have been with two neighbouring digits written
;; the other way round (21 -> 12).
(defun abf:digit-flips (n / s i out new)
  (setq s (itoa n) i 1 out nil)
  (while (< i (strlen s))
    (setq new (atoi (strcat (substr s 1 (1- i))
                            (substr s (1+ i) 1)
                            (substr s i 1)
                            (substr s (+ i 2)))))
    (if (and (/= new n) (not (member new out)))
      (setq out (cons new out)))
    (setq i (1+ i)))
  (reverse out))

;; V inserted into the already-sorted LST, smallest miss first.
(defun abf:ins-delta (v lst)
  (cond ((null lst) (list v))
        ((< (abs v) (abs (car lst))) (cons v lst))
        (t (cons (car lst) (abf:ins-delta v (cdr lst))))))

;; Every way D's reading could have been written down for a different
;; number, as a signed shift in inches: a foot out either way, the
;; inches losing or gaining a leading 1, a look-alike digit in the
;; inches or in the feet, and two feet digits changing places.  Only
;; misses up to abf:*max-shift* survive, nearest miss first.
(defun abf:deltas (d / r ft inch raw out v)
  (setq r    (abf:reading d)
        ft   (car  r)
        inch (cadr r)
        raw  (list 12.0 -12.0))
  (foreach v '(10.0 -10.0)
    (if (and (>= (+ inch v) 0.0) (<= (+ inch v) 11.0))
      (setq raw (cons v raw))))
  (foreach v (abf:digit-swaps inch)
    (if (<= v 11) (setq raw (cons (float (- v inch)) raw))))
  (foreach v (append (abf:digit-swaps ft) (abf:digit-flips ft))
    (setq raw (cons (float (* 12 (- v ft))) raw)))
  (setq out nil)
  (foreach v raw
    (if (and (> (abs v) abf:*fuzz*)
             (<= (abs v) abf:*max-shift*)
             (> (+ d v) 0.0)
             (not (member v out)))
      (setq out (abf:ins-delta v out))))
  out)

;; C inserted into the already-sorted LST, smallest miss first.
(defun abf:ins-cand (c lst)
  (cond ((null lst) (list c))
        ((< (car c) (car (car lst))) (cons c lst))
        (t (cons (car lst) (abf:ins-cand c (cdr lst))))))

;; T when P is already where one of the candidates in LST sits, or
;; where the point itself sits - the same place twice is one choice.
(defun abf:seen-p (p pp lst / hit c)
  (setq hit (< (abf:dist p pp) abf:*same-eps*))
  (foreach c lst
    (if (< (abf:dist p (nth 5 c)) abf:*same-eps*) (setq hit T)))
  hit)

;; Every place PP could sit if ONE of its two tapes was written down
;; wrong: A held while B's reading moves, then B held while A's does.
;; Each entry is (miss held moved old-reading new-reading point), the
;; smallest miss first, capped at abf:*max-sugg*.
(defun abf:candidates (pa pb pp / a b out dl nd np n cut one)
  (setq a   (abf:dist pa pp)
        b   (abf:dist pb pp)
        out nil)
  (if (and (> a abf:*fuzz*) (> b abf:*fuzz*))
    (progn
      (foreach dl (abf:deltas b)                    ; hold A, move B
        (setq nd (+ b dl)
              np (abf:circint pa a pb nd pp))
        (if (and np (not (abf:seen-p np pp out)))
          (setq out (abf:ins-cand
                      (list (abs dl) abf:*a-name* abf:*b-name* b nd np)
                      out))))
      (foreach dl (abf:deltas a)                    ; hold B, move A
        (setq nd (+ a dl)
              np (abf:circint pa nd pb b pp))
        (if (and np (not (abf:seen-p np pp out)))
          (setq out (abf:ins-cand
                      (list (abs dl) abf:*b-name* abf:*a-name* a nd np)
                      out))))))
  (if (> (length out) abf:*max-sugg*)
    (progn
      (setq cut nil n 0)
      (foreach one out
        (if (< n abf:*max-sugg*) (setq cut (cons one cut)))
        (setq n (1+ n)))
      (setq out (reverse cut))))
  out)

;;; ---------------------- what gets drawn -------------------------------

;; Restore a dimension style by name when the drawing has it; returns T
;; when the style was set.
(defun abf:setstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; A copy of an entget list with every entry for group CODE dropped.
(defun abf:strip (code lst / out g)
  (foreach g lst (if (/= code (car g)) (setq out (cons g out))))
  (reverse out))

;; Force a freshly drawn dimension onto the layer and style ABFIND
;; promises, ByLayer -- DIMLAYER, a style-owned layer or a leftover
;; per-entity override would otherwise have the last word.
(defun abf:fixdim (en havestyle / ed code)
  (if (and en (setq ed (entget en))
           (= "DIMENSION" (cdr (assoc 0 ed))))
    (progn
      (setq ed (if (assoc 8 ed)
                 (subst (cons 8 abf:*layer*) (assoc 8 ed) ed)
                 (append ed (list (cons 8 abf:*layer*)))))
      (if havestyle
        (setq ed (if (assoc 3 ed)
                   (subst (cons 3 abf:*style*) (assoc 3 ed) ed)
                   (append ed (list (cons 3 abf:*style*))))))
      (foreach code '(62 6 370) (setq ed (abf:strip code ed)))
      (entmod ed)
      (entupd en)
      t)))

;; One aligned dimension from P1 to P2, on the tie.  Returns the new
;; entity, or nil when there was nothing to measure.
(defun abf:dim1 (p1 p2 havestyle / pre new)
  (if (> (abf:dist p1 p2) abf:*fuzz*)
    (progn
      (setq pre (entlast))
      (command "_.DIMALIGNED"
               "_non" (trans p1 0 1)
               "_non" (trans p2 0 1)
               "_non" (trans (abf:loc p1 p2 abf:*offset*) 0 1))
      (setq new (entlast))
      (if (and new (not (eq new pre)))
        (progn (abf:fixdim new havestyle) new)))))

;; The pair of ties a point is surveyed by: A to it and B to it.
(defun abf:dim-pair (pa pb pp havestyle / e out)
  (setq out nil)
  (if (setq e (abf:dim1 pa pp havestyle)) (setq out (cons e out)))
  (if (setq e (abf:dim1 pb pp havestyle)) (setq out (cons e out)))
  (reverse out))

;; The ring round the point that moved.
(defun abf:ring (ctr)
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 (cons 8 abf:*ring-layer*) '(100 . "AcDbCircle")
                 (list 10 (car ctr) (cadr ctr) 0.0)
                 (cons 40 abf:*ring-radius*)))
  (entlast))

;; The note that says what moved, and from what reading to what.
(defun abf:note (p str)
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 (cons 8 abf:*ring-layer*) '(100 . "AcDbText")
                 (list 10 (car p) (cadr p) 0.0)
                 (cons 40 abf:*note-hgt*) (cons 1 str)))
  (entlast))

;; Where the note goes when it is not placed by hand: beside the ring,
;; clear of it, the way BPCALLOUT tucks its callout.
(defun abf:note-spot (ctr)
  (list (+ (car  ctr) (* 2.0 abf:*ring-radius*))
        (- (cadr ctr) (* 2.0 abf:*ring-radius*))
        0.0))

;; A survey point at P numbered NM: the drawing's own point block when
;; it has one, a POINT with a text label beside it when it does not.
;; Returns the entities it made.
(defun abf:make-point (p nm / out apt)
  (setq out nil
        apt (list (+ (car  p) (car  abf:*att-offset*))
                  (+ (cadr p) (cadr abf:*att-offset*))
                  0.0))
  (if (tblsearch "BLOCK" abf:*point-block*)
    (progn
      (entmake (list '(0 . "INSERT") '(100 . "AcDbEntity")
                     (cons 8 abf:*point-layer*)
                     '(100 . "AcDbBlockReference") '(66 . 1)
                     (cons 2 abf:*point-block*)
                     (list 10 (car p) (cadr p) 0.0)
                     '(41 . 1.0) '(42 . 1.0) '(43 . 1.0) '(50 . 0.0)))
      (setq out (cons (entlast) out))
      (entmake (list '(0 . "ATTRIB") '(100 . "AcDbEntity") '(8 . "0")
                     '(100 . "AcDbText") (cons 10 apt)
                     (cons 40 abf:*att-height*) (cons 1 nm)
                     '(100 . "AcDbAttribute")
                     (cons 2 abf:*pt-tag*) '(70 . 0)))
      (setq out (cons (entlast) out))
      (entmake (list '(0 . "SEQEND") '(100 . "AcDbEntity")
                     (cons 8 abf:*point-layer*)))
      (setq out (cons (entlast) out)))
    (progn
      (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                     (cons 8 abf:*point-layer*) '(100 . "AcDbPoint")
                     (list 10 (car p) (cadr p) 0.0)))
      (setq out (cons (entlast) out))
      (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                     (cons 8 abf:*point-layer*) '(100 . "AcDbText")
                     (cons 10 apt) (cons 40 abf:*att-height*)
                     (cons 1 nm)))
      (setq out (cons (entlast) out))))
  (reverse out))

;; One suggestion on screen: a point where it would sit, a small circle
;; so it can be seen and clicked, and its number in the list.  All on
;; the points layer, all swept again as soon as the round ends.
(defun abf:draw-sug (p idx / out)
  (setq out nil)
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 (cons 8 abf:*point-layer*) '(100 . "AcDbPoint")
                 (list 10 (car p) (cadr p) 0.0)))
  (setq out (cons (entlast) out))
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 (cons 8 abf:*point-layer*) '(100 . "AcDbCircle")
                 (list 10 (car p) (cadr p) 0.0)
                 (cons 40 abf:*sug-radius*)))
  (setq out (cons (entlast) out))
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 (cons 8 abf:*point-layer*) '(100 . "AcDbText")
                 (list 10 (+ (car  p) abf:*sug-radius*)
                          (+ (cadr p) abf:*sug-radius*) 0.0)
                 (cons 40 abf:*sug-hgt*) (cons 1 (itoa idx))))
  (setq out (cons (entlast) out))
  (reverse out))

;; Erase a list of entities, skipping any that has gone already.
(defun abf:drop (lst / e)
  (foreach e lst (if (and e (entget e)) (entdel e))))

;; Bring a list of erased entities back (entdel un-deletes what it
;; deleted), skipping any that is still there.
(defun abf:undrop (lst / e)
  (foreach e lst (if (and e (null (entget e))) (entdel e))))

;;; ---------------------- the engine ------------------------------------
;;; ABFIND and ABMOVE are one flow: ABMOVE is ABFIND plus the two
;;; questions that move the point, so they share this and differ by the
;;; MOVEP flag.  The *error* handler lives here rather than in the
;;; command defuns because this is where the state it has to put back
;;; is - it is localized in the arglist just the same, so the previous
;;; handler comes back when the run ends (STANDARDS.md section 5).
;;;
;;; A round is remembered as ("DIM" pair) or as
;;; ("MOVE" old-pair new-pair moved-point-ents ring note) so Back can
;;; undo the whole of it, the erased dimensions included.

(defun abf:undo-round (r)
  (if (= (car r) "DIM")
    (abf:drop (cadr r))
    (progn
      (abf:drop (caddr r))                 ; the dims to where it moved
      (abf:drop (cadddr r))                ; the moved point
      (abf:drop (list (nth 4 r) (nth 5 r))); its ring and its note
      (abf:undrop (cadr r)))))             ; the dims it had before

;; NOTE: no local here may be named after a function this routine calls
;; - an AutoLISP local SHADOWS the function of the same name for the
;; whole call (the BPCALLOUT v1.0 lesson).
(defun abf:run (movep / *error* undo-open oce ocl oos odim cmd cands
                        pa pb hist stage done made moves s hit nm pp
                        pair sugs temps c i kws shown ans idx sug havestyle
                        np newpt ments ring note)

  (defun *error* (m)
    ;; user settings come back FIRST so nothing below can skip them
    (abf:drop temps)
    (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" odim)))
    (if ocl (setvar "CLAYER"  ocl))
    (if oos (setvar "OSMODE"  oos))
    (if oce (setvar "CMDECHO" oce))
    (if undo-open
      (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\n" (if cmd cmd "ABFIND") " error: " m)))
    (princ))

  (setq cmd  (if movep "ABMOVE" "ABFIND")
        oce  (getvar "CMDECHO")
        ocl  (getvar "CLAYER")
        oos  (getvar "OSMODE")
        odim (getvar "DIMSTYLE"))
  (princ (strcat "\n" cmd " " *abfind-version*))

  (setq cands (abf:collect-points))
  (if (null cands)
    (princ (strcat "\nNo named survey points found in the drawing - "
                   cmd " has nothing to tie to."))
    (progn
      (princ (strcat "\n" (itoa (length cands)) " named survey point(s)"
                     " found.  Type numbers as they read in the"
                     " drawing (\"35\" or \"Pt.35\")."))
      ;; -- the two stakes, before OSMODE goes down: a drawing that
      ;;    does not name them wants object snap for the clicks
      (setq pa (abf:stake abf:*a-name* cands))
      (if pa (setq pb (abf:stake abf:*b-name* cands)))
      (cond
        ((null pa)
         (princ (strcat "\nNo " abf:*a-name* " stake - nothing drawn.")))
        ((null pb)
         (princ (strcat "\nNo " abf:*b-name* " stake - nothing drawn.")))
        ((< (abf:dist pa pb) abf:*fuzz*)
         (princ (strcat "\nThe " abf:*a-name* " and " abf:*b-name*
                        " stakes sit on the same spot - two tapes off"
                        " one stake cannot place anything.")))
        (t
         (setvar "CMDECHO" 0)
         (setvar "OSMODE"  0)
         (command "_.UNDO" "_Begin")
         (setq undo-open T)
         (abf:setlayer abf:*layer*)
         (setq havestyle (abf:setstyle abf:*style*))
         (if (not havestyle)
           (princ (strcat "\n** This drawing has no \"" abf:*style*
                          "\" dimension style -- dims drawn in \""
                          (getvar "DIMSTYLE")
                          "\" instead.  Create the style (or start"
                          " from the standard template) and re-run.")))

         ;; -- the round loop.  Stage 1 is the point number and is all
         ;;    ABFIND has; ABMOVE goes on to stage 2 (which suggestion)
         ;;    and stage 3 (where the note goes), each backing out into
         ;;    the one before it.
         (setq hist nil stage 1 done nil made 0 moves 0 temps nil)
         (while (not done)
           (cond

             ;; -- 1: which point
             ((= stage 1)
              (setq s (getstring
                        (strcat "\nPoint number"
                                (if hist " [Back]" "")
                                " <Enter = done>: ")))
              (cond
                ((= s "") (setq done T))
                ((abf:back-word-p s)
                 (if hist
                   (progn
                     (abf:undo-round (car hist))
                     ;; a MOVE round added exactly one point to the
                     ;; lookup, and Back always pops the newest round,
                     ;; so the newest entry is the one it added
                     (if (= (car (car hist)) "MOVE")
                       (setq moves (1- moves)
                             cands (cdr cands)))
                     (setq hist (cdr hist)
                           made (1- made))
                     (princ "\nStepping back one point."))
                   (princ "\nAlready at the first point.")))
                ((null (setq hit (abf:find-point s cands)))
                 (princ (strcat "\n  No point numbered \"" s
                                "\" in the drawing - nothing drawn.")))
                ((or (< (abf:dist (car hit) pa) abf:*fuzz*)
                     (< (abf:dist (car hit) pb) abf:*fuzz*))
                 (princ (strcat "\n  Pt." (cdr hit) " IS a stake - the"
                                " ties are measured FROM it.")))
                (t
                 (setq nm   (cdr hit)
                       pp   (car hit)
                       pair (abf:dim-pair pa pb pp havestyle))
                 (if (null pair)
                   (princ (strcat "\n  Pt." nm " sits on a stake - "
                                  "there is nothing to measure."))
                   (progn
                     (setq made (1+ made))
                     (princ (strcat "\n  Pt." nm ":  " abf:*a-name* " "
                                    (abf:fmt (abf:dist pa pp)) "   "
                                    abf:*b-name* " "
                                    (abf:fmt (abf:dist pb pp))
                                    "  dimensioned."))
                     (if (not movep)
                       (setq hist (cons (list "DIM" pair) hist))
                       (progn
                         ;; -- where else could this point be?
                         (setq sugs  (abf:candidates pa pb pp)
                               temps nil)
                         (if (null sugs)
                           (progn
                             (princ (strcat
                                      "\n  No misreading within "
                                      (abf:fmt abf:*max-shift*)
                                      " puts Pt." nm " anywhere else -"
                                      " left where it is."))
                             (setq hist (cons (list "DIM" pair) hist)))
                           (progn
                             (abf:ensure-layer abf:*point-layer* 2)
                             (setq i 1)
                             (foreach c sugs
                               (setq temps (append temps
                                                   (abf:draw-sug (nth 5 c) i))
                                     i     (1+ i)))
                             (princ (strcat
                                      "\n\n  Where Pt." nm
                                      " lands if one tape was written"
                                      " down wrong (nearest miss"
                                      " first):"))
                             (princ (strcat
                                      "\n   #  held  moved  from"
                                      "          to            the point"
                                      " moves"))
                             (princ (strcat
                                      "\n   -  ----  -----  -----------"
                                      "   -----------   ---------------"))
                             (setq i 1)
                             (foreach c sugs
                               (princ (strcat
                                        "\n   " (abf:pad (itoa i) 3)
                                        (abf:pad (cadr c) 6)
                                        (abf:pad (caddr c) 7)
                                        (abf:pad (abf:fmt (cadddr c)) 14)
                                        (abf:pad (abf:fmt (nth 4 c)) 14)
                                        (abf:fmt (abf:dist pp (nth 5 c)))
                                        " "
                                        (abf:compass
                                          (angle (abf:2d pp)
                                                 (abf:2d (nth 5 c))))))
                               (setq i (1+ i)))
                             (setq stage 2))))))))))

             ;; -- 2: which suggestion (ABMOVE only)
             ((= stage 2)
              (setq kws "" i 1)
              (repeat (length sugs)
                (setq kws (strcat kws (itoa i) " ") i (1+ i)))
              (setq kws   (strcat kws "Pick None")
                    shown (vl-string-translate " " "/" kws)
                    ans   (abf:askkw
                            (strcat "  Move Pt." nm " to which?")
                            kws shown "None" T))
              (cond
                ((eq ans 'ABF-BACK)
                 (abf:drop temps)
                 (abf:drop pair)
                 (setq temps nil
                       made  (1- made)
                       stage 1)
                 (princ "\nStepping back one point."))
                ((= ans "None")
                 (abf:drop temps)
                 (setq temps nil
                       hist  (cons (list "DIM" pair) hist)
                       stage 1)
                 (princ (strcat "\n  Pt." nm " left where it is.")))
                ((= ans "Pick")
                 (initget "Back Undo")
                 (setq np (getpoint "\n  Click the one you want [Back]: "))
                 (cond
                   ((null np)
                    (princ "\n  Nothing clicked - pick from the list."))
                   ((member np '("Back" "Undo"))
                    (princ "\n  Back to the list."))
                   (t
                    (setq idx nil i 1)
                    (foreach c sugs
                      (if (and (null idx)
                               (<= (abf:dist np (nth 5 c)) abf:*snap*))
                        (setq idx i))
                      (setq i (1+ i)))
                    (if idx
                      (setq stage 3)
                      (princ (strcat "\n  No suggestion within "
                                     (rtos abf:*snap* 4 0)
                                     " of that click - try again."))))))
                (t (setq idx (atoi ans) stage 3))))

             ;; -- 3: where the note goes, and then the move itself
             (t
              (setq sug (nth (1- idx) sugs))
              (princ "\n  Auto tucks the note beside the ring.")
              (initget "Auto Back Undo")
              (setq np (getpoint (strcat "\n  Place the note for Pt." nm
                                         " [Auto/Back] <Auto>: ")))
              (if (and np (member np '("Back" "Undo")))
                (setq stage 2)
                (progn
                  ;; nil is Enter and a string is the Auto keyword;
                  ;; only a real list is a spot the user clicked
                  (if (or (null np) (not (listp np)))
                    (setq np (abf:note-spot pp)))
                  ;; the suggestions have done their job
                  (abf:drop temps)
                  (setq temps  nil
                        newpt  (nth 5 sug)
                        ments  (abf:make-point
                                 newpt (strcat nm abf:*moved-suffix*)))
                  (abf:ensure-layer abf:*ring-layer* 1)
                  (setq ring (abf:ring pp)
                        note (abf:note np
                               (strcat "Moved Pt." nm " " (caddr sug)
                                       " from " (abf:fmt (cadddr sug))
                                       " to "   (abf:fmt (nth 4 sug)))))
                  ;; the ties belong to where the point is now; the old
                  ;; reading is not lost - the note carries it
                  (abf:drop pair)
                  ;; the moved point joins the lookup, so it can be
                  ;; named again later in this same run
                  (setq cands (cons (cons newpt
                                          (strcat nm abf:*moved-suffix*))
                                    cands))
                  (setq hist (cons (list "MOVE" pair
                                         (abf:dim-pair pa pb newpt havestyle)
                                         ments ring note)
                                   hist)
                        moves (1+ moves)
                        stage 1)
                  (princ (strcat "\n  Pt." nm " moved to Pt." nm
                                 abf:*moved-suffix* " - " (cadr sug)
                                 " held at "
                                 (abf:fmt (abf:dist
                                            (if (= (cadr sug) abf:*a-name*)
                                              pa pb)
                                            newpt))
                                 ", " (caddr sug) " "
                                 (abf:fmt (cadddr sug)) " -> "
                                 (abf:fmt (nth 4 sug)) ".")))))))

         ;; -- put the drawing back the way it was
         (abf:drop temps)
         (setq temps nil)
         (if (and odim (not (equal odim (getvar "DIMSTYLE"))))
           (abf:setstyle odim))
         (setvar "CLAYER"  ocl)
         (setvar "OSMODE"  oos)
         (setvar "CMDECHO" oce)
         (command "_.UNDO" "_End")
         (setq undo-open nil)

         (princ (strcat "\n" cmd ": " (itoa made) " point"
                        (if (= made 1) "" "s") " tied to "
                        abf:*a-name* " and " abf:*b-name*
                        " on layer " abf:*layer*
                        (if havestyle
                          (strcat " in style " abf:*style* ".")
                          " (current style).")))
         (if (> moves 0)
           (princ (strcat "\n" cmd ": " (itoa moves) " point"
                          (if (= moves 1) "" "s") " moved - ringed on "
                          abf:*ring-layer* " where "
                          (if (= moves 1) "it" "they") " came off.")))))))
  (princ))

;;; ---------------------- commands --------------------------------------

(defun c:ABFIND ()
  (abf:run nil))

(defun c:ABMOVE ()
  (abf:run T))

(defun c:ABFINDVER ()
  (princ (strcat "\nABFIND " *abfind-version*
                 "  (commands: ABFIND, ABMOVE)"))
  (princ))

(princ (strcat "\nABFIND " *abfind-version*
               " loaded.  Commands: ABFIND (dim Pt.## from the "
               abf:*a-name* " and " abf:*b-name*
               " stakes), ABMOVE (the same, and move it to where a"
               " misread tape would put it)."))
(princ)
