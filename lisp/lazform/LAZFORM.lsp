;;; ======================================================================
;;; LAZFORM.lsp  --  fill a dimension chart in, then draw the pool
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZFORM        fill in a shape chart and run POOL from it
;;;            LAZFORMVER     print the loaded version
;;;
;;; The chart on screen is the one off the paper: the pool outline, the
;;; hopper, and the dimension chain with its letters.  Type a number
;;; against a letter and the letter is REPLACED by what you typed --
;;; which is what the letter was standing in for all along.  Click
;;; anywhere on the picture and the box for the nearest dimension takes
;;; the caret, so you can work off the drawing rather than off the list.
;;; Fill in what you know, leave the rest blank, press Insert: POOL runs
;;; and asks only for the gaps.
;;;
;;; NA in a box means "not measured" and is passed through as such --
;;; different from leaving it blank, which just means POOL should ask.
;;;
;;; ZERO INSTALL, like LAZPANEL: the dialog is plain DCL written to the
;;; temp folder at run time, and the chart is drawn with vector_image,
;;; so there is no artwork file to ship and nothing to NETLOAD.
;;;
;;; WHY THE BOXES ARE BESIDE THE PICTURE AND NOT ON IT.  DCL packs tiles
;;; into rows and columns: no absolute positioning, no overlapping, so
;;; an edit box cannot sit on an image tile.  DCL also cannot display a
;;; raster at all -- an image tile takes vectors or an AutoCAD slide,
;;; nothing else.  Hence the chart is drawn rather than loaded, the
;;; numbers appear ON it as they are typed, and clicking it moves the
;;; caret: between them those two recover most of what a text box
;;; sitting on the artwork would have given, without a DLL to install.
;;;
;;; ADDING A SHAPE is adding data, not code -- one entry in
;;; lzf:*charts* with an outline, a dimension list and its POOL keys.
;;; Six charts so far: Rectangle, True Oval, Roman, both Grecians and
;;; True L Left.  Watch the keys rather than the letters when you add
;;; one: the same letter means different things on different sheets --
;;; a rectangle's B is the side length, an oval's B is the tip-to-tip
;;; total and its SIDE is T -- so the mapping is per chart and is
;;; checked against POOL's own question lists by tests/test_lazform.py.
;;; ======================================================================

(vl-load-com)

(setq *lazform-version* "v1.1")

;;; -------------------- the stroke font ---------------------------------
;;;  DCL has no way to draw text into an image tile -- vector_image draws
;;;  line segments and that is the whole of it -- so the letters and the
;;;  numbers on the chart are stroked out of segments here.
;;;
;;;  One entry per character: the glyph as a list of polylines, each a
;;;  flat list of x y x y ... in TENTHS of a font unit, on a cell 4 wide
;;;  and 6 tall with y running DOWN the way image-tile pixels do.
;;;  Integers, so nothing here depends on float formatting.

