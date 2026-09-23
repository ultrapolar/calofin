;;; ======================================================================
;;; PERPMARK.lsp  --  measured distances marked square off the pool wall,
;;;                   then joined into one polyline and dimensioned
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  PERPMARK     mark measured distances off the perimeter
;;;            PERPMARKVER  print the loaded version
;;; ======================================================================
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; What it is for
;;;   A bench, a step, a tanning ledge and a gutter are all measured the
;;;   same way in the field: stand at a survey point on the wall, run the
;;;   tape square off it, and write the number down beside that point's
;;;   number.  PERPMARK is that, at the keyboard.  Name the point -- click
;;;   it or type its number -- give the distance, and the point gets a
;;;   circle of that radius, the swing of the tape, and a line of that
;;;   length running square off the wall into the pool.  Name the next
;;;   point, type the next number, and so on for as long as the sheet
;;;   lasts.  Enter ends it.
;;;
;;;   Then, if the marks are meant to BE something, it will join them up:
;;;   one polyline through the far end of every line between the two
;;;   points you name, the circles cleared away, and each line replaced
;;;   by the dimension that says what it measured.
;;;
;;;   The points are the ones the rest of the family reads -- ABHD,
;;;   CABHD, ABFIND, BPCALLOUT, CDCALLOUT and LHD all classify a survey
;;;   point the same way, and this uses their classifier: an "ab_pt"
;;;   INSERT wherever it sits, any other INSERT on the POINTS layer, and
;;;   a plain POINT on that layer, numbered by its "number" attribute.
;;;   Only model space is read: a point block pasted onto a layout is
;;;   not one of the pool's points.
;;;
;;; Workflow
;;;   1. Select the perimeter -- the wall the distances were taped off.
;;;      Any curve: a polyline (arc segments included), a line, an arc, a
;;;      circle, and anything else AutoCAD can measure along.
;;;   2. Only when the wall does NOT close: click the side the pool is
;;;      on.  A closed wall knows its own inside and is not asked --
;;;      see below.
;;;   3. Name a survey point, give the distance, and repeat:
;;;        - click the point, or type its number; "17", "Pt.17", "#17"
;;;          and "017" all name the same one;
;;;        - a point that is not ON the perimeter is projected onto it,
;;;          and the mark is drawn from where it landed, so a shot that
;;;          sits an inch off the fitted wall still marks the wall;
;;;        - naming a point already marked REPLACES its mark -- the sheet
;;;          has one distance at a point, so the second answer is a
;;;          correction rather than a second mark;
;;;        - Back takes the last mark away again;
;;;        - from the second distance on, a RULER of nearby distances
;;;          stands beside the prompt: click a row and that is the
;;;          distance (see "The ruler beside the distance" below);
;;;        - Enter ends the round.
;;;   4. Draw a polyline through the marks?  No leaves every circle and
;;;      every line exactly where they are, for you to do as you see fit.
;;;   5. Yes asks which point the run starts at and which it ends at,
;;;      named the same way.  A point that was taped is the mark made at
;;;      it, so the run starts where the tape reached; a point that was
;;;      NOT taped measures zero and the run starts on the wall itself,
;;;      which is how a step that dies back into the wall is drawn.  The
;;;      two may be named in either order -- the marks say which way
;;;      round the run goes (below) -- and a tie, and only a tie, asks
;;;      for one click to settle it.
;;;   6. Last, the dimension style -- STANDARD INCHES or SIDE STANDARD,
;;;      the question PERPPTS and CPERPPTS ask in the same words.  It is
;;;      put only when there is a polyline to draw, so a pair of ends
;;;      with nothing between them is reported instead of being asked a
;;;      question it would throw away.
;;;   7. The polyline goes in on the perimeter's own layer and properties,
;;;      every circle is erased, and every line becomes a dimension in
;;;      that style on layer "DIMENSION".
;;;
;;; How the direction is found
;;;   Each mark's base point is the point of the perimeter closest to the
;;;   survey point.  The perimeter's tangent there, turned 90 degrees,
;;;   gives the two ways a mark could run, and the INSIDE of the pool
;;;   says which.  It is measured per mark rather than fixed once, so a
;;;   run of marks around a corner or along a radius each come off their
;;;   own piece of wall square.
;;;
;;;   A CLOSED wall defines its own inside, and that is what is used: the
;;;   direction the wall is drawn in (its signed area) turns the tangent
;;;   into the water at every point of it, whatever shape it is.  So the
;;;   pool is never asked about and cannot be answered wrongly.
;;;
;;;   It used to be one click -- "the centre of the pool" -- and one dot
;;;   product per mark.  That is right only for a shape with no notch in
;;;   it: on a narrow L or a keyhole a centre clicked in one lobe sits on
;;;   the wrong side of a wall in the other, and every mark there came out
;;;   backwards, pointing into the deck.  A closed wall is now read
;;;   instead of asked about, and the click survives only where there
;;;   genuinely is no inside -- an OPEN wall, a stretch of coping traced
;;;   on its own, where nothing but the drafter knows which side the water
;;;   is.  A closed wall that encloses nothing measurable (a doubled-back
;;;   trace, a figure-eight) falls back to the same click rather than
;;;   guessing from an area near zero.
;;;
;;; A distance that fights its neighbours
;;;   Three points in a row taped 40, 10 and 30 are not a wall: the wall
;;;   between a 40 and a 30 is about 35, and the 10 is a digit that went
;;;   in wrong.  When the round ends, any distance that sits against BOTH
;;;   its neighbours along the wall by more than pm:*spike-tol* is named,
;;;   with the number they put there -- and naming that point again
;;;   replaces its distance, which is the fix.  Nothing is changed for
;;;   the drafter: a surveyed value is the one thing a drawing tool may
;;;   not quietly overwrite.  A real curve says nothing, however hard it
;;;   bends -- 40, 38, 30 has every value between its neighbours, and it
;;;   is fighting both sides at once that marks a typo.
;;;
;;;   A mark whose far end lands outside a closed pool is named the same
;;;   way: the tape reached past the far wall, so either the number or
;;;   the point is wrong.
;;;
;;; The order the polyline runs in
;;;   Marks are kept with their STATION -- how far along the perimeter,
;;;   measured from its start, the base point sits -- so the polyline runs
;;;   along the wall in the order the wall does, whatever order the points
;;;   were named in.
;;;
;;;   What decides whether a run end IS one of the marks is the survey
;;;   point's own identity, never how close the two landed.  That is the
;;;   whole reason the pick is a point rather than a place: two shots a
;;;   quarter inch apart are still two shots, and the sheet says which.
;;;
;;; Which way round a closed wall -- and why it is not asked
;;;   Two ends cut a closed perimeter into two arcs, and the run is one
;;;   of them.  Which one is decided by the MARKS, not by the order the
;;;   two ends were named: every mark sits on exactly one arc, so the arc
;;;   carrying more of them is the run that was measured.  Naming the
;;;   ends the other way round therefore gives the same run, read from
;;;   whichever end was named first.
;;;
;;;   It used to go forward from the start station whatever was on the
;;;   way, so naming the ends the other way round sent the run round the
;;;   empty side of the pool and handed back a two-point line straight
;;;   across it, with every measurement left off.
;;;
;;;   The one case the marks cannot settle is a genuine tie -- the same
;;;   number on each arc -- and that is the only time the question is
;;;   put: one click on a spot the run passes through, which is a
;;;   direction like the centre click and not a datum.  A tie needs at
;;;   least two marks to be a tie, and marks that ARE the two ends do not
;;;   vote (an end sits on both arcs), so an ordinary run never sees it.
;;;
;;;   A mark the run does not reach is NAMED before the drawing is done
;;;   -- "Pt.7 and Pt.9 sit outside the run" -- and is still marked and
;;;   still dimensioned.  A measurement is the one thing that may never
;;;   go quietly missing.
;;;
;;; The ruler beside the distance
;;;   From the second distance on, DIMSTAMP's ruler stands near the
;;;   right edge of the view: the eighths of an inch for a whole inch
;;;   either side of the last distance, graded like a tape with the
;;;   last one ringed.  Click a row and that is the distance; type one
;;;   and it reads as DIMSTAMP reads (44, 44.5, 44-1/2, 3'8, 4'-4-1/2"
;;;   - kept exactly as typed, only the ruler rounds to the eighth; a
;;;   fraction is dashed, because the spacebar is Enter here and 44 1/2
;;;   would hand the 1/2 to the next question);
;;;   click empty space and it is the first of two points to measure
;;;   between, as getdist always offered.  Back means what it always
;;;   did.  The ruler is scratch on the marks layer, down when the
;;;   round ends or backs out of itself, and swept on every way out,
;;;   Esc included.  Its knobs are the pm:*ruler-* tunables.
;;;
;;; Properties
;;;   * Circles and lines land on layer "PERPMARK" (created if missing).
;;;     They are the run's working marks: keep them, turn the layer off,
;;;     or let step 5 clear them.
;;;   * The joined polyline takes the layer, colour, linetype, lineweight
;;;     and linetype scale of the perimeter it was measured off.
;;;   * Dimensions go on layer "DIMENSION" in the style picked at step 6
;;;     when the drawing has it; otherwise the current style is used and
;;;     a note is printed.
;;;
;;; Robustness
;;;   * The whole run is one UNDO group: a single U reverses all of it.
;;;   * Esc or an error at any prompt restores every system variable the
;;;     command changed (OSMODE, CMDECHO, CLAYER and the dimension style),
;;;     takes the ruler down and closes the UNDO group.
;;;   * A number nothing carries, a number two points share, a click on
;;;     nothing, a point the perimeter cannot be read under, and a centre
;;;     click that leaves the direction ambiguous all re-prompt where
;;;     they stand instead of guessing.
;;;   * All geometry is worked in WCS and converted at the edges, so the
;;;     command behaves under a rotated or shifted UCS.
;;;
;;; License: GPL-3.0-or-later
;;; ----------------------------------------------------------------------

