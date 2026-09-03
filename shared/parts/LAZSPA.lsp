;;; ======================================================================
;;; LAZSPA.lsp  --  fill a spa dimension chart in, then draw the spa
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZSPA         fill in a spa chart and run SPA from it
;;;            LAZSPAVER      print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; What LAZFORM is to POOL, this is to SPA.  SPA grew an answer store
;;; this week -- spa:*form*, spa:run-with-answers, and the hooks in its
;;; ask helpers -- and nothing in AutoCAD could drive it: the VB palette
;;; in ui/ needs a DLL NETLOADed on every machine.  LAZFORM proved a
;;; plain DCL chart can drive POOL with nothing to install, so this is
;;; that chart for SPA.
;;;
;;; The chart on screen is the one off the order sheet: the outline, the
;;; dimension chain and its letters.  Type a number against a letter and
;;; the letter is REPLACED by what you typed -- which is what the letter
;;; was standing in for all along.  Fill in what you know, leave the
;;; rest blank, press Insert: SPA runs and asks only for the gaps.
;;;
;;; NA in a box means "not measured" and is passed through as such --
;;; different from leaving it blank, which just means SPA should ask.
;;;
;;; THE FORM SAYS WHAT IT IS ABOUT TO DO.  SPA has two ways of dropping
;;; a box unread: lzs:answer cannot read it, or lzs:keyanswer demotes an
;;; NA on a key SPA has no NA for -- and NA is a word this very form
;;; tells you to type.  Either way the chart went on showing what was
;;; typed, so the box looked answered.  A state line under the form now
;;; names both, and Insert stays greyed until they are fixed; when
;;; neither is there, the same line says how much is filled and what SPA
;;; will still ask for.  It reports what lzs:form is about to send, so
;;; the line and the alist cannot say different things.
;;;
;;; ZERO INSTALL, like LAZFORM and LAZPANEL: the dialog is plain DCL
;;; written to the temp folder at run time, and the chart is drawn with
;;; vector_image, so there is no artwork file to ship and nothing to
;;; NETLOAD.
;;;
;;; WHY THE BOXES ARE BESIDE AND INSIDE THE PICTURE, NEVER ON IT.  DCL
;;; packs tiles into rows and columns: no absolute positioning, no
;;; overlapping, no z-order, so an edit box cannot sit on an image tile
;;; -- and DCL cannot display a raster at all, an image tile takes
;;; vectors or an AutoCAD slide and nothing else.  So the chart is
;;; DRAWN, and cut into horizontal bands at the heights where its
;;; across dimensions run; those rows are real edit boxes wedged
;;; between the bands, pushed to their letters' positions by spacers.
;;; The dimensions that run UP cannot be wedged -- a box cannot stand
;;; sideways in a row -- so they keep boxes in the side column and what
;;; is typed there is drawn onto the chart in the letter's place.
;;;
;;; THE PICTURE IS PASSIVE AND MUST STAY PASSIVE.  It is an "image"
;;; tile, never an "image_button".  A DCL image tile is NOT retained by
;;; AutoCAD: any repaint clears it to its own colour attribute and
;;; everything the application drew into it is gone, and there is no
;;; expose callback to draw it again.  An image_button is repainted on
;;; mouse-enter and mouse-leave, so the chart vanishes the first time
;;; the cursor crosses it -- which is exactly how LAZFORM lost its
;;; drawing before the button was taken back out.  The same rule is why
;;; every dropdown on this form repaints the chart: a list unrolling
;;; over it does the same damage and nothing else would repair it.
;;;
;;; WHY THE FONT AND THE DRAWING CODE ARE NOT SHARED WITH LAZFORM.  They
;;; are the same idea twice, and that is deliberate: only
;;; CALOFIN-LIB.lsp may define cal: symbols, and a tool may not define a
;;; top-level name another shared file defines -- so borrowing lzf:
;;; names would make LAZSPA depend on LAZFORM being loaded, which it
;;; never is at the standalone tier.  Everything here is lzs:.
;;;
;;; ADDING A SHAPE is adding data, not code -- one entry in lzs:*charts*
;;; with an outline, a dimension list and its SPA keys, plus a line in
;;; the tables under it.  Three charts, one per shape SPA draws:
;;; Rectangle, OCtagon, ROund.  The chart sends the word the legend
;;; prints; SPA's own keyword is "ROUnd" (one capitalisation repo-wide
;;; -- POOL needs RO for ROman), and spa:fshape matches the shape word
;;; WITHOUT case and returns the canonical spelling, so either reaches
;;; the right branch.  A word that is not a shape at all still falls
;;; through to the prompt rather than drawing the wrong spa silently.
;;; ======================================================================

(vl-load-com)

(setq *lazspa-version* "v1.1")

;;; -------------------- the stroke font ---------------------------------
;;;  DCL has no way to draw text into an image tile -- vector_image draws
;;;  line segments and that is the whole of it -- so the letters and the
;;;  numbers on the chart are stroked out of segments here.
;;;
;;;  One entry per character: the glyph as a list of polylines, each a
;;;  flat list of x y x y ... in TENTHS of a font unit, on a cell 4 wide
;;;  and 6 tall with y running DOWN the way image-tile pixels do.
;;;  Integers, so nothing here depends on float formatting.

(setq lzs:*font* '(
    ("A" (0 60 20 0 40 60) (8 40 32 40))
    ("B" (0 0 0 60) (0 0 30 0 40 10 40 20 30 30 0 30) (30 30 40 40 40 50 30 60 0 60))
    ("C" (40 10 30 0 10 0 0 10 0 50 10 60 30 60 40 50))
    ("D" (0 0 0 60) (0 0 30 0 40 10 40 50 30 60 0 60))
    ("E" (40 0 0 0 0 60 40 60) (0 30 30 30))
    ("F" (40 0 0 0 0 60) (0 30 30 30))
    ("G" (40 10 30 0 10 0 0 10 0 50 10 60 30 60 40 50 40 30 20 30))
    ("H" (0 0 0 60) (40 0 40 60) (0 30 40 30))
    ("I" (10 0 30 0) (20 0 20 60) (10 60 30 60))
    ("J" (30 0 30 50 20 60 10 60 0 50))
    ("K" (0 0 0 60) (40 0 0 35) (14 25 40 60))
    ("L" (0 0 0 60 40 60))
    ("M" (0 60 0 0 20 30 40 0 40 60))
    ("N" (0 60 0 0 40 60 40 0))
    ("O" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0))
    ("P" (0 60 0 0 30 0 40 10 40 20 30 30 0 30))
    ("Q" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0) (25 45 40 60))
    ("R" (0 60 0 0 30 0 40 10 40 20 30 30 0 30) (20 30 40 60))
    ("S" (40 10 30 0 10 0 0 10 0 20 10 30 30 30 40 40 40 50 30 60 10 60 0 50))
    ("T" (0 0 40 0) (20 0 20 60))
    ("U" (0 0 0 50 10 60 30 60 40 50 40 0))
    ("V" (0 0 20 60 40 0))
    ("W" (0 0 10 60 20 20 30 60 40 0))
    ("X" (0 0 40 60) (40 0 0 60))
    ("Y" (0 0 20 30 40 0) (20 30 20 60))
    ("Z" (0 0 40 0 0 60 40 60))
    ("0" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0) (5 55 35 5))
    ("1" (10 10 20 0 20 60) (10 60 30 60))
    ("2" (0 10 10 0 30 0 40 10 40 20 0 60 40 60))
    ("3" (0 0 40 0 20 25) (20 25 40 35 40 50 30 60 10 60 0 50))
    ("4" (30 60 30 0 0 40 40 40))
    ("5" (40 0 0 0 0 25 30 25 40 35 40 50 30 60 10 60 0 50))
    ("6" (40 0 20 0 0 20 0 50 10 60 30 60 40 50 40 40 30 30 10 30 0 40))
    ("7" (0 0 40 0 15 60))
    ("8" (10 30 0 20 0 10 10 0 30 0 40 10 40 20 30 30 10 30 0 40 0 50 10 60 30 60 40 50 40 40 30 30))
    ("9" (0 60 20 60 40 40 40 10 30 0 10 0 0 10 0 20 10 30 30 30 40 20))
    ("." (17 54 23 54 23 60 17 60 17 54))
    ("-" (5 30 35 30))
    ("'" (20 0 20 16))
    ("\"" (13 0 13 16) (27 0 27 16))
    ("/" (0 60 40 0))
    (":" (20 16 20 22) (20 40 20 46))
    ("%" (0 60 40 0) (5 5 12 5) (28 55 35 55))
    ("#" (10 0 6 60) (30 0 26 60) (0 20 40 20) (0 40 40 40))
    (" ")
))