(setq lzf:*font* '(
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

(setq lzf:*font-w* 40)          ; glyph cell width, tenths
(setq lzf:*font-h* 60)          ; glyph cell height, tenths
(setq lzf:*font-adv* 56)        ; pen advance per character, tenths

;;; -------------------- the charts --------------------------------------
;;;  Everything is in PER-MILLE of the picture, x and y, y down -- the
;;;  same convention as an image tile, so the only conversion at draw
;;;  time is a multiply.  Integers again.
;;;
;;;  A chart is:
;;;    (key  pool-shape  title
;;;      (outline-polyline ...)
;;;      (dimension ...)
;;;      (column-only-field ...))
;;;
;;;  A dimension is (letter poolkey x1 y1 x2 y2 side label), where side
;;;  is "h" or "v" -- which way the measurement runs, and so where its
;;;  text sits.  The arrow, the letter and the typed value all come off
;;;  those two endpoints, so there is no separate position table that
;;;  could fall out of step with the drawing.
;;;
;;;  A column-only field is (poolkey label): a real POOL answer with no
;;;  place on the plan -- the depths are read off a section, not this
;;;  view -- so it gets a box in the list and nothing on the picture.

(setq lzf:*charts* '(
  ("Rectangle" "Rectangle" "Rectangle"
   ;; pool outline, hopper flat, the four slopes, deep-end wall
   ((100 300 900 300 900 860 100 860 100 300)
    (275 475 400 475 400 700 275 700 275 475)
    (100 300 275 475)
    (100 860 275 700)
    (400 475 685 300)
    (400 700 685 860)
    (685 300 685 860))
   (("B"  "tp" 100 175 900 175 "h" "overall across, top side")
    ("A"  "le"  45 300  45 860 "v" "overall up, left end")
    ("H"  "h"  100 580 275 580 "h" "left end to the hopper")
    ("G"  "g"  275 580 400 580 "h" "hopper length (0 = slope bottom)")
    ("F"  "f"  400 580 685 580 "h" "hopper to the slope break")
    ("E"  "e"  685 580 900 580 "h" "slope break to the right end")
    ("M"  "m"  437 300 437 475 "v" "top side to the hopper")
    ("L"  "l"  437 475 437 700 "v" "hopper width")
    ("K"  "k"  437 700 437 860 "v" "hopper to the bottom side"))
   (("bo" "overall across, bottom side (out-of-square only)")
    ("ri" "overall up, right end (out-of-square only)")
    ("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")))

  ;; ---------------- True Oval ----------------
  ;;  Careful: B is NOT the key it is on the rectangle.  A rectangle's B
  ;;  is the side length (tp); an oval's B is the tip-to-tip total
  ;;  (tot), and it is the SIDE that becomes T.  The two charts share a
  ;;  letter and not a meaning, which is exactly the sort of thing this
  ;;  table exists to write down.
  ("Oval" "Oval" "True Oval"
   (("A" 310 500 250 250 90 270)
     (310 250 690 250)
     ("A" 690 500 250 250 90 -90)
     (310 750 690 750)
     ("A" 310 500 120 120 90 270)
     (310 380 400 380) (400 380 400 620) (310 620 400 620)
     (400 380 690 250) (400 620 690 750)
     (690 250 690 750))
   (("B"  "tot" 60 130 940 130 "h" "total length, arc tip to arc tip")
    ("T"  "tp" 310 205 690 205 "h" "straight side length, top and bottom")
    ("A"  "le"  35 250  35 750 "v" "end length, left and right")
    ("H"  "h"   60 580 190 580 "h" "H - pool left tip to hopper tip")
    ("G"  "g"  190 580 400 580 "h" "G - hopper length, tip to right edge")
    ("F"  "f"  400 580 690 580 "h" "F - hopper to slope break")
    ("E"  "e"  690 580 940 580 "h" "E - slope break to pool right tip")
    ("W"  "w"  310 345 400 345 "h" "W - hopper flat top")
    ("M"  "m"  437 250 437 380 "v" "M - top side to hopper")
    ("L"  "l"  437 380 437 620 "v" "L - hopper width")
    ("K"  "k"  437 620 437 750 "v" "K - hopper to bottom side"))
   (("lr" "R1 - LEFT oval end radius")
    ("rr" "R2 - RIGHT oval end radius")
    ("r3" "R3 - hopper end radius")
    ("bo" "side length BOTTOM (out-of-square only)")
    ("ri" "end length RIGHT (out-of-square only)")))

  ;; ---------------- Roman ----------------
  ;;  S / S1 / V / R are asked once per end when both ends are "perfect"
  ;;  and twice when they are not, so the right-hand halves sit in the
  ;;  column below: fill them in and answer No to the perfect question.
  ("ROman" "ROman" "Roman"
   ((160 250 840 250)
     ("A" 840 500 100 250 90 -90)
     (840 750 160 750)
     (160 750 100 621)
     ("A" 140 500 80 140 120 240)
     (160 250 100 379)
     ("A" 330 500 110 120 90 270)
     (330 380 420 380) (420 380 420 620) (330 620 420 620)
     (420 380 700 250) (420 620 700 750)
     (700 250 700 750)
     (160 250 300 385) (160 750 300 615))
   (("B"  "b"   60 130 940 130 "h" "B - overall length")
    ("T"  "tt" 160 205 840 205 "h" "T - side length, top and bottom")
    ("A"  "a"   35 250  35 750 "v" "A - overall width")
    ("S"  "sl"  60 205 160 205 "h" "S - end setback")
    ("S1" "s1l" 90 250  90 379 "v" "S1 - corner drop")
    ("V"  "vl" 125 379 125 621 "v" "V - end width")
    ("H"  "h"   60 580 220 580 "h" "H - left end to hopper")
    ("G"  "g"  220 580 420 580 "h" "G - hopper length")
    ("F"  "f"  420 580 700 580 "h" "F - hopper to slope break")
    ("E"  "e"  700 580 940 580 "h" "E - slope break to right end")
    ("W"  "w"  330 345 420 345 "h" "W - hopper flat top")
    ("M"  "m"  455 250 455 380 "v" "M - top side to hopper")
    ("L"  "l"  455 380 455 620 "v" "L - hopper width")
    ("K"  "k"  455 620 455 750 "v" "K - hopper to bottom side"))
   (("r1" "R1 - LEFT end radius (check)")
    ("r2" "R2 - RIGHT end radius (check)")
    ("r3" "R3 - hopper end radius")
    ("sr"  "S - RIGHT end setback (ends not perfect)")
    ("s1r" "S1 - RIGHT corner drop (ends not perfect)")
    ("vr"  "V - RIGHT end width (ends not perfect)")))

  ;; ---------------- Grecian, six-sided hopper ----------------
  ;;  These letters exist only on the Overall input path with a SIX
  ;;  hopper taped by Letters, so the form answers those three gates
  ;;  itself rather than filling in boxes nothing would ever read.
  ("Grecian" "Grecian" "Grecian (6-Sided Hopper)"
   ((190 250 780 250) (780 250 900 380) (900 380 900 620)
     (900 620 780 750) (780 750 190 750) (190 750 100 620)
     (100 620 100 380) (100 380 190 250)
     (250 440 330 380) (330 380 420 380) (420 380 420 620)
     (330 620 420 620) (250 560 330 620) (250 440 250 560)
     (420 380 690 250) (420 620 690 750) (690 250 690 750)
     (190 250 250 440) (190 750 250 560))
   (("B"  "b"  100 120 900 120 "h" "B - overall length")
    ("S"  "ss" 100 195 190 195 "h" "S - corner cut along the side")
    ("T"  "tt" 190 205 780 205 "h" "T - top side length")
    ("S1" "s1"  70 250  70 380 "v" "S1 - corner cut down the end")
    ("A"  "a"   20 250  20 750 "v" "A - overall width")
    ("V"  "vv"  55 380  55 620 "v" "V - end width")
    ("H"  "h"  100 580 250 580 "h" "H - left end to hopper")
    ("G"  "g"  250 580 420 580 "h" "G - hopper length")
    ("W"  "w"  270 330 350 330 "h" "W - top flat, cut corner to hopper end")
    ("L1" "l1" 225 440 225 560 "v" "L1 - hopper left edge length")
    ("M"  "m"  455 250 455 380 "v" "M - top side to hopper")
    ("L"  "l"  455 380 455 620 "v" "L - hopper width")
    ("K"  "k"  455 620 455 750 "v" "K - hopper to bottom side")
    ("F"  "f"  420 580 690 580 "h" "F - hopper to slope break")
    ("E"  "e"  690 580 900 580 "h" "E - slope break to right end"))
   (("x"  "X - hopper cut face length (check)")
    ("s2" "S2 - corner cut face (check)"))
   (("imeth" . "Overall") ("htype" . "SIX") ("hmode" . "Letters")))

  ;; ---------------- Grecian, square hopper ----------------
  ("GRSquare" "Grecian" "Grecian (Square Hopper)"
   ((190 250 780 250) (780 250 900 380) (900 380 900 620)
     (900 620 780 750) (780 750 190 750) (190 750 100 620)
     (100 620 100 380) (100 380 190 250)
     (250 380 420 380) (420 380 420 620) (250 620 420 620)
     (250 380 250 620)
     (420 380 690 250) (420 620 690 750) (690 250 690 750)
     (190 250 250 380) (190 750 250 620))
   (("B"  "b"  100 120 900 120 "h" "B - overall length")
    ("S"  "ss" 100 195 190 195 "h" "S - corner cut along the side")
    ("T"  "tt" 190 205 780 205 "h" "T - top side length")
    ("S1" "s1"  70 250  70 380 "v" "S1 - corner cut down the end")
    ("A"  "a"   20 250  20 750 "v" "A - overall width")
    ("V"  "vv"  55 380  55 620 "v" "V - end width")
    ("H"  "h"  100 580 250 580 "h" "H - left end to hopper")
    ("G"  "g"  250 580 420 580 "h" "G - hopper length")
    ("M"  "m"  455 250 455 380 "v" "M - top side to hopper")
    ("L"  "l"  455 380 455 620 "v" "L - hopper width")
    ("K"  "k"  455 620 455 750 "v" "K - hopper to bottom side")
    ("F"  "f"  420 580 690 580 "h" "F - hopper to slope break")
    ("E"  "e"  690 580 900 580 "h" "E - slope break to right end"))
   (("s2" "S2 - corner cut face (check)"))
   (("imeth" . "Overall") ("htype" . "Square")))

  ;; ---------------- True L Left ----------------
  ;;  The six sides are POOL's ab..fa, and the chart letters walk the
  ;;  same ring: B is the bottom (A-B), A1 the right end (B-C), B2 the
  ;;  wing top (C-D), A2 the step down to the reverse corner (D-E), B1
  ;;  the main-section top (E-F), A the left end (F-A).  The "Reverse
  ;;  Corner" the sheet names is POOL's inner corner E, asked as a
  ;;  treatment and not answerable from here -- it is a corner, not a
  ;;  measurement, so it gets no box.
  ("L" "L" "True L Left"
   ((100 400 640 400) (640 400 640 150) (640 150 900 150)
     (900 150 900 850) (900 850 100 850) (100 850 100 400)
     (250 520 400 520) (400 520 400 730) (250 730 400 730)
     (250 520 250 730)
     (100 400 250 520) (100 850 250 730)
     (400 520 640 400) (400 730 640 850)
     (640 400 640 850))
   (("B"  "ab" 100 920 900 920 "h" "side A-B, bottom, full length")
    ("A1" "bc" 960 150 960 850 "v" "end B-C, right end, full height")
    ("B2" "cd" 640  90 900  90 "h" "side C-D, top of the wing")
    ("A2" "de" 600 150 600 400 "v" "step D-E, down to the reverse corner")
    ("B1" "ef" 100 340 640 340 "h" "side E-F, top of the main section")
    ("A"  "fa"  45 400  45 850 "v" "end F-A, left end")
    ("H"  "h"  100 625 250 625 "h" "H - left end to deep end")
    ("G"  "g"  250 625 400 625 "h" "G - hopper length")
    ("F"  "f"  400 625 640 625 "h" "F - hopper to slope break")
    ("E"  "e"  640 625 900 625 "h" "E - slope break to right end")
    ("M"  "m"  430 400 430 520 "v" "M - top side to hopper")
    ("L"  "l"  430 520 430 730 "v" "L - hopper width")
    ("K"  "k"  430 730 430 850 "v" "K - hopper to bottom side"))
   (("c" "C - wall height (shallow depth)")
    ("d" "D - deep end depth")))
))

