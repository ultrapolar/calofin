;;; ======================================================================
;;; POINTRENAMER.lsp  --  hand the point numbers back out in the order
;;;                       the perimeter runs
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  POINTRENAMER     renumber the highlighted survey points
;;;            POINTRENAMERVER  print the loaded version
;;; ======================================================================
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;  A survey comes back numbered in the order the crew shot it, which
;;;  is no order at all by the time the pool is drawn: Pt.3 sits across
;;;  the water from Pt.4 and the sheet reads like a scavenger hunt.
;;;  POINTRENAMER reprograms the numbers so they run round the pool.
;;;
;;;  Highlight the whole area.  The perimeter inside it is found (or
;;;  picked), you click where the count starts and say which way round
;;;  it goes, and every point sitting ON the perimeter -- or within the
;;;  band you allow off it, asked in feet-and-inches -- is renumbered
;;;  1, 2, 3... sweeping from that spot in that direction.  Whatever
;;;  the band does not catch (a spa shot, the equipment pad, a stray)
;;;  continues the count after the loop is closed, swept in the same
;;;  direction by where each sits against the perimeter, so the
;;;  leftovers read round the sheet too instead of jumping about.
;;;
;;;  WHAT COUNTS AS A POINT.  ABPCHECK's definition, unchanged: every
;;;  "ab_pt" block wherever it sits, and any other block on the POINTS
;;;  layer.  The number lives in the block's "number" attribute, or
;;;  failing that the first attribute holding something numeric -- the
;;;  same place every reader in this toolset looks.  A plain POINT
;;;  entity carries no number at all, so it is counted, said out loud
;;;  and left alone rather than silently skipped.
;;;
;;;  WHAT COUNTS AS THE PERIMETER.  The closed polyline on layer POOL
;;;  (the biggest one, when a pool and a spa share the layer) -- the
;;;  shape ABHD and LINGUTTER leave behind.  When the highlight holds
;;;  exactly one closed polyline on some other layer, that one is
;;;  offered instead.  Enter takes the found one; a click on any
;;;  polyline, circle, line or arc overrides it, so a spa ring or an
;;;  odd layer is one pick away.  Distance and position along it are
;;;  measured to the run itself, arcs included, not to its endpoints.
;;;
;;;  Clockwise means clockwise ON THE SHEET, whichever way the polyline
;;;  happens to have been drawn: the loop's own winding is measured
;;;  (bulges included) and the sweep runs against it when it has to.
;;;
;;;  Nothing is written until the split is shown and answered Yes, the
;;;  old-to-new table is printed so a callout can be chased afterwards,
;;;  and the whole renumber is one U.  A write that does not land -- a
;;;  locked POINTS layer is the everyday reason -- is named in the table
;;;  and counted at the end, never reported as a renumber that happened.
;;;
;;;  EVERY knob the tool has is in the TUNABLES block below, grouped and
;;;  explained; nothing past it is a value meant to be edited.
;;; ======================================================================

;;; -------------------- version -----------------------------------------
;;;  The banner form tools/release_lisp.py reads (lowercase name, "v",
;;;  one dot).  Bump it with every change and regenerate releases/.

(setq *pointrenamer-version* "v1.4")

;;; -------------------- tunables ----------------------------------------
;;;  Every knob the tool has, all of them here.
;;;  Past this block nothing is a bare number: every value the tool's
;;;  behaviour turns on is named here, with what it does and what moving
;;;  it costs.  Two ways to change one:
;;;
;;;    for good     edit the line here and re-APPLOAD the file
;;;    for one job  type (setq ptr:*band* 3.0) at the command line after
;;;                 loading -- it holds until the drawing closes
;;;
;;;  The groups, in the order you are likely to want them:
;;;
;;;    1  what counts as a point         4  what the report looks like
;;;    2  what counts as the perimeter   5  tolerances, named not tuned
;;;    3  what the questions start at
;;;
;;;  Every one of them is a literal the tool only ever READS, so what
;;;  stands here is what the file does.  The two answers carried between
;;;  runs -- the band and the direction -- are remembered in state of
;;;  their own below the block, seeded from the knobs here, so a run
;;;  cannot quietly overwrite the value you set.
;;;
;;;  One number is deliberately NOT here: the clamp inside the generic
;;;  tangent helper.  That helper is the shared library's, carried here
;;;  as a copy, and in the grouped build the library's own body is what
;;;  runs -- so a knob here would be read at one tier and ignored at the
;;;  other, which is worse than a number with a comment on it.

;; -- 1. what counts as a point ----------------------------------------

;; ABPCHECK's definition of a survey point, unchanged, so the two tools
;; never disagree about what they are looking at (its abp:*pt-layer* /
;; abp:*pt-block* / abp:*pt-tag*).  A block counts when it is NAMED
;; *pt-block*, wherever in the drawing it sits, or when it sits on
;; *pt-layer*, whatever it is named -- widen either and more blocks are
;; swept in.  A block with nowhere to write a number is counted out loud
;; and left alone whichever way it got here.
(setq ptr:*pt-layer* "POINTS")    ; layer whose blocks count as points
(setq ptr:*pt-block* "ab_pt")     ; block name that counts wherever it sits
(setq ptr:*pt-tag*   "number")    ; the attribute the number lives in

;; -- 2. what counts as the perimeter ----------------------------------

