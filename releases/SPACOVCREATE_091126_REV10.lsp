;;; ======================================================================
;;; SPACOVCREATE.lsp  --  build a spa cover, and its hinges, from the spa
;;;                       that is already drawn
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  SPACOVCREATE     offset a selected spa outline into its
;;;                             cover and hinge the cover
;;;            SPACOVCREATEVER  print the loaded version
;;; ======================================================================
;;;
;;;  SPA.LSP draws a spa from its measurements.  This draws the COVER for
;;;  a spa that is already on the sheet -- somebody else's drawing, a
;;;  DXF off a survey, an outline traced from a photo -- where there are
;;;  no measurements to type, only geometry to point at.
;;;
;;;  Three questions and it is done:
;;;
;;;    1  SELECT THE SPA.  Whatever you pick is the spa: one closed
;;;       polyline, a circle, or a handful of loose lines and arcs that
;;;       meet end to end.  They are chained into a loop and the biggest
;;;       loop in the selection is the spa -- a bench line or a spillway
;;;       picked up by a careless window is a smaller loop and is left
;;;       alone (the report says how many it found and which it took).
;;;
;;;    2  HOW FAR THE COVER LAPS, defaulting to 6".  The cover is always
;;;       the larger of the two, so the offset always goes OUTWARD.
;;;
;;;    3  WHAT TAPER.  Click the Spa Cover Details block and its GRADE
;;;       and TAPER tags are read; or type the taper; or answer neither,
;;;       in which case a STANDARD 4-2 is assumed AND SAID SO IN THE
;;;       REPORT, in red, beside the drawing.  An assumption nobody can
;;;       see on the sheet is the one that gets built.
;;;
;;;  THE OFFSET KEEPS THE ARCS.  A cover is not a tessellated
;;;  approximation of a cover: a radius corner offsets to a radius
;;;  corner, on the same centre, sweeping the same angle -- so the
;;;  bulge is unchanged and only the vertex moves, out along the corner
;;;  bisector.  A circle offsets to a circle.  What comes out is one
;;;  closed LWPOLYLINE (or one CIRCLE) that picks in a single click and
;;;  can be dimensioned, hatched, offset again or handed to STOCKCOVER.
;;;  An ELLIPSE is the one shape with no exact answer -- the true offset
;;;  of an ellipse is not an ellipse -- so it is offset as a polyline
;;;  and the report says so rather than quietly drawing a lie.  A SPLINE
;;;  is not read at all, for the same reason turned up: it is let
;;;  through the selection filter purely so the run can SAY so, because
;;;  dropped at the filter a spline outline reports "nothing closes" and
;;;  leaves the drafter guessing.
;;;
;;;  THE HINGES follow the same shop data SPA works to, read off the
;;;  same tables: the grade and taper pick a foam sheet, the sheet gives
;;;  the widest a piece may be (so the closest two hinges may sit) and
;;;  the longest a hinge may run, and the taper says which piece counts
;;;  are acceptable.  A taper carrying more than one sheet has every
;;;  sheet solved and scored -- the wider sheet needs fewer pieces, the
;;;  longer one lets a hinge run further -- before fewest pieces
;;;  decides.  Fold and velcro then follow the Hinge Arrangement Chart,
;;;  pairs folding from both ends, labelled on the TEXT layer.
;;;
;;;  WHICH WAY THE HINGES RUN.  SPA turns the spa so its long overall
;;;  runs west to east and then runs the hinges north-south.  Nothing
;;;  here can be turned -- the geometry is already drawn, at whatever
;;;  angle the sheet has it -- so the rule is applied the other way
;;;  round: the hinges divide the LONGER of the cover's two overalls,
;;;  which is the same layout SPA would reach, arrived at without
;;;  moving anybody's drawing.  A cover wider than it is tall gets
;;;  upright hinges; a tall one gets flat hinges.
;;;
;;;  WHAT IT DOES NOT DO.  It does not ask about spillaways: a spillway
;;;  is a no-go zone that SPA dodges by turning the spa, and turning is
;;;  not on the table here.  And it never moves, changes or erases the
;;;  spa outline it was handed.  Anything out of spec -- a hinge over
;;;  the foam length, a piece count the taper does not allow, an offset
;;;  that ate a concave corner -- is still drawn and flagged in red in
;;;  the report, because a drafter who can see the problem can fix it
;;;  and one who cannot, cannot.
;;; ======================================================================

;;; -------------------- version -----------------------------------------
;;;  The banner form tools/release_lisp.py reads (lowercase name, "v",
;;;  one dot).  Bump it with every change and regenerate releases/.

(setq *spacovcreate-version* "v1.0")

;;; ======================================================================
;;;  TUNABLES -- every value SPACOVCREATE reads that somebody might want
;;;  changed lives in this block, and nowhere else in the file.
;;;
;;;  How to change one: edit the value, save, and APPLOAD the file again.
;;;  To try a value for one session only, type the setq at the command
;;;  line -- e.g. (setq scv:*offset-dflt* 8.0) -- because every knob is
;;;  read when the command runs, not when the file loads.
;;;
;;;  Units: distances are drawing units (1 unit = 1 inch on the shop's
;;;  sheets); colours are ACI numbers (1 red, 2 yellow, 3 green, 4 cyan,
;;;  5 blue, 6 magenta, 7 white, 8 grey, 256 ByLayer).
;;; ----------------------------------------------------------------------

;; -- the questions -----------------------------------------------------

;; How far the cover laps the spa, the number Enter takes.  SPA offers
;; the same 6" as its cover-over-water's-edge lap; change one and change
;; the other or the two tools will draw different covers for one spa.
(setq scv:*offset-dflt* 6.0)      ; drawing units

