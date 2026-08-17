;;; ====================================================================
;;;  TUTORIALSPA.LSP -- how SPA.LSP works, for someone meeting it new
;;;
;;;  Command:  TUTORIALSPA
;;;
;;;    Checklist  every question it asks, every decision it makes for
;;;               you, and every check it runs -- written to the text
;;;               window, and optionally placed in the drawing as a
;;;               reference sheet you can plot.
;;;    Demo       draws a worked cover a step at a time, explaining each
;;;               step before it appears, so you see what SPA produces
;;;               and why.  Nothing is asked for: the measurements are
;;;               canned.
;;;    Both       the checklist, then the demo.
;;;
;;;  Requires SPA.LSP to be loaded first -- the demo drives the real
;;;  drawing functions (spa:drawrect, spa:dimov, the hinge solver ...),
;;;  so what it shows is what SPA actually does, not a mock-up.  Only
;;;  the ORDER of the steps is duplicated here; if the flow in SPA.LSP
;;;  changes, walk this file through with it.
;;;
;;;  This file ships twice under two names with IDENTICAL contents:
;;;      TUTORIALSPA.LSP                 the static name
;;;      TUTORIALSPA_MMDDYY_REV##.LSP    named for its revision
;;; ====================================================================

(setq tut:*version* "081726 REV01")

;;; -------------------- the worked example -----------------------------
;;;  140 x 110 cover, one diagonal corner, water's edge 3" inside it,
;;;  Standard 4-3.  Chosen because it exercises nearly everything:
;;;  mixed corners (so flats and a 90 Typ. mark appear), both outlines,
;;;  the overlap dimension, three pieces (so a fold hinge AND a velcro
;;;  hinge get drawn), and a hinge run long enough to call for a double
;;;  C channel.

(setq tut:*w*    140.0)
(setq tut:*l*    110.0)
(setq tut:*gap*    3.0)
(setq tut:*cut*   21.0)             ; the diagonal cut face at corner C
(setq tut:*fw*    48.0)             ; Standard 4-3 foam width
(setq tut:*fl*   144.0)             ; ... and its length

;;; -------------------- little helpers ---------------------------------

(defun tut:say (s) (princ (strcat "\n" s)) (princ))

(defun tut:head (s)
  (princ (strcat "\n\n=== " s " "))
  (princ (substr "=========================================================="
                 1 (max 3 (- 58 (strlen s)))))
  (princ))

