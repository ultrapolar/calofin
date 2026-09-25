;;; tutorial_cperp_points.lsp  --  AutoCAD 2018 (AutoLISP)
;;;
;;; Command: TUTORIALCPERPPTS
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; Interactive tutorial for the CPERPPTS command (cperp_points.lsp),
;;; the curved companion to PERPPTS.  Offers three modes:
;;;
;;;   Checks - lists everything CPERPPTS validates and guards against
;;;   Demo   - draws a worked example on a curved polyline, one stage
;;;            at a time, narrating what happens at each step
;;;   Both   - the checklist first, then the demo
;;;
;;; The demo asks for an insertion point and a size, draws a sample
;;; arched polyline, then walks through the direction click, the
;;; arc-length division points, the tangent-perpendicular offsets, the
;;; smooth arc-polyline result, the dimensions, and a repeat round from
;;; the newest curve.  At the end the demo drawing can be kept or
;;; erased.  The whole tutorial is one UNDO group either way.
;;;
;;; License: GPL-3.0-or-later
;;; ---------------------------------------------------------------------

(vl-load-com)

;; Version banner: tools/release_lisp.py reads it to stamp the dated
;; REV twin in releases/ (vN.M -> _MMDDYY_REVNM).
(setq *tutcperp-version* "v0.13")

;; curve helpers (they match cperp_points.lsp)

;; unit tangent of the curve (current UCS) at the point closest to pt;
;; rev flips it to follow the direction of travel
(defun tutc:tangent (crv pt rev / w cp prm dv dx dy dl)
  (setq w  (trans pt 1 0)
        cp (vlax-curve-getClosestPointTo crv w))
  (if (null cp)
    nil
    (progn
      (setq prm (vlax-curve-getParamAtPoint crv cp))
      (if (null prm)
        (setq prm (vlax-curve-getParamAtDist
                    crv (vlax-curve-getDistAtPoint crv cp))))
      (if (null prm)
        nil
        (progn
          (setq dv (trans (vlax-curve-getFirstDeriv crv prm) 0 1 T)
                dx (car dv)
                dy (cadr dv)
                dl (sqrt (+ (* dx dx) (* dy dy))))
          (if (< dl 1e-12)
            nil
            (progn
              (if rev (setq dx (- dx) dy (- dy)))
              (list (/ dx dl) (/ dy dl)))))))))

;; bulge of the arc a->b whose start tangent is tg (tan of half the
;; tangent-to-chord angle); straight fallback on degenerate input
(defun tutc:bulge (tg a b / cx cy dot crs alpha lim)
  (setq cx (- (car b) (car a))
        cy (- (cadr b) (cadr a)))
  (if (or (null tg)
          (< (sqrt (+ (* cx cx) (* cy cy))) 1e-12))
    0.0
    (progn
      (setq dot   (+ (* (car tg) cx) (* (cadr tg) cy))
            crs   (- (* (car tg) cy) (* (cadr tg) cx))
            alpha (atan crs dot)
            lim   2.98)
      (if (> alpha lim)     (setq alpha lim))
      (if (< alpha (- lim)) (setq alpha (- lim)))
      (/ (sin (/ alpha 2.0)) (cos (/ alpha 2.0))))))