;; Where the perimeter is looked for before anything is asked: the
;; BIGGEST closed polyline on this layer inside the highlight.  Point it
;; at the spa's layer and a spa sheet needs no pick either.  When the
;; highlight holds no closed polyline on this layer but exactly one
;; anywhere, that one is offered instead -- and a click overrides
;; whatever was found, always.
(setq ptr:*perim-layer* "POOL")

;; What the highlight is allowed to keep, so a hatch or a dimension
;; cannot be dragged in by a sloppy window.  LINE and ARC are missing on
;; purpose: they are perfectly good perimeters, but only when clicked
;; for by name, never when swept up by the window.
(setq ptr:*filter* '((0 . "POINT,INSERT,LWPOLYLINE,POLYLINE")))

;; Which vertices of an old-style (heavy) POLYLINE are NOT on the drawn
;; curve, as a mask over the vertex flags (DXF group 70).  Bit 16 is a
;; spline FRAME control point: the curve is pulled toward it and never
;; through it, so walking the frame measures against a shape that is not
;; on the sheet.  Bits 1 and 8 are the opposite -- the extra vertices
;; curve- and spline-fitting ADD are the curve the sheet shows -- so
;; they are kept.  Set it to 17 to walk a fitted polyline by its control
;; points instead, as this tool did before v1.4.
(setq ptr:*vertex-skip* 16)

;; -- 3. what the questions start at -----------------------------------

;; How far off the perimeter still counts as on it -- what the FIRST run
;; of a session offers, before anyone has answered.  Later runs offer
;; the last answer instead (ptr:*band-now*, below).  Zero is refused at
;; the prompt (initget 6) -- to mean "only what is exactly on it",
;; answer a hair such as 1/16" rather than 0.  Inches, like every
;; distance here: 6.0 is six inches.
(setq ptr:*band* 6.0)

;; Which way round the FIRST run of a session offers, on the same
;; footing as the band.  Spelled exactly as the keywords are, because
;; this string IS the offered default: "Clockwise" or
;; "COunterclockwise", nothing else.
(setq ptr:*dir* "Clockwise")

;; The number the count starts at, offered at every run.  Unlike the
;; band and the direction this one is NOT carried between runs: a
;; renumber almost always starts at 1, and continuing someone else's
;; count is the exception you type.  Zero and negatives are refused.
(setq ptr:*first* 1)

;; The sysvars saved on the way in and put back on the way out, however
;; the run ends.  Add a name here if a change ever starts touching one.
(setq ptr:*sysvars* '("CMDECHO"))

;; -- 4. what the report looks like ------------------------------------

;; A start pick further than this off the perimeter is called out.  The
;; sweep still begins at the nearest spot on the run, but a pick this
;; far away is more often a mis-click than a corner.  Raise it to quiet
;; the note on a plan drawn at a large scale, lower it to be told about
;; a looser one.  Inches: 12.0 is a foot.
(setq ptr:*far-pick* 12.0)

;; The width the OLD number is padded to in the old-to-new table, so the
;; arrows line up.  Widen it for a survey that numbers its shots
;; "SW-CORNER-01" rather than "17".
(setq ptr:*name-width* 8)

;; How every distance in a prompt or a report is written -- the two
;; arguments of (rtos d MODE PRECISION).  Mode 4 is feet-and-inches,
;; which is what the sheets carry and what the crew reads back, and
;; precision 4 is a sixteenth.  Mode 2 precision 2 would print "6.00"
;; where this prints 0'-6".
(setq ptr:*dist-mode* 4)
(setq ptr:*dist-prec* 4)

;; -- 5. tolerances ----------------------------------------------------
;;  Named so that nothing in the code is an unexplained number, not so
;;  that they can be tuned: every one is a floating-point noise floor,
;;  in drawing units (inches).  Move one only with a reason.

;; Two spots closer together than this are the same spot -- the test for
;; whether a closed polyline's last vertex already sits on its first, so
;; the closing run is not laid down twice.
(setq ptr:*exact-eps* 1.0e-6)

;; A perimeter shorter than this has nothing to sweep, so it is refused
;; instead of divided by.
(setq ptr:*zero-len* 1.0e-6)

;; Below this a bulge is a straight line rather than an arc -- and so is
;; the chord under one, which the same floor guards, because the arc
;; math divides by both.
(setq ptr:*bulge-eps* 1.0e-9)

;; Below this a determinant has gone to zero: three points are collinear
;; and have no circumcentre, and an arc's sweep is a whole circle rather
;; than nothing at all.
(setq ptr:*flat-eps* 1.0e-10)

;; Below this a segment has no direction to project onto, so the nearest
;; spot on it is simply its start.  It is a length SQUARED, which is why
;; it is the square of the floors above.
(setq ptr:*tiny-len2* 1.0e-20)

;; How near a whole number a point's number has to read before the clash
;; sweep counts it as one.  A shot numbered "3.5" is not in the range
;; 1-10 in any sense a callout cares about, and neither is "3.0000001".
(setq ptr:*whole-eps* 1.0e-9)

;; Added to every station before it is wrapped round the loop, so that a
;; point clicked dead-on the start sorts FIRST instead of being wrapped
;; by floating-point noise to the far end of the sweep.  It has to be
;; bigger than that noise and far smaller than the gap between two shots
;; anyone would call separate.
(setq ptr:*start-whisker* 1.0e-4)

;;; -------------------- state -------------------------------------------
;;;  Not knobs: what a run writes down, seeded from the block above.  A
;;;  setting hoisted in here would advertise an initial value as a knob;
;;;  a knob left down here would be overwritten by the first run.

;; The band and the direction the last run of this session used, offered
;; as the default by the next one.  nil until a run has answered, and
;; the knobs above are what is offered until then.
(setq ptr:*band-now* nil)
(setq ptr:*dir-now* nil)


;;; -------------------- generic helpers ----------------------------------
;;;  The grouped build: the helpers come from CALOFIN-LIB.lsp.

;;; -------------------- tool-specific asks ------------------------------

;; Distance as every prompt and report writes it.
(defun ptr:dstr (d) (rtos d ptr:*dist-mode* ptr:*dist-prec*))

;; Which way round.  CW and CCW ride along ALL-CAPS and hidden, so they
;; must be typed in full and cannot steal a canonical hotkey; they are
;; normalized HERE, never downstream.  Returns the canonical keyword or
;; CAL-BACK.
(defun ptr:askdir (dflt / v)
  (setq v (cal:askkw "Number the points which way around?"
                     "Clockwise COunterclockwise CW CCW"
                     "Clockwise/COunterclockwise"
                     dflt T))
  (cond ((eq v 'CAL-BACK) v)
        ((= v "CW") "Clockwise")
        ((= v "CCW") "COunterclockwise")
        (t v)))

;; The band, as a distance.  A band is always needed, so there is no NA
;; here: Enter takes the remembered answer.  initget 6 rejects zero and
;; negatives, as a REQ measurement does.  Returns the number or
;; CAL-BACK.
(defun ptr:asklimit (msg dflt back / v)
  (if back (initget 6 "Back Undo") (initget 6))
  (setq v (getdist (strcat "\n" msg (if back " [Back]" "")
                           " <" (ptr:dstr dflt) ">: ")))
  (cond ((member v '("Back" "Undo")) 'CAL-BACK)
        ((null v) dflt)
        (t v)))

;; The first number to hand out.  A whole number, one or more; Enter
;; takes the default.  Returns the number or CAL-BACK.
(defun ptr:asknum (msg dflt back / v)
  (if back (initget 6 "Back Undo") (initget 6))
  (setq v (getint (strcat "\n" msg (if back " [Back]" "")
                          " <" (itoa dflt) ">: ")))
  (cond ((member v '("Back" "Undo")) 'CAL-BACK)
        ((null v) dflt)
        (t v)))


;;; -------------------- arc / segment geometry --------------------------
;;;  A segment is (startPt endPt bulge), 2D points -- ABHD's shape, by
;;;  way of ABPCHECK, where the distance-to-a-bulged-segment math is
;;;  already proven.  POINTRENAMER needs one thing more from every
;;;  segment: not just how FAR a point sits off it but WHERE along it
;;;  the closest spot lands, so the points can be put in walking order.

;; Center of the circle through three points; nil when they are
;; collinear.  (The 2-element form, since every point here is 2D.)
(defun ptr:circumcenter (pa pb pc / x1 y1 x2 y2 x3 y3 d s1 s2 s3)
  (setq x1 (car pa) y1 (cadr pa)
        x2 (car pb) y2 (cadr pb)
        x3 (car pc) y3 (cadr pc)
        d  (* 2.0 (+ (* x1 (- y2 y3)) (* x2 (- y3 y1)) (* x3 (- y1 y2)))))
  (if (< (abs d) ptr:*flat-eps*)
    nil
    (progn
      (setq s1 (+ (* x1 x1) (* y1 y1))
            s2 (+ (* x2 x2) (* y2 y2))
            s3 (+ (* x3 x3) (* y3 y3)))
      (list (/ (+ (* s1 (- y2 y3)) (* s2 (- y3 y1)) (* s3 (- y1 y2))) d)
            (/ (+ (* s1 (- x3 x2)) (* s2 (- x1 x3)) (* s3 (- x2 x1))) d)))))

;; Arc geometry of a bulged segment: (center radius angStart angEnd)
;; where the arc runs CCW from angStart to angEnd when bulge > 0 and CW
;; when bulge < 0.  nil for a straight segment -- and nil for a doubled
;; vertex under a bulge (a traced outline leaves those behind), where
;; there is nothing to sweep and the chord math would divide by zero.
(defun ptr:arc-geom (p1 p2 b / ch dir apex c)
  (if (< (abs b) ptr:*bulge-eps*)
    nil
    (progn
      (setq p1 (cal:2d p1)
            p2 (cal:2d p2)
            ch (cal:dist p1 p2))
      (if (< ch ptr:*bulge-eps*)
        nil
        (progn
          (setq dir  (cal:v* (cal:v- p2 p1) (/ 1.0 ch))
                ;; sagitta = (chord/2)*bulge; a positive (CCW) bulge
                ;; apex lies to the RIGHT of the p1->p2 chord direction
                apex (cal:v+ (cal:mid p1 p2)
                             (cal:v* (cal:perp dir) (* -0.5 ch b)))
                c    (ptr:circumcenter p1 apex p2))
          (if (null c)
            nil
            (list c (cal:dist c p1) (angle c p1) (angle c p2))))))))

;; Length of one segment: the chord for a straight run, radius times
;; sweep for a bulged one (falling back to the chord when the arc is
;; degenerate).
(defun ptr:seg-len (seg / p1 p2 b g)
  (setq p1 (car seg) p2 (cadr seg) b (caddr seg))
  (if (< (abs b) ptr:*bulge-eps*)
    (cal:dist p1 p2)
    (progn
      (setq g (ptr:arc-geom p1 p2 b))
      (if (null g)
        (cal:dist p1 p2)
        (* (cadr g)
           (if (> b 0.0)
             (cal:angnorm (- (cadddr g) (caddr g)))
             (cal:angnorm (- (caddr g) (cadddr g)))))))))

;; Point P against segment (p1 p2 bulge) of length SLEN: how far off it
;; P sits, and how far ALONG the segment (from its start) the closest
;; spot lands.  Straight: project onto the run and clamp to its ends.
;; Curved: radial when P falls inside the sweep, the nearer endpoint
;; when it does not.  Returns (distance . along).
(defun ptr:seg-near (p seg slen / p1 p2 b v w len2 t2 g c r a1 a2 ap
                       sweep rel d1 d2)
  (setq p  (cal:2d p)
        p1 (cal:2d (car seg))
        p2 (cal:2d (cadr seg))
        b  (caddr seg))
  (if (< (abs b) ptr:*bulge-eps*)
    (progn
      (setq v    (cal:v- p2 p1)
            w    (cal:v- p p1)
            len2 (cal:dot v v))
      (if (< len2 ptr:*tiny-len2*)
        (cons (cal:dist p p1) 0.0)
        (progn
          (setq t2 (/ (cal:dot w v) len2))
          (if (< t2 0.0) (setq t2 0.0))
          (if (> t2 1.0) (setq t2 1.0))
          (cons (cal:dist p (cal:v+ p1 (cal:v* v t2))) (* t2 slen)))))
    (progn
      (setq g (ptr:arc-geom (car seg) (cadr seg) b))
      (if (null g)
        (progn
          (setq d1 (cal:dist p p1) d2 (cal:dist p p2))
          (if (<= d1 d2) (cons d1 0.0) (cons d2 slen)))
        (progn
          (setq c  (car g)   r  (cadr g)
                a1 (caddr g) a2 (cadddr g)
                ap (angle c p))
          ;; rel is measured from the segment's OWN start (p1), with
          ;; the sweep, so (* r rel) is the walk from p1 to the foot
          (if (> b 0.0)
            (setq sweep (cal:angnorm (- a2 a1)) rel (cal:angnorm (- ap a1)))
            (setq sweep (cal:angnorm (- a1 a2)) rel (cal:angnorm (- a1 ap))))
          (if (<= rel sweep)
            (cons (abs (- (cal:dist p c) r)) (* r rel))
            (progn
              (setq d1 (cal:dist p p1) d2 (cal:dist p p2))
              (if (<= d1 d2) (cons d1 0.0) (cons d2 slen)))))))))

;; Signed area of the loop the segments trace (shoelace plus the
;; circular-segment correction every bulge adds), the drawn order
;; positive when it runs counter-clockwise.  An open run is closed by
;; the implicit chord back to its start -- zero-length when the loop
;; already closes -- so a polyline left unclosed still reports the way
;; it was drawn.
(defun ptr:loop-area (segs / a s p1 p2 b th ch r s0 e0)
  (setq a 0.0)
  (foreach s segs
    (setq p1 (cal:2d (car s))
          p2 (cal:2d (cadr s))
          b  (caddr s))
    (setq a (+ a (* 0.5 (- (* (car p1) (cadr p2))
                           (* (car p2) (cadr p1))))))
    (if (> (abs b) ptr:*bulge-eps*)
      (progn
        ;; bulge = tan(sweep/4); segment area = r^2/2 (th - sin th),
        ;; signed the way the bulge turns
        (setq th (* 4.0 (atan (abs b)))
              ch (cal:dist p1 p2))
        (if (> (abs (sin (/ th 2.0))) ptr:*flat-eps*)
          (progn
            (setq r (/ ch (* 2.0 (sin (/ th 2.0)))))
            (setq a (+ a (* (if (> b 0.0) 1.0 -1.0)
                            0.5 r r (- th (sin th))))))))))
  (if segs
    (progn
      (setq s0 (cal:2d (car (car segs)))
            e0 (cal:2d (cadr (last segs))))
      (setq a (+ a (* 0.5 (- (* (car e0) (cadr s0))
                             (* (car s0) (cadr e0))))))))
  a)

;; X into [0, M), for walking a station round a closed loop.
(defun ptr:wrap (x m)
  (if (<= m ptr:*zero-len*)
    0.0
    (progn
      (setq x (- x (* m (fix (/ x m)))))
      (if (< x 0.0) (+ x m) x))))

;; How far round the sweep a station S sits from the start station S0,
;; travelling WITH the drawn order when FWD and against it otherwise.
;; The whisker keeps a point clicked dead-on as the start FIRST instead
;; of letting floating-point noise wrap it to the far end of the loop.
(defun ptr:dirkey (s s0 len fwd)
  (ptr:wrap (+ (if fwd (- s s0) (- s0 s)) ptr:*start-whisker*) len))

;;; -------------------- entity -> segments ------------------------------

(defun ptr:lw-segs (ed / pts bls item segs n closed)
  ;; collect (10) vertices and their (42) bulges, in order
  (setq pts nil bls nil)
  (foreach item ed
    (cond
      ((= (car item) 10)
       (setq pts (cons (cal:2d (cdr item)) pts)
             bls (cons 0.0 bls)))
      ((and (= (car item) 42) bls)
       (setq bls (cons (cdr item) (cdr bls))))))
  (setq pts    (reverse pts)
        bls    (reverse bls)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        segs   nil
        n      0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  ;; the closing run exists only on a closed polyline, and only when
  ;; the last vertex is not already sitting on the first
  (if (and closed
           (> (length pts) 2)
           (> (cal:dist (last pts) (car pts)) ptr:*exact-eps*))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun ptr:pl-segs (en / ed sub pts bls segs n closed)
  ;; heavy (old-style) 2D POLYLINE: walk its VERTEX sub-entities
  (setq ed     (entget en)
        closed (= 1 (logand 1 (cdr (assoc 70 ed))))
        pts    nil
        bls    nil
        sub    (entnext en))
  (while (and sub (= "VERTEX" (cdr (assoc 0 (setq ed (entget sub))))))
    ;; skip the vertices that are not ON the drawn curve -- the spline
    ;; FRAME, by ptr:*vertex-skip*.  The curve- and spline-FIT vertices
    ;; are the curve the sheet shows and are walked with the rest.
    (if (= 0 (logand ptr:*vertex-skip*
                     (cond ((cdr (assoc 70 ed))) (0))))
      (setq pts (cons (cal:2d (cdr (assoc 10 ed))) pts)
            bls (cons (cond ((cdr (assoc 42 ed))) (0.0)) bls)))
    (setq sub (entnext sub)))
  (setq pts (reverse pts) bls (reverse bls) segs nil n 0)
  (while (< n (1- (length pts)))
    (setq segs (cons (list (nth n pts) (nth (1+ n) pts) (nth n bls)) segs)
          n    (1+ n)))
  ;; the same closing run lw-segs draws, under the same guard: a heavy
  ;; polyline whose last vertex already sits on its first would
  ;; otherwise carry a zero-length segment round the loop
  (if (and closed
           (> (length pts) 2)
           (> (cal:dist (last pts) (car pts)) ptr:*exact-eps*))
    (setq segs (cons (list (last pts) (car pts) (last bls)) segs)))
  (reverse segs))

(defun ptr:ent-segs (en / ed typ c r a1 a2 delta)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (cal:2d (cdr (assoc 10 ed)))
                 (cal:2d (cdr (assoc 11 ed)))
                 0.0)))
    ((= typ "ARC")
     (setq c     (cal:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           a1    (cdr (assoc 50 ed))
           a2    (cdr (assoc 51 ed))
           delta (cal:angnorm (- a2 a1)))
     (if (< delta ptr:*flat-eps*) (setq delta (* 2.0 pi)))
     ;; a full-circle arc cannot be one bulged segment (its bulge is
     ;; infinite): hand back two semicircles instead
     (if (> delta (- (* 2.0 pi) ptr:*bulge-eps*))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r) (cal:tan (/ delta 4.0))))))
    ((= typ "CIRCLE")
     (setq c (cal:2d (cdr (assoc 10 ed)))
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
    ((= typ "LWPOLYLINE") (ptr:lw-segs ed))
    ((= typ "POLYLINE") (ptr:pl-segs en))
    (T nil)))

;; The segments paired with their lengths, so a walk down the table
;; carries its own stations: ((seg . len) ...).
(defun ptr:seg-tab (segs / out s)
  (foreach s segs (setq out (cons (cons s (ptr:seg-len s)) out)))
  (reverse out))

(defun ptr:tab-len (tab / n r)
  (setq n 0.0)
  (foreach r tab (setq n (+ n (cdr r))))
  n)

;; Point P against the whole perimeter: the distance to the nearest
;; spot on it, and that spot's station -- the walk from the polyline's
;; own start, in its drawn order.  Returns (distance . station).
(defun ptr:measure (p tab / cum best r d)
  (setq cum 0.0 best nil)
  (foreach r tab
    (setq d (ptr:seg-near p (car r) (cdr r)))
    (if (or (null best) (< (car d) (car best)))
      (setq best (cons (car d) (+ cum (cdr d)))))
    (setq cum (+ cum (cdr r))))
  best)

;;; -------------------- ordering ----------------------------------------
;;;  A row is (key dist idx name attrEname insEname): key is the walk
;;;  from the start in the chosen direction, dist the offset from the
;;;  perimeter, idx the order the point was read.  Rows sort by key,
;;;  then dist, then idx, so two points sharing a station still land in
;;;  one deterministic order.  Insertion sort, not vl-sort -- vl-sort
;;;  drops elements its predicate calls equal, and two shots on the
;;;  same corner ARE equal by key.

(defun ptr:row< (a b)
  (cond ((< (car a) (car b)) T)
        ((> (car a) (car b)) nil)
        ((< (cadr a) (cadr b)) T)
        ((> (cadr a) (cadr b)) nil)
        (t (< (caddr a) (caddr b)))))

(defun ptr:ins-row (x lst)
  (cond ((null lst) (list x))
        ((ptr:row< x (car lst)) (cons x lst))
        (T (cons (car lst) (ptr:ins-row x (cdr lst))))))

(defun ptr:sort-rows (lst / out x)
  (foreach x lst (setq out (ptr:ins-row x out)))
  out)

;;; -------------------- reading the selection ---------------------------

;; Is this entity a survey point block?  ABPCHECK's definition, in ONE
;; place because two different sweeps ask it -- the highlight and the
;; clash check -- and a knob that only half of them read would warn
;; about the wrong points.  ED is the entity's data, which both callers
;; already hold.
(defun ptr:point-block-p (ed)
  (and (= "INSERT" (cdr (assoc 0 ed)))
       (or (= (strcase (cdr (assoc 2 ed))) (strcase ptr:*pt-block*))
           (= (strcase (cdr (assoc 8 ed))) (strcase ptr:*pt-layer*)))))

;; WHICH attribute of a point block gets the new number: the TAG one
;; when the block carries it, else the first attribute already holding
;; something numeric -- the same fallback ptr:block-number reads by, so
;; the number is written exactly where every reader will look.  Returns
;; the ATTRIB ename, or nil when the block has nowhere to take a number.
;; The attributes-follow flag (66) is checked first: this walk picks
;; the attribute a WRITE lands on, and an INSERT that owns no chain
;; must never claim a neighbour's.
(defun ptr:attr-target (en tag / sub ed val fall v)
  (if (/= 1 (cond ((cdr (assoc 66 (entget en)))) (0)))
    (setq sub nil)
    (setq sub (entnext en)))
  (setq val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase tag)))
      (setq val sub))
    (if (and (null fall) v (distof v 2))
      (setq fall sub))
    (setq sub (entnext sub)))
  (if val val fall))

