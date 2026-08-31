;;; ======================================================================
;;; TYLERDRONE.lsp  --  the drone trace in one file
;;; ----------------------------------------------------------------------
;;; Built 2026-08-31 by tools/build_drone_edition.py -- DO NOT EDIT.
;;; Edit the files under lisp/ and rebuild.
;;;
;;; APPLOAD this one file.  It carries:
;;;     AutoDim.lsp        v1.0
;;;     PADDLE.lsp         v1.4
;;;     tydrn.lsp          v1.1
;;;     LAZPANEL.lsp       v3.4
;;;
;;; Then type TYLERDRONESUITE, or click the orange triangle
;;; on screen.  That button is the only one this build puts
;;; up: LAZPANEL is here for the machinery that draws it and
;;; still types the same as ever, it is just not on the
;;; strip.  For the whole calofin toolkit, use LAZPASS.lsp
;;; instead -- there the suite rides the panel like every
;;; other tool and does not take a button of its own.
;;; ======================================================================

;;; ======================================================================
;;; >>> lisp/autodim/AutoDim.lsp
;;; ======================================================================

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

(setq *autodim-version* "v1.0")   ; announced on load; release_lisp.py
                                     ; stamps the dated twin in releases/

(vl-load-com)

;; ---------------------------------------------------------------- helpers

