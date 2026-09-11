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
;;;            ABPCREATE   the point is NOT in the drawing: type the
;;;                        two readings it was taped at, see where
;;;                        they cross - or, when they cannot, every
;;;                        place they could have crossed if one of
;;;                        them was written down wrong - pick one,
;;;                        name it, and it is plotted and tied
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
;;; ABPCREATE
;;;   The other half of the same problem.  ABFIND and ABMOVE both start
;;;   from a point that is already plotted; ABPCREATE starts from one
;;;   that is NOT -- the field sheet has a row for it and the drawing
;;;   has nothing.  So it asks for the two readings instead of a
;;;   number:
;;;
;;;       A to the new point [Back] <Enter = done>: 21'-1"
;;;       B to the new point [Back]: 18'-6"
;;;
;;;   and crosses them exactly as the survey did.  BOTH readings are
;;;   drawn whole, as two dashed circles round the stakes -- everywhere
;;;   each tape reaches -- so the answer is on the sheet either way:
;;;   where they cross, or that they do not.
;;;
;;;   THEY CROSS.  There is one spot on the field side of the A-B line,
;;;   it is marked, and the only thing left to settle is what the point
;;;   is called.  Name it and it is plotted and tied, like any other.
;;;
;;;   THEY DO NOT CROSS.  Two tapes that fall short of each other, or
;;;   one arc lying wholly inside the other, cannot place anything --
;;;   and the two circles on screen say so better than a sentence can.
;;;   One of the two readings was written down wrong, which is exactly
;;;   what ABMOVE already knows how to walk: one reading is HELD and
;;;   the other swept -- a foot at a time, abf:*foot-steps* each way,
;;;   plus every number it could have been misread as -- and every pair
;;;   that does cross is offered, tagged 1A, -3B, R1A the same way.
;;;
;;;   Each one is drawn with the PAIR it stands for beside it:
;;;
;;;       7A  28'-1" / 18'-6"
;;;
;;;   because that is what tells the candidates apart here.  ABMOVE's
;;;   markers all share one pair of readings and differ by where they
;;;   sit, so its tag alone names them; ABPCREATE's each stand for a
;;;   DIFFERENT pair, and the pair -- not the position -- is what the
;;;   drafter is checking against the field sheet.  The tag is still
;;;   what you type.
;;;
;;;   IF NONE OF THEM IS RIGHT.  None (the Enter answer) takes no
;;;   reading, and the command asks for another pair -- which is the
;;;   way out when the sheet itself has to be re-read.  Enter at the A
;;;   reading ends the run.
;;;
;;;   NAMING IT.  A point is not created until it is named:
;;;
;;;       Number for the new point <24> (B = back): 23
;;;
;;;   one past the highest number the drawing already carries is
;;;   offered, and a number the drawing already uses is refused -- a
;;;   number names ONE point, and the lookup every tool in this family
;;;   does takes the first match.  The point itself is built like the
;;;   drawing's own: the nearest survey point copied for its block,
;;;   layer, colour, linetype, lineweight, scale, rotation and
;;;   attribute layout, with the number written and every OTHER
;;;   attribute left BLANK.  A point that has just been plotted has no
;;;   elevation and no description, and copying the neighbour's would
;;;   be inventing one (abf:*new-atts* keeps them for a drawing whose
;;;   second attribute really is the same on every point).
;;;
;;;   Then its two ties are drawn, and it asks for the next pair.
;;;
;;; AND WHEN A LOOKUP FINDS NOTHING.  A number typed at ABFIND or
;;; ABMOVE that names no point used to be reported and re-asked, full
;;; stop.  It is much more often a point that was never plotted than a
;;; typo, so both now offer the way forward:
;;;
;;;     No point numbered "23" in the drawing.
;;;     Create Pt.23 from its two readings? [Yes/No/Back] <No>:
;;;
;;;   Yes runs everything under ABPCREATE above, with 23 already
;;;   filled in as the number to offer.  ABFIND then carries on to the
;;;   next point with the new one plotted and tied; ABMOVE, which
;;;   settles ONE point, is done -- the point it was asked about now
;;;   exists, at the reading that was asked for.  No is the Enter
;;;   answer and re-asks the number, because a typo is the other way
;;;   to get here and Enter must not plot a point from one.
;;;
;;; MORE THAN ONE AB LINE ON THE SHEET.  A drawing can carry two
;;; surveys - two pools in one yard, or two field sheets merged - and
;;; then it carries two points named A, two named B, and two of every
;;; Pt.## after them.  Which pair of stakes a point was taped off is
;;; then a real question, and the wrong answer draws two ties that
;;; measure nothing: Pt.1 off the OTHER survey's stakes is not a
;;; reading anybody took.
;;;
;;; An AB LINE is one such pair.  They are worked out once, at the top
;;; of the run: every A is paired with a B shortest tie first, each
;;; stake claimed once - a pair of stakes is set out together and
;;; stands a couple of tape lengths apart, so the shortest tie still
;;; going is the pair that was set out - and they are labelled L1, L2
;;; in the order their A stakes appear in the drawing.  A point belongs
;;; to the line it sits nearest.
;;;
;;; A drawing with ONE pair of stakes makes one line, and none of this
;;; is ever asked or printed.  It is a sheet with two that asks, and it
;;; asks once:
;;;
;;;   * ABFIND and ABMOVE read the line off the FIRST point they are
;;;     given.  Name a number only one point carries and it is simply
;;;     taken, and the line it sits on is reported.  Name one that
;;;     several carry and every one of them is ringed on screen and
;;;     labelled with its line, with what each was taped at off ITS OWN
;;;     stakes printed beside it - which is what the field sheet has,
;;;     and so what tells them apart:
;;;
;;;         2 points are numbered "1" - one per AB line, ringed and
;;;         labelled on screen.
;;;          tag   A             B
;;;          ----  ------------  ------------
;;;          L1    21'-1"        18'-6"
;;;          L2    16'-4"        22'-0"
;;;
;;;         Which AB line is Pt.1 on - click the one you mean, or type
;;;         its label [Back] <Enter = none>:
;;;
;;;   * ABPCREATE has no point to read it off - the point does not
;;;     exist yet, which is the whole reason for the command - so it
;;;     asks off the LINES themselves, each ringed at its two stakes
;;;     with the tie between them dashed and labelled.  So does either
;;;     of the other two when the number it was given names no point
;;;     and the answer to "create it?" was Yes.
;;;
;;; AND THEN IT STAYS THERE.  The answer is the run's: every point
;;; after it is taken to be on the same line, so a second doubled
;;; number is resolved from it and only reported -
;;;
;;;     2 points are numbered "2" - the one on L2 taken.
;;;
;;; - and the ties are measured from that line's stakes.  Only a number
;;; whose points include none on that line asks again, because then the
;;; assumption has nothing to stand on.  A CLICK is never asked about
;;; either way: it names the point it landed on, whatever that point is
;;; numbered.
;;;
;;; Two points numbered the same ON ONE LINE is a fault in the drawing
;;; rather than a second survey, and it is still answerable: the second
;;; takes a letter after the label (L1, L1b).
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
;;; README).  Back at either of the two questions above re-asks the one
;;; in front of it: at the ringed points, the point number; at the AB
;;; lines, the point number that offered to create one - and nothing,
;;; in an ABPCREATE run, where it is the first question of all.
;;; In ABFIND, B/BACK/U/UNDO typed at the point number undoes
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

(setq *abfind-version* "v1.13")      ; announced on load; release_lisp.py
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
(setq abf:*ghost-color*  1)         ; colour of the two whole circles
                                    ; ABPCREATE draws round the stakes
                                    ; - everywhere each tape reaches -
                                    ; in abf:*locus-ltype*: red, so a
                                    ; pair that cannot cross reads as
                                    ; wrong at a glance
(setq abf:*dupe-color*   4)         ; colour of the ring round each
                                    ; point a number names when it
                                    ; names more than one, and round
                                    ; the stakes of each AB line: cyan,
                                    ; so a real point being chosen
                                    ; between never reads as a
                                    ; suggestion (abf:*sug-color*) or
                                    ; as a point already ringed
(setq abf:*dupe-radius*  9.0)       ; radius of that ring - wider than
                                    ; abf:*sug-radius* and than the
                                    ; ring round a moved point, so the
                                    ; three never read as one mark
(setq abf:*line-prefix*  "L")       ; what an AB line is called, on
                                    ; screen and at the prompt: the
                                    ; lines are L1, L2, ... in the
                                    ; order their A stakes appear in
                                    ; the drawing
(setq abf:*new-atts*     nil)       ; T makes a CREATED point copy the
                                    ; other attribute values of the
                                    ; point it was patterned on (an
                                    ; elevation, a description) as well
                                    ; as its layout.  nil leaves them
                                    ; blank: a point that has just been
                                    ; plotted has not been measured for
                                    ; them, and the neighbour's numbers
                                    ; are not its own
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

