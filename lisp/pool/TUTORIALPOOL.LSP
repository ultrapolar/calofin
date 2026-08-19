;;; ===================================================================
;;;  TUTORIALPOOL.LSP -- guided walkthrough for POOL.LSP
;;;
;;;  Command:  TUTORIALPOOL
;;;
;;;  A paced, captioned tour of how POOL.LSP works: what it asks, why,
;;;  and what the drawing looks like at each stage.  Each topic prints
;;;  a short explanation (and, where it matters, a full checklist of
;;;  what the routine actually verifies), draws a small illustrative
;;;  example, and waits for you to read it -- press ENTER to move on,
;;;  or type X then ENTER to stop early.
;;;
;;;  This is a WALKTHROUGH, not a reference sheet: POOLDEMO draws one
;;;  example of every shape and bottom side by side for comparison;
;;;  this command draws a handful of focused examples, one concept at
;;;  a time, with the reasoning spelled out next to each.
;;;
;;;  Load POOL.LSP first (this file uses its geometry helpers), then
;;;  this file.  Safe to run in a scratch drawing at any time -- it
;;;  draws on the same layers POOL uses.
;;;
;;;  This file ships twice under two names with IDENTICAL contents:
;;;      TUTORIALPOOL.LSP                 the static name
;;;      TUTORIALPOOL_MMDDYY_REV##.LSP    named for its revision
;;; ===================================================================

(setq tutorial:*version* "081926 REV01")

(setq tutorial:*colw* 620.0)            ; horizontal spacing between topics

;; Caption above a topic's drawing (local coords -- pool:*base* is set
;; to that topic's origin before this is called).
(defun tutorial:cap (txt)
  (pool:text (list 0.0 260.0) 14.0 txt "POOL-NOTES"))

;; One bulleted line, wrapped to keep the command line readable.
(defun tutorial:bullet (txt)
  (princ (strcat "\n  - " txt)))

;; Frame this topic's drawing: lo/hi are LOCAL coordinates (pool:wp
;; applies the topic's own pool:*base* automatically).
(defun tutorial:frame (lo hi)
  (command "_.ZOOM" "_Window" (pool:wp lo) (pool:wp hi)))

;; Wait for the user to read the topic before moving on.  Returns NIL
;; if they typed X (quit early); T otherwise.  Scriptable: any script
;; value maps to a plain Enter except one starting with X/x.
(defun tutorial:pause ( / v)
  (setq v (getstring "\nPress ENTER for the next topic (X then ENTER to stop here): "))
  (/= (strcase (substr v 1 1)) "X"))

;;; -------------------- topic 1: welcome --------------------------------

(defun tutorial:c1 ()
  (princ "\n\n=== 1. WELCOME ===")
  (princ "\nPOOL.LSP lays out an as-built swimming-pool plan from real field")
  (princ "\nmeasurements: perimeter, cross dims, corner treatments, the pool")
  (princ "\nbottom (hopper), dimensions, and a target/actual/delta report --")
  (princ "\nall from typed numbers, no drawing by hand.")
  (princ "\n\nNine shapes: Rectangle, Grecian, ROman, L, LAzyl, Oval, OCtagon,")
  (princ "\nROUnd, MUtt (a rectangle body with independently chosen deep and")
  (princ "\nshallow ends).")
  (princ "\n\nThree commands:")
  (tutorial:bullet "POOL          -- run the real thing")
  (tutorial:bullet "POOLDEMO      -- one hardcoded example of every shape and bottom, side by side (install check)")
  (tutorial:bullet "TUTORIALPOOL  -- this walkthrough")
  (princ "\n\nDistances may be typed as 25'6\", 25'-6-1/2\" or 25'6.5, as well")
  (princ "\nas plain inches (306.5) -- POOL switches units for you while it runs.")
  (princ))

;;; -------------------- topic 2: guided input ----------------------------

