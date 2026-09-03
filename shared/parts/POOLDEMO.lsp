;;; ===================================================================
;;;  POOLDEMO.LSP -- install check + reference sheet for POOL.LSP
;;; ===================================================================
;;;
;;;  Type POOLDEMO to draw one canned example of every shape, every
;;;  pool bottom and every drawing feature POOL.LSP can produce, from
;;;  hardcoded numbers -- no prompts.  It answers, in your own AutoCAD
;;;  and in about a second:
;;;
;;;    * did POOL.LSP actually load?
;;;    * do the layers and the dashed/dotted linetypes come out right?
;;;    * do the dimension commands work in this drawing's dim style?
;;;    * do arcs, text, the report table and the red failure marking
;;;      all render as intended?
;;;
;;;  It is also a reference sheet: every shape and bottom side by side,
;;;  captioned, at real-world sizes.
;;;
;;;  Nothing here prompts, so it is safe to run in a scratch drawing at
;;;  any time.  It draws on the same layers POOL uses -- run it in a
;;;  NEW drawing, not over live work.
;;;
;;;  Load POOL.LSP first (POOLDEMO uses its geometry), then this file.
;;;
;;;  This file ships twice under two names with IDENTICAL contents:
;;;      POOLDEMO.LSP                 the static name
;;;      POOLDEMO_MMDDYY_REV##.LSP    named for its revision
;;; ===================================================================

;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;

(setq pooldemo:*version* "090126 REV07")

(setq pooldemo:*colw* 760.0)            ; grid cell width
(setq pooldemo:*rowh* 900.0)            ; grid cell height

;; Caption above a cell.
(defun pooldemo:cap (org txt)
  (setq pool:*base* org)
  (pool:text (list 0.0 470.0) 22.0 txt "POOL-NOTES"))

;; Standard-hopper bottom inside quad, in a named style, with its
;; profile when the style has one.  Mirrors what pool:hopnormal draws
;; once the prompting is done.
(defun pooldemo:bottom (quad corners style h g f e m k wh dp c2 / gg sp toth)
  (setq sp (pool:btmspec style)
        toth (distance (car quad) (cadr quad))
        gg (pool:hopcalc quad corners h g e m k))
  (pool:hopdraw gg "POOL" t)
  (if (caddr sp)
      (pool:profdraw 0.0 -150.0 toth wh
                     (pool:btmbrks style h g f wh dp c2) "POOL" nil))
  gg)

;; Chain dims for a hopper, red on the flagged indices.
(defun pooldemo:hopdims (gg fixed / tl k)
  (setvar "CLAYER" "DIMENSION")
  (setq k 0)
  (foreach tl (list (list 'pl 'phl nil) (list 'phl 'phr nil)
                    (list 'phr 'pbrk nil) (list 'pbrk 'pr nil)
                    (list 'pht 'pt t) (list 'phb 'pht t) (list 'pb 'phb t))
    (if (> (distance (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg)))
           1.0e-6)
        (progn
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (cal:v+ (cal:mid (cadr (assoc (car tl) gg))
                                          (cadr (assoc (cadr tl) gg)))
                                (if (caddr tl) (cadr (assoc 'voff gg))
                                    (list 0.0 0.0))))
          (if (member k fixed) (pool:dimred))))
    (setq k (1+ k)))
  (setvar "CLAYER" "POOL"))

;;; -------------------- the cells --------------------------------------

;; 1. in-square rectangle, square corners, standard hopper
(defun pooldemo:c1 (org / q sq gg)
  (pooldemo:cap org "1  RECTANGLE in-square / square corners / NORMAL hopper")
  (setq q (list (list 0.0 0.0) (list 480.0 0.0) (list 480.0 240.0) (list 0.0 240.0))
        sq pool:*sq4*)
  (pool:drawrect q sq)
  (setvar "CLAYER" "DIMENSION")
  (pool:dimrot (nth 3 q) (nth 2 q) (angle (nth 3 q) (nth 2 q))
               (list 240.0 300.0))
  (pool:dimrot (nth 0 q) (nth 3 q) (angle (nth 0 q) (nth 3 q))
               (list -60.0 120.0))
  (setvar "CLAYER" "POOL")
  (setq gg (pooldemo:bottom q sq "Normal" 60.0 90.0 210.0 120.0 60.0 60.0
                            nil nil nil))
  (pooldemo:hopdims gg nil))