;; Distance entry with the kind system of STANDARDS.md section 3.  Only
;; REQ is asked for here -- a reading a point is built from is never NA
;; -- but the helper is carried whole so the grouped build can swap it
;; for cal:askdist.  Returns the number, nil for NA, or ABF-BACK.
;; (cal:askdist, copied under this file's prefix.)
(defun abf:askdist (kind msg dflt back / v kw)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; REQ always rejects zero - offering Back must not loosen what
  ;; counts as a valid measurement; ZER alone admits 0
  (if kw
      (initget (cond ((eq kind 'ZER) 5)
                     ((and (eq kind 'SUG) dflt) 6)
                     (t 7))
               kw)
      (initget 7))
  (setq v (getdist
            (strcat "\n" msg
                    (cond ((eq kind 'REQ) "")
                          ((eq kind 'SUG)
                           (if dflt (strcat " <" (rtos dflt) "> (or NA)")
                               " (or NA)"))
                          (t " (or NA if not measured)"))
                    (if back " [Back]" "")
                    ": ")))
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'ABF-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;; The FIRST of the two readings a new point is taped at.  Zero and a
;; negative are refused the way askdist's REQ refuses them, but Enter is
;; left free: this question is the top of ABPCREATE's loop, and Enter is
;; how a run of it ends -- so it cannot be askdist, whose REQ closes
;; Enter off.  ENDTEXT says what Enter does here, which is not the same
;; thing when ABFIND has sent us in mid-run.  Returns the number, nil
;; for Enter, or ABF-BACK.
(defun abf:askfirst (msg endtext / v)
  (initget 6 "Back Undo")
  (setq v (getdist (strcat "\n" msg " [Back] <Enter = " endtext ">: ")))
  (if (and (= (type v) 'STR) (member v '("Back" "Undo"))) 'ABF-BACK v))

;; Free-text entry (the new point's number).  The prompt says how to
;; back out because nothing else will.  (cal:askstr, copied under this
;; file's prefix.)
(defun abf:askstr (msg dflt back / v)
  (setq v (getstring T (strcat "\n" msg
                               (if dflt (strcat " <" dflt ">") "")
                               (if back " (B = back)" "") ": ")))
  (cond ((and back (abf:back-word-p v)) 'ABF-BACK)
        ((= v "") (if dflt dflt v))
        (t v)))

;; Trim leading / trailing blanks; nil-safe.  (cal:trim, copied under
;; this file's prefix.)
(defun abf:trim (s / i n)
  (if (null s) (setq s ""))
  (setq n (strlen s) i 1)
  (while (and (<= i n) (member (substr s i 1) '(" " "\t")))
    (setq i (1+ i)))
  (setq s (substr s i))
  (setq n (strlen s))
  (while (and (> n 0) (member (substr s n 1) '(" " "\t")))
    (setq s (substr s 1 (1- n)) n (1- n)))
  s)

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

;; The NUMBER a typed point name carries: the spelling with the spaces,
;; the hashes and the "Pt." prefix taken off, and nothing else touched.
;; Only the dot right after PT is a prefix dot - a point genuinely named
;; "40.5" keeps its decimal.  This is what the drawing would SHOW, so it
;; is what a point being created is offered as its number: "Pt.23",
;; "#23" and "23" all offer "23".
(defun abf:as-number (s / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (not (member ch '(" " "#")))
      (setq out (strcat out ch)))
    (setq i (1+ i)))
  (if (and (>= (strlen out) 2) (= (strcase (substr out 1 2)) "PT"))
    (progn
      (setq out (substr out 3))
      (if (= (substr out 1 1) ".") (setq out (substr out 2)))))
  out)

;; One comparable form for a point number, so "35", "Pt.35", "pt 35",
;; "#35" and "035" all meet in the middle: the name above, uppercased,
;; and a value that reads as a number rendered numerically so leading
;; zeros do not matter.  (CDCALLOUT's cdo:canon.)
(defun abf:canon (s)
  (setq s (abf:as-number (strcase s)))
  (if (distof s 2)
    (rtos (distof s 2) 2 8)
    s))

;; EVERY survey point a typed number names, in drawing order.  More
;; than one of them is a sheet carrying more than one survey - see
;; "the AB lines" below, where the caller finds out which is meant.
(defun abf:matches (s cands / want out c)
  (setq want (abf:canon s) out nil)
  (foreach c cands
    (if (= (abf:canon (abf:cd-nm c)) want) (setq out (cons c out))))
  (reverse out))

;; The survey point the typed number names, or nil - the first when a
;; drawing carries the same number twice.  Every prompt that can ASK
;; about a duplicate goes through abf:matches instead; this one is for
;; the places where the question is only "is this number taken?".
(defun abf:find-point (s cands)
  (car (abf:matches s cands)))

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
(defun abf:stake (name cands back / hit pk)
  (if (setq hit (abf:find-point name cands))
    (progn
      (princ (strcat "\n  Stake " name " found at Pt."
                     (abf:cd-nm hit) "."))
      (abf:cd-pt hit))
    (progn
      (princ (strcat "\nNo point is numbered \"" name
                     "\" in this drawing - click the " name
                     " stake instead."))
      (if back (initget "Back Undo"))
      (setq pk (getpoint (strcat "\nPick the " name
                                 " stake (Enter to cancel)"
                                 (if back " [Back]" "") ": ")))
      (cond
        ((and back (= (type pk) 'STR) (member pk '("Back" "Undo"))) 'ABF-BACK)
        (pk
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

;; Why a reading RA off PA and a reading RB off PB cannot cross, as a
;; sentence - or nil when they do.  Two circles miss each other two ways
;; round and they are different mistakes: tapes that fall short of each
;; other, and one arc that lies wholly inside the other.  A pair that
;; only just reaches (d exactly ra+rb) touches at one spot and counts as
;; crossing - abf:circint solves it with h = 0.
(defun abf:reach (pa pb ra rb / d)
  (setq d (abf:dist pa pb))
  (cond
    ((> d (+ ra rb))
     (strcat "the two arcs fall " (abf:fmt (- d ra rb))
             " short of each other"))
    ((< d (abs (- ra rb)))
     (strcat (if (> ra rb) abf:*b-name* abf:*a-name*) "'s arc lies "
             (abf:fmt (- (abs (- ra rb)) d)) " inside "
             (if (> ra rb) abf:*a-name* abf:*b-name*) "'s"))))

;; A point well off the PA-PB line on side S (+1 to the left of A->B,
;; -1 to the right), for abf:circint to choose a crossing by.  The two
;; crossings of any pair of readings mirror across that line, so a
;; reference far enough off it names the one on its own side wherever
;; along the line the crossing sits - which a reference NEAR the line
;; does not.
(defun abf:side-ref (pa pb s)
  (polar (abf:loc pa pb 0.0)
         (+ (angle (abf:2d pa) (abf:2d pb)) (* s 0.5 pi))
         (abf:dist pa pb)))

;; The side reference a spot PK stands for: which side of the A-B line
;; it fell on, taken back out to a point that names that side for every
;; crossing rather than only the ones near PK.  nil when it is ON the
;; line, which names no side at all.
(defun abf:click-side (pa pb pk / dx dy cz)
  (setq dx (- (car  pb) (car  pa))
        dy (- (cadr pb) (cadr pa))
        cz (- (* dx (- (cadr pk) (cadr pa)))
              (* dy (- (car  pk) (car  pa)))))
  (if (> (abs cz) abf:*fuzz*)
    (abf:side-ref pa pb (if (> cz 0.0) 1.0 -1.0))))

;; Which side of the A-B line the field is on, read off the survey
;; itself: the mean of every named point that is not a stake.  A pool is
;; taped from two stakes standing to one side of it, so the points
;; already plotted say which side the next one belongs on and nothing
;; has to be asked.  nil when the drawing carries nothing but the
;; stakes, or when what it carries averages out onto the line: then
;; there is genuinely nothing to read, and the caller asks.
(defun abf:field-ref (pa pb cands / n sx sy c p)
  (setq n 0 sx 0.0 sy 0.0)
  (foreach c cands
    (setq p (abf:cd-pt c))
    (if (and (> (abf:dist p pa) abf:*fuzz*)
             (> (abf:dist p pb) abf:*fuzz*))
      (setq n  (1+ n)
            sx (+ sx (car  p))
            sy (+ sy (cadr p)))))
  (if (> n 0)
    (abf:click-side pa pb (list (/ sx n) (/ sy n)))))

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

;;; ---------------------- the AB lines ----------------------------------
;;; A sheet can carry more than one survey, and each brings its own pair
;;; of stakes and its own numbering: two points named A, two named B,
;;; and two of every Pt.## after them.  An AB LINE is one such pair, and
;;; it is what tells those duplicates apart - Pt.1 taped off THIS A and
;;; B is a different point from the Pt.1 taped off the other pair, and
;;; the two ties ABFIND draws are only right if they run to the stakes
;;; the point was actually surveyed from.
;;;
;;; A line is (index a-position b-position tag), the tag being "L1",
;;; "L2": both its label on screen and the answer you type.  A drawing
;;; with one pair of stakes makes one line and nothing here is ever
;;; asked; a drawing that names no stakes makes none, and its stakes are
;;; clicked the way they always were.

(defun abf:ln-ix  (l) (car    l))
(defun abf:ln-a   (l) (cadr   l))
(defun abf:ln-b   (l) (caddr  l))
(defun abf:ln-tag (l) (cadddr l))

;; Insert (distance a b) into LST, shortest tie first.
(defun abf:ins-pair (p lst / out done q)
  (setq out nil done nil)
  (foreach q lst
    (if (and (null done) (< (car p) (car q)))
      (setq done T out (cons p out)))
    (setq out (cons q out)))
  (if (null done) (setq out (cons p out)))
  (reverse out))

;; The AB lines the drawing carries.  Every A is paired with a B,
;; shortest tie first, each stake claimed once: a pair of stakes is set
;; out together and stands a couple of tape lengths apart, so the
;; shortest tie still going is the pair that was set out.  They are
;; NUMBERED in the order their A stakes appear in the drawing, so L1 is
;; the first A on the sheet however the pairing fell out.  A stake left
;; over - three As and two Bs - joins no line, and the caller says so.
(defun abf:lines (cands / as bs raw a b d p useda usedb pairs out ix)
  (setq as  (abf:matches abf:*a-name* cands)
        bs  (abf:matches abf:*b-name* cands)
        raw nil)
  (foreach a as
    (foreach b bs
      (setq d (abf:dist (abf:cd-pt a) (abf:cd-pt b)))
      (if (> d abf:*fuzz*)
        (setq raw (abf:ins-pair (list d a b) raw)))))
  (setq pairs nil useda nil usedb nil)
  (foreach p raw
    (if (and (null (member (cadr  p) useda))
             (null (member (caddr p) usedb)))
      (setq useda (cons (cadr  p) useda)
            usedb (cons (caddr p) usedb)
            pairs (cons p pairs))))
  (setq out nil ix 0)
  (foreach a as
    (foreach p pairs
      (if (equal (cadr p) a)
        (setq ix  (1+ ix)
              out (cons (list ix (abf:cd-pt a) (abf:cd-pt (caddr p))
                              (strcat abf:*line-prefix* (itoa ix)))
                        out)))))
  (reverse out))

;; How many stakes joined no line: the odd A in a drawing with three of
;; them and two Bs.  Worth saying out loud - it means a survey on the
;; sheet has no pair to be measured from.
(defun abf:spare-stakes (cands lines)
  (- (+ (length (abf:matches abf:*a-name* cands))
        (length (abf:matches abf:*b-name* cands)))
     (* 2 (length lines))))

;; The AB line a point belongs to: the one whose A-B line it sits
;; nearest.  A survey is taped from its own two stakes and falls around
;; them, so the nearest pair is the pair it was taped from - and the
;; readings printed beside each candidate let the drafter check that
;; against the field sheet before answering.  nil when there are no
;; lines at all.
(defun abf:line-of (p lines / best bd l d)
  (setq best nil bd nil)
  (foreach l lines
    (setq d (abf:seg-dist (abf:2d p) (abf:2d (abf:ln-a l))
                          (abf:2d (abf:ln-b l))))
    (if (or (null bd) (< d bd)) (setq best l bd d)))
  best)

;; T when point P belongs to line L.
(defun abf:on-line-p (p l lines / hit)
  (and l
       (setq hit (abf:line-of p lines))
       (= (abf:ln-ix hit) (abf:ln-ix l))))

;; The ones of HITS that belong to L, in the order they were given.
(defun abf:on-line (hits l lines / out c)
  (setq out nil)
  (foreach c hits
    (if (abf:on-line-p (abf:cd-pt c) l lines) (setq out (cons c out))))
  (reverse out))

;; The survey points the field side is read off: one line's own, so one
;; survey never votes on which side of another survey's A-B line its
;; pool sits.  Everything, when the drawing makes no lines at all.
(defun abf:line-pts (l lines cands / out c)
  (if (null l)
    cands
    (progn
      (setq out nil)
      (foreach c cands
        (if (abf:on-line-p (abf:cd-pt c) l lines) (setq out (cons c out))))
      (reverse out))))

;; T when TAG is already one of the labels in LST.
(defun abf:tag-used-p (tag lst / hit c)
  (setq hit nil)
  (foreach c lst (if (= (car c) tag) (setq hit T)))
  hit)

;; The points a doubled number names, each labelled with the AB line it
;; belongs to, as (tag position nil point): (tag position ...) is what
;; abf:ask-tag reads a click against, and the point is what the answer
;; stands for.  The label IS the line, because the line is what the
;; question is really about - so two points on the SAME line, which is
;; one survey having used a number twice rather than a second survey,
;; take a letter after it (L1, L1b) so they can still be told apart.
(defun abf:dupe-tags (hits lines / out c l base tag n)
  (setq out nil)
  (foreach c hits
    (setq l    (abf:line-of (abf:cd-pt c) lines)
          base (if l (abf:ln-tag l) "?")
          tag  base
          n    1)
    (while (abf:tag-used-p tag out)
      (setq n   (1+ n)
            tag (strcat base (chr (+ 96 n)))))
    (setq out (cons (list tag (abf:cd-pt c) nil c) out)))
  (reverse out))

;; The entry of such a list whose label reads S.
(defun abf:dupe-by-tag (s lst / hit c)
  (setq s (strcase (abf:trim s)) hit nil)
  (foreach c lst
    (if (and (null hit) (= (strcase (car c)) s)) (setq hit c)))
  hit)

;; The line whose tag reads S, whatever case it was typed in.
(defun abf:line-by-tag (s lines / hit l)
  (setq s (strcase (abf:trim s)) hit nil)
  (foreach l lines
    (if (and (null hit) (= (strcase (abf:ln-tag l)) s)) (setq hit l)))
  hit)

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
;; PP nil is ABPCREATE, where no point is plotted yet: nothing is "where
;; it already is", and only the candidates can collide.
(defun abf:seen-p (p pp lst / hit c)
  (setq hit (and pp (< (abf:dist p pp) abf:*same-eps*)))
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
;;
;; Two references, not one.  NEAR chooses between the two crossings
;; every pair of readings has, mirrored across the A-B line; PP is the
;; place that is already taken.  For ABMOVE they are the same point -
;; the point as it is drawn now - but ABPCREATE has no point yet, so it
;; passes the side the field is on as NEAR and nil as PP.
(defun abf:group (pa a pb b pp near held moved movea
                  / was out dl nd np n cut one k tag reads)
  (setq was   (if movea a b)
        out   nil
        reads 0)
  (foreach dl (abf:deltas was)
    (setq nd (+ was dl)
          np (if movea
               (abf:circint pa nd pb b near)
               (abf:circint pa a pb nd near)))
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
    (append (abf:group pa a pb b pp pp abf:*b-name* abf:*a-name* T)
            (abf:group pa a pb b pp pp abf:*a-name* abf:*b-name* nil))))

;; What a suggestion is drawn and clicked as: its LABEL where it has
;; one, its tag otherwise.  ABMOVE's markers all share one pair of
;; readings and differ by where they sit, so the tag alone names them;
;; ABPCREATE's each stand for a DIFFERENT pair, and the pair is what the
;; drafter is checking against the field sheet - so it is written beside
;; the marker rather than left on the command line.  The tag is still
;; the answer that is typed.
(defun abf:sug-text (c)
  (if (nth 7 c) (nth 7 c) (nth 6 c)))

;; The label a created suggestion carries: its tag, then the pair of
;; readings it stands for - A's first, B's second.
(defun abf:ab-label (pa pb c)
  (strcat (nth 6 c) "  " (abf:fmt (abf:dist pa (nth 5 c)))
          " / " (abf:fmt (abf:dist pb (nth 5 c)))))

;; Every pair of readings A and B COULD have been, if one of the two was
;; written down wrong, that crosses somewhere: ABMOVE's sweep with no
;; point to start from.  NEAR is the side of the A-B line the field is
;; on (abf:field-ref); nothing is plotted yet, so nothing is "the same
;; place" and every crossing counts.  Each entry takes its label as an
;; eighth element, which is what abf:sug-text finds.
(defun abf:create-candidates (pa pb a b near / raw out c)
  (setq raw (append
              (abf:group pa a pb b nil near abf:*b-name* abf:*a-name* T)
              (abf:group pa a pb b nil near abf:*a-name* abf:*b-name* nil))
        out nil)
  (foreach c raw
    (setq out (cons (append c (list (abf:ab-label pa pb c))) out)))
  (reverse out))

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
;; holds the number is written, and only with NM -- KEEP says what
;; happens to the rest.  A point that MOVED is the same point one
;; reading further on, so ABMOVE keeps them; a point being CREATED has
;; been measured for none of them, so ABPCREATE blanks them rather than
;; copy the neighbour's elevation onto a point that has none.
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
(defun abf:copy-point (en p nm keep / ed atts sub sd base dx dy lay numi
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
        (if (and numi (= i numi))
          (setq sd (abf:put sd 1 nm))
          (if (not keep) (setq sd (abf:put sd 1 ""))))
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

;; The number to offer for a new point: one past the highest the
;; drawing already uses, as a string.  A survey numbers its points in
;; sequence, so the next one is nearly always what is wanted - and it is
;; only ever the DEFAULT, shown in the prompt and typed over.
(defun abf:next-number (cands / hi c v)
  (setq hi 0.0)
  (foreach c cands
    (if (setq v (distof (abf:cd-nm c) 2))
      (if (> v hi) (setq hi v))))
  (itoa (1+ (fix hi))))

;; The point a new one is patterned on: the survey point nearest to
;; where it is going, stakes excluded.  A survey point is more than a
;; position - the layer the survey put it on, a block scaled to the
;; sheet, an attribute height - and a point invented from this file's
;; defaults matches none of it, while its neighbours match all of it.
;; nil when the drawing carries nothing but stakes.
(defun abf:template (p cands pa pb / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (abf:dist p (abf:cd-pt c)))
    (if (and (> (abf:dist (abf:cd-pt c) pa) abf:*fuzz*)
             (> (abf:dist (abf:cd-pt c) pb) abf:*fuzz*)
             (or (null bd) (< d bd)))
      (setq best c bd d)))
  (if best (abf:cd-en best)))

;; A NEW survey point at P numbered NM, built like the drawing's own:
;; TMPL copied for its block, layer, colour, linetype, lineweight,
;; scale, rotation and attribute layout, with the number written and
;; every other attribute left blank unless abf:*new-atts* says to keep
;; them.  Falls back to abf:make-point when there is nothing to copy -
;; a drawing with nothing but stakes, or a block it cannot insert again
;; - so a run never ends with a tie drawn to a point that was not made.
(defun abf:new-point (tmpl p nm / out)
  (if (setq out (abf:copy-point tmpl p nm abf:*new-atts*))
    out
    (abf:make-point p nm)))

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
    (setq longest (max longest (* (strlen (abf:sug-text c)) abf:*sug-hgt*
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
                                   (* (strlen (abf:sug-text c)) abf:*sug-hgt*
                                      abf:*tag-width*))
                             out)))))))
  out)

;; Where each ABPCREATE label hangs, as the same (tag base ang width)
;; spots abf:tag-spots hands back - so the marker drawing, the click
;; test and the tag lookup are shared between the two.
;;
;; ABMOVE's two arcs MEET, at the point as it is drawn now, and its tags
;; fan out into the four empty quarters round that crossing.
;; ABPCREATE's do NOT meet - that is the whole of what it is solving -
;; so there are no quarters and no crossing to hang anything off.  What
;; it has instead is simpler: only the field-side root of each pair is
;; taken, so every candidate of a group sits on ONE side of the A-B
;; line, strung along the arc its held reading draws.  So each label
;; hangs off that arc on a leader abf:*tag-standoff* long and runs
;; RADIALLY, straight on out from the stake: the labels radiate like
;; spokes instead of filing along the arc.
;;
;; That is the whole of the layout, and it is radial for a reason.  A
;; create label is four or five times the length of an ABMOVE tag, and
;; laid ALONG the arc a label that long cannot be kept clear of its
;; neighbours: text runs straight while the arc curves, so it climbs
;; back through the arc and lies across the very markers it labels, and
;; the sideways shoving it then takes to separate two of them drags
;; their leaders into long slants that cross each other.  (Both were
;; measured, not feared: inward, a label passed 1 1/2" from another
;; candidate's marker; outward, twelve leaders crossed on a 50-foot
;; baseline.)  Two rays out of one centre at different angles never
;; meet, so radial labels cannot overlap at all, whatever the readings
;; are.  What is left to keep is the DAYLIGHT between two of them, and
;; that is tightest at the end of the spokes nearer the stake:
;; abf:*sug-hgt* plus abf:*tag-gap* there, which on a pool-sized arc is
;; a degree or two, so a label nudged round to get it keeps a leader
;; that is as good as radial.  A reading barely longer than the label
;; itself needs tens of degrees instead and its leaders do slant across
;; each other - which is the right way round to fail: an untidy leader
;; can be read past and two labels on top of each other cannot.
;;
;; Which WAY each fan points is the other half, and it is what keeps
;; the two groups off each other: a group points away from the other
;; arc - outward when that arc lies inside its own, inward otherwise.
;; Two tapes that fall short both point inward, into their own discs,
;; and those two discs do not touch - that is what falling short MEANS.
;; One arc inside the other puts the outer group outside everything and
;; the inner one deeper in.  Either way the two fans cannot reach each
;; other, so the only spacing left to do is within a group.
(defun abf:create-spots (pa pb ra rb sugs / out held ctr oth rad orad a0
                                           lst c d e sgn off brad inner
                                           step longest prev slot ang
                                           base wid)
  (setq out nil)
  (foreach held (list abf:*b-name* abf:*a-name*)
    (setq ctr  (if (= held abf:*a-name*) pa pb)
          oth  (if (= held abf:*a-name*) pb pa)
          rad  (if (= held abf:*a-name*) ra rb)
          orad (if (= held abf:*a-name*) rb ra)
          ;; the arcs come nearest each other along the line joining the
          ;; stakes, whichever way they miss, so that is where the row
          ;; starts from
          a0   (angle (abf:2d ctr) (abf:2d oth))
          lst  nil
          longest 0.0)
    (foreach c sugs
      (if (= (cadr c) held)
        (setq longest (max longest
                           (* (strlen (abf:sug-text c)) abf:*sug-hgt*
                              abf:*tag-width*))
              lst     (abf:ins-by-abs
                        (cons (abf:signed-dang
                                a0 (angle (abf:2d ctr)
                                          (abf:2d (nth 5 c))))
                              c)
                        lst))))
    (if lst
      (progn
        (setq sgn   (if (< (car (car lst)) 0.0) -1 1)
              off   (if (< (+ (abf:dist ctr oth) orad) rad) 1 -1)
              ;; a reading shorter than the standoff would put an
              ;; inward row of labels through its own stake and out the
              ;; far side, so the row is never taken past it
              brad  (max 1.0 (+ rad (* off abf:*tag-standoff*)))
              ;; where two neighbouring spokes come closest: the end of
              ;; the text nearer the stake.  A reading small enough for
              ;; an inward label to reach past the stake itself has no
              ;; such end, and is held off it instead
              inner (if (> off 0) brad (max 1.0 (- brad longest)))
              step  (/ (+ abf:*sug-hgt* abf:*tag-gap*) inner)
              prev  nil)
        (foreach e lst
          (setq d    (car e)
                c    (cdr e)
                wid  (* (strlen (abf:sug-text c)) abf:*sug-hgt*
                        abf:*tag-width*)
                slot (if prev (max (abs d) prev) (abs d))
                prev (+ slot step)
                ang  (+ a0 (* sgn slot))
                base (polar (abf:2d ctr) ang brad)
                out  (cons (list (nth 6 c)
                                 (list (car base) (cadr base) 0.0)
                                 ;; the spoke runs on OUT from the base,
                                 ;; or back in toward the stake
                                 (abf:angnorm (if (> off 0) ang (+ ang pi)))
                                 wid)
                           out))))))
  out)

;; A suggestion's MARKER: a point where it would sit and a small circle
;; round it, so it can be seen and clicked.  On abf:*sug-layer*, never
;; the points layer - a suggestion is not one of the drawing's own
;; points and must not read as one, to the eye or to the next tool - in
;; abf:*sug-color*, and swept again as soon as the round ends.  Drawn on
;; its own where there is nothing to choose between (ABPCREATE's two
;; readings crossed, so there is one spot and no tag to hang off it).
(defun abf:mark (p / out)
  (setq out nil)
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
  (reverse out))

;; One whole reading: the circle of everywhere one tape reaches, centred
;; on its stake, dashed and in abf:*ghost-color*.  ABPCREATE draws both,
;; so a pair that cannot cross SHOWS that it cannot - two arcs with the
;; gap between them on screen - instead of only saying so; and where it
;; does cross, the crossing is on the sheet where the marker sits.  The
;; two are also the lines the two groups of suggestions sit on, which is
;; why ABPCREATE draws no separate locus the way ABMOVE does.
(defun abf:ghost (ctr rad)
  (abf:ensure-dashed)
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 (cons 8 abf:*sug-layer*)
                 (cons 62 abf:*ghost-color*)
                 (cons 6 abf:*locus-ltype*)
                 '(100 . "AcDbCircle")
                 (list 10 (car ctr) (cadr ctr) 0.0)
                 (cons 40 rad)))
  (list (entlast)))

;; A ring round something the run is asking the drafter to choose
;; between: one of several points a number names, or the stakes of one
;; AB line.  Wider than a suggestion's marker and a different colour,
;; because what it rings is a REAL point already in the drawing, not a
;; place one might move to.  Scaffolding all the same - the suggestion
;; layer, swept at the end of the round.
(defun abf:dupe-ring (p)
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity")
                 (cons 8 abf:*sug-layer*)
                 (cons 62 abf:*dupe-color*) '(100 . "AcDbCircle")
                 (list 10 (car p) (cadr p) 0.0)
                 (cons 40 abf:*dupe-radius*)))
  (list (entlast)))

;; The tag that says which one it is, up and to the right of the ring so
;; it clears both the ring and the point's own number underneath it.
(defun abf:dupe-tag (p tag)
  (entmake (list '(0 . "TEXT") '(100 . "AcDbEntity")
                 (cons 8 abf:*sug-layer*)
                 (cons 62 abf:*dupe-color*) '(100 . "AcDbText")
                 (list 10 (+ (car  p) abf:*dupe-radius*)
                          (+ (cadr p) abf:*dupe-radius*) 0.0)
                 (cons 40 abf:*sug-hgt*) (cons 1 tag)))
  (list (entlast)))

;; One of several points a number names: ringed, and labelled with the
;; AB line it belongs to.  The label is the answer, so two points on the
;; SAME line - a number a survey used twice, which is a drawing fault
;; rather than a second survey - are told apart by a letter after it.
(defun abf:mark-dupe (p tag)
  (append (abf:dupe-ring p) (abf:dupe-tag p tag)))

;; One AB line drawn whole: both stakes ringed, the tie between them
;; dashed, and the line's tag at the middle of it.  This is what
;; ABPCREATE shows when it asks which line a point it is about to plot
;; belongs to - there is no point to ring yet, so the lines themselves
;; are what is picked between.
(defun abf:mark-line (l / out)
  (abf:ensure-dashed)
  (setq out (append (abf:dupe-ring (abf:ln-a l))
                    (abf:dupe-ring (abf:ln-b l))))
  (entmake (list '(0 . "LINE") '(100 . "AcDbEntity")
                 (cons 8 abf:*sug-layer*)
                 (cons 62 abf:*dupe-color*)
                 (cons 6 abf:*locus-ltype*) '(100 . "AcDbLine")
                 (list 10 (car (abf:ln-a l)) (cadr (abf:ln-a l)) 0.0)
                 (list 11 (car (abf:ln-b l)) (cadr (abf:ln-b l)) 0.0)))
  (setq out (append out (list (entlast))))
  (append out (abf:dupe-tag (abf:loc (abf:ln-a l) (abf:ln-b l) 0.0)
                            (abf:ln-tag l))))

;; How far a click landed from one of the things on screen: from the
;; point, or - for an AB line, which is given as its two stakes - from
;; the tie itself, so anywhere along it picks that line.
(defun abf:tag-dist (pk s)
  (if (caddr s)
    (abf:seg-dist (abf:2d pk) (abf:2d (cadr s)) (abf:2d (caddr s)))
    (abf:dist pk (cadr s))))

;; Which of the ringed things was meant.  ONE prompt, the way stage 4
;; asks about suggestions: click the one you want, or type its tag.
;; SPOTS is ((tag position [second-position]) ...).  A click takes the
;; NEAREST - there is nothing else on the layer to hit, and what was
;; taken is read back before anything is drawn from it - so no click is
;; refused for being a few feet out.  Returns the tag, 'ABF-BACK, or
;; nil for Enter.
(defun abf:ask-tag (msg spots back / ans best bd s d)
  (initget 128)
  (setq ans (getpoint (strcat msg (if back " [Back]" "")
                              " <Enter = none>: ")))
  (cond
    ((null ans) nil)
    ((and (not (listp ans)) (abf:back-word-p ans))
     (if back
       'ABF-BACK
       (progn (princ "\n  Nothing to step back to.") 'ABF-AGAIN)))
    ((listp ans)
     (setq best nil bd nil)
     (foreach s spots
       (setq d (abf:tag-dist ans s))
       (if (or (null bd) (< d bd)) (setq best (car s) bd d)))
     best)
    (t
     (setq best nil)
     (foreach s spots
       (if (and (null best)
                (= (strcase (abf:trim ans)) (strcase (car s))))
         (setq best (car s))))
     (if best
       best
       (progn (princ (strcat "\n  \"" ans "\" is not one of the labels"
                             " - type one of them, or click the one you"
                             " want."))
              'ABF-AGAIN)))))

;; One suggestion on screen: its marker, and its tag hung off the arc at
;; SPOT (abf:tag-spots, or abf:create-spots) on a leader from the
;; marker.  A tag whose direction would read upside down is turned round
;; and right-justified on its base, so it still runs away from the
;; leader and never across its neighbours.
(defun abf:draw-sug (p tag spot / out base ang flip)
  (setq out  (reverse (abf:mark p))
        base (cadr  spot)
        ang  (caddr spot)
        flip (and (> ang (* 0.5 pi)) (<= ang (* 1.5 pi))))
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

;; The same, for a pair being CREATED: which reading moved and which
;; was held, because here the PAIR is what was chosen, not a place.
(defun abf:say-made (sug)
  (princ (strcat "\n  " (nth 6 sug) " taken: " (caddr sug) " "
                 (abf:fmt (cadddr sug)) " -> " (abf:fmt (nth 4 sug))
                 ", " (cadr sug) " held.")))

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
;;; ABFIND, ABMOVE and ABPCREATE are one flow, and MODE is which of them
;;; is running: FIND, MOVE or CREATE.  ABMOVE is ABFIND plus the two
;;; questions that move the point; ABPCREATE is the same machinery
;;; entered from the other end, with two readings in place of a number.
;;; All three share the stakes, the crossing arithmetic, the markers,
;;; the one pick prompt and the putback, which is why they are one defun
;;; and not three.  The *error* handler lives here rather than in the
;;; command defuns because this is where the state it has to put back
;;; is - it is localized in the arglist just the same, so the previous
;;; handler comes back when the run ends (STANDARDS.md section 5).
;;;
;;; They differ in shape as well as in questions.  ABFIND and ABPCREATE
;;; rinse and repeat, so they keep a history and Back takes the last
;;; round away again, whatever that round did:
;;;
;;;     ("DIM"  pair)
;;;     ("MOVE" old-pair new-pair moved-point-ents ring note)
;;;     ("NEW"  pair new-point-ents)
;;;
;;; ABMOVE does ONE point - it was typed to settle one - and ends as
;;; soon as that point is settled, whether it moved it or created it, so
;;; it keeps no history.  A single U undoes the whole run either way.

(defun abf:undo-round (r)
  (cond
    ((= (car r) "DIM") (abf:drop (cadr r)))
    ((= (car r) "NEW")
     (abf:drop (cadr r))                   ; the ties to the new point
     (abf:drop (caddr r)))                 ; and the point itself
    (t
     (abf:drop (caddr r))                  ; the dims to where it moved
     (abf:drop (cadddr r))                 ; the moved point
     (abf:drop (list (nth 4 r) (nth 5 r))) ; its ring and its note
     (abf:undrop (cadr r)))))              ; the dims it had before

;; NOTE: no local here may be named after a function this routine calls
;; - an AutoLISP local SHADOWS the function of the same name for the
;; whole call (the BPCALLOUT v1.0 lesson).
(defun abf:run (mode / *error* undo-open oce ocl oos odim cmd cands
                       pa pb hist stage done made moves hit sce nm pp
                       pair sugs temps c kws shown ans sug havestyle
                       np newpt newnm tried lasthold ments ring note
                       npair spots hits h astep movep createp near ra rb
                       why fromfind built deft tmpl pents mk
                       lines curln pend lsel dtag dupes l)

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

  (setq movep   (eq mode 'MOVE)
        ;; createp is the ROUND, not the command: ABFIND and ABMOVE
        ;; raise it too when a number they were given names no point and
        ;; the answer to "create it?" was Yes
        createp (eq mode 'CREATE)
        cmd  (cond ((eq mode 'MOVE)   "ABMOVE")
                   ((eq mode 'CREATE) "ABPCREATE")
                   (t                 "ABFIND"))
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
                     " found."
                     (if createp
                       (strcat "  Give the two readings the new point"
                               " was taped at.")
                       (strcat "  Click one, or type its number as it"
                               " reads in the drawing (\"35\" or"
                               " \"Pt.35\")."))))
      ;; -- the stakes.  A sheet can carry more than one survey, and
      ;;    then it carries more than one A, more than one B, and more
      ;;    than one of every number after them.  abf:lines pairs the
      ;;    stakes up into AB LINES; which line the run is on decides
      ;;    which stakes the ties are measured from AND which of two
      ;;    points numbered the same is meant.
      (setq lines (abf:lines cands)
            curln nil
            pend  nil)
      ;; only worth saying where a pair was actually made: a drawing
      ;; that names one stake and not the other is asked to click the
      ;; missing one, which says it better than a count would
      (if (and lines (> (abf:spare-stakes cands lines) 0))
        (princ (strcat "\n" (itoa (abf:spare-stakes cands lines))
                       " stake(s) pair with nothing - a survey on this"
                       " sheet has no " abf:*a-name* "/" abf:*b-name*
                       " pair to be measured from.")))
      (if (< (length lines) 2)
        ;; the ordinary sheet: one pair of stakes, or none named.
        ;; before OSMODE goes down, because a drawing that does not name
        ;; them wants object snap for the clicks.
        ;; the two stakes are a chain: Back at B re-asks A.  Back is only
        ;; ON THE TABLE when A was CLICKED - when the drawing names it
        ;; there is no question behind this one, and re-asking it would
        ;; find the same point again and walk straight forward, which is a
        ;; deadlock rather than a way back (STANDARDS 7.2, same reason).
        (progn
          (setq astep 1)
          (while (<= astep 2)
            (cond
              ((= astep 1)
               (setq pa    (abf:stake abf:*a-name* cands nil)
                     astep 2))
              ((= astep 2)
               (if (null pa)
                 (setq astep 3)
                 (progn
                   (setq pb (abf:stake abf:*b-name* cands
                                       (null (abf:find-point abf:*a-name* cands))))
                   (if (eq pb 'ABF-BACK)
                     (progn (princ "\n  Stepping back one stake.")
                            (setq pb nil astep 1))
                     (setq astep 3)))))))
          (setq curln (car lines)))
        ;; more than one survey on the sheet.  Which line the run is on
        ;; is not settled here, because the drafter cannot answer it
        ;; here: ABFIND and ABMOVE read it off the first point they are
        ;; given, with the points that carry that number ringed (stage
        ;; 1), and a run that is PLOTTING a point - ABPCREATE, or either
        ;; of the other two creating one - has no point to read it off,
        ;; so it is asked off the lines themselves (stage 11).
        (progn
          (setq pend T)
          (princ (strcat "\n" (itoa (length lines)) " AB lines on this"
                         " sheet - " abf:*a-name* " and " abf:*b-name*
                         " are each numbered more than once, so every"
                         " point number may be too."))
          (princ (strcat "\n  Which line the run is on is settled by the"
                         " first point it handles, and every point after"
                         " it is taken to be on the same one."))))
      (cond
        ((and (null pend) (null pa))
         (princ (strcat "\nNo " abf:*a-name* " stake - nothing drawn.")))
        ((and (null pend) (null pb))
         (princ (strcat "\nNo " abf:*b-name* " stake - nothing drawn.")))
        ((and (null pend) (< (abf:dist pa pb) abf:*fuzz*))
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

         ;; -- which side of the A-B line the field is on.  Two
         ;;    readings cross TWICE, mirrored across the line joining
         ;;    the stakes, so a point built from a pair has to be told
         ;;    which of the two is meant.  The survey already says: the
         ;;    points it has plotted are all on one side of that line.
         ;;    Only a drawing carrying nothing but the stakes says
         ;;    nothing, and only that one is asked (stage 8).  ABFIND
         ;;    and ABMOVE need it too, because either can end up
         ;;    creating a point.
         ;;
         ;;    On a sheet with more than one AB line it is read off THAT
         ;;    line's own points: another survey sits wherever it sits,
         ;;    and letting it vote would put the new point on the wrong
         ;;    side of this one.  A run whose line is not settled yet
         ;;    (ABFIND and ABMOVE, stage 1) reads it when the line is.
         (if (null pend)
           (setq near (abf:field-ref pa pb
                                     (abf:line-pts curln lines cands))))

         ;; -- the round loop.  A round is one point:
         ;;      1  which point       -- its two ties are drawn.  A
         ;;                              number that names none offers
         ;;                              to CREATE it, which is stage 6
         ;;      2  move it?          -- ABFIND only: it measures, so
         ;;                              it asks before going looking.
         ;;                              ABMOVE was typed to move a
         ;;                              point and goes straight on
         ;;      3  work out where it could go, and show it (no
         ;;         question of its own)
         ;;      4  which suggestion  -- shared: the one pick prompt,
         ;;                              for a move and for a creation
         ;;      5  where the note goes, and then the move itself
         ;;      6  the A reading     -- ABPCREATE starts here
         ;;      7  the B reading
         ;;      8  which side of A-B  (only when the drawing is mute)
         ;;      9  cross the two, or show why they cannot and work out
         ;;         the pairs they could have been (no question)
         ;;     10  name it, and then build it
         ;;    Each question backs out into the one before it.  ABFIND
         ;;    and ABPCREATE go round again after every round;
         ;;    ABMOVE settles its one point and ends.
         (setq hist nil done nil made 0 moves 0 built 0 temps nil
               stage (cond ((and createp pend) 11)
                           (createp 6)
                           (t 1)))
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
                     ;; a MOVE and a NEW round each put exactly one
                     ;; point into the lookup, and Back always pops the
                     ;; newest round, so the newest entry is the one it
                     ;; added
                     (if (member (car (car hist)) '("MOVE" "NEW"))
                       (setq cands (cdr cands)))
                     (if (= (car (car hist)) "MOVE")
                       (setq moves (1- moves)))
                     (if (= (car (car hist)) "NEW")
                       (setq built (1- built)))
                     (setq hist (cdr hist)
                           made (1- made))
                     (princ "\nStepping back one point."))
                   (princ "\nAlready at the first point.")))
                (t
                 ;; a click names the survey point under it, exactly as
                 ;; a typed number names one; nothing under it names
                 ;; nothing, and is reported the way a typo is.  A click
                 ;; is never ambiguous - it names the point it landed
                 ;; on, whatever that point is numbered - so only a
                 ;; typed number can reach the question below.
                 (setq hit nil dupes nil)
                 (if (listp ans)
                   (setq hit (abf:nearest ans cands))
                   (progn
                     (setq dupes (abf:matches ans cands)
                           lsel  (if (and curln (> (length dupes) 1))
                                   (abf:on-line dupes curln lines)))
                     (cond
                       ;; one point carries it: the ordinary sheet, and
                       ;; the ordinary sheet is never asked anything
                       ((< (length dupes) 2) (setq hit (car dupes)))
                       ;; the run is already on an AB line and exactly
                       ;; one of them is on it - that is the convention:
                       ;; once a line is settled the rest of the run
                       ;; stays on it, so this one is not asked again,
                       ;; only reported
                       ((= (length lsel) 1)
                        (setq hit (car lsel))
                        (princ (strcat "\n  " (itoa (length dupes))
                                       " points are numbered \""
                                       (abf:as-number ans) "\" - the one"
                                       " on " (abf:ln-tag curln)
                                       " taken.")))
                       ;; otherwise ask: ring them all, print what each
                       ;; was taped at off ITS OWN stakes - which is
                       ;; what the field sheet has, and so what tells
                       ;; them apart - and take a click or a label
                       (t
                        (abf:ensure-layer abf:*sug-layer* abf:*sug-color*)
                        (abf:drop temps)
                        (setq dtag  (abf:dupe-tags dupes lines)
                              temps nil)
                        (foreach c dtag
                          (setq temps (append temps
                                              (abf:mark-dupe (cadr c)
                                                             (car c)))))
                        (princ (strcat "\n  " (itoa (length dupes))
                                       " points are numbered \""
                                       (abf:as-number ans) "\" - one per"
                                       " AB line, ringed and labelled on"
                                       " screen."
                                       (if curln
                                         (strcat "  None of them is on "
                                                 (abf:ln-tag curln) ".")
                                         "")))
                        (princ (strcat "\n   " (abf:pad "tag" 6)
                                       (abf:pad abf:*a-name* 14)
                                       abf:*b-name*))
                        (princ (strcat "\n   " (abf:pad "----" 6)
                                       (abf:pad "------------" 14)
                                       "------------"))
                        (foreach c dtag
                          (setq l (abf:line-of (cadr c) lines))
                          (princ (strcat "\n   " (abf:pad (car c) 6)
                                         (abf:pad
                                           (abf:fmt (abf:dist (abf:ln-a l)
                                                              (cadr c)))
                                           14)
                                         (abf:fmt (abf:dist (abf:ln-b l)
                                                            (cadr c))))))
                        (setq lsel (abf:ask-tag
                                     (strcat "\n  Which AB line is Pt."
                                             (abf:as-number ans)
                                             " on - click the one you"
                                             " mean, or type its label")
                                     dtag T))
                        (abf:drop temps)
                        (setq temps nil)
                        (cond
                          ;; Back re-asks the number itself: that is the
                          ;; question in front of this one
                          ((eq lsel 'ABF-BACK)
                           (princ "\n  Back to the point number."))
                          ((or (null lsel) (eq lsel 'ABF-AGAIN))
                           (princ (strcat "\n  None taken - nothing"
                                          " drawn.")))
                          (t
                           (setq hit (cadddr (abf:dupe-by-tag lsel
                                                              dtag)))))))))
                 ;; the AB line is settled by the first point the run
                 ;; handles, and every point after it is taken to be on
                 ;; the same one - that is what lets the answer above be
                 ;; assumed rather than asked a second time
                 (if (and hit pend)
                   (progn
                     (setq curln (abf:line-of (abf:cd-pt hit) lines)
                           pa    (abf:ln-a curln)
                           pb    (abf:ln-b curln)
                           pend  nil
                           near  (abf:field-ref
                                   pa pb
                                   (abf:line-pts curln lines cands)))
                     (princ (strcat "\n  On AB line " (abf:ln-tag curln)
                                    " (" abf:*a-name* " to " abf:*b-name*
                                    " " (abf:fmt (abf:dist pa pb))
                                    ") - the rest of the run stays on"
                                    " it."))))
                 (cond
                   ;; a click on nothing is a stray click and is simply
                   ;; reported; a NUMBER that names nothing is far more
                   ;; often a point that was never plotted than a typo,
                   ;; so that one is offered the way forward.  No is the
                   ;; Enter answer, because a typo is the other way to
                   ;; get here and Enter must not plot a point from one
                   ;; a number that named points and was then declined
                   ;; or backed out of at the pick has said its piece
                   ;; already - it is not a typo and must not raise the
                   ;; offer to plot a point that is plainly in the
                   ;; drawing twice over
                   ((and (null hit) dupes))
                   ((null hit)
                    (if (listp ans)
                      (princ (strcat "\n  No survey point within "
                                     (rtos abf:*snap* 4 0)
                                     " of that click - nothing drawn."))
                      (progn
                        (princ (strcat "\n  No point numbered \"" ans
                                       "\" in the drawing."))
                        (setq mk (abf:askyn
                                   (strcat "  Create Pt."
                                           (abf:as-number ans)
                                           " from its two readings?")
                                   "No" T))
                        (if (eq mk T)
                          (setq newnm    (abf:as-number ans)
                                createp  T
                                fromfind T
                                ;; there is no point to read the AB line
                                ;; off - a point that does not exist is
                                ;; the reason we are here - so a sheet
                                ;; with more than one asks for it first
                                stage    (if pend 11 6))))))
                   ((and pa pb
                         (or (< (abf:dist (abf:cd-pt hit) pa) abf:*fuzz*)
                             (< (abf:dist (abf:cd-pt hit) pb) abf:*fuzz*)))
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
              (setq ans (getpoint
                          (if createp
                            (strcat "\n  "
                                    (if newnm (strcat "Pt." newnm)
                                        "The new point")
                                    " - click a marker or its label, or"
                                    " type a tag [None/Back] <None>: ")
                            (strcat "\n  Move Pt." nm
                                    " - click a marker or its"
                                    " tag, or type a tag"
                                    " [None/Back] <None>: "))))
              (cond
                ((and ans (not (listp ans)) (member ans '("Back" "Undo")))
                 (abf:drop temps)
                 (setq temps nil)
                 ;; ABFIND came here from its own question, so Back
                 ;; re-asks that; ABMOVE came straight from the point
                 ;; number, so Back re-asks that instead; and a round
                 ;; that is creating a point came from the two readings
                 (cond
                   (createp (setq stage 7))
                   (movep
                    (abf:drop pair)
                    (setq made  (1- made)
                          stage 1)
                    (princ "\nStepping back one point."))
                   (t (setq stage 2))))
                ((or (null ans) (and (not (listp ans)) (= ans "None")))
                 (abf:drop temps)
                 (setq temps nil)
                 ;; None here is the way out of a pair that cannot be
                 ;; made to work: nothing is taken, and the command asks
                 ;; for another pair of readings
                 (if createp
                   (progn
                     (princ (strcat "\n  No reading taken - read the"
                                    " sheet again and give another"
                                    " pair."))
                     (setq stage 6))
                   (progn
                     (princ (strcat "\n  Pt." nm " left where it is."))
                     (if movep
                       (setq done T)
                       (setq hist  (cons (list "DIM" pair) hist)
                             stage 1)))))
                ((not (listp ans))
                 ;; typed: a tag from the table - or the Pick that
                 ;; earlier versions asked for first, which is now
                 ;; just what the prompt does
                 (cond
                   ((member (strcase ans) '("P" "PICK"))
                    (princ (strcat "\n  Just click it - this prompt"
                                   " takes the click itself.")))
                   ((setq sug (abf:tag-lookup ans sugs))
                    (if createp (abf:say-made sug) (abf:say-taken sug))
                    (setq newpt (nth 5 sug)
                          stage (if createp 10 5)))
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
                    (if createp (abf:say-made sug) (abf:say-taken sug))
                    (setq newpt (nth 5 sug)
                          stage (if createp 10 5)))
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
                       (if createp (abf:say-made sug) (abf:say-taken sug))
                       (setq newpt (nth 5 sug)
                             stage (if createp 10 5)))))))))

             ;; -- 11: which AB line, on a sheet that carries more than
             ;;        one.  A run that is PLOTTING a point comes here
             ;;        first: there is no point yet to read the line
             ;;        off, so the lines themselves are what is picked
             ;;        between - each ringed at its two stakes with the
             ;;        tie between them dashed and labelled.  Asked
             ;;        once per run: the answer stands for every point
             ;;        after it, which is the whole convention.
             ((= stage 11)
              (abf:ensure-layer abf:*sug-layer* abf:*sug-color*)
              (abf:drop temps)
              (setq temps nil lsel nil)
              (foreach l lines
                (setq temps (append temps (abf:mark-line l))))
              (princ (strcat "\n  " (itoa (length lines)) " AB lines,"
                             " each ringed at its stakes and labelled on"
                             " the tie between them."))
              (princ (strcat "\n   " (abf:pad "tag" 6)
                             abf:*a-name* " to " abf:*b-name*))
              (princ (strcat "\n   " (abf:pad "----" 6) "------------"))
              (foreach l lines
                (princ (strcat "\n   " (abf:pad (abf:ln-tag l) 6)
                               (abf:fmt (abf:dist (abf:ln-a l)
                                                  (abf:ln-b l))))))
              (setq dtag (abf:ask-tag
                           (strcat "\n  Which AB line is "
                                   (if newnm (strcat "Pt." newnm)
                                       "the new point")
                                   " taped off - click it, or type its"
                                   " label")
                           (mapcar '(lambda (x) (list (abf:ln-tag x)
                                                      (abf:ln-a x)
                                                      (abf:ln-b x)))
                                   lines)
                           T))
              (cond
                ((eq dtag 'ABF-AGAIN))          ; re-ask, nothing moved
                ((eq dtag 'ABF-BACK)
                 (abf:drop temps)
                 (setq temps nil)
                 ;; the point number is the question in front of this
                 ;; one when that is what sent us here; ABPCREATE has
                 ;; nothing in front of its first question
                 (if fromfind
                   (progn
                     (setq createp nil fromfind nil newnm nil stage 1)
                     (princ "\n  Back to the point number."))
                   (princ "\n  Already at the first question.")))
                ((null dtag)
                 (abf:drop temps)
                 (setq temps nil)
                 (princ (strcat "\n  No AB line taken - a point is"
                                " plotted off two stakes, and which two"
                                " is the first thing to settle."))
                 (if fromfind
                   (setq createp nil fromfind nil newnm nil stage 1)
                   (setq done T)))
                (t
                 (abf:drop temps)
                 (setq lsel  (abf:line-by-tag dtag lines)
                       temps nil
                       curln lsel
                       pa    (abf:ln-a lsel)
                       pb    (abf:ln-b lsel)
                       pend  nil
                       near  (abf:field-ref
                               pa pb (abf:line-pts curln lines cands))
                       stage 6)
                 (princ (strcat "\n  " (abf:ln-tag lsel) " taken: "
                                abf:*a-name* " and " abf:*b-name* " "
                                (abf:fmt (abf:dist pa pb))
                                " apart - the rest of the run stays on"
                                " it.")))))

             ;; -- 6: the A reading.  ABPCREATE's first question, and
             ;;       where ABFIND and ABMOVE land when the number they
             ;;       were given names no point and the answer to
             ;;       "create it?" was Yes.  Enter ends an ABPCREATE run
             ;;       but only abandons a creation the other two offered,
             ;;       so the prompt says which of the two it is doing
             ;;       rather than leaving it to be found out.
             ((= stage 6)
              (setq ans (abf:askfirst
                          (strcat "  " abf:*a-name* " to "
                                  (if newnm (strcat "Pt." newnm)
                                      "the new point"))
                          (if fromfind "cancel" "done")))
              (cond
                ((eq ans 'ABF-BACK)
                 (cond
                   ;; the point number is the question in front of this
                   ;; one when that is what sent us here
                   (fromfind
                    (setq createp nil fromfind nil newnm nil stage 1)
                    (princ "\n  Back to the point number."))
                   (hist
                    (abf:undo-round (car hist))
                    ;; a MOVE and a NEW round each put exactly one point
                    ;; into the lookup, and Back always pops the newest
                    ;; round, so the newest entry is the one it added
                    (if (member (car (car hist)) '("MOVE" "NEW"))
                      (setq cands (cdr cands)))
                    (if (= (car (car hist)) "MOVE")
                      (setq moves (1- moves)))
                    (if (= (car (car hist)) "NEW")
                      (setq built (1- built)))
                    (setq hist (cdr hist)
                          made (1- made))
                    (princ "\nStepping back one point."))
                   (t (princ "\nAlready at the first point."))))
                ((null ans)
                 (if fromfind
                   (progn
                     (princ (strcat "\n  Pt." newnm " not created."))
                     (setq createp nil fromfind nil newnm nil stage 1))
                   (setq done T)))
                (t (setq ra ans stage 7))))

             ;; -- 7: the B reading.  Required, with no Enter of its
             ;;       own: a point is crossed from TWO tapes and there
             ;;       is no such thing as half of the pair.
             ((= stage 7)
              (setq ans (abf:askdist 'REQ
                          (strcat "  " abf:*b-name* " to "
                                  (if newnm (strcat "Pt." newnm)
                                      "the new point"))
                          nil T))
              (if (eq ans 'ABF-BACK)
                (setq stage 6)
                (setq rb ans stage 8)))

             ;; -- 8: which side of the A-B line.  Skipped whenever the
             ;;       survey answers it, which is every drawing that has
             ;;       plotted anything at all - so this question is the
             ;;       one nobody normally sees.
             ((= stage 8)
              (if near
                (setq stage 9)
                (progn
                  (princ (strcat "\n  Nothing but the stakes is"
                                 " plotted, so the drawing does not say"
                                 " which side of " abf:*a-name* "-"
                                 abf:*b-name* " the pool is on - and"
                                 " two readings cross on both."))
                  (initget "Back Undo")
                  (setq ans (getpoint
                              (strcat "\n  Click roughly where "
                                      (if newnm (strcat "Pt." newnm)
                                          "the new point")
                                      " belongs [Back]: ")))
                  (cond
                    ((null ans)
                     (princ (strcat "\n  Nothing clicked - the readings"
                                    " again."))
                     (setq stage 7))
                    ((not (listp ans)) (setq stage 7))
                    ((setq near (abf:click-side pa pb ans))
                     (setq stage 9))
                    (t
                     (princ (strcat "\n  That is on the " abf:*a-name*
                                    "-" abf:*b-name* " line itself,"
                                    " which names no side - click to"
                                    " one side of it.")))))))

             ;; -- 9: cross the two readings.  Nothing is asked here.
             ;;       Both are drawn WHOLE, as the circle of everywhere
             ;;       each tape reaches, so the answer is on the sheet
             ;;       either way: they meet at one spot on the field
             ;;       side, and the only thing left to settle is what
             ;;       the point is called - or they cannot meet at all,
             ;;       and the pairs they could have been are worked out
             ;;       and shown exactly the way ABMOVE shows a move.
             ((= stage 9)
              (abf:drop temps)
              (abf:ensure-layer abf:*sug-layer* abf:*sug-color*)
              (setq why   (abf:reach pa pb ra rb)
                    sugs  nil
                    spots nil
                    temps (append (abf:ghost pa ra) (abf:ghost pb rb)))
              (if (null why)
                (progn
                  (setq newpt (abf:circint pa ra pb rb near)
                        temps (append temps (abf:mark newpt)))
                  (princ (strcat "\n  " abf:*a-name* " " (abf:fmt ra)
                                 " and " abf:*b-name* " " (abf:fmt rb)
                                 " cross on the field side - marked."))
                  (setq stage 10))
                (progn
                  (princ (strcat "\n\n  " abf:*a-name* " " (abf:fmt ra)
                                 " and " abf:*b-name* " " (abf:fmt rb)
                                 " cannot cross: " why
                                 " - both are drawn whole, so the gap"
                                 " is on screen."))
                  (setq sugs (abf:create-candidates pa pb ra rb near))
                  (if (null sugs)
                    (progn
                      (princ (strcat "\n  No reading within "
                                     (abf:fmt abf:*max-shift*)
                                     " of either makes the two meet -"
                                     " read the sheet again and give"
                                     " another pair."))
                      (abf:drop temps)
                      (setq temps nil stage 6))
                    (progn
                      ;; where each label hangs is worked out for the
                      ;; whole round at once - each is spaced off the
                      ;; ones before it - and kept, because a click on
                      ;; one has to find its way back to the pair it
                      ;; names
                      (setq spots (abf:create-spots pa pb ra rb sugs))
                      (foreach c sugs
                        (setq temps
                              (append temps
                                      (abf:draw-sug
                                        (nth 5 c) (abf:sug-text c)
                                        (assoc (nth 6 c) spots)))))
                      (setq tried (+ (length (abf:deltas ra))
                                     (length (abf:deltas rb))))
                      (princ (strcat "\n\n  Where "
                                     (if newnm (strcat "Pt." newnm)
                                         "the new point")
                                     " can sit if one of those two was"
                                     " written down wrong - the ones"
                                     " that move " abf:*a-name*
                                     " first, then " abf:*b-name*
                                     " (smallest change first):"))
                      (if (> tried (length sugs))
                        (princ (strcat "\n  "
                                       (itoa (- tried (length sugs)))
                                       " of the " (itoa tried)
                                       " readings are not offered: they"
                                       " still do not reach the other"
                                       " tape"
                                       (if abf:*max-sugg*
                                         ", or are past the list cap"
                                         "")
                                       ".")))
                      (princ (strcat "\n   " (abf:pad "tag" 6)
                                     (abf:pad "moves" 7)
                                     (abf:pad "by" 14)
                                     (abf:pad abf:*a-name* 14)
                                     abf:*b-name*))
                      (princ (strcat "\n   " (abf:pad "----" 6)
                                     (abf:pad "-----" 7)
                                     (abf:pad "------------" 14)
                                     (abf:pad "------------" 14)
                                     "------------"))
                      (setq lasthold nil)
                      (foreach c sugs
                        ;; a blank line where the held stake changes:
                        ;; the two answers read as two blocks, not one
                        ;; long list
                        (if (and lasthold (/= lasthold (cadr c)))
                          (princ "\n"))
                        (setq lasthold (cadr c))
                        (princ
                          (strcat "\n   " (abf:pad (nth 6 c) 6)
                                  (abf:pad (caddr c) 7)
                                  (abf:pad
                                    (strcat
                                      (if (> (nth 4 c) (cadddr c))
                                        "+" "-")
                                      (abf:fmt (abs (- (nth 4 c)
                                                       (cadddr c)))))
                                    14)
                                  (abf:pad
                                    (abf:fmt (abf:dist pa (nth 5 c))) 14)
                                  (abf:fmt (abf:dist pb (nth 5 c))))))
                      (setq stage 4))))))

             ;; -- 10: name it, and then build it.  A point is not
             ;;        created until it is named: the number is what
             ;;        every tool in this family looks it up by, so an
             ;;        unnamed one would be a point nothing can find.
             ((= stage 10)
              (setq deft (if newnm newnm (abf:next-number cands))
                    ans  (abf:askstr "  Number for the new point"
                                     deft T))
              (cond
                ;; back to the pick when there was one to make, and to
                ;; the readings themselves when the pair simply crossed
                ((eq ans 'ABF-BACK) (setq stage (if sugs 4 7)))
                ((= (abf:trim ans) "")
                 (princ (strcat "\n  A point has to be numbered - the"
                                " number is what every later lookup"
                                " finds it by.")))
                ((abf:find-point ans cands)
                 (princ (strcat "\n  Pt." (abf:trim ans) " is already in"
                                " the drawing - a number names ONE"
                                " point, so give this one another.")))
                (t
                 (setq newnm (abf:trim ans))
                 ;; the circles and the markers have done their job
                 (abf:drop temps)
                 (setq temps nil)
                 (abf:ensure-layer abf:*point-layer* abf:*point-color*)
                 (setq tmpl  (abf:template newpt cands pa pb)
                       pents (abf:new-point tmpl newpt newnm)
                       pair  (abf:dim-pair pa pb newpt havestyle)
                       made  (1+ made)
                       built (1+ built)
                       ;; and it is a point like any other from here:
                       ;; the next round can name it, tie it or move it
                       cands (cons (list newpt newnm (car pents)) cands))
                 (princ (strcat "\n  Pt." newnm " created:  "
                                abf:*a-name* " "
                                (abf:fmt (abf:dist pa newpt)) "   "
                                abf:*b-name* " "
                                (abf:fmt (abf:dist pb newpt))
                                "  dimensioned."))
                 (princ
                   (if tmpl
                     (strcat "\n  Built like the survey point nearest"
                             " it"
                             (if abf:*new-atts* ""
                               " - its other attributes left blank")
                             ".")
                     (strcat "\n  Nothing but stakes to pattern it on -"
                             " built on " abf:*point-layer*
                             " from this file's own defaults.")))
                 (if movep
                   ;; ABMOVE settles ONE point, and a point that did not
                   ;; exist is settled by existing
                   (progn
                     (princ (strcat "\n  Pt." newnm " is where those two"
                                    " readings put it - run " cmd
                                    " again to move it."))
                     (setq done T))
                   (setq hist    (cons (list "NEW" pair pents) hist)
                         newnm   nil
                         fromfind nil
                         createp (eq mode 'CREATE)
                         stage   (if (eq mode 'CREATE) 6 1))))))

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
                                    (abf:copy-point sce newpt newnm T))
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
           (princ (strcat "\n" cmd (if (eq mode 'CREATE)
                                     ": no point created."
                                     ": nothing dimensioned.")))
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
                          (if (= moves 1) "it" "they") " came off.")))
         (if (> built 0)
           (princ (strcat "\n" cmd ": " (itoa built) " point"
                          (if (= built 1) "" "s") " created from "
                          (if (= built 1) "its" "their")
                          " two readings.")))))))
  (princ))

;;; ---------------------- commands --------------------------------------

(defun c:ABFIND ()
  (abf:run 'FIND))

(defun c:ABMOVE ()
  (abf:run 'MOVE))

(defun c:ABPCREATE ()
  (abf:run 'CREATE))

(defun c:ABFINDVER ()
  (princ (strcat "\nABFIND " *abfind-version*
                 "  (commands: ABFIND, ABMOVE, ABPCREATE)"))
  (princ))

(princ (strcat "\nABFIND " *abfind-version*
               " loaded.  Commands: ABFIND (dim Pt.## from the "
               abf:*a-name* " and " abf:*b-name*
               " stakes), ABMOVE (the same, and move it to where a"
               " misread tape would put it), ABPCREATE (plot a point"
               " that is not there yet from the two readings it was"
               " taped at)."))
(princ)
