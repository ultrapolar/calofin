;;; cperp_points.lsp  --  AutoCAD 2018 (AutoLISP)
;;;
;;; Command: CPERPPTS   ("C" for curved)
;;;
;;; The curved-geometry companion to PERPPTS (perp_points.lsp).  Same
;;; workflow and same pipeline, but the offsets are taken perpendicular
;;; to the TANGENT of the curve rather than to a straight line, so arcs,
;;; bulged polylines and splines can be offset with a different length
;;; at every point.
;;;
;;; Works on anything AutoCAD treats as a curve: LWPOLYLINE (including
;;; arc/bulge segments), POLYLINE, LINE, ARC, ELLIPSE and SPLINE.
;;;
;;; The offset points are joined into a single LWPOLYLINE whose
;;; segments are ARCS (bulges), each arc matched to the curve's tangent
;;; direction at its start point.  The result is a smooth POLYLINE
;;; curve passing exactly through every offset point -- a real
;;; lightweight polyline, never a spline and never a curve-fit heavy
;;; polyline.
;;;
;;; Points are spaced by true arc length along the curve, so spacing
;;; stays even through curved segments instead of bunching up.
;;;
;;; Workflow
;;;   1. Select a curve (open, i.e. not a closed loop).
;;;   2. Click a point to set the direction:
;;;        - the curve end nearest the click becomes START, the far end
;;;          FINISH, fixing the order the lengths are entered in; a red
;;;          arrow marks START for the whole run;
;;;        - the side of the curve the click lands on is the side the
;;;          new points are offset toward.
;;;   3. Say whether the overall width has changed: Grew, Shrank, New
;;;      or Unchanged.  The width meant is the distance straight across,
;;;      end to end, not the length of the curve.  The change is split
;;;      evenly, half at each end, unless you say otherwise -- then you
;;;      give the amount at the START end (the arrowed one) and the rest
;;;      goes on at FINISH -- and the curve in the drawing is resized to
;;;      match.
;;;   4. Optionally select a BOUNDARY for the offsets -- a property line,
;;;      a house wall, a deck edge already drawn -- and say whether the
;;;      offsets STOP at it (Limit: a typed length past it is brought
;;;      back to it) or RUN OUT TO MEET it (Meet: every point with the
;;;      boundary ahead of it lands on the boundary, and no length is
;;;      asked for it).  Enter takes None and nothing is capped.
;;;   5. Enter how many values (points) are required  (>= 2).
;;;   6. Enter a length for each point, in order START -> FINISH.
;;;      Press Enter to reuse the previous length when it repeats, or
;;;      type B (Back) to step back and re-enter the previous point
;;;      (U, the old keyword, is still accepted).  With a Limit boundary
;;;      the prompt names the distance to it and takes M (Max) to go
;;;      exactly that far; a longer length is brought back to it.
;;;      From the second length on, DIMSTAMP's RULER stands beside the
;;;      drawing: the eighths for an inch either side of the last
;;;      length, and a click on a row IS the length for this point --
;;;      see "The length ruler" below.
;;;   7. Say whether the overall width of the curve just drawn has
;;;      changed -- step 3's question, asked of the course this round
;;;      built.  It is resized the same way, split the same way, before
;;;      anything is measured off it.
;;;   8. Choose whether to repeat on the new polyline.  If so, enter a
;;;      new point count and repeat from step 6 with the new polyline as
;;;      the path.
;;;   9. Pick the dimension style, STANDARD INCHES or SIDE STANDARD.
;;;      Every dimension is then drawn at once, on the DIMENSION layer.
;;;
;;; Steps 1 to 4 are one chain: Back at the click re-opens the
;;; selection, Back at the width question re-opens the click, and Back
;;; at the Limit/Meet question re-opens the boundary selection.  The
;;; boundary selection itself offers no Back, because the resize step 3
;;; made is already in the drawing by then.
;;;
;;; The boundary
;;;   A wall is not always free to run as far as the tape says: there
;;;   is a property line, a house, a deck edge already drawn, and the
;;;   course being built has to answer to it.  Step 4 takes that object
;;;   once, and then asks which of two things it is.
;;;
;;;   Limit: the boundary is the most any offset may reach.  At each
;;;   point a ray is cast from the base point along the offset normal
;;;   and the nearest crossing ahead of it is that point's maximum --
;;;   per point, not one number for the run, because a boundary at an
;;;   angle to the curve is nearer at one end than at the other.  The
;;;   length prompt names it, M (Max) takes it exactly, and a longer
;;;   length is brought back to it and said so; the number typed is
;;;   still what Enter repeats at the next point, since the tape has
;;;   not changed, only where this one point may reach.
;;;
;;;   Meet: the boundary is where every offset ENDS.  A point with the
;;;   boundary ahead of it is placed on the boundary and dimensioned to
;;;   it, and no length is asked -- the offset is the distance to the
;;;   boundary along that point's own normal and nothing else.  Back at
;;;   a length that IS asked steps back to the last length typed, taking
;;;   every point that ran out to the boundary in between with it, and
;;;   to the count question when nothing was typed in front of it.
;;;
;;;   Either way, where the ray never meets the boundary -- it is behind
;;;   the offset side, or stops short of that end of the run -- the
;;;   point has no maximum and no landing, and the prompt is the one it
;;;   always was (Meet says "no boundary ahead" so the silence is not
;;;   mistaken for a landing).  A boundary covering part of a run
;;;   answers for the part it covers.
;;;
;;;   Two things neither mode is.  It holds the measured POINTS at or
;;;   inside the boundary, and the arcs between them are fitted to the
;;;   curve's tangents: where a boundary bends away between two points,
;;;   the arc joining them can still bow past it, and the answer is a
;;;   point there rather than a different arc.  And it is not re-applied
;;;   by the width correction at step 7, which scales the whole curve:
;;;   that is the drafter's own measurement and is not second-guessed,
;;;   but a correction that carries points past a Limit boundary, or
;;;   off a Meet one, says how many.
;;;
;;; The overall width
;;;   Walls get re-measured, and the number that comes back is the
;;;   distance straight across, end to end.  That is what steps 3 and 7
;;;   ask for -- never the developed length of the CURVE, which on
;;;   anything bowed runs further than the width it spans.  Grew and
;;;   Shrank take the difference, New takes the width itself, and
;;;   Unchanged (the default, and Enter) leaves everything exactly as it
;;;   was.
;;;
;;;   A change is then SHARED between the two ends, and the question
;;;   after the amount is how.  Enter (Yes) splits it evenly, half at
;;;   each end, which is what a wall re-measured as a whole usually
;;;   means; No asks how much of it is at the START end -- the end the
;;;   red arrow points at -- and the rest goes on at FINISH.  Zero is an
;;;   answer (all of it at FINISH) and so is the whole amount (all of it
;;;   at START); more than the whole amount would move FINISH the other
;;;   way, which is a different change from the one just given, and is
;;;   refused.  Growing and shrinking are handled alike: the amount is
;;;   what each end moves by, outward or inward.
;;;
;;;   A new width is made true by scaling the curve about a point on
;;;   the line through its two ends: the midpoint for an even split,
;;;   nearer START the more of the change goes to FINISH, and ON an end
;;;   when that end holds still.  One uniform scale, whatever the split,
;;;   so the curve keeps its shape: an arc stays that arc, scaled.  The
;;;   curve in the drawing is resized too, not just the numbers behind
;;;   it -- the offsets and their dimensions are measured off it, so
;;;   leaving it at the old width would put every base point somewhere
;;;   the drawing says nothing is.  The base points and dimensions then
;;;   follow the resized curve, since they are spaced along it after the
;;;   resize.  The whole thing sits inside the command's undo group, so
;;;   one U puts the width back.
;;;
;;;   Every curve gets that question, not just the one selected: each
;;;   round draws the next course out, and a course is re-measured the
;;;   same way the first one was.  A curve the routine draws is only
;;;   ever as wide as the typed offsets add up to, so ends measured a
;;;   little long or a little short leave it that much wide or narrow --
;;;   and the next round spaces its base points along it and reads its
;;;   tangents, which is the same reason step 3 resizes the selected
;;;   curve rather than only remembering a number.  Step 7 asks after
;;;   the polyline is drawn, because that is when there is a width to
;;;   compare against, and before its dimensions are recorded: a round
;;;   that corrects its width has its new points moved with the curve,
;;;   so each dimension reads the distance the corrected drawing really
;;;   has rather than the length that was typed into it.  A resize the
;;;   drawing will not take stops step 3 -- nothing is drawn yet, so
;;;   re-running costs a click -- but at step 7 it leaves the curve at
;;;   the width it drew and says so, because whole rounds of typed
;;;   lengths sit behind it.
;;;
;;; How the offset direction is found
;;;   Every round works from the NEWEST curve.  Round 1 offsets from the
;;;   selected curve; each later round offsets from the arc polyline
;;;   the previous round built.  Each base point sits on that
;;;   newest curve, and its offset runs along the normal of the curve's
;;;   tangent underneath it -- so both the offset and its dimension read
;;;   perpendicular to the line the point actually sits on, and each
;;;   round follows the shape its predecessor took.  A round that
;;;   corrects its width at step 7 is the one exception: the correction
;;;   moves its new points along the resized curve, and that round's
;;;   dimensions read the corrected drawing instead.
;;;
;;;   Which side is used is fixed once, from the direction click,
;;;   relative to the direction of travel (START -> FINISH), so every
;;;   point in every round offsets to the same side however the curves
;;;   bend.
;;;
;;; Properties
;;;   * The offset polylines take the layer, colour, linetype, lineweight
;;;     and linetype scale of the curve they were offset from.
;;;   * The dimensions go on the DIMENSION layer (created if missing)
;;;     and use the dimension style picked in step 9 when the drawing
;;;     has it; otherwise the current style is used and a note is
;;;     printed.
;;;
;;; The length ruler
;;;   Offsets off one wall are rarely all the same number and rarely
;;;   far apart: 44, 44 1/2, 44 1/4, 45, and the run reads like that
;;;   for twenty points.  Typing each one over again is what DIMSTAMP
;;;   stopped doing for stamped text, and its ruler does the same job
;;;   here.  Once a first length has been given, every later length
;;;   prompt draws a column of nearby values down a strip near the
;;;   right edge of the view -- every eighth of an inch for a whole
;;;   inch either side of the last length, graded like a tape (the
;;;   whole inches boldest, the eighths smallest), the last length
;;;   ringed in the middle -- and one prompt takes four answers:
;;;     * click a ROW            -- that value is the length for this
;;;                                 point, and the ruler re-grades
;;;                                 round it for the next;
;;;     * type a length          -- read the way DIMSTAMP reads: 44,
;;;                                 44.5, 44-1/2, 4'4.5 and 4'-4-1/2"
;;;                                 all mean what they say, kept
;;;                                 exactly as typed (44.3 stays 44.3;
;;;                                 the ruler rounds to the eighth).
;;;                                 A fraction is DASHED: the spacebar
;;;                                 is Enter here, so 44 1/2 would be
;;;                                 44 for this point and 1/2 for the
;;;                                 next;
;;;     * Enter                  -- the last length again, as before;
;;;     * click EMPTY SPACE      -- the first of two points to measure
;;;                                 the length between, which is what
;;;                                 getdist always offered here.
;;;   Feet typed put the ruler in the feet family (3'-8", 3'-8 1/8" ...)
;;;   until a plain-inches length is typed.  B, U and M ride through
;;;   unchanged.  The ruler is pinned to the screen, not the drawing,
;;;   so it reads the same at any zoom; it is scratch on the guide
;;;   layer, taken down between rounds and swept with the rest of the
;;;   guides on every way out, Esc included.  Its sizes and colours
;;;   are the knobs in the tunables block.
;;;
;;; Robustness
;;;   * The whole run is one UNDO group: a single U reverses everything.
;;;   * Esc or an error at any prompt restores every system variable it
;;;     changed (OSMODE, CMDECHO, PDMODE, CLAYER, the CE* creation
;;;     defaults, PLINETYPE, PLINEWID and the current dimension style),
;;;     erases the temporary guides and closes the UNDO group.
;;;   * Bad input re-prompts instead of aborting the command; zero and
;;;     negative lengths are rejected, as is a direction click that lands
;;;     on the curve itself (where "which side" would be ambiguous).
;;;   * All geometry is handled in the current UCS, so the command works
;;;     in a rotated or shifted UCS.
;;;
;;; Note: on a tight concave bend, normals converge and large offsets
;;; can make the new curve cross itself -- inherent to offsetting along
;;; normals, not a fault of the routine.  The arc segments pass exactly
;;; through every offset point, so each dimension's endpoint lies on
;;; the new curve.
;;;
;;; License: GPL-3.0-or-later
;;; ---------------------------------------------------------------------

(vl-load-com)

;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *cperp-version* "v0.26")