;; Everything POINTRENAMER needs out of the highlight, in one pass:
;;   (points skipped candidate)
;; A point record is (idx inspt name attrEname insEname), in reading
;; order.  SKIPPED counts what carries no number to rewrite -- plain
;; POINTs and attribute-less blocks.  CANDIDATE is the perimeter Enter
;; will take: the biggest closed polyline on the perimeter layer, or,
;; failing that, the only closed polyline in the highlight.
(defun ptr:harvest (ss / i en ed typ lay att nm pts n nskip cand carea
                        nany lastc a)
  (setq pts nil n 0 nskip 0 cand nil carea 0.0 nany 0 lastc nil i 0)
  (while (< i (sslength ss))
    (setq en  (ssname ss i)
          ed  (entget en)
          i   (1+ i)
          typ (cdr (assoc 0 ed))
          lay (strcase (cdr (assoc 8 ed))))
    (cond
      ;; ab_pt blocks are survey points wherever they sit; other blocks
      ;; only count on the points layer
      ((ptr:point-block-p ed)
       (setq att (ptr:attr-target en ptr:*pt-tag*))
       (if att
         (setq n   (1+ n)
               nm  (cal:block-number en ptr:*pt-tag*)
               pts (cons (list n (cdr (assoc 10 ed)) nm att en) pts))
         (setq nskip (1+ nskip))))
      ;; a plain POINT is a survey point with no number to rewrite
      ((= typ "POINT") (setq nskip (1+ nskip)))
      ;; closed polylines are perimeter candidates
      ((and (member typ '("LWPOLYLINE" "POLYLINE"))
            (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0)))))
       (setq nany (1+ nany) lastc en)
       (if (= lay (strcase ptr:*perim-layer*))
         (progn
           (setq a (abs (ptr:loop-area (ptr:ent-segs en))))
           (if (or (null cand) (> a carea))
             (setq cand en carea a)))))))
  ;; no perimeter-layer loop, but exactly one closed polyline anywhere
  ;; in the highlight: that one is unambiguous, so offer it
  (if (and (null cand) (= nany 1)) (setq cand lastc))
  (list (reverse pts) nskip cand))