;; 2. out-of-square rectangle, radius corners, WEDGE bottom + profile
(defun pooldemo:c2 (org / q cs arcs cen gg od)
  (pooldemo:cap org "2  RECTANGLE out-of-square / radius corners / WEDGE + section")
  (setq q (list (list 0.0 0.0) (list 482.0 3.0) (list 479.0 243.0) (list 2.0 239.0))
        cs (list (list "Radius" 36.0) (list "Radius" 36.0)
                 (list "Radius" 36.0) (list "Radius" 36.0))
        cen (cal:v* (cal:v+ (cal:v+ (nth 0 q) (nth 1 q))
                              (cal:v+ (nth 2 q) (nth 3 q))) 0.25)
        arcs (pool:drawrect q cs))
  (setvar "CLAYER" "DIMENSION")
  (setq od (pool:dimxbegin))
  (pool:dimalg (nth 0 q) (nth 2 q) (cal:mid (nth 0 q) (nth 2 q)))
  (pool:dimxend od)
  (pool:dimcorners q cs arcs cen 30.0)
  (setvar "CLAYER" "POOL")
  (setq gg (pooldemo:bottom q cs "Wedge" 60.0 0.0 420.0 0.0 60.0 60.0
                            40.0 60.0 40.0))
  (pooldemo:hopdims gg nil))

;; 3. oval, SPORT bottom (full-width breaks + V-less deep flat)
(defun pooldemo:c3 (org / q ores tipl tipr gg cen)
  (pooldemo:cap org "3  OVAL / true-radius ends / SPORT bottom + section")
  (setq q (list (list 60.0 0.0) (list 420.0 0.0) (list 420.0 240.0) (list 60.0 240.0))
        cen (list 240.0 120.0)
        ores (pool:ovalends 480.0 nil nil 360.0 240.0 240.0)
        tipl (list (- 60.0 (caddr ores)) 120.0)
        tipr (list (+ 420.0 (cadddr ores)) 120.0))
  (pool:line (nth 0 q) (nth 1 q) "POOL")
  (pool:line (nth 3 q) (nth 2 q) "POOL")
  (pool:arc3p (nth 0 q) tipl (nth 3 q) "POOL")
  (setvar "CLAYER" "DIMENSION")
  (pool:dimrad (entlast) tipl (list -1.0 0.0) 30.0)
  (setvar "CLAYER" "POOL")
  (pool:arc3p (nth 1 q) tipr (nth 2 q) "POOL")
  (setvar "CLAYER" "DIMENSION")
  (pool:dimrad (entlast) tipr (list 1.0 0.0) 30.0)
  (pool:dimalg tipl tipr (list 240.0 -60.0))
  (setvar "CLAYER" "POOL")
  (setq gg (pool:hopsportc (list tipl (list 0.0 1.0)) (list tipr (list 0.0 1.0))
                           (list (nth 0 q) (list 1.0 0.0))
                           (list (nth 3 q) (list 1.0 0.0))
                           cen 48.0 60.0 120.0 144.0 108.0 24.0 24.0))
  (pool:hopsportdraw gg nil "POOL" nil)
  (pool:profdraw 0.0 -150.0 480.0 40.0
                 (list (cons 48.0 40.0) (cons 108.0 72.0)
                       (cons 228.0 72.0) (cons 372.0 40.0))
                 "POOL" nil))

