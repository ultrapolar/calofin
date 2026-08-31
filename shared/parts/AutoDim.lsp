;;; ======================================================================
;;;  AutoDim.lsp
;;;
;;;  AUTODIM  - Step 1. Asks the user to highlight the stuff to
;;;                auto-dim (the plan geometry).  Everything else in
;;;                the drawing is ignored from then on.  Highlight a
;;;                flight of steps drawn in side view instead and it
;;;                is recognised as one - see "Steps in side view"
;;;                below - and steps 2 to 5 are skipped, being all
;;;                about a plan.
;;;             Step 2. Dimensions the perimeter of the highlighted
;;;                geometry, at least a foot outside the plan: its
;;;                straight sides (LINE entities and straight
;;;                LWPOLYLINE segments) with aligned dimensions, then
;;;                its arcs (ARC and CIRCLE entities and bulged
;;;                LWPOLYLINE segments) with radius dimensions.  A
;;;                measurement that repeats is called out once and
;;;                noted "Typ." - see "One dim per size" below.
;;;             Step 3. Asks the user to highlight the stairs.  The
;;;                treads (the largest group of parallel lines in the
;;;                selection) get their widths dimensioned and the
;;;                distances between them chained beside the stair.
;;;             Step 4. Asks whether you would like floor dims, and if
;;;                you do, has you draw two lines across the plan.
;;;                Each one becomes a continued dimension chain
;;;                (DIMALIGNED + DIMCONTINUE) that breaks at every
;;;                highlighted object standing in its way.  A start or
;;;                end point that is not on an object is pulled back to
;;;                the last object before it, so every dim runs object
;;;                to object and none hangs off the end into open
;;;                drawing.
;;;             Step 5. Places the two overall dims, no input needed:
;;;                the plan's full width about 2ft above the topmost
;;;                dimension and its full height about 2ft to the left
;;;                of the left-most one.
;;;
;;;  STAIRDIM - Runs just the stairs part again for another selection.
;;;  FLOORDIM - Runs just the floor dims part for one extra line
;;;             (breaks at everything in model space).
;;;
;;;  AUTODIMSIDEPOV - Dimensions steps drawn in side view (elevation).
;;;             Highlight the step profile: every vertical riser gets a
;;;             vertical dimension placed beside its step - extension
;;;             lines hooked to the nosing corners, each dim stepping
;;;             down the flight with the stairs - plus one overall
;;;             height dimension further out.  The dims are created on
;;;             layer "DIMENSION" in the "STANDARD INCHES" style, like
;;;             the reference drawing, and work whichever way the
;;;             stairs face.
;;;
;;;  Usage:
;;;    1. APPLOAD this file (or drag it into the drawing window).
;;;    2. Type AUTODIM and follow the prompts.
;;;
;;;  Steps in side view:
;;;    AUTODIM works out for itself whether step 1's selection is a
;;;    plan or a flight of steps drawn in side view, and it only takes
;;;    the second route when the drawing really looks like steps:
;;;      * nothing curved in the selection - no arc, circle, ellipse,
;;;        spline, polyline bulge or block;
;;;      * three quarters or more of the straight segments running
;;;        square, so a sloping pool floor at the foot of the flight is
;;;        still allowed;
;;;      * two or more risers, and at least one tread per gap between
;;;        them;
;;;      * the risers forming a connected staircase across the drawing,
;;;        each starting where the one before it finished, a tread's
;;;        run further along.
;;;    A vertical as tall as the whole profile is read as the back wall
;;;    rather than a step and left out of that - which is also what
;;;    stops a rectangular plan reading as a two-step flight.  Anything
;;;    that fails the test is dimensioned as a plan, so a false alarm
;;;    is not something a plan can trip into.
;;;    What it then places: the depth of every step as a vertical dim,
;;;    all on one line clear of the right-hand side of the flight, and
;;;    the overall depth further right again.  Both in "STANDARD
;;;    INCHES".  AUTODIMSIDEPOV is still there for a flight the test
;;;    does not recognise, or to put the dims on the high side of the
;;;    steps instead of the right.
;;;
;;;  How the perimeter is found:
;;;    From the midpoint of every straight segment a test ray is cast
;;;    perpendicular to each side, out past the extents of the
;;;    highlighted geometry.  If at least one side is completely clear
;;;    of highlighted geometry the segment is on the perimeter, and its
;;;    dimension is placed on that clear side.  Because only the
;;;    highlighted stuff blocks the rays, title borders, notes and
;;;    anything else in the drawing cannot get in the way.
;;;
;;;  Dimension styles - every dimension picks its own, by what it
;;;  measures rather than by which step placed it (a style the drawing
;;;  does not have falls back to the style that was current when the
;;;  command started, and that style is restored when it finishes):
;;;    * Perimeter and stairs    -> "SIDE STANDARD"
;;;    * The floor dims chains   -> "STANDARD"
;;;    * The two overall dims    -> "STANDARD"
;;;    * ...measuring under 12"  -> "STANDARD INCHES", whichever of the
;;;                                 three it would otherwise have been
;;;    * Steps in side view      -> "STANDARD INCHES", depths and the
;;;                                 overall alike, in AUTODIM and in
;;;                                 AUTODIMSIDEPOV
;;;
;;;  One dim per size - the "Typ." rule:
;;;    A measurement that repeats around the perimeter is called out
;;;    once, with " Typ." after it, and the others are left to that
;;;    note rather than dimensioned again.  The one that carries it is
;;;    the first of its size the tool comes across, so a re-run marks
;;;    the same side or arc it marked before.
;;;      * straight sides -> from two equal ones up
;;;      * arcs, by radius -> from four equal ones up; a pair or a trio
;;;        of matching curves reads better dimensioned where each one
;;;        is, so those are left alone
;;;    Two lengths, or two radii, within a sixteenth of an inch count
;;;    as the same measurement.  The counts and the wording are
;;;    ad:*typ-lines*, ad:*typ-curves* and ad:*typ-note* at the top of
;;;    the file.
;;;
;;;  One dimension per place:
;;;    Before placing anything the tool reads every linear, aligned and
;;;    radius dimension already in model space.  A dim is skipped when
;;;    one is already there for that place - same two extension line
;;;    origins (either way round) and a dimension line within a foot of
;;;    where the new one would sit, or for a radius dim, the same
;;;    centre and the same radius.  So a second run over a plan that has
;;;    grown dimensions the new geometry only, while the overall dims,
;;;    two feet further out, are still placed even when a side of the
;;;    plan happens to measure the same thing.
;;;
;;;  Notes:
;;;    * All dims go on the current layer.
;;;    * Ellipses and splines have no one radius to call out, so the
;;;      perimeter step passes over them.
;;;    * Perimeter dims are placed at least one foot away from the
;;;      perimeter, heading outwards (or 2 x DIMTXT x DIMSCALE when
;;;      that is larger).
;;;    * Equal step widths are dimensioned once instead of once per
;;;      tread; a width dim is repeated only when the width changes.
;;;    * A dim chain breaks where a span is already dimensioned, and
;;;      where the style has to change, so a short span still lands in
;;;      inches without dragging the rest of the chain with it.
;;;    * The two floor dims lines are construction lines only - they
;;;      are erased once their dimension chain has been created.
;;;    * Answering No to the floor dims question skips straight to the
;;;      overall dims; Back at it re-opens the stairs.
;;;    * Break points closer together than 0.0001 drawing units are
;;;      merged so no zero-length dimensions are created.
;;; ======================================================================

;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;

(setq *autodim-version* "v1.4")   ; announced on load; release_lisp.py
                                     ; stamps the dated twin in releases/

(vl-load-com)

;; ---------------------------------------------------------------- helpers

;; angle of a segment folded into [0, pi) so opposite directions match
(defun ad:segang (seg / a)
  (setq a (angle (car seg) (cadr seg)))
  (if (>= a pi) (- a pi) a))

