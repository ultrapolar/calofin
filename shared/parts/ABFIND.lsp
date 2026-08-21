;;; ======================================================================
;;; ABFIND.lsp  --  tie a survey point back to the A and B stakes
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP; needs the Visual LISP
;;; engine that ships with full AutoCAD -- LT cannot run this).
;;;
;;; Commands:  ABFIND      dimension Pt.## from A and from B, point
;;;                        after point until Enter - and offer to move
;;;                        each one before it asks for the next
;;;            ABMOVE      ONE point: the same two ties, and then every
;;;                        place it could sit if one of the two tapes
;;;                        was written down wrong; pick one, it moves,
;;;                        and the command is done
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
;;;   ABFIND asks this itself, once its two ties are drawn:
;;;
;;;       Move Pt.17 to a different reading? [Yes/No] <No>:
;;;
;;;   Yes runs everything below, and when the point is settled ABFIND
;;;   asks for the next number as usual.  ABMOVE is the same flow
;;;   without the question -- it was typed to move a point, so it goes
;;;   straight to the readings and ends when that point is settled.
;;;
;;;   Either way: if this point is in the wrong place, where SHOULD it
;;;   be?  One tape
;;;   is held exactly as it is and the other's reading is varied, and
;;;   each pair of distances is crossed back to a position.  Two
;;;   families of reading are tried:
;;;
;;;     * THE FOOT SWEEP -- the moved tape a whole foot out, a foot at
;;;       a time, abf:*foot-steps* of them EACH WAY (10 up and 10 down
;;;       as shipped).  A foot is the unit a tape gets miscounted in,
;;;       so every foot within reach is worth seeing whether or not
;;;       the number looks like another one.
;;;     * THE LOOK-ALIKES -- a reading that could be read as this one:
;;;         the inches lost or gained a leading 1     1"  <->  11"
;;;         a digit read as its look-alike            21'-1" -> 21'-7"
;;;           (abf:*digit-pairs*: 1/7, 1/4, 3/8, 3/5, 5/6, 6/8, 0/9,
;;;           4/9, 7/9), in the inches or in the feet
;;;         two feet digits changed places            21' -> 12'
;;;
;;;   Both ways round, as two groups: the readings that move A (B
;;;   held), then the ones that move B.  Nothing further than
;;;   abf:*max-shift* (10 feet, the reach of the foot sweep) is
;;;   offered, and a reading the held tape can no longer reach has no
;;;   crossing and is left out.  A look-alike that lands on a whole
;;;   foot is already in the sweep and is not listed twice.
;;;
;;;   Every suggestion carries a TAG, which is both its label on screen
;;;   and the answer you type: the moved tape's letter after the number
;;;   of feet it moved -- 1A, 2A, -1A, -2A for the sweep on A, 1B, -1B
;;;   for the sweep on B -- or R1A, R2A for a look-alike reading of A
;;;   that is not a whole foot out, in the same nearest-first order.
;;;   The candidates are drawn on the POINTS layer in abf:*sug-color*
;;;   (yellow), so they never read as the drawing's own points, and
;;;   listed on the command line nearest miss first within each group.
;;;   Type a tag, or Pick and click the marker you want.
;;;
;;;   Each group also gets the line it sits on, dashed and grey: a
;;;   held tape is a fixed radius off its stake, so everything that
;;;   holds it lies on one arc centred there - through the point as it
;;;   is drawn now, and out to the furthest suggestion each way.  Two
;;;   arcs, then: one through all the A readings and one through all
;;;   the B readings, crossing at the point itself.  They are
;;;   scaffolding like the markers and go when the round does.
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
;;;   For ABMOVE that is the end of the run: it settles ONE point and
;;;   stops -- run it again for the next one.  ABFIND carries on to the
;;;   next point number, and the point it has just made is a point like
;;;   any other from there: it can be named in a later round of the
;;;   same run.
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
;;; README).  In ABFIND, B/BACK/U/UNDO typed at the point number undoes
;;; the whole of the last round -- its ties, and, if that round moved a
;;; point, the moved point, its ring and its note, with the original
;;; ties put back.  Back at "Move Pt.17?" un-draws that point's ties
;;; and re-asks the number; Back at the suggestions re-asks "Move
;;; Pt.17?"; Back at the note re-asks the suggestion.  ABMOVE is the
;;; same minus its own question: Back at the suggestions re-asks the
;;; point number, its first question has nothing to go back to, and
;;; once the point is settled the run is over.  A single U undoes a
;;; whole run either way -- it is one undo group.
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
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.