(vl-load-com)

;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *perpmark-version* "v1.11")

;;; ----------------------------------------------------------------------
;;;  Tunables
;;; ----------------------------------------------------------------------

;; Layer the circles and the perpendicular lines are drawn on.  Change it
;; to put the run's working marks somewhere a plot style already hides.
(setq pm:*marklayer* "PERPMARK")

;; ACI colour that layer is CREATED with, on a drawing that lacks it.  A
;; number, not 'auto: these marks are the measurement record and are
;; meant to be seen, so they take a colour that reads on any background
;; rather than one that recedes into it.
(setq pm:*markcolor* 1)

;; Which answer step 4's "Draw a polyline through the marks?" question
;; takes on Enter: "Yes" joins the marks up and goes on to the ends and
;; the dimensions, "No" stops the round there and leaves every circle
;; and line standing on the marks layer.  Both words are still offered
;; and either can still be typed -- this only decides what tapping
;; Enter means.  Anything that is neither word is ignored and "Yes"
;; stands.
(setq pm:*join-default* "Yes")

;; Layer and creation colour for the dimensions step 6 leaves behind.
(setq pm:*dimlayer* "DIMENSION")
(setq pm:*dimcolor* 7)

;; The two dimension styles step 6 offers, and their order in the
;; question: STandard is the Enter answer.  PERPPTS and CPERPPTS ask the
;; same question in the same words, so a shop that renames a style
;; renames it here and the prompt follows -- the two KEYWORDS stay
;; STandard and SIde, which is the vocabulary all three share.  A
;; drawing that has neither keeps its current style and is told so.
(setq pm:*dimstyle-std*  "STANDARD INCHES")
(setq pm:*dimstyle-side* "SIDE STANDARD")

;; Which of the two styles above step 6's question takes on Enter --
;; "STandard" or "SIde", in any case.  A shop whose work is mostly side
;; dimensions stops re-typing SIde at every run; the question is asked
;; in the same words either way and both keywords are still offered.
;; Anything that is neither keyword is ignored and "STandard" stands.
(setq pm:*dimstyle-default* "STandard")

;; What counts as a survey point.  The classifier is the one BPCALLOUT,
;; CDCALLOUT, ABFIND and LHD share: change it in all of them or the
;; tools disagree about what the drawing holds.
(setq pm:*point-block* "ab_pt")    ; block name whose INSERTs mark
                                   ; points wherever they sit
(setq pm:*point-layer* "POINTS")   ; layer whose POINTs and INSERTs are
                                   ; always points, whatever block
(setq pm:*pt-tag* "number")        ; attribute tag on the point block
                                   ; naming the point.  A block without
                                   ; it lends its first attribute that
                                   ; reads as a number instead
(setq pm:*unknown* "?")            ; what a point with no readable
                                   ; number is called.  It can still be
                                   ; clicked; only a number can be typed
(setq pm:*pt-prefix* "Pt.")        ; how a point is named in the prompts
                                   ; and the report

;; A click within this of a survey point picks that point.  The number
;; typed at the same prompt never uses it -- a name is exact.  12.0 is
;; what BPCALLOUT and ABFIND snap at, so a drafter's aim carries between
;; the three.
(setq pm:*snap* 12.0)

;; Two points closer than this are one point: it keeps a zero-length
;; segment out of the joined polyline and a zero-length normal out of
;; the direction test.
(setq pm:*fuzz* 1e-6)

;; How far a distance has to sit against BOTH its neighbours along the
;; wall before the round names it: two inches.  A tape misread by less
;; than this is inside the noise a survey carries anyway; one misread by
;; more, in the direction neither neighbour agrees with, is a digit.
;; Raising it hides typos, lowering it starts naming real steps.
(setq pm:*spike-tol* 2.0)

;; The LENGTH RULER beside the distance prompt: from the second distance
;; on, DIMSTAMP's ruler stands near the right edge of the view -- the
;; eighths for an inch either side of the last distance, graded like a
;; tape, the last one ringed -- and a click on a row is the distance.
;; Scratch on the marks layer, taken down when the round ends and on
;; every way out.  Every size is a fraction of the current view, so the
;; ruler reads the same at any zoom.
(setq pm:*ruler-color* 3)          ; ACI colour of the rows you can PICK,
                                   ; carried on the entities themselves
(setq pm:*ruler-current-color* 7)  ; ACI colour of the ringed CURRENT
                                   ; row -- the last distance -- so it
                                   ; reads apart from the options; 7 is
                                   ; AutoCAD's black/white swap
(setq pm:*ruler-screen-x* 0.88)    ; where the spine sits across the
                                   ; view, as a fraction of its width in
                                   ; from the left; past 0.5 the rows
                                   ; reach left, short of it they reach
                                   ; right, so the ruler is always inside
                                   ; the view
(setq pm:*ruler-row-frac* 0.042)   ; one row's share of the view's
                                   ; height -- the ruler's size knob
(setq pm:*ruler-txt-frac* 0.5)     ; the biggest row label's height, as
                                   ; a fraction of the row spacing
(setq pm:*ruler-tick-frac* 0.6)    ; the longest tick, same measure
(setq pm:*ruler-ring-frac* 0.26)   ; the ring round the current row, as
                                   ; a fraction of the row spacing
(setq pm:*ruler-reach* 6.0)        ; how far inboard of the spine, in
                                   ; row spacings, a click still counts
                                   ; as picking a row rather than as the
                                   ; first point of a measured distance

;;; ----------------------------------------------------------------------
;;;  Vectors and angles
;;;  Copied from CALOFIN-LIB.lsp under this file's own prefix, so the
;;;  standalone file loads alone -- see STANDARDS.md section 4.
;;; ----------------------------------------------------------------------

;;; ----------------------------------------------------------------------
;;;  The perimeter, as segments
;;;
;;;  The wall is walked as a list of segments read off the entity itself
;;;  rather than through vlax-curve-*, for one reason: the polyline step 6
;;;  builds has to run along the wall in the wall's own order, and that
;;;  order is each mark's STATION -- the distance along the perimeter of
;;;  its base point.  A segment walk hands that back as a by-product of
;;;  the projection it is doing anyway, where vlax-curve-getDistAtPoint
;;;  would be a second COM round trip per mark with its own failure mode.
;;;
;;;  LINE, ARC, CIRCLE and LWPOLYLINE are what a pool perimeter is drawn
;;;  as in this tree -- ABHD, POOL and ADAB all leave an LWPOLYLINE, arc
;;;  segments and all.  Anything else (a SPLINE traced off a drone photo,
;;;  an ELLIPSE, an old heavy POLYLINE) is measured through vlax-curve-*
;;;  instead, by pm:project-com below.
;;;
;;;  A segment is one of:
;;;     (S p1 p2)              a straight run from p1 to p2
;;;     (A ctr rad a0 sweep)   an arc of rad about ctr, starting at angle
;;;                            a0 and sweeping SIGNED sweep radians --
;;;                            positive counterclockwise, which is the
;;;                            sign a positive bulge carries
;;;  Every point in one is WCS, because that is what entget hands back.
;;; ----------------------------------------------------------------------

