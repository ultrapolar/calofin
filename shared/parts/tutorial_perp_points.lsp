;;; tutorial_perp_points.lsp  --  AutoCAD 2018 (AutoLISP)
;;;
;;; Command: TUTORIALPERPPTS
;;;
;;; Interactive tutorial for the PERPPTS command (perp_points.lsp),
;;; aimed at first-time users.  Offers three modes:
;;;
;;;   Checks - lists everything PERPPTS validates and guards against,
;;;            for readers who want the rules up front
;;;   Demo   - draws a worked example one stage at a time, narrating
;;;            what PERPPTS does and what the drawing looks like at
;;;            each step
;;;   Both   - the checklist first, then the demo
;;;
;;; The demo asks for an insertion point and a size, then builds the
;;; sample: the selected line, the direction click and its red arrow,
;;; the division points, the offset points, the connecting polyline,
;;; the dimensions, and a repeat round on the new polyline.  At the end
;;; the demo drawing can be kept for reference or erased.  The whole
;;; tutorial is one UNDO group either way.
;;;
;;; License: GPL-3.0-or-later
;;; ---------------------------------------------------------------------
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.

;; arc-length helpers (they match perp_points.lsp)
;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *tutperp-version* "v0.3")

(defun tutp:lerp (a b tt)
  (list (+ (car a)   (* tt (- (car b)   (car a))))
        (+ (cadr a)  (* tt (- (cadr b)  (cadr a))))
        (+ (caddr a) (* tt (- (caddr b) (caddr a))))))

(defun tutp:pathlen (pts / total i)
  (setq total 0.0 i 0)
  (while (< (1+ i) (length pts))
    (setq total (+ total (distance (nth i pts) (nth (1+ i) pts)))
          i     (1+ i)))
  total)

(defun tutp:pt-at (pts d / i a b segd res)
  (cond
    ((<= d 0.0) (car pts))
    (t
     (setq i 0 res nil)
     (while (and (null res) (< (1+ i) (length pts)))
       (setq a    (nth i pts)
             b    (nth (1+ i) pts)
             segd (distance a b))
       (if (<= d segd)
         (setq res (tutp:lerp a b (if (> segd 1e-12) (/ d segd) 0.0)))
         (setq d (- d segd) i (1+ i))))
     (if res res (last pts)))))

