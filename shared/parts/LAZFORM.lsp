;;; ======================================================================
;;; LAZFORM.lsp  --  fill a dimension chart in, then draw the pool
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZFORM        fill in a shape chart and draw the pool
;;;            LAZFORMCOVER   the same, for a cover sheet
;;;            LAZASCII       probe: could the chart be drawn in text?
;;;            LAZTXT         the same form, drawn out of tiles
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
;;; Insert: the routine runs and asks only for the gaps.
;;;
;;; TWO ROUTINES ARE FED FROM HERE.  The eight POOL sheets -- Rectangle,
;;; True Oval, Roman, both Grecians, True L Left, Round and Octagon --
;;; hand their answers to POOL; the five OASIS sheets -- Center,
;;; TopRight, Cloud, Kidney and NXT cloud -- hand theirs to OASIS.  The
;;; page decides which, so a tab is all there is to it.
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
;;; nothing else.  Hence the chart is drawn rather than loaded and the
;;; numbers appear ON it as they are typed, which recovers most of what
;;; a text box sitting on the artwork would have given, without a DLL
;;; to install.  (An earlier version also let you click the picture to
;;; jump to a box; DCL took that back -- see "why the picture is not
;;; clickable".)
;;;
;;; ONE PICTURE, AND EVERY BOX IN THE COLUMN BESIDE IT.  v1.6 to v2.5
;;; sliced the chart into horizontal bands and wedged the across-chains
;;; between them, so B was typed on the B line.  It cost more than it
;;; bought: the picture came apart into strips, the wedged boxes were
;;; placed by spacer arithmetic that could only ever be approximate,
;;; and a sheet read as two different kinds of thing at once -- some
;;; letters answered on the drawing, the rest in a list.  So the boxes
;;; are all back in the column, each labelled with its letter and each
;;; with that letter as a button beside it, and the chart is one whole
;;; passive image again.
;;;
;;; ADDING A SHAPE is adding data, not code -- one entry in
;;; lzf:*charts* with an outline, a dimension list and its answer keys,
;;; plus a row in whichever of lzf:*cross*, lzf:*picks*, lzf:*corners*
;;; and lzf:*oaslive* the sheet needs.  Thirteen charts so far, eight
;;; POOL and five OASIS.  Watch the keys rather than the letters when
;;; you add one: the same letter means different things on different
;;; sheets -- a rectangle's B is the side length, an oval's B is the
;;; tip-to-tip total and its SIDE is T -- so the mapping is per chart
;;; and is checked against the routines' own question lists by
;;; tests/test_lazform.py.
;;;
;;; WHAT IS LIVE ON A PAGE IS ONE FUNCTION'S DECISION.  lzf:dead reads
;;; the whole state of the page -- the bottom type, the in-square
;;; toggle and the mode dropdowns -- and names every key POOL will not
;;; ask about.  lzf:btgrey greys exactly that set and lzf:form drops
;;; exactly that set, so what is greyed and what is sent cannot say
;;; different things.
;;; ======================================================================

(vl-load-com)

(setq *lazform-version* "v2.7")

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
;;;
;;;  THE SPORT CHAIN (E2 F2 G F1 E1) is column-only on every sheet
;;;  that carries it.  A sport bottom asks a different plan chain from
;;;  the one these charts are drawn with -- E2 F2 G F1 E1 M L K, not
;;;  H G F E M L K -- and only G, M, L and K are shared, so its own
;;;  letters have nowhere to sit on a drawing of a hopper.  They are
;;;  listed here with POOL's own prompts, and lzf:dead greys them
;;;  unless the bottom type actually is Sport.

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
    ("c2" "C2 - shallow floor at the break")
    ("e2" "E2 - left end shallow flat")
    ("f2" "F2 - left slope")
    ("f1" "F1 - right slope")
    ("e1" "E1 - right end shallow flat")))

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
    ("c2" "C2 - shallow floor at the break")
    ;; the Normal bottom re-asks the side as a CHECK, under a key of
    ;; its own (pool:hopoval), so it is a second box and not the T on
    ;; the drawing
    ("tt" "T - straight side length (check)")
    ("e2" "E2 - left end shallow flat")
    ("f2" "F2 - left slope")
    ("f1" "F1 - right slope")
    ("e1" "E1 - right end shallow flat")))

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
    ("c2" "C2 - shallow floor at the break")
    ("e2" "E2 - left end shallow flat")
    ("f2" "F2 - left slope")
    ("f1" "F1 - right slope")
    ("e1" "E1 - right end shallow flat")))

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
    ("s2" "S2 - corner cut face (check, sets NA S/S1)")
    ("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break")
    ("e2" "E2 - left end shallow flat")
    ("f2" "F2 - left slope")
    ("f1" "F1 - right slope")
    ("e1" "E1 - right end shallow flat"))
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
   (("s2" "S2 - corner cut face (check, sets NA S/S1)")
    ("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break")
    ("e2" "E2 - left end shallow flat")
    ("f2" "F2 - left slope")
    ("f1" "F1 - right slope")
    ("e1" "E1 - right end shallow flat"))
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
    ("c2" "C2 - shallow floor at the break")
    ;; the round pool hands its bottom to the oval's routine, which
    ;; re-asks the straight side as a check even on a circle
    ("tt" "T - straight side length (check)")
    ("e2" "E2 - left end shallow flat")
    ("f2" "F2 - left slope")
    ("f1" "F1 - right slope")
    ("e1" "E1 - right end shallow flat")))

  ;; ---------------- Octagon ----------------
  ;;  POOL reaches the octagon through the SAME flow as the grecian --
  ;;  (pool:grecflow t) -- so the letters are the grecian square-hopper
  ;;  set exactly: B S T on the top, A S1 V down the end, H G F E across
  ;;  the middle, M L K at the hopper, and S2 for the far corner cut.
  ;;  The sheet bears that out.  The geometry is GRSquare's, deliberately
  ;;  and to the coordinate: that outline already IS an eight-sided pool
  ;;  with a cut at every corner, and its numbers are the ones the
  ;;  box-position audit has been passing all along.
  ;;
  ;;  S2 IS A COLUMN BOX, like GRSquare's.  It measures the far corner's
  ;;  cut FACE, which runs diagonally; a dim on this chart is "h" or "v"
  ;;  and nothing else, so a diagonal has no place to be drawn and is
  ;;  answered in the list.
  ;;
  ;;  The gates pin what the drawing assumes, the way both grecians do:
  ;;  Overall input (which is what an octagon defaults to anyway, since
  ;;  A and B are enough), and the square hopper this chart draws.  An
  ;;  octagon with a SIX-sided hopper asks for W and L1 as well and
  ;;  wants a sheet of its own; we do not have one.
  ("OCtagon" "OCtagon" "Octagon"
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
   (("s2" "S2 - corner cut face (check, sets NA S/S1)")
    ("c"  "C - wall height (shallow depth)")
    ("d"  "D - deep end depth")
    ("c2" "C2 - shallow floor at the break")
    ("e2" "E2 - left end shallow flat")
    ("f2" "F2 - left slope")
    ("f1" "F1 - right slope")
    ("e1" "E1 - right end shallow flat"))
   (("imeth" . "Overall") ("htype" . "Square")))

  ;;; ============== the OASIS sheets ==============
  ;;  An oasis pool is arcs and nothing else, so there is no chain to
  ;;  draw and no hopper: the whole sheet is the ENVELOPE, X across and
  ;;  Y up, and a radius against every arc.  Which is exactly what
  ;;  OASIS asks for, in the order it asks -- the shape first (the tab
  ;;  is that answer), then the box, then the bulges, then the joiners
  ;;  between them.
  ;;
  ;;  THE OUTLINES ARE NOT DRAWN BY HAND.  Each is the ring
  ;;  oasis:solve builds for that shape's own reference drawing --
  ;;  scaled into the picture and flipped for the y-down convention,
  ;;  and nothing else.  So the chart is the pool OASIS draws rather
  ;;  than an artist's impression of it, and tests/test_lazform.py
  ;;  re-derives every arc from OASIS and compares, which is why the
  ;;  reference dimensions are written down in lzf:*oasart* rather
  ;;  than lost in a comment.  Arc angles carry a decimal here (the
  ;;  coordinates are still integers): rounded to whole degrees a
  ;;  200-unit arc misses its neighbour by enough to show as a kink.
  ;;
  ;;  A BULGE'S RADIUS IS DRAWN WHERE IT RUNS.  Every bulge is pinned
  ;;  to the envelope, so the line from its centre to the bound it
  ;;  touches is the radius itself and is square to the page -- L, T
  ;;  and R below are real "h" and "v" dimensions.  A JOINER's centre
  ;;  is off the pool and its radius runs at whatever angle the
  ;;  tangency puts it, so those are "p": a LEADER out to the letter,
  ;;  drawn from the point on the outline it names.

  ;; ---------------- Center ----------------
  ;;  Three bulges -- left, right and one across the top, centred --
  ;;  joined by three reverse arcs.  The one shape whose hump can be
  ;;  moved off centre, which is why OFF is in the column here and on
  ;;  no other sheet: it is a Complex-only question, greyed until the
  ;;  detail dropdown says so.
  ("OACenter" "Center" "Oasis - Center Bulge"
   (("A" 260 658 160 222 85.9 329.7)
    ("A" 484 840 100 139 32.7 149.7)
    ("A" 720 630 180 250 212.7 465.2)
    ("A" 657 308 60 83 235.8 285.2)
    ("A" 500 630 220 306 55.8 130.3)
    ("A" 280 270 120 167 265.9 310.3))
   (("X"  "x"  100 204 900 204 "h" "X - overall left-to-right bounds")
    ("Y"  "y"   45 324  45 880 "v" "Y - overall front-to-back bounds")
    ("L"  "rl" 100 658 260 658 "h" "L - left bulge radius")
    ("T"  "rt" 500 630 500 324 "v" "T - top bulge radius")
    ("R"  "rr" 720 630 900 630 "h" "R - right bulge radius")
    ("TL" "ftl" 317 428 256 380 "p" "TL - top-left tangent radius")
    ("TR" "ftr" 647 390 696 333 "p" "TR - top-right tangent radius")
    ("BC" "fbc" 482 701 467 770 "p" "BC - bottom-center tangent radius"))
   (("off" "Top bulge off center, left negative (complex only)")))

  ;; ---------------- Top Right ----------------
  ;;  The same three bulges, with the third tucked into the top-right
  ;;  corner instead of sitting across the top -- so it is tangent to
  ;;  the Y-max AND the X-max bound, and the joiner that was the
  ;;  top-right tangent is now the right-SIDE one, running down the far
  ;;  wall between the corner bulge and the right bulge.
  ("OATopRight" "TopRight" "Oasis - Top-Right Bulge"
   (("A" 348 679 145 201 74.2 299.9)
    ("A" 500 1047 161 223 60.1 119.9)
    ("A" 652 679 145 201 240.1 380.4)
    ("A" 908 547 129 179 159.0 200.4)
    ("A" 668 419 129 179 339.0 522.9)
    ("A" 422 314 129 179 254.2 342.9))
   (("X"  "x"  203 120 797 120 "h" "X - overall left-to-right bounds")
    ("Y"  "y"  148 240 148 880 "v" "Y - overall front-to-back bounds")
    ("L"  "rl" 203 679 348 679 "h" "L - left bulge radius")
    ("T"  "rt" 668 419 668 240 "v" "T - top-right bulge radius")
    ("R"  "rr" 652 679 797 679 "h" "R - right bulge radius")
    ("TL" "ftl" 484 471 469 402 "p" "TL - top-left tangent radius")
    ("RS" "ftr" 780 546 864 542 "p" "RS - right-side tangent radius")
    ("BC" "fbc" 500 824 500 894 "p" "BC - bottom-center tangent radius"))
   ())

  ;; ---------------- Cloud ----------------
  ;;  Two bulges, joined over the top by a reverse arc.  The LEFT one
  ;;  is tangent to three bounds at once -- X-min, Y-min and Y-max --
  ;;  which pins its radius at half of Y and takes it out of the
  ;;  questions altogether, so this sheet has no L box at all.  The
  ;;  bottom comes two ways, and the dropdown is that question: a
  ;;  Straight bottom is the flat run of the Y-min bound between the
  ;;  two bulges and has no radius, so B only comes alive on Rounded.
  ;;  The picture is the rounded one, which is the one with something
  ;;  to show.
  ("OACloud" "Cloud" "Oasis - Cloud"
   (("A" 385 560 230 320 38.6 287.9)
    ("A" 540 1230 276 384 70.8 107.9)
    ("A" 684 656 161 224 250.8 452.2)
    ("A" 673 240 138 192 218.6 272.2))
   (("X" "x"  154 120 846 120 "h" "X - overall left-to-right bounds")
    ("Y" "y"   99 240  99 880 "v" "Y - overall front-to-back bounds")
    ("R" "rr" 684 656 846 656 "h" "R - right bulge radius")
    ("T" "ftl" 615 415 668 360 "p" "T - top tangent radius")
    ("B" "fbc" 543 846 556 915 "p" "B - bottom radius (rounded only)"))
   ())

  ;; ---------------- Kidney ----------------
  ;;  Three bulges and ONE reverse arc: the two side circles sit INSIDE
  ;;  the big top circle, touching it from within, and the outline
  ;;  hands straight over at each touch.  Which of the three is given
  ;;  and which is derived is the dropdown: a TRUE kidney gives the
  ;;  top-center radius and derives two equal sides, an ASYMMETRIC one
  ;;  gives two unequal sides and derives the top.  So TC and the L/R
  ;;  pair are never live together, and until the dropdown is answered
  ;;  neither is.  The picture is a true kidney.
  ;;
  ;;  TC is a LEADER and not a "v" dimension like the other top
  ;;  bulges: a kidney's top circle is far bigger than the envelope and
  ;;  its centre is a long way below the bottom of it, so the radius
  ;;  line would run right off the sheet.
  ("OAKidney" "Kidney" "Oasis - Kidney"
   (("A" 298 605 198 275 115.5 313.0)
    ("A" 500 907  99 137  47.0 133.0)
    ("A" 702 605 198 275 227.0 424.5)
    ("A" 500 1195 668 928 64.5 115.5))
   (("X"  "x"  100 147 900 147 "h" "X - overall left-to-right bounds")
    ("Y"  "y"   45 267  45 880 "v" "Y - overall front-to-back bounds")
    ("L"  "rl" 100 605 298 605 "h" "L - left bulge radius (asymmetric)")
    ("R"  "rr" 702 605 900 605 "h" "R - right bulge radius (asymmetric)")
    ("TC" "rt" 500 267 500 197 "p" "TC - top-center radius (true kidney)")
    ("BC" "fbc" 500 769 500 839 "p" "BC - bottom-center tangent radius"))
   ())

  ;; ---------------- NXT cloud ----------------
  ;;  Three lobes and FOUR fillets, and the one ring that meets a bulge
  ;;  twice: the outline runs under the centre lobe on its way out to
  ;;  the right one and back over it on the way home, so that lobe
  ;;  gives the drawing two disjoint arcs of one circle.  Eight
  ;;  elements from seven circles, and all three lobes are pinned by
  ;;  the envelope alone -- nothing to ask but the radii.
  ("OANXT" "NXTcloud" "Oasis - NXT Cloud"
   (("A" 260 547 160 222  42.5 280.7)
    ("A" 308 902 100 139  42.5 100.7)
    ("A" 500 658 160 222 222.5 307.4)
    ("A" 658 945 100 139  71.6 127.4)
    ("A" 740 602 160 222 251.6 487.4)
    ("A" 582 315 100 139 251.6 307.4)
    ("A" 500 658 160 222  71.6 100.7)
    ("A" 452 303 100 139 222.5 280.7))
   (("X"  "x"  100 204 900 204 "h" "X - overall left-to-right bounds")
    ("Y"  "y"   45 324  45 880 "v" "Y - overall front-to-back bounds")
    ("TL" "rl" 100 547 260 547 "h" "TL - top-left lobe radius")
    ("CE" "rt" 500 880 500 658 "v" "CE - center lobe radius")
    ("RI" "rr" 740 602 900 602 "h" "RI - right lobe radius")
    ("LB" "fbc" 340 770 281 820 "p" "LB - left-bottom tangent radius")
    ("RB" "fbr" 641 808 689 865 "p" "RB - right-bottom tangent radius")
    ("RT" "ftr" 599 452 645 394 "p" "RT - right-top tangent radius")
    ("LT" "ftl" 420 435 384 371 "p" "LT - left-top tangent radius"))
   ())
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