;; 4. grecian, six-sided hopper
(defun pooldemo:c4 (org / pts lend rend gg)
  (pooldemo:cap org "4  GRECIAN / 45-deg ends / SIX-SIDED hopper")
  (setq lend (pool:grecendp (list 0.0 0.0) (list 0.0 240.0) (list -1.0 0.0)
                            70.0 70.0 140.0)
        rend (pool:grecendp (list 480.0 0.0) (list 480.0 240.0) (list 1.0 0.0)
                            70.0 70.0 140.0)
        pts (list (list 0.0 0.0) (list 480.0 0.0)
                  (cadr rend) (car rend)
                  (list 480.0 240.0) (list 0.0 240.0)
                  (car lend) (cadr lend)))
  (pool:line (nth 0 pts) (nth 1 pts) "POOL")
  (pool:line (nth 1 pts) (nth 2 pts) "POOL")
  (pool:line (nth 2 pts) (nth 3 pts) "POOL")
  (pool:line (nth 3 pts) (nth 4 pts) "POOL")
  (pool:line (nth 4 pts) (nth 5 pts) "POOL")
  (pool:line (nth 5 pts) (nth 6 pts) "POOL")
  (pool:line (nth 6 pts) (nth 7 pts) "POOL")
  (pool:line (nth 7 pts) (nth 0 pts) "POOL")
  (setvar "CLAYER" "DIMENSION")
  (pool:dimalg (nth 0 pts) (nth 1 pts) (list 240.0 -60.0))
  (pool:dimalg (nth 7 pts) (nth 6 pts)
               (cal:v+ (cal:mid (nth 7 pts) (nth 6 pts)) (list -40.0 0.0)))
  (setvar "CLAYER" "POOL")
  ;; sheet letters: W 84 flat, L1 48 left edge on the 120 hopper width
  (setq gg (pool:hopgrecc pts 90.0 120.0 150.0 60.0 60.0
                          (list "Letters" 84.0 48.0 120.0)))
  (pool:hopgrecdraw gg "POOL" t nil))

;; 5. roman, oval (radius-end) hopper
(defun pooldemo:c5 (org / q lend rend tipl tipr gg)
  (pooldemo:cap org "5  ROMAN / stub ends + arcs / TRUE-OVAL hopper")
  (setq q (list (list 0.0 0.0) (list 400.0 0.0) (list 400.0 260.0) (list 0.0 260.0)))
  (pool:line (nth 0 q) (nth 1 q) "POOL")
  (pool:line (nth 3 q) (nth 2 q) "POOL")
  (pool:lined (nth 1 q) (nth 2 q))
  (pool:lined (nth 3 q) (nth 0 q))
  ;; pool:romend grew a second point pair (the stub feet) after this
  ;; demo was written; a plain rectangular end has no stub, so both
  ;; pairs are the same two points - the mapping POOL.LSP's own
  ;; "ROman" branch uses when it forwards an un-offset end.
  (setq lend (pool:romend (nth 0 q) (nth 3 q) (nth 0 q) (nth 3 q)
                          (list -1.0 0.0) 45.0 160.0 "POOL")
        rend (pool:romend (nth 1 q) (nth 2 q) (nth 1 q) (nth 2 q)
                          (list 1.0 0.0) 45.0 160.0 "POOL")
        tipl (car lend) tipr (car rend))
  (setvar "CLAYER" "DIMENSION")
  (pool:dimrad (nth 3 lend) tipl (list -1.0 0.0) 30.0)
  (pool:dimrad (nth 3 rend) tipr (list 1.0 0.0) 30.0)
  (pool:dimalg tipl tipr (list 200.0 -60.0))
  (setvar "CLAYER" "POOL")
  (setq gg (pool:hopovalc q tipl tipr 80.0 150.0 130.0 65.0 65.0 65.0))
  (pool:hopovaldraw gg "POOL" nil))

;; 6. true L, standard hopper in the main section
(defun pooldemo:c6 (org / pts dv mquad gg)
  (pooldemo:cap org "6  L / standard hopper in the main section")
  (setq pts (pool:hexguess (list 480.0 420.0 180.0 180.0 300.0 240.0) nil))
  (pool:line (nth 0 pts) (nth 1 pts) "POOL")
  (pool:line (nth 1 pts) (nth 2 pts) "POOL")
  (pool:line (nth 2 pts) (nth 3 pts) "POOL")
  (pool:line (nth 3 pts) (nth 4 pts) "POOL")
  (pool:line (nth 4 pts) (nth 5 pts) "POOL")
  (pool:line (nth 5 pts) (nth 0 pts) "POOL")
  (setq dv (pool:linex (nth 4 pts) (cal:v- (nth 5 pts) (nth 0 pts))
                       (nth 0 pts) (cal:v- (nth 1 pts) (nth 0 pts)))
        mquad (list (nth 0 pts) dv (nth 4 pts) (nth 5 pts))
        gg (pool:hopcalc mquad pool:*sq4* 60.0 90.0 0.0 60.0 60.0))
  (pool:hopdraw gg "POOL" t)
  (pooldemo:hopdims gg nil))