(defun tutp:sample (pts n / total i out)
  (setq total (tutp:pathlen pts) out '() i 0)
  (while (< i n)
    (setq out (cons (tutp:pt-at pts
                                (if (> n 1)
                                  (* (/ (float i) (float (1- n))) total)
                                  0.0))
                    out)
          i   (1+ i)))
  (reverse out))

(defun c:TUTORIALPERPPTS (/ *error* tutp:say tutp:pause tutp:track
                            tutp:finish
                            os ce pd undoOpen ents mode ans p sz z
                            n i tt bx q d lens len base np
                            basePts newPts bases2 new2 e s)

  (defun tutp:say (lines)
    (foreach s lines (princ (strcat "\n" s)))
    (princ))

  (defun tutp:pause ()
    (getstring "\n      --- press Enter to continue --- ")
    (princ))

  ;; remember the entity just created so the demo can be erased
  (defun tutp:track ()
    (setq ents (cons (entlast) ents)))

  (defun tutp:finish ()
    (if pd (setvar "PDMODE"  pd))
    (if os (setvar "OSMODE"  os))
    (if ce (setvar "CMDECHO" ce))
    (if undoOpen
      (progn (command "._UNDO" "_End") (setq undoOpen nil))))

  (defun *error* (msg)
    (tutp:finish)
    (if (and msg (not (member msg '("Function cancelled" "quit / exit abort"))))
      (princ (strcat "\nError: " msg)))
    (princ))

  (setq os (getvar "OSMODE")
        ce (getvar "CMDECHO")
        pd (getvar "PDMODE")
        ents '())
  (setvar "CMDECHO" 0)
  (command "._UNDO" "_Begin")
  (setq undoOpen T)

  (tutp:say '("======================================================="
              " TUTORIALPERPPTS - a guided tour of the PERPPTS command"
              "======================================================="
              "PERPPTS divides a line into equally spaced points, offsets"
              "each point perpendicular to the line by a length you type,"
              "joins the offset points with a polyline, and dimensions"
              "every offset.  It can then repeat on the polyline it just"
              "built, as many times as you like."))
  (initget "Checks Demo Both")
  (setq mode (getkword "\nWhat would you like? [Checks/Demo/Both] <Both>: "))
  (if (null mode) (setq mode "Both"))

  ;; --- the checklist ---------------------------------------------------
  (if (member mode '("Checks" "Both"))
    (progn
      (tutp:say '(""
                  "----- What PERPPTS checks and guarantees -----"
                  ""
                  "Selection"
                  "  * only a LINE or an open polyline is accepted; anything"
                  "    else re-prompts instead of cancelling the command"
                  "  * zero-length and closed objects are rejected"
                  ""
                  "Overall width"
                  "  * right after the selection you are asked whether the"
                  "    overall width has changed: Grew, Shrank, New, or"
                  "    Unchanged (the default, and Enter)"
                  "  * the width meant is the distance straight ACROSS, end"
                  "    to end - never the length of the OBJECT, which on"
                  "    anything bowed runs further than the width it spans"
                  "  * half of any difference is added to, or taken off,"
                  "    EACH end: the OBJECT in the drawing is resized to"
                  "    match, so the base points and their dimensions still"
                  "    land on it.  One U puts the width back"
                  "  * shrinking away the whole width is rejected, and a"
                  "    resize the drawing will not take - a locked, frozen"
                  "    or switched-off layer - stops the command rather"
                  "    than measuring off geometry that is not there"
                  ""
                  "Direction click"
                  "  * the end nearest your click becomes START - lengths are"
                  "    then entered in order START -> FINISH (a red arrow"
                  "    marks START for the whole run)"
                  "  * the side of the line you click is the side every round"
                  "    offsets toward"
                  "  * a click landing on the line itself is rejected (the"
                  "    side would be ambiguous); object snap is off for this"
                  "    click so it cannot be pulled onto the line"
                  ""
                  "Counts and lengths"
                  "  * the point count must be a whole number of at least 2;"
                  "    Enter reuses the previous round's count"
                  "  * a count over 100 asks for confirmation first"
                  "  * lengths must be positive - zero and negative values"
                  "    are rejected"
                  "  * Enter repeats the previous length (handy for runs of"
                  "    equal values); typing B (Back) steps back one point"
                  ""
                  "Joining the points"
                  "  * Straight, Arcs or Mixed, asked once a round has three"
                  "    points or more; the default is the previous round's"
                  "    answer, and Straight to begin with"
                  "  * Mixed then asks which segment numbers are arcs, as"
                  "    single numbers or ranges - 1 3-5 - and leaves the"
                  "    rest straight; a list it cannot read re-asks, and B"
                  "    goes back to the question"
                  "  * an arc is a bulge on the same polyline, running"
                  "    through the measured points - never a spline, and"
                  "    never a curve-fit heavy polyline"
                  ""
                  "Output"
                  "  * the offset polyline takes the layer, colour, linetype,"
                  "    lineweight and linetype scale of the source line"
                  "  * dimensions are drawn at the very end, all at once, on"
                  "    the DIMENSIONS layer (created if missing)"
                  "  * you pick STANDARD INCHES or SIDE STANDARD; if the"
                  "    drawing lacks that style the current style is used"
                  "    and a note is printed"
                  ""
                  "Safety net"
                  "  * the whole run is one UNDO group - a single U reverses"
                  "    everything, however many rounds were done"
                  "  * Esc at any prompt cleans up: temporary guides erased;"
                  "    OSMODE, CMDECHO, PDMODE, CLAYER, the colour/linetype/"
                  "    lineweight defaults and the dimension style restored"
                  "  * works correctly in a rotated or shifted UCS"))
      (if (equal mode "Both") (tutp:pause))))

  ;; --- the drawn demo --------------------------------------------------
  (if (member mode '("Demo" "Both"))
    (progn
      (tutp:say '(""
                  "----- Worked example -----"
                  "The demo now draws what PERPPTS produces, one stage at a"
                  "time.  Pick an empty spot with room to the upper right."))
      (setq p (getpoint "\nInsertion point for the demo: "))
      (while (null p)
        (setq p (getpoint "\nA point is required - insertion point: ")))
      (setq sz (getdist p "\nDemo size <100>: "))
      (if (null sz) (setq sz 100.0))
      (setvar "OSMODE" 0)
      (if (member pd '(0 1)) (setvar "PDMODE" 3))
      (setq z (caddr p))

      ;; stage 1: the selected line
      (entmake (list '(0 . "LINE")
                     (cons 10 (trans p 1 0))
                     (cons 11 (trans (list (+ (car p) sz) (cadr p) z) 1 0))))
      (tutp:track)
      (tutp:say '(""
                  "STAGE 1 - the line."
                  "You start PERPPTS and select this line.  Wrong picks just"
                  "re-prompt, so a missed click costs nothing."))
      (tutp:pause)

      ;; stage 2: the direction click, marked with a red X, and the
      ;; red arrow at the START end
      (setq q (list (+ (car p) (* 0.20 sz)) (+ (cadr p) (* 0.30 sz)) z)
            d (* 0.03 sz))
      (foreach s (list (list (list (- (car q) d) (- (cadr q) d) z)
                             (list (+ (car q) d) (+ (cadr q) d) z))
                       (list (list (- (car q) d) (+ (cadr q) d) z)
                             (list (+ (car q) d) (- (cadr q) d) z)))
        (entmake (list '(0 . "LINE") '(62 . 1)
                       (cons 10 (trans (car s)  1 0))
                       (cons 11 (trans (cadr s) 1 0))))
        (tutp:track))
      ;; arrow: shaft into START from outside, plus two barbs
      (foreach s (list (list (list (- (car p) (* 0.15 sz)) (cadr p) z) p)
                       (list p (list (- (car p) (* 0.048 sz))
                                     (- (cadr p) (* 0.022 sz)) z))
                       (list p (list (- (car p) (* 0.048 sz))
                                     (+ (cadr p) (* 0.022 sz)) z)))
        (entmake (list '(0 . "LINE") '(62 . 1)
                       (cons 10 (trans (car s)  1 0))
                       (cons 11 (trans (cadr s) 1 0))))
        (tutp:track))
      (tutp:say '(""
                  "STAGE 2 - the direction click."
                  "You click once beside the line (the red X).  Two things"
                  "are decided by that single click:"
                  "  * the line end nearest the click becomes START - the red"
                  "    arrow marks it - and lengths are entered START to"
                  "    FINISH;"
                  "  * the side you clicked (here: above) is the side all"
                  "    offsets go, in every round."
                  "A click exactly on the line is rejected as ambiguous."))
      (tutp:pause)

      ;; stage 3: the division points
      (setq n 5 basePts '() i 0)
      (while (< i n)
        (setq tt (/ (float i) (float (1- n)))
              bx (+ (car p) (* tt sz)))
        (setq basePts (cons (list bx (cadr p) z) basePts))
        (command "._POINT" (list bx (cadr p) z))
        (tutp:track)
        (setq i (1+ i)))
      (setq basePts (reverse basePts))
      (tutp:say '(""
                  "STAGE 3 - the division points."
                  "You enter how many values are required - here 5.  The"
                  "line is divided into that many equally spaced points,"
                  "both ends included.  (At least 2; over 100 asks first.)"))
      (tutp:pause)

      ;; stage 4: the offset points
      (setq lens (list (* 0.20 sz) (* 0.30 sz) (* 0.45 sz)
                       (* 0.35 sz) (* 0.25 sz))
            newPts '() i 0)
      (foreach base basePts
        (setq len (nth i lens)
              np  (list (car base) (+ (cadr base) len) z))
        (setq newPts (cons np newPts))
        (command "._POINT" np)
        (tutp:track)
        (setq i (1+ i)))
      (setq newPts (reverse newPts))
      (tutp:say '(""
                  "STAGE 4 - the offset points."
                  "You type a length for each point, START to FINISH - here"
                  "20, 30, 45, 35 and 25 (per 100 of demo size).  Each point"
                  "moves perpendicular to the line by its length, toward the"
                  "clicked side.  Enter repeats the previous length; Back"
                  "steps back one point; zero and negatives are refused."))
      (tutp:pause)

      ;; stage 5: the connecting polyline
      (command "._PLINE")
      (foreach np newPts (command np))
      (command "")
      (tutp:track)
      (tutp:say '(""
                  "STAGE 5 - the polyline."
                  "The offset points are joined with a polyline.  In the"
                  "real command it takes the layer, colour, linetype,"
                  "lineweight and linetype scale of the line you selected,"
                  "so it reads as the same kind of object."))
      (tutp:pause)

      ;; stage 6: the dimensions
      (setq i 0)
      (while (< i n)
        (command "._DIMALIGNED" (nth i basePts) (nth i newPts) (nth i newPts))
        (tutp:track)
        (setq i (1+ i)))
      (tutp:say '(""
                  "STAGE 6 - the dimensions."
                  "One aligned dimension per point, from the line to its"
                  "offset point.  In the real command these are drawn at the"
                  "very end, all at once, on the DIMENSIONS layer, in the"
                  "style you pick: STANDARD INCHES or SIDE STANDARD."))
      (tutp:pause)

      ;; stage 7: a repeat round on the new polyline
      (setq bases2 (tutp:sample newPts n)
            new2   '())
      (foreach base bases2
        (setq np (list (car base) (+ (cadr base) (* 0.15 sz)) z))
        (setq new2 (cons np new2))
        (command "._POINT" np)
        (tutp:track))
      (setq new2 (reverse new2))
      (command "._PLINE")
      (foreach np new2 (command np))
      (command "")
      (tutp:track)
      (setq i 0)
      (while (< i n)
        (command "._DIMALIGNED" (nth i bases2) (nth i new2) (nth i new2))
        (tutp:track)
        (setq i (1+ i)))
      (tutp:say '(""
                  "STAGE 7 - repeating."
                  "After each polyline PERPPTS asks: Repeat on the new"
                  "polyline?  Answering Yes spaces a fresh set of points by"
                  "arc length ALONG that polyline and offsets them again -"
                  "same side, dimensions still perpendicular to the original"
                  "line.  Here a second round of 15s was added.  Repeat as"
                  "many times as you like; a single U undoes the whole run."))
      (tutp:pause)

      ;; keep or erase the demo
      (initget "Keep Erase")
      (setq ans (getkword "\nKeep the demo drawing? [Keep/Erase] <Keep>: "))
      (if (equal ans "Erase")
        (progn
          (foreach e ents (if (and e (entget e)) (entdel e)))
          (setq ents nil)))))

  (tutp:finish)
  (tutp:say '(""
              "Tutorial finished.  Type PERPPTS to try it for real."))
  (princ))

(princ (strcat "\ntutorial_perp_points.lsp " *tutperp-version*
               " loaded.  Type TUTORIALPERPPTS to run."))
(princ)
