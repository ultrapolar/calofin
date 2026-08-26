;;; ======================================================================
;;; LAZFORM.lsp  --  fill a dimension chart in, then draw the pool
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZFORM        fill in a shape chart and run POOL from it
;;;            LAZASCII       probe: could the chart be drawn in text?
;;;            LAZFORMVER     print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; The chart on screen is the one off the paper: the pool outline, the
;;; hopper, and the dimension chain with its letters.  Type a number
;;; against a letter and the letter is REPLACED by what you typed --
;;; which is what the letter was standing in for all along.  Every box
;;; is labelled with its own letter, so the list and the picture read
;;; as one thing.  Fill in what you know, leave the rest blank, press
;;; Insert: POOL runs and asks only for the gaps.
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
;;; (An earlier version also let you click the picture to jump to a
;;; box; DCL took that back -- see "why the picture is not clickable".)
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

(setq *lazform-version* "v2.1")

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
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break")))

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
    ("ri" "end length RIGHT (out-of-square only)")
    ("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break")))

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
    ("vr"  "V - RIGHT end width (ends not perfect)")
    ("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break")))

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
    ("S"  "ss" 100 205 190 205 "h" "S - corner cut along the side")
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
    ("s2" "S2 - corner cut face (check)")
    ("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break"))
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
    ("S"  "ss" 100 205 190 205 "h" "S - corner cut along the side")
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
   (("s2" "S2 - corner cut face (check)")
    ("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break"))
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
    ("d" "D - deep end depth")
    ("c2" "C2 - shallow floor at the break")))

  ;; ---------------- Round ----------------
  ;;  POOL's ROUnd flow asks two overalls -- B across and A up, both
  ;;  through the middle -- and then hands the bottom to the SAME
  ;;  hopper routine the oval uses (pool:hopovaldsp), so the hopper
  ;;  letters here are the oval's: H G F E, W, M L K.  The plan pair is
  ;;  NOT the oval's: a round pool answers b and a, where an oval
  ;;  answers tot, tp and le.
  ;;
  ;;  In square, POOL asks one diameter and keys it 'b -- so B is the
  ;;  box that matters and A goes unread.  Tick the in-square toggle
  ;;  and fill B in.
  ;;
  ;;  M L K RUN THROUGH THE CENTRE, and they have to.  POOL resolves
  ;;  that chain against the overall width, so M+L+K must equal A --
  ;;  and on a circle the only vertical that is a full diameter is the
  ;;  one through the middle.  Measured anywhere else it comes up short
  ;;  (the first draft put them at the hopper's own x and the chain
  ;;  closure test caught it: 460 against an A of 500).  So the hopper
  ;;  is drawn wide enough to cross that centre line, which is also
  ;;  where the tape goes.
  ;;
  ;;  H G F E ARE COLUMN BOXES HERE, not a wedge row on the drawing.
  ;;  A wedge box is its letter plus ten cells, so four of them need 44
  ;;  of the chart's 52 -- and a round pool spans about 31.  On the
  ;;  rectangle the chain runs the full width and just fits; on a
  ;;  circle it cannot, and forcing it makes boxes that sit nowhere
  ;;  near the letters they belong to.  So this chart declares cuts for
  ;;  B and W only and the chain is answered in the list, where it has
  ;;  room.  Every dimension is still enterable; only the position of
  ;;  four boxes differs.
  ("ROUnd" "ROUnd" "Round"
   (("A" 500 500 250 250 0 360)
    ("A" 390 500 70 70 90 270)
    (390 430 540 430) (540 430 540 570) (390 570 540 570)
    (540 430 660 350) (540 570 660 650)
    (660 350 660 650))
   (("B"  "b"  250 150 750 150 "h" "B - overall length (across)")
    ("A"  "a"  175 250 175 750 "v" "A - overall width (up)")
    ("H"  "h"  250 600 320 600 "h" "H - pool left edge to hopper tip")
    ("G"  "g"  320 600 540 600 "h" "G - hopper length, tip to right edge")
    ("F"  "f"  540 600 660 600 "h" "F - hopper to slope break")
    ("E"  "e"  660 600 750 600 "h" "E - slope break to pool right edge")
    ("W"  "w"  390 405 540 405 "h" "W - hopper flat top")
    ("M"  "m"  500 250 500 430 "v" "M - top of pool to hopper")
    ("L"  "l"  500 430 500 570 "v" "L - hopper width")
    ("K"  "k"  500 570 500 750 "v" "K - hopper to bottom of pool"))
   (("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break")))
))

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

;;; -------------------- where the chart is cut ---------------------------
;;;  The closest DCL comes to boxes ON the drawing: the chart is cut
;;;  into horizontal bands at the heights where its horizontal
;;;  dimension rows run, and those rows are REAL edit boxes wedged
;;;  between the bands, pushed to their letters' positions by spacers.
;;;  The vertical dimensions cannot be wedged -- a box cannot stand
;;;  sideways in a row -- so they keep their boxes in the side column
;;;  with their values drawn on the chart as before.
;;;
;;;  A cut is a per-mille y that must land EXACTLY on a horizontal
;;;  dimension's line; every "h" dimension at that y becomes a wedge
;;;  box and loses its drawn arrow, since the row of boxes IS that row
;;;  of the drawing now.  tests/test_lazform.py checks both ways: no
;;;  cut without dims on it, and the wedge boxes sitting where the
;;;  letters were, within the tolerance spacer widths allow.

