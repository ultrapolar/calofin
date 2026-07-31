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
;;;  on every shape.  What else appears depends on the corners:
;;;
;;;    All four corners identical -- the two overalls plus ONE corner
;;;    callout with a Typ. suffix, at the bottom-right.  That is the
;;;    whole drawing for an all-radius or all-diagonal cover, and for a
;;;    true square octagon.  A plain 90-corner rectangle gets no corner
;;;    callout at all: the two overalls are the drawing.
;;;
;;;    Corners NOT identical -- each cut corner is called out on its own
;;;    (no Typ.), the square ones among them share one 90-degree mark,
;;;    and every side a cut has SHORTENED also gets its remaining FLAT
;;;    dimensioned, inboard of the overalls.  So a cover with one cut
;;;    top-right reads: overall across, overall up, the top flat, the
;;;    right flat, the cut face, and 90 Typ. on the square corners.
;;;
;;;  The round spa takes one overall; only an out-of-round one gets the
;;;  second.  An octagon whose eight sides come out unequal picks up the
;;;  bottom and right flats the same way the rectangle does.
;;;
;;;  RECTANGLE CORNERS
;;;  -----------------
;;;  A corner is Radius (sized by its radius), Diagonal (a cut, sized by
;;;  its face length) or 90 -- the sheet's own corner legend.  Side
;;;  lengths are always to the TRUE (sharp) corner; the treatment cuts
;;;  inward from there.  Corner A is asked first and its answer
;;;  AUTOFILLS corners B, C and D -- press Enter at each to accept it, or
;;;  type a different treatment for that corner, so a cover with two cut
;;;  corners and two square ones takes four different answers.
;;;
;;;  Callouts sit outside the corner on its 45-degree line: a radius dim
;;;  on a Radius corner (R12"), an aligned dim across a Diagonal cut
;;;  face (21"), and a circled corner point with a 90%%d leader on a 90
;;;  corner.
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
;;;  as well as plain inches.  "Back" at any prompt after the first
;;;  re-asks the previous question.
;;;
;;;  Written in plain AutoLISP (entmake + classic commands, no
;;;  ActiveX/VLA), so it loads in AutoCAD 2018 as well as older releases.
;;; ====================================================================

;;; -------------------- adjustable constants --------------------------

;; Dimension text units.  5 = Fractional inches (84-1/2), 2 = Decimal
;; inches (84.50).  Anything but 4 (Architectural) keeps the numbers in
;; standard inches instead of rolling them up into feet.
(setq spa:*dimlunit* 5)
(setq spa:*dimprec*  3)         ; 5 -> 1/8", 2 -> 3 decimal places
(setq spa:*dimpost*  "\"")      ; suffix stuck on every measurement

(setq spa:*sfx-water* "Water's Edge")
(setq spa:*sfx-cover* "Cover Size")
(setq spa:*lay-water* "POOL")   ; water's edge perimeter layer (dashed)
(setq spa:*lay-cover* "COVER")  ; cover size perimeter layer

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

;;; -------------------- the perimeter itself ---------------------------
;;;  Water's edge -> dashed, on the POOL layer.
;;;  Cover size   -> solid, on the COVER layer.

(defun spa:perdxf ()
  (if (and spa:*perdash* (/= spa:*dashlt* "CONTINUOUS"))
      (list (cons 6 spa:*dashlt*) (cons 48 (spa:ltsc)))))

(defun spa:perline (p1 p2) (spa:line p1 p2 spa:*perlay* (spa:perdxf)))

(defun spa:perarc3p (p1 p2 p3) (spa:arc3p p1 p2 p3 spa:*perlay* (spa:perdxf)))

(defun spa:perround (cen b a) (spa:body-round cen b a spa:*perlay* (spa:perdxf)))

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
      '("DIMLUNIT" "DIMFRAC" "DIMDEC" "DIMZIN" "DIMPOST" "DIMTAD" "DIMTXT" "DIMASZ"
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

;; Aligned dimension between two points, dragged to pt.  note is appended
;; to the measurement inside a text override ("\\XCover Size" to stack it,
;; " Typ." to run it on); pass nil for a plain dimension.
(defun spa:dimalg (p1 p2 pt note)
  (if (and note (/= note ""))
      (command "_.DIMALIGNED" (spa:wp p1) (spa:wp p2)
               "_T" (strcat "<>" note) (spa:wp pt))
      (command "_.DIMALIGNED" (spa:wp p1) (spa:wp p2) (spa:wp pt))))

;; Radius dimension read from OUTSIDE the arc: the arc is picked at its
;; far point and the dimension line dragged further out along the same
;; direction, so the leader comes in from outside.
(defun spa:dimrad (ent tip outd doff sfx)
  (if (and ent (entget ent) (= "ARC" (cdr (assoc 0 (entget ent)))))
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
(defun spa:asks (kind msg ents dflt back / v cols kw)
  (setq cols (mapcar 'spa:getcol ents))
  (foreach e ents (spa:setcol e spa:*hi-col*))
  (spa:osup)
  (setq kw (cond ((eq kind 'REQ) (if back "Back" nil))
                 (back "NA Back")
                 (t "NA")))
  (if kw
      (initget (if (and (eq kind 'SUG) dflt) 6 7) kw)
      (initget 7))
  (setq v (getdist
            (strcat "\n" msg
                    (cond ((eq kind 'REQ) "")
                          ((eq kind 'SUG)
                           (if dflt (strcat " <" (rtos dflt) "> (or NA)")
                               " (or NA)"))
                          (t " (or NA if not measured)"))
                    (if back " [Back]" "")
                    ": ")))
  (spa:osdown)
  (mapcar '(lambda (e c) (spa:setcol e c)) ents cols)
  (cond ((and (= (type v) 'STR) (= v "Back")) 'SPA-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;; Keyword question that can also be backed out of.  kws is the initget
;; string, shown the bracketed list, dflt the Enter answer (nil = an
;; answer is required).  Returns the keyword or SPA-BACK.
(defun spa:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((= v "Back") 'SPA-BACK)
        ((null v) (if dflt dflt (spa:askkw msg kws shown dflt back)))
        (t v)))

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
(defun spa:pvkill ()
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

;; rows  = list of (label target actual [red]); a nil target prints N/A
;; notes = list of failure strings (written big and red)
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
    (if tgt
        (progn
          (setq dl (- act tgt)
                ds (strcat (if (< dl 0.0) "" "+") (rtos dl 2 2)))
          (spa:rtext (list (+ x (* 20.0 h)) y) h (rtos tgt 2 2) lay (nth 3 r))
          (spa:rtext (list (+ x (* 38.0 h)) y) h ds lay (nth 3 r)))
        (progn
          (spa:rtext (list (+ x (* 20.0 h)) y) h "N/A" lay (nth 3 r))
          (spa:rtext (list (+ x (* 38.0 h)) y) h "-" lay (nth 3 r))))
    (spa:rtext (list (+ x (* 29.0 h)) y) h (rtos act 2 2) lay (nth 3 r)))
  (foreach n notes
    (setq y (- y (* 1.5 lh)))
    (spa:textc (list x y) (* 1.4 h) n lay 1))
  (setq y0 (- y lh)
        ytop (+ ytop (* 0.6 lh)))
  (spa:line (list (- x h) y0) (list xr y0) lay nil)
  (spa:line (list xr y0) (list xr ytop) lay nil)
  (spa:line (list xr ytop) (list (- x h) ytop) lay nil)
  (spa:line (list (- x h) ytop) (list (- x h) y0) lay nil)
  (princ))

;; The Water's Edge / Cover Size note under the drawing.
(defun spa:modenote (x y th)
  (spa:textc (list x y) (* 1.6 th)
             (strcat "SPA OUTLINE DRAWN AT " spa:*modename*) "SPA-NOTES" 7))

;;; -------------------- rectangle corner treatments --------------------
;;;
;;;  A corner may be Square, Rounded (radius) or Diag (chamfer).  Side
;;;  lengths are measured to the TRUE (sharp) corner; the treatment cuts
;;;  inward from there.  The size typed is:
;;;    Rounded -> the corner RADIUS
;;;    Diag    -> the CHAMFER FACE length (the cut itself)

;; The two points where a corner's treatment meets the straight sides
;; (toward the previous / next corner) plus, for Radius, the arc mid.
;; Returns (ePrev eNext arcMid|nil).  A 90 corner -> (P P nil).
(defun spa:cornerends (p pp pn ctype size / uprev unext dp ang sb bis cen)
  (setq uprev (spa:unit (spa:v- pp p))
        unext (spa:unit (spa:v- pn p))
        dp (spa:dot uprev unext)
        ang (atan (sqrt (max 0.0 (- 1.0 (* dp dp)))) dp))   ; interior angle
  (cond
    ((= ctype "Diagonal")
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

;; Draw the rectangle perimeter with its corner treatments.  Returns the
;; list of fillet-arc entity names per corner (nil where the corner is 90
;; or diagonal) for the corner callouts.
(defun spa:drawrect (q corners / ce i tyi arcs)
  (setq ce (spa:allends q corners))
  (foreach i (list 0 1 2 3)             ; straight sides (eNext(i) -> ePrev(i+1))
    (spa:perline (cadr (nth i ce)) (car (nth (rem (+ i 1) 4) ce))))
  (setq arcs nil)
  (foreach i (list 0 1 2 3)             ; corner treatments
    (setq tyi (car (nth i corners)))
    (cond
      ((= tyi "Diagonal")
       (spa:perline (car (nth i ce)) (cadr (nth i ce)))
       (setq arcs (cons nil arcs)))
      ((= tyi "Radius")
       (spa:perarc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce)))
       (setq arcs (cons (entlast) arcs)))
      (t (setq arcs (cons nil arcs)))))
  (reverse arcs))

;; Do all four corners carry the same treatment?  Four identical corners
;; get ONE callout with a Typ. suffix, the way the order sheet shows it.
(defun spa:samecorners (corners / c0 same)
  (setq c0 (car corners) same t)
  (foreach c corners
    (if (or (/= (car c) (car c0))
            (> (abs (- (cadr c) (cadr c0))) 0.0005))
        (setq same nil)))
  same)

;; The order sheet's 90-degree corner mark: a small circle on the corner
;; point with a leader out of it.  Assumes CLAYER is already DIMENSION.
(defun spa:dim90 (quad i cen doff sfx / p outd r)
  (setq p (nth i quad)
        outd (spa:unit (spa:v- p cen))
        r (* 0.18 doff))
  (entmake (list '(0 . "CIRCLE")
                 (cons 8 "DIMENSION")
                 (cons 10 (spa:wp p))
                 (cons 40 r)))
  (command "_.LEADER" (spa:wp (spa:v+ p (spa:v* outd r)))
           (spa:wp (spa:v+ p (spa:v* outd (* 1.2 doff))))
           "" (strcat "90%%d" sfx) ""))

;; Corner callouts, laid out the way the order sheet does them: the note
;; sits OUTSIDE the corner, on the 45-degree line out of it.
;;   Radius    -> a radius dimension read from outside the arc  (R12")
;;   Diagonal  -> an aligned dimension across the cut face      (21")
;;   90        -> a circled corner point with a 90%%d leader
;;
;; Four identical corners are called out ONCE, at the bottom-right, with
;; a Typ. suffix -- that is the whole annotation an all-radius or
;; all-diagonal cover needs.  Mixed corners are called out one by one,
;; and the square ones among them share a single 90-degree mark (Typ.
;; when there is more than one).  A plain rectangle -- four 90 corners,
;; nothing cut -- gets no corner notes at all.
;;
;; None of these ever carry the Water's Edge / Cover Size note: they are
;; corners, not overalls.  Assumes CLAYER is already DIMENSION.
(defun spa:dimcorners (quad corners arcs cen doff / allsame sfx ilist nsq sqi
                                                   i cc ce p pp pn ty outd am fm)
  (setq allsame (spa:samecorners corners)
        sfx (if allsame " Typ." "")
        ilist (if allsame (list 1) (list 0 1 2 3)))   ; 1 = bottom-right
  (foreach i ilist
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
      ((= ty "Diagonal")
       (setq fm (spa:mid (car ce) (cadr ce)))
       (spa:dimalg (car ce) (cadr ce)
                   (spa:v+ fm (spa:v* outd (* 0.6 doff))) sfx))))
  ;; the square corners of a MIXED set share one mark, scanned from the
  ;; bottom-right the way the sheet places it
  (if (not allsame)
      (progn
        (setq nsq 0 sqi nil)
        (foreach i (list 1 0 2 3)
          (if (= (car (nth i corners)) "90")
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
      ((= (car cc) "Diagonal")
       (spa:pvadd (spa:pvline (car (nth i ce)) (cadr (nth i ce)))))
      ((= (car cc) "Radius")
       (spa:arc3p (car (nth i ce)) (caddr (nth i ce)) (cadr (nth i ce))
                  "SPA-NOTES" nil)
       (spa:pvadd (spa:setcol (entlast) spa:*pv-col*))))
    (setq i (1+ i)))
  pv)

;; What the corner's size prompt is called.
(defun spa:cornersizemsg (ty)
  (if (= ty "Radius") " corner radius" " diagonal cut face length"))

;; Prompt one corner's treatment, named the way the order sheet's corner
;; legend names them: Radius / Diagonal / 90.  ("Square" is accepted as
;; a synonym for 90 and normalised away.)  dflty/dfltsz are the autofill
;; answer (corner A's) -- Enter accepts them.  maxsb caps the
;; treatment's setback along the walls at half the shorter adjacent
;; wall, so two treatments can never overlap and fold the perimeter;
;; too-large answers are re-asked.  Returns (type size) or SPA-BACK.
(defun spa:askcorner (label dflty dfltsz ents maxsb back / ty sz cols sb)
  (setq cols (mapcar 'spa:getcol ents))
  (foreach e ents (spa:setcol e spa:*hi-col*))
  (spa:osup)
  (setq ty (spa:askkw label "Radius Diagonal 90 Square" "Radius/Diagonal/90"
                      dflty back))
  (spa:osdown)
  (if (eq ty 'SPA-BACK) (setq ty nil))
  (if (equal ty "Square") (setq ty "90"))   ; sheet legend calls it 90
  (if (null ty)
      (progn (mapcar '(lambda (e c) (spa:setcol e c)) ents cols)
             'SPA-BACK)
      (progn
        (if (= ty "90")
            (setq sz 0.0)
            (progn
              (spa:osup)
              ;; the autofill size only stands in when it came from the
              ;; SAME treatment -- a radius is not a cut face
              (if (or (null dfltsz) (<= dfltsz 0.0) (/= ty dflty))
                  (setq dfltsz nil))
              (initget (if dfltsz 6 7))
              (setq sz (getdist (strcat "\n" label (spa:cornersizemsg ty)
                                        (if dfltsz (strcat " <" (rtos dfltsz) ">") "")
                                        ": ")))
              (if (null sz) (setq sz dfltsz))
              ;; Radius sets back r along each wall; a Diagonal face f
              ;; sets back f/sqrt(2) on a 90-degree corner
              (while (and maxsb
                          (> (setq sb (if (= ty "Radius") sz (* sz 0.70711)))
                             maxsb))
                (princ (strcat "\nToo large for this corner's walls -- max "
                               (rtos (if (= ty "Radius") maxsb (/ maxsb 0.70711)))
                               ".  Re-enter."))
                (initget 7)
                (setq sz (getdist (strcat "\n" label (spa:cornersizemsg ty)
                                          ": "))))
              (spa:osdown)))
        (mapcar '(lambda (e c) (spa:setcol e c)) ents cols)
        (list ty sz))))

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
                        a b c d cen doff th allsame oo fo i j lbls cc back
                        rows lbl)
  (setq oldclay (getvar "CLAYER")
        pv (spa:rectpreview))
  (command "_.ZOOM" "_Window"
           (spa:wp (list -110.0 -90.0)) (spa:wp (list 350.0 320.0)))
  (princ "\nA gray guide spa is shown -- the RED element is the dimension being asked for.")
  (princ "\nCorners: A bottom-left, B bottom-right, C top-right, D top-left.")
  (princ "\n(Back re-asks the previous question)")

  ;; -------- the two overalls (a moulded shell is a true rectangle)
  (defun rc:sides ( / ans)
    (setq ans (spa:askseqb
                (list (list 'w 'REQ "Overall WIDTH across (A-B)"
                            (append (cdr (assoc 'ab pv)) (cdr (assoc 'cd pv))
                                    (spa:lbl pv '(lA lB))))
                      (list 'l 'REQ "Overall LENGTH up (A-D)"
                            (append (cdr (assoc 'da pv)) (cdr (assoc 'bc pv))
                                    (spa:lbl pv '(lA lD)))))
                nil))
    (setq w (spa:sq ans 'w) l (spa:sq ans 'l))
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
          (foreach cc corners (if (/= (car cc) "90") (setq anycut t)))
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

  ;; -------------------------------------------------- draw
  (setq quad (list (list 0.0 0.0) (list w 0.0) (list w l) (list 0.0 l))
        a (car quad) b (cadr quad) c (caddr quad) d (cadddr quad)
        cen (list (* 0.5 w) (* 0.5 l))
        doff (max 6.0 (/ (max w l) 12.0))
        th (max 1.0 (/ (max w l) 40.0))
        spa:*dashlt* (spa:ltload "DASHED"))
  (setq arcs (spa:drawrect quad corners))

  ;; -------------------------------------------------- dimensions
  ;; Laid out the way the order sheet does it: the overall across on the
  ;; TOP and the overall up on the LEFT, both reading <size> over the
  ;; Cover Size / Water's Edge note.  When all four corners match, that
  ;; plus one Typ. corner callout is the whole drawing.  When they do
  ;; NOT match, each side a cut has shortened also gets its remaining
  ;; FLAT dimensioned, inboard of the overalls.
  (setq allsame (spa:samecorners corners)
        oo (if allsame doff (* 1.7 doff))     ; overalls clear the flats
        fo (* 0.6 doff))
  (setvar "CLAYER" "DIMENSION")
  (spa:dimsetup th)
  ;; the overalls, true corner to true corner -- the only dims that
  ;; carry the Water's Edge / Cover Size note
  (spa:dimalg d c (spa:outoff d c cen oo) (spa:ovnote))
  (spa:dimalg a d (spa:outoff a d cen oo) (spa:ovnote))
  ;; the flats
  (if (not allsame)
      (foreach i (list 0 1 2 3)
        (setq j (rem (+ i 1) 4))
        (if (or (/= (car (nth i corners)) "90")
                (/= (car (nth j corners)) "90"))
            (spa:dimalg (spa:cornerpoint quad corners i 'next)
                        (spa:cornerpoint quad corners j 'prev)
                        (spa:outoff (nth i quad) (nth j quad) cen fo) nil))))
  ;; corner callouts (no note -- these are corners, not overalls)
  (spa:dimcorners quad corners arcs cen doff)
  (setvar "CLAYER" oldclay)

  ;; -------------------------------------------------- labels + report
  (foreach lbl (list (list a "A") (list b "B") (list c "C") (list d "D"))
    (spa:text (spa:v+ (car lbl)
                      (spa:v* (spa:unit (spa:v- (car lbl) cen)) (* 1.6 th)))
              th (cadr lbl) "SPA-NOTES"))
  (spa:modenote 0.0 (- 0.0 (* 3.0 doff)) th)
  (setq rows (list (list "OVERALL WIDTH (A-B)" w w)
                   (list "OVERALL LENGTH (A-D)" l l)))
  (setq i 0)
  (foreach cc corners
    (setq rows (append rows
                       (list (list (strcat "CORNER " (nth i lbls) " "
                                           (strcase (car cc)))
                                   (if (= (car cc) "90") nil (cadr cc))
                                   (cadr cc))))
          i (1+ i)))
  (spa:report rows spa:*valnotes* (+ w (* 2.0 doff)) l th "SPA-NOTES")
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
                       xmax ymax ymin tact vact s2act alleq)
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

  ;; -------------------------------------------------- draw
  (setq pts (spa:octpts bov aov s s1)
        cen (spa:centroid pts)
        doff (max 6.0 (/ (max bov aov) 12.0))
        th (max 1.0 (/ (max bov aov) 40.0))
        spa:*dashlt* (spa:ltload "DASHED")
        xmax bov ymax aov ymin 0.0)
  (foreach e spa:*octedges*
    (spa:perline (nth (car e) pts) (nth (cadr e) pts)))

  ;; -------------------------------------------------- dimensions
  ;; The order sheet's octagon panel carries three things: the overall
  ;; across, the overall up, and ONE corner-cut callout, because all
  ;; eight sides are equal.  When the cut letters make the sides UNequal
  ;; the two flats are dimensioned as well, inboard of the overalls --
  ;; the same layout as the cut-corner rectangle panel.
  (setq tact (distance (nth 0 pts) (nth 1 pts))
        vact (distance (nth 2 pts) (nth 3 pts))
        s2act (distance (nth 1 pts) (nth 2 pts))
        ;; "all sides equal" to within 1/8" -- a rounded-off cut face
        ;; like 39-3/8" must still read as the regular octagon it is
        alleq (and (< (abs (- tact vact)) 0.125)
                   (< (abs (- tact s2act)) 0.125)))
  (setvar "CLAYER" "DIMENSION")
  (spa:dimsetup th)
  ;; the two overalls, hooked to real corners, dragged clear of the shape
  (spa:dimalg (nth 7 pts) (nth 2 pts)
              (list (* 0.5 bov) (+ ymax (* 1.6 doff))) (spa:ovnote))
  (spa:dimalg (nth 0 pts) (nth 5 pts)
              (list (- 0.0 (* 1.6 doff)) (* 0.5 aov)) (spa:ovnote))
  ;; the flats, only when the eight sides are NOT simply all equal --
  ;; a true square octagon needs the overalls and the cut, nothing else
  (if (not alleq)
      (progn
        (spa:dimalg (nth 0 pts) (nth 1 pts)
                    (list (* 0.5 bov) (- ymin (* 0.6 doff))) nil)
        (spa:dimalg (nth 2 pts) (nth 3 pts)
                    (list (+ xmax (* 0.6 doff)) (* 0.5 aov)) nil)))
  ;; the corner cut itself -- one callout on the bottom-right cut, Typ.
  ;; because all four cuts of an octagon are the same
  (setq p (nth 1 pts) q (nth 2 pts))
  (spa:dimalg p q (spa:outoffp p q pts (* 0.8 doff)) " Typ.")
  (setvar "CLAYER" oldclay)

  ;; -------------------------------------------------- labels + report
  (setq k 0)
  (foreach p pts
    (spa:text (spa:lbloff p cen pts (* 1.8 th)) th (nth k spa:*octnames*) "SPA-NOTES")
    (setq k (1+ k)))
  (spa:modenote 0.0 (- ymin (* 2.4 doff)) th)
  (setq rows (list (list "OV B (ACROSS)" bov bov)
                   (list "OV A (UP)" aov aov)
                   (list "T - FLAT ACROSS" traw tact)
                   (list "V - FLAT UP" vraw vact)
                   (list "S - CUT ALONG SIDE" sraw s)
                   (list "S1 - CUT UP END" s1raw s1)
                   (list "S2 - CUT FACE" s2raw s2act)))
  (spa:report rows spa:*valnotes* (+ xmax (* 2.0 doff)) ymax th "SPA-NOTES")
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

(defun spa:roundflow ( / oldclay pv ans bov aov cen doff th rows)
  (setq oldclay (getvar "CLAYER")
        pv (spa:roundpreview))
  (command "_.ZOOM" "_Window"
           (spa:wp (list -130.0 -70.0)) (spa:wp (list 340.0 330.0)))
  (princ "\nRound spa -- B across and A up, both through the middle.")
  (princ "\n(Enter at A takes B, i.e. a true circle)")

  (setq ans (spa:askseqb
              (list (list 'b 'REQ "B - overall size ACROSS" (cdr (assoc "B" pv)))
                    (list 'a 'SUG "A - overall size UP" (cdr (assoc "A" pv)) '(b)))
              nil)
        bov (spa:sq ans 'b)
        aov (if (spa:sq ans 'a) (spa:sq ans 'a) bov))  ; NA at A -> circle
  (spa:pvkill)

  (setq cen (list (* 0.5 bov) (* 0.5 aov))
        doff (max 6.0 (/ (max bov aov) 12.0))
        th (max 1.0 (/ (max bov aov) 40.0))
        spa:*dashlt* (spa:ltload "DASHED"))
  (spa:perround cen bov aov)
  (if (> (abs (- aov bov)) 1.0e-6)
      (princ "\nThe two overalls differ, so the spa is drawn as an ellipse.")
      (princ "\nA and B agree, so the spa is drawn as a true circle."))

  ;; A true circle takes the single overall the order sheet's round panel
  ;; shows; only an out-of-round spa needs the second one.
  (setvar "CLAYER" "DIMENSION")
  (spa:dimsetup th)
  (spa:dimalg (list 0.0 (* 0.5 aov)) (list bov (* 0.5 aov))
              (list (* 0.5 bov) (+ aov (* 1.6 doff))) (spa:ovnote))
  (if (> (abs (- aov bov)) 1.0e-6)
      (spa:dimalg (list (* 0.5 bov) 0.0) (list (* 0.5 bov) aov)
                  (list (- 0.0 (* 1.6 doff)) (* 0.5 aov)) (spa:ovnote)))
  (setvar "CLAYER" oldclay)

  (spa:modenote 0.0 (- 0.0 (* 3.0 doff)) th)
  (setq rows (list (list "OV B (ACROSS)" bov bov)
                   (list "OV A (UP)" aov aov)))
  (spa:report rows spa:*valnotes* (+ bov (* 2.0 doff)) aov th "SPA-NOTES")
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
      (foreach v (spa:sysvars)
        (if (/= nil (getvar v))
            (setq spa:*sysold* (append spa:*sysold* (list (cons v (getvar v)))))))))

(defun spa:sysrestore ( / v p)
  ;; OSMODE first -- object snaps are the setting the user misses most
  ;; if a cleanup is ever cut short partway
  (foreach v (spa:sysvars)
    (setq p (assoc v spa:*sysold*))
    (if p (setvar v (cdr p))))
  (setq spa:*sysold* nil))

;;; -------------------- main command -----------------------------------

(defun c:SPA ( / *error* stype base mode)

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
  (setq spa:*valnotes* nil)
  (setvar "CMDECHO" 0)
  (spa:undobegin)
  ;; architectural units while prompting so every distance can be typed
  ;; as 6'10", 6'-10-1/2" or 6'10.5 as well as plain inches
  (setvar "LUNITS" 4)
  (princ "\nDistances may be typed as 6'10\", 6'-10-1/2\" or 82.5 (plain numbers = inches).")
  (princ "\nDimensions are written in standard inches and placed outside the shape.")

  ;; ------------------------------------------------ what is being drawn
  (setq mode (spa:askkw "Is this drawing at the water's edge or the cover size"
                        "Watersedge Coversize" "Watersedge/Coversize" nil nil))
  (if (= mode "Watersedge")
      (setq spa:*perlay*   spa:*lay-water*
            spa:*perdash*  t
            spa:*sfx*      spa:*sfx-water*
            spa:*modename* "WATER'S EDGE")
      (setq spa:*perlay*   spa:*lay-cover*
            spa:*perdash*  nil
            spa:*sfx*      spa:*sfx-cover*
            spa:*modename* "COVER SIZE"))
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


(princ "\nSPA.LSP loaded.  Type SPA to lay out a spa.")
(princ)