;; How many point blocks OUTSIDE the renamed set already carry a number
;; in [first, last] -- the collision the renumber cannot see, said out
;; loud instead of found at the next callout.  Only the current tab is
;; swept: a Layout1 detail reusing the numbers is not a clash.
(defun ptr:clash-count (renamed first lastn / ss i en ed att nm v n)
  (setq n 0
        ss (ssget "_X" (list '(0 . "INSERT") (cons 410 (getvar "CTAB")))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq en  (ssname ss i)
              ed  (entget en)
              i   (1+ i))
        (if (ptr:point-block-p ed)
          (progn
            (setq att (ptr:attr-target en ptr:*pt-tag*))
            (if (and att (not (member att renamed)))
              (progn
                (setq nm (cal:block-number en ptr:*pt-tag*)
                      v  (if nm (distof nm 2)))
                (if (and v
                         (equal v (float (fix v)) ptr:*whole-eps*)
                         (>= v (float first))
                         (<= v (float lastn)))
                  (setq n (1+ n))))))))))
  n)

;;; -------------------- writing the number ------------------------------

;; The one write the whole command makes: the new number into the point
;; block's attribute, and the block redisplayed so the sheet shows it.
;; entmod answers nil when it could NOT write -- a locked layer is the
;; everyday reason -- so its answer is carried back rather than assumed,
;; and the caller counts what never landed instead of printing a table
;; of renames that did not happen.  T when the number is on the sheet.
(defun ptr:set-number (att ins s / ed got)
  (setq ed  (entget att)
        got (entmod (subst (cons 1 s) (assoc 1 ed) ed)))
  (if got (progn (entupd ins) T)))