;;; -------------------- tunables --------------------------------------
;; The LENGTH RULER.  Once a length has been given, every later length
;; prompt draws a column of nearby values beside the drawing -- the
;; DIMSTAMP ruler, borrowed whole: eighths for a whole inch either side
;; of the last length, graded like a tape measure, with the last length
;; ringed in the middle.  Clicking a row hands that value in as the
;; length, so a run of near-equal offsets is clicked rather than typed
;; over and over.  Scratch geometry on the guide layer, swept away with
;; the rest of the guides.  Every size is a fraction of the current
;; view, so the ruler reads the same at any zoom.
(setq cperp:*ruler-color* 3)          ; ACI colour of the rows you can PICK,
                                    ; carried on the entities themselves
(setq cperp:*ruler-current-color* 7)  ; ACI colour of the ringed CURRENT
                                    ; row -- the last length -- so it
                                    ; reads apart from the options; 7 is
                                    ; AutoCAD's black/white swap
(setq cperp:*ruler-screen-x* 0.88)    ; where the spine sits across the
                                    ; view, as a fraction of its width
                                    ; in from the left; past 0.5 the rows
                                    ; reach left, short of it they reach
                                    ; right, so the ruler is always inside
                                    ; the view
(setq cperp:*ruler-row-frac* 0.042)   ; one row's share of the view's
                                    ; height -- the ruler's size knob
(setq cperp:*ruler-txt-frac* 0.5)     ; the biggest row label's height, as
                                    ; a fraction of the row spacing
(setq cperp:*ruler-tick-frac* 0.6)    ; the longest tick, same measure
(setq cperp:*ruler-ring-frac* 0.26)   ; the ring round the current row, as
                                    ; a fraction of the row spacing
(setq cperp:*ruler-reach* 6.0)        ; how far inboard of the spine, in
                                    ; row spacings, a click still counts
                                    ; as picking a row rather than as the
                                    ; first point of a measured length

;; Which answer the "Split the ... evenly, half at each end?" question
;; takes on Enter when a width change has to be shared out: "Yes" puts
;; half of the difference at each end, "No" goes on to ask how much of
;; it the START end takes.  Both words are still offered and either can
;; still be typed -- this only decides what tapping Enter means.
;; Anything that is neither word is ignored and "Yes" stands.
(setq cperp:*split-default* "Yes")

;; Which answer the boundary's "stop at the boundary, or run out to
;; meet it?" question takes on Enter: "Limit" caps a length that would
;; carry a point past the boundary, "Meet" runs every offset out to it
;; without asking a length at all.  Both keywords are still offered and
;; either can still be typed.  Anything that is neither is ignored and
;; "Limit" stands.
(setq cperp:*boundary-default* "Limit")

;; Which of the two dimension styles the closing question takes on
;; Enter -- "STandard" (STANDARD INCHES) or "SIde" (SIDE STANDARD), in
;; any case.  A shop whose work is mostly side dimensions stops
;; re-typing SIde at every run; the question is asked in the same words
;; either way and both keywords are still offered.  Anything that is
;; neither keyword is ignored and "STandard" stands.
(setq cperp:*dimstyle-default* "STandard")

;; The layer every dimension goes on (made if missing, ACI 4) -- the
;; shop-wide DIMENSION layer the other drawing tools use.
(setq cperp:*dimlayer* "DIMENSION")    ; layer the dimensions are drawn on