;;; -------------------- cross dims and the mode dropdowns ----------------
;;;  A cross dim is a tape run corner to corner, and it is the one
;;;  measurement that has no place at all on a chart drawn square: it
;;;  runs diagonally, and a dim here is "h" or "v" and nothing else.
;;;  So every one of them is a column box.
;;;
;;;  HOW MANY OF THEM POOL ASKS FOR DEPENDS ON A QUESTION OF ITS OWN,
;;;  and that question is a dropdown here:
;;;
;;;    Rectangle / Oval   cmode   Corner | Middle | Ends
;;;                       Corner and Middle tape two diagonals, Ends
;;;                       tapes four (pool:crosstemplate).
;;;    the Grecians       gcross  Simple | Center | Complex
;;;                       Simple tapes the two body diagonals; Center
;;;                       and Complex tape 14 and 18, far more than a
;;;                       sheet has boxes for, so the dropdown answers
;;;                       the gate and the dims are typed at the
;;;                       command line (pool:grecmode).
;;;
;;;  Left on "(ask)" the boxes are all dead and none of them travels:
;;;  which box is which diagonal is undefined until the mode is, so a
;;;  number typed into one would be attached to the wrong tape.
;;;
;;;  The L's nine diagonals need no such question -- POOL asks for the
;;;  same nine every time -- so that chart carries the boxes and no
;;;  mode dropdown.  Its "mirror" dropdown is a different sort of
;;;  thing: a plain keyword question with a home on this page, which is
;;;  why a pick declares the section it belongs to.