;; 7. lazy L
(defun pooldemo:c7 (org / pts)
  (pooldemo:cap org "7  LAZY L / 45-degree bend")
  (setq pts (pool:hexguess (list 296.0 167.6 167.6 99.0 226.0 168.0) t))
  (pool:line (nth 0 pts) (nth 1 pts) "POOL")
  (pool:line (nth 1 pts) (nth 2 pts) "POOL")
  (pool:line (nth 2 pts) (nth 3 pts) "POOL")
  (pool:line (nth 3 pts) (nth 4 pts) "POOL")
  (pool:line (nth 4 pts) (nth 5 pts) "POOL")
  (pool:line (nth 5 pts) (nth 0 pts) "POOL")
  (setvar "CLAYER" "DIMENSION")
  (pool:dimalg (nth 0 pts) (nth 1 pts)
               (cal:v+ (cal:mid (nth 0 pts) (nth 1 pts)) (list 0.0 -50.0)))
  (setvar "CLAYER" "POOL"))

;; 8. modified flat and sloping shallow end, side by side
(defun pooldemo:c8 (org / q sq gg)
  (pooldemo:cap org "8  MODIFIED FLAT (left) and SLOPING SHALLOW END (right)")
  (setq q (list (list 0.0 0.0) (list 480.0 0.0) (list 480.0 240.0) (list 0.0 240.0))
        sq (list (list "Cut" 34.0) (list "Cut" 34.0)
                 (list "Cut" 34.0) (list "Cut" 34.0)))
  (pool:drawrect q sq)
  (setq gg (pooldemo:bottom q sq "MOdflat" 24.0 432.0 24.0 0.0 24.0 24.0
                            40.0 60.0 40.0))
  (pooldemo:hopdims gg nil)
  ;; the sloping shallow end, one cell to the right
  (setq pool:*base* (list (+ (car org) pooldemo:*colw*) (cadr org)))
  (pool:drawrect q pool:*sq4*)
  (setq gg (pooldemo:bottom q pool:*sq4* "SHallow" 60.0 60.0 240.0 120.0
                            60.0 60.0 40.0 60.0 45.0))
  (pooldemo:hopdims gg nil))

;; 9. a FAILED bottom: G resolved negative, so it is drawn 1' long,
;;    F pays the difference, and both go red -- dims and report rows
(defun pooldemo:c9 (org / q sq cv vals fixed gg rows)
  (pooldemo:cap org "9  VALIDATION / negative G floored to 1', F trimmed, both RED")
  (setq q (list (list 0.0 0.0) (list 480.0 0.0) (list 480.0 240.0) (list 0.0 240.0))
        sq pool:*sq4*)
  (pool:drawrect q sq)
  ;; H 60 + G -20 + F 380 + E 60 cannot close: G floors at 12, F pays
  (setq cv (pool:chainval (list 60.0 -20.0 380.0 60.0) 480.0)
        vals (car cv) fixed (cadr cv)
        gg (pool:hopcalc q sq (nth 0 vals) (nth 1 vals) (nth 3 vals) 60.0 60.0))
  (pool:hopdraw gg "POOL" t)
  (pooldemo:hopdims gg fixed)
  (setq rows (list
    (pool:vrow "HOP H" 60.0 (nth 0 vals) 0 fixed)
    (pool:vrow "HOP G" -20.0 (nth 1 vals) 1 fixed)
    (pool:vrow "HOP F" 380.0 (nth 2 vals) 2 fixed)
    (pool:vrow "HOP E" 60.0 (nth 3 vals) 3 fixed)))
  (pool:report rows
               (list "BOTTOM LENGTHS FAILED - G/F ADJUSTED, VERIFY")
               540.0 240.0 9.0 "POOL-NOTES"))