(setq lzs:*font-w* 40)          ; glyph cell width, tenths
(setq lzs:*font-h* 60)          ; glyph cell height, tenths
(setq lzs:*font-adv* 56)        ; pen advance per character, tenths

;;; -------------------- the charts --------------------------------------
;;;  Everything is in PER-MILLE of the picture, x and y, y DOWN -- the
;;;  same convention as an image tile, so the only conversion at draw
;;;  time is a multiply.  Integers again.  y running down is why the
;;;  BOTTOM of a spa is the LARGER y here: corner A, bottom left on the
;;;  order sheet, is the low x and the high y.
;;;
;;;  A chart is:
;;;    (key  spa-shape  title
;;;      (outline-element ...)
;;;      (dimension ...)
;;;      (column-only-field ...)
;;;      (mark ...))
;;;
;;;  An outline element is a flat per-mille polyline, x y x y ..., or an
;;;  ARC written ("A" cx cy rx ry from to) with the centre and both
;;;  radii in per-mille and the angles in degrees, 0 due east and
;;;  counting anticlockwise ON SCREEN.
;;;
;;;  A dimension is (letter spakey x1 y1 x2 y2 side label), where side
;;;  is "h" or "v" -- which way the measurement runs, and so where its
;;;  text sits.  The arrow, the letter and the typed value all come off
;;;  those two endpoints, so there is no separate position table that
;;;  could fall out of step with the drawing.
;;;
;;;  A column-only field is (spakey label): a real SPA answer with no
;;;  place on the plan.  The octagon's S2 is the only one -- it measures
;;;  a diagonal cut FACE, and a dimension on this chart is "h" or "v"
;;;  and nothing else, so a diagonal has nowhere to be drawn and is
;;;  answered in the list instead.  (LAZFORM's grecian charts do exactly
;;;  this with their own S2, for exactly this reason.)
;;;
;;;  A mark is (text cx cy): a letter drawn on the picture at that
;;;  per-mille CENTRE, answering nothing.  The rectangle's A B C D are
;;;  the whole of it -- SPA names its corner questions after those
;;;  letters, so the Corners rows and the drawing have to agree about
;;;  which corner is which.

(setq lzs:*charts* '(

  ;; ---------------- Rectangle ----------------
  ;;  SPA's own header: "Corners: A bottom-left, B bottom-right, C
  ;;  top-right, D top-left", and its two overalls are named for them --
  ;;  W runs A-B across the bottom and L runs A-D up the left end.  So W
  ;;  is drawn UNDER the shape, on the side it is actually taped, rather
  ;;  than borrowed from the top edge because there was room up there.
  ("Rectangle" "Rectangle" "Rectangle"
   ((150 250 850 250 850 820 150 820 150 250))
   (("W" "w" 150 920 850 920 "h" "W - overall WIDTH across (A-B)")
    ("L" "l"  75 250  75 820 "v" "L - overall LENGTH up (A-D)"))
   nil
   (("D" 105 210) ("C" 895 210) ("A" 105 860) ("B" 895 860)))

  ;; ---------------- Octagon ----------------
  ;;  SPA's eight corners, counter-clockwise from the left end of the
  ;;  bottom flat:
  ;;
  ;;                 F ---------- E
  ;;                /              \      B = overall across
  ;;               G                D     A = overall up
  ;;               |                |     T = the flats across
  ;;               H                C     V = the flats up
  ;;                \              /      S  = cut along the side
  ;;                 A ---------- B       S1 = cut up the end
  ;;                                      S2 = the cut face itself
  ;;
  ;;  The letters have to CLOSE against the overalls, because spa:octov
  ;;  resolves them that way: S + T + S = B and S1 + V + S1 = A.  The
  ;;  drawing below is built to those sums (100 + 600 + 100 = 800 across,
  ;;  90 + 320 + 90 = 500 up), and tests/test_lazspa.py re-checks them,
  ;;  so a picture that lies about the measurement it names fails the
  ;;  suite rather than misleading the person reading it off.
  ;;
  ;;  The corner letters are NOT marked on this chart on purpose: SPA
  ;;  calls its corners A..H and its dimensions A, B, S, S1, T, V, S2,
  ;;  so an A on the outline and an A on a dimension line would be two
  ;;  different things a hand's breadth apart.
  ("OCtagon" "OCtagon" "Octagon"
   ((200 250 800 250 900 340 900 660 800 750 200 750
     100 660 100 340 200 250))
   (("B"  "b"  100 130 900 130 "h" "B - overall size ACROSS")
    ("S"  "ss" 100 200 200 200 "h" "S - corner cut along the side")
    ("T"  "tt" 200 200 800 200 "h" "T - flat across (top & bottom)")
    ("A"  "a"   30 250  30 750 "v" "A - overall size UP")
    ("S1" "s1"  65 250  65 340 "v" "S1 - corner cut up the end")
    ("V"  "vv"  65 340  65 660 "v" "V - flat up (left & right)"))
   (("s2" "S2 - corner cut FACE (tape across it)"))
   nil)

  ;; ---------------- Round ----------------
  ;;  SPA asks ONE question here -- "Overall diameter [Outofround]" --
  ;;  and only takes the two axes when the answer is the keyword.  Its
  ;;  roundflow reads the store like this:
  ;;
  ;;      (cond ((spa:fhas 'a) "Outofround")
  ;;            ((and (spa:fhas 'b) (numberp ...)) <the diameter>)
  ;;            (t <ask>))
  ;;
  ;;  -- so A is only PEEKED at, and its mere PRESENCE is what takes the
  ;;  out-of-round branch; B alone is the diameter.  That is why A's box
  ;;  says "only if out of round" and why an NA typed into it is treated
  ;;  as an empty box rather than sent (see lzs:*naok*): an NA there
  ;;  would open the out-of-round branch to say nothing at all.
  ("ROund" "ROund" "Round"
   (("A" 500 500 250 250 0 360))
   (("B" "b" 250 150 750 150 "h" "B - overall diameter (across)")
    ("A" "a" 175 250 175 750 "v" "A - overall UP (only if out of round)"))
   nil
   nil)
))

;;; -------------------- chart access ------------------------------------

(defun lzs:chart (key / c out)
  (foreach c lzs:*charts*
    (if (and (not out) (= (car c) key)) (setq out c)))
  out)

(defun lzs:outline (c) (nth 3 c))
(defun lzs:dims (c) (nth 4 c))
(defun lzs:extra (c) (nth 5 c))
(defun lzs:marks (c) (nth 6 c))

;;; -------------------- where the chart is cut ---------------------------
;;;  The closest DCL comes to boxes ON the drawing: the chart is cut
;;;  into horizontal bands at the heights where its horizontal
;;;  dimension rows run, and those rows are REAL edit boxes wedged
;;;  between the bands, pushed to their letters' positions by spacers.
;;;  The vertical dimensions cannot be wedged -- a box cannot stand
;;;  sideways in a row -- so they keep their boxes in the side column
;;;  with their values drawn on the chart instead.
;;;
;;;  A cut is a per-mille y that must land EXACTLY on a horizontal
;;;  dimension's line; every "h" dimension at that y becomes a wedge box
;;;  and loses its drawn arrow, since the row of boxes IS that row of
;;;  the drawing now.

(setq lzs:*cuts* '(("Rectangle" 920)
                   ("OCtagon" 130 200)
                   ("ROund" 150)))

(defun lzs:cuts (c) (cdr (assoc (car c) lzs:*cuts*)))

;;; -------------------- corners -----------------------------------------
;;;  A corner is a treatment plus, when the treatment is Radius or
;;;  Diagonal, a size -- so each gets a dropdown and a size box that is
;;;  greyed until a sized treatment is picked.  The dropdown's first
;;;  entry is "(ask)": the form's version of leaving a box empty, and
;;;  the only honest default, since SPA offers no default on corner A
;;;  either.
;;;
;;;  THE DROPDOWN SPEAKS THE SHEET LEGEND -- 90 / Radius / Diagonal, the
;;;  words printed on the order sheet a drafter copies from.  SPA itself
;;;  now asks the canonical Treatment question (Square / Radius / Cut /
;;;  NotGiven, STANDARDS.md section 2) and normalises the legend words
;;;  on the way in, so the chart keeps the drafter's vocabulary and the
;;;  routine keeps the standard's.  Send a word that is neither and
;;;  spa:askcorner consumes it, throws it away, and asks the corner at
;;;  the keyboard as if the box had been
;;;  left empty.  ("Square" SPA does accept, as a synonym it normalises
;;;  to 90; the dropdown offers 90 because that is what the sheet says.)
;;;
;;;  Only the Rectangle carries corner rows: it is the only shape SPA
;;;  asks corner treatments for.  An octagon's corners ARE its S / S1 /
;;;  S2 letters, already on the chart, and a round spa has none.

(setq lzs:*ctreat* '("(ask)" "90" "Radius" "Diagonal"))

(setq lzs:*corners*
  '(("Rectangle"
     ("cornera" "Corner A (bottom left)")
     ("cornerb" "Corner B (bottom right)")
     ("cornerc" "Corner C (top right)")
     ("cornerd" "Corner D (top left)"))))

(defun lzs:corners (c) (cdr (assoc (car c) lzs:*corners*)))

;; is selection I a treatment that carries a size?  2 = Radius,
;; 3 = Diagonal; 90 sets back nothing and asks for no number.
(defun lzs:sized (i) (member i '(2 3)))

;;; -------------------- the other outline --------------------------------
;;;  SPA offers to draw the second outline once the first is down, and
;;;  "by dims" asks for its overalls under keys that are PER SHAPE --
;;;  the rectangle's second pair is w2/l2, the octagon's is b2/a2 plus
;;;  the cut face f2, the round one's is b2/a2.  Same question, three
;;;  key sets, so the table is per chart rather than one shared row.

(setq lzs:*second*
  '(("Rectangle"
     ("w2" "Other outline ACROSS")
     ("l2" "Other outline UP"))
    ("OCtagon"
     ("b2" "Other outline ACROSS")
     ("a2" "Other outline UP")
     ("f2" "Other outline cut FACE"))
    ("ROund"
     ("b2" "Other outline ACROSS")
     ("a2" "Other outline UP"))))

(defun lzs:second (c) (cdr (assoc (car c) lzs:*second*)))

(defun lzs:secondkeys (c / d out)
  (foreach d (lzs:second c) (setq out (cons (car d) out)))
  (reverse out))

;;; -------------------- where NA is a real answer ------------------------
;;;  The three-state contract sends NA as (key . nil), and SPA reads
;;;  that as "not measured" -- but only where the question ACCEPTS an
;;;  NA.  Its measurement sequences mark each item REQ / SUG / NAX, and
;;;  a REQ item fed a nil is not asked again: spa:askseqb stores the nil
;;;  straight into its answers and the flow then does arithmetic on it,
;;;  which in AutoLISP is an error, not a fallback.  (w and b are REQ;
;;;  so are the second outline's w2 and b2.)
;;;
;;;  So an NA typed against a key SPA has no NA for is demoted to an
;;;  EMPTY BOX -- nothing is sent and SPA asks, which is what the person
;;;  who typed it meant and is the same fail-safe direction as an
;;;  unparseable typo.  This list is the keys where NA really is an
;;;  answer, per chart.
;;;
;;;  Round's A is deliberately not here even though the sequence would
;;;  take it: its presence is the out-of-round GATE (see the chart note
;;;  above), so an NA there would switch branches to say nothing.

(setq lzs:*naok*
  '(("Rectangle" "l" "l2")
    ("OCtagon" "a" "s2" "tt" "ss" "s1" "vv" "a2" "f2")
    ("ROund" "a2")))

(defun lzs:naok (c) (cdr (assoc (car c) lzs:*naok*)))

;;; -------------------- the dropdowns every page carries -----------------
;;;  (key label (item ...)) -- item 0 is always "(ask)", the dropdown's
;;;  version of an empty box: nothing is sent and SPA asks as usual.
;;;
;;;  MODE is SPA's very first question and it changes the layer, the
;;;  linetype and the dimension style the whole run draws in, so it sits
;;;  at the top of the page rather than in with the rest.
;;;
;;;  GRADE and TAPER are what the Spa Cover Details block would have
;;;  supplied; answering them here does not remove the block pick (SPA
;;;  offers that up front, before anything else, and an entsel is not
;;;  something a form can answer) but it does settle the hinge maths.

(setq lzs:*lists*
  '(("mode"      "Water's edge or cover size"
     ("(ask)" "Watersedge" "Coversize"))
    ("second"    "Draw the other outline as well"
     ("(ask)" "Yes" "No"))
    ("method"    "Take the other outline from"
     ("(ask)" "Offset" "Dims"))
    ("autohinge" "Auto-hinge the cover"
     ("(ask)" "Yes" "No"))
    ("grade"     "Cover grade"
     ("(ask)" "STANDARD" "THERMOLIGHT"))
    ("taper"     "Taper"
     ("(ask)" "3-2" "4-2" "4-3" "5-3" "5-4" "3-3" "1-3/8"))))