(setq lzf:*cross*
  '(("Rectangle" ("x0" "Cross dim 1") ("x1" "Cross dim 2")
                 ("x2" "Cross dim 3") ("x3" "Cross dim 4"))
    ("Oval"      ("x0" "Cross dim 1") ("x1" "Cross dim 2")
                 ("x2" "Cross dim 3") ("x3" "Cross dim 4"))
    ("ROman"     ("ac" "Cross dim body A-C") ("bd" "Cross dim body B-D"))
    ("Grecian"   ("x0" "Cross dim 1") ("x1" "Cross dim 2"))
    ("GRSquare"  ("x0" "Cross dim 1") ("x1" "Cross dim 2"))
    ("OCtagon"   ("x0" "Cross dim 1") ("x1" "Cross dim 2"))
    ("L"         ("ac" "Cross dim A-C") ("bd" "Cross dim B-D")
                 ("ce" "Cross dim C-E") ("df" "Cross dim D-F")
                 ("ae" "Cross dim A-E") ("bf" "Cross dim B-F")
                 ("ad" "Cross dim A-D") ("be" "Cross dim B-E")
                 ("cf" "Cross dim C-F"))))

(defun lzf:cross (c) (cdr (assoc (car c) lzf:*cross*)))

;; The keyword dropdowns a page carries beyond the bottom type:
;;   (key label section (choice ...))
;; section "cross" puts the dropdown at the head of the cross-dim box
;; and ties its life to them -- in square there are no cross dims, so
;; there is no mode to pick either; section "run" is a question in its
;; own right and sits with the toggle and the bottom type.
(setq lzf:*picks*
  '(("Rectangle" ("cmode" "Cross dims measured from" "cross"
                  ("(ask)" "Corner" "Middle" "Ends")))
    ("Oval"      ("cmode" "Cross dims measured from" "cross"
                  ("(ask)" "Corner" "Middle" "Ends")))
    ("Grecian"   ("gcross" "Cross-dim detail" "cross"
                  ("(ask)" "Simple" "Center" "Complex")))
    ("GRSquare"  ("gcross" "Cross-dim detail" "cross"
                  ("(ask)" "Simple" "Center" "Complex")))
    ("OCtagon"   ("gcross" "Cross-dim detail" "cross"
                  ("(ask)" "Simple" "Center" "Complex")))
    ("L"         ("mirror" "Mirror the pool (wing swaps sides)" "run"
                  ("(ask)" "Yes" "No")))
    ;; the OASIS pages.  "sub" is the second question the two families
    ;; that come two ways are asked straight after the shape, and it
    ;; decides which radii this sheet is even asked for; "detail" is
    ;; simple-or-complex, which every oasis run is asked.
    ("OACenter"   ("detail" "Simple or complex" "run"
                   ("(ask)" "Simple" "Complex")))
    ("OATopRight" ("detail" "Simple or complex" "run"
                   ("(ask)" "Simple" "Complex")))
    ("OACloud"    ("sub" "Cloud bottom" "run"
                   ("(ask)" "Straight" "Rounded"))
                  ("detail" "Simple or complex" "run"
                   ("(ask)" "Simple" "Complex")))
    ("OAKidney"   ("sub" "Kidney type" "run"
                   ("(ask)" "True" "Asymmetric"))
                  ("detail" "Simple or complex" "run"
                   ("(ask)" "Simple" "Complex")))
    ("OANXT"      ("detail" "Simple or complex" "run"
                   ("(ask)" "Simple" "Complex")))))

(defun lzf:picks (c) (cdr (assoc (car c) lzf:*picks*)))

;;; -------------------- the OASIS sheets ---------------------------------
;;;  A page feeds one routine or the other, and which is a property of
;;;  the chart rather than of anything the user does: the tab IS the
;;;  choice.  lzf:*oaslive* names the OASIS pages and, for each, the
;;;  keys that page really asks for -- which is how the greying and the
;;;  sending stay one decision on these sheets as on the POOL ones.
;;;
;;;      (chart  always-live  ((sub-answer also-live ...) ...))
;;;
;;;  The second list is read against the "sub" dropdown -- a cloud's
;;;  bottom, a kidney's type -- and NOTHING in it is live until that
;;;  dropdown is answered.  That is not caution, it is the form
;;;  contract: a straight-bottomed cloud is never asked for a bottom
;;;  radius and an asymmetric kidney is never asked for a top-center
;;;  one, so a number typed into either before the question is settled
;;;  would be read by nothing.
;;;
;;;  OFF -- how far a hump is off centre -- is the one key outside that
;;;  table, because it hangs off the OTHER dropdown: OASIS asks it on a
;;;  Center pool and only on a Complex run.

;;  What each oasis picture was drawn from: the arguments oasis:solve
;;  was handed, and the box the answer was scaled into.
;;
;;      (chart variant w h rl rt rr ftl ftr fbc fbr
;;             x-left x-right y-top y-bottom)
;;
;;  A nil is a radius that shape does not take -- a cloud's left bulge
;;  is pinned by three bounds, a true kidney's sides are derived.  The
;;  scale is uniform in world terms and then stretched by 1/0.72 up the
;;  page, which is the image tile's own aspect: per-mille y is squashed
;;  by exactly that on the way to pixels, so pre-dividing it here is
;;  what makes the picture come out true rather than flat.
;;
;;  This is not documentation.  tests/test_lazform.py runs oasis:solve
;;  on these numbers and checks every arc of every chart against what
;;  comes back, so the artwork cannot drift from the routine it draws
;;  for -- and a shape OASIS changes shows up as a failing chart rather
;;  than as a picture that quietly stopped being true.
(setq lzf:*oasart*
  '(("OACenter"   "Center"        480.0 240.0 96.0 132.0 108.0
                                  72.0 36.0 60.0 nil     100 900 324 880)
    ("OATopRight" "TopRight"      443.0 344.0 108.0 96.0 108.0
                                  96.0 96.0 120.0 nil    203 797 240 880)
    ("OACloud"    "RoundedBottom" 360.0 240.0 nil nil 84.0
                                  72.0 nil 144.0 nil     154 846 240 880)
    ("OAKidney"   "TrueKidney"    388.0 214.0 nil 324.0 nil
                                  nil nil 48.0 nil       100 900 267 880)
    ("OANXT"      "NXTcloud"      480.0 240.0 96.0 96.0 96.0
                                  60.0 60.0 60.0 60.0    100 900 324 880)))

(setq lzf:*oaslive*
  '(("OACenter"   ("x" "y" "rl" "rt" "rr" "ftl" "ftr" "fbc") ())
    ("OATopRight" ("x" "y" "rl" "rt" "rr" "ftl" "ftr" "fbc") ())
    ("OACloud"    ("x" "y" "rr" "ftl")
                  (("Rounded" "fbc")))
    ("OAKidney"   ("x" "y" "fbc")
                  (("True" "rt") ("Asymmetric" "rl" "rr")))
    ("OANXT"      ("x" "y" "rl" "rt" "rr" "ftl" "ftr" "fbc" "fbr") ())))

;; T when this page hands its answers to OASIS rather than to POOL.
(defun lzf:oasis-p (c) (if (assoc (car c) lzf:*oaslive*) t nil))

;; Every key this OASIS page will actually be asked for, in the state
;; its two dropdowns are in.
(defun lzf:oaslive (c / r out sub)
  (setq r   (cdr (assoc (car c) lzf:*oaslive*))
        out (car r)
        sub (lzf:pickval c "sub"))
  (if (assoc sub (cadr r))
      (setq out (append out (cdr (assoc sub (cadr r))))))
  ;; a hump off centre is a Center pool's question and a complex run's
  (if (and (= (cadr c) "Center") (= (lzf:pickval c "detail") "Complex"))
      (setq out (cons "off" out)))
  out)

