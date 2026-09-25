;;; ======================================================================
;;; SQUAREUP.lsp  --  turn a drawing until its perimeter's longest run
;;;                   is horizontal
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  SQUAREUP     highlight the work, pick the perimeter, and
;;;                         rotate the work square to it
;;;            SQUAREUPVER  print the loaded version
;;; ======================================================================
;;;
;;; A survey does not arrive square.  The tape is walked round the pool
;;; in whatever direction the deck allowed, the drone photo is taken
;;; from wherever the operator stood, and what lands in the drawing is
;;; a pool sitting four or five degrees off -- close enough to look
;;; deliberate, far enough that every horizontal dimension is a hair
;;; long and every AUTODIM run stands its text at an angle.  Squaring
;;; it up by eye is a ROTATE, a guess at the angle, an undo, and
;;; another guess.
;;;
;;; SQUAREUP measures the angle instead.  Two picks:
;;;
;;;   1. HIGHLIGHT THE WORK -- everything that has to turn together:
;;;      the outline, the bead track, the survey points, their number
;;;      labels, the notes.  Enter takes the whole drawing, which is
;;;      what a freshly imported survey usually is.
;;;   2. SELECT THE PERIMETER -- the one outline that says which way is
;;;      along.  It may be a single polyline or the loose lines and
;;;      arcs a traced perimeter comes in as.
;;;
;;; Then it says what it measured and turns the whole of (1) about the
;;; middle of (2) by the SMALLEST angle that gets there.  Smallest is
;;; the point: a wall lying at 176 degrees is put flat by turning 4,
;;; not by turning 176 and standing the drawing on its head.
;;;
;;; TWO THINGS CAN BE "THE LONGEST LENGTH", and which one is right
;;; depends on the pool, so both are measured and the answer is the
;;; drafter's:
;;;
;;;   Wall  the longest STRAIGHT RUN of the perimeter -- a rectangle
;;;         pool's long side.  A run split into five collinear pieces
;;;         by a trace is one wall, not five; a run that BOWS is not a
;;;         wall at all past the point where it has bent away from its
;;;         own start direction (sq:*collinear-deg*).
;;;   Span  the longest DISTANCE ACROSS the perimeter, corner to
;;;         corner -- the only answer a kidney or a freeform pool has,
;;;         since neither owns a straight line anywhere.
;;;
;;; Wall is the default and Span is the fallback: a perimeter with no
;;; straight run in it is squared to its span, and says so rather than
;;; asking a question with one answer.
;;;
;;; WHAT IT DOES NOT DO.  Nothing is scaled, mirrored, moved, drawn or
;;; erased, and no layer, colour or style is touched: the drawing that
;;; comes out is the drawing that went in, turned.  The turn is one
;;; ROTATE inside one undo group, so a single U puts it back.  A
;;; drawing already square -- under sq:*square-deg* off -- is left
;;; alone entirely rather than turned by a millionth of a degree,
;;; because a no-op that dirties the file is worse than no run at all.
;;;
;;; THE PERIMETER HAS TO BE PART OF THE WORK.  Picking an outline that
;;; is not among the highlighted objects would leave the one thing
;;; being measured standing where it was while everything else turned
;;; round it, so that is asked about before anything moves.
;;;
;;; HORIZONTAL MEANS HORIZONTAL ON THE SCREEN -- the current UCS's X
;;; axis, not the world's.  A drafter working under a rotated UCS
;;; means the direction they can see, so the measurement is taken in
;;; the UCS (entity points come out of the drawing in WCS or in their
;;; own OCS, and both are converted on the way in) and ROTATE turns in
;;; the same one.
;;; ======================================================================

(setq *squareup-version* "v1.3")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/

(vl-load-com)

;;; -------------------- tunables ----------------------------------------
;;; Everything a shop might want changed, all in one block; nothing
;;; settable lives anywhere else in this file.  Each says what CHANGING
;;; it does.  setq any of them after loading -- in a startup file, say
;;; -- and the next run reads the new value.

;; How many chords an arc is measured as when the SPAN is worked out.
;; Raise it and a big sweeping arc's widest point is found more exactly;
;; lower it and a perimeter of a hundred arcs measures faster.  It has
;; no effect on Wall, which reads straight runs only.
(setq sq:*arcsegs* 12)

;; How close two points have to be to count as the same one -- what
;; decides whether two straight pieces of perimeter TOUCH and so can be
;; one wall.  In drawing units.  A traced perimeter whose pieces do not
;; quite meet needs this raised; a tiny pool drawn in millimetres needs
;; it lowered.
(setq sq:*fuzz* 0.02)

;; How far two touching straight pieces may differ in direction, in
;; DEGREES, and still be read as one wall.  This is measured against
;; the direction of the run SO FAR, not the piece before, so a gently
;; bowing chain stops being one wall as soon as it has bent this far
;; from where it set off rather than creeping round a corner one
;; harmless degree at a time.
(setq sq:*collinear-deg* 1.0)

;; Under this many DEGREES out of square, the drawing is already
;; square and nothing is turned.  It is not a precision knob: it is
;; what stops a run that would change nothing from dirtying the file
;; and spending the drafter's undo.
(setq sq:*square-deg* 0.01)

;; When the runner-up wall is within this FRACTION of the longest one's
;; length and sq:*tie-deg* or more away in direction, the run says so:
;; the two are the same length to the tape and squaring to one of them
;; is a choice, not a measurement.  Raise it to be told about looser
;; ties, set it to 0 never to be told.
(setq sq:*tie-frac* 0.02)

