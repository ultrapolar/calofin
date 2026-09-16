;;; ======================================================================
;;; CLEARDIM.lsp  --  slide dimension text along its own dimension until
;;;                    it is readable, and leave the readable ones where
;;;                    they are
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  CLEARDIM       clear the dimension text that is hard to read
;;;            CLEARDIMSCAN   the same pass, read-only: report, move nothing
;;;            CLEARDIMVER    print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; Every dimension's text has ONE TRACK, and it is made of the dimension
;;; itself:
;;;
;;;   linear and aligned    the dimension line, a straight run
;;;   angular               the dimension ARC, about the angle's vertex
;;;   radius and diameter   the radial line it is measured along
;;;   ordinate              the leader, along the axis it reads
;;;
;;; Sliding the text along that track is free -- it still reads as the
;;; same dimension, the extension lines still say what was measured, and
;;; nothing about the drawing changes.  Lifting it OFF the track is not
;;; free: the text stops sitting on the thing it measures and AutoCAD
;;; starts drawing a leader to explain where it went.  So CLEARDIM only
;;; ever slides ALONG, never across.  What that means is different for
;;; each shape of track and the same in substance: a linear text keeps
;;; its offset above the dimension line to the last decimal, an angular
;;; one keeps the RADIUS it rides at, and both come out of the run on the
;;; track they went in on.
;;;
;;; The track's parameter is a DISTANCE in every case, an arc length
;;; round an arc rather than an angle.  That is what lets cd:*step-f*
;;; and cd:*reach-f* mean the same thing on a dimension arc as on a
;;; straight dimension line instead of needing a second pair of knobs
;;; kept in step with the first.
;;;
;;; What counts as hard to read is anything under the text:
;;;
;;;   * another dimension's text sitting on top of it;
;;;   * any other drawing ink -- lines, polyline edges, arcs, circles,
;;;     TEXT, MTEXT -- crossing the letters;
;;;   * the dimension lines, arcs, radial lines and leaders of the OTHER
;;;     dimensions in the sweep, which are ink like any other;
;;;   * this dimension's OWN extension lines, which cross its track at
;;;     right angles and are the thing text slid too far ends up on.
;;;
;;; The one thing that is not an obstacle is the piece of itself the text
;;; RIDES -- its own dimension line, its own arc.  AutoCAD breaks that
;;; around the text, which is what a dimension is.
;;;
;;; A LINE OF DIMENSIONS IS ONE DIMENSION.  Where several dimensions'
;;; lines are the same straight line -- what AutoCAD's DIMCONTINUE lays
;;; down by the handful and AUTODIM lays whole perimeters out as -- they
;;; are a RUN: one continuous dimension with breaks in it.  Three things
;;; follow, and all three are what a drafter would do:
;;;
;;;   * A run's text stays in its OWN segment.  AutoCAD centres each
;;;     text between its own extension lines, and one shuffled past them
;;;     reads as the dimension for the span next door.  So a run member
;;;     has less room along the track than a lone dimension, not more.
;;;   * A run's own skeleton is its OWN.  Its dimension line and its
;;;     extension lines are one dimension's, not several -- a continued
;;;     chain does not merely have extension lines near each other, it
;;;     SHARES them -- so a member's text never has to clear them.
;;;   * When one member has to stand further off the work, THEY ALL GO.
;;;     Moving one dimension off a wall and leaving its neighbours
;;;     behind trades a crowded dimension for a crooked run.
;;;
;;; And when a run's own members are what crowd each other -- four
;;; segments thirty wide with text forty wide, where there is nowhere
;;; along the track to go because every text overhangs its own segment
;;; whatever it does -- the run is STAGGERED: every other dimension
;;; stands a row further off the work, its own dimension line with it,
;;; and every text stays centred where it belongs.  Which of the two it
;;; is gets decided by WHO is in the way: run-mates alone means stagger,
;;; anything else means the whole run goes.
;;;
;;; A row is cd:*row-f* text heights, the unit AUTODIM already stands
;;; its own chains off the work in.
;;;
;;; THE ONE THAT IS ALREADY GOOD DOES NOT MOVE.  That is the whole
;;; policy for everything else, and it decides who gives way when two
;;; texts want one spot:
;;;
;;;   1. Text that CANNOT move goes down first and keeps its spot --
;;;      a dimension on a locked layer, a dimension with no text, and
;;;      one whose track cannot be read off it (below).
;;;   2. Then the text that is clear of every fixed thing in the
;;;      drawing.  It has earned its spot, so it keeps it.
;;;   3. Only then the text that is on top of something.  It is routed
;;;      around everything already placed.
;;;
;;; Inside each of those three the order is reading order -- row by row
;;; down the sheet, left to right along each row -- so two texts that
;;; are each clear of the drawing but not of each other resolve the same
;;; way every run: the first one read keeps its spot and the second
;;; slides.  Nothing is moved that did not have to be.
;;;
;;; A text that has to move goes first to the NEAREST clear spot on its track,
;;; found by stepping outward from where it sits and then bisecting back
;;; toward it, so the move is the smallest one that works.  The two
;;; directions are not equal: the one that takes the text back toward
;;; where its family says it belongs is tried first -- the middle of the
;;; dimension line, the middle of the arc's sweep, the circle a radius
;;; measures to, and for an ordinate simply further out, because a
;;; leader is made longer to get its text clear and never shorter back
;;; onto the work.  A text with nowhere clear within reach
;;; (cd:*reach-f*) is LEFT WHERE IT WAS and named in the report -- a text
;;; parked somewhere arbitrary is worse than a text still sitting on a
;;; line, because the drafter can see the second one.
;;;
;;; What it will not touch, and says so rather than guessing:
;;;
;;;   * a dimension whose TRACK CANNOT BE READ off it.  A 2-line angular
;;;     dimension keeps no vertex: it is where the two measured lines
;;;     cross, and parallel lines cross nowhere.  An ordinate with no
;;;     leader end has no axis to run along.  And the vertex an angular
;;;     dimension does yield is checked before it is trusted -- the
;;;     sweep between its two rays IS the angle it measures, so a vertex
;;;     group 42 disagrees with is refused.  A track guessed wrong does
;;;     not move text along the dimension, it moves it OFF it, which is
;;;     the one thing this tool exists not to do.
;;;   * a dimension on a LOCKED layer.  entmod would be refused, and a
;;;     run that silently skipped it would claim a sheet was cleared
;;;     when it was not.
;;;   * a dimension whose text is suppressed (DIMENSION group 1 is a
;;;     single space).  There is no text to be hard to read.
;;;
;;; Each of those is still ink everything else has to clear.
;;;
;;; The ordinate is the one family whose text does not travel alone: its
;;; leader ends where the text is, so group 14 moves the same step and
;;; the feature point never moves.  Writing group 11 by itself would
;;; leave the text off the end of its own leader.
;;;
;;; The whole run is one UNDO group, so a single U puts every text back.
;;; CLEARDIMSCAN is the same analysis with the entmod left out: it says
;;; what CLEARDIM would do and changes nothing.
;;;
;;; HOW THE TEXT BOX IS MEASURED, which is the part that decides
;;; whether this tool does anything at all.  A DIMENSION's letters live
;;; in its anonymous block, which is regenerated whenever anything about
;;; the dimension changes, so the box is computed from the dimension
;;; itself instead.  Group 11 is the middle of the text.  The rest:
;;;
;;;   HEIGHT.  A text style with a FIXED height wins outright -- the
;;;   dimension style points at one through DIMTXSTY (group 340), and
;;;   where that style's height is non-zero it is the height, with
;;;   DIMTXT ignored and DIMSCALE not applied.  Only a variable-height
;;;   style leaves DIMTXT times DIMSCALE in charge (the dimension's own
;;;   xdata overrides laid over both).  This is where v2.0 was wrong and
;;;   the whole tool with it: a dimension style is entitled to leave
;;;   DIMTXT at its 0.18 DXF default and keep the real height on its
;;;   text style, every style in the drawing that found this did, and a
;;;   6-unit text measuring 0.18 made every box a speck.  Nothing
;;;   overlapped anything; a sheet with two cross dims printing on top
;;;   of each other in the middle came back "6 already clear".
;;;
;;;   WIDTH.  The glyph count at cd:*charwidth* of the height, times the
;;;   text style's own width factor.  The count is what the text DRAWS,
;;;   not what it is spelled with: "%%d" is one glyph of three
;;;   characters, MTEXT markup ("\A1;", "{Arial|b1|i0|c0|p34;...}",
;;;   "\H0.85x;") is none at all, and a stacked "\S1/2;" is as wide as
;;;   its longer half.  Counting markup as letters is not erring on the
;;;   safe side -- it fills a sheet with obstacles that are not there.
;;;   cd:*charwidth* itself is the one ESTIMATE left, because a stroke
;;;   font's glyphs are not all one width; raise it and every box gets
;;;   wider and the tool more cautious.
;;;
;;;   WHAT IT SAYS.  A measurement is spelled with the dimension
;;;   STYLE's own DIMLUNIT and DIMDEC, not the drawing's LUNITS and
;;;   LUPREC.  The difference is half the width: 33'-3" against
;;;   33'-2 15/16".
;;;
;;; On an arc the box TURNS as it slides, because text set along a
;;; dimension arc turns with it unless the style holds it upright.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root.  It reads
;;; *cleardim-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;; ======================================================================

;;; -------------------- version ---------------------------------------
(setq *cleardim-version* "v3.1")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

;;; -------------------- tunables --------------------------------------
;;; Everything about this run somebody might reasonably want different.
;;; Each is read when the command runs, not when the file loads, so a
;;; setq typed at the command line changes the next run.

(setq cd:*charwidth* 0.75)         ; how wide one glyph is taken to be,
                                   ; as a fraction of the text height.
                                   ; The one estimate in the file:
                                   ; raise it and every text box gets
                                   ; wider, so more texts are called
                                   ; hard to read and the ones that
                                   ; move end up further clear

(setq cd:*gap-f* 0.4)              ; breathing room left around a text
                                   ; box on every side, as a multiple
                                   ; of the text height.  0.0 asks only
                                   ; that the ink not actually cross
                                   ; the letters, which is not the same
                                   ; as readable

(setq cd:*step-f* 0.25)            ; how far each trial slide steps, as
                                   ; a multiple of the text height.
                                   ; Smaller finds narrower gaps and
                                   ; takes proportionally longer

(setq cd:*reach-f* 4.0)            ; how far a text may slide from where
                                   ; it started, each way, as a multiple
                                   ; of its own width.  A text with
                                   ; nothing clear inside this is left
                                   ; alone and reported, not parked

(setq cd:*refine* 5)               ; halvings used to bisect the found
                                   ; spot back toward the original one,
                                   ; so the move is the smallest that
                                   ; still clears.  0 leaves the moves on
                                   ; whole cd:*step-f* boundaries

(setq cd:*rowtol-f* 2.0)           ; how tall a "row" is for reading
                                   ; order, as a multiple of the tallest
                                   ; text in the sweep.  Two dimensions
                                   ; inside one row are ordered left to
                                   ; right instead of by height

(setq cd:*track-tol-f* 0.5)        ; how far apart two dimension lines
                                   ; may be across their own direction
                                   ; and still be the SAME track, as a
                                   ; multiple of the text height.  A
                                   ; chain AutoCAD continued is exact;
                                   ; this is for one somebody nudged

(setq cd:*run-gap-f* 6.0)          ; how big a break may be between two
                                   ; dimensions on one line before they
                                   ; stop reading as one run, as a
                                   ; multiple of the text height.  A run
                                   ; is one continuous dimension WITH
                                   ; breaks; raise this and dimensions at
                                   ; opposite ends of a sheet start
                                   ; moving each other

(setq cd:*row-f* 2.0)              ; how far one row out is, as a
                                   ; multiple of the text height -- the
                                   ; unit AUTODIM already stands its own
                                   ; chains off the work in
                                   ; (ad:*text-offsets*)

(setq cd:*rows* 3)                 ; how many rows out a run or a
                                   ; staggered dimension may be pushed
                                   ; before the run is left as drawn.  A
                                   ; dimension four rows from the thing
                                   ; it measures has stopped belonging
                                   ; to it

(setq cd:*stagger-max* 3)          ; how many rows a run may be
                                   ; staggered ACROSS: 2 is every other
                                   ; dimension a row out, 3 goes out,
                                   ; further out, and back

(setq cd:*stagger* T)              ; whether dimensions on one track that
                                   ; crowd each other may be STAGGERED --
                                   ; the one in the way pushed out a row
                                   ; on its own, which is what a drafter
                                   ; does to a run of short dimensions.
                                   ; nil keeps every run dead straight
                                   ; and leaves the crowding reported

(setq cd:*arcsegs* 32)             ; chords a full circle is flattened
                                   ; into before it is tested against a
                                   ; text box; an arc gets its share of
                                   ; them.  More is a closer curve and a
                                   ; slower run