;;; -------------------- the length ruler --------------------------------
;;;  DIMSTAMP's ruler, as a helper any LENGTH prompt can stand beside.
;;;  Once a first length has been given, the prompt draws the eighths
;;;  of an inch for a whole inch either side of the last one down a
;;;  strip near the right edge of the view, graded like a tape with the
;;;  last length ringed in the middle -- and one prompt then takes a
;;;  click on a row (that row's value), a typed measurement in any
;;;  spelling (44, 44.5, 44-1/2, 4'4.5, 4'-4-1/2"), Enter, a keyword,
;;;  or a click on empty space as the first of two points to measure
;;;  between, which is what getdist always offered.  A run of
;;;  near-equal lengths is clicked rather than typed over and over.
;;;  The fractions are DASHED because the prompt is a getpoint, where
;;;  the spacebar is Enter: 44 1/2 is two answers there, 44 to this
;;;  question and 1/2 to the next, so a bare fraction is refused
;;;  rather than taken as a length of its own.
;;;
;;;  PERPPTS, CPERPPTS, PERPMARK, CORNERSTP, HEMISTEP and NORMIESTEP
;;;  ask their lengths through it.  Each carries this block under its
;;;  own prefix so the standalone file loads alone, the grouped build
;;;  swaps the copy for the library's, and tests/test_ruler_copies.py
;;;  holds every copy to this one text.  DIMSTAMP keeps its own ruler:
;;;  its current row is drawn as the stamp it would make, on the
;;;  stamp's layer in the stamp's style, which is a different thing
;;;  from a row of nearby lengths.
;;;
;;;  A ruler comes in two families, and the prompt picks which.
;;;
;;;  The TAPE is the one above: the eighths of an inch for a whole inch
;;;  either side of the LAST answer, which is what a run of near-equal
;;;  numbers wants.  It needs a last answer to be built round, so the
;;;  first prompt of a run stands alone.
;;;
;;;  The LADDER is the other: a fixed (LO HI STEP) of the values that
;;;  prompt is actually answered with, every one of them offered from
;;;  the first prompt on.  A corner radius is 3" to 2'-0" by 3" and a
;;;  tape of eighths round nothing helps nobody -- 3, 6, 9, 12 is the
;;;  whole vocabulary, and a drafter picks out of it rather than types
;;;  into it.  Its rows are graded off the VALUE, not off a distance
;;;  from the current row: the foot marks are the deep ones and the
;;;  half-foot next, which is where a tape's deep marks are too.  A
;;;  ladder still takes a typed measurement that is not on it, and the
;;;  answer is then ringed among the rungs as the current row.
;;;
;;;  Nothing in here reads a knob.  A tool hands its knobs in as one
;;;  STYLE list and keeps the ruler between prompts as one STATE list:
;;;    STYLE  (COLOR CURRENT-COLOR SCREEN-X ROW-FRAC TXT-FRAC TICK-FRAC
;;;            RING-FRAC REACH) -- a caller's tunables block says what
;;;            each one moves
;;;    STATE  (LEN FEET ENTS BOX ROWS LAY STYLE SAID LADDER) -- the
;;;            length the ruler stands round (nil = none), the family it
;;;            is labelled in (T = feet), what is drawn, its layer, the
;;;            style, whether the one-line hint has been said, and the
;;;            ladder it is standing on (nil = a tape)
;;;  Values are INCHES, the unit this shop draws in, and the ruler
;;;  steps in eighths of one, which is what a tape reads in.

;; T when C is 0-9.
(defun cperp:len-digit-p (c)
  (and (>= (ascii c) 48) (<= (ascii c) 57)))

;; T when S reads as a plain decimal number: digits, at most one dot,
;; at least one digit, nothing else.
(defun cperp:len-num-p (s / i n c dots digits ok)
  (setq n (strlen s) i 1 dots 0 digits 0 ok T)
  (while (and ok (<= i n))
    (setq c (substr s i 1))
    (cond
      ((cperp:len-digit-p c) (setq digits (1+ digits)))
      ((= c ".") (setq dots (1+ dots)))
      (T (setq ok nil)))
    (setq i (1+ i)))
  (and ok (> digits 0) (< dots 2)))

;; S cut on spaces, tabs and dashes, empty pieces dropped -- the
;; separators an inches part is written with, so "4 1/2" and "4-1/2"
;; come apart the same way.  It cuts a keyword list the same way.
(defun cperp:len-split (s / i n c buf out)
  (setq n (strlen s) i 1 buf "" out nil)
  (while (<= i n)
    (setq c (substr s i 1))
    (if (or (= c " ") (= c "\t") (= c "-"))
      (progn
        (if (/= buf "") (setq out (cons buf out)))
        (setq buf ""))
      (setq buf (strcat buf c)))
    (setq i (1+ i)))
  (if (/= buf "") (setq out (cons buf out)))
  (reverse out))

;; One token of an inches part -- a decimal number, or a fraction N/D
;; -- as a number of inches.  nil when it is neither.
(defun cperp:len-token (tok / slash n d)
  (if (setq slash (vl-string-search "/" tok))
    (progn
      (setq n (substr tok 1 slash)
            d (substr tok (+ slash 2)))
      (if (and (cperp:len-num-p n) (cperp:len-num-p d) (/= (atof d) 0.0))
        (/ (atof n) (atof d))))
    (if (cperp:len-num-p tok) (atof tok))))

;; The inches part of a measurement as a number of inches: every token
;; added up, so "4", "4.5", "4 1/2", "4-1/2" and "1/2" all read.  An
;; empty part is 0, which is how 4' reads as 4'-0".  nil when any
;; token is neither a number nor a fraction.
(defun cperp:len-inches (s / toks total v tk)
  (setq toks (cperp:len-split s) total 0.0)
  (foreach tk toks
    (if (and total (setq v (cperp:len-token tk)))
      (setq total (+ total v))
      (setq total nil)))
  total)

;; Read a typed measurement as (INCHES HASFEET): the length in inches,
;; exactly as typed and NOT rounded, and T when feet were spelled --
;; carried through so the ruler is labelled in the family the length
;; was typed in.  Lenient, the way DIMSTAMP reads: the inch mark is
;; optional and may be two apostrophes, the dash after the feet mark is
;; optional, inches may be decimal, and a fraction may be spaced or
;; dashed -- 44, 44.5, 44 1/2, 4'4.5 and 4'-4 1/2" all read.  nil when
;; the text is not a measurement at all.
(defun cperp:parse-len (s / n apos feetstr rest hasfeet feet inch)
  (setq s (vl-string-trim " \t" s)
        n (strlen s))
  (cond
    ((and (>= n 2) (= (substr s (1- n) 2) "''"))
     (setq s (substr s 1 (- n 2))))
    ((and (>= n 1) (= (substr s n 1) "\""))
     (setq s (substr s 1 (1- n)))))
  (setq s (vl-string-trim " \t" s) hasfeet nil feet 0.0)
  (if (setq apos (vl-string-search "'" s))
    (progn
      (setq feetstr (vl-string-trim " \t" (substr s 1 apos))
            rest    (vl-string-trim " \t-" (substr s (+ apos 2))))
      (if (cperp:len-num-p feetstr)
        (setq feet (atof feetstr) hasfeet T)
        (setq rest nil)))
    (setq rest (vl-string-trim " \t" s)))
  (setq inch (if rest (cperp:len-inches rest)))
  (if (and inch (or hasfeet (/= rest "")))
    (list (+ (* feet 12.0) inch) hasfeet)))

;; INCHES to the nearest eighth, as an integer count of eighths -- the
;; unit the ruler is built in.
(defun cperp:len-eighths (inches)
  (fix (+ 0.5 (* 8.0 inches))))

;; Spell TOTAL-EIGHTHS out as text, in the HASFEET family.  STACKED nil
;; is the PLAIN spelling ("44 1/2\"", what the command line says);
;; STACKED T is the DRAWN one, the fraction stacked through AutoCAD's
;; \S code at the size of the text around it, for a ruler label and
;; nothing else.
(defun cperp:spell-len (total-eighths hasfeet stacked / feet remain whole f8
                         g num den fr)
  (if hasfeet
    (setq feet   (/ total-eighths 96)
          remain (- total-eighths (* feet 96)))
    (setq feet 0 remain total-eighths))
  (setq whole (/ remain 8)
        f8    (- remain (* whole 8))
        num   0
        den   1)
  (if (/= f8 0)
    (progn
      (setq g (gcd f8 8))
      (setq num (/ f8 g) den (/ 8 g))))
  (setq fr (cond
             ((= num 0) "")
             ((null stacked) (strcat " " (itoa num) "/" (itoa den)))
             (T (strcat "{\\H1.0000x;\\S" (itoa num) "/" (itoa den) ";}"))))
  (strcat (if (and stacked (/= num 0)) "\\A1;" "")
          (if hasfeet (strcat (itoa feet) "'-") "")
          (itoa whole) fr "\""))

;; What to say when something typed is not a length at all.  The
;; examples are the lazy spellings on purpose: the ones worth showing
;; are the ones that save keystrokes.  A fraction is shown DASHED, never
;; spaced: at a click-or-type prompt the spacebar is Enter, so 44 1/2
;; entered 44 and handed the 1/2 to the next question as half an inch.
(defun cperp:len-unread (v)
  (princ (strcat "\n\"" v "\" is not a length - try 44, 44.5, 44-1/2,"
                 " 4'4.5 or 4'-4-1/2\".")))

;; The RULER TIER an offset of OFFSET eighths from the current value
;; falls in -- 'jump for a whole inch, 'half/'quarter/'eighth for the
;; finer steps, biggest to smallest; a row's tick length and text
;; height read off it.
(defun cperp:ruler-tier (offset / a m)
  (setq a (abs offset) m (rem a 8))
  (cond
    ((= m 0) 'jump)
    ((= m 4) 'half)
    ((member m '(2 6)) 'quarter)
    (T 'eighth)))

;; The nearby values to offer, as (EIGHTHS TIER) pairs: every eighth
;; for a whole inch either side, and with feet in play the 2" and 3"
;; jumps beyond that as well.  A row at or below zero is dropped.
;; Unsorted -- the ruler sorts once it also has the current row.
(defun cperp:ruler-rows (total-eighths hasfeet / out i off)
  (setq out nil i 1)
  (while (<= i 8)
    (setq out (cons (list (- total-eighths i) (cperp:ruler-tier i)) out))
    (setq out (cons (list (+ total-eighths i) (cperp:ruler-tier i)) out))
    (setq i (1+ i)))
  (if hasfeet
    (progn
      (setq i 2)
      (while (<= i 3)
        (setq off (* i 8))
        (setq out (cons (list (- total-eighths off) 'jump) out))
        (setq out (cons (list (+ total-eighths off) 'jump) out))
        (setq i (1+ i)))))
  (vl-remove-if '(lambda (pr) (<= (car pr) 0)) out))

;; The RULER TIER a LADDER rung falls in, read off the value itself
;; rather than off a distance from the current row: a whole foot is the
;; deepest mark, a half foot the next, a quarter foot after that, and
;; everything else is a plain rung.  That is where a tape's deep marks
;; are, so a ladder of radii reads as a ruler and not as a list.
(defun cperp:ladder-tier (eighths)
  (cond
    ((= 0 (rem eighths 96)) 'jump)        ; a whole foot
    ((= 0 (rem eighths 48)) 'half)        ; a half foot
    ((= 0 (rem eighths 24)) 'quarter)     ; a quarter foot
    (T 'eighth)))

;; The rungs of LADDER, given as (LO HI STEP) in inches: every step from
;; LO to HI, as the same (EIGHTHS TIER) pairs a tape's rows are.  A rung
;; at or below zero is dropped, as a tape's rows are.
;;
;; A ladder is a KNOB, and a knob is whatever a drafter left in it -- a
;; string, two numbers where three were wanted, a step of zero.  So the
;; shape is read here rather than trusted: anything that is not three
;; numbers with a positive step has no rungs, and cperp:ruler-show reads
;; that as no ladder.  A settings line typed wrong costs the ruler, not
;; the command.  Unsorted -- the ruler sorts once it also has the
;; current row.
(defun cperp:ladder-rows (ladder / lo hi step v out)
  (setq out nil)
  (if (and (= (type ladder) 'LIST) (= 3 (length ladder))
           (numberp (car ladder)) (numberp (cadr ladder))
           (numberp (caddr ladder)) (> (caddr ladder) 0.0))
    (progn
      (setq lo   (cperp:len-eighths (car ladder))
            hi   (cperp:len-eighths (cadr ladder))
            step (cperp:len-eighths (caddr ladder))
            v    lo)
      (if (> step 0)
        (while (<= v hi)
          (if (> v 0) (setq out (cons (list v (cperp:ladder-tier v)) out)))
          (setq v (+ v step))))))
  out)

;; Ascending by value -- the comparator the ruler sorts rows with.
(defun cperp:ruler-val-lt (a b) (< (car a) (car b)))

;; What the screen is showing, as (LEFT BOTTOM WIDTH HEIGHT) in drawing
;; units: VIEWSIZE is the view's height and SCREENSIZE its aspect.
;; This is what pins the ruler to the same strip of screen at any zoom.
(defun cperp:ruler-view ( / ctr vh ss aspect vw)
  (setq ctr (getvar "VIEWCTR")
        vh  (getvar "VIEWSIZE")
        ss  (getvar "SCREENSIZE"))
  (setq aspect (if (and ss (listp ss) (numberp (car ss))
                        (numberp (cadr ss)) (> (cadr ss) 0))
                 (/ (float (car ss)) (float (cadr ss)))
                 1.6))                    ; no viewport to measure
  (setq vw (* vh aspect))
  (list (- (car ctr) (/ vw 2.0)) (- (cadr ctr) (/ vh 2.0)) vw vh))

;; Which way a row reaches from a spine pinned SCREEN-X of the way
;; across the view: always toward the middle, so a ruler pinned near an
;; edge is never drawn past it.  1.0 toward higher x, -1.0 lower.
(defun cperp:ruler-dir (screen-x)
  (if (> screen-x 0.5) -1.0 1.0))

;; Label height for a row of this TIER, against a row spacing of GAP,
;; the biggest label being FRAC of the spacing.
(defun cperp:ruler-hgt (tier gap frac / base)
  (setq base (* gap frac))
  (cond
    ((eq tier 'half) (* base 0.8))
    ((eq tier 'quarter) (* base 0.65))
    ((eq tier 'eighth) (* base 0.5))
    (T base)))                     ; 'current and 'jump

;; Tick length for a row of this TIER, same measure.
(defun cperp:ruler-tick (tier gap frac / base)
  (setq base (* gap frac))
  (cond
    ((eq tier 'half) (* base 0.75))
    ((eq tier 'quarter) (* base 0.55))
    ((eq tier 'eighth) (* base 0.35))
    (T base)))                     ; 'current and 'jump

;; The ruler is laid out in the UCS -- VIEWCTR is a UCS point, and so
;; is every click the hit test reads -- and entmake takes the WORLD.
;; So each point goes through trans on its way into the drawing: under
;; a UCS whose origin a drafter has moved to the pool's corner, the
;; ruler was drawn that far away from the view it was measured off,
;; out of sight, while the prompt still answered clicks on the empty
;; strip where it should have been.

;; A ruler stroke from (X1 Y1) to (X2 Y2) on LAY in ACI colour COL.
(defun cperp:ruler-line (x1 y1 x2 y2 lay col)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbLine")
                  (cons 10 (trans (list x1 y1 0.0) 1 0))
                  (cons 11 (trans (list x2 y2 0.0) 1 0)))))

;; The ring that marks the current row.
(defun cperp:ruler-ring (x y r lay col)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbCircle")
                  (cons 10 (trans (list x y 0.0) 1 0)) (cons 40 r))))

;; A ruler label: one unwrapped MTEXT of height HGT at PT in the
;; current text style, attached top left (ATT 1) or top right (3) so
;; it grows away from the spine, and running along the UCS X axis
;; (group 11, a WORLD direction) so it reads level in a plan view of
;; that UCS.
(defun cperp:ruler-label (pt hgt str lay col att)
  (entmakex (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbMText")
                  (cons 10 (trans (list (car pt) (cadr pt) 0.0) 1 0))
                  (cons 40 hgt) '(41 . 0.0) (cons 71 att) '(72 . 5)
                  (cons 1 str) (cons 11 (trans '(1.0 0.0 0.0) 1 0 T))
                  '(73 . 1) '(44 . 1.0))))

;; Draw the ruler down its strip of the current view round
;; TOTAL-EIGHTHS, in the HASFEET family, on layer LAY, sized and
;; coloured by STYLE: one row per suggestion plus the ringed current
;; row among them, the whole thing centred vertically in the view.
;; LADDER nil is the tape, the eighths either side of TOTAL-EIGHTHS;
;; a (LO HI STEP) is the ladder, its rungs instead.  TOTAL-EIGHTHS may
;; be nil ON A LADDER and only there -- a ladder is the values a prompt
;; is answered with and stands whether or not one has been given yet,
;; where a tape is built round the last answer and has nothing to be
;; without it.  A rung equal to the current row is dropped, so the row
;; is ringed once rather than drawn twice.
;; Returns (ENTS BOX ROWS): the entities drawn, BOX as (XMIN XMAX YTOL)
;; for the hit test, and ROWS as (EIGHTHS ROW-Y) pairs.
(defun cperp:draw-ruler (total-eighths hasfeet lay style ladder / rows n i row
                          val tier y hgt tl spx ents result view vx vy vw vh
                          gap base rcol dir far near)
  (setq rows (if ladder
               (vl-remove-if '(lambda (pr) (equal (car pr) total-eighths))
                             (cperp:ladder-rows ladder))
               (cperp:ruler-rows total-eighths hasfeet)))
  (if total-eighths
    (setq rows (cons (list total-eighths 'current) rows)))
  (setq rows (vl-sort rows 'cperp:ruler-val-lt))
  (setq view (cperp:ruler-view)
        vx   (car view)  vy (cadr view)
        vw   (caddr view) vh (cadddr view))
  (setq n    (length rows)
        gap  (* vh (nth 3 style))
        spx  (+ vx (* vw (nth 2 style)))
        dir  (cperp:ruler-dir (nth 2 style))   ; rows run inward
        base (- (+ vy (/ vh 2.0)) (* gap (/ (- n 1) 2.0)))
        i    0
        ents nil
        result nil)
  (foreach row rows
    (setq val  (car row) tier (cadr row))
    (setq y    (+ base (* i gap))
          hgt  (cperp:ruler-hgt tier gap (nth 4 style))
          tl   (cperp:ruler-tick tier gap (nth 5 style))
          rcol (if (eq tier 'current) (nth 1 style) (nth 0 style)))
    (setq ents (cons (cperp:ruler-line spx y (+ spx (* dir tl)) y lay rcol)
                     ents))
    ;; half a label's height above the tick puts it astride its own
    ;; row, and the attachment turns with the row: a label on a row
    ;; that reaches left is hung by its RIGHT edge, so it grows away
    ;; from the spine rather than back across it
    (setq ents (cons (cperp:ruler-label (list (+ spx (* dir (+ tl (* gap 0.35))))
                                            (+ y (/ hgt 2.0)))
                                      hgt (cperp:spell-len val hasfeet T)
                                      lay rcol (if (< dir 0.0) 3 1))
                     ents))
    (if (eq tier 'current)
      (setq ents (cons (cperp:ruler-ring spx y (* gap (nth 6 style)) lay rcol)
                       ents)))
    (setq result (cons (list val y) result))
    (setq i (1+ i)))
  (setq ents (cons (cperp:ruler-line spx base spx (+ base (* (- n 1) gap))
                                   lay (nth 0 style))
                   ents))
  ;; the strip a click counts as a pick in: the reach on the side the
  ;; rows run, half a spacing on the other -- the tick's own side
  (setq near (+ spx (* dir gap (nth 7 style)))
        far  (- spx (* dir (/ gap 2.0))))
  (list ents
        (list (min near far) (max near far) (/ gap 2.0))
        (reverse result)))

;; The row (if any) that PT lands on: inside the ruler's strip in X and
;; close enough in Y to one of ROWS.  Returns the row's EIGHTHS, or nil
;; when PT is empty space.
(defun cperp:ruler-hit (pt box rows / r best bd d)
  (setq best nil bd nil)
  (if (and box (>= (car pt) (car box)) (<= (car pt) (cadr box)))
    (foreach r rows
      (setq d (abs (- (cadr pt) (cadr r))))
      (if (and (<= d (caddr box)) (or (null bd) (< d bd)))
        (setq best (car r) bd d))))
  best)

;; A ruler that is not up yet, to draw on LAY in STYLE.
(defun cperp:ruler-new (lay style)
  (list nil nil nil nil nil lay style nil nil))

;; The ruler taken down: its entities erased and forgotten.  The family
;; and the hint flag are kept, since neither is about what is drawn; the
;; ladder is not, since it is what the next prompt asks for and the next
;; prompt says so itself.
;;
;; entdel refuses on a locked layer, and it refuses quietly -- so a
;; ruler that would not come down stayed in the drawing, and every
;; redraw added another.  The tools unlock their own ruler layer before
;; drawing on it; this is the line that says so if one gets through
;; anyway (the step routines draw on the current layer), once per
;; take-down, naming the layer the rows are left on.
(defun cperp:ruler-off (state / e left)
  (setq left 0)
  (foreach e (nth 2 state)
    (if (and e (entget e) (not (entdel e))) (setq left (1+ left))))
  (if (> left 0)
    (princ (strcat "
  " (itoa left) " ruler item(s) could not be"
                   " erased - layer " (vl-princ-to-string (nth 5 state))
                   " is locked.  Unlock it and ERASE them.")))
  (list nil (nth 1 state) nil nil nil (nth 5 state) (nth 6 state)
        (nth 7 state) nil))

;; The ruler the next prompt stands beside: the tape round LEN when
;; LADDER is nil, the rungs of LADDER when it is not -- with LEN ringed
;; among them when there is one.  Drawn fresh when it is not up, or is
;; up round some other length or on some other ladder; left alone when
;; it already is what was asked for; taken down when neither is given,
;; since there is then nothing to build one out of.  Whether it is UP is
;; what is drawn, not what it stands round: a ladder with no answer yet
;; stands round nothing and is up all the same.
;; The one-line hint is said the first time a run draws one.
(defun cperp:ruler-show (state len ladder / rr)
  ;; a ladder nothing can be built out of is no ladder at all, and is
  ;; dropped here rather than drawn as an empty one
  (if (and ladder (null (cperp:ladder-rows ladder))) (setq ladder nil))
  (cond
    ((and (null len) (null ladder)) (cperp:ruler-off state))
    ((and (nth 2 state) (equal (nth 0 state) len)
          (equal (nth 8 state) ladder)) state)
    (T
     (setq state (cperp:ruler-off state))
     (setq rr (cperp:draw-ruler (if len (cperp:len-eighths len)) (nth 1 state)
                              (nth 5 state) (nth 6 state) ladder))
     (if (not (nth 7 state))
       (princ (strcat "\n  A ruler of " (if ladder "the usual" "nearby")
                      " lengths is beside the drawing: click a row to"
                      " take it, or type a length (44, 44-1/2, 3'8).")))
     (list len (nth 1 state) (car rr) (cadr rr) (caddr rr)
           (nth 5 state) (nth 6 state) T ladder))))

;; One length prompt beside the ruler in STATE, and every way of
;; answering it: Enter (nil back, for the caller to read as it always
;; did), a keyword out of KWS (handed back as the keyword), a typed
;; measurement in any spelling cperp:parse-len reads, a click on a ruler
;; row (that row's value), or a click on empty space, which is the
;; first of two points to measure the length between.  Zero, a
;; negative and text that is not a length are refused and asked again,
;; as initget 6 used to refuse them.  Returns (VALUE STATE): the
;; answer, and the ruler as it now stands.
;;
;; READER is the one thing a caller can add to the reading: a function
;; of the typed string returning inches, for a spelling this tree reads
;; somewhere and the library does not -- SPA's "600mm".  It is tried
;; AFTER the standard spellings, so a measurement written the tree's
;; way still reads the tree's way at a prompt that has one, and what it
;; returns is refused on the same terms as anything else: zero and a
;; negative are not lengths whoever read them.  nil = no such spelling,
;; which is every caller but one.
;;
;; The caller SHOWS the ruler first -- (setq rl (cperp:ruler-show rl last
;; ladder) rr (cperp:ask-len prompt kws rl nil) v (car rr) rl (cadr rr)) --
;; and that order is not a nicety: an Esc inside this prompt runs the
;; caller's *error*, and what that handler can take down is the ruler
;; the CALLER's state names.  A ruler drawn in here, in a state only
;; this function held, would outlive the Esc.  The caller keeps the
;; state between prompts and takes the ruler down with cperp:ruler-off
;; before a prompt that does not take it and on every way out.
(defun cperp:ask-len (prompt kws state reader / pk v out done toks)
  (setq done nil out nil)
  (while (not done)
    (if kws (initget 128 kws) (initget 128))
    (setq pk (getpoint prompt))
    (if lzd:ask (lzd:ask prompt pk) pk)
    (cond
      ((null pk) (setq done T))
      ((= (type pk) 'STR)
       (cond
         ((member pk (cperp:len-split (if kws kws ""))) (setq out pk done T))
         ;; a leading minus is refused here, since the reader treats a
         ;; dash as the separator in 4-1/2 and would read -5 as 5
         ((= (substr (vl-string-trim " \t" pk) 1 1) "-")
          (princ "\nA length must be more than zero."))
         ;; a fraction with nothing in front of it is almost always the
         ;; tail of 44 1/2 typed with a space -- which this prompt, a
         ;; getpoint, took as Enter after 44 -- landing on the NEXT
         ;; question.  Taken, it was half an inch there, and nothing
         ;; said so.  Refused, the drafter sees what happened and can
         ;; still give half an inch as 0-1/2 or .5
         ((and (= 1 (length (setq toks (cperp:len-split
                                          (vl-string-trim " \t\"'" pk)))))
               (vl-string-search "/" (car toks)))
          (princ (strcat "\n\"" pk "\" on its own?  A space ends the answer"
                         " at this prompt - type 44-1/2, or 0-1/2 for half"
                         " an inch.")))
         ((setq v (cperp:parse-len pk))
          (if (> (car v) 0.0)
            (progn
              (setq out (car v) done T)
              ;; a typed spelling picks the ruler's family -- feet typed
              ;; means feet on the ruler -- and a change relabels every
              ;; row, so the one standing is taken down here.  Down, not
              ;; forgotten: a ladder stands round no length, so there is
              ;; nothing for forgetting one to redraw
              (if (not (eq (cadr v) (nth 1 state)))
                (setq state (cperp:ruler-off
                              (list (nth 0 state) (cadr v) (nth 2 state)
                                    (nth 3 state) (nth 4 state) (nth 5 state)
                                    (nth 6 state) (nth 7 state)
                                    (nth 8 state))))))
            (princ "\nA length must be more than zero.")))
         ((and reader (setq v (apply reader (list pk))))
          (if (and (numberp v) (> v 0.0))
            (setq out v done T)
            (princ "\nA length must be more than zero.")))
         (T (cperp:len-unread pk))))
      ((setq v (cperp:ruler-hit pk (nth 3 state) (nth 4 state)))
       (setq out (/ v 8.0) done T))
      (T
       (setq v (getdist pk "\nSecond point of the length: "))
       (if lzd:ask (lzd:ask "\nSecond point of the length: " v) v)
       (if (and (numberp v) (> v 0.0))
         (setq out v done T)
         (princ "\nA length must be more than zero.")))))
  (list out state))
;;; -------------------- end of the length ruler -------------------------

;; This file's knobs, in the order the ruler reads them.
(defun cperp:ruler-style ()
  (list cperp:*ruler-color* cperp:*ruler-current-color* cperp:*ruler-screen-x*
        cperp:*ruler-row-frac* cperp:*ruler-txt-frac* cperp:*ruler-tick-frac*
        cperp:*ruler-ring-frac* cperp:*ruler-reach*))

;; The canonical spelling S stands for among KWS, in any case, or nil
;; for anything that is not one of them -- what a tunable default is
;; read through before it reaches a question, since Enter hands a
;; default straight back without checking it, and "side" typed into a
;; settings box must not reach the style table unspelled.
(defun cperp:kw-canon (s kws / u out w)
  (setq u (if (= (type s) 'STR) (strcase s) ""))
  (foreach w kws
    (if (= u (strcase w)) (setq out w)))
  out)

;; The Enter answer each of the three question knobs names, canonicalised
;; -- or the word the file ships with, when the override is none of the
;; keywords the question offers.  One reader per knob, so the global is
;; read in exactly one place and the question itself takes a word it can
;; use.
(defun cperp:split-dflt ()
  (cond ((cperp:kw-canon cperp:*split-default* '("Yes" "No"))) ("Yes")))

(defun cperp:boundary-dflt ()
  (cond ((cperp:kw-canon cperp:*boundary-default* '("Limit" "Meet")))
        ("Limit")))

(defun cperp:dimstyle-dflt ()
  (cond ((cperp:kw-canon cperp:*dimstyle-default* '("STandard" "SIde")))
        ("STandard")))

;; --- generic helpers -------------------------------------------------

;; colour of an entity as a CECOLOR string ("BYLAYER", "3", "12,34,56")
(defun cperp:color (d / c tc)
  (cond
    ((setq tc (cdr (assoc 420 d)))
     (strcat (itoa (logand (lsh tc -16) 255)) ","
             (itoa (logand (lsh tc -8) 255)) ","
             (itoa (logand tc 255))))
    ((setq c (cdr (assoc 62 d)))
     (cond ((= c 0) "BYBLOCK")
           ((= c 256) "BYLAYER")
           (t (itoa (abs c)))))
    (t "BYLAYER")))

;; make sure a layer exists and is usable (thawed, unlocked, on).
;; Repairs through entmod - no command echo, and safe to call from the
;; error handler - and SAYS so when it had to: a run that quietly
;; un-freezes a layer leaves the user wondering why their drawing
;; changed.  (The canonical body of STANDARDS section 5; the grouped
;; build swaps this whole helper for cal:ensure-layer, which has
;; announced all along - this is the standalone tier catching up.)
(defun cperp:layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
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

;; --- curve helpers ---------------------------------------------------
;; vlax-curve-* works on any curve entity and always speaks WCS, so the
;; results are converted into the current UCS as they come back.

;; is this entity something AutoCAD can measure along?
(defun cperp:curve-p (e / r)
  (setq r (vl-catch-all-apply 'vlax-curve-getEndParam (list e)))
  (and r (not (vl-catch-all-error-p r))))

;; total length of the curve
(defun cperp:curvelen (crv)
  (vlax-curve-getDistAtParam crv (vlax-curve-getEndParam crv)))

;; point at arc-length distance d along the curve, in the current UCS
(defun cperp:pt-at-dist (crv d tot / p)
  (setq d (cond ((< d 0.0) 0.0) ((> d tot) tot) (t d)))
  (if (setq p (vlax-curve-getPointAtDist crv d))
    (trans p 0 1)))

;; n points equally spaced by arc length along the curve, START first.
;; rev traverses the curve from its far end.
(defun cperp:curve-pts (crv n rev / tot i d out)
  (setq tot (cperp:curvelen crv) out '() i 0)
  (while (< i n)
    (setq d (* (/ (float i) (float (1- n))) tot))
    (if rev (setq d (- tot d)))
    (setq out (cons (cperp:pt-at-dist crv d tot) out)
          i   (1+ i)))
  (reverse out))

;; Unit tangent of the curve (current UCS) at the point of the curve
;; closest to pt, as a 2D (x y) vector.  rev flips it so the tangent
;; follows the direction of travel when the curve is being traversed
;; from its far end.  Returns nil at a cusp.
(defun cperp:tangent (crv pt rev / w p prm d dx dy dl)
  (setq w   (trans pt 1 0)
        p   (vlax-curve-getClosestPointTo crv w))
  (if (null p)
    nil
    (progn
      (setq prm (vlax-curve-getParamAtPoint crv p))
      ;; floating point can put the projected point a hair off the curve
      (if (null prm)
        (setq prm (vlax-curve-getParamAtDist
                    crv (vlax-curve-getDistAtPoint crv p))))
      (if (null prm)
        nil
        (progn
          ;; a derivative is a direction, so transform it as a displacement
          (setq d  (trans (vlax-curve-getFirstDeriv crv prm) 0 1 T)
                dx (car d)
                dy (cadr d)
                dl (sqrt (+ (* dx dx) (* dy dy))))
          (if (< dl 1e-12)
            nil
            (progn
              (if rev (setq dx (- dx) dy (- dy)))
              (list (/ dx dl) (/ dy dl)))))))))

;; Bulge of the arc from a to b whose tangent at a is tg: tan(alpha/2)
;; where alpha is the signed angle from the tangent to the chord (the
;; arc's included angle is 2*alpha).  Sampling a circle this way
;; reproduces the circle exactly.  Falls back to a straight segment
;; (bulge 0) when there is no tangent or no chord.
(defun cperp:bulge (tg a b / cx cy dot crs alpha lim)
  (setq cx (- (car b) (car a))
        cy (- (cadr b) (cadr a)))
  (if (or (null tg)
          (< (sqrt (+ (* cx cx) (* cy cy))) 1e-12))
    0.0
    (progn
      (setq dot   (+ (* (car tg) cx) (* (cadr tg) cy))
            crs   (- (* (car tg) cy) (* (cadr tg) cx))
            alpha (atan crs dot))
      ;; a chord folding back on the tangent would blow the bulge up
      ;; toward infinity; cap the included angle at ~342 degrees
      (setq lim 2.98)
      (if (> alpha lim)     (setq alpha lim))
      (if (< alpha (- lim)) (setq alpha (- lim)))
      (/ (sin (/ alpha 2.0)) (cos (/ alpha 2.0))))))

;; Turn the straight LWPOLYLINE en (drawn through pts, whose travel
;; tangents are tangs) into an arc polyline: every segment becomes an
;; arc matched to the tangent at its start point.  The entity stays an
;; LWPOLYLINE -- only bulge values are written.
(defun cperp:arcs (en pts tangs / d out g i b)
  (setq d (entget en) out '() i 0)
  (foreach g d
    (cond
      ((= 42 (car g)))                       ; drop existing bulges
      ((= 10 (car g))
       (setq b (if (< (1+ i) (length pts))
                 (cperp:bulge (nth i tangs) (nth i pts) (nth (1+ i) pts))
                 0.0))
       (setq out (cons (cons 42 b) (cons g out))
             i   (1+ i)))
      (t (setq out (cons g out)))))
  (entmod (reverse out)))

;; --- the overall width -----------------------------------------------
;; Widths get re-measured, and the number that comes back is the
;; distance straight across, end to end -- NOT the developed length of
;; the object on the drawing, which on anything bowed is the longer of
;; the two.  Making that width true is one scale of the whole curve
;; about a point on the line through its two ends: the shape between
;; them is carried along, the direction of travel and the offset side
;; are left alone, and WHERE on that line the centre sits is what
;; decides how the change is shared out.  The midpoint puts exactly
;; half of it at each end; a centre nearer START moves START less and
;; FINISH more, and a centre ON an end holds that end still.

;; T when a prompt that DOES take keywords was answered Back - or its
;; hidden synonym Undo.  getdist/getpoint/getint hand a keyword back as
;; a string where a value would be a number or a list.
(defun cperp:back-kw (v)
  (and (= (type v) 'STR) (member v '("Back" "Undo"))))

;; Ask whether the overall width has changed, and how the change is
;; shared between the two ends.  Returns (width frac) -- the width to
;; work to, and the share of the change that lands at the START end,
;; 0.5 when it is split evenly -- or nil when nothing has changed, so
;; an unchanged answer skips the resize altogether, or CPERP-BACK when
;; the first question was answered Back (only offered when back is
;; set).  d is the width the drawing carries now, and lbl heads the
;; line that reports it: the question is asked of the selected curve
;; AND of every curve a round draws, so it has to say which one it
;; means.
;;
;; Four questions walked with a step counter, so Back at any of them
;; re-asks the one in front of it rather than abandoning the resize:
;;   1  Grew / Shrank / New / Unchanged
;;   2  the amount (or the new width itself)
;;   3  split it evenly, half at each end?
;;   4  how much of it at the START end -- the rest goes on at FINISH
(defun cperp:ask-width (lbl d back / kws step kind ans v w diff frac out
                        sdflt)
  (princ (strcat "\n" lbl ", end to end: " (rtos d) "."))
  (setq kws "Grew Shrank New Unchanged" step 1 out nil w nil frac 0.5)
  (while (and (> step 0) (< step 5))
    (cond
      ;; --- 1. has it changed at all?
      ((= step 1)
       (initget (strcat kws (if back " Back Undo" "")))
       (setq kind (getkword (strcat "\nHas that width changed? ["
                                    (vl-string-translate " " "/" kws)
                                    (if back "/Back" "")
                                    "] <Unchanged>: ")))
       ;; the label, not the helper name: one helper asks this of the
       ;; selected object and of every line a round draws, and a report
       ;; that cannot tell them apart cannot say which one died
       (if lzd:ask (lzd:ask lbl kind) kind)
       (cond
         ((or (null kind) (= kind "Unchanged")) (setq out nil step 5))
         ((member kind '("Back" "Undo")) (setq out 'CPERP-BACK step 0))
         (t (setq step 2))))
      ;; --- 2. by how much?
      ((= step 2)
       (cond
         ((= kind "Grew")
          (initget 7 "Back Undo")                ; a real, positive amount
          (setq v (getdist "\nHow much wider? [Back]: "))
          (if lzd:ask (lzd:ask "\nHow much wider? [Back]: " v) v)
          (if (cperp:back-kw v)
            (progn (princ "\nStepping back one question.") (setq step 1))
            (setq w (+ d v) step 3)))
         ((= kind "Shrank")
          (initget 7 "Back Undo")
          (setq v (getdist "\nHow much narrower? [Back]: "))
          (if lzd:ask (lzd:ask "\nHow much narrower? [Back]: " v) v)
          (cond
            ((cperp:back-kw v)
             (princ "\nStepping back one question.")
             (setq step 1))
            ((< v d) (setq w (- d v) step 3))
            (T (princ "\nThat is the whole width or more - nothing would be left."))))
         (T                                      ; New: the width itself
          (initget 6 "Back Undo")                ; Enter keeps what is drawn
          (setq v (getdist (strcat "\nNew overall width <" (rtos d) "> [Back]: ")))
          (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v)
          (cond
            ((cperp:back-kw v)
             (princ "\nStepping back one question.")
             (setq step 1))
            ((or (null v) (equal v d 1e-9)) (setq out nil step 5))
            (T (setq w v step 3))))))
      ;; --- 3. half at each end, or not?
      ((= step 3)
       (setq diff (abs (- w d)))
       (setq sdflt (cperp:split-dflt))
       (initget "Yes No Back Undo")
       (setq ans (getkword (strcat "\nSplit the " (rtos diff)
                                   " evenly, half at each end?"
                                   " [Yes/No/Back] <" sdflt ">: ")))
       (if lzd:ask (lzd:ask (getvar "LASTPROMPT") ans) ans)
       (if (null ans) (setq ans sdflt))  ; Enter = the knob's word
       (cond
         ((member ans '("Back" "Undo"))
          (princ "\nStepping back one question.")
          (setq step 2))
         ((= ans "No") (setq step 4))
         (t (setq frac 0.5 out (list w frac) step 5))))
      ;; --- 4. how much of it at START?  Zero is an answer - all of it
      ;; at FINISH - and so is the whole amount; more than that would
      ;; move FINISH the other way, which is a different change from
      ;; the one just given
      ((= step 4)
       (initget 5 "Back Undo")                  ; no Enter, no negative
       (setq v (getdist (strcat "\nHow much of the " (rtos diff)
                                " at the START end (the arrowed end)?"
                                " [Back]: ")))
       (if lzd:ask (lzd:ask (getvar "LASTPROMPT") v) v)
       (cond
         ((cperp:back-kw v)
          (princ "\nStepping back one question.")
          (setq step 3))
         ((> v (+ diff 1e-9))
          (princ (strcat "\nThat is more than the whole " (rtos diff)
                         " - the FINISH end would have to move the"
                         " other way.")))
         (t
          (setq frac (/ v diff) out (list w frac) step 5)
          (princ (strcat "\nThe other " (rtos (- diff v))
                         " goes at the FINISH end.")))))))
  out)

;; The point to scale about so that FRAC of the change lands at START
;; and the rest at FINISH: that far along the line from START to
;; FINISH.  0.5 is the midpoint, 0 holds START still, 1 holds FINISH
;; still.  z is START's, carried through untouched.
(defun cperp:scale-ctr (ps pf frac)
  (list (+ (car ps)  (* frac (- (car pf)  (car ps))))
        (+ (cadr ps) (* frac (- (cadr pf) (cadr ps))))
        (caddr ps)))

;; The one line that says what a resize did to each end.
(defun cperp:width-line (wOld wNew frac / diff verb)
  (setq diff (abs (- wNew wOld))
        verb (if (> wNew wOld) "added" "taken off"))
  (strcat "\nWidth " (rtos wOld) " -> " (rtos wNew) ": "
          (if (equal frac 0.5 1e-9)
            (strcat (rtos (/ diff 2.0)) " " verb " at each end.")
            (strcat (rtos (* frac diff)) " " verb " at the START end, "
                    (rtos (* (- 1.0 frac) diff)) " at the FINISH end."))))

;; Scale en about ctr (a point in the current UCS) by k.  T when the
;; drawing took it, nil when it would not -- a locked, frozen or
;; switched-off layer is the usual reason, and the caller has to say so
;; rather than measure offsets against geometry the drawing does not
;; actually have.
(defun cperp:rescale (en ctr k / r)
  (setq r (vl-catch-all-apply
            'vla-ScaleEntity
            (list (vlax-ename->vla-object en)
                  (vlax-3d-point (trans ctr 1 0))
                  k)))
  (not (vl-catch-all-error-p r)))

;; p scaled about ctr by k, in plan; z is carried through untouched
(defun cperp:scale-pt (p ctr k)
  (list (+ (car ctr)  (* k (- (car p)  (car ctr))))
        (+ (cadr ctr) (* k (- (cadr p) (cadr ctr))))
        (caddr p)))

;; every point of pts scaled about ctr by k.  The selected curve is
;; re-read from the drawing after a resize, but a curve a round draws
;; has its points in hand -- they are what the dimensions are recorded
;; from -- so they are scaled with it rather than measured off it again.
(defun cperp:scale-pts (pts ctr k / out p)
  (setq out '())
  (foreach p pts (setq out (cons (cperp:scale-pt p ctr k) out)))
  (reverse out))

;; --- the START arrow -------------------------------------------------
;; Three red lines on the guide layer: a shaft running back from START
;; along the curve's tangent there, so the arrow sits outside the curve
;; pointing at the end the lengths are entered from, and two barbs.  It
;; is kept for the whole run, and it is what the width question means
;; by "the arrowed end".  Returns the three enames so the caller can
;; track and redraw them: a resize moves START, and an arrow left where
;; START was would point at nothing.  rev says START is the curve's far
;; end; tot is the curve's length.
(defun cperp:arrow (crv rev tot / p p2 sz tx ty arlen hlen tailx taily
                                 ca sa bkx bky b1x b1y b2x b2y seg out)
  (setq p  (trans (if rev (vlax-curve-getEndPoint crv)
                          (vlax-curve-getStartPoint crv))
                  0 1)
        sz (caddr p)
        ;; a point a little way along the traversal gives the start tangent
        p2 (cperp:pt-at-dist crv
                             (if rev (- tot (* tot 0.001)) (* tot 0.001))
                             tot))
  (setq tx (- (car p2)  (car p))
        ty (- (cadr p2) (cadr p)))
  (if (< (distance p p2) 1e-9)
    (setq tx 1.0 ty 0.0)
    (setq tx (/ tx (distance p p2))
          ty (/ ty (distance p p2))))
  (setq arlen (* tot 0.15))
  (if (< arlen 1e-6) (setq arlen 1.0))
  (setq hlen  (* arlen 0.35)
        tailx (- (car p)  (* tx arlen))
        taily (- (cadr p) (* ty arlen))
        ca    0.9063 sa 0.4226                 ; cos/sin 25 deg
        bkx   (- tx) bky (- ty)
        b1x   (+ (car p)  (* hlen (- (* bkx ca) (* bky sa))))
        b1y   (+ (cadr p) (* hlen (+ (* bkx sa) (* bky ca))))
        b2x   (+ (car p)  (* hlen (+ (* bkx ca) (* bky sa))))
        b2y   (+ (cadr p) (* hlen (+ (* (- bkx) sa) (* bky ca))))
        out   '())
  (foreach seg (list (list (list tailx taily sz) p)
                     (list p (list b1x b1y sz))
                     (list p (list b2x b2y sz)))
    (entmake (list '(0 . "LINE") '(8 . "PERPPTS-TEMP") '(62 . 1)
                   (cons 10 (trans (car seg)  1 0))
                   (cons 11 (trans (cadr seg) 1 0))))
    (setq out (cons (entlast) out)))
  out)

;; --- the boundary the offsets answer to ------------------------------
;; A wall is not always free to run as far as the tape says: there is a
;; property line, a house, a deck edge already drawn, and the course
;; being built has to answer to it.  Selecting that object once turns
;; it into either the maximum for EVERY offset (Limit) or the place
;; every offset ends (Meet) -- per point either way, since a boundary
;; that runs at an angle to the curve is nearer at one end than the
;; other, and one number could not say where.

;; How far p may travel along the unit vector u before it meets bnd:
;; the nearest crossing strictly ahead of p, or nil when the ray never
;; reaches the boundary -- it lies behind the offset side, or off the
;; end of the run, and that point simply has no maximum.
;;
;; A ray is not something AutoCAD can intersect, so one is drawn.  The
;; temporary line is made long enough to reach any point of bnd -- the
;; distance to the nearest point of it plus its own length, which no
;; point on it can be further off than -- and IntersectWith reports the
;; crossings.  The line is erased before this returns, whatever came
;; back, so a run cannot litter the drawing one probe at a time.
(defun cperp:capdist (bndobj p u / near far prev ln rtn lst q d best)
  ;; the nearest point of bnd may not be readable on a degenerate
  ;; curve; its own length alone still reaches a boundary that crosses
  ;; the run, which is the case a cap is wanted for
  (setq near (vlax-curve-getClosestPointTo bndobj (trans p 1 0))
        far  (+ (if near (distance p (trans near 0 1)) 0.0)
                (cperp:curvelen bndobj)))
  (if (< far 1e-9) (setq far 1.0))
  (setq prev (entlast))
  (entmake (list '(0 . "LINE") '(8 . "PERPPTS-TEMP")
                 (cons 10 (trans p 1 0))
                 (cons 11 (trans (list (+ (car p)  (* far (car u)))
                                       (+ (cadr p) (* far (cadr u)))
                                       (caddr p))
                                 1 0))))
  (setq ln (entlast))
  ;; entlast is unmoved when entmake was refused, and erasing on that
  ;; would take whatever WAS last out of the drawing.  No ray, no cap.
  (if (eq ln prev)
    nil
    (progn
      (setq rtn (vl-catch-all-apply
                  'vlax-invoke
                  (list (vlax-ename->vla-object ln) 'IntersectWith
                        bndobj
                        ;; acExtendNone: neither object is stretched to
                        ;; reach the other.  The symbol is AutoCAD's own
                        ;; and is nil where it was never loaded, so the
                        ;; number it stands for is spelled out behind it.
                        (cond (acExtendNone) (0)))))
      (entdel ln)
      (if (or (vl-catch-all-error-p rtn) (null rtn))
        nil
        (progn
          ;; a flat list of WCS x y z, one triple per crossing
          (setq lst rtn best nil)
          (while (>= (length lst) 3)
            (setq q (trans (list (car lst) (cadr lst) (caddr lst)) 0 1)
                  d (+ (* (- (car q)  (car p))  (car u))
                       (* (- (cadr q) (cadr p)) (cadr u))))
            (if (and (> d 1e-8) (or (null best) (< d best))) (setq best d))
            (setq lst (cdddr lst)))
          best)))))

;; How many of pts sit past bnd, each measured along the ray from the
;; base it was offset from.  Every length was capped as it was typed,
;; so this can only come back above zero after a width correction: that
;; scales the whole curve and can carry a point that was sitting ON the
;; boundary out beyond it.  A curve that quietly crosses a boundary the
;; drafter asked it to respect is worth a line of its own.
(defun cperp:past-bnd (bndobj bases pts / i n a b dx dy d u cap out)
  (setq i 0 n (min (length bases) (length pts)) out 0)
  (while (< i n)
    (setq a  (nth i bases)
          b  (nth i pts)
          dx (- (car b)  (car a))
          dy (- (cadr b) (cadr a))
          d  (sqrt (+ (* dx dx) (* dy dy))))
    (if (> d 1e-9)
      (progn
        (setq u   (list (/ dx d) (/ dy d))
              cap (cperp:capdist bndobj a u))
        (if (and cap (> d (+ cap 1e-8))) (setq out (1+ out)))))
    (setq i (1+ i)))
  out)

;; How many of pts no longer sit ON bnd -- the Meet answer's version of
;; the count above.  Every one of them was run out to the boundary as it
;; was placed, so only the width correction can have moved it off, and
;; a curve that no longer meets the boundary it was told to meet is
;; worth a line of its own too.
(defun cperp:off-bnd (bnd pts / p q out)
  (setq out 0)
  (foreach p pts
    (setq q (vlax-curve-getClosestPointTo bnd (trans p 1 0)))
    (if (or (null q) (> (distance p (trans q 0 1)) 1e-6))
      (setq out (1+ out))))
  out)

;; bnd (an ename) as the vla-object cperp:capdist and cperp:past-bnd
;; measure through -- made ONCE, when bnd is fixed for the round,
;; rather than once per point as cperp:capdist used to.  nil in, nil
;; out, so a call site does not have to guard the no-boundary case
;; itself.
(defun cperp:bnd-obj (bnd)
  (if bnd (vlax-ename->vla-object bnd)))

;; --- command ---------------------------------------------------------

;; ahead of the command on purpose: the structural tests scan from
;; c:CPERPPTS to end-of-file for leaked variables, and a defun name
;; there would read as one
(defun c:CPERPPTSVER ()
  (princ (strcat "\nCPERPPTS " *cperp-version*))
  (princ))

(defun c:CPERPPTS (/ *error* cperp:kill cperp:unplace cperp:finish
                                      rl rr
                     os ce pd plw clay cec celt celw celts cdim undoOpen
                     tmpEnts stopped
                     srcData srcLayer srcColor srcLtype srcLw srcLts
                     dimPairs dimStyle pr
                     sel crv etype sp ep click rev side tot
                     tng prj cross fuzz nrm tx ty
                     curCrv curRev n lastN basePts newPts usedBases idxs
                     tangs tg guideEnts total len lastLen i base np again
                     ans iter plt p e
                     wOld wNew wres mid fac qstep arrow bnd bmode cap over
                     rstep askd tgt bdflt dsdflt)

  ;; erase one temporary entity and forget it
  (defun cperp:kill (e)
    (if e
      (progn (if (entget e) (entdel e))
             (setq tmpEnts (vl-remove e tmpEnts)))))

  ;; take back every point placed from index tgt on - guide nodes and
  ;; all - so the prompt for point tgt can be asked again; tgt 0 takes
  ;; back the whole round.  idxs holds each created point's index, so
  ;; skipped points are stepped over on the way back too
  (defun cperp:unplace (tgt)
    (while (and idxs (>= (car idxs) tgt))
      (cperp:kill (car guideEnts))
      (setq guideEnts (cdr guideEnts)
            newPts    (cdr newPts)
            usedBases (cdr usedBases)
            tangs     (cdr tangs)
            idxs      (cdr idxs)))
    (setq i tgt))

  ;; single cleanup path shared by normal exit, Esc and errors.
  ;;
  ;; It runs in AutoCAD's DEFAULT error mode, and must: it is local to
  ;; the command and reads only the command's locals, and under
  ;; *push-error-using-command* AutoCAD resets the evaluator before
  ;; *error* runs.  The handler used to call an undefined cperp:finish
  ;; there and die at its first form -- OSMODE left at 0, the drafter on
  ;; PERPPTS-TEMP, the guides left in, no report, and the mode pushed
  ;; for the session.  The push was only for a bare (command) drain of
  ;; a pending PLINE, and none is ever pending: every (command ...) here
  ;; is fed points the run computed, with no prompt in between, so an
  ;; Esc lands at one of the run's own prompts.  No push, no pop, no
  ;; drain; command-s only.
  (defun cperp:finish ()
    ;; The drafter's settings come back FIRST: putting back values this
    ;; run captured itself is pure setvar and cannot throw, so nothing
    ;; after this block can take them with it.
    (if os    (setvar "OSMODE"    os))
    (if pd    (setvar "PDMODE"    pd))
    (if cec   (setvar "CECOLOR"   cec))
    (if celt  (setvar "CELTYPE"   celt))
    (if celw  (setvar "CELWEIGHT" celw))
    (if celts (setvar "CELTSCALE" celts))
    (if plt   (setvar "PLINETYPE" plt))
    (if plw   (setvar "PLINEWID"  plw))
    ;; CLAYER last of the setvars: it is the one that can throw here, if
    ;; the layer it names was purged while the run was open
    (if clay  (setvar "CLAYER"    clay))
    (if rl (setq rl (cperp:ruler-off rl)))
    (foreach e tmpEnts (if (and e (entget e)) (entdel e)))
    (setq tmpEnts nil)
    ;; cdim is cleared once it is put back: a stop the run explains
    ;; comes through here twice, once before its (exit) and once from
    ;; the handler, and the second -DIMSTYLE landed AFTER the undo group
    ;; had closed -- one more thing for the drafter's next U to undo.
    ;; Everything else in here is already safe to run twice.
    (if (and cdim (tblsearch "DIMSTYLE" cdim))
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" cdim)))
    (setq cdim nil)
    ;; CMDECHO after the -DIMSTYLE restore, so that stays quiet
    (if ce (setvar "CMDECHO" ce))
    (if undoOpen
      (progn (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
             (setq undoOpen nil))))

  (defun *error* (msg)
    (cperp:finish)
    ;; stopped = the run has already said why it is stopping (a resize
    ;; the layer would not take, too few points left to join) and ended
    ;; itself by (exit), which arrives here like an Esc.  "Cancelled."
    ;; under that reason told the drafter they had pressed a key they
    ;; had not.
    (if (not stopped)
      (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nError: " msg))
        (princ "\nCancelled.")))
    (if lzd:report (lzd:report "CPERPPTS" *cperp-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CPERPPTS" *cperp-version*))

  ;; --- save state and open one undo group for the whole run -----------
  (setq os    (getvar "OSMODE")
        ce    (getvar "CMDECHO")
        pd    (getvar "PDMODE")
        clay  (getvar "CLAYER")
        cec   (getvar "CECOLOR")
        celt  (getvar "CELTYPE")
        celw  (getvar "CELWEIGHT")
        celts (getvar "CELTSCALE")
        cdim  (getvar "DIMSTYLE")
        plt   (getvar "PLINETYPE")
        plw   (getvar "PLINEWID")
        tmpEnts '())
  (setvar "CMDECHO" 0)
  ;; PLINE must produce a lightweight polyline so the arc bulges can be
  ;; written into it and the result stays a plain LWPOLYLINE
  (setvar "PLINETYPE" 2)
  ;; ...and a hairline one.  PLINE starts at PLINEWID, which the drawing
  ;; saves and any earlier PLINE Width answer sets, and cperp:arcs keeps
  ;; every group but the bulges -- so one 2" wide polyline drawn earlier
  ;; made every measured course a heavy 2" band, with nothing said.
  ;; Moved only when it is not already 0, so a run borrows nothing it
  ;; does not have to give back.
  (if (and plw (/= plw 0.0)) (setvar "PLINEWID" 0.0))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undoOpen T)))
  (if (member pd '(0 1)) (setvar "PDMODE" 3))

  ;; --- prepare the layers ---------------------------------------------
  ;; PERPPTS-TEMP first: the START arrow and the boundary probe both draw
  ;; on it, and a locked current layer cannot stop them being erased
  ;; there.  Made once, ahead of the chain below, which can come back
  ;; through the click step more than once.
  (cperp:layer "PERPPTS-TEMP" 1)
  (cperp:layer cperp:*dimlayer* 4)
  ;; the length ruler, not up yet: it stands beside the length prompts
  ;; on the guide layer, and cperp:finish takes it down with the guides
  (setq rl (cperp:ruler-new "PERPPTS-TEMP" (cperp:ruler-style)))

  ;; --- 1 to 3: the selection, the click and the width ------------------
  ;; One chain walked with a step counter: Back at the click re-opens
  ;; the selection, and Back at the width question re-opens the click.
  ;; The click comes BEFORE the width question because the width
  ;; question may have to name an end -- how much of a change is at
  ;; START -- and it is the click that says which end that is.
  (setq qstep 1 arrow nil)
  (while (< qstep 4)
    (cond
      ;; --- 1. select a curve (re-prompts until valid) ------------------
      ((= qstep 1)
       (setq crv nil)
       (while (null crv)
         (setq sel (entsel "\nSelect a curve (polyline, arc, spline...): "))
         (if lzd:ask (lzd:ask "\nSelect a curve (polyline, arc, spline...): " sel) sel)
         (if lzd:watch (lzd:watch sel) sel)
         (cond
           ((null sel)
            (princ "\nNothing selected - try again, or press Esc to quit."))
           (t
            (setq etype (cdr (assoc 0 (entget (car sel)))))
            (cond
              ((not (cperp:curve-p (car sel)))
               (princ (strcat "\nA " etype " is not a curve.")))
              ((< (cperp:curvelen (car sel)) 1e-9)
               (princ "\nThat curve has no length."))
              ((equal (vlax-curve-getStartPoint (car sel))
                      (vlax-curve-getEndPoint (car sel)) 1e-9)
               (princ (strcat "\nThat curve is closed, so it has no start or"
                              " end - use an open curve.")))
              (t (setq crv (car sel)))))))
       (setq tot (cperp:curvelen crv)
             sp  (trans (vlax-curve-getStartPoint crv) 0 1)
             ep  (trans (vlax-curve-getEndPoint crv) 0 1)
             qstep 2))

      ;; --- 2. click to set direction (START/FINISH) and offset side ----
      ;; The side is measured against the direction of travel (START ->
      ;; FINISH), so later rounds -- whose curves are built in travel
      ;; order -- inherit the same side directly.
      ((= qstep 2)
       (setvar "OSMODE" 0)
       (setq click nil)
       (while (null click)
         (initget "Back Undo")
         (setq click (getpoint "\nClick to pick direction / offset side [Back]: "))
         (if lzd:ask (lzd:ask "\nClick to pick direction / offset side [Back]: " click) click)
         (cond
           ((null click)
            (princ "\nA point is required - click one side of the curve."))
           ((cperp:back-kw click)
            (princ "\nStepping back one question.")
            (setq qstep 1))
           (t
            ;; nearest end of the curve to the click = START
            (setq rev (> (distance click sp) (distance click ep)))
            (cond
              ((null (setq tng (cperp:tangent crv click rev)))
               (princ "\nCannot read the curve direction there - click elsewhere.")
               (setq click nil))
              (t
               ;; signed offset of the click from the tangent line at the
               ;; projection of the click onto the curve
               (setq prj (trans (vlax-curve-getClosestPointTo
                                  crv (trans click 1 0))
                                0 1))
               (setq cross (- (* (car tng)  (- (cadr click) (cadr prj)))
                              (* (cadr tng) (- (car click)  (car prj))))
                     fuzz  (max 1e-8 (* tot 1e-6)))
               (if (< (abs cross) fuzz)
                 (progn
                   (princ "\nThat point is on the curve - click clearly to one side.")
                   (setq click nil))
                 (setq qstep 3)))))))
       (if (= qstep 3)
         (progn
           (setq side (if (>= cross 0.0) 1.0 -1.0))
           ;; the red arrow at START, kept until the command finishes so
           ;; the entry order stays clear across repeat rounds -- and so
           ;; the width question can say "the arrowed end" and be
           ;; understood
           (setq arrow   (cperp:arrow crv rev tot)
                 tmpEnts (append arrow tmpEnts)))))

      ;; --- 3. has the overall width changed? ---------------------------
      ;; The width asked about is the distance straight across, end to
      ;; end -- NOT the length of the curve, which on anything bowed runs
      ;; a good deal further than the width it spans, and it is the width
      ;; that gets re-measured.  Making a new one true is a scale about a
      ;; point on the line through the two ends -- the midpoint when the
      ;; change is split evenly, nearer START the more of it goes to
      ;; FINISH -- and the curve keeps its shape: an arc stays that arc,
      ;; scaled.  The drawing is resized too: the offsets and their
      ;; dimensions are measured off this curve, so leaving it at the old
      ;; width would put every base point somewhere the drawing says
      ;; nothing is.  It is all inside the command's undo group, so one U
      ;; puts the width back.
      ((= qstep 3)
       (setq tx   (- (car ep)  (car sp))
             ty   (- (cadr ep) (cadr sp))
             wOld (sqrt (+ (* tx tx) (* ty ty)))
             ;; a plan projection with no width at all has nothing to
             ;; ask about
             wres (if (> wOld 1e-9) (cperp:ask-width "Overall width" wOld T)))
       (cond
         ((eq wres 'CPERP-BACK)
          ;; back to the click - the arrow goes with it, since the click
          ;; is what placed it
          (princ "\nStepping back one question.")
          (foreach e arrow (cperp:kill e))
          (setq arrow nil qstep 2))
         (t
          (if wres
            (progn
              (setq wNew (car wres)
                    ;; START is the end the click chose, whichever end of
                    ;; the curve that is
                    mid  (if rev
                           (cperp:scale-ctr ep sp (cadr wres))
                           (cperp:scale-ctr sp ep (cadr wres)))
                    fac  (/ wNew wOld))
              (if (not (cperp:rescale crv mid fac))
                (progn
                  (princ (strcat "\nThe curve could not be resized - it is most"
                                 " likely on a locked, frozen or switched-off"
                                 " layer.  Free the layer and run CPERPPTS again."))
                  (cperp:finish)
                  (setq stopped T)
                  (exit)))
              ;; re-read: the curve itself is what every round measures along
              (setq tot (cperp:curvelen crv)
                    sp  (trans (vlax-curve-getStartPoint crv) 0 1)
                    ep  (trans (vlax-curve-getEndPoint crv) 0 1))
              (princ (cperp:width-line wOld wNew (cadr wres)))
              ;; START moved, so the arrow is drawn again where it now is
              (foreach e arrow (cperp:kill e))
              (setq arrow   (cperp:arrow crv rev tot)
                    tmpEnts (append arrow tmpEnts))))
          (setq qstep 4))))))

  ;; --- properties to give the offset polylines -------------------------
  (setq srcData  (entget crv)
        srcLayer (cdr (assoc 8 srcData))
        srcColor (cperp:color srcData)
        srcLtype (cond ((cdr (assoc 6 srcData))) ("BYLAYER"))
        srcLw    (cond ((cdr (assoc 370 srcData))) (-1))
        srcLts   (cond ((cdr (assoc 48 srcData))) (1.0)))

  ;; --- 4. the boundary the offsets answer to (optional) ---------------
  ;; Asked after the direction click because the click is what fixes
  ;; which way the offsets run, and a boundary is only a boundary on the
  ;; side they run toward; and after the width question, because the
  ;; resize is already in the drawing by now, which is also why this
  ;; selection offers no Back.  Enter takes None and the command behaves
  ;; exactly as it did before there was one.  A boundary then gets one
  ;; more question -- a limit the offsets stop at, or the line every one
  ;; of them runs out to meet -- and Back there re-opens the selection.
  (setq qstep 1 bnd nil bmode nil bdflt (cperp:boundary-dflt))
  (while (< qstep 3)
    (cond
      ((= qstep 1)
       (setq bnd 'RETRY)
       (while (eq bnd 'RETRY)
         (initget "None")
         ;; ERRNO is STICKY: it holds whatever the last failing call
         ;; left there, so it is cleared right before the pick it is read
         ;; after -- or one earlier miss turned every later Enter into
         ;; "Nothing there".  Wrapped as POINTRENAMER wraps it
         (vl-catch-all-apply 'setvar (list "ERRNO" 0))
         (setq sel (entsel "\nSelect a boundary for the offsets [None] <None>: "))
         (if lzd:ask (lzd:ask "\nSelect a boundary for the offsets [None] <None>: " sel) sel)
         (if lzd:watch (lzd:watch sel) sel)
         (cond
           ;; entsel answers nil for Enter AND for a click that hit nothing.
           ;; ERRNO 7 is what tells them apart, and without asking, a click
           ;; that missed would quietly drop the boundary the drafter was
           ;; reaching for and cap nothing all run.
           ((and (null sel) (= 7 (getvar "ERRNO")))
            (princ "\nNothing there - click the boundary itself, or press Enter for none."))
           ((or (null sel) (= (type sel) 'STR)) (setq bnd nil))
           ((not (cperp:curve-p (car sel)))
            (princ (strcat "\nA " (cdr (assoc 0 (entget (car sel))))
                           " cannot be a boundary - pick a curve, or press"
                           " Enter for none.")))
           ((eq (car sel) crv)
            (princ (strcat "\nThat is the curve being offset from - a run"
                           " cannot be bounded by where it starts.")))
           (t (setq bnd (car sel)))))
       (setq qstep (if bnd 2 3)))
      ((= qstep 2)
       (initget "Limit Meet Back Undo")
       (setq bmode (getkword (strcat "\nDo the offsets stop at the boundary,"
                                     " or run out to meet it?"
                                     " [Limit/Meet/Back] <" bdflt ">: ")))
       (if lzd:ask (lzd:ask (getvar "LASTPROMPT") bmode) bmode)
       (cond
         ((member bmode '("Back" "Undo"))
          (princ "\nStepping back one question.")
          (setq qstep 1))
         (t
          (if (null bmode) (setq bmode bdflt))
          (setq qstep 3))))))
  (if bnd
    (princ (strcat "\nBoundary set: "
                   (if (equal bmode "Meet")
                     "every offset runs out to that "
                     "no offset will cross that ")
                   (cdr (assoc 0 (entget bnd))) ".")))
  ;; bnd is fixed for the rest of the run once this chain settles -- so
  ;; it is turned into the vla-object cperp:capdist and cperp:past-bnd
  ;; measure through right here, ONCE, rather than once per point as
  ;; cperp:capdist used to.  Every reference to bnd below this line
  ;; reads that vla-object; the ename it started as was only ever
  ;; needed for the entget above and the eq/curve-p checks in the
  ;; selection loop, both already behind us.
  (setq bnd (cperp:bnd-obj bnd))

  ;; --- offset rounds --------------------------------------------------
  ;; Every round samples and offsets from the NEWEST curve: the selected
  ;; curve in round 1 (traversed from the clicked end), then the
  ;; arc polyline each round builds.  Later curves are built in travel
  ;; order, so their traversal is never reversed.
  (setq curCrv crv
        curRev rev
        again  "Yes"
        iter   0
        total  0)
  ;; the closing style question's Enter answer, read through the
  ;; canonicaliser so a misspelled override cannot reach the style table
  (setq dsdflt (cperp:dimstyle-dflt))

  (while (equal again "Yes")
    (setq iter (1+ iter) rstep 1)

    ;; The count and the lengths are one chain walked with a step
    ;; counter.  Back at a length re-asks the last length TYPED -- a
    ;; point that ran out to the boundary was never asked, so it is
    ;; taken back on the way past -- and re-asks the count when nothing
    ;; was typed in front of it.
    (while (< rstep 3)
      (cond
        ;; --- how many values / points for this round -------------------
        ((= rstep 1)
         (setq rl (cperp:ruler-off rl))
         (setq n nil)
         (while (null n)
           (initget 6)
           (setq n (getint (strcat "\nRound " (itoa iter)
                                   " - how many values (points) are required?"
                                   (if lastN (strcat " <" (itoa lastN) ">") "")
                                   " ")))
           (if lzd:ask (lzd:ask (getvar "LASTPROMPT") n) n)
           (if (null n) (setq n lastN))
           (cond
             ((null n)
              (princ "\nA number is required."))
             ((< n 2)
              (princ "\nNeed at least 2 points.")
              (setq n nil))
             ((> n 100)
              ;; Back is listed because it is what a hand reaches for here,
              ;; and it means what No means - ask the count again
              (initget "Yes No Back Undo")
              (setq ans (getkword
                          (strcat "\n" (itoa n) " points means " (itoa n)
                                  " dimensions. Continue? [Yes/No/Back] <No>: ")))
              (if lzd:ask (lzd:ask (getvar "LASTPROMPT") ans) ans)
              (if (not (equal ans "Yes")) (setq n nil)))))
         (setq lastN n)

         ;; base points, equally spaced by true arc length along the newest
         ;; curve, START first
         (setq basePts (cperp:curve-pts curCrv n curRev))
         ;; usedBases collects the base of each created point so bases and
         ;; new points stay paired even when a point is skipped; tangs
         ;; holds the travel tangent under each created point (it becomes
         ;; the arc direction of the new polyline there); idxs records each
         ;; created point's position so Back returns to the right prompt
         ;; even across skipped points; askd records which of them were
         ;; ASKED, which is where Back goes.
         (setvar "CLAYER" "PERPPTS-TEMP")
         (setq newPts '() usedBases '() tangs '() idxs '() askd '()
               guideEnts '() i 0 rstep 2))

        ;; --- length per point + build the new perpendicular points -----
        ((= rstep 2)
         (if (>= i n)
           (progn (setq rl (cperp:ruler-off rl)) (setq rstep 3))
           (progn
             (setq base (nth i basePts)
                   tg   (cperp:tangent curCrv base curRev)
                   nrm  (if tg (list (* side (- (cadr tg))) (* side (car tg)))))
             (cond
               ;; no readable tangent under this point - skip it rather than
               ;; place the offset in an arbitrary direction
               ((null nrm)
                (princ (strcat "\nSkipping point " (itoa (1+ i))
                               ": the curve direction cannot be read there."))
                (setq i (1+ i)))
               (t
                ;; How far this point may go before it meets the boundary.
                ;; Measured per point along its own normal: a boundary
                ;; running at an angle to the curve is nearer at one end
                ;; than at the other, and one number could not say where.
                ;; nil when the ray never reaches it, and then nothing
                ;; below changes.
                (setq cap (if bnd (cperp:capdist bnd base nrm)))
                (cond
                  ;; Meet: a boundary ahead IS the length, so nothing is asked
                  ((and cap (equal bmode "Meet"))
                   (setq np (list (+ (car base)  (* cap (car nrm)))
                                  (+ (cadr base) (* cap (cadr nrm)))
                                  (caddr base)))
                   (princ (strcat "\nPoint " (itoa (1+ i)) " of " (itoa n)
                                  " runs out to the boundary: " (rtos cap) "."))
                   (setq newPts    (cons np newPts)
                         usedBases (cons base usedBases)
                         tangs     (cons tg tangs)
                         idxs      (cons i idxs))
                   (command "._POINT" np)
                   (setq guideEnts (cons (entlast) guideEnts)
                         tmpEnts   (cons (entlast) tmpEnts))
                   (setq i (1+ i)))
                  (t
                   ;; Undo kept as a hidden synonym; Max is offered only
                   ;; where there is a boundary ahead of this point to reach
                   (setq rl  (cperp:ruler-show rl lastLen nil)
                         rr  (cperp:ask-len
                               (strcat "\nLength for point " (itoa (1+ i))
                                       " of " (itoa n)
                                       (cond
                                         (cap (strcat ", boundary at " (rtos cap)))
                                         ((equal bmode "Meet") " (no boundary ahead)")
                                         (t ""))
                                       (if lastLen
                                         (strcat " <" (rtos lastLen) ">")
                                         "")
                                       (if cap " [Back/Max]: " " [Back]: "))
                               (if cap "Back Undo Max" "Back Undo")
                               rl nil)
                             len (car rr)
                             rl  (cadr rr))
                   (if (null len) (setq len lastLen))
                   (if (equal len "Max") (setq len cap))
                   ;; The typed number is what Enter repeats, not the capped
                   ;; one: the tape still says what it says, and the next
                   ;; point has its own boundary to meet it against.
                   (if (numberp len) (setq lastLen len))
                   (if (and cap (numberp len) (> len cap))
                     (progn
                       (princ (strcat "\n" (rtos len) " would cross the boundary -"
                                      " point " (itoa (1+ i)) " is capped at "
                                      (rtos cap) "."))
                       (setq len cap)))
                   (cond
                     ;; Back: to the last length typed - or to the count
                     ;; when nothing was typed in front of this point
                     ((eq (type len) 'STR)
                      (cond
                        (askd
                         (setq tgt (car askd) askd (cdr askd))
                         (cperp:unplace tgt)
                         (princ "\nStepping back one point."))
                        (t
                         (cperp:unplace 0)
                         (princ "\nStepping back one question.")
                         (setq rstep 1))))
                     ((null len)
                      (princ "\nA length is required."))
                     (t
                      (setq np (list (+ (car base)  (* len (car nrm)))
                                     (+ (cadr base) (* len (cadr nrm)))
                                     (caddr base)))
                      (setq newPts    (cons np newPts)
                            usedBases (cons base usedBases)
                            tangs     (cons tg tangs)
                            idxs      (cons i idxs)
                            askd      (cons i askd))
                      (command "._POINT" np)
                      (setq guideEnts (cons (entlast) guideEnts)
                            tmpEnts   (cons (entlast) tmpEnts))
                      (setq i (1+ i)))))))))))))
    (setq newPts    (reverse newPts)
          usedBases (reverse usedBases)
          tangs     (reverse tangs))

    ;; --- connect the new points with a polyline ----------------------
    ;; drawn with the source curve's layer and line properties.  If
    ;; skipped points left fewer than 2, there is nothing to join and
    ;; nothing for the next round to follow.
    (if (< (length newPts) 2)
      (progn
        (princ "\nToo few points were placed to build a polyline.")
        (cperp:finish)
        (setq stopped T)
        (exit)))
    (setvar "CLAYER"    srcLayer)
    (setvar "CECOLOR"   srcColor)
    (setvar "CELTYPE"   srcLtype)
    (setvar "CELWEIGHT" srcLw)
    (setvar "CELTSCALE" srcLts)
    (command "._PLINE")
    (foreach p newPts (command p))
    (command "")
    ;; Curve it: every straight segment becomes an arc whose direction
    ;; at its start point matches the source curve's tangent there (an
    ;; offset curve runs parallel to its source, so the tangent carries
    ;; over).  The entity stays a plain LWPOLYLINE -- smooth, passing
    ;; exactly through every offset point, and never a spline.
    (cperp:arcs (entlast) newPts tangs)

    ;; the curve just built becomes the source for the next round; it
    ;; was drawn in travel order, so it is never traversed reversed
    (setq curCrv (entlast)
          curRev nil)

    ;; --- erase this round's point guides -----------------------------
    (foreach e guideEnts (cperp:kill e))
    (setq guideEnts nil)

    ;; --- has the width of the curve just drawn changed? --------------
    ;; Step 3's question, asked again of the curve this round built.  It
    ;; is the next course out and it was re-measured too, and the typed
    ;; offsets only reach the width they happen to add up to: a course
    ;; whose ends were measured a little long or a little short comes
    ;; out that much wide or narrow, and everything taken off it after
    ;; -- this round's dimensions, and the base points of every round
    ;; that follows -- would be measured off a width the wall does not
    ;; have.  So it is resized here, before any of that: the same
    ;; correction, the same split and the same undo group as step 3,
    ;; with the polyline's first point as START (it sits at the arrowed
    ;; end).  Unchanged is the default and the Enter answer, which
    ;; leaves the round exactly as it drew.  No Back: the curve is drawn.
    (setq tx   (- (car  (last newPts)) (car  (car newPts)))
          ty   (- (cadr (last newPts)) (cadr (car newPts)))
          wOld (sqrt (+ (* tx tx) (* ty ty)))
          ;; ends that land on top of each other span no width, so there
          ;; is nothing to ask about and nothing to scale about either
          wres (if (> wOld 1e-9)
                 (cperp:ask-width "Overall width of the new curve" wOld nil)))
    (if wres
      (progn
        (setq wNew (car wres)
              mid  (cperp:scale-ctr (car newPts) (last newPts) (cadr wres))
              fac  (/ wNew wOld))
        ;; A refused resize stops step 3 outright: nothing is drawn yet
        ;; there, so re-running costs one click.  Here rounds of typed
        ;; lengths sit behind it and not one dimension is written, so
        ;; the curve is left at the width it drew and the drafter is
        ;; told which width that is -- nothing is scaled, so the drawing
        ;; and the numbers measured off it still agree.
        (if (cperp:rescale curCrv mid fac)
          (progn
            (setq newPts (cperp:scale-pts newPts mid fac))
            (princ (cperp:width-line wOld wNew (cadr wres)))
            ;; every length was capped, or run out to the boundary, as
            ;; it was placed; this scales the whole curve and can carry
            ;; a point that was sitting ON the boundary out past it, or
            ;; off it.  The correction is the drafter's measurement and
            ;; is not second-guessed -- but a curve that crosses a
            ;; boundary it was told to respect, or leaves one it was
            ;; told to meet, does not go without saying.
            (if bnd
              (progn
                (setq over (if (equal bmode "Meet")
                             (cperp:off-bnd bnd newPts)
                             (cperp:past-bnd bnd usedBases newPts)))
                (if (> over 0)
                  (princ (strcat "\n" (itoa over) " of " (itoa (length newPts))
                                 (if (equal bmode "Meet")
                                   (strcat " points no longer sit on the"
                                           " boundary - the width correction"
                                           " moved the curve off it.")
                                   (strcat " points now sit past the"
                                           " boundary - the width correction"
                                           " carried the curve beyond it."))))))))
          (princ (strcat "\nThe new curve could not be resized - it is"
                         " most likely on a locked, frozen or switched-off"
                         " layer.  It is left at the " (rtos wOld)
                         " it was drawn, and the dimensions follow it.")))))

    ;; --- remember the dimensions to draw -----------------------------
    ;; each pair runs along the normal of the curve the base point sits
    ;; on, so the dimension reads perpendicular to that curve -- until a
    ;; width correction above moves the new points along the curve they
    ;; landed on, and then each dimension reads the distance the
    ;; corrected drawing really has
    (setq i 0)
    (while (< i (length newPts))
      (setq dimPairs (cons (list (nth i usedBases) (nth i newPts)) dimPairs)
            i        (1+ i)))
    (setq total (+ total (length newPts)))

    ;; --- repeat?, and when not, the dimension style ------------------
    ;; the two are one chain: Back at the style re-asks whether to
    ;; repeat, which is the question in front of it
    (setq again 'RETRY)
    (while (eq again 'RETRY)
      (initget "Yes No")
      (setq again (getkword "\nRepeat on the new polyline? [Yes/No] <No>: "))
      (if lzd:ask (lzd:ask "\nRepeat on the new polyline? [Yes/No] <No>: " again) again)
      (if (null again) (setq again "No"))
      (if (equal again "No")
        (progn
          (initget "STandard SIde Back Undo")
          (setq ans (getkword (strcat "\nDimension style - STANDARD INCHES or "
                                      "SIDE STANDARD? [STandard/SIde/Back] <"
                                      dsdflt ">: ")))
          (if lzd:ask (lzd:ask (getvar "LASTPROMPT") ans) ans)
          (if (null ans) (setq ans dsdflt))  ; Enter = the knob's word
          (if (member ans '("Back" "Undo"))
            (progn (princ "\nStepping back one question.")
                   (setq again 'RETRY)))))))

  ;; --- 9. draw every dimension in the chosen style --------------------
  (setq dimStyle (if (equal ans "SIde") "SIDE STANDARD" "STANDARD INCHES"))
  (if (tblsearch "DIMSTYLE" dimStyle)
    (command "._-DIMSTYLE" "_Restore" dimStyle)
    (princ (strcat "\nDimension style \"" dimStyle
                   "\" is not in this drawing - using the current style \""
                   cdim "\" instead.")))

  (setvar "CLAYER" cperp:*dimlayer*)
  (foreach pr (reverse dimPairs)
    (command "._DIMALIGNED" (car pr) (cadr pr) (cadr pr)))

  ;; --- restore everything and close the undo group --------------------
  (cperp:finish)
  (princ (strcat "\nDone: " (itoa iter) " round(s), "
                 (itoa total) " points, "
                 (itoa iter) " polyline(s) on layer \"" srcLayer "\" and "
                 (itoa total) " dimensions on layer \"" cperp:*dimlayer* "\"."))
  (if lzd:end (lzd:end "CPERPPTS"))
  (princ))

;;; -------------------- self tests --------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun cperp:selftests ()
  (list
    (list "kw-canon spells side as the style table wants"
          '(cperp:kw-canon "side" '("STandard" "SIde"))  "SIde")
    (list "kw-canon refuses a word the question never offers"
          '(cperp:kw-canon "Maybe" '("Yes" "No"))  nil)
    (list "dimstyle-dflt is always one of the two keywords"
          '(member (cperp:dimstyle-dflt) '("STandard" "SIde")))
    (list "back-kw knows Undo as well as Back"  '(cperp:back-kw "Undo"))
    (list "bulge of a 45 degree turn is tan(pi/8)"
          '(cperp:bulge '(1 0) '(0 0) '(1 1))  (/ (sin (/ pi 8.0)) (cos (/ pi 8.0))))
    (list "bulge of a chord along the tangent is 0"
          '(cperp:bulge '(1 0) '(0 0) '(5 0))  0.0)
    (list "scale-pt doubles about the centre, z untouched"
          '(cperp:scale-pt '(3 4 7) '(1 2 0) 2.0)  '(5.0 6.0 7))
    (list "scale-ctr lands a quarter of the way from START"
          '(cperp:scale-ctr '(0 0 5) '(10 20 9) 0.25)  '(2.5 5.0 5))
    (list "parse-len reads feet, dash and a dashed fraction"
          '(cperp:parse-len "4'-4-1/2\"")  '(52.5 T))
    (list "parse-len reads a spaced fraction as inches"
          '(cperp:parse-len "44 1/2")  '(44.5 nil))
    (list "spell-len writes 356 eighths in feet"
          '(cperp:spell-len 356 T nil)  "3'-8 1/2\"")
    (list "ladder-rows grades 3 to 12 by 3 off the value"
          '(cperp:ladder-rows '(3 12 3))
          '((96 jump) (72 quarter) (48 half) (24 quarter)))))

(foreach c '("CPERPPTS")
  (setq *calofin-selftests*
        (cons (cons c 'cperp:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\ncperp_points.lsp " *cperp-version*
                 " loaded.  Type CPERPPTS to run.")))
(princ)