;; The segment p1 -> p2 carrying polyline bulge b.  A bulge is
;; tan(included/4), so the included angle is 4*atan(b) and its sign is
;; the direction of travel; the centre sits half a chord away along the
;; chord's normal, by (chord/2)/tan(included/2).
(defun pm:mkseg (p1 p2 b / inc ch r th d cx cy ctr)
  (setq inc (* 4.0 (atan b))
        ch  (distance (cal:2d p1) (cal:2d p2)))
  (if (or (< (abs b) 1e-12)
          (< ch 1e-12)
          (< (abs (sin (/ inc 2.0))) 1e-12))
    (list 'S (cal:2d p1) (cal:2d p2))
    (progn
      (setq r   (abs (/ ch (* 2.0 (sin (/ inc 2.0)))))
            th  (angle (cal:2d p1) (cal:2d p2))
            d   (/ (/ ch 2.0) (cal:tan (/ inc 2.0)))
            cx  (+ (/ (+ (car p1) (car p2)) 2.0)
                   (* d (cos (+ th (/ pi 2.0)))))
            cy  (+ (/ (+ (cadr p1) (cadr p2)) 2.0)
                   (* d (sin (+ th (/ pi 2.0)))))
            ctr (list cx cy))
      (list 'A ctr r (angle ctr (cal:2d p1)) inc))))

;; The vertices of an LWPOLYLINE as (point bulge), in order.  entget
;; hands the groups back in order, so a 42 belongs to the 10 in front of
;; it; a vertex with no 42 carries no bulge.
(defun pm:lwverts (ed / vs g)
  (setq vs '())
  (foreach g ed
    (cond
      ((= 10 (car g)) (setq vs (cons (list (cal:2d (cdr g)) 0.0) vs)))
      ((and (= 42 (car g)) vs)
       (setq vs (cons (list (car (car vs)) (cdr g)) (cdr vs))))))
  (reverse vs))

;; EN as a list of segments, or nil when nothing here can read it.
(defun pm:segs (en / ed typ vs closed n i out a0 a1 sw v1 v2)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed))
        out '())
  (cond
    ((= typ "LINE")
     (list (list 'S (cal:2d (cdr (assoc 10 ed))) (cal:2d (cdr (assoc 11 ed))))))
    ((= typ "ARC")
     (setq a0 (cdr (assoc 50 ed))
           a1 (cdr (assoc 51 ed))
           sw (cal:angnorm (- a1 a0)))
     (if (< sw 1e-12) (setq sw (+ pi pi)))
     (list (list 'A (cal:2d (cdr (assoc 10 ed))) (cdr (assoc 40 ed)) a0 sw)))
    ((= typ "CIRCLE")
     (list (list 'A (cal:2d (cdr (assoc 10 ed))) (cdr (assoc 40 ed))
                 0.0 (+ pi pi))))
    ((= typ "LWPOLYLINE")
     (setq vs     (pm:lwverts ed)
           n      (length vs)
           closed (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
           i      0)
     (if (< n 2)
       nil
       (progn
         (while (< i (if closed n (1- n)))
           (setq v1  (nth i vs)
                 v2  (nth (rem (1+ i) n) vs)
                 out (cons (pm:mkseg (car v1) (car v2) (cadr v1)) out)
                 i   (1+ i)))
         (reverse out))))
    (t nil)))

(defun pm:seg-len (s)
  (if (eq (car s) 'S)
    (distance (cadr s) (caddr s))
    (* (caddr s) (abs (nth 4 s)))))

(defun pm:seg-start (s / ctr)
  (if (eq (car s) 'S)
    (cadr s)
    (progn
      (setq ctr (cadr s))
      (list (+ (car ctr)  (* (caddr s) (cos (nth 3 s))))
            (+ (cadr ctr) (* (caddr s) (sin (nth 3 s))))))))

(defun pm:seg-end (s / ctr a)
  (if (eq (car s) 'S)
    (caddr s)
    (progn
      (setq ctr (cadr s)
            a   (+ (nth 3 s) (nth 4 s)))
      (list (+ (car ctr)  (* (caddr s) (cos a)))
            (+ (cadr ctr) (* (caddr s) (sin a)))))))

;; The point of S closest to P.  A straight segment clamps the projection
;; to its ends; an arc takes the radial point when the direction of P
;; falls inside the sweep and the nearer end when it does not.
(defun pm:seg-closest (s p / a b d l t01 ctr r rel u)
  (setq p (cal:2d p))
  (if (eq (car s) 'S)
    (progn
      (setq a (cadr s)
            b (caddr s)
            d (cal:v- b a)
            l (cal:dot d d))
      (if (< l 1e-24)
        a
        (progn
          (setq t01 (/ (cal:dot (cal:v- p a) d) l))
          (cond ((< t01 0.0) (setq t01 0.0))
                ((> t01 1.0) (setq t01 1.0)))
          (cal:v+ a (cal:v* d t01)))))
    (progn
      (setq ctr (cadr s)
            r   (caddr s)
            u   (cal:unit (cal:v- p ctr)))
      (if (null u)
        (pm:seg-start s)
        (progn
          ;; how far into the sweep the direction of P lies, measured
          ;; the way the sweep runs
          (setq rel (cal:angnorm (* (if (< (nth 4 s) 0.0) -1.0 1.0)
                                   (- (angle ctr p) (nth 3 s)))))
          (if (<= rel (abs (nth 4 s)))
            (cal:v+ ctr (cal:v* u r))
            (if (< (distance p (pm:seg-start s))
                   (distance p (pm:seg-end s)))
              (pm:seg-start s)
              (pm:seg-end s))))))))

;; Unit tangent of S at Q (a point already on it), pointing the way the
;; segment travels.  nil on a segment with no length.
(defun pm:seg-tangent (s q / ctr rad)
  (if (eq (car s) 'S)
    (cal:unit (cal:v- (caddr s) (cadr s)))
    (progn
      (setq ctr (cadr s)
            rad (cal:unit (cal:v- q ctr)))
      (if (null rad)
        nil
        (cal:v* (cal:perp rad) (if (< (nth 4 s) 0.0) -1.0 1.0))))))

;; Arc length from the start of S to Q.
(defun pm:seg-station (s q / ctr rel)
  (if (eq (car s) 'S)
    (distance (cadr s) (cal:2d q))
    (progn
      (setq ctr (cadr s)
            rel (cal:angnorm (* (if (< (nth 4 s) 0.0) -1.0 1.0)
                               (- (angle ctr q) (nth 3 s)))))
      (if (> rel (abs (nth 4 s)))
        ;; past the far end: the clamp landed on one end or the other
        (if (< (distance (cal:2d q) (pm:seg-start s))
               (distance (cal:2d q) (pm:seg-end s)))
          0.0
          (pm:seg-len s))
        (* (caddr s) rel)))))

(defun pm:total (segs / tot s)
  (setq tot 0.0)
  (foreach s segs (setq tot (+ tot (pm:seg-len s))))
  tot)

;; T when the walk closes back on itself -- a circle, a closed polyline,
;; or a shape drawn open but ending where it started.
(defun pm:closed-p (segs)
  (and segs
       (< (distance (pm:seg-start (car segs))
                    (pm:seg-end (last segs)))
          1e-9)))

;; (base tangent station) for the point of SEGS closest to P, all WCS.
(defun pm:project (segs p / acc best bd s q d)
  (setq acc 0.0 best nil bd nil)
  (foreach s segs
    (setq q (pm:seg-closest s p)
          d (distance (cal:2d p) q))
    (if (or (null best) (< d bd))
      (setq best (list q (pm:seg-tangent s q) (+ acc (pm:seg-station s q)))
            bd   d))
    (setq acc (+ acc (pm:seg-len s))))
  (if (and best (cadr best)) best))

;;; ----------------------------------------------------------------------
;;;  The perimeter AutoCAD can measure but this file cannot read
;;;
;;;  A SPLINE, an ELLIPSE or a heavy POLYLINE has no segment list here,
;;;  so the same three numbers are asked of AutoCAD instead: the closest
;;;  point, the distance along to it, and the first derivative there for
;;;  the tangent.  Every call is caught -- a curve AutoCAD will not answer
;;;  for comes back nil and the pick is re-prompted, never half-measured.
;;; ----------------------------------------------------------------------

(defun pm:comcall (fn args / r)
  (setq r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r) nil r))

(defun pm:project-com (en p / q prm st dv tg)
  (setq q (pm:comcall 'vlax-curve-getClosestPointTo (list en (cal:2d p))))
  (if (null q)
    nil
    (progn
      (setq st  (pm:comcall 'vlax-curve-getDistAtPoint (list en q))
            prm (pm:comcall 'vlax-curve-getParamAtPoint (list en q)))
      (if (null prm)
        nil
        (progn
          (setq dv (pm:comcall 'vlax-curve-getFirstDeriv (list en prm))
                tg (if dv (cal:unit dv)))
          (if (or (null tg) (null st))
            nil
            (list (cal:2d q) tg st)))))))

;; Either reader, whichever this perimeter answers to.
(defun pm:locate (en segs p)
  (if segs (pm:project segs p) (pm:project-com en p)))

(defun pm:runlen (en segs / prm r)
  (if segs
    (pm:total segs)
    (progn
      (setq prm (pm:comcall 'vlax-curve-getEndParam (list en))
            r   (if prm (pm:comcall 'vlax-curve-getDistAtParam
                          (list en prm))))
      (if (numberp r) r 0.0))))

(defun pm:isclosed (en segs)
  (if segs
    (pm:closed-p segs)
    (if (pm:comcall 'vlax-curve-isClosed (list en)) T)))

;;; ----------------------------------------------------------------------
;;;  Lists
;;; ----------------------------------------------------------------------

;; LST sorted ascending on the car of each element, stably.  vl-sort is
;; not used on purpose: it DROPS items that compare equal, which here
;; would silently lose a mark that shares a station with another.
(defun pm:sortkey (lst / out e head)
  (setq out '())
  (foreach e lst
    (setq head '())
    (while (and out (<= (car (car out)) (car e)))
      (setq head (cons (car out) head)
            out  (cdr out)))
    (setq out (cons e out))
    (while head
      (setq out  (cons (car head) out)
            head (cdr head))))
  out)

;;; ----------------------------------------------------------------------
;;;  Layers and drawing
;;; ----------------------------------------------------------------------

(defun pm:circle (ctr r lay)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbCircle")
                  (cons 10 (list (car ctr) (cadr ctr) 0.0))
                  (cons 40 r))))

(defun pm:line (a b lay)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                  '(100 . "AcDbLine")
                  (cons 10 (list (car a) (cadr a) 0.0))
                  (cons 11 (list (car b) (cadr b) 0.0)))))

;; The groups that carry an entity's look, for the joined polyline to
;; inherit from the perimeter it was measured off.
(defun pm:props (ed / out g)
  (setq out '())
  (foreach g '(62 420 6 370 48)
    (if (assoc g ed) (setq out (cons (assoc g ed) out))))
  (reverse out))

(defun pm:pline (pts ed / e p)
  (setq e (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                        (cons 8 (cdr (assoc 8 ed))))
                  (pm:props ed)
                  (list '(100 . "AcDbPolyline")
                        (cons 90 (length pts)) '(70 . 0))))
  (foreach p pts
    (setq e (append e (list (cons 10 (list (car p) (cadr p)))))))
  (entmakex e))

(defun pm:erase (e)
  (if (and e (entget e)) (entdel e)))

;;; ----------------------------------------------------------------------
;;;  The survey points
;;;
;;;  A distance off the wall is taped AT a point -- one of the numbered
;;;  shots ABHD, CABHD and the rest of the family read -- so a point is
;;;  what this command marks, and its number is what names it.  The
;;;  classifier below is BPCALLOUT's, shared with CDCALLOUT, ABFIND and
;;;  LHD: an ab_pt INSERT wherever it sits, any other INSERT on the
;;;  POINTS layer, and a plain POINT on that layer.
;;;
;;;  A point with no readable number is carried as "?" rather than
;;;  dropped: it can be clicked like any other, it just cannot be typed.
;;; ----------------------------------------------------------------------

;; What the routine knows about one survey point: where it is, what it
;; is called, and the entity it is.  The entity is its IDENTITY -- it is
;; how a second pick of the same point is known to be a re-mark, and how
;; a run end is known to be a mark already made.
(defun pm:cd-pt (c) (car c))        ; (x y)
(defun pm:cd-nm (c) (cadr c))       ; "17"
(defun pm:cd-en (c) (caddr c))      ; the INSERT (or POINT) it was read from

;; "Pt.17", the way the prompts and the report name a point.
(defun pm:ptname (nm) (strcat pm:*pt-prefix* nm))

;; Every survey point in the drawing, as (position name entity).
;;
;; Model space only.  "_X" sweeps every layout too, so a survey-point
;; block pasted onto a sheet -- a key plan, a detail -- was a candidate
;; beside the real one: a typed number came back "two points are
;; numbered N", or a click was measured against paper-space numbers
;; that have nothing to do with the pool.
(defun pm:collect-points ( / ss i en ed typ p nm out)
  (setq out nil
        ss  (ssget "_X" '((0 . "INSERT,POINT") (410 . "Model"))))
  (if ss
    (progn
      (setq i 0)
      (repeat (sslength ss)
        (setq en  (ssname ss i)
              ed  (entget en)
              typ (cdr (assoc 0 ed))
              p   (cdr (assoc 10 ed))
              nm  nil)
        (cond
          ((= typ "INSERT")
           (if (or (= (strcase (cdr (assoc 2 ed)))
                      (strcase pm:*point-block*))
                   (= (strcase (cdr (assoc 8 ed)))
                      (strcase pm:*point-layer*)))
             (progn
               (setq nm (cal:block-number en pm:*pt-tag*))
               (setq out (cons (list (list (car p) (cadr p))
                                     (if (and nm (/= nm "")) nm pm:*unknown*)
                                     en)
                               out)))))
          ((= typ "POINT")
           (if (= (strcase (cdr (assoc 8 ed)))
                  (strcase pm:*point-layer*))
             (setq out (cons (list (list (car p) (cadr p)) pm:*unknown* en)
                             out)))))
        (setq i (1+ i)))))
  (reverse out))

;; The NUMBER a typed point name carries: the spelling with the spaces,
;; the hashes and the "Pt." prefix taken off, and nothing else touched.
;; Only the dot right after PT is a prefix dot - a point genuinely named
;; "40.5" keeps its decimal.  (ABFIND's abf:as-number.)
(defun pm:as-number (s / out i ch)
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
;; "#35" and "035" all meet in the middle.  (ABFIND's abf:canon.)
(defun pm:canon (s)
  (setq s (pm:as-number (strcase s)))
  (if (distof s 2)
    (rtos (distof s 2) 2 8)
    s))

;; The survey point nearest PK, when one sits within pm:*snap* of it.
(defun pm:nearest (pk cands / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (distance (cal:2d pk) (pm:cd-pt c)))
    (if (and (<= d pm:*snap*) (or (null bd) (< d bd)))
      (setq best c bd d)))
  best)

;; Every point whose number is the one typed.  More than one is a sheet
;; that numbers two points the same, and is asked about rather than
;; guessed at.
(defun pm:matches (s cands / want out c)
  (setq want (pm:canon s) out nil)
  (foreach c cands
    (if (= (pm:canon (pm:cd-nm c)) want) (setq out (cons c out))))
  (reverse out))

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

;; The ruler is laid out in the UCS -- VIEWCTR is a UCS point, and so
;; is every click the hit test reads -- and entmake takes the WORLD.
;; So each point goes through trans on its way into the drawing: under
;; a UCS whose origin a drafter has moved to the pool's corner, the
;; ruler was drawn that far away from the view it was measured off,
;; out of sight, while the prompt still answered clicks on the empty
;; strip where it should have been.

;;; -------------------- end of the length ruler -------------------------

;; This file's knobs, in the order the ruler reads them.
(defun pm:ruler-style ()
  (list pm:*ruler-color* pm:*ruler-current-color* pm:*ruler-screen-x*
        pm:*ruler-row-frac* pm:*ruler-txt-frac* pm:*ruler-tick-frac*
        pm:*ruler-ring-frac* pm:*ruler-reach*))

;;; ----------------------------------------------------------------------
;;;  Ask helpers
;;;  Copied from CALOFIN-LIB.lsp under this file's own prefix, so the
;;;  standalone file loads alone -- see STANDARDS.md section 4.
;;;  Back sentinel: CAL-BACK.
;;; ----------------------------------------------------------------------

;; The canonical spelling S stands for among KWS, in any case, or nil
;; for anything that is not one of them -- what a tunable default is
;; read through before it reaches a question, since the ask helpers
;; hand a default straight back on Enter without checking it, and
;; "side" typed into a settings box must not reach the style table
;; unspelled.
(defun pm:kw-canon (s kws / u out w)
  (setq u (if (= (type s) 'STR) (strcase s) ""))
  (foreach w kws
    (if (= u (strcase w)) (setq out w)))
  out)

;; A PLACE, in the current UCS -- the centre click, and nothing else in
;; this command.  Always required: Enter re-asks.  Returns the point or
;; CAL-BACK.  (A survey point is pm:askpoint below, which is a different
;; question: it names one of the drawing's own points.)
(defun pm:askpt (msg back / v)
  (if back (initget 1 "Back Undo") (initget 1))
  (setq v (getpoint (strcat "\n" msg (if back " [Back]" "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (if (and (= (type v) 'STR) (member v '("Back" "Undo"))) 'CAL-BACK v))

;; A survey point, clicked or typed.  One prompt takes both: (initget
;; 128) is arbitrary input, which hands typed text back from getpoint as
;; the string it is where a click comes back as the point it is.  The
;; misses are re-asked HERE rather than unwinding the caller's chain --
;; a number nothing carries and a click on nothing are typos, not
;; answers, and the question they belong to is this one.  tail is the
;; prose inside the angle brackets on a loop prompt whose Enter ends the
;; loop (nil = a point is required).  Returns the candidate, nil for
;; Enter, or CAL-BACK.
;;
;; A click comes back in the CURRENT UCS and the survey points are read
;; out of entget in WCS, so the click is carried into WCS before it is
;; measured against them.  Compared raw, a UCS moved off World matched
;; the click against the wrong numbers: the point under the crosshair
;; was "not there", or a different point was marked.
(defun pm:askpoint (msg tail back cands / v out done dupes)
  (setq done nil out nil)
  (while (not done)
    (if back
      (initget (if tail 128 129) "Back Undo")
      (initget (if tail 128 129)))
    (setq v (getpoint (strcat "\n" msg
                              (if back " [Back]" "")
                              (if tail (strcat " <" tail ">") "")
                              ": ")))
    (if lzd:ask (lzd:ask msg v) v)
    (cond
      ((null v)
       (if tail
         (setq out nil done T)
         (princ "\nA survey point is required - click one, or type its number.")))
      ((and (= (type v) 'STR) (member v '("Back" "Undo")))
       (setq out 'CAL-BACK done T))
      ((= (type v) 'STR)
       (setq dupes (pm:matches v cands))
       (cond
         ((null dupes)
          (princ (strcat "\nNo survey point is numbered \""
                         (pm:as-number v)
                         "\" - try again, or click the point itself.")))
         ((> (length dupes) 1)
          (princ (strcat "\n" (itoa (length dupes)) " points are numbered \""
                         (pm:as-number v)
                         "\" - click the one you mean.")))
         (t (setq out (car dupes) done T))))
      (t
       (setq out (pm:nearest (trans v 1 0) cands))
       (if out
         (setq done T)
         (princ (strcat "\nNo survey point there - click one, or type"
                        " its number."))))))
  out)

;;; ----------------------------------------------------------------------
;;;  System variables
;;; ----------------------------------------------------------------------


;; OSMODE is deliberately NOT in this list.  PERPMARK never
;; changes it, and a list is a promise to WRITE the value back: the run
;; would put its opening snapshot back over any snap the drafter ticked
;; on while it was up -- on a clean exit, with no error involved, which
;; is the likeliest way anyone meets it.  Borrow only what you move.
(defun pm:sysvars () '("CMDECHO" "CLAYER"))

;;; ----------------------------------------------------------------------
;;;  The marks
;;;
;;;  One mark is (station base offs dist circle line name ent):
;;;    station  how far along the perimeter its base point sits
;;;    base     the point ON the perimeter the tape was run from
;;;    offs     where the tape reached -- base + dist square off the wall
;;;    dist     the measurement (0.0 for a run end that was never taped)
;;;    circle   the swing of the tape, an ename (nil on a zero station)
;;;    line     the measurement itself, an ename (nil on a zero station)
;;;    name     the survey point's number, for the prompts and the report
;;;    ent      the survey point itself, which is the mark's IDENTITY:
;;;             picking that point again is a re-mark, and naming it at
;;;             a run end is naming this mark
;;; ----------------------------------------------------------------------

;; A run end at a point that was never taped: it sits ON the wall, so
;; its offset is its base and it carries no circle and no line.
(defun pm:mk-station (station base name ent)
  (list station base base 0.0 nil nil name ent))

(defun pm:m-station (m) (car m))
(defun pm:m-base (m) (cadr m))
(defun pm:m-offs (m) (caddr m))
(defun pm:m-dist (m) (nth 3 m))
(defun pm:m-circle (m) (nth 4 m))
(defun pm:m-line (m) (nth 5 m))
(defun pm:m-name (m) (nth 6 m))
(defun pm:m-ent (m) (nth 7 m))

;; Which way a mark at BASE runs: square off the wall, into the pool.
;; SGN is the closed wall's own answer -- the sign that turns a tangent
;; inward, from the loop's orientation -- and when it is known nothing
;; else is consulted.  CTR is the fallback for an open wall, which has
;; no inside: the mark runs toward the side that click was on.  nil when
;; the tangent is unreadable, or when an open wall's click leaves the
;; two sides tied -- both are re-prompts, never a guess.
(defun pm:inward (tg base ctr sgn / n side)
  (setq n (if tg (cal:unit (cal:perp tg))))
  (cond
    ((null n) nil)
    ;; pm:perp turns 90 degrees counterclockwise, so on a wall drawn
    ;; counterclockwise (positive area, sgn 1.0) the left-hand normal
    ;; already points into the water; a wall drawn the other way round
    ;; carries -1.0 and the same line flips it.  ABHD's hopper and slope
    ;; lines have been built on this same sign for as long as they have
    ;; existed.
    (sgn (cal:v* n sgn))
    ((null ctr) nil)
    (t
     (setq side (cal:dot n (cal:v- ctr base)))
     (cond ((> side  pm:*fuzz*) n)
           ((< side (- pm:*fuzz*)) (cal:v* n -1.0))
           (t nil)))))

;;; ----------------------------------------------------------------------
;;;  The inside of the pool
;;;  Copied from CALOFIN-LIB.lsp under this file's own prefix, so the
;;;  standalone file loads alone -- see STANDARDS.md section 4.
;;; ----------------------------------------------------------------------

;; The perimeter as a polygon, for the two tests above: every segment's
;; start point, with an arc broken into chords about five degrees apart
;; so a position near a curved wall is placed on the right side of it.
;; A wall this file reads as segments is sampled from them; anything
;; else (a SPLINE traced off a drone photo, an ELLIPSE) is walked
;; through vlax-curve-* the same way its stations are.
(defun pm:sample-loop (segs / out s ctr r a0 sw n k a)
  (setq out nil)
  (foreach s segs
    (if (eq (car s) 'S)
      (setq out (cons (cadr s) out))
      (progn
        (setq ctr (cadr s)
              r   (caddr s)
              a0  (nth 3 s)
              sw  (nth 4 s)
              n   (max 2 (fix (+ 1.0 (/ (abs sw) 0.0873))))
              k   0)
        (while (< k n)
          (setq a   (+ a0 (* sw (/ (float k) (float n))))
                out (cons (list (+ (car ctr)  (* r (cos a)))
                                (+ (cadr ctr) (* r (sin a))))
                          out)
                k   (1+ k))))))
  (reverse out))

(defun pm:sample-com (en tot / out n k d p)
  (setq out nil n 180 k 0)
  (while (< k n)
    (setq d (* tot (/ (float k) (float n)))
          p (pm:comcall 'vlax-curve-getPointAtDist (list en d)))
    (if p (setq out (cons (cal:2d p) out)))
    (setq k (1+ k)))
  (reverse out))

;; The closed wall as a polygon, however this file can read it; nil when
;; the wall is open or nothing usable came back.
(defun pm:wall-loop (en segs closed tot / out)
  (if (not closed)
    nil
    (progn
      (setq out (if segs (pm:sample-loop segs) (pm:sample-com en tot)))
      (if (and out (> (length out) 2)) out))))

;; d wrapped into [0, tot) -- how far FORWARD along a closed perimeter,
;; so a run that crosses the polyline's own seam is one stretch and not
;; two.
(defun pm:wrap (d tot)
  (if (< tot 1e-12)
    0.0
    (progn
      (while (< d 0.0) (setq d (+ d tot)))
      (while (>= d tot) (setq d (- d tot)))
      d)))

;; The marks the run passes through, in the order the wall runs.
;;
;; s0 and s1 are the run's ends.  On an OPEN perimeter there is one
;; stretch between them and that is the run, read from s0 toward s1.  On
;; a CLOSED one there are two arcs, and BACK says which: nil walks
;; forward from s0 (wrapping past the polyline's own seam if that is the
;; way the ends point), T walks the other way round.  Either way the run
;; is handed back starting at s0, because that is the end the drafter
;; named first.
(defun pm:span (marks s0 s1 closed tot back / out m k span)
  (setq out '())
  (cond
    ((and closed back)
     ;; the far arc: how far each mark sits FORWARD of s1, turned round
     ;; so the run still reads from s0
     (setq span (pm:wrap (- s0 s1) tot))
     (foreach m marks
       (setq k (pm:wrap (- (pm:m-station m) s1) tot))
       (if (<= k (+ span pm:*fuzz*))
         (setq out (cons (cons (- span k) m) out)))))
    (closed
     (setq span (pm:wrap (- s1 s0) tot))
     (foreach m marks
       (setq k (pm:wrap (- (pm:m-station m) s0) tot))
       (if (<= k (+ span pm:*fuzz*)) (setq out (cons (cons k m) out)))))
    (t
     (foreach m marks
       (setq k (- (pm:m-station m) s0))
       (if (< s1 s0) (setq k (- k)))
       (if (and (>= k (- pm:*fuzz*))
                (<= k (+ (abs (- s1 s0)) pm:*fuzz*)))
         (setq out (cons (cons k m) out))))))
  (mapcar 'cdr (pm:sortkey out)))

;; Which way round a CLOSED perimeter the run goes, decided by the MARKS
;; rather than by the order the two ends happened to be named.
;;
;; Two ends cut a closed wall into two arcs and every mark sits on
;; exactly one of them, so the arc carrying more of them is the run the
;; drafter measured: naming the ends the other way round used to send the
;; run the other way and quietly leave every mark off it.  Returns nil
;; for the near arc (forward from s0), T for the far one, and 'ASK when
;; the two arcs hold the same number and nothing here can choose.
;;
;; A mark AT one of the ends is the end, not a vote: it sits on both
;; arcs and would only ever pad the count.
(defun pm:whichway (marks s0 s1 tot m0 m1 / near far span m k)
  (setq span (pm:wrap (- s1 s0) tot) near 0 far 0)
  (foreach m marks
    (if (not (or (eq (pm:m-ent m) (pm:m-ent m0))
                 (eq (pm:m-ent m) (pm:m-ent m1))))
      (progn
        (setq k (pm:wrap (- (pm:m-station m) s0) tot))
        (if (<= k (+ span pm:*fuzz*))
          (setq near (1+ near))
          (setq far (1+ far))))))
  (cond ((> near far) nil)
        ((> far near) T)
        ;; nothing to place: every mark IS one of the two ends, so both
        ;; arcs give the same two-point run and there is nothing to ask
        ((= 0 near) nil)
        (t 'ASK)))

;; T when station ST sits on the FAR arc -- the answer the middle click
;; gives when the marks could not.
(defun pm:far-side-p (st s0 s1 tot)
  (> (pm:wrap (- st s0) tot) (+ (pm:wrap (- s1 s0) tot) pm:*fuzz*)))

;; The marks the run does not pass through, named in the order they were
;; taped, so a measurement is never quietly left off the drawing.
(defun pm:left-out (marks run / out m r hit)
  (setq out '())
  (foreach m (reverse marks)
    (setq hit nil)
    (foreach r run
      (if (eq (pm:m-ent r) (pm:m-ent m)) (setq hit T)))
    (if (not hit) (setq out (cons (pm:ptname (pm:m-name m)) out))))
  (reverse out))

;; "Pt.7", "Pt.7 and Pt.9", "Pt.7, Pt.9 and Pt.12".
(defun pm:andjoin (l last / n i out k)
  (setq n (length l) i 0 out "")
  (foreach k l
    (setq i (1+ i)
          out (cond ((= i 1) k)
                    ((and last (= i n)) (strcat out " and " k))
                    (t (strcat out ", " k)))))
  out)

;; What a run end names.  A point that was taped is the mark that was
;; made at it, so the run starts where the tape reached; a point that
;; was NOT taped is a station of its own measuring zero, which is how a
;; step that dies back into the wall is drawn.  It is the point's own
;; identity that decides which, never how close the two landed -- that
;; is the whole reason the pick is a point rather than a place.  nil
;; when the perimeter cannot be read under it at all.
;; The mark made at survey point ENT, when one was made.
(defun pm:marked-at (marks ent / hit m)
  (setq hit nil)
  (foreach m marks
    (if (eq (pm:m-ent m) ent) (setq hit m)))
  hit)

(defun pm:runend (en segs marks cand / hit loc)
  (setq hit (pm:marked-at marks (pm:cd-en cand)))
  (if hit
    hit
    (progn
      (setq loc (pm:locate en segs (pm:cd-pt cand)))
      (if loc
        (pm:mk-station (caddr loc) (car loc)
                       (pm:cd-nm cand) (pm:cd-en cand))))))

;; MARKS with the one made at ENT taken out, its circle and its line
;; erased with it.  Picking a point a second time is a correction, not a
;; second mark: the sheet has one distance at that point.
(defun pm:unmark (marks ent / out m)
  (setq out '())
  (foreach m marks
    (if (eq (pm:m-ent m) ent)
      (progn (pm:erase (pm:m-circle m)) (pm:erase (pm:m-line m)))
      (setq out (cons m out))))
  (reverse out))

;; PTS with each point that repeats its predecessor dropped, so the
;; joined polyline never carries a zero-length segment.  Consecutive-only
;; on purpose: two marks the same distance apart at opposite ends of the
;; pool are two marks, and cal:dedupe's any-kept-one test would drop one
;; of them.
(defun pm:dedupe (pts / out p)
  (setq out '())
  (foreach p pts
    (if (or (null out) (> (distance p (car out)) pm:*fuzz*))
      (setq out (cons p out))))
  (reverse out))

;; A taped distance, written the way the tape read it.
(defun pm:fmt (v) (rtos v 2 2))

;; What the round has to say about itself, once the last distance is in
;; and before anything is drawn or erased.  Two things, both advisory:
;; a distance that fights BOTH its neighbours along the wall (the digit
;; that went in wrong), and a mark whose far end lands outside a closed
;; pool (a tape that reached past the far wall).  Every mark is kept and
;; drawn either way -- the drafter is the one who knows whether 10 was
;; the number -- and both messages name the point, because naming a
;; point again is what replaces its distance.
(defun pm:review (marks poly / ord pairs sp e m a c out n)
  (setq ord   (mapcar 'cdr
                (pm:sortkey (mapcar '(lambda (m) (cons (pm:m-station m) m))
                                    marks)))
        pairs (mapcar '(lambda (m) (cons (pm:m-station m) (pm:m-dist m)))
                      ord)
        sp    (cal:spikes pairs pm:*spike-tol*))
  (foreach e sp
    (setq m (nth (car e) ord)
          a (nth (1- (car e)) ord)
          c (nth (1+ (car e)) ord))
    (princ (strcat "
" (pm:ptname (pm:m-name m)) " measures "
                   (pm:fmt (pm:m-dist m)) ", against "
                   (pm:ptname (pm:m-name a)) " ("
                   (pm:fmt (pm:m-dist a)) ") and "
                   (pm:ptname (pm:m-name c)) " ("
                   (pm:fmt (pm:m-dist c))
                   ") on both sides - the wall between them is about "
                   (pm:fmt (cdr e)) "."))
    (princ (strcat "
  If that is a digit, name "
                   (pm:ptname (pm:m-name m))
                   " again and the new distance replaces it.")))
  ;; a mark that left the pool: only a closed wall has an outside to
  ;; land in, and only a mark that measured something can reach it
  (if poly
    (progn
      (setq out nil)
      (foreach m (reverse marks)
        (if (and (> (pm:m-dist m) pm:*fuzz*)
                 (not (cal:in-loop-p (pm:m-offs m) poly)))
          (setq out (cons (pm:ptname (pm:m-name m)) out))))
      (setq out (reverse out)
            n   (length out))
      (if out
        (princ (strcat "
" (pm:andjoin out T)
                       (if (= n 1) " reaches" " reach")
                       " past the far wall - that tape would have left"
                       " the pool.  The mark"
                       (if (= n 1) " is" "s are")
                       " drawn; check the sheet.")))))
  (princ))

;; Every mark that measured something, dimensioned where its line was,
;; in the STYLE the drafter picked.  Returns how many went in.  The
;; style is restored by the caller -- it is one of the settings the
;; *error* handler owes the user.
(defun pm:dimension (marks style / n m)
  (setq n 0)
  (setvar "CLAYER" (cal:ensure-layer pm:*dimlayer* pm:*dimcolor*))
  (if (tblsearch "DIMSTYLE" style)
    (command "_.-DIMSTYLE" "_Restore" style)
    (princ (strcat "\nDimension style \"" style
                   "\" is not in this drawing - using the current style"
                   " instead.")))
  (foreach m (reverse marks)
    (if (> (pm:m-dist m) pm:*fuzz*)
      (progn
        ;; command arguments are read in the CURRENT UCS, and every mark
        ;; has been carried in WCS since the pick that made it.  _non on
        ;; each: PERPMARK leaves the drafter's OSMODE alone, so a running
        ;; Endpoint or Nearest would otherwise pull the wall foot or the
        ;; mark onto whatever is near it -- a taped distance, dimensioned
        ;; wrong, with nothing on screen to say so
        (command "_.DIMALIGNED"
                 "_non" (trans (pm:m-base m) 0 1)
                 "_non" (trans (pm:m-offs m) 0 1)
                 "_non" (trans (pm:m-offs m) 0 1))
        (setq n (1+ n)))))
  n)

;;; ----------------------------------------------------------------------
;;;  Commands
;;; ----------------------------------------------------------------------

;; ahead of the command on purpose: the structural test scans from
;; c:PERPMARK to end-of-file for leaked variables, and a defun name there
;; would read as one
(defun c:PERPMARKVER ()
  (princ (strcat "\nPERPMARK " *perpmark-version*))
  (princ))

(defun c:PERPMARK (/ *error* undo-open
                     sel en ed segs tot closed ctr pick cand cands loc
                     base tg nrm d ans marks stage done pts run s0 s1
                     m0 m1 way wayasked miss sty lay odim ndims npts m
                     poly sgn rl rr lastd)

  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:sysrestore)
    (if rl (setq rl (cal:ruler-off rl)))
    ;; DIMSTYLE cannot be setvar'd back
    (if (and odim (tblsearch "DIMSTYLE" odim))
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" odim)))
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nPERPMARK error: " msg)))
    (if lzd:report (lzd:report "PERPMARK" *perpmark-version* msg))
    (princ))

  (if lzd:begin (lzd:begin "PERPMARK" *perpmark-version*))
  (cal:syssave (pm:sysvars))
  (setvar "CMDECHO" 0)
  ;; one group for the whole run -- the marks are drawn as they are
  ;; answered, so anything less would take one U per circle
  (setq undo-open (cal:undobegin)
        odim      (getvar "DIMSTYLE")
        marks     '()
        stage     1
        done      nil
        lastd     nil
        ;; the length ruler, not up yet: it stands beside the distance
        ;; prompt from the second distance on, on the marks layer
        rl        (cal:ruler-new pm:*marklayer* (pm:ruler-style)))

  (while (not done)
    (cond

      ;; --- 1. the perimeter the distances were taped off ---------------
      ((= stage 1)
       (setq sel (entsel "\nSelect the pool perimeter: "))
       (if lzd:ask (lzd:ask "\nSelect the pool perimeter: " sel) sel)
       (if lzd:watch (lzd:watch sel) sel)
       (cond
         ((null sel)
          (princ "\nNothing selected - try again, or press Esc to quit."))
         (t
          (setq en   (car sel)
                ed   (entget en)
                segs (pm:segs en)
                tot  (pm:runlen en segs))
          (cond
            ((and (null segs)
                  (null (pm:project-com en (cal:2d (trans (cadr sel) 1 0)))))
             (princ (strcat "\nA " (cdr (assoc 0 ed))
                            " is not something PERPMARK can measure along"
                            " - select the pool wall.")))
            ((< tot 1e-9)
             (princ "\nThat perimeter has no length."))
            (t
             ;; a closed wall defines its own inside, and that is the
             ;; whole of the direction question; only an open one -- or
             ;; a closed one that encloses nothing measurable -- has to
             ;; be asked which side the water is on
             (setq closed (pm:isclosed en segs)
                   poly   (pm:wall-loop en segs closed tot)
                   sgn    (if poly (cal:inward-sign poly))
                   ctr    nil
                   cands  (pm:collect-points))
             (if (null cands)
               (progn
                 (princ (strcat "\nNo survey points in this drawing -"
                                " PERPMARK marks the distances taped at"
                                " the numbered points ABHD and its family"
                                " read."))
                 (setq done T))
               (progn
                 (princ (strcat "\n" (itoa (length cands))
                                " survey point(s) found."))
                 (if sgn
                   (princ (strcat "\nThe wall closes, so its own inside"
                                  " is which way a mark runs - nothing"
                                  " to click.")))
                 (setq stage (if sgn 3 2)))))))))

      ;; --- 2. which side the water is on, asked only when the wall
      ;;        cannot say: an open stretch of coping, or a closed trace
      ;;        that doubles back and encloses nothing --------------------
      ((= stage 2)
       (princ (if closed
                (strcat "\nThis wall closes but encloses nothing"
                        " measurable, so its own inside cannot be read.")
                (strcat "\nThis wall does not close, so nothing in it says"
                        " which side the pool is on.")))
       (princ (strcat "\nA mark runs square off the wall, toward the side"
                      " you click."))
       (setq pick (pm:askpt "Click a spot inside the pool" T))
       (cond
         ((eq pick 'CAL-BACK) (setq stage 1))
         ((null pick)
          (princ "\nA point is required - click the side the pool is on."))
         (t (setq ctr   (cal:2d (trans pick 1 0))
                  stage 3))))

      ;; --- 3. name a survey point.  Enter ends the round; Back takes
      ;;        the last mark away again, and at the first one re-opens
      ;;        whichever question came before it ------------------------
      ((= stage 3)
       (setq cand (pm:askpoint "Pick a survey point, or type its number"
                               "Enter = done" T cands))
       (cond
         ((eq cand 'CAL-BACK)
          (cond
            ((null marks)
             (setq rl (cal:ruler-off rl))
             (princ "\nStepping back one question.")
             ;; the side question is only there on a wall that needed it
             (setq stage (if sgn 1 2)))
            (t
             (princ (strcat "\nStepping back one point - "
                            (pm:ptname (pm:m-name (car marks))) " undone."))
             (setq marks (pm:unmark marks (pm:m-ent (car marks)))))))
         ((null cand)
          (setq rl (cal:ruler-off rl))
          (if (null marks)
            (progn (princ "\nNothing marked.") (setq done T))
            (progn (pm:review marks poly) (setq stage 4))))
         (t
          (setq loc (pm:locate en segs (pm:cd-pt cand)))
          (cond
            ((null loc)
             (princ (strcat "\nThe perimeter cannot be read under "
                            (pm:ptname (pm:cd-nm cand))
                            " - pick a point nearer the wall.")))
            (t
             (setq base (car loc)
                   tg   (cadr loc)
                   nrm  (pm:inward tg base ctr sgn))
             (if (null nrm)
               (princ (strcat "\nWhich side the mark runs to cannot be"
                              " read at " (pm:ptname (pm:cd-nm cand))
                              " - the wall has no direction there, or the"
                              " side you clicked lines up with it."
                              "  Back at the first point re-opens the"
                              " question before this one."))
               (setq stage 31)))))))

      ;; --- 3b. and the distance taped off it.  From the second one on
      ;;        the length ruler stands beside the prompt, round the
      ;;        last distance given: a click on a row IS the distance ---
      ((= stage 31)
       (setq rl (cal:ruler-show rl lastd nil)
             rr (cal:ask-len (strcat "\nDistance from the perimeter at "
                                    (pm:ptname (pm:cd-nm cand))
                                    " [Back]: ")
                            "Back Undo" rl nil)
             d  (car rr)
             rl (cadr rr))
       (cond
         ((= (type d) 'STR) (setq stage 3))          ; Back, or Undo
         ((null d)
          (princ "\nA distance is required - type it, or click a ruler row."))
         (t
          (setq lastd d)
          (if (null lay)
            (setq lay (cal:ensure-layer pm:*marklayer* pm:*markcolor*)))
          ;; a point picked twice is the sheet being corrected, not two
          ;; marks at one shot: the older one goes
          (if (pm:marked-at marks (pm:cd-en cand))
            (progn
              (princ (strcat "\n" (pm:ptname (pm:cd-nm cand))
                             " re-marked - the first distance goes."))
              (setq marks (pm:unmark marks (pm:cd-en cand)))))
          (setq marks (cons (list (caddr loc) base
                                  (cal:v+ base (cal:v* nrm d)) d
                                  (pm:circle base d lay)
                                  (pm:line base (cal:v+ base (cal:v* nrm d))
                                           lay)
                                  (pm:cd-nm cand) (pm:cd-en cand))
                            marks)
                stage 3))))

      ;; --- 4. join them up? -------------------------------------------
      ((= stage 4)
       (setq ans (cal:askyn "Draw a polyline through the marks?"
                           (cond ((pm:kw-canon pm:*join-default* '("Yes" "No")))
                                 ("Yes"))
                           T))
       (cond
         ((eq ans 'CAL-BACK) (setq stage 3))
         ((null ans)
          (princ (strcat "\n" (itoa (length marks)) " mark(s) left on layer"
                         " \"" pm:*marklayer* "\" - circles and lines both."))
          (setq done T))
         (t (setq stage 5))))

      ;; --- 5 and 6. where the run starts, and where it ends ------------
      ((= stage 5)
       (setq cand (pm:askpoint
                    "The point the run starts at, or type its number"
                    nil T cands))
       (cond
         ((eq cand 'CAL-BACK) (setq stage 4))
         (t
          (setq m0 (pm:runend en segs marks cand))
          (if (null m0)
            (princ (strcat "\nThe perimeter cannot be read under "
                           (pm:ptname (pm:cd-nm cand))
                           " - pick a point nearer the wall."))
            (setq stage 6)))))

      ((= stage 6)
       (setq cand (pm:askpoint
                    "The point the run ends at, or type its number"
                    nil T cands))
       (cond
         ((eq cand 'CAL-BACK) (setq stage 5))
         (t
          (setq m1 (pm:runend en segs marks cand))
          (cond
            ((null m1)
             (princ (strcat "\nThe perimeter cannot be read under "
                            (pm:ptname (pm:cd-nm cand))
                            " - pick a point nearer the wall.")))
            (t
             (setq s0 (pm:m-station m0)
                   s1 (pm:m-station m1))
             ;; which way round: the marks decide it wherever they can,
             ;; so the two ends can be named in either order
             (setq way (if closed
                         (pm:whichway marks s0 s1 tot m0 m1)
                         nil))
             ;; the style question sits behind whichever of these two was
             ;; the last one actually put (STANDARDS section 3: a chain
             ;; with a conditional step carries its direction)
             (setq wayasked (eq way 'ASK))
             (if wayasked (setq stage 7) (setq stage 8)))))))

      ;; --- 7. the two arcs hold the same number of marks, so only the
      ;;        drafter can say which way the run passes ---------------
      ((= stage 7)
       (princ (strcat "\nThe run's two ends cut the wall in half and each"
                      " half carries the same number of marks, so which"
                      " way round it goes is yours to say."))
       (setq pick (pm:askpt "Click a spot the run passes through" T))
       (cond
         ((eq pick 'CAL-BACK) (setq stage 6))
         (t
          (setq loc (pm:locate en segs (cal:2d (trans pick 1 0))))
          (if (null loc)
            (princ (strcat "\nThe perimeter cannot be read there - click"
                           " nearer the wall, on the side the run runs."))
            (setq way   (pm:far-side-p (caddr loc) s0 s1 tot)
                  stage 8)))))

      ;; --- 8. which dimension style, the question PERPPTS and CPERPPTS
      ;;        ask in the same words.  The run is worked out FIRST, so a
      ;;        pair of ends with nothing between them is reported
      ;;        instead of being asked a question it would throw away ---
      ((= stage 8)
       (setq run  (pm:span (append (list m0 m1) marks) s0 s1 closed tot way)
             pts  (pm:dedupe (mapcar 'pm:m-offs run))
             miss (pm:left-out marks run))
       (cond
         ((< (length pts) 2)
          (princ (strcat "\nThose two ends enclose fewer than two marks,"
                         " so there is no polyline to draw - nothing was"
                         " erased."))
          (setq done T))
         (t
          (setq ans (cal:askkw (strcat "Dimension style - " pm:*dimstyle-std*
                                      " or " pm:*dimstyle-side* "?")
                              "STandard SIde" "STandard/SIde"
                              (cond ((pm:kw-canon pm:*dimstyle-default*
                                                  '("STandard" "SIde")))
                                    ("STandard"))
                              T))
          (cond
            ((eq ans 'CAL-BACK) (setq stage (if wayasked 7 6)))
            (t (setq sty   (if (= ans "SIde") pm:*dimstyle-side*
                             pm:*dimstyle-std*)
                     stage 9))))))

      ;; --- 9. draw it ------------------------------------------------
      ((= stage 9)
       (pm:pline pts ed)
       (setq npts (length pts))
       ;; --- the circles go, the lines become dimensions ---------------
       (foreach m marks
         (pm:erase (pm:m-circle m))
         (pm:erase (pm:m-line m)))
       (setq ndims (pm:dimension marks sty))
       ;; a measurement left off the polyline is SAID, never dropped
       ;; quietly: it is still marked and still dimensioned, and the
       ;; drafter is the one who decides whether that is what they meant
       (if miss
         (princ (strcat "\n" (pm:andjoin miss T)
                        (if (= 1 (length miss)) " sits" " sit")
                        " outside the run - still dimensioned, but not"
                        " joined.")))
       (princ (strcat "\nDone: a " (itoa npts)
                      "-point polyline on layer \""
                      (cdr (assoc 8 ed)) "\", "
                      (itoa (length marks))
                      " circle(s) erased and " (itoa ndims)
                      " dimension(s) on layer \"" pm:*dimlayer*
                      "\" in \"" sty "\"."))
       (setq done T))))

  ;; only when pm:dimension moved it: a run answered No never touched the
  ;; style, and restoring it to itself is a command line nobody asked for
  (if (and odim (/= odim (getvar "DIMSTYLE")) (tblsearch "DIMSTYLE" odim))
    (command "_.-DIMSTYLE" "_Restore" odim))
  (if undo-open (setq undo-open (cal:undoend)))
  (if rl (setq rl (cal:ruler-off rl)))
  (cal:sysrestore)
  (if lzd:end (lzd:end "PERPMARK"))
  (princ))

(if (not *calofin-quiet*)
  (princ (strcat "\nPERPMARK " *perpmark-version*
                 " loaded.  Type PERPMARK to run.")))
(princ)