(defun tutorial:c2 ( / a b c d)
  (tutorial:cap "2  THE GUIDED INPUT")
  (setq a (list 0.0 0.0) b (list 300.0 0.0)
        c (list 300.0 180.0) d (list 0.0 180.0))
  (pool:line a b "POOL-NOTES")
  (pool:setcol (entlast) pool:*pv-col*)
  (pool:line b c "POOL-NOTES")
  (pool:setcol (entlast) pool:*pv-col*)
  (pool:line c d "POOL-NOTES")
  (pool:setcol (entlast) pool:*pv-col*)
  ;; the side currently "being asked about" -- drawn RED, same colour
  ;; and convention the real guide uses while prompting
  (pool:line d a "POOL-NOTES")
  (pool:setcol (entlast) pool:*hi-col*)
  (pool:text (list -14.0 0.0) 10.0 "A" "POOL-NOTES")
  (pool:text (list 300.0 -18.0) 10.0 "B" "POOL-NOTES")
  (pool:text (list 314.0 180.0) 10.0 "C" "POOL-NOTES")
  (pool:text (list -14.0 198.0) 10.0 "D" "POOL-NOTES")
  (pool:textc (list 0.0 90.0) 10.0 "<- being asked now" "POOL-NOTES" 1)
  (tutorial:frame (list -40.0 -40.0) (list 400.0 300.0))
  (princ "\n\n=== 2. THE GUIDED INPUT ===")
  (princ "\nAs soon as you pick the shape, a gray guide (like the three")
  (princ "\nsides above) is drawn at the base point and the view zooms to it.")
  (tutorial:bullet "The element being asked about right now turns RED (the D-A side, here) -- there is never any doubt which measurement you are answering.")
  (tutorial:bullet "When a prompt names corners (a side, a cross dim, a corner treatment) the corner LETTERS turn red too.")
  (tutorial:bullet "Object snaps stay LIVE the whole time you are answering, including the very first base-point pick, so you can snap to the real site.")
  (tutorial:bullet "Back (type B -- or U for Undo, its unlisted synonym) re-asks the previous question, from ANYWHERE in the process, right back to the very first one.")
  (tutorial:bullet "Your own snap settings come back exactly as they were once POOL finishes, even if you cancel or it hits an error.")
  (princ))

;;; -------------------- topic 3: in-square vs out-of-square -------------

(defun tutorial:c3 ( / q1 q2)
  (tutorial:cap "3  IN-SQUARE vs OUT-OF-SQUARE")
  (setq q1 (list (list 0.0 0.0) (list 240.0 0.0)
                 (list 240.0 140.0) (list 0.0 140.0)))
  (pool:drawrect q1 pool:*sq4*)
  (pool:text (list 20.0 -20.0) 10.0 "IN-SQUARE: built true, no diagonals" "POOL-NOTES")
  (setq q2 (list (list 320.0 4.0) (list 562.0 0.0)
                 (list 558.0 138.0) (list 322.0 142.0)))
  (pool:drawrect q2 pool:*sq4*)
  (pool:lined (nth 0 q2) (nth 2 q2))
  (pool:lined (nth 1 q2) (nth 3 q2))
  (pool:text (list 330.0 -20.0) 10.0 "OUT-OF-SQUARE: cross dims taped" "POOL-NOTES")
  (tutorial:frame (list -40.0 -40.0) (list 600.0 300.0))
  (princ "\n\n=== 3. IN-SQUARE vs OUT-OF-SQUARE ===")
  (princ "\nAsked FIRST, before the shape itself.")
  (tutorial:bullet "In-square: built true to the side/end lengths you give -- no diagonals asked, no diagonals drawn.")
  (tutorial:bullet "Out-of-square: perimeter first, THEN cross dims (dashed above) -- the guide draws no diagonals until every side is in.")
  (princ "\nHow the body is fit to what does not quite agree (tapes always")
  (princ "\ncarry a little human error):")
  (tutorial:bullet "1. Sides held EXACTLY true; the body is skewed to bring the cross dims as close as possible. Within 2\"? Done.")
  (tutorial:bullet "2. Otherwise the sides may flex inside their own +/-1\" band to pull the cross dims in.")
  (tutorial:bullet "3. Still can't be met? Sides held true, cross dims as close as possible, and CROSS DIMS FAILED is written in red under the report.")
  (princ))

;;; -------------------- topic 4: corner treatments -----------------------