;; difference between two folded angles, allowing for wrap-around
(defun ad:angdiff (a b / d)
  (setq d (abs (- a b)))
  (min d (abs (- pi d))))

;; perpendicular offset used for the automatic dims
(defun ad:dimoff ()
  (* 2.0
     (getvar "DIMTXT")
     (if (zerop (getvar "DIMSCALE")) 1.0 (getvar "DIMSCALE"))))

;; one foot expressed in the current drawing units (INSUNITS),
;; assuming inches when unitless or unknown
(defun ad:onefoot (/ u)
  (setq u (getvar "INSUNITS"))
  (cond ((= u 2) 1.0)                   ; feet
        ((= u 4) 304.8)                 ; millimetres
        ((= u 5) 30.48)                 ; centimetres
        ((= u 6) 0.3048)                ; metres
        ((= u 10) (/ 1.0 3.0))          ; yards
        (t 12.0)))                      ; inches / unitless

;; ------------------------------------------------------------- asking

;; restore a dimension style by name if the drawing has it,
;; return T when the style was set
(defun ad:setdimstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; create the dim layer, or - when it already exists - un-freeze,
;; unlock and switch it back on, telling the user when it had to: a
;; run onto a frozen layer would otherwise look like it did nothing
(defun ad:ensure-layer (name color / rec ed flags col fixed)
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

;; make that layer current, creating or repairing it on the way
(defun ad:setlayer (name)
  (setvar "CLAYER" (ad:ensure-layer name 7)))

;; ------------------------------------------------ dimension styles

;; The styles the tool asks for.  The perimeter and the stairs go in
;; ad:*style-plan*, the floor dims chains in ad:*style-floor* and the
;; two overall dims in ad:*style-over*; whichever of those it is,
;; anything measuring less than a foot goes in ad:*style-short*
;; instead, a sub-foot dim reading better in inches.
(setq ad:*style-plan*  "SIDE STANDARD"
      ad:*style-floor* "STANDARD"
      ad:*style-short* "STANDARD INCHES"
      ad:*style-over*  "STANDARD")

;; Repeated measurements are called out once and noted, rather than
;; dimensioned over and over.  ad:*typ-note* is the suffix the one dim
;; that stands for its group carries - the wording POOL.LSP already
;; uses for the same job.  The two counts are how many equal ones it
;; takes before that happens: two equal straight sides are enough,
;; while equal radii are left alone until there are more than three of
;; them, a pair or a trio of matching curves reading better dimensioned
;; where they are.
(setq ad:*typ-note*   " Typ."
      ad:*typ-lines*  2
      ad:*typ-curves* 4)

;; per-run state, all reset by ad:begin
(setq ad:*dims*      nil    ; the places that already carry a dimension
      ad:*rads*      nil    ; the arcs that already carry a radius dim
      ad:*skipped*   0      ; how many dims this run left to what was there
      ad:*curstyle*  nil    ; the dimension style in force right now
      ad:*homestyle* nil)   ; what to fall back on when a style is missing

;; T when two style names are the same one (AutoCAD folds their case)
(defun ad:samestyle (a b)
  (and a b (= (strcase a) (strcase b))))

;; make a dimension style current, skipping the work when it already
;; is.  A style the drawing does not have falls back to the one that
;; was current when the command started, so a missing "SIDE STANDARD"
;; cannot leave a later dim stranded in the style of the dim before it.
(defun ad:usestyle (name / want)
  (setq want (if (and name (tblsearch "DIMSTYLE" name)) name ad:*homestyle*))
  (if (and want (not (ad:samestyle want ad:*curstyle*)))
    (progn
      (ad:setdimstyle want)
      (setq ad:*curstyle* want))))

;; the style a dimension of this measured length belongs in
(defun ad:styfor (len base)
  (if (< len (ad:onefoot)) ad:*style-short* base))

;; ---------------------------------------- dimensions already in place

;; how close two extension line origins have to be before they count as
;; the same place - a sixteenth of an inch, in the drawing's own units
(defun ad:dupetol () (/ (ad:onefoot) 192.0))

;; how close two dimension lines have to be before dims across the same
;; two points count as the same dim.  A foot: enough that a re-run, or
;; a dim nudged by hand, is recognised, and small enough that the
;; overall dims - two feet further out - are still their own dims.
(defun ad:bandtol () (ad:onefoot))

;; every dimension in model space
(defun ad:dimss ()
  (ssget "_X" '((0 . "DIMENSION") (410 . "Model"))))

;; a linear / aligned dimension as (origin1 origin2 dimline-point) -
;; nil for any other kind (radial, angular, ordinate), which has no
;; pair of extension line origins to compare
(defun ad:dimpts (en / el)
  (setq el (entget en))
  (if (and el
           (= "DIMENSION" (cdr (assoc 0 el)))
           (assoc 13 el)
           (assoc 14 el)
           (assoc 10 el))
    (list (cdr (assoc 13 el)) (cdr (assoc 14 el)) (cdr (assoc 10 el)))))

;; note that p1-p2 now carries a dimension whose dim line runs through
;; loc, so nothing later in the same run doubles up on it
(defun ad:remember (p1 p2 loc)
  (setq ad:*dims* (cons (list p1 p2 loc) ad:*dims*)))

;; a radius dimension as (centre radius), nil for anything else.  Only
;; radius dims are read: a diameter dim writes two points on the circle
;; into 10 and 15 rather than the centre and one, and is not what this
;; tool places anyway.
(defun ad:raddimpts (en / el c)
  (setq el (entget en))
  (if (and el
           (= "DIMENSION" (cdr (assoc 0 el)))
           (assoc 70 el)
           (= 4 (logand 7 (cdr (assoc 70 el))))
           (assoc 10 el)
           (assoc 15 el))
    (progn
      (setq c (cdr (assoc 10 el)))
      (list c (distance c (cdr (assoc 15 el)))))))

;; note that the arc at centre with this radius now carries one
(defun ad:remrad (centre rad)
  (setq ad:*rads* (cons (list centre rad) ad:*rads*)))

;; T when that arc is dimensioned already - same centre, same radius
(defun ad:raddimmed-p (centre rad / tol lst q hit)
  (setq tol (ad:dupetol)
        lst ad:*rads*)
  (while (and lst (not hit))
    (setq q   (car lst)
          lst (cdr lst))
    (if (and (ad:samept (car q) centre tol)
             (<= (abs (- (cadr q) rad)) tol))
      (setq hit t)))
  hit)

;; read what the drawing already carries into ad:*dims* and ad:*rads*
(defun ad:dimscan (/ ss i en q)
  (setq ad:*dims* nil
        ad:*rads* nil
        ss        (ad:dimss)
        i         0)
  (if ss
    (repeat (sslength ss)
      (setq en (ssname ss i)
            i  (1+ i))
      (if (setq q (ad:dimpts en))
        (setq ad:*dims* (cons q ad:*dims*)))
      (if (setq q (ad:raddimpts en))
        (setq ad:*rads* (cons q ad:*rads*)))))
  ad:*dims*)

;; start a run: remember the style to fall back on and what is current,
;; zero the skip count and read the drawing's dimensions
(defun ad:begin ()
  (setq ad:*homestyle* (getvar "DIMSTYLE")
        ad:*curstyle*  (getvar "DIMSTYLE")
        ad:*skipped*   0)
  (ad:dimscan))

;; T when a and b are the same point on the plan, within tol
(defun ad:samept (a b tol)
  (and (<= (abs (- (car a) (car b))) tol)
       (<= (abs (- (cadr a) (cadr b))) tol)))

;; how far off the p1-p2 span the dimension line through loc sits,
;; signed, so two dims across the same points but on opposite sides do
;; not read as one.  Straight vector maths, not (angle ...), so a
;; rotated UCS cannot turn the answer round.
(defun ad:lineoff (p1 p2 loc / dx dy len)
  (setq dx  (- (car p2) (car p1))
        dy  (- (cadr p2) (cadr p1))
        len (sqrt (+ (* dx dx) (* dy dy))))
  (if (> len 1e-12)
    (/ (- (* dx (- (cadr loc) (cadr p1)))
          (* dy (- (car loc) (car p1))))
       len)
    0.0))

;; T when p1-p2 is already dimensioned with the dim line about where
;; loc would put it: same two origins either way round, dim line within
;; ad:bandtol.  This is the "do not add another one there" test.
(defun ad:dimmed-p (p1 p2 loc / tol band off lst q hit)
  (setq tol  (ad:dupetol)
        band (ad:bandtol)
        off  (ad:lineoff p1 p2 loc)
        lst  ad:*dims*)
  (while (and lst (not hit))
    (setq q   (car lst)
          lst (cdr lst))
    (if (and (or (and (ad:samept (car q) p1 tol)
                      (ad:samept (cadr q) p2 tol))
                 (and (ad:samept (car q) p2 tol)
                      (ad:samept (cadr q) p1 tol)))
             (<= (abs (- off (ad:lineoff p1 p2 (caddr q)))) band))
      (setq hit t)))
  hit)

;; Split records whose car is the measurement into groups of equal
;; measurement, within tol.  Order is kept both ways: a group sits
;; where its first member was found, and its members keep the order
;; they were found in - so "the one that gets the note" is the first
;; one the tool came across, every run.
(defun ad:groupsame (recs tol / out r g hit new)
  (setq out '())
  (foreach r recs
    (setq hit nil
          new '())
    (foreach g out
      (if (and (not hit) (<= (abs (- (car r) (car (car g)))) tol))
        (setq g   (append g (list r))
              hit t))
      (setq new (cons g new)))
    (if (not hit) (setq new (cons (list r) new)))
    (setq out (reverse new)))
  out)

;; count one dim left to the one already there
(defun ad:skip ()
  (setq ad:*skipped* (1+ ad:*skipped*))
  0)

;; tell the user what the run left to the dims that were already there
(defun ad:skipreport ()
  (if (> ad:*skipped* 0)
    (prompt (strcat "\n" (itoa ad:*skipped*)
                    " dimension(s) skipped - that place is dimensioned"
                    " already."))))

;; -------------------------------------------------- placing dimensions

;; place one aligned dimension - all points expected in WCS.  note is
;; appended to the measurement, "" leaving it as measured.
(defun ad:aligned (p1 p2 loc note)
  (if (= note "")
    (command "_.DIMALIGNED"
             "_non" (trans p1 0 1)
             "_non" (trans p2 0 1)
             "_non" (trans loc 0 1))
    (command "_.DIMALIGNED"
             "_non" (trans p1 0 1)
             "_non" (trans p2 0 1)
             "_T" (strcat "<>" note)
             "_non" (trans loc 0 1))))

;; place one linear dimension - dir is "_H" or "_V", points in WCS
(defun ad:lindim (p1 p2 loc dir)
  (command "_.DIMLINEAR"
           "_non" (trans p1 0 1)
           "_non" (trans p2 0 1)
           dir
           "_non" (trans loc 0 1)))

;; place one aligned dimension across p1-p2, in the style its length
;; calls for, unless that place is dimensioned already.  note is what
;; follows the measurement - "" for the measurement alone.
;; Returns 1 when a dimension was placed, 0 when it was not.
(defun ad:putaligned (p1 p2 loc base note / len)
  (setq len (distance p1 p2))
  (cond
    ((<= len 1e-8) 0)
    ((ad:dimmed-p p1 p2 loc) (ad:skip))
    (t (ad:usestyle (ad:styfor len base))
       (ad:aligned p1 p2 loc note)
       (ad:remember p1 p2 loc)
       1)))

;; the same for a horizontal ("_H") or vertical ("_V") linear dim - the
;; length that picks the style is the one the dim reads out, not the
;; distance between the two points
(defun ad:putlinear (p1 p2 loc dir base / len)
  (setq len (if (= dir "_V")
              (abs (- (cadr p1) (cadr p2)))
              (abs (- (car p1) (car p2)))))
  (cond
    ((<= len 1e-8) 0)
    ((ad:dimmed-p p1 p2 loc) (ad:skip))
    (t (ad:usestyle (ad:styfor len base))
       (ad:lindim p1 p2 loc dir)
       (ad:remember p1 p2 loc)
       1)))

;; place one radius dimension on the arc en, its leader reaching from
;; the point on it out to loc, unless that arc is dimensioned already.
;; note follows the measurement, "" leaving it as measured.
;; Returns 1 when a dimension was placed, 0 when it was not.
(defun ad:putradius (rad en on centre loc base note)
  (cond
    ((<= rad 1e-8) 0)
    ((ad:raddimmed-p centre rad) (ad:skip))
    (t (ad:usestyle (ad:styfor rad base))
       (if (= note "")
         (command "_.DIMRADIUS"
                  (list en (trans on 0 1))
                  "_non" (trans loc 0 1))
         (command "_.DIMRADIUS"
                  (list en (trans on 0 1))
                  "_T" (strcat "<>" note)
                  "_non" (trans loc 0 1)))
       (ad:remrad centre rad)
       1)))

;; one contiguous run of a chain, all of it in style sty: a first
;; aligned dim, then DIMCONTINUE through the rest.
;; Returns the number of dimensions placed.
(defun ad:putrun (pts loc sty / p prev)
  (ad:usestyle sty)
  (ad:aligned (car pts) (cadr pts) loc "")
  (ad:remember (car pts) (cadr pts) loc)
  (if (cddr pts)
    (progn
      (command "_.DIMCONTINUE")
      (setq prev (cadr pts))
      (foreach p (cddr pts)
        (command "_non" (trans p 0 1))
        (ad:remember prev p loc)
        (setq prev p))
      (command "" "")))
  (1- (length pts)))

;; place a continued dimension chain through the given WCS points.  A
;; span that is dimensioned already is left alone, and the chain breaks
;; there and wherever the style has to change - so a span under a foot
;; still lands in inches without dragging the rest of the chain with
;; it, and the pieces stay on the one dimension line through loc.
;; Returns the number of dimensions placed.
(defun ad:dimchain (pts loc base / cnt run sty a b d s dup)
  (setq cnt 0
        run nil
        sty nil)
  (while (cdr pts)
    (setq a   (car pts)
          b   (cadr pts)
          pts (cdr pts)
          d   (distance a b)
          dup (and (> d 1e-8) (ad:dimmed-p a b loc))
          s   (if (or (<= d 1e-8) dup) nil (ad:styfor d base)))
    (if dup (ad:skip))
    (if (and s run (ad:samestyle s sty))
      (setq run (cons b run))
      (progn
        (if (cdr run) (setq cnt (+ cnt (ad:putrun (reverse run) loc sty))))
        (if s
          (setq run (list b a)
                sty s)
          (setq run nil
                sty nil)))))
  (if (cdr run) (setq cnt (+ cnt (ad:putrun (reverse run) loc sty))))
  cnt)

;; every straight segment of a LINE or plan-view LWPOLYLINE as a list
;; of (p1 p2) pairs - other entity types return nil
(defun ad:segs (en / el pts blg segs n g)
  (setq el (entget en))
  (cond
    ((= "LINE" (cdr (assoc 0 el)))
     (list (list (cdr (assoc 10 el)) (cdr (assoc 11 el)))))
    ((and (= "LWPOLYLINE" (cdr (assoc 0 el)))
          (or (null (assoc 210 el))
              (equal (cdr (assoc 210 el)) '(0.0 0.0 1.0) 1e-6)))
     (setq pts '()
           blg '())
     (foreach g el
       (cond ((= 10 (car g)) (setq pts (cons (append (cdr g) '(0.0)) pts)))
             ((= 42 (car g)) (setq blg (cons (cdr g) blg)))))
     (setq pts (reverse pts)
           blg (reverse blg))
     ;; closed polylines also get their last->first segment
     (if (= 1 (logand 1 (cdr (assoc 70 el))))
       (setq pts (append pts (list (car pts)))))
     (setq segs '()
           n    0)
     (while (< (1+ n) (length pts))
       (if (or (null (nth n blg)) (equal 0.0 (nth n blg) 1e-8))
         (setq segs (cons (list (nth n pts) (nth (1+ n) pts)) segs)))
       (setq n (1+ n)))
     (reverse segs))))

;; The arc a bulged polyline segment describes, as (centre radius mid)
;; with mid the point half way round it - nil for a straight one.  The
;; bulge is tan(sweep/4), signed + for counter-clockwise, so the sweep
;; and the radius come straight back out of it and the centre sits on
;; the chord's perpendicular bisector, the signed radius putting it on
;; the correct side.
(defun ad:bulgearc (p1 p2 b / chord sweep rad cen)
  (setq chord (distance p1 p2))
  (if (and (> chord 1e-8) (> (abs b) 1e-8))
    (progn
      (setq sweep (* 4.0 (atan b))
            rad   (/ chord (* 2.0 (sin (/ sweep 2.0))))
            cen   (polar (cal:midn p1 p2)
                         (+ (angle p1 p2) (* 0.5 pi))
                         (* rad (cos (/ sweep 2.0)))))
      (list cen
            (abs rad)
            (polar cen (+ (angle cen p1) (/ sweep 2.0)) (abs rad))))))

;; every curved piece of every entity in ss, as
;; (radius entity point-on-it centre) - one per ARC and CIRCLE and one
;; per bulged segment of an LWPOLYLINE.  Radius first, so the records
;; group by size the same way the straight ones do.  Ellipses and
;; splines have no one radius to call out and are passed over.
(defun ad:arcs (ss / out i en el ty c r a1 a2 pts blg n p1 p2 arc)
  (setq out '()
        i   0)
  (if ss
    (repeat (sslength ss)
      (setq en (ssname ss i)
            i  (1+ i)
            el (entget en)
            ty (cdr (assoc 0 el)))
      (cond
        ((= ty "ARC")
         (setq c  (cdr (assoc 10 el))
               r  (cdr (assoc 40 el))
               a1 (cdr (assoc 50 el))
               a2 (cdr (assoc 51 el)))
         (if (< a2 a1) (setq a2 (+ a2 (* 2.0 pi))))
         (setq out (cons (list r en (polar c (* 0.5 (+ a1 a2)) r) c) out)))
        ((= ty "CIRCLE")
         (setq c (cdr (assoc 10 el))
               r (cdr (assoc 40 el)))
         (setq out (cons (list r en (polar c 0.0 r) c) out)))
        ((and (= ty "LWPOLYLINE")
              (or (null (assoc 210 el))
                  (equal (cdr (assoc 210 el)) '(0.0 0.0 1.0) 1e-6)))
         (setq pts '()
               blg '())
         (foreach c el
           (cond ((= 10 (car c)) (setq pts (cons (append (cdr c) '(0.0)) pts)))
                 ((= 42 (car c)) (setq blg (cons (cdr c) blg)))))
         (setq pts (reverse pts)
               blg (reverse blg))
         (if (= 1 (logand 1 (cdr (assoc 70 el))))
           (setq pts (append pts (list (car pts)))))
         (setq n 0)
         (while (< (1+ n) (length pts))
           (setq p1  (nth n pts)
                 p2  (nth (1+ n) pts)
                 arc (if (nth n blg) (ad:bulgearc p1 p2 (nth n blg))))
           (if arc
             (setq out (cons (list (cadr arc) en (caddr arc) (car arc)) out)))
           (setq n (1+ n)))))))
  (reverse out))

;; if the arc at centre with this radius lies on the perimeter, return
;; the angle from its centre out through mid to the clear side, else
;; nil.  Radially out first, then radially in, the way a straight
;; segment's two sides are tried.
(defun ad:arcang (centre mid diag eps ss / a)
  (setq a (angle centre mid))
  (cond ((ad:sideclear mid a diag eps ss) a)
        ((ad:sideclear mid (+ a pi) diag eps ss) (+ a pi))))

;; every straight segment of every entity in ss, as (p1 p2) pairs
(defun ad:allsegs (ss / i en s out)
  (setq out '()
        i   0)
  (if ss
    (repeat (sslength ss)
      (setq en (ssname ss i)
            i  (1+ i))
      (foreach s (ad:segs en)
        (if (> (distance (car s) (cadr s)) 1e-8)
          (setq out (cons s out))))))
  out)

;; how many curved pieces the selection holds: arc, circle, ellipse and
;; spline entities, the bulged segments of a polyline, and blocks,
;; whose contents cannot be read from the DXF list.  A flight of steps
;; drawn in side view has none of them.
(defun ad:curves (ss / i en el ty g n)
  (setq n 0
        i 0)
  (if ss
    (repeat (sslength ss)
      (setq en (ssname ss i)
            i  (1+ i)
            el (entget en)
            ty (cdr (assoc 0 el)))
      (cond
        ((wcmatch ty "ARC,CIRCLE,ELLIPSE,SPLINE,INSERT,POLYLINE")
         (setq n (1+ n)))
        ((= "LWPOLYLINE" ty)
         (foreach g el
           (if (and (= 42 (car g)) (> (abs (cdr g)) 1e-8))
             (setq n (1+ n))))))))
  n)

;; dxf filter for geometry that can be dimensioned / block a ray /
;; break a dim chain
(defun ad:geomfilter ()
  '((0 . "LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE,INSERT")))

;; everything in model space matching the geometry filter
(defun ad:geomss ()
  (ssget "_X" (append (ad:geomfilter) '((410 . "Model")))))

;; ------------------------------------------ part 1: perimeter dimensions

;; T if nothing in ss lies between pt and pt + dist along direction ang
(defun ad:sideclear (pt ang dist eps ss / lin lobj i rtn clear)
  (entmake (list '(0 . "LINE")
                 (cons 10 (polar pt ang eps))
                 (cons 11 (polar pt ang dist))))
  (setq lin   (entlast)
        lobj  (vlax-ename->vla-object lin)
        clear t
        i     0)
  (if ss
    (while (and clear (< i (sslength ss)))
      (setq rtn (vl-catch-all-apply
                  'vlax-invoke
                  (list lobj 'IntersectWith
                        (vlax-ename->vla-object (ssname ss i)) acextendnone)))
      (if (and (not (vl-catch-all-error-p rtn)) rtn)
        (setq clear nil))
      (setq i (1+ i))))
  (entdel lin)
  clear)

;; if segment p1-p2 lies on the perimeter of the highlighted geometry,
;; return the angle pointing to its clear (outside) side, else nil
(defun ad:perimang (p1 p2 diag eps ss / mid a)
  (setq mid (cal:midn p1 p2)
        a   (angle p1 p2))
  (cond ((ad:sideclear mid (+ a (* 0.5 pi)) diag eps ss) (+ a (* 0.5 pi)))
        ((ad:sideclear mid (- a (* 0.5 pi)) diag eps ss) (- a (* 0.5 pi)))))

;; every straight segment on the perimeter of ss, as
;; (length p1 p2 where-its-dim-goes).  Length first, so the records
;; group by size.
(defun ad:perimsegs (ss diag eps off / out i en seg len pa)
  (setq out '()
        i   0)
  (repeat (sslength ss)
    (setq en (ssname ss i)
          i  (1+ i))
    (foreach seg (ad:segs en)
      (setq len (distance (car seg) (cadr seg)))
      (if (and (> len 1e-8)
               (setq pa (ad:perimang (car seg) (cadr seg) diag eps ss)))
        (setq out (cons (list len (car seg) (cadr seg)
                              (polar (cal:midn (car seg) (cadr seg)) pa off))
                        out)))))
  (reverse out))

;; every arc on the perimeter of ss, as
;; (radius entity point-on-it centre where-its-dim-goes)
(defun ad:perimarcs (ss diag eps off / out rec pa)
  (setq out '())
  (foreach rec (ad:arcs ss)
    (if (setq pa (ad:arcang (cadddr rec) (caddr rec) diag eps ss))
      (setq out (cons (append rec (list (polar (caddr rec) pa off))) out))))
  (reverse out))

;; Dimension the perimeter of the highlighted geometry in ss: its
;; straight sides, then its arcs by radius.  A measurement that repeats
;; is called out once, on the first one found, with ad:*typ-note* after
;; it, and the rest are left to that note - from ad:*typ-lines* equal
;; sides up, and from ad:*typ-curves* equal radii up.  Below those
;; counts every one is dimensioned where it is.
;; Returns how many dimensions were placed.
(defun ad:dimperim (ss / box diag eps off cnt g rec)
  (setq box (cal:bbox-ss ss)
        cnt 0)
  (if box
    (progn
      (setq diag (* 2.0 (distance (car box) (cadr box)))
            eps  (* 1e-6 diag)
            ;; at least a foot away from the perimeter, heading outwards
            off  (max (ad:dimoff) (ad:onefoot)))
      ;; the straight sides
      (foreach g (ad:groupsame (ad:perimsegs ss diag eps off) (ad:dupetol))
        (if (>= (length g) ad:*typ-lines*)
          (setq rec (car g)
                cnt (+ cnt (ad:putaligned (cadr rec) (caddr rec) (cadddr rec)
                                          ad:*style-plan* ad:*typ-note*)))
          (foreach rec g
            (setq cnt (+ cnt (ad:putaligned (cadr rec) (caddr rec) (cadddr rec)
                                            ad:*style-plan* ""))))))
      ;; the arcs, by radius
      (foreach g (ad:groupsame (ad:perimarcs ss diag eps off) (ad:dupetol))
        (if (>= (length g) ad:*typ-curves*)
          (setq rec (car g)
                cnt (+ cnt (ad:putradius (car rec) (cadr rec) (caddr rec)
                                         (cadddr rec) (nth 4 rec)
                                         ad:*style-plan* ad:*typ-note*)))
          (foreach rec g
            (setq cnt (+ cnt (ad:putradius (car rec) (cadr rec) (caddr rec)
                                           (cadddr rec) (nth 4 rec)
                                           ad:*style-plan* ""))))))))
  cnt)

;; --------------------------------------------- part 2: stairs dimensions

;; ask the user to highlight the stairs.  The treads - the largest
;; group of parallel straight lines in the selection - get their widths
;; dimensioned, and the distances between them chained beside the
;; stair.  Both go in the plan style, or in inches when they measure
;; under a foot, which the gap between two treads usually does.
;; Returns the number of dimensions placed.
(defun ad:dimstairs (/ ss segs s a hit g out groups best u v off
                       tds td w lastw mid loc smax ts prev pts cnt)
  (prompt (strcat "\nHighlight the stairs (window or pick the tread"
                  " lines), then press Enter."
                  "\nStep widths and the distances between steps both"
                  " get dimensioned - anything under 12\" in"
                  " \"STANDARD INCHES\"."
                  "  Press Enter without selecting to skip."))
  (setq ss  (ssget '((0 . "LINE,LWPOLYLINE")))
        cnt 0)
  (if ss
    (progn
      (setq segs (ad:allsegs ss))
      ;; group the segments by direction - the biggest group of
      ;; parallel lines is taken as the treads
      (setq groups '())
      (foreach s segs
        (setq a   (ad:segang s)
              hit nil
              out '())
        (foreach g groups
          (if (and (not hit) (< (ad:angdiff a (car g)) 1e-3))
            (setq g   (cons (car g) (cons s (cdr g)))
                  hit t))
          (setq out (cons g out)))
        (if (not hit) (setq out (cons (list a s) out)))
        (setq groups out))
      (setq best nil)
      (foreach g groups
        (if (or (null best) (> (length (cdr g)) (length (cdr best))))
          (setq best g)))
      (if best
        (progn
          (setq a   (car best)
                u   (list (cos a) (sin a) 0.0)          ; along the treads
                v   (list (- (sin a)) (cos a) 0.0)      ; up the stair
                off (ad:dimoff)
                tds '()
                smax nil)
          ;; sort the treads up the stair and find the stair's side edge
          (foreach s (cdr best)
            (setq tds  (cons (cons (cal:dotn (cal:midn (car s) (cadr s)) v) s) tds)
                  smax (apply 'max
                              (append (if smax (list smax))
                                      (list (cal:dotn (car s) u)
                                            (cal:dotn (cadr s) u))))))
          (setq tds (vl-sort tds '(lambda (x y) (< (car x) (car y)))))
          ;; widths of the steps (repeated only when the width changes)
          (setq lastw nil)
          (foreach td tds
            (setq w (distance (cadr td) (caddr td)))
            (if (or (null lastw) (> (abs (- w lastw)) 1e-4))
              (progn
                (setq mid (cal:midn (cadr td) (caddr td))
                      loc (mapcar '(lambda (m vv) (- m (* off vv))) mid v))
                (setq cnt   (+ cnt (ad:putaligned (cadr td) (caddr td) loc
                                                  ad:*style-plan* ""))
                      lastw w))))
          ;; distances between the steps, chained beside the stair
          (setq ts   '()
                prev nil)
          (foreach td tds
            (if (or (null prev) (> (- (car td) prev) 1e-4))
              (setq ts   (cons (car td) ts)
                    prev (car td))))
          (setq ts (reverse ts))
          (if (cdr ts)
            (progn
              (setq pts (mapcar
                          '(lambda (tv)
                             (mapcar '(lambda (uu vv)
                                        (+ (* smax uu) (* tv vv)))
                                     u v))
                          ts)
                    loc (mapcar '(lambda (uu vv)
                                   (+ (* (+ smax off) uu) (* (car ts) vv)))
                                u v))
              (setq cnt (+ cnt (ad:dimchain pts loc ad:*style-plan*)))))))))
  cnt)

;; ------------------------------------------------- part 3: the floor dims

;; WCS intersection points between the line object and every object in ss
(defun ad:xpoints (lobj ss / i rtn pts res)
  (setq res '()
        i   0)
  (if ss
    (repeat (sslength ss)
      (setq rtn (vl-catch-all-apply
                  'vlax-invoke
                  (list lobj 'IntersectWith
                        (vlax-ename->vla-object (ssname ss i)) acextendnone)))
      (setq i (1+ i))
      (if (not (vl-catch-all-error-p rtn))
        (progn
          (setq pts rtn)
          (while (and pts (cddr pts))
            (setq res (cons (list (car pts) (cadr pts) (caddr pts)) res)
                  pts (cdddr pts)))))))
  res)

;; build one floor dims chain along p1->p2 (WCS): a first aligned dim
;; followed by DIMCONTINUE through every break point, breaking wherever
;; an obstacle stands in the line's way.  An end point the user did not
;; land on an object is pulled back to the last object before it, so
;; every dim runs object to object.
;; Returns the number of dimensions placed.
(defun ad:floorchain (p1 p2 loc obstacles / ssx lin lobj len dir ds d x
                                            starton endon chain prev)
  (setq ssx (if obstacles obstacles (ad:geomss)))
  (entmake (list '(0 . "LINE") (cons 10 p1) (cons 11 p2)))
  (setq lin  (entlast)
        lobj (vlax-ename->vla-object lin))
  (if (and ssx (ssmemb lin ssx)) (ssdel lin ssx))
  (setq len (distance p1 p2)
        dir (mapcar '(lambda (b c) (/ (- c b) len)) p1 p2)
        ds  '())
  ;; distance of every crossing object along the line, noting crossings
  ;; sitting right on the picked start / end points
  (foreach x (ad:xpoints lobj ssx)
    (setq d (apply '+ (mapcar '* dir (mapcar '- x p1))))
    (cond ((< (abs d) 1e-4)           (setq starton t))
          ((< (abs (- d len)) 1e-4)   (setq endon t))
          ((and (> d 1e-4) (< d (- len 1e-4))) (setq ds (cons d ds)))))
  (entdel lin)
  ;; sorted break points, near-coincident ones merged
  (setq chain (list p1)
        prev  0.0)
  (foreach d (vl-sort ds '<)
    (if (> (- d prev) 1e-4)
      (setq chain (cons (mapcar '(lambda (b v) (+ b (* d v))) p1 dir) chain)
            prev  d)))
  (setq chain (reverse (cons p2 chain)))
  ;; an end the user did not land on an object is pulled back to the
  ;; last object before it, so every dim in the chain runs object to
  ;; object and none hangs off the end into open drawing
  (if (not starton)
    (progn
      (setq chain (cdr chain))
      (prompt (strcat "\n  (start point was not on an object - the chain"
                      " starts at the first one the line crosses)"))))
  (if (and (cdr chain) (not endon))
    (progn
      (setq chain (reverse (cdr (reverse chain))))
      (prompt (strcat "\n  (end point was not on an object - the chain"
                      " stops at the last one the line crosses)"))))
  (if (cdr chain)
    (ad:dimchain chain loc ad:*style-floor*)
    0))

;; erase everything drawn after entity MARK (nil = an empty drawing) -
;; the rollback when a Back re-opens an earlier dimensioning step.  The
;; record of what is dimensioned is read again afterwards, so a dim
;; this rolled back does not go on blocking its own place.
(defun ad:eraseafter (mark / en nx)
  (setq en (if mark (entnext mark) (entnext)))
  (while en
    (setq nx (entnext en))
    (if (entget en) (entdel en))
    (setq en nx))
  (ad:dimscan))

;; prompt the user to draw one floor dims line and dimension it,
;; breaking at the given obstacles (nil = all model space geometry).
;; The three picks step back through each other with Back (Undo is
;; accepted too); with BACK non-nil, Back at the START pick returns
;; the symbol CAL-BACK so the caller can re-open its previous step.
;; Returns the dimension count, or nil when the line was skipped.
(defun ad:getfloor (tag obstacles back / p1 p2 loc n stage out)
  (setq stage 1 out nil)
  (while (null out)
    (cond
      ((= stage 1)
       (if back (initget "Back Undo") (initget ""))
       (setq p1 (getpoint (strcat "\n" tag
                                  " - pick the START point of the line to"
                                  " measure along (Enter to skip"
                                  (if back ", or Back" "") "): ")))
       (cond
         ((null p1) (prompt "\nNothing drawn - skipped.") (setq out 'skip))
         ((= (type p1) 'STR) (setq out 'CAL-BACK))
         (T (setq stage 2))))
      ((= stage 2)
       (initget "Back Undo")
       (setq p2 (getpoint p1 (strcat "\n" tag
                                     " - pick the END point [Back]: ")))
       (cond
         ((= (type p2) 'STR) (setq stage 1))
         ((or (null p2) (<= (distance p1 p2) 1e-8))
          (prompt "\nNothing drawn - skipped.")
          (setq out 'skip))
         (T (setq stage 3))))
      (T
       (initget "Back Undo")
       (setq loc (getpoint (strcat "\n" tag
                                   " - pick where the dimension chain"
                                   " should sit <on the drawn line> [Back]: ")))
       (if (= (type loc) 'STR)
         (setq stage 2)
         (progn
           (if (null loc) (setq loc (cal:midn p1 p2)))
           (setq n (ad:floorchain (trans p1 1 0) (trans p2 1 0)
                                  (trans loc 1 0) obstacles))
           (if (> n 0)
             (prompt (strcat "\n" tag ": " (itoa n) " dimension(s) placed."))
             (prompt (strcat "\n" tag ": the line did not cross two"
                             " objects - no dimensions placed.")))
           (setq out (list n)))))))
  (cond
    ((eq out 'CAL-BACK) 'CAL-BACK)
    ((eq out 'skip) nil)
    (T (car out))))

;; ---------------------------------------------- part 4: the overall dims

;; T when the boxes a and b, each (min max), overlap in plan
(defun ad:boxlap (a b)
  (and (<= (car  (car a)) (car  (cadr b)))
       (>= (car  (cadr a)) (car  (car b)))
       (<= (cadr (car a)) (cadr (cadr b)))
       (>= (cadr (cadr a)) (cadr (car b)))))

;; the extents the overall dims have to clear: the plan's own box grown
;; by every dimension sitting around it.  Dims far away - another plan
;; on the same sheet, the title block - are left out; only those within
;; a margin of the plan count as its dims.
(defun ad:dimextents (plan / box mrg near ss i en b mn mx)
  (setq box (cal:bbox-ss plan))
  (if box
    (progn
      (setq mrg  (max (* 4.0 (ad:onefoot)) (* 4.0 (ad:dimoff)))
            near (list (mapcar '(lambda (v) (- v mrg)) (car box))
                       (mapcar '(lambda (v) (+ v mrg)) (cadr box)))
            mn   (car box)
            mx   (cadr box)
            ss   (ad:dimss)
            i    0)
      (if ss
        (repeat (sslength ss)
          (setq en (ssname ss i)
                i  (1+ i)
                b  (cal:bbox-ent en))
          (if (and b (ad:boxlap b near))
            (setq mn (mapcar 'min mn (car b))
                  mx (mapcar 'max mx (cadr b))))))
      (list mn mx))))

;; the two overall dims, both in the "STANDARD" style: the plan's full
;; width about two feet above the topmost dimension around it, and its
;; full height about two feet to the left of the left-most one.  Both
;; extents are read before either dim goes in, so the first one placed
;; cannot push the second further out.
;; Returns how many were placed (0, 1 or 2 - one already there is not
;; repeated).
(defun ad:overall (plan / box out gap x0 y0 x1 y1 cnt)
  (setq cnt 0
        box (cal:bbox-ss plan))
  (if box
    (progn
      (setq out (ad:dimextents plan)
            gap (* 2.0 (ad:onefoot))
            x0  (car  (car box))
            y0  (cadr (car box))
            x1  (car  (cadr box))
            y1  (cadr (cadr box)))
      ;; overall width, sitting two feet above the topmost dim
      (setq cnt (+ cnt (ad:putlinear
                         (list x0 y1 0.0)
                         (list x1 y1 0.0)
                         (list (* 0.5 (+ x0 x1)) (+ (cadr (cadr out)) gap) 0.0)
                         "_H" ad:*style-over*)))
      ;; overall height, sitting two feet left of the left-most dim
      (setq cnt (+ cnt (ad:putlinear
                         (list x0 y0 0.0)
                         (list x0 y1 0.0)
                         (list (- (car (car out)) gap) (* 0.5 (+ y0 y1)) 0.0)
                         "_V" ad:*style-over*)))))
  cnt)

;; ------------------------------------- part 5: steps drawn in side view

;; every vertical segment in ss as (top bottom), from the top step down
;; - the risers of a flight drawn in side view
(defun ad:risers (ss / s out)
  (setq out '())
  (foreach s (ad:allsegs ss)
    (if (and (< (ad:angdiff (ad:segang s) (* 0.5 pi)) 1e-3)
             (> (abs (- (cadr (car s)) (cadr (cadr s)))) 1e-4))
      (setq out (cons (if (> (cadr (car s)) (cadr (cadr s)))
                        s
                        (list (cadr s) (car s)))
                      out))))
  (ad:topdown out))

;; risers ordered from the top step down
(defun ad:topdown (risers)
  (vl-sort risers '(lambda (a b) (> (cadr (car a)) (cadr (car b))))))

;; the nosing corners of a flight, top down: the top of the top riser,
;; then the bottom corner of every riser going down the flight
(defun ad:stepchain (risers)
  (cons (car (car risers)) (mapcar 'cadr risers)))

;; T when the risers, taken in the order given, are a connected
;; staircase: each one starts where the one before it finished, a
;; tread's run further along
(defun ad:stairlike-p (risers tol / r prev ok)
  (setq ok   t
        prev (car risers))
  (foreach r (cdr risers)
    (if (or (> (abs (- (cadr (car r)) (cadr (cadr prev)))) tol)
            (<= (abs (- (car (car r)) (car (car prev)))) tol))
      (setq ok nil))
    (setq prev r))
  ok)

;; Does the highlighted geometry look like a flight of steps drawn in
;; side view rather than a plan?  It does when
;;   * nothing in it is curved - no arc, circle, ellipse, spline,
;;     polyline bulge or block;
;;   * three quarters or more of its straight segments run square, so a
;;     sloping pool floor at the foot of the flight is still allowed;
;;   * it has two or more risers and at least one tread per gap
;;     between them;
;;   * and the risers form a connected staircase across the drawing,
;;     each starting where the one before it finished.
;; A vertical as tall as the whole profile is the back wall, not a
;; step, and is left out of that reckoning - which is also what stops a
;; rectangular plan reading as a two-step flight.
;; Returns the risers, top down, or nil.
(defun ad:stepprofile-p (ss / segs s pp vert horz nsq ymin ymax hgt
                              tol risers r)
  (setq segs (ad:allsegs ss)
        vert '()
        horz '()
        ymin nil
        ymax nil)
  (foreach s segs
    (cond ((< (ad:angdiff (ad:segang s) (* 0.5 pi)) 1e-3)
           (setq vert (cons s vert)))
          ((< (ad:angdiff (ad:segang s) 0.0) 1e-3)
           (setq horz (cons s horz))))
    (foreach pp s
      (setq ymin (if ymin (min ymin (cadr pp)) (cadr pp))
            ymax (if ymax (max ymax (cadr pp)) (cadr pp)))))
  (setq nsq (+ (length vert) (length horz))
        hgt (if ymin (- ymax ymin) 0.0))
  (if (and (> hgt 1e-8)
           (zerop (ad:curves ss))
           (>= (length vert) 2)
           (>= (length horz) 1)
           (>= (* 4 nsq) (* 3 (length segs))))
    (progn
      ;; the risers, a full-height back wall left out
      (setq tol    (max (ad:dupetol) (* 0.01 hgt))
            risers '())
      (foreach s vert
        (setq r (if (> (cadr (car s)) (cadr (cadr s)))
                  s
                  (list (cadr s) (car s))))
        (if (< (- (cadr (car r)) (cadr (cadr r))) (* 0.9 hgt))
          (setq risers (cons r risers))))
      (setq risers (vl-sort risers
                            '(lambda (a b) (< (car (car a)) (car (car b))))))
      (if (and (cdr risers)
               (>= (length horz) (1- (length risers)))
               (or (ad:stairlike-p risers tol)
                   (ad:stairlike-p (reverse risers) tol)))
        (ad:topdown risers)))))

;; Dimension a flight of steps drawn in side view: one vertical dim for
;; the depth of every step, then the overall depth one step further
;; out.  side is 1.0 to put them to the right of the profile, -1.0 to
;; put them to the left.  With stack non-nil they all sit on one line
;; clear of the whole flight; with it nil each sits just outside its
;; own step, walking down with the stairs.
;; Returns the number of dimensions placed.
(defun ad:dimsteps (chain side stack base / clear xs xdim edge loc
                                            cnt nris prev pb)
  (setq clear (max (ad:dimoff) (* 2.0 (ad:onefoot)))
        cnt   0
        nris  0
        edge  nil
        prev  (car chain))
  (if stack
    (setq xs   (mapcar 'car chain)
          xdim (+ (* side clear)
                  (if (> side 0.0) (apply 'max xs) (apply 'min xs)))
          edge xdim))
  (foreach pb (cdr chain)
    (if (> (abs (- (cadr prev) (cadr pb))) 1e-4)
      (progn
        (if (not stack)
          (setq xdim (+ (* side clear)
                        (if (> side 0.0)
                          (max (car prev) (car pb))
                          (min (car prev) (car pb))))
                edge (cond ((null edge) xdim)
                           ((> side 0.0) (max edge xdim))
                           (t (min edge xdim)))))
        (setq loc  (list xdim (* 0.5 (+ (cadr prev) (cadr pb))) 0.0)
              cnt  (+ cnt (ad:putlinear prev pb loc "_V" base))
              nris (1+ nris))))
    (setq prev pb))
  ;; the overall depth, one step further out again - counted off the
  ;; risers found, not the dims placed, so a flight that is dimensioned
  ;; already still gets its overall
  (if (> nris 1)
    (setq cnt (+ cnt (ad:putlinear
                       (last chain) (car chain)
                       (list (+ edge (* side clear))
                             (* 0.5 (+ (cadr (car chain))
                                       (cadr (last chain))))
                             0.0)
                       "_V" base))))
  cnt)

;; --------------------------------------------------------------- commands

;; AUTODIM's plan flow, steps 2 to 5: the perimeter, then the stairs,
;; then the two floor dims lines, then the two overall dims.
(defun ad:runplan (plan / nper nstair nover nf1 nf2 stage mark3 mark4 v)
  (prompt (strcat "\n=== AUTODIM step 2 of 5: perimeter ==="
                  "\nDimensioning the straight lines about the"
                  " perimeter - no input needed..."))
  (setq nper (ad:dimperim plan))
  (prompt (strcat "\n" (itoa nper) " perimeter dimension(s) placed."))
  ;; steps 3 and 4 walk back through each other: Back at the floor dims
  ;; question re-opens the stairs, erasing what they drew, and Back at
  ;; the second floor line re-opens the first
  (setq stage 3)
  (while (< stage 7)
    (cond
      ((= stage 3)
       (prompt "\n=== AUTODIM step 3 of 5: stairs ===")
       (setq mark3  (entlast)
             nstair (ad:dimstairs))
       (prompt (strcat "\n" (itoa nstair) " stair dimension(s) placed."))
       (setq stage 4))
      ((= stage 4)
       (prompt (strcat "\n=== AUTODIM step 4 of 5: floor dims ==="
                       "\nTwo lines drawn across the plan, each becoming a"
                       " dimension chain in \"" ad:*style-floor* "\" that"
                       " breaks at every highlighted object it crosses.  A"
                       " start or end point that is not on an object pulls"
                       " back to the last object before it, so every dim"
                       " runs object to object."))
       (setq v (cal:askyn "Would you like floor dims?" "Yes" T))
       (cond
         ((eq v 'CAL-BACK)
          (ad:eraseafter mark3)
          (prompt "\nStepping back to the stairs.")
          (setq stage 3))
         (v (setq stage 5))
         (T (prompt "\nNo floor dims.")
            (setq stage 7))))
      ((= stage 5)
       (setq mark4 (entlast)
             v     (ad:getfloor "Floor dims 1 of 2" plan T))
       (if (eq v 'CAL-BACK)
         (progn
           (prompt "\nStepping back to the floor dims question.")
           (setq stage 4))
         (progn
           (setq nf1 (if (numberp v) v 0))    ; 'skip counts as none
           (setq stage 6))))
      (T
       (setq v (ad:getfloor "Floor dims 2 of 2" plan T))
       (if (eq v 'CAL-BACK)
         (progn
           (ad:eraseafter mark4)
           (prompt "\nStepping back one floor line.")
           (setq nf1 0)                       ; its dims were just erased
           (setq stage 5))
         (progn
           (setq nf2 (if (numberp v) v 0))
           (setq stage 7))))))
  (prompt (strcat "\n=== AUTODIM step 5 of 5: overall dims ==="
                  "\nPlacing the overall width about 2ft above the"
                  " topmost dim and the overall height about 2ft to"
                  " the left of the left-most one - no input"
                  " needed..."))
  (setq nover (ad:overall plan))
  (prompt (strcat "\n" (itoa nover) " overall dimension(s) placed."))
  ;; the run's total, for AUTODIM's sign-off line
  (+ nper nstair (if nf1 nf1 0) (if nf2 nf2 0) nover))

;; AUTODIM's side-view flow, for when step 1's selection turned out to
;; be a flight of steps drawn in side view: the depth of every step
;; down the right-hand side, then the overall depth further right
;; again.  Nothing else is asked for - the perimeter, stairs and floor
;; dims steps are all about a plan.
(defun ad:runsteps (risers / n)
  (prompt (strcat "\n=== AUTODIM: that is a side view of steps ==="
                  "\nDimensioning the depth of every step, to the right"
                  " of the flight in \"" ad:*style-short* "\", and the"
                  " overall depth further right again - no input"
                  " needed..."))
  (setq n (ad:dimsteps (ad:stepchain risers) 1.0 T ad:*style-short*))
  (prompt (strcat "\n" (itoa n) " step dimension(s) placed."))
  ;; the run's total, for AUTODIM's sign-off line
  n)

(defun c:AUTODIM (/ *error* oldcmd olddim plan risers n undo-open)
  (defun *error* (msg)
    ;; only close a group that was actually opened - the handler is
    ;; live before _Begin runs (AUTODIM's is during its selection)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq plan (ssget "_I" (ad:geomfilter)))
  (if (null plan)
    (progn
      (prompt (strcat "\n=== AUTODIM step 1: highlight the plan ==="
                      "\nHighlight everything that makes up the plan (walls"
                      " etc.), then press Enter.  Only what you highlight is"
                      " dimensioned and used to find the perimeter."
                      "\nHighlight a flight of steps drawn in side view"
                      " instead and it is recognised as one: the depth of"
                      " every step gets dimensioned rather than a plan."))
      (setq plan (ssget (ad:geomfilter)))))
  (if (null plan)
    (prompt "\nNothing highlighted - AUTODIM cancelled.")
    (progn
      (setq oldcmd (getvar "CMDECHO")
            olddim (getvar "DIMSTYLE"))
      (setvar "CMDECHO" 0)
      (ad:begin)
      (command "_.UNDO" "_Begin")
      (setq undo-open T)
      (setq n (if (setq risers (ad:stepprofile-p plan))
                (ad:runsteps risers)
                (ad:runplan plan)))
      (ad:skipreport)
      (ad:usestyle olddim)
      (command "_.UNDO" "_End")
      (setq undo-open nil)
      (setvar "CMDECHO" oldcmd)
      (prompt (strcat "\nAUTODIM finished - "
                      (if (numberp n) (itoa n) "0")
                      " dimension(s) placed."))))
  (princ))

(defun c:STAIRDIM (/ *error* oldcmd olddim n undo-open)
  (defun *error* (msg)
    ;; only close a group that was actually opened - the handler is
    ;; live before _Begin runs (AUTODIM's is during its selection)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (setq oldcmd (getvar "CMDECHO")
        olddim (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)
  (ad:begin)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  (setq n (ad:dimstairs))
  (prompt (strcat "\n" (itoa n) " stair dimension(s) placed."))
  (ad:skipreport)
  (ad:usestyle olddim)
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (setvar "CMDECHO" oldcmd)
  (princ))

(defun c:FLOORDIM (/ *error* oldcmd olddim n undo-open)
  (defun *error* (msg)
    ;; only close a group that was actually opened - the handler is
    ;; live before _Begin runs (AUTODIM's is during its selection)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (setq oldcmd (getvar "CMDECHO")
        olddim (getvar "DIMSTYLE"))
  (setvar "CMDECHO" 0)
  (ad:begin)
  (command "_.UNDO" "_Begin")
  (setq undo-open T)
  (setq n (ad:getfloor "Floor dims" nil nil))
  (prompt (strcat "\n" (if (numberp n) (itoa n) "0")
                  " floor dimension(s) placed."))
  (ad:skipreport)
  (ad:usestyle olddim)
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (setvar "CMDECHO" oldcmd)
  (princ))

;; AUTODIMSIDEPOV - dimension steps drawn in side view (elevation):
;; every riser gets a vertical dimension placed beside its step,
;; stepping down the flight with the nosing corners as extension line
;; origins, plus one overall height dimension further out.  The dims
;; are created on layer "DIMENSION" in the "STANDARD INCHES" style to
;; match the reference drawing - a riser is under a foot anyway, so
;; that is the style the length rule asks for too.  A riser that is
;; dimensioned already is left alone, as everywhere else.
(defun c:AUTODIMSIDEPOV (/ *error* oldcmd olddim oldlay ss risers chain
                            sx cnt undo-open)
  (defun *error* (msg)
    ;; only close a group that was actually opened - the handler is
    ;; live before _Begin runs (AUTODIM's is during its selection)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq undo-open nil)
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldlay (setvar "CLAYER" oldlay))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  ;; a pickfirst selection if there is one, otherwise ask for it
  (setq ss (ssget "_I" '((0 . "LINE,LWPOLYLINE"))))
  (if (null ss)
    (progn
      (prompt (strcat "\nAUTODIMSIDEPOV - dimensions steps drawn in side"
                      " view: every riser gets a vertical dim beside its"
                      " step, plus the overall height."
                      "\nHighlight the side view of the steps, then press"
                      " Enter."))
      (setq ss (ssget '((0 . "LINE,LWPOLYLINE"))))))
  (if (null ss)
    (prompt "\nNothing highlighted - AUTODIMSIDEPOV cancelled.")
    (progn
      (setq oldcmd (getvar "CMDECHO")
            olddim (getvar "DIMSTYLE")
            oldlay (getvar "CLAYER"))
      (setvar "CMDECHO" 0)
      (ad:begin)
      (command "_.UNDO" "_Begin")
      (setq undo-open T)
      (ad:setlayer "DIMENSION")
      ;; told these are steps, so every vertical is taken as a riser -
      ;; no staircase test here, unlike AUTODIM's own side-view branch
      (setq risers (ad:risers ss))
      (if (null risers)
        (prompt (strcat "\nNo vertical riser lines found in the selection"
                        " - nothing dimensioned."))
        (progn
          (setq chain (ad:stepchain risers)
                ;; dims go on the high side of the steps
                sx    (if (>= (car (car chain)) (car (last chain))) 1.0 -1.0)
                cnt   (ad:dimsteps chain sx nil ad:*style-short*))
          (prompt (strcat "\n" (itoa cnt) " step dimension(s) placed."))
          (ad:skipreport)))
      (ad:usestyle olddim)
      (setvar "CLAYER" oldlay)
      (command "_.UNDO" "_End")
      (setq undo-open nil)
      (setvar "CMDECHO" oldcmd)))
  (princ))

(defun c:AUTODIMVER ()
  (princ (strcat "\nAUTODIM " *autodim-version*))
  (princ))

(princ (strcat "\nAutoDim.lsp " *autodim-version* " loaded.  Commands: AUTODIM (highlight plan -> perimeter + stairs + two floor dims + the two overall dims; highlight a side view of steps -> the depth of every step), STAIRDIM (dimension another stair selection), FLOORDIM (one extra floor dims chain), AUTODIMSIDEPOV (dimension steps drawn in side view)."))
(princ)