;; How many of a chart's cross boxes each mode leaves live.  A mode
;; this table does not name -- "(ask)" above all -- leaves none.
(setq lzf:*crosslive* '(("Corner" 2) ("Middle" 2) ("Ends" 4) ("Simple" 2)))

;; The dropdown that decides how many cross boxes are live, or nil.
(defun lzf:crossmode (c / d out)
  (foreach d (lzf:picks c)
    (if (and (not out) (= (caddr d) "cross")) (setq out (car d))))
  out)

;; the dropdown selections, by key: (("cmode" . 3) ...)
(setq lzf:*pvals* nil)

(defun lzf:pget (key / p)
  (if (setq p (assoc key lzf:*pvals*)) (cdr p) 0))

(defun lzf:pput (key i / out p)
  (foreach p lzf:*pvals* (if (/= (car p) key) (setq out (cons p out))))
  (setq lzf:*pvals* (reverse (cons (cons key i) out))))

;; What a dropdown is set to, as the word POOL would read -- "" while
;; it is still on "(ask)", which is the form's version of an empty box.
(defun lzf:pickval (c key / d i)
  (if (setq d (assoc key (lzf:picks c)))
      (progn
        (setq i (lzf:pget key))
        (if (and (> i 0) (< i (length (cadddr d)))) (nth i (cadddr d)) ""))
      ""))

;; The cross boxes this page's mode leaves live, counted off the front
;; of the chart's list -- the order the template asks them in.
(defun lzf:crosslive (c / m p)
  (if (setq m (lzf:crossmode c))
      (if (setq p (assoc (lzf:pickval c m) lzf:*crosslive*)) (cadr p) 0)
      (length (lzf:cross c))))

;; The charts POOL never asks a bottom type on.  The L family takes
;; the standard hopper and nothing else, so the popup is greyed, btype
;; is not sent, and the page is greyed against "Normal" -- the bottom
;; those flows really draw.
(setq lzf:*nobtype* '("L" "LAzyl"))

(defun lzf:btlive (c) (not (member (car c) lzf:*nobtype*)))

;; The charts whose flow puts a yes/no gate in front of the corner
;; questions ("Anything to record about the corners?").  Answer a
;; corner row on one of these and the gate is answered Yes for you;
;; leave every row on "(ask)" and the gate is left for POOL to ask.
;; The rectangle and the oval have no such gate.
(setq lzf:*crecharts*
  '("L" "LAzyl" "Grecian" "GRSquare" "OCtagon" "ROman"))

;;; -------------------- the across-chains --------------------------------
;;;  Not a layout table -- the CHART's own dimension list, read
;;;  sideways.  Every horizontal dimension sits on a line of the
;;;  drawing, and the ones sharing a line are a chain: B alone across
;;;  the top, H G F E together down the middle.  LAZTXT lays its rows
;;;  out along those chains, so the schematic reads the way the sheet
;;;  does without a second table to keep in step with the first.

;; The horizontal dims of one line, left to right.
(defun lzf:hline (c y / d out)
  (foreach d (lzf:dims c)
    (if (and (= (nth 6 d) "h") (= (nth 3 d) y) (= (nth 5 d) y))
        (setq out (cons d out))))
  (vl-sort (reverse out)
           '(lambda (p q) (< (+ (nth 2 p) (nth 4 p))
                             (+ (nth 2 q) (nth 4 q))))))

;; Every across-chain the chart has, top of the drawing downwards, as a
;; list of dimension lists.
(defun lzf:hrows (c / d ys out y)
  (foreach d (lzf:dims c)
    (if (and (= (nth 6 d) "h") (= (nth 3 d) (nth 5 d))
             (not (member (nth 3 d) ys)))
        (setq ys (cons (nth 3 d) ys))))
  (foreach y (vl-sort ys '<) (setq out (cons (lzf:hline c y) out)))
  (reverse out))

;;; -------------------- corners -----------------------------------------
;;;  A corner is a treatment plus, when the treatment is Radius or Cut,
;;;  a size -- so each gets a dropdown and a size box that is greyed
;;;  until a sized treatment is picked.  The dropdown's first entry is
;;;  "(ask)": the form's version of leaving a box empty, and the only
;;;  honest default, since POOL offers no default on a first corner
;;;  either.
;;;
;;;  IN SQUARE AND OUT OF SQUARE ARE DIFFERENT QUESTIONS, and that is
;;;  the whole reason a row carries two lists of POOL stems rather than
;;;  one name.  A row is
;;;
;;;      (stem  label  (in-square stem ...)  (out-of-square stem ...))
;;;
;;;  where stem is the row's own tile key and each list is the POOL
;;;  corner questions that row answers in that state.  An EMPTY list
;;;  means the row is not read at all there.  Three shapes of that:
;;;
;;;    Rectangle, Roman   four rows out of square, one question in
;;;                       square -- so corner A's row maps to "corners"
;;;                       and B, C and D map to nothing.
;;;    the Grecians       two collective rows.  In square POOL asks
;;;                       exactly those two (bodycorners, endcorners);
;;;                       out of square it asks all eight individually,
;;;                       so each row FANS OUT to its four, carrying
;;;                       one treatment and one size to all of them.
;;;    True L             two rows, the same two questions either way.
;;;
;;;  On the shapes that gate their corner questions behind a yes/no
;;;  (lzf:*crecharts*), picking any row answers that gate too.

(setq lzf:*ctreat* '("(ask)" "Square" "Radius" "Cut" "NotGiven"))

(setq lzf:*corners*
  '(("Rectangle"
     ("cornera" "Corner A (bottom left)"  ("corners") ("cornera"))
     ("cornerb" "Corner B (bottom right)" ()          ("cornerb"))
     ("cornerc" "Corner C (top right)"    ()          ("cornerc"))
     ("cornerd" "Corner D (top left)"     ()          ("cornerd")))
    ("ROman"
     ("cornera" "Corner A (bottom left)"  ("corners") ("cornera"))
     ("cornerb" "Corner B (bottom right)" ()          ("cornerb"))
     ("cornerc" "Corner C (top right)"    ()          ("cornerc"))
     ("cornerd" "Corner D (top left)"     ()          ("cornerd")))
    ("Grecian"
     ("bodycorners" "Body corners (all four)" ("bodycorners")
      ("cornera" "cornerb" "cornerc" "cornerd"))
     ("endcorners" "End-tip corners (LT LB RT RB)" ("endcorners")
      ("cornerlt" "cornerlb" "cornerrt" "cornerrb")))
    ("GRSquare"
     ("bodycorners" "Body corners (all four)" ("bodycorners")
      ("cornera" "cornerb" "cornerc" "cornerd"))
     ("endcorners" "End-tip corners (LT LB RT RB)" ("endcorners")
      ("cornerlt" "cornerlb" "cornerrt" "cornerrb")))
    ("OCtagon"
     ("bodycorners" "Body corners (all four)" ("bodycorners")
      ("cornera" "cornerb" "cornerc" "cornerd"))
     ("endcorners" "End-tip corners (LT LB RT RB)" ("endcorners")
      ("cornerlt" "cornerlb" "cornerrt" "cornerrb")))
    ("L"
     ("outercorners" "Outer corners (all five)"
      ("outercorners") ("outercorners"))
     ("innercorner" "Reverse corner E"
      ("innercorner") ("innercorner")))))

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

;; A mode dropdown changed: remember it, repaint the chart the list
;; unrolled across, and re-decide what is live -- a cross-dim mode is
;; one of the things lzf:dead reads, so the boxes under it change
;; state as the mode is picked.
(defun lzf:pickpick (key v)
  (lzf:pput key (atoi v))
  (lzf:redraw)
  (lzf:btgrey lzf:*chart*)
  (princ))

;; The horizontal dims whose line IS this cut.
;; Every POOL key the chart can answer with a BOX, drawn ones first,
;; then the column-only fields, then the cross dims.
(defun lzf:keys (c / d out)
  (foreach d (lzf:dims c) (setq out (cons (cadr d) out)))
  (foreach d (lzf:extra c) (setq out (cons (car d) out)))
  (foreach d (lzf:cross c) (setq out (cons (car d) out)))
  (reverse out))

;; Everything on the page that can be greyed and can be sent: the
;; boxes, the dropdowns that carry a keyword answer, and the bottom
;; type.  lzf:dead is measured against this, so a rule may name a key
;; no chart carries without anything having to know.
(defun lzf:pagekeys (c / out d)
  (setq out (lzf:keys c))
  (foreach d (lzf:picks c) (setq out (append out (list (car d)))))
  ;; the bottom type is POOL's question and an OASIS page carries no
  ;; such tile, so naming it there would grey a box that is not there
  (if (lzf:oasis-p c) out (append out (list "btype"))))

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
(setq lzf:*ranchart* nil)       ; the chart Insert was finally pressed on

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

;; The dimension line, in per-mille.  A measurement that runs along the
;; drawing -- "h" or "v" -- gets an arrowhead at each end; a radius
;; with no square run to lie along -- "p" -- gets a LEADER instead,
;; drawn from the point on the outline it names out to where its
;; letter sits.  The head shapes are the whole of the first two cases
;; because these charts have no diagonal dimension: the one
;; measurement that genuinely runs corner to corner, the cross dim, is
;; a column box on every sheet that has one.
(defun lzf:arrow (x1 y1 x2 y2 side col / a b p q)
  (vector_image (lzf:px x1) (lzf:py y1) (lzf:px x2) (lzf:py y2) col)
  (setq a 6 b 3)
  (cond
    ((= side "p") nil)                  ; a leader: the line is all of it
    ((= y1 y2)                          ; horizontal: heads point in
     (setq p (list (lzf:px (min x1 x2)) (lzf:py y1))
           q (list (lzf:px (max x1 x2)) (lzf:py y1)))
     (vector_image (car p) (cadr p) (+ (car p) a) (- (cadr p) b) col)
     (vector_image (car p) (cadr p) (+ (car p) a) (+ (cadr p) b) col)
     (vector_image (car q) (cadr q) (- (car q) a) (- (cadr q) b) col)
     (vector_image (car q) (cadr q) (- (car q) a) (+ (cadr q) b) col))
    (t                                  ; vertical
     (setq p (list (lzf:px x1) (lzf:py (min y1 y2)))
           q (list (lzf:px x1) (lzf:py (max y1 y2))))
     (vector_image (car p) (cadr p) (- (car p) b) (+ (cadr p) a) col)
     (vector_image (car p) (cadr p) (+ (car p) b) (+ (cadr p) a) col)
     (vector_image (car q) (cadr q) (- (car q) b) (- (cadr q) a) col)
     (vector_image (car q) (cadr q) (+ (car q) b) (- (cadr q) a) col))))

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
  (cond
    ;; a leader ends where its letter goes, and the letter is centred
    ;; on that spot -- the line runs up to it and the blanked strip
    ;; behind the text stops it there
    ((= side "p") (setq lx (- x2 (/ w 2)) ly (- y2 (/ h 2))))
    ((= side "h") (setq lx (- mx (/ w 2)) ly (- y1 h 4)))
    ;; a vertical dimension labels at the TOP of its span: the middle
    ;; row already carries the H/G/F/E chain across the pool.  It is
    ;; centred on its own line, EXCEPT when that would run off the
    ;; left edge -- an overall like A sits hard against the boundary
    ;; with no room on its outside, so its label goes on the inside
    ;; rather than being clipped down to a stub
    (t
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
;; start_image and one end_image so the tile is painted once: the
;; outline first, then every dimension's line, then every dimension's
;; text over the top of it -- the text blanks the strip behind itself,
;; so a letter never has a dimension line running through it.
(defun lzf:redraw ( / c poly d)
  (setq c lzf:*chart*
        lzf:*dx* (dimx_tile "chart")
        lzf:*dy* (dimy_tile "chart"))
  (start_image "chart")
  (fill_image 0 0 lzf:*dx* lzf:*dy* lzf:*col-back*)
  (foreach poly (lzf:outline c)
    (lzf:pline (lzf:flatten poly) lzf:*col-line*))
  (foreach d (lzf:dims c)
    (lzf:arrow (nth 2 d) (nth 3 d) (nth 4 d) (nth 5 d) (nth 6 d)
               lzf:*col-dim*))
  (foreach d (lzf:dims c) (lzf:label d))
  (end_image)
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

(defun lzf:tabstrip (cur / out c n)
  ;; The tab strip: one button per chart, the current one disabled so
  ;; it reads as the page you are on.  DCL has no tab tile and no way
  ;; to hide or restyle one, so "which page am I on" is carried by that
  ;; greyed button and by the dialog's own title bar.
  ;; the KEY, not the title: six full chart titles make a row 117
  ;; characters wide, twice the chart it sits above, and a dialog wider
  ;; than the screen has nowhere to go -- DCL does not scroll.
  ;;
  ;; The keys alone were not enough either.  Eight of them run about 94
  ;; cells against a budget of 90, which is a dialog that does not open
  ;; -- so they WRAP, greedily, the way the panel's pinned row does.
  ;; Adding a ninth chart costs a row rather than the whole form.
  (foreach c (lzf:tabrows)
    (setq out (cons "  : row {" out))
    (foreach n c
      (setq out (cons (strcat "    : button { key = \"tab_" n
                              "\"; label = \"" n "\"; }")
                      out)))
    (setq out (cons "  }" out)))
  (reverse out))

;; Chart keys packed into rows no wider than the budget.
(setq lzf:*tabbudget* 84)

(defun lzf:tabrows ( / out row w c cw)
  (setq row nil w 0)
  (foreach c lzf:*charts*
    (setq cw (+ (strlen (car c)) 6))
    (if (and row (> (+ w cw) lzf:*tabbudget*))
      (setq out (cons (reverse row) out) row nil w 0))
    (setq row (cons (car c) row) w (+ w cw)))
  (if row (setq out (cons (reverse row) out)))
  (reverse out))

(setq lzf:*chart-w* 52)         ; the chart column, in character cells
(setq lzf:*chart-a* "0.72")     ; and its height, as a share of that

;;; -------------------- packing the column boxes ------------------------
;;;  A DCL DIALOG TALLER THAN THE SCREEN DOES NOT OPEN, and nothing
;;;  here can measure a screen: DCL reports a tile's size only while
;;;  the dialog is already up, which is too late to lay it out.  So the
;;;  column-only boxes are packed TWO TO A ROW wherever the pair still
;;;  fits across.  Nine of them stacked -- which is what a Roman sheet
;;;  with the Sport chain on it would be -- is nine rows for nine
;;;  numbers; five rows carries the same nine.
;;;
;;;  A row wider than the screen does not open either, though, and both
;;;  labels of a pair sit on one line.  So the pair is only made when
;;;  the two labels and their boxes fit the budget below; a field whose
;;;  label is a sentence keeps a row of its own, at its full width.
;;;  That is why the pairing does not always fall on the group
;;;  boundaries a reader might expect -- it follows the width, and
;;;  every box is labelled for itself either way.

(setq lzf:*rowbudget* 92)       ; cells a packed row may occupy

;; One column-only box, at the given width and indent.
(defun lzf:extbox (d w ind)
  (strcat ind ": edit_box { key = \"" (car d) "\"; label = \"" (cadr d)
          "\"; edit_width = " (itoa w) "; }"))

;; (key label) fields as DCL lines, two to a row where they fit.
(defun lzf:packrows (items ind / out a b)
  (while items
    (setq a (car items) b (cadr items))
    (if (and b (<= (+ (strlen (cadr a)) (strlen (cadr b)) 20) lzf:*rowbudget*))
      (setq out (append out
                        (list (strcat ind ": row {")
                              (lzf:extbox a 6 (strcat ind "  "))
                              (lzf:extbox b 6 (strcat ind "  "))
                              (strcat ind "}")))
            items (cddr items))
      (setq out (append out (list (lzf:extbox a 9 ind)))
            items (cdr items))))
  out)

;; The Sport chain is packed on its own so it reads as the chain it is
;; rather than being broken across a row boundary by whatever the
;; depths happened to leave over.  It is a group in the greying rules
;; too -- lzf:dead names it from here.
(setq lzf:*sportchain* '("e2" "f2" "f1" "e1"))

(defun lzf:sportof (items / d out)
  (foreach d items
    (if (member (car d) lzf:*sportchain*) (setq out (cons d out))))
  (reverse out))

(defun lzf:notsport (items / d out)
  (foreach d items
    (if (not (member (car d) lzf:*sportchain*)) (setq out (cons d out))))
  (reverse out))

;; A keyword dropdown as a DCL line.
(defun lzf:pickline (d ind)
  (strcat ind ": popup_list { key = \"" (car d) "\"; label = \"" (cadr d)
          "\"; edit_width = 12; }"))

;; A second line under the form, for what only this page has to
;; explain.  The Grecians earn one: two of their three cross-dim modes
;; ask for far more diagonals than a sheet has boxes, so the dropdown
;; answers the gate and the tape numbers are typed at the command line
;; -- which is worth saying on the page rather than in a README.
(setq lzf:*grechint*
  (strcat "Cross dims: Simple takes the two boxes here; Center and "
          "Complex answer the gate and ask their 14 or 18 diagonals at "
          "the command line."))

(setq lzf:*hints*
  (list (cons "Grecian" lzf:*grechint*)
        (cons "GRSquare" lzf:*grechint*)
        (cons "OCtagon" lzf:*grechint*)))

(defun lzf:hint (c) (cdr (assoc (car c) lzf:*hints*)))

;; One dialog per chart.  They all live in one generated file so the
;; page loop can load_dialog once and switch pages without touching
;; the disk again.
(defun lzf:dcl-one (c / out d l)
  ;; out is consed newest-first and reversed once at the end, so this
  ;; seed list reads BACKWARDS: the label second here puts it second in
  ;; the file, after the line that opens the dialog.  The other way
  ;; round emits an attribute before its own dialog, which is not DCL.
  (setq out (list (strcat "  label = \"LazForm - " (caddr c) "\";")
                  (strcat (lzf:dlgname (car c)) " : dialog {")))
  (setq out (append (reverse (lzf:tabstrip (car c))) out))
  (setq out (cons "  : row {" out))
  ;; A PASSIVE image tile, deliberately -- see "why the picture is not
  ;; clickable" above -- and ONE of them: the whole chart, whole.
  (setq out (cons (strcat "    : image { key = \"chart\"; width = "
                          (itoa lzf:*chart-w*) "; aspect_ratio = "
                          lzf:*chart-a* "; fixed_width = true; "
                          "fixed_height = true; color = -15; }")
                  out))
  (setq out (cons "    : column {" out))
  (setq out (cons "      : boxed_column {" out))
  (setq out (cons "        label = \"Dimensions\";" out))
  ;; Each dimension is a row: its LETTER as a button, then the box.
  ;; Clicking the letter puts the caret in that box and rings the
  ;; dimension on the chart -- which is as close to clicking the
  ;; drawing itself as DCL allows, and the button sits against the box
  ;; it fills rather than off in a separate list.  EVERY dimension the
  ;; chart draws has a row here: the picture is read, the column is
  ;; typed into, and the letter is what ties the two together.
  (foreach d (lzf:dims c)
    (setq out (cons "        : row {" out))
    (setq out (cons (strcat "          : button { key = \"pick_"
                            (cadr d) "\"; label = \"" (car d)
                            "\"; fixed_width = true; }")
                    out))
    (setq out (cons (strcat "          : edit_box { key = \"" (cadr d)
                            "\"; edit_width = 9; label = \"" (nth 7 d)
                            "\"; }")
                    out))
    (setq out (cons "        }" out)))
  (setq out (cons "      }" out))
  (if (lzf:extra c)
    (progn
      (setq out (cons "      : boxed_column {" out))
      (setq out (cons "        label = \"Not on this view\";" out))
      (foreach l (append
                   (lzf:packrows (lzf:notsport (lzf:extra c)) "        ")
                   (lzf:packrows (lzf:sportof (lzf:extra c)) "        "))
        (setq out (cons l out)))
      (setq out (cons "      }" out))))
  ;; the cross dims, with the question that decides how many of them
  ;; POOL will ask for at the head of the box
  (if (lzf:cross c)
    (progn
      (setq out (cons "      : boxed_column {" out))
      (setq out (cons "        label = \"Cross dims (out-of-square only)\";" out))
      (foreach d (lzf:picks c)
        (if (= (caddr d) "cross")
            (setq out (cons (lzf:pickline d "        ") out))))
      (foreach l (lzf:packrows (lzf:cross c) "        ")
        (setq out (cons l out)))
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
  ;; the in-square toggle and the bottom type are POOL's questions and
  ;; nothing on an oasis answers to either: it is arcs all round, so
  ;; there is no corner to run a tape across, and its floor is asked
  ;; about after the outline is drawn
  (if (not (lzf:oasis-p c))
    (progn
      (setq out (cons (strcat "        : toggle { key = \"insq\"; "
                              "label = \"Pool is in-square "
                              "(no cross dims)\"; }")
                      out))
      (setq out (cons (strcat "        : popup_list { key = \"btype\"; "
                              "label = \"Bottom type\"; }")
                      out))))
  ;; the keyword questions that are not about cross dims live here,
  ;; with the toggle and the bottom type
  (foreach d (lzf:picks c)
    (if (= (caddr d) "run")
        (setq out (cons (lzf:pickline d "        ") out))))
  (setq out (cons "      }" out))
  (setq out (cons "    }" out))
  (setq out (cons "  }" out))
  (setq out (cons "  spacer;" out))
  (setq out (cons (strcat "  : text { key = \"hint\"; width = 62; "
                          "label = \"Read the letters off the chart and type "
                          "the numbers in the column beside it.  Type NA where "
                          "nothing was measured; leave a box empty and "
                          (if (lzf:oasis-p c) "OASIS" "POOL")
                          " will ask.\"; }")
                  out))
  (if (lzf:hint c)
    (setq out (cons (strcat "  : text { key = \"hint2\"; width = 62; label = \""
                            (lzf:hint c) "\"; }")
                    out)))
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
  (setq out (append out (lzf:dcl-ascii) (list "")))
  (append out (lzf:dcl-txt (lzf:chart "Rectangle")) (list "")))

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
;;;  ANSWERED, on AutoCAD 2018+: the font is PROPORTIONAL.  Twelve W's
;;;  came out about three times the width of twelve i's, the bars were
;;;  nowhere near a column, and the pool drawn in characters sheared
;;;  apart line by line.  Leading spaces do survive -- the staircase in
;;;  section 2 was clean -- but that does not help on its own.
;;;
;;;  Section 4 is the half that works, and it is what the wedge rows
;;;  already do: a row of text tiles with explicit widths and an edit
;;;  box between them lines up in a proportional font, because the
;;;  alignment comes from tile widths and not from glyphs.  So the
;;;  boxes-in-the-line half was already here and the ASCII half never
;;;  will be.  Kept because the answer belongs to the AutoCAD build,
;;;  not to this code, and is worth re-asking elsewhere.
;;;
;;;  So this asks AutoCAD instead of guessing.  Run LAZASCII and look:
;;;  section 1 says whether the font is fixed-pitch, section 2 shows
;;;  what a pool would look like if it is, and section 3 shows the
;;;  fallback that works either way -- a row of tiles, where alignment
;;;  comes from tile widths rather than from glyphs.
;; The pool exactly as it is drawn on paper, in characters.  If a list
;; box turns out to be fixed-pitch this is what the form could show --
;; retained, never wiped by a repaint, and the real shape rather than a
;; rectangle standing in for one.
(setq lzf:*poolart* (list
    "    <--------------------------------- B --------------------------------->"
    "    +---------------------------------------------------------------------+"
    " ^  |\\                  ^                        ______/|                 |"
    " |  | \\                 M                 ______/       |                 |"
    " |  |  \\                |          ______/              |                 |"
    " |  |   \\               v   ______/                     |                 |"
    " |  |    \\+-----------+_____                            |                 |"
    " |  |     |           |  ^                              |                 |"
    " |  |     |           |  L                              |                 |"
    " A  |<-H->|<--- G --->|<-------------- F -------------->|<------ E ------>|"
    " |  |     |           |  |                              |                 |"
    " |  |     |           |  v                              |                 |"
    " |  |    /+-----------+_____                            |                 |"
    " |  |   /               ^   \\______                     |                 |"
    " |  |  /                |          \\______              |                 |"
    " |  | /                 K                 \\______       |                 |"
    " v  |/                  v                        \\______|                 |"
    "    +---------------------------------------------------------------------+"
  ))

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
    "  : boxed_column {"
    "    label = \"5.  Is a LIST BOX fixed-pitch?\";"
    (strcat "    : text { label = \"A text tile is not.  A list box is a "
            "different control -- if ITS bars line up,\"; }")
    (strcat "    : text { label = \"the pool below can be drawn in "
            "characters after all.\"; }")
    "    : list_box { key = \"ruler\"; width = 32; height = 5; }"
    "    : list_box { key = \"pool\"; width = 78; height = 18; }"
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
(defun c:LAZASCII ( / f dcl l)
  (cond
    ((not (setq f (lzf:write-dcl)))
     (princ "\nLAZASCII error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZASCII error: could not load the dialog file."))
    (t
     (if (new_dialog "lazform_ascii" dcl)
       (progn
         ;; the same twelve characters the text tiles got, and then the
         ;; pool -- populated at run time, which is how a list box is fed
         (start_list "ruler")
         (foreach l '("|iiiiiiiiiiii|" "|WWWWWWWWWWWW|" "|000000000000|"
                      "|------------|" "|            |")
           (add_list l))
         (end_list)
         (start_list "pool")
         (foreach l lzf:*poolart* (add_list l))
         (end_list)
         (action_tile "cancel" "(done_dialog 0)")
         (start_dialog)))
     (unload_dialog dcl)
     (vl-file-delete f)
     (princ (strcat "\nLAZASCII: if sections 1-3 lined up, the chart can be"
                    " drawn in characters -- and a text tile, unlike an"
                    " image tile, is never wiped by a repaint."))))
  (princ))

;;; -------------------- the text view -----------------------------------
;;;  LAZTXT: the pool drawn out of TILES rather than out of vectors,
;;;  with the boxes inside it.
;;;
;;;  The LAZASCII probe killed character art -- the dialog font is
;;;  proportional, so a pool drawn in "+---+" shears apart line by line.
;;;  But it also showed the half that works: a row of tiles with
;;;  declared widths lines up perfectly, because the alignment comes
;;;  from the tiles and not from the glyphs.
;;;
;;;  DCL has something better than dashes for the outline.  A
;;;  boxed_row or boxed_column draws a REAL etched border -- drawn by
;;;  the widget, so it is straight by construction and cannot shear.
;;;  Nest one inside another and you have a pool with a hopper in it;
;;;  put the edit boxes inside those clusters and the fields are IN the
;;;  drawing rather than beside it.
;;;
;;;  What it buys over the vector chart: every tile here is RETAINED.
;;;  DCL does not retain an image tile -- a repaint clears it and there
;;;  is no expose callback -- which is the standing hazard behind the
;;;  chart having vanished on people.  Nothing in this view can vanish.
;;;
;;;  What it costs: the outline is a rectangle whatever the pool is.  A
;;;  boxed cluster cannot be round, cut-cornered or L-shaped, so this
;;;  is a schematic of where the numbers sit, not a picture of the
;;;  pool.  Which is why it is a SECOND view and not a replacement.

;; The v dim that spans the most: the overall, which belongs outside the
;; hopper rather than in it.
(defun lzf:txt-tallest (c / d best bs sp)
  (foreach d (lzf:dims c)
    (if (= (nth 6 d) "v")
      (progn
        (setq sp (abs (- (nth 5 d) (nth 3 d))))
        (if (or (not best) (> sp bs)) (setq best d bs sp)))))
  best)

(defun lzf:txt-box (d w)
  (strcat "        : edit_box { key = \"" (cadr d) "\"; label = \""
          (car d) "\"; edit_width = " (itoa w) "; }"))

;; One row per across-chain, top of the drawing downwards: the chain
;; the way it reads on the sheet.
(defun lzf:txt-rows (c / out ds d)
  (foreach ds (lzf:hrows c)
    (setq out (cons "      : row {" out))
    (foreach d ds (setq out (cons (lzf:txt-box d 6) out)))
    (setq out (cons "      }" out)))
  (reverse out))

;; The first chain on its own -- the overall length, above the pool the
;; way the sheet has it.
(defun lzf:txt-firstrow (c / out d)
  (setq out (list "    : row {"))
  (foreach d (car (lzf:hrows c)) (setq out (cons (lzf:txt-box d 6) out)))
  (reverse (cons "    }" out)))

;; Every chain after the first.
(defun lzf:txt-restrows (c / out ds d)
  (foreach ds (cdr (lzf:hrows c))
    (setq out (cons "      : row {" out))
    (foreach d ds (setq out (cons (lzf:txt-box d 6) out)))
    (setq out (cons "      }" out)))
  (reverse out))

(defun lzf:dcl-txt (c / out tall d rows)
  (setq tall (lzf:txt-tallest c))
  (setq out (list
    "lazform_txt : dialog {"
    (strcat "  label = \"LAZFORM text view  -  " (nth 2 c) "\";")
    (strcat "  : text { label = \"The boxes sit IN the drawing.\"; }")
    (strcat "  : text { label = \"Nothing here is an image tile, so "
            "nothing here can be wiped.\"; }")
    (strcat "  : boxed_column {")
    (strcat "    label = \"" (nth 2 c) "\";")))
  ;; the first across-row -- the overall length -- goes ABOVE the body,
  ;; where the sheet puts it
  (setq rows (lzf:txt-rows c))
  (if rows
    (progn
      (setq out (append out (lzf:txt-firstrow c)))
      (setq rows (lzf:txt-restrows c))))
  ;; the overall width, outside the hopper, then the pool body
  (setq out (append out (list "    : boxed_row {" "      label = \"\";")))
  (if tall
    (setq out (append out (list "      : boxed_column {"
                                "        label = \"Overall\";"
                                (lzf:txt-box tall 8)
                                "      }"))))
  (setq out (append out (list "      : boxed_column {"
                              "        label = \"Hopper\";")))
  (foreach d (lzf:dims c)
    (if (and (= (nth 6 d) "v") (not (equal d tall)))
      (setq out (append out (list (lzf:txt-box d 6))))))
  (setq out (append out (list "      }" "    }")))
  ;; the remaining across-chains, one row per cut, in drawing order
  (if rows
    (setq out (append out (list "    : boxed_column {"
                                "      label = \"Across\";")
                      rows
                      (list "    }"))))
  ;; and the boxes with no place in the schematic at all: the
  ;; column-only fields and the cross dims
  (setq out (append out (list "    : boxed_column {"
                              "      label = \"And the rest\";")))
  (foreach d (append (lzf:extra c) (lzf:cross c))
    (setq out (append out (list (strcat "        : edit_box { key = \""
                                        (car d) "\"; label = \"" (cadr d)
                                        "\"; edit_width = 8; }")))))
  (setq out (append out (list "    }" "  }")))
  (append out
    (list "  spacer;"
          "  : row {"
          (strcat "    : button { key = \"accept\"; label = \"Insert\"; "
                  "is_default = true; fixed_width = true; }")
          (strcat "    : button { key = \"cancel\"; label = \"Cancel\"; "
                  "is_cancel = true; fixed_width = true; }")
          "  }"
          "}")))

;; Show it, collect it, and hand POOL the same alist LAZFORM would.
(defun lzf:txt-show (c / f dcl rc k out)
  (setq lzf:*vals* nil lzf:*cvals* nil lzf:*pvals* nil lzf:*chart* c)
  (cond
    ((not (setq f (lzf:write-dcl)))
     (princ "\nLAZTXT error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZTXT error: could not load the dialog file."))
    (t
     (cond
       ((not (new_dialog "lazform_txt" dcl))
        (princ "\nLAZTXT error: could not open the view."))
       (t
        (foreach k (lzf:keys c)
          (action_tile k (strcat "(lzf:put \"" k "\" $value)")))
        (action_tile "accept" "(done_dialog 1)")
        (action_tile "cancel" "(done_dialog 0)")
        (setq rc (start_dialog))
        (if (= rc 1)
          (setq out (lzf:form (cadr c) lzf:*insq*
                              (nth lzf:*btype* lzf:*btypes*))))))
     (unload_dialog dcl)
     (vl-file-delete f)))
  out)

(defun c:LAZTXT ( / c form)
  (setq c (lzf:chart "Rectangle"))
  (cond
    ((not pool:run-with-answers)
     (princ "\nLAZTXT: POOL is not loaded in this session -- APPLOAD")
     (princ "\n        lisp/pool/POOL.LSP, or LAZPASS.lsp which has both."))
    ((setq form (lzf:txt-show c))
     (princ (strcat "\nLAZTXT: " (itoa (length form))
                    " answers to POOL; it will ask for whatever is left."))
     (pool:run-with-answers form))
    (t (princ "\nLAZTXT: cancelled, nothing drawn.")))
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
;;; -------------------- what this page actually asks ---------------------
;;;  A page does not ask for every box on it, and the form used to
;;;  offer them all anyway: type a C against a Normal hopper and POOL
;;;  never asks for it, so the number went nowhere and nothing said so.
;;;  THREE things on the page decide, not one:
;;;
;;;    the bottom type    which of the plan and depth letters that
;;;                       bottom's own routine will ask for;
;;;    the in-square      whether there are cross dims at all, and
;;;    toggle             whether the second overalls are asked;
;;;    the mode dropdown  how many of the cross boxes map to a tape.
;;;
;;;  lzf:dead puts the three together and names the dead keys once.
;;;  lzf:btgrey greys exactly that set and lzf:form drops exactly that
;;;  set -- one function, two callers -- so the page cannot grey a box
;;;  and then send what is in it, or send a box it has greyed.
;;;
;;;  The bottom-type half comes from POOL'S OWN pool:btmspec rather
;;;  than a copy of it here -- (ask-G ask-E has-profile ask-C2 slack)
;;;  -- so the two cannot drift.  LAZFORM already refuses to open
;;;  without POOL loaded, so it is always there to ask.
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
;;;  L K, not H G F E.  So on a Sport the chart's H, F and E boxes are
;;;  greyed: they are not what POOL will ask for, and a number typed
;;;  into one would be read by nothing.  The other side of that trade
;;;  is in lzf:dead: E2 F2 F1 E1 have boxes on every sheet whose flow
;;;  can reach a Sport, and every bottom that is NOT a Sport greys
;;;  them.
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

;; THE ONE AUTHORITY.  Every key on this page POOL will not ask about,
;; given the bottom type, the in-square toggle and the mode dropdowns
;; (which are read from their own store, the way the boxes are).  The
;; answer is restricted to keys the page really carries, so a rule may
;; name a key no chart has and the two callers can both trust the list
;; -- mode_tile on a tile that is not there would error.
;; A POOL page's dead keys: the bottom type, the in-square toggle and
;; the mode dropdown, put together.
(defun lzf:pooldead (c insq btype / out bt n i k)
  ;; the L family: POOL asks no bottom type there at all, so the popup
  ;; is dead and the page is judged against the bottom those flows
  ;; really draw
  (setq bt (if (lzf:btlive c) btype "Normal")
        out (if (lzf:btlive c) nil (list "btype")))
  (setq out (append out (lzf:btskip bt)))
  ;; the Sport chain is asked by a Sport bottom and by nothing else
  (if (/= bt "Sport")
      (setq out (append out lzf:*sportchain*)))
  ;; in square there are no cross dims to measure, no mode to measure
  ;; them from, and no second overall
  (if insq
      (setq out (append out (list "bo" "ri")
                        (mapcar 'car (lzf:cross c))
                        (if (lzf:crossmode c) (list (lzf:crossmode c))))))
  ;; and out of square, only as many cross boxes as the mode maps: the
  ;; rest stand for tapes this mode does not run
  (setq n (lzf:crosslive c) i 0)
  (foreach k (lzf:cross c)
    (if (>= i n) (setq out (cons (car k) out)))
    (setq i (1+ i)))
  out)

;; An OASIS page's, which is the same idea read the other way round:
;; lzf:*oaslive* names what the shape DOES ask for in this state, and
;; everything else on the sheet is dead.  A cloud's pinned left bulge,
;; the kidney radius the other kidney derives, a hump offset on a
;; simple run -- each is dead here for the reason a Normal hopper's C
;; is dead on a POOL page: OASIS will never ask, so a number typed
;; into it would be read by nothing.  The dropdowns themselves are
;; always live; they are the questions the rest hangs off.
(defun lzf:oasdead (c / live out k)
  (setq live (lzf:oaslive c))
  (foreach k (lzf:picks c) (setq live (cons (car k) live)))
  (foreach k (lzf:pagekeys c)
    (if (not (member k live)) (setq out (cons k out))))
  (reverse out))

(defun lzf:dead (c insq btype / out k have seen)
  (setq out (if (lzf:oasis-p c)
                (lzf:oasdead c)
                (lzf:pooldead c insq btype)))
  ;; keep what this page actually has, once each
  (setq have (lzf:pagekeys c))
  (foreach k out
    (if (and (member k have) (not (member k seen)))
        (setq seen (cons k seen))))
  (reverse seen))

;; Grey every dead key on the page, un-grey the rest.
(defun lzf:btgrey (c / dead k)
  (setq dead (lzf:dead c lzf:*insq* (nth lzf:*btype* lzf:*btypes*)))
  (foreach k (lzf:pagekeys c)
    (mode_tile k (if (member k dead) 1 0))))

(defun lzf:form (shape insq btype)
  (if (lzf:oasis-p lzf:*chart*)
      (lzf:oasform shape)
      (lzf:poolform shape insq btype)))

;; What OASIS is handed.  Shorter than POOL's by everything POOL has
;; that an oasis has not: no corners on a shape with none, no cross
;; dims on one with no straight side to run a tape across, no bottom
;; type -- OASIS asks about the floor after the outline is drawn and
;; not before.  The shape itself is the page, so it always travels.
(defun lzf:oasform (shape / out k v a dead d)
  (setq dead (lzf:dead lzf:*chart* nil nil)
        out  (list (cons 'shape shape)))
  (foreach k (lzf:keys lzf:*chart*)
    (setq v (lzf:get k)
          a (lzf:answer v))
    (if (and (not (eq a 'SKIP)) (not (member k dead)))
        (setq out (cons (cons (read k) a) out))))
  ;; the cloud's bottom, the kidney's type and simple-or-complex: a
  ;; keyword answer in its own right, and one left on "(ask)" sends
  ;; nothing, exactly as an empty box does
  (foreach d (lzf:picks lzf:*chart*)
    (setq v (lzf:pickval lzf:*chart* (car d)))
    (if (and (/= v "") (not (member (car d) dead)))
        (setq out (cons (cons (read (car d)) v) out))))
  (reverse out))

(defun lzf:poolform (shape insq btype / out k v a dead d cp)
  (setq dead (lzf:dead lzf:*chart* insq btype))
  (setq out (list (cons 'shape shape)
                  (cons 'insq (if insq "Insquare" "Outofsquare"))))
  ;; a key this page never asks about does not travel: it would sit in
  ;; the store unread, and a form that quietly carries dead answers is
  ;; harder to reason about than one that does not
  (if (and btype (/= btype "") (not (member "btype" dead)))
      (setq out (cons (cons 'btype btype) out)))
  (foreach k (lzf:keys lzf:*chart*)
    (setq v (lzf:get k)
          a (lzf:answer v))
    (if (and (not (eq a 'SKIP)) (not (member k dead)))
        (setq out (cons (cons (read k) a) out))))
  ;; the mode dropdowns: a keyword answer in its own right, and one
  ;; left on "(ask)" sends nothing, exactly as an empty box does
  (foreach d (lzf:picks lzf:*chart*)
    (setq v (lzf:pickval lzf:*chart* (car d)))
    (if (and (/= v "") (not (member (car d) dead)))
        (setq out (cons (cons (read (car d)) v) out))))
  ;; the corners: a dropdown left on (ask) sends nothing, a sized
  ;; treatment carries its size when one parses, and each row goes to
  ;; whichever POOL questions it answers in this state
  (setq cp (lzf:cornerpairs insq))
  (foreach k cp
    (setq out (cons k out)))
  ;; the corner gate.  On the shapes that put a yes/no in front of the
  ;; corner questions, a row picked here answers that gate too -- the
  ;; treatments would be read by nothing if it were left on No
  (if (and cp (member (car lzf:*chart*) lzf:*crecharts*))
      (setq out (cons (cons 'crec "Yes") out)))
  ;; the gates last, so a chart cannot be talked out of the path its
  ;; own letters live on
  (foreach k (lzf:gates lzf:*chart*)
    (setq out (cons (cons (read (car k)) (cdr k)) out)))
  (reverse out))

;; The (key . value) pairs the corner rows contribute.  A row carries
;; one treatment and one size to every POOL stem it answers in this
;; state: one on a rectangle corner, four when a Grecian's collective
;; row fans out to the corners POOL asks individually.
(defun lzf:cornerpairs (insq / out d stem targets i ty sz u)
  (foreach d (lzf:corners lzf:*chart*)
    (setq stem (car d)
          targets (if insq (caddr d) (cadddr d)))
    (if (and targets (> (setq i (lzf:cget stem)) 0))
        (progn
          (setq ty (nth i lzf:*ctreat*)
                sz (if (lzf:csized i)
                       (lzf:answer (lzf:get (strcat stem "-sz")))))
          (foreach u targets
            (setq out (cons (cons (read (strcat u "-ty")) ty) out))
            (if (numberp sz)
                (setq out (cons (cons (read (strcat u "-sz")) sz) out)))))))
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
        lzf:*pvals* nil                 ; and the mode dropdowns with them
        lzf:*insq* nil                  ; the toggle's own starting state
        lzf:*btype* 0                   ; Normal, first in the list
        lzf:*pos* nil                   ; where the user last had it
        lzf:*ranchart* nil              ; no page has been accepted yet
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
          ;; the bottom type and the in-square toggle are POOL's, and
          ;; an OASIS page carries neither tile -- so neither is
          ;; filled in, set or bound there
          (if (not (lzf:oasis-p c))
            (progn
              (start_list "btype")
              (foreach d lzf:*btypes* (add_list d))
              (end_list)
              (set_tile "btype" (itoa lzf:*btype*))))
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
          ;; the mode dropdowns -- the cross-dim reference and the L's
          ;; mirror -- filled and put back the same way, and each
          ;; re-decides what is live as it changes
          (foreach d (lzf:picks c)
            (start_list (car d))
            (foreach n (cadddr d) (add_list n))
            (end_list)
            (set_tile (car d) (itoa (lzf:pget (car d))))
            (action_tile (car d)
              (strcat "(lzf:pickpick \"" (car d) "\" $value)")))
          (if (and lzf:*insq* (not (lzf:oasis-p c))) (set_tile "insq" "1"))
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
          (foreach d (lzf:dims c)
            (action_tile (strcat "pick_" (cadr d))
              (strcat "(setq lzf:*focus* \"" (cadr d) "\") (lzf:redraw)"
                      " (mode_tile \"" (cadr d) "\" 2)"
                      " (mode_tile \"" (cadr d) "\" 3)")))
          ;; the tabs -- each closes this page and names the next
          (foreach d lzf:*charts*
            (action_tile (strcat "tab_" (car d))
              (strcat "(setq lzf:*go* \"" (car d)
                      "\" lzf:*pos* (done_dialog 4))")))
          ;; the chart takes no action -- it is a passive image tile.
          ;; These two capture their value as it changes: get_tile
          ;; answers about a LIVE dialog, and by the time the answers
          ;; are assembled this one is closed and unloaded.
          (if (not (lzf:oasis-p c))
            (progn
              (action_tile "btype"
                (strcat "(setq lzf:*btype* (atoi $value)) (lzf:redraw)"
                        " (lzf:btgrey lzf:*chart*)"))
              ;; the toggle decides the cross dims and the second
              ;; overalls, so it re-greys the page as well as
              ;; repainting the chart
              (action_tile "insq"
                (strcat "(setq lzf:*insq* (= $value \"1\")) (lzf:redraw)"
                        " (lzf:btgrey lzf:*chart*)"))))
          (action_tile "accept" "(setq lzf:*pos* (done_dialog 1))")
          (action_tile "cancel" "(setq lzf:*pos* (done_dialog 0))")
          (lzf:redraw)
          (lzf:btgrey c)
          (setq rc (start_dialog))
          (cond
            ((= rc 4) (setq go lzf:*go*))     ; a tab: go round again
            (t (setq done t
                     lzf:*ranchart* (if (= rc 1) (car c))
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

;; The form, then the routine the page it was filled in on feeds.
;; COVER closes POOL's pool-bottom gate first: a cover sheet has no
;; floor work on it, so the depth chain behind that gate is neither
;; asked for nor drawn.  The flag goes on at the last moment -- after
;; the form comes back -- so a cancelled form leaves the session
;; exactly as it found it, and c:POOL clears it again on the way out
;; either way.  It is a POOL flag and the OASIS pages never set it: an
;; oasis is asked about its floor after the outline exists, so there
;; is no gate in front of the question to close.
(defun lzf:run (cover / form c)
  (cond
    ;; the chart fills POOL's answers in, so POOL has to be here to
    ;; receive them -- say so plainly rather than opening a form whose
    ;; Insert button could only fail.  POOL and not OASIS, because
    ;; POOL is what lzf:btskip reads the bottom-type rules out of, so
    ;; without it not even the greying on a rectangle sheet is honest
    ((not pool:run-with-answers)
     (princ "\nLAZFORM: POOL is not loaded in this session -- APPLOAD")
     (princ "\n         lisp/pool/POOL.LSP, or LAZPASS.lsp which has both."))
    ((not (setq form (lzf:show (car (car lzf:*charts*)))))
     (princ "\nLAZFORM: cancelled, nothing drawn."))
    ((not (lzf:oasis-p (setq c (lzf:chart lzf:*ranchart*))))
     (princ (strcat "\nLAZFORM: " (itoa (length form))
                    " answers to POOL; it will ask for whatever is left."))
     (if cover
       (progn
         (setq pool:*nobottom* t)
         (princ "\n         Cover sheet - no pool bottom will be asked for.")))
     (pool:run-with-answers form))
    ;; an oasis sheet, and OASIS is the one that has to be here for it
    ((not oasis:run-with-answers)
     (princ "\nLAZFORM: that is an OASIS sheet and OASIS is not loaded in")
     (princ "\n         this session -- APPLOAD lisp/oasis/OASIS.lsp, or")
     (princ "\n         LAZPASS.lsp which has the lot.  Nothing drawn."))
    (t
     (princ (strcat "\nLAZFORM: " (itoa (length form))
                    " answers to OASIS; it will ask for whatever is left."))
     (oasis:run-with-answers form)))
  (princ))

(defun c:LAZFORM () (lzf:run nil))

(defun c:LAZFORMCOVER () (lzf:run t))

(defun c:LAZFORMVER ( / c n)
  (setq n 0)
  (foreach c lzf:*charts* (if (lzf:oasis-p c) (setq n (1+ n))))
  (princ (strcat "\nLAZFORM " *lazform-version* " (LAZFORM.lsp) - "
                 (itoa (length lzf:*charts*)) " chart(s), "
                 (itoa n) " of them OASIS."))
  (princ))

(princ (strcat "\nLAZFORM " *lazform-version*
               " loaded.  Type LAZFORM to fill a chart in and draw it."))
(princ)