;;; -------------------- asking which chart ------------------------------
;;;  The canonical keyword prompt of STANDARDS.md section 4, carried
;;;  locally: the grouped build swaps this for cal:askkw, so nothing
;;;  here may call another tool's copy of it.

(defun lzf:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'LZF-BACK)
        ((null v) (if dflt dflt (lzf:askkw msg kws shown dflt back)))
        (t v)))

;;; -------------------- chart access ------------------------------------

(defun lzf:chart (key / c out)
  (foreach c lzf:*charts*
    (if (and (not out) (= (car c) key)) (setq out c)))
  out)

(defun lzf:outline (c) (nth 3 c))
(defun lzf:dims (c) (nth 4 c))
(defun lzf:extra (c) (nth 5 c))

;; Answers a chart implies rather than asks for.  The Grecian letters
;; exist only on the Overall input path with the hopper type the chart
;; draws -- pick "Measured" instead and every letter typed here goes
;; unread -- so the chart answers those gates itself.  A chart with
;; nothing to imply simply has none.
(defun lzf:gates (c) (nth 6 c))

;; Every POOL key the chart can answer, drawn ones first, in order.
(defun lzf:keys (c / d out)
  (foreach d (lzf:dims c) (setq out (cons (cadr d) out)))
  (foreach d (lzf:extra c) (setq out (cons (car d) out)))
  (reverse out))