;; write arc bulges into the LWPOLYLINE en (drawn through pts with
;; travel tangents tangs); the entity stays an LWPOLYLINE
(defun tutc:arcs (en pts tangs / d out g i b)
  (setq d (entget en) out '() i 0)
  (foreach g d
    (cond
      ((= 42 (car g)))
      ((= 10 (car g))
       (setq b (if (< (1+ i) (length pts))
                 (tutc:bulge (nth i tangs) (nth i pts) (nth (1+ i) pts))
                 0.0))
       (setq out (cons (cons 42 b) (cons g out))
             i   (1+ i)))
      (t (setq out (cons g out)))))
  (entmod (reverse out)))

(defun c:TUTORIALCPERPPTS (/ *error* tutc:say tutc:pause tutc:track
                             tutc:finish tutc:round
                             os ce pd plt plw undoOpen ents mode ans p sz z
                             w1 w2 w3 crv tot n i dd q d tg nrm
                             lens base np basePts newPts tangs e s)

  (defun tutc:say (lines)
    (foreach s lines (princ (strcat "\n" s)))
    (princ))

  (defun tutc:pause ()
    ((lambda (v) (if lzd:ask (lzd:ask "\n      --- press Enter to continue --- " v) v))
      (getstring "\n      --- press Enter to continue --- "))
    (princ))

  (defun tutc:track ()
    (setq ents (cons (entlast) ents)))

  (defun tutc:finish ()
    (if pd  (setvar "PDMODE"    pd))
    (if os  (setvar "OSMODE"    os))
    (if plt (setvar "PLINETYPE" plt))
    (if plw (setvar "PLINEWID"  plw))
    (if ce  (setvar "CMDECHO"   ce))
    (if undoOpen
      (progn (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
             (setq undoOpen nil))))

  (defun *error* (msg)
    (tutc:finish)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nError: " msg)))
    (if lzd:report (lzd:report "TUTORIALCPERPPTS" *tutcperp-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "TUTORIALCPERPPTS" *tutcperp-version*))

  ;; one demo round: sample n points along crv by arc length, offset
  ;; each along the left travel normal by (nth i lens), draw guides,
  ;; the arc polyline and the dimensions; returns the new curve entity
  (defun tutc:round (crv lens / tot i dd base tg nrm np
                                basePts newPts tangs n)
    (setq n   (length lens)
          tot (vlax-curve-getDistAtParam crv (vlax-curve-getEndParam crv))
          basePts '() newPts '() tangs '() i 0)
    (while (< i n)
      (setq dd   (* (/ (float i) (float (1- n))) tot)
            base (trans (vlax-curve-getPointAtDist crv dd) 0 1)
            tg   (tutc:tangent crv base nil))
      (if (null tg) (setq tg (list 1.0 0.0)))     ; demo-safe fallback
      (setq nrm  (list (- (cadr tg)) (car tg))    ; left of travel
            np   (list (+ (car base)  (* (nth i lens) (car nrm)))
                       (+ (cadr base) (* (nth i lens) (cadr nrm)))
                       (caddr base)))
      (setq basePts (cons base basePts)
            newPts  (cons np newPts)
            tangs   (cons tg tangs))
      (command "._POINT" np)
      (tutc:track)
      (setq i (1+ i)))
    (setq basePts (reverse basePts)
          newPts  (reverse newPts)
          tangs   (reverse tangs))
    (command "._PLINE")
    (foreach np newPts (command np))
    (command "")
    (tutc:arcs (entlast) newPts tangs)
    (tutc:track)
    (setq i 0)
    (while (< i n)
      (command "._DIMALIGNED" (nth i basePts) (nth i newPts) (nth i newPts))
      (tutc:track)
      (setq i (1+ i)))
    (entlast))

  (setq os  (getvar "OSMODE")
        ce  (getvar "CMDECHO")
        pd  (getvar "PDMODE")
        plt (getvar "PLINETYPE")
        plw (getvar "PLINEWID")
        ents '())
  (setvar "CMDECHO" 0)
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undoOpen T)))

  (tutc:say '("========================================================="
              " TUTORIALCPERPPTS - a guided tour of the CPERPPTS command"
              "========================================================="
              "CPERPPTS is PERPPTS for curves.  It divides an open curve"
              "into points spaced by true arc length, offsets each point"
              "PERPENDICULAR TO THE TANGENT of the curve underneath it by"
              "a length you type, joins the offsets into a smooth arc"
              "polyline, and dimensions every offset.  It can then repeat"
              "from the curve it just built."))
  (initget "Checks Demo Both")
  (setq mode (getkword "\nWhat would you like? [Checks/Demo/Both] <Both>: "))
  (if lzd:ask (lzd:ask "\nWhat would you like? [Checks/Demo/Both] <Both>: " mode) mode)
  (if (null mode) (setq mode "Both"))

  ;; --- the checklist ---------------------------------------------------
  (if (member mode '("Checks" "Both"))
    (progn
      (tutc:say '(""
                  "----- What CPERPPTS checks and guarantees -----"
                  ""
                  "Selection"
                  "  * accepts any OPEN curve AutoCAD can measure along:"
                  "    polylines (with arc segments), arcs, splines,"
                  "    ellipse arcs and plain lines; anything else"
                  "    re-prompts"
                  "  * zero-length and closed curves are rejected"
                  ""
                  "Direction click"
                  "  * right after the selection you click once beside the"
                  "    curve: the end nearest your click becomes START, and a"
                  "    red arrow marks it for the whole run"
                  "  * the side you click - relative to the direction of"
                  "    travel - is the side every round offsets toward,"
                  "    however the curve bends"
                  "  * a click landing on the curve is rejected as ambiguous"
                  "  * Back at the click re-opens the selection"
                  ""
                  "Overall width"
                  "  * after the click you are asked whether the overall"
                  "    width has changed: Grew, Shrank, New, or Unchanged"
                  "    (the default, and Enter); Back there re-opens the"
                  "    click"
                  "  * EVERY curve gets that question, not just the selected"
                  "    one: each round draws the next course out, and the"
                  "    curve it drew is asked about the moment it appears -"
                  "    a curve built from typed offsets is only as wide as"
                  "    they add up to, and the next round is spaced along"
                  "    it and reads its tangents"
                  "  * the width meant is the distance straight ACROSS, end"
                  "    to end - never the length of the CURVE, which on"
                  "    anything bowed runs further than the width it spans"
                  "  * the change is split EVENLY, half at each end, unless"
                  "    you say otherwise: answer No to the split question and"
                  "    give the amount at the START end (the arrowed one) -"
                  "    the rest goes on at FINISH.  Zero and the whole amount"
                  "    are both answers; more than the whole is refused, and"
                  "    growing and shrinking are shared out the same way"
                  "  * the CURVE in the drawing is resized to match - one"
                  "    scale about a point on the line through its two ends,"
                  "    so an arc stays that arc, scaled - and the base points"
                  "    and their dimensions still land on it.  One U puts"
                  "    the width back"
                  "  * a corrected round has its new points moved with the"
                  "    curve, so its dimensions read the corrected drawing"
                  "    rather than the lengths typed into it"
                  "  * shrinking away the whole width is rejected, and a"
                  "    resize the drawing will not take - a locked, frozen"
                  "    or switched-off layer - stops the command before the"
                  "    first round, where nothing is drawn yet; at a round"
                  "    it leaves the curve at the width it drew and says so"
                  ""
                  "The boundary (optional)"
                  "  * after the width question you may select a curve"
                  "    already in the drawing - a property line, a house"
                  "    wall, a deck edge - for the offsets to answer to;"
                  "    Enter takes None and nothing is capped"
                  "  * you then say what it is: a LIMIT the offsets stop at,"
                  "    or the line every offset runs out to MEET.  Back there"
                  "    re-opens the boundary selection"
                  "  * the distance to it is measured PER POINT: a ray from"
                  "    each base point along its own normal, and the nearest"
                  "    crossing ahead of it.  A boundary at an angle to the"
                  "    run is nearer at one end than the other, which one"
                  "    number could never say"
                  "  * Limit: the length prompt names the distance, M (Max)"
                  "    takes it exactly, and a longer length is brought back"
                  "    to it and said so - the number TYPED is still what"
                  "    Enter repeats at the next point"
                  "  * Meet: a point with the boundary ahead of it lands ON"
                  "    the boundary and no length is asked for it; Back at a"
                  "    length that is asked steps back to the last length"
                  "    typed, taking the landed points in between with it"
                  "  * where the ray never reaches the boundary that point"
                  "    has no maximum and no landing, so a boundary covering"
                  "    part of a run answers for the part it covers"
                  "  * it holds the measured POINTS at the boundary: where"
                  "    the boundary bends away between two of them the arc"
                  "    joining them can still bow past it, and the answer is"
                  "    a point there.  The width correction is not re-capped"
                  "    either - it is your measurement - but a correction"
                  "    that carries points past a Limit, or off a Meet, says"
                  "    how many"
                  ""
                  "Counts and lengths"
                  "  * point count: whole number, at least 2; Enter reuses"
                  "    the previous round's count; over 100 asks first"
                  "  * lengths must be positive; Enter repeats the previous"
                  "    length; B (Back) steps back to the last length typed,"
                  "    or to the count when none was typed yet"
                  "  * a point where the curve direction cannot be read"
                  "    (a cusp) is skipped with a message, never offset in"
                  "    an arbitrary direction"
                  ""
                  "Geometry"
                  "  * points are spaced by TRUE ARC LENGTH, so they never"
                  "    bunch up in tight curvature"
                  "  * each offset runs perpendicular to the curve tangent"
                  "    under its point, so offsets follow the bend"
                  "  * every round works from the NEWEST curve - round 2"
                  "    offsets from the curve round 1 built, and so on"
                  ""
                  "Output"
                  "  * the result is a plain LIGHTWEIGHT POLYLINE whose"
                  "    segments are arcs (bulges) - never a spline, and"
                  "    never a curve-fit heavy polyline; it passes exactly"
                  "    through every offset point"
                  "  * the polyline takes the layer, colour, linetype,"
                  "    lineweight and linetype scale of the source curve"
                  "  * dimensions are drawn at the end, all at once, on the"
                  "    DIMENSION layer, in STANDARD INCHES or SIDE"
                  "    STANDARD (current style if the drawing lacks it)"
                  ""
                  "Safety net"
                  "  * one UNDO group - a single U reverses everything"
                  "  * Esc at any prompt cleans up: guides erased and every"
                  "    changed system variable restored"
                  "  * works correctly in a rotated or shifted UCS"
                  ""
                  "Worth knowing: on a tight concave bend, normals converge,"
                  "so a large offset there can make the new curve cross"
                  "itself - inherent to offsetting along normals."))
      (if (equal mode "Both") (tutc:pause))))

  ;; --- the drawn demo --------------------------------------------------
  (if (member mode '("Demo" "Both"))
    (progn
      (tutc:say '(""
                  "----- Worked example -----"
                  "The demo draws what CPERPPTS produces on a curved"
                  "polyline, one stage at a time.  Pick an empty spot with"
                  "room above."))
      (setq p (getpoint "\nInsertion point for the demo: "))
      (if lzd:ask (lzd:ask "\nInsertion point for the demo: " p) p)
      (while (null p)
        (setq p (getpoint "\nA point is required - insertion point: "))
        (if lzd:ask (lzd:ask "\nA point is required - insertion point: " p) p))
      (setq sz (getdist p "\nDemo size <100>: "))
      (if lzd:ask (lzd:ask "\nDemo size <100>: " sz) sz)
      (if (null sz) (setq sz 100.0))
      (setvar "OSMODE" 0)
      (setvar "PLINETYPE" 2)
      ;; PLINE starts at the width the drawing last used; the demo shows
      ;; what CPERPPTS draws, which is a hairline
      (if (and plw (/= plw 0.0)) (setvar "PLINEWID" 0.0))
      (if (member pd '(0 1)) (setvar "PDMODE" 3))
      (setq z (caddr p))

      ;; stage 1: the source curve - an arched polyline with arc
      ;; segments (negative bulges = clockwise when traveling left to
      ;; right over the top)
      (setq w1 (trans p 1 0)
            w2 (trans (list (+ (car p) (* 0.5 sz))
                            (+ (cadr p) (* 0.30 sz)) z) 1 0)
            w3 (trans (list (+ (car p) sz) (cadr p) z) 1 0))
      (entmake (list '(0 . "LWPOLYLINE")
                     '(100 . "AcDbEntity")
                     '(100 . "AcDbPolyline")
                     '(90 . 3) '(70 . 0)
                     (cons 38 (caddr w1))
                     (cons 10 (list (car w1) (cadr w1))) '(42 . -0.25)
                     (cons 10 (list (car w2) (cadr w2))) '(42 . -0.25)
                     (cons 10 (list (car w3) (cadr w3))) '(42 . 0.0)))
      (setq crv (entlast))
      (tutc:track)
      (tutc:say '(""
                  "STAGE 1 - the curve."
                  "You start CPERPPTS and select this arched polyline.  Any"
                  "OPEN curve works: polylines with arcs, plain arcs,"
                  "splines, ellipse arcs, even straight lines."))
      (tutc:pause)

      ;; stage 2: the direction click (red X above the left end) and
      ;; the red arrow at START, drawn back along the start tangent
      (setq q (list (+ (car p) (* 0.10 sz)) (+ (cadr p) (* 0.35 sz)) z)
            d (* 0.03 sz))
      (foreach s (list (list (list (- (car q) d) (- (cadr q) d) z)
                             (list (+ (car q) d) (+ (cadr q) d) z))
                       (list (list (- (car q) d) (+ (cadr q) d) z)
                             (list (+ (car q) d) (- (cadr q) d) z)))
        (entmake (list '(0 . "LINE") '(62 . 1)
                       (cons 10 (trans (car s)  1 0))
                       (cons 11 (trans (cadr s) 1 0))))
        (tutc:track))
      (setq tg (tutc:tangent crv p nil))
      (entmake (list '(0 . "LINE") '(62 . 1)
                     (cons 10 (trans (list (- (car p)  (* 0.15 sz (car tg)))
                                           (- (cadr p) (* 0.15 sz (cadr tg)))
                                           z) 1 0))
                     (cons 11 (trans p 1 0))))
      (tutc:track)
      (tutc:say '(""
                  "STAGE 2 - the direction click."
                  "You click once beside the curve (the red X).  The end"
                  "nearest the click becomes START (the red arrow), and the"
                  "side you clicked - relative to the direction of travel -"
                  "is the side every round offsets toward, all the way"
                  "around the bend.  The overall-width question comes next,"
                  "and when a change is not split evenly it is this arrow"
                  "that says which end START is."))
      (tutc:pause)

      ;; stage 3 + 4 + 5 + 6: division points, offsets, arc polyline,
      ;; dimensions - drawn by the shared round routine
      (setq lens (list (* 0.22 sz) (* 0.30 sz) (* 0.26 sz)
                       (* 0.34 sz) (* 0.24 sz)))
      (tutc:say '(""
                  "STAGES 3 to 6 - one full round, drawn now:"
                  "  * 5 division points spaced by TRUE ARC LENGTH along the"
                  "    curve (they never bunch up in tight curvature);"
                  "  * each offset by its own typed length, PERPENDICULAR TO"
                  "    THE TANGENT underneath it - watch the directions fan"
                  "    with the bend;"
                  "  * the offsets joined into a smooth ARC POLYLINE - a"
                  "    plain lightweight polyline with arc segments, never a"
                  "    spline - passing exactly through every point;"
                  "  * one aligned dimension per point (in the real command"
                  "    these land on the DIMENSION layer at the end, in the"
                  "    style you pick)."))
      (setq crv (tutc:round crv lens))
      (tutc:pause)

      ;; stage 7: a repeat round from the newest curve
      (setq lens (list (* 0.12 sz) (* 0.12 sz) (* 0.12 sz)
                       (* 0.12 sz) (* 0.12 sz)))
      (setq crv (tutc:round crv lens))
      (tutc:say '(""
                  "STAGE 7 - repeating."
                  "After each curve CPERPPTS asks whether ITS overall width"
                  "has changed - the same Grew/Shrank/New/Unchanged question"
                  "the selected curve got, split the same way - and then"
                  "whether to repeat.  Answering Yes runs the next round"
                  "FROM THE NEWEST CURVE: fresh arc-length points along the"
                  "curve just built, offset perpendicular to ITS tangents -"
                  "here a uniform round of 12s.  Each round follows the"
                  "shape its predecessor took.  Repeat as often as needed;"
                  "one U undoes the whole run."))
      (tutc:pause)

      ;; erase the demo only on an explicit Yes -- Enter keeps it
      (initget "Yes No")
      (setq ans (getkword "\nErase the demo drawing? [Yes/No] <No>: "))
      (if lzd:ask (lzd:ask "\nErase the demo drawing? [Yes/No] <No>: " ans) ans)
      (if (equal ans "Yes")
        (progn
          (foreach e ents (if (and e (entget e)) (entdel e)))
          (setq ents nil)))))

  (tutc:finish)
  (tutc:say '(""
              "Tutorial finished.  Type CPERPPTS to try it for real."))
  (if lzd:end (lzd:end "TUTORIALCPERPPTS"))
  (princ))