(defun tut:pause ( / v)
  (setq v (getstring "\n      [Enter to carry on, X to stop] "))
  (if (or (= v "x") (= v "X")) 'TUT-STOP))

;; Zoom so the whole demo, dimensions and all, is on screen.
(defun tut:zoom ()
  (command "_.ZOOM" "_Window"
           (spa:wp (list -80.0 -80.0))
           (spa:wp (list (+ tut:*w* 200.0) (+ tut:*l* 70.0)))))

;; A step: explain, draw, show, wait.  tfn is a function of no arguments.
;;
;; AutoLISP is dynamically scoped, so a local of THIS function is visible
;; inside the callback -- a local named `l` here would shadow the demo's
;; cover length while the callback ran.  Hence the deliberately odd
;; names: nothing here may collide with a variable tut:demo uses.
(defun tut:step (ttitle tlines tfn / tln)
  (tut:head ttitle)
  (foreach tln tlines (tut:say (strcat "  " tln)))
  (apply tfn nil)
  (tut:zoom)
  (tut:pause))

;;; -------------------- the checklist ----------------------------------

(setq tut:*asks*
  (list
    "1.  The Spa Cover Details block -- picked FIRST, because its GRADE"
    "    decides what comes next.  Enter skips it; the hinge pass will"
    "    ask again.  GRADE and TAPER are read off the tags, and the"
    "    'Grade:' / 'Taper:' prefixes are stripped."
    "2.  Water's edge or cover size.  NOT asked on Thermo-Light -- the"
    "    two are the same thing there, so it draws the cover size."
    "3.  Shape: Rectangle, Octagon or Round."
    "4.  Insertion base point (Enter = 0,0).  Your own object snaps stay"
    "    live for this pick, and for every measurement prompt after it."
    "5.  The measurements, against a grey guide spa whose matching piece"
    "    turns RED while it is being asked for.  Back re-asks the"
    "    previous question, right across the whole input phase."
    "6.  Rectangle corners, one at a time: Radius / Diagonal / 90."
    "    Corner A's answer autofills B, C and D -- Enter accepts."
    "7.  Draw the other outline as well?  By Offset (give the lap) or by"
    "    Dims (give it as measured; the two are drawn concentric)."
    "    Skipped on Thermo-Light."
    "8.  Auto-hinge?  Then the spillaways, in a loop defaulting to No."))

(setq tut:*decides*
  (list
    "*   ORIENTATION.  The long overall always ends up running west to"
    "    east.  A taller-than-wide cover is turned a quarter turn, and"
    "    the corner treatments and their letters travel round with it,"
    "    so the corner you called B is still B in the report."
    "*   WHICH DIMS GO WHERE.  The cover's overalls go outside it -- 2 ft"
    "    above, 3 ft to the left.  When both outlines are drawn the"
    "    water's edge's go a third of the way INTO the water's edge."
    "    That follows from which outline it is, not which you drew first."
    "*   HOW MANY CORNER CALLOUTS.  Four identical corners get ONE, with"
    "    a Typ. suffix, at the bottom-right.  Mixed corners are called"
    "    out one by one, and the square ones share a single 90 mark."
    "    Four 90 corners get none at all."
    "*   WHICH FLATS TO DIMENSION.  Only the sides a cut corner actually"
    "    shortened, and only when the corners are not all identical."
    "*   WHICH FOAM SHEET.  A taper can carry more than one -- Standard"
    "    3-2 and 4-2 each come as 48 x 144/96 and as 49-1/2 x 102 -- and"
    "    one can work where the other will not.  Every sheet is solved"
    "    and scored before fewest pieces is even considered."
    "*   HOW MANY HINGES AND WHERE.  The fewest pieces that fit the foam"
    "    width, evenly spaced, nudged off the spillaway zones."))

(setq tut:*checks*
  (list
    "GEOMETRY"
    "  - a corner treatment too big for its own walls is re-asked, so"
    "    two treatments can never overlap and fold the perimeter"
    "  - the octagon's letters must close POSITIVE against the overalls"
    "    (S + T + S = B, S1 + V + S1 = A).  One that will not fit is"
    "    adjusted, its report row goes red, and a note says so"
    "  - a second outline that comes out at or below zero is skipped"
    "  - an octagon second outline that will not close is skipped"
    "  - an octagon whose eight sides come out equal within 1/8\" drops"
    "    its flat dimensions -- the overalls and the cut say it all"
    "  - a radius corner that came out flat gets no radius dimension"
    ""
    "HINGES"
    "  - a hinge longer than the foam length is still drawn, and the"
    "    report says by how much"
    "  - a piece count the taper does not allow is still drawn, flagged"
    "  - a hinge that ends up inside a spillaway zone is flagged"
    "  - spillaway zones that could not all be dodged are flagged"
    "  - a left/right wall spillaway cannot meet a north-south hinge, so"
    "    it is recorded but blocks nothing"
    "  - Thermo-Light has no published hinge length: a verify note"
    "  - a grade/taper not on the foam sheet falls back to 48 x 96"
    ""
    "HARDWARE (advisory, in cyan -- recommendations, not failures)"
    "  - velcro hinges, double C channel and hold down kit are each"
    "    recommended or not from the LONGEST hinge in the drawing:"
    "      Economy            all three upon request only"
    "      Standard & Deluxe  over 120 / over 108 / over 120"
    "      Ultra              over 108 / never    / over 96"
    "      Thermo-Light       always   / never    / never"
    ""
    "INPUT"
    "  - a block that is not named Spa Cover Details is read anyway,"
    "    with a warning; something that is not a block is refused"
    "  - a taper that is not on the foam sheet is re-asked"
    "  - every measurement prompt refuses zero and negative values"
    ""
    "THE DRAWING ITSELF"
    "  - your OSMODE, LUNITS, CMDECHO, CLAYER, the whole DIM set and the"
    "    current dimension style are put back on the way out -- including"
    "    after an Esc or an error mid-prompt"
    "  - the whole run is one UNDO group, so one U takes it all back"
    "  - a dimension style the drawing already defines is used exactly as"
    "    it stands; only a missing one is built"))

(setq tut:*draws*
  (list
    "COVER        the cover outline, solid"
    "POOL         the water's edge outline, dashed"
    "DIMENSION    every dimension, in standard inches (fractional to"
    "             1/8\" with the inch mark), always outside the shape"
    "TEXT         the Hinge / Velcro Hinge labels"
    "SPA-NOTES    corner letters, the mode note, the report table"
    ""
    "Freeze SPA-NOTES and what is left is the outline and its"
    "dimensions -- the drawing as the order sheet shows it."))

(defun tut:checklist ( / l)
  (tut:head "WHAT SPA ASKS YOU, IN ORDER")
  (foreach l tut:*asks* (tut:say l))
  (tut:head "WHAT SPA DECIDES FOR YOU")
  (foreach l tut:*decides* (tut:say l))
  (tut:head "WHAT SPA CHECKS")
  (foreach l tut:*checks* (tut:say l))
  (tut:head "WHAT SPA DRAWS, BY LAYER")
  (foreach l tut:*draws* (tut:say l))
  (princ "\n"))

;; The same checklist as a text sheet in the drawing, at a picked point.
(defun tut:sheet ( / p x y h l)
  (setq p (getpoint "\nPoint for the reference sheet <skip>: "))
  (if p
      (progn
        (spa:layer "SPA-NOTES" 3)
        (setq x (car p) y (cadr p) h 2.5)
        (spa:textc (list x y) (* 2.0 h)
                   (strcat "SPA " spa:*version* " -- REFERENCE") "SPA-NOTES" 7)
        (setq y (- y (* 4.0 h)))
        (foreach l (append (list "WHAT SPA ASKS YOU, IN ORDER") tut:*asks*
                           (list "" "WHAT SPA DECIDES FOR YOU") tut:*decides*
                           (list "" "WHAT SPA CHECKS") tut:*checks*
                           (list "" "WHAT SPA DRAWS, BY LAYER") tut:*draws*)
          (if (/= l "")
              (spa:text (list x y) h l "SPA-NOTES"))
          (setq y (- y (* 1.6 h))))
        (princ "\nReference sheet placed on SPA-NOTES."))))

;;; -------------------- the demo ---------------------------------------

(defun tut:demo ( / base w l cut gap corners quad cen doff th arcs
                    w2 l2 c2 org2 q2 ip2 sb2 desc n xs res nmin
                    k x ch rows stop)
  (setq base (getpoint "\nWhere shall the demo go <0,0>: ")
        spa:*base* (if base (list (car base) (cadr base)) (list 0.0 0.0)))
  (setvar "OSMODE" 0)

  ;; the same set-up the real command does
  (spa:layer "POOL" 4) (spa:layer "COVER" 6)
  (spa:layer "DIMENSION" 2) (spa:layer "SPA-NOTES" 3) (spa:layer "TEXT" 7)
  (setq spa:*dashlt* (spa:ltload "DASHED")
        spa:*dotlt*  (spa:ltload "DOT")
        spa:*valnotes* nil spa:*advice* nil spa:*turned* nil)
  (spa:setmode "Coversize")

  (setq w tut:*w* l tut:*l* cut tut:*cut* gap tut:*gap*
        corners (list (list "90" 0.0) (list "90" 0.0)
                      (list "Diagonal" cut) (list "90" 0.0))
        quad (spa:quadat (list 0.0 0.0) w l)
        cen (list (* 0.5 w) (* 0.5 l))
        doff (max 6.0 (/ (max w l) 12.0))
        th (max 1.0 (/ (max w l) 40.0)))

  (tut:head "THE DEMO")
  (tut:say "  A 140 x 110 cover with one diagonal corner, a water's edge")
  (tut:say "  3\" inside it, and Standard 4-3 foam.  Nothing is asked for --")
  (tut:say "  the measurements are canned so you can watch the drawing")
  (tut:say "  build up.  Each step explains itself before it appears.")
  (if (eq (tut:pause) 'TUT-STOP)
      (setq stop t))

  (if (not stop)
      (setq stop
        (eq 'TUT-STOP
          (tut:step "STEP 1 -- THE COVER OUTLINE"
            (list "Corners A and B (bottom) and D (top-left) are 90."
                  "Corner C (top-right) is a Diagonal with a 21\" cut FACE."
                  ""
                  "The overalls are always measured to the TRUE, sharp"
                  "corner; the treatment then cuts inward from there.  So"
                  "the cover is 140 x 110 even though the cut takes a"
                  "bite out of the top-right.")
            '(lambda () (setq arcs (spa:drawrect quad corners)))))))

  (if (not stop)
      (setq stop
        (eq 'TUT-STOP
          (tut:step "STEP 2 -- THE OVERALLS"
            (list "Across the TOP, 2 ft above.  Up the LEFT, 3 ft to the"
                  "left.  Each reads the measurement with the note"
                  "stacked under it, across the dimension line:"
                  ""
                  "                    140\""
                  "              |--------------|"
                  "                 Cover Size"
                  ""
                  "Only the overalls carry that note.")
            '(lambda ()
               (setvar "CLAYER" "DIMENSION")
               (spa:dimstylenow th)
               (spa:dimov (nth 3 quad) (nth 2 quad)
                          (list (* 0.5 w) (+ l spa:*topoff*)))
               (spa:dimov (nth 0 quad) (nth 3 quad)
                          (list (- 0.0 spa:*dimoff*) (* 0.5 l))))))))

  (if (not stop)
      (setq stop
        (eq 'TUT-STOP
          (tut:step "STEP 3 -- THE FLATS"
            (list "The cut at corner C shortened the TOP and the RIGHT, so"
                  "each gets its remaining straight run dimensioned,"
                  "inboard of the overalls.  The bottom and left were not"
                  "shortened, so they get nothing."
                  ""
                  "Had all four corners matched, there would be no flats"
                  "at all -- the overalls and one Typ. callout would be"
                  "the whole drawing.")
            '(lambda ()
               (spa:dimalg (spa:cornerpoint quad corners 1 'next)
                           (spa:cornerpoint quad corners 2 'prev)
                           (spa:outoff (nth 1 quad) (nth 2 quad) cen
                                       spa:*flatoff*) nil)
               (spa:dimalg (spa:cornerpoint quad corners 2 'next)
                           (spa:cornerpoint quad corners 3 'prev)
                           (spa:outoff (nth 2 quad) (nth 3 quad) cen
                                       spa:*flatoff*) nil))))))

  (if (not stop)
      (setq stop
        (eq 'TUT-STOP
          (tut:step "STEP 4 -- THE CORNER CALLOUTS"
            (list "The cut face is dimensioned across itself, outside the"
                  "corner on its 45-degree line.  The three square corners"
                  "share ONE mark -- a circled corner point with a 90"
                  "leader, Typ. because there is more than one."
                  ""
                  "A radius corner would get R12\" instead, read from"
                  "outside the arc.  Corner callouts never carry the"
                  "Cover Size note -- they are corners, not overalls.")
            '(lambda () (spa:dimcorners quad corners arcs cen doff))))))

  (if (not stop)
      (setq stop
        (eq 'TUT-STOP
          (tut:step "STEP 5 -- THE WATER'S EDGE"
            (list "Offset 3\" INWARD, because the cover is always the"
                  "larger of the two.  This is a true parallel offset, so"
                  "the corner moves with it: the 21\" cut face shrinks by"
                  "3 x (2*root2 - 2) = 2.49\", to 18.51\"."
                  ""
                  "Dashed, on the POOL layer.  Its own overalls go a third"
                  "of the way INTO it, hooked to points on the dimension"
                  "line so the arrows land on the outline.")
            '(lambda ()
               (setq w2 (- w (* 2.0 gap))
                     l2 (- l (* 2.0 gap))
                     c2 (spa:offcorners corners (- gap))
                     org2 (spa:orgfor cen w2 l2)
                     q2 (spa:quadat org2 w2 l2)
                     sb2 (spa:maxsetback c2)
                     ip2 (spa:insidepts (car org2) (+ (car org2) w2)
                                        (cadr org2) (+ (cadr org2) l2)
                                        sb2 sb2))
               (spa:setmode "Watersedge")
               (spa:drawrect q2 c2)
               (setvar "CLAYER" "DIMENSION")
               (spa:dimstylenow th)
               (spa:dimoveralls nil (nth 0 ip2) (nth 1 ip2)
                                (nth 2 ip2) (nth 3 ip2) 0.0 l)
               (spa:setmode "Coversize"))))))

  (if (not stop)
      (setq stop
        (eq 'TUT-STOP
          (tut:step "STEP 6 -- THE OVERLAP"
            (list "How far the cover laps the water's edge, at the bottom."
                  "The lap itself is far too small to hold its text, so"
                  "the note is parked under the cover with a leader.")
            '(lambda ()
               (spa:dimstyle spa:*ds-cover* th 1.0)
               (spa:dimlap (* 0.5 w) 0.0 (cadr org2)))))))

  (if (not stop)
      (setq stop
        (eq 'TUT-STOP
          (tut:step "STEP 7 -- THE HINGES"
            (list "Standard 4-3 foam: 48\" wide, 144\" long, 2 to 4 pieces."
                  ""
                  "140\" / 48\" needs 3 pieces, so 2 hinges, evenly spaced."
                  "The LEFTMOST is the fold hinge -- dashed, labelled"
                  "Hinge.  The rest are Velcro Hinge, ByLayer.  Labels go"
                  "on the TEXT layer."
                  ""
                  "Each hinge runs the full 110\", well inside the 144\""
                  "foam length.  Had a spillaway been declared, the even"
                  "stations would have been nudged off it.")
            '(lambda ()
               (setvar "CLAYER" "DIMENSION")
               (setq desc (list "RECT" quad corners)
                     nmin (max 2 (spa:ceilv (/ w tut:*fw*)))
                     res (spa:hsolve 0.0 w tut:*fw* nil nmin)
                     n (car res) xs (cadr res) k 0)
               (foreach x xs
                 (setq ch (spa:chordat desc x))
                 (if ch
                     (progn
                       (if (= k 0)
                           (spa:line (list x (car ch)) (list x (cadr ch))
                                     "COVER" (spa:hdash))
                           (spa:line (list x (car ch)) (list x (cadr ch))
                                     "COVER" nil))
                       (spa:htext (list (- x (* 2.0 th))
                                        (* 0.5 (+ (car ch) (cadr ch))))
                                  (* 1.2 th)
                                  (if (= k 0) "Hinge" "Velcro Hinge"))))
                 (setq k (1+ k))))))))

  (if (not stop)
      (tut:step "STEP 8 -- THE REPORT"
        (list "Target / actual / delta for everything that was measured,"
              "off to the right.  Problems print under it in RED --"
              "adjusted octagon letters, a hinge over the foam length, a"
              "piece count the taper does not allow."
              ""
              "Recommendations print in CYAN.  This 110\" hinge is over"
              "108\", so Standard & Deluxe calls for a double C channel."
              ""
              "The whole run is one UNDO group: a single U clears it.")
        '(lambda ()
           (spa:advise "DOUBLE C CHANNEL: YES - hinge 110.0 over 108")
           (spa:advise "VELCRO HINGES: no - hinge 110.0 not over 120")
           (spa:advise "HOLD DOWN KIT: no - hinge 110.0 not over 120")
           (spa:modenote 0.0 (- 0.0 (* 1.4 spa:*dimoff*)) th)
           (setq rows (list (list "OVERALL ACROSS (A-B)" w w)
                            (list "OVERALL UP (A-D)" l l)
                            (list "CORNER C DIAGONAL" cut cut)
                            (list "WATER'S EDGE ACROSS" w2 w2)
                            (list "WATER'S EDGE UP" l2 l2)
                            (list "PIECES (STD 4-3)" nil (float n))
                            (list "FOAM WIDTH MAX" tut:*fw* (/ w n))
                            (list "FOAM LENGTH MAX" tut:*fl* l)))
           (spa:report rows nil (+ w spa:*dimoff*) l th "SPA-NOTES"))))

  (tut:head "THAT IS THE WHOLE THING")
  (tut:say "  Type SPA to do it for real.  The grey guide will show you")
  (tut:say "  which measurement is being asked for, and Back at any")
  (tut:say "  prompt re-asks the previous one.")
  (princ "\n"))

;;; -------------------- the command ------------------------------------

(defun c:TUTORIALSPA ( / *error* what)

  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg t) "function cancelled")
             (/= (strcase msg t) "quit / exit abort"))
        (princ (strcat "\nTUTORIALSPA error: " msg)))
    (spa:sysrestore)
    (spa:undoend)
    (if *pop-error-mode* (*pop-error-mode*))
    (princ))

  (if (null spa:*version*)
      (progn
        (princ "\nLoad SPA.LSP first -- the tutorial drives its own drawing")
        (princ "\nfunctions, so it cannot run without it.")
        (princ))
      (progn
        (if *push-error-using-command* (*push-error-using-command*))
        (princ (strcat "\nSPA " spa:*version* " -- tutorial " tut:*version*))
        (initget "Checklist Demo Both")
        (setq what (getkword "\nShow me [Checklist/Demo/Both] <Both>: "))
        (if (null what) (setq what "Both"))
        (spa:syssave)
        (setvar "CMDECHO" 0)
        (spa:undobegin)
        (setvar "LUNITS" 4)
        (if (member what '("Checklist" "Both"))
            (progn (tut:checklist) (tut:sheet)))
        (if (member what '("Demo" "Both"))
            (tut:demo))
        (spa:undoend)
        (spa:sysrestore)
        (if *pop-error-mode* (*pop-error-mode*))
        (princ))))

(princ (strcat "\nTUTORIALSPA " tut:*version*
               " loaded.  Type TUTORIALSPA to walk through SPA."))
(princ)