(defun tutorial:c4 ( / q cs arcs cen)
  (tutorial:cap "4  CORNER TREATMENTS")
  (setq q (list (list 0.0 0.0) (list 300.0 0.0)
               (list 300.0 180.0) (list 0.0 180.0))
        cs (list (list "Rounded" 30.0) (list "Diag" 40.0)
                 (list "Square" 0.0) (list "Square" 0.0))
        cen (pool:v* (pool:v+ (pool:v+ (nth 0 q) (nth 1 q))
                              (pool:v+ (nth 2 q) (nth 3 q))) 0.25)
        arcs (pool:drawrect q cs))
  (setvar "CLAYER" "DIMENSION")
  (pool:dimcorner1 (pool:cornerends (nth 0 q) (nth 3 q) (nth 1 q) "Rounded" 30.0 nil)
                   "Rounded" (nth 0 arcs)
                   (pool:unit (pool:v- (nth 0 q) cen)) 20.0 "")
  (pool:dimcorner1 (pool:cornerends (nth 1 q) (nth 0 q) (nth 2 q) "Diag" 40.0 nil)
                   "Diag" (nth 1 arcs)
                   (pool:unit (pool:v- (nth 1 q) cen)) 20.0 "")
  (setvar "CLAYER" "POOL")
  (tutorial:frame (list -40.0 -40.0) (list 400.0 300.0))
  (princ "\n\n=== 4. CORNER TREATMENTS ===")
  (princ "\nRectangle, and now L/Lazy L, corners can each be:")
  (tutorial:bullet "Square  -- the plain sharp corner (nothing drawn).")
  (tutorial:bullet "Rounded -- you give the RADIUS; a fillet arc is drawn (bottom-left, above).")
  (tutorial:bullet "Diag    -- you give the CHAMFER FACE length; a straight cut is drawn (bottom-right, above).")
  (princ "\nSide lengths always read to the TRUE (sharp) corner -- the")
  (princ "\ntreatment cuts inward from there, so a measured wall length never")
  (princ "\nchanges because you added a radius.")
  (tutorial:bullet "In-square: all four (or five, for L/Lazy L) corners get ONE answer, with a single \"Typ.\" callout in the drawing.")
  (tutorial:bullet "Out-of-square: every corner is asked individually -- but if all four answers come back the same type and size, they collapse to that same single \"Typ.\" callout instead of four separate dims.")
  (tutorial:bullet "Sizes are capped so two treatments on the same wall can never overlap and fold it -- too-large answers are re-asked with the max shown.")
  (tutorial:bullet "L/Lazy L: the five OUTER corners take one answer, the INNER corner (E) is asked separately since it's usually different (Enter reuses the outer answer).")
  (tutorial:bullet "The pool bottom's hopper ties connect to the ACTUAL corner cut on the deep-end wall, not the sharp corner behind it -- see topic 5.")
  (princ))

;;; -------------------- topic 5: the hopper ------------------------------