(defun lzs:lvals (key) (caddr (assoc key lzs:*lists*)))
(defun lzs:llabel (key) (cadr (assoc key lzs:*lists*)))

(defun lzs:listkeys ( / d out)
  (foreach d lzs:*lists* (setq out (cons (car d) out)))
  (reverse out))

;;; -------------------- the per-page hint --------------------------------

(setq lzs:*hints*
  '(("Rectangle"
     "A B C D run from the bottom left, the way SPA numbers them.")
    ("OCtagon"
     "B and A alone draw a true square octagon -- NA the cut letters.")
    ("ROund"
     "Leave A empty for a circle; fill it in and the spa is out of round.")))

(defun lzs:hint (c) (cadr (assoc (car c) lzs:*hints*)))

;;; -------------------- which dims are wedged, and the bands -------------

;; The horizontal dims whose line IS this cut.
(defun lzs:cutdims (c y / d out)
  (foreach d (lzs:dims c)
    (if (and (= (nth 6 d) "h") (= (nth 3 d) y) (= (nth 5 d) y))
        (setq out (cons d out))))
  (reverse out))

;; Keys of every dim that lives in a wedge row rather than the column.
(defun lzs:wedge-keys (c / y d out)
  (foreach y (lzs:cuts c)
    (foreach d (lzs:cutdims c y)
      (setq out (cons (cadr d) out))))
  (reverse out))

;; The bands between the cuts: ((y0 . y1) ...), whole chart when a
;; chart declares no cuts.
(defun lzs:bands (c / ys prev out y)
  (setq ys (append (list 0) (lzs:cuts c) (list 1000))
        prev (car ys))
  (foreach y (cdr ys)
    (setq out (cons (cons prev y) out)
          prev y))
  (reverse out))

;; Every SPA key the chart's own picture and list can answer, drawn ones
;; first, in order.
(defun lzs:keys (c / d out)
  (foreach d (lzs:dims c) (setq out (cons (cadr d) out)))
  (foreach d (lzs:extra c) (setq out (cons (car d) out)))
  (reverse out))

;; Every key on the page that is a TYPED box: the chart's own, the
;; second outline's overalls, and the cover lap.
(defun lzs:boxkeys (c)
  (append (lzs:keys c) (lzs:secondkeys c) (list "gap")))

;;; -------------------- the answers -------------------------------------
;;;  What is typed is kept as the STRING the user typed, so the chart can
;;;  show it back exactly as entered -- 6'10" stays 6'10" -- and it is
;;;  only turned into a number when SPA is handed the form.

(setq lzs:*vals* nil)           ; ((key . "typed") ...)
(setq lzs:*picks* nil)          ; ((dropdown-key . index) ...)
(setq lzs:*focus* nil)          ; the key whose box has the caret
(setq lzs:*chart* nil)          ; the chart being filled in
(setq lzs:*pos* nil)            ; where the dialog was last standing
(setq lzs:*go* nil)             ; the chart a tab click asked for

(defun lzs:get (key / p)
  (if (setq p (assoc key lzs:*vals*)) (cdr p) ""))

(defun lzs:put (key v / out p)
  (foreach p lzs:*vals* (if (/= (car p) key) (setq out (cons p out))))
  (setq lzs:*vals* (reverse (cons (cons key v) out))))

(defun lzs:pget (key / p)
  (if (setq p (assoc key lzs:*picks*)) (cdr p) 0))

(defun lzs:pput (key i / out p)
  (foreach p lzs:*picks* (if (/= (car p) key) (setq out (cons p out))))
  (setq lzs:*picks* (reverse (cons (cons key i) out))))

;; The word a dropdown is standing on, or nil when it is still on
;; "(ask)" -- which is the form's way of sending nothing at all.
(defun lzs:pick (key / i v)
  (setq i (lzs:pget key)
        v (lzs:lvals key))
  (if (and v (> i 0)) (nth i v)))

;;; -------------------- drawing the chart -------------------------------
;;;  Pixel coordinates, origin top-left, y down -- image-tile convention,
;;;  which is why the per-mille data is stored that way too and needs no
;;;  flipping here.  dimx_tile / dimy_tile report the LARGEST legal
;;;  coordinate, not the size, and are only answerable while the dialog
;;;  is up, so everything below runs between new_dialog and start_dialog.

