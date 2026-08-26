;;; ====================================================================
;;;  SPA.LSP -- Spa / hot-tub template layout tool
;;;
;;;  Command:  SPA
;;;
;;;  Built from the same bones as POOL.LSP, cut down to the three
;;;  shapes a spa template actually needs:
;;;
;;;      Rectangle   four sides, every corner treated separately
;;;      Octagon     eight sides off the A / B overalls and the cuts
;;;      Round       circle, or an ellipse when the two overalls differ
;;;
;;;  WATER'S EDGE vs COVER SIZE
;;;  --------------------------
;;;  The first question asks which one is being drawn:
;;;
;;;    Watersedge  the perimeter is drawn DASHED on layer POOL and every
;;;                overall reads  <measurement> over  Water's Edge
;;;    Coversize   the perimeter is drawn on layer COVER and every
;;;                overall reads  <measurement> over  Cover Size
;;;
;;;  The note is stacked UNDER the measurement, across the dimension
;;;  line, the way the order sheet draws it:
;;;
;;;             95"
;;;       |--------------|
;;;          Cover Size
;;;
;;;  It goes on the OVERALLS only.  Corner callouts (radii, cut faces)
;;;  and the inboard flat dims are left plain, so a corner or a segment
;;;  note can never be mistaken for an overall.
;;;
;;;  BOTH OUTLINES
;;;  -------------
;;;  Once the first outline is drawn the command offers to add the other
;;;  one, either way round.  THE COVER IS ALWAYS THE LARGER of the two,
;;;  which settles the direction of travel:
;;;
;;;    Offset  ask how far the cover laps the water's edge and offset
;;;            OUTWARD (water's edge drawn first) or INWARD (cover drawn
;;;            first).  Radii grow and shrink with the offset, cut faces
;;;            by g * (2*sqrt2 - 2), and a treatment offset away to
;;;            nothing falls back to a 90 corner.
;;;    Dims    give the other outline as measured; the two are drawn
;;;            concentric.  The corner sizes are offered at whatever the
;;;            implied lap works out to, so Enter walks through when it
;;;            really is a parallel offset.
;;;
;;;  With both drawn, the COVER's overalls go outside -- across 2 ft
;;;  above it, up 3 ft to its left -- and the WATER'S EDGE's overalls go
;;;  a third of the way INTO the water's edge, hooked to points on the
;;;  dimension line itself so the arrows land on the outline.  A lone
;;;  outline always takes the outside pair.  One more dimension at the
;;;  bottom gives the OVERLAP: how far the cover laps the water's edge.
;;;
;;;  THERMO-LIGHT
;;;  ------------
;;;  Two rules make it a special case, so the Spa Cover Details block is
;;;  read BEFORE anything else is asked:
;;;    * its water's edge and cover size are the same, so that question
;;;      is skipped (drawn as COVER SIZE) and so is the offer to add the
;;;      other outline;
;;;    * every one of its hinges is velcro -- no dashed fold hinge.
;;;
;;;  AUTO-HINGE
;;;  ----------
;;;  The command offers to auto-hinge the cover.  The offer, and the
;;;  spillaways and the grade / taper behind it, are ASKED AS SOON AS
;;;  THE SPA IS MEASURED -- before a line is drawn -- because their
;;;  answers can still turn the spa (see THE QUARTER TURN below), and
;;;  nothing already on the screen can be turned.  The hinges themselves
;;;  are drawn at the end, on whichever outline they belong to.
;;;
;;;  Spillaways (corner or centred-on-a-wall) are the no-go zones, and
;;;  they are answered against the spa AS MEASURED; the "Spa Cover
;;;  Details" block supplies the grade and taper, which set the foam
;;;  width (max hinge spacing), foam length (max hinge run) and the
;;;  acceptable piece counts.  A taper can carry MORE THAN ONE foam
;;;  sheet and one may work where the other will not, so every sheet is
;;;  solved and scored before fewest pieces decides.
;;;  The longest hinge is then checked against the hinge-length chart
;;;  and velcro hinges / double C channel / hold down kit recommended.  The fewest hinges
;;;  that fit are placed evenly and nudged off the no-go zones; fold
;;;  vs velcro then follows the Hinge Arrangement Chart (pairs folding
;;;  from both ends), labels on the TEXT layer.  Anything out of spec --
;;;  foam length exceeded, piece count not acceptable, a zone that
;;;  could not be dodged -- is still drawn but flagged in the report.
;;;
;;;  THE QUARTER TURN
;;;  ----------------
;;;  The spa is drawn with its long overall running west to east, which
;;;  can mean turning it a quarter turn clockwise from the way it was
;;;  measured; the corners, their treatments and their letters all
;;;  travel with the shape.
;;;
;;;  Hinges run north-south, so a spillaway on the top or the bottom
;;;  wall stands in the way of every one of them -- while the same
;;;  spillaway on a LEFT or RIGHT wall cannot touch any.  A quarter turn
;;;  moves it there, so when the spa laid out the way the long-overall
;;;  rule wants cannot get a hinge clear of a spillaway and the other
;;;  way round can, the spillway wins and the spa is turned.  Both ways
;;;  round are scored on the same three things the layout is scored on
;;;  -- dodging every zone, fitting the foam length, an acceptable piece
;;;  count -- so the turn is never taken to clear a zone at the price of
;;;  a hinge that overruns the foam.  The drawing says which turn it
;;;  took and why, under the outline.
;;;
;;;  THE MINI-MODEL
;;;  --------------
;;;  The corner letters are not written on the drawing.  They go on a
;;;  small copy of the outline beside the report table -- the same move
;;;  POOL made -- so the drawing itself carries nothing but geometry and
;;;  dimensions, and the report's rows (OVERALL ACROSS (A-B), CORNER C
;;;  RADIUS) still read back against a picture of the shape.
;;;
;;;  DIMENSION STYLES
;;;  ----------------
;;;    cover size   "STANDARD INCHES"
;;;    water's edge "STANDARD INCHES 0.5"
;;;  A style the drawing already defines is used exactly as it stands --
;;;  the office template wins.  A missing one is built from the
;;;  standard-inches settings below, the water's edge at half the normal
;;;  furniture size.  The drawing's own current style is put back when
;;;  the command finishes.
;;;
;;;  STANDARD INCHES
;;;  ---------------
;;;  Every dimension is written in standard inches (fractional inches to
;;;  1/8" by default, with the inch mark appended) no matter how the host
;;;  drawing is set up, and every dimension line is placed OUTSIDE the
;;;  shape.  The dimension variables are set for the duration of the
;;;  command and restored afterwards; each dimension keeps the settings
;;;  as its own style override, so the numbers stay in inches after the
;;;  command is done.  See the adjustable constants below to change the
;;;  units or the precision.
;;;
;;;  DIMENSION LAYOUT
;;;  ----------------
;;;  The overall ACROSS goes on the TOP and the overall UP on the LEFT,
;;;  on every shape, with the text centred on its dimension line as
;;;  normal.  What else appears depends on the corners:
;;;
;;;    All four corners identical -- the two overalls plus ONE corner
;;;    callout with a Typ. suffix, at the bottom-right.  That is the
;;;    whole drawing for an all-radius or all-cut cover, and for a
;;;    true square octagon.  An all-Square rectangle gets one 90%%d
;;;    Typ. mark the same way (STANDARDS section 2), and an
;;;    all-NotGiven one gets one ? mark with its Not Given note.
;;;
;;;    Corners NOT identical -- each cut corner is called out on its own
;;;    (no Typ.), the Square ones among them share one 90-degree mark,
;;;    each NotGiven one gets its own ? mark, and every side a cut has
;;;    SHORTENED also gets its remaining FLAT dimensioned, inboard of
;;;    the overalls.  So a cover with one cut top-right reads: overall
;;;    across, overall up, the top flat, the right flat, the cut face,
;;;    and 90 Typ. on the Square corners.
;;;
;;;  The round spa takes one overall; only an out-of-round one gets the
;;;  second.  An octagon whose eight sides come out unequal picks up the
;;;  bottom and right flats the same way the rectangle does.
;;;
;;;  RECTANGLE CORNERS
;;;  -----------------
;;;  The corner question is the canonical Treatment question (STANDARDS
;;;  section 2):
;;;
;;;      How should Corner A be treated? [Square/Radius/Cut/NotGiven]:
;;;
;;;  Square is a true 90 corner; Radius is sized by its radius; Cut (a
;;;  chamfer) by its face length; NotGiven means the order sheet never
;;;  recorded the treatment -- the corner is DRAWN square but flagged,
;;;  on the sheet and in the report, so a guess is never presented as a
;;;  measurement.  The legacy words (90, ROUNDED, DIAG/DIAGONAL, NG)
;;;  stay accepted typed in full, unlisted, and are normalised to the
;;;  canonical word at the ask site.  Side lengths are always to the
;;;  TRUE (sharp) corner; the treatment cuts inward from there.  Corner
;;;  A is asked first and its answer AUTOFILLS corners B, C and D --
;;;  press Enter at each to accept it, or type a different treatment
;;;  for that corner.
;;;
;;;  Callouts sit outside the corner on its 45-degree line: a radius dim
;;;  on a Radius corner (R12"), an aligned dim across a Cut face (21"),
;;;  a circled corner point with a 90%%d leader on a Square corner, and
;;;  the same circled point with a ? leader and a Not Given note on a
;;;  NotGiven one.
;;;
;;;  Corner naming (plan view):   D ---------- C
;;;                               |            |
;;;                               |            |
;;;                               A ---------- B
;;;
;;;  Octagon corner naming runs counter-clockwise from the left end of
;;;  the bottom flat:  A B (bottom flat), C D (right flat), E F (top
;;;  flat), G H (left flat); the four cuts are B-C, D-E, F-G and H-A.
;;;
;;;  Distances may be typed in the current drawing units, e.g. 6'10-1/2"
;;;  as well as plain inches -- or in MILLIMETRES by putting the unit on
;;;  the number: 600mm, 1524 MM.  Object snaps stay live, so a distance
;;;  can still be picked off existing geometry instead of typed.
;;;
;;;  Each outline is drawn as ONE CLOSED POLYLINE, so the cover and the
;;;  water's edge are each a single bounded entity: one click selects
;;;  either, each encloses an area, and either can be offset, hatched or
;;;  handed to the tools that work on a highlighted perimeter.  "Back" at any prompt after the first
;;;  re-asks the previous question.
;;;
;;;  Written in plain AutoLISP (entmake + classic commands, no
;;;  ActiveX/VLA), so it loads in AutoCAD 2018 as well as older releases.
;;; ====================================================================

;;; -------------------- version ----------------------------------------
;;;  This file ships twice under two names with IDENTICAL contents:
;;;
;;;      SPA.LSP                 the static name, for the APPLOAD stack
;;;      SPA_MMDDYY_REV##.LSP    the same file, named for its revision
;;;
;;;  Load either one.  The version below travels inside both, so a stack
;;;  that loaded the static name can still say which revision it holds:
;;;  type SPAVER.  Regenerate the pair with tools/release.py.

(setq spa:*version* "082626 REV07")

;;; -------------------- adjustable constants --------------------------

;; Dimension text units.  5 = Fractional inches (84-1/2), 2 = Decimal
;; inches (84.50).  Anything but 4 (Architectural) keeps the numbers in
;; standard inches instead of rolling them up into feet.
(setq spa:*dimlunit* 5)
(setq spa:*dimprec*  3)         ; 5 -> 1/8", 2 -> 3 decimal places
(setq spa:*dimpost*  "\"")      ; suffix stuck on every measurement

;; How far the dimension lines stand off the cover outline, and where
;; the Water's Edge / Cover Size note sits along its dimension line.
(setq spa:*dimoff*    36.0)     ; 3 ft: cover outline -> the LEFT overall dim
(setq spa:*topoff*    24.0)     ; 2 ft: cover outline -> the TOP overall dim
(setq spa:*flatoff*   18.0)     ; outline -> the inboard flat dims
(setq spa:*insetfrac* 0.3333)   ; water's edge dims, a third of the way in
(setq spa:*lapoff*    14.0)     ; how far under the cover the lap note sits

;; Hinge lettering and linework, matched to the office template's
;; before/after sample: labels are MTEXT in the Attributes style at a
;; fixed 5" height, bottom-centred 3" off the line; the fold hinge is
;; drawn in the stock DASHED2 linetype at an effective 5" dash.
(setq spa:*hingetxth*  5.0)     ; hinge label height
(setq spa:*hingetxw*  60.0)     ; hinge label MTEXT frame width
(setq spa:*hingestyle* "Attributes")  ; label style (Standard when absent)
(setq spa:*hdashmult* 20.0)     ; DASHED2 0.25" dash x 20 = 5" on paper

(setq spa:*sfx-water* "Water's Edge")
(setq spa:*sfx-cover* "Cover Size")
(setq spa:*lay-water* "POOL")   ; water's edge perimeter layer (dashed)
(setq spa:*lay-cover* "COVER")  ; cover size perimeter layer

;; Dimension styles, one per outline.  A style the drawing already
;; defines is used exactly as it stands -- the office template wins --
;; and one that is missing is built from the standard-inches settings
;; below, the water's edge at spa:*wefactor* of the normal furniture
;; size (the 0.5 in its name).
(setq spa:*ds-cover*  "STANDARD INCHES")
(setq spa:*ds-water*  "STANDARD INCHES 0.5")
(setq spa:*wefactor*  0.5)
(setq spa:*gapdflt*   3.0)      ; suggested cover lap over the water's edge

(setq spa:*base*     (list 0.0 0.0))
(setq spa:*dashlt*   "CONTINUOUS")   ; resolved to SPADASH per run
(setq spa:*dotlt*    "CONTINUOUS")   ; resolved to SPADOT per run
(setq spa:*pvents*   nil)            ; live guide-preview entities
(setq spa:*valnotes* nil)            ; validation problems for the report
(setq spa:*undogrp*  nil)            ; an UNDO group of ours is open
(setq spa:*sysold*   nil)            ; saved sysvars

(setq spa:*perlay*   "POOL")         ; active perimeter layer
(setq spa:*perdash*  t)              ; draw the perimeter dashed
(setq spa:*sfx*      "")             ; active dimension suffix
(setq spa:*modename* "WATER'S EDGE") ; note written under the drawing
(setq spa:*mode*     "Watersedge")   ; which outline is being drawn
(setq spa:*dstyle*   "STANDARD INCHES 0.5")   ; its dimension style
(setq spa:*dsfac*    0.5)                     ; its furniture factor
(setq spa:*odstyle*  nil)            ; the drawing's dim style before we ran
(setq spa:*turned*   nil)            ; the cover was turned 90 to lie long-ways
(setq spa:*spillturn* nil)           ; ...and it was the spillway that turned it
(setq spa:*hingeon*   nil)           ; the cover is being auto-hinged
(setq spa:*spills*    nil)           ; spillaways, as measured (see spa:askspill)
(setq spa:*hingerows* nil)           ; hinge/spillaway rows for the report
(setq spa:*advice*    nil)           ; hardware recommendations
(setq spa:*grade*     nil)           ; from the Spa Cover Details block
(setq spa:*taper*     nil)

;;; -------------------- small vector helpers --------------------------

(defun spa:v+ (p q) (list (+ (car p) (car q)) (+ (cadr p) (cadr q))))

(defun spa:v- (p q) (list (- (car p) (car q)) (- (cadr p) (cadr q))))

(defun spa:v* (p s) (list (* (car p) s) (* (cadr p) s)))

(defun spa:dot (p q) (+ (* (car p) (car q)) (* (cadr p) (cadr q))))

(defun spa:perp (p) (list (- (cadr p)) (car p)))

(defun spa:mid (p q) (spa:v* (spa:v+ p q) 0.5))

(defun spa:unit (p / d)
  (setq d (sqrt (spa:dot p p)))
  (if (> d 1.0e-12) (spa:v* p (/ 1.0 d)) (list 0.0 0.0)))

;; local 2D point -> world 3D point (applies the insertion base)
(defun spa:wp (p)
  (list (+ (car p) (car spa:*base*))
        (+ (cadr p) (cadr spa:*base*))
        0.0))

;;; -------------------- geometry ---------------------------------------

;; Circumcenter of three points, or nil when collinear.
(defun spa:circum (p1 p2 p3 / ax ay bx by cx cy dd)
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

(defun spa:npos (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;; Is p inside the polygon poly (crossing number)?
(defun spa:inpoly (p poly / n i j xi yi xj yj in x y)
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

;; Midpoint of p->q offset by dist to the side that lies OUTSIDE poly --
;; every dimension in this file is placed with one of these two.
(defun spa:outoffp (p q poly dist / m n)
  (setq m (spa:mid p q)
        n (spa:unit (spa:perp (spa:v- q p))))
  (if (spa:inpoly (spa:v+ m (spa:v* n 1.0)) poly)
      (setq n (spa:v* n -1.0)))
  (spa:v+ m (spa:v* n dist)))

;; Point offset outward (away from cen) from the midpoint of p->q.
(defun spa:outoff (p q cen dist / m n)
  (setq m (spa:mid p q)
        n (spa:unit (spa:perp (spa:v- q p))))
  (if (< (spa:dot (spa:v- m cen) n) 0.0)
      (setq n (spa:v* n -1.0)))
  (spa:v+ m (spa:v* n dist)))

;; Corner-label position: away from the centroid, flipped when that
;; lands inside the shape.
(defun spa:lbloff (p cen poly dist / dir cand)
  (setq dir (spa:unit (spa:v- p cen))
        cand (spa:v+ p (spa:v* dir dist)))
  (if (spa:inpoly cand poly)
      (spa:v+ p (spa:v* dir (- dist)))
      cand))

(defun spa:centroid (pts / cen p)
  (setq cen (list 0.0 0.0))
  (foreach p pts (setq cen (spa:v+ cen p)))
  (spa:v* cen (/ 1.0 (float (length pts)))))

;;; -------------------- entity makers ----------------------------------

(defun spa:layer (name color)
  (if (not (tblsearch "LAYER" name))
      (entmake (list '(0 . "LAYER")
                     '(100 . "AcDbSymbolTableRecord")
                     '(100 . "AcDbLayerTableRecord")
                     (cons 2 name)
                     '(70 . 0)
                     (cons 62 color)
                     '(6 . "Continuous"))))
  name)

;; Build a linetype from an explicit pattern (positive = dash length,
;; 0 = dot, negative = gap), all in drawing units (inches).  Done with
;; entmake rather than loading acad.lin so a failed load can never fall
;; back to CONTINUOUS silently.  Returns the linetype name.
(defun spa:ltmake (name descr pat / lst x)
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
;; pattern defined in inches always plots at that size.
(defun spa:ltsc ( / s)
  (setq s (getvar "LTSCALE"))
  (if (or (null s) (<= s 0.0)) 1.0 (/ 1.0 s)))

;; Spa-scale dash / dot patterns (a spa is a fraction of a pool's size,
;; so the pool's 12" dash would read as a solid line here).
(defun spa:ltload (name)
  (if (= name "DOT")
      (spa:ltmake "SPADOT" "Spa guide dot . . . . . . . ." '(0.0 -3.0))
      (spa:ltmake "SPADASH" "Spa dashed __ __ __ __" '(4.0 -3.0))))

;; extra = a list of extra DXF pairs (linetype override and friends).
(defun spa:line (p1 p2 lay extra)
  (entmake (append (list '(0 . "LINE")
                         (cons 8 lay)
                         (cons 10 (spa:wp p1))
                         (cons 11 (spa:wp p2)))
                   extra)))

;; Three-point arc through p1 -> p2 -> p3 (falls back to a line when
;; the points are collinear).
(defun spa:arc3p (p1 p2 p3 lay extra / o r a1 a2 a3 da2 da3 s e)
  (setq o (spa:circum p1 p2 p3))
  (if o
      (progn
        (setq r  (distance o p1)
              a1 (angle o p1)
              a2 (angle o p2)
              a3 (angle o p3)
              da2 (spa:npos (- a2 a1))
              da3 (spa:npos (- a3 a1)))
        (if (< da2 da3)
            (setq s a1 e a3)
            (setq s a3 e a1))
        (entmake (append (list '(0 . "ARC")
                               (cons 8 lay)
                               (cons 10 (spa:wp o))
                               (cons 40 r)
                               (cons 50 s)
                               (cons 51 e))
                         extra)))
      (spa:line p1 p3 lay extra)))

;; Circle (a = b) or axis-aligned ellipse.  The DXF ratio is minor over
;; MAJOR and must never exceed 1, so the axis that is actually longer
;; becomes the major one.
(defun spa:body-round (cen b a lay extra / maj rat)
  (if (< (abs (- a b)) 1.0e-6)
      (entmake (append (list '(0 . "CIRCLE")
                             (cons 8 lay)
                             (cons 10 (spa:wp cen))
                             (cons 40 (* 0.5 b)))
                       extra))
      (progn
        (if (>= b a)
            (setq maj (list (* 0.5 b) 0.0 0.0) rat (/ a b))
            (setq maj (list 0.0 (* 0.5 a) 0.0) rat (/ b a)))
        (entmake (append (list '(0 . "ELLIPSE")
                               '(100 . "AcDbEntity")
                               (cons 8 lay)
                               '(100 . "AcDbEllipse")
                               (cons 10 (spa:wp cen))
                               (cons 11 maj)              ; major axis, relative
                               (cons 210 '(0.0 0.0 1.0))
                               (cons 40 rat)              ; minor / major
                               (cons 41 0.0)
                               (cons 42 (* 2.0 pi)))
                         extra)))))

(defun spa:text (pt h str lay)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 10 (spa:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

(defun spa:textc (pt h str lay col)
  (entmake (list '(0 . "TEXT")
                 (cons 8 lay)
                 (cons 62 col)
                 (cons 10 (spa:wp pt))
                 (cons 40 h)
                 (cons 1 str))))

;;; -------------------- which outline is being drawn -------------------
;;;
;;;  Everything that differs between the two outlines -- layer, linetype,
;;;  dimension note, dimension style -- hangs off one switch, so the
;;;  command can draw one, flip, and draw the other.

(defun spa:setmode (m)
  (setq spa:*mode* m)
  (if (= m "Watersedge")
      (setq spa:*perlay*   spa:*lay-water*
            spa:*perdash*  t
            spa:*sfx*      spa:*sfx-water*
            spa:*modename* "WATER'S EDGE"
            spa:*dstyle*   spa:*ds-water*
            spa:*dsfac*    spa:*wefactor*)
      (setq spa:*perlay*   spa:*lay-cover*
            spa:*perdash*  nil
            spa:*sfx*      spa:*sfx-cover*
            spa:*modename* "COVER SIZE"
            spa:*dstyle*   spa:*ds-cover*
            spa:*dsfac*    1.0))
  m)

(defun spa:othermode ()
  (if (= spa:*mode* "Watersedge") "Coversize" "Watersedge"))

(defun spa:modeword (m)
  (if (= m "Watersedge") "water's edge" "cover size"))

;;; -------------------- the perimeter itself ---------------------------
;;;  Water's edge -> dashed, on the POOL layer.
;;;  Cover size   -> solid, on the COVER layer.

(defun spa:perdxf ()
  (if (and spa:*perdash* (/= spa:*dashlt* "CONTINUOUS"))
      (list (cons 6 spa:*dashlt*) (cons 48 (spa:ltsc)))))

(defun spa:perline (p1 p2) (spa:line p1 p2 spa:*perlay* (spa:perdxf)))

(defun spa:perarc3p (p1 p2 p3) (spa:arc3p p1 p2 p3 spa:*perlay* (spa:perdxf)))

(defun spa:perround (cen b a) (spa:body-round cen b a spa:*perlay* (spa:perdxf)))

;; tan(theta/4) -- the DXF bulge of an arc segment sweeping theta.
(defun spa:bulge (th) (/ (sin (* 0.25 th)) (cos (* 0.25 th))))

;; The perimeter as ONE closed LWPOLYLINE rather than a handful of loose
;; lines and arcs, so each outline is a single bounded entity: it picks
;; in one click, encloses an area, and can be offset, hatched or handed
;; to the tools that expect a highlighted perimeter (STOCKCOVER, PADDLE,
;; AUTOBEAD).  verts is a list of (point . bulge) walked counter-
;; clockwise; a bulge of 0 is a straight run to the next vertex.
;; Returns the polyline's entity name.
(defun spa:perpoly (verts / lst v p)
  (setq lst (append (list '(0 . "LWPOLYLINE")
                          '(100 . "AcDbEntity")
                          (cons 8 spa:*perlay*)
                          '(100 . "AcDbPolyline")
                          (cons 90 (length verts))
                          '(70 . 1))          ; closed
                    (spa:perdxf)))
  (foreach v verts
    (setq p (spa:wp (car v))
          lst (append lst (list (cons 10 (list (car p) (cadr p)))
                                (cons 42 (cdr v))))))
  (entmake lst)
  (entlast))

;; Dotted WHITE guide line -- the measuring ties on the input screen.
(defun spa:linedot (p1 p2)
  (spa:line p1 p2 "SPA-NOTES"
            (append (list (cons 62 spa:*pvx-col*))
                    (if (/= spa:*dotlt* "CONTINUOUS")
                        (list (cons 6 spa:*dotlt*) (cons 48 (spa:ltsc)))))))

;;; -------------------- dimensions in standard inches ------------------
;;;
;;;  Every dimension this command makes is written in standard inches,
;;;  placed outside the shape, and (for overalls and sides, never for
;;;  corners) suffixed with the Water's Edge / Cover Size note.

(setq spa:*dimvars*
      '("DIMLUNIT" "DIMFRAC" "DIMDEC" "DIMZIN" "DIMPOST" "DIMTAD" "DIMTMOVE"
        "DIMTXT" "DIMASZ"
        "DIMEXE" "DIMEXO" "DIMGAP" "DIMSCALE" "DIMTIX" "DIMTOFL" "DIMATFIT"))

;; setvar that quietly skips a variable this release does not have.
(defun spa:setv (v val)
  (if (/= nil (getvar v)) (setvar v val)))

;; th = the drawing's note text height; the dimension furniture is sized
;; off it so the numbers read at any spa size.
(defun spa:dimsetup (th)
  (spa:setv "DIMLUNIT" spa:*dimlunit*)  ; 5 = fractional inches
  (spa:setv "DIMFRAC"  0)               ; 39 3/8, stacked fraction
  (spa:setv "DIMTAD"   0)               ; text straddles the dim line (\X)
  (spa:setv "DIMTMOVE" 2)               ; text may slide along without a leader
  (spa:setv "DIMDEC"   spa:*dimprec*)
  (spa:setv "DIMZIN"   8)               ; no trailing zeros
  (spa:setv "DIMPOST"  spa:*dimpost*)   ; the inch mark
  (spa:setv "DIMSCALE" 1.0)             ; sizes below are already real
  (spa:setv "DIMTXT"   th)
  (spa:setv "DIMASZ"   (* 0.8 th))
  (spa:setv "DIMEXE"   (* 0.6 th))
  (spa:setv "DIMEXO"   (* 0.6 th))
  (spa:setv "DIMGAP"   (* 0.4 th))
  (spa:setv "DIMTIX"   0)               ; text may go outside...
  (spa:setv "DIMTOFL"  1)               ; ...but keep the dimension line
  (spa:setv "DIMATFIT" 3)
  (princ))

;; The tail of an OVERALL dimension's text override.  \X splits the
;; text across the dimension line, so an overall reads as the order
;; sheet draws it -- the measurement on top, the note stacked under it:
;;        95"
;;     Cover Size
(defun spa:ovnote () (strcat "\\X" spa:*sfx*))

;; Put the outline's named dimension style in charge of the dims that
;; follow.  A style the drawing already defines is restored untouched --
;; the office template wins.  A missing one is built from the
;; standard-inches settings at `fac` times the normal furniture size and
;; saved under the name, so the drawing ends up carrying both styles.
(defun spa:dimstyle (name th fac)
  (if (tblsearch "DIMSTYLE" name)
      (command "_.-DIMSTYLE" "_Restore" name)
      (progn
        (spa:dimsetup (* th fac))
        (command "_.-DIMSTYLE" "_Save" name)))
  ;; whatever the style says, the note has to be free to slide along its
  ;; dimension line without dragging the line or growing a leader
  (spa:setv "DIMTMOVE" 2)
  (princ))

;; The style for whichever outline is being drawn right now.
(defun spa:dimstylenow (th) (spa:dimstyle spa:*dstyle* th spa:*dsfac*))

;; Aligned dimension between two points, dragged to pt.  note is appended
;; to the measurement inside a text override ("\\XCover Size" to stack it,
;; " Typ." to run it on); pass nil for a plain dimension.
(defun spa:dimalg (p1 p2 pt note)
  (if (and note (/= note ""))
      (command "_.DIMALIGNED" (spa:wp p1) (spa:wp p2)
               "_T" (strcat "<>" note) (spa:wp pt))
      (command "_.DIMALIGNED" (spa:wp p1) (spa:wp p2) (spa:wp pt))))

;; Park a dimension's text at an explicit point.  DXF 11 is the text
;; midpoint and bit 128 of DXF 70 marks it as user-placed.  Used only for
;; the overlap note, which is far too small to hold its own text.
(defun spa:dimtextat (e pt / ed f)
  (if (and e (setq ed (entget e)) (= "DIMENSION" (cdr (assoc 0 ed)))
           (assoc 11 ed) (assoc 70 ed))
      (progn
        (setq f  (cdr (assoc 70 ed))
              ed (subst (cons 11 (spa:wp pt)) (assoc 11 ed) ed)
              ed (subst (cons 70 (logior f 128)) (assoc 70 ed) ed))
        (entmod ed)
        (entupd e)))
  (princ))

;; An OVERALL dimension: the measurement over the Water's Edge / Cover
;; Size note, both centred on the dimension line as normal.
(defun spa:dimov (p1 p2 loc)
  (spa:dimalg p1 p2 loc (spa:ovnote)))

;; Radius dimension read from OUTSIDE the arc: the arc is picked at its
;; far point and the dimension line dragged further out along the same
;; direction, so the leader comes in from outside.
(defun spa:dimrad (ent tip outd doff sfx)
  (if (and ent (entget ent)
           (member (cdr (assoc 0 (entget ent))) '("ARC" "LWPOLYLINE")))
      (if (and sfx (/= sfx ""))
          (command "_.DIMRADIUS" (list ent (spa:wp tip))
                   "_T" (strcat "<>" sfx)
                   (spa:wp (spa:v+ tip (spa:v* outd (* 0.9 doff)))))
          (command "_.DIMRADIUS" (list ent (spa:wp tip))
                   (spa:wp (spa:v+ tip (spa:v* outd (* 0.9 doff))))))
      (princ "\n(radius dim skipped -- that corner came out flat, no arc)")))

;;; -------------------- user input -------------------------------------
;;;
;;;  The user's own object snaps stay LIVE during every measurement
;;;  prompt (typed input is unaffected; a picked point can snap onto
;;;  existing geometry).  OSMODE is zeroed only while the routine feeds
;;;  points to commands, where a snap would grab the wrong geometry.

(defun spa:osup ( / p)
  (setq p (assoc "OSMODE" spa:*sysold*))
  (if p (setvar "OSMODE" (cdr p))))

(defun spa:osdown () (setvar "OSMODE" 0))

;;; -------------------- measurement sequences (Back) -------------------
;;;
;;;  A block of related measurements runs through spa:askseqb so every
;;;  prompt after the first also offers *Back*, which re-asks the
;;;  previous question -- a typo no longer means Esc and start over.
;;;  Each item: (key kind msg ents dflt)
;;;    key   symbol the answer is stored under
;;;    kind  REQ  a value is required
;;;          NAX  NA accepted (returns nil)
;;;          SUG  NA accepted, suggested default (Enter takes it)
;;;    ents  guide entities highlighted while prompted
;;;    dflt  for SUG: a number, or a list of keys -- the first of those
;;;          keys with a non-nil answer supplies the suggestion

(defun spa:sq (ans key) (cdr (assoc key ans)))

(defun spa:sqput (ans key v / out p)
  (foreach p ans (if (not (eq (car p) key)) (setq out (cons p out))))
  (reverse (cons (cons key v) out)))

(defun spa:sqfirst (ans keys / out k)
  (foreach k keys
    (if (and (not out) (spa:sq ans k)) (setq out (spa:sq ans k))))
  out)

;; One prompt of a sequence.  Returns the value, nil for NA, or the
;; symbol SPA-BACK.
(defun spa:asks (kind msg ents dflt back / v cols kw e out)
  (setq cols (mapcar 'spa:getcol ents))
  (foreach e ents (spa:setcol e spa:*hi-col*))
  (spa:osup)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  (while (null out)
    ;; 128 = arbitrary input, so a value typed in millimetres reaches us
    ;; as text for spa:mmval rather than being rejected by getdist
    (if kw
        (initget (+ (if (and (eq kind 'SUG) dflt) 6 7) 128) kw)
        (initget (+ 7 128)))
    (setq v (getdist
              (strcat "\n" msg
                      (cond ((eq kind 'REQ) "")
                            ((eq kind 'SUG)
                             (if dflt (strcat " <" (rtos dflt) "> (or NA)")
                                 " (or NA)"))
                            (t " (or NA if not measured)"))
                      (if back " [Back]" "")
                      ": ")))
    (cond
      ((and (= (type v) 'STR) (member v '("Back" "Undo"))) (setq out 'SPA-BACK))
      ((and (= (type v) 'STR) (= v "NA")) (setq out 'SPA-NA))
      ((and (null v) (eq kind 'SUG)) (setq out dflt))   ; Enter took it
      ((setq out (spa:dval v)))
      (t (princ "\nNot a measurement -- type inches, 6'10\", or 600mm."))))
  (spa:osdown)
  (mapcar '(lambda (e c) (spa:setcol e c)) ents cols)
  (if (eq out 'SPA-NA) nil out))

;; Keyword question that can also be backed out of.  kws is the initget
;; string, shown the bracketed list, dflt the Enter answer (nil = an
;; answer is required).  Returns the keyword or SPA-BACK.
(defun spa:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'SPA-BACK)
        ((null v) (if dflt dflt (spa:askkw msg kws shown dflt back)))
        (t v)))

;; Millimetres, typed with the unit on the number: 600mm, 600 MM,
;; 1524.5mm.  The drawing is in inches, so the value is converted.
;; Returns the distance in inches, or nil when the text is not that --
;; which is how the callers tell a mm answer from a typo.
;;
;; getdist cannot parse this itself, so the prompts that accept it set
;; initget's bit 128 (arbitrary input): a value getdist understands
;; still comes back as a number, and anything else comes back as the
;; raw string for this to look at.  Point picking and architectural
;; input are both untouched.
(defun spa:mmval (s / n body v)
  (setq s (spa:trim s)
        n (strlen s))
  (if (and (> n 2) (= "MM" (strcase (substr s (1- n) 2))))
      (progn
        (setq body (spa:trim (substr s 1 (- n 2)))
              v (if (> (strlen body) 0) (distof body 2) nil))
        (if (and v (> v 0.0)) (/ v 25.4)))))

;; What a bit-128 getdist gave back: a number passes through, mm text
;; converts, and anything else is nil so the caller can re-ask.
(defun spa:dval (v)
  (cond ((= (type v) 'STR) (spa:mmval v))
        (t v)))

;; A typed distance prompt that follows the repo's Back convention: a
;; getdist DOES take keywords, so Back (and its unlisted synonym Undo)
;; are offered as keywords whenever there is a previous question to
;; return to, shown in the prompt's brackets like everywhere else.
;; xkw is any extra keyword to merge in, dflt an Enter answer.
;; Returns the distance, a matched keyword string, or SPA-BACK.
(defun spa:askd (msg xkw dflt back / kw v out)
  (setq kw (cond ((and xkw back) (strcat xkw " Back Undo"))
                 (back "Back Undo")
                 (t xkw)))
  (spa:osup)
  (while (null out)
    ;; 128 = arbitrary input, so a mm answer reaches us as text
    (if kw (initget (+ (if dflt 6 7) 128) kw)
        (initget (+ (if dflt 6 7) 128)))
    (setq v (getdist (strcat "\n" msg
                             (if dflt (strcat " <" (rtos dflt) ">") "")
                             (cond ((and xkw back) (strcat " [" xkw "/Back]"))
                                   (xkw (strcat " [" xkw "]"))
                                   (back " [Back]")
                                   (t ""))
                             ": ")))
    (cond
      ((and (= (type v) 'STR) (member v '("Back" "Undo"))) (setq out 'SPA-BACK))
      ((and (= (type v) 'STR) xkw (= v xkw)) (setq out v))
      ((and (null v) dflt) (setq out dflt))
      ((setq out (spa:dval v)))
      (t (princ "\nNot a measurement -- type inches, 6'10\", or 600mm."))))
  (spa:osdown)
  out)

;; Back typed like a value, for the one prompt that cannot take
;; keywords (getstring).  Any case, per the shared convention.
(defun spa:backstr (v)
  (member (strcase v) '("B" "BACK" "U" "UNDO")))

;; Run a list of input stages with Back between them: a stage that
;; returns SPA-BACK sends the user to the previous stage, which is
;; re-asked from scratch.  Each stage is a function of no arguments and
;; must be safely re-runnable (it recomputes from its own answers).
;; Stage 1 has nowhere to go back to, so its Back is suppressed.
(defun spa:stages (fns / i n v)
  (setq i 0 n (length fns))
  (while (< i n)
    (setq v (apply (nth i fns) nil))
    (if (eq v 'SPA-BACK)
        (if (> i 0) (setq i (1- i)))
        (setq i (1+ i))))
  (princ))

;; Run a whole block; returns the answers as an assoc list, or SPA-BACK
;; when the user backed out of its FIRST question (only offered when bk
;; is non-nil).
(defun spa:askseqb (items bk / ans i n it v dflt asked out)
  (setq ans nil i 0 n (length items) asked nil out nil)
  (while (and (< i n) (not out))
    (setq it (nth i items)
          dflt (nth 4 it))
    (if (and dflt (listp dflt))
        (setq dflt (spa:sqfirst ans dflt)))
    (setq v (spa:asks (cadr it) (caddr it) (cadddr it) dflt
                      (if (or asked bk) t nil)))
    (if (eq v 'SPA-BACK)
        (if asked
            (setq i (car asked) asked (cdr asked))
            (setq out t))               ; backed out of the block
        (setq ans (spa:sqput ans (car it) v)
              asked (cons i asked)
              i (1+ i))))
  (if out 'SPA-BACK ans))

;;; -------------------- guide preview ----------------------------------
;;;  A gray nominal spa of the chosen shape is drawn as soon as the shape
;;;  is picked.  While each measurement is prompted for, the matching
;;;  element of the guide turns red so the user can see exactly which
;;;  dimension is being asked for.  Once all inputs are in, the guide
;;;  deletes itself and is replaced by the true spa.

(setq spa:*pv-col*  8)                  ; guide outline color (dark gray)
(setq spa:*pvx-col* 7)                  ; measuring-tie color (white)
(setq spa:*hi-col*  1)                  ; highlight color (red)

;; Override (or set) the color of an entity, refresh it, return it.
(defun spa:setcol (e col / ed old)
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
(defun spa:getcol (e / ed)
  (if (and e (setq ed (entget e)) (assoc 62 ed))
      (cdr (assoc 62 ed))
      spa:*pv-col*))

;; Guide entities for a list of corner-label keys, e.g. '(lA lB).
(defun spa:lbl (pv keys / out k)
  (foreach k keys (setq out (append out (cdr (assoc k pv)))))
  out)

;; The guide's corner-label key for a letter string ("A" -> 'lA).
(defun spa:lblkey (s) (read (strcat "l" s)))

;; Track a freshly made guide entity so spa:pvkill / *error* find it.
(defun spa:pvadd (e)
  (setq spa:*pvents* (cons e spa:*pvents*))
  e)

(defun spa:pvline (p1 p2)
  (spa:line p1 p2 "SPA-NOTES" nil)
  (spa:setcol (entlast) spa:*pv-col*))

;; Guide measuring line, drawn WHITE and DOTTED so it stands out from
;; the gray outline.
(defun spa:pvlined (p1 p2)
  (spa:linedot p1 p2)
  (entlast))

;; A labelled measuring tie (the overall-sheet letters).  The tie AND
;; its letter highlight together while it is prompted for.
(defun spa:pvtie (p q lbl th / e et)
  (setq e (spa:pvadd (spa:pvlined p q)))
  (spa:text (spa:v+ (spa:mid p q) (list (* 0.5 th) (* 0.5 th)))
            (* 1.2 th) lbl "SPA-NOTES")
  (setq et (spa:pvadd (spa:setcol (entlast) spa:*pv-col*)))
  (cons lbl (list e et)))

;; Remove an item (by equality) from a list.
(defun spa:lremove (x lst / out i)
  (foreach i lst (if (not (equal i x)) (setq out (cons i out))))
  (reverse out))

;; Delete specific guide entities mid-flow and untrack them.
(defun spa:pvdel (ents / e)
  (foreach e ents
    (if (and e (entget e)) (entdel e))
    (setq spa:*pvents* (spa:lremove e spa:*pvents*))))

;; Delete all guide entities (tracked globally so the *error* handler
;; can clean up after a cancel mid-prompt).
(defun spa:pvkill ( / e)
  (foreach e spa:*pvents*
    (if (and e (entget e)) (entdel e)))
  (setq spa:*pvents* nil))

;;; -------------------- report table -----------------------------------

;; Report cell: red when the row is flagged.
(defun spa:rtext (pt h str lay red)
  (if red (spa:textc pt h str lay 1) (spa:text pt h str lay)))

(defun spa:valnote (msg)
  (setq spa:*valnotes* (append spa:*valnotes* (list msg)))
  (princ (strcat "\n" msg)))

;; An advisory -- a recommendation rather than a problem.  Printed under
;; the report table in cyan, so it reads apart from the red failures.
(defun spa:advise (msg)
  (setq spa:*advice* (append spa:*advice* (list msg)))
  (princ (strcat "\n" msg)))

;; rows  = list of (label target actual [red]); a nil target prints N/A
;; notes = list of failure strings (written big and red)
;; Returns the table's box as (xr ytop y0) so the caller can hang the
;; perimeter mini-model off its right edge (spa:minimap).
(defun spa:report (rows notes x y h lay / lh ytop y0 xr r tgt act dl ds n)
  (setq lh (* 2.2 h)
        ytop (+ y lh)
        xr (+ x (* 46.0 h))
        y ytop)
  (setq y (- y lh))
  (spa:text (list x y) (* 1.25 h) (strcat "SPA LAYOUT REPORT - " spa:*modename*) lay)
  (setq y (- y lh))
  (spa:text (list x y) h "MEASUREMENT" lay)
  (spa:text (list (+ x (* 20.0 h)) y) h "TARGET" lay)
  (spa:text (list (+ x (* 29.0 h)) y) h "ACTUAL" lay)
  (spa:text (list (+ x (* 38.0 h)) y) h "DELTA" lay)
  (foreach r rows
    (setq y (- y lh)
          tgt (cadr r)
          act (caddr r))
    (spa:rtext (list x y) h (car r) lay (nth 3 r))
    (if (and tgt act)
        (progn
          (setq dl (- act tgt)
                ds (strcat (if (< dl 0.0) "" "+") (rtos dl 2 2)))
          (spa:rtext (list (+ x (* 20.0 h)) y) h (rtos tgt 2 2) lay (nth 3 r))
          (spa:rtext (list (+ x (* 38.0 h)) y) h ds lay (nth 3 r)))
        (progn
          (spa:rtext (list (+ x (* 20.0 h)) y) h "N/A" lay (nth 3 r))
          (spa:rtext (list (+ x (* 38.0 h)) y) h "-" lay (nth 3 r))))
    (spa:rtext (list (+ x (* 29.0 h)) y) h
               (if act (rtos act 2 2) "N/A") lay (nth 3 r)))
  (foreach n notes
    (setq y (- y (* 1.5 lh)))
    (spa:textc (list x y) (* 1.4 h) n lay 1))
  (foreach n spa:*advice*
    (setq y (- y (* 1.3 lh)))
    (spa:textc (list x y) (* 1.15 h) n lay 4))
  (setq y0 (- y lh)
        ytop (+ ytop (* 0.6 lh)))
  (spa:line (list (- x h) y0) (list xr y0) lay nil)
  (spa:line (list xr y0) (list xr ytop) lay nil)
  (spa:line (list xr ytop) (list (- x h) ytop) lay nil)
  (spa:line (list (- x h) ytop) (list (- x h) y0) lay nil)
  (list xr ytop y0))

;;; -------------------- the mini-model ---------------------------------
;;;
;;;  The corner letters used to sit on the corners of the full-size
;;;  drawing, where they crowd the dimensions, the corner callouts and
;;;  the hinge labels.  They live on a small copy of the outline beside
;;;  the report instead -- the same move POOL made -- so the drawing
;;;  itself carries nothing but its geometry and its dimensions, and the
;;;  report's rows still read back against a picture of the shape.

;; Map a spa-space point into the mini-model's box.  Called only from
;; spa:minimap -- sc / ox / oy / xmin / ymax are ITS locals, seen here
;; through dynamic scope (top-left anchored, y measured downward).
(defun spa:mms (p)
  (list (+ ox (* sc (- (car p) xmin)))
        (- oy (* sc (- ymax (cadr p))))))

;; The perimeter mini-model drawn beside the report: the outline at a
;; small fixed size with the corner LETTERS on it.
;;   prims  ('l p1 p2) line | ('a p1 pmid p2) arc as three points
;;          (uniform scaling keeps an arc an arc) | ('rb cen b a) a
;;          round / elliptical body
;;   poly   the corner ring, for keeping letters outside the outline
;;          (nil -> plain outward-from-centre offsets)
;;   lbls   ((pt . "A") ...); nil on a shape with no corners
;;   x y    top-left anchor (report space); size = the fit box
(defun spa:minimap (prims poly lbls x y size th / pts p l xmin xmax ymin ymax
                                                  sc ox oy w hh spoly cen tx
                                                  lth)
  (setq pts nil)
  (foreach p prims
    (if (eq (car p) 'rb)
        (setq pts (cons (spa:v- (cadr p) (list (* 0.5 (caddr p))
                                               (* 0.5 (cadddr p))))
                        (cons (spa:v+ (cadr p) (list (* 0.5 (caddr p))
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
             (spa:line (spa:mms (cadr p)) (spa:mms (caddr p)) "SPA-NOTES" nil))
            ((eq (car p) 'a)
             (spa:arc3p (spa:mms (cadr p)) (spa:mms (caddr p))
                        (spa:mms (cadddr p)) "SPA-NOTES" nil))
            ((eq (car p) 'rb)
             (spa:body-round (spa:mms (cadr p)) (* sc (caddr p))
                             (* sc (cadddr p)) "SPA-NOTES" nil))))
        (setq spoly (if poly (mapcar 'spa:mms poly))
              cen (list 0.0 0.0))
        (foreach l lbls (setq cen (spa:v+ cen (spa:mms (car l)))))
        (if lbls (setq cen (spa:v* cen (/ 1.0 (length lbls)))))
        (foreach l lbls
          (setq tx (spa:mms (car l)))
          (spa:text (if spoly
                        (spa:lbloff tx cen spoly (* 1.6 lth))
                        (spa:v+ tx (spa:v* (spa:unit (spa:v- tx cen))
                                           (* 1.6 lth))))
                    lth (cdr l) "SPA-NOTES"))))
  (princ))

;; ((point . letter) ...) for the mini-model, corners in their own order.
(defun spa:mlbls (pts names / out i p)
  (setq out nil i 0)
  (foreach p pts
    (setq out (cons (cons p (nth i names)) out)
          i (1+ i)))
  (reverse out))

;; A closed ring of points as mini-model line primitives.
(defun spa:polyprims (pts / out n i)
  (setq out nil n (length pts) i 0)
  (while (< i n)
    (setq out (cons (list 'l (nth i pts) (nth (rem (1+ i) n) pts)) out)
          i (1+ i)))
  out)

;; The rectangle as mini-model primitives: the straight run between one
;; corner's treatment and the next corner's, plus the treatment itself
;; -- an arc on a Radius corner, the cut face on a Diagonal, nothing on
;; a 90 (its two ends are the corner).
(defun spa:rectprims (q corners / ce out i n)
  (setq ce (spa:allends q corners) out nil i 0)
  (while (< i 4)
    (setq n (rem (1+ i) 4)
          out (cons (list 'l (cadr (nth i ce)) (car (nth n ce))) out))
    (cond
      ((caddr (nth i ce))
       (setq out (cons (list 'a (car (nth i ce)) (caddr (nth i ce))
                             (cadr (nth i ce)))
                       out)))
      ((> (distance (car (nth i ce)) (cadr (nth i ce))) 1.0e-9)
       (setq out (cons (list 'l (car (nth i ce)) (cadr (nth i ce))) out))))
    (setq i (1+ i)))
  out)

;; The Water's Edge / Cover Size note under the drawing, plus a line
;; saying so when the cover was turned to lie long-ways.
(defun spa:modenote (x y th)
  (spa:textc (list x y) (* 1.6 th)
             (strcat "SPA OUTLINE DRAWN AT " spa:*modename*) "SPA-NOTES" 7)
  (if spa:*turned*
      (spa:textc (list x (- y (* 2.2 th))) (* 1.2 th)
                 (if spa:*spillturn*
                     "TURNED A QUARTER TURN - HINGES CLEAR OF THE SPILLWAY"
                     "TURNED A QUARTER TURN - LONG OVERALL RUNS ACROSS")
                 "SPA-NOTES" 7)))

;;; -------------------- water's edge <-> cover -------------------------
;;;
;;;  The COVER IS ALWAYS THE LARGER of the two -- it laps the water's
;;;  edge by the same gap the whole way round.  That single fact settles
;;;  which way the offset runs:
;;;
;;;    drew the water's edge, adding the cover   ->  offset OUTWARD
;;;    drew the cover, adding the water's edge   ->  offset INWARD
;;;
;;;  By dims the two outlines are simply concentric: the second is built
;;;  from its own measurements and centred on the first.
;;;
;;;  Offsetting a corner by g (positive outward) is not the same for
;;;  every treatment:
;;;    Radius    the arc stays concentric, so r -> r + g
;;;    Diagonal  the cut face lengthens, f -> f + g * (2*sqrt2 - 2)
;;;    90        stays a sharp 90
;;;  and a treatment offset inward past nothing falls back to a 90.

(setq spa:*diagoff* 0.82842712)         ; 2*sqrt 2 - 2

;; Which way the offset runs to get from the outline just drawn to the
;; other one: +1 outward (water's edge -> cover), -1 inward.
(defun spa:offsign ()
  (if (= spa:*mode* "Watersedge") 1.0 -1.0))

;; Offer the other outline once the first is drawn.  Returns the method
;; keyword ("Offset" / "Dims") or nil.
(defun spa:askother ( / v)
  (if (spa:thermop)
      (progn
        (princ "\nThermo-Light: the water's edge and the cover are the same -- nothing to add.")
        nil)
      (spa:askother2)))

(defun spa:askother2 ( / v)
  (princ (strcat "\nThe " (spa:modeword (spa:othermode))
                 " can be added now -- the cover is always the larger of the two."))
  ;; the Yes/No is this phase's first question -- the outline is already
  ;; drawn behind it, so there is nothing to go back to; the method
  ;; question after it backs up to the Yes/No like any second question
  (if (= "Yes" (spa:askkw (strcat "Draw the " (spa:modeword (spa:othermode))
                                  " as well")
                          "Yes No" "Yes/No" "Yes" nil))
      (if (eq 'SPA-BACK
              (setq v (spa:askkw "Take it from" "Offset Dims"
                                 "Offset/Dims" "Offset" t)))
          (spa:askother2)
          v)))

;; The gap between the two outlines, asked as a positive lap and signed
;; for the direction of travel.
(defun spa:askgap ( / g)
  ;; Back here re-asks the question that chose Offset in the first
  ;; place, which spa:askother2 owns -- so it is returned as SPA-BACK
  ;; and the caller re-enters the offer.
  (setq g (spa:askd "How far does the cover lap the water's edge"
                    nil spa:*gapdflt* t))
  (if (eq g 'SPA-BACK) g (* g (spa:offsign))))

;; Offset every corner treatment by g (positive = outward).
(defun spa:offcorners (corners g / out c sz)
  (foreach c corners
    (setq sz (cond ((= (car c) "Radius") (+ (cadr c) g))
                   ((= (car c) "Cut") (+ (cadr c) (* g spa:*diagoff*)))
                   (t 0.0)))
    ;; a NotGiven corner stays NotGiven: offsetting a treatment nobody
    ;; recorded does not conjure one up
    (setq out (cons (cond ((= (car c) "NotGiven") (list "NotGiven" 0.0))
                          ((and (spa:cutp (car c)) (> sz 1.0e-6))
                           (list (car c) sz))
                          (t (list "Square" 0.0)))
                    out)))
  (reverse out))

;; By dims, the corner sizes still have to come from somewhere.  Each is
;; offered with the size the implied lap works out to, so Enter walks
;; straight through when the second outline really is a parallel offset,
;; and a corner that was measured differently can be typed over.
(defun spa:askothercorners (corners lbls maxsb / out i cc any v)
  (setq any nil)
  (foreach cc corners (if (spa:cutp (car cc)) (setq any t)))
  (if any
      (princ (strcat "\n" (spa:modeword (spa:othermode))
                     " corners -- Enter takes the size the overalls imply.")))
  ;; Back steps to the previous corner, like the main corner loop
  (setq out nil i 0)
  (while (< i (length corners))
    (setq cc (nth i corners))
    (if (not (spa:cutp (car cc)))
        (setq out (cons cc out) i (1+ i))
        (progn
          (setq v (spa:askcorner (strcat "Corner " (nth i lbls))
                                 (car cc) (cadr cc) nil maxsb (> i 0)))
          (if (eq v 'SPA-BACK)
              (if (> i 0)
                  (setq i (1- i) out (cdr out))
                  (princ "\nAlready at the first corner."))
              (setq out (cons v out) i (1+ i))))))
  (reverse out))

;; A quad of width w by length l with its bottom-left at org.
(defun spa:quadat (org w l)
  (list org
        (spa:v+ org (list w 0.0))
        (spa:v+ org (list w l))
        (spa:v+ org (list 0.0 l))))

;; Bottom-left corner that puts a w x l shape concentric with cen.
(defun spa:orgfor (cen w l)
  (list (- (car cen) (* 0.5 w)) (- (cadr cen) (* 0.5 l))))

;; Dimension one outline's two overalls.
;;
;;   OUTSIDE -- the COVER's pair, and a lone outline's: the across dim
;;   2 ft above the cover and the up dim 3 ft to its left, clear of the
;;   whole drawing.
;;
;;   INSIDE -- the WATER'S EDGE's pair, when the cover is drawn as well:
;;   a third of the way into its own outline, hooked to points that sit
;;   ON the dimension line, so the arrows land on the outline itself
;;   rather than trailing extension lines across the cover.
;;
;;  cxlo / cyhi are the cover's left and top edges.
(defun spa:dimoveralls (outside ac1 ac2 up1 up2 cxlo cyhi)
  (if outside
      (progn
        (spa:dimov ac1 ac2 (list (* 0.5 (+ (car ac1) (car ac2)))
                                 (+ cyhi spa:*topoff*)))
        (spa:dimov up1 up2 (list (- cxlo spa:*dimoff*)
                                 (* 0.5 (+ (cadr up1) (cadr up2))))))
      (progn
        (spa:dimov ac1 ac2 (spa:mid ac1 ac2))
        (spa:dimov up1 up2 (spa:mid up1 up2))))
  (princ))

;; The four points an outline is dimensioned from when its pair goes
;; INSIDE: a third of the way up from the bottom for the across dim and
;; a third of the way in from the left for the up dim, each pair lying on
;; its own dimension line.  inx / iny push the station clear of a cut
;; corner, so the arrows always land on a straight run of the outline.
;; Returns (across1 across2 up1 up2).
(defun spa:insidepts (xlo xhi ylo yhi inx iny / xst yst)
  (setq xst (+ xlo (max (* (- xhi xlo) spa:*insetfrac*) (* 1.05 inx)))
        yst (+ ylo (max (* (- yhi ylo) spa:*insetfrac*) (* 1.05 iny))))
  (list (list xlo yst) (list xhi yst)
        (list xst ylo) (list xst yhi)))

;; The overlap between the two outlines, dimensioned at the BOTTOM: how
;; far the cover laps the water's edge.  The lap is far too small to hold
;; its own text, so the note is parked below the cover -- DIMTMOVE 1
;; gives it a leader back to the dimension.
(defun spa:dimlap (x ycov ywe / om)
  (setq om (getvar "DIMTMOVE"))
  (spa:setv "DIMTMOVE" 1)
  (spa:dimalg (list x ycov) (list x ywe) (list x (* 0.5 (+ ycov ywe)))
              " Overlap")
  (spa:dimtextat (entlast)
                 (list x (- (min ycov ywe) spa:*lapoff*)))
  (if om (spa:setv "DIMTMOVE" om))
  (princ))

;; Report rows for the second outline, tagged with which one it is.
(defun spa:otherrows (across up)
  (list (list (strcat (strcase (spa:modeword spa:*mode*)) " ACROSS") across across)
        (list (strcat (strcase (spa:modeword spa:*mode*)) " UP") up up)))


;;; -------------------- hinges -----------------------------------------
;;;
;;;  After the cover is drawn (and dimensioned) the command offers to
;;;  AUTO-HINGE it.  Hinges run north-south, splitting the cover into
;;;  side-by-side pieces along its west-east length.
;;;
;;;  1.  SPILLAWAYS -- places a hinge cannot go.  Asked in a loop that
;;;      always defaults to No: a CORNER spillaway blocks a typed length
;;;      from that (hypotenuse) corner along both of its walls; a WALL
;;;      spillaway is a typed overall length assumed centred on its
;;;      wall.  A left/right wall spillaway cannot collide with a
;;;      north-south hinge, so it is only recorded.
;;;
;;;  2.  The "Spa Cover Details" block supplies the GRADE and TAPER
;;;      (Enter types the taper instead; no grade given means
;;;      Standard).  Grade + taper give, from the foam sheets:
;;;        foam width   the widest a piece may be = max hinge spacing
;;;        foam length  the longest a hinge may run -- exceeded, the
;;;                     hinge is still drawn and the report says so
;;;        pieces       which piece counts are acceptable
;;;
;;;  3.  The FEWEST pieces that fit the foam width are used, spaced
;;;      evenly, then nudged off any spillaway zone.  A nudge keeps
;;;      every piece inside the foam width; when no nudge works the
;;;      piece count is bumped, and failing everything the even layout
;;;      is kept and the report says which hinge is in a zone.
;;;
;;;  Fold vs velcro follows the Hinge Arrangement Chart: the pieces
;;;  fold up in PAIRS from both ends -- a sewn FOLD hinge inside each
;;;  pair, Velcro between bundles -- so a 5-piece cover reads Hinge /
;;;  Velcro / Velcro / Hinge, and an odd count leaves one flat piece
;;;  at or beside the centre.  The leftmost hinge is always a fold and
;;;  no two folds are ever adjacent.  (Thermo-Light: all velcro.)
;;;
;;;  The linework matches the office template's sample: the fold hinge
;;;  is a DASHED2 line on COVER scaled to a 5" dash, velcro hinges are
;;;  ByLayer lines on COVER, and every label is a vertical MTEXT in
;;;  the Attributes style (Standard when absent) at a fixed 5" height,
;;;  bottom-centred 3" west of its hinge, on the TEXT layer.

;; Foam sheet: (grade taper ((foamW . foamL) ...) (piece counts, 5 = 5+))
;; A grade+taper with two width options (48" / 49-1/2") carries both;
;; the solver picks the one that needs the fewest hinges.
(setq spa:*foamtab*
  (list
    (list "ECONOMY"     "3-2"   (list (cons 48.0 96.0))                  (list 2))
    (list "STANDARD"    "3-2"   (list (cons 48.0 144.0) (cons 49.5 102.0)) (list 2))
    (list "STANDARD"    "4-2"   (list (cons 48.0 96.0)  (cons 49.5 102.0)) (list 2 3 4))
    (list "STANDARD"    "4-3"   (list (cons 48.0 144.0))                 (list 2 3 4))
    (list "STANDARD"    "5-3"   (list (cons 48.0 96.0))                  (list 2 3 4 5))
    (list "STANDARD"    "5-4"   (list (cons 48.0 96.0))                  (list 2 3 4 5))
    (list "STANDARD"    "3-3"   (list (cons 48.0 144.0))                 (list 2 3 4 5))
    (list "ULTRA"       "3-2"   (list (cons 48.0 144.0))                 (list 2))
    (list "ULTRA"       "4-3"   (list (cons 48.0 96.0))                  (list 2 3 4))
    (list "ULTRA"       "3-3"   (list (cons 48.0 144.0))                 (list 2 3 4 5))
    (list "THERMOLIGHT" "1-3/8" (list (cons 53.0 nil))                   (list 2 3 4 5))))

;; Hardware called for by the LONGEST hinge, per grade.  Each rule is
;; (OVER <inches>) | (ALWAYS) | (NEVER) | (REQUEST).
(setq spa:*hardtab*
  (list                 ;  grade          velcro        double C      hold down
    (list "ECONOMY"     '(REQUEST)    '(REQUEST)    '(REQUEST))
    (list "STANDARD"    '(OVER 120.0) '(OVER 108.0) '(OVER 120.0))
    (list "ULTRA"       '(OVER 108.0) '(NEVER)      '(OVER 96.0))
    (list "THERMOLIGHT" '(ALWAYS)     '(NEVER)      '(NEVER))))

;; A rule against the longest hinge -> (needed . reason), needed nil when
;; the item is not called for.
(defun spa:hardverdict (rule len / k v)
  (setq k (car rule) v (cadr rule))
  (cond
    ((eq k 'ALWAYS)  (cons t   "always for this grade"))
    ((eq k 'NEVER)   (cons nil "not used on this grade"))
    ((eq k 'REQUEST) (cons t   "upon request only"))
    ((> len v)       (cons t   (strcat "hinge " (rtos len 2 1)
                                       " over " (rtos v 2 0))))
    (t               (cons nil (strcat "hinge " (rtos len 2 1)
                                       " not over " (rtos v 2 0))))))

;;; ---------- small string helpers (plain AutoLISP, no VL) ----------

(defun spa:trim (s)
  (while (and (> (strlen s) 0) (= " " (substr s 1 1)))
    (setq s (substr s 2)))
  (while (and (> (strlen s) 0) (= " " (substr s (strlen s) 1)))
    (setq s (substr s 1 (1- (strlen s)))))
  s)

;; "Taper: 4-2" -> "4-2" (everything after the last colon, trimmed)
(defun spa:aftercolon (s / i out)
  (setq i (strlen s) out s)
  (while (> i 0)
    (if (= ":" (substr s i 1))
        (progn (setq out (substr s (1+ i))) (setq i 0))
        (setq i (1- i))))
  (spa:trim out))

;; Normalise a taper string to a foam-sheet key ("3-3 Flat" -> "3-3").
(defun spa:tapernorm (v / u)
  (setq u (strcase v))
  (cond ((wcmatch u "*3-2*") "3-2")
        ((wcmatch u "*4-2*") "4-2")
        ((wcmatch u "*4-3*") "4-3")
        ((wcmatch u "*5-3*") "5-3")
        ((wcmatch u "*5-4*") "5-4")
        ((wcmatch u "*3-3*") "3-3")
        ((wcmatch u "*3/8*") "1-3/8")))

;; Normalise a grade; anything unrecognised (or missing) is Standard.
(defun spa:gradenorm (v / u)
  (setq u (strcase (if v v "")))
  (cond ((wcmatch u "*ECON*") "ECONOMY")
        ((or (wcmatch u "*ULTRA*") (wcmatch u "*FRP*")) "ULTRA")
        ((wcmatch u "*THERMO*") "THERMOLIGHT")
        (t "STANDARD")))

(defun spa:gradeshort (g)
  (cond ((= g "ECONOMY") "ECO") ((= g "STANDARD") "STD")
        ((= g "ULTRA") "ULTRA") (t "THERMO")))

;; Attributes of a block reference, as ((TAG . value) ...).
(defun spa:attribs (ename / e ed out)
  (setq e (entnext ename))
  (while (and e (setq ed (entget e)) (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq out (cons (cons (strcase (cdr (assoc 2 ed))) (cdr (assoc 1 ed))) out)
          e (entnext e)))
  (reverse out))

;;; ---------- geometry: the cover's north-south chord at x ----------

;; How far a corner treatment sets back along its walls.
(defun spa:cornsb (cc)
  (cond ((= (car cc) "Radius") (cadr cc))
        ((= (car cc) "Cut") (* (cadr cc) 0.70711))
        (t 0.0)))

;; Offset of a treated edge INTO the shape at rx along a wall of length
;; wlen; c1 is the corner at rx = 0, c2 the corner at rx = wlen.
(defun spa:edgeoff (rx wlen c1 c2 / sb r)
  (cond
    ((< rx (setq sb (spa:cornsb c1)))
     (if (= (car c1) "Radius")
         (progn (setq r (cadr c1))
                (- r (sqrt (max 0.0 (- (* r r) (* (- rx r) (- rx r)))))))
         (- sb rx)))
    ((> rx (- wlen (setq sb (spa:cornsb c2))))
     (setq rx (- wlen rx))
     (if (= (car c2) "Radius")
         (progn (setq r (cadr c2))
                (- r (sqrt (max 0.0 (- (* r r) (* (- rx r) (- rx r)))))))
         (- sb rx)))
    (t 0.0)))

;; (ybot ytop) of the rectangle (with corner treatments) at x, or nil.
(defun spa:chordrect (quad corners x / x0 y0 wlen hlen rx offb offt)
  (setq x0 (car (car quad)) y0 (cadr (car quad))
        wlen (- (car (cadr quad)) x0)
        hlen (- (cadr (cadddr quad)) y0)
        rx (- x x0))
  (if (and (> rx 1.0e-6) (< rx (- wlen 1.0e-6)))
      (progn
        (setq offb (spa:edgeoff rx wlen (nth 0 corners) (nth 1 corners))
              offt (spa:edgeoff rx wlen (nth 3 corners) (nth 2 corners)))
        (if (< (+ offb offt) hlen)
            (list (+ y0 offb) (- (+ y0 hlen) offt))))))

;; (ybot ytop) of a polygon at x, or nil.
(defun spa:chordpoly (pts x / n i p q tt ys)
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

;; (ybot ytop) of the circle / ellipse at x, or nil.
(defun spa:chordell (cen b a x / dx q dy)
  (setq dx (/ (- x (car cen)) (* 0.5 b))
        q (- 1.0 (* dx dx)))
  (if (> q 1.0e-9)
      (progn
        (setq dy (* 0.5 a (sqrt q)))
        (list (- (cadr cen) dy) (+ (cadr cen) dy)))))

;; desc = ("RECT" quad corners) | ("OCT" pts) | ("ROUND" cen b a)
(defun spa:chordat (desc x)
  (cond
    ((= (car desc) "RECT") (spa:chordrect (cadr desc) (caddr desc) x))
    ((= (car desc) "OCT")  (spa:chordpoly (cadr desc) x))
    (t (spa:chordell (cadr desc) (caddr desc) (cadddr desc) x))))

;;; ---------- the placement solver ----------

(defun spa:ceilv (v / f)
  (setq f (fix v))
  (if (> v (+ f 1.0e-6)) (1+ f) f))

;; The forbidden interval x falls inside, or nil.  Intervals are open,
;; so a hinge sitting exactly on a zone's edge is allowed.
(defun spa:inforb (x forb / hit f)
  (foreach f forb
    (if (and (> x (car f)) (< x (cadr f))) (setq hit f)))
  hit)

;; Even hinge stations for n pieces across [x1 x2].
(defun spa:heven (x1 x2 n / i out)
  (setq i 1 out nil)
  (while (< i n)
    (setq out (cons (+ x1 (* (- x2 x1) (/ (float i) n))) out)
          i (1+ i)))
  (reverse out))

;; Place the n-1 hinges of an n-piece layout, dodging the forbidden
;; zones.  Each hinge starts at its even station; one that lands in a
;; zone moves to the nearer zone edge that still leaves every piece --
;; taken and to come -- inside the foam width fw.  Returns the x list,
;; or nil when this piece count cannot dodge the zones.
(defun spa:hplace (x1 x2 n fw forb / i xs prev x lo hi f cand e ok)
  (setq prev x1 xs nil i 1 ok t)
  (while (and ok (< i n))
    (setq x (+ x1 (* (- x2 x1) (/ (float i) n)))
          lo (max (+ prev 0.01) (- x2 (* fw (- n i))))
          hi (min (+ prev fw) (- x2 0.01)))
    (if (> lo hi)
        (setq ok nil)
        (progn
          (if (< x lo) (setq x lo))
          (if (> x hi) (setq x hi))
          (setq f (spa:inforb x forb))
          (if f
              (progn
                (setq cand nil)
                (foreach e (if (< (- x (car f)) (- (cadr f) x))
                               (list (car f) (cadr f))
                               (list (cadr f) (car f)))
                  (if (and (not cand) (>= e lo) (<= e hi)
                           (not (spa:inforb e forb)))
                      (setq cand e)))
                (if cand (setq x cand) (setq ok nil))))
          (if ok (setq xs (cons x xs) prev x i (1+ i))))))
  (if (and ok (<= (- x2 prev) (+ fw 0.01)))
      (reverse xs)))

;; The longest hinge a station list would produce.
(defun spa:hmaxchord (desc xs / m ch x)
  (setq m 0.0)
  (foreach x xs
    (if (setq ch (spa:chordat desc x))
        (setq m (max m (- (cadr ch) (car ch))))))
  m)

;; Fewest pieces first: try n up to n+3 for a layout that dodges every
;; zone.  Returns (n x-list solvedflag); when nothing dodges, the even
;; minimum-count layout with the flag down.
(defun spa:hsolve (x1 x2 fw forb nmin / n xs)
  (setq n nmin)
  (while (and (<= n (+ nmin 3)) (not xs))
    (setq xs (spa:hplace x1 x2 n fw forb))
    (if (not xs) (setq n (1+ n))))
  (if xs
      (list n xs t)
      (list nmin (spa:heven x1 x2 nmin) nil)))

(defun spa:hallow (n allowed)
  (if (>= n 5) (member 5 allowed) (member n allowed)))

;; Fold or velcro for each hinge, per the Hinge Arrangement Chart.
;; The chart's P is the HINGE COUNT (pieces - 1), positions 0-indexed
;; west to east.  Fold ("Normal") hinges land on even positions and
;; velcro on odd -- across the whole row when pieces mod 4 is 0 or 2,
;; and only up to the chart's cutoff when it is 1 or 3, with the rest
;; MIRRORING the left half:
;;
;;     2  H              5  H V V H          8  H V H V H V H
;;     3  H V            6  H V H V H       9  H V H V V H V H
;;     4  H V H          7  H V H V V H
;;
;; Read as bundles: the pieces fold up in PAIRS from both ends (a fold
;; hinge inside each pair, velcro between bundles), an odd count leaving
;; one flat piece at or beside the centre.  The leftmost hinge is always
;; a fold, no two folds are ever adjacent, and 2- and 3-piece covers
;; come out exactly as they always have.  allvel (Thermo-Light) forces
;; every hinge to velcro.  Returns a list of "H" / "V", west to east.
(defun spa:hingetypes (n allvel / hc m zone p out)
  (setq hc (1- n)
        m (rem n 4)
        zone (cond ((or (= m 0) (= m 2)) hc)
                   ((= m 1) (/ hc 2))
                   (t (/ (+ hc 2) 2)))
        p 0 out nil)
  ;; built west to east, so the mirror lookup (nth (hc-1-p)) always
  ;; lands on a position already decided
  (while (< p hc)
    (setq out (append out
                      (list (cond (allvel "V")
                                  ((< p zone) (if (= 0 (rem p 2)) "H" "V"))
                                  (t (nth (- hc 1 p) out)))))
          p (1+ p)))
  out)

;;; ---------- drawing ----------

;; The fold hinge draws in the stock DASHED2 pattern (0.25 dash, 0.125
;; gap), defined here when the drawing lacks it, and scaled so the dash
;; plots 5" long no matter how the host drawing's LTSCALE is set --
;; ent-scale x LTSCALE x 0.25 = 5.  In the office template (LTSCALE 50)
;; that lands the sample drawing's exact 0.4.
(defun spa:hdash ( / lt)
  (setq lt (spa:ltmake "DASHED2"
                       "Dashed (.5x) _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _"
                       '(0.25 -0.125)))
  (if (/= lt "CONTINUOUS")
      (list (cons 6 lt) (cons 48 (* spa:*hdashmult* (spa:ltsc))))))

;; Label beside a hinge, per the template sample: MTEXT in the
;; Attributes style (Standard when the drawing has no such style),
;; fixed 5" height, reading upward via the (0 1) direction vector,
;; bottom-centred so its underside faces the hinge line, inserted 3"
;; west of the line at the hinge's midpoint.
(defun spa:htext (x ymid str)
  (entmake (list '(0 . "MTEXT")
                 '(100 . "AcDbEntity")
                 '(8 . "TEXT")
                 '(100 . "AcDbMText")
                 (cons 10 (spa:wp (list (- x (* 0.6 spa:*hingetxth*)) ymid)))
                 (cons 40 spa:*hingetxth*)
                 (cons 41 spa:*hingetxw*)
                 '(71 . 8)              ; bottom centre
                 '(72 . 5)              ; drawing direction: by style
                 (cons 1 str)
                 (cons 7 (if (tblsearch "STYLE" spa:*hingestyle*)
                             spa:*hingestyle* "Standard"))
                 (cons 11 '(0.0 1.0 0.0)))))

;;; ---------- the guided flow ----------

(defun spa:hask (msg back)
  (spa:askd msg nil nil back))

;; Ask the spillaways.  Returns them as measured -- (kind name length),
;; kind "Corner" or "Wall" -- NOT as x-intervals: the spa may still be
;; turned a quarter turn to get a hinge clear of one, and the turn is
;; applied where the zones are worked out (spa:spillzones).
;;
;; This is one of the repo's commit-as-you-go loops, so Back follows
;; that convention: it steps back a question within a spillaway, and
;; from the first question of one it REMOVES the spillaway just
;; committed before re-asking.  The feedback wording is the shared one.
(defun spa:askspill ( / spills loc cnr d wall v stage done)
  (setq spills nil done nil)
  (princ "\n(a spillaway is named on the spa AS MEASURED; the drawing may be turned to clear it)")
  (while (not done)
    (setq v (spa:askkw "Is there a spillaway" "Yes No" "Yes/No" "No"
                       (if spills t nil)))
    (cond
      ;; Back from the top question: drop the last spillaway and re-ask
      ((eq v 'SPA-BACK)
       (if spills
           (progn
             (princ "\nStepping back one spillaway.")
             (setq spills (cdr spills)))
           (princ "\nAlready at the first spillaway.")))
      ((= v "No") (setq done t))
      (t
       ;; one spillaway, its own questions Back-able among themselves
       (setq stage 0)
       (while (and stage (< stage 3))
         (cond
           ((= stage 0)
            (setq loc (spa:askkw "Spillaway location" "Corner Wall"
                                 "Corner/Wall(centred)" "Wall" t))
            (setq stage (if (eq loc 'SPA-BACK) nil 1)))
           ((= stage 1)
            (if (= loc "Corner")
                (setq cnr (spa:askkw "Which corner"
                                     "BottomLeft BottomRight TopRight TopLeft"
                                     "BottomLeft/BottomRight/TopRight/TopLeft"
                                     nil t))
                (setq wall (spa:askkw "On which wall" "Top Bottom Left Right"
                                      "Top/Bottom/Left/Right" nil t)))
            (setq stage (if (eq (if (= loc "Corner") cnr wall) 'SPA-BACK) 0 2)))
           (t
            (setq d (spa:hask (if (= loc "Corner")
                                  "Length from the corner to keep clear of hinges"
                                  "Overall length of the spillaway (centred)")
                              t))
            (if (eq d 'SPA-BACK)
                (setq stage 1)
                (progn
                  ;; commit it
                  (setq spills (cons (if (= loc "Corner")
                                         (list "Corner" cnr d)
                                         (list "Wall" wall d))
                                     spills))
                  (if (and (= loc "Wall") (member wall '("Left" "Right")))
                      (princ "\n(a left/right wall spillaway cannot meet a north-south hinge)"))
                  (setq stage 3)))))))))
  (reverse spills))

;;; ---------- spillaways in drawing space ----------
;;;
;;;  One quarter turn CLOCKWISE is the turn this file makes, and it
;;;  carries every wall and corner round with the shape:
;;;
;;;      bottom -> left    right -> bottom    top -> right    left -> top
;;;      A (BL) -> TL      B (BR) -> BL       C (TR) -> BR    D (TL) -> TR
;;;
;;;  which is the whole reason a turn can save a hinge: a spillaway that
;;;  was on the top or the bottom wall, square in the path of every
;;;  north-south hinge, comes to rest on a side wall where no hinge can
;;;  reach it.

;; A wall name after the turn (nil turn = as measured).
(defun spa:spillwall (w turn)
  (if turn
      (cond ((= w "Bottom") "Left")
            ((= w "Right") "Bottom")
            ((= w "Top") "Right")
            (t "Top"))
      w))

;; A corner name after the turn.
(defun spa:spillcnr (c turn)
  (if turn
      (cond ((= c "BottomLeft") "TopLeft")
            ((= c "BottomRight") "BottomLeft")
            ((= c "TopRight") "BottomRight")
            (t "TopRight"))
      c))

;; The forbidden x-intervals a spillaway list makes of the run [x1 x2]
;; with the shape drawn turned or not.  A corner spillaway blocks its
;; typed length in from that end of the run; a top or bottom wall one
;; blocks its length centred on the wall; a left or right wall one
;; blocks nothing at all -- no north-south hinge can meet it.
(defun spa:spillzones (spills x1 x2 turn / forb sp nm d)
  (setq forb nil)
  (foreach sp spills
    (setq d (caddr sp))
    (if (= (car sp) "Corner")
        (progn
          (setq nm (spa:spillcnr (cadr sp) turn))
          (if (member nm '("BottomLeft" "TopLeft"))
              (setq forb (cons (list x1 (+ x1 d)) forb))
              (setq forb (cons (list (- x2 d) x2) forb))))
        (progn
          (setq nm (spa:spillwall (cadr sp) turn))
          (if (member nm '("Top" "Bottom"))
              (setq forb (cons (list (- (* 0.5 (+ x1 x2)) (* 0.5 d))
                                     (+ (* 0.5 (+ x1 x2)) (* 0.5 d)))
                               forb))))))
  forb)

;; One report row per spillaway, named as it was MEASURED -- that is how
;; the field sheet reads -- with where it ended up on the drawing added
;; when the turn moved it.
(defun spa:spillrows (spills turn / rows sp nm as)
  (setq rows nil)
  (foreach sp spills
    (setq nm (cadr sp)
          as (if (= (car sp) "Corner")
                 (spa:spillcnr nm turn)
                 (spa:spillwall nm turn))
          rows (append rows
                       (list (list (strcat "SPILLWAY " (strcase nm)
                                           (if (= (car sp) "Wall") " WALL" "")
                                           (if (= as nm)
                                               ""
                                               (strcat " (DRAWN " (strcase as)
                                                       ")")))
                                   nil (caddr sp))))))
  rows)

;; Is this a Thermo-Light cover?  Its water's edge and cover size are
;; the same thing, and every one of its hinges is velcro.
(defun spa:thermop ()
  (and spa:*grade* (= spa:*grade* "THERMOLIGHT")))

;; Try to read GRADE and TAPER off a Spa Cover Details block.  Sets the
;; globals; either may be left nil.  Returns T when something was read.
(defun spa:readblock ( / sel ed bn att v got)
  (spa:osup)
  (setq sel (entsel "\nSelect the Spa Cover Details block <Enter to skip>: "))
  (spa:osdown)
  (if sel
      (progn
        (setq ed (entget (car sel)))
        (if (= "INSERT" (cdr (assoc 0 ed)))
            (progn
              (setq bn (cdr (assoc 2 ed)))
              (if (/= (strcase bn) "SPA COVER DETAILS")
                  (princ (strcat "\n(block is named \"" bn
                                 "\", not Spa Cover Details -- reading its tags anyway)")))
              (setq att (spa:attribs (car sel)))
              (if (setq v (cdr (assoc "GRADE" att)))
                  (setq spa:*grade* (spa:gradenorm (spa:aftercolon v)) got t))
              (if (setq v (cdr (assoc "TAPER" att)))
                  (setq spa:*taper* (spa:tapernorm (spa:aftercolon v)) got t))
              (if (null spa:*taper*)
                  (princ "\nNo readable TAPER tag on that block.")))
            (princ "\nThat is not a block reference."))))
  got)

;; Grade and taper for the hinge maths.  Whatever the block gave up front
;; stands; anything still missing is asked for now.  No grade at all
;; means Standard.  Returns (grade taper).
(defun spa:askdetails ( / v)
  (if (and (null spa:*grade*) (null spa:*taper*))
      (spa:readblock))                  ; not offered earlier -- offer now
  (if (null spa:*grade*) (setq spa:*grade* "STANDARD"))
  (if (spa:thermop) (setq spa:*taper* "1-3/8"))
  ;; getstring cannot take keywords, so Back is typed like a value here
  ;; -- B, BACK, U or UNDO alone, any case -- as the prompt says
  (while (null spa:*taper*)
    (setq v (getstring "\nTaper (3-2, 4-2, 4-3, 5-3, 5-4, 3-3, 1-3/8) [type B to go Back]: "))
    (if (spa:backstr v)
        (setq spa:*taper* 'SPA-BACK)
        (progn
          (setq spa:*taper* (spa:tapernorm v))
          (if (null spa:*taper*)
              (princ "\nNot a taper on the foam sheet -- again.")))))
  (if (eq spa:*taper* 'SPA-BACK)
      (progn (setq spa:*taper* nil) 'SPA-BACK)
      (list spa:*grade* spa:*taper*)))

;;; ---------- the foam sheet and the best layout on it ----------

;; The foam sheets a grade + taper may be cut from: (options counts got).
;; An Economy taper that only the Standard sheet carries falls back to
;; Standard; nothing on the sheet at all falls back to 48 x 96 with the
;; flag down.  It says nothing itself -- this is asked twice, once to
;; settle which way round the spa is drawn and once to lay the hinges
;; out -- so the caller that draws does the reporting.
(defun spa:foamopts (grade taper / row r)
  (foreach r spa:*foamtab*
    (if (and (not row) (= (car r) grade) (= (cadr r) taper))
        (setq row r)))
  (if (not row)
      (foreach r spa:*foamtab*
        (if (and (not row) (= (car r) "STANDARD") (= (cadr r) taper))
            (setq row r))))
  (if row
      (list (caddr row) (cadddr row) t)
      (list (list (cons 48.0 96.0)) (list 2 3 4 5) nil)))

;; The best layout over every foam sheet the taper carries.  A
;; grade/taper can carry MORE THAN ONE -- Standard 3-2 and 4-2 each come
;; in a 48 x 144/96 and a 49-1/2 x 102 -- and one can work where the
;; other will not: the wider sheet needs fewer hinges, the longer one
;; lets a hinge run further.  So every option is solved and SCORED on
;; what it satisfies -- dodging the spillaways (4), fitting the foam
;; length (2), an acceptable piece count (1) -- and only then on fewest
;; pieces.  Returns (n xs fw fl solved lenok pcok maxchord score).
(defun spa:hbest (desc x1 x2 forb opts allowed / best bestsc opt fw fl nmin
                                                 res mc lenok pcok sc cand)
  (setq best nil bestsc -1)
  (foreach opt opts
    (setq fw (car opt)
          fl (cdr opt)
          nmin (max 2 (spa:ceilv (/ (- x2 x1) fw)))
          res (spa:hsolve x1 x2 fw forb nmin)
          mc (spa:hmaxchord desc (cadr res))
          lenok (or (null fl) (<= mc (+ fl 0.01)))
          pcok (if (spa:hallow (car res) allowed) t nil)
          sc (+ (if (caddr res) 4 0) (if lenok 2 0) (if pcok 1 0))
          cand (list (car res) (cadr res) fw fl (caddr res) lenok pcok mc sc))
    (if (or (null best)
            (> sc bestsc)
            (and (= sc bestsc) (< (car cand) (car best)))
            ;; nothing to choose on either -> the longer sheet, so a
            ;; hinge that overruns overruns by as little as it can
            (and (= sc bestsc) (= (car cand) (car best))
                 (> (if fl fl 0.0)
                    (if (nth 3 best) (nth 3 best) 0.0))))
        (setq best cand bestsc sc)))
  best)

;;; ---------- which way round to draw the spa ----------
;;;
;;;  Hinges run north-south, so a spillaway on the top or the bottom
;;;  wall stands in the way of every one of them while the same
;;;  spillaway on a side wall cannot touch any.  A quarter turn moves it
;;;  there -- the drafter's own dodge -- and it is taken here whenever
;;;  the spa laid out the way the long-overall rule wants cannot get its
;;;  hinges clear and the other way round can.  Both ways round are
;;;  scored on the layout score above, so the turn is never taken to
;;;  clear a zone at the price of a hinge that overruns the foam.
;;;
;;;  It is a PROBE: nothing is drawn yet.  The run it measures is the
;;;  outline in hand, which may still grow a water's edge (or a cover)
;;;  afterwards -- a lap of an inch or three either way, against zones
;;;  measured in feet.  The layout that is finally drawn is solved again
;;;  on the real cover, in spa:hingeflow.

;; c = (desc x1 x2), one way round.  Its layout score.
(defun spa:hscore (c turn opts allowed)
  (nth 8 (spa:hbest (car c) (cadr c) (caddr c)
                    (spa:spillzones spa:*spills* (cadr c) (caddr c) turn)
                    opts allowed)))

;; pref = the way round the long-overall rule asks for (T = turned).
;; c0 / c1 describe the spa unturned and turned.  Returns the way round
;; to draw it: pref unless the other way round scores strictly better.
(defun spa:pickturn (pref c0 c1 / fo opts allowed sp so)
  (if (or (null spa:*hingeon*) (null spa:*spills*))
      pref
      (progn
        (setq fo (spa:foamopts (if spa:*grade* spa:*grade* "STANDARD")
                               spa:*taper*)
              opts (car fo)
              allowed (cadr fo)
              sp (spa:hscore (if pref c1 c0) pref opts allowed)
              so (spa:hscore (if pref c0 c1) (not pref) opts allowed))
        (if (> so sp)
            (progn
              (setq spa:*spillturn* t)
              (princ (strcat "\nA hinge cannot be got clear of the spillway that way round"
                             " -- the spa is turned a quarter turn instead."))
              (spa:advise "TURNED A QUARTER TURN TO CLEAR THE SPILLWAY")
              (not pref))
            pref))))

;; The questions the hinges need, asked BEFORE the outline is drawn:
;; the answers can still turn the spa at that point, and nothing that is
;; already on the screen can be turned.  Fills spa:*spills* and the
;; grade / taper globals; returns T when the cover is to be hinged.
(defun spa:hingeask ( / gt)
  (setq spa:*spills* nil
        spa:*hingeon*
        (= "Yes" (spa:askkw "Auto-hinge the cover" "Yes No" "Yes/No" "Yes" nil)))
  (if spa:*hingeon*
      ;; 1 -- where hinges cannot go, then 2 -- grade + taper.  Back at
      ;; the taper re-opens the spillaways, its previous question.
      (progn
        (setq gt 'SPA-BACK)
        (while (eq gt 'SPA-BACK)
          (setq spa:*spills* (spa:askspill)
                gt (spa:askdetails)))))
  spa:*hingeon*)

;; The auto-hinge pass itself.  desc / x1 / x2 describe the COVER
;; outline; coverp nil means only the water's edge was drawn and the
;; hinges are being laid on that.  Everything it asks was asked before
;; the spa was drawn (spa:hingeask); this draws the hinges on the
;; outline as it ended up and returns the report rows.
(defun spa:hingeflow (desc x1 x2 th coverp / forb grade taper fo opts allowed
                         best n xs fw fl hw h nm vd allvel htys hty
                         k x ch maxch maxpc prev lbl)
  (setq spa:*hingerows* nil)
  (if (not spa:*hingeon*)
      nil
      (progn
        (if (not coverp)
            (spa:valnote "NO COVER OUTLINE - HINGES LAID ON THE WATER'S EDGE"))
        (setq grade (if spa:*grade* spa:*grade* "STANDARD")
              taper spa:*taper*
              ;; Thermo-Light is velcro throughout -- no fold hinge
              allvel (spa:thermop))
        (if allvel
            (spa:advise "THERMO-LIGHT: EVERY HINGE IS VELCRO - NO FOLD HINGE"))
        (setq fo (spa:foamopts grade taper)
              opts (car fo)
              allowed (cadr fo))
        (if (not (caddr fo))
            (spa:valnote (strcat "GRADE/TAPER " grade " " taper
                                 " NOT ON THE FOAM SHEET - 48/96 ASSUMED")))
        ;; 3 -- the spillaway zones as the spa was finally drawn, then
        ;; the foam sheet and the layout on it
        (setq spa:*hingerows* (spa:spillrows spa:*spills* spa:*turned*)
              forb (spa:spillzones spa:*spills* x1 x2 spa:*turned*)
              best (spa:hbest desc x1 x2 forb opts allowed)
              n (car best) xs (cadr best) fw (caddr best) fl (nth 3 best))
        (if (not (nth 4 best))
            (spa:valnote "SPILLAWAY ZONES COULD NOT ALL BE AVOIDED - CHECK HINGES"))
        (if (not (spa:hallow n allowed))
            (spa:valnote (strcat (itoa n) " PIECES NOT ACCEPTABLE FOR "
                                 (spa:gradeshort grade) " " taper)))
        ;; say which sheet was taken when the taper offers a choice
        (if (> (length opts) 1)
            (spa:advise (strcat "FOAM SHEET USED: " (rtos fw 2 2) " x "
                                (if fl (rtos fl 2 0) "N/A")
                                " (this taper has "
                                (itoa (length opts)) " sheets)")))
        ;; 4 -- draw them per the Hinge Arrangement Chart: FOLD hinges
        ;; (dashed, "Hinge") and Velcro (ByLayer, "Velcro Hinge") laid
        ;; out by spa:hingetypes -- pairs folding from both ends, so a
        ;; 5-piece cover reads Hinge / Velcro / Velcro / Hinge
        (setq htys (spa:hingetypes n allvel)
              k 0 maxch 0.0)
        (foreach x xs
          (setq ch (spa:chordat desc x)
                hty (nth k htys))
          (if ch
              (progn
                (setq maxch (max maxch (- (cadr ch) (car ch))))
                (if (= hty "H")
                    (spa:line (list x (car ch)) (list x (cadr ch))
                              "COVER" (spa:hdash))
                    (spa:line (list x (car ch)) (list x (cadr ch))
                              "COVER" nil))
                (spa:htext x (* 0.5 (+ (car ch) (cadr ch)))
                           (if (= hty "H") "Hinge" "Velcro Hinge"))
                (if (and fl (> (- (cadr ch) (car ch)) (+ fl 0.01)))
                    (spa:valnote (strcat "HINGE " (itoa (1+ k))
                                         " EXCEEDS THE FOAM LENGTH ("
                                         (rtos (- (cadr ch) (car ch)) 2 1)
                                         " > " (rtos fl 2 0) ")")))
                (if (spa:inforb x forb)
                    (spa:valnote (strcat "HINGE " (itoa (1+ k))
                                         " FALLS IN A SPILLAWAY ZONE")))))
          (setq k (1+ k)))
        (if (null fl)
            (spa:valnote "THERMOLIGHT: HINGE LENGTH N/A - VERIFY"))
        ;; 4b -- hardware called for by the longest hinge
        (setq hw nil)
        (foreach h spa:*hardtab*
          (if (and (not hw) (= (car h) grade)) (setq hw h)))
        (if hw
            (progn
              (setq k 0)
              (foreach nm (list "VELCRO HINGES" "DOUBLE C CHANNEL" "HOLD DOWN KIT")
                (setq vd (spa:hardverdict (nth (1+ k) hw) maxch))
                (if (car vd)
                    (spa:advise (strcat nm ": YES - " (cdr vd)))
                    (spa:advise (strcat nm ": no - " (cdr vd))))
                (setq k (1+ k)))))
        ;; 5 -- report rows: the pieces, their worst width, each hinge
        (setq maxpc 0.0 prev x1)
        (foreach x (append xs (list x2))
          (setq maxpc (max maxpc (- x prev)) prev x))
        (setq spa:*hingerows*
              (append spa:*hingerows*
                      (list (list (strcat "PIECES (" (spa:gradeshort grade)
                                          " " taper ")")
                                  nil (float n))
                            (list "FOAM WIDTH MAX" fw maxpc)
                            (list "FOAM LENGTH MAX" fl maxch))))
        (setq k 0)
        (foreach x xs
          (setq lbl (strcat "HINGE " (itoa (1+ k))
                            (if (= (nth k htys) "H") " (FOLD)" " (VELCRO)"))
                spa:*hingerows*
                (append spa:*hingerows* (list (list lbl nil (- x x1))))
                k (1+ k)))
        spa:*hingerows*)))

;;; -------------------- rectangle corner treatments --------------------
;;;
;;;  A corner is Square, Radius, Cut or NotGiven -- the canonical
;;;  Treatment set (STANDARDS section 2).  Side lengths are measured to
;;;  the TRUE (sharp) corner; the treatment cuts inward from there.
;;;  The size typed is:
;;;    Radius -> the corner RADIUS
;;;    Cut    -> the CHAMFER FACE length (the cut itself)
;;;  Square takes no size, and NotGiven takes none either: nothing was
;;;  measured, so its corner is BUILT square and flagged instead.

;; The two points where a corner's treatment meets the straight sides
;; (toward the previous / next corner) plus, for Radius, the arc mid.
;; Returns (ePrev eNext arcMid|nil).  A 90 corner -> (P P nil).
(defun spa:cornerends (p pp pn ctype size / uprev unext dp ang sb bis cen)
  (setq uprev (spa:unit (spa:v- pp p))
        unext (spa:unit (spa:v- pn p))
        dp (spa:dot uprev unext)
        ang (atan (sqrt (max 0.0 (- 1.0 (* dp dp)))) dp))   ; interior angle
  (cond
    ((= ctype "Cut")
     (setq sb (/ size (* 2.0 (sin (/ ang 2.0)))))           ; face -> edge setback
     (list (spa:v+ p (spa:v* uprev sb))
           (spa:v+ p (spa:v* unext sb)) nil))
    ((= ctype "Radius")
     (setq sb (/ (* size (cos (/ ang 2.0))) (sin (/ ang 2.0)))  ; r/tan(ang/2)
           bis (spa:unit (spa:v+ uprev unext))
           cen (spa:v+ p (spa:v* bis (/ size (sin (/ ang 2.0))))))
     (list (spa:v+ p (spa:v* uprev sb))
           (spa:v+ p (spa:v* unext sb))
           (spa:v- cen (spa:v* bis size))))                 ; arc point nearest corner
    (t (list p p nil))))

;; Every corner's ends, in corner order.
(defun spa:allends (q corners)
  (mapcar '(lambda (i)
             (spa:cornerends (nth i q)
                             (nth (rem (+ i 3) 4) q)
                             (nth (rem (+ i 1) 4) q)
                             (car (nth i corners)) (cadr (nth i corners))))
          (list 0 1 2 3)))

;; A reference point at corner i of quad q:
;;   spec = 'true (the sharp corner) | 'prev | 'next (the treatment ends)
(defun spa:cornerpoint (q corners i spec / ce)
  (setq ce (spa:cornerends (nth i q)
                           (nth (rem (+ i 3) 4) q)
                           (nth (rem (+ i 1) 4) q)
                           (car (nth i corners)) (cadr (nth i corners))))
  (cond ((eq spec 'prev) (car ce))
        ((eq spec 'next) (cadr ce))
        (t (nth i q))))

;; Draw the rectangle perimeter with its corner treatments, as ONE
;; closed polyline.  A radius corner becomes an arc segment (its bulge
;; is tan of a quarter of the angle the arc sweeps, which for a square
;; corner is tan 22.5 = 0.4142); a diagonal becomes a straight segment
;; between its two ends; a 90 corner is a single vertex.
;;
;; Returns a per-corner list holding the polyline's entity name at each
;; RADIUS corner and nil elsewhere, so the corner callouts still have
;; something to hang a radius dimension on -- DIMRADIUS takes a polyline
;; arc segment picked at a point on it just as it takes a bare arc.
(defun spa:drawrect (q corners / ce i j tyi verts pl p pp pn uprev unext
                                 dp ang arcs)
  (setq ce (spa:allends q corners) verts nil)
  (foreach i (list 0 1 2 3)
    (setq tyi (car (nth i corners)))
    (cond
      ((= tyi "Cut")
       (setq verts (cons (cons (cadr (nth i ce)) 0.0)
                         (cons (cons (car (nth i ce)) 0.0) verts))))
      ((/= tyi "Radius")
       ;; Square, and NotGiven drawn as built -- a single sharp vertex,
       ;; straight out to the next corner
       (setq verts (cons (cons (nth i q) 0.0) verts)))
      (t                                ; Radius
       (setq p  (nth i q)
             pp (nth (rem (+ i 3) 4) q)
             pn (nth (rem (+ i 1) 4) q)
             uprev (spa:unit (spa:v- pp p))
             unext (spa:unit (spa:v- pn p))
             dp (spa:dot uprev unext)
             ang (atan (sqrt (max 0.0 (- 1.0 (* dp dp)))) dp)
             ;; the fillet sweeps the corner's exterior angle, and the
             ;; walk is counter-clockwise, so the bulge is positive
             verts (cons (cons (cadr (nth i ce)) 0.0)
                         (cons (cons (car (nth i ce)) (spa:bulge (- pi ang)))
                               verts))))))
  (setq pl (spa:perpoly (reverse verts)) arcs nil)
  (foreach i (list 0 1 2 3)
    (setq arcs (cons (if (= (car (nth i corners)) "Radius") pl nil) arcs)))
  (reverse arcs))

;; How far the deepest corner treatment sets back along its walls -- an
;; inside dimension has to stand clear of that to land on a straight run.
(defun spa:maxsetback (corners / m c)
  (setq m 0.0)
  (foreach c corners
    (setq m (max m (cond ((= (car c) "Radius") (cadr c))
                         ((= (car c) "Cut") (* (cadr c) 0.70711))
                         (t 0.0)))))
  m)

;; Do all four corners carry the same treatment?  Four identical corners
;; get ONE callout with a Typ. suffix, the way the order sheet shows it.
(defun spa:samecorners (corners / c c0 same)
  (setq c0 (car corners) same t)
  (foreach c corners
    (if (or (/= (car c) (car c0))
            (> (abs (- (cadr c) (cadr c0))) 0.0005))
        (setq same nil)))
  same)

;; The order sheet's circled corner mark: a small circle on the corner
;; point with a leader out along its outward diagonal saying txt.
;; Assumes CLAYER is already DIMENSION.
(defun spa:cmark (quad i cen doff txt / p outd r)
  (setq p (nth i quad)
        outd (spa:unit (spa:v- p cen))
        r (* 0.18 doff))
  (entmake (list '(0 . "CIRCLE")
                 (cons 8 "DIMENSION")
                 (cons 10 (spa:wp p))
                 (cons 40 r)))
  (command "_.LEADER" (spa:wp (spa:v+ p (spa:v* outd r)))
           (spa:wp (spa:v+ p (spa:v* outd (* 1.2 doff))))
           "" txt ""))

;; A Square corner's mark asserts the 90.
(defun spa:dim90 (quad i cen doff sfx)
  (spa:cmark quad i cen doff (strcat "90%%d" sfx)))

;; A NotGiven corner: the same circled mark, but the leader asks a
;; question instead of asserting an angle, and a note under it spells
;; the reason out -- the sheet has to SAY the treatment was never
;; recorded, not silently claim a 90.  The note is pulled back by its
;; own width when the corner points LEFT: text runs left-to-right from
;; its insertion point, so an unadjusted note there would read back
;; across its own leader and into the spa.
(defun spa:dimng (quad i cen doff sfx / p outd h tp)
  (spa:cmark quad i cen doff (strcat "?" sfx))
  (setq p (nth i quad)
        outd (spa:unit (spa:v- p cen))
        h (* 0.25 doff)
        tp (spa:v+ p (spa:v* outd (* 1.45 doff))))
  (if (< (car outd) 0.0)
      (setq tp (list (- (car tp) (* 9.0 0.6 h)) (cadr tp))))
  (spa:text tp h "Not Given" "DIMENSION"))

;; Corner callouts, laid out the way the order sheet does them: the note
;; sits OUTSIDE the corner, on the 45-degree line out of it.
;;   Radius   -> a radius dimension read from outside the arc  (R12")
;;   Cut      -> an aligned dimension across the cut face      (21")
;;   Square   -> a circled corner point with a 90%%d leader
;;   NotGiven -> the circled point with a ? leader and a Not Given note
;;
;; Four identical corners are called out ONCE, at the bottom-right, with
;; a Typ. suffix -- so an all-Square cover gets one 90%%d Typ. mark and
;; an all-NotGiven one gets one ? Typ. with its note (STANDARDS section
;; 2).  Mixed corners are called out one by one: the Square ones among
;; them share a single 90-degree mark (Typ. when there is more than
;; one), placed by spa:dimcorners, and each NotGiven one gets its own
;; mark -- ? asserts nothing, so it is never shared.
;;
;; None of these ever carry the Water's Edge / Cover Size note: they are
;; corners, not overalls.  Assumes CLAYER is already DIMENSION.
(defun spa:dimcorner1 (quad corners arcs cen doff i sfx / cc ce p pp pn ty
                                                          outd am fm)
  (setq p (nth i quad)
        pp (nth (rem (+ i 3) 4) quad)
        pn (nth (rem (+ i 1) 4) quad)
        cc (nth i corners)
        ty (car cc)
        ce (spa:cornerends p pp pn ty (cadr cc))
        outd (spa:unit (spa:v- p cen)))
  (cond
    ((= ty "Radius")
     (setq am (caddr ce))
     (spa:dimrad (nth i arcs) am outd doff sfx))
    ((= ty "Cut")
     (setq fm (spa:mid (car ce) (cadr ce)))
     (spa:dimalg (car ce) (cadr ce)
                 (spa:v+ fm (spa:v* outd (* 0.6 doff))) sfx))
    ((= ty "NotGiven")
     (spa:dimng quad i cen doff sfx))
    (t                                  ; Square
     (spa:dim90 quad i cen doff sfx)))
  (princ))

(defun spa:dimcorners (quad corners arcs cen doff / allsame sfx ilist nsq sqi i)
  (setq allsame (spa:samecorners corners)
        sfx (if allsame " Typ." "")
        ilist (if allsame (list 1) (list 0 1 2 3)))   ; 1 = bottom-right
  ;; in a MIXED set the Square corners are skipped here: they share the
  ;; single mark placed below, where every other treatment (a ? mark
  ;; included) is called out on its own corner
  (foreach i ilist
    (if (or allsame (/= (car (nth i corners)) "Square"))
        (spa:dimcorner1 quad corners arcs cen doff i sfx)))
  (if (not allsame)
      (progn
        (setq nsq 0 sqi nil)
        (foreach i (list 1 0 2 3)       ; scanned from the bottom-right
          (if (= (car (nth i corners)) "Square")
              (progn (setq nsq (1+ nsq))
                     (if (null sqi) (setq sqi i)))))
        (if sqi (spa:dim90 quad sqi cen doff (if (> nsq 1) " Typ." "")))))
  (princ))

;; Re-draw the guide rectangle's corners with the chosen treatments so
;; the picture matches what will be built.  gq = the guide quad,
;; corners = per-corner (type size) with the sizes already clamped for
;; display.  Returns the updated pv.
(defun spa:pvcorners (pv gq corners / ce i k cc ent)
  (foreach k (list 'ab 'bc 'cd 'da)
    (spa:pvdel (cdr (assoc k pv))))
  (setq ce (spa:allends gq corners))
  ;; shortened straight sides (side i runs corner i -> corner i+1)
  (setq i 0)
  (foreach k (list 'ab 'bc 'cd 'da)
    (setq ent (spa:pvadd (spa:pvline (cadr (nth i ce))
                                     (car (nth (rem (+ i 1) 4) ce))))
          pv (subst (cons k (list ent)) (assoc k pv) pv)
          i (1+ i)))
  ;; the corner treatments themselves
  (setq i 0)
  (foreach cc corners
    (cond
      ((= (car cc) "Cut")
       (spa:pvadd (spa:pvline (car (nth i ce)) (cadr (nth i ce)))))
      ((= (car cc) "Radius")
       (spa:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce))
                  "SPA-NOTES" nil)
       (spa:pvadd (spa:setcol (entlast) spa:*pv-col*))))
    (setq i (1+ i)))
  pv)

;; The canonical Treatment question (STANDARDS section 2).  The bracket
;; is DERIVED from the visible words, so a click on it can never miss;
;; the legacy words -- 90, ROUNDED, DIAG/DIAGONAL, and NG for NotGiven
;; -- ride along as ALL-CAPS hidden aliases in the initget list only,
;; and are normalised to the canonical word HERE, so nothing downstream
;; ever sees them.
(defun spa:asktreat (subject dflt back / v kws)
  (setq kws "Square Radius Cut NotGiven")
  (setq v (spa:askkw (strcat "How should " subject " be treated?")
                     (strcat kws " NG 90 ROUNDED DIAG DIAGONAL")
                     (vl-string-translate " " "/" kws)
                     dflt back))
  (cond ((eq v 'SPA-BACK) v)
        ((= v "NG") "NotGiven")
        ((= v "90") "Square")
        ((= v "ROUNDED") "Radius")
        ((member v '("DIAG" "DIAGONAL")) "Cut")
        (t v)))

;; Does this treatment cut real geometry off the corner?  NotGiven does
;; NOT: its corner is built square, so everything that asks "is there a
;; cut here" -- the setback caps, the flats, the hinge chords -- must
;; answer no.  Only the report and the corner marks care that it is not
;; a plain Square.
(defun spa:cutp (ty) (member ty '("Radius" "Cut")))

;; The fixed wording of the size follow-up (STANDARDS section 2).
(defun spa:cornersizemsg (ty label)
  (strcat (if (= ty "Radius") "Radius for " "Cut face length for ") label))

;; Prompt one corner's treatment -- the canonical question, through
;; spa:asktreat.  dflty/dfltsz are the autofill answer (corner A's) --
;; Enter accepts them.  maxsb caps the treatment's setback along the
;; walls at half the shorter adjacent wall, so two treatments can never
;; overlap and fold the perimeter; too-large answers are re-asked.
;; Returns (type size) or SPA-BACK.
(defun spa:askcorner (label dflty dfltsz ents maxsb back / ty sz cols sb e
                                                            dsz out)
  (setq cols (mapcar 'spa:getcol ents))
  (foreach e ents (spa:setcol e spa:*hi-col*))
  (while (null out)
    (spa:osup)
    (setq ty (spa:asktreat label dflty back))
    (spa:osdown)
    (cond
      ;; backed out of the type question -- out of the corner entirely
      ((eq ty 'SPA-BACK) (setq out 'SPA-BACK))
      ;; Square has no size, and NotGiven has none either: nothing was
      ;; measured, so there is no number to ask for
      ((not (spa:cutp ty)) (setq out (list ty 0.0)))
      (t
       ;; the autofill size only stands in when it came from the SAME
       ;; treatment -- a radius is not a cut face
       (setq dsz (if (or (null dfltsz) (<= dfltsz 0.0) (/= ty dflty))
                     nil dfltsz)
             sz (spa:askd (spa:cornersizemsg ty label) nil dsz t))
       ;; Back at the size re-asks the type, its previous question
       (if (not (eq sz 'SPA-BACK))
           (progn
             ;; Radius sets back r along each wall; a Cut face f sets
             ;; back f/sqrt(2) on a 90-degree corner
             (while (and maxsb
                         (not (eq sz 'SPA-BACK))
                         (> (setq sb (if (= ty "Radius") sz (* sz 0.70711)))
                            maxsb))
               (princ (strcat "\nToo large for this corner's walls -- max "
                              (rtos (if (= ty "Radius") maxsb
                                        (/ maxsb 0.70711)))
                              ".  Re-enter."))
               (setq sz (spa:askd (spa:cornersizemsg ty label) nil nil t)))
             (if (not (eq sz 'SPA-BACK)) (setq out (list ty sz))))))))
  (mapcar '(lambda (e c) (spa:setcol e c)) ents cols)
  out)

;;; -------------------- rectangle flow ---------------------------------

;; Gray nominal rectangle with its corner letters.
(defun spa:rectpreview ( / gq cen pr ent all pv)
  (setq gq (list (list 0.0 0.0) (list 240.0 0.0)
                 (list 240.0 200.0) (list 0.0 200.0))
        cen (list 120.0 100.0)
        all nil pv nil)
  (setq pv (list (cons 'ab (list (spa:pvline (nth 0 gq) (nth 1 gq))))
                 (cons 'bc (list (spa:pvline (nth 1 gq) (nth 2 gq))))
                 (cons 'cd (list (spa:pvline (nth 2 gq) (nth 3 gq))))
                 (cons 'da (list (spa:pvline (nth 3 gq) (nth 0 gq)))))
        all (apply 'append (mapcar 'cdr pv)))
  (foreach pr (list (list (nth 0 gq) "A") (list (nth 1 gq) "B")
                    (list (nth 2 gq) "C") (list (nth 3 gq) "D"))
    (spa:text (spa:v+ (car pr)
                      (spa:v* (spa:unit (spa:v- (car pr) cen)) 22.0))
              12.0 (cadr pr) "SPA-NOTES")
    (setq ent (spa:setcol (entlast) spa:*pv-col*)
          all (cons ent all)
          pv (cons (cons (spa:lblkey (cadr pr)) (list ent)) pv)))
  (setq spa:*pvents* all)
  pv)

;; Full guided flow for a rectangular spa.
(defun spa:rectflow ( / oldclay pv gq gsc w l corners anycut arcs quad
                        a b c d cen doff th allsame i j tmp lbls cc back
                        rows lbl mode1 meth ans g w2 l2 c2 org2 q2 cen2 arcs2
                        xlo xhi ylo yhi out1 sb1 sb2 ip1 ip2 hrows done turn
                        rbox)
  (setq oldclay (getvar "CLAYER")
        pv (spa:rectpreview))
  (command "_.ZOOM" "_Window"
           (spa:wp (list -110.0 -90.0)) (spa:wp (list 350.0 320.0)))
  (princ "\nA gray guide spa is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C top-right, D top-left.")
  (princ "\n(Enter at the length takes the width, i.e. a square spa)")
  (princ "\n(Back re-asks the previous question)")

  ;; -------- the two overalls (a moulded shell is a true rectangle)
  (defun rc:sides ( / ans)
    (setq ans (spa:askseqb
                (list (list 'w 'REQ "Overall WIDTH across (A-B)"
                            (append (cdr (assoc 'ab pv)) (cdr (assoc 'cd pv))
                                    (spa:lbl pv '(lA lB))))
                      ;; the width is offered back as the length, so a
                      ;; square spa is one measurement and Enter -- type
                      ;; a different value to decline it
                      (list 'l 'SUG "Overall LENGTH up (A-D)"
                            (append (cdr (assoc 'da pv)) (cdr (assoc 'bc pv))
                                    (spa:lbl pv '(lA lD)))
                            '(w)))
                nil))
    (setq w (spa:sq ans 'w)
          l (if (spa:sq ans 'l) (spa:sq ans 'l) w))   ; NA -> square
    nil)

  ;; -------- corner treatments; corner A autofills B, C and D
  (defun rc:corners ( / )
    (princ "\n(corner A's answer autofills B, C and D -- Enter accepts it,")
    (princ "\n or type a different treatment for that corner)")
    (setq lbls (list "A" "B" "C" "D")
          corners nil i 0 back nil)
    (while (and (< i 4) (not back))
      (setq cc (spa:askcorner
                 (strcat "Corner " (nth i lbls))
                 (if (> i 0) (car (car (reverse corners))) nil)
                 (if (> i 0) (cadr (car (reverse corners))) nil)
                 (spa:lbl pv (list (spa:lblkey (nth i lbls))))
                 (* 0.5 (min w l))
                 t))
      (if (eq cc 'SPA-BACK)
          (if (= i 0)
              (setq back t)             ; back out of the whole stage
              (setq i (1- i) corners (cdr corners)))
          (setq corners (cons cc corners) i (1+ i))))
    (if back
        'SPA-BACK
        (progn
          (setq corners (reverse corners) anycut nil)
          (foreach cc corners (if (spa:cutp (car cc)) (setq anycut t)))
          ;; show the chosen treatments on the guide, scaled from the
          ;; real spa onto the 240 x 200 nominal and capped so a big
          ;; treatment cannot swallow the guide
          (setq gq (list (list 0.0 0.0) (list 240.0 0.0)
                         (list 240.0 200.0) (list 0.0 200.0))
                gsc (/ 240.0 (max w 1.0)))
          (if anycut
              (setq pv (spa:pvcorners
                         pv gq
                         (mapcar '(lambda (c)
                                    (list (car c) (min 50.0 (* (cadr c) gsc))))
                                 corners))))
          nil)))

  (spa:stages (list 'rc:sides 'rc:corners))
  (spa:pvkill)

  ;; -------------------------------------------------- hinges, asked now
  ;; The hinge questions come BEFORE anything is drawn because their
  ;; answers can still turn the spa -- a spillaway no north-south hinge
  ;; can dodge is dodged by turning the cover instead, and there is no
  ;; turning it once it is on the screen.  The hinges themselves are
  ;; drawn at the end, on whichever outline they belong to.
  (spa:hingeask)

  ;; -------------------------------------------------- orientation
  ;; The long overall always runs west to east, whichever order the two
  ;; were typed in.  Turning the cover a quarter turn clockwise carries
  ;; the corners round with it: the corner that was B lands bottom-left,
  ;; so the treatments and their letters rotate one step with the shape.
  ;; A spillaway that blocks every hinge one way round and none the
  ;; other overrules the long overall -- see spa:pickturn.
  (setq turn (spa:pickturn
               (> l w)
               (list (list "RECT" (spa:quadat (list 0.0 0.0) w l) corners)
                     0.0 w)
               (list (list "RECT" (spa:quadat (list 0.0 0.0) l w)
                           (append (cdr corners) (list (car corners))))
                     0.0 l)))
  (if turn
      (setq tmp w
            w l
            l tmp
            corners (append (cdr corners) (list (car corners)))
            lbls (append (cdr lbls) (list (car lbls)))
            spa:*turned* t))
  (if (and spa:*turned* (not spa:*spillturn*))
      (princ "\nThe long overall runs across, so the cover is drawn a quarter turn over."))

  (setq quad (spa:quadat (list 0.0 0.0) w l)
        a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (list (* 0.5 w) (* 0.5 l))
        doff (max 6.0 (/ (max w l) 12.0))
        th (max 1.0 (/ (max w l) 40.0))
        spa:*dashlt* (spa:ltload "DASHED")
        mode1 spa:*mode*)

  ;; ------------------------------------------- draw the first outline
  (setq arcs (spa:drawrect quad corners))

  ;; ------------------------------------------- and, if wanted, the other
  ;; Resolved BEFORE anything is dimensioned, because every dimension
  ;; line stands off the COVER outline -- the outer of the two.
  ;; Asked as one re-enterable unit: a Back anywhere inside either
  ;; branch re-opens the offer, so the method itself can be changed.
  (setq meth (spa:askother) done nil)
  (while (and meth (not done))
    (if (= meth "Offset")
        (progn
          (setq g (spa:askgap))
          (if (eq g 'SPA-BACK)
              (setq meth (spa:askother))
              (setq w2 (+ w (* 2.0 g))
                    l2 (+ l (* 2.0 g))
                    c2 (spa:offcorners corners g)
                    done t)))
        (progn
          (princ (strcat "\nThe two outlines share a centre; give the "
                         (spa:modeword (spa:othermode)) " as measured."))
          (setq ans (spa:askseqb
                      (list (list 'w2 'REQ (strcat (strcase (spa:modeword (spa:othermode)) t)
                                                   " overall ACROSS") nil)
                            (list 'l2 'SUG (strcat (strcase (spa:modeword (spa:othermode)) t)
                                                   " overall UP") nil '(w2)))
                      t))
          (if (eq ans 'SPA-BACK)
              (setq meth (spa:askother))
              (setq w2 (spa:sq ans 'w2)
                    l2 (if (spa:sq ans 'l2) (spa:sq ans 'l2) w2)
                    ;; the implied lap drives the corner sizes, which the
                    ;; user may then correct one at a time
                    g  (* 0.25 (+ (- w2 w) (- l2 l)))
                    c2 (spa:offcorners corners g)
                    c2 (spa:askothercorners c2 lbls (* 0.5 (min w2 l2)))
                    done t)))))
  (if (and meth done)
      (if (or (<= w2 0.0) (<= l2 0.0))
          (progn
            (spa:valnote "THE SECOND OUTLINE CAME OUT AT OR BELOW ZERO - SKIPPED")
            (setq meth nil))
          (setq org2 (spa:orgfor cen w2 l2)
                q2   (spa:quadat org2 w2 l2)
                cen2 cen)))

  ;; the cover is the larger, so its extents are the ones to stand off
  (setq xhi (if meth (max w (+ (car org2) w2)) w)
        ylo (if meth (min 0.0 (cadr org2)) 0.0)
        xlo (if meth (min 0.0 (car org2)) 0.0)
        yhi (if meth (max l (+ (cadr org2) l2)) l))

  ;; ------------------------------------------- draw the second outline
  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (setq arcs2 (spa:drawrect q2 c2))
        (spa:setmode mode1)))

  ;; -------------------------------------------------- dimensions
  ;; Laid out the way the order sheet does it.  The COVER's overalls go
  ;; outside -- across 2 ft above it, up 3 ft to its left.  The WATER'S
  ;; EDGE's overalls, when both outlines are drawn, go a third of the way
  ;; INTO the water's edge.  When all four corners match, that plus one
  ;; Typ. corner callout is the whole drawing; when they do not, each
  ;; side a cut has shortened also gets its remaining FLAT dimensioned.
  (setq allsame (spa:samecorners corners)
        out1 (or (null meth) (= mode1 "Coversize"))
        sb1 (spa:maxsetback corners)
        ip1 (spa:insidepts 0.0 w 0.0 l sb1 sb1))
  (setvar "CLAYER" "DIMENSION")
  (spa:dimstylenow th)
  ;; the overalls -- the only dims that carry the Water's Edge / Cover
  ;; Size note
  (if out1
      (spa:dimoveralls t d c a d xlo yhi)
      (spa:dimoveralls nil (nth 0 ip1) (nth 1 ip1) (nth 2 ip1) (nth 3 ip1)
                       xlo yhi))
  ;; the flats
  (if (not allsame)
      (foreach i (list 0 1 2 3)
        (setq j (rem (+ i 1) 4))
        (if (or (spa:cutp (car (nth i corners)))
                (spa:cutp (car (nth j corners))))
            (spa:dimalg (spa:cornerpoint quad corners i 'next)
                        (spa:cornerpoint quad corners j 'prev)
                        (spa:outoff (nth i quad) (nth j quad) cen spa:*flatoff*)
                        nil))))
  ;; corner callouts (no note -- these are corners, not overalls)
  (spa:dimcorners quad corners arcs cen doff)

  ;; the second outline, in ITS dimension style, plus one Typ. corner
  ;; callout at the top-left when its corners all match
  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (spa:dimstylenow th)
        (setq sb2 (spa:maxsetback c2)
              ip2 (spa:insidepts (car org2) (+ (car org2) w2)
                                 (cadr org2) (+ (cadr org2) l2) sb2 sb2))
        (if out1
            (spa:dimoveralls nil (nth 0 ip2) (nth 1 ip2) (nth 2 ip2) (nth 3 ip2)
                             xlo yhi)
            (spa:dimoveralls t (nth 3 q2) (nth 2 q2) (nth 0 q2) (nth 3 q2)
                             xlo yhi))
        (if (spa:samecorners c2)
            (spa:dimcorner1 q2 c2 arcs2 cen2 doff 3 " Typ."))
        (spa:setmode mode1)
        ;; and how far the cover laps the water's edge, at the bottom
        (spa:dimstyle spa:*ds-cover* th 1.0)
        (spa:dimlap (* 0.5 (+ xlo xhi)) ylo (max 0.0 (cadr org2))))
      nil)
  (setvar "CLAYER" oldclay)

  ;; -------------------------------------------------- report
  ;; the corner letters are NOT written on the drawing: they go on the
  ;; mini-model beside the report, below.  The letters travel with their
  ;; corners, so a turned cover still reads back against the table.
  (spa:modenote xlo (- ylo (* 1.4 spa:*dimoff*)) th)
  (setq rows (list (list (strcat "OVERALL ACROSS (" (nth 0 lbls) "-" (nth 1 lbls) ")")
                         w w)
                   (list (strcat "OVERALL UP (" (nth 0 lbls) "-" (nth 3 lbls) ")")
                         l l)))
  (setq i 0)
  ;; a NotGiven corner's row reads N/A in BOTH columns: nothing was
  ;; measured and nothing was built to a size -- the row exists to
  ;; record that the sheet never said
  (foreach cc corners
    (setq rows (append rows
                       (list (list (strcat "CORNER " (nth i lbls) " "
                                           (strcase (car cc)))
                                   (if (spa:cutp (car cc)) (cadr cc))
                                   (if (= (car cc) "NotGiven")
                                       nil (cadr cc)))))
          i (1+ i)))
  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (setq rows (append rows (spa:otherrows w2 l2)))
        (setq i 0)
        (foreach cc c2
          (setq rows (append rows
                             (list (list (strcat (strcase (spa:modeword spa:*mode*))
                                                 " COR " (nth i lbls) " "
                                                 (strcase (car cc)))
                                         (if (spa:cutp (car cc)) (cadr cc))
                                         (if (= (car cc) "NotGiven")
                                             nil (cadr cc)))))
                i (1+ i)))
        (spa:setmode mode1)))
  ;; -------------------------------------------------- hinges
  (setq hrows
    (cond ((= mode1 "Coversize")
           (spa:hingeflow (list "RECT" quad corners) 0.0 w th t))
          (meth
           (spa:hingeflow (list "RECT" q2 c2) (car org2) (+ (car org2) w2) th t))
          (t
           (spa:hingeflow (list "RECT" quad corners) 0.0 w th nil))))
  (if hrows (setq rows (append rows hrows)))
  (setq rbox (spa:report rows spa:*valnotes* (+ xhi spa:*dimoff*) yhi th
                         "SPA-NOTES"))
  ;; perimeter mini-model with the corner letters, right of the report
  (spa:minimap (spa:rectprims quad corners) quad (spa:mlbls quad lbls)
               (+ (car rbox) (* 3.0 th)) (cadr rbox) (* 24.0 th) th)
  (princ "\nSpa layout complete -- see the report table.")
  (princ))

;;; -------------------- octagon ----------------------------------------
;;;
;;;  Eight corners, counter-clockwise from the left end of the bottom
;;;  flat:
;;;                     F ---------- E
;;;                    /              \        B = overall across
;;;                   G                D       A = overall up
;;;                   |                |       T = the flats across
;;;                   H                C       V = the flats up
;;;                    \              /        S = cut along the side
;;;                     A ---------- B         S1 = cut up the end
;;;                                            S2 = the cut face itself
;;;
;;;  A and B are required; every cut letter may be NA, in which case the
;;;  shape falls back to a true square octagon (45-degree cuts, all eight
;;;  sides equal) sized off A and B.

(setq spa:*octnames* (list "A" "B" "C" "D" "E" "F" "G" "H"))

;; (i j kind) for each edge -- kind 'side is a flat, 'cut is a corner.
(setq spa:*octedges*
      (list '(0 1 side) '(1 2 cut) '(2 3 side) '(3 4 cut)
            '(4 5 side) '(5 6 cut) '(6 7 side) '(7 0 cut)))

;; Resolve the sheet letters against the overalls.
;;
;; The cut is normally measured as its FACE (S2) -- that is the tape run
;; a crew actually takes across the corner -- so a 45-degree face
;; resolves to equal legs, S = S1 = S2 / sqrt 2.  With even that
;; unmeasured the shape falls back to a true square octagon, where the
;; flats equal the cut faces:
;;   c = min(A,B) / (2 + sqrt 2)  ->  T = B - 2c,  V = A - 2c
;; Any letter that WAS measured wins and its partner is derived from it.
;; Returns (S T S1 V).
(defun spa:octov (aov bov sraw traw s1raw vraw s2raw / c s tv s1 v)
  (setq c (if s2raw
              (/ s2raw 1.41421356237)
              (/ (min aov bov) 3.41421356237)))
  (cond
    (sraw (setq s sraw tv (- bov (* 2.0 sraw))))
    (traw (setq s (/ (- bov traw) 2.0) tv traw))
    (t (setq s c tv (- bov (* 2.0 c)))))
  (cond
    (s1raw (setq s1 s1raw v (- aov (* 2.0 s1raw))))
    (vraw (setq s1 (/ (- aov vraw) 2.0) v vraw))
    ;; an unmeasured vertical cut matches the horizontal one (45 deg)
    (t (setq s1 s v (- aov (* 2.0 s)))))
  (list s tv s1 v))

;; The eight corner points for overalls a/b and cuts s (across) and
;; s1 (up).
(defun spa:octpts (bov aov s s1)
  (list (list s 0.0) (list (- bov s) 0.0)
        (list bov s1) (list bov (- aov s1))
        (list (- bov s) aov) (list s aov)
        (list 0.0 (- aov s1)) (list 0.0 s1)))

;; Gray nominal octagon (a regular one -- that is what the shape being
;; measured looks like) plus the overall-sheet ties.  Returns
;; (outline-pv . tie-pv).
(defun spa:octpreview ( / npts cen e p q ent all pv k pvo)
  (setq npts (spa:octpts 240.0 240.0 70.294 70.294)
        cen (spa:centroid npts)
        all nil pv nil)
  (foreach e spa:*octedges*
    (setq p (nth (car e) npts) q (nth (cadr e) npts)
          ent (spa:pvline p q)
          pv (cons (cons (list (car e) (cadr e)) (list ent)) pv)
          all (cons ent all)))
  (setq k 0)
  (foreach p npts
    (spa:text (spa:lbloff p cen npts 20.0) 12.0 (nth k spa:*octnames*) "SPA-NOTES")
    (setq ent (spa:setcol (entlast) spa:*pv-col*)
          all (cons ent all)
          pv (cons (cons (spa:lblkey (nth k spa:*octnames*)) (list ent)) pv)
          k (1+ k)))
  (setq spa:*pvents* all)
  ;; the field-sheet ties: B/T/S across the top, A/S1/V down the left,
  ;; S2 parallel to the bottom-right cut
  (setq pvo (list
    (spa:pvtie (list 0.0 300.0) (list 240.0 300.0) "B" 10.0)
    (spa:pvtie (list 70.294 278.0) (list 169.706 278.0) "T" 10.0)
    (spa:pvtie (list 0.0 278.0) (list 70.294 278.0) "S" 10.0)
    (spa:pvtie (list -85.0 0.0) (list -85.0 240.0) "A" 10.0)
    (spa:pvtie (list -42.0 169.706) (list -42.0 240.0) "S1" 10.0)
    (spa:pvtie (list -42.0 70.294) (list -42.0 169.706) "V" 10.0)
    (spa:pvtie (list 185.0 -15.0) (list 255.0 55.0) "S2" 10.0)))
  (cons pv pvo))

;; Full guided flow for an octagonal spa.
(defun spa:octflow ( / oldclay pvs pv pvo ans bov aov traw sraw s1raw vraw s2raw
                       ovres s tv s1 v pts cen doff th e p q k rows
                       tact vact s2act alleq tmp
                       mode1 meth g kk b2 a2 s2 s12 ovr org2 pts2 cen2
                       xlo xhi ylo yhi out1 ip1 ip2 hrows done turn rbox)
  (setq oldclay (getvar "CLAYER")
        pvs (spa:octpreview)
        pv (car pvs) pvo (cdr pvs))
  (command "_.ZOOM" "_Window"
           (spa:wp (list -120.0 -70.0)) (spa:wp (list 340.0 340.0)))
  (princ "\nA gray guide spa is shown -- the RED tie is the dimension being asked for.")
  (princ "\nUsually A, B and the cut FACE S2 are all that is measured -- NA the rest.")
  (princ "\nEven S2 may be NA: A and B alone draw a true square octagon.")
  (princ "\n(after the first answer, Back re-asks the previous one)")

  (setq ans (spa:askseqb
              (list (list 'b 'REQ "B - overall size ACROSS" (cdr (assoc "B" pvo)))
                    (list 'a 'SUG "A - overall size UP" (cdr (assoc "A" pvo)) '(b))
                    (list 's2 'NAX "S2 - corner cut FACE (the tape across the cut)"
                          (cdr (assoc "S2" pvo)))
                    (list 'tt 'NAX "T - flat across (top & bottom)" (cdr (assoc "T" pvo)))
                    (list 'ss 'NAX "S - corner cut along the side" (cdr (assoc "S" pvo)))
                    (list 's1 'NAX "S1 - corner cut up the end" (cdr (assoc "S1" pvo)))
                    (list 'vv 'NAX "V - flat up (left & right)" (cdr (assoc "V" pvo))))
              nil)
        bov (spa:sq ans 'b)
        aov (if (spa:sq ans 'a) (spa:sq ans 'a) bov)   ; NA at A -> square
        traw (spa:sq ans 'tt) sraw (spa:sq ans 'ss)
        s1raw (spa:sq ans 's1) vraw (spa:sq ans 'vv)
        s2raw (spa:sq ans 's2)
        ovres (spa:octov aov bov sraw traw s1raw vraw s2raw)
        s (car ovres) tv (cadr ovres) s1 (caddr ovres) v (cadddr ovres))
  (spa:pvkill)

  ;; the sheet letters must close POSITIVE against the overalls; one
  ;; that does not fit is adjusted and the report says so
  (if (<= tv 1.0e-6)
      (progn
        (setq tv (min 6.0 (* 0.25 bov)) s (/ (- bov tv) 2.0))
        (spa:valnote "S + T + S DOES NOT FIT B - ADJUSTED")))
  (if (<= s 1.0e-6)
      (progn
        (setq s (min 6.0 (* 0.125 bov)) tv (- bov s s))
        (spa:valnote "T LONGER THAN B - ADJUSTED")))
  (if (<= v 1.0e-6)
      (progn
        (setq v (min 6.0 (* 0.25 aov)) s1 (/ (- aov v) 2.0))
        (spa:valnote "S1 + V + S1 DOES NOT FIT A - ADJUSTED")))
  (if (<= s1 1.0e-6)
      (progn
        (setq s1 (min 6.0 (* 0.125 aov)) v (- aov s1 s1))
        (spa:valnote "V LONGER THAN A - ADJUSTED")))

  ;; -------------------------------------------------- hinges, asked now
  ;; before anything is drawn, so a spillaway can still turn the spa
  (spa:hingeask)

  ;; -------------------------------------------------- orientation
  ;; the long overall runs west to east; a quarter turn swaps the two
  ;; overalls and, with them, the flats and the cut legs.  A spillaway
  ;; no hinge can dodge one way round overrules that (spa:pickturn).
  (setq turn (spa:pickturn
               (> aov bov)
               (list (list "OCT" (spa:octpts bov aov s s1)) 0.0 bov)
               (list (list "OCT" (spa:octpts aov bov s1 s)) 0.0 aov)))
  (if turn
      (setq tmp bov  bov  aov   aov   tmp
            tmp s    s    s1    s1    tmp
            tmp tv   tv   v     v     tmp
            tmp traw traw vraw  vraw  tmp
            tmp sraw sraw s1raw s1raw tmp
            spa:*turned* t))
  (if (and spa:*turned* (not spa:*spillturn*))
      (princ "\nThe long overall runs across, so the spa is drawn a quarter turn over."))

  (setq pts (spa:octpts bov aov s s1)
        cen (spa:centroid pts)
        doff (max 6.0 (/ (max bov aov) 12.0))
        th (max 1.0 (/ (max bov aov) 40.0))
        spa:*dashlt* (spa:ltload "DASHED")
        mode1 spa:*mode*)

  ;; ------------------------------------------- draw the first outline
  ;; one closed polyline, not eight loose lines
  (spa:perpoly (mapcar '(lambda (p) (cons p 0.0)) pts))

  ;; ------------------------------------------- and, if wanted, the other
  ;; An octagon offset by g keeps its shape: the overalls each grow by
  ;; 2g and the cut legs by g*(s + s1 - face)/the other leg.
  ;; one re-enterable unit: a Back inside either branch re-opens the offer
  (setq meth (spa:askother) done nil)
  (while (and meth (not done))
    (if (= meth "Offset")
        (progn
          (setq g (spa:askgap))
          (if (eq g 'SPA-BACK)
              (setq meth (spa:askother))
              (setq kk  (- (+ s s1) (distance (nth 1 pts) (nth 2 pts)))
                    b2  (+ bov (* 2.0 g))
                    a2  (+ aov (* 2.0 g))
                    s2  (+ s  (/ (* g kk) s1))
                    s12 (+ s1 (/ (* g kk) s))
                    done t)))
        (progn
          (princ (strcat "\nThe two outlines share a centre; give the "
                         (spa:modeword (spa:othermode)) " as measured."))
          (setq ans (spa:askseqb
                      (list (list 'b2 'REQ "Overall ACROSS" nil)
                            (list 'a2 'SUG "Overall UP" nil '(b2))
                            (list 'f2 'NAX "Corner cut FACE" nil))
                      t))
          (if (eq ans 'SPA-BACK)
              (setq meth (spa:askother))
              (setq b2 (spa:sq ans 'b2)
                    a2 (if (spa:sq ans 'a2) (spa:sq ans 'a2) b2)
                    ovr (spa:octov a2 b2 nil nil nil nil (spa:sq ans 'f2))
                    s2 (car ovr) s12 (caddr ovr)
                    done t)))))
  (if (and meth done)
      (if (or (<= b2 0.0) (<= a2 0.0) (<= s2 0.0) (<= s12 0.0)
              (<= (- b2 (* 2.0 s2)) 0.0) (<= (- a2 (* 2.0 s12)) 0.0))
          (progn
            (spa:valnote "THE SECOND OUTLINE WILL NOT CLOSE - SKIPPED")
            (setq meth nil))
          (setq org2 (spa:orgfor cen b2 a2)
                pts2 (mapcar '(lambda (p) (spa:v+ p org2))
                             (spa:octpts b2 a2 s2 s12))
                cen2 cen)))

  ;; the cover is the larger, so its extents are the ones to stand off
  (setq xlo (if meth (min 0.0 (car org2)) 0.0)
        xhi (if meth (max bov (+ (car org2) b2)) bov)
        ylo (if meth (min 0.0 (cadr org2)) 0.0)
        yhi (if meth (max aov (+ (cadr org2) a2)) aov))

  ;; ------------------------------------------- draw the second outline
  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (spa:perpoly (mapcar '(lambda (p) (cons p 0.0)) pts2))
        (spa:setmode mode1)))

  ;; -------------------------------------------------- dimensions
  ;; The order sheet's octagon panel carries three things: the overall
  ;; across, the overall up, and ONE corner-cut callout, because all
  ;; eight sides are equal.  When the cut letters make the sides UNequal
  ;; the two flats are dimensioned as well, inboard of the overalls.
  (setq tact (distance (nth 0 pts) (nth 1 pts))
        vact (distance (nth 2 pts) (nth 3 pts))
        s2act (distance (nth 1 pts) (nth 2 pts))
        ;; "all sides equal" to within 1/8" -- a rounded-off cut face
        ;; like 39-3/8" must still read as the regular octagon it is
        alleq (and (< (abs (- tact vact)) 0.125)
                   (< (abs (- tact s2act)) 0.125))
        out1 (or (null meth) (= mode1 "Coversize"))
        ip1 (spa:insidepts 0.0 bov 0.0 aov s s1))
  (setvar "CLAYER" "DIMENSION")
  (spa:dimstylenow th)
  ;; the two overalls, hooked to real corners
  (if out1
      (spa:dimoveralls t (nth 7 pts) (nth 2 pts) (nth 0 pts) (nth 5 pts)
                       xlo yhi)
      (spa:dimoveralls nil (nth 0 ip1) (nth 1 ip1) (nth 2 ip1) (nth 3 ip1)
                       xlo yhi))
  ;; the flats, only when the eight sides are NOT simply all equal --
  ;; a true square octagon needs the overalls and the cut, nothing else
  (if (not alleq)
      (progn
        (spa:dimalg (nth 0 pts) (nth 1 pts)
                    (list (* 0.5 bov) (- 0.0 spa:*flatoff*)) nil)
        (spa:dimalg (nth 2 pts) (nth 3 pts)
                    (list (+ bov spa:*flatoff*) (* 0.5 aov)) nil)))
  ;; the corner cut itself -- one callout on the bottom-right cut, Typ.
  ;; because all four cuts of an octagon are the same
  (setq p (nth 1 pts) q (nth 2 pts))
  (spa:dimalg p q (spa:outoffp p q pts (* 0.8 doff)) " Typ.")

  ;; the second outline, in ITS dimension style, plus its cut face
  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (spa:dimstylenow th)
        (setq ip2 (spa:insidepts (car org2) (+ (car org2) b2)
                                 (cadr org2) (+ (cadr org2) a2) s2 s12))
        (if out1
            (spa:dimoveralls nil (nth 0 ip2) (nth 1 ip2) (nth 2 ip2) (nth 3 ip2)
                             xlo yhi)
            (spa:dimoveralls t (nth 7 pts2) (nth 2 pts2) (nth 0 pts2) (nth 5 pts2)
                             xlo yhi))
        (setq p (nth 5 pts2) q (nth 6 pts2))
        (spa:dimalg p q (spa:outoffp p q pts2 (* 0.8 doff)) " Typ.")
        (spa:setmode mode1)
        ;; and how far the cover laps the water's edge, at the bottom
        (spa:dimstyle spa:*ds-cover* th 1.0)
        (spa:dimlap (* 0.5 (+ xlo xhi)) ylo (max 0.0 (cadr org2)))))
  (setvar "CLAYER" oldclay)

  ;; -------------------------------------------------- report
  ;; the corner letters go on the mini-model beside the report, below,
  ;; not on the drawing itself
  (spa:modenote xlo (- ylo (* 1.4 spa:*dimoff*)) th)
  (setq rows (list (list "OVERALL ACROSS" bov bov)
                   (list "OVERALL UP" aov aov)
                   (list "T - FLAT ACROSS" traw tact)
                   (list "V - FLAT UP" vraw vact)
                   (list "S - CUT ALONG SIDE" sraw s)
                   (list "S1 - CUT UP END" s1raw s1)
                   (list "S2 - CUT FACE" s2raw s2act)))
  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (setq rows (append rows
                           (spa:otherrows b2 a2)
                           (list (list (strcat (strcase (spa:modeword spa:*mode*))
                                               " CUT FACE")
                                       nil (distance (nth 1 pts2) (nth 2 pts2))))))
        (spa:setmode mode1)))
  ;; -------------------------------------------------- hinges
  (setq hrows
    (cond ((= mode1 "Coversize")
           (spa:hingeflow (list "OCT" pts) 0.0 bov th t))
          (meth
           (spa:hingeflow (list "OCT" pts2) (car org2) (+ (car org2) b2) th t))
          (t
           (spa:hingeflow (list "OCT" pts) 0.0 bov th nil))))
  (if hrows (setq rows (append rows hrows)))
  (setq rbox (spa:report rows spa:*valnotes* (+ xhi spa:*dimoff*) yhi th
                         "SPA-NOTES"))
  ;; perimeter mini-model with the corner letters, right of the report
  (spa:minimap (spa:polyprims pts) pts (spa:mlbls pts spa:*octnames*)
               (+ (car rbox) (* 3.0 th)) (cadr rbox) (* 24.0 th) th)
  (princ "\nSpa layout complete -- see the report table.")
  (princ))

;;; -------------------- round ------------------------------------------
;;;
;;;  A round spa is a circle when the two overalls agree and an ellipse
;;;  when they do not -- B across, A up, both measured through the
;;;  middle.  There are no corners, so the perimeter is drawn exactly to
;;;  the overalls.

(defun spa:roundpreview ( / cen pv)
  (setq cen (list 120.0 120.0))
  (spa:body-round cen 240.0 240.0 "SPA-NOTES" nil)
  (spa:pvadd (spa:setcol (entlast) spa:*pv-col*))
  (setq pv (list
    (spa:pvtie (list 0.0 285.0) (list 240.0 285.0) "B" 10.0)
    (spa:pvtie (list -50.0 0.0) (list -50.0 240.0) "A" 10.0)))
  pv)

(defun spa:roundflow ( / oldclay pv ans bov aov cen doff th rows tmp
                         mode1 meth g b2 a2 cen2 xlo xhi ylo yhi
                         out1 bl br ab at hrows done turn rbox)
  (setq oldclay (getvar "CLAYER")
        pv (spa:roundpreview))
  (command "_.ZOOM" "_Window"
           (spa:wp (list -130.0 -70.0)) (spa:wp (list 340.0 330.0)))
  ;; A round spa takes ONE measurement -- the diameter, through the
  ;; middle.  A spa that measured out of round is the exception, not the
  ;; rule, so it costs a keyword rather than a second prompt every time:
  ;; type O and the two axes are asked for instead.
  (princ "\nRound spa -- the diameter, measured through the middle.")
  (princ "\n(measured out of round?  type O for the two axes instead)")
  (setq bov (spa:askd "Overall diameter" "Outofround" nil nil))
  (if (= (type bov) 'STR)
      (progn
        (setq ans (spa:askseqb
                    (list (list 'b 'REQ "B - overall size ACROSS"
                                (cdr (assoc "B" pv)))
                          (list 'a 'SUG "A - overall size UP"
                                (cdr (assoc "A" pv)) '(b)))
                    nil)
              bov (spa:sq ans 'b)
              aov (if (spa:sq ans 'a) (spa:sq ans 'a) bov)))
      (setq aov bov))
  (spa:pvkill)

  ;; hinges are asked before anything is drawn, so a spillaway can still
  ;; turn the spa (a round one turns too: the spillway travels with it)
  (spa:hingeask)

  ;; an out-of-round spa lies with its long overall west to east, unless
  ;; a spillaway no hinge can dodge asks for the other way round
  (setq turn (spa:pickturn
               (> aov bov)
               (list (list "ROUND" (list (* 0.5 bov) (* 0.5 aov)) bov aov)
                     0.0 bov)
               (list (list "ROUND" (list (* 0.5 aov) (* 0.5 bov)) aov bov)
                     0.0 aov)))
  (if turn
      (setq tmp bov bov aov aov tmp
            spa:*turned* t))
  (if (and spa:*turned* (not spa:*spillturn*))
      (princ "\nThe long overall runs across, so the spa is drawn a quarter turn over."))

  (setq cen (list (* 0.5 bov) (* 0.5 aov))
        doff (max 6.0 (/ (max bov aov) 12.0))
        th (max 1.0 (/ (max bov aov) 40.0))
        spa:*dashlt* (spa:ltload "DASHED")
        mode1 spa:*mode*)
  (spa:perround cen bov aov)
  (if (> (abs (- aov bov)) 1.0e-6)
      (princ "\nThe two overalls differ, so the spa is drawn as an ellipse.")
      (princ "\nA and B agree, so the spa is drawn as a true circle."))

  ;; ------------------------------------------- and, if wanted, the other
  ;; one re-enterable unit: a Back inside either branch re-opens the offer
  (setq meth (spa:askother) done nil)
  (while (and meth (not done))
    (if (= meth "Offset")
        (progn
          (setq g (spa:askgap))
          (if (eq g 'SPA-BACK)
              (setq meth (spa:askother))
              (setq b2 (+ bov (* 2.0 g))
                    a2 (+ aov (* 2.0 g))
                    done t)))
        (progn
          (princ (strcat "\nThe two outlines share a centre; give the "
                         (spa:modeword (spa:othermode)) " as measured."))
          (setq ans (spa:askseqb
                      (list (list 'b2 'REQ "Overall ACROSS" nil)
                            (list 'a2 'SUG "Overall UP" nil '(b2)))
                      t))
          (if (eq ans 'SPA-BACK)
              (setq meth (spa:askother))
              (setq b2 (spa:sq ans 'b2)
                    a2 (if (spa:sq ans 'a2) (spa:sq ans 'a2) b2)
                    done t)))))
  (if (and meth done)
      (if (or (<= b2 0.0) (<= a2 0.0))
          (progn
            (spa:valnote "THE SECOND OUTLINE CAME OUT AT OR BELOW ZERO - SKIPPED")
            (setq meth nil))
          (setq cen2 cen)))

  (setq xlo (if meth (min 0.0 (- (car cen) (* 0.5 b2))) 0.0)
        xhi (if meth (max bov (+ (car cen) (* 0.5 b2))) bov)
        ylo (if meth (min 0.0 (- (cadr cen) (* 0.5 a2))) 0.0)
        yhi (if meth (max aov (+ (cadr cen) (* 0.5 a2))) aov))

  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (spa:perround cen2 b2 a2)
        (spa:setmode mode1)))

  ;; A true circle takes the single overall the order sheet's round panel
  ;; shows; only an out-of-round spa needs the second one.  A round spa's
  ;; overalls have to run through the centre, so the water's edge pair
  ;; sits on the centre lines rather than a third of the way in.
  (setq out1 (or (null meth) (= mode1 "Coversize")))
  (setvar "CLAYER" "DIMENSION")
  (spa:dimstylenow th)
  (if out1
      (progn
        (spa:dimov (list 0.0 (* 0.5 aov)) (list bov (* 0.5 aov))
                   (list (* 0.5 bov) (+ yhi spa:*topoff*)))
        (if (> (abs (- aov bov)) 1.0e-6)
            (spa:dimov (list (* 0.5 bov) 0.0) (list (* 0.5 bov) aov)
                       (list (- xlo spa:*dimoff*) (* 0.5 aov)))))
      (progn
        (spa:dimov (list 0.0 (* 0.5 aov)) (list bov (* 0.5 aov))
                   (list (* 0.5 bov) (* 0.5 aov)))
        (if (> (abs (- aov bov)) 1.0e-6)
            (spa:dimov (list (* 0.5 bov) 0.0) (list (* 0.5 bov) aov)
                       (list (* 0.5 bov) (* 0.5 aov))))))
  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (spa:dimstylenow th)
        (setq bl (- (car cen) (* 0.5 b2)) br (+ (car cen) (* 0.5 b2))
              ab (- (cadr cen) (* 0.5 a2)) at (+ (cadr cen) (* 0.5 a2)))
        (if out1
            (progn
              (spa:dimov (list bl (cadr cen)) (list br (cadr cen))
                         (list (car cen) (cadr cen)))
              (if (> (abs (- a2 b2)) 1.0e-6)
                  (spa:dimov (list (car cen) ab) (list (car cen) at)
                             (list (car cen) (cadr cen)))))
            (progn
              (spa:dimov (list bl (cadr cen)) (list br (cadr cen))
                         (list (car cen) (+ yhi spa:*topoff*)))
              (if (> (abs (- a2 b2)) 1.0e-6)
                  (spa:dimov (list (car cen) ab) (list (car cen) at)
                             (list (- xlo spa:*dimoff*) (cadr cen))))))
        (spa:setmode mode1)
        ;; and how far the cover laps the water's edge, at the bottom
        (spa:dimstyle spa:*ds-cover* th 1.0)
        (spa:dimlap (car cen) ylo (max 0.0 ab))))
  (setvar "CLAYER" oldclay)

  (spa:modenote xlo (- ylo (* 1.4 spa:*dimoff*)) th)
  (setq rows (list (list "OVERALL ACROSS" bov bov)
                   (list "OVERALL UP" aov aov)))
  (if meth
      (progn
        (spa:setmode (spa:othermode))
        (setq rows (append rows (spa:otherrows b2 a2)))
        (spa:setmode mode1)))
  ;; -------------------------------------------------- hinges
  (setq hrows
    (cond ((= mode1 "Coversize")
           (spa:hingeflow (list "ROUND" cen bov aov) 0.0 bov th t))
          (meth
           (spa:hingeflow (list "ROUND" cen b2 a2)
                          (- (car cen) (* 0.5 b2)) (+ (car cen) (* 0.5 b2)) th t))
          (t
           (spa:hingeflow (list "ROUND" cen bov aov) 0.0 bov th nil))))
  (if hrows (setq rows (append rows hrows)))
  (setq rbox (spa:report rows spa:*valnotes* (+ xhi spa:*dimoff*) yhi th
                         "SPA-NOTES"))
  ;; the mini-model beside the report -- a round spa has no corners, so
  ;; it carries no letters; it is there to say which way round it lies
  (spa:minimap (list (list 'rb cen bov aov)) nil nil
               (+ (car rbox) (* 3.0 th)) (cadr rbox) (* 24.0 th) th)
  (princ "\nSpa layout complete -- see the report table.")
  (princ))

;;; -------------------- undo grouping ----------------------------------

;; Copes with drawings where undo is limited or off, and with an error
;; firing before the group was ever opened.
(defun spa:undobegin ()
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
      (progn
        (command "_.UNDO" "_Begin")
        (setq spa:*undogrp* t))))

(defun spa:undoend ()
  (if spa:*undogrp* (command "_.UNDO" "_End"))
  (setq spa:*undogrp* nil))

;;; -------------------- sysvar save / restore --------------------------
;;; The snapshot of the user's settings lives in a GLOBAL and is taken
;;; only when no snapshot is already pending: if a previous run died
;;; before restoring, the stale snapshot still holds the user's TRUE
;;; settings.  Saving again at that point would capture the zeroed
;;; OSMODE and every later run would faithfully "restore" 0 -- the
;;; user's object snaps would look permanently wiped by the command.

(defun spa:sysvars ()
  (append '("OSMODE" "LUNITS" "CMDECHO" "CLAYER") spa:*dimvars*))

(defun spa:syssave ( / v)
  (if (not spa:*sysold*)
      (progn
        (foreach v (spa:sysvars)
          (if (/= nil (getvar v))
              (setq spa:*sysold* (append spa:*sysold* (list (cons v (getvar v)))))))
        (setq spa:*odstyle* (getvar "DIMSTYLE")))))

(defun spa:sysrestore ( / v p)
  ;; OSMODE first -- object snaps are the setting the user misses most
  ;; if a cleanup is ever cut short partway
  (foreach v (spa:sysvars)
    (setq p (assoc v spa:*sysold*))
    (if p (setvar v (cdr p))))
  ;; the current dimension style is read-only, so it takes a command
  (if (and spa:*odstyle* (tblsearch "DIMSTYLE" spa:*odstyle*))
      (command "_.-DIMSTYLE" "_Restore" spa:*odstyle*))
  (setq spa:*sysold* nil
        spa:*odstyle* nil))

;;; -------------------- main command -----------------------------------

(defun c:SPA ( / *error* stype base)

  (defun *error* (msg)
    (if (and msg
             (/= (strcase msg t) "function cancelled")
             (/= (strcase msg t) "quit / exit abort"))
        (princ (strcat "\nSPA error: " msg)))
    ;; user settings come back FIRST so nothing below can skip them
    (spa:sysrestore)
    (spa:pvkill)
    (spa:undoend)
    (if *pop-error-mode* (*pop-error-mode*))
    (princ))

  ;; AutoCAD 2012+ requires this so *error* may call (command);
  ;; harmless no-op guard on older releases where it doesn't exist
  (if *push-error-using-command* (*push-error-using-command*))

  (spa:syssave)
  (setq spa:*valnotes* nil
        spa:*turned* nil
        spa:*spillturn* nil
        spa:*hingeon* nil
        spa:*spills* nil
        spa:*hingerows* nil
        spa:*advice* nil
        spa:*grade* nil
        spa:*taper* nil)
  (setvar "CMDECHO" 0)
  (spa:undobegin)
  ;; architectural units while prompting so every distance can be typed
  ;; as 6'10", 6'-10-1/2" or 6'10.5 as well as plain inches
  (setvar "LUNITS" 4)
  (princ "\nDistances may be typed as 6'10\", 6'-10-1/2\" or 82.5 (plain numbers = inches).")
  (princ "\nDimensions are written in standard inches and placed outside the shape.")

  ;; ------------------------------------------------ grade + taper first
  ;; The Spa Cover Details block is read UP FRONT because its grade can
  ;; settle the next question outright: a Thermo-Light cover's water's
  ;; edge and cover size are the same thing, so there is nothing to ask
  ;; and nothing to add later.  Skipping here just defers the block to
  ;; the hinge pass.
  (princ "\nThe Spa Cover Details block sets the grade and taper.")
  (spa:readblock)
  (if (spa:thermop)
      (progn
        (spa:setmode "Coversize")
        (setq spa:*taper* "1-3/8")
        (princ "\nThermo-Light: the water's edge and the cover size are the same.")
        (spa:advise "THERMO-LIGHT: WATER'S EDGE = COVER SIZE, ONE OUTLINE"))
      (spa:setmode
        (spa:askkw "Is this drawing at the water's edge or the cover size"
                   "Watersedge Coversize" "Watersedge/Coversize" nil nil)))
  (princ (strcat "\n" spa:*modename* ": outline on layer " spa:*perlay*
                 (if spa:*perdash* " (dashed)" "")
                 "; overalls read <measurement> over \"" spa:*sfx* "\"."))

  ;; ------------------------------------------------ shape
  (initget 1 "Rectangle OCtagon ROund")
  (setq stype (getkword "\nSpa shape [Rectangle/OCtagon/ROund]: "))

  ;; the base point is picked with the user's own snaps still live;
  ;; only afterwards do snaps drop for the command-fed drawing work
  (setq base (getpoint "\nInsertion base point <0,0>: ")
        spa:*base* (if base (list (car base) (cadr base)) (list 0.0 0.0)))
  (setvar "OSMODE" 0)

  ;; ------------------------------------------------ layers
  (spa:layer spa:*lay-water* 4)
  (spa:layer spa:*lay-cover* 6)
  (spa:layer "DIMENSION" 2)
  (spa:layer "SPA-NOTES" 3)
  (spa:layer "TEXT" 7)

  ;; dashed / dotted patterns up front so the guide draws them; the
  ;; patterns are defined in inches and scaled to cancel LTSCALE, so they
  ;; show the same in any drawing
  (setq spa:*dashlt* (spa:ltload "DASHED")
        spa:*dotlt*  (spa:ltload "DOT"))

  (cond
    ((= stype "OCtagon") (spa:octflow))
    ((= stype "ROund")   (spa:roundflow))
    (t                   (spa:rectflow)))

  ;; ------------------------------------------------ finish
  (command "_.ZOOM" "_Extents")
  (spa:undoend)
  (spa:sysrestore)
  (if *pop-error-mode* (*pop-error-mode*))
  (princ))


(defun c:SPAVER ()
  (princ (strcat "\nSPA " spa:*version*))
  (princ (strcat "\nTutorial: "
                 (if tut:*version* tut:*version* "not loaded")))
  (princ))

(princ (strcat "\nSPA " spa:*version*
               " loaded.  SPA to draw, SPAVER for the version"
               (if tut:*version* ", TUTORIALSPA to learn it" "")
               "."))
(princ)