;; midpoint of two points
(defun ad:mid (p1 p2) (mapcar '(lambda (a b) (* 0.5 (+ a b))) p1 p2))

;; dot product
(defun ad:dot (p q) (apply '+ (mapcar '* p q)))

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

;; Keyword question.  kws is the initget string, shown the bracketed
;; list, dflt the Enter answer (nil = an answer is required).  Returns
;; the keyword, or AD-BACK for Back/Undo, which is accepted everywhere
;; Back is as a hidden synonym.  (STANDARDS.md section 4.)
(defun ad:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'AD-BACK)
        ((null v) (if dflt dflt (ad:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No that can be backed out of.  Returns T, nil or AD-BACK.
(defun ad:askyn (msg dflt back / v)
  (setq v (ad:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'AD-BACK) v (= v "Yes")))

;; restore a dimension style by name if the drawing has it,
;; return T when the style was set
(defun ad:setdimstyle (name)
  (if (and name (tblsearch "DIMSTYLE" name))
    (progn (command "_.-DIMSTYLE" "_Restore" name) t)))

;; make a layer current, creating it first when the drawing lacks it
(defun ad:setlayer (name)
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   '(70 . 0)
                   '(62 . 7)
                   '(6 . "Continuous"))))
  (setvar "CLAYER" name))

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
            cen   (polar (ad:mid p1 p2)
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

;; WCS bounding box of a selection set as (min max), nil if none
(defun ad:ssbox (ss / i obj ll ur mn mx)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq obj (vlax-ename->vla-object (ssname ss i))
            i   (1+ i))
      (if (not (vl-catch-all-error-p
                 (vl-catch-all-apply 'vla-getboundingbox (list obj 'll 'ur))))
        (progn
          (setq ll (vlax-safearray->list ll)
                ur (vlax-safearray->list ur)
                mn (if mn (mapcar 'min mn ll) ll)
                mx (if mx (mapcar 'max mx ur) ur))))))
  (if mn (list mn mx)))

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
  (setq mid (ad:mid p1 p2)
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
                              (polar (ad:mid (car seg) (cadr seg)) pa off))
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
  (setq box (ad:ssbox ss)
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
            (setq tds  (cons (cons (ad:dot (ad:mid (car s) (cadr s)) v) s) tds)
                  smax (apply 'max
                              (append (if smax (list smax))
                                      (list (ad:dot (car s) u)
                                            (ad:dot (cadr s) u))))))
          (setq tds (vl-sort tds '(lambda (x y) (< (car x) (car y)))))
          ;; widths of the steps (repeated only when the width changes)
          (setq lastw nil)
          (foreach td tds
            (setq w (distance (cadr td) (caddr td)))
            (if (or (null lastw) (> (abs (- w lastw)) 1e-4))
              (progn
                (setq mid (ad:mid (cadr td) (caddr td))
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
;; the symbol AD-BACK so the caller can re-open its previous step.
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
         ((= (type p1) 'STR) (setq out 'AD-BACK))
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
           (if (null loc) (setq loc (ad:mid p1 p2)))
           (setq n (ad:floorchain (trans p1 1 0) (trans p2 1 0)
                                  (trans loc 1 0) obstacles))
           (if (> n 0)
             (prompt (strcat "\n" tag ": " (itoa n) " dimension(s) placed."))
             (prompt (strcat "\n" tag ": the line did not cross two"
                             " objects - no dimensions placed.")))
           (setq out (list n)))))))
  (cond
    ((eq out 'AD-BACK) 'AD-BACK)
    ((eq out 'skip) nil)
    (T (car out))))

;; ---------------------------------------------- part 4: the overall dims

;; WCS bounding box of one entity, nil when it has none
(defun ad:entbox (en / obj ll ur)
  (setq obj (vlax-ename->vla-object en))
  (if (not (vl-catch-all-error-p
             (vl-catch-all-apply 'vla-getboundingbox (list obj 'll 'ur))))
    (list (vlax-safearray->list ll) (vlax-safearray->list ur))))

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
  (setq box (ad:ssbox plan))
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
                b  (ad:entbox en))
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
        box (ad:ssbox plan))
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
(defun ad:runplan (plan / nper nstair nover stage mark3 mark4 v)
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
       (setq v (ad:askyn "Would you like floor dims?" "Yes" T))
       (cond
         ((eq v 'AD-BACK)
          (ad:eraseafter mark3)
          (prompt "\nStepping back to the stairs.")
          (setq stage 3))
         (v (setq stage 5))
         (T (prompt "\nNo floor dims.")
            (setq stage 7))))
      ((= stage 5)
       (setq mark4 (entlast)
             v     (ad:getfloor "Floor dims 1 of 2" plan T))
       (if (eq v 'AD-BACK)
         (progn
           (prompt "\nStepping back to the floor dims question.")
           (setq stage 4))
         (setq stage 6)))
      (T
       (setq v (ad:getfloor "Floor dims 2 of 2" plan T))
       (if (eq v 'AD-BACK)
         (progn
           (ad:eraseafter mark4)
           (prompt "\nStepping back one floor line.")
           (setq stage 5))
         (setq stage 7)))))
  (prompt (strcat "\n=== AUTODIM step 5 of 5: overall dims ==="
                  "\nPlacing the overall width about 2ft above the"
                  " topmost dim and the overall height about 2ft to"
                  " the left of the left-most one - no input"
                  " needed..."))
  (setq nover (ad:overall plan))
  (prompt (strcat "\n" (itoa nover) " overall dimension(s) placed."))
  (princ))

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
  (princ))

(defun c:AUTODIM (/ *error* oldcmd olddim plan risers)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (prompt (strcat "\n=== AUTODIM step 1: highlight the plan ==="
                  "\nHighlight everything that makes up the plan (walls"
                  " etc.), then press Enter.  Only what you highlight is"
                  " dimensioned and used to find the perimeter."
                  "\nHighlight a flight of steps drawn in side view"
                  " instead and it is recognised as one: the depth of"
                  " every step gets dimensioned rather than a plan."))
  (setq plan (ssget (ad:geomfilter)))
  (if (null plan)
    (prompt "\nNothing highlighted - AUTODIM cancelled.")
    (progn
      (setq oldcmd (getvar "CMDECHO")
            olddim (getvar "DIMSTYLE"))
      (setvar "CMDECHO" 0)
      (ad:begin)
      (command "_.UNDO" "_Begin")
      (if (setq risers (ad:stepprofile-p plan))
        (ad:runsteps risers)
        (ad:runplan plan))
      (ad:skipreport)
      (ad:usestyle olddim)
      (command "_.UNDO" "_End")
      (setvar "CMDECHO" oldcmd)
      (prompt "\nAUTODIM finished.")))
  (princ))

(defun c:STAIRDIM (/ *error* oldcmd olddim n)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
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
  (setq n (ad:dimstairs))
  (prompt (strcat "\n" (itoa n) " stair dimension(s) placed."))
  (ad:skipreport)
  (ad:usestyle olddim)
  (command "_.UNDO" "_End")
  (setvar "CMDECHO" oldcmd)
  (princ))

(defun c:FLOORDIM (/ *error* oldcmd olddim)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
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
  (ad:getfloor "Floor dims" nil nil)
  (ad:skipreport)
  (ad:usestyle olddim)
  (command "_.UNDO" "_End")
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
                            sx cnt)
  (defun *error* (msg)
    (vl-catch-all-apply 'command-s (list "_.UNDO" "_End"))
    (if olddim
      (vl-catch-all-apply 'command-s (list "_.-DIMSTYLE" "_Restore" olddim)))
    (if oldlay (setvar "CLAYER" oldlay))
    (if oldcmd (setvar "CMDECHO" oldcmd))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (prompt (strcat "\nAutoDim error: " msg)))
    (princ))
  (prompt (strcat "\nAUTODIMSIDEPOV - dimensions steps drawn in side view:"
                  " every riser gets a vertical dim beside its step, plus"
                  " the overall height."
                  "\nHighlight the side view of the steps, then press"
                  " Enter."))
  (setq ss (ssget '((0 . "LINE,LWPOLYLINE"))))
  (if (null ss)
    (prompt "\nNothing highlighted - AUTODIMSIDEPOV cancelled.")
    (progn
      (setq oldcmd (getvar "CMDECHO")
            olddim (getvar "DIMSTYLE")
            oldlay (getvar "CLAYER"))
      (setvar "CMDECHO" 0)
      (ad:begin)
      (command "_.UNDO" "_Begin")
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
      (setvar "CMDECHO" oldcmd)))
  (princ))

(princ "\nAutoDim.lsp loaded.  Commands: AUTODIM (highlight plan -> perimeter + stairs + two floor dims + the two overall dims; highlight a side view of steps -> the depth of every step), STAIRDIM (dimension another stair selection), FLOORDIM (one extra floor dims chain), AUTODIMSIDEPOV (dimension steps drawn in side view).")
(princ)

;;; ======================================================================
;;; >>> lisp/paddle/PADDLE.lsp
;;; ======================================================================

;;; ===================================================================
;;; PADDLE.lsp
;;;
;;; Scans the perimeter of a drawing for concave features that require
;;; pads, and inserts 36" x 36" pad blocks ("Pad36x36") centered on
;;; the affected areas, always parallel to the X/Y axes.
;;;
;;; Pad specification:
;;;   * Any CONCAVE arc / fillet with a radius of 4'-6" (54") or less
;;;     -- all the way down to sharp 90-degree inside corners --
;;;     requires pads along the affected arc.
;;;   * Any CONCAVE intersection of straight segments (an inside
;;;     corner) requires a pad centered on the corner.
;;;   * Semi-straight geometry is left alone: a connection point or an
;;;     arc whose total bend is 10 degrees or less is not a feature.
;;;   * Convex features and concave arcs larger than 4'-6" radius do
;;;     NOT require pads.
;;;   * Pads never overlap: where features crowd together, a pad on a
;;;     sharp point stays dead-center on that point, and the pads
;;;     along curves do the dodging -- sliding over to sit flush
;;;     alongside, or dropping out when a neighbour covers their spot.
;;;
;;; Accepted perimeter input (generous):
;;;   * a closed LWPOLYLINE or 2D POLYLINE, or
;;;   * loose LINEs / ARCs (or a mix of all of the above) -- PADDLE
;;;     chains touching segments end-to-end into closed loops.
;;;
;;; Usage:
;;;   Command: PADDLE
;;;   Select the perimeter geometry, or press Enter to auto-detect
;;;   the perimeter (the largest closed loop found in the drawing).
;;;
;;;   Command: TUTORIALPADDLE
;;;   Guided tour for new users: lists everything PADDLE checks, then
;;;   optionally draws a labelled sample perimeter and pads it step by
;;;   step so you can watch what happens.
;;;
;;; Versioning: see tools/release_lisp.py at the repo root. It reads
;;; *paddle-version* below and stamps a dated, REV-numbered twin of
;;; this file into releases/.
;;;
;;; Block resolution order for the chosen pad block:
;;;   1. A block definition already in the drawing.
;;;   2. Imported from "24inpad.dwg" found on the AutoCAD support
;;;      path (ships alongside this lisp -- add its folder to the
;;;      support file search path, or drop the dwg next to the
;;;      current drawing).
;;;   3. As a last resort a plain square block of the right size is
;;;      created so the command always works.
;;;
;;; Assumes drawing units are INCHES (architectural). Adjust the
;;; constants below for other setups.
;;; ===================================================================

(vl-load-com)

;; --------------------------- settings ------------------------------
(setq *paddle-version* "v1.4") ; printed on load and at command start
                             ; so a loaded routine and its releases/
                             ; twin can never disagree
(setq *paddle-blkname* "Pad36x36") ; the 3'x3' pad block
(setq *paddle-padsize* 36.0) ; pads are 36" x 36"
(setq *paddle-blkfile* "24inpad.dwg") ; dwg holding the pad blocks
(setq *paddle-maxrad* 54.0)  ; 4'-6" : largest concave radius needing pads
(setq *paddle-layer* "PADS") ; layer pads are inserted on
(setq *paddle-align* nil)    ; nil = pads stay parallel to the X/Y axes,
                             ; T = rotate pads with the perimeter edge
(setq *paddle-fuzz* 0.05)    ; max gap between segment ends when
                             ; chaining loose lines/arcs into a loop
(setq *paddle-angtol* (/ (* 10.0 pi) 180.0)) ; a connection point or an
                             ; arc whose total bend is 10 degrees or
                             ; less is semi-straight - no pad

;; ------------------------ 2D vector helpers ------------------------
(defun paddle--sub (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun paddle--add (a b) (list (+ (car a) (car b)) (+ (cadr a) (cadr b))))
(defun paddle--scl (v k) (list (* (car v) k) (* (cadr v) k)))
(defun paddle--len (v) (distance '(0.0 0.0) v))
(defun paddle--unit (v / l) (if (> (setq l (paddle--len v)) 1e-12) (paddle--scl v (/ 1.0 l))))
(defun paddle--cross (a b) (- (* (car a) (cadr b)) (* (cadr a) (car b))))
(defun paddle--dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun paddle--dir (a) (list (cos a) (sin a))) ; unit vector at angle a
(defun paddle--rot (v a) ; rotate vector v by angle a
  (list (- (* (car v) (cos a)) (* (cadr v) (sin a)))
        (+ (* (car v) (sin a)) (* (cadr v) (cos a)))))
(defun paddle--2d (p) (list (car p) (cadr p)))
(defun paddle--arcpt (cen r ang) (paddle--add cen (paddle--scl (paddle--dir ang) r)))
(defun paddle--cheb (v) (max (abs (car v)) (abs (cadr v)))) ; Chebyshev norm

;; Segment data for vertex A -> B with bulge b (b /= 0):
;; returns (theta radius center start-tangent end-tangent)
;; theta = signed included angle (CCW positive), tangents are angles.
(defun paddle--arcdata (a b blg / theta chord r phi ts cen)
  (setq theta (* 4.0 (atan blg))
        chord (distance a b)
        r     (/ chord (* 2.0 (sin (/ (abs theta) 2.0))))
        phi   (angle a b)
        ts    (- phi (/ theta 2.0))
        cen   (paddle--add a (paddle--scl (paddle--dir (+ ts (if (> blg 0.0) (/ pi 2.0) (/ pi -2.0)))) r)))
  (list theta r cen ts (+ phi (/ theta 2.0))))

;; Signed area of a closed vertex list (shoelace + circular segments).
;; vts = list of (x y bulge), bulge belongs to the segment leaving it.
(defun paddle--area (vts / n i a b blg area theta r seg)
  (setq n (length vts) i 0 area 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq area (+ area (* 0.5 (- (* (car a) (cadr b)) (* (car b) (cadr a))))))
    (if (/= blg 0.0)
        (progn
          (setq seg   (paddle--arcdata a b blg)
                theta (abs (car seg))
                r     (cadr seg))
          (setq area (+ area (* (if (> blg 0.0) 1.0 -1.0)
                                0.5 r r (- theta (sin theta)))))))
    (setq i (1+ i)))
  area)

;; Next pad along an arc: starting from arc-parameter CUR (previous
;; pad center PREV), find the parameter where the pad center is
;; exactly PADSIZE away from PREV in Chebyshev distance -- axis-
;; aligned pads of that size then touch edge-to-edge without ever
;; overlapping. Returns (parameter center), or nil when the rest of
;; the arc is too short for another flush pad.
(defun paddle--next-flush (cen r sa sgn cur sweep prev padsize
                           / ds d p hit lo hi mid)
  (setq ds (/ padsize r 8.0))                ; ~1/8 pad per probe step
  (if (> ds (/ sweep 4.0)) (setq ds (/ sweep 4.0)))
  (setq d cur hit nil)
  (while (and (not hit) (< d (- sweep 1e-9))) ; walk until pads separate
    (setq lo d
          d  (min sweep (+ d ds))
          p  (paddle--arcpt cen r (+ sa (* sgn d))))
    (if (>= (paddle--cheb (paddle--sub p prev)) padsize)
        (setq hit T)))
  (if hit
      (progn ; tighten the crossing between lo and d by bisection
        (setq hi d)
        (repeat 45
          (setq mid (/ (+ lo hi) 2.0)
                p   (paddle--arcpt cen r (+ sa (* sgn mid))))
          (if (>= (paddle--cheb (paddle--sub p prev)) padsize)
              (setq hi mid)
              (setq lo mid)))
        (list hi (paddle--arcpt cen r (+ sa (* sgn hi)))))))

;; Pad centers for one concave arc: the fewest pads that matter most.
;; The first pad is centered on the MIDDLE of the arc (the part that
;; must be covered); further pads march outward toward both ends, each
;; exactly one pad-size on center from the last, so the row touches
;; edge-to-edge and stair-steps into a blocky representation of the
;; curve. Marching stops when the leftover end of the arc is too short
;; for another flush pad -- the extreme ends of the radius are allowed
;; to stay uncovered.
(defun paddle--arc-pads (cen r sa sgn sweep padsize
                         / mid amid pmid fwd bwd cur prev nxt)
  (setq mid  (/ sweep 2.0)
        amid (+ sa (* sgn mid))
        pmid (paddle--arcpt cen r amid))
  ;; march from the middle toward the arc's end...
  (setq cur 0.0 prev pmid fwd nil)
  (while (setq nxt (paddle--next-flush cen r amid sgn cur (- sweep mid) prev padsize))
    (setq cur (car nxt) prev (cadr nxt) fwd (cons prev fwd)))
  ;; ...and from the middle back toward the arc's start
  (setq cur 0.0 prev pmid bwd nil)
  (while (setq nxt (paddle--next-flush cen r amid (- sgn) cur mid prev padsize))
    (setq cur (car nxt) prev (cadr nxt) bwd (cons prev bwd)))
  (append bwd (list pmid) (reverse fwd)))

;; Direction (unit vector) of travel at the START / END of segment a->b.
(defun paddle--tan-start (a b blg)
  (if (= blg 0.0)
      (paddle--unit (paddle--sub b a))
      (paddle--dir (cadddr (paddle--arcdata a b blg)))))
(defun paddle--tan-end (a b blg)
  (if (= blg 0.0)
      (paddle--unit (paddle--sub b a))
      (paddle--dir (last (paddle--arcdata a b blg)))))

;; --------------------- entities -> segments ------------------------
;; A segment is (p1 p2 bulge) with 2D points.

;; LWPOLYLINE -> (closed-flag . vts)
(defun paddle--lwverts (ent / ed out grp)
  (setq ed (entget ent))
  (foreach grp ed
    (cond
      ((= (car grp) 10)
       (setq out (cons (list (cadr grp) (caddr grp) 0.0) out)))
      ((= (car grp) 42)
       (if out (setq out (cons (list (caar out) (cadr (car out)) (cdr grp)) (cdr out)))))))
  (cons (= 1 (logand 1 (cdr (assoc 70 ed)))) (reverse out)))

;; heavy 2D POLYLINE -> (closed-flag . vts), nil for 3D/mesh plines
(defun paddle--plverts (ent / ed flags e ved out p)
  (setq ed (entget ent) flags (cdr (assoc 70 ed)))
  (if (zerop (logand 112 flags)) ; skip 3D polylines / meshes / polyfaces
      (progn
        (setq e (entnext ent))
        (while (and e (= "VERTEX" (cdr (assoc 0 (setq ved (entget e))))))
          (if (zerop (logand 16 (cond ((cdr (assoc 70 ved))) (0)))) ; skip spline frame pts
              (progn
                (setq p (cdr (assoc 10 ved)))
                (setq out (cons (list (car p) (cadr p)
                                      (cond ((cdr (assoc 42 ved))) (0.0)))
                                out))))
          (setq e (entnext e)))
        (cons (= 1 (logand 1 flags)) (reverse out)))))

;; vertex list -> segments (wrapping when closed)
(defun paddle--vts->segs (closed vts / n i segs a b)
  (setq n (length vts) i 0)
  (repeat (if closed n (max 0 (1- n)))
    (setq a (nth i vts)
          b (nth (rem (1+ i) n) vts))
    (setq segs (cons (list (paddle--2d a) (paddle--2d b) (caddr a)) segs))
    (setq i (1+ i)))
  (reverse segs))

;; any supported entity -> list of segments
(defun paddle--ent-segs (ent / ed typ cen r sa ea sweep cv)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (paddle--2d (cdr (assoc 10 ed)))
                 (paddle--2d (cdr (assoc 11 ed))) 0.0)))
    ((= typ "ARC")
     (setq cen   (paddle--2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           sa    (cdr (assoc 50 ed))
           ea    (cdr (assoc 51 ed))
           sweep (- ea sa))
     (if (<= sweep 0.0) (setq sweep (+ sweep pi pi)))
     (list (list (paddle--add cen (paddle--scl (paddle--dir sa) r))
                 (paddle--add cen (paddle--scl (paddle--dir ea) r))
                 (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0)))))) ; tan(sweep/4)
    ((= typ "LWPOLYLINE")
     (setq cv (paddle--lwverts ent))
     (paddle--vts->segs (car cv) (cdr cv)))
    ((= typ "POLYLINE")
     (setq cv (paddle--plverts ent))
     (if cv (paddle--vts->segs (car cv) (cdr cv))))))

;; ------------------- chain segments into loops ---------------------
;; Chains touching segments (ends within *paddle-fuzz*) end-to-end.
;; Returns (loops . open-count); each loop is a vertex list (x y bulge).
(defun paddle--chain (segs / loops nopen chain head tail done found rest s)
  (setq nopen 0)
  ;; drop degenerate slivers
  (setq segs (vl-remove-if
               '(lambda (s) (<= (distance (car s) (cadr s)) *paddle-fuzz*))
               segs))
  (while segs
    (setq chain (list (car segs))
          head  (car (car segs))
          tail  (cadr (car segs))
          segs  (cdr segs)
          done  nil)
    (while (not done)
      (cond
        ;; loop closed back onto its start?
        ((and (> (length chain) 1) (<= (distance tail head) *paddle-fuzz*))
         (setq loops (cons (mapcar '(lambda (s) (list (car (car s)) (cadr (car s)) (caddr s)))
                                   chain)
                           loops)
               done  T))
        (T ;; look for a segment continuing from the tail
         (setq found nil rest nil)
         (foreach s segs
           (if found
               (setq rest (cons s rest))
               (cond
                 ((<= (distance tail (car s)) *paddle-fuzz*)
                  (setq found s))
                 ((<= (distance tail (cadr s)) *paddle-fuzz*) ; reversed
                  (setq found (list (cadr s) (car s) (- (caddr s)))))
                 (T (setq rest (cons s rest))))))
         (if found
             (setq chain (append chain (list found))
                   tail  (cadr found)
                   segs  (reverse rest))
             (setq nopen (1+ nopen) done T)))))) ; dead end: open chain
  (cons (reverse loops) nopen))

;; ------------------------ feature detection ------------------------
;; Returns a list of pads: (center rotation kind), kind = "corner"/"arc".
;; PADSIZE sets the pad-grid pitch used to cover concave arcs.
(defun paddle--features (vts padsize / s n i a b c blg pads din dout turn
                             seg theta r cen sa sgn sweep)
  (setq s (if (< (paddle--area vts) 0.0) -1 1) ; -1 = clockwise
        n (length vts)
        i 0)
  (repeat n
    (setq a   (nth i vts)                     ; segment i : a -> b
          b   (nth (rem (1+ i) n) vts)
          c   (nth (rem (+ i (1- n)) n) vts)  ; previous vertex
          blg (caddr a))

    ;; --- concave vertex (inside corner) at a, between seg i-1 and i ---
    (setq din  (paddle--tan-end (paddle--2d c) (paddle--2d a) (caddr c))
          dout (paddle--tan-start (paddle--2d a) (paddle--2d b) blg))
    (if (and din dout)
        (progn
          (setq turn (atan (paddle--cross din dout) (paddle--dot din dout)))
          (if (< (* s turn) (- *paddle-angtol*)) ; turns away from interior
              (setq pads (cons (list (paddle--2d a) (angle '(0.0 0.0) din) "corner")
                               pads)))))

    ;; --- concave arc segment with radius <= 4'-6" ---
    (if (and (/= blg 0.0)
             (< (* s blg) 0.0)) ; bulges into the interior
        (progn
          (setq seg   (paddle--arcdata (paddle--2d a) (paddle--2d b) blg)
                theta (car seg)
                r     (cadr seg)
                cen   (caddr seg))
          (if (and (<= r (+ *paddle-maxrad* 1e-6))
                   (> (abs theta) *paddle-angtol*)) ; total bend over 10
                                                    ; deg, else it's a
                                                    ; semi-straight line
              (progn
                (setq sa    (angle cen (paddle--2d a))
                      sgn   (if (> theta 0.0) 1.0 -1.0)
                      sweep (abs theta))
                (foreach ctr (paddle--arc-pads cen r sa sgn sweep padsize)
                  (setq pads (cons (list ctr 0.0 "arc") pads)))))))
    (setq i (1+ i)))
  (reverse pads))

;; Keep pads from colliding where features crowd together, without
;; ever pulling a pad off a sharp point. Corner pads commit first,
;; dead-center on their vertex -- they NEVER slide; one that would
;; overlap an earlier corner pad is dropped (in a notch that tight,
;; the neighbour carries the area). Arc pads then dodge around
;; everything committed: one that would overlap a committed pad slides
;; along one axis to sit flush alongside it instead (pads are PADSIZE
;; x PADSIZE, so flush = exactly PADSIZE on center). An arc pad whose
;; center is already inside a committed pad -- or that cannot find a
;; clear flush spot within half a pad of where it wanted to be -- is
;; dropped: its area is covered by the neighbours it kept hitting.
;; Returns the committed pads, corner pads first.
(defun paddle--dodge (pads padsize / out ctr orig tries done hit d ax sgn)
  (foreach pad pads ; sharp points first: exact centers, never slid
    (if (= (caddr pad) "corner")
        (progn
          (setq hit nil)
          (foreach q out
            (if (and (not hit)
                     (< (paddle--cheb (paddle--sub (car pad) (car q)))
                        (- padsize 1e-6)))
                (setq hit T)))
          (if (not hit) (setq out (cons pad out))))))
  (foreach pad pads ; arc pads dodge around what's committed
    (if (/= (caddr pad) "corner")
        (progn
          (setq ctr   (car pad)
                orig  ctr
                tries 0
                done  nil)
          (while (not done)
            (setq hit nil)
            (foreach q out
              (if (and (not hit)
                       (< (paddle--cheb (paddle--sub ctr (car q)))
                          (- padsize 1e-6)))
                  (setq hit (car q))))
            (cond
              ((not hit) ; clear: commit it here
               (setq out  (cons (list ctr (cadr pad) (caddr pad)) out)
                     done T))
              ((or (< (paddle--cheb (paddle--sub ctr hit)) (/ padsize 2.0))
                   (> tries 6)
                   (> (paddle--cheb (paddle--sub ctr orig)) (/ padsize 2.0)))
               (setq done T)) ; already covered there, or stuck: drop it
              (T ; slide along the more-separated axis until flush
               (setq d   (paddle--sub ctr hit)
                     ax  (if (>= (abs (car d)) (abs (cadr d))) 0 1)
                     sgn (if (< (nth ax d) 0.0) -1.0 1.0))
               (setq ctr (if (= ax 0)
                             (list (+ (car hit) (* sgn padsize)) (cadr ctr))
                             (list (car ctr) (+ (cadr hit) (* sgn padsize)))))
               (setq tries (1+ tries))))))))
  (reverse out))

;; ------------------------- block handling --------------------------
;; Make sure block NAME (a SIZE-inch pad) is defined in the drawing.
;; Returns T.
(defun paddle--ensure-block (doc name size / path oldcmd oldatt tmpname)
  (cond
    ((tblsearch "BLOCK" name) T)
    ;; pull the definitions in from the pad dwg if it can be found --
    ;; inserting the file (under a throwaway name, then cancelling)
    ;; imports every block definition it contains
    ((setq path (findfile *paddle-blkfile*))
     (setq oldcmd (getvar "CMDECHO") oldatt (getvar "ATTREQ")
           tmpname "PADDLE-TEMP-IMPORT")
     (setvar "CMDECHO" 0) (setvar "ATTREQ" 0)
     ;; the restore below must run even if the insert throws: oldcmd
     ;; and oldatt are locals of THIS helper, so c:PADDLE's *error*
     ;; handler cannot put them back and the user would be left with
     ;; no command echo and no attribute prompts
     (vl-catch-all-apply
       '(lambda ()
          (command "_.-INSERT" (strcat tmpname "=" path))
          (command)))   ; cancel the insert -- the definitions stay behind
     (setvar "CMDECHO" oldcmd) (setvar "ATTREQ" oldatt)
     (vl-catch-all-apply ; drop the unused throwaway definition
       '(lambda () (vla-Delete (vla-Item (vla-get-Blocks doc) tmpname))))
     (if (tblsearch "BLOCK" name)
         T
         (paddle--make-fallback-block name size)))
    (T (paddle--make-fallback-block name size))))

;; Last-resort pad: a plain size x size square block, base at center.
(defun paddle--make-fallback-block (name size / h)
  (setq h (/ size 2.0))
  (entmake (list '(0 . "BLOCK") (cons 2 name)
                 '(10 0.0 0.0 0.0) '(70 . 0)))
  (entmake (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0")
                 '(100 . "AcDbPolyline") '(90 . 4) '(70 . 1)
                 (list 10 (- h) (- h)) (list 10 h (- h))
                 (list 10 h h) (list 10 (- h) h)))
  (entmake '((0 . "ENDBLK")))
  (princ (strcat "\nPADDLE: block \"" name "\" not found; created a plain "
                 (rtos size 2 0) "x" (rtos size 2 0) " square block instead."))
  (tblsearch "BLOCK" name))

;; Offset from the block's insertion point to the center of its extents
;; (measured at 0 rotation), so pads land centered no matter where the
;; block's base point was drawn.
(defun paddle--block-delta (space name / tmp mn mx d)
  (setq tmp (vla-InsertBlock space (vlax-3d-point 0.0 0.0 0.0)
                             name 1.0 1.0 1.0 0.0))
  (vla-GetBoundingBox tmp 'mn 'mx)
  (setq mn (vlax-safearray->list mn)
        mx (vlax-safearray->list mx)
        d  (list (/ (+ (car mn) (car mx)) 2.0)
                 (/ (+ (cadr mn) (cadr mx)) 2.0)))
  (vla-Delete tmp)
  d)

(defun paddle--ensure-layer (doc)
  (vla-Add (vla-get-Layers doc) *paddle-layer*))

;; Insert one pad so that its extents are centered on CTR. Pads stay
;; parallel to the X/Y axes unless *paddle-align* is set.
(defun paddle--insert-pad (space name ctr rot delta / ip obj)
  (if (not *paddle-align*) (setq rot 0.0))
  (setq ip  (paddle--sub ctr (paddle--rot delta rot))
        obj (vla-InsertBlock space
              (vlax-3d-point (car ip) (cadr ip) 0.0)
              name 1.0 1.0 1.0 rot))
  (vla-put-Layer obj *paddle-layer*)
  obj)

;; --------------------------- selection -----------------------------
;; Turns a selection set (or the whole current tab when SS is nil) into
;; a list of closed perimeter loops (vertex lists). Auto-detect keeps
;; only the largest loop.
(defun paddle--perimeters (ss / auto i segs res loops nopen best bestarea a)
  (setq auto (not ss))
  (if auto
      (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE,POLYLINE,LINE,ARC")
                                 (cons 410 (getvar "CTAB"))))))
  (if ss
      (progn
        (setq i 0)
        (repeat (sslength ss)
          (setq segs (append segs (paddle--ent-segs (ssname ss i)))
                i    (1+ i)))
        (setq res   (paddle--chain segs)
              loops (car res)
              nopen (cdr res))
        (if (> nopen 0)
            (princ (strcat "\nPADDLE: ignored " (itoa nopen)
                           " open chain(s) that never close back on themselves"
                           " (check for gaps; chaining tolerance is "
                           (rtos *paddle-fuzz* 2 2) ").")))
        (if auto
            (progn ; keep only the biggest closed loop
              (setq bestarea 0.0)
              (foreach l loops
                (setq a (abs (paddle--area l)))
                (if (> a bestarea) (setq bestarea a best l)))
              (if best
                  (progn
                    (princ "\nPADDLE: auto-detected the largest closed loop as the perimeter.")
                    (list best))))
            loops))))

;; ---------------------------- command ------------------------------
(defun c:PADDLE (/ *error* doc space padsize blkname ss perims vts
                   allpads delta ndodge ncorner narc)
  (defun *error* (msg)
    (if doc (vla-EndUndoMark doc))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
        (princ (strcat "\nPADDLE error: " msg)))
    (princ))

  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-Block (vla-get-ActiveLayout doc)))

  (princ (strcat "\nPADDLE " *paddle-version*))
  (princ (strcat "\nPADDLE - 36\" pads at concave perimeter features (R <= "
                 (rtos *paddle-maxrad* 4 0) " and inside corners)."))

  (setq padsize *paddle-padsize*
        blkname *paddle-blkname*)

  (princ "\nSelect perimeter (polylines, lines and arcs) or press Enter to auto-detect: ")
  (setq ss (ssget '((0 . "LWPOLYLINE,POLYLINE,LINE,ARC"))))
  (setq perims (paddle--perimeters ss))

  (if (not perims)
      (princ "\nPADDLE: no closed perimeter loop found.")
      (progn
        (vla-StartUndoMark doc)
        (paddle--ensure-block doc blkname padsize)
        (paddle--ensure-layer doc)
        (setq delta (paddle--block-delta space blkname))
        (foreach vts perims
          (if (> (length vts) 1)
              (setq allpads (append allpads (paddle--features vts padsize)))))
        (setq ndodge  (length allpads)
              allpads (paddle--dodge allpads padsize)
              ndodge  (- ndodge (length allpads)))
        (setq ncorner 0 narc 0)
        (foreach pad allpads
          (paddle--insert-pad space blkname (car pad) (cadr pad) delta)
          (if (= (caddr pad) "corner") (setq ncorner (1+ ncorner)) (setq narc (1+ narc))))
        (vla-EndUndoMark doc)
        (if allpads
            (progn
              (princ (strcat "\nPADDLE: inserted " (itoa (length allpads))
                             " 36\" pad(s) on layer \"" *paddle-layer* "\" ("
                             (itoa ncorner) " at inside corners, "
                             (itoa narc) " along concave arcs)."))
              (if (> ndodge 0)
                  (princ (strcat "\nPADDLE: " (itoa ndodge)
                                 " overlapping pad(s) merged into their"
                                 " neighbours where features crowd together."))))
            (princ "\nPADDLE: perimeter checked - no concave features need pads."))))
  (princ))

;; --------------------------- tutorial ------------------------------
;; TUTORIALPADDLE walks a new user through what PADDLE checks, then
;; (optionally) draws a sample perimeter containing every kind of
;; feature and pads it step by step.

(defun paddle--pause ()
  (getstring "\n  [ press ENTER to continue ]")
  (princ))

;; the sample perimeter: straight walls, a 2-degree kink (ignored),
;; convex corners (ignored), a rectangular slot with two >10-degree
;; inside corners (padded), a concave R4'-0" bite (padded row) and a
;; concave R6'-0" sweep (too big -- no pads)
(defun paddle--demo-pline (base lay / pts absv)
  (setq pts '((0 0 0) (150 3 0) (300 0 0) (300 168 0) (264 168 -1.0)
              (168 168 0) (132 168 0) (132 120 0) (84 120 0) (84 168 0)
              (0 168 0) (0 134 -0.4038) (0 34 0)))
  (setq absv (mapcar '(lambda (v) (list (+ (car base) (car v))
                                        (+ (cadr base) (cadr v))
                                        (caddr v)))
                     pts))
  (entmake (append
             (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
                   '(100 . "AcDbPolyline") (cons 90 (length absv)) '(70 . 1))
             (apply 'append
                    (mapcar '(lambda (v) (list (list 10 (car v) (cadr v))
                                               (cons 42 (caddr v))))
                            absv))))
  (entlast))

(defun paddle--demo-text (base lay pt str)
  (entmake (list '(0 . "TEXT") (cons 8 lay)
                 (list 10 (+ (car base) (car pt)) (+ (cadr base) (cadr pt)) 0.0)
                 '(40 . 6.0) (cons 1 str)))
  (entlast))

(defun c:TUTORIALPADDLE (/ doc space base lay ents pl vts feats blk delta
                           pad ncorner narc)
  (setq doc   (vla-get-ActiveDocument (vlax-get-acad-object))
        space (vla-get-Block (vla-get-ActiveLayout doc)))
  (princ (strcat "\n=== PADDLE TUTORIAL " *paddle-version* " ==="))
  (princ "\nPADDLE looks at the perimeter of a drawing and inserts pad blocks")
  (princ "\nwherever the perimeter caves inward. Everything it checks:")
  (princ "\n")
  (princ "\n 1. THE PERIMETER. Select it, or press ENTER and PADDLE finds the")
  (princ "\n    largest closed loop by itself. A closed polyline is ideal, but")
  (princ "\n    loose lines and arcs work too - touching ends (within ")
  (princ (strcat (rtos *paddle-fuzz* 2 2) "\") are"))
  (princ "\n    chained together automatically.")
  (princ (strcat "\n 2. INSIDE CORNERS. A connection point that bends more than "
                 (rtos (/ (* *paddle-angtol* 180.0) pi) 2 0) " degrees"))
  (princ "\n    away from straight gets one pad centered on the corner. Gentler")
  (princ "\n    kinks - semi-straight lines - and all convex (outside) corners")
  (princ "\n    are passed over.")
  (princ (strcat "\n 3. CONCAVE CURVES. A concave radius of " (rtos *paddle-maxrad* 4 0)
                 " or less, bending more"))
  (princ "\n    than 10 degrees in total, gets a row of pads: the middle of the")
  (princ "\n    curve is always covered, then pads march flush toward both ends")
  (princ "\n    (exactly 36\" on center, touching, never overlapping) - a blocky")
  (princ "\n    version of the curve. The extreme ends of the radius may stay")
  (princ "\n    uncovered; that is by design. Bigger concave radii, and curves")
  (princ "\n    bending 10 degrees or less, need no pads at all.")
  (princ "\n 4. NO COLLISIONS. Where features crowd together, a pad on a sharp")
  (princ "\n    point stays dead-center on that point - it never moves. The pads")
  (princ "\n    along curves do the dodging: they slide over to sit flush")
  (princ "\n    alongside, or drop out when a neighbour already covers their spot.")
  (princ (strcat "\n 5. RESULT. 36\" x 36\" pads (block " *paddle-blkname*
                 ", imported from"))
  (princ (strcat "\n    " *paddle-blkfile* " if needed), always square to the"
                 " X/Y axes, on layer"))
  (princ (strcat "\n    \"" *paddle-layer* "\", as a single undo step."))
  (paddle--pause)
  (initget "Yes No")
  (if (/= (getkword "\nDraw a live demonstration in this drawing? [Yes/No] <Yes>: ") "No")
      (progn
        (setq lay "PADDLE-DEMO")
        (vla-put-Color (vla-Add (vla-get-Layers doc) lay) 3)
        (setq base (getpoint "\nPick a clear spot for the demo <0,0>: "))
        (if (not base) (setq base '(0.0 0.0 0.0)))
        (setq pl   (paddle--demo-pline base lay)
              ents (list pl))
        (command "_.ZOOM" "_W"
                 (list (- (car base) 40.0) (- (cadr base) 40.0))
                 (list (+ (car base) 340.0) (+ (cadr base) 210.0)))
        (princ "\nThis sample perimeter (green) has one of everything. Labelling it...")
        (paddle--pause)
        (setq ents (cons (paddle--demo-text base lay '(96 14)
                     "2-deg kink here: 10 deg or less = ignored") ents))
        (setq ents (cons (paddle--demo-text base lay '(140 100)
                     "slot corners bend >10 deg: pad on each") ents))
        (setq ents (cons (paddle--demo-text base lay '(166 108)
                     "concave R4'-0\" (<= R4'-6\"): row of pads") ents))
        (setq ents (cons (paddle--demo-text base lay '(30 84)
                     "concave R6'-0\" (> R4'-6\"): no pads") ents))
        (setq ents (cons (paddle--demo-text base lay '(230 180)
                     "convex corners: never padded") ents))
        (princ "\nRead the labels on the drawing.")
        (paddle--pause)
        ;; run the real PADDLE pipeline on the demo
        (setq vts   (cdr (paddle--lwverts pl))
              feats (paddle--dodge (paddle--features vts *paddle-padsize*)
                                   *paddle-padsize*)
              blk   *paddle-blkname*)
        (paddle--ensure-block doc blk *paddle-padsize*)
        (paddle--ensure-layer doc)
        (setq delta (paddle--block-delta space blk)
              ncorner 0 narc 0)
        (princ "\nStep 1 - inside corners: one pad centered on each corner of the slot.")
        (foreach pad feats
          (if (= (caddr pad) "corner")
              (progn (paddle--insert-pad space blk (car pad) (cadr pad) delta)
                     (setq ents (cons (entlast) ents) ncorner (1+ ncorner)))))
        (paddle--pause)
        (princ "\nStep 2 - the R4'-0\" curve: first pad centered on the middle of the")
        (princ "\nradius, the rest flush at 36\" on center, stair-stepping the curve.")
        (princ "\nNote the R6'-0\" curve and the kink get nothing.")
        (foreach pad feats
          (if (= (caddr pad) "arc")
              (progn (paddle--insert-pad space blk (car pad) (cadr pad) delta)
                     (setq ents (cons (entlast) ents) narc (1+ narc)))))
        (princ (strcat "\nDone: " (itoa ncorner) " corner pad(s) + " (itoa narc)
                       " pad(s) along the curve, on layer \"" *paddle-layer* "\"."))
        (paddle--pause)
        (initget "Yes No")
        (if (= (getkword "\nErase the demonstration? [Yes/No] <No>: ") "Yes")
            (foreach e ents (entdel e)))))
  (princ "\nEnd of tutorial. Type PADDLE to run it on a real drawing.")
  (princ))

(princ (strcat "\nPADDLE " *paddle-version*
               " loaded. Commands: PADDLE (place pads), TUTORIALPADDLE (guided demo)."))
(princ)

;;; ======================================================================
;;; >>> lisp/tydrn/tydrn.lsp
;;; ======================================================================

;;; ===================================================================
;;; TYDRN.LSP                                          AutoCAD 2018
;;; -------------------------------------------------------------------
;;; Commands: TYDRN             the cleanup below
;;;           TYLERDRONESUITE  TYDRN, then PADDLE, then AUTODIM
;;;
;;; Drawing cleanup routine that applies three fixes in one pass:
;;;
;;;   1. TEXT  - every highlighted (pre-selected) text entity is
;;;              switched to style ROMANC at height 4.5, with color,
;;;              linetype and lineweight forced to BYLAYER.
;;;              If nothing is highlighted when the command starts you
;;;              are prompted to select text; pressing Enter at that
;;;              prompt processes ALL text in the drawing.
;;;
;;;   2. POOL POINTS - every POINT entity on layer POOL is moved to
;;;              layer POINTS with color / linetype / lineweight all
;;;              set to BYLAYER (POINTS is magenta, so they show pink).
;;;
;;;   3. ANCHOR POINTS - every POINT entity on layer ANCHORS is given
;;;              an explicit magenta (ACI 6) color - the same pink as
;;;              the points - but stays on the ANCHORS layer.
;;;
;;;   4. ORIENT - after the conversion the processed text is rotated
;;;              flat so it reads west -> east, right side up
;;;              (absolute angle 0).  Each text pivots about its own
;;;              insertion point - the labels share that point in
;;;              space with the POINT they belong to - so every label
;;;              stays anchored to its point.  Set
;;;              *tydrn-orient-angle* to nil to only flip upside-down
;;;              text instead ("Most readable").
;;;
;;; The ROMANC text style and the POINTS layer are created if they do
;;; not already exist.  Locked layers are unlocked for the duration of
;;; the command and re-locked afterwards.  The whole run is wrapped in
;;; a single undo group.
;;; ===================================================================

(setq *tydrn-version* "v1.1")   ; announced on load; release_lisp.py
                                   ; stamps the dated twin in releases/

(vl-load-com)

;; ---------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------
(setq *tydrn-text-style*  "ROMANC"
      *tydrn-text-font*   "romanc.shx"
      *tydrn-text-height* 4.5
      *tydrn-pool-layer*  "POOL"
      *tydrn-dest-layer*  "POINTS"
      *tydrn-anch-layer*  "ANCHORS"
      *tydrn-pink*        6           ; ACI 6 = magenta / pink
      *tydrn-orient-angle* 0.0)       ; absolute text angle in degrees
                                      ; (0 = read west->east, right
                                      ; side up); nil = only flip
                                      ; upside-down text ("Most
                                      ; readable")

;; ---------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------

;; Make sure the target text style exists.
(defun tydrn:ensure-style (name font)
  (if (null (tblsearch "STYLE" name))
    (entmake
      (list '(0 . "STYLE")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbTextStyleTableRecord")
            (cons 2 name)
            '(70 . 0)
            '(40 . 0.0)                ; height 0 = not fixed
            '(41 . 1.0)                ; width factor
            '(50 . 0.0)                ; oblique angle
            '(71 . 0)
            (cons 3 font)
            '(4 . ""))))
  (tblsearch "STYLE" name))

;; Make sure the target layer exists.
(defun tydrn:ensure-layer (name color)
  (if (null (tblsearch "LAYER" name))
    (entmake
      (list '(0 . "LAYER")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbLayerTableRecord")
            (cons 2 name)
            '(70 . 0)
            (cons 62 color)
            '(6 . "Continuous"))))
  (tblsearch "LAYER" name))

;; Unlock every layer in NAMES that is currently locked and return the
;; list of layer objects that were unlocked (so they can be re-locked).
(defun tydrn:unlock-layers (names doc / layers obj unlocked)
  (setq layers (vla-get-Layers doc))
  (foreach name names
    (if (and name (tblsearch "LAYER" name))
      (progn
        (setq obj (vla-Item layers name))
        (if (= :vlax-true (vla-get-Lock obj))
          (progn
            (vla-put-Lock obj :vlax-false)
            (setq unlocked (cons obj unlocked)))))))
  unlocked)

(defun tydrn:relock-layers (objs)
  (foreach obj objs (vla-put-Lock obj :vlax-true)))

;; Reset color / linetype / lineweight of a vla-object to BYLAYER.
(defun tydrn:force-bylayer (obj)
  (vla-put-Color obj acByLayer)
  (vla-put-Linetype obj "ByLayer")
  (vla-put-Lineweight obj acLnWtByLayer))

;; Rotate a text to the target orientation.  Setting the Rotation
;; property pivots the text about its insertion/alignment point; the
;; point labels share that point in space with the POINT entity they
;; belong to, so each label swings around its own point and stays
;; anchored to it.  With *tydrn-orient-angle* set, the text is turned
;; to that absolute angle; with it nil, only upside-down text (angle
;; in (90, 270] degrees) is flipped 180.
(defun tydrn:orient (obj / cur target)
  (setq cur (rem (vla-get-Rotation obj) (* 2.0 pi)))   ; radians
  (if (< cur 0.0) (setq cur (+ cur (* 2.0 pi))))
  (setq target
        (if *tydrn-orient-angle*
          (* pi (/ *tydrn-orient-angle* 180.0))
          (if (and (> cur (* 0.5 pi)) (<= cur (* 1.5 pi)))
            (rem (+ cur pi) (* 2.0 pi))
            cur)))
  (if (not (equal cur target 1e-8))
    (vla-put-Rotation obj target)))

;; Collect the distinct layer names used by the entities of a
;; selection set.
(defun tydrn:sel-layers (ss / i lay result)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq lay (cdr (assoc 8 (entget (ssname ss i)))))
        (if (not (member (strcase lay) result))
          (setq result (cons (strcase lay) result)))
        (setq i (1+ i)))))
  result)

;; ---------------------------------------------------------------
;; Error handler - restore locked layers and close the undo group
;; even if the user hits Esc or something fails mid-run.
;; ---------------------------------------------------------------
(defun tydrn:error (msg)
  (if *tydrn-unlocked* (tydrn:relock-layers *tydrn-unlocked*))
  (setq *tydrn-unlocked* nil)
  (if *tydrn-doc* (vla-EndUndoMark *tydrn-doc*))
  (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
    (princ (strcat "\nTYDRN error: " msg)))
  (if *tydrn-old-error* (setq *error* *tydrn-old-error*))
  (princ))

;; ---------------------------------------------------------------
;; Main command
;; ---------------------------------------------------------------
(defun C:TYDRN (/ ss-text ss-pool ss-anch i ent obj
                  n-text n-pool n-anch)

  (setq *tydrn-old-error* *error*
        *error*           tydrn:error
        *tydrn-doc*       (vla-get-ActiveDocument (vlax-get-acad-object))
        *tydrn-unlocked*  nil
        n-text 0  n-pool 0  n-anch 0)

  (vla-StartUndoMark *tydrn-doc*)

  ;; Make sure the style and destination layer are available.
  (tydrn:ensure-style *tydrn-text-style* *tydrn-text-font*)
  (tydrn:ensure-layer *tydrn-dest-layer* *tydrn-pink*)

  ;; ------------------------------------------------------------
  ;; 1. Text: highlighted selection, else prompt, Enter = all text
  ;; ------------------------------------------------------------
  (setq ss-text (ssget "_I" '((0 . "TEXT"))))
  (if (null ss-text)
    (progn
      (prompt "\nSelect text to update <Enter = all text in drawing>: ")
      (setq ss-text (ssget '((0 . "TEXT"))))
      (if (null ss-text)
        (setq ss-text (ssget "_X" '((0 . "TEXT")))))))

  ;; ------------------------------------------------------------
  ;; 2/3. Points on POOL and ANCHORS, anywhere in the drawing
  ;; ------------------------------------------------------------
  (setq ss-pool (ssget "_X" (list '(0 . "POINT") (cons 8 *tydrn-pool-layer*)))
        ss-anch (ssget "_X" (list '(0 . "POINT") (cons 8 *tydrn-anch-layer*))))

  ;; Unlock every layer we are about to touch.
  (setq *tydrn-unlocked*
        (tydrn:unlock-layers
          (append (list *tydrn-pool-layer*
                        *tydrn-anch-layer*
                        *tydrn-dest-layer*)
                  (tydrn:sel-layers ss-text))
          *tydrn-doc*))

  ;; Text -> ROMANC / 4.5 / BYLAYER
  (if ss-text
    (progn
      (setq i 0)
      (while (< i (sslength ss-text))
        (setq ent (ssname ss-text i)
              obj (vlax-ename->vla-object ent))
        (vla-put-StyleName obj *tydrn-text-style*)
        (vla-put-Height obj *tydrn-text-height*)
        (tydrn:force-bylayer obj)
        (setq n-text (1+ n-text)
              i      (1+ i)))))

  ;; POOL points -> POINTS layer, everything BYLAYER
  (if ss-pool
    (progn
      (setq i 0)
      (while (< i (sslength ss-pool))
        (setq obj (vlax-ename->vla-object (ssname ss-pool i)))
        (vla-put-Layer obj *tydrn-dest-layer*)
        (tydrn:force-bylayer obj)
        (setq n-pool (1+ n-pool)
              i      (1+ i)))))

  ;; ANCHORS points -> pink (ACI 6), same layer
  (if ss-anch
    (progn
      (setq i 0)
      (while (< i (sslength ss-anch))
        (setq obj (vlax-ename->vla-object (ssname ss-anch i)))
        (vla-put-Color obj *tydrn-pink*)
        (setq n-anch (1+ n-anch)
              i      (1+ i)))))

  ;; ------------------------------------------------------------
  ;; 4. Orient the converted text to read west -> east, right side
  ;;    up, each label pivoting about its insertion point (= the
  ;;    point it labels).
  ;; ------------------------------------------------------------
  (if ss-text
    (progn
      (setq i 0)
      (while (< i (sslength ss-text))
        (vl-catch-all-apply
          'tydrn:orient
          (list (vlax-ename->vla-object (ssname ss-text i))))
        (setq i (1+ i)))))

  ;; Re-lock whatever we unlocked and close the undo group.
  (tydrn:relock-layers *tydrn-unlocked*)
  (setq *tydrn-unlocked* nil)
  (vla-EndUndoMark *tydrn-doc*)
  (setq *error* *tydrn-old-error*)

  (princ (strcat "\nTYDRN done: "
                 (itoa n-text) " text -> " *tydrn-text-style*
                 " h" (rtos *tydrn-text-height* 2 2)
                 " oriented W->E, "
                 (itoa n-pool) " point(s) POOL -> " *tydrn-dest-layer*
                 ", "
                 (itoa n-anch) " ANCHORS point(s) -> pink."))
  (princ))

;;; ===================================================================
;;; TYLERDRONESUITE - the drone trace, start to finish
;;; -------------------------------------------------------------------
;;; TYDRN, then PADDLE, then AUTODIM, in that order because that is the
;;; order the work has to happen in: the points have to be on the right
;;; layer before PADDLE can find the perimeter features to pad, and the
;;; pads have to be in before AUTODIM dimensions what is there.
;;;
;;; Nothing is skipped or reworded - each stage is the command itself,
;;; asking its own questions, so anything learned about TYDRN, PADDLE
;;; or AUTODIM stays true here.  The suite only supplies the order.
;;;
;;; EACH STAGE KEEPS ITS OWN UNDO GROUP, so three U's back the suite
;;; out, one per stage.  That is deliberate, and it is XYPLOT's
;;; reasoning about its ABHD handoff: a stage that went well should not
;;; have to be undone to get at one that did not.
;;;
;;; Esc in any stage stops the suite there - an AutoLISP error unwinds
;;; to the command line, so the stages after it never start.  What ran
;;; before it stays run, which is why the check below happens first.
;;; ===================================================================

(setq *tydrn-suite* '("TYDRN" "PADDLE" "AUTODIM"))

;; Is C:<name> defined in this session?  (XYPLOT's boundp test, with
;; the name computed rather than quoted.)
(defun tydrn:has (name)
  (boundp (read (strcat "c:" name))))

;; "PADDLE and AUTODIM" -- the way the refusal names what is missing.
(defun tydrn:namelist (names / out n i nm)
  (setq out "" n (length names) i 0)
  (foreach nm names
    (setq out (strcat out
                      (cond ((= i 0) "")
                            ((= i (1- n)) (if (= n 2) " and " ", and "))
                            (t ", "))
                      nm)
          i   (1+ i)))
  out)

(defun c:TYLERDRONESUITE ( / missing nm step)
  ;; Every stage is checked BEFORE any of them runs.  Half a suite is
  ;; worse than none: TYDRN would have moved the points and PADDLE
  ;; dropped the pads, and the operator would find out only at the end
  ;; that the dimensioning they ran this for was never going to happen.
  (setq missing nil)
  (foreach nm *tydrn-suite*
    (if (not (tydrn:has nm)) (setq missing (cons nm missing))))
  (setq missing (reverse missing))
  (if missing
    (progn
      (princ (strcat "\nTYLERDRONESUITE needs " (tydrn:namelist missing)
                     ", which " (if (= 1 (length missing)) "is" "are")
                     " not loaded here."))
      (princ "\n  APPLOAD the missing file - or LAZPASS.lsp, which is the")
      (princ "\n  whole build in one - and run it again.  Nothing has been")
      (princ "\n  changed."))
    (progn
      (princ "\nTYLERDRONESUITE: TYDRN, then PADDLE, then AUTODIM.")
      (princ "\n  Each stage is its own undo group, so a stage that went")
      (princ "\n  well is not undone to get at one that did not.  Esc in")
      (princ "\n  any stage stops the suite there.")
      (setq step 0)
      (foreach nm *tydrn-suite*
        (setq step (1+ step))
        (princ (strcat "\n\n--- " (itoa step) " of "
                       (itoa (length *tydrn-suite*)) ": " nm " ---"))
        ;; through the command line, not as a direct call, so each stage
        ;; prompts and errors exactly as it does when it is typed
        (vl-cmdf (strcat "_." nm)))
      (princ "\n\nTYLERDRONESUITE done - all three stages ran.")))
  (princ))

(princ (strcat "\nTYDRN.LSP " *tydrn-version*
               " loaded.  Type TYDRN to run, or TYLERDRONESUITE"
               " for TYDRN + PADDLE + AUTODIM."))
(princ)

;;; ======================================================================
;;; >>> lisp/lazpanel/LAZPANEL.lsp
;;; ======================================================================

;;; ======================================================================
;;; LAZPANEL.lsp  --  clickable button panel that launches the calofin tools
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZPANEL       open the panel
;;;            LAZBUTTON      put the screen-button toolbars up
;;;            LAZICON        report where the button picture came from
;;;            LAZPIN         choose the pinned tools
;;;            LAZPANELVER    print the loaded version
;;;
;;; Every headline calofin routine as a button, on tabbed pages of two
;;; kinds.  Four JOB pages -- Pool, Cover, Spa, Rest -- hold what you
;;; reach for while doing that job, in columns that follow the work:
;;; lay the shape out, tie the points, build the steps, dimension and
;;; check.  Four CATEGORY pages -- Layout, Points, Dimensions, Checking,
;;; the same four names the VB.NET palette in ui/calofin_net uses --
;;; hold the whole roster filed by what each tool IS.  A tool that
;;; serves two jobs is on both, so there are more buttons than commands.
;;; Clicking a button closes the panel and runs the command exactly as
;;; if its name had been typed -- the panel adds nothing in front of a
;;; tool and nothing behind it.  (The Cover page names the cover twins,
;;; POOLCOVER and friends, which is not the panel meddling: they are
;;; commands of their own and do the same thing typed.)
;;;
;;; ZERO INSTALL.  The dialog is plain DCL, and this file writes its own
;;; .dcl into the system temp folder each time the panel opens, so there
;;; is no second file to ship, no support-path entry to add and no DLL
;;; to NETLOAD.  APPLOAD this one file (or LAZPASS.lsp, which carries
;;; it), type LAZPANEL, click.
;;;
;;; THE SCREEN BUTTON.  Loading this file also puts a one-button
;;; toolbar named "LazPanel" on screen, so the panel can live as a
;;; clickable button you drag anywhere or dock, like any toolbar.  It
;;; is created through the ActiveX menu API when no toolbar of that
;;; name exists yet -- no CUI file to install -- and its icon (an
;;; orange hexagon, point to the north) is generated as two .bmp files under
;;; TEMPPREFIX and re-applied on every load, because SetBitmaps stores
;;; the path rather than the picture.  Clicking it runs LAZPANEL.  If
;;; the toolbar gets closed or lost, LAZBUTTON brings it back.  When
;;; any of this is unavailable (no COM, locked CUI, unwritable temp
;;; folder) the button is quietly skipped and the panel is untouched.
;;;
;;; The icon goes out through an ADODB.Stream in binary mode, not
;;; through write-char: AutoLISP writes text-mode files and has no NUL
;;; in its character model at all -- (chr 0) is the empty string --
;;; while a 24-bit BMP header is full of NULs before a single pixel is
;;; reached.  No arrangement of this format could be written with the
;;; language's own file output.  COM is no new dependency here: the
;;; toolbar the icon goes on is made through the same ActiveX API.
;;;
;;; A button whose command is not loaded in this session is greyed out
;;; rather than left to fail -- the same availability probe the VB
;;; palette uses (read the name, evaluate it: an unbound C: symbol is
;;; nil).  The status line across the top says how many tools the
;;; session has.
;;;
;;; DCL dialogs are modal, so the panel cannot stay open while a tool
;;; runs the way a docked palette can -- but it no longer has to be
;;; reopened by hand: click, the panel closes, the tool runs to its own
;;; end, and the panel COMES BACK on the page and at the screen position
;;; it was at.  Close is the way out, and is the default button.  A
;;; PINNED row on every page carries the handful of tools you actually
;;; run all day, remembered between sessions; Pin... or LAZPIN edits it.
;;;
;;; The *SCAN companions are on the panel;
;;; satellites reachable from their headline tool (TUTORIAL*
;;; walkthroughs, *VER reporters, *RESCUE undo companions, -CFG /
;;; -SETUP partners) stay off on purpose, and so does the DD*
;;; drone-height toolset -- eight specialist photo-EXIF commands that
;;; are not part of the drafting flow the panel serves.
;;; tests/test_lazpanel.py pins the roster to the commands actually
;;; defined under lisp/, so a new tool without a button fails the suite
;;; instead of being quietly missing.
;;; ======================================================================

(vl-load-com)

(setq *lazpanel-version* "v3.4")

;;; -------------------- the roster --------------------------------------
;;  Two tables: lzp:*captions* names every command once, and
;;  lzp:*groups* lays the pages out in columns of those names.  The
;;  rules for what belongs on the panel at all:
;;    - every headline drafting command under lisp/ gets a button;
;;    - satellites do not: TUTORIAL* walkthroughs, *VER reporters,
;;      *RESCUE undo companions, -CFG / -SETUP partners, DCE (alias of
;;      DIMCONTEND) and STOCKLIST (STOCKCOVER's listing companion);
;;    - the DD* drone-height toolset stays off as a whole: eight
;;      specialist photo-EXIF commands, not part of the drafting flow;
;;    - LISPLAB never appears: it is held back from the shared build as
;;      OMITTED (see cal:*held-back* in CALOFIN-LOADER.lsp);
;;    - the deprecated acady matcher (MATCHSTD, ACADY-*) never appears.
;;  tests/test_lazpanel.py enforces all five rules against the tree.

;;  TWO KINDS OF TAB, and a command may sit on several.
;;
;;  The first four pages are JOBS -- what the drafter is actually doing
;;  this hour: a pool, a cover, a spa, and everything those three do not
;;  reach.  They run in the order the work runs: lay the shape out, tie
;;  the points, build the steps, then dimension and check.  A command
;;  that serves two jobs appears on both; AUTODIM and DIMCHECK are on
;;  all three, because every job ends the same way.  The last four are
;;  the CATEGORIES the panel has always had -- the whole roster filed by
;;  what each tool is rather than when you reach for it -- so a tool you
;;  cannot place in a job is still one tab away.
;;
;;  Every command therefore appears at least twice: once on a job page
;;  and once on a category page.  Keys are only required to be unique
;;  within a page, and each page is its own dialog, so this is free --
;;  but lzp:commands has to fold the repeats or the status line would
;;  count the roster twice over.
;;
;;  The job pages are laid out in COLUMNS, which is the other half of
;;  the same idea: a job is not a flat list of two dozen tools, it is
;;  four short lists in the order you reach for them.
;;
;;  "Rest" is not a hand-kept list: it is every command the Pool, Cover
;;  and Spa pages do not name, and the test recomputes that complement
;;  from the tree, so a tool added to the panel lands there by default
;;  instead of falling off the job pages unnoticed.
;;
;;  THE AB CHECKS LIVE IN "Rest" AND NOWHERE ELSE among the jobs.
;;  ABCURCHECK and its scan read the A/B survey ties themselves -- the
;;  tape rather than the pool -- so they are bench work over the
;;  numbers, not a step in laying out a pool, a cover or a spa.  Any
;;  further AB* check joins them on Rest and stays off the other three
;;  job pages; test_lazpanel.py enforces that against the tree, so a
;;  new one dropped onto Pool out of habit fails the suite instead of
;;  quietly widening a job page.  The Checking CATEGORY page still
;;  carries them: that page answers "what is this tool", which is a
;;  different question from "what am I doing this hour".

;;  ONE CAPTION PER COMMAND, here and nowhere else.  A command appears
;;  on several pages, so a caption kept beside each button would be the
;;  same words written two or three times -- and would drift the first
;;  time one copy was edited.  This is the only place they live.
(setq lzp:*captions*
  '(
    ("ABCDEF"           "Rectangle plot")
    ("ABCURCHECK"       "Perimeter continuity")
    ("ABCURCHECKSCAN"   "Perimeter continuity, no marks")
    ("ABFIND"           "A/B stake ties")
    ("ABHD"             "Survey perimeter + bottom")
    ("ABHDCOVER"        "Survey perimeter, no bottom")
    ("ABMOVE"           "Move mis-taped point")
    ("ADAB"             "Organic shape points")
    ("ALTABCDEF"        "Clockwise rectangle plot")
    ("AUTOBEAD"         "Bead offsets")
    ("AUTODIM"          "Auto dimension")
    ("AUTODIMSIDEPOV"   "Side-view dims")
    ("BPCALLOUT"        "Bad point callout")
    ("CABHD"            "Perimeter-only fit")
    ("CCPRECHECK"       "Tech flow chart")
    ("CDCALLOUT"        "Point-to-point cross dims")
    ("CDCREATE"         "Lines to cross dims")
    ("CHECK"            "Drawing check")
    ("CONSTELLATION"    "Points from cross dims")
    ("CORNERSTP"        "Corner step")
    ("COVERCHECK"       "Cover review")
    ("COVERSCAN"        "Cover scan")
    ("CPERPPTS"         "Curved perp points")
    ("CUSTBLOCK"        "Block from L/W/H")
    ("DIMARCCHECK"      "Arc endpoint check")
    ("DIMCHECK"         "Dimension review")
    ("DIMCONTEND"       "Continue dim chains")
    ("DIMSCAN"          "Dimension scan")
    ("DRONE"            "Drone cleanup")
    ("FITABHD"          "Typed template fit")
    ("FITABHDCOVER"     "Typed template fit, no bottom")
    ("FLOORDIM"         "Floor dims")
    ("HEMISTEP"         "Hemi step")
    ("LAZFORM"          "Pool from a filled-in chart")
    ("LAZTXT"           "The same form, drawn in tiles")
    ("LAZFORMCOVER"     "Chart to pool, no bottom")
    ("LAZSPA"           "Spa from a filled-in chart")
    ("LAZSTEP"          "Steps from a filled-in drawing")
    ("LHD"              "Laser outline fit")
    ("LINCHECK"         "Line checklist")
    ("LINFINCHECK"      "Liner finish review")
    ("LINFINSCAN"       "Liner finish scan")
    ("LINTXTCHK"        "Liner checklist text")
    ("LITECOVERSCAN"    "Cover scan, no dims")
    ("LITELINFINSCAN"   "Liner scan, no dims")
    ("LITESPACHECKSCAN" "Spa scan, no dims")
    ("NORMIESTEP"       "Normie step")
    ("OASIS"            "Freeform pool")
    ("PADDLE"           "Paddle pads")
    ("PERPPTS"          "Perpendicular points")
    ("POOL"             "Pool layout")
    ("POOLCOVER"        "Pool layout, no bottom")
    ("POOLDEMO"         "Worked pool example")
    ("SMARTFILLET"      "Corner radius, previewed")
    ("SPA"              "Spa template")
    ("SPACHECK"         "Spa sheet review")
    ("SPACHECKSCAN"     "Spa sheet scan")
    ("STAIRDIM"         "Stair dims")
    ("STOCKCOVER"       "Stock cover placement")
    ("TYDRN"            "Text + point tidy-up")
    ("TYLERDRONESUITE"  "Drone suite: tidy, pad, dim")
    ("WCALST"           "Unroll curved band")
    ("XFTCONV"          "Leica import cleanup")
    ("XYPLOT"           "X/Y offset plot")
   ))

(defun lzp:caption (name / p)
  (if (setq p (assoc name lzp:*captions*)) (cadr p) ""))

;;  THE PAGES, AS COLUMNS.  Each page is (title (heading cmd ...) ...) --
;;  one entry per COLUMN, laid out side by side across the page.  The
;;  job pages break their tools into the columns the work falls into:
;;  lay the shape out, tie the points, build the steps, dimension and
;;  check.  That is the grouping the drafter already carries; the
;;  columns just stop it being a single list of twenty-four.
;;
;;  A column heading of "" means the page is one plain column -- what
;;  the four category pages are.
;;
;;  WHY A MULTI-COLUMN PAGE SHOWS THE NAME ALONE.  A button reading
;;  "CDCALLOUT  -  Point-to-point cross dims" is about 39 cells wide;
;;  four of those side by side is 147, and DCL will not scroll a dialog
;;  wider than the screen -- the dialog simply fails to open.  So the
;;  columns carry the meaning in their headings and the buttons carry
;;  the command name, which puts the widest page at about 64 cells.
;;  Single-column pages have the room, and keep the caption on the
;;  button: the category pages stay the place to go to find out what a
;;  tool is, and the job pages are the place to go when you know.
(setq lzp:*groups*
  '(("Pool"
     ("Shape"
      "POOL"
      "LAZFORM"
      "LAZTXT"
      "OASIS"
      "ABHD"
      "ADAB"
      "FITABHD"
      "XFTCONV"
      )
     ("Points"
      "ABFIND"
      "ABMOVE"
      "CDCREATE"
      "CDCALLOUT"
      "BPCALLOUT"
      )
     ("Steps"
      "LAZSTEP"
      "CORNERSTP"
      "HEMISTEP"
      "NORMIESTEP"
      "AUTOBEAD"
      "PERPPTS"
      "CPERPPTS"
      )
     ("Dims & check"
      "AUTODIM"
      "LINFINCHECK"
      "LINFINSCAN"
      "LITELINFINSCAN"
      "DIMCHECK"
      "DIMSCAN"
      )
    )
     ("Cover"
     ("Shape"
      "POOLCOVER"
      "LAZFORMCOVER"
      "OASIS"
      "ABHDCOVER"
      "FITABHDCOVER"
      "STOCKCOVER"
      "CUSTBLOCK"
      "XFTCONV"
      )
     ("Points"
      "ABFIND"
      "ABMOVE"
      "CDCREATE"
      "CDCALLOUT"
      "BPCALLOUT"
      )
     ("Pads, dims & check"
      "PADDLE"
      "AUTODIM"
      "COVERCHECK"
      "COVERSCAN"
      "LITECOVERSCAN"
      "DIMCHECK"
      "DIMSCAN"
      )
    )
     ("Spa"
     (""
      "SPA"
      "LAZSPA"
      "CUSTBLOCK"
      "AUTODIM"
      "SPACHECK"
      "SPACHECKSCAN"
      "LITESPACHECKSCAN"
      "DIMCHECK"
      "DIMSCAN"
      )
    )
     ("Rest"
     (""
      "POOLDEMO"
      "CABHD"
      "LHD"
      "SMARTFILLET"
      "WCALST"
      "ABCDEF"
      "ALTABCDEF"
      "XYPLOT"
      "CONSTELLATION"
      "DRONE"
      "TYDRN"
      "TYLERDRONESUITE"
      "AUTODIMSIDEPOV"
      "STAIRDIM"
      "FLOORDIM"
      "DIMCONTEND"
      "CHECK"
      "DIMARCCHECK"
      "ABCURCHECK"
      "ABCURCHECKSCAN"
      "LINCHECK"
      "LINTXTCHK"
      "CCPRECHECK"
      )
    )
     ("Layout"
     (""
      "LAZFORM"
      "LAZTXT"
      "LAZFORMCOVER"
      "LAZSPA"
      "SPA"
      "POOL"
      "POOLCOVER"
      "POOLDEMO"
      "OASIS"
      "FITABHD"
      "FITABHDCOVER"
      "ABHD"
      "ABHDCOVER"
      "ADAB"
      "CABHD"
      "LHD"
      "PADDLE"
      "AUTOBEAD"
      "LAZSTEP"
      "CORNERSTP"
      "HEMISTEP"
      "NORMIESTEP"
      "SMARTFILLET"
      "STOCKCOVER"
      "WCALST"
      "CUSTBLOCK"
      )
    )
     ("Points"
     (""
      "ABCDEF"
      "ALTABCDEF"
      "XYPLOT"
      "CONSTELLATION"
      "ABFIND"
      "ABMOVE"
      "PERPPTS"
      "CPERPPTS"
      "XFTCONV"
      "DRONE"
      "TYDRN"
      "TYLERDRONESUITE"
      )
    )
     ("Dimensions"
     (""
      "AUTODIM"
      "AUTODIMSIDEPOV"
      "STAIRDIM"
      "FLOORDIM"
      "DIMCONTEND"
      "CDCREATE"
      "CDCALLOUT"
      "BPCALLOUT"
      )
    )
     ("Checking"
     (""
      "CHECK"
      "DIMARCCHECK"
      "DIMCHECK"
      "DIMSCAN"
      "ABCURCHECK"
      "ABCURCHECKSCAN"
      "LINCHECK"
      "LINFINCHECK"
      "LINFINSCAN"
      "LITELINFINSCAN"
      "COVERCHECK"
      "COVERSCAN"
      "LITECOVERSCAN"
      "SPACHECK"
      "SPACHECKSCAN"
      "LITESPACHECKSCAN"
      "LINTXTCHK"
      "CCPRECHECK"
      )
    )))

;; How the tab strip is laid out: one DCL row per entry, in this order.
;; The jobs sit on one line and the categories on the next, which is
;; both what they mean and what keeps the strip narrow -- eight tabs on
;; a single row run about 94 character cells, and DCL will not scroll a
;; dialog that is wider than the screen.  This is presentation only; the
;; pages themselves are still lzp:*groups*.  The test asserts the two
;; tables name exactly the same groups, so neither can drift.
(setq lzp:*rows*
  '(("Job"            "Pool" "Cover" "Spa" "Rest")
    ("Or by category" "Layout" "Points" "Dimensions" "Checking")))

(setq lzp:*pick* nil)             ; the button clicked on the last run
(setq lzp:*tbname* "LazPanel")    ; the panel's screen-button toolbar
(setq lzp:*tbsuite* "TylerDroneSuite")  ; and the suite's own

;; Whether TYLERDRONESUITE gets a screen button of its own.
;;
;;   AUTO  (the default) yes when the drone lisp was loaded ON ITS OWN,
;;         no when it arrived inside LAZPASS
;;   T     always      nil  never
;;
;; Set these AFTER the file has loaded and run LAZBUTTON -- not before.
;; The load sets each of them itself, so a value put in place first is
;; overwritten before it is ever read.  (editions/TYLERDRONE.lsp sets
;; them in its footer, which is after, and states BOTH outright rather
;; than leaving one to AUTO: AUTO reads a flag another build may have
;; left standing, which is exactly how that edition once put up no
;; button at all.)
;;
;; The distinction is the point.  A drawer who was handed tydrn.lsp by
;; itself has no panel to reach the suite through, so the button IS the
;; surface.  Inside LAZPASS the panel is already on screen and carries
;; the suite like every other tool, so a second toolbar is one more
;; thing on the strip earning nothing -- the whole build should put up
;; ONE external button, and that button is the panel's.
(setq lzp:*suitebutton* 'AUTO)

;; And whether the PANEL gets one.  Almost always yes -- being on screen
;; is the panel's whole reason for being.  The exception is a build put
;; together around ONE tool, where the panel is along for the ride and
;; its button would be the odd one out: editions/TYLERDRONE.lsp sets
;; this nil so the only thing on the strip is the drone button.
;; LAZPANEL still types the same as ever; it is just not on the strip.
(setq lzp:*panelbutton* T)

;; Draw the button at 32 pixels rather than 16.  The small one is easy
;; to miss on a crowded screen, and both pictures are already written
;; -- AutoCAD simply picks the 16 unless it is told otherwise.
;;
;; Read this before changing it: AutoCAD's large-button setting is not
;; per toolbar.  Asking for it here turns it on for EVERY toolbar in
;; the session, which is the same switch as Options > Display > "Use
;; large buttons for Toolbars".  That is why it is a tunable and why
;; LAZBUTTON says what it did: setq it nil and run LAZBUTTON to put the
;; setting back and return every toolbar to small buttons.
(setq lzp:*bigbutton* T)
(setq lzp:*iconerr* nil)          ; why the last icon write failed
(setq lzp:*pos* nil)              ; where the panel was last standing
(setq lzp:*go* nil)               ; the group a tab click asked for
(setq lzp:*icontype* nil)         ; which byte-array spelling worked
(setq lzp:*iconstep* nil)         ; the COM call the icon write died on
(setq lzp:*msxmlwhy* nil)         ; what each MSXML ProgID said, newest first
(setq lzp:*iconroute* nil)        ; which route actually wrote the file
(setq lzp:*icondir* nil)          ; the folder the icons landed in
(setq lzp:*iconref* nil)          ; "name" on the support path, else "path"
(setq lzp:*page* nil)             ; the page the panel reopens on
(setq lzp:*pins* nil)             ; the pinned tools, in pin order
(setq lzp:*pinkey* "HKEY_CURRENT_USER\\Software\\Calofin\\LazPanel")

;;; -------------------- roster access -----------------------------------

;; One page's commands, flattened out of its columns, in display order:
;; down the first column, then down the second.
(defun lzp:group-commands (name / g col c out)
  (foreach g lzp:*groups*
    (if (= (car g) name)
        (foreach col (cdr g)
          (foreach c (cdr col) (setq out (cons c out))))))
  (reverse out))

;; A page's columns: (heading cmd ...) each.
(defun lzp:group-columns (name / g out)
  (foreach g lzp:*groups*
    (if (= (car g) name) (setq out (cdr g))))
  out)

;; Folded, because a command that serves two jobs is listed on both
;; pages and the status line counts tools, not buttons.  First
;; appearance wins, so the order still reads as the panel is laid out.
(defun lzp:commands ( / g col c out)
  (foreach g lzp:*groups*
    (foreach col (cdr g)
      (foreach c (cdr col)
        (if (not (member c out))
          (setq out (cons c out))))))
  (reverse out))

;; Is C:<name> defined in this session?  An unbound symbol evaluates to
;; nil in AutoLISP, so reading the name and evaluating it is enough --
;; and it stays correct for commands loaded after this file was.
(defun lzp:has (name)
  (if (eval (read (strcat "C:" name))) t nil))

;; The subset of the roster that is loaded right now.
(defun lzp:loaded ( / n out)
  (foreach n (lzp:commands)
    (if (lzp:has n)
      (setq out (cons n out))))
  (reverse out))

;;; -------------------- the dialog --------------------------------------
;;  The DCL is built here as a list of lines and written to a temp file
;;  when the panel opens, so the whole panel travels inside this one
;;  .lsp.  Keys are the command names themselves; boxed columns carry
;;  the group labels.

(defun lzp:dlgname (group) (strcat "lazpanel_" (strcase group t)))

;; The tab strip: one button per group, laid out in the rows of
;; lzp:*rows* -- jobs on the first line, categories on the second.  DCL
;; has no tab tile, so a tab is a button that closes this page and
;; reopens the next -- and since done_dialog reports where the dialog
;; was standing, it reopens there rather than jumping back to the middle
;; of the screen.
(defun lzp:tabstrip ( / out r g)
  (foreach r lzp:*rows*
    (setq out (cons "  : boxed_row {" out))
    (setq out (cons (strcat "    label = \"" (car r) "\";") out))
    (foreach g (cdr r)
      (setq out (cons (strcat "    : button { key = \"tab_" g
                              "\"; label = \"" g "\"; }")
                      out)))
    (setq out (cons "  }" out)))
  (reverse out))

;;; -------------------- the pinned row ----------------------------------
;;  Pins are the answer to "I run four of these fifty-six all day": the
;;  tools you tick sit on EVERY page, in the order you pinned them, so
;;  the ones you actually use stop being three tabs apart.
;;
;;  A pinned button carries a "pin_" key so it cannot collide with the
;;  same tool's own button further down the page, and it is greyed by
;;  the same availability probe.
;;
;;  WIDTH.  The pinned row is generated DCL like everything else, and a
;;  handful of long names abreast -- LITESPACHECKSCAN is sixteen
;;  characters -- would push the dialog past the width DCL refuses to
;;  scroll, which does not clip the page, it stops it opening at all.
;;  So pins are packed greedily into as many rows as they need, with
;;  the Pin... button packed last like any other item.  Pin thirty
;;  tools and you get a tall panel, never a broken one.
(setq lzp:*pinbudget* 84)

(defun lzp:pin-label (n) (strcat "    : button { label = \"" n
                                 "\"; key = \"pin_" n "\"; }"))

;; (name width) for every pinned tool, then the editor button last.
(defun lzp:pin-items ( / out n)
  (foreach n lzp:*pins* (setq out (cons n out)))
  (reverse (cons "*edit*" out)))

(defun lzp:pinrows ( / out row w n cw items)
  (setq items (lzp:pin-items) row nil w 0)
  (foreach n items
    (setq cw (+ (strlen (if (= n "*edit*") "Pin..." n)) 6))
    (if (and row (> (+ w cw) lzp:*pinbudget*))
      (setq out (cons (reverse row) out) row nil w 0))
    (setq row (cons n row) w (+ w cw)))
  (if row (setq out (cons (reverse row) out)))
  (reverse out))

(defun lzp:pinrow ( / out rows r n first)
  (setq rows (lzp:pinrows) first t)
  (foreach r rows
    (setq out (cons "  : boxed_row {" out))
    ;; only the first row is labelled: two boxes both saying "Pinned"
    ;; would read as two different things
    (setq out (cons (strcat "    label = \""
                            (if first "Pinned" "") "\";") out))
    (foreach n r
      (setq out
        (cons (if (= n "*edit*")
                "    : button { label = \"Pin...\"; key = \"pin_edit\"; }"
                (lzp:pin-label n))
              out)))
    (if (and first (not lzp:*pins*))
      (setq out (cons "    : text { label = \"nothing pinned yet\"; }" out)))
    (setq out (cons "  }" out))
    (setq first nil))
  (reverse out))

;; One page per group.  The whole roster is still one list -- the pages
;; are lzp:*groups* itself, so re-ordering or re-grouping the tools is
;; an edit to that table and nothing else.
(defun lzp:dcl-one (g / out c col)
  ;; consed newest-first and reversed at the end, so this seed list
  ;; reads BACKWARDS: the dialog line last here comes out first
  (setq out (list (strcat "  : text { key = \"status\"; width = 60; "
                          "alignment = centered; }")
                  (strcat "  label = \"LazPanel " *lazpanel-version*
                          "  -  " (car g) "\";")
                  (strcat (lzp:dlgname (car g)) " : dialog {")))
  (setq out (append (reverse (lzp:tabstrip)) out))
  (setq out (append (reverse (lzp:pinrow)) out))
  (cond
    ;; ONE COLUMN: the page has the width to spare, so every button
    ;; carries its caption -- this is what the category pages are for.
    ((= (length (cdr g)) 1)
     (setq out (cons "  : boxed_column {" out))
     (setq out (cons (strcat "    label = \"" (car g) "\";") out))
     (foreach c (cdr (car (cdr g)))
       (setq out (cons (strcat "    : button { label = \"" c "  -  "
                               (lzp:caption c) "\"; key = \"" c "\"; }")
                       out)))
     (setq out (cons "  }" out)))
    ;; SEVERAL COLUMNS, side by side: the heading says what the column
    ;; is for and the buttons carry the command name alone.  Four
    ;; captioned buttons abreast would be about 147 cells wide and the
    ;; dialog would not open at all.
    (t
     (setq out (cons "  : boxed_row {" out))
     (setq out (cons (strcat "    label = \"" (car g) "\";") out))
     (foreach col (cdr g)
       (setq out (cons "    : boxed_column {" out))
       (setq out (cons (strcat "      label = \"" (car col) "\";") out))
       (foreach c (cdr col)
         (setq out (cons (strcat "      : button { label = \"" c
                                 "\"; key = \"" c "\"; }")
                         out)))
       (setq out (cons "    }" out)))
     (setq out (cons "  }" out))))
  (setq out (cons "  spacer;" out))
  (setq out (cons (strcat "  : button { label = \"Close\"; key = \"cancel\"; "
                          "is_default = true; is_cancel = true; "
                          "fixed_width = true; alignment = centered; }")
                  out))
  (reverse (cons "}" out)))

;; The pin editor: every tool on the panel as a toggle, in three
;; columns so fifty-six of them fit on a screen rather than a scroll
;; DCL would not give.
(defun lzp:dcl-pins ( / out cmds n per i j c)
  (setq cmds (lzp:commands)
        n    (length cmds)
        per  (1+ (/ (1- n) 3))
        i    0)
  (setq out (list "lazpanel_pins : dialog {"
                  "  label = \"LazPanel  -  pinned tools\";"
                  (strcat "  : text { label = \"Ticked tools sit in the "
                          "Pinned row on every page.\"; }")
                  "  : row {"))
  (while (< i n)
    (setq out (append out (list "    : column {")) j 0)
    (while (and (< j per) (< i n))
      (setq c (nth i cmds))
      (setq out (append out
        (list (strcat "      : toggle { label = \"" c
                      "\"; key = \"tg_" c "\"; }"))))
      (setq i (1+ i) j (1+ j)))
    (setq out (append out (list "    }"))))
  (append out
    (list "  }" "  spacer;"
          (strcat "  : row { alignment = centered; "
                  ": button { label = \"OK\"; key = \"accept\"; "
                  "is_default = true; fixed_width = true; } "
                  ": button { label = \"Cancel\"; key = \"cancel\"; "
                  "is_cancel = true; fixed_width = true; } }")
          "}")))

;; Every page, then the pin editor, in one generated file.
(defun lzp:dcl-lines ( / out g)
  (foreach g lzp:*groups*
    (setq out (append out (lzp:dcl-one g) (list ""))))
  (append out (lzp:dcl-pins) (list "")))

;; The write loop, alone so it can run under vl-catch-all-apply: if a
;; write dies half way (disk full, quota) the handle still gets closed
;; and the partial file deleted instead of being handed to load_dialog.
(defun lzp:write-lines (fh / l)
  (foreach l (lzp:dcl-lines)
    (write-line l fh)))

;; Write the dialog into the system temp folder; the path comes back,
;; or nil when the folder cannot be written to.
(defun lzp:write-dcl ( / f fh err)
  (setq f (vl-filename-mktemp "lazpanel" nil ".dcl"))
  (if (and f (setq fh (open f "w")))
    (progn
      (setq err (vl-catch-all-apply 'lzp:write-lines (list fh)))
      (close fh)
      (cond
        ((vl-catch-all-error-p err)
         (vl-file-delete f)
         nil)
        (t f)))))

;; Run a roster command by name, exactly as if it had been typed.  The
;; probe guards the greyed-button race: a command that vanished between
;; opening the panel and clicking reports itself instead of erroring.
(defun lzp:split (s sep / i n c cur out)
  (setq i 1 n (strlen s) cur "")
  (while (<= i n)
    (setq c (substr s i 1))
    (if (= c sep)
      (progn (if (/= cur "") (setq out (cons cur out))) (setq cur ""))
      (setq cur (strcat cur c)))
    (setq i (1+ i)))
  (if (/= cur "") (setq out (cons cur out)))
  (reverse out))

;; Read the pins back, dropping any name no longer on the roster: a pin
;; left over from an older build must not put a dead button on screen,
;; and the roster is the only thing that says what is real.
(defun lzp:pins-read ( / s)
  (setq s (vl-catch-all-apply 'vl-registry-read (list lzp:*pinkey* "Pins")))
  (setq lzp:*pins*
    (if (and (not (vl-catch-all-error-p s)) (= (type s) 'STR) (/= s ""))
      (vl-remove-if-not '(lambda (n) (member n (lzp:commands)))
                        (lzp:split s ";"))))
  lzp:*pins*)

(defun lzp:pins-write ( / s n)
  (setq s "")
  (foreach n lzp:*pins*
    (setq s (strcat s (if (= s "") "" ";") n)))
  (vl-catch-all-apply 'vl-registry-write (list lzp:*pinkey* "Pins" s))
  lzp:*pins*)

;; Pin order is click order: a newly ticked tool goes on the END rather
;; than jumping into the middle of a row the hand has already learned.
(defun lzp:pin-toggle (name val)
  (if (= val "1")
    (if (not (member name lzp:*pins*))
      (setq lzp:*pins* (append lzp:*pins* (list name))))
    (setq lzp:*pins* (vl-remove name lzp:*pins*)))
  (princ))

;; The toggle dialog.  Cancel re-reads the registry rather than trying
;; to undo the ticks one by one -- the stored list is the truth, so
;; going back to it is exact where unwinding would be approximate.
(defun lzp:pin-edit (dcl / n rc)
  (cond
    ((not (new_dialog "lazpanel_pins" dcl)) nil)
    (t
     (foreach n (lzp:commands)
       (set_tile (strcat "tg_" n) (if (member n lzp:*pins*) "1" "0"))
       (action_tile (strcat "tg_" n)
                    (strcat "(lzp:pin-toggle \"" n "\" $value)")))
     (action_tile "accept" "(done_dialog 1)")
     (action_tile "cancel" "(done_dialog 0)")
     (setq rc (start_dialog))
     (if (= rc 1) (lzp:pins-write) (lzp:pins-read))
     t)))

(defun lzp:launch (name / fn)
  (setq fn (read (strcat "C:" name)))
  (cond
    ((eval fn)
     (princ (strcat "\nLAZPANEL: running " name
                    " -- LAZPANEL reopens the panel."))
     (eval (list fn)))
    (t
     (princ (strcat "\nLAZPANEL: " name
                    " is not loaded in this session.")))))

;;; -------------------- the screen button -------------------------------
;;  A one-button toolbar so the panel can sit on screen like any other
;;  toolbar button -- drag it anywhere, dock it, click it to open the
;;  panel.  Created through the ActiveX menu API, so there is no CUI
;;  file to install; the icon is an orange hexagon, point north.
;;
;;  Everything here is best effort by design.  A session without COM,
;;  with a locked CUI or an unwritable temp folder loses the button and
;;  keeps the panel -- which is why the load-time call sits inside
;;  vl-catch-all-apply and why nothing below reports its own failure.

;; The mark: a hexagon with a corner facing north.  Each size is
;; drawn at its own resolution rather than the small one doubled --
;; a hexagon doubled from 16 pixels keeps the 16-pixel staircase on
;; its diagonals, and those diagonals are the whole shape.
(setq lzp:*icon16*
  '(
    "................"
    "......XXXX......"
    ".....XXXXXX....."
    "...XXXXXXXXXX..."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "...XXXXXXXXXX..."
    ".....XXXXXX....."
    "......XXXX......"
    "................"))

;; The second mark: a triangle, point north, for TYLERDRONESUITE's own
;; button.  A different SHAPE rather than a different colour, because
;; the two sit side by side on the same strip and both are orange --
;; lzp:bmp-bytes paints every "X" the one orange, which is what makes
;; the pair read as one toolkit rather than two.
(setq lzp:*tri16*
  '(
    "................"
    ".......XX......."
    ".......XX......."
    "......XXXX......"
    "......XXXX......"
    ".....XXXXXX....."
    ".....XXXXXX....."
    "....XXXXXXXX...."
    "....XXXXXXXX...."
    "...XXXXXXXXXX..."
    "...XXXXXXXXXX..."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    ".XXXXXXXXXXXXXX."
    "XXXXXXXXXXXXXXXX"
    "................"
))

(setq lzp:*tri32*
  '(
    "................................"
    "................................"
    "...............XX..............."
    "...............XX..............."
    "..............XXXX.............."
    "..............XXXX.............."
    ".............XXXXXX............."
    ".............XXXXXX............."
    "............XXXXXXXX............"
    "............XXXXXXXX............"
    "...........XXXXXXXXXX..........."
    "...........XXXXXXXXXX..........."
    "..........XXXXXXXXXXXX.........."
    "..........XXXXXXXXXXXX.........."
    ".........XXXXXXXXXXXXXX........."
    ".........XXXXXXXXXXXXXX........."
    "........XXXXXXXXXXXXXXXX........"
    ".......XXXXXXXXXXXXXXXXXX......."
    ".......XXXXXXXXXXXXXXXXXX......."
    "......XXXXXXXXXXXXXXXXXXXX......"
    "......XXXXXXXXXXXXXXXXXXXX......"
    ".....XXXXXXXXXXXXXXXXXXXXXX....."
    ".....XXXXXXXXXXXXXXXXXXXXXX....."
    "....XXXXXXXXXXXXXXXXXXXXXXXX...."
    "....XXXXXXXXXXXXXXXXXXXXXXXX...."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "..XXXXXXXXXXXXXXXXXXXXXXXXXXXX.."
    "..XXXXXXXXXXXXXXXXXXXXXXXXXXXX.."
    ".XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX."
    "................................"
    "................................"
))

(setq lzp:*icon32*
  '(
    "................................"
    "..............XXXX.............."
    ".............XXXXXX............."
    "...........XXXXXXXXXX..........."
    ".........XXXXXXXXXXXXXX........."
    ".......XXXXXXXXXXXXXXXXXX......."
    "......XXXXXXXXXXXXXXXXXXXX......"
    "....XXXXXXXXXXXXXXXXXXXXXXXX...."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "....XXXXXXXXXXXXXXXXXXXXXXXX...."
    "......XXXXXXXXXXXXXXXXXXXX......"
    ".......XXXXXXXXXXXXXXXXXX......."
    ".........XXXXXXXXXXXXXX........."
    "...........XXXXXXXXXX..........."
    ".............XXXXXX............."
    "..............XXXX.............."
    "................................"))

(defun lzp:le2 (n)
  (list (rem n 256) (rem (/ n 256) 256)))

(defun lzp:le4 (n)
  (append (lzp:le2 (rem n 65536)) (lzp:le2 (/ n 65536))))

;; The complete .bmp as a byte list: 24bpp, bottom-up rows (a positive
;; height means the FIRST row in the file is the BOTTOM row of the
;; image, hence the reverse).  "X" pixels are orange -- stored B,G,R,
;; so 0 165 255 -- and the rest panel grey.  Both sizes give a row
;; width that is a multiple of 4 (48 and 96), so there is no row
;; padding to get wrong.
(defun lzp:bmp-bytes (size grid / fg bg rowbytes out row s i)
  (setq fg '(0 165 255)
        bg '(54 54 54)
        rowbytes (* 3 size))
  (setq out (append
              (list 66 77)                      ; "BM"
              (lzp:le4 (+ 54 (* rowbytes size)))
              '(0 0 0 0)
              (lzp:le4 54)                      ; pixel data offset
              (lzp:le4 40)                      ; BITMAPINFOHEADER
              (lzp:le4 size)
              (lzp:le4 size)
              (lzp:le2 1)                       ; planes
              (lzp:le2 24)                      ; bits per pixel
              (lzp:le4 0)                       ; no compression
              (lzp:le4 (* rowbytes size))
              (lzp:le4 0) (lzp:le4 0)
              (lzp:le4 0) (lzp:le4 0)))
  ;; built by consing and reversed once: appending inside the loop
  ;; would copy the whole list per pixel, which for the 32x32 is
  ;; millions of cons cells and a visible pause on every load
  (setq out (reverse out))
  (foreach row (reverse grid)
    (setq i 1)
    (while (<= i size)
      (setq s (substr row i 1))
      (setq out (cons (caddr (if (= s "X") fg bg))
                      (cons (cadr (if (= s "X") fg bg))
                            (cons (car (if (= s "X") fg bg)) out))))
      (setq i (1+ i))))
  (reverse out))

;;  WRITING IT.  Not with write-char: AutoLISP opens files in text mode
;;  and has no NUL in its character model at all -- (chr 0) is the
;;  empty string -- while a 24-bit BMP header is full of them.  The
;;  pixel-data offset (54 0 0 0), the header size (40 0 0 0) and the
;;  five zeroed DIB fields are 43 NULs before a single pixel, and the
;;  orange itself has a zero blue channel.  There is no arrangement of
;;  this format that write-char could emit, so the bytes go out through
;;  an ADODB.Stream in binary mode instead.
;;
;;  That is no new dependency: the toolbar this icon goes on is made
;;  through the ActiveX menu API a few lines below, so a session that
;;  cannot reach COM has no button to put an icon on.  If the stream
;;  is unavailable the write fails, the caller skips SetBitmaps, and
;;  the button keeps its default face.

;; A byte array is the one piece of this that AutoLISP may refuse:
;; vlax-make-safearray's documented type constants stop at
;; vlax-vbVariant, and VT_UI1 (17) is not among them, so whether it is
;; accepted is a property of the release rather than of the code.  Both
;; spellings are tried before giving up, and which one worked is
;; recorded for LAZICON to report.
;;  BASE64, AND WHY THE ICON GOES OUT THROUGH IT.
;;
;;  ADODB.Stream's Write wants a VT_UI1 (byte) array and nothing else.
;;  AutoLISP cannot reliably make one: vlax-make-safearray's documented
;;  type constants stop at vlax-vbVariant, VT_UI1 (17) is not among
;;  them, and whether a release accepts it anyway is a property of that
;;  release.  Where it is refused the old code fell back to a
;;  vbInteger (VT_I2) array, which Write then rejected with
;;
;;      Arguments are of the wrong type, are out of acceptable range,
;;      or are in conflict with one another
;;
;;  -- reported from the field, and the reason the button had no
;;  picture at all rather than a wrong one.
;;
;;  The way round it is to stop trying to build a byte array in
;;  AutoLISP.  Base64 is a pure-ASCII encoding of arbitrary bytes --
;;  no NUL, nothing AutoLISP's character model lacks -- so the bytes
;;  can be carried in an ordinary string, and MSXML turns that string
;;  into a real VT_UI1 array on the other side.  Both components ship
;;  with Windows, and the toolbar this icon goes on already needs COM.
(setq lzp:*b64*
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

;; Join a list of strings without the quadratic cost of strcat-ing onto
;; one accumulator: a 32x32 icon is 4168 base64 characters, and growing
;; that a chunk at a time copies the whole string every time.  Pairwise
;; merging is O(n log n) and finishes instantly.
(defun lzp:joinstr (lst / out a)
  (while (cdr lst)
    (setq out nil)
    (while lst
      (setq a (car lst) lst (cdr lst))
      (if lst
        (setq out (cons (strcat a (car lst)) out) lst (cdr lst))
        (setq out (cons a out))))
    (setq lst (reverse out)))
  (if lst (car lst) ""))

;; Bytes to base64.  Plain integer arithmetic rather than lsh/logand:
;; the shifts are all by 2, 4 and 6 bits, which is division and
;; multiplication by 4, 16 and 64, and every AutoLISP has those.
(defun lzp:b64 (bytes / out n b1 b2 b3)
  (while bytes
    (setq b1 (car bytes) bytes (cdr bytes) n 1 b2 0 b3 0)
    (if bytes (setq b2 (car bytes) bytes (cdr bytes) n 2))
    (if bytes (setq b3 (car bytes) bytes (cdr bytes) n 3))
    (setq out
      (cons
        (strcat
          (substr lzp:*b64* (1+ (/ b1 4)) 1)
          (substr lzp:*b64* (1+ (+ (* (rem b1 4) 16) (/ b2 16))) 1)
          (if (>= n 2)
            (substr lzp:*b64* (1+ (+ (* (rem b2 16) 4) (/ b3 64))) 1)
            "=")
          (if (>= n 3) (substr lzp:*b64* (1+ (rem b3 64)) 1) "="))
        out)))
  (lzp:joinstr (reverse out)))

;; The base64 string as a real byte array, via MSXML's bin.base64
;; element.  nodeTypedValue on such an element IS a VT_UI1 array, which
;; is exactly what Write will take.
;; The whole chain on one document: an element typed bin.base64, the
;; base64 text put into it, and the byte array read back out.
(defun lzp:b64-chain (doc b64 / el out)
  ;; the documented long spellings, not the vlax-get / vlax-put /
  ;; vlax-invoke shorthands: the shorthands are what the rest of this
  ;; file uses and they clearly work here, but this chain is the part
  ;; that keeps coming back empty, so it does not get to be the place
  ;; a spelling is also in question
  (setq el (vlax-invoke-method doc 'createElement "b"))
  (vlax-put-property el 'dataType "bin.base64")
  (vlax-put-property el 'text b64)
  (setq out (vlax-get-property el 'nodeTypedValue))
  (vl-catch-all-apply 'vlax-release-object (list el))
  out)

;; One ProgID, tried all the way through.  nil if this version cannot
;; carry it.
(defun lzp:whynot (id msg)
  (setq lzp:*msxmlwhy*
        (cons (strcat id ": " msg) lzp:*msxmlwhy*))
  nil)

(defun lzp:b64-try (id b64 / doc r)
  (setq r (vl-catch-all-apply 'vlax-create-object (list id)))
  (cond
    ((vl-catch-all-error-p r)
     (lzp:whynot id (vl-catch-all-error-message r)))
    ((null r) (lzp:whynot id "came back nil"))
    (t
     (setq doc r)
     (setq r (vl-catch-all-apply 'lzp:b64-chain (list doc b64)))
     (vl-catch-all-apply 'vlax-release-object (list doc))
     (cond
       ((vl-catch-all-error-p r)
        (lzp:whynot id (vl-catch-all-error-message r)))
       ((null r) (lzp:whynot id "the chain ran but gave back nothing"))
       (t (setq lzp:*icontype* (strcat "bin.base64 via " id))
          r)))))

;;  EVERY ProgID IS TRIED ALL THE WAY THROUGH, not just far enough to
;;  create.  MSXML 6.0 creates perfectly happily and then refuses
;;  dataType -- XDR schema support, of which bin.base64 is part, was
;;  removed in 6.0 -- so a version test that stops at "did the object
;;  appear?" picks 6.0, fails on the next line, and reports nothing.
;;  That is exactly what happened in the field: the report said
;;  "array: VT_UI1 safearray", meaning this returned nil and the
;;  fallback ran.
;;
;;  So 3.0 and the version-independent Microsoft.XMLDOM come first --
;;  both carry XDR -- and 6.0 stays at the back where it costs one
;;  failed attempt and nothing else.
(defun lzp:bytes-msxml (bytes / b64 out id)
  (setq lzp:*msxmlwhy* nil)
  (setq b64 (lzp:b64 bytes))
  (foreach id '("MSXML2.DOMDocument.3.0" "Microsoft.XMLDOM"
                "MSXML2.DOMDocument" "MSXML2.DOMDocument.6.0")
    (if (not out) (setq out (lzp:b64-try id b64))))
  out)

;; A byte array by whichever route this AutoCAD allows.  MSXML first
;; because it is the one that does not depend on an undocumented
;; safearray type; the two safearray spellings stay as fallbacks so a
;; machine where they DO work is no worse off.  Which route won is
;; recorded for LAZICON to report.
(defun lzp:bytearray (bytes / sa)
  (cond
    ;; lzp:b64-try has already recorded WHICH MSXML version carried it,
    ;; which is the part worth knowing; do not flatten that back to a
    ;; generic label here
    ((setq sa (lzp:bytes-msxml bytes)) sa)
    (t
     (setq sa (vl-catch-all-apply
                'vlax-make-safearray
                (list 17 (cons 0 (1- (length bytes))))))
     (if (vl-catch-all-error-p sa)
         (setq sa (vl-catch-all-apply
                    'vlax-make-safearray
                    (list vlax-vbInteger (cons 0 (1- (length bytes)))))
               lzp:*icontype* "vbInteger (VT_I2 - Write may refuse this)")
         (setq lzp:*icontype* "VT_UI1 safearray"))
     (cond
       ((vl-catch-all-error-p sa) (setq lzp:*icontype* "none - no array could be made") nil)
       (t (vlax-safearray-fill sa bytes)
          sa)))))

(defun lzp:bmp-stream (st path bytes / sa)
  (setq lzp:*icontype* nil)
  ;; each step names itself before it runs, so a failure reports WHICH
  ;; call refused rather than one COM message with no address on it
  (setq lzp:*iconstep* "building the byte array")
  (if (not (setq sa (lzp:bytearray bytes)))
      (exit))                                 ; caught by the caller
  (setq lzp:*iconstep* "Type = 1 (adTypeBinary)")
  (vlax-put st 'Type 1)
  (setq lzp:*iconstep* "Open")
  (vlax-invoke st 'Open)
  ;; Two spellings.  Write takes a Variant, and whether a raw safearray
  ;; marshals into one is another thing that varies by release -- so if
  ;; the plain call is refused, the wrapped one is tried before giving
  ;; up.  The step name says which was in play.
  (setq lzp:*iconstep* "Write")
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'vlax-invoke (list st 'Write sa)))
    (progn
      (setq lzp:*iconstep* "Write (variant-wrapped)")
      (vlax-invoke st 'Write (vlax-make-variant sa))))
  (setq lzp:*iconstep* "SaveToFile")
  (vlax-invoke st 'SaveToFile path 2)         ; overwrite if present
  (setq lzp:*iconstep* "Close")
  (vlax-invoke st 'Close)
  (setq lzp:*iconstep* nil)
  t)

;;; -------------------- the route that needs no byte array ---------------
;;  Every failure so far has been about handing AutoLISP's idea of an
;;  array to COM.  VT_UI1 was accepted on the machine that reported it
;;  and Write refused the array anyway, wrapped in a variant or not;
;;  MSXML, which exists to sidestep that, came back empty.
;;
;;  So here is the route with no array in it at all.  certutil has
;;  shipped with Windows since Vista and decodes base64 to binary in
;;  one command.  AutoLISP writes the base64 as ORDINARY TEXT with
;;  write-line -- which is the one thing it has never had trouble with
;;  -- and Windows does the decoding.  Nothing crosses the COM boundary
;;  except a command line.
;;
;;  It is last because it costs a process and writes a second file;
;;  when the stream route works this never runs.
(defun lzp:b64-lines (b64 fh / i n)
  ;; certutil wants the base64 wrapped rather than one enormous line
  (setq i 1 n (strlen b64))
  (while (<= i n)
    (write-line (substr b64 i 76) fh)
    (setq i (+ i 76))))

(defun lzp:bmp-certutil (path bytes / tmp fh sh r out)
  (setq tmp (strcat path ".b64"))
  (cond
    ((not (setq fh (open tmp "w")))
     (setq lzp:*iconerr*
           (strcat lzp:*iconerr* "  certutil: could not write " tmp "."))
     nil)
    (t
     (setq r (vl-catch-all-apply 'lzp:b64-lines (list (lzp:b64 bytes) fh)))
     (close fh)
     (cond
       ((vl-catch-all-error-p r)
        (vl-file-delete tmp)
        (setq lzp:*iconerr*
              (strcat lzp:*iconerr* "  certutil: writing the base64 failed: "
                      (vl-catch-all-error-message r)))
        nil)
       (t
        (setq sh (vl-catch-all-apply 'vlax-create-object
                                     (list "WScript.Shell")))
        (cond
          ((vl-catch-all-error-p sh)
           (vl-file-delete tmp)
           (setq lzp:*iconerr*
                 (strcat lzp:*iconerr* "  certutil: WScript.Shell would not "
                         "start: " (vl-catch-all-error-message sh)))
           nil)
          (t
           ;; the third argument waits for it, so the file is there by
           ;; the time this returns rather than some moments later
           (setq r (vl-catch-all-apply
                     'vlax-invoke-method
                     (list sh 'Run
                           (strcat "cmd /c certutil -f -decode \"" tmp
                                   "\" \"" path "\"")
                           0 :vlax-true)))
           (vl-catch-all-apply 'vlax-release-object (list sh))
           (vl-file-delete tmp)
           (cond
             ((vl-catch-all-error-p r)
              (setq lzp:*iconerr*
                    (strcat lzp:*iconerr* "  certutil: " 
                            (vl-catch-all-error-message r)))
              nil)
             ((findfile path) (setq lzp:*icontype* "base64 text + certutil") t)
             (t (setq lzp:*iconerr*
                      (strcat lzp:*iconerr* "  certutil ran but wrote nothing."))
                nil)))))))))

(defun lzp:bmp-via-stream (path bytes / st ok)
  (setq st (vl-catch-all-apply 'vlax-create-object (list "ADODB.Stream")))
  (cond
    ((vl-catch-all-error-p st)
     (setq lzp:*iconerr*
           (strcat "ADODB.Stream would not start: "
                   (vl-catch-all-error-message st)))
     nil)
    ((null st)
     (setq lzp:*iconerr* "ADODB.Stream came back nil.")
     nil)
    (t
     (setq ok (vl-catch-all-apply 'lzp:bmp-stream (list st path bytes)))
     (vl-catch-all-apply 'vlax-release-object (list st))
     (cond
       ((vl-catch-all-error-p ok)
        (setq lzp:*iconerr*
              (strcat "writing " path " failed at "
                      (if lzp:*iconstep* lzp:*iconstep* "an unnamed step")
                      ": " (vl-catch-all-error-message ok)))
        nil)
       (t path)))))

;; The icon, by whichever route this machine allows.  The stream first
;; because it writes the file directly; certutil after it, because it
;; costs a process and a second file but asks nothing of AutoLISP but
;; text.  Which one won is recorded for LAZICON to report.
(defun lzp:bmp-write (path size grid / bytes)
  (setq lzp:*iconerr* ""
        lzp:*iconroute* nil
        bytes (lzp:bmp-bytes size grid))
  (cond
    ((lzp:bmp-via-stream path bytes)
     (setq lzp:*iconroute* "ADODB.Stream" lzp:*iconerr* nil)
     path)
    ((lzp:bmp-certutil path bytes)
     (setq lzp:*iconroute* "certutil")
     path)
    (t nil)))

;; A STABLE path, not a fresh temp name each time: SetBitmaps stores the
;; path rather than the image, and AutoCAD re-reads it whenever the
;; button is redrawn.  A toolbar that survives into another session
;; would otherwise be pointing at a swept temp file for ever.
(defun lzp:icon-file (dir stem name / d)
  (setq d dir)
  ;; a folder is not guaranteed to end in a separator -- glue the name
  ;; straight on and a folder called Temp becomes a file called
  ;; Templazpanel-16.bmp, which fails silently later
  (if (not (member (substr d (strlen d) 1) '("\\" "/")))
      (setq d (strcat d "\\")))
  (strcat d stem "-" name ".bmp"))

(defun lzp:icon-path (stem name / d)
  (setq d (getvar "TEMPPREFIX"))
  (if (and d (= (type d) 'STR) (/= d ""))
      (lzp:icon-file d stem name)
      (vl-filename-mktemp (strcat stem "-" name) nil ".bmp")))

;;  WHERE THE FILES GO, AND WHAT SETBITMAPS IS TOLD.  The CUI resolves a
;;  toolbar bitmap by NAME along the support file search path -- hand it
;;  a full path into the temp folder, which is not on that path, and on
;;  many builds the button draws the "?" missing-image placeholder even
;;  though the file is right where the path says.  So the icons go into
;;  the FIRST folder of the support path (the user's own Support folder,
;;  writable by design) and SetBitmaps is handed the bare names, which
;;  resolve exactly the way the CUI wants to resolve them.  Only when
;;  that folder cannot be written does this fall back to the temp folder
;;  and full paths -- better a chance of an icon than none.

(defun lzp:support-read ()
  (vla-get-supportpath
    (vla-get-files (vla-get-preferences (vlax-get-acad-object)))))

;; The first entry of the support path, or nil.
(defun lzp:support-dir ( / p out i n c)
  (setq p (vl-catch-all-apply 'lzp:support-read nil))
  (if (and (not (vl-catch-all-error-p p)) (= (type p) 'STR) (/= p ""))
      (progn
        (setq i 1 n (strlen p) out "")
        (while (and (<= i n) (/= (setq c (substr p i 1)) ";"))
          (setq out (strcat out c)
                i (1+ i)))
        (if (/= out "") out))))

;; Write both sizes into DIR; the paths, or nil when either write fails
;; (lzp:bmp-write records why in lzp:*iconerr*).
(defun lzp:try-icons (dir stem art16 art32 / s l)
  (if (and dir (= (type dir) 'STR) (/= dir ""))
      (progn
        (setq s (lzp:icon-file dir stem "16")
              l (lzp:icon-file dir stem "32"))
        (if (and (lzp:bmp-write s 16 art16)
                 (lzp:bmp-write l 32 art32))
            (progn (setq lzp:*icondir* dir)
                   (list s l))))))

;; What to hand SetBitmaps: bare names when the files sit on the support
;; path, full temp paths as the fallback.
(defun lzp:write-bmps (stem art16 art32 / d)
  (setq lzp:*icondir* nil
        lzp:*iconref* nil)
  (cond
    ((and (setq d (lzp:support-dir)) (lzp:try-icons d stem art16 art32))
     (setq lzp:*iconref* "name")
     (list (strcat stem "-16.bmp") (strcat stem "-32.bmp")))
    ((lzp:try-icons (getvar "TEMPPREFIX") stem art16 art32)
     (setq lzp:*iconref* "path")
     (list (lzp:icon-file (getvar "TEMPPREFIX") stem "16")
           (lzp:icon-file (getvar "TEMPPREFIX") stem "32")))))

;; The LazPanel toolbar, wherever it lives -- one this file made in an
;; earlier session may sit in any loaded menu group.
;;; -------------------- the two screen buttons --------------------------
;;  Each is one toolbar with one button, and a spec says everything that
;;  differs between them:
;;
;;      (toolbar-name  icon-stem  tooltip  command  art16  art32)
;;
;;  There are two because they are two different tools.  The panel is
;;  the whole roster; the suite is one job someone runs all day, and it
;;  earns a button of its own rather than two clicks through a dialog.
;;  A different SHAPE tells them apart -- hexagon and triangle -- since
;;  both are painted the same orange.
(defun lzp:tb-name (spec) (nth 0 spec))
(defun lzp:tb-stem (spec) (nth 1 spec))
(defun lzp:tb-tip  (spec) (nth 2 spec))
(defun lzp:tb-cmd  (spec) (nth 3 spec))
(defun lzp:tb-16   (spec) (nth 4 spec))
(defun lzp:tb-32   (spec) (nth 5 spec))

(defun lzp:panel-spec ()
  (list lzp:*tbname* "lazpanel"
        "Open the LazPanel tool panel" "LAZPANEL"
        lzp:*icon16* lzp:*icon32*))

(defun lzp:suite-spec ()
  (list lzp:*tbsuite* "tylerdronesuite"
        "TYLERDRONESUITE - TYDRN, then PADDLE, then AUTODIM"
        "TYLERDRONESUITE"
        lzp:*tri16* lzp:*tri32*))

;; Is this session the LAZPASS build?  Both LAZPASS.lsp and
;; CALOFIN-LOADER.lsp raise cal:*build-loading* before they load a
;; thing, and neither lowers it -- so it answers for the session, which
;; is what is being asked.  Standalone the symbol is simply unbound,
;; and an unbound symbol is nil.
(defun lzp:in-build-p () (if cal:*build-loading* T nil))

;; Does the suite want a button of its own here?
(defun lzp:suite-wanted-p ()
  (and (lzp:has "TYLERDRONESUITE")
       (cond ((eq lzp:*suitebutton* 'AUTO) (not (lzp:in-build-p)))
             (lzp:*suitebutton* T))))

;; The buttons to put up.  Two things have to be true for the suite's:
;; its command has to be loaded -- LAZPANEL.lsp APPLOADed on its own has
;; no tydrn.lsp beside it, and a button that answers a click with
;; "Unknown command" is worse than no button -- and this has to not be
;; the LAZPASS build, which puts up one external button and that one is
;; the panel's.
(defun lzp:tb-specs ( / out)
  (setq out nil)
  (if lzp:*panelbutton* (setq out (list (lzp:panel-spec))))
  (if (lzp:suite-wanted-p)
    (setq out (append out (list (lzp:suite-spec)))))
  out)

;; Every button this file knows how to draw, wanted here or not.  What
;; is NOT wanted still matters: AutoCAD keeps toolbars in the CUI
;; between sessions, so one put up by another build is still on screen
;; when this one loads.
(defun lzp:tb-all ()
  (list (lzp:panel-spec) (lzp:suite-spec)))

(defun lzp:wanted-name-p (name / spec found)
  (foreach spec (lzp:tb-specs)
    (if (= (lzp:tb-name spec) name) (setq found T)))
  found)

(defun lzp:toolbar-find (name / mgs n i tbs m j tb found)
  (setq mgs (vla-get-menugroups (vlax-get-acad-object)))
  (setq n (vla-get-count mgs)
        i 0)
  (while (and (< i n) (not found))
    (setq tbs (vla-get-toolbars (vla-item mgs i)))
    (setq m (vla-get-count tbs)
          j 0)
    (while (and (< j m) (not found))
      (setq tb (vla-item tbs j))
      (if (= (strcase (vla-get-name tb)) (strcase name))
        (setq found tb))
      (setq j (1+ j)))
    (setq i (1+ i)))
  found)

;; Make the toolbar with its one button.  The macro is what a menu
;; button really sends: two Cancels (ASCII 3 -- the COM API takes the
;; raw characters, not the "^C^C" spelling a menu FILE would use) and
;; the command.
;;
;; The button goes in at index 0.  The toolbar was created empty a line
;; earlier, so 1 is past its end -- and if that throws, an empty
;; toolbar called LazPanel is left behind, which lzp:toolbar-find would
;; then hand back for ever while LAZBUTTON reported success and put
;; nothing on screen.  So a toolbar that fails to get its button does
;; not survive the attempt.
(defun lzp:toolbar-make (spec / tbs tb btn)
  (setq tbs (vla-get-toolbars
              (vla-item (vla-get-menugroups (vlax-get-acad-object)) 0)))
  (setq tb (vla-add tbs (lzp:tb-name spec)))
  (setq btn (vl-catch-all-apply
              'vla-addtoolbarbutton
              (list tb 0 (lzp:tb-name spec)
                    (lzp:tb-tip spec)
                    (strcat (chr 3) (chr 3) "_" (lzp:tb-cmd spec) " "))))
  (cond
    ((vl-catch-all-error-p btn)
     (vl-catch-all-apply 'vla-delete (list tb))
     nil)
    (t (list tb btn))))

;; Put the button on screen: reuse the toolbar when one exists -- its
;; position and docking are the user's -- otherwise create it and float
;; it in view.  Either way the icons are rewritten and re-applied, and
;; the toolbar is made visible: a toolbar the user closed is still
;; found by name, and without this it would never come back.
;; Returns the toolbar, or nil when there is none to be had.
(defun lzp:button-init (spec / tb btn pair paths made)
  (cond
    ((setq tb (lzp:toolbar-find (lzp:tb-name spec)))
     (setq btn (vl-catch-all-apply 'vla-item (list tb 0)))
     (if (vl-catch-all-error-p btn) (setq btn nil)))
    ((setq pair (lzp:toolbar-make spec))
     (setq tb (car pair)
           btn (cadr pair)
           made t)))
  (if tb
    (progn
      (if (and btn (setq paths (lzp:write-bmps (lzp:tb-stem spec)
                                               (lzp:tb-16 spec)
                                               (lzp:tb-32 spec))))
        (vl-catch-all-apply 'vla-setbitmaps
                            (list btn (car paths) (cadr paths)))
        ;; one line, not a stack trace: the panel still works without a
        ;; picture, but a blank button should not be a mystery
        (princ "\n[lazpanel] button picture not applied - LAZICON says why."))
      ;; Big buttons before visible: the toolbar resizes to fit its
      ;; button, and doing it the other way round makes it visibly jump.
      ;; nil does not merely SKIP this -- it puts the setting back, or
      ;; "setq it nil and run LAZBUTTON" would be advice that does
      ;; nothing once a session has already been switched over.
      (vl-catch-all-apply 'vla-put-largebuttons
                          (list tb (if lzp:*bigbutton*
                                     :vlax-true :vlax-false)))
      (vl-catch-all-apply 'vla-put-visible (list tb :vlax-true))
      ;; a new one is floated where it can be seen; the second lands
      ;; below the first rather than on top of it
      (if made
        (vl-catch-all-apply
          'vla-float
          (list tb (+ 200 (* 40 (lzp:tb-index spec))) 300 1)))))
  tb)

;; Where SPEC sits in the roster, so two new toolbars do not float onto
;; the same pixel.
(defun lzp:tb-index (spec / i n found)
  (setq i 0 found 0)
  (foreach n (lzp:tb-all)
    (if (= (lzp:tb-name n) (lzp:tb-name spec)) (setq found i))
    (setq i (1+ i)))
  found)

;; Take a button off the strip without destroying it: the toolbar keeps
;; wherever the operator docked or dragged it, and turning the tunable
;; back on and running LAZBUTTON brings it back exactly there.
(defun lzp:button-hide (spec / tb)
  (if (setq tb (lzp:toolbar-find (lzp:tb-name spec)))
    (vl-catch-all-apply 'vla-put-visible (list tb :vlax-false))))

;; Put up the buttons this session should have -- AND take down the ones
;; it should not.
;;
;; The second half is not tidiness.  AutoCAD keeps toolbars in the CUI,
;; so one put up by another build is still on screen the next time
;; AutoCAD opens: load the drone edition on a machine that has ever seen
;; LAZPASS and, without this, the panel's button would still be sitting
;; there beside the drone's.  "One button" has to mean one button on the
;; machine it actually lands on.  It works both ways round -- load
;; LAZPASS after the edition and the drone button goes away again -- so
;; whichever build was loaded last is the one whose buttons are showing.
;;
;; Returns the toolbars it put up, newest last.
(defun lzp:buttons-init ( / out spec tb)
  (foreach spec (lzp:tb-all)
    (if (lzp:wanted-name-p (lzp:tb-name spec))
      (if (setq tb (lzp:button-init spec))
        (setq out (append out (list tb))))
      (lzp:button-hide spec)))
  out)

;;; -------------------- the dialog run ----------------------------------
;;  No sysvar save, no undo group: the panel changes no settings and
;;  draws nothing -- whatever it launches manages its own.  The error
;;  handler only has the dialog and the temp file to pick up.
;;
;;  This is a helper rather than the command body so that its localized
;;  *error* is OUT OF SCOPE by the time anything is launched: the tool
;;  the user clicked gets whatever error handling it sets up itself,
;;  and a tool that fails reports as itself, not as "LAZPANEL error".

(defun lzp:show ( / *error* f dcl rc pick have n g done out)
  (defun *error* (msg)
    ;; the dialog itself first: unload_dialog alone does not dismiss a
    ;; dialog that is still up, term_dialog does (and is a no-op when
    ;; none is)
    (term_dialog)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (setq dcl nil)
    (if f (vl-file-delete f))
    (setq f nil lzp:*pick* nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZPANEL error: " msg)))
    (princ))
  ;; NOT reset here: the panel reopens after every tool it launches, and
  ;; coming back to page one in the middle of the screen each time would
  ;; undo the whole point of reopening.  lzp:*page* and lzp:*pos* are
  ;; where the user last had it.
  (setq lzp:*pick* nil)
  (if (not (and lzp:*page* (assoc lzp:*page* lzp:*groups*)))
    (setq lzp:*page* (car (car lzp:*groups*))))
  (setq g lzp:*page*)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZPANEL error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZPANEL error: could not load the dialog file."))
    (t
     ;; The page loop.  One page per group, so the eye lands on a dozen
     ;; buttons rather than all of them; the tab strip is the whole
     ;; roster and never changes width as you move along it.
     (while (not done)
       (cond
         ((not (lzp:newdlg (lzp:dlgname g) dcl))
          (princ "\nLAZPANEL error: could not open the panel.")
          (setq done t))
         (t
          (setq lzp:*page* g
                have (lzp:loaded))
          (set_tile "status"
                    (strcat (itoa (length have)) " of "
                            (itoa (length (lzp:commands)))
                            " tools loaded - greyed are not in this session"))
          (foreach n (lzp:group-commands g)
            (action_tile n
              "(setq lzp:*pick* $key lzp:*pos* (done_dialog 1))")
            (if (not (member n have))
              (mode_tile n 1)))
          ;; the pinned row: same launch, its own keys, greyed the same
          ;; way -- $key would read "pin_POOL", so the name is baked in
          (foreach n lzp:*pins*
            (action_tile (strcat "pin_" n)
              (strcat "(setq lzp:*pick* \"" n
                      "\" lzp:*pos* (done_dialog 1))"))
            (if (not (member n have))
              (mode_tile (strcat "pin_" n) 1)))
          (action_tile "pin_edit" "(setq lzp:*pos* (done_dialog 5))")
          (foreach n lzp:*groups*
            (action_tile (strcat "tab_" (car n))
              (strcat "(setq lzp:*go* \"" (car n)
                      "\" lzp:*pos* (done_dialog 4))")))
          (action_tile "cancel" "(setq lzp:*pos* (done_dialog 0))")
          (setq rc (start_dialog))
          (cond
            ((= rc 4) (setq g lzp:*go* lzp:*page* lzp:*go*))  ; a tab
            ;; the pin editor runs on the same loaded handle, then the
            ;; caller reopens: the Pinned row is generated DCL, so it
            ;; only changes when the file is written again
            ((= rc 5)
             (lzp:pin-edit dcl)
             (setq done t out "*pins*"))
            (t (setq done t
                     out (if (= rc 1) lzp:*pick*)))))))))
  ;; the dialog and its temp file go away BEFORE anything is launched,
  ;; so an interactive command never starts under an open modal dialog
  ;; and the temp file never outlives the panel
  (if (and dcl (>= dcl 0)) (unload_dialog dcl))
  (setq dcl nil)
  (if f (vl-file-delete f))
  (setq f nil lzp:*pick* nil)
  out)

;; Open a page where the user last had the panel.  done_dialog reports
;; the position it closed at and new_dialog takes one back, but only in
;; its four-argument form -- and a build answering done_dialog with
;; something other than a point would poison every reopen, so the shape
;; is checked before it is trusted.
(defun lzp:newdlg (name dcl)
  (if (and lzp:*pos* (listp lzp:*pos*) (= (length lzp:*pos*) 2)
           (numberp (car lzp:*pos*)) (numberp (cadr lzp:*pos*)))
      (new_dialog name dcl "" lzp:*pos*)
      (new_dialog name dcl)))

;;; -------------------- commands ----------------------------------------

;;  THE REOPEN.  A DCL dialog is modal, so the panel still has to close
;;  for a tool to run -- but it no longer has to be reopened by hand.
;;  The loop is the feature: click, the panel closes, the tool runs to
;;  its own end, the panel comes straight back on the page and at the
;;  screen position it was at, with the session re-probed so a tool
;;  loaded meanwhile is no longer greyed.  Close is the way out, and it
;;  is the default button.
;;
;;  A tool cancelled with Escape comes back here exactly as a finished
;;  one does: lzp:launch has already returned by then, so the reopen is
;;  not conditional on the tool having succeeded.  A tool that dies with
;;  a hard error DOES end the loop -- its own *error* runs, the panel
;;  simply does not come back, and LAZPANEL reopens it.  That is the
;;  right way round: the alternative is a panel that keeps bouncing back
;;  in front of someone trying to read the error it just printed.
(defun c:LAZPANEL ( / pick)
  (lzp:pins-read)
  (while (setq pick (lzp:show))
    (if (/= pick "*pins*")
      (lzp:launch pick)))
  (princ))

;; Open the pin editor on its own, without going through the panel.
(defun c:LAZPIN ( / f dcl)
  (lzp:pins-read)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZPIN error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZPIN error: could not load the dialog file."))
    (t
     (lzp:pin-edit dcl)
     (unload_dialog dcl)
     (vl-file-delete f)
     (princ (strcat "\nLAZPANEL: "
                    (itoa (length lzp:*pins*)) " tools pinned."))))
  (princ))

(defun c:LAZBUTTON ( / tbs spec tb any)
  (setq tbs (vl-catch-all-apply 'lzp:buttons-init nil))
  (cond
    ((vl-catch-all-error-p tbs)
     (princ (strcat "\nLAZBUTTON error: " (vl-catch-all-error-message tbs))))
    (tbs
     (foreach tb tbs
       (vl-catch-all-apply 'vla-put-visible (list tb :vlax-true)))
     (setq any nil)
     (foreach spec (lzp:tb-specs)
       (if (lzp:toolbar-find (lzp:tb-name spec))
         (progn
           (setq any T)
           (princ (strcat "\n" (lzp:tb-name spec) " button is on screen -"
                          " drag it anywhere, dock it,"
                          "\n  click it to run " (lzp:tb-cmd spec) ".")))))
     ;; said out loud because it is not a change to THESE toolbars: the
     ;; operator's other toolbars grew too, and they should hear it
     ;; from the command that did it rather than wonder
     (if (and any lzp:*bigbutton*)
       (princ (strcat "\n  Drawn at 32 pixels.  AutoCAD sizes every"
                      " toolbar together, so the rest grew"
                      "\n  with it; (setq lzp:*bigbutton* nil) then"
                      " LAZBUTTON puts them all back.")))
     (cond
       ((lzp:suite-wanted-p))
       ((not (lzp:has "TYLERDRONESUITE"))
        (princ (strcat "\n  TYLERDRONESUITE is not loaded, so it has no"
                       " button of its own -"
                       "\n  APPLOAD tydrn.lsp (or LAZPASS.lsp) and run"
                       " LAZBUTTON again.")))
       (t
        (princ (strcat "\n  TYLERDRONESUITE is on the panel rather than"
                       " on a button of its own:"
                       "\n  this is the whole build, and the build puts"
                       " up one external button."
                       "\n  (setq lzp:*suitebutton* T) then LAZBUTTON"
                       " gives it one anyway.")))))
    (t
     (princ "\nLAZBUTTON: the menu API is unavailable - type LAZPANEL instead.")))
  (princ))

(defun c:LAZICON ( / spec)
  ;; The icon path is best effort and fails silently on purpose: a
  ;; missing picture must never stop the panel working.  Silence is the
  ;; right default and a poor answer to "why is my button blank", so
  ;; this walks the same steps out loud -- once per button, because
  ;; they are written separately and either can fail on its own.
  (princ "\nLAZICON: where the button pictures come from.")
  (princ (strcat "\n  support    : "
                 (cond ((lzp:support-dir))
                       (t "(could not read the support path)"))))
  (princ (strcat "\n  TEMPPREFIX : "
                 (if (= (type (getvar "TEMPPREFIX")) 'STR)
                     (getvar "TEMPPREFIX") "(not a string)")))
  (foreach spec (lzp:tb-specs) (lzp:icon-report spec))
  (if (not (lzp:suite-wanted-p))
    (princ (strcat "\n\n  TYLERDRONESUITE has no button here, so no"
                   " picture is drawn for it."
                   "\n  LAZBUTTON says which of the two reasons it is.")))
  (princ))

;; One button's picture, start to finish.
(defun lzp:icon-report (spec / paths tb btn r w)
  (princ (strcat "\n\n  [" (lzp:tb-name spec) "] -> " (lzp:tb-cmd spec)))
  (setq paths (lzp:write-bmps (lzp:tb-stem spec)
                              (lzp:tb-16 spec) (lzp:tb-32 spec)))
  (cond
    (paths
     (princ (strcat "\n  written to : "
                    (if lzp:*icondir* lzp:*icondir* "?")))
     (princ (strcat "\n  route      : "
                    (if lzp:*iconroute* lzp:*iconroute* "?")
                    "  (" (if lzp:*icontype* lzp:*icontype* "?") ")"))
     (princ (strcat "\n  handed on  : " (car paths)
                    (if (= lzp:*iconref* "name")
                        "  (a name the support path resolves)"
                        "  (a full path - the fallback)")))
     ;; the CUI's own test, run here: a bitmap is resolved by findfile
     ;; along the support path, and a name findfile cannot resolve is
     ;; exactly the "?" placeholder on the button
     (princ (strcat "\n  findfile   : "
                    (cond ((findfile (car paths)))
                          (t "CANNOT RESOLVE - this is the ? placeholder"))))
     (cond
       ((not (setq tb (vl-catch-all-apply 'lzp:toolbar-find
                                          (list (lzp:tb-name spec)))))
        (princ "\n  toolbar    : not on screen - type LAZBUTTON first."))
       ((vl-catch-all-error-p tb)
        (princ (strcat "\n  toolbar    : " (vl-catch-all-error-message tb))))
       (t
        (setq btn (vl-catch-all-apply 'vla-item (list tb 0)))
        (cond
          ((vl-catch-all-error-p btn)
           (princ (strcat "\n  button     : "
                          (vl-catch-all-error-message btn))))
          (t
           (setq r (vl-catch-all-apply
                     'vla-setbitmaps
                     (list btn (car paths) (cadr paths))))
           (princ (strcat "\n  SetBitmaps : "
                          (if (vl-catch-all-error-p r)
                              (vl-catch-all-error-message r)
                              "accepted - the button should show it now"))))))))
    (t
     ;; the failure branch has to say as much as the success one, or
     ;; the next report leaves the same two questions open: which route
     ;; produced the array, and which COM call refused it
     (princ (strcat "\n  array      : "
                    (if lzp:*icontype* lzp:*icontype* "none was made")))
     (princ (strcat "\n  died at    : "
                    (if lzp:*iconstep* lzp:*iconstep* "an unnamed step")))
     ;; the MSXML route failing silently is what cost two rounds of
     ;; this; every ProgID now says what it said
     (if lzp:*msxmlwhy*
       (progn
         (princ "\n  MSXML      : every version refused it --")
         (foreach w (reverse lzp:*msxmlwhy*)
           (princ (strcat "\n               " w))))
       (princ "\n  MSXML      : carried it, so the array is not the story"))
     (princ (strcat "\n  written    : NO - "
                    (if lzp:*iconerr* lzp:*iconerr* "no reason recorded")))))
  (princ))

(defun c:LAZPANELVER ()
  (princ (strcat "\nLAZPANEL " *lazpanel-version* " (LAZPANEL.lsp) - "
                 (itoa (length (lzp:commands))) " tools on the panel across "
                 (itoa (length lzp:*groups*)) " pages, "
                 (itoa (length lzp:*pins*)) " pinned."))
  (princ))

;; Put the button up as the file loads, quietly: in a session where
;; the COM menu API is missing the panel still loads and LAZPANEL
;; still runs -- the button is a convenience, never a gate.
;; The load-time call is TAKEN OUT here and made again in
;; the edition's footer, once it has said which buttons it
;; wants.  (tools/build_drone_edition.py)
(vl-catch-all-apply 'lzp:pins-read nil)

(princ (strcat "\nLAZPANEL " *lazpanel-version*
               " loaded.  LAZPANEL opens the panel;"
               " LAZBUTTON puts its button on screen;"
               " LAZPIN edits the pinned row."))
(princ)

;;; ======================================================================
;;; >>> the edition's own footer
;;; ======================================================================

;; One button on the strip, and it is the drone's.  The
;; panel is along for the ride here -- it owns the bitmap
;; and toolbar machinery -- so it does not take a button of
;; its own; LAZPANEL still opens it if you type it.
;;
;; BOTH are stated outright, and the second one is the
;; lesson.  lzp:*suitebutton* AUTO works out whether to
;; give the suite a button by reading cal:*build-loading*,
;; which LAZPASS raises and nothing ever lowers -- so on a
;; machine that had loaded LAZPASS earlier in the session
;; (a startup suite will do it every drawing) this edition
;; read a flag left by somebody else, decided it was inside
;; the build, and put up no button at all -- having already
;; taken the panel's away.  An edition knows exactly which
;; button it wants.  It should say so, not deduce it.
(setq lzp:*panelbutton* nil)
(setq lzp:*suitebutton* T)
(vl-catch-all-apply 'lzp:buttons-init nil)

;; And say so if it did not work.  A load that silently
;; leaves nothing on screen is the failure that brought
;; that bug back.
(if (vl-catch-all-apply 'lzp:toolbar-find (list lzp:*tbsuite*))
  (princ "
TYLERDRONE: the orange triangle is on screen - click it to run the suite.")
  (progn
    (princ "
TYLERDRONE: the button could not be put up - the AutoCAD menu API")
    (princ "
is unavailable here.  Type TYLERDRONESUITE instead, or LAZBUTTON to retry.")))

(princ "\nTYLERDRONE edition loaded.  Type TYLERDRONESUITE (or click the orange")
(princ "\ntriangle) to run TYDRN, then PADDLE, then AUTODIM.")
(princ)