(setq lzs:*dx* 0)               ; the tile's extent this time round
(setq lzs:*dy* 0)
(setq lzs:*y0* 0)               ; the band being drawn, in per-mille --
(setq lzs:*y1* 1000)            ; the whole chart when nothing is cut

(setq lzs:*col-line* -16)       ; dialog foreground: the outline
(setq lzs:*col-back* -15)       ; dialog background: the clear
(setq lzs:*col-dim* 8)          ; grey: the dimension arrows
(setq lzs:*col-val* 30)         ; orange: a value that has been typed
(setq lzs:*col-hi* 5)           ; blue: the box round the active one

;; per-mille -> pixels
(defun lzs:px (v) (fix (/ (* v lzs:*dx*) 1000.0)))
(defun lzs:py (v)
  (fix (/ (* (- v lzs:*y0*) lzs:*dy*) (float (- lzs:*y1* lzs:*y0*)))))

(defun lzs:iny (v) (and (<= lzs:*y0* v) (<= v lzs:*y1*)))
(defun lzs:inband (v) (and (<= lzs:*y0* v) (< v lzs:*y1*)))

;; The segment, clipped to the band, or nil when none of it is inside.
;; Everything the bands draw goes through this, so a cut is one rule
;; applied everywhere rather than per-shape case work.
(defun lzs:clipseg (x1 y1 x2 y2 / ta tb lo hi)
  (cond
    ((= y1 y2)
     (if (lzs:iny y1) (list x1 y1 x2 y2)))
    (t
     (setq ta (/ (- lzs:*y0* y1) (float (- y2 y1)))
           tb (/ (- lzs:*y1* y1) (float (- y2 y1)))
           lo (max 0.0 (min ta tb))
           hi (min 1.0 (max ta tb)))
     (if (< lo hi)
         (list (+ x1 (* (- x2 x1) lo)) (+ y1 (* (- y2 y1) lo))
               (+ x1 (* (- x2 x1) hi)) (+ y1 (* (- y2 y1) hi)))))))

;; An arc as per-mille points.  DCL draws line segments and nothing
;; else, so an arc has to become a polyline sooner or later; doing it
;; here means the chart data can say what it means and say it once.
(defun lzs:arcpts (a / cx cy rx ry f to n i ang out)
  (setq cx (nth 1 a) cy (nth 2 a) rx (nth 3 a) ry (nth 4 a)
        f (nth 5 a) to (nth 6 a))
  (setq n (fix (/ (abs (- to f)) 6.0)))
  (if (< n 4) (setq n 4))
  (setq i 0)
  (while (<= i n)
    ;; NB: the angle local is not called t -- a local of that name would
    ;; shadow TRUE for the length of the call
    (setq ang (/ (* pi (+ f (/ (* (- to f) i) (float n)))) 180.0)
          out (cons (fix (- cy (* ry (sin ang))))
                    (cons (fix (+ cx (* rx (cos ang)))) out))
          i (1+ i)))
  (reverse out))