(vl-load-com)

;;; ---------------------- configuration ---------------------------------

(setq *abfind-version* "v1.5")      ; announced on load; release_lisp.py
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
(setq abf:*sug-color*    2)         ; colour the suggestions are drawn
                                    ; in, as an entity override: yellow,
                                    ; so a suggestion never reads as one
                                    ; of the drawing's own POINTS
(setq abf:*sug-hgt*      6.0)       ; height of a suggestion's tag
(setq abf:*locus-color*  8)         ; colour of the guide line each
                                    ; group of suggestions sits on:
                                    ; grey, so it reads as a guide and
                                    ; not as drawn work
(setq abf:*locus-ltype*  "DASHED")  ; and its linetype - created at
                                    ; pool scale when the drawing has
                                    ; no linetype by that name
(setq abf:*foot-steps*   10)        ; how many 1-foot steps are offered
                                    ; each way when a tape is swept: 10
                                    ; up and 10 down, per held stake
(setq abf:*max-shift*    120.0)     ; furthest a suggestion may sit from
                                    ; the reading, in inches.  It bounds
                                    ; BOTH families, so the shipped 10
                                    ; feet is exactly the reach of the
                                    ; foot sweep; lower it and the sweep
                                    ; shortens with the look-alikes
(setq abf:*max-sugg*     nil)       ; most suggestions per held stake,
                                    ; nil = as many as there are
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

;;; ---------------------- layers ----------------------------------------

;; Make a layer current, creating it first when the drawing lacks it.
(defun abf:setlayer (name)
  (cal:ensure-layer name 7)
  (setvar "CLAYER" name))

;;; ---------------------- point lookup ----------------------------------

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
            (setq nm (cal:block-number en abf:*pt-tag*))
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
    (setq d (cal:dist pk (car c)))
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

;; The 8-point compass name for ANG (0 = east), reading the drawing the
;; way it is plotted: plan north is +Y.
(defun abf:compass (ang / i)
  (setq i (rem (fix (+ 0.5 (/ (cal:angnorm ang) (/ pi 4.0)))) 8))
  (nth i '("E" "NE" "N" "NW" "W" "SW" "S" "SE")))

;; Where circle (ca ra) meets circle (cb rb), as a 3-D point.  The two
;; circles meet twice, mirrored across the A-B line; a misread tape
;; never flips a point to the far side of the stakes, so the crossing
;; nearer NEAR - the point as it is drawn now - is the one meant.  nil
;; when the two circles never reach each other at all.
(defun abf:circint (ca ra cb rb near / d ux uy m h2 h bx by p1 p2)
  (setq d (cal:dist ca cb))
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
          (if (< (cal:dist p1 near) (cal:dist p2 near)) p1 p2))))))

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

;; V inserted into the already-sorted LST, smallest miss first.  A tie
;; goes up before down, so the sweep always reads 1, -1, 2, -2 ... and
;; never flips a pair round because a look-alike happened to land on
;; that foot first.
(defun abf:ins-delta (v lst)
  (cond ((null lst) (list v))
        ((< (abs v) (abs (car lst))) (cons v lst))
        ((and (equal (abs v) (abs (car lst)) 1e-9) (> v 0.0))
         (cons v lst))
        (t (cons (car lst) (abf:ins-delta v (cdr lst))))))

;; Every reading D could have been instead, as a signed shift in
;; inches.  Two families:
;;
;;   * THE FOOT SWEEP - the tape read a whole number of feet out, one
;;     foot at a time, abf:*foot-steps* of them each way.  It does not
;;     care whether the number looks like another one: a foot is the
;;     unit a tape gets miscounted in, so every foot within reach is
;;     worth seeing.
;;   * THE LOOK-ALIKES - the reading was written down as a number that
;;     resembles it: the inches losing or gaining a leading 1
;;     (1" <-> 11"), a digit read as its look-alike in the inches or
;;     in the feet (abf:*digit-pairs*), and two feet digits changing
;;     places (21' -> 12').
;;
;; Only shifts up to abf:*max-shift* survive - it bounds both families
;; - and a reading that would come out at or below zero is dropped.
;; Nearest miss first, no repeats: a look-alike that lands on a whole
;; foot is already in the sweep and is not listed twice.
(defun abf:deltas (d / r ft inch raw out v k)
  (setq r    (abf:reading d)
        ft   (car  r)
        inch (cadr r)
        raw  nil
        k    1)
  (repeat abf:*foot-steps*                       ; the foot sweep
    (setq raw (cons (* 12.0 k) (cons (* -12.0 k) raw))
          k   (1+ k)))
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
  (setq hit (< (cal:dist p pp) abf:*same-eps*))
  (foreach c lst
    (if (< (cal:dist p (nth 5 c)) abf:*same-eps*) (setq hit T)))
  hit)