;; 10. octagon drawn from A and B alone, with a square hopper
(defun pooldemo:c10 (org / c pts gg)
  (pooldemo:cap org "10  OCTAGON / drawn from A and B alone / square hopper")
  ;; A = B = 420 -> a regular octagon: c = A / (2 + root 2)
  (setq c (/ 420.0 3.41421356237)
        pts (list (list c 0.0) (list (- 420.0 c) 0.0)
                  (list 420.0 c) (list 420.0 (- 420.0 c))
                  (list (- 420.0 c) 420.0) (list c 420.0)
                  (list 0.0 (- 420.0 c)) (list 0.0 c)))
  (pool:line (nth 0 pts) (nth 1 pts) "POOL")
  (pool:line (nth 1 pts) (nth 2 pts) "POOL")
  (pool:line (nth 2 pts) (nth 3 pts) "POOL")
  (pool:line (nth 3 pts) (nth 4 pts) "POOL")
  (pool:line (nth 4 pts) (nth 5 pts) "POOL")
  (pool:line (nth 5 pts) (nth 6 pts) "POOL")
  (pool:line (nth 6 pts) (nth 7 pts) "POOL")
  (pool:line (nth 7 pts) (nth 0 pts) "POOL")
  (setvar "CLAYER" "DIMENSION")
  (pool:dimalg (list 0.0 0.0) (list 420.0 0.0) (list 210.0 -60.0))
  (pool:dimalg (nth 7 pts) (nth 0 pts)
               (cal:v+ (cal:mid (nth 7 pts) (nth 0 pts)) (list -30.0 -30.0)))
  (setvar "CLAYER" "POOL")
  (setq gg (pool:hopgrecc pts 90.0 110.0 130.0 90.0 90.0 nil))
  (pool:hopgrecdraw gg "POOL" nil nil))

;; 11. round pool: a true circle in square, with the radius-end hopper
(defun pooldemo:c11 (org / quad tipl tipr gg)
  (pooldemo:cap org "11  ROUND / in-square circle / TRUE-OVAL hopper")
  (pool:roundbody (list 210.0 210.0) 420.0 420.0 "POOL")
  (setq quad (list (list 0.0 0.0) (list 420.0 0.0)
                   (list 420.0 420.0) (list 0.0 420.0))
        tipl (list 0.0 210.0) tipr (list 420.0 210.0))
  (setvar "CLAYER" "DIMENSION")
  (pool:dimalg tipl tipr (list 210.0 -60.0))
  (setvar "CLAYER" "POOL")
  ;; H 70 + G 150 + F 110 + E 90 = 420 ; M 90 + L 240 + K 90 = 420
  (setq gg (pool:hopovalc quad tipl tipr 70.0 150.0 90.0 90.0 90.0 120.0))
  (pool:hopovaldraw gg "POOL" nil))

;; 12. mutt: roman deep end + grecian shallow end on one rectangle body
(defun pooldemo:c12 (org / quad lend rend tipl tipr hq gg)
  (pooldemo:cap org "12  MUTT / ROMAN deep end + GRECIAN shallow end / NORMAL hopper")
  ;; body 440 x 240; roman end sticks 40 out left, grecian cuts 50 in
  (setq quad (list (list 0.0 0.0) (list 440.0 0.0)
                   (list 440.0 240.0) (list 0.0 240.0)))
  (pool:line (list 0.0 0.0) (list 390.0 0.0) "POOL")
  (pool:line (list 0.0 240.0) (list 390.0 240.0) "POOL")
  ;; the two extra points are the END-WALL ends (POOL REV20: a square
  ;; end's corners can be treated, and the wall then stops short of
  ;; them); neither of these ends is square, so they are the corners
  (setq lend (pool:muttend (nth 0 quad) (nth 3 quad)
                           (list 0.0 0.0) (list 0.0 240.0)
                           (nth 0 quad) (nth 3 quad)
                           (list -1.0 0.0) "ROman" 40.0 160.0 40.0 "POOL")
        rend (pool:muttend (nth 1 quad) (nth 2 quad)
                           (list 390.0 0.0) (list 390.0 240.0)
                           (nth 1 quad) (nth 2 quad)
                           (list 1.0 0.0) "Grecian" 40.0 160.0 0.0 "POOL")
        tipl (car lend) tipr (car rend))
  (setvar "CLAYER" "DIMENSION")
  (pool:dimalg tipl tipr (list (car (cal:mid tipl tipr)) 300.0))
  (pool:dimrad (cadddr lend) tipl (list -1.0 0.0) 30.0)
  (setvar "CLAYER" "POOL")
  ;; bottom on the tip-to-tip frame, no corner ties (mixed ends)
  (setq hq (list (list -40.0 0.0) (list 440.0 0.0)
                 (list 440.0 240.0) (list -40.0 240.0))
        gg (pool:hopcalc hq pool:*sq4* 60.0 90.0 120.0 60.0 60.0))
  (pool:hopdraw gg "POOL" nil)
  (pooldemo:hopdims gg nil))