;;; -------------------- the answers -------------------------------------
;;;  What is typed is kept as the STRING the user typed, so the chart can
;;;  show it back exactly as entered -- 12'6" stays 12'6" -- and it is
;;;  only turned into a number when POOL is handed the form.

(setq lzf:*vals* nil)           ; ((key . "typed") ...)
(setq lzf:*focus* nil)          ; the key whose box has the caret
(setq lzf:*chart* nil)          ; the chart being filled in

(defun lzf:get (key / p)
  (if (setq p (assoc key lzf:*vals*)) (cdr p) ""))

(defun lzf:put (key v / out p)
  (foreach p lzf:*vals* (if (/= (car p) key) (setq out (cons p out))))
  (setq lzf:*vals* (reverse (cons (cons key v) out))))

;;; -------------------- drawing the chart -------------------------------
;;;  Pixel coordinates, origin top-left, y down -- image-tile convention,
;;;  which is why the per-mille data is stored that way too and needs no
;;;  flipping here.  dimx_tile / dimy_tile report the LARGEST legal
;;;  coordinate, not the size, and are only answerable while the dialog
;;;  is up, so everything below runs between new_dialog and start_dialog.

(setq lzf:*dx* 0)               ; the tile's extent this time round
(setq lzf:*dy* 0)

(setq lzf:*col-line* -16)       ; dialog foreground: the outline
(setq lzf:*col-back* -15)       ; dialog background: the clear
(setq lzf:*col-dim* 8)          ; grey: the dimension arrows
(setq lzf:*col-val* 30)         ; orange: a value that has been typed
(setq lzf:*col-hi* 5)           ; blue: the box round the active one