;; How far apart in DEGREES two walls have to point before a tie
;; between them is worth mentioning.  Two long sides of a rectangle are
;; the same length and the same direction -- squaring to either gives
;; the same drawing, so that is not news.
(setq sq:*tie-deg* 2.0)

;; What the drawing turns ABOUT.  'perimeter is the middle of the
;; perimeter's extents, which keeps the pool where it is on screen and
;; swings the labels round it; 'work is the middle of everything
;; highlighted, which keeps the whole sheet centred instead.  Anything
;; else is read as 'perimeter.
(setq sq:*about* 'perimeter)

;;; ----------------------------------------------------------------------
;;;  END TUNABLES.  The sysvar list and its snapshot below are not
;;;  knobs: they are what the run puts back on the way out.
;; OSMODE leads the list because object snaps are the setting a drafter
;; misses most, and SQUAREUP really does mute them: the base point it
;; hands ROTATE is a computed one, and a running endpoint snap would
;; pull it onto whatever geometry happened to be near the middle of the
;; pool.  The angle three follow for the same reason -- ROTATE reads
;; its angle through AUNITS, ANGBASE and ANGDIR, so a drawing set to
;; surveyor's units or to clockwise angles would read the measured
;; number as something else entirely.  Borrow only what you move: every
;; one of these five is written by the run.
(setq sq:*sysvars* '("OSMODE" "CMDECHO" "AUNITS" "ANGBASE" "ANGDIR"))
(setq sq:*sysold* nil)                 ; the snapshot itself
(setq sq:*held* nil)                   ; layers thawed/unlocked for the turn
;;; ======================================================================

;;; -------------------- ask layer ---------------------------------------
;;; The STANDARDS section 4 reference helper: kws is BOTH the initget
;;; list and the bracket text, so the two cannot drift.

(defun sq:askkw (msg kws hidden dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (strcat kws
                   (if hidden (strcat " " hidden) "")
                   (if back " Back Undo" "")))
  (setq v (getkword (strcat "\n" msg " ["
                            (vl-string-translate " " "/" kws)
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'SQ-BACK)
        ((null v) (if dflt dflt (sq:askkw msg kws hidden dflt back)))
        (t v)))

;; Yes/No.  dflt is always shown; a destructive ask defaults "No".
(defun sq:askyn (msg dflt back / v)
  (setq v (sq:askkw msg "Yes No" nil dflt back))
  (if (eq v 'SQ-BACK) v (= v "Yes")))

;;; -------------------- sysvars -----------------------------------------
;;; CALOFIN-LIB's pair under this file's own prefix, copied rather than
;;; reworded (STANDARDS 4) -- the mirror swaps these two onto cal:, so a
;;; body that is merely EQUIVALENT is a body the two tiers can diverge
;;; on.  This one nearly did: a save written to refuse a whole snapshot
;;; that already stands, instead of refusing one VARIABLE that is
;;; already in it, also snapshots a sysvar getvar answers nil for -- and
;;; then "restores" that nil over the 0 the run wrote.  The library
;;; skips such a variable instead, so on a build where AUNITS does not
;;; exist the grouped tier left it written and the standalone one did
;;; not.  Same file, two behaviours, and only the sweep in
;;; tests/test_cancel_paths.py at BOTH tiers could see it.
;;;
;;; The per-variable refusal is what stops a second save mid-run
;;; capturing the muted OSMODE and putting 0 back for ever.

(defun sq:syssave (vars / v)
  (foreach v vars
    (if (and (not (assoc v sq:*sysold*))
             (/= nil (getvar v)))
        (setq sq:*sysold*
              (append sq:*sysold* (list (cons v (getvar v))))))))

(defun sq:sysrestore ( / p)
  ;; restored in the saved order, so OSMODE leads sq:*sysvars* -- and
  ;; the snapshot is dropped HERE, with nothing that can throw in front
  ;; of it, or a failed run would silence every later one
  (foreach p sq:*sysold* (setvar (car p) (cdr p)))
  (setq sq:*sysold* nil))

;;; -------------------- small 2D helpers --------------------------------
;;; Local copies of the generic library helpers, as the standalone tier
;;; needs (STANDARDS 4); the grouped twin calls cal: instead.

(defun sq:2d (p) (list (car p) (cadr p)))
(defun sq:dist (a b) (distance (sq:2d a) (sq:2d b)))

;; normalize an angle into [0, 2pi)
(defun sq:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;; distance between two folded directions, in [0, pi/2]
(defun sq:ang-diff (a b / d)
  (setq d (abs (- a b)))
  (min d (- pi d)))

;; Tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn bulge yields a huge but finite number instead
;; of dividing by zero.
(defun sq:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;; A LINE has no front and no back: the direction it lies along is the
;; same whichever end you start from, so every direction in this file
;; is folded into [0, pi) before it is compared to another.
(defun sq:dirfold (a)
  (setq a (sq:angnorm a))
  (if (>= a pi) (- a pi) a))

;; radians <-> degrees, spelled out rather than through angtos: the
;; number this file prints is a measurement of the drawing, and must
;; not change with the drafter's AUNITS.
(defun sq:deg (a) (/ (* 180.0 a) pi))
(defun sq:rad (d) (/ (* pi d) 180.0))

;; The turn that puts direction A flat, and the SMALLEST one: the
;; result is in [-pi/2, pi/2], so a wall at 176 degrees is squared by
;; turning 4 rather than by turning the drawing upside down.
(defun sq:turn (a)
  (setq a (sq:dirfold a))
  (if (<= a (* 0.5 pi)) (- a) (- pi a)))

;;; -------------------- reading the perimeter ---------------------------
;;; A perimeter arrives as spans: (p1 p2 bulge), the same shape OLAUTO
;;; walks.  A bulge of 0 is a straight piece and is what Wall is
;;; measured from; anything else is an arc and contributes to Span
;;; only.

;; Points on the bulged span from P1 to P2, N chords' worth, both ends
;; included.  The centre sits on the LEFT of the chord for a positive
;; (counterclockwise) bulge, at half the chord over the tangent of the
;; half-angle -- which is 0 for the half-turn bulge of 1, where the
;; centre IS the midpoint.
(defun sq:bulge-pts (p1 p2 b n / inc d half c r a1 i out)
  (setq d (sq:dist p1 p2))
  (if (or (null b) (< (abs b) 1e-8) (< d sq:*fuzz*) (< n 1))
    (list (sq:2d p1) (sq:2d p2))
    (progn
      (setq inc  (* 4.0 (atan b))              ; included angle, signed
            half (* 0.5 inc)
            r    (/ d (* 2.0 (abs (sin half))))
            c    (polar (list (* 0.5 (+ (car p1) (car p2)))
                              (* 0.5 (+ (cadr p1) (cadr p2))))
                        (+ (angle (sq:2d p1) (sq:2d p2)) (* 0.5 pi))
                        (/ (* 0.5 d) (sq:tan half)))
            a1   (angle c (sq:2d p1))
            i    0
            out  nil)
      (while (<= i n)
        (setq out (cons (polar c (+ a1 (* inc (/ (float i) (float n)))) r)
                        out)
              i   (1+ i)))
      (reverse out))))

;; The spans of an LWPOLYLINE, straight from its group codes: the 10s
;; are the vertices and the 42 beside each one is the bulge of the span
;; that LEAVES it.  A closed polyline's last span is the one back to
;; the first vertex and carries the last vertex's bulge.
(defun sq:lw-spans (en / ed closed pts bls cur nxt n out p ocs)
  (setq ed     (entget en)
        ocs    (sq:ocs-p ed "LWPOLYLINE")
        closed (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
        pts    nil
        bls    nil)
  (foreach p ed
    (cond ((= 10 (car p)) (setq pts (cons (sq:wcs (cdr p) en ocs) pts)
                                bls (cons 0.0 bls)))
          ((and (= 42 (car p)) bls) (setq bls (cons (cdr p) (cdr bls))))))
  (setq pts (reverse pts) bls (reverse bls) out nil)
  (setq cur pts nxt (cdr pts) n bls)
  (while nxt
    (setq out (cons (list (car cur) (car nxt) (car n)) out)
          cur nxt
          nxt (cdr nxt)
          n   (cdr n)))
  (if (and closed (> (length pts) 1)
           (>= (sq:dist (last pts) (car pts)) sq:*fuzz*))
    (setq out (cons (list (last pts) (car pts) (last bls)) out)))
  (reverse out))

;; The same for a heavy (old-style) 2D POLYLINE, whose vertices are
;; sub-entities.  Spline and fit control vertices (flag bits 1 and 16)
;; are not on the curve and are skipped.
(defun sq:pl-spans (en / ed sub closed pts bls cur nxt n out ocs)
  (setq ed     (entget en)
        ocs    (sq:ocs-p ed "POLYLINE")
        closed (= 1 (logand 1 (cond ((cdr (assoc 70 ed))) (0))))
        pts    nil
        bls    nil
        sub    (entnext en))
  (while (and sub (= "VERTEX" (cdr (assoc 0 (setq ed (entget sub))))))
    (if (= 0 (logand 17 (cond ((cdr (assoc 70 ed))) (0))))
      (setq pts (cons (sq:wcs (cdr (assoc 10 ed)) en ocs) pts)
            bls (cons (cond ((cdr (assoc 42 ed))) (0.0)) bls)))
    (setq sub (entnext sub)))
  (setq pts (reverse pts) bls (reverse bls) out nil)
  (setq cur pts nxt (cdr pts) n bls)
  (while nxt
    (setq out (cons (list (car cur) (car nxt) (car n)) out)
          cur nxt
          nxt (cdr nxt)
          n   (cdr n)))
  (if (and closed (> (length pts) 1)
           (>= (sq:dist (last pts) (car pts)) sq:*fuzz*))
    (setq out (cons (list (last pts) (car pts) (last bls)) out)))
  (reverse out))

;; An ELLIPSE off its own group codes: 10 is the centre, 11 the major
;; axis as a vector FROM it, 40 the minor/major ratio and 41/42 the
;; parameters it runs between.  Sampled rather than solved -- Span is
;; the only thing an ellipse can contribute and sq:*arcsegs* is what
;; says how finely.
(defun sq:ellipse-pts (en / ed c mj rat p0 p1 n i t0 a b ang out)
  (setq ed  (entget en)
        c   (sq:wcs (cdr (assoc 10 ed)) en (sq:ocs-p ed "ELLIPSE"))
        mj  (cdr (assoc 11 ed))
        rat (cond ((cdr (assoc 40 ed))) (1.0))
        p0  (cond ((cdr (assoc 41 ed))) (0.0))
        p1  (cond ((cdr (assoc 42 ed))) (+ pi pi))
        n   (* 4 (max 1 sq:*arcsegs*))
        a   (sqrt (+ (* (car mj) (car mj)) (* (cadr mj) (cadr mj))))
        ang (angle '(0.0 0.0) (sq:2d mj))
        b   (* a rat)
        i   0
        out nil)
  (while (<= i n)
    (setq t0  (+ p0 (* (- p1 p0) (/ (float i) (float n))))
          out (cons (list (+ (car c)
                             (* a (cos t0) (cos ang))
                             (- (* b (sin t0) (sin ang))))
                          (+ (cadr c)
                             (* a (cos t0) (sin ang))
                             (* b (sin t0) (cos ang))))
                    out)
          i   (1+ i)))
  (reverse out))

;; A SPLINE, sampled along its own length.  vlax-curve is what knows
;; the curve, so it is asked first; where it cannot answer (an engine
;; without it, a degenerate spline) the fit points fall back to -- they
;; at least LIE on the curve, which the control points in group 10 do
;; not, so those are the last resort and only because a hull that is
;; too big is better than no measurement at all.
(defun sq:spline-pts (en / len n i out p ed)
  (setq len (vl-catch-all-apply 'vlax-curve-getdistatparam
                                (list en (vl-catch-all-apply
                                           'vlax-curve-getendparam
                                           (list en)))))
  (if (and (numberp len) (> len 0.0))
    (progn
      (setq n (* 4 (max 1 sq:*arcsegs*)) i 0 out nil)
      (while (<= i n)
        (setq p (vl-catch-all-apply 'vlax-curve-getpointatdist
                                    (list en (* len (/ (float i) (float n))))))
        (if (listp p) (setq out (cons (sq:2d p) out)))
        (setq i (1+ i)))
      (reverse out))
    (progn
      (setq ed  (entget en)
            out nil)
      (foreach p ed
        (if (= 11 (car p)) (setq out (cons (sq:2d (cdr p)) out))))
      (if (null out)
        (foreach p ed
          (if (= 10 (car p)) (setq out (cons (sq:2d (cdr p)) out)))))
      (reverse out))))

;; T when ENT keeps its points in its OWN plane rather than the world's
;; -- an ARC, CIRCLE, ELLIPSE or polyline carrying a 210 that is not
;; the world Z.  A LINE's points are world whatever its extrusion says,
;; which is the DXF reference's split and not a guess.  Asked ONCE per
;; entity, because the alternative is an entget for every vertex and a
;; traced perimeter carries hundreds.  A flat drawing -- every drawing
;; this build makes -- carries no 210 at all and answers nil here, so
;; the per-point transform below never runs.
(defun sq:ocs-p (ed typ / n)
  (and (member typ '("ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE"))
       (setq n (cdr (assoc 210 ed)))
       (not (and (equal (car n) 0.0 1e-10)
                 (equal (cadr n) 0.0 1e-10)
                 (> (caddr n) 0.0)))))

;; A point out of ENT's group codes, in the WCS.  OCS is what sq:ocs-p
;; answered for the entity the point came off.
(defun sq:wcs (p en ocs)
  (if ocs (trans p en 0) (sq:2d p)))

;; NOT A KNOB: the entity types the perimeter selection admits, which
;; is exactly the set the cond below can read.  Adding a name here does
;; not teach sq:ent-spans that type -- it lets one through that
;; measures as nothing and contributes no direction at all.
(setq sq:*curvetypes*
  "LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE")

;; The spans of one entity, or nil when it carries none.
(defun sq:ent-spans (en / ed typ ocs c r a1 a2 delta)
  (setq ed  (entget en)
        typ (cdr (assoc 0 ed))
        ocs (sq:ocs-p ed typ))
  (cond
    ((= typ "LINE")
     (list (list (sq:wcs (cdr (assoc 10 ed)) en ocs)
                 (sq:wcs (cdr (assoc 11 ed)) en ocs)
                 0.0)))
    ((= typ "ARC")
     (setq c     (sq:wcs (cdr (assoc 10 ed)) en ocs)
           r     (cdr (assoc 40 ed))
           a1    (cdr (assoc 50 ed))
           a2    (cdr (assoc 51 ed))
           delta (sq:angnorm (- a2 a1)))
     (if (< delta 1.0e-10) (setq delta (+ pi pi)))
     ;; a full-circle arc cannot be one bulged span (its bulge is
     ;; infinite): two semicircles instead
     (if (> delta (- (+ pi pi) 1.0e-9))
       (list (list (polar c a1 r) (polar c (+ a1 pi) r) 1.0)
             (list (polar c (+ a1 pi) r) (polar c a1 r) 1.0))
       (list (list (polar c a1 r) (polar c a2 r)
                   (sq:tan (/ delta 4.0))))))
    ;; a CIRCLE is a legitimate perimeter (a round spa): two
    ;; semicircles, so the walk sees a closed loop instead of a gap
    ((= typ "CIRCLE")
     (setq c (sq:wcs (cdr (assoc 10 ed)) en ocs)
           r (cdr (assoc 40 ed)))
     (list (list (polar c 0.0 r) (polar c pi r) 1.0)
           (list (polar c pi r) (polar c 0.0 r) 1.0)))
    ((= typ "LWPOLYLINE") (sq:lw-spans en))
    ((= typ "POLYLINE") (sq:pl-spans en))
    (T nil)))

;; The sampled points of a run of spans, span by span.  Each span's
;; points are one chunk, and the chunks are joined once at the end
;; rather than the growing list being copied again for every span.
(defun sq:spans-pts (spans / s chunks)
  (setq chunks nil)
  (foreach s spans
    (setq chunks (cons (sq:bulge-pts (car s) (cadr s) (caddr s)
                                     sq:*arcsegs*)
                       chunks)))
  (apply 'append (reverse chunks)))

;; The sampled points of one entity -- what SPAN is measured over.  The
;; two curve types with no spans of their own answer here and nowhere
;; else.
(defun sq:ent-pts (en / typ)
  (setq typ (cdr (assoc 0 (entget en))))
  (cond
    ((= typ "ELLIPSE") (sq:ellipse-pts en))
    ((= typ "SPLINE")  (sq:spline-pts en))
    (t (sq:spans-pts (sq:ent-spans en)))))

;;; -------------------- locked and frozen layers -------------------------
;;; ROTATE SKIPS AN OBJECT ON A LOCKED OR FROZEN LAYER, and says
;;; nothing about it.  A run that ignored that would turn the outline
;;; and leave the base plan it was traced over lying at the old angle
;;; -- half a drawing squared and half not, which is worse than a
;;; drawing that was never squared at all, because the second is
;;; obvious and the first is not.  (A layer that is merely OFF is not
;;; in this: its objects are invisible but every editing command still
;;; works on them.)
;;;
;;; So both bits are cleared for the length of the turn and put back
;;; exactly as they were, on the failed path too.  sq:*held* is the
;;; record of what was borrowed -- run state, not a setting, which is
;;; why it sits beside the sysvar snapshot and not in the tunables.

;; Clear the lock (4) and freeze (1) bits on every layer SS touches,
;; remembering the flags each one arrived with.
(defun sq:free-layers (ss / i lay seen rec ed flags)
  (setq i 0 seen nil)
  (while (< i (sslength ss))
    (setq lay (cdr (assoc 8 (entget (ssname ss i)))))
    (if (and lay (not (member (strcase lay) seen)))
      (progn
        (setq seen (cons (strcase lay) seen)
              rec  (tblobjname "LAYER" lay))
        (if rec
          (progn
            (setq ed    (entget rec)
                  flags (cond ((cdr (assoc 70 ed))) (0)))
            (if (/= 0 (logand 5 flags))
              (progn
                (entmod (subst (cons 70 (- flags (logand 5 flags)))
                               (assoc 70 ed) ed))
                (setq sq:*held*
                      (cons (cons lay flags) sq:*held*))))))))
    (setq i (1+ i)))
  sq:*held*)

;; ...and put every one of them back the way it was found.
(defun sq:restore-layers ( / p rec ed)
  (foreach p sq:*held*
    (setq rec (tblobjname "LAYER" (car p)))
    (if rec
      (progn
        (setq ed (entget rec))
        (entmod (subst (cons 70 (cdr p)) (assoc 70 ed) ed)))))
  (setq sq:*held* nil))

;;; -------------------- walls -------------------------------------------

;; The two endpoints of the union of straight spans A and B that are
;; furthest apart: the wall the two of them make.
(defun sq:span-union (a b / ps best bd p q d)
  (setq ps   (list (car a) (cadr a) (car b) (cadr b))
        bd   -1.0
        best (list (car a) (cadr a)))
  (foreach p ps
    (foreach q ps
      (setq d (sq:dist p q))
      (if (> d bd) (setq bd d best (list p q)))))
  (list (car best) (cadr best) 0.0))

;; T when two straight spans are one wall: they touch at an end, and
;; they lie along the same line.  The direction compared is the whole
;; of A's, so a run that has already bent stops taking pieces on.
(defun sq:joins-p (a b / tol)
  (setq tol (sq:rad sq:*collinear-deg*))
  (and (or (< (sq:dist (cadr a) (car b))  sq:*fuzz*)
           (< (sq:dist (cadr a) (cadr b)) sq:*fuzz*)
           (< (sq:dist (car a)  (car b))  sq:*fuzz*)
           (< (sq:dist (car a)  (cadr b)) sq:*fuzz*))
       (< (sq:ang-diff (sq:dirfold (angle (car a) (cadr a)))
                       (sq:dirfold (angle (car b) (cadr b))))
          tol)))

;; Straight spans folded into walls: every collinear chain that touches
;; end to end becomes the one span running from one extreme of it to
;; the other, whichever entity each piece came off.  A perimeter traced
;; as forty short segments has four walls, not forty.
;;
;; keep is gathered backwards and turned round once per pass, so rest
;; is exactly the old order less the one span the pass merged -- the
;; order matters, because the next pass takes the FIRST span that joins.
(defun sq:merge-walls (spans / out a rest hit keep b)
  (setq out nil)
  (while spans
    (setq a    (car spans)
          rest (cdr spans)
          hit  T)
    (while hit
      (setq hit nil keep nil)
      (foreach b rest
        (if (and (not hit) (sq:joins-p a b))
          (setq a   (sq:span-union a b)
                hit T)
          (setq keep (cons b keep))))
      (setq rest (reverse keep)))
    (setq out   (cons a out)
          spans rest))
  (reverse out))

;; (length direction p1 p2) per wall, longest first.  Spans shorter
;; than the fuzz are not walls -- a zero-length one has no direction to
;; read at all.
(defun sq:walls (spans / straight s out)
  (setq straight nil)
  ;; both lists are gathered backwards and turned round once, so each
  ;; is in the order its source is in -- merge-walls and the sort below
  ;; see exactly what they always did
  (foreach s spans
    (if (and (or (null (caddr s)) (< (abs (caddr s)) 1e-8))
             (>= (sq:dist (car s) (cadr s)) sq:*fuzz*))
      (setq straight (cons s straight))))
  (foreach s (sq:merge-walls (reverse straight))
    (if (>= (sq:dist (car s) (cadr s)) sq:*fuzz*)
      (setq out (cons (list (sq:dist (car s) (cadr s))
                            (sq:dirfold (angle (car s) (cadr s)))
                            (car s) (cadr s))
                      out))))
  (vl-sort (reverse out) '(lambda (p q) (> (car p) (car q)))))

;;; -------------------- the span ----------------------------------------
;;; The widest measurement across a set of points is between two of its
;;; CONVEX HULL's corners and never anywhere else, so the hull is taken
;;; first: a traced perimeter of three hundred points has a hull of a
;;; dozen, and twelve times twelve is a measurement instead of a wait.

;; (a-o) x (b-o): positive when o->a->b turns left.
(defun sq:cross3 (o a b)
  (- (* (- (car a) (car o)) (- (cadr b) (cadr o)))
     (* (- (cadr a) (cadr o)) (- (car b) (car o)))))

;; One chain of Andrew's monotone hull over PTS, already sorted.
(defun sq:halfhull (pts / st p)
  (setq st nil)
  (foreach p pts
    (while (and (cdr st) (<= (sq:cross3 (cadr st) (car st) p) 0.0))
      (setq st (cdr st)))
    (setq st (cons p st)))
  st)

;; The hull's corners.  Order is not promised and is not needed -- what
;; comes back is the small set of points the widest measurement can
;; possibly run between, and the two ends appear in both chains.
(defun sq:hull (pts / srt)
  (setq srt (vl-sort (mapcar 'sq:2d pts)
                     '(lambda (p q)
                        (if (equal (car p) (car q) 1e-12)
                          (< (cadr p) (cadr q))
                          (< (car p) (car q))))))
  (if (< (length srt) 3)
    srt
    (append (sq:halfhull srt) (sq:halfhull (reverse srt)))))

;; (length direction p1 p2) for the widest measurement across PTS, or
;; nil when there is nothing to measure.
(defun sq:span (pts / h bd best p q d)
  (setq h (sq:hull pts) bd -1.0)
  (foreach p h
    (foreach q h
      (setq d (sq:dist p q))
      (if (> d bd) (setq bd d best (list p q)))))
  (if (and best (> bd sq:*fuzz*))
    (list bd (sq:dirfold (angle (car best) (cadr best)))
          (car best) (cadr best))))

;; The middle of a set of points' extents.
(defun sq:middle (pts / xs ys)
  (if pts
    (progn
      (setq xs (mapcar 'car (mapcar 'sq:2d pts))
            ys (mapcar 'cadr (mapcar 'sq:2d pts)))
      (list (* 0.5 (+ (apply 'min xs) (apply 'max xs)))
            (* 0.5 (+ (apply 'min ys) (apply 'max ys)))))))

;; Every sampled point of a selection, and every span of it.  An
;; entity's spans are built ONCE and its points sampled off them; one
;; with no spans -- an ELLIPSE or a SPLINE, which answer only for
;; points -- is sampled by sq:ent-pts.  Each entity's points and spans
;; are one chunk apiece, joined once at the end in entity order.
(defun sq:read-ss (ss / i en s pchunks schunks)
  (setq i 0 pchunks nil schunks nil)
  (while (< i (sslength ss))
    (setq en      (ssname ss i)
          s       (sq:ent-spans en)
          pchunks (cons (if s (sq:spans-pts s) (sq:ent-pts en)) pchunks)
          schunks (cons s schunks)
          i       (1+ i)))
  (list (apply 'append (reverse pchunks))
        (apply 'append (reverse schunks))))

;; Every sampled point of a selection and nothing else -- what the
;; middle of the whole highlight is taken over, which has no use for
;; the spans sq:read-ss would build alongside.
(defun sq:read-pts (ss / i chunks)
  (setq i 0 chunks nil)
  (while (< i (sslength ss))
    (setq chunks (cons (sq:ent-pts (ssname ss i)) chunks)
          i      (1+ i)))
  (apply 'append (reverse chunks)))

;;; -------------------- saying what it measured -------------------------

;; A length in the drawing's own units, as the drafter has set them up
;; to read.
(defun sq:len (d) (rtos d))

;; A signed angle in degrees, two places, always with its sign so a
;; turn reads as a turn.
(defun sq:ang (a / d s)
  (setq d (sq:deg a)
        s (if (< d 0.0) "-" "+"))
  (strcat s (rtos (abs d) 2 2)))

;; Which way a turn goes, in words: the sign of a rotation is the one
;; thing nobody reads off a number correctly at a glance.
(defun sq:way (a)
  (if (< a 0.0) "clockwise" "counterclockwise"))

;; The wall that is as long as the longest one but points somewhere
;; else, or nil.  A rectangle's two long sides are the same length AND
;; the same direction, so they are not a tie worth reporting -- both
;; give the same drawing.
(defun sq:tie (walls / best out w)
  (setq best (car walls))
  (if (and best (> sq:*tie-frac* 0.0) (> (car best) 0.0))
    (foreach w (cdr walls)
      (if (and (null out)
               (<= (- (car best) (car w)) (* sq:*tie-frac* (car best)))
               (>= (sq:ang-diff (cadr best) (cadr w))
                   (sq:rad sq:*tie-deg*)))
        (setq out w))))
  out)

;;; -------------------- the run -----------------------------------------

;; The space the drafter is drawing in: model space from the Model tab
;; or from inside a layout's viewport, the layout itself only when its
;; paper is active.  CTAB alone is wrong from a viewport.  Enter = the
;; whole drawing sweeps only this: a bare "_X" pulled the title block
;; and viewports in too, which ROTATE skips as not in the current
;; space -- while the done line counted them turned and the locked
;; VIEWPORT layer was reported freed for a turn it was never part of.
(defun sq:space ()
  (if (= 1 (getvar "CVPORT")) (getvar "CTAB") "Model"))

(defun sq:run ( / work per read pts spans walls wall span pick chosen
                  turn about wpts tie)

  ;; What turns: the highlight if there is one, else what is picked at
  ;; the prompt, else the whole drawing.  An imported survey usually IS
  ;; the whole drawing, which is why Enter means that.
  (setq work (ssget "_I"))
  (if lzd:watch (lzd:watch work) work)
  (if (null work)
    (progn
      (prompt "\nHighlight the drawing to square up <Enter = whole drawing>: ")
      (setq work (ssget))
      (if lzd:watch (lzd:watch work) work)
      (if (null work)
        (setq work (ssget "_X" (list (cons 410 (sq:space))))))))

  (if (null work)
    (princ "\nSQUAREUP: there is nothing in this drawing to turn.")
    (progn
      ;; and what says which way is along.  Only the curve types carry
      ;; a direction, so the filter keeps a stray label or point out of
      ;; the measurement rather than letting it quietly contribute a
      ;; corner to the span.
      (prompt "\nSelect the perimeter that sets the direction: ")
      (setq per (ssget (list (cons 0 sq:*curvetypes*))))
      (if lzd:watch (lzd:watch per) per)

      (if (null per)
        (princ (strcat "\nSQUAREUP: no perimeter picked - nothing turned."
                       "\n  It wants one outline (or the loose lines and arcs"
                       " of one) to measure."))
        (progn
          (setq read  (sq:read-ss per)
                pts   (mapcar '(lambda (p) (trans p 0 1)) (car read))
                spans (mapcar '(lambda (s)
                                 (list (trans (car s) 0 1)
                                       (trans (cadr s) 0 1)
                                       (caddr s)))
                              (cadr read))
                walls (sq:walls spans)
                wall  (car walls)
                span  (sq:span pts))

          (cond
            ((null span)
             (princ (strcat "\nSQUAREUP: that perimeter has no size - every"
                            " point of it is in one spot, so there is no"
                            "\n  direction to square to.")))
            (t
             ;; say what was measured before asking which of it to use:
             ;; the choice is between two numbers, and a drafter who
             ;; cannot see them is guessing
             (if wall
               (princ (strcat "\nSQUAREUP: the longest wall is "
                              (sq:len (car wall)) " at "
                              (sq:ang (cadr wall)) " degrees; the longest"
                              " span is\n  " (sq:len (car span)) " at "
                              (sq:ang (cadr span)) " degrees."))
               (princ (strcat "\nSQUAREUP: that perimeter has no straight run"
                              " in it, so there is no wall to\n  square to."
                              "  Its longest span is " (sq:len (car span))
                              " at " (sq:ang (cadr span)) " degrees.")))
             (if (setq tie (sq:tie walls))
               (princ (strcat "\n  Another wall is within "
                              (sq:len (- (car wall) (car tie)))
                              " of the longest and points "
                              (rtos (sq:deg (sq:ang-diff (cadr wall)
                                                         (cadr tie))) 2 1)
                              " degrees\n  away, so which one squares the"
                              " drawing is a choice and not a measurement.")))

             (setq pick (if wall
                          (sq:askkw "What should end up horizontal?"
                                    "Wall Span" nil "Wall" nil)
                          "Span"))
             (setq chosen (if (= pick "Wall") wall span)
                   turn   (sq:turn (cadr chosen)))

             ;; what it turns about: the middle of the perimeter's
             ;; extents, so the pool stays where it is on screen and
             ;; the labels swing round it -- or the middle of the whole
             ;; highlight, when sq:*about* says so.  A highlight with
             ;; no measurable geometry in it (all text, all points) has
             ;; no middle of its own and falls back to the perimeter's.
             (setq wpts  (if (eq sq:*about* 'work)
                           (sq:middle (mapcar '(lambda (p) (trans p 0 1))
                                              (sq:read-pts work))))
                   about (if wpts wpts (sq:middle pts)))

             ;; Already square comes FIRST, ahead of the question
             ;; below: there is no turn to confirm, so asking about one
             ;; would be a question whose two answers do the same
             ;; thing.  And the perimeter has to be part of what turns,
             ;; or the one thing being measured stands still while the
             ;; rest of the drawing swings round it.
             (cond
               ((< (abs (sq:deg turn)) sq:*square-deg*)
                (princ (strcat "\nSQUAREUP: that " (strcase pick T)
                               " is already horizontal to within "
                               (rtos sq:*square-deg* 2 3)
                               " degrees -\n  nothing turned.")))
               ((sq:outside-p per work)
                (princ (strcat "\nSQUAREUP: the perimeter is not among the"
                               " objects you highlighted, so it would"
                               "\n  stand still while everything else turned"
                               " round it."))
                (if (sq:askyn "Turn the highlighted objects anyway?" "No" nil)
                  (sq:turn-it work turn about (car chosen) pick)
                  (princ "\nSQUAREUP: nothing turned.")))
               (t (sq:turn-it work turn about (car chosen) pick)))))))))
  (princ))

;; T when any of the perimeter is outside the work.
(defun sq:outside-p (per work / i out)
  (setq i 0 out nil)
  (while (< i (sslength per))
    (if (not (ssmemb (ssname per i) work)) (setq out T))
    (setq i (1+ i)))
  out)

;; The turn itself, and the one line that says what happened.  ROTATE
;; reads its angle in degrees here because AUNITS, ANGBASE and ANGDIR
;; were all zeroed at the top of the command -- a drawing set to
;; clockwise angles would otherwise turn the measured number the wrong
;; way and look, to the drafter, like a tool that cannot do arithmetic.
(defun sq:turn-it (work turn about len pick / n)
  (setvar "OSMODE" 0)
  (setq n (length (sq:free-layers work)))
  (command "_.ROTATE" work "" "_non" about (sq:deg turn))
  (sq:restore-layers)
  (princ (strcat "\nSQUAREUP done: " (itoa (sslength work))
                 " object(s) turned " (rtos (abs (sq:deg turn)) 2 2)
                 " degrees " (sq:way turn) ","))
  (princ (strcat "\n  so the perimeter's longest " (strcase pick T) " ("
                 (sq:len len) ") is horizontal.  U puts it back."))
  (if (> n 0)
    (princ (strcat "\n  " (itoa n) " locked or frozen layer(s) were freed"
                   " for the turn and put straight back - ROTATE"
                   "\n  skips an object on either, and half a drawing"
                   " squared is worse than none.")))
  (princ))

;;; -------------------- the commands ------------------------------------

(defun c:SQUAREUP ( / *error* undo-open)
  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them --
    ;; OSMODE leads the list, and a setvar cannot throw
    (sq:sysrestore)
    ;; then the layers the run borrowed, before the undo group closes
    ;; over them -- entmod on a layer record can throw, so it is caught
    (vl-catch-all-apply 'sq:restore-layers '())
    ;; command-s, never plain command: a 2015+ engine rejects (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSQUAREUP error: " msg)))
    (if lzd:report (lzd:report "SQUAREUP" *squareup-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "SQUAREUP" *squareup-version*))
  (sq:syssave sq:*sysvars*)
  (setvar "CMDECHO" 0)
  ;; the angle three, so the number handed to ROTATE below is read as
  ;; the decimal degrees it is
  (setvar "AUNITS" 0)
  (setvar "ANGBASE" 0.0)
  (setvar "ANGDIR" 0)
  ;; opened only when undo is recording: _Begin in a drawing whose
  ;; UNDOCTL has bit 1 clear errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))
  (sq:run)
  (if undo-open
    (progn
      (command "_.UNDO" "_End")
      (setq undo-open nil)))
  (sq:sysrestore)
  (if lzd:end (lzd:end "SQUAREUP"))
  (princ))

(defun c:SQUAREUPVER ()
  (princ (strcat "\nSQUAREUP " *squareup-version* " loaded."))
  (princ))

;;; -------------------- self tests --------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun sq:selftests ()
  (list
    (list "angnorm folds -90 into [0, 2pi)"     '(sq:angnorm (- (* 0.5 pi)))  (* 1.5 pi))
    (list "angnorm brings a full turn to 0"     '(sq:angnorm (* 2.0 pi))      0.0)
    (list "dirfold makes 190 read as 10 degrees"
          '(sq:deg (sq:dirfold (sq:rad 190.0)))  10.0)
    (list "ang-diff of 10 and 170 is 20, not 160"
          '(sq:deg (sq:ang-diff (sq:rad 10.0) (sq:rad 170.0)))  20.0)
    (list "turn squares 176 degrees by turning 4"
          '(sq:deg (sq:turn (sq:rad 176.0)))  4.0)
    (list "turn squares 30 degrees by turning -30"
          '(sq:deg (sq:turn (sq:rad 30.0)))  -30.0)
    (list "deg and rad are inverses"            '(sq:deg (sq:rad 37.5))       37.5)
    (list "tan stays finite at a half turn"     '(numberp (sq:tan (* 0.5 pi))))
    (list "cross3 is positive for a left turn"
          '(> (sq:cross3 '(0 0) '(1 0) '(1 1)) 0.0))
    (list "hull drops an inside point"
          '(not (member '(2.0 2.0) (sq:hull '((0 0) (4 0) (4 4) (0 4) (2 2))))))
    (list "span of a 3 by 4 box is its diagonal"
          '(car (sq:span '((0 0) (3 0) (3 4) (0 4))))  5.0)
    (list "middle of a box's extents"           '(sq:middle '((0 0) (4 2)))   '(2.0 1.0))
    (list "ang writes a signed angle"           '(sq:ang (sq:rad -4.25))      "-4.25")
    (list "way names a negative turn"           '(sq:way -0.1)                "clockwise")
    (list "tie: two equal walls one way are not a tie"
          '(sq:tie (list (list 10.0 0.0) (list 10.0 0.0)))  nil)
    (list "tie: an equal wall across is one"
          '(cadr (sq:tie (list (list 10.0 0.0) (list 10.0 (* 0.5 pi)))))  (* 0.5 pi))))

(foreach c '("SQUAREUP")
  (setq *calofin-selftests*
        (cons (cons c 'sq:selftests) *calofin-selftests*)))

;; Quiet inside the whole build: LAZPASS.lsp and CALOFIN-LOADER.lsp set
;; the flag while they load their members, because one file's greeting
;; is a greeting and sixty-odd of them is a wall the drafter scrolls
;; past in every drawing they open.  APPLOADed alone the flag is nil
;; and this prints, which is the one time somebody wants to be told.
(if (not *calofin-quiet*)
  (princ (strcat "\nSQUAREUP " *squareup-version*
                 " loaded.  Type SQUAREUP to run.")))
(princ)