;; One group of candidates: one stake's reading is HELD exactly as it
;; is and the other's is walked through abf:deltas.  movea non-nil
;; varies A's reading and holds B's; nil is the other way round.  Each
;; entry is (miss held moved old-reading new-reading point tag),
;; smallest miss first, capped at abf:*max-sugg* (nil = uncapped).  A
;; reading the held tape can no longer reach has no crossing and is
;; left out.
(defun abf:group (pa a pb b pp held moved movea
                  / was out dl nd np n cut one k tag reads)
  (setq was   (if movea a b)
        out   nil
        reads 0)
  (foreach dl (abf:deltas was)
    (setq nd (+ was dl)
          np (if movea
               (abf:circint pa nd pb b pp)
               (abf:circint pa a pb nd pp)))
    (if (and np (not (abf:seen-p np pp out)))
      (progn
        ;; the tag is the answer the user types, so it says what the
        ;; suggestion IS: the moved tape's letter, after either the
        ;; number of feet it moved (2B, -3B) or, for a reading that is
        ;; not a whole foot, its place in this tape's look-alikes
        ;; (R1B).  Numbering only what is actually offered keeps the
        ;; R numbers unbroken when a reading is out of reach.
        (setq k (/ dl 12.0))
        (if (equal k (float (fix k)) 1e-9)
          (setq tag (strcat (itoa (fix k)) moved))
          (setq reads (1+ reads)
                tag   (strcat "R" (itoa reads) moved)))
        (setq out (abf:ins-cand
                    (list (abs dl) held moved was nd np tag) out)))))
  (if (and abf:*max-sugg* (> (length out) abf:*max-sugg*))
    (progn
      (setq cut nil n 0)
      (foreach one out
        (if (< n abf:*max-sugg*) (setq cut (cons one cut)))
        (setq n (1+ n)))
      (setq out (reverse cut))))
  out)

;; Every place PP could sit if ONE of its two tapes was read wrong, in
;; the two groups that answer separately: the ones that move A (B held)
;; first, so their tags run 1A, -1A, R1A ..., then the ones that move
;; B.  A candidate can never appear in both - a B-held one keeps its
;; distance from B exactly and an A-held one does not - so the groups
;; are simply run together, each nearest miss first.
(defun abf:candidates (pa pb pp / a b)
  (setq a (cal:dist pa pp)
        b (cal:dist pb pp))
  (if (and (> a abf:*fuzz*) (> b abf:*fuzz*))
    (append (abf:group pa a pb b pp abf:*b-name* abf:*a-name* T)
            (abf:group pa a pb b pp abf:*a-name* abf:*b-name* nil))))

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
  (if (> (cal:dist p1 p2) abf:*fuzz*)
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
;; so it can be seen and clicked, and its tag beside it.  On the points
;; layer, but in abf:*sug-color* rather than ByLayer - a suggestion is
;; not one of the drawing's own points and must not read as one - and
;; all of it swept again as soon as the round ends.
(defun abf:draw-sug (p tag / out)
  (setq out nil)
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 (cons 8 abf:*point-layer*)
                 (cons 62 abf:*sug-color*) '(100 . "AcDbPoint")
                 (list 10 (car p) (cadr p) 0.0)))
  (setq out (cons (entlast) out))
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 (cons 8 abf:*point-layer*)
                 (cons 62 abf:*sug-color*) '(100 . "AcDbCircle")
                 (list 10 (car p) (cadr p) 0.0)
                 (cons 40 abf:*sug-radius*)))
  (setq out (cons (entlast) out))
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 (cons 8 abf:*point-layer*)
                 (cons 62 abf:*sug-color*) '(100 . "AcDbText")
                 (list 10 (+ (car  p) abf:*sug-radius*)
                          (+ (cadr p) abf:*sug-radius*) 0.0)
                 (cons 40 abf:*sug-hgt*) (cons 1 tag)))
  (setq out (cons (entlast) out))
  (reverse out))