;; per-mille -> pixels
(defun lzf:px (v) (fix (/ (* v lzf:*dx*) 1000.0)))
(defun lzf:py (v) (fix (/ (* v lzf:*dy*) 1000.0)))

;;  An outline element is either a POLYLINE -- a flat list of per-mille
;;  numbers, x y x y ... -- or an ARC, written
;;
;;      ("A" cx cy rx ry from to)
;;
;;  with the centre and both radii in per-mille and the angles in
;;  degrees, 0 due east and counting anticlockwise ON SCREEN.  Since
;;  image-tile y runs DOWN, that is a minus on the y term and nowhere
;;  else.  Two radii rather than one because these charts want half of
;;  an ellipse as often as half of a circle.
;;
;;  DCL draws line segments and nothing else, so an arc has to become a
;;  polyline sooner or later; doing it here means the chart data can say
;;  what it means and say it once.

(defun lzf:arcpts (a / cx cy rx ry f to n i ang out)
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
(defun lzf:flatten (e)
  (if (= (type (car e)) 'STR) (lzf:arcpts e) e))

;; A polyline given as a flat per-mille list, in pixels.
(defun lzf:pline (flat col / a b)
  (while (and flat (cddr flat))
    (setq a (list (lzf:px (car flat)) (lzf:py (cadr flat)))
          b (list (lzf:px (caddr flat)) (lzf:py (cadddr flat))))
    (vector_image (car a) (cadr a) (car b) (cadr b) col)
    (setq flat (cddr flat))))

;; A polyline already in pixels, given as (x y x y ...).
(defun lzf:plinepx (flat col)
  (while (and flat (cddr flat))
    (vector_image (car flat) (cadr flat) (caddr flat) (cadddr flat) col)
    (setq flat (cddr flat))))

(defun lzf:glyph (ch / p out)
  (if (setq p (assoc (strcase ch) lzf:*font*)) (cdr p)))

;; The width one string will occupy, in pixels, at SC tenths per unit.
(defun lzf:textw (s sc)
  (if (= s "") 0
      (fix (/ (* (- (* (strlen s) lzf:*font-adv*)
                    (- lzf:*font-adv* lzf:*font-w*))
                 sc)
              100.0))))

(defun lzf:texth (sc) (fix (/ (* lzf:*font-h* sc) 100.0)))

;; The size to letter the chart at.  Derived from the tile rather than
;; fixed: an image tile's pixel size falls out of the user's dialog font
;; and display DPI, and is not knowable until the dialog is up.  This
;; puts a glyph at about a twenty-sixth of the picture's height, which
;; is the size the paper charts letter at.
(defun lzf:basesc ( / sc)
  (setq sc (/ (* lzf:*dy* 100) 1560))
  (if (< sc 12) 12 sc))

;; Stroke S with its top-left corner at pixel X Y.  SC is a percentage
;; of the font's own tenth-units, so the caller can size text to fit.
(defun lzf:text (s x y sc col / i ch pen poly out n)
  (setq i 1 pen x)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (foreach poly (lzf:glyph ch)
      (setq out nil n poly)
      (while n
        (setq out (cons (+ y (fix (/ (* (cadr n) sc) 100.0)))
                        (cons (+ pen (fix (/ (* (car n) sc) 100.0))) out))
              n (cddr n)))
      (lzf:plinepx (reverse out) col))
    (setq pen (+ pen (fix (/ (* lzf:*font-adv* sc) 100.0)))
          i (1+ i)))
  pen)

;; The dimension line with an arrowhead at each end.  Only horizontal
;; and vertical dimensions exist on these charts, which is why the two
;; cases below are the whole of it.
(defun lzf:arrow (x1 y1 x2 y2 col / a b)
  (vector_image x1 y1 x2 y2 col)
  (setq a 6 b 3)
  (cond
    ((= y1 y2)                          ; horizontal: heads point out
     (vector_image x1 y1 (+ x1 a) (- y1 b) col)
     (vector_image x1 y1 (+ x1 a) (+ y1 b) col)
     (vector_image x2 y2 (- x2 a) (- y2 b) col)
     (vector_image x2 y2 (- x2 a) (+ y2 b) col))
    (t                                  ; vertical
     (vector_image x1 y1 (- x1 b) (+ y1 a) col)
     (vector_image x1 y1 (+ x1 b) (+ y1 a) col)
     (vector_image x2 y2 (- x2 b) (- y2 a) col)
     (vector_image x2 y2 (+ x2 b) (- y2 a) col))))

;; Where one dimension's text belongs, and what it says: the LETTER
;; until a value is typed, then the value in the letter's place.  A
;; value too wide for its own span is shrunk to fit rather than allowed
;; to run into its neighbours -- H, G, F and E sit shoulder to shoulder
;; along the middle of the chart and every one of them can carry a
;; five-character feet-and-inches number.
(defun lzf:label (d / letter key x1 y1 x2 y2 side txt sc w h lx ly span mx my)
  (setq letter (car d) key (cadr d)
        x1 (lzf:px (nth 2 d)) y1 (lzf:py (nth 3 d))
        x2 (lzf:px (nth 4 d)) y2 (lzf:py (nth 5 d))
        side (nth 6 d)
        txt (lzf:get key)
        mx (/ (+ x1 x2) 2) my (/ (+ y1 y2) 2))
  (if (= txt "")
      (setq txt letter sc (lzf:basesc))
      (setq sc (/ (* (lzf:basesc) 90) 100)))
  (setq w (lzf:textw txt sc))
  (if (and (= side "h") (> w 0))
      (progn
        (setq span (abs (- x2 x1)))
        (if (> w span)
            (progn
              (setq sc (/ (* sc span) w))
              (if (< sc (/ (* (lzf:basesc) 55) 100))
                  (setq sc (/ (* (lzf:basesc) 55) 100)))
              (setq w (lzf:textw txt sc))))))
  (setq h (lzf:texth sc))
  (if (= side "h")
      (setq lx (- mx (/ w 2)) ly (- y1 h 4))
      ;; a vertical dimension labels at the TOP of its span: the middle
      ;; row already carries the H/G/F/E chain across the pool.  It is
      ;; centred on its own line, EXCEPT when that would run off the
      ;; left edge -- an overall like A sits hard against the boundary
      ;; with no room on its outside, so its label goes on the inside
      ;; rather than being clipped down to a stub
      (progn
        (setq ly (+ (min y1 y2) 5))
        (setq lx (if (< (- mx (/ w 2)) 2) (+ mx 4) (- mx (/ w 2))))))
  ;; and nothing is allowed off the edge of the picture
  (if (< lx 2) (setq lx 2))
  (if (> (+ lx w) (- lzf:*dx* 2)) (setq lx (- lzf:*dx* w 2)))
  (if (< ly 2) (setq ly 2))
  (if (> (+ ly h) (- lzf:*dy* 2)) (setq ly (- lzf:*dy* h 2)))
  ;; blank the strip behind it so the dimension line does not run
  ;; through the characters
  (fill_image (- lx 3) (- ly 2) (+ w 6) (+ h 4) lzf:*col-back*)
  (if (= key lzf:*focus*)
      (lzf:plinepx (list (- lx 3) (- ly 2) (+ lx w 3) (- ly 2)
                         (+ lx w 3) (+ ly h 2) (- lx 3) (+ ly h 2)
                         (- lx 3) (- ly 2))
                   lzf:*col-hi*))
  (lzf:text txt lx ly sc
            (if (= (lzf:get key) "") lzf:*col-line* lzf:*col-val*)))

;; The whole picture, start to end.  Every vector goes between one
;; start_image and one end_image so the tile is painted once.
(defun lzf:redraw ( / c poly d)
  (setq c lzf:*chart*
        lzf:*dx* (dimx_tile "chart")
        lzf:*dy* (dimy_tile "chart"))
  (start_image "chart")
  (fill_image 0 0 lzf:*dx* lzf:*dy* lzf:*col-back*)
  (foreach poly (lzf:outline c)
    (lzf:pline (lzf:flatten poly) lzf:*col-line*))
  (foreach d (lzf:dims c)
    (lzf:arrow (lzf:px (nth 2 d)) (lzf:py (nth 3 d))
               (lzf:px (nth 4 d)) (lzf:py (nth 5 d)) lzf:*col-dim*))
  (foreach d (lzf:dims c) (lzf:label d))
  (end_image)
  (princ))

;;; -------------------- clicking the picture ----------------------------
;;  An image_button reports where it was picked, so the nearest
;;  dimension to the click takes the caret.  This is what stands in for
;;  a text box sitting on the artwork: you work off the drawing, and the
;;  typing happens in the box the click just moved you to.

(defun lzf:nearest (x y / c d best bd mx my dd)
  (setq c lzf:*chart*)
  (foreach d (lzf:dims c)
    (setq mx (/ (+ (lzf:px (nth 2 d)) (lzf:px (nth 4 d))) 2)
          my (/ (+ (lzf:py (nth 3 d)) (lzf:py (nth 5 d))) 2)
          dd (+ (* (- x mx) (- x mx)) (* (- y my) (- y my))))
    (if (or (not best) (< dd bd)) (setq best (cadr d) bd dd)))
  best)

(defun lzf:pick (x y / key)
  (if (setq key (lzf:nearest x y))
      (progn
        (setq lzf:*focus* key)
        (mode_tile key 2)               ; move the caret to its box
        (lzf:redraw)))
  (princ))

;;; -------------------- which chart -------------------------------------

;; The keyword list, straight off the chart table: a chart added below
;; is offered here without touching this code.
(defun lzf:keywords ( / c out)
  (foreach c lzf:*charts*
    (setq out (if out (strcat out " " (car c)) (car c))))
  out)

(defun lzf:pickchart ( / kws)
  (setq kws (lzf:keywords))
  (lzf:askkw "Which chart" kws (vl-string-translate " " "/" kws)
             (car (car lzf:*charts*)) nil))

;;; -------------------- the dialog --------------------------------------
;;  Two columns: the chart on the left as an image_button, the boxes on
;;  the right in the chart's own order, each labelled with its letter so
;;  the list and the picture read as one thing.

(setq lzf:*btypes* '("Normal" "Sport" "Wedge" "SLope" "MOdflat" "SHallow"))

(defun lzf:dcl-lines ( / c out d)
  (setq c lzf:*chart*)
  (setq out (list "  : row {"
                  (strcat "  label = \"LazForm - " (caddr c) "\";")
                  "lazform : dialog {"))
  (setq out (cons (strcat "    : image_button { key = \"chart\"; "
                          "width = 52; aspect_ratio = 0.72; "
                          "fixed_width = true; fixed_height = true; "
                          "color = -15; }")
                  out))
  (setq out (cons "    : column {" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Dimensions\";" out))
  (foreach d (lzf:dims c)
    (setq out (cons (strcat "        : edit_box { key = \"" (cadr d)
                            "\"; edit_width = 10; label = \"" (car d)
                            "  " (nth 7 d) "\"; }")
                    out)))
  (setq out (cons "      }" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Not on this view\";" out))
  (foreach d (lzf:extra c)
    (setq out (cons (strcat "        : edit_box { key = \"" (car d)
                            "\"; edit_width = 10; label = \"" (cadr d)
                            "\"; }")
                    out)))
  (setq out (cons "      }" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"The rest of the run\";" out))
  (setq out (cons (strcat "        : toggle { key = \"insq\"; "
                          "label = \"Pool is in-square (no cross dims)\"; }")
                  out))
  (setq out (cons (strcat "        : popup_list { key = \"btype\"; "
                          "label = \"Bottom type\"; }")
                  out))
  (setq out (cons "      }" out))
  (setq out (cons "    }" out))
  (setq out (cons "  }" out))
  (setq out (cons "  spacer;" out))
  (setq out (cons (strcat "  : text { key = \"hint\"; width = 62; "
                          "label = \"Type NA where nothing was measured; "
                          "leave a box empty and POOL will ask.\"; }")
                  out))
  (setq out (cons "  : row {" out))
  (setq out (cons (strcat "    : button { key = \"accept\"; label = \"Insert\"; "
                          "is_default = true; fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : button { key = \"cancel\"; label = \"Cancel\"; "
                          "is_cancel = true; fixed_width = true; }")
                  out))
  (setq out (cons "  }" out))
  (reverse (cons "}" out)))

(defun lzf:write-lines (fh / l)
  (foreach l (lzf:dcl-lines) (write-line l fh)))

(defun lzf:write-dcl ( / f fh err)
  (setq f (vl-filename-mktemp "lazform" nil ".dcl"))
  (if (and f (setq fh (open f "w")))
    (progn
      (setq err (vl-catch-all-apply 'lzf:write-lines (list fh)))
      (close fh)
      (cond
        ((vl-catch-all-error-p err) (vl-file-delete f) nil)
        (t f)))))

;;; -------------------- what POOL is handed -----------------------------
;;;  The three states of STANDARDS.md's form contract, decided here:
;;;
;;;    box left empty   the key is not sent at all -> POOL asks
;;;    NA typed in it   (key . nil) is sent        -> POOL takes NA
;;;    a measurement    (key . 84.0) is sent       -> POOL takes it
;;;
;;;  Anything that is neither NA nor a distance AutoCAD can read is
;;;  treated as an empty box: a typo must leave POOL asking rather than
;;;  quietly feeding it a nil that means something else entirely.
;;;  distof reads the architectural spellings, so 25'6" and 25'-6-1/2"
;;;  arrive as the numbers they look like.

(defun lzf:answer (v / n)
  (cond
    ((or (null v) (= v "")) 'SKIP)
    ((= (strcase (lzf:trim v)) "NA") nil)
    ((setq n (distof (lzf:trim v) 4)) n)
    ((setq n (distof (lzf:trim v) 2)) n)
    (t 'SKIP)))

(defun lzf:trim (s / i n)
  (setq i 1 n (strlen s))
  (while (and (<= i n) (= (substr s i 1) " ")) (setq i (1+ i)))
  (while (and (>= n i) (= (substr s n 1) " ")) (setq n (1- n)))
  (if (> i n) "" (substr s i (1+ (- n i)))))

;; The alist POOL reads, built from what was typed.
(defun lzf:form (shape insq btype / out k v a)
  (setq out (list (cons 'shape shape)
                  (cons 'insq (if insq "Insquare" "Outofsquare"))))
  (if (and btype (/= btype "")) (setq out (cons (cons 'btype btype) out)))
  (foreach k (lzf:keys lzf:*chart*)
    (setq v (lzf:get k)
          a (lzf:answer v))
    (if (not (eq a 'SKIP))
        (setq out (cons (cons (read k) a) out))))
  ;; the gates last, so a chart cannot be talked out of the path its
  ;; own letters live on
  (foreach k (lzf:gates lzf:*chart*)
    (setq out (cons (cons (read (car k)) (cdr k)) out)))
  (reverse out))

;;; -------------------- the run -----------------------------------------
;;  A helper rather than the command body, so its localized *error* is
;;  out of scope by the time POOL is started: POOL installs its own, and
;;  a POOL that fails must report as POOL.

(defun lzf:show (chartkey / *error* f dcl rc c d bi)
  (defun *error* (msg)
    (term_dialog)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (setq dcl nil)
    (if f (vl-file-delete f))
    (setq f nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZFORM error: " msg)))
    (princ))
  (setq lzf:*chart* (lzf:chart chartkey)
        lzf:*vals* nil
        lzf:*focus* nil
        c lzf:*chart*)
  (cond
    ((not c) (princ (strcat "\nLAZFORM: no chart called " chartkey ".")))
    ((not (setq f (lzf:write-dcl)))
     (princ "\nLAZFORM error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZFORM error: could not load the dialog file."))
    ((not (new_dialog "lazform" dcl))
     (princ "\nLAZFORM error: could not open the form."))
    (t
     (start_list "btype")
     (foreach d lzf:*btypes* (add_list d))
     (end_list)
     (set_tile "btype" "0")
     ;; every box redraws the chart when it is left, which is when DCL
     ;; reports an edit box changed
     (foreach d (lzf:keys c)
       (action_tile d
         (strcat "(lzf:put \"" d "\" $value) (setq lzf:*focus* \"" d "\")"
                 " (lzf:redraw)")))
     (action_tile "chart" "(lzf:pick $x $y)")
     (action_tile "accept" "(done_dialog 1)")
     (action_tile "cancel" "(done_dialog 0)")
     (lzf:redraw)
     (setq rc (start_dialog))
     (setq bi (atoi (get_tile "btype")))))
  (if (and dcl (>= dcl 0)) (unload_dialog dcl))
  (setq dcl nil)
  (if f (vl-file-delete f))
  (setq f nil)
  (if (and rc (= rc 1))
      (lzf:form (cadr c)
                (= (get_tile "insq") "1")
                (nth (if bi bi 0) lzf:*btypes*))))

;;; -------------------- commands ----------------------------------------

(defun c:LAZFORM ( / form)
  (cond
    ;; the chart fills POOL's answers in, so POOL has to be here to
    ;; receive them -- say so plainly rather than opening a form whose
    ;; Insert button could only fail
    ((not pool:run-with-answers)
     (princ "\nLAZFORM: POOL is not loaded in this session -- APPLOAD")
     (princ "\n         lisp/pool/POOL.LSP, or LAZPASS.lsp which has both."))
    ((setq form (lzf:show (lzf:pickchart)))
     (princ (strcat "\nLAZFORM: " (itoa (length form))
                    " answers to POOL; it will ask for whatever is left."))
     (pool:run-with-answers form))
    (t (princ "\nLAZFORM: cancelled, nothing drawn.")))
  (princ))

(defun c:LAZFORMVER ()
  (princ (strcat "\nLAZFORM " *lazform-version* " (LAZFORM.lsp) - "
                 (itoa (length lzf:*charts*)) " chart(s)."))
  (princ))

(princ (strcat "\nLAZFORM " *lazform-version*
               " loaded.  Type LAZFORM to fill a chart in and draw it."))
(princ)