(defun tutorial:c5 ( / q gg tl)
  (tutorial:cap "5  THE POOL BOTTOM (HOPPER)")
  (setq q (list (list 0.0 0.0) (list 360.0 0.0)
               (list 360.0 200.0) (list 0.0 200.0)))
  (pool:drawrect q pool:*sq4*)
  (setq gg (pool:hopcalc q pool:*sq4* 50.0 90.0 120.0 40.0 40.0))
  (pool:hopdraw gg "POOL-NOTES" t)
  (setvar "CLAYER" "DIMENSION")
  (foreach tl (list (list 'pl 'phl nil) (list 'phl 'phr nil)
                    (list 'phr 'pbrk nil) (list 'pbrk 'pr nil)
                    (list 'pht 'pt t) (list 'phb 'pht t) (list 'pb 'phb t))
    (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                 (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                    (cadr (assoc (cadr tl) gg)))
                          (if (caddr tl) (cadr (assoc 'voff gg)) (list 0.0 0.0)))))
  (setvar "CLAYER" "POOL")
  (tutorial:frame (list -40.0 -40.0) (list 460.0 260.0))
  (princ "\n\n=== 5. THE POOL BOTTOM (HOPPER) ===")
  (princ "\nOffered after the perimeter is drawn and dimensioned.  The")
  (princ "\nprimary letters are OFFSETS from the perimeter:")
  (tutorial:bullet "H / G / F / E along the main run: left end -> hopper start (H), hopper length (G), hopper -> slope break (F), break -> right end (E).")
  (tutorial:bullet "M / L / K across the width: top -> hopper (M), hopper width (L), hopper -> bottom (K).")
  (tutorial:bullet "F and L are redundant with the others and reported as CHECKS, with their delta against the perimeter.")
  (princ "\nEvery other bottom is this SAME chain, just with letters pinned:")
  (tutorial:bullet "Wedge    -- G=0, E=0 (deep line at H, floor rises all the way to the far wall)")
  (tutorial:bullet "SLope    -- G=0 (deep line at H, rises to a full-width break, then flat)")
  (tutorial:bullet "MOdflat  -- E=0 (one flat pad, sloping up to every wall, no shallow flat)")
  (tutorial:bullet "SHallow  -- full hopper, but the shallow floor slopes from C2 up to C")
  (tutorial:bullet "Sport    -- the symmetric full-width bottom (E2/F2/G/F1/E1, no offsets)")
  (princ "\nGrecian/Octagon SIX-sided hoppers cut the deep pad's corners two")
  (princ "\nways: Offsets (every hopper line parallel to its wall, cut faces")
  (princ "\nparallel to the pool's own corner cuts) or Letters (the sheet's")
  (princ "\nW/X/L/L1 -- W is the flat, L1 the left edge, the faces just")
  (princ "\nconnect the corners and need not be parallel to anything).")
  (princ))

;;; -------------------- topic 6: validation & safety checks --------------

(defun tutorial:c6 ( / q cv vals fixed gg rows k tl)
  (tutorial:cap "6  VALIDATION -- G floored to 1', F pays, both RED")
  (setq q (list (list 0.0 0.0) (list 360.0 0.0)
               (list 360.0 180.0) (list 0.0 180.0)))
  (pool:drawrect q pool:*sq4*)
  ;; H 50 + G -30 + F 300 + E 40 cannot close on a 360-wide body:
  ;; G floors at a positive minimum and F, the largest OTHER member,
  ;; pays the difference -- exactly what pool:chainval does for real
  (setq cv (pool:chainval (list 50.0 -30.0 300.0 40.0) 360.0)
        vals (car cv) fixed (cadr cv)
        gg (pool:hopcalc q pool:*sq4* (nth 0 vals) (nth 1 vals) (nth 3 vals) 40.0 40.0))
  (pool:hopdraw gg "POOL" t)
  (setvar "CLAYER" "DIMENSION")
  (setq k 0)
  (foreach tl (list (list 'pl 'phl) (list 'phl 'phr)
                    (list 'phr 'pbrk) (list 'pbrk 'pr))
    (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                 (pool:mid (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))))
    (if (member k fixed) (pool:dimred))
    (setq k (1+ k)))
  (setvar "CLAYER" "POOL")
  (setq rows (list
    (pool:vrow "HOP H" 50.0 (nth 0 vals) 0 fixed)
    (pool:vrow "HOP G" -30.0 (nth 1 vals) 1 fixed)
    (pool:vrow "HOP F" 300.0 (nth 2 vals) 2 fixed)
    (pool:vrow "HOP E" 40.0 (nth 3 vals) 3 fixed)))
  (pool:report rows (list "BOTTOM LENGTHS FAILED - G/F ADJUSTED, VERIFY")
               420.0 180.0 8.0 "POOL-NOTES")
  (tutorial:frame (list -40.0 -40.0) (list 900.0 260.0))
  (princ "\n\n=== 6. VALIDATION & SAFETY CHECKS ===")
  (princ "\nField numbers do not always close.  POOL never just crashes or")
  (princ "\nsilently draws something wrong -- every check below adjusts,")
  (princ "\nflags RED (both in the dims and the report table), and writes a")
  (princ "\nplain-English note under the report so you know exactly what to")
  (princ "\nverify on site.  The example above: G resolved negative, so it's")
  (princ "\nfloored to a positive minimum and F -- the largest OTHER member")
  (princ "\n-- gives up the difference.")
  (princ "\n\nEverything POOL.LSP checks:")
  (tutorial:bullet "Negative chain members (H/G/F/E or M/L/K) are floored positive; the largest other member in the same chain pays the difference; both go red.")
  (tutorial:bullet "Grecian/Roman overall-sheet letters (S+T+S=B, S1+V+S1=A) must close positive -- warned BEFORE the bottom is even asked, reported red after.")
  (tutorial:bullet "Grecian/Octagon overall sheet: a measured WALL letter (T, V) is held true over its CORNER letter (S, S1) when the two disagree -- a wall is far easier to tape accurately than a virtual corner.")
  (tutorial:bullet "Corner-treatment sizes are capped so two treatments can never overlap and fold a wall.")
  (tutorial:bullet "Rectangle out-of-square Sport/SHallow depths: D must beat C, and C2 must land between C and D -- re-asked live until it does.")
  (tutorial:bullet "Oval/Roman end radius vs. width/offset (R3+W=G, or S from R and V) is checked and flagged if it does not close within tolerance.")
  (tutorial:bullet "SIX-sided hopper: W can't exceed G, L1 can't exceed L (floored + flagged); X is checked against the derived diagonal.")
  (tutorial:bullet "Cross dims: ordinary diagonals fit within +/-2\"; a Grecian tip-to-tip width or body-end chord is held like a WALL instead, within +/-1\" -- CROSS DIMS FAILED if neither can be met.")
  (tutorial:bullet "In-square lazy L: A-B stays exactly parallel to E-F, and B-C to D-E; any closure error lands in the E-F/F-A lengths, never in bent angles.")
  (tutorial:bullet "Back works from anywhere, one question (or one stage) at a time, all the way to the very first prompt.")
  (princ))

;;; -------------------- topic 7: dimension styles -------------------------

(defun tutorial:c7 ()
  (princ "\n\n=== 7. DIMENSION STYLES ===")
  (princ "\nThree named dim styles are used automatically WHEN YOUR DRAWING")
  (princ "\nDEFINES THEM -- the previous style always comes back right after,")
  (princ "\nand if a style is missing, POOL just quietly uses whatever style")
  (princ "\nwas already current (a one-time note for STANDARD INCHES, then")
  (princ "\nit stays quiet for the rest of the run).")
  (tutorial:bullet "CROSS DIMENSIONS -- every cross dim, on every shape. Pure ByLayer: no per-entity color/linetype/lineweight override, so the look comes entirely from that style and the DIMENSION layer.")
  (tutorial:bullet "STANDARD INCHES -- any dimension measuring UNDER 2' (24\"): corner radii, chamfer faces, short hopper offsets, end radii, profile depths. A dimension of EXACTLY 2' stays in the current style, not inches.")
  (tutorial:bullet "SIDE STANDARD -- the secondary sheet letters (Grecian/Octagon S/T/S1/V, Roman and Oval end radii, L wing and step sides, the six-sided hopper's W/L1/X). Wins over the under-24\" rule: a 19\" S1 stays in SIDE STANDARD, not inches.")
  (princ "\nThe styles nest correctly -- a small dimension drawn inside the")
  (princ "\ncross-dim block returns to CROSS DIMENSIONS afterward, not to")
  (princ "\nwhatever was current before the block opened.")
  (princ))

;;; -------------------- topic 8: report table & mirroring -----------------

(defun tutorial:c8 ( / rows elast a b c d e f)
  (tutorial:cap "8  THE REPORT TABLE, AND MIRRORING")
  (setq rows (list (list "SIDE A-B" 300.0 300.0)
                   (append (list "SIDE B-C" 180.0 181.4) (list t))
                   (list "HOP H" 50.0 50.0)))
  (pool:report rows nil 0.0 60.0 8.0 "POOL-NOTES")
  (princ "\n\n=== 8. THE REPORT TABLE, AND MIRRORING ===")
  (princ "\nEvery measurement you gave gets one row: TARGET (what you typed),")
  (princ "\nACTUAL (what was drawn) and DELTA.  A red row (like SIDE B-C,")
  (princ "\nabove) means a validator adjusted that value -- always double")
  (princ "\ncheck a red row against the site.  Failure notes print big and")
  (princ "\nred underneath the whole table.")
  (princ "\n\nWhen the drawing's units are Architectural or Engineering the")
  (princ "\nTARGET and ACTUAL columns read in feet-and-inches (DELTA stays")
  (princ "\nsigned decimal inches), and a small mini-model of the perimeter")
  (princ "\nis drawn beside the report carrying the measurement letters, so")
  (princ "\nthe letters never crowd the drawing itself.")
  (princ "\n\nL and Lazy L pools also offer to MIRROR the finished pool once")
  (princ "\nevery dimension is in -- the plan flips TOP-TO-BOTTOM about the")
  (princ "\npool's horizontal centreline (perimeter, dimensions AND hopper")
  (princ "\ntogether, text kept readable), so the wing swaps sides while the")
  (princ "\ndeep end stays on the left; the report itself is written")
  (princ "\nafterward, unmirrored.")
  (setq elast (entlast)
        a (list 480.0 0.0) b (list 780.0 0.0) c (list 780.0 240.0)
        d (list 630.0 240.0) e (list 630.0 120.0) f (list 480.0 120.0))
  (pool:line a b "POOL") (pool:line b c "POOL") (pool:line c d "POOL")
  (pool:line d e "POOL") (pool:line e f "POOL") (pool:line f a "POOL")
  (pool:mirrory elast (cadr (pool:wp (list 0.0 120.0))))
  (tutorial:frame (list -40.0 -40.0) (list 1120.0 300.0))
  (princ))

;;; -------------------- topic 9: wrap-up -----------------------------------

(defun tutorial:c9 ()
  (princ "\n\n=== 9. THAT'S THE TOUR ===")
  (princ (strcat "\nLoaded version: POOL " pool:*version*
                 " -- tutorial " tutorial:*version*))
  (princ "\nType POOLVER any time to check what's loaded in a drawing --")
  (princ "\nhandy for comparing what other people have in their stacks.")
  (princ "\n\nFull details on every shape, bottom, corner treatment, and")
  (princ "\nvalidation rule live in lisp/pool/README.md.")
  (princ "\n\nReady? Type POOL to lay out a real pool, or POOLDEMO for a")
  (princ "\nside-by-side reference sheet of every shape and bottom.")
  (princ))

;;; -------------------- the command ---------------------------------------

(defun c:TUTORIALPOOL ( / *error*)

  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg t) "function cancelled")
             (/= (strcase msg t) "quit / exit abort"))
        (princ (strcat "\nTUTORIALPOOL error: " msg)))
    (pool:sysrestore)
    (pool:undoend)
    (if *pop-error-mode* (*pop-error-mode*))
    (princ))

  (if (null pool:*version*)
      (progn
        (princ "\nLoad POOL.LSP first -- the tutorial draws with its geometry")
        (princ "\nhelpers, so it cannot run without it.")
        (princ))
      (tutorial:run))
  (princ))