;; What the selection is allowed to hand the command.  Anything not in
;; this list is never seen, so a window dragged over the whole spa picks
;; up the outline and leaves the dimensions, the text and the blocks
;; behind instead of making somebody pick each wall.
;; SPLINE is in the list and is NOT read: a spline has no exact
;; offset and no bulge to keep, so it would have to be chopped into
;; straight runs and the cover would come back as a polygon of one.
;; It is let through the filter anyway so the run can SAY that is what
;; happened -- dropped at the filter, a traced outline that is all
;; spline just reports "nothing closes" and leaves the drafter guessing.
(setq scv:*filter*
  '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE")))

;; The grade and taper assumed when nobody gives one.  THE POINT OF
;; THESE TWO is that the run still produces a hinged cover; the report
;; carries a red line saying the taper was assumed, so the assumption
;; arrives with the drawing rather than in somebody's memory.
(setq scv:*taper-dflt* "4-2")
(setq scv:*grade-dflt* "STANDARD")

;; The block the grade and taper are read off, and its two tags.  The
;; name is only used to warn that a DIFFERENT block was clicked -- its
;; tags are read either way, because a shop that renamed the block still
;; wants its numbers.
(setq scv:*block-name* "SPA COVER DETAILS")
(setq scv:*grade-tag*  "GRADE")
(setq scv:*taper-tag*  "TAPER")

;; -- reading the geometry ----------------------------------------------

;; Two ends this close together are the same end.  Raise it for a
;; drawing whose walls were drawn by eye and do not quite meet; too high
;; and two different corners chain to each other.
(setq scv:*chain-tol* 0.05)       ; drawing units

;; How finely an arc is chopped when one has to be measured as points --
;; the chord maths, the bounding box, the enclosed area.  The DRAWN
;; cover keeps its arcs whatever this says; this only sets how closely
;; they are measured.  Smaller is more accurate and slower.
(setq scv:*arcstep* 5.0)          ; degrees per tessellated segment

;; How far a corner may be stretched by the offset before the spike is
;; cut back, in multiples of the offset itself.  A 90-degree corner
;; mitres to 1.41; anything past this is a needle the drafter did not
;; draw, so it is clamped and the report says which corner.
(setq scv:*miterlim* 4.0)

;; Anything smaller than this is zero: a zero-length wall, a bulge that
;; is really a straight run, an area of nothing.
(setq scv:*fuzz* 1.0e-6)

;; -- what it draws -----------------------------------------------------

;; The layers written on, created on first use with these colours.  An
;; existing layer is used exactly as the drawing has it -- the office
;; template wins -- and only a layer that had to be created gets the
;; colour below.  These are SPA's own layers, so a cover drawn here and
;; a cover drawn there land in the same place.
(setq scv:*lay-cover*  "COVER")   ; the cover outline AND the hinges
(setq scv:*col-cover*  6)         ; ACI (magenta)
(setq scv:*lay-text*   "TEXT")    ; the Hinge / Velcro Hinge labels
(setq scv:*col-text*   7)         ; ACI (white or black, whichever reads)
(setq scv:*lay-report* "SPA-NOTES")  ; the report table beside the cover
(setq scv:*col-report* 3)         ; ACI (green)
(setq scv:*col-bad*    1)         ; ACI (red) -- a flagged report row
(setq scv:*col-advice* 4)         ; ACI (cyan) -- a recommendation

;; The fold hinge's linetype: the stock DASHED2 pattern, defined when
;; the drawing lacks it, scaled so its dash plots 5" long no matter how
;; the host drawing's LTSCALE is set (dash x LTSCALE x multiplier = 5).
(setq scv:*hdashname* "DASHED2")
(setq scv:*hdashpat*  '(0.25 -0.125))
(setq scv:*hdashmult* 20.0)

;; The hinge labels: SPA's numbers, so the two tools' drawings stack.
(setq scv:*hingetxth*  5.0)       ; label height
(setq scv:*hingetxw*  60.0)       ; label MTEXT frame width
(setq scv:*hingestyle* "Attributes")  ; label style (Standard when absent)
(setq scv:*hingetxoff* 0.6)       ; label heights from the line to the label

;; The report table beside the cover.  Its text height is worked out
;; from the size of the cover -- th-div bigger a spa means th-div bigger
;; lettering -- so one table reads the same on a 5-foot spa and a
;; 12-foot one, and never smaller than th-min.
(setq scv:*th-min*    1.0)        ; smallest report lettering
(setq scv:*th-div*   40.0)        ; cover size / this = lettering height
(setq scv:*rep-gap*  12.0)        ; th multiples: cover -> the table
(setq scv:*rep-row*   2.2)        ; th multiples: row pitch
(setq scv:*rep-title* 1.25)       ; th multiples: heading text height
(setq scv:*rep-note*  1.4)        ; th multiples: a red failure note
(setq scv:*rep-adv*   1.15)       ; th multiples: a cyan recommendation
(setq scv:*rep-c1*   22.0)        ; th multiples: the LIMIT column
(setq scv:*rep-c2*   32.0)        ; th multiples: the ACTUAL column
(setq scv:*rep-w*    44.0)        ; th multiples: how wide the box comes out

;; -- the shop data the hinges are built on -----------------------------
;;;
;;;  THE FOAM SHEET.  Grade and taper pick a row, and the row gives the
;;;  foam width (the widest a piece may be, so the furthest two hinges
;;;  may sit apart), the foam length (the longest a hinge may run) and
;;;  which piece counts are acceptable.
;;;
;;;  Row: (grade taper ((foamW . foamL) ...) (piece counts, 5 = 5+))
;;;  A grade+taper with two width options (48" / 49-1/2") carries both;
;;;  the solver picks the one that needs the fewest hinges.  A foamL of
;;;  nil means the sheet sets no length limit.
;;;
;;;  This is SPA's spa:*foamtab*, value for value.  IT IS A COPY ON
;;;  PURPOSE -- a standalone file has to load alone, and SPA is not
;;;  loaded when this one is -- so a change to the shop's foam sheet is
;;;  a change to BOTH, and tests/test_spacovcreate.py compares the two
;;;  tables row by row so the copy cannot quietly drift.
(setq scv:*foamtab*
  (list
    (list "ECONOMY"     "3-2"   (list (cons 48.0 96.0))                    (list 2))
    (list "STANDARD"    "3-2"   (list (cons 48.0 144.0) (cons 49.5 102.0)) (list 2))
    (list "STANDARD"    "4-2"   (list (cons 48.0 96.0)  (cons 49.5 102.0)) (list 2 3 4))
    (list "STANDARD"    "4-3"   (list (cons 48.0 144.0))                   (list 2 3 4))
    (list "STANDARD"    "5-3"   (list (cons 48.0 96.0))                    (list 2 3 4 5))
    (list "STANDARD"    "5-4"   (list (cons 48.0 96.0))                    (list 2 3 4 5))
    (list "STANDARD"    "3-3"   (list (cons 48.0 144.0))                   (list 2 3 4 5))
    (list "ULTRA"       "3-2"   (list (cons 48.0 144.0))                   (list 2))
    (list "ULTRA"       "4-3"   (list (cons 48.0 96.0))                    (list 2 3 4))
    (list "ULTRA"       "3-3"   (list (cons 48.0 144.0))                   (list 2 3 4 5))
    (list "THERMOLIGHT" "1-3/8" (list (cons 53.0 nil))                     (list 2 3 4 5))))

(setq scv:*foamdflt* (list (cons 48.0 96.0)))  ; when nothing matches at all
(setq scv:*foamdpc*  (list 2 3 4 5))           ; and the counts it will accept
(setq scv:*thermotaper* "1-3/8")  ; the one taper a Thermo-Light comes in

;;;  HARDWARE called for by the LONGEST hinge, per grade.  Each rule is
;;;  (OVER <inches>) | (ALWAYS) | (NEVER) | (REQUEST), and the three
;;;  columns are velcro hinges, double C channel, hold down kit -- in
;;;  that order, which is the order they are reported in.  SPA's
;;;  spa:*hardtab*, same copy rule as the foam table above.
(setq scv:*hardtab*
  (list                ;  grade          velcro        double C      hold down
    (list "ECONOMY"     '(REQUEST)    '(REQUEST)    '(REQUEST))
    (list "STANDARD"    '(OVER 120.0) '(OVER 108.0) '(OVER 120.0))
    (list "ULTRA"       '(OVER 108.0) '(NEVER)      '(OVER 96.0))
    (list "THERMOLIGHT" '(ALWAYS)     '(NEVER)      '(NEVER))))

;; What the three columns are called in the report, in the order the
;; table above holds them -- rename one and the report follows.
(setq scv:*hardnames* (list "VELCRO HINGES" "DOUBLE C CHANNEL"
                            "HOLD DOWN KIT"))

;; The placement solver.  The fewest pieces that fit the foam width are
;; used, spaced evenly; when that count is one the taper will not accept
;; the search tries more, up to hinge-try counts past the minimum.
(setq scv:*hinge-min* 2)          ; a cover is never fewer pieces than this
(setq scv:*hinge-try* 3)          ; how many extra piece counts to try

;;; ======================================================================
;;;  END OF TUNABLES
;;; ======================================================================

;;; -------------------- run state (not tunables) ------------------------
;;;  Declared here because AutoLISP wants a global to exist before the
;;;  code that reads it loads.  These are written as the command runs;
;;;  none of them is a setting.

(setq scv:*sysold* nil)     ; saved sysvars
(setq scv:*notes*  nil)     ; red failure lines for the report
(setq scv:*advice* nil)     ; cyan recommendations for the report
(setq scv:*dashlt* "CONTINUOUS")  ; resolved to DASHED2 per run

;;; -------------------- small helpers -----------------------------------

(defun scv:2d (p) (list (car p) (cadr p)))
(defun scv:3d (p) (list (car p) (cadr p) 0.0))
(defun scv:v+ (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun scv:v- (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun scv:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun scv:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun scv:cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))
(defun scv:vlen (v) (sqrt (scv:dot v v)))
(defun scv:mid (a b) (scv:v* (scv:v+ a b) 0.5))

;; Rotate 90 degrees: LEFT is counter-clockwise, RIGHT is clockwise.
;; Every loop here is walked counter-clockwise, which puts the inside on
;; the left -- so RIGHT is the way out, and that is the whole of the
;; sign convention in the offset below.
(defun scv:left (v) (list (- (cadr v)) (car v)))
(defun scv:right (v) (list (cadr v) (- (car v))))

(defun scv:unit (v / l)
  (setq l (scv:vlen v))
  (if (> l scv:*fuzz*) (scv:v* v (/ 1.0 l)) (list 0.0 0.0)))

(defun scv:samep (a b) (< (distance (scv:2d a) (scv:2d b)) scv:*chain-tol*))

(defun scv:ceilv (v / f)
  (setq f (fix v))
  (if (> v (+ f scv:*fuzz*)) (1+ f) f))

(defun scv:plural (n one many)
  (strcat (itoa n) " " (if (= n 1) one many)))

(defun scv:trim (s)
  (while (and (> (strlen s) 0) (= " " (substr s 1 1)))
    (setq s (substr s 2)))
  (while (and (> (strlen s) 0) (= " " (substr s (strlen s) 1)))
    (setq s (substr s 1 (1- (strlen s)))))
  s)

;; "Taper: 4-2" -> "4-2" (everything after the last colon, trimmed).
(defun scv:aftercolon (s / i out)
  (setq i (strlen s) out s)
  (while (> i 0)
    (if (= ":" (substr s i 1))
        (progn (setq out (substr s (1+ i))) (setq i 0))
        (setq i (1- i))))
  (scv:trim out))

(defun scv:say (s) (princ (strcat "\n" s)) (princ))

;; A problem: printed now, and written into the report in red.
(defun scv:note (msg)
  (setq scv:*notes* (append scv:*notes* (list msg)))
  (scv:say msg))

;; A recommendation rather than a problem: cyan, under the red ones.
(defun scv:advise (msg)
  (setq scv:*advice* (append scv:*advice* (list msg)))
  (scv:say msg))

;;; -------------------- sysvars and layers ------------------------------

(defun scv:syssave (vars / v)
  (if (not scv:*sysold*)
      (foreach v vars
        (if (/= nil (getvar v))
            (setq scv:*sysold*
                  (append scv:*sysold* (list (cons v (getvar v)))))))))

(defun scv:sysrestore ( / p)
  (foreach p scv:*sysold* (setvar (car p) (cdr p)))
  (setq scv:*sysold* nil))

(defun scv:osup ( / p)
  (setq p (assoc "OSMODE" scv:*sysold*))
  (if p (setvar "OSMODE" (cdr p))))

(defun scv:osdown () (setvar "OSMODE" 0))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case.
(defun scv:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
                    '(6 . "Continuous")))
    (progn
      (setq rec   (tblobjname "LAYER" name)
            ed    (entget rec)
            flags (cdr (assoc 70 ed))
            col   (cdr (assoc 62 ed))
            fixed nil)
      (if (/= 0 (logand 5 flags))          ; frozen (1) or locked (4)
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)                        ; layer switched off
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nLayer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; The fold hinge's dashed linetype, defined when the drawing lacks it.
;; Returns its name, or CONTINUOUS when it could not be made.
(defun scv:ltmake (name descr pat / lst x)
  (if (tblsearch "LTYPE" name)
      name
      (progn
        (setq lst (list '(0 . "LTYPE") '(100 . "AcDbSymbolTableRecord")
                        '(100 . "AcDbLinetypeTableRecord")
                        (cons 2 name) '(70 . 0) (cons 3 descr)
                        '(72 . 65) (cons 73 (length pat))
                        (cons 40 (apply '+ (mapcar 'abs pat)))))
        (foreach x pat (setq lst (append lst (list (cons 49 x) '(74 . 0)))))
        (if (entmake lst) name "CONTINUOUS"))))

;; Entity linetype scale that makes the dash plot 5" long whatever the
;; drawing's LTSCALE is.
(defun scv:ltsc ( / s)
  (setq s (getvar "LTSCALE"))
  (if (and s (> s scv:*fuzz*)) (/ 1.0 s) 1.0))

(defun scv:hdash ( / )
  (if (/= scv:*dashlt* "CONTINUOUS")
      (list (cons 6 scv:*dashlt*)
            (cons 48 (* scv:*hdashmult* (scv:ltsc))))))

;;; ======================================================================
;;;  THE GEOMETRY
;;; ======================================================================
;;;
;;;  Everything below works on ONE representation, the same one an
;;;  LWPOLYLINE uses, because that is what has to come out at the end:
;;;
;;;    a VERTEX is (point . bulge) -- the bulge belonging to the segment
;;;      that LEAVES this vertex.  Zero is a straight run.
;;;    a STRAND is (closed-flag vertex vertex ...).  Closed means the
;;;      last vertex's segment runs back to the first; open means the
;;;      last vertex's bulge is not a segment at all and is ignored.
;;;
;;;  Every entity read is turned into a strand, the open strands are
;;;  chained end to end into loops, and the loop with the biggest area
;;;  is the spa.  The bulge survives all of it, which is the point: the
;;;  radius corner that came in is the radius corner that goes out.

(defun scv:st-closed (s) (car s))
(defun scv:st-verts (s) (cdr s))
(defun scv:st (closed verts) (cons closed verts))
(defun scv:vpt (v) (car v))
(defun scv:vb (v) (cdr v))
(defun scv:vx (p b) (cons (scv:2d p) b))

;; Bulge <-> included angle.  The bulge is the tangent of a quarter of
;; the angle the arc sweeps, negative when the arc runs clockwise.
(defun scv:bulge (th) (/ (sin (* 0.25 th)) (cos (* 0.25 th))))
(defun scv:sweep (b) (* 4.0 (atan b)))

(defun scv:rot (v a / c s)
  (setq c (cos a) s (sin a))
  (list (- (* (car v) c) (* (cadr v) s))
        (+ (* (car v) s) (* (cadr v) c))))

;; Where the arc of a bulged segment lives: (centre radius sweep), or
;; nil when the bulge is really a straight run.  The centre sits on the
;; chord's perpendicular bisector, d*cot(sweep/2) to the LEFT of the
;; chord -- which puts it on the far side from the way the arc bulges,
;; and gets a major arc (bulge over 1) right by changing that cotangent's
;; sign rather than by a special case.
(defun scv:arcinfo (p q b / th d hs u)
  (setq th (scv:sweep b)
        d  (* 0.5 (distance (scv:2d p) (scv:2d q)))
        hs (sin (* 0.5 th)))
  (if (or (< (abs b) scv:*fuzz*) (< d scv:*fuzz*) (< (abs hs) scv:*fuzz*))
      nil
      (progn
        (setq u (scv:unit (scv:v- q p)))
        (list (scv:v+ (scv:mid p q)
                      (scv:v* (scv:left u) (* d (/ (cos (* 0.5 th)) hs))))
              (abs (/ d hs))
              th))))

;; The direction the outline is travelling as it LEAVES p, and as it
;; ARRIVES at q: the chord turned back and forward by half the sweep.
;; For a straight run both are the chord itself.
(defun scv:tan-out (p q b / u)
  (setq u (scv:unit (scv:v- q p)))
  (if (< (abs b) scv:*fuzz*) u (scv:rot u (* -0.5 (scv:sweep b)))))

(defun scv:tan-in (p q b / u)
  (setq u (scv:unit (scv:v- q p)))
  (if (< (abs b) scv:*fuzz*) u (scv:rot u (* 0.5 (scv:sweep b)))))

;; The points ALONG a bulged segment, first and last excluded, for the
;; measuring that cannot be done on a bulge: the chord maths, the
;; bounding box, the enclosed area.  Nothing drawn goes through here.
(defun scv:arcpts (p q b / ai cen r th n i out a0 a)
  (setq ai (scv:arcinfo p q b) out nil)
  (if ai
      (progn
        (setq cen (car ai) r (cadr ai) th (caddr ai)
              a0 (angle (scv:2d cen) (scv:2d p))
              n (max 2 (scv:ceilv (/ (abs (* 180.0 (/ th pi)))
                                     scv:*arcstep*)))
              i 1)
        (while (< i n)
          (setq a (+ a0 (* th (/ (float i) n)))
                out (cons (list (+ (car cen) (* r (cos a)))
                                (+ (cadr cen) (* r (sin a))))
                          out)
                i (1+ i)))))
  (reverse out))

;; A closed strand as a plain list of points, arcs chopped up.  The
;; closing point is NOT repeated -- every consumer below walks the list
;; round on its own.
(defun scv:flatten (verts / n i v w p out)
  (setq n (length verts) i 0 out nil)
  (while (< i n)
    (setq v (nth i verts)
          w (nth (rem (1+ i) n) verts)
          out (cons (scv:vpt v) out))
    (foreach p (scv:arcpts (scv:vpt v) (scv:vpt w) (scv:vb v))
      (setq out (cons p out)))
    (setq i (1+ i)))
  (reverse out))

;; Twice the signed area of a polygon: positive counter-clockwise.  The
;; sign is the only thing the orientation pass needs, and the size is
;; what picks the spa out of a selection holding more than one loop.
(defun scv:area2 (pts / n i p q s)
  (setq n (length pts) i 0 s 0.0)
  (while (< i n)
    (setq p (nth i pts)
          q (nth (rem (1+ i) n) pts)
          s (+ s (scv:cross p q))
          i (1+ i)))
  s)

(defun scv:bbox (pts / x1 y1 x2 y2 p)
  (foreach p pts
    (if (or (null x1) (< (car p) x1)) (setq x1 (car p)))
    (if (or (null x2) (> (car p) x2)) (setq x2 (car p)))
    (if (or (null y1) (< (cadr p) y1)) (setq y1 (cadr p)))
    (if (or (null y2) (> (cadr p) y2)) (setq y2 (cadr p))))
  (if x1 (list x1 y1 x2 y2)))

;;; -------------------- reading entities into strands -------------------

;; An ARC, as the two ends of one bulged segment.  DXF 50 / 51 always
;; run counter-clockwise, so the sweep is their difference brought into
;; 0..2pi -- a full turn meaning a full circle, which an ARC never is.
(defun scv:arc-strand (ed / cen r a1 a2 th)
  (setq cen (cdr (assoc 10 ed))
        r   (cdr (assoc 40 ed))
        a1  (cdr (assoc 50 ed))
        a2  (cdr (assoc 51 ed))
        th  (- a2 a1))
  (while (< th 0.0) (setq th (+ th (* 2.0 pi))))
  (while (>= th (* 2.0 pi)) (setq th (- th (* 2.0 pi))))
  (scv:st nil
          (list (scv:vx (list (+ (car cen) (* r (cos a1)))
                              (+ (cadr cen) (* r (sin a1))))
                        (scv:bulge th))
                (scv:vx (list (+ (car cen) (* r (cos a2)))
                              (+ (cadr cen) (* r (sin a2))))
                        0.0))))

;; A CIRCLE, as the two semicircles a closed polyline would use.  It
;; survives the offset as two semicircles of a bigger radius, which is
;; what lets the cover come back out as a CIRCLE (scv:circlep).
(defun scv:circle-strand (ed / cen r)
  (setq cen (cdr (assoc 10 ed)) r (cdr (assoc 40 ed)))
  (scv:st t (list (scv:vx (list (+ (car cen) r) (cadr cen)) 1.0)
                  (scv:vx (list (- (car cen) r) (cadr cen)) 1.0))))

;; An ELLIPSE, chopped into straight runs.  There is no exact offset of
;; an ellipse -- the curve parallel to an ellipse is not one -- so this
;; is the one shape that cannot keep its curve, and the caller says so
;; in the report rather than letting somebody find out at the saw.
(defun scv:ellipse-strand (ed / cen maj rat t1 t2 n i verts a bx by)
  (setq cen (cdr (assoc 10 ed))
        maj (cdr (assoc 11 ed))
        rat (cdr (assoc 40 ed))
        t1  (cdr (assoc 41 ed))
        t2  (cdr (assoc 42 ed)))
  (if (null rat) (setq rat 1.0))
  (if (null t1) (setq t1 0.0))
  (if (null t2) (setq t2 (* 2.0 pi)))
  (setq bx (scv:v* (scv:left (scv:2d maj)) rat)
        n (max 8 (scv:ceilv (/ (abs (* 180.0 (/ (- t2 t1) pi)))
                               scv:*arcstep*)))
        i 0 verts nil)
  (while (< i n)
    (setq a (+ t1 (* (- t2 t1) (/ (float i) n)))
          by (scv:v+ (scv:v* (scv:2d maj) (cos a)) (scv:v* bx (sin a)))
          verts (cons (scv:vx (scv:v+ (scv:2d cen) by) 0.0) verts)
          i (1+ i)))
  (scv:st t (reverse verts)))

;; An LWPOLYLINE: its DXF 10 points in order, each with the DXF 42 that
;; follows it, and closed when bit 1 of DXF 70 is set.
(defun scv:lw-strand (ed / verts p b g)
  (setq verts nil p nil b 0.0)
  (foreach g ed
    (cond
      ((= (car g) 10)
       (if p (setq verts (cons (scv:vx p b) verts)))
       (setq p (cdr g) b 0.0))
      ((= (car g) 42) (setq b (cdr g)))))
  (if p (setq verts (cons (scv:vx p b) verts)))
  (scv:st (= 1 (logand 1 (cdr (assoc 70 ed))))
          (reverse verts)))

;; A heavyweight 2D POLYLINE, whose vertices are entities of their own
;; following the header until the SEQEND.
(defun scv:pl-strand (en ed / e ved verts)
  (setq verts nil e (entnext en))
  (while (and e (setq ved (entget e))
              (= "VERTEX" (cdr (assoc 0 ved))))
    (if (/= 16 (logand 16 (cdr (assoc 70 ved))))   ; skip spline frames
        (setq verts (cons (scv:vx (cdr (assoc 10 ved))
                                  (if (assoc 42 ved) (cdr (assoc 42 ved)) 0.0))
                          verts)))
    (setq e (entnext e)))
  (scv:st (= 1 (logand 1 (cdr (assoc 70 ed)))) (reverse verts)))

;; Every entity in the selection as a strand, plus what the caller has
;; to report about what was in there: whether an ellipse was among them
;; (no exact offset) and how many splines were (not read at all).
;; Returns (strands ellipsep splinecount).
(defun scv:harvest (ss / i en ed typ st out ell spl)
  (setq i 0 out nil ell nil spl 0)
  (while (< i (sslength ss))
    (setq en (ssname ss i)
          ed (entget en)
          i  (1+ i)
          st nil)
    (if ed
        (progn
          (setq typ (cdr (assoc 0 ed)))
          (cond
            ((= typ "LINE")
             (setq st (scv:st nil (list (scv:vx (cdr (assoc 10 ed)) 0.0)
                                        (scv:vx (cdr (assoc 11 ed)) 0.0)))))
            ((= typ "ARC")        (setq st (scv:arc-strand ed)))
            ((= typ "CIRCLE")     (setq st (scv:circle-strand ed)))
            ((= typ "ELLIPSE")    (setq st (scv:ellipse-strand ed) ell t))
            ((= typ "LWPOLYLINE") (setq st (scv:lw-strand ed)))
            ((= typ "POLYLINE")   (setq st (scv:pl-strand en ed)))
            ((= typ "SPLINE")     (setq spl (1+ spl))))
          (if (and st (> (length (scv:st-verts st)) 1))
              (setq out (cons st out))))))
  (list (reverse out) ell spl))

;;; -------------------- chaining the strands into loops -----------------

;; An open strand walked the other way: the points reverse, and each
;; bulge moves back one place and changes sign, because every segment is
;; now being travelled backwards.
(defun scv:revopen (verts / n i out)
  (setq n (length verts) i 0 out nil)
  (while (< i n)
    (setq out (cons (scv:vx (scv:vpt (nth (- n 1 i) verts))
                            (if (< i (1- n))
                                (- (scv:vb (nth (- n 2 i) verts)))
                                0.0))
                    out)
          i (1+ i)))
  (reverse out))

;; The same for a closed loop, where there is no spare last bulge: every
;; vertex keeps a segment, so the shift wraps round instead of stopping.
(defun scv:revclosed (verts / n i out k)
  (setq n (length verts) i 0 out nil)
  (while (< i n)
    (setq k (rem (+ (- n 2 i) n) n)
          out (cons (scv:vx (scv:vpt (nth (- n 1 i) verts))
                            (- (scv:vb (nth k verts))))
                    out)
          i (1+ i)))
  (reverse out))

(defun scv:first-pt (verts) (scv:vpt (car verts)))
(defun scv:last-pt (verts) (scv:vpt (last verts)))

;; Chain the open strands end to end.  Each run starts from whatever
;; open strand is left, keeps hunting for one that meets its far end --
;; either way round -- and stops when it closes on itself or runs out of
;; neighbours.  Returns (loops leftovers): loops are closed strands,
;; leftovers are the counts of open runs that never closed.
(defun scv:chain (strands / open loops leftover cur verts pool hit s sv
                            grew)
  (setq open nil loops nil leftover 0)
  (foreach s strands
    (if (scv:st-closed s)
        (setq loops (cons s loops))
        (setq open (cons s open))))
  (setq pool (reverse open))
  (while pool
    (setq cur (car pool)
          pool (cdr pool)
          verts (scv:st-verts cur)
          grew t)
    (while grew
      (setq grew nil hit nil)
      (if (not (scv:samep (scv:last-pt verts) (scv:first-pt verts)))
          (foreach s pool
            (if (null hit)
                (progn
                  (setq sv (scv:st-verts s))
                  (cond
                    ((scv:samep (scv:last-pt verts) (scv:first-pt sv))
                     (setq hit s))
                    ((scv:samep (scv:last-pt verts) (scv:last-pt sv))
                     (setq hit s sv (scv:revopen sv))))
                  (if hit
                      (setq verts (append (reverse (cdr (reverse verts))) sv)
                            grew t
                            pool (vl-remove s pool)))))))
      ;; a closed run is a loop; the last vertex is the first one over
      ;; again, so it goes, and the segment back to the start is already
      ;; carried by the vertex in front of it
      (if (and (> (length verts) 2)
               (scv:samep (scv:last-pt verts) (scv:first-pt verts)))
          (setq loops (cons (scv:st t (reverse (cdr (reverse verts)))) loops)
                verts nil
                grew nil)))
    (if verts (setq leftover (1+ leftover))))
  (list (reverse loops) leftover))

;; The biggest loop in the list, walked counter-clockwise whichever way
;; it arrived.  Returns (strand points area), the points being the
;; flattened outline; nil when there is no loop with an area in it.
(defun scv:pick-loop (loops / best bpts barea s pts a)
  (foreach s loops
    (setq pts (scv:flatten (scv:st-verts s))
          a   (* 0.5 (scv:area2 pts)))
    (if (or (null best) (> (abs a) (abs barea)))
        (setq best s bpts pts barea a)))
  (if (and best (> (abs barea) scv:*fuzz*))
      (progn
        (if (< barea 0.0)                      ; clockwise -- turn it round
            (setq best (scv:st t (scv:revclosed (scv:st-verts best)))
                  bpts (scv:flatten (scv:st-verts best))
                  barea (- barea)))
        (list best bpts barea))))

;;; -------------------- the offset --------------------------------------
;;;
;;;  The loop runs counter-clockwise, so the inside is on the left and
;;;  OUT is to the right of the way it is travelling.  Every vertex
;;;  moves out along the bisector of the two directions meeting there,
;;;  far enough that BOTH segments end up a full d further out --
;;;  d*(n1+n2)/(1+n1.n2), the mitre, which is exact for two straight
;;;  walls and exact again where an arc runs tangent into a wall (the
;;;  two normals are then the same and it reduces to d straight out).
;;;
;;;  EVERY BULGE IS LEFT ALONE, and that is not an approximation: the
;;;  offset of a circular arc is a circular arc on the same centre
;;;  sweeping the same angle, and the bulge is a function of the angle
;;;  alone.  A radius corner comes out a radius corner, r + d if it
;;;  bulges outward and r - d if it bulges in.
;;;
;;;  Two things are flagged rather than fixed, because a cover the
;;;  drafter can see is wrong beats a cover quietly repaired:
;;;    * an inward arc (negative bulge) whose radius the offset eats;
;;;    * a corner whose mitre runs past scv:*miterlim*, which is a
;;;      needle nobody drew -- it is clamped, and named.
(defun scv:offset (verts d / n i v vp vn p pp pn u1 u2 n1 n2 den mv ml
                             ai out)
  (setq n (length verts) i 0 out nil)
  (while (< i n)
    (setq v  (nth i verts)
          vp (nth (rem (+ i (1- n)) n) verts)
          vn (nth (rem (1+ i) n) verts)
          p  (scv:vpt v)
          pp (scv:vpt vp)
          pn (scv:vpt vn)
          u1 (scv:tan-in pp p (scv:vb vp))
          u2 (scv:tan-out p pn (scv:vb v))
          n1 (scv:right u1)
          n2 (scv:right u2)
          den (+ 1.0 (scv:dot n1 n2)))
    (if (< den 1.0e-4)
        ;; the outline doubles back on itself here; there is no bisector
        ;; to run out along, so take the one normal and say so
        (setq mv (scv:v* n2 d))
        (setq mv (scv:v* (scv:v+ n1 n2) (/ d den))))
    (setq ml (scv:vlen mv))
    (if (> ml (* scv:*miterlim* (abs d)))
        (progn
          (setq mv (scv:v* (scv:unit mv) (* scv:*miterlim* (abs d))))
          (scv:note (strcat "CORNER " (itoa (1+ i))
                            " IS TOO SHARP TO OFFSET CLEANLY - CLAMPED"))))
    ;; an arc that curves INTO the shape loses radius to the offset
    (if (< (scv:vb v) (- scv:*fuzz*))
        (progn
          (setq ai (scv:arcinfo p pn (scv:vb v)))
          (if (and ai (<= (cadr ai) (+ d scv:*fuzz*)))
              (scv:note (strcat "INWARD ARC AT CORNER " (itoa (1+ i))
                                " IS SMALLER THAN THE OFFSET - CHECK IT")))))
    (setq out (cons (scv:vx (scv:v+ p mv) (scv:vb v)) out)
          i (1+ i)))
  (setq out (reverse out))
  (scv:offset-check verts out)
  out)

;; Did the offset swallow a wall?  A segment whose chord comes out
;; pointing the other way is one the offset ran straight over, and the
;; cover has a little loop in it there.  It is drawn anyway -- see it,
;; fix it -- but nobody finds it by accident.
(defun scv:offset-check (verts out / n i a b c e)
  (setq n (length verts) i 0)
  (while (< i n)
    (setq a (scv:v- (scv:vpt (nth (rem (1+ i) n) verts))
                    (scv:vpt (nth i verts)))
          b (scv:v- (scv:vpt (nth (rem (1+ i) n) out))
                    (scv:vpt (nth i out)))
          c (scv:vlen a)
          e (scv:vlen b))
    (if (and (> c scv:*fuzz*) (> e scv:*fuzz*)
             (< (scv:dot (scv:unit a) (scv:unit b)) 0.0))
        (scv:note (strcat "WALL " (itoa (1+ i))
                          " IS SHORTER THAN THE OFFSET - COVER CROSSES ITSELF")))
    (setq i (1+ i))))

;; Is this loop really a circle?  Two vertices, each a half turn, the
;; same distance apart both ways -- which is what a CIRCLE reads as and
;; what its offset stays.  Returns (centre radius) so it can be drawn as
;; one rather than as a two-vertex polyline nobody can dimension.
(defun scv:circlep (verts / a b)
  (if (= 2 (length verts))
      (progn
        (setq a (car verts) b (cadr verts))
        (if (and (< (abs (- (scv:vb a) 1.0)) 1.0e-6)
                 (< (abs (- (scv:vb b) 1.0)) 1.0e-6))
            (list (scv:mid (scv:vpt a) (scv:vpt b))
                  (* 0.5 (distance (scv:2d (scv:vpt a))
                                   (scv:2d (scv:vpt b)))))))))

;;; ======================================================================
;;;  THE HINGES
;;; ======================================================================
;;;
;;;  SPA turns the spa until its long overall runs west to east and then
;;;  runs the hinges north-south.  Nothing here can be turned, so the
;;;  same rule is read the other way round: the hinges divide the LONGER
;;;  of the cover's two overalls.  Everything below is written as though
;;;  that overall runs west to east; when it does not, the outline is
;;;  handed over with x and y swapped and the answer swapped back, which
;;;  is one function (scv:swap) instead of a second copy of the solver.

(defun scv:swap (pts)
  (mapcar '(lambda (p) (list (cadr p) (car p))) pts))

;; (ybot ytop) of the outline at x, or nil when x misses it.  The
;; outline is walked as a polygon and the lowest and highest crossings
;; taken, so a hinge measured across a notched cover measures the whole
;; run the foam has to cover, not the two bits either side of the notch.
(defun scv:chordpoly (pts x / n i p q tt ys)
  (setq n (length pts) i 0 ys nil)
  (while (< i n)
    (setq p (nth i pts) q (nth (rem (1+ i) n) pts))
    (if (or (and (<= (car p) x) (> (car q) x))
            (and (<= (car q) x) (> (car p) x)))
        (setq tt (/ (- x (car p)) (- (car q) (car p)))
              ys (cons (+ (cadr p) (* tt (- (cadr q) (cadr p)))) ys)))
    (setq i (1+ i)))
  (if (>= (length ys) 2)
      (list (apply 'min ys) (apply 'max ys))))

;; Even hinge stations for n pieces across [x1 x2].
(defun scv:heven (x1 x2 n / i out)
  (setq i 1 out nil)
  (while (< i n)
    (setq out (cons (+ x1 (* (- x2 x1) (/ (float i) n))) out)
          i (1+ i)))
  (reverse out))

;; The longest hinge a station list produces -- what the foam LENGTH is
;; measured against.
(defun scv:hmaxchord (pts xs / m ch x)
  (setq m 0.0)
  (foreach x xs
    (if (setq ch (scv:chordpoly pts x))
        (setq m (max m (- (cadr ch) (car ch))))))
  m)

;; The widest piece a station list leaves -- what the foam WIDTH is
;; measured against.
(defun scv:hmaxpiece (x1 x2 xs / m prev x)
  (setq m 0.0 prev x1)
  (foreach x (append xs (list x2))
    (setq m (max m (- x prev)) prev x))
  m)

;; A piece count the taper allows?  Five and over are one row on the
;; sheet, so a 5 in the list stands for "five or more".
(defun scv:hallow (n allowed)
  (if (>= n 5) (member 5 allowed) (member n allowed)))

;; The foam sheets a grade + taper may be cut from: (options counts got).
;; A grade in a taper only the Standard sheet carries falls back to
;; Standard, quietly, exactly as SPA does; nothing on the sheet at all
;; falls back to scv:*foamdflt* with the flag down, and THAT is said.
(defun scv:foamopts (grade taper / row r)
  (foreach r scv:*foamtab*
    (if (and (not row) (= (car r) grade) (= (cadr r) taper))
        (setq row r)))
  (if (not row)
      (foreach r scv:*foamtab*
        (if (and (not row) (= (car r) "STANDARD") (= (cadr r) taper))
            (setq row r))))
  (if row
      (list (caddr row) (cadddr row) t)
      (list scv:*foamdflt* scv:*foamdpc* nil)))

;; The best layout over every foam sheet the taper carries, and over
;; every piece count from the fewest that fit up to scv:*hinge-try*
;; past it.  Each candidate is SCORED on what it satisfies -- the foam
;; width (4), the foam length (2), an acceptable piece count (1) -- and
;; only then on fewest pieces, so a cover that has to break one rule
;; breaks the least important one.  The width is the heaviest because a
;; piece wider than the sheet cannot be cut at all, where a hinge over
;; the foam length is a cover that is made and then flagged.
;; Returns (n xs fw fl wok lenok pcok maxchord maxpiece score).
(defun scv:hbest (pts x1 x2 opts allowed / best bestsc opt fw fl nmin n xs
                                          mc mp lenok pcok wok sc cand)
  (setq best nil bestsc -1)
  (foreach opt opts
    (setq fw (car opt)
          fl (cdr opt)
          nmin (max scv:*hinge-min* (scv:ceilv (/ (- x2 x1) fw)))
          n nmin)
    (while (<= n (+ nmin scv:*hinge-try*))
      (setq xs (scv:heven x1 x2 n)
            mc (scv:hmaxchord pts xs)
            mp (scv:hmaxpiece x1 x2 xs)
            wok (<= mp (+ fw 0.01))
            lenok (or (null fl) (<= mc (+ fl 0.01)))
            pcok (if (scv:hallow n allowed) t nil)
            sc (+ (if wok 4 0) (if lenok 2 0) (if pcok 1 0))
            cand (list n xs fw fl wok lenok pcok mc mp sc))
      (if (or (null best)
              (> sc bestsc)
              (and (= sc bestsc) (< n (car best)))
              ;; nothing to choose on either -> the longer sheet, so a
              ;; hinge that overruns overruns by as little as it can
              (and (= sc bestsc) (= n (car best))
                   (> (if fl fl 0.0) (if (nth 3 best) (nth 3 best) 0.0))))
          (setq best cand bestsc sc))
      (setq n (1+ n))))
  best)

;; Fold or velcro for each hinge, per the Hinge Arrangement Chart.  SPA's
;; spa:hingetypes, unchanged, so the two tools draw one chart:
;;
;;     2  H              5  H V V H          8  H V H V H V H
;;     3  H V            6  H V H V H        9  H V H V V H V H
;;     4  H V H          7  H V H V V H
;;
;; The pieces fold up in PAIRS from both ends -- a fold hinge inside
;; each pair, velcro between bundles -- an odd count leaving one flat
;; piece at or beside the centre.  allvel (Thermo-Light) forces every
;; hinge to velcro.  Returns a list of "H" / "V", west to east.
(defun scv:hingetypes (n allvel / hc m zone p out)
  (setq hc (1- n)
        m (rem n 4)
        zone (cond ((or (= m 0) (= m 2)) hc)
                   ((= m 1) (/ hc 2))
                   (t (/ (+ hc 2) 2)))
        p 0 out nil)
  (while (< p hc)
    (setq out (append out
                      (list (cond (allvel "V")
                                  ((< p zone) (if (= 0 (rem p 2)) "H" "V"))
                                  (t (nth (- hc 1 p) out)))))
          p (1+ p)))
  out)

;; Hardware rule against the longest hinge -> (needed . reason).
(defun scv:hardverdict (rule len / k v)
  (setq k (car rule) v (cadr rule))
  (cond
    ((eq k 'ALWAYS)  (cons t   "always for this grade"))
    ((eq k 'NEVER)   (cons nil "not used on this grade"))
    ((eq k 'REQUEST) (cons t   "upon request only"))
    ((> len v)       (cons t   (strcat "hinge " (rtos len 2 1)
                                       " over " (rtos v 2 0))))
    (t               (cons nil (strcat "hinge " (rtos len 2 1)
                                       " not over " (rtos v 2 0))))))

;;; -------------------- grade and taper vocabulary ----------------------
;;;
;;;  Matched as substrings, so "Taper: 4-2 Flat" and "4-2" are the same
;;;  answer and a tag nobody trimmed still reads.  SPA's spa:tapernorm
;;;  and spa:gradenorm, word for word.

(defun scv:tapernorm (v / u)
  (setq u (strcase v))
  (cond ((wcmatch u "*3-2*") "3-2")
        ((wcmatch u "*4-2*") "4-2")
        ((wcmatch u "*4-3*") "4-3")
        ((wcmatch u "*5-3*") "5-3")
        ((wcmatch u "*5-4*") "5-4")
        ((wcmatch u "*3-3*") "3-3")
        ((wcmatch u "*3/8*") "1-3/8")))

;; Anything unrecognised, or missing, is Standard.
(defun scv:gradenorm (v / u)
  (setq u (strcase (if v v "")))
  (cond ((wcmatch u "*ECON*") "ECONOMY")
        ((or (wcmatch u "*ULTRA*") (wcmatch u "*FRP*")) "ULTRA")
        ((wcmatch u "*THERMO*") "THERMOLIGHT")
        (t "STANDARD")))

(defun scv:gradeshort (g)
  (cond ((= g "ECONOMY") "ECO") ((= g "STANDARD") "STD")
        ((= g "ULTRA") "ULTRA") (t "THERMO")))

;; Attributes of a block reference, as ((TAG . value) ...).
(defun scv:attribs (en / e ed out)
  (setq e (entnext en))
  (while (and e (setq ed (entget e)) (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq out (cons (cons (strcase (cdr (assoc 2 ed))) (cdr (assoc 1 ed)))
                    out)
          e (entnext e)))
  (reverse out))

;;; ======================================================================
;;;  DRAWING
;;; ======================================================================

;; The cover as ONE closed LWPOLYLINE -- so it picks in a single click,
;; encloses an area, and can be dimensioned, hatched, offset again or
;; handed to STOCKCOVER.  Same shape as spa:perpoly, and on purpose.
(defun scv:polyline (verts lay / lst v p)
  (setq lst (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
                  (cons 8 lay) '(100 . "AcDbPolyline")
                  (cons 90 (length verts)) '(70 . 1)))
  (foreach v verts
    (setq p (scv:vpt v)
          lst (append lst (list (cons 10 (list (car p) (cadr p)))
                                (cons 42 (scv:vb v))))))
  (entmake lst)
  (entlast))

(defun scv:circle (cen r lay)
  (entmake (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                 '(100 . "AcDbCircle") (cons 10 (scv:3d cen)) (cons 40 r)))
  (entlast))

(defun scv:line (p q lay extra)
  (entmake (append (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                         '(100 . "AcDbLine")
                         (cons 10 (scv:3d p)) (cons 11 (scv:3d q)))
                   extra))
  (entlast))

(defun scv:text (pt h str lay col)
  (entmake (append (list '(0 . "TEXT") '(100 . "AcDbEntity") (cons 8 lay))
                   (if col (list (cons 62 col)))
                   (list '(100 . "AcDbText") (cons 10 (scv:3d pt))
                         (cons 40 h) (cons 1 str))))
  (entlast))

;; A hinge's label: MTEXT reading ALONG the hinge, middle-centred one
;; label-height clear of it on the left.  SPA writes its labels upright
;; beside an upright hinge; this reaches the same place for an upright
;; hinge and the matching one for a flat hinge, which SPA never has to
;; draw because it turns the spa instead.
(defun scv:hlabel (p q str / dir off mid)
  (setq dir (scv:unit (scv:v- q p))
        off (scv:v* (scv:left dir) (* scv:*hingetxoff* scv:*hingetxth*))
        mid (scv:v+ (scv:mid p q) off))
  (entmake (list '(0 . "MTEXT") '(100 . "AcDbEntity")
                 (cons 8 scv:*lay-text*) '(100 . "AcDbMText")
                 (cons 10 (scv:3d mid))
                 (cons 40 scv:*hingetxth*)
                 (cons 41 scv:*hingetxw*)
                 '(71 . 5)                      ; middle centre
                 '(72 . 5)                      ; drawing direction: by style
                 (cons 1 str)
                 (cons 7 (if (tblsearch "STYLE" scv:*hingestyle*)
                             scv:*hingestyle* "Standard"))
                 (cons 11 (scv:3d dir))))
  (entlast))

;;; -------------------- the report beside the cover ---------------------
;;;
;;;  Three columns -- what was measured, the limit it is measured
;;;  against, and what it came out at -- because every number the hinge
;;;  maths produces is a number with a ceiling over it.  A row with no
;;;  ceiling (the piece count, a hinge's position) prints a dash there
;;;  rather than a nought, which would read as a limit of zero.
;;;
;;;  Under the rows go the red lines: anything out of spec, and THE
;;;  ASSUMED TAPER, which is why this table exists at all.  Under those,
;;;  in cyan, the hardware the longest hinge calls for.

(defun scv:cell (v)
  (cond ((null v) "-")
        ((= (type v) 'STR) v)
        (t (rtos v 2 2))))

(defun scv:rtext (pt h str red)
  (scv:text pt h str scv:*lay-report*
            (if red scv:*col-bad* scv:*col-report*)))

;; rows = (label limit actual [red]); limit and actual are numbers,
;; strings or nil.  x / y is the table's top left corner, h its
;; lettering height.  Returns the y it finished at.
(defun scv:report (rows x y h / lh ytop y0 xr r n)
  (setq lh (* scv:*rep-row* h)
        ytop y
        xr (+ x (* scv:*rep-w* h)))
  (setq y (- y lh))
  (scv:text (list x y) (* scv:*rep-title* h) "SPA COVER REPORT"
            scv:*lay-report* scv:*col-report*)
  (setq y (- y lh))
  (scv:rtext (list x y) h "ITEM" nil)
  (scv:rtext (list (+ x (* scv:*rep-c1* h)) y) h "LIMIT" nil)
  (scv:rtext (list (+ x (* scv:*rep-c2* h)) y) h "ACTUAL" nil)
  (foreach r rows
    (setq y (- y lh))
    (scv:rtext (list x y) h (car r) (nth 3 r))
    (scv:rtext (list (+ x (* scv:*rep-c1* h)) y) h (scv:cell (cadr r))
               (nth 3 r))
    (scv:rtext (list (+ x (* scv:*rep-c2* h)) y) h (scv:cell (caddr r))
               (nth 3 r)))
  (foreach n scv:*notes*
    (setq y (- y (* 1.5 lh)))
    (scv:text (list x y) (* scv:*rep-note* h) n scv:*lay-report*
              scv:*col-bad*))
  (foreach n scv:*advice*
    (setq y (- y (* 1.3 lh)))
    (scv:text (list x y) (* scv:*rep-adv* h) n scv:*lay-report*
              scv:*col-advice*))
  (setq y0 (- y lh)
        ytop (+ ytop (* 0.6 lh)))
  (scv:line (list (- x h) y0) (list xr y0) scv:*lay-report* nil)
  (scv:line (list xr y0) (list xr ytop) scv:*lay-report* nil)
  (scv:line (list xr ytop) (list (- x h) ytop) scv:*lay-report* nil)
  (scv:line (list (- x h) ytop) (list (- x h) y0) scv:*lay-report* nil)
  y0)

;;; ======================================================================
;;;  THE QUESTIONS
;;; ======================================================================
;;;
;;;  Three of them, walked with a step counter the way STANDARDS section
;;;  3 asks for: each answer sets the counter to the step it wants next,
;;;  and Back sets it to the one before.  The selection is the first
;;;  question, so it offers no Back -- there is nothing in front of it.

;; A measurement with a suggested default on a REQUIRED value (the SUGR
;; kind): Enter takes the number shown, zero and negative are refused
;; because a cover that laps nothing is not a cover, and Back re-opens
;; the question before this one.
(defun scv:askdist (msg dflt back / v out)
  (scv:osup)
  (while (null out)
    (if back (initget (if dflt 6 7) "Back Undo") (initget (if dflt 6 7)))
    (setq v (getdist (strcat "\n" msg
                             (if dflt (strcat " <" (rtos dflt) ">") "")
                             (if back " [Back]" "")
                             ": ")))
    (if lzd:ask (lzd:ask msg v))
    (cond
      ((and (= (type v) 'STR) (member v '("Back" "Undo"))) (setq out 'SCV-BACK))
      ((and (null v) dflt) (setq out dflt))
      ((and v (numberp v)) (setq out v))
      (t (princ "\nA measurement is needed here."))))
  (scv:osdown)
  out)

;; Back typed like a value, for the one prompt that cannot take keywords
;; (getstring).  Any case, per the shared convention.
(defun scv:backstr (v)
  (member (strcase v) '("B" "BACK" "U" "UNDO")))

;; The taper typed instead of clicked.  Returns the normalised taper, or
;; SCV-BACK.
(defun scv:asktaper (/ v out)
  (while (null out)
    (setq v (getstring
              "\nTaper (3-2, 4-2, 4-3, 5-3, 5-4, 3-3, 1-3/8) [type B to go Back]: "))
    (if lzd:ask (lzd:ask "Taper" v))
    (cond
      ((scv:backstr v) (setq out 'SCV-BACK))
      ((setq out (scv:tapernorm v)))
      (t (princ "\nNot a taper on the foam sheet -- again."))))
  out)

;; THE TAPER QUESTION.  Click the block and its GRADE / TAPER tags are
;; read; Type to type the taper; Skip -- which is what Enter does -- to
;; take neither, and be told in the report that a standard 4-2 was
;; assumed.  initget's keywords reach entsel exactly as they reach any
;; other prompt, so one question carries all three answers instead of a
;; do-you-want-to first.
;;
;; Returns (grade taper assumed-flag), or SCV-BACK.
(defun scv:askblock (back / v ed bn att g tp)
  (scv:osup)
  (initget (if back "Type Skip Back Undo" "Type Skip"))
  (setq v (entsel (strcat "\nSelect the block that gives the taper [Type/Skip"
                          (if back "/Back" "") "] <Skip>: ")))
  (if lzd:watch (lzd:watch v))
  (if lzd:ask (lzd:ask "Block that gives the taper" v))
  (scv:osdown)
  (cond
    ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'SCV-BACK)
    ((and (= (type v) 'STR) (= v "Type"))
     (setq tp (scv:asktaper))
     (if (eq tp 'SCV-BACK) (scv:askblock back) (list scv:*grade-dflt* tp nil)))
    ((or (null v) (= (type v) 'STR))            ; Skip, or Enter
     (list scv:*grade-dflt* scv:*taper-dflt* t))
    (t
     (setq ed (entget (car v)))
     (if (/= "INSERT" (cdr (assoc 0 ed)))
         (progn
           (scv:say "That is not a block reference.")
           (scv:askblock back))
         (progn
           (setq bn (cdr (assoc 2 ed)))
           (if (/= (strcase bn) (strcase scv:*block-name*))
               (scv:say (strcat "(block is named \"" bn "\", not "
                                scv:*block-name*
                                " -- reading its tags anyway)")))
           (setq att (scv:attribs (car v))
                 g   (cdr (assoc scv:*grade-tag* att))
                 tp  (cdr (assoc scv:*taper-tag* att))
                 g   (if g (scv:gradenorm (scv:aftercolon g)) scv:*grade-dflt*)
                 tp  (if tp (scv:tapernorm (scv:aftercolon tp))))
           (if tp
               (list g tp nil)
               (progn
                 (scv:say (strcat "No readable " scv:*taper-tag*
                                  " tag on that block."))
                 (list g scv:*taper-dflt* t))))))))

;;; ======================================================================
;;;  THE HINGE PASS
;;; ======================================================================

;; Draw the hinges on the cover and return the report rows.  cpts is the
;; finished cover, flattened; grade and taper are whatever the taper
;; question settled on.
(defun scv:hingepass (cpts grade taper / bb across up longx wpts s1 s2 fo
                                        opts allowed best n xs fw fl mc mp
                                        allvel htys k x ch p q hty rows hw
                                        h vd nm)
  (setq bb (scv:bbox cpts)
        across (- (caddr bb) (car bb))
        up     (- (cadddr bb) (cadr bb))
        longx  (>= across up)
        wpts   (if longx cpts (scv:swap cpts))
        s1     (if longx (car bb) (cadr bb))
        s2     (if longx (caddr bb) (cadddr bb))
        allvel (= grade "THERMOLIGHT")
        fo     (scv:foamopts grade taper)
        opts   (car fo)
        allowed (cadr fo))
  (if allvel
      (scv:advise "THERMO-LIGHT: EVERY HINGE IS VELCRO - NO FOLD HINGE"))
  (if (not (caddr fo))
      (scv:note (strcat "GRADE/TAPER " grade " " taper
                        " NOT ON THE FOAM SHEET - 48/96 ASSUMED")))
  (setq best (scv:hbest wpts s1 s2 opts allowed)
        n  (car best)   xs (cadr best)
        fw (caddr best) fl (nth 3 best)
        mc (nth 7 best) mp (nth 8 best))
  (if (not (nth 4 best))
      (scv:note (strcat "A PIECE IS WIDER THAN THE FOAM SHEET ("
                        (rtos mp 2 1) " > " (rtos fw 2 1) ")")))
  (if (not (nth 6 best))
      (scv:note (strcat (itoa n) " PIECES NOT ACCEPTABLE FOR "
                        (scv:gradeshort grade) " " taper)))
  (if (> (length opts) 1)
      (scv:advise (strcat "FOAM SHEET USED: " (rtos fw 2 2) " x "
                          (if fl (rtos fl 2 0) "N/A")
                          " (this taper has " (itoa (length opts))
                          " sheets)")))
  ;; the hinges themselves, west to east -- or south to north on a cover
  ;; that is taller than it is wide, which is the same list read in the
  ;; frame it was solved in
  (setq htys (scv:hingetypes n allvel) k 0)
  (foreach x xs
    (setq ch (scv:chordpoly wpts x)
          hty (nth k htys))
    (if ch
        (progn
          (setq p (if longx (list x (car ch)) (list (car ch) x))
                q (if longx (list x (cadr ch)) (list (cadr ch) x)))
          (scv:line p q scv:*lay-cover* (if (= hty "H") (scv:hdash) nil))
          (scv:hlabel p q (if (= hty "H") "Hinge" "Velcro Hinge"))
          (if (and fl (> (- (cadr ch) (car ch)) (+ fl 0.01)))
              (scv:note (strcat "HINGE " (itoa (1+ k))
                                " EXCEEDS THE FOAM LENGTH ("
                                (rtos (- (cadr ch) (car ch)) 2 1)
                                " > " (rtos fl 2 0) ")")))))
    (setq k (1+ k)))
  (if (null fl)
      (scv:note "THERMOLIGHT: HINGE LENGTH N/A - VERIFY"))
  ;; hardware called for by the LONGEST hinge
  (setq hw nil)
  (foreach h scv:*hardtab*
    (if (and (not hw) (= (car h) grade)) (setq hw h)))
  (if hw
      (progn
        (setq k 0)
        (foreach nm scv:*hardnames*
          (setq vd (scv:hardverdict (nth (1+ k) hw) mc))
          (if (car vd)
              (scv:advise (strcat nm ": YES - " (cdr vd)))
              (scv:advise (strcat nm ": no - " (cdr vd))))
          (setq k (1+ k)))))
  ;; the rows: the pieces, the two foam limits, then each hinge's
  ;; position measured from the end the solver started at
  (setq rows (list (list (strcat "PIECES (" (scv:gradeshort grade) " "
                                 taper ")")
                         nil (itoa n) (not (nth 6 best)))
                   (list "FOAM WIDTH MAX" fw mp (not (nth 4 best)))
                   (list "FOAM LENGTH MAX" fl mc (not (nth 5 best)))
                   (list "HINGES RUN" nil
                         (if longx "UP (dividing across)"
                             "ACROSS (dividing up)"))))
  (setq k 0)
  (foreach x xs
    (setq rows (append rows
                       (list (list (strcat "HINGE " (itoa (1+ k))
                                           (if (= (nth k htys) "H")
                                               " (FOLD)" " (VELCRO)"))
                                   nil (- x s1))))
          k (1+ k)))
  rows)

;;; ======================================================================
;;;  THE COMMAND
;;; ======================================================================

(defun c:SPACOVCREATE ( / *error* undo-open qstep pre ss hv strands ellp
                          splines chained loops leftover picked sverts sarea
                          d gt grade taper assumed cverts cpts cbb circ
                          rows th across up size)

  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (scv:sysrestore)
    ;; command-s, never plain command: 2015+ engines reject (command)
    ;; inside *error* unless the error mode was pushed beforehand
    (if undo-open
      (progn
        (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
        ;; the run is one undo group, so whatever was half drawn goes
        ;; back in one keystroke -- say which, because a half-drawn cover
        ;; erased by hand is a half-drawn cover somebody misses a bit of
        (princ "\nNothing was left half done - use U to roll the run back.")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nSPACOVCREATE error: " msg)))
    (if lzd:report (lzd:report "SPACOVCREATE" *spacovcreate-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "SPACOVCREATE" *spacovcreate-version*))

  (setq scv:*notes* nil scv:*advice* nil)
  ;; the two this command actually changes -- it never touches CLAYER,
  ;; because every entmake here carries its own layer in DXF 8
  (scv:syssave '("OSMODE" "CMDECHO"))
  (setvar "CMDECHO" 0)
  ;; a highlight made before the command was typed is the spa -- probed
  ;; BEFORE the undo group opens, because _.UNDO _Begin clears the
  ;; pickfirst set (the convention LOBF and ABPCHECK already carry)
  (setq pre (ssget "_I" scv:*filter*))
  (if lzd:watch (lzd:watch pre))

  (princ (strcat "\n\nSPACOVCREATE " *spacovcreate-version*
                 " - the cover for a spa that is already drawn."))

  ;; -------- the three questions, walked with a step counter ----------
  (setq qstep 1)
  (while (and qstep (< qstep 4))
    (cond
      ;; 1 -- which geometry is the spa
      ((= qstep 1)
       (if pre
           (setq ss pre pre nil)
           (progn
             (princ "\nSelect the geometry that is the spa: ")
             (setq ss (ssget scv:*filter*))
             (if lzd:watch (lzd:watch ss))))
       (if (null ss)
           (progn (scv:say "Nothing selected - nothing to cover.")
                  (setq qstep nil))
           (progn
             (setq hv (scv:harvest ss)
                   strands (car hv)
                   ellp (cadr hv)
                   splines (caddr hv)
                   chained (scv:chain strands)
                   loops (car chained)
                   leftover (cadr chained)
                   picked (scv:pick-loop loops))
             (cond
               ((null picked)
                (scv:say (strcat (scv:plural (sslength ss)
                                             "object" "objects")
                                 " selected and nothing closes into an"
                                 " outline - check the walls meet at the"
                                 " corners."))
                (setq ss nil))
               (t
                (setq sverts (scv:st-verts (car picked))
                      sarea  (caddr picked))
                (scv:say (strcat (scv:plural (length loops)
                                             "closed outline" "closed outlines")
                                 " in the selection; the biggest is the spa ("
                                 (rtos (/ sarea 144.0) 2 1) " sq ft)."))
                (if (> leftover 0)
                    (scv:note (strcat (scv:plural leftover
                                                  "SELECTED RUN" "SELECTED RUNS")
                                      " NEVER CLOSED - IGNORED")))
                (if ellp
                    (scv:note (strcat "ELLIPSE OFFSET AS A POLYLINE - NO"
                                      " ELLIPSE IS PARALLEL TO ANOTHER")))
                (if (> splines 0)
                    (scv:note (strcat (scv:plural splines "SPLINE" "SPLINES")
                                      " NOT READ - EXPLODE OR FIT TO A POLYLINE")))
                (setq qstep 2))))))
      ;; 2 -- how far the cover laps
      ((= qstep 2)
       (setq d (scv:askdist "Cover offset past the spa"
                            scv:*offset-dflt* t))
       (if (eq d 'SCV-BACK)
           (progn (scv:say "Stepping back one question.")
                  (setq ss nil qstep 1))
           (setq qstep 3)))
      ;; 3 -- the taper
      ((= qstep 3)
       (setq gt (scv:askblock t))
       (if (eq gt 'SCV-BACK)
           (progn (scv:say "Stepping back one question.")
                  (setq qstep 2))
           (setq grade (car gt) taper (cadr gt) assumed (caddr gt)
                 qstep 4)))))

  ;; -------- draw it -------------------------------------------------
  (if (= qstep 4)
      (progn
        ;; A Thermo-Light comes in ONE taper, so the grade settles it:
        ;; a block with no readable TAPER tag on a Thermo-Light is not a
        ;; taper nobody gave, it is one the grade already answered -- and
        ;; flagging that as an assumption would send a drafter hunting
        ;; for a number that was never missing.  It is still SAID, in
        ;; cyan, because the taper on the sheet is not the one drawn to.
        (if (= grade "THERMOLIGHT")
            (progn
              (if (/= taper scv:*thermotaper*)
                  (scv:advise (strcat "TAPER TAKEN FROM THE GRADE - A"
                                      " THERMO-LIGHT IS "
                                      scv:*thermotaper*)))
              (setq taper scv:*thermotaper* assumed nil)))
        (if assumed
            (scv:note (strcat "TAPER NOT GIVEN - "
                              (scv:gradeshort scv:*grade-dflt*) " "
                              scv:*taper-dflt* " ASSUMED")))
        ;; only when undo is recording -- _Begin in a drawing with UNDO
        ;; off (bit 1 of UNDOCTL clear) errors out of the command
        (if (= 1 (logand 1 (getvar "UNDOCTL")))
            (progn (command "_.UNDO" "_Begin") (setq undo-open T)))
        (setvar "OSMODE" 0)
        (scv:ensure-layer scv:*lay-cover* scv:*col-cover*)
        (scv:ensure-layer scv:*lay-text* scv:*col-text*)
        (scv:ensure-layer scv:*lay-report* scv:*col-report*)
        (setq scv:*dashlt* (scv:ltmake scv:*hdashname*
                                       "Dashed (.5x) _ _ _ _ _ _ _ _ _ _"
                                       scv:*hdashpat*))
        (setq cverts (scv:offset sverts d)
              cpts   (scv:flatten cverts)
              circ   (scv:circlep cverts))
        (if circ
            (scv:circle (car circ) (cadr circ) scv:*lay-cover*)
            (scv:polyline cverts scv:*lay-cover*))
        (setq cbb (scv:bbox cpts)
              across (- (caddr cbb) (car cbb))
              up     (- (cadddr cbb) (cadr cbb))
              size   (max across up)
              th     (max scv:*th-min* (/ size scv:*th-div*)))
        (setq rows (append
                     (list (list "SPA OUTLINE" nil
                                 (strcat (scv:plural (sslength ss)
                                                     "object" "objects")
                                         ", "
                                         (scv:plural (length sverts)
                                                     "vertex" "vertices")))
                           (list "COVER OFFSET" nil d)
                           (list "COVER ACROSS" nil across)
                           (list "COVER UP" nil up)
                           (list "GRADE / TAPER" nil
                                 (strcat (scv:gradeshort grade) " " taper)
                                 assumed))
                     (scv:hingepass cpts grade taper)))
        (scv:report rows
                    (+ (caddr cbb) (* scv:*rep-gap* th))
                    (cadddr cbb)
                    th)
        (scv:say (strcat "Cover drawn on layer " scv:*lay-cover*
                         " - " (rtos across 2 2) " across x "
                         (rtos up 2 2) " up, "
                         (if scv:*notes*
                             (strcat (scv:plural (length scv:*notes*)
                                                 "thing" "things")
                                     " flagged.")
                             "nothing flagged.")))
        (if undo-open (command "_.UNDO" "_End"))
        (setq undo-open nil)))

  (scv:sysrestore)
  (princ))

;; Which build is loaded -- the first thing to check when a run does
;; something the notes above say it should not.
(defun c:SPACOVCREATEVER ()
  (princ (strcat "\nSPACOVCREATE " *spacovcreate-version*))
  (princ))

(princ (strcat "\nSPACOVCREATE " *spacovcreate-version*
               " loaded.  SPACOVCREATE to build a spa cover from the spa"
               " already on the sheet."))
(princ)