;;; -------------------- asking for the perimeter ------------------------

;; The perimeter pick.  Enter takes the candidate the highlight offered
;; (named by its layer in the prompt); a click takes any polyline,
;; circle, line or arc, in or out of the highlight.  Returns the ename,
;; or CAL-BACK to reopen the highlight.
(defun ptr:ask-perim (cand / v en done res)
  (while (not done)
    (initget "Back Undo")
    ;; ERRNO is sticky -- it holds whatever the last failing call left
    ;; there -- so it is cleared here and read immediately after the
    ;; pick.  The clear is wrapped because an engine that makes ERRNO
    ;; read-only would otherwise kill the command at its own prompt,
    ;; and not telling a mis-click from Enter is the smaller loss.
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (setq v (entsel
              (if cand
                (strcat "\nSelect the perimeter (Enter = the highlighted"
                        " closed polyline on "
                        (cdr (assoc 8 (entget cand))) ") [Back]: ")
                (strcat "\nSelect the perimeter (a polyline, circle,"
                        " line or arc) [Back]: "))))
    (cond
      ((member v '("Back" "Undo")) (setq done T res 'CAL-BACK))
      ;; entsel answers nil for Enter AND for a click that hit nothing.
      ;; ERRNO 7 is what tells them apart, and without asking, a click
      ;; that missed silently accepts the found perimeter -- the one
      ;; outcome the user was reaching past it to override.
      ((and (null v) (= 7 (getvar "ERRNO")))
       (princ (strcat "\nNothing there - click on the perimeter itself"
                      (if cand
                        ", or press Enter to take the one that was found."
                        "."))))
      ((and (null v) cand) (setq done T res cand))
      ((null v)
       (princ (strcat "\nThe highlight holds no closed polyline to fall"
                      " back on - select the perimeter itself.")))
      (t
       (setq en (car v))
       (if (null (ptr:ent-segs en))
         (princ (strcat "\nA " (cdr (assoc 0 (entget en)))
                        " cannot be the perimeter - pick a polyline,"
                        " circle, line or arc."))
         (setq done T res en)))))
  res)