;; -------------------- self tests ---------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun tutc:selftests ()
  (list
    (list "bulge of a 45 degree left turn is tan(pi/8)"
          '(tutc:bulge '(1 0) '(0 0) '(1 1))  (/ (sin (/ pi 8.0)) (cos (/ pi 8.0))))
    (list "bulge of the same turn to the right is negative"
          '(tutc:bulge '(1 0) '(0 0) '(1 -1))  (- (/ (sin (/ pi 8.0)) (cos (/ pi 8.0)))))
    (list "bulge of a clockwise half circle is -1"
          '(tutc:bulge '(0 1) '(0 0) '(2 0))  -1.0)
    (list "bulge of a chord along the tangent is 0"
          '(tutc:bulge '(1 0) '(0 0) '(5 0))  0.0)
    (list "bulge with no tangent falls back to straight"
          '(tutc:bulge nil '(0 0) '(5 0))  0.0)
    (list "bulge of a zero-length chord is 0"
          '(tutc:bulge '(1 0) '(2 2) '(2 2))  0.0)
    (list "bulge caps a chord folding back at 2.98 rad"
          '(tutc:bulge '(1 0) '(0 0) '(-1 0.001))  (/ (sin 1.49) (cos 1.49)))))

(foreach c '("TUTORIALCPERPPTS")
  (setq *calofin-selftests*
        (cons (cons c 'tutc:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\ntutorial_cperp_points.lsp " *tutcperp-version*
                 " loaded.  Type TUTORIALCPERPPTS to run.")))
(princ)