;;; -------------------- the command ------------------------------------

(defun c:POOLDEMO ( / *error*)

  ;; nothing to put back at this level: the gate below changes nothing,
  ;; and pooldemo:run carries the handler for what it changes
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nPOOLDEMO error: " msg)))
    (princ))

  (if (not (member 'pool:hopcalc (atoms-family 0)))
      (princ "\nPOOL.LSP is not loaded -- APPLOAD it first, then run POOLDEMO.")
      (pooldemo:run))
  (princ))

(defun pooldemo:run ( / *error* undo-open cells k org)

  ;; the handler lives where the group is opened, so the flag it reads
  ;; is this run's own local -- it used to be pool:*undogrp*, shared
  ;; with POOL and the tutorial
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nPOOLDEMO error: " msg)))
    (cal:sysrestore)
    (if undo-open (setq undo-open (cal:undoend)))
    (if *pop-error-mode* (*pop-error-mode*))
    (princ))

  (if *push-error-using-command* (*push-error-using-command*))
  (cal:syssave '("OSMODE" "LUNITS" "CMDECHO" "CLAYER"))
  (setq pool:*valnotes* nil
        pool:*smallwarned* nil)
  (setvar "CMDECHO" 0)
  (setq undo-open (cal:undobegin))
  (setvar "OSMODE" 0)
  (setvar "LUNITS" 4)

  (pool:layer "POOL" 4)
  (pool:layer "DIMENSION" 2)
  (pool:layer "POOL-NOTES" 3)
  (setq pool:*dashlt* (pool:ltload "DASHED")
        pool:*dotlt* (pool:ltload "DOT"))
  (setvar "CLAYER" "POOL")

  (princ "\nPOOLDEMO -- drawing one example of every shape and bottom ...")
  (setq cells (list 'pooldemo:c1 'pooldemo:c2 'pooldemo:c3 'pooldemo:c4
                    'pooldemo:c5 'pooldemo:c6 'pooldemo:c7 'pooldemo:c8
                    'pooldemo:c9 'pooldemo:c10 'pooldemo:c11 'pooldemo:c12)
        k 0)
  (foreach fn cells
    (setq org (list (* pooldemo:*colw* (rem k 3))
                    (* pooldemo:*rowh* (- 0 (/ k 3)))))
    (setq pool:*base* org)
    (princ (strcat "\n  cell " (itoa (1+ k)) " ..."))
    (apply fn (list org))
    (setq pool:*base* org)              ; a cell may have moved the base
    (setq k (1+ k)))

  (command "_.ZOOM" "_Extents")
  (if undo-open (setq undo-open (cal:undoend)))
  (cal:sysrestore)
  (if *pop-error-mode* (*pop-error-mode*))
  (princ (strcat "\nPOOLDEMO complete -- " (itoa (length cells))
                 " cells drawn.  If every cell looks right, POOL.LSP is"
                 " working in this drawing."))
  (princ))

;; Which build is loaded - the first thing to check when a run does
;; something the notes above say it should not.
(defun c:POOLDEMOVER ()
  (princ (strcat "\nPOOLDEMO " pooldemo:*version*))
  (princ))

(princ (strcat "\nPOOLDEMO " pooldemo:*version*
               " loaded.  Type POOLDEMO to draw the install-check sheet."))
(princ)