(setq lzf:*cuts* '(("Rectangle" 175 580)
                   ("Oval" 130 205 345 580)
                   ("ROman" 130 205 345 580)
                   ("Grecian" 120 205 330 580)
                   ("GRSquare" 120 205 580)
                   ("L" 90 340 625 920)
                   ("ROUnd" 150 405)))

(defun lzf:cuts (c) (cdr (assoc (car c) lzf:*cuts*)))

;;; -------------------- corners -----------------------------------------
;;;  A corner is a treatment plus, when the treatment is Radius or Cut,
;;;  a size -- so each gets a dropdown and a size box that is greyed
;;;  until a sized treatment is picked.  The dropdown's first entry is
;;;  "(ask)": the form's version of leaving a box empty, and the only
;;;  honest default, since POOL offers no default on a first corner
;;;  either.  Only the charts whose POOL flow asks in these terms carry
;;;  corner rows; Roman and the Grecians spell their corners as letter
;;;  dimensions that are already on the chart.
;;;
;;;  In-square is the one wrinkle: an in-square rectangle asks ONE
;;;  question for all four corners, under its own key -- so when the
;;;  toggle is on, corner A's row speaks for all four and the other
;;;  three are ignored (lzf:form does the mapping).

(setq lzf:*ctreat* '("(ask)" "Square" "Radius" "Cut" "NotGiven"))

(setq lzf:*corners*
  '(("Rectangle"
     ("cornera" "Corner A (bottom left)")
     ("cornerb" "Corner B (bottom right)")
     ("cornerc" "Corner C (top right)")
     ("cornerd" "Corner D (top left)"))
    ("L"
     ("outercorners" "Outer corners (all five)")
     ("innercorner" "Reverse corner E"))))

(defun lzf:corners (c) (cdr (assoc (car c) lzf:*corners*)))

