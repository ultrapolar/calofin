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
;;;   Name a point -- type its number, or click the point itself: the
;;;   one prompt takes either.  Two aligned dimensions are drawn, A to
;;;   the point and B to the point -- the pair of readings the point was
;;;   plotted from -- in the "CROSS DIMENSIONS" dimension style, on the
;;;   "DIMENSION" layer, ByLayer, the dimension line sitting right on
;;;   the tie, exactly the convention CDCALLOUT and CDCREATE use.  It
;;;   keeps asking for the next point until you press Enter.  The
;;;   stakes are found by name.
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
;;;   The candidates are drawn on abf:*sug-layer* ("ABMOVE-POINTS") in
;;;   abf:*sug-color* (yellow) -- a layer of their OWN, never the
;;;   points layer.  They are throwaway, they would inherit the points
;;;   layer's colour, and while they existed every other tool in the
;;;   toolset would count them as real survey points.  They are listed
;;;   on the command line nearest miss first within each group.  The
;;;   ONE that is chosen is a survey point, and that is what goes on
;;;   POINTS.
;;;
;;;   The tags do not sit beside their markers.  The look-alike
;;;   readings land an inch or three apart, and a 6" tag beside each
;;;   piled half a dozen of them onto one spot, unreadable - which is
;;;   what made the right one so hard to pick.  So each tag hangs OFF
;;;   its arc on a short leader, in a row abf:*tag-standoff* out from
;;;   the arc, with abf:*tag-gap* of daylight to the next tag.  The
;;;   two arcs cross at the point and cut the sheet into four empty
;;;   quarters (every marker is ON an arc), and each half of each
;;;   group takes a quarter of its own, its tags run down the
;;;   quarter's bisector so they draw away from both arcs at once - no
;;;   tag lands on the other group's markers, however sharp the
;;;   crossing.
;;;
;;;   Choosing one is ONE prompt: click the marker or the tag you want,
;;;   type its tag from the table, or Enter for None.  A click takes
;;;   the NEAREST marker or tag - a tag is as good a target as its
;;;   marker, and the easier one when the markers crowd.  When two or
;;;   more sit closer together than the pickbox spans at the current
;;;   zoom, the click cannot tell them apart and the routine says so:
;;;   it lists the ones under the click and asks which, the nearest
;;;   being the Enter answer.  Zoom in and the same click is exact.
;;;   Whatever was taken is read back with the reading it stands for
;;;   before the note is placed.
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
;;;     * the point is COPIED to there and numbered "17m" -- the
;;;       original number with abf:*moved-suffix* on it, so the drawing
;;;       says plainly that this one was moved.  A COPY: the same
;;;       block, the same layer, colour, linetype, lineweight, scale
;;;       and rotation, and every attribute it carries, each keeping
;;;       the offset it had -- only the number is different.  A survey
;;;       point is more than a position, and the moved one is the SAME
;;;       point one reading further on, so it has to read as one:
;;;       building a fresh point from this file's defaults threw the
;;;       drawing's own away.  Only a drawing whose point block is not
;;;       in its block table has nothing to copy, and that one falls
;;;       back to a POINT on the points layer with a text label beside
;;;       it,
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
;;; NAMING THE POINT.  Type its number the way it reads in the drawing
;;; -- "35", "Pt.35", "pt 35", "#35" and "035" all name the same point
;;; -- or click the point on screen: the one prompt takes both, because
;;; (initget 128) hands typed text back from getpoint as the string it
;;; is while a click comes back as the point it is.  A click is snapped
;;; to the survey point within abf:*snap* of it, so it names a point
;;; exactly as a typed number does.  A number that names nothing, and a
;;; click with no survey point under it, are both reported and the
;;; prompt re-asks -- nothing is drawn from a typo or a stray click.
;;;
;;; Going back a step follows the shared Back convention (see the root
;;; README).  In ABFIND, B/BACK/U/UNDO typed at the point number undoes
;;; the whole of the last round -- its ties, and, if that round moved a
;;; point, the moved point, its ring and its note, with the original
;;; ties put back.  Back at "Move Pt.17?" un-draws that point's ties
;;; and re-asks the number; Back at the suggestions re-asks "Move
;;; Pt.17?"; Back at the note re-asks the suggestion; Back at "Which
;;; one?" (the tie a click could not settle) goes back to the markers.
;;; ABMOVE is the same minus its own question: Back at the suggestions
;;; re-asks the point number, its first question has nothing to go back
;;; to, and once the point is settled the run is over.  A single U
;;; undoes a whole run either way -- it is one undo group.
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

(setq *abfind-version* "v1.10")      ; announced on load; release_lisp.py
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
                                    ; points, and where the moved point
                                    ; lands once one is chosen