(defun tutorial:run ( / topics textonly k org going fn)
  (if *push-error-using-command* (*push-error-using-command*))
  (pool:syssave)
  (setq pool:*valnotes* nil
        pool:*smallwarned* nil)
  (setvar "CMDECHO" 0)
  (pool:undobegin)
  (setvar "OSMODE" 0)
  (setvar "LUNITS" 4)

  (pool:layer "POOL" 4)
  (pool:layer "DIMENSION" 2)
  (pool:layer "POOL-NOTES" 3)
  (setq pool:*dashlt* (pool:ltload "DASHED")
        pool:*dotlt* (pool:ltload "DOT"))
  (setvar "CLAYER" "POOL")

  ;; topics 1, 7 and 9 are text-only -- no drawing, no origin needed
  (setq topics (list 'tutorial:c1 'tutorial:c2 'tutorial:c3 'tutorial:c4
                     'tutorial:c5 'tutorial:c6 'tutorial:c7 'tutorial:c8
                     'tutorial:c9)
        textonly (list 'tutorial:c1 'tutorial:c7 'tutorial:c9)
        k 0 going t)
  (foreach fn topics
    (if going
        (progn
          (if (member fn textonly)
              (apply fn nil)
              (progn
                (setq org (list (* tutorial:*colw* k) 0.0)
                      pool:*base* org)
                (apply fn nil)))
          (if (/= fn 'tutorial:c9) (setq going (tutorial:pause)))))
    (setq k (1+ k)))

  (command "_.ZOOM" "_Extents")
  (pool:undoend)
  (pool:sysrestore)
  (if *pop-error-mode* (*pop-error-mode*))
  (princ))

(princ (strcat "\nTUTORIALPOOL " tutorial:*version*
               " loaded.  Type TUTORIALPOOL for a guided walkthrough of POOL.LSP."))
(princ)