;; the dropdown selections, by stem: ((\"cornera\" . 3) ...)
(setq lzf:*cvals* nil)

(defun lzf:cget (stem / p)
  (if (setq p (assoc stem lzf:*cvals*)) (cdr p) 0))

(defun lzf:cput (stem i / out p)
  (foreach p lzf:*cvals* (if (/= (car p) stem) (setq out (cons p out))))
  (setq lzf:*cvals* (reverse (cons (cons stem i) out))))

;; is selection I a sized treatment?  2 = Radius, 3 = Cut
(defun lzf:csized (i) (member i '(2 3)))

;; the dropdown changed: remember it, grey or un-grey the size box,
;; and repaint the chart the list may have unrolled across
(defun lzf:cornerpick (stem v / i)
  (setq i (atoi v))
  (lzf:cput stem i)
  (mode_tile (strcat stem "-sz") (if (lzf:csized i) 0 1))
  (lzf:redraw)
  (princ))

;; The horizontal dims whose line IS this cut.
(defun lzf:cutdims (c y / d out)
  (foreach d (lzf:dims c)
    (if (and (= (nth 6 d) "h") (= (nth 3 d) y) (= (nth 5 d) y))
        (setq out (cons d out))))
  (reverse out))

;; Keys of every dim that lives in a wedge row rather than the column.
(defun lzf:wedge-keys (c / y d out)
  (foreach y (lzf:cuts c)
    (foreach d (lzf:cutdims c y)
      (setq out (cons (cadr d) out))))
  (reverse out))

;; The bands between the cuts: ((y0 . y1) ...), whole chart when a
;; chart declares no cuts.
(defun lzf:bands (c / ys prev out y)
  (setq ys (append (list 0) (lzf:cuts c) (list 1000))
        prev (car ys))
  (foreach y (cdr ys)
    (setq out (cons (cons prev y) out)
          prev y))
  (reverse out))

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
(setq lzf:*insq* nil)           ; the in-square toggle, as it is set
(setq lzf:*btype* 0)            ; the bottom-type row, as it is picked
(setq lzf:*pos* nil)            ; where the dialog was last standing
(setq lzf:*go* nil)             ; the chart a tab click asked for

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
(setq lzf:*y0* 0)               ; the band being drawn, in per-mille --
(setq lzf:*y1* 1000)            ; the whole chart when nothing is cut

(setq lzf:*col-line* -16)       ; dialog foreground: the outline
(setq lzf:*col-back* -15)       ; dialog background: the clear
(setq lzf:*col-dim* 8)          ; grey: the dimension arrows
(setq lzf:*col-val* 30)         ; orange: a value that has been typed
(setq lzf:*col-hi* 5)           ; blue: the box round the active one

;; per-mille -> pixels
(defun lzf:px (v) (fix (/ (* v lzf:*dx*) 1000.0)))
(defun lzf:py (v)
  (fix (/ (* (- v lzf:*y0*) lzf:*dy*) (float (- lzf:*y1* lzf:*y0*)))))

(defun lzf:iny (v) (and (<= lzf:*y0* v) (<= v lzf:*y1*)))

;; The segment, clipped to the band, or nil when none of it is inside.
;; Everything the bands draw goes through this, so a cut is one rule
;; applied everywhere rather than per-shape case work.
(defun lzf:clipseg (x1 y1 x2 y2 / ta tb lo hi)
  (cond
    ((= y1 y2)
     (if (lzf:iny y1) (list x1 y1 x2 y2)))
    (t
     (setq ta (/ (- lzf:*y0* y1) (float (- y2 y1)))
           tb (/ (- lzf:*y1* y1) (float (- y2 y1)))
           lo (max 0.0 (min ta tb))
           hi (min 1.0 (max ta tb)))
     (if (< lo hi)
         (list (+ x1 (* (- x2 x1) lo)) (+ y1 (* (- y2 y1) lo))
               (+ x1 (* (- x2 x1) hi)) (+ y1 (* (- y2 y1) hi)))))))

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

;; A polyline given as a flat per-mille list, clipped to the band.
(defun lzf:pline (flat col / s)
  (while (and flat (cddr flat))
    (if (setq s (lzf:clipseg (car flat) (cadr flat)
                             (caddr flat) (cadddr flat)))
        (vector_image (lzf:px (car s)) (lzf:py (cadr s))
                      (lzf:px (caddr s)) (lzf:py (cadddr s)) col))
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

;; The dimension line with an arrowhead at each end, in per-mille,
;; clipped to the band.  A head is drawn only when its own end is
;; inside the band -- the shaft of a vertical dimension can run
;; through several bands, and each draws just its stretch.
(defun lzf:arrow (x1 y1 x2 y2 col / s a b p q)
  (if (setq s (lzf:clipseg x1 y1 x2 y2))
      (vector_image (lzf:px (car s)) (lzf:py (cadr s))
                    (lzf:px (caddr s)) (lzf:py (cadddr s)) col))
  (setq a 6 b 3)
  (cond
    ((= y1 y2)                          ; horizontal: heads point in
     (if (lzf:iny y1)
         (progn
           (setq p (list (lzf:px (min x1 x2)) (lzf:py y1))
                 q (list (lzf:px (max x1 x2)) (lzf:py y1)))
           (vector_image (car p) (cadr p) (+ (car p) a) (- (cadr p) b) col)
           (vector_image (car p) (cadr p) (+ (car p) a) (+ (cadr p) b) col)
           (vector_image (car q) (cadr q) (- (car q) a) (- (cadr q) b) col)
           (vector_image (car q) (cadr q) (- (car q) a) (+ (cadr q) b) col))))
    (t                                  ; vertical
     (if (lzf:iny (min y1 y2))
         (progn
           (setq p (list (lzf:px x1) (lzf:py (min y1 y2))))
           (vector_image (car p) (cadr p) (- (car p) b) (+ (cadr p) a) col)
           (vector_image (car p) (cadr p) (+ (car p) b) (+ (cadr p) a) col)))
     (if (lzf:iny (max y1 y2))
         (progn
           (setq q (list (lzf:px x1) (lzf:py (max y1 y2))))
           (vector_image (car q) (cadr q) (- (car q) b) (- (cadr q) a) col)
           (vector_image (car q) (cadr q) (+ (car q) b) (- (cadr q) a) col))))))

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

;; The band a dimension's TEXT belongs to: a horizontal dim sits on
;; its own line, a vertical one labels at the top of its span.
(defun lzf:anchor (d)
  (if (= (nth 6 d) "h")
      (nth 3 d)
      (min (nth 3 d) (nth 5 d))))

(defun lzf:inband (v) (and (<= lzf:*y0* v) (< v lzf:*y1*)))

;; The whole picture: every band painted once, each between its own
;; start_image and end_image.  Wedge dims draw nothing at all -- their
;; row of the drawing IS a row of real boxes now -- while every other
;; dim draws its clipped arrow in every band it crosses and its text
;; in the band its anchor falls in.
(defun lzf:redraw ( / c wk bands b i key poly d)
  (setq c lzf:*chart*
        wk (lzf:wedge-keys c)
        bands (lzf:bands c)
        i 0)
  (foreach b bands
    (setq key (strcat "chart" (itoa i))
          lzf:*y0* (car b)
          lzf:*y1* (cdr b)
          lzf:*dx* (dimx_tile key)
          lzf:*dy* (dimy_tile key))
    (start_image key)
    (fill_image 0 0 lzf:*dx* lzf:*dy* lzf:*col-back*)
    (foreach poly (lzf:outline c)
      (lzf:pline (lzf:flatten poly) lzf:*col-line*))
    (foreach d (lzf:dims c)
      (if (not (member (cadr d) wk))
          (lzf:arrow (nth 2 d) (nth 3 d) (nth 4 d) (nth 5 d)
                     lzf:*col-dim*)))
    (foreach d (lzf:dims c)
      (if (and (not (member (cadr d) wk))
               (lzf:inband (lzf:anchor d)))
          (lzf:label d)))
    (end_image)
    (setq i (1+ i)))
  (setq lzf:*y0* 0
        lzf:*y1* 1000)
  (princ))

;;; -------------------- why the picture is not clickable ----------------
;;;
;;;  It was, once: an image_button reports the point it was picked at,
;;;  so a click near a dimension could move the caret to that box.  It
;;;  had to go.  An image_button is repainted when the mouse enters it
;;;  and again when it leaves, and a DCL image tile is NOT retained by
;;;  AutoCAD -- a repaint clears the tile to its own colour attribute
;;;  and everything the application drew into it is gone.  There is no
;;;  expose callback to redraw from, so the chart vanished the first
;;;  time the cursor crossed it.
;;;
;;;  A plain image tile is passive: no highlight, no repaint, nothing
;;;  to vanish.  The cost is that the picture is read rather than
;;;  clicked, and the letter at the front of each box's label is what
;;;  ties the two together instead.
;;;
;;;  The same retention rule is why lzf:redraw runs after the
;;;  bottom-type list and the in-square toggle as well as after every
;;;  edit box: a list unrolling over the chart damages it the same way,
;;;  and nothing else would repair it.

;;; -------------------- the dialog --------------------------------------
;;  Two columns: the chart on the left as a passive image, the boxes on
;;  the right in the chart's own order, each labelled with its letter so
;;  the list and the picture read as one thing.

(setq lzf:*btypes* '("Normal" "Sport" "Wedge" "SLope" "MOdflat" "SHallow"))

(defun lzf:tabstrip (cur / out c)
  ;; The tab strip: one button per chart, the current one disabled so
  ;; it reads as the page you are on.  DCL has no tab tile and no way
  ;; to hide or restyle one, so "which page am I on" is carried by that
  ;; greyed button and by the dialog's own title bar.
  (setq out (list "  : row {"))
  ;; the KEY, not the title: six full chart titles make a row 117
  ;; characters wide, twice the chart it sits above, and a dialog wider
  ;; than the screen has nowhere to go -- DCL does not scroll
  (foreach c lzf:*charts*
    (setq out (cons (strcat "    : button { key = \"tab_" (car c)
                            "\"; label = \"" (car c) "\"; }")
                    out)))
  (reverse (cons "  }" out)))

(setq lzf:*chart-w* 52)         ; the chart column, in character cells
(setq lzf:*chart-h* 19)         ; its total height, spread over the bands

;; character cells across for a per-mille x
(defun lzf:cellx (v) (/ (* v lzf:*chart-w*) 1000.0))

;; One wedge row: the cut's dims as real edit boxes, pushed to their
;; letters' positions by spacers.  Positions are in character cells and
;; a box has its own minimum size, so this is honest about being
;; approximate: a box lands within a cell or so of its letter, and two
;; that would collide get pushed apart rather than overlapped.
(defun lzf:wedgerow (c y / out d lbl w want pos)
  (setq out (list "      : row {")
        pos 0.0)
  ;; LEFT TO RIGHT, whatever order the chart lists them in: the row is
  ;; built by walking a cursor across it, and a dim listed before its
  ;; left-hand neighbour would shove that neighbour to the wrong side
  ;; of the chart
  (foreach d (vl-sort (lzf:cutdims c y)
                      '(lambda (p q)
                         (< (+ (nth 2 p) (nth 4 p))
                            (+ (nth 2 q) (nth 4 q)))))
    (setq lbl (car d)
          w (+ (strlen lbl) 10.0)       ; label + borders + 6-char box
          want (- (lzf:cellx (/ (+ (nth 2 d) (nth 4 d)) 2)) (/ w 2)))
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
(defun lzf:bandtiles (c / out bands b i h)
  (setq i 0
        bands (lzf:bands c))
  (foreach b bands
    (setq h (/ (* (- (cdr b) (car b)) lzf:*chart-h*) 1000.0))
    (if (< h 0.8) (setq h 0.8))
    (setq out (append out
                      (list (strcat "      : image { key = \"chart" (itoa i)
                                    "\"; width = " (itoa lzf:*chart-w*)
                                    "; height = " (rtos h 2 1)
                                    "; fixed_width = true; "
                                    "fixed_height = true; color = -15; }"))))
    (if (< (1+ i) (length bands))
        (setq out (append out (lzf:wedgerow c (cdr b)))))
    (setq i (1+ i)))
  out)

;; One dialog per chart.  They all live in one generated file so the
;; page loop can load_dialog once and switch pages without touching
;; the disk again.
(defun lzf:dcl-one (c / out d wk l)
  ;; out is consed newest-first and reversed once at the end, so this
  ;; seed list reads BACKWARDS: the label second here puts it second in
  ;; the file, after the line that opens the dialog.  The other way
  ;; round emits an attribute before its own dialog, which is not DCL.
  (setq out (list (strcat "  label = \"LazForm - " (caddr c) "\";")
                  (strcat (lzf:dlgname (car c)) " : dialog {")))
  (setq out (append (reverse (lzf:tabstrip (car c))) out))
  (setq out (cons "  : row {" out))
  ;; PASSIVE image tiles, deliberately -- see "why the picture is not
  ;; clickable" above -- stacked with the wedge rows between them.
  (setq wk (lzf:wedge-keys c))
  (setq out (cons "    : column {" out))
  (foreach l (lzf:bandtiles c)
    (setq out (cons l out)))
  (setq out (cons "    }" out))
  (setq out (cons "    : column {" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Dimensions\";" out))
  ;; Each dimension is a row: its LETTER as a button, then the box.
  ;; Clicking the letter puts the caret in that box and rings the
  ;; dimension on the chart -- which is as close to clicking the
  ;; drawing itself as DCL allows, and the button sits against the box
  ;; it fills rather than off in a separate list.
  ;; only the dims that could NOT be wedged into the drawing -- the
  ;; vertical ones -- keep a row here; the horizontal chains live on
  ;; the chart itself now
  (foreach d (lzf:dims c)
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
  (if (lzf:extra c)
    (progn
      (setq out (cons "      : boxed_column {" out))
      (setq out (cons "        label = \"Not on this view\";" out))
      (foreach d (lzf:extra c)
        (setq out (cons (strcat "        : edit_box { key = \"" (car d)
                                "\"; edit_width = 9; label = \"" (cadr d)
                                "\"; }")
                        out)))
      (setq out (cons "      }" out))))
  (if (lzf:corners c)
    (progn
      (setq out (cons "      : boxed_column {" out))
      (setq out (cons "        label = \"Corners\";" out))
      (foreach d (lzf:corners c)
        (setq out (cons "        : row {" out))
        (setq out (cons (strcat "          : popup_list { key = \"" (car d)
                                "\"; label = \"" (cadr d)
                                "\"; edit_width = 9; }")
                        out))
        (setq out (cons (strcat "          : edit_box { key = \"" (car d)
                                "-sz\"; label = \"size\"; "
                                "edit_width = 6; fixed_width = true; }")
                        out))
        (setq out (cons "        }" out)))
      (setq out (cons "      }" out))))
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
                          "label = \"The chain boxes sit on the drawing itself.  "
                          "Type NA where nothing was measured; leave a box "
                          "empty and POOL will ask.\"; }")
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

;; The DCL name of a chart's page.
(defun lzf:dlgname (key) (strcat "lazform_" (strcase key t)))

;; Every page, one after another, in one file.
(defun lzf:dcl-lines ( / out c)
  (foreach c lzf:*charts*
    (setq out (append out (lzf:dcl-one c) (list ""))))
  (append out (lzf:dcl-ascii) (list "")))

;;; -------------------- the character-drawing probe ----------------------
;;;  Could the chart be drawn in CHARACTERS instead of vectors, with the
;;;  edit boxes sitting in the drawing rather than beside it?
;;;
;;;  There is a real prize in it.  DCL does not RETAIN an image tile:
;;;  anything that repaints the dialog clears the picture, and there is
;;;  no expose callback to draw it again -- which is why the chart has
;;;  vanished on people twice.  A text tile is retained by the dialog
;;;  manager like any other control, so a chart drawn in characters
;;;  could not vanish at all.
;;;
;;;  It turns on one thing this file cannot answer for itself: whether
;;;  the DCL dialog font is FIXED-PITCH.  Character art needs every
;;;  glyph the same width; a proportional font makes "WWWW" far wider
;;;  than "iiii" and the drawing shears apart line by line.  DCL gives
;;;  no way to choose a font, and widths are quoted in "character
;;;  cells" that are an AVERAGE, not a guarantee.
;;;
;;;  So this asks AutoCAD instead of guessing.  Run LAZASCII and look:
;;;  section 1 says whether the font is fixed-pitch, section 2 shows
;;;  what a pool would look like if it is, and section 3 shows the
;;;  fallback that works either way -- a row of tiles, where alignment
;;;  comes from tile widths rather than from glyphs.
(defun lzf:dcl-ascii ( / out)
  (setq out (list
    "lazform_ascii : dialog {"
    "  label = \"LAZFORM  -  can this dialog draw in characters?\";"
    "  : boxed_column {"
    "    label = \"1.  Is the dialog font fixed-pitch?\";"
    "    : text { label = \"Twelve characters sit between the bars on every line.\"; }"
    "    : text { label = \"|iiiiiiiiiiii|  thin letters\"; }"
    "    : text { label = \"|WWWWWWWWWWWW|  wide letters\"; }"
    "    : text { label = \"|000000000000|  digits\"; }"
    "    : text { label = \"|------------|  dashes\"; }"
    "    : text { label = \"|            |  spaces\"; }"
    "    : text { label = \"FIXED-PITCH if the right-hand bars form one straight column.\"; }"
    "  }"
    "  : boxed_column {"
    "    label = \"2.  Do leading spaces survive?\";"
    "    : text { label = \"|column zero\"; }"
    "    : text { label = \"    |four spaces in\"; }"
    "    : text { label = \"        |eight spaces in\"; }"
    "    : text { label = \"A staircase means indenting works; three bars in one\"; }"
    "    : text { label = \"column means DCL trimmed the spaces and art is impossible.\"; }"
    "  }"
    "  : boxed_column {"
    "    label = \"3.  The pool, drawn in characters\";"
    "    : text { label = \"    +--------------------------+\"; }"
    "    : text { label = \"    |                          |\"; }"
    "    : text { label = \"    |      +------------+      |\"; }"
    "    : text { label = \"    |      |            |      |\"; }"
    "    : text { label = \"    |      +------------+      |\"; }"
    "    : text { label = \"    |                          |\"; }"
    "    : text { label = \"    +--------------------------+\"; }"
    "  }"
    "  : boxed_column {"
    "    label = \"4.  A box IN the dimension line -- works either way\";"
    "    : text { label = \"Alignment here comes from tile widths, not from glyphs,\"; }"
    "    : text { label = \"so this reads straight even in a proportional font.\"; }"
    "    : row {"
    "      : text { label = \"B\"; width = 3; }"
    "      : text { label = \"|<---\"; width = 7; }"
    "      : edit_box { key = \"probe_b\"; edit_width = 8; }"
    "      : text { label = \"--->|\"; width = 7; }"
    "    }"
    "    : row {"
    "      : text { label = \"A\"; width = 3; }"
    "      : text { label = \"|<---\"; width = 7; }"
    "      : edit_box { key = \"probe_a\"; edit_width = 8; }"
    "      : text { label = \"--->|\"; width = 7; }"
    "    }"
    "  }"
    "  spacer;"
    "  : text { label = \"Tell the session which sections lined up.\"; alignment = centered; }"
    (strcat "  : button { label = \"Close\"; key = \"cancel\"; "
            "is_default = true; is_cancel = true; "
            "fixed_width = true; alignment = centered; }")
    "}"))
  out)

;; The probe, on its own loaded handle.  It draws nothing and answers
;; nothing -- it exists to be looked at.
(defun c:LAZASCII ( / f dcl)
  (cond
    ((not (setq f (lzf:write-dcl)))
     (princ "\nLAZASCII error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZASCII error: could not load the dialog file."))
    (t
     (if (new_dialog "lazform_ascii" dcl)
       (progn
         (action_tile "cancel" "(done_dialog 0)")
         (start_dialog)))
     (unload_dialog dcl)
     (vl-file-delete f)
     (princ (strcat "\nLAZASCII: if sections 1-3 lined up, the chart can be"
                    " drawn in characters -- and a text tile, unlike an"
                    " image tile, is never wiped by a repaint."))))
  (princ))

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
;;; -------------------- what this bottom actually asks -------------------
;;;  A bottom type does not ask for every letter on the sheet, and the
;;;  form offered all of them anyway: type a C against a Normal hopper
;;;  and POOL never asks for it, so the number goes nowhere and nothing
;;;  says so.  These grey the boxes the chosen bottom will not reach.
;;;
;;;  The truth comes from POOL'S OWN pool:btmspec rather than a copy of
;;;  it here -- (ask-G ask-E has-profile ask-C2 slack) -- so the two
;;;  cannot drift.  LAZFORM already refuses to open without POOL loaded,
;;;  so it is always there to ask.
;;;
;;;  SPORT IS THE EXCEPTION, and not a small one.  btmspec's has-profile
;;;  flag reads nil for Sport, which would say "no C or D" -- but that
;;;  flag is only ever consulted inside pool:hopnormal, and a Sport
;;;  never goes near it.  Sport has its own path, which DOES ask C and
;;;  D, and which asks a different plan chain entirely: E2 F2 G F1 E1 M
;;;  K, not H G F E.  So on a Sport the chart's H, F and E boxes are
;;;  greyed: they are not what POOL will ask for, and a number typed
;;;  into one would be read by nothing.
(defun lzf:btskip (bt / sp out)
  (cond
    ((= bt "Sport") (list "h" "f" "e" "c2"))
    ((not pool:btmspec) nil)          ; no POOL: grey nothing, ask everything
    (t
     (setq sp (pool:btmspec bt))
     (if (not (car sp))    (setq out (cons "g" out)))
     (if (not (cadr sp))   (setq out (cons "e" out)))
     (if (not (caddr sp))  (setq out (append (list "c" "d") out)))
     (if (not (cadddr sp)) (setq out (cons "c2" out)))
     out)))

;; Grey every box this bottom will not ask about, un-grey the rest.
;; Only keys the CURRENT chart carries are touched -- mode_tile on a key
;; that is not on this page would error.
(defun lzf:btgrey (c / skip k)
  (setq skip (lzf:btskip (nth lzf:*btype* lzf:*btypes*)))
  (foreach k (lzf:keys c)
    (mode_tile k (if (member k skip) 1 0))))

(defun lzf:form (shape insq btype / out k v a noask)
  (setq out (list (cons 'shape shape)
                  (cons 'insq (if insq "Insquare" "Outofsquare"))))
  (if (and btype (/= btype "")) (setq out (cons (cons 'btype btype) out)))
  ;; a key this bottom never asks about does not travel: it would sit in
  ;; the store unread, and a form that quietly carries dead answers is
  ;; harder to reason about than one that does not
  (setq noask (lzf:btskip btype))
  (foreach k (lzf:keys lzf:*chart*)
    (setq v (lzf:get k)
          a (lzf:answer v))
    (if (and (not (eq a 'SKIP)) (not (member k noask)))
        (setq out (cons (cons (read k) a) out))))
  ;; the corners: a dropdown left on (ask) sends nothing, a sized
  ;; treatment carries its size when one parses.  In-square asks ONE
  ;; question for all four rectangle corners, under its own key, so
  ;; corner A's row speaks for all four there and B-D are ignored.
  (foreach k (lzf:cornerpairs insq)
    (setq out (cons k out)))
  ;; the gates last, so a chart cannot be talked out of the path its
  ;; own letters live on
  (foreach k (lzf:gates lzf:*chart*)
    (setq out (cons (cons (read (car k)) (cdr k)) out)))
  (reverse out))

;; The (key . value) pairs the corner rows contribute.
(defun lzf:cornerpairs (insq / out d stem use i ty a)
  (foreach d (lzf:corners lzf:*chart*)
    (setq stem (car d)
          use stem)
    (if (and insq (= (car lzf:*chart*) "Rectangle"))
        (setq use (if (= stem "cornera") "corners" nil)))
    (if (and use (> (setq i (lzf:cget stem)) 0))
        (progn
          (setq ty (nth i lzf:*ctreat*))
          (setq out (cons (cons (read (strcat use "-ty")) ty) out))
          (if (lzf:csized i)
              (progn
                (setq a (lzf:answer (lzf:get (strcat stem "-sz"))))
                (if (numberp a)
                    (setq out (cons (cons (read (strcat use "-sz")) a)
                                    out))))))))
  (reverse out))

;;; -------------------- the run -----------------------------------------
;;  A helper rather than the command body, so its localized *error* is
;;  out of scope by the time POOL is started: POOL installs its own, and
;;  a POOL that fails must report as POOL.

(defun lzf:show (chartkey / *error* f dcl rc c d n go done out)
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
  (setq lzf:*vals* nil
        lzf:*cvals* nil                 ; corner dropdowns back to (ask)
        lzf:*insq* nil                  ; the toggle's own starting state
        lzf:*btype* 0                   ; Normal, first in the list
        lzf:*pos* nil                   ; where the user last had it
        go chartkey)
  (cond
    ((not (lzf:chart go))
     (princ (strcat "\nLAZFORM: no chart called " go ".")))
    ((not (setq f (lzf:write-dcl)))
     (princ "\nLAZFORM error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZFORM error: could not load the dialog file."))
    (t
     ;; The page loop.  DCL has no tab tile, so a tab is a button that
     ;; closes this page and reopens the next -- and because
     ;; done_dialog hands back where the dialog was standing, it
     ;; reopens exactly there instead of wandering off to the middle of
     ;; the screen.  Everything typed lives in lzf:*vals*, keyed, so it
     ;; survives the switch and is still there if you tab back.
     (while (not done)
       (setq lzf:*chart* (lzf:chart go)
             c lzf:*chart*
             lzf:*focus* nil)
       (cond
         ((not (lzf:newdlg (lzf:dlgname go) dcl))
          (princ "\nLAZFORM error: could not open the form.")
          (setq done t))
         (t
          (start_list "btype")
          (foreach d lzf:*btypes* (add_list d))
          (end_list)
          (set_tile "btype" (itoa lzf:*btype*))
          ;; the corner dropdowns: filled, put back to their remembered
          ;; pick, size boxes greyed unless that pick takes a size --
          ;; and each harvests into its own store the moment it changes
          (foreach d (lzf:corners c)
            (start_list (car d))
            (foreach n lzf:*ctreat* (add_list n))
            (end_list)
            (set_tile (car d) (itoa (lzf:cget (car d))))
            (set_tile (strcat (car d) "-sz")
                      (lzf:get (strcat (car d) "-sz")))
            (mode_tile (strcat (car d) "-sz")
                       (if (lzf:csized (lzf:cget (car d))) 0 1))
            (action_tile (car d)
              (strcat "(lzf:cornerpick \"" (car d) "\" $value)"))
            (action_tile (strcat (car d) "-sz")
              (strcat "(lzf:put \"" (car d) "-sz\" $value)")))
          (if lzf:*insq* (set_tile "insq" "1"))
          ;; put back what was typed before this page was opened
          (foreach d (lzf:keys c) (set_tile d (lzf:get d)))
          (foreach d (lzf:keys c)
            (action_tile d
              (strcat "(lzf:put \"" d "\" $value) (setq lzf:*focus* \"" d "\")"
                      " (lzf:redraw)")))
          ;; clicking a dimension's letter: caret into its box, with
          ;; the box's contents selected so the first keystroke
          ;; replaces rather than appends, and the dimension ringed on
          ;; the chart
          ;; wedge dims have no pick button -- their box already sits
          ;; on the drawing where the letter was
          (foreach d (lzf:dims c)
            (if (not (member (cadr d) (lzf:wedge-keys c)))
                (action_tile (strcat "pick_" (cadr d))
                  (strcat "(setq lzf:*focus* \"" (cadr d) "\") (lzf:redraw)"
                          " (mode_tile \"" (cadr d) "\" 2)"
                          " (mode_tile \"" (cadr d) "\" 3)"))))
          ;; the tabs -- each closes this page and names the next
          (foreach d lzf:*charts*
            (action_tile (strcat "tab_" (car d))
              (strcat "(setq lzf:*go* \"" (car d)
                      "\" lzf:*pos* (done_dialog 4))")))
          ;; the chart takes no action -- it is a passive image tile.
          ;; These two capture their value as it changes: get_tile
          ;; answers about a LIVE dialog, and by the time the answers
          ;; are assembled this one is closed and unloaded.
          (action_tile "btype"
            (strcat "(setq lzf:*btype* (atoi $value)) (lzf:redraw)"
                    " (lzf:btgrey lzf:*chart*)"))
          (action_tile "insq" "(setq lzf:*insq* (= $value \"1\")) (lzf:redraw)")
          (action_tile "accept" "(setq lzf:*pos* (done_dialog 1))")
          (action_tile "cancel" "(setq lzf:*pos* (done_dialog 0))")
          (lzf:redraw)
          (lzf:btgrey c)
          (setq rc (start_dialog))
          (cond
            ((= rc 4) (setq go lzf:*go*))     ; a tab: go round again
            (t (setq done t
                     out (if (= rc 1)
                             (lzf:form (cadr c) lzf:*insq*
                                       (nth lzf:*btype* lzf:*btypes*)))))))))))
  (if (and dcl (>= dcl 0)) (unload_dialog dcl))
  (setq dcl nil)
  (if f (vl-file-delete f))
  (setq f nil)
  out)

;; Open a page where the user last had the dialog.  done_dialog reports
;; the position it was closed at and new_dialog takes one back, but only
;; as a 4-argument call -- and a build that answered done_dialog with
;; something other than a point would poison every reopen, so the shape
;; is checked before it is trusted and the plain 2-argument call is the
;; fallback.
(defun lzf:newdlg (name dcl)
  (if (and lzf:*pos* (listp lzf:*pos*) (= (length lzf:*pos*) 2)
           (numberp (car lzf:*pos*)) (numberp (cadr lzf:*pos*)))
      (new_dialog name dcl "" lzf:*pos*)
      (new_dialog name dcl)))

;;; -------------------- commands ----------------------------------------

;; The form, then POOL with what it collected.  COVER closes POOL's
;; pool-bottom gate first: a cover sheet has no floor work on it, so
;; the depth chain behind that gate is neither asked for nor drawn.
;; The flag goes on at the last moment -- after the form comes back --
;; so a cancelled form leaves the session exactly as it found it, and
;; c:POOL clears it again on the way out either way.
(defun lzf:run (cover / form)
  (cond
    ;; the chart fills POOL's answers in, so POOL has to be here to
    ;; receive them -- say so plainly rather than opening a form whose
    ;; Insert button could only fail
    ((not pool:run-with-answers)
     (princ "\nLAZFORM: POOL is not loaded in this session -- APPLOAD")
     (princ "\n         lisp/pool/POOL.LSP, or LAZPASS.lsp which has both."))
    ((setq form (lzf:show (car (car lzf:*charts*))))
     (princ (strcat "\nLAZFORM: " (itoa (length form))
                    " answers to POOL; it will ask for whatever is left."))
     (if cover
       (progn
         (setq pool:*nobottom* t)
         (princ "\n         Cover sheet - no pool bottom will be asked for.")))
     (pool:run-with-answers form))
    (t (princ "\nLAZFORM: cancelled, nothing drawn.")))
  (princ))

(defun c:LAZFORM () (lzf:run nil))

(defun c:LAZFORMCOVER () (lzf:run t))

(defun c:LAZFORMVER ()
  (princ (strcat "\nLAZFORM " *lazform-version* " (LAZFORM.lsp) - "
                 (itoa (length lzf:*charts*)) " chart(s)."))
  (princ))

(princ (strcat "\nLAZFORM " *lazform-version*
               " loaded.  Type LAZFORM to fill a chart in and draw it."))
(princ)