(setq abf:*point-color*  6)         ; colour to give that layer if the
                                    ; drawing somehow lacks it - the
                                    ; magenta the standard uses.  An
                                    ; existing POINTS keeps its own
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
(setq abf:*sug-layer*    "ABMOVE-POINTS") ; the suggestions get a layer
                                    ; of their OWN, never the points
                                    ; layer: they are throwaway, they
                                    ; would inherit the points layer's
                                    ; colour, and while they existed
                                    ; every other tool in the toolset
                                    ; would count them as real survey
                                    ; points.  Created when missing,
                                    ; and swept clear at the end of
                                    ; every round
(setq abf:*sug-color*    2)         ; colour of that layer, and an
                                    ; entity override to match: yellow,
                                    ; so a suggestion reads as a
                                    ; suggestion whatever the layer was
                                    ; set to by hand
(setq abf:*sug-hgt*      5.0)       ; height of a suggestion's tag -
                                    ; above the 4" point numbers, and
                                    ; still narrow enough for the tags
                                    ; to file past each other
(setq abf:*tag-standoff* 10.0)      ; how far off its arc the row of
                                    ; tags hangs, in inches - each tag
                                    ; on a leader from its marker
(setq abf:*tag-gap*      1.5)       ; the daylight kept between two
                                    ; tags, between a tag and the other
                                    ; arc's markers, in inches.  Along
                                    ; the arc the tags stand further
                                    ; apart than that, by the angle
                                    ; they make with it
(setq abf:*tag-width*    0.8)       ; a character's width as a fraction
                                    ; of the tag height - how long the
                                    ; strip a click on a tag can land
                                    ; on is taken to be
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
                                    ; (both as the ab_pt block has it).
                                    ; The FALLBACK's only: a point that
                                    ; is copied keeps the attribute the
                                    ; point it came from had, height,
                                    ; place and all
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

;; Yes/No.  dflt is "Yes" or "No" and is always shown; a change to the
;; drawing defaults "No".  Returns T, nil or ABF-BACK.
;; (cal:askyn, copied under this file's prefix.)
(defun abf:askyn (msg dflt back / v)
  (setq v (abf:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'ABF-BACK) v (= v "Yes")))

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

;; WHICH attribute of a point block carries its number, and what that
;; number is, as (index tag value): the abf:*pt-tag* one when the block
;; has it, otherwise the first whose value reads as a number (survey
;; exports do not all use the ab_pt tag).  nil when neither exists.
;; The index is what copying the point needs - it is the one attribute
;; of the copy whose value is not the original's.
(defun abf:number-att (en / sub ed hit fall v i)
  (setq sub (entnext en) hit nil fall nil i 0)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null hit) v
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase abf:*pt-tag*)))
      (setq hit (list i (cdr (assoc 2 ed)) v)))
    (if (and (null fall) v (distof v 2))
      (setq fall (list i (cdr (assoc 2 ed)) v)))
    (setq sub (entnext sub) i (1+ i)))
  (if hit hit fall))

;; The name carried by a point block: the value abf:number-att found.
;; (cal:block-number, copied under this file's prefix.)
(defun abf:block-number (en / a)
  (if (setq a (abf:number-att en)) (caddr a)))

;; What the routine knows about one survey point: where it is, what it
;; is called, and the ENTITY it is.  The entity is carried so that a
;; point which moves can be COPIED rather than re-invented from this
;; file's defaults - it is what makes the moved point the same point.
(defun abf:cd-pt (c) (car c))       ; (x y z)
(defun abf:cd-nm (c) (cadr c))      ; "17"
(defun abf:cd-en (c) (caddr c))     ; the INSERT it was read from

;; Every NAMED survey point in the drawing, as (position name entity).
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
              (setq out (cons (list (list (car p) (cadr p) 0.0) nm en)
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
    (if (and (null found) (= (abf:canon (abf:cd-nm c)) want))
      (setq found c)))
  found)

;; The survey point nearest to pick PK, when one sits within
;; abf:*snap* of it; nil otherwise.  Returns the ((x y z) . name) pair.
(defun abf:nearest (pk cands / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (abf:dist pk (abf:cd-pt c)))
    (if (and (<= d abf:*snap*) (or (null bd) (< d bd)))
      (setq best c bd d)))
  best)