;; An outline element as a flat per-mille polyline, whichever it was.
(defun lzs:flatten (e)
  (if (= (type (car e)) 'STR) (lzs:arcpts e) e))

;; A polyline given as a flat per-mille list, clipped to the band.
(defun lzs:pline (flat col / s)
  (while (and flat (cddr flat))
    (if (setq s (lzs:clipseg (car flat) (cadr flat)
                             (caddr flat) (cadddr flat)))
        (vector_image (lzs:px (car s)) (lzs:py (cadr s))
                      (lzs:px (caddr s)) (lzs:py (cadddr s)) col))
    (setq flat (cddr flat))))

;; A polyline already in pixels, given as (x y x y ...).
(defun lzs:plinepx (flat col)
  (while (and flat (cddr flat))
    (vector_image (car flat) (cadr flat) (caddr flat) (cadddr flat) col)
    (setq flat (cddr flat))))

(defun lzs:glyph (ch / p)
  (if (setq p (assoc (strcase ch) lzs:*font*)) (cdr p)))

;; The width one string will occupy, in pixels, at SC tenths per unit.
(defun lzs:textw (s sc)
  (if (= s "") 0
      (fix (/ (* (- (* (strlen s) lzs:*font-adv*)
                    (- lzs:*font-adv* lzs:*font-w*))
                 sc)
              100.0))))

(defun lzs:texth (sc) (fix (/ (* lzs:*font-h* sc) 100.0)))

;; The size to letter the chart at.  Derived from the tile rather than
;; fixed: an image tile's pixel size falls out of the user's dialog font
;; and display DPI, and is not knowable until the dialog is up.
(defun lzs:basesc ( / sc)
  (setq sc (/ (* lzs:*dy* 100) 1560))
  (if (< sc 12) 12 sc))

;; Stroke S with its top-left corner at pixel X Y.  SC is a percentage
;; of the font's own tenth-units, so the caller can size text to fit.
(defun lzs:text (s x y sc col / i ch pen poly out n)
  (setq i 1 pen x)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (foreach poly (lzs:glyph ch)
      (setq out nil n poly)
      (while n
        (setq out (cons (+ y (fix (/ (* (cadr n) sc) 100.0)))
                        (cons (+ pen (fix (/ (* (car n) sc) 100.0))) out))
              n (cddr n)))
      (lzs:plinepx (reverse out) col))
    (setq pen (+ pen (fix (/ (* lzs:*font-adv* sc) 100.0)))
          i (1+ i)))
  pen)

;; The dimension line with an arrowhead at each end, in per-mille,
;; clipped to the band.  A head is drawn only when its own end is
;; inside the band -- the shaft of a vertical dimension can run through
;; several bands, and each draws just its stretch.
(defun lzs:arrow (x1 y1 x2 y2 col / s a b p q)
  (if (setq s (lzs:clipseg x1 y1 x2 y2))
      (vector_image (lzs:px (car s)) (lzs:py (cadr s))
                    (lzs:px (caddr s)) (lzs:py (cadddr s)) col))
  (setq a 6 b 3)
  (cond
    ((= y1 y2)                          ; horizontal: heads point in
     (if (lzs:iny y1)
         (progn
           (setq p (list (lzs:px (min x1 x2)) (lzs:py y1))
                 q (list (lzs:px (max x1 x2)) (lzs:py y1)))
           (vector_image (car p) (cadr p) (+ (car p) a) (- (cadr p) b) col)
           (vector_image (car p) (cadr p) (+ (car p) a) (+ (cadr p) b) col)
           (vector_image (car q) (cadr q) (- (car q) a) (- (cadr q) b) col)
           (vector_image (car q) (cadr q) (- (car q) a) (+ (cadr q) b) col))))
    (t                                  ; vertical
     (if (lzs:iny (min y1 y2))
         (progn
           (setq p (list (lzs:px x1) (lzs:py (min y1 y2))))
           (vector_image (car p) (cadr p) (- (car p) b) (+ (cadr p) a) col)
           (vector_image (car p) (cadr p) (+ (car p) b) (+ (cadr p) a) col)))
     (if (lzs:iny (max y1 y2))
         (progn
           (setq q (list (lzs:px x1) (lzs:py (max y1 y2))))
           (vector_image (car q) (cadr q) (- (car q) b) (- (cadr q) a) col)
           (vector_image (car q) (cadr q) (+ (car q) b) (- (cadr q) a) col))))))

;; Keep a text box inside the tile, whatever it was asked for.
(defun lzs:clampx (lx w)
  (cond ((< lx 2) 2)
        ((> (+ lx w) (- lzs:*dx* 2)) (- lzs:*dx* w 2))
        (t lx)))

(defun lzs:clampy (ly h)
  (cond ((< ly 2) 2)
        ((> (+ ly h) (- lzs:*dy* 2)) (- lzs:*dy* h 2))
        (t ly)))

;; Where one dimension's text belongs, and what it says: the LETTER
;; until a value is typed, then the value in the letter's place.  A
;; value too wide for its own span is shrunk to fit rather than allowed
;; to run into its neighbours.
(defun lzs:label (d / letter key x1 y1 x2 y2 side txt sc w h lx ly span mx my)
  (setq letter (car d) key (cadr d)
        x1 (lzs:px (nth 2 d)) y1 (lzs:py (nth 3 d))
        x2 (lzs:px (nth 4 d)) y2 (lzs:py (nth 5 d))
        side (nth 6 d)
        txt (lzs:get key)
        mx (/ (+ x1 x2) 2) my (/ (+ y1 y2) 2))
  (if (= txt "")
      (setq txt letter sc (lzs:basesc))
      (setq sc (/ (* (lzs:basesc) 90) 100)))
  (setq w (lzs:textw txt sc))
  (if (and (= side "h") (> w 0))
      (progn
        (setq span (abs (- x2 x1)))
        (if (> w span)
            (progn
              (setq sc (/ (* sc span) w))
              (if (< sc (/ (* (lzs:basesc) 55) 100))
                  (setq sc (/ (* (lzs:basesc) 55) 100)))
              (setq w (lzs:textw txt sc))))))
  (setq h (lzs:texth sc))
  (if (= side "h")
      (setq lx (- mx (/ w 2)) ly (- y1 h 4))
      ;; a vertical dimension labels at the TOP of its span, centred on
      ;; its own line, EXCEPT when that would run off the left edge --
      ;; an overall sits hard against the boundary with no room on its
      ;; outside, so its label goes on the inside rather than clipping
      (progn
        (setq ly (+ (min y1 y2) 5))
        (setq lx (if (< (- mx (/ w 2)) 2) (+ mx 4) (- mx (/ w 2))))))
  (setq lx (lzs:clampx lx w)
        ly (lzs:clampy ly h))
  ;; blank the strip behind it so the dimension line does not run
  ;; through the characters
  (fill_image (- lx 3) (- ly 2) (+ w 6) (+ h 4) lzs:*col-back*)
  (if (= key lzs:*focus*)
      (lzs:plinepx (list (- lx 3) (- ly 2) (+ lx w 3) (- ly 2)
                         (+ lx w 3) (+ ly h 2) (- lx 3) (+ ly h 2)
                         (- lx 3) (- ly 2))
                   lzs:*col-hi*))
  (lzs:text txt lx ly sc
            (if (= (lzs:get key) "") lzs:*col-line* lzs:*col-val*)))

;; A corner letter, centred on its per-mille point.  It answers nothing
;; -- it is there so the Corners rows and the picture agree about which
;; corner is which.
(defun lzs:mark (m / txt sc w h lx ly)
  (setq txt (car m)
        sc (lzs:basesc)
        w (lzs:textw txt sc)
        h (lzs:texth sc)
        lx (lzs:clampx (- (lzs:px (cadr m)) (/ w 2)) w)
        ly (lzs:clampy (- (lzs:py (caddr m)) (/ h 2)) h))
  (lzs:text txt lx ly sc lzs:*col-line*))

;; The band a dimension's TEXT belongs to: a horizontal dim sits on its
;; own line, a vertical one labels at the top of its span.
(defun lzs:anchor (d)
  (if (= (nth 6 d) "h")
      (nth 3 d)
      (min (nth 3 d) (nth 5 d))))

;; The whole picture: every band painted once, each between its own
;; start_image and end_image.  Wedge dims draw nothing at all -- their
;; row of the drawing IS a row of real boxes now -- while every other
;; dim draws its clipped arrow in every band it crosses and its text in
;; the band its anchor falls in.
(defun lzs:redraw ( / c wk bands b i key poly d m)
  (setq c lzs:*chart*
        wk (lzs:wedge-keys c)
        bands (lzs:bands c)
        i 0)
  (foreach b bands
    (setq key (strcat "chart" (itoa i))
          lzs:*y0* (car b)
          lzs:*y1* (cdr b)
          lzs:*dx* (dimx_tile key)
          lzs:*dy* (dimy_tile key))
    (start_image key)
    (fill_image 0 0 lzs:*dx* lzs:*dy* lzs:*col-back*)
    (foreach poly (lzs:outline c)
      (lzs:pline (lzs:flatten poly) lzs:*col-line*))
    (foreach d (lzs:dims c)
      (if (not (member (cadr d) wk))
          (lzs:arrow (nth 2 d) (nth 3 d) (nth 4 d) (nth 5 d)
                     lzs:*col-dim*)))
    (foreach m (lzs:marks c)
      (if (lzs:inband (caddr m)) (lzs:mark m)))
    (foreach d (lzs:dims c)
      (if (and (not (member (cadr d) wk))
               (lzs:inband (lzs:anchor d)))
          (lzs:label d)))
    (end_image)
    (setq i (1+ i)))
  (setq lzs:*y0* 0
        lzs:*y1* 1000)
  (princ))

;;; -------------------- what SPA will and will not ask -------------------
;;;  A page offers every question SPA could ask, and some of them stop
;;;  being questions the moment another one is answered.  These are the
;;;  keys the run will not reach, so they are greyed AND not sent -- a
;;;  form that quietly carries dead answers is harder to reason about
;;;  than one that does not, and SPA drops them unread on the way out
;;;  either way.
;;;
;;;    grade THERMOLIGHT  a Thermo-Light cover's water's edge and cover
;;;                       size are the SAME thing, so c:SPA sets the
;;;                       mode itself (Coversize), spa:askother declines
;;;                       to offer the second outline at all, and
;;;                       spa:askdetails forces the taper to 1-3/8.
;;;                       Mode, the whole cover block and the taper are
;;;                       therefore dead.
;;;    second No          spa:askother2 stops at the Yes/No, so the
;;;                       method, the lap and the by-dims overalls are
;;;                       never asked.
;;;    method Offset      the lap is asked, the by-dims overalls are not.
;;;    method Dims        the by-dims overalls are asked, the lap is not.
;;;
;;;  Auto-hinge survives all of it: Thermo-Light covers are hinged like
;;;  any other, only in velcro throughout.

(defun lzs:dead (c / g s m)
  (setq g (lzs:pick "grade")
        s (lzs:pick "second")
        m (lzs:pick "method"))
  (cond
    ((= g "THERMOLIGHT")
     (append (list "mode" "second" "method" "gap" "taper")
             (lzs:secondkeys c)))
    ((= s "No")
     (append (list "method" "gap") (lzs:secondkeys c)))
    ((= m "Offset") (lzs:secondkeys c))
    ((= m "Dims") (list "gap"))))

;; The tiles greying is allowed to touch on this page.  mode_tile on a
;; key that is not on the page would error, and every one of these is on
;; every page.
(defun lzs:greyable (c)
  (append (list "mode" "second" "method" "gap" "taper")
          (lzs:secondkeys c)))

(defun lzs:grey (c / dead k)
  (setq dead (lzs:dead c))
  (foreach k (lzs:greyable c)
    (mode_tile k (if (member k dead) 1 0)))
  (princ))

;;; -------------------- what the page still owes -------------------------
;;;  LAZFORM's state line, with a third thing to say.  SPA has TWO ways
;;;  of dropping a box without a word:
;;;
;;;    lzs:answer   turns anything it cannot read into SKIP
;;;    lzs:keyanswer demotes an NA to SKIP on any key SPA has no NA for
;;;
;;;  Both leave the chart showing what was typed -- the chart draws the
;;;  STRING -- so a box that will be ignored looks exactly like a box
;;;  that was answered, and the drafter finds out at the command line,
;;;  if at all.  The demotion is the sharper of the two: NA is a word
;;;  the form itself tells you to type, and on the wrong box it means
;;;  nothing.
;;;
;;;  Nothing here changes what is SENT.  lzs:form is still the only
;;;  thing that decides that; this reports what it is about to do.

;; "Corner A (bottom left)" -> "Corner A".
(defun lzs:unbracket (s / i n)
  (setq n (strlen s) i 1)
  (while (and (<= i n) (/= (substr s i 2) " (")) (setq i (1+ i)))
  (if (<= i n) (substr s 1 (1- i)) s))

;; "C - wall height" -> "C"; a label with no short letter prefix -> nil.
(defun lzs:leadletter (s / i n)
  (setq n (strlen s) i 1)
  (while (and (<= i n) (/= (substr s i 3) " - ")) (setq i (1+ i)))
  (if (and (<= i n) (> i 1) (<= i 4)) (substr s 1 (1- i))))

;; The short name a box answers to, which has to be the name printed on
;; the sheet: naming a box by its SPA key would send the drafter
;; hunting for a letter that is not on the paper.
(defun lzs:tagof (c key / d out)
  (foreach d (lzs:dims c)
    (if (and (not out) (= (cadr d) key)) (setq out (car d))))
  (foreach d (append (lzs:extra c) (lzs:second c))
    (if (and (not out) (= (car d) key))
      (setq out (lzs:leadletter (cadr d)))))
  (foreach d (lzs:corners c)
    (if (and (not out) (= (strcat (car d) "-sz") key))
      (setq out (lzs:unbracket (cadr d)))))
  (cond (out out)
        ((= key "gap") "the cover lap")
        (t (strcase key))))

;; Every typed box on the page that is not greyed.  A greyed box is
;; withheld whatever is in it, so neither complaining about its contents
;; nor counting it as still to ask would be true.  The corner size boxes
;; are here too: they are not in lzs:greyable, so lzs:dead never names
;; them -- what makes one live is its own dropdown taking a size.
(defun lzs:livekeys (c / dead out d)
  (setq dead (lzs:dead c))
  (foreach d (lzs:boxkeys c)
    (if (not (member d dead)) (setq out (cons d out))))
  (foreach d (lzs:corners c)
    (if (lzs:sized (lzs:pget (car d)))
      (setq out (cons (strcat (car d) "-sz") out))))
  (reverse out))

;; Live boxes holding something lzs:answer cannot read at all.
(defun lzs:unreadable ( / c out k v)
  (setq c lzs:*chart*)
  (foreach k (lzs:livekeys c)
    (setq v (lzs:trim (lzs:get k)))
    (if (and (/= v "") (eq (lzs:answer v) 'SKIP))
      (setq out (cons k out))))
  (reverse out))

;; Live boxes reading NA on a key that has no NA -- the demotion, said
;; out loud.  A corner size is one of them: SPA asks for the number.
(defun lzs:nabad ( / c out k)
  (setq c lzs:*chart*)
  (foreach k (lzs:livekeys c)
    (if (and (= (strcase (lzs:trim (lzs:get k))) "NA")
             (not (member k (lzs:naok c))))
      (setq out (cons k out))))
  (reverse out))

;; Live boxes still empty -- exactly what SPA will ask for.
(defun lzs:togo ( / c out k)
  (setq c lzs:*chart*)
  (foreach k (lzs:livekeys c)
    (if (= (lzs:trim (lzs:get k)) "") (setq out (cons k out))))
  (reverse out))

;; "B", "B and C2", "B, H and F", "B, H, F and 2 more".  The last "and"
;; belongs to whatever ENDS the list: with an overflow count hung off
;; it, "B, H and F and 2 more" reads as two lists rather than one.
(defun lzs:join (l last / n i out k)
  (setq n (length l) i 0 out "")
  (foreach k l
    (setq i (1+ i)
          out (cond ((= i 1) k)
                    ((and last (= i n)) (strcat out " and " k))
                    (t (strcat out ", " k)))))
  out)

(defun lzs:taglist (c keys / n i named k)
  (setq n (length keys) i 0)
  (foreach k keys
    (if (< i 3) (setq named (cons (lzs:tagof c k) named) i (1+ i))))
  (setq named (reverse named))
  (if (> n 3)
    (strcat (lzs:join named nil) " and " (itoa (- n 3)) " more")
    (lzs:join named t)))

;; "1 box" / "5 boxes" -- a line that says "all 1 boxes" reads as a bug
;; in the form, whatever it is actually reporting.
(defun lzs:boxes (n)
  (strcat (itoa n) (if (= n 1) " box" " boxes")))

;; The line itself.  The two silent drops take it in turn, urgent
;; first; when neither is there the line is the hand-off.
(defun lzs:statetext ( / c bad na togo n)
  (setq c    lzs:*chart*
        bad  (lzs:unreadable)
        na   (lzs:nabad)
        togo (lzs:togo)
        n    (length (lzs:livekeys c)))
  (cond
    ((cdr bad)
     (strcat (lzs:taglist c bad)
             " are not measurements - type a number, or NA, or clear them."))
    (bad
     (strcat (lzs:taglist c bad)
             " is not a measurement - type a number, or NA, or clear it."))
    ((cdr na)
     (strcat (lzs:taglist c na)
             " cannot be NA - SPA needs a number in each of them."))
    (na
     (strcat (lzs:taglist c na) " cannot be NA - SPA needs a number there."))
    ((zerop n)
     "Nothing on this page is live - SPA will ask for all of it.")
    ((not togo)
     (strcat "All " (lzs:boxes n) " filled - SPA will ask only for the "
             "base point and the block."))
    ((= (length togo) n)
     (strcat "Nothing filled yet - SPA will ask for all " (lzs:boxes n)
             ", plus the base point."))
    (t
     (strcat (itoa (- n (length togo))) " of " (lzs:boxes n) " filled - "
             "SPA will ask for " (lzs:taglist c togo)
             ", plus the base point."))))

;; Put the state on the page, and hold Insert back while any box holds
;; something that will be dropped.  Greying it IS the feature: pressing
;; Insert past either of those drops the box without a word.
(defun lzs:restate ( / )
  (set_tile "state" (lzs:statetext))
  (mode_tile "accept" (if (or (lzs:unreadable) (lzs:nabad)) 1 0))
  (princ))

;;; -------------------- the dialog --------------------------------------
;;  Two columns: the chart on the left as a passive image cut into
;;  bands, the boxes on the right in the chart's own order, each
;;  labelled with its letter so the list and the picture read as one
;;  thing.

;; Chart keys packed into rows no wider than the budget.  Three charts
;; run about 39 cells, so this never wraps today -- it is here because
;; DCL does not scroll and a fourth shape must cost a row rather than
;; the whole form.
(setq lzs:*tabbudget* 84)

(defun lzs:tabrows ( / out row w c cw)
  (setq row nil w 0)
  (foreach c lzs:*charts*
    (setq cw (+ (strlen (car c)) 6))
    (if (and row (> (+ w cw) lzs:*tabbudget*))
      (setq out (cons (reverse row) out) row nil w 0))
    (setq row (cons (car c) row) w (+ w cw)))
  (if row (setq out (cons (reverse row) out)))
  (reverse out))

;; The tab strip: one button per chart.  DCL has no tab tile, so a tab
;; is a button that closes this page and reopens the next.
(defun lzs:tabstrip ( / out c n)
  (foreach c (lzs:tabrows)
    (setq out (cons "  : row {" out))
    (foreach n c
      (setq out (cons (strcat "    : button { key = \"tab_" n
                              "\"; label = \"" n "\"; }")
                      out)))
    (setq out (cons "  }" out)))
  (reverse out))

(setq lzs:*chart-w* 52)         ; the chart column, in character cells
(setq lzs:*chart-h* 19)         ; its total height, spread over the bands

;; character cells across for a per-mille x
(defun lzs:cellx (v) (/ (* v lzs:*chart-w*) 1000.0))

;; One wedge row: the cut's dims as real edit boxes, pushed to their
;; letters' positions by spacers.  Positions are in character cells and
;; a box has its own minimum size, so this is honest about being
;; approximate: a box lands within a cell or so of its letter, and two
;; that would collide get pushed apart rather than overlapped.
(defun lzs:wedgerow (c y / out d lbl w want pos)
  (setq out (list "      : row {")
        pos 0.0)
  ;; LEFT TO RIGHT, whatever order the chart lists them in: the row is
  ;; built by walking a cursor across it, and a dim listed before its
  ;; left-hand neighbour would shove that neighbour to the wrong side
  ;; of the chart
  (foreach d (vl-sort (lzs:cutdims c y)
                      '(lambda (p q)
                         (< (+ (nth 2 p) (nth 4 p))
                            (+ (nth 2 q) (nth 4 q)))))
    (setq lbl (car d)
          w (+ (strlen lbl) 10.0)       ; label + borders + 6-char box
          want (- (lzs:cellx (/ (+ (nth 2 d) (nth 4 d)) 2)) (/ w 2)))
    (if (< want (+ pos 0.5)) (setq want (+ pos 0.5)))
    (setq out (cons (strcat "        : spacer { width = "
                            (rtos (- want pos) 2 1) "; }")
                    out))
    (setq out (cons (strcat "        : edit_box { key = \"" (cadr d)
                            "\"; label = \"" lbl
                            "\"; edit_width = 6; fixed_width = true; }")
                    out))
    (setq pos (+ want w)))
  (setq out (cons "        spacer;" out))
  (reverse (cons "      }" out)))

;; The chart as a stack: an image tile per band, a wedge row at every
;; cut, heights split in proportion to the bands they show.
(defun lzs:bandtiles (c / out bands b i h)
  (setq i 0
        bands (lzs:bands c))
  (foreach b bands
    (setq h (/ (* (- (cdr b) (car b)) lzs:*chart-h*) 1000.0))
    (if (< h 0.8) (setq h 0.8))
    (setq out (append out
                      (list (strcat "      : image { key = \"chart" (itoa i)
                                    "\"; width = " (itoa lzs:*chart-w*)
                                    "; height = " (rtos h 2 1)
                                    "; fixed_width = true; "
                                    "fixed_height = true; color = -15; }"))))
    (if (< (1+ i) (length bands))
        (setq out (append out (lzs:wedgerow c (cdr b)))))
    (setq i (1+ i)))
  out)

(defun lzs:box (key label w)
  (strcat "        : edit_box { key = \"" key "\"; edit_width = "
          (itoa w) "; label = \"" label "\"; }"))

(defun lzs:popup (key w)
  (strcat "        : popup_list { key = \"" key "\"; label = \""
          (lzs:llabel key) "\"; edit_width = " (itoa w) "; }"))

;; The DCL name of a chart's page.
(defun lzs:dlgname (key) (strcat "lazspa_" (strcase key t)))

;; One dialog per chart.  They all live in one generated file so the
;; page loop can load_dialog once and switch pages without touching the
;; disk again.
(defun lzs:dcl-one (c / out d wk l)
  ;; out is consed newest-first and reversed once at the end, so this
  ;; seed list reads BACKWARDS: the label second here puts it second in
  ;; the file, after the line that opens the dialog.  The other way
  ;; round emits an attribute before its own dialog, which is not DCL.
  (setq out (list (strcat "  label = \"LazSpa - " (caddr c) "\";")
                  (strcat (lzs:dlgname (car c)) " : dialog {")))
  (setq out (append (reverse (lzs:tabstrip)) out))
  ;; MODE first, and on its own: it is SPA's opening question and it
  ;; settles the layer, the linetype and the dimension style everything
  ;; below is drawn in.
  (setq out (cons "  : boxed_row {" out))
  (setq out (cons "    label = \"This drawing\";" out))
  (setq out (cons (strcat "    : popup_list { key = \"mode\"; label = \""
                          (lzs:llabel "mode") "\"; edit_width = 12; }")
                  out))
  (setq out (cons "  }" out))
  (setq out (cons "  : row {" out))
  ;; PASSIVE image tiles, deliberately -- see the header -- stacked with
  ;; the wedge rows between them.
  (setq wk (lzs:wedge-keys c))
  (setq out (cons "    : column {" out))
  (foreach l (lzs:bandtiles c)
    (setq out (cons l out)))
  (setq out (cons "    }" out))
  (setq out (cons "    : column {" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Dimensions\";" out))
  ;; only the dims that could NOT be wedged into the drawing -- the
  ;; vertical ones -- keep a row here; the across chains live on the
  ;; chart itself.  Each is its LETTER as a button and then the box:
  ;; clicking the letter puts the caret in that box and rings the
  ;; dimension on the chart, which is as close to clicking the drawing
  ;; itself as DCL allows.
  (foreach d (lzs:dims c)
    (if (not (member (cadr d) wk))
        (progn
          (setq out (cons "        : row {" out))
          (setq out (cons (strcat "          : button { key = \"pick_"
                                  (cadr d) "\"; label = \"" (car d)
                                  "\"; fixed_width = true; }")
                          out))
          (setq out (cons (strcat "          : edit_box { key = \"" (cadr d)
                                  "\"; edit_width = 9; label = \"" (nth 7 d)
                                  "\"; }")
                          out))
          (setq out (cons "        }" out)))))
  (setq out (cons "      }" out))
  (if (lzs:extra c)
    (progn
      (setq out (cons "      : boxed_column {" out))
      (setq out (cons "        label = \"Not on this view\";" out))
      (foreach d (lzs:extra c)
        (setq out (cons (lzs:box (car d) (cadr d) 9) out)))
      (setq out (cons "      }" out))))
  (if (lzs:corners c)
    (progn
      (setq out (cons "      : boxed_column {" out))
      (setq out (cons "        label = \"Corners\";" out))
      (foreach d (lzs:corners c)
        (setq out (cons "        : row {" out))
        (setq out (cons (strcat "          : popup_list { key = \"" (car d)
                                "\"; label = \"" (cadr d)
                                "\"; edit_width = 11; }")
                        out))
        (setq out (cons (strcat "          : edit_box { key = \"" (car d)
                                "-sz\"; label = \"size\"; "
                                "edit_width = 6; fixed_width = true; }")
                        out))
        (setq out (cons "        }" out)))
      (setq out (cons "      }" out))))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"The other outline\";" out))
  (setq out (cons (lzs:popup "second" 9) out))
  (setq out (cons (lzs:popup "method" 9) out))
  (setq out (cons (lzs:box "gap" "How far the cover laps the water's edge" 9)
                  out))
  (foreach d (lzs:second c)
    (setq out (cons (lzs:box (car d) (cadr d) 9) out)))
  (setq out (cons "      }" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Hinges and cover details\";" out))
  (setq out (cons (lzs:popup "autohinge" 9) out))
  (setq out (cons (lzs:popup "grade" 13) out))
  (setq out (cons (lzs:popup "taper" 9) out))
  (setq out (cons "      }" out))
  (setq out (cons "    }" out))
  (setq out (cons "  }" out))
  (setq out (cons "  spacer;" out))
  (setq out (cons (strcat "  : text { key = \"hint\"; width = 62; label = \""
                          (lzs:hint c) "\"; }")
                  out))
  (setq out (cons (strcat "  : text { width = 62; label = \""
                          "Type NA where nothing was measured; leave a box "
                          "empty and SPA will ask.\"; }")
                  out))
  ;; the two things no form can answer, said on the form itself rather
  ;; than discovered at the command line
  (setq out (cons (strcat "  : text { width = 62; label = \""
                          "The Spa Cover Details block pick and the "
                          "spillaway questions stay at the command line.\"; }")
                  out))
  ;; The state line.  No label here: it is written before the dialog is
  ;; shown and rewritten on every change, so a label in the file would
  ;; only ever be the wrong answer for an instant.
  (setq out (cons "  : text { key = \"state\"; width = 62; }" out))
  (setq out (cons "  : row {" out))
  (setq out (cons (strcat "    : button { key = \"accept\"; label = \"Insert\"; "
                          "is_default = true; fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : button { key = \"cancel\"; label = \"Cancel\"; "
                          "is_cancel = true; fixed_width = true; }")
                  out))
  (setq out (cons "  }" out))
  (reverse (cons "}" out)))

;; Every page, one after another, in one file.
(defun lzs:dcl-lines ( / out c)
  (foreach c lzs:*charts*
    (setq out (append out (lzs:dcl-one c) (list ""))))
  out)

(defun lzs:write-lines (fh / l)
  (foreach l (lzs:dcl-lines) (write-line l fh)))

(defun lzs:write-dcl ( / f fh err)
  (setq f (vl-filename-mktemp "lazspa" nil ".dcl"))
  (if (and f (setq fh (open f "w")))
    (progn
      (setq err (vl-catch-all-apply 'lzs:write-lines (list fh)))
      (close fh)
      (cond
        ((vl-catch-all-error-p err) (vl-file-delete f) nil)
        (t f)))))

;;; -------------------- what SPA is handed ------------------------------
;;;  The three states of STANDARDS.md's form contract, decided here and
;;;  unchanged from LAZFORM's:
;;;
;;;    box left empty   the key is not sent at all -> SPA asks
;;;    NA typed in it   (key . nil) is sent        -> SPA takes NA
;;;    a measurement    (key . 84.0) is sent       -> SPA takes it
;;;
;;;  Anything that is neither NA nor a distance AutoCAD can read is
;;;  treated as an empty box: a typo must leave SPA asking rather than
;;;  quietly feeding it a nil that means something else entirely.
;;;  distof reads the architectural spellings, so 6'10" and 6'-10-1/2"
;;;  arrive as the numbers they look like.
;;;
;;;  A dropdown left on "(ask)" is the same as an empty box and sends
;;;  nothing.

(defun lzs:answer (v / n)
  (cond
    ((or (null v) (= v "")) 'SKIP)
    ((= (strcase (lzs:trim v)) "NA") nil)
    ((setq n (distof (lzs:trim v) 4)) n)
    ((setq n (distof (lzs:trim v) 2)) n)
    (t 'SKIP)))

(defun lzs:trim (s / i n)
  (setq i 1 n (strlen s))
  (while (and (<= i n) (= (substr s i 1) " ")) (setq i (1+ i)))
  (while (and (>= n i) (= (substr s n 1) " ")) (setq n (1- n)))
  (if (> i n) "" (substr s i (1+ (- n i)))))

;; One typed box, as SPA should hear it.  'SKIP means "send nothing".
;; An NA against a key SPA has no NA for is demoted to SKIP -- see
;; lzs:*naok* for why that is a fail-safe rather than a shrug.
(defun lzs:keyanswer (c key / a)
  (setq a (lzs:answer (lzs:get key)))
  (if (and (null a) (not (member key (lzs:naok c))))
      'SKIP
      a))

;; The (key . value) pairs the corner rows contribute.  A dropdown left
;; on (ask) sends nothing; a sized treatment carries its size when one
;; parses, and sends the treatment alone when it does not -- SPA then
;; asks for just the number.
(defun lzs:cornerpairs (c / out d stem i ty a)
  (foreach d (lzs:corners c)
    (setq stem (car d))
    (if (> (setq i (lzs:pget stem)) 0)
        (progn
          (setq ty (nth i lzs:*ctreat*))
          (setq out (cons (cons (read (strcat stem "-ty")) ty) out))
          (if (lzs:sized i)
              (progn
                (setq a (lzs:answer (lzs:get (strcat stem "-sz"))))
                (if (numberp a)
                    (setq out (cons (cons (read (strcat stem "-sz")) a)
                                    out))))))))
  (reverse out))

;; The alist SPA reads, built from what was typed.  The insertion base
;; point is NOT in it: SPA picks that in the drawing with the user's own
;; snaps live, which is where it belongs.
(defun lzs:form ( / c out dead k v a)
  (setq c lzs:*chart*
        dead (lzs:dead c)
        out (list (cons 'shape (cadr c))))
  (foreach k (lzs:listkeys)
    (if (and (not (member k dead)) (setq v (lzs:pick k)))
        (setq out (cons (cons (read k) v) out))))
  (foreach k (lzs:boxkeys c)
    (if (not (member k dead))
        (progn
          (setq a (lzs:keyanswer c k))
          (if (not (eq a 'SKIP))
              (setq out (cons (cons (read k) a) out))))))
  (foreach k (lzs:cornerpairs c)
    (setq out (cons k out)))
  (reverse out))

;;; -------------------- the run -----------------------------------------
;;  A helper rather than the command body, so its localized *error* is
;;  out of scope by the time SPA is started: SPA installs its own, and a
;;  SPA that fails must report as SPA.

;; A dropdown changed: remember it, re-grey what that answer kills, and
;; repaint the chart the list may have unrolled across.
(defun lzs:listpick (key v)
  (lzs:pput key (atoi v))
  (lzs:grey lzs:*chart*)
  (lzs:redraw)
  ;; grade, second and method all move the dead set, so they move the
  ;; count and the still-to-ask list with it
  (lzs:restate)
  (princ))

;; A corner dropdown changed: remember it, grey or un-grey its size box,
;; and repaint the chart.
(defun lzs:cornerpick (stem v / i)
  (setq i (atoi v))
  (lzs:pput stem i)
  (mode_tile (strcat stem "-sz") (if (lzs:sized i) 0 1))
  (lzs:redraw)
  ;; a treatment that takes a size has just added a live box, or taken
  ;; one away
  (lzs:restate)
  (princ))

;; Open a page where the user last had the dialog.  done_dialog reports
;; the position it was closed at and new_dialog takes one back, but only
;; as a 4-argument call -- and a build that answered done_dialog with
;; something other than a point would poison every reopen, so the shape
;; is checked before it is trusted and the plain 2-argument call is the
;; fallback.
(defun lzs:newdlg (name dcl)
  (if (and lzs:*pos* (listp lzs:*pos*) (= (length lzs:*pos*) 2)
           (numberp (car lzs:*pos*)) (numberp (cadr lzs:*pos*)))
      (new_dialog name dcl "" lzs:*pos*)
      (new_dialog name dcl)))

(defun lzs:show (chartkey / *error* f dcl rc c d n go done out)
  (defun *error* (msg)
    (term_dialog)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (setq dcl nil)
    (if f (vl-file-delete f))
    (setq f nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZSPA error: " msg)))
    (princ))
  (setq lzs:*vals* nil
        lzs:*picks* nil                 ; every dropdown back to (ask)
        lzs:*pos* nil                   ; where the user last had it
        go chartkey)
  (cond
    ((not (lzs:chart go))
     (princ (strcat "\nLAZSPA: no chart called " go ".")))
    ((not (setq f (lzs:write-dcl)))
     (princ "\nLAZSPA error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZSPA error: could not load the dialog file."))
    (t
     ;; The page loop.  DCL has no tab tile, so a tab is a button that
     ;; closes this page and reopens the next -- and because done_dialog
     ;; hands back where the dialog was standing, it reopens exactly
     ;; there instead of wandering off to the middle of the screen.
     ;; Everything typed lives in lzs:*vals* and lzs:*picks*, keyed, so
     ;; it survives the switch and is still there if you tab back.
     (while (not done)
       (setq lzs:*chart* (lzs:chart go)
             c lzs:*chart*
             lzs:*focus* nil)
       (cond
         ((not (lzs:newdlg (lzs:dlgname go) dcl))
          (princ "\nLAZSPA error: could not open the form.")
          (setq done t))
         (t
          ;; the plain dropdowns: filled, put back to their remembered
          ;; pick, and each harvests into its own store the moment it
          ;; changes -- get_tile answers about a LIVE dialog, and by the
          ;; time the answers are assembled this one is closed
          (foreach d (lzs:listkeys)
            (start_list d)
            (foreach n (lzs:lvals d) (add_list n))
            (end_list)
            (set_tile d (itoa (lzs:pget d)))
            (action_tile d
              (strcat "(lzs:listpick \"" d "\" $value)")))
          ;; the corner dropdowns, with their size boxes greyed unless
          ;; the remembered pick takes a size
          (foreach d (lzs:corners c)
            (start_list (car d))
            (foreach n lzs:*ctreat* (add_list n))
            (end_list)
            (set_tile (car d) (itoa (lzs:pget (car d))))
            (set_tile (strcat (car d) "-sz")
                      (lzs:get (strcat (car d) "-sz")))
            (mode_tile (strcat (car d) "-sz")
                       (if (lzs:sized (lzs:pget (car d))) 0 1))
            (action_tile (car d)
              (strcat "(lzs:cornerpick \"" (car d) "\" $value)"))
            (action_tile (strcat (car d) "-sz")
              (strcat "(lzs:put \"" (car d) "-sz\" $value) (lzs:restate)")))
          ;; put back what was typed before this page was opened
          (foreach d (lzs:boxkeys c) (set_tile d (lzs:get d)))
          (foreach d (lzs:boxkeys c)
            (action_tile d
              (strcat "(lzs:put \"" d "\" $value) (setq lzs:*focus* \"" d "\")"
                      " (lzs:redraw) (lzs:restate)")))
          ;; clicking a dimension's letter: caret into its box, with the
          ;; box's contents selected so the first keystroke replaces
          ;; rather than appends, and the dimension ringed on the chart.
          ;; Wedge dims have no pick button -- their box already sits on
          ;; the drawing where the letter was.
          (foreach d (lzs:dims c)
            (if (not (member (cadr d) (lzs:wedge-keys c)))
                (action_tile (strcat "pick_" (cadr d))
                  (strcat "(setq lzs:*focus* \"" (cadr d) "\") (lzs:redraw)"
                          " (mode_tile \"" (cadr d) "\" 2)"
                          " (mode_tile \"" (cadr d) "\" 3)"))))
          ;; the tabs -- each closes this page and names the next
          (foreach d lzs:*charts*
            (action_tile (strcat "tab_" (car d))
              (strcat "(setq lzs:*go* \"" (car d)
                      "\" lzs:*pos* (done_dialog 4))")))
          ;; the chart takes no action at all -- it is a passive image
          ;; tile, and an image_button would be wiped on hover
          (action_tile "accept" "(setq lzs:*pos* (done_dialog 1))")
          (action_tile "cancel" "(setq lzs:*pos* (done_dialog 0))")
          (lzs:redraw)
          (lzs:grey c)
          (lzs:restate)
          (setq rc (start_dialog))
          (cond
            ((= rc 4) (setq go lzs:*go*))     ; a tab: go round again
            (t (setq done t
                     out (if (= rc 1) (lzs:form))))))))))
  (if (and dcl (>= dcl 0)) (unload_dialog dcl))
  (setq dcl nil)
  (if f (vl-file-delete f))
  (setq f nil)
  out)

;;; -------------------- commands ----------------------------------------

(defun c:LAZSPA ( / form)
  (cond
    ;; the chart fills SPA's answers in, so SPA has to be here to
    ;; receive them -- say so plainly rather than opening a form whose
    ;; Insert button could only fail
    ((not spa:run-with-answers)
     (princ "\nLAZSPA: SPA is not loaded in this session -- APPLOAD")
     (princ "\n        lisp/spa/SPA.LSP, or LAZPASS.lsp which has both."))
    ((setq form (lzs:show (car (car lzs:*charts*))))
     (princ (strcat "\nLAZSPA: " (itoa (length form))
                    " answers to SPA; it will ask for whatever is left."))
     (spa:run-with-answers form))
    (t (princ "\nLAZSPA: cancelled, nothing drawn.")))
  (princ))

(defun c:LAZSPAVER ()
  (princ (strcat "\nLAZSPA " *lazspa-version* " (LAZSPA.lsp) - "
                 (itoa (length lzs:*charts*)) " chart(s)."))
  (princ))

(princ (strcat "\nLAZSPA " *lazspa-version*
               " loaded.  Type LAZSPA to fill a chart in and draw it."))
(princ)