;;; -------------------- the command -------------------------------------

(defun c:POINTRENAMER ( / *error* undo-open step quit go ss got recs
                          nskip cand res perim segs tab len area fwd
                          start s0 dir band first lastn near far order
                          row q d k n new renamed nhead i dirword clash
                          pick1 nfail nwrit ok)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (cal:sysrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nPOINTRENAMER error: " msg)))
    (princ))
  (cal:syssave ptr:*sysvars*)
  (setvar "CMDECHO" 0)
  ;; a highlight made before the command was typed (pickfirst), grabbed
  ;; before the undo group's command clears it - step 1 takes it once,
  ;; so coming Back re-asks interactively
  (setq pick1 (ssget "_I" ptr:*filter*))
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))
  (princ "\n\nPOINTRENAMER - hand the point numbers back out in the")
  (princ "\norder the perimeter runs.")
  (setq step 1 quit nil go nil)
  (while (and (not quit) (not go))
    (cond
      ;; ---- 1. the highlight --------------------------------------
      ((= step 1)
       (if pick1
         (setq ss pick1 pick1 nil)
         (progn
           (princ "\nHighlight the area to renumber (Enter = whole drawing): ")
           (setq ss (ssget ptr:*filter*))))
       ;; "whole drawing" is the tab you are looking at, the same scope
       ;; the clash check sweeps and the same one COVERCHECK and XFTCONV
       ;; use for this prompt: renumbering points in a layout you cannot
       ;; see -- and which the clash check would not even warn about --
       ;; is never what Enter was meant to say
       (if (null ss)
         (setq ss (ssget "_X" (append ptr:*filter*
                                      (list (cons 410 (getvar "CTAB")))))))
       (cond
         ((null ss)
          (princ "\nNothing to renumber - no points or polylines in the drawing.")
          (setq quit T))
         (t
          (setq got   (ptr:harvest ss)
                recs  (car got)
                nskip (cadr got)
                cand  (caddr got))
          (cond
            ((null recs)
             (princ (strcat "\nNo renumberable points in the highlight -"
                            " looked for \"" ptr:*pt-block* "\" blocks"
                            " anywhere and other blocks on layer "
                            ptr:*pt-layer* ", each with a number"
                            " attribute to rewrite."))
             (if (> nskip 0)
               (princ (strcat "\n(" (itoa nskip) " point(s) were seen"
                              " that carry no number at all - plain"
                              " POINTs, or blocks with no attribute.)")))
             (setq quit T))
            (t (setq step 2))))))
      ;; ---- 2. the perimeter --------------------------------------
      ((= step 2)
       (setq res (ptr:ask-perim cand))
       (cond
         ((eq res 'CAL-BACK) (setq step 1))
         (t
          (setq perim res
                segs  (ptr:ent-segs perim)
                tab   (ptr:seg-tab segs)
                len   (ptr:tab-len tab))
          (if (<= len ptr:*zero-len*)
            (progn
              ;; a candidate this broken has to stop being offered, or
              ;; Enter hands the same unusable loop back for ever
              (if (eq perim cand) (setq cand nil))
              (princ "\nThat perimeter has no length - pick another."))
            (progn
              (setq area (ptr:loop-area segs))
              (setq step 3))))))
      ;; ---- 3. where the count starts -----------------------------
      ((= step 3)
       (initget 1 "Back Undo")
       (setq res (getpoint
                   "\nPick the start point on the perimeter [Back]: "))
       (cond
         ((member res '("Back" "Undo")) (setq step 2))
         ((null res))                   ; initget 1 makes this unreachable
                                        ; at the command line; re-ask
         (t
          (setq start (ptr:measure res tab)
                s0    (cdr start))
          (if (> (car start) ptr:*far-pick*)
            (princ (strcat "\nNote: the pick sits " (ptr:dstr (car start))
                           " off the perimeter - the sweep starts at"
                           " the nearest spot on it.")))
          (setq step 4))))
      ;; ---- 4. which way round ------------------------------------
      ((= step 4)
       (setq res (ptr:askdir (if ptr:*dir-now* ptr:*dir-now* ptr:*dir*)))
       (cond
         ((eq res 'CAL-BACK) (setq step 3))
         (t (setq ptr:*dir-now* res
                  step 5))))
      ;; ---- 5. the band -------------------------------------------
      ((= step 5)
       (setq res (ptr:asklimit
                   "How far off the perimeter still counts as on it?"
                   (if ptr:*band-now* ptr:*band-now* ptr:*band*) T))
       (cond
         ((eq res 'CAL-BACK) (setq step 4))
         (t (setq ptr:*band-now* res
                  step 6))))
      ;; ---- 6. the first number -----------------------------------
      ((= step 6)
       (setq res (ptr:asknum "Start the numbering at" ptr:*first* T))
       (cond
         ((eq res 'CAL-BACK) (setq step 5))
         (t (setq first res
                  step 7))))
      ;; ---- 7. the split, shown before anything is written --------
      ((= step 7)
       ;; the sweep travels WITH the drawn vertex order exactly when
       ;; the direction asked for matches the loop's own winding
       ;; (counter-clockwise = positive area; a degenerate zero-area
       ;; run counts as drawn counter-clockwise)
       (setq fwd  (eq (= ptr:*dir-now* "COunterclockwise") (>= area 0.0))
             dir  ptr:*dir-now*
             band ptr:*band-now*
             near nil
             far  nil)
       (foreach q recs
         (setq d   (ptr:measure (cadr q) tab)
               k   (ptr:dirkey (cdr d) s0 len fwd)
               row (list k (car d) (car q) (caddr q)
                         (cadddr q) (nth 4 q)))
         (if (<= (car d) band)
           (setq near (cons row near))
           (setq far (cons row far))))
       (setq near  (ptr:sort-rows near)
             far   (ptr:sort-rows far)
             order (append near far)
             lastn (1- (+ first (length order))))
       (princ (strcat "\n\n" (itoa (length order)) " point(s) to"
                      " renumber: " (itoa (length near)) " within "
                      (ptr:dstr band) " of the perimeter, "
                      (itoa (length far)) " beyond it."))
       (if (> nskip 0)
         (princ (strcat "\n(" (itoa nskip) " more carry no number at"
                        " all - plain POINTs, or blocks with no"
                        " attribute - and are left alone.)")))
       (setq res (cal:askyn (strcat "Renumber them " (itoa first)
                                    " to " (itoa lastn) "?")
                            "No" T))
       (cond
         ((eq res 'CAL-BACK) (setq step 6))
         ((null res)
          (princ "\nNothing renamed.")
          (setq quit T))
         (t (setq go T))))))
  ;; ---- the write, in one pass, then the old-to-new table ----------
  (if go
    (progn
      (setq dirword (if (= dir "COunterclockwise")
                      "counterclockwise" "clockwise")
            n       first
            renamed nil
            nhead   (length near)
            i       0
            nfail   0)
      (foreach row order
        ;; the near heading only when something IS near: with an empty
        ;; band both headings used to print, back to back, over one list
        (if (and (= i 0) (> nhead 0))
          (princ (strcat "\nAround the perimeter (" dirword " from the"
                         " pick):")))
        (if (= i nhead)
          (princ (strcat "\nBeyond " (ptr:dstr band) " off the"
                         " perimeter (the count carries on, same"
                         " sweep):")))
        (setq new (itoa n)
              ok  (ptr:set-number (nth 4 row) (nth 5 row) new))
        (if ok
          (setq renamed (cons (nth 4 row) renamed))
          (setq nfail (1+ nfail)))
        ;; the row is printed either way, and a write that did not land
        ;; says so on its own line -- a table that shows a rename the
        ;; drawing never took is worse than no table at all
        (princ (strcat "\n  Pt. "
                       (cal:pad (if (and (nth 3 row) (/= (nth 3 row) ""))
                                  (nth 3 row) "?")
                                ptr:*name-width*)
                       "->  Pt. " new
                       (if ok "" "   NOT WRITTEN")))
        (setq n (1+ n) i (1+ i)))
      (setq nwrit (- (length order) nfail))
      (princ (strcat "\n" (itoa nwrit) " point(s) renumbered "
                     (itoa first) "-" (itoa lastn) "."))
      (if (> nfail 0)
        (princ (strcat "\nWarning: " (itoa nfail) " of them could not be"
                       " written and still carry their old number - the"
                       " layer they sit on is most likely locked."
                       "  Unlock it and run POINTRENAMER again.")))
      (setq clash (ptr:clash-count renamed first lastn))
      (if (> clash 0)
        (princ (strcat "\nWarning: " (itoa clash) " point(s) OUTSIDE"
                       " the highlight already carry a number between "
                       (itoa first) " and " (itoa lastn)
                       " - two points can now share a number.")))
      (princ "\nThe whole renumber is one U.")))
  (if undo-open
    (progn (command "_.UNDO" "_End") (setq undo-open nil)))
  (cal:sysrestore)
  (princ))

(defun c:POINTRENAMERVER ()
  (princ (strcat "\nPOINTRENAMER " *pointrenamer-version*))
  (princ))

(princ (strcat "\nPOINTRENAMER " *pointrenamer-version*
               " loaded.  Type POINTRENAMER to run."))
(princ)