;; Make sure the guide line's linetype exists, with dashes sized for a
;; drawing in inches so they read at pool scale.  Pure entmake, no
;; command calls.  (pf:ensure-dashed, abhd.lsp:1566.)  A drawing that
;; already has a linetype by that name keeps its own.
(defun abf:ensure-dashed ()
  (if (not (tblsearch "LTYPE" abf:*locus-ltype*))
    (entmake (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLinetypeTableRecord")
                   (cons 2 abf:*locus-ltype*) '(70 . 0)
                   '(3 . "Dashed __ __ __ __ __")
                   '(72 . 65) '(73 . 2) '(40 . 18.0)
                   '(49 . 12.0) '(74 . 0)
                   '(49 . -6.0) '(74 . 0)))))

;; The guide line one group of suggestions lies on.  Every candidate
;; that HELD the same tape sits at exactly that tape's reading off its
;; stake - and so does the point as it is drawn now - so the whole
;; group is on one circle centred there.  The arc runs from the
;; furthest candidate one way round to the furthest the other, through
;; the point itself: a dashed grey line through all of them.  Returns
;; what it made, in a list, or nil when the group is empty.
(defun abf:draw-locus (ctr rad pp sugs held / a0 lo hi c d)
  (setq a0 (angle (cal:2d ctr) (cal:2d pp))
        lo 0.0
        hi 0.0)
  (foreach c sugs
    (if (= (cadr c) held)
      (progn
        (setq d (cal:signed-dang
                  a0 (angle (cal:2d ctr) (cal:2d (nth 5 c)))))
        (if (< d lo) (setq lo d))
        (if (> d hi) (setq hi d)))))
  (if (> (- hi lo) abf:*fuzz*)
    (progn
      (abf:ensure-dashed)
      (entmake (list '(0 . "ARC") '(100 . "AcDbEntity")
                     (cons 8 abf:*point-layer*)
                     (cons 62 abf:*locus-color*)
                     (cons 6 abf:*locus-ltype*)
                     '(100 . "AcDbCircle")
                     (list 10 (car ctr) (cadr ctr) 0.0)
                     (cons 40 rad)
                     '(100 . "AcDbArc")
                     (cons 50 (+ a0 lo)) (cons 51 (+ a0 hi))))
      (list (entlast)))))

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
;;; The two differ in shape as well as in questions.  ABFIND rinses and
;;; repeats, so it keeps a history and Back takes the last round away
;;; again, whatever that round did:
;;;
;;;     ("DIM"  pair)
;;;     ("MOVE" old-pair new-pair moved-point-ents ring note)
;;;
;;; ABMOVE does ONE point - it was typed to move one - and ends as soon
;;; as that point is settled, so it keeps no history.  A single U
;;; undoes the whole run either way.

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
                        pair sugs temps c kws shown ans sug havestyle
                        np newpt tried lasthold ments ring note npair)

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
        ((< (cal:dist pa pb) abf:*fuzz*)
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

         ;; -- the round loop.  A round is one point:
         ;;      1  which point       -- its two ties are drawn
         ;;      2  move it?          -- ABFIND only: it measures, so
         ;;                              it asks before going looking.
         ;;                              ABMOVE was typed to move a
         ;;                              point and goes straight on
         ;;      3  work out where it could go, and show it (no
         ;;         question of its own)
         ;;      4  which suggestion
         ;;      5  where the note goes, and then the move itself
         ;;    Each question backs out into the one before it.  ABFIND
         ;;    goes round again after every round, moved or not;
         ;;    ABMOVE settles its one point and ends.
         (setq hist nil stage 1 done nil made 0 moves 0 temps nil)
         (while (not done)
           (cond

             ;; -- 1: which point
             ((= stage 1)
              (setq s (getstring
                        (if movep
                          "\nPoint number (Enter to cancel): "
                          (strcat "\nPoint number"
                                  (if hist " [Back]" "")
                                  " <Enter = done>: "))))
              (cond
                ((= s "") (setq done T))
                ((cal:back-word-p s)
                 (if hist
                   (progn
                     (abf:undo-round (car hist))
                     ;; a MOVE round put exactly one point into the
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
                ((or (< (cal:dist (car hit) pa) abf:*fuzz*)
                     (< (cal:dist (car hit) pb) abf:*fuzz*))
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
                     (setq made  (1+ made)
                           stage (if movep 3 2))
                     (princ (strcat "\n  Pt." nm ":  " abf:*a-name* " "
                                    (abf:fmt (cal:dist pa pp)) "   "
                                    abf:*b-name* " "
                                    (abf:fmt (cal:dist pb pp))
                                    "  dimensioned.")))))))

             ;; -- 2: does this one want moving?  (ABFIND only)
             ((= stage 2)
              (setq ans (cal:askyn (strcat "  Move Pt." nm
                                           " to a different reading?")
                                   "No" T))
              (cond
                ((eq ans 'CAL-BACK)
                 (abf:drop pair)
                 (setq made  (1- made)
                       stage 1)
                 (princ "\nStepping back one point."))
                (ans (setq stage 3))
                (t (setq hist  (cons (list "DIM" pair) hist)
                         stage 1))))

             ;; -- 3: where else could this point be?  Nothing is asked
             ;;       here - the readings are worked out and drawn, and
             ;;       the next stage is the one that asks.
             ((= stage 3)
              (setq sugs  (abf:candidates pa pb pp)
                    temps nil)
              (if (null sugs)
                (progn
                  (princ (strcat "\n  No reading within "
                                 (abf:fmt abf:*max-shift*)
                                 " puts Pt." nm " anywhere the other"
                                 " tape can reach - left where it is."))
                  (if movep
                    (setq done T)
                    (setq hist  (cons (list "DIM" pair) hist)
                          stage 1)))
                (progn
                  (cal:ensure-layer abf:*point-layer* 2)
                  (foreach c sugs
                    (setq temps (append temps
                                        (abf:draw-sug (nth 5 c)
                                                      (nth 6 c)))))
                  ;; and the line each group sits on, in the order the
                  ;; table lists them
                  (setq temps (append temps
                                      (abf:draw-locus
                                        pb (cal:dist pb pp) pp sugs
                                        abf:*b-name*)
                                      (abf:draw-locus
                                        pa (cal:dist pa pp) pp sugs
                                        abf:*a-name*)))
                  (setq tried (+ (length (abf:deltas (cal:dist pa pp)))
                                 (length (abf:deltas (cal:dist pb pp)))))
                  (princ (strcat "\n\n  Where Pt." nm
                                 " lands if one tape was read wrong -"
                                 " the ones that move " abf:*a-name*
                                 " first, then " abf:*b-name*
                                 " (nearest miss first):"))
                  (if (> tried (length sugs))
                    (princ (strcat "\n  "
                                   (itoa (- tried (length sugs)))
                                   " of the " (itoa tried)
                                   " readings are not offered: out of"
                                   " the other tape's reach"
                                   (if abf:*max-sugg*
                                     ", or past the list cap" "")
                                   ".")))
                  (princ (strcat "\n   tag   held  moved  from"
                                 "          to            the point"
                                 " moves"))
                  (princ (strcat "\n   ----  ----  -----  ---------"
                                 "--   -----------   -------------"
                                 "--"))
                  (setq lasthold nil)
                  (foreach c sugs
                    ;; a blank line where the held stake changes: the
                    ;; two answers read as two blocks, not one long
                    ;; list
                    (if (and lasthold (/= lasthold (cadr c)))
                      (princ "\n"))
                    (setq lasthold (cadr c))
                    (princ (strcat "\n   " (cal:pad (nth 6 c) 6)
                                   (cal:pad (cadr c) 6)
                                   (cal:pad (caddr c) 7)
                                   (cal:pad (abf:fmt (cadddr c)) 14)
                                   (cal:pad (abf:fmt (nth 4 c)) 14)
                                   (abf:fmt (cal:dist pp (nth 5 c)))
                                   " "
                                   (abf:compass
                                     (angle (cal:2d pp)
                                            (cal:2d (nth 5 c)))))))
                  (setq stage 4))))

             ;; -- 4: which suggestion
             ((= stage 4)
              ;; every tag is a keyword, so any of them can be typed -
              ;; but a bracket listing forty-odd of them is unreadable,
              ;; so the bracket shows only the words that are not in
              ;; the table.  Everything it DOES show is a keyword, so
              ;; nothing shown fails when it is clicked.
              (setq kws "")
              (foreach c sugs (setq kws (strcat kws (nth 6 c) " ")))
              (setq kws   (strcat kws "Pick None")
                    shown "Pick/None"
                    ans   (cal:askkw
                            (strcat "  Move Pt." nm
                                    " - type a tag from the table")
                            kws shown "None" T))
              (cond
                ((eq ans 'CAL-BACK)
                 (abf:drop temps)
                 (setq temps nil)
                 ;; ABFIND came here from its own question, so Back
                 ;; re-asks that; ABMOVE came straight from the point
                 ;; number, so Back re-asks that instead
                 (if movep
                   (progn
                     (abf:drop pair)
                     (setq made  (1- made)
                           stage 1)
                     (princ "\nStepping back one point."))
                   (setq stage 2)))
                ((= ans "None")
                 (abf:drop temps)
                 (setq temps nil)
                 (princ (strcat "\n  Pt." nm " left where it is."))
                 (if movep
                   (setq done T)
                   (setq hist  (cons (list "DIM" pair) hist)
                         stage 1)))
                ((= ans "Pick")
                 (initget "Back Undo")
                 (setq np (getpoint "\n  Click the one you want [Back]: "))
                 (cond
                   ((null np)
                    (princ "\n  Nothing clicked - pick from the list."))
                   ((member np '("Back" "Undo"))
                    (princ "\n  Back to the list."))
                   (t
                    (setq sug nil)
                    (foreach c sugs
                      (if (and (null sug)
                               (<= (cal:dist np (nth 5 c)) abf:*snap*))
                        (setq sug c)))
                    (if sug
                      (setq stage 5)
                      (princ (strcat "\n  No suggestion within "
                                     (rtos abf:*snap* 4 0)
                                     " of that click - try again."))))))
                (t
                 ;; initget refuses anything that is not one of the
                 ;; tags, so the lookup cannot miss - the guard is
                 ;; there so a future keyword cannot walk off the list
                 (setq sug nil)
                 (foreach c sugs
                   (if (and (null sug) (= (nth 6 c) ans)) (setq sug c)))
                 (if sug
                   (setq stage 5)
                   (princ (strcat "\n  \"" ans "\" is not one of the"
                                  " tags - nothing moved."))))))

             ;; -- 5: where the note goes, and then the move itself
             (t
              (princ "\n  Auto tucks the note beside the ring.")
              (initget "Auto Back Undo")
              (setq np (getpoint (strcat "\n  Place the note for Pt." nm
                                         " [Auto/Back] <Auto>: ")))
              (if (and np (member np '("Back" "Undo")))
                (setq stage 4)
                (progn
                  ;; nil is Enter and a string is the Auto keyword;
                  ;; only a real list is a spot the user clicked
                  (if (or (null np) (not (listp np)))
                    (setq np (abf:note-spot pp)))
                  ;; the suggestions have done their job
                  (abf:drop temps)
                  (setq temps nil
                        newpt (nth 5 sug)
                        ments (abf:make-point
                                newpt (strcat nm abf:*moved-suffix*)))
                  (cal:ensure-layer abf:*ring-layer* 1)
                  (setq ring (abf:ring pp)
                        note (abf:note np
                               (strcat "Moved Pt." nm " " (caddr sug)
                                       " from " (abf:fmt (cadddr sug))
                                       " to "   (abf:fmt (nth 4 sug)))))
                  ;; the ties belong to where the point is now; the old
                  ;; reading is not lost - the note carries it
                  (abf:drop pair)
                  (setq npair (abf:dim-pair pa pb newpt havestyle)
                        moves (1+ moves))
                  (if movep
                    ;; that point is settled, and settling one is all
                    ;; ABMOVE is for
                    (setq done T)
                    ;; ABFIND carries on, and the point it just made is
                    ;; a point like any other from here
                    (setq hist  (cons (list "MOVE" pair npair ments
                                            ring note)
                                      hist)
                          cands (cons (cons newpt
                                            (strcat nm
                                                    abf:*moved-suffix*))
                                      cands)
                          stage 1))
                  (princ (strcat "\n  Pt." nm " moved to Pt." nm
                                 abf:*moved-suffix* " - " (cadr sug)
                                 " held at "
                                 (abf:fmt (cal:dist
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

         (if (= made 0)
           (princ (strcat "\n" cmd ": nothing dimensioned."))
           (princ (strcat "\n" cmd ": " (itoa made) " point"
                          (if (= made 1) "" "s") " tied to "
                          abf:*a-name* " and " abf:*b-name*
                          " on layer " abf:*layer*
                          (if havestyle
                            (strcat " in style " abf:*style* ".")
                            " (current style)."))))
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