;; Where a stake is: the point named NAME when the drawing names one,
;; otherwise a click (snapped to the nearest survey point when there is
;; one under it).  nil when the user presses Enter instead.
(defun abf:stake (name cands / hit pk)
  (if (setq hit (abf:find-point name cands))
    (progn
      (princ (strcat "\n  Stake " name " found at Pt."
                     (abf:cd-nm hit) "."))
      (abf:cd-pt hit))
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
              (princ (strcat "\n  Taken from Pt." (abf:cd-nm hit) "."))
              (abf:cd-pt hit))
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

;; Smallest signed angular difference (to - from), in (-pi, pi].
;; (cal:signed-dang, copied under this file's prefix.)
(defun abf:signed-dang (from to / d)
  (setq d (abf:angnorm (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

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

;; How far P is from the segment A-B - the nearest point of it, an end
;; included.  Locals are not named T: that is a constant in AutoLISP.
(defun abf:seg-dist (p a b / dx dy l2 u)
  (setq dx (- (car  b) (car  a))
        dy (- (cadr b) (cadr a))
        l2 (+ (* dx dx) (* dy dy)))
  (if (< l2 abf:*fuzz*)
    (abf:dist p a)
    (progn
      (setq u (/ (+ (* (- (car  p) (car  a)) dx)
                    (* (- (cadr p) (cadr a)) dy))
                 l2))
      (if (< u 0.0) (setq u 0.0))
      (if (> u 1.0) (setq u 1.0))
      (abf:dist p (list (+ (car a) (* u dx)) (+ (cadr a) (* u dy)))))))

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
  (setq hit (< (abf:dist p pp) abf:*same-eps*))
  (foreach c lst
    (if (< (abf:dist p (nth 5 c)) abf:*same-eps*) (setq hit T)))
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
  (setq a (abf:dist pa pp)
        b (abf:dist pb pp))
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

;; A survey point at P numbered NM, built from this file's defaults:
;; the drawing's own point block when it has one, a POINT with a text
;; label beside it when it does not.  Returns the entities it made.
;;
;; This is the FALLBACK.  A point that moves is copied from the point
;; it came from (abf:copy-point) so that it keeps that point's layer,
;; block, scale and attributes; only a drawing whose point block is not
;; in its block table has nothing to copy from and comes here.
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

;; An entget list ready to be entmade as a NEW entity: the codes that
;; name the entity it was read from, rather than describe it, are
;; dropped.  Everything else - layer, colour, linetype, lineweight,
;; block name, scale, rotation, extrusion, extended data - is what
;; makes the copy the same thing as the original, and stays.
(defun abf:cloneable (ed / out g)
  (foreach g ed
    (if (not (member (car g) '(-1 -2 5 102 330 331 340 360 361)))
      (setq out (cons g out))))
  (reverse out))

;; ED with CODE set to VAL: the entry it has replaced, or a new one on
;; the end when it has none.
(defun abf:put (ed code val / g)
  (if (setq g (assoc code ed))
    (subst (cons code val) g ed)
    (append ed (list (cons code val)))))

;; ED's point at CODE moved by (DX DY), when it has one.  An attribute
;; travels with the block it belongs to, keeping the offset it had.
(defun abf:shift (ed code dx dy / g)
  (if (setq g (assoc code ed))
    (abf:put ed code (list (+ (cadr g) dx) (+ (caddr g) dy)
                           (if (cdddr g) (cadddr g) 0.0)))
    ed))

;; A COPY of the survey point EN, standing at P and numbered NM.  The
;; same point in every other way: the same block, layer, colour,
;; linetype, lineweight, scale, rotation and extended data, and every
;; attribute it carries - same tag, same height, same style, each
;; keeping the offset it had from the point.  Only the attribute that
;; holds the number is written, and only with NM.
;;
;; A survey point carries more than a position: the layer the survey
;; put it on, a block scaled to the sheet, an elevation or a
;; description in a second attribute.  A moved point is that same point
;; one reading further on, so it is copied rather than rebuilt - a
;; rebuilt one silently dropped all of it.
;;
;; Returns the entities it made, or nil when EN is not a block
;; reference this drawing can insert again - the caller falls back to
;; abf:make-point then.
(defun abf:copy-point (en p nm / ed atts sub sd base dx dy lay numi
                                 out i)
  (setq ed (if en (entget en '("*"))))
  (if (and ed
           (= "INSERT" (cdr (assoc 0 ed)))
           (assoc 10 ed)
           (assoc 2 ed)
           (tblsearch "BLOCK" (cdr (assoc 2 ed))))
    (progn
      (setq base (cdr (assoc 10 ed))
            dx   (- (car  p) (car  base))
            dy   (- (cadr p) (cadr base))
            lay  (if (assoc 8 ed) (cdr (assoc 8 ed)) "0")
            numi (car (abf:number-att en))
            atts nil
            sub  (entnext en)
            i    0)
      ;; the attributes first, so the INSERT can be made knowing
      ;; whether it needs the (66 . 1) that says it has some
      (while (and sub
                  (setq sd (entget sub '("*")))
                  (= "ATTRIB" (cdr (assoc 0 sd))))
        (setq sd (abf:shift (abf:shift (abf:cloneable sd) 10 dx dy)
                            11 dx dy))
        (if (and numi (= i numi)) (setq sd (abf:put sd 1 nm)))
        (setq atts (cons sd atts)
              sub  (entnext sub)
              i    (1+ i)))
      (setq atts (reverse atts)
            ed   (abf:put (abf:cloneable ed) 10
                          (list (car p) (cadr p) 0.0))
            ed   (if atts (abf:put ed 66 1) (abf:strip 66 ed))
            out  nil)
      ;; the point goes back on its own layer, so that layer has to be
      ;; visible for the same reason every other output layer does
      (abf:ensure-layer lay abf:*point-color*)
      (if (entmake ed)                     ; nil when the copy is
        (progn                             ; refused - fall back then
          (setq out (list (entlast)))
          (foreach sd atts
            (if (entmake sd) (setq out (cons (entlast) out))))
          (if atts
            (if (entmake (list '(0 . "SEQEND") '(100 . "AcDbEntity")
                               (cons 8 lay)))
              (setq out (cons (entlast) out))))
          (reverse out))))))

;; E slid into the already-sorted LST by the size of its first element,
;; smallest first - the order the tags along a row are handed out in.
(defun abf:ins-by-abs (e lst)
  (cond ((null lst) (list e))
        ((< (abs (car e)) (abs (car (car lst)))) (cons e lst))
        (t (cons (car lst) (abf:ins-by-abs e (cdr lst))))))

;; The spot every suggestion's tag hangs at, as one (tag base ang width)
;; per suggestion: BASE is where its leader ends and its text starts,
;; ANG the direction the text runs from there, WIDTH how far it runs
;; (abf:*tag-width* of the height per character - an estimate, for
;; the click test; the text itself is as wide as its font makes it).
;;
;; The look-alike readings sit an inch or three apart, and a tag beside
;; each marker piled half a dozen tags onto one spot: the reason the
;; right one was so hard to pick.  So the tags hang OFF the arc, on a
;; row abf:*tag-standoff* out from it, tied to their markers by
;; leaders, and spaced along the row so that abf:*tag-gap* of daylight
;; stays between any two.  A tag is only ever pushed along the row
;; AWAY from the point, so the leaders never cross each other.
;;
;; Which side of the arc, and which way does the text run?  The two
;; arcs cross at the point and cut the sheet into four quarters, and
;; every marker sits ON an arc - so the quarters are empty, and each
;; half of each group hangs its tags in a quarter of its own.  The
;; readings that grew (1A, R1A) and the ones that shrank (-1A) lie
;; either side of the crossing: the group that holds B hangs its grown
;; readings outward from B and its shrunk ones inward, and the group
;; that holds A does it the other way about.  Four halves, four
;; quarters.  Within its quarter a tag runs along the quarter's
;; BISECTOR, not straight off its own arc: a quarter is as narrow as
;; the two ties' crossing angle, and text run straight off one arc
;; walks into the other where the crossing is sharp.  Run down the
;; middle it draws away from both arcs at once.  The narrower the
;; quarter, the flatter the tags lie to their arc and the further
;; apart along it they have to stand for the daylight to hold - and
;; the further the first one has to keep from the crossing, where the
;; other arc's nearest markers sit; both fall out of the angle.
(defun abf:tag-spots (pa pb pp sugs / out held ctr oth rad a0 a0o half
                                       lst c d e off nrm ray1 ray2 wedge
                                       bis across gap first prev slot ang
                                       base longest)
  (setq out nil longest 0.0)
  (foreach c sugs
    (setq longest (max longest (* (strlen (nth 6 c)) abf:*sug-hgt*
                                  abf:*tag-width*))))
  (foreach held (list abf:*b-name* abf:*a-name*)
    (setq ctr (if (= held abf:*a-name*) pa pb)
          oth (if (= held abf:*a-name*) pb pa)
          rad (abf:dist ctr pp)
          a0  (angle (abf:2d ctr) (abf:2d pp))
          a0o (angle (abf:2d oth) (abf:2d pp)))
    (foreach half '(1 -1)
      ;; this half of the group: the suggestions on one side of the
      ;; point along the arc, nearest the crossing first, each with
      ;; its signed angle off the point round the held stake
      (setq lst nil)
      (foreach c sugs
        (if (= (cadr c) held)
          (progn
            (setq d (abf:signed-dang
                      a0 (angle (abf:2d ctr) (abf:2d (nth 5 c)))))
            (if (= half (if (< d 0.0) -1 1))
              (setq lst (abf:ins-by-abs (cons d c) lst))))))
      (if lst
        (progn
          ;; the side of the arc, from whether this half's readings
          ;; grew or shrank - its nearest one says which
          (setq off (if (> (nth 4 (cdr (car lst)))
                           (cadddr (cdr (car lst))))
                      1 -1))
          (if (= held abf:*a-name*) (setq off (- off)))
          ;; the quarter: this arc's tangent the way this half runs,
          ;; and the other arc's tangent on the side the tags hang
          (setq nrm  (if (> off 0) a0 (+ a0 pi))
                ray1 (+ a0 (* half 0.5 pi))
                ray2 (if (> (cos (- (+ a0o (* 0.5 pi)) nrm)) 0.0)
                       (+ a0o (* 0.5 pi))
                       (- a0o (* 0.5 pi)))
                wedge (abs (abf:signed-dang ray1 ray2)))
          ;; a crossing so flat the two arcs all but lie together
          ;; would spread the tags to the horizon; treat it as 10
          ;; degrees, or 170, and let them touch
          (if (< wedge 0.1745) (setq wedge 0.1745))
          (if (> wedge 2.9671) (setq wedge 2.9671))
          ;; the tags turn with the arc, so two at the least spacing
          ;; lean together by the angle between them over their length
          ;; - the daylight is widened by what the longest tag loses
          (setq bis    (+ ray1 (* 0.5 (abf:signed-dang ray1 ray2)))
                across (+ abf:*sug-hgt* abf:*tag-gap*)
                gap    (/ (/ across (sin (* 0.5 wedge))) rad)
                gap    (/ (/ (+ across (* longest gap))
                             (sin (* 0.5 wedge)))
                          rad)
                first  (/ (max across
                               (/ (+ abf:*sug-radius* (* 0.5 abf:*sug-hgt*)
                                     abf:*tag-gap*
                                     (* abf:*tag-standoff* (cos wedge)))
                                  (sin wedge)))
                          rad)
                prev   nil)
          (foreach e lst
            (setq d    (car e)
                  c    (cdr e)
                  slot (max (abs d) (if prev (+ prev gap) first))
                  prev slot
                  ang  (+ a0 (* half slot))
                  base (polar (abf:2d ctr) ang
                              (+ rad (* off abf:*tag-standoff*)))
                  out  (cons (list (nth 6 c)
                                   (list (car base) (cadr base) 0.0)
                                   (abf:angnorm (+ bis (* half slot)))
                                   (* (strlen (nth 6 c)) abf:*sug-hgt*
                                      abf:*tag-width*))
                             out)))))))
  out)

;; One suggestion on screen: a point where it would sit, a small circle
;; so it can be seen and clicked, and its tag hung off the arc at SPOT
;; (abf:tag-spots) on a leader from the marker.  On abf:*sug-layer*,
;; never the points layer - a suggestion is not one of the drawing's
;; own points and must not read as one, to the eye or to the next tool
;; - in abf:*sug-color*, and all of it swept again as soon as the round
;; ends.  A tag whose direction would read upside down is turned round
;; and right-justified on its base, so it still runs away from the
;; leader and never across its neighbours.
(defun abf:draw-sug (p tag spot / out base ang flip)
  (setq out  nil
        base (cadr  spot)
        ang  (caddr spot)
        flip (and (> ang (* 0.5 pi)) (<= ang (* 1.5 pi))))
  (entmake (list '(0 . "POINT") '(100 . "AcDbEntity")
                 (cons 8 abf:*sug-layer*)
                 (cons 62 abf:*sug-color*) '(100 . "AcDbPoint")
                 (list 10 (car p) (cadr p) 0.0)))
  (setq out (cons (entlast) out))
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 (cons 8 abf:*sug-layer*)
                 (cons 62 abf:*sug-color*) '(100 . "AcDbCircle")
                 (list 10 (car p) (cadr p) 0.0)
                 (cons 40 abf:*sug-radius*)))
  (setq out (cons (entlast) out))
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 (cons 8 abf:*sug-layer*)
                 (cons 62 abf:*sug-color*) '(100 . "AcDbLine")
                 (list 10 (car p) (cadr p) 0.0)
                 (list 11 (car base) (cadr base) 0.0)))
  (setq out (cons (entlast) out))
  (entmake (append
             (list '(0 . "TEXT") '(100 . "AcDbEntity")
                   (cons 8 abf:*sug-layer*)
                   (cons 62 abf:*sug-color*) '(100 . "AcDbText")
                   (list 10 (car base) (cadr base) 0.0)
                   (cons 40 abf:*sug-hgt*) (cons 1 tag)
                   (cons 50 (if flip (abf:angnorm (+ ang pi)) ang)))
             (if flip
               (list '(72 . 2) (list 11 (car base) (cadr base) 0.0)))))
  (setq out (cons (entlast) out))
  (reverse out))

;; The pickbox, in drawing units at the current zoom: PICKBOX is a
;; count of pixels, and VIEWSIZE over the height of SCREENSIZE is the
;; drawing units one pixel spans.  Two markers closer together than
;; this are one place to a click at this zoom, so the routine asks
;; which was meant instead of guessing; zoom in and they come apart.
;; A session that cannot say (no screen to read) gets abf:*same-eps*,
;; so only a dead heat asks.
(defun abf:aperture (/ px vs ss)
  (setq px (getvar "PICKBOX")
        vs (getvar "VIEWSIZE")
        ss (getvar "SCREENSIZE"))
  (if (and (numberp px) (numberp vs) (> vs 0.0)
           (listp ss) (numberp (cadr ss)) (> (cadr ss) 0.0))
    (max abf:*same-eps* (* px (/ vs (cadr ss))))
    abf:*same-eps*))

;; What a click means: the suggestions under it, nearest first, each
;; as (distance . suggestion).  A suggestion is under a click that
;; lands within abf:*snap* of its marker, or on its tag - within the
;; pickbox of the strip the text runs along - and its distance is to
;; whichever of the two is the closer, so a click on a tag beats a
;; marker that merely happens to be near.  Only the ties come back:
;; the nearest, and whatever the click cannot tell from it at this
;; zoom (within the pickbox of its distance).  One entry, then, for a
;; clean click; several when it needs asking about; none for a miss.
(defun abf:under-click (pk sugs spots / ap hits c sp dm dt d best h out)
  (setq ap   (abf:aperture)
        hits nil)
  (foreach c sugs
    (setq sp (assoc (nth 6 c) spots)
          dm (abf:dist pk (nth 5 c))
          d  nil)
    (if (<= dm abf:*snap*) (setq d dm))
    (if sp
      (progn
        (setq dt (max 0.0
                      (- (abf:seg-dist pk (cadr sp)
                                       (polar (abf:2d (cadr sp))
                                              (caddr sp) (cadddr sp)))
                         (* 0.5 abf:*sug-hgt*))))
        (if (and (<= dt ap) (or (null d) (< dt d))) (setq d dt))))
    (if d (setq hits (abf:ins-cand (cons d c) hits))))
  (setq out nil)
  (if hits
    (progn
      (setq best (car (car hits)))
      (foreach h hits
        (if (<= (car h) (+ best ap)) (setq out (cons h out))))))
  (reverse out))

;; The suggestion whose tag reads S, whatever case it was typed in.
(defun abf:tag-lookup (s sugs / hit c)
  (setq s (strcase s) hit nil)
  (foreach c sugs
    (if (and (null hit) (= (strcase (nth 6 c)) s)) (setq hit c)))
  hit)

;; What was chosen, read back: the tag and the reading it stands for,
;; so a click is confirmed before the point moves on it.
(defun abf:say-taken (sug)
  (princ (strcat "\n  " (nth 6 sug) " taken: " (caddr sug) " "
                 (abf:fmt (cadddr sug)) " -> " (abf:fmt (nth 4 sug))
                 ".")))

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
  (setq a0 (angle (abf:2d ctr) (abf:2d pp))
        lo 0.0
        hi 0.0)
  (foreach c sugs
    (if (= (cadr c) held)
      (progn
        (setq d (abf:signed-dang
                  a0 (angle (abf:2d ctr) (abf:2d (nth 5 c)))))
        (if (< d lo) (setq lo d))
        (if (> d hi) (setq hi d)))))
  (if (> (- hi lo) abf:*fuzz*)
    (progn
      (abf:ensure-dashed)
      (entmake (list '(0 . "ARC") '(100 . "AcDbEntity")
                     (cons 8 abf:*sug-layer*)
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
                        pa pb hist stage done made moves hit sce nm pp
                        pair sugs temps c kws shown ans sug havestyle
                        np newpt newnm tried lasthold ments ring note
                        npair spots hits h)

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
                     " found.  Click one, or type its number as it"
                     " reads in the drawing (\"35\" or \"Pt.35\")."))
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
         ;; only when undo is recording - _Begin in a drawing with UNDO
         ;; off (bit 1 of UNDOCTL clear) errors out of the command
         (if (= 1 (logand 1 (getvar "UNDOCTL")))
           (progn
             (command "_.UNDO" "_Begin")
             (setq undo-open T)))
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

             ;; -- 1: which point.  Typed or clicked, the one prompt
             ;;       takes both: (initget 128) hands typed text back
             ;;       from getpoint as the string it is, and a click
             ;;       comes back as the point it is.  Back is typed
             ;;       like a value here, the way it is at every prompt
             ;;       that is not a keyword one.
             ((= stage 1)
              (initget 128)
              (setq ans (getpoint
                          (if movep
                            (strcat "\nPick the point, or type its"
                                    " number (Enter to cancel): ")
                            (strcat "\nPick the point, or type its"
                                    " number"
                                    (if hist " [Back]" "")
                                    " <Enter = done>: ")))
                    hit nil)
              (cond
                ((null ans) (setq done T))
                ((and (not (listp ans)) (abf:back-word-p ans))
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
                (t
                 ;; a click names the survey point under it, exactly as
                 ;; a typed number names one; nothing under it names
                 ;; nothing, and is reported the way a typo is
                 (setq hit (if (listp ans)
                             (abf:nearest ans cands)
                             (abf:find-point ans cands)))
                 (cond
                   ((null hit)
                    (if (listp ans)
                      (princ (strcat "\n  No survey point within "
                                     (rtos abf:*snap* 4 0)
                                     " of that click - nothing drawn."))
                      (princ (strcat "\n  No point numbered \"" ans
                                     "\" in the drawing - nothing"
                                     " drawn."))))
                   ((or (< (abf:dist (abf:cd-pt hit) pa) abf:*fuzz*)
                        (< (abf:dist (abf:cd-pt hit) pb) abf:*fuzz*))
                    (princ (strcat "\n  Pt." (abf:cd-nm hit) " IS a"
                                   " stake - the ties are measured"
                                   " FROM it.")))
                   (t
                    (setq nm   (abf:cd-nm hit)
                          sce  (abf:cd-en hit)   ; what a move copies
                          pp   (abf:cd-pt hit)
                          pair (abf:dim-pair pa pb pp havestyle))
                    (if (null pair)
                      (princ (strcat "\n  Pt." nm " sits on a stake - "
                                     "there is nothing to measure."))
                      (progn
                        (setq made  (1+ made)
                              stage (if movep 3 2))
                        (princ (strcat "\n  Pt." nm ":  "
                                       abf:*a-name* " "
                                       (abf:fmt (abf:dist pa pp)) "   "
                                       abf:*b-name* " "
                                       (abf:fmt (abf:dist pb pp))
                                       "  dimensioned.")))))))))

             ;; -- 2: does this one want moving?  (ABFIND only)
             ((= stage 2)
              (setq ans (abf:askyn (strcat "  Move Pt." nm
                                           " to a different reading?")
                                   "No" T))
              (cond
                ((eq ans 'ABF-BACK)
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
                  (abf:ensure-layer abf:*sug-layer* abf:*sug-color*)
                  ;; where each tag hangs is worked out for the whole
                  ;; round at once - the tags share a row - and kept,
                  ;; because a click on a tag has to find its way back
                  ;; to the suggestion it names
                  (setq spots (abf:tag-spots pa pb pp sugs))
                  (foreach c sugs
                    (setq temps (append temps
                                        (abf:draw-sug
                                          (nth 5 c) (nth 6 c)
                                          (assoc (nth 6 c) spots)))))
                  ;; and the line each group sits on, in the order the
                  ;; table lists them
                  (setq temps (append temps
                                      (abf:draw-locus
                                        pb (abf:dist pb pp) pp sugs
                                        abf:*b-name*)
                                      (abf:draw-locus
                                        pa (abf:dist pa pp) pp sugs
                                        abf:*a-name*)))
                  (setq tried (+ (length (abf:deltas (abf:dist pa pp)))
                                 (length (abf:deltas (abf:dist pb pp)))))
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
                    (princ (strcat "\n   " (abf:pad (nth 6 c) 6)
                                   (abf:pad (cadr c) 6)
                                   (abf:pad (caddr c) 7)
                                   (abf:pad (abf:fmt (cadddr c)) 14)
                                   (abf:pad (abf:fmt (nth 4 c)) 14)
                                   (abf:fmt (abf:dist pp (nth 5 c)))
                                   " "
                                   (abf:compass
                                     (angle (abf:2d pp)
                                            (abf:2d (nth 5 c)))))))
                  (setq stage 4))))

             ;; -- 4: which suggestion.  ONE prompt, three ways to
             ;;       answer it: click the marker or the tag you want,
             ;;       type a tag from the table, or Enter for None.
             ;;       (initget 128) hands typed text back as it is, so
             ;;       every tag is accepted without being a keyword -
             ;;       forty-odd of them in the bracket would swamp the
             ;;       command line - and None/Back stay keywords, so
             ;;       the bracket lists just those, and a click on it
             ;;       sends what it shows.
             ;;
             ;;       A click takes the NEAREST marker or tag.  The
             ;;       tags hang clear of each other, so the tag is the
             ;;       easy target where the markers crowd - and when
             ;;       two or more sit closer than the pickbox spans at
             ;;       this zoom, the click cannot tell them apart, and
             ;;       it says so and asks which, nearest first.  It
             ;;       used to take the first in the LIST within a foot
             ;;       of the click, which near the crossing was always
             ;;       R1A, whichever marker was under the cursor.
             ((= stage 4)
              (initget 128 "None Back Undo")
              (setq ans (getpoint (strcat "\n  Move Pt." nm
                                          " - click a marker or its"
                                          " tag, or type a tag"
                                          " [None/Back] <None>: ")))
              (cond
                ((and ans (not (listp ans)) (member ans '("Back" "Undo")))
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
                ((or (null ans) (and (not (listp ans)) (= ans "None")))
                 (abf:drop temps)
                 (setq temps nil)
                 (princ (strcat "\n  Pt." nm " left where it is."))
                 (if movep
                   (setq done T)
                   (setq hist  (cons (list "DIM" pair) hist)
                         stage 1)))
                ((not (listp ans))
                 ;; typed: a tag from the table - or the Pick that
                 ;; earlier versions asked for first, which is now
                 ;; just what the prompt does
                 (cond
                   ((member (strcase ans) '("P" "PICK"))
                    (princ (strcat "\n  Just click it - this prompt"
                                   " takes the click itself.")))
                   ((setq sug (abf:tag-lookup ans sugs))
                    (abf:say-taken sug)
                    (setq stage 5))
                   (t
                    (princ (strcat "\n  \"" ans "\" is not one of the"
                                   " tags - type one from the table,"
                                   " or click a marker or its tag.")))))
                (t
                 (setq hits (abf:under-click ans sugs spots))
                 (cond
                   ((null hits)
                    (princ (strcat "\n  No marker within "
                                   (rtos abf:*snap* 4 0)
                                   " of that click and no tag under it"
                                   " - try again, or type a tag.")))
                   ((null (cdr hits))
                    (setq sug (cdr (car hits)))
                    (abf:say-taken sug)
                    (setq stage 5))
                   (t
                    ;; the click cannot tell these apart at this zoom:
                    ;; say what they are, and ask - the nearest is the
                    ;; Enter answer, and Back is the markers again
                    (princ (strcat "\n  " (itoa (length hits))
                                   " markers under that click - zoom"
                                   " in, or say which:"))
                    (setq kws "" shown "")
                    (foreach h hits
                      (setq c (cdr h))
                      (princ (strcat "\n   " (abf:pad (nth 6 c) 6)
                                     (caddr c) " "
                                     (abf:fmt (cadddr c)) " -> "
                                     (abf:fmt (nth 4 c))))
                      (setq kws   (strcat kws (if (= kws "") "" " ")
                                          (nth 6 c))
                            shown (strcat shown (if (= shown "") "" "/")
                                          (nth 6 c))))
                    (setq ans (abf:askkw "  Which one?" kws shown
                                         (nth 6 (cdr (car hits))) T))
                    (cond
                      ((eq ans 'ABF-BACK)
                       (princ "\n  Back to the markers."))
                      ((setq sug (abf:tag-lookup ans sugs))
                       (abf:say-taken sug)
                       (setq stage 5))))))))

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
                        ments nil)
                  ;; the chosen one is a survey point, so THIS is what
                  ;; lands on the points layer - and it is the point it
                  ;; came from, copied: same block, same layer, same
                  ;; scale, same attributes, one number different.
                  ;; Only a drawing whose point block is not in its
                  ;; block table has nothing to copy from
                  (abf:ensure-layer abf:*point-layer* abf:*point-color*)
                  (setq newnm (strcat nm abf:*moved-suffix*)
                        ments (if (setq ments
                                    (abf:copy-point sce newpt newnm))
                                ments
                                (abf:make-point newpt newnm)))
                  (abf:ensure-layer abf:*ring-layer* 1)
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
                          ;; the point it just made is a point like
                          ;; any other from here - and a later round
                          ;; that moves IT copies it in turn
                          cands (cons (list newpt newnm (car ments))
                                      cands)
                          stage 1))
                  (princ (strcat "\n  Pt." nm " moved to Pt." newnm
                                 " - " (cadr sug)
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
         (if undo-open (command "_.UNDO" "_End"))
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