(setq cd:*skip-layers* '("DEFPOINTS"))  ; layers whose entities are not
                                   ; ink: nothing on them is treated as
                                   ; an obstacle.  DEFPOINTS does not
                                   ; plot, so text over it is readable

(setq cd:*obstacle-types*          ; entity types read as ink under the
  '("LINE" "LWPOLYLINE" "POLYLINE" "ARC" "CIRCLE" "TEXT" "MTEXT"))
                                   ; text.  DIMENSION is handled on its
                                   ; own and is not listed here.  An
                                   ; INSERT is deliberately absent: a
                                   ; block's bounding box is mostly
                                   ; empty space, so counting it as ink
                                   ; would move texts that read fine

(setq cd:*dimtxt-default* 0.18)    ; DIMTXT to assume when the style
                                   ; record carries none -- AutoCAD's
                                   ; own out-of-the-box value

;;; -------------------- 2-D vector helpers -----------------------------
;;; The set itself is CALOFIN-LIB.lsp's, under cal:.  What is left
;;; here is the one that is about a dimension rather than a vector.

;;; -------------------- the track --------------------------------------
;;; What a text may slide along, and there are two shapes of it:
;;;
;;;   ('line BASE U OFF)        the point at s is BASE + s*U + OFF
;;;   ('arc  CENTRE RAD ROT)    the point at s is CENTRE at radius RAD,
;;;                             s being an ARC LENGTH round it
;;;
;;; s is a DISTANCE in both, never an angle.  That is the whole reason
;;; the arc is parameterised by arc length: cd:*step-f* and
;;; cd:*reach-f* are lengths, and they go on meaning the same thing on
;;; a dimension arc as on a straight dimension line without a second
;;; pair of knobs to keep in step with the first.
;;;
;;; OFF is the across-the-track offset a straight track preserves; RAD
;;; is the same invariant on an arc -- the radius the text rides at,
;;; which an angular dimension's text keeps exactly as a linear one
;;; keeps its distance above the dimension line.  ROT says whether the
;;; text turns with the arc as it goes round, which it does unless the
;;; style holds it upright.

(defun cd:trk-line (base u off) (list 'line base u off))
(defun cd:trk-arc (centre rad rot) (list 'arc centre rad rot))
(defun cd:trk-arc-p (trk) (eq (car trk) 'arc))
(defun cd:trk-base (trk) (cadr trk))     ; the base point, or the centre

;; Where TRK is at S.
(defun cd:trk-pt (trk s)
  (if (cd:trk-arc-p trk)
    (polar (cadr trk) (/ s (caddr trk)) (caddr trk))
    (cal:v+ (cal:v+ (cadr trk) (cal:v* (caddr trk) s)) (cadddr trk))))

;; The parameter of the point P on TRK.  On an arc this is only right
;; up to a whole turn -- the seam at angle zero is real -- so a caller
;; comparing it against another parameter goes through cd:trk-near.
(defun cd:trk-s (trk p)
  (if (cd:trk-arc-p trk)
    (* (caddr trk) (angle (cadr trk) p))
    (cal:dot (cal:v- p (cadr trk)) (caddr trk))))

;; S expressed near S0, the short way round: an arc's parameter wraps,
;; and "is the text before or after this spot" has to be asked about
;; the short way or a text just past the seam answers backwards.
(defun cd:trk-near (trk s s0)
  (if (cd:trk-arc-p trk)
    (+ s0 (* (caddr trk)
             (cal:signed-dang (/ s0 (caddr trk)) (/ s (caddr trk)))))
    s))

;; The text's own angle at S, given that it was ANG at S0.  On an arc
;; that turns with it, the text keeps the angle it held to the tangent.
(defun cd:trk-ang (trk s s0 ang)
  (if (and (cd:trk-arc-p trk) (cadddr trk))
    (+ ang (/ (- s s0) (caddr trk)))
    ang))

;; REACH, capped at half a turn on an arc: further than that and the
;; search is coming back round the other side to spots it has already
;; tried, which is time spent to no purpose.
(defun cd:trk-reach (trk reach)
  (if (cd:trk-arc-p trk) (min reach (* pi (caddr trk))) reach))

;;; -------------------- convex polygons and the clash test -------------
;;; Everything in the drawing is reduced to one of two shapes: a SEGMENT
;;; (two points) or a BOX (four).  Both are convex polygons, so one
;;; separating-axis test covers every pair -- box against segment, box
;;; against box -- and there is no second overlap routine to disagree
;;; with the first.

;; The four corners of a rectangle CENTRED on C, turned by ANG, W wide
;; along that angle and H tall across it.  Counterclockwise from the
;; bottom-left, which is the order the axis walk below assumes.
(defun cd:box (c ang w h / u v hu hv)
  (setq u  (list (cos ang) (sin ang))
        v  (cal:perp u)
        hu (cal:v* u (* 0.5 w))
        hv (cal:v* v (* 0.5 h))
        c  (cal:2d c))
  (list (cal:v- (cal:v- c hu) hv)
        (cal:v- (cal:v+ c hu) hv)
        (cal:v+ (cal:v+ c hu) hv)
        (cal:v+ (cal:v- c hu) hv)))

;; (minx miny maxx maxy) around POLY -- the cheap reject that runs
;; before the axis walk.  A drawing is mostly entities nowhere near the
;; text being placed, and this is what stops the expensive test being
;; run on all of them.
(defun cd:aabb (poly / xs ys)
  (setq xs (mapcar 'car poly)
        ys (mapcar 'cadr poly))
  (list (apply 'min xs) (apply 'min ys)
        (apply 'max xs) (apply 'max ys)))

;; Do two (minx miny maxx maxy) boxes share any area at all?
(defun cd:aabb-hit-p (a b)
  (not (or (< (caddr a) (car b)) (< (caddr b) (car a))
           (< (cadddr a) (cadr b)) (< (cadddr b) (cadr a)))))

;; (lo hi), POLY projected onto the direction AX.
(defun cd:span (poly ax / lo hi d q)
  (foreach q poly
    (setq d (cal:dot q ax))
    (if (or (null lo) (< d lo)) (setq lo d))
    (if (or (null hi) (> d hi)) (setq hi d)))
  (list lo hi))

;; The outward normals of POLY's edges, zero-length ones dropped.  A
;; two-point polygon -- a segment -- yields the single normal that its
;; own direction gives, which is exactly the third axis a segment
;; against a box needs.
(defun cd:axes (poly / out n i a b ax)
  (setq n (length poly) i 0 out nil)
  (while (< i n)
    (setq a  (nth i poly)
          b  (nth (rem (1+ i) n) poly)
          ax (cal:unit (cal:perp (cal:v- b a))))
    (if ax (setq out (cons ax out)))
    (setq i (1+ i)))
  out)

;; Do two convex polygons overlap?  Separating-axis: they do NOT if any
;; one edge normal of either sees their projections fall apart.  Touching
;; exactly -- one span ending where the other begins -- is not an
;; overlap, which is what lets a box sit flush against a line it has
;; just cleared.
(defun cd:hit-p (pa pb / axes apart sa sb ax)
  (setq axes  (append (cd:axes pa) (cd:axes pb))
        apart nil)
  (while (and axes (not apart))
    (setq ax   (car axes)
          axes (cdr axes)
          sa   (cd:span pa ax)
          sb   (cd:span pb ax))
    (if (or (<= (cadr sa) (car sb)) (<= (cadr sb) (car sa)))
      (setq apart T)))
  (not apart))

;;; -------------------- obstacles --------------------------------------
;;; An OBSTACLE is (TAG AABB POLY).  TAG says who does NOT have to clear
;;; it: a record index for one dimension's own text box, a LIST of them
;;; for ink a whole run shares, nil for the drawing's own ink, which
;;; everybody clears.
;;;
;;; A dimension never has to clear its own dimension line -- AutoCAD
;;; breaks that around the text, which is what a dimension is -- and a
;;; RUN never has to clear its run's.  A run is one continuous dimension
;;; with breaks in it, so its line is one line, and when the run is
;;; staggered a neighbour's step of that line passing behind a text is
;;; not crowding: it is what a staggered run looks like.  While the run
;;; is straight the rule changes nothing at all, because every member's
;;; line IS its own line.

(defun cd:ob (tag poly) (list tag (cd:aabb poly) poly))

;; Is this obstacle OWNER's own, and so not in its way?
(defun cd:ob-mine-p (tag owner)
  (and owner tag
       (if (listp tag) (member owner tag) (equal tag owner))))

;; The OWNER TAGS of everything in OBS that POLY runs into -- an index
;; for another dimension's own ink, nil for the drawing's.  Whether a
;; text is in the way is one question and WHOSE way it is in is another,
;; and the second is what decides between staggering one dimension and
;; moving a whole run: a dimension crowded only by its own run-mates is
;; a run that needs staggering, and one crowded by anything else is a
;; run that needs to stand further off the work.
(defun cd:hit-owners (poly obs owner / bb out o)
  (setq bb (cd:aabb poly) out nil)
  (foreach o obs
    (if (and (not (cd:ob-mine-p (car o) owner))
             (cd:aabb-hit-p bb (cadr o))
             (cd:hit-p poly (caddr o))
             (not (member (car o) out)))
      (setq out (cons (car o) out))))
  out)

;; Every obstacle in OBS that is not OWNER's own and does overlap POLY.
;; Returns T on the first hit: nothing downstream wants the list.
(defun cd:hits-p (poly obs owner / bb hit o)
  (setq bb (cd:aabb poly) hit nil)
  (while (and obs (not hit))
    (setq o   (car obs)
          obs (cdr obs))
    (if (and (not (cd:ob-mine-p (car o) owner))
             (cd:aabb-hit-p bb (cadr o))
             (cd:hit-p poly (caddr o)))
      (setq hit T)))
  hit)

;;; -------------------- text as a rectangle ----------------------------

;; The index of the ";" that ends an MTEXT code starting at FROM, or
;; one past the end of the string when the code never closes.
(defun cd:find-semi (s from / n i hit)
  (setq n (strlen s) i from hit nil)
  (while (and (<= i n) (not hit))
    (if (= (substr s i 1) ";") (setq hit i) (setq i (1+ i))))
  (if hit hit (1+ n)))

;; The MTEXT codes that carry an argument up to a semicolon, none of
;; which draws anything.  \P (the hard break), \~ (a hard space) and the
;; \L \O \K toggles take no argument and are NOT in here -- scanning one
;; of them for a semicolon would swallow the rest of the line.  \S is
;; not here either: its argument is the fraction, and the fraction is
;; drawn.
(defun cd:arg-code-p (c)
  (member c '("A" "C" "c" "f" "F" "H" "Q" "T" "W" "p")))

;; How wide a stacked fraction draws: the longer of its two halves.  A
;; stack is two half-height lines one above the other, so "1/2" is one
;; glyph wide and not three.
(defun cd:stack-width (body / i n c a b seen)
  (setq n (strlen body) i 1 a 0 b 0 seen nil)
  (while (<= i n)
    (setq c (substr body i 1))
    (if (and (not seen) (member c '("/" "^" "#")))
      (setq seen T)
      (if seen (setq b (1+ b)) (setq a (1+ a))))
    (setq i (1+ i)))
  (if seen (max a b) a))

;; The glyph count of S: the printable characters it would draw.
;;
;; Two families of code get in the way of counting characters, and both
;; are the ordinary content of a shop drawing rather than exotica:
;;
;;   * "%%d", "%%c", "%%p" and "%%%" are one glyph written as three
;;     characters, and "%%o" / "%%u" are toggles that draw nothing;
;;   * MTEXT formatting -- "\A1;", "{\fArial|b1|i0|c0|p34;...}",
;;     "\H0.85x;", "\S1/2;" -- is markup, and counting it as letters is
;;     what made "\A1;2{\H1.000000x;\S3/4;}" measure twenty-six glyphs
;;     wide instead of about four.  A hundred and fifty of the hundred
;;     and fifty-two MTEXTs in the drawing this was written against
;;     carry some, so over-measuring here does not err on the safe side
;;     -- it fills the sheet with obstacles that are not there and
;;     leaves every dimension with nowhere clear to go.
(defun cd:glyphs (s / i n c nx n2 j out)
  (setq n (strlen s) i 1 out 0)
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ;; MTEXT grouping braces draw nothing
      ((member c '("{" "}")) (setq i (1+ i)))
      ((= c "\\")
       (setq nx (substr s (1+ i) 1))
       (cond
         ((= nx "") (setq out (1+ out) i (1+ i)))     ; a trailing backslash
         ;; an escaped literal: one glyph out of two characters
         ((member nx '("\\" "{" "}")) (setq out (1+ out) i (+ i 2)))
         ;; the stacked fraction, whose argument IS drawn
         ((= nx "S")
          (setq j   (cd:find-semi s (+ i 2))
                out (+ out (cd:stack-width (substr s (+ i 2) (- j i 2))))
                i   (1+ j)))
         ;; a code with an argument: none of it is drawn
         ((cd:arg-code-p nx) (setq i (1+ (cd:find-semi s (+ i 2)))))
         ((= nx "~") (setq out (1+ out) i (+ i 2)))   ; a hard space
         (T (setq i (+ i 2)))))                       ; \L \O \K and kin
      ((and (= c "%") (<= (+ i 2) n) (= (substr s (1+ i) 1) "%"))
       (setq n2 (strcase (substr s (+ i 2) 1)))
       (cond
         ;; %%o and %%u are overscore/underscore toggles: three
         ;; characters, no glyph at all
         ((member n2 '("O" "U")) (setq i (+ i 3)))
         ;; the rest of the codes draw one glyph for their three
         ((member n2 '("D" "C" "P" "%")) (setq out (1+ out) i (+ i 3)))
         ;; "%%" in front of anything else is two ordinary per-cent
         ;; signs, which is what the first of them is counted as here
         (T (setq out (1+ out) i (1+ i)))))
      (T (setq out (1+ out) i (1+ i)))))
  out)

;; S split on MTEXT's "\P" hard line break, as a list of strings.  A
;; string with no break is a one-element list, which is what keeps the
;; two cases one code path.
(defun cd:lines (s / out i)
  (setq out nil)
  (while (setq i (vl-string-search "\\P" s))
    (setq out (cons (substr s 1 i) out)
          s   (substr s (+ i 3))))
  (reverse (cons s out)))

;; (W H) for the string S set at height HGT with width factor WF -- the
;; widest of its lines by cd:*charwidth*, and a height that grows by
;; half a line for each line after the first, the way stacked dimension
;; text does.
(defun cd:text-size (s hgt wf / ls n w l)
  (setq ls (cd:lines s)
        n  (length ls)
        w  0.0)
  (foreach l ls
    (setq w (max w (* (cd:glyphs l) hgt cd:*charwidth* wf))))
  (list w (* hgt (- (* 1.5 n) 0.5))))

;; The box for a string whose rectangle is W by H, anchored at ANCHOR
;; with justification (DX DY) -- the offsets from the anchor to the
;; rectangle's lower-left corner -- and turned by ANG about the anchor.
(defun cd:just-box (anchor ang w h dx dy / u v c)
  (setq u (list (cos ang) (sin ang))
        v (cal:perp u)
        c (cal:v+ (cal:2d anchor)
                 (cal:v+ (cal:v* u (+ dx (* 0.5 w)))
                        (cal:v* v (+ dy (* 0.5 h))))))
  (cd:box c ang w h))

;; POLY grown by PAD on every side -- how cd:*gap-f* turns "the ink does
;; not cross the letters" into "the letters are readable".  The box is
;; rebuilt rather than offset edge by edge, which only works because
;; every box here is a rectangle and is always built by cd:box.
(defun cd:grow (c ang w h pad)
  (cd:box c ang (+ w (* 2.0 pad)) (+ h (* 2.0 pad))))

;;; -------------------- reading the drawing ----------------------------

(defun cd:dxf (code ed) (cdr (assoc code ed)))

;; CODE's value off ED, or DFLT when the group is absent or is not a
;; number.  Half the DXF groups read here are optional and AutoCAD omits
;; the ones sitting at their default, so this is the common case, not
;; the defensive one.
(defun cd:num (code ed dflt / v)
  (setq v (cd:dxf code ed))
  (if (numberp v) v dflt))

;; A dimension's own override of dimension variable VAR, out of its
;; xdata: an "ACAD" application list, a (1000 . "DSTYLE") marker, then
;; (1070 . var) / value pairs between braces.  nil when the dimension
;; overrides nothing, which is the usual answer.
(defun cd:override (ed var / xd app rest found on out v k)
  (setq xd (cdr (assoc -3 ed)))
  (foreach app xd
    (if (= (strcase (car app)) "ACAD")
      (progn
        ;; the name is the head of the list and every element after it
        ;; is a group pair, so (car v) below is always a group code --
        ;; which is the test, because a dotted pair is a list to
        ;; AutoLISP and there is nothing else in here to tell it from
        (setq rest  (cdr app)
              found nil
              on    nil)
        (foreach v rest
          (setq k (car v))
          (cond
            ((and (= k 1000) (= (strcase (cdr v)) "DSTYLE")) (setq on T))
            ((not on) nil)
            ((= k 1002) (if (= (cdr v) "}") (setq on nil found nil)))
            ;; a code, then whatever group carries its value
            ((and found (member k '(1040 1070)))
             (setq out (cdr v) found nil))
            ((and (= k 1070) (= (cdr v) var)) (setq found T))
            (T (setq found nil)))))))
  out)

;; The effective text height of the dimension whose entity list is ED
;; and whose style record is STY: DIMTXT times DIMSCALE, with the
;; dimension's own overrides laid over both.  A DIMSCALE of 0 is
;; annotative -- scaled by the viewport, which is not a thing this file
;; can measure -- so the drawing's current DIMSCALE stands in.
;; The record of the text STYLE a dimension is written in.  The
;; dimension style keeps it as DIMTXSTY, group 340, which is a POINTER
;; and not a name -- AutoLISP hands it back as an ename, and a raw
;; handle string is looked up rather than assumed to be one.  nil when
;; the style keeps none, which is what makes every caller fall back on
;; DIMTXT.
(defun cd:txtstyle (sty / v r)
  (setq v (cd:dxf 340 sty))
  (if (= (type v) 'STR) (setq v (handent v)))
  (if (= (type v) 'ENAME)
    (progn
      (setq r (vl-catch-all-apply 'entget (list v)))
      (if (vl-catch-all-error-p r) nil r))))

;; How much wider than tall this dimension's glyphs are set -- the text
;; style's own width factor, on top of cd:*charwidth*.
(defun cd:txt-wfactor (sty / f)
  (setq f (cd:num 41 (cd:txtstyle sty) 1.0))
  (if (> f 0.0) f 1.0))

;; The DIMSCALE everything the dimension draws is sized by: the style's,
;; the dimension's own override of it where it has one, and -- for the
;; annotative 0, which is scaled by a viewport this file cannot measure
;; -- the drawing's current one.
(defun cd:dimscale (ed sty / scl o)
  (setq scl (cd:num 40 sty 1.0))
  (if (setq o (cd:override ed 40)) (setq scl o))
  (if (<= scl 0.0) (setq scl (cond ((getvar "DIMSCALE")) (1.0))))
  (if (<= scl 0.0) (setq scl 1.0))
  scl)

;; The height the dimension's text is actually drawn at.
;;
;; A TEXT STYLE WITH A FIXED HEIGHT WINS OUTRIGHT, and is used exactly
;; as it stands -- DIMTXT is ignored and DIMSCALE does not touch it.
;; That is not a guess: the drawing this rule was written for keeps
;; STANDARD at DIMSCALE 1.5 pointing at an 8-unit style, and the MTEXT
;; in the dimension's own block is 8.0 high, not 12.
;;
;; It matters more than any other number here.  A dimension style that
;; leaves DIMTXT at its 0.18 DXF default -- which a style is entitled
;; to do, and every style in that drawing did -- and carries its real
;; height on the text style instead used to come out THIRTY TIMES too
;; small.  Every text box was a speck, nothing overlapped anything, and
;; a sheet with two cross dims printing on top of each other in the
;; middle was reported "6 already clear - left alone".
(defun cd:txt-height (ed sty / txt o fixed)
  (setq txt   (cd:num 140 sty cd:*dimtxt-default*)
        fixed (cd:num 40 (cd:txtstyle sty) 0.0))
  (if (setq o (cd:override ed 140)) (setq txt o))
  (if (> fixed 0.0) fixed (* txt (cd:dimscale ed sty))))

;; What the dimension actually says.  Group 1 is the override: empty
;; means "the measurement", and "<>" inside an override stands for the
;; measurement too.  A single space is AutoCAD's "draw no text at all",
;; and it comes back as "".
(defun cd:dim-text (ed sty / ov meas i)
  (setq ov   (cd:dxf 1 ed)
        meas (cd:dim-meas ed sty))
  (cond
    ((null ov) meas)
    ((= ov "") meas)
    ((= (vl-string-trim " " ov) "") "")
    ((setq i (vl-string-search "<>" ov))
     (strcat (substr ov 1 i) meas (substr ov (+ i 3))))
    (T ov)))

;; The measurement as the text would read it.  Group 42 is what AutoCAD
;; stored; a linear or aligned dimension is recomputed from its own
;; definition points instead, so a dimension somebody stretched still
;; measures its own geometry.
;; How a length is spelled on this dimension: the STYLE's own DIMLUNIT
;; (277) and DIMDEC (271) where it has them, the drawing's LUNITS and
;; LUPREC where it does not.  The difference is not cosmetic -- the
;; drawing this was written against reads 1/8" off its styles and 1/16"
;; off its header, and "33'-3"" is half the width of "33'-2 15/16"".
;; DIMLUNIT 6 is Windows desktop, which rtos has no mode for; decimal
;; stands in.
(defun cd:lu-mode (sty / m)
  (setq m (cd:num 277 sty (cond ((getvar "LUNITS")) (2))))
  (if (and (>= m 1) (<= m 5)) m 2))

(defun cd:lu-prec (sty) (cd:num 271 sty (cond ((getvar "LUPREC")) (4))))

(defun cd:dim-meas (ed sty / dtype p13 p14 ang v meas)
  (setq dtype (logand 7 (cd:num 70 ed 0))
        meas  (cd:dxf 42 ed)
        p13   (cd:dxf 13 ed)
        p14   (cd:dxf 14 ed))
  (cond
    ((and (= dtype 1) p13 p14)
     (rtos (distance (cal:2d p13) (cal:2d p14))
           (cd:lu-mode sty) (cd:lu-prec sty)))
    ((and (= dtype 0) p13 p14)
     (setq ang (cd:num 50 ed 0.0)
           v   (cal:v- p14 p13))
     (rtos (abs (cal:dot v (list (cos ang) (sin ang))))
           (cd:lu-mode sty) (cd:lu-prec sty)))
    ((and (member dtype '(2 5)) meas (>= meas 0.0))
     (angtos meas (cd:num 275 sty 0) (cd:num 179 sty 4)))
    ((and meas (>= meas 0.0))
     (rtos meas (cd:lu-mode sty) (cd:lu-prec sty)))
    (T "")))

;; T when NAME is a layer this run must not write to.
(defun cd:layer-locked-p (name / ld)
  (setq ld (tblsearch "LAYER" name))
  (and ld (= 4 (logand 4 (cd:num 70 ld 0)))))

;; T when NAME is a layer whose entities are not ink.
(defun cd:layer-skip-p (name / hit l)
  (setq hit nil)
  (foreach l cd:*skip-layers*
    (if (= (strcase l) (strcase name)) (setq hit T)))
  hit)

;;; -------------------- entities reduced to polygons -------------------

;; Every (10 . pt) group on ED, in order -- an LWPOLYLINE's vertices.
(defun cd:pts10 (ed / out g)
  (setq out nil)
  (foreach g ed
    (if (= (car g) 10)
      (setq out (cons (cal:2d (cdr g)) out))))
  (reverse out))

;; PTS as a run of two-point polygons, closed back to the start when
;; CLOSED.  Bulges are read as their chord: a bulged edge's real arc
;; bows AWAY from the chord, so a text the chord clears can still be
;; caught -- the one place this file is optimistic, and it is written
;; down in the README rather than left to be discovered.
(defun cd:chain (pts closed / out rest)
  (setq out nil rest pts)
  (while (cdr rest)
    (setq out  (cons (list (car rest) (cadr rest)) out)
          rest (cdr rest)))
  (if (and closed (cdr pts))
    (setq out (cons (list (last pts) (car pts)) out)))
  out)

;; The arc CENTRE/R from A0 through SWEEP radians, as chords.
(defun cd:arc-chain (centre r a0 sweep / n i out step pts)
  (setq n    (max 2 (fix (+ 0.5 (* cd:*arcsegs* (/ (abs sweep) (* 2.0 pi))))))
        step (/ sweep (float n))
        i    0
        pts  nil)
  (while (<= i n)
    (setq pts (cons (list (+ (car centre) (* r (cos (+ a0 (* i step)))))
                          (+ (cadr centre) (* r (sin (+ a0 (* i step))))))
                    pts)
          i   (1+ i)))
  (setq out (cd:chain (reverse pts) nil))
  out)

;; A TEXT entity's width factor: its own group 41, or -- when it does
;; not carry one, which is what AutoCAD writes when the entity agrees
;; with its style -- the style's.  Unlike a dimension's, a TEXT names
;; its style (group 7) rather than pointing at it.
(defun cd:ent-wfactor (ed / f)
  (setq f (cd:num 41 ed 0.0))
  (if (<= f 0.0)
    (setq f (cd:num 41 (tblsearch "STYLE" (cond ((cd:dxf 7 ed)) ("STANDARD")))
                    1.0)))
  (if (> f 0.0) f 1.0))

;; The polygons a TEXT entity covers: one box, justified the way its
;; 72/73 codes say and anchored where they say to anchor it.  Group 11
;; is the alignment point and only means anything when one of the two
;; is non-zero -- otherwise group 10 is the left end of the baseline.
(defun cd:text-poly (ed / s hgt wh w h ang j72 j73 p10 p11 u anchor dx dy)
  (setq s (cd:dxf 1 ed))
  (if (or (null s) (= s "")) nil
    (progn
      (setq hgt (cd:num 40 ed 1.0)
            wh  (cd:text-size s hgt (cd:ent-wfactor ed))
            w   (car wh)
            h   (cadr wh)
            ang (cd:num 50 ed 0.0)
            j72 (cd:num 72 ed 0)
            j73 (cd:num 73 ed 0)
            p10 (cd:dxf 10 ed)
            p11 (cd:dxf 11 ed))
      (cond
        ;; Aligned (3) and Fit (5) are not justifications at all: the
        ;; text is SET BETWEEN groups 10 and 11, so those two ARE its
        ;; ends -- both the width the glyph count worked out and the
        ;; angle group 50 carries are the wrong ones, and reading them
        ;; as an anchor would put the box over one end of the letters
        ((and (member j72 '(3 5)) p10 p11
              (setq u (cal:unit (cal:v- p11 p10))))
         (list (cd:box (cal:v+ (cal:v* (cal:v+ (cal:2d p10) (cal:2d p11)) 0.5)
                              (cal:v* (cal:perp u) (* 0.5 h)))
                       (angle (cal:2d p10) (cal:2d p11))
                       (distance (cal:2d p10) (cal:2d p11))
                       h)))
        ((<= w 0.0) nil)
        (T
         ;; group 11 is the alignment point and only means anything when
         ;; the text is justified away from the left of its own baseline
         (setq anchor (if (and (or (/= 0 j72) (/= 0 j73)) p11) p11 p10))
         (setq dx (cond ((= j72 0) 0.0)
                        ((= j72 2) (- w))
                        (T (* -0.5 w))))       ; centre and middle
         (setq dy (cond ((= j72 4) (* -0.5 h)) ; "middle" is both at once
                        ((= j73 2) (* -0.5 h))
                        ((= j73 3) (- h))
                        (T 0.0)))              ; baseline and bottom
         (if anchor (list (cd:just-box anchor ang w h dx dy))))))))

;; An MTEXT's whole string.  Anything over 250 characters is split
;; across repeated group 3 chunks with the remainder in group 1, so
;; reading group 1 alone measures the LAST stretch of a paragraph and
;; none of the rest of it.
(defun cd:mtext-string (ed / out g)
  (setq out "")
  (foreach g ed
    (if (and (= (car g) 3) (= (type (cdr g)) 'STR))
      (setq out (strcat out (cdr g)))))
  (strcat out (cond ((cd:dxf 1 ed)) (""))))

;; The polygons an MTEXT entity covers: one box, placed by its
;; attachment point (group 71, 1 = top-left counting across then down).
(defun cd:mtext-poly (ed / s hgt wh w h ang ap col row anchor dx dy xdir)
  (setq s (cd:mtext-string ed))
  (if (or (null s) (= s "")) nil
    (progn
      (setq hgt  (cd:num 40 ed 1.0)
            wh   (cd:text-size s hgt 1.0)   ; MTEXT's group 41 is its
            w    (car wh)                   ; wrap width, not a factor
            h    (cadr wh)
            xdir (cd:dxf 11 ed)
            ang  (if (and xdir (cal:unit (cal:2d xdir)))
                   (atan (cadr xdir) (car xdir))
                   (cd:num 50 ed 0.0))
            ap   (cd:num 71 ed 1)
            col  (rem (1- ap) 3)
            row  (/ (1- ap) 3))
      (setq anchor (cd:dxf 10 ed))
      (setq dx (cond ((= col 0) 0.0) ((= col 1) (* -0.5 w)) (T (- w))))
      (setq dy (cond ((= row 0) (- h)) ((= row 1) (* -0.5 h)) (T 0.0)))
      (if (and anchor (> w 0.0))
        (list (cd:just-box anchor ang w h dx dy))))))

;; Every polygon EN covers, as ink.  An entity type the file does not
;; know is no ink at all -- listing it in cd:*obstacle-types* is what
;; makes it ink, and a type with no branch here would return nothing
;; anyway.
(defun cd:ent-polys (en / ed typ pts closed centre r a0 a1 sweep)
  (setq ed  (entget en)
        typ (cd:dxf 0 ed))
  (cond
    ((= typ "LINE")
     (list (list (cal:2d (cd:dxf 10 ed)) (cal:2d (cd:dxf 11 ed)))))
    ((= typ "LWPOLYLINE")
     (setq pts    (cd:pts10 ed)
           closed (= 1 (logand 1 (cd:num 70 ed 0))))
     (cd:chain pts closed))
    ((= typ "POLYLINE")
     (setq pts    (cd:vertex-pts en)
           closed (= 1 (logand 1 (cd:num 70 ed 0))))
     (cd:chain pts closed))
    ((= typ "CIRCLE")
     (cd:arc-chain (cal:2d (cd:dxf 10 ed)) (cd:num 40 ed 0.0) 0.0 (* 2.0 pi)))
    ((= typ "ARC")
     (setq centre (cal:2d (cd:dxf 10 ed))
           r      (cd:num 40 ed 0.0)
           a0     (cd:num 50 ed 0.0)
           a1     (cd:num 51 ed 0.0)
           sweep  (rem (+ (- a1 a0) (* 4.0 pi)) (* 2.0 pi)))
     (if (< sweep 1e-9) (setq sweep (* 2.0 pi)))
     (cd:arc-chain centre r a0 sweep))
    ((= typ "TEXT") (cd:text-poly ed))
    ((= typ "MTEXT") (cd:mtext-poly ed))
    (T nil)))

;; The vertices of an old-style heavy POLYLINE: the VERTEX entities that
;; follow it, up to its SEQEND.  They are subentities, so no ssget ever
;; hands one over and the walk has to be made here.
(defun cd:vertex-pts (en / e ed typ out p)
  (setq out nil e (entnext en))
  (while (and e (setq ed (entget e))
              (/= (setq typ (cd:dxf 0 ed)) "SEQEND"))
    (if (and (= typ "VERTEX") (setq p (cd:dxf 10 ed)))
      (setq out (cons (cal:2d p) out)))
    (setq e (entnext e)))
  (reverse out))

;;; -------------------- the dimension record ---------------------------
;;; One per DIMENSION in the sweep.  Positional, with an accessor each,
;;; because every field is read from three or four places and (nth 7 r)
;;; at each of them is how a field quietly becomes the wrong field.

(defun cd:rec (idx en dtype trk s0 ang w h own pins home lo hi out shift why)
  (list idx en dtype trk s0 ang w h own pins home lo hi out shift why))

(defun cd:r-idx  (r) (nth 0 r))    ; also the obstacle OWNER tag
(defun cd:r-en   (r) (nth 1 r))
(defun cd:r-type (r) (nth 2 r))    ; DXF 70's low three bits
(defun cd:r-trk  (r) (nth 3 r))    ; the TRACK: what it may slide along
(defun cd:r-s0   (r) (nth 4 r))    ; where the text sits on the track now
(defun cd:r-ang  (r) (nth 5 r))    ; the angle the text is set at, there
(defun cd:r-w    (r) (nth 6 r))
(defun cd:r-h    (r) (nth 7 r))
(defun cd:r-own  (r) (nth 8 r))    ; (RIDDEN OTHER) -- see the families
(defun cd:r-pins (r) (nth 9 r))    ; the DXF point groups that travel
                                   ; with the text -- (11), and (11 14)
                                   ; for an ordinate, whose leader ends
                                   ; where the text does
(defun cd:r-home (r) (nth 10 r))   ; the spot on the track the text would
                                   ; rather be near; the search tries
                                   ; the way toward it first
(defun cd:r-lo   (r) (nth 11 r))   ; the smallest s it may take, or nil
(defun cd:r-hi   (r) (nth 12 r))   ; and the largest, or nil.  A run
                                   ; member is held inside its OWN span:
                                   ; a chain's text slid past its own
                                   ; extension lines reads as the
                                   ; dimension for the span next door
(defun cd:r-out  (r) (nth 13 r))   ; the way AWAY from what it measures
(defun cd:r-shift (r) (nth 14 r))  ; how far its dimension LINE has been
                                   ; pushed that way so far, as a vector
(defun cd:r-why  (r) (nth 15 r))   ; nil, or why it cannot slide

;; Where R's text sits when it is slid to S.
(defun cd:r-pt (r s) (cd:trk-pt (cd:r-trk r) s))

;; The text box of R with its text slid to S along the track, grown by
;; cd:*gap-f* so "clear" means readable rather than merely not crossed.
;; On an arc the box turns as it goes, because the text does.
(defun cd:r-box (r s / pad)
  (setq pad (* cd:*gap-f* (cd:r-h r)))
  (cd:grow (cd:r-pt r s)
           (cd:trk-ang (cd:r-trk r) s (cd:r-s0 r) (cd:r-ang r))
           (cd:r-w r) (cd:r-h r) pad))

;; The kind of dimension DTYPE is, in the words the report uses.
(defun cd:typename (dtype)
  (cond ((member dtype '(2 5)) "angular")
        ((= dtype 3) "diameter")
        ((= dtype 4) "radius")
        ((= dtype 6) "ordinate")
        (T "linear")))

;;; Each family answers the same four questions about itself, and
;;; nothing below this line cares which family it was:
;;;
;;;   TRACK  what the text may slide along
;;;   OWN    the ink the dimension draws, as (RIDDEN OTHER).  RIDDEN
;;;          is what the text sits ON -- the dimension line, or the
;;;          dimension arc -- and is tagged to the dimension so it
;;;          alone ignores it, the way AutoCAD breaks that around the
;;;          text.  OTHER is the rest, ink to everyone including the
;;;          dimension itself.  An arc is MANY polygons, which is why
;;;          the two are separate lists and not a first element and a
;;;          tail: tagging only the first chord of its own arc would
;;;          have an angular dimension fleeing the other thirty-one
;;;   HOME   a point the text would rather be near, so a tie in the
;;;          search goes the way a drafter would send it; nil for no
;;;          preference
;;;   PINS   the DXF point groups that travel with the text
;;;   OUT    the unit normal pointing AWAY from what the dimension
;;;          measures, toward its own dimension line -- the direction a
;;;          whole run of dimensions is pushed when something is in its
;;;          way.  nil for a family whose group 10 is not a dimension
;;;          line location at all: a radius keeps its CENTRE there and
;;;          an ordinate its feature, and pushing either "out" would
;;;          move the dimension onto a different circle or a different
;;;          point rather than clear of an obstacle.
;;;   LO     the smallest s the text may take, or nil for none.  Two
;;;          families have a floor under them and the rest do not: an
;;;          ordinate's text slid back past its own feature point turns
;;;          its leader round the other way, and a radius dimension's
;;;          text on the far side of the centre is measuring from
;;;          nowhere.  An arc needs none -- a text at a fixed radius
;;;          can never reach the vertex -- and a diameter's text is
;;;          welcome anywhere along the diameter, which is what the
;;;          centre being the MIDDLE of its two points means
;;;
;;; A family answers nil when it cannot read its own track off the
;;; dimension -- two parallel lines with no vertex between them, an
;;; ordinate with no leader.  That dimension is reported and left
;;; alone, which is the only honest answer: a track guessed wrong does
;;; not move text along the dimension, it moves it off it.

;; LINEAR and ALIGNED (type 0 and 1).  The track is the dimension line:
;; group 50's direction on a rotated dimension, the run between the two
;; extension line origins on an aligned one.  Home is the middle of the
;; dimension line, and the ink is that line plus the two extension
;; lines, which cross the track at right angles and are what a text slid
;; too far ends up on.
(defun cd:fam-linear (ed dtype p10 p11 p13 p14 sty ang / base u exe
                         s13 s14 f13 f14 own)
  (setq base (if p10 (cal:2d p10) '(0.0 0.0))
        u    (list (cos ang) (sin ang)))
  (if (and p13 p14)
    (setq exe (* (cd:num 44 sty 0.18) (cd:dimscale ed sty))
          s13 (cal:dot (cal:v- p13 base) u)
          s14 (cal:dot (cal:v- p14 base) u)
          f13 (cal:v+ base (cal:v* u s13))
          f14 (cal:v+ base (cal:v* u s14))
          own (list (list (list f13 f14))
                    (list (list (cal:2d p13)
                                (cal:v+ f13 (cd:ext-tip p13 f13 exe)))
                          (list (cal:2d p14)
                                (cal:v+ f14 (cd:ext-tip p14 f14 exe)))))))
  (list (cd:trk-line base u
                     (cal:v- (cal:v- p11 base)
                            (cal:v* u (cal:dot (cal:v- p11 base) u))))
        own
        (if own (cal:mid f13 f14))
        '(11)
        nil
        ;; out: the perpendicular run from the middle of what is being
        ;; measured to the dimension line.  A dimension line drawn
        ;; straight through its own definition points has no outward
        ;; side and gets none
        (if (and p13 p14)
          (cal:unit (cal:v- (cal:v- base (cal:mid (cal:2d p13) (cal:2d p14)))
                          (cal:v* u (cal:dot (cal:v- base
                                                  (cal:mid (cal:2d p13)
                                                          (cal:2d p14)))
                                           u)))))))

;; ANGULAR (type 2, off two lines; type 5, off three points).  The
;; track is an ARC about the angle's vertex, and the radius the text
;; rides at is the invariant -- exactly what the offset above the
;; dimension line is for a linear one.
;;
;; The vertex is the one thing that has to be right, and the two kinds
;; keep it in different places: a 3-point dimension writes it into group
;; 15 outright, while a 2-line one has no vertex stored at all -- it is
;; where the two measured lines (13-14 and 15-10) cross, which is what
;; inters with an explicit nil finds on the INFINITE lines rather than
;; the drawn segments.  Two parallel lines cross nowhere and the
;; dimension is left alone.
(defun cd:ang-vertex (dtype p10 p13 p14 p15)
  (if (= dtype 5)
    (if p15 (cal:2d p15))
    (if (and p10 p13 p14 p15)
      ;; inters hands back a 3-element point; every track is 2-D
      (if (setq p15 (inters (cal:2d p13) (cal:2d p14)
                            (cal:2d p15) (cal:2d p10) nil))
        (cal:2d p15)))))

;; The two ray directions the dimension arc runs between, as angles from
;; the vertex, or nil when they cannot be read.  A 3-point dimension
;; points them straight at groups 13 and 14.  A 2-line one has four
;; candidate rays -- each measured line runs both ways out of the vertex
;; -- and the pair that is the arc is the pair whose short sweep the
;; dimension's own arc point falls inside, which is what the arc point
;; is there to say.
(defun cd:ang-rays (dtype vtx p10 p13 p14 p15 arcpt / a b d1 d2 best sw)
  (cond
    ((= dtype 5)
     (if (and p13 p14) (list (angle vtx (cal:2d p13)) (angle vtx (cal:2d p14)))))
    ((null arcpt) nil)
    (T
     (setq d1   (angle (cal:2d p13) (cal:2d p14))
           d2   (angle (cal:2d p15) (cal:2d p10))
           best nil)
     (foreach a (list d1 (+ d1 pi))
       (foreach b (list d2 (+ d2 pi))
         ;; the sweep from a to b that is under half a turn, with the
         ;; arc point's own bearing measured against it.  A pair the
         ;; arc point falls outside is one of the other three angles
         ;; those two lines make, which this dimension is not about
         (setq sw (cal:signed-dang a b))
         (if (and (> (abs sw) 1e-9) (null best)
                  (cd:between-p a b (angle vtx arcpt)))
           (setq best (list (cal:angnorm a) (cal:angnorm b))))))
     best)))

;; T when the bearing C lies inside the sweep from A to B that is under
;; half a turn -- the sweep an angular dimension's arc actually draws.
(defun cd:between-p (a b c / sw sc)
  (setq sw (cal:signed-dang a b)
        sc (cal:signed-dang a c))
  (if (> sw 0.0) (and (>= sc 0.0) (<= sc sw))
    (and (<= sc 0.0) (>= sc sw))))

(defun cd:fam-angular (ed dtype p10 p11 p13 p14 p15 sty / vtx arcpt rad
                          rays arad own meas swept)
  (setq vtx   (cd:ang-vertex dtype p10 p13 p14 p15)
        arcpt (if (= dtype 5) (if p10 (cal:2d p10)) (cd:dxf 16 ed)))
  (if arcpt (setq arcpt (cal:2d arcpt)))
  (if (or (null vtx) (< (distance vtx (cal:2d p11)) 1e-9))
    nil
    (progn
      (setq rad  (distance vtx (cal:2d p11))
            rays (cd:ang-rays dtype vtx p10 p13 p14 p15 arcpt)
            meas (cd:dxf 42 ed))
      ;; the check that says the vertex really is the vertex: the sweep
      ;; between the two rays IS the angle the dimension measures, and
      ;; group 42 is what it measured.  A vertex read off the wrong
      ;; groups does not survive it.
      (if rays
        (progn
          (setq swept (abs (cal:signed-dang (car rays) (cadr rays))))
          (if (and (numberp meas) (> meas 0.0)
                   (> (abs (- swept meas)) 0.02))
            (setq rays nil vtx nil))))
      (if (null vtx) nil
        (progn
          ;; the arc it draws, at its own radius rather than the text's
          (if (and rays arcpt (> (distance vtx arcpt) 1e-9))
            (setq arad (distance vtx arcpt)
                  own  (list (cd:arc-chain vtx arad (car rays)
                                           (cal:signed-dang (car rays)
                                                           (cadr rays)))
                             nil)))
          (list (cd:trk-arc vtx rad
                            (zerop (cd:num 73 sty 0)))  ; upright text does
                                                        ; not turn with it
                own
                ;; home is the middle of the sweep, at the text's own
                ;; radius -- where an angular dimension's text belongs
                (if rays
                  (polar vtx (+ (car rays)
                                (* 0.5 (cal:signed-dang (car rays)
                                                       (cadr rays))))
                         rad))
                '(11)
                nil
                nil))))))

;; RADIUS (type 4) and DIAMETER (type 3).  Both slide along the line
;; through the two points the dimension is built on, which is the
;; leader a drafter drags the text in and out along.  The two families
;; put different things in those groups and AutoDim's ad:raddimpts says
;; which: a radius dimension writes the CENTRE into group 10 and a point
;; on the circle into 15, while a diameter writes the two ends of the
;; diameter and has no centre of its own -- so its centre is the middle
;; of them, and that is where its text belongs.
(defun cd:fam-radial (dtype p10 p11 p15 / a b u base)
  (if (or (null p10) (null p15)) nil
    (progn
      (setq a (cal:2d p10)
            b (cal:2d p15)
            u (cal:unit (cal:v- b a)))
      (if (null u) nil
        (progn
          (setq base (if (= dtype 3) (cal:mid a b) a))
          (list (cd:trk-line base u
                             (cal:v- (cal:v- p11 base)
                                    (cal:v* u (cal:dot (cal:v- p11 base) u))))
                (list (list (list a b)) nil)
                (if (= dtype 3) base b)   ; the centre, or the circle it
                                          ; measures to
                '(11)
                ;; a radius runs OUT from its centre and its text has no
                ;; business on the far side of it; a diameter's centre is
                ;; the middle of its two points, so both sides are its own
                (if (= dtype 3) nil 0.0)
                nil))))))

;; ORDINATE (type 6).  Group 13 is the feature being measured and 14 is
;; where its leader ends; the text hangs off that end.  Bit 64 of group
;; 70 says which coordinate is being read, and with it which way the
;; leader runs: an X-type ordinate reads across and leads AWAY in Y, a
;; Y-type the other way about.  The sign comes from the leader itself,
;; so the track runs the way the leader was actually drawn.
;;
;; This is the one family whose text does not travel alone: the leader
;; ends where the text is, so group 14 is pinned to it and moves the
;; same step.  Moving the text off the end of its own leader is what
;; writing group 11 by itself would do.  The feature point never moves.
(defun cd:fam-ordinate (ed p11 p13 p14 h / xtype d u base)
  (if (or (null p13) (null p14)) nil
    (progn
      (setq xtype (= 64 (logand 64 (cd:num 70 ed 0)))
            d     (cal:v- p14 p13)
            u     (if xtype
                    (list 0.0 (if (< (cadr d) 0.0) -1.0 1.0))
                    (list (if (< (car d) 0.0) -1.0 1.0) 0.0))
            base  (cal:2d p13))
      (list (cd:trk-line base u
                         (cal:v- (cal:v- p11 base)
                                (cal:v* u (cal:dot (cal:v- p11 base) u))))
            (list (list (list base (cal:2d p14))) nil)
            ;; further out, always: an ordinate's leader is made longer
            ;; to get its text clear, never shorter back onto the work
            (cal:v+ (cal:v+ base (cal:v* u (cal:dot (cal:v- p11 base) u)))
                   (cal:v* u 1.0))
            '(11 14)
            ;; and it stops clear of the feature it is reading.  Slid
            ;; back past that the leader turns round and points the
            ;; other way, which is a drawing error rather than a
            ;; crowded one
            (* (+ 0.5 cd:*gap-f*) h)
            nil))))

;; The record for one DIMENSION.  Returns nil only for an entity that
;; is not a dimension at all; everything else comes back as a record,
;; with cd:r-why saying why it will not be moved when it will not.
(defun cd:read-dim (idx en / ed dtype sty hgt s wh w h p10 p11 p13 p14 p15
                        ang fam trk own home pins lo out s0 txtang why)
  (setq ed (entget en))
  ;; an entity that is not a dimension, and an ename that no longer
  ;; names one, both come back nil rather than half a record
  (if (and ed (= (cd:dxf 0 ed) "DIMENSION"))
    (progn
      (setq dtype (logand 7 (cd:num 70 ed 0))
            sty   (tblsearch "DIMSTYLE" (cond ((cd:dxf 3 ed)) ("STANDARD")))
            hgt   (cd:txt-height ed sty)
            s     (cd:dim-text ed sty)
            wh    (cd:text-size s hgt (cd:txt-wfactor sty))
            w     (car wh)
            h     (cadr wh)
            p10   (cd:dxf 10 ed)
            p11   (cd:dxf 11 ed)
            p13   (cd:dxf 13 ed)
            p14   (cd:dxf 14 ed)
            p15   (cd:dxf 15 ed))
      ;; the direction a linear dimension's line runs, which is also the
      ;; angle its text is set at
      (setq ang (if (= dtype 1)
                  (if (and p13 p14) (angle (cal:2d p13) (cal:2d p14)) 0.0)
                  (cd:num 50 ed 0.0)))
      ;; A linear dimension with no stored text point gets AutoCAD's own
      ;; default: the middle of the dimension line, the text sitting a
      ;; gap above it.  No other family gets a guess -- every dimension
      ;; AutoCAD writes carries group 11, and inventing one for an arc
      ;; or a leader would be putting the text somewhere rather than
      ;; finding where it already is.
      (if (and (null p11) (member dtype '(0 1)))
        (setq p11 (cal:v+ (if p10 (cal:2d p10) '(0.0 0.0))
                         (cal:v+ (cal:v* (list (cos ang) (sin ang))
                                       (if (and p10 p13 p14)
                                         (* 0.5 (+ (cal:dot (cal:v- p13 p10)
                                                           (list (cos ang)
                                                                 (sin ang)))
                                                   (cal:dot (cal:v- p14 p10)
                                                           (list (cos ang)
                                                                 (sin ang)))))
                                         0.0))
                                (cal:v* (cal:perp (list (cos ang) (sin ang)))
                                       (* 0.5 h))))))
      (setq fam (if (null p11) nil
                  (cond
                    ((member dtype '(0 1))
                     (cd:fam-linear ed dtype p10 p11 p13 p14 sty
                                    (+ ang (cd:num 53 ed 0.0))))
                    ((member dtype '(2 5))
                     (cd:fam-angular ed dtype p10 p11 p13 p14 p15 sty))
                    ((member dtype '(3 4)) (cd:fam-radial dtype p10 p11 p15))
                    ((= dtype 6) (cd:fam-ordinate ed p11 p13 p14 h)))))
      (if fam
        (setq trk  (car fam)
              own  (cadr fam)
              home (caddr fam)
              pins (cadddr fam)
              lo   (nth 4 fam)
              out  (nth 5 fam)
              s0   (cd:trk-s trk (cal:2d p11))))
      ;; the text reads along whatever it is set on -- the dimension
      ;; line, or the tangent of the arc -- unless the style turns it
      ;; upright (DIMTIH), and group 53 turns it further either way
      (setq txtang
            (+ (cond ((and sty (/= 0 (cd:num 73 sty 0))) 0.0)
                     ((and trk (cd:trk-arc-p trk))
                      (+ (angle (cd:trk-base trk) (cal:2d p11)) (* 0.5 pi)))
                     (T ang))
               (cd:num 53 ed 0.0)))
      (setq why (cond ((null fam) 'track)
                      ((<= w 0.0) 'notext)
                      ((cd:layer-locked-p (cond ((cd:dxf 8 ed)) ("0"))) 'locked)))
      ;; a dimension that will not move still needs a track to hold its
      ;; text box on, so an unreadable one gets a standing-still stub
      (if (null trk)
        (setq trk  (cd:trk-line (if p11 (cal:2d p11)
                                  (if p10 (cal:2d p10) '(0.0 0.0)))
                                '(1.0 0.0) '(0.0 0.0))
              s0   0.0
              own  nil
              pins '(11)))
      (cd:rec idx en dtype trk s0 txtang w h own pins
              (if home (cd:trk-near trk (cd:trk-s trk home) s0) s0)
              lo nil out '(0.0 0.0) why))))

;; How far an extension line runs PAST the dimension line: DIMEXE along
;; the direction it was already going.  A zero-length run -- the
;; definition point sitting on the dimension line -- gets no tip rather
;; than a division by zero.
(defun cd:ext-tip (org foot exe / v)
  (setq v (cal:unit (cal:v- foot org)))
  (if v (cal:v* v exe) '(0.0 0.0)))

;;; -------------------- the search -------------------------------------

;; The nearest S to R's current spot at which its text box clears OBS --
;; the current spot itself when that is already clear.  Stepped outward
;; in cd:*step-f* steps to cd:*reach-f*, then bisected back toward where
;; it started so the move is the smallest one that still works.  nil
;; when nothing inside reach is clear: the caller leaves the text alone
;; and says so, which is worth more to a drafter than a text parked in
;; an arbitrary spot.
(defun cd:find-slide (r obs / s0 smid step reach owner floor roof k s found
                         blocked dirs d lo hi mid i)
  (setq s0    (cd:r-s0 r)
        smid  (cd:r-home r)
        owner (cd:r-idx r)
        floor (cd:r-lo r)
        roof  (cd:r-hi r)
        step  (max 1e-6 (* cd:*step-f* (cd:r-h r)))
        reach (cd:trk-reach (cd:r-trk r) (* cd:*reach-f* (cd:r-w r))))
  (if (not (cd:hits-p (cd:r-box r s0) obs owner))
    s0
    (progn
      ;; the way back toward the middle of its own dimension line is
      ;; tried first, because the middle is where a dimension's text
      ;; belongs; a text already AT the middle has no way back, and its
      ;; tie goes down the line rather than up it
      (setq dirs (if (< s0 smid) '(1.0 -1.0) '(-1.0 1.0)))
      (setq k 1 found nil blocked nil)
      (while (and (not found) (<= (* k step) reach))
        (foreach d dirs
          (if (not found)
            (progn
              (setq s (+ s0 (* d k step)))
              (if (and (or (null floor) (>= s floor))
                       (or (null roof) (<= s roof))
                       (not (cd:hits-p (cd:r-box r s) obs owner)))
                (setq found   s
                      blocked (+ s0 (* d (1- k) step)))))))
        (setq k (1+ k)))
      (if (and found (> cd:*refine* 0))
        (progn
          ;; the bisection runs between a spot that was blocked and the
          ;; one that was not, and the floor is the one place the
          ;; blocked end may not be allowed to sit
          (setq lo (cond ((and floor (< blocked floor)) floor)
                         ((and roof (> blocked roof)) roof)
                         (blocked))
                hi found
                i  0)
          (while (< i cd:*refine*)
            (setq mid (* 0.5 (+ lo hi)))
            (if (cd:hits-p (cd:r-box r mid) obs owner)
              (setq lo mid)
              (setq hi mid))
            (setq i (1+ i)))
          (setq found hi)))
      found)))

;;; -------------------- reading order ----------------------------------

;; Row index of R, counting down the sheet: rows ROWTOL tall, so two
;; dimensions within one row sort left to right rather than by a
;; hairsbreadth of height.
(defun cd:row (r rowtol)
  (fix (/ (cadr (cd:r-pt r (cd:r-s0 r))) rowtol)))

;; Reading order, as a comparator: down the sheet, then left to right,
;; then by index so no two records ever compare equal.  vl-sort DROPS
;; what compares equal to its predecessor, so a comparator that can
;; return "same" for two different dimensions loses one of them.
(defun cd:order-lt (a b / ra rb xa xb)
  (setq ra (cd:row a cd:*rowtol*)
        rb (cd:row b cd:*rowtol*))
  (cond
    ((/= ra rb) (> ra rb))
    (T
     (setq xa (car (cd:r-pt a (cd:r-s0 a)))
           xb (car (cd:r-pt b (cd:r-s0 b))))
     (cond ((/= xa xb) (< xa xb))
           (T (< (cd:r-idx a) (cd:r-idx b)))))))

;; cd:*rowtol* is not a knob: it is cd:*rowtol-f* measured against the
;; sweep that is actually in front of us, and it is a global only
;; because vl-sort's comparator takes two arguments and no more.
(setq cd:*rowtol* 1.0)

(defun cd:set-rowtol (recs / h r)
  (setq h 0.0)
  (foreach r recs (setq h (max h (cd:r-h r))))
  (setq cd:*rowtol* (max 1e-6 (* cd:*rowtol-f* h))))

;;; -------------------- runs ---------------------------------------------
;;; A RUN is what a drafter reads as ONE dimension with breaks in it: a
;;; line of dimensions whose dimension lines are the same straight line.
;;; AutoCAD's own DIMCONTINUE makes them by the handful, AUTODIM lays
;;; whole perimeters out that way, and the thing that makes them a run
;;; rather than a coincidence is that a drafter who moves one expects
;;; the rest to come.
;;;
;;; Only a linear or aligned dimension joins one.  The other families
;;; keep something else in group 10 -- a radius keeps the CENTRE of its
;;; circle, an ordinate its feature -- so there is no dimension line
;;; there to be collinear with, and pushing one "out" would move the
;;; dimension onto a different circle rather than clear of an obstacle.
;;; cd:r-out is nil for exactly those, which is the test.

;; T when A and B are the same straight line, near enough: the same
;; direction (either way round -- a line has no front), the same
;; perpendicular offset, and close enough ALONG it to read as one run
;; rather than as two dimensions that happen to be in line across a
;; whole sheet.
(defun cd:same-track-p (a b / ua ub tol gap)
  (and (cd:r-out a) (cd:r-out b)
       (setq ua (cd:trk-u (cd:r-trk a))
             ub (cd:trk-u (cd:r-trk b)))
       ;; parallel, either way round
       (< (abs (cal:cross ua ub)) 1e-6)
       (progn
         (setq tol (* cd:*track-tol-f* (max (cd:r-h a) (cd:r-h b))))
         ;; and the same line, not merely a parallel one: the offset of
         ;; b's base from a's, measured across a's direction
         (< (abs (cal:dot (cal:v- (cd:trk-base (cd:r-trk b))
                                (cd:trk-base (cd:r-trk a)))
                         (cal:perp ua)))
            tol))
       (progn
         (setq gap (* cd:*run-gap-f* (max (cd:r-h a) (cd:r-h b))))
         (cd:spans-near-p (cd:r-span a) (cd:r-span b ) gap))))

;; A track's own direction.  An arc has none, and nothing that reaches
;; here has one.
(defun cd:trk-u (trk) (if (cd:trk-arc-p trk) nil (caddr trk)))

;; (LO HI): how far R's dimension line runs along its own track.  Its
;; own dimension line is the first thing in its ink, so this is read off
;; the geometry rather than guessed from the text.
(defun cd:r-span (r / dl a b)
  (setq dl (car (car (cd:r-own r))))
  (if dl
    (progn
      (setq a (cd:trk-s (cd:r-trk r) (car dl))
            b (cd:trk-s (cd:r-trk r) (cadr dl)))
      (list (min a b) (max a b)))
    (list (cd:r-s0 r) (cd:r-s0 r))))

;; Do two spans on one line come within GAP of each other?  Overlapping
;; counts, and so does a break of less than GAP -- "one continuous
;; dimension with breaks" is the whole idea, and a break is allowed to
;; be a real one.
(defun cd:spans-near-p (a b gap)
  (and (<= (car a) (+ (cadr b) gap)) (<= (car b) (+ (cadr a) gap))))

;; RECS grouped into runs, as a list of lists of RECORD INDEXES.  Every
;; record appears in exactly one, and a dimension with no run-mates is a
;; run of one -- which keeps everything downstream from having to ask
;; whether a record is in a run at all.
(defun cd:runs (recs / out grp r q placed joined)
  (setq out nil placed nil)
  (foreach r recs
    (if (not (member (cd:r-idx r) placed))
      (progn
        (setq grp (list r) placed (cons (cd:r-idx r) placed) joined T)
        ;; keep sweeping: a dimension that joins the group can bring the
        ;; next one within reach, which one pass over the list would miss
        (while joined
          (setq joined nil)
          (foreach q recs
            (if (and (not (member (cd:r-idx q) placed))
                     (cd:any-same-track-p q grp))
              (setq grp    (cons q grp)
                    placed (cons (cd:r-idx q) placed)
                    joined T))))
        (setq out (cons (mapcar 'cd:r-idx grp) out)))))
  (reverse out))

(defun cd:any-same-track-p (q grp / hit m)
  (setq hit nil)
  (foreach m grp (if (cd:same-track-p q m) (setq hit T)))
  hit)

;; R held inside its own span: a run's text stays between its OWN
;; extension lines.  On a chain that is not a nicety -- AutoCAD centres
;; each text in its own segment, and one slid past the end of that
;; segment reads as the dimension for the span next door.  It is why a
;; crowded run is STAGGERED rather than shuffled along: there is nowhere
;; along to go.
;;
;; A dimension with no run-mates keeps the run of the whole track, which
;; is the ordinary AutoCAD placement for a short dimension with wide
;; text -- outside its extension lines, where there is room.
(defun cd:bound-to-span (r / sp)
  (setq sp (cd:r-span r))
  (cd:rec (cd:r-idx r) (cd:r-en r) (cd:r-type r) (cd:r-trk r) (cd:r-s0 r)
          (cd:r-ang r) (cd:r-w r) (cd:r-h r) (cd:r-own r) (cd:r-pins r)
          (cd:r-home r)
          (if (cd:r-lo r) (max (cd:r-lo r) (car sp)) (car sp))
          (cadr sp)
          (cd:r-out r) (cd:r-shift r) (cd:r-why r)))

;; RECS with every member of a run of MORE THAN ONE bounded to its span.
(defun cd:bound-runs (recs runs / out r g)
  (setq out nil)
  (foreach r recs
    (setq g (cd:run-of (cd:r-idx r) runs))
    (setq out (cons (if (and g (cdr g)) (cd:bound-to-span r) r) out)))
  (reverse out))

;; The run IDX belongs to.
(defun cd:run-of (idx runs / out g)
  (foreach g runs (if (member idx g) (setq out g)))
  out)

;;; -------------------- pushing a line out -------------------------------

;; R with its whole dimension LINE moved N rows away from what it
;; measures -- the text with it, because the text belongs to the line;
;; the extension lines stretch to follow, which is what makes this a
;; move a drafter would make and not a distortion.  The definition
;; points do not move, so the dimension goes on measuring what it
;; measured.
;;
;; A row is cd:*row-f* text heights, which is the unit AUTODIM already
;; stands its own chains off the work in.
(defun cd:shift-rec (r n / d trk own)
  (if (or (null (cd:r-out r)) (= n 0))
    r
    (progn
      (setq d   (cal:v* (cd:r-out r) (* n cd:*row-f* (cd:r-h r)))
            trk (cd:r-trk r)
            own (cd:shift-own (cd:r-own r) d))
      (cd:rec (cd:r-idx r) (cd:r-en r) (cd:r-type r)
              (cd:trk-line (cal:v+ (cd:trk-base trk) d) (caddr trk)
                           (cadddr trk))
              (cd:r-s0 r) (cd:r-ang r) (cd:r-w r) (cd:r-h r)
              own (cd:r-pins r) (cd:r-home r) (cd:r-lo r) (cd:r-hi r)
              (cd:r-out r) (cal:v+ (cd:r-shift r) d) (cd:r-why r)))))

;; OWN moved by D: the dimension line goes bodily, and an extension line
;; keeps its origin on the work and grows at the far end.
(defun cd:shift-own (own d / dl ext p)
  (setq dl nil ext nil)
  (foreach p (car own) (setq dl (cons (list (cal:v+ (car p) d)
                                            (cal:v+ (cadr p) d)) dl)))
  (foreach p (cadr own) (setq ext (cons (list (car p) (cal:v+ (cadr p) d))
                                        ext)))
  (list (reverse dl) (reverse ext)))

;; RECS with each one pushed out the number of rows ROWS gives for its
;; index.  ROWS is an alist; an index it does not name stays put.
(defun cd:shift-all (recs rows / out r n)
  (setq out nil)
  (foreach r recs
    (setq n (cdr (assoc (cd:r-idx r) rows)))
    (setq out (cons (cd:shift-rec r (cond (n) (0))) out)))
  (reverse out))

;;; -------------------- the plan ---------------------------------------
;;; The result for one dimension is (REC S MOVED CLEARED):
;;;   S        where its text ends up on the track
;;;   MOVED    T when that is not where it started
;;;   CLEARED  T when the box there is clear of everything placed

;; Results back in the order the records came in.  No two records
;; share an index, so nothing here ever compares equal -- vl-sort DROPS
;; what does.
(defun cd:res-lt (x y)
  (< (cd:r-idx (cd:res-rec x)) (cd:r-idx (cd:res-rec y))))

(defun cd:res-rec  (x) (nth 0 x))
(defun cd:res-s    (x) (nth 1 x))
(defun cd:res-moved (x) (nth 2 x))
(defun cd:res-clear (x) (nth 3 x))

;; Everything in the drawing that is ink, as obstacles: the entities in
;; SS that are not dimensions, plus what every dimension in RECS draws
;; for itself.  A dimension's own dimension line is tagged with its
;; index so that dimension alone ignores it; the extension lines are
;; tagged nil, because a text over one of those is unreadable whoever
;; drew it.
(defun cd:static-obs (ss recs runs / out i n en ed typ lay own p r tag)
  (setq out nil i 0 n (if ss (sslength ss) 0))
  (while (< i n)
    (setq en  (ssname ss i)
          ed  (entget en)
          typ (cd:dxf 0 ed)
          lay (cond ((cd:dxf 8 ed)) ("0")))
    (if (and (member typ cd:*obstacle-types*) (not (cd:layer-skip-p lay)))
      (foreach p (cd:ent-polys en)
        (setq out (cons (cd:ob nil p) out))))
    (setq i (1+ i)))
  (foreach r recs
    (setq own (cd:r-own r)
          tag (cond ((cd:run-of (cd:r-idx r) runs)) ((list (cd:r-idx r)))))
    ;; What it RIDES is tagged to its whole RUN, so every member of one
    ;; line of dimensions passes through it.
    (foreach p (car own)
      (setq out (cons (cd:ob tag p) out)))
    ;; Its EXTENSION lines are ink to everyone -- except, in a run of
    ;; more than one, to the run itself.  A continued chain does not
    ;; merely have extension lines near each other, it SHARES them: the
    ;; line at the end of one segment is the line at the start of the
    ;; next.  They are the skeleton of one dimension with breaks in it,
    ;; and a text of that dimension standing against them is the chain
    ;; drawn tight rather than a text that is hard to read.
    (foreach p (cadr own)
      (setq out (cons (cd:ob (if (cdr tag) tag nil) p) out))))
  out)

;; The three buckets, in the order they get to claim a spot: what cannot
;; move, then what is already clear of everything fixed, then the rest.
;; Each is in reading order inside itself.  This is the whole of the
;; policy -- a text that is already good keeps its spot and the ones
;; that are not go around it.
(defun cd:buckets (recs static / fixed clear dirty r)
  (setq fixed nil clear nil dirty nil)
  (foreach r recs
    (cond
      ((cd:r-why r) (setq fixed (cons r fixed)))
      ((not (cd:hits-p (cd:r-box r (cd:r-s0 r)) static (cd:r-idx r)))
       (setq clear (cons r clear)))
      (T (setq dirty (cons r dirty)))))
  (list (vl-sort (reverse fixed) 'cd:order-lt)
        (vl-sort (reverse clear) 'cd:order-lt)
        (vl-sort (reverse dirty) 'cd:order-lt)))

;; What CLEARDIM would do to RECS, given the drawing's own ink STATIC:
;; one result per record, in the records' own order.  Pure -- it reads
;; the drawing through what it was handed and writes nothing -- so the
;; policy can be tested without a drawing to write to.
(defun cd:plan (recs static / bk order obs out r s res)
  (cd:set-rowtol recs)
  (setq bk    (cd:buckets recs static)
        order (append (car bk) (cadr bk) (caddr bk))
        obs   static
        out   nil)
  (foreach r order
    (setq s (if (cd:r-why r)
              (cd:r-s0 r)                 ; cannot move: it keeps its spot
              (cd:find-slide r obs)))
    (if (null s) (setq s (cd:r-s0 r)))    ; nowhere clear: left as drawn
    (setq res (list r s
                    (or (> (abs (- s (cd:r-s0 r))) 1e-9)
                        (> (cal:vlen (cd:r-shift r)) 1e-9))
                    (or (<= (cd:r-w r) 0.0)
                        (not (cd:hits-p (cd:r-box r s) obs (cd:r-idx r))))))
    ;; the spot it just took is ink for everyone after it -- unless there
    ;; are no letters there to be ink.  A dimension whose text is
    ;; suppressed has a text POINT like any other, and counting it would
    ;; put a small square of nothing in the way of the next text along
    (if (> (cd:r-w r) 0.0)
      (setq obs (cons (cd:ob (cd:r-idx r) (cd:r-box r s)) obs)))
    (setq out (cons res out)))
  ;; back into the records' own order, so a caller can pair results with
  ;; the list it handed in without carrying the bucket order around
  (vl-sort out 'cd:res-lt))

;;; -------------------- rows: staggering, and moving a run ---------------
;;; cd:plan places text ALONG the track.  When that is not enough there
;;; is one move left, and it is the one a drafter makes: stand the
;;; dimension LINE further off the work.  Two shapes of it, and which
;;; one is right is decided by WHO is in the way:
;;;
;;;   * crowded only by its own run-mates -> STAGGER.  That one
;;;     dimension goes out a row on its own.  A run of short dimensions
;;;     whose text will not fit between its own extension lines is
;;;     exactly this, and staggering is what a drafter does to it.
;;;   * crowded by anything else -> the WHOLE RUN goes out a row
;;;     together, so the line of them stays a line.  Moving one of them
;;;     off a wall and leaving its neighbours behind would trade a
;;;     crowded dimension for a crooked run.
;;;
;;; Then the whole placement is run again from the top on the moved
;;; records, because a row out is a different drawing and the answer to
;;; who keeps their spot may have changed.  Up to cd:*rows* rows, and
;;; the arrangement kept is the one that leaves the fewest dimensions
;;; crowded -- ties to the one that moved the least, and a tie there to
;;; the rows that came first, so the same sheet comes out the same way
;;; every run.

;; How many dimensions an arrangement leaves crowded, and how many rows
;; it spent doing it -- lower is better, in that order.
(defun cd:score (results state / bad r)
  (setq bad 0)
  (foreach r results (if (not (cd:res-clear r)) (setq bad (1+ bad))))
  (list bad (cd:state-cost state)))

(defun cd:score-lt (a b)
  (or (< (car a) (car b))
      (and (= (car a) (car b)) (< (cadr a) (cadr b)))))

;;; A run's state is (INDEXES OFFSET DEPTH):
;;;
;;;   OFFSET  how many rows the WHOLE run stands off the work.  This is
;;;           the one that keeps a line of dimensions a line -- every
;;;           member takes it, the crowded one and its neighbours alike.
;;;   DEPTH   how many rows the run is STAGGERED across.  1 is dead
;;;           straight; 2 puts every other dimension a row further out;
;;;           3 goes out, further out, and back.
;;;
;;; A member's row is OFFSET plus its own place in the stagger, counted
;;; ALONG THE TRACK so the pattern reads as a pattern and not as
;;; scatter.

(defun cd:run-state (run) (list run 0 1))

;; RUN's indexes in the order they sit along the track.
(defun cd:run-order (run recs / pairs r)
  (setq pairs nil)
  (foreach r recs
    (if (member (cd:r-idx r) run)
      (setq pairs (cons (list (cd:r-s0 r) (cd:r-idx r)) pairs))))
  (mapcar 'cadr (vl-sort pairs 'cd:pair-lt)))

(defun cd:pair-lt (a b)
  (if (/= (car a) (car b)) (< (car a) (car b)) (< (cadr a) (cadr b))))

;; The row each record sits on, as an alist, out of every run's state.
(defun cd:state-rows (state recs / out g i idx)
  (setq out nil)
  (foreach g state
    (setq i 0)
    (foreach idx (cd:run-order (car g) recs)
      (setq out (cons (cons idx (+ (cadr g) (rem i (caddr g)))) out)
            i   (1+ i))))
  out)

;; How many rows the state spends altogether -- the tie-break that stops
;; the tool standing a run off the work further than it had to.
(defun cd:state-cost (state / n g)
  (setq n 0)
  (foreach g state
    (setq n (+ n (* (length (car g)) (+ (cadr g) (1- (caddr g)))))))
  n)

;; ITEMS without IDX.
(defun cd:remove-one (idx items / out g)
  (foreach g items (if (not (equal g idx)) (setq out (cons g out))))
  (reverse out))

;; Is every one of A in B?  An empty A is not a subset here: a dimension
;; nothing is in the way of is not one to stagger.
(defun cd:subset-p (a b / ok g)
  (setq ok (and a T))
  ;; a tag that is a LIST is ink some OTHER run shares, never a mate of
  ;; this one -- its own run's tags never reach here, being its own
  (foreach g a (if (or (listp g) (not (member g b))) (setq ok nil)))
  ok)

;; The results for RUN's members that came out crowded and could be
;; moved about it.
(defun cd:run-bad (run results / out r)
  (setq out nil)
  (foreach r results
    (if (and (member (cd:r-idx (cd:res-rec r)) run) (not (cd:res-clear r))
             (cd:r-out (cd:res-rec r)) (not (cd:r-why (cd:res-rec r))))
      (setq out (cons r out))))
  out)

;; The state to try next.  Every run with a dimension still crowded in
;; it moves, and WHICH WAY is decided by who is in the way:
;;
;;   * crowded only by its own run-mates -> stagger one row deeper.
;;     There is nothing along the track to be done about a text wider
;;     than the segment it belongs to, and shuffling one along only
;;     hands the crowding to its neighbour.
;;   * crowded by anything else -> the whole run stands one row further
;;     off the work, TOGETHER, so the line of them stays a line.  Moving
;;     one dimension off a wall and leaving its neighbours behind trades
;;     a crowded dimension for a crooked run.
;;
;; nil when nothing is crowded, or when every run that is has run out of
;; rows to spend.
(defun cd:next-state (results state runs obs recs / out g run bad mates
                          hitters all-mates moved r)
  (setq out nil moved nil)
  (foreach g state
    (setq run       (car g)
          bad       (cd:run-bad run results)
          all-mates T)
    (foreach r bad
      (setq mates   (cd:remove-one (cd:r-idx (cd:res-rec r)) run)
            hitters (cd:hit-owners (cd:r-box (cd:res-rec r) (cd:res-s r))
                                   obs (cd:r-idx (cd:res-rec r))))
      (if (not (cd:subset-p hitters mates)) (setq all-mates nil)))
    (cond
      ((null bad) (setq out (cons g out)))
      ;; a crowd of its own making: stagger deeper
      ((and cd:*stagger* all-mates (< (caddr g) cd:*stagger-max*))
       (setq out   (cons (list run (cadr g) (1+ (caddr g))) out)
             moved T))
      ;; something else is in the way: the whole run stands further off
      ((< (cadr g) cd:*rows*)
       (setq out   (cons (list run (1+ (cadr g)) (caddr g)) out)
             moved T))
      (T (setq out (cons g out)))))
  (if moved (reverse out)))

;; The whole answer: place along the track, and where that is not enough
;; stagger the run or stand it off the work and place again.  Returns
;; (RESULTS RECS) -- the results, and the records they were computed
;; against, which carry the rows in their cd:r-shift and are what
;; cd:apply must be handed.
(defun cd:plan-rows (ss recs / runs state tries going shifted static
                        results score best bestrecs bestscore next)
  (setq runs  (cd:runs recs)
        recs  (cd:bound-runs recs runs)
        state (mapcar 'cd:run-state runs)
        tries 0
        going T)
  (while going
    (setq shifted (cd:shift-all recs (cd:state-rows state recs))
          static  (cd:static-obs ss shifted runs)
          results (cd:plan shifted static)
          score   (cd:score results state))
    ;; strictly better only, so a later arrangement that merely ties
    ;; never displaces an earlier one that spent fewer rows
    (if (or (null bestscore) (cd:score-lt score bestscore))
      (setq bestscore score
            best      results
            bestrecs  shifted))
    (setq next (if (= (car score) 0)
                 nil                            ; nothing left to fix
                 (cd:next-state results state runs
                                (cd:placed-obs shifted results static)
                                shifted)))
    (if (and next (< tries (* 2 (+ cd:*rows* cd:*stagger-max*))))
      (setq state next
            tries (1+ tries))
      (setq going nil)))
  (list best bestrecs))

;; STATIC with every text box the arrangement placed added to it -- what
;; cd:plan itself builds as it goes, rebuilt here so cd:next-rows can
;; ask who a crowded text is actually crowded BY.
(defun cd:placed-obs (recs results static / out r rec)
  (setq out static)
  (foreach r results
    (setq rec (cd:res-rec r))
    (if (> (cd:r-w rec) 0.0)
      (setq out (cons (cd:ob (cd:r-idx rec) (cd:r-box rec (cd:res-s r)))
                      out))))
  out)

;;; -------------------- writing it back --------------------------------

;; XY from P, Z from the point OLD that is being replaced -- a drawing
;; that works at an elevation keeps it rather than having every text it
;; touches quietly flattened to zero.
(defun cd:pt-at (p old)
  (list (car p) (cadr p)
        (cond ((and old (caddr old)) (caddr old)) (0.0))))

;; Slide RES's text to where the plan put it, and with it every DXF
;; point group pinned to it: group 11 always, plus an ordinate's leader
;; end, which is where its text hangs from and would otherwise be left
;; behind.  Group 11 goes to the track point; the rest move by the same
;; step, so the shape of the dimension is carried along rather than
;; rebuilt.  Then the bit in group 70 that tells AutoCAD the text sits
;; where it was put rather than where the style would have put it.
;;
;; Only the along-track part of the position changes -- the across-track
;; offset of a straight track, and the radius of an arc, are what
;; cd:trk-pt puts back exactly as they were read -- so the text comes
;; out on the same track it went in on.  T when the drawing changed.
(defun cd:apply (res / r ed p0 p1 d sh flags code g)
  (setq r (cd:res-rec res))
  (if (not (cd:res-moved res))
    nil
    (progn
      (setq ed    (entget (cd:r-en r))
            sh    (cd:r-shift r)
            ;; where the text WAS: on the track before the run was
            ;; pushed out, which is the track the record carries minus
            ;; the push
            p0    (cal:v- (cd:r-pt r (cd:r-s0 r)) sh)
            p1    (cd:r-pt r (cd:res-s res))
            d     (cal:v- p1 p0)
            flags (cd:num 70 ed 0))
      ;; the dimension LINE goes with it.  Group 10 is where a linear
      ;; dimension's line sits, and the definition points are left alone
      ;; -- so the extension lines stretch and the dimension goes on
      ;; measuring exactly what it measured
      (if (and (> (cal:vlen sh) 1e-9) (setq g (assoc 10 ed)))
        (setq ed (subst (cons 10 (cd:pt-at (cal:v+ (cdr g) sh) (cdr g)))
                        g ed)))
      (foreach code (cd:r-pins r)
        (setq g (assoc code ed))
        (if g
          (setq ed (subst (cons code
                                (cd:pt-at (if (= code 11) p1
                                            (cal:v+ (cdr g) d))
                                          (cdr g)))
                          g ed))
          ;; group 11 is written even onto a dimension that carried none
          (if (= code 11)
            (setq ed (append ed (list (cons 11 (cd:pt-at p1 nil))))))))
      (setq ed (if (assoc 70 ed)
                 (subst (cons 70 (logior 128 flags)) (assoc 70 ed) ed)
                 (append ed (list (cons 70 (logior 128 flags))))))
      (entmod ed)
      (entupd (cd:r-en r))
      T)))

;;; -------------------- the report -------------------------------------

;; One line per dimension the run has something to say about, then the
;; totals, under the name WHAT of the command that asked for them.
;; MOVING is T for the run that writes and nil for the scan, so the same
;; report reads correctly either way.
(defun cd:report (what results moving / nmove nstuck nclear skip r why d
                                        sh res)
  (setq nmove 0 nstuck 0 nclear 0 skip nil)
  (foreach res results
    (setq r   (cd:res-rec res)
          why (cd:r-why r))
    (if why
      (progn
        (setq skip (cons why skip))
        (if (not (cd:res-clear res))
          (princ (strcat "\n  " (cd:handle-of r) ": "
                         (cd:why-text why)
                         " - left as drawn, and its text is not clear."))))
      (cond
        ((cd:res-moved res)
         (setq nmove (1+ nmove)
               d     (- (cd:res-s res) (cd:r-s0 r))
               sh    (cal:vlen (cd:r-shift r)))
         (princ (strcat "\n  " (cd:handle-of r) ": "
                        (if moving "" "would be ")
                        ;; two things can have happened and either may
                        ;; be the only one: the dimension stood further
                        ;; off the work, and the text slid along it
                        (if (> sh 1e-9)
                          (strcat "stood " (rtos sh) " further off the work")
                          "")
                        (if (and (> sh 1e-9) (> (abs d) 1e-9)) " and " "")
                        (if (> (abs d) 1e-9)
                          (strcat "slid " (rtos (abs d)) " "
                                  (if (< d 0.0) "back " "")
                                  (cd:trackword r))
                          "")
                        ".")))
        ((not (cd:res-clear res))
         (setq nstuck (1+ nstuck))
         (princ (strcat "\n  " (cd:handle-of r)
                        ": nothing within reach of its track is clear"
                        " - left as drawn.")))
        (T (setq nclear (1+ nclear))))))
  (princ (strcat "\n" what ": "
                 (cal:plural (length results) "dimension" "dimensions") "."))
  (princ (strcat "\n  " (itoa nclear) " already clear - left alone."))
  ;; "along its own dimension line" was true while only the straight
  ;; ones moved; an angular dimension's text goes round an arc.  What
  ;; holds for every family is that it did not leave its dimension --
  ;; which is the thing a drafter wants told, and the per-dimension
  ;; lines above say which of the two it was
  (princ (strcat "\n  "
                 (if moving
                   (cal:plural nmove "slid clear without leaving its dimension"
                              "slid clear without leaving their dimensions")
                   (cal:plural nmove
                              "to slide clear without leaving its dimension"
                              "to slide clear without leaving their dimensions"))
                 "."))
  (if (> nstuck 0)
    (princ (strcat "\n  " (itoa nstuck) " with nowhere clear on the track"
                   " - left as drawn.")))
  (if skip (princ (strcat "\n  " (cd:skip-text skip))))
  (list nclear nmove nstuck (length skip)))

;; The handle, which is what a drafter types at SELECT to find the thing
;; the report is talking about.  A record with no entity behind it --
;; cd:plan is pure and can be driven from built records -- falls back to
;; naming the kind, so the report never crashes on the way out.
(defun cd:handle-of (r / ed)
  (if (cd:r-en r) (setq ed (entget (cd:r-en r))))
  (cond ((and ed (cd:dxf 5 ed)) (strcat "handle " (cd:dxf 5 ed)))
        (T (strcat (cd:typename (cd:r-type r)) " dimension"))))

;; What R's text slides along, in the words the report uses.
(defun cd:trackword (r)
  (if (cd:trk-arc-p (cd:r-trk r))
    "round its dimension arc"
    "along its dimension line"))

(defun cd:why-text (why)
  (cond ((eq why 'track) "its track could not be read off the dimension")
        ((eq why 'locked) "its layer is locked")
        (T "it has no text")))

;; "3 skipped: 2 angular tracks, 1 locked layer." -- counted by reason,
;; because "3 skipped" alone tells a drafter nothing they can act on.
(defun cd:skip-text (skip / nc nl nt out w)
  (setq nc 0 nl 0 nt 0 out nil)
  (foreach w skip
    (cond ((eq w 'track) (setq nc (1+ nc)))
          ((eq w 'locked) (setq nl (1+ nl)))
          (T (setq nt (1+ nt)))))
  (if (> nc 0)
    (setq out (cons (if (= nc 1) "1 whose track could not be read"
                      (strcat (itoa nc) " whose tracks could not be read"))
                    out)))
  (if (> nl 0)
    (setq out (cons (if (= nl 1) "1 on a locked layer"
                      (strcat (itoa nl) " on locked layers")) out)))
  (if (> nt 0)
    (setq out (cons (strcat (itoa nt) " with no text") out)))
  (strcat (itoa (length skip)) " skipped: "
          (cd:join (reverse out) ", ") "."))

(defun cd:join (items sep / out s)
  (setq out "")
  (foreach s items
    (setq out (if (= out "") s (strcat out sep s))))
  out)

;;; -------------------- asking -----------------------------------------

;; The one question either command puts: which part of the drawing to
;; work on.  Enter takes the whole of model space, which is the answer
;; nearly every run wants; a selection is for a sheet with more than one
;; drawing on it.  Returns the selection set, or nil when the drawing
;; holds no dimension at all.
(defun cd:asksel (what / msg ss)
  ;; whatever the drafter had already picked before typing the command
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
    (progn
      (setq msg (strcat "\nHighlight the drawing to " what
                        " (Enter = whole drawing): "))
      (prompt msg)
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss) ss)
      (if lzd:ask (lzd:ask msg ss) ss)))
  ;; Enter: everything in the space the drafter is looking at.  CTAB is
  ;; "Model" in model space and the layout's name in a layout, so a run
  ;; started on a sheet does not drag model-space geometry in as ink --
  ;; and a drawing whose entities carry no space group at all still
  ;; answers the plain sweep underneath
  (if (null ss)
    (progn
      (setq ss (ssget "_X"
                      (list (cons 410 (cond ((getvar "CTAB")) ("Model"))))))
      (if lzd:watch (lzd:watch ss) ss)))
  (if (null ss)
    (progn
      (setq ss (ssget "_X"))
      (if lzd:watch (lzd:watch ss) ss)))
  ss)

;; Every record for the dimensions in SS, indexed in the order ssget
;; hands them over -- which is the order the obstacle owner tags and the
;; final result order are both in.
(defun cd:records (ss / out i n en r)
  (setq out nil i 0 n (if ss (sslength ss) 0))
  (while (< i n)
    (setq en (ssname ss i))
    (if (= (cd:dxf 0 (entget en)) "DIMENSION")
      (if (setq r (cd:read-dim (length out) en))
        (setq out (cons r out))))
    (setq i (1+ i)))
  (reverse out))

;;; -------------------- the commands -----------------------------------

;; The sysvars either command changes, in the order they come back.
;; OSMODE is deliberately NOT in this list.  CLEARDIM, and neither does CLEARDIMSCAN, never
;; changes it, and a list is a promise to WRITE the value back: the run
;; would put its opening snapshot back over any snap the drafter ticked
;; on while it was up -- on a clean exit, with no error involved, which
;; is the likeliest way anyone meets it.  Borrow only what you move.
(defun cd:sysvars () '("CMDECHO"))

(defun c:CLEARDIM ( / *error* undo-open ss recs results n res)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:sysrestore)
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCLEARDIM error: " msg)))
    (if lzd:report (lzd:report "CLEARDIM" *cleardim-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CLEARDIM" *cleardim-version*))
  (cal:syssave (cd:sysvars))
  (setvar "CMDECHO" 0)
  (setq ss (cd:asksel "CLEARDIM"))
  (setq recs (cd:records ss))
  (if (null recs)
    (princ "\nCLEARDIM: no dimensions in the selection - nothing to do.")
    (progn
      ;; opened only when undo is recording: _Begin in a drawing whose
      ;; UNDOCTL has bit 1 clear errors out of the command
      (if (= 1 (logand 1 (getvar "UNDOCTL")))
        (progn
          (command "_.UNDO" "_Begin")
          (setq undo-open T)))
      (setq results (car (cd:plan-rows ss recs))
            n       0)
      (foreach res results (if (cd:apply res) (setq n (1+ n))))
      (cd:report "CLEARDIM" results T)
      (if (> n 0)
        (princ "\n  One U puts every one of them back."))
      (if undo-open
        (progn
          (command "_.UNDO" "_End")
          (setq undo-open nil)))))
  (cal:sysrestore)
  (if lzd:end (lzd:end "CLEARDIM"))
  (princ))

(defun c:CLEARDIMSCAN ( / *error* ss recs results)
  (defun *error* (msg)
    (cal:sysrestore)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCLEARDIMSCAN error: " msg)))
    (if lzd:report (lzd:report "CLEARDIMSCAN" *cleardim-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CLEARDIMSCAN" *cleardim-version*))
  (cal:syssave (cd:sysvars))
  (setvar "CMDECHO" 0)
  (setq ss (cd:asksel "CLEARDIMSCAN"))
  (setq recs (cd:records ss))
  (if (null recs)
    (princ "\nCLEARDIMSCAN: no dimensions in the selection - nothing to do.")
    (progn
      (setq results (car (cd:plan-rows ss recs)))
      (cd:report "CLEARDIMSCAN" results nil)
      (princ "\n  Nothing was moved - run CLEARDIM to do it.")))
  (cal:sysrestore)
  (if lzd:end (lzd:end "CLEARDIMSCAN"))
  (princ))

(defun c:CLEARDIMVER ()
  (princ (strcat "\nCLEARDIM " *cleardim-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and CALOFIN-LOADER.lsp set
;; the flag while they load their members.  APPLOADed alone the flag is
;; nil and this prints, which is the one time somebody wants to be told.
;; CALVER reports the whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nCLEARDIM " *cleardim-version*
                 " loaded. Commands: CLEARDIM (slide crowded dimension"
                 " text clear along its own dimension, without leaving"
                 " it), CLEARDIMSCAN (say what it would do, change"
                 " nothing).")))
(princ)
