;;; ====================================================================
;;;  POOL.LSP -- Swimming-pool as-built layout tool
;;;
;;;  Commands:  POOL     - lay out a pool from field measurements
;;;             POOLVER  - report which revision is loaded
;;;
;;;  Draws a pool plan (Rectangle, Oval, Grecian, L or Lazy L) from
;;;  field measurements.
;;;
;;;  First asks whether the pool is IN-SQUARE or OUT-OF-SQUARE.  An
;;;  in-square pool is built true to the side/end measurements and no
;;;  cross dims (diagonals) are asked for or drawn.  An out-of-square
;;;  pool takes the full cross-dim route described below.
;;;
;;;  Rectangle corners may be Square, Radius, Cut (a chamfer, sized
;;;  by its face length) or NotGiven -- not recorded on the order
;;;  sheet, so drawn square and flagged.  Side lengths are always to
;;;  the TRUE corner; the treatment cuts inward.  In-square assumes all
;;;  four corners identical; out-of-square asks per corner (Enter
;;;  reuses the previous corner).  When corners are cut and the pool is
;;;  out-of-square, the cross dims are measured from one of: the true
;;;  Corner, the Middle of the cut/arc, or its Ends (both endpoints of
;;;  each diagonal).  Square corners -> cross dims from the true corner.
;;;
;;;  Out-of-square details:
;;;
;;;    * A gray "guide" pool appears as soon as the shape is chosen;
;;;      while each measurement is prompted for, the matching element
;;;      of the guide turns red so you can see which dimension is
;;;      being asked for.  The guide is LIVE: every answer reshapes it
;;;      on the spot (the way an OASIS preview redraws before every
;;;      question), so the pool on screen grows out of the numbers as
;;;      they are typed instead of sitting at a fixed nominal size.
;;;      Once every dimension is in, the guide deletes itself and is
;;;      replaced by the true out-of-square pool.
;;;    * The full pool PERIMETER on layer POOL -- around the whole
;;;      shape including the Grecian corner cuts and oval end arcs
;;;      (drawn as individual lines/arcs, i.e. an exploded polyline).
;;;      Field measurements carry human error, so side lengths may be
;;;      held within +/-1" and cross dimensions within +/-2" of the
;;;      given values.
;;;    * Reference lines that are not part of the perimeter (the body
;;;      end lines under oval/Grecian ends, the oval radius
;;;      construction lines) go on POOL-NOTES with a DASHED linetype
;;;      (when acad.lin / acadiso.lin can be found).
;;;    * An exact as-measured two-triangle check (each triangle uses
;;;      one side, one end and the shared A-C cross dimension -- held
;;;      EXACTLY, no tolerance) is computed and reported as the
;;;      TRI CHECK B-D report row; the check figure itself is not
;;;      drawn, so out-of-square pools leave a clean drawing.
;;;    * Aligned dimensions for all sides and cross dims on layer
;;;      DIMENSION.  The two cross dims are drawn in the "CROSS
;;;      DIMENSION" dimension style when the drawing has one.
;;;    * A target / actual / delta report table to the right of the
;;;      drawing on POOL-NOTES.  When the cross dimensions cannot be
;;;      met within tolerance the sides are held true, the cross dims
;;;      get as close as possible, and "CROSS DIMS FAILED" is written
;;;      under the table.
;;;
;;;  Corner naming (plan view):   D ---------- C
;;;                               |            |     cross dims:
;;;                               |            |     A-C and B-D
;;;                               A ---------- B
;;;
;;;  Oval:    adds a radius line perpendicular to each end and a
;;;           three-point arc (end corner -> radius tip -> other end
;;;           corner) on both ends, plus a total-length check.  A SIDE
;;;           length that was not taped may be answered NA: the
;;;           overall spends its length on the two end bulges and the
;;;           straight body, so the side reads back off it.  An end
;;;           radius that was not given either is taken TANGENT to the
;;;           box around the pool -- the semicircle a true oval has --
;;;           which makes the side the overall less the width.
;;;  Grecian: 8-corner pool (body A/B/C/D plus angled-end tips
;;;           LT/LB left and RT/RB right).  Prompts for the six body
;;;           sides/ends, the four end diagonals and two end widths,
;;;           then cross dims at one of three detail levels:
;;;             Simple  = A-C, B-D            (2)
;;;             Center  = + LB-RT, LT-RB      (4, long tip-to-tip X)
;;;             Complex = every diagonal      (18, all pairs; NA any)
;;;           All 8 corners are best-fit against every provided cross
;;;           dim, so more cross dims pin the out-of-square shape down
;;;           more tightly.
;;;  L/LazyL: six-corner pools with one wing (square step joint for
;;;           the true L, angled joint for the lazy L); six sides plus
;;;           up to six cross dims, best-fit the same way.  An
;;;           IN-SQUARE lazy L is built rather than fitted: the main
;;;           section A-B / E-F / F-A (the deep end, where the hopper
;;;           is measured from) is held EXACTLY and comes out a true
;;;           rectangle, the 45-degree bends B-C and D-E stay
;;;           parallel, and whatever the six measurements fail to
;;;           close by is spread over the three WING sides.  Past the
;;;           1" side tolerance that is a bad tape, so those sides are
;;;           dimensioned red, listed red in the report and called out
;;;           as "SIDES DO NOT CLOSE" under it.
;;;
;;;  Every cross-dim prompt also accepts NA when that measurement was
;;;  not taken in the field: the fitter skips it and the report shows
;;;  N/A for its target and delta.
;;;
;;;  Drawing units are assumed to be INCHES (tolerances: 1" sides,
;;;  2" cross dims, 1/2" max Grecian diagonal adjustment in 1/8"
;;;  steps).  Values may be typed in the current drawing units, e.g.
;;;  20'6-1/2" when units are set to Architectural.
;;;
;;;  Written in plain AutoLISP (entmake + classic commands, no
;;;  ActiveX/VLA), so it loads in AutoCAD 2018 as well as older
;;;  releases.
;;; ====================================================================

;;; -------------------- version ---------------------------------------
;;;
;;;  This file is distributed under two names with IDENTICAL contents:
;;;
;;;      POOL.LSP                 the static name, for the APPLOAD stack
;;;      POOL_MMDDYY_REV##.LSP    the same file, named for its revision
;;;
;;;  Load either one.  The version below travels inside both, so a
;;;  stack that loaded the static name can still say which revision it
;;;  holds: type POOLVER.  Regenerate the pair with
;;;  tools/release_lisp.py.

(setq pool:*version* "090126 REV22")

;;; -------------------- adjustable constants --------------------------

(setq pool:*side-tol*  1.0)     ; side length tolerance (drawing units)
(setq pool:*cross-tol* 2.0)     ; cross dimension tolerance
(setq pool:*grec-step* 0.125)   ; Grecian diagonal adjustment increment
(setq pool:*grec-max*  4)       ; max increments each way (4 * 1/8 = 1/2)
(setq pool:*base*      (list 0.0 0.0))
(setq pool:*dashlt*    "CONTINUOUS")  ; resolved to DASHED per run
(setq pool:*dotlt*     "CONTINUOUS")  ; resolved to POOLDOT per run
(setq pool:*lts*       1.0)           ; (legacy, unused: see pool:ltsc)
(setq pool:*mlkoff*    30.0)          ; M/L/K dim line offset right of the hopper
(setq pool:*pvents*    nil)           ; live guide-preview entities
(setq pool:*insq*      nil)           ; T = in-square pool (no cross dims)
;; Entities making up the side profile (section) and its depth dims.
;; An L pool's mirror flips the PLAN top-to-bottom; a longitudinal
;; section is unchanged by that, so these are held out of it.
(setq pool:*profents*  nil)

;; Bottom-type keywords, shared by the rectangle / oval / grecian
;; dispatchers.  Normal and the four special bottoms all run through
;; pool:hopnormal (they are the same plan chain with G and/or E
;; pinned); Sport is the symmetric full-width bottom.  L / Lazy L
;; pools take the standard hopper only and are not asked.
(setq pool:*btypes*   "Normal Sport Wedge SLope MOdflat SHallow")
(setq pool:*btshown* "Normal/Sport/Wedge/SLope/MOdflat/SHallow")
(setq pool:*sq4* (list (list "Square" 0.0) (list "Square" 0.0)
                       (list "Square" 0.0) (list "Square" 0.0)))
;; How far off 90 a corner may sit and still be marked "90%%d" on the
;; sheet.  This separates two POPULATIONS, so it wants to sit between
;; them rather than hug either: a pool the crew still calls a
;; rectangle can fit several degrees off square (240x120 with cross
;; dims 12" apart fits at 86.8 / 93.2), while the corners this gate
;; exists to refuse -- a grecian's cut corners and an L's bend -- are
;; 135, a full 45 degrees away.  20 degrees clears any real rectangle
;; and still leaves more than twice that margin to 135.
(setq pool:*sq90-tol* (* pi (/ 20.0 180.0)))
;; How far a wall dim may read off its true corner-to-corner run in
;; order to keep both of its extension lines ON the pool -- see the
;; "dims attached to the pool" block below.  A corner UNDER 90 degrees
;; pokes out past its own treatment, so the drawn edge near it starts a
;; little way up the wall and the far end cannot always meet it exactly
;; there.  Splitting that mismatch between the two ends costs 1/16" on
;; a pool built two degrees off square and a thousandth of an inch on
;; one built a quarter-degree off -- under what a tape can read either
;; way, so the dim still says what was measured.  A genuinely sharp
;; corner misses by INCHES, blows this budget, and keeps the true
;; corners instead.
(setq pool:*hookslack* 0.0625)
(setq pool:*valnotes* nil)            ; validation problems for the report

;; Measurements under pool:*smalldim* are dimensioned in the drawing's
;; "STANDARD INCHES" dim style (see pool:dimsbegin); the missing-style
;; note is printed at most once per run.  Cross dims (the diagonal
;; block, any shape) use pool:*crossstyle* instead -- see pool:dimxbegin.
;;
;; The SECONDARY perimeter letters -- the ones the field sheets stack
;; against an overall (S, S1, T, V, the end radii, an L's wing/step
;; sides, the six-sided hopper's W/L1/X) -- go in pool:*sidestyle*
;; ("SIDE STANDARD"), per the reference drawings.  A dim inside a
;; SIDE STANDARD block keeps that style even under 24 inches: the
;; reference sheets show a 19" S1 in SIDE STANDARD, not inches.
;; The cut-off is "UNDER 24 inches": a 2 ft corner is a STANDARD dim,
;; not an inches one.  It has to be read with a hair of tolerance,
;; because most of these lengths are not the number the crew typed --
;; they are measured back off geometry the routine built from it, and a
;; 24" radius corner comes back as 23.99999999999913 as readily as
;; 24.000000000001137 (a three-point arc's circumcentre, a treated
;; corner's two end points).  Compared raw, the same 2 ft corner draws
;; in inches or not depending on which way the last bit fell.  The
;; tolerance is float noise only -- a MILLIONTH of an inch, a million
;; times the noise it absorbs and orders below the 1/16" a tape can
;; read, so every real measurement under 2 ft is still an inches dim.
(setq pool:*smalldim*    24.0)
(setq pool:*smallfuzz*   1.0e-6)
(setq pool:*smallstyle*  "STANDARD INCHES")
(setq pool:*smallwarned* nil)
(setq pool:*crossstyle*  "CROSS DIMENSIONS")
(setq pool:*sidestyle*   "SIDE STANDARD")
(setq pool:*sideon*      nil)         ; a SIDE STANDARD block is open
(setq pool:*dimstyle0*   nil)         ; dim style current when POOL started
;; T = report lengths in feet-inches; set per run from the units the
;; DRAWING was in before POOL switched to architectural for its
;; prompts (getdist keeps only the value, never how it was typed, so
;; the drawing's own units are the crew's declared preference).
(setq pool:*ftin*        nil)

;;; -------------------- small vector helpers --------------------------

(defun pool:d2r (a) (* pi (/ a 180.0)))

(defun pool:v+ (p q) (list (+ (car p) (car q)) (+ (cadr p) (cadr q))))

(defun pool:v- (p q) (list (- (car p) (car q)) (- (cadr p) (cadr q))))

(defun pool:v* (p s) (list (* (car p) s) (* (cadr p) s)))

(defun pool:dot (p q) (+ (* (car p) (car q)) (* (cadr p) (cadr q))))

(defun pool:perp (p) (list (- (cadr p)) (car p)))

(defun pool:mid (p q) (pool:v* (pool:v+ p q) 0.5))

(defun pool:unit (p / d)
  (setq d (sqrt (pool:dot p p)))
  (if (> d 1.0e-12) (pool:v* p (/ 1.0 d)) (list 0.0 0.0)))

;; local 2D point -> world 3D point (applies the insertion base)
(defun pool:wp (p)
  (list (+ (car p) (car pool:*base*))
        (+ (cadr p) (cadr pool:*base*))
        0.0))

;;; -------------------- geometry ---------------------------------------

;; Intersection of circle (c1 r1) with circle (c2 r2).
;; side = 1.0 -> point on the left of the c1->c2 direction, -1.0 -> right.
;; Returns a 2D point or nil when the circles do not intersect.
(defun pool:circint (c1 r1 c2 r2 side / d ux uy a h2 h bx by)
  (setq d (distance c1 c2))
  (if (> d 1.0e-9)
      (progn
        (setq ux (/ (- (car c2) (car c1)) d)
              uy (/ (- (cadr c2) (cadr c1)) d)
              a  (/ (+ (* d d) (* r1 r1) (- (* r2 r2))) (* 2.0 d))
              h2 (- (* r1 r1) (* a a)))
        (if (> h2 -1.0e-6)
            (progn
              (setq h  (sqrt (max h2 0.0))
                    bx (+ (car c1) (* a ux))
                    by (+ (cadr c1) (* a uy)))
              (list (+ bx (* side h (- uy)))
                    (+ by (* side h ux))))))))

;; Circumcenter of three points, or nil when collinear.
(defun pool:circum (p1 p2 p3 / ax ay bx by cx cy dd)
  (setq ax (car p1) ay (cadr p1)
        bx (car p2) by (cadr p2)
        cx (car p3) cy (cadr p3)
        dd (* 2.0 (+ (* ax (- by cy)) (* bx (- cy ay)) (* cx (- ay by)))))
  (if (> (abs dd) 1.0e-9)
      (list (/ (+ (* (+ (* ax ax) (* ay ay)) (- by cy))
                  (* (+ (* bx bx) (* by by)) (- cy ay))
                  (* (+ (* cx cx) (* cy cy)) (- ay by)))
               dd)
            (/ (+ (* (+ (* ax ax) (* ay ay)) (- cx bx))
                  (* (+ (* bx bx) (* by by)) (- ax cx))
                  (* (+ (* cx cx) (* cy cy)) (- bx ax)))
               dd))))

(defun pool:npos (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;;; -------------------- entity makers ----------------------------------

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked (STANDARDS section 5).  Without the repair
;; a run onto a frozen or switched-off DIMENSION layer looks like the
;; command drew nothing.
(defun pool:layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
      (entmake (list '(0 . "LAYER")
                     '(100 . "AcDbSymbolTableRecord")
                     '(100 . "AcDbLayerTableRecord")
                     (cons 2 name)
                     '(70 . 0)
                     (cons 62 color)
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
              (princ (strcat "\nPOOL: layer " name
                             " was off, frozen or locked - restored so"
                             " the result is visible."))))))
  name)

(defun pool:line (p1 p2 lay)
  (entmake (list '(0 . "LINE")
                 (cons 8 lay)
                 (cons 10 (pool:wp p1))
                 (cons 11 (pool:wp p2)))))

;; Build a linetype from an explicit pattern (positive = dash length,
;; 0 = dot, negative = gap), all in drawing units (inches).  Done with
;; entmake rather than loading acad.lin: a failed load used to fall
;; back to CONTINUOUS silently, which is why dashes could vanish.
;; Returns the linetype name.
(defun pool:ltmake (name descr pat / lst x)
  (if (not (tblsearch "LTYPE" name))
      (progn
        (setq lst (list '(0 . "LTYPE")
                        '(100 . "AcDbSymbolTableRecord")
                        '(100 . "AcDbLinetypeTableRecord")
                        (cons 2 name)
                        '(70 . 0)
                        (cons 3 descr)
                        '(72 . 65)
                        (cons 73 (length pat))
                        (cons 40 (apply '+ (mapcar 'abs pat)))))
        (foreach x pat
          (setq lst (append lst (list (cons 49 x) '(74 . 0)))))
        (entmake lst)))
  (if (tblsearch "LTYPE" name) name "CONTINUOUS"))

;; Per-entity linetype scale that cancels the drawing's LTSCALE, so a
;; pattern defined in inches always plots at that size no matter how
;; the host drawing is set up.
(defun pool:ltsc ( / s)
  (setq s (getvar "LTSCALE"))
  (if (or (null s) (<= s 0.0)) 1.0 (/ 1.0 s)))

;; Kept for compatibility: our patterns are self-defined now.
(defun pool:ltload (name)
  (if (= name "DOT")
      (pool:ltmake "POOLDOT" "Pool guide dot . . . . . . . ." '(0.0 -1.0))
      (pool:ltmake "POOLDASH" "Pool dashed __ __ __ __" '(12.0 -12.0))))

;; Dashed reference line on POOL-NOTES.
(defun pool:lined (p1 p2)
  (entmake (append (list '(0 . "LINE")
                         (cons 8 "POOL-NOTES")
                         (cons 10 (pool:wp p1))
                         (cons 11 (pool:wp p2)))
                   (if (/= pool:*dashlt* "CONTINUOUS")
                       (list (cons 6 pool:*dashlt*)
                             (cons 48 (pool:ltsc)))))))

;; Dotted WHITE guide line -- the cross dims and other measuring lines
;; on the input screen, so they read clearly over the pool outline.
(defun pool:linedot (p1 p2)
  (entmake (append (list '(0 . "LINE")
                         (cons 8 "POOL-NOTES")
                         (cons 62 pool:*pvx-col*)
                         (cons 10 (pool:wp p1))
                         (cons 11 (pool:wp p2)))
                   (if (/= pool:*dotlt* "CONTINUOUS")
                       (list (cons 6 pool:*dotlt*)
                             (cons 48 (pool:ltsc)))))))

(defun pool:text (pt h str lay)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 10 (pool:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

(defun pool:textc (pt h str lay col)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 62 col)
                 (cons 10 (pool:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

;; Three-point arc through p1 -> p2 -> p3 (falls back to a line when
;; the points are collinear).
(defun pool:arc3p (p1 p2 p3 lay / o r a1 a2 a3 da2 da3 s e)
  (setq o (pool:circum p1 p2 p3))
  (if o
      (progn
        (setq r  (distance o p1)
              a1 (angle o p1)
              a2 (angle o p2)
              a3 (angle o p3)
              da2 (pool:npos (- a2 a1))
              da3 (pool:npos (- a3 a1)))
        (if (< da2 da3)
            (setq s a1 e a3)
            (setq s a3 e a1))
        (entmake (list '(0 . "ARC")
                       (cons 8 lay)
                       (cons 10 (pool:wp o))
                       (cons 40 r)
                       (cons 50 s)
                       (cons 51 e))))
      (pool:line p1 p3 lay)))

;;; Small dimensions read in inches.  Any measurement under 24" is
;;; drawn in the "STANDARD INCHES" dim style when the drawing has one
;;; -- under, so a 2 ft corner is a STANDARD dim (pool:*smallfuzz*
;;; keeps that true when the 24 is measured back off the geometry),
;;; and the previous style comes straight back afterwards.  Every
;;; dimension the routine draws goes through pool:dimalg / pool:dimrot
;;; / pool:dimrad / pool:dimcorner1, so switching in those four covers
;;; plan dims, hopper chain dims, corner treatments, radii and the
;;; side-profile depths alike.  (Angular corner dims measure degrees,
;;; not inches, so they are left alone.)

(defun pool:dimsbegin (d / odim)
  ;; inside a SIDE STANDARD block the letter keeps that style however
  ;; small it is -- the reference sheets show a 19" S1 in SIDE
  ;; STANDARD, not in inches
  (if (and (< d (- pool:*smalldim* pool:*smallfuzz*)) (not pool:*sideon*))
      (if (tblsearch "DIMSTYLE" pool:*smallstyle*)
          (progn
            (setq odim (getvar "DIMSTYLE"))
            ;; already current -> nothing to switch, nothing to undo
            (if (= (strcase odim) (strcase pool:*smallstyle*))
                (setq odim nil)
                (command "_.-DIMSTYLE" "_Restore" pool:*smallstyle*))
            odim)
          (progn
            (if (not pool:*smallwarned*)
                (progn
                  (princ (strcat "\n(no \"" pool:*smallstyle*
                                 "\" dim style in this drawing -- dims under "
                                 (rtos pool:*smalldim*)
                                 " drawn in the current style)"))
                  (setq pool:*smallwarned* t)))
            nil))))

(defun pool:dimsend (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim))
      (command "_.-DIMSTYLE" "_Restore" odim)))

;; One dimension between two drawn points.  A horizontal or vertical
;; pair comes out as a true linear dimension (DIMLINEAR, orientation
;; forced so the placement point can't flip it); only a genuinely
;; skewed edge -- an out-of-square wall, a grecian chord -- still needs
;; DIMALIGNED.
(defun pool:dimalg (p1 p2 pt / od)
  (setq od (pool:dimsbegin (distance p1 p2)))
  (cond
    ((< (abs (- (cadr p1) (cadr p2))) 1.0e-6)
     (command "_.DIMLINEAR" (pool:wp p1) (pool:wp p2) "_H" (pool:wp pt)))
    ((< (abs (- (car p1) (car p2))) 1.0e-6)
     (command "_.DIMLINEAR" (pool:wp p1) (pool:wp p2) "_V" (pool:wp pt)))
    (t
     (command "_.DIMALIGNED" (pool:wp p1) (pool:wp p2) (pool:wp pt))))
  (pool:dimsend od))

;; Radius dimension ON the arc, read from OUTSIDE it: the arc is picked
;; at its far point and the dimension line is dragged further out along
;; the same direction, so the leader comes in from outside instead of
;; running back to the circle centre.
(defun pool:dimrad (ent tip outd doff / od)
  (if (and ent (entget ent) (= "ARC" (cdr (assoc 0 (entget ent)))))
      (progn
        (setq od (pool:dimsbegin (cdr (assoc 40 (entget ent)))))
        (command "_.DIMRADIUS" (list ent (pool:wp tip))
                 (pool:wp (pool:v+ tip (pool:v* outd (* 0.9 doff)))))
        (pool:dimsend od))
      ;; a degenerate end (bulge ~ 0) drew a straight line instead
      (princ "\n(radius dim skipped -- the end came out flat, no arc)")))

;; Rotated linear dimension hooked to two OBJECT points: the ext-line
;; origins land on drawn geometry (wall endpoints / arc tangents), and
;; the rotation makes it read the full run regardless of the hooks.
(defun pool:dimrot (p1 p2 ang loc / od)
  ;; a rotated linear dim measures the RUN along ang, not p1->p2
  (setq od (pool:dimsbegin (abs (pool:dot (pool:v- p2 p1)
                                          (list (cos ang) (sin ang))))))
  (command "_.DIMLINEAR" (pool:wp p1) (pool:wp p2)
           "_R" (angtos ang 0 6) (pool:wp loc))
  (pool:dimsend od))

;; Switch to the CROSS DIMENSIONS dim style when the drawing has one.
;; Cross dims are drawn ByLayer (no per-entity color/linetype/lineweight
;; override) -- their look (dashed or otherwise) comes entirely from
;; that dim style and the DIMENSION layer, same as every other dim.
;; Returns the previous style name (for pool:dimxend), or nil.
(defun pool:dimxbegin ( / odim)
  (if (tblsearch "DIMSTYLE" pool:*crossstyle*)
      (progn
        (setq odim (getvar "DIMSTYLE"))
        (command "_.-DIMSTYLE" "_Restore" pool:*crossstyle*)
        odim)))

(defun pool:dimxend (odim)
  (if (and odim (tblsearch "DIMSTYLE" odim))
      (command "_.-DIMSTYLE" "_Restore" odim)))

;; Switch to the SIDE STANDARD dim style (the secondary sheet
;; letters) when the drawing has one -- see the note above
;; pool:*sidestyle*.  While the block is open, the under-24" switch is
;; suppressed (pool:*sideon*).  Missing style -> current style, and
;; the under-24" rule stays live.
(defun pool:dimsdbeg ( / odim)
  (if (tblsearch "DIMSTYLE" pool:*sidestyle*)
      (progn
        (setq odim (getvar "DIMSTYLE"))
        (if (= (strcase odim) (strcase pool:*sidestyle*))
            (setq odim nil)
            (command "_.-DIMSTYLE" "_Restore" pool:*sidestyle*))
        (setq pool:*sideon* t)
        odim)))

(defun pool:dimsdend (odim)
  (setq pool:*sideon* nil)
  (if (and odim (tblsearch "DIMSTYLE" odim))
      (command "_.-DIMSTYLE" "_Restore" odim)))

;; One aligned dim / radius dim in the SIDE STANDARD style.
(defun pool:dimalgs (p1 p2 pt / od)
  (setq od (pool:dimsdbeg))
  (pool:dimalg p1 p2 pt)
  (pool:dimsdend od))

(defun pool:dimrads (ent tip outd doff / od)
  (setq od (pool:dimsdbeg))
  (pool:dimrad ent tip outd doff)
  (pool:dimsdend od))

;; Point offset outward (away from cen) from the midpoint of p->q.
;; A negative dist offsets inward instead.
(defun pool:outoff (p q cen dist / m n)
  (setq m (pool:mid p q)
        n (pool:unit (pool:perp (pool:v- q p))))
  (if (< (pool:dot (pool:v- m cen) n) 0.0)
      (setq n (pool:v* n -1.0)))
  (pool:v+ m (pool:v* n dist)))

;;; -------------------- user input -------------------------------------

;; The user's own object snaps stay LIVE during every measurement
;; prompt (typed input is unaffected; a picked point can snap onto
;; existing geometry).  OSMODE is zeroed only while the routine feeds
;; points to commands, where a snap would grab the wrong geometry.
(defun pool:osup ( / p)
  (setq p (assoc "OSMODE" pool:*sysold*))
  (if p (setvar "OSMODE" (cdr p))))

(defun pool:osdown () (setvar "OSMODE" 0))

(defun pool:ask (msg / v)
  (pool:osup)
  (initget 7)                           ; no null, no zero, no negative
  (setq v (getdist (strcat "\n" msg ": ")))
  (pool:osdown)
  v)

;;; -------------------- measurement sequences (Back) -------------------
;;;
;;;  A block of related measurements runs through pool:askseq so every
;;;  prompt after the first also offers *Back*, which re-asks the
;;;  previous question -- a typo no longer means Esc and start over.
;;;  Each item: (key kind msg ents dflt skip skipmsg sug)
;;;    key   symbol the answer is stored under
;;;    kind  REQ  a value is required
;;;          NAX  NA accepted (returns nil)
;;;          ZER  NA accepted, zero accepted
;;;          SUG  NA accepted, suggested default (Enter takes it)
;;;    ents  guide entities highlighted while prompted
;;;    dflt  for SUG: a number, or a list of keys -- the first of those
;;;          keys with a non-nil answer supplies the suggestion
;;;    skip  optional quoted expression; non-nil -> answered 0.0 unasked
;;;    sug   optional quoted expression, evaluated just before asking
;;;          (it sees the answers so far, in ans): a number from it is
;;;          the suggestion -- one WORKED OUT from what has been given
;;;          rather than copied off another letter, e.g. the last
;;;          member of a chain, which is whatever the total has left.
;;;          It beats dflt, and it turns a plain NA question into one
;;;          Enter can answer.  A REQ or ZER question keeps its kind:
;;;          those two mean something about what is a valid answer,
;;;          not about what is offered.

(defun pool:sq (ans key) (cdr (assoc key ans)))

(defun pool:sqput (ans key v / out p)
  (foreach p ans (if (not (eq (car p) key)) (setq out (cons p out))))
  (reverse (cons (cons key v) out)))

(defun pool:sqfirst (ans keys / out k)
  (foreach k keys
    (if (and (not out) (pool:sq ans k)) (setq out (pool:sq ans k))))
  out)

;; What a chain has LEFT for its last member: the total less every
;; other member, once all of them have been answered.  This is the
;; suggestion a crew gets when the second-to-last letter of a loop
;; goes in -- H, G and F given means E can only be one number, so it
;; is offered rather than asked for cold (Enter takes it, NA still
;; leaves it to pool:chainfix, and typing over it still wins).
;;
;; nil unless every named key carries a real answer and what is left
;; is a length that could be built: a chain already over its total
;; must not suggest a negative offset, and one that lands on the total
;; exactly has nothing left to suggest.
(defun pool:chainrest (ans keys total / out k v)
  (setq out total)
  (foreach k keys
    (if out
        (if (setq v (pool:sq ans k))
            (setq out (- out v))
            (setq out nil))))
  (if (and out (> out 1.0e-6)) out))

;; M answered the same as H is the crew saying the deep end sits
;; SQUARE in the pool -- the same offset off every wall -- so the
;; hopper width is what is left with that offset taken off both sides:
;; 2M + L = A.  Suggest it; anything else (M measured different from
;; H, or either one not given) has nothing to say about L and asks.
(defun pool:sugsym (ans total / m h rest)
  (setq m (pool:sq ans 'm)
        h (pool:sq ans 'h))
  (if (and m h (equal m h 0.5))
      (progn
        (setq rest (- total (* 2.0 m)))
        (if (> rest 1.0e-6) rest))))

;; A pool is typically about twice as long as it is wide, so the WIDTH
;; question is offered half the length rather than asked cold: 36'
;; across suggests 18' up the end, Enter takes it, and a real tape
;; reading typed over it still wins.  It is a shape hint, not a
;; measurement -- the report still lists what was entered against what
;; was drawn either way.
;;
;; keys are the length answers to average (both sides out of square,
;; the one pair in square); a side nobody measured is skipped, and a
;; question reached with no length at all behind it has nothing to
;; suggest and is asked cold.
(defun pool:sughalf (ans keys / n tot v k)
  (setq n 0 tot 0.0)
  (foreach k keys
    (if (setq v (pool:sq ans k))
        (setq tot (+ tot v) n (1+ n))))
  (if (> n 0)
      (progn
        (setq v (* 0.5 (/ tot n)))
        (if (> v 1.0e-6) v))))

;;; -------------------- form answers -----------------------------------
;;;
;;;  A form -- the LAZFORM dialog, or the VB palette -- can answer some
;;;  or all of POOL's questions before the run starts.  It leaves them
;;;  in pool:*form* as (key . value) and the ask helpers below look
;;;  there first, so a filled-in sheet drives the whole run and a
;;;  half-filled one simply shortens it.
;;;
;;;  Three states, and the difference between the last two IS the
;;;  feature:
;;;
;;;    key absent      the form did not answer it   -> ask, as usual
;;;    (key . nil)     the form answered NA         -> nil, no prompt
;;;    (key . 84.0)    the form answered it         -> 84.0, no prompt
;;;
;;;  (assoc key ...) tells those apart; (cdr (assoc ...)) alone cannot.
;;;  Get it backwards and a half-filled form is either impossible or
;;;  silent, and the half-filled form is the whole point.
;;;
;;;  AN ANSWER IS REMOVED AS IT IS USED.  Not marked used -- removed.
;;;  Otherwise Back deadlocks: step back onto a form-answered question,
;;;  it answers itself instantly and walks forward again, and there is
;;;  no key the user can press to get out.  Consuming also gives the
;;;  range checks their way out: pool:askdeep re-asks through pool:askh
;;;  when a depth fails its check, and the second pass finds the store
;;;  empty and lets the user type the correction -- rather than being
;;;  re-fed the same bad number for ever.

(setq pool:*form* nil)

;; Cover mode: no pool bottom, so the gate in pool:askbottom answers No
;; and the whole depth interrogation behind it never runs.  Set by
;; POOLCOVER (and by LAZFORM's cover twin), cleared on both exits from
;; c:POOL.  nil for a typed POOL, always.
(setq pool:*nobottom* nil)

;; Did the form answer KEY at all?  This is the absent/nil distinction
;; that (cdr (assoc ...)) throws away.
(defun pool:fhas (key) (if (assoc key pool:*form*) t nil))

;; The form's answer for KEY, removed from the store as it is read.
(defun pool:ftake (key / p)
  (setq p (assoc key pool:*form*))
  (setq pool:*form* (vl-remove p pool:*form*))
  (cdr p))

(defun pool:fclear () (setq pool:*form* nil))

;; The letter a prompt leads with, as a form key.  The depth questions
;; are asked through pool:askh, which carries no key of its own, but
;; their prompts all read "<letter> - <what it is>": "C - wall height
;; (shallow depth)" is 'c, "C2 - depth where the shallow floor meets
;; the break" is 'c2, and both spellings of D are 'd.  ONLY that exact
;; shape counts -- "Total pool length (arc tip to arc tip)" leads with
;; no letter and must come back nil so it prompts, rather than eating
;; whatever answer happens to be under that name in the store.
(defun pool:fkeyof (msg / n s out)
  (setq n 1)
  (while (and (not out) (<= n 2))
    (if (= (substr msg (1+ n) 3) " - ")
        (progn
          (setq s (strcase (substr msg 1 n) t))
          (if (wcmatch s "@,@#") (setq out (read s)))))
    (setq n (1+ n)))
  out)

;; The form-key stem for a corner question, from the subject string
;; every flow already passes pool:askcorner -- "Corner A" is cornera,
;; and the collective questions get names of their own.  A subject no
;; form addresses comes back nil and the corner is asked as always.
(defun pool:fckey (subject / s)
  (setq s (strcase subject t))
  (cond
    ((= s "all four corners") "corners")
    ((= s "the deep end corners a and d") "deepcorners")
    ((= s "the shallow end corners b and c") "shalcorners")
    ((= s "the outer corners") "outercorners")
    ((= s "the inner corner e") "innercorner")
    ((= s "the body corners a, b, c and d") "bodycorners")
    ((= s "the end-tip corners lt, lb, rt and rb") "endcorners")
    ((and (> (strlen s) 7) (= (substr s 1 7) "corner "))
     (strcat "corner" (substr s 8)))))

;; The shape, from the form when it named one the dispatch knows, else
;; asked.  Checked against the same list the prompt offers: an unknown
;; shape would fall through the cond at the foot of c:POOL into the
;; rectangle branch and draw the wrong pool without saying so.
(defun pool:fshape ( / v)
  (if (pool:fhas 'shape) (setq v (pool:ftake 'shape)))
  (if (and v (= (type v) 'STR)
           (member v '("Rectangle" "Grecian" "ROman" "L" "LAzyl"
                       "Oval" "OCtagon" "ROUnd" "MUtt")))
      v
      (progn
        (initget 1 "Rectangle Grecian ROman L LAzyl Oval OCtagon ROUnd MUtt")
        (getkword
          (strcat "\nPool shape [Rectangle/Grecian/ROman/L/LAzyl/Oval/"
                  "OCtagon/ROUnd/MUtt]: ")))))

;; Run POOL with a form's answers already in hand.  Nothing happens
;; here that the direct path misses: a caller may equally set
;; pool:*form* itself and call c:POOL, which is what the tests do.
(defun pool:run-with-answers (answers)
  (setq pool:*form* answers)
  (c:POOL)
  (pool:fclear)
  (princ))

;; One prompt of a sequence.  Returns the value, nil for NA, or the
;; symbol POOL-BACK.
;; Kinds: REQ a measurement that must be given, NAX one that may be
;; NA, ZER one that may be zero, SUG an NAX with a worked-out value
;; offered on Enter -- and SUGR the same offer on a REQUIRED question.
;; SUGR is what a suggestion does to a REQ: Enter takes the number,
;; but NA is still not on the table, because the answer is still one
;; the pool cannot be drawn without.
(defun pool:asks (kind msg ents dflt back / v cols kw)
  (setq cols (mapcar 'pool:getcol ents))
  (foreach e ents (pool:setcol e pool:*hi-col*))
  (pool:osup)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((member kind '(REQ SUGR)) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  (if kw
      ;; REQ always rejects zero (bit 7) - offering Back must not
      ;; loosen what counts as a valid measurement; ZER alone admits 0
      (initget (cond ((eq kind 'ZER) 5)
                     ((and (member kind '(SUG SUGR)) dflt) 6)
                     (t 7))
               kw)
      (initget 7))
  (setq v (getdist
            (strcat "\n" msg
                    (cond ((eq kind 'REQ) "")
                          ((eq kind 'SUGR)
                           (if dflt (strcat " <" (rtos dflt) ">") ""))
                          ((eq kind 'SUG)
                           (if dflt (strcat " <" (rtos dflt) "> (or NA)")
                               " (or NA)"))
                          (t " (or NA if not measured)"))
                    (if back " [Back]" "")
                    ": ")))
  (pool:osdown)
  (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'POOL-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ;; Enter took the suggestion
        ((and (null v) (member kind '(SUG SUGR))) dflt)
        (t v)))

;; Keyword question that can also be backed out of.  kws is the
;; initget string, shown is the bracketed list, dflt the Enter answer
;; (nil = an answer is required).  Returns the keyword or POOL-BACK.
(defun pool:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'POOL-BACK)
        ((null v) (if dflt dflt (pool:askkw msg kws shown dflt back)))
        (t v)))

;; The keyword question a form can answer.  Deliberately a WRAPPER and
;; not a sixth argument on pool:askkw: the grouped build swaps that
;; helper out for cal:askkw, which takes five, so widening it here
;; would have the twin call the library with an argument it does not
;; accept -- a build that loads cleanly and dies at the first keyword
;; question.  The mirror leaves this defun alone, while the pool:askkw
;; call inside it is rewritten like any other call site.
(defun pool:askkwf (key msg kws shown dflt back / v)
  (if (and (pool:fhas key)
           (setq v (pool:ftake key))
           (= (type v) 'STR)
           (setq v (pool:fkword v kws)))
      v
      (pool:askkw msg kws shown dflt back)))

;; V as the question would spell it, or nil when the question does not
;; accept it at all.  Two jobs in one walk of the keyword list:
;;
;;   - an answer the question does not offer falls through to the
;;     prompt instead of being handed on to fail later.  The shape
;;     charts show bottoms POOL cannot draw, and a form built from a
;;     chart will offer them;
;;   - the canonical SPELLING comes back, not the caller's.  Every test
;;     downstream is (= btype "Wedge"), so a form that said "wedge"
;;     would sail through a case-insensitive check and then match
;;     nothing at all.
(defun pool:fkword (v kws / i n c w out)
  (setq i 1 n (strlen kws) w "" v (strcase v))
  (while (<= i (1+ n))
    (setq c (if (<= i n) (substr kws i 1) " "))
    (if (= c " ")
        (progn
          (if (and (/= w "") (= (strcase w) v)) (setq out w))
          (setq w ""))
        (setq w (strcat w c)))
    (setq i (1+ i)))
  out)

;; Yes/No that can be backed out of.  Returns T, nil or POOL-BACK.
(defun pool:askyn (msg dflt back / v)
  (setq v (pool:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'POOL-BACK) v (= v "Yes")))

;; The Yes/No question a form can answer.  A wrapper over pool:askkwf
;; for pool:askkwf's own reason: pool:askyn is swapped for the library's
;; in the grouped build, so neither may grow an argument.  The form
;; answers "Yes" or "No" -- the same words a click on the bracket would
;; send -- and pool:fkword holds it to exactly those, so anything else
;; in the box falls through to the prompt.  Returns T, nil or
;; POOL-BACK, like pool:askyn.
(defun pool:askynf (key msg dflt back / v)
  (setq v (pool:askkwf key msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'POOL-BACK) v (= v "Yes")))

;; THE POOL-BOTTOM GATE.  The same question in five places, one per
;; shape family, and everything behind it -- the wall height C, the
;; break depth C2, the deep end D, the hopper type and its corner
;; method -- is asked only if the answer is Yes.
;;
;; A cover sheet records no floor work at all, so there is nothing on
;; the other side of this question worth asking for: POOLCOVER sets
;; pool:*nobottom* and the gate answers No without appearing.  That is
;; the whole of "cover mode" -- one gate, closed.
;;
;; It is a run flag rather than an entry in pool:*form* on purpose.
;; The store is consume-once (an answer is removed as it is read, so a
;; range check can escape to the keyboard and Back cannot deadlock),
;; which is right for a measurement asked once and wrong for a gate
;; that five different shape paths may reach.  A flag answers wherever
;; the run happens to land.
;;
;; Like the store, it is cleared on the way out of c:POOL -- both exits
;; -- so a cover run can never leave the next POOL silently bottomless.
(defun pool:askbottom ()
  (if pool:*nobottom*
      nil
      (pool:askyn "Add pool bottom (hopper) detail?" "Yes" nil)))

;; The Treatment question (STANDARDS.md section 2), the one vocabulary
;; every corner in this file is answered in:
;;
;;   How should <subject> be treated? [Square/Radius/Cut/NotGiven] <prev>:
;;
;; subject reads like prose -- "Corner A", "the outer corners" -- and
;; is reused verbatim in the size follow-up, so the two questions read
;; as one.  The four answers mean:
;;   Square   a true sharp corner, nothing cut
;;   Radius   a filleted corner, sized by its RADIUS
;;   Cut      a straight chamfer, sized by its FACE length
;;   NotGiven the order sheet never recorded this corner -- drawn
;;            square, but flagged on the sheet rather than silently
;;            claimed as a 90
;; The pre-standard words this tool used to ask for (ROUNDED, DIAG,
;; DIAGONAL) and SPA's 90 stay accepted typed in full, unlisted, as
;; does NG for NotGiven; they are normalized to the canonical word
;; HERE so nothing downstream ever sees an old spelling.  The bracket
;; deliberately shows only the four canonical words.
;; Returns "Square", "Radius", "Cut", "NotGiven" or POOL-BACK.
(defun pool:asktreat (subject dflt back / v kws)
  ;; the bracket is DERIVED from the visible words (STANDARDS section 1
  ;; rule 1: a click sends the bracket text, so the two must not be
  ;; able to drift); the hidden aliases are appended to the initget
  ;; list only, never to the bracket
  (setq kws "Square Radius Cut NotGiven")
  (setq v (pool:askkw (strcat "How should " subject " be treated?")
                      (strcat kws " NG 90 ROUNDED DIAG DIAGONAL")
                      (vl-string-translate " " "/" kws)
                      dflt back))
  (cond ((eq v 'POOL-BACK) v)
        ((= v "NG") "NotGiven")
        ((= v "90") "Square")
        ((= v "ROUNDED") "Radius")
        ((member v '("DIAG" "DIAGONAL")) "Cut")
        (t v)))

;; Does this treatment cut real geometry off the corner?  NotGiven
;; does NOT: its corner is built square, so everything that asks
;; "is there a cut here" -- the setback caps, the cross-dim reference
;; modes, the hopper ties -- must answer no.  Only the report and the
;; corner marks care that it is not a plain Square.
;; The same question with the two SIZED answers withheld, for a corner
;; whose walls leave no room for a cut at all.  Square and NotGiven are
;; the only truthful answers there, and both take no size.
(defun pool:asktreatng (subject dflt back / v kws)
  (setq kws "Square NotGiven")
  (setq v (pool:askkw (strcat "How should " subject " be treated?")
                      (strcat kws " NG 90")
                      (vl-string-translate " " "/" kws)
                      dflt back))
  (cond ((eq v 'POOL-BACK) v)
        ((= v "NG") "NotGiven")
        ((= v "90") "Square")
        (t v)))

(defun pool:cutp (ty) (member ty '("Radius" "Cut")))

;; Does any corner carry something the SHEET must record -- a cut, or
;; a NotGiven?  The wider question pool:cutp deliberately does not
;; answer, for the report rows and the corner marks.
(defun pool:anytreat (corners / out c)
  (foreach c corners (if (/= (car c) "Square") (setq out t)))
  out)

;; Run a list of input stages with Back between them: a stage that
;; returns POOL-BACK sends the user to the previous stage, which is
;; re-asked from scratch.  Each stage is a function of no arguments
;; and must be safely re-runnable (it recomputes from its own answers).
;; Stage 1 has nowhere to go back to, so its Back is suppressed.
(defun pool:stages (fns / i n v)
  (setq i 0 n (length fns))
  (while (< i n)
    (setq v (apply (nth i fns) nil))
    (if (eq v 'POOL-BACK)
        ;; the first stage has nowhere to go back to, so it re-asks
        ;; rather than falling forward past its own question
        (if (> i 0) (setq i (1- i)))
        (setq i (1+ i))))
  (princ))

;; Run a whole block; returns the answers as an assoc list, or the
;; symbol POOL-BACK when the user backed out of its FIRST question
;; (only offered when bk is non-nil).
(defun pool:askseq (items / ans i n it v dflt asked)
  (setq ans (pool:askseqb items nil))
  ans)

(defun pool:askseqb (items bk / ans i n it v dflt asked out kind sg)
  (setq ans nil i 0 n (length items) asked nil out nil)
  (while (and (< i n) (not out))
    (setq it (nth i items))
    (if (and (nth 5 it) (eval (nth 5 it)))    ; auto-skip -> 0, unasked
        (progn
          (if (nth 6 it) (princ (nth 6 it)))
          (setq ans (pool:sqput ans (car it) 0.0)
                i (1+ i))
          ;; a skipped answer is still an answer: the live guide gets
          ;; the 0 too, so a spanned-out E collapses exactly
          (pool:pvnote (car it) 0.0))
        (progn
          (setq dflt (nth 4 it)
                kind (cadr it))
          (if (and dflt (listp dflt))
              (setq dflt (pool:sqfirst ans dflt)))
          ;; a suggestion WORKED OUT from the answers so far -- the one
          ;; member a chain has left, say -- beats one copied off
          ;; another letter, and lets a plain NA question be answered
          ;; with Enter
          (if (and (nth 7 it) (setq sg (eval (nth 7 it))))
              (setq dflt sg
                    kind (cond ((eq kind 'NAX) 'SUG)
                               ;; a suggestion on a REQUIRED question
                               ;; opens Enter, never NA
                               ((eq kind 'REQ) 'SUGR)
                               (t kind))))
          ;; the form answers first, and its answer is consumed --
          ;; see "form answers" above for why removing beats marking
          (setq v (if (pool:fhas (car it))
                      (pool:ftake (car it))
                      (pool:asks kind (caddr it) (cadddr it) dflt
                                 (if (or asked bk) t nil))))
          (if (eq v 'POOL-BACK)
              (if asked
                  (setq i (car asked) asked (cdr asked))
                  (setq out t))             ; backed out of the block
              (progn
                (setq ans (pool:sqput ans (car it) v)
                      asked (cons i asked)
                      i (1+ i))
                ;; the live guide reshapes to every accepted answer --
                ;; including a re-answer after Back, which overwrites
                (pool:pvnote (car it) v))))))
  (if out 'POOL-BACK ans))

;;; -------------------- guide preview ----------------------------------
;;; A gray pool of the chosen shape is drawn as soon as the shape is
;;; picked.  While each measurement is prompted for, the matching
;;; element of the guide turns red so the user can see exactly which
;;; dimension is being asked for -- and the guide is LIVE: every
;;; accepted answer reshapes it in place (see "live guide reshaping"
;;; below), so it starts at a familiar nominal size and turns into the
;;; actual pool as the numbers come in.  Once all inputs are in, the
;;; guide deletes itself and is replaced by the true out-of-square pool.

(setq pool:*pv-col* 8)                  ; guide outline color (dark gray)
(setq pool:*pvx-col* 7)                 ; cross-dim / measuring line color (white)
(setq pool:*hi-col* 1)                  ; highlight color (red)

;; Override (or set) the color of an entity, refresh it, return it.
(defun pool:setcol (e col / ed old)
  (if (and e (setq ed (entget e)))
      (progn
        (setq old (assoc 62 ed))
        (if old
            (setq ed (subst (cons 62 col) old ed))
            (setq ed (append ed (list (cons 62 col)))))
        (entmod ed)
        (entupd e)))
  e)

;; Read an entity's current color (defaults to the outline gray).
(defun pool:getcol (e / ed)
  (if (and e (setq ed (entget e)) (assoc 62 ed))
      (cdr (assoc 62 ed))
      pool:*pv-col*))

;; Guide entities for a list of corner-label keys, e.g. '(lA lB), so a
;; prompt can light up the letters it names as well as the line.
(defun pool:lbl (pv keys / out k)
  (foreach k keys (setq out (append out (cdr (assoc k pv)))))
  out)

;; The guide's corner-label key for a letter string ("A" -> 'lA).
(defun pool:lblkey (s) (read (strcat "l" s)))

(defun pool:pvline (p1 p2)
  (pool:line p1 p2 "POOL-NOTES")
  (pool:setcol (entlast) pool:*pv-col*))

;; Guide measuring line -- the cross dims and other ties, drawn WHITE
;; and DOTTED so they stand out from the gray pool outline.
(defun pool:pvlined (p1 p2)
  (pool:linedot p1 p2)
  (entlast))

;; Ask for a distance while the matching guide elements glow red, then
;; restore each element to the color it had (outline vs cross-dim gray).
(defun pool:askh (msg ents / v cols k)
  ;; A form answer for this letter skips the prompt and the highlight
  ;; with it -- there is nothing to look at while nothing is being
  ;; asked.  Only a real measurement is taken: every caller here range
  ;; checks what it gets and none of them can do anything with nil, so
  ;; an NA in the store falls through to the keyboard (having been
  ;; consumed, so it cannot come back round again).
  (setq k (pool:fkeyof msg))
  (if (and k (pool:fhas k) (numberp (setq v (pool:ftake k))))
      v
      (progn
        (setq cols (mapcar 'pool:getcol ents))
        (foreach e ents (pool:setcol e pool:*hi-col*))
        (setq v (pool:ask msg))
        (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
        v)))

;; Delete all guide entities (tracked globally so the *error* handler
;; can clean up after a cancel mid-prompt).  The live-reshape engine is
;; disarmed with them: a dead guide must never be morphed again.
(defun pool:pvkill ()
  (foreach e pool:*pvents*
    (if (and e (entget e)) (entdel e)))
  (setq pool:*pvents* nil
        pool:*pvgeo* nil
        pool:*pvments* nil
        pool:*pvmore* nil
        pool:*pvbox* nil))

;; Remove an item (by equality) from a list.
(defun pool:lremove (x lst / out i)
  (foreach i lst (if (not (equal i x)) (setq out (cons i out))))
  (reverse out))

;; Track a freshly made guide entity so pool:pvkill / *error* find it.
(defun pool:pvadd (e)
  (setq pool:*pvents* (cons e pool:*pvents*))
  e)

;; Delete specific guide entities mid-flow and untrack them (used when
;; part of the guide is redrawn, e.g. corner treatments).
(defun pool:pvdel (ents / e)
  (foreach e ents
    (if (and e (entget e)) (entdel e))
    (setq pool:*pvents* (pool:lremove e pool:*pvents*))))

;;; -------------------- live guide reshaping ---------------------------
;;; What makes the guide LIVE.  Each flow describes its guide as a SPEC
;;; -- an ordered list of primitives --
;;;
;;;     ("LINE" p1 p2)     gray outline segment
;;;     ("LINED" p1 p2)    white dotted measuring line
;;;     ("TEXT" pt h str)  gray label
;;;     ("ARC" p1 p2 p3)   gray three-point arc
;;;     ("ELL" cen b a)    gray axis-aligned ellipse (b across, a up)
;;;
;;; -- produced by a small geometry function the flow registers in
;;; pool:*pvgeo*.  That function reads the answers given SO FAR out of
;;; pool:*pvdims* and fills every gap with the nominal proportions, so
;;; the first paint is the familiar nominal pool and each answer after
;;; it snaps the guide closer to the real one.  pool:askseqb records
;;; every accepted answer through pool:pvnote, which re-runs the
;;; geometry and MOVES the existing entities onto it with entmod.
;;;
;;; Moving (never remaking) the entities is the point of the design:
;;; the pending ask items hold the guide entities they highlight, and
;;; those references stay valid only while the entities live.  The one
;;; exception is a three-point arc whose points go collinear (or come
;;; back apart) -- the entity type has to change, so it is remade and
;;; that single highlight reference is written off.
;;;
;;; The geometry function returns (spec keymap box): keymap maps each
;;; highlight key to the spec indices it lights up (consumed once, at
;;; build time), box is the window the guide wants on screen -- the
;;; view follows the reshape, so a pool bigger than the nominal guide
;;; never grows out of sight.

(setq pool:*pvdims* nil)                ; assoc: answer key -> value so far
(setq pool:*pvgeo* nil)                 ; the flow's geometry fn (a symbol)
(setq pool:*pvments* nil)               ; entities to morph, in spec order
(setq pool:*pvmore* nil)                ; per-flow extra morph fn (a symbol)
(setq pool:*pvbox* nil)                 ; the view box last zoomed to

;; One answered dimension, or nil while it has not been given (NA and
;; not-yet-asked read the same: the nominal proportion fills in).
(defun pool:pvdim (key) (cdr (assoc key pool:*pvdims*)))

;; Axis-aligned guide ellipse.  Always an ELLIPSE, even with equal
;; axes, so the entity type never changes as the two overalls come in.
(defun pool:pvell (cen b a / mj rt)
  (if (>= b a)
      (setq mj (list (* 0.5 b) 0.0 0.0) rt (/ a b))
      (setq mj (list 0.0 (* 0.5 a) 0.0) rt (/ b a)))
  (entmake (list '(0 . "ELLIPSE")
                 '(100 . "AcDbEntity")
                 (cons 8 "POOL-NOTES")
                 '(100 . "AcDbEllipse")
                 (cons 10 (pool:wp cen))
                 (cons 11 mj)                  ; major semi-axis, relative
                 (cons 210 '(0.0 0.0 1.0))
                 (cons 40 rt)                  ; minor / major
                 (cons 41 0.0)
                 (cons 42 (* 2.0 pi)))))

;; Make one primitive's entity, tracked for pool:pvkill.  LINE / TEXT /
;; ARC draw gray on POOL-NOTES exactly as the fixed guides always did;
;; LINED is the white dotted measuring line.
(defun pool:pvmk (pr / ty)
  (setq ty (car pr))
  (cond
    ((= ty "LINE") (pool:pvadd (pool:pvline (cadr pr) (caddr pr))))
    ((= ty "LINED") (pool:pvadd (pool:pvlined (cadr pr) (caddr pr))))
    ((= ty "TEXT")
     (pool:text (cadr pr) (caddr pr) (cadddr pr) "POOL-NOTES")
     (pool:pvadd (pool:setcol (entlast) pool:*pv-col*)))
    ((= ty "ARC")
     (pool:arc3p (cadr pr) (caddr pr) (cadddr pr) "POOL-NOTES")
     (pool:pvadd (pool:setcol (entlast) pool:*pv-col*)))
    ((= ty "ELL")
     (pool:pvell (cadr pr) (caddr pr) (cadddr pr))
     (pool:pvadd (pool:setcol (entlast) pool:*pv-col*)))))

;; The two primitives of one field-sheet tie -- the dotted measuring
;; line and its letter beside the midpoint.
(defun pool:pvtiespec (p q lbl th)
  (list (list "LINED" p q)
        (list "TEXT" (pool:v+ (pool:mid p q) (list (* 0.5 th) (* 0.5 th)))
              (* 1.2 th) lbl)))

;; The window a spec wants on screen: its extents plus a margin.
(defun pool:pvspecbox (spec / pts pr hx hy px py qx qy m)
  (setq pts nil)
  (foreach pr spec
    (cond
      ((member (car pr) '("LINE" "LINED"))
       (setq pts (cons (cadr pr) (cons (caddr pr) pts))))
      ((= (car pr) "TEXT")
       (setq pts (cons (cadr pr) pts)))
      ((= (car pr) "ARC")
       (setq pts (cons (cadr pr) (cons (caddr pr) (cons (cadddr pr) pts)))))
      ((= (car pr) "ELL")
       (setq hx (* 0.5 (caddr pr)) hy (* 0.5 (cadddr pr))
             pts (cons (pool:v+ (cadr pr) (list hx hy))
                       (cons (pool:v- (cadr pr) (list hx hy)) pts))))))
  (setq px (apply 'min (mapcar 'car pts))
        qx (apply 'max (mapcar 'car pts))
        py (apply 'min (mapcar 'cadr pts))
        qy (apply 'max (mapcar 'cadr pts))
        m (max 30.0 (* 0.10 (max (- qx px) (- qy py)))))
  (list (list (- px m) (- py m)) (list (+ qx m) (+ qy m))))

;; Follow the reshaped guide with the view -- but only when the box
;; really moved, so answers that barely change the shape do not churn
;; the screen.
(defun pool:pvzoom (box / o)
  (setq o pool:*pvbox*)
  (if (and box
           (or (null o)
               (> (+ (distance (car box) (car o))
                     (distance (cadr box) (cadr o)))
                  (* 0.05 (distance (car box) (cadr box))))))
      (progn
        (setq pool:*pvbox* box)
        (command "_.ZOOM" "_Window"
                 (pool:wp (car box)) (pool:wp (cadr box))))))

;; Move one guide entity onto its recomputed primitive.  An entity that
;; no longer exists (the corner redraw retires the plain sides) is left
;; dead; a three-point arc whose kind changed is remade.  Returns the
;; entity holding the primitive now.
(defun pool:pvmod (e pr / ed ty o r a1 a2 a3 da2 da3 s en mj rt)
  (setq ed (if e (entget e)))
  (cond
    ((null ed) e)
    ((member (car pr) '("LINE" "LINED"))
     (entmod (subst (cons 11 (pool:wp (caddr pr))) (assoc 11 ed)
                    (subst (cons 10 (pool:wp (cadr pr))) (assoc 10 ed) ed)))
     (entupd e)
     e)
    ((= (car pr) "TEXT")
     (entmod (subst (cons 1 (cadddr pr)) (assoc 1 ed)
                    (subst (cons 40 (caddr pr)) (assoc 40 ed)
                           (subst (cons 10 (pool:wp (cadr pr)))
                                  (assoc 10 ed) ed))))
     (entupd e)
     e)
    ((= (car pr) "ARC")
     (setq o (pool:circum (cadr pr) (caddr pr) (cadddr pr))
           ty (cdr (assoc 0 ed)))
     (if (and o (= ty "ARC"))
         (progn
           (setq r (distance o (cadr pr))
                 a1 (angle o (cadr pr))
                 a2 (angle o (caddr pr))
                 a3 (angle o (cadddr pr))
                 da2 (pool:npos (- a2 a1))
                 da3 (pool:npos (- a3 a1)))
           (if (< da2 da3)
               (setq s a1 en a3)
               (setq s a3 en a1))
           (entmod (subst (cons 51 en) (assoc 51 ed)
                          (subst (cons 50 s) (assoc 50 ed)
                                 (subst (cons 40 r) (assoc 40 ed)
                                        (subst (cons 10 (pool:wp o))
                                               (assoc 10 ed) ed)))))
           (entupd e)
           e)
         ;; the kind changed (arc went collinear, or a line-fallback
         ;; arc came back apart) -- remade, references written off
         (progn (pool:pvdel (list e)) (pool:pvmk pr))))
    ((= (car pr) "ELL")
     (if (>= (caddr pr) (cadddr pr))
         (setq mj (list (* 0.5 (caddr pr)) 0.0 0.0)
               rt (/ (cadddr pr) (caddr pr)))
         (setq mj (list 0.0 (* 0.5 (cadddr pr)) 0.0)
               rt (/ (caddr pr) (cadddr pr))))
     (entmod (subst (cons 40 rt) (assoc 40 ed)
                    (subst (cons 11 mj) (assoc 11 ed)
                           (subst (cons 10 (pool:wp (cadr pr)))
                                  (assoc 10 ed) ed))))
     (entupd e)
     e)
    (t e)))

;; Reshape the live guide from the answers recorded so far: re-run the
;; flow's geometry, move every entity onto it, follow with the view,
;; then let the flow move what the generic pass cannot see (the corner
;; treatments and cross-dim lines it added after the build).
(defun pool:pvreshape ( / g)
  (if (and pool:*pvgeo* pool:*pvments*)
      (progn
        (setq g (apply pool:*pvgeo* nil))
        (setq pool:*pvments* (mapcar 'pool:pvmod pool:*pvments* (car g)))
        (pool:pvzoom (caddr g))
        (if pool:*pvmore* (apply pool:*pvmore* nil)))))

;; Record one accepted answer and reshape the guide to it.  Harmless
;; once the guide is gone -- pool:pvkill disarms the engine, so the
;; interior (hopper) questions record into the void.
(defun pool:pvnote (key v)
  (setq pool:*pvdims* (pool:sqput pool:*pvdims* key v))
  (pool:pvreshape))

;; Build a live guide from the flow's geometry function: draw the spec,
;; register the function for reshaping, zoom to it, and hand back the
;; highlight assoc the ask items index by key.
(defun pool:pvlive (geofn / g ents)
  (setq pool:*pvdims* nil
        pool:*pvmore* nil
        pool:*pvbox* nil
        pool:*pvgeo* geofn
        g (apply geofn nil)
        ents (mapcar 'pool:pvmk (car g))
        pool:*pvments* ents)
  (pool:pvzoom (caddr g))
  (mapcar '(lambda (km)
             (cons (car km)
                   (mapcar '(lambda (i) (nth i ents)) (cdr km))))
          (cadr g)))

;;; The BOTTOM-phase guides (the floor dims: the H/G/F/E/M/L/K hopper
;;; chains and the section depths) ride the same engine through a
;;; COLLECTOR.  The hopper draw routines (pool:hgl / pool:hga /
;;; pool:profdraw) have always had a pvflag preview path; arming the
;;; collector makes that same path EMIT primitives instead of drawing,
;;; so the existing compute-and-draw code doubles as the geometry
;;; function and the hopper reshapes with every letter answered.

(setq pool:*pvcoll* nil)                ; T while a spec is being collected
(setq pool:*pvcsp* nil)                 ; collected primitives, reversed
(setq pool:*pvckm* nil)                 ; collected keymap entries

;; Arm the collector (a bottom geometry function's first act).
(defun pool:pvcopen ()
  (setq pool:*pvcoll* t
        pool:*pvcsp* nil
        pool:*pvckm* nil))

;; One primitive into the collector.
(defun pool:pvcput (pr)
  (setq pool:*pvcsp* (cons pr pool:*pvcsp*))
  nil)

;; One keyed field-sheet tie into the collector -- the live counterpart
;; of the old pool:pvtie: the dotted line and its letter, highlighted
;; together while that letter is prompted.
(defun pool:pvctie (p q lbl th / n pr)
  (setq n (length pool:*pvcsp*))
  (foreach pr (pool:pvtiespec p q lbl th) (pool:pvcput pr))
  (setq pool:*pvckm* (cons (list lbl n (1+ n)) pool:*pvckm*))
  nil)

;; Close the collector into the (spec keymap box) a geometry function
;; returns.  pts joins the view box without being drawn, so the pool
;; the bottom guide sits inside stays on screen however the guide
;; moves.
(defun pool:pvcout (pts / spec km box p px py qx qy)
  (setq spec (reverse pool:*pvcsp*)
        km (reverse pool:*pvckm*)
        box (pool:pvspecbox spec)
        pool:*pvcoll* nil
        px (car (car box)) py (cadr (car box))
        qx (car (cadr box)) qy (cadr (cadr box)))
  (foreach p pts
    (setq px (min px (- (car p) 20.0)) py (min py (- (cadr p) 20.0))
          qx (max qx (+ (car p) 20.0)) qy (max qy (+ (cadr p) 20.0))))
  (list spec km (list (list px py) (list qx qy))))

;; Live fill-in for a measurement chain: answered members are held,
;; open ones share whatever the total has left in proportion to their
;; nominals -- so the chain closes against the pool at every step, and
;; once all but one member is in, the last shows exactly the remainder
;; the resolver will hand it.  An overspent chain squeezes the open
;; members toward zero instead of going negative.
(defun pool:pvchain (vals noms total / sum nsum s out k v)
  (setq sum 0.0 nsum 0.0 k 0)
  (foreach v vals
    (if v (setq sum (+ sum v)) (setq nsum (+ nsum (nth k noms))))
    (setq k (1+ k)))
  (setq s (if (> nsum 1.0e-6) (max 0.05 (/ (- total sum) nsum)) 0.0)
        out nil k 0)
  (foreach v vals
    (setq out (cons (if v v (* s (nth k noms))) out)
          k (1+ k)))
  (reverse out))

;; Mirror everything drawn after `after` about the HORIZONTAL line
;; y = y0 -- a top-to-bottom flip.
;;
;; L and Lazy L pools flip this way rather than left-to-right, because
;; the deep end is always the end AWAY from the wing: flipping
;; left-to-right would swing the wing across and carry the hopper over
;; to the right-hand side of the sheet with it.  Flipping top-to-bottom
;; swaps which way the wing points instead and leaves the deep end --
;; and so the hopper -- on the left, where the convention wants it.
;;
;; The side profile is held out of it (pool:*profents*): that is a
;; LONGITUDINAL section, and turning the plan upside down does not
;; change it.  Text is mirrored with MIRRTEXT off so it stays readable.
(defun pool:mirrory (after y0 / ss e mt)
  (setq ss (ssadd)
        e (if after (entnext after) (entnext)))
  (while e
    (if (not (member e pool:*profents*)) (ssadd e ss))
    (setq e (entnext e)))
  (if (> (sslength ss) 0)
      (progn
        (setq mt (getvar "MIRRTEXT"))
        (setvar "MIRRTEXT" 0)
        (command "_.MIRROR" ss "" (list 0.0 y0 0.0) (list 1.0 y0 0.0) "_Y")
        (setvar "MIRRTEXT" mt)))
  (princ))

;; The rectangle / oval guide is built by qf:geo inside pool:quadflow
;; -- a live-guide geometry function fed to pool:pvlive, so the box
;; reshapes as its sides come in.  Every other flow has its own such
;; function (gr:geo, hx:geo, rd:geo, rm:geo, mu:geo).

;;; -------------------- quadrilateral fitting --------------------------

;; Measured lengths of quad (A B C D):
;; (bottom top left right crossAC crossBD)
(defun pool:quadmeas (q / a b c d)
  (setq a (car q) b (cadr q) c (caddr q) d (cadddr q))
  (list (distance a b) (distance d c) (distance a d) (distance b c)
        (distance a c) (distance b d)))

;; Cross-dim error of a quad; a nil target (NA) contributes nothing.
(defun pool:diagerr (q dac dbd / e1 e2)
  (setq e1 (if dac (- (distance (car q) (caddr q)) dac) 0.0)
        e2 (if dbd (- (distance (cadr q) (cadddr q)) dbd) 0.0))
  (+ (* e1 e1) (* e2 e2)))

;; Quad with all four sides EXACT, parameterised by the interior angle
;; at corner A (four-bar linkage).  Returns (A B C D) or nil.
(defun pool:4bar (bo tp le ri alfa / a b d c1 c2)
  (setq a (list 0.0 0.0)
        b (list bo 0.0)
        d (list (* le (cos alfa)) (* le (sin alfa)))
        c1 (pool:circint b ri d tp 1.0)
        c2 (pool:circint b ri d tp -1.0))
  (cond
    ((and c1 c2)
     (list a b (if (> (distance a c1) (distance a c2)) c1 c2) d))
    (c1 (list a b c1 d))
    (c2 (list a b c2 d))
    (t nil)))

;; Scan the angle at A over [a0 a1], returning (quad alfa) with the
;; smallest cross-dim error, or nil.
(defun pool:scanalfa (bo tp le ri dac dbd a0 a1 step / alfa q e best bestq)
  (setq alfa a0 best 1.0e30 bestq nil)
  (while (<= alfa a1)
    (setq q (pool:4bar bo tp le ri alfa))
    (if q
        (progn
          (setq e (pool:diagerr q dac dbd))
          (if (< e best) (setq best e bestq (list q alfa)))))
    (setq alfa (+ alfa step)))
  bestq)

;; Best quad with sides held EXACTLY true, cross dims as close as
;; possible.  Coarse scan then fine refine.  Returns quad or nil.
;; With both cross dims NA there is nothing to skew for: square up.
(defun pool:fitsides (bo tp le ri dac dbd / r1 r2 alfa)
  (if (and (null dac) (null dbd))
      (pool:4bar bo tp le ri (pool:d2r 90.0))
      (progn
        (setq r1 (pool:scanalfa bo tp le ri dac dbd
                                (pool:d2r 15.0) (pool:d2r 165.0) (pool:d2r 0.25)))
        (if r1
            (progn
              (setq alfa (cadr r1)
                    r2 (pool:scanalfa bo tp le ri dac dbd
                                      (- alfa (pool:d2r 0.3)) (+ alfa (pool:d2r 0.3))
                                      (pool:d2r 0.005)))
              (car (if r2 r2 r1)))))))

(defun pool:setnth (lst i val / k out)
  (setq k 0 out nil)
  (foreach x lst
    (setq out (cons (if (= k i) val x) out)
          k (1+ k)))
  (reverse out))

;; One distance-constraint relaxation step: pull points i and j of pts
;; so their distance moves into [lo hi] (lo = hi -> exact pull).
(defun pool:relax1 (pts i j lo hi w / p q d des err ux uy e2)
  (setq p (nth i pts)
        q (nth j pts)
        d (distance p q))
  (if (> d 1.0e-9)
      (progn
        (setq des (min (max d lo) hi)
              err (- d des))
        (if (/= err 0.0)
            (progn
              (setq ux (/ (- (car q) (car p)) d)
                    uy (/ (- (cadr q) (cadr p)) d)
                    e2 (* 0.5 w err))
              (setq pts (pool:setnth pts i
                          (list (+ (car p) (* e2 ux)) (+ (cadr p) (* e2 uy)))))
              (setq pts (pool:setnth pts j
                          (list (- (car q) (* e2 ux)) (- (cadr q) (* e2 uy)))))))))
  pts)

(defun pool:rot (p ang)
  (list (- (* (car p) (cos ang)) (* (cadr p) (sin ang)))
        (+ (* (car p) (sin ang)) (* (cadr p) (cos ang)))))

;; Re-gauge a polygon: first point at the origin, second on the +X
;; axis, bulk of the shape above the axis.  Works for any point count.
(defun pool:normpoly (pts / a ang my)
  (setq a (car pts)
        pts (mapcar '(lambda (p) (pool:v- p a)) pts)
        ang (- (angle (list 0.0 0.0) (cadr pts)))
        pts (mapcar '(lambda (p) (pool:rot p ang)) pts)
        my 0.0)
  (foreach a pts (setq my (+ my (cadr a))))
  (if (< my 0.0)
      (setq pts (mapcar '(lambda (p) (list (car p) (- (cadr p)))) pts)))
  pts)

;; Iterative relaxation of an arbitrary point list against distance
;; constraints (i j lo hi weight); lo = hi -> exact pull.
(defun pool:relaxn (pts conlst niter / k c)
  (setq k 0)
  (while (< k niter)
    (foreach c conlst
      (setq pts (pool:relax1 pts (car c) (cadr c) (caddr c) (cadddr c) (nth 4 c))))
    (setq k (1+ k)))
  (pool:normpoly pts))

;; Quad relaxation: sides banded to +/-stol, provided cross dims
;; pulled to their exact targets.  Cross dims pull first, side bands
;; clamp last so each sweep ends with the sides inside their band.
(defun pool:relaxquad (pts bo tp le ri dac dbd stol niter / conlst)
  (setq conlst nil)
  (if dbd (setq conlst (cons (list 1 3 dbd dbd 0.5) conlst)))
  (if dac (setq conlst (cons (list 0 2 dac dac 0.5) conlst)))
  (setq conlst (append conlst
                       (list (list 0 1 (- bo stol) (+ bo stol) 1.0)
                             (list 3 2 (- tp stol) (+ tp stol) 1.0)
                             (list 0 3 (- le stol) (+ le stol) 1.0)
                             (list 1 2 (- ri stol) (+ ri stol) 1.0))))
  (pool:relaxn pts conlst niter))

;; Fit the parametric quad.  Returns (quad failedflag):
;;  1. hold sides exact, pick the angle whose cross dims are closest;
;;     if both cross dims land inside xtol -> done, no failure.
;;  2. otherwise let the sides flex inside +/-stol and pull the cross
;;     dims to their targets; if everything then fits -> done.
;;  3. otherwise: sides held true (result of step 1), cross dims as
;;     close as possible, failure flag set.
(defun pool:fitquad (bo tp le ri dac dbd stol xtol / q1 m1 q2 m2 sok xok)
  (setq q1 (pool:fitsides bo tp le ri dac dbd))
  (if (null q1)                         ; degenerate input fallback
      (setq q1 (list (list 0.0 0.0) (list bo 0.0)
                     (list bo (* 0.5 (+ le ri))) (list 0.0 le))))
  (setq m1 (pool:quadmeas q1))
  (if (and (or (null dac) (<= (abs (- (nth 4 m1) dac)) xtol))
           (or (null dbd) (<= (abs (- (nth 5 m1) dbd)) xtol)))
      (list q1 nil)
      (progn
        (setq q2 (pool:relaxquad q1 bo tp le ri dac dbd stol 2000)
              m2 (pool:quadmeas q2)
              sok (and (<= (abs (- (car m2) bo)) (+ stol 0.05))
                       (<= (abs (- (cadr m2) tp)) (+ stol 0.05))
                       (<= (abs (- (caddr m2) le)) (+ stol 0.05))
                       (<= (abs (- (cadddr m2) ri)) (+ stol 0.05)))
              xok (and (or (null dac) (<= (abs (- (nth 4 m2) dac)) (+ xtol 0.05)))
                       (or (null dbd) (<= (abs (- (nth 5 m2) dbd)) (+ xtol 0.05)))))
        (if (and sok xok)
            (list q2 nil)
            (list q1 t)))))

;; Exact two-triangle check (report only, nothing is drawn from it):
;;   triangle 1 = A B C  (bottom side, right end, cross A-C)
;;   triangle 2 = A C D  (top side, left end, shared cross A-C)
;; All lengths held exactly.  Returns (A B C D) or nil when the given
;; lengths cannot form the triangles.
(defun pool:triquad (bo tp le ri dac / a b c d)
  (setq a (list 0.0 0.0)
        b (list bo 0.0)
        c (pool:circint a dac b ri 1.0))
  (if c (setq d (pool:circint a le c tp 1.0)))
  (if (and c d) (list a b c d)))

;;; -------------------- grecian ends -----------------------------------

;; Distance between the two diagonal end points for end width w,
;; diagonal lengths lt/lb and diagonal angle th (from the end line's
;; outward normal).
(defun pool:grecf (w lt lb th)
  (sqrt (+ (expt (- w (* (+ lt lb) (sin th))) 2)
           (expt (* (- lt lb) (cos th)) 2))))

;; Best diagonal angle for target end width e: scan 1..89 degrees.
;; Returns (theta err).
(defun pool:grecth (w lt lb e / th best berr dd)
  (setq th 0.0175 best 0.7854 berr 1.0e30)
  (while (< th 1.5533)
    (setq dd (abs (- (pool:grecf w lt lb th) e)))
    (if (< dd berr) (setq berr dd best th))
    (setq th (+ th 0.00087)))           ; ~ 0.05 degree steps
  (list best berr))

;; Try to fit the end width by adjusting the angle; when that is not
;; enough, adjust the diagonal lengths in 1/8" increments (smallest
;; total adjustment first) up to +/-1/2".
;; Returns (ltUsed lbUsed theta) or nil.
(defun pool:grecfit (w lt lb e / s i j lt2 lb2 r out n)
  (setq n pool:*grec-max* s 0 out nil)
  (while (and (null out) (<= s (* 2 n)))
    (setq i (- n))
    (while (and (null out) (<= i n))
      (setq j (- n))
      (while (and (null out) (<= j n))
        (if (= (+ (abs i) (abs j)) s)
            (progn
              (setq lt2 (+ lt (* pool:*grec-step* i))
                    lb2 (+ lb (* pool:*grec-step* j)))
              (if (and (> lt2 0.0) (> lb2 0.0))
                  (progn
                    (setq r (pool:grecth w lt2 lb2 e))
                    (if (<= (cadr r) 0.0625)   ; within 1/16"
                        (setq out (list lt2 lb2 (car r))))))))
        (setq j (1+ j)))
      (setq i (1+ i)))
    (setq s (1+ s)))
  out)

;; Compute one Grecian end (no drawing).  pbot/ptop = end line
;; corners, mdir = unit normal pointing away from the pool body.
;; Returns (p1 p2 ltUsed lbUsed theta okflag); p1 joins ptop, p2 joins
;; pbot.  When the fit fails the end falls back to 45 degrees with the
;; given lengths, okflag nil.
(defun pool:grecendp (pbot ptop mdir lt lb e / u fit lt2 lb2 th ok dtop dbot)
  (setq u (pool:unit (pool:v- ptop pbot))
        fit (pool:grecfit (distance pbot ptop) lt lb e))
  (if fit
      (setq lt2 (car fit) lb2 (cadr fit) th (caddr fit) ok t)
      (setq lt2 lt lb2 lb th (pool:d2r 45.0) ok nil))
  (setq dtop (pool:v- (pool:v* mdir (cos th)) (pool:v* u (sin th)))
        dbot (pool:v+ (pool:v* mdir (cos th)) (pool:v* u (sin th))))
  (list (pool:v+ ptop (pool:v* dtop lt2))
        (pool:v+ pbot (pool:v* dbot lb2))
        lt2 lb2 th ok))

;;; -------------------- grecian cross-dim modes -------------------------
;;;
;;;  A Grecian pool has 8 corners; from the bottom-left, clockwise:
;;;
;;;         D ------------------ C          body:  A B C D
;;;        /                      \         left tips:  LT (off D), LB (off A)
;;;      LT                        RT       right tips: RT (off C), RB (off B)
;;;        \                      /
;;;         LB                  RB          index order used below:
;;;           \                /             0=A 1=B 2=RB 3=RT 4=C 5=D 6=LT 7=LB
;;;            A ------------ B
;;;
;;;  Cross-dim modes (how many diagonals the user is asked for):
;;;    Simple  = A-C, B-D                       (2, the body diagonals)
;;;    Center  = Simple + LB-RT, LT-RB          (4, adds the long tip X)
;;;    Complex = every possible diagonal        (18, all pairs; NA any)
;;;  More provided cross dims -> the out-of-square shape is pinned down
;;;  more tightly.  Any cross dim may be answered NA.

(setq pool:*grecnames*
      (list "A" "B" "RB" "RT" "C" "D" "LT" "LB"))

;; perimeter edges + the two body-end chords as (i j prompt-key band):
;; body sides loose (1"), end diagonals held near the given 1/2", end
;; widths near-exact.  The prompt-key ties each edge to its guide
;; highlight and prompt.
(setq pool:*grecedges*
      (list '(0 1 ab  1.0)     ; A-B  bottom side
            '(1 2 rbd 0.5)     ; B-RB right diag bottom
            '(2 3 rew 0.1)     ; RB-RT right end width
            '(3 4 rtd 0.5)     ; RT-C right diag top
            '(4 5 cd  1.0)     ; C-D  top side
            '(5 6 ltd 0.5)     ; D-LT left diag top
            '(6 7 lew 0.1)     ; LT-LB left end width
            '(7 0 lbd 0.5)     ; LB-A left diag bottom
            '(0 5 ad  1.0)     ; A-D  left end (internal chord)
            '(1 4 bc  1.0)))   ; B-C  right end (internal chord)

;; The 8 corners in the two families a treatment is answered by: the
;; BODY corners, where a long wall runs into a cut face, and the END
;; TIPS, where that cut face lands on the end wall.  With them, the
;; walls a tip treatment has to share -- the four cut faces (one body
;; corner and one tip on each) and the two end walls (two tips each).
(setq pool:*grecbody* '(0 1 4 5))               ; A B C D
(setq pool:*grectips* '(2 3 6 7))               ; RB RT LT LB
(setq pool:*greccuts* '((1 2) (3 4) (5 6) (7 0)))
(setq pool:*grecwalls* '((2 3) (6 7)))          ; RB-RT and LT-LB

(setq pool:*grec-simple*
      (list '(0 4 "A-C") '(1 5 "B-D")))
(setq pool:*grec-center*
      (list '(0 4 "A-C") '(1 5 "B-D") '(7 3 "LB-RT") '(6 2 "LT-RB")
            ;; tip to tip along the top and along the bottom -- the two
            ;; tapes a crew can run straight down the pool's own edges
            '(6 3 "LT-RT") '(7 2 "LB-RB")
            ;; the X over each end cut (tip to the near body corner)...
            '(5 7 "D-LB") '(0 6 "A-LT")
            '(2 4 "RB-C") '(1 3 "B-RT")
            ;; ...and each tip to the far bottom/top body corner
            '(1 6 "B-LT") '(4 7 "C-LB")
            '(0 3 "A-RT") '(2 5 "RB-D")))
(setq pool:*grec-complex*
      (list '(0 2 "A-RB") '(0 3 "A-RT") '(0 4 "A-C")  '(0 6 "A-LT")
            '(1 3 "B-RT") '(1 5 "B-D")  '(1 6 "B-LT") '(1 7 "B-LB")
            '(2 4 "RB-C") '(2 5 "RB-D") '(2 6 "RB-LT") '(2 7 "RB-LB")
            '(3 5 "RT-D") '(3 6 "RT-LT") '(3 7 "RT-LB")
            '(4 6 "C-LT") '(4 7 "C-LB")
            '(5 7 "D-LB")))

(defun pool:grecmode (m)
  (cond ((= m "Center")  pool:*grec-center*)
        ((= m "Complex") pool:*grec-complex*)
        (t               pool:*grec-simple*)))

;; Worst cross-dim miss over the provided (non-nil) targets.
(defun pool:crossmax (pts crosscons / mx d)
  (setq mx 0.0)
  (foreach c crosscons
    (if (caddr c)
        (setq d (abs (- (distance (nth (car c) pts) (nth (cadr c) pts)) (caddr c)))
              mx (max mx d))))
  mx)

;; Worst amount any edge sits OUTSIDE its band (<=0 means all in band).
(defun pool:edgemax (pts edgecons / mx d)
  (setq mx -1.0e30)
  (foreach e edgecons
    (setq d (- (abs (- (distance (nth (car e) pts) (nth (cadr e) pts)) (caddr e)))
               (cadddr e))
          mx (max mx d)))
  mx)

;; Generic two-phase best fit of a point list:
;;   edgecons  = (i j target band)   crosscons = (i j target)
;;   1. pull crosses while holding edges EXACT; if crosses land inside
;;      xtol -> done, no failure.
;;   2. let edges flex within their bands and pull crosses; if edges
;;      stay in band and crosses land inside xtol -> done.
;;   3. otherwise edges held true (step-1 result), crosses as close as
;;      possible, failure flag set.
;; Returns (pts failed).
(defun pool:fitpoly (seed edgecons crosscons xtol / xcon e0 eb p1 p2)
  (setq xcon nil)
  (foreach c crosscons                  ; provided (non-NA) crosses only
    (if (caddr c)
        (setq xcon (cons (list (car c) (cadr c) (caddr c) (caddr c) 0.5) xcon))))
  (setq e0 (mapcar '(lambda (e) (list (car e) (cadr e) (caddr e) (caddr e) 1.0))
                   edgecons)
        eb (mapcar '(lambda (e) (list (car e) (cadr e)
                                      (- (caddr e) (cadddr e))
                                      (+ (caddr e) (cadddr e)) 1.0))
                   edgecons))
  (setq p1 (pool:relaxn seed (append xcon e0) 3000)
        p1 (pool:relaxn p1 e0 400))
  (if (<= (pool:crossmax p1 crosscons) xtol)
      (list p1 nil)
      (progn
        (setq p2 (pool:relaxn p1 (append xcon eb) 3000))
        (if (and (<= (pool:edgemax p2 edgecons) 0.05)
                 (<= (pool:crossmax p2 crosscons) (+ xtol 0.05)))
            (list p2 nil)
            (list p1 t)))))

;; The tip-to-tip widths LT-RT and LB-RB, in either corner order.
(defun pool:tippair (i j)
  (or (and (= i 6) (= j 3)) (and (= i 3) (= j 6))
      (and (= i 7) (= j 2)) (and (= i 2) (= j 7))))

;; Look up a provided cross target for corner pair (i j); nil if NA or
;; not in the active set.
(defun pool:crossget (crosscons i j / out)
  (foreach c crosscons
    (if (or (and (= (car c) i) (= (cadr c) j))
            (and (= (car c) j) (= (cadr c) i)))
        (setq out (caddr c))))
  out)

(defun pool:grecnm (i j)
  (strcat (nth i pool:*grecnames*) "-" (nth j pool:*grecnames*)))

;; Gray guide for a Grecian: 8-corner nominal body (solid perimeter,
;; dashed internal end chords), corner labels clear of the linework,
;; and the active mode's cross diagonals (dashed).  Returns the
;; highlight assoc (edge prompt-keys + one entry per cross name).
(setq pool:*grecnpts* (list (list 0.0 0.0) (list 360.0 0.0) (list 410.0 55.0)
                            (list 410.0 125.0) (list 360.0 180.0)
                            (list 0.0 180.0) (list -50.0 125.0)
                            (list -50.0 55.0)))

;; An OCTAGON is the same eight-corner shape with the same edge list --
;; only the proportions differ: its cuts run at 45 degrees (S = S1) and
;; its short flats match the cut faces, where a grecian's ends are long
;; and shallow.
;;
;; The guide is a REGULAR octagon -- 300 square, cut c = 300/(2+root 2)
;; = 87.87, so all eight sides come out 124.26 -- because that is what
;; the shape being measured looks like.  (An elongated guide made the
;; sheet read like a grecian's.)
(setq pool:*octnpts* (list (list 87.87 0.0) (list 212.13 0.0)
                           (list 300.0 87.87) (list 300.0 212.13)
                           (list 212.13 300.0) (list 87.87 300.0)
                           (list 0.0 212.13) (list 0.0 87.87)))

;; The Grecian / Octagon guide is built by gr:geo inside pool:grecflow
;; (a live-guide geometry function fed to pool:pvlive), so the ring
;; reshapes as the overalls and letters -- or the measured edges --
;; come in.  gr:geo keeps the flow's npts on the live ring, which is
;; what pool:greccross later draws the diagonals against.

;; Add the chosen mode's cross diagonals to the Grecian guide once the
;; perimeter is measured.  Returns the extended highlight assoc.
(defun pool:greccross (crosses pv npts / c ent)
  (foreach c crosses
    (setq ent (pool:pvadd (pool:pvlined (nth (car c) npts) (nth (cadr c) npts)))
          pv (cons (cons (caddr c) (list ent)) pv)))
  pv)

;; Round to the nearest quarter inch -- the granularity a tape is read
;; to in the field, and the one a DERIVED letter is worth quoting at.
(defun pool:q4 (v) (* 0.25 (fix (+ (* 4.0 v) 0.5))))

;; The grecian corner cut, filled in from its FACE.  A crew tapes
;; ACROSS the cut (S2) far more readily than it locates the virtual
;; sharp corner the legs S / S1 run out to -- the face is a wall, the
;; legs are not -- so a taped face fills in whichever leg the sheet
;; left blank:
;;   both legs blank -- the cut is the 45 it is drawn as, so
;;                      S = S1 = S2 / sqrt 2  (a 6'-0 face gives
;;                      4'-3 legs)
;;   one leg pinned  -- the other closes the right triangle, i.e.
;;                      sqrt(S2^2 - leg^2)
;; A derived leg comes back to the nearest 1/4", so the number the
;; report quotes is one a crew can actually pull.  A face too short to
;; hold the pinned leg is ignored rather than square-rooted into
;; nothing: the caller's nominal split takes over and the S2 report row
;; shows how far out the sheet was.
;; Returns (S . S1), either member still nil when nothing filled it.
(defun pool:greccut (s2raw s s1 / c)
  (cond
    ((null s2raw) (cons s s1))
    ((and (null s) (null s1))
     (setq c (pool:q4 (/ s2raw 1.41421356237)))
     (cons c c))
    ((and (null s) (< s1 s2raw))
     (cons (pool:q4 (sqrt (- (* s2raw s2raw) (* s1 s1)))) s1))
    ((and (null s1) (< s s2raw))
     (cons s (pool:q4 (sqrt (- (* s2raw s2raw) (* s s))))))
    (t (cons s s1))))

;; Full guided flow for a Grecian pool (all three cross-dim modes).
;; Caller handles sysvars / undo / zoom-extents.
;; Resolve the overall-sheet letters against the overalls: S/T close
;; against B (T absorbs any difference), S1/V against A (V absorbs).
;; An NA letter is derived -- from the taped cut face S2 where there
;; is one, and only with no face either from a nominal split.
;; Returns (S T S1 V).
;; WALLS BEAT CORNERS.  T and V run along a wall, so a tape can be
;; held flat against them and they come back reliable.  S and S1 only
;; locate the VIRTUAL sharp corner out past the cut -- on a real pool
;; there is nothing there to measure to, so they are the softer
;; numbers.  When both are given, the wall wins and its partner is
;; re-derived from the overall (S = (B - T)/2, S1 = (A - V)/2); the
;; taped S / S1 still show in the report against what was drawn.
;; Only when the wall was NOT measured does S / S1 drive the shape.
;; S2 is softer still than a wall but harder than nothing, so it sits
;; between the two: it fills a leg in, it never overrides one.
(defun pool:grecov (aov bov sraw traw s1raw vraw s2raw / s tv s1 v cut)
  ;; what the sheet pins outright, the wall ahead of its corner
  (cond
    (traw (setq s (/ (- bov traw) 2.0) tv traw))
    (sraw (setq s sraw tv (- bov (* 2.0 sraw)))))
  (cond
    (vraw (setq s1 (/ (- aov vraw) 2.0) v vraw))
    (s1raw (setq s1 s1raw v (- aov (* 2.0 s1raw)))))
  ;; then the cut face, for whichever leg nothing pinned
  (setq cut (pool:greccut s2raw s s1)
        s (car cut) s1 (cdr cut))
  ;; and the long-pool nominal split for whatever is still open
  (if (null s) (setq s (/ bov 8.0)))
  (if (null s1) (setq s1 (/ aov 6.0)))
  (if (null tv) (setq tv (- bov (* 2.0 s))))
  (if (null v) (setq v (- aov (* 2.0 s1))))
  (list s tv s1 v))

;; Octagon overall sheet.  With the letters unmeasured the shape is
;; derived from A and B alone, per the sheet: the four corners are cut
;; at 45 degrees (so S = S1 = c) and the SHORT flats equal the cut
;; faces, i.e. every side of a square octagon is the same length.
;;   c = min(A,B) / (2 + sqrt 2)   ->   T = B - 2c,  V = A - 2c
;; A measured letter wins over the derivation, and -- exactly like the
;; grecian sheet -- the WALL letters (T, V) win over the corner ones
;; (S, S1) when both were taped.  Returns (S T S1 V).
(defun pool:octov (aov bov sraw traw s1raw vraw / c s tv s1 v)
  (setq c (/ (min aov bov) 3.41421356237))
  (cond
    (traw (setq s (/ (- bov traw) 2.0) tv traw))
    (sraw (setq s sraw tv (- bov (* 2.0 sraw))))
    (t (setq s c tv (- bov (* 2.0 c)))))
  (cond
    (vraw (setq s1 (/ (- aov vraw) 2.0) v vraw))
    (s1raw (setq s1 s1raw v (- aov (* 2.0 s1raw))))
    ;; an unmeasured vertical cut matches the horizontal one (45 deg)
    (t (setq s1 s v (- aov (* 2.0 s)))))
  (list s tv s1 v))

;; The overall-sheet ties (B T S A S1 V S2) are part of gr:geo's spec
;; when the Overall input method is chosen, laid around the live ring
;; the way pool:grecovties once laid them around the nominal one.

(defun pool:grecflow (oct / oldclay mode crosses pv imeth pvo ovbad ans xitems
                       nm2 npts grback
                       braw araw traw sraw s1raw vraw s2raw
                       ovres sv tv s1v vov hyp u2 vv2 bact aact sact s1act
                       tp bo le ri ltd lbd lew rtd rbd rew
                       evals edgecons crosscons dac dbd fq q
                       a b c d cen0 ml mr lend rend seed
                       res pts failed notes gcs gce gcarcs
                       xmin xmax ymin ymax w hh doff th cen odim
                       e p qq cc nm tgt act rows k fedge fcross
                       rbox mprims mlbls)
  (setq oldclay (getvar "CLAYER"))

  ;; perimeter input method first: measure every edge, or the overall
  ;; sheet (A/B overalls with the sides assumed symmetric).  The
  ;; cross-dim detail level is asked later, once the perimeter is in.
  ;; An octagon defaults to Overall -- knowing A and B is enough to
  ;; draw it, since its sides are all the same.
  (setq nm2 (if oct "Octagon" "Grecian")
        npts (if oct pool:*octnpts* pool:*grecnpts*))
  (defun gr:method ()
    ;; a form built from a sheet answers the LETTERS, which only the
    ;; Overall path asks for -- so this has to be form-answerable too,
    ;; or every letter it filled in would go unread
    (setq imeth (pool:askkwf 'imeth (strcat nm2 " perimeter input")
                             "Measured Overall" "Measured/Overall"
                             (if oct "Overall" nil) nil))
    nil)
  ;; The live guide geometry (see "live guide reshaping").  Both input
  ;; methods produce the same eight-corner ring in the index order the
  ;; whole flow reads, every unanswered value filled by the sheet's own
  ;; derivations -- so the first paint is the familiar nominal shape
  ;; and each answer reshapes it.  npts is left on the live ring, which
  ;; is what pool:greccross hangs the mode's diagonals on later.
  (defun gr:geo ( / bov aov ovr sv tvv s1v vov bo2 tp2 le2 ri2 qd
                    a2 b2 c2 d2 cenl ml mr u2 m0 cl ewd dy dg px
                    lt2 lb2 rt2 rb2 sc th spec km k p q e yt yb xa x2
                    tp1 tq1 nrm)
    (if (= imeth "Overall")
        (progn
          (setq bov (cond ((pool:pvdim 'b)) ((if oct 300.0 460.0)))
                aov (cond ((pool:pvdim 'a)) ((pool:pvdim 'b))
                          ((if oct 300.0 180.0)))
                ovr (if oct
                        (pool:octov aov bov (pool:pvdim 'ss) (pool:pvdim 'tt)
                                    (pool:pvdim 's1) (pool:pvdim 'vv))
                        (pool:grecov aov bov (pool:pvdim 'ss) (pool:pvdim 'tt)
                                     (pool:pvdim 's1) (pool:pvdim 'vv)
                                     (pool:pvdim 's2)))
                sv (max 1.0 (car ovr)) tvv (max 1.0 (cadr ovr))
                s1v (max 1.0 (caddr ovr)) vov (max 1.0 (cadddr ovr)))
          ;; the two frames the two nominal guides always used: the
          ;; grecian keeps A at the origin with the tips outboard, the
          ;; octagon keeps the tips on x = 0
          (if oct
              (setq npts (list (list sv 0.0) (list (+ sv tvv) 0.0)
                               (list bov s1v) (list bov (- aov s1v))
                               (list (+ sv tvv) aov) (list sv aov)
                               (list 0.0 (- aov s1v)) (list 0.0 s1v)))
              (setq npts (list (list 0.0 0.0) (list tvv 0.0)
                               (list (+ tvv sv) s1v)
                               (list (+ tvv sv) (- aov s1v))
                               (list tvv aov) (list 0.0 aov)
                               (list (- 0.0 sv) (- aov s1v))
                               (list (- 0.0 sv) s1v)))))
        (progn
          ;; measured edges: the body quad true to its four sides, each
          ;; end's tips projected off its chord -- the measured width
          ;; and diagonals where given, nominal proportions where not
          (setq bo2 (cond ((pool:pvdim 'bo)) ((pool:pvdim 'tp)) (360.0))
                tp2 (cond ((pool:pvdim 'tp)) ((pool:pvdim 'bo)) (bo2))
                le2 (cond ((pool:pvdim 'le)) ((pool:pvdim 'ri)) ((* 0.5 bo2)))
                ri2 (cond ((pool:pvdim 'ri)) ((pool:pvdim 'le)) (le2))
                qd (pool:fitsides bo2 tp2 le2 ri2 nil nil))
          (if (null qd)
              (setq qd (list (list 0.0 0.0) (list bo2 0.0)
                             (list bo2 (* 0.5 (+ le2 ri2))) (list 0.0 le2))))
          (setq a2 (car qd) b2 (cadr qd) c2 (caddr qd) d2 (cadddr qd)
                cenl (pool:v* (pool:v+ (pool:v+ a2 b2) (pool:v+ c2 d2)) 0.25)
                ml (pool:unit (pool:perp (pool:v- d2 a2))))
          (if (< (pool:dot (pool:v- (pool:mid a2 d2) cenl) ml) 0.0)
              (setq ml (pool:v* ml -1.0)))
          (setq mr (pool:unit (pool:perp (pool:v- c2 b2))))
          (if (< (pool:dot (pool:v- (pool:mid b2 c2) cenl) mr) 0.0)
              (setq mr (pool:v* mr -1.0)))
          ;; left end, centred on its chord
          (setq u2 (pool:unit (pool:v- d2 a2))
                m0 (pool:mid a2 d2)
                cl (distance a2 d2)
                ewd (min (cond ((pool:pvdim 'lew)) ((* 0.39 cl))) (* 0.95 cl))
                dy (* 0.5 (- cl ewd))
                dg (cond ((and (pool:pvdim 'ltd) (pool:pvdim 'lbd))
                          (* 0.5 (+ (pool:pvdim 'ltd) (pool:pvdim 'lbd))))
                         ((pool:pvdim 'ltd)) ((pool:pvdim 'lbd))
                         ((* 1.4142 dy)))
                px (sqrt (max (- (* dg dg) (* dy dy)) (* 0.01 cl cl)))
                lt2 (pool:v+ (pool:v+ m0 (pool:v* u2 (* 0.5 ewd)))
                             (pool:v* ml px))
                lb2 (pool:v+ (pool:v- m0 (pool:v* u2 (* 0.5 ewd)))
                             (pool:v* ml px)))
          ;; right end the same way
          (setq u2 (pool:unit (pool:v- c2 b2))
                m0 (pool:mid b2 c2)
                cl (distance b2 c2)
                ewd (min (cond ((pool:pvdim 'rew)) ((* 0.39 cl))) (* 0.95 cl))
                dy (* 0.5 (- cl ewd))
                dg (cond ((and (pool:pvdim 'rtd) (pool:pvdim 'rbd))
                          (* 0.5 (+ (pool:pvdim 'rtd) (pool:pvdim 'rbd))))
                         ((pool:pvdim 'rtd)) ((pool:pvdim 'rbd))
                         ((* 1.4142 dy)))
                px (sqrt (max (- (* dg dg) (* dy dy)) (* 0.01 cl cl)))
                rt2 (pool:v+ (pool:v+ m0 (pool:v* u2 (* 0.5 ewd)))
                             (pool:v* mr px))
                rb2 (pool:v+ (pool:v- m0 (pool:v* u2 (* 0.5 ewd)))
                             (pool:v* mr px))
                npts (list a2 b2 rb2 rt2 c2 d2 lt2 lb2))))
    ;; the ring, its labels, and (Overall only) the sheet ties
    (setq cenl (list 0.0 0.0))
    (foreach p npts (setq cenl (pool:v+ cenl p)))
    (setq cenl (pool:v* cenl 0.125)
          sc (/ (max (- (apply 'max (mapcar 'car npts))
                        (apply 'min (mapcar 'car npts)))
                     (- (apply 'max (mapcar 'cadr npts))
                        (apply 'min (mapcar 'cadr npts))))
                420.0)
          th (* 10.0 sc)
          spec nil km nil k 0)
    (foreach e pool:*grecedges*
      (setq p (nth (car e) npts) q (nth (cadr e) npts)
            spec (append spec
                         (list (list (if (member (caddr e) '(ad bc))
                                         "LINED" "LINE")
                                     p q)))
            km (cons (list (caddr e) k) km)
            k (1+ k)))
    (foreach p npts
      (setq spec (append spec
                         (list (list "TEXT"
                                     (pool:lbloff p cenl npts (* 22.0 sc))
                                     (* 12.0 sc)
                                     (nth (- k 10) pool:*grecnames*))))
            km (cons (list (pool:lblkey (nth (- k 10) pool:*grecnames*)) k) km)
            k (1+ k)))
    (if (= imeth "Overall")
        (progn
          ;; B/T/S across the top, A/S1/V down the left, S2 on the
          ;; bottom-right cut, like the field sheet
          (setq yt (+ aov (* 35.0 sc))
                yb (+ aov (* 62.0 sc)))
          (if oct
              (setq xa (- 0.0 (* 60.0 sc)) x2 (- 0.0 (* 30.0 sc))
                    tp1 (list 0.0 yb) tq1 (list bov yb))
              (setq xa (- 0.0 sv (* 45.0 sc)) x2 (- 0.0 sv (* 22.0 sc))
                    tp1 (list (- 0.0 sv) yb) tq1 (list (+ tvv sv) yb)))
          (setq nrm (pool:unit (pool:perp (pool:v- (nth 2 npts)
                                                   (nth 1 npts)))))
          (if (pool:inpoly (pool:v+ (pool:mid (nth 1 npts) (nth 2 npts)) nrm)
                           npts)
              (setq nrm (pool:v* nrm -1.0)))
          (setq spec (append spec
                       (pool:pvtiespec tp1 tq1 "B" th)
                       (pool:pvtiespec (list (if oct sv 0.0) yt)
                                       (list (if oct (+ sv tvv) tvv) yt)
                                       "T" th)
                       (pool:pvtiespec (list (if oct 0.0 (- 0.0 sv)) yt)
                                       (list (if oct sv 0.0) yt) "S" th)
                       (pool:pvtiespec (list xa 0.0) (list xa aov) "A" th)
                       (pool:pvtiespec (list x2 (- aov s1v)) (list x2 aov)
                                       "S1" th)
                       (pool:pvtiespec (list x2 s1v) (list x2 (- aov s1v))
                                       "V" th)
                       (pool:pvtiespec (pool:v+ (nth 1 npts)
                                                (pool:v* nrm (* 22.0 sc)))
                                       (pool:v+ (nth 2 npts)
                                                (pool:v* nrm (* 22.0 sc)))
                                       "S2" th)))
          (foreach p '("B" "T" "S" "A" "S1" "V" "S2")
            (setq km (cons (list p k (1+ k)) km)
                  k (+ k 2)))))
    (list spec km (pool:pvspecbox spec)))

  ;; the guide depends on the method, so it is (re)built by the stage
  ;; that follows it -- backing into the method question and out again
  ;; therefore always leaves a guide matching the chosen method
  (defun gr:guide ()
    (pool:pvkill)
    (setq mode "Simple" crosses nil
          pv (pool:pvlive 'gr:geo)
          pvo pv)
    nil)
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A/B bottom, C/D top, LT/LB left tips, RT/RB right tips.")

  ;; -------- body + ends: measured edges, or the overall sheet
  (defun gr:perim ( / ans)
   (setq grback nil)
   (if (= imeth "Overall")
      (progn
        (princ (strcat "\nOverall sheet -- symmetric " (strcase nm2 t)
                       "; the RED tie is being asked for."))
        (if oct
            (princ "\nThe cut letters may all be NA: A and B alone draw the octagon.")
            (princ "\nS and S1 may be NA: a taped cut FACE S2 sets them both (a 45)."))
        (princ "\n(after the first answer, Back re-asks the previous one)")
        ;; An in-square OCTAGON is square, so its two overalls are one
        ;; measurement, asked once.  A GRECIAN is a long pool -- its A
        ;; and B are never equal -- so it is always asked for both,
        ;; in square or not.
        (setq ans (pool:askseqb
                    (append
                      (if (and oct pool:*insq*)
                          (list (list 'b 'REQ "Overall size (A & B are equal)"
                                      (append (cdr (assoc "B" pvo))
                                              (cdr (assoc "A" pvo)))))
                          (list (list 'b 'REQ "B - overall length" (cdr (assoc "B" pvo)))
                                (list 'a 'REQ "A - overall width" (cdr (assoc "A" pvo)))))
                      (list (list 'tt 'NAX "T - top side length" (cdr (assoc "T" pvo)))
                            (list 'ss 'NAX "S - corner cut along the side" (cdr (assoc "S" pvo)))
                            (list 's1 'NAX "S1 - corner cut down the end" (cdr (assoc "S1" pvo)))
                            (list 'vv 'NAX "V - end width" (cdr (assoc "V" pvo)))
                            (list 's2 'NAX "S2 - corner cut face (check, sets NA S/S1)" (cdr (assoc "S2" pvo)))))
                    t))
        (if (eq ans 'POOL-BACK)
            (setq grback t braw 1.0 araw 1.0 ans nil))
        (setq braw (pool:sq ans 'b)
              araw (if (and oct pool:*insq*) braw (pool:sq ans 'a))
              traw (pool:sq ans 'tt) sraw (pool:sq ans 'ss)
              s1raw (pool:sq ans 's1) vraw (pool:sq ans 'vv)
              s2raw (pool:sq ans 's2)
              ovres (if grback
                        (list 1.0 1.0 1.0 1.0)
                        (if oct
                            (pool:octov araw braw sraw traw s1raw vraw)
                            (pool:grecov araw braw sraw traw s1raw vraw s2raw)))
              sv (car ovres) tv (cadr ovres)
              s1v (caddr ovres) vov (cadddr ovres))
        ;; walls beat corners (see pool:grecov): say so when holding a
        ;; taped T / V actually moved the taped S / S1, so the crew can
        ;; see in the report why their corner number came out different
        (if (and traw sraw (> (abs (- sv sraw)) 0.5))
            (princ (strcat "\nT is a wall, so it is held true -- S re-derived "
                           (rtos sraw 2 2) " -> " (rtos sv 2 2) ".")))
        (if (and vraw s1raw (> (abs (- s1v s1raw)) 0.5))
            (princ (strcat "\nV is a wall, so it is held true -- S1 re-derived "
                           (rtos s1raw 2 2) " -> " (rtos s1v 2 2) ".")))
        ;; the sheet letters must close POSITIVE against the overalls;
        ;; a letter that does not fit is adjusted, warned about now,
        ;; and its report rows go red
        (if (<= tv 1.0e-6)
            (progn
              (setq tv (min 12.0 (* 0.25 braw)) sv (/ (- braw tv) 2.0) ovbad t)
              (pool:valnote "OVERALL SHEET FAILED - S + T + S DOES NOT FIT B, ADJUSTED")))
        (if (<= sv 1.0e-6)
            (progn
              (setq sv (min 12.0 (* 0.125 braw)) tv (- braw sv sv) ovbad t)
              (pool:valnote "OVERALL SHEET FAILED - T LONGER THAN B, ADJUSTED")))
        (if (<= vov 1.0e-6)
            (progn
              (setq vov (min 12.0 (* 0.25 araw)) s1v (/ (- araw vov) 2.0) ovbad t)
              (pool:valnote "OVERALL SHEET FAILED - S1 + V + S1 DOES NOT FIT A, ADJUSTED")))
        (if (<= s1v 1.0e-6)
            (progn
              (setq s1v (min 12.0 (* 0.125 araw)) vov (- araw s1v s1v) ovbad t)
              (pool:valnote "OVERALL SHEET FAILED - V LONGER THAN A, ADJUSTED")))
        (setq hyp (sqrt (+ (* sv sv) (* s1v s1v)))
              bo tv tp tv le araw ri araw
              ltd hyp lbd hyp rtd hyp rbd hyp
              lew vov rew vov))
      (progn
        (princ "\n(Back re-asks the previous question)")
        (if pool:*insq*
            (progn
            (setq ans (pool:askseqb
                        (list (list 'bo 'REQ "Side (top & bottom)"
                                    (append (cdr (assoc 'ab pv)) (cdr (assoc 'cd pv))))
                              (list 'le 'REQ "Body end (left & right, A-D / B-C)"
                                    (append (cdr (assoc 'ad pv)) (cdr (assoc 'bc pv))))
                              (list 'ltd 'REQ "LEFT end diagonals (top & bottom)"
                                    (append (cdr (assoc 'ltd pv)) (cdr (assoc 'lbd pv))))
                              (list 'lew 'REQ "LEFT end width (LT-LB)"
                                    (append (cdr (assoc 'lew pv)) (pool:lbl pv '(lLT lLB))))
                              (list 'rtd 'REQ "RIGHT end diagonals (top & bottom)"
                                    (append (cdr (assoc 'rtd pv)) (cdr (assoc 'rbd pv))))
                              (list 'rew 'REQ "RIGHT end width (RT-RB)"
                                    (append (cdr (assoc 'rew pv)) (pool:lbl pv '(lRT lRB)))))
                        t))
            (if (eq ans 'POOL-BACK)
                (setq grback t)
                (setq bo (pool:sq ans 'bo) tp bo
                      le (pool:sq ans 'le) ri le
                      ltd (pool:sq ans 'ltd) lbd ltd
                      lew (pool:sq ans 'lew)
                      rtd (pool:sq ans 'rtd) rbd rtd
                      rew (pool:sq ans 'rew))))
            (progn
            (setq ans (pool:askseqb
                        (list (list 'bo 'REQ "Side BOTTOM (A-B)"
                                    (append (cdr (assoc 'ab pv)) (pool:lbl pv '(lA lB))))
                              (list 'tp 'REQ "Side TOP (D-C)"
                                    (append (cdr (assoc 'cd pv)) (pool:lbl pv '(lD lC))))
                              (list 'le 'REQ "End LEFT (A-D)"
                                    (append (cdr (assoc 'ad pv)) (pool:lbl pv '(lA lD))))
                              (list 'ri 'REQ "End RIGHT (B-C)"
                                    (append (cdr (assoc 'bc pv)) (pool:lbl pv '(lB lC))))
                              (list 'ltd 'REQ "LEFT end diagonal TOP (D-LT)"
                                    (append (cdr (assoc 'ltd pv)) (pool:lbl pv '(lD lLT))))
                              (list 'lbd 'REQ "LEFT end diagonal BOTTOM (A-LB)"
                                    (append (cdr (assoc 'lbd pv)) (pool:lbl pv '(lA lLB))))
                              (list 'lew 'REQ "LEFT end width (LT-LB)"
                                    (append (cdr (assoc 'lew pv)) (pool:lbl pv '(lLT lLB))))
                              (list 'rtd 'REQ "RIGHT end diagonal TOP (C-RT)"
                                    (append (cdr (assoc 'rtd pv)) (pool:lbl pv '(lC lRT))))
                              (list 'rbd 'REQ "RIGHT end diagonal BOTTOM (B-RB)"
                                    (append (cdr (assoc 'rbd pv)) (pool:lbl pv '(lB lRB))))
                              (list 'rew 'REQ "RIGHT end width (RT-RB)"
                                    (append (cdr (assoc 'rew pv)) (pool:lbl pv '(lRT lRB)))))
                        t))
            (if (eq ans 'POOL-BACK)
                (setq grback t)
                (setq bo (pool:sq ans 'bo) tp (pool:sq ans 'tp)
                      le (pool:sq ans 'le) ri (pool:sq ans 'ri)
                      ltd (pool:sq ans 'ltd) lbd (pool:sq ans 'lbd)
                      lew (pool:sq ans 'lew)
                      rtd (pool:sq ans 'rtd) rbd (pool:sq ans 'rbd)
                      rew (pool:sq ans 'rew)))))))
   (if grback 'POOL-BACK nil))

  ;; -------- the perimeter is in: now pick the cross-dim detail level,
  ;; draw those diagonals on the guide, and measure them (NA allowed)
  (defun gr:cross ( / ans xg v)
   (setq crosses nil xg nil)
   (if (not pool:*insq*)
      (progn
        (setq v (pool:askkwf 'gcross (strcat nm2 " cross-dim detail")
                             "Simple Center Complex" "Simple/Center/Complex"
                             nil t))
        (if (eq v 'POOL-BACK) (setq grback t)
            (setq mode v
                  crosses (pool:grecmode mode)
                  xg (mapcar '(lambda (c) (car (cdr (assoc (caddr c) pv))))
                             crosses)
                  pv (pool:greccross crosses pv npts)
                  xg (mapcar '(lambda (c) (car (cdr (assoc (caddr c) pv))))
                             crosses)))))
   (if grback
       'POOL-BACK
       (progn (gr:crossask xg) (if grback 'POOL-BACK nil))))

  (defun gr:crossask (xg / ans)
  (setq crosscons nil xitems nil k 0)
  (foreach e crosses
    (setq xitems (cons (list (read (strcat "x" (itoa k))) 'NAX
                             (strcat "Cross dim " (caddr e))
                             (append (cdr (assoc (caddr e) pv))
                                     (pool:lbl pv
                                       (list (pool:lblkey (nth (car e) pool:*grecnames*))
                                             (pool:lblkey (nth (cadr e) pool:*grecnames*))))))
                       xitems)
          k (1+ k)))
  (setq ans (if xitems (pool:askseqb (reverse xitems) t) nil) k 0)
  (if (eq ans 'POOL-BACK)
      (progn (pool:pvdel xg) (setq grback t crosses nil ans nil)))
  (foreach e crosses
    (setq crosscons (cons (list (car e) (cadr e)
                                (pool:sq ans (read (strcat "x" (itoa k)))))
                          crosscons)
          k (1+ k)))
  (setq crosscons (reverse crosscons))
  (princ))

  ;; -------- seed: fit the body quad, project nominal ends.
  ;; Runs at the top of gr:corners rather than after the input phase,
  ;; because a treatment's setback depends on the corner's real angle
  ;; -- and a grecian's corners are 135 degrees, not 90.  Pure, so
  ;; backing into a measurement and forward again simply re-fits.
  (defun gr:fit ( / )
  (setq evals (list (cons 'ab bo) (cons 'cd tp) (cons 'ad le) (cons 'bc ri)
                    (cons 'rbd rbd) (cons 'rew rew) (cons 'rtd rtd)
                    (cons 'ltd ltd) (cons 'lew lew) (cons 'lbd lbd))
        edgecons (mapcar '(lambda (e)
                            (list (car e) (cadr e) (cdr (assoc (caddr e) evals)) (cadddr e)))
                         pool:*grecedges*)
        dac (pool:crossget crosscons 0 4)
        dbd (pool:crossget crosscons 1 5)
        fq (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
        q (car fq)
        a (car q) b (cadr q) c (caddr q) d (cadddr q)
        cen0 (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        ml (pool:unit (pool:perp (pool:v- d a))))
  (if (< (pool:dot (pool:v- (pool:mid a d) cen0) ml) 0.0)
      (setq ml (pool:v* ml -1.0)))
  (setq mr (pool:unit (pool:perp (pool:v- c b))))
  (if (< (pool:dot (pool:v- (pool:mid b c) cen0) mr) 0.0)
      (setq mr (pool:v* mr -1.0)))
  (setq lend (pool:grecendp a d ml ltd lbd lew)
        rend (pool:grecendp b c mr rtd rbd rew)
        seed (list a b (cadr rend) (car rend) c d (car lend) (cadr lend))
        notes nil)
  (if (not (nth 5 lend))
      (setq notes (cons "LEFT END: diagonals/width did not fit -- 45 seed used" notes)))
  (if (not (nth 5 rend))
      (setq notes (cons "RIGHT END: diagonals/width did not fit -- 45 seed used" notes)))

  ;; -------- fit: Simple keeps the validated seed; Center/Complex
  ;; best-fit all 8 corners against every provided cross dim.
  ;; The tip-to-tip widths LT-RT and LB-RB are what B WOULD be on an
  ;; ideal grecian, so when measured they are held like WALLS (the
  ;; 1-inch edge band) -- just as the body chords A-D and B-C already
  ;; are -- rather than pulled like cross dims in the 2-inch band.
  ;; They still get their CROSS DIMENSIONS-style dim and report row
  ;; like any tie.
  (if (= mode "Simple")
      (setq pts seed failed (cadr fq))
      (progn
        (setq fedge edgecons fcross nil)
        (foreach cc crosscons
          (if (and (caddr cc) (pool:tippair (car cc) (cadr cc)))
              (setq fedge (append fedge
                                  (list (list (car cc) (cadr cc) (caddr cc)
                                              pool:*side-tol*))))
              (setq fcross (cons cc fcross))))
        (setq res (pool:fitpoly seed fedge (reverse fcross) pool:*cross-tol*)
              pts (car res)
              failed (cadr res))))
  (princ))

  ;; -------- corner treatments.  A grecian's 8 corners come in two
  ;; families: the BODY corners A/B/C/D, where a long wall runs into a
  ;; cut face, and the END TIPS LT/LB/RT/RB, where that cut face lands
  ;; on the end wall.  In square the two families take one answer each
  ;; (the tips default to the body answer, since a pool that rounds
  ;; one usually rounds both); out of square every corner is asked on
  ;; its own, Enter reusing the previous -- the same split the
  ;; rectangle makes.
  ;;
  ;; The shape is FIT at the top of this stage, exactly as the L pool
  ;; fits at the top of its own corner stage: the setback depends on
  ;; the real corner angle, and fitting inside the stage (rather than
  ;; as a stage of its own) keeps Back working -- an always-succeeding
  ;; stage would swallow the Back out of the corner question.
  (defun gr:corners ( / v bc tc bcap tcap bsb v2 k caps angs lbls ents)
    (princ "\nFitting pool body to the measurements ...")
    (gr:fit)
    (setq gcs (list (list "Square" 0.0) (list "Square" 0.0) (list "Square" 0.0)
                    (list "Square" 0.0) (list "Square" 0.0) (list "Square" 0.0)
                    (list "Square" 0.0) (list "Square" 0.0)))
    (setq v (pool:askynf 'crec
                         "Anything to record about the corners (radius / cut / not given)?"
                         "No" t))
    (cond
      ((eq v 'POOL-BACK) 'POOL-BACK)
      ((not v) nil)
      (pool:*insq*
       ;; one answer for the four body corners, one for the four tips.
       ;; The body answer covers the SHARPEST of A/B/C/D, since that is
       ;; the corner whose cut reaches furthest along its walls, and is
       ;; budgeted half the shortest wall it touches -- which leaves
       ;; the other half of every cut face for the tip on its far end.
       (setq bcap (pool:groupcap pts pool:*grecbody*)
             bc (pool:askcorner "the body corners A, B, C and D" nil nil
                                (pool:lbl pv '(lA lB lC lD))
                                (car bcap) (cadr bcap) t))
       (if (eq bc 'POOL-BACK)
           'POOL-BACK
           (progn
             ;; each tip is then capped by what the body cut actually
             ;; LEFT on the cut face they share; the two tips on one
             ;; END wall share that wall with each other, so it halves
             (setq bsb (* (cadr bc) (pool:cornerk (car bc) (cadr bcap)))
                   tcap nil)
             (foreach k pool:*greccuts*
               (setq v2 (- (distance (nth (car k) pts) (nth (cadr k) pts)) bsb)
                     tcap (if tcap (min tcap v2) v2)))
             (foreach k pool:*grecwalls*
               (setq v2 (* 0.5 (distance (nth (car k) pts) (nth (cadr k) pts)))
                     tcap (min tcap v2)))
             (setq tc (pool:askcorner "the end-tip corners LT, LB, RT and RB"
                                      (car bc) (cadr bc)
                                      (pool:lbl pv '(lLT lLB lRT lRB))
                                      (max 0.0 tcap)
                                      (cadr (pool:groupcap pts pool:*grectips*)) t))
             (if (eq tc 'POOL-BACK)
                 'POOL-BACK
                 ;; index order is 0=A 1=B 2=RB 3=RT 4=C 5=D 6=LT 7=LB
                 (progn (setq gcs (list bc bc tc tc bc bc tc tc)) nil)))))
      (t
       ;; out of square: all eight, round the perimeter, Enter reusing
       (princ "\n(per-corner treatment; press Enter to reuse the previous corner)")
       (setq caps nil angs nil lbls nil ents nil k 0)
       (while (< k 8)
         (setq caps (cons (pool:polycap pts k) caps)
               angs (cons (pool:polywedge pts k) angs)
               lbls (cons (strcat "Corner " (nth k pool:*grecnames*)) lbls)
               ents (cons (pool:lbl pv (list (pool:lblkey (nth k pool:*grecnames*))))
                          ents)
               k (1+ k)))
       (setq v (pool:askcorners (reverse lbls) (reverse caps)
                                (reverse angs) (reverse ents)))
       (if (eq v 'POOL-BACK)
           'POOL-BACK
           (progn (setq gcs v) nil)))))

  ;; ---- the input phase, with Back working right across it
  (pool:stages (list 'gr:method 'gr:guide 'gr:perim 'gr:cross 'gr:corners))
  (pool:pvkill)

  ;; pts / failed / notes were fit at the top of gr:corners, so the
  ;; corner questions could be sized against the real corner angles
  (setq gce (pool:ringends pts gcs))

  ;; -------- extents / scale
  (setq xmin (apply 'min (mapcar 'car pts))
        xmax (apply 'max (mapcar 'car pts))
        ymin (apply 'min (mapcar 'cadr pts))
        ymax (apply 'max (mapcar 'cadr pts))
        w (- xmax xmin) hh (- ymax ymin)
        doff (max 12.0 (/ (max w hh) 18.0))
        th (max 3.0 (/ (max w hh) 70.0))
        pool:*dashlt* (pool:ltload "DASHED")
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 8.0)))

  ;; -------- perimeter (POOL) + internal end chords (dashed,
  ;; POOL-NOTES).  Perimeter walls run between the corner TREATMENT
  ;; ends and the treatment itself closes each corner (a square corner
  ;; degenerates to the plain corner-to-corner wall); the two internal
  ;; chords are not walls, so they stay on the true corners.
  (foreach e pool:*grecedges*
    (setq p (nth (car e) pts) qq (nth (cadr e) pts))
    (if (member (caddr e) '(ad bc))
        (pool:lined p qq)
        (pool:line (cadr (nth (car e) gce))          ; eNext(i)
                   (car (nth (cadr e) gce)) "POOL"))) ; ePrev(j)
  (setq gcarcs (pool:ringarcs gce gcs "POOL"))

  ;; -------- dimensions (DIMENSION)
  ;; In-square: the field-sheet exterior set only -- S+T share a row
  ;; above the top with B outboard of them, S1+V share a column left
  ;; of the pool with A outboard, and S2 reads once on the
  ;; bottom-right cut.  Every corner is the same corner in square, so
  ;; one of each keeps the sheet clean.  Out-of-square: every edge
  ;; differs, so every edge is dimensioned as before.
  ;; Style split per the reference sheet: the letters that SUBDIVIDE
  ;; an overall (S, T, S1, V -- and out of square, every edge) read in
  ;; SIDE STANDARD; the overalls themselves (B, A / the end chords)
  ;; and the S2 corner cut stay in the standard style.
  (setvar "CLAYER" "DIMENSION")
  (if pool:*insq*
      (progn
        ;; S: pool's left extreme to the top side start (row 1)
        (setq p (nth 6 pts) qq (nth 5 pts))              ; LT, D
        (pool:dimalgs (list (car p) ymax) qq
                      (list (* 0.5 (+ (car p) (car qq))) (+ ymax doff)))
        ;; T: the top side D-C (row 1)
        (pool:dimwalls pts gcs 5 4
                       (list (car (pool:mid (nth 5 pts) (nth 4 pts)))
                             (+ ymax doff)))
        ;; B: overall, tip to tip LT-RT (row 2, outboard)
        (pool:dimalg (nth 6 pts) (nth 3 pts)
                     (list (car (pool:mid (nth 6 pts) (nth 3 pts)))
                           (+ ymax (* 1.9 doff))))
        ;; S1: top down to the left tip (column 1)
        (pool:dimalgs (list xmin ymax) (nth 6 pts)
                      (list (- xmin doff)
                            (* 0.5 (+ ymax (cadr (nth 6 pts))))))
        ;; V: the left end LT-LB (column 1)
        (pool:dimwalls pts gcs 6 7
                       (list (- xmin doff)
                             (cadr (pool:mid (nth 6 pts) (nth 7 pts)))))
        ;; A: overall, the A-D chord (column 2, outboard)
        (pool:dimalg (nth 0 pts) (nth 5 pts)
                     (list (- xmin (* 1.9 doff))
                           (cadr (pool:mid (nth 0 pts) (nth 5 pts)))))
        ;; S2: the bottom-right corner cut, once
        (pool:dimwall pts gcs 1 2
                      (pool:outoffp (nth 1 pts) (nth 2 pts) pts doff)))
      (foreach e pool:*grecedges*
        (setq p (nth (car e) pts) qq (nth (cadr e) pts))
        (cond
          ((= (caddr e) 'ad)            ; left end chord -> outboard left
           (pool:dimalg p qq (list (- xmin (* 0.6 doff)) (cadr (pool:mid p qq)))))
          ((= (caddr e) 'bc)            ; right end chord -> outboard right
           (pool:dimalg p qq (list (+ xmax (* 0.6 doff)) (cadr (pool:mid p qq)))))
          (t                            ; a wall -> hooked to the pool
           (pool:dimwalls pts gcs (car e) (cadr e)
                          (pool:outoffp p qq pts doff))))))
  ;; provided cross dims, in the CROSS DIMENSIONS style when available
  (setq odim (pool:dimxbegin) k 0)
  (foreach cc crosscons
    (if (caddr cc)
        (pool:dimalg (nth (car cc) pts) (nth (cadr cc) pts)
                     (pool:v+ (pool:mid (nth (car cc) pts) (nth (cadr cc) pts))
                              (pool:v* (pool:unit
                                         (pool:perp (pool:v- (nth (cadr cc) pts)
                                                             (nth (car cc) pts))))
                                       (* (if (= 0 (rem k 2)) 0.12 -0.12) doff)))))
    (setq k (1+ k)))
  (pool:dimxend odim)
  ;; corner treatments: one Typ. per family in square (body / tips),
  ;; each treated corner its own dim out of square (collapsing back to
  ;; Typ. when Enter reused one answer all the way round)
  ;; out of square the eight are their own groups -- but B leads the
  ;; list, as it does in square, so an all-same answer puts its one
  ;; Typ. mark on the same corner either way
  (pool:dimringcorners pts gcs gce gcarcs cen doff
                       (if pool:*insq*
                           (list '(1 0 4 5) '(2 3 6 7))
                           (mapcar 'list '(1 0 2 3 4 5 6 7))))
  (setvar "CLAYER" oldclay)

  ;; corner letters live on the mini-model beside the report, not in
  ;; the corners of the drawing itself -- see the pool:minimap call

  ;; -------- report table
  (setq rows nil)
  (foreach e pool:*grecedges*
    (setq nm (pool:grecnm (car e) (cadr e))
          tgt (cdr (assoc (caddr e) evals))
          act (distance (nth (car e) pts) (nth (cadr e) pts))
          rows (cons (list nm tgt act) rows)))
  (foreach cc crosscons
    (setq nm (pool:grecnm (car cc) (cadr cc))
          act (distance (nth (car cc) pts) (nth (cadr cc) pts))
          rows (cons (list (strcat "X " nm) (caddr cc) act) rows)))
  (setq rows (reverse rows))
  ;; corner treatments: one row per family in square, per corner out
  (setq rows (append rows
    (if pool:*insq*
        (pool:cornerrows (list "BODY CORNER" "END TIP")
                         (list (nth 0 gcs) (nth 2 gcs)))
        (pool:cornerrows (mapcar '(lambda (nm) (strcat "CORNER " nm))
                                 pool:*grecnames*)
                         gcs))))
  ;; overall-sheet letters vs the fitted shape
  (if (= imeth "Overall")
      (progn
        (setq u2 (pool:v- (nth 1 pts) (nth 0 pts))
              vv2 (pool:v- (nth 5 pts) (nth 0 pts))
              bact (distance
                     (pool:linex cen u2 (nth 7 pts) (pool:v- (nth 6 pts) (nth 7 pts)))
                     (pool:linex cen u2 (nth 2 pts) (pool:v- (nth 3 pts) (nth 2 pts))))
              aact (distance
                     (pool:linex cen vv2 (nth 0 pts) u2)
                     (pool:linex cen vv2 (nth 5 pts) (pool:v- (nth 4 pts) (nth 5 pts))))
              sact (abs (pool:dot (pool:v- (nth 6 pts) (nth 5 pts)) (pool:unit u2)))
              s1act (abs (pool:dot (pool:v- (nth 6 pts) (nth 5 pts)) (pool:unit vv2))))
        (setq rows (append rows (list
          (list "OV B" braw bact)
          (list "OV A" araw aact)
          (append (list "OV T" traw (distance (nth 5 pts) (nth 4 pts)))
                  (if ovbad (list t) nil))
          (append (list "OV S" sraw sact) (if ovbad (list t) nil))
          (append (list "OV S1" s1raw s1act) (if ovbad (list t) nil))
          (append (list "OV V" vraw (distance (nth 6 pts) (nth 7 pts)))
                  (if ovbad (list t) nil))
          (list "OV S2" s2raw (distance (nth 5 pts) (nth 6 pts))))))))
  ;; -------- pool bottom (interior pipeline)
  (setq rows (append rows (pool:hopgrecdsp pts doff th)))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (setq rbox (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES"))
  ;; perimeter mini-model with the corner letters, right of the report
  (setq mprims nil k 0)
  (foreach e pool:*grecedges*
    (if (not (member (caddr e) '(ad bc)))
        (setq mprims (cons (list 'l (nth (car e) pts) (nth (cadr e) pts))
                           mprims))))
  (setq mlbls nil)
  (foreach p pts
    (setq mlbls (append mlbls (list (cons p (nth (length mlbls) pool:*grecnames*))))))
  (pool:minimap mprims pts mlbls (+ (car rbox) (* 3.0 th)) (cadr rbox)
                (* 24.0 th) th)
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- L / Lazy L pools --------------------------------
;;;
;;;  Six-corner pools, one wing:      F -------- E
;;;                                   |           \
;;;    True L: joint D-E is a         |            D ------- C
;;;    square step; Lazy L: D-E       |                      |
;;;    is an angled joint.            A -------------------- B
;;;
;;;  Sides A-B, B-C, C-D, D-E, E-F, F-A plus up to six cross dims
;;;  (A-C, B-D, C-E, D-F, A-E, B-F -- any of them may be NA).

(setq pool:*hexsides* (list '(0 1) '(1 2) '(2 3) '(3 4) '(4 5) '(5 0)))
(setq pool:*hexsidenames* (list "A-B" "B-C" "C-D" "D-E" "E-F" "F-A"))
(setq pool:*hexdiags* (list '(0 2) '(1 3) '(2 4) '(3 5) '(0 4) '(1 5)
                            '(0 3) '(1 4) '(2 5)))
(setq pool:*hexdiagnames* (list "A-C" "B-D" "C-E" "D-F" "A-E" "B-F"
                                "A-D" "B-E" "C-F"))

;; Nominal right-angle (or 45-degree jointed) L built from the given
;; side lengths -- the starting shape for the relaxation fit.
(defun pool:hexguess (sides lazy / ab bc cd de fa a b c d e f)
  (setq ab (nth 0 sides) bc (nth 1 sides) cd (nth 2 sides)
        de (nth 3 sides) fa (nth 5 sides)
        a (list 0.0 0.0)
        b (list ab 0.0))
  (if lazy
      ;; constant-width pool bent 45 degrees (per the reference):
      ;; B-C and D-E are the bend sides, C-D the far end
      (setq c (pool:v+ b (list (* bc 0.7071067812) (* bc 0.7071067812)))
            d (pool:v+ c (list (* cd -0.7071067812) (* cd 0.7071067812)))
            e (pool:v+ d (list (* de -0.7071067812) (* de -0.7071067812)))
            f (list 0.0 fa))
      ;; true L (per the reference): B-C is the full right end, the
      ;; wing sits top-right and the notch top-left
      (setq c (list ab bc)
            d (list (- ab cd) bc)
            e (pool:v- d (list 0.0 de))
            f (pool:v- e (list (nth 4 sides) 0.0))))
  (list a b c d e f))

;; In-square lazy L: the DEEP END is what has to be right.  The hopper
;; sits in the main section (A - break - E - F) and is dimensioned off
;; A-B, E-F and F-A, so those three are held EXACTLY and the main body
;; comes out a true rectangle -- A-B and E-F dead horizontal, F-A dead
;; vertical, square corners at A and F.
;;
;; That leaves the wing to absorb whatever the tape did not close.
;; B-C and D-E are held PARALLEL (both on the 45-degree bend), so the
;; only freedom left is how far C and D slide along their own bend
;; lines: one number, m -- the slide of D relative to C, measured
;; along the bend.  It is picked to spread the closure error over the
;; three wing sides in the least-squares sense: B-C and D-E give up
;; half of it each (one grows exactly as much as the other shrinks)
;; and C-D takes what is left.  Every one of those deltas shows in the
;; report, red past pool:*side-tol* (see the SIDES DO NOT CLOSE note).
;;
;; The old build walked the whole chain A->B->C->D->E at exact headings
;; and dropped F onto the left wall, which piled the entire closure
;; error into E-F and F-A -- the two sides the hopper is measured
;; from, and the two that must not move.

;; Summed squared length error of the three wing sides at slide m.
;; m0 is the slide the taped B-C / D-E would have; (vx vy) is B->E,
;; the wing's closing vector, so C-D comes to |(vx+m, vy+m)|.  B-C and
;; D-E split (m - m0) between them, which lands their two squared
;; errors at exactly (m - m0)^2 together.
(defun pool:hexwing (m m0 vx vy cd / g)
  (setq g (sqrt (max 0.0 (+ (* 2.0 m m) (* 2.0 m (+ vx vy))
                            (* vx vx) (* vy vy)))))
  (+ (* (- m m0) (- m m0)) (* (- g cd) (- g cd))))

(defun pool:hexsquare (sides / u ab bc cd de ef fa a b c d e f vx vy m0
                             lo hi n i step m fm bm bf m1 m2 sl s1 s2)
  (setq u 0.7071067812
        ab (nth 0 sides) bc (nth 1 sides) cd (nth 2 sides)
        de (nth 3 sides) ef (nth 4 sides) fa (nth 5 sides)
        a (list 0.0 0.0)
        b (list ab 0.0)
        f (list 0.0 fa)
        e (list ef fa)
        vx (- (car e) (car b))
        vy (- (cadr e) (cadr b))
        m0 (* u (- de bc))
        ;; C stays past B and D past E: the slide can never eat more
        ;; than a bend side's own length (a hair inside, so neither
        ;; collapses to nothing)
        lo (+ (- m0 (* 2.0 u de)) 0.001)
        hi (- (+ m0 (* 2.0 u bc)) 0.001)
        n 240
        step (/ (- hi lo) n)
        bm m0
        bf (pool:hexwing m0 m0 vx vy cd)
        i 0)
  ;; coarse sweep first -- the wing error is a squared distance to a
  ;; circle and can hold two dips, so start the polish in the deeper
  ;; one rather than wherever a local slope points
  (while (<= i n)
    (setq m (+ lo (* i step))
          fm (pool:hexwing m m0 vx vy cd))
    (if (< fm bf) (setq bf fm bm m))
    (setq i (1+ i)))
  ;; ternary polish inside the winning bucket
  (setq lo (max lo (- bm step))
        hi (min hi (+ bm step))
        i 0)
  (while (< i 40)
    (setq m1 (+ lo (/ (- hi lo) 3.0))
          m2 (- hi (/ (- hi lo) 3.0)))
    (if (< (pool:hexwing m1 m0 vx vy cd) (pool:hexwing m2 m0 vx vy cd))
        (setq hi m2)
        (setq lo m1))
    (setq i (1+ i)))
  (setq m (* 0.5 (+ lo hi))
        sl (/ (- m m0) (* 2.0 u))     ; what each bend side gives up
        s1 (- bc sl)
        s2 (+ de sl)
        c (pool:v+ b (list (* s1 u) (* s1 u)))
        d (pool:v+ e (list (* s2 u) (* s2 u))))
  (list a b c d e f))

;; Side constraints (banded by +/-band) for the hexagon.
(defun pool:hexsidecon (sides band w / k out pr)
  (setq k 0 out nil)
  (foreach pr pool:*hexsides*
    (setq out (cons (list (car pr) (cadr pr)
                          (- (nth k sides) band) (+ (nth k sides) band) w)
                    out)
          k (1+ k)))
  (reverse out))

;; Exact-pull constraints for the provided (non-NA) cross dims.
(defun pool:hexdiagcon (diags w / k out pr tgt)
  (setq k 0 out nil)
  (foreach pr pool:*hexdiags*
    (setq tgt (nth k diags))
    (if tgt
        (setq out (cons (list (car pr) (cadr pr) tgt tgt w) out)))
    (setq k (1+ k)))
  (reverse out))

;; (max-side-delta max-cross-delta) of a fitted hexagon; NA cross dims
;; are ignored.
(defun pool:hexerr (pts sides diags / k pr smax xmax d)
  (setq smax 0.0 xmax 0.0 k 0)
  (foreach pr pool:*hexsides*
    (setq d (abs (- (distance (nth (car pr) pts) (nth (cadr pr) pts))
                    (nth k sides)))
          smax (max smax d)
          k (1+ k)))
  (setq k 0)
  (foreach pr pool:*hexdiags*
    (if (nth k diags)
        (setq d (abs (- (distance (nth (car pr) pts) (nth (cadr pr) pts))
                        (nth k diags)))
              xmax (max xmax d)))
    (setq k (1+ k)))
  (list smax xmax))

;; Fit the L hexagon (same policy as the quad):
;;  1. sides held true, provided cross dims pulled as close as they
;;     will come; inside tolerance -> done
;;  2. sides may flex inside +/-stol to pull the cross dims in
;;  3. otherwise sides held true, cross dims as close as possible,
;;     failure flag set
;; Returns (pts failed).
(defun pool:fithex (sides diags lazy stol xtol / guess p1 e1 p2 e2 any dg)
  ;; In-square lazy L (no cross dims measured): build the shape at
  ;; exact headings instead of relaxing, so A-B // E-F and B-C // D-E
  ;; hold perfectly and the closure error goes into the WING lengths,
  ;; leaving the deep-end sides (A-B, E-F, F-A) true -- pool:hexsquare.
  (setq any nil)
  (foreach dg diags (if dg (setq any t)))
  (if (and lazy (not any))
      (list (pool:hexsquare sides) nil)
      (pool:fithexr sides diags lazy stol xtol)))

(defun pool:fithexr (sides diags lazy stol xtol / guess p1 e1 p2 e2)
  (setq guess (pool:hexguess sides lazy)
        p1 (pool:relaxn guess
                        (append (pool:hexdiagcon diags 0.4)
                                (pool:hexsidecon sides 0.0 1.0))
                        3000))
  ;; polish: a sides-only pass so the sides land exactly true
  (setq p1 (pool:relaxn p1 (pool:hexsidecon sides 0.0 1.0) 400)
        e1 (pool:hexerr p1 sides diags))
  (if (<= (cadr e1) xtol)
      (list p1 nil)
      (progn
        (setq p2 (pool:relaxn p1
                              (append (pool:hexdiagcon diags 0.5)
                                      (pool:hexsidecon sides stol 1.0))
                              3000)
              e2 (pool:hexerr p2 sides diags))
        (if (and (<= (car e2) (+ stol 0.05)) (<= (cadr e2) (+ xtol 0.05)))
            (list p2 nil)
            (list p1 t)))))

;; Point-in-polygon (ray casting) -- the L is not convex, so side
;; dimensions find "outward" by testing against the actual shape.
(defun pool:inpoly (p poly / n i j xi yi xj yj in x y)
  (setq x (car p) y (cadr p)
        n (length poly)
        i 0 j (1- n) in nil)
  (while (< i n)
    (setq xi (car (nth i poly)) yi (cadr (nth i poly))
          xj (car (nth j poly)) yj (cadr (nth j poly)))
    (if (and (or (and (> yi y) (<= yj y))
                 (and (> yj y) (<= yi y)))
             (< x (+ xi (* (- xj xi) (/ (- y yi) (- yj yi))))))
        (setq in (not in)))
    (setq j i i (1+ i)))
  in)

;; Midpoint of p->q offset by dist to the side that lies OUTSIDE poly.
(defun pool:outoffp (p q poly dist / m n)
  (setq m (pool:mid p q)
        n (pool:unit (pool:perp (pool:v- q p))))
  (if (pool:inpoly (pool:v+ m (pool:v* n 1.0)) poly)
      (setq n (pool:v* n -1.0)))
  (pool:v+ m (pool:v* n dist)))

;; Corner-label position: away from the centroid, but flipped when
;; that lands inside the shape (the inner corner of an L).
(defun pool:lbloff (p cen poly dist / dir cand)
  (setq dir (pool:unit (pool:v- p cen))
        cand (pool:v+ p (pool:v* dir dist)))
  (if (pool:inpoly cand poly)
      (pool:v+ p (pool:v* dir (- dist)))
      cand))

;; The L / Lazy L guide is built by hx:geo inside pool:hexflow (a
;; live-guide geometry function fed to pool:pvlive): the nominal body
;; reshapes through pool:hexguess as the six sides come in.  hx:geo
;; keeps the flow's hxg on the live ring, which is what the cross
;; diagonals below are drawn against.

;; Add the nine (eight on a lazy L) cross diagonals to the L guide once
;; the side lengths are in, on the live guide ring pts.  Returns the
;; extended highlight assoc.
(defun pool:hexcross (lazy pv pts / keys k ent)
  (setq keys (list 'ac 'bd 'ce 'df 'ae 'bf 'ad 'be 'cf)
        k 0)
  (foreach pr pool:*hexdiags*
    ;; the lazy L omits the B-E joint diagonal (per the reference)
    (if (not (and lazy (equal pr (list 1 4))))
        (setq ent (pool:pvadd (pool:pvlined (nth (car pr) pts)
                                            (nth (cadr pr) pts)))
              pv (cons (cons (nth k keys) (list ent)) pv)))
    (setq k (1+ k)))
  pv)

;; Full guided flow for L / Lazy L pools: preview, prompts, fit, draw,
;; dimension and report.  Caller handles sysvars / undo / zoom-extents.
(defun pool:hexflow (lazy / oldclay pv sides diags res pts failed notes ans hxr
                            cen p pr k w hh xmin xmax ymax ymin doff th
                            odim rows lbls dv mquad sq4 elast hxg
                            octy ocsz icty icsz oc ic hcs hce hcarcs ock
                            rbox mprims mlbls soff)
  (setq oldclay (getvar "CLAYER"))
  ;; The live guide geometry (see "live guide reshaping"): each side
  ;; answered so far is held, every side still open takes its nominal
  ;; length scaled by how the answered ones compare to theirs, and
  ;; pool:hexguess folds the six into the L.  hxg keeps the live ring
  ;; for the cross diagonals to hang on.
  (defun hx:geo ( / nom keys ratio n k s pr sd cen sc spec km p)
    (setq nom (if lazy
                  (list (list 0.0 0.0) (list 296.0 0.0) (list 414.0 119.0)
                        (list 296.0 238.0) (list 226.0 168.0)
                        (list 0.0 168.0))
                  (list (list 0.0 0.0) (list 360.0 0.0) (list 360.0 315.0)
                        (list 225.0 315.0) (list 225.0 180.0)
                        (list 0.0 180.0)))
          keys (list 'ab 'bc 'cd 'de 'ef 'fa)
          ratio 0.0 n 0 k 0 sd nil)
    (foreach pr pool:*hexsides*
      (setq s (pool:pvdim (nth k keys)))
      (if s
          (setq ratio (+ ratio (/ s (distance (nth (car pr) nom)
                                              (nth (cadr pr) nom))))
                n (1+ n)))
      (setq k (1+ k)))
    (setq ratio (if (> n 0) (/ ratio n) 1.0)
          k 0)
    (foreach pr pool:*hexsides*
      (setq s (pool:pvdim (nth k keys))
            sd (cons (if s s (* ratio (distance (nth (car pr) nom)
                                                (nth (cadr pr) nom))))
                     sd)
            k (1+ k)))
    (setq hxg (pool:hexguess (reverse sd) lazy)
          cen (list 0.0 0.0))
    (foreach p hxg (setq cen (pool:v+ cen p)))
    (setq cen (pool:v* cen (/ 1.0 6.0))
          sc (/ (max (- (apply 'max (mapcar 'car hxg))
                        (apply 'min (mapcar 'car hxg)))
                     (- (apply 'max (mapcar 'cadr hxg))
                        (apply 'min (mapcar 'cadr hxg))))
                380.0)
          spec nil km nil k 0)
    (foreach pr pool:*hexsides*
      (setq spec (append spec (list (list "LINE" (nth (car pr) hxg)
                                          (nth (cadr pr) hxg))))
            km (cons (list (nth k keys) k) km)
            k (1+ k)))
    (foreach p hxg
      (setq spec (append spec
                         (list (list "TEXT"
                                     (pool:lbloff p cen hxg (* 20.0 sc))
                                     (* 12.0 sc)
                                     (nth (- k 6) (list "A" "B" "C" "D"
                                                        "E" "F")))))
            km (cons (list (pool:lblkey (nth (- k 6) (list "A" "B" "C" "D"
                                                           "E" "F")))
                           k)
                     km)
            k (1+ k)))
    (list spec km (pool:pvspecbox spec)))
  (setq pv (pool:pvlive 'hx:geo))
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C right end top, D inner corner, E wing corner, F top-left.")
  (princ "\n(Back re-asks the previous question, right back to the start)")
  (defun hx:sides ( / ans)
  (setq ans (pool:askseqb
              (mapcar '(lambda (q)
                         (list (car q) 'REQ (cadr q)
                               (append (cdr (assoc (caddr q) pv))
                                       (pool:lbl pv (cadddr q)))))
                      (if lazy
                          (list (list 'ab "Main side A-B (bottom)" 'ab '(lA lB))
                                (list 'bc "Lower bend side B-C (45 deg)" 'bc '(lB lC))
                                (list 'cd "Far end C-D" 'cd '(lC lD))
                                (list 'de "Upper bend side D-E (45 deg)" 'de '(lD lE))
                                (list 'ef "Top side E-F" 'ef '(lE lF))
                                (list 'fa "Left end F-A" 'fa '(lF lA)))
                          (list (list 'ab "Side A-B (bottom, full length)" 'ab '(lA lB))
                                (list 'bc "End B-C (right end, full height)" 'bc '(lB lC))
                                (list 'cd "Side C-D (top of wing)" 'cd '(lC lD))
                                (list 'de "Step D-E (down to the inner corner)" 'de '(lD lE))
                                (list 'ef "Side E-F (top of main section)" 'ef '(lE lF))
                                (list 'fa "End F-A (left end)" 'fa '(lF lA)))))
              nil)
        sides (mapcar '(lambda (k) (pool:sq ans k)) '(ab bc cd de ef fa)))
    nil)
  ;; cross dims only when out-of-square; in-square squares up to sides.
  ;; The diagonals join the guide now that the sides are all in, on the
  ;; live ring the guide has reshaped itself to.
  (defun hx:diags ( / ans)
  (if (not pool:*insq*) (setq pv (pool:hexcross lazy pv hxg)))
  (setq diags
        (if pool:*insq*
            (list nil nil nil nil nil nil nil nil nil)
            (progn
              (setq ans (pool:askseqb
                          (mapcar '(lambda (q)
                                     (list (car q) 'NAX
                                           (strcat "Cross dim " (cadr q))
                                           (append (cdr (assoc (car q) pv))
                                                   (pool:lbl pv (caddr q)))))
                                  (append
                                    (list (list 'ac "A-C" '(lA lC))
                                          (list 'bd "B-D" '(lB lD))
                                          (list 'ce "C-E" '(lC lE))
                                          (list 'df "D-F" '(lD lF))
                                          (list 'ae "A-E" '(lA lE))
                                          (list 'bf "B-F" '(lB lF))
                                          (list 'ad "A-D" '(lA lD)))
                                    ;; the lazy L's bend joint is not taped
                                    (if lazy nil (list (list 'be "B-E" '(lB lE))))
                                    (list (list 'cf "C-F" '(lC lF)))))
                          t))
              (if (eq ans 'POOL-BACK)
                  'POOL-BACK
                  (list (pool:sq ans 'ac) (pool:sq ans 'bd) (pool:sq ans 'ce)
                        (pool:sq ans 'df) (pool:sq ans 'ae) (pool:sq ans 'bf)
                        (pool:sq ans 'ad) (if lazy nil (pool:sq ans 'be))
                        (pool:sq ans 'cf))))))
  (if (eq diags 'POOL-BACK) 'POOL-BACK nil))

  ;; corner treatments, like the rectangle: the five OUTER corners
  ;; take one answer; the INNER corner (E) is typically different, so
  ;; it is asked separately (Enter reuses the outer answer).
  ;;
  ;; The body is FIT first, at the top of this stage rather than after
  ;; the questions, because a treatment's setback depends on the real
  ;; corner angle and on an L those are never all 90 degrees -- a lazy
  ;; L bends 135 at B and E even in-square, and out-of-square every
  ;; corner drifts.  Fitting here (not as its own stage) keeps Back
  ;; working: an extra always-succeeding stage would swallow the Back
  ;; out of the corner question by falling straight forward again.
  ;; Re-entering after a Back re-fits, which is what changing a side
  ;; or a diagonal should do.
  (defun hx:corners ( / v k oang mins de ef icap)
    (princ "\nFitting pool body to the measurements ...")
    (setq res (pool:fithex sides diags lazy pool:*side-tol* pool:*cross-tol*)
          pts (car res)
          failed (cadr res)
          octy "Square" ocsz 0.0 icty "Square" icsz 0.0)
    (setq v (pool:askynf 'crec
                         "Anything to record about the corners (radius / cut / not given)?"
                         "No" t))
    (cond
      ((eq v 'POOL-BACK) 'POOL-BACK)
      ((not v) nil)
      (t
       ;; one answer covers the five OUTER corners (0 1 2 3 5), so it
       ;; has to hold for the SHARPEST of them -- that is the one whose
       ;; cut reaches furthest along its walls.  Budget: half the
       ;; shortest fitted wall, which with the sharpest angle on both
       ;; ends of every wall can never overrun any of them.
       (setq oang (pool:polywedge pts 0) mins nil)
       (foreach k '(1 2 3 5)
         (setq oang (min oang (pool:polywedge pts k))))
       (foreach k pool:*hexsides*
         (setq de (distance (nth (car k) pts) (nth (cadr k) pts))
               mins (if mins (min mins de) de)))
       (setq oc (pool:askcorner "the outer corners" nil nil nil
                                (* 0.5 mins) oang t))
       (if (eq oc 'POOL-BACK)
           'POOL-BACK
           (progn
             (setq octy (car oc) ocsz (cadr oc))
             ;; E is capped by what the outer cuts actually LEFT on its
             ;; two walls, at each of those corners' own angles
             (setq de (- (distance (nth 3 pts) (nth 4 pts))
                         (* ocsz (pool:cornerk octy (pool:polywedge pts 3))))
                   ef (- (distance (nth 4 pts) (nth 5 pts))
                         (* ocsz (pool:cornerk octy (pool:polywedge pts 5))))
                   icap (max 0.0 (min de ef))
                   ic (pool:askcorner "the inner corner E" octy ocsz nil
                                      icap (pool:polywedge pts 4) t))
             (if (eq ic 'POOL-BACK)
                 'POOL-BACK
                 (progn (setq icty (car ic) icsz (cadr ic)) nil)))))))

  (pool:stages (list 'hx:sides 'hx:diags 'hx:corners))
  (pool:pvkill)

  ;; pts / res / failed were fit at the top of hx:corners, so the
  ;; corner questions could be sized against the real corner angles.
  ;;
  ;; soff = every side the fit could not build to the tape.  The
  ;; in-square lazy L pushes closure error into the wing ON PURPOSE
  ;; (pool:hexsquare), so a small delta there is the design working --
  ;; but six measurements that miss each other by more than
  ;; pool:*side-tol* are a bad tape, not a fit, and saying so is the
  ;; whole point of the report.  Those sides are drawn with a red
  ;; dimension, listed red in the table, and called out underneath.
  ;; The trip point carries pool:fithexr's own 0.05 slack, so a side
  ;; the out-of-square fit legitimately flexed to the edge of its
  ;; +/-side-tol band is not reported as a bad measurement.
  (setq soff nil k 0)
  (foreach pr pool:*hexsides*
    (if (> (abs (- (distance (nth (car pr) pts) (nth (cadr pr) pts))
                   (nth k sides)))
           (+ pool:*side-tol* 0.05))
        (setq soff (cons k soff)))
    (setq k (1+ k)))
  (setq soff (reverse soff))
  (if soff
      (pool:valnote
        (strcat "SIDES DO NOT CLOSE - "
                (pool:fixnames soff pool:*hexsidenames*)
                " OFF THE TAPE, RE-MEASURE")))
  (setq notes nil
        xmin (apply 'min (mapcar 'car pts))
        xmax (apply 'max (mapcar 'car pts))
        ymin (apply 'min (mapcar 'cadr pts))
        ymax (apply 'max (mapcar 'cadr pts))
        w (- xmax xmin)
        hh (- ymax ymin)
        doff (max 12.0 (/ (max w hh) 18.0))
        th (max 3.0 (/ (max w hh) 70.0))
        pool:*dashlt* (pool:ltload "DASHED")
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen (/ 1.0 6.0)))

  ;; perimeter (layer POOL) -- mark the drawing so the whole pool can
  ;; be mirrored later if the user asks.  Corner treatments cut in
  ;; exactly like the rectangle's: sides run between the treatment
  ;; ends, an arc or chamfer face closes each corner (square corners
  ;; degenerate to the plain corner-to-corner sides).  E (index 4) is
  ;; the inner corner and carries its own treatment; the wedge math in
  ;; pool:cornerends handles the reflex angle as-is.
  (setq elast (entlast))
  (setq hcs (list (list octy ocsz) (list octy ocsz) (list octy ocsz)
                  (list octy ocsz) (list icty icsz) (list octy ocsz))
        hce (mapcar '(lambda (k)
                       (pool:cornerends (nth k pts)
                                        (nth (rem (+ k 5) 6) pts)
                                        (nth (rem (+ k 1) 6) pts)
                                        (car (nth k hcs)) (cadr (nth k hcs))
                                        nil))
                    (list 0 1 2 3 4 5)))
  (foreach pr pool:*hexsides*            ; side i: eNext(i) -> ePrev(i+1)
    (pool:line (cadr (nth (car pr) hce)) (car (nth (cadr pr) hce)) "POOL"))
  (setq hcarcs nil k 0)
  (foreach p hcs
    (cond
      ((= (car p) "Cut")
       (pool:line (car (nth k hce)) (cadr (nth k hce)) "POOL")
       (setq hcarcs (cons nil hcarcs)))
      ((= (car p) "Radius")
       (pool:arc3p (car (nth k hce)) (caddr (nth k hce)) (cadr (nth k hce))
                   "POOL")
       (setq hcarcs (cons (entlast) hcarcs)))
      (t (setq hcarcs (cons nil hcarcs))))
    (setq k (1+ k)))
  (setq hcarcs (reverse hcarcs))

  ;; dimensions (layer DIMENSION) -- side dims MEASURE to the TRUE
  ;; corners, same convention as the rectangle, but they hang off the
  ;; drawn wall rather than the hypothetical point behind a treatment
  ;; (pool:dimwall).  Per the reference
  ;; sheet, the wing/step detail sides read in SIDE STANDARD while the
  ;; principal walls (main run, far end, deep end) stay standard:
  ;; true L -> C-D, D-E, E-F secondary; lazy L -> the bends B-C, D-E
  ;; and the top E-F.
  (setvar "CLAYER" "DIMENSION")
  (setq k 0)
  (foreach pr pool:*hexsides*
    (if (member k (if lazy '(1 3 4) '(2 3 4)))
        (pool:dimwalls pts hcs (car pr) (cadr pr)
                       (pool:outoffp (nth (car pr) pts) (nth (cadr pr) pts)
                                     pts doff))
        (pool:dimwall pts hcs (car pr) (cadr pr)
                      (pool:outoffp (nth (car pr) pts) (nth (cadr pr) pts)
                                    pts doff)))
    ;; a side the tape could not close reads its BUILT length, so the
    ;; dimension goes red like any other measurement the validator had
    ;; to move
    (if (member k soff) (pool:dimred))
    (setq k (1+ k)))
  ;; corner annotations: one Typ. callout on an outer corner (B), the
  ;; inner corner E dimensioned on its own.  B carries its own fitted
  ;; angle, so a true L's square corners are marked 90 and a lazy L's
  ;; 135-degree bend is not.  E passes nil: it is the REFLEX corner,
  ;; and pool:wedge is unsigned -- 270 degrees measures back as 90, so
  ;; the mark has to be forbidden outright rather than angle-tested.
  ;; one answer covers five outer corners, so the single Typ. mark has
  ;; to sit on one that can actually carry it: B is the convention, but
  ;; a lazy L bends B 135 degrees, and marking it 90 would be a lie --
  ;; so fall through to whichever outer corner is genuinely square
  (setq ock 1)
  (if (> (abs (- (pool:polywedge pts 1) (/ pi 2.0))) pool:*sq90-tol*)
      (foreach k '(0 2 3 5)
        (if (and (= ock 1)
                 (<= (abs (- (pool:polywedge pts k) (/ pi 2.0)))
                     pool:*sq90-tol*))
            (setq ock k))))
  (pool:dimtreat1 (nth ock hce) octy (nth ock hcarcs) (nth ock pts)
                  (pool:unit (pool:v- (nth ock pts) cen)) doff " Typ."
                  (pool:polywedge pts ock))
  (pool:dimtreat1 (nth 4 hce) icty (nth 4 hcarcs) (nth 4 pts)
                  (pool:unit
                    (pool:v+ (pool:unit (pool:v- (nth 3 pts) (nth 4 pts)))
                             (pool:unit (pool:v- (nth 5 pts) (nth 4 pts)))))
                  doff "" nil)
  ;; provided cross dims, in the CROSS DIMENSIONS style when available
  (setq odim (pool:dimxbegin) k 0)
  (foreach pr pool:*hexdiags*
    (if (nth k diags)
        (pool:dimalg (nth (car pr) pts) (nth (cadr pr) pts)
                     (pool:v+ (pool:mid (nth (car pr) pts) (nth (cadr pr) pts))
                              (pool:v* (pool:unit
                                         (pool:perp
                                           (pool:v- (nth (cadr pr) pts)
                                                    (nth (car pr) pts))))
                                       (* (if (= 0 (rem k 2)) 0.15 -0.15)
                                          doff)))))
    (setq k (1+ k)))
  (pool:dimxend odim)
  (setvar "CLAYER" oldclay)

  ;; corner letters live on the mini-model beside the report, not in
  ;; the corners of the drawing itself -- see the pool:minimap call
  (setq lbls (list "A" "B" "C" "D" "E" "F"))

  ;; report table
  (setq rows nil k 0)
  (foreach pr pool:*hexsides*
    (setq rows (cons (pool:vrow (strcat "SIDE " (nth k pool:*hexsidenames*))
                                (nth k sides)
                                (distance (nth (car pr) pts)
                                          (nth (cadr pr) pts))
                                k soff)
                     rows)
          k (1+ k)))
  (if (not pool:*insq*)
      (progn
        (setq k 0)
        (foreach pr pool:*hexdiags*
          (setq rows (cons (list (strcat "CROSS " (nth k pool:*hexdiagnames*))
                                 (nth k diags)
                                 (distance (nth (car pr) pts) (nth (cadr pr) pts)))
                           rows)
                k (1+ k)))))
  (setq rows (reverse rows))
  (setq rows (append rows
                     (pool:cornerrows (list "OUTER CORNER" "INNER CORNER")
                                      (list (list octy ocsz) (list icty icsz)))))

  ;; -------- standard hopper in the main section (no sport for L).
  ;; dv = the virtual main-section corner where the break line (down
  ;; from inner corner E) meets the main-run line A-B; the hopper
  ;; anchors off the main rectangle A-dv-E-F and its left corners tie
  ;; to A and F.  A and F are REAL pool corners, so when the outer
  ;; corner treatment cuts them, the ties must land on the ends of
  ;; that cut -- exactly like the rectangle's hopper -- not on the
  ;; sharp corner behind it.  dv and E are not real treated walls in
  ;; this virtual frame (dv has no corner at all; E's real treatment
  ;; is sized for the true reflex angle against D, not against dv), so
  ;; they stay plain "Square" the way they always have.
  (if (pool:askbottom)
      (progn
        ;; per the reference: the break line drops from the inner
        ;; corner E to the bottom side, and the hopper lives in the
        ;; main section A - breakBottom - E - F
        (setq dv (pool:linex (nth 4 pts) (pool:v- (nth 5 pts) (nth 0 pts))
                             (nth 0 pts) (pool:v- (nth 1 pts) (nth 0 pts)))
              mquad (list (nth 0 pts) dv (nth 4 pts) (nth 5 pts))
              sq4 (list (list octy ocsz) (list "Square" 0.0)
                        (list "Square" 0.0) (list octy ocsz)))
        (command "_.ZOOM" "_Window"
                 (pool:wp (list (- (apply 'min (mapcar 'car mquad)) doff)
                                (- (apply 'min (mapcar 'cadr mquad)) doff)))
                 (pool:wp (list (+ (apply 'max (mapcar 'car mquad)) doff)
                                (+ (apply 'max (mapcar 'cadr mquad)) doff))))
        ;; L pools take the standard hopper only
        (setq rows (append rows
                           (pool:hopnormal mquad sq4 doff th t "Normal"
                                           (apply 'min (mapcar 'car pts))
                                           (- (apply 'min (mapcar 'cadr pts))
                                              (* 2.2 doff))
                                           t)))))

  ;; -------- all dimensions are in: offer to mirror the pool.
  ;; Top-to-bottom, so the wing swaps sides but the deep end (and its
  ;; hopper) stays on the left -- see pool:mirrory.
  (if (pool:askynf 'mirror
                   "Mirror the pool (flips the wing; deep end stays left)"
                   "No" nil)
      (progn
        (pool:mirrory elast (cadr (pool:wp (list 0.0 (* 0.5 (+ ymin ymax))))))
        ;; the mini-model must show the pool as BUILT, so its points
        ;; flip with the plan
        (setq pts (mapcar '(lambda (p) (list (car p)
                                             (- (+ ymin ymax) (cadr p))))
                          pts))
        (princ "\nPool mirrored -- the wing swapped sides, deep end still on the left.")))

  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (setq rbox (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES"))
  ;; perimeter mini-model with the corner letters, right of the report
  (setq mprims nil k 0)
  (foreach pr pool:*hexsides*
    (setq mprims (cons (list 'l (nth (car pr) pts) (nth (cadr pr) pts)) mprims)))
  (setq mlbls nil)
  (foreach p pts
    (setq mlbls (append mlbls (list (cons p (nth (length mlbls) lbls))))))
  (pool:minimap mprims pts mlbls (+ (car rbox) (* 3.0 th)) (cadr rbox)
                (* 24.0 th) th)
  (cond
    (failed
     (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***"))
    (soff
     (princ (strcat "\n*** SIDES DO NOT CLOSE -- deep end held true, the wing"
                    " carries the error, see report table ***")))
    (t (princ "\nPool layout complete -- see the report table.")))
  (princ))

;;; -------------------- report table -----------------------------------

;; Report cell: red when the row is flagged.
(defun pool:rtext (pt h str lay red)
  (if red (pool:textc pt h str lay 1) (pool:text pt h str lay)))

;; rows  = list of (label target actual [red])
;; notes = list of failure strings (written big and red)
;; TARGET / ACTUAL lengths in the crew's own units: feet-inches when
;; the drawing was in architectural or engineering units before POOL
;; switched to architectural for its prompts, plain inches otherwise.
;; (getdist keeps only the value, never the text typed, so the
;; drawing's own units are the crew's declared preference.)
(defun pool:fmtlen (v)
  (if pool:*ftin* (rtos v 4 4) (rtos v 2 2)))

;; DELTA is always plain signed inches -- a delta is a small number
;; and reads best that way whichever units the lengths are in.
(defun pool:fmtdelta (dl)
  (strcat (if (< dl 0.0) "" "+") (rtos dl 2 2)))

;; Returns the table's box as (xr ytop y0) so the caller can hang the
;; perimeter mini-model off its right edge (pool:minimap).
(defun pool:report (rows notes x y h lay / lh ytop y0 xr r tgt act c2 c3 n)
  ;; feet-inch strings run longer than decimal inches, so the TARGET/
  ;; ACTUAL/DELTA columns spread out when the report is in feet-inches
  (setq lh (* 2.2 h)
        ytop (+ y lh)
        c2 (if pool:*ftin* 33.0 29.0)
        c3 (if pool:*ftin* 46.0 38.0)
        xr (+ x (* (if pool:*ftin* 54.0 46.0) h))
        y ytop)
  (setq y (- y lh))
  (pool:text (list x y) (* 1.25 h) "POOL LAYOUT REPORT" lay)
  (setq y (- y lh))
  (pool:text (list x y) h "MEASUREMENT" lay)
  (pool:text (list (+ x (* 20.0 h)) y) h "TARGET" lay)
  (pool:text (list (+ x (* c2 h)) y) h "ACTUAL" lay)
  (pool:text (list (+ x (* c3 h)) y) h "DELTA" lay)
  ;; a 4th row element flags the row RED: the validator adjusted it
  (foreach r rows
    (setq y (- y lh)
          tgt (cadr r)
          act (caddr r))
    (pool:rtext (list x y) h (car r) lay (nth 3 r))
    (if (and tgt act)
        (progn
          (pool:rtext (list (+ x (* 20.0 h)) y) h (pool:fmtlen tgt) lay (nth 3 r))
          (pool:rtext (list (+ x (* c3 h)) y) h (pool:fmtdelta (- act tgt))
                      lay (nth 3 r)))
        ;; NA target: measurement was not taken in the field.  A row
        ;; may also carry no ACTUAL -- a NotGiven corner records that
        ;; the sheet never said, so there is nothing to compare and
        ;; nothing was built to a size
        (progn
          (pool:rtext (list (+ x (* 20.0 h)) y) h
                      (if tgt (pool:fmtlen tgt) "N/A") lay (nth 3 r))
          (pool:rtext (list (+ x (* c3 h)) y) h "-" lay (nth 3 r))))
    (pool:rtext (list (+ x (* c2 h)) y) h
                (if act (pool:fmtlen act) "N/A") lay (nth 3 r)))
  (foreach n notes
    (setq y (- y (* 1.5 lh)))
    (pool:textc (list x y) (* 1.4 h) n lay 1))
  (setq y0 (- y lh)
        ytop (+ ytop (* 0.6 lh)))
  (pool:line (list (- x h) y0) (list xr y0) lay)
  (pool:line (list xr y0) (list xr ytop) lay)
  (pool:line (list xr ytop) (list (- x h) ytop) lay)
  (pool:line (list (- x h) ytop) (list (- x h) y0) lay)
  (list xr ytop y0))

;; Map a pool-space point into the mini-model's box.  Called only from
;; pool:minimap -- sc / ox / oy / xmin / ymax are ITS locals, seen here
;; through dynamic scope (top-left anchored, y measured downward).
(defun pool:mms (p)
  (list (+ ox (* sc (- (car p) xmin)))
        (- oy (* sc (- ymax (cadr p))))))

;; The perimeter mini-model drawn beside the report: the pool outline
;; at a small fixed size with the corner LETTERS on it.  The letters
;; used to sit in the corners of the full-size drawing; they live here
;; now, so the drawing itself stays clean.
;;   prims  ('l p1 p2) line | ('a p1 pmid p2) arc as three points
;;          (uniform scaling keeps an arc an arc) | ('rb cen b a) a
;;          round/elliptical body
;;   poly   the corner ring, for keeping letters outside the outline
;;          (nil -> plain outward-from-centre offsets)
;;   lbls   ((pt . "A") ...)
;;   x y    top-left anchor (pool-report space); size = fit box
(defun pool:minimap (prims poly lbls x y size th / pts p l xmin xmax ymin ymax
                                                   sc ox oy w hh spoly cen tx
                                                   lth)
  (setq pts nil)
  (foreach p prims
    (if (eq (car p) 'rb)
        (setq pts (cons (pool:v- (cadr p) (list (* 0.5 (caddr p))
                                                (* 0.5 (cadddr p))))
                        (cons (pool:v+ (cadr p) (list (* 0.5 (caddr p))
                                                      (* 0.5 (cadddr p))))
                              pts)))
        (setq pts (append (cdr p) pts))))
  (foreach l lbls (setq pts (cons (car l) pts)))
  (if pts
      (progn
        (setq xmin (apply 'min (mapcar 'car pts))
              xmax (apply 'max (mapcar 'car pts))
              ymin (apply 'min (mapcar 'cadr pts))
              ymax (apply 'max (mapcar 'cadr pts))
              w (max 1.0e-6 (- xmax xmin))
              hh (max 1.0e-6 (- ymax ymin))
              sc (min (/ size w) (/ size hh))
              ox x oy y
              lth (* 1.4 th))
        (foreach p prims
          (cond
            ((eq (car p) 'l)
             (pool:line (pool:mms (cadr p)) (pool:mms (caddr p)) "POOL-NOTES"))
            ((eq (car p) 'a)
             (pool:arc3p (pool:mms (cadr p)) (pool:mms (caddr p))
                         (pool:mms (cadddr p)) "POOL-NOTES"))
            ((eq (car p) 'rb)
             (pool:roundbody (pool:mms (cadr p)) (* sc (caddr p))
                             (* sc (cadddr p)) "POOL-NOTES"))))
        (setq spoly (if poly (mapcar 'pool:mms poly))
              cen (list 0.0 0.0))
        (foreach l lbls (setq cen (pool:v+ cen (pool:mms (car l)))))
        (if lbls (setq cen (pool:v* cen (/ 1.0 (length lbls)))))
        (foreach l lbls
          (setq tx (pool:mms (car l)))
          (pool:text (if spoly
                         (pool:lbloff tx cen spoly (* 1.6 lth))
                         (pool:v+ tx (pool:v* (pool:unit (pool:v- tx cen))
                                              (* 1.6 lth))))
                     lth (cdr l) "POOL-NOTES"))))
  (princ))


;;; -------------------- rectangle corner treatments --------------------
;;;
;;;  A rectangle corner may be Square, Radius, Cut (a chamfer) or
;;;  NotGiven.  Side lengths are always measured to the TRUE (sharp)
;;;  corner; the treatment cuts inward from there.  The size typed is:
;;;    Radius -> the corner RADIUS
;;;    Cut    -> the CUT FACE length (the chamfer itself)
;;;  Square and NotGiven have no size: nothing was cut, and in the
;;;  NotGiven case nothing was measured either.
;;;  In-square pools assume all four corners identical; out-of-square
;;;  pools ask per corner (Enter reuses the previous corner's answer).

;; The two points where a corner's treatment meets the straight sides
;; (toward the previous / next corner) plus, for Radius, the arc mid.
;; Returns (ePrev eNext arcMid|nil).  Square -> (P P nil).
;; ctype "Ends" is the escape hatch for corners that are not a plain
;; treatment of this quad's corner (a Grecian's angled cut, say): size
;; and xtra ARE the two treatment ends, prev-side first.
;; The wedge angle the two walls at p actually make (0..pi), measured
;; from p toward its previous and next corners.  A reflex corner is
;; measured by the wedge its walls make, not the 360-minus angle --
;; which is what the treatment geometry wants either way.
(defun pool:wedge (p pp pn / u v dp)
  (setq u (pool:unit (pool:v- pp p))
        v (pool:unit (pool:v- pn p))
        dp (pool:dot u v))
  (atan (sqrt (max 0.0 (- 1.0 (* dp dp)))) dp))

;; Same, for corner i of a closed polygon.
(defun pool:polywedge (pts i / n)
  (setq n (length pts))
  (pool:wedge (nth i pts)
              (nth (rem (+ i (1- n)) n) pts)
              (nth (rem (+ i 1) n) pts)))

;; The setback budget for a treatment at corner i of a closed polygon:
;; half the shorter of its two walls, so the treatments at the two
;; ends of any wall can never overrun each other and fold it.
(defun pool:polycap (pts i / n)
  (setq n (length pts))
  (* 0.5 (min (distance (nth i pts) (nth (rem (+ i (1- n)) n) pts))
              (distance (nth i pts) (nth (rem (+ i 1) n) pts)))))

;; The tightest budget over a GROUP of corners answered together, and
;; the sharpest angle in it -- the corner whose cut reaches furthest
;; along its walls is the one the single answer has to fit.
;; Returns (cap angle).
(defun pool:groupcap (pts ks / cap ang k)
  (foreach k ks
    (setq cap (if cap (min cap (pool:polycap pts k)) (pool:polycap pts k))
          ang (if ang (min ang (pool:polywedge pts k)) (pool:polywedge pts k))))
  (list cap ang))

;; How far a corner treatment eats along EACH adjacent wall, per unit
;; of entered size, at wedge angle ang:
;;   Radius  radius r -> r / tan(ang/2)
;;   Cut     face   f -> f / (2 sin(ang/2))
;; At 90 degrees these come to 1.0 and 0.70711, which is what the old
;; fixed arithmetic assumed -- but they diverge fast away from square
;; (a 60-degree Radius corner sets back 1.73 x its radius, a
;; 135-degree one only 0.41 x), so anything sizing a treatment against
;; the wall it has to fit on must ask for the real angle.  L and Lazy
;; L pools are the ones that care: their bends are 135 degrees even
;; in-square, and out-of-square every corner drifts off 90.
(defun pool:cornerk (ctype ang / h s)
  (setq h (* 0.5 ang) s (sin h))
  (if (< s 1.0e-9)
      1.0e9                             ; degenerate: treat as unusable
      (cond ((= ctype "Radius") (/ (cos h) s))
            ((= ctype "Cut") (/ 1.0 (* 2.0 s)))
            (t 0.0))))

(defun pool:cornerends (p pp pn ctype size xtra / uprev unext ang sb bis cen)
  (setq uprev (pool:unit (pool:v- pp p))
        unext (pool:unit (pool:v- pn p))
        ang (pool:wedge p pp pn))                          ; interior angle
  (cond
    ((= ctype "Ends") (list size xtra nil))
    ((= ctype "Cut")
     (setq sb (/ size (* 2.0 (sin (/ ang 2.0)))))           ; face -> edge setback
     (list (pool:v+ p (pool:v* uprev sb))
           (pool:v+ p (pool:v* unext sb)) nil))
    ((= ctype "Radius")
     (setq sb (/ (* size (cos (/ ang 2.0))) (sin (/ ang 2.0)))  ; r/tan(ang/2)
           bis (pool:unit (pool:v+ uprev unext))
           cen (pool:v+ p (pool:v* bis (/ size (sin (/ ang 2.0))))))
     (list (pool:v+ p (pool:v* uprev sb))
           (pool:v+ p (pool:v* unext sb))
           (pool:v- cen (pool:v* bis size))))              ; arc point nearest corner
    (t (list p p nil))))

;; A reference point at corner i of quad q for a cross-dim measurement:
;;   spec = 'true (sharp corner) | 'prev | 'next (treatment ends) |
;;          'mid (chamfer/arc middle).
(defun pool:cornerpoint (q corners i spec / ce)
  (setq ce (pool:cornerends (nth i q)
                            (nth (rem (+ i 3) 4) q)
                            (nth (rem (+ i 1) 4) q)
                            (car (nth i corners)) (cadr (nth i corners))
                            (caddr (nth i corners))))
  (cond ((eq spec 'prev) (car ce))
        ((eq spec 'next) (cadr ce))
        ((eq spec 'mid) (if (caddr ce) (caddr ce) (pool:mid (car ce) (cadr ce))))
        (t (nth i q))))

;;; -------------------- dims attached to the pool ----------------------
;;;
;;; A treated corner is no longer ON the pool: round B off and the true
;;; corner sits out in space past the fillet, so a side dim taken to it
;;; hangs its extension line on that hypothetical point instead of on
;;; the drawing.  The MEASUREMENT still has to be the true
;;; corner-to-corner run -- that is what was taped, what the report
;;; lists, and what the builder sets out to -- so the fix moves the
;;; ORIGIN, not the number.
;;;
;;; A dim measures along its own direction, so what a rotated linear
;;; dim reads is the two origins' STATIONS along the wall.  Slide both
;;; origins the same distance along the wall and the number does not
;;; move at all; slide each down onto the drawn edge and the dim
;;; touches the pool.  So: find the stations each corner's treatment
;;; can be hooked at, take a station both can reach, and hook there.
;;;
;;;   station 0 -- the true corners' own -- is used whenever both ends
;;;   can reach it, which is every corner of 90 degrees or more: the
;;;   arc tangent on the adjacent wall at a square corner, a point
;;;   part-way round the arc at a 135-degree L bend, the cut face where
;;;   the corner is chamfered.  The extension lines then run through
;;;   the true corners exactly as they always did.
;;;
;;;   a corner UNDER 90 degrees pokes out past its own treatment, so
;;;   the drawn edge near it does not start until a little way up the
;;;   wall.  The other end follows it up there, and the dim still reads
;;;   the full run.  Its blunter opposite number cannot always come
;;;   quite that far, though -- the same degree off square that pushed
;;;   one station up the wall shortens the other's reach -- so the two
;;;   split what is left between them and the dim reads off by the gap.
;;;   pool:*hookslack* caps that at less than a tape can read: a pool
;;;   built a quarter-degree off square, which is what an in-square L
;;;   dumping its closure error into one bend comes to, pays a
;;;   thousandth of an inch for it.
;;;
;;; When the two ends miss each other by more than that budget -- a
;;; genuinely sharp corner, inches out -- nothing on the pool reads
;;; right, and the true corners stay the origins.  Hence "whenever
;;; possible", not always.

;; The stations along u, measured from the true corner p, that the
;; drawn treatment at p reaches: (lo hi).  An untreated corner reaches
;; only its own station, (0 0).
(defun pool:hookspan (p pp pn ctype size u / uprev unext sb a b)
  (setq uprev (pool:unit (pool:v- pp p))
        unext (pool:unit (pool:v- pn p))
        sb (* (if size size 0.0)
              (pool:cornerk ctype (pool:wedge p pp pn))))
  (if (> sb 1.0e8) (setq sb 0.0))       ; degenerate corner: no treatment
  (setq a (* sb (pool:dot uprev u))
        b (* sb (pool:dot unext u)))
  (if (< a b) (list a b) (list b a)))

;; The point on the treatment at p standing s along u from p -- where
;; the extension line at that station meets the drawn edge.  nil if the
;; treatment does not reach it (pool:hookspan is what says whether it
;; does; this only refuses what the arithmetic cannot place).
(defun pool:cornerhook (p pp pn ctype size u s / uprev unext ang h sb den t0
                                                 bis cen p0 w bw cw disc rt xa xb)
  (setq uprev (pool:unit (pool:v- pp p))
        unext (pool:unit (pool:v- pn p))
        ang (pool:wedge p pp pn)
        h (* 0.5 ang)
        sb (* (if size size 0.0) (pool:cornerk ctype ang)))
  (cond
    ((or (< (sin h) 1.0e-9) (> sb 1.0e8)) nil)
    ;; no treatment -- the true corner is the only point there is
    ((<= sb 1.0e-9) (if (< (abs s) 1.0e-9) p nil))
    ;; the cut face, from the previous wall's end across to the next
    ((= ctype "Cut")
     (setq den (* sb (- (pool:dot unext u) (pool:dot uprev u)))
           t0 (if (< (abs den) 1.0e-9)
                  nil
                  (/ (- s (* sb (pool:dot uprev u))) den)))
     (if (and t0 (> t0 -1.0e-6) (< t0 1.000001))
         (pool:v+ p (pool:v+ (pool:v* uprev (* sb (- 1.0 t0)))
                             (pool:v* unext (* sb t0))))
         nil))
    ;; the fillet arc: where the station's extension line cuts the circle
    ((= ctype "Radius")
     (setq bis (pool:unit (pool:v+ uprev unext))
           cen (pool:v+ p (pool:v* bis (/ size (sin h))))
           p0 (pool:v+ p (pool:v* u s))
           w (pool:unit (pool:perp u))
           bw (pool:dot (pool:v- cen p0) w)
           cw (- (pool:dot (pool:v- cen p0) (pool:v- cen p0)) (* size size))
           disc (- (* bw bw) cw))
     (if (< disc 0.0)
         nil
         (progn
           (setq rt (sqrt disc)
                 xa (pool:v+ p0 (pool:v* w (+ bw rt)))
                 xb (pool:v+ p0 (pool:v* w (- bw rt))))
           ;; of the two crossings only the one nearer the corner can
           ;; be on the arc -- the other is round the back of the
           ;; circle, inside the pool
           (if (> (pool:dot (pool:v- xa cen) bis) (pool:dot (pool:v- xb cen) bis))
               (setq xa xb))
           ;; ... and it is on the arc only within the treatment's own
           ;; sweep, which reaches sin(ang/2) x radius back from the
           ;; centre along the bisector
           (if (<= (pool:dot (pool:v- xa cen) bis)
                   (+ (* (- size) (sin h)) 1.0e-6))
               xa
               nil))))
    (t (if (< (abs s) 1.0e-9) p nil))))

;; The two extension-line origins for the wall between corners i and j
;; of a closed ring of TRUE corners, or nil when the two ends share no
;; station and the dim has to fall back to the corners themselves.
(defun pool:ringhooks (pts corners i j / n p q u ip in2 jp jn
                                         sp sq lo hi s hp hq)
  (setq n (length pts)
        p (nth i pts) q (nth j pts)
        u (pool:unit (pool:v- q p))
        ip (nth (rem (+ i (1- n)) n) pts) in2 (nth (rem (+ i 1) n) pts)
        jp (nth (rem (+ j (1- n)) n) pts) jn (nth (rem (+ j 1) n) pts)
        sp (pool:hookspan p ip in2
                          (car (nth i corners)) (cadr (nth i corners)) u)
        sq (pool:hookspan q jp jn
                          (car (nth j corners)) (cadr (nth j corners)) u)
        lo (max (car sp) (car sq))
        hi (min (cadr sp) (cadr sq)))
  (if (> (- lo hi) pool:*hookslack*)
      nil                               ; too far apart -- true corners
      (progn
        ;; a shared station: the true corners' own when both ends reach
        ;; it, otherwise the shared one closest to it.  When the spans
        ;; only just miss each other, each end takes the station of its
        ;; own nearest to the midpoint and the dim reads off by the
        ;; gap, which pool:*hookslack* has already capped.
        (setq s (cond ((> lo hi) (* 0.5 (+ lo hi)))
                      ((> lo 0.0) lo)
                      ((< hi 0.0) hi)
                      (t 0.0))
              hp (pool:cornerhook p ip in2
                                  (car (nth i corners)) (cadr (nth i corners))
                                  u (min (max s (car sp)) (cadr sp)))
              hq (pool:cornerhook q jp jn
                                  (car (nth j corners)) (cadr (nth j corners))
                                  u (min (max s (car sq)) (cadr sq))))
        (if (and hp hq) (list hp hq) nil))))

;; One perimeter WALL dim, hooked to the pool wherever the treatments
;; allow.  The number does not move with it: both origins stand at the
;; same station along the wall (to within pool:*hookslack*), so the
;; rotated dim reads the true corner-to-corner run.  Nothing moved ->
;; straight through pool:dimalg, so square corners keep their true
;; _H / _V linear dims.
(defun pool:dimwall (pts corners i j loc / p q hk)
  (setq p (nth i pts)
        q (nth j pts)
        hk (pool:ringhooks pts corners i j))
  (if (or (null hk)
          (and (< (distance p (car hk)) 1.0e-9)
               (< (distance q (cadr hk)) 1.0e-9)))
      (pool:dimalg p q loc)
      (pool:dimrot (car hk) (cadr hk) (angle p q) loc)))

;; The same, in the SIDE STANDARD style (the secondary sheet letters).
(defun pool:dimwalls (pts corners i j loc / od)
  (setq od (pool:dimsdbeg))
  (pool:dimwall pts corners i j loc)
  (pool:dimsdend od))

;; Draw the rectangle perimeter with corner treatments on layer POOL.
;; Returns the list of fillet-arc entity names per corner (nil where
;; the corner is square or chamfered) for the corner dimensions.
(defun pool:drawrect (q corners / ce i tyi arcs)
  (setq ce (mapcar '(lambda (i)
                      (pool:cornerends (nth i q)
                                       (nth (rem (+ i 3) 4) q)
                                       (nth (rem (+ i 1) 4) q)
                                       (car (nth i corners)) (cadr (nth i corners))
                                       (caddr (nth i corners))))
                   (list 0 1 2 3)))
  (foreach i (list 0 1 2 3)             ; straight sides (eNext(i) -> ePrev(i+1))
    (pool:line (cadr (nth i ce)) (car (nth (rem (+ i 1) 4) ce)) "POOL"))
  (setq arcs nil)
  (foreach i (list 0 1 2 3)             ; corner treatments
    (setq tyi (car (nth i corners)))
    (cond
      ((= tyi "Cut")
       (pool:line (car (nth i ce)) (cadr (nth i ce)) "POOL")
       (setq arcs (cons nil arcs)))
      ((= tyi "Radius")
       (pool:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce)) "POOL")
       (setq arcs (cons (entlast) arcs)))
      (t (setq arcs (cons nil arcs)))))
  (reverse arcs))

;; One corner-treatment annotation: a radius dim on a fillet arc or an
;; aligned dim on a cut face, dropped outward along outd, with an
;; optional " Typ." suffix.  Square corners are not this helper's job.
;; The square-corner mark of STANDARDS.md section 2: a small circle on
;; the corner point with a leader out along the corner's outward
;; diagonal.  Ported from spa:dim90 (lisp/spa/SPA.LSP), the reference
;; implementation, so the two tools' sheets match.  txt is what the
;; leader says -- "90%%d" on a square corner, "?" on a NotGiven one,
;; either with a " Typ." suffix when one mark speaks for several.
(defun pool:dim90 (p outd doff txt / r)
  (setq r (* 0.18 doff))
  (entmake (list '(0 . "CIRCLE")
                 (cons 8 "DIMENSION")
                 (cons 10 (pool:wp p))
                 (cons 40 r)))
  (command "_.LEADER" (pool:wp (pool:v+ p (pool:v* outd r)))
           (pool:wp (pool:v+ p (pool:v* outd (* 1.2 doff))))
           "" txt ""))

;; A NotGiven corner: the same circled mark, but the leader asks a
;; question instead of asserting an angle, and a note under it spells
;; the reason out.  The sheet has to SAY the treatment was never
;; recorded -- drawing a bare 90 would claim a measurement nobody took.
(defun pool:dimng (p outd doff sfx / h tp)
  (pool:dim90 p outd doff (strcat "?" sfx))
  ;; the note sits just past the leader tip, and is pulled back by its
  ;; own width when the corner points LEFT -- text runs left-to-right
  ;; from its insertion point, so an unadjusted note on a left-hand
  ;; corner would read back across its own leader and into the pool
  (setq h (* 0.25 doff)
        tp (pool:v+ p (pool:v* outd (* 1.45 doff))))
  (if (< (car outd) 0.0)
      (setq tp (list (- (car tp) (* 9.0 0.6 h)) (cadr tp))))
  (pool:text tp h "Not Given" "DIMENSION"))

;; One corner's annotation, whichever of the four treatments it
;; carries.  ang is the corner's real wedge angle, and it decides
;; whether a plain Square corner may be marked at all:
;;
;;   the "90%%d" mark ASSERTS a right angle, so it is only drawn where
;;   the corner really is one.  A grecian's corners sit at ~135 and an
;;   L's bend at 135, and stamping 90 on those would be a lie -- they
;;   stay unmarked, exactly as before.  Pass ang = nil to forbid the
;;   mark outright, which is what the L's INNER corner needs: it is
;;   reflex, and pool:wedge is unsigned, so a 270-degree corner
;;   measures back as 90 and would otherwise be marked.
;;
;;   "?" asserts nothing about the angle, so a NotGiven corner is
;;   flagged on every shape at every angle, no exceptions.
(defun pool:dimtreat1 (ce ty arc p outd doff sfx ang)
  (cond
    ((pool:cutp ty) (pool:dimcorner1 ce ty arc outd doff sfx))
    ((= ty "NotGiven") (pool:dimng p outd doff sfx))
    ((and ang (< (abs (- ang (/ pi 2.0))) pool:*sq90-tol*))
     (pool:dim90 p outd doff (strcat "90%%d" sfx)))))

(defun pool:dimcorner1 (ce ty arc outd doff sfx / am fm od)
  (cond
    ((= ty "Radius")
     (setq am (caddr ce)
           od (pool:dimsbegin (if (and arc (entget arc))
                                  (cdr (assoc 40 (entget arc)))
                                  (distance (car ce) (cadr ce)))))
     (if (= sfx "")
         (command "_.DIMRADIUS" (list arc (pool:wp am))
                  (pool:wp (pool:v+ am (pool:v* outd (* 0.9 doff)))))
         (command "_.DIMRADIUS" (list arc (pool:wp am))
                  "_T" (strcat "<>" sfx)
                  (pool:wp (pool:v+ am (pool:v* outd (* 0.9 doff))))))
     (pool:dimsend od))
    ((= ty "Cut")
     (setq fm (pool:mid (car ce) (cadr ce))
           od (pool:dimsbegin (distance (car ce) (cadr ce))))
     (if (= sfx "")
         (command "_.DIMALIGNED" (pool:wp (car ce)) (pool:wp (cadr ce))
                  (pool:wp (pool:v+ fm (pool:v* outd (* 0.5 doff)))))
         (command "_.DIMALIGNED" (pool:wp (car ce)) (pool:wp (cadr ce))
                  "_T" (strcat "<>" sfx)
                  (pool:wp (pool:v+ fm (pool:v* outd (* 0.5 doff))))))
     (pool:dimsend od))))

;; Corner annotations for the rectangle.  In-square pools get a single
;; "Typ." note at the bottom-right corner (B): the radius or cut-face
;; measurement with a Typ. suffix, or the circled 90 mark for square
;; corners.  Out-of-square pools dim every corner individually --
;; radius dim, cut-face dim, or its own circled mark.  Assumes CLAYER
;; is already DIMENSION.
(defun pool:dimcorners (quad corners arcs cen doff / ilist sfx i cc ce p pp pn
                                                    ty outd same)
  ;; out-of-square, the corners are asked one at a time -- but when
  ;; every answer came back the SAME treatment at the SAME size (Enter
  ;; reusing the previous corner, typically), one "Typ." callout reads
  ;; cleaner than four identical dims, exactly like in-square
  (setq same t)
  (foreach cc (cdr corners)
    (if (not (and (equal (car cc) (car (car corners)))
                  (equal (cadr cc) (cadr (car corners)) 1.0e-6)))
        (setq same nil)))
  (if (or pool:*insq* same)
      (setq ilist (list 1) sfx " Typ.")
      (setq ilist (list 0 1 2 3) sfx ""))
  (foreach i ilist
    (setq p (nth i quad)
          pp (nth (rem (+ i 3) 4) quad)
          pn (nth (rem (+ i 1) 4) quad)
          cc (nth i corners)
          ty (car cc)
          ce (pool:cornerends p pp pn ty (cadr cc) (caddr cc))
          outd (pool:unit (pool:v- p cen)))
    ;; a rectangle's corners are square by definition -- out of square
    ;; they drift a fraction of a degree -- so the 90 mark is earned
    ;; here and pool:dimtreat1 draws it
    (pool:dimtreat1 ce ty (nth i arcs) p outd doff sfx
                    (pool:wedge p pp pn))))

;; Corner-treatment annotations for a ring with more corners than the
;; rectangle's four.  groups = the index groups that were answered
;; TOGETHER, each ordered reference-corner first (a grecian's body
;; family and tip family in square; eight singletons out of square).
;; Whether a plain Square corner earns the circled 90 mark is decided
;; per corner from its own fitted angle inside pool:dimtreat1, so a
;; roman's true 90s are marked while a grecian's 135s are not; a
;; NotGiven corner is flagged on any shape at any angle.
;;   every corner in the ring identical -> one Typ. on the first
;;                                         group's reference corner
;;   else, per group all-same           -> one Typ. on its reference
;;   else (members differ)              -> each corner its own mark
(defun pool:dimringcorners (pts corners ces arcs cen doff groups
                            / allsame ord g i cc same ref)
  (setq ord (apply 'append groups)
        allsame t)
  (foreach i (cdr ord)
    (if (not (and (equal (car (nth i corners)) (car (nth (car ord) corners)))
                  (equal (cadr (nth i corners)) (cadr (nth (car ord) corners))
                         1.0e-6)))
        (setq allsame nil)))
  (foreach g (if allsame (list ord) groups)
    (setq same t ref (car g))
    (foreach i (cdr g)
      (if (not (and (equal (car (nth i corners)) (car (nth ref corners)))
                    (equal (cadr (nth i corners)) (cadr (nth ref corners))
                           1.0e-6)))
          (setq same nil)))
    (foreach i (if same (list ref) g)
      (setq cc (nth i corners))
      (pool:dimtreat1 (nth i ces) (car cc) (nth i arcs) (nth i pts)
                      (pool:unit (pool:v- (nth i pts) cen)) doff
                      (if (and same (> (length g) 1)) " Typ." "")
                      (pool:polywedge pts i)))))

;; Re-draw the guide rectangle's corners with the chosen treatments so
;; the visual matches what will be built.  gq = the guide quad,
;; corners = per-corner (type size), sizes already clamped for display.
;; The four full-length guide sides are replaced by shortened sides
;; plus gray chamfer lines / fillet arcs; the pv assoc side keys are
;; re-pointed at the new side entities.  Returns the updated pv.
(defun pool:pvcorners (pv gq corners / ce i k cc ent)
  (foreach k (list 'ab 'bc 'dc 'da)
    (pool:pvdel (cdr (assoc k pv))))
  (setq ce (mapcar '(lambda (i)
                      (pool:cornerends (nth i gq)
                                       (nth (rem (+ i 3) 4) gq)
                                       (nth (rem (+ i 1) 4) gq)
                                       (car (nth i corners)) (cadr (nth i corners))
                                       (caddr (nth i corners))))
                   (list 0 1 2 3)))
  ;; shortened straight sides (side i runs corner i -> corner i+1)
  (setq i 0)
  (foreach k (list 'ab 'bc 'dc 'da)
    (setq ent (pool:pvadd (pool:pvline (cadr (nth i ce))
                                       (car (nth (rem (+ i 1) 4) ce))))
          pv (subst (cons k (list ent)) (assoc k pv) pv)
          i (1+ i)))
  ;; the corner treatments themselves
  (setq i 0)
  (foreach cc corners
    (cond
      ((= (car cc) "Cut")
       (pool:pvadd (pool:pvline (car (nth i ce)) (cadr (nth i ce)))))
      ((= (car cc) "Radius")
       (pool:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce))
                   "POOL-NOTES")
       (pool:pvadd (pool:setcol (entlast) pool:*pv-col*))))
    (setq i (1+ i)))
  pv)

;; Prompt one corner's treatment (Enter reuses prevty/prevsz).
;; maxsb caps the treatment's setback along the walls at half the
;; shorter adjacent wall, so two treatments can never overlap and fold
;; the perimeter; too-large answers are re-asked.
;; ang = the wedge angle to size this answer against (the SHARPEST of
;; them when one answer covers several corners, since that is the one
;; that eats furthest into its walls).  nil means "assume square",
;; which is right for the rectangle: it asks its corners before the
;; cross dims, so its true angles are not known yet -- and a pool
;; still called a rectangle is within a degree of 90 anyway.
(defun pool:askcorner (subject prevty prevsz ents maxsb ang back
                       / ty sz cols sb wed dflt szmsg nofit fk fty fsz)
  ;; A form can answer this corner: <stem>-ty carries the treatment,
  ;; <stem>-sz the radius or cut face.  Both are consumed NOW, valid or
  ;; not -- consume-once is what keeps Back from deadlocking, and what
  ;; lets a rejected size be retyped at the keyboard instead of re-fed.
  ;; An answer the question would not accept falls through to the
  ;; prompt exactly as if the box had been left empty.
  (if (setq fk (pool:fckey subject))
      (progn
        (if (pool:fhas (read (strcat fk "-ty")))
            (progn
              (setq fty (pool:ftake (read (strcat fk "-ty"))))
              (if (not (member fty '("Square" "Radius" "Cut" "NotGiven")))
                  (setq fty nil))))
        (if (pool:fhas (read (strcat fk "-sz")))
            (progn
              (setq fsz (pool:ftake (read (strcat fk "-sz"))))
              (if (not (and (numberp fsz) (> fsz 0.0)))
                  (setq fsz nil))))))
  ;; A corner whose walls leave no room for a cut cannot be given one:
  ;; every size would be rejected and re-asked forever.  That is a fact
  ;; about the GEOMETRY, though, and it must not answer the question
  ;; the sheet asks -- "nobody wrote this corner down" is still a
  ;; truthful answer here.  So the two sized options are withheld and
  ;; the question is still put.
  (if (and maxsb (< maxsb 0.125))
      (progn
        (princ (strcat "\nNo room for a cut on " subject
                       " -- Radius and Cut are not offered."))
        (setq maxsb nil nofit t)
        ;; the geometry outranks the form: a sized treatment cannot fit
        ;; here whoever supplied it, so the question is put after all
        (if (pool:cutp fty) (setq fty nil))))
  (progn
  (setq cols (mapcar 'pool:getcol ents))
  (foreach e ents (pool:setcol e pool:*hi-col*))
  (pool:osup)
  (setq ty (cond
             (fty fty)
             (nofit
              ;; a remembered Radius/Cut is not among the offered
              ;; words, and pool:askkw hands a default straight back
              ;; on Enter without checking it -- so drop it
              (pool:asktreatng subject
                               (if (member prevty '("Square" "NotGiven"))
                                   prevty nil)
                               back))
             (t (pool:asktreat subject prevty back))))
  (pool:osdown)
  (if (eq ty 'POOL-BACK)
      (progn (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
             (setq ty nil)))
  (if (null ty)
      (progn (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
             (setq sz nil)))
  (if (null ty)
      nil
  ;; Square has no size, and NotGiven has none either -- nothing was
  ;; measured, so there is no number to ask for
  (if (not (pool:cutp ty))
      (setq sz 0.0)
      (progn
        ;; the remembered size is only offered back when the answer
        ;; MATCHES the one it was measured for: a radius is not a cut
        ;; face, so carrying 24" across from one to the other would be
        ;; a wrong default, not a convenient one
        (setq dflt (if (and prevsz (> prevsz 0.0) (= ty prevty)) prevsz nil)
              szmsg (strcat "\n" (if (= ty "Radius") "Radius for "
                                     "Cut face length for ")
                            subject))
        (pool:osup)
        (if fsz
            ;; the form's size skips the prompt but NOT the cap check
            ;; below: one that will not fit is rejected there and
            ;; retyped at the keyboard, the store already being empty
            (setq sz fsz)
            (progn
              (initget (if dflt 6 7))
              (setq sz (getdist (strcat szmsg
                                        (if dflt (strcat " <" (rtos dflt) ">")
                                            "")
                                        ": ")))
              (if (null sz) (setq sz dflt))))
        ;; how far this treatment eats along each wall, at the real
        ;; corner angle -- so the cap holds on a 135-degree bend or a
        ;; skewed out-of-square corner, not just on a square one
        (setq wed (if ang ang (/ pi 2.0)))
        (while (and maxsb
                    (> (setq sb (* sz (pool:cornerk ty wed))) maxsb))
          (princ (strcat "\nToo large for this corner's walls -- max "
                         (rtos (/ maxsb (pool:cornerk ty wed)))
                         ".  Re-enter."))
          (initget 7)
          (setq sz (getdist (strcat szmsg ": "))))
        (pool:osdown))))
  (mapcar '(lambda (e c) (pool:setcol e c)) ents cols)
  (if ty (list ty sz) 'POOL-BACK)))

;; Ask one treatment per corner, in order, Enter reusing the previous
;; corner's answer -- the out-of-square pattern.  labels / caps / angs
;; / entl run parallel: the prompt text, the setback budget, the real
;; wedge angle to size the budget against, and the guide entities to
;; light up while that corner is being asked.
;; Back inside the loop steps to the PREVIOUS corner and re-asks it;
;; Back on the first corner returns POOL-BACK for the stage to hand on.
;; Returns a list of (type size), or POOL-BACK.
(defun pool:askcorners (labels caps angs entl / i n out prevty prevsz cc back)
  (setq i 0 n (length labels) out nil back nil)
  (while (and (< i n) (not back))
    (setq cc (pool:askcorner (nth i labels) prevty prevsz (nth i entl)
                             (nth i caps) (nth i angs) t))
    (if (eq cc 'POOL-BACK)
        (if (= i 0)
            (setq back t)               ; back out of the whole stage
            (setq i (1- i)
                  out (cdr out)
                  ;; the reuse default is the corner BEFORE the one
                  ;; being re-asked
                  prevty (if out (car (car out)) nil)
                  prevsz (if out (cadr (car out)) nil)))
        (setq prevty (car cc) prevsz (cadr cc)
              out (cons cc out)
              i (1+ i))))
  (if back 'POOL-BACK (reverse out)))

;; Treatment ends for every corner of a closed ring of points, in ring
;; order -- pool:cornerends applied all the way round.
(defun pool:ringends (pts corners / n i out)
  (setq n (length pts) i 0)
  (while (< i n)
    (setq out (cons (pool:cornerends (nth i pts)
                                     (nth (rem (+ i (1- n)) n) pts)
                                     (nth (rem (+ i 1) n) pts)
                                     (car (nth i corners)) (cadr (nth i corners))
                                     (caddr (nth i corners)))
                    out)
          i (1+ i)))
  (reverse out))

;; Draw the corner treatments themselves -- chamfer faces and fillet
;; arcs -- for a ring whose straight walls the caller has already
;; drawn between the treatment ends.  Returns the fillet-arc entity
;; per corner (nil where the corner is square or chamfered), which is
;; what the radius dims measure.
(defun pool:ringarcs (ce corners lay / out k cc)
  (setq k 0 out nil)
  (foreach cc corners
    (cond
      ((= (car cc) "Cut")
       (pool:line (car (nth k ce)) (cadr (nth k ce)) lay)
       (setq out (cons nil out)))
      ((= (car cc) "Radius")
       (pool:arc3p (car (nth k ce)) (caddr (nth k ce)) (cadr (nth k ce)) lay)
       (setq out (cons (entlast) out)))
      (t (setq out (cons nil out))))
    (setq k (1+ k)))
  (reverse out))

;; Report rows for a set of corner treatments: one row per corner that
;; is not Square, labelled "<label> RAD" or "<label> FACE".  labels
;; and corners run parallel.
(defun pool:cornerrows (labels corners / out k cc)
  (setq k 0 out nil)
  (foreach cc corners
    (cond
      ((pool:cutp (car cc))
       (setq out (cons (list (strcat (nth k labels)
                                     (if (= (car cc) "Radius") " RAD" " FACE"))
                             (cadr cc) (cadr cc))
                       out)))
      ;; nothing was measured, so both columns read N/A -- the row
      ;; exists to record that the sheet never said
      ((= (car cc) "NotGiven")
       (setq out (cons (list (strcat (nth k labels) " NotGiven") nil nil)
                       out))))
    (setq k (1+ k)))
  (reverse out))

;; Cross-dim measurement templates for the chosen reference mode.
;; Each entry: (diagkey prompt rowlabel iA specA iC specC).  Ends uses
;; both endpoints on each side of the diagonal.
(defun pool:crosstemplate (cmode)
  (cond
    ((= cmode "Middle")
     (list (list 'ac "Cross dim A-C (to corner middles)" "AC MID" 0 'mid 2 'mid)
           (list 'bd "Cross dim B-D (to corner middles)" "BD MID" 1 'mid 3 'mid)))
    ;; The two ties of a diagonal CROSS each other, the way the tape
    ;; actually runs: each starts at one end of a corner treatment and
    ;; finishes at the OPPOSITE end of the far treatment.  Pairing the
    ;; same side at both corners would give two near-parallel ties,
    ;; which pin the out-of-squareness down far less.
    ((= cmode "Ends")
     (list (list 'ac "Cross A-C (A>B end to C>D end)" "AC B-D" 0 'next 2 'next)
           (list 'ac "Cross A-C (A>D end to C>B end)" "AC D-B" 0 'prev 2 'prev)
           (list 'bd "Cross B-D (B>A end to D>C end)" "BD A-C" 1 'prev 3 'prev)
           (list 'bd "Cross B-D (B>C end to D>A end)" "BD C-A" 1 'next 3 'next)))
    (t
     (list (list 'ac "Cross dim bottom-left to top-right (A-C)" "CROSS A-C" 0 'true 2 'true)
           (list 'bd "Cross dim bottom-right to top-left (B-D)" "CROSS B-D" 1 'true 3 'true)))))

;; Average of a diagonal's raw measurements (bootstrap), or the
;; corner-corrected effective true-corner target using estimate q.
(defun pool:rawavg (xmeas diagkey / sum n)
  (setq sum 0.0 n 0)
  (foreach m xmeas
    (if (and (eq (car m) diagkey) (nth 7 m))
        (setq sum (+ sum (nth 7 m)) n (1+ n))))
  (if (> n 0) (/ sum n) nil))

(defun pool:effcross (q corners xmeas diagkey / sum n ra rc)
  (setq sum 0.0 n 0)
  (foreach m xmeas
    (if (and (eq (car m) diagkey) (nth 7 m))
        (progn
          (setq ra (pool:cornerpoint q corners (nth 3 m) (nth 4 m))
                rc (pool:cornerpoint q corners (nth 5 m) (nth 6 m))
                sum (+ sum (+ (nth 7 m)
                              (- (distance (nth (nth 3 m) q) (nth (nth 5 m) q))
                                 (distance ra rc))))
                n (1+ n)))))
  (if (> n 0) (/ sum n) nil))

;;; -------------------- pool bottom / hopper (rectangle) ---------------
;;;
;;;  Field-sheet letters (plan view):
;;;
;;;      D ------------------------------------ C
;;;      |\        M                           /|
;;;      | htl --------- htr                 /  |
;;;      |  |   hopper    |  \            brkt  |
;;;      |H |G    (G x L) |     \           |   |
;;;      | hbl --------- hbr       \        | E |
;;;      |/        K          \       \   brkb  |
;;;      A ------------------------------------ B
;;;
;;;  H = left end -> hopper, G = hopper length, F = hopper -> slope
;;;  break (CHECK), E = slope break -> right end, M = top -> hopper,
;;;  L = hopper width (CHECK), K = hopper -> bottom.  The primary dims
;;;  are perimeter OFFSETS (H, E, M, K) plus the hopper size G; F and
;;;  L are redundant and reported as checks with their deltas.
;;;  The hopper's left corners tie to the pool's left corners -- to the
;;;  end-wall end of the corner treatment when that corner is cut or
;;;  rounded -- and its right corners tie to the slope-break ends.

;; Intersection of two infinite lines (p1 along d1, p2 along d2).
(defun pool:linex (p1 d1 p2 d2 / den s)
  (setq den (- (* (car d1) (cadr d2)) (* (cadr d1) (car d2))))
  (if (> (abs den) 1.0e-9)
      (progn
        (setq s (/ (- (* (- (car p2) (car p1)) (cadr d2))
                      (* (- (cadr p2) (cadr p1)) (car d2)))
                   den))
        (pool:v+ p1 (pool:v* d1 s)))
      ;; parallel lines never truly happen on sane input; a degenerate
      ;; fit must not crash a caller with nil, so fall back to the
      ;; midpoint of the two anchor points
      (pool:mid p1 p2)))

;; The side p->q offset inward (toward cen) by dist, as (point dir).
(defun pool:offline (p q cen dist / n)
  (setq n (pool:unit (pool:perp (pool:v- q p))))
  (if (> (pool:dot (pool:v- (pool:mid p q) cen) n) 0.0)
      (setq n (pool:v* n -1.0)))
  (list (pool:v+ p (pool:v* n dist)) (pool:v- q p)))

;; All hopper geometry for quad + corner treatments + the primary
;; offsets.  Returns an assoc list of named points: hopper corners
;; (hbl htl hbr htr), slope-break ends (brkb brkt), left tie anchors
;; (lab lat), and the measuring-chain points -- horizontal pl phl phr
;; pbrk pr, vertical pb phb pht pt (through the hopper centre).
(defun pool:hopcalc (quad corners h g e m k / a b c d cen hl hr ht hb brk
                                              hbl htl hbr htr brkb brkt
                                              lab1 lab2 lat1 lat2
                                              rab1 rab2 rat1 rat2
                                              hc hdir vdir hc2)
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        hl (pool:offline a d cen h)
        hr (pool:offline a d cen (+ h g))
        ht (pool:offline d c cen m)
        hb (pool:offline a b cen k)
        brk (pool:offline b c cen e)
        hbl (pool:linex (car hl) (cadr hl) (car hb) (cadr hb))
        htl (pool:linex (car hl) (cadr hl) (car ht) (cadr ht))
        hbr (pool:linex (car hr) (cadr hr) (car hb) (cadr hb))
        htr (pool:linex (car hr) (cadr hr) (car ht) (cadr ht))
        brkb (pool:linex (car brk) (cadr brk) a (pool:v- b a))
        brkt (pool:linex (car brk) (cadr brk) d (pool:v- c d))
        ;; both ends of each left corner treatment (Square -> both ends
        ;; coincide with the true corner)
        lab1 (pool:cornerpoint quad corners 0 'prev)
        lab2 (pool:cornerpoint quad corners 0 'next)
        lat1 (pool:cornerpoint quad corners 3 'next)
        lat2 (pool:cornerpoint quad corners 3 'prev)
        ;; and the same for the right corners, used when E = 0 puts the
        ;; slope break on the end wall: the floor breaks to the ends of
        ;; the corner treatment, not to the sharp corner behind it
        rab1 (pool:cornerpoint quad corners 1 'prev)
        rab2 (pool:cornerpoint quad corners 1 'next)
        rat1 (pool:cornerpoint quad corners 2 'next)
        rat2 (pool:cornerpoint quad corners 2 'prev)
        hc (pool:v* (pool:v+ (pool:v+ hbl htl) (pool:v+ hbr htr)) 0.25)
        hdir (pool:v- b a)
        vdir (pool:v- d a)
        ;; H/G/F/E chain sits below the hopper centre by 12" or L/6
        ;; (2/3 down from the top of L), whichever is closer; the
        ;; M/L/K chain sits 12" right of the hopper's right edge
        hc2 (pool:v- hc (pool:v* (pool:unit vdir)
                                 (min 12.0 (/ (distance hbr htr) 6.0)))))
  (list (list 'hbl hbl) (list 'htl htl) (list 'hbr hbr) (list 'htr htr)
        (list 'brkb brkb) (list 'brkt brkt)
        (list 'lab1 lab1) (list 'lab2 lab2)
        (list 'lat1 lat1) (list 'lat2 lat2)
        (list 'rab1 rab1) (list 'rab2 rab2)
        (list 'rat1 rat1) (list 'rat2 rat2)
        (list 'pl (pool:linex hc2 hdir a (pool:v- d a)))
        (list 'phl (pool:linex hc2 hdir (car hl) (cadr hl)))
        (list 'phr (pool:linex hc2 hdir (car hr) (cadr hr)))
        (list 'pbrk (pool:linex hc2 hdir (car brk) (cadr brk)))
        (list 'pr (pool:linex hc2 hdir b (pool:v- c b)))
        ;; M/L/K attach to the hopper's right edge itself; the dim
        ;; line floats 12" further right via 'voff
        (list 'pb (pool:linex (car hr) (cadr hr) a (pool:v- b a)))
        (list 'phb hbr)
        (list 'pht htr)
        (list 'pt (pool:linex (car hr) (cadr hr) d (pool:v- c d)))
        (list 'voff (pool:v* (pool:unit hdir) pool:*mlkoff*))
        ;; G = 0 collapses the pad to a single deep line; E = 0 puts the
        ;; slope break on the end wall, which is already drawn
        (list 'zg (< g 1.0e-6))
        (list 'ze (< e 1.0e-6))))

;; Draw the hopper, slope break and corner ties on layer lay.  Each
;; hopper left corner ties to BOTH ends of its pool corner treatment
;; (one line when the corner is square and the ends coincide).
;; tie = draw the left corner ties (off for shapes whose "left end" is
;; an arc rather than a pair of corners).
(defun pool:hopdraw (gg lay tie / hbl htl hbr htr brkb brkt lab1 lab2 lat1 lat2
                                  rab1 rab2 rat1 rat2)
  (setq hbl (cadr (assoc 'hbl gg)) htl (cadr (assoc 'htl gg))
        hbr (cadr (assoc 'hbr gg)) htr (cadr (assoc 'htr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg))
        lab1 (cadr (assoc 'lab1 gg)) lab2 (cadr (assoc 'lab2 gg))
        lat1 (cadr (assoc 'lat1 gg)) lat2 (cadr (assoc 'lat2 gg))
        rab1 (cadr (assoc 'rab1 gg)) rab2 (cadr (assoc 'rab2 gg))
        rat1 (cadr (assoc 'rat1 gg)) rat2 (cadr (assoc 'rat2 gg)))
  (pool:line hbl htl lay)               ; deep-end line (the whole pad when G=0)
  (if (not (cadr (assoc 'zg gg)))
      (progn
        (pool:line htl htr lay)
        (pool:line htr hbr lay)
        (pool:line hbr hbl lay)))
  (if tie
      (progn
        (pool:line lab1 hbl lay)
        (if (> (distance lab1 lab2) 1.0e-6) (pool:line lab2 hbl lay))
        (pool:line lat1 htl lay)
        (if (> (distance lat1 lat2) 1.0e-6) (pool:line lat2 htl lay))))
  (if (and (cadr (assoc 'ze gg)) tie)
      ;; E = 0: the break IS the end wall, so the floor breaks to BOTH
      ;; ends of each right corner treatment -- the same rule the left
      ;; corners follow -- rather than to the sharp corner behind it
      (progn
        (pool:line rab1 hbr lay)
        (if (> (distance rab1 rab2) 1.0e-6) (pool:line rab2 hbr lay))
        (pool:line rat1 htr lay)
        (if (> (distance rat1 rat2) 1.0e-6) (pool:line rat2 htr lay)))
      (progn
        (if (not (cadr (assoc 'ze gg))) (pool:line brkb brkt lay))
        (pool:line htr brkt lay)
        (pool:line hbr brkb lay))))

;;; -------------------- bottom styles ----------------------------------
;;;
;;;  Every one of these is the standard hopper's plan language -- the
;;;  same H/G/F/E/M/L/K chain, deep-end line, slope break and corner
;;;  ties -- with G and/or E pinned to zero, plus the side profile the
;;;  style implies (per the reference drawing):
;;;
;;;    Normal     full hopper, plan only.  A G of 0 turns it into a
;;;               Slope bottom and the profile appears automatically.
;;;    Wedge      G=0, E=0: a deep line at H, floor rising all the way
;;;               to the far wall.
;;;    SLope      G=0: a deep line at H, floor rising to a full-width
;;;               break, then flat to the far wall.
;;;    MOdflat    E=0: one flat pad inset H / G / F, sloping up to the
;;;               walls all round, no shallow flat.
;;;    SHallow    full hopper whose shallow floor is not flat -- it
;;;               slopes from C2 at the break up to C at the wall.

;; Per style: (ask-G ask-E has-profile ask-C2 slack-index).  The slack
;; member absorbs any mismatch when the whole chain was given: G where
;; there is a pad, F where the deep end is a line.
(defun pool:btmspec (style)
  (cond
    ((= style "Wedge")   (list nil nil t   nil 2))
    ((= style "SLope")   (list nil t   t   nil 2))
    ((= style "MOdflat") (list t   nil t   nil 1))
    ((= style "SHallow") (list t   t   t   t   1))
    (t                   (list t   t   nil nil 1))))

;; Nominal guide proportions (h g e) for the style's preview.
(defun pool:btmnom (style len)
  (cond
    ((= style "Wedge")   (list (* 0.12 len) 0.0 0.0))
    ((= style "SLope")   (list (* 0.12 len) 0.0 (* 0.30 len)))
    ((= style "MOdflat") (list (* 0.10 len) (* 0.70 len) 0.0))
    (t                   (list (* 0.12 len) (* 0.20 len) (* 0.40 len)))))

;; Bottom vertices ((run . depth) ...) between the two wall bottoms,
;; left (deep end) to right.  wh = wall height, dp = deep depth,
;; c2 = depth where the shallow floor meets the slope break.
(defun pool:btmbrks (style h g f wh dp c2)
  (cond
    ((= style "Wedge")   (list (cons h dp)))
    ((= style "MOdflat") (list (cons h dp) (cons (+ h g) dp)))
    ((= style "SHallow") (list (cons h dp) (cons (+ h g) dp)
                               (cons (+ h g f) c2)))
    ;; SLope, and a Normal hopper whose G came out at 0
    (t                   (list (cons h dp) (cons (+ h g f) wh)))))

;; Letters the style prompts for, in order, with their chain points.
(defun pool:btmties (style / sp)
  (setq sp (pool:btmspec style))
  (append (list (list "H" 'pl 'phl))
          (if (car sp) (list (list "G" 'phl 'phr)) nil)
          (list (list "F" 'phr 'pbrk))
          (if (cadr sp) (list (list "E" 'pbrk 'pr)) nil)
          (list (list "M" 'pht 'pt) (list "L" 'phb 'pht)
                (list "K" 'pb 'phb))))

;; The field-sheet guide inside the fitted pool is LIVE: hn:geo inside
;; pool:hopnormal builds it through the collector (see "live guide
;; reshaping"), so the hopper, its ties and the nominal section all
;; reshape as the letters and depths come in.

;; Resolve a bottom measurement chain against the pool total:
;;   * NA (nil) entries take the remainder -- split evenly when there
;;     is more than one
;;   * when every value is provided but the sum misses the total, the
;;     slack member at index islack (G on the horizontal chain, L on
;;     the vertical) absorbs the difference; islack -1 = nobody (the
;;     caller handles the residual itself)
;; Returns the resolved list.
(defun pool:chainfix (vals total islack / sum n share out k v)
  (setq sum 0.0 n 0)
  (foreach v vals (if v (setq sum (+ sum v)) (setq n (1+ n))))
  (setq out nil k 0)
  (if (> n 0)
      (progn
        (setq share (/ (- total sum) n))
        (foreach v vals (setq out (cons (if v v share) out))))
      (foreach v vals
        (setq out (cons (if (and (= k islack)
                                 (> (abs (- sum total)) 1.0e-6))
                            (+ v (- total sum))
                            v)
                        out)
              k (1+ k))))
  (reverse out))

;; Post-check a resolved chain: no member may be negative.  A member
;; that resolved below zero is lifted to a positive floor (12", or a
;; share of the total on a small pool) and the deficit comes out of
;; the LARGEST other member -- e.g. a G that went negative is drawn
;; 1' long and F gives up the difference.  Returns (vals fixed):
;; fixed holds the index of every member changed (the lifted one AND
;; its donor) so the caller can flag their dims and report rows red.
(defun pool:chainval (vals total / out fixed n i j v flo need big bigi w)
  (setq n (length vals)
        flo (min 12.0 (/ (abs total) (* 4.0 n)))
        out vals fixed nil i 0)
  (while (< i n)
    (setq v (nth i out))
    (if (< v -1.0e-6)
        (progn
          (setq need (- flo v) big -1.0e30 bigi nil j 0)
          (foreach w out
            (if (and (/= j i) (> w big)) (setq big w bigi j))
            (setq j (1+ j)))
          (setq out (pool:setnth (pool:setnth out i flo) bigi (- big need))
                fixed (append fixed (list i bigi)))))
    (setq i (1+ i)))
  (list out fixed))

;; Record a validation problem: an immediate command-line warning now,
;; and a red note under the report table later.
(defun pool:valnote (msg)
  (setq pool:*valnotes* (append pool:*valnotes* (list msg)))
  (princ (strcat "\n*** " msg " ***"))
  (princ))

;; The adjusted letters as "G/F" for a note.
(defun pool:fixnames (fixed labels / out i)
  (setq out "")
  (foreach i fixed
    (setq out (strcat out (if (= out "") "" "/") (nth i labels))))
  out)

;; Color the just-drawn dimension red (a measurement the validator had
;; to adjust).
(defun pool:dimred ( / e ed)
  (setq e (entlast))
  (if (and e (setq ed (entget e)))
      (entmod (if (assoc 62 ed)
                  (subst (cons 62 1) (assoc 62 ed) ed)
                  (append ed (list (cons 62 1)))))))

;; Report row, red-flagged when index i is among the adjusted ones.
(defun pool:vrow (label tgt act i fixed)
  (append (list label tgt act) (if (member i fixed) (list t) nil)))

;; Deep depth must beat the wall height; C2 must land between them.
(defun pool:askdeep (msg ents wh / dp)
  (setq dp (pool:askh msg ents))
  (while (<= dp wh)
    (princ (strcat "\nD must be deeper than the wall height C ("
                   (rtos wh) ") -- re-enter."))
    (setq dp (pool:askh msg ents)))
  dp)

(defun pool:askc2 (msg ents wh dp / c2)
  (setq c2 (pool:askh msg ents))
  (while (or (< c2 wh) (> c2 dp))
    (princ (strcat "\nC2 must be between C (" (rtos wh) ") and D ("
                   (rtos dp) ") -- re-enter."))
    (setq c2 (pool:askh msg ents)))
  c2)

;; Hopper-language bottom: lettered guide, the H/G/F/E/M/L/K chain,
;; plan hopper + chain dims, and -- for every style but Normal -- the
;; side profile below with its depth dims.
;; style = Normal / Wedge / SLope / MOdflat / SHallow (see above);
;; x0/y0 place the side profile below the pool; tie draws the left
;; corner ties.
(defun pool:hopnormal (quad corners doff th lmode style x0 y0 tie
                       / pv h g f e m l k gg tl odl sp
                         hraw graw fraw eraw mraw lraw kraw wh dp c2
                         a b c d cen toth totv hres vres skipe rows
                         cv hfx vfx ans lmode2 toth2 totv2)
  (setq sp (pool:btmspec style))
  ;; wall-to-wall totals through the pool centre: B1 along the run,
  ;; V1 across it
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        toth (distance (pool:linex cen (pool:v- b a) a (pool:v- d a))
                       (pool:linex cen (pool:v- b a) b (pool:v- c b)))
        totv (distance (pool:linex cen (pool:v- d a) a (pool:v- b a))
                       (pool:linex cen (pool:v- d a) d (pool:v- c d))))
  ;; The live guide geometry (see "live guide reshaping"): the chain
  ;; letters answered so far are held and the open ones share what the
  ;; two totals have left (pool:pvchain), so the hopper on screen
  ;; closes against the pool at every answer -- and, on the profile
  ;; styles, the section under the plan reshapes the same way as the
  ;; depths come in.
  (defun hn:geo ( / len nom res hv gv fv ev mv kv gg pr tl wh2 dp2 c22 fb)
    (setq len (distance (car quad) (cadr quad))
          nom (pool:btmnom style len)
          res (pool:pvchain
                (list (pool:pvdim 'h)
                      (if (car sp) (pool:pvdim 'g) 0.0)
                      (pool:pvdim 'f)
                      (if (cadr sp) (pool:pvdim 'e) 0.0))
                (list (car nom) (cadr nom)
                      (max 1.0 (- len (car nom) (cadr nom) (caddr nom)))
                      (caddr nom))
                toth)
          hv (car res) gv (cadr res) fv (caddr res) ev (cadddr res)
          res (pool:pvchain
                (list (pool:pvdim 'm) (pool:pvdim 'l) (pool:pvdim 'k))
                (list (* 0.25 totv) (* 0.5 totv) (* 0.25 totv))
                totv)
          mv (car res) kv (caddr res)
          gg (pool:hopcalc quad corners hv gv ev mv kv))
    (pool:pvcopen)
    ;; the outline, with the structure the STYLE fixes -- a pad or a
    ;; break that shrinks to nothing simply collapses in place
    (foreach pr (append (list (list 'hbl 'htl))
                        (if (car sp)
                            (list (list 'htl 'htr) (list 'htr 'hbr)
                                  (list 'hbr 'hbl))
                            nil)
                        (if (cadr sp) (list (list 'brkb 'brkt)) nil)
                        (if tie
                            (list (list 'lab1 'hbl) (list 'lab2 'hbl)
                                  (list 'lat1 'htl) (list 'lat2 'htl))
                            nil)
                        ;; a style with E pinned to 0 breaks to the
                        ;; right corner treatments instead
                        (if (and (not (cadr sp)) tie)
                            (list (list 'rab1 'hbr) (list 'rab2 'hbr)
                                  (list 'rat1 'htr) (list 'rat2 'htr))
                            (list (list 'htr 'brkt) (list 'hbr 'brkb))))
      (pool:pvcput (list "LINE" (cadr (assoc (car pr) gg))
                         (cadr (assoc (cadr pr) gg)))))
    (foreach tl (pool:btmties style)
      (pool:pvctie (cadr (assoc (cadr tl) gg))
                   (cadr (assoc (caddr tl) gg))
                   (car tl) th))
    ;; the profile styles get a section under the plan, so the depth
    ;; prompts highlight a tie the same way the plan letters do
    (if (caddr sp)
        (progn
          (setq wh2 (cond ((pool:pvdim 'wh)) ((* 0.25 totv)))
                dp2 (cond ((pool:pvdim 'dp)) ((* 0.55 totv)))
                ;; a deep C with D still open must not float the floor
                ;; above the wall bottoms while D is being asked
                dp2 (max dp2 (* 1.15 wh2))
                c22 (cond ((pool:pvdim 'c2)) ((* 0.5 (+ wh2 dp2))))
                fb (max 0.0 (- toth hv gv ev)))
          (pool:profdraw x0 y0 toth wh2
                         (pool:btmbrks style hv gv fb wh2 dp2 c22)
                         "POOL-NOTES" t)
          (pool:pvctie (list (+ x0 toth (* 0.6 doff)) y0)
                       (list (+ x0 toth (* 0.6 doff)) (- y0 wh2)) "C" th)
          (pool:pvctie (list (+ x0 hv) y0)
                       (list (+ x0 hv) (- y0 dp2)) "D" th)
          (if (cadddr sp)
              (pool:pvctie (list (+ x0 hv gv fb) y0)
                           (list (+ x0 hv gv fb) (- y0 c22)) "C2" th))))
    (pool:pvcout quad))
  (setq pv (pool:pvlive 'hn:geo))
  (princ "\nPool bottom -- offsets from the perimeter; the RED tie is the one being asked for.")
  (princ "\n(after the first answer, Back re-asks the previous one)")
  ;; L pools: when H+G+F are all given and already span the main
  ;; section (B1), the break lands on the inner corner and E is moot.
  ;;
  ;; Suggestions, all taken with Enter and all still typeable over:
  ;;   * H, M and K are usually the same offset, so M suggests H;
  ;;   * the LAST member of either chain is arithmetic once the rest
  ;;     are in -- E is what B1 has left of H+G+F, K what A has left
  ;;     of M+L -- so it is offered rather than asked for cold;
  ;;   * M answered the same as H says the deep end sits square in the
  ;;     pool, which fixes L at A - 2M (pool:sugsym).
  ;; Between them a squarely-set hopper is four Enters.
  (setq lmode2 lmode toth2 toth totv2 totv
        ans (pool:askseq
              (append
                (list (list 'h 'NAX "H - left end to deep end" (cdr (assoc "H" pv))))
                (if (car sp)
                    (list (list 'g 'ZER (if (= style "MOdflat")
                                            "G - flat pad length"
                                            "G - hopper length, 0 = slope bottom")
                                (cdr (assoc "G" pv))))
                    (list (list 'g 'NAX "G" nil nil ''t)))
                (list (list 'f 'NAX (if (= style "MOdflat")
                                        "F - pad to right end"
                                        "F - deep end to slope break")
                            (cdr (assoc "F" pv)))
                      (list 'e 'NAX "E - slope break to right end"
                            (cdr (assoc "E" pv)) nil
                            '(or (not (cadr sp))
                                 (and lmode2 (pool:sq ans 'h) (pool:sq ans 'g)
                                      (pool:sq ans 'f)
                                      (<= (abs (- (+ (pool:sq ans 'h) (pool:sq ans 'g)
                                                     (pool:sq ans 'f))
                                                  toth2))
                                          0.5)))
                            "\nH + G + F span the main section -- E not needed."
                            '(pool:chainrest ans '(h g f) toth2))
                      (list 'm 'SUG "M - top side to deep end" (cdr (assoc "M" pv)) '(h))
                      (list 'l 'NAX "L - deep end width" (cdr (assoc "L" pv))
                            nil nil nil '(pool:sugsym ans totv2))
                      (list 'k 'SUG "K - deep end to bottom side"
                            (cdr (assoc "K" pv)) '(m h) nil nil
                            '(pool:chainrest ans '(m l) totv2)))))
        hraw (pool:sq ans 'h) graw (pool:sq ans 'g) fraw (pool:sq ans 'f)
        eraw (pool:sq ans 'e) mraw (pool:sq ans 'm) lraw (pool:sq ans 'l)
        kraw (pool:sq ans 'k)
        skipe (and (cadr sp) (equal eraw 0.0)))
  (if (not (car sp)) (setq graw 0.0))
  (if (not (cadr sp)) (setq eraw 0.0))
  ;; depths, while the live section is still on screen -- each answer
  ;; reshapes it, so C sets the walls and D digs the deep end in front
  ;; of the user
  (if (caddr sp)
      (progn
        (setq wh (pool:askh "C - wall height (shallow depth)" (cdr (assoc "C" pv))))
        (pool:pvnote 'wh wh)
        (setq dp (pool:askdeep "D - deep end depth" (cdr (assoc "D" pv)) wh))
        (pool:pvnote 'dp dp)
        (setq c2 (if (cadddr sp)
                     (pool:askc2 "C2 - depth where the shallow floor meets the break"
                                 (cdr (assoc "C2" pv)) wh dp)
                     wh))
        (if (cadddr sp) (pool:pvnote 'c2 c2))))
  (pool:pvkill)
  ;; resolve the chains: NA takes the remainder (split when several);
  ;; the style's slack member (G with a pad, F without) absorbs any
  ;; leftover, and L does across the pool
  (setq hres (pool:chainfix (list hraw graw fraw eraw) toth (nth 4 sp))
        vres (pool:chainfix (list mraw lraw kraw) totv 1)
        cv (pool:chainval hres toth) hres (car cv) hfx (cadr cv)
        cv (pool:chainval vres totv) vres (car cv) vfx (cadr cv)
        h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
        m (car vres) l (cadr vres) k (caddr vres))
  ;; a chain member that resolved negative was floored and its donor
  ;; trimmed: both get RED dims and RED report rows below
  (if hfx (pool:valnote (strcat "BOTTOM LENGTHS FAILED - "
                                (pool:fixnames hfx '("H" "G" "F" "E"))
                                " ADJUSTED, VERIFY")))
  (if vfx (pool:valnote (strcat "BOTTOM WIDTHS FAILED - "
                                (pool:fixnames vfx '("M" "L" "K"))
                                " ADJUSTED, VERIFY")))
  ;; a G that came out at zero is a slope bottom whatever was asked
  ;; for, so the section comes along automatically
  (if (< g 1.0e-6) (setq g 0.0))
  (if (and (= g 0.0) (not (caddr sp)))
      (progn
        (princ "\nG = 0 -- that is a slope bottom, so a side view is drawn too.")
        (setq wh (pool:askh "C - wall height (shallow depth)" nil)
              dp (pool:askdeep "D - deep end depth" nil wh)
              c2 wh)))
  (setq gg (pool:hopcalc quad corners h g e m k))
  (pool:hopdraw gg "POOL" tie)
  ;; side profile below the plan, per the style
  (if wh
      (pool:profdraw x0 y0 toth wh
                     (pool:btmbrks (if (caddr sp) style "SLope")
                                   h g f wh dp c2)
                     "POOL" nil))
  ;; chain dimensions along the two centerlines, like the sheet
  (setq odl (getvar "CLAYER"))
  (setvar "CLAYER" "DIMENSION")
  ;; M/L/K def points sit on the hopper edge; their dim line floats
  ;; 30" right via the 'voff vector
  (foreach tl (list (list 'pl 'phl nil (member 0 hfx))
                    (list 'phl 'phr nil (member 1 hfx))
                    (list 'phr 'pbrk nil (member 2 hfx))
                    (list 'pbrk 'pr nil (member 3 hfx))
                    (list 'pht 'pt t (member 0 vfx))
                    (list 'phb 'pht t (member 1 vfx))
                    (list 'pb 'phb t (member 2 vfx)))
    ;; a pinned-out letter (G with no pad, E on the wall) has nothing
    ;; to dimension
    (if (> (distance (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg)))
           1.0e-6)
        (progn
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                          (cadr (assoc (cadr tl) gg)))
                                (if (caddr tl) (cadr (assoc 'voff gg))
                                    (list 0.0 0.0))))
          (if (cadddr tl) (pool:dimred)))))
  ;; profile depths: C at the shallow wall, D at the deep end.  These
  ;; belong to the section, so they join pool:*profents* and stay put
  ;; when an L pool's plan is mirrored.
  (if wh
      (progn
        (pool:dimalg (list (+ x0 toth) y0) (list (+ x0 toth) (- y0 wh))
                     (list (+ x0 toth (* 0.8 doff)) (- y0 (* 0.5 wh))))
        (setq pool:*profents* (cons (entlast) pool:*profents*))
        (pool:dimalg (list (+ x0 h) y0) (list (+ x0 h) (- y0 dp))
                     (list (+ x0 h (* -0.5 doff)) (- y0 (* 0.5 dp))))
        (setq pool:*profents* (cons (entlast) pool:*profents*))
        (if (cadddr sp)
            (progn
              (pool:dimalg (list (+ x0 h g f) y0) (list (+ x0 h g f) (- y0 c2))
                           (list (+ x0 h g f (* 0.3 doff)) (- y0 (* 0.5 c2))))
              (setq pool:*profents* (cons (entlast) pool:*profents*))))))
  (setvar "CLAYER" odl)
  (setq rows (list
    (pool:vrow "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))) 0 hfx)
    (pool:vrow "HOP G" (if (car sp) graw nil)
               (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))) 1 hfx)
    (pool:vrow "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))) 2 hfx)
    (pool:vrow "HOP E" (if (or skipe (not (cadr sp))) nil eraw)
               (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))) 3 hfx)
    (pool:vrow "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))) 0 vfx)
    (pool:vrow "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))) 1 vfx)
    (pool:vrow "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))) 2 vfx)))
  (if wh
      (setq rows (append rows
                         (list (list "WALL HT C" wh wh)
                               (list "DEPTH D" dp dp))
                         (if (cadddr sp)
                             (list (list "BRK DEPTH C2" c2 c2))
                             nil))))
  rows)


;; Offset an infinite line (pt dir) toward cen by dist -> (pt dir).
(defun pool:offln (ln cen dist / n)
  (setq n (pool:unit (pool:perp (cadr ln))))
  (if (> (pool:dot (pool:v- (car ln) cen) n) 0.0)
      (setq n (pool:v* n -1.0)))
  (list (pool:v+ (car ln) (pool:v* n dist)) (cadr ln)))

;; Sport bottom PLAN geometry (per the reference drawing): full-width
;; break lines at the outer breaks, the deep flat drawn as a rectangle
;; inset M/K from the side walls, and corner diagonals tying the outer
;; breaks to the deep-flat corners -- the standard hopper language.
;; Chain points follow the standard-hopper placement rules.
(defun pool:hopsportc (lline rline bline tline cen e2 f2 g f1 e1 m k
                       / obl dfl dfr obr dfb dft oblb oblt obrb obrt
                         dbl dtl dbr dtr hc hc2 up)
  (setq obl (pool:offln lline cen e2)
        dfl (pool:offln lline cen (+ e2 f2))
        dfr (pool:offln lline cen (+ e2 f2 g))
        obr (pool:offln lline cen (+ e2 f2 g f1))
        dfb (pool:offln bline cen k)
        dft (pool:offln tline cen m)
        oblb (pool:linex (car obl) (cadr obl) (car bline) (cadr bline))
        oblt (pool:linex (car obl) (cadr obl) (car tline) (cadr tline))
        obrb (pool:linex (car obr) (cadr obr) (car bline) (cadr bline))
        obrt (pool:linex (car obr) (cadr obr) (car tline) (cadr tline))
        dbl (pool:linex (car dfl) (cadr dfl) (car dfb) (cadr dfb))
        dtl (pool:linex (car dfl) (cadr dfl) (car dft) (cadr dft))
        dbr (pool:linex (car dfr) (cadr dfr) (car dfb) (cadr dfb))
        dtr (pool:linex (car dfr) (cadr dfr) (car dft) (cadr dft))
        hc (pool:v* (pool:v+ (pool:v+ dbl dtl) (pool:v+ dbr dtr)) 0.25)
        up (pool:unit (cadr lline))
        hc2 (pool:v- hc (pool:v* up (min 12.0 (/ (distance dbr dtr) 6.0)))))
  (list (list 'oblb oblb) (list 'oblt oblt)
        (list 'obrb obrb) (list 'obrt obrt)
        (list 'dbl dbl) (list 'dtl dtl) (list 'dbr dbr) (list 'dtr dtr)
        (list 'pl (pool:linex hc2 (cadr bline) (car lline) (cadr lline)))
        (list 'pobl (pool:linex hc2 (cadr bline) (car obl) (cadr obl)))
        (list 'pdfl (pool:linex hc2 (cadr bline) (car dfl) (cadr dfl)))
        (list 'pdfr (pool:linex hc2 (cadr bline) (car dfr) (cadr dfr)))
        (list 'pobr (pool:linex hc2 (cadr bline) (car obr) (cadr obr)))
        (list 'pr (pool:linex hc2 (cadr bline) (car rline) (cadr rline)))
        ;; M/L/K attach to the deep flat's right edge; dim line +12"
        (list 'pb (pool:linex (car dfr) (cadr dfr) (car bline) (cadr bline)))
        (list 'pdb dbr)
        (list 'pdt dtr)
        (list 'pt (pool:linex (car dfr) (cadr dfr) (car tline) (cadr tline)))
        (list 'voff (pool:v* (pool:unit (cadr bline)) pool:*mlkoff*))))

(defun pool:hopsportdraw (gg nopad lay pvflag / oblb oblt obrb obrt
                                                dbl dtl dbr dtr)
  (setq oblb (cadr (assoc 'oblb gg)) oblt (cadr (assoc 'oblt gg))
        obrb (cadr (assoc 'obrb gg)) obrt (cadr (assoc 'obrt gg))
        dbl (cadr (assoc 'dbl gg)) dtl (cadr (assoc 'dtl gg))
        dbr (cadr (assoc 'dbr gg)) dtr (cadr (assoc 'dtr gg)))
  (pool:hgl oblb oblt lay pvflag)
  (pool:hgl obrb obrt lay pvflag)
  (if nopad
      (pool:hgl dbl dtl lay pvflag)     ; G = 0: the V line
      (progn
        (pool:hgl dbl dtl lay pvflag)
        (pool:hgl dtl dtr lay pvflag)
        (pool:hgl dtr dbr lay pvflag)
        (pool:hgl dbr dbl lay pvflag)))
  (pool:hgl oblb dbl lay pvflag)
  (pool:hgl oblt dtl lay pvflag)
  (pool:hgl obrb dbr lay pvflag)
  (pool:hgl obrt dtr lay pvflag))

;; Guided sport bottom: plan hopper (standard-hopper dim logic) plus
;; the side profile below with C and D only.  Returns report rows.
;; G = 0 means no hopper pad (V bottom): the deep flat collapses to
;; the single V line, its residual splits across F2/F1, and the G
;; dim/report row are skipped -- the old NOhopper variant, now just a
;; zero answer at the G prompt.
(defun pool:hopsport (lline rline bline tline cen total x0 y0 ymax doff th
                      / wid whn hdn pv e2r f2r gr f1r e1r mraw lraw kraw
                        wh hd res resid e2 f2 g f1 e1 m l k vres gg rows odl
                        brks tl xd nopad cv hfx vfx ans total2 wid2)
  (setq wid (distance (pool:linex cen (cadr lline) (car bline) (cadr bline))
                      (pool:linex cen (cadr lline) (car tline) (cadr tline)))
        whn (* 0.25 wid)
        hdn (* 0.55 wid)
        ;; the two chain totals under names of their own, for the
        ;; suggestion expressions below to read
        total2 total wid2 wid)
  ;; The live guide geometry (see "live guide reshaping"): plan and
  ;; profile together, the chain closing against the pool at every
  ;; answer and the section digging itself as C and D come in.  The
  ;; padded structure is kept whatever G does -- a zero pad simply
  ;; collapses onto the V line.
  (defun hs:geo ( / res e2v f2v gv f1v e1v mv kv wh2 dp2 gg)
    (setq res (pool:pvchain
                (list (pool:pvdim 'e2) (pool:pvdim 'f2) (pool:pvdim 'g)
                      (pool:pvdim 'f1) (pool:pvdim 'e1))
                (list (* 0.12 total) (* 0.20 total) (* 0.30 total)
                      (* 0.26 total) (* 0.12 total))
                total)
          e2v (car res) f2v (cadr res) gv (caddr res)
          f1v (cadddr res) e1v (nth 4 res)
          res (pool:pvchain
                (list (pool:pvdim 'm) (pool:pvdim 'l) (pool:pvdim 'k))
                (list (* 0.2 wid) (* 0.6 wid) (* 0.2 wid))
                wid)
          mv (car res) kv (caddr res)
          wh2 (cond ((pool:pvdim 'wh)) (whn))
          dp2 (cond ((pool:pvdim 'dp)) (hdn))
          ;; a deep C with D still open must not float the floor above
          ;; the wall bottoms while D is being asked
          dp2 (max dp2 (* 1.15 wh2))
          gg (pool:hopsportc lline rline bline tline cen
                             e2v f2v gv f1v e1v mv kv))
    (pool:pvcopen)
    (pool:hopsportdraw gg nil "POOL-NOTES" t)
    (pool:profdraw x0 y0 total wh2
                   (list (cons e2v wh2) (cons (+ e2v f2v) dp2)
                         (cons (+ e2v f2v gv) dp2)
                         (cons (- total e1v) wh2))
                   "POOL-NOTES" t)
    (pool:pvctie (cadr (assoc 'pl gg)) (cadr (assoc 'pobl gg)) "E2" th)
    (pool:pvctie (cadr (assoc 'pobl gg)) (cadr (assoc 'pdfl gg)) "F2" th)
    (pool:pvctie (cadr (assoc 'pdfl gg)) (cadr (assoc 'pdfr gg)) "G" th)
    (pool:pvctie (cadr (assoc 'pdfr gg)) (cadr (assoc 'pobr gg)) "F1" th)
    (pool:pvctie (cadr (assoc 'pobr gg)) (cadr (assoc 'pr gg)) "E1" th)
    (pool:pvctie (cadr (assoc 'pdt gg)) (cadr (assoc 'pt gg)) "M" th)
    (pool:pvctie (cadr (assoc 'pdb gg)) (cadr (assoc 'pdt gg)) "L" th)
    (pool:pvctie (cadr (assoc 'pb gg)) (cadr (assoc 'pdb gg)) "K" th)
    (pool:pvctie (list (+ x0 total (* 0.6 doff)) y0)
                 (list (+ x0 total (* 0.6 doff)) (- y0 wh2)) "C" th)
    (pool:pvctie (list (+ x0 e2v f2v (* 0.5 gv)) y0)
                 (list (+ x0 e2v f2v (* 0.5 gv)) (- y0 dp2)) "D" th)
    (pool:pvcout (append (pool:bodyquad lline rline bline tline)
                         (list (list x0 ymax)))))
  (setq pv (pool:pvlive 'hs:geo))
  (princ "\nSport bottom -- plan hopper letters; the RED tie is being asked for.")
  (princ "\n(after the first answer, Back re-asks the previous one)")
  (setq ans (pool:askseq
              (list (list 'e2 'NAX "E2 - left end shallow flat" (cdr (assoc "E2" pv)))
                    (list 'f2 'NAX "F2 - left slope" (cdr (assoc "F2" pv)))
                    (list 'g 'ZER "G - deep flat length, 0 = no hopper pad"
                          (cdr (assoc "G" pv)))
                    (list 'f1 'NAX "F1 - right slope" (cdr (assoc "F1" pv)))
                    (list 'e1 'NAX "E1 - right end shallow flat" (cdr (assoc "E1" pv))
                          nil nil nil '(pool:chainrest ans '(e2 f2 g f1) total2))
                    (list 'm 'NAX "M - top side to deep flat" (cdr (assoc "M" pv)))
                    (list 'l 'NAX "L - deep flat width" (cdr (assoc "L" pv)))
                    (list 'k 'SUG "K - deep flat to bottom side"
                          (cdr (assoc "K" pv)) '(m) nil nil
                          '(pool:chainrest ans '(m l) wid2))))
        e2r (pool:sq ans 'e2) f2r (pool:sq ans 'f2) gr (pool:sq ans 'g)
        f1r (pool:sq ans 'f1) e1r (pool:sq ans 'e1)
        mraw (pool:sq ans 'm) lraw (pool:sq ans 'l) kraw (pool:sq ans 'k)
        nopad (and gr (< gr 1.0e-6))
        wh (pool:askh "C - wall height (shallow depth)" (cdr (assoc "C" pv))))
  (pool:pvnote 'wh wh)
  (setq hd (pool:askdeep "D - deep depth" (cdr (assoc "D" pv)) wh))
  (pool:pvnote 'dp hd)
  (pool:pvkill)
  ;; resolve: horizontal chain vs the pool length (G absorbs; the
  ;; no-pad sport fixes G = 0 and splits its residual across F2/F1),
  ;; vertical chain vs the width (L absorbs)
  (if nopad
      (progn
        (setq res (pool:chainfix (list e2r f2r f1r e1r) total -1)
              e2 (car res) f2 (cadr res) f1 (caddr res) e1 (cadddr res)
              g 0.0
              resid (- total e2 f2 f1 e1))
        (if (> (abs resid) 1.0e-6)
            (setq f2 (+ f2 (* 0.5 resid))
                  f1 (+ f1 (* 0.5 resid)))))
      (setq res (pool:chainfix (list e2r f2r gr f1r e1r) total 2)
            e2 (car res) f2 (cadr res) g (caddr res)
            f1 (cadddr res) e1 (nth 4 res)))
  ;; no member of the resolved chain may be negative: floor it and
  ;; trim the largest other member, marking both red below
  (setq cv (pool:chainval (list e2 f2 g f1 e1) total)
        hfx (cadr cv)
        e2 (nth 0 (car cv)) f2 (nth 1 (car cv)) g (nth 2 (car cv))
        f1 (nth 3 (car cv)) e1 (nth 4 (car cv)))
  (if hfx (pool:valnote (strcat "SPORT LENGTHS FAILED - "
                                (pool:fixnames hfx '("E2" "F2" "G" "F1" "E1"))
                                " ADJUSTED, VERIFY")))
  ;; a G that resolves away (NA with the rest filling the length, or
  ;; absorbed to nothing) also collapses to the no-pad V bottom
  (if (< g 1.0e-6) (setq nopad t g 0.0))
  (setq vres (pool:chainfix (list mraw lraw kraw) wid 1)
        cv (pool:chainval vres wid) vres (car cv) vfx (cadr cv)
        m (car vres) l (cadr vres) k (caddr vres)
        gg (pool:hopsportc lline rline bline tline cen e2 f2 g f1 e1 m k))
  (if vfx (pool:valnote (strcat "SPORT WIDTHS FAILED - "
                                (pool:fixnames vfx '("M" "L" "K"))
                                " ADJUSTED, VERIFY")))
  (pool:hopsportdraw gg nopad "POOL" nil)
  ;; profile below, with C and D dims only
  (setq brks (if nopad
                 (list (cons e2 wh) (cons (+ e2 f2) hd) (cons (- total e1) wh))
                 (list (cons e2 wh) (cons (+ e2 f2) hd)
                       (cons (- total e1 f1) hd) (cons (- total e1) wh))))
  (pool:profdraw x0 y0 total wh brks "POOL" nil)
  (setq odl (getvar "CLAYER"))
  (setvar "CLAYER" "DIMENSION")
  ;; plan chains, standard-hopper style
  (foreach tl (append (list (list 'pl 'pobl nil (member 0 hfx))
                            (list 'pobl 'pdfl nil (member 1 hfx)))
                      (if nopad nil (list (list 'pdfl 'pdfr nil (member 2 hfx))))
                      (list (list 'pdfr 'pobr nil (member 3 hfx))
                            (list 'pobr 'pr nil (member 4 hfx))
                            (list 'pdt 'pt t (member 0 vfx))
                            (list 'pdb 'pdt t (member 1 vfx))
                            (list 'pb 'pdb t (member 2 vfx))))
    (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                 (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                    (cadr (assoc (cadr tl) gg)))
                          (if (caddr tl) (cadr (assoc 'voff gg))
                              (list 0.0 0.0))))
    (if (cadddr tl) (pool:dimred)))
  (pool:dimalg (list (+ x0 total) y0) (list (+ x0 total) (- y0 wh))
               (list (+ x0 total (* 0.8 doff)) (- y0 (* 0.5 wh))))
  (setq xd (if nopad (+ x0 e2 f2) (+ x0 e2 f2 (* 0.5 g))))
  (pool:dimalg (list xd y0) (list xd (- y0 hd))
               (list (+ xd (* 0.3 doff)) (- y0 (* 0.5 hd))))
  (setvar "CLAYER" odl)
  (setq rows (append
    (list (pool:vrow "SPT E2" e2r (distance (cadr (assoc 'pl gg)) (cadr (assoc 'pobl gg))) 0 hfx)
          (pool:vrow "SPT F2" f2r (distance (cadr (assoc 'pobl gg)) (cadr (assoc 'pdfl gg))) 1 hfx))
    (if nopad nil
        (list (pool:vrow "SPT G" gr (distance (cadr (assoc 'pdfl gg)) (cadr (assoc 'pdfr gg))) 2 hfx)))
    (list (pool:vrow "SPT F1" f1r (distance (cadr (assoc 'pdfr gg)) (cadr (assoc 'pobr gg))) 3 hfx)
          (pool:vrow "SPT E1" e1r (distance (cadr (assoc 'pobr gg)) (cadr (assoc 'pr gg))) 4 hfx)
          (pool:vrow "SPT M" mraw (distance (cadr (assoc 'pdt gg)) (cadr (assoc 'pt gg))) 0 vfx)
          (pool:vrow "SPT L" lraw (distance (cadr (assoc 'pdb gg)) (cadr (assoc 'pdt gg))) 1 vfx)
          (pool:vrow "SPT K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'pdb gg))) 2 vfx)
          (list "WALL HT C" wh wh)
          (list "DEPTH D" hd hd))))
  rows)

;; Pool-bottom dispatcher for the rectangle.
;; Returns the report rows (nil if skipped).
(defun pool:hopper (quad corners doff th / btype xmin xmax ymin ymax
                                           a b c d cen sres ln xi)
  (if (not (pool:askbottom))
      nil
      (progn
        (setq xmin (apply 'min (mapcar 'car quad))
              xmax (apply 'max (mapcar 'car quad))
              ymin (apply 'min (mapcar 'cadr quad))
              ymax (apply 'max (mapcar 'cadr quad)))
        (command "_.ZOOM" "_Window"
                 (pool:wp (list (- xmin doff) (- ymin doff)))
                 (pool:wp (list (+ xmax doff) (+ ymax doff))))
        (setq btype (pool:askkwf 'btype "Bottom type"
                                 pool:*btypes* pool:*btshown*
                                 "Normal" nil))
        (if (/= btype "Sport")
            (pool:hopnormal quad corners doff th nil btype
                            xmin (- ymin (* 2.2 doff)) t)
            (progn
              (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
                    cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25))
              (pool:hopsport (list a (pool:v- d a)) (list b (pool:v- c b))
                             (list a (pool:v- b a)) (list d (pool:v- c d))
                             cen (distance a b)
                             xmin (- ymin (* 2.2 doff)) ymax
                             doff th))))))

;;; -------------------- side profile -----------------------------------
;;;
;;;  Section view under the plan: waterline across the top, walls of
;;;  height C at both ends, and the bottom running through the given
;;;  break vertices.  Used by the normal hoppers and by the Sport
;;;  bottoms (whose field sheets ARE this profile).

;; Draw the profile outline.  x0/y0 = top-left, total = pool length,
;; wh = wall height, brks = bottom vertices ((dist . depth) ...) from
;; the left wall, left to right.
(defun pool:profdraw (x0 y0 total wh brks lay pvflag / pts prev p)
  (setq pts (append (list (list x0 y0)
                          (list (+ x0 total) y0)
                          (list (+ x0 total) (- y0 wh)))
                    (mapcar '(lambda (p) (list (+ x0 (car p)) (- y0 (cdr p))))
                            (reverse brks))
                    (list (list x0 (- y0 wh))
                          (list x0 y0)))
        prev (car pts))
  (foreach p (cdr pts)
    ;; a break sitting exactly on a wall bottom repeats that point --
    ;; but a COLLECTED profile keeps every segment, even zero-length,
    ;; so the live guide's primitive count never changes as the
    ;; answers move the breaks around
    (if (or (and pvflag pool:*pvcoll*) (> (distance prev p) 1.0e-6))
        (progn
          (pool:hgl prev p lay pvflag)
          ;; remember the real (non-preview) section lines so an L
          ;; pool's plan mirror can leave them alone
          (if (not pvflag)
              (setq pool:*profents* (cons (entlast) pool:*profents*)))))
    (setq prev p)))

;; Line/arc makers used by the shape-specific hopper draws.  Three
;; ways out: the real drawing on layer lay; the old gray-guide preview
;; (pvflag); and, when the live-guide collector is armed, the pvflag
;; path emits a spec primitive instead of an entity -- which is how
;; the bottom guides reshape with every answer.
(defun pool:hgl (p q lay pvflag)
  (cond
    ((and pvflag pool:*pvcoll*) (pool:pvcput (list "LINE" p q)))
    (pvflag (pool:pvadd (pool:pvline p q)))
    (t (pool:line p q lay))))

(defun pool:hga (p mm q lay pvflag)
  (cond
    ((and pvflag pool:*pvcoll*) (pool:pvcput (list "ARC" p mm q)))
    (pvflag
     (pool:arc3p p mm q "POOL-NOTES")
     (pool:pvadd (pool:setcol (entlast) pool:*pv-col*)))
    (t (pool:arc3p p mm q lay))))

;;; ---------------- oval pool bottom (True Oval sheet) -----------------
;;;
;;;  The hopper is a box with a radius (R3) left end, set out along
;;;  the pool axis (arc tip to arc tip):
;;;    H = pool left tip -> hopper tip      E = break -> pool right tip
;;;    G = hopper tip -> hopper right edge  M/K = top/bottom offsets
;;;    R3 = hopper end radius               L = hopper width (CHECK)
;;;    W = hopper flat top, tangent -> right edge (CHECK, = G - R3)
;;;    F = hopper -> slope break (CHECK)    T = straight side (CHECK)
;;;  No left ties (the radius IS the end); the right corners tie to
;;;  the slope-break ends as usual.

(defun pool:hopovalc (quad tipl tipr h g e m k r3 / a b c d cen u v ht hb
                                                    lt re tan brk tt tb tip vc
                                                    tip2)
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        u (pool:unit (pool:v- tipr tipl))
        v (pool:perp u)
        ht (pool:offline d c cen m)
        hb (pool:offline a b cen k)
        lt (list (pool:v+ tipl (pool:v* u h)) v)
        re (list (pool:v+ tipl (pool:v* u (+ h g))) v)
        tan (list (pool:v+ tipl (pool:v* u (+ h r3))) v)
        brk (list (pool:v- tipr (pool:v* u e)) v)
        tt (pool:linex (car tan) (cadr tan) (car ht) (cadr ht))
        tb (pool:linex (car tan) (cadr tan) (car hb) (cadr hb))
        tip (pool:mid (pool:linex (car lt) (cadr lt) (car ht) (cadr ht))
                      (pool:linex (car lt) (cadr lt) (car hb) (cadr hb)))
        ;; M/L/K attach to the hopper's right edge; dim line +12"
        vc (pool:v+ tipl (pool:v* u (+ h g)))
        ;; H/G/F/E chain below the hopper centre by 12" or L/6,
        ;; whichever is closer
        tip2 (pool:v- tip
                      (pool:v* (pool:unit v)
                               (min 12.0
                                    (/ (distance
                                         (pool:linex vc v (car hb) (cadr hb))
                                         (pool:linex vc v (car ht) (cadr ht)))
                                       6.0)))))
  (list (list 'tip tip) (list 'ttop tt) (list 'tbot tb)
        (list 'htr (pool:linex (car re) (cadr re) (car ht) (cadr ht)))
        (list 'hbr (pool:linex (car re) (cadr re) (car hb) (cadr hb)))
        (list 'brkb (pool:linex (car brk) (cadr brk) a (pool:v- b a)))
        (list 'brkt (pool:linex (car brk) (cadr brk) d (pool:v- c d)))
        (list 'ptan (pool:linex tip2 u (car tan) v))
        (list 'pl (pool:linex tip2 u tipl v))
        (list 'phl (pool:linex tip2 u (car lt) (cadr lt)))
        (list 'phr (pool:linex tip2 u (car re) v))
        (list 'pbrk (pool:linex tip2 u (car brk) v))
        (list 'pr (pool:linex tip2 u tipr v))
        (list 'pb (pool:linex vc v a (pool:v- b a)))
        (list 'phb (pool:linex vc v (car hb) (cadr hb)))
        (list 'pht (pool:linex vc v (car ht) (cadr ht)))
        (list 'pt (pool:linex vc v d (pool:v- c d)))
        (list 'voff (pool:v* u pool:*mlkoff*))))

(defun pool:hopovaldraw (gg lay pvflag / tt tb tip htr hbr brkb brkt)
  (setq tt (cadr (assoc 'ttop gg)) tb (cadr (assoc 'tbot gg))
        tip (cadr (assoc 'tip gg))
        htr (cadr (assoc 'htr gg)) hbr (cadr (assoc 'hbr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg)))
  (pool:hgl tt htr lay pvflag)
  (pool:hgl tb hbr lay pvflag)
  (pool:hgl htr hbr lay pvflag)
  (pool:hga tt tip tb lay pvflag)
  (pool:hgl brkb brkt lay pvflag)
  (pool:hgl htr brkt lay pvflag)
  (pool:hgl hbr brkb lay pvflag))

;; Guided oval bottom phase.  Returns report rows (nil if skipped).
(defun pool:hopoval (quad tipl tipr doff th / pv gg rows tl odl
                                              h g f e m l k r3 r3raw w tt o
                                              hraw graw fraw eraw mraw lraw kraw
                                              totv hres vres cv hfx vfx r3wbad
                                              ans len2 totv2)
  (if nil                               ; Yes/No now lives in the dispatcher
      nil
      (progn
        ;; The live guide geometry (see "live guide reshaping"): the
        ;; axis chain closes against the tip-to-tip length at every
        ;; answer, the M/L/K chain against the width, and the radius
        ;; end follows R3 / W -- or stays the tangent semicircle of
        ;; whatever hopper width the offsets currently give.
        (defun ho:geo ( / len wid res hv gv ev mv lv kv r3v gg)
          (setq len (distance tipl tipr)
                wid (distance (car quad) (cadddr quad))
                res (pool:pvchain
                      (list (pool:pvdim 'h) (pool:pvdim 'g)
                            (pool:pvdim 'f) (pool:pvdim 'e))
                      (list (* 0.10 len) (* 0.24 len)
                            (* 0.28 len) (* 0.38 len))
                      len)
                hv (car res) gv (cadr res) ev (cadddr res)
                res (pool:pvchain
                      (list (pool:pvdim 'm) (pool:pvdim 'l) (pool:pvdim 'k))
                      (list (* 0.25 wid) (* 0.5 wid) (* 0.25 wid))
                      wid)
                mv (car res) lv (cadr res) kv (caddr res)
                ;; the same precedence the resolver applies below: a
                ;; given R3 wins, else the tangent semicircle of the
                ;; hopper width, and only a collapsed width lets W
                ;; spend the hopper length -- so the end the user
                ;; watches is the end the final draw keeps
                r3v (cond ((pool:pvdim 'r3))
                          ((> lv 1.0e-6) (* 0.5 lv))
                          ((and (pool:pvdim 'w)
                                (> (- gv (pool:pvdim 'w)) 1.0))
                           (- gv (pool:pvdim 'w)))
                          (t (* 0.20 wid)))
                r3v (max (min r3v (* 0.9 gv)) (* 0.02 len))
                gg (pool:hopovalc quad tipl tipr hv gv ev mv kv r3v))
          (pool:pvcopen)
          (pool:hopovaldraw gg "POOL-NOTES" t)
          (pool:pvctie (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg)) "H" th)
          (pool:pvctie (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg)) "G" th)
          (pool:pvctie (cadr (assoc 'phl gg)) (cadr (assoc 'ptan gg)) "R3" th)
          (pool:pvctie (cadr (assoc 'ttop gg)) (cadr (assoc 'htr gg)) "W" th)
          (pool:pvctie (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg)) "F" th)
          (pool:pvctie (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg)) "E" th)
          (pool:pvctie (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg)) "M" th)
          (pool:pvctie (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg)) "L" th)
          (pool:pvctie (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg)) "K" th)
          (pool:pvctie (cadddr quad) (caddr quad) "T" th)
          (pool:pvcout (append quad (list tipl tipr))))
        (setq pv (pool:pvlive 'ho:geo))
        (princ "\nPool bottom -- offsets along the pool axis; the RED tie is being asked for.")
        (princ "\n(after the first answer, Back re-asks the previous one)")
        ;; the two chain totals -- tip to tip along the pool, wall to
        ;; wall across it -- are worked out BEFORE the questions now,
        ;; so the last letter of each chain can be suggested as it is
        ;; reached rather than only resolved afterwards
        (setq len2 (distance tipl tipr)
              totv (distance
                     (pool:linex (pool:mid (car quad) (caddr quad))
                                 (pool:v- (cadddr quad) (car quad))
                                 (car quad) (pool:v- (cadr quad) (car quad)))
                     (pool:linex (pool:mid (car quad) (caddr quad))
                                 (pool:v- (cadddr quad) (car quad))
                                 (cadddr quad) (pool:v- (caddr quad) (cadddr quad))))
              totv2 totv)
        (setq ans (pool:askseq
                    (list (list 'h 'NAX "H - pool left tip to hopper tip" (cdr (assoc "H" pv)))
                          (list 'g 'NAX "G - hopper length (tip to right edge)" (cdr (assoc "G" pv)))
                          (list 'r3 'NAX "R3 - hopper end radius" (cdr (assoc "R3" pv)))
                          (list 'w 'NAX "W - hopper flat top" (cdr (assoc "W" pv)))
                          (list 'f 'NAX "F - hopper to slope break" (cdr (assoc "F" pv)))
                          (list 'e 'NAX "E - slope break to pool right tip" (cdr (assoc "E" pv))
                                nil nil nil '(pool:chainrest ans '(h g f) len2))
                          (list 'm 'SUG "M - top side to hopper" (cdr (assoc "M" pv)) '(h))
                          (list 'l 'NAX "L - hopper width" (cdr (assoc "L" pv))
                                nil nil nil '(pool:sugsym ans totv2))
                          (list 'k 'SUG "K - hopper to bottom side" (cdr (assoc "K" pv)) '(m h)
                                nil nil '(pool:chainrest ans '(m l) totv2))
                          (list 'tt 'NAX "T - straight side length (check)" (cdr (assoc "T" pv)))))
              hraw (pool:sq ans 'h) graw (pool:sq ans 'g) r3raw (pool:sq ans 'r3)
              w (pool:sq ans 'w) fraw (pool:sq ans 'f) eraw (pool:sq ans 'e)
              mraw (pool:sq ans 'm) lraw (pool:sq ans 'l) kraw (pool:sq ans 'k)
              tt (pool:sq ans 'tt))
        (pool:pvkill)
        ;; resolve against tip-to-tip length and side-to-side width
        ;; (both measured out above, before the questions)
        (setq hres (pool:chainfix (list hraw graw fraw eraw) (distance tipl tipr) 1)
              vres (pool:chainfix (list mraw lraw kraw) totv 1)
              cv (pool:chainval hres (distance tipl tipr))
              hres (car cv) hfx (cadr cv)
              cv (pool:chainval vres totv) vres (car cv) vfx (cadr cv)
              h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
              m (car vres) l (cadr vres) k (caddr vres))
        (if hfx (pool:valnote (strcat "BOTTOM LENGTHS FAILED - "
                                      (pool:fixnames hfx '("H" "G" "F" "E"))
                                      " ADJUSTED, VERIFY")))
        (if vfx (pool:valnote (strcat "BOTTOM WIDTHS FAILED - "
                                      (pool:fixnames vfx '("M" "L" "K"))
                                      " ADJUSTED, VERIFY")))
        ;; The hopper's radius end and its flat top close against the
        ;; hopper length:  R3 + W = G.
        ;;   * R3 NA -> half the hopper width the offsets give (L/2),
        ;;     the semicircle end that meets the straight sides
        ;;     tangentially; failing that, whatever W leaves of G
        ;;   * W NA  -> G - R3, i.e. the flat runs from the arc's
        ;;     tangent point to the hopper's right edge
        (setq r3 (cond (r3raw r3raw)
                       ((> l 1.0e-6) (* 0.5 l))
                       (w (- g w))
                       (t (* 0.5 l))))
        (if (< r3 1.0e-6) (setq r3 (* 0.5 l)))
        ;; when BOTH were measured they must close against the hopper
        ;; length: R3 + W = G
        (if (and r3raw w (> (abs (- (+ r3raw w) g)) 0.5))
            (progn
              (setq r3wbad t)
              (pool:valnote "OVAL HOPPER R3 + W DOES NOT CLOSE AGAINST G - VERIFY")))
        (setq gg (pool:hopovalc quad tipl tipr h g e m k r3))
        (pool:hopovaldraw gg "POOL" nil)
        (setq odl (getvar "CLAYER"))
        (setvar "CLAYER" "DIMENSION")
        (foreach tl (list (list 'pl 'phl nil (member 0 hfx))
                          (list 'phl 'phr nil (member 1 hfx))
                          (list 'phr 'pbrk nil (member 2 hfx))
                          (list 'pbrk 'pr nil (member 3 hfx))
                          (list 'phl 'ptan nil r3wbad)
                          (list 'ttop 'htr nil r3wbad)
                          (list 'pht 'pt t (member 0 vfx))
                          (list 'phb 'pht t (member 1 vfx))
                          (list 'pb 'phb t (member 2 vfx)))
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                          (cadr (assoc (cadr tl) gg)))
                                (if (caddr tl) (cadr (assoc 'voff gg))
                                    (list 0.0 0.0))))
          (if (cadddr tl) (pool:dimred)))
        (setvar "CLAYER" odl)
        (setq o (pool:circum (cadr (assoc 'ttop gg)) (cadr (assoc 'tip gg))
                             (cadr (assoc 'tbot gg)))
              rows (list
          (pool:vrow "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))) 0 hfx)
          (pool:vrow "HOP G" graw (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))) 1 hfx)
          (append (list "HOP R3" r3raw (if o (distance o (cadr (assoc 'tip gg))) r3))
                  (if r3wbad (list t) nil))
          (append (list "HOP W" w (distance (cadr (assoc 'ttop gg)) (cadr (assoc 'htr gg))))
                  (if r3wbad (list t) nil))
          (pool:vrow "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))) 2 hfx)
          (pool:vrow "HOP E" eraw (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))) 3 hfx)
          (pool:vrow "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))) 0 vfx)
          (pool:vrow "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))) 1 vfx)
          (pool:vrow "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))) 2 vfx)
          (list "HOP T" tt (distance (cadddr quad) (caddr quad)))))
        rows)))

;;; ---------------- grecian pool bottom (Square / 6-sided) -------------
;;;
;;;  Square hopper = the rectangle letters (H G F E M L K), anchored
;;;  off the end walls; each hopper left corner ties to BOTH ends of
;;;  its pool corner cut.  The 6-sided hopper cuts the deep pad's left
;;;  corners, and can be measured TWO ways (hex argument):
;;;
;;;    ("Offsets" co) -- offsets from the walls only: every pad edge
;;;      is its pool wall offset inward (left wall by H, top/bottom by
;;;      M/K) and the cut faces are the pool CORNER CUTS offset in by
;;;      co, so every hopper line is PARALLEL to its wall.  Corners
;;;      land wherever adjacent offset lines intersect.
;;;
;;;    ("Letters" w l1 lw) -- the field-sheet letters:
;;;      W  = the top/bottom flat, cut corner to the pad's right edge
;;;      L1 = the left edge length, centred on the pad
;;;      (lw = the resolved hopper width L, so the cut drop per corner
;;;      is (L - L1)/2; X = sqrt((G-W)^2 + ((L-L1)/2)^2) is a CHECK.)
;;;      The flats and the left edge ride their wall-offset lines
;;;      (parallel); the cut faces just CONNECT the corners and need
;;;      not be parallel to anything.
;;;
;;;  Either way the pool cut ends tie to the matching hopper corners.

(defun pool:hopgrecc (pts h g e m k hex / aa bb rb rt cc dd ltp lbp cen p
                                          hl hr ht hb brk hbl htl hbr htr
                                          hlw htl1 hbl1 hc u v hc2 out
                                          tcut bcut dy ct1 ct2 cb1 cb2)
  (setq aa (nth 0 pts) bb (nth 1 pts) rb (nth 2 pts) rt (nth 3 pts)
        cc (nth 4 pts) dd (nth 5 pts) ltp (nth 6 pts) lbp (nth 7 pts)
        cen (list 0.0 0.0))
  (foreach p pts (setq cen (pool:v+ cen p)))
  (setq cen (pool:v* cen 0.125)
        hl (pool:offline lbp ltp cen h)
        hr (pool:offline lbp ltp cen (+ h g))
        ht (pool:offline dd cc cen m)
        hb (pool:offline aa bb cen k)
        brk (pool:offline rb rt cen e)
        hbl (pool:linex (car hl) (cadr hl) (car hb) (cadr hb))
        htl (pool:linex (car hl) (cadr hl) (car ht) (cadr ht))
        hbr (pool:linex (car hr) (cadr hr) (car hb) (cadr hb))
        htr (pool:linex (car hr) (cadr hr) (car ht) (cadr ht))
        hc (pool:v* (pool:v+ (pool:v+ hbl htl) (pool:v+ hbr htr)) 0.25)
        u (pool:v- bb aa)
        v (pool:v- dd aa)
        ;; chain placement: H/G/F/E below the hopper centre by 12" or
        ;; L/6 (whichever is closer); M/L/K 12" right of the hopper
        hc2 (pool:v- hc (pool:v* (pool:unit v)
                                 (min 12.0 (/ (distance hbr htr) 6.0))))
        out (list
          (list 'hbl hbl) (list 'htl htl) (list 'hbr hbr) (list 'htr htr)
          (list 'brkb (pool:linex (car brk) (cadr brk) aa (pool:v- bb aa)))
          (list 'brkt (pool:linex (car brk) (cadr brk) dd (pool:v- cc dd)))
          (list 'aa aa) (list 'dd dd) (list 'ltp ltp) (list 'lbp lbp)
          (list 'pl (pool:linex hc2 u lbp (pool:v- ltp lbp)))
          (list 'phl (pool:linex hc2 u (car hl) (cadr hl)))
          (list 'phr (pool:linex hc2 u (car hr) (cadr hr)))
          (list 'pbrk (pool:linex hc2 u (car brk) (cadr brk)))
          (list 'pr (pool:linex hc2 u rb (pool:v- rt rb)))
          (list 'pb (pool:linex (car hr) (cadr hr) aa (pool:v- bb aa)))
          (list 'phb hbr)
          (list 'pht htr)
          (list 'pt (pool:linex (car hr) (cadr hr) dd (pool:v- cc dd)))
          (list 'voff (pool:v* (pool:unit u) pool:*mlkoff*))))
  (if hex
      (progn
        (if (= (car hex) "Offsets")
            ;; cut faces = the pool corner cuts offset inward by co;
            ;; corners at the intersections with the adjacent offsets
            (setq tcut (pool:offline ltp dd cen (cadr hex))
                  bcut (pool:offline lbp aa cen (cadr hex))
                  ct1 (pool:linex (car tcut) (cadr tcut) (car ht) (cadr ht))
                  ct2 (pool:linex (car tcut) (cadr tcut) (car hl) (cadr hl))
                  cb1 (pool:linex (car bcut) (cadr bcut) (car hb) (cadr hb))
                  cb2 (pool:linex (car bcut) (cadr bcut) (car hl) (cadr hl)))
            ;; sheet letters: cut corners W back from the pad's right
            ;; edge along the flats, the left edge L1 long centred on
            ;; the pad; the faces connect them (no parallelism forced)
            (setq hlw (pool:offline lbp ltp cen (+ h (- g (cadr hex))))
                  dy (* 0.5 (- (cadddr hex) (caddr hex)))
                  htl1 (pool:offline dd cc cen (+ m dy))
                  hbl1 (pool:offline aa bb cen (+ k dy))
                  ct1 (pool:linex (car hlw) (cadr hlw) (car ht) (cadr ht))
                  ct2 (pool:linex (car hl) (cadr hl) (car htl1) (cadr htl1))
                  cb1 (pool:linex (car hlw) (cadr hlw) (car hb) (cadr hb))
                  cb2 (pool:linex (car hl) (cadr hl) (car hbl1) (cadr hbl1))))
        (setq out (append out (list (list 'ct1 ct1) (list 'ct2 ct2)
                                    (list 'cb1 cb1) (list 'cb2 cb2))))))
  out)

(defun pool:hopgrecdraw (gg lay six pvflag / hbl htl hbr htr brkb brkt
                                             aa dd ltp lbp ct1 ct2 cb1 cb2)
  (setq hbl (cadr (assoc 'hbl gg)) htl (cadr (assoc 'htl gg))
        hbr (cadr (assoc 'hbr gg)) htr (cadr (assoc 'htr gg))
        brkb (cadr (assoc 'brkb gg)) brkt (cadr (assoc 'brkt gg))
        aa (cadr (assoc 'aa gg)) dd (cadr (assoc 'dd gg))
        ltp (cadr (assoc 'ltp gg)) lbp (cadr (assoc 'lbp gg)))
  (pool:hgl htr hbr lay pvflag)
  (pool:hgl brkb brkt lay pvflag)
  (pool:hgl htr brkt lay pvflag)
  (pool:hgl hbr brkb lay pvflag)
  (if six
      (progn
        (setq ct1 (cadr (assoc 'ct1 gg)) ct2 (cadr (assoc 'ct2 gg))
              cb1 (cadr (assoc 'cb1 gg)) cb2 (cadr (assoc 'cb2 gg)))
        (pool:hgl ct1 htr lay pvflag)
        (pool:hgl cb1 hbr lay pvflag)
        (pool:hgl ct2 cb2 lay pvflag)
        (pool:hgl ct2 ct1 lay pvflag)
        (pool:hgl cb2 cb1 lay pvflag)
        (pool:hgl dd ct1 lay pvflag)
        (pool:hgl ltp ct2 lay pvflag)
        (pool:hgl aa cb1 lay pvflag)
        (pool:hgl lbp cb2 lay pvflag))
      (progn
        (pool:hgl htl htr lay pvflag)
        (pool:hgl hbl hbr lay pvflag)
        (pool:hgl htl hbl lay pvflag)
        (pool:hgl dd htl lay pvflag)
        (pool:hgl ltp htl lay pvflag)
        (pool:hgl aa hbl lay pvflag)
        (pool:hgl lbp hbl lay pvflag))))

;; Guided grecian bottom phase.  Returns report rows (nil if skipped).
(defun pool:hopgrec (pts doff th / htype six mode pv gg rows tl odl
                                   h g f e m l k w l1 x co coraw xcal sixbad
                                   hraw graw fraw eraw mraw lraw kraw
                                   cen p u vv toth totv hres vres cv hfx vfx ans
                                   mm ud proj toth2 totv2)
  (if nil                               ; Yes/No now lives in the dispatcher
      nil
      (progn
        ;; the bracket is exactly the keyword list (STANDARDS section
        ;; 1 rule 1): a click on "SIX-sided" sent text initget could
        ;; not accept, so the explanation moved into the question
        (setq htype (pool:askkwf 'htype "Hopper type (SIX = six-sided)"
                                 "Square SIX" "Square/SIX"
                                 "Square" nil)
              six (= htype "SIX"))
        ;; a six-sided deep end can be taped two ways: offsets shot
        ;; from every wall (cut faces parallel to the pool cuts), or
        ;; the sheet letters W / X / L / L1 / G / M / K
        (if six
            (setq mode (pool:askkwf 'hmode "SIX-sided corners measured by"
                                    "Offsets Letters" "Offsets/Letters"
                                    "Offsets" nil)))
        ;; The live guide geometry (see "live guide reshaping"): the
        ;; chain closes against the end-wall-to-end-wall total at every
        ;; answer, and the six-sided corner letters move their own cut
        ;; faces as they come in.
        (defun hg:geo ( / len wid gcen gu p2 gth gtv res
                          hv gv ev mv lv kv hx gg)
          (setq len (distance (nth 0 pts) (nth 1 pts))
                wid (distance (nth 0 pts) (nth 5 pts))
                gcen (list 0.0 0.0))
          (foreach p2 pts (setq gcen (pool:v+ gcen p2)))
          (setq gcen (pool:v* gcen 0.125)
                gu (pool:v- (nth 1 pts) (nth 0 pts))
                gth (distance
                      (pool:linex gcen gu (nth 7 pts)
                                  (pool:v- (nth 6 pts) (nth 7 pts)))
                      (pool:linex gcen gu (nth 2 pts)
                                  (pool:v- (nth 3 pts) (nth 2 pts))))
                gtv (distance
                      (pool:linex gcen (pool:v- (nth 5 pts) (nth 0 pts))
                                  (nth 0 pts)
                                  (pool:v- (nth 1 pts) (nth 0 pts)))
                      (pool:linex gcen (pool:v- (nth 5 pts) (nth 0 pts))
                                  (nth 5 pts)
                                  (pool:v- (nth 4 pts) (nth 5 pts))))
                res (pool:pvchain
                      (list (pool:pvdim 'h) (pool:pvdim 'g)
                            (pool:pvdim 'f) (pool:pvdim 'e))
                      (list (* 0.10 len) (* 0.20 len)
                            (* 0.32 len) (* 0.38 len))
                      gth)
                hv (car res) gv (cadr res) ev (cadddr res)
                res (pool:pvchain
                      (list (pool:pvdim 'm) (pool:pvdim 'l) (pool:pvdim 'k))
                      (list (* 0.27 wid) (* 0.46 wid) (* 0.27 wid))
                      gtv)
                mv (car res) lv (cadr res) kv (caddr res)
                hx (cond
                     ((not six) nil)
                     ((= mode "Offsets")
                      (list "Offsets" (cond ((pool:pvdim 'co)) (hv))))
                     (t (list "Letters"
                              ;; clamped the way the resolver will
                              ;; clamp them, so a W or L1 typo cannot
                              ;; draw a preview that crosses itself
                              (min (cond ((pool:pvdim 'w)) ((* 0.12 len)))
                                   gv)
                              (min (cond ((pool:pvdim 'l1)) ((* 0.26 wid)))
                                   lv)
                              lv)))
                gg (pool:hopgrecc pts hv gv ev mv kv hx))
          (pool:pvcopen)
          (pool:hopgrecdraw gg "POOL-NOTES" six t)
          (pool:pvctie (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg)) "H" th)
          (pool:pvctie (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg)) "G" th)
          (pool:pvctie (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg)) "F" th)
          (pool:pvctie (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg)) "E" th)
          (pool:pvctie (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg)) "M" th)
          (pool:pvctie (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg)) "L" th)
          (pool:pvctie (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg)) "K" th)
          (if six
              (if (= mode "Offsets")
                  (pool:pvctie
                    (pool:mid (cadr (assoc 'dd gg)) (cadr (assoc 'ltp gg)))
                    (pool:mid (cadr (assoc 'ct2 gg)) (cadr (assoc 'ct1 gg)))
                    "CUT" th)
                  (progn
                    (pool:pvctie (cadr (assoc 'ct1 gg))
                                 (cadr (assoc 'htr gg)) "W" th)
                    (pool:pvctie (cadr (assoc 'ct2 gg))
                                 (cadr (assoc 'cb2 gg)) "L1" th)
                    (pool:pvctie (cadr (assoc 'ct2 gg))
                                 (cadr (assoc 'ct1 gg)) "X" th))))
          (pool:pvcout pts))
        (setq pv (pool:pvlive 'hg:geo))
        (princ "\nPool bottom -- offsets from the end walls; the RED tie is being asked for.")
        (princ "\n(after the first answer, Back re-asks the previous one)")
        ;; wall-to-wall totals through the pool centre, worked out
        ;; BEFORE the questions so the last letter of each chain can be
        ;; suggested as it is reached rather than only resolved after
        (setq cen (list 0.0 0.0))
        (foreach p pts (setq cen (pool:v+ cen p)))
        (setq cen (pool:v* cen 0.125)
              u (pool:v- (nth 1 pts) (nth 0 pts))
              vv (pool:v- (nth 5 pts) (nth 0 pts))
              toth (distance
                     (pool:linex cen u (nth 7 pts) (pool:v- (nth 6 pts) (nth 7 pts)))
                     (pool:linex cen u (nth 2 pts) (pool:v- (nth 3 pts) (nth 2 pts))))
              totv (distance
                     (pool:linex cen vv (nth 0 pts) (pool:v- (nth 1 pts) (nth 0 pts)))
                     (pool:linex cen vv (nth 5 pts) (pool:v- (nth 4 pts) (nth 5 pts))))
              toth2 toth totv2 totv)
        (setq ans (pool:askseq
                    (append
                      (list (list 'h 'NAX "H - left end to hopper" (cdr (assoc "H" pv)))
                            (list 'g 'NAX "G - hopper length" (cdr (assoc "G" pv))))
                      (cond
                        ((not six) nil)
                        ((= mode "Offsets")
                         (list (list 'co 'NAX
                                     "Cut faces - offset in from the pool corner cuts (NA = H)"
                                     (cdr (assoc "CUT" pv)))))
                        (t
                         (list (list 'w 'REQ "W - top/bottom flat, cut corner to hopper end"
                                     (cdr (assoc "W" pv)))
                               (list 'l1 'REQ "L1 - hopper left edge length"
                                     (cdr (assoc "L1" pv)))
                               (list 'x 'NAX "X - hopper cut face length (check)"
                                     (cdr (assoc "X" pv))))))
                      (list (list 'f 'NAX "F - hopper to slope break" (cdr (assoc "F" pv)))
                            (list 'e 'NAX "E - slope break to right end" (cdr (assoc "E" pv))
                                  nil nil nil '(pool:chainrest ans '(h g f) toth2))
                            (list 'm 'SUG "M - top side to hopper" (cdr (assoc "M" pv)) '(h))
                            (list 'l 'NAX "L - hopper width" (cdr (assoc "L" pv))
                                  nil nil nil '(pool:sugsym ans totv2))
                            (list 'k 'SUG "K - hopper to bottom side"
                                  (cdr (assoc "K" pv)) '(m h) nil nil
                                  '(pool:chainrest ans '(m l) totv2)))))
              hraw (pool:sq ans 'h) graw (pool:sq ans 'g)
              coraw (pool:sq ans 'co)
              w (pool:sq ans 'w) l1 (pool:sq ans 'l1) x (pool:sq ans 'x)
              fraw (pool:sq ans 'f) eraw (pool:sq ans 'e)
              mraw (pool:sq ans 'm) lraw (pool:sq ans 'l) kraw (pool:sq ans 'k))
        (pool:pvkill)
        ;; resolve against the wall-to-wall totals measured out above
        (setq hres (pool:chainfix (list hraw graw fraw eraw) toth 1)
              vres (pool:chainfix (list mraw lraw kraw) totv 1)
              cv (pool:chainval hres toth) hres (car cv) hfx (cadr cv)
              cv (pool:chainval vres totv) vres (car cv) vfx (cadr cv)
              h (car hres) g (cadr hres) f (caddr hres) e (cadddr hres)
              m (car vres) l (cadr vres) k (caddr vres))
        (if hfx (pool:valnote (strcat "BOTTOM LENGTHS FAILED - "
                                      (pool:fixnames hfx '("H" "G" "F" "E"))
                                      " ADJUSTED, VERIFY")))
        (if vfx (pool:valnote (strcat "BOTTOM WIDTHS FAILED - "
                                      (pool:fixnames vfx '("M" "L" "K"))
                                      " ADJUSTED, VERIFY")))
        ;; six-sided closure checks, per input method
        (if (and six (= mode "Offsets"))
            (setq co (if coraw coraw h)))
        (if (and six (= mode "Letters"))
            (progn
              (if (> w g)
                  (progn (setq w g sixbad t)
                         (pool:valnote "HOPPER W LONGER THAN G - ADJUSTED")))
              (if (> l1 l)
                  (progn (setq l1 l sixbad t)
                         (pool:valnote "HOPPER L1 LONGER THAN L - ADJUSTED")))
              (setq xcal (sqrt (+ (* (- g w) (- g w))
                                  (* (* 0.5 (- l l1)) (* 0.5 (- l l1))))))
              (if (and x (> (abs (- x xcal)) 0.5))
                  (progn (setq sixbad t)
                         (pool:valnote "HOPPER CUT X DOES NOT CLOSE AGAINST W/L1 - VERIFY")))))
        (setq gg (pool:hopgrecc pts h g e m k
                                (cond
                                  ((not six) nil)
                                  ((= mode "Offsets") (list "Offsets" co))
                                  (t (list "Letters" w l1 l)))))
        (pool:hopgrecdraw gg "POOL" six nil)
        (setq odl (getvar "CLAYER"))
        (setvar "CLAYER" "DIMENSION")
        (foreach tl (list (list 'pl 'phl nil (member 0 hfx))
                          (list 'phl 'phr nil (member 1 hfx))
                          (list 'phr 'pbrk nil (member 2 hfx))
                          (list 'pbrk 'pr nil (member 3 hfx))
                          (list 'pht 'pt t (member 0 vfx))
                          (list 'phb 'pht t (member 1 vfx))
                          (list 'pb 'phb t (member 2 vfx)))
          (pool:dimalg (cadr (assoc (car tl) gg)) (cadr (assoc (cadr tl) gg))
                       (pool:v+ (pool:mid (cadr (assoc (car tl) gg))
                                          (cadr (assoc (cadr tl) gg)))
                                (if (caddr tl) (cadr (assoc 'voff gg))
                                    (list 0.0 0.0))))
          (if (cadddr tl) (pool:dimred)))
        (if six
            (if (= mode "Offsets")
                ;; one offset dim per cut face, square off the pool
                ;; cut -- hopper cut letters read in SIDE STANDARD,
                ;; per the reference sheet
                (foreach tl (list (list 'ct1 'ct2 'dd 'ltp)
                                  (list 'cb1 'cb2 'aa 'lbp))
                  (setq mm (pool:mid (cadr (assoc (car tl) gg))
                                     (cadr (assoc (cadr tl) gg)))
                        ud (pool:unit (pool:v- (cadr (assoc (cadddr tl) gg))
                                               (cadr (assoc (caddr tl) gg))))
                        proj (pool:v+ (cadr (assoc (caddr tl) gg))
                                      (pool:v* ud (pool:dot
                                        (pool:v- mm (cadr (assoc (caddr tl) gg)))
                                        ud))))
                  (pool:dimalgs proj mm (pool:mid proj mm))
                  (if sixbad (pool:dimred)))
                ;; the sheet letters: W flat, L1 left edge, X on a
                ;; face -- all SIDE STANDARD, per the reference sheet
                (progn
                  (pool:dimalgs (cadr (assoc 'ct1 gg)) (cadr (assoc 'htr gg))
                                (pool:mid (cadr (assoc 'ct1 gg)) (cadr (assoc 'htr gg))))
                  (if sixbad (pool:dimred))
                  (pool:dimalgs (cadr (assoc 'ct2 gg)) (cadr (assoc 'cb2 gg))
                                (pool:mid (cadr (assoc 'ct2 gg)) (cadr (assoc 'cb2 gg))))
                  (if sixbad (pool:dimred))
                  (pool:dimalgs (cadr (assoc 'cb2 gg)) (cadr (assoc 'cb1 gg))
                                (pool:mid (cadr (assoc 'cb2 gg)) (cadr (assoc 'cb1 gg))))
                  (if sixbad (pool:dimred)))))
        (setvar "CLAYER" odl)
        (setq rows (list
          (pool:vrow "HOP H" hraw (distance (cadr (assoc 'pl gg)) (cadr (assoc 'phl gg))) 0 hfx)
          (pool:vrow "HOP G" graw (distance (cadr (assoc 'phl gg)) (cadr (assoc 'phr gg))) 1 hfx)
          (pool:vrow "HOP F" fraw (distance (cadr (assoc 'phr gg)) (cadr (assoc 'pbrk gg))) 2 hfx)
          (pool:vrow "HOP E" eraw (distance (cadr (assoc 'pbrk gg)) (cadr (assoc 'pr gg))) 3 hfx)
          (pool:vrow "HOP M" mraw (distance (cadr (assoc 'pht gg)) (cadr (assoc 'pt gg))) 0 vfx)
          (pool:vrow "HOP L" lraw (distance (cadr (assoc 'phb gg)) (cadr (assoc 'pht gg))) 1 vfx)
          (pool:vrow "HOP K" kraw (distance (cadr (assoc 'pb gg)) (cadr (assoc 'phb gg))) 2 vfx)))
        (if six
            (setq rows (append rows
              (if (= mode "Offsets")
                  ;; actual = the drawn face's true perpendicular
                  ;; offset from the pool's corner cut
                  (progn
                    (setq mm (pool:mid (cadr (assoc 'ct2 gg)) (cadr (assoc 'ct1 gg)))
                          ud (pool:unit (pool:v- (cadr (assoc 'ltp gg))
                                                 (cadr (assoc 'dd gg))))
                          proj (pool:v+ (cadr (assoc 'dd gg))
                                        (pool:v* ud (pool:dot
                                          (pool:v- mm (cadr (assoc 'dd gg))) ud))))
                    (list (list "HOP CUT OFF" coraw (distance proj mm))))
                  (list
                    (append (list "HOP W" w (distance (cadr (assoc 'ct1 gg))
                                                      (cadr (assoc 'htr gg))))
                            (if sixbad (list t) nil))
                    (append (list "HOP L1" l1 (distance (cadr (assoc 'ct2 gg))
                                                        (cadr (assoc 'cb2 gg))))
                            (if sixbad (list t) nil))
                    (append (list "HOP X" x (distance (cadr (assoc 'ct2 gg))
                                                      (cadr (assoc 'ct1 gg))))
                            (if sixbad (list t) nil)))))))
        rows)))

;; Body quad spanning two end lines and the two side lines: the frame
;; the special bottoms measure their chain off for the shapes whose
;; ends are not plain corners.
(defun pool:bodyquad (lline rline bline tline)
  (list (pool:linex (car lline) (cadr lline) (car bline) (cadr bline))
        (pool:linex (car rline) (cadr rline) (car bline) (cadr bline))
        (pool:linex (car rline) (cadr rline) (car tline) (cadr tline))
        (pool:linex (car lline) (cadr lline) (car tline) (cadr tline))))

;; Bottom-type dispatchers for oval and grecian pools.  Normal keeps
;; each shape's own field sheet (radius end / corner cuts); the four
;; special bottoms are the standard chain measured off the body, so
;; they work here too.

(defun pool:hopovaldsp (quad tipl tipr doff th / btype u v sres p xi
                                                 lline rline bline tline)
  (if (not (pool:askbottom))
      nil
      (progn
        (setq btype (pool:askkwf 'btype "Bottom type"
                                 pool:*btypes* pool:*btshown*
                                 "Normal" nil))
        (setq u (pool:unit (pool:v- tipr tipl))
              v (pool:perp u)
              lline (list tipl v)
              rline (list tipr v)
              bline (list (car quad) (pool:v- (cadr quad) (car quad)))
              tline (list (cadddr quad)
                          (pool:v- (caddr quad) (cadddr quad))))
        (cond
          ((= btype "Normal") (pool:hopoval quad tipl tipr doff th))
          ;; the oval's ends are arcs, so there are no left corners to
          ;; tie the deep end back to
          ((/= btype "Sport")
           (pool:hopnormal (pool:bodyquad lline rline bline tline)
                           pool:*sq4* doff th nil btype
                           (min (car tipl) (car tipr))
                           (- (apply 'min (mapcar 'cadr quad)) (* 2.2 doff))
                           nil))
          (t
            (pool:hopsport (list tipl v) (list tipr v)
                             (list (car quad) (pool:v- (cadr quad) (car quad)))
                             (list (cadddr quad)
                                   (pool:v- (caddr quad) (cadddr quad)))
                             (pool:v* (pool:v+ (pool:v+ (car quad) (cadr quad))
                                               (pool:v+ (caddr quad) (cadddr quad)))
                                      0.25)
                             (distance tipl tipr)
                             (min (car tipl) (car tipr))
                             (- (apply 'min (mapcar 'cadr quad)) (* 2.2 doff))
                             (apply 'max (mapcar 'cadr quad))
                             doff th))))))

(defun pool:hopgrecdsp (pts doff th / btype cen p u pl pr sres xi ln
                                      lline rline bline tline)
  (if (not (pool:askbottom))
      nil
      (progn
        (setq btype (pool:askkwf 'btype "Bottom type"
                                 pool:*btypes* pool:*btshown*
                                 "Normal" nil))
        (setq cen (list 0.0 0.0))
        (foreach p pts (setq cen (pool:v+ cen p)))
        (setq cen (pool:v* cen 0.125)
              u (pool:v- (nth 1 pts) (nth 0 pts))
              lline (list (nth 7 pts) (pool:v- (nth 6 pts) (nth 7 pts)))
              rline (list (nth 2 pts) (pool:v- (nth 3 pts) (nth 2 pts)))
              bline (list (nth 0 pts) (pool:v- (nth 1 pts) (nth 0 pts)))
              tline (list (nth 5 pts) (pool:v- (nth 4 pts) (nth 5 pts)))
              pl (pool:linex cen u (car lline) (cadr lline))
              pr (pool:linex cen u (car rline) (cadr rline)))
        (cond
          ((= btype "Normal") (pool:hopgrec pts doff th))
          ((/= btype "Sport")
           ;; the deep end ties to BOTH ends of each left corner cut,
           ;; exactly as the Grecian's own hopper does
           (pool:hopnormal (pool:bodyquad lline rline bline tline)
                           (list (list "Ends" (nth 7 pts) (nth 0 pts))
                                 (list "Square" 0.0)
                                 (list "Square" 0.0)
                                 (list "Ends" (nth 5 pts) (nth 6 pts)))
                           doff th nil btype
                           (apply 'min (mapcar 'car pts))
                           (- (apply 'min (mapcar 'cadr pts)) (* 2.2 doff))
                           t))
          (t
            (pool:hopsport lline rline bline tline
                             cen (distance pl pr)
                             (apply 'min (mapcar 'car pts))
                             (- (apply 'min (mapcar 'cadr pts)) (* 2.2 doff))
                             (apply 'max (mapcar 'cadr pts))
                             doff th))))))

;;; -------------------- oval ends --------------------------------------
;;;
;;;  R1/R2 are TRUE arc radii: each end arc springs from the two end
;;;  corners (chord c = the end length) and bulges past them by the
;;;  sagitta  s = R - sqrt(R^2 - (c/2)^2).  Dimensioning the drawn arc
;;;  therefore reads back the radius that was typed in.

;; Bulge of an arc of radius r spanning a chord c.  An r smaller than
;; the chord's half cannot reach across it, so it is clamped to the
;; semicircle (the tightest arc that end can have).
(defun pool:sag (r c / half)
  (setq half (* 0.5 c))
  (if (<= r half) half (- r (sqrt (- (* r r) (* half half))))))

;; The inverse: radius of the arc that bulges s past a chord c.
(defun pool:sagr (s c / half)
  (setq half (* 0.5 c))
  (if (<= s 1.0e-9) nil (/ (+ (* s s) (* half half)) (* 2.0 s))))

;; The straight body the overall leaves -- the same chain read the
;; other way, for the sheet that gives the overall and the width but
;; never taped the sides.  Each end spends its own bulge out of the
;; overall and what is left over is the side.  A radius that WAS given
;; sets its own bulge; one that was not is taken TANGENT to the box the
;; pool sits in -- an arc that meets the sides square, i.e. the
;; semicircle s = c/2, which is exactly what a true oval is.  Returns
;; nil when the overall does not reach past the two ends at all.
(defun pool:ovalaxis (totl lraw rraw lc rc / v)
  (if totl
      (progn
        (setq v (- totl
                   (+ (if lraw (pool:sag lraw lc) (* 0.5 lc))
                      (if rraw (pool:sag rraw rc) (* 0.5 rc)))))
        (if (> v 1.0e-6) v nil))))

;; Resolve the two end arcs against the overall length.  The overall
;; closes the chain  s_left + axis + s_right = TOTAL, so any one of
;; TOTAL / R1 / R2 may be NA:
;;   * both radii NA -> the remainder splits evenly between the ends,
;;     i.e. both arcs the same -- exactly what an in-square oval is;
;;   * one radius NA -> it takes the remainder;
;;   * TOTAL NA      -> it is computed from the two radii.
;; lc/rc are the end lengths (chords).  Returns (lrad rrad sl sr total notes).
(defun pool:ovalends (totl lraw rraw axis lc rc / sl sr left notes lr rr)
  (if (and lraw rraw)
      (setq sl (pool:sag lraw lc)
            sr (pool:sag rraw rc))
      (progn
        (setq left (- totl axis))       ; length left over for the ends
        (cond
          ((and (null lraw) (null rraw))
           (setq sl (* 0.5 left) sr (* 0.5 left)))
          ((null lraw)
           (setq sr (pool:sag rraw rc) sl (- left sr)))
          (t
           (setq sl (pool:sag lraw lc) sr (- left sl))))))
  ;; a bulge that came out at or below zero means the overall and the
  ;; body disagree; fall back to the semicircle and say so
  (if (<= sl 1.0e-6)
      (setq sl (* 0.5 lc)
            notes (cons "LEFT END DOES NOT FIT THE TOTAL LENGTH - SEMICIRCLE USED" notes)))
  (if (<= sr 1.0e-6)
      (setq sr (* 0.5 rc)
            notes (cons "RIGHT END DOES NOT FIT THE TOTAL LENGTH - SEMICIRCLE USED" notes)))
  ;; a radius tighter than the end is half its width was clamped above
  (if (and lraw (< lraw (- (* 0.5 lc) 1.0e-6)))
      (setq notes (cons "LEFT RADIUS SMALLER THAN HALF THE END - SEMICIRCLE USED" notes)))
  (if (and rraw (< rraw (- (* 0.5 rc) 1.0e-6)))
      (setq notes (cons "RIGHT RADIUS SMALLER THAN HALF THE END - SEMICIRCLE USED" notes)))
  (setq lr (pool:sagr sl lc)
        rr (pool:sagr sr rc))
  (list lr rr sl sr (+ sl axis sr) notes))

;;; -------------------- rectangle / oval flow --------------------------

;; Full guided flow for the quad-based pools: preview, prompts, fit,
;; draw, dimension and report.  Caller handles sysvars/undo/zoom.
(defun pool:quadflow (ptype / oldclay pv arcs
                             tp bo le ri dac dbd totl lrad rrad tpna bona
                             corners cmode anycut cc prevty prevsz lbl
                             gq gcorners xmeas xg tm hl val m rpa rpb pass
                             ans xitems cc2
                             fitres quad failed a b c d cen meas notes tri
                             doff th endoff pr odim k
                             midl midr ml mr tipl tipr
                             ores lrfit rrfit larc rarc
                             allpts xmax ymax ymin rows rbox mprims)
  (setq oldclay (getvar "CLAYER"))

  ;; The live guide geometry (see "live guide reshaping"): each side
  ;; borrows its unanswered partner, then the 360 x 180 nominal, and
  ;; the quad is fit the way the final fit will hold it -- so once the
  ;; cross dims start coming in, the guide leans out of square in
  ;; front of the user.  gq keeps the quad the guide sits on: the
  ;; corner-treatment guides and the cross-dim reference points ride
  ;; the same shape the user is looking at.
  (defun qf:geo ( / bov tpv lev riv xac xbd q qa qb qc qd cen2 sc hgt
                    spec km k tm s cl cr axis ml2 mr2 midl2 midr2
                    extl extr left tot lr rr tipl2 tipr2 o1 o2)
    (setq bov (cond ((pool:pvdim 'bo)) ((pool:pvdim 'tp)) (360.0))
          tpv (cond ((pool:pvdim 'tp)) ((pool:pvdim 'bo)) (360.0))
          lev (cond ((pool:pvdim 'le)) ((pool:pvdim 'ri))
                    ((* 0.25 (+ bov tpv))))
          riv (cond ((pool:pvdim 'ri)) ((pool:pvdim 'le)) (lev)))
    ;; cross dims answered so far, averaged per diagonal like the
    ;; bootstrap pool:rawavg
    (if cmode
        (progn
          (setq k 0)
          (foreach tm (pool:crosstemplate cmode)
            (setq s (pool:pvdim (read (strcat "x" (itoa k)))))
            (if s
                (if (eq (car tm) 'ac)
                    (setq xac (if xac (* 0.5 (+ xac s)) s))
                    (setq xbd (if xbd (* 0.5 (+ xbd s)) s))))
            (setq k (1+ k)))))
    (setq q (pool:fitsides bov tpv lev riv xac xbd))
    (if (null q)
        (setq q (list (list 0.0 0.0) (list bov 0.0)
                      (list bov (* 0.5 (+ lev riv))) (list 0.0 lev))))
    (setq gq q
          qa (car q) qb (cadr q) qc (caddr q) qd (cadddr q)
          cen2 (pool:v* (pool:v+ (pool:v+ qa qb) (pool:v+ qc qd)) 0.25)
          sc (/ (max bov tpv lev riv) 360.0)
          hgt (* 12.0 sc)
          spec (list (list "LINE" qa qb) (list "LINE" qb qc)
                     (list "LINE" qd qc) (list "LINE" qd qa))
          km (list (list 'ab 0) (list 'bc 1) (list 'dc 2) (list 'da 3)
                   (list 'lA 4) (list 'lB 5) (list 'lC 6) (list 'lD 7)))
    (foreach tm (list (list qa "A") (list qb "B") (list qc "C")
                      (list qd "D"))
      (setq spec (append spec
                   (list (list "TEXT"
                               (pool:v+ (car tm)
                                        (pool:v* (pool:unit
                                                   (pool:v- (car tm) cen2))
                                                 (* 20.0 sc)))
                               hgt (cadr tm))))))
    (if (= ptype "Oval")
        (progn
          ;; ends resolved the way the final pool:ovalends will: a
          ;; radius sets its own bulge (semicircle when NA), and a
          ;; given overall re-spends what the body leaves over
          (setq tot (pool:pvdim 'tot) lr (pool:pvdim 'lr)
                rr (pool:pvdim 'rr)
                midl2 (pool:mid qa qd) midr2 (pool:mid qb qc)
                cl (distance qa qd) cr (distance qb qc)
                axis (distance midl2 midr2)
                ml2 (pool:unit (pool:perp (pool:v- qd qa)))
                mr2 (pool:unit (pool:perp (pool:v- qc qb))))
          (if (< (pool:dot (pool:v- midl2 cen2) ml2) 0.0)
              (setq ml2 (pool:v* ml2 -1.0)))
          (if (< (pool:dot (pool:v- midr2 cen2) mr2) 0.0)
              (setq mr2 (pool:v* mr2 -1.0)))
          (setq extl (if lr (pool:sag lr cl) (* 0.5 cl))
                extr (if rr (pool:sag rr cr) (* 0.5 cr)))
          (if tot
              (progn
                (setq left (- tot axis))
                (cond
                  ((and lr rr) nil)     ; both pinned; the total is a check
                  ((and (null lr) (null rr))
                   (if (> left 1.0e-6) (setq extl (* 0.5 left) extr extl)))
                  ((null lr)
                   (if (> (- left extr) 1.0e-6) (setq extl (- left extr))))
                  (t
                   (if (> (- left extl) 1.0e-6)
                       (setq extr (- left extl)))))))
          ;; the radius lines run from each arc's centre to its tip, so
          ;; they read as the true radius that is being asked for
          (setq tipl2 (pool:v+ midl2 (pool:v* ml2 extl))
                tipr2 (pool:v+ midr2 (pool:v* mr2 extr))
                o1 (pool:circum qa tipl2 qd)
                o2 (pool:circum qb tipr2 qc)
                spec (append spec
                       (list (list "LINED" (if o1 o1 midl2) tipl2)
                             (list "LINED" (if o2 o2 midr2) tipr2)
                             (list "ARC" qa tipl2 qd)
                             (list "ARC" qb tipr2 qc)
                             (list "LINED" tipl2 tipr2)))
                km (append km (list (list 'lrad 8 10) (list 'rrad 9 11)
                                    (list 'tot 12))))))
    (list spec km (pool:pvspecbox spec)))

  ;; what the generic reshape cannot move: the corner-treatment guides
  ;; are recreated on the live quad, and the cross-dim guide lines are
  ;; walked onto their reference points on it
  (defun qf:more ( / k tm)
    (if (and anycut gcorners) (setq pv (pool:pvcorners pv gq gcorners)))
    (if (and xg cmode)
        (progn
          (setq k 0)
          (foreach tm (pool:crosstemplate cmode)
            (if (nth k xg)
                (pool:pvmod (nth k xg)
                            (list "LINED"
                                  (pool:cornerpoint gq gcorners (nth 3 tm)
                                                    (nth 4 tm))
                                  (pool:cornerpoint gq gcorners (nth 5 tm)
                                                    (nth 6 tm)))))
            (setq k (1+ k))))))

  ;; -------------------------------------- guide preview + input
  (setq pv (pool:pvlive 'qf:geo)
        pool:*pvmore* 'qf:more)
  (princ "\nA gray guide pool is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C top-right, D top-left.")

  ;; in-square: opposing sides are equal, ask each pair once
  (princ "\n(Back re-asks the previous question, right back to the start)")
  ;; An OVAL's sides are the one pair that may be NA: the overall and
  ;; the two ends read them back (qf:ovalsides).  The ends themselves
  ;; are always required -- they are the chords the arcs spring from.
  ;; The END is the pool's WIDTH, and a pool is typically about twice
  ;; as long as it is wide -- so on a RECTANGLE it is offered half the
  ;; side rather than asked cold (pool:sughalf).  Enter takes the
  ;; offer, anything typed wins over it, and the offer only stands
  ;; once a side is actually in.  Not on an OVAL: its overall spends
  ;; length on the two end bulges, so half the straight SIDE is not
  ;; half the pool.
  (defun qf:sides ( / ans sk)
  (setq sk (if (= ptype "Oval") 'NAX 'REQ))
  (if pool:*insq*
      (setq ans (pool:askseqb
                  (list (list 'tp sk "Side length (top & bottom)"
                              (append (cdr (assoc 'dc pv)) (cdr (assoc 'ab pv))
                                      (pool:lbl pv '(lA lB lC lD))))
                        (list 'le 'REQ "End length (left & right)"
                              (append (cdr (assoc 'da pv)) (cdr (assoc 'bc pv))
                                      (pool:lbl pv '(lA lB lC lD)))
                              nil nil nil
                              (if (= ptype "Rectangle")
                                  '(pool:sughalf ans '(tp)))))
                  nil)
            tp (pool:sq ans 'tp) bo tp
            le (pool:sq ans 'le) ri le)
      (setq ans (pool:askseqb
                  (list (list 'tp sk "Side length TOP (D-C)"
                              (append (cdr (assoc 'dc pv)) (pool:lbl pv '(lD lC))))
                        (list 'bo sk "Side length BOTTOM (A-B)"
                              (append (cdr (assoc 'ab pv)) (pool:lbl pv '(lA lB))))
                        (list 'le 'REQ "End length LEFT (A-D)"
                              (append (cdr (assoc 'da pv)) (pool:lbl pv '(lA lD)))
                              nil nil nil
                              (if (= ptype "Rectangle")
                                  '(pool:sughalf ans '(tp bo))))
                        (list 'ri 'REQ "End length RIGHT (B-C)"
                              (append (cdr (assoc 'bc pv)) (pool:lbl pv '(lB lC)))
                              nil nil nil
                              (if (= ptype "Rectangle")
                                  '(pool:sughalf ans '(tp bo)))))
                  nil)
            tp (pool:sq ans 'tp) bo (pool:sq ans 'bo)
            le (pool:sq ans 'le) ri (pool:sq ans 'ri)))
    ;; re-flagged on every run, so backing in and out re-derives cleanly
    (setq tpna (null tp) bona (null bo))
    ans)

  ;; -------- oval ends.  Any ONE of total / left radius / right radius
  ;; may be NA -- the overall closes the chain against the body, and
  ;; with both radii NA the two ends come out the same (the in-square
  ;; oval).  Only the total is re-asked when too much is missing.
  (defun qf:oval ( / ans)
  (if (/= ptype "Oval")
      nil
      (progn
        ;; in-square ovals are symmetric, so the end radius is asked once
        (setq ans (pool:askseqb
                    (if pool:*insq*
                        (list (list 'tot 'NAX "Total pool length (arc tip to arc tip)"
                                    (cdr (assoc 'tot pv)))
                              (list 'lr 'NAX "End radius (both ends)"
                                    (append (cdr (assoc 'lrad pv))
                                            (cdr (assoc 'rrad pv)))))
                        (list (list 'tot 'NAX "Total pool length (arc tip to arc tip)"
                                    (cdr (assoc 'tot pv)))
                              (list 'lr 'NAX "LEFT oval end radius"
                                    (cdr (assoc 'lrad pv)))
                              (list 'rr 'NAX "RIGHT oval end radius"
                                    (cdr (assoc 'rrad pv)))))
                    t))
        (if (eq ans 'POOL-BACK)
            'POOL-BACK
            (progn
              (setq totl (pool:sq ans 'tot)
                    lrad (pool:sq ans 'lr)
                    rrad (if pool:*insq* lrad (pool:sq ans 'rr)))
              (if (and (null totl)
                       (or (null lrad) (null rrad) tpna bona))
                  (progn
                    (princ (if (or tpna bona)
                               "\nThe total length is needed when a side length is NA."
                               "\nThe total length is needed when an end radius is NA."))
                    (setq totl (pool:askh "Total pool length (arc tip to arc tip)"
                                          (cdr (assoc 'tot pv))))
                    (pool:pvnote 'tot totl)))
              (if (or tpna bona) (qf:ovalsides))
              nil)))))

  ;; -------- sides that were never taped.  An oval spends its overall
  ;; on the two end bulges plus the straight body, so a side that was
  ;; NA reads back out of the overall and the ends (pool:ovalaxis --
  ;; a radius that was not given is taken tangent, i.e. a semicircle,
  ;; so overall - width is the side).  BOTH NA -> the body is that
  ;; length and the oval comes out symmetric; ONE NA -> the overall
  ;; pins the MIDLINE between the ends, so the missing side is the
  ;; derived length mirrored about the one that was measured.
  (defun qf:ovalsides ( / ax v)
    (setq ax (pool:ovalaxis totl lrad rrad le ri))
    (cond
      ;; the overall does not even reach past the two ends -- nothing
      ;; to read the side out of, so it has to be measured
      ((null ax)
       (princ "\nThe total length does not reach past the ends -- measure the side.")
       (if pool:*insq*
           (setq tp (pool:askh "Side length (top & bottom)"
                               (append (cdr (assoc 'dc pv))
                                       (cdr (assoc 'ab pv))))
                 bo tp)
           (progn
             (if tpna (setq tp (pool:askh "Side length TOP (D-C)"
                                          (cdr (assoc 'dc pv)))))
             (if bona (setq bo (pool:askh "Side length BOTTOM (A-B)"
                                          (cdr (assoc 'ab pv)))))))
       (setq tpna nil bona nil))
      ((and tpna bona)
       (setq tp ax bo ax)
       (princ (strcat "\nSide length not measured -- " (pool:fmtlen ax)
                      " off the overall and the ends.")))
      (t
       (setq v (- (* 2.0 ax) (if tpna bo tp)))
       (if (<= v 1.0e-6)
           (progn
             (pool:valnote "SIDE AND TOTAL LENGTH DISAGREE - MISSING SIDE TAKEN OFF THE TOTAL")
             (setq v ax)))
       (if tpna (setq tp v) (setq bo v))
       (princ (strcat "\n" (if tpna "TOP" "BOTTOM") " side not measured -- "
                      (pool:fmtlen v) " closes the overall against the other side."))))
    ;; the guide takes the read-back sides too, so it closes up the
    ;; way the drawn pool will
    (pool:pvnote 'tp tp)
    (pool:pvnote 'bo bo))

  ;; -------- corner treatments (rectangle only; side lengths are to
  ;; the TRUE corner, treatments cut inward)
  (defun qf:corners ( / i lbls out back)
    (if (/= ptype "Rectangle")
        (progn
          (setq corners (list (list "Square" 0.0) (list "Square" 0.0)
                              (list "Square" 0.0) (list "Square" 0.0)))
          (qf:aftercorners)
          nil)
        (if pool:*insq*
            (progn                      ; in-square: one answer for all 4
              (setq cc (pool:askcorner "all four corners" nil nil
                                       (pool:lbl pv '(lA lB lC lD))
                                       (* 0.5 (min tp le)) nil t))
              (if (eq cc 'POOL-BACK)
                  'POOL-BACK
                  (progn (setq corners (list cc cc cc cc))
                         (qf:aftercorners)
                         nil)))
            (progn                      ; out-of-square: per corner, Enter reuses
              (princ "\n(per-corner treatment; press Enter to reuse the previous corner)")
              (setq lbls (list (list "A" bo le) (list "B" bo ri)
                               (list "C" tp ri) (list "D" tp le))
                    corners nil prevty nil prevsz nil i 0 back nil)
              (while (and (< i 4) (not back))
                (setq cc (pool:askcorner
                           (strcat "Corner " (car (nth i lbls))) prevty prevsz
                           (pool:lbl pv (list (pool:lblkey (car (nth i lbls)))))
                           (* 0.5 (min (cadr (nth i lbls)) (caddr (nth i lbls))))
                           nil t))
                (if (eq cc 'POOL-BACK)
                    (if (= i 0)
                        (setq back t)   ; back out of the whole stage
                        (setq i (1- i)
                              corners (cdr corners)
                              ;; the reuse default is the corner BEFORE
                              ;; the one being re-asked
                              prevty (if corners (car (car corners)) nil)
                              prevsz (if corners (cadr (car corners)) nil)))
                    (setq prevty (car cc) prevsz (cadr cc)
                          corners (cons cc corners)
                          i (1+ i))))
              (if back
                  'POOL-BACK
                  (progn (setq corners (reverse corners))
                         (qf:aftercorners)
                         nil))))))

  ;; everything the corner answers determine: the cut flag and the
  ;; guide redraw.  Re-runnable, so backing in and out is safe.  The
  ;; guide sits on the live quad qf:geo keeps in gq, so the treatments
  ;; are drawn at their real sizes -- pool:askcorner has already
  ;; capped each against its own walls.
  (defun qf:aftercorners ( / c)
    (setq anycut nil)
    (foreach c corners (if (pool:cutp (car c)) (setq anycut t)))
    (setq gcorners corners)
    (if anycut (setq pv (pool:pvcorners pv gq gcorners)))
    (princ))

  ;; -------- cross-dim reference mode (only when corners are cut and
  ;; the pool is out-of-square)
  (defun qf:cmode ( / v)
    (setq cmode "Corner")
    (if (and (not pool:*insq*) anycut)
        (progn
          ;; a bare "Cut corners" would now read as the Cut keyword, and
          ;; this gate covers Radius corners too -- but NOT NotGiven,
          ;; which has no treatment ends to tape between
          (setq v (pool:askkwf 'cmode
                               "Radius/Cut corners -- cross dims measured from"
                               "Corner Middle Ends" "Corner/Middle/Ends" nil t))
          (if (eq v 'POOL-BACK) v (progn (setq cmode v) nil)))
        nil))

  ;; -------- cross dims (out-of-square only), per the reference mode.
  ;; The corner-to-corner guide diagonals are retired and one dashed
  ;; guide line is drawn per measurement between its actual reference
  ;; points, so Middle/Ends prompts highlight exactly what gets taped.
  (defun qf:cross ( / )
    (setq xmeas nil xg nil)
    (if pool:*insq*
        (progn
          (princ "\nIn-square: building true to the side measurements (no cross dims).")
          nil)
        (progn
          ;; sides are all in -- the cross dims appear now, one guide
          ;; line per measurement, between its actual reference points,
          ;; then the block runs as one Back-able sequence.  xg holds
          ;; the lines in template order so qf:more can walk them onto
          ;; the quad as their own answers reshape it.
          (setq xitems nil k 0)
          (foreach tm (pool:crosstemplate cmode)
            (setq rpa (pool:cornerpoint gq gcorners (nth 3 tm) (nth 4 tm))
                  rpb (pool:cornerpoint gq gcorners (nth 5 tm) (nth 6 tm))
                  hl (pool:pvadd (pool:pvlined rpa rpb))
                  xg (cons hl xg)
                  xitems (cons (list (read (strcat "x" (itoa k))) 'NAX (cadr tm)
                                     (cons hl (pool:lbl pv
                                       (list (pool:lblkey (nth (nth 3 tm) '("A" "B" "C" "D")))
                                             (pool:lblkey (nth (nth 5 tm) '("A" "B" "C" "D")))))))
                               xitems)
                  k (1+ k)))
          (setq xg (reverse xg)
                ans (pool:askseqb (reverse xitems) t))
          (if (eq ans 'POOL-BACK)
              ;; drop this round's guide lines so a re-entry redraws
              ;; them cleanly for whatever mode is chosen next
              (progn (pool:pvdel xg) (setq xg nil) 'POOL-BACK)
              (progn
                (setq k 0)
                (foreach tm (pool:crosstemplate cmode)
                  (setq xmeas (cons (append tm
                                            (list (pool:sq ans (read (strcat "x" (itoa k))))))
                                    xmeas)
                        k (1+ k)))
                (setq xmeas (reverse xmeas))
                nil)))))

  ;; ---- the input phase, with Back working right across it
  (pool:stages (list 'qf:sides 'qf:oval 'qf:corners 'qf:cmode 'qf:cross))


  ;; the guide has served its purpose -- replace it with the true pool
  (pool:pvkill)

  ;; ------------------------------------------------ fit the body
  ;; bootstrap the true-corner cross targets from the raw measurements,
  ;; then (for cut corners) refine them against the fitted corner
  ;; reference points and re-fit.
  (princ "\nFitting pool body to the measurements ...")
  (setq dac (pool:rawavg xmeas 'ac)
        dbd (pool:rawavg xmeas 'bd)
        fitres (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
        quad (car fitres)
        failed (cadr fitres))
  (if (/= cmode "Corner")
      (progn
        (setq pass 0)
        (while (< pass 2)
          (setq dac (pool:effcross quad corners xmeas 'ac)
                dbd (pool:effcross quad corners xmeas 'bd)
                fitres (pool:fitquad bo tp le ri dac dbd pool:*side-tol* pool:*cross-tol*)
                quad (car fitres)
                failed (cadr fitres)
                pass (1+ pass)))))
  (setq a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        meas (pool:quadmeas quad)
        notes nil)

  ;; dashed linetype + scale for the reference lines
  (setq pool:*dashlt* (pool:ltload "DASHED"))

  ;; -------------------------------- pool body / perimeter (layer POOL)
  ;; Rectangle draws its perimeter with corner treatments.  The oval's
  ;; end chords are construction, not pool, so only the two sides are
  ;; drawn and the perimeter closes through the end arcs.
  (if (= ptype "Rectangle")
      (setq arcs (pool:drawrect quad corners))
      (progn
        (pool:line a b "POOL")
        (pool:line c d "POOL")))

  ;; -------------------------------------- exact two-triangle check
  ;; Computed only (needs the A-C cross dim -- skipped when it was NA);
  ;; the result feeds the TRI CHECK B-D report row.  The check figure
  ;; itself is no longer drawn so out-of-square pools leave a clean
  ;; drawing behind.
  (setq tri (if dac (pool:triquad bo tp le ri dac) nil))
  (if (and dac (not tri))
      (setq notes (cons "TRIANGLE CHECK IMPOSSIBLE - VERIFY MEASUREMENTS" notes)))

  (setq doff (max 12.0 (/ (max bo tp le ri) 18.0))
        th (max 3.0 (/ (max bo tp le ri) 70.0)))

  ;; ------------------------------------------------ oval ends
  ;; The arcs are built from the resolved radii (sagitta off each end
  ;; chord), so dimensioning them reads back the radius that was typed.
  (if (= ptype "Oval")
      (progn
        (setq midl (pool:mid a d)
              ml (pool:unit (pool:perp (pool:v- d a))))
        (if (< (pool:dot (pool:v- midl cen) ml) 0.0)
            (setq ml (pool:v* ml -1.0)))
        (setq midr (pool:mid b c)
              mr (pool:unit (pool:perp (pool:v- c b))))
        (if (< (pool:dot (pool:v- midr cen) mr) 0.0)
            (setq mr (pool:v* mr -1.0)))
        (setq ores (pool:ovalends totl lrad rrad (distance midl midr)
                                  (distance a d) (distance b c))
              lrfit (car ores) rrfit (cadr ores)
              notes (append (nth 5 ores) notes)
              tipl (pool:v+ midl (pool:v* ml (caddr ores)))
              tipr (pool:v+ midr (pool:v* mr (cadddr ores))))
        (pool:arc3p a tipl d "POOL")
        (setq larc (entlast))
        (pool:arc3p b tipr c "POOL")
        (setq rarc (entlast))))

  ;; ------------------------------------------------ extents
  (setq allpts (append quad
                       (if tipl (list tipl tipr) nil))
        xmax (apply 'max (mapcar 'car allpts))
        ymax (apply 'max (mapcar 'cadr allpts))
        ymin (apply 'min (mapcar 'cadr allpts)))

  ;; ------------------------------------------------ dimensions
  (setvar "CLAYER" "DIMENSION")
  (if (= ptype "Rectangle")
      ;; per the reference: only the northern and western perimeter
      ;; dims, hooked to the drawn wall (object-bounded) rather than to
      ;; the hypothetical corner a treatment cut away.  pool:dimwall
      ;; finds the hook by dropping each corner's own extension line
      ;; onto the treatment, so an out-of-square wall lands right too
      ;; -- picking the neighbouring treatment end by hand only
      ;; measured the full run while the corner stayed at 90 degrees.
      (progn
        (pool:dimwall quad corners 3 2 (pool:outoff d c cen doff))
        (pool:dimwall quad corners 0 3 (pool:outoff a d cen doff)))
      (if pool:*insq*
          ;; oval in-square, per the field sheet: T above the top side
          ;; and A outside the left arc -- the bottom side and right
          ;; chord repeat them, so they are not dimensioned (B joins
          ;; from the tip-to-tip dim below).  T subdivides B, so it
          ;; reads in SIDE STANDARD; A is an overall and stays put.
          (progn
            (pool:dimalgs d c (pool:outoff d c cen doff))
            (pool:dimalg a d (list (- (car tipl) (* 1.2 doff))
                                   (cadr (pool:mid a d)))))
          (progn
            (setq endoff (* -0.6 doff))
            (pool:dimalgs a b (pool:outoff a b cen doff))
            (pool:dimalgs d c (pool:outoff d c cen doff))
            (pool:dimalg a d (pool:outoff a d cen endoff))
            (pool:dimalg b c (pool:outoff b c cen endoff)))))
  ;; corner annotations: one "Typ." at B when in-square, every corner
  ;; individually when out-of-square
  (if (= ptype "Rectangle")
      (pool:dimcorners quad corners arcs cen doff))
  ;; oval: radius dims read on the ARC from outside it (no line back to
  ;; the circle centre), plus the tip-to-tip overall.  End radii are
  ;; sheet letters -> SIDE STANDARD, like the roman reference.
  (if (= ptype "Oval")
      (progn
        (pool:dimrads larc tipl ml doff)
        (pool:dimrads rarc tipr mr doff)
        ;; B tip-to-tip: on top per the field sheet when in-square,
        ;; below the pool (clear of the 4 side dims) out-of-square
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (if pool:*insq*
                                         (+ ymax (* 1.9 doff))
                                         (- ymin (* 1.5 doff)))))))
  ;; provided cross dims, between their reference points, in the CROSS
  ;; DIMENSION style when the drawing has one
  (setq odim (pool:dimxbegin) k 0)
  (foreach m xmeas
    (if (nth 7 m)
        (progn
          (setq rpa (pool:cornerpoint quad corners (nth 3 m) (nth 4 m))
                rpb (pool:cornerpoint quad corners (nth 5 m) (nth 6 m)))
          (pool:dimalg rpa rpb
                       (pool:v+ (pool:mid rpa rpb)
                                (pool:v* (pool:unit (pool:perp (pool:v- rpb rpa)))
                                         (* (if (= 0 (rem k 2)) 0.2 -0.2) doff))))))
    (setq k (1+ k)))
  (pool:dimxend odim)
  (setvar "CLAYER" oldclay)

  ;; corner letters live on the mini-model beside the report, not in
  ;; the corners of the drawing itself -- see the pool:minimap call

  ;; ------------------------------------------------ report table
  ;; a side that was read back out of the overall was never measured,
  ;; so it reports N/A like any other NA -- the ACTUAL column shows
  ;; what it came out at
  (setq rows (list (list "TOP SIDE (D-C)" (if tpna nil tp) (cadr meas))
                   (list "BOTTOM SIDE (A-B)" (if bona nil bo) (car meas))
                   (list "LEFT END (A-D)" le (caddr meas))
                   (list "RIGHT END (B-C)" ri (cadddr meas))))
  ;; each cross measurement vs the actual distance between its
  ;; reference points in the fitted drawing
  (foreach m xmeas
    (setq rows (append rows
                       (list (list (nth 2 m) (nth 7 m)
                                   (distance (pool:cornerpoint quad corners (nth 3 m) (nth 4 m))
                                             (pool:cornerpoint quad corners (nth 5 m) (nth 6 m))))))))
  (if tri
      (setq rows (append rows
                         (list (list "TRI CHECK B-D" dbd
                                     (distance (cadr tri) (cadddr tri)))))))
  (if (= ptype "Oval")
      (setq rows (append rows
                         (list (list "TOTAL LENGTH" totl (distance tipl tipr))
                               (list "LEFT RADIUS" lrad lrfit)
                               (list "RIGHT RADIUS" rrad rrfit)))))
  ;; -------------------------------- pool bottom (interior pipeline)
  (cond
    ((= ptype "Rectangle")
     (setq rows (append rows (pool:hopper quad corners doff th))))
    ((= ptype "Oval")
     (setq rows (append rows (pool:hopovaldsp quad tipl tipr doff th)))))
  ;; corner treatments
  ;; corner treatments.  Gated on pool:anytreat, not on anycut: anycut
  ;; asks the GEOMETRY question and so misses a NotGiven corner, which
  ;; is the one the report most needs to carry -- nothing else on the
  ;; sheet records it.  A NotGiven row has no size, so both number
  ;; columns read N/A rather than a fabricated 0.
  (if (and (= ptype "Rectangle") (pool:anytreat corners))
      (if pool:*insq*
          (setq rows (append rows
                             (list (list (strcat "CORNERS " (car (car corners)))
                                         (if (pool:cutp (car (car corners)))
                                             (cadr (car corners)) nil)
                                         (if (pool:cutp (car (car corners)))
                                             (cadr (car corners)) nil)))))
          (foreach lbl (list (list "A" 0) (list "B" 1) (list "C" 2) (list "D" 3))
            (if (/= (car (nth (cadr lbl) corners)) "Square")
                (setq rows (append rows
                                   (list (list (strcat "COR " (car lbl) " " (car (nth (cadr lbl) corners)))
                                               (if (pool:cutp (car (nth (cadr lbl) corners)))
                                                   (cadr (nth (cadr lbl) corners)) nil)
                                               (if (pool:cutp (car (nth (cadr lbl) corners)))
                                                   (cadr (nth (cadr lbl) corners)) nil)))))))))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (setq rbox (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES"))
  ;; perimeter mini-model with the corner letters, right of the report
  (setq mprims (list (list 'l a b) (list 'l d c)))
  (if (= ptype "Oval")
      (setq mprims (append mprims (list (list 'a a tipl d)
                                        (list 'a b tipr c))))
      (setq mprims (append mprims (list (list 'l a d) (list 'l b c)))))
  (pool:minimap mprims quad
                (list (cons a "A") (cons b "B") (cons c "C") (cons d "D"))
                (+ (car rbox) (* 3.0 th)) (cadr rbox) (* 24.0 th) th)
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- round pools ------------------------------------
;;;
;;;  A round pool is a circle when it is in square and an ellipse when
;;;  the two overalls disagree -- B across, A up, both measured through
;;;  the middle.  There are no corners to best-fit, so the perimeter is
;;;  drawn exactly to the overalls and the report shows them as-drawn.
;;;
;;;  The interior is the True Oval hopper / sport bottom set, measured
;;;  off the pool's own extremes: H from the left edge, E to the right
;;;  edge, M/K off the top and bottom -- so H+G+F+E = B and M+L+K = A,
;;;  exactly like the field sheet.

;; Circle (a = b) or axis-aligned ellipse, on layer lay.
(defun pool:roundbody (cen b a lay)
  (if (< (abs (- a b)) 1.0e-6)
      (entmake (list '(0 . "CIRCLE")
                     (cons 8 lay)
                     (cons 10 (pool:wp cen))
                     (cons 40 (* 0.5 b))))
      (entmake (list '(0 . "ELLIPSE")
                     '(100 . "AcDbEntity")
                     (cons 8 lay)
                     '(100 . "AcDbEllipse")
                     (cons 10 (pool:wp cen))
                     (cons 11 (list (* 0.5 b) 0.0 0.0))   ; major axis, relative
                     (cons 210 '(0.0 0.0 1.0))
                     (cons 40 (/ a b))                    ; minor / major
                     (cons 41 0.0)
                     (cons 42 (* 2.0 pi))))))

;; Full guided flow for round pools.
(defun pool:roundflow ( / oldclay pv ans braw araw b a cen quad tipl tipr
                          doff th rows notes xmax ymax rbox)
  (setq oldclay (getvar "CLAYER"))
  ;; The live guide geometry (see "live guide reshaping"): a circle
  ;; until the two overalls part company, then the ellipse they make.
  ;; The guide body is always an ELLIPSE entity so it can be morphed
  ;; in place however the two answers land.
  (defun rd:geo ( / bov aov sc spec km)
    (setq bov (cond ((pool:pvdim 'b)) (360.0))
          aov (cond ((pool:pvdim 'a)) ((pool:pvdim 'b)) (360.0))
          sc (/ (max bov aov) 360.0)
          spec (append
                 (list (list "ELL" (list (* 0.5 bov) (* 0.5 aov)) bov aov))
                 (pool:pvtiespec (list 0.0 (+ aov (* 55.0 sc)))
                                 (list bov (+ aov (* 55.0 sc)))
                                 "B" (* 12.0 sc))
                 (pool:pvtiespec (list (- 0.0 (* 55.0 sc)) 0.0)
                                 (list (- 0.0 (* 55.0 sc)) aov)
                                 "A" (* 12.0 sc)))
          km (list (list "B" 1 2) (list "A" 3 4)))
    (list spec km (pool:pvspecbox spec)))
  (setq pv (pool:pvlive 'rd:geo))
  (princ "\nRound pool -- B across and A up, both through the middle.")
  (princ "\n(after the first answer, Back re-asks the previous one)")
  ;; in square, the two overalls are the same measurement
  (setq ans (pool:askseq
              (if pool:*insq*
                  (list (list 'b 'REQ "Overall diameter (A & B are equal)"
                              (append (cdr (assoc "B" pv)) (cdr (assoc "A" pv)))))
                  (list (list 'b 'REQ "B - overall length (across)"
                              (cdr (assoc "B" pv)))
                        (list 'a 'REQ "A - overall width (up)"
                              (cdr (assoc "A" pv))))))
        braw (pool:sq ans 'b)
        araw (if pool:*insq* braw (pool:sq ans 'a))
        b braw a araw)
  (pool:pvkill)

  (setq cen (list (* 0.5 b) (* 0.5 a))
        doff (max 12.0 (/ (max b a) 18.0))
        th (max 3.0 (/ (max b a) 70.0))
        notes nil
        pool:*dashlt* (pool:ltload "DASHED"))
  (pool:roundbody cen b a "POOL")
  (if (> (abs (- a b)) 1.0e-6)
      (princ "\nOut of square: the two overalls differ, so the pool is drawn as an ellipse.")
      (princ "\nIn square: A and B agree, so the pool is drawn as a true circle."))

  ;; the bounding box IS the hopper's frame: H/E off the left and right
  ;; extremes, M/K off the top and bottom
  (setq quad (list (list 0.0 0.0) (list b 0.0) (list b a) (list 0.0 a))
        tipl (list 0.0 (* 0.5 a))
        tipr (list b (* 0.5 a))
        xmax b ymax a)

  ;; per the field sheet: B across the top, A up the left side
  (setvar "CLAYER" "DIMENSION")
  (pool:dimalg tipl tipr (list (* 0.5 b) (+ a (* 1.4 doff))))
  (pool:dimalg (list (* 0.5 b) 0.0) (list (* 0.5 b) a)
               (list (- 0.0 (* 1.4 doff)) (* 0.5 a)))
  (setvar "CLAYER" oldclay)

  (setq rows (list (list "OV B" braw b) (list "OV A" araw a))
        rows (append rows (pool:hopovaldsp quad tipl tipr doff th)))
  (setq notes (append notes pool:*valnotes*))
  (setq rbox (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES"))
  ;; mini-model beside the report -- a round pool has no corner
  ;; letters, but the outline keeps the report set consistent
  (pool:minimap (list (list 'rb cen b a)) nil nil
                (+ (car rbox) (* 3.0 th)) (cadr rbox) (* 24.0 th) th)
  (princ "\nPool layout complete -- see the report table.")
  (princ))

;;; -------------------- roman pools ------------------------------------
;;;
;;;  Rectangle body of side length T and width A, with a radius end
;;;  behind corner drops at each side (per the Roman field sheet):
;;;  B/A overalls, S = tip setback past the side ends, S1 = corner
;;;  drop, V = end width between the arc springs, R1/R2 = end radii.
;;;  Letters close against the overalls like the grecian sheet
;;;  (S+T+S = B with T absorbing, S1+V+S1 = A with V absorbing).
;;;  Interior = the True Oval hopper / sport bottoms.

;; Per-end vertical resolution: returns (S1 V) against overall width.
(defun pool:romres (aov s1raw vraw)
  (cond
    (s1raw (list s1raw (- aov (* 2.0 s1raw))))
    (vraw (list (/ (- aov vraw) 2.0) vraw))
    (t (list (/ aov 6.0) (* aov (/ 2.0 3.0))))))

;; Build and draw one Roman end (per the reference drawing: straight
;; S1 stubs along the end line down to the arc springs, the arc
;; bulging S past the end line).  R is implied by S and V:
;; r = (S^2 + (V/2)^2) / 2S.  pb2/pt2 = where the stubs actually START
;; -- the body corners themselves normally, the corner-treatment ends
;; when those corners are rounded or chamfered (the geometry of the
;; end still springs off the TRUE corners pbot/ptop either way).
;; Returns (tip springT springB arcEname rImplied).
(defun pool:romend (pbot ptop pb2 pt2 m s v lay / u mide tip half st sb)
  (setq u (pool:unit (pool:v- ptop pbot))
        mide (pool:mid pbot ptop)
        tip (pool:v+ mide (pool:v* m s))
        half (* 0.5 v)
        st (pool:v+ mide (pool:v* u half))
        sb (pool:v- mide (pool:v* u half)))
  (if (> (distance pt2 st) 1.0e-6) (pool:line pt2 st lay))
  (if (> (distance pb2 sb) 1.0e-6) (pool:line pb2 sb lay))
  (pool:arc3p st tip sb lay)
  (list tip st sb (entlast)
        (/ (+ (* s s) (* half half)) (* 2.0 s))))

;; Gray nominal Roman guide, proportioned from the reference drawing:
;; full-length sides, vertical S1 stubs on the end lines, near-half-
;; round arcs, and the dashed tip-to-tip B centerline.
;; Cross-dim guide lines are NOT part of the preview: they are added by
;; pool:romancross once every side length is in, so the sheet stays
;; uncluttered while the perimeter is being measured.
;; the two body cross-dim guide lines (A-C, B-D), corner to corner of
;; the live guide body q -- so they land on the reshaped guide, not on
;; a fixed nominal box
(defun pool:romancross (pv q)
  (append pv
          (list (cons "XAC" (list (pool:pvadd (pool:pvlined (car q)
                                                            (caddr q)))))
                (cons "XBD" (list (pool:pvadd (pool:pvlined (cadr q)
                                                            (cadddr q))))))))

;; The Roman guide is built by rm:geo inside pool:romanflow (a
;; live-guide geometry function fed to pool:pvlive), so the body, the
;; two end arcs and every sheet tie reshape as the letters come in.

;; Full guided flow for Roman pools.
(defun pool:romanflow ( / oldclay perfect pv gq braw araw traw rombad ans
                          slraw srraw s1lraw s1rraw vlraw vrraw r1 r2
                          hres sl tv sr lres rres s1l vl s1r vr
                          dac dbd fq quad failed a b c d cen meas notes
                          ml mr lend rend tipl tipr doff th odim pr
                          rcs rce rcarcs
                          allpts xmax ymax ymin rows xcol xa rbox)
  (setq oldclay (getvar "CLAYER"))
  (defun rm:perfect ( / v)
    (if pool:*insq*
        (progn (setq perfect t) nil)
        (progn (setq perfect (pool:askynf 'perfect
                                          "Are both ends perfect (identical)"
                                          nil nil))
               nil)))
  ;; one end's tip setback for the live guide, from whatever the sheet
  ;; has so far: the taped S, else what T leaves of B, else the arc
  ;; sagitta of a given radius, else the nominal eighth of B
  (defun rm:geoext (sraw traw rraw v bv)
    (cond
      (sraw sraw)
      (traw (max 1.0 (* 0.5 (- bv traw))))
      ((and rraw (>= rraw (* 0.5 v)))
       (- rraw (sqrt (max 0.0 (- (* rraw rraw) (* 0.25 v v))))))
      (rraw (* 0.5 v))
      (t (/ bv 8.0))))
  ;; The live guide geometry (see "live guide reshaping"): the body
  ;; rectangle T x A with an arc end either side, every letter resolved
  ;; the way rm:resolve will resolve it -- measured where given, the
  ;; sheet's own derivation where not.  A perfect pool's right end
  ;; follows the left letters, exactly as the questions do.  gq keeps
  ;; the live body for pool:romancross.
  (defun rm:geo ( / bov aov res s1l2 vl2 s1r2 vr2 sl2 sr2 tvv sc th
                    st1 sb1 st2 sb2 tl tr xa x2 x3 yt spec km)
    (setq bov (cond ((pool:pvdim 'b)) (464.0))
          aov (cond ((pool:pvdim 'a)) (300.0))
          res (pool:romres aov (pool:pvdim 's1l) (pool:pvdim 'vl))
          s1l2 (car res) vl2 (cadr res)
          res (pool:romres aov
                           (cond ((pool:pvdim 's1r)) ((pool:pvdim 's1l)))
                           (cond ((pool:pvdim 'vr)) ((pool:pvdim 'vl))))
          s1r2 (car res) vr2 (cadr res))
    (if (<= vl2 1.0) (setq s1l2 (/ aov 6.0) vl2 (- aov s1l2 s1l2)))
    (if (<= vr2 1.0) (setq s1r2 (/ aov 6.0) vr2 (- aov s1r2 s1r2)))
    (setq sl2 (rm:geoext (pool:pvdim 'sl) (pool:pvdim 'tt)
                         (pool:pvdim 'r1) vl2 bov)
          sr2 (rm:geoext (cond ((pool:pvdim 'sr)) ((pool:pvdim 'sl)))
                         (pool:pvdim 'tt)
                         (cond ((pool:pvdim 'r2)) ((pool:pvdim 'r1)))
                         vr2 bov)
          tvv (- bov sl2 sr2))
    (if (<= tvv 1.0)
        (setq tvv (* 0.775 bov) sl2 (* 0.5 (- bov tvv)) sr2 sl2))
    (setq st1 (list 0.0 (- aov s1l2)) sb1 (list 0.0 s1l2)
          st2 (list tvv (- aov s1r2)) sb2 (list tvv s1r2)
          tl (list (- 0.0 sl2) (* 0.5 aov))
          tr (list (+ tvv sr2) (* 0.5 aov))
          sc (/ (max bov aov) 400.0)
          th (* 10.0 sc)
          yt (+ aov (* 30.0 sc))
          xa (- 0.0 sl2 (* 43.0 sc))
          x2 (- 0.0 sl2 (* 20.0 sc))
          x3 (+ tvv sr2 (* 20.0 sc))
          gq (list (list 0.0 0.0) (list tvv 0.0)
                   (list tvv aov) (list 0.0 aov))
          spec (append
                 (list (list "LINE" (list 0.0 0.0) (list tvv 0.0))
                       (list "LINE" (list 0.0 aov) (list tvv aov))
                       (list "LINE" (list 0.0 aov) st1)
                       (list "LINE" (list 0.0 0.0) sb1)
                       (list "LINE" (list tvv aov) st2)
                       (list "LINE" (list tvv 0.0) sb2)
                       (list "ARC" st1 tl sb1)
                       (list "ARC" st2 tr sb2))
                 (pool:pvtiespec tl tr "B" th)
                 (pool:pvtiespec (list 0.0 yt) (list tvv yt) "T" th)
                 (pool:pvtiespec (list (- 0.0 sl2) yt) (list 0.0 yt)
                                 "SL" th)
                 (pool:pvtiespec (list tvv yt) (list (+ tvv sr2) yt)
                                 "SR" th)
                 (pool:pvtiespec (list xa 0.0) (list xa aov) "A" th)
                 (pool:pvtiespec (list x2 (- aov s1l2)) (list x2 aov)
                                 "S1L" th)
                 (pool:pvtiespec (list x2 s1l2) (list x2 (- aov s1l2))
                                 "VL" th)
                 (pool:pvtiespec (list x3 (- aov s1r2)) (list x3 aov)
                                 "S1R" th)
                 (pool:pvtiespec (list x3 s1r2) (list x3 (- aov s1r2))
                                 "VR" th)
                 (pool:pvtiespec tl (pool:v+ tl (list (+ sl2 (* 40.0 sc))
                                                      (* 60.0 sc)))
                                 "R1" th)
                 (pool:pvtiespec tr (pool:v+ tr (list (- 0.0 sr2 (* 40.0 sc))
                                                      (* 60.0 sc)))
                                 "R2" th))
          km (list (list "B" 8 9) (list "T" 10 11) (list "SL" 12 13)
                   (list "SR" 14 15) (list "A" 16 17) (list "S1L" 18 19)
                   (list "VL" 20 21) (list "S1R" 22 23) (list "VR" 24 25)
                   (list "R1" 26 27) (list "R2" 28 29)))
    (list spec km (pool:pvspecbox spec)))
  (defun rm:guide ()
    (pool:pvkill)
    (setq pv (pool:pvlive 'rm:geo))
    (princ "\nRoman sheet -- the RED tie is the dimension being asked for.")
    (princ "\n(Back re-asks the previous question)")
    nil)
  (defun rm:letters ( / ans)
  (setq ans (pool:askseqb
              (append
                (list (list 'b 'REQ "B - overall length" (cdr (assoc "B" pv)))
                      (list 'a 'REQ "A - overall width" (cdr (assoc "A" pv)))
                      (list 'tt 'NAX "T - side length (top & bottom)"
                            (cdr (assoc "T" pv))))
                (if perfect
                    (list (list 'sl 'NAX "S - end setback (both ends)"
                                (append (cdr (assoc "SL" pv)) (cdr (assoc "SR" pv))))
                          (list 's1l 'NAX "S1 - corner drop (all corners)"
                                (append (cdr (assoc "S1L" pv)) (cdr (assoc "S1R" pv))))
                          (list 'vl 'NAX "V - end width (both ends)"
                                (append (cdr (assoc "VL" pv)) (cdr (assoc "VR" pv))))
                          (list 'r1 'NAX "R - end radius (both ends, check)"
                                (append (cdr (assoc "R1" pv)) (cdr (assoc "R2" pv)))))
                    (list (list 'sl 'NAX "S - LEFT end setback" (cdr (assoc "SL" pv)))
                          (list 'sr 'NAX "S - RIGHT end setback" (cdr (assoc "SR" pv)))
                          (list 's1l 'NAX "S1 - LEFT corner drop" (cdr (assoc "S1L" pv)))
                          (list 's1r 'NAX "S1 - RIGHT corner drop" (cdr (assoc "S1R" pv)))
                          (list 'vl 'NAX "V - LEFT end width" (cdr (assoc "VL" pv)))
                          (list 'vr 'NAX "V - RIGHT end width" (cdr (assoc "VR" pv)))
                          (list 'r1 'NAX "R1 - LEFT end radius (check)" (cdr (assoc "R1" pv)))
                          (list 'r2 'NAX "R2 - RIGHT end radius (check)"
                                (cdr (assoc "R2" pv))))))
              t))
  (if (eq ans 'POOL-BACK)
      'POOL-BACK
      (progn
  (setq braw (pool:sq ans 'b) araw (pool:sq ans 'a) traw (pool:sq ans 'tt)
        slraw (pool:sq ans 'sl) s1lraw (pool:sq ans 's1l)
        vlraw (pool:sq ans 'vl) r1 (pool:sq ans 'r1)
        srraw (if perfect slraw (pool:sq ans 'sr))
        s1rraw (if perfect s1lraw (pool:sq ans 's1r))
        vrraw (if perfect vlraw (pool:sq ans 'vr))
        r2 (if perfect r1 (pool:sq ans 'r2)))
      nil)))

  ;; every side length is in -- now the cross dims appear on the guide,
  ;; corner to corner of the live body the guide reshaped itself to
  (defun rm:cross ( / ans xg)
    (if pool:*insq*
        nil
        (progn
          (setq pv (pool:romancross pv gq)
                xg (append (cdr (assoc "XAC" pv)) (cdr (assoc "XBD" pv)))
                ans (pool:askseqb
                      (list (list 'ac 'NAX "Cross dim body A-C" (cdr (assoc "XAC" pv)))
                            (list 'bd 'NAX "Cross dim body B-D" (cdr (assoc "XBD" pv))))
                      t))
          (if (eq ans 'POOL-BACK)
              (progn (pool:pvdel xg) 'POOL-BACK)
              (progn (setq dac (pool:sq ans 'ac)
                           dbd (pool:sq ans 'bd))
                     nil)))))

  ;; resolve: per end S1/V vs A (V absorbs); then S + T + S = B with
  ;; T absorbing -- an NA S can come from the chain, or from the end
  ;; radius (arc sagitta: S = R - sqrt(R^2 - (V/2)^2)).
  ;; Lives at the top of rm:corners so the corner questions can be
  ;; capped against the resolved side and stub lengths; re-entered
  ;; after a Back it re-resolves from scratch (the valnotes it emits
  ;; are reset first so they cannot double up).
  (defun rm:resolve ()
  (setq pool:*valnotes* nil rombad nil)
  (setq lres (pool:romres araw s1lraw vlraw)
        s1l (car lres) vl (cadr lres)
        rres (pool:romres araw s1rraw vrraw)
        s1r (car rres) vr (cadr rres)
        sl (cond
             (slraw slraw)
             (traw (/ (- braw traw) 2.0))
             ((and r1 (>= r1 (* 0.5 vl)))
              (- r1 (sqrt (max 0.0 (- (* r1 r1) (* 0.25 vl vl))))))
             (t (/ braw 8.0)))
        sr (cond
             (srraw srraw)
             (traw (/ (- braw traw) 2.0))
             ((and r2 (>= r2 (* 0.5 vr)))
              (- r2 (sqrt (max 0.0 (- (* r2 r2) (* 0.25 vr vr))))))
             (t (/ braw 8.0)))
        tv (- braw sl sr))

  ;; every letter must close POSITIVE against the overalls -- warned
  ;; NOW, before the pool is drawn or the bottom letters asked, and
  ;; red in the report after
  (if (<= s1l 1.0e-6)
      (progn (setq s1l (min 12.0 (* 0.125 araw)) vl (- araw s1l s1l) rombad t)
             (pool:valnote "ROMAN S1 LEFT NOT POSITIVE - ADJUSTED")))
  (if (<= s1r 1.0e-6)
      (progn (setq s1r (min 12.0 (* 0.125 araw)) vr (- araw s1r s1r) rombad t)
             (pool:valnote "ROMAN S1 RIGHT NOT POSITIVE - ADJUSTED")))
  (if (<= vl 1.0e-6)
      (progn (setq vl (min 12.0 (* 0.5 araw)) s1l (/ (- araw vl) 2.0) rombad t)
             (pool:valnote "ROMAN S1 + V + S1 LEFT DOES NOT FIT A - ADJUSTED")))
  (if (<= vr 1.0e-6)
      (progn (setq vr (min 12.0 (* 0.5 araw)) s1r (/ (- araw vr) 2.0) rombad t)
             (pool:valnote "ROMAN S1 + V + S1 RIGHT DOES NOT FIT A - ADJUSTED")))
  (if (<= sl 1.0e-6)
      (progn (setq sl (min 12.0 (/ braw 8.0)) rombad t)
             (pool:valnote "ROMAN S LEFT NOT POSITIVE - ADJUSTED")))
  (if (<= sr 1.0e-6)
      (progn (setq sr (min 12.0 (/ braw 8.0)) rombad t)
             (pool:valnote "ROMAN S RIGHT NOT POSITIVE - ADJUSTED")))
  (if (<= (setq tv (- braw sl sr)) 1.0e-6)
      (progn
        (setq tv (min 12.0 (* 0.25 braw))
              sl (/ (- braw tv) 2.0) sr sl rombad t)
        (pool:valnote "ROMAN S + T + S DOES NOT FIT B - ADJUSTED")))
  (princ))

  ;; -------- corner treatments: the four TRUE corners A/B/C/D, where
  ;; a side runs into an end line above/below the arc's corner drop
  ;; (the arc springs are not corners a builder treats).  One answer
  ;; for all four in square, each asked on its own out of square --
  ;; the rectangle's split exactly, and like the rectangle the corner
  ;; angles are assumed square: the roman body IS a rectangle, within
  ;; a degree of 90 even out of square.  Sizes are capped at half the
  ;; side and at the S1 corner drop, so a treatment can never cross
  ;; the arc spring on the stub below it.
  (defun rm:corners ( / v cc)
    (rm:resolve)
    (setq rcs (list (list "Square" 0.0) (list "Square" 0.0)
                    (list "Square" 0.0) (list "Square" 0.0)))
    (setq v (pool:askynf 'crec
                         "Anything to record about the corners (radius / cut / not given)?"
                         "No" t))
    (cond
      ((eq v 'POOL-BACK) 'POOL-BACK)
      ((not v) nil)
      (pool:*insq*
       (setq cc (pool:askcorner "all four corners" nil nil nil
                                (min (* 0.5 tv) s1l s1r) nil t))
       (if (eq cc 'POOL-BACK)
           'POOL-BACK
           (progn (setq rcs (list cc cc cc cc)) nil)))
      (t
       (princ "\n(per-corner treatment; press Enter to reuse the previous corner)")
       (princ "\nCorners: A bottom-left, B bottom-right, C top-right, D top-left.")
       (setq v (pool:askcorners
                 (list "Corner A" "Corner B" "Corner C" "Corner D")
                 (list (min (* 0.5 tv) s1l) (min (* 0.5 tv) s1r)
                       (min (* 0.5 tv) s1r) (min (* 0.5 tv) s1l))
                 (list nil nil nil nil)
                 (list nil nil nil nil)))
       (if (eq v 'POOL-BACK)
           'POOL-BACK
           (progn (setq rcs v) nil)))))

  (pool:stages (list 'rm:perfect 'rm:guide 'rm:letters 'rm:cross 'rm:corners))
  (pool:pvkill)

  ;; body fit (sides T, ends A) + roman ends; sl/tv/s1l... were
  ;; resolved at the top of rm:corners
  (princ "\nFitting pool body to the measurements ...")
  (setq fq (pool:fitquad tv tv araw araw dac dbd pool:*side-tol* pool:*cross-tol*)
        quad (car fq) failed (cadr fq)
        a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        meas (pool:quadmeas quad)
        notes nil
        doff (max 12.0 (/ (max tv araw) 18.0))
        th (max 3.0 (/ (max tv araw) 70.0))
        pool:*dashlt* (pool:ltload "DASHED"))
  ;; sides run between the corner-treatment ends (the true corners
  ;; when the corners are square); the dashed body chords stay on the
  ;; true corners -- they are construction, not walls
  (setq rce (pool:ringends quad rcs))
  (pool:line (cadr (nth 0 rce)) (car (nth 1 rce)) "POOL")
  (pool:line (cadr (nth 2 rce)) (car (nth 3 rce)) "POOL")
  (pool:lined b c)
  (pool:lined d a)
  (setq rcarcs (pool:ringarcs rce rcs "POOL"))
  (setq ml (pool:unit (pool:perp (pool:v- d a))))
  (if (< (pool:dot (pool:v- (pool:mid a d) cen) ml) 0.0)
      (setq ml (pool:v* ml -1.0)))
  (setq mr (pool:unit (pool:perp (pool:v- c b))))
  (if (< (pool:dot (pool:v- (pool:mid b c) cen) mr) 0.0)
      (setq mr (pool:v* mr -1.0)))
  ;; the S1 stubs spring from the treatment ends down the end lines
  ;; (ePrev at A and C, eNext at B and D -- the stub side of each)
  (setq lend (pool:romend a d (car (nth 0 rce)) (cadr (nth 3 rce)) ml sl vl "POOL")
        rend (pool:romend b c (cadr (nth 1 rce)) (car (nth 2 rce)) mr sr vr "POOL")
        tipl (car lend) tipr (car rend))

  ;; dims
  (setq allpts (append quad (list tipl tipr (cadr lend) (caddr lend)
                                  (cadr rend) (caddr rend)))
        xmax (apply 'max (mapcar 'car allpts))
        ymax (apply 'max (mapcar 'cadr allpts))
        ymin (apply 'min (mapcar 'cadr allpts)))
  (setvar "CLAYER" "DIMENSION")
  (if pool:*insq*
      ;; in-square, per the field sheet: S+T+S share a row along the
      ;; top with B outboard of them (S shows at BOTH ends), and
      ;; S1+V+S1 share a column beside the left end with A outboard
      ;; (S1 shows at BOTH corners); the bottom side repeats T and is
      ;; not dimensioned.  The stacked letters (S, T, S1, V) subdivide
      ;; their overalls, so they read in SIDE STANDARD; B and A stay
      ;; in the standard style.
      (progn
        (setq xcol (- (car tipl) (* 0.9 doff))
              xa (- (car tipl) (* 1.9 doff)))
        ;; row 1: S (left tip to side start), T, S (side end to right tip)
        (pool:dimalgs (list (car tipl) ymax) d
                      (list (* 0.5 (+ (car tipl) (car d))) (+ ymax doff)))
        (pool:dimwalls quad rcs 3 2
                       (list (car (pool:mid d c)) (+ ymax doff)))
        (pool:dimalgs c (list (car tipr) ymax)
                      (list (* 0.5 (+ (car c) (car tipr))) (+ ymax doff)))
        ;; row 2: B, tip to tip
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (+ ymax (* 1.9 doff))))
        ;; column 1: S1, V, S1 down the left end line
        (pool:dimalgs d (cadr lend)
                      (list xcol (* 0.5 (+ (cadr d) (cadr (cadr lend))))))
        (pool:dimalgs (cadr lend) (caddr lend)
                      (list xcol (cadr (pool:mid (cadr lend) (caddr lend)))))
        (pool:dimalgs (caddr lend) a
                      (list xcol (* 0.5 (+ (cadr (caddr lend)) (cadr a)))))
        ;; column 2: A, the overall width
        (pool:dimalg a d (list xa (cadr (pool:mid a d)))))
      (progn
        (pool:dimwalls quad rcs 0 1 (pool:outoff a b cen doff))
        (pool:dimwalls quad rcs 3 2 (pool:outoff d c cen doff))
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (- ymin (* 1.5 doff))))
        (pool:dimalg a d (list (- (car tipl) (* 1.2 doff))
                               (cadr (pool:mid a d))))))
  ;; end radii are sheet letters too -> SIDE STANDARD, per the example
  (pool:dimrads (nth 3 lend) tipl ml doff)
  (pool:dimrads (nth 3 rend) tipr mr doff)
  (setq odim (pool:dimxbegin))
  (if dac
      (pool:dimalg a c (pool:v+ (pool:mid a c)
                                (pool:v* (pool:unit (pool:perp (pool:v- c a)))
                                         (* 0.2 doff)))))
  (if dbd
      (pool:dimalg b d (pool:v+ (pool:mid b d)
                                (pool:v* (pool:unit (pool:perp (pool:v- d b)))
                                         (* -0.2 doff)))))
  (pool:dimxend odim)
  ;; corner treatments: one Typ. at B in square, each treated corner
  ;; its own dim out of square (collapsing back to Typ. when Enter
  ;; reused one answer all the way round)
  ;; B leads out of square too, so the all-same Typ. mark lands on the
  ;; same corner as it does in square
  (pool:dimringcorners quad rcs rce rcarcs cen doff
                       (if pool:*insq*
                           (list '(1 0 2 3))
                           (mapcar 'list '(1 0 2 3))))
  (setvar "CLAYER" oldclay)

  ;; corner letters live on the mini-model beside the report, not in
  ;; the corners of the drawing itself -- see the pool:minimap call

  ;; report
  (setq rows (list
    (list "OV B" braw (distance tipl tipr))
    (list "OV A" araw (distance a d))
    (append (list "T TOP" traw (distance d c)) (if rombad (list t) nil))
    (append (list "T BOT" traw (distance a b)) (if rombad (list t) nil))
    (append (list "S LEFT" slraw (distance tipl (pool:mid a d)))
            (if rombad (list t) nil))
    (append (list "S RIGHT" srraw (distance tipr (pool:mid b c)))
            (if rombad (list t) nil))
    (append (list "S1 LEFT" s1lraw (/ (- (distance a d)
                                         (distance (cadr lend) (caddr lend))) 2.0))
            (if rombad (list t) nil))
    (append (list "S1 RIGHT" s1rraw (/ (- (distance b c)
                                          (distance (cadr rend) (caddr rend))) 2.0))
            (if rombad (list t) nil))
    (append (list "V LEFT" vlraw (distance (cadr lend) (caddr lend)))
            (if rombad (list t) nil))
    (append (list "V RIGHT" vrraw (distance (cadr rend) (caddr rend)))
            (if rombad (list t) nil))
    (list "R1" r1 (nth 4 lend))
    (list "R2" r2 (nth 4 rend))))
  (if (not pool:*insq*)
      (setq rows (append rows
                         (list (list "CROSS A-C" dac (nth 4 meas))
                               (list "CROSS B-D" dbd (nth 5 meas))))))
  ;; corner treatments: one row in square, per corner out of square
  (setq rows (append rows
    (if pool:*insq*
        (pool:cornerrows (list "CORNER") (list (nth 0 rcs)))
        (pool:cornerrows (list "CORNER A" "CORNER B" "CORNER C" "CORNER D")
                         rcs))))
  ;; interior: the True Oval hopper / sport bottoms
  (setq rows (append rows (pool:hopovaldsp quad tipl tipr doff th)))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (setq rbox (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES"))
  ;; perimeter mini-model with the corner letters, right of the report:
  ;; the two sides, the S1 stubs and the end arcs
  (pool:minimap
    (list (list 'l a b) (list 'l d c)
          (list 'l d (cadr lend)) (list 'l a (caddr lend))
          (list 'a (cadr lend) tipl (caddr lend))
          (list 'l c (cadr rend)) (list 'l b (caddr rend))
          (list 'a (cadr rend) tipr (caddr rend)))
    quad
    (list (cons a "A") (cons b "B") (cons c "C") (cons d "D"))
    (+ (car rbox) (* 3.0 th)) (cadr rbox) (* 24.0 th) th)
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;;; -------------------- mutt pools -------------------------------------
;;;
;;;  A "mutt" is a rectangle body whose DEEP end (left) and SHALLOW
;;;  end (right) are picked independently -- a roman deep end with a
;;;  grecian shallow end, a grecian deep end with an oval shallow end,
;;;  and so on.  End styles:
;;;    Square  -- plain wall (the rectangle end)
;;;    Grecian -- corner cuts: S setback / S1 drop / S2 face (a
;;;               check, and what an NA S / S1 is filled in from)
;;;    ROman   -- S1 stubs + arc bulging S past the end line (V, R)
;;;    Oval    -- full-width arc (R, NA = half round)
;;;  B is the tip-to-tip overall, A the overall width; each end's
;;;  letters close against them exactly like their home sheets, and
;;;  the body length is what's left of B after the end bulges.
;;;  A SQUARE end is a plain rectangle end, so its two corners take
;;;  the same Square / Radius / Cut / NotGiven treatments the
;;;  rectangle's do, behind the same gate; the other three styles
;;;  measure their corners with their own letters and are not asked.
;;;  Interior = the standard rectangle bottom pipeline, anchored tip
;;;  to tip (no corner ties -- the ends are too varied to tie to).

;; Resolve one mutt end.  Returns (ext inset s1 v r bad):
;; ext = how far the end sticks out past the body end line, inset =
;; how far a grecian cut eats into the sides.  Emits valnotes on the
;; way out of anything that doesn't close.
(defun pool:muttres (style sraw s1raw vraw rraw s2raw aov bov nm / s s1 v ext
                                                                  bad half res)
  (cond
    ((= style "Grecian")
     ;; a grecian END is the grecian sheet's corner cut, so its taped
     ;; face fills in a blank leg the same way (see pool:greccut)
     (setq res (pool:greccut s2raw sraw s1raw)
           s (cond ((car res)) ((/ bov 8.0)))
           s1 (cond ((cdr res)) ((/ aov 6.0)))
           v (- aov s1 s1))
     (if (<= v 1.0e-6)
         (progn
           (setq s1 (min 12.0 (* 0.125 aov)) v (- aov s1 s1) bad t)
           (pool:valnote (strcat nm " END S1 + V + S1 DOES NOT FIT A - ADJUSTED"))))
     (if (<= s 1.0e-6)
         (progn
           (setq s (min 12.0 (/ bov 8.0)) bad t)
           (pool:valnote (strcat nm " END S NOT POSITIVE - ADJUSTED"))))
     (list 0.0 s s1 v nil bad))
    ((= style "ROman")
     (setq res (pool:romres aov s1raw vraw)
           s1 (car res) v (cadr res))
     (if (<= v 1.0e-6)
         (progn
           (setq s1 (min 12.0 (* 0.125 aov)) v (- aov s1 s1) bad t)
           (pool:valnote (strcat nm " END S1 + V + S1 DOES NOT FIT A - ADJUSTED"))))
     (setq s (cond
               (sraw sraw)
               ((and rraw (>= rraw (* 0.5 v)))
                (- rraw (sqrt (max 0.0 (- (* rraw rraw) (* 0.25 v v))))))
               (t (/ bov 8.0))))
     (if (<= s 1.0e-6)
         (progn
           (setq s (min 12.0 (/ bov 8.0)) bad t)
           (pool:valnote (strcat nm " END S NOT POSITIVE - ADJUSTED"))))
     (list s 0.0 s1 v rraw bad))
    ((= style "Oval")
     (setq half (* 0.5 aov)
           ext (cond
                 ((and rraw (>= rraw half))
                  (- rraw (sqrt (max 0.0 (- (* rraw rraw) (* half half))))))
                 (rraw
                  (pool:valnote (strcat nm " END RADIUS SMALLER THAN A/2 - HALF ROUND DRAWN"))
                  (setq bad t)
                  half)
                 (t half)))
     (list ext 0.0 nil nil rraw bad))
    (t (list 0.0 0.0 nil nil nil nil))))

;; Draw one mutt end onto the fitted body.  pbot/ptop = the body
;; corners on this end line, pb2/pt2 = where the sides start (inset
;; for a grecian end), eb/et = where the END WALL starts at pbot/ptop
;; (the corner-treatment ends on a square end; the true corners
;; themselves everywhere else), m = outward unit normal.
;; Returns (tip springT springB arcent rfit) -- tip is the extreme
;; point B is taped to; springs are the wall/stub ends (the body
;; corners themselves on a square or oval end).  The tip of a square
;; end stays the mid of the TRUE end line: a corner treatment eats
;; into the wall from its ends, never past the middle, so B is taped
;; to the same point either way.
(defun pool:muttend (pbot ptop pb2 pt2 eb et m style s1 v ext lay
                     / uu wb wt tip o)
  (setq uu (pool:unit (pool:v- ptop pbot)))
  (cond
    ((= style "Square")
     (pool:line eb et lay)
     (list (pool:mid pbot ptop) ptop pbot nil nil))
    ((= style "Grecian")
     (setq wb (pool:v+ pbot (pool:v* uu s1))
           wt (pool:v- ptop (pool:v* uu s1)))
     (pool:line pb2 wb lay)
     (pool:line wb wt lay)
     (pool:line wt pt2 lay)
     (list (pool:mid pbot ptop) wt wb nil nil))
    ((= style "ROman")
     (pool:romend pbot ptop eb et m ext v lay))
    (t                                  ; Oval
     (setq tip (pool:v+ (pool:mid pbot ptop) (pool:v* m ext)))
     (pool:arc3p ptop tip pbot lay)
     (setq o (pool:circum ptop tip pbot))
     (list tip ptop pbot (entlast) (if o (distance o tip) ext)))))

;;;  A mutt's SQUARE end is a plain rectangle end, so its two corners
;;;  are real corners a builder can round or chamfer -- the field
;;;  sheet's "rectangle with rounded corners on that end".  They are
;;;  asked exactly like the rectangle's and the roman's, behind the
;;;  same gate, and the two questions below are what a treated corner
;;;  costs the rest of the flow: the drawn wall no longer reaches the
;;;  true corner, and the dims that read the wall have to follow it
;;;  down (STANDARDS' "wall dims attach to the pool").
;;;
;;;  The other three end styles are not asked and must not be: a
;;;  grecian end's corner IS its S / S1 / S2 cut, a roman end's is the
;;;  S1 stub under the arc, and an oval end has no corner at all.
;;;  Each is already measured by its own letters, so a treatment there
;;;  would ask the same corner twice, in two vocabularies.

;; The extension-line origin for a mutt body side at quad corner i.
;; A treated corner is off the pool, so the dim hangs on the point of
;; the treatment standing at the TRUE corner's station along the wall
;; -- the number does not move, only the origin (pool:cornerhook).
;; An untreated corner hands back p, which a grecian end has already
;; inset to where its wall really starts.
(defun pool:mutthook (quad corners i p u / hk)
  (if (pool:cutp (car (nth i corners)))
      (if (setq hk (pool:cornerhook (nth i quad)
                                    (nth (rem (+ i 3) 4) quad)
                                    (nth (rem (+ i 1) 4) quad)
                                    (car (nth i corners)) (cadr (nth i corners))
                                    u 0.0))
          hk
          p)
      p))

;; One mutt body-side dim, in SIDE STANDARD like every other sheet
;; letter: it READS the true side run p -> q and hooks its origins
;; onto the drawn wall wherever a corner treatment cut an end off it.
;; Nothing treated -> straight through pool:dimalgs, so an untreated
;; mutt draws exactly the dim it always did.
(defun pool:muttside (quad corners i j p q loc / u hp hq od)
  (setq u (pool:unit (pool:v- q p))
        hp (pool:mutthook quad corners i p u)
        hq (pool:mutthook quad corners j q u))
  (if (and (< (distance p hp) 1.0e-9) (< (distance q hq) 1.0e-9))
      (pool:dimalgs p q loc)
      (progn (setq od (pool:dimsdbeg))
             (pool:dimrot hp hq (angle p q) loc)
             (pool:dimsdend od))))

;; The mutt guide is built by mu:geo inside pool:muttflow (a live-guide
;; geometry function fed to pool:pvlive): the body and both styled ends
;; reshape as B, A and the end letters come in.

;; Full guided flow for mutt pools.
(defun pool:muttflow ( / oldclay pv gq dstyle sstyle ans braw araw
                         dsraw ds1raw dvraw ds2raw drraw
                         ssraw ss1raw svraw ss2raw srraw
                         dres sres extl extr insl insr tv muttbad
                         mcs mce mcarcs mgrp mrlbl mrcs
                         dac dbd fq quad failed a b c d cen meas notes
                         uab udc ml mr lend rend tipl tipr
                         pab0 pab1 pdc0 pdc1 doff th odim
                         allpts xmax ymax ymin rows xcol xa rbox)
  (setq oldclay (getvar "CLAYER"))

  (defun mu:ends ( / v)
    (setq v (pool:askkwf 'dstyle "DEEP end (left) style"
                         "Square Grecian ROman Oval"
                         "Square/Grecian/ROman/Oval" nil t))
    (if (eq v 'POOL-BACK)
        v
        (progn
          (setq dstyle v
                v (pool:askkwf 'sstyle "SHALLOW end (right) style"
                               "Square Grecian ROman Oval"
                               "Square/Grecian/ROman/Oval" nil t))
          (if (eq v 'POOL-BACK)
              v
              (progn (setq sstyle v) nil)))))

  ;; ---- the live guide geometry (see "live guide reshaping").  The
  ;; helpers run inside mu:geo and read / extend its state the same
  ;; dynamic way the flow stages read the flow's own locals.

  ;; one end's live values (ext ins s1 v) from its answer keys, filled
  ;; with the same derivations pool:muttres will apply at the end
  (defun mu:geoval (style ks ks1 kv ks2 kr / s s1 v ext r res half)
    (cond
      ((= style "Grecian")
       (setq res (pool:greccut (pool:pvdim ks2)
                               (pool:pvdim ks) (pool:pvdim ks1))
             s (cond ((car res)) ((/ bov 8.0)))
             s1 (cond ((cdr res)) ((/ aov 6.0)))
             v (- aov s1 s1))
       (if (<= v 1.0) (setq s1 (/ aov 6.0) v (- aov s1 s1)))
       (if (<= s 1.0) (setq s (/ bov 8.0)))
       (list 0.0 s s1 v))
      ((= style "ROman")
       (setq res (pool:romres aov (pool:pvdim ks1) (pool:pvdim kv))
             s1 (car res) v (cadr res))
       (if (<= v 1.0) (setq s1 (/ aov 6.0) v (- aov s1 s1)))
       (setq r (pool:pvdim kr)
             ext (cond ((pool:pvdim ks))
                       ((and r (>= r (* 0.5 v)))
                        (- r (sqrt (max 0.0 (- (* r r) (* 0.25 v v))))))
                       (r (* 0.5 v))
                       (t (/ bov 8.0))))
       (if (<= ext 1.0) (setq ext (/ bov 8.0)))
       (list ext 0.0 s1 v))
      ((= style "Oval")
       (setq r (pool:pvdim kr)
             half (* 0.5 aov)
             ext (if (and r (>= r half))
                     (- r (sqrt (max 0.0 (- (* r r) (* half half)))))
                     half))
       (list ext 0.0 nil nil))
      (t (list 0.0 0.0 nil nil))))

  ;; push one outline primitive / one keyed tie onto the spec
  (defun mu:spec (pr) (setq spec (append spec (list pr)) n (1+ n)))
  (defun mu:tie (p q lbl)
    (setq spec (append spec (pool:pvtiespec p q lbl th))
          km (cons (list lbl n (1+ n)) km)
          n (+ n 2)))

  ;; one end's outline and ties at live size.  A grecian end's cut runs
  ;; INBOARD from the setback corner to the end line -- the shape
  ;; pool:muttend really draws.  Returns the tip B is taped to.
  (defun mu:geoend (wx sgn style sfx ev / tip ext insv s1 v tx)
    (setq ext (car ev) insv (cadr ev) s1 (caddr ev) v (cadddr ev)
          tip (list wx (* 0.5 aov)))
    (cond
      ((= style "Square")
       (mu:spec (list "LINE" (list wx 0.0) (list wx aov))))
      ((= style "Grecian")
       (mu:spec (list "LINE" (list (- wx (* sgn insv)) 0.0) (list wx s1)))
       (mu:spec (list "LINE" (list wx s1) (list wx (- aov s1))))
       (mu:spec (list "LINE" (list wx (- aov s1))
                      (list (- wx (* sgn insv)) aov)))
       (mu:tie (list (- wx (* sgn insv)) 0.0) (list wx s1)
               (strcat "S2" sfx)))
      ((= style "ROman")
       (setq tip (list (+ wx (* sgn ext)) (* 0.5 aov)))
       (mu:spec (list "LINE" (list wx aov) (list wx (- aov s1))))
       (mu:spec (list "LINE" (list wx 0.0) (list wx s1)))
       (mu:spec (list "ARC" (list wx (- aov s1)) tip (list wx s1)))
       (mu:tie tip (pool:v+ tip (list (* sgn -40.0 sc) (* 60.0 sc)))
               (strcat "R" sfx)))
      (t                                ; Oval
       (setq tip (list (+ wx (* sgn ext)) (* 0.5 aov)))
       (mu:spec (list "ARC" (list wx aov) tip (list wx 0.0)))
       (mu:tie tip (pool:v+ tip (list (* sgn -40.0 sc) (* 60.0 sc)))
               (strcat "R" sfx))))
    ;; grecian and roman ends share the S / S1 / V letters
    (if (member style '("Grecian" "ROman"))
        (progn
          (setq tx (+ wx (* sgn 72.0 sc)))
          (mu:tie (list (car tip) (+ aov (* 30.0 sc)))
                  (list (- wx (* sgn insv)) (+ aov (* 30.0 sc)))
                  (strcat "S" sfx))
          (mu:tie (list tx (- aov s1)) (list tx aov) (strcat "S1" sfx))
          (mu:tie (list tx s1) (list tx (- aov s1)) (strcat "V" sfx))))
    tip)

  ;; the guide itself: end lines at 0 and tvv, ends in their chosen
  ;; styles, the body between the grecian insets, and the B / A tapes.
  ;; gq keeps the live body for pool:romancross.
  (defun mu:geo ( / bov aov sc th el er tvv spec km n tipl2 tipr2 xa2)
    (setq bov (cond ((pool:pvdim 'b)) (464.0))
          aov (cond ((pool:pvdim 'a)) (300.0))
          sc (/ (max bov aov) 400.0)
          th (* 10.0 sc)
          el (mu:geoval dstyle 'dsl 'ds1 'dv 'ds2 'dr)
          er (mu:geoval sstyle 'ssl 'ss1 'sv 'ss2 'sr)
          tvv (- bov (car el) (car er)))
    (if (<= (- tvv (cadr el) (cadr er)) 1.0)
        (setq tvv (+ (cadr el) (cadr er) (* 0.5 bov))))
    (setq spec nil km nil n 0
          gq (list (list 0.0 0.0) (list tvv 0.0)
                   (list tvv aov) (list 0.0 aov))
          tipl2 (mu:geoend 0.0 -1.0 dstyle "L" el)
          tipr2 (mu:geoend tvv 1.0 sstyle "R" er)
          xa2 (- 0.0 (car el) (* 70.0 sc)))
    (mu:spec (list "LINE" (list (cadr el) 0.0) (list (- tvv (cadr er)) 0.0)))
    (mu:spec (list "LINE" (list (cadr el) aov) (list (- tvv (cadr er)) aov)))
    (mu:tie tipl2 tipr2 "B")
    (mu:tie (list xa2 0.0) (list xa2 aov) "A")
    (list spec km (pool:pvspecbox spec)))

  (defun mu:guide ()
    (pool:pvkill)
    (setq pv (pool:pvlive 'mu:geo))
    (princ "\nMutt sheet -- deep end LEFT, shallow end RIGHT; the RED tie is the dimension being asked for.")
    (princ "\n(Back re-asks the previous question)")
    nil)

  ;; the letter items one end contributes, per its style
  (defun mu:enditems (style sfx nm ks ks1 kv ks2 kr)
    (cond
      ((= style "Grecian")
       (list (list ks 'NAX (strcat nm " end S - corner setback")
                   (cdr (assoc (strcat "S" sfx) pv)))
             (list ks1 'NAX (strcat nm " end S1 - corner drop")
                   (cdr (assoc (strcat "S1" sfx) pv)))
             (list ks2 'NAX (strcat nm " end S2 - corner face (check, sets NA S/S1)")
                   (cdr (assoc (strcat "S2" sfx) pv)))))
      ((= style "ROman")
       (list (list ks 'NAX (strcat nm " end S - tip setback")
                   (cdr (assoc (strcat "S" sfx) pv)))
             (list ks1 'NAX (strcat nm " end S1 - corner drop")
                   (cdr (assoc (strcat "S1" sfx) pv)))
             (list kv 'NAX (strcat nm " end V - width between springs")
                   (cdr (assoc (strcat "V" sfx) pv)))
             (list kr 'NAX (strcat nm " end R - radius (check)")
                   (cdr (assoc (strcat "R" sfx) pv)))))
      ((= style "Oval")
       (list (list kr 'NAX (strcat nm " end R - radius (NA = half round)")
                   (cdr (assoc (strcat "R" sfx) pv)))))
      (t nil)))

  (defun mu:letters ( / ans)
    (setq ans (pool:askseqb
                (append
                  (list (list 'b 'REQ "B - overall length (tip to tip)"
                              (cdr (assoc "B" pv)))
                        (list 'a 'REQ "A - overall width"
                              (cdr (assoc "A" pv))))
                  (mu:enditems dstyle "L" "Deep" 'dsl 'ds1 'dv 'ds2 'dr)
                  (mu:enditems sstyle "R" "Shallow" 'ssl 'ss1 'sv 'ss2 'sr))
                t))
    (if (eq ans 'POOL-BACK)
        'POOL-BACK
        (progn
          (setq braw (pool:sq ans 'b) araw (pool:sq ans 'a)
                dsraw (pool:sq ans 'dsl) ds1raw (pool:sq ans 'ds1)
                dvraw (pool:sq ans 'dv) ds2raw (pool:sq ans 'ds2)
                drraw (pool:sq ans 'dr)
                ssraw (pool:sq ans 'ssl) ss1raw (pool:sq ans 'ss1)
                svraw (pool:sq ans 'sv) ss2raw (pool:sq ans 'ss2)
                srraw (pool:sq ans 'sr))
          nil)))

  ;; body cross dims, out-of-square only (the ends ride on the body),
  ;; corner to corner of the live body the guide reshaped itself to
  (defun mu:cross ( / ans xg)
    (if pool:*insq*
        nil
        (progn
          (setq pv (pool:romancross pv gq)
                xg (append (cdr (assoc "XAC" pv)) (cdr (assoc "XBD" pv)))
                ans (pool:askseqb
                      (list (list 'ac 'NAX "Cross dim body A-C"
                                  (cdr (assoc "XAC" pv)))
                            (list 'bd 'NAX "Cross dim body B-D"
                                  (cdr (assoc "XBD" pv))))
                      t))
          (if (eq ans 'POOL-BACK)
              (progn (pool:pvdel xg) 'POOL-BACK)
              (progn (setq dac (pool:sq ans 'ac)
                           dbd (pool:sq ans 'bd))
                     nil)))))

  ;; -------- resolve the ends, then the body against B.  Run at the
  ;; top of mu:corners, because the corner questions have to cap their
  ;; sizes against the body side the ends leave behind -- and re-run
  ;; from scratch (valnotes cleared) every time Back comes through, so
  ;; a re-answered letter does not stack a second copy of its warning.
  (defun mu:resolve ()
    (setq pool:*valnotes* nil muttbad nil)
    (setq dres (pool:muttres dstyle dsraw ds1raw dvraw drraw ds2raw
                             araw braw "DEEP")
          sres (pool:muttres sstyle ssraw ss1raw svraw srraw ss2raw
                             araw braw "SHALLOW")
          extl (car dres) insl (cadr dres)
          extr (car sres) insr (cadr sres)
          muttbad (or (nth 5 dres) (nth 5 sres))
          tv (- braw extl extr))
    (if (<= (- tv insl insr) 1.0e-6)
        (progn
          (setq tv (+ insl insr (min 12.0 (* 0.25 braw))) muttbad t)
          (pool:valnote "MUTT ENDS DO NOT FIT B - BODY ADJUSTED")))
    (princ))

  ;; -------- corner treatments on the SQUARE ends.  Quad order: A
  ;; bottom-left and D top-left are the DEEP end's, B bottom-right and
  ;; C top-right the SHALLOW end's -- so an end contributes its two
  ;; corners only when it is Square (see the note above pool:mutthook
  ;; for why the other three styles are not asked).
  ;;
  ;; The grouping is the rectangle's and the roman's: in square one
  ;; question per family of like corners -- both ends square makes ONE
  ;; family of four, since a square-ended mutt's four corners are the
  ;; rectangle's -- and out of square one per corner, Enter reusing
  ;; the previous.  mgrp carries the groups on to the corner marks and
  ;; the report so all three tell the same story.
  ;; the corners to ask, in the order they are asked: A B C D when
  ;; both ends are square (the rectangle's own order), otherwise the
  ;; one square end's pair
  (defun mu:cornerix ()
    (cond ((and (= dstyle "Square") (= sstyle "Square")) (list 0 1 2 3))
          ((= dstyle "Square") (list 0 3))
          ((= sstyle "Square") (list 1 2))))

  ;; the four-corner list the drawing works from: the answer at every
  ;; index that was asked, a plain square corner everywhere else
  (defun mu:cornerset (ans / k out)
    (foreach k (list 0 1 2 3)
      (setq out (cons (if (assoc k ans) (cdr (assoc k ans)) (list "Square" 0.0))
                      out)))
    (reverse out))

  (defun mu:corners ( / ix v cc cap)
    (mu:resolve)
    (setq mcs (mu:cornerset nil)
          mgrp nil mrlbl nil mrcs nil
          ix (mu:cornerix))
    (if (null ix)
        nil                             ; no square end: no corners to ask
        (progn
          ;; half the shorter wall the treatment has to fit on: the
          ;; body side the ends left, or the end wall A
          (setq cap (* 0.5 (min (- tv insl insr) araw)))
          (cond
            ((eq (setq v (pool:askynf 'crec
                                      "Anything to record about the corners (radius / cut / not given)?"
                                      "No" t))
                 'POOL-BACK)
             'POOL-BACK)
            ((not v)
             (mu:cornergroups ix)
             nil)
            (pool:*insq*
             (setq cc (pool:askcorner
                        (cond ((= (length ix) 4) "all four corners")
                              ((= dstyle "Square")
                               "the DEEP end corners A and D")
                              (t "the SHALLOW end corners B and C"))
                        nil nil nil cap nil t))
             (if (eq cc 'POOL-BACK)
                 'POOL-BACK
                 (progn
                   (setq mcs (mu:cornerset
                               (mapcar '(lambda (k) (cons k cc)) ix)))
                   (mu:cornergroups ix)
                   nil)))
            (t
             (princ "\n(per-corner treatment; press Enter to reuse the previous corner)")
             (princ "\nCorners: A bottom-left, B bottom-right, C top-right, D top-left.")
             (princ "\nOnly a SQUARE end has corners to treat -- the others carry their own letters.")
             (setq v (pool:askcorners
                       (mapcar '(lambda (k) (strcat "Corner " (mu:cornerlbl k))) ix)
                       (mapcar '(lambda (k) cap) ix)
                       (mapcar '(lambda (k) nil) ix)
                       (mapcar '(lambda (k) nil) ix)))
             (if (eq v 'POOL-BACK)
                 'POOL-BACK
                 (progn
                   (setq mcs (mu:cornerset (mapcar 'cons ix v)))
                   (mu:cornergroups ix)
                   nil)))))))

  ;; The index groups the answers were given in -- what pool:dimringcorners
  ;; needs to know which corners may collapse to one "Typ." mark -- and
  ;; the matching report labels.  In square the treated end(s) answered
  ;; together are one group led by its reference corner (B when all
  ;; four, the way the rectangle and the roman lead); out of square
  ;; every corner stands alone.
  (defun mu:cornerlbl (k) (nth k (list "A" "B" "C" "D")))

  (defun mu:cornergroups (ix / ord)
    (setq ord (if (= (length ix) 4) (list 1 0 2 3) ix))
    (if pool:*insq*
        (setq mgrp (list ord)
              mrlbl (list (cond ((= (length ix) 4) "CORNER")
                                ((= dstyle "Square") "DEEP CORNER")
                                (t "SHAL CORNER")))
              mrcs (list (nth (car ord) mcs)))
        (setq mgrp (mapcar 'list ord)
              mrlbl (mapcar '(lambda (k) (strcat "CORNER " (mu:cornerlbl k))) ord)
              mrcs (mapcar '(lambda (k) (nth k mcs)) ord)))
    (princ))

  (pool:stages (list 'mu:ends 'mu:guide 'mu:letters 'mu:cross 'mu:corners))
  (pool:pvkill)

  ;; -------- fit the body, draw sides and ends
  (princ "\nFitting pool body to the measurements ...")
  (setq fq (pool:fitquad tv tv araw araw dac dbd pool:*side-tol* pool:*cross-tol*)
        quad (car fq) failed (cadr fq)
        a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (pool:v* (pool:v+ (pool:v+ a b) (pool:v+ c d)) 0.25)
        meas (pool:quadmeas quad)
        notes nil
        doff (max 12.0 (/ (max braw araw) 18.0))
        th (max 3.0 (/ (max braw araw) 70.0))
        pool:*dashlt* (pool:ltload "DASHED")
        uab (pool:unit (pool:v- b a))
        udc (pool:unit (pool:v- c d)))
  (setq ml (pool:unit (pool:perp (pool:v- d a))))
  (if (< (pool:dot (pool:v- (pool:mid a d) cen) ml) 0.0)
      (setq ml (pool:v* ml -1.0)))
  (setq mr (pool:unit (pool:perp (pool:v- c b))))
  (if (< (pool:dot (pool:v- (pool:mid b c) cen) mr) 0.0)
      (setq mr (pool:v* mr -1.0)))
  ;; pab0 / pab1 / pdc0 / pdc1 are the TRUE side ends -- the corners
  ;; themselves, or the setback where a grecian end insets them.  They
  ;; are what the letters measure and what the mini-model draws.  The
  ;; WALLS run between the corner-treatment ends, which is the same
  ;; points again until a square end's corner is rounded or cut (only
  ;; a square end can be, and it never insets, so the two adjustments
  ;; can never collide on one corner).
  (setq mce (pool:ringends quad mcs)
        pab0 (pool:v+ a (pool:v* uab insl))
        pab1 (pool:v- b (pool:v* uab insr))
        pdc0 (pool:v+ d (pool:v* udc insl))
        pdc1 (pool:v- c (pool:v* udc insr)))
  (pool:line (pool:v+ (cadr (nth 0 mce)) (pool:v* uab insl))
             (pool:v- (car (nth 1 mce)) (pool:v* uab insr)) "POOL")
  (pool:line (pool:v+ (car (nth 3 mce)) (pool:v* udc insl))
             (pool:v- (cadr (nth 2 mce)) (pool:v* udc insr)) "POOL")
  (setq lend (pool:muttend a d pab0 pdc0
                           (car (nth 0 mce)) (cadr (nth 3 mce)) ml dstyle
                           (caddr dres) (nth 3 dres) extl "POOL")
        rend (pool:muttend b c pab1 pdc1
                           (cadr (nth 1 mce)) (car (nth 2 mce)) mr sstyle
                           (caddr sres) (nth 3 sres) extr "POOL")
        mcarcs (pool:ringarcs mce mcs "POOL")
        tipl (car lend) tipr (car rend))

  ;; -------- extents / dims
  (setq allpts (append quad (list tipl tipr (cadr lend) (caddr lend)
                                  (cadr rend) (caddr rend)))
        xmax (apply 'max (mapcar 'car allpts))
        ymax (apply 'max (mapcar 'cadr allpts))
        ymin (apply 'min (mapcar 'cadr allpts)))
  (setvar "CLAYER" "DIMENSION")
  (if pool:*insq*
      ;; field-sheet set: each end's letters where its home sheet puts
      ;; them -- S row + top side under B along the top, S1/V columns
      ;; beside their ends, A outboard left, S2 on grecian cuts, R on
      ;; the arcs (below).  The stacked letters (S, the top side, S1,
      ;; V) subdivide the overalls and read in SIDE STANDARD; B, A and
      ;; the S2 cut faces stay in the standard style, per the example.
      (progn
        (if (or (= dstyle "Grecian") (= dstyle "ROman"))
            (pool:dimalgs (list (car tipl) ymax) pdc0
                          (list (* 0.5 (+ (car tipl) (car pdc0)))
                                (+ ymax doff))))
        (pool:muttside quad mcs 3 2 pdc0 pdc1
                       (list (car (pool:mid pdc0 pdc1)) (+ ymax doff)))
        (if (or (= sstyle "Grecian") (= sstyle "ROman"))
            (pool:dimalgs pdc1 (list (car tipr) ymax)
                          (list (* 0.5 (+ (car pdc1) (car tipr)))
                                (+ ymax doff))))
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (+ ymax (* 1.9 doff))))
        (setq xcol (- (car tipl) (* 0.9 doff))
              xa (- (car tipl) (* 1.9 doff)))
        (if (or (= dstyle "Grecian") (= dstyle "ROman"))
            (progn
              (pool:dimalgs d (cadr lend)
                            (list xcol (* 0.5 (+ (cadr d) (cadr (cadr lend))))))
              (pool:dimalgs (cadr lend) (caddr lend)
                            (list xcol (cadr (pool:mid (cadr lend) (caddr lend)))))))
        (if (or (= sstyle "Grecian") (= sstyle "ROman"))
            (progn
              (pool:dimalgs c (cadr rend)
                            (list (+ (car tipr) (* 0.9 doff))
                                  (* 0.5 (+ (cadr c) (cadr (cadr rend))))))
              (pool:dimalgs (cadr rend) (caddr rend)
                            (list (+ (car tipr) (* 0.9 doff))
                                  (cadr (pool:mid (cadr rend) (caddr rend)))))))
        ;; A runs down the deep end line: a drawn wall when that end
        ;; is square, so it hooks onto the pool like any other wall
        (pool:dimwall quad mcs 0 3 (list xa (cadr (pool:mid a d))))
        (if (= dstyle "Grecian")
            (pool:dimalg pab0 (caddr lend)
                         (pool:outoffp pab0 (caddr lend)
                                       (list pab0 pab1 pdc1 pdc0) doff)))
        (if (= sstyle "Grecian")
            (pool:dimalg pab1 (caddr rend)
                         (pool:outoffp pab1 (caddr rend)
                                       (list pab0 pab1 pdc1 pdc0) doff))))
      ;; out-of-square: the simple roman-style set + dashed crosses
      (progn
        (pool:muttside quad mcs 0 1 pab0 pab1
                       (pool:outoff pab0 pab1 cen doff))
        (pool:muttside quad mcs 3 2 pdc0 pdc1
                       (pool:outoff pdc0 pdc1 cen doff))
        (pool:dimalg tipl tipr (list (car (pool:mid tipl tipr))
                                     (- ymin (* 1.5 doff))))
        (pool:dimwall quad mcs 0 3 (list (- (car tipl) (* 1.2 doff))
                                         (cadr (pool:mid a d))))))
  ;; end radii are sheet letters -> SIDE STANDARD, like the roman
  (pool:dimrads (nth 3 lend) tipl ml doff)
  (pool:dimrads (nth 3 rend) tipr mr doff)
  (if (not pool:*insq*)
      (progn
        (setq odim (pool:dimxbegin))
        (if dac
            (pool:dimalg a c (pool:v+ (pool:mid a c)
                                      (pool:v* (pool:unit (pool:perp (pool:v- c a)))
                                               (* 0.2 doff)))))
        (if dbd
            (pool:dimalg b d (pool:v+ (pool:mid b d)
                                      (pool:v* (pool:unit (pool:perp (pool:v- d b)))
                                               (* -0.2 doff)))))
        (pool:dimxend odim)))
  ;; corner treatments on the square end(s): one Typ. per family that
  ;; answered together, each corner its own dim when they differ.  A
  ;; mutt with no square end has no corner to mark, and mgrp is nil.
  (if mgrp
      (pool:dimringcorners quad mcs mce mcarcs cen doff mgrp))
  (setvar "CLAYER" oldclay)

  ;; corner letters live on the mini-model beside the report, not in
  ;; the corners of the drawing itself -- see the pool:minimap call

  ;; -------- report: one block per end, in its own sheet's letters
  (defun mu:endrows (nm style res ends pbot ptop pb2 sraw s1raw vraw
                     s2raw rraw / bad out)
    (setq bad (if (nth 5 res) (list t) nil)
          out nil)
    (if (or (= style "Grecian") (= style "ROman"))
        (setq out (append out (list
          (append (list (strcat nm " S") sraw
                        (if (= style "Grecian")
                            (distance pbot pb2)
                            (distance (car ends) (pool:mid pbot ptop))))
                  bad)
          (append (list (strcat nm " S1") s1raw
                        (distance ptop (cadr ends))) bad)
          (append (list (strcat nm " V") vraw
                        (distance (cadr ends) (caddr ends))) bad)))))
    (if (= style "Grecian")
        (setq out (append out (list
          (append (list (strcat nm " S2") s2raw
                        (distance pb2 (caddr ends))) bad)))))
    (if (or (= style "ROman") (= style "Oval"))
        (setq out (append out (list
          (append (list (strcat nm " R") rraw (nth 4 ends)) bad)))))
    out)

  (setq rows (append
    (list (append (list "OV B" braw (distance tipl tipr))
                  (if muttbad (list t) nil))
          (list "OV A" araw (distance a d))
          (list "T SIDE" (- tv insl insr) (distance pdc0 pdc1)))
    (mu:endrows "DEEP" dstyle dres lend a d pab0
                dsraw ds1raw dvraw ds2raw drraw)
    (mu:endrows "SHAL" sstyle sres rend b c pab1
                ssraw ss1raw svraw ss2raw srraw)))
  (if (not pool:*insq*)
      (setq rows (append rows
                         (list (list "CROSS A-C" dac (nth 4 meas))
                               (list "CROSS B-D" dbd (nth 5 meas))))))

  ;; corner treatments: one row per family in square, per corner out
  ;; of square -- and nothing at all when every corner came back Square
  (if mrlbl
      (setq rows (append rows (pool:cornerrows mrlbl mrcs))))

  ;; -------- interior: standard bottom pipeline, anchored tip to tip
  (setq rows (append rows (pool:hopmuttdsp quad tipl tipr doff th)))
  (if failed (setq notes (cons "CROSS DIMS FAILED" notes)))
  (setq notes (append notes pool:*valnotes*))
  (setq rbox (pool:report rows notes (+ xmax (* 2.0 doff)) ymax th "POOL-NOTES"))
  ;; perimeter mini-model with the corner letters, right of the
  ;; report: sides + each end in its own style
  (pool:minimap
    (append (list (list 'l pab0 pab1) (list 'l pdc0 pdc1))
            (pool:muttmmend dstyle a d pab0 pdc0 lend tipl)
            (pool:muttmmend sstyle b c pab1 pdc1 rend tipr))
    quad
    (list (cons a "A") (cons b "B") (cons c "C") (cons d "D"))
    (+ (car rbox) (* 3.0 th)) (cadr rbox) (* 24.0 th) th)
  (if failed
      (princ "\n*** CROSS DIMS FAILED -- sides held true, see report table ***")
      (princ "\nPool layout complete -- see the report table."))
  (princ))

;; One mutt end as mini-model primitives, per its style (ends =
;; muttend's (tip springT springB arcent rfit) return).
(defun pool:muttmmend (style pbot ptop pb2 pt2 ends tip)
  (cond
    ((= style "Grecian")
     (list (list 'l pb2 (caddr ends))
           (list 'l (caddr ends) (cadr ends))
           (list 'l (cadr ends) pt2)))
    ((= style "ROman")
     (list (list 'l ptop (cadr ends)) (list 'l pbot (caddr ends))
           (list 'a (cadr ends) tip (caddr ends))))
    ((= style "Oval")
     (list (list 'a ptop tip pbot)))
    (t (list (list 'l pbot ptop)))))

;; Mutt bottom dispatcher: the standard rectangle pipeline on the
;; tip-to-tip frame (H closes from the deep tip, E to the shallow
;; tip, like every home sheet), square hopper corners, no corner
;; ties -- the ends are too varied to tie the hopper back to.
(defun pool:hopmuttdsp (quad tipl tipr doff th / btype u v)
  (if (not (pool:askbottom))
      nil
      (progn
        (setq btype (pool:askkwf 'btype "Bottom type"
                                 pool:*btypes* pool:*btshown*
                                 "Normal" nil))
        (setq u (pool:unit (pool:v- tipr tipl))
              v (pool:perp u))
        (if (/= btype "Sport")
            (pool:hopnormal (pool:bodyquad (list tipl v) (list tipr v)
                                           (list (car quad)
                                                 (pool:v- (cadr quad) (car quad)))
                                           (list (cadddr quad)
                                                 (pool:v- (caddr quad) (cadddr quad))))
                            pool:*sq4* doff th nil btype
                            (min (car tipl) (car tipr))
                            (- (apply 'min (mapcar 'cadr quad)) (* 2.2 doff))
                            nil)
            (pool:hopsport (list tipl v) (list tipr v)
                           (list (car quad) (pool:v- (cadr quad) (car quad)))
                           (list (cadddr quad)
                                 (pool:v- (caddr quad) (cadddr quad)))
                           (pool:v* (pool:v+ (pool:v+ (car quad) (cadr quad))
                                             (pool:v+ (caddr quad) (cadddr quad)))
                                    0.25)
                           (distance tipl tipr)
                           (min (car tipl) (car tipr))
                           (- (apply 'min (mapcar 'cadr quad)) (* 2.2 doff))
                           (apply 'max (mapcar 'cadr quad))
                           doff th)))))

;; UNDO grouping that copes with drawings where undo is limited or
;; off, and with an error firing before the group was ever opened.
;; One undo group per command, tracked in a LOCAL of the command that
;; opened it (undo-open), never in a global.  The flag used to live in
;; pool:*undogrp*, shared with POOLDEMO and TUTORIALPOOL -- so a run that died between
;; its last dim and the close left it set, and the next command's
;; handler closed a group it never opened.  Same body as cal:undobegin
;; / cal:undoend, which the grouped build swaps in:
;;   (setq undo-open (pool:undobegin))
;;   ... (if undo-open (setq undo-open (pool:undoend))) ...
;; Opens only while undo is recording -- _Begin in a drawing with UNDO
;; off (bit 1 of UNDOCTL clear) errors out of the command -- and
;; returns nil then, so the idiom above skips the close it does not own.
(defun pool:undobegin ()
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") T)))

(defun pool:undoend ()
  (command "_.UNDO" "_End")
  nil)

;;; -------------------- sysvar save / restore --------------------------
;;; The snapshot of the user's settings lives in a GLOBAL and is taken
;;; only when no snapshot is already pending: if a previous run died
;;; before restoring (hard crash, failure inside the error handler),
;;; the stale snapshot still holds the user's TRUE settings.  Saving
;;; again at that point would capture the zeroed OSMODE and every
;;; later run would faithfully "restore" 0 -- the user's object snaps
;;; would look permanently wiped by the command.  Restoring clears the
;;; snapshot so the next run saves fresh.

(defun pool:syssave ()
  (if (not pool:*sysold*)
      (setq pool:*sysold*
            (mapcar '(lambda (v) (cons v (getvar v)))
                    '("OSMODE" "LUNITS" "CMDECHO" "CLAYER")))))

(defun pool:sysrestore ( / v p)
  ;; OSMODE first -- object snaps are the setting the user misses most
  ;; if a cleanup is ever cut short partway
  (foreach v '("OSMODE" "LUNITS" "CMDECHO" "CLAYER")
    (setq p (assoc v pool:*sysold*))
    (if p (setvar v (cdr p))))
  (setq pool:*sysold* nil))

;;; -------------------- main command -----------------------------------

(defun c:POOL ( / *error* undo-open ptype base)

  (defun *error* (msg)
    (if (and msg
             (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nPOOL error: " msg)))
    ;; user settings come back FIRST so nothing below can skip them
    (pool:sysrestore)
    ;; DIMSTYLE is read-only to setvar, so it is put back the only way
    ;; it can be: dying inside a small-dim, cross-dim or SIDE STANDARD
    ;; block must not leave that style current in the user's drawing
    (setq pool:*sideon* nil)
    (pool:dimsend pool:*dimstyle0*)
    (pool:pvkill)
    ;; a form must never outlive the run it was given to: left behind,
    ;; the next POOL typed at the command line would answer itself with
    ;; last time's numbers and draw a wrong pool with no error at all.
    ;; Cover mode is the same hazard, quieter: a leaked flag draws the
    ;; next pool with no bottom and never asks why
    (pool:fclear)
    (setq pool:*nobottom* nil)
    (if undo-open (setq undo-open (pool:undoend)))
    (if *pop-error-mode* (*pop-error-mode*))
    (princ))

  ;; AutoCAD 2012+ requires this so *error* may call (command);
  ;; harmless no-op guard on older releases where it doesn't exist
  (if *push-error-using-command* (*push-error-using-command*))

  (pool:syssave)
  (setq pool:*valnotes* nil
        pool:*smallwarned* nil
        pool:*profents* nil
        pool:*sideon* nil
        pool:*dimstyle0* (getvar "DIMSTYLE")
        ;; report lengths follow the units the DRAWING was in before
        ;; POOL switches to architectural for its prompts: a crew whose
        ;; drawing is in feet-inches gets a feet-inches report
        pool:*ftin* (member (cdr (assoc "LUNITS" pool:*sysold*)) '(3 4)))
  (setvar "CMDECHO" 0)
  (setq undo-open (pool:undobegin))
  ;; architectural units while prompting so every distance can be
  ;; typed as 25'6", 25'-6-1/2" or 25'6.5 as well as plain inches
  (setvar "LUNITS" 4)
  (princ "\nDistances may be typed as 25'6\", 25'-6-1/2\" or 25'6.5 (plain numbers = inches).")

  ;; In-square pools are built true to the side measurements and need
  ;; no diagonals; out-of-square pools take the usual cross-dim route.
  (setq pool:*insq*
        (= "Insquare"
           (pool:askkwf 'insq "Is the pool in-square or out-of-square"
                        "Insquare Outofsquare" "Insquare/Outofsquare" nil nil)))
  (if pool:*insq*
      (princ "\nIn-square: building true to the side measurements (no cross dims needed)."))

  ;; L = true L; LAzyl = lazy L (type LA); ROman = roman (type RO)
  ;; the six common shapes first, then the rarely-used ones; type RO
  ;; for a roman, ROU for a round, MU for a mutt (mixed ends).
  (setq ptype (pool:fshape))

  ;; the base point is picked with the user's own snaps still live;
  ;; only afterwards do snaps drop for the command-fed drawing work
  (setq base (if (pool:fhas 'base)
                 (pool:ftake 'base)
                 (getpoint "\nInsertion base point <0,0>: "))
        pool:*base* (if (and base (listp base))
                        (list (car base) (cadr base))
                        (list 0.0 0.0)))
  (setvar "OSMODE" 0)

  ;; ------------------------------------------------ layers
  (pool:layer "POOL" 4)
  (pool:layer "DIMENSION" 2)
  (pool:layer "POOL-NOTES" 3)

  ;; dashed linetype up front so the guide's cross dims draw dashed
  ;; patterns are defined in inches and scaled to cancel LTSCALE, so
  ;; they show the same in any drawing
  (setq pool:*dashlt* (pool:ltload "DASHED")
        pool:*dotlt* (pool:ltload "DOT"))

  (cond
    ((= ptype "L") (pool:hexflow nil))
    ((= ptype "LAzyl") (pool:hexflow t))
    ((= ptype "Grecian") (pool:grecflow nil))
    ((= ptype "OCtagon") (pool:grecflow t))
    ((= ptype "ROman") (pool:romanflow))
    ((= ptype "ROUnd") (pool:roundflow))
    ((= ptype "MUtt") (pool:muttflow))
    (t (pool:quadflow ptype)))

  ;; ------------------------------------------------ finish
  (command "_.ZOOM" "_Extents")
  (if undo-open (setq undo-open (pool:undoend)))
  (pool:sysrestore)
  (pool:fclear)
  (setq pool:*nobottom* nil)
  (if *pop-error-mode* (*pop-error-mode*))
  (princ))


;; POOL for a cover sheet: the same command, with the pool-bottom gate
;; already answered No.  A cover records the perimeter and nothing
;; below it, so the depth chain -- C, C2, D, the hopper type and its
;; corner method -- is work the sheet has no answers for and no room
;; to show.
;;
;; It is a command of its own rather than a mode the panel switches on,
;; so that clicking a button still runs exactly the command named on it
;; and typing POOLCOVER does the same thing as clicking it.  The flag
;; is cleared by c:POOL on both its exits, so this cannot leak into the
;; next pool even if this run is cancelled half way.
(defun c:POOLCOVER ()
  (setq pool:*nobottom* t)
  (princ "\nPOOLCOVER: cover sheet - no pool bottom will be asked for.")
  (c:POOL)
  (princ))

(defun c:POOLVER ()
  (princ (strcat "\nPOOL " pool:*version*))
  (princ (strcat "\nDemo: "
                 (if pooldemo:*version* pooldemo:*version* "not loaded")))
  (princ (strcat "\nTutorial: "
                 (if tutorial:*version* tutorial:*version* "not loaded")))
  (princ))

(princ (strcat "\nPOOL " pool:*version*
               " loaded.  POOL to lay out a pool, POOLVER for the version"
               (if tutorial:*version* ", TUTORIALPOOL to learn it" "")
               "."))
(princ)
